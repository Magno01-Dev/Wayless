--!strict
-- SprintStepVFXController v1.7 - Marker-Synced Footsteps
-- DiabloStudios / Roblox
--
-- INSTALL:
-- StarterPlayer > StarterPlayerScripts > SprintStepVFXController [LocalScript]
--
-- PURPOSE:
-- Adds subtle sprint footstep dust using the same visual language as the
-- approved DashVFX v1.5:
--   ParticleEmitter
--   rbxasset://textures/particles/smoke_main.dds
--   Outer + Core layers
--
-- IMPORTANT:
-- This script DOES NOT modify SprintController, movement speed, animation,
-- stamina, FOV, WindTrail, Dash VFX, or gameplay logic.
--
-- Local player:
--   Uses IsSprinting from SprintController.
--
-- Other players:
--   Uses replicated physical movement speed as a cosmetic approximation so
--   sprint dust can still be seen even though IsSprinting is authored locally.
--
-- Ground only in v1:
--   no Air Dash / jump dust
--   no WaterWalking dust
--   no wall / ceiling dust

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local Debris =
	game:GetService("Debris")


local localPlayer =
	Players.LocalPlayer


local RUN_ANIMATION_NUMERIC_ID =
	"116142758807536"

local FOOT_LEFT_MARKER =
	"FootL"

local FOOT_RIGHT_MARKER =
	"FootR"


-- =========================
-- SETTINGS
-- =========================

local MAX_RENDER_DISTANCE =
	120

-- At SprintSpeed 40, this yields roughly 5-6 visible contacts per second.
local STEP_INTERVAL =
	0.18

-- Remote sprint approximation:
-- normal walk = 16
-- sprint = 40
-- dash = ~75
local REMOTE_SPRINT_MIN_SPEED =
	28

local REMOTE_SPRINT_MAX_SPEED =
	56

local LOCAL_MIN_MOVEMENT_SPEED =
	10

local FOOT_RAY_UP =
	0.55

local FOOT_RAY_DOWN =
	2.25

local ROOT_RAY_DOWN =
	4.0

local DUST_TEXTURE =
	"rbxasset://textures/particles/smoke_main.dds"


-- =========================
-- OUTER PARTICLES
-- =========================

local OUTER_COUNT =
	6

local OUTER_LIFETIME =
	NumberRange.new(
		0.22,
		0.34
	)

local OUTER_SPEED =
	NumberRange.new(
		0.9,
		2.0
	)


-- =========================
-- CORE PARTICLES
-- =========================

local CORE_COUNT =
	3

local CORE_LIFETIME =
	NumberRange.new(
		0.16,
		0.26
	)

local CORE_SPEED =
	NumberRange.new(
		0.45,
		1.10
	)


-- =========================
-- TYPES / STATE
-- =========================

type CharacterData = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	animator: Animator,
	leftLeg: BasePart?,
	rightLeg: BasePart?,
	activeRunTracks: {[AnimationTrack]: boolean},
	connections: {RBXScriptConnection},
}

local characters: {[Model]: CharacterData} =
	{}

local playerConnections: {[Player]: RBXScriptConnection} =
	{}


-- =========================
-- HELPERS
-- =========================

local function safeUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	if vector.Magnitude > 0.001 then
		return vector.Unit
	end

	if fallback.Magnitude > 0.001 then
		return fallback.Unit
	end

	return Vector3.new(
		0,
		0,
		-1
	)
end


local function horizontalVelocity(
	root: BasePart
): Vector3

	local velocity =
		root.AssemblyLinearVelocity

	return Vector3.new(
		velocity.X,
		0,
		velocity.Z
	)
end


local function cameraDistance(
	position: Vector3
): number

	local camera =
		workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	return (
		camera.CFrame.Position
		- position
	).Magnitude
end


local function getDustColor(
	result: RaycastResult
): Color3

	local instance =
		result.Instance

	if instance
		and instance:IsA("BasePart") then

		return instance.Color:Lerp(
			Color3.fromRGB(
				151,
				146,
				137
			),
			0.34
		)
	end

	local material =
		result.Material

	if material ==
		Enum.Material.Sand then

		return Color3.fromRGB(
			181,
			165,
			130
		)

	elseif material ==
		Enum.Material.Grass
		or material ==
		Enum.Material.Ground
		or material ==
		Enum.Material.LeafyGrass then

		return Color3.fromRGB(
			128,
			121,
			96
		)

	elseif material ==
		Enum.Material.Snow then

		return Color3.fromRGB(
			211,
			215,
			217
		)

	elseif material ==
		Enum.Material.Wood
		or material ==
		Enum.Material.WoodPlanks then

		return Color3.fromRGB(
			141,
			121,
			98
		)
	end

	return Color3.fromRGB(
		147,
		145,
		140
	)
