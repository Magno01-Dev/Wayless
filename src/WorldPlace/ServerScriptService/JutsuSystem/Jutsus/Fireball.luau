--!strict
-- ServerScriptService > JutsuSystem > Jutsus > Fireball
--
-- Fireball v15
--
-- NUEVA ESTRUCTURA VFX:
--
-- ReplicatedStorage
-- +-- VFX
--     +-- Jutsus
--         +-- Fire
--             +-- Fireball
--                 +-- Root
--                 +-- FireJutsuEnd
--
-- IMPORTANTE:
-- - El gameplay de Fireball v14 se mantiene.
-- - Solo se adapta la ubicacion de los VFX Katon.
-- - Projectile payload ahora envia VFXNature = "Fire".
-- - Projectile payload ahora envia VFXModel = "Fireball".
-- - FireJutsuEnd se busca dentro de:
--   ReplicatedStorage.VFX.Jutsus.FireJutsuEnd
--
-- PRESERVADO:
-- - Release-time aim.
-- - Downward aim hasta -60.
-- - Skillshot target hitbox.
-- - Tiny world collision core.
-- - Explosion AOE.
-- - DamageService.
-- - Fire/Burn handling.
-- - Spawn/impact sounds.
-- - Marker-driven casting.

local RunService =
	game:GetService("RunService")

local HttpService =
	game:GetService("HttpService")

local Debris =
	game:GetService("Debris")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

---------------------------------------------------------------------
-- SKILLSHOT POLICY
---------------------------------------------------------------------

local ProjectileSkillshotPolicy =
	require(
		ReplicatedStorage:
		WaitForChild("JutsuSystem"):
		WaitForChild("Shared"):
		WaitForChild("ProjectileSkillshotPolicy")
	)

---------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------

local Fireball = {}

Fireball.Id =
	"Fireball"

Fireball.NatureId =
	"Fire"

Fireball.TechniqueCategory =
	"ElementalNinjutsu"

---------------------------------------------------------------------
-- MARKER CONTRACT
---------------------------------------------------------------------

Fireball.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

Fireball.MarkerCastTimeout =
	8.0

Fireball.ProjectileFallbackDelay =
	6.0

Fireball.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- DAMAGE RESULTS
---------------------------------------------------------------------

local BODY_HIT_RESULTS: {[string]: boolean} = {
	Damaged = true,
	Downed = true,
	DamagedNPC = true,
}

---------------------------------------------------------------------
-- FIREBALL SFX
---------------------------------------------------------------------

local FIREBALL_SPAWN_SOUND_ID =
	"rbxassetid://113831670560719"

local FIREBALL_IMPACT_SOUND_ID =
	"rbxassetid://130565967505452"

local FIREBALL_SPAWN_SOUND_VOLUME =
	1.0

local FIREBALL_IMPACT_SOUND_VOLUME =
	1.35

local FIREBALL_SPAWN_SOUND_ROLLOFF_MIN =
	8

local FIREBALL_SPAWN_SOUND_ROLLOFF_MAX =
	80

local FIREBALL_IMPACT_SOUND_ROLLOFF_MIN =
	12

local FIREBALL_IMPACT_SOUND_ROLLOFF_MAX =
	220

---------------------------------------------------------------------
-- FIREBALL COLLISION / EXPLOSION
---------------------------------------------------------------------

local FIREBALL_EXPLOSION_DAMAGE =
	12

local FIREBALL_EXPLOSION_RADIUS =
	9

local FIREBALL_MIN_DOWNWARD_PITCH_DEGREES =
	-60

local FIREBALL_TARGET_HIT_RADIUS_MIN =
	ProjectileSkillshotPolicy
	.TargetRadiusMin

---------------------------------------------------------------------
-- VFX LOCATION
--
-- ReplicatedStorage
-- +-- VFX
--     +-- Jutsus
--         +-- Fire
--             +-- Fireball
---------------------------------------------------------------------

local function getFireballVFXTemplate(): Instance?

	local vfxFolder =
		ReplicatedStorage:
		FindFirstChild(
			"VFX"
		)

	if not vfxFolder then
		return nil
	end

	local jutsusFolder =
		vfxFolder:
		FindFirstChild(
			"Jutsus"
		)

	if not jutsusFolder then
		return nil
	end

	local fireFolder =
		jutsusFolder:
		FindFirstChild(
			"Fire"
		)

	if not fireFolder then
		return nil
	end

	return fireFolder:
		FindFirstChild(
			"Fireball"
		)
