--!strict
-- StarterPlayer > StarterPlayerScripts > CombatHUD > CombatHUD_v20_ASTRA_STRICT
-- WAYLESS Combat HUD v20.2 bootstrap hotfix
-- Fixes the missing-assets-module infinite yield and uses the slot-connected adapter.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local folder = script.Parent

local function requireSibling(name: string)
	local instance = folder:FindFirstChild(name)
	if not instance then
		error(("[CombatHUD_v20] Missing sibling ModuleScript '%s' at %s"):format(name, folder:GetFullName()), 0)
	end
	if not instance:IsA("ModuleScript") then
		error(("[CombatHUD_v20] '%s' exists but is %s; it must be a ModuleScript"):format(name, instance.ClassName), 0)
	end
	return require(instance)
end

local Assets = requireSibling("CombatHUDAssets_v20_FINAL_COMPLETE")
local CombatHUD = requireSibling("CombatHUDFacade_v20_ASTRA_STRICT")
local Adapter = requireSibling("CombatHUDBackendAdapter_v20_FROM_SHINOBIHUD")

local old = playerGui:FindFirstChild("WAYLESSCombatHUD_v20")
if old then
	old:Destroy()
end

local hud = CombatHUD.new(playerGui, Assets, {
	screenGuiName = "WAYLESSCombatHUD_v20",
	reducedMotion = false,
})

_G.WAYLESSCombatHUD = hud
Adapter.Bind(hud)

print(
	"[CombatHUD_v20] READY v20.2"
		.. " | AstraLayout=ON"
		.. " | LiveResources=ON"
		.. " | TechniqueSlots=ON"
		.. " | TypeFrames=ON"
		.. " | Cooldowns=ON"
)
