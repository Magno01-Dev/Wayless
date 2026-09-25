--!strict
-- ServerScriptService > Services > AfterlifeTransferService
--
-- WAYLESS World -> Afterlife transfer v1.1 - dead-slot return routing.
--
-- Future final-death gameplay hook:
--   AfterlifeTransferService.HandleFinalDeath(player, reason)
--
-- The state transition is server-authoritative:
-- Alive -> DeadAwaitingDecision -> secure one-time handoff -> Afterlife Place.

local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperiencePlaceConfig =
	require(Shared:WaitForChild("ExperiencePlaceConfig"))

local Services =
	ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterSlotContextService =
	require(Services:WaitForChild("CharacterSlotContextService"))

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

local CharacterLifecycleService =
	require(Services:WaitForChild("CharacterLifecycleService"))

local CharacterHandoffService =
	require(Services:WaitForChild("CharacterHandoffService"))

local AfterlifeTransferService = {}

local function afterlifePlaceId(): number
	return tonumber(
		ExperiencePlaceConfig.AfterlifePlaceId
	) or 0
end

local function teleportDeadLife(
	player: Player,
	slotId: string,
	lifeId: string,
	reason: string
): (boolean, string)
	local placeId = afterlifePlaceId()

	if placeId <= 0 then
		return false,
			"AfterlifePlaceIdNotConfigured"
	end

	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot
		or slot.State ~= "DeadAwaitingDecision"
		or typeof(slot.CurrentLife) ~= "table" then

		return false,
			"LifeNotAwaitingDecision"
	end

	if tostring(slot.CurrentLife.LifeId) ~= lifeId then
		return false,
			"LifeIdentityMismatch"
	end

	local handoffOk,
		handoffReason,
		token =
		CharacterHandoffService.Create(
			player,
			"Afterlife",
			slotId,
			lifeId,
			{
				Reason = reason,
			}
		)

	if not handoffOk or not token then
		return false,
			handoffReason
	end

	local options =
		Instance.new("TeleportOptions")

	options:SetTeleportData({
		Flow = "WorldToAfterlife",
		HandoffToken = token,

		-- Hints only. Destination validates the MemoryStore handoff and
		-- AccountProfile before trusting them.
		CharacterSlotId = slotId,
	})

	local ok, err =
		pcall(function()
			TeleportService:TeleportAsync(
				placeId,
				{ player },
				options
			)
		end)

	if not ok then
		CharacterHandoffService.Revoke(token)

		warn(
			"[AfterlifeTransferService] TELEPORT FAILED",
			player.Name,
			err
		)

		return false,
			"AfterlifeTeleportFailed"
	end

	player:SetAttribute(
		"AfterlifeTransferStarted",
		true
	)

	return true,
		"AfterlifeTeleportStarted"
end

function AfterlifeTransferService.SendDeadLife(
	player: Player,
	reason: string?
): (boolean, string)
	AccountProfileService.Start()
	CharacterSlotContextService.Start()
	CharacterLifeContextService.Start()

	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	return teleportDeadLife(
		player,
		identity.SlotId,
		identity.LifeId,
		reason or "DeadLifeRouting"
	)
end

-- Routes ANY account slot that is already DeadAwaitingDecision back to the
-- Afterlife. This does not change the active World slot and does not revive,
-- wipe, or otherwise mutate the dead life.
--
-- Used by Frontend/QA slot selectors after the player chose LEAVE.
function AfterlifeTransferService.SendDeadSlot(
	player: Player,
	slotId: string,
	reason: string?
): (boolean, string)
	AccountProfileService.Start()

	if typeof(slotId) ~= "string"
		or slotId == "" then

		return false,
			"InvalidSlotId"
	end

	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot then
		return false,
			"SlotNotUnlocked"
	end

	if slot.State ~= "DeadAwaitingDecision"
		or typeof(slot.CurrentLife) ~= "table" then

		return false,
			"LifeNotAwaitingDecision"
	end

	local lifeId =
		slot.CurrentLife.LifeId

	if typeof(lifeId) ~= "string"
		or lifeId == "" then

		return false,
			"NoCurrentLife"
	end

	return teleportDeadLife(
		player,
		slotId,
		lifeId,
		reason or "DeadSlotReturn"
	)
end

function AfterlifeTransferService.HandleFinalDeath(
	player: Player,
	reason: string?
): (boolean, string)
	if afterlifePlaceId() <= 0 then
		return false,
			"AfterlifePlaceIdNotConfigured"
	end

	AccountProfileService.Start()
	CharacterSlotContextService.Start()
	CharacterLifeContextService.Start()

	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	local slot =
		AccountProfileService.GetSlot(
			player,
			identity.SlotId
		)

	if not slot then
		return false, "SlotNotUnlocked"
	end

	if slot.State == "DeadAwaitingDecision" then
		return teleportDeadLife(
			player,
			identity.SlotId,
			identity.LifeId,
			reason or "ExistingFinalDeath"
		)
	end

	if slot.State ~= "Alive" then
		return false,
			"LifeNotAlive"
	end

	local deathOk,
		deathReason =
		CharacterLifecycleService.MarkFinalDeath(
			player,
			reason or "FinalDeath"
		)

	if not deathOk then
		return false,
			deathReason
	end

	return teleportDeadLife(
		player,
		identity.SlotId,
		identity.LifeId,
		reason or "FinalDeath"
	)
end

print(
	"[AfterlifeTransferService] READY v1.1"
		.. " | AfterlifePlaceId="
		.. tostring(
			ExperiencePlaceConfig.AfterlifePlaceId
		)
)

return AfterlifeTransferService
