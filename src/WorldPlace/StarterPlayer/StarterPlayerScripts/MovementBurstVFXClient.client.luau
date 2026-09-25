--!strict
-- MovementBurstVFXClient v3 - Wind Ribbons
--
-- StarterPlayer > StarterPlayerScripts > MovementBurstVFXClient
--
-- Replaces the thin solid-line look with:
-- - broad, semi-transparent white/blue wind ribbons
-- - broken curved arcs instead of perfect geometric rings
-- - larger jump/landing silhouettes
-- - surface color used only for small debris accents
--
-- Multiplayer remote stays the same:
-- ReplicatedStorage > MovementRemotes > MovementBurstVFX
--
-- No movement controller is modified.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local movementRemotes = ReplicatedStorage:WaitForChild("MovementRemotes")
local movementBurstVFX = movementRemotes:WaitForChild("MovementBurstVFX") :: RemoteEvent

-- =========================
-- MOVEMENT REFERENCES
-- =========================

local DOUBLE_JUMP_ANIMATION_ID = "rbxassetid://113724435658718"

local MIN_NORMAL_LAND_FALL_SPEED = 28
local HEAVY_LAND_FALL_SPEED = 85
local TREE_JUMP_RECENT_WINDOW = 0.40
local GROUND_RAY_DISTANCE = 7

-- =========================
-- WIND LOOK
-- =========================

local WIND_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local WIND_WHITE = Color3.fromRGB(250, 252, 255)
local WIND_BLUE = Color3.fromRGB(185, 222, 255)

local WIND_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, WIND_WHITE),
	ColorSequenceKeypoint.new(0.45, WIND_BLUE),
	ColorSequenceKeypoint.new(1.00, WIND_WHITE),
})

local DEFAULT_SURFACE_COLOR = Color3.fromRGB(145, 140, 132)

-- Larger than v2 on purpose.
local JUMP_ARCS = 4
local JUMP_RADIUS_START = 0.45
local JUMP_RADIUS_END = 2.45
local JUMP_WIDTH = 0.62
local JUMP_DURATION = 0.24

local DOUBLE_ARCS = 6
local DOUBLE_RADIUS_START = 0.55
local DOUBLE_RADIUS_END = 3.10
local DOUBLE_WIDTH = 0.74
local DOUBLE_DURATION = 0.27

local LAND_ARCS = 5
local LAND_RADIUS_START = 0.48
local LAND_RADIUS_END = 3.05
local LAND_WIDTH = 0.70
local LAND_DURATION = 0.27

local HEAVY_ARCS = 7
local HEAVY_RADIUS_START = 0.60
local HEAVY_RADIUS_END = 4.35
local HEAVY_WIDTH = 0.92
local HEAVY_DURATION = 0.34

-- =========================
-- TRANSIENT HELPERS
-- =========================

local function makeAnchor(position: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "MovementWindAnchor"
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.CFrame = CFrame.new(position)
	p.Parent = workspace
	return p
end

local function polar(radius: number, angle: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

local function makeBeam(a0: Attachment, a1: Attachment, width: number): Beam
	local beam = Instance.new("Beam")
	beam.Name = "WindRibbon"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Segments = 3
	beam.Width0 = width
	beam.Width1 = width * 0.72
	beam.Color = WIND_COLOR
	beam.LightEmission = 1
	beam.LightInfluence = 0

	-- The soft texture is stretched/repeated across a wide ribbon,
	-- so it reads as a wispy gust instead of a solid neon line.
	beam.Texture = WIND_TEXTURE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 1.15
	beam.TextureSpeed = 2.25

	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1.00),
		NumberSequenceKeypoint.new(0.12, 0.56),
		NumberSequenceKeypoint.new(0.32, 0.28),
		NumberSequenceKeypoint.new(0.65, 0.34),
		NumberSequenceKeypoint.new(0.88, 0.64),
		NumberSequenceKeypoint.new(1.00, 1.00),
	})

	beam.Parent = a0.Parent
	return beam
end

