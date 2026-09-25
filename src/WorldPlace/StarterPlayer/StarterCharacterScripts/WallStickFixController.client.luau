--!strict
-- WallStickFixController v2.1 - Robust Wall Release / Lunge Safe
-- ElDiabloLocoStudios / Roblox
--
-- INSTALL:
-- StarterPlayer > StarterCharacterScripts > WallStickFixController [LocalScript]
--
-- Replaces v1 completely.
--
-- v2 changes:
-- - Does NOT use GroundingService for anti-stick detection.
-- - Does NOT exclude ChakraFeetActive forever.
-- - Uses a real vertical ground ray with floor-normal validation.
-- - Casts THROUGH the character toward the wall so contact is still detected
--   when HRP/Torso is already nearly touching the surface.
-- - While stuck, removes the input/velocity component pushing INTO the wall.
-- - Preserves tangent movement along the wall.
-- - Forces a controlled Freefall Y velocity.
-- - Gives Chakra Feet a short grace window for SurfaceController to claim wall
--   traversal before anti-stick takes over.

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")


local player =
	Players.LocalPlayer

local character =
	script.Parent :: Model

local humanoid =
	character:
	WaitForChild(
		"Humanoid"
	) :: Humanoid

local rootPart =
	character:
	WaitForChild(
		"HumanoidRootPart"
	) :: BasePart


-- =========================
-- TUNING
-- =========================

-- Ground check is straight down and requires an upward-facing normal.
local GROUND_RAY_DISTANCE =
	4.15

local MIN_GROUND_NORMAL_Y =
	0.55

-- Wall ray begins slightly BEHIND movement direction and crosses through the
-- character into the wall. This avoids the "ray starts already touching /
-- partially inside the wall" weakness of v1.
local WALL_RAY_BACK_OFFSET =
	1.45

local WALL_RAY_DISTANCE =
	4.75

local MAX_WALL_NORMAL_Y =
	0.32

local MIN_MOVE_DIRECTION =
	0.08

local MIN_INPUT_INTO_WALL_DOT =
	0.25

-- Let the genuine jump ascent finish. Anti-stick begins near apex/descent.
local MAX_ASCENDING_Y_FOR_FIX =
	3.0

local MIN_WALL_FALL_SPEED =
	11

local WALL_FALL_ACCELERATION =
	82

local MAX_WALL_FALL_SPEED =
	90

-- Tiny separation prevents contact solver/friction from immediately rebuilding
-- the exact wedged state. It is deliberately too small to feel like a bounce.
local WALL_RELEASE_OUTWARD_SPEED =
	2.5

-- If Chakra Feet is ON but SurfaceWalking has not been claimed yet, allow
-- SurfaceController a brief moment to attach intentionally.
local CHAKRA_FEET_SURFACE_GRACE =
	0.18


local WALL_RAY_Y_OFFSETS = {
	1.35,
	0.20,
	-1.10,
}


-- =========================
-- RAYCAST PARAMS
-- =========================

local raycastParams =
	RaycastParams.new()

raycastParams.FilterType =
	Enum.RaycastFilterType.Exclude

raycastParams.FilterDescendantsInstances = {
	character,
}

raycastParams.IgnoreWater =
	true


-- =========================
-- STATE
-- =========================

local wallStickActive =
	false

local wallContactStartedAt =
	-math.huge

local lastWallNormal: Vector3? =
	nil


-- =========================
-- ATTRIBUTES / OWNERSHIP
-- =========================

