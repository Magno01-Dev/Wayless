--!strict
-- ServerScriptService > Services > TechniqueLearningService
--
-- WAYLESS per-character learned-technique persistence v2.1 - Character Life short keys.
--
-- Production rule:
-- A technique must be learned before it can be cast.
--
-- Developer rule:
-- Authorized developers with DevContentBypassEnabled=true are treated as
-- knowing every registered technique automatically. Nothing needs to be
-- individually unlocked in a dev menu.
--
-- Persistence remains independent, but SlotId now comes from the canonical
-- CharacterSlotContextService so real slots can be added later without
-- changing the learned-technique datastore contract.

local DataStoreService =
	game:GetService("DataStoreService")

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local ServerScriptService =
	game:GetService("ServerScriptService")

local DeveloperAccessService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("DeveloperAccessService")
)

local CharacterSlotContextService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("CharacterSlotContextService")
)

local CharacterLifeContextService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("CharacterLifeContextService")
)

local TechniqueLearningService = {}

local STORE_NAME =
	"WAYLESS_TechniqueLearning_v1"

local AUTOSAVE_SECONDS =
	60

-- Same isolation philosophy as CharacterOrigin during Studio QA.
local ENABLE_STUDIO_PERSISTENCE =
	false

local store =
	DataStoreService:GetDataStore(
		STORE_NAME
	)

type LearnSource = {
	Type: string?,
	Id: string?,
}

type LearnedRecord = {
	LearnedAt: number,
	SourceType: string,
	SourceId: string,
}

type TechniqueData = {
	Version: number,
	Learned: {[string]: LearnedRecord},
}

type PlayerState = {
	Loaded: boolean,
	Persistent: boolean,
	LoadFailed: boolean,
	Dirty: boolean,
	SlotId: string,
	LifeId: string,
	CharacterId: string,
	Data: TechniqueData,
}

local states: {[Player]: PlayerState} = {}
local started = false

local function canPersist(): boolean
	if RunService:IsStudio() then
		return ENABLE_STUDIO_PERSISTENCE
	end

	return true
end

local function getSlotId(
	player: Player
): string
	return CharacterSlotContextService
		.GetActiveSlotId(
			player
		)
end

local function legacyKeyForSlot(
	player: Player,
	slotId: string
): string
	return "Player_"
		.. tostring(player.UserId)
		.. "_Slot_"
		.. slotId
end

local function previousLifeKey(
	player: Player,
	lifeId: string
): string
	return "Player_"
		.. tostring(player.UserId)
		.. "_Life_"
		.. lifeId
end

local function keyForLife(
	_player: Player,
	lifeId: string
): string
	-- LifeId is globally unique. Keep the DataStore key below Roblox's
	-- 50-character KeyName limit for both legacy ids and future GUIDs.
	return "life_" .. lifeId
end

local function emptyData(): TechniqueData
	return {
		Version = 1,
		Learned = {},
	}
end

local function sanitizeRecord(
	raw: any
): LearnedRecord
	if typeof(raw) ~= "table" then
		return {
			LearnedAt = 0,
			SourceType = "Legacy",
			SourceId = "",
		}
	end

	return {
		LearnedAt =
			typeof(raw.LearnedAt) == "number"
			and math.floor(raw.LearnedAt)
			or 0,

		SourceType =
			typeof(raw.SourceType) == "string"
			and raw.SourceType
			or "Unknown",

		SourceId =
			typeof(raw.SourceId) == "string"
			and raw.SourceId
			or "",
	}
end

local function sanitizeData(
	raw: any
): TechniqueData
	local result =
		emptyData()

	if typeof(raw) ~= "table" then
		return result
	end

	if typeof(raw.Learned) == "table" then
		for techniqueId,
			record in pairs(
				raw.Learned
			) do

			if typeof(techniqueId) == "string"
				and techniqueId ~= "" then

				result.Learned[
				techniqueId
				] = sanitizeRecord(
					record
				)
			end
		end
	end

	return result
end

local function countLearned(
	data: TechniqueData
): number
	local count = 0

	for _ in pairs(
		data.Learned
		) do
		count += 1
	end

	return count
end

local function getReplicaFolder(
	player: Player
): Folder
	local existing =
		player:FindFirstChild(
			"LearnedTechniques"
		)

	if existing
		and existing:IsA("Folder") then

		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder =
		Instance.new("Folder")

	folder.Name =
		"LearnedTechniques"

	folder.Parent =
		player

	return folder
end

