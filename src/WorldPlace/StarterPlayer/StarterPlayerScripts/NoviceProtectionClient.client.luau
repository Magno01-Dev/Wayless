--!strict
-- StarterPlayer > StarterPlayerScripts > NoviceProtectionClient
--
-- Icono de brote sobre la cabeza de los jugadores con protección de novato (atributo del jugador
-- NoviceProtected, lo pone LifeForceServer). Lo ven todos: quien ataca sabe que es nuevo.

local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local ICON = "rbxassetid://78957545012343" -- provisional
local ICON_SIZE = 24 -- px
local ICON_OFFSET = Vector3.new(0, 2.2, 0) -- studs sobre la cabeza
local MAX_DISTANCE = 80

local icons: {[Player]: BillboardGui} = {}

local function clear(player: Player)
	local existing = icons[player]
	if existing then
		existing:Destroy()
		icons[player] = nil
	end
end

local function refresh(player: Player)
	clear(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if player:GetAttribute("NoviceProtected") ~= true or not head or not head:IsA("BasePart") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NoviceProtectionIcon"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	billboard.StudsOffsetWorldSpace = ICON_OFFSET
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Parent = playerGui
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = ICON
	image.Parent = billboard
	icons[player] = billboard
end

local function bind(player: Player)
	player:GetAttributeChangedSignal("NoviceProtected"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		refresh(player)
	end)
	if player.Character then
		task.spawn(function()
			player.Character:WaitForChild("Head", 10)
			refresh(player)
		end)
	end
end

Players.PlayerAdded:Connect(bind)
Players.PlayerRemoving:Connect(clear)
for _, player in Players:GetPlayers() do
	bind(player)
end
