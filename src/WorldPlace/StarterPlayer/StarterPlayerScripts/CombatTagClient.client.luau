--!strict
-- CombatTagClient v3 - Option 1 + Shuriken Icon + Centered Layout
-- PLACE AS LocalScript:
-- StarterPlayer > StarterPlayerScripts > CombatTagClient
--
-- COLLAPSED:
--   [red shuriken]  IN COMBAT
--
-- HOVER:
--   compact details panel with tag sources + individual remaining times.
--
-- Everything is created from code. No PNG/UI preparation is required.
--
-- While tagged:
-- - Default Roblox Reset is intercepted/blocked.
-- - Clicking Reset sends a server-side "attempt" signal for future lives logic.
--
-- NOTE:
-- A game cannot prevent someone from closing Roblox.
-- Leaving while tagged is detected on the server as a combat log.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes =
	ReplicatedStorage:
	WaitForChild("CombatTagRemotes")

local updateRemote =
	remotes:
	WaitForChild("CombatTagUpdate") :: RemoteEvent

local requestSnapshotRemote =
	remotes:
	WaitForChild("CombatTagRequestSnapshot") :: RemoteEvent

local resetAttemptRemote =
	remotes:
	WaitForChild("CombatTagResetAttempt") :: RemoteEvent


-- ============================================================
-- CONFIG
-- ============================================================

local HEADER_WIDTH = 150
local HEADER_HEIGHT = 32

local DETAILS_WIDTH = 310
local DETAILS_TOP_PADDING = 12
local DETAILS_BOTTOM_PADDING = 10
local DETAILS_TITLE_HEIGHT = 20
local DETAILS_INFO_HEIGHT = 18
local ROW_HEIGHT = 25
local MAX_VISIBLE_ROWS = 6

local TOP_OFFSET = 10

local FADE_TIME = 0.14
local EXPAND_TIME = 0.16
local HOVER_CLOSE_DELAY = 0.08

local PANEL_TRANSPARENCY = 0.45
local DETAILS_TRANSPARENCY = 0.35

local COLOR_BLACK = Color3.fromRGB(14, 14, 14)
local COLOR_BLACK_2 = Color3.fromRGB(22, 20, 18)
local COLOR_RED = Color3.fromRGB(220, 47, 47)
local COLOR_RED_BRIGHT = Color3.fromRGB(244, 66, 66)
local COLOR_GOLD = Color3.fromRGB(171, 126, 48)
local COLOR_TEXT = Color3.fromRGB(235, 232, 224)
local COLOR_DIM = Color3.fromRGB(170, 166, 157)


-- ============================================================
-- STATE
-- ============================================================

type ClientTag = {
	sourceUserId: number,
	sourceName: string,
	sourceDisplayName: string,
	expiresAt: number,
}

local activeTags: {ClientTag} = {}
local combatTagged = false
local expanded = false

local hoverHeader = false
local hoverDetails = false
local hoverGeneration = 0

local resetBlocked = false
local resetCallback = Instance.new("BindableEvent")


-- ============================================================
-- GUI ROOT
-- ============================================================

local oldGui =
	playerGui:
	FindFirstChild("CombatTagGui")

if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "CombatTagGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 95
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui


local root = Instance.new("Frame")
root.Name = "CombatTagRoot"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position =
	UDim2.new(
		0.5,
		0,
		0,
		TOP_OFFSET
	)

root.Size =
	UDim2.fromOffset(
		DETAILS_WIDTH,
		HEADER_HEIGHT
	)

root.BackgroundTransparency = 1
root.Visible = false
root.ClipsDescendants = false
root.ZIndex = 50
root.Parent = gui


-- ============================================================
-- COLLAPSED HEADER
-- ============================================================

local header = Instance.new("Frame")
header.Name = "Header"
header.AnchorPoint = Vector2.new(0.5, 0)
header.Position =
	UDim2.new(
		0.5,
		0,
		0,
		0
	)

header.Size =
	UDim2.fromOffset(
		HEADER_WIDTH,
		HEADER_HEIGHT
	)

header.BackgroundColor3 = COLOR_BLACK
header.BackgroundTransparency = PANEL_TRANSPARENCY
header.BorderSizePixel = 0
header.Active = true
header.ZIndex = 52
header.Parent = root

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 7)
headerCorner.Parent = header

