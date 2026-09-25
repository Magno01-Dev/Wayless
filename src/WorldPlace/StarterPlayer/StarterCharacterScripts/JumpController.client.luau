--!strict
-- JumpController v2.5 - StatusFX Direct + Heavy Jump Modifier
-- INSTALL: StarterPlayer > StarterCharacterScripts > JumpController [LocalScript]
--
-- StatusFX:
-- - Status Stun blocks normal jump, double jump, Water Walk jump and Wall/Surface jump.
-- - If Status Stun lands while rising, only positive Y impulse is cancelled.
-- - Slow does NOT change jump power.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
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

local actionSpendRequest =
	staminaRemotes:WaitForChild("ActionSpendRequest") :: RemoteFunction

local character = script.Parent
local humanoid =
	character:WaitForChild("Humanoid") :: Humanoid
local animator =
	humanoid:WaitForChild("Animator") :: Animator
local rootPart =
	character:WaitForChild("HumanoidRootPart") :: BasePart

local JUMP_POWER = 65
local DOUBLE_JUMP_POWER = 55
local DOUBLE_JUMP_MIN_DELAY = 0.08

local DOUBLE_JUMP_STAMINA_COST =
	StaminaConfig.Actions.DoubleJump.Cost

local WALL_JUMP_OUT_POWER = 55
local WALL_JUMP_MOVE_POWER = 20
local SURFACE_JUMP_RELEASE_TIME = 0.25
local WATER_JUMP_SWIM_GUARD_TIME = 0.22

local EXTRA_FALL_ACCELERATION = 60
local MAX_FALL_SPEED = 165

local DOUBLE_JUMP_ANIMATION_ID =
	"rbxassetid://113724435658718"
local DOUBLE_JUMP_ANIMATION_SPEED = 1.5

local hasJumpedFromGround = false
local canDoubleJump = false
local hasUsedDoubleJump = false
local firstJumpTime = -math.huge
local jumpCycle = 0
local surfaceJumpVersion = 0

if character:GetAttribute("WaterJumping") == nil then
	character:SetAttribute("WaterJumping", false)
end

local function getJumpMultiplier(): number
	return StatusCombatModifierReader
		.GetJumpMultiplier(
			character
		)
end

local function refreshHumanoidJumpPower()
	humanoid.UseJumpPower = true
	humanoid.JumpPower =
		JUMP_POWER
		* getJumpMultiplier()
end

refreshHumanoidJumpPower()

character:GetAttributeChangedSignal(
	"Status_JumpMultiplier"
):Connect(
	refreshHumanoidJumpPower
)

local doubleJumpAnimation = Instance.new("Animation")
doubleJumpAnimation.AnimationId = DOUBLE_JUMP_ANIMATION_ID

local doubleJumpTrack =
	animator:LoadAnimation(doubleJumpAnimation)

doubleJumpTrack.Priority =
	Enum.AnimationPriority.Movement
doubleJumpTrack.Looped = false

local function isDownedSystemLocked(): boolean
	-- IsCarrying intentionally remains allowed.
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
end

local function isStatusMovementBlocked(): boolean
	return character:GetAttribute("Status_MovementBlocked") == true
		or character:GetAttribute("Status_Stunned") == true
end

local function isAnyMovementStunned(): boolean
	return character:GetAttribute("IsStunned") == true
		or isStatusMovementBlocked()
end

local function isTreeJumpActive(): boolean
	return character:GetAttribute("TreeJumpActive") == true
		or character:GetAttribute("IsTreeJumping") == true
end

local function isSurfaceWalking(): boolean
	return character:GetAttribute("SurfaceWalking") == true
end

local function isWaterWalking(): boolean
	return character:GetAttribute("WaterWalking") == true
end

local function isSurfaceJumping(): boolean
	return character:GetAttribute("SurfaceJumping") == true
end

local function isGrounded(): boolean
	if isSurfaceJumping() or isSurfaceWalking() then
		return false
	end

	return GroundingService.IsSolidGrounded(
		character,
		humanoid,
		rootPart
	)
end

local function resetJumpState()
	jumpCycle += 1
	hasJumpedFromGround = false
	canDoubleJump = false
	hasUsedDoubleJump = false
	firstJumpTime = -math.huge
end

local function playDoubleJumpAnimation()
	if doubleJumpTrack.IsPlaying then
		doubleJumpTrack:Stop(0)
	end

	doubleJumpTrack:Play(0.05)
	doubleJumpTrack:AdjustSpeed(
		DOUBLE_JUMP_ANIMATION_SPEED
	)
end

local function armDoubleJump()
	if isAnyMovementStunned() then
		canDoubleJump = false
		return
	end

	if not hasJumpedFromGround
		or hasUsedDoubleJump
		or isTreeJumpActive()
		or isSurfaceWalking()
		or isGrounded() then
		return
	end

	canDoubleJump = true
end

