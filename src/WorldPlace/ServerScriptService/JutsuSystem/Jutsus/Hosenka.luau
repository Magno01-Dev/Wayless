--!strict
-- ServerScriptService > JutsuSystem > Jutsus > Hosenka
--
-- Hosenka v10
--
-- - Proyectiles secuenciales muy rapidos.
-- - Spawn autoritativo desde la boca.
-- - VFX inicia visualmente EXACTAMENTE desde la boca.
-- - Aim arriba / recto / abajo hasta -60.
-- - Spread propio de Hosenka.
-- - Impact VFX FireJutsuEnd.
-- - Impact sound 99101526343223.
-- - Sin AOE.

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

local Hosenka = {}

Hosenka.Id =
	"Hosenka"

Hosenka.NatureId =
	"Fire"

Hosenka.TechniqueCategory =
	"ElementalNinjutsu"

---------------------------------------------------------------------
-- MARKER CONTRACT
---------------------------------------------------------------------

Hosenka.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

Hosenka.MarkerCastTimeout =
	8.0

Hosenka.ProjectileFallbackDelay =
	6.0

Hosenka.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- BURST
---------------------------------------------------------------------

local HOSENKA_SHOT_INTERVAL =
	0.07

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local HOSENKA_MIN_DOWNWARD_PITCH_DEGREES =
	-60

---------------------------------------------------------------------
-- IMPACT
---------------------------------------------------------------------

local HOSENKA_IMPACT_VFX =
	"FireJutsuEnd"

local HOSENKA_IMPACT_VFX_SCALE =
	0.55

local HOSENKA_IMPACT_SOUND_ID =
	"rbxassetid://99101526343223"

local HOSENKA_IMPACT_SOUND_VOLUME =
	1.0

local HOSENKA_IMPACT_SOUND_ROLLOFF_MIN =
	8

local HOSENKA_IMPACT_SOUND_ROLLOFF_MAX =
	140

---------------------------------------------------------------------
-- MOUTH POSITION
---------------------------------------------------------------------

local MOUTH_DOWN_OFFSET_SCALE =
	0.13

local MOUTH_FORWARD_OFFSET =
	0.05

---------------------------------------------------------------------
-- DAMAGE
---------------------------------------------------------------------

local BODY_HIT_RESULTS: {[string]: boolean} = {
	Damaged = true,
	Downed = true,
	DamagedNPC = true,
}

local HOSENKA_TARGET_HIT_RADIUS_MIN =
	ProjectileSkillshotPolicy.TargetRadiusMin

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
		Instance.new("Part")

	holder.Name =
		"HosenkaImpactSound"

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

	holder.CanTouch =
		false

	holder.CanQuery =
		false

	holder.CastShadow =
		false

	holder.Position =
		position

	holder.Parent =
		workspace

	local sound =
		Instance.new("Sound")

	sound.Name =
		"HosenkaExplosion"

	sound.SoundId =
		soundId

	sound.Volume =
		volume

	sound.RollOffMode =
		Enum.RollOffMode.InverseTapered

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
-- TRUE MOUTH POSITION
---------------------------------------------------------------------

local function getMouthPosition(
	head: BasePart
): Vector3

	-----------------------------------------------------------------
	-- IDEAL:
	-- custom MouthAttachment
	-----------------------------------------------------------------

	local mouthAttachment =
		head:FindFirstChild(
			"MouthAttachment"
		)

	if mouthAttachment
		and mouthAttachment:IsA(
			"Attachment"
		) then

		return mouthAttachment.WorldPosition
	end

	-----------------------------------------------------------------
	-- R15 FACE FRONT
	-----------------------------------------------------------------

	local faceFront =
		head:FindFirstChild(
			"FaceFrontAttachment"
		)

	if faceFront
		and faceFront:IsA(
			"Attachment"
		) then

		return faceFront.WorldPosition

		- head.CFrame.UpVector
			* (
				head.Size.Y
				* MOUTH_DOWN_OFFSET_SCALE
			)

			+ head.CFrame.LookVector
			* MOUTH_FORWARD_OFFSET
	end

	-----------------------------------------------------------------
	-- FACE CENTER
	-----------------------------------------------------------------

	local faceCenter =
		head:FindFirstChild(
			"FaceCenterAttachment"
		)

	if faceCenter
		and faceCenter:IsA(
			"Attachment"
		) then

		return faceCenter.WorldPosition

		- head.CFrame.UpVector
			* (
				head.Size.Y
				* MOUTH_DOWN_OFFSET_SCALE
			)

			+ head.CFrame.LookVector
			* MOUTH_FORWARD_OFFSET
	end

	-----------------------------------------------------------------
	-- GENERIC FALLBACK
	-----------------------------------------------------------------

	return head.CFrame:
		PointToWorldSpace(
			Vector3.new(
				0,

				-head.Size.Y
				* 0.13,

				-head.Size.Z
				* 0.50
			)
		)
