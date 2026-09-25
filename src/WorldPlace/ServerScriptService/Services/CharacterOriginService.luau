--!strict
-- ServerScriptService > Services > CharacterOriginService
-- WAYLESS v1.6 Character Creation bridge: seeds village/primary nature from life summary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(
	ServerScriptService:WaitForChild("Config"):WaitForChild("CharacterOriginConfig")
)

local CharacterSlotContextService =
	require(
		ServerScriptService:
		WaitForChild(
			"Services"
		):
		WaitForChild(
			"CharacterSlotContextService"
		)
	)

local AccountProfileService =
	require(
		ServerScriptService:
		WaitForChild(
			"Services"
		):
		WaitForChild(
			"AccountProfileService"
		)
	)

local CharacterLifeContextService =
	require(
		ServerScriptService:
		WaitForChild(
			"Services"
		):
		WaitForChild(
			"CharacterLifeContextService"
		)
	)

local originSystem = ReplicatedStorage:WaitForChild("CharacterOriginSystem")
local shared = originSystem:WaitForChild("Shared")

local NatureDefinitions = require(shared:WaitForChild("NatureDefinitions"))
local VillageDefinitions = require(shared:WaitForChild("VillageDefinitions"))
local ClanDefinitions = require(shared:WaitForChild("ClanDefinitions"))

local CharacterOriginService = {}
local rng = Random.new()
local store = DataStoreService:GetDataStore(Config.DataStoreName)

local states = {}

local function persistenceEnabled(): boolean
	if RunService:IsStudio() then
		return Config.EnableStudioPersistence == true
	end
	return true
end

local function resolveSlotId(
	player: Player
): string
	local slotId =
		CharacterSlotContextService
		.GetActiveSlotId(
			player
		)

	-- Preserve the existing CharacterOriginConfig compatibility contract.
	if player:GetAttribute(
		Config.SlotAttributeName
		) ~= slotId then

		player:SetAttribute(
			Config.SlotAttributeName,
			slotId
		)
	end

	return slotId
end

local function makeKey(player: Player, slotId: string): string
	return string.format("Player_%d_Slot_%s", player.UserId, slotId)
end

local function chooseDistinct(excluded: {[string]: boolean}): string
	local candidates = {}
	for _, natureId in ipairs(NatureDefinitions.Order) do
		if excluded[natureId] ~= true then
			table.insert(candidates, natureId)
		end
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function chooseClan(): string
	return ClanDefinitions.Order[
	rng:NextInteger(
		1,
		#ClanDefinitions.Order
	)
	]
end

local function getCanonicalPermanentOrigin(
	player: Player,
	slotId: string
): {[string]: any}?
	if not AccountProfileService.IsReady(player) then
		return nil
	end

	local slot = AccountProfileService.GetSlot(player, slotId)
	if not slot or typeof(slot.PermanentOrigin) ~= "table" then
		return nil
	end

	return slot.PermanentOrigin
end

local function getCreationSummary(
	player: Player,
	slotId: string,
	lifeId: string
): {[string]: any}?
	if not AccountProfileService.IsReady(
		player
		) then

		return nil
	end

	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot
		or typeof(slot.CurrentLife) ~= "table"
		or tostring(
			slot.CurrentLife.LifeId
		) ~= lifeId
			or typeof(
				slot.CurrentLife.Summary
			) ~= "table" then

		return nil
	end

	return slot.CurrentLife.Summary
end

local function applyCreationSummary(
	data: {[string]: any},
	summary: any
): boolean
	if typeof(summary) ~= "table" then
		return false
	end

	local changed = false

	local villageId =
		summary.VillageId

	if data.OriginVillageId == nil
		and typeof(villageId) == "string"
		and VillageDefinitions.IsValid(
			villageId
		) then

		data.OriginVillageId =
			villageId

		data.AffiliationVillageId =
			villageId

		data.IsRogue = false
		changed = true
	end

	local primaryNatureId =
		summary.PrimaryNatureId

	local validPrimary =
		typeof(primaryNatureId) == "string"
		and (
			primaryNatureId == data.Nature1Id
			or primaryNatureId == data.Nature2Id
			or primaryNatureId == data.Nature3Id
		)

	if data.PrimaryNatureId == nil
		and validPrimary then

		data.PrimaryNatureId =
			primaryNatureId

		data.UnlockedNatures[
		primaryNatureId
		] = true

		changed = true
	end

	return changed
