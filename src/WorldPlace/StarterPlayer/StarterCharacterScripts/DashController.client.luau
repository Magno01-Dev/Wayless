--!strict
-- DashController v4.6 - StatusFX Direct + Heavy Movement Modifiers
-- INSTALL: StarterPlayer > StarterCharacterScripts > DashController [LocalScript]
--
-- Preserves:
-- - Ground Dash 75 / 0.26
-- - Air Dash 105 / 0.262
-- - one Air Dash per real jump cycle
-- - Water Walk jump reliability / WaterWalk cycle reset
-- - Surface Dash
-- - Ballistic Air Dash carry until touchdown
-- - powered 3D microsteering + carry yaw microsteering
-- - server-authoritative Stamina spend
-- - combat/restricted cooldown
-- - CoreCooldown_Dash_* HUD contract
-- - directional animations/SFX/FOV
--
-- StatusFX:
-- - Status Stun blocks new Dash and interrupts active Dash immediately.
-- - Slow intentionally DOES NOT reduce Dash speed.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundingService = require(
	ReplicatedStorage:WaitForChild("GroundingService")
)

local StaminaConfig = require(
	ReplicatedStorage:WaitForChild("StaminaConfig")
)

local StatusCombatModifierReader = require(
	ReplicatedStorage:
		WaitForChild("Shared"):
		WaitForChild("StatusCombatModifierReader")
)

local staminaRemotes =
	ReplicatedStorage:WaitForChild("StaminaRemotes")

local dashSpendRequest =
	staminaRemotes:WaitForChild("DashSpendRequest") :: RemoteEvent

local dashSpendResult =
	staminaRemotes:WaitForChild("DashSpendResult") :: RemoteEvent

local character = script.Parent
local humanoid =
	character:WaitForChild("Humanoid") :: Humanoid
local animator =
	humanoid:WaitForChild("Animator") :: Animator
local rootPart =
	character:WaitForChild("HumanoidRootPart") :: BasePart

local DASH_KEY = Enum.KeyCode.Q
local DASH_SPEED = 75
local DASH_DURATION = 0.26
local AIR_DASH_SPEED = 105
local AIR_DASH_DURATION = 0.262
local DASH_COOLDOWN = 0.60
local POST_DASH_MOMENTUM_TIME = 0.16
local AIR_DASH_CARRY_FAILSAFE_TIME = 3.50

local AIR_DASH_POWERED_STEER_DEG_PER_SEC = 150
local AIR_DASH_CARRY_STEER_DEG_PER_SEC = 55
local AIR_DASH_POWERED_STEER_RAD_PER_SEC =
	math.rad(AIR_DASH_POWERED_STEER_DEG_PER_SEC)
local AIR_DASH_CARRY_STEER_RAD_PER_SEC =
	math.rad(AIR_DASH_CARRY_STEER_DEG_PER_SEC)

local BACK_DASH_INPUT_WINDOW = 0.30
local SIDE_DASH_INPUT_WINDOW = 0.30

local NORMAL_FOV = 70
local SPRINT_FOV = 80
local DASH_FOV = 87
local DASH_FOV_IN_TIME = 0.08
local DASH_FOV_OUT_TIME = 0.16

local FORWARD_DASH_ANIMATION_ID =
	"rbxassetid://101651539767821"
local BACK_DASH_ANIMATION_ID =
	"rbxassetid://107834944480329"
local RIGHT_DASH_ANIMATION_ID =
	"rbxassetid://133451550328369"
local LEFT_DASH_ANIMATION_ID =
	"rbxassetid://119152397409036"

local FORWARD_DASH_ANIMATION_SPEED = 1.0
local BACK_DASH_ANIMATION_SPEED = 2.2
local RIGHT_DASH_ANIMATION_SPEED = 2.2
local LEFT_DASH_ANIMATION_SPEED = 2.2

local DASH_SOUND_ID =
	"rbxassetid://125132870654875"
local DASH_SOUND_VOLUME = 0.7
local DASH_SOUND_START_TIME = 0.10
local DASH_SOUND_SPEED = 0.90
local DASH_SOUND_FADE_TIME = 0.18
local DASH_SOUND_MIN_DISTANCE = 8
local DASH_SOUND_MAX_DISTANCE = 60

local isDashing = false
local dashSpendSequence = 0
local activeDashSpendRequestId = 0
local dashSpendDenied = false
local activeDashCooldownDuration = DASH_COOLDOWN
local dashCooldownEndsAt = 0

local jumpAirborne = false
local airDashUsed = false
local currentFOVTween: Tween?

local lastSPressTime = -math.huge
local lastAPressTime = -math.huge
local lastDPressTime = -math.huge

local bufferedBackDirection: Vector3?
local bufferedBackFacingDirection: Vector3?
local bufferedLeftDirection: Vector3?
local bufferedLeftFacingDirection: Vector3?
local bufferedRightDirection: Vector3?
local bufferedRightFacingDirection: Vector3?

local currentSoundFadeTween: Tween?
local soundPlaybackVersion = 0

