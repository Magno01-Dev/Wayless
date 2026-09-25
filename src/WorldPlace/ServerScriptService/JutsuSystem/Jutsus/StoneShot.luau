--!strict
-- ServerScriptService > JutsuSystem > Jutsus > StoneShot
--
-- WAYLESS Doton bulk gameplay pass v1.
-- Medium-speed rock projectile. Moderate damage + Earth/Heavy.
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

local function horizontalDirection(
	root: BasePart,
	rawDirection: any
): Vector3

	if typeof(rawDirection) == "Vector3" then
		local flat =
			Vector3.new(
				rawDirection.X,
				0,
				rawDirection.Z
			)

		if flat.Magnitude > 0.001 then
			return flat.Unit
		end
	end

	local look =
		Vector3.new(
			root.CFrame.LookVector.X,
			0,
			root.CFrame.LookVector.Z
		)

	if look.Magnitude > 0.001 then
		return look.Unit
	end

	return Vector3.new(0, 0, -1)
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


local StoneShot = {}

StoneShot.Id = "StoneShot"
StoneShot.NatureId = "Earth"
StoneShot.TechniqueCategory = "ElementalNinjutsu"
StoneShot.MinimumLevel = 1
StoneShot.SortOrder = 410

StoneShot.Config = {
	DisplayName = "Stone Shot",
	NatureId = "Earth",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 410,

	ChakraCost = 15,
	Cooldown = 5.0,
	CastTime = 1.0,
	Damage = 18,

	Projectile = {
		Speed = 72,
		MaxDistance = 64,
		Radius = 1.75,
	},
}

StoneShot.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

StoneShot.MarkerCastTimeout = 8.0
StoneShot.ProjectileFallbackDelay = 6.0
StoneShot.MinProjectileDelay = 0.80

function StoneShot.SanitizeRequest(
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

local StoneShotVFX = require(script:WaitForChild("StoneShotVFX"))
local function makeRockVisual(position: Vector3, radius: number, owner: Player?): BasePart
    return StoneShotVFX.Create(position, radius, owner)
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
		else 72

	local maxDistance =
		if typeof(projectileConfig.MaxDistance) == "number"
		then math.max(10, projectileConfig.MaxDistance)
		else 64

	local radius =
		if typeof(projectileConfig.Radius) == "number"
		then math.max(0.4, projectileConfig.Radius)
		else 1.75

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
		+ direction * 2.2

	local visual =
		makeRockVisual(
			position,
			radius,
			context.Player
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
						damageEntity(
							context,
							entity,
							StoneShot.Id,
							context.Config.Damage
						)

						finish()
						task.defer(StoneShotVFX.Impact, result.Position, result.Normal, radius)
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
						finish()
						task.defer(StoneShotVFX.Impact, result.Position, result.Normal, radius)
						return
					end
				end

				position += displacement
				travelled += step

				if visual.Parent then
					StoneShotVFX.Move(
						visual,
						CFrame.new(position)
						* CFrame.Angles(
							travelled * 0.08,
							travelled * 0.05,
							0
						)
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

function StoneShot.OnCastStarted(
	_context: any
)
end

function StoneShot.OnCastMarker(
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

function StoneShot.OnCastEnded(
	_context: any,
	_reason: string
)
end

function StoneShot.Execute(
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

return StoneShot
