--!strict
-- WaterWalkVFXClient v5 - Marker-Synced Walk / Run Steps
-- ElDiabloLocoStudios / Roblox
--
-- StarterPlayer > StarterPlayerScripts > WaterWalkVFXClient [LocalScript]
--
-- Based on v4 Dash Leap.
--
-- PRESERVED:
-- - Idle ripple
-- - Water Jump
-- - real landing splash
-- - DashStart leap splash
-- - DashLand splash
-- - Terrain.WaterColor tint
-- - multiplayer replication through WaterWalkVFXServer
--
-- CHANGED:
-- - distance/timer Step logic removed
-- - Walk animation FootL / FootR markers drive WalkStep
-- - Run animation FootL / FootR markers drive RunStep
-- - WalkStep and RunStep have different visual intensity
--
-- Current locomotion assets:
-- Walk = 75479783841702
-- Run  = 116142758807536
--
-- Required markers:
-- FootL
-- FootR

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local TweenService =
	game:GetService("TweenService")

local Debris =
	game:GetService("Debris")

local RunService =
	game:GetService("RunService")


local player =
	Players.LocalPlayer

local movementRemotes =
	ReplicatedStorage:
	WaitForChild(
		"MovementRemotes"
	)

local remote =
	movementRemotes:
	WaitForChild(
		"WaterWalkVFX"
	) :: RemoteEvent


-- =========================
-- ANIMATION IDS
-- =========================

local WALK_ANIMATION_NUMERIC_ID =
	"75479783841702"

local RUN_ANIMATION_NUMERIC_ID =
	"116142758807536"

local FOOT_LEFT_MARKER =
	"FootL"

local FOOT_RIGHT_MARKER =
	"FootR"

-- Protects only against two overlapping copies of the SAME locomotion
-- track firing the same contact almost simultaneously.
-- This is NOT cadence throttling.
local SAME_INSTANT_STEP_DEDUPE =
	0.025


-- =========================
-- COLORS
-- =========================

local DEFAULT_WATER_COLOR =
	Color3.fromRGB(
		95,
		175,
		225
	)

local RIPPLE_HIGHLIGHT =
	Color3.fromRGB(
		225,
		247,
		255
	)

local DASH_FOAM =
	Color3.fromRGB(
		240,
		251,
		255
	)

local DASH_SPRAY_TEXTURE =
	"rbxasset://textures/particles/smoke_main.dds"


local function mixColor(
	a: Color3,
	b: Color3,
	t: number
): Color3

	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end


local function getWaterTint(): Color3

	local terrain =
		workspace:
		FindFirstChildOfClass(
			"Terrain"
		)

	if terrain then
		return terrain.WaterColor
	end

	return DEFAULT_WATER_COLOR
end


-- =========================
-- WALK STEP LOOK
-- =========================

local WALK_STEP_SEGMENTS =
	16

local WALK_STEP_START_RADIUS =
	0.28

local WALK_STEP_END_RADIUS =
	1.42

local WALK_STEP_DURATION =
	0.34

local WALK_STEP_WIDTH =
	0.082

local WALK_STEP_DROPLETS =
	3


-- =========================
-- RUN STEP LOOK
-- =========================

local RUN_STEP_SEGMENTS =
	20

local RUN_STEP_START_RADIUS =
	0.34

local RUN_STEP_END_RADIUS =
	2.04

local RUN_STEP_DURATION =
	0.38

local RUN_STEP_WIDTH =
	0.11

local RUN_STEP_DROPLETS =
	6


-- =========================
-- PRESERVED v4 LOOKS
-- =========================

local IDLE_SEGMENTS =
	14

local IDLE_START_RADIUS =
	0.28

local IDLE_END_RADIUS =
	1.08

local IDLE_DURATION =
	0.50

local IDLE_WIDTH =
	0.060

local JUMP_SEGMENTS =
	22

local JUMP_START_RADIUS =
	0.46

local JUMP_END_RADIUS =
	2.78

