--!strict
-- TreeJumpPolishController v1 - Presence 3D
-- ElDiabloLocoStudios / Roblox
--
-- INSTALL:
-- StarterPlayer > StarterPlayerScripts > TreeJumpPolishController [LocalScript]
--
-- Uses the EXISTING server-approved TreeJumpReplicate event.
-- No new RemoteEvent and no TreeJumpServer replacement.
--
-- Visual language:
-- Launch:
--   directional surface-color smoke + small material chips
-- Arrival:
--   smaller contact burst + fewer chips
--
-- Audio:
--   existing Tree Jump sounds converted to spatial 3D presence audio
--
-- IMPORTANT:
-- This script does NOT touch camera, FOV, DOF, physics, trajectory,
-- targeting, animation, cooldowns or WindTrail.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Debris =
	game:GetService("Debris")

local ContentProvider =
	game:GetService("ContentProvider")

local SoundService =
	game:GetService("SoundService")


local localPlayer =
	Players.LocalPlayer


local replicateEvent =
	ReplicatedStorage:
	WaitForChild(
		"TreeJumpReplicate"
	) :: RemoteEvent


-- =========================
-- SERVER-MATCHED TRAVEL TIMING
-- =========================
-- Read-only mirror for cosmetic arrival timing.
-- TreeJumpServer itself is untouched.

local TREE_JUMP_SPEED =
	160

local MIN_JUMP_DURATION =
	0.20

local MAX_JUMP_DURATION =
	1.60


-- =========================
-- AUDIO
-- =========================

local LAUNCH_SOUND_ID =
	"rbxassetid://73544689711793"

local LAND_SOUND_ID =
	"rbxassetid://106345699720712"


local LAUNCH_AUDIO = {
	Volume = 0.62,
	PlaybackSpeed = 1.00,
	RollOffMinDistance = 5,
	RollOffMaxDistance = 72,
	EmitterSize = 3.0,
}


local LAND_AUDIO = {
	Volume = 0.46,
	PlaybackSpeed = 1.02,
	RollOffMinDistance = 4,
	RollOffMaxDistance = 52,
	EmitterSize = 2.5,
}


-- =========================
-- VFX
-- =========================

local SMOKE_TEXTURE =
	"rbxasset://textures/particles/smoke_main.dds"


local LAUNCH_OUTER_COUNT =
	8

local LAUNCH_CORE_COUNT =
	5

local LAUNCH_CHIP_COUNT =
	6


local LAND_OUTER_COUNT =
	5

local LAND_CORE_COUNT =
	3

local LAND_CHIP_COUNT =
	3


-- Arrival is skipped if the observed character was cancelled and never
-- actually reached the server-approved destination.
local LANDING_VISUAL_TOLERANCE =
	18


local rng =
	Random.new()


-- =========================
-- PRELOAD AUDIO
-- =========================

task.spawn(
	function()

		local launch =
			Instance.new("Sound")

		launch.SoundId =
			LAUNCH_SOUND_ID

		launch.Volume =
			0

		launch.Parent =
			SoundService


		local land =
			Instance.new("Sound")

		land.SoundId =
			LAND_SOUND_ID

		land.Volume =
			0

		land.Parent =
			SoundService


		pcall(
			function()

				ContentProvider:
					PreloadAsync({
						launch,
						land,
					})
			end
		)


		launch:
			Destroy()

		land:
			Destroy()
	end
)


-- =========================
-- COLOR / SURFACE
-- =========================

type SurfaceInfo = {
	position: Vector3,
	normal: Vector3,
	color: Color3,
	material: Enum.Material,
}


local function terrainMaterialColor(
	material: Enum.Material
): Color3

	local terrain =
		workspace:
		FindFirstChildOfClass(
			"Terrain"
		)


	if terrain then

		local ok,
			result =
			pcall(
				function()

					return terrain:
					GetMaterialColor(
						material
					)
				end
			)


		if ok
			and typeof(result) ==
			"Color3" then

			return result
		end
	end


	return Color3.fromRGB(
		120,
		100,
		80
	)
