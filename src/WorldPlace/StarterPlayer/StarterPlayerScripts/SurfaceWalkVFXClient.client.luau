--!strict
-- SurfaceWalkVFXClient v1
--
-- StarterPlayer > StarterPlayerScripts > SurfaceWalkVFXClient
--
-- Dedicated Wall / Ceiling / Surface Walk VFX.
--
-- Visual language:
-- - broad soft contact streaks, not smoke clouds
-- - tiny surface-colored flecks for physical contact
-- - stronger push burst when jumping away from a surface
-- - automatically oriented using SurfaceNormal
-- - works on walls and ceilings
-- - multiplayer
--
-- Reads existing attributes only:
--   SurfaceWalking
--   SurfaceNormal
--   SurfaceMoving
--   SurfaceJumping
--   IsDashing
--
-- Does NOT modify SurfaceController or movement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local movementRemotes = ReplicatedStorage:WaitForChild("MovementRemotes")
local remote = movementRemotes:WaitForChild("SurfaceWalkVFX") :: RemoteEvent

-- =========================
-- STYLE
-- =========================

local AIR_WHITE = Color3.fromRGB(245, 250, 255)
local AIR_BLUE = Color3.fromRGB(195, 225, 255)
local DEFAULT_SURFACE_COLOR = Color3.fromRGB(145, 140, 135)
local SOFT_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Contact cadence is distance-based so Sprint naturally produces more contacts.
local WALK_STEP_DISTANCE = 3.4
local SPRINT_STEP_DISTANCE = 2.7
local MIN_STEP_INTERVAL = 0.12
local MIN_SPRINT_INTERVAL = 0.085

local CONTACT_RIBBON_LENGTH = 1.15
local CONTACT_RIBBON_WIDTH = 0.30
local CONTACT_LIFETIME = 0.22

local SPRINT_RIBBON_LENGTH = 1.50
local SPRINT_RIBBON_WIDTH = 0.38
local SPRINT_LIFETIME = 0.24

local JUMP_RIBBON_LENGTH = 2.45
local JUMP_RIBBON_WIDTH = 0.52
local JUMP_LIFETIME = 0.30

local DETECTION_HZ = 30
local DETECTION_INTERVAL = 1 / DETECTION_HZ

-- Existing project speeds.
local WALK_SPEED_THRESHOLD = 25

-- =========================
-- VECTOR HELPERS
-- =========================

local function safeUnit(vector: Vector3, fallback: Vector3): Vector3
	if vector.Magnitude < 0.001 then
		return fallback
	end
	return vector.Unit
end

local function projectOntoPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

local function buildSurfaceBasis(
	normal: Vector3,
	moveDirection: Vector3
): (Vector3, Vector3, Vector3)
	local n = safeUnit(normal, Vector3.yAxis)
	local tangent = projectOntoPlane(moveDirection, n)

	if tangent.Magnitude < 0.05 then
		local fallback = math.abs(n:Dot(Vector3.yAxis)) < 0.95
			and Vector3.yAxis
			or Vector3.xAxis
		tangent = projectOntoPlane(fallback, n)
	end

	tangent = safeUnit(tangent, Vector3.zAxis)
	local side = safeUnit(n:Cross(tangent), Vector3.xAxis)

	return n, tangent, side
end

-- =========================
-- TRANSIENT ANCHOR
-- =========================