local JUMP_DURATION =
	0.52

local JUMP_WIDTH =
	0.145

local LAND_SEGMENTS =
	22

local LAND_START_RADIUS =
	0.42

local LAND_END_RADIUS =
	2.48

local LAND_DURATION =
	0.48

local LAND_WIDTH =
	0.13

local IDLE_RIPPLE_INTERVAL =
	1.15

-- Dash animation is a single forward impulse/leap.
local DASH_START_RIPPLE_RADIUS =
	2.55

local DASH_START_RIPPLE_WIDTH =
	0.16

local DASH_START_SPRAY_LENGTH =
	2.65

local DASH_START_SPRAY_WIDTH =
	0.42

local DASH_START_SPRAY_LIFETIME =
	0.34

local DASH_LAND_RIPPLE_RADIUS =
	2.10

local DASH_LAND_RIPPLE_WIDTH =
	0.12

local DASH_LAND_DROPLETS =
	9

local WATER_RAY_DISTANCE =
	5.5

local DETECTION_HZ =
	30

local DETECTION_INTERVAL =
	1 / DETECTION_HZ

local MIN_LANDING_DOWN_SPEED =
	8

local LANDING_MEMORY_TIME =
	0.65


-- =========================
-- PART HELPERS
-- =========================

local function makeAnchor(
	position: Vector3
): Part

	local part =
		Instance.new("Part")

	part.Name =
		"WaterWalkVFXAnchor"

	part.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)

	part.Anchored =
		true

	part.CanCollide =
		false

	part.CanTouch =
		false

	part.CanQuery =
		false

	part.CastShadow =
		false

	part.Transparency =
		1

	part.CFrame =
		CFrame.new(
			position
		)

	part.Parent =
		workspace


	return part
end


local function spawnRipple(
	worldPosition: Vector3,
	waterColor: Color3,
	segments: number,
	startRadius: number,
	endRadius: number,
	duration: number,
	width: number,
	baseTransparency: number
)

	local anchor =
		makeAnchor(
			worldPosition
			+ Vector3.new(
				0,
				0.035,
				0
			)
		)

	local angleStep =
		(math.pi * 2)
		/ segments

	local initialRotation =
		math.random()
		* math.pi
		* 2


	for index = 1,
		segments do

		local angle =
			initialRotation
			+ (index - 1)
			* angleStep

		local radial =
			Vector3.new(
				math.cos(
					angle
				),
				0,
				math.sin(
					angle
				)
			)

		local tangent =
			Vector3.new(
				-radial.Z,
				0,
				radial.X
			)

		local startPos =
			anchor.Position
			+ radial
			* startRadius

		local startArcLength =
			(
				2
				* math.pi
				* startRadius
				/ segments
			)
			* 0.84

		local finalPos =
			anchor.Position
			+ radial
			* endRadius

		local finalArcLength =
			(
				2
				* math.pi
				* endRadius
				/ segments
			)
			* 0.86


		local segment =
			Instance.new("Part")

		segment.Name =
			"WaterRippleSegment"

		segment.Anchored =
			true

		segment.CanCollide =
			false

		segment.CanTouch =
			false

		segment.CanQuery =
			false

		segment.CastShadow =
			false

		segment.Material =
			Enum.Material.Neon

		segment.Color =
			mixColor(
				waterColor,
				RIPPLE_HIGHLIGHT,
				0.52
				+ math.random()
				* 0.24
			)

		segment.Transparency =
			baseTransparency
			+ math.random()
			* 0.07

		segment.Size =
			Vector3.new(
				width,
				width * 0.30,
				startArcLength
			)

		segment.CFrame =
			CFrame.lookAt(
				startPos,
				startPos + tangent
			)

		segment.Parent =
			workspace


		TweenService:
			Create(
				segment,
				TweenInfo.new(
					duration
					* (
						0.92
						+ math.random()
						* 0.12
					),
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					CFrame =
					CFrame.lookAt(
						finalPos,
						finalPos + tangent
					),

					Transparency =
					1,

					Size =
					Vector3.new(
						width * 0.38,
						width * 0.13,
						finalArcLength
					),
				}
			):
			Play()


		Debris:AddItem(
			segment,
			duration + 0.10
		)
	end


	Debris:AddItem(
		anchor,
		duration + 0.12
	)
