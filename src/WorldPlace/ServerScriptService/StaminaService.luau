-- StaminaService v1.2 - ChakraCharge Lock + Context Regen + Action Spend Gateway
--
-- Install as:
-- ServerScriptService > StaminaService (ModuleScript)
--
-- SERVER-AUTHORITATIVE OWNERSHIP:
-- - Stamina
-- - regeneration
-- - Dash costs
-- - generic whitelisted action costs (currently DoubleJump)
--
-- Character attributes:
-- StaminaSystemReady
-- Stamina
-- MaxStamina
-- StaminaRegenRate
-- StaminaRegenDelay
-- StaminaRegenStartsAt
-- StaminaLastSpendReason
--
-- Public server API:
-- GetCurrent(player)
-- GetMax(player)
-- GetDashSettings(player, airDash)
-- TrySpend(player, amount, reason)
-- TrySpendAction(player, actionId)
-- Start()

local Players =
	game:GetService(
		"Players"
	)

local RunService =
	game:GetService(
		"RunService"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)


local StaminaConfig =
	require(
		ReplicatedStorage:
		WaitForChild(
			"StaminaConfig"
		)
	)


local StaminaService = {}

local started =
	false


type PlayerState = {
	Character: Model?,
	Current: number,
	Max: number,
	LastSpendAt: number,
	LastDashRequestAt: number,
	LastActionRequestAt: number,
}


local states: {
	[Player]: PlayerState
} = {}


-- ============================================================
-- REMOTES
-- ============================================================

local remotes =
	ReplicatedStorage:
	FindFirstChild(
		"StaminaRemotes"
	)

if not remotes then

	remotes =
		Instance.new(
			"Folder"
		)

	remotes.Name =
		"StaminaRemotes"

	remotes.Parent =
		ReplicatedStorage
end


local dashSpendRequest =
	remotes:
	FindFirstChild(
		"DashSpendRequest"
	)

if not dashSpendRequest then

	dashSpendRequest =
		Instance.new(
			"RemoteEvent"
		)

	dashSpendRequest.Name =
		"DashSpendRequest"

	dashSpendRequest.Parent =
		remotes
end


local dashSpendResult =
	remotes:
	FindFirstChild(
		"DashSpendResult"
	)

if not dashSpendResult then

	dashSpendResult =
		Instance.new(
			"RemoteEvent"
		)

	dashSpendResult.Name =
		"DashSpendResult"

	dashSpendResult.Parent =
		remotes
end


-- Generic read/write action gateway.
--
-- The CLIENT NEVER supplies an amount.
-- It supplies only a whitelisted ActionId and the server resolves its cost
-- from StaminaConfig.Actions.
--
-- Current:
-- DoubleJump
--
-- Future candidates:
-- Lunge
-- other physical actions
local actionSpendRequest =
	remotes:
	FindFirstChild(
		"ActionSpendRequest"
	)

if not actionSpendRequest then

	actionSpendRequest =
		Instance.new(
			"RemoteFunction"
		)

	actionSpendRequest.Name =
		"ActionSpendRequest"

	actionSpendRequest.Parent =
		remotes
end


-- ============================================================
-- HELPERS
-- ============================================================

local function clampStamina(
	value: number,
	maxValue: number
): number

	return math.clamp(
		value,
		0,
		maxValue
	)
end


local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?)

	local character =
		player.Character


	if not character
		or not character.Parent then

		return nil,
			nil
	end


	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)


	if not humanoid
		or humanoid.Health <= 0 then

		return nil,
			nil
	end


	return character,
		humanoid
end


local function isActionLocked(
	character: Model
): boolean

	return character:GetAttribute(
		"DownedActionLocked"
	) == true
		or character:GetAttribute(
			"IsDowned"
		) == true
		or character:GetAttribute(
			"IsCarried"
		) == true
		or character:GetAttribute(
			"IsExecuting"
		) == true
		or character:GetAttribute(
			"IsStunned"
		) == true
		or character:GetAttribute(
			"ChakraCharging"
		) == true
