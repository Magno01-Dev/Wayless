--!strict
-- MovementBurstVFXServer v1
--
-- ServerScriptService > MovementBurstVFXServer
--
-- Cosmetic replication only.
-- Receives transient movement VFX events from the owning client,
-- validates the request, then forwards it to the other clients.
--
-- It does NOT modify JumpController, DashController, TreeJumpController,
-- SurfaceController, camera, movement, physics, animations, or damage.

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
		Instance.new(
			"Folder"
		)

	movementRemotes.Name =
		"MovementRemotes"

	movementRemotes.Parent =
		ReplicatedStorage

end


local movementBurstVFX =
	movementRemotes:FindFirstChild(
		"MovementBurstVFX"
	)

if not movementBurstVFX then

	movementBurstVFX =
		Instance.new(
			"RemoteEvent"
		)

	movementBurstVFX.Name =
		"MovementBurstVFX"

	movementBurstVFX.Parent =
		movementRemotes

end


-- =========================
-- VALIDATION
-- =========================

local VALID_EVENTS = {
	Jump = true,
	DoubleJump = true,
	Land = true,
	LandHeavy = true,
}

local MIN_EVENT_INTERVAL = {
	Jump = 0.10,
	DoubleJump = 0.10,
	Land = 0.10,
	LandHeavy = 0.10,
}

local MAX_POSITION_DISTANCE_FROM_ROOT =
	18

local lastEventTimes: {
	[Player]: {
		[string]: number
	}
} = {}


local function canSend(
	player: Player,
	eventName: string
): boolean

	local now =
		time()

	local playerTimes =
		lastEventTimes[
	player
	]

	if not playerTimes then

		playerTimes =
			{}

		lastEventTimes[
		player
		] =
			playerTimes

	end


	local last =
		playerTimes[
	eventName
	]
		or -math.huge


	local minimum =
		MIN_EVENT_INTERVAL[
	eventName
	]
		or 0.10


	if now - last <
		minimum then

		return false

	end


	playerTimes[
	eventName
	] =
		now


	return true

end


movementBurstVFX.OnServerEvent:Connect(
	function(
		player: Player,
		eventName: any,
		worldPosition: any,
		surfaceColor: any
	)

		if typeof(
			eventName
			) ~= "string"
				or VALID_EVENTS[
			eventName
			] ~= true then

			return

		end


		if typeof(
			worldPosition
			) ~= "Vector3" then

			return

		end


		if typeof(
			surfaceColor
			) ~= "Color3" then

			surfaceColor =
				Color3.fromRGB(
					175,
					175,
					175
				)

		end


		if not canSend(
			player,
			eventName
			) then

			return

		end


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

		local rootPart =
			character:
			FindFirstChild(
				"HumanoidRootPart"
			)


		if not humanoid
			or humanoid.Health <= 0
			or not rootPart
			or not rootPart:IsA(
				"BasePart"
			) then

			return

		end


		if (
			worldPosition -
				rootPart.Position
			).Magnitude >
			MAX_POSITION_DISTANCE_FROM_ROOT then

			return

		end


		-- Sender already renders the event immediately.
		-- Forward only to the other clients to avoid duplicate VFX.
		for _, otherPlayer in ipairs(
			Players:GetPlayers()
			) do

			if otherPlayer ~=
				player then

				movementBurstVFX:
					FireClient(
						otherPlayer,
						player,
						eventName,
						worldPosition,
						surfaceColor
					)

			end

		end

	end
)


Players.PlayerRemoving:Connect(
	function(
		player: Player
	)

		lastEventTimes[
		player
		] =
			nil

	end
)
