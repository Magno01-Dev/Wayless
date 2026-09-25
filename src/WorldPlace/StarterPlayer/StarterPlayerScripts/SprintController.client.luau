--!strict
-- SprintController v1.17 - Generic Movement Restrictions + StatusFX Direct + Combat Directional Run + Clean Lunge Handoff
-- INSTALL: StarterPlayer > StarterPlayerScripts > SprintController [LocalScript]
--
-- Preserves:
-- - Walk 16 / Sprint 44
-- - Combat backward Sprint OFF
-- - Forward/Left/Right directional Run
-- - Carry airborne run legs
-- - Swimming animation speed handoff
-- - M1MovementSpeedCap
-- - Block speed
-- - Dash-owned FOV handoff
-- - Generic Movement_SprintLocked / Movement_WalkSpeedCap restrictions
--
-- StatusFX:
-- - Status_MoveSpeedMultiplier scales Walk/Sprint/Block/M1 locomotion.
-- - Status_MovementBlocked / Status_Stunned behave as movement stun.
-- - Dash speed is NOT owned here and is NOT scaled here.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundingService = require(
	ReplicatedStorage:WaitForChild("GroundingService")
)

local player = Players.LocalPlayer

local WALK_SPEED = 16
local SPRINT_SPEED = 44
local ATTACK_MOVEMENT_BASE_SPEED = 24
local BLOCK_WALK_SPEED = 8
local COMBAT_BACKWARD_SPRINT_DOT_THRESHOLD = -0.05

local NORMAL_FOV = 70
local SPRINT_FOV = 80
local FOV_TRANSITION_TIME = 0.25

local RUN_ANIMATION_ID = "rbxassetid://116142758807536"
local LEFT_RUN_ANIMATION_ID = "rbxassetid://96610792244949"
local RIGHT_RUN_ANIMATION_ID = "rbxassetid://121603680342672"
local RUN_ANIMATION_SPEED = 1.4
local COMBAT_DIRECTIONAL_RUN_LATERAL_THRESHOLD = 0.35
local SWIM_SPRINT_ANIMATION_SPEED = 1.5

local character: Model?
local humanoid: Humanoid?
local animator: Animator?
local animate: Instance?
local runTrack: AnimationTrack?
local leftRunTrack: AnimationTrack?
local rightRunTrack: AnimationTrack?
local activeRunTrack: AnimationTrack?

local swimAnimationIds: {[string]: boolean} = {}
local sprinting = false
local sprintVisualsActive = false
local currentFOVTween: Tween?
local stateConnection: RBXScriptConnection?
local animationPlayedConnection: RBXScriptConnection?
local attributeConnections: {RBXScriptConnection} = {}

local function disconnectAttributeConnections()
	for _, connection in ipairs(attributeConnections) do
		connection:Disconnect()
	end
	table.clear(attributeConnections)
end

