--!strict
-- WAYLESS
-- CharacterDataService v1.4 - Character Life scoped progression
-- Persistent per-player / per-character-slot data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local ConfigFolder = ServerScriptService:WaitForChild("Config")

local DataConfig = require(ConfigFolder:WaitForChild("CharacterDataConfig"))
local Progression = require(Services:WaitForChild("CharacterProgressionService"))
local CharacterSessionSlotGate =
	require(Services:WaitForChild("CharacterSessionSlotGate"))

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

local DeveloperAccessService =
	require(Services:WaitForChild("DeveloperAccessService"))

DeveloperAccessService.Start()

type ProgressionData = {
	Level: number,
	TotalXP: number,
}

type SlotData = {
	Progression: ProgressionData,
	LifeId: string?,
	CharacterId: string?,
	ArchivedLives: {[string]: any}?,
}

type SessionLock = {
	JobId: string,
	PlaceId: number,
	ExpiresAt: number,
}

type PlayerData = {
	SchemaVersion: number,
	ActiveSlotId: string,
	Slots: {[string]: SlotData},
	SessionLock: SessionLock?,
}

type Session = {
	Data: PlayerData,
	ActiveSlotId: string,
	LifeId: string,
	CharacterId: string,
	PersistenceEnabled: boolean,
	PersistentProgression: ProgressionData,
	DevProgressionOverride: boolean,
	Dirty: boolean,
	Closing: boolean,
}

local CharacterDataService = {}
local sessions: {[Player]: Session} = {}
local dataStore = DataStoreService:GetDataStore(DataConfig.DATASTORE_NAME)

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[deepCopy(key)] = deepCopy(child)
	end
	return result
end

local function defaultProgression(): ProgressionData
	return {Level = 1, TotalXP = 0}
end

local function defaultSlot(): SlotData
	return {
		Progression = defaultProgression(),
		LifeId = nil,
		CharacterId = nil,
		ArchivedLives = nil,
	}
end

local function defaultPlayerData(): PlayerData
	local slotId = tostring(DataConfig.DEFAULT_SLOT_ID)
	return {
		SchemaVersion = DataConfig.SCHEMA_VERSION,
		ActiveSlotId = slotId,
		Slots = {[slotId] = defaultSlot()},
		SessionLock = nil,
	}
end

local function normalizeProgression(raw: any): ProgressionData
	if typeof(raw) ~= "table" then
		return defaultProgression()
	end

	local totalXP = 0
	if typeof(raw.TotalXP) == "number" then
		totalXP = math.max(0, math.floor(raw.TotalXP))
	end

	local level = 1
	if typeof(raw.Level) == "number" then
		level = math.max(1, math.floor(raw.Level))
	end

	return {Level = level, TotalXP = totalXP}
end

local function normalizePlayerData(raw: any): PlayerData
	local data = defaultPlayerData()
	if typeof(raw) ~= "table" then
		return data
	end

	if typeof(raw.ActiveSlotId) == "string" and raw.ActiveSlotId ~= "" then
		data.ActiveSlotId = raw.ActiveSlotId
	end

	if typeof(raw.Slots) == "table" then
		data.Slots = {}
		for rawSlotId, rawSlot in pairs(raw.Slots) do
			local slotId = tostring(rawSlotId)
			if typeof(rawSlot) == "table" then
				data.Slots[slotId] = {
					Progression = normalizeProgression(rawSlot.Progression),
				}

				-- Preserve unknown/future slot fields.
				for key, value in pairs(rawSlot) do
					if key ~= "Progression" then
						(data.Slots[slotId] :: any)[key] = deepCopy(value)
					end
				end
			end
		end
	end

	if not data.Slots[data.ActiveSlotId] then
		data.Slots[data.ActiveSlotId] = defaultSlot()
	end

	if typeof(raw.SessionLock) == "table"
		and typeof(raw.SessionLock.JobId) == "string"
		and typeof(raw.SessionLock.ExpiresAt) == "number" then
		data.SessionLock = {
			JobId = raw.SessionLock.JobId,
			PlaceId = if typeof(raw.SessionLock.PlaceId) == "number" then raw.SessionLock.PlaceId else 0,
			ExpiresAt = raw.SessionLock.ExpiresAt,
		}
	end

	data.SchemaVersion = DataConfig.SCHEMA_VERSION
	return data
end

