--!strict
-- StarterPlayer > StarterPlayerScripts > FrontendAudioController
-- WAYLESS PRE-ALPHA SHOWCASE 01 frontend audio candidate.
--
-- Centralized UI audio only. This script does not replace or modify any approved
-- Frontend flow logic. It observes the existing WAYLESSFrontend GUI and adds the
-- candidate SFX layer around real interactions.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	warn("[FrontendAudioController] ReplicatedStorage.Shared missing")
	return
end

local assetsModule = shared:WaitForChild("FrontendAudioAssets", 30)
if not assetsModule or not assetsModule:IsA("ModuleScript") then
	warn("[FrontendAudioController] FrontendAudioAssets missing")
	return
end

local requireOk, AudioAssets = pcall(require, assetsModule)
if not requireOk or typeof(AudioAssets) ~= "table" or typeof(AudioAssets.Sounds) ~= "table" then
	warn("[FrontendAudioController] Failed to require FrontendAudioAssets", AudioAssets)
	return
end

local audioFolder = SoundService:FindFirstChild("WAYLESSFrontendAudio")
if not audioFolder then
	audioFolder = Instance.new("Folder")
	audioFolder.Name = "WAYLESSFrontendAudio"
	audioFolder.Parent = SoundService
end

local uiGroup = SoundService:FindFirstChild("WAYLESSFrontendUI")
if not uiGroup or not uiGroup:IsA("SoundGroup") then
	if uiGroup then
		uiGroup:Destroy()
	end
	uiGroup = Instance.new("SoundGroup")
	uiGroup.Name = "WAYLESSFrontendUI"
	uiGroup.Volume = 1
	uiGroup.Parent = SoundService
end

local musicGroup = SoundService:FindFirstChild("WAYLESSFrontendMusic")
if not musicGroup or not musicGroup:IsA("SoundGroup") then
	if musicGroup then
		musicGroup:Destroy()
	end
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "WAYLESSFrontendMusic"
	musicGroup.Volume = 1
	musicGroup.Parent = SoundService
end

local sounds: {[string]: Sound} = {}
local preload: {Instance} = {}

local function createSound(name: string, spec: any): Sound?
	if typeof(spec) ~= "table" then
		return nil
	end

	local assetId = tonumber(spec.Id) or 0
	if assetId <= 0 then
		return nil
	end

	local old = audioFolder:FindFirstChild(name)
	if old then
		old:Destroy()
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(math.floor(assetId))
	sound.Volume = math.clamp(tonumber(spec.Volume) or 0.25, 0, 1)
	sound.Looped = spec.Looped == true
	sound.SoundGroup = sound.Looped and (musicGroup :: SoundGroup) or (uiGroup :: SoundGroup)
	sound.Parent = audioFolder

	sounds[name] = sound
	table.insert(preload, sound)
	return sound
end

for name, spec in pairs(AudioAssets.Sounds) do
	createSound(tostring(name), spec)
end

task.spawn(function()
	if #preload == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(preload)
	end)
	if not ok then
		warn("[FrontendAudioController] Audio preload warning", err)
	end
end)

local cooldowns = {
	Hover = 0.045,
	Click = 0.025,
	Transition = 0.18,
	Notification = 0.18,
	Warning = 0.18,
	CosmeticSelect = 0.025,
}

local lastPlayed: {[string]: number} = {}

local function play(name: string)
	local sound = sounds[name]
	if not sound then
		return
	end

	local now = os.clock()
	local cooldown = cooldowns[name] or 0
	local last = lastPlayed[name] or -math.huge
	if now - last < cooldown then
		return
	end
	lastPlayed[name] = now

	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

local music = sounds.MenuMusic
if music and music.Looped then
	music:Play()
end

local guiObject = playerGui:WaitForChild("WAYLESSFrontend", 30)
if not guiObject or not guiObject:IsA("ScreenGui") then
	warn("[FrontendAudioController] WAYLESSFrontend ScreenGui missing")
	return
end

local gui = guiObject :: ScreenGui

local function hasAncestorName(instance: Instance, targetName: string): boolean
	local cursor: Instance? = instance
	while cursor and cursor ~= gui do
		if cursor.Name == targetName then
			return true
		end
		cursor = cursor.Parent
	end
	return false
end

local function endsWith(value: string, suffix: string): boolean
	return #value >= #suffix and string.sub(value, #value - #suffix + 1) == suffix
end

local function isCompatibilityControl(button: GuiButton): boolean
	return hasAncestorName(button, "CompatibilityControls")
end

local function isCreationCosmeticControl(button: GuiButton): boolean
	if not hasAncestorName(button, "Creation") then
		return false
	end

	local name = button.Name
	if name == "Back" or name == "Cancel" or name == "CreateCharacter" then
		return false
	end

	if string.sub(name, 1, 5) == "Skin_" then
		return true
	end

	return endsWith(name, "Left")
		or endsWith(name, "Right")
		or endsWith(name, "Value")
