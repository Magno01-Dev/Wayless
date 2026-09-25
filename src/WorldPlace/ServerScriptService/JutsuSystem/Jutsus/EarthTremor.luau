--!strict
-- ServerScriptService > JutsuSystem > Jutsus > EarthTremor
--
-- WAYLESS Doton v6 GroundVFXAudioShake.
-- Small AoE centered on the caster.
-- Damage + Earth/Heavy + short stability-disrupting outward shove.
-- VFX uses the reusable client Static Cast contract.


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


local EarthTremor = {}

EarthTremor.Id = "EarthTremor"
EarthTremor.NatureId = "Earth"
EarthTremor.TechniqueCategory = "ElementalNinjutsu"
EarthTremor.MinimumLevel = 1
EarthTremor.SortOrder = 440

EarthTremor.Config = {
	DisplayName = "Earth Tremor",
	NatureId = "Earth",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 440,

	ChakraCost = 18,
	Cooldown = 6.5,
	CastTime = 1.0,
	Damage = 11,

	Tremor = {
		Radius = 12,
		PushSpeed = 38,
		PushDuration = 0.10,
		UpwardSpeed = 5,
	},
}

EarthTremor.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

EarthTremor.MarkerCastTimeout = 8.0
EarthTremor.ProjectileFallbackDelay = 6.0
EarthTremor.MinProjectileDelay = 0.80

function EarthTremor.SanitizeRequest(
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

local function applyShortPush(
	targetRoot: BasePart,
	direction: Vector3,
	speed: number,
	duration: number,
	upwardSpeed: number
)
	local existing =
		targetRoot:FindFirstChild(
			"EarthTremorLinearVelocity"
		)

	if existing then
		existing:Destroy()
	end

	local existingAttachment =
		targetRoot:FindFirstChild(
			"EarthTremorKnockbackAttachment"
		)

	if existingAttachment then
		existingAttachment:Destroy()
	end

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"EarthTremorKnockbackAttachment"

	attachment.Parent =
		targetRoot

	local velocity =
		Instance.new("LinearVelocity")

	velocity.Name =
		"EarthTremorLinearVelocity"

	velocity.Attachment0 =
		attachment

	velocity.RelativeTo =
		Enum.ActuatorRelativeTo.World

	velocity.VectorVelocity =
		direction * speed
		+ Vector3.new(
			0,
			upwardSpeed,
			0
		)

	velocity.MaxForce =
		1000000

	velocity.Parent =
		targetRoot

	task.delay(
		duration,
		function()
			if velocity.Parent then
				velocity:Destroy()
			end

			if attachment.Parent then
				attachment:Destroy()
			end
		end
	)

	Debris:AddItem(
		velocity,
		duration + 0.3
	)

	Debris:AddItem(
		attachment,
		duration + 0.3
	)
end

local EARTH_TREMOR_VFX_DURATION =
	1.0

local EARTH_TREMOR_SOUND_ID =
	"rbxassetid://117599116339619"

local EARTH_TREMOR_SOUND_VOLUME =
	1.15

local EARTH_TREMOR_SHAKE = {
	Magnitude = 0.38,
	Duration = 0.42,
	Radius = 50,
	RotationDegrees = 0.45,
	Roughness = 28,
}

local function getGroundCastPosition(
	context: any,
	root: BasePart
): Vector3

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		context.Character,
	}

	local result =
		workspace:Raycast(
			root.Position
			+ Vector3.new(
				0,
				3,
				0
			),
			Vector3.new(
				0,
				-12,
				0
			),
			params
		)

	if result then
		return result.Position
	end

	return root.Position
	- Vector3.new(
		0,
		root.Size.Y * 0.5 + 2.5,
		0
	)
end

local function playTremorCastVFX(
	context: any,
	root: BasePart
)
	local vfxRemote: RemoteEvent =
		context.VFXRemote

	local groundPosition =
		getGroundCastPosition(
			context,
			root
		)

	local direction =
		horizontalDirection(
			root,
			context.RequestData.Direction
		)

	local effectId =
		if typeof(context.CastToken) == "string"
		then context.CastToken
		else tostring(
			workspace:GetServerTimeNow()
		)

	vfxRemote:FireAllClients(
		"Cast",
		{
			CastMode =
				"Static",

			JutsuId =
				EarthTremor.Id,

			VFXNature =
				"Earth",

			VFXModel =
				"EarthTremor",

			VFXAnchor =
				"Ground",

			Position =
				groundPosition,

			Direction =
				direction,

			Duration =
				EARTH_TREMOR_VFX_DURATION,

			SoundId =
				EARTH_TREMOR_SOUND_ID,

			SoundVolume =
				EARTH_TREMOR_SOUND_VOLUME,

			SoundMinDistance =
				8,

			SoundMaxDistance =
				85,

			ScreenShake =
				EARTH_TREMOR_SHAKE,

			EffectId =
				effectId,
		}
	)

	print(
		"[EarthTremor v6] CAST VFX",
		"ReplicatedStorage.VFX.Jutsus.Earth.EarthTremor"
	)
end

local function executeTremor(
	context: any
)
	local _head, root =
		getAliveHeadRoot(context)

	if not root then
		return
	end

	local tremorConfig =
		context.Config.Tremor or {}

	local radius =
		if typeof(tremorConfig.Radius) == "number"
		then math.max(4, tremorConfig.Radius)
		else 12

	local pushSpeed =
		if typeof(tremorConfig.PushSpeed) == "number"
		then math.max(0, tremorConfig.PushSpeed)
		else 38

	local pushDuration =
		if typeof(tremorConfig.PushDuration) == "number"
		then math.clamp(
			tremorConfig.PushDuration,
			0.05,
			0.25
		)
		else 0.10

	local upwardSpeed =
		if typeof(tremorConfig.UpwardSpeed) == "number"
		then math.max(0, tremorConfig.UpwardSpeed)
		else 5

	local origin =
		root.Position

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

			local flat =
				Vector3.new(
					targetPosition.X - origin.X,
					0,
					targetPosition.Z - origin.Z
				)

			if flat.Magnitude <= radius then
				damageEntity(
					context,
					entity,
					EarthTremor.Id,
					context.Config.Damage
				)

				if targetRoot
					and targetRoot:IsA("BasePart")
					and flat.Magnitude > 0.001 then

					applyShortPush(
						targetRoot,
						flat.Unit,
						pushSpeed,
						pushDuration,
						upwardSpeed
					)
				end
			end
		end
	end

	playTremorCastVFX(
		context,
		root
	)
end

function EarthTremor.OnCastStarted(
	_context: any
)
end

function EarthTremor.OnCastMarker(
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

		executeTremor(
			context
		)
	end
end

function EarthTremor.OnCastEnded(
	_context: any,
	_reason: string
)
end

function EarthTremor.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeTremor(
				context
			)
		end
	)
end

return EarthTremor