end

local function generateData(
	slotId: string,
	permanentOrigin: any?,
	lifeId: string?,
	characterId: string?,
	preservedKGRoll: number?
)
	local n1: string
	local n2: string
	local n3: string?
	local clanId: string

	if typeof(permanentOrigin) == "table"
		and NatureDefinitions.IsValid(permanentOrigin.Nature1Id)
		and NatureDefinitions.IsValid(permanentOrigin.Nature2Id)
		and permanentOrigin.Nature1Id ~= permanentOrigin.Nature2Id
		and ClanDefinitions.IsValid(permanentOrigin.ClanId) then

		n1 = permanentOrigin.Nature1Id
		n2 = permanentOrigin.Nature2Id
		n3 = permanentOrigin.Nature3Id
		clanId = permanentOrigin.ClanId
	else
		local excluded = {}
		n1 = chooseDistinct(excluded)
		excluded[n1] = true
		n2 = chooseDistinct(excluded)
		excluded[n2] = true

		n3 = nil
		if rng:NextNumber() < Config.ThirdNatureChance then
			n3 = chooseDistinct(excluded)
		end

		clanId = chooseClan()
	end

	local kgRoll = preservedKGRoll
	if typeof(kgRoll) ~= "number"
		or kgRoll < 0
		or kgRoll >= 1 then

		kgRoll = rng:NextNumber()
	end

	local nowUnix = os.time()
	return {
		Version = Config.DataVersion,
		SlotId = slotId,
		LifeId = lifeId,
		CharacterId = characterId,
		Nature1Id = n1,
		Nature2Id = n2,
		Nature3Id = n3,
		PrimaryNatureId = nil,
		UnlockedNatures = {},
		OriginVillageId = nil,
		AffiliationVillageId = nil,
		IsRogue = false,
		ClanId = clanId,
		NaturalKGPotentialRoll = kgRoll,
		CreatedAt = nowUnix,
		UpdatedAt = nowUnix,
	}
end

local function applyCanonicalPermanentOrigin(
	data: {[string]: any},
	permanentOrigin: any
): boolean
	if typeof(permanentOrigin) ~= "table" then
		return false
	end

	if not ClanDefinitions.IsValid(permanentOrigin.ClanId)
		or not NatureDefinitions.IsValid(permanentOrigin.Nature1Id)
		or not NatureDefinitions.IsValid(permanentOrigin.Nature2Id) then
		return false
	end

	local changed = false
	local fields = { "ClanId", "Nature1Id", "Nature2Id", "Nature3Id" }
	for _, field in ipairs(fields) do
		if data[field] ~= permanentOrigin[field] then
			data[field] = permanentOrigin[field]
			changed = true
		end
	end

	if changed then
		-- A changed permanent origin invalidates a previous primary selection if
		-- it is no longer one of the slot's innate natures.
		local primary = data.PrimaryNatureId
		if primary ~= nil
			and primary ~= data.Nature1Id
			and primary ~= data.Nature2Id
			and primary ~= data.Nature3Id then
			data.PrimaryNatureId = nil
		end
	end

	return changed
end