end


local function spawnDroplets(
	worldPosition: Vector3,
	waterColor: Color3,
	count: number,
	powerScale: number
)

	for _ = 1,
		count do

		local angle =
			math.random()
			* math.pi
			* 2

		local dir =
			Vector3.new(
				math.cos(
					angle
				),
				0,
				math.sin(
					angle
				)
			)

		local size =
			0.045
			+ math.random()
			* 0.055


		local part =
			Instance.new("Part")

		part.Name =
			"WaterDroplet"

		part.Anchored =
			true

		part.CanCollide =
			false

		part.CanTouch =
			false

		part.CanQuery =
			false

		part.CastShadow =
			false

		part.Material =
			Enum.Material.Neon

		part.Color =
			mixColor(
				waterColor,
				RIPPLE_HIGHLIGHT,
				0.45
				+ math.random()
				* 0.35
			)

		part.Transparency =
			0.12

		part.Size =
			Vector3.new(
				size,
				size * 2.1,
				size
			)

		part.CFrame =
			CFrame.new(
				worldPosition
				+ Vector3.new(
					0,
					0.08,
					0
				)
			)

		part.Parent =
			workspace


		local outward =
			(
				0.42
				+ math.random()
				* 1.0
			)
			* powerScale

		local rise =
			(
				0.72
				+ math.random()
				* 1.15
			)
			* powerScale

		local apex =
			worldPosition
			+ dir * outward
			+ Vector3.new(
				0,
				rise,
				0
			)

		local upTime =
			0.13
			+ math.random()
			* 0.06

		local downTime =
			0.15
			+ math.random()
			* 0.07


		local upTween =
			TweenService:
			Create(
				part,
				TweenInfo.new(
					upTime,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					CFrame =
					CFrame.new(
						apex
					),

					Transparency =
					0.24,
				}
			)


		local downTween =
			TweenService:
			Create(
				part,
				TweenInfo.new(
					downTime,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					CFrame =
					CFrame.new(
						worldPosition
						+ dir
						* outward
						* 1.25
						+ Vector3.new(
							0,
							0.02,
							0
						)
					),

					Transparency =
					1,

					Size =
					Vector3.new(
						size * 0.4,
						size,
						size * 0.4
					),
				}
			)


		upTween.Completed:
			Connect(
				function()

					if part.Parent then

						downTween:
						Play()
					end
				end
			)


		upTween:
			Play()


		Debris:AddItem(
			part,
			upTime
				+ downTime
				+ 0.10
		)
	end
end


-- =========================
-- DASH LEAP VFX (v4 preserved)
-- =========================

