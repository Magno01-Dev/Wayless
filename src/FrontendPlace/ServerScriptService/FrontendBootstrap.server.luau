--!strict
-- ServerScriptService > FrontendBootstrap
--
-- WAYLESS Frontend bootstrap v1.
-- No playable character is spawned in the Main Menu Place.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

Players.CharacterAutoLoads = false

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		player.Character:Destroy()
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:Destroy()
	end)
end)

local FrontendService =
	require(
		ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("FrontendService")
	)

FrontendService.Start()

print(
	"[FrontendBootstrap] READY v1"
		.. " | CharacterAutoLoads=OFF"
)