local function sanitize(raw: any, slotId: string)
	if typeof(raw) ~= "table" then
		return nil
	end

	local n1 = raw.Nature1Id
	local n2 = raw.Nature2Id
	local n3 = raw.Nature3Id

	if not NatureDefinitions.IsValid(n1) or not NatureDefinitions.IsValid(n2) or n1 == n2 then
		return nil
	end

	if n3 ~= nil then
		if not NatureDefinitions.IsValid(n3) or n3 == n1 or n3 == n2 then
			n3 = nil
		end
	end

	local primary = raw.PrimaryNatureId
	if primary ~= nil and primary ~= n1 and primary ~= n2 then
		primary = nil
	end

	-- v1 -> v1.1 migration.
	-- Old records used one VillageId for both origin and affiliation.
	local originVillage = raw.OriginVillageId
	if originVillage == nil then
		originVillage = raw.VillageId
	end
	if originVillage ~= nil and not VillageDefinitions.IsValid(originVillage) then
		originVillage = nil
	end

	local isRogue = raw.IsRogue == true

	local affiliationVillage = raw.AffiliationVillageId
	if affiliationVillage == nil and not isRogue then
		affiliationVillage = raw.VillageId or originVillage
	end
	if affiliationVillage ~= nil and not VillageDefinitions.IsValid(affiliationVillage) then
		affiliationVillage = nil
	end
	if isRogue then
		affiliationVillage = nil
	end

	local unlocked = {}
	if typeof(raw.UnlockedNatures) == "table" then
		for natureId, value in pairs(raw.UnlockedNatures) do
			if value == true and (natureId == n1 or natureId == n2 or natureId == n3) then
				unlocked[natureId] = true
			end
		end
	end

	if primary then
		unlocked[primary] = true
	end

	local clanId = raw.ClanId
	local migratedClan = false

	if not ClanDefinitions.IsValid(
		clanId
		) then
		clanId = chooseClan()
		migratedClan = true
	end

	local kgRoll = tonumber(raw.NaturalKGPotentialRoll)
	local migratedKGRoll = false

	if kgRoll == nil or kgRoll < 0 or kgRoll >= 1 then
		kgRoll = rng:NextNumber()
		migratedKGRoll = true
	end

	local sanitized = {
		Version = Config.DataVersion,
		SlotId = slotId,
		LifeId =
			typeof(raw.LifeId) == "string"
			and raw.LifeId ~= ""
			and raw.LifeId
			or nil,
		CharacterId =
			typeof(raw.CharacterId) == "string"
			and raw.CharacterId ~= ""
			and raw.CharacterId
			or nil,
		Nature1Id = n1,
		Nature2Id = n2,
		Nature3Id = n3,
		PrimaryNatureId = primary,
		UnlockedNatures = unlocked,
		OriginVillageId = originVillage,
		AffiliationVillageId = affiliationVillage,
		IsRogue = isRogue,
		ClanId = clanId,
		NaturalKGPotentialRoll = kgRoll,
		CreatedAt = tonumber(raw.CreatedAt) or os.time(),
		UpdatedAt = tonumber(raw.UpdatedAt) or os.time(),
	}

	return sanitized,
		migratedClan
		or migratedKGRoll
end

local function getNaturalKGIdFromData(
	data: any
): string?
	local innate = {
		data.Nature1Id,
		data.Nature2Id,
	}

	if data.Nature3Id then
		table.insert(
			innate,
			data.Nature3Id
		)
	end

	for i = 1, #innate do
		for j = i + 1, #innate do
			local pair = {
				innate[i],
				innate[j],
			}

			table.sort(pair)

			local key =
				pair[1]
				.. "+"
				.. pair[2]

			local configured =
				Config.ElementalKGCombinations[
			key
			]

			if typeof(configured) ==
				"string" then

				return configured

			elseif typeof(configured) ==
				"table"
				and typeof(
					configured.Id
				) == "string" then

				return configured.Id
			end
		end
	end

	return nil
end

local function hasNaturalKGPotentialFromData(
	data: any
): boolean
	return data.NaturalKGPotentialRoll
		< Config.NaturalKGPotentialChance
end

