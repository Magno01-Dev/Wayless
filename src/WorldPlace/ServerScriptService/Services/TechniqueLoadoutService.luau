--!strict
-- ServerScriptService > Services > TechniqueLoadoutService
--
-- WAYLESS Technique Loadout v2.1 - Character Life short keys.
--
-- Canonical contract:
--   10 technique slots per current Character Life.
--   Empty slots are stored as "".
--   Only actually learned techniques may be equipped.
--   The same technique cannot occupy more than one slot.
--   Assigning an already-equipped technique moves it to the requested slot.
--
-- Replicated compatibility/read attributes:
--   TechniqueLoadoutReady
--   TechniqueLoadoutSlotCount
--   TechniqueLoadoutSlot_1 .. TechniqueLoadoutSlot_10
--
-- Server remains authoritative. Client UI never writes attributes directly.

local Players =
	game:GetService(
		"Players"
	)

local DataStoreService =
	game:GetService(
		"DataStoreService"
	)

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

local Services =
	ServerScriptService:
	WaitForChild(
		"Services"
	)

local CharacterSlotContextService =
	require(
		Services:
		WaitForChild(
			"CharacterSlotContextService"
		)
	)

local CharacterLifeContextService =
	require(
		Services:
		WaitForChild(
			"CharacterLifeContextService"
		)
	)

local TechniqueLearningService =
	require(
		Services:
		WaitForChild(
			"TechniqueLearningService"
		)
	)

local TechniqueRegistry =
	require(
		Services:
		WaitForChild(
			"TechniqueRegistry"
		)
	)

local TechniqueLoadoutService = {}

local SLOT_COUNT =
	10

local DATASTORE_NAME =
	"WAYLESS_TechniqueLoadout_v1"

local store =
	DataStoreService:GetDataStore(
		DATASTORE_NAME
	)

local started =
	false

type PlayerState = {
	SlotId: string,
	LifeId: string,
	CharacterId: string,
	Slots: {[number]: string},
	Loaded: boolean,
	LoadFailed: boolean,
	Dirty: boolean,
}

local states: {[Player]: PlayerState} =
	{}

local function makeEmptySlots(): {[number]: string}
	local slots: {[number]: string} =
		{}

	for slotIndex = 1,
		SLOT_COUNT do

		slots[slotIndex] =
			""
	end

	return slots
end

local function legacyKeyForSlot(
	player: Player,
	slotId: string
): string
	return "u_"
		.. tostring(
			player.UserId
		)
		.. "_slot_"
		.. slotId
end

local function previousLifeKey(
	player: Player,
	lifeId: string
): string
	return "u_"
		.. tostring(
			player.UserId
		)
		.. "_life_"
		.. lifeId
end

local function makeLifeKey(
	_player: Player,
	lifeId: string
): string
	return "life_" .. lifeId
end

local function isValidSlotIndex(
	value: any
): boolean
	return typeof(value) == "number"
		and value == math.floor(value)
		and value >= 1
		and value <= SLOT_COUNT
end

local function buildKnownSet(
	player: Player
): {[string]: boolean}
	local result: {[string]: boolean} =
		{}

	for _, techniqueId in ipairs(
		TechniqueLearningService
			.GetKnownTechniqueIds(
				player
			)
		) do

		result[techniqueId] =
			true
	end

	return result
end

local function isUsableTechniqueId(
	techniqueId: any,
	knownSet: {[string]: boolean}
): boolean
	if typeof(techniqueId)
		~= "string"
		or techniqueId == ""
		or #techniqueId > 80 then

		return false
	end

	if not TechniqueRegistry.Get(
		techniqueId
		) then

		return false
	end

	return knownSet[techniqueId]
		== true
end

local function sanitizeStoredSlots(
	player: Player,
	raw: any
): ({[number]: string}, boolean)
	local slots =
		makeEmptySlots()

	local changed =
		false

	local source =
		typeof(raw) == "table"
		and typeof(raw.Slots) == "table"
		and raw.Slots
		or raw

	if typeof(source) ~= "table" then
		return slots,
			raw ~= nil
	end

	local knownSet =
		buildKnownSet(
			player
		)

	local alreadyUsed: {[string]: boolean} =
		{}

	for slotIndex = 1,
		SLOT_COUNT do

		local candidate =
			source[slotIndex]
			or source[tostring(slotIndex)]

		if candidate == nil
			or candidate == "" then

			slots[slotIndex] =
				""

		elseif isUsableTechniqueId(
			candidate,
			knownSet
			) and not alreadyUsed[candidate] then

			slots[slotIndex] =
				candidate

			alreadyUsed[candidate] =
				true

		else
			changed =
				true
		end
	end

	return slots,
		changed