local function publish(
	player: Player
)
	local state =
		states[player]

	if not state then
		return
	end

	player:SetAttribute(
		"TechniqueLearningReady",
		state.Loaded
	)

	player:SetAttribute(
		"TechniqueLearningPersistent",
		state.Persistent
	)

	player:SetAttribute(
		"TechniqueLearningSlotId",
		state.SlotId
	)

	player:SetAttribute(
		"TechniqueLearningLifeId",
		state.LifeId
	)

	player:SetAttribute(
		"TechniqueLearningCharacterId",
		state.CharacterId
	)

	player:SetAttribute(
		"TechniqueLearnedCount",
		countLearned(
			state.Data
		)
	)

	player:SetAttribute(
		"TechniqueDevBypassActive",
		DeveloperAccessService.HasContentBypass(
			player
		)
	)

	local folder =
		getReplicaFolder(
			player
		)

	folder:ClearAllChildren()

	for techniqueId in pairs(
		state.Data.Learned
		) do
		local value =
			Instance.new("BoolValue")

		value.Name =
			techniqueId

		value.Value =
			true

		value.Parent =
			folder
	end
end

local function markDirty(
	player: Player
)
	local state =
		states[player]

	if not state then
		return
	end

	state.Dirty =
		true

	publish(player)
end

local function savePlayer(
	player: Player,
	reason: string
): boolean
	local state =
		states[player]

	if not state
		or not state.Loaded then

		return false
	end

	if state.LoadFailed then
		warn(
			"[TechniqueLearningService] SAVE SKIPPED",
			player.Name,
			"Reason="
				.. reason,
			"LoadFailed=true"
		)

		return false
	end

	if not canPersist() then
		state.Persistent =
			false

		publish(player)

		return true
	end

	if not state.Dirty
		and reason == "Autosave" then

		return true
	end

	CharacterLifeContextService.AssertIdentity(
		player,
		state.SlotId,
		state.LifeId,
		"TechniqueLearningService"
	)

	local snapshot = {
		Version = 2,
		SlotId = state.SlotId,
		LifeId = state.LifeId,
		CharacterId = state.CharacterId,
		Learned =
			table.clone(
				state.Data.Learned
			),
	}

	local key =
		keyForLife(
			player,
			state.LifeId
		)

	local ok,
		err =
		pcall(
			function()
				store:UpdateAsync(
					key,
					function()
						return snapshot
					end
				)
			end
		)

	if not ok then
		warn(
			"[TechniqueLearningService] SAVE FAILED",
			player.Name,
			"Slot="
				.. state.SlotId,
			"Life="
				.. state.LifeId,
			err
		)

		return false
	end

	state.Persistent =
		true

	state.Dirty =
		false

	publish(player)

	return true
end

local function loadPlayer(
	player: Player
)
	local slotId =
		getSlotId(
			player
		)

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
		"TechniqueLearningService"
	)

	local state: PlayerState = {
		Loaded = false,
		Persistent = false,
		LoadFailed = false,
		Dirty = false,
		SlotId = slotId,
		LifeId = lifeId,
		CharacterId = characterId,
		Data = emptyData(),
	}

	states[player] =
		state

	local migratedLegacy =
		false

	if canPersist() then
		local key =
			keyForLife(
				player,
				lifeId
			)

		local ok,
			raw =
			pcall(
				function()
					return store:GetAsync(
						key
					)
				end
			)

		if not ok then
			state.LoadFailed =
				true

			warn(
				"[TechniqueLearningService] LOAD FAILED; USING MEMORY ONLY",
				player.Name,
				raw
			)

		else
			-- Compatibility with CharacterLife v1. The previous life key
			-- included UserId and can exceed Roblox's 50-character limit.
			-- Only query it when it is valid.
			if raw == nil then
				local previousKey =
					previousLifeKey(
						player,
						lifeId
					)

				if #previousKey <= 50 then
					local previousOk,
						previousRaw =
						pcall(function()
							return store:GetAsync(
								previousKey
							)
						end)

					if previousOk
						and previousRaw ~= nil then
						raw = previousRaw
						migratedLegacy = true
					end
				end
			end

			if raw == nil
				and identity.LegacyChildDataMigrationEligible == true then

				local legacyOk,
					legacyRaw =
					pcall(
						function()
							return store:GetAsync(
								legacyKeyForSlot(
									player,
									slotId
								)
							)
						end
					)

				if legacyOk and legacyRaw ~= nil then
					raw = legacyRaw
					migratedLegacy = true
				end
			end

			state.Data =
				sanitizeData(
					raw
				)

			state.Persistent =
				true

			if migratedLegacy then
				state.Dirty = true

				print(
					"[TechniqueLearningService] LEGACY SLOT MIGRATED",
					player.Name,
					"Slot=" .. slotId,
					"Life=" .. lifeId
				)
			end
		end
	end

	state.Loaded =
		true

	publish(player)

	print(
		"[TechniqueLearningService] LOADED",
		player.Name,
		"Slot="
			.. slotId,
		"Life="
			.. lifeId,
		"Persistent="
			.. tostring(
				state.Persistent
			),
		"Known="
			.. tostring(
				countLearned(
					state.Data
				)
			),
		"DevBypass="
			.. tostring(
				DeveloperAccessService.HasContentBypass(
					player
				)
			)
	)

	if migratedLegacy
		and state.Persistent then

		task.defer(function()
			if states[player]
				and states[player].Loaded then

				savePlayer(
					player,
					"LegacyLifeMigration"
				)
			end
		end)
	end
