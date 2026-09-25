--!strict
-- WaterRunAudioController v1.1 - Two-Step Clip / One Trigger Per Run Cycle
-- ElDiabloLocoStudios / Roblox
--
-- INSTALL:
-- StarterPlayer > StarterPlayerScripts > WaterRunAudioController [LocalScript]
--
-- Additive audio only.
-- Does NOT modify SurfaceController, SprintController, WaterWalkVFXClient,
-- or WaterWalkVFXServer.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local WATER_RUN_SOUND_ID = "rbxassetid://117277198490421"

local WATER_RUN_VOLUME = 0.52
local WATER_RUN_MIN_DISTANCE = 6
local WATER_RUN_MAX_DISTANCE = 58
local WATER_RUN_PITCH_MIN = 0.97
local WATER_RUN_PITCH_MAX = 1.03

local RUN_ANIMATION_IDS: {[string]: boolean} = {
	["116142758807536"] = true, -- Forward
	["96610792244949"] = true,  -- Left
	["121603680342672"] = true, -- Right
}

local FOOT_LEFT_MARKER = "FootL"
local SAME_INSTANT_STEP_DEDUPE = 0.025

local function numericAnimationId(animationId: string): string?
	return string.match(animationId, "(%d+)$")
end

local function waterRunAllowed(character: Model): boolean
	if character:GetAttribute("WaterWalking") ~= true then
		return false
	end

	if character:GetAttribute("ChakraFeetActive") ~= true then
		return false
	end

	if character:GetAttribute("IsDashing") == true then
		return false
	end

	if character:GetAttribute("WaterJumping") == true then
		return false
	end

	if character:GetAttribute("IsDowned") == true
		or character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true then

		return false
	end

	return true
end

local function playWaterRunContact(leg: BasePart)
	local sound = Instance.new("Sound")
	sound.Name = "WaterRunStep"
	sound.SoundId = WATER_RUN_SOUND_ID
	sound.Volume = WATER_RUN_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = WATER_RUN_MIN_DISTANCE
	sound.RollOffMaxDistance = WATER_RUN_MAX_DISTANCE
	sound.PlaybackSpeed =
		WATER_RUN_PITCH_MIN
		+ math.random()
		* (WATER_RUN_PITCH_MAX - WATER_RUN_PITCH_MIN)

	sound.Parent = leg
	sound:Play()

	Debris:AddItem(sound, 4)
end

type CharacterObserver = {
	character: Model,
	connections: {RBXScriptConnection},
	boundTracks: {[AnimationTrack]: boolean},
	lastStepAt: number,
}

local observers: {[Player]: CharacterObserver} = {}
local playerLevelConnections: {[Player]: {RBXScriptConnection}} = {}

local function disconnectObserver(player: Player)
	local observer = observers[player]

	if not observer then
		return
	end

	for _, connection in ipairs(observer.connections) do
		connection:Disconnect()
	end

	table.clear(observer.connections)
	table.clear(observer.boundTracks)
	observers[player] = nil
end

local function disconnectPlayerLevel(player: Player)
	local connections = playerLevelConnections[player]

	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
	playerLevelConnections[player] = nil
end

local function observeCharacter(player: Player, character: Model)
	disconnectObserver(player)

	local humanoid =
		character:WaitForChild("Humanoid") :: Humanoid

	local animator =
		humanoid:FindFirstChildOfClass("Animator")
		or humanoid:WaitForChild("Animator") :: Animator

	local leftLeg =
		character:WaitForChild("Left Leg") :: BasePart

	local rightLeg =
		character:WaitForChild("Right Leg") :: BasePart

	local observer: CharacterObserver = {
		character = character,
		connections = {},
		boundTracks = {},
		lastStepAt = -math.huge,
	}

	observers[player] = observer

	local function onFootContact(leg: BasePart)
		if humanoid.Health <= 0 then
			return
		end

		if not waterRunAllowed(character) then
			return
		end

		if humanoid.MoveDirection.Magnitude <= 0.05 then
			return
		end

		local now = os.clock()

		if now - observer.lastStepAt < SAME_INSTANT_STEP_DEDUPE then
			return
		end

		observer.lastStepAt = now
		playWaterRunContact(leg)
	end

	local function bindTrack(track: AnimationTrack)
		if observer.boundTracks[track] then
			return
		end

		local animation = track.Animation

		if not animation then
			return
		end

		local numericId =
			numericAnimationId(animation.AnimationId)

		if not numericId
			or RUN_ANIMATION_IDS[numericId] ~= true then

			return
		end

		observer.boundTracks[track] = true

		-- The audio asset already contains two consecutive foot contacts.
		-- Trigger it once at FootL; its internal second step covers FootR.
		local cycleConnection =
			track:GetMarkerReachedSignal(FOOT_LEFT_MARKER):Connect(function()
				onFootContact(leftLeg)
			end)

		local stoppedConnection: RBXScriptConnection?

		stoppedConnection = track.Stopped:Connect(function()
			cycleConnection:Disconnect()

			if stoppedConnection then
				stoppedConnection:Disconnect()
			end

			observer.boundTracks[track] = nil
		end)

		table.insert(observer.connections, cycleConnection)
		table.insert(observer.connections, stoppedConnection)
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		bindTrack(track)
	end

	local animationPlayedConnection =
		animator.AnimationPlayed:Connect(function(track: AnimationTrack)
			bindTrack(track)
		end)

	table.insert(observer.connections, animationPlayedConnection)

	local diedConnection =
		humanoid.Died:Connect(function()
			observer.lastStepAt = -math.huge
		end)

	table.insert(observer.connections, diedConnection)
end

local function observePlayer(player: Player)
	disconnectPlayerLevel(player)

	local connections: {RBXScriptConnection} = {}
	playerLevelConnections[player] = connections

	local characterAddedConnection =
		player.CharacterAdded:Connect(function(character: Model)
			task.spawn(observeCharacter, player, character)
		end)

	table.insert(connections, characterAddedConnection)

	if player.Character then
		task.spawn(observeCharacter, player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	observePlayer(player)
end

Players.PlayerAdded:Connect(observePlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	disconnectObserver(player)
	disconnectPlayerLevel(player)
end)

print(
	"[WaterRunAudioController] READY v1"
		.. " | Sound="
		.. WATER_RUN_SOUND_ID
		.. " | TwoStepClip=FootLTrigger"
		.. " | MultiplayerObservation=ON"
)
