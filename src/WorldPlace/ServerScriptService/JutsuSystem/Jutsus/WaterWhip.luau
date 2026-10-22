--!strict
-- ServerScriptService > JutsuSystem > Jutsus > WaterWhip
--
-- WAYLESS Water Beam v5
--
-- IMPORTANT:
-- Internal Id remains "WaterWhip" for compatibility with the current
-- registry, hotbar, progression and ElementalCombatService.
--
-- Gameplay is no longer a whip.
-- The caster releases a concentrated stream of water from the mouth.
--
-- v5 HOTFIX:
-- - Removes invalid "local type" syntax that prevented this ModuleScript
--   from requiring, which made the technique disappear from the registry.
-- - Preserves the v4 mouth-follow / turn-follow behavior unchanged.
--
-- VFX:
-- ReplicatedStorage > VFX > Jutsus > Water > WaterBeam
-- WaterBeam > Root > Start
-- WaterBeam > Root > End

local Debris =
	game:GetService("Debris")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

---------------------------------------------------------------------
-- VFX
--
-- El servidor solo avisa (inicio y fin del chorro); cada cliente lo dibuja
-- desde la boca del lanzador siguiendo su giro, igual que la logica de abajo
-- (ReplicatedStorage > JutsuSystem > ElementalFX > Water).
---------------------------------------------------------------------

local ElementalFX = require(
	ReplicatedStorage
		:WaitForChild("JutsuSystem")
		:WaitForChild("Shared")
		:WaitForChild("ElementalFX")
)

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

local function safeLookAt(
	position: Vector3,
	direction: Vector3
): CFrame

	local unit =
		if direction.Magnitude > 0.001
		then direction.Unit
		else Vector3.new(0, 0, -1)

	local up =
		if math.abs(
			unit:Dot(Vector3.yAxis)
		) > 0.98
		then Vector3.xAxis
		else Vector3.yAxis

	return CFrame.lookAt(
		position,
		position + unit,
		up
	)
end

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local function sanitizeDirection(
	character: Model,
	payload: any
): (boolean, string, Vector3?)

	if typeof(payload) ~= "table" then
		return false, "InvalidPayload", nil
	end

	local rawDirection =
		payload.Direction

	if typeof(rawDirection) ~= "Vector3"
		or not isFiniteNumber(rawDirection.X)
		or not isFiniteNumber(rawDirection.Y)
		or not isFiniteNumber(rawDirection.Z)
		or rawDirection.Magnitude < 0.001 then

		return false, "InvalidDirection", nil
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA("BasePart") then

		return false, "NoRoot", nil
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

	if horizontalDirection.Magnitude > 0.001
		and horizontalLook.Magnitude > 0.001
		and horizontalLook.Unit:Dot(
			horizontalDirection.Unit
		) < -0.25 then

		return false, "AimBehindCharacter", nil
	end

	return true, "OK", direction
end

local function refreshReleaseAim(
	context: any,
	markerPayload: any?
)

	if typeof(markerPayload) ~= "table" then
		return
	end

	local ok, _reason, direction =
		sanitizeDirection(
			context.Character,
			markerPayload
		)

	if ok and direction then
		context.RequestData.Direction =
			direction
	end
end

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local function getAliveHeadRoot(
	context: any
): (BasePart?, BasePart?)

	local character: Model =
		context.Character

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return nil, nil
	end

	local head =
		character:FindFirstChild(
			"Head"
		)

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not head
		or not head:IsA("BasePart")
		or not root
		or not root:IsA("BasePart") then

		return nil, nil
	end

	return head, root
end

---------------------------------------------------------------------
-- COMBAT ENTITY
---------------------------------------------------------------------

local function resolveDamageableEntity(
	context: any,
	instance: Instance?
): any?

	if not instance
		or not instance:IsA("BasePart") then

		return nil
	end

	local entity =
		context.CombatEntityService
		.ResolveFromInstance(
			instance
		)

	if not entity
		or entity.Character == context.Character
		or not entity.CanReceiveDamage
		or not context.CombatEntityService
		.IsAlive(entity)
		or entity.Character:GetAttribute(
			"CombatImmune"
		) == true
			or entity.Character:GetAttribute(
				"IsMissionNPC"
			) == true then

		return nil
	end

	return entity
end

