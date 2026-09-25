--!strict
-- InventoryCatalog v2.2 - Katana Medium Weapon Baseline / Persistent Inventory
-- ReplicatedStorage > InventoryCatalog [ModuleScript]
--
-- Functional equipment slots:
-- Weapon
-- Armor
-- NinjaBag
--
-- Reserved:
-- Accessory
--
-- Appearance/cosmetics are intentionally NOT equipment stats.

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local ProjectileConfigs =
	require(
		ReplicatedStorage:
		WaitForChild(
			"ProjectileConfigs"
		)
	)

local InventoryCatalog = {}

InventoryCatalog.Categories = {
	{ Id = "All", DisplayName = "TODOS" },
	{ Id = "Weapons", DisplayName = "ARMAS" },
	{ Id = "Armor", DisplayName = "ARMADURAS" },
	{ Id = "Resources", DisplayName = "RECURSOS" },
	{ Id = "Tools", DisplayName = "HERRAMIENTAS" },
	{ Id = "Consumables", DisplayName = "CONSUMIBLES" },
}

InventoryCatalog.EquipmentSlots = {
	{ Id = "Weapon", DisplayName = "WEAPON", Active = true },
	{ Id = "Armor", DisplayName = "ARMOR", Active = true },
	{ Id = "NinjaBag", DisplayName = "NINJA BAG", Active = true },
	{ Id = "Accessory", DisplayName = "ACCESSORY", Active = false },
}

-- Current test equipment items.
-- Ownership is no longer forced on spawn. Developers may grant them from F7.
local STATIC_ITEMS: {[string]: any} = {
	KatanaQA = {
		Id = "KatanaQA",
		DisplayName = "KATANA",
		Description = "MEDIUM WEAPON - QA BASELINE",
		Category = "Weapons",
		Kind = "Weapon",
		EquipmentSlot = "Weapon",
		StartingAmount = 0,
		MaxAmount = 1,

		Weapon = {
			CatalogId = "KatanaQA",
			Class = "Medium",
		},
	},

	ChuninVest = {
		Id = "ChuninVest",
		DisplayName = "CHUNIN VEST",
		Description = "ARMOR � 15% RESISTENCIA",
		Category = "Armor",
		Kind = "Armor",
		EquipmentSlot = "Armor",
		StartingAmount = 0,
		MaxAmount = 1,

		Armor = {
			Resistance = 0.15,
			MaxDurability = 100,
		},
	},

	StandardNinjaBag = {
		Id = "StandardNinjaBag",
		DisplayName = "STANDARD NINJA BAG",
		Description = "BOLSA QA � CAPACIDAD 80",
		Category = "Tools",
		Kind = "NinjaBag",
		EquipmentSlot = "NinjaBag",
		StartingAmount = 0,
		MaxAmount = 1,

		NinjaBagEquipment = {
			Capacity = 80,
		},
	},
}

local function cloneTable(
	source: any
): any

	local copy = {}

	for key,
		value in pairs(
			source
		) do

		if typeof(value) == "table" then
			local nested = {}
			for nestedKey, nestedValue in pairs(value) do
				nested[nestedKey] = nestedValue
			end
			copy[key] = nested
		else
			copy[key] = value
		end
	end

	return copy
end

local function projectileToItem(
	projectileId: string
): any?

	local config =
		ProjectileConfigs[
	projectileId
	]

	if typeof(config) ~= "table"
		or typeof(
			config.NinjaBag
		) ~= "table" then

		return nil
	end

	local bag =
		config.NinjaBag

	return {
		Id = projectileId,

		DisplayName =
			if typeof(
				bag.DisplayName
			) == "string"
			then bag.DisplayName
			else string.upper(
				projectileId
			),

		Description =
			if typeof(
				bag.Subtitle
			) == "string"
			then bag.Subtitle
			else "LANZABLE",

		Category = "Tools",
		Kind = "Throwable",
		NinjaBagEquippable = true,

		-- One current action/volley = one capacity unit in QA.
		-- Can be tuned per item later (for example Fuma = 3).
		NinjaBagCapacityCost =
			if typeof(
				bag.CapacityCost
			) == "number"
			then math.max(
				1,
				bag.CapacityCost
			)
			else 1,

		-- Inventory is now persistent. ProjectileConfigs.QAStartingAmount is
		-- intentionally ignored so test ammunition is never forced on spawn.
		StartingAmount = 0,

		MaxAmount =
			if typeof(
				bag.QAMaxAmount
			) == "number"
			then bag.QAMaxAmount
			else 99,

		ProjectileId = projectileId,
	}
end

function InventoryCatalog.GetItem(
	itemId: string
): any?

	local staticItem =
		STATIC_ITEMS[
	itemId
	]

	if staticItem then
		return cloneTable(
			staticItem
		)
	end

	return projectileToItem(
		itemId
	)
end

function InventoryCatalog.GetAllItems(): {any}

	local result = {}

	for itemId,
		source in pairs(
			STATIC_ITEMS
		) do

		local item =
			cloneTable(
				source
			)

		item.Id =
			item.Id
			or itemId

		table.insert(
			result,
			item
		)
	end

	for projectileId in pairs(
		ProjectileConfigs
		) do

		local item =
			projectileToItem(
				projectileId
			)

		if item then
			table.insert(
				result,
				item
			)
		end
	end

	table.sort(
		result,
		function(
			a: any,
			b: any
		)

			return tostring(
				a.DisplayName
			) < tostring(
				b.DisplayName
			)
		end
	)

	return result
end

function InventoryCatalog.GetItemsByCategory(
	categoryId: string
): {any}

	if categoryId == "All" then
		return InventoryCatalog.GetAllItems()
	end

	local result = {}

	for _,
		item in ipairs(
			InventoryCatalog.GetAllItems()
		) do

		if item.Category ==
			categoryId then

			table.insert(
				result,
				item
			)
		end
	end

	return result
end

function InventoryCatalog.GetNinjaBagItems(): {any}

	local result = {}

	for _,
		item in ipairs(
			InventoryCatalog.GetAllItems()
		) do

		if item.NinjaBagEquippable ==
			true then

			table.insert(
				result,
				item
			)
		end
	end

	return result
end

function InventoryCatalog.GetItemsForEquipmentSlot(
	slotId: string
): {any}

	local result = {}

	for _,
		item in ipairs(
			InventoryCatalog.GetAllItems()
		) do

		if item.EquipmentSlot ==
			slotId then

			table.insert(
				result,
				item
			)
		end
	end

	return result
end

function InventoryCatalog.GetEquipmentSlotDefinition(
	slotId: string
): any?

	for _,
		definition in ipairs(
			InventoryCatalog.EquipmentSlots
		) do

		if definition.Id ==
			slotId then

			return definition
		end
	end

	return nil
end

return InventoryCatalog
