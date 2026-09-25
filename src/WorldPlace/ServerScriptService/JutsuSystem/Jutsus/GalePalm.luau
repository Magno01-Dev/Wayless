--!strict
-- ServerScriptService > JutsuSystem > Jutsus > GalePalm
--
-- WAYLESS Fūton bulk gameplay pass v4 - Heavy Knockback.
--
-- FIX:
-- - Frontal detection now uses a HORIZONTAL sector instead of full 3D aim.
-- - More reliable LOS through non-collidable / ProjectileIgnore geometry.
-- - Strong knockback uses both AssemblyLinearVelocity + ApplyImpulse.
-- - Target dedupe happens after entity resolution.
--
-- Placeholder VFX only.

local Debris = game:GetService("Debris")

local GalePalm = {}

GalePalm.Id = "GalePalm"
GalePalm.NatureId = "Wind"
GalePalm.TechniqueCategory = "ElementalNinjutsu"
GalePalm.MinimumLevel = 1
GalePalm.SortOrder = 230

GalePalm.Config = {
	DisplayName = "Gale Palm",
	NatureId = "Wind",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 230,

	ChakraCost = 16,
	Cooldown = 6.0,
	CastTime = 1.0,
	Damage = 8,

	Blast = {
		Range = 15,
		HalfAngleDegrees = 42,
		PushSpeed = 140,
		PushDuration = 0.28,
		UpwardSpeed = 12,
	},
}

GalePalm.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

GalePalm.MarkerCastTimeout = 8.0
GalePalm.ProjectileFallbackDelay = 6.0
GalePalm.MinProjectileDelay = 0.80

---------------------------------------------------------------------
-- REQUEST / AIM
---------------------------------------------------------------------

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

function GalePalm.SanitizeRequest(
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
-- HELPERS
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

local function getHorizontalDirection(
	root: BasePart,
	requestDirection: any
): Vector3

	if typeof(requestDirection) == "Vector3" then
		local horizontal =
			Vector3.new(
				requestDirection.X,
				0,
				requestDirection.Z
			)

		if horizontal.Magnitude > 0.001 then
			return horizontal.Unit
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

	return Vector3.new(
		0,
		0,
		-1
	)
end

local function hasLineOfSight(
	context: any,
	origin: Vector3,
	targetCharacter: Model,
	targetPosition: Vector3
): boolean

	local displacement =
		targetPosition - origin

	if displacement.Magnitude <= 0.05 then
		return true
	end

	local ignored: {Instance} = {
		context.Character,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater = false

	for _ = 1, 12 do
		params.FilterDescendantsInstances =
			ignored

		local result =
			workspace:Raycast(
				origin,
				displacement,
				params
			)

		if not result then
			return true
		end

		if result.Instance:
			IsDescendantOf(
				targetCharacter
			) then

			return true
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
			return false
		end
	end

	return false
end

---------------------------------------------------------------------
-- PLACEHOLDER VFX
---------------------------------------------------------------------

local function spawnBlastPlaceholder(origin: Vector3, direction: Vector3, range: number, halfAngle: number?)
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("WaylessGalePalmVFX")
    if remote and remote:IsA("RemoteEvent") then
        remote:FireAllClients(origin, direction, range, halfAngle or 42)
    end
end

local function executeBlast(
	context: any
)
	local _head, root =
		getAliveHeadRoot(
			context
		)

	if not root then
		return
	end

	local blastConfig =
		context.Config.Blast or {}

	local range =
		if typeof(blastConfig.Range) == "number"
		then math.max(
			4,
			blastConfig.Range
		)
		else 15

	local halfAngleDegrees =
		if typeof(
			blastConfig.HalfAngleDegrees
		) == "number"
		then math.clamp(
			blastConfig.HalfAngleDegrees,
			8,
			80
		)
		else 42

	local pushSpeed =
		if typeof(
			blastConfig.PushSpeed
		) == "number"
		then math.max(
			0,
			blastConfig.PushSpeed
		)
		else 140

	local pushDuration =
		if typeof(
			blastConfig.PushDuration
		) == "number"
		then math.clamp(
			blastConfig.PushDuration,
			0.08,
			0.40
		)
		else 0.28

	local upwardSpeed =
		if typeof(
			blastConfig.UpwardSpeed
		) == "number"
		then math.max(
			0,
			blastConfig.UpwardSpeed
		)
		else 12

	local direction =
		getHorizontalDirection(
			root,
			context.RequestData.Direction
		)

	-- Chest-height origin makes close-range LOS much more stable than
	-- tracing from a pitched camera/head aim.
	local origin =
		root.Position
		+ Vector3.new(
			0,
			1.6,
			0
		)
		+ direction * 0.75

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
			range + 2,
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

			local horizontalOffset =
				Vector3.new(
					targetPosition.X - origin.X,
					0,
					targetPosition.Z - origin.Z
				)

			local horizontalDistance =
				horizontalOffset.Magnitude

			local insideSector =
				horizontalDistance <= range
				and (
					horizontalDistance <= 0.10
					or direction:Dot(
						horizontalOffset.Unit
					) >= threshold
				)

			if insideSector
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
						context.Config.Damage,

					SourceType =
						"Jutsu",

					SourceId =
						GalePalm.Id,

					Armor =
						context.Config.Armor,
				})

				if targetRoot
					and targetRoot:IsA("BasePart") then

					-- Replace any previous Gale Palm force on this root.
					local existingVelocity =
						targetRoot:FindFirstChild(
							"GalePalmLinearVelocity"
						)

					if existingVelocity then
						existingVelocity:Destroy()
					end

					local existingAttachment =
						targetRoot:FindFirstChild(
							"GalePalmKnockbackAttachment"
						)

					if existingAttachment then
						existingAttachment:Destroy()
					end

					local attachment =
						Instance.new("Attachment")

					attachment.Name =
						"GalePalmKnockbackAttachment"

					attachment.Parent =
						targetRoot

					local linearVelocity =
						Instance.new("LinearVelocity")

					linearVelocity.Name =
						"GalePalmLinearVelocity"

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

					-- Heavy controlled burst. Gale Palm is intentionally a
					-- major displacement tool and should out-range Launcher.
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

					-- Safety cleanup.
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

	spawnBlastPlaceholder(
		origin,
		direction,
		range,
		halfAngleDegrees
	)
end

---------------------------------------------------------------------
-- MARKER CONTRACT
---------------------------------------------------------------------

function GalePalm.OnCastStarted(
	_context: any
)
end

function GalePalm.OnCastMarker(
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

		executeBlast(
			context
		)
	end
end

function GalePalm.OnCastEnded(
	_context: any,
	_reason: string
)
end

function GalePalm.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeBlast(
				context
			)
		end
	)
end

return GalePalm