local function fadeBeam(beam: Beam, duration: number, originalWidth0: number, originalWidth1: number)
	task.spawn(function()
		local steps = 8

		for i = 1, steps do
			if not beam.Parent then
				return
			end

			local t = i / steps
			local center = 0.28 + (0.72 * t)

			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 1.00),
				NumberSequenceKeypoint.new(0.12, math.min(1, center + 0.28)),
				NumberSequenceKeypoint.new(0.35, center),
				NumberSequenceKeypoint.new(0.68, math.min(1, center + 0.06)),
				NumberSequenceKeypoint.new(0.90, math.min(1, center + 0.34)),
				NumberSequenceKeypoint.new(1.00, 1.00),
			})

			local widthFactor = 1 - (0.28 * t)
			beam.Width0 = originalWidth0 * widthFactor
			beam.Width1 = originalWidth1 * widthFactor

			task.wait(duration / steps)
		end
	end)
end

-- One arc is built from 4 points and 3 Beam sections.
-- This creates a visibly curved/broken wisp instead of one thin line.
local function spawnWindArc(
	worldPosition: Vector3,
	baseAngle: number,
	startRadius: number,
	endRadius: number,
	spanRadians: number,
	width: number,
	duration: number,
	yBase: number,
	yLift: number
)
	local anchor = makeAnchor(worldPosition)
	local attachments: { Attachment } = {}

	for index = 0, 3 do
		local t = index / 3
		local angle = baseAngle + ((t - 0.5) * spanRadians)
		local radius = startRadius * (0.90 + 0.10 * t)

		local att = Instance.new("Attachment")
		att.Name = "WindPoint" .. tostring(index)
		att.Position = polar(
			radius,
			angle,
			yBase + math.sin(t * math.pi) * yLift
		)
		att.Parent = anchor

		table.insert(attachments, att)
	end

	local beams: { Beam } = {}

	for i = 1, 3 do
		local localWidth = width * (0.88 + math.random() * 0.20)
		local beam = makeBeam(attachments[i], attachments[i + 1], localWidth)
		table.insert(beams, beam)

		fadeBeam(
			beam,
			duration,
			beam.Width0,
			beam.Width1
		)
	end

	for index, att in ipairs(attachments) do
		local t = (index - 1) / 3
		local angle = baseAngle + ((t - 0.5) * spanRadians)
		local radius = endRadius * (0.90 + 0.10 * t)

		local destination = polar(
			radius,
			angle,
			yBase + 0.05 + math.sin(t * math.pi) * (yLift * 1.35)
		)

		TweenService:Create(
			att,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{ Position = destination }
		):Play()
	end

	Debris:AddItem(anchor, duration + 0.15)
end

local function spawnWindBurst(
	position: Vector3,
	arcCount: number,
	startRadius: number,
	endRadius: number,
	width: number,
	duration: number,
	yBase: number,
	yLift: number,
	spanDegrees: number
)
	local rotation = math.random() * math.pi * 2
	local spacing = (math.pi * 2) / arcCount

	for i = 1, arcCount do
		local angle =
			rotation
			+ ((i - 1) * spacing)
			+ math.rad(math.random(-12, 12))

		spawnWindArc(
			position,
			angle,
			startRadius,
			endRadius * (0.88 + math.random() * 0.20),
			math.rad(spanDegrees + math.random(-12, 12)),
			width * (0.88 + math.random() * 0.20),
			duration * (0.92 + math.random() * 0.14),
			yBase,
			yLift * (0.85 + math.random() * 0.30)
		)
	end
end

-- Secondary surface detail only.
local function spawnSurfaceFlecks(
	position: Vector3,
	color: Color3,
	count: number,
	heavy: boolean
)
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local size =
			if heavy
			then 0.09 + math.random() * 0.07
			else 0.055 + math.random() * 0.045

		local p = Instance.new("Part")
		p.Name = "SurfaceFleck"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.Transparency = 0.16
		p.Size = Vector3.new(size, size, size)
		p.CFrame = CFrame.new(position + Vector3.new(0, 0.05, 0))
		p.Parent = workspace

		local duration = if heavy then 0.30 else 0.22
		local travel =
			if heavy
			then 1.6 + math.random() * 1.5
			else 0.75 + math.random() * 0.85

		local rise =
			if heavy
			then 0.65 + math.random() * 0.95
			else 0.35 + math.random() * 0.50

		local destination =
			position
			+ dir * travel
			+ Vector3.new(0, rise, 0)

		TweenService:Create(
			p,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				CFrame =
					CFrame.new(destination)
					* CFrame.Angles(
						math.rad(math.random(-100, 100)),
						math.rad(math.random(-100, 100)),
						math.rad(math.random(-100, 100))
					),
				Transparency = 1,
				Size = p.Size * 0.30,
			}
		):Play()

		Debris:AddItem(p, duration + 0.06)
	end