local function tweenFOV(targetFOV: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if currentFOVTween then
		currentFOVTween:Cancel()
	end

	currentFOVTween = TweenService:Create(
		camera,
		TweenInfo.new(
			FOV_TRANSITION_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{FieldOfView = targetFOV}
	)
	currentFOVTween:Play()
end

local function isSurfaceWalking(): boolean
	return character ~= nil
		and character:GetAttribute("SurfaceWalking") == true
end

local function isCharacterMoving(): boolean
	if not humanoid then
		return false
	end

	if isSurfaceWalking() and character then
		return character:GetAttribute("SurfaceMoving") == true
	end

	return humanoid.MoveDirection.Magnitude > 0.05
end

local function isSwimming(): boolean
	return humanoid ~= nil
		and humanoid:GetState() == Enum.HumanoidStateType.Swimming
		and not (
			character
			and character:GetAttribute("WaterWalking") == true
		)
end

local function collectAnimationIds(container: Instance?): {[string]: boolean}
	local ids: {[string]: boolean} = {}

	if not container then
		return ids
	end

	if container:IsA("Animation") and container.AnimationId ~= "" then
		ids[container.AnimationId] = true
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Animation") and descendant.AnimationId ~= "" then
			ids[descendant.AnimationId] = true
		end
	end

	return ids
end

local function refreshSwimAnimationIds()
	swimAnimationIds = {}

	if not animate then
		return
	end

	local swimContainer = animate:FindFirstChild("swim")
	local swimIdleContainer = animate:FindFirstChild("swimidle")

	for id in pairs(collectAnimationIds(swimContainer)) do
		swimAnimationIds[id] = true
	end

	for id in pairs(collectAnimationIds(swimIdleContainer)) do
		swimAnimationIds[id] = true
	end
end

local function isSwimTrack(track: AnimationTrack): boolean
	local animation = track.Animation
	if not animation then
		return false
	end

	return swimAnimationIds[animation.AnimationId] == true
end

local function updateSwimAnimationSpeed(sprintActive: boolean)
	if not animator then
		return
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if isSwimTrack(track) then
			track:AdjustSpeed(
				sprintActive and SWIM_SPRINT_ANIMATION_SPEED or 1.0
			)
		end
	end
end

local function isCharacterGrounded(): boolean
	if not character or not humanoid then
		return false
	end

	if isSurfaceWalking() then
		return true
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	return GroundingService.IsSolidGrounded(
		character,
		humanoid,
		root
	)
end

local function stopRunAnimation()
	for _, track in ipairs({
		runTrack,
		leftRunTrack,
		rightRunTrack,
		}) do
		if track and track.IsPlaying then
			track:Stop(0.05)
		end
	end

	activeRunTrack = nil
end

local function getDesiredRunTrack(): AnimationTrack?
	if not character or not humanoid or not runTrack then
		return nil
	end

	if character:GetAttribute("CombatMode") ~= true then
		return runTrack
	end

	local moveDirection = humanoid.MoveDirection

	if isSurfaceWalking() then
		local surfaceMoveDirection =
			character:GetAttribute("SurfaceMoveDirection")

		if typeof(surfaceMoveDirection) == "Vector3"
			and surfaceMoveDirection.Magnitude > 0.05 then

			moveDirection = surfaceMoveDirection
		end
	end

	if moveDirection.Magnitude <= 0.05 then
		return runTrack
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return runTrack
	end

	local right = root.CFrame.RightVector
	local lateralDot = moveDirection.Unit:Dot(right.Unit)

	if lateralDot >= COMBAT_DIRECTIONAL_RUN_LATERAL_THRESHOLD then
		return rightRunTrack or runTrack
	end

	if lateralDot <= -COMBAT_DIRECTIONAL_RUN_LATERAL_THRESHOLD then
		return leftRunTrack or runTrack
	end

	return runTrack
end

local function startRunAnimation()
	local desiredTrack = getDesiredRunTrack()
	if not desiredTrack then
		return
	end

	if activeRunTrack ~= desiredTrack then
		if activeRunTrack and activeRunTrack.IsPlaying then
			activeRunTrack:Stop(0.06)
		end
		activeRunTrack = desiredTrack
	end

	if not desiredTrack.IsPlaying then
		desiredTrack:Play(0.06)
	end

	desiredTrack:AdjustSpeed(RUN_ANIMATION_SPEED)
end

local function startSprintVisuals()
	if sprintVisualsActive then
		return
	end

	sprintVisualsActive = true

	if character
		and character:GetAttribute("IsDashing") == true then
		return
	end

	tweenFOV(SPRINT_FOV)
end

local function stopSprintVisuals()
	if not sprintVisualsActive then
		return
	end

	sprintVisualsActive = false

	if character
		and character:GetAttribute("IsDashing") == true then
		return
	end

	tweenFOV(NORMAL_FOV)
end

local function isDownedSystemLocked(): boolean
	if not character then
		return true
	end

	-- IsCarrying intentionally remains allowed.
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
end

local function shouldKeepCarryRunLegsAirborne(
	sprintActive: boolean
): boolean
	if not sprintActive or not character or not humanoid then
		return false
	end

	if character:GetAttribute("IsCarrying") ~= true then
		return false
	end

	local state = humanoid:GetState()

	return state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
end

local function getM1MovementSpeedCap(): number?
	if not character then
		return nil
	end

	local value = character:GetAttribute("M1MovementSpeedCap")
	if typeof(value) ~= "number" then
		return nil
	end

	return math.max(0, value)
end

-- ============================================================
-- STATUSFX DIRECT
-- ============================================================

local function isStatusMovementBlocked(): boolean
	if not character then
		return false
	end

	return character:GetAttribute("Status_MovementBlocked") == true
		or character:GetAttribute("Status_Stunned") == true
end

local function isAnyMovementStunned(): boolean
	if not character then
		return false
	end

	return character:GetAttribute("IsStunned") == true
		or isStatusMovementBlocked()
end

local function getStatusMoveSpeedMultiplier(): number
	if not character then
		return 1
	end

	local value = character:GetAttribute("Status_MoveSpeedMultiplier")
	if typeof(value) ~= "number" then
		return 1
	end

	return math.clamp(value, 0, 3)
end

-- ============================================================
-- GENERIC MOVEMENT RESTRICTIONS
-- ============================================================
--
-- Server-side systems can publish these attributes on Character:
--
-- Movement_SprintLocked      : boolean
-- Movement_WalkSpeedCap      : number?
-- Movement_RestrictionUntil  : server time number?
--
-- This is intentionally generic and is not tied to FlameBreath.
-- Any future jutsu/system can use the same contract.
--
-- Legacy JutsuRunLocked attributes are still honored so older
-- jutsus/controllers remain compatible during migration.

local function isRestrictionTimeActive(
	untilAttributeName: string
): boolean
	if not character then
		return false
	end

	local untilTime = character:GetAttribute(untilAttributeName)

	if typeof(untilTime) ~= "number" then
		return true
	end

	return workspace:GetServerTimeNow() < untilTime
end

local function isGenericRestrictionActive(): boolean
	if not character then
		return false
	end

	local hasSprintLock =
		character:GetAttribute("Movement_SprintLocked") == true

	local hasWalkSpeedCap =
		typeof(
			character:GetAttribute("Movement_WalkSpeedCap")
		) == "number"

	return (hasSprintLock or hasWalkSpeedCap)
		and isRestrictionTimeActive("Movement_RestrictionUntil")
end

local function isGenericSprintLocked(): boolean
	if not character then
		return false
	end

	return isGenericRestrictionActive()
		and character:GetAttribute("Movement_SprintLocked") == true
end

local function isLegacyJutsuSprintLocked(): boolean
	if not character then
		return false
	end

	return character:GetAttribute("JutsuRunLocked") == true
		and isRestrictionTimeActive("JutsuRunLockedUntil")
end

local function isSprintMovementLocked(): boolean
	return isGenericSprintLocked()
		or isLegacyJutsuSprintLocked()
end

local function getMovementWalkSpeedCap(): number?
	if not character then
		return nil
	end

	local cap: number? = nil

	if isGenericRestrictionActive() then
		local genericCap =
			character:GetAttribute("Movement_WalkSpeedCap")

		if typeof(genericCap) == "number" then
			cap = math.max(0, genericCap)
		end
	end

	if isLegacyJutsuSprintLocked() then
		local legacyCap =
			character:GetAttribute("JutsuRunLockWalkSpeed")

		if typeof(legacyCap) == "number" then
			local resolvedLegacyCap =
				math.max(0, legacyCap)

			cap =
				if cap == nil
				then resolvedLegacyCap
				else math.min(cap, resolvedLegacyCap)
		end
	end

	return cap
end

local function applyMovementCap(baseSpeed: number): number
	if isStatusMovementBlocked() then
		return 0
	end

	local m1Cap = getM1MovementSpeedCap()

	local resolvedSpeed =
		if m1Cap == nil
		then baseSpeed
		else math.min(baseSpeed, m1Cap)

	resolvedSpeed =
		math.max(
			0,
			resolvedSpeed * getStatusMoveSpeedMultiplier()
		)

	-- Generic movement restrictions are absolute final caps.
	-- Example: FlameBreath sets 16, so even sprint's base 44
	-- resolves to a maximum of 16.
	local restrictionCap =
		getMovementWalkSpeedCap()

	if restrictionCap ~= nil then
		resolvedSpeed =
			math.min(
				resolvedSpeed,
				restrictionCap
			)
	end

	return math.max(
		0,
		resolvedSpeed
	)
end

local function isCombatBackwardMovement(): boolean
	if not character
		or not humanoid
		or character:GetAttribute("CombatMode") ~= true then
		return false
	end

	local moveDirection = humanoid.MoveDirection

	if isSurfaceWalking() then
		local surfaceMoveDirection =
			character:GetAttribute("SurfaceMoveDirection")

		if typeof(surfaceMoveDirection) == "Vector3"
			and surfaceMoveDirection.Magnitude > 0.05 then
			moveDirection = surfaceMoveDirection
		end
	end

	if moveDirection.Magnitude <= 0.05 then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local facing = root.CFrame.LookVector
	if facing.Magnitude <= 0.05 then
		return false
	end

	return moveDirection.Unit:Dot(facing.Unit)
		< COMBAT_BACKWARD_SPRINT_DOT_THRESHOLD
end

local function updateSprint()
	if not humanoid or not runTrack or not character then
		return
	end

	if isDownedSystemLocked() then
		sprinting = false
		character:SetAttribute("IsSprinting", false)
		humanoid.WalkSpeed = 0
		stopSprintVisuals()
		stopRunAnimation()
		return
	end

	local isMoving = isCharacterMoving()
	local isGrounded = isCharacterGrounded()
	local isBlocking = character:GetAttribute("IsBlocking") == true
	local isStunned = isAnyMovementStunned()
	local isAttacking = character:GetAttribute("IsAttacking") == true
	local combatBackwardMovement = isCombatBackwardMovement()
	local sprintMovementLocked = isSprintMovementLocked()

	local sprintActive =
		sprinting
		and isMoving
		and not isBlocking
		and not isStunned
		and not isAttacking
		and not combatBackwardMovement
		and not sprintMovementLocked

	character:SetAttribute("IsSprinting", sprintActive)

	if isStunned then
		humanoid.WalkSpeed = 0

		if isStatusMovementBlocked()
			and character:GetAttribute("IsDashing") ~= true
			and not isSurfaceWalking() then

			local root = character:FindFirstChild("HumanoidRootPart")

			if root and root:IsA("BasePart") then
				local velocity = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity =
					Vector3.new(0, velocity.Y, 0)
			end
		end

		stopSprintVisuals()
		stopRunAnimation()

	elseif isBlocking then
		humanoid.WalkSpeed =
			applyMovementCap(BLOCK_WALK_SPEED)
		stopSprintVisuals()

	elseif isAttacking then
		humanoid.WalkSpeed =
			applyMovementCap(ATTACK_MOVEMENT_BASE_SPEED)
		stopSprintVisuals()
		stopRunAnimation()

	elseif sprintActive then
		humanoid.WalkSpeed =
			applyMovementCap(SPRINT_SPEED)
		startSprintVisuals()

	else
		humanoid.WalkSpeed =
			applyMovementCap(WALK_SPEED)
		stopSprintVisuals()
	end

	if isSwimming() then
		stopRunAnimation()
		updateSwimAnimationSpeed(sprintActive)
		return
	end

	if isSurfaceWalking() then
		stopRunAnimation()
		return
	end

	local keepCarryRunLegsAirborne =
		shouldKeepCarryRunLegsAirborne(sprintActive)

	if sprintActive
		and (isGrounded or keepCarryRunLegsAirborne) then
		startRunAnimation()
	else
		stopRunAnimation()
	end
end

local function setupCharacter(newCharacter: Model)
	character = newCharacter
	humanoid =
		character:WaitForChild("Humanoid") :: Humanoid
	animator =
		humanoid:WaitForChild("Animator") :: Animator
	animate =
		character:WaitForChild("Animate")

	refreshSwimAnimationIds()

	local animation = Instance.new("Animation")
	animation.AnimationId = RUN_ANIMATION_ID
	runTrack = animator:LoadAnimation(animation)
	runTrack.Priority = Enum.AnimationPriority.Movement
	runTrack.Looped = true

	local leftRunAnimation = Instance.new("Animation")
	leftRunAnimation.AnimationId = LEFT_RUN_ANIMATION_ID
	leftRunTrack = animator:LoadAnimation(leftRunAnimation)
	leftRunTrack.Priority = Enum.AnimationPriority.Movement
	leftRunTrack.Looped = true

	local rightRunAnimation = Instance.new("Animation")
	rightRunAnimation.AnimationId = RIGHT_RUN_ANIMATION_ID
	rightRunTrack = animator:LoadAnimation(rightRunAnimation)
	rightRunTrack.Priority = Enum.AnimationPriority.Movement
	rightRunTrack.Looped = true

	activeRunTrack = nil
	sprinting = false
	sprintVisualsActive = false

	character:SetAttribute("IsSprinting", false)
	humanoid.WalkSpeed =
		applyMovementCap(WALK_SPEED)

	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = NORMAL_FOV
	end

	if stateConnection then
		stateConnection:Disconnect()
	end

	stateConnection =
		humanoid.StateChanged:Connect(function(_, newState)
			if isSurfaceWalking() then
				stopRunAnimation()
				return
			end

			if newState == Enum.HumanoidStateType.Swimming then
				stopRunAnimation()
				updateSprint()
				return
			end

			if newState == Enum.HumanoidStateType.Jumping
				or newState == Enum.HumanoidStateType.Freefall
				or newState == Enum.HumanoidStateType.Landed
				or newState == Enum.HumanoidStateType.Running then
				updateSprint()
			end
		end)

	if animationPlayedConnection then
		animationPlayedConnection:Disconnect()
	end

	animationPlayedConnection =
		animator.AnimationPlayed:Connect(function(track: AnimationTrack)
			if not isSwimTrack(track) or not isSwimming() then
				return
			end

			local sprintActive =
			not isDownedSystemLocked()
			and sprinting
			and isCharacterMoving()
			and character:GetAttribute("IsBlocking") ~= true
			and not isAnyMovementStunned()
			and character:GetAttribute("IsAttacking") ~= true
			and not isCombatBackwardMovement()
			and not isSprintMovementLocked()

			track:AdjustSpeed(
				sprintActive and SWIM_SPRINT_ANIMATION_SPEED or 1.0
			)
		end)

	disconnectAttributeConnections()

	for _, attributeName in ipairs({
		"Status_MovementBlocked",
		"Status_Stunned",
		"Status_MoveSpeedMultiplier",
		"IsStunned",
		"IsBlocking",
		"IsAttacking",
		"M1MovementSpeedCap",
		"SurfaceWalking",
		"SurfaceMoving",
		"CombatMode",
		"IsDashing",

		-- Generic movement restriction contract.
		"Movement_SprintLocked",
		"Movement_WalkSpeedCap",
		"Movement_RestrictionUntil",

		-- Legacy compatibility.
		"JutsuRunLocked",
		"JutsuRunLockWalkSpeed",
		"JutsuRunLockedUntil",
		}) do
		table.insert(
			attributeConnections,
			character:GetAttributeChangedSignal(attributeName):
				Connect(updateSprint)
		)
	end

	updateSprint()
end

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

UserInputService.InputBegan:Connect(function(
	input: InputObject,
	gameProcessed: boolean
)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		updateSprint()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		updateSprint()
	end
end)

RunService.RenderStepped:Connect(function()
	updateSprint()
end)

print(
	"[SprintController] READY v1.17 GenericMovementRestrictions"
		.. " | SharedGrounding=ON"
		.. " | CarryAirborneRunLegs=ON"
		.. " | M1MovementCap=ON"
		.. " | CombatBackwardSprint=OFF"
		.. " | DirectionalRun=Forward/Left/Right"
		.. " | StatusSlow=ON"
		.. " | StatusStun=ON"
		.. " | GenericSprintLock=ON"
		.. " | GenericWalkSpeedCap=ON"
)