local function persistenceEnabled(): boolean
	if RunService:IsStudio() then
		return DataConfig.ENABLE_STUDIO_PERSISTENCE
	end
	return true
end

local function dataKey(player: Player): string
	return DataConfig.KEY_PREFIX .. tostring(player.UserId)
end

local function makeLock(): SessionLock
	return {
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		ExpiresAt = os.time() + DataConfig.SESSION_LOCK_LEASE_SECONDS,
	}
end

local function lockIsLiveForeign(lock: SessionLock?): boolean
	if not lock or lock.JobId == game.JobId then
		return false
	end
	return lock.ExpiresAt > os.time()
end

local function getSession(player: Player): Session
	local session = sessions[player]
	if not session then
		error(("CharacterDataService: %s has no loaded data session"):format(player.Name), 3)
	end
	return session
end

local function ensureSlot(data: PlayerData, slotId: string): SlotData
	local slot = data.Slots[slotId]
	if not slot then
		slot = defaultSlot()
		data.Slots[slotId] = slot
	end
	return slot
end

local function bindSlotToCurrentLife(
	player: Player,
	slot: SlotData,
	slotId: string
): (string, string, boolean)
	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	local lifeId = identity.LifeId
	local characterId = identity.CharacterId

	assert(
		typeof(lifeId) == "string"
			and lifeId ~= "",
		"CharacterDataService: missing LifeId"
	)

	assert(
		typeof(characterId) == "string"
			and characterId ~= "",
		"CharacterDataService: missing CharacterId"
	)

	local changed = false
	local storedLifeId = slot.LifeId

	if storedLifeId == nil or storedLifeId == "" then
		if identity.LegacyChildDataMigrationEligible == true then
			-- Existing current character: claim the old slot-scoped
			-- progression without changing it.
			slot.LifeId = lifeId
			slot.CharacterId = characterId
			changed = true

			print(
				"[CharacterDataService] LEGACY SLOT PROGRESSION BOUND",
				player.Name,
				"Slot=" .. slotId,
				"Life=" .. lifeId
			)
		else
			-- A brand-new life must never inherit anonymous slot data.
			slot.ArchivedLives =
				slot.ArchivedLives or {}

			slot.ArchivedLives[
			"legacy_slot_" .. slotId
			] = {
				Progression =
					deepCopy(
						slot.Progression
					),
				ArchivedAt = os.time(),
				Reason = "NewLifeRejectedLegacySlotData",
			}

			slot.Progression =
				defaultProgression()

			slot.LifeId = lifeId
			slot.CharacterId = characterId
			changed = true

			print(
				"[CharacterDataService] NEW LIFE PROGRESSION RESET",
				player.Name,
				"Slot=" .. slotId,
				"Life=" .. lifeId
			)
		end

	elseif storedLifeId ~= lifeId then
		-- New incarnation occupying the same permanent slot.
		slot.ArchivedLives =
			slot.ArchivedLives or {}

		slot.ArchivedLives[
		storedLifeId
		] = {
			CharacterId = slot.CharacterId,
			Progression =
				deepCopy(
					slot.Progression
				),
			ArchivedAt = os.time(),
			Reason = "LifeRotation",
		}

		slot.Progression =
			defaultProgression()

		slot.LifeId = lifeId
		slot.CharacterId = characterId
		changed = true

		print(
			"[CharacterDataService] LIFE ROTATION",
			player.Name,
			"Slot=" .. slotId,
			"OldLife=" .. storedLifeId,
			"NewLife=" .. lifeId
		)

	elseif slot.CharacterId ~= characterId then
		slot.CharacterId = characterId
		changed = true
	end

	return lifeId,
		characterId,
		changed
end

local function snapshotCurrentProgression(player: Player): ProgressionData
	local exported = Progression.ExportPlayerData(player)
	return {
		Level = exported.Level or 1,
		TotalXP = exported.TotalXP or 0,
	}
end

local function updateSessionDataForSave(session: Session)
	local slot = ensureSlot(session.Data, session.ActiveSlotId)
	slot.Progression = deepCopy(session.PersistentProgression)
	session.Data.ActiveSlotId = session.ActiveSlotId
	session.Data.SchemaVersion = DataConfig.SCHEMA_VERSION
end

local function retry(attempts: number, callback: () -> any): (boolean, any)
	local lastError = nil
	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(DataConfig.RETRY_DELAY_SECONDS * attempt)
		end
	end
	return false, lastError
end

