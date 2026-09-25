--!strict
-- EquipmentServer v1 - Server Authoritative Equipment Mutations
-- ServerScriptService > EquipmentServer [Script]

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

local EquipmentService =
	require(
		script.Parent:
		WaitForChild(
			"EquipmentService"
		)
	)

local remotes =
	ReplicatedStorage:
	FindFirstChild(
		"EquipmentRemotes"
	)

if not remotes then
	remotes =
		Instance.new(
			"Folder"
		)

	remotes.Name =
		"EquipmentRemotes"

	remotes.Parent =
		ReplicatedStorage
end

local function getRemote(
	name: string
): RemoteEvent

	local existing =
		remotes:
		FindFirstChild(
			name
		)

	if existing
		and existing:IsA(
			"RemoteEvent"
		) then

		return existing
	end

	if existing then
		existing:
			Destroy()
	end

	local remote =
		Instance.new(
			"RemoteEvent"
		)

	remote.Name =
		name

	remote.Parent =
		remotes

	return remote
end

local equipRequest =
	getRemote(
		"EquipRequest"
	)

local equipResult =
	getRemote(
		"EquipResult"
	)

local lastRequestAt: {[Player]: number} =
	{}

local REQUEST_DEBOUNCE =
	0.10

local function blockedReason(
	player: Player
): string?

	local character =
		player.Character

	if not character then
		return "no character"
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then
		return "character unavailable"
	end

	if character:GetAttribute(
		"CombatTagged"
		) == true then
		return "CombatTagged"
	end

	if character:GetAttribute(
		"DownedActionLocked"
		) == true
			or character:GetAttribute(
				"IsDowned"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true
			or character:GetAttribute(
				"IsCarrying"
			) == true
			or character:GetAttribute(
				"IsExecuting"
			) == true then

		return "character action locked"
	end

	return nil
end

equipRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			slotValue: any,
			itemValue: any
		)

			local now =
			time()

			local previous =
			lastRequestAt[
			player
			] or -math.huge

			if now - previous <
				REQUEST_DEBOUNCE then
				return
			end

			lastRequestAt[
			player
			] =
			now

			if typeof(slotValue) ~=
				"string" then

				equipResult:
				FireClient(
					player,
					false,
					nil,
					nil,
					"invalid slot"
				)

				return
			end

			local definition =
			InventoryCatalog.GetEquipmentSlotDefinition(
				slotValue
			)

			if not definition
				or definition.Active ~=
				true then

				equipResult:
				FireClient(
					player,
					false,
					slotValue,
					nil,
					"slot inactive"
				)

				return
			end

			local block =
			blockedReason(
				player
			)

			if block then
				equipResult:
				FireClient(
					player,
					false,
					slotValue,
					nil,
					block
				)
				return
			end

			local itemId: string? =
			nil

			if itemValue ~= nil
				and itemValue ~= "" then

				if typeof(itemValue) ~=
					"string" then

					equipResult:
					FireClient(
						player,
						false,
						slotValue,
						nil,
						"invalid item"
					)

					return
				end

				local item =
				InventoryCatalog.GetItem(
					itemValue
				)

				if not item
					or item.EquipmentSlot ~=
					slotValue then

					equipResult:
					FireClient(
						player,
						false,
						slotValue,
						itemValue,
						"item does not fit slot"
					)

					return
				end

				if player:GetAttribute(
					"InventoryUnlocked_"
					.. itemValue
					) == false then

					equipResult:
					FireClient(
						player,
						false,
						slotValue,
						itemValue,
						"item locked"
					)

					return
				end

				if InventoryService.GetAmount(
					player,
					itemValue
					) <= 0 then

					equipResult:
					FireClient(
						player,
						false,
						slotValue,
						itemValue,
						"item not owned"
					)

					return
				end

				itemId =
				itemValue
			end

			local success,
			reason =
			EquipmentService.SetEquipped(
				player,
				slotValue,
				itemId
			)

			equipResult:
			FireClient(
				player,
				success,
				slotValue,
				itemId,
				reason
			)

			if success then
				print(
					"[EquipmentServer] EQUIP",
					player.Name,
					slotValue,
					"->",
					itemId or "EMPTY"
				)
			end
		end
	)

print(
	"[EquipmentServer] READY v1"
		.. " | CombatTagMutationLock=ON"
)
