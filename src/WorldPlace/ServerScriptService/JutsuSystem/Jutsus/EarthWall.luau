--!strict
-- ServerScriptService > JutsuSystem > Jutsus > EarthWall
--
-- WAYLESS Doton bulk gameplay pass v1.
-- Temporary physical defensive wall/blocker.
-- No damage in this prototype; the wall is real collision/query geometry.
-- Placeholder geometry only.


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


local EarthWall = {}

EarthWall.Id = "EarthWall"
EarthWall.NatureId = "Earth"
EarthWall.TechniqueCategory = "ElementalNinjutsu"
EarthWall.MinimumLevel = 1
EarthWall.SortOrder = 420

EarthWall.Config = {
	DisplayName = "Earth Wall",
	NatureId = "Earth",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 420,

	ChakraCost = 22,
	Cooldown = 9.0,
	CastTime = 1.0,

	Wall = {
		Distance = 7,
		Width = 14,
		Height = 9,
		Thickness = 2.5,
		Duration = 5.0,
		GroundProbeHeight = 8,
		GroundProbeDepth = 18,
	},
}

EarthWall.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

EarthWall.MarkerCastTimeout = 8.0
EarthWall.ProjectileFallbackDelay = 6.0
EarthWall.MinProjectileDelay = 0.80

function EarthWall.SanitizeRequest(
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

local function executeWall(
	context: any
)
	local _head, root =
		getAliveHeadRoot(context)

	if not root then
		return
	end

	local wallConfig =
		context.Config.Wall or {}

	local distance =
		if typeof(wallConfig.Distance) == "number"
		then math.max(3, wallConfig.Distance)
		else 7

	local width =
		if typeof(wallConfig.Width) == "number"
		then math.max(5, wallConfig.Width)
		else 14

	local height =
		if typeof(wallConfig.Height) == "number"
		then math.max(4, wallConfig.Height)
		else 9

	local thickness =
		if typeof(wallConfig.Thickness) == "number"
		then math.max(1, wallConfig.Thickness)
		else 2.5

	local duration =
		if typeof(wallConfig.Duration) == "number"
		then math.clamp(
			wallConfig.Duration,
			1,
			12
		)
		else 5

	local probeHeight =
		if typeof(wallConfig.GroundProbeHeight) == "number"
		then math.max(2, wallConfig.GroundProbeHeight)
		else 8

	local probeDepth =
		if typeof(wallConfig.GroundProbeDepth) == "number"
		then math.max(6, wallConfig.GroundProbeDepth)
		else 18

	local direction =
		horizontalDirection(
			root,
			context.RequestData.Direction
		)

	local desiredBase =
		root.Position
		+ direction * distance

	local rayParams =
		RaycastParams.new()

	rayParams.FilterType =
		Enum.RaycastFilterType.Exclude

	rayParams.FilterDescendantsInstances = {
		context.Character,
	}

	rayParams.IgnoreWater = false

	local result =
		workspace:Raycast(
			desiredBase
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

	if not result then
		return
	end

	local groundPosition =
		result.Position

	local center =
		groundPosition
		+ Vector3.new(
			0,
			height * 0.5,
			0
		)

	local wall =
		Instance.new("Part")

	wall.Name =
		"EarthWall"

	wall.Size =
		Vector3.new(
			width,
			height,
			thickness
		)

	wall.CFrame =
		safeLookAt(
			center,
			direction
		)

	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = true
	wall.CanTouch = true
	wall.Material = Enum.Material.Slate
	wall.Color =
		Color3.fromRGB(
			98,
			78,
			57
		)
	wall.CastShadow = true

	wall:SetAttribute(
		"JutsuId",
		EarthWall.Id
	)

	wall:SetAttribute(
		"OwnerUserId",
		context.Player.UserId
	)

	wall:SetAttribute(
		"TemporaryJutsuObstacle",
		true
	)

	wall.Parent = workspace

	Debris:AddItem(
		wall,
		duration
	)
end

function EarthWall.OnCastStarted(
	_context: any
)
end

function EarthWall.OnCastMarker(
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

		executeWall(
			context
		)
	end
end

function EarthWall.OnCastEnded(
	_context: any,
	_reason: string
)
end

function EarthWall.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			executeWall(
				context
			)
		end
	)
end

return EarthWall
