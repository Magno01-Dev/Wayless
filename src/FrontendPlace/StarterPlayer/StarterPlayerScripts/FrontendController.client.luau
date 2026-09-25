--!strict
-- StarterPlayer > StarterPlayerScripts > FrontendController
--
-- WAYLESS Frontend / Main Menu UI v5.0 - asset-driven main menu + Astra Character Creation HUD.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local initialCamera =
	Workspace.CurrentCamera

local defaultCameraFieldOfView =
	initialCamera
	and initialCamera.FieldOfView
	or 70

local CREATION_DEFAULT_FOV = 48
local CREATION_MIN_FOV = 30
local CREATION_MAX_FOV = 68

-- Continuous presentation controls.
local CREATION_ROTATE_SPEED = 105 -- degrees / second while held
local CREATION_ZOOM_SPEED = 26 -- FOV degrees / second while held
local CREATION_MOUSE_WHEEL_STEP = 3.25
local CREATION_ZOOM_SMOOTHNESS = 12
local CREATION_DRAG_SENSITIVITY = 0.32 -- degrees per horizontal pixel

local CREATION_RIGHT_COMPOSITION_BIAS = 0
local PREVIEW_FOOT_CLEARANCE = 0.22

local creationCameraFieldOfView =
	CREATION_DEFAULT_FOV

local creationCameraTargetFieldOfView =
	CREATION_DEFAULT_FOV

local previewYawDegrees = 0

local rotateLeftHeld = false
local rotateRightHeld = false
local zoomInHeld = false
local zoomOutHeld = false

local dragRotateActive = false
local dragLastX = 0

local system =
	ReplicatedStorage:
	WaitForChild("FrontendSystem", 30)

if not system then
	warn("[FrontendController] FrontendSystem missing")
	return
end

local remotes = system:WaitForChild("Remotes", 10)
local requestObject =
	remotes and remotes:WaitForChild("FrontendRequest", 10)

if not requestObject
	or not requestObject:IsA("RemoteFunction") then

	warn("[FrontendController] FrontendRequest missing")
	return
end

local request = requestObject :: RemoteFunction

local function findSceneMarkerContainer(): Instance?
	local persistent =
		Workspace:
		FindFirstChild(
			"FrontendSceneMarkers"
		)

	if persistent then
		return persistent
	end

	-- Legacy compatibility during migration from FrontendWorldBootstrap v2.
	return Workspace:
		FindFirstChild(
			"FrontendScene"
		)
end

local function waitForSceneMarker(
	name: string,
	timeoutSeconds: number?
): BasePart?
	local timeout =
		timeoutSeconds or 10

	local deadline =
		os.clock() + timeout

	repeat
		local container =
			findSceneMarkerContainer()

		if container then
			local marker =
				container:
				FindFirstChild(name)

			if marker
				and marker:IsA("BasePart") then

				return marker
			end
		end

		task.wait(0.1)
	until os.clock() >= deadline

	return nil
end

