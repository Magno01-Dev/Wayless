--!strict
-- ServerScriptService > FrontendCharacterDeleteBootstrap
-- WAYLESS Frontend character delete-to-Afterlife v2.
--
-- Provides a dedicated server-authoritative delete endpoint for the slot UI.
-- IMPORTANT: the selector's DELETE action is NOT a final wipe.
-- It only marks the current life as a final death:
--   Alive -> MarkFinalDeath -> DeadAwaitingDecision (Afterlife)
--
-- The actual Revive / Wipe decision remains inside the Afterlife flow.
-- No child datastore is detached and no slot is returned to Empty here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local AccountProfileService = require(Services:WaitForChild("AccountProfileService"))

local deleteBusy: {[Player]: boolean} = {}

local function snapshotResponse(player: Player, ok: boolean, reason: string): {[string]: any}
	return {
		Ok = ok,
		Reason = reason,
		Ready = AccountProfileService.IsReady(player),
		FocusSlotId = nil,
		Snapshot = AccountProfileService.GetSnapshot(player),
	}
end

local function ensureRemote(): RemoteFunction
	local system = ReplicatedStorage:FindFirstChild("FrontendSystem")
	if not system then
		system = Instance.new("Folder")
		system.Name = "FrontendSystem"
		system.Parent = ReplicatedStorage
	end

	local remotes = system:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = system
	end

	local existing = remotes:FindFirstChild("DeleteCharacterRequest")
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "DeleteCharacterRequest"
	remote.Parent = remotes
	return remote
end

-- Structured wrapper so mutation reasons are preserved exactly.
local function handleDelete(player: Player, payload: any): {[string]: any}
	if deleteBusy[player] then
		return snapshotResponse(player, false, "DeleteAlreadyPending")
	end

	if player:GetAttribute("FrontendTeleporting") == true then
		return snapshotResponse(player, false, "TeleportInProgress")
	end

	if typeof(payload) ~= "table" then
		return snapshotResponse(player, false, "InvalidPayload")
	end

	if payload.Confirmation ~= "DELETE" then
		return snapshotResponse(player, false, "DeleteConfirmationMismatch")
	end

	if payload.SlotId == nil then
		return snapshotResponse(player, false, "SlotMissing")
	end

	local slotId = tostring(payload.SlotId)

	AccountProfileService.Start()
	if not AccountProfileService.IsReady(player) then
		return snapshotResponse(player, false, "AccountProfileNotReady")
	end

	local slot = AccountProfileService.GetSlot(player, slotId)
	if not slot then
		return snapshotResponse(player, false, "SlotNotUnlocked")
	end

	if typeof(slot.CurrentLife) ~= "table" then
		return snapshotResponse(player, false, "NoCurrentLife")
	end

	local state = tostring(slot.State or "")
	if state ~= AccountProfileService.SlotStates.Alive
		and state ~= AccountProfileService.SlotStates.DeadAwaitingDecision then

		return snapshotResponse(player, false, "SlotNotDeletable")
	end

	deleteBusy[player] = true

	local callOk, deleteOk, deleteReason = pcall(function(): (boolean, string)
		-- Idempotent server behavior: if a retry arrives after the first request
		-- already moved the slot to Afterlife, treat it as success.
		if state == AccountProfileService.SlotStates.DeadAwaitingDecision then
			return true, "AlreadyInAfterlife"
		end

		local deathOk, deathReason = AccountProfileService.MarkFinalDeath(player, slotId)
		if not deathOk then
			return false, deathReason
		end

		return true, "SentToAfterlife"
	end)

	deleteBusy[player] = nil

	if not callOk then
		warn("[FrontendCharacterDelete] INTERNAL ERROR", player.Name, slotId, deleteOk)
		return snapshotResponse(player, false, "DeleteInternalError")
	end

	if deleteOk ~= true then
		warn("[FrontendCharacterDelete] REJECTED", player.Name, slotId, deleteReason)
		return snapshotResponse(player, false, tostring(deleteReason or "DeleteFailed"))
	end

	if tostring(player:GetAttribute("FrontendFocusSlotId") or "") == slotId then
		player:SetAttribute("FrontendFocusSlotId", nil)
	end

	print("[FrontendCharacterDelete] SENT_TO_AFTERLIFE", player.Name, "Slot=" .. slotId)
	return snapshotResponse(player, true, tostring(deleteReason or "SentToAfterlife"))
end

local remote = ensureRemote()
remote.OnServerInvoke = handleDelete

Players.PlayerRemoving:Connect(function(player)
	deleteBusy[player] = nil
end)

print("[FrontendCharacterDelete] READY v2 | DELETE=>AFTERLIFE | ExactDELETE=ON | FinalWipe=OFF")