local headerStroke = Instance.new("UIStroke")
headerStroke.Color = COLOR_GOLD
headerStroke.Thickness = 1
headerStroke.Transparency = 0.48
headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
headerStroke.Parent = header


local redAccent = Instance.new("Frame")
redAccent.Name = "RedAccent"
redAccent.AnchorPoint = Vector2.new(0, 0.5)
redAccent.Position = UDim2.new(0, 0, 0.5, 0)
redAccent.Size = UDim2.fromOffset(3, 18)
redAccent.BackgroundColor3 = COLOR_RED
redAccent.BackgroundTransparency = 0.08
redAccent.BorderSizePixel = 0
redAccent.ZIndex = 53
redAccent.Parent = header

local redAccentCorner = Instance.new("UICorner")
redAccentCorner.CornerRadius = UDim.new(1, 0)
redAccentCorner.Parent = redAccent


local headerContent = Instance.new("Frame")
headerContent.Name = "HeaderContent"
headerContent.AnchorPoint = Vector2.new(0.5, 0.5)
headerContent.Position = UDim2.new(0.5, 0, 0.5, 0)
headerContent.Size = UDim2.fromOffset(108, HEADER_HEIGHT)
headerContent.BackgroundTransparency = 1
headerContent.ZIndex = 53
headerContent.Parent = header


local skull = Instance.new("ImageLabel")
skull.Name = "ShurikenIcon"
skull.AnchorPoint = Vector2.new(0, 0.5)
skull.Position = UDim2.new(0, 0, 0.5, 0)
skull.Size = UDim2.fromOffset(20, 20)
skull.BackgroundTransparency = 1
skull.Image = "rbxassetid://73652859108274"
skull.ImageColor3 = Color3.new(1, 1, 1)
skull.ImageTransparency = 0
skull.ScaleType = Enum.ScaleType.Fit
skull.ZIndex = 54
skull.Parent = headerContent


local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(28, 0)
title.Size = UDim2.fromOffset(80, HEADER_HEIGHT)
title.BackgroundTransparency = 1
title.Text = "IN COMBAT"
title.TextColor3 = COLOR_RED_BRIGHT
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Center
title.ZIndex = 54
title.Parent = headerContent


-- ============================================================
-- DETAILS PANEL
-- ============================================================

local details = Instance.new("Frame")
details.Name = "Details"
details.AnchorPoint = Vector2.new(0.5, 0)
details.Position =
	UDim2.new(
		0.5,
		0,
		0,
		HEADER_HEIGHT + 6
	)

details.Size =
	UDim2.fromOffset(
		DETAILS_WIDTH,
		1
	)

details.BackgroundColor3 = COLOR_BLACK
details.BackgroundTransparency = DETAILS_TRANSPARENCY
details.BorderSizePixel = 0
details.Active = true
details.Visible = false
details.ClipsDescendants = true
details.ZIndex = 51
details.Parent = root

local detailsCorner = Instance.new("UICorner")
detailsCorner.CornerRadius = UDim.new(0, 7)
detailsCorner.Parent = details

local detailsStroke = Instance.new("UIStroke")
detailsStroke.Color = COLOR_GOLD
detailsStroke.Thickness = 1
detailsStroke.Transparency = 0.48
detailsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
detailsStroke.Parent = details


local detailTitle = Instance.new("TextLabel")
detailTitle.Name = "DetailTitle"
detailTitle.Position =
	UDim2.fromOffset(
		12,
		DETAILS_TOP_PADDING
	)

detailTitle.Size =
	UDim2.new(
		1,
		-24,
		0,
		DETAILS_TITLE_HEIGHT
	)

detailTitle.BackgroundTransparency = 1
detailTitle.Text = "COMBAT TAG"
detailTitle.TextColor3 = COLOR_TEXT
detailTitle.TextSize = 13
detailTitle.Font = Enum.Font.GothamBold
detailTitle.TextXAlignment = Enum.TextXAlignment.Center
detailTitle.ZIndex = 52
detailTitle.Parent = details


local restriction = Instance.new("TextLabel")
restriction.Name = "Restriction"
restriction.Position =
	UDim2.fromOffset(
		12,
		DETAILS_TOP_PADDING
		+ DETAILS_TITLE_HEIGHT
	)

restriction.Size =
	UDim2.new(
		1,
		-24,
		0,
		DETAILS_INFO_HEIGHT
	)

restriction.BackgroundTransparency = 1
restriction.Text =
	"Reset blocked  •  Leaving counts as combat log"