character:SetAttribute("SurfaceDashFacingDirection", Vector3.zero)
character:SetAttribute("AirDashCarryActive", false)
character:SetAttribute("IsDashing", false)

character:SetAttribute("DashCooldownEndsAt", 0)
character:SetAttribute("CoreCooldown_Dash_Label", "Dash")
character:SetAttribute("CoreCooldown_Dash_StartsAt", 0)
character:SetAttribute("CoreCooldown_Dash_EndsAt", 0)

local function createDashTrack(
	animationId: string
): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false

	return track
end

local forwardDashTrack =
	createDashTrack(FORWARD_DASH_ANIMATION_ID)
local backDashTrack =
	createDashTrack(BACK_DASH_ANIMATION_ID)
local rightDashTrack =
	createDashTrack(RIGHT_DASH_ANIMATION_ID)
local leftDashTrack =
	createDashTrack(LEFT_DASH_ANIMATION_ID)

local dashSound = Instance.new("Sound")
dashSound.Name = "DashSound"
dashSound.SoundId = DASH_SOUND_ID
dashSound.Volume = DASH_SOUND_VOLUME
dashSound.PlaybackSpeed = DASH_SOUND_SPEED
dashSound.RollOffMinDistance = DASH_SOUND_MIN_DISTANCE
dashSound.RollOffMaxDistance = DASH_SOUND_MAX_DISTANCE
dashSound.Parent = rootPart

task.spawn(function()
	local success, errorMessage =
		pcall(function()
			ContentProvider:PreloadAsync({dashSound})
		end)

	if not success then
		warn(
			"Could not preload DashSound:",
			errorMessage
		)
	end
end)

local function playDashSound()
	soundPlaybackVersion += 1
	local thisPlaybackVersion = soundPlaybackVersion

	if currentSoundFadeTween then
		currentSoundFadeTween:Cancel()
		currentSoundFadeTween = nil
	end

	dashSound:Stop()
	dashSound.Volume = DASH_SOUND_VOLUME
	dashSound.PlaybackSpeed = DASH_SOUND_SPEED
	dashSound.TimePosition = DASH_SOUND_START_TIME
	dashSound:Play()

	task.spawn(function()
		RunService.Heartbeat:Wait()

		if thisPlaybackVersion ~= soundPlaybackVersion then
			return
		end

		local soundLength = dashSound.TimeLength
		if soundLength <= 0 then
			return
		end

		local remainingSoundTime =
			(soundLength - DASH_SOUND_START_TIME)
			/ DASH_SOUND_SPEED

		local fadeStartTime =
			math.max(
				remainingSoundTime - DASH_SOUND_FADE_TIME,
				0
			)

		task.wait(fadeStartTime)

		if thisPlaybackVersion ~= soundPlaybackVersion
			or not dashSound.IsPlaying then
			return
		end

		currentSoundFadeTween =
			TweenService:Create(
				dashSound,
				TweenInfo.new(
					DASH_SOUND_FADE_TIME,
					Enum.EasingStyle.Linear,
					Enum.EasingDirection.Out
				),
				{Volume = 0}
			)

		currentSoundFadeTween:Play()
	end)
end