local function hardMovementOwnerActive(): boolean

	-- Actual surface ownership is intentional.
	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		return true
	end

	if character:GetAttribute(
		"WaterWalking"
		) == true then

		return true
	end

	if character:GetAttribute(
		"TreeJumpActive"
		) == true
			or character:GetAttribute(
				"IsTreeJumping"
			) == true then

		return true
	end

	if character:GetAttribute(
		"IsDashing"
		) == true
			or character:GetAttribute(
				"AirDashCarryActive"
			) == true then

		return true
	end

	-- Running Lunge v2 is a deliberate airborne attack with its own horizontal
	-- carry. Do not let anti-wall-stick rewrite that trajectory mid-flip.
	if character:GetAttribute(
		"IsLungeAttacking"
		) == true then

		return true
	end

	if character:GetAttribute(
		"IsDowned"
		) == true
			or character:GetAttribute(
				"DownedActionLocked"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true
			or character:GetAttribute(
				"IsExecuting"
			) == true then

		return true
	end

	if humanoid:GetState()
		== Enum.HumanoidStateType.Swimming then

		return true
	end

	return false
end


local function chakraFeetActive(): boolean

	return character:GetAttribute(
		"ChakraFeetActive"
	) == true
end


-- =========================
-- REAL FLOOR DETECTION
-- =========================

local function hasRealGroundBelow(): boolean

	local origins = {
		rootPart.Position,

		rootPart.Position
			+ rootPart.CFrame.RightVector
			* 0.55,

		rootPart.Position
		- rootPart.CFrame.RightVector
			* 0.55,
	}

	for _,
		origin in ipairs(
			origins
		) do

		local result =
			workspace:
			Raycast(
				origin,
				Vector3.new(
					0,
					-GROUND_RAY_DISTANCE,
					0
				),
				raycastParams
			)

		if result
			and result.Normal.Y >=
			MIN_GROUND_NORMAL_Y then

			return true
		end
	end

	return false
end


-- =========================
-- WALL DETECTION
-- =========================

local function getHorizontalMoveDirection(): Vector3?

	local move =
		humanoid.MoveDirection

	local horizontal =
		Vector3.new(
			move.X,
			0,
			move.Z
		)

	if horizontal.Magnitude <
		MIN_MOVE_DIRECTION then

		return nil
	end

	return horizontal.Unit
end


local function findWall(
	moveDirection: Vector3
): RaycastResult?

	for _,
		yOffset in ipairs(
			WALL_RAY_Y_OFFSETS
		) do

		local origin =
			rootPart.Position
		- moveDirection
			* WALL_RAY_BACK_OFFSET
			+ Vector3.new(
				0,
				yOffset,
				0
			)

		local result =
			workspace:
			Raycast(
				origin,
				moveDirection
				* WALL_RAY_DISTANCE,
				raycastParams
			)

		if result then

			local normal =
				result.Normal

			if math.abs(
				normal.Y
				) <= MAX_WALL_NORMAL_Y then

				local flatNormal =
					Vector3.new(
						normal.X,
						0,
						normal.Z
					)

				if flatNormal.Magnitude >
					0.05 then

					local intoWall =
						moveDirection:
						Dot(
							-flatNormal.Unit
						)

					if intoWall >=
						MIN_INPUT_INTO_WALL_DOT then

						return result
					end
				end
			end
		end
	end

	return nil
end


-- =========================
-- ACTIVE STATE
-- =========================

local function setActive(
	active: boolean
)

	if wallStickActive ==
		active then

		return
	end

	wallStickActive =
		active

	character:SetAttribute(
		"WallStickFixActive",
		active
	)
end


local function resetWallContact()

	wallContactStartedAt =
		-math.huge

	lastWallNormal =
		nil

	setActive(
		false
	)
end


-- =========================
-- FIX
-- =========================

local function applyWallRelease(
	wallNormal: Vector3,
	dt: number
)

	local flatNormal =
		Vector3.new(
			wallNormal.X,
			0,
			wallNormal.Z
		)

	if flatNormal.Magnitude <=
		0.05 then

		return
	end

	flatNormal =
		flatNormal.Unit


	-- =========================
	-- INPUT RELEASE
	-- =========================
	--
	-- PlayerModule will keep producing W every frame.
	-- Remove only the INTO-WALL component before physics.
	-- Tangential strafe along the wall remains possible.

	local requestedMove =
		humanoid.MoveDirection

	local requestedHorizontal =
		Vector3.new(
			requestedMove.X,
			0,
			requestedMove.Z
		)

	if requestedHorizontal.Magnitude >
		0.001 then

		local normalComponent =
			requestedHorizontal:
			Dot(
				flatNormal
			)

		-- Negative means pushing INTO the wall because wall normal points out.
		if normalComponent < 0 then

			requestedHorizontal =
				requestedHorizontal
			- flatNormal
				* normalComponent
		end

		humanoid:
			Move(
				requestedHorizontal,
				false
			)
	end


	-- =========================
	-- VELOCITY RELEASE
	-- =========================

	local velocity =
		rootPart.AssemblyLinearVelocity

	local horizontalVelocity =
		Vector3.new(
			velocity.X,
			0,
			velocity.Z
		)

	local velocityNormalComponent =
		horizontalVelocity:
		Dot(
			flatNormal
		)

	if velocityNormalComponent < 0 then

		horizontalVelocity =
			horizontalVelocity
		- flatNormal
			* velocityNormalComponent
	end

	-- Barely separate from contact so friction/contact solver cannot keep the
	-- exact wedged state alive.
	horizontalVelocity +=
		flatNormal
		* WALL_RELEASE_OUTWARD_SPEED


	-- =========================
	-- FREEFALL
	-- =========================

	local state =
		humanoid:GetState()

	if state ~=
		Enum.HumanoidStateType.Freefall
		and state ~=
		Enum.HumanoidStateType.FallingDown then

		humanoid:
			ChangeState(
				Enum.HumanoidStateType.Freefall
			)
	end


	local nextY =
		velocity.Y
	- WALL_FALL_ACCELERATION
		* math.min(
			dt,
			0.05
		)

	nextY =
		math.min(
			nextY,
			-MIN_WALL_FALL_SPEED
		)

	nextY =
		math.max(
			nextY,
			-MAX_WALL_FALL_SPEED
		)


	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			horizontalVelocity.X,
			nextY,
			horizontalVelocity.Z
		)