end

function TechniqueLearningService.GetData(
	player: Player
): TechniqueData?
	local state =
		states[player]

	if not state
		or not state.Loaded then

		return nil
	end

	return state.Data
end

function TechniqueLearningService.IsReady(
	player: Player
): boolean
	local state =
		states[player]

	return state ~= nil
		and state.Loaded
end

function TechniqueLearningService.Knows(
	player: Player,
	techniqueId: string
): boolean
	-- Devs do not need to populate LearnedTechniques one by one.
	if DeveloperAccessService.HasContentBypass(
		player
		) then

		return true
	end

	local state =
		states[player]

	if not state
		or not state.Loaded then

		return false
	end

	return state.Data.Learned[
	techniqueId
	] ~= nil
end

function TechniqueLearningService.CheckUse(
	player: Player,
	techniqueId: string
): (boolean, string, any?)
	if DeveloperAccessService.HasContentBypass(
		player
		) then

		return true,
			"DeveloperBypass",
			{
				DeveloperBypass =
				true,
			}
	end

	local state =
		states[player]

	if not state
		or not state.Loaded then

		return false,
			"TechniqueLearningNotReady",
			nil
	end

	if state.Data.Learned[
		techniqueId
		] == nil then

		return false,
			"TechniqueNotLearned",
			{
				TechniqueId =
				techniqueId,
			}
	end

	return true,
		"Known",
		nil
end

function TechniqueLearningService.Learn(
	player: Player,
	techniqueId: string,
	source: LearnSource?
): (boolean, string)
	if typeof(techniqueId) ~= "string"
		or techniqueId == "" then

		return false,
			"InvalidTechniqueId"
	end

	local state =
		states[player]

	if not state
		or not state.Loaded then

		return false,
			"TechniqueLearningNotReady"
	end

	if state.Data.Learned[
		techniqueId
		] ~= nil then

		return true,
			"AlreadyLearned"
	end

	source =
		source or {}

	state.Data.Learned[
	techniqueId
	] = {
		LearnedAt =
			os.time(),

		SourceType =
			typeof(source.Type) == "string"
			and source.Type
			or "Unknown",

		SourceId =
			typeof(source.Id) == "string"
			and source.Id
			or "",
	}

	markDirty(player)

	return true,
		"Learned"
end

function TechniqueLearningService.Forget(
	player: Player,
	techniqueId: string
): (boolean, string)
	local state =
		states[player]

	if not state
		or not state.Loaded then

		return false,
			"TechniqueLearningNotReady"
	end

	if state.Data.Learned[
		techniqueId
		] == nil then

		return true,
			"NotLearned"
	end

	state.Data.Learned[
	techniqueId
	] = nil

	markDirty(player)

	return true,
		"Forgotten"
end

function TechniqueLearningService.GetKnownTechniqueIds(
	player: Player
): {string}
	local result = {}

	local state =
		states[player]

	if not state
		or not state.Loaded then

		return result
	end

	for techniqueId in pairs(
		state.Data.Learned
		) do
		table.insert(
			result,
			techniqueId
		)
	end

	table.sort(result)

	return result
end

function TechniqueLearningService.Save(
	player: Player
): boolean
	return savePlayer(
		player,
		"Manual"
	)
end

function TechniqueLearningService.Start()
	if started then
		return
	end

	started =
		true

	DeveloperAccessService.Start()
	CharacterLifeContextService.Start()

	Players.PlayerAdded:
		Connect(
			loadPlayer
		)

	Players.PlayerRemoving:
		Connect(
			function(player)
				savePlayer(
					player,
					"PlayerRemoving"
				)

				states[player] =
				nil
			end
		)

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(
			loadPlayer,
			player
		)
	end

	task.spawn(
		function()
			while true do
				task.wait(
					AUTOSAVE_SECONDS
				)

				for player,
					state in pairs(
						states
					) do

					if player.Parent
						and state.Loaded then

						savePlayer(
							player,
							"Autosave"
						)
					end
				end
			end
		end
	)

	game:BindToClose(
		function()
			for player,
				state in pairs(
					states
				) do

				if state.Loaded then
					savePlayer(
						player,
						"BindToClose"
					)
				end
			end
		end
	)

	print(
		"[TechniqueLearningService] READY v2.1 CharacterLifeShortKey"
			.. " | Store="
			.. STORE_NAME
			.. " | StudioPersistence="
			.. tostring(
				ENABLE_STUDIO_PERSISTENCE
			)
			.. " | Autosave="
			.. tostring(
				AUTOSAVE_SECONDS
			)
			.. "s"
			.. " | DevBypass=ON"
			.. " | LifeScoped=ON"
	)
end

return TechniqueLearningService