local function tweenFOV(
	targetFOV: number,
	transitionTime: number
)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if currentFOVTween then
		currentFOVTween:Cancel()
	end

	currentFOVTween =
		TweenService:Create(
			camera,
			TweenInfo.new(
				transitionTime,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{FieldOfView = targetFOV}
		)

	currentFOVTween:Play()
end

local function getCorrectFOVAfterDash(): number
	return character:GetAttribute("IsSprinting") == true
		and SPRINT_FOV
		or NORMAL_FOV
end

local function isDashCooldownReady(): boolean
	return workspace:GetServerTimeNow()
		>= dashCooldownEndsAt
end

local function startDashCooldown(
	cooldownDuration: number?
)
	local startsAt = workspace:GetServerTimeNow()

	local resolvedDuration =
		if typeof(cooldownDuration) == "number"
		then math.max(0, cooldownDuration)
		else DASH_COOLDOWN

	dashCooldownEndsAt =
		startsAt + resolvedDuration

	character:SetAttribute(
		"DashCooldownEndsAt",
		dashCooldownEndsAt
	)
	character:SetAttribute(
		"CoreCooldown_Dash_StartsAt",
		startsAt
	)
	character:SetAttribute(
		"CoreCooldown_Dash_EndsAt",
		dashCooldownEndsAt
	)
end

local function stopDashAnimations()
	for _, track in ipairs({
		forwardDashTrack,
		backDashTrack,
		rightDashTrack,
		leftDashTrack,
		}) do
		if track.IsPlaying then
			track:Stop(0.05)
		end
	end
end

local function playDashAnimation(
	track: AnimationTrack,
	speed: number
)
	stopDashAnimations()
	track:Play(0.04)
	track:AdjustSpeed(speed)
end

local function isDownedSystemLocked(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
end

local function isAnyMovementStunned(): boolean
	return character:GetAttribute("IsStunned") == true
		or character:GetAttribute("Status_MovementBlocked") == true
		or character:GetAttribute("Status_Stunned") == true
end

local function isSurfaceWalking(): boolean
	return character:GetAttribute("SurfaceWalking") == true
end

local function isWaterWalking(): boolean
	return character:GetAttribute("WaterWalking") == true
end

local function isGrounded(): boolean
	if isSurfaceWalking() then
		return true
	end

	return GroundingService.IsSolidGrounded(
		character,
		humanoid,
		rootPart
	)
end

local localTreeJumpHasStarted = false
local localTreeJumpHasFinished = false

local function isTreeJumpBusy(): boolean
	if character:GetAttribute("TreeJumpActive") == true then
		return true
	end

	if character:GetAttribute("IsTreeJumping") == true
		and not localTreeJumpHasFinished then
		return true
	end

	return false
end

character:GetAttributeChangedSignal(
	"TreeJumpActive"
):Connect(function()
	local active =
		character:GetAttribute("TreeJumpActive") == true

	if active then
		localTreeJumpHasStarted = true
		localTreeJumpHasFinished = false
	elseif localTreeJumpHasStarted then
		localTreeJumpHasFinished = true
	end
end)

character:GetAttributeChangedSignal(
	"IsTreeJumping"
):Connect(function()
	if character:GetAttribute("IsTreeJumping") ~= true then
		localTreeJumpHasStarted = false
		localTreeJumpHasFinished = false
	end
end)

local WATER_WALK_JUMP_DASH_GRACE = 0.32
local lastWaterWalkJumpTime = -math.huge

-- v4.4: standing on Water Walk is a grounded traversal state and resets
-- the aerial Dash cycle. Leaving by Water Jump starts a fresh air cycle.
character:GetAttributeChangedSignal(
	"WaterWalking"
):Connect(function()
	if character:GetAttribute("WaterWalking") == true then
		jumpAirborne = false
		airDashUsed = false
	else
		if character:GetAttribute("WaterJumping") == true
			or rootPart.AssemblyLinearVelocity.Y > 2 then
			lastWaterWalkJumpTime = time()
		end
	end
end)

character:GetAttributeChangedSignal(
	"WaterJumping"
):Connect(function()
	if character:GetAttribute("WaterJumping") == true then
		lastWaterWalkJumpTime = time()
		jumpAirborne = true
		airDashUsed = false
	end
end)

local function isAirDashAvailable(): boolean
	if not jumpAirborne or airDashUsed then
		return false
	end

	if isTreeJumpBusy() then
		return false
	end

	local state = humanoid:GetState()
	local waterJumping =
		character:GetAttribute("WaterJumping") == true
	local recentWaterWalkJump =
		time() - lastWaterWalkJumpTime
		<= WATER_WALK_JUMP_DASH_GRACE

	if state == Enum.HumanoidStateType.Dead then
		return false
	end

	if state == Enum.HumanoidStateType.Swimming
		and not waterJumping
		and not recentWaterWalkJump then
		return false
	end

	if isSurfaceWalking() and not waterJumping then
		return false
	end

	return waterJumping
		or recentWaterWalkJump
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
end

local function projectOnSurface(
	vector: Vector3,
	normal: Vector3
): Vector3
	return vector - normal * vector:Dot(normal)
end

local function safeUnit(
	vector: Vector3,
	fallback: Vector3?
): Vector3?
	if vector.Magnitude <= 0.05 then
		return fallback
	end

	return vector.Unit
end

local function getSurfaceNormal(): Vector3
	local value =
		character:GetAttribute("SurfaceNormal")

	if typeof(value) == "Vector3"
		and value.Magnitude > 0.5 then
		return value.Unit
	end

	return Vector3.yAxis
end

local function transportSurfaceVector(
	vector: Vector3?,
	oldNormal: Vector3,
	newNormal: Vector3
): Vector3?
	if not vector or vector.Magnitude <= 0.05 then
		return nil
	end

	local axis = oldNormal:Cross(newNormal)
	local axisMagnitude = axis.Magnitude
	local dot = math.clamp(
		oldNormal:Dot(newNormal),
		-1,
		1
	)

	if axisMagnitude <= 0.0001 then
		return safeUnit(
			projectOnSurface(vector, newNormal)
		)
	end

	local angle = math.acos(dot)
	local rotation =
		CFrame.fromAxisAngle(
			axis.Unit,
			angle
		)

	local transported =
		rotation:VectorToWorldSpace(vector)

	return safeUnit(
		projectOnSurface(
			transported,
			newNormal
		)
	)
end

local function getFlatCameraDirections(): (
	Vector3?,
	Vector3?
	)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector

	local flatLook =
		Vector3.new(look.X, 0, look.Z)
	local flatRight =
		Vector3.new(right.X, 0, right.Z)

	return safeUnit(flatLook),
		safeUnit(flatRight)
end

local function getFlatFacingDirection(): Vector3
	local cameraLook = select(
		1,
		getFlatCameraDirections()
	)

	if cameraLook then
		return cameraLook
	end

	local rootLook = rootPart.CFrame.LookVector
	local flatRootLook =
		Vector3.new(rootLook.X, 0, rootLook.Z)

	return flatRootLook.Magnitude > 0.05
		and flatRootLook.Unit
		or Vector3.new(0, 0, -1)
end

local function getAirDashCameraDirection(
	dashType: string
): (Vector3?, Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector

	if look.Magnitude < 0.05
		or right.Magnitude < 0.05 then
		return nil, nil
	end

	look = look.Unit
	right = right.Unit

	local dashDirection: Vector3?

	if dashType == "Forward" then
		dashDirection = look
	elseif dashType == "Back" then
		dashDirection = -look
	elseif dashType == "Right" then
		dashDirection = right
	elseif dashType == "Left" then
		dashDirection = -right
	end

	if not dashDirection
		or dashDirection.Magnitude < 0.05 then
		return nil, nil
	end

	local facing =
		Vector3.new(look.X, 0, look.Z)

	if facing.Magnitude < 0.05 then
		local rootLook = rootPart.CFrame.LookVector
		facing =
			Vector3.new(
				rootLook.X,
				0,
				rootLook.Z
			)
	end

	return dashDirection.Unit,
		facing.Magnitude > 0.05
		and facing.Unit
		or nil
end

local function rotateDirectionTowards(
	current: Vector3,
	desired: Vector3,
	maxRadians: number
): Vector3
	if current.Magnitude <= 0.05
		or desired.Magnitude <= 0.05 then
		return current
	end

	local c = current.Unit
	local d = desired.Unit
	local dot = math.clamp(c:Dot(d), -1, 1)
	local angle = math.acos(dot)

	if angle <= 0.0001 then
		return d
	end

	local alpha =
		math.min(1, maxRadians / angle)

	local mixed = c:Lerp(d, alpha)

	return mixed.Magnitude > 0.05
		and mixed.Unit
		or c
end

local function isCombatMode(): boolean
	return character:GetAttribute("CombatMode") == true
		and character:GetAttribute("CombatSuppressed") ~= true
end

local function isRestrictedDash(): boolean
	return (
		StaminaConfig.Dash.RestrictedByCombatMode
			and character:GetAttribute("CombatMode") == true
	)
		or (
			StaminaConfig.Dash.RestrictedByCombatTag
			and character:GetAttribute("CombatTagged") == true
		)
end

local function getDashStaminaSettings(
	airDash: boolean
): (number, number, boolean)
	local restricted = isRestrictedDash()

	local profile =
		restricted
		and StaminaConfig.Dash.Restricted
		or StaminaConfig.Dash.OpenWorld

	local cost =
		airDash
		and profile.AirCost
		or profile.GroundCost

	return cost,
		profile.Cooldown,
		restricted
end

local function hasLocalStaminaForDash(
	cost: number
): boolean
	local current =
		character:GetAttribute("Stamina")

	if typeof(current) ~= "number" then
		return true
	end

	return current >= cost
end

local function lockCharacterFacing(
	direction: Vector3?
)
	if not direction
		or direction.Magnitude <= 0.05 then
		return
	end

	local flat =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	if flat.Magnitude <= 0.05 then
		return
	end

	local position = rootPart.Position
	rootPart.CFrame =
		CFrame.lookAt(
			position,
			position + flat.Unit,
			Vector3.yAxis
		)
end

local function restoreFacingOwnershipAfterDash()
	character:SetAttribute(
		"SurfaceDashFacingDirection",
		Vector3.zero
	)

	if not isSurfaceWalking() then
		humanoid.AutoRotate =
			not isCombatMode()
	end
end

local function captureBackDashDirection()
	local forward, _right =
		getFlatCameraDirections()

	if forward then
		bufferedBackDirection = -forward
		bufferedBackFacingDirection = forward
	end
end

local function captureLeftDashDirection()
	local forward, right =
		getFlatCameraDirections()

	if right then
		bufferedLeftDirection = -right
		bufferedLeftFacingDirection =
			forward or getFlatFacingDirection()
	end
end

local function captureRightDashDirection()
	local forward, right =
		getFlatCameraDirections()

	if right then
		bufferedRightDirection = right
		bufferedRightFacingDirection =
			forward or getFlatFacingDirection()
	end
end

local function getGroundDashDirection(
	dashType: string
): (Vector3?, Vector3?)
	if isSurfaceWalking() then
		local normal = getSurfaceNormal()
		local camera = workspace.CurrentCamera

		if not camera then
			return nil, nil
		end

		local forward =
			safeUnit(
				projectOnSurface(
					camera.CFrame.LookVector,
					normal
				),
				safeUnit(
					projectOnSurface(
						rootPart.CFrame.LookVector,
						normal
					)
				)
			)

		local right =
			safeUnit(
				projectOnSurface(
					camera.CFrame.RightVector,
					normal
				)
			)

		if not forward then
			return nil, nil
		end

		local direction: Vector3?

		if dashType == "Forward" then
			direction = forward
		elseif dashType == "Back" then
			direction = -forward
		elseif dashType == "Right" then
			direction = right
		elseif dashType == "Left" and right then
			direction = -right
		end

		return direction,
			forward
	end

	local forward, right =
		getFlatCameraDirections()

	if not forward then
		forward = getFlatFacingDirection()
	end

	if not right then
		right =
			Vector3.yAxis:Cross(forward).Unit
	end

	if dashType == "Forward" then
		return forward, forward
	elseif dashType == "Back" then
		return bufferedBackDirection or -forward,
			bufferedBackFacingDirection or forward
	elseif dashType == "Right" then
		return bufferedRightDirection or right,
			bufferedRightFacingDirection or forward
	elseif dashType == "Left" then
		return bufferedLeftDirection or -right,
			bufferedLeftFacingDirection or forward
	end

	return forward, forward
end

local function shouldLockFacing(
	dashType: string
): boolean
	return dashType == "Back"
		or dashType == "Left"
		or dashType == "Right"
end

local function getCombatRequestedDashType(): string
	local requestedDashType = "Forward"
	local newestPressTime = -math.huge

	if UserInputService:IsKeyDown(Enum.KeyCode.S)
		and lastSPressTime > newestPressTime then
		newestPressTime = lastSPressTime
		requestedDashType = "Back"
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.A)
		and lastAPressTime > newestPressTime then
		newestPressTime = lastAPressTime
		requestedDashType = "Left"
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.D)
		and lastDPressTime > newestPressTime then
		requestedDashType = "Right"
	end

	return requestedDashType
end

character:GetAttributeChangedSignal(
	"CombatMode"
):Connect(function()
	lastSPressTime = -math.huge
	lastAPressTime = -math.huge
	lastDPressTime = -math.huge
	bufferedBackDirection = nil
	bufferedBackFacingDirection = nil
	bufferedLeftDirection = nil
	bufferedLeftFacingDirection = nil
	bufferedRightDirection = nil
	bufferedRightFacingDirection = nil
end)

dashSpendResult.OnClientEvent:Connect(function(
	requestId: any,
	success: any,
	_reason: any,
	_remaining: any,
	_cost: any,
	cooldown: any,
	_restricted: any
)
	if typeof(requestId) ~= "number"
		or requestId ~= activeDashSpendRequestId then
		return
	end

	if success ~= true then
		dashSpendDenied = true
		return
	end

	if typeof(cooldown) == "number" then
		activeDashCooldownDuration =
			math.max(0, cooldown)
	end
end)

local function preserveGroundMomentum(
	dashType: string,
	lockedFacingDirection: Vector3?,
	surfaceDash: boolean
)
	if POST_DASH_MOMENTUM_TIME <= 0 then
		return
	end

	if isAnyMovementStunned() then
		return
	end

	if surfaceDash and isSurfaceWalking() then
		local normal = getSurfaceNormal()
		local startVelocity =
			projectOnSurface(
				rootPart.AssemblyLinearVelocity,
				normal
			)

		local startTime = time()

		while time() - startTime
			< POST_DASH_MOMENTUM_TIME do

			if humanoid.Health <= 0
				or isDownedSystemLocked()
				or isAnyMovementStunned() then
				break
			end

			if not isSurfaceWalking() then
				break
			end

			local elapsed = time() - startTime
			local alpha =
				math.clamp(
					elapsed
					/ POST_DASH_MOMENTUM_TIME,
					0,
					1
				)

			normal = getSurfaceNormal()
			startVelocity =
				projectOnSurface(
					startVelocity,
					normal
				)

			local targetVelocity = Vector3.zero
			local surfaceMoving =
				character:GetAttribute("SurfaceMoving")
				== true
			local moveDirection =
				character:GetAttribute(
					"SurfaceMoveDirection"
				)

			if surfaceMoving
				and typeof(moveDirection) == "Vector3"
				and moveDirection.Magnitude > 0.05 then

				targetVelocity =
					projectOnSurface(
						moveDirection.Unit
						* humanoid.WalkSpeed,
						normal
					)
			end

			rootPart.AssemblyLinearVelocity =
				startVelocity:Lerp(
					targetVelocity,
					alpha
				)
			- normal * 3

			RunService.Heartbeat:Wait()
		end

		return
	end

	local startVelocity =
		rootPart.AssemblyLinearVelocity
	local startHorizontalVelocity =
		Vector3.new(
			startVelocity.X,
			0,
			startVelocity.Z
		)

	local startTime = time()

	while time() - startTime
		< POST_DASH_MOMENTUM_TIME do

		if humanoid.Health <= 0
			or isDownedSystemLocked()
			or isAnyMovementStunned() then
			break
		end

		local alpha =
			math.clamp(
				(time() - startTime)
				/ POST_DASH_MOMENTUM_TIME,
				0,
				1
			)

		local moveDirection = humanoid.MoveDirection
		local targetHorizontalVelocity =
			moveDirection.Magnitude > 0.05
			and moveDirection.Unit * humanoid.WalkSpeed
			or Vector3.zero

		local newHorizontalVelocity =
			startHorizontalVelocity:Lerp(
				targetHorizontalVelocity,
				alpha
			)

		local currentY =
			rootPart.AssemblyLinearVelocity.Y

		rootPart.AssemblyLinearVelocity =
			Vector3.new(
				newHorizontalVelocity.X,
				currentY,
				newHorizontalVelocity.Z
			)

		if shouldLockFacing(dashType)
			or isCombatMode() then
			lockCharacterFacing(
				lockedFacingDirection
			)
		end

		RunService.Heartbeat:Wait()
	end
end

local function preserveAirDashArc(
	dashType: string,
	lockedFacingDirection: Vector3?
)
	local startVelocity =
		rootPart.AssemblyLinearVelocity

	local carriedHorizontal =
		Vector3.new(
			startVelocity.X,
			0,
			startVelocity.Z
		)

	character:SetAttribute(
		"AirDashCarryActive",
		true
	)

	local carryStartedAt = time()
	local lastCarryStepAt = carryStartedAt

	while character.Parent
		and humanoid.Health > 0 do

		if isDownedSystemLocked()
			or isAnyMovementStunned() then
			break
		end

		if isSurfaceWalking()
			or isWaterWalking() then
			break
		end

		local state = humanoid:GetState()

		-- During the short WaterJumping handoff, do not treat a transient
		-- Swimming frame as a real swim cancellation.
		if state == Enum.HumanoidStateType.Swimming
			and character:GetAttribute("WaterJumping") ~= true
			and time() - lastWaterWalkJumpTime
			> WATER_WALK_JUMP_DASH_GRACE then
			break
		end

		if isGrounded() then
			break
		end

		if time() - carryStartedAt
			>= AIR_DASH_CARRY_FAILSAFE_TIME then
			warn(
				"[DashController] AirDashCarry failsafe released after "
					.. tostring(
						AIR_DASH_CARRY_FAILSAFE_TIME
					)
					.. "s"
			)
			break
		end

		local currentVelocity =
			rootPart.AssemblyLinearVelocity

		local now = time()
		local dt =
			math.clamp(
				now - lastCarryStepAt,
				0,
				0.05
			)
		lastCarryStepAt = now

		local airControlMultiplier =
			StatusCombatModifierReader
			.GetAirControlMultiplier(
				character
			)

		local desiredAirDirection,
			desiredFacing =
			getAirDashCameraDirection(dashType)

		if desiredAirDirection
			and carriedHorizontal.Magnitude > 0.05 then

			local desiredHorizontal =
				Vector3.new(
					desiredAirDirection.X,
					0,
					desiredAirDirection.Z
				)

			if desiredHorizontal.Magnitude > 0.05 then
				local horizontalSpeed =
					carriedHorizontal.Magnitude

				carriedHorizontal =
					rotateDirectionTowards(
						carriedHorizontal,
						desiredHorizontal.Unit,
						AIR_DASH_CARRY_STEER_RAD_PER_SEC
						* airControlMultiplier
						* dt
					)
					* horizontalSpeed
			end
		end

		if desiredFacing
			and lockedFacingDirection then
			lockedFacingDirection =
				rotateDirectionTowards(
					lockedFacingDirection,
					desiredFacing,
					AIR_DASH_CARRY_STEER_RAD_PER_SEC
					* airControlMultiplier
					* dt
				)
		end

		rootPart.AssemblyLinearVelocity =
			Vector3.new(
				carriedHorizontal.X,
				currentVelocity.Y,
				carriedHorizontal.Z
			)

		if shouldLockFacing(dashType)
			or isCombatMode() then
			lockCharacterFacing(
				lockedFacingDirection
			)
		end

		RunService.Heartbeat:Wait()
	end

	character:SetAttribute(
		"AirDashCarryActive",
		false
	)
end

local function performDash(dashType: string)
	if isDashing
		or not isDashCooldownReady()
		or humanoid.Health <= 0
		or isDownedSystemLocked()
		or isAnyMovementStunned()
		or character:GetAttribute("ChakraCharging") == true
		or isTreeJumpBusy() then
		return
	end

	local airDash = isAirDashAvailable()
	local surfaceDash =
		isSurfaceWalking() and not airDash

	if not airDash
		and not surfaceDash
		and not isGrounded() then
		return
	end

	if airDash and airDashUsed then
		return
	end

	local cost, fallbackCooldown =
		getDashStaminaSettings(airDash)

	if not hasLocalStaminaForDash(cost) then
		return
	end

	isDashing = true
	character:SetAttribute("IsDashing", true)
	character:SetAttribute(
		"SurfaceDashFacingDirection",
		Vector3.zero
	)

	humanoid.AutoRotate = false

	local dashDirection: Vector3?
	local lockedFacingDirection: Vector3?

	if airDash then
		dashDirection,
			lockedFacingDirection =
			getAirDashCameraDirection(dashType)
	else
		dashDirection,
			lockedFacingDirection =
			getGroundDashDirection(dashType)
	end

	if not dashDirection
		or dashDirection.Magnitude <= 0.05 then
		isDashing = false
		character:SetAttribute("IsDashing", false)
		restoreFacingOwnershipAfterDash()
		return
	end

	dashDirection = dashDirection.Unit

	if surfaceDash then
		character:SetAttribute(
			"SurfaceDashFacingDirection",
			lockedFacingDirection
				or Vector3.zero
		)
	end

	if lockedFacingDirection then
		lockCharacterFacing(
			lockedFacingDirection
		)
	end

	if dashType == "Forward" then
		playDashAnimation(
			forwardDashTrack,
			FORWARD_DASH_ANIMATION_SPEED
		)
	elseif dashType == "Back" then
		playDashAnimation(
			backDashTrack,
			BACK_DASH_ANIMATION_SPEED
		)
	elseif dashType == "Right" then
		playDashAnimation(
			rightDashTrack,
			RIGHT_DASH_ANIMATION_SPEED
		)
	elseif dashType == "Left" then
		playDashAnimation(
			leftDashTrack,
			LEFT_DASH_ANIMATION_SPEED
		)
	end

	playDashSound()

	dashSpendSequence += 1
	activeDashSpendRequestId =
		dashSpendSequence
	dashSpendDenied = false
	activeDashCooldownDuration =
		fallbackCooldown

	dashSpendRequest:FireServer(
		activeDashSpendRequestId,
		airDash
	)

	if airDash then
		airDashUsed = true
	end

	tweenFOV(
		DASH_FOV,
		DASH_FOV_IN_TIME
	)

	local dashDistanceMultiplier =
		StatusCombatModifierReader
		.GetDashDistanceMultiplier(
			character
		)

	-- Heavy changes dash travel only; cooldown/stamina/duration stay authored.
	local currentDashSpeed =
		(
			airDash
			and AIR_DASH_SPEED
			or DASH_SPEED
		)
		* dashDistanceMultiplier

	local currentDashDuration =
		airDash
		and AIR_DASH_DURATION
		or DASH_DURATION

	local dashStartTime = time()
	local lastDashStepAt = dashStartTime
	local interrupted = false
	local surfaceDashNormal =
		surfaceDash and getSurfaceNormal()
		or nil

	while time() - dashStartTime
		< currentDashDuration do

		if dashSpendDenied
			or humanoid.Health <= 0
			or isDownedSystemLocked()
			or isAnyMovementStunned() then
			interrupted = true
			break
		end

		if surfaceDash
			and isSurfaceWalking() then

			local liveNormal =
				getSurfaceNormal()

			if surfaceDashNormal
				and liveNormal:Dot(
					surfaceDashNormal
				) < 0.9999 then

				local transportedDirection =
					transportSurfaceVector(
						dashDirection,
						surfaceDashNormal,
						liveNormal
					)

				local transportedFacing =
					transportSurfaceVector(
						lockedFacingDirection,
						surfaceDashNormal,
						liveNormal
					)

				if transportedDirection then
					dashDirection =
						transportedDirection
				end

				if transportedFacing then
					lockedFacingDirection =
						transportedFacing

					character:SetAttribute(
						"SurfaceDashFacingDirection",
						transportedFacing
					)
				end

				surfaceDashNormal = liveNormal
			end
		end

		if airDash then
			local now = time()
			local dt =
				math.clamp(
					now - lastDashStepAt,
					0,
					0.05
				)
			lastDashStepAt = now

			local airControlMultiplier =
				StatusCombatModifierReader
				.GetAirControlMultiplier(
					character
				)

			local desiredAirDirection,
				desiredFacing =
				getAirDashCameraDirection(
					dashType
				)

			if desiredAirDirection then
				dashDirection =
					rotateDirectionTowards(
						dashDirection,
						desiredAirDirection,
						AIR_DASH_POWERED_STEER_RAD_PER_SEC
						* airControlMultiplier
						* dt
					)
			end

			if desiredFacing
				and lockedFacingDirection then
				lockedFacingDirection =
					rotateDirectionTowards(
						lockedFacingDirection,
						desiredFacing,
						AIR_DASH_POWERED_STEER_RAD_PER_SEC
						* airControlMultiplier
						* dt
					)
			end
		end

		rootPart.AssemblyLinearVelocity =
			dashDirection * currentDashSpeed

		if not surfaceDash
			and (
				shouldLockFacing(dashType)
					or isCombatMode()
			) then
			lockCharacterFacing(
				lockedFacingDirection
			)
		end

		RunService.Heartbeat:Wait()
	end

	if interrupted then
		stopDashAnimations()

		local velocity =
			rootPart.AssemblyLinearVelocity

		rootPart.AssemblyLinearVelocity =
			Vector3.new(
				0,
				velocity.Y,
				0
			)

		character:SetAttribute(
			"AirDashCarryActive",
			false
		)
	else
		if airDash then
			tweenFOV(
				getCorrectFOVAfterDash(),
				DASH_FOV_OUT_TIME
			)
			preserveAirDashArc(
				dashType,
				lockedFacingDirection
			)
		else
			preserveGroundMomentum(
				dashType,
				lockedFacingDirection,
				surfaceDash
			)
		end
	end

	if not airDash then
		tweenFOV(
			getCorrectFOVAfterDash(),
			DASH_FOV_OUT_TIME
		)
	end

	stopDashAnimations()

	character:SetAttribute(
		"SurfaceDashFacingDirection",
		Vector3.zero
	)
	character:SetAttribute(
		"AirDashCarryActive",
		false
	)
	character:SetAttribute(
		"IsDashing",
		false
	)

	isDashing = false
	restoreFacingOwnershipAfterDash()

	if not dashSpendDenied then
		startDashCooldown(
			activeDashCooldownDuration
		)
	end
end

humanoid.StateChanged:Connect(function(_, newState)
	if isTreeJumpBusy() then
		return
	end

	if newState == Enum.HumanoidStateType.Jumping then
		if not jumpAirborne then
			jumpAirborne = true
			airDashUsed = false
		end

	elseif newState == Enum.HumanoidStateType.Landed then
		jumpAirborne = false
		airDashUsed = false

	elseif newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.RunningNoPhysics then

		if isWaterWalking() then
			jumpAirborne = false
			airDashUsed = false
		elseif GroundingService.IsSolidGrounded(
			character,
			humanoid,
			rootPart
			) then
			jumpAirborne = false
			airDashUsed = false
		end

	elseif newState == Enum.HumanoidStateType.Swimming then
		if character:GetAttribute("WaterJumping") ~= true
			and time() - lastWaterWalkJumpTime
			> WATER_WALK_JUMP_DASH_GRACE then

			jumpAirborne = false
			airDashUsed = false
		end
	end
end)

character:GetAttributeChangedSignal(
	"TreeJumpActive"
):Connect(function()
	if character:GetAttribute("TreeJumpActive") == true then
		jumpAirborne = false
		airDashUsed = false
	end
end)

local function onStatusMovementBlockedChanged()
	if not isAnyMovementStunned() then
		return
	end

	if not isDashing
		and character:GetAttribute("IsDashing") ~= true then
		return
	end

	local velocity =
		rootPart.AssemblyLinearVelocity

	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			0,
			velocity.Y,
			0
		)

	rootPart.AssemblyAngularVelocity =
		Vector3.zero
