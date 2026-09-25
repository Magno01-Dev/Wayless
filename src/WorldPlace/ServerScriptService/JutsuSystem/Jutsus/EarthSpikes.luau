--!strict
-- ServerScriptService > JutsuSystem > Jutsus > EarthSpikes
--
-- WAYLESS Doton bulk gameplay pass v1.
-- Short frontal sequence of ground eruptions.
-- Each character can be damaged once per cast.
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


local EarthSpikes = {}

EarthSpikes.Id = "EarthSpikes"
EarthSpikes.NatureId = "Earth"
EarthSpikes.TechniqueCategory = "ElementalNinjutsu"
EarthSpikes.MinimumLevel = 1
EarthSpikes.SortOrder = 430

EarthSpikes.Config = {
	DisplayName = "Earth Spikes",
	NatureId = "Earth",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 430,

	ChakraCost = 19,
	Cooldown = 6.5,
	CastTime = 1.0,
	Damage = 14,

	Spikes = {
		StartDistance = 5,
		Count = 4,
		Spacing = 4.5,
		Radius = 3.4,
		Height = 6,
		Interval = 0.08,
		GroundProbeHeight = 7,
		GroundProbeDepth = 16,
	},
}

EarthSpikes.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

EarthSpikes.MarkerCastTimeout = 8.0
EarthSpikes.ProjectileFallbackDelay = 6.0
EarthSpikes.MinProjectileDelay = 0.80

function EarthSpikes.SanitizeRequest(
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

local function spawnSpikePlaceholder(
	groundPosition: Vector3,
	height: number
)
	local part =
		Instance.new("Part")

	part.Name =
		"EarthSpikes_Placeholder"

	part.Size =
		Vector3.new(
			2.2,
			height,
			2.2
		)

	part.CFrame =
		CFrame.new(
			groundPosition
			+ Vector3.new(
				0,
				height * 0.5,
				0
			)
		)
		* CFrame.Angles(
			math.rad(-6),
			math.rad(math.random(-12, 12)),
			math.rad(5)
		)

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Slate
	part.Color =
		Color3.fromRGB(
			105,
			82,
			58
		)
	part.CastShadow = true
	part.Parent = workspace

	Debris:AddItem(
		part,
		0.55
	)
end

local function executeSpikes(
	context: any
)
	local _head, root =
		getAliveHeadRoot(context)

	if not root then
		return
	end

	local spikeConfig =
		context.Config.Spikes or {}

	local startDistance =
		if typeof(spikeConfig.StartDistance) == "number"
		then math.max(2, spikeConfig.StartDistance)
		else 5

	local count =
		if typeof(spikeConfig.Count) == "number"
		then math.clamp(
			math.floor(spikeConfig.Count),
			1,
			8
		)
		else 4

	local spacing =
		if typeof(spikeConfig.Spacing) == "number"
		then math.max(2, spikeConfig.Spacing)
		else 4.5

	local radius =
		if typeof(spikeConfig.Radius) == "number"
		then math.max(1.5, spikeConfig.Radius)
		else 3.4

	local height =
		if typeof(spikeConfig.Height) == "number"
		then math.max(2, spikeConfig.Height)
		else 6

	local interval =
		if typeof(spikeConfig.Interval) == "number"
		then math.clamp(
			spikeConfig.Interval,
			0.03,
			0.25
		)
		else 0.08

	local probeHeight =
		if typeof(spikeConfig.GroundProbeHeight) == "number"
		then math.max(2, spikeConfig.GroundProbeHeight)
		else 7

	local probeDepth =
		if typeof(spikeConfig.GroundProbeDepth) == "number"
		then math.max(6, spikeConfig.GroundProbeDepth)
		else 16

	local direction =
		horizontalDirection(
			root,
			context.RequestData.Direction
		)

	local baseOrigin =
		root.Position

	local rayParams =
		RaycastParams.new()

	rayParams.FilterType =
		Enum.RaycastFilterType.Exclude

	rayParams.FilterDescendantsInstances = {
		context.Character,
	}

	rayParams.IgnoreWater = false

	local hitCharacters:
		{[Model]: boolean} =
		{}

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		context.Character,
	}

	task.spawn(function()
		for index = 1, count do
			if not context.Player.Parent
				or context.Player.Character
				~= context.Character
				or not context.Character.Parent then

				return
			end

			local distance =
				startDistance
				+ (index - 1) * spacing

			local desired =
				baseOrigin
				+ direction * distance

			local result =
				workspace:Raycast(
					desired
					+ Vector3.new(
						0,
						probeHeight,
						0
					),
					Vector3.new(
						0,
						-probeDepth,
						0
					),
					rayParams
				)

			if result then
				local groundPosition =
					result.Position

				spawnSpikePlaceholder(
					groundPosition,
					height
				)

				local hitCenter =
					groundPosition
					+ Vector3.new(
						0,
						height * 0.45,
						0
					)

				for _, part in ipairs(
					workspace:GetPartBoundsInRadius(
						hitCenter,
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
						and not hitCharacters[
						entity.Character
						] then

						hitCharacters[
						entity.Character
						] = true

						damageEntity(
							context,
							entity,
							EarthSpikes.Id,
							context.Config.Damage
						)

						local targetRoot =
							entity.Character:
							FindFirstChild(
								"HumanoidRootPart"
							)

						if targetRoot
							and targetRoot:IsA("BasePart") then

							targetRoot.AssemblyLinearVelocity =
								targetRoot.AssemblyLinearVelocity
								+ Vector3.new(
									0,
									18,
									0
								)
						end
					end
				end
			end

			if index < count then
				task.wait(
					interval
				)
			end
		end
	end)
end

function EarthSpikes.OnCastStarted(
	_context: any
)
end

function EarthSpikes.OnCastMarker(
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

		executeSpikes(
			context
		)
	end
end

function EarthSpikes.OnCastEnded(
	_context: any,
	_reason: string
)
end

function EarthSpikes.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeSpikes(
				context
			)
		end
	)
end

return EarthSpikes