local function createDashSprayRibbon(
	worldPosition: Vector3,
	direction: Vector3,
	sideSign: number,
	waterColor: Color3
)

	local flatDirection =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)


	if flatDirection.Magnitude <
		0.05 then

		return
	end


	flatDirection =
		flatDirection.Unit


	local right =
		Vector3.new(
			-flatDirection.Z,
			0,
			flatDirection.X
		)


	local anchor =
		makeAnchor(
			worldPosition
			+ Vector3.new(
				0,
				0.10,
				0
			)
		)


	local startAttachment =
		Instance.new("Attachment")

	startAttachment.Name =
		"DashSprayStart"

	startAttachment.Position =
		right
		* sideSign
		* 0.30

	startAttachment.Parent =
		anchor


	local midAttachment =
		Instance.new("Attachment")

	midAttachment.Name =
		"DashSprayMid"

	midAttachment.Position =
		-flatDirection
		* (
			DASH_START_SPRAY_LENGTH
			* 0.48
		)
		+ right
		* sideSign
		* 0.72
		+ Vector3.new(
			0,
			0.28,
			0
		)

	midAttachment.Parent =
		anchor


	local endAttachment =
		Instance.new("Attachment")

	endAttachment.Name =
		"DashSprayEnd"

	endAttachment.Position =
		-flatDirection
		* DASH_START_SPRAY_LENGTH
		+ right
		* sideSign
		* 1.05
		+ Vector3.new(
			0,
			0.52,
			0
		)

	endAttachment.Parent =
		anchor


	local function makeBeam(
		a0: Attachment,
		a1: Attachment,
		width: number
	): Beam

		local beam =
			Instance.new("Beam")

		beam.Name =
			"DashWaterSpray"

		beam.Attachment0 =
			a0

		beam.Attachment1 =
			a1

		beam.FaceCamera =
			true

		beam.Segments =
			4

		beam.Width0 =
			width

		beam.Width1 =
			width * 0.42

		beam.Texture =
			DASH_SPRAY_TEXTURE

		beam.TextureMode =
			Enum.TextureMode.Stretch

		beam.TextureLength =
			1

		beam.Color =
			ColorSequence.new({
				ColorSequenceKeypoint.new(
					0,
					DASH_FOAM
				),

				ColorSequenceKeypoint.new(
					0.55,
					mixColor(
						waterColor,
						DASH_FOAM,
						0.70
					)
				),

				ColorSequenceKeypoint.new(
					1,
					waterColor
				),
			})

		beam.LightEmission =
			0.76

		beam.LightInfluence =
			0

		beam.Transparency =
			NumberSequence.new({
				NumberSequenceKeypoint.new(
					0,
					0.20
				),

				NumberSequenceKeypoint.new(
					0.52,
					0.38
				),

				NumberSequenceKeypoint.new(
					1,
					1
				),
			})

		beam.Parent =
			anchor


		return beam
	end


	local beamA =
		makeBeam(
			startAttachment,
			midAttachment,
			DASH_START_SPRAY_WIDTH
		)

	local beamB =
		makeBeam(
			midAttachment,
			endAttachment,
			DASH_START_SPRAY_WIDTH
			* 0.76
		)


	task.spawn(
		function()

			local steps =
				6


			for i = 1,
				steps do

				if not anchor.Parent then
					return
				end


				local alpha =
					i / steps

				local transparency =
					0.20
					+ 0.80
					* alpha


				for _,
					beam in ipairs({
						beamA,
						beamB,
					}) do

					if beam.Parent then

						beam.Transparency =
							NumberSequence.new({
								NumberSequenceKeypoint.new(
									0,
									transparency
								),

								NumberSequenceKeypoint.new(
									0.55,
									math.min(
										1,
										transparency
										+ 0.12
									)
								),

								NumberSequenceKeypoint.new(
									1,
									1
								),
							})
					end
				end


				task.wait(
					DASH_START_SPRAY_LIFETIME
						/ steps
				)
			end
		end
	)


	Debris:AddItem(
		anchor,
		DASH_START_SPRAY_LIFETIME
			+ 0.10
	)
end


local function renderDashStart(
	position: Vector3,
	color: Color3,
	direction: Vector3
)

	spawnRipple(
		position,
		color,
		22,
		0.38,
		DASH_START_RIPPLE_RADIUS,
		0.42,
		DASH_START_RIPPLE_WIDTH,
		0.20
	)


	createDashSprayRibbon(
		position,
		direction,
		-1,
		color
	)


	createDashSprayRibbon(
		position,
		direction,
		1,
		color
	)


	spawnDroplets(
		position,
		color,
		14,
		1.15
	)
end


local function renderDashLand(
	position: Vector3,
	color: Color3
)

	spawnRipple(
		position,
		color,
		18,
		0.32,
		DASH_LAND_RIPPLE_RADIUS,
		0.38,
		DASH_LAND_RIPPLE_WIDTH,
		0.31
	)


	spawnDroplets(
		position,
		color,
		DASH_LAND_DROPLETS,
		0.72
	)
