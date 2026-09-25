--!strict
-- ProjectileLaunchArcController v3 - Light Hand-Throw Arcs (Assist-Compatible)
-- StarterPlayer > StarterCharacterScripts > ProjectileLaunchArcController
--
-- Replaces v1 StaticTargetArcs.
--
-- DESIGN RULE
-- ===========
-- The AIM decides where a projectile should go.
-- The ARC only gives visual identity AFTER a valid guidance target is likely.
--
-- Therefore:
--
-- VALID GUIDANCE TARGET
-- -> apply a SMALL launch bias
-- -> ProjectileServer's light guidance bends back into the target
--
-- v3 CHANGE
-- =========
-- ProjectileServer v3.0 replaced heavy mid-flight homing with strong aim
-- assist + light guidance + terminal commit. A v2-sized launch bias
-- (11.5 deg for Kunai, 14 deg for Fuma) was tuned for homing that no longer
-- exists, so it now costs real accuracy instead of buying visual identity.
--
-- The arcs below are roughly a third of the v2 values: still a readable
-- hand-thrown curve, small enough that the server's assist cone absorbs it.
--
-- The arc is also now gated by the NEW Guidance.AimAssistConeDegrees when
-- present, so the visual never triggers outside the cone the server actually
-- uses to pick a target.
--
-- NO GUIDANCE TARGET
-- -> return the ORIGINAL CombatAim direction exactly
-- -> free-aim throws land where the reticle is pointing
--
-- This fixes v1 behavior where a throw at a wall / empty space could begin
-- 10-15 degrees away from the reticle with no target available to guide it back.
--
-- IMPORTANT
-- =========
-- This script does NOT:
-- - select damage targets for the server
-- - spawn projectiles
-- - decide hits
-- - alter DefensiveIntercept
--
-- It only predicts whether the CURRENT offensive throw is safely inside the
-- same target-acquisition family used by ProjectileServer. The server remains
-- authoritative and may still accept/reject/acquire independently.
--
-- To avoid the visual layer creating a false-positive arc near the extreme
-- edge of the server's cone, the local arc trigger uses a SAFETY MARGIN inside
-- config.Guidance.AcquireConeDegrees.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local CollectionService =
	game:GetService("CollectionService")

local player =
	Players.LocalPlayer

local character =
	script.Parent


local ProjectileConfigs =
	require(
		ReplicatedStorage:
		WaitForChild("ProjectileConfigs")
	)


local CombatAim: any =
	require(
		ReplicatedStorage:
		WaitForChild("CombatAim")
	)


local PROJECTILE_TARGET_TAG =
	"ProjectileTarget"


-- Keep local visual detection safely inside the server cone.
-- This prevents a projectile from receiving a large launch arc when the
-- target is so close to the cone edge that the biased direction could make
-- server acquisition ambiguous.
local ARC_TRIGGER_CONE_MARGIN_DEGREES =
	3


type ArcProfile = {
	YawDegrees: number,
	PitchDegrees: number,
	MinDistance: number,
	FullDistance: number,
	AlternateSide: boolean,
}


local PROFILES: {[string]: ArcProfile} = {
	-- MinDistance is raised so close-range throws leave the hand exactly on
	-- the reticle: at point blank the projectile commits almost immediately
	-- and there is no guidance left to undo a launch bias.
	Kunai = {
		YawDegrees = 4.0,
		PitchDegrees = 1.5,
		MinDistance = 14,
		FullDistance = 42,
		AlternateSide = true,
	},

	Shuriken = {
		YawDegrees = 2.0,
		PitchDegrees = 2.5,
		MinDistance = 14,
		FullDistance = 40,
		AlternateSide = true,
	},

	-- Senbon is Direct Precision: essentially no arc.
	Senbon = {
		YawDegrees = 0.6,
		PitchDegrees = 0.8,
		MinDistance = 16,
		FullDistance = 36,
		AlternateSide = true,
	},

	Fuma = {
		YawDegrees = 5.0,
		PitchDegrees = 2.0,
		MinDistance = 16,
		FullDistance = 48,
		AlternateSide = true,
	},
}