end

-- =========================
-- EVENT LOOKS
-- =========================

local function renderJump(position: Vector3, surfaceColor: Color3)
	spawnWindBurst(
		position + Vector3.new(0, 0.12, 0),
		JUMP_ARCS,
		JUMP_RADIUS_START,
		JUMP_RADIUS_END,
		JUMP_WIDTH,
		JUMP_DURATION,
		0.02,
		0.22,
		70
	)

	spawnSurfaceFlecks(position, surfaceColor, 4, false)
end

local function renderDoubleJump(position: Vector3)
	spawnWindBurst(
		position,
		DOUBLE_ARCS,
		DOUBLE_RADIUS_START,
		DOUBLE_RADIUS_END,
		DOUBLE_WIDTH,
		DOUBLE_DURATION,
		-0.05,
		0.50,
		82
	)
end

local function renderLanding(position: Vector3, surfaceColor: Color3, heavy: boolean)
	if heavy then
		spawnWindBurst(
			position + Vector3.new(0, 0.12, 0),
			HEAVY_ARCS,
			HEAVY_RADIUS_START,
			HEAVY_RADIUS_END,
			HEAVY_WIDTH,
			HEAVY_DURATION,
			0.01,
			0.30,
			88
		)

		spawnSurfaceFlecks(position, surfaceColor, 9, true)
	else
		spawnWindBurst(
			position + Vector3.new(0, 0.10, 0),
			LAND_ARCS,
			LAND_RADIUS_START,
			LAND_RADIUS_END,
			LAND_WIDTH,
			LAND_DURATION,
			0.01,
			0.20,
			76
		)

		spawnSurfaceFlecks(position, surfaceColor, 5, false)
	end
end

local function renderEvent(
	eventName: string,
	position: Vector3,
	surfaceColor: Color3
)
	if eventName == "Jump" then
		renderJump(position, surfaceColor)
	elseif eventName == "DoubleJump" then
		renderDoubleJump(position)
	elseif eventName == "Land" then
		renderLanding(position, surfaceColor, false)
	elseif eventName == "LandHeavy" then
		renderLanding(position, surfaceColor, true)
	end
end

-- =========================
-- GROUND COLOR / POSITION
-- =========================

