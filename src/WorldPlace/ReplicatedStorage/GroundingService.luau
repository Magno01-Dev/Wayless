--!strict
-- GroundingService v1
-- ReplicatedStorage > GroundingService
--
-- Shared physical-ground authority for local locomotion controllers.
--
-- Why:
-- Humanoid.FloorMaterial can remain Enum.Material.Air while an R6 character
-- is physically standing on solid ground. Sprint / Dash / Jump should not
-- depend on that property as the single source of truth.
--
-- This module:
-- - preserves Humanoid state semantics for real Jumping / Swimming / Dead
-- - accepts FloorMaterial when it is valid
-- - falls back to a short downward raycast when FloorMaterial is stale
-- - treats Terrain Water as NOT solid ground
-- - has a stricter fallback for Freefall so a real airborne character does
--   not regain ground actions simply because the floor is still close below
--
-- It does NOT:
-- - ChangeState()
-- - SetStateEnabled()
-- - alter velocity
-- - alter attributes
-- - alter animations

local GroundingService = {}

local DEFAULT_GROUND_RAY_DISTANCE = 4.25

-- Normal standing R6 root distance is around ~3 studs in this project.
-- We allow a little slope / collision tolerance.
local DEFAULT_SOLID_GROUND_MAX_DISTANCE = 3.75

-- Freefall is intentionally stricter than Running/FallingDown/etc.
local FREEFALL_GROUND_MAX_DISTANCE = 3.25
local FREEFALL_MAX_VERTICAL_SPEED = 6.0

local raycastParamsCache: {[Model]: RaycastParams} =
	setmetatable({}, {
		__mode = "k",
	})


local function getRaycastParams(
	character: Model
): RaycastParams

	local cached =
		raycastParamsCache[character]

	if cached then
		return cached
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}

	params.IgnoreWater = false
	params.RespectCanCollide = true

	raycastParamsCache[character] =
		params

	return params
end


local function isFloorMaterialSolid(
	material: Enum.Material
): boolean

	return material ~= Enum.Material.Air
		and material ~= Enum.Material.Water
end


local function raycastGround(
	character: Model,
	rootPart: BasePart,
	rayDistance: number?
): (boolean, number, Enum.Material?, RaycastResult?)

	local result =
		workspace:Raycast(
			rootPart.Position,
			Vector3.new(
				0,
				-(rayDistance or DEFAULT_GROUND_RAY_DISTANCE),
				0
			),
			getRaycastParams(character)
		)

	if not result then
		return false, math.huge, nil, nil
	end

	local distance =
		(
			rootPart.Position
			- result.Position
		).Magnitude

	-- Terrain Water is intentionally not ordinary solid ground.
	if result.Material ==
		Enum.Material.Water then

		return false,
			distance,
			result.Material,
			result
	end

	return true,
		distance,
		result.Material,
		result
end


function GroundingService.GetGroundInfo(
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart
)
	local state =
		humanoid:GetState()

	local floorMaterial =
		humanoid.FloorMaterial

	local raySolid,
		rayDistance,
		rayMaterial,
		rayResult =
		raycastGround(
			character,
			rootPart
		)

	return {
		state = state,
		floorMaterial = floorMaterial,

		floorMaterialSolid =
			isFloorMaterialSolid(
				floorMaterial
			),

		raySolid = raySolid,
		rayDistance = rayDistance,
		rayMaterial = rayMaterial,
		rayResult = rayResult,

		verticalSpeed =
			rootPart.AssemblyLinearVelocity.Y,
	}
end


function GroundingService.IsSolidGrounded(
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart
): boolean

	if not character.Parent
		or humanoid.Health <= 0
		or not rootPart.Parent then

		return false
	end

	local state =
		humanoid:GetState()

	-- These states are authoritative enough to always count as non-ground.
	if state ==
		Enum.HumanoidStateType.Dead
		or state ==
		Enum.HumanoidStateType.Swimming
		or state ==
		Enum.HumanoidStateType.Jumping
		or state ==
		Enum.HumanoidStateType.Seated
		or state ==
		Enum.HumanoidStateType.Climbing then

		return false
	end

	local floorMaterial =
		humanoid.FloorMaterial

	-- When FloorMaterial is correct, use it immediately.
	if isFloorMaterialSolid(
		floorMaterial
		) then

		-- A genuine Freefall state still needs physical confirmation.
		-- FloorMaterial can lag for a frame at takeoff.
		if state ~=
			Enum.HumanoidStateType.Freefall then

			return true
		end
	end

	local raySolid,
		rayDistance =
		raycastGround(
			character,
			rootPart
		)

	if not raySolid then
		return false
	end

	-- Freefall gets the strictest fallback.
	--
	-- This supports the stale-Freefall edge case while preserving actual air
	-- movement after a jump / ledge fall.
	if state ==
		Enum.HumanoidStateType.Freefall then

		return rayDistance <=
			FREEFALL_GROUND_MAX_DISTANCE
			and math.abs(
				rootPart.AssemblyLinearVelocity.Y
			) <=
			FREEFALL_MAX_VERTICAL_SPEED
	end

	-- Running / RunningNoPhysics / Landed / FallingDown / GettingUp and other
	-- non-air states may use the physical ray fallback. This is what fixes:
	--   Running + FloorMaterial Air + real concrete below
	--   FallingDown + FloorMaterial Air + real concrete below
	return rayDistance <=
		DEFAULT_SOLID_GROUND_MAX_DISTANCE
end


return GroundingService