restriction.TextColor3 = COLOR_DIM
restriction.TextSize = 11
restriction.Font = Enum.Font.Gotham
restriction.TextXAlignment = Enum.TextXAlignment.Center
restriction.ZIndex = 52
restriction.Parent = details


local taggedByLabel = Instance.new("TextLabel")
taggedByLabel.Name = "TaggedByLabel"
taggedByLabel.Position =
	UDim2.fromOffset(
		12,
		DETAILS_TOP_PADDING
		+ DETAILS_TITLE_HEIGHT
		+ DETAILS_INFO_HEIGHT
		+ 5
	)

taggedByLabel.Size =
	UDim2.new(
		1,
		-24,
		0,
		18
	)

taggedByLabel.BackgroundTransparency = 1
taggedByLabel.Text = "TAGGED BY"
taggedByLabel.TextColor3 = COLOR_RED_BRIGHT
taggedByLabel.TextSize = 11
taggedByLabel.Font = Enum.Font.GothamBold
taggedByLabel.TextXAlignment = Enum.TextXAlignment.Left
taggedByLabel.ZIndex = 52
taggedByLabel.Parent = details


local rowsContainer = Instance.new("Frame")
rowsContainer.Name = "Rows"
rowsContainer.Position =
	UDim2.fromOffset(
		12,
		DETAILS_TOP_PADDING
		+ DETAILS_TITLE_HEIGHT
		+ DETAILS_INFO_HEIGHT
		+ 25
	)

rowsContainer.Size =
	UDim2.new(
		1,
		-24,
		0,
		0
	)

rowsContainer.BackgroundTransparency = 1
rowsContainer.ZIndex = 52
rowsContainer.Parent = details


local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Vertical
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, 0)
rowLayout.Parent = rowsContainer


-- ============================================================
-- ROWS
-- ============================================================

local rowTimeLabels: {[number]: TextLabel} = {}
local overflowLabel: TextLabel? = nil


local function formatRemaining(
	seconds: number
): string

	seconds =
		math.max(
			0,
			math.ceil(seconds)
		)

	local minutes =
		math.floor(
			seconds / 60
		)

	local remainder =
		seconds % 60

	return string.format(
		"%d:%02d",
		minutes,
		remainder
	)
end


local function getDetailHeight(): number
	local visibleRows =
		math.min(
			#activeTags,
			MAX_VISIBLE_ROWS
		)

	local overflowRows =
		if #activeTags >
		MAX_VISIBLE_ROWS
		then 1
		else 0

	return DETAILS_TOP_PADDING
		+ DETAILS_TITLE_HEIGHT
		+ DETAILS_INFO_HEIGHT
		+ 25
		+ (visibleRows + overflowRows) * ROW_HEIGHT
		+ DETAILS_BOTTOM_PADDING
end


local function rebuildRows()
	for _, child in ipairs(
		rowsContainer:GetChildren()
		) do
		if child ~= rowLayout then
			child:Destroy()
		end
	end

	table.clear(rowTimeLabels)
	overflowLabel = nil

	local visibleCount =
		math.min(
			#activeTags,
			MAX_VISIBLE_ROWS
		)

	for index = 1, visibleCount do
		local tag =
			activeTags[index]

		local row = Instance.new("Frame")
		row.Name = "Tag_" .. tostring(tag.sourceUserId)
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.ZIndex = 53
		row.Parent = rowsContainer

		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 1, 0.5, 0)
		dot.Size = UDim2.fromOffset(5, 5)
		dot.BackgroundColor3 = COLOR_RED
		dot.BorderSizePixel = 0
		dot.ZIndex = 54
		dot.Parent = row

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Position = UDim2.fromOffset(13, 0)
		nameLabel.Size = UDim2.new(1, -82, 1, 0)
		nameLabel.BackgroundTransparency = 1

		local display =
			tag.sourceDisplayName

		if display == "" then
			display = tag.sourceName
		end

		nameLabel.Text = display
		nameLabel.TextColor3 = COLOR_TEXT
		nameLabel.TextSize = 12
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.ZIndex = 54
		nameLabel.Parent = row

		local timeLabel = Instance.new("TextLabel")
		timeLabel.AnchorPoint = Vector2.new(1, 0)
		timeLabel.Position = UDim2.new(1, 0, 0, 0)
		timeLabel.Size = UDim2.fromOffset(64, ROW_HEIGHT)
		timeLabel.BackgroundTransparency = 1
		timeLabel.TextColor3 = COLOR_DIM
		timeLabel.TextSize = 12
		timeLabel.Font = Enum.Font.GothamMedium
		timeLabel.TextXAlignment = Enum.TextXAlignment.Right
		timeLabel.ZIndex = 54
		timeLabel.Parent = row

		rowTimeLabels[tag.sourceUserId] =
			timeLabel
	end

	if #activeTags > MAX_VISIBLE_ROWS then
		local more =
			Instance.new("TextLabel")

		more.Name = "Overflow"
		more.LayoutOrder = MAX_VISIBLE_ROWS + 1
		more.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		more.BackgroundTransparency = 1
		more.Text =
			"+ "
			.. tostring(
				#activeTags - MAX_VISIBLE_ROWS
			)
			.. " more"

		more.TextColor3 = COLOR_DIM
		more.TextSize = 11
		more.Font = Enum.Font.Gotham
		more.TextXAlignment = Enum.TextXAlignment.Left
		more.ZIndex = 53
		more.Parent = rowsContainer
		overflowLabel = more
	end

	rowsContainer.Size =
		UDim2.new(
			1,
			-24,
			0,
			(
				math.min(
					#activeTags,
					MAX_VISIBLE_ROWS
				)
				+
				(
					if #activeTags >
					MAX_VISIBLE_ROWS
					then 1
					else 0
				)
			)
			* ROW_HEIGHT
		)
