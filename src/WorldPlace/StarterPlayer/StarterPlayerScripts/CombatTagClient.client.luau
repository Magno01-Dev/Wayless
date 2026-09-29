--!strict
-- CombatTagClient v4 - Astra CombatTagHUD package integration
-- PLACE AS LocalScript:
-- StarterPlayer > StarterPlayerScripts > CombatTagClient
--
-- Presentation follows CombatTagHUD/Layout.json exactly where Roblox has parity.
-- Backend remains server-authoritative through CombatTagService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("CombatTagRemotes")
local updateRemote = remotes:WaitForChild("CombatTagUpdate") :: RemoteEvent
local requestSnapshotRemote = remotes:WaitForChild("CombatTagRequestSnapshot") :: RemoteEvent
local resetAttemptRemote = remotes:WaitForChild("CombatTagResetAttempt") :: RemoteEvent
local outgoingUpdateRemote = remotes:WaitForChild("CombatTagOutgoingUpdate") :: RemoteEvent
local clearOutgoingRequestRemote = remotes:WaitForChild("CombatTagClearOutgoingRequest") :: RemoteEvent


-- ============================================================
-- ASTRA PACKAGE CONSTANTS
-- ============================================================

local REFERENCE_VIEWPORT = Vector2.new(1920, 1080)
local TOP_OFFSET = 32
local MARK_SIZE = 78
local SEAL_SIZE = 110
local SEAL_OFFSET = Vector2.new(-16, -16)
local HOVER_TIMER_X = 7
local HOVER_TIMER_Y = 92
local HOVER_TIMER_WIDTH = 64
local HOVER_TIMER_HEIGHT = 24
local INCOMING_MENU_OFFSET_Y = 120
local INCOMING_MENU_WIDTH = 285
local CONTEXT_MENU_WIDTH = 142
local TAG_DURATION = 90

local ENTRY_MARK_SECONDS = 0.38
local ENTRY_SEAL_DELAY = 0.10
local ENTRY_SEAL_SECONDS = 0.45
local HIT_SECONDS = 0.36
local EXIT_SECONDS = 0.48
local SEAL_ROTATION_SECONDS = 32

local TITLE_FONT = Font.new("rbxasset://fonts/families/Fondamento.json")
local NUMBERS_FONT = Font.new("rbxasset://fonts/families/Merriweather.json")

local CHAKRA_CUT_IMAGE = "rbxassetid://109021347520830"
local CHAKRA_CUT_SPENT_IMAGE = "rbxassetid://140044824949263"
local CHAKRA_CUT_HIT_IMAGE = "rbxassetid://116009433181725"
local WASHI_IMAGE = "rbxassetid://111589873404506"
local INK_SEAL_IMAGE = "rbxassetid://105488786932080"
local CORNER_TL_IMAGE = "rbxassetid://102806658118949"
local CORNER_BR_IMAGE = "rbxassetid://103491173944662"

local TEXT_COLOR = Color3.fromRGB(41, 39, 31)
local TIMER_TEXT_COLOR = Color3.fromRGB(231, 223, 205)
local TIMER_BACKGROUND = Color3.fromRGB(23, 23, 23)
local BORDER_COLOR = Color3.fromRGB(139, 121, 90)
local SEPARATOR_COLOR = Color3.fromRGB(130, 113, 85)
local CLEAR_COLOR = Color3.fromRGB(114, 60, 52)

local WASHI_RECT_OFFSET = Vector2.new(129, 162)
local WASHI_RECT_SIZE = Vector2.new(863, 1078)

local REDUCED_MOTION_FADE = 0.12
local TOUCH_LONG_PRESS_SECONDS = 0.55


type ClientTag = {
	sourceId: string?,
	sourceType: string?,
	sourceUserId: number?,
	sourceName: string,
	sourceDisplayName: string,
	expiresAt: number,
}

local incomingTags: {ClientTag} = {}
local incomingById: {[string]: ClientTag} = {}
local rowTimeLabels: {[string]: TextLabel} = {}
local outgoingCount = 0
local combatActive = false
local incomingMenuOpen = false
local contextMenuOpen = false
local markHovered = false
local markSelected = false
local baseScale = 1
local sealOrbitStart = 0
local exitingGeneration = 0
local touchGeneration = 0
local longPressTriggered = false

local reducedMotion = false
pcall(function()
	reducedMotion = GuiService.ReducedMotionEnabled
end)

local connections: {RBXScriptConnection} = {}
local activeTweens: {Tween} = {}

local function rememberConnection(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, connection)
	return connection
end

