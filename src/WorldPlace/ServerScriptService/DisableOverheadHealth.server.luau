--!strict
-- DisableOverheadHealth
-- ServerScriptService > DisableOverheadHealth
--
-- Removes Roblox default overhead health bars
-- for every player's character.

local Players = game:GetService("Players")


local function configureCharacter(character: Model)
	local humanoid =
		character:WaitForChild("Humanoid") :: Humanoid

	humanoid.HealthDisplayType =
		Enum.HumanoidHealthDisplayType.AlwaysOff
end


local function configurePlayer(player: Player)
	if player.Character then
		task.spawn(
			configureCharacter,
			player.Character
		)
	end

	player.CharacterAdded:Connect(
		function(character)
			configureCharacter(character)
		end
	)
end


-- Players already connected
for _, player in ipairs(Players:GetPlayers()) do
	configurePlayer(player)
end


-- Future players
Players.PlayerAdded:Connect(
	configurePlayer
)