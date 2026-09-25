--!strict
-- ServerScriptService > JutsuSystem > Jutsus > FlameBreath
--
-- WAYLESS FlameBreath v6
--
-- - Damage is server-authoritative through DamageService.
-- - Damage cone always follows HumanoidRootPart.LookVector.
-- - Client VFX follows character rotation through JutsuVFXController.
-- - VFX/gameplay breath duration: 1 second.
-- - Generic movement restriction:
--     * Block sprint for 1.5 seconds.
--     * Maximum WalkSpeed 16.
--     * Walking is still allowed.
--
-- Generic restriction is NOT implemented specifically inside SprintController.
-- It uses MovementRestrictionService so future jutsus can reuse the same system.

local HttpService =
	game:GetService("HttpService")

local ServerScriptService =
	game:GetService("ServerScriptService")

local MovementRestrictionService =
	require(
		ServerScriptService:
		WaitForChild(
			"MovementRestrictionService"
		)
	)

local FlameBreath = {}

---------------------------------------------------------------------
-- METADATA
---------------------------------------------------------------------

FlameBreath.Id =
	"FlameBreath"

FlameBreath.NatureId =
	"Fire"

FlameBreath.TechniqueCategory =
	"ElementalNinjutsu"

FlameBreath.MinimumLevel =
	1

FlameBreath.SortOrder =
	30

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

FlameBreath.Config = {
	DisplayName =
		"Flame Breath",

	NatureId =
		"Fire",

	TechniqueCategory =
		"ElementalNinjutsu",

	MinimumLevel =
		1,

	SortOrder =
		30,

	ChakraCost =
		18,

	Cooldown =
		6.0,

	CastTime =
		1.0,

	Damage =
		5,

	Breath = {
		Range =
			16,

		HalfAngleDegrees =
			32,

		Duration =
			1.0,

		TickInterval =
			0.16,
	},

	-----------------------------------------------------------------
	-- GENERIC MOVEMENT RESTRICTION
	--
	-- Future jutsus can use the same shape and call
	-- MovementRestrictionService.Apply().
	-----------------------------------------------------------------

	MovementRestriction = {
		Duration =
			1.5,

		BlockSprint =
			true,

		MaxWalkSpeed =
			16,
	},
}

---------------------------------------------------------------------
-- MARKERS
---------------------------------------------------------------------

FlameBreath.AllowedCastMarkers = {
	ReleaseStart =
		true,

	ProjectileSpawn =
		true,

	RecoveryStart =
		true,

	CastEnd =
		true,
}

FlameBreath.MarkerCastTimeout =
	8.0

FlameBreath.ProjectileFallbackDelay =
	6.0

FlameBreath.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- VFX
---------------------------------------------------------------------

local FLAME_BREATH_VFX_MODEL =
	"FlameBreath"

local FLAME_BREATH_VFX_NATURE =
	"Fire"

---------------------------------------------------------------------
-- MOUTH
---------------------------------------------------------------------

local MOUTH_DOWN_OFFSET_SCALE =
	0.13

local MOUTH_FORWARD_OFFSET =
	0.05

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
-- SAFE LOOK AT
---------------------------------------------------------------------

local function safeLookAt(
	position: Vector3,
	direction: Vector3
): CFrame

	local unit =
		if direction.Magnitude > 0.001
		then
		direction.Unit
		else
		Vector3.new(
			0,
			0,
			-1
		)

	local up =
		if math.abs(
			unit:
			Dot(
				Vector3.yAxis
			)
		) > 0.98
		then
		Vector3.xAxis
		else
		Vector3.yAxis

	return CFrame.lookAt(
		position,
		position + unit,
		up
	)
end

---------------------------------------------------------------------
-- MOUTH POSITION
---------------------------------------------------------------------

