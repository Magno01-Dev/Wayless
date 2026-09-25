--!strict
-- ServerScriptService > AccountProfileDevTools
--
-- WAYLESS Account / Character Slot + Lifecycle QA gateway v7.1 Dead Slot Return syntax fix.
-- SINGLE canonical gateway. Replace the old AccountProfileDevTools with this script.
-- Adds safe QA-life creation and NEXT-PLAY slot selection.
-- Active gameplay sessions remain slot-locked.

print("[AccountProfileDevTools] BOOT v7.1 DeadSlotReturn")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local DeveloperAccessService = require(Services:WaitForChild("DeveloperAccessService"))
local AccountProfileService = require(Services:WaitForChild("AccountProfileService"))
local CharacterSlotContextService = require(Services:WaitForChild("CharacterSlotContextService"))
local CharacterLifecycleService = require(Services:WaitForChild("CharacterLifecycleService"))
local AfterlifeTransferService = require(Services:WaitForChild("AfterlifeTransferService"))

DeveloperAccessService.Start()
AccountProfileService.Start()
CharacterSlotContextService.Start()

local commonRemotes = ReplicatedStorage:FindFirstChild("CommonRemotes")
if not commonRemotes then
	commonRemotes = Instance.new("Folder")
	commonRemotes.Name = "CommonRemotes"
	commonRemotes.Parent = ReplicatedStorage
end

local existing = commonRemotes:FindFirstChild("AccountProfileDevRequest")
local request: RemoteFunction

if existing and existing:IsA("RemoteFunction") then
	request = existing
elseif existing then
	existing:Destroy()
	request = Instance.new("RemoteFunction")
	request.Name = "AccountProfileDevRequest"
	request.Parent = commonRemotes
else
	request = Instance.new("RemoteFunction")
	request.Name = "AccountProfileDevRequest"
	request.Parent = commonRemotes
end

local ALLOWED_CURRENCIES = {
	ClanRerolls = true,
	NatureRerolls = true,
	RevivalTokens = true,
}

local WIPE_CONFIRM_WINDOW = 15

type WipeArm = {
	SlotId: string,
	LifeId: string,
	ExpiresAt: number,
}

local wipeArms: {[Player]: WipeArm} = {}

local function getWipeArm(player: Player): (boolean, number)
	local arm = wipeArms[player]
	if not arm then
		return false, 0
	end

	local remaining = arm.ExpiresAt - os.clock()
	if remaining <= 0 then
		wipeArms[player] = nil
		return false, 0
	end

	return true, math.ceil(remaining)
end

Players.PlayerRemoving:Connect(function(player: Player)
	wipeArms[player] = nil
end)

local function fail(reason: string)
	return {
		Ok = false,
		Reason = reason,
	}
end

local function buildResponse(
	player: Player,
	ok: boolean,
	reason: string,
	slotId: string?,
	extra: {[string]: any}?
)
	local wipeArmed, wipeSecondsRemaining =
		getWipeArm(player)

	local response = {
		Ok = ok,
		Reason = reason,
		SlotId = slotId,
		Snapshot = AccountProfileService.GetSnapshot(player),
		ActiveSlotId = player:GetAttribute("CharacterActiveSlotId"),
		SelectionSource = player:GetAttribute("CharacterSlotSelectionSource"),
		NextStudioSlotId = CharacterSlotContextService.GetStudioPreferredSlot(player),
		WipeArmed = wipeArmed,
		WipeSecondsRemaining = wipeSecondsRemaining,
		RequiresRejoin = player:GetAttribute("CharacterLifecycleMustExitSession") == true,
	}

	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			response[key] = value
		end
	end

	return response
end

