-- CombatIdleController v8 - Hitstun + Downed Aware
--
-- StarterPlayer > StarterCharacterScripts
--
-- RESPONSABILIDAD UNICA:
-- reproducir Combat Idle cuando CombatMode = true y el personaje esta quieto.
--
-- Este script NO modifica:
-- HumanoidRootPart.CFrame
-- AutoRotate
-- MouseBehavior
-- WalkSpeed
-- estados del Humanoid
-- Tree Jump
-- Surface Walking
-- Dash
--
-- Por eso la animacion de Combat Idle queda separada del controlador
-- que maneja la orientacion real del modo combate.

local RunService =
	game:GetService("RunService")


-- =========================
-- CHARACTER
-- =========================

local character =
	script.Parent

local humanoid =
	character:WaitForChild(
		"Humanoid"
	)

local animator =
	humanoid:WaitForChild(
		"Animator"
	)


-- =========================
-- SETTINGS
-- =========================

local COMBAT_IDLE_ANIMATION_ID =
	"rbxassetid://89511887601090"

local COMBAT_IDLE_SPEED =
	1.0

local COMBAT_IDLE_FADE_IN =
	0.10

local COMBAT_IDLE_FADE_OUT =
	0.08


-- =========================
-- ANIMATION
-- =========================

local animation =
	Instance.new("Animation")

animation.Name =
	"CombatIdle"

animation.AnimationId =
	COMBAT_IDLE_ANIMATION_ID


local track =
	animator:LoadAnimation(
		animation
	)

track.Priority =
	Enum.AnimationPriority.Movement

track.Looped =
	true


-- =========================
-- HELPERS
-- =========================

local function isTreeJumpActive()
	-- Usamos solo el movimiento local real.
	-- IsTreeJumping puede seguir true brevemente después del aterrizaje,
	-- lo que antes dejaba entrar al Idle normal antes del Combat Idle.
	return character:GetAttribute(
		"TreeJumpActive"
	) == true
end


local function isAirState()
	local state =
		humanoid:GetState()

	return state ==
		Enum.HumanoidStateType.Jumping
		or state ==
		Enum.HumanoidStateType.Freefall
end



local function isDownedSystemLocked(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsCarrying") == true
end

local function shouldPlay()
	if isDownedSystemLocked() then
		return false
	end

	if character:GetAttribute(
		"CombatMode"
		) ~= true then

		return false
	end

	if character:GetAttribute(
		"CombatSuppressed"
		) == true then

		return false
	end

	if humanoid.Health <= 0 then
		return false
	end

	if character:GetAttribute(
		"IsStunned"
		) == true then
		return false
	end

	local surfaceWalking =
		character:GetAttribute(
			"SurfaceWalking"
		) == true

	if surfaceWalking then

		-- En SurfaceWalking el Humanoid esta en Physics y el movimiento
		-- real lo maneja SurfaceController. SurfaceMoving es la fuente
		-- correcta para saber si debe verse Combat Idle.
		if character:GetAttribute(
			"SurfaceMoving"
			) == true then

			return false
		end

	elseif humanoid.MoveDirection.Magnitude >
		0.05 then

		return false
	end

	if isTreeJumpActive() then
		return false
	end

	if character:GetAttribute(
		"IsDashing"
		) == true then

		return false
	end

	if character:GetAttribute(
		"IsBlocking"
		) == true then

		return false
	end

	if character:GetAttribute(
		"IsAttacking"
		) == true then

		return false
	end

	if character:GetAttribute(
		"SurfaceJumping"
		) == true then

		return false
	end

	if isAirState() then
		return false
	end

	if humanoid:GetState() ==
		Enum.HumanoidStateType.Swimming then

		return false
	end

	if humanoid.PlatformStand then
		return false
	end

	return true
end


-- =========================
-- PLAYBACK
-- =========================

local function update()
	if shouldPlay() then

		if not track.IsPlaying then
			track:Play(
				COMBAT_IDLE_FADE_IN
			)

			track:AdjustSpeed(
				COMBAT_IDLE_SPEED
			)
		end

	else

		if track.IsPlaying then
			track:Stop(
				COMBAT_IDLE_FADE_OUT
			)
		end

	end
end


-- =========================
-- UPDATE
-- =========================

local connection =
	RunService.RenderStepped:Connect(
		update
	)


-- =========================
-- DEATH / CLEANUP
-- =========================

humanoid.Died:Connect(
	function()
		if track.IsPlaying then
			track:Stop(0)
		end
	end
)


script.Destroying:Connect(
	function()
		connection:Disconnect()

		if track.IsPlaying then
			track:Stop(0)
		end

		animation:Destroy()
	end
)