local function playTween(instance: Instance, tweenInfo: TweenInfo, properties: {[string]: any}): Tween
	local tween = TweenService:Create(instance, tweenInfo, properties)
	table.insert(activeTweens, tween)
	tween:Play()
	return tween
end

local function sourceKey(tag: ClientTag): string
	if typeof(tag.sourceId) == "string" and tag.sourceId ~= "" then
		return tag.sourceId
	end
	if typeof(tag.sourceUserId) == "number" then
		return "P:" .. tostring(tag.sourceUserId)
	end
	return "LEGACY:" .. tostring(tag.sourceName)
end

local function formatRemaining(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	local minutes = math.floor(whole / 60)
	local remainder = whole % 60
	return string.format("%d:%02d", minutes, remainder)
end

local function maxIncomingExpiresAt(): number
	local result = 0
	for _, tag in ipairs(incomingTags) do
		result = math.max(result, tag.expiresAt)
	end
	return result
end

for _, oldName in ipairs({"CombatTagHUD", "CombatTagGui"}) do
	local oldGui = playerGui:FindFirstChild(oldName)
	if oldGui then
		oldGui:Destroy()
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "CombatTagHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 95
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET)
root.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
root.BackgroundTransparency = 1
root.ClipsDescendants = false
root.Visible = false
root.ZIndex = 1
root.Parent = gui

local rootScale = Instance.new("UIScale")
rootScale.Name = "ReferenceScale"
rootScale.Scale = 1
rootScale.Parent = root

local sealEntrance = Instance.new("Frame")
sealEntrance.Name = "SealEntrance"
sealEntrance.AnchorPoint = Vector2.new(0.5, 0.5)
sealEntrance.Position = UDim2.fromOffset(SEAL_OFFSET.X + SEAL_SIZE / 2, SEAL_OFFSET.Y + SEAL_SIZE / 2)
sealEntrance.Size = UDim2.fromOffset(SEAL_SIZE, SEAL_SIZE)
sealEntrance.BackgroundTransparency = 1
sealEntrance.ClipsDescendants = false
sealEntrance.ZIndex = 1
sealEntrance.Parent = root

local sealEntranceScale = Instance.new("UIScale")
sealEntranceScale.Name = "EntranceScale"
sealEntranceScale.Scale = 1
sealEntranceScale.Parent = sealEntrance

local sealRotation = Instance.new("ImageLabel")
sealRotation.Name = "SealRotation"
sealRotation.Size = UDim2.fromScale(1, 1)
sealRotation.BackgroundTransparency = 1
sealRotation.Image = INK_SEAL_IMAGE
sealRotation.ImageTransparency = 0.28
sealRotation.ScaleType = Enum.ScaleType.Fit
sealRotation.ZIndex = 1
sealRotation.Parent = sealEntrance

local markEntrance = Instance.new("Frame")
markEntrance.Name = "MarkEntrance"
markEntrance.Position = UDim2.fromOffset(0, 0)
markEntrance.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
markEntrance.BackgroundTransparency = 1
markEntrance.ClipsDescendants = false
markEntrance.ZIndex = 2
markEntrance.Parent = root

local markMotion = Instance.new("Frame")
markMotion.Name = "MarkMotion"
markMotion.AnchorPoint = Vector2.new(0.5, 0.5)
markMotion.Position = UDim2.new(0.5, 0, 0.5, 0)
markMotion.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
markMotion.BackgroundTransparency = 1
markMotion.ClipsDescendants = false
markMotion.ZIndex = 2
markMotion.Parent = markEntrance

local markPulseScale = Instance.new("UIScale")
markPulseScale.Name = "HitScale"
markPulseScale.Scale = 1
markPulseScale.Parent = markMotion

local revealClip = Instance.new("Frame")
revealClip.Name = "EntryRevealClip"
revealClip.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
revealClip.BackgroundTransparency = 1
revealClip.ClipsDescendants = true
revealClip.ZIndex = 2
revealClip.Parent = markMotion

local markVisual = Instance.new("Frame")
markVisual.Name = "MarkVisual"
markVisual.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
markVisual.BackgroundTransparency = 1
markVisual.ZIndex = 2
markVisual.Parent = revealClip

local spentMark = Instance.new("ImageLabel")
spentMark.Name = "SpentMark"
spentMark.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
spentMark.BackgroundTransparency = 1
spentMark.Image = CHAKRA_CUT_SPENT_IMAGE
spentMark.ImageTransparency = 0.15
spentMark.ScaleType = Enum.ScaleType.Fit
spentMark.ZIndex = 2
spentMark.Parent = markVisual

