--!strict
-- ServerScriptService > JutsuSystem > Jutsus > WindSweep
--
-- WAYLESS Fūton bulk gameplay pass v2 - Controlled Radial Knockback.
-- Very wide close-range frontal sweep for local space control.
-- Multi-target damage + outward displacement + Wind/Unsteady.
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


local WindSweep = {}

WindSweep.Id = "WindSweep"
WindSweep.NatureId = "Wind"
WindSweep.TechniqueCategory = "ElementalNinjutsu"
WindSweep.MinimumLevel = 1
WindSweep.SortOrder = 240

WindSweep.Config = {
	DisplayName = "Wind Sweep",
	NatureId = "Wind",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 240,

	ChakraCost = 18,
	Cooldown = 6.5,
	CastTime = 1.0,
	Damage = 10,

	Sweep = {
		Range = 13,
		HalfAngleDegrees = 70,
		PushSpeed = 110,
		PushDuration = 0.24,
		UpwardSpeed = 6,
	},
}

WindSweep.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

WindSweep.MarkerCastTimeout = 8.0
WindSweep.ProjectileFallbackDelay = 6.0
WindSweep.MinProjectileDelay = 0.80

function WindSweep.SanitizeRequest(
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

local function spawnSweepPlaceholder(origin: Vector3, direction: Vector3, range: number, halfAngle: number?)
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("WaylessWindSweepVFX")
    if remote and remote:IsA("RemoteEvent") then
        remote:FireAllClients(origin, direction, range, halfAngle or 70)
    end
end

local function executeSweep(
	context: any
)
	local _head, root =
		getAliveHeadRoot(context)

	if not root then
		return
	end

	local sweepConfig =
		context.Config.Sweep or {}

	local range =
		if typeof(sweepConfig.Range) == "number"
		then math.max(4, sweepConfig.Range)
		else 13

	local halfAngleDegrees =
		if typeof(sweepConfig.HalfAngleDegrees) == "number"
		then math.clamp(
			sweepConfig.HalfAngleDegrees,
			20,
			89
		)
		else 70

	local pushSpeed =
		if typeof(sweepConfig.PushSpeed) == "number"
		then math.max(0, sweepConfig.PushSpeed)
		else 110

	local pushDuration =
		if typeof(sweepConfig.PushDuration) == "number"
		then math.clamp(
			sweepConfig.PushDuration,
			0.08,
			0.40
		)
		else 0.24

	local upwardSpeed =
		if typeof(sweepConfig.UpwardSpeed) == "number"
		then math.max(
			0,
			sweepConfig.UpwardSpeed
		)
		else 6

	local rawDirection =
		context.RequestData.Direction

	local horizontal =
		if typeof(rawDirection) == "Vector3"
		then Vector3.new(
			rawDirection.X,
			0,
			rawDirection.Z
		)
		else Vector3.new(
			root.CFrame.LookVector.X,
			0,
			root.CFrame.LookVector.Z
		)

	if horizontal.Magnitude < 0.001 then
		horizontal =
			Vector3.new(
				root.CFrame.LookVector.X,
				0,
				root.CFrame.LookVector.Z
			)
	end

	if horizontal.Magnitude < 0.001 then
		horizontal =
			Vector3.new(0, 0, -1)
	end

	local direction =
		horizontal.Unit

	local origin =
		root.Position
		+ Vector3.new(
			0,
			1.5,
			0
		)

	local threshold =
		math.cos(
			math.rad(
				halfAngleDegrees
			)
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
			range,
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

			local toTarget =
				targetPosition - origin

			local horizontalTarget =
				Vector3.new(
					toTarget.X,
					0,
					toTarget.Z
				)

			if horizontalTarget.Magnitude > 0.05
				and direction:Dot(
					horizontalTarget.Unit
				) >= threshold then

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
						toTarget,
						rayParams
					)

				local hasLOS =
					not result
					or result.Instance:
					IsDescendantOf(
						entity.Character
					)

				if hasLOS then
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
							WindSweep.Id,

						Armor =
							context.Config.Armor,
					})

					if targetRoot
						and targetRoot:IsA("BasePart") then

						local outward =
							Vector3.new(
								toTarget.X,
								0,
								toTarget.Z
							)

						if outward.Magnitude > 0.001 then
							local pushDirection =
								outward.Unit

							local existingVelocity =
								targetRoot:FindFirstChild(
									"WindSweepLinearVelocity"
								)

							if existingVelocity then
								existingVelocity:Destroy()
							end

							local existingAttachment =
								targetRoot:FindFirstChild(
									"WindSweepKnockbackAttachment"
								)

							if existingAttachment then
								existingAttachment:Destroy()
							end

							local attachment =
								Instance.new("Attachment")

							attachment.Name =
								"WindSweepKnockbackAttachment"

							attachment.Parent =
								targetRoot

							local linearVelocity =
								Instance.new("LinearVelocity")

							linearVelocity.Name =
								"WindSweepLinearVelocity"

							linearVelocity.Attachment0 =
								attachment

							linearVelocity.RelativeTo =
								Enum.ActuatorRelativeTo.World

							linearVelocity.VectorVelocity =
								pushDirection * pushSpeed
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
					end
				end
			end
		end
	end

	spawnSweepPlaceholder(
		origin,
		direction,
		range,
		halfAngleDegrees
	)
end

function WindSweep.OnCastStarted(
	_context: any
)
end

function WindSweep.OnCastMarker(
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

		executeSweep(
			context
		)
	end
end

function WindSweep.OnCastEnded(
	_context: any,
	_reason: string
)
end

function WindSweep.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeSweep(
				context
			)
		end
	)
end

return WindSweep