end


local function isRestrictedDash(
	character: Model
): boolean

	if StaminaConfig.Dash.RestrictedByCombatTag
		and character:GetAttribute(
			"CombatTagged"
		) == true then

		return true
	end


	if StaminaConfig.Dash.RestrictedByCombatMode
		and character:GetAttribute(
			"CombatMode"
		) == true then

		return true
	end


	return false
end


local function getDashSettings(
	character: Model,
	airDash: boolean
): (number, number, boolean)

	local restricted =
		isRestrictedDash(
			character
		)


	local profile =
		if restricted
		then StaminaConfig.Dash.Restricted
		else StaminaConfig.Dash.OpenWorld


	local cost =
		if airDash
		then profile.AirCost
		else profile.GroundCost


	return cost,
		profile.Cooldown,
		restricted
end


local function getRegenSettings(
	character: Model
): (number, number, boolean)

	local combatTagged =
		character:GetAttribute(
			"CombatTagged"
		) == true


	local profile =
		if combatTagged
		then StaminaConfig.Regen.CombatTagged
		else StaminaConfig.Regen.OpenWorld


	return profile.PerSecond,
		profile.DelayAfterSpend,
		combatTagged
end


local function getRegenStartsAt(
	state: PlayerState,
	character: Model
): number

	local _rate,
		delayAfterSpend =
		getRegenSettings(
			character
		)


	if state.LastSpendAt <= 0 then

		return 0
	end


	return state.LastSpendAt
		+ delayAfterSpend
end


local function syncCharacterAttributes(
	state: PlayerState
)

	local character =
		state.Character


	if not character
		or not character.Parent then

		return
	end


	local regenRate,
		regenDelay =
		getRegenSettings(
			character
		)


	character:SetAttribute(
		"Stamina",
		state.Current
	)

	character:SetAttribute(
		"MaxStamina",
		state.Max
	)

	character:SetAttribute(
		"StaminaRegenRate",
		regenRate
	)

	character:SetAttribute(
		"StaminaRegenDelay",
		regenDelay
	)

	character:SetAttribute(
		"StaminaRegenStartsAt",
		getRegenStartsAt(
			state,
			character
		)
	)

	character:SetAttribute(
		"StaminaSystemReady",
		true
	)
end


local function initializeCharacter(
	player: Player,
	character: Model
)

	local state =
		states[
	player
	]


	if not state then

		state = {
			Character =
				character,

			Current =
				StaminaConfig.MaxStamina,

			Max =
				StaminaConfig.MaxStamina,

			LastSpendAt =
				0,

			LastDashRequestAt =
				-math.huge,

			LastActionRequestAt =
				-math.huge,
		}

		states[
		player
		] =
			state

	else

		state.Character =
			character

		state.Current =
			state.Max

		state.LastSpendAt =
			0

		state.LastDashRequestAt =
			-math.huge

		state.LastActionRequestAt =
			-math.huge
	end


	character:SetAttribute(
		"StaminaLastSpendReason",
		""
	)


	-- CombatTag can change the active regen rate/delay without another spend.
	character:
		GetAttributeChangedSignal(
			"CombatTagged"
		):
		Connect(
			function()

				if state.Character ==
					character then

					syncCharacterAttributes(
						state
					)
				end
			end
		)


	syncCharacterAttributes(
		state
	)
end


local function initializePlayer(
	player: Player
)

	if not states[
		player
		] then

		states[
		player
		] = {
			Character =
				nil,

			Current =
				StaminaConfig.MaxStamina,

			Max =
				StaminaConfig.MaxStamina,

			LastSpendAt =
				0,

			LastDashRequestAt =
				-math.huge,

			LastActionRequestAt =
				-math.huge,
		}
	end


	player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				initializeCharacter(
					player,
					character
				)
			end
		)


	if player.Character then

		initializeCharacter(
			player,
			player.Character
		)
	end
end


-- ============================================================
-- PUBLIC API
-- ============================================================