---------------------------------------------------------------------
-- FLAME-BREATH STYLE MOUTH FOLLOW
---------------------------------------------------------------------

local MOUTH_DOWN_OFFSET_SCALE =
	0.13

local MOUTH_FORWARD_OFFSET =
	0.05

local function getMouthPosition(
	head: BasePart
): Vector3

	-----------------------------------------------------------------
	-- CUSTOM MOUTH ATTACHMENT
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
	-- ROBLOX FACE FRONT
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
	-- ROBLOX FACE CENTER
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
	-- GENERIC R6/R15 FALLBACK
	-----------------------------------------------------------------

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

-- Keep the release-time vertical pitch, but continuously inherit the
-- character's CURRENT yaw while the beam is active.
--
-- This gives Water Beam the same "locked to the caster" feel as
-- Flame Breath: turning the character turns the technique instead of
-- leaving a frozen beam behind in world space.
local function getFollowingDirection(
	root: BasePart,
	releaseDirection: Vector3
): Vector3

	local horizontalLook =
		Vector3.new(
			root.CFrame.LookVector.X,
			0,
			root.CFrame.LookVector.Z
		)

	if horizontalLook.Magnitude < 0.001 then
		return releaseDirection.Unit
	end

	horizontalLook =
		horizontalLook.Unit

	local pitchY =
		math.clamp(
			releaseDirection.Unit.Y,
			-0.95,
			0.95
		)

	local horizontalScale =
		math.sqrt(
			math.max(
				0,
				1 - pitchY * pitchY
			)
		)

	local direction =
		horizontalLook
		* horizontalScale
		+ Vector3.new(
			0,
			pitchY,
			0
		)

	if direction.Magnitude < 0.001 then
		return horizontalLook
	end

	return direction.Unit
end

---------------------------------------------------------------------
-- WORLD OCCLUSION
---------------------------------------------------------------------

