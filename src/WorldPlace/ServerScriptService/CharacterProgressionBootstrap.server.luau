--!strict
-- WAYLESS
-- CharacterProgressionBootstrap v2.0 - Persistent Slot Data Bootstrap

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local CharacterDataService = require(Services:WaitForChild("CharacterDataService"))

local function onPlayerAdded(player: Player)
	if CharacterDataService.IsLoaded(player) then
		return
	end

	local ok, errorMessage = CharacterDataService.LoadPlayer(player)
	if not ok then
		warn("[CharacterProgressionBootstrap] LOAD FAILED", player.Name, errorMessage)
		player:Kick("Your character data could not be loaded safely. Please rejoin in a moment.")
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

print("[CharacterProgressionBootstrap] READY v2.0 | PersistentSlotData=ON")