local function publish(player: Player)
	local state = states[player]
	if not state then
		return
	end

	local data = state.Data
	player:SetAttribute("CharacterOriginReady", state.Loaded)
	player:SetAttribute("CharacterOriginPersistent", state.Persistent)
	player:SetAttribute("CharacterOriginSlotId", data.SlotId)
	player:SetAttribute("CharacterOriginLifeId", data.LifeId)
	player:SetAttribute("CharacterOriginCharacterId", data.CharacterId)
	player:SetAttribute("OriginVillageId", data.OriginVillageId)
	player:SetAttribute("AffiliationVillageId", data.AffiliationVillageId)
	player:SetAttribute("IsRogue", data.IsRogue)

	-- Compatibility mirror for old UI/callers.
	-- New systems should use AffiliationVillageId/VillageService.
	player:SetAttribute("VillageId", data.AffiliationVillageId)

	player:SetAttribute("Nature1Id", data.Nature1Id)
	player:SetAttribute("Nature2Id", data.Nature2Id)
	player:SetAttribute("Nature3Id", data.Nature3Id)
	player:SetAttribute("PrimaryNatureId", data.PrimaryNatureId)

	local clanDefinition =
		ClanDefinitions.Get(
			data.ClanId
		)

	player:SetAttribute(
		"ClanId",
		data.ClanId
	)

	player:SetAttribute(
		"ClanDisplayName",
		clanDefinition
			and clanDefinition.DisplayName
			or data.ClanId
	)

	player:SetAttribute(
		"ClanArchetype",
		clanDefinition
			and clanDefinition.Archetype
			or nil
	)

	local kgId =
		getNaturalKGIdFromData(
			data
		)

	local kgPotentialQualified =
		hasNaturalKGPotentialFromData(
			data
		)

	local kgEligible =
		kgId ~= nil

	player:SetAttribute(
		"NaturalKGPotentialRoll",
		data.NaturalKGPotentialRoll
	)

	player:SetAttribute(
		"NaturalKGPotentialChance",
		Config.NaturalKGPotentialChance
	)

	player:SetAttribute(
		"NaturalKGPotentialQualified",
		kgPotentialQualified
	)

	player:SetAttribute(
		"NaturalKGEligible",
		kgEligible
	)

	player:SetAttribute(
		"NaturalKGAvailable",
		kgPotentialQualified
			and kgEligible
	)

	player:SetAttribute(
		"NaturalKGId",
		kgId
	)

	for _, natureId in ipairs(NatureDefinitions.Order) do
		local innate = natureId == data.Nature1Id or natureId == data.Nature2Id or natureId == data.Nature3Id
		player:SetAttribute("NatureInnate_" .. natureId, innate)
		player:SetAttribute("NatureUnlocked_" .. natureId, data.UnlockedNatures[natureId] == true)
	end
end