type ArcRuntimeState = {
	Character: Model?,
	LastArcAssignedAt: number,
	ArcSide: number,
	LastProjectileType: string?,
}


local runtimeState: ArcRuntimeState


local existingState =
	CombatAim._DiabloProjectileLaunchArcState


if typeof(existingState) == "table" then

	runtimeState =
		existingState

else

	runtimeState = {
		Character = nil,
		LastArcAssignedAt = -math.huge,
		ArcSide = 1,
		LastProjectileType = nil,
	}

	CombatAim._DiabloProjectileLaunchArcState =
		runtimeState
end


runtimeState.Character =
	character


local function getSelectedProjectileType(): string?

	local activeCharacter =
		runtimeState.Character

	if not activeCharacter
		or not activeCharacter.Parent then

		return nil
	end


	if activeCharacter:GetAttribute(
		"IsThrowingProjectile"
		) ~= true then

		return nil
	end


	-- Offensive throws only.
	if activeCharacter:GetAttribute(
		"CombatMode"
		) ~= true then

		return nil
	end


	local slotValue =
		player:GetAttribute(
			"NinjaBagSelectedSlot"
		)


	if typeof(slotValue) ~= "number" then
		return nil
	end


	local slotIndex =
		math.floor(
			slotValue
		)


	if slotIndex < 1
		or slotIndex > 4 then

		return nil
	end


	local projectileType =
		player:GetAttribute(
			"NinjaBagSlot"
			.. tostring(slotIndex)
			.. "Projectile"
		)


	if typeof(projectileType) ~= "string"
		or PROFILES[
		projectileType
		] == nil then

		return nil
	end


	return projectileType
end


local function findTargetModelFromInstance(
	instance: Instance?
): Model?

	local current =
		instance


	while current
		and current ~= workspace do

		if current:IsA("Model") then

			local humanoid =
				current:
				FindFirstChildOfClass(
					"Humanoid"
				)


			local root =
				current:
				FindFirstChild(
					"HumanoidRootPart"
				)


			if humanoid
				and root
				and root:IsA(
					"BasePart"
				) then

				return current
			end
		end


		current =
			current.Parent
	end


	return nil
end


local function hasLineOfSight(
	origin: Vector3,
	targetCharacter: Model,
	targetPosition: Vector3
): boolean

	local delta =
		targetPosition
	- origin


	if delta.Magnitude <= 0.05 then
		return true
	end


	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	params.FilterDescendantsInstances =
		{
			character,
		}


	params.IgnoreWater =
		false


	local result =
		workspace:
		Raycast(
			origin,
			delta,
			params
		)


	if not result then
		return true
	end


	return result.Instance:
		IsDescendantOf(
			targetCharacter
		)
end


local function considerTarget(
	targetCharacter: Model,
	origin: Vector3,
	aimDirection: Vector3,
	maxRange: number,
	coneDot: number,
	bestScore: number
): (boolean, number)

	if targetCharacter ==
		character then

		return false,
			bestScore
	end


	local humanoid =
		targetCharacter:
		FindFirstChildOfClass(
			"Humanoid"
		)


	local root =
		targetCharacter:
		FindFirstChild(
			"HumanoidRootPart"
		)


	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA(
			"BasePart"
		) then

		return false,
			bestScore
	end


	if targetCharacter:GetAttribute(
		"IsDowned"
		) == true then

		return false,
			bestScore
	end


	local delta =
		root.Position
	- origin


	local distance =
		delta.Magnitude


	if distance <= 0.01
		or distance > maxRange then

		return false,
			bestScore
	end


	local dot =
		aimDirection:
		Dot(
			delta.Unit
		)


	if dot < coneDot then

		return false,
			bestScore
	end


	if not hasLineOfSight(
		origin,
		targetCharacter,
		root.Position
		) then

		return false,
			bestScore
	end


	-- Same scoring family used by ProjectileServer:
	-- angular closeness dominates, distance is a small tie-break.
	local score =
		(1 - dot) * 100
		+ distance * 0.015


	if score >= bestScore then

		return false,
			bestScore
	end


	return true,
		score