end


local function resultColor(
	result: RaycastResult
): Color3

	local instance =
		result.Instance


	if instance
		and instance:IsA(
			"BasePart"
		) then

		return instance.Color
	end


	return terrainMaterialColor(
		result.Material
	)
end


local function raycastSurface(
	character: Model,
	origin: Vector3,
	direction: Vector3
): SurfaceInfo?

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{character}

	params.IgnoreWater =
		false


	local result =
		workspace:
		Raycast(
			origin,
			direction,
			params
		)


	if not result then
		return nil
	end


	return {
		position =
			result.Position,
		normal =
			result.Normal,
		color =
			resultColor(
				result
			),
		material =
			result.Material,
	}
end


local function findLaunchSurface(
	character: Model,
	root: BasePart
): SurfaceInfo

	-- If the character was Chakra Feet surface-walking, use that contact plane.
	local surfaceNormal =
		character:GetAttribute(
			"SurfaceNormal"
		)


	if character:GetAttribute(
		"SurfaceWalking"
		) == true
			and typeof(surfaceNormal) ==
			"Vector3"
			and surfaceNormal.Magnitude >
		0.5 then

		local normal =
			surfaceNormal.Unit


		local result =
			raycastSurface(
				character,
				root.Position
				+ normal
				* 0.5,
				-normal
				* 8
			)


		if result then
			return result
		end
	end


	local down =
		raycastSurface(
			character,
			root.Position
			+ Vector3.new(
				0,
				1.0,
				0
			),
			Vector3.new(
				0,
				-9,
				0
			)
		)


	if down then
		return down
	end


	return {
		position =
			root.Position
		- Vector3.new(
			0,
			2.8,
			0
		),
		normal =
			Vector3.yAxis,
		color =
			Color3.fromRGB(
				112,
				86,
				61
			),
		material =
			Enum.Material.Wood,
	}
end


local function findLandingSurface(
	character: Model,
	landingPosition: Vector3
): SurfaceInfo

	local down =
		raycastSurface(
			character,
			landingPosition
			+ Vector3.new(
				0,
				1.0,
				0
			),
			Vector3.new(
				0,
				-12,
				0
			)
		)


	if down then
		return down
	end


	return {
		position =
			landingPosition
		- Vector3.new(
			0,
			3.0,
			0
		),
		normal =
			Vector3.yAxis,
		color =
			Color3.fromRGB(
				112,
				86,
				61
			),
		material =
			Enum.Material.Wood,
	}
end


-- =========================
-- ANCHOR / AUDIO
-- =========================

local function safeDirection(
	value: Vector3,
	fallback: Vector3
): Vector3

	if value.Magnitude >
		0.01 then

		return value.Unit
	end


	return fallback
end


local function makeOrientedAnchor(
	position: Vector3,
	travelDirection: Vector3,
	surfaceNormal: Vector3
): Part

	local forward =
		safeDirection(
			travelDirection,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local up =
		safeDirection(
			surfaceNormal,
			Vector3.yAxis
		)


	-- Avoid lookAt degeneracy if movement is almost parallel to surface normal.
	if math.abs(
		forward:
			Dot(
				up
			)
		) >
		0.94 then

		up =
			Vector3.yAxis


		if math.abs(
			forward:
				Dot(
					up
				)
			) >
			0.94 then

			up =
				Vector3.xAxis
		end
	end


	local anchor =
		Instance.new("Part")

	anchor.Name =
		"TreeJumpPolishAnchor"

	anchor.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)

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

	anchor.Transparency =
		1

	anchor.CFrame =
		CFrame.lookAt(
			position,
			position + forward,
			up
		)

	anchor.Parent =
		workspace


	return anchor
end


