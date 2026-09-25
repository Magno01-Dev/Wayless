--!strict
-- ServerScriptService > JutsuSystem > Jutsus > LightningStream
--
-- WAYLESS Raiton bulk gameplay pass v1.
-- Very brief maintained linear discharge.
-- Four rapid server-authoritative beam ticks.
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


local LightningStream = {}

LightningStream.Id = "LightningStream"
LightningStream.NatureId = "Lightning"
LightningStream.TechniqueCategory = "ElementalNinjutsu"
LightningStream.MinimumLevel = 1
LightningStream.SortOrder = 320

LightningStream.Config = {
	DisplayName = "Lightning Stream",
	NatureId = "Lightning",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 320,

	ChakraCost = 21,
	Cooldown = 7.0,
	CastTime = 1.0,
	Damage = 5,

	Stream = {
		Range = 34,
		Radius = 1.8,
		TickCount = 4,
		TickInterval = 0.12,
	},
}

LightningStream.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

LightningStream.MarkerCastTimeout = 8.0
LightningStream.ProjectileFallbackDelay = 6.0
LightningStream.MinProjectileDelay = 0.80

function LightningStream.SanitizeRequest(
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

local LightningStreamVFX = require(script:WaitForChild("LightningStreamVFX"))
local function spawnStreamPlaceholder(origin: Vector3, endPosition: Vector3, context: any)
    LightningStreamVFX.Pulse(context, origin, endPosition)
end

local function beamTick(
	context: any,
	origin: Vector3,
	direction: Vector3,
	range: number,
	radius: number
)
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
				LightningStream.Id,
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

	spawnStreamPlaceholder(
		origin,
		endPosition,
		context
	)
end

local function executeStream(
	context: any
)
	local head, root =
		getAliveHeadRoot(
			context
		)

	if not head or not root then
		return
	end

	local streamConfig =
		context.Config.Stream or {}

	local range =
		if typeof(streamConfig.Range) == "number"
		then math.max(6, streamConfig.Range)
		else 34

	local radius =
		if typeof(streamConfig.Radius) == "number"
		then math.max(0.25, streamConfig.Radius)
		else 1.8

	local tickCount =
		if typeof(streamConfig.TickCount) == "number"
		then math.clamp(
			math.floor(
				streamConfig.TickCount
			),
			1,
			8
		)
		else 4

	local tickInterval =
		if typeof(streamConfig.TickInterval) == "number"
		then math.clamp(
			streamConfig.TickInterval,
			0.05,
			0.30
		)
		else 0.12

	local direction =
		context.RequestData.Direction

	if typeof(direction) ~= "Vector3"
		or direction.Magnitude < 0.001 then

		direction =
			root.CFrame.LookVector
	end

	direction = direction.Unit

	task.spawn(function()
		for tickIndex = 1, tickCount do
			if not context.Player.Parent
				or context.Player.Character
				~= context.Character
				or not context.Character.Parent then

				return
			end

			local currentHead, currentRoot =
				getAliveHeadRoot(
					context
				)

			if not currentHead
				or not currentRoot then

				return
			end

			local origin =
				currentHead.Position
				+ direction * 1.4

			beamTick(
				context,
				origin,
				direction,
				range,
				radius
			)

			if tickIndex < tickCount then
				task.wait(
					tickInterval
				)
			end
		end
	end)
end

function LightningStream.OnCastStarted(
	_context: any
)
end

function LightningStream.OnCastMarker(
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

		executeStream(
			context
		)
	end
end

function LightningStream.OnCastEnded(
	_context: any,
	_reason: string
)
end

function LightningStream.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeStream(
				context
			)
		end
	)
end

return LightningStream