end

---------------------------------------------------------------------
-- PITCH
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
			math.sin(pitch),
			-math.cos(pitch)
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

	return (
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
	).Unit
end

---------------------------------------------------------------------
-- SANITIZE AIM
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
-- REQUEST
---------------------------------------------------------------------

function Hosenka.SanitizeRequest(
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
end

---------------------------------------------------------------------
-- RESOLVED DIRECTION
---------------------------------------------------------------------

local function getResolvedDirection(
	context: any
): Vector3

	local config =
		context.Config

	local direction: Vector3 =
		context.RequestData.Direction

	local minimumPitch =
		HOSENKA_MIN_DOWNWARD_PITCH_DEGREES

	if config.Aim
		and typeof(
			config.Aim.MinPitchDegrees
		) == "number" then

		minimumPitch =
			math.min(
				config.Aim.MinPitchDegrees,
				HOSENKA_MIN_DOWNWARD_PITCH_DEGREES
			)
	end

	return clampMinimumPitch(
		direction,
		minimumPitch
	).Unit
end

---------------------------------------------------------------------
-- SPREAD
---------------------------------------------------------------------

local function applySpread(
	direction: Vector3,
	yawDegrees: number,
	pitchDegrees: number
): Vector3

	local base =
		CFrame.lookAt(
			Vector3.zero,
			direction.Unit,
			Vector3.yAxis
		)

	local spreadCFrame =
		base
		* CFrame.Angles(
			math.rad(
				pitchDegrees
			),
			math.rad(
				yawDegrees
			),
			0
		)

	return spreadCFrame.LookVector.Unit
end

---------------------------------------------------------------------
-- CASTER
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
		or humanoid.Health <= 0
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
-- ENTITY
---------------------------------------------------------------------

local function resolveDamageableEntity(
	instance: Instance?,
	character: Model,
	CombatEntityService: any
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
		or not entity.Character
		or entity.Character ==
		character
		or entity.CanReceiveDamage ~=
		true
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
		head,
		root =
		getValidCasterParts(
			player,
			character
		)

	if not head
		or not root then

		return
	end

	local direction =
		getResolvedDirection(
			context
		)

	vfxRemote:FireAllClients(
		"Cast",
		{
			JutsuId =
				Hosenka.Id,

			Caster =
				character,

			Position =
				getMouthPosition(
					head
				),

			Direction =
				direction,

			CastTime =
				config.CastTime,
		}
	)
end

---------------------------------------------------------------------
-- LAUNCH ONE PROJECTILE
---------------------------------------------------------------------

local function launchProjectile(
	context: any,
	shotIndex: number,
	direction: Vector3,
	hitCounts: {[Model]: number},
	burnedTargets: {[Model]: boolean}
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

	local StatusEffectService =
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

	local projectileConfig =
		config.Projectile

	local speed: number =
		projectileConfig.Speed

	local maxDistance: number =
		projectileConfig.MaxDistance

	local radius: number =
		projectileConfig.Radius

	local vfxScale =
		if typeof(
			projectileConfig.VFXScale
		) == "number"
		then
		projectileConfig.VFXScale
		else
		1

	local lifetime =
		maxDistance
		/ speed

	-----------------------------------------------------------------
	-- AUTHORITATIVE ORIGIN = MOUTH
	-----------------------------------------------------------------

	local startPosition =
		getMouthPosition(
			head
		)

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
	-- StartVisualAtOrigin means:
	--
	-- Do NOT compensate network latency on the first rendered frame.
	-- Show it exactly from StartPosition first.
	-----------------------------------------------------------------

	vfxRemote:FireAllClients(
		"Projectile",
		{
			JutsuId =
				Hosenka.Id,

			VFXModel =
				if typeof(
					config.VFXModel
				) == "string"
				then
				config.VFXModel
				else
				Hosenka.Id,

			VFXScale =
				vfxScale,

			StartVisualAtOrigin =
				true,

			ProjectileId =
				projectileId,

			ShotIndex =
				shotIndex,

			Caster =
				character,

			StartPosition =
				startPosition,

			Direction =
				direction,

			Speed =
				speed,

			Lifetime =
				lifetime,

			Radius =
				radius,

			SpawnedAt =
				spawnedAt,
		}
	)

	-----------------------------------------------------------------
	-- COLLISION
	-----------------------------------------------------------------

	local targetHitRadius =
		math.max(
			HOSENKA_TARGET_HIT_RADIUS_MIN,

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
				instance,
				character,
				CombatEntityService
			)

		if entity then

			return true,
				entity.Character
		end

		if instance:GetAttribute(
			"ProjectileBlocker"
			) == true then

			return false,
				nil
		end

		if instance:GetAttribute(
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
	-- WORLD CAST
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
				workspace:Spherecast(
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
			+ displacement
			* 0.5

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
					part,
					character,
					CombatEntityService
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
	-- IMPACT POSITION
	-----------------------------------------------------------------

	local function getImpactCenter(
		origin: Vector3,
		displacement: Vector3,
		distance: number
	): Vector3

		if displacement.Magnitude <=
			0.001 then

			return origin
		end

		return origin
			+ displacement.Unit
			* math.clamp(
				distance,
				0,
				displacement.Magnitude
			)
	end

	-----------------------------------------------------------------
	-- STATE
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
		hitSomething: boolean
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

		if hitSomething then

			vfxRemote:FireAllClients(
				"Impact",
				{
					JutsuId =
						Hosenka.Id,

					ProjectileId =
						projectileId,

					ShotIndex =
						shotIndex,

					Position =
						impactPosition,

					Direction =
						direction,

					ImpactVFX =
						HOSENKA_IMPACT_VFX,

					ImpactVFXScale =
						HOSENKA_IMPACT_VFX_SCALE,
				}
			)

			playWorldSound(
				impactPosition,
				HOSENKA_IMPACT_SOUND_ID,
				HOSENKA_IMPACT_SOUND_VOLUME,
				HOSENKA_IMPACT_SOUND_ROLLOFF_MIN,
				HOSENKA_IMPACT_SOUND_ROLLOFF_MAX
			)

		else

			vfxRemote:FireAllClients(
				"Expire",
				{
					JutsuId =
						Hosenka.Id,

					ProjectileId =
						projectileId,

					ShotIndex =
						shotIndex,

					Position =
						impactPosition,

					Direction =
						direction,
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- DAMAGE
	-----------------------------------------------------------------

	local function applyTargetHit(
		entity: any
	)

		local targetCharacter: Model =
			entity.Character

		local maximumHits =
			if typeof(
				config.MaxHitsPerTarget
			) == "number"
			then
			math.max(
				1,
				math.floor(
					config.MaxHitsPerTarget
				)
			)
			else
			3

		local currentHits =
			hitCounts[
		targetCharacter
		] or 0

		if currentHits >=
			maximumHits then

			return
		end

		local resolution =
			DamageService.Apply({
				TargetCharacter =
				targetCharacter,

				TargetHumanoid =
				entity.Humanoid,

				TargetPlayer =
				entity.Player,

				Attacker =
				player,

				Damage =
				config.Damage,

				SourceType =
				"Jutsu",

				SourceId =
				Hosenka.Id,

				Armor =
				config.Armor,
			})

		if not BODY_HIT_RESULTS[
			resolution.Result
			] then

			return
		end

		hitCounts[
		targetCharacter
		] =
			currentHits + 1

		if not config.Burn
			or config.Burn.Enabled ~=
			true then

			return
		end

		if config.Burn.OncePerTarget ==
			true
			and burnedTargets[
			targetCharacter
			] == true then

			return
		end

		burnedTargets[
		targetCharacter
		] =
			true

		StatusEffectService.Apply(
			targetCharacter,
			"Burn",
			{
				Duration =
					config.Burn.Duration,

				Stacks =
					config.Burn.Stacks,

				SourcePlayer =
					player,

				SourceCharacter =
					character,

				Metadata = {
					SourceJutsu =
						Hosenka.Id,

					ShotIndex =
						shotIndex,
				},
			}
		)
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
						false
					)

					return
				end

				local remaining =
				maxDistance
				- travelled

				if remaining <= 0 then

					finish(
						position,
						false
					)

					return
				end

				local frameDistance =
				math.min(
					speed * deltaTime,
					remaining
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

					local targetEntity,
					targetDistance =
					findTargetAlongStep(
						position,
						displacement,
						worldDistance
					)

					if targetEntity
						and targetDistance then

						local impactPosition =
						getImpactCenter(
							position,
							displacement,
							targetDistance
						)

						applyTargetHit(
							targetEntity
						)

						finish(
							impactPosition,
							true
						)

						return
					end

					if worldResult then

						local impactPosition =
						getImpactCenter(
							position,
							displacement,
							worldDistance
						)

						finish(
							impactPosition,
							true
						)

						return
					end

					position +=
					displacement

					travelled +=
					substepDistance

					if travelled >=
						maxDistance
						- 0.001 then

						finish(
							position,
							false
						)

						return
					end
				end
			end
		)
end

---------------------------------------------------------------------
-- HOSENKA BURST
---------------------------------------------------------------------

local function spawnHosenkaBurst(
	context: any
)

	local player: Player =
		context.Player

	local character: Model =
		context.Character

	local config =
		context.Config

	local validHumanoid,
		validHead,
		validRoot =
		getValidCasterParts(
			player,
			character
		)

	if not validHumanoid
		or not validHead
		or not validRoot then

		return
	end

	local baseDirection =
		getResolvedDirection(
			context
		)

	local projectileConfig =
		config.Projectile

	local offsets =
		projectileConfig.Offsets

	if typeof(offsets) ~=
		"table" then

		warn(
			"[Hosenka v10] Missing Projectile.Offsets"
		)

		return
	end

	local requestedCount =
		if typeof(
			projectileConfig.Count
		) == "number"
		then
		math.floor(
			projectileConfig.Count
		)
		else
		#offsets

	local count =
		math.clamp(
			requestedCount,
			1,
			#offsets
		)

	local hitCounts:
		{[Model]: number} =
		{}

	local burnedTargets:
		{[Model]: boolean} =
		{}

	task.spawn(
		function()

			for shotIndex = 1,
				count do

				local currentHumanoid,
				currentHead,
				currentRoot =
					getValidCasterParts(
						player,
						character
					)

				if not currentHumanoid
					or not currentHead
					or not currentRoot then

					return
				end

				local offset =
					offsets[
				shotIndex
				]

				local yaw =
					if typeof(offset) ==
					"table"
					and typeof(
						offset.Yaw
					) == "number"
					then
					offset.Yaw
					else
					0

				local pitch =
					if typeof(offset) ==
					"table"
					and typeof(
						offset.Pitch
					) == "number"
					then
					offset.Pitch
					else
					0

				local shotDirection =
					applySpread(
						baseDirection,
						yaw,
						pitch
					)

				shotDirection =
					clampMinimumPitch(
						shotDirection,
						HOSENKA_MIN_DOWNWARD_PITCH_DEGREES
					)

				launchProjectile(
					context,
					shotIndex,
					shotDirection,
					hitCounts,
					burnedTargets
				)

				if shotIndex <
					count then

					task.wait(
						HOSENKA_SHOT_INTERVAL
					)
				end
			end
		end
	)
end

---------------------------------------------------------------------
-- MARKER CAST
---------------------------------------------------------------------

function Hosenka.OnCastStarted(
	_context: any
)
end

function Hosenka.OnCastMarker(
	context: any,
	semanticMarker: string,
	_source: string,
	markerPayload: any?
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

		spawnHosenkaBurst(
			context
		)
	end
end

function Hosenka.OnCastEnded(
	_context: any,
	_reason: string
)
end

---------------------------------------------------------------------
-- LEGACY
---------------------------------------------------------------------

function Hosenka.Execute(
	context: any
)

	fireCastVFX(
		context
	)

	task.delay(
		context.Config.CastTime,
		function()

			spawnHosenkaBurst(
				context
			)
		end
	)
end

return Hosenka