local fillClip = Instance.new("Frame")
fillClip.Name = "FillClip"
fillClip.Position = UDim2.fromOffset(0, 0)
fillClip.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
fillClip.BackgroundTransparency = 1
fillClip.ClipsDescendants = true
fillClip.ZIndex = 3
fillClip.Parent = markVisual

local markFill = Instance.new("ImageLabel")
markFill.Name = "MarkFill"
markFill.Position = UDim2.fromOffset(0, 0)
markFill.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
markFill.BackgroundTransparency = 1
markFill.Image = CHAKRA_CUT_IMAGE
markFill.ImageTransparency = 0
markFill.ScaleType = Enum.ScaleType.Fit
markFill.ZIndex = 3
markFill.Parent = fillClip

local hitFlash = Instance.new("ImageLabel")
hitFlash.Name = "HitFlash"
hitFlash.Position = UDim2.fromOffset(0, 0)
hitFlash.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
hitFlash.BackgroundTransparency = 1
hitFlash.Image = CHAKRA_CUT_HIT_IMAGE
hitFlash.ImageTransparency = 1
hitFlash.ScaleType = Enum.ScaleType.Fit
hitFlash.ZIndex = 4
hitFlash.Parent = fillClip

local markButton = Instance.new("TextButton")
markButton.Name = "MarkButton"
markButton.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
markButton.BackgroundTransparency = 1
markButton.Text = ""
markButton.AutoButtonColor = false
markButton.Selectable = true
markButton.ZIndex = 10
markButton.Parent = root

local hoverTimer = Instance.new("TextLabel")
hoverTimer.Name = "HoverTimer"
hoverTimer.Position = UDim2.fromOffset(HOVER_TIMER_X, HOVER_TIMER_Y)
hoverTimer.Size = UDim2.fromOffset(HOVER_TIMER_WIDTH, HOVER_TIMER_HEIGHT)
hoverTimer.BackgroundColor3 = TIMER_BACKGROUND
hoverTimer.BackgroundTransparency = 0.21
hoverTimer.BorderSizePixel = 0
hoverTimer.Text = "0:00"
hoverTimer.TextColor3 = TIMER_TEXT_COLOR
hoverTimer.TextTransparency = 0
hoverTimer.TextSize = 13
hoverTimer.TextScaled = false
hoverTimer.FontFace = NUMBERS_FONT
hoverTimer.TextXAlignment = Enum.TextXAlignment.Center
hoverTimer.TextYAlignment = Enum.TextYAlignment.Center
hoverTimer.Visible = false
hoverTimer.ZIndex = 5
hoverTimer.Parent = root

local function addWashi(parent: GuiObject, zIndex: number)
	local paper = Instance.new("ImageLabel")
	paper.Name = "Paper"
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundTransparency = 1
	paper.Image = WASHI_IMAGE
	paper.ImageTransparency = 0.32
	paper.ImageRectOffset = WASHI_RECT_OFFSET
	paper.ImageRectSize = WASHI_RECT_SIZE
	paper.ScaleType = Enum.ScaleType.Stretch
	paper.ZIndex = zIndex
	paper.Parent = parent
end

local function addBorder(parent: GuiObject, inset: number, zIndex: number)
	local borderFrame = Instance.new("Frame")
	borderFrame.Name = "Border"
	borderFrame.Position = UDim2.fromOffset(inset, inset)
	borderFrame.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	borderFrame.BackgroundTransparency = 1
	borderFrame.ZIndex = zIndex
	borderFrame.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER_COLOR
	stroke.Thickness = 1
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = borderFrame
end

local incomingMenu = Instance.new("Frame")
incomingMenu.Name = "IncomingMenu"
incomingMenu.AnchorPoint = Vector2.new(0.5, 0)
incomingMenu.Position = UDim2.new(0.5, 0, 0, INCOMING_MENU_OFFSET_Y)
incomingMenu.Size = UDim2.fromOffset(INCOMING_MENU_WIDTH, 120)
incomingMenu.BackgroundTransparency = 1
incomingMenu.ClipsDescendants = true
incomingMenu.Visible = false
incomingMenu.ZIndex = 20
incomingMenu.Parent = root

addWashi(incomingMenu, 20)
addBorder(incomingMenu, 3, 21)

local cornerTL = Instance.new("ImageLabel")
cornerTL.Name = "CornerTL"
cornerTL.Position = UDim2.fromOffset(3, 3)
cornerTL.Size = UDim2.fromOffset(36, 30.46)
cornerTL.BackgroundTransparency = 1
cornerTL.Image = CORNER_TL_IMAGE
cornerTL.ScaleType = Enum.ScaleType.Fit
cornerTL.ZIndex = 22
cornerTL.Parent = incomingMenu