end

character:GetAttributeChangedSignal(
	"Status_MovementBlocked"
):Connect(onStatusMovementBlockedChanged)

character:GetAttributeChangedSignal(
	"Status_Stunned"
):Connect(onStatusMovementBlockedChanged)

UserInputService.InputBegan:Connect(function(
	input: InputObject,
	gameProcessed: boolean
)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.S then
		lastSPressTime = time()
		captureBackDashDirection()
	end

	if input.KeyCode == Enum.KeyCode.A then
		lastAPressTime = time()
		captureLeftDashDirection()
	end

	if input.KeyCode == Enum.KeyCode.D then
		lastDPressTime = time()
		captureRightDashDirection()
	end

	if input.KeyCode ~= DASH_KEY then
		return
	end

	local currentTime = time()

	local backDashRequested =
		UserInputService:IsKeyDown(Enum.KeyCode.S)
		or currentTime - lastSPressTime
		<= BACK_DASH_INPUT_WINDOW

	local leftDashRequested =
		UserInputService:IsKeyDown(Enum.KeyCode.A)
		or currentTime - lastAPressTime
		<= SIDE_DASH_INPUT_WINDOW

	local rightDashRequested =
		UserInputService:IsKeyDown(Enum.KeyCode.D)
		or currentTime - lastDPressTime
		<= SIDE_DASH_INPUT_WINDOW

	local requestedDashType: string

	if isCombatMode() then
		requestedDashType =
			getCombatRequestedDashType()
	else
		requestedDashType = "Forward"
		local newestPressTime = -math.huge

		if backDashRequested
			and lastSPressTime > newestPressTime then
			newestPressTime = lastSPressTime
			requestedDashType = "Back"
		end

		if leftDashRequested
			and lastAPressTime > newestPressTime then
			newestPressTime = lastAPressTime
			requestedDashType = "Left"
		end

		if rightDashRequested
			and lastDPressTime > newestPressTime then
			requestedDashType = "Right"
		end
	end

	performDash(requestedDashType)
end)

print(
	"[DashController] READY v4.6 StatusFXDirect+HeavyMovement"
		.. " | Stamina=ON"
		.. " | OpenGroundCost="
		.. tostring(
			StaminaConfig.Dash.OpenWorld.GroundCost
		)
		.. " | OpenAirCost="
		.. tostring(
			StaminaConfig.Dash.OpenWorld.AirCost
		)
		.. " | RestrictedGroundCost="
		.. tostring(
			StaminaConfig.Dash.Restricted.GroundCost
		)
		.. " | RestrictedAirCost="
		.. tostring(
			StaminaConfig.Dash.Restricted.AirCost
		)
		.. " | CombatTagRestriction=ON"
		.. " | WaterJumpDash=RELIABLE"
		.. " | WaterWalkCycleReset=ON"
		.. " | StatusStun=ON"
		.. " | SlowAffectsDash=OFF"
		.. " | StatusDashDistanceMultiplier=ON"
		.. " | StatusAirControlMultiplier=ON"
)
