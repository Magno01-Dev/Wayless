--!strict
-- ServerScriptService > InventoryPersistenceService
--
-- WAYLESS Inventory Persistence v2.1 - Character Life short keys
--
-- Life-scoped:
-- - item quantities
-- - equipment
-- - armor durability
-- - Ninja Bag quick slots
--
-- Legacy slot data is migrated only for lives that existed before the
-- CharacterId/LifeId migration. New lives never read old slot keys.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryCatalog =
	require(ReplicatedStorage:WaitForChild("InventoryCatalog"))

local InventoryService =
	require(ServerScriptService:WaitForChild("InventoryService"))

local EquipmentService =
	require(ServerScriptService:WaitForChild("EquipmentService"))

local NinjaBagService =
	require(ServerScriptService:WaitForChild("NinjaBagService"))

local Services =
	ServerScriptService:WaitForChild("Services")

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

local InventoryPersistenceService = {}

local STORE_NAME = "WAYLESS_Inventory_v1"
local DATA_VERSION = 2
local AUTOSAVE_INTERVAL = 45
local READY_TIMEOUT = 10

local store =
	DataStoreService:GetDataStore(STORE_NAME)

type PlayerState = {
	Loaded: boolean,
	Loading: boolean,
	LoadFailed: boolean,
	Dirty: boolean,
	Saving: boolean,
	Restoring: boolean,
	SlotId: string?,
	LifeId: string?,
	CharacterId: string?,
	Connections: {RBXScriptConnection},
}

local states: {[Player]: PlayerState} = {}

local function makeState(): PlayerState
	return {
		Loaded = false,
		Loading = false,
		LoadFailed = false,
		Dirty = false,
		Saving = false,
		Restoring = false,
		SlotId = nil,
		LifeId = nil,
		CharacterId = nil,
		Connections = {},
	}
end

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = makeState()
		states[player] = state
	end
	return state
end

local function legacyKeyForSlot(
	player: Player,
	slotId: string
): string
	return "u"
		.. tostring(player.UserId)
		.. "_s"
		.. slotId
end

local function previousLifeKey(
	player: Player,
	lifeId: string
): string
	return "u"
		.. tostring(player.UserId)
		.. "_life_"
		.. lifeId
end

local function keyForLife(
	_player: Player,
	lifeId: string
): string
	return "life_" .. lifeId
end

local function amountAttr(itemId: string): string
	return "InventoryAmount_" .. itemId
end

local function equippedAttr(slotId: string): string
	return "Equipped" .. slotId
end

local function durabilityAttr(itemId: string): string
	return "EquipmentDurability_" .. itemId
end

local function quickSlotAttr(slotIndex: number): string
	return "NinjaBagSlot"
		.. tostring(slotIndex)
		.. "Projectile"
end

