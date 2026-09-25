--!strict
-- ServerScriptService > JutsuSystem > Jutsus > AirBullet
--
-- WAYLESS Fūton bulk gameplay pass v1.
-- Very fast compressed-air projectile.
-- Low visual profile, moderate damage, Wind/Unsteady application.
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


local AirBullet = {}

AirBullet.Id = "AirBullet"
AirBullet.NatureId = "Wind"
AirBullet.TechniqueCategory = "ElementalNinjutsu"
AirBullet.MinimumLevel = 1
AirBullet.SortOrder = 210

AirBullet.Config = {
	DisplayName = "Air Bullet",
	NatureId = "Wind",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 210,

	ChakraCost = 13,
	Cooldown = 4.0,
	CastTime = 1.0,
	Damage = 13,

	Projectile = {
		Speed = 125,
		MaxDistance = 92,
		Radius = 1.15,
	},
}

AirBullet.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

AirBullet.MarkerCastTimeout = 8.0
AirBullet.ProjectileFallbackDelay = 6.0
AirBullet.MinProjectileDelay = 0.80

function AirBullet.SanitizeRequest(
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

local AirBulletVFX = require(script:WaitForChild("AirBulletVFX"))
local function makeProjectileVisual(position: Vector3, direction: Vector3, radius: number): BasePart
    return AirBulletVFX.Create(position, direction, radius)
end

local function executeProjectile(
	context: any
)
	local head, root =
		getAliveHeadRoot(context)

	if not head or not root then
		return
	end

	local projectileConfig =
		context.Config.Projectile or {}

	local speed =
		if typeof(projectileConfig.Speed) == "number"
		then math.max(10, projectileConfig.Speed)
		else 125

	local maxDistance =
		if typeof(projectileConfig.MaxDistance) == "number"
		then math.max(10, projectileConfig.MaxDistance)
		else 92

	local radius =
		if typeof(projectileConfig.Radius) == "number"
		then math.max(0.25, projectileConfig.Radius)
		else 1.15

	local direction =
		context.RequestData.Direction

	if typeof(direction) ~= "Vector3"
		or direction.Magnitude < 0.001 then

		direction =
			root.CFrame.LookVector
	end

	direction = direction.Unit

	local position =
		head.Position
		+ direction * 2.15

	local visual =
		makeProjectileVisual(
			position,
			direction,
			radius
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

	local function finish()
		if not alive then
			return
		end

		alive = false

		if connection then
			connection:Disconnect()
			connection = nil
		end

		if visual.Parent then
			visual:Destroy()
		end
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
							context.Config.Damage,

							SourceType =
							"Jutsu",

							SourceId =
							AirBullet.Id,

							Armor =
							context.Config.Armor,
						})

						AirBulletVFX.Impact(result.Position, result.Normal, radius)
						finish()
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
						AirBulletVFX.Impact(result.Position, result.Normal, radius)
						finish()
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

function AirBullet.OnCastStarted(
	_context: any
)
end

function AirBullet.OnCastMarker(
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

		executeProjectile(
			context
		)
	end
end

function AirBullet.OnCastEnded(
	_context: any,
	_reason: string
)
end

function AirBullet.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeProjectile(
				context
			)
		end
	)
end

return AirBullet