local cornerBR = Instance.new("ImageLabel")
cornerBR.Name = "CornerBR"
cornerBR.AnchorPoint = Vector2.new(1, 1)
cornerBR.Position = UDim2.new(1, -3, 1, -3)
cornerBR.Size = UDim2.fromOffset(36, 27.76)
cornerBR.BackgroundTransparency = 1
cornerBR.Image = CORNER_BR_IMAGE
cornerBR.ScaleType = Enum.ScaleType.Fit
cornerBR.ZIndex = 22
cornerBR.Parent = incomingMenu

local incomingTitle = Instance.new("TextLabel")
incomingTitle.Name = "Title"
incomingTitle.Position = UDim2.fromOffset(23, 25)
incomingTitle.Size = UDim2.new(1, -46, 0, 28)
incomingTitle.BackgroundTransparency = 1
incomingTitle.Text = "Tagged by"
incomingTitle.TextColor3 = TEXT_COLOR
incomingTitle.TextTransparency = 0
incomingTitle.TextSize = 22
incomingTitle.TextScaled = false
incomingTitle.FontFace = TITLE_FONT
incomingTitle.TextXAlignment = Enum.TextXAlignment.Left
incomingTitle.TextYAlignment = Enum.TextYAlignment.Center
incomingTitle.ZIndex = 23
incomingTitle.Parent = incomingMenu

local incomingCounter = Instance.new("TextLabel")
incomingCounter.Name = "Counter"
incomingCounter.AnchorPoint = Vector2.new(1, 0)
incomingCounter.Position = UDim2.new(1, -23, 0, 31)
incomingCounter.Size = UDim2.fromOffset(74, 16)
incomingCounter.BackgroundTransparency = 1
incomingCounter.Text = "0 active"
incomingCounter.TextColor3 = TEXT_COLOR
incomingCounter.TextTransparency = 0
incomingCounter.TextSize = 10
incomingCounter.TextScaled = false
incomingCounter.FontFace = NUMBERS_FONT
incomingCounter.TextXAlignment = Enum.TextXAlignment.Right
incomingCounter.TextYAlignment = Enum.TextYAlignment.Center
incomingCounter.ZIndex = 24
incomingCounter.Parent = incomingMenu

local rowsScroller = Instance.new("ScrollingFrame")
rowsScroller.Name = "Rows"
rowsScroller.Position = UDim2.fromOffset(23, 58)
rowsScroller.Size = UDim2.new(1, -46, 0, 38)
rowsScroller.BackgroundTransparency = 1
rowsScroller.BorderSizePixel = 0
rowsScroller.ScrollBarThickness = 0
rowsScroller.ScrollingDirection = Enum.ScrollingDirection.Y
rowsScroller.AutomaticCanvasSize = Enum.AutomaticSize.None
rowsScroller.CanvasSize = UDim2.fromOffset(0, 0)
rowsScroller.ZIndex = 23
rowsScroller.Parent = incomingMenu

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rowsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Padding = UDim.new(0, 0)
rowsLayout.Parent = rowsScroller

local incomingFooter = Instance.new("TextLabel")
incomingFooter.Name = "Footer"
incomingFooter.Position = UDim2.fromOffset(23, 98)
incomingFooter.Size = UDim2.new(1, -46, 0, 30)
incomingFooter.BackgroundTransparency = 1
incomingFooter.Text = "Combat ends when all incoming tags expire."
incomingFooter.TextColor3 = TEXT_COLOR
incomingFooter.TextTransparency = 0
incomingFooter.TextSize = 10
incomingFooter.TextScaled = false
incomingFooter.FontFace = NUMBERS_FONT
incomingFooter.TextWrapped = true
incomingFooter.TextXAlignment = Enum.TextXAlignment.Left
incomingFooter.TextYAlignment = Enum.TextYAlignment.Top
incomingFooter.ZIndex = 23
incomingFooter.Parent = incomingMenu

local contextMenu = Instance.new("Frame")
contextMenu.Name = "ContextMenu"
contextMenu.AnchorPoint = Vector2.new(0.5, 0)
contextMenu.Position = UDim2.new(0.5, 0, 0, INCOMING_MENU_OFFSET_Y)
contextMenu.Size = UDim2.fromOffset(CONTEXT_MENU_WIDTH, 46)
contextMenu.BackgroundTransparency = 1
contextMenu.Visible = false
contextMenu.ZIndex = 30
contextMenu.Parent = root

addWashi(contextMenu, 30)
addBorder(contextMenu, 0, 31)

