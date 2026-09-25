--!strict
-- ServerScriptService > JutsuSystem > Jutsus > StaticBurst
--
-- WAYLESS Raiton bulk gameplay pass v1.
-- Short electric anti-melee burst around the caster.
-- AoE damage + small interruption knockback.
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


local StaticBurst = {}

StaticBurst.Id = "StaticBurst"
StaticBurst.NatureId = "Lightning"
StaticBurst.TechniqueCategory = "ElementalNinjutsu"
StaticBurst.MinimumLevel = 1
StaticBurst.SortOrder = 330

StaticBurst.Config = {
	DisplayName = "Static Burst",
	NatureId = "Lightning",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 330,

	ChakraCost = 18,
	Cooldown = 6.5,
	CastTime = 1.0,
	Damage = 12,

	Burst = {
		Radius = 11,
		PushSpeed = 42,
		PushDuration = 0.10,
		UpwardSpeed = 4,
	},
}

StaticBurst.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

StaticBurst.MarkerCastTimeout = 8.0
StaticBurst.ProjectileFallbackDelay = 6.0
StaticBurst.MinProjectileDelay = 0.80

function StaticBurst.SanitizeRequest(
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

local function applyBurstPush(
	targetRoot: BasePart,
	direction: Vector3,
	pushSpeed: number,
	pushDuration: number,
	upwardSpeed: number
)
	local existing =
		targetRoot:FindFirstChild(
			"StaticBurstLinearVelocity"
		)

	if existing then
		existing:Destroy()
	end

	local existingAttachment =
		targetRoot:FindFirstChild(
			"StaticBurstKnockbackAttachment"
		)

	if existingAttachment then
		existingAttachment:Destroy()
	end

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"StaticBurstKnockbackAttachment"

	attachment.Parent =
		targetRoot

	local linearVelocity =
		Instance.new("LinearVelocity")

	linearVelocity.Name =
		"StaticBurstLinearVelocity"

	linearVelocity.Attachment0 =
		attachment

	linearVelocity.RelativeTo =
		Enum.ActuatorRelativeTo.World

	linearVelocity.VectorVelocity =
		direction * pushSpeed
		+ Vector3.new(
			0,
			upwardSpeed,
			0
		)

	linearVelocity.MaxForce =
		1000000

	linearVelocity.Parent =
		targetRoot

	task.delay(
		pushDuration,
		function()
			if linearVelocity.Parent then
				linearVelocity:Destroy()
			end

			if attachment.Parent then
				attachment:Destroy()
			end
		end
	)

	Debris:AddItem(
		linearVelocity,
		pushDuration + 0.35
	)

	Debris:AddItem(
		attachment,
		pushDuration + 0.35
	)
end

local function spawnBurstPlaceholder(position: Vector3, radius: number)
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("WaylessStaticBurstVFX")
    if remote and remote:IsA("RemoteEvent") then
        remote:FireAllClients(position, radius)
    end
end

local function executeBurst(
	context: any
)
	local _head, root =
		getAliveHeadRoot(
			context
		)

	if not root then
		return
	end

	local burstConfig =
		context.Config.Burst or {}

	local radius =
		if typeof(burstConfig.Radius) == "number"
		then math.max(3, burstConfig.Radius)
		else 11

	local pushSpeed =
		if typeof(burstConfig.PushSpeed) == "number"
		then math.max(0, burstConfig.PushSpeed)
		else 42

	local pushDuration =
		if typeof(burstConfig.PushDuration) == "number"
		then math.clamp(
			burstConfig.PushDuration,
			0.05,
			0.25
		)
		else 0.10

	local upwardSpeed =
		if typeof(burstConfig.UpwardSpeed) == "number"
		then math.max(0, burstConfig.UpwardSpeed)
		else 4

	local origin =
		root.Position
		+ Vector3.new(
			0,
			1.5,
			0
		)

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		context.Character,
	}

	local seen:
		{[Model]: boolean} =
		{}

	for _, part in ipairs(
		workspace:GetPartBoundsInRadius(
			origin,
			radius,
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
			] = true

			local targetRoot =
				entity.Character:
				FindFirstChild(
					"HumanoidRootPart"
				)

			local targetPosition =
				if targetRoot
				and targetRoot:IsA("BasePart")
				then targetRoot.Position
				else part.Position

			local displacement =
				targetPosition - origin

			if displacement.Magnitude <= radius then
				local rayParams =
					RaycastParams.new()

				rayParams.FilterType =
					Enum.RaycastFilterType.Exclude

				rayParams.FilterDescendantsInstances = {
					context.Character,
				}

				local result =
					workspace:Raycast(
						origin,
						displacement,
						rayParams
					)

				local hasLOS =
					not result
					or result.Instance:
					IsDescendantOf(
						entity.Character
					)

				if hasLOS then
					damageEntity(
						context,
						entity,
						StaticBurst.Id,
						context.Config.Damage
					)

					if targetRoot
						and targetRoot:IsA("BasePart") then

						local horizontal =
							Vector3.new(
								displacement.X,
								0,
								displacement.Z
							)

						if horizontal.Magnitude > 0.001 then
							applyBurstPush(
								targetRoot,
								horizontal.Unit,
								pushSpeed,
								pushDuration,
								upwardSpeed
							)
						end
					end
				end
			end
		end
	end

	spawnBurstPlaceholder(
		origin,
		radius
	)
end

function StaticBurst.OnCastStarted(
	_context: any
)
end

function StaticBurst.OnCastMarker(
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

		executeBurst(
			context
		)
	end
end

function StaticBurst.OnCastEnded(
	_context: any,
	_reason: string
)
end

function StaticBurst.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeBurst(
				context
			)
		end
	)
end

return StaticBurst