function CharacterDataService.IsLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function CharacterDataService.GetActiveSlotId(player: Player): string
	return getSession(player).ActiveSlotId
end

function CharacterDataService.GetLifeId(player: Player): string
	return getSession(player).LifeId
end

function CharacterDataService.GetCharacterId(player: Player): string
	return getSession(player).CharacterId
end

function CharacterDataService.IsPersistenceEnabled(player: Player): boolean
	return getSession(player).PersistenceEnabled
end

function CharacterDataService.HasDevProgressionOverride(player: Player): boolean
	return getSession(player).DevProgressionOverride
end

function CharacterDataService.LoadPlayer(player: Player, requestedSlotId: string?): (boolean, string?)
	if sessions[player] then
		return true, nil
	end

	-- Canonical session slot is resolved before ANY CharacterData DataStore
	-- read/write. Legacy callers may still pass Slot 1; that value is ignored
	-- when it disagrees with the immutable session context.
	local canonicalSlotId =
		CharacterSessionSlotGate.WaitForSlot(player)

	CharacterLifeContextService.Start()
	local lifeReady =
		CharacterLifeContextService.WaitUntilReady(
			player,
			30
		)

	if not lifeReady then
		return false,
			"Character life context was not ready."
	end

	if requestedSlotId
		and requestedSlotId ~= ""
		and tostring(requestedSlotId) ~= canonicalSlotId then

		warn(
			"[CharacterDataService] LEGACY REQUESTED SLOT IGNORED",
			player.Name,
			"Requested=" .. tostring(requestedSlotId),
			"Session=" .. canonicalSlotId
		)
	end

	requestedSlotId = canonicalSlotId

	local usePersistence = persistenceEnabled()
	local data: PlayerData

	if not usePersistence then
		data = defaultPlayerData()
		if requestedSlotId and requestedSlotId ~= "" then
			data.ActiveSlotId = tostring(requestedSlotId)
			ensureSlot(data, data.ActiveSlotId)
		end
	else
		local key = dataKey(player)
		local foreignLockDetected = false
		local qaRecoveredForeignLock = false

		-- Narrow recovery path for the account-slot QA flow only.
		-- The previous v1.2 teardown race could leave a live session lock even
		-- after Team Test had already closed. A developer who has explicitly
		-- selected a Next Play slot may reclaim that orphaned QA lock.
		local allowQaLockRecovery =
			DeveloperAccessService.IsDeveloper(player)
			and player:GetAttribute("AccountStudioNextSlotId") ~= nil

		local ok, result = retry(DataConfig.LOAD_RETRIES, function()
			return dataStore:UpdateAsync(key, function(oldValue)
				local candidate = normalizePlayerData(oldValue)

				if lockIsLiveForeign(candidate.SessionLock) then
					if allowQaLockRecovery then
						qaRecoveredForeignLock = true
						foreignLockDetected = false
					else
						foreignLockDetected = true
						return nil
					end
				end

				foreignLockDetected = false

				if requestedSlotId and requestedSlotId ~= "" then
					candidate.ActiveSlotId = tostring(requestedSlotId)
				end

				ensureSlot(candidate, candidate.ActiveSlotId)
				candidate.SessionLock = makeLock()
				return candidate
			end)
		end)

		if not ok then
			return false, "DataStore load failed: " .. tostring(result)
		end

		if foreignLockDetected then
			return false, "Your character data is still active in another server. Please wait a moment and rejoin."
		end

		if result == nil then
			return false, "Character data could not be locked safely."
		end

		if qaRecoveredForeignLock then
			warn(
				"[CharacterDataService] QA ORPHAN LOCK RECOVERED",
				player.Name,
				"Slot=" .. canonicalSlotId
			)
		end

		data = normalizePlayerData(result)
	end

	-- Fail closed if normalized/stored data somehow disagrees with the
	-- session-selected character.
	data.ActiveSlotId = canonicalSlotId
	local activeSlotId = data.ActiveSlotId

	CharacterSessionSlotGate.AssertLoadedSlot(
		player,
		activeSlotId,
		"CharacterDataService"
	)

	local slot = ensureSlot(data, activeSlotId)

	local lifeId,
		characterId,
		lifeBindingChanged =
		bindSlotToCurrentLife(
			player,
			slot,
			activeSlotId
		)

	CharacterLifeContextService.AssertIdentity(
		player,
		activeSlotId,
		lifeId,
		"CharacterDataService"
	)

	local loadedSnapshot = Progression.InitializePlayer(player, slot.Progression)

	local canonicalProgression: ProgressionData = {
		Level = loadedSnapshot.Level,
		TotalXP = loadedSnapshot.TotalXP,
	}

	slot.Progression = deepCopy(canonicalProgression)

	sessions[player] = {
		Data = data,
		ActiveSlotId = activeSlotId,
		LifeId = lifeId,
		CharacterId = characterId,
		PersistenceEnabled = usePersistence,
		PersistentProgression = deepCopy(canonicalProgression),
		DevProgressionOverride = false,
		Dirty = lifeBindingChanged,
		Closing = false,
	}

	player:SetAttribute("CharacterActiveSlotId", activeSlotId)
	player:SetAttribute("CharacterDataLifeId", lifeId)
	player:SetAttribute("CharacterDataCharacterId", characterId)
	player:SetAttribute("CharacterDataPersistent", usePersistence)
	player:SetAttribute("CharacterProgressionDevOverride", false)

	if DataConfig.DEBUG then
		print(
			"[CharacterDataService] LOADED",
			player.Name,
			"Slot=" .. activeSlotId,
			"Life=" .. lifeId,
			"Persistent=" .. tostring(usePersistence),
			"Level=" .. tostring(loadedSnapshot.Level),
			"TotalXP=" .. tostring(loadedSnapshot.TotalXP)
		)
	end

	if lifeBindingChanged and usePersistence then
		task.defer(function()
			if sessions[player] then
				CharacterDataService.SavePlayer(
					player,
					"CharacterLifeBinding",
					true
				)
			end
		end)
	end

	return true, nil