end


-- =========================
-- STEP LOOKS - NEW v5
-- =========================

local function renderWalkStep(
	position: Vector3,
	color: Color3
)

	-- Main contact ripple.
	spawnRipple(
		position,
		color,
		WALK_STEP_SEGMENTS,
		WALK_STEP_START_RADIUS,
		WALK_STEP_END_RADIUS,
		WALK_STEP_DURATION,
		WALK_STEP_WIDTH,
		0.43
	)


	-- Tiny secondary ripple gives the water a layered displacement rather than
	-- one perfect ring.
	task.delay(
		0.045,
		function()

			spawnRipple(
				position,
				color,
				11,
				0.22,
				0.92,
				0.29,
				0.050,
				0.62
			)
		end
	)


	spawnDroplets(
		position,
		color,
		WALK_STEP_DROPLETS,
		0.42
	)
end


local function renderRunStep(
	position: Vector3,
	color: Color3
)

	-- Larger / stronger than Walk but still much smaller than Jump or Dash.
	spawnRipple(
		position,
		color,
		RUN_STEP_SEGMENTS,
		RUN_STEP_START_RADIUS,
		RUN_STEP_END_RADIUS,
		RUN_STEP_DURATION,
		RUN_STEP_WIDTH,
		0.30
	)


	task.delay(
		0.035,
		function()

			spawnRipple(
				position,
				color,
				14,
				0.26,
				1.34,
				0.31,
				0.070,
				0.51
			)
		end
	)


	spawnDroplets(
		position,
		color,
		RUN_STEP_DROPLETS,
		0.66
	)
end


local function renderIdle(
	position: Vector3,
	color: Color3
)

	spawnRipple(
		position,
		color,
		IDLE_SEGMENTS,
		IDLE_START_RADIUS,
		IDLE_END_RADIUS,
		IDLE_DURATION,
		IDLE_WIDTH,
		0.56
	)
end


local function renderJump(
	position: Vector3,
	color: Color3
)

	spawnRipple(
		position,
		color,
		JUMP_SEGMENTS,
		JUMP_START_RADIUS,
		JUMP_END_RADIUS,
		JUMP_DURATION,
		JUMP_WIDTH,
		0.22
	)


	task.delay(
		0.055,
		function()

			spawnRipple(
				position,
				color,
				18,
				0.34,
				2.02,
				0.40,
				0.09,
				0.43
			)
		end
	)


	spawnDroplets(
		position,
		color,
		14,
		1.0
	)
end


local function renderLand(
	position: Vector3,
	color: Color3
)

	spawnRipple(
		position,
		color,
		LAND_SEGMENTS,
		LAND_START_RADIUS,
		LAND_END_RADIUS,
		LAND_DURATION,
		LAND_WIDTH,
		0.25
	)


	task.delay(
		0.045,
		function()

			spawnRipple(
				position,
				color,
				16,
				0.30,
				1.72,
				0.38,
				0.08,
				0.46
			)
		end
	)


	spawnDroplets(
		position,
		color,
		10,
		0.82
	)
end


local function renderEvent(
	eventName: string,
	position: Vector3,
	color: Color3,
	direction: Vector3
)

	if eventName ==
		"WalkStep" then

		renderWalkStep(
			position,
			color
		)

	elseif eventName ==
		"RunStep" then

		renderRunStep(
			position,
			color
		)

		-- Compatibility if an old v4 client briefly exists during Studio QA.
	elseif eventName ==
		"Step" then

		renderRunStep(
			position,
			color
		)

	elseif eventName ==
		"Idle" then

		renderIdle(
			position,
			color
		)

	elseif eventName ==
		"Jump" then

		renderJump(
			position,
			color
		)

	elseif eventName ==
		"Land" then

		renderLand(
			position,
			color
		)

	elseif eventName ==
		"DashStart" then

		renderDashStart(
			position,
			color,
			direction
		)

	elseif eventName ==
		"DashLand" then

		renderDashLand(
			position,
			color
		)
	end
