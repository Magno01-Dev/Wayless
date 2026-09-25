--!strict
-- ServerScriptService > Services > AccountProfileService
--
-- WAYLESS Account / Character Slot canonical profile v1.5 - Cross-place safe origin validation.
--
-- PURPOSE
--   Establishes the new canonical hierarchy:
--
--     Account
--       -> account currencies / entitlements
--       -> Character Slots
--            -> permanent origin (Clan + innate Natures)
--            -> current life metadata
--
-- IMPORTANT TRANSITION RULE
--   This service does NOT replace CharacterOriginService, InventoryPersistence,
--   TechniqueLearningService, TechniqueLoadoutService, etc. yet.
--   During migration those systems remain authoritative for gameplay.
--
-- CANONICAL SLOT RULES
--   * Slot 1 is granted for free.
--   * Chuunin can grant one additional permanent slot.
--   * Jonin can grant one additional permanent slot.
--   * Purchased slots stack with progression slots.
--   * Clan + innate Natures belong to the SLOT, not to the current life.
--   * Wiping a life never changes Clan/Natures.
--   * Clan/Nature rerolls are account currencies.
--   * Rerolls may only be consumed while the slot is in Character Creation.
--   * A final death does not immediately wipe a life. It moves the slot to
--     DeadAwaitingDecision until the player chooses Revive or Wipe.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local AccountProfileService = {}

-- Cross-place safe origin dependencies.
-- Gameplay/Frontend places can provide these modules to roll new slot genetics.
-- The Afterlife place never rolls genetics, so it can load AccountProfile
-- without carrying the entire CharacterOrigin package.
local cachedOriginConfig: any? = nil
local cachedNatureDefinitions: any? = nil
local cachedClanDefinitions: any? = nil

local function getOriginConfig(): any
	if cachedOriginConfig then
		return cachedOriginConfig
	end

	local configFolder = ServerScriptService:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("CharacterOriginConfig")

	if module and module:IsA("ModuleScript") then
		cachedOriginConfig = require(module)
	else
		cachedOriginConfig = {
			EnableStudioPersistence = false,
			ThirdNatureChance = 0,
		}
	end

	return cachedOriginConfig
end

local function tryGetOriginDefinitions(): (any?, any?)
	if cachedNatureDefinitions and cachedClanDefinitions then
		return cachedNatureDefinitions, cachedClanDefinitions
	end

	local originSystem =
		ReplicatedStorage:
		FindFirstChild(
			"CharacterOriginSystem"
		)

	local shared =
		originSystem
		and originSystem:
		FindFirstChild(
			"Shared"
		)

	if not shared then
		return nil, nil
	end

	local natureModule =
		shared:
		FindFirstChild(
			"NatureDefinitions"
		)

	local clanModule =
		shared:
		FindFirstChild(
			"ClanDefinitions"
		)

	if not natureModule
		or not natureModule:IsA("ModuleScript")
		or not clanModule
		or not clanModule:IsA("ModuleScript") then

		return nil, nil
	end

	local natureOk,
		natureResult =
		pcall(
			require,
			natureModule
		)

	local clanOk,
		clanResult =
		pcall(
			require,
			clanModule
		)

	if not natureOk
		or not clanOk then

		warn(
			"[AccountProfileService] Origin definitions unavailable",
			tostring(natureResult),
			tostring(clanResult)
		)

		return nil, nil
	end

	cachedNatureDefinitions =
		natureResult

	cachedClanDefinitions =
		clanResult

	return cachedNatureDefinitions,
		cachedClanDefinitions
end

local function requireOriginDefinitions(): (any, any)
	local natureDefinitions,
		clanDefinitions =
		tryGetOriginDefinitions()

	assert(
		natureDefinitions ~= nil
			and clanDefinitions ~= nil,
		"CharacterOriginSystem/Shared definitions are required when allocating or rerolling slot genetics"
	)

	return natureDefinitions,
		clanDefinitions
end

AccountProfileService.DataVersion = 2
AccountProfileService.StoreName = "WAYLESS_AccountProfile_v1"

AccountProfileService.SlotStates = table.freeze({
	LegacyImportPending = "LegacyImportPending",
	Empty = "Empty",
	Creating = "Creating",
	Alive = "Alive",
	DeadAwaitingDecision = "DeadAwaitingDecision",
})

AccountProfileService.SlotUnlockSources = table.freeze({
	Base = "Base",
	Chuunin = "Chuunin",
	Jonin = "Jonin",
	Purchase = "Purchase",
	Admin = "Admin",
})

local AUTOSAVE_INTERVAL = 60
local store = DataStoreService:GetDataStore(AccountProfileService.StoreName)
local rng = Random.new()

local started = false
local states: {[Player]: any} = {}
local mutationLocks: {[Player]: boolean} = {}

local function persistenceEnabled(): boolean
	if RunService:IsStudio() then
		-- Gameplay keeps the existing project policy. An isolated Afterlife
		-- Studio place without CharacterOriginConfig defaults to memory-only.
		return getOriginConfig().EnableStudioPersistence == true
	end

	return true
end

local function now(): number
	return os.time()
end

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[deepClone(key)] = deepClone(child)
	end
	return result
end