local function makeAnchor(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "SurfaceWalkVFXAnchor"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	return part
end

-- =========================
-- SOFT WIND RIBBON
-- =========================

local function spawnRibbon(
	position: Vector3,
	normal: Vector3,
	tangent: Vector3,
	side: Vector3,
	sideSign: number,
	length: number,
	width: number,
	duration: number,
	power: number
)
	local anchor = makeAnchor(position + normal * 0.06)

	local a0 = Instance.new("Attachment")
	a0.Name = "RibbonStart"
	a0.Position = side * sideSign * 0.13
	a0.Parent = anchor

	local a1 = Instance.new("Attachment")
	a1.Name = "RibbonMid"
	a1.Position =
		-tangent * (length * 0.48)
		+ side * sideSign * (0.28 + 0.12 * power)
		+ normal * (0.18 + 0.08 * power)
	a1.Parent = anchor

	local a2 = Instance.new("Attachment")
	a2.Name = "RibbonEnd"
	a2.Position =
		-tangent * length
		+ side * sideSign * (0.52 + 0.18 * power)
		+ normal * (0.36 + 0.12 * power)
	a2.Parent = anchor

	local function createBeam(p0: Attachment, p1: Attachment, beamWidth: number): Beam
		local beam = Instance.new("Beam")
		beam.Name = "SurfaceAirRibbon"
		beam.Attachment0 = p0
		beam.Attachment1 = p1
		beam.FaceCamera = true
		beam.Segments = 4
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth * 0.44
		beam.Texture = SOFT_TEXTURE
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, AIR_WHITE),
			ColorSequenceKeypoint.new(0.55, AIR_BLUE),
			ColorSequenceKeypoint.new(1.00, AIR_WHITE),
		})
		beam.LightEmission = 0.76
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.00, 0.30),
			NumberSequenceKeypoint.new(0.40, 0.40),
			NumberSequenceKeypoint.new(0.78, 0.62),
			NumberSequenceKeypoint.new(1.00, 1.00),
		})
		beam.Parent = anchor
		return beam
	end

	local beamA = createBeam(a0, a1, width)
	local beamB = createBeam(a1, a2, width * 0.78)

	-- Expand away from the surface a little while fading.
	TweenService:Create(
		a1,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = a1.Position
			- tangent * 0.22
				+ normal * 0.12,
		}
	):Play()

	TweenService:Create(
		a2,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = a2.Position
			- tangent * 0.38
				+ normal * 0.20,
		}
	):Play()

	task.spawn(function()
		local steps = 6
		for i = 1, steps do
			if not anchor.Parent then
				return
			end

			local alpha = i / steps
			local t = 0.30 + 0.70 * alpha

			for _, beam in ipairs({ beamA, beamB }) do
				if beam.Parent then
					beam.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0.00, math.min(1, t)),
						NumberSequenceKeypoint.new(0.52, math.min(1, t + 0.10)),
						NumberSequenceKeypoint.new(1.00, 1.00),
					})
				end
			end

			task.wait(duration / steps)
		end
	end)

	Debris:AddItem(anchor, duration + 0.10)
end

-- =========================
-- SURFACE FLECKS
-- =========================

local function spawnSurfaceFlecks(
	position: Vector3,
	normal: Vector3,
	tangent: Vector3,
	side: Vector3,
	surfaceColor: Color3,
	count: number,
	power: number
)
	for _ = 1, count do
		local sideAmount = (math.random() * 2 - 1) * (0.55 + 0.25 * power)
		local backAmount = 0.32 + math.random() * (0.65 + 0.40 * power)
		local outward = 0.20 + math.random() * (0.46 + 0.28 * power)
		local size = 0.045 + math.random() * 0.045 * power

		local part = Instance.new("Part")
		part.Name = "SurfaceContactFleck"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = surfaceColor
		part.Transparency = 0.16
		part.Size = Vector3.new(size, size, size)
		part.CFrame = CFrame.new(position + normal * 0.04)
		part.Parent = workspace

		local target =
			position
		- tangent * backAmount
			+ side * sideAmount
			+ normal * outward

		local duration = 0.18 + math.random() * 0.10

		TweenService:Create(
			part,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				CFrame = CFrame.new(target)
					* CFrame.Angles(
						math.rad(math.random(-100, 100)),
						math.rad(math.random(-100, 100)),
						math.rad(math.random(-100, 100))
					),
				Transparency = 1,
				Size = Vector3.new(size * 0.35, size * 0.35, size * 0.35),
			}
		):Play()

		Debris:AddItem(part, duration + 0.05)
	end
end

-- =========================
-- EVENT LOOKS
-- =========================