end

function CharacterDataService.MarkProgressionDevOverride(player: Player)
	local session = getSession(player)
	if session.DevProgressionOverride then
		return
	end

	session.DevProgressionOverride = true
	player:SetAttribute("CharacterProgressionDevOverride", true)
end

function CharacterDataService.CommitCurrentProgression(player: Player): (boolean, string)
	local session = getSession(player)
	session.PersistentProgression = snapshotCurrentProgression(player)
	session.DevProgressionOverride = false
	session.Dirty = true
	player:SetAttribute("CharacterProgressionDevOverride", false)

	local ok, errorMessage = CharacterDataService.SavePlayer(player, "DevCommit", true)
	if ok then
		return true, "Current progression committed to persistent slot data."
	end
	return false, errorMessage or "Could not save committed progression."
end

function CharacterDataService.RestorePersistentProgression(player: Player): (boolean, string)
	local session = getSession(player)
	Progression.SetTotalXP(player, session.PersistentProgression.TotalXP, "DataRestore")
	session.DevProgressionOverride = false
	player:SetAttribute("CharacterProgressionDevOverride", false)
	return true, "Restored progression from the last persistent value."
end

function CharacterDataService.SavePlayer(player: Player, reason: string?, keepLock: boolean?): (boolean, string?)
	local session = sessions[player]
	if not session then
		return false, "No loaded data session."
	end

	-- Never save progression into a slot different from the immutable
	-- session slot.
	CharacterSessionSlotGate.AssertLoadedSlot(
		player,
		session.ActiveSlotId,
		"CharacterDataService"
	)

	CharacterLifeContextService.AssertIdentity(
		player,
		session.ActiveSlotId,
		session.LifeId,
		"CharacterDataService"
	)

	local slot =
		ensureSlot(
			session.Data,
			session.ActiveSlotId
		)

	if slot.LifeId ~= session.LifeId then
		return false,
			"Character life identity changed during session; save blocked."
	end

	updateSessionDataForSave(session)

	if not session.PersistenceEnabled then
		session.Dirty = false
		if DataConfig.DEBUG then
			print("[CharacterDataService] SAVE SKIPPED", player.Name, "Reason=" .. tostring(reason), "StudioPersistence=OFF")
		end
		return true, nil
	end

	local shouldKeepLock = if keepLock == nil then true else keepLock
	local key = dataKey(player)
	local foreignLockDetected = false
	local localData = deepCopy(session.Data)

	local ok, result = retry(DataConfig.SAVE_RETRIES, function()
		return dataStore:UpdateAsync(key, function(oldValue)
			local stored = normalizePlayerData(oldValue)

			if lockIsLiveForeign(stored.SessionLock) then
				foreignLockDetected = true
				return nil
			end

			foreignLockDetected = false
			local toWrite = deepCopy(localData)
			toWrite.SessionLock = if shouldKeepLock then makeLock() else nil
			return toWrite
		end)
	end)

	if not ok then
		warn("[CharacterDataService] SAVE FAILED", player.Name, reason, result)
		return false, "DataStore save failed: " .. tostring(result)
	end

	if foreignLockDetected or result == nil then
		warn("[CharacterDataService] SAVE BLOCKED - LOCK LOST", player.Name, reason)
		return false, "Data session lock was lost; save was blocked to protect existing data."
	end

	session.Dirty = false

	if DataConfig.DEBUG then
		print(
			"[CharacterDataService] SAVED",
			player.Name,
			"Reason=" .. tostring(reason),
			"KeepLock=" .. tostring(shouldKeepLock),
			"DevOverride=" .. tostring(session.DevProgressionOverride)
		)
	end

	return true, nil
