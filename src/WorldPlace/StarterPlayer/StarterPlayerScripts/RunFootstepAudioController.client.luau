--!strict
-- RunFootstepAudioController v1.2 - Exact Marker Presence Footsteps
-- ElDiabloLocoStudios / Roblox
--
-- StarterPlayer > StarterPlayerScripts > RunFootstepAudioController [LocalScript]
--
-- DESIGN:
-- Exactly ONE Run footstep audio event per FootL / FootR animation marker.
--
-- No cadence timer.
-- No 0.20 throttle.
-- No Walk fallback inside this controller.
-- No looped Run sound.
--
-- The six Run sounds are pre-created and preloaded per character so the
-- marker callback only needs to restart an already-loaded Sound.
--
-- PRESENCE FOOTSTEPS:
-- These are spatial 3D sounds. Nearby players can hear a runner.
--
-- Roblox default HumanoidRootPart > Running sound is suppressed.

local Players =
	game:GetService("Players")

local ContentProvider =
	game:GetService("ContentProvider")


local localPlayer =
	Players.LocalPlayer


-- =========================
-- RUN ANIMATION
-- =========================

local RUN_ANIMATION_NUMERIC_ID =
	"116142758807536"

local FOOT_LEFT_MARKER =
	"FootL"

local FOOT_RIGHT_MARKER =
	"FootR"


-- =========================
-- GROUND RUN BANK
-- =========================

local RUN_GROUND_IDS = {
	"rbxassetid://79596529626387",
	"rbxassetid://123769768867577",
	"rbxassetid://89180104678550",
	"rbxassetid://99842982453302",
	"rbxassetid://99419393308712",
	"rbxassetid://115763325081722",
}


-- =========================
-- WATER BANK
-- =========================
--
-- Kept here for later replacement / QA.
-- Disabled because current source recordings were rejected.

local WATER_RUN_AUDIO_ENABLED =
	false

local RUN_WATER_IDS = {
	"rbxassetid://133034789986387",
	"rbxassetid://138102786276089",
	"rbxassetid://111652818325056",
	"rbxassetid://119998864119977",
	"rbxassetid://129798493411876",
	"rbxassetid://124083114624502",
}


-- =========================
-- AUDIO TUNING
-- =========================

local RUN_GROUND_VOLUME =
	0.50

local RUN_WATER_VOLUME =
	0.60

local PLAYBACK_SPEED_MIN =
	0.97

local PLAYBACK_SPEED_MAX =
	1.02

-- Presence-footstep range.
-- Raise MAX if you want running to reveal players from farther away.
local ROLLOFF_MIN_DISTANCE =
	4

local ROLLOFF_MAX_DISTANCE =
	42

local EMITTER_SIZE =
	2.5


-- =========================
-- DUPLICATE PROTECTION
-- =========================
--
-- This is NOT cadence throttling.
-- It only rejects two callbacks that happen essentially on the same instant,
-- which can occur if two identical Run tracks overlap during a transition.
--
-- Legitimate FootL -> FootR markers are not intentionally skipped.

local SAME_INSTANT_DEDUPE =
	0.025


-- =========================
-- TYPES / STATE
-- =========================

type SoundBank = {
	ground: {Sound},
	water: {Sound},
}

type CharacterData = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	animator: Animator,
	leftLeg: BasePart?,
	rightLeg: BasePart?,
	bank: SoundBank,
	lastGroundIndex: number?,
	lastWaterIndex: number?,
	lastMarkerAt: number,
	activeRunTracks: {[AnimationTrack]: boolean},
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


local function chooseNoRepeat(
	count: number,
	lastIndex: number?
): number

	if count <= 1 then
		return 1
	end


	local index =
		rng:NextInteger(
			1,
			count
		)


	if lastIndex
		and index == lastIndex then

		index =
			index % count
			+ 1
	end


	return index
end


local function makeSound(
	root: BasePart,
	name: string,
	soundId: string,
	volume: number
): Sound

	local sound =
		Instance.new("Sound")

	sound.Name =
		name

	sound.SoundId =
		soundId

	sound.Volume =
		volume

	sound.PlaybackSpeed =
		1

	sound.Looped =
		false

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
): SoundBank

	local ground: {Sound} =
		{}

	local water: {Sound} =
		{}


	for index,
		soundId in ipairs(
			RUN_GROUND_IDS
		) do

		table.insert(
			ground,
			makeSound(
				root,
				"RunGround_"
					.. tostring(index),
				soundId,
				RUN_GROUND_VOLUME
			)
		)
	end


	for index,
		soundId in ipairs(
			RUN_WATER_IDS
		) do

		table.insert(
			water,
			makeSound(
				root,
				"RunWater_"
					.. tostring(index),
				soundId,
				RUN_WATER_VOLUME
			)
		)
	end


	-- Preload once. The marker callback itself does not wait for loading.
	task.spawn(
		function()

			local allSounds =
				{}


			for _,
				sound in ipairs(
					ground
				) do

				table.insert(
					allSounds,
					sound
				)
			end


			for _,
				sound in ipairs(
					water
				) do

				table.insert(
					allSounds,
					sound
				)
			end


			pcall(
				function()

					ContentProvider:
						PreloadAsync(
							allSounds
						)
				end
			)
		end
	)


	return {
		ground = ground,
		water = water,
	}