local function getGroundInfo(
	character: Model,
	rootPart: BasePart
): (Vector3, Color3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(
		rootPart.Position,
		Vector3.new(0, -GROUND_RAY_DISTANCE, 0),
		params
	)

	if result then
		local color = DEFAULT_SURFACE_COLOR

		if result.Instance and result.Instance:IsA("BasePart") then
			color = result.Instance.Color
		elseif result.Instance == workspace.Terrain then
			color = workspace.Terrain:GetMaterialColor(result.Material)
		end

		return result.Position + result.Normal * 0.06, color
	end

	return rootPart.Position - Vector3.new(0, 2.7, 0), DEFAULT_SURFACE_COLOR
end

-- =========================
-- LOCAL CHARACTER DETECTION
-- =========================

local activeCharacter: Model? = nil

local stateConnection: RBXScriptConnection? = nil
local animationConnection: RBXScriptConnection? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local treeJumpConnection: RBXScriptConnection? = nil
local deathConnection: RBXScriptConnection? = nil

local lastJumpEvent = -math.huge
local lastDoubleJumpEvent = -math.huge
local lastLandEvent = -math.huge
local peakDownwardSpeed = 0
local lastTreeJumpActiveTime = -math.huge

local function disconnectCharacterSignals()
	for _, connection in ipairs({
		stateConnection,
		animationConnection,
		heartbeatConnection,
		treeJumpConnection,
		deathConnection,
		}) do
		if connection then
			connection:Disconnect()
		end
	end

	stateConnection = nil
	animationConnection = nil
	heartbeatConnection = nil
	treeJumpConnection = nil
	deathConnection = nil
end

local function sendLocalEvent(
	eventName: string,
	position: Vector3,
	surfaceColor: Color3
)
	renderEvent(eventName, position, surfaceColor)
	movementBurstVFX:FireServer(eventName, position, surfaceColor)
end

local function setupCharacter(character: Model)
	disconnectCharacterSignals()

	activeCharacter = character

	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator")

	lastJumpEvent = -math.huge
	lastDoubleJumpEvent = -math.huge
	lastLandEvent = -math.huge
	peakDownwardSpeed = 0
	lastTreeJumpActiveTime = -math.huge

	local function isTreeJumpBusy(): boolean
		return character:GetAttribute("TreeJumpActive") == true
			or character:GetAttribute("IsTreeJumping") == true
	end

	local function isSurfaceOrWaterMovement(): boolean
		return character:GetAttribute("SurfaceWalking") == true
			or character:GetAttribute("SurfaceJumping") == true
			or character:GetAttribute("WaterWalking") == true
			or character:GetAttribute("WaterJumping") == true
	end

	treeJumpConnection =
		character:GetAttributeChangedSignal("TreeJumpActive"):Connect(function()
			lastTreeJumpActiveTime = time()
		end)

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if activeCharacter ~= character or humanoid.Health <= 0 then
			return
		end

		if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
			local downward = math.max(0, -rootPart.AssemblyLinearVelocity.Y)
			peakDownwardSpeed = math.max(peakDownwardSpeed, downward)
		end
	end)

	animationConnection = animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		if track.Animation.AnimationId ~= DOUBLE_JUMP_ANIMATION_ID then
			return
		end

		if time() - lastDoubleJumpEvent < 0.10 or isTreeJumpBusy() then
			return
		end

		lastDoubleJumpEvent = time()
		sendLocalEvent("DoubleJump", rootPart.Position, WIND_BLUE)
	end)

	stateConnection = humanoid.StateChanged:Connect(function(_oldState, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			peakDownwardSpeed = 0

			if isSurfaceOrWaterMovement() or isTreeJumpBusy() then
				return
			end

			if time() - lastJumpEvent < 0.12 then
				return
			end

			lastJumpEvent = time()

			local groundPosition, groundColor = getGroundInfo(character, rootPart)
			sendLocalEvent("Jump", groundPosition, groundColor)

		elseif newState == Enum.HumanoidStateType.Landed then
			if time() - lastLandEvent < 0.10 then
				return
			end

			if character:GetAttribute("WaterWalking") == true
				or character:GetAttribute("WaterJumping") == true then
				peakDownwardSpeed = 0
				return
			end

			local recentTreeJump =
				time() - lastTreeJumpActiveTime <= TREE_JUMP_RECENT_WINDOW

			local impactSpeed = peakDownwardSpeed
			peakDownwardSpeed = 0

			if impactSpeed < MIN_NORMAL_LAND_FALL_SPEED
				and not recentTreeJump then
				return
			end

			lastLandEvent = time()

			local groundPosition, groundColor = getGroundInfo(character, rootPart)

			local heavy =
				recentTreeJump
				or impactSpeed >= HEAVY_LAND_FALL_SPEED

			sendLocalEvent(
				if heavy then "LandHeavy" else "Land",
				groundPosition,
				groundColor
			)
		end
	end)

	deathConnection = humanoid.Died:Connect(function()
		peakDownwardSpeed = 0
	end)
end

if player.Character then
	task.spawn(setupCharacter, player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

-- =========================
-- MULTIPLAYER
-- =========================

movementBurstVFX.OnClientEvent:Connect(function(
	sourcePlayer: Player,
	eventName: string,
	position: Vector3,
	surfaceColor: Color3
)
	if not sourcePlayer or sourcePlayer == player then
		return
	end

	renderEvent(eventName, position, surfaceColor)
end)