function StaminaService.GetCurrent(
	player: Player
): number

	local state =
		states[
	player
	]


	if not state then

		return 0
	end


	return state.Current
end


function StaminaService.GetMax(
	player: Player
): number

	local state =
		states[
	player
	]


	if not state then

		return StaminaConfig.MaxStamina
	end


	return state.Max
end


function StaminaService.GetDashSettings(
	player: Player,
	airDash: boolean
): (number?, number?, boolean?)

	local character =
		player.Character


	if not character then

		return nil,
			nil,
			nil
	end


	return getDashSettings(
		character,
		airDash
	)
end


function StaminaService.TrySpend(
	player: Player,
	amount: number,
	reason: string?
): (boolean, string, number)

	if typeof(
		amount
		) ~= "number"
			or amount <= 0 then

		return false,
			"InvalidAmount",
			StaminaService.GetCurrent(
				player
			)
	end


	local character,
		humanoid =
		getAliveCharacter(
			player
		)


	if not character
		or not humanoid then

		return false,
			"CharacterUnavailable",
			StaminaService.GetCurrent(
				player
			)
	end


	if isActionLocked(
		character
		) then

		return false,
			"ActionLocked",
			StaminaService.GetCurrent(
				player
			)
	end


	local state =
		states[
	player
	]


	if not state
		or state.Character ~=
		character then

		initializeCharacter(
			player,
			character
		)

		state =
			states[
		player
		]
	end


	if state.Current
		+ 0.0001 <
		amount then

		return false,
			"InsufficientStamina",
			state.Current
	end


	state.Current =
		clampStamina(
			state.Current
			- amount,
			state.Max
		)


	state.LastSpendAt =
		workspace:
		GetServerTimeNow()


	character:SetAttribute(
		"StaminaLastSpendReason",
		reason
			or "Spend"
	)


	syncCharacterAttributes(
		state
	)


	return true,
		"OK",
		state.Current
end


function StaminaService.TrySpendAction(
	player: Player,
	actionId: string
): (boolean, string, number, number)

	if typeof(
		actionId
		) ~= "string" then

		return false,
			"InvalidAction",
			StaminaService.GetCurrent(
				player
			),
			0
	end


	local actionConfig =
		StaminaConfig.Actions[
	actionId
	]


	if typeof(
		actionConfig
		) ~= "table"
			or typeof(
				actionConfig.Cost
			) ~= "number"
			or actionConfig.Cost <= 0 then

		return false,
			"UnknownAction",
			StaminaService.GetCurrent(
				player
			),
			0
	end


	local success,
		reason,
		remaining =
		StaminaService.TrySpend(
			player,
			actionConfig.Cost,
			actionId
		)


	return success,
		reason,
		remaining,
		actionConfig.Cost
end


-- ============================================================
-- DASH REMOTE
-- ============================================================

dashSpendRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			requestId: any,
			airDashValue: any
		)

			if typeof(
				requestId
				) ~= "number" then

				return
			end


			local airDash =
			airDashValue == true


			local character,
			humanoid =
			getAliveCharacter(
				player
			)


			if not character
				or not humanoid then

				dashSpendResult:
				FireClient(
					player,
					requestId,
					false,
					"CharacterUnavailable",
					0,
					0,
					0,
					false
				)

				return
			end


			local state =
			states[
			player
			]


			if not state
				or state.Character ~=
				character then

				initializeCharacter(
					player,
					character
				)

				state =
				states[
				player
				]
			end


			-- Remote spam protection, separate from gameplay cooldown.
			local nowClock =
			time()


			if nowClock
				- state.LastDashRequestAt <
				0.08 then

				dashSpendResult:
				FireClient(
					player,
					requestId,
					false,
					"RequestRateLimited",
					state.Current,
					0,
					0,
					isRestrictedDash(
						character
					)
				)

				return
			end


			state.LastDashRequestAt =
			nowClock


			if isActionLocked(
				character
				) then

				dashSpendResult:
				FireClient(
					player,
					requestId,
					false,
					"ActionLocked",
					state.Current,
					0,
					0,
					isRestrictedDash(
						character
					)
				)

				return
			end


			local cost,
			cooldown,
			restricted =
			getDashSettings(
				character,
				airDash
			)


			local success,
			reason,
			remaining =
			StaminaService.TrySpend(
				player,
				cost,
				if airDash
				then "AirDash"
				else "GroundDash"
			)


			dashSpendResult:
			FireClient(
				player,
				requestId,
				success,
				reason,
				remaining,
				cost,
				cooldown,
				restricted
			)
		end
	)


