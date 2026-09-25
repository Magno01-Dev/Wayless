--!strict
-- ComboCounterService v1 - Server Confirmed / Per Target
-- ServerScriptService > ComboCounterService [ModuleScript]
--
-- Central server-owned hit-combo tracker.
--
-- Rules:
-- - Only server-confirmed impacts are recorded.
-- - Combo is tracked per attacker and current target.
-- - Switching target resets the chain to 1.
-- - More than COMBO_TIMEOUT seconds between hits resets to 1.
-- - The client never reports hits to this service.
--
-- Future systems can reuse:
--
-- ComboCounterService.RecordHit(
--     attackerPlayer,
--     targetCharacter,
--     "Projectile",
--     "Kunai"
-- )

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Players =
	game:GetService("Players")


local ComboCounterService = {}


-- =========================
-- SETTINGS
-- =========================

local COMBO_TIMEOUT =
	1.75


-- =========================
-- REMOTE
-- =========================

local combatRemotes =
	ReplicatedStorage:
	FindFirstChild("CombatRemotes")

if not combatRemotes then
	combatRemotes = Instance.new("Folder")
	combatRemotes.Name = "CombatRemotes"
	combatRemotes.Parent = ReplicatedStorage
end


local comboConfirmed =
	combatRemotes:
	FindFirstChild("ComboHitConfirmed")

if not comboConfirmed then
	comboConfirmed = Instance.new("RemoteEvent")
	comboConfirmed.Name = "ComboHitConfirmed"
	comboConfirmed.Parent = combatRemotes
end


-- =========================
-- STATE
-- =========================

type ComboState = {
	target: Model,
	count: number,
	lastHitAt: number,
}

local states: {[Player]: ComboState} = {}


-- =========================
-- API
-- =========================

function ComboCounterService.RecordHit(
	attackerPlayer: Player,
	targetCharacter: Model,
	sourceType: string?,
	sourceId: string?
): number

	if not attackerPlayer.Parent then
		return 0
	end

	if not targetCharacter.Parent then
		return 0
	end


	local now =
		time()


	local state =
		states[
	attackerPlayer
	]


	local count: number


	if state
		and state.target ==
		targetCharacter
		and now - state.lastHitAt
		<= COMBO_TIMEOUT then

		state.count += 1
		state.lastHitAt = now

		count =
			state.count

	else

		count =
			1


		states[
		attackerPlayer
		] = {
			target = targetCharacter,
			count = count,
			lastHitAt = now,
		}
	end


	comboConfirmed:
		FireClient(
			attackerPlayer,
			count,
			targetCharacter,
			sourceType or "Unknown",
			sourceId or "Unknown",
			COMBO_TIMEOUT
		)


	return count
end


function ComboCounterService.Reset(
	attackerPlayer: Player
)

	states[
	attackerPlayer
	] = nil


	comboConfirmed:
		FireClient(
			attackerPlayer,
			0,
			nil,
			"Reset",
			"Reset",
			COMBO_TIMEOUT
		)
end


function ComboCounterService.GetTimeout(): number
	return COMBO_TIMEOUT
end


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			states[
			player
			] = nil
		end
	)


return ComboCounterService
