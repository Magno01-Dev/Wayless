--!strict
-- ServerScriptService > InventoryItemActionsServer
--
-- Provides a generic server gateway for inventory item contextual actions.
-- Current goal:
--   - fully support Lock / Unlock immediately
--   - reserve Consume / Drop for your authoritative inventory backend
--   - never trust the client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryCatalog = require(ReplicatedStorage:WaitForChild("InventoryCatalog"))

local function tryRequire(parent: Instance, childName: string): any?
	local child = parent:FindFirstChild(childName)
	if not child or not child:IsA("ModuleScript") then
		return nil
	end

	local ok, result = pcall(require, child)
	if ok then
		return result
	end

	warn("[InventoryItemActions] Could not require", childName, result)
	return nil
end

local InventoryService = tryRequire(script.Parent, "InventoryService")
local ConsumableService = tryRequire(script.Parent, "ConsumableService")

local FOLDER_NAME = "InventoryActionRemotes"
local REQUEST_NAME = "RequestAction"

local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
end

local requestRemote = folder:FindFirstChild(REQUEST_NAME)
if requestRemote and not requestRemote:IsA("RemoteFunction") then
	requestRemote:Destroy()
	requestRemote = nil
end
if not requestRemote then
	requestRemote = Instance.new("RemoteFunction")
	requestRemote.Name = REQUEST_NAME
	requestRemote.Parent = folder
end

local RequestAction = requestRemote :: RemoteFunction

local REQUEST_COOLDOWN = 0.10
local lastRequestAt: {[Player]: number} = {}

local function amountAttr(itemId: string): string
	return "InventoryAmount_" .. itemId
end

local function lockAttr(itemId: string): string
	return "InventoryLocked_" .. itemId
end

local function isLocked(player: Player, itemId: string): boolean
	return player:GetAttribute(lockAttr(itemId)) == true
end

local function getAmount(player: Player, itemId: string): number
	local value = player:GetAttribute(amountAttr(itemId))
	if typeof(value) ~= "number" then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function success(payload: {[string]: any}?): {[string]: any}
	local result = payload or {}
	result.Ok = true
	return result
end

local function failure(reason: string, payload: {[string]: any}?): {[string]: any}
	local result = payload or {}
	result.Ok = false
	result.Reason = reason
	return result
end

local function setLocked(player: Player, itemId: string, locked: boolean): {[string]: any}
	player:SetAttribute(lockAttr(itemId), locked)

	if InventoryService then
		if typeof(InventoryService.SetItemLocked) == "function" then
			pcall(InventoryService.SetItemLocked, player, itemId, locked)
		elseif typeof(InventoryService.SetLocked) == "function" then
			pcall(InventoryService.SetLocked, player, itemId, locked)
		end
	end

	return success({ Locked = locked })
end

local function handleConsume(player: Player, itemId: string): {[string]: any}
	if getAmount(player, itemId) <= 0 then
		return failure("ItemUnavailable")
	end

	if ConsumableService and typeof(ConsumableService.Consume) == "function" then
		local ok, result = pcall(ConsumableService.Consume, player, itemId, 1)
		if ok then
			if result == true or (typeof(result) == "table" and result.Ok == true) then
				return success(typeof(result) == "table" and result or nil)
			end
			if typeof(result) == "table" and typeof(result.Reason) == "string" then
				return failure(result.Reason, result)
			end
			return failure("ConsumeDenied")
		end
		warn("[InventoryItemActions] Consume backend error:", result)
		return failure("ConsumeBackendError")
	end

	return failure("ConsumePendingBackend")
end

local function handleDrop(player: Player, itemId: string): {[string]: any}
	if isLocked(player, itemId) then
		return failure("Locked")
	end

	if getAmount(player, itemId) <= 0 then
		return failure("ItemUnavailable")
	end

	if InventoryService then
		if typeof(InventoryService.DropItem) == "function" then
			local ok, result = pcall(InventoryService.DropItem, player, itemId, 1)
			if ok then
				if result == true or (typeof(result) == "table" and result.Ok == true) then
					return success(typeof(result) == "table" and result or nil)
				end
				if typeof(result) == "table" and typeof(result.Reason) == "string" then
					return failure(result.Reason, result)
				end
				return failure("DropDenied")
			end
			warn("[InventoryItemActions] Drop backend error:", result)
			return failure("DropBackendError")
		end

		if typeof(InventoryService.RemoveItem) == "function" then
			local ok, result = pcall(InventoryService.RemoveItem, player, itemId, 1)
			if ok then
				if result == true or result == nil or (typeof(result) == "table" and result.Ok == true) then
					return success(typeof(result) == "table" and result or nil)
				end
				if typeof(result) == "table" and typeof(result.Reason) == "string" then
					return failure(result.Reason, result)
				end
				return failure("DropDenied")
			end
			warn("[InventoryItemActions] RemoveItem backend error:", result)
			return failure("DropBackendError")
		end
	end

	return failure("DropPendingBackend")
end

local function validateCharacterState(player: Player): string?
	local character = player.Character
	if not character then
		return "NoCharacter"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return "CharacterUnavailable"
	end

	if character:GetAttribute("CombatTagged") == true then
		return "CombatTagged"
	end

	if character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsCarrying") == true
		or character:GetAttribute("IsExecuting") == true then
		return "CharacterActionLocked"
	end

	return nil
end

function RequestAction.OnServerInvoke(player: Player, actionId: any, payload: any)
	if typeof(actionId) ~= "string" then
		return failure("InvalidAction")
	end

	local now = time()
	local previous = lastRequestAt[player] or -math.huge
	if now - previous < REQUEST_COOLDOWN then
		return failure("RequestThrottled")
	end
	lastRequestAt[player] = now

	if typeof(payload) ~= "table" then
		return failure("InvalidPayload")
	end

	local itemId = payload.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return failure("InvalidItem")
	end

	local definition = InventoryCatalog.GetItem(itemId)
	if not definition then
		return failure("UnknownItem")
	end

	local blocked = validateCharacterState(player)
	if blocked then
		return failure(blocked)
	end

	if actionId == "SetLocked" then
		local locked = payload.Locked == true
		return setLocked(player, itemId, locked)
	elseif actionId == "Consume" then
		return handleConsume(player, itemId)
	elseif actionId == "Drop" then
		return handleDrop(player, itemId)
	end

	return failure("UnsupportedAction")
end

print("[InventoryItemActions] READY v1 | Lock=ON | Consume=BACKEND_OPTIONAL | Drop=BACKEND_OPTIONAL")
