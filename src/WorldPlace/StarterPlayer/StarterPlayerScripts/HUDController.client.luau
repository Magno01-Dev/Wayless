local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainHUD = playerGui:WaitForChild("MainHUD")

mainHUD.Enabled = true