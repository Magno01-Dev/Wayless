--!strict
-- ServerScriptService > JutsuSystem > Jutsus > LightningBolt
--
-- WAYLESS Raiton bulk gameplay pass v1.
-- Fast mid-range lightning discharge.
-- Server-authoritative hitscan with a forgiving spherecast radius.
-- Placeholder VFX only.


local Debris = game:GetService("Debris")

local function isFiniteNumber(value: number): boolean
	return value == value
		and value ~= math.huge
		and value ~= -math.huge
end

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
		character:FindFirstChild("Head")

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

local function damageEntity(
	context: any,
	entity: any,
	sourceId: string,
	damage: number
)
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
			damage,

		SourceType =
			"Jutsu",

		SourceId =
			sourceId,

		Armor =
			context.Config.Armor,
	})
end


local LightningBolt = {}

LightningBolt.Id = "LightningBolt"
LightningBolt.NatureId = "Lightning"
LightningBolt.TechniqueCategory = "ElementalNinjutsu"
LightningBolt.MinimumLevel = 1
LightningBolt.SortOrder = 310

LightningBolt.Config = {
	DisplayName = "Lightning Bolt",
	NatureId = "Lightning",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 310,

	ChakraCost = 14,
	Cooldown = 4.5,
	CastTime = 1.0,
	Damage = 15,

	Bolt = {
		Range = 62,
		Radius = 1.35,
	},
}

LightningBolt.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

LightningBolt.MarkerCastTimeout = 8.0
LightningBolt.ProjectileFallbackDelay = 6.0
LightningBolt.MinProjectileDelay = 0.80

function LightningBolt.SanitizeRequest(
	character: Model,
	payload: any
): (boolean, string, any?)

	local ok, reason, direction =
		sanitizeDirection(
			character,
			payload
		)

	if not ok or not direction then
		return false, reason, nil
	end

	return true, "OK", {
		Direction = direction,
	}
end

local function spawnBoltPlaceholder(origin: Vector3, endPosition: Vector3)
    local visual = require(script:WaitForChild("LightningBoltVFX"))
    visual.Play(origin, endPosition)
end

local function executeBolt(
	context: any
)
	local head, root =
		getAliveHeadRoot(
			context
		)

	if not head or not root then
		return
	end

	local boltConfig =
		context.Config.Bolt or {}

	local range =
		if typeof(boltConfig.Range) == "number"
		then math.max(8, boltConfig.Range)
		else 62

	local radius =
		if typeof(boltConfig.Radius) == "number"
		then math.max(0.2, boltConfig.Radius)
		else 1.35

	local direction =
		context.RequestData.Direction

	if typeof(direction) ~= "Vector3"
		or direction.Magnitude < 0.001 then

		direction =
			root.CFrame.LookVector
	end

	direction = direction.Unit

	local origin =
		head.Position
		+ direction * 1.6

	local ignored: {Instance} = {
		context.Character,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater = false

	local endPosition =
		origin + direction * range

	for _ = 1, 12 do
		params.FilterDescendantsInstances =
			ignored

		local result =
			workspace:Spherecast(
				origin,
				radius,
				direction * range,
				params
			)

		if not result then
			break
		end

		endPosition =
			result.Position

		local entity =
			resolveDamageableEntity(
				context,
				result.Instance
			)

		if entity then
			damageEntity(
				context,
				entity,
				LightningBolt.Id,
				context.Config.Damage
			)

			break
		end

		if result.Instance:GetAttribute(
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
			break
		end
	end

	spawnBoltPlaceholder(
		origin,
		endPosition
	)
end

function LightningBolt.OnCastStarted(
	_context: any
)
end

function LightningBolt.OnCastMarker(
	context: any,
	semanticMarker: string,
	_source: string,
	markerPayload: any?
)
	if semanticMarker == "ProjectileSpawn" then
		refreshReleaseAim(
			context,
			markerPayload
		)

		executeBolt(
			context
		)
	end
end

function LightningBolt.OnCastEnded(
	_context: any,
	_reason: string
)
end

function LightningBolt.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeBolt(
				context
			)
		end
	)
end

return LightningBolt