end


-- =========================
-- WATER QUERY
-- =========================

local function findWaterSurface(
	character: Model,
	origin: Vector3
): Vector3?

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{
			character
		}

	params.IgnoreWater =
		false


	local result =
		workspace:
		Raycast(
			origin
			+ Vector3.new(
				0,
				1.2,
				0
			),
			Vector3.new(
				0,
				-WATER_RAY_DISTANCE,
				0
			),
			params
		)


	if result
		and result.Material ==
		Enum.Material.Water then

		return result.Position
			+ result.Normal
			* 0.025
	end


	return nil
end


local function footBottomPosition(
	leg: BasePart
): Vector3

	return leg.Position
	- leg.CFrame.UpVector
		* (
			leg.Size.Y
			* 0.5
		)
end


local function numericAnimationId(
	animationId: string
): string?

	return string.match(
		animationId,
		"(%d+)$"
	)
end


-- =========================
-- NETWORK
-- =========================

local function sendLocalEvent(
	eventName: string,
	position: Vector3,
	color: Color3,
	direction: Vector3?
)

	local dir =
		direction
		or Vector3.zero


	renderEvent(
		eventName,
		position,
		color,
		dir
	)


	remote:
		FireServer(
			eventName,
			position,
			color,
			dir
		)
end


-- =========================
-- LOCAL CHARACTER
-- =========================

local heartbeatConnection: RBXScriptConnection? =
	nil

local waterJumpConnection: RBXScriptConnection? =
	nil

local waterWalkConnection: RBXScriptConnection? =
	nil

local animationPlayedConnection: RBXScriptConnection? =
	nil

local deathConnection: RBXScriptConnection? =
	nil

local trackConnections: {RBXScriptConnection} =
	{}


local function disconnectCharacter()

	for _,
		connection in ipairs({
			heartbeatConnection,
			waterJumpConnection,
			waterWalkConnection,
			animationPlayedConnection,
			deathConnection,
		}) do

		if connection then

			connection:
				Disconnect()
		end
	end


	for _,
		connection in ipairs(
			trackConnections
		) do

		connection:
			Disconnect()
	end


	table.clear(
		trackConnections
	)


	heartbeatConnection =
		nil

	waterJumpConnection =
		nil

	waterWalkConnection =
		nil

	animationPlayedConnection =
		nil

	deathConnection =
		nil
end


