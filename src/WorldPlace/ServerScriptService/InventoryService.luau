--!strict
-- InventoryService v1.2 - Persistent Quantities + Ninja Bag Capacity Contract
-- ServerScriptService > InventoryService [ModuleScript]
--
-- Canonical:
-- InventoryAmount_<ItemId>
-- InventoryMax_<ItemId>
--
-- Throwable compatibility mirrors:
-- NinjaBagAmount_<Projectile>
-- NinjaBagMax_<Projectile>
--
-- Ninja Bag capacity is enforced for INCREASES after EquipmentReady=true.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local InventoryCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"InventoryCatalog"
		)
	)

local InventoryService = {}

local function amountName(
	itemId: string
): string
	return "InventoryAmount_" .. itemId
end

local function maxName(
	itemId: string
): string
	return "InventoryMax_" .. itemId
end

local function legacyAmountName(
	itemId: string
): string
	return "NinjaBagAmount_" .. itemId
end

local function legacyMaxName(
	itemId: string
): string
	return "NinjaBagMax_" .. itemId
end

local function safeInt(
	value: any,
	fallback: number
): number

	if typeof(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge then

		return math.max(
			0,
			math.floor(
				fallback
			)
		)
	end

	return math.max(
		0,
		math.floor(
			value
		)
	)
end

local function capacityCost(
	item: any
): number

	if item.NinjaBagEquippable ~=
		true then
		return 0
	end

	return math.max(
		1,
		tonumber(
			item.NinjaBagCapacityCost
		) or 1
	)
end

local function mirrorThrowable(
	player: Player,
	item: any,
	amount: number,
	maxAmount: number
)

	if item.NinjaBagEquippable ~=
		true then
		return
	end

	player:SetAttribute(
		legacyAmountName(
			item.Id
		),
		amount
	)

	player:SetAttribute(
		legacyMaxName(
			item.Id
		),
		maxAmount
	)
end

function InventoryService.GetAmount(
	player: Player,
	itemId: string
): number

	if not InventoryCatalog.GetItem(
		itemId
		) then

		return 0
	end

	return safeInt(
		player:GetAttribute(
			amountName(
				itemId
			)
		),
		0
	)
end

function InventoryService.GetMaxAmount(
	player: Player,
	itemId: string
): number

	local item =
		InventoryCatalog.GetItem(
			itemId
		)

	if not item then
		return 0
	end

	return safeInt(
		player:GetAttribute(
			maxName(
				itemId
			)
		),
		item.MaxAmount
			or 0
	)
end

function InventoryService.GetUsedNinjaBagCapacity(
	player: Player
): number

	local used = 0

	for _,
		item in ipairs(
			InventoryCatalog.GetNinjaBagItems()
		) do

		used +=
			InventoryService.GetAmount(
				player,
				item.Id
			)
			* capacityCost(
				item
			)
	end

	return used
end

function InventoryService.RefreshNinjaBagCapacityUsage(
	player: Player
): number

	local used =
		InventoryService.GetUsedNinjaBagCapacity(
			player
		)

	player:SetAttribute(
		"NinjaBagUsedCapacity",
		used
	)

	return used
end

function InventoryService.InitializePlayer(
	player: Player
)

	player:SetAttribute(
		"InventoryReady",
		false
	)

	for _,
		item in ipairs(
			InventoryCatalog.GetAllItems()
		) do

		local configuredMax =
			safeInt(
				item.MaxAmount,
				99
			)

		local existingMax =
			player:GetAttribute(
				maxName(
					item.Id
				)
			)

		local finalMax =
			if typeof(
				existingMax
			) == "number"
			then safeInt(
				existingMax,
				configuredMax
			)
			else configuredMax

		player:SetAttribute(
			maxName(
				item.Id
			),
			finalMax
		)

		local existingAmount =
			player:GetAttribute(
				amountName(
					item.Id
				)
			)

		if existingAmount == nil
			and item.NinjaBagEquippable ==
			true then

			existingAmount =
				player:GetAttribute(
					legacyAmountName(
						item.Id
					)
				)
		end

		local starting =
			safeInt(
				item.StartingAmount,
				0
			)

		local finalAmount =
			if typeof(
				existingAmount
			) == "number"
			then math.clamp(
				safeInt(
					existingAmount,
					starting
				),
				0,
				finalMax
			)
			else math.min(
				starting,
				finalMax
			)

		player:SetAttribute(
			amountName(
				item.Id
			),
			finalAmount
		)

		mirrorThrowable(
			player,
			item,
			finalAmount,
			finalMax
		)
	end

	InventoryService.RefreshNinjaBagCapacityUsage(
		player
	)

	player:SetAttribute(
		"InventoryReady",
		true
	)
end

-- Persistence-only restore path.
-- It bypasses equipped Ninja Bag capacity because the inventory quantities
-- must be restored BEFORE saved equipment is reapplied.
-- Values are still catalog-validated and clamped to the configured max.
function InventoryService.RestoreAmount(
	player: Player,
	itemId: string,
	amount: number
): (boolean, number, string)

	local item =
		InventoryCatalog.GetItem(
			itemId
		)

	if not item then
		return false,
			0,
			"invalid item"
	end

	local maxAmount =
		InventoryService.GetMaxAmount(
			player,
			itemId
		)

	local finalAmount =
		math.clamp(
			safeInt(
				amount,
				0
			),
			0,
			maxAmount
		)

	player:SetAttribute(
		amountName(
			itemId
		),
		finalAmount
	)

	mirrorThrowable(
		player,
		item,
		finalAmount,
		maxAmount
	)

	InventoryService.RefreshNinjaBagCapacityUsage(
		player
	)

	return true,
		finalAmount,
		"OK"
end

function InventoryService.SetAmount(
	player: Player,
	itemId: string,
	amount: number
): (boolean, number, string)

	local item =
		InventoryCatalog.GetItem(
			itemId
		)

	if not item then
		return false,
			0,
			"invalid item"
	end

	local current =
		InventoryService.GetAmount(
			player,
			itemId
		)

	local maxAmount =
		InventoryService.GetMaxAmount(
			player,
			itemId
		)

	local requested =
		math.clamp(
			safeInt(
				amount,
				0
			),
			0,
			maxAmount
		)

	local finalAmount =
		requested

	local reason =
		"OK"

	-- Capacity applies only after EquipmentService has established the equipped
	-- bag. Existing QA data can initialize first without being destroyed.
	if item.NinjaBagEquippable ==
		true
		and requested > current
		and player:GetAttribute(
			"EquipmentReady"
		) == true then

		local bagCapacity =
			safeInt(
				player:GetAttribute(
					"NinjaBagCapacity"
				),
				0
			)

		local used =
			InventoryService.GetUsedNinjaBagCapacity(
				player
			)

		local free =
			math.max(
				0,
				bagCapacity
				- used
			)

		local cost =
			capacityCost(
				item
			)

		local maxAdditional =
			math.floor(
				free
				/ cost
			)

		finalAmount =
			math.min(
				requested,
				current
				+ maxAdditional
			)

		if finalAmount <
			requested then
			reason =
				"ninja bag capacity limited"
		end
	end

	player:SetAttribute(
		amountName(
			itemId
		),
		finalAmount
	)

	mirrorThrowable(
		player,
		item,
		finalAmount,
		maxAmount
	)

	InventoryService.RefreshNinjaBagCapacityUsage(
		player
	)

	return true,
		finalAmount,
		reason
end

function InventoryService.Add(
	player: Player,
	itemId: string,
	amount: number
): (boolean, number, string)

	return InventoryService.SetAmount(
		player,
		itemId,
		InventoryService.GetAmount(
			player,
			itemId
		) + amount
	)
end

function InventoryService.Consume(
	player: Player,
	itemId: string,
	amount: number?
): (boolean, number, string)

	if not InventoryCatalog.GetItem(
		itemId
		) then

		return false,
			0,
			"invalid item"
	end

	local consumeAmount =
		math.max(
			1,
			safeInt(
				amount,
				1
			)
		)

	local current =
		InventoryService.GetAmount(
			player,
			itemId
		)

	if current <
		consumeAmount then

		return false,
			current,
			"not enough amount"
	end

	return InventoryService.SetAmount(
		player,
		itemId,
		current
		- consumeAmount
	)
end

function InventoryService.RefillAll(
	player: Player
)

	for _,
		item in ipairs(
			InventoryCatalog.GetAllItems()
		) do

		InventoryService.SetAmount(
			player,
			item.Id,
			InventoryService.GetMaxAmount(
				player,
				item.Id
			)
		)
	end
end

Players.PlayerAdded:
	Connect(
		function(
			player: Player
		)

			InventoryService.InitializePlayer(
				player
			)
		end
	)

for _,
	player in ipairs(
		Players:GetPlayers()
	) do

	InventoryService.InitializePlayer(
		player
	)
end

print(
	"[InventoryService] READY v1.2"
		.. " | PersistentQuantities=ON"
		.. " | ForcedStartingAmounts=OFF"
		.. " | NinjaBagCapacity=ON"
		.. " | LegacyMirror=ON"
)

return InventoryService