end

---------------------------------------------------------------------
-- FIREJUTSUEND LOCATION
--
-- CANONICAL EXISTING ROUTE:
-- ReplicatedStorage > VFX > Jutsus > FireJutsuEnd
--
-- FireJutsuEnd was never moved into Fire/Fireball.
---------------------------------------------------------------------

local function getFireJutsuEndTemplate(): Instance?
	local vfxFolder =
		ReplicatedStorage:
		FindFirstChild(
			"VFX"
		)

	if not vfxFolder then
		return nil
	end

	local jutsusFolder =
		vfxFolder:
		FindFirstChild(
			"Jutsus"
		)

	if not jutsusFolder then
		return nil
	end

	return jutsusFolder:
		FindFirstChild(
			"FireJutsuEnd"
		)
end

local FIRE_JUTSU_END_ACTIVE_TIME =
	0.30

local FIRE_JUTSU_END_CLEANUP_TIME =
	4.0

---------------------------------------------------------------------
-- BURST COUNT
---------------------------------------------------------------------

local function resolveBurstCount(
	emitter: ParticleEmitter
): number

	local explicit =
		emitter:
		GetAttribute(
			"EmitCount"
		)

	if typeof(explicit) ==
		"number" then

		return math.max(
			1,
			math.floor(
				explicit
			)
		)
	end

	local burst =
		emitter:
		GetAttribute(
			"BurstCount"
		)

	if typeof(burst) ==
		"number" then

		return math.max(
			1,
			math.floor(
				burst
			)
		)
	end

	local lowerName =
		string.lower(
			emitter.Name
		)

	if string.find(
		lowerName,
		"smoke",
		1,
		true
		) then

		return 12

	elseif string.find(
		lowerName,
		"ember",
		1,
		true
		) then

		return 18

	elseif string.find(
		lowerName,
		"sharp",
		1,
		true
		)

			or string.find(
				lowerName,
				"shrap",
				1,
				true
			) then

		return 22
	end

	if emitter.Rate >
		0 then

		return math.clamp(
			math.floor(
				emitter.Rate
					* 0.20
					+ 0.5
			),
			4,
			30
		)
	end

	return 12
end

---------------------------------------------------------------------
-- FIREJUTSUEND VFX
---------------------------------------------------------------------

local function playFireJutsuEndVFX(
	position: Vector3,
	direction: Vector3
)

	local template =
		getFireJutsuEndTemplate()

	if not template then

		warn(
			"[Fireball v16] Missing impact VFX at "
				.. "ReplicatedStorage.VFX.Jutsus.FireJutsuEnd"
		)

		return
	end

	local clone =
		template:
		Clone()

	local lookDirection =
		if direction.Magnitude >
		0.001

		then
		direction.Unit

		else
		Vector3.new(
			0,
			0,
			-1
		)

	local placement =
		CFrame.lookAt(
			position,
			position
			+ lookDirection,
			Vector3.yAxis
		)

	-----------------------------------------------------------------
	-- PART
	-----------------------------------------------------------------

	if clone:IsA(
		"BasePart"
		) then

		clone.Anchored =
			true

		clone.CanCollide =
			false

		clone.CanTouch =
			false

		clone.CanQuery =
			false

		clone.CastShadow =
			false

		clone.CFrame =
			placement

		-----------------------------------------------------------------
		-- MODEL
		-----------------------------------------------------------------

	elseif clone:IsA(
		"Model"
		) then

		for _, descendant in ipairs(
			clone:
				GetDescendants()
			) do

			if descendant:IsA(
				"BasePart"
				) then

				descendant.Anchored =
					true

				descendant.CanCollide =
					false

				descendant.CanTouch =
					false

				descendant.CanQuery =
					false

				descendant.CastShadow =
					false
			end
		end

		clone:
			PivotTo(
				placement
			)
	end

	clone.Parent =
		workspace

	-----------------------------------------------------------------
	-- EMITTERS
	-----------------------------------------------------------------

	for _, descendant in ipairs(
		clone:
			GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			local wasEnabled =
				descendant.Enabled

			if wasEnabled then

				task.delay(
					FIRE_JUTSU_END_ACTIVE_TIME,

					function()

						if descendant.Parent then

							descendant.Enabled =
								false
						end
					end
				)

			else

				descendant:
					Emit(
						resolveBurstCount(
							descendant
						)
					)
			end
		end
	end

	Debris:AddItem(
		clone,
		FIRE_JUTSU_END_CLEANUP_TIME
	)
end

---------------------------------------------------------------------
-- WORLD SOUND
---------------------------------------------------------------------

local function playWorldSound(
	position: Vector3,
	soundId: string,
	volume: number,
	rolloffMin: number,
	rolloffMax: number
)

	local holder =
		Instance.new(
			"Part"
		)

	holder.Name =
		"JutsuSoundEmitter"

	holder.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)

	holder.Transparency =
		1

	holder.Anchored =
		true

	holder.CanCollide =
		false

	holder.CanQuery =
		false

	holder.CanTouch =
		false

	holder.CastShadow =
		false

	holder.CFrame =
		CFrame.new(
			position
		)

	holder.Parent =
		workspace

	local sound =
		Instance.new(
			"Sound"
		)

	sound.SoundId =
		soundId

	sound.Volume =
		volume

	sound.RollOffMode =
		Enum.RollOffMode
		.InverseTapered

	sound.RollOffMinDistance =
		rolloffMin

	sound.RollOffMaxDistance =
		rolloffMax

	sound.Parent =
		holder

	sound:Play()

	Debris:AddItem(
		holder,
		6
	)