end


-- ============================================================
-- EXPAND / COLLAPSE
-- ============================================================

local sizeTween: Tween? = nil


local function setExpanded(
	value: boolean
)
	if expanded == value then
		return
	end

	expanded = value

	if sizeTween then
		sizeTween:Cancel()
		sizeTween = nil
	end

	if expanded then
		details.Visible = true
		details.Size =
			UDim2.fromOffset(
				DETAILS_WIDTH,
				1
			)

		local targetHeight =
			getDetailHeight()

		sizeTween =
			TweenService:Create(
				details,
				TweenInfo.new(
					EXPAND_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					Size =
					UDim2.fromOffset(
						DETAILS_WIDTH,
						targetHeight
					)
				}
			)

		sizeTween:Play()

		root.Size =
			UDim2.fromOffset(
				DETAILS_WIDTH,
				HEADER_HEIGHT
				+ 6
				+ targetHeight
			)
	else
		sizeTween =
			TweenService:Create(
				details,
				TweenInfo.new(
					EXPAND_TIME * 0.8,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					Size =
					UDim2.fromOffset(
						DETAILS_WIDTH,
						1
					)
				}
			)

		sizeTween:Play()

		local generation =
			hoverGeneration

		task.delay(
			EXPAND_TIME * 0.8,
			function()
				if not expanded
					and generation ==
					hoverGeneration then

					details.Visible = false

					root.Size =
						UDim2.fromOffset(
							DETAILS_WIDTH,
							HEADER_HEIGHT
						)
				end
			end
		)
	end
end


local function evaluateHoverSoon()
	hoverGeneration += 1
	local generation =
		hoverGeneration

	task.delay(
		HOVER_CLOSE_DELAY,
		function()
			if generation ~=
				hoverGeneration then

				return
			end

			setExpanded(
				hoverHeader
					or hoverDetails
			)
		end
	)
end


header.MouseEnter:Connect(function()
	hoverHeader = true
	hoverGeneration += 1
	setExpanded(true)
end)

header.MouseLeave:Connect(function()
	hoverHeader = false
	evaluateHoverSoon()
end)

details.MouseEnter:Connect(function()
	hoverDetails = true
	hoverGeneration += 1
	setExpanded(true)
end)

details.MouseLeave:Connect(function()
	hoverDetails = false
	evaluateHoverSoon()
end)


-- ============================================================
-- RESET BLOCK
-- ============================================================

local function applyResetCore()
	task.spawn(function()
		for attempt = 1, 12 do
			local success =
				pcall(function()
					if resetBlocked then
						StarterGui:SetCore(
							"ResetButtonCallback",
							resetCallback
						)
					else
						StarterGui:SetCore(
							"ResetButtonCallback",
							true
						)
					end
				end)

			if success then
				return
			end

			task.wait(0.2)
		end
	end)
end