local function renderStep(
	position: Vector3,
	normal: Vector3,
	surfaceColor: Color3,
	moveDirection: Vector3,
	sprint: boolean
)
	local n, tangent, side = buildSurfaceBasis(normal, moveDirection)
	local length = sprint and SPRINT_RIBBON_LENGTH or CONTACT_RIBBON_LENGTH
	local width = sprint and SPRINT_RIBBON_WIDTH or CONTACT_RIBBON_WIDTH
	local duration = sprint and SPRINT_LIFETIME or CONTACT_LIFETIME
	local power = sprint and 1.25 or 0.85

	spawnRibbon(position, n, tangent, side, -1, length, width, duration, power)
	spawnRibbon(position, n, tangent, side, 1, length, width, duration, power)

	spawnSurfaceFlecks(
		position,
		n,
		tangent,
		side,
		surfaceColor,
		sprint and 5 or 3,
		power
	)
end

local function renderJumpPush(
	position: Vector3,
	normal: Vector3,
	surfaceColor: Color3,
	moveDirection: Vector3
)
	local n, tangent, side = buildSurfaceBasis(normal, moveDirection)

	-- Four ribbons make the jump read like a pressure release from the contact surface.
	spawnRibbon(position, n, tangent, side, -1, JUMP_RIBBON_LENGTH, JUMP_RIBBON_WIDTH, JUMP_LIFETIME, 1.55)
	spawnRibbon(position, n, tangent, side, 1, JUMP_RIBBON_LENGTH, JUMP_RIBBON_WIDTH, JUMP_LIFETIME, 1.55)
	spawnRibbon(position, n, side, tangent, -1, JUMP_RIBBON_LENGTH * 0.72, JUMP_RIBBON_WIDTH * 0.80, JUMP_LIFETIME * 0.90, 1.25)
	spawnRibbon(position, n, side, tangent, 1, JUMP_RIBBON_LENGTH * 0.72, JUMP_RIBBON_WIDTH * 0.80, JUMP_LIFETIME * 0.90, 1.25)

	spawnSurfaceFlecks(
		position,
		n,
		tangent,
		side,
		surfaceColor,
		9,
		1.45
	)
end

local function renderEvent(
	eventName: string,
	position: Vector3,
	normal: Vector3,
	surfaceColor: Color3,
	moveDirection: Vector3
)
	if eventName == "Step" then
		renderStep(position, normal, surfaceColor, moveDirection, false)
	elseif eventName == "SprintStep" then
		renderStep(position, normal, surfaceColor, moveDirection, true)
	elseif eventName == "JumpPush" then
		renderJumpPush(position, normal, surfaceColor, moveDirection)
	end
end

-- =========================
-- SURFACE QUERY
-- =========================

local function getSurfaceHit(
	character: Model,
	origin: Vector3,
	normal: Vector3
): RaycastResult?
	local n = safeUnit(normal, Vector3.yAxis)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	return workspace:Raycast(
		origin + n * 0.55,
		-n * 4.5,
		params
	)
end

local function getSurfaceColor(hit: RaycastResult?): Color3
	if not hit then
		return DEFAULT_SURFACE_COLOR
	end

	if hit.Instance and hit.Instance:IsA("BasePart") then
		return hit.Instance.Color
	end

	if hit.Instance == workspace.Terrain then
		return workspace.Terrain:GetMaterialColor(hit.Material)
	end

	return DEFAULT_SURFACE_COLOR
end

-- =========================
-- NETWORK
-- =========================

local function sendLocalEvent(
	eventName: string,
	position: Vector3,
	normal: Vector3,
	surfaceColor: Color3,
	moveDirection: Vector3
)
	renderEvent(
		eventName,
		position,
		normal,
		surfaceColor,
		moveDirection
	)

	remote:FireServer(
		eventName,
		position,
		normal,
		surfaceColor,
		moveDirection
	)
end

-- =========================
-- LOCAL CHARACTER
-- =========================

local heartbeatConnection: RBXScriptConnection? = nil
local surfaceJumpConnection: RBXScriptConnection? = nil
local deathConnection: RBXScriptConnection? = nil