local function safeNonNegativeInt(value: any): number
	if typeof(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge then

		return 0
	end

	return math.max(0, math.floor(value))
end

local function safeString(value: any): string
	return typeof(value) == "string"
		and value
		or ""
end

local function waitForBackendReady(player: Player): boolean
	local deadline = time() + READY_TIMEOUT

	while player.Parent
		and time() < deadline do

		if player:GetAttribute("InventoryReady") == true
			and player:GetAttribute("EquipmentReady") == true
			and player:GetAttribute("NinjaBagReady") == true then

			return true
		end

		task.wait(0.05)
	end

	return player:GetAttribute("InventoryReady") == true
		and player:GetAttribute("EquipmentReady") == true
		and player:GetAttribute("NinjaBagReady") == true
end

local function disconnectState(state: PlayerState)
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end

	table.clear(state.Connections)
end

local function markDirty(player: Player)
	local state = states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed
		or state.Restoring then

		return
	end

	state.Dirty = true

	player:SetAttribute(
		"InventoryPersistenceDirty",
		true
	)
end

local function connectTrackedAttributes(
	player: Player,
	state: PlayerState
)
	disconnectState(state)

	local tracked = {}

	for _, item in ipairs(
		InventoryCatalog.GetAllItems()
		) do
		table.insert(
			tracked,
			amountAttr(item.Id)
		)

		if item.EquipmentSlot == "Armor"
			and typeof(item.Armor) == "table" then

			table.insert(
				tracked,
				durabilityAttr(item.Id)
			)
		end
	end

	for _, definition in ipairs(
		InventoryCatalog.EquipmentSlots
		) do
		table.insert(
			tracked,
			equippedAttr(definition.Id)
		)
	end

	for slotIndex = 1,
		NinjaBagService.GetSlotCount() do

		table.insert(
			tracked,
			quickSlotAttr(slotIndex)
		)
	end

	for _, attributeName in ipairs(tracked) do
		table.insert(
			state.Connections,
			player:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(function()
					markDirty(player)
				end)
		)
	end
end

local function buildPayload(
	player: Player,
	state: PlayerState
): {[string]: any}
	local items = {}
	local durability = {}
	local equipment = {}
	local quickSlots = {}

	for _, item in ipairs(
		InventoryCatalog.GetAllItems()
		) do
		items[item.Id] =
			InventoryService.GetAmount(
				player,
				item.Id
			)

		if item.EquipmentSlot == "Armor"
			and typeof(item.Armor) == "table" then

			durability[item.Id] =
				EquipmentService.GetArmorDurability(
					player,
					item.Id
				)
		end
	end

	for _, definition in ipairs(
		InventoryCatalog.EquipmentSlots
		) do
		equipment[definition.Id] =
			EquipmentService.GetEquipped(
				player,
				definition.Id
			)
			or ""
	end

	for slotIndex = 1,
		NinjaBagService.GetSlotCount() do

		quickSlots[tostring(slotIndex)] =
			NinjaBagService.GetSlotProjectile(
				player,
				slotIndex
			)
			or ""
	end

	return {
		Version = DATA_VERSION,
		SlotId = state.SlotId,
		LifeId = state.LifeId,
		CharacterId = state.CharacterId,
		Items = items,
		Equipment = equipment,
		Durability = durability,
		NinjaBagSlots = quickSlots,
		UpdatedAt = os.time(),
	}
end

local function restorePayload(
	player: Player,
	raw: any
)
	if typeof(raw) ~= "table" then
		return
	end

	local state = getState(player)
	state.Restoring = true

	local items =
		typeof(raw.Items) == "table"
		and raw.Items
		or {}

	for _, item in ipairs(
		InventoryCatalog.GetAllItems()
		) do
		local amount =
			safeNonNegativeInt(
				items[item.Id]
			)

		InventoryService.RestoreAmount(
			player,
			item.Id,
			amount
		)
	end

	local equipment =
		typeof(raw.Equipment) == "table"
		and raw.Equipment
		or {}

	for _, definition in ipairs(
		InventoryCatalog.EquipmentSlots
		) do
		if definition.Active == true then
			local requested =
				safeString(
					equipment[definition.Id]
				)

			local itemId: string? =
				requested ~= ""
				and requested
				or nil

			local ok, reason =
				EquipmentService.SetEquipped(
					player,
					definition.Id,
					itemId
				)

			if not ok then
				warn(
					"[InventoryPersistenceService] EQUIPMENT RESTORE SKIPPED",
					player.Name,
					definition.Id,
					requested,
					reason
				)
			end
		end
	end

	local durability =
		typeof(raw.Durability) == "table"
		and raw.Durability
		or {}

	for _, item in ipairs(
		InventoryCatalog.GetAllItems()
		) do
		if item.EquipmentSlot == "Armor"
			and typeof(item.Armor) == "table"
			and durability[item.Id] ~= nil then

			EquipmentService.SetArmorDurability(
				player,
				item.Id,
				tonumber(
					durability[item.Id]
				)
					or 0
			)
		end
	end

	local slots =
		typeof(raw.NinjaBagSlots) == "table"
		and raw.NinjaBagSlots
		or {}

	for slotIndex = 1,
		NinjaBagService.GetSlotCount() do

		local value =
			safeString(
				slots[tostring(slotIndex)]
			)

		local ok, reason =
			NinjaBagService.SetSlot(
				player,
				slotIndex,
				value ~= ""
				and value
				or nil
			)

		if not ok then
			warn(
				"[InventoryPersistenceService] QUICK SLOT RESTORE SKIPPED",
				player.Name,
				slotIndex,
				value,
				reason
			)
		end
	end

	EquipmentService.InitializePlayer(player)

	InventoryService.RefreshNinjaBagCapacityUsage(
		player
	)

	state.Restoring = false
end

function InventoryPersistenceService.LoadPlayer(
	player: Player
): (boolean, string)
	local state = getState(player)

	if state.Loaded then
		return true, "AlreadyLoaded"
	end

	if state.Loading then
		return false, "AlreadyLoading"
	end

	state.Loading = true
	state.LoadFailed = false

	player:SetAttribute(
		"InventoryPersistenceReady",
		false
	)
	player:SetAttribute(
		"InventoryPersistenceLoadFailed",
		false
	)
	player:SetAttribute(
		"InventoryPersistenceDirty",
		false
	)

	if not waitForBackendReady(player) then
		state.Loading = false
		state.LoadFailed = true

		player:SetAttribute(
			"InventoryPersistenceLoadFailed",
			true
		)

		return false,
			"InventoryBackendNotReady"
	end

	CharacterLifeContextService.Start()

	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	local slotId = identity.SlotId
	local lifeId = identity.LifeId
	local characterId = identity.CharacterId

	CharacterLifeContextService.AssertIdentity(
		player,
		slotId,
		lifeId,
		"InventoryPersistenceService"
	)

	state.SlotId = slotId
	state.LifeId = lifeId
	state.CharacterId = characterId

	local key =
		keyForLife(
			player,
			lifeId
		)

	local success, raw =
		pcall(function()
			return store:GetAsync(key)
		end)

	if not success then
		state.Loading = false
		state.LoadFailed = true

		player:SetAttribute(
			"InventoryPersistenceLoadFailed",
			true
		)

		warn(
			"[InventoryPersistenceService] LOAD FAILED",
			player.Name,
			key,
			raw
		)

		return false,
			"DataStoreLoadFailed"
	end

	local migratedLegacy = false

	-- CharacterLife v1 Inventory could successfully create the old long
	-- life key for short legacy ids. Import it first so no changes made
	-- during that QA session are lost.
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

		local legacyKey =
			legacyKeyForSlot(
				player,
				slotId
			)

		local legacyOk, legacyRaw =
			pcall(function()
				return store:GetAsync(
					legacyKey
				)
			end)

		if legacyOk
			and legacyRaw ~= nil then

			raw = legacyRaw
			migratedLegacy = true
		end
	end

	if raw ~= nil then
		restorePayload(
			player,
			raw
		)
	end

	state.Loading = false
	state.Loaded = true
	state.Dirty = migratedLegacy

	connectTrackedAttributes(
		player,
		state
	)

	player:SetAttribute(
		"InventoryPersistenceReady",
		true
	)
	player:SetAttribute(
		"InventoryPersistenceLoadFailed",
		false
	)
	player:SetAttribute(
		"InventoryPersistenceDirty",
		migratedLegacy
	)
	player:SetAttribute(
		"InventoryPersistenceSlotId",
		slotId
	)
	player:SetAttribute(
		"InventoryPersistenceLifeId",
		lifeId
	)
	player:SetAttribute(
		"InventoryPersistenceCharacterId",
		characterId
	)

	print(
		"[InventoryPersistenceService] LOADED",
		player.Name,
		"Slot=" .. slotId,
		"Life=" .. lifeId,
		raw ~= nil
			and "ExistingData"
			or "NewInventory"
	)

	if migratedLegacy then
		print(
			"[InventoryPersistenceService] LEGACY SLOT MIGRATED",
			player.Name,
			"Slot=" .. slotId,
			"Life=" .. lifeId
		)

		task.defer(function()
			if states[player] then
				InventoryPersistenceService.SavePlayer(
					player,
					"LegacyLifeMigration"
				)
			end
		end)
	end

	return true,
		raw ~= nil
		and "Loaded"
		or "NewInventory"
end

function InventoryPersistenceService.IsReady(
	player: Player
): boolean
	local state = states[player]

	return state ~= nil
		and state.Loaded
		and not state.LoadFailed
end

function InventoryPersistenceService.SavePlayer(
	player: Player,
	reason: string?
): (boolean, string)
	local state = states[player]

	if not state
		or not state.Loaded then

		return false,
			"NotLoaded"
	end

	if state.LoadFailed then
		return false,
			"LoadFailedSaveBlocked"
	end

	if state.Saving then
		return false,
			"AlreadySaving"
	end

	local slotId = state.SlotId
	local lifeId = state.LifeId

	if not slotId or not lifeId then
		return false,
			"MissingLifeIdentity"
	end

	CharacterLifeContextService.AssertIdentity(
		player,
		slotId,
		lifeId,
		"InventoryPersistenceService"
	)

	state.Saving = true

	local key =
		keyForLife(
			player,
			lifeId
		)

	local payload =
		buildPayload(
			player,
			state
		)

	local success, result =
		pcall(function()
			return store:UpdateAsync(
				key,
				function(
					_old: any
				)
					return payload
				end
			)
		end)

	state.Saving = false

	if not success then
		state.Dirty = true

		player:SetAttribute(
			"InventoryPersistenceDirty",
			true
		)

		warn(
			"[InventoryPersistenceService] SAVE FAILED",
			player.Name,
			key,
			reason or "Unspecified",
			result
		)

		return false,
			"DataStoreSaveFailed"
	end

	state.Dirty = false

	player:SetAttribute(
		"InventoryPersistenceDirty",
		false
	)
	player:SetAttribute(
		"InventoryPersistenceLastSaveAt",
		os.time()
	)

	return true,
		"Saved"
end

function InventoryPersistenceService.SaveIfDirty(
	player: Player,
	reason: string?
): (boolean, string)
	local state = states[player]

	if not state
		or not state.Loaded
		or state.LoadFailed then

		return false,
			"NotReady"
	end

	if not state.Dirty then
		return true,
			"NotDirty"
	end

	return InventoryPersistenceService.SavePlayer(
		player,
		reason
	)
end

function InventoryPersistenceService.UnloadPlayer(
	player: Player
)
	local state = states[player]

	if not state then
		return
	end

	if state.Loaded
		and not state.LoadFailed then

		local ok, err =
			pcall(function()
				InventoryPersistenceService.SaveIfDirty(
					player,
					"PlayerRemoving"
				)
			end)

		if not ok then
			warn(
				"[InventoryPersistenceService] PLAYER REMOVING SAVE ERROR",
				player.Name,
				err
			)
		end
	end

	disconnectState(state)
	states[player] = nil
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)

		for _, player in ipairs(
			Players:GetPlayers()
			) do
			local state = states[player]

			if state
				and state.Loaded
				and state.Dirty
				and not state.Saving
				and not state.LoadFailed then

				InventoryPersistenceService.SavePlayer(
					player,
					"Autosave"
				)
			end
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(
		Players:GetPlayers()
		) do
		local state = states[player]

		if state
			and state.Loaded
			and not state.LoadFailed then

			local ok, err =
				pcall(function()
					InventoryPersistenceService.SaveIfDirty(
						player,
						"BindToClose"
					)
				end)

			if not ok then
				warn(
					"[InventoryPersistenceService] BIND TO CLOSE SAVE ERROR",
					player.Name,
					err
				)
			end
		end
	end
end)

print(
	"[InventoryPersistenceService] READY v2.1 CharacterLifeShortKey"
		.. " | DataStore="
		.. STORE_NAME
		.. " | LifeScoped=ON"
		.. " | LegacySlotMigration=ON"
		.. " | Autosave="
		.. tostring(AUTOSAVE_INTERVAL)
		.. "s"
)

return InventoryPersistenceService
