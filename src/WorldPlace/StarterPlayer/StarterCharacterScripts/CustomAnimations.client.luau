-- CustomAnimations v4.2 - LayeredR6Swim + CarrySafeLanding
local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local animate = character:WaitForChild("Animate")


-- =========================
-- ANIMATION IDS
-- =========================

local IDLE_ANIMATION_ID = "rbxassetid://129182759601754"
local WALK_ANIMATION_ID = "rbxassetid://75479783841702"
local JUMP_ANIMATION_ID = "rbxassetid://96074100792499"
local FALL_ANIMATION_ID = "rbxassetid://92479075812419"
local LAND_ANIMATION_ID = "rbxassetid://115591267819549"
local SWIM_IDLE_ANIMATION_ID = "rbxassetid://115486462864120"
local SWIM_ANIMATION_ID = "rbxassetid://111879004231294"


-- =========================
-- ANIMATION SPEEDS
-- =========================

local IDLE_ANIMATION_SPEED = 1.0
local WALK_ANIMATION_SPEED = 1.2
local JUMP_ANIMATION_SPEED = 1.0
local FALL_ANIMATION_SPEED = 1.0
local LAND_ANIMATION_SPEED = 1.0
local LAND_SPRINT_ANIMATION_SPEED = 2
local SWIM_IDLE_ANIMATION_SPEED = 1.0
local SWIM_ANIMATION_SPEED = 1.0


-- =========================
-- LAND SETTINGS
-- =========================

local MIN_FALL_TIME_FOR_LAND = 0.10


-- =========================
-- VARIABLES
-- =========================

local landTrack
local freefallStartTime
local swimIdleTrack
local swimTrack
local activeSwimMode = nil


-- =========================
-- SURFACE CHECK
-- =========================

local function isSurfaceWalking()
	return character:GetAttribute(
		"SurfaceWalking"
	) == true
end

local function isWaterWalking()
	return character:GetAttribute(
		"WaterWalking"
	) == true
end

local function isRealSwimming()
	return humanoid:GetState() ==
		Enum.HumanoidStateType.Swimming
		and not isSurfaceWalking()
		and not isWaterWalking()
end


-- =========================
-- CARRY ANIMATION OWNERSHIP
-- =========================
--
-- Carry has its own full-body pickup / shoulder animations. A grounded pickup
-- can make Roblox briefly report Freefall/Landed even though the player did
-- not perform a real gameplay fall. The generic Land animation must never
-- enter that transition.

local function isCarryAnimationOwned(): boolean
	return character:GetAttribute("CarryPickupActive") == true
		or character:GetAttribute("IsCarrying") == true
		or character:GetAttribute("IsCarried") == true
end

local function suppressLandForCarry()
	freefallStartTime = nil

	if landTrack
		and landTrack.IsPlaying then

		landTrack:Stop(0.03)
	end
end


-- =========================
-- ANIMATION SPEED CONTROL
-- =========================

animator.AnimationPlayed:Connect(
	function(track)
		if track.Animation.AnimationId ==
			IDLE_ANIMATION_ID then

			track:AdjustSpeed(
				IDLE_ANIMATION_SPEED
			)

		elseif track.Animation.AnimationId ==
			WALK_ANIMATION_ID then

			track:AdjustSpeed(
				WALK_ANIMATION_SPEED
			)

		elseif track.Animation.AnimationId ==
			JUMP_ANIMATION_ID then

			track:AdjustSpeed(
				JUMP_ANIMATION_SPEED
			)

		elseif track.Animation.AnimationId ==
			FALL_ANIMATION_ID then

			track:AdjustSpeed(
				FALL_ANIMATION_SPEED
			)

		elseif track.Animation.AnimationId ==
			SWIM_IDLE_ANIMATION_ID then

			track:AdjustSpeed(
				SWIM_IDLE_ANIMATION_SPEED
			)

		elseif track.Animation.AnimationId ==
			SWIM_ANIMATION_ID then

			track:AdjustSpeed(
				SWIM_ANIMATION_SPEED
			)
		end
	end
)


-- =========================
-- REPLACE DEFAULT ANIMATIONS
-- =========================

-- In multi-client Studio tests the Animate LocalScript can replicate before
-- its child animation folders/objects. Waiting only for "Animate" is not
-- sufficient and can produce:
--   idle is not a valid member of LocalScript "...Animate"
--
-- Resolve every required descendant explicitly before editing IDs.
local animateIdle =
	animate:WaitForChild("idle")

local animateWalk =
	animate:WaitForChild("walk")

local animateJump =
	animate:WaitForChild("jump")