end

local function publish(
	player: Player,
	state: PlayerState
)
	player:SetAttribute(
		"TechniqueLoadoutReady",
		state.Loaded
			and not state.LoadFailed
	)

	player:SetAttribute(
		"TechniqueLoadoutLoadFailed",
		state.LoadFailed
	)

	player:SetAttribute(
		"TechniqueLoadoutSlotCount",
		SLOT_COUNT
	)

	player:SetAttribute(
		"TechniqueLoadoutCharacterSlotId",
		state.SlotId
	)

	player:SetAttribute(
		"TechniqueLoadoutLifeId",
		state.LifeId
	)

	player:SetAttribute(
		"TechniqueLoadoutCharacterId",
		state.CharacterId
	)

	for slotIndex = 1,
		SLOT_COUNT do

		player:SetAttribute(
			"TechniqueLoadoutSlot_"
				.. tostring(slotIndex),
			state.Slots[slotIndex]
				or ""
		)
	end
end

local function waitForTechniqueLearning(
	player: Player
): boolean
	while player.Parent
		and not TechniqueLearningService
		.IsReady(
			player
		) do

		task.wait(0.1)
	end

	return player.Parent ~= nil
		and TechniqueLearningService
		.IsReady(
			player
		)
end

local function loadPlayer(
	player: Player
)
	local slotId =
		CharacterSlotContextService
		.GetActiveSlotId(
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
		"TechniqueLoadoutService"
	)

	local state: PlayerState = {
		SlotId = slotId,
		LifeId = lifeId,
		CharacterId = characterId,
		Slots = makeEmptySlots(),
		Loaded = false,
		LoadFailed = false,
		Dirty = false,
	}

	states[player] =
		state

	publish(
		player,
		state
	)

	if not waitForTechniqueLearning(
		player
		) then

		return
	end

	local ok,
		raw =
		pcall(
			function()
				return store:GetAsync(
					makeLifeKey(
						player,
						lifeId
					)
				)
			end
		)

	local migratedLegacy =
		false

	if ok and raw == nil then
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

	if ok
		and raw == nil
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

	if not ok then
		state.LoadFailed =
			true

		warn(
			"[TechniqueLoadoutService] LOAD FAILED",
			player.Name,
			slotId,
			raw
		)

		publish(
			player,
			state
		)

		return
	end

	local slots,
		changed =
		sanitizeStoredSlots(
			player,
			raw
		)

	state.Slots =
		slots

	state.Loaded =
		true

	state.Dirty =
		changed
		or migratedLegacy

	publish(
		player,
		state
	)

	print(
		"[TechniqueLoadoutService] LOADED",
		player.Name,
		"Slot",
		slotId,
		"Life",
		lifeId
	)

	if migratedLegacy then
		print(
			"[TechniqueLoadoutService] LEGACY SLOT MIGRATED",
			player.Name,
			"Slot=" .. slotId,
			"Life=" .. lifeId
		)

		task.defer(function()
			if states[player] then
				TechniqueLoadoutService.Save(
					player
				)
			end
		end)
	end
end

function TechniqueLoadoutService.GetSlotCount(): number
	return SLOT_COUNT
end

function TechniqueLoadoutService.IsReady(
	player: Player
): boolean
	local state =
		states[player]

	return state ~= nil
		and state.Loaded
		and not state.LoadFailed
end

function TechniqueLoadoutService.GetSlot(
	player: Player,
	slotIndex: number
): string?
	if not isValidSlotIndex(
		slotIndex
		) then

		return nil
	end

	local state =
		states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed then

		return nil
	end

	local techniqueId =
		state.Slots[slotIndex]

	if techniqueId == "" then
		return nil
	end

	return techniqueId
end

function TechniqueLoadoutService.GetSlots(
	player: Player
): {[number]: string}
	local result: {[number]: string} =
		makeEmptySlots()

	local state =
		states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed then

		return result
	end

	for slotIndex = 1,
		SLOT_COUNT do

		result[slotIndex] =
			state.Slots[slotIndex]
			or ""
	end

	return result
end

function TechniqueLoadoutService.FindSlot(
	player: Player,
	techniqueId: string
): number?
	local state =
		states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed then

		return nil
	end

	for slotIndex = 1,
		SLOT_COUNT do

		if state.Slots[slotIndex]
			== techniqueId then

			return slotIndex
		end
	end

	return nil