end

---------------------------------------------------------------------
-- UTILITIES
---------------------------------------------------------------------

local function isFiniteNumber(
	value: number
): boolean

	return value == value
		and value ~= math.huge
		and value ~= -math.huge
end

---------------------------------------------------------------------
-- AIM PITCH CLAMP
---------------------------------------------------------------------

local function clampMinimumPitch(
	direction: Vector3,
	minPitchDegrees: number
): Vector3

	if direction.Magnitude <
		0.001 then

		return direction
	end

	direction =
		direction.Unit

	local horizontal =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	-----------------------------------------------------------------
	-- VERTICAL
	-----------------------------------------------------------------

	if horizontal.Magnitude <
		0.001 then

		if direction.Y >= 0 then

			return direction
		end

		local pitch =
			math.rad(
				minPitchDegrees
			)

		return Vector3.new(
			0,
			math.sin(
				pitch
			),
			-math.cos(
				pitch
			)
		).Unit
	end

	local horizontalUnit =
		horizontal.Unit

	local currentPitchDegrees =
		math.deg(
			math.asin(
				math.clamp(
					direction.Y,
					-1,
					1
				)
			)
		)

	if currentPitchDegrees >=
		minPitchDegrees then

		return direction
	end

	local pitchRadians =
		math.rad(
			minPitchDegrees
		)

	local correctedDirection =
		horizontalUnit
		* math.cos(
			pitchRadians
		)

		+ Vector3.new(
			0,
			math.sin(
				pitchRadians
			),
			0
		)

	return correctedDirection.Unit
end

---------------------------------------------------------------------
-- REQUEST VALIDATION
---------------------------------------------------------------------

local function sanitizeDirection(
	character: Model,
	payload: any
): (boolean, string, Vector3?)

	if typeof(payload) ~=
		"table" then

		return false,
			"InvalidPayload",
			nil
	end

	local rawDirection =
		payload.Direction

	if typeof(rawDirection) ~=
		"Vector3" then

		return false,
			"InvalidDirection",
			nil
	end

	if not isFiniteNumber(
		rawDirection.X
		)

			or not isFiniteNumber(
				rawDirection.Y
			)

			or not isFiniteNumber(
				rawDirection.Z
			) then

		return false,
			"InvalidDirection",
			nil
	end

	if rawDirection.Magnitude <
		0.001 then

		return false,
			"InvalidDirection",
			nil
	end

	local direction =
		rawDirection.Unit

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA(
			"BasePart"
		) then

		return false,
			"NoRoot",
			nil
	end

	-----------------------------------------------------------------
	-- ANTI-BACKWARDS AIM
	-----------------------------------------------------------------

	local horizontalDirection =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	local horizontalLook =
		Vector3.new(
			root.CFrame.LookVector.X,
			0,
			root.CFrame.LookVector.Z
		)

	if horizontalDirection.Magnitude >
		0.001

			and horizontalLook.Magnitude >
		0.001 then

		local dot =
			horizontalLook.Unit:
			Dot(
				horizontalDirection.Unit
			)

		if dot < -0.25 then

			return false,
				"AimBehindCharacter",
				nil
		end
	end

	return true,
		"OK",
		direction
