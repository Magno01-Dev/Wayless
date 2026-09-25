--!strict
-- SwimController v1.3.1 - Custom Swim Propulsion + Surface Exit
-- StarterPlayer > StarterCharacterScripts > SwimController [LocalScript]
--
-- ARCHITECTURE
-- Roblox keeps:
--   - Humanoid Swimming state
--   - water detection / swimming state transitions
--   - native swimming body posture / automatic tilt
--
-- This controller owns while REAL Swimming:
--   - propulsion velocity
--   - acceleration / deceleration
--   - camera-pitch depth movement
--   - directional swim input
--
-- CustomAnimations owns Swim / SwimIdle visuals.
-- SurfaceController owns Water Walk / Chakra Feet.
--
-- No custom body orientation is applied here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = script.Parent

local humanoid =
	character:WaitForChild("Humanoid") :: Humanoid

local rootPart =
	character:WaitForChild("HumanoidRootPart") :: BasePart


-- ============================================================
-- TUNING
-- ============================================================

-- Overall movement.
local FORWARD_SPEED = 15
local BACKWARD_SPEED = 10
local STRAFE_SPEED = 11

-- Vertical movement produced by looking up/down while holding W/S.
-- 1.0 would follow the camera pitch fully.
-- Lower values keep the swimmer flatter and more controllable.
local CAMERA_PITCH_STRENGTH = 0.72

-- Prevents W + extreme camera pitch from becoming a purely vertical rocket.
local MAX_CAMERA_VERTICAL_COMPONENT = 0.72

-- Space gives an explicit upward swim contribution.
local SPACE_ASCEND_SPEED = 10

-- Custom movement feel.
-- Higher acceleration = snappier response.
local ACCELERATION_RESPONSIVENESS = 5.75
local DECELERATION_RESPONSIVENESS = 4.25

-- Maximum speeds after all inputs are combined.
local MAX_HORIZONTAL_SPEED = 15
local MAX_ASCEND_SPEED = 10
local MAX_DESCEND_SPEED = 11

-- Simple surface exit.
local SWIM_EXIT_UPWARD_SPEED = 22
local SWIM_EXIT_SURFACE_SEARCH_HEIGHT = 5
local SWIM_EXIT_SURFACE_SEARCH_DEPTH = 10
local SWIM_EXIT_MAX_ROOT_BELOW_SURFACE = 3.5
local SWIM_EXIT_GRACE = 0.28

-- LinearVelocity authority.
local FORCE_PER_MASS = 7500

-- Roblox native propulsion is nearly disabled while Swimming,
-- but Humanoid:Move is still fed input so Roblox can keep its native
-- swimming posture / body tilt.
local NATIVE_SWIM_WALKSPEED = 0.01

local INPUT_EPSILON = 0.01
local VELOCITY_STOP_EPSILON = 0.035

local RENDER_STEP_NAME =
	"DiabloStudios_SwimController_"
	.. tostring(player.UserId)


-- ============================================================
-- EARLY STATE
-- ============================================================

-- IMPORTANT:
-- This must be declared BEFORE isRealSwimming(),
-- because isRealSwimming() reads it.
local swimExitGraceUntil =
	-math.huge


-- ============================================================
-- STATE HELPERS
-- ============================================================

local function isSurfaceWalking(): boolean
	return character:GetAttribute(
		"SurfaceWalking"
	) == true
end

local function isWaterWalking(): boolean
	return character:GetAttribute(
		"WaterWalking"
	) == true
end

local function isWaterJumping(): boolean
	return character:GetAttribute(
		"WaterJumping"
	) == true
end

local function isSurfaceJumping(): boolean
	return character:GetAttribute(
		"SurfaceJumping"
	) == true
end

local function isRealSwimming(): boolean
	if humanoid.Health <= 0 then
		return false
	end

	if time() < swimExitGraceUntil then
		return false
	end

	if humanoid:GetState()
		~= Enum.HumanoidStateType.Swimming then

		return false
	end

	if isSurfaceWalking()
		or isWaterWalking()
		or isWaterJumping()
		or isSurfaceJumping() then

		return false
	end

	return true
end


-- ============================================================
-- CLEAN OLD v1.0 ORIENTATION OBJECTS
-- ============================================================

local obsoleteAttachment =
	rootPart:FindFirstChild(
		"SwimControlAttachment"
	)

if obsoleteAttachment then
	obsoleteAttachment:Destroy()
end

local obsoleteAlign =
	rootPart:FindFirstChild(
		"SwimControlAlignOrientation"
	)

if obsoleteAlign then
	obsoleteAlign:Destroy()
end


