--!strict
-- CombatLogPenaltyServer v1
-- PLACE AS Script:
-- ServerScriptService > CombatLogPenaltyServer
--
-- Listens to ServerStorage > CombatTagInternal > CombatLogDetected
-- (fired by CombatTagServer when a CombatTagged player leaves) and applies
-- the combat-log penalty: v2 · the current life LOSES LIFE FORCE (20 %, value in
-- ServerStorage > LifeForceInternal > CombatLogLoss, set by LifeForceServer).
--
-- Only if that takes it to 0 does the slot become DeadAwaitingDecision, exactly
-- like the dev-panel "MarkFinalDeath" button. On the next join the player is
-- routed through the normal dead-slot flow (Afterlife / Revive / Wipe).
--
-- Safety rules:
-- - Server shutdown is NEVER punished. BindToClose runs before players are
--   removed, so the shutdown flag is already set when PlayerRemoving fires.
-- - In Studio the penalty is only logged unless APPLY_IN_STUDIO = true, so
--   pressing Stop or closing a Team Test client does not kill test characters.
-- - The mutation is done synchronously during PlayerRemoving, while
--   AccountProfileService still holds the profile in memory. Its own unload
--   save either includes the death or is followed by this save.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local APPLY_IN_STUDIO = false

-- Fallback if LifeForceServer did not publish its value
local DEFAULT_COMBAT_LOG_LOSS = 20

local function combatLogLoss(): number
	local internal = ServerStorage:FindFirstChild("LifeForceInternal")
	local value = internal and internal:FindFirstChild("CombatLogLoss")
	if value and value:IsA("NumberValue") then
		return value.Value
	end
	return DEFAULT_COMBAT_LOG_LOSS
end

local Services =
	ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

-- CombatTagService creates the folder/event when it is first required.
require(ServerScriptService:WaitForChild("CombatTagService"))

local internalFolder =
	ServerStorage:WaitForChild("CombatTagInternal")

local combatLogDetected =
	internalFolder:WaitForChild("CombatLogDetected") :: BindableEvent

local shuttingDown = false

game:BindToClose(function()
	shuttingDown = true
end)


local function getActiveSlotId(
	player: Player
): string?
	-- Read the published attributes instead of the context services: those
	-- services clear their per-player state on PlayerRemoving.
	for _, name in ipairs({
		"CharacterLifeSlotId",
		"CharacterLifecycleActiveSlotId",
		}) do
		local value =
			player:GetAttribute(name)

		if typeof(value) == "string"
			and value ~= "" then

			return value
		end
	end

	return nil
end


local function describeSources(
	snapshot: {any}?
): string
	if typeof(snapshot) ~= "table" then
		return "?"
	end

	local names = {}

	for _, entry in ipairs(snapshot) do
		if typeof(entry) == "table" then
			table.insert(
				names,
				tostring(entry.sourceName)
			)
		end
	end

	return if #names > 0
		then table.concat(names, ", ")
		else "?"
end


local function applyPenalty(
	player: Player,
	snapshot: {any}?
)
	local sources =
		describeSources(snapshot)

	if shuttingDown then
		print(
			"[CombatLogPenalty] skipped (server shutdown):",
			player.Name
		)

		return
	end

	if RunService:IsStudio()
		and not APPLY_IN_STUDIO then

		warn(
			"[CombatLogPenalty] STUDIO: would remove " .. tostring(combatLogLoss()) .. " Life Force from",
			player.Name,
			"| tagged by:",
			sources,
			"| set APPLY_IN_STUDIO = true to test it"
		)

		return
	end

	local slotId =
		getActiveSlotId(player)

	if not slotId then
		warn(
			"[CombatLogPenalty] no active slot, penalty NOT applied:",
			player.Name
		)

		return
	end

	local loss =
		combatLogLoss()

	local adjusted, adjustReason, lifeForce =
		AccountProfileService.AdjustLifeForce(
			player,
			slotId,
			-loss,
			"CombatLog",
			true
		)

	if not adjusted then
		warn(
			"[CombatLogPenalty] Life Force NOT removed:",
			player.Name,
			"| reason:",
			adjustReason
		)

		return
	end

	warn(
		"[CombatLogPenalty] -" .. tostring(loss) .. " Life Force:",
		player.Name,
		"| now:",
		lifeForce,
		"| tagged by:",
		sources
	)

	-- Only reaching 0 is a final death (Afterlife on the next join, never a wipe)
	if typeof(lifeForce) ~= "number"
		or lifeForce > 0 then

		return
	end

	local ok, reason =
		AccountProfileService.MarkFinalDeath(
			player,
			slotId
		)

	if ok then
		warn(
			"[CombatLogPenalty] Life Force depleted, FINAL DEATH applied:",
			player.Name,
			"| slot:",
			slotId,
			"| tagged by:",
			sources
		)
	else
		warn(
			"[CombatLogPenalty] FAILED:",
			player.Name,
			"| slot:",
			slotId,
			"| reason:",
			reason
		)
	end
end


combatLogDetected.Event:Connect(
	function(player: Player, snapshot: {any}?)
		if typeof(player) ~= "Instance"
			or not player:IsA("Player") then

			return
		end

		applyPenalty(player, snapshot)
	end
)

print(
	"[CombatLogPenaltyServer] READY v2"
		.. " | Penalty=LifeForce -" .. tostring(combatLogLoss()) .. " (FinalDeath only at 0)"
		.. " | Studio=" .. (if APPLY_IN_STUDIO then "APPLY" else "LOG_ONLY")
)