end

function TechniqueLoadoutService.IsEquipped(
	player: Player,
	techniqueId: string
): boolean
	return TechniqueLoadoutService.FindSlot(
		player,
		techniqueId
	) ~= nil
end

function TechniqueLoadoutService.Save(
	player: Player
): boolean
	local state =
		states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed then

		return false
	end

	if not state.Dirty then
		return true
	end

	CharacterLifeContextService.AssertIdentity(
		player,
		state.SlotId,
		state.LifeId,
		"TechniqueLoadoutService"
	)

	local payload: any = {
		Version = 2,
		CharacterSlotId =
			state.SlotId,
		LifeId =
			state.LifeId,
		CharacterId =
			state.CharacterId,
		Slots = {},
	}

	for slotIndex = 1,
		SLOT_COUNT do

		payload.Slots[
		tostring(slotIndex)
		] =
			state.Slots[slotIndex]
			or ""
	end

	local ok,
		err =
		pcall(
			function()
				store:UpdateAsync(
					makeLifeKey(
						player,
						state.LifeId
					),
					function(
						_current: any
					): any
						return payload
					end
				)
			end
		)

	if not ok then
		warn(
			"[TechniqueLoadoutService] SAVE FAILED",
			player.Name,
			state.SlotId,
			err
		)

		return false
	end

	state.Dirty =
		false

	return true
end

function TechniqueLoadoutService.SetSlot(
	player: Player,
	slotIndex: any,
	techniqueId: any
): (boolean, string)
	if not isValidSlotIndex(
		slotIndex
		) then

		return false,
			"InvalidSlotIndex"
	end

	local state =
		states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed then

		return false,
			"TechniqueLoadoutNotReady"
	end

	local normalizedId: string =
		""

	if techniqueId ~= nil
		and techniqueId ~= "" then

		if typeof(techniqueId)
			~= "string"
			or #techniqueId > 80 then

			return false,
				"InvalidTechniqueId"
		end

		if not TechniqueRegistry.Get(
			techniqueId
			) then

			return false,
				"UnknownTechnique"
		end

		local knownSet =
			buildKnownSet(
				player
			)

		if knownSet[techniqueId]
			~= true then

			return false,
				"TechniqueNotLearned"
		end

		normalizedId =
			techniqueId
	end

	local numericSlot =
		slotIndex :: number

	if normalizedId ~= "" then
		for index = 1,
			SLOT_COUNT do

			if index ~= numericSlot
				and state.Slots[index]
				== normalizedId then

				state.Slots[index] =
					""
			end
		end
	end

	if state.Slots[numericSlot]
		== normalizedId then

		return true,
			"NoChange"
	end

	state.Slots[numericSlot] =
		normalizedId

	state.Dirty =
		true

	publish(
		player,
		state
	)

	local saveOk =
		TechniqueLoadoutService.Save(
			player
		)

	if normalizedId == "" then
		return true,
			saveOk
			and "SlotCleared"
			or "SlotClearedSavePending"
	end

	return true,
		saveOk
		and "TechniqueAssigned"
		or "TechniqueAssignedSavePending"
end

function TechniqueLoadoutService.Start()
	if started then
		return
	end

	started =
		true

	CharacterSlotContextService.Start()
	CharacterLifeContextService.Start()
	TechniqueLearningService.Start()

	for _, player in ipairs(
		Players:GetPlayers()
		) do

		task.spawn(
			loadPlayer,
			player
		)
	end

	Players.PlayerAdded:
		Connect(
			function(
				player: Player
			)
				task.spawn(
					loadPlayer,
					player
				)
			end
		)

	Players.PlayerRemoving:
		Connect(
			function(
				player: Player
			)
				TechniqueLoadoutService.Save(
					player
				)

				states[player] =
				nil
			end
		)

	game:BindToClose(
		function()
			for _, player in ipairs(
				Players:GetPlayers()
				) do

				TechniqueLoadoutService.Save(
					player
				)
			end
		end
	)
end

print(
	"[TechniqueLoadoutService] READY v2.1 CharacterLifeShortKey"
		.. " | Slots="
		.. tostring(SLOT_COUNT)
		.. " | CharacterSlotContext=ON"
		.. " | LearnedOnly=ON"
		.. " | DuplicateTechniques=OFF"
)

return TechniqueLoadoutService