-- ============================================================
-- WATER SURFACE EXIT
-- ============================================================

local swimExitRaycastParams =
	RaycastParams.new()

swimExitRaycastParams.FilterType =
	Enum.RaycastFilterType.Include

swimExitRaycastParams.FilterDescendantsInstances = {
	workspace.Terrain,
}

swimExitRaycastParams.IgnoreWater =
	false


local function findNearbyWaterSurface(): RaycastResult?
	local origin =
		rootPart.Position
		+ Vector3.yAxis
		* SWIM_EXIT_SURFACE_SEARCH_HEIGHT

	local direction =
		-Vector3.yAxis
		* (
			SWIM_EXIT_SURFACE_SEARCH_HEIGHT
			+ SWIM_EXIT_SURFACE_SEARCH_DEPTH
		)

	local hit =
		workspace:Raycast(
			origin,
			direction,
			swimExitRaycastParams
		)

	if not hit
		or hit.Material ~= Enum.Material.Water then

		return nil
	end

	return hit
end


local function isNearWaterSurface(): boolean
	local hit =
		findNearbyWaterSurface()

	if not hit then
		return false
	end

	local rootBelowSurface =
		hit.Position.Y
	- rootPart.Position.Y

	-- Must actually be at/below the surface, not several studs above it.
	return rootBelowSurface >= -0.75
		and rootBelowSurface
		<= SWIM_EXIT_MAX_ROOT_BELOW_SURFACE
end


-- ============================================================
-- CUSTOM PROPULSION
-- ============================================================

local oldPropulsion =
	rootPart:FindFirstChild(
		"SwimPropulsionVelocity"
	)

if oldPropulsion then
	oldPropulsion:Destroy()
end

local oldPropulsionAttachment =
	rootPart:FindFirstChild(
		"SwimPropulsionAttachment"
	)

if oldPropulsionAttachment then
	oldPropulsionAttachment:Destroy()
end


local propulsionAttachment =
	Instance.new("Attachment")

propulsionAttachment.Name =
	"SwimPropulsionAttachment"

propulsionAttachment.Parent =
	rootPart


local propulsion =
	Instance.new("LinearVelocity")

propulsion.Name =
	"SwimPropulsionVelocity"

propulsion.Attachment0 =
	propulsionAttachment

propulsion.RelativeTo =
	Enum.ActuatorRelativeTo.World

propulsion.VelocityConstraintMode =
	Enum.VelocityConstraintMode.Vector

propulsion.VectorVelocity =
	Vector3.zero

propulsion.MaxForce =
	math.max(
		1,
		rootPart.AssemblyMass
		* FORCE_PER_MASS
	)

propulsion.Enabled =
	false

propulsion.Parent =
	rootPart


-- ============================================================
-- CONTROLLER STATE
-- ============================================================

local customSwimming =
	false

local savedWalkSpeed: number? =
	nil

local currentVelocity =
	Vector3.zero


local function restoreNativeWalkSpeed()
	if savedWalkSpeed == nil then
		return
	end

	-- If another owner (SurfaceController, combat, etc.) has already
	-- changed WalkSpeed during the handoff, do not overwrite it.
	if math.abs(
		humanoid.WalkSpeed
		- NATIVE_SWIM_WALKSPEED
		) <= 0.05 then

		humanoid.WalkSpeed =
			savedWalkSpeed
	end

	savedWalkSpeed =
		nil
end


local function setCustomSwimming(
	active: boolean
)
	if customSwimming == active then
		return
	end

	customSwimming =
		active

	character:SetAttribute(
		"CustomSwimMovementActive",
		active
	)

	if active then
		savedWalkSpeed =
			humanoid.WalkSpeed

		humanoid.WalkSpeed =
			NATIVE_SWIM_WALKSPEED

		-- Enter smoothly from the velocity the player already had.
		local initialVelocity =
			rootPart.AssemblyLinearVelocity

		currentVelocity =
			Vector3.new(
				math.clamp(
					initialVelocity.X,
					-MAX_HORIZONTAL_SPEED,
					MAX_HORIZONTAL_SPEED
				),
				math.clamp(
					initialVelocity.Y,
					-MAX_DESCEND_SPEED,
					MAX_ASCEND_SPEED
				),
				math.clamp(
					initialVelocity.Z,
					-MAX_HORIZONTAL_SPEED,
					MAX_HORIZONTAL_SPEED
				)
			)

		propulsion.MaxForce =
			math.max(
				1,
				rootPart.AssemblyMass
				* FORCE_PER_MASS
			)

		propulsion.VectorVelocity =
			currentVelocity

		propulsion.Enabled =
			true

		print(
			"[SwimController] ENTER Custom Swimming",
			"| NativeBodyTilt=ON",
			"| CustomPropulsion=ON"
		)
	else
		propulsion.Enabled =
			false

		propulsion.VectorVelocity =
			Vector3.zero

		currentVelocity =
			Vector3.zero

		restoreNativeWalkSpeed()

		print(
			"[SwimController] EXIT Custom Swimming"
		)
	end
