-- DisableDefaultHealthUI
-- StarterPlayer > StarterPlayerScripts
-- LocalScript

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer


-- ============================================================
-- DISABLE ROBLOX DEFAULT HEALTH GUI
-- ============================================================

local function disableCoreHealthGui()
	local success = false

	-- SetCoreGuiEnabled sometimes needs a moment during startup,
	-- so retry until Roblox accepts the call.
	while not success do
		success = pcall(function()
			StarterGui:SetCoreGuiEnabled(
				Enum.CoreGuiType.Health,
				false
			)
		end)

		if not success then
			task.wait(0.25)
		end
	end
end


-- ============================================================
-- DISABLE HUMANOID OVERHEAD HEALTH BAR
-- ============================================================

local function configureCharacter(character: Model)
	local humanoid =
		character:WaitForChild("Humanoid") :: Humanoid

	humanoid.HealthDisplayType =
		Enum.HumanoidHealthDisplayType.AlwaysOff
end


-- Current / future character
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


-- ============================================================
-- START
-- ============================================================

task.spawn(disableCoreHealthGui)