end

---------------------------------------------------------------------
-- SANITIZE REQUEST
---------------------------------------------------------------------

function Fireball.SanitizeRequest(
	character: Model,
	payload: any
): (boolean, string, any?)

	local ok,
		reason,
		direction =
		sanitizeDirection(
			character,
			payload
		)

	if not ok
		or not direction then

		return false,
			reason,
			nil
	end

	return true,
		"OK",
		{
			Direction =
			direction,
		}
end

---------------------------------------------------------------------
-- RELEASE AIM
---------------------------------------------------------------------

local function refreshReleaseAim(
	context: any,
	markerPayload: any?
)

	if typeof(markerPayload) ~=
		"table" then

		return
	end

	local ok,
		_reason,
		direction =
		sanitizeDirection(
			context.Character,
			markerPayload
		)

	if not ok
		or not direction then

		return
	end

	context.RequestData.Direction =
		direction

	print(
		"[Fireball v16] RELEASE AIM ACCEPTED",
		direction
	)
end

---------------------------------------------------------------------
-- RESOLVE FINAL AIM
---------------------------------------------------------------------

local function getResolvedDirection(
	context: any
): Vector3

	local config =
		context.Config

	local requestData =
		context.RequestData

	local direction: Vector3 =
		requestData.Direction

	local configuredMinPitch =
		FIREBALL_MIN_DOWNWARD_PITCH_DEGREES

	if config.Aim
		and typeof(
			config.Aim.MinPitchDegrees
		) == "number" then

		configuredMinPitch =
			math.min(
				config.Aim.MinPitchDegrees,
				FIREBALL_MIN_DOWNWARD_PITCH_DEGREES
			)
	end

	direction =
		clampMinimumPitch(
			direction,
			configuredMinPitch
		)

	return direction
end

---------------------------------------------------------------------
-- VALIDATE CASTER
---------------------------------------------------------------------

local function getValidCasterParts(
	player: Player,
	character: Model
): (Humanoid?, BasePart?, BasePart?)

	if not player.Parent

		or player.Character ~=
		character

		or not character.Parent then

		return nil,
			nil,
			nil
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local head =
		character:
		FindFirstChild(
			"Head"
		)

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid

		or humanoid.Health <=
		0

		or not head

		or not head:IsA(
			"BasePart"
		)

			or not root

			or not root:IsA(
				"BasePart"
			) then

		return nil,
			nil,
			nil
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
				"Status_AttackBlocked"
			) == true

			or character:GetAttribute(
				"Status_Stunned"
			) == true

			or character:GetAttribute(
				"IsStunned"
			) == true then

		return nil,
			nil,
			nil
	end

	return humanoid,
		head,
		root
end

---------------------------------------------------------------------
-- CAST VFX
---------------------------------------------------------------------

local function fireCastVFX(
	context: any
)

	local player: Player =
		context.Player

	local character: Model =
		context.Character

	local config =
		context.Config

	local vfxRemote: RemoteEvent =
		context.VFXRemote

	local _humanoid,
		initialHead,
		initialRoot =
		getValidCasterParts(
			player,
			character
		)

	if not initialHead
		or not initialRoot then

		return
	end

	local direction =
		getResolvedDirection(
			context
		)

	vfxRemote:
		FireAllClients(
			"Cast",
			{
				JutsuId =
				Fireball.Id,

				VFXNature =
				Fireball.NatureId,

				VFXModel =
				Fireball.Id,

				Caster =
				character,

				Position =
				initialHead.Position
				+ direction * 1.5,

				Direction =
				direction,

				CastTime =
				if config.Animation
				and typeof(
					config.Animation
					.ReleaseTelegraphTime
				) == "number"

				then
				config.Animation
				.ReleaseTelegraphTime

				else
				config.CastTime,
			}
		)
end

---------------------------------------------------------------------
-- PROJECTILE
---------------------------------------------------------------------