end


local function makeEmitter(
	name: string,
	color: Color3
): ParticleEmitter

	local emitter =
		Instance.new("ParticleEmitter")

	emitter.Name =
		name

	emitter.Texture =
		DUST_TEXTURE

	emitter.Rate =
		0

	emitter.Enabled =
		false

	emitter.SpreadAngle =
		Vector2.new(
			132,
			132
		)

	emitter.Rotation =
		NumberRange.new(
			-180,
			180
		)

	emitter.RotSpeed =
		NumberRange.new(
			-55,
			55
		)

	emitter.Drag =
		4.1

	emitter.LightInfluence =
		0.28

	emitter.LightEmission =
		0.0

	emitter.Color =
		ColorSequence.new({
			ColorSequenceKeypoint.new(
				0,
				color:Lerp(
					Color3.fromRGB(
						235,
						234,
						230
					),
					0.16
				)
			),

			ColorSequenceKeypoint.new(
				0.58,
				color
			),

			ColorSequenceKeypoint.new(
				1,
				color:Lerp(
					Color3.fromRGB(
						118,
						115,
						109
					),
					0.14
				)
			),
		})

	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.4032
			),

			NumberSequenceKeypoint.new(
				0.28,
				0.4896
			),

			NumberSequenceKeypoint.new(
				0.72,
				0.9792
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	return emitter
end


local function emitFootPoof(
	contact: RaycastResult,
	moveDirection: Vector3
)

	if contact.Material ==
		Enum.Material.Water then

		return
	end

	local normal =
		safeUnit(
			contact.Normal,
			Vector3.yAxis
		)

	if normal:Dot(
		Vector3.yAxis
		) < 0.62 then

		return
	end

	local backward =
		-safeUnit(
			Vector3.new(
				moveDirection.X,
				0,
				moveDirection.Z
			),
			Vector3.new(
				0,
				0,
				-1
			)
		)

	local dustColor =
		getDustColor(
			contact
		)

	local anchor =
		Instance.new("Part")

	anchor.Name =
		"SprintStepDustAnchor"

	anchor.Size =
		Vector3.new(
			0.08,
			0.08,
			0.08
		)

	anchor.Transparency =
		1

	anchor.Anchored =
		true

	anchor.CanCollide =
		false

	anchor.CanTouch =
		false

	anchor.CanQuery =
		false

	anchor.CastShadow =
		false

	anchor.CFrame =
		CFrame.new(
			contact.Position
			+ normal * 0.055
			+ backward * 0.08
		)

	anchor.Parent =
		workspace

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"SprintStepDustAttachment"

	attachment.Parent =
		anchor


	local outer =
		makeEmitter(
			"SprintStepOuter",
			dustColor
		)

	outer.Lifetime =
		OUTER_LIFETIME

	outer.Speed =
		OUTER_SPEED

	outer.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.56
			),

			NumberSequenceKeypoint.new(
				0.24,
				0.98
			),

			NumberSequenceKeypoint.new(
				0.68,
				1.58
			),

			NumberSequenceKeypoint.new(
				1,
				2.05
			),
		})

	outer.Acceleration =
		backward * 3.1
		+ normal * 1.70

	outer.Parent =
		attachment


	local core =
		makeEmitter(
			"SprintStepCore",
			dustColor
		)

	core.Lifetime =
		CORE_LIFETIME

	core.Speed =
		CORE_SPEED

	core.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.38
			),

			NumberSequenceKeypoint.new(
				0.34,
				0.70
			),

			NumberSequenceKeypoint.new(
				1,
				1.18
			),
		})

	core.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.3168
			),

			NumberSequenceKeypoint.new(
				0.38,
				0.5184
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	core.Acceleration =
		backward * 2.3
		+ normal * 1.10

	core.Parent =
		attachment


	-- VERTICAL BODY:
	-- Same spawn point as the footstep. This does NOT move the cloud upward.
	-- It gives the poof more vertical mass immediately so the silhouette is
	-- taller from birth instead of becoming tall only after drifting.
	local body =
		makeEmitter(
			"SprintStepVerticalBody",
			dustColor
		)

	body.Lifetime =
		NumberRange.new(
			0.18,
			0.29
		)

	body.Speed =
		NumberRange.new(
			1.15,
			2.30
		)

	body.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.48
			),

			NumberSequenceKeypoint.new(
				0.22,
				0.88
			),

			NumberSequenceKeypoint.new(
				0.62,
				1.34
			),

			NumberSequenceKeypoint.new(
				1,
				1.76
			),
		})

	body.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.3456
			),

			NumberSequenceKeypoint.new(
				0.34,
				0.4896
			),

			NumberSequenceKeypoint.new(
				0.76,
				0.9504
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	body.SpreadAngle =
		Vector2.new(
			90,
			90
		)

	body.Acceleration =
		backward * 1.7
		+ normal * 3.15

	body.Parent =
		attachment


	outer:
		Emit(
			OUTER_COUNT
		)

	core:
		Emit(
			CORE_COUNT
		)

	body:
		Emit(
			4
		)


	Debris:AddItem(
		anchor,
		0.95
	)
end


local function makeRayParams(
	character: Model
): RaycastParams

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{character}

	params.IgnoreWater =
		false

	return params
end


local function raycastFoot(
	data: CharacterData,
	foot: BasePart?
): RaycastResult?

	local params =
		makeRayParams(
			data.character
		)

	if foot
		and foot.Parent then

		return workspace:
			Raycast(
				foot.Position
				+ Vector3.yAxis
				* FOOT_RAY_UP,
				-Vector3.yAxis
				* (
					FOOT_RAY_UP
					+ FOOT_RAY_DOWN
				),
				params
			)
	end

	return workspace:
		Raycast(
			data.root.Position,
			-Vector3.yAxis
			* ROOT_RAY_DOWN,
			params
		)
end


local function isLocalSprintActive(
	data: CharacterData,
	speed: number
): boolean

	if data.player ~=
		localPlayer then

		return false
	end

	if data.character:GetAttribute(
		"IsSprinting"
		) ~= true then

		return false
	end

	if data.character:GetAttribute(
		"IsDashing"
		) == true then

		return false
	end

	if data.character:GetAttribute(
		"WaterWalking"
		) == true then

		return false
	end

	if data.character:GetAttribute(
		"SurfaceWalking"
		) == true then

		return false
	end

	return speed >=
		LOCAL_MIN_MOVEMENT_SPEED
end


local function isRemoteSprintActive(
	data: CharacterData,
	speed: number
): boolean

	if data.player ==
		localPlayer then

		return false
	end

	if speed <
		REMOTE_SPRINT_MIN_SPEED
		or speed >
		REMOTE_SPRINT_MAX_SPEED then

		return false
	end

	local state =
		data.humanoid:GetState()

	if state ==
		Enum.HumanoidStateType.Jumping
		or state ==
		Enum.HumanoidStateType.Freefall
		or state ==
		Enum.HumanoidStateType.Swimming
		or state ==
		Enum.HumanoidStateType.Dead then

		return false
	end

	return true
end


local function shouldEmit(
	data: CharacterData
): (boolean, Vector3)

	if data.humanoid.Health <= 0 then

		return false,
			Vector3.zero
	end

	if cameraDistance(
		data.root.Position
		) > MAX_RENDER_DISTANCE then

		return false,
			Vector3.zero
	end

	local horizontal =
		horizontalVelocity(
			data.root
		)

	local speed =
		horizontal.Magnitude

	local active =
		isLocalSprintActive(
			data,
			speed
		)
		or isRemoteSprintActive(
			data,
			speed
		)

	return active,
		horizontal
end


local function emitMarkerStep(
	data: CharacterData,
	markerName: string
)

	if data.humanoid.Health <= 0 then
		return
	end


	if cameraDistance(
		data.root.Position
		) > MAX_RENDER_DISTANCE then

		return
	end


	if data.character:GetAttribute(
		"IsDashing"
		) == true
			or data.character:GetAttribute(
				"WaterWalking"
			) == true
			or data.character:GetAttribute(
				"SurfaceWalking"
			) == true then

		return
	end


	local foot =
		if markerName ==
		FOOT_LEFT_MARKER
		then data.leftLeg
		else data.rightLeg


	local contact =
		raycastFoot(
			data,
			foot
		)


	if not contact then

		contact =
			raycastFoot(
				data,
				nil
			)
	end


	if not contact
		or contact.Material ==
		Enum.Material.Water then

		return
	end


	local moveDirection =
		horizontalVelocity(
			data.root
		)


	if moveDirection.Magnitude <
		4 then

		return
	end


	emitFootPoof(
		contact,
		moveDirection
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


local function bindRunTrack(
	data: CharacterData,
	track: AnimationTrack
)

	if data.activeRunTracks[
		track
		] then

		return
	end


	data.activeRunTracks[
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

				emitMarkerStep(
					data,
					FOOT_LEFT_MARKER
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

				emitMarkerStep(
					data,
					FOOT_RIGHT_MARKER
				)
			end
		)


	local stoppedConnection

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


				data.activeRunTracks[
				track
				] =
				nil
			end
		)
end


local function inspectTrack(
	data: CharacterData,
	track: AnimationTrack
)

	local animation =
		track.Animation


	if not animation then
		return
	end


	if numericAnimationId(
		animation.AnimationId
		) ==
			RUN_ANIMATION_NUMERIC_ID then

		bindRunTrack(
			data,
			track
		)
	end
end


-- =========================
-- CHARACTER BINDING
-- =========================

local function cleanupCharacter(
	character: Model
)

	local data =
		characters[
	character
	]

	if not data then
		return
	end

	for _,
		connection in ipairs(
			data.connections
		) do

		connection:
			Disconnect()
	end

	characters[
	character
	] =
		nil
end


local function bindCharacter(
	player: Player,
	character: Model
)

	cleanupCharacter(
		character
	)

	task.spawn(
		function()

			local humanoid =
				character:
				WaitForChild(
					"Humanoid",
					8
				)

			local root =
				character:
				WaitForChild(
					"HumanoidRootPart",
					8
				)

			if not humanoid
				or not humanoid:IsA(
					"Humanoid"
				)
					or not root
					or not root:IsA(
						"BasePart"
					)
					or not character.Parent then

				return
			end

			local animator =
				humanoid:
				FindFirstChildOfClass(
					"Animator"
				)
				or humanoid:
				WaitForChild(
					"Animator",
					5
				)


			if not animator
				or not animator:IsA(
					"Animator"
				) then

				return
			end


			local leftLeg =
				character:
				FindFirstChild(
					"Left Leg"
				)

			local rightLeg =
				character:
				FindFirstChild(
					"Right Leg"
				)

			local data: CharacterData = {
				player = player,
				character = character,
				humanoid = humanoid,
				root = root,
				animator = animator,
				leftLeg =
					if leftLeg
					and leftLeg:IsA(
						"BasePart"
					)
					then leftLeg
					else nil,
				rightLeg =
					if rightLeg
					and rightLeg:IsA(
						"BasePart"
					)
					then rightLeg
					else nil,
				activeRunTracks = {},
				connections = {},
			}

			characters[
			character
			] =
				data


			for _,
				track in ipairs(
					animator:
						GetPlayingAnimationTracks()
				) do

				inspectTrack(
					data,
					track
				)
			end


			table.insert(
				data.connections,
				animator.AnimationPlayed:
					Connect(
						function(
							track: AnimationTrack
						)

							inspectTrack(
								data,
								track
							)
						end
					)
			)


			table.insert(
				data.connections,
				humanoid.Died:
					Connect(
						function()

							cleanupCharacter(
								character
							)
						end
					)
			)

			table.insert(
				data.connections,
				character.AncestryChanged:
					Connect(
						function(
							_child,
							parent
						)

							if parent == nil then

								cleanupCharacter(
									character
								)
							end
						end
					)
			)
		end
	)
end


local function bindPlayer(
	player: Player
)

	if playerConnections[
		player
		] then

		return
	end

	if player.Character then

		bindCharacter(
			player,
			player.Character
		)
	end

	playerConnections[
	player
	] =
		player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				bindCharacter(
					player,
					character
				)
			end
		)
end


local function unbindPlayer(
	player: Player
)

	local connection =
		playerConnections[
	player
	]

	if connection then
		connection:
			Disconnect()
	end

	playerConnections[
	player
	] =
		nil

	if player.Character then

		cleanupCharacter(
			player.Character
		)
	end
end


-- =========================
-- MARKER DRIVEN
-- =========================
--
-- No RenderStepped timer anymore.
-- Each cloud is emitted only when FootL / FootR is reached in the new Run
-- animation, so VFX follows the actual Moon Animator contacts.


for _,
	player in ipairs(
		Players:GetPlayers()
	) do

	bindPlayer(
		player
	)
end


Players.PlayerAdded:
	Connect(
		bindPlayer
	)


Players.PlayerRemoving:
	Connect(
		unbindPlayer
	)


print(
	"[SprintStepVFXController] READY v1.7"
		.. " | BalancedFastFadePoof=ON | Transparency=+40%vs_v1.3 | TerrainColor=STRONGER"
		.. " | OuterCore=ON"
		.. " | AlternatingFeet=ON"
		.. " | GroundOnly=ON | MarkerSync=FootL+FootR"
		.. " | MultiplayerVisual=ON"
)
