--!strict
-- ServerScriptService > JutsuSystem > Jutsus > WindBlade
--
-- WAYLESS Fūton bulk gameplay pass v1.
-- Precise medium-range cutting projectile.
-- Can pierce several characters before stopping on solid world geometry.
-- Wind/Unsteady application through the normal elemental hook.
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


local WindBlade = {}

WindBlade.Id = "WindBlade"
WindBlade.NatureId = "Wind"
WindBlade.TechniqueCategory = "ElementalNinjutsu"
WindBlade.MinimumLevel = 1
WindBlade.SortOrder = 220

WindBlade.Config = {
	DisplayName = "Wind Blade",
	NatureId = "Wind",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 220,

	ChakraCost = 17,
	Cooldown = 5.5,
	CastTime = 1.0,
	Damage = 17,

	Projectile = {
		Speed = 105,
		MaxDistance = 72,
		Radius = 1.55,
		MaxTargets = 3,
	},
}

WindBlade.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

WindBlade.MarkerCastTimeout = 8.0
WindBlade.ProjectileFallbackDelay = 6.0
WindBlade.MinProjectileDelay = 0.80

function WindBlade.SanitizeRequest(
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

local WindBladeVFX = require(script:WaitForChild("WindBladeVFX"))
local function makeBladeVisual(position: Vector3, direction: Vector3): BasePart
    return WindBladeVFX.Create(position, direction)
end

local function executeBlade(
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
		else 105

	local maxDistance =
		if typeof(projectileConfig.MaxDistance) == "number"
		then math.max(10, projectileConfig.MaxDistance)
		else 72

	local radius =
		if typeof(projectileConfig.Radius) == "number"
		then math.max(0.35, projectileConfig.Radius)
		else 1.55

	local maxTargets =
		if typeof(projectileConfig.MaxTargets) == "number"
		then math.clamp(
			math.floor(
				projectileConfig.MaxTargets
			),
			1,
			8
		)
		else 3

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
		makeBladeVisual(
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

	local hitCharacters:
		{[Model]: boolean} =
		{}

	local hitCount = 0
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

				for _ = 1, 12 do
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
						if not hitCharacters[
							entity.Character
							] then

							hitCharacters[
							entity.Character
							] = true

							hitCount += 1
							WindBladeVFX.Impact(result.Position, direction, radius * 0.7)

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
								WindBlade.Id,

								Armor =
								context.Config.Armor,
							})
						end

						table.insert(
							ignored,
							entity.Character
						)

						if hitCount >= maxTargets then
							finish()
							return
						end

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
						WindBladeVFX.Impact(result.Position, result.Normal, radius)
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

function WindBlade.OnCastStarted(
	_context: any
)
end

function WindBlade.OnCastMarker(
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

		executeBlade(
			context
		)
	end
end

function WindBlade.OnCastEnded(
	_context: any,
	_reason: string
)
end

function WindBlade.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeBlade(
				context
			)
		end
	)
end

return WindBlade