local clearButton = Instance.new("TextButton")
clearButton.Name = "ClearTags"
clearButton.Position = UDim2.fromOffset(4, 4)
clearButton.Size = UDim2.new(1, -8, 1, -8)
clearButton.BackgroundTransparency = 1
clearButton.Text = "Clear tags"
clearButton.TextColor3 = CLEAR_COLOR
clearButton.TextTransparency = 0
clearButton.TextSize = 18
clearButton.TextScaled = false
clearButton.FontFace = TITLE_FONT
clearButton.TextXAlignment = Enum.TextXAlignment.Center
clearButton.TextYAlignment = Enum.TextYAlignment.Center
clearButton.AutoButtonColor = false
clearButton.ZIndex = 32
clearButton.Parent = contextMenu

local cameraViewportConnection: RBXScriptConnection? = nil

local function desiredScale(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end
	return math.min(viewport.X / REFERENCE_VIEWPORT.X, viewport.Y / REFERENCE_VIEWPORT.Y)
end

local function applyReferenceScale()
	baseScale = desiredScale()
	rootScale.Scale = baseScale
	root.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET * baseScale)
end

local function bindCurrentCamera()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyReferenceScale)
	end
	applyReferenceScale()
end

rememberConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera))
bindCurrentCamera()

local ROW_HEIGHT = 38
local MENU_TOP_PADDING = 25
local MENU_BOTTOM_PADDING = 20
local MENU_TITLE_BLOCK = 33
local MENU_FOOTER_GAP = 8
local MENU_FOOTER_HEIGHT = 30
local ROWS_TOP = MENU_TOP_PADDING + MENU_TITLE_BLOCK

local function closeMenus()
	incomingMenuOpen = false
	contextMenuOpen = false
	incomingMenu.Visible = false
	contextMenu.Visible = false
end

local function availableIncomingMenuHeight(): number
	local camera = Workspace.CurrentCamera
	if not camera or baseScale <= 0 then
		return 480
	end
	local viewportHeight = camera.ViewportSize.Y
	local markTopPx = TOP_OFFSET * baseScale
	local menuTopPx = markTopPx + INCOMING_MENU_OFFSET_Y * baseScale
	local availablePx = math.max(100, viewportHeight - menuTopPx - 8 * baseScale)
	return availablePx / baseScale
end

