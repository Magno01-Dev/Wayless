--!strict
-- WalkFootstepAudioController v2 - Exact Marker Presence
-- ElDiabloLocoStudios / Roblox
--
-- StarterPlayer > StarterPlayerScripts > WalkFootstepAudioController [LocalScript]
--
-- WALK ANIMATION:
-- rbxassetid://75479783841702
--
-- REQUIRED MARKERS:
-- FootL
-- FootR
--
-- RULE:
-- exactly one Walk footstep sound per animation marker.
--
-- No timer cadence.
-- No Run audio.
-- No default Roblox movement audio.
--
-- Walk presence is intentionally quieter / shorter range than Run presence.

local Players =
	game:GetService("Players")

local ContentProvider =
	game:GetService("ContentProvider")


-- =========================
-- WALK ANIMATION
-- =========================

local WALK_ANIMATION_NUMERIC_ID =
	"75479783841702"

local FOOT_LEFT_MARKER =
	"FootL"

local FOOT_RIGHT_MARKER =
	"FootR"


-- =========================
-- WALK AUDIO BANK
-- =========================

local WALK_IDS = {
	"rbxassetid://101433001981076",
	"rbxassetid://138790661508180",
}


-- =========================
-- AUDIO TUNING
-- =========================

local WALK_VOLUME =
	0.40

local PLAYBACK_SPEED_MIN =
	0.985

local PLAYBACK_SPEED_MAX =
	1.02

local ROLLOFF_MIN_DISTANCE =
	3

local ROLLOFF_MAX_DISTANCE =
	26

local EMITTER_SIZE =
	2.0


-- =========================
-- MOVEMENT GUARDS
-- =========================

-- Prevent an underlying Walk track from producing audio if a remote character
-- is visibly moving at Sprint speed while the Run track is transitioning.
local MAX_WALK_AUDIO_SPEED =
	24


-- Only protects against nearly simultaneous duplicate callbacks caused by two
-- copies of the same Walk track overlapping during a transition.
-- This is NOT a cadence timer.
local SAME_INSTANT_DEDUPE =
	0.025


-- =========================
-- TYPES / STATE
-- =========================

type CharacterData = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	animator: Animator,
	sounds: {Sound},
	nextIndex: number,
	lastMarkerAt: number,
	activeWalkTracks: {[AnimationTrack]: boolean},
	connections: {RBXScriptConnection},
}

local characters: {[Model]: CharacterData} =
	{}

local playerConnections: {[Player]: RBXScriptConnection} =
	{}

local rng =
	Random.new()


-- =========================
-- HELPERS
-- =========================

local function numericAnimationId(
	animationId: string
): string?

	return string.match(
		animationId,
		"(%d+)$"
	)
end


local function horizontalSpeed(
	root: BasePart
): number

	local velocity =
		root.AssemblyLinearVelocity


	return Vector3.new(
		velocity.X,
		0,
		velocity.Z
	).Magnitude
end


local function makeSound(
	root: BasePart,
	index: number,
	soundId: string
): Sound

	local sound =
		Instance.new("Sound")

	sound.Name =
		"WalkFootstep_"
		.. tostring(index)

	sound.SoundId =
		soundId

	sound.Volume =
		WALK_VOLUME

	sound.Looped =
		false

	sound.PlaybackSpeed =
		1

	sound.RollOffMode =
		Enum.RollOffMode.InverseTapered

	sound.RollOffMinDistance =
		ROLLOFF_MIN_DISTANCE

	sound.RollOffMaxDistance =
		ROLLOFF_MAX_DISTANCE

	sound.EmitterSize =
		EMITTER_SIZE

	sound.Parent =
		root


	return sound
end


local function createBank(
	root: BasePart
): {Sound}

	local sounds: {Sound} =
		{}


	for index,
		soundId in ipairs(
			WALK_IDS
		) do

		table.insert(
			sounds,
			makeSound(
				root,
				index,
				soundId
			)
		)
	end


	task.spawn(
		function()

			pcall(
				function()

					ContentProvider:
						PreloadAsync(
							sounds
						)
				end
			)
		end
	)


	return sounds
end


local function stopBank(
	sounds: {Sound}
)

	for _,
		sound in ipairs(
			sounds
		) do

		if sound.IsPlaying then

			sound:
				Stop()

			sound.TimePosition =
				0
		end
	end
end


local function playStep(
	data: CharacterData
)

	stopBank(
		data.sounds
	)


	local sound =
		data.sounds[
	data.nextIndex
	]


	if not sound then
		return
	end


	sound.Volume =
		WALK_VOLUME

	sound.PlaybackSpeed =
		rng:NextNumber(
			PLAYBACK_SPEED_MIN,
			PLAYBACK_SPEED_MAX
		)

	sound.TimePosition =
		0


	sound:
		Play()


	data.nextIndex =
		if data.nextIndex == 1
		then 2
		else 1
end


local function blocked(
	data: CharacterData
): boolean

	if data.humanoid.Health <= 0 then

		return true
	end


	if data.character:GetAttribute(
		"IsDashing"
		) == true then

		return true
	end


	-- Local player publishes IsSprinting. For remote characters, the speed
	-- guard below provides the fallback.
	if data.character:GetAttribute(
		"IsSprinting"
		) == true then

		return true
	end


	if data.character:GetAttribute(
		"WaterWalking"
		) == true
			or data.character:GetAttribute(
				"SurfaceWalking"
			) == true then

		return true
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
		Enum.HumanoidStateType.Dead
		or state ==
		Enum.HumanoidStateType.Seated then

		return true
	end


	if horizontalSpeed(
		data.root
		) >
		MAX_WALK_AUDIO_SPEED then

		return true
	end


	return false
end


-- =========================
-- EXACT MARKERS
-- =========================

local function onWalkMarker(
	data: CharacterData
)

	if blocked(
		data
		) then

		return
	end


	if data.humanoid.MoveDirection.Magnitude <
		0.05 then

		return
	end


	local now =
		os.clock()


	if now - data.lastMarkerAt <
		SAME_INSTANT_DEDUPE then

		return
	end


	data.lastMarkerAt =
		now


	playStep(
		data
	)
end


local function bindWalkTrack(
	data: CharacterData,
	track: AnimationTrack
)

	if data.activeWalkTracks[
		track
		] then

		return
	end


	data.activeWalkTracks[
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

				onWalkMarker(
					data
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

				onWalkMarker(
					data
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


				data.activeWalkTracks[
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
			WALK_ANIMATION_NUMERIC_ID then

		bindWalkTrack(
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


	for _,
		sound in ipairs(
			data.sounds
		) do

		sound:
			Destroy()
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


			local data: CharacterData = {
				player = player,
				character = character,
				humanoid = humanoid,
				root = root,
				animator = animator,
				sounds =
					createBank(
						root
					),
				nextIndex = 1,
				lastMarkerAt = -math.huge,
				activeWalkTracks = {},
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

							if parent ==
								nil then

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
	"[WalkFootstepAudioController] READY v2"
		.. " | WalkID=75479783841702"
		.. " | ExactMarkers=FootL+FootR"
		.. " | Alternating1-2=ON"
		.. " | PresenceRange=26"
)