-- ============================================================
-- GENERIC ACTION REMOTE
-- ============================================================

actionSpendRequest.OnServerInvoke =
	function(
		player: Player,
		actionId: any
	)

	local state =
		states[
	player
	]


	if not state then

		return false,
			"StateUnavailable",
			0,
			0
	end


	local nowClock =
		time()


	if nowClock
		- state.LastActionRequestAt <
			0.04 then

		return false,
			"RequestRateLimited",
			state.Current,
			0
	end


	state.LastActionRequestAt =
		nowClock


	return StaminaService.TrySpendAction(
		player,
		actionId
	)
end


-- ============================================================
-- REGENERATION
-- ============================================================

local accumulated =
	0


RunService.Heartbeat:
	Connect(
		function(
			deltaTime: number
		)

			if not started then
				return
			end


			accumulated +=
			deltaTime


			if accumulated <
				StaminaConfig.Regen.UpdateInterval then

				return
			end


			local step =
			accumulated


			accumulated =
			0


			local now =
			workspace:
			GetServerTimeNow()


			for player,
				state in pairs(
					states
				) do

				local character =
				state.Character


				if not character
					or not character.Parent
					or player.Character ~=
					character then

					continue
				end


				local humanoid =
				character:
				FindFirstChildOfClass(
					"Humanoid"
				)


				if not humanoid
					or humanoid.Health <= 0 then

					continue
				end


				local regenRate,
				regenDelay =
				getRegenSettings(
					character
				)


				local regenStartsAt =
				if state.LastSpendAt > 0
				then state.LastSpendAt
				+ regenDelay
				else 0


				if now <
					regenStartsAt then

					continue
				end


				if state.Current >=
					state.Max then

					continue
				end


				state.Current =
				clampStamina(
					state.Current
					+ regenRate
					* step,
					state.Max
				)


				syncCharacterAttributes(
					state
				)
			end
		end
	)


-- ============================================================
-- START
-- ============================================================

function StaminaService.Start()

	if started then
		return
	end


	started =
		true


	Players.PlayerAdded:
		Connect(
			initializePlayer
		)


	Players.PlayerRemoving:
		Connect(
			function(
				player: Player
			)

				states[
				player
				] =
				nil
			end
		)


	for _,
		player in ipairs(
			Players:GetPlayers()
		) do

		initializePlayer(
			player
		)
	end


	print(
		"[StaminaService] READY v1.2"
			.. " | Max="
			.. tostring(
				StaminaConfig.MaxStamina
			)
			.. " | OpenRegen="
			.. tostring(
				StaminaConfig.Regen.OpenWorld.PerSecond
			)
			.. "/s"
			.. " | PvPRegen="
			.. tostring(
				StaminaConfig.Regen.CombatTagged.PerSecond
			)
			.. "/s"
			.. " | PvPDelay="
			.. tostring(
				StaminaConfig.Regen.CombatTagged.DelayAfterSpend
			)
			.. " | DashCost="
			.. tostring(
				StaminaConfig.Dash.Restricted.GroundCost
			)
			.. " | PvPDashCooldown="
			.. tostring(
				StaminaConfig.Dash.Restricted.Cooldown
			)
			.. " | DoubleJumpCost="
			.. tostring(
				StaminaConfig.Actions.DoubleJump.Cost
			)
	)
end


return StaminaService
