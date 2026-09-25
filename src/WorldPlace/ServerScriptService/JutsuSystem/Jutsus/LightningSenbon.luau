--!strict
-- ServerScriptService > JutsuSystem > Jutsus > LightningSenbon
--
-- WAYLESS Raiton bulk gameplay pass v1.
-- Five fast precise electric needles with low individual damage.
-- Strong Charged application pressure through repeated hits.
-- Placeholder VFX only.

local RunService = game:GetService("RunService")

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


local LightningSenbon = {}

LightningSenbon.Id = "LightningSenbon"
LightningSenbon.NatureId = "Lightning"
LightningSenbon.TechniqueCategory = "ElementalNinjutsu"
LightningSenbon.MinimumLevel = 1
LightningSenbon.SortOrder = 340

LightningSenbon.Config = {
	DisplayName = "Lightning Senbon",
	NatureId = "Lightning",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 340,

	ChakraCost = 19,
	Cooldown = 6.0,
	CastTime = 1.0,
	Damage = 4,

	Senbon = {
		Count = 5,
		Speed = 145,
		MaxDistance = 72,
		Radius = 0.55,
		SpreadDegrees = 2.0,
		Interval = 0.045,
	},
}

LightningSenbon.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

LightningSenbon.MarkerCastTimeout = 8.0
LightningSenbon.ProjectileFallbackDelay = 6.0
LightningSenbon.MinProjectileDelay = 0.80

function LightningSenbon.SanitizeRequest(
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

local LightningSenbonVFX = require(script:WaitForChild("LightningSenbonVFX"))
local function makeSenbonVisual(position: Vector3, direction: Vector3): BasePart
    return LightningSenbonVFX.Create(position, direction)
end

local function launchNeedle(
	context: any,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	maxDistance: number,
	radius: number
)
	local position =
		origin

	local visual =
		makeSenbonVisual(
			position,
			direction
		)

	local ignored: {Instance} = {
		context.Character,
		visual,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater = false

	local travelled = 0.0
	local alive = true
	local connection: RBXScriptConnection?

	local function finish(hitPosition: Vector3?, hitNormal: Vector3?)
		if not alive then
			return
		end

		alive = false

		if connection then
			connection:Disconnect()
			connection = nil
		end

		if hitPosition and hitNormal then
			LightningSenbonVFX.Impact(hitPosition, hitNormal)
		end
		LightningSenbonVFX.Release(visual)
	end

	connection =
		RunService.Heartbeat:Connect(
			function(dt)
				if not alive then
					return
				end

				if not context.Player.Parent
					or context.Player.Character
					~= context.Character
					or not context.Character.Parent then

					finish()
					return
				end

				local step =
				math.min(
					speed * dt,
					maxDistance - travelled
				)

				if step <= 0 then
					finish()
					return
				end

				local displacement =
				direction * step

				for _ = 1, 10 do
					params.FilterDescendantsInstances =
					ignored

					local result =
					workspace:Spherecast(
						position,
						radius,
						displacement,
						params
					)

					if not result then
						break
					end

					local entity =
					resolveDamageableEntity(
						context,
						result.Instance
					)

					if entity then
						damageEntity(
							context,
							entity,
							LightningSenbon.Id,
							context.Config.Damage
						)

						finish(result.Position, result.Normal)
						return
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
						finish(result.Position, result.Normal)
						return
					end
				end

				position += displacement
				travelled += step

				if visual.Parent then
					visual.CFrame =
					safeLookAt(
						position,
						direction
					)
				end

				if travelled >= maxDistance then
					finish()
				end
			end
		)

	Debris:AddItem(
		visual,
		maxDistance / speed + 1
	)
end

local function executeSenbon(
	context: any
)
	local head, root =
		getAliveHeadRoot(
			context
		)

	if not head or not root then
		return
	end

	local senbonConfig =
		context.Config.Senbon or {}

	local count =
		if typeof(senbonConfig.Count) == "number"
		then math.clamp(
			math.floor(
				senbonConfig.Count
			),
			1,
			9
		)
		else 5

	local speed =
		if typeof(senbonConfig.Speed) == "number"
		then math.max(20, senbonConfig.Speed)
		else 145

	local maxDistance =
		if typeof(senbonConfig.MaxDistance) == "number"
		then math.max(10, senbonConfig.MaxDistance)
		else 72

	local radius =
		if typeof(senbonConfig.Radius) == "number"
		then math.max(0.15, senbonConfig.Radius)
		else 0.55

	local spreadDegrees =
		if typeof(senbonConfig.SpreadDegrees) == "number"
		then math.clamp(
			senbonConfig.SpreadDegrees,
			0,
			8
		)
		else 2.0

	local interval =
		if typeof(senbonConfig.Interval) == "number"
		then math.clamp(
			senbonConfig.Interval,
			0,
			0.15
		)
		else 0.045

	local baseDirection =
		context.RequestData.Direction

	if typeof(baseDirection) ~= "Vector3"
		or baseDirection.Magnitude < 0.001 then

		baseDirection =
			root.CFrame.LookVector
	end

	baseDirection =
		baseDirection.Unit

	local basis =
		safeLookAt(
			Vector3.zero,
			baseDirection
		)

	local right =
		basis.RightVector

	local centerIndex =
		(count + 1) * 0.5

	task.spawn(function()
		for index = 1, count do
			if not context.Player.Parent
				or context.Player.Character
				~= context.Character
				or not context.Character.Parent then

				return
			end

			local angleOffset =
				(index - centerIndex)
				* spreadDegrees

			local tangent =
				math.tan(
					math.rad(
						angleOffset
					)
				)

			local direction =
				(
					baseDirection
					+ right * tangent
				).Unit

			local currentHead =
				context.Character:
				FindFirstChild("Head")

			if not currentHead
				or not currentHead:IsA("BasePart") then

				return
			end

			local origin =
				currentHead.Position
				+ direction * 1.5

			launchNeedle(
				context,
				origin,
				direction,
				speed,
				maxDistance,
				radius
			)

			if index < count
				and interval > 0 then

				task.wait(
					interval
				)
			end
		end
	end)
end

function LightningSenbon.OnCastStarted(
	_context: any
)
end

function LightningSenbon.OnCastMarker(
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

		executeSenbon(
			context
		)
	end
end

function LightningSenbon.OnCastEnded(
	_context: any,
	_reason: string
)
end

function LightningSenbon.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeSenbon(
				context
			)
		end
	)
end

return LightningSenbon
