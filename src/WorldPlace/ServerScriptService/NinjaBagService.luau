--!strict
-- NinjaBagService v2.1 - Configurable Slots + Equipped Bag Requirement
-- ServerScriptService > NinjaBagService [ModuleScript]

local Players =
	game:GetService(
		"Players"
	)

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

local InventoryService =
	require(
		script.Parent:
		WaitForChild(
			"InventoryService"
		)
	)

local NinjaBagService = {}

local SLOT_COUNT =
	4

local DEFAULT_LOADOUT: {[number]: string} = {
	[1] = "Kunai",
	[2] = "Shuriken",
	[3] = "Senbon",
	[4] = "Fuma",
}

local function validSlot(
	slotIndex: any
): boolean

	return typeof(slotIndex) == "number"
		and slotIndex % 1 == 0
		and slotIndex >= 1
		and slotIndex <= SLOT_COUNT
end

local function slotName(
	slotIndex: number
): string

	return "NinjaBagSlot"
		.. tostring(
			slotIndex
		)
		.. "Projectile"
end

function NinjaBagService.InitializePlayer(
	player: Player
)

	InventoryService.InitializePlayer(
		player
	)

	player:SetAttribute(
		"NinjaBagReady",
		false
	)

	player:SetAttribute(
		"NinjaBagSlotCount",
		SLOT_COUNT
	)

	for slotIndex = 1,
		SLOT_COUNT do

		if player:GetAttribute(
			slotName(
				slotIndex
			)
			) == nil then

			player:SetAttribute(
				slotName(
					slotIndex
				),
				DEFAULT_LOADOUT[
				slotIndex
				] or ""
			)
		end
	end

	player:SetAttribute(
		"NinjaBagReady",
		true
	)
end

function NinjaBagService.GetSlotCount(): number
	return SLOT_COUNT
end

function NinjaBagService.GetSlotProjectile(
	player: Player,
	slotIndex: any
): string?

	if not validSlot(
		slotIndex
		) then
		return nil
	end

	local value =
		player:GetAttribute(
			slotName(
				slotIndex
			)
		)

	if typeof(value) ~= "string"
		or value == ""
		or typeof(
			ProjectileConfigs[
			value
			]
		) ~= "table" then

		return nil
	end

	return value
end

function NinjaBagService.GetAmount(
	player: Player,
	projectileType: string
): number

	return InventoryService.GetAmount(
		player,
		projectileType
	)
end

function NinjaBagService.GetMaxAmount(
	player: Player,
	projectileType: string
): number

	return InventoryService.GetMaxAmount(
		player,
		projectileType
	)
end

function NinjaBagService.CanUseSlot(
	player: Player,
	slotIndex: any
): (boolean, string?, string)

	if not validSlot(
		slotIndex
		) then
		return false,
			nil,
			"invalid slot"
	end

	local equippedBag =
		player:GetAttribute(
			"EquippedNinjaBag"
		)

	local capacity =
		player:GetAttribute(
			"NinjaBagCapacity"
		)

	if typeof(equippedBag) ~= "string"
		or equippedBag == ""
		or typeof(capacity) ~= "number"
		or capacity <= 0 then

		return false,
			nil,
			"no ninja bag equipped"
	end

	local projectileType =
		NinjaBagService.GetSlotProjectile(
			player,
			slotIndex
		)

	if not projectileType then
		return false,
			nil,
			"empty slot"
	end

	if NinjaBagService.GetAmount(
		player,
		projectileType
		) <= 0 then

		return false,
			projectileType,
			"out of ammo"
	end

	return true,
		projectileType,
		"OK"
end

function NinjaBagService.ConsumeSlot(
	player: Player,
	slotIndex: any,
	amount: number?
): (boolean, string?, number, string)

	local canUse,
		projectileType,
		reason =
		NinjaBagService.CanUseSlot(
			player,
			slotIndex
		)

	if not canUse
		or not projectileType then

		return false,
			projectileType,
			0,
			reason
	end

	local success,
		remaining,
		consumeReason =
		InventoryService.Consume(
			player,
			projectileType,
			amount or 1
		)

	return success,
		projectileType,
		remaining,
		consumeReason
end

function NinjaBagService.SetSlot(
	player: Player,
	slotIndex: any,
	projectileType: string?
): (boolean, string)

	if not validSlot(
		slotIndex
		) then
		return false,
			"invalid slot"
	end

	if projectileType ~= nil then
		if typeof(projectileType) ~= "string"
			or typeof(
				ProjectileConfigs[
				projectileType
				]
			) ~= "table" then

			return false,
				"invalid projectile"
		end
	end

	player:SetAttribute(
		slotName(
			slotIndex
		),
		projectileType or ""
	)

	return true,
		"OK"
end

function NinjaBagService.SetAmount(
	player: Player,
	projectileType: string,
	amount: number
): (boolean, string)

	local success,
		_,
		reason =
		InventoryService.SetAmount(
			player,
			projectileType,
			amount
		)

	return success,
		reason
end

function NinjaBagService.RefillAll(
	player: Player
)

	for projectileType,
		config in pairs(
			ProjectileConfigs
		) do

		if typeof(config) == "table"
			and typeof(
				config.NinjaBag
			) == "table" then

			InventoryService.SetAmount(
				player,
				projectileType,
				InventoryService.GetMaxAmount(
					player,
					projectileType
				)
			)
		end
	end
end

Players.PlayerAdded:
	Connect(
		function(
			player: Player
		)

			NinjaBagService.InitializePlayer(
				player
			)
		end
	)

for _,
	player in ipairs(
		Players:GetPlayers()
	) do

	NinjaBagService.InitializePlayer(
		player
	)
end

print(
	"[NinjaBagService] READY v2.1"
		.. " | Slots=4"
		.. " | EquippedBagRequired=ON"
		.. " | InventoryServiceBridge=ON"
)

return NinjaBagService