local function playSpatialSound(
	anchor: BasePart,
	name: string,
	soundId: string,
	config: {[string]: number}
)

	local sound =
		Instance.new("Sound")

	sound.Name =
		name

	sound.SoundId =
		soundId

	sound.Volume =
		config.Volume

	sound.PlaybackSpeed =
		config.PlaybackSpeed

	sound.RollOffMode =
		Enum.RollOffMode.InverseTapered

	sound.RollOffMinDistance =
		config.RollOffMinDistance

	sound.RollOffMaxDistance =
		config.RollOffMaxDistance

	sound.EmitterSize =
		config.EmitterSize

	sound.Parent =
		anchor


	sound:
		Play()


	sound.Ended:
		Once(
			function()

				if sound.Parent then

					sound:
					Destroy()
				end
			end
		)


	Debris:AddItem(
		sound,
		5
	)
end


-- =========================
-- PARTICLES
-- =========================

local function softSurfaceColor(
	color: Color3,
	whiteMix: number
): Color3

	return color:
		Lerp(
			Color3.new(
				1,
				1,
				1
			),
			whiteMix
		)
end


local function makeOuterEmitter(
	anchor: BasePart,
	color: Color3,
	isLanding: boolean
): ParticleEmitter

	local emitter =
		Instance.new(
			"ParticleEmitter"
		)

	emitter.Name =
		"TreeJumpOuter"

	emitter.Texture =
		SMOKE_TEXTURE

	emitter.Enabled =
		false

	emitter.Rate =
		0

	emitter.EmissionDirection =
		Enum.NormalId.Back

	emitter.SpreadAngle =
		if isLanding
		then Vector2.new(
			72,
			54
		)
		else Vector2.new(
			46,
			38
		)

	emitter.Speed =
		if isLanding
		then NumberRange.new(
			3.8,
			8.0
		)
		else NumberRange.new(
			8.0,
			15.0
		)

	emitter.Lifetime =
		if isLanding
		then NumberRange.new(
			0.20,
			0.34
		)
		else NumberRange.new(
			0.24,
			0.42
		)

	emitter.RotSpeed =
		NumberRange.new(
			-55,
			55
		)

	emitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	emitter.Drag =
		if isLanding
		then 5
		else 3.5

	emitter.LightInfluence =
		0

	emitter.Color =
		ColorSequence.new(
			softSurfaceColor(
				color,
				0.26
			)
		)

	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				if isLanding
				then 0.48
				else 0.38
			),

			NumberSequenceKeypoint.new(
				0.35,
				if isLanding
				then 0.60
				else 0.51
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	emitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				if isLanding
				then 0.25
				else 0.34
			),

			NumberSequenceKeypoint.new(
				0.52,
				if isLanding
				then 0.70
				else 1.02
			),

			NumberSequenceKeypoint.new(
				1,
				if isLanding
				then 0.95
				else 1.34
			),
		})

	emitter.Parent =
		anchor


	return emitter
end


local function makeCoreEmitter(
	anchor: BasePart,
	color: Color3,
	isLanding: boolean
): ParticleEmitter

	local emitter =
		Instance.new(
			"ParticleEmitter"
		)

	emitter.Name =
		"TreeJumpCore"

	emitter.Texture =
		SMOKE_TEXTURE

	emitter.Enabled =
		false

	emitter.Rate =
		0

	emitter.EmissionDirection =
		Enum.NormalId.Back

	emitter.SpreadAngle =
		if isLanding
		then Vector2.new(
			58,
			45
		)
		else Vector2.new(
			32,
			28
		)

	emitter.Speed =
		if isLanding
		then NumberRange.new(
			5.0,
			9.0
		)
		else NumberRange.new(
			11,
			19
		)

	emitter.Lifetime =
		if isLanding
		then NumberRange.new(
			0.14,
			0.24
		)
		else NumberRange.new(
			0.15,
			0.28
		)

	emitter.Drag =
		4

	emitter.LightInfluence =
		0

	emitter.Color =
		ColorSequence.new(
			softSurfaceColor(
				color,
				0.12
			)
		)

	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				if isLanding
				then 0.35
				else 0.24
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	emitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				if isLanding
				then 0.16
				else 0.20
			),

			NumberSequenceKeypoint.new(
				1,
				if isLanding
				then 0.52
				else 0.72
			),
		})

	emitter.Parent =
		anchor


	return emitter