end

local boundButtons: {[GuiButton]: boolean} = {}
local pendingCreationAt: number? = nil

local function bindButton(button: GuiButton)
	if boundButtons[button] or isCompatibilityControl(button) then
		return
	end
	boundButtons[button] = true

	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		-- Cosmetic arrows/swatches already have a dedicated lightweight click.
		-- Suppress hover there so rapid creator navigation does not become noisy.
		if isCreationCosmeticControl(button) then
			return
		end
		play("Hover")
	end)

	button.MouseButton1Click:Connect(function()
		if not button.Active then
			return
		end

		if isCreationCosmeticControl(button) then
			play("CosmeticSelect")
			return
		end

		if button.Name == "CreateCharacter" and hasAncestorName(button, "Creation") then
			pendingCreationAt = os.clock()
			play("Click")
			return
		end

		-- DeleteAction opens the destructive confirmation modal. The Warning SFX
		-- is fired when that modal actually becomes visible, avoiding Click+Warning
		-- stacking on the same input.
		if hasAncestorName(button, "DeleteAction") then
			return
		end

		play("Click")
	end)
end

for _, descendant in ipairs(gui:GetDescendants()) do
	if descendant:IsA("GuiButton") then
		bindButton(descendant)
	end
end

gui.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("GuiButton") then
		task.defer(bindButton, descendant)
	end
end)

local trackedDeleteModals: {[GuiObject]: boolean} = {}

local function trackDeleteModal(modal: GuiObject)
	if trackedDeleteModals[modal] then
		return
	end
	trackedDeleteModals[modal] = true

	local wasVisible = modal.Visible
	modal:GetPropertyChangedSignal("Visible"):Connect(function()
		local isVisible = modal.Visible
		if isVisible and not wasVisible then
			play("Warning")
		end
		wasVisible = isVisible
	end)
end

local existingDeleteModal = gui:FindFirstChild("DeleteModal", true)
if existingDeleteModal and existingDeleteModal:IsA("GuiObject") then
	trackDeleteModal(existingDeleteModal)
end

gui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "DeleteModal" and descendant:IsA("GuiObject") then
		trackDeleteModal(descendant)
	end
end)

local ROOT_PRIORITY = {
	"Creation",
	"ServerSelectorHUDRoot",
	"SlotSelectorHUDRoot",
	"MainMenuRoot",
}

local trackedRoots: {[GuiObject]: boolean} = {}
local lastActiveRoot: string? = nil
local rootInitialized = false

local function currentActiveRoot(): string?
	for _, rootName in ipairs(ROOT_PRIORITY) do
		local candidate = gui:FindFirstChild(rootName, true)
		if candidate and candidate:IsA("GuiObject") and candidate.Visible then
			return rootName
		end
	end
	return nil
end

local function refreshActiveRoot()
	local nextRoot = currentActiveRoot()

	if not rootInitialized then
		if nextRoot then
			lastActiveRoot = nextRoot
			rootInitialized = true
		end
		return
	end

	if not nextRoot or nextRoot == lastActiveRoot then
		return
	end

	local previousRoot = lastActiveRoot
	lastActiveRoot = nextRoot
	play("Transition")

	if previousRoot == "Creation" and nextRoot == "SlotSelectorHUDRoot" and pendingCreationAt then
		if os.clock() - pendingCreationAt <= 12 then
			task.delay(0.20, function()
				play("Notification")
			end)
		end
		pendingCreationAt = nil
	elseif pendingCreationAt and os.clock() - pendingCreationAt > 12 then
		pendingCreationAt = nil
	end
end

local function trackRoot(root: GuiObject)
	if trackedRoots[root] then
		return
	end
	trackedRoots[root] = true
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		task.defer(refreshActiveRoot)
	end)
end

for _, rootName in ipairs(ROOT_PRIORITY) do
	local root = gui:FindFirstChild(rootName, true)
	if root and root:IsA("GuiObject") then
		trackRoot(root)
	end
end

gui.DescendantAdded:Connect(function(descendant)
	for _, rootName in ipairs(ROOT_PRIORITY) do
		if descendant.Name == rootName and descendant:IsA("GuiObject") then
			trackRoot(descendant)
			task.defer(refreshActiveRoot)
			break
		end
	end
end)

task.defer(refreshActiveRoot)

print(
	"[FrontendAudioController] READY "
		.. tostring(AudioAssets.Version or "candidate")
		.. " | SFX=Hover,Click,Transition,Notification,Warning,CosmeticSelect"
		.. " | MenuMusic="
		.. (music and "ON" or "PENDING")
)