end


-- ============================================================
-- INPUT
-- ============================================================

local function getInput(): (
	number,
	number,
	boolean
	)
	if UserInputService:GetFocusedTextBox() then
		return 0, 0, false
	end

	local forwardAxis = 0
	local rightAxis = 0

	if UserInputService:IsKeyDown(
		Enum.KeyCode.W
		) then

		forwardAxis += 1
	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.S
		) then

		forwardAxis -= 1
	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.D
		) then

		rightAxis += 1
	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.A
		) then

		rightAxis -= 1
	end

	local ascend =
		UserInputService:IsKeyDown(
			Enum.KeyCode.Space
		)

	return
		forwardAxis,
		rightAxis,
		ascend
end


-- ============================================================
-- CAMERA-RELATIVE DIRECTIONS
-- ============================================================

local function getFlatUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3
	local flat =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if flat.Magnitude <= 0.001 then
		return fallback
	end

	return flat.Unit
end


local function getTargetVelocity(): (
	Vector3,
	Vector3
	)
	local camera =
		workspace.CurrentCamera

	if not camera then
		return Vector3.zero, Vector3.zero
	end

	local forwardAxis,
		rightAxis,
		ascend =
		getInput()

	if forwardAxis == 0
		and rightAxis == 0
		and not ascend then

		return Vector3.zero, Vector3.zero
	end


	local cameraLook =
		camera.CFrame.LookVector

	local flatForward =
		getFlatUnit(
			cameraLook,
			rootPart.CFrame.LookVector
		)

	local flatRight =
		getFlatUnit(
			camera.CFrame.RightVector,
			rootPart.CFrame.RightVector
		)


	-- Camera pitch affects depth, but is intentionally damped.
	local verticalFromCamera =
		math.clamp(
			cameraLook.Y
			* CAMERA_PITCH_STRENGTH,
			-MAX_CAMERA_VERTICAL_COMPONENT,
			MAX_CAMERA_VERTICAL_COMPONENT
		)

	local pitchedForward =
		flatForward
		+ Vector3.yAxis
		* verticalFromCamera

	if pitchedForward.Magnitude > 0.001 then
		pitchedForward =
			pitchedForward.Unit
	end


	local target =
		Vector3.zero

	-- Forward/back have different speed profiles.
	if forwardAxis > 0 then
		target +=
			pitchedForward
			* FORWARD_SPEED
	elseif forwardAxis < 0 then
		target -=
			pitchedForward
			* BACKWARD_SPEED
	end

	if rightAxis ~= 0 then
		target +=
			flatRight
			* rightAxis
			* STRAFE_SPEED
	end

	if ascend then
		target +=
			Vector3.yAxis
			* SPACE_ASCEND_SPEED
	end


	-- Clamp horizontal speed independently.
	local horizontal =
		Vector3.new(
			target.X,
			0,
			target.Z
		)

	if horizontal.Magnitude
		> MAX_HORIZONTAL_SPEED then

		horizontal =
			horizontal.Unit
			* MAX_HORIZONTAL_SPEED
	end

	local vertical =
		math.clamp(
			target.Y,
			-MAX_DESCEND_SPEED,
			MAX_ASCEND_SPEED
		)

	target =
		Vector3.new(
			horizontal.X,
			vertical,
			horizontal.Z
		)


	-- This vector is only sent to Humanoid:Move so Roblox keeps
	-- its native Swimming body posture / tilt.
	local visualMoveDirection =
		target

	if visualMoveDirection.Magnitude > 1 then
		visualMoveDirection =
			visualMoveDirection.Unit
	end

	return
		target,
		visualMoveDirection
end


-- ============================================================
-- UPDATE
-- ============================================================