local function safeNonNegativeInt(value: any, fallback: number): number
	if typeof(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge then

		return fallback
	end

	return math.max(0, math.floor(value))
end

local function isValidSlotId(slotId: any): boolean
	if typeof(slotId) ~= "string" or slotId == "" then
		return false
	end

	local numberValue = tonumber(slotId)
	return numberValue ~= nil
		and numberValue >= 1
		and numberValue == math.floor(numberValue)
end

local function profileKey(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function chooseDistinctNature(excluded: {[string]: boolean}): string
	local NatureDefinitions = select(1, requireOriginDefinitions())
	local candidates = {}

	for _, natureId in ipairs(NatureDefinitions.Order) do
		if excluded[natureId] ~= true then
			table.insert(candidates, natureId)
		end
	end

	assert(#candidates > 0, "No Nature candidates available")
	return candidates[rng:NextInteger(1, #candidates)]
end

local function chooseClan(): string
	local _, ClanDefinitions = requireOriginDefinitions()
	assert(#ClanDefinitions.Order > 0, "No Clan candidates available")
	return ClanDefinitions.Order[
	rng:NextInteger(1, #ClanDefinitions.Order)
	]
end

local function rollPermanentOrigin(): {[string]: any}
	local excluded: {[string]: boolean} = {}

	local nature1 = chooseDistinctNature(excluded)
	excluded[nature1] = true

	local nature2 = chooseDistinctNature(excluded)
	excluded[nature2] = true

	local nature3: string? = nil
	local thirdNatureChance = tonumber(getOriginConfig().ThirdNatureChance) or 0

	if rng:NextNumber() < thirdNatureChance then
		nature3 = chooseDistinctNature(excluded)
	end

	return {
		Revision = 1,
		ClanId = chooseClan(),
		Nature1Id = nature1,
		Nature2Id = nature2,
		Nature3Id = nature3,
		RolledAt = now(),
	}
end

local function sanitizePermanentOrigin(raw: any): {[string]: any}?
	if typeof(raw) ~= "table" then
		return nil
	end

	local clanId = raw.ClanId
	local nature1 = raw.Nature1Id
	local nature2 = raw.Nature2Id
	local nature3 = raw.Nature3Id

	-- Structural validation is sufficient for read-only places such as
	-- Afterlife. Those places intentionally do not carry CharacterOriginSystem.
	if typeof(clanId) ~= "string"
		or clanId == ""
		or typeof(nature1) ~= "string"
		or nature1 == ""
		or typeof(nature2) ~= "string"
		or nature2 == ""
		or nature1 == nature2 then

		return nil
	end

	if nature3 ~= nil then
		if typeof(nature3) ~= "string"
			or nature3 == ""
			or nature3 == nature1
			or nature3 == nature2 then

			nature3 = nil
		end
	end

	-- When the full CharacterOrigin package exists (World / Frontend),
	-- additionally validate against the canonical definitions.
	local NatureDefinitions,
		ClanDefinitions =
		tryGetOriginDefinitions()

	if NatureDefinitions
		and ClanDefinitions then

		if not ClanDefinitions.IsValid(
			clanId
			) then

			return nil
		end

		if not NatureDefinitions.IsValid(
			nature1
			)
				or not NatureDefinitions.IsValid(
					nature2
				) then

			return nil
		end

		if nature3 ~= nil
			and not NatureDefinitions.IsValid(
				nature3
			) then

			nature3 = nil
		end
	end

	return {
		Revision =
			safeNonNegativeInt(
				raw.Revision,
				1
			),
		ClanId = clanId,
		Nature1Id = nature1,
		Nature2Id = nature2,
		Nature3Id = nature3,
		RolledAt =
			tonumber(
				raw.RolledAt
			)
			or now(),
	}
end

local function makeBaseSlot(): {[string]: any}
	return {
		SlotId = "1",
		UnlockSource = AccountProfileService.SlotUnlockSources.Base,
		UnlockedAt = now(),

		-- Slot 1 is imported from the currently-authoritative
		-- CharacterOriginService during the migration bootstrap.
		State = AccountProfileService.SlotStates.LegacyImportPending,
		PermanentOrigin = nil,

		LifeCounter = 0,
		CurrentLife = nil,
	}
end

local function makeUnlockedSlot(slotId: string, unlockSource: string): {[string]: any}
	return {
		SlotId = slotId,
		UnlockSource = unlockSource,
		UnlockedAt = now(),
		State = AccountProfileService.SlotStates.Empty,
		PermanentOrigin = rollPermanentOrigin(),
		LifeCounter = 0,
		CurrentLife = nil,
	}
end

local function makeDefaultProfile(player: Player): {[string]: any}
	local timestamp = now()

	return {
		Version = AccountProfileService.DataVersion,
		UserId = player.UserId,
		CreatedAt = timestamp,
		UpdatedAt = timestamp,

		Currencies = {
			ClanRerolls = 0,
			NatureRerolls = 0,
			RevivalTokens = 0,
		},

		Entitlements = {
			BaseSlotGranted = true,
			ChuuninSlotGranted = false,
			JoninSlotGranted = false,
			PurchasedSlotCount = 0,
		},

		RedeemedCodes = {},

		Slots = {
			["1"] = makeBaseSlot(),
		},

		NextSlotNumber = 2,

		-- Studio/developer-only persistent QA state.
		-- Production slot selection comes from TeleportData and does not depend
		-- on this field.
		QA = {
			StudioNextSlotId = nil,
		},

		Migration = {
			LegacySlot1OriginImported = false,
			LegacySlot1LifeImported = false,
			LegacyImportedAt = nil,
		},
	}
end

local function sanitizeCurrentLife(raw: any, lifeCounter: number): {[string]: any}?
	if typeof(raw) ~= "table" then
		return nil
	end

	local lifeId = raw.LifeId
	if typeof(lifeId) ~= "string" or lifeId == "" then
		return nil
	end

	local characterId = raw.CharacterId
	if typeof(characterId) ~= "string" or characterId == "" then
		-- Existing pre-v2 lives had only LifeId. Use the same stable value as
		-- CharacterId during migration so identity remains deterministic.
		characterId = lifeId
	end

	local legacyMigrationEligible = raw.LegacyChildDataMigrationEligible
	if typeof(legacyMigrationEligible) ~= "boolean" then
		-- Every life that existed before the CharacterId/LifeId child-store
		-- migration is allowed to import its current slot-scoped data once.
		legacyMigrationEligible = true
	end

	local lifeNumber = safeNonNegativeInt(raw.LifeNumber, lifeCounter)
	if lifeNumber < 1 then
		lifeNumber = math.max(1, lifeCounter)
	end

	local state = raw.State
	if state ~= AccountProfileService.SlotStates.Alive
		and state ~= AccountProfileService.SlotStates.DeadAwaitingDecision then

		state = AccountProfileService.SlotStates.Alive
	end

	return {
		LifeId = lifeId,
		CharacterId = characterId,
		LifeNumber = lifeNumber,
		State = state,
		LegacyChildDataMigrationEligible = legacyMigrationEligible,
		CreatedAt = tonumber(raw.CreatedAt) or now(),
		FinalDeathAt = tonumber(raw.FinalDeathAt),
		RevivalCount = safeNonNegativeInt(raw.RevivalCount, 0),
		LastRevivedAt = tonumber(raw.LastRevivedAt),
		MigrationSource = typeof(raw.MigrationSource) == "string"
			and raw.MigrationSource
			or nil,
		Summary = typeof(raw.Summary) == "table"
			and deepClone(raw.Summary)
			or {},
	}
end

local function sanitizeSlot(raw: any, slotId: string): {[string]: any}?
	if typeof(raw) ~= "table" then
		return nil
	end

	local unlockSource = raw.UnlockSource
	if typeof(unlockSource) ~= "string" or unlockSource == "" then
		unlockSource = slotId == "1"
			and AccountProfileService.SlotUnlockSources.Base
			or AccountProfileService.SlotUnlockSources.Admin
	end

	local origin = sanitizePermanentOrigin(raw.PermanentOrigin)
	local lifeCounter = safeNonNegativeInt(raw.LifeCounter, 0)
	local currentLife = sanitizeCurrentLife(raw.CurrentLife, lifeCounter)

	local state = raw.State
	local validStates = AccountProfileService.SlotStates

	if state ~= validStates.LegacyImportPending
		and state ~= validStates.Empty
		and state ~= validStates.Creating
		and state ~= validStates.Alive
		and state ~= validStates.DeadAwaitingDecision then

		state = currentLife ~= nil
			and currentLife.State
			or (origin ~= nil and validStates.Empty or validStates.LegacyImportPending)
	end

	if currentLife ~= nil then
		state = currentLife.State
	elseif state == validStates.Alive
		or state == validStates.DeadAwaitingDecision then

		state = origin ~= nil
			and validStates.Empty
			or validStates.LegacyImportPending
	end

	local archivedLives =
		typeof(raw.ArchivedLives) == "table"
		and deepClone(raw.ArchivedLives)
		or {}

	return {
		SlotId = slotId,
		UnlockSource = unlockSource,
		UnlockedAt = tonumber(raw.UnlockedAt) or now(),
		State = state,
		PermanentOrigin = origin,
		LifeCounter = lifeCounter,
		CurrentLife = currentLife,
		ArchivedLives = archivedLives,
	}
end

local function sanitizeProfile(player: Player, raw: any): {[string]: any}
	if typeof(raw) ~= "table" then
		return makeDefaultProfile(player)
	end

	local profile = makeDefaultProfile(player)

	profile.CreatedAt = tonumber(raw.CreatedAt) or profile.CreatedAt
	profile.UpdatedAt = tonumber(raw.UpdatedAt) or profile.UpdatedAt

	if typeof(raw.Currencies) == "table" then
		profile.Currencies.ClanRerolls = safeNonNegativeInt(
			raw.Currencies.ClanRerolls,
			0
		)
		profile.Currencies.NatureRerolls = safeNonNegativeInt(
			raw.Currencies.NatureRerolls,
			0
		)
		profile.Currencies.RevivalTokens = safeNonNegativeInt(
			raw.Currencies.RevivalTokens,
			0
		)
	end

	if typeof(raw.Entitlements) == "table" then
		profile.Entitlements.BaseSlotGranted = true
		profile.Entitlements.ChuuninSlotGranted = raw.Entitlements.ChuuninSlotGranted == true
		profile.Entitlements.JoninSlotGranted = raw.Entitlements.JoninSlotGranted == true
		profile.Entitlements.PurchasedSlotCount = safeNonNegativeInt(
			raw.Entitlements.PurchasedSlotCount,
			0
		)
	end

	profile.RedeemedCodes = typeof(raw.RedeemedCodes) == "table"
		and deepClone(raw.RedeemedCodes)
		or {}

	profile.QA = {
		StudioNextSlotId = nil,
	}

	if typeof(raw.QA) == "table" then
		local rawStudioSlot = raw.QA.StudioNextSlotId
		if rawStudioSlot ~= nil then
			local normalizedStudioSlot = tostring(rawStudioSlot)
			if isValidSlotId(normalizedStudioSlot) then
				profile.QA.StudioNextSlotId = normalizedStudioSlot
			end
		end
	end

	profile.Slots = {}
	local highestSlot = 0

	if typeof(raw.Slots) == "table" then
		for rawSlotId, rawSlot in pairs(raw.Slots) do
			local slotId = tostring(rawSlotId)
			if isValidSlotId(slotId) then
				local sanitized = sanitizeSlot(rawSlot, slotId)
				if sanitized then
					profile.Slots[slotId] = sanitized
					highestSlot = math.max(highestSlot, tonumber(slotId) or 0)
				end
			end
		end
	end

	if profile.Slots["1"] == nil then
		profile.Slots["1"] = makeBaseSlot()
		highestSlot = math.max(highestSlot, 1)
	end

	local requestedNext = safeNonNegativeInt(raw.NextSlotNumber, highestSlot + 1)
	profile.NextSlotNumber = math.max(2, highestSlot + 1, requestedNext)

	if typeof(raw.Migration) == "table" then
		profile.Migration.LegacySlot1OriginImported =
			raw.Migration.LegacySlot1OriginImported == true
		profile.Migration.LegacySlot1LifeImported =
			raw.Migration.LegacySlot1LifeImported == true
		profile.Migration.LegacyImportedAt = tonumber(raw.Migration.LegacyImportedAt)
	end

	profile.Version = AccountProfileService.DataVersion
	profile.UserId = player.UserId

	return profile
end

local function countSlots(profile: {[string]: any}): number
	local count = 0
	for _ in pairs(profile.Slots) do
		count += 1
	end
	return count
end

local function publish(player: Player)
	local state = states[player]
	if not state then
		return
	end

	local profile = state.Profile

	player:SetAttribute("AccountProfileReady", state.Loaded and not state.LoadFailed)
	player:SetAttribute("AccountProfilePersistent", state.Persistent)
	player:SetAttribute("AccountProfileLoadFailed", state.LoadFailed)
	player:SetAttribute("AccountProfileVersion", AccountProfileService.DataVersion)

	player:SetAttribute("AccountClanRerolls", profile.Currencies.ClanRerolls)
	player:SetAttribute("AccountNatureRerolls", profile.Currencies.NatureRerolls)
	player:SetAttribute("AccountRevivalTokens", profile.Currencies.RevivalTokens)
	player:SetAttribute("AccountUnlockedSlotCount", countSlots(profile))
	player:SetAttribute("AccountNextSlotNumber", profile.NextSlotNumber)
	player:SetAttribute(
		"AccountChuuninSlotGranted",
		profile.Entitlements.ChuuninSlotGranted
	)
	player:SetAttribute(
		"AccountJoninSlotGranted",
		profile.Entitlements.JoninSlotGranted
	)
	player:SetAttribute(
		"AccountPurchasedSlotCount",
		profile.Entitlements.PurchasedSlotCount
	)

	player:SetAttribute(
		"AccountStudioNextSlotId",
		profile.QA and profile.QA.StudioNextSlotId or nil
	)

	for slotId, slot in pairs(profile.Slots) do
		local prefix = "AccountSlot_" .. slotId .. "_"
		player:SetAttribute(prefix .. "State", slot.State)
		player:SetAttribute(prefix .. "UnlockSource", slot.UnlockSource)

		local origin = slot.PermanentOrigin
		player:SetAttribute(prefix .. "ClanId", origin and origin.ClanId or nil)
		player:SetAttribute(prefix .. "Nature1Id", origin and origin.Nature1Id or nil)
		player:SetAttribute(prefix .. "Nature2Id", origin and origin.Nature2Id or nil)
		player:SetAttribute(prefix .. "Nature3Id", origin and origin.Nature3Id or nil)

		local life = slot.CurrentLife
		player:SetAttribute(prefix .. "LifeId", life and life.LifeId or nil)
		player:SetAttribute(prefix .. "CharacterId", life and life.CharacterId or nil)
		player:SetAttribute(prefix .. "LifeNumber", life and life.LifeNumber or 0)
	end
end

local function markDirty(player: Player)
	local state = states[player]
	if not state or not state.Loaded or state.LoadFailed then
		return
	end

	state.Dirty = true
	state.Profile.UpdatedAt = now()
	publish(player)
end

local function saveInternal(player: Player, reason: string): boolean
	local state = states[player]
	if not state or not state.Loaded or state.LoadFailed then
		return false
	end

	if not persistenceEnabled() then
		state.Persistent = false
		state.Dirty = false
		publish(player)
		return true
	end

	if not state.Dirty and reason == "Autosave" then
		return true
	end

	local snapshot = deepClone(state.Profile)
	local key = profileKey(player)

	local ok, err = pcall(function()
		store:UpdateAsync(key, function(_old)
			return snapshot
		end)
	end)

	if not ok then
		state.Persistent = false
		publish(player)
		warn("[AccountProfileService] SAVE FAILED", player.Name, reason, err)
		return false
	end

	state.Persistent = true
	state.Dirty = false
	publish(player)
	return true
end

local function withMutationLock(player: Player, callback: () -> (boolean, string)): (boolean, string)
	if mutationLocks[player] then
		return false, "AccountProfileBusy"
	end

	mutationLocks[player] = true

	local ok, success, reason = pcall(callback)
	mutationLocks[player] = nil

	if not ok then
		warn("[AccountProfileService] MUTATION FAILED", player.Name, success)
		return false, "AccountProfileInternalError"
	end

	return success, reason
end

function AccountProfileService.LoadPlayer(player: Player): (boolean, string)
	if states[player] then
		return true, "AlreadyLoaded"
	end

	local state = {
		Profile = makeDefaultProfile(player),
		Loaded = false,
		LoadFailed = false,
		Persistent = false,
		Dirty = false,
	}
	states[player] = state

	player:SetAttribute("AccountProfileReady", false)
	player:SetAttribute("AccountProfileLoadFailed", false)

	if persistenceEnabled() then
		local ok, raw = pcall(function()
			return store:GetAsync(profileKey(player))
		end)

		if not ok then
			state.LoadFailed = true
			state.Loaded = true
			state.Persistent = false
			player:SetAttribute("AccountProfileLoadFailed", true)
			publish(player)
			warn("[AccountProfileService] LOAD FAILED", player.Name, raw)
			return false, "LoadFailed"
		end

		state.Profile = sanitizeProfile(player, raw)
		state.Persistent = true

		if raw == nil
			or typeof(raw) ~= "table"
			or raw.Version ~= AccountProfileService.DataVersion then

			state.Dirty = true
		end
	else
		state.Profile = makeDefaultProfile(player)
		state.Persistent = false
		state.Dirty = true
	end

	state.Loaded = true
	publish(player)

	print(
		"[AccountProfileService] LOADED",
		player.Name,
		"Slots=" .. tostring(countSlots(state.Profile)),
		"Persistent=" .. tostring(state.Persistent)
	)

	return true, "Loaded"
end

function AccountProfileService.IsReady(player: Player): boolean
	local state = states[player]
	return state ~= nil
		and state.Loaded == true
		and state.LoadFailed ~= true
end

function AccountProfileService.GetSnapshot(player: Player): {[string]: any}?
	local state = states[player]
	if not state or not state.Loaded or state.LoadFailed then
		return nil
	end

	return deepClone(state.Profile)
end

function AccountProfileService.GetSlot(player: Player, slotId: string): {[string]: any}?
	local state = states[player]
	if not state or not state.Loaded or state.LoadFailed then
		return nil
	end

	local slot = state.Profile.Slots[slotId]
	return slot and deepClone(slot) or nil
end

function AccountProfileService.GetCurrentLife(
	player: Player,
	slotId: string
): {[string]: any}?
	local slot = AccountProfileService.GetSlot(player, slotId)
	if not slot or typeof(slot.CurrentLife) ~= "table" then
		return nil
	end

	return deepClone(slot.CurrentLife)
end

function AccountProfileService.SavePlayer(player: Player, reason: string?): boolean
	return saveInternal(player, reason or "Manual")
end

-- Studio-only QA preference used by CharacterSlotContextService.
-- This lives in the already-proven AccountProfile datastore so Stop -> Play
-- cannot lose the requested slot by relying on a second datastore.
function AccountProfileService.GetStudioNextSlotId(
	player: Player
): string?
	local state = states[player]
	if not state or not state.Loaded or state.LoadFailed then
		return nil
	end

	local qa = state.Profile.QA
	if typeof(qa) ~= "table" then
		return nil
	end

	local raw = qa.StudioNextSlotId
	if raw == nil then
		return nil
	end

	local slotId = tostring(raw)
	if not isValidSlotId(slotId) then
		return nil
	end

	return slotId
end

function AccountProfileService.SetStudioNextSlotId(
	player: Player,
	requestedSlotId: any
): (boolean, string)
	-- Authorization belongs to the developer-only server gateway.
	-- Do not use RunService:IsStudio() here: some Studio test modes can
	-- report differently on the server process, which made QA selection fail.
	local slotId = requestedSlotId ~= nil and tostring(requestedSlotId) or ""
	if not isValidSlotId(slotId) then
		return false, "InvalidSlotId"
	end

	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot then
			return false, "SlotNotUnlocked"
		end

		if slot.State ~= AccountProfileService.SlotStates.Alive then
			return false, "SlotNotAlive"
		end

		if typeof(slot.CurrentLife) ~= "table" then
			return false, "SlotHasNoCurrentLife"
		end

		state.Profile.QA = state.Profile.QA or {}
		state.Profile.QA.StudioNextSlotId = slotId
		markDirty(player)

		if not saveInternal(player, "SetStudioNextSlot_" .. slotId) then
			return false, "StudioPreferenceSaveFailed"
		end

		return true, "NextPlaySlotSaved"
	end)
end

function AccountProfileService.ClearStudioNextSlotId(
	player: Player
): (boolean, string)
	-- Authorization belongs to the developer-only server gateway.
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		state.Profile.QA = state.Profile.QA or {}
		state.Profile.QA.StudioNextSlotId = nil
		markDirty(player)

		if not saveInternal(player, "ClearStudioNextSlot") then
			return false, "StudioPreferenceClearFailed"
		end

		return true, "NextPlaySlotCleared"
	end)
end

-- One-time migration bridge for the current Slot 1 gameplay baseline.
-- This is intentionally idempotent.
function AccountProfileService.ImportLegacySlot1(
	player: Player,
	originData: {[string]: any}
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		if typeof(originData) ~= "table" then
			return false, "InvalidLegacyOrigin"
		end

		local importedOrigin = sanitizePermanentOrigin({
			Revision = 1,
			ClanId = originData.ClanId,
			Nature1Id = originData.Nature1Id,
			Nature2Id = originData.Nature2Id,
			Nature3Id = originData.Nature3Id,
			RolledAt = tonumber(originData.CreatedAt) or now(),
		})

		if importedOrigin == nil then
			return false, "InvalidLegacyPermanentOrigin"
		end

		local profile = state.Profile
		local slot = profile.Slots["1"]
		if not slot then
			slot = makeBaseSlot()
			profile.Slots["1"] = slot
		end

		local changed = false

		if slot.PermanentOrigin == nil then
			slot.PermanentOrigin = importedOrigin
			profile.Migration.LegacySlot1OriginImported = true
			changed = true
		end

		if slot.CurrentLife == nil then
			slot.LifeCounter = math.max(1, safeNonNegativeInt(slot.LifeCounter, 0))
			local legacyLifeId =
				"legacy_" .. tostring(player.UserId) .. "_slot_1_life_1"

			slot.CurrentLife = {
				LifeId = legacyLifeId,
				CharacterId = legacyLifeId,
				LifeNumber = slot.LifeCounter,
				State = AccountProfileService.SlotStates.Alive,
				LegacyChildDataMigrationEligible = true,
				CreatedAt = tonumber(originData.CreatedAt) or now(),
				FinalDeathAt = nil,
				RevivalCount = 0,
				LastRevivedAt = nil,
				MigrationSource = "CharacterOriginService_v1",
				Summary = {},
			}
			slot.State = AccountProfileService.SlotStates.Alive
			profile.Migration.LegacySlot1LifeImported = true
			changed = true
		end

		if changed then
			profile.Migration.LegacyImportedAt = now()
			markDirty(player)

			if not saveInternal(player, "LegacySlot1Import") then
				return false, "LegacyImportSaveFailed"
			end
		end

		return true, changed and "LegacySlot1Imported" or "AlreadyImported"
	end)
end

local function allocateSlot(profile: {[string]: any}, unlockSource: string): {[string]: any}
	local slotNumber = math.max(2, safeNonNegativeInt(profile.NextSlotNumber, 2))

	while profile.Slots[tostring(slotNumber)] ~= nil do
		slotNumber += 1
	end

	local slotId = tostring(slotNumber)
	local slot = makeUnlockedSlot(slotId, unlockSource)
	profile.Slots[slotId] = slot
	profile.NextSlotNumber = slotNumber + 1

	return slot
end

function AccountProfileService.GrantProgressionSlot(
	player: Player,
	milestone: string
): (boolean, string, string?)
	local grantedSlotId: string? = nil

	local ok, reason = withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local profile = state.Profile
		local entitlementField: string
		local source: string

		if milestone == "Chuunin" then
			entitlementField = "ChuuninSlotGranted"
			source = AccountProfileService.SlotUnlockSources.Chuunin
		elseif milestone == "Jonin" then
			entitlementField = "JoninSlotGranted"
			source = AccountProfileService.SlotUnlockSources.Jonin
		else
			return false, "InvalidProgressionMilestone"
		end

		if profile.Entitlements[entitlementField] == true then
			return false, "ProgressionSlotAlreadyGranted"
		end

		local slot = allocateSlot(profile, source)
		profile.Entitlements[entitlementField] = true
		grantedSlotId = slot.SlotId
		markDirty(player)

		if not saveInternal(player, "GrantProgressionSlot_" .. milestone) then
			return false, "ProgressionSlotSaveFailed"
		end

		return true, "ProgressionSlotGranted"
	end)

	return ok, reason, grantedSlotId
end

function AccountProfileService.GrantPurchasedSlot(player: Player): (boolean, string, string?)
	local grantedSlotId: string? = nil

	local ok, reason = withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local profile = state.Profile
		local slot = allocateSlot(
			profile,
			AccountProfileService.SlotUnlockSources.Purchase
		)

		profile.Entitlements.PurchasedSlotCount += 1
		grantedSlotId = slot.SlotId
		markDirty(player)

		if not saveInternal(player, "GrantPurchasedSlot") then
			return false, "PurchasedSlotSaveFailed"
		end

		return true, "PurchasedSlotGranted"
	end)

	return ok, reason, grantedSlotId
end

function AccountProfileService.BeginCharacterCreation(
	player: Player,
	slotId: string
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot then
			return false, "SlotNotUnlocked"
		end

		if slot.PermanentOrigin == nil then
			return false, "SlotOriginNotReady"
		end

		if slot.CurrentLife ~= nil then
			return false, "SlotAlreadyHasLife"
		end

		if slot.State ~= AccountProfileService.SlotStates.Empty
			and slot.State ~= AccountProfileService.SlotStates.Creating then

			return false, "SlotNotAvailableForCreation"
		end

		if slot.State ~= AccountProfileService.SlotStates.Creating then
			slot.State = AccountProfileService.SlotStates.Creating
			markDirty(player)

			if not saveInternal(player, "BeginCharacterCreation") then
				return false, "CreationStateSaveFailed"
			end
		end

		return true, "CharacterCreationReady"
	end)
end

-- The reroll methods are deliberately NOT implemented yet.
-- Currency exists now, but consumption will be added only when the exact
-- clan/nature spin rules and Frontend creation flow are implemented.
-- This prevents accidental live-character rerolls during migration.

function AccountProfileService.MarkFinalDeath(
	player: Player,
	slotId: string
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot or not slot.CurrentLife then
			return false, "NoCurrentLife"
		end

		if slot.State ~= AccountProfileService.SlotStates.Alive then
			return false, "LifeNotAlive"
		end

		slot.State = AccountProfileService.SlotStates.DeadAwaitingDecision
		slot.CurrentLife.State = AccountProfileService.SlotStates.DeadAwaitingDecision
		slot.CurrentLife.FinalDeathAt = now()
		markDirty(player)

		if not saveInternal(player, "MarkFinalDeath") then
			return false, "FinalDeathStateSaveFailed"
		end

		return true, "DeadAwaitingDecision"
	end)
end

function AccountProfileService.ReviveCurrentLife(
	player: Player,
	slotId: string
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot or not slot.CurrentLife then
			return false, "NoCurrentLife"
		end

		if slot.State ~= AccountProfileService.SlotStates.DeadAwaitingDecision then
			return false, "LifeNotAwaitingDecision"
		end

		slot.State = AccountProfileService.SlotStates.Alive
		slot.CurrentLife.State = AccountProfileService.SlotStates.Alive
		slot.CurrentLife.RevivalCount = safeNonNegativeInt(
			slot.CurrentLife.RevivalCount,
			0
		) + 1
		slot.CurrentLife.LastRevivedAt = now()
		slot.CurrentLife.FinalDeathAt = nil
		markDirty(player)

		if not saveInternal(player, "ReviveCurrentLife") then
			return false, "ReviveStateSaveFailed"
		end

		return true, "LifeRevived"
	end)
end

function AccountProfileService.ReviveCurrentLifeWithToken(
	player: Player,
	slotId: string
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot or not slot.CurrentLife then
			return false, "NoCurrentLife"
		end

		if slot.State ~= AccountProfileService.SlotStates.DeadAwaitingDecision then
			return false, "LifeNotAwaitingDecision"
		end

		local tokens =
			safeNonNegativeInt(
				state.Profile.Currencies.RevivalTokens,
				0
			)

		if tokens < 1 then
			return false, "NoRevivalTokens"
		end

		local oldTokens = tokens
		local oldState = slot.State
		local oldLifeState = slot.CurrentLife.State
		local oldRevivalCount = slot.CurrentLife.RevivalCount
		local oldLastRevivedAt = slot.CurrentLife.LastRevivedAt
		local oldFinalDeathAt = slot.CurrentLife.FinalDeathAt

		state.Profile.Currencies.RevivalTokens = tokens - 1
		slot.State = AccountProfileService.SlotStates.Alive
		slot.CurrentLife.State = AccountProfileService.SlotStates.Alive
		slot.CurrentLife.RevivalCount =
			safeNonNegativeInt(
				slot.CurrentLife.RevivalCount,
				0
			) + 1
		slot.CurrentLife.LastRevivedAt = now()
		slot.CurrentLife.FinalDeathAt = nil

		markDirty(player)

		if not saveInternal(player, "ReviveCurrentLifeWithToken") then
			-- Roll back in memory. The failed save did not commit the snapshot.
			state.Profile.Currencies.RevivalTokens = oldTokens
			slot.State = oldState
			slot.CurrentLife.State = oldLifeState
			slot.CurrentLife.RevivalCount = oldRevivalCount
			slot.CurrentLife.LastRevivedAt = oldLastRevivedAt
			slot.CurrentLife.FinalDeathAt = oldFinalDeathAt
			markDirty(player)

			return false, "ReviveTokenSaveFailed"
		end

		return true, "LifeRevivedWithToken"
	end)
end

-- Metadata-only final wipe.
-- Child stores are LifeId-scoped. Finalizing the wipe detaches CurrentLife
-- but intentionally does NOT delete old LifeId data; it remains archived.
function AccountProfileService.FinalizeWipeMetadata(
	player: Player,
	slotId: string
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot or not slot.CurrentLife then
			return false, "NoCurrentLife"
		end

		if slot.State ~= AccountProfileService.SlotStates.DeadAwaitingDecision then
			return false, "LifeNotAwaitingDecision"
		end

		-- PermanentOrigin is intentionally preserved.
		-- Keep a metadata reference to the old LifeId/CharacterId so future
		-- Memorial/Legacy systems can still locate archived child-store data.
		local archivedLife =
			deepClone(
				slot.CurrentLife
			)

		archivedLife.ArchivedAt = now()
		archivedLife.ArchiveReason = "FinalWipe"

		slot.ArchivedLives =
			typeof(slot.ArchivedLives) == "table"
			and slot.ArchivedLives
			or {}

		local archiveKey =
			tostring(
				archivedLife.LifeId
				or ("life_" .. tostring(slot.LifeCounter))
			)

		slot.ArchivedLives[archiveKey] =
			archivedLife

		slot.CurrentLife = nil
		slot.State = AccountProfileService.SlotStates.Empty
		markDirty(player)

		if not saveInternal(player, "FinalizeWipeMetadata") then
			return false, "WipeMetadataSaveFailed"
		end

		return true, "SlotReadyForNewLife"
	end)
end

-- Creates only the account-level life metadata. The actual Character Creation
-- service will later validate name/appearance/village and initialize the
-- character-specific DataStores before calling this transition.
function AccountProfileService.CommitNewLifeMetadata(
	player: Player,
	slotId: string,
	summary: {[string]: any}?
): (boolean, string, string?)
	local createdLifeId: string? = nil

	local ok, reason = withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		local slot = state.Profile.Slots[slotId]
		if not slot then
			return false, "SlotNotUnlocked"
		end

		if slot.PermanentOrigin == nil then
			return false, "SlotOriginNotReady"
		end

		if slot.State ~= AccountProfileService.SlotStates.Creating then
			return false, "SlotNotInCreation"
		end

		if slot.CurrentLife ~= nil then
			return false, "SlotAlreadyHasLife"
		end

		slot.LifeCounter = safeNonNegativeInt(slot.LifeCounter, 0) + 1
		createdLifeId = HttpService:GenerateGUID(false)
		local createdCharacterId = HttpService:GenerateGUID(false)

		slot.CurrentLife = {
			LifeId = createdLifeId,
			CharacterId = createdCharacterId,
			LifeNumber = slot.LifeCounter,
			State = AccountProfileService.SlotStates.Alive,
			LegacyChildDataMigrationEligible = false,
			CreatedAt = now(),
			FinalDeathAt = nil,
			RevivalCount = 0,
			LastRevivedAt = nil,
			MigrationSource = nil,
			Summary = typeof(summary) == "table" and deepClone(summary) or {},
		}
		slot.State = AccountProfileService.SlotStates.Alive
		markDirty(player)

		if not saveInternal(player, "CommitNewLifeMetadata") then
			return false, "NewLifeMetadataSaveFailed"
		end

		return true, "NewLifeMetadataCommitted"
	end)

	return ok, reason, createdLifeId
end

function AccountProfileService.GrantCurrency(
	player: Player,
	currencyId: string,
	amount: number
): (boolean, string)
	return withMutationLock(player, function()
		local state = states[player]
		if not state or not state.Loaded or state.LoadFailed then
			return false, "AccountProfileNotReady"
		end

		if typeof(amount) ~= "number"
			or amount ~= amount
			or amount <= 0
			or amount ~= math.floor(amount) then

			return false, "InvalidAmount"
		end

		local field: string
		if currencyId == "ClanRerolls" then
			field = "ClanRerolls"
		elseif currencyId == "NatureRerolls" then
			field = "NatureRerolls"
		elseif currencyId == "RevivalTokens" then
			field = "RevivalTokens"
		else
			return false, "UnknownCurrency"
		end

		state.Profile.Currencies[field] += amount
		markDirty(player)

		if not saveInternal(player, "GrantCurrency_" .. field) then
			return false, "CurrencySaveFailed"
		end

		return true, "CurrencyGranted"
	end)
end

function AccountProfileService.UnloadPlayer(player: Player)
	local state = states[player]
	if state and state.Loaded and not state.LoadFailed then
		saveInternal(player, "PlayerRemoving")
	end

	states[player] = nil
	mutationLocks[player] = nil
end

function AccountProfileService.Start()
	if started then
		return
	end
	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			AccountProfileService.LoadPlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			AccountProfileService.LoadPlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		AccountProfileService.UnloadPlayer(player)
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)

			for player, state in pairs(states) do
				if player.Parent
					and state.Loaded
					and not state.LoadFailed
					and state.Dirty then

					task.spawn(function()
						saveInternal(player, "Autosave")
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		for player, state in pairs(states) do
			if state.Loaded and not state.LoadFailed then
				saveInternal(player, "BindToClose")
			end
		end
	end)

	print(
		"[AccountProfileService] READY v1.5"
			.. " | CanonicalAccountSlots=ON"
			.. " | CharacterIdentity=CharacterId+LifeId"
			.. " | Store=" .. AccountProfileService.StoreName
	)
end

return AccountProfileService