local function markDirty(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.Dirty = true
	state.Data.UpdatedAt = os.time()
	publish(player)
end

local function save(player: Player, reason: string): boolean
	local state = states[player]
	if not state or not state.Loaded then
		return false
	end

	if state.LoadFailed then
		warn("[CharacterOriginService] SAVE SKIPPED", player.Name, "LoadFailed", reason)
		return false
	end

	if not persistenceEnabled() then
		state.Persistent = false
		publish(player)
		return true
	end

	if not state.Dirty and reason == "Autosave" then
		return true
	end

	CharacterLifeContextService.AssertIdentity(
		player,
		state.Data.SlotId,
		state.Data.LifeId,
		"CharacterOriginService"
	)

	local snapshot = table.clone(state.Data)
	snapshot.UnlockedNatures = table.clone(state.Data.UnlockedNatures)
	local key = makeKey(player, state.Data.SlotId)

	local ok, err = pcall(function()
		store:UpdateAsync(key, function(_old)
			return snapshot
		end)
	end)

	if not ok then
		state.Persistent = false
		publish(player)
		warn("[CharacterOriginService] SAVE FAILED", player.Name, reason, err)
		return false
	end

	state.Persistent = true
	state.Dirty = false
	publish(player)
	print("[CharacterOriginService] SAVED", player.Name, "Slot=" .. state.Data.SlotId, "Reason=" .. reason)
	return true
end

function CharacterOriginService.LoadPlayer(player: Player): boolean
	if states[player] then
		return true
	end

	local slotId = resolveSlotId(player)

	CharacterLifeContextService.Start()

	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	local lifeId = identity.LifeId
	local characterId = identity.CharacterId

	CharacterLifeContextService.AssertIdentity(
		player,
		slotId,
		lifeId,
		"CharacterOriginService"
	)

	local permanentOrigin =
		getCanonicalPermanentOrigin(
			player,
			slotId
		)

	local state = {
		Data = generateData(
			slotId,
			permanentOrigin,
			lifeId,
			characterId,
			nil
		),
		Persistent = false,
		LoadFailed = false,
		Dirty = false,
		Loaded = false,
	}
	states[player] = state

	if persistenceEnabled() then
		local key = makeKey(player, slotId)
		local ok, raw = pcall(function()
			return store:GetAsync(key)
		end)

		if not ok then
			state.LoadFailed = true
			state.Persistent = false
			state.Loaded = true
			publish(player)
			warn(
				"[CharacterOriginService] LOAD FAILED; USING MEMORY ONLY",
				player.Name,
				raw
			)
			return false
		end

		local loaded,
			migrated =
			sanitize(
				raw,
				slotId
			)

		if loaded then
			state.Persistent = true

			local oldLifeId = loaded.LifeId
			local preserveLegacyLife =
				(oldLifeId == nil or oldLifeId == "")
				and identity.LegacyChildDataMigrationEligible == true

			if preserveLegacyLife then
				-- Existing current character: preserve its current
				-- village/unlocks/primary/rogue state, then bind it.
				loaded.LifeId = lifeId
				loaded.CharacterId = characterId
				state.Data = loaded
				migrated = true

				print(
					"[CharacterOriginService] LEGACY LIFE BOUND",
					player.Name,
					"Slot=" .. slotId,
					"Life=" .. lifeId
				)

			elseif oldLifeId ~= lifeId then
				-- New incarnation in the same permanent slot.
				-- Clan/Natures come from AccountProfile; KG potential is
				-- intentionally preserved as slot genetics. Life-scoped
				-- village/nature-unlock state resets.
				state.Data = generateData(
					slotId,
					permanentOrigin,
					lifeId,
					characterId,
					loaded.NaturalKGPotentialRoll
				)
				migrated = true

				print(
					"[CharacterOriginService] NEW LIFE STATE RESET",
					player.Name,
					"Slot=" .. slotId,
					"OldLife=" .. tostring(oldLifeId),
					"NewLife=" .. lifeId
				)

			else
				loaded.LifeId = lifeId
				loaded.CharacterId = characterId
				state.Data = loaded
			end

			local canonicalChanged =
				applyCanonicalPermanentOrigin(
					state.Data,
					permanentOrigin
				)

			state.Dirty =
				migrated == true
				or canonicalChanged

			if canonicalChanged then
				warn(
					"[CharacterOriginService] Permanent origin reconciled from AccountProfile",
					player.Name,
					"Slot=" .. slotId
				)
			end
		else
			state.Data = generateData(
				slotId,
				permanentOrigin,
				lifeId,
				characterId,
				nil
			)
			state.Persistent = true
			state.Dirty = true
		end
	else
		state.Persistent = false
		state.Dirty = true
	end

	local creationChanged =
		applyCreationSummary(
			state.Data,
			getCreationSummary(
				player,
				slotId,
				lifeId
			)
		)

	if creationChanged then
		state.Dirty = true

		print(
			"[CharacterOriginService] CREATION SUMMARY APPLIED",
			player.Name,
			"Slot=" .. slotId,
			"Life=" .. lifeId,
			"Village="
				.. tostring(
					state.Data.OriginVillageId
				),
			"Primary="
				.. tostring(
					state.Data.PrimaryNatureId
				)
		)
	end

	state.Loaded = true
	publish(player)

	local natures = state.Data.Nature1Id .. "+" .. state.Data.Nature2Id
	if state.Data.Nature3Id then
		natures ..= "+" .. state.Data.Nature3Id
	end

	print(
		"[CharacterOriginService] LOADED",
		player.Name,
		"Slot=" .. slotId,
		"Life=" .. lifeId,
		"Persistent=" .. tostring(state.Persistent),
		"Natures=" .. natures,
		"OriginVillage=" .. tostring(state.Data.OriginVillageId),
		"Affiliation=" .. tostring(state.Data.AffiliationVillageId),
		"Rogue=" .. tostring(state.Data.IsRogue),
		"Primary=" .. tostring(state.Data.PrimaryNatureId),
		"Clan=" .. tostring(state.Data.ClanId),
		"KGPotential="
			.. tostring(
				hasNaturalKGPotentialFromData(
					state.Data
				)
			)
	)

	if state.Dirty
		and state.Persistent then

		task.defer(function()
			if states[player]
				and states[player].Loaded then

				CharacterOriginService.SavePlayer(
					player,
					"CharacterLifeBinding"
				)
			end
		end)
	end

	return true
end

function CharacterOriginService.GetData(player: Player)
	local state = states[player]
	if not state or not state.Loaded then
		return nil
	end
	return state.Data
end

function CharacterOriginService.GetInnateNatures(player: Player): {string}
	local data = CharacterOriginService.GetData(player)
	if not data then
		return {}
	end
	local result = { data.Nature1Id, data.Nature2Id }
	if data.Nature3Id then
		table.insert(result, data.Nature3Id)
	end
	return result
end

function CharacterOriginService.HasInnateNature(player: Player, natureId: string): boolean
	local data = CharacterOriginService.GetData(player)
	if not data then
		return false
	end
	return data.Nature1Id == natureId or data.Nature2Id == natureId or data.Nature3Id == natureId
end

function CharacterOriginService.IsNatureUnlocked(player: Player, natureId: string): boolean
	local data = CharacterOriginService.GetData(player)
	return data ~= nil and data.UnlockedNatures[natureId] == true
end

function CharacterOriginService.CanUseNature(player: Player, natureId: string): boolean
	return CharacterOriginService.HasInnateNature(player, natureId)
		and CharacterOriginService.IsNatureUnlocked(player, natureId)
end

function CharacterOriginService.ChoosePrimaryNature(player: Player, natureId: string): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end
	if state.Data.PrimaryNatureId ~= nil then
		return false, "PrimaryNatureAlreadyChosen"
	end
	if natureId ~= state.Data.Nature1Id and natureId ~= state.Data.Nature2Id then
		return false, "NatureMustBeOneOfFirstTwo"
	end
	state.Data.PrimaryNatureId = natureId
	state.Data.UnlockedNatures[natureId] = true
	markDirty(player)
	return true, "PrimaryNatureChosen"
end

function CharacterOriginService.UnlockNature(player: Player, natureId: string): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end
	if not CharacterOriginService.HasInnateNature(player, natureId) then
		return false, "NotInnateNature"
	end
	if state.Data.UnlockedNatures[natureId] == true then
		return true, "AlreadyUnlocked"
	end
	state.Data.UnlockedNatures[natureId] = true
	markDirty(player)
	return true, "NatureUnlocked"
end

function CharacterOriginService.ChooseVillage(player: Player, villageId: string): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end
	if not VillageDefinitions.IsValid(villageId) then
		return false, "InvalidVillage"
	end
	if state.Data.OriginVillageId ~= nil then
		return false, "VillageAlreadyChosen"
	end

	state.Data.OriginVillageId = villageId
	state.Data.AffiliationVillageId = villageId
	state.Data.IsRogue = false

	markDirty(player)
	return true, "VillageChosen"
end

function CharacterOriginService.GetOriginVillage(player: Player): string?
	local data = CharacterOriginService.GetData(player)
	return data and data.OriginVillageId or nil
end

function CharacterOriginService.GetAffiliationVillage(player: Player): string?
	local data = CharacterOriginService.GetData(player)
	return data and data.AffiliationVillageId or nil
end

-- Compatibility: Village means CURRENT affiliation.
function CharacterOriginService.GetVillage(player: Player): string?
	return CharacterOriginService.GetAffiliationVillage(player)
end

function CharacterOriginService.IsRogue(player: Player): boolean
	local data = CharacterOriginService.GetData(player)
	return data ~= nil and data.IsRogue == true
end

function CharacterOriginService.SetVillageAffiliation(
	player: Player,
	villageId: string?
): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end

	if villageId ~= nil and not VillageDefinitions.IsValid(villageId) then
		return false, "InvalidVillage"
	end

	state.Data.AffiliationVillageId = villageId

	if villageId ~= nil then
		state.Data.IsRogue = false
	end

	markDirty(player)
	return true, "VillageAffiliationSet"
end

function CharacterOriginService.SetRogueStatus(
	player: Player,
	isRogue: boolean
): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end

	if typeof(isRogue) ~= "boolean" then
		return false, "InvalidRogueStatus"
	end

	state.Data.IsRogue = isRogue

	if isRogue then
		state.Data.AffiliationVillageId = nil
	elseif state.Data.AffiliationVillageId == nil then
		-- QA/future default. Real re-affiliation rules can override this later.
		state.Data.AffiliationVillageId = state.Data.OriginVillageId
	end

	markDirty(player)
	return true, "RogueStatusSet"
end

function CharacterOriginService.GetClan(
	player: Player
): string?
	local data =
		CharacterOriginService.GetData(
			player
		)

	return data
		and data.ClanId
		or nil
end

function CharacterOriginService.GetNaturalKGPotentialRoll(
	player: Player
): number?
	local data =
		CharacterOriginService.GetData(
			player
		)

	return data
		and data.NaturalKGPotentialRoll
		or nil
end

-- "Potential" is the genetic roll only.
-- It does NOT mean the character currently owns/expresses a KG.
function CharacterOriginService.HasNaturalKGPotential(
	player: Player
): boolean
	local data =
		CharacterOriginService.GetData(
			player
		)

	return data ~= nil
		and hasNaturalKGPotentialFromData(
			data
		)
end

function CharacterOriginService.GetNaturalKGId(
	player: Player
): string?
	local data =
		CharacterOriginService.GetData(
			player
		)

	if not data then
		return nil
	end

	return getNaturalKGIdFromData(
		data
	)
end

function CharacterOriginService.IsNaturalKGEligible(
	player: Player
): boolean
	return CharacterOriginService.GetNaturalKGId(
		player
	) ~= nil
end

function CharacterOriginService.HasNaturalKGAvailable(
	player: Player
): boolean
	return CharacterOriginService.HasNaturalKGPotential(
		player
	)
		and CharacterOriginService.IsNaturalKGEligible(
			player
		)
end

-- Deprecated compatibility hook.
-- Genetics are slot-persistent. A wipe/new life must NOT reroll this value.
function CharacterOriginService.RerollNaturalKGPotentialForNewLife(
	player: Player
): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end

	return true,
		"NaturalKGPotentialPreservedBySlot"
end

-- Developer QA helpers.
function CharacterOriginService.DevSetClan(
	player: Player,
	clanId: string
): (boolean, string)
	if not ClanDefinitions.IsValid(
		clanId
		) then
		return false, "InvalidClan"
	end

	local state = states[player]

	if not state
		or not state.Loaded then

		return false,
			"OriginNotReady"
	end

	state.Data.ClanId =
		clanId

	markDirty(player)

	return true,
		"DevClanSet"
end

function CharacterOriginService.DevRandomizeClan(
	player: Player
): (boolean, string)
	local state = states[player]

	if not state
		or not state.Loaded then

		return false,
			"OriginNotReady"
	end

	state.Data.ClanId =
		chooseClan()

	markDirty(player)

	return true,
		"DevClanRandomized"
end

function CharacterOriginService.DevForceNaturalKGPotential(
	player: Player,
	qualified: boolean
): (boolean, string)
	local state = states[player]

	if not state
		or not state.Loaded then

		return false,
			"OriginNotReady"
	end

	if qualified then
		state.Data.NaturalKGPotentialRoll =
			math.max(
				0,
				Config.NaturalKGPotentialChance
				* 0.5
			)
	else
		state.Data.NaturalKGPotentialRoll =
			math.min(
				0.999999,
				Config.NaturalKGPotentialChance
				+ (
					1
					- Config.NaturalKGPotentialChance
				) * 0.5
			)
	end

	markDirty(player)

	return true,
		qualified
		and "DevKGPotentialQualified"
		or "DevKGPotentialNotQualified"
end

function CharacterOriginService.DevSetVillage(player: Player, villageId: string?): (boolean, string)
	if villageId ~= nil and not VillageDefinitions.IsValid(villageId) then
		return false, "InvalidVillage"
	end
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end
	state.Data.OriginVillageId = villageId
	state.Data.AffiliationVillageId = villageId
	state.Data.IsRogue = false

	markDirty(player)
	return true, "DevVillageSet"
end

function CharacterOriginService.DevSetPrimaryNature(player: Player, natureId: string?): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end
	if natureId ~= nil and natureId ~= state.Data.Nature1Id and natureId ~= state.Data.Nature2Id then
		return false, "NatureMustBeOneOfFirstTwo"
	end
	state.Data.PrimaryNatureId = natureId
	if natureId then
		state.Data.UnlockedNatures[natureId] = true
	end
	markDirty(player)
	return true, "DevPrimaryNatureSet"
end

function CharacterOriginService.DevRegenerateGenetics(player: Player): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "OriginNotReady"
	end
	local originVillage = state.Data.OriginVillageId
	local affiliationVillage = state.Data.AffiliationVillageId
	local isRogue = state.Data.IsRogue

	local slotId = state.Data.SlotId
	local lifeId = state.Data.LifeId
	local characterId = state.Data.CharacterId

	state.Data = generateData(
		slotId,
		nil,
		lifeId,
		characterId,
		nil
	)

	state.Data.OriginVillageId = originVillage
	state.Data.AffiliationVillageId = affiliationVillage
	state.Data.IsRogue = isRogue

	markDirty(player)
	return true, "DevGeneticsRegenerated"
end

function CharacterOriginService.SavePlayer(player: Player, reason: string?): boolean
	return save(player, reason or "Manual")
end

function CharacterOriginService.UnloadPlayer(player: Player)
	save(player, "PlayerRemoving")
	states[player] = nil
end

task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		for player in pairs(states) do
			if player.Parent == Players then
				save(player, "Autosave")
			end
		end
	end
end)

game:BindToClose(function()
	for player in pairs(states) do
		save(player, "BindToClose")
	end
end)

print(
	"[CharacterOriginService] READY v1.6 CharacterCreation+ClanKGPotential"
		.. " | Store=" .. Config.DataStoreName
		.. " | StudioPersistence=" .. tostring(Config.EnableStudioPersistence)
		.. " | ThirdNatureChance=" .. tostring(Config.ThirdNatureChance)
		.. " | NaturalKGPotentialChance=" .. tostring(Config.NaturalKGPotentialChance)
		.. " | Clans=" .. tostring(#ClanDefinitions.Order)
		.. " | ClanBonuses=OFF"
		.. " | SlotContext=ON"
		.. " | CharacterLife=ON"
		.. " | SlotMode="
		.. CharacterSlotContextService.GetMode()
		.. " | NaturalKGDefinitions="
		.. tostring(
			next(
				Config.ElementalKGCombinations
			) ~= nil
		)
)

return CharacterOriginService