local function updateSwimming(
	deltaTime: number
)
	local realSwimming =
		isRealSwimming()

	setCustomSwimming(
		realSwimming
	)

	if not realSwimming then
		return
	end


	local targetVelocity,
		visualMoveDirection =
		getTargetVelocity()


	-- Keep feeding Roblox the intended movement vector even though its
	-- propulsion has effectively been removed. This preserves the native
	-- Swimming posture/automatic tilt behavior.
	humanoid:Move(
		visualMoveDirection,
		false
	)


	local hasInput =
		targetVelocity.Magnitude
		> INPUT_EPSILON

	local responsiveness =
		if hasInput
		then ACCELERATION_RESPONSIVENESS
		else DECELERATION_RESPONSIVENESS

	local alpha =
		1 - math.exp(
			-responsiveness
			* deltaTime
		)

	currentVelocity =
		currentVelocity:Lerp(
			targetVelocity,
			alpha
		)

	if not hasInput
		and currentVelocity.Magnitude
		< VELOCITY_STOP_EPSILON then

		currentVelocity =
			Vector3.zero
	end


	propulsion.VectorVelocity =
		currentVelocity
end


-- ============================================================
-- SIMPLE SURFACE EXIT
-- ============================================================

local function trySurfaceExit()
	if not customSwimming
		or not isRealSwimming() then

		return
	end

	-- Chakra Feet already has its own correct Swimming -> Water Walk
	-- handoff inside SurfaceController.
	if character:GetAttribute(
		"ChakraFeetActive"
		) == true then

		return
	end

	if not isNearWaterSurface() then
		return
	end

	swimExitGraceUntil =
		time() + SWIM_EXIT_GRACE

	-- Release custom propulsion before applying exit velocity.
	setCustomSwimming(false)

	local existingVelocity =
		rootPart.AssemblyLinearVelocity

	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			existingVelocity.X,
			math.max(
				existingVelocity.Y,
				SWIM_EXIT_UPWARD_SPEED
			),
			existingVelocity.Z
		)

	humanoid:ChangeState(
		Enum.HumanoidStateType.Jumping
	)

	print(
		"[SwimController] SURFACE EXIT",
		"| UpSpeed",
		SWIM_EXIT_UPWARD_SPEED
	)
end


UserInputService.InputBegan:Connect(
	function(
		input: InputObject,
		gameProcessed: boolean
	)
		if gameProcessed then
			return
		end

		if input.KeyCode
			~= Enum.KeyCode.Space then

			return
		end

		trySurfaceExit()
	end
)


-- ============================================================
-- HANDOFFS
-- ============================================================

local function refreshOwnership()
	if not isRealSwimming() then
		setCustomSwimming(false)
	end
end


humanoid.StateChanged:Connect(
	function(
		_oldState,
		_newState
	)
		refreshOwnership()
	end
)

character:GetAttributeChangedSignal(
	"SurfaceWalking"
):Connect(refreshOwnership)

character:GetAttributeChangedSignal(
	"WaterWalking"
):Connect(refreshOwnership)

character:GetAttributeChangedSignal(
	"WaterJumping"
):Connect(refreshOwnership)

character:GetAttributeChangedSignal(
	"SurfaceJumping"
):Connect(refreshOwnership)


-- ============================================================
-- RENDER STEP
-- ============================================================

RunService:UnbindFromRenderStep(
	RENDER_STEP_NAME
)

RunService:BindToRenderStep(
	RENDER_STEP_NAME,
	Enum.RenderPriority.Character.Value - 1,
	updateSwimming
)


-- ============================================================
-- CLEANUP
-- ============================================================

local cleaned =
	false

local function cleanup()
	if cleaned then
		return
	end

	cleaned =
		true

	RunService:UnbindFromRenderStep(
		RENDER_STEP_NAME
	)

	setCustomSwimming(false)

	character:SetAttribute(
		"CustomSwimMovementActive",
		false
	)

	if propulsion.Parent then
		propulsion:Destroy()
	end

	if propulsionAttachment.Parent then
		propulsionAttachment:Destroy()
	end
end


character.AncestryChanged:Connect(
	function(
		_child,
		parent
	)
		if parent == nil then
			cleanup()
		end
	end
)


character:SetAttribute(
	"CustomSwimMovementActive",
	false
)


print(
	"[SwimController] READY v1.3.1"
		.. " | NativeSwimmingState=ON"
		.. " | NativeBodyTilt=ON"
		.. " | NativePropulsion=OFF"
		.. " | CustomPropulsion=ON"
		.. " | Acceleration="
		.. tostring(ACCELERATION_RESPONSIVENESS)
		.. " | Deceleration="
		.. tostring(DECELERATION_RESPONSIVENESS)
		.. " | ForwardSpeed="
		.. tostring(FORWARD_SPEED)
		.. " | CameraPitchDepth=ON"
		.. " | WaterWalkPriority=ON"
		.. " | SurfaceExit=ON"
		.. " | ChakraFeetSurfaceHandoff=SurfaceController"
		.. " | UnderwaterCombatExtensions=OFF"
		.. " | FastSwim=OFF"
		.. " | Animations=CustomAnimations"
)