local function resolveWorldRange(
	context: any,
	origin: Vector3,
	direction: Vector3,
	range: number,
	padding: number
): number

	local ignored: {Instance} = {
		context.Character,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater =
		false

	for _ = 1, 16 do

		params.FilterDescendantsInstances =
			ignored

		local result =
			workspace:Raycast(
				origin,
				direction * range,
				params
			)

		if not result then
			return range
		end

		local entity =
			resolveDamageableEntity(
				context,
				result.Instance
			)

		if entity then

			table.insert(
				ignored,
				entity.Character
			)

		elseif result.Instance:GetAttribute(
			"ProjectileIgnore"
			) == true
				or (
					result.Instance:IsA("BasePart")
					and not result.Instance.CanCollide
				) then

			table.insert(
				ignored,
				result.Instance
			)

		else

			return math.clamp(
				result.Distance
				- padding,
				0,
				range
			)
		end
	end

	return range
end

---------------------------------------------------------------------
-- TARGET DETECTION
---------------------------------------------------------------------

local function findClosestBeamTarget(
	context: any,
	origin: Vector3,
	direction: Vector3,
	effectiveRange: number,
	radius: number
): any?

	if effectiveRange <= 0.05 then
		return nil
	end

	local center =
		origin
		+ direction
		* (
			effectiveRange
			* 0.5
		)

	local boxCFrame =
		safeLookAt(
			center,
			direction
		)

	local boxSize =
		Vector3.new(
			radius * 2,
			radius * 2,
			effectiveRange
		)

	local params =
		OverlapParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		context.Character,
	}

	local seen:
		{[Model]: boolean} =
		{}

	local bestEntity: any? =
		nil

	local bestProjection =
		math.huge

	for _, part in ipairs(
		workspace:GetPartBoundsInBox(
			boxCFrame,
			boxSize,
			params
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
			] = true

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
				then targetRoot.Position
				else part.Position

			local displacement =
				targetPosition
			- origin

			local projection =
				displacement:Dot(
					direction
				)

			local closestPoint =
				origin
				+ direction
				* projection

			local lateralDistance =
				(
					targetPosition
					- closestPoint
				).Magnitude

			if projection >= 0
				and projection <= effectiveRange
				and lateralDistance <= radius
				and projection < bestProjection then

				bestProjection =
					projection

				bestEntity =
					entity
			end
		end
	end

	return bestEntity
end

---------------------------------------------------------------------
-- KNOCKBACK
---------------------------------------------------------------------

local function pushTarget(
	entity: any,
	direction: Vector3,
	speed: number
)

	if speed <= 0 then
		return
	end

	local targetRoot =
		entity.Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not targetRoot
		or not targetRoot:IsA("BasePart") then

		return
	end

	local horizontal =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	if horizontal.Magnitude < 0.001 then
		return
	end

	targetRoot.AssemblyLinearVelocity =
		targetRoot.AssemblyLinearVelocity
		+ horizontal.Unit * speed
end

---------------------------------------------------------------------
-- JUTSU
---------------------------------------------------------------------

local WaterWhip = {}

WaterWhip.Id =
	"WaterWhip"

WaterWhip.NatureId =
	"Water"

WaterWhip.TechniqueCategory =
	"ElementalNinjutsu"

WaterWhip.MinimumLevel =
	1

WaterWhip.SortOrder =
	130

WaterWhip.Config = {

	DisplayName =
		"Water Beam",

	NatureId =
		"Water",

	TechniqueCategory =
		"ElementalNinjutsu",

	MinimumLevel =
		1,

	SortOrder =
		130,

	ChakraCost =
		16,

	Cooldown =
		5.5,

	CastTime =
		1.0,

	Damage =
		13,

	Beam = {

		-- Fireball-class engagement range.
		-- This is intentionally long enough to function as the Water
		-- counterpart in the future elemental jutsu-clash system.
		Range = 72,

		HitRadius = 2.25,

		PushSpeed = 7,

		-- Longer continuous visual presence so the water stream reads as
		-- an actual sustained technique instead of a brief laser flash.
		ActiveTime = 1.15,

		GrowTime = 0.10,

		-- Mouth placement now uses the exact Flame Breath attachment logic:
		-- MouthAttachment -> FaceFrontAttachment -> FaceCenterAttachment ->
		-- generic head fallback.
		MouthFollow = true,

		WorldImpactPadding = 0.15,

		VFXYawDegrees = 0,

		EndAxisSign = -1,

		-- Reserved metadata for the planned elemental clash system.
		-- Current gameplay does not consume this table yet.
		Clash = {
			Enabled = true,
			Element = "Water",
			Shape = "ContinuousBeam",
			Power = 1.0,
			Radius = 2.25,
		},
	},
}

WaterWhip.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

WaterWhip.MarkerCastTimeout =
	8.0

WaterWhip.ProjectileFallbackDelay =
	6.0

WaterWhip.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- REQUEST
---------------------------------------------------------------------

function WaterWhip.SanitizeRequest(
	character: Model,
	payload: any
): (boolean, string, any?)

	local ok, reason, direction =
		sanitizeDirection(
			character,
			payload
		)

	if not ok
		or not direction then

		return false, reason, nil
	end

	return true, "OK", {
		Direction = direction,
	}
end

---------------------------------------------------------------------
-- EXECUTION
---------------------------------------------------------------------

local function executeBeam(
	context: any
)

	local head, root =
		getAliveHeadRoot(
			context
		)

	if not head
		or not root then

		return
	end

	local beamConfig =
		context.Config.Beam
		or {}

	local range =
		if typeof(
			beamConfig.Range
		) == "number"
		then math.max(
			5,
			beamConfig.Range
		)
		else 72

	local hitRadius =
		if typeof(
			beamConfig.HitRadius
		) == "number"
		then math.max(
			0.5,
			beamConfig.HitRadius
		)
		else 2.25

	local pushSpeed =
		if typeof(
			beamConfig.PushSpeed
		) == "number"
		then math.max(
			0,
			beamConfig.PushSpeed
		)
		else 7

	local activeTime =
		if typeof(
			beamConfig.ActiveTime
		) == "number"
		then math.clamp(
			beamConfig.ActiveTime,
			0.10,
			2
		)
		else 1.15

	local growTime =
		if typeof(
			beamConfig.GrowTime
		) == "number"
		then math.clamp(
			beamConfig.GrowTime,
			0.01,
			activeTime
		)
		else 0.10

	local worldImpactPadding =
		if typeof(
			beamConfig.WorldImpactPadding
		) == "number"
		then math.max(
			0,
			beamConfig.WorldImpactPadding
		)
		else 0.15

	local vfxYawDegrees =
		if typeof(
			beamConfig.VFXYawDegrees
		) == "number"
		then beamConfig.VFXYawDegrees
		else 0

	local endAxisSign =
		if typeof(
			beamConfig.EndAxisSign
		) == "number"
		and beamConfig.EndAxisSign >= 0
		then 1
		else -1

	-----------------------------------------------------------------
	-- RELEASE AIM
	-----------------------------------------------------------------

	local releaseDirection =
		context.RequestData.Direction

	if typeof(releaseDirection)
		~= "Vector3"
		or releaseDirection.Magnitude
		< 0.001 then

		releaseDirection =
			root.CFrame.LookVector
	end

	releaseDirection =
		releaseDirection.Unit

	-----------------------------------------------------------------
	-- VISUAL
	-----------------------------------------------------------------

	-- Cada cliente dibuja el chorro con la misma lógica de boca, giro y alcance
	local fxId =
		ElementalFX.NewId()

	ElementalFX.Fire(WaterWhip.Id, "Start", {
		Id = fxId,
		Caster = context.Character,
		Direction = releaseDirection,
		Range = range,
		ActiveTime = activeTime,
		GrowTime = growTime,
		Padding = worldImpactPadding,
	})

	local _ = vfxYawDegrees + endAxisSign

	-----------------------------------------------------------------
	-- SUSTAINED BEAM
	--
	-- VFX + collision now use the SAME current mouth position,
	-- direction and world-clamped range every frame.
	-----------------------------------------------------------------

	task.spawn(function()

		local startedAt =
			time()

		local hitCharacters:
			{[Model]: boolean} =
			{}

		while true do

			local elapsed =
				time()
			- startedAt

			if elapsed >= activeTime then
				break
			end

			if not context.Player.Parent
				or context.Player.Character
				~= context.Character
				or not context.Character.Parent then

				break
			end

			local currentHead,
			currentRoot =
				getAliveHeadRoot(
					context
				)

			if not currentHead
				or not currentRoot then

				break
			end

			---------------------------------------------------------
			-- SAME FOLLOWING LOGIC AS FLAME BREATH
			---------------------------------------------------------

			local origin =
				getMouthPosition(
					currentHead
				)

			local direction =
				getFollowingDirection(
					currentRoot,
					releaseDirection
				)

			local effectiveRange =
				resolveWorldRange(
					context,
					origin,
					direction,
					range,
					worldImpactPadding
				)

			local lengthAlpha =
				math.clamp(
					elapsed
					/ math.max(
						growTime,
						0.01
					),
					0,
					1
				)

			local _ = lengthAlpha

			---------------------------------------------------------
			-- GAMEPLAY HITBOX FOLLOWS THE SAME MOVING BEAM
			---------------------------------------------------------

			if effectiveRange > 0.05 then

				local target =
					findClosestBeamTarget(
						context,
						origin,
						direction,
						effectiveRange,
						hitRadius
					)

				if target
					and not hitCharacters[
					target.Character
					] then

					hitCharacters[
					target.Character
					] = true

					context.DamageService.Apply({

						TargetCharacter =
							target.Character,

						TargetHumanoid =
							target.Humanoid,

						TargetPlayer =
							target.Player,

						Attacker =
							context.Player,

						Damage =
							context.Config.Damage,

						SourceType =
							"Jutsu",

						SourceId =
							WaterWhip.Id,

						Armor =
							context.Config.Armor,
					})

					pushTarget(
						target,
						direction,
						pushSpeed
					)
				end
			end

			RunService.Heartbeat:
				Wait()
		end

		ElementalFX.Fire(WaterWhip.Id, "End", {
			Id = fxId,
		})
	end)
end

---------------------------------------------------------------------
-- CAST CONTRACT
---------------------------------------------------------------------

function WaterWhip.OnCastStarted(
	_context: any
)
end

function WaterWhip.OnCastMarker(
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

		executeBeam(
			context
		)
	end
end

function WaterWhip.OnCastEnded(
	_context: any,
	_reason: string
)
end

---------------------------------------------------------------------
-- LEGACY FALLBACK
---------------------------------------------------------------------

function WaterWhip.Execute(
	context: any
)

	task.delay(
		context.Config.CastTime,
		function()

			executeBeam(
				context
			)
		end
	)
end

return WaterWhip
