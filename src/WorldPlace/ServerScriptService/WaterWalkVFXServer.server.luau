--!strict
-- WaterWalkVFXServer v5 - Marker-Synced Walk / Run Steps
--
-- ServerScriptService > WaterWalkVFXServer
--
-- Cosmetic replication only.
--
-- Events:
--   WalkStep
--   RunStep
--   Idle
--   Jump
--   Land
--   DashStart
--   DashLand
--
-- "Step" is retained temporarily as compatibility for an old v4 client.
--
-- v5 lowers only the Step rate limit enough that legitimate FootL/FootR
-- markers are not discarded. It does not affect movement/gameplay.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


local movementRemotes =
	ReplicatedStorage:
	FindFirstChild(
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


local remote =
	movementRemotes:
	FindFirstChild(
		"WaterWalkVFX"
	)


if not remote then

	remote =
		Instance.new("RemoteEvent")

	remote.Name =
		"WaterWalkVFX"

	remote.Parent =
		movementRemotes
end


local VALID_EVENTS = {
	WalkStep = true,
	RunStep = true,
	Step = true,
	Idle = true,
	Jump = true,
	Land = true,
	DashStart = true,
	DashLand = true,
}


local MIN_INTERVAL = {
	WalkStep = 0.035,
	RunStep = 0.035,
	Step = 0.035,
	Idle = 0.45,
	Jump = 0.18,
	Land = 0.18,
	DashStart = 0.16,
	DashLand = 0.16,
}


local MAX_DISTANCE_FROM_ROOT =
	20


local lastTimes: {
	[Player]: {
		[string]: number
	}
} = {}


local function rateLimit(
	player: Player,
	eventName: string
): boolean

	local now =
		time()

	local map =
		lastTimes[
	player
	]


	if not map then

		map =
			{}

		lastTimes[
		player
		] =
			map
	end


	local previous =
		map[
	eventName
	]
		or -math.huge

	local minimum =
		MIN_INTERVAL[
	eventName
	]
		or 0.12


	if now - previous <
		minimum then

		return false
	end


	map[
	eventName
	] =
		now


	return true
end


remote.OnServerEvent:
	Connect(
		function(
			player: Player,
			eventName: any,
			worldPosition: any,
			waterColor: any,
			direction: any
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
				waterColor
				) ~= "Color3" then

				waterColor =
				Color3.fromRGB(
					95,
					175,
					225
				)
			end


			if typeof(
				direction
				) ~= "Vector3" then

				direction =
				Vector3.zero
			end


			if direction.Magnitude >
				1.05 then

				direction =
				direction.Unit
			end


			if not rateLimit(
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
				or humanoid.Health <=
				0
				or not rootPart
				or not rootPart:IsA(
					"BasePart"
				) then

				return
			end


			if (
				worldPosition
				- rootPart.Position
				).Magnitude >
				MAX_DISTANCE_FROM_ROOT then

				return
			end


			for _,
				otherPlayer in ipairs(
					Players:GetPlayers()
				) do

				if otherPlayer ~=
					player then

					remote:
					FireClient(
						otherPlayer,
						player,
						eventName,
						worldPosition,
						waterColor,
						direction
					)
				end
			end
		end
	)


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			lastTimes[
			player
			] =
			nil
		end
	)


print(
	"[WaterWalkVFXServer] READY v5"
		.. " | WalkStep=ON"
		.. " | RunStep=ON"
		.. " | MultiplayerReplication=ON"
)