local function registerGroundJump()
	jumpCycle += 1
	local thisJumpCycle = jumpCycle

	hasJumpedFromGround = true
	hasUsedDoubleJump = false
	canDoubleJump = false
	firstJumpTime = time()

	task.delay(DOUBLE_JUMP_MIN_DELAY, function()
		if thisJumpCycle ~= jumpCycle then
			return
		end
		armDoubleJump()
	end)
end

local function performWaterJump()
	if isAnyMovementStunned() then
		canDoubleJump = false
		return
	end

	if not isSurfaceWalking()
		or not isWaterWalking()
		or isTreeJumpActive() then
		return
	end

	registerGroundJump()

	surfaceJumpVersion += 1
	local thisSurfaceJump = surfaceJumpVersion

	-- v2.4.1 reliability: publish WaterJumping BEFORE SurfaceJumping so
	-- Surface/Dash see the explicit water-jump handoff on the same frame.
	character:SetAttribute("WaterJumping", true)
	character:SetAttribute("SurfaceJumping", true)

	local swimmingWasEnabled =
		humanoid:GetStateEnabled(
			Enum.HumanoidStateType.Swimming
		)

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Swimming,
		false
	)

	humanoid.Jump = false
	humanoid.AutoRotate = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	rootPart.AssemblyAngularVelocity = Vector3.zero

	local velocity = rootPart.AssemblyLinearVelocity
	local jumpMultiplier =
		getJumpMultiplier()

	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			velocity.X,
			JUMP_POWER
			* jumpMultiplier,
			velocity.Z
		)

	task.delay(WATER_JUMP_SWIM_GUARD_TIME, function()
		if humanoid.Parent then
			humanoid:SetStateEnabled(
				Enum.HumanoidStateType.Swimming,
				swimmingWasEnabled
			)
		end
	end)

	task.delay(SURFACE_JUMP_RELEASE_TIME, function()
		if thisSurfaceJump ~= surfaceJumpVersion then
			return
		end

		if character.Parent then
			character:SetAttribute(
				"SurfaceJumping",
				false
			)
			character:SetAttribute(
				"WaterJumping",
				false
			)
		end
	end)
end

local function performSurfaceJump()
	if isAnyMovementStunned() then
		canDoubleJump = false
		return
	end

	if not isSurfaceWalking()
		or isTreeJumpActive() then
		return
	end

	local surfaceNormal =
		character:GetAttribute("SurfaceNormal")

	if typeof(surfaceNormal) ~= "Vector3"
		or surfaceNormal.Magnitude < 0.5 then
		return
	end

	surfaceNormal = surfaceNormal.Unit

	local surfaceMoveDirection =
		character:GetAttribute("SurfaceMoveDirection")

	if typeof(surfaceMoveDirection) ~= "Vector3" then
		surfaceMoveDirection = Vector3.zero
	end

	if surfaceMoveDirection.Magnitude > 0.05 then
		surfaceMoveDirection =
			surfaceMoveDirection.Unit
	else
		surfaceMoveDirection = Vector3.zero
	end

	registerGroundJump()

	surfaceJumpVersion += 1
	local thisSurfaceJump = surfaceJumpVersion

	character:SetAttribute("SurfaceJumping", true)
	character:SetAttribute("WaterJumping", false)

	humanoid.Jump = false
	humanoid.AutoRotate = true
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	rootPart.AssemblyAngularVelocity = Vector3.zero

	local jumpMultiplier =
		getJumpMultiplier()

	rootPart.AssemblyLinearVelocity =
		surfaceNormal
		* WALL_JUMP_OUT_POWER
		* jumpMultiplier
		+ surfaceMoveDirection
		* WALL_JUMP_MOVE_POWER
		* jumpMultiplier

	task.delay(SURFACE_JUMP_RELEASE_TIME, function()
		if thisSurfaceJump ~= surfaceJumpVersion then
			return
		end

		if character.Parent then
			character:SetAttribute(
				"SurfaceJumping",
				false
			)
		end
	end)
end

local function spendDoubleJumpStamina(): boolean
	local ok, allowed, reason =
		pcall(function()
			return actionSpendRequest:
			InvokeServer("DoubleJump")
		end)

	if not ok then
		warn(
			"[JumpController] DoubleJump Stamina request failed:",
			allowed
		)
		return false
	end

	if allowed ~= true then
		if reason ~= "InsufficientStamina" then
			warn(
				"[JumpController] DoubleJump Stamina denied:",
				reason
			)
		end
		return false
	end

	return true
end

local function performDoubleJump()
	if isAnyMovementStunned() then
		canDoubleJump = false
		return
	end

	if character:GetAttribute("IsDashing") == true
		or not canDoubleJump
		or hasUsedDoubleJump
		or not hasJumpedFromGround
		or isTreeJumpActive()
		or isSurfaceWalking()
		or isGrounded()
		or time() - firstJumpTime < DOUBLE_JUMP_MIN_DELAY then
		return
	end

	if not spendDoubleJumpStamina() then
		return
	end

	canDoubleJump = false
	hasUsedDoubleJump = true

	if humanoid:GetState()
		== Enum.HumanoidStateType.Swimming then

		humanoid:ChangeState(
			Enum.HumanoidStateType.Freefall
		)
	end

	humanoid.Jump = false

	local velocity = rootPart.AssemblyLinearVelocity
	local jumpMultiplier =
		getJumpMultiplier()

	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			velocity.X,
			DOUBLE_JUMP_POWER
			* jumpMultiplier,
			velocity.Z
		)

	playDoubleJumpAnimation()
end

UserInputService.JumpRequest:Connect(function()
	if isDownedSystemLocked() then
		canDoubleJump = false
		return
	end

	if isAnyMovementStunned() then
		canDoubleJump = false
		humanoid.Jump = false
		return
	end

	if character:GetAttribute("IsDashing") == true
		or isTreeJumpActive() then
		return
	end

	if isSurfaceJumping() then
		performDoubleJump()
		return
	end

	if isSurfaceWalking() then
		if isWaterWalking() then
			performWaterJump()
		else
			performSurfaceJump()
		end
		return
	end

	if isGrounded() then
		registerGroundJump()
		return
	end

	performDoubleJump()
end)

humanoid.StateChanged:Connect(function(_, newState)
	if isTreeJumpActive() then
		canDoubleJump = false
		return
	end

	if isSurfaceJumping() then
		if newState == Enum.HumanoidStateType.Freefall
			and hasJumpedFromGround
			and not hasUsedDoubleJump
			and time() - firstJumpTime >= DOUBLE_JUMP_MIN_DELAY then
			canDoubleJump = true
		end
		return
	end

	if isSurfaceWalking() then
		return
	end

	if newState == Enum.HumanoidStateType.Jumping then
		if not hasJumpedFromGround
			and not hasUsedDoubleJump then
			registerGroundJump()
		end
		return
	end

	if newState == Enum.HumanoidStateType.Freefall then
		if hasJumpedFromGround
			and not hasUsedDoubleJump
			and time() - firstJumpTime >= DOUBLE_JUMP_MIN_DELAY
			and not isAnyMovementStunned() then
			canDoubleJump = true
		end

	elseif newState == Enum.HumanoidStateType.Landed then
		resetJumpState()

	elseif newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.RunningNoPhysics then

		if GroundingService.IsSolidGrounded(
			character,
			humanoid,
			rootPart
			) then
			resetJumpState()
		end
	end
end)

character:GetAttributeChangedSignal(
	"SurfaceWalking"
):Connect(function()
	if character:GetAttribute("SurfaceWalking") == true then
		resetJumpState()
	end
end)

character:GetAttributeChangedSignal(
	"TreeJumpActive"
):Connect(function()
	if character:GetAttribute("TreeJumpActive") == true then
		resetJumpState()
	end
end)

character:GetAttributeChangedSignal(
	"IsTreeJumping"
):Connect(function()
	if character:GetAttribute("IsTreeJumping") == true then
		resetJumpState()
	end
end)

local function cancelJumpFromStatusStun()
	if not isStatusMovementBlocked() then
		return
	end

	canDoubleJump = false
	humanoid.Jump = false

	if doubleJumpTrack.IsPlaying then
		doubleJumpTrack:Stop(0.05)
	end

	local velocity = rootPart.AssemblyLinearVelocity

	if velocity.Y > 0 then
		rootPart.AssemblyLinearVelocity =
			Vector3.new(
				velocity.X,
				0,
				velocity.Z
			)
	end
end

character:GetAttributeChangedSignal(
	"Status_MovementBlocked"
):Connect(cancelJumpFromStatusStun)

character:GetAttributeChangedSignal(
	"Status_Stunned"
):Connect(cancelJumpFromStatusStun)

RunService.Heartbeat:Connect(function(deltaTime)
	if isSurfaceWalking() or isTreeJumpActive() then
		return
	end

	local state = humanoid:GetState()

	if state ~= Enum.HumanoidStateType.Freefall then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	if velocity.Y >= 0 then
		return
	end

	local newY =
		math.max(
			velocity.Y - EXTRA_FALL_ACCELERATION * deltaTime,
			-MAX_FALL_SPEED
		)

	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			velocity.X,
			newY,
			velocity.Z
		)
end)

humanoid.Died:Connect(function()
	resetJumpState()
	surfaceJumpVersion += 1

	character:SetAttribute("SurfaceJumping", false)
	character:SetAttribute("WaterJumping", false)

	if doubleJumpTrack.IsPlaying then
		doubleJumpTrack:Stop(0)
	end
end)

for _, attributeName in ipairs({
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsExecuting",
	}) do
	character:GetAttributeChangedSignal(attributeName):Connect(function()
		if isDownedSystemLocked() then
			canDoubleJump = false
		end
	end)
end

print(
	"[JumpController] READY v2.5 StatusFXDirect+HeavyJump"
		.. " | SharedGrounding=ON"
		.. " | DoubleJumpStamina="
		.. tostring(DOUBLE_JUMP_STAMINA_COST)
		.. " | StatusStun=ON"
		.. " | SlowAffectsJump=OFF"
		.. " | StatusJumpMultiplier=ON"
)