end


local function hasLikelyGuidanceTarget(
	origin: Vector3,
	baseDirection: Vector3,
	projectileType: string
): boolean

	local config =
		ProjectileConfigs[
	projectileType
	]


	if typeof(config) ~= "table"
		or typeof(
			config.Guidance
		) ~= "table" then

		return false
	end


	local guidance =
		config.Guidance


	if guidance.Mode ~= "Predictive" then
		return false
	end


	local maxRange =
		if typeof(
			guidance.AcquireRange
		) == "number"
		then guidance.AcquireRange
		else 0


	-- ProjectileServer v3.0 selects the target inside AimAssistConeDegrees.
	-- AcquireConeDegrees remains only as a legacy fallback.
	local serverCone =
		if typeof(
			guidance.AimAssistConeDegrees
		) == "number"
		then guidance.AimAssistConeDegrees
		elseif typeof(
			guidance.AcquireConeDegrees
		) == "number"
		then guidance.AcquireConeDegrees
		else 0


	local serverRange =
		if typeof(
			guidance.AimAssistRange
		) == "number"
		then guidance.AimAssistRange
		else maxRange


	maxRange =
		serverRange


	local localCone =
		math.max(
			4,
			serverCone
			- ARC_TRIGGER_CONE_MARGIN_DEGREES
		)


	local coneDot =
		math.cos(
			math.rad(
				localCone
			)
		)


	local bestScore =
		math.huge


	local considered: {[Model]: boolean} =
		{}


	for _, targetPlayer in ipairs(
		Players:
			GetPlayers()
		) do

		if targetPlayer == player then
			continue
		end


		local targetCharacter =
			targetPlayer.Character


		if targetCharacter then

			considered[
			targetCharacter
			] =
				true


			local accepted,
				score =
				considerTarget(
					targetCharacter,
					origin,
					baseDirection,
					maxRange,
					coneDot,
					bestScore
				)


			if accepted then

				return true
			end


			bestScore =
				math.min(
					bestScore,
					score
				)
		end
	end


	for _, tagged in ipairs(
		CollectionService:
			GetTagged(
				PROJECTILE_TARGET_TAG
			)
		) do

		local targetCharacter =
			if tagged:IsA("Model")
			then tagged
			else findTargetModelFromInstance(
				tagged
			)


		if not targetCharacter
			or considered[
			targetCharacter
			] then

			continue
		end


		local accepted,
			score =
			considerTarget(
				targetCharacter,
				origin,
				baseDirection,
				maxRange,
				coneDot,
				bestScore
			)


		if accepted then

			return true
		end


		bestScore =
			math.min(
				bestScore,
				score
			)
	end


	return false
end


local function getArcSide(
	projectileType: string,
	profile: ArcProfile
): number

	if not profile.AlternateSide then
		return 1
	end


	local now =
		time()


	if now - runtimeState.LastArcAssignedAt > 0.16
		or runtimeState.LastProjectileType
		~= projectileType then

		runtimeState.ArcSide =
			-runtimeState.ArcSide

		runtimeState.LastArcAssignedAt =
			now

		runtimeState.LastProjectileType =
			projectileType
	end


	return runtimeState.ArcSide
end


