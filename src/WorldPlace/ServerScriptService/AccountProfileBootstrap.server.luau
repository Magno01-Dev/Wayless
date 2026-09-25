--!strict
-- ServerScriptService > AccountProfileBootstrap
--
-- WAYLESS Account Profile migration bootstrap v1.1.
-- Slot 1 legacy import is now explicitly gated to an ACTIVE Slot 1 session.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local AccountProfileService = require(Services:WaitForChild("AccountProfileService"))
local CharacterOriginService = require(Services:WaitForChild("CharacterOriginService"))
local CharacterSlotContextService = require(Services:WaitForChild("CharacterSlotContextService"))

local WAIT_TIMEOUT = 20

AccountProfileService.Start()
CharacterSlotContextService.Start()

local function waitUntilReady(player: Player): boolean
	local deadline = time() + WAIT_TIMEOUT

	while player.Parent and time() < deadline do
		if AccountProfileService.IsReady(player)
			and player:GetAttribute("CharacterSlotContextReady") == true
			and player:GetAttribute("CharacterOriginReady") == true then
			return true
		end
		task.wait(0.1)
	end

	return player.Parent ~= nil
		and AccountProfileService.IsReady(player)
		and player:GetAttribute("CharacterSlotContextReady") == true
		and player:GetAttribute("CharacterOriginReady") == true
end

local function migratePlayer(player: Player)
	task.spawn(function()
		if not waitUntilReady(player) then
			warn("[AccountProfileBootstrap] MIGRATION WAIT TIMEOUT", player.Name)
			return
		end

		local activeSlotId = CharacterSlotContextService.GetActiveSlotId(player)
		if activeSlotId ~= "1" then
			print(
				"[AccountProfileBootstrap] SLOT 1 MIGRATION SKIPPED",
				player.Name,
				"ActiveSlot=" .. activeSlotId
			)
			return
		end

		if not RunService:IsStudio()
			and player:GetAttribute("CharacterOriginPersistent") ~= true then
			warn(
				"[AccountProfileBootstrap] MIGRATION SKIPPED; legacy origin is not persistent",
				player.Name
			)
			return
		end

		local originData = CharacterOriginService.GetData(player)
		if not originData or tostring(originData.SlotId) ~= "1" then
			warn("[AccountProfileBootstrap] Slot 1 origin missing/mismatched", player.Name)
			return
		end

		local ok, reason = AccountProfileService.ImportLegacySlot1(player, originData)
		if not ok then
			warn("[AccountProfileBootstrap] SLOT 1 IMPORT FAILED", player.Name, reason)
			return
		end

		print(
			"[AccountProfileBootstrap] SLOT 1 READY",
			player.Name,
			reason,
			"Clan=" .. tostring(player:GetAttribute("AccountSlot_1_ClanId")),
			"Natures="
				.. tostring(player:GetAttribute("AccountSlot_1_Nature1Id"))
				.. "+"
				.. tostring(player:GetAttribute("AccountSlot_1_Nature2Id")),
			"State=" .. tostring(player:GetAttribute("AccountSlot_1_State"))
		)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	migratePlayer(player)
end

Players.PlayerAdded:Connect(migratePlayer)

print(
	"[AccountProfileBootstrap] READY v1.1"
		.. " | LegacySlot1Migration=ON"
		.. " | ActiveSlot1Gate=ON"
)
