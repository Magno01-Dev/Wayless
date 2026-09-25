--!strict
-- EquipmentService v1 - Hybrid Functional Equipment
-- ServerScriptService > EquipmentService [ModuleScript]
--
-- Functional:
-- Weapon
-- Armor
-- NinjaBag
--
-- Reserved:
-- Accessory
--
-- Armor state is copied to Character attributes for the existing
-- ProjectileDamageService armor contract.

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

local InventoryService =
	require(
		script.Parent:
		WaitForChild(
			"InventoryService"
		)
	)

local EquipmentService = {}

local DEFAULT_EQUIPMENT: {[string]: string} = {
	Weapon = "",
	Armor = "",
	NinjaBag = "StandardNinjaBag",
	Accessory = "",
}

local characterConnections: {[Player]: {RBXScriptConnection}} =
	{}

local function equippedAttribute(
	slotId: string
): string
	return "Equipped" .. slotId
end

local function durabilityAttribute(
	itemId: string
): string
	return "EquipmentDurability_" .. itemId
end

local function disconnectCharacter(
	player: Player
)

	local connections =
		characterConnections[
	player
	]

	if connections then
		for _,
			connection in ipairs(
				connections
			) do

			connection:
				Disconnect()
		end
	end

	characterConnections[
	player
	] = {}
end

local function getEquipped(
	player: Player,
	slotId: string
): string?

	local value =
		player:GetAttribute(
			equippedAttribute(
				slotId
			)
		)

	if typeof(value) ~= "string"
		or value == "" then
		return nil
	end

	return value
end

local function clearArmorAttributes(
	character: Model
)

	character:SetAttribute(
		"EquippedArmorId",
		""
	)

	character:SetAttribute(
		"ArmorResistance",
		0
	)

	character:SetAttribute(
		"ArmorDurability",
		0
	)

	character:SetAttribute(
		"ArmorMaxDurability",
		0
	)

	character:SetAttribute(
		"ArmorBroken",
		false
	)
end

local function applyArmor(
	player: Player,
	character: Model
)

	local armorId =
		getEquipped(
			player,
			"Armor"
		)

	if not armorId then
		clearArmorAttributes(
			character
		)
		return
	end

	local item =
		InventoryCatalog.GetItem(
			armorId
		)

	if not item
		or item.EquipmentSlot ~= "Armor"
		or typeof(
			item.Armor
		) ~= "table" then

		clearArmorAttributes(
			character
		)
		return
	end

	local resistance =
		math.clamp(
			tonumber(
				item.Armor.Resistance
			) or 0,
			0,
			0.95
		)

	local maxDurability =
		math.max(
			0,
			tonumber(
				item.Armor.MaxDurability
			) or 0
		)

	local durabilityName =
		durabilityAttribute(
			armorId
		)

	local durability =
		player:GetAttribute(
			durabilityName
		)

	if typeof(durability) ~= "number" then
		durability =
			maxDurability

		player:SetAttribute(
			durabilityName,
			durability
		)
	end

	durability =
		math.clamp(
			durability,
			0,
			maxDurability
		)

	character:SetAttribute(
		"EquippedArmorId",
		armorId
	)

	character:SetAttribute(
		"ArmorResistance",
		resistance
	)

	character:SetAttribute(
		"ArmorDurability",
		durability
	)

	character:SetAttribute(
		"ArmorMaxDurability",
		maxDurability
	)

	character:SetAttribute(
		"ArmorBroken",
		durability <= 0
	)
end

local function applySimpleEquipmentIds(
	player: Player,
	character: Model
)

	character:SetAttribute(
		"EquippedWeaponId",
		getEquipped(
			player,
			"Weapon"
		) or ""
	)

	character:SetAttribute(
		"EquippedNinjaBagId",
		getEquipped(
			player,
			"NinjaBag"
		) or ""
	)

	character:SetAttribute(
		"EquippedAccessoryId",
		getEquipped(
			player,
			"Accessory"
		) or ""
	)
end

local function applyNinjaBagCapacity(
	player: Player
)

	local bagId =
		getEquipped(
			player,
			"NinjaBag"
		)

	local capacity = 0

	if bagId then
		local item =
			InventoryCatalog.GetItem(
				bagId
			)

		if item
			and item.EquipmentSlot ==
			"NinjaBag"
			and typeof(
				item.NinjaBagEquipment
			) == "table" then

			capacity =
				math.max(
					0,
					math.floor(
						tonumber(
							item.NinjaBagEquipment.Capacity
						) or 0
					)
				)
		end
	end

	player:SetAttribute(
		"NinjaBagCapacity",
		capacity
	)

	InventoryService.RefreshNinjaBagCapacityUsage(
		player
	)
end

local function applyCharacter(
	player: Player,
	character: Model
)

	applySimpleEquipmentIds(
		player,
		character
	)

	applyArmor(
		player,
		character
	)
end

local function bindCharacter(
	player: Player,
	character: Model
)

	disconnectCharacter(
		player
	)

	applyCharacter(
		player,
		character
	)

	local connections =
		characterConnections[
	player
	]

	table.insert(
		connections,
		character:
			GetAttributeChangedSignal(
				"ArmorDurability"
			):
			Connect(
				function()

					local armorId =
					getEquipped(
						player,
						"Armor"
					)

					if not armorId then
						return
					end

					local item =
					InventoryCatalog.GetItem(
						armorId
					)

					if not item
						or typeof(
							item.Armor
						) ~= "table" then

						return
					end

					local maxDurability =
					math.max(
						0,
						tonumber(
							item.Armor.MaxDurability
						) or 0
					)

					local current =
					character:GetAttribute(
						"ArmorDurability"
					)

					if typeof(current) ~= "number" then
						return
					end

					player:SetAttribute(
						durabilityAttribute(
							armorId
						),
						math.clamp(
							current,
							0,
							maxDurability
						)
					)
				end
			)
	)