local function buildArcDirection(
	baseDirection: Vector3,
	distance: number,
	projectileType: string,
	profile: ArcProfile
): Vector3

	if distance <=
		profile.MinDistance then

		return baseDirection
	end


	local distanceAlpha =
		math.clamp(
			(
				distance
				- profile.MinDistance
			)
			/ math.max(
				0.001,
				profile.FullDistance
				- profile.MinDistance
			),
			0,
			1
		)


	distanceAlpha =
		distanceAlpha
		* distanceAlpha
		* (
			3
			- 2 * distanceAlpha
		)


	local side =
		getArcSide(
			projectileType,
			profile
		)


	local camera =
		workspace.CurrentCamera


	local referenceUp =
		Vector3.yAxis


	if math.abs(
		baseDirection:
			Dot(
				referenceUp
			)
		) > 0.94
			and camera then

		referenceUp =
			camera.CFrame.UpVector
	end


	local lateral =
		referenceUp:
		Cross(
			baseDirection
		)


	if lateral.Magnitude < 0.05
		and camera then

		lateral =
			camera.CFrame.RightVector
	end


	if lateral.Magnitude < 0.05 then
		return baseDirection
	end


	lateral =
		lateral.Unit


	local localUp =
		baseDirection:
		Cross(
			lateral
		)


	if localUp.Magnitude < 0.05 then
		return baseDirection
	end


	localUp =
		localUp.Unit


	local yawRadians =
		math.rad(
			profile.YawDegrees
			* distanceAlpha
		)


	local pitchRadians =
		math.rad(
			profile.PitchDegrees
			* distanceAlpha
		)


	local biased =
		baseDirection
		+ lateral
		* math.tan(
			yawRadians
		)
		* side
		+ localUp
		* math.tan(
			pitchRadians
		)


	if biased.Magnitude < 0.001 then
		return baseDirection
	end


	return biased.Unit
end


-- Install/upgrade wrapper.
--
-- If v1 was already required in this play session, restore its saved original
-- function before installing v2. This prevents nested wrappers.
local originalGetDirectionFromOrigin =
	CombatAim._DiabloProjectileLaunchArcOriginal


if typeof(originalGetDirectionFromOrigin)
	~= "function" then

	originalGetDirectionFromOrigin =
		CombatAim.GetDirectionFromOrigin
end


CombatAim.GetDirectionFromOrigin =
	originalGetDirectionFromOrigin


CombatAim._DiabloProjectileLaunchArcOriginal =
	originalGetDirectionFromOrigin


CombatAim.GetDirectionFromOrigin =
	function(
		worldOrigin: Vector3,
		maxDistance: number?,
		raycastParams: RaycastParams?
	)

	local direction,
		targetPoint,
		result =
		originalGetDirectionFromOrigin(
			worldOrigin,
			maxDistance,
			raycastParams
		)


	if typeof(direction) ~= "Vector3"
		or typeof(targetPoint) ~= "Vector3" then

		return direction,
			targetPoint,
			result
	end


	local projectileType =
		getSelectedProjectileType()


	if not projectileType then

		return direction,
			targetPoint,
			result
	end


	-- CRITICAL v2 RULE:
	-- Empty-space / wall aim stays EXACTLY on the reticle.
	if not hasLikelyGuidanceTarget(
		worldOrigin,
		direction.Unit,
		projectileType
		) then

		return direction,
			targetPoint,
			result
	end


	local profile =
		PROFILES[
	projectileType
	]


	if not profile then

		return direction,
			targetPoint,
			result
	end


	local distance =
		(
			targetPoint
			- worldOrigin
		).Magnitude


	local arcDirection =
		buildArcDirection(
			direction.Unit,
			distance,
			projectileType,
			profile
		)


	return arcDirection,
		targetPoint,
		result
end


CombatAim._DiabloProjectileLaunchArcWrapped =
	true

CombatAim._DiabloProjectileLaunchArcVersion =
	2


script.Destroying:
	Connect(
		function()

			if runtimeState.Character ==
				character then

				runtimeState.Character =
				nil
			end
		end
	)


print(
	"[ProjectileLaunchArcController] READY v3"
		.. " | LightHandThrowArcs=ON"
		.. " | FreeAimReticleExact=ON"
		.. " | AimAssistConeAware=ON"
		.. " | CounterPathUntouched=ON"
)