local animateFall =
	animate:WaitForChild("fall")

local idleAnimation1 =
	animateIdle:WaitForChild("Animation1") :: Animation

local idleAnimation2 =
	animateIdle:WaitForChild("Animation2") :: Animation

local walkAnimation =
	animateWalk:WaitForChild("WalkAnim") :: Animation

local jumpAnimation =
	animateJump:WaitForChild("JumpAnim") :: Animation

local fallAnimation =
	animateFall:WaitForChild("FallAnim") :: Animation

idleAnimation1.AnimationId =
	IDLE_ANIMATION_ID

idleAnimation2.AnimationId =
	IDLE_ANIMATION_ID

walkAnimation.AnimationId =
	WALK_ANIMATION_ID

jumpAnimation.AnimationId =
	JUMP_ANIMATION_ID

fallAnimation.AnimationId =
	FALL_ANIMATION_ID


-- =========================
-- RELOAD ROBLOX ANIMATE
-- =========================

animate.Enabled = false
task.wait()
animate.Enabled = true


-- =========================
-- CREATE SWIM ANIMATIONS
-- =========================
-- R6 layered swim:
-- Roblox/Animate keeps its normal lower-body locomotion running underneath.
-- Our custom Swim / SwimIdle tracks are authored only on the upper body and
-- are played at Action priority so they override only the joints they contain.
-- IMPORTANT: do not keyframe Torso, Left Leg, Right Leg or HumanoidRootPart
-- in the custom swim assets if lower-body layering is desired.

local swimIdleAnimation =
	Instance.new("Animation")

swimIdleAnimation.Name =
	"CustomSwimIdle"

swimIdleAnimation.AnimationId =
	SWIM_IDLE_ANIMATION_ID

swimIdleTrack =
	animator:LoadAnimation(
		swimIdleAnimation
	)

swimIdleTrack.Priority =
	Enum.AnimationPriority.Action

swimIdleTrack.Looped = true

local swimAnimation =
	Instance.new("Animation")

swimAnimation.Name =
	"CustomSwim"

swimAnimation.AnimationId =
	SWIM_ANIMATION_ID

swimTrack =
	animator:LoadAnimation(
		swimAnimation
	)

swimTrack.Priority =
	Enum.AnimationPriority.Action

swimTrack.Looped = true


local function stopSwimTracks(fadeTime)
	fadeTime = fadeTime or 0.10

	if swimIdleTrack
		and swimIdleTrack.IsPlaying then

		swimIdleTrack:Stop(fadeTime)
	end

	if swimTrack
		and swimTrack.IsPlaying then

		swimTrack:Stop(fadeTime)
	end

	activeSwimMode = nil
end


local function updateSwimAnimation()
	if not isRealSwimming() then
		stopSwimTracks(0.10)
		return
	end


	local isMoving =
		humanoid.MoveDirection.Magnitude > 0.05

	if isMoving then
		if activeSwimMode ~= "Swim" then
			if swimIdleTrack
				and swimIdleTrack.IsPlaying then

				swimIdleTrack:Stop(0.12)
			end

			if swimTrack then
				swimTrack:Play(0.12)
				swimTrack:AdjustSpeed(
					SWIM_ANIMATION_SPEED
				)
			end

			activeSwimMode = "Swim"
			print(
				"[CustomAnimations] SWIM -> Move",
				"state",
				humanoid:GetState().Name,
				"move",
				string.format("%.2f", humanoid.MoveDirection.Magnitude)
			)
		end
	else
		if activeSwimMode ~= "Idle" then
			if swimTrack
				and swimTrack.IsPlaying then

				swimTrack:Stop(0.12)
			end

			if swimIdleTrack then
				swimIdleTrack:Play(0.12)
				swimIdleTrack:AdjustSpeed(
					SWIM_IDLE_ANIMATION_SPEED
				)
			end

			activeSwimMode = "Idle"
			print(
				"[CustomAnimations] SWIM -> Idle",
				"state",
				humanoid:GetState().Name
			)
		end
	end
end


-- =========================
-- CREATE LAND ANIMATION
-- =========================

local landAnimation =
	Instance.new("Animation")

landAnimation.AnimationId =
	LAND_ANIMATION_ID

landTrack =
	animator:LoadAnimation(
		landAnimation
	)

landTrack.Priority =
	Enum.AnimationPriority.Action

landTrack.Looped =
	false


-- =========================
-- LAND SYSTEM
-- =========================