end


local function stopBank(
	bank: {Sound}
)

	for _,
		sound in ipairs(
			bank
		) do

		if sound.IsPlaying then

			sound:
				Stop()

			sound.TimePosition =
				0
		end
	end
end


local function playBankSound(
	bank: {Sound},
	index: number,
	volume: number
)

	-- Guarantee one clean presence-footstep event at a time for this bank.
	-- This prevents long tails in a source clip from stacking into a double hit.
	stopBank(
		bank
	)


	local sound =
		bank[
	index
	]


	if not sound then
		return
	end


	sound.Volume =
		volume

	sound.PlaybackSpeed =
		rng:NextNumber(
			PLAYBACK_SPEED_MIN,
			PLAYBACK_SPEED_MAX
		)

	sound.TimePosition =
		0


	sound:
		Play()
end


-- =========================
-- DEFAULT ROBLOX RUNNING
-- =========================

local function silenceDefaultRunningSound(
	sound: Sound
)

	local enforcing =
		false


	local function apply()

		if enforcing
			or not sound.Parent then

			return
		end


		enforcing =
			true

		sound.Volume =
			0

		sound.SoundId =
			""

		enforcing =
			false
	end


	apply()


	sound:GetPropertyChangedSignal(
		"Volume"
	):
		Connect(
			apply
		)


	sound:GetPropertyChangedSignal(
		"SoundId"
	):
		Connect(
			apply
		)
end


local function watchDefaultRunning(
	data: CharacterData
)

	local existing =
		data.root:
		FindFirstChild(
			"Running"
		)


	if existing
		and existing:IsA(
			"Sound"
		) then

		silenceDefaultRunningSound(
			existing
		)
	end


	table.insert(
		data.connections,
		data.root.ChildAdded:
			Connect(
				function(
					child: Instance
				)

					if child.Name ==
						"Running"
						and child:IsA(
							"Sound"
						) then

						silenceDefaultRunningSound(
							child
						)
					end
				end
			)
	)
end


-- =========================
-- WATER DETECTION
-- =========================

local function footRaycast(
	data: CharacterData,
	foot: BasePart?
): RaycastResult?

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{data.character}

	params.IgnoreWater =
		false

	params.RespectCanCollide =
		false


	local origin =
		if foot
		and foot.Parent
		then foot.Position
		+ Vector3.yAxis * 0.65
		else data.root.Position


	return workspace:
		Raycast(
			origin,
			-Vector3.yAxis * 4.2,
			params
		)
end


local function isWaterStep(
	data: CharacterData,
	foot: BasePart?
): boolean

	if data.character:GetAttribute(
		"WaterWalking"
		) == true then

		return true
	end


	local hit =
		footRaycast(
			data,
			foot
		)


	return hit ~= nil
		and hit.Material ==
		Enum.Material.Water
end


-- =========================
-- EXACT RUN MARKERS
-- =========================

local function canPlayRunStep(
	data: CharacterData
): boolean

	if data.humanoid.Health <= 0 then
		return false
	end


	if data.character:GetAttribute(
		"IsDashing"
		) == true then

		return false
	end


	return true
end


local function onRunMarker(
	data: CharacterData,
	markerName: string
)

	if not canPlayRunStep(
		data
		) then

		return
	end


	local now =
		os.clock()


	-- Only reject essentially simultaneous duplicate callbacks.
	if now - data.lastMarkerAt <
		SAME_INSTANT_DEDUPE then

		return
	end


	data.lastMarkerAt =
		now


	local foot =
		if markerName ==
		FOOT_LEFT_MARKER
		then data.leftLeg
		else data.rightLeg


	if isWaterStep(
		data,
		foot
		) then

		if not WATER_RUN_AUDIO_ENABLED then
			return
		end


		local index =
			chooseNoRepeat(
				#data.bank.water,
				data.lastWaterIndex
			)


		data.lastWaterIndex =
			index


		playBankSound(
			data.bank.water,
			index,
			RUN_WATER_VOLUME
		)

	else

		local index =
			chooseNoRepeat(
				#data.bank.ground,
				data.lastGroundIndex
			)


		data.lastGroundIndex =
			index


		playBankSound(
			data.bank.ground,
			index,
			RUN_GROUND_VOLUME
		)
	end
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

				onRunMarker(
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

				onRunMarker(
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


	for _,
		sound in ipairs(
			data.bank.ground
		) do

		sound:
			Destroy()
	end


	for _,
		sound in ipairs(
			data.bank.water
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
				bank =
					createBank(
						root
					),
				lastGroundIndex = nil,
				lastWaterIndex = nil,
				lastMarkerAt = -math.huge,
				activeRunTracks = {},
				connections = {},
			}


			characters[
			character
			] =
				data


			watchDefaultRunning(
				data
			)


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
	"[RunFootstepAudioController] READY v1.2"
		.. " | ExactMarkerAudio=ON"
		.. " | PreloadedBank=ON"
		.. " | WalkFallback=REMOVED"
		.. " | WaterRunAudio=OFF"
		.. " | PresenceRange=" .. tostring(ROLLOFF_MAX_DISTANCE)
		.. " | RobloxRunningSound=SUPPRESSED"
)