local function spawnProjectile(
	context: any
)

	local player: Player =
		context.Player

	local character: Model =
		context.Character

	local config =
		context.Config

	local vfxRemote: RemoteEvent =
		context.VFXRemote

	local DamageService =
		context.DamageService

	local CombatEntityService =
		context.CombatEntityService

	local _StatusEffectService =
		context.StatusEffectService

	local _humanoid,
		head,
		_root =
		getValidCasterParts(
			player,
			character
		)

	if not head then
		return
	end

	-----------------------------------------------------------------
	-- AIM
	-----------------------------------------------------------------

	local direction =
		getResolvedDirection(
			context
		)

	-----------------------------------------------------------------
	-- PROJECTILE CONFIG
	-----------------------------------------------------------------

	local projectileConfig =
		config.Projectile

	local speed: number =
		projectileConfig.Speed

	local maxDistance: number =
		projectileConfig.MaxDistance

	local radius: number =
		projectileConfig.Radius

	local terrainTolerance =
		0

	if typeof(
		projectileConfig
			.TerrainTolerance
		) == "number" then

		terrainTolerance =
			math.max(
				0,
				projectileConfig
				.TerrainTolerance
			)
	end

	local terrainRadius =
		math.max(
			0,
			radius
			- terrainTolerance
		)

	local maxLifetime =
		maxDistance
		/ speed

	-----------------------------------------------------------------
	-- SPAWN POSITION
	-----------------------------------------------------------------

	local startPosition =
		head.Position
		+ direction * 2.5

	local projectileId =
		HttpService:
		GenerateGUID(
			false
		)

	local spawnedAt =
		workspace:
		GetServerTimeNow()

	-----------------------------------------------------------------
	-- PROJECTILE VFX
	--
	-- NEW PATH METADATA:
	--
	-- VFXNature = "Fire"
	-- VFXModel  = "Fireball"
	--
	-- Final path:
	-- VFX/Jutsus/Fire/Fireball
	-----------------------------------------------------------------

	vfxRemote:
		FireAllClients(
			"Projectile",
			{
				JutsuId =
				Fireball.Id,

				VFXNature =
				Fireball.NatureId,

				VFXModel =
				Fireball.Id,

				ProjectileId =
				projectileId,

				Caster =
				character,

				StartPosition =
				startPosition,

				Direction =
				direction,

				Speed =
				speed,

				Lifetime =
				maxLifetime,

				Radius =
				radius,

				TerrainRadius =
				terrainRadius,

				SpawnedAt =
				spawnedAt,
			}
		)

	-----------------------------------------------------------------
	-- SPAWN SOUND
	-----------------------------------------------------------------

	playWorldSound(
		startPosition,
		FIREBALL_SPAWN_SOUND_ID,
		FIREBALL_SPAWN_SOUND_VOLUME,
		FIREBALL_SPAWN_SOUND_ROLLOFF_MIN,
		FIREBALL_SPAWN_SOUND_ROLLOFF_MAX
	)

	-----------------------------------------------------------------
	-- SKILLSHOT COLLISION
	-----------------------------------------------------------------

	local targetHitRadius =
		math.max(
			FIREBALL_TARGET_HIT_RADIUS_MIN,

			radius
			+ ProjectileSkillshotPolicy
			.TargetRadiusBonus
		)

	local worldCollisionRadius =
		ProjectileSkillshotPolicy
		.WorldCollisionRadius

	local worldRayParams =
		RaycastParams.new()

	worldRayParams.FilterType =
		Enum.RaycastFilterType.Exclude

	local ignoredWorldInstances:
		{Instance} =
		{
			character,
		}

	worldRayParams.IgnoreWater =
		false

	local targetOverlapParams =
		OverlapParams.new()

	targetOverlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	targetOverlapParams.FilterDescendantsInstances = {
		character,
	}

	-----------------------------------------------------------------
	-- RESOLVE ENTITY
	-----------------------------------------------------------------

	local function resolveDamageableEntity(
		instance: Instance?
	): any?

		if not instance
			or not instance:IsA(
				"BasePart"
			) then

			return nil
		end

		local entity =
			CombatEntityService
			.ResolveFromInstance(
				instance
			)

		if not entity

			or entity.Character ==
			character

			or not entity.CanReceiveDamage

			or not CombatEntityService
			.IsAlive(
				entity
			)

				or entity.Character:
				GetAttribute(
					"CombatImmune"
				) == true

				or entity.Character:
				GetAttribute(
					"IsMissionNPC"
				) == true then

			return nil
		end

		return entity
	end

	-----------------------------------------------------------------
	-- WORLD IGNORE
	-----------------------------------------------------------------

	local function shouldIgnoreWorldHit(
		instance: Instance?
	): (boolean, Instance?)

		if not instance
			or not instance:IsA(
				"BasePart"
			) then

			return false,
				nil
		end

		local entity =
			resolveDamageableEntity(
				instance
			)

		if entity then

			return true,
				entity.Character
		end

		if instance:
			GetAttribute(
				"ProjectileBlocker"
			) == true then

			return false,
				nil
		end

		if instance:
			GetAttribute(
				"ProjectileIgnore"
			) == true then

			return true,
				instance
		end

		if not instance.CanCollide then

			return true,
				instance
		end

		return false,
			nil
	end

	-----------------------------------------------------------------
	-- WORLD CORE
	-----------------------------------------------------------------

	local function castWorldCore(
		origin: Vector3,
		displacement: Vector3
	): RaycastResult?

		if displacement.Magnitude <=
			0.001 then

			return nil
		end

		for _ = 1,
			ProjectileSkillshotPolicy
			.MaxIgnoredWorldHits do

			worldRayParams
				.FilterDescendantsInstances =
				ignoredWorldInstances

			local result =
				workspace:
				Spherecast(
					origin,
					worldCollisionRadius,
					displacement,
					worldRayParams
				)

			if not result then

				return nil
			end

			local ignore,
				ignoreInstance =
				shouldIgnoreWorldHit(
					result.Instance
				)

			if not ignore then

				return result
			end

			if ignoreInstance then

				table.insert(
					ignoredWorldInstances,
					ignoreInstance
				)

			else

				return nil
			end
		end

		return nil
	end

	-----------------------------------------------------------------
	-- IMPACT CENTER
	-----------------------------------------------------------------

	local function getImpactCenterFromDistance(
		stepOrigin: Vector3,
		displacement: Vector3,
		distanceAlongStep: number
	): Vector3

		if displacement.Magnitude <=
			0.001 then

			return stepOrigin
		end

		return stepOrigin
			+ displacement.Unit
			* math.clamp(
				distanceAlongStep,
				0,
				displacement.Magnitude
			)
	end

	-----------------------------------------------------------------
	-- TARGET SWEEP
	-----------------------------------------------------------------

	local function findTargetAlongStep(
		stepOrigin: Vector3,
		displacement: Vector3,
		maxDistanceBeforeWorld: number
	): (any?, number?)

		local stepLength =
			displacement.Magnitude

		if stepLength <=
			0.001 then

			return nil,
				nil
		end

		local unitDirection =
			displacement.Unit

		local midpoint =
			stepOrigin
			+ displacement * 0.5

		local sweepCFrame =
			CFrame.lookAt(
				midpoint,
				midpoint
				+ unitDirection
			)

		local sweepSize =
			Vector3.new(
				targetHitRadius * 2,
				targetHitRadius * 2,

				stepLength
				+ targetHitRadius * 2
			)

		local bestEntity: any? =
			nil

		local bestDistance =
			math.huge

		local seen:
			{[Model]: boolean} =
			{}

		for _, part in ipairs(
			workspace:
				GetPartBoundsInBox(
					sweepCFrame,
					sweepSize,
					targetOverlapParams
				)
			) do

			local entity =
				resolveDamageableEntity(
					part
				)

			if entity
				and not seen[
				entity.Character
				] then

				seen[
				entity.Character
				] =
					true

				local targetRoot =
					entity.Character:
					FindFirstChild(
						"HumanoidRootPart"
					)

				local targetPosition =
					if targetRoot
					and targetRoot:IsA(
						"BasePart"
					)

					then
					targetRoot.Position

					else
					part.Position

				local projected =
					(
						targetPosition
						- stepOrigin
					):
					Dot(
						unitDirection
					)

				projected =
					math.clamp(
						projected,
						0,
						stepLength
					)

				if projected <=
					maxDistanceBeforeWorld
					+ ProjectileSkillshotPolicy
					.HitOrderEpsilon then

					local closestPoint =
						stepOrigin
						+ unitDirection
						* projected

					local radialDistance =
						(
							targetPosition
							- closestPoint
						).Magnitude

					if radialDistance <=
						targetHitRadius

						and projected <
						bestDistance then

						bestDistance =
							projected

						bestEntity =
							entity
					end
				end
			end
		end

		if bestEntity then

			return bestEntity,
				bestDistance
		end

		return nil,
			nil
	end

	-----------------------------------------------------------------
	-- EXPLOSION OVERLAP
	-----------------------------------------------------------------

	local explosionOverlapParams =
		OverlapParams.new()

	explosionOverlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	explosionOverlapParams.FilterDescendantsInstances = {
		character,
	}

	local explosionLOSParams =
		RaycastParams.new()

	explosionLOSParams.FilterType =
		Enum.RaycastFilterType.Exclude

	explosionLOSParams.FilterDescendantsInstances = {
		character,
	}

	explosionLOSParams.IgnoreWater =
		false

	-----------------------------------------------------------------
	-- EXPLOSION LOS
	-----------------------------------------------------------------

	local function hasExplosionLOS(
		explosionPosition: Vector3,
		targetCharacter: Model
	): boolean

		local targetRoot =
			targetCharacter:
			FindFirstChild(
				"HumanoidRootPart"
			)

		if not targetRoot
			or not targetRoot:IsA(
				"BasePart"
			) then

			return true
		end

		local toTarget =
			targetRoot.Position
		- explosionPosition

		if toTarget.Magnitude <=
			0.05 then

			return true
		end

		local result =
			workspace:
			Raycast(
				explosionPosition
				+ direction * 0.10,

				toTarget,

				explosionLOSParams
			)

		if not result then

			return true
		end

		return result.Instance:
			IsDescendantOf(
				targetCharacter
			)
	end

	-----------------------------------------------------------------
	-- EXPLOSION DAMAGE
	-----------------------------------------------------------------

	local function applyExplosionDamage(
		explosionPosition: Vector3,
		directHitCharacter: Model?
	)

		local seen:
			{[Model]: boolean} =
			{}

		for _, part in ipairs(
			workspace:
				GetPartBoundsInRadius(
					explosionPosition,
					FIREBALL_EXPLOSION_RADIUS,
					explosionOverlapParams
				)
			) do

			local entity =
				resolveDamageableEntity(
					part
				)

			if entity

				and entity.Character ~=
				directHitCharacter

				and not seen[
				entity.Character
				] then

				seen[
				entity.Character
				] =
					true

				if hasExplosionLOS(
					explosionPosition,
					entity.Character
					) then

					DamageService.Apply({
						TargetCharacter =
							entity.Character,

						TargetHumanoid =
							entity.Humanoid,

						TargetPlayer =
							entity.Player,

						Attacker =
							player,

						Damage =
							FIREBALL_EXPLOSION_DAMAGE,

						SourceType =
							"Jutsu",

						SourceId =
							Fireball.Id,

						Armor =
							config.Armor,
					})
				end
			end
		end
	end

	-----------------------------------------------------------------
	-- PROJECTILE STATE
	-----------------------------------------------------------------

	local position =
		startPosition

	local travelled =
		0.0

	local alive =
		true

	local connection:
		RBXScriptConnection?

	-----------------------------------------------------------------
	-- FINISH
	-----------------------------------------------------------------

	local function finish(
		impactPosition: Vector3,
		hitSomething: boolean,
		directHitCharacter: Model?
	)

		if not alive then
			return
		end

		alive =
			false

		if connection then

			connection:
				Disconnect()

			connection =
				nil
		end

		vfxRemote:
			FireAllClients(
				if hitSomething
				then "Impact"
				else "Expire",

				{
					JutsuId =
					Fireball.Id,

					VFXNature =
					Fireball.NatureId,

					VFXModel =
					Fireball.Id,

					ProjectileId =
					projectileId,

					Position =
					impactPosition,

					Direction =
					direction,
				}
			)

		if hitSomething then

			-------------------------------------------------------------
			-- AOE DAMAGE
			-------------------------------------------------------------

			applyExplosionDamage(
				impactPosition,
				directHitCharacter
			)

			-------------------------------------------------------------
			-- NEW IMPACT VFX LOCATION
			-------------------------------------------------------------

			playFireJutsuEndVFX(
				impactPosition,
				direction
			)

			-------------------------------------------------------------
			-- SOUND
			-------------------------------------------------------------

			playWorldSound(
				impactPosition,
				FIREBALL_IMPACT_SOUND_ID,
				FIREBALL_IMPACT_SOUND_VOLUME,
				FIREBALL_IMPACT_SOUND_ROLLOFF_MIN,
				FIREBALL_IMPACT_SOUND_ROLLOFF_MAX
			)
		end
	end

	-----------------------------------------------------------------
	-- SERVER SIMULATION
	-----------------------------------------------------------------

	connection =
		RunService.Heartbeat:
		Connect(
			function(
				deltaTime: number
			)

				if not alive then
					return
				end

				if not player.Parent

					or player.Character ~=
					character

					or not character.Parent then

					finish(
						position,
						false,
						nil
					)

					return
				end

				local remainingDistance =
				maxDistance
				- travelled

				if remainingDistance <=
					0 then

					finish(
						position,
						false,
						nil
					)

					return
				end

				local frameDistance =
				math.min(
					speed * deltaTime,
					remainingDistance
				)

				local maxSubstep =
				ProjectileSkillshotPolicy
				.MaxSimulationStepDistance

				local substeps =
				math.max(
					1,

					math.ceil(
						frameDistance
						/ maxSubstep
					)
				)

				local substepDistance =
				frameDistance
				/ substeps

				for _ = 1,
					substeps do

					if not alive then
						return
					end

					local displacement =
					direction
					* substepDistance

					-------------------------------------------------
					-- WORLD
					-------------------------------------------------

					local worldResult =
					castWorldCore(
						position,
						displacement
					)

					local worldDistance =
					if worldResult

					then
					math.clamp(
						worldResult.Distance,
						0,
						substepDistance
					)

					else
					substepDistance

					-------------------------------------------------
					-- TARGET
					-------------------------------------------------

					local targetEntity,
					targetDistance =
					findTargetAlongStep(
						position,
						displacement,
						worldDistance
					)

					-------------------------------------------------
					-- TARGET FIRST
					-------------------------------------------------

					if targetEntity
						and targetDistance then

						local impactPosition =
						getImpactCenterFromDistance(
							position,
							displacement,
							targetDistance
						)

						DamageService.Apply({
							TargetCharacter =
							targetEntity.Character,

							TargetHumanoid =
							targetEntity.Humanoid,

							TargetPlayer =
							targetEntity.Player,

							Attacker =
							player,

							Damage =
							config.Damage,

							SourceType =
							"Jutsu",

							SourceId =
							Fireball.Id,

							Armor =
							config.Armor,
						})

						finish(
							impactPosition,
							true,
							targetEntity.Character
						)

						return
					end

					-------------------------------------------------
					-- WORLD FIRST
					-------------------------------------------------

					if worldResult then

						local impactPosition =
						getImpactCenterFromDistance(
							position,
							displacement,
							worldDistance
						)

						finish(
							impactPosition,
							true,
							nil
						)

						return
					end

					-------------------------------------------------
					-- CONTINUE
					-------------------------------------------------

					position +=
					displacement

					travelled +=
					substepDistance

					if travelled >=
						maxDistance
						- 0.001 then

						finish(
							position,
							false,
							nil
						)

						return
					end
				end
			end
		)
end

---------------------------------------------------------------------
-- MARKER CONTRACT
---------------------------------------------------------------------

function Fireball.OnCastStarted(
	_context: any
)
end

function Fireball.OnCastMarker(
	context: any,
	semanticMarker: string,
	source: string,
	markerPayload: any?
)

	print(
		"[Fireball v16] MARKER",
		semanticMarker,
		source
	)

	if semanticMarker ==
		"ReleaseStart" then

		fireCastVFX(
			context
		)

	elseif semanticMarker ==
		"ProjectileSpawn" then

		refreshReleaseAim(
			context,
			markerPayload
		)

		spawnProjectile(
			context
		)
	end
end

function Fireball.OnCastEnded(
	_context: any,
	_reason: string
)
end

---------------------------------------------------------------------
-- LEGACY EXECUTE
---------------------------------------------------------------------

function Fireball.Execute(
	context: any
)

	fireCastVFX(
		context
	)

	task.delay(
		context.Config.CastTime,

		function()

			spawnProjectile(
				context
			)
		end
	)
end

return Fireball