-- Camera markers are server-owned and may arrive after this LocalScript starts.
-- Do not assume they already exist on the first frame.
task.spawn(function()
	local anchor =
		waitForSceneMarker(
			"CameraAnchor",
			10
		)

	local focus =
		waitForSceneMarker(
			"CameraFocus",
			10
		)

	local camera =
		Workspace.CurrentCamera

	if camera
		and anchor
		and focus then

		camera.CameraType =
			Enum.CameraType.Scriptable

		camera.CFrame =
			CFrame.lookAt(
				anchor.Position,
				focus.Position
			)
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "WAYLESSFrontend"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(5, 7, 10)
background.BackgroundTransparency = 0.22
background.BorderSizePixel = 0
background.Parent = gui

local shell = Instance.new("Frame")
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.fromOffset(930, 640)
shell.BackgroundColor3 = Color3.fromRGB(11, 13, 18)
shell.BackgroundTransparency = 0.04
shell.BorderSizePixel = 0
shell.Parent = gui

local shellCorner = Instance.new("UICorner")
shellCorner.CornerRadius = UDim.new(0, 10)
shellCorner.Parent = shell

local shellStroke = Instance.new("UIStroke")
shellStroke.Color = Color3.fromRGB(75, 82, 98)
shellStroke.Transparency = 0.45
shellStroke.Parent = shell

local header = Instance.new("TextLabel")
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(28, 20)
header.Size = UDim2.fromOffset(520, 46)
header.Text = "WAYLESS"
header.TextColor3 = Color3.fromRGB(238, 240, 246)
header.TextSize = 31
header.TextXAlignment = Enum.TextXAlignment.Left
header.Font = Enum.Font.GothamBold
header.Parent = shell

local subheader = Instance.new("TextLabel")
subheader.BackgroundTransparency = 1
subheader.Position = UDim2.fromOffset(31, 61)
subheader.Size = UDim2.fromOffset(600, 24)
subheader.Text = "SHINOBI FRONTEND"
subheader.TextColor3 = Color3.fromRGB(132, 141, 160)
subheader.TextSize = 11
subheader.TextXAlignment = Enum.TextXAlignment.Left
subheader.Font = Enum.Font.GothamMedium
subheader.Parent = shell

local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(24, 96)
content.Size = UDim2.new(1, -48, 1, -140)
content.Parent = shell

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.new(0, 28, 1, -38)
status.Size = UDim2.new(1, -56, 0, 22)
status.Text = "Loading account..."
status.TextColor3 = Color3.fromRGB(145, 154, 172)
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Gotham
status.Parent = shell

local pages: {[string]: Frame} = {}

local function makePage(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = content
	pages[name] = frame
	return frame
end

local mainPage = makePage("Main")
local slotsPage = makePage("Slots")
local creationPage = makePage("Creation")
local serversPage = makePage("Servers")

local function button(
	parent: Instance,
	text: string,
	pos: UDim2,
	size: UDim2
): TextButton
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = Color3.fromRGB(31, 35, 45)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.fromRGB(235, 237, 243)
	b.TextSize = 12
	b.Font = Enum.Font.GothamBold
	b.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b

	return b
end

local function label(
	parent: Instance,
	text: string,
	pos: UDim2,
	size: UDim2,
	textSize: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Text = text
	l.TextColor3 = Color3.fromRGB(220, 224, 234)
	l.TextSize = textSize
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Font = Enum.Font.Gotham
	l.Parent = parent
	return l
end

local function selectorControl(
	parent: Instance,
	initialText: string,
	pos: UDim2,
	size: UDim2
): (TextButton, TextLabel, TextButton)
	local frame = Instance.new("Frame")
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(24, 27, 35)
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local arrowWidth = 28

	local left = button(
		frame,
		"<",
		UDim2.fromOffset(0, 0),
		UDim2.new(0, arrowWidth, 1, 0)
	)
	left.TextSize = 14

	local right = button(
		frame,
		">",
		UDim2.new(1, -arrowWidth, 0, 0),
		UDim2.new(0, arrowWidth, 1, 0)
	)
	right.TextSize = 14

	local value = Instance.new("TextLabel")
	value.Position = UDim2.fromOffset(arrowWidth + 2, 0)
	value.Size = UDim2.new(1, -(arrowWidth * 2) - 4, 1, 0)
	value.BackgroundTransparency = 1
	value.Text = initialText
	value.TextColor3 = Color3.fromRGB(235, 237, 243)
	value.TextSize = 10
	value.Font = Enum.Font.GothamBold
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.TextYAlignment = Enum.TextYAlignment.Center
	value.Parent = frame

	return left, value, right
end

local function textBox(
	parent: Instance,
	placeholder: string,
	pos: UDim2,
	size: UDim2
): TextBox
	local box = Instance.new("TextBox")
	box.Position = pos
	box.Size = size
	box.BackgroundColor3 = Color3.fromRGB(24, 27, 35)
	box.BorderSizePixel = 0
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(111, 120, 139)
	box.Text = ""
	box.TextColor3 = Color3.fromRGB(235, 237, 243)
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = Enum.Font.GothamMedium
	box.ClearTextOnFocus = false
	box.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = box

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = box

	return box
end

local currentState: any = nil
local selectedSlotId: string? = nil
local busy = false

local creationVillages: {any} = {}
local creationNatures: {any} = {}
local selectedVillageIndex = 1
local selectedNatureIndex = 1

local cachedAppearanceCatalog: any? = nil
local selectedSkinIndex = 5
local selectedMouthIndex = 1
local selectedBrowIndex = 1
local selectedNoseIndex = 1
local selectedEyeIndex = 1
local selectedShoesIndex = 1
local selectedGlovesIndex = 1
local selectedTopColorIndex = 1
local selectedBottomColorIndex = 1
local selectedTopIndex = 1
local selectedBottomIndex = 1
local selectedHairAssetIds: {number} = {}

local previewModel: Model? = nil
local previewRefreshRequested = false
local previewRefreshRunning = false

-- MAIN MENU HUD
-- The source pack uses a fixed 1920x1080 design canvas. MainMenuHUD applies
-- one uniform scale factor and centers that canvas on non-16:9 displays.
local sharedModules = ReplicatedStorage:FindFirstChild("Shared")

if not sharedModules then
	warn("[FrontendController] ReplicatedStorage.Shared missing")
	return
end

-- FRONTEND COMMERCE
local commerceConfigModule =
	sharedModules:FindFirstChild("FrontendCommerceConfig")
	or sharedModules:FindFirstChild("FrontendCommerceConfig_v1")

local CommerceConfig: any = {
	BuyCharacterSlotProductId = 0,
}

if commerceConfigModule and commerceConfigModule:IsA("ModuleScript") then
	local ok, result = pcall(require, commerceConfigModule)
	if ok and typeof(result) == "table" then
		CommerceConfig = result
	else
		warn("[FrontendController] Failed to require FrontendCommerceConfig", result)
	end
end

local BUY_CHARACTER_SLOT_PRODUCT_ID =
	tonumber(CommerceConfig.BuyCharacterSlotProductId) or 0

local mainMenuHUDModule =
	sharedModules:FindFirstChild("MainMenuHUD")
	or sharedModules:FindFirstChild("MainMenuHUD_v1")

if not mainMenuHUDModule
	or not mainMenuHUDModule:IsA("ModuleScript") then

	warn(
		"[FrontendController] MainMenuHUD ModuleScript missing. "
			.. "Expected ReplicatedStorage.Shared.MainMenuHUD."
	)
	return
end

local mainMenuRequireOk, MainMenuHUD =
	pcall(require, mainMenuHUDModule)

if not mainMenuRequireOk then
	warn(
		"[FrontendController] Failed to require MainMenuHUD:",
		MainMenuHUD
	)
	return
end

local mainMenuUI = MainMenuHUD.Create(gui)
mainMenuUI.setPlayEnabled(false)
mainMenuUI.setQuickplayEnabled(false)

-- Full-screen slot selector is parented directly to the ScreenGui, not the legacy shell.
local frontendHUDs: {[string]: any} = {
	Slots = nil,
	Servers = nil,
}

-- FRONTEND TRANSITIONS
-- A short ink/brush cover hides the actual page/camera swap so screens feel like
-- one continuous frontend instead of one GUI suddenly appearing over another.
local transitionModule =
	sharedModules:FindFirstChild("FrontendTransitionController")
	or sharedModules:FindFirstChild("FrontendTransitionController_v1")

local pageTransitions: any = nil
if transitionModule and transitionModule:IsA("ModuleScript") then
	local ok, result = pcall(require, transitionModule)
	if ok and typeof(result) == "table" and typeof(result.Create) == "function" then
		pageTransitions = result.Create(gui)
	else
		warn("[FrontendController] Failed to require FrontendTransitionController", result)
	end
else
	warn("[FrontendController] FrontendTransitionController missing; page swaps will be immediate")
end

local PAGE_DEPTH = {
	Main = 0,
	Slots = 1,
	Servers = 2,
	Creation = 2,
}

local currentPageName: string? = nil

local function applyPageVisibility(name: string)
	local isMain = name == "Main"

	for pageName, page in pairs(pages) do
		-- Main now lives in its own full-screen asset-driven root rather than
		-- inside the legacy centered shell.
		page.Visible = (not isMain) and pageName == name
	end

	mainMenuUI.SetVisible(isMain)

	if frontendHUDs.Slots then
		frontendHUDs.Slots.SetVisible(name == "Slots")
	end

	if frontendHUDs.Servers then
		frontendHUDs.Servers.SetVisible(name == "Servers")
	end

	if isMain then
		background.Visible = false
		shell.Visible = false
		status.Visible = false
	elseif name == "Creation" or name == "Slots" or name == "Servers" then
		-- CharacterCreationHUD is also a full-screen presentation.
		background.Visible = false
		shell.Visible = false
		status.Visible = false
	else
		background.Visible = true
		shell.Visible = true
		status.Visible = true
	end
end

local function showPage(name: string, options: {[string]: any}?)
	local opts = options or {}

	local function swap()
		if typeof(opts.BeforeSwap) == "function" then
			opts.BeforeSwap()
		end

		applyPageVisibility(name)
		currentPageName = name

		if typeof(opts.AfterSwap) == "function" then
			opts.AfterSwap()
		end
	end

	if opts.Instant == true or currentPageName == nil then
		swap()
		return
	end

	if currentPageName == name then
		swap()
		return
	end

	local fromDepth = PAGE_DEPTH[currentPageName] or 0
	local toDepth = PAGE_DEPTH[name] or fromDepth
	local direction = opts.Direction
	if direction == nil then
		direction = (toDepth < fromDepth) and "Back" or "Forward"
	end

	if pageTransitions then
		pageTransitions.Run(swap, {
			Direction = direction,
		})
	else
		swap()
	end
end

-- SLOTS
local slotsTitle = label(
	slotsPage,
	"CHARACTER SLOTS",
	UDim2.fromOffset(8, 0),
	UDim2.fromOffset(400, 34),
	22
)
slotsTitle.Font = Enum.Font.GothamBold

local currencyLabel = label(
	slotsPage,
	"",
	UDim2.fromOffset(8, 35),
	UDim2.fromOffset(650, 24),
	10
)
currencyLabel.TextColor3 = Color3.fromRGB(145, 154, 172)

local slotsBack =
	button(
		slotsPage,
		"BACK",
		UDim2.new(1, -112, 0, 0),
		UDim2.fromOffset(104, 32)
	)

local slotsScroll = Instance.new("ScrollingFrame")
slotsScroll.Position = UDim2.fromOffset(6, 72)
slotsScroll.Size = UDim2.new(1, -12, 1, -78)
slotsScroll.BackgroundTransparency = 1
slotsScroll.BorderSizePixel = 0
slotsScroll.ScrollBarThickness = 5
slotsScroll.CanvasSize = UDim2.new()
slotsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
slotsScroll.Parent = slotsPage

local slotsLayout = Instance.new("UIListLayout")
slotsLayout.Padding = UDim.new(0, 10)
slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotsLayout.Parent = slotsScroll

-- CREATION
-- Robust module resolution: Studio imports often preserve the source filename
-- (for example CharacterCreationHUD_v2_STATIC_ASTRA_LABELS) instead of the
-- canonical runtime name CharacterCreationHUD. Never block forever here.
local characterCreationHUDModule =
	sharedModules:FindFirstChild("CharacterCreationHUD")
	or sharedModules:FindFirstChild("CharacterCreationHUD_v2_STATIC_ASTRA_LABELS")
	or sharedModules:FindFirstChild("CharacterCreationHUD_v1")

if not characterCreationHUDModule
	or not characterCreationHUDModule:IsA("ModuleScript") then

	warn(
		"[FrontendController] CharacterCreationHUD ModuleScript missing. "
			.. "Expected ReplicatedStorage.Shared.CharacterCreationHUD "
			.. "(preferred) or a known imported filename."
	)
	return
end

local requireOk, CharacterCreationHUD =
	pcall(require, characterCreationHUDModule)

if not requireOk then
	warn(
		"[FrontendController] Failed to require CharacterCreationHUD:",
		CharacterCreationHUD
	)
	return
end

local creationUI =
	CharacterCreationHUD.Create(
		gui,
		creationPage
	)

creationUI.statusLabel.Text = status.Text
status:GetPropertyChangedSignal("Text"):Connect(function()
	creationUI.statusLabel.Text = status.Text
end)

-- SERVERS
-- The legacy code-generated server browser was removed. The server selector is
-- now rendered by ReplicatedStorage.Shared.ServerSelectorHUD.

local function invoke(action: string, payload: any?): any
	if busy then
		return nil
	end

	busy = true
	status.Text = action .. "..."

	local ok, result = pcall(function()
		return request:InvokeServer(action, payload)
	end)

	busy = false

	if not ok then
		status.Text = "Request failed: " .. action
		warn("[FrontendController] REQUEST FAILED", action, result)
		return nil
	end

	if typeof(result) == "table" then
		currentState = result
		status.Text = tostring(result.Reason or "Ready")
	end

	return result
end

local function slotSort(a: string, b: string): boolean
	return (tonumber(a) or 9999) < (tonumber(b) or 9999)
end

-- MAIN MENU QUICKPLAY
-- Last-used-slot persistence is isolated behind MainMenuPreferencesRequest.
-- If that optional remote is unavailable, Quickplay still falls back safely to
-- the returning FocusSlotId and then the first playable Alive slot.
local lastUsedSlotId: string? = nil

local function getMainMenuPreferencesRemote(): RemoteFunction?
	local candidate = remotes and remotes:FindFirstChild("MainMenuPreferencesRequest")
	if candidate and candidate:IsA("RemoteFunction") then
		return candidate
	end
	return nil
end

local function menuPreferencesInvoke(action: string, payload: any?): any
	local remote = getMainMenuPreferencesRemote()
	if not remote then
		return nil
	end

	local ok, result = pcall(function()
		return remote:InvokeServer(action, payload)
	end)

	if not ok then
		warn("[FrontendController] Main menu preferences request failed", action, result)
		return nil
	end

	return result
end

local function isPlayableSlotId(slotId: any): boolean
	if slotId == nil then
		return false
	end

	local snapshot = currentState and currentState.Snapshot
	local slots = snapshot and snapshot.Slots
	if typeof(slots) ~= "table" then
		return false
	end

	local normalized = tostring(slotId)
	local slot = slots[normalized]

	return typeof(slot) == "table"
		and slot.State == "Alive"
		and typeof(slot.CurrentLife) == "table"
end

local function resolveQuickPlaySlot(): string?
	-- Do not build this as a sparse array: ipairs stops at the first nil.
	local candidates: {any} = {}

	local function addCandidate(value: any)
		if value ~= nil then
			table.insert(candidates, value)
		end
	end

	addCandidate(lastUsedSlotId)
	addCandidate(currentState and currentState.LastUsedSlotId)
	addCandidate(currentState and currentState.QuickPlaySlotId)
	addCandidate(currentState and currentState.FocusSlotId)
	addCandidate(player:GetAttribute("FrontendLastUsedSlotId"))
	addCandidate(selectedSlotId)

	for _, candidate in ipairs(candidates) do
		if isPlayableSlotId(candidate) then
			return tostring(candidate)
		end
	end

	local snapshot = currentState and currentState.Snapshot
	local slots = snapshot and snapshot.Slots
	if typeof(slots) ~= "table" then
		return nil
	end

	local playable: {string} = {}
	for slotId, _ in pairs(slots) do
		if isPlayableSlotId(slotId) then
			table.insert(playable, tostring(slotId))
		end
	end

	table.sort(playable, slotSort)
	return playable[1]
end

local function refreshMainMenuAvailability()
	local ready =
		currentState ~= nil
		and currentState.Ready == true

	mainMenuUI.setPlayEnabled(ready)
	mainMenuUI.setQuickplayEnabled(ready and resolveQuickPlaySlot() ~= nil)
end

local function recordLastUsedSlot(slotId: string)
	lastUsedSlotId = slotId
	player:SetAttribute("FrontendLastUsedSlotId", slotId)

	task.spawn(function()
		menuPreferencesInvoke("SetLastSlot", {
			SlotId = slotId,
		})
	end)
end

local function playSlotRequest(slotId: string, serverInstanceId: string?): any
	recordLastUsedSlot(slotId)

	local payload: {[string]: any} = {
		SlotId = slotId,
	}

	if serverInstanceId and serverInstanceId ~= "" then
		payload.ServerInstanceId = serverInstanceId
	end

	return invoke("PlaySlot", payload)
end

local function clearDynamic(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function natures(origin: any): string
	if typeof(origin) ~= "table" then
		return "Unknown"
	end

	local values = {}

	for _, id in ipairs({
		origin.Nature1Id,
		origin.Nature2Id,
		origin.Nature3Id,
		}) do
		if typeof(id) == "string" and id ~= "" then
			table.insert(values, id)
		end
	end

	return #values > 0 and table.concat(values, " + ") or "Unknown"
end

local renderSlots: () -> ()

local VILLAGE_OPTIONS = {
	{ Id = "Leaf", DisplayName = "Leaf" },
	{ Id = "Sand", DisplayName = "Sand" },
	{ Id = "Mist", DisplayName = "Mist" },
	{ Id = "Cloud", DisplayName = "Cloud" },
	{ Id = "Stone", DisplayName = "Stone" },
}

local function natureDisplayName(natureId: string): string
	return natureId
end

local function cycleIndex(current: number, count: number): number
	if count <= 0 then
		return 1
	end

	return (current % count) + 1
end

local function cycleIndexBy(
	current: number,
	count: number,
	delta: number
): number
	if count <= 0 then
		return 1
	end

	return ((current - 1 + delta) % count) + 1
end

local function getEnabledClothingColors(
	catalog: any
): {any}
	local result = {}

	if not catalog
		or typeof(catalog.ClothingColors) ~= "table" then

		return result
	end

	for _, entry in ipairs(catalog.ClothingColors) do
		if typeof(entry) == "table"
			and entry.Enabled ~= false then

			table.insert(result, entry)
		end
	end

	return result
end

local function enabledWearableOptions(raw: any): {any}
	local result = {}

	if typeof(raw) ~= "table" then
		return result
	end

	for _, entry in ipairs(raw) do
		if typeof(entry) == "table"
			and entry.Enabled ~= false then

			table.insert(
				result,
				entry
			)
		end
	end

	return result
end

local function getEnabledShoes(catalog: any): {any}
	return enabledWearableOptions(
		catalog
			and catalog.ShoesStyles
			or nil
	)
end

local function getEnabledGloves(catalog: any): {any}
	return enabledWearableOptions(
		catalog
			and catalog.GlovesStyles
			or nil
	)
end

local function getAppearanceCatalog(): (any?, string?)
	if cachedAppearanceCatalog then
		return cachedAppearanceCatalog, nil
	end

	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("AppearanceCatalog")

	if not module or not module:IsA("ModuleScript") then
		return nil, "AppearanceCatalog is missing."
	end

	local ok, result = pcall(require, module)
	if not ok then
		return nil, "AppearanceCatalog failed to load."
	end

	cachedAppearanceCatalog = result
	return cachedAppearanceCatalog, nil
end

local function getEnabledOptions(raw: any): {any}
	local result = {}

	if typeof(raw) ~= "table" then
		return result
	end

	for _, entry in ipairs(raw) do
		if typeof(entry) == "table"
			and entry.Enabled ~= false then

			table.insert(result, entry)
		end
	end

	return result
end

local function setMainCamera()
	local currentCamera =
		Workspace.CurrentCamera

	local cameraAnchor =
		waitForSceneMarker(
			"CameraAnchor",
			5
		)

	local cameraFocus =
		waitForSceneMarker(
			"CameraFocus",
			5
		)

	if currentCamera
		and cameraAnchor
		and cameraFocus then

		currentCamera.CameraType =
			Enum.CameraType.Scriptable

		currentCamera.FieldOfView =
			defaultCameraFieldOfView

		currentCamera.CFrame =
			CFrame.lookAt(
				cameraAnchor.Position,
				cameraFocus.Position
			)
	end
end

local function setCreationCamera(): boolean
	local currentCamera =
		Workspace.CurrentCamera

	local cameraAnchor =
		waitForSceneMarker(
			"CharacterCreationCamera",
			10
		)

	local cameraFocus =
		waitForSceneMarker(
			"CharacterCreationFocus",
			10
		)

	if not currentCamera
		or not cameraAnchor
		or not cameraFocus then

		return false
	end

	currentCamera.CameraType =
		Enum.CameraType.Scriptable

	currentCamera.FieldOfView =
		creationCameraFieldOfView

	local baseLook =
		CFrame.lookAt(
			cameraAnchor.Position,
			cameraFocus.Position
		)

	local biasedFocus =
		cameraFocus.Position
	- (
		baseLook.RightVector
			* CREATION_RIGHT_COMPOSITION_BIAS
	)

	currentCamera.CFrame =
		CFrame.lookAt(
			cameraAnchor.Position,
			biasedFocus
		)

	return true
end

local function getCreationSpawn(): BasePart?
	return waitForSceneMarker(
		"CharacterCreationSpawn",
		10
	)
end

local function destroyPreviewModel()
	if previewModel then
		previewModel:Destroy()
	end

	previewModel = nil
end

local function parseHairInput(value: string): number?
	local digits =
		string.match(
			value,
			"(%d+)"
		)

	local assetId =
		digits and tonumber(digits) or nil

	if not assetId
		or assetId <= 0 then

		return nil
	end

	return math.floor(assetId)
end

local function setModelPreviewPhysics(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	local root =
		model:FindFirstChild("HumanoidRootPart")

	if root and root:IsA("BasePart") then
		root.Anchored = true
	end

	local humanoid =
		model:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid.DisplayDistanceType =
			Enum.HumanoidDisplayDistanceType.None

		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
	end
end

local function placePreviewAtSpawn(
	model: Model,
	spawn: BasePart
)
	-- Always rebuild the preview transform from the scene spawn.
	-- Never use the full model bounding box here: hair/accessories can change
	-- its AABB while rotating and caused the mannequin to climb upward.
	local spawnCFrame =
		spawn.CFrame
		* CFrame.Angles(
			0,
			math.rad(
				previewYawDegrees
			),
			0
		)

	model:PivotTo(
		spawnCFrame
	)

	local lowestBodyY =
		math.huge

	for _, partName in ipairs({
		"Left Leg",
		"Right Leg",
		}) do
		local part =
			model:
			FindFirstChild(
				partName
			)

		if part
			and part:IsA("BasePart") then

			local partBottomY =
				part.Position.Y
			- (part.Size.Y * 0.5)

			lowestBodyY =
				math.min(
					lowestBodyY,
					partBottomY
				)
		end
	end

	if lowestBodyY == math.huge then
		return
	end

	local targetBottomY =
		spawn.Position.Y
		+ PREVIEW_FOOT_CLEARANCE

	local deltaY =
		targetBottomY
	- lowestBodyY

	if math.abs(deltaY) > 0.0001 then
		model:PivotTo(
			model:GetPivot()
				+ Vector3.new(
					0,
					deltaY,
					0
				)
		)
	end
end

local function refreshCreationView()
	setCreationCamera()

	if previewModel
		and previewModel.Parent then

		local spawn =
			getCreationSpawn()

		if spawn then
			placePreviewAtSpawn(
				previewModel,
				spawn
			)
		end
	end
end

local function rotatePreview(deltaDegrees: number)
	previewYawDegrees =
		(previewYawDegrees + deltaDegrees)
		% 360

	refreshCreationView()
end

local function setCreationZoomTarget(
	targetFov: number
)
	creationCameraTargetFieldOfView =
		math.clamp(
			targetFov,
			CREATION_MIN_FOV,
			CREATION_MAX_FOV
		)
end

local function zoomCreation(deltaFov: number)
	setCreationZoomTarget(
		creationCameraTargetFieldOfView
			+ deltaFov
	)
end

local function resetCreationView()
	previewYawDegrees = 0

	creationCameraFieldOfView =
		CREATION_DEFAULT_FOV

	creationCameraTargetFieldOfView =
		CREATION_DEFAULT_FOV

	refreshCreationView()
end

local function pointIsInGuiObject(
	guiObject: GuiObject,
	point: Vector2
): boolean
	local position =
		guiObject.AbsolutePosition

	local size =
		guiObject.AbsoluteSize

	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

local function canBeginSceneDrag(
	screenPoint: Vector2
): boolean
	if not creationPage.Visible then
		return false
	end

	-- The Astra HUD uses two side scrolls with the 3D character in the center.
	-- Only the transparent center opening starts drag rotation.
	return pointIsInGuiObject(
		creationUI.sceneHitbox,
		screenPoint
	)
end

local function hasNativeR6Body(
	model: Model
): boolean
	for _, name in ipairs({
		"Head",
		"Torso",
		"Left Arm",
		"Right Arm",
		"Left Leg",
		"Right Leg",
		"HumanoidRootPart",
		}) do
		if not model:
			FindFirstChild(name) then

			return false
		end
	end

	return model:
		FindFirstChildOfClass("Humanoid")
		~= nil
end

local function addPreviewLighting(
	model: Model
)
	local head =
		model:FindFirstChild("Head")

	local torso =
		model:FindFirstChild("Torso")

	if head
		and head:IsA("BasePart") then

		local light =
			Instance.new("PointLight")

		light.Name =
			"WAYLESSPreviewKeyLight"

		light.Brightness = 1.8
		light.Range = 12
		light.Shadows = false
		light.Parent = head
	end

	if torso
		and torso:IsA("BasePart") then

		local fill =
			Instance.new("PointLight")

		fill.Name =
			"WAYLESSPreviewFillLight"

		fill.Brightness = 1.1
		fill.Range = 10
		fill.Shadows = false
		fill.Parent = torso
	end
end

local function starterOutfitTemplates(
	top: any,
	bottom: any
): (string?, string?)
	local shirtTemplate: string? = nil
	local pantsTemplate: string? = nil

	if typeof(top) == "table"
		and typeof(top.ShirtTemplate) == "string"
		and top.ShirtTemplate ~= "" then

		shirtTemplate =
			top.ShirtTemplate
	end

	if typeof(bottom) == "table"
		and typeof(bottom.PantsTemplate) == "string"
		and bottom.PantsTemplate ~= "" then

		pantsTemplate =
			bottom.PantsTemplate
	end

	return shirtTemplate,
		pantsTemplate
end

local function applyPreviewClassicClothing(
	model: Model,
	top: any,
	bottom: any
)
	for _, child in ipairs(
		model:GetChildren()
		) do
		if child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
			or child:IsA("CharacterMesh") then

			child:Destroy()
		end
	end

	local shirtTemplate,
		pantsTemplate =
		starterOutfitTemplates(
			top,
			bottom
		)

	if shirtTemplate then
		local shirt =
			Instance.new("Shirt")

		shirt.Name =
			"WAYLESSStarterTop"

		shirt.ShirtTemplate =
			shirtTemplate

		shirt.Parent = model
	end

	if pantsTemplate then
		local pants =
			Instance.new("Pants")

		pants.Name =
			"WAYLESSStarterBottom"

		pants.PantsTemplate =
			pantsTemplate

		pants.Parent = model
	end
end

local R6_WEARABLE_ATTACHMENTS = {
	{
		PartName = "Left Arm",
		AttachmentName = "WAYLESS_LeftGloveAttachment",
		Position = Vector3.new(0, -0.80, 0),
		Orientation = Vector3.new(90, 180, 0),
	},
	{
		PartName = "Right Arm",
		AttachmentName = "WAYLESS_RightGloveAttachment",
		Position = Vector3.new(0, -0.80, 0),
		Orientation = Vector3.new(90, 0, 0),
	},
	{
		PartName = "Left Leg",
		AttachmentName = "WAYLESS_LeftShoeAttachment",
		Position = Vector3.new(0, -1, 0),
		Orientation = Vector3.new(0, 180, 0),
	},
	{
		PartName = "Right Leg",
		AttachmentName = "WAYLESS_RightShoeAttachment",
		Position = Vector3.new(0, -1, 0),
		Orientation = Vector3.new(0, 180, 0),
	},
}

local function ensureR6WearableAttachments(
	character: Model
)
	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.RigType
		~= Enum.HumanoidRigType.R6 then

		return
	end

	for _, definition in ipairs(
		R6_WEARABLE_ATTACHMENTS
		) do
		local bodyPart =
			character:
			FindFirstChild(
				definition.PartName
			)

		if bodyPart
			and bodyPart:IsA("BasePart") then

			local attachment =
				bodyPart:
				FindFirstChild(
					definition.AttachmentName
				)

			if attachment
				and not attachment:IsA("Attachment") then

				attachment:Destroy()
				attachment = nil
			end

			if not attachment then
				attachment =
					Instance.new(
						"Attachment"
					)

				attachment.Name =
					definition.AttachmentName

				attachment.Parent =
					bodyPart
			end

			local typedAttachment =
				attachment :: Attachment

			typedAttachment.Position =
				definition.Position

			typedAttachment.Orientation =
				definition.Orientation
		end
	end
end

local function removePreviewWearables(
	model: Model,
	categoryName: string
)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory")
			and child:GetAttribute(
				"WAYLESSWearableCategory"
			) == categoryName then

			child:Destroy()
		end
	end
end

local function getWearableStyleFolder(
	categoryName: string,
	styleId: string
): Folder?
	local shared =
		ReplicatedStorage:
		WaitForChild(
			"Shared",
			5
		)

	if not shared then
		return nil
	end

	local root =
		shared:
		WaitForChild(
			"CharacterWearableTemplates",
			8
		)

	if not root then
		return nil
	end

	local category =
		root:
		WaitForChild(
			categoryName,
			3
		)

	if not category then
		return nil
	end

	local style =
		category:
		WaitForChild(
			styleId,
			3
		)

	return style
		and style:IsA("Folder")
		and style
		or nil
end

local function findCharacterAttachment(
	character: Model,
	attachmentName: string
): Attachment?
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Attachment")
			and descendant.Name == attachmentName then

			local accessoryAncestor =
				descendant:
				FindFirstAncestorOfClass(
					"Accessory"
				)

			if not accessoryAncestor then
				return descendant
			end
		end
	end

	return nil
end

local function findWearableHandleAttachment(
	accessory: Accessory
): Attachment?
	local handle =
		accessory:
		FindFirstChild(
			"Handle"
		)

	if not handle
		or not handle:IsA("BasePart") then

		return nil
	end

	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment")
			and string.sub(
				child.Name,
				1,
				8
			) == "WAYLESS_" then

			return child
		end
	end

	return nil
end

local function weldWearableAccessory(
	character: Model,
	accessory: Accessory
): boolean
	local handle =
		accessory:
		FindFirstChild(
			"Handle"
		)

	if not handle
		or not handle:IsA("BasePart") then

		return false
	end

	local handleAttachment =
		findWearableHandleAttachment(
			accessory
		)

	if not handleAttachment then
		return false
	end

	local bodyAttachment =
		findCharacterAttachment(
			character,
			handleAttachment.Name
		)

	if not bodyAttachment
		or not bodyAttachment.Parent
		or not bodyAttachment.Parent:IsA("BasePart") then

		warn(
			"[WAYLESS Wearable] BODY ATTACHMENT MISSING",
			handleAttachment.Name
		)

		return false
	end

	local bodyPart =
		bodyAttachment.Parent :: BasePart

	local oldWeld =
		handle:
		FindFirstChild(
			"AccessoryWeld"
		)

	if oldWeld then
		oldWeld:Destroy()
	end

	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Massless = true

	accessory.Parent =
		character

	handle.CFrame =
		bodyAttachment.WorldCFrame
		* handleAttachment.CFrame:Inverse()

	local weld =
		Instance.new(
			"Weld"
		)

	weld.Name =
		"AccessoryWeld"

	weld.Part0 =
		bodyPart

	weld.Part1 =
		handle

	weld.C0 =
		bodyAttachment.CFrame

	weld.C1 =
		handleAttachment.CFrame

	weld.Parent =
		handle

	return true
end

local function applyPreviewWearable(
	model: Model,
	categoryName: string,
	style: any
)
	removePreviewWearables(
		model,
		categoryName
	)

	if typeof(style) ~= "table"
		or typeof(style.Id) ~= "string" then

		return
	end

	if style.None == true then
		return
	end

	local template =
		getWearableStyleFolder(
			categoryName,
			style.Id
		)

	if not template then
		warn(
			"[FrontendController] WEARABLE TEMPLATE MISSING",
			categoryName,
			style.Id
		)

		return
	end

	ensureR6WearableAttachments(
		model
	)

	local attachedCount = 0

	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("Accessory") then
			local clone =
				child:Clone()

			clone:SetAttribute(
				"WAYLESSWearableCategory",
				categoryName
			)

			clone:SetAttribute(
				"WAYLESSWearableStyleId",
				style.Id
			)

			if weldWearableAccessory(
				model,
				clone
				) then

				attachedCount += 1
			else
				clone:Destroy()

				warn(
					"[FrontendController] WEARABLE ATTACH FAILED",
					categoryName,
					style.Id,
					child.Name
				)
			end
		end
	end

	print(
		"[FrontendController] WEARABLE APPLIED",
		categoryName,
		style.Id,
		"Count=" .. tostring(attachedCount)
	)
end

local function applyPreviewWearables(
	model: Model,
	shoes: any,
	gloves: any
)
	applyPreviewWearable(
		model,
		"Shoes",
		shoes
	)

	applyPreviewWearable(
		model,
		"Gloves",
		gloves
	)
end

local function buildPreviewDescription(
	skin: any,
	top: any,
	bottom: any
): HumanoidDescription
	local description =
		Instance.new(
			"HumanoidDescription"
		)

	local color =
		typeof(skin) == "table"
		and skin.Color
		or nil

	if typeof(color) == "Color3" then
		description.HeadColor = color
		description.LeftArmColor = color
		description.RightArmColor = color
		description.LeftLegColor = color
		description.RightLegColor = color
		description.TorsoColor = color
	end

	if #selectedHairAssetIds > 0 then
		description.HairAccessory =
			table.concat(
				selectedHairAssetIds,
				","
			)
	end

	return description
end

local function rebuildPreviewModel(
	skin: any,
	top: any,
	bottom: any,
	shoes: any,
	gloves: any
): (boolean, string)
	local spawn =
		getCreationSpawn()

	if not spawn then
		return false,
			"Character Creation scene did not replicate. Check FrontendWorldBootstrap v3."
	end

	local description =
		buildPreviewDescription(
			skin,
			top,
			bottom,
			shoes,
			gloves
		)

	local modelOk, modelResult =
		pcall(function()
			return Players:
			CreateHumanoidModelFromDescriptionAsync(
				description,
				Enum.HumanoidRigType.R6
			)
		end)

	description:Destroy()

	if not modelOk
		or typeof(modelResult) ~= "Instance"
		or not modelResult:IsA("Model") then

		warn(
			"[FrontendController] R6 PREVIEW CREATE FAILED",
			modelResult
		)

		return false,
			"Could not load the selected appearance preview."
	end

	local newModel =
		modelResult :: Model

	if not hasNativeR6Body(
		newModel
		) then

		newModel:Destroy()

		return false,
			"Roblox returned an incomplete R6 preview mannequin."
	end

	if previewModel then
		previewModel:Destroy()
	end

	previewModel =
		newModel

	previewModel.Name =
		"CharacterCreationPreview_LOCAL"

	previewModel.Parent =
		Workspace

	setModelPreviewPhysics(
		previewModel
	)

	addPreviewLighting(
		previewModel
	)

	applyPreviewClassicClothing(
		previewModel,
		top,
		bottom
	)

	applyPreviewWearables(
		previewModel,
		shoes,
		gloves
	)

	placePreviewAtSpawn(
		previewModel,
		spawn
	)

	local root =
		previewModel:
		FindFirstChild(
			"HumanoidRootPart"
		)

	print(
		"[FrontendController] R6 PREVIEW BUILT",
		"HairCount="
			.. tostring(
				#selectedHairAssetIds
			),
		"Spawn="
			.. tostring(
				spawn.Position
			),
		"Root="
			.. tostring(
				root
				and (root :: BasePart).Position
				or "missing"
			)
	)

	return true, "PreviewReady"
end

local function selectedAppearanceEntries(): (any?, any?, any?, any?, any?, any?, any?, any?, any?)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return nil, nil, nil, nil, nil, nil, nil
	end

	local skins = getEnabledOptions(catalog.SkinTones)
	local mouths = getEnabledOptions(catalog.MouthStyles)
	local brows = getEnabledOptions(catalog.BrowStyles)
	local noses = getEnabledOptions(catalog.NoseStyles)
	local eyes = getEnabledOptions(catalog.EyeStyles)
	local shoes = getEnabledShoes(catalog)
	local gloves = getEnabledGloves(catalog)

	local colors =
		getEnabledClothingColors(
			catalog
		)

	local topColor =
		colors[selectedTopColorIndex]

	local bottomColor =
		colors[selectedBottomColorIndex]

	local topId =
		topColor
		and typeof(topColor.TopIds) == "table"
		and topColor.TopIds[selectedTopIndex]
		or nil

	local bottomId =
		bottomColor
		and typeof(bottomColor.BottomIds) == "table"
		and bottomColor.BottomIds[selectedBottomIndex]
		or nil

	local top =
		typeof(topId) == "string"
		and catalog.GetStarterTop(topId)
		or nil

	local bottom =
		typeof(bottomId) == "string"
		and catalog.GetStarterBottom(bottomId)
		or nil

	return skins[selectedSkinIndex],
		mouths[selectedMouthIndex],
		brows[selectedBrowIndex],
		noses[selectedNoseIndex],
		eyes[selectedEyeIndex],
		top,
		bottom,
		shoes[selectedShoesIndex],
		gloves[selectedGlovesIndex]
end

local FACE_DECAL_NAMES = {
	face = true,
	Face = true,
	WAYLESS_Eyes = true,
	WAYLESS_Brows = true,
	WAYLESS_Nose = true,
	WAYLESS_Mouth = true,
}

local function clearFaceVisuals(
	head: BasePart
)
	for _, child in ipairs(
		head:GetChildren()
		) do
		if child:IsA("Decal")
			and FACE_DECAL_NAMES[child.Name] then

			child:Destroy()

		elseif child:IsA("SurfaceGui")
			and child.Name == "WAYLESSFaceGui" then

			-- Cleanup for characters/previews created by the previous version.
			child:Destroy()
		end
	end
end

local function addFaceDecal(
	head: BasePart,
	name: string,
	image: any,
	zIndex: number
)
	if typeof(image) ~= "string"
		or image == "" then

		return
	end

	local decal =
		Instance.new("Decal")

	decal.Name = name
	decal.Face = Enum.NormalId.Front
	decal.Texture = image

	-- Transparent PNGs stack naturally. ZIndex keeps deterministic ordering:
	-- eyes below brows below mouth.
	pcall(function()
		decal.ZIndex = zIndex
	end)

	decal.Parent = head
end

local function applyFaceLayers(
	model: Model,
	mouthEntry: any,
	browEntry: any,
	noseEntry: any,
	eyeEntry: any
)
	local head =
		model:FindFirstChild("Head")

	if not head
		or not head:IsA("BasePart") then

		return
	end

	clearFaceVisuals(head)

	addFaceDecal(
		head,
		"WAYLESS_Eyes",
		typeof(eyeEntry) == "table"
			and eyeEntry.Image
			or nil,
		10
	)

	addFaceDecal(
		head,
		"WAYLESS_Brows",
		typeof(browEntry) == "table"
			and browEntry.Image
			or nil,
		20
	)

	addFaceDecal(
		head,
		"WAYLESS_Nose",
		typeof(noseEntry) == "table"
			and noseEntry.Image
			or nil,
		25
	)

	addFaceDecal(
		head,
		"WAYLESS_Mouth",
		typeof(mouthEntry) == "table"
			and mouthEntry.Image
			or nil,
		30
	)
end

local function refreshPreviewClothingInPlace()
	if not previewModel
		or not previewModel.Parent then

		return
	end

	local _, _, _, _, _, top, bottom =
		selectedAppearanceEntries()

	if not top
		or not bottom then

		return
	end

	applyPreviewClassicClothing(
		previewModel,
		top,
		bottom
	)

	refreshCreationView()
	status.Text = "Creator ready"
end

local function refreshPreviewWearablesInPlace()
	if not previewModel
		or not previewModel.Parent then

		return
	end

	local _, _, _, _, _, _, _, shoes, gloves =
		selectedAppearanceEntries()

	if not shoes
		or not gloves then

		return
	end

	applyPreviewWearables(
		previewModel,
		shoes,
		gloves
	)

	refreshCreationView()
	status.Text = "Creator ready"
end

local function applyPreviewAppearanceOnce()
	local skin, mouth, brow, nose, eye, top, bottom, shoes, gloves =
		selectedAppearanceEntries()

	if not skin
		or not mouth
		or not brow
		or not nose
		or not eye
		or not shoes
		or not gloves then
		status.Text =
			"No skin tone is selected."
		return
	end

	local ready, reason =
		rebuildPreviewModel(
			skin,
			top,
			bottom,
			shoes,
			gloves
		)

	if not ready
		or not previewModel then

		status.Text = reason
		return
	end

	applyFaceLayers(
		previewModel,
		mouth,
		brow,
		nose,
		eye
	)

	refreshCreationView()

	status.Text = "Creator ready"
end

local function requestPreviewRefresh()
	previewRefreshRequested = true

	if previewRefreshRunning then
		return
	end

	previewRefreshRunning = true

	task.spawn(function()
		while previewRefreshRequested do
			previewRefreshRequested = false
			applyPreviewAppearanceOnce()
		end

		previewRefreshRunning = false
	end)
end

local function rebuildSkinSwatches()
	for _, child in ipairs(
		creationUI.skinSwatchFrame:GetChildren()
		) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	local skins =
		getEnabledOptions(
			catalog.SkinTones
		)

	print("[CharacterCreator] Skin swatches:", #skins)

	selectedSkinIndex =
		math.clamp(
			selectedSkinIndex,
			1,
			math.max(1, #skins)
		)

	for index, entry in ipairs(skins) do
		local swatch =
			Instance.new("TextButton")

		swatch.Name =
			"Skin_"
			.. tostring(entry.Id)

		swatch.Size =
			UDim2.fromOffset(
				34,
				44
			)

		swatch.BackgroundColor3 =
			entry.Color

		-- The parchment panel is rendered above ZIndex 100. Child GUI objects do
		-- not inherit the parent's ZIndex, so the old swatches stayed at the
		-- default ZIndex 1 and were hidden behind the panel image.
		swatch.ZIndex = 141
		swatch.LayoutOrder = index
		swatch.BorderSizePixel = 0
		swatch.BackgroundTransparency = 0
		swatch.Visible = true
		swatch.Active = true
		swatch.Text = ""
		swatch.AutoButtonColor = false
		swatch.Parent =
			creationUI.skinSwatchFrame

		local corner =
			Instance.new("UICorner")

		corner.CornerRadius =
			UDim.new(0, 2)

		corner.Parent = swatch

		local stroke =
			Instance.new("UIStroke")

		stroke.Thickness =
			index == selectedSkinIndex
			and 2
			or 1

		stroke.Color =
			index == selectedSkinIndex
			and Color3.fromRGB(133, 59, 52)
			or Color3.fromRGB(121, 105, 87)

		stroke.Transparency =
			index == selectedSkinIndex
			and 0
			or 0.35

		stroke.Parent = swatch

		swatch.MouseButton1Click:
			Connect(function()
				selectedSkinIndex = index
				rebuildSkinSwatches()
				requestPreviewRefresh()
			end)
	end
end

local function refreshCreationButtons()
	local village =
		creationVillages[
	selectedVillageIndex
	]

	local nature =
		creationNatures[
	selectedNatureIndex
	]

	local villageDisplayName =
		tostring(
			village
			and village.DisplayName
			or "-"
		)

	local natureDisplay =
		tostring(
			nature
			and nature.DisplayName
			or "-"
		)

	creationUI.villageValueButton.Text = villageDisplayName
	creationUI.natureValueButton.Text = natureDisplay
	creationUI.setVillageIcon(villageDisplayName)
	creationUI.setNatureIcon(natureDisplay)

	local catalog = cachedAppearanceCatalog

	if catalog then
		local mouths = getEnabledOptions(catalog.MouthStyles)
		local brows = getEnabledOptions(catalog.BrowStyles)
		local noses = getEnabledOptions(catalog.NoseStyles)
		local eyes = getEnabledOptions(catalog.EyeStyles)
		local shoes = getEnabledShoes(catalog)
		local gloves = getEnabledGloves(catalog)
		local colors = getEnabledClothingColors(catalog)

		selectedMouthIndex =
			math.clamp(
				selectedMouthIndex,
				1,
				math.max(1, #mouths)
			)

		selectedBrowIndex =
			math.clamp(
				selectedBrowIndex,
				1,
				math.max(1, #brows)
			)

		selectedNoseIndex =
			math.clamp(
				selectedNoseIndex,
				1,
				math.max(1, #noses)
			)

		selectedEyeIndex =
			math.clamp(
				selectedEyeIndex,
				1,
				math.max(1, #eyes)
			)

		selectedShoesIndex =
			math.clamp(
				selectedShoesIndex,
				1,
				math.max(1, #shoes)
			)

		selectedGlovesIndex =
			math.clamp(
				selectedGlovesIndex,
				1,
				math.max(1, #gloves)
			)

		selectedTopColorIndex =
			math.clamp(
				selectedTopColorIndex,
				1,
				math.max(1, #colors)
			)

		-- The final Astra HUD intentionally exposes one shared clothing color.
		-- Keep both canonical state fields synchronized so persistence remains unchanged.
		selectedBottomColorIndex = selectedTopColorIndex

		local topColor =
			colors[selectedTopColorIndex]

		local bottomColor = topColor

		local topCount =
			topColor
			and typeof(topColor.TopIds) == "table"
			and #topColor.TopIds
			or 0

		local bottomCount =
			bottomColor
			and typeof(bottomColor.BottomIds) == "table"
			and #bottomColor.BottomIds
			or 0

		selectedTopIndex =
			math.clamp(
				selectedTopIndex,
				1,
				math.max(1, topCount)
			)

		selectedBottomIndex =
			math.clamp(
				selectedBottomIndex,
				1,
				math.max(1, bottomCount)
			)

		creationUI.eyeStyleValue.Text =
			string.format("%02d / %02d", selectedEyeIndex, #eyes)

		creationUI.browStyleValue.Text =
			string.format("%02d / %02d", selectedBrowIndex, #brows)

		creationUI.noseStyleValue.Text =
			string.format("%02d / %02d", selectedNoseIndex, #noses)

		creationUI.mouthStyleValue.Text =
			string.format("%02d / %02d", selectedMouthIndex, #mouths)

		creationUI.shoesStyleValue.Text =
			string.format("%02d / %02d", selectedShoesIndex, #shoes)

		local selectedGloves =
			gloves[selectedGlovesIndex]

		if selectedGloves
			and selectedGloves.None == true then

			creationUI.glovesStyleValue.Text = "NONE"
		else
			local realIndex = 0
			local realCount = 0

			for _, entry in ipairs(gloves) do
				if entry.None ~= true then
					realCount += 1

					if entry == selectedGloves then
						realIndex =
							realCount
					end
				end
			end

			creationUI.glovesStyleValue.Text =
				string.format(
					"%02d / %02d",
					math.max(1, realIndex),
					math.max(1, realCount)
				)
		end

		creationUI.colorValue.Text =
			string.format(
				"%02d / %02d",
				selectedTopColorIndex,
				#colors
			)

		creationUI.starterTopValue.Text =
			string.format(
				"%02d / %02d",
				selectedTopIndex,
				topCount
			)

		creationUI.starterBottomValue.Text =
			string.format(
				"%02d / %02d",
				selectedBottomIndex,
				bottomCount
			)
	end
end

local function enterCreationPresentation()
	previewYawDegrees = 0

	creationCameraFieldOfView =
		CREATION_DEFAULT_FOV

	creationCameraTargetFieldOfView =
		CREATION_DEFAULT_FOV

	-- Character Creation owns the full screen. The real 3D scene remains visible
	-- through the transparent center between Astra's two parchment panels.
	shell.Visible = false
	background.Visible = false
	status.Visible = false

	if not setCreationCamera() then
		status.Text =
			"Character Creation camera markers are missing."
	end
end

local function exitCreationPresentation()
	destroyPreviewModel()

	shell.Visible = true
	background.Visible = true
	status.Visible = true

	setMainCamera()
end

local function openCreation(slotId: string)
	selectedSlotId = slotId

	local snapshot =
		currentState
		and currentState.Snapshot

	local slot =
		snapshot
		and snapshot.Slots
		and snapshot.Slots[slotId]

	if not slot then
		status.Text =
			"Creator error: slot snapshot missing."
		return
	end

	if slot.State ~= "Empty"
		and slot.State ~= "Creating" then

		status.Text =
			"Creator error: slot is not available."
		return
	end

	if typeof(slot.PermanentOrigin)
		~= "table" then

		status.Text =
			"Creator error: slot genetics missing."
		return
	end

	local catalog, catalogReason =
		getAppearanceCatalog()

	if not catalog then
		status.Text =
			catalogReason
			or "Appearance Catalog is unavailable."
		return
	end

	creationVillages = {}

	for _, village in ipairs(VILLAGE_OPTIONS) do
		table.insert(
			creationVillages,
			{
				Id = village.Id,
				DisplayName =
					village.DisplayName,
			}
		)
	end

	creationNatures = {}

	for _, natureId in ipairs({
		slot.PermanentOrigin.Nature1Id,
		slot.PermanentOrigin.Nature2Id,
		slot.PermanentOrigin.Nature3Id,
		}) do
		if typeof(natureId) == "string"
			and natureId ~= "" then

			table.insert(
				creationNatures,
				{
					Id = natureId,
					DisplayName =
						natureDisplayName(
							natureId
						),
				}
			)
		end
	end

	if #creationVillages == 0 then
		status.Text =
			"Creator error: no villages configured."
		return
	end

	if #creationNatures == 0 then
		status.Text =
			"Creator error: no innate natures."
		return
	end

	local skins =
		getEnabledOptions(
			catalog.SkinTones
		)

	local mouths =
		getEnabledOptions(
			catalog.MouthStyles
		)

	local brows =
		getEnabledOptions(
			catalog.BrowStyles
		)

	local noses =
		getEnabledOptions(
			catalog.NoseStyles
		)

	local eyes =
		getEnabledOptions(
			catalog.EyeStyles
		)

	local shoes =
		getEnabledShoes(
			catalog
		)

	local gloves =
		getEnabledGloves(
			catalog
		)

	local colors =
		getEnabledClothingColors(
			catalog
		)

	local firstColor =
		colors[1]

	local firstTopCount =
		firstColor
		and typeof(firstColor.TopIds) == "table"
		and #firstColor.TopIds
		or 0

	local firstBottomCount =
		firstColor
		and typeof(firstColor.BottomIds) == "table"
		and #firstColor.BottomIds
		or 0

	if #skins == 0
		or #mouths == 0
		or #brows == 0
		or #noses == 0
		or #eyes == 0
		or #shoes == 0
		or #gloves == 0
		or #colors == 0
		or firstTopCount == 0
		or firstBottomCount == 0 then

		status.Text =
			"Creator error: Appearance Catalog is incomplete."
		return
	end

	selectedVillageIndex = 1
	selectedNatureIndex = 1
	selectedSkinIndex =
		math.clamp(
			5,
			1,
			#skins
		)

	selectedMouthIndex = 1
	selectedBrowIndex = 1
	selectedNoseIndex = 1
	selectedEyeIndex = 1
	selectedShoesIndex = 1
	selectedGlovesIndex = 1
	selectedTopColorIndex = 1
	selectedBottomColorIndex = 1
	selectedTopIndex = 1
	selectedBottomIndex = 1
	selectedHairAssetIds = {}

	local origin = slot.PermanentOrigin

	creationUI.info.Text =
		"Slot "
		.. slotId
		.. "  •  Clan: "
		.. tostring(
			origin.ClanId
			or "Unknown"
		)
		.. "  •  Innate Natures: "
		.. natures(origin)

	creationUI.nameBox.Text = ""

	for _, box in ipairs(
		creationUI.hairIdBoxes
		) do
		box.Text = ""
	end

	refreshCreationButtons()

	showPage("Creation", {
		AfterSwap = function()
			rebuildSkinSwatches()
			enterCreationPresentation()

			status.Text =
				"Building 3D preview..."

			requestPreviewRefresh()
		end,
	})
end

frontendHUDs.ServerFlow = {}

function frontendHUDs.ServerFlow.normalizeServerEntry(server: any, index: number): any
	local playerCount = tonumber(server and (server.playerCount or server.Players or server.PlayerCount)) or 0
	local maxPlayers = tonumber(server and (server.maxPlayers or server.MaxPlayers or server.Capacity)) or 0
	local estimatedPingMs = tonumber(server and (server.estimatedPingMs or server.EstimatedPingMs))
	if estimatedPingMs and estimatedPingMs < 0 then
		estimatedPingMs = nil
	end
	local joinableField = server and (server.joinable or server.Joinable)
	local isFullField = server and (server.IsFull or server.Full)
	local joinable = true
	if typeof(joinableField) == "boolean" then
		joinable = joinableField
	elseif typeof(isFullField) == "boolean" then
		joinable = not isFullField
	end
	if maxPlayers > 0 and playerCount >= maxPlayers then
		joinable = false
	end
	return {
		serverId = tostring(server and (server.serverId or server.ServerId or server.JobId or server.Id or index) or index),
		jobId = tostring(server and (server.JobId or server.serverId or server.ServerId or "") or ""),
		displayName = tostring(server and (server.displayName or server.DisplayName or server.Name or server.PublicName or ("Server " .. tostring(index))) or ("Server " .. tostring(index))),
		playerCount = playerCount,
		maxPlayers = maxPlayers,
		regionLabel = tostring(server and (server.regionLabel or server.RegionLabel or server.Region or server.regionCode or "Unknown") or "Unknown"),
		estimatedPingMs = estimatedPingMs,
		joinable = joinable,
		raw = server,
	}
end

function frontendHUDs.ServerFlow.normalizedServerList(serverList: any): {any}
	local normalized = {}
	if typeof(serverList) ~= "table" then
		return normalized
	end
	for index, server in ipairs(serverList) do
		table.insert(normalized, frontendHUDs.ServerFlow.normalizeServerEntry(server, index))
	end
	return normalized
end

function frontendHUDs.ServerFlow.chooseQuickplayCandidate(serverList: any): any?
	local normalized = frontendHUDs.ServerFlow.normalizedServerList(serverList)
	local minPing: number? = nil

	for _, server in ipairs(normalized) do
		if server.joinable == true and typeof(server.estimatedPingMs) == "number" then
			if not minPing or server.estimatedPingMs < minPing then
				minPing = server.estimatedPingMs
			end
		end
	end

	-- If we do not have real latency estimates for the destination servers,
	-- return nil so Roblox matchmaking remains the honest fallback.
	if not minPing then
		return nil
	end

	local tolerance = 25
	local candidates = {}
	for _, server in ipairs(normalized) do
		if server.joinable == true
			and typeof(server.estimatedPingMs) == "number"
			and server.estimatedPingMs <= (minPing :: number) + tolerance then
			table.insert(candidates, server)
		end
	end

	table.sort(candidates, function(a, b)
		if a.playerCount ~= b.playerCount then
			return a.playerCount > b.playerCount
		end
		if a.estimatedPingMs ~= b.estimatedPingMs then
			return a.estimatedPingMs < b.estimatedPingMs
		end
		return tostring(a.serverId) < tostring(b.serverId)
	end)

	return candidates[1]
end

function frontendHUDs.ServerFlow.renderServers(serverList: any)
	local normalized = frontendHUDs.ServerFlow.normalizedServerList(serverList)
	if frontendHUDs.Servers then
		if #normalized > 0 then
			frontendHUDs.Servers.SetState("ready", { servers = normalized })
		else
			frontendHUDs.Servers.SetState("empty")
		end
		frontendHUDs.Servers.SetRefreshing(false)
		frontendHUDs.Servers.ResetJoinPending()
		return
	end

	warn("[FrontendController] ServerSelectorHUD unavailable; server list cannot render")
end

function frontendHUDs.ServerFlow.requestServers(refreshing: boolean?): any
	if frontendHUDs.Servers then
		if refreshing then
			frontendHUDs.Servers.SetRefreshing(true)
		else
			frontendHUDs.Servers.SetState("loading")
		end
	end

	local result = invoke("GetServers")
	if result and result.Servers ~= nil then
		frontendHUDs.ServerFlow.renderServers(result.Servers)
		return result
	end

	if frontendHUDs.Servers then
		frontendHUDs.Servers.SetRefreshing(false)
		frontendHUDs.Servers.SetState("error", {
			keepExisting = true,
			description = "Couldn’t refresh. Showing previous list.",
		})
	end
	return result
end

function frontendHUDs.ServerFlow.openServers(slotId: string)
	selectedSlotId = slotId
	if frontendHUDs.Servers then
		frontendHUDs.Servers.ResetJoinPending()
		frontendHUDs.Servers.SetState("loading")
	end
	showPage("Servers", {
		AfterSwap = function()
			frontendHUDs.ServerFlow.requestServers(false)
		end,
	})
end

renderSlots = function()
	clearDynamic(slotsScroll)

	local snapshot =
		currentState
		and currentState.Snapshot

	if not snapshot then
		return
	end

	local currencies = snapshot.Currencies or {}

	currencyLabel.Text =
		"Clan Rerolls "
		.. tostring(currencies.ClanRerolls or 0)
		.. "    •    Nature Rerolls "
		.. tostring(currencies.NatureRerolls or 0)
		.. "    •    Revival Tokens "
		.. tostring(currencies.RevivalTokens or 0)

	local ids = {}

	for slotId in pairs(snapshot.Slots or {}) do
		table.insert(ids, tostring(slotId))
	end

	table.sort(ids, slotSort)

	for index, slotId in ipairs(ids) do
		local slot = snapshot.Slots[slotId]

		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.Size = UDim2.new(1, -8, 0, 100)
		card.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
		card.BorderSizePixel = 0
		card.Parent = slotsScroll

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = card

		local titleText =
			"SLOT "
			.. slotId
			.. "  |  "
			.. tostring(slot.UnlockSource or "?")
			.. "  |  "
			.. tostring(slot.State or "?")

		local t = label(
			card,
			titleText,
			UDim2.fromOffset(14, 12),
			UDim2.new(1, -150, 0, 24),
			12
		)
		t.Font = Enum.Font.GothamBold

		local origin = slot.PermanentOrigin

		local info = label(
			card,
			"Clan: "
				.. tostring(origin and origin.ClanId or "Pending")
				.. "    |    Natures: "
				.. natures(origin),
			UDim2.fromOffset(14, 42),
			UDim2.new(1, -150, 0, 22),
			10
		)
		info.TextColor3 = Color3.fromRGB(157, 166, 184)

		local life = slot.CurrentLife

		local summary =
			life
			and life.Summary
			or nil

		local identityText =
			typeof(summary) == "table"
			and typeof(summary.GivenName) == "string"
			and summary.GivenName ~= ""
			and ("  |  " .. summary.GivenName)
			or ""

		local lifeText =
			life
			and (
				"Life #"
				.. tostring(life.LifeNumber or "?")
				.. identityText
				.. "  |  Revivals "
				.. tostring(life.RevivalCount or 0)
			)
			or "No current life"

		local lifeLabel = label(
			card,
			lifeText,
			UDim2.fromOffset(14, 68),
			UDim2.new(1, -150, 0, 20),
			10
		)
		lifeLabel.TextColor3 = Color3.fromRGB(128, 137, 155)

		local action =
			button(
				card,
				"...",
				UDim2.new(1, -130, 0, 30),
				UDim2.fromOffset(112, 40)
			)

		local state = tostring(slot.State)

		if state == "Alive" then
			action.Text = "PLAY"
			action.MouseButton1Click:Connect(function()
				frontendHUDs.ServerFlow.openServers(slotId)
			end)

		elseif state == "DeadAwaitingDecision" then
			action.Text = "AFTERLIFE"
			action.MouseButton1Click:Connect(function()
				invoke("ReturnAfterlife", {
					SlotId = slotId,
				})
			end)

		elseif state == "Empty" or state == "Creating" then
			action.Text =
				state == "Creating"
				and "CONTINUE"
				or "CREATE"

			action.MouseButton1Click:Connect(function()
				openCreation(slotId)
			end)

		else
			action.Text = "UNAVAILABLE"
			action.Active = false
			action.AutoButtonColor = false
			action.TextTransparency = 0.45
		end
	end
end


-- SLOT SELECTOR HUD / BINGO BOOK
-- Replaces the legacy list-style slot page with Astra's desk + card grid.
local slotSelectorHUDModule =
	sharedModules:FindFirstChild("SlotSelectorHUD")
	or sharedModules:FindFirstChild("SlotSelectorHUD_v1")

local SlotSelectorHUD = nil

if slotSelectorHUDModule
	and slotSelectorHUDModule:IsA("ModuleScript") then
	local ok, result = pcall(require, slotSelectorHUDModule)
	if ok then
		SlotSelectorHUD = result
	else
		warn("[FrontendController] Failed to require SlotSelectorHUD:", result)
	end
end

local serverSelectorHUDModule =
	sharedModules:FindFirstChild("ServerSelectorHUD")
	or sharedModules:FindFirstChild("ServerSelectorHUD_v1")

local ServerSelectorHUD = nil

if serverSelectorHUDModule
	and serverSelectorHUDModule:IsA("ModuleScript") then
	local ok, result = pcall(require, serverSelectorHUDModule)
	if ok then
		ServerSelectorHUD = result
	else
		warn("[FrontendController] Failed to require ServerSelectorHUD:", result)
	end
end

local function slotVillageIdFromRaw(raw: any): string
	local value = string.lower(tostring(raw or "leaf"))
	if string.find(value, "sand", 1, true) then return "sand" end
	if string.find(value, "mist", 1, true) then return "mist" end
	if string.find(value, "stone", 1, true) or string.find(value, "rock", 1, true) then return "stone" end
	if string.find(value, "cloud", 1, true) then return "cloud" end
	return "leaf"
end

local function slotVillageName(villageId: string): string
	local names = {
		leaf = "Hidden Leaf",
		sand = "Hidden Sand",
		mist = "Hidden Mist",
		stone = "Hidden Stone",
		cloud = "Hidden Cloud",
	}
	return names[villageId] or "Hidden Leaf"
end

local function firstStringFrom(container: any, keys: {string}): string?
	if typeof(container) ~= "table" then
		return nil
	end
	for _, key in ipairs(keys) do
		local value = container[key]
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

local function firstNumberFrom(container: any, keys: {string}): number?
	if typeof(container) ~= "table" then
		return nil
	end
	for _, key in ipairs(keys) do
		local value = container[key]
		if typeof(value) == "number" then
			return value
		elseif typeof(value) == "string" then
			local n = tonumber(value)
			if n then return n end
		end
	end
	return nil
end

local function buildSlotSelectorModels(): {any}
	local snapshot = currentState and currentState.Snapshot
	local slots = snapshot and snapshot.Slots
	if typeof(slots) ~= "table" then
		return {}
	end

	local ids = {}
	for slotId in pairs(slots) do
		table.insert(ids, tostring(slotId))
	end
	table.sort(ids, slotSort)

	local models = {}
	for order, slotId in ipairs(ids) do
		local slot = slots[slotId]
		if typeof(slot) == "table" then
			local rawState = tostring(slot.State or "Empty")
			local uiState = "empty"
			if rawState == "Alive" then
				uiState = "alive"
			elseif rawState == "DeadAwaitingDecision" then
				uiState = "afterlife"
			elseif rawState == "Empty" or rawState == "Creating" then
				uiState = "empty"
			end

			local life = slot.CurrentLife
			local summary = life and life.Summary or nil
			local firstName = firstStringFrom(summary, {"GivenName", "FirstName", "Name", "DisplayName"})
			local lastName = firstStringFrom(summary, {"Surname", "FamilyName", "LastName", "ClanSurname"})
			local fallbackClan = firstStringFrom(slot.PermanentOrigin, {"ClanName", "ClanId"})
			if not firstName then
				firstName = uiState == "empty" and "Empty" or ("Slot " .. tostring(slotId))
			end
			if not lastName and fallbackClan and uiState ~= "empty" then
				lastName = fallbackClan
			end
			local displayName = firstName
			if typeof(lastName) == "string" and lastName ~= "" then
				displayName ..= " " .. lastName
			end

			local rawVillage =
				firstStringFrom(summary, {"VillageId", "Village", "VillageName"})
				or firstStringFrom(life, {"VillageId", "Village", "VillageName"})
				or firstStringFrom(slot, {"VillageId", "Village", "VillageName"})
				or firstStringFrom(slot.PermanentOrigin, {"VillageId", "Village", "VillageName"})

			local villageId = slotVillageIdFromRaw(rawVillage)
			local level =
				firstNumberFrom(summary, {"Level", "CharacterLevel"})
				or firstNumberFrom(life, {"Level", "CharacterLevel"})
				or firstNumberFrom(slot, {"Level", "CharacterLevel"})
				or 1

			table.insert(models, {
				slotId = slotId,
				slotIndex = tonumber(slotId) or order,
				state = uiState,
				displayName = displayName,
				firstName = firstName,
				lastName = lastName or "",
				villageId = villageId,
				villageName = slotVillageName(villageId),
				level = level,
				sourceSlot = slot,
				rawState = rawState,
				appearance = typeof(summary) == "table" and summary.Appearance or nil,
				starterOutfit = typeof(summary) == "table" and summary.StarterOutfit or nil,
				appearanceRevision =
					(typeof(summary) == "table" and summary.AppearanceRevision)
					or slot.AppearanceRevision,
			})
		end
	end
	return models
end


-- SLOT PORTRAITS -----------------------------------------------------------
-- Reconstructs the saved character inside each slot card. This deliberately
-- uses the slot's saved Summary.Appearance / Summary.StarterOutfit rather than
-- the player's Roblox account avatar thumbnail.
local slotPortraitGeneration = 0
local slotPortraitQueue: {any} = {}
local slotPortraitWorkers = 0
local SLOT_PORTRAIT_MAX_WORKERS = 2

local function findCatalogEntryById(raw: any, id: any): any?
	if typeof(id) ~= "string" or id == "" or typeof(raw) ~= "table" then
		return nil
	end
	for _, entry in ipairs(raw) do
		if typeof(entry) == "table" and tostring(entry.Id or "") == id then
			return entry
		end
	end
	return nil
end

local function catalogEntry(catalog: any, methodName: string, listName: string, id: any): any?
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	local method = catalog and catalog[methodName]
	if typeof(method) == "function" then
		local ok, result = pcall(method, id)
		if ok and typeof(result) == "table" then
			return result
		end
	end
	return findCatalogEntryById(catalog and catalog[listName] or nil, id)
end

local function cleanHairIds(raw: any): {number}
	local result = {}
	if typeof(raw) ~= "table" then
		return result
	end
	for _, rawId in ipairs(raw) do
		local id = math.floor(tonumber(rawId) or 0)
		if id > 0 then
			table.insert(result, id)
		end
	end
	return result
end

local function portraitStatus(viewport: ViewportFrame, textValue: string, isError: boolean?)
	local parent = viewport.Parent
	if not parent then
		return
	end
	local label = parent:FindFirstChild("PortraitLoading")
	if label and label:IsA("TextLabel") then
		label.Text = textValue
		label.TextColor3 = isError and Color3.fromRGB(133, 59, 52) or Color3.fromRGB(116, 107, 92)
		label.Visible = textValue ~= ""
	end
end

local function clearViewport(viewport: ViewportFrame)
	viewport.CurrentCamera = nil
	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end
end

local function buildSlotPortrait(viewport: ViewportFrame, slotView: any, generation: number)
	if not viewport.Parent or generation ~= slotPortraitGeneration then
		return
	end

	portraitStatus(viewport, "Loading...", false)
	clearViewport(viewport)

	local appearance = slotView and slotView.appearance
	local starterOutfit = slotView and slotView.starterOutfit
	if typeof(appearance) ~= "table" then
		portraitStatus(viewport, "No appearance", true)
		return
	end

	local catalog, catalogReason = getAppearanceCatalog()
	if not catalog then
		portraitStatus(viewport, catalogReason or "Catalog unavailable", true)
		return
	end

	local skin = catalogEntry(catalog, "GetSkinTone", "SkinTones", appearance.SkinToneId)
	local mouth = catalogEntry(catalog, "GetMouthStyle", "MouthStyles", appearance.MouthStyleId)
	local brow = catalogEntry(catalog, "GetBrowStyle", "BrowStyles", appearance.BrowStyleId)
	local nose = catalogEntry(catalog, "GetNoseStyle", "NoseStyles", appearance.NoseStyleId)
	local eye = catalogEntry(catalog, "GetEyeStyle", "EyeStyles", appearance.EyeStyleId)
	local shoes = catalogEntry(catalog, "GetShoesStyle", "ShoesStyles", appearance.ShoesStyleId)
		or findCatalogEntryById(catalog.ShoesStyles, appearance.ShoesStyleId)
	local gloves = catalogEntry(catalog, "GetGlovesStyle", "GlovesStyles", appearance.GlovesStyleId)
		or findCatalogEntryById(catalog.GlovesStyles, appearance.GlovesStyleId)

	local top = nil
	local bottom = nil
	if typeof(starterOutfit) == "table" then
		if typeof(starterOutfit.TopId) == "string" and typeof(catalog.GetStarterTop) == "function" then
			local ok, result = pcall(catalog.GetStarterTop, starterOutfit.TopId)
			if ok and typeof(result) == "table" then top = result end
		end
		if typeof(starterOutfit.BottomId) == "string" and typeof(catalog.GetStarterBottom) == "function" then
			local ok, result = pcall(catalog.GetStarterBottom, starterOutfit.BottomId)
			if ok and typeof(result) == "table" then bottom = result end
		end
	end

	local description = Instance.new("HumanoidDescription")
	if typeof(skin) == "table" and typeof(skin.Color) == "Color3" then
		description.HeadColor = skin.Color
		description.LeftArmColor = skin.Color
		description.RightArmColor = skin.Color
		description.LeftLegColor = skin.Color
		description.RightLegColor = skin.Color
		description.TorsoColor = skin.Color
	end

	local hairIds = cleanHairIds(appearance.HairAssetIds)
	if #hairIds > 0 then
		local asStrings = {}
		for _, id in ipairs(hairIds) do
			table.insert(asStrings, tostring(id))
		end
		description.HairAccessory = table.concat(asStrings, ",")
	end

	local okModel, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			description,
			Enum.HumanoidRigType.R6
		)
	end)
	description:Destroy()

	if generation ~= slotPortraitGeneration or not viewport.Parent then
		if okModel and typeof(result) == "Instance" then
			result:Destroy()
		end
		return
	end

	if not okModel or typeof(result) ~= "Instance" or not result:IsA("Model") then
		portraitStatus(viewport, "Preview unavailable", true)
		warn("[FrontendController] SLOT PORTRAIT CREATE FAILED", slotView and slotView.slotId, result)
		return
	end

	local model = result :: Model
	model.Name = "SlotPortrait_" .. tostring(slotView.slotId)
	setModelPreviewPhysics(model)
	applyPreviewClassicClothing(model, top, bottom)
	if shoes or gloves then
		applyPreviewWearables(model, shoes, gloves)
	end
	applyFaceLayers(model, mouth, brow, nose, eye)

	-- Keep the portrait's world isolated from Workspace.
	local world = Instance.new("WorldModel")
	world.Name = "PortraitWorld"
	world.Parent = viewport
	model.Parent = world

	model:PivotTo(CFrame.new(0, 0, 0))

	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("Torso")
	if not head or not head:IsA("BasePart") or not torso or not torso:IsA("BasePart") then
		model:Destroy()
		world:Destroy()
		portraitStatus(viewport, "Preview unavailable", true)
		return
	end

	local camera = Instance.new("Camera")
	camera.Name = "PortraitCamera"
	camera.FieldOfView = 28
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- R6 Front faces -Z. Camera therefore sits on -Z and looks toward the model.
	local target = Vector3.new(
		head.Position.X,
		(head.Position.Y * 0.72) + (torso.Position.Y * 0.28) + 0.08,
		head.Position.Z
	)

	local cameraDistance = 6.15
	camera.CFrame = CFrame.lookAt(
		target + Vector3.new(0, 0.05, -cameraDistance),
		target
	)

	viewport.Ambient = Color3.fromRGB(185, 178, 166)
	viewport.LightColor = Color3.fromRGB(255, 245, 226)
	viewport.LightDirection = Vector3.new(-1, -0.7, -1)

	portraitStatus(viewport, "", false)
	print(
		"[FrontendController] SLOT PORTRAIT READY",
		tostring(slotView.slotId),
		"Hair=" .. tostring(#hairIds),
		"Top=" .. tostring(starterOutfit and starterOutfit.TopId or "nil"),
		"Bottom=" .. tostring(starterOutfit and starterOutfit.BottomId or "nil")
	)
end

local function pumpSlotPortraitQueue()
	while slotPortraitWorkers < SLOT_PORTRAIT_MAX_WORKERS and #slotPortraitQueue > 0 do
		local job = table.remove(slotPortraitQueue, 1)
		slotPortraitWorkers += 1
		task.spawn(function()
			local ok, err = pcall(buildSlotPortrait, job.viewport, job.slotView, job.generation)
			if not ok then
				warn("[FrontendController] SLOT PORTRAIT ERROR", job.slotView and job.slotView.slotId, err)
				portraitStatus(job.viewport, "Preview unavailable", true)
			end
			slotPortraitWorkers -= 1
			pumpSlotPortraitQueue()
		end)
	end
end

local function queueSlotPortrait(viewport: ViewportFrame, slotView: any)
	table.insert(slotPortraitQueue, {
		viewport = viewport,
		slotView = slotView,
		generation = slotPortraitGeneration,
	})
	pumpSlotPortraitQueue()
end

local function getDeleteCharacterRemote(): RemoteFunction?
	local candidate = remotes and remotes:FindFirstChild("DeleteCharacterRequest")
	if candidate and candidate:IsA("RemoteFunction") then
		return candidate
	end
	return nil
end

local function deleteSlotThroughBackend(slotView: any): (boolean, string?)
	if typeof(slotView) ~= "table" or slotView.slotId == nil then
		return false, "Invalid slot."
	end

	local remote = getDeleteCharacterRemote()
	if not remote then
		warn("[FrontendController] DeleteCharacterRequest missing")
		return false, "Delete service is unavailable."
	end

	local slotId = tostring(slotView.slotId)
	local ok, result = pcall(function()
		return remote:InvokeServer({
			SlotId = slotId,
			Confirmation = "DELETE",
		})
	end)

	if not ok then
		warn("[FrontendController] DELETE REQUEST FAILED", slotId, result)
		return false, "Delete request failed."
	end

	if typeof(result) ~= "table" then
		return false, "Invalid delete response."
	end

	if result.Ok ~= true then
		local reason = tostring(result.Reason or "DeleteFailed")
		warn("[FrontendController] DELETE REJECTED", slotId, reason)
		return false, reason
	end

	currentState = result
	selectedSlotId = slotId

	renderSlots()
	refreshMainMenuAvailability()
	status.Text = "Character sent to Afterlife. Select the slot to continue there."

	print("[FrontendController] SLOT SENT TO AFTERLIFE", slotId)
	return true, nil
end

if ServerSelectorHUD then
	frontendHUDs.Servers = ServerSelectorHUD.Create(gui, gui, {
		onBack = function()
			renderSlots()
			showPage("Slots")
		end,
		onQuickplay = function()
			if not selectedSlotId then
				return
			end

			if frontendHUDs.Servers then
				frontendHUDs.Servers.SetJoinPending("__quickplay__")
				frontendHUDs.Servers.ShowStatus("Finding the best available server…", 6)
			end

			local listResult = invoke("GetServers")
			local candidate = nil
			if listResult and typeof(listResult.Servers) == "table" then
				frontendHUDs.ServerFlow.renderServers(listResult.Servers)
				candidate = frontendHUDs.ServerFlow.chooseQuickplayCandidate(listResult.Servers)
			end

			if frontendHUDs.Servers then
				frontendHUDs.Servers.SetJoinPending("__quickplay__")
			end

			local result = playSlotRequest(
				selectedSlotId,
				candidate and tostring(candidate.jobId or candidate.serverId or "") or nil
			)

			if not result or result.Ok ~= true then
				if frontendHUDs.Servers then
					frontendHUDs.Servers.ResetJoinPending()
					frontendHUDs.Servers.ShowStatus("Couldn’t join that server. Try again.", 4)
				end
			elseif candidate == nil and frontendHUDs.Servers then
				frontendHUDs.Servers.ShowStatus("Using Roblox matchmaking for the best connection…", 4)
			end
		end,
		onRefresh = function()
			frontendHUDs.ServerFlow.requestServers(true)
		end,
		onJoin = function(serverView: any)
			if not selectedSlotId or typeof(serverView) ~= "table" then
				if frontendHUDs.Servers then
					frontendHUDs.Servers.ResetJoinPending()
				end
				return
			end

			local result = playSlotRequest(
				selectedSlotId,
				tostring(serverView.jobId or serverView.serverId or "")
			)

			if not result or result.Ok ~= true then
				if frontendHUDs.Servers then
					frontendHUDs.Servers.ResetJoinPending()
					local reason = result and tostring(result.Reason or "Server unavailable") or "Server unavailable"
					frontendHUDs.Servers.ShowStatus(reason .. ". Refreshing…", 4)
				end
				frontendHUDs.ServerFlow.requestServers(true)
			end
		end,
	})
end

if SlotSelectorHUD and slotsPage then
	slotsTitle.Visible = false
	currencyLabel.Visible = false
	slotsBack.Visible = false
	slotsScroll.Visible = false

	frontendHUDs.Slots = SlotSelectorHUD.Create(gui, {
		onBack = function()
			showPage("Main")
		end,
		onBuySlot = function()
			if BUY_CHARACTER_SLOT_PRODUCT_ID <= 0 then
				status.Text = "Character slot product is not configured yet."
				warn("[FrontendController] BuyCharacterSlotProductId is 0; create the Developer Product, then update FrontendCommerceConfig")
				return
			end

			status.Text = "Opening Roblox purchase prompt..."
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(
					player,
					BUY_CHARACTER_SLOT_PRODUCT_ID
				)
			end)
			if not ok then
				status.Text = "Could not open the purchase prompt."
				warn("[FrontendController] PromptProductPurchase failed", err)
			end
		end,
		onPrimaryAction = function(slotView: any)
			selectedSlotId = tostring(slotView.slotId)
			if slotView.state == "alive" then
				frontendHUDs.ServerFlow.openServers(selectedSlotId)
			elseif slotView.state == "afterlife" then
				invoke("ReturnAfterlife", {
					SlotId = selectedSlotId,
				})
			else
				openCreation(selectedSlotId)
			end
		end,
		onDeleteConfirmed = function(slotView: any)
			return deleteSlotThroughBackend(slotView)
		end,
		onRenderPortrait = function(viewportFrame: ViewportFrame, slotView: any)
			queueSlotPortrait(viewportFrame, slotView)
		end,
	})
	frontendHUDs.Slots.SetVisible(false)
end

local legacyRenderSlots = renderSlots
renderSlots = function()
	if not frontendHUDs.Slots then
		legacyRenderSlots()
		return
	end
	slotPortraitGeneration += 1
	table.clear(slotPortraitQueue)
	local models = buildSlotSelectorModels()
	frontendHUDs.Slots.SetSlots(models)
	frontendHUDs.Slots.SetSelectedSlot(selectedSlotId)
end

-- Prompt completion is not a grant. It is only UX feedback while the server
-- waits for MarketplaceService.ProcessReceipt to authoritatively award the slot.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, wasPurchased: boolean)
	if userId ~= player.UserId or productId ~= BUY_CHARACTER_SLOT_PRODUCT_ID then
		return
	end

	if wasPurchased then
		status.Text = "Purchase submitted. Waiting for Roblox confirmation..."
	else
		status.Text = "Purchase cancelled."
	end
end)

-- Receipt grants happen on the server. This event only refreshes the already
-- authoritative frontend snapshot after ProcessReceipt has granted the slot.
task.spawn(function()
	local commerceEvent = remotes and remotes:WaitForChild("FrontendCommerceUpdated", 30)
	if not commerceEvent or not commerceEvent:IsA("RemoteEvent") then
		warn("[FrontendController] FrontendCommerceUpdated RemoteEvent missing")
		return
	end

	commerceEvent.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or payload.Kind ~= "CharacterSlotPurchased" then
			return
		end

		task.spawn(function()
			for _ = 1, 20 do
				local result = invoke("GetState")
				if result and result.Ready == true then
					currentState = result
					selectedSlotId = payload.SlotId and tostring(payload.SlotId) or selectedSlotId
					renderSlots()
					refreshMainMenuAvailability()
					status.Text = "Character slot purchased."
					print("[FrontendController] PURCHASED SLOT REFRESHED", tostring(payload.SlotId))
					return
				end
				task.wait(0.25)
			end
			warn("[FrontendController] Purchased slot granted but frontend refresh timed out")
		end)
	end)
end)

mainMenuUI.playButton.MouseButton1Click:Connect(function()
	if not currentState or currentState.Ready ~= true then
		return
	end

	renderSlots()
	showPage("Slots")
end)

mainMenuUI.quickplayButton.MouseButton1Click:Connect(function()
	local slotId = resolveQuickPlaySlot()
	if not slotId then
		-- No living character yet: send the player to the already-integrated
		-- slot screen rather than silently failing.
		renderSlots()
		showPage("Slots")
		return
	end

	selectedSlotId = slotId
	playSlotRequest(slotId, nil)
end)

mainMenuUI.settingsButton.MouseButton1Click:Connect(function()
	mainMenuUI.ShowPlaceholder(
		"Settings",
		"Settings is connected. The actual options panel will be added in the next integration pass."
	)
end)

mainMenuUI.creditsButton.MouseButton1Click:Connect(function()
	mainMenuUI.ShowPlaceholder(
		"Credits",
		"Credits is connected and reserved for the final credits panel."
	)
end)

slotsBack.MouseButton1Click:Connect(function()
	refreshMainMenuAvailability()
	showPage("Main")
end)

creationUI.villageValueButton.MouseButton1Click:Connect(function()
	selectedVillageIndex =
		cycleIndex(
			selectedVillageIndex,
			#creationVillages
		)

	refreshCreationButtons()
end)

creationUI.natureValueButton.MouseButton1Click:Connect(function()
	selectedNatureIndex =
		cycleIndex(
			selectedNatureIndex,
			#creationNatures
		)

	refreshCreationButtons()
end)

creationUI.villageLeftButton.MouseButton1Click:Connect(function()
	selectedVillageIndex = cycleIndexBy(selectedVillageIndex, #creationVillages, -1)
	refreshCreationButtons()
end)

creationUI.villageRightButton.MouseButton1Click:Connect(function()
	selectedVillageIndex = cycleIndexBy(selectedVillageIndex, #creationVillages, 1)
	refreshCreationButtons()
end)

creationUI.natureLeftButton.MouseButton1Click:Connect(function()
	selectedNatureIndex = cycleIndexBy(selectedNatureIndex, #creationNatures, -1)
	refreshCreationButtons()
end)

creationUI.natureRightButton.MouseButton1Click:Connect(function()
	selectedNatureIndex = cycleIndexBy(selectedNatureIndex, #creationNatures, 1)
	refreshCreationButtons()
end)

local hairAssetValidationCache: {[number]: boolean} = {}

local function isValidHairAsset(assetId: number): boolean
	local cached = hairAssetValidationCache[assetId]
	if cached ~= nil then
		return cached
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(
			assetId,
			Enum.InfoType.Asset
		)
	end)

	local valid =
		ok
		and typeof(info) == "table"
		and tonumber(info.AssetTypeId)
		== Enum.AvatarAssetType.HairAccessory.Value

	hairAssetValidationCache[assetId] = valid
	return valid
end

local function applyHairInputsNow()
	local newIds: {number} = {}
	local seen: {[number]: boolean} = {}
	local removedInvalid = false

	for _, box in ipairs(creationUI.hairIdBoxes) do
		local raw = string.gsub(box.Text, "%s+", "")

		if raw ~= "" then
			local assetId = parseHairInput(raw)

			if assetId
				and isValidHairAsset(assetId) then

				if not seen[assetId] then
					seen[assetId] = true
					table.insert(newIds, assetId)
				end

				box.Text = tostring(assetId)
			else
				box.Text = ""
				removedInvalid = true
			end
		end
	end

	selectedHairAssetIds = newIds

	if removedInvalid then
		status.Text = "Invalid hair ID removed."
	elseif #selectedHairAssetIds > 0 then
		status.Text = "Hair preview updated."
	else
		status.Text = "Hair cleared."
	end

	requestPreviewRefresh()
end

for _, box in ipairs(creationUI.hairIdBoxes) do
	box.FocusLost:Connect(function()
		applyHairInputsNow()
	end)
end

local function isHoldInput(
	input: InputObject
): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function bindHoldButton(
	buttonObject: GuiButton,
	onChanged: (boolean) -> ()
)
	buttonObject.InputBegan:Connect(function(input)
		if isHoldInput(input) then
			onChanged(true)
		end
	end)

	buttonObject.InputEnded:Connect(function(input)
		if isHoldInput(input) then
			onChanged(false)
		end
	end)

	buttonObject.MouseLeave:Connect(function()
		onChanged(false)
	end)
end

bindHoldButton(
	creationUI.rotateLeftButton,
	function(isHeld)
		rotateLeftHeld = isHeld
	end
)

bindHoldButton(
	creationUI.rotateRightButton,
	function(isHeld)
		rotateRightHeld = isHeld
	end
)

bindHoldButton(
	creationUI.zoomInButton,
	function(isHeld)
		zoomInHeld = isHeld
	end
)

bindHoldButton(
	creationUI.zoomOutButton,
	function(isHeld)
		zoomOutHeld = isHeld
	end
)

creationUI.resetViewButton.MouseButton1Click:Connect(function()
	resetCreationView()
end)

UserInputService.InputBegan:Connect(function(
	input: InputObject,
	gameProcessedEvent: boolean
)
	if gameProcessedEvent
		or not creationPage.Visible then

		return
	end

	if input.UserInputType
		== Enum.UserInputType.MouseButton1 then

		local position =
			Vector2.new(
				input.Position.X,
				input.Position.Y
			)

		if canBeginSceneDrag(position) then
			dragRotateActive = true
			dragLastX = input.Position.X
		end

	elseif input.UserInputType
		== Enum.UserInputType.Touch then

		local position =
			Vector2.new(
				input.Position.X,
				input.Position.Y
			)

		if canBeginSceneDrag(position) then
			dragRotateActive = true
			dragLastX = input.Position.X
		end
	end
end)

UserInputService.InputEnded:Connect(function(
	input: InputObject
)
	if input.UserInputType
		== Enum.UserInputType.MouseButton1
		or input.UserInputType
		== Enum.UserInputType.Touch then

		dragRotateActive = false
	end
end)

UserInputService.InputChanged:Connect(function(
	input: InputObject
)
	if not creationPage.Visible then
		return
	end

	if dragRotateActive
		and (
			input.UserInputType
				== Enum.UserInputType.MouseMovement
				or input.UserInputType
				== Enum.UserInputType.Touch
		) then

		local currentX =
			input.Position.X

		local deltaX =
			currentX - dragLastX

		dragLastX =
			currentX

		if math.abs(deltaX) > 0 then
			rotatePreview(
				deltaX
					* CREATION_DRAG_SENSITIVITY
			)
		end

	elseif input.UserInputType
		== Enum.UserInputType.MouseWheel then

		zoomCreation(
			-input.Position.Z
				* CREATION_MOUSE_WHEEL_STEP
		)
	end
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	if not creationPage.Visible then
		rotateLeftHeld = false
		rotateRightHeld = false
		zoomInHeld = false
		zoomOutHeld = false
		dragRotateActive = false
		return
	end

	local viewChanged = false

	local rotationDirection =
		(rotateRightHeld and 1 or 0)
	- (rotateLeftHeld and 1 or 0)

	if rotationDirection ~= 0 then
		previewYawDegrees =
			(
				previewYawDegrees
				+ (
					rotationDirection
					* CREATION_ROTATE_SPEED
					* deltaTime
				)
			)
			% 360

		viewChanged = true
	end

	local zoomDirection =
		(zoomOutHeld and 1 or 0)
	- (zoomInHeld and 1 or 0)

	if zoomDirection ~= 0 then
		setCreationZoomTarget(
			creationCameraTargetFieldOfView
				+ (
					zoomDirection
					* CREATION_ZOOM_SPEED
					* deltaTime
				)
		)
	end

	local zoomAlpha =
		1
	- math.exp(
		-CREATION_ZOOM_SMOOTHNESS
			* deltaTime
	)

	local previousFov =
		creationCameraFieldOfView

	creationCameraFieldOfView =
		creationCameraFieldOfView
		+ (
			creationCameraTargetFieldOfView
			- creationCameraFieldOfView
		)
		* zoomAlpha

	if math.abs(
		creationCameraFieldOfView
		- previousFov
		) > 0.001 then

		viewChanged = true
	end

	if viewChanged then
		refreshCreationView()
	end
end)

local function shiftFaceSelection(
	kind: string,
	delta: number
)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	if kind == "Eyes" then
		local list = getEnabledOptions(catalog.EyeStyles)
		selectedEyeIndex = cycleIndexBy(selectedEyeIndex, #list, delta)

	elseif kind == "Brows" then
		local list = getEnabledOptions(catalog.BrowStyles)
		selectedBrowIndex = cycleIndexBy(selectedBrowIndex, #list, delta)

	elseif kind == "Nose" then
		local list = getEnabledOptions(catalog.NoseStyles)
		selectedNoseIndex = cycleIndexBy(selectedNoseIndex, #list, delta)

	elseif kind == "Mouth" then
		local list = getEnabledOptions(catalog.MouthStyles)
		selectedMouthIndex = cycleIndexBy(selectedMouthIndex, #list, delta)
	end

	refreshCreationButtons()
	requestPreviewRefresh()
end

creationUI.eyeLeftButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Eyes", -1)
	end)

creationUI.eyeRightButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Eyes", 1)
	end)

creationUI.browLeftButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Brows", -1)
	end)

creationUI.browRightButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Brows", 1)
	end)

creationUI.noseLeftButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Nose", -1)
	end)

creationUI.noseRightButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Nose", 1)
	end)

creationUI.mouthLeftButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Mouth", -1)
	end)

creationUI.mouthRightButton.MouseButton1Click:
	Connect(function()
		shiftFaceSelection("Mouth", 1)
	end)

local function shiftShoes(delta: number)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	local list =
		getEnabledShoes(
			catalog
		)

	selectedShoesIndex =
		cycleIndexBy(
			selectedShoesIndex,
			#list,
			delta
		)

	refreshCreationButtons()
	refreshPreviewWearablesInPlace()
end

creationUI.shoesLeftButton.MouseButton1Click:
	Connect(function()
		shiftShoes(-1)
	end)

creationUI.shoesRightButton.MouseButton1Click:
	Connect(function()
		shiftShoes(1)
	end)

local function shiftGloves(delta: number)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	local list =
		getEnabledGloves(
			catalog
		)

	selectedGlovesIndex =
		cycleIndexBy(
			selectedGlovesIndex,
			#list,
			delta
		)

	refreshCreationButtons()
	refreshPreviewWearablesInPlace()
end

creationUI.glovesLeftButton.MouseButton1Click:
	Connect(function()
		shiftGloves(-1)
	end)

creationUI.glovesRightButton.MouseButton1Click:
	Connect(function()
		shiftGloves(1)
	end)

local function shiftClothingColor(delta: number)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	local colors = getEnabledClothingColors(catalog)
	selectedTopColorIndex = cycleIndexBy(selectedTopColorIndex, #colors, delta)
	selectedBottomColorIndex = selectedTopColorIndex

	-- Preserve the independent Top/Bottom design numbers while sharing one color.
	refreshCreationButtons()
	refreshPreviewClothingInPlace()
end

creationUI.colorLeftButton.MouseButton1Click:Connect(function()
	shiftClothingColor(-1)
end)

creationUI.colorRightButton.MouseButton1Click:Connect(function()
	shiftClothingColor(1)
end)

local function shiftTop(delta: number)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	local colors = getEnabledClothingColors(catalog)
	local color = colors[selectedTopColorIndex]
	local count =
		color
		and typeof(color.TopIds) == "table"
		and #color.TopIds
		or 0

	selectedTopIndex =
		cycleIndexBy(
			selectedTopIndex,
			count,
			delta
		)

	refreshCreationButtons()
	refreshPreviewClothingInPlace()
end

creationUI.topLeftButton.MouseButton1Click:
	Connect(function()
		shiftTop(-1)
	end)

creationUI.topRightButton.MouseButton1Click:
	Connect(function()
		shiftTop(1)
	end)

local function shiftBottom(delta: number)
	local catalog = cachedAppearanceCatalog
	if not catalog then
		return
	end

	local colors = getEnabledClothingColors(catalog)
	local color = colors[selectedBottomColorIndex]
	local count =
		color
		and typeof(color.BottomIds) == "table"
		and #color.BottomIds
		or 0

	selectedBottomIndex =
		cycleIndexBy(
			selectedBottomIndex,
			count,
			delta
		)

	refreshCreationButtons()
	refreshPreviewClothingInPlace()
end

creationUI.bottomLeftButton.MouseButton1Click:
	Connect(function()
		shiftBottom(-1)
	end)

creationUI.bottomRightButton.MouseButton1Click:
	Connect(function()
		shiftBottom(1)
	end)

creationUI.createButton.MouseButton1Click:Connect(function()
	if not selectedSlotId then
		return
	end

	applyHairInputsNow()

	local village =
		creationVillages[
	selectedVillageIndex
	]

	local nature =
		creationNatures[
	selectedNatureIndex
	]

	local skin, mouth, brow, nose, eye, top, bottom, shoes, gloves =
		selectedAppearanceEntries()

	if not village
		or not nature
		or not skin
		or not mouth
		or not brow
		or not nose
		or not eye
		or not top
		or not bottom
		or not shoes
		or not gloves then

		status.Text =
			"Creation options are incomplete."
		return
	end

	local result = invoke("CommitCreation", {
		SlotId = selectedSlotId,
		GivenName = creationUI.nameBox.Text,
		VillageId = village.Id,
		PrimaryNatureId = nature.Id,
		Appearance = {
			RigType = "R6",
			SkinToneId = skin.Id,
			HairAssetIds = selectedHairAssetIds,
			MouthStyleId = mouth.Id,
			BrowStyleId = brow.Id,
			NoseStyleId = nose.Id,
			EyeStyleId = eye.Id,
			ShoesStyleId = shoes.Id,
			GlovesStyleId = gloves.Id,
		},
		StarterOutfit = {
			TopId = top.Id,
			BottomId = bottom.Id,
		},
	})

	if result and result.Ok == true then
		currentState = result
		renderSlots()
		showPage("Slots", {
			BeforeSwap = exitCreationPresentation,
		})
	end
end)

creationUI.backButton.MouseButton1Click:Connect(function()
	status.Text = "Ready"
	renderSlots()
	showPage("Slots", {
		BeforeSwap = exitCreationPresentation,
	})
end)

creationUI.cancelButton.MouseButton1Click:Connect(function()
	if not selectedSlotId then
		showPage("Slots", {
			BeforeSwap = exitCreationPresentation,
		})
		return
	end

	local snapshot =
		currentState
		and currentState.Snapshot

	local slot =
		snapshot
		and snapshot.Slots
		and snapshot.Slots[selectedSlotId]

	if slot and slot.State == "Creating" then
		local result = invoke("CancelCreation", {
			SlotId = selectedSlotId,
		})

		if result and result.Ok == true then
			currentState = result
			renderSlots()
			showPage("Slots", {
				BeforeSwap = exitCreationPresentation,
			})
		end
	else
		status.Text = "Ready"
		renderSlots()
		showPage("Slots", {
			BeforeSwap = exitCreationPresentation,
		})
	end
end)

showPage("Main", {Instant = true})

-- Load the persistent Quickplay preference independently. This never blocks the
-- account/slot UI; the button becomes active as soon as both pieces are ready.
task.spawn(function()
	for _ = 1, 40 do
		local result = menuPreferencesInvoke("GetLastSlot", nil)
		if typeof(result) == "table" and result.Ready == true then
			if result.LastSlotId ~= nil then
				lastUsedSlotId = tostring(result.LastSlotId)
			end
			refreshMainMenuAvailability()
			return
		end
		task.wait(0.25)
	end
end)

task.spawn(function()
	for _ = 1, 60 do
		local result = invoke("GetState")

		if result and result.Ready == true then
			currentState = result
			status.Text = "Ready"

			-- Returning from World/Afterlife can provide the previously active slot.
			-- Keep it as a Quickplay fallback, but always stay on the new main menu.
			if result.FocusSlotId then
				selectedSlotId = tostring(result.FocusSlotId)
				if not lastUsedSlotId then
					lastUsedSlotId = selectedSlotId
				end
			end

			refreshMainMenuAvailability()
			showPage("Main", {Instant = true})
			return
		end

		task.wait(0.5)
	end

	status.Text = "Frontend account load timed out."
	mainMenuUI.setPlayEnabled(false)
	mainMenuUI.setQuickplayEnabled(false)
end)

print(
	"[FrontendController] READY v5.9 ServerMetadata+ServerSelectorHUD+FrontendTransitions+SlotPortraits+DeleteToAfterlife+BuySlotReady"
		.. " | MainMenu=ASSET_DRIVEN"
		.. " | QuickplayLastSlot=ON"
		.. " | Slots=ON"
		.. " | CharacterCreation=STABLE_V1"
		.. " | AppearancePreview=WORKSPACE_3D | SlotPortraits=VIEWPORT_R6"
		.. " | ServerBrowser=ON"
)