local function rebuildIncomingRows()
	for _, child in ipairs(rowsScroller:GetChildren()) do
		if child ~= rowsLayout then
			child:Destroy()
		end
	end
	table.clear(rowTimeLabels)

	for index, tag in ipairs(incomingTags) do
		local key = sourceKey(tag)
		local row = Instance.new("Frame")
		row.Name = "Tag_" .. key
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.ZIndex = 24
		row.Parent = rowsScroller

		local displayName = tag.sourceDisplayName
		if displayName == "" then
			displayName = tag.sourceName
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Position = UDim2.fromOffset(0, 0)
		nameLabel.Size = UDim2.new(1, -66, 1, -1)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = displayName
		nameLabel.TextColor3 = TEXT_COLOR
		nameLabel.TextTransparency = 0
		nameLabel.TextSize = 12
		nameLabel.TextScaled = false
		nameLabel.FontFace = NUMBERS_FONT
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.ZIndex = 24
		nameLabel.Parent = row

		local timeLabel = Instance.new("TextLabel")
		timeLabel.Name = "Time"
		timeLabel.AnchorPoint = Vector2.new(1, 0)
		timeLabel.Position = UDim2.new(1, 0, 0, 0)
		timeLabel.Size = UDim2.fromOffset(62, ROW_HEIGHT - 1)
		timeLabel.BackgroundTransparency = 1
		timeLabel.Text = formatRemaining(tag.expiresAt - Workspace:GetServerTimeNow())
		timeLabel.TextColor3 = TEXT_COLOR
		timeLabel.TextTransparency = 0
		timeLabel.TextSize = 12
		timeLabel.TextScaled = false
		timeLabel.FontFace = NUMBERS_FONT
		timeLabel.TextXAlignment = Enum.TextXAlignment.Right
		timeLabel.TextYAlignment = Enum.TextYAlignment.Center
		timeLabel.ZIndex = 24
		timeLabel.Parent = row
		rowTimeLabels[key] = timeLabel

		if index < #incomingTags then
			local separator = Instance.new("Frame")
			separator.Name = "Separator"
			separator.AnchorPoint = Vector2.new(0, 1)
			separator.Position = UDim2.new(0, 0, 1, 0)
			separator.Size = UDim2.new(1, 0, 0, 1)
			separator.BackgroundColor3 = SEPARATOR_COLOR
			separator.BackgroundTransparency = 0.67
			separator.BorderSizePixel = 0
			separator.ZIndex = 24
			separator.Parent = row
		end
	end

	incomingCounter.Text = tostring(#incomingTags) .. " active"
	local rowsHeight = #incomingTags * ROW_HEIGHT
	local desiredHeight = MENU_TOP_PADDING + MENU_TITLE_BLOCK + rowsHeight + MENU_FOOTER_GAP + MENU_FOOTER_HEIGHT + MENU_BOTTOM_PADDING
	local actualHeight = math.min(desiredHeight, availableIncomingMenuHeight())
	actualHeight = math.max(actualHeight, 132)
	local fixedHeight = MENU_TOP_PADDING + MENU_TITLE_BLOCK + MENU_FOOTER_GAP + MENU_FOOTER_HEIGHT + MENU_BOTTOM_PADDING
	local visibleRowsHeight = math.max(38, actualHeight - fixedHeight)
	incomingMenu.Size = UDim2.fromOffset(INCOMING_MENU_WIDTH, actualHeight)
	rowsScroller.Position = UDim2.fromOffset(23, ROWS_TOP)
	rowsScroller.Size = UDim2.new(1, -46, 0, visibleRowsHeight)
	rowsScroller.CanvasSize = UDim2.fromOffset(0, rowsHeight)
	incomingFooter.Position = UDim2.fromOffset(23, ROWS_TOP + visibleRowsHeight + MENU_FOOTER_GAP)
end

local function setIncomingMenuOpen(open: boolean)
	if not combatActive then
		open = false
	end
	incomingMenuOpen = open
	if open then
		contextMenuOpen = false
		contextMenu.Visible = false
		rebuildIncomingRows()
	end
	incomingMenu.Visible = open
end

local function setContextMenuOpen(open: boolean)
	if not combatActive then
		open = false
	end
	contextMenuOpen = open
	if open then
		incomingMenuOpen = false
		incomingMenu.Visible = false
	end
	contextMenu.Visible = open
end

local function pointInside(guiObject: GuiObject, point: Vector2): boolean
	if not guiObject.Visible then
		return false
	end
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return point.X >= pos.X and point.X <= pos.X + size.X and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
end

local resetBlocked = false
local resetCallback = Instance.new("BindableEvent")

local function applyResetCore()
	task.spawn(function()
		for _ = 1, 12 do
			local success = pcall(function()
				if resetBlocked then
					StarterGui:SetCore("ResetButtonCallback", resetCallback)
				else
					StarterGui:SetCore("ResetButtonCallback", true)
				end
			end)
			if success then
				return
			end
			task.wait(0.2)
		end
	end)
end

local function setResetBlocked(blocked: boolean)
	if resetBlocked == blocked then
		return
	end
	resetBlocked = blocked
	applyResetCore()
end

resetCallback.Event:Connect(function()
	if resetBlocked then
		resetAttemptRemote:FireServer()
	end
end)

rememberConnection(player.CharacterAdded:Connect(function()
	task.delay(0.5, function()
		if resetBlocked then
			applyResetCore()
		end
	end)
end))

local function updateHoverTimerVisibility()
	hoverTimer.Visible = combatActive and (markHovered or markSelected)
end

local hitFlashTween: Tween? = nil
local hitScaleTween: Tween? = nil
local exitTweens: {Tween} = {}

local function cancelExitTweens()
	for _, tween in ipairs(exitTweens) do
		tween:Cancel()
	end
	table.clear(exitTweens)
end

local function animateHit()
	if not combatActive then
		return
	end
	if hitFlashTween then
		hitFlashTween:Cancel()
		hitFlashTween = nil
	end
	if hitScaleTween then
		hitScaleTween:Cancel()
		hitScaleTween = nil
	end
	hitFlash.ImageTransparency = 1
	markPulseScale.Scale = 1

	if reducedMotion then
		hitFlashTween = playTween(hitFlash, TweenInfo.new(0.09, Enum.EasingStyle.Linear), {ImageTransparency = 0})
		task.delay(0.09, function()
			if hitFlash.Parent and combatActive then
				hitFlashTween = playTween(hitFlash, TweenInfo.new(0.09, Enum.EasingStyle.Linear), {ImageTransparency = 1})
			end
		end)
		return
	end

	local peakSeconds = HIT_SECONDS / 3
	hitFlashTween = playTween(hitFlash, TweenInfo.new(peakSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0})
	hitScaleTween = playTween(markPulseScale, TweenInfo.new(peakSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.05})
	task.delay(peakSeconds, function()
		if hitFlash.Parent and combatActive then
			hitFlashTween = playTween(hitFlash, TweenInfo.new(HIT_SECONDS - peakSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 1})
			hitScaleTween = playTween(markPulseScale, TweenInfo.new(HIT_SECONDS - peakSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1})
		end
	end)
end

local function animateEntry()
	exitingGeneration += 1
	cancelExitTweens()
	root.Visible = true
	root.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET * baseScale)
	rootScale.Scale = baseScale
	markPulseScale.Scale = 1
	hitFlash.ImageTransparency = 1
	spentMark.ImageTransparency = 0.15
	markFill.ImageTransparency = 0
	sealOrbitStart = Workspace:GetServerTimeNow()
	sealRotation.Rotation = 0

	if reducedMotion then
		revealClip.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
		markMotion.Position = UDim2.new(0.5, 0, 0.5, 0)
		sealEntranceScale.Scale = 1
		sealEntrance.Rotation = 0
		spentMark.ImageTransparency = 1
		markFill.ImageTransparency = 1
		sealRotation.ImageTransparency = 1
		playTween(spentMark, TweenInfo.new(REDUCED_MOTION_FADE, Enum.EasingStyle.Linear), {ImageTransparency = 0.15})
		playTween(markFill, TweenInfo.new(REDUCED_MOTION_FADE, Enum.EasingStyle.Linear), {ImageTransparency = 0})
		playTween(sealRotation, TweenInfo.new(REDUCED_MOTION_FADE, Enum.EasingStyle.Linear), {ImageTransparency = 0.28})
		return
	end

	markMotion.Position = UDim2.new(0.5, -9, 0.5, 5)
	revealClip.Size = UDim2.fromOffset(0, MARK_SIZE)
	playTween(revealClip, TweenInfo.new(ENTRY_MARK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)})
	local overshootSeconds = ENTRY_MARK_SECONDS * 0.74
	playTween(markMotion, TweenInfo.new(overshootSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 2, 0.5, -1)})
	task.delay(overshootSeconds, function()
		if markMotion.Parent and combatActive then
			playTween(markMotion, TweenInfo.new(ENTRY_MARK_SECONDS - overshootSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0.5, 0)})
		end
	end)

	sealEntranceScale.Scale = 0.9
	sealEntrance.Rotation = -12
	sealRotation.ImageTransparency = 1
	task.delay(ENTRY_SEAL_DELAY, function()
		if not combatActive or not sealEntrance.Parent then
			return
		end
		playTween(sealEntranceScale, TweenInfo.new(ENTRY_SEAL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1})
		playTween(sealEntrance, TweenInfo.new(ENTRY_SEAL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 0})
		playTween(sealRotation, TweenInfo.new(ENTRY_SEAL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0.28})
	end)