end


-- =========================
-- PRE-PHYSICS LOOP
-- =========================
--
-- PreSimulation is deliberate:
-- PlayerModule has already produced requested locomotion for this frame,
-- and we strip the wall-normal component before physics/contact resolution.

RunService.PreSimulation:
	Connect(
		function(
			dt: number
		)

			if humanoid.Health <= 0
				or not character.Parent then

				resetWallContact()
				return
			end

			if hardMovementOwnerActive() then

				resetWallContact()
				return
			end

			if hasRealGroundBelow() then

				resetWallContact()
				return
			end


			local moveDirection =
			getHorizontalMoveDirection()

			if not moveDirection then

				resetWallContact()
				return
			end


			local wall =
			findWall(
				moveDirection
			)

			if not wall then

				resetWallContact()
				return
			end


			local currentFlatNormal =
			Vector3.new(
				wall.Normal.X,
				0,
				wall.Normal.Z
			)

			if currentFlatNormal.Magnitude <=
				0.05 then

				resetWallContact()
				return
			end

			currentFlatNormal =
			currentFlatNormal.Unit


			if not lastWallNormal
				or lastWallNormal:
				Dot(
					currentFlatNormal
				) < 0.90 then

				wallContactStartedAt =
				time()
			end

			lastWallNormal =
			currentFlatNormal


			local velocity =
			rootPart.AssemblyLinearVelocity

			-- Genuine upward jump still gets its ascent.
			if velocity.Y >
				MAX_ASCENDING_Y_FOR_FIX then

				setActive(
					false
				)

				return
			end


			-- If Chakra Feet is toggled, SurfaceController gets one short chance
			-- to claim this wall. If it does, hardMovementOwnerActive() exits
			-- this controller next frame. If it does not, anti-stick still works.
			if chakraFeetActive()
				and time()
				- wallContactStartedAt
				< CHAKRA_FEET_SURFACE_GRACE then

				setActive(
					false
				)

				return
			end


			setActive(
				true
			)

			applyWallRelease(
				wall.Normal,
				dt
			)
		end
	)


character:SetAttribute(
	"WallStickFixActive",
	false
)


print(
	"[WallStickFixController] READY v2.1 LungeSafe"
		.. " | RealGroundRay=ON"
		.. " | IntoWallInputStrip=ON"
		.. " | ChakraFeetGrace="
		.. tostring(
			CHAKRA_FEET_SURFACE_GRACE
		)
)
