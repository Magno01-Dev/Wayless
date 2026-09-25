--!strict
-- ServerScriptService > InventoryPersistenceBootstrap
--
-- Starts slot-aware inventory persistence after the current inventory,
-- equipment and Ninja Bag backends have initialized.

local Players =
	game:GetService(
		"Players"
	)

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

-- Requiring these first guarantees their PlayerAdded initialization paths
-- are registered before persistence attempts to restore saved data.
require(
	ServerScriptService:
		WaitForChild(
			"InventoryService"
		)
)

require(
	ServerScriptService:
		WaitForChild(
			"EquipmentService"
		)
)

require(
	ServerScriptService:
		WaitForChild(
			"NinjaBagService"
		)
)

local InventoryPersistenceService =
	require(
		ServerScriptService:
		WaitForChild(
			"InventoryPersistenceService"
		)
	)

local function load(
	player: Player
)
	task.spawn(
		function()
			local ok,
			reason =
				InventoryPersistenceService
				.LoadPlayer(
					player
				)

			if not ok then
				warn(
					"[InventoryPersistenceBootstrap] LOAD",
					player.Name,
					reason
				)
			end
		end
	)
end

for _, player in ipairs(
	Players:GetPlayers()
	) do
	load(
		player
	)
end

Players.PlayerAdded:
	Connect(
		load
	)

Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)
			InventoryPersistenceService
			.UnloadPlayer(
				player
			)
		end
	)

print(
	"[InventoryPersistenceBootstrap] READY v1"
		.. " | SlotAware=ON"
		.. " | ForcedInventory=OFF"
)
