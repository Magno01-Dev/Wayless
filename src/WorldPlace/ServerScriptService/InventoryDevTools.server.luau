--!strict
-- ServerScriptService > InventoryDevTools
--
-- WAYLESS Inventory Dev Tools v1
--
-- Developer-only inventory mutation gateway.
-- Normal players never receive inventory through this remote.
--
-- Actions:
-- AddItem
-- SetItem
-- Save
--
-- All mutations use InventoryService and therefore respect configured max
-- amounts and Ninja Bag capacity.

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

local DeveloperAccessService =
	require(
		ServerScriptService:
		WaitForChild(
			"Services"
		):
		WaitForChild(
			"DeveloperAccessService"
		)
	)

local InventoryService =
	require(
		ServerScriptService:
		WaitForChild(
			"InventoryService"
		)
	)

local InventoryPersistenceService =
	require(
		ServerScriptService:
		WaitForChild(
			"InventoryPersistenceService"
		)
	)

DeveloperAccessService.Start()

local remotes =
	ReplicatedStorage:
	FindFirstChild(
		"InventoryDevRemotes"
	)

if not remotes then
	remotes =
		Instance.new(
			"Folder"
		)

	remotes.Name =
		"InventoryDevRemotes"

	remotes.Parent =
		ReplicatedStorage
end

local existing =
	remotes:
	FindFirstChild(
		"Request"
	)

local request: RemoteFunction

if existing
	and existing:IsA(
		"RemoteFunction"
	) then

	request =
		existing
else
	if existing then
		existing:Destroy()
	end

	request =
		Instance.new(
			"RemoteFunction"
		)

	request.Name =
		"Request"

	request.Parent =
		remotes
end

local function validAmount(
	value: any
): number?
	if typeof(value) ~=
		"number"
		or value ~= value
		or value == math.huge
		or value == -math.huge then

		return nil
	end

	return math.floor(
		value
	)
end

request.OnServerInvoke =
	function(
		player: Player,
		action: any,
		payload: any
	)
	if not DeveloperAccessService
		.IsDeveloper(
			player
		) then

		return {
			Ok = false,
			Reason = "NotDeveloper",
		}
	end

	if typeof(action) ~=
		"string" then

		return {
			Ok = false,
			Reason = "InvalidAction",
		}
	end

	if action == "Save" then
		local ok,
			reason =
			InventoryPersistenceService
			.SavePlayer(
				player,
				"DeveloperManualSave"
			)

		return {
			Ok = ok,
			Reason = reason,
		}
	end

	if action == "AddItem"
		or action == "SetItem" then

		if not InventoryPersistenceService
			.IsReady(
				player
			) then

			return {
				Ok = false,
				Reason =
					"InventoryPersistenceNotReady",
			}
		end

		if typeof(payload) ~=
			"table" then

			return {
				Ok = false,
				Reason = "InvalidPayload",
			}
		end

		local itemId =
			payload.ItemId

		local amount =
			validAmount(
				payload.Amount
			)

		if typeof(itemId) ~=
			"string"
			or itemId == ""
			or amount == nil then

			return {
				Ok = false,
				Reason = "InvalidItemOrAmount",
			}
		end

		local ok: boolean
		local finalAmount: number
		local reason: string

		if action ==
			"AddItem" then

			ok,
				finalAmount,
				reason =
				InventoryService.Add(
					player,
					itemId,
					amount
				)
		else
			ok,
				finalAmount,
				reason =
				InventoryService.SetAmount(
					player,
					itemId,
					amount
				)
		end

		if ok then
			local saveOk =
				InventoryPersistenceService
				.SavePlayer(
					player,
					"DeveloperInventoryMutation"
				)

			return {
				Ok = true,
				Reason =
					saveOk
					and reason
					or (
						reason
						.. " / SavePending"
					),
				ItemId =
					itemId,
				Amount =
					finalAmount,
			}
		end

		return {
			Ok = false,
			Reason = reason,
			ItemId = itemId,
			Amount = finalAmount,
		}
	end

	return {
		Ok = false,
		Reason = "UnknownAction",
	}
end

print(
	"[InventoryDevTools] READY v1"
		.. " | DeveloperAccessService=ON"
		.. " | AddItem=ON"
		.. " | SetItem=ON"
		.. " | ImmediateSave=ON"
)