end


local function createChip(
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	surfaceNormal: Vector3,
	backDirection: Vector3,
	sideDirection: Vector3,
	power: number
)

	local chip =
		Instance.new("Part")

	chip.Name =
		"TreeJumpSurfaceChip"

	chip.Size =
		Vector3.new(
			rng:NextNumber(
				0.06,
				0.13
			),
			rng:NextNumber(
				0.025,
				0.055
			),
			rng:NextNumber(
				0.12,
				0.28
			)
		)

	chip.Color =
		color

	chip.Material =
		if material ==
		Enum.Material.Air
		then Enum.Material.Wood
		else material

	chip.Anchored =
		false

	chip.CanCollide =
		false

	chip.CanTouch =
		false

	chip.CanQuery =
		false

	chip.CastShadow =
		false

	chip.Massless =
		true

	chip.CFrame =
		CFrame.new(
			position
			+ surfaceNormal
			* 0.05
		)
		* CFrame.Angles(
			rng:NextNumber(
				0,
				math.pi
			),
			rng:NextNumber(
				0,
				math.pi
			),
			rng:NextNumber(
				0,
				math.pi
			)
		)

	chip.Parent =
		workspace


	local backAmount =
		rng:NextNumber(
			4.0,
			10.0
		)
		* power

	local normalAmount =
		rng:NextNumber(
			3.0,
			8.0
		)
		* power

	local sideAmount =
		rng:NextNumber(
			-4.0,
			4.0
		)
		* power


	chip.AssemblyLinearVelocity =
		backDirection
		* backAmount
		+ surfaceNormal
		* normalAmount
		+ sideDirection
		* sideAmount


	chip.AssemblyAngularVelocity =
		Vector3.new(
			rng:NextNumber(
				-14,
				14
			),
			rng:NextNumber(
				-14,
				14
			),
			rng:NextNumber(
				-14,
				14
			)
		)


	Debris:AddItem(
		chip,
		rng:NextNumber(
			0.34,
			0.58
		)
	)
end


local function spawnChips(
	surface: SurfaceInfo,
	travelDirection: Vector3,
	count: number,
	power: number
)

	local normal =
		safeDirection(
			surface.normal,
			Vector3.yAxis
		)


	local backward =
		-travelDirection


	-- Project backward impulse onto the contact plane.
	backward =
		backward
	- normal
		* backward:
		Dot(
			normal
		)


	if backward.Magnitude <
		0.05 then

		backward =
			Vector3.new(
				1,
				0,
				0
			)
	else

		backward =
			backward.Unit
	end


	local side =
		backward:
		Cross(
			normal
		)


	if side.Magnitude <
		0.05 then

		side =
			Vector3.zAxis
	else

		side =
			side.Unit
	end


	for _ = 1,
		count do

		createChip(
			surface.position,
			surface.color,
			surface.material,
			normal,
			backward,
			side,
			power
		)
	end
end


local function spawnBurst(
	surface: SurfaceInfo,
	travelDirection: Vector3,
	isLanding: boolean
): Part

	local anchor =
		makeOrientedAnchor(
			surface.position
			+ surface.normal
			* 0.04,
			travelDirection,
			surface.normal
		)


	local outer =
		makeOuterEmitter(
			anchor,
			surface.color,
			isLanding
		)


	local core =
		makeCoreEmitter(
			anchor,
			surface.color,
			isLanding
		)


	outer:
		Emit(
			if isLanding
			then LAND_OUTER_COUNT
			else LAUNCH_OUTER_COUNT
		)


	core:
		Emit(
			if isLanding
			then LAND_CORE_COUNT
			else LAUNCH_CORE_COUNT
		)


	spawnChips(
		surface,
		travelDirection,
		if isLanding
			then LAND_CHIP_COUNT
			else LAUNCH_CHIP_COUNT,
		if isLanding
			then 0.62
			else 1.0
	)


	-- Keep the world anchor alive long enough for the spatial sound tail.
	-- Particle emitters themselves finish much earlier.
	Debris:AddItem(
		anchor,
		4.0
	)


	return anchor