local function playLandAnimation()
	-- Carry owns this transition. Never layer a generic landing animation
	-- underneath/after pickup or while transporting another player.
	if isCarryAnimationOwned() then
		suppressLandForCarry()
		return
	end

	-- Cambiar de cara en una pared/techo NO es un aterrizaje.
	if isSurfaceWalking() then
		return
	end

	if not landTrack then
		return
	end

	if landTrack.IsPlaying then
		landTrack:Stop(0)
	end

	local isMoving =
		humanoid.MoveDirection.Magnitude > 0

	local isSprinting =
		humanoid.WalkSpeed >= 30

	local landSpeed =
		LAND_ANIMATION_SPEED

	if isMoving
		and isSprinting then

		landSpeed =
			LAND_SPRINT_ANIMATION_SPEED
	end

	landTrack:Play(0.03)
	landTrack:AdjustSpeed(
		landSpeed
	)
end


-- =========================
-- HUMANOID STATE CONTROL
-- =========================

humanoid.StateChanged:Connect(
	function(_, newState)
		if isCarryAnimationOwned() then
			suppressLandForCarry()

			if newState ~=
				Enum.HumanoidStateType.Swimming then

				stopSwimTracks(0.08)
			end

			return
		end

		if isSurfaceWalking() then
			freefallStartTime =
				nil

			stopSwimTracks(0.08)
			return
		end

		if newState ~=
			Enum.HumanoidStateType.Swimming then

			stopSwimTracks(0.08)
		end

		if newState ==
			Enum.HumanoidStateType.Swimming then

			freefallStartTime = nil
			updateSwimAnimation()

		elseif newState ==
			Enum.HumanoidStateType.Freefall then

			stopSwimTracks(0.08)

			if not freefallStartTime then
				freefallStartTime =
					time()
			end

		elseif newState ==
			Enum.HumanoidStateType.Landed then

			if freefallStartTime then
				local fallTime =
					time()
				- freefallStartTime

				if fallTime >=
					MIN_FALL_TIME_FOR_LAND then

					playLandAnimation()
				end
			end

			freefallStartTime =
				nil

		elseif newState ==
			Enum.HumanoidStateType.Running
			or newState ==
			Enum.HumanoidStateType.RunningNoPhysics then

			freefallStartTime =
				nil
		end
	end
)


-- =========================
-- CARRY STATE
-- =========================

for _, carryAttribute in ipairs({
	"CarryPickupActive",
	"IsCarrying",
	"IsCarried",
	}) do
	character:GetAttributeChangedSignal(
		carryAttribute
	):Connect(function()
		if isCarryAnimationOwned() then
			suppressLandForCarry()
		end
	end)
end


-- =========================
-- SURFACE STATE
-- =========================

character:GetAttributeChangedSignal(
	"SurfaceWalking"
):Connect(
	function()
		-- Entrar/salir de una pared no debe heredar
		-- tiempo de caida y disparar Land accidentalmente.
		freefallStartTime =
			nil

		if isSurfaceWalking()
			and landTrack.IsPlaying then

			landTrack:Stop(0.05)
		end
	end
)

-- =========================
-- SWIM STATE / MOVEMENT
-- =========================

humanoid:GetPropertyChangedSignal(
	"MoveDirection"
):Connect(
	function()
		if isRealSwimming() then
			updateSwimAnimation()
		end
	end
)

character:GetAttributeChangedSignal(
	"WaterWalking"
):Connect(
	function()
		if isWaterWalking() then
			stopSwimTracks(0.05)
		else
			updateSwimAnimation()
		end
	end
)

-- R6/terrain-water state transitions can happen between input changes.
-- This lightweight check only acts while genuinely Swimming and ensures
-- the correct custom track stays authoritative.
local swimHeartbeatAccumulator = 0

RunService.Heartbeat:Connect(
	function(dt)
		swimHeartbeatAccumulator += dt

		if swimHeartbeatAccumulator < 0.10 then
			return
		end

		swimHeartbeatAccumulator = 0

		if isRealSwimming() then
			updateSwimAnimation()
		end
	end
)

updateSwimAnimation()

print(
	"[CustomAnimations] READY v4.2 LayeredR6Swim + CarrySafeLanding"
		.. " | SwimIdle=115486462864120"
		.. " | Swim=111879004231294"
		.. " | DirectSwimTracks=ON"
		.. " | LowerBodyBaseLayer=ON"
		.. " | SwimUpperBodyPriority=Action"
		.. " | NativeSwimPhysics=ON"
		.. " | WaterWalkPriority=ON"
		.. " | AnimateHierarchyWait=ON"
		.. " | CarrySuppressesLand=ON"
		.. " | PickupFalseLanding=BLOCKED"
)

