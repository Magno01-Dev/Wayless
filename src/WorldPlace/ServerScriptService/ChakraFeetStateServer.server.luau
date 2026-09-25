--!strict
-- ChakraFeetStateServer v2
--
-- ServerScriptService > ChakraFeetStateServer
--
-- Responsibility:
-- ONLY replicate the ChakraFeetActive state to all clients.
--
-- The VFX itself is rendered locally by every client for every player.
-- This is more reliable for cosmetic effects than creating ParticleEmitters
-- directly on the server.
--
-- Does NOT touch SurfaceController physics/movement.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


-- =========================
-- REMOTE
-- =========================

local movementRemotes =
	ReplicatedStorage:FindFirstChild(
		"MovementRemotes"
	)

if not movementRemotes then
	movementRemotes =
		Instance.new("Folder")

	movementRemotes.Name =
		"MovementRemotes"

	movementRemotes.Parent =
		ReplicatedStorage
end


local chakraFeetStateRequest =
	movementRemotes:FindFirstChild(
		"ChakraFeetStateRequest"
	)

if not chakraFeetStateRequest then
	chakraFeetStateRequest =
		Instance.new("RemoteEvent")

	chakraFeetStateRequest.Name =
		"ChakraFeetStateRequest"

	chakraFeetStateRequest.Parent =
		movementRemotes
end


local MIN_REQUEST_INTERVAL =
	0.08

local lastRequest: { [Player]: number } =
	{}


local function initializeCharacter(
	character: Model
)
	character:SetAttribute(
		"ChakraFeetActive",
		false
	)
end


chakraFeetStateRequest.OnServerEvent:Connect(
	function(
		player: Player,
		requestedState: any
	)

		if typeof(requestedState) ~=
			"boolean" then

			return

		end


		local now =
			time()

		local previous =
			lastRequest[player]
			or -math.huge


		if now - previous <
			MIN_REQUEST_INTERVAL then

			return

		end


		lastRequest[player] =
			now


		local character =
			player.Character

		if not character then

			return

		end


		local humanoid =
			character:
			FindFirstChildOfClass(
				"Humanoid"
			)

		if not humanoid
			or humanoid.Health <= 0 then

			return

		end


		-- This attribute is set by the SERVER, therefore it replicates
		-- to every client and becomes the shared visual state.
		character:SetAttribute(
			"ChakraFeetActive",
			requestedState
		)

	end
)


local function bindPlayer(
	player: Player
)

	player.CharacterAdded:Connect(
		initializeCharacter
	)


	if player.Character then

		initializeCharacter(
			player.Character
		)

	end

end


for _, player in ipairs(
	Players:GetPlayers()
	) do

	bindPlayer(
		player
	)

end


Players.PlayerAdded:Connect(
	bindPlayer
)


Players.PlayerRemoving:Connect(
	function(
		player: Player
	)

		lastRequest[player] =
			nil

	end
)