end


-- =========================
-- APPROVED MULTIPLAYER EVENT
-- =========================

local lastEventAt: {[Player]: number} =
	{}


replicateEvent.OnClientEvent:
	Connect(
		function(
			jumpingPlayer: Player,
			landingPosition: Vector3
		)

			if typeof(
				jumpingPlayer
				) ~= "Instance"
				or not jumpingPlayer:IsA(
					"Player"
				)
				or typeof(
					landingPosition
				) ~= "Vector3" then

				return
			end


			-- Defensive local duplicate guard only.
			local now =
			os.clock()

			local previous =
			lastEventAt[
			jumpingPlayer
			]
			or -math.huge


			if now - previous <
				0.08 then

				return
			end


			lastEventAt[
			jumpingPlayer
			] =
			now


			local character =
			jumpingPlayer.Character


			if not character then
				return
			end


			local humanoid =
			character:
			FindFirstChildOfClass(
				"Humanoid"
			)


			local root =
			character:
			FindFirstChild(
				"HumanoidRootPart"
			)


			if not humanoid
				or humanoid.Health <= 0
				or not root
				or not root:IsA(
					"BasePart"
				) then

				return
			end


			local startPosition =
			root.Position


			local travel =
			landingPosition
			- startPosition


			if travel.Magnitude <
				0.5 then

				return
			end


			local travelDirection =
			travel.Unit


			local duration =
			math.clamp(
				travel.Magnitude
				/ TREE_JUMP_SPEED,
				MIN_JUMP_DURATION,
				MAX_JUMP_DURATION
			)


			-- =========================
			-- LAUNCH
			-- =========================

			local launchSurface =
			findLaunchSurface(
				character,
				root
			)


			local launchAnchor =
			spawnBurst(
				launchSurface,
				travelDirection,
				false
			)


			playSpatialSound(
				launchAnchor,
				"TreeJumpLaunchPresence",
				LAUNCH_SOUND_ID,
				LAUNCH_AUDIO
			)


			-- =========================
			-- ARRIVAL
			-- =========================

			task.delay(
				duration,
				function()

					local currentCharacter =
					jumpingPlayer.Character


					if currentCharacter ~=
						character
						or not character.Parent then

						return
					end


					local currentRoot =
					character:
					FindFirstChild(
						"HumanoidRootPart"
					)


					local currentHumanoid =
					character:
					FindFirstChildOfClass(
						"Humanoid"
					)


					if not currentRoot
						or not currentRoot:IsA(
							"BasePart"
						)
						or not currentHumanoid
						or currentHumanoid.Health <=
						0 then

						return
					end


					-- If another system cancelled Tree Jump, don't fake a landing
					-- at a destination the character never reached.
					if (
						currentRoot.Position
						- landingPosition
						).Magnitude >
						LANDING_VISUAL_TOLERANCE then

						return
					end


					local landingSurface =
					findLandingSurface(
						character,
						landingPosition
					)


					local landingAnchor =
					spawnBurst(
						landingSurface,
						travelDirection,
						true
					)


					playSpatialSound(
						landingAnchor,
						"TreeJumpLandPresence",
						LAND_SOUND_ID,
						LAND_AUDIO
					)
				end
			)
		end
	)


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			lastEventAt[
			player
			] =
			nil
		end
	)


print(
	"[TreeJumpPolishController] READY v1"
		.. " | ApprovedReplicate=ON"
		.. " | LaunchPresence3D=72"
		.. " | LandPresence3D=52"
		.. " | FOV/DOF=UNTOUCHED"
)