local function setupCharacter(
	character: Model
)

	disconnectCharacter()


	local humanoid =
		character:
		WaitForChild(
			"Humanoid"
		) :: Humanoid

	local rootPart =
		character:
		WaitForChild(
			"HumanoidRootPart"
		) :: BasePart

	local leftLeg =
		character:
		WaitForChild(
			"Left Leg"
		) :: BasePart

	local rightLeg =
		character:
		WaitForChild(
			"Right Leg"
		) :: BasePart

	local animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)
		or humanoid:
		WaitForChild(
			"Animator"
		) :: Animator


	local accumulated =
		0

	local lastIdleRipple =
		-math.huge

	local dashWasActive =
		false

	local dashDirection =
		Vector3.zero

	local useLeftIdleFoot =
		true

	local waterJumpWasActive =
		character:GetAttribute(
			"WaterJumping"
		) == true

	local lastRealAirborneTime =
		-math.huge

	local peakDownwardSpeed =
		0

	local lastWalkStepAt =
		-math.huge

	local lastRunStepAt =
		-math.huge

	local boundTracks: {[AnimationTrack]: boolean} =
		{}


	local function waterWalkingActive(): boolean

		return character:GetAttribute(
			"WaterWalking"
		) == true
			and character:GetAttribute(
				"ChakraFeetActive"
			) == true
	end


	local function findCurrentWaterSurface(): Vector3?

		return findWaterSurface(
			character,
			rootPart.Position
		)
	end


	local function emitAtFoot(
		eventName: string,
		leg: BasePart
	): boolean

		if not waterWalkingActive()
			or character:GetAttribute(
				"IsDashing"
			) == true then

			return false
		end


		local waterPosition =
			findWaterSurface(
				character,
				footBottomPosition(
					leg
				)
			)


		if not waterPosition then

			waterPosition =
				findCurrentWaterSurface()
		end


		if not waterPosition then
			return false
		end


		local velocity =
			rootPart.AssemblyLinearVelocity

		local direction =
			Vector3.new(
				velocity.X,
				0,
				velocity.Z
			)


		if direction.Magnitude >
			0.05 then

			direction =
				direction.Unit
		else

			direction =
				Vector3.zero
		end


		sendLocalEvent(
			eventName,
			waterPosition,
			getWaterTint(),
			direction
		)


		return true
	end


	local function onMarker(
		eventName: string,
		leg: BasePart
	)

		local now =
			os.clock()


		if eventName ==
			"WalkStep" then

			if now - lastWalkStepAt <
				SAME_INSTANT_STEP_DEDUPE then

				return
			end

			lastWalkStepAt =
				now

		elseif eventName ==
			"RunStep" then

			if now - lastRunStepAt <
				SAME_INSTANT_STEP_DEDUPE then

				return
			end

			lastRunStepAt =
				now
		end


		emitAtFoot(
			eventName,
			leg
		)
	end


	local function bindLocomotionTrack(
		track: AnimationTrack
	)

		if boundTracks[
			track
			] then

			return
		end


		local animation =
			track.Animation


		if not animation then
			return
		end


		local numericId =
			numericAnimationId(
				animation.AnimationId
			)


		local eventName: string?


		if numericId ==
			WALK_ANIMATION_NUMERIC_ID then

			eventName =
				"WalkStep"

		elseif numericId ==
			RUN_ANIMATION_NUMERIC_ID then

			eventName =
				"RunStep"

		else

			return
		end


		boundTracks[
		track
		] =
			true


		local leftConnection =
			track:
			GetMarkerReachedSignal(
				FOOT_LEFT_MARKER
			):
			Connect(
				function()

					onMarker(
						eventName :: string,
						leftLeg
					)
				end
			)


		local rightConnection =
			track:
			GetMarkerReachedSignal(
				FOOT_RIGHT_MARKER
			):
			Connect(
				function()

					onMarker(
						eventName :: string,
						rightLeg
					)
				end
			)


		local stoppedConnection: RBXScriptConnection?


		stoppedConnection =
			track.Stopped:
			Connect(
				function()

					leftConnection:
					Disconnect()

					rightConnection:
					Disconnect()


					if stoppedConnection then

						stoppedConnection:
						Disconnect()
					end


					boundTracks[
					track
					] =
					nil
				end
			)


		table.insert(
			trackConnections,
			leftConnection
		)

		table.insert(
			trackConnections,
			rightConnection
		)

		table.insert(
			trackConnections,
			stoppedConnection
		)
	end


	for _,
		track in ipairs(
			animator:
				GetPlayingAnimationTracks()
		) do

		bindLocomotionTrack(
			track
		)
	end


	animationPlayedConnection =
		animator.AnimationPlayed:
		Connect(
			function(
				track: AnimationTrack
			)

				bindLocomotionTrack(
					track
				)
			end
		)


	waterJumpConnection =
		character:
		GetAttributeChangedSignal(
			"WaterJumping"
		):
		Connect(
			function()

				local active =
				character:GetAttribute(
					"WaterJumping"
				) == true


				if active
					and not waterJumpWasActive then

					local waterPosition =
					findCurrentWaterSurface()


					if waterPosition then

						sendLocalEvent(
							"Jump",
							waterPosition,
							getWaterTint()
						)
					end
				end


				waterJumpWasActive =
				active
			end
		)


	waterWalkConnection =
		character:
		GetAttributeChangedSignal(
			"WaterWalking"
		):
		Connect(
			function()

				local active =
				character:GetAttribute(
					"WaterWalking"
				) == true


				if not active then
					return
				end


				if time()
					- lastRealAirborneTime
					<= LANDING_MEMORY_TIME
					and peakDownwardSpeed
					>= MIN_LANDING_DOWN_SPEED then

					local waterPosition =
					findCurrentWaterSurface()


					if waterPosition then

						sendLocalEvent(
							"Land",
							waterPosition,
							getWaterTint()
						)
					end
				end


				peakDownwardSpeed =
				0
			end
		)


	heartbeatConnection =
		RunService.Heartbeat:
		Connect(
			function(
				deltaTime: number
			)

				if humanoid.Health <= 0 then
					return
				end


				local state =
				humanoid:GetState()


				if state ==
					Enum.HumanoidStateType.Jumping
					or state ==
					Enum.HumanoidStateType.Freefall then

					lastRealAirborneTime =
					time()


					local downSpeed =
					math.max(
						0,
						-rootPart.AssemblyLinearVelocity.Y
					)


					peakDownwardSpeed =
					math.max(
						peakDownwardSpeed,
						downSpeed
					)
				end


				accumulated +=
				deltaTime


				if accumulated <
					DETECTION_INTERVAL then

					return
				end


				accumulated =
				0


				if not waterWalkingActive() then
					return
				end


				local waterPosition =
				findCurrentWaterSurface()


				local dashing =
				character:GetAttribute(
					"IsDashing"
				) == true


				if dashing then

					local velocity =
					rootPart.AssemblyLinearVelocity

					local flatVelocity =
					Vector3.new(
						velocity.X,
						0,
						velocity.Z
					)


					if flatVelocity.Magnitude >
						5 then

						dashDirection =
						flatVelocity.Unit
					end


					if not dashWasActive
						and waterPosition
						and dashDirection.Magnitude >
						0.05 then

						sendLocalEvent(
							"DashStart",
							waterPosition,
							getWaterTint(),
							dashDirection
						)
					end


					dashWasActive =
					true

					return
				end


				if dashWasActive then

					dashWasActive =
					false


					if waterPosition
						and waterWalkingActive() then

						sendLocalEvent(
							"DashLand",
							waterPosition,
							getWaterTint(),
							dashDirection
						)
					end


					dashDirection =
					Vector3.zero
				end


				local moving =
				humanoid.MoveDirection.Magnitude >
				0.05


				-- Step ripples are marker-driven now.
				-- Heartbeat is only responsible for standing/idle contact.
				if not moving then

					if time()
						- lastIdleRipple
						>= IDLE_RIPPLE_INTERVAL then

						lastIdleRipple =
						time()


						local leg =
						if useLeftIdleFoot
						then leftLeg
						else rightLeg


						useLeftIdleFoot =
						not useLeftIdleFoot


						emitAtFoot(
							"Idle",
							leg
						)
					end
				end
			end
		)


	deathConnection =
		humanoid.Died:
		Connect(
			function()

				peakDownwardSpeed =
				0
			end
		)
end


if player.Character then

	task.spawn(
		setupCharacter,
		player.Character
	)
end


player.CharacterAdded:
	Connect(
		setupCharacter
	)


-- =========================
-- REMOTE
-- =========================

remote.OnClientEvent:
	Connect(
		function(
			sourcePlayer: Player,
			eventName: string,
			position: Vector3,
			color: Color3,
			direction: Vector3
		)

			if not sourcePlayer
				or sourcePlayer ==
				player then

				return
			end


			renderEvent(
				eventName,
				position,
				color,
				direction
			)
		end
	)


print(
	"[WaterWalkVFXClient] READY v5"
		.. " | WalkStep=FootL+FootR"
		.. " | RunStep=FootL+FootR"
		.. " | DistanceStepLogic=REMOVED"
		.. " | IdleJumpLandDash=PRESERVED"
		.. " | Multiplayer=ON"
)