end

local function animateExit()
	exitingGeneration += 1
	local generation = exitingGeneration
	closeMenus()
	hoverTimer.Visible = false
	cancelExitTweens()
	local seconds = if reducedMotion then REDUCED_MOTION_FADE else EXIT_SECONDS
	local easing = if reducedMotion then Enum.EasingStyle.Linear else Enum.EasingStyle.Quad
	table.insert(exitTweens, playTween(spentMark, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), {ImageTransparency = 1}))
	table.insert(exitTweens, playTween(markFill, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), {ImageTransparency = 1}))
	table.insert(exitTweens, playTween(hitFlash, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), {ImageTransparency = 1}))
	table.insert(exitTweens, playTween(sealRotation, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), {ImageTransparency = 1}))
	if not reducedMotion then
		table.insert(exitTweens, playTween(root, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, (TOP_OFFSET - 5) * baseScale)}))
		table.insert(exitTweens, playTween(rootScale, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), {Scale = baseScale * 1.06}))
	end
	task.delay(seconds, function()
		if generation == exitingGeneration and not combatActive then
			root.Visible = false
			root.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET * baseScale)
			rootScale.Scale = baseScale
			spentMark.ImageTransparency = 0.15
			markFill.ImageTransparency = 0
			hitFlash.ImageTransparency = 1
			sealRotation.ImageTransparency = 0.28
			table.clear(exitTweens)
		end
	end)
end

local function setCombatActive(active: boolean)
	if combatActive == active then
		setResetBlocked(active)
		updateHoverTimerVisibility()
		return
	end
	combatActive = active
	setResetBlocked(active)
	if active then
		animateEntry()
	else
		animateExit()
	end
	updateHoverTimerVisibility()
end