end

function CharacterDataService.ReleasePlayer(player: Player, reason: string?)
	local session = sessions[player]
	if not session or session.Closing then
		return
	end

	session.Closing = true
	local ok, errorMessage = CharacterDataService.SavePlayer(player, reason or "Release", false)
	if not ok then
		warn("[CharacterDataService] RELEASE SAVE FAILED", player.Name, errorMessage)
	end

	Progression.ReleasePlayer(player)
	sessions[player] = nil
end

Progression.XPChanged:Connect(function(player: Player, _oldSnapshot, newSnapshot, source: string)
	local session = sessions[player]
	if not session then
		return
	end

	-- v1.1:
	-- ALL authoritative progression changes are persistent, including Dev*
	-- sources from the QA-approved ProgressionDevTools.
	--
	-- This intentionally removes the previous "temporary dev override"
	-- behavior so testers can set a level in the dev menu, leave, rejoin,
	-- and continue testing from the same saved character state.
	session.PersistentProgression = {
		Level = newSnapshot.Level,
		TotalXP = newSnapshot.TotalXP,
	}

	session.DevProgressionOverride = false
	session.Dirty = true

	player:SetAttribute(
		"CharacterProgressionDevOverride",
		false
	)

	if DataConfig.DEBUG then
		print(
			"[CharacterDataService] PROGRESSION DIRTY",
			player.Name,
			"Source=" .. tostring(source),
			"Level=" .. tostring(newSnapshot.Level),
			"TotalXP=" .. tostring(newSnapshot.TotalXP)
		)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local ok, err = pcall(function()
		CharacterDataService.ReleasePlayer(
			player,
			"PlayerRemoving"
		)
	end)

	if not ok then
		warn(
			"[CharacterDataService] PLAYER REMOVING RELEASE ERROR",
			player.Name,
			err
		)
	end
end)

task.spawn(function()
	while true do
		task.wait(DataConfig.AUTOSAVE_SECONDS)
		for player, session in pairs(sessions) do
			if player.Parent == Players and not session.Closing then
				local ok, errorMessage = CharacterDataService.SavePlayer(player, "Autosave", true)
				if not ok then
					warn("[CharacterDataService] AUTOSAVE FAILED", player.Name, errorMessage)
				end
			end
		end
	end
end)

game:BindToClose(function()
	local playersToRelease = {}
	for player in pairs(sessions) do
		table.insert(playersToRelease, player)
	end

	local remaining = #playersToRelease
	if remaining == 0 then
		return
	end

	local done = Instance.new("BindableEvent")
	local finished = 0

	for _, player in ipairs(playersToRelease) do
		task.spawn(function()
			local ok, err = pcall(function()
				CharacterDataService.ReleasePlayer(
					player,
					"BindToClose"
				)
			end)

			if not ok then
				warn(
					"[CharacterDataService] BIND TO CLOSE RELEASE ERROR",
					player.Name,
					err
				)
			end

			-- ALWAYS complete the shutdown barrier, even if a save failed.
			finished += 1
			if finished >= remaining then
				done:Fire()
			end
		end)
	end

	if finished < remaining then
		done.Event:Wait()
	end
	done:Destroy()
end)

print(
	"[CharacterDataService] READY v1.4"
		.. " | Store=" .. DataConfig.DATASTORE_NAME
		.. " | StudioPersistence=" .. tostring(DataConfig.ENABLE_STUDIO_PERSISTENCE)
		.. " | Autosave=" .. tostring(DataConfig.AUTOSAVE_SECONDS) .. "s"
)

return CharacterDataService