end

function EquipmentService.InitializePlayer(
	player: Player
)

	player:SetAttribute(
		"EquipmentReady",
		false
	)

	InventoryService.InitializePlayer(
		player
	)

	for _,
		definition in ipairs(
			InventoryCatalog.EquipmentSlots
		) do

		local attribute =
			equippedAttribute(
				definition.Id
			)

		if player:GetAttribute(
			attribute
			) == nil then

			player:SetAttribute(
				attribute,
				DEFAULT_EQUIPMENT[
				definition.Id
				] or ""
			)
		end
	end

	for _,
		item in ipairs(
			InventoryCatalog.GetAllItems()
		) do

		if item.EquipmentSlot ==
			"Armor"
			and typeof(
				item.Armor
			) == "table" then

			local durabilityName =
				durabilityAttribute(
					item.Id
				)

			if player:GetAttribute(
				durabilityName
				) == nil then

				player:SetAttribute(
					durabilityName,
					math.max(
						0,
						tonumber(
							item.Armor.MaxDurability
						) or 0
					)
				)
			end
		end
	end

	applyNinjaBagCapacity(
		player
	)

	player:SetAttribute(
		"EquipmentReady",
		true
	)

	if player.Character then
		bindCharacter(
			player,
			player.Character
		)
	end
end

function EquipmentService.GetEquipped(
	player: Player,
	slotId: string
): string?

	return getEquipped(
		player,
		slotId
	)
end

function EquipmentService.GetArmorDurability(
	player: Player,
	armorId: string
): number

	local value =
		player:GetAttribute(
			durabilityAttribute(
				armorId
			)
		)

	return if typeof(value) == "number"
		then math.max(
			0,
			value
		)
		else 0
end

function EquipmentService.SetArmorDurability(
	player: Player,
	armorId: string,
	value: number
): (boolean, string)

	local item =
		InventoryCatalog.GetItem(
			armorId
		)

	if not item
		or item.EquipmentSlot ~= "Armor"
		or typeof(
			item.Armor
		) ~= "table" then

		return false,
			"invalid armor"
	end

	local maxDurability =
		math.max(
			0,
			tonumber(
				item.Armor.MaxDurability
			) or 0
		)

	local final =
		math.clamp(
			value,
			0,
			maxDurability
		)

	player:SetAttribute(
		durabilityAttribute(
			armorId
		),
		final
	)

	if player.Character
		and getEquipped(
			player,
			"Armor"
		) == armorId then

		player.Character:SetAttribute(
			"ArmorDurability",
			final
		)

		player.Character:SetAttribute(
			"ArmorBroken",
			final <= 0
		)
	end

	return true,
		"OK"
end

function EquipmentService.SetEquipped(
	player: Player,
	slotId: string,
	itemId: string?
): (boolean, string)

	local definition =
		InventoryCatalog.GetEquipmentSlotDefinition(
			slotId
		)

	if not definition then
		return false,
			"invalid equipment slot"
	end

	if definition.Active ~= true then
		return false,
			"equipment slot inactive"
	end

	if itemId == nil
		or itemId == "" then

		if slotId == "NinjaBag" then
			return false,
				"ninja bag is required"
		end

		player:SetAttribute(
			equippedAttribute(
				slotId
			),
			""
		)

		if player.Character then
			applyCharacter(
				player,
				player.Character
			)
		end

		return true,
			"OK"
	end

	local item =
		InventoryCatalog.GetItem(
			itemId
		)

	if not item
		or item.EquipmentSlot ~=
		slotId then

		return false,
			"item does not fit slot"
	end

	if InventoryService.GetAmount(
		player,
		itemId
		) <= 0 then

		return false,
			"item not owned"
	end

	if slotId == "NinjaBag" then

		local newCapacity =
			if typeof(
				item.NinjaBagEquipment
			) == "table"
			then math.max(
				0,
				math.floor(
					tonumber(
						item.NinjaBagEquipment.Capacity
					) or 0
				)
			)
			else 0

		local used =
			InventoryService.GetUsedNinjaBagCapacity(
				player
			)

		if newCapacity <
			used then

			return false,
				"bag too small for current contents"
		end
	end

	player:SetAttribute(
		equippedAttribute(
			slotId
		),
		itemId
	)

	if slotId == "NinjaBag" then
		applyNinjaBagCapacity(
			player
		)
	end

	if player.Character then
		applyCharacter(
			player,
			player.Character
		)
	end

	return true,
		"OK"
end

Players.PlayerAdded:
	Connect(
		function(
			player: Player
		)

			EquipmentService.InitializePlayer(
				player
			)

			player.CharacterAdded:
			Connect(
				function(
					character: Model
				)

					bindCharacter(
						player,
						character
					)
				end
			)
		end
	)

for _,
	player in ipairs(
		Players:GetPlayers()
	) do

	EquipmentService.InitializePlayer(
		player
	)

	player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				bindCharacter(
					player,
					character
				)
			end
		)
end

Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			disconnectCharacter(
				player
			)

			characterConnections[
			player
			] = nil
		end
	)

print(
	"[EquipmentService] READY v1"
		.. " | Weapon=ON"
		.. " | Armor=ON"
		.. " | NinjaBag=ON"
		.. " | Accessory=RESERVED"
)

return EquipmentService