local function disconnectCharacter()
	for _, connection in ipairs({
		heartbeatConnection,
		surfaceJumpConnection,
		deathConnection,
		}) do
		if connection then
			connection:Disconnect()
		end
	end

	heartbeatConnection = nil
	surfaceJumpConnection = nil
	deathConnection = nil
end

local function setupCharacter(character: Model)
	disconnectCharacter()

	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	local accumulated = 0
	local traveled = 0
	local previousPosition = rootPart.Position
	local lastStepTime = -math.huge
	local surfaceJumpWasActive = character:GetAttribute("SurfaceJumping") == true

	local function getNormal(): Vector3
		local value = character:GetAttribute("SurfaceNormal")
		return typeof(value) == "Vector3"
			and safeUnit(value, Vector3.yAxis)
			or Vector3.yAxis
	end

	local function getMoveDirection(normal: Vector3): Vector3
		local velocity = rootPart.AssemblyLinearVelocity
		local tangentVelocity = projectOntoPlane(velocity, normal)

		if tangentVelocity.Magnitude > 1 then
			return tangentVelocity.Unit
		end

		local move = projectOntoPlane(humanoid.MoveDirection, normal)
		return safeUnit(move, rootPart.CFrame.LookVector)
	end

	local function emitContact(eventName: string)
		local normal = getNormal()
		local hit = getSurfaceHit(character, rootPart.Position, normal)

		if not hit then
			return
		end

		local moveDirection = getMoveDirection(normal)

		sendLocalEvent(
			eventName,
			hit.Position + hit.Normal * 0.035,
			hit.Normal,
			getSurfaceColor(hit),
			moveDirection
		)
	end

	surfaceJumpConnection =
		character:GetAttributeChangedSignal("SurfaceJumping"):Connect(function()
			local active = character:GetAttribute("SurfaceJumping") == true

			if active and not surfaceJumpWasActive
				and character:GetAttribute("WaterJumping") ~= true then
				emitContact("JumpPush")
			end

			surfaceJumpWasActive = active
		end)

	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if humanoid.Health <= 0 then
			return
		end

		accumulated += deltaTime
		if accumulated < DETECTION_INTERVAL then
			return
		end
		accumulated = 0

		local currentPosition = rootPart.Position
		local delta = currentPosition - previousPosition
		previousPosition = currentPosition

		local surfaceWalking = character:GetAttribute("SurfaceWalking") == true
		local waterWalking = character:GetAttribute("WaterWalking") == true
		local moving = character:GetAttribute("SurfaceMoving") == true
		local dashing = character:GetAttribute("IsDashing") == true

		-- Water has its own dedicated VFX language.
		if not surfaceWalking
			or waterWalking
			or not moving
			or dashing then
			traveled = 0
			return
		end

		local normal = getNormal()
		local tangentDelta = projectOntoPlane(delta, normal)
		traveled += tangentDelta.Magnitude

		local tangentVelocity = projectOntoPlane(rootPart.AssemblyLinearVelocity, normal)
		local sprinting = tangentVelocity.Magnitude >= WALK_SPEED_THRESHOLD
		local requiredDistance = sprinting and SPRINT_STEP_DISTANCE or WALK_STEP_DISTANCE
		local minInterval = sprinting and MIN_SPRINT_INTERVAL or MIN_STEP_INTERVAL

		if traveled >= requiredDistance
			and time() - lastStepTime >= minInterval then
			traveled = 0
			lastStepTime = time()
			emitContact(sprinting and "SprintStep" or "Step")
		end
	end)

	deathConnection = humanoid.Died:Connect(function()
		traveled = 0
	end)
end

if player.Character then
	task.spawn(setupCharacter, player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

-- =========================
-- MULTIPLAYER
-- =========================

remote.OnClientEvent:Connect(function(
	sourcePlayer: Player,
	eventName: string,
	position: Vector3,
	normal: Vector3,
	surfaceColor: Color3,
	moveDirection: Vector3
)
	if not sourcePlayer or sourcePlayer == player then
		return
	end

	renderEvent(
		eventName,
		position,
		normal,
		surfaceColor,
		moveDirection
	)
end)