local function payloadSlotId(payload: any): string?
	if typeof(payload) ~= "table" then
		return nil
	end
	local raw = payload.SlotId
	if raw == nil then
		return nil
	end
	return tostring(raw)
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	print(
		"[AccountProfileDevTools] REQUEST",
		player.Name,
		"Action=" .. tostring(action),
		"Slot=" .. tostring(typeof(payload) == "table" and payload.SlotId or "-")
	)

	if action == "CanUse" then
		return DeveloperAccessService.IsDeveloper(player)
	end

	if not DeveloperAccessService.IsDeveloper(player) then
		return fail("DeveloperOnly")
	end

	if typeof(action) ~= "string" then
		return fail("InvalidAction")
	end

	if not AccountProfileService.IsReady(player) then
		return fail("AccountProfileNotReady")
	end

	if action == "GetSnapshot" then
		return buildResponse(player, true, "SnapshotReady", nil)
	end

	if action == "GrantChuuninSlot" then
		local ok, reason, slotId = AccountProfileService.GrantProgressionSlot(player, "Chuunin")
		return buildResponse(player, ok, reason, slotId)
	end

	if action == "GrantJoninSlot" then
		local ok, reason, slotId = AccountProfileService.GrantProgressionSlot(player, "Jonin")
		return buildResponse(player, ok, reason, slotId)
	end

	if action == "GrantPurchasedSlot" then
		local ok, reason, slotId = AccountProfileService.GrantPurchasedSlot(player)
		return buildResponse(player, ok, reason, slotId)
	end

	if action == "CreateTestLife" then
		local slotId = payloadSlotId(payload)
		if not slotId then
			return fail("InvalidSlotId")
		end

		local activeSlotId = tostring(player:GetAttribute("CharacterActiveSlotId") or "")
		if activeSlotId == slotId
			and player:GetAttribute("CharacterLifecycleMustExitSession") == true then

			return buildResponse(
				player,
				false,
				"UseCreateNextLifeAfterWipe",
				slotId
			)
		end

		local slot = AccountProfileService.GetSlot(player, slotId)
		if not slot then
			return fail("SlotNotUnlocked")
		end

		if slot.State == "Alive" and typeof(slot.CurrentLife) == "table" then
			return buildResponse(player, true, "SlotAlreadyAlive", slotId)
		end

		local beginOk, beginReason = AccountProfileService.BeginCharacterCreation(player, slotId)
		if not beginOk then
			return buildResponse(player, false, beginReason, slotId)
		end

		local commitOk, commitReason = AccountProfileService.CommitNewLifeMetadata(
			player,
			slotId,
			{
				QA = true,
				CreatedBy = "AccountProfileDevTools_v5",
			}
		)

		return buildResponse(player, commitOk, commitReason, slotId)
	end

	if action == "MarkFinalDeath" then
		local activeSlotId =
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
				or ""
			)

		if activeSlotId == "" then
			return fail("ActiveSlotNotResolved")
		end

		local ok, reason =
			CharacterLifecycleService.MarkFinalDeath(
				player,
				"AccountSlotsQA"
			)

		wipeArms[player] = nil
		return buildResponse(
			player,
			ok,
			reason,
			activeSlotId
		)
	end

	if action == "ReviveCurrentLife" then
		local activeSlotId =
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
				or ""
			)

		if activeSlotId == "" then
			return fail("ActiveSlotNotResolved")
		end

		local ok, reason =
			CharacterLifecycleService.ReviveCurrentLife(
				player,
				"AccountSlotsQA"
			)

		wipeArms[player] = nil
		return buildResponse(
			player,
			ok,
			reason,
			activeSlotId
		)
	end

	if action == "ArmFinalWipe" then
		local activeSlotId =
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
				or ""
			)

		if activeSlotId == "" then
			return fail("ActiveSlotNotResolved")
		end

		local slot =
			AccountProfileService.GetSlot(
				player,
				activeSlotId
			)

		if not slot then
			return fail("SlotNotUnlocked")
		end

		if slot.State ~= "DeadAwaitingDecision" then
			return buildResponse(
				player,
				false,
				"LifeNotAwaitingDecision",
				activeSlotId
			)
		end

		local life = slot.CurrentLife
		if typeof(life) ~= "table"
			or typeof(life.LifeId) ~= "string"
			or life.LifeId == "" then

			return buildResponse(
				player,
				false,
				"NoCurrentLife",
				activeSlotId
			)
		end

		wipeArms[player] = {
			SlotId = activeSlotId,
			LifeId = life.LifeId,
			ExpiresAt = os.clock() + WIPE_CONFIRM_WINDOW,
		}

		return buildResponse(
			player,
			true,
			"WipeArmedConfirmWithin15s",
			activeSlotId,
			{
				ArmedLifeId = life.LifeId,
			}
		)
	end

	if action == "CancelFinalWipe" then
		wipeArms[player] = nil
		return buildResponse(
			player,
			true,
			"WipeDisarmed",
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
					or ""
			)
		)
	end

	if action == "ConfirmFinalWipe" then
		local arm = wipeArms[player]
		if not arm or arm.ExpiresAt <= os.clock() then
			wipeArms[player] = nil
			return buildResponse(
				player,
				false,
				"WipeNotArmedOrExpired",
				tostring(
					player:GetAttribute("CharacterActiveSlotId")
						or ""
				)
			)
		end

		local activeSlotId =
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
				or ""
			)

		if activeSlotId ~= arm.SlotId then
			wipeArms[player] = nil
			return buildResponse(
				player,
				false,
				"ActiveSlotChanged",
				activeSlotId
			)
		end

		local slot =
			AccountProfileService.GetSlot(
				player,
				activeSlotId
			)

		local life = slot and slot.CurrentLife or nil
		if not slot
			or slot.State ~= "DeadAwaitingDecision"
			or typeof(life) ~= "table"
			or life.LifeId ~= arm.LifeId then

			wipeArms[player] = nil
			return buildResponse(
				player,
				false,
				"WipeTargetChanged",
				activeSlotId
			)
		end

		local oldLifeId = arm.LifeId
		local oldCharacterId = life.CharacterId

		local ok, reason =
			CharacterLifecycleService.RequestFinalWipe(
				player,
				"AccountSlotsQAConfirmed"
			)

		wipeArms[player] = nil

		return buildResponse(
			player,
			ok,
			reason,
			activeSlotId,
			{
				ArchivedLifeId = oldLifeId,
				ArchivedCharacterId = oldCharacterId,
				RequiresRejoin = ok,
			}
		)
	end

	if action == "CreateNextLifeAfterWipe" then
		local activeSlotId =
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
				or ""
			)

		if activeSlotId == "" then
			return fail("ActiveSlotNotResolved")
		end

		if player:GetAttribute("CharacterLifecycleMustExitSession") ~= true then
			return buildResponse(
				player,
				false,
				"WipeNotFinalizedThisSession",
				activeSlotId
			)
		end

		local slot =
			AccountProfileService.GetSlot(
				player,
				activeSlotId
			)

		if not slot then
			return fail("SlotNotUnlocked")
		end

		if slot.State ~= "Empty"
			and slot.State ~= "Creating" then

			return buildResponse(
				player,
				false,
				"SlotNotReadyForNewLife",
				activeSlotId
			)
		end

		local beginOk, beginReason =
			AccountProfileService.BeginCharacterCreation(
				player,
				activeSlotId
			)

		if not beginOk then
			return buildResponse(
				player,
				false,
				beginReason,
				activeSlotId
			)
		end

		local commitOk, commitReason, newLifeId =
			AccountProfileService.CommitNewLifeMetadata(
				player,
				activeSlotId,
				{
					QA = true,
					CreatedBy = "AccountProfileDevTools_v5",
					CreationPath = "PostWipeQA",
				}
			)

		if not commitOk then
			return buildResponse(
				player,
				false,
				commitReason,
				activeSlotId
			)
		end

		local newSlot =
			AccountProfileService.GetSlot(
				player,
				activeSlotId
			)

		local newLife =
			newSlot and newSlot.CurrentLife or nil

		local preferenceOk, preferenceReason =
			CharacterSlotContextService.SetStudioPreferredSlot(
				player,
				activeSlotId
			)

		player:SetAttribute(
			"CharacterLifecyclePendingNextLifeId",
			newLifeId
		)

		return buildResponse(
			player,
			commitOk and preferenceOk,
			preferenceOk
				and "NewLifeCreatedStopAndRejoin"
				or ("NewLifeCreatedButNextPlayFailed:" .. preferenceReason),
			activeSlotId,
			{
				NewLifeId = newLifeId,
				NewCharacterId =
					typeof(newLife) == "table"
					and newLife.CharacterId
					or nil,
				RequiresRejoin = true,
			}
		)
	end

	if action == "EnterAfterlife" then
		local activeSlotId =
			tostring(
				player:GetAttribute("CharacterActiveSlotId")
				or ""
			)

		if activeSlotId == "" then
			return fail("ActiveSlotNotResolved")
		end

		local slot =
			AccountProfileService.GetSlot(
				player,
				activeSlotId
			)

		if not slot then
			return fail("SlotNotUnlocked")
		end

		local ok: boolean
		local reason: string

		if slot.State == "Alive" then
			ok, reason =
				AfterlifeTransferService.HandleFinalDeath(
					player,
					"F7AfterlifeQA"
				)
		elseif slot.State == "DeadAwaitingDecision" then
			ok, reason =
				AfterlifeTransferService.SendDeadLife(
					player,
					"F7AfterlifeQA"
				)
		else
			return buildResponse(
				player,
				false,
				"SlotCannotEnterAfterlife:" .. tostring(slot.State),
				activeSlotId
			)
		end

		return buildResponse(
			player,
			ok,
			reason,
			activeSlotId,
			{
				AfterlifeTransfer =
					ok == true,
			}
		)
	end

	if action == "ReturnDeadSlotToAfterlife" then
		local slotId =
			payloadSlotId(
				payload
			)

		if not slotId then
			return fail(
				"InvalidSlotId"
			)
		end

		local slot =
			AccountProfileService.GetSlot(
				player,
				slotId
			)

		if not slot then
			return buildResponse(
				player,
				false,
				"SlotNotUnlocked",
				slotId
			)
		end

		if slot.State ~= "DeadAwaitingDecision"
			or typeof(slot.CurrentLife) ~= "table" then

			return buildResponse(
				player,
				false,
				"LifeNotAwaitingDecision",
				slotId
			)
		end

		local ok,
			reason =
			AfterlifeTransferService.SendDeadSlot(
				player,
				slotId,
				"F7ReturnDeadSlot"
			)

		return buildResponse(
			player,
			ok,
			reason,
			slotId,
			{
				AfterlifeTransfer =
					ok == true,
			}
		)
	end

	if action == "SetNextSessionSlot" then
		local slotId = payloadSlotId(payload)
		if not slotId then
			return fail("InvalidSlotId")
		end

		local ok, reason = CharacterSlotContextService.SetStudioPreferredSlot(player, slotId)
		return buildResponse(player, ok, reason, slotId)
	end

	if action == "ClearNextSessionSlot" then
		local ok, reason = CharacterSlotContextService.ClearStudioPreferredSlot(player)
		return buildResponse(player, ok, reason, nil)
	end

	if action == "GrantCurrency" then
		if typeof(payload) ~= "table" then
			return fail("InvalidPayload")
		end

		local currencyId = payload.CurrencyId
		local amount = payload.Amount

		if typeof(currencyId) ~= "string" or ALLOWED_CURRENCIES[currencyId] ~= true then
			return fail("UnknownCurrency")
		end

		if typeof(amount) ~= "number"
			or amount <= 0
			or amount ~= math.floor(amount)
			or amount > 100 then
			return fail("InvalidAmount")
		end

		local ok, reason = AccountProfileService.GrantCurrency(player, currencyId, amount)
		return buildResponse(player, ok, reason, nil)
	end

	if action == "Save" then
		local ok = AccountProfileService.SavePlayer(player, "DevPanelManualSave")
		return buildResponse(player, ok, ok and "Saved" or "SaveFailed", nil)
	end

	return fail("UnknownAction")
end

print(
	"[AccountProfileDevTools] READY v7.1 DeadSlotReturn"
		.. " | DeveloperOnly=ON"
		.. " | CreateQALife=ON"
		.. " | LifecycleQA=FinalDeath+Revive+DoubleConfirmWipe+NewLife"
		.. " | DeadSlotReturnToAfterlife=ON"
		.. " | NextPlaySlotSelection=ON"
		.. " | HotSwitch=OFF"
)