local function setIncomingTags(records: {ClientTag})
	local currentTime = Workspace:GetServerTimeNow()
	local nextTags: {ClientTag} = {}
	local nextById: {[string]: ClientTag} = {}
	local authoritativeHit = false
	for _, tag in ipairs(records) do
		if typeof(tag) == "table" and typeof(tag.expiresAt) == "number" and tag.expiresAt > currentTime then
			local key = sourceKey(tag)
			local previous = incomingById[key]
			if combatActive and (not previous or tag.expiresAt > previous.expiresAt + 0.05) then
				authoritativeHit = true
			end
			table.insert(nextTags, tag)
			nextById[key] = tag
		end
	end
	table.sort(nextTags, function(a, b)
		if a.expiresAt == b.expiresAt then
			return string.lower(a.sourceDisplayName or a.sourceName) < string.lower(b.sourceDisplayName or b.sourceName)
		end
		return a.expiresAt > b.expiresAt
	end)
	incomingTags = nextTags
	incomingById = nextById
	if incomingMenuOpen then
		rebuildIncomingRows()
	else
		incomingCounter.Text = tostring(#incomingTags) .. " active"
	end
	setCombatActive(#incomingTags > 0)
	if authoritativeHit and combatActive then
		animateHit()
	end
end

local function setOutgoingCount(count: number)
	outgoingCount = math.max(0, math.floor(count))
	local enabled = outgoingCount > 0
	clearButton.Active = enabled
	clearButton.Selectable = enabled
end

rememberConnection(updateRemote.OnClientEvent:Connect(function(snapshot: {ClientTag})
	setIncomingTags(snapshot)
end))
rememberConnection(outgoingUpdateRemote.OnClientEvent:Connect(function(count: number)
	if typeof(count) == "number" then
		setOutgoingCount(count)
	end
end))

rememberConnection(markButton.MouseEnter:Connect(function()
	markHovered = true
	updateHoverTimerVisibility()
end))
rememberConnection(markButton.MouseLeave:Connect(function()
	markHovered = false
	updateHoverTimerVisibility()
end))
rememberConnection(markButton.SelectionGained:Connect(function()
	markSelected = true
	updateHoverTimerVisibility()
end))
rememberConnection(markButton.SelectionLost:Connect(function()
	markSelected = false
	updateHoverTimerVisibility()
end))
rememberConnection(markButton.Activated:Connect(function()
	if longPressTriggered then
		longPressTriggered = false
		return
	end
	setIncomingMenuOpen(not incomingMenuOpen)
end))
rememberConnection(markButton.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		setContextMenuOpen(not contextMenuOpen)
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		touchGeneration += 1
		local generation = touchGeneration
		longPressTriggered = false
		task.delay(TOUCH_LONG_PRESS_SECONDS, function()
			if generation == touchGeneration and input.UserInputState ~= Enum.UserInputState.End and combatActive then
				longPressTriggered = true
				setContextMenuOpen(not contextMenuOpen)
			end
		end)
	end
end))
rememberConnection(markButton.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		touchGeneration += 1
	end
end))
rememberConnection(clearButton.Activated:Connect(function()
	if outgoingCount <= 0 then
		return
	end
	clearOutgoingRequestRemote:FireServer()
	setContextMenuOpen(false)
end))
rememberConnection(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.Escape then
		closeMenus()
		return
	end
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if pointInside(markButton, position) or pointInside(incomingMenu, position) or pointInside(contextMenu, position) then
			return
		end
		closeMenus()
	end
end))

rememberConnection(RunService.RenderStepped:Connect(function()
	if not combatActive then
		return
	end
	local currentTime = Workspace:GetServerTimeNow()
	local maxExpiresAt = maxIncomingExpiresAt()
	local remaining = math.max(0, maxExpiresAt - currentTime)
	local ratio = math.clamp(remaining / TAG_DURATION, 0, 1)
	local spent = MARK_SIZE * (1 - ratio)
	fillClip.Position = UDim2.fromOffset(0, spent)
	fillClip.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE * ratio)
	markFill.Position = UDim2.fromOffset(0, -spent)
	markFill.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
	hitFlash.Position = UDim2.fromOffset(0, -spent)
	hitFlash.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
	hoverTimer.Text = formatRemaining(remaining)
	for _, tag in ipairs(incomingTags) do
		local timeLabel = rowTimeLabels[sourceKey(tag)]
		if timeLabel then
			timeLabel.Text = formatRemaining(tag.expiresAt - currentTime)
		end
	end
	if not reducedMotion then
		local elapsed = currentTime - sealOrbitStart
		sealRotation.Rotation = (elapsed * 360 / SEAL_ROTATION_SECONDS) % 360
	else
		sealRotation.Rotation = 0
	end
end))

setOutgoingCount(0)
requestSnapshotRemote:FireServer()
task.delay(1, function()
	if script.Parent then
		requestSnapshotRemote:FireServer()
	end
end)

script.Destroying:Connect(function()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
	end
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", true)
	end)
	resetCallback:Destroy()
end)

print("[CombatTagClient] Astra CombatTagHUD candidate ready")
