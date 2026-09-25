--!strict
-- SurfaceWalkVFXServer v1
--
-- ServerScriptService > SurfaceWalkVFXServer
--
-- Cosmetic replication only.
-- Events:
--   Step, SprintStep, JumpPush
--
-- Does NOT modify SurfaceController, movement, camera, physics, combat or animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local movementRemotes = ReplicatedStorage:FindFirstChild("MovementRemotes")

if not movementRemotes then
	movementRemotes = Instance.new("Folder")
	movementRemotes.Name = "MovementRemotes"
	movementRemotes.Parent = ReplicatedStorage
end

local remote = movementRemotes:FindFirstChild("SurfaceWalkVFX")

if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SurfaceWalkVFX"
	remote.Parent = movementRemotes
end

local VALID_EVENTS = {
	Step = true,
	SprintStep = true,
	JumpPush = true,
}

local MIN_INTERVAL = {
	Step = 0.11,
	SprintStep = 0.08,
	JumpPush = 0.16,
}

local MAX_DISTANCE_FROM_ROOT = 14

local lastTimes: { [Player]: { [string]: number } } = {}

local function rateLimit(player: Player, eventName: string): boolean
	local now = time()
	local map = lastTimes[player]

	if not map then
		map = {}
		lastTimes[player] = map
	end

	local previous = map[eventName] or -math.huge
	local minimum = MIN_INTERVAL[eventName] or 0.10

	if now - previous < minimum then
		return false
	end

	map[eventName] = now
	return true
end

remote.OnServerEvent:Connect(function(
	player: Player,
	eventName: any,
	worldPosition: any,
	surfaceNormal: any,
	surfaceColor: any,
	moveDirection: any
)
	if typeof(eventName) ~= "string"
		or VALID_EVENTS[eventName] ~= true then
		return
	end

	if typeof(worldPosition) ~= "Vector3"
		or typeof(surfaceNormal) ~= "Vector3" then
		return
	end

	if surfaceNormal.Magnitude < 0.5 then
		return
	end

	surfaceNormal = surfaceNormal.Unit

	if typeof(surfaceColor) ~= "Color3" then
		surfaceColor = Color3.fromRGB(145, 140, 135)
	end

	if typeof(moveDirection) ~= "Vector3" then
		moveDirection = Vector3.zero
	end

	if moveDirection.Magnitude > 1.05 then
		moveDirection = moveDirection.Unit
	end

	if not rateLimit(player, eventName) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid
		or humanoid.Health <= 0
		or not rootPart
		or not rootPart:IsA("BasePart") then
		return
	end

	if (worldPosition - rootPart.Position).Magnitude > MAX_DISTANCE_FROM_ROOT then
		return
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			remote:FireClient(
				otherPlayer,
				player,
				eventName,
				worldPosition,
				surfaceNormal,
				surfaceColor,
				moveDirection
			)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastTimes[player] = nil
end)