local function getMouthPosition(
	head: BasePart
): Vector3

	local mouthAttachment =
		head:
		FindFirstChild(
			"MouthAttachment"
		)

	if mouthAttachment
		and mouthAttachment:IsA(
			"Attachment"
		) then

		return mouthAttachment.WorldPosition
	end

	local faceFront =
		head:
		FindFirstChild(
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

	local faceCenter =
		head:
		FindFirstChild(
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

	return head.CFrame:
		PointToWorldSpace(
			Vector3.new(
				0,

				-head.Size.Y
				* MOUTH_DOWN_OFFSET_SCALE,

				-head.Size.Z
				* 0.50
			)
		)
end

---------------------------------------------------------------------
-- CHARACTER LOOK DIRECTION
---------------------------------------------------------------------

local function getCharacterLookDirection(
	root: BasePart
): Vector3

	local direction =
		root.CFrame.LookVector

	if direction.Magnitude <
		0.001 then

		return Vector3.new(
			0,
			0,
			-1
		)
	end

	return direction.Unit
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
		"Vector3"

		or not isFiniteNumber(
			rawDirection.X
		)

			or not isFiniteNumber(
				rawDirection.Y
			)

			or not isFiniteNumber(
				rawDirection.Z
			)

			or rawDirection.Magnitude <
			0.001 then

		return false,
			"InvalidDirection",
			nil
	end

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

	local direction =
		rawDirection.Unit

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
-- PUBLIC SANITIZE
---------------------------------------------------------------------

function FlameBreath.SanitizeRequest(
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
--
-- Retained for compatibility with marker-driven JutsuServer.
-- Gameplay direction itself follows HumanoidRootPart.LookVector.
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

	if ok
		and direction then

		context.RequestData.Direction =
			direction
	end
end

---------------------------------------------------------------------
-- CASTER
---------------------------------------------------------------------

local function getCasterParts(
	context: any
): (Humanoid?, BasePart?, BasePart?)

	local player: Player =
		context.Player

	local character: Model =
		context.Character

	if not player.Parent
		or player.Character ~= character
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

	if not humanoid
		or humanoid.Health <= 0 then

		return nil,
			nil,
			nil
	end

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

	if not head
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

	if character:
		GetAttribute(
			"IsDowned"
		) == true

			or character:
			GetAttribute(
				"IsCarried"
			) == true

			or character:
			GetAttribute(
				"Status_Stunned"
			) == true

			or character:
			GetAttribute(
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
-- GENERIC MOVEMENT RESTRICTION
---------------------------------------------------------------------

local function applyMovementRestriction(
	context: any
)

	-----------------------------------------------------------------
	-- Prevent duplicate application if the same cast reaches both
	-- marker and fallback paths.
	-----------------------------------------------------------------

	if context.__FlameBreathMovementRestrictionApplied ==
		true then

		return
	end

	context.__FlameBreathMovementRestrictionApplied =
		true

	local config =
		context.Config

	local restrictionConfig =
		if typeof(config) == "table"
		and typeof(
			config.MovementRestriction
		) == "table"
		then
		config.MovementRestriction
		else
		FlameBreath.Config.MovementRestriction

	local duration =
		if typeof(
			restrictionConfig.Duration
		) == "number"
		then
		math.max(
			0,
			restrictionConfig.Duration
		)
		else
		1.5

	local blockSprint =
		if typeof(
			restrictionConfig.BlockSprint
		) == "boolean"
		then
		restrictionConfig.BlockSprint
		else
		true

	local maxWalkSpeed: number? =
		nil

	if typeof(
		restrictionConfig.MaxWalkSpeed
		) == "number" then

		maxWalkSpeed =
			math.max(
				0,
				restrictionConfig.MaxWalkSpeed
			)
	end

	MovementRestrictionService.Apply(
		context.Character,
		{
			Source =
				"Jutsu:"
				.. FlameBreath.Id,

			Duration =
				duration,

			BlockSprint =
				blockSprint,

			MaxWalkSpeed =
				maxWalkSpeed,
		}
	)
end

---------------------------------------------------------------------
-- DAMAGEABLE ENTITY
---------------------------------------------------------------------

local function resolveDamageableEntity(
	context: any,
	instance: Instance?
): any?

	if not instance
		or not instance:IsA(
			"BasePart"
		) then

		return nil
	end

	local CombatEntityService =
		context.CombatEntityService

	local character: Model =
		context.Character

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
-- ENTITY POSITION
---------------------------------------------------------------------

local function getEntityPosition(
	entity: any,
	fallbackPart: BasePart
): Vector3

	local root =
		entity.Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if root
		and root:IsA(
			"BasePart"
		) then

		return root.Position
	end

	return fallbackPart.Position
end

---------------------------------------------------------------------
-- LINE OF SIGHT
---------------------------------------------------------------------

local function hasLineOfSight(
	context: any,
	origin: Vector3,
	targetCharacter: Model,
	targetPosition: Vector3
): boolean

	local displacement =
		targetPosition
	- origin

	if displacement.Magnitude <=
		0.05 then

		return true
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		context.Character,
	}

	params.IgnoreWater =
		false

	local result =
		workspace:
		Raycast(
			origin,
			displacement,
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

---------------------------------------------------------------------
-- ONE DAMAGE TICK
---------------------------------------------------------------------

local function executeDamageTick(
	context: any,
	origin: Vector3,
	direction: Vector3,
	range: number,
	halfAngleDegrees: number,
	overlapParams: OverlapParams
)

	local config =
		context.Config

	local coneThreshold =
		math.cos(
			math.rad(
				halfAngleDegrees
			)
		)

	local width =
		math.max(
			6,

			range
			* math.tan(
				math.rad(
					halfAngleDegrees
				)
			)
			* 2
		)

	local boxCenter =
		origin

		+ direction
		* (
			range
			* 0.5
		)

	local boxCFrame =
		safeLookAt(
			boxCenter,
			direction
		)

	local boxSize =
		Vector3.new(
			width,
			width,
			range
		)

	local seen:
		{[Model]: boolean} =
		{}

	for _, part in ipairs(
		workspace:
			GetPartBoundsInBox(
				boxCFrame,
				boxSize,
				overlapParams
			)
		) do

		local entity =
			resolveDamageableEntity(
				context,
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

			local targetPosition =
				getEntityPosition(
					entity,
					part
				)

			local toTarget =
				targetPosition
			- origin

			local distance =
				toTarget.Magnitude

			local insideCone =
				false

			if distance <=
				0.05 then

				insideCone =
					true

			elseif distance <=
				range then

				insideCone =
					direction:
					Dot(
						toTarget.Unit
					) >=
					coneThreshold
			end

			if insideCone
				and hasLineOfSight(
					context,
					origin,
					entity.Character,
					targetPosition
				) then

				context.DamageService.Apply({
					TargetCharacter =
						entity.Character,

					TargetHumanoid =
						entity.Humanoid,

					TargetPlayer =
						entity.Player,

					Attacker =
						context.Player,

					Damage =
						config.Damage,

					SourceType =
						"Jutsu",

					SourceId =
						FlameBreath.Id,

					Armor =
						config.Armor,
				})
			end
		end
	end
end

---------------------------------------------------------------------
-- EXECUTE BREATH
---------------------------------------------------------------------

local function executeBreath(
	context: any
)

	local _humanoid,
		head,
		root =
		getCasterParts(
			context
		)

	if not head
		or not root then

		return
	end

	local config =
		context.Config

	local breathConfig =
		if typeof(config) == "table"
		and typeof(
			config.Breath
		) == "table"
		then
		config.Breath
		else
		FlameBreath.Config.Breath

	-----------------------------------------------------------------
	-- RANGE
	-----------------------------------------------------------------

	local range =
		if typeof(
			breathConfig.Range
		) == "number"

		then
		math.max(
			4,
			breathConfig.Range
		)

		else
		16

	-----------------------------------------------------------------
	-- ANGLE
	-----------------------------------------------------------------

	local halfAngleDegrees =
		if typeof(
			breathConfig
			.HalfAngleDegrees
		) == "number"

		then
		math.clamp(
			breathConfig
			.HalfAngleDegrees,
			5,
			75
		)

		else
		32

	-----------------------------------------------------------------
	-- DURATION
	-----------------------------------------------------------------

	local duration =
		if typeof(
			breathConfig.Duration
		) == "number"

		then
		math.clamp(
			breathConfig.Duration,
			0.1,
			3
		)

		else
		1.0

	-----------------------------------------------------------------
	-- DAMAGE TICK
	-----------------------------------------------------------------

	local tickInterval =
		if typeof(
			breathConfig.TickInterval
		) == "number"

		then
		math.clamp(
			breathConfig.TickInterval,
			0.05,
			0.5
		)

		else
		0.16

	-----------------------------------------------------------------
	-- OVERLAP
	-----------------------------------------------------------------

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		context.Character,
	}

	-----------------------------------------------------------------
	-- EFFECT
	-----------------------------------------------------------------

	local effectId =
		HttpService:
		GenerateGUID(
			false
		)

	local vfxRemote: RemoteEvent =
		context.VFXRemote

	local vfxActive =
		true

	-----------------------------------------------------------------
	-- INITIAL FACING
	-----------------------------------------------------------------

	local initialDirection =
		getCharacterLookDirection(
			root
		)

	-----------------------------------------------------------------
	-- START VFX
	-----------------------------------------------------------------

	vfxRemote:
		FireAllClients(
			"FlameBreathStart",
			{
				JutsuId =
				FlameBreath.Id,

				VFXNature =
				FLAME_BREATH_VFX_NATURE,

				VFXModel =
				FLAME_BREATH_VFX_MODEL,

				EffectId =
				effectId,

				Caster =
				context.Character,

				Position =
				getMouthPosition(
					head
				),

				Direction =
				initialDirection,

				FollowCharacterLook =
				true,

				Duration =
				duration,
			}
		)

	-----------------------------------------------------------------
	-- STOP VFX
	-----------------------------------------------------------------

	local function stopVFX()

		if not vfxActive then
			return
		end

		vfxActive =
			false

		vfxRemote:
			FireAllClients(
				"FlameBreathStop",
				{
					JutsuId =
					FlameBreath.Id,

					VFXNature =
					FLAME_BREATH_VFX_NATURE,

					VFXModel =
					FLAME_BREATH_VFX_MODEL,

					EffectId =
					effectId,
				}
			)
	end

	-----------------------------------------------------------------
	-- GAMEPLAY LOOP
	-----------------------------------------------------------------

	task.spawn(
		function()

			local startedAt =
				workspace:
				GetServerTimeNow()

			local nextDamageTick =
				startedAt

			while true do

				local now =
					workspace:
					GetServerTimeNow()

				if now - startedAt >=
					duration then

					break
				end

				local _currentHumanoid,
				currentHead,
				currentRoot =
					getCasterParts(
						context
					)

				if not currentHead
					or not currentRoot then

					stopVFX()

					return
				end

				local currentDirection =
					getCharacterLookDirection(
						currentRoot
					)

				local origin =
					getMouthPosition(
						currentHead
					)

				if now >=
					nextDamageTick then

					executeDamageTick(
						context,
						origin,
						currentDirection,
						range,
						halfAngleDegrees,
						overlapParams
					)

					nextDamageTick +=
						tickInterval
				end

				task.wait(
					0.01
				)
			end

			stopVFX()
		end
	)
end

---------------------------------------------------------------------
-- CAST START
---------------------------------------------------------------------

function FlameBreath.OnCastStarted(
	_context: any
)

	-- Movement restriction starts on ProjectileSpawn,
	-- exactly when the breath starts firing.
end

---------------------------------------------------------------------
-- MARKERS
---------------------------------------------------------------------

function FlameBreath.OnCastMarker(
	context: any,
	semanticMarker: string,
	_source: string,
	markerPayload: any?
)

	if semanticMarker ==
		"ProjectileSpawn" then

		refreshReleaseAim(
			context,
			markerPayload
		)

		-----------------------------------------------------------------
		-- GENERIC MOVEMENT RESTRICTION
		--
		-- 1.5 seconds
		-- Sprint OFF
		-- WalkSpeed max 16
		-----------------------------------------------------------------

		applyMovementRestriction(
			context
		)

		-----------------------------------------------------------------
		-- FIRE
		-----------------------------------------------------------------

		executeBreath(
			context
		)
	end
end

---------------------------------------------------------------------
-- CAST END
---------------------------------------------------------------------

function FlameBreath.OnCastEnded(
	_context: any,
	_reason: string
)

	-- The generic movement restriction owns its own timer.
	-- It intentionally survives CastEnd until 1.5 seconds expire.
end

---------------------------------------------------------------------
-- LEGACY FALLBACK
---------------------------------------------------------------------

function FlameBreath.Execute(
	context: any
)

	task.delay(
		context.Config.CastTime,

		function()

			applyMovementRestriction(
				context
			)

			executeBreath(
				context
			)
		end
	)
end

return FlameBreath