local function setResetBlocked(
	blocked: boolean
)
	if resetBlocked == blocked then
		return
	end

	resetBlocked = blocked
	applyResetCore()
end


resetCallback.Event:Connect(function()
	if resetBlocked then
		resetAttemptRemote:FireServer()

		-- Small visual acknowledgement without adding a permanent warning.
		local oldColor =
			headerStroke.Color

		headerStroke.Color =
			COLOR_RED_BRIGHT

		task.delay(0.18, function()
			if headerStroke.Parent then
				headerStroke.Color =
					oldColor
			end
		end)
	end
end)


player.CharacterAdded:Connect(function()
	task.delay(0.5, function()
		if resetBlocked then
			applyResetCore()
		end
	end)
end)


-- ============================================================
-- TAG VISIBILITY / SERVER SNAPSHOT
-- ============================================================

local fadeTween: Tween? = nil

local function setCombatTagged(
	active: boolean
)
	if combatTagged == active then
		setResetBlocked(active)
		return
	end

	combatTagged = active

	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end

	if active then
		root.Visible = true

		header.BackgroundTransparency = 1
		skull.ImageTransparency = 1
		title.TextTransparency = 1
		redAccent.BackgroundTransparency = 1
		headerStroke.Transparency = 1

		fadeTween =
			TweenService:Create(
				header,
				TweenInfo.new(
					FADE_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					BackgroundTransparency =
					PANEL_TRANSPARENCY
				}
			)

		fadeTween:Play()

		TweenService:Create(
			skull,
			TweenInfo.new(FADE_TIME),
			{ImageTransparency = 0}
		):Play()

		TweenService:Create(
			title,
			TweenInfo.new(FADE_TIME),
			{TextTransparency = 0}
		):Play()

		TweenService:Create(
			redAccent,
			TweenInfo.new(FADE_TIME),
			{BackgroundTransparency = 0.08}
		):Play()

		TweenService:Create(
			headerStroke,
			TweenInfo.new(FADE_TIME),
			{Transparency = 0.48}
		):Play()
	else
		hoverHeader = false
		hoverDetails = false
		hoverGeneration += 1
		setExpanded(false)

		task.delay(
			FADE_TIME,
			function()
				if not combatTagged then
					root.Visible = false
				end
			end
		)
	end

	setResetBlocked(active)
end


updateRemote.OnClientEvent:Connect(
	function(snapshot: {ClientTag})
		activeTags = {}

		local currentTime =
			workspace:GetServerTimeNow()

		for _, tag in ipairs(snapshot) do
			if typeof(tag) == "table"
				and typeof(tag.expiresAt) == "number"
				and tag.expiresAt > currentTime then

				table.insert(
					activeTags,
					tag
				)
			end
		end

		table.sort(activeTags, function(a, b)
			return a.expiresAt > b.expiresAt
		end)

		rebuildRows()

		if expanded then
			local targetHeight =
				getDetailHeight()

			details.Size =
				UDim2.fromOffset(
					DETAILS_WIDTH,
					targetHeight
				)

			root.Size =
				UDim2.fromOffset(
					DETAILS_WIDTH,
					HEADER_HEIGHT
					+ 6
					+ targetHeight
				)
		end

		setCombatTagged(
			#activeTags > 0
		)
	end
)


-- ============================================================
-- TIMER DISPLAY
-- ============================================================

local timerAccumulator = 0

RunService.RenderStepped:Connect(
	function(deltaTime: number)
		if not combatTagged then
			return
		end

		timerAccumulator += deltaTime

		if timerAccumulator < 0.10 then
			return
		end

		timerAccumulator = 0

		local currentTime =
			workspace:GetServerTimeNow()

		for _, tag in ipairs(activeTags) do
			local label =
				rowTimeLabels[
			tag.sourceUserId
			]

			if label then
				label.Text =
					formatRemaining(
						tag.expiresAt
						- currentTime
					)
			end
		end
	end
)


-- ============================================================
-- INITIAL SYNC
-- ============================================================

requestSnapshotRemote:FireServer()

task.delay(1, function()
	-- Covers the rare case where server scripts were still starting
	-- when this LocalScript first requested its snapshot.
	requestSnapshotRemote:FireServer()
end)

script.Destroying:Connect(function()
	pcall(function()
		StarterGui:SetCore(
			"ResetButtonCallback",
			true
		)
	end)
end)

print(
	"[CombatTagClient] Option 1 + Shuriken + Centered ready"
)
