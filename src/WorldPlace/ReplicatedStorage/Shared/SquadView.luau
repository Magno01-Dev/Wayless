--!strict
-- ReplicatedStorage > Shared > SquadView
-- WAYLESS SquadUI v1 candidate — presentation defined by Astra SquadUI.zip.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SquadView = {}
SquadView.__index = SquadView

export type MemberData = {
	UserId: number,
	characterName: string,
	username: string,
	identityKey: string,
	health: number,
	maxHealth: number,
}

export type SearchEntry = {
	UserId: number,
	characterName: string,
	username: string,
	isLeader: boolean?,
	isSelf: boolean?,
}

export type View = typeof(setmetatable({} :: any, SquadView))

type AssetMeta = {
	Canvas: Vector2,
	Bounds: {number},
}

type RowCallbacks = {
	Invite: ((number) -> ())?,
	Remove: ((number) -> ())?,
}

local COLOR_DARK = Color3.fromRGB(18, 23, 25)
local COLOR_CREAM = Color3.fromRGB(238, 226, 198)
local COLOR_GOLD = Color3.fromRGB(165, 138, 96)
local COLOR_BROWN = Color3.fromRGB(56, 39, 25)
local COLOR_MUTED = Color3.fromRGB(128, 108, 83)
local COLOR_RED = Color3.fromRGB(145, 70, 46)
local COLOR_HEALTH_A = Color3.fromRGB(133, 62, 57)
local COLOR_HEALTH_B = Color3.fromRGB(187, 115, 103)

local function makeFrame(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function makeCanvasGroup(name: string, parent: Instance): CanvasGroup
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 0
	group.Parent = parent
	return group
end

local function makeText(
	name: string,
	parent: Instance,
	font: Font,
	textSize: number,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = font
	label.Text = ""
	label.TextColor3 = color
	label.TextSize = textSize
	label.TextScaled = false
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function makeTextButton(
	name: string,
	parent: Instance,
	font: Font,
	textSize: number,
	color: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.FontFace = font
	button.Text = ""
	button.TextColor3 = color
	button.TextSize = textSize
	button.TextScaled = false
	button.Parent = parent
	return button
end

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function identityColor(config: any, key: string): Color3
	for _, identity in ipairs(config.Identities) do
		if identity.Key == key then
			return identity.Color
		end
	end
	return COLOR_GOLD
end

local function addBoundedAsset(
	config: any,
	parent: Instance,
	name: string,
	assetKey: string,
	visibleX: number,
	visibleY: number,
	desiredVisibleWidth: number,
	zIndex: number
): ImageLabel
	local assetId = config.Assets[assetKey]
	local meta = config.AssetMeta[assetKey] :: AssetMeta
	local bounds = meta.Bounds
	local scale = desiredVisibleWidth / bounds[3]

	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = assetId
	image.ImageTransparency = 0
	image.ScaleType = Enum.ScaleType.Stretch
	image.Position = UDim2.fromOffset(
		visibleX - bounds[1] * scale,
		visibleY - bounds[2] * scale
	)
	image.Size = UDim2.fromOffset(
		meta.Canvas.X * scale,
		meta.Canvas.Y * scale
	)
	image.ZIndex = zIndex
	image.Parent = parent
	return image
end

local function addPlainAsset(
	config: any,
	parent: Instance,
	name: string,
	assetKey: string,
	position: Vector2,
	size: Vector2,
	zIndex: number,
	color: Color3?
): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = config.Assets[assetKey]
	image.ImageTransparency = 0
	image.ScaleType = Enum.ScaleType.Fit
	image.Position = UDim2.fromOffset(position.X, position.Y)
	image.Size = UDim2.fromOffset(size.X, size.Y)
	image.ZIndex = zIndex
	if color then
		image.ImageColor3 = color
	end
	image.Parent = parent
	return image
end

local function connectButtonFeedback(button: GuiButton, image: ImageLabel?)
	local hovering = false
	local pressing = false

	local function apply()
		if image then
			if pressing then
				image.ImageColor3 = Color3.fromRGB(220, 220, 220)
			elseif hovering then
				image.ImageColor3 = Color3.fromRGB(255, 255, 255)
			else
				image.ImageColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end

	button.MouseEnter:Connect(function()
		hovering = true
		apply()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		apply()
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true
			apply()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false
			apply()
		end
	end)

	apply()
end

local function createAssetButton(
	config: any,
	parent: Instance,
	name: string,
	assetKey: string,
	position: Vector2,
	size: Vector2,
	text: string,
	textColor: Color3,
	textSize: number,
	zIndex: number
): TextButton
	local button = makeTextButton(name, parent, config.Fonts.Title, textSize, textColor)
	button.Position = UDim2.fromOffset(position.X, position.Y)
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.Text = text
	button.ZIndex = zIndex + 1

	local meta = config.AssetMeta[assetKey] :: AssetMeta
	local bounds = meta.Bounds
	local visibleAspect = bounds[3] / bounds[4]
	local desiredVisibleWidth = size.X
	local desiredVisibleHeight = desiredVisibleWidth / visibleAspect
	if desiredVisibleHeight > size.Y then
		desiredVisibleHeight = size.Y
		desiredVisibleWidth = desiredVisibleHeight * visibleAspect
	end
	local x = (size.X - desiredVisibleWidth) * 0.5
	local y = (size.Y - desiredVisibleHeight) * 0.5
	local art = addBoundedAsset(config, button, "Art", assetKey, x, y, desiredVisibleWidth, zIndex)
	connectButtonFeedback(button, art)
	return button
end

local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

function SquadView.new(config: any, playerGui: PlayerGui): View
	local self = setmetatable({}, SquadView)
	self.Config = config
	self.PlayerGui = playerGui
	self.Destroyed = false
	self.ReducedMotion = false
	self.Scale = 1
	self.Connections = {}
	self.MenuTransitionRevision = 0
	self.InviteTransitionRevision = 0
	self.NoticeRevision = 0
	self.MenuTween = nil
	self.MenuFadeTween = nil
	self.InviteTween = nil
	self.InviteFadeTween = nil
	self.NoticeTween = nil
	self.NoticeTimer = nil
	self.HUDRows = {}
	self.MarkerRows = {}
	self.CurrentMembers = {}

	local old = playerGui:FindFirstChild("SquadUI")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SquadUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 75
	gui.Parent = playerGui
	self.Gui = gui

	self:_buildSocial()
	self:_buildMenu()
	self:_buildInvitation()
	self:_buildHUD()
	self:_buildMarkers()
	self:_buildNotice()
	self:_bindViewport()

	return self
end

function SquadView:_buildSocial()
	local config = self.Config
	local button = makeTextButton("SocialButton", self.Gui, config.Fonts.Body, 15, COLOR_CREAM)
	button.Text = "Social"
	button.TextXAlignment = Enum.TextXAlignment.Right
	button.BackgroundColor3 = Color3.fromRGB(21, 27, 28)
	button.BackgroundTransparency = 0.21
	button.BorderSizePixel = 0
	button.ZIndex = 20
	addCorner(button, 7)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(188, 162, 118)
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = button

	local icon = addBoundedAsset(config, button, "Icon", "People", 12, 10, 24, 21)
	icon.ImageColor3 = Color3.fromRGB(231, 223, 205)

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = Color3.fromRGB(48, 55, 51)
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Color3.fromRGB(21, 27, 28)
	end)

	self.SocialButton = button
end

function SquadView:_buildMenu()
	local config = self.Config
	local layout = config.Layout.Menu
	local outer = makeCanvasGroup("SquadMenu", self.Gui)
	outer.Visible = false
	outer.ZIndex = 15
	self.Menu = outer

	local canvas = makeFrame("Canvas", outer)
	canvas.Size = UDim2.fromOffset(layout.CanvasSize.X, layout.CanvasSize.Y)
	canvas.ZIndex = 15
	self.MenuCanvas = canvas

	local scale = Instance.new("UIScale")
	scale.Name = "LocalScale"
	scale.Scale = layout.LocalScale
	scale.Parent = canvas
	self.MenuLocalScale = scale

	addBoundedAsset(config, canvas, "Panel", "Panel", 0, 0, 608, 15)

	addBoundedAsset(config, canvas, "Title", "Title", 40, 28, 280, 16)

	local close = makeTextButton("Close", canvas, Font.fromEnum(Enum.Font.Arial), 36, Color3.fromRGB(116, 91, 60))
	close.Position = UDim2.fromOffset(535, 25)
	close.Size = UDim2.fromOffset(40, 40)
	close.Text = "×"
	close.ZIndex = 20
	self.CloseButton = close

	local rule = makeFrame("Rule", canvas)
	rule.Position = UDim2.fromOffset(40, 119)
	rule.Size = UDim2.fromOffset(528, 1)
	rule.BackgroundColor3 = Color3.fromRGB(157, 128, 90)
	rule.BackgroundTransparency = 0.25
	rule.ZIndex = 17

	local tabs = makeFrame("Tabs", canvas)
	tabs.Position = UDim2.fromOffset(40, 132)
	tabs.Size = UDim2.fromOffset(528, 34)
	tabs.ZIndex = 18
	self.Tabs = tabs

	local inviteTab = makeTextButton("InviteTab", tabs, config.Fonts.Title, 21, COLOR_BROWN)
	inviteTab.Position = UDim2.fromOffset(0, 0)
	inviteTab.Size = UDim2.fromOffset(132, 34)
	inviteTab.Text = "Invite player"
	inviteTab.TextXAlignment = Enum.TextXAlignment.Left
	inviteTab.ZIndex = 19
	self.InviteTab = inviteTab

	local membersTab = makeTextButton("MembersTab", tabs, config.Fonts.Title, 21, COLOR_MUTED)
	membersTab.Position = UDim2.fromOffset(154, 0)
	membersTab.Size = UDim2.fromOffset(100, 34)
	membersTab.Text = "Members"
	membersTab.TextXAlignment = Enum.TextXAlignment.Left
	membersTab.ZIndex = 19
	self.MembersTab = membersTab

	local tabLine = makeFrame("TabLine", tabs)
	tabLine.Position = UDim2.new(0, 0, 1, -1)
	tabLine.Size = UDim2.new(1, 0, 0, 1)
	tabLine.BackgroundColor3 = Color3.fromRGB(146, 119, 86)
	tabLine.BackgroundTransparency = 0.67
	tabLine.ZIndex = 18

	local activeLine = makeFrame("ActiveLine", tabs)
	activeLine.Position = UDim2.fromOffset(0, 31)
	activeLine.Size = UDim2.fromOffset(132, 2)
	activeLine.BackgroundColor3 = Color3.fromRGB(157, 75, 50)
	activeLine.BackgroundTransparency = 0
	activeLine.ZIndex = 20
	self.ActiveTabLine = activeLine

	local sectionTitle = makeText("SectionTitle", canvas, config.Fonts.Title, 25, COLOR_BROWN)
	sectionTitle.Position = UDim2.fromOffset(40, 174)
	sectionTitle.Size = UDim2.fromOffset(528, 30)
	sectionTitle.Text = "Invite player"
	sectionTitle.ZIndex = 18
	self.SectionTitle = sectionTitle

	local searchLabel = makeText("SearchLabel", canvas, config.Fonts.Body, 17, Color3.fromRGB(102, 81, 61))
	searchLabel.Position = UDim2.fromOffset(40, 207)
	searchLabel.Size = UDim2.fromOffset(528, 22)
	searchLabel.Text = "Search by character name or username"
	searchLabel.ZIndex = 18
	self.SearchLabel = searchLabel

	local search = makeFrame("SearchArea", canvas)
	search.Position = UDim2.fromOffset(40, 236)
	search.Size = UDim2.fromOffset(528, 52)
	search.BackgroundColor3 = Color3.fromRGB(238, 224, 194)
	search.BackgroundTransparency = 0.84
	search.BorderSizePixel = 0
	search.ZIndex = 18
	addCorner(search, 4)
	local searchStroke = Instance.new("UIStroke")
	searchStroke.Color = Color3.fromRGB(126, 103, 74)
	searchStroke.Thickness = 1
	searchStroke.Parent = search
	self.SearchArea = search

	local searchIcon = makeFrame("SearchIcon", search)
	searchIcon.Position = UDim2.fromOffset(18, 15)
	searchIcon.Size = UDim2.fromOffset(21, 21)
	searchIcon.BackgroundTransparency = 1
	searchIcon.ZIndex = 19
	local circle = Instance.new("UIStroke")
	circle.Color = Color3.fromRGB(52, 37, 26)
	circle.Thickness = 3
	circle.Parent = searchIcon
	addCorner(searchIcon, 20)
	local handle = makeFrame("Handle", searchIcon)
	handle.Position = UDim2.fromOffset(16, 18)
	handle.Size = UDim2.fromOffset(12, 3)
	handle.AnchorPoint = Vector2.new(0, 0.5)
	handle.Rotation = 48
	handle.BackgroundColor3 = Color3.fromRGB(52, 37, 26)
	handle.BackgroundTransparency = 0
	handle.ZIndex = 20

	local box = Instance.new("TextBox")
	box.Name = "SearchBox"
	box.Position = UDim2.fromOffset(55, 0)
	box.Size = UDim2.new(1, -70, 1, 0)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.FontFace = config.Fonts.Body
	box.PlaceholderText = "Name or @username"
	box.PlaceholderColor3 = Color3.fromRGB(120, 101, 79)
	box.Text = ""
	box.TextColor3 = Color3.fromRGB(57, 45, 32)
	box.TextSize = 19
	box.TextScaled = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ZIndex = 20
	box.Parent = search
	self.SearchBox = box

	local results = Instance.new("ScrollingFrame")
	results.Name = "Results"
	results.Position = UDim2.fromOffset(40, 302)
	results.Size = UDim2.fromOffset(528, 276)
	results.BackgroundTransparency = 1
	results.BorderSizePixel = 0
	results.ScrollBarThickness = 3
	results.ScrollBarImageColor3 = Color3.fromRGB(126, 103, 74)
	results.AutomaticCanvasSize = Enum.AutomaticSize.Y
	results.CanvasSize = UDim2.fromOffset(0, 0)
	results.ScrollingDirection = Enum.ScrollingDirection.Y
	results.ZIndex = 18
	results.Parent = canvas
	self.Results = results

	local resultLayout = Instance.new("UIListLayout")
	resultLayout.Name = "Layout"
	resultLayout.FillDirection = Enum.FillDirection.Vertical
	resultLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	resultLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resultLayout.Padding = UDim.new(0, 0)
	resultLayout.Parent = results
	self.ResultsLayout = resultLayout

	local footer = makeFrame("FooterRule", canvas)
	footer.Position = UDim2.fromOffset(40, 592)
	footer.Size = UDim2.fromOffset(528, 25)
	footer.ZIndex = 18
	self.FooterRule = footer
	local leftLine = makeFrame("Left", footer)
	leftLine.Position = UDim2.fromOffset(0, 12)
	leftLine.Size = UDim2.fromOffset(245, 1)
	leftLine.BackgroundColor3 = COLOR_GOLD
	leftLine.BackgroundTransparency = 0.35
	leftLine.ZIndex = 18
	local rightLine = makeFrame("Right", footer)
	rightLine.AnchorPoint = Vector2.new(1, 0)
	rightLine.Position = UDim2.new(1, 0, 0, 12)
	rightLine.Size = UDim2.fromOffset(245, 1)
	rightLine.BackgroundColor3 = COLOR_GOLD
	rightLine.BackgroundTransparency = 0.35
	rightLine.ZIndex = 18
	addPlainAsset(config, footer, "Crosshair", "Crosshair", Vector2.new(254, 0), Vector2.new(20, 20), 19, COLOR_GOLD)

	local hint = makeText("Hint", canvas, config.Fonts.Body, 18, Color3.fromRGB(102, 81, 61))
	hint.Position = UDim2.fromOffset(40, 622)
	hint.Size = UDim2.fromOffset(528, 48)
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Text = "Select a player to invite"
	hint.ZIndex = 18
	self.Hint = hint

	local leave = makeTextButton("LeaveAction", canvas, config.Fonts.Title, 19, COLOR_RED)
	leave.Position = UDim2.fromOffset(194, 680)
	leave.Size = UDim2.fromOffset(220, 38)
	leave.Text = "Leave squad"
	leave.Visible = false
	leave.ZIndex = 19
	self.LeaveButton = leave
end

function SquadView:_buildInvitation()
	local config = self.Config
	local layout = config.Layout.Invitation
	local outer = makeCanvasGroup("InvitationPanel", self.Gui)
	outer.Visible = false
	outer.ZIndex = 15
	self.InvitationPanel = outer

	local canvas = makeFrame("Canvas", outer)
	canvas.Size = UDim2.fromOffset(layout.CanvasSize.X, layout.CanvasSize.Y)
	canvas.ZIndex = 15
	self.InvitationCanvas = canvas

	local scale = Instance.new("UIScale")
	scale.Name = "LocalScale"
	scale.Scale = layout.LocalScale
	scale.Parent = canvas
	self.InvitationLocalScale = scale

	addBoundedAsset(config, canvas, "Background", "Invitation", 0, 0, 585, 15)
	-- Keep the supplied People asset in its original cream color on the orange ribbon.
	addBoundedAsset(config, canvas, "People", "People", 17, 27, 48, 17)

	local header = makeText("Header", canvas, config.Fonts.Body, 16, Color3.fromRGB(71, 53, 38))
	header.Position = UDim2.fromOffset(93, 30)
	header.Size = UDim2.fromOffset(320, 22)
	header.Text = "SQUAD INVITATION"
	header.ZIndex = 18
	self.InvitationHeader = header

	local expiry = makeText("Expiry", canvas, config.Fonts.Body, 16, Color3.fromRGB(71, 53, 38))
	expiry.Position = UDim2.fromOffset(438, 30)
	expiry.Size = UDim2.fromOffset(100, 22)
	expiry.Text = "30s"
	expiry.TextXAlignment = Enum.TextXAlignment.Right
	expiry.ZIndex = 18
	self.InvitationExpiry = expiry

	local sender = makeText("Sender", canvas, config.Fonts.Title, 38, Color3.fromRGB(57, 42, 28))
	sender.Position = UDim2.fromOffset(93, 70)
	sender.Size = UDim2.fromOffset(440, 48)
	sender.Text = ""
	sender.ZIndex = 18
	self.InvitationSender = sender

	local body = makeText("Body", canvas, config.Fonts.Body, 21, Color3.fromRGB(78, 62, 44))
	body.Position = UDim2.fromOffset(93, 115)
	body.Size = UDim2.fromOffset(440, 28)
	body.Text = "wants you to join their squad."
	body.ZIndex = 18
	self.InvitationBody = body

	local dividerLine = makeFrame("DividerLine", canvas)
	dividerLine.Position = UDim2.fromOffset(50, 164)
	dividerLine.Size = UDim2.fromOffset(395, 1)
	dividerLine.BackgroundColor3 = COLOR_GOLD
	dividerLine.BackgroundTransparency = 0.35
	dividerLine.ZIndex = 18
	addPlainAsset(config, canvas, "DividerCrosshair", "Crosshair", Vector2.new(454, 155), Vector2.new(18, 18), 19, COLOR_GOLD)

	local accept = createAssetButton(
		config,
		canvas,
		"Accept",
		"Primary",
		Vector2.new(50, 180),
		Vector2.new(232, 65),
		"Accept",
		Color3.fromRGB(255, 240, 213),
		27,
		18
	)
	self.AcceptButton = accept

	local decline = createAssetButton(
		config,
		canvas,
		"Decline",
		"Secondary",
		Vector2.new(300, 180),
		Vector2.new(232, 65),
		"Decline",
		Color3.fromRGB(41, 28, 18),
		27,
		18
	)
	self.DeclineButton = decline
end

function SquadView:_buildHUD()
	local config = self.Config
	local hud = makeFrame("SquadHUD", self.Gui)
	hud.Visible = false
	hud.ZIndex = 10
	self.SquadHUD = hud

	local canvas = makeFrame("Canvas", hud)
	canvas.Size = UDim2.fromOffset(266, 290)
	canvas.ZIndex = 10
	self.HUDCanvas = canvas
	local scale = Instance.new("UIScale")
	scale.Name = "ReferenceScale"
	scale.Scale = 1
	scale.Parent = canvas
	self.HUDScale = scale

	local heading = makeTextButton("Heading", canvas, config.Fonts.Title, 20, Color3.fromRGB(231, 223, 205))
	heading.Position = UDim2.fromOffset(0, 0)
	heading.Size = UDim2.fromOffset(266, 34)
	heading.Text = "SQUAD"
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.ZIndex = 11
	self.HUDHeading = heading

	local count = makeText("Count", heading, config.Fonts.Body, 10, Color3.fromRGB(194, 182, 160))
	count.Position = UDim2.fromOffset(69, 1)
	count.Size = UDim2.fromOffset(55, 30)
	count.Text = "0 / 4"
	count.ZIndex = 12
	self.HUDCount = count

	local chevron = makeText("Chevron", heading, config.Fonts.Title, 20, Color3.fromRGB(188, 162, 118))
	chevron.AnchorPoint = Vector2.new(1, 0)
	chevron.Position = UDim2.new(1, 0, 0, 0)
	chevron.Size = UDim2.fromOffset(24, 30)
	chevron.Text = "⌄"
	chevron.TextXAlignment = Enum.TextXAlignment.Right
	chevron.ZIndex = 12

	local line = makeFrame("HeadingLine", canvas)
	line.Position = UDim2.fromOffset(0, 33)
	line.Size = UDim2.fromOffset(266, 1)
	line.BackgroundColor3 = Color3.fromRGB(188, 162, 118)
	line.BackgroundTransparency = 0.53
	line.ZIndex = 11

	local rows = makeFrame("Members", canvas)
	rows.Position = UDim2.fromOffset(0, 34)
	rows.Size = UDim2.fromOffset(266, 256)
	rows.ZIndex = 10
	self.HUDMembers = rows
end

function SquadView:_buildMarkers()
	local host = makeFrame("AllyMarkers", self.Gui)
	host.Size = UDim2.fromScale(1, 1)
	host.Position = UDim2.fromScale(0, 0)
	host.ZIndex = 5
	host.Active = false
	self.AllyMarkers = host
end

function SquadView:_buildNotice()
	local config = self.Config
	local notice = makeCanvasGroup("SquadNotice", self.Gui)
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.BackgroundColor3 = COLOR_DARK
	notice.BackgroundTransparency = 0.21
	notice.BorderSizePixel = 0
	notice.GroupTransparency = 1
	notice.Visible = false
	notice.ZIndex = 30
	self.SquadNotice = notice

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = notice

	local text = makeText("Text", notice, config.Fonts.Body, 17, Color3.fromRGB(241, 230, 210))
	text.Size = UDim2.fromScale(1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextWrapped = true
	text.ZIndex = 31
	self.NoticeText = text
end

function SquadView:_getScale(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end
	return math.min(
		viewport.X / self.Config.ReferenceViewport.X,
		viewport.Y / self.Config.ReferenceViewport.Y
	)
end

function SquadView:_updatePlacement()
	if self.Destroyed then
		return
	end
	local scale = self:_getScale()
	self.Scale = scale
	local config = self.Config

	local social = config.Layout.Social
	self.SocialButton.Position = UDim2.fromOffset(social.Position.X * scale, social.Position.Y * scale)
	self.SocialButton.Size = UDim2.fromOffset(social.Size.X * scale, social.Size.Y * scale)
	self.SocialButton.TextSize = 15 * scale

	local menu = config.Layout.Menu
	local menuRight = config.ReferenceViewport.X - (menu.Position.X + menu.Size.X)
	self.Menu.Size = UDim2.fromOffset(menu.Size.X * scale, menu.Size.Y * scale)
	self.Menu.Position = UDim2.new(1, -((menuRight + menu.Size.X) * scale), 0, menu.Position.Y * scale)
	self.MenuBasePosition = self.Menu.Position
	self.MenuCanvas.Position = UDim2.fromOffset(0, 0)
	self.MenuLocalScale.Scale = menu.LocalScale * scale

	local invitation = config.Layout.Invitation
	local invitationBottom = config.ReferenceViewport.Y - (invitation.Position.Y + invitation.Size.Y)
	self.Invitation.Size = UDim2.fromOffset(invitation.Size.X * scale, invitation.Size.Y * scale)
	self.Invitation.Position = UDim2.new(0, invitation.Position.X * scale, 1, -((invitationBottom + invitation.Size.Y) * scale))
	self.InvitationBasePosition = self.Invitation.Position
	self.InvitationLocalScale.Scale = invitation.LocalScale * scale

	local hud = config.Layout.HUD
	self.SquadHUD.Position = UDim2.fromOffset(hud.Position.X * scale, hud.Position.Y * scale)
	self.SquadHUD.Size = UDim2.fromOffset(hud.Size.X * scale, hud.Size.Y * scale)
	self.HUDScale.Scale = scale

	self.SquadNotice.Position = UDim2.new(0.5, 0, 0, config.Layout.NoticeTop * scale)
	self.SquadNotice.Size = UDim2.fromOffset(550 * scale, 44 * scale)
	self.NoticeText.TextSize = math.max(10, 17 * scale)
end

function SquadView:_bindViewport()
	local cameraConnection: RBXScriptConnection? = nil
	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:_updatePlacement()
			end)
		end
		self:_updatePlacement()
	end

	table.insert(self.Connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
	bindCamera()
	self.CameraConnectionGetter = function()
		return cameraConnection
	end
end

function SquadView:SetReducedMotion(enabled: boolean)
	self.ReducedMotion = enabled
end

function SquadView:SetActiveTab(tab: string)
	local invite = tab == "invite"
	self.InviteTab.TextColor3 = if invite then COLOR_BROWN else COLOR_MUTED
	self.MembersTab.TextColor3 = if invite then COLOR_MUTED else COLOR_BROWN
	self.ActiveTabLine.Position = if invite
		then UDim2.fromOffset(0, 31)
		else UDim2.fromOffset(154, 31)
	self.ActiveTabLine.Size = if invite
		then UDim2.fromOffset(132, 2)
		else UDim2.fromOffset(100, 2)
	self.SectionTitle.Text = if invite then "Invite player" else "Squad members"
	self.SearchLabel.Visible = invite
	self.SearchArea.Visible = invite
	if invite then
		self.Results.Position = UDim2.fromOffset(40, 302)
		self.Results.Size = UDim2.fromOffset(528, 276)
		self.FooterRule.Position = UDim2.fromOffset(40, 592)
		self.Hint.Position = UDim2.fromOffset(40, 622)
		self.LeaveButton.Position = UDim2.fromOffset(194, 680)
	else
		self.Results.Position = UDim2.fromOffset(40, 214)
		self.Results.Size = UDim2.fromOffset(528, 350)
		self.FooterRule.Position = UDim2.fromOffset(40, 578)
		self.Hint.Position = UDim2.fromOffset(40, 608)
		self.LeaveButton.Position = UDim2.fromOffset(194, 664)
	end
end

function SquadView:SetHint(text: string)
	self.Hint.Text = text
end

function SquadView:SetLeaveVisible(visible: boolean)
	self.LeaveButton.Visible = visible
end

function SquadView:RenderResults(entries: {SearchEntry}, mode: string, callbacks: RowCallbacks, localUserId: number, leaderUserId: number?)
	for _, child in ipairs(self.Results:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local rowHeight = if mode == "members" then 87 else 92
	if #entries == 0 then
		local empty = makeText("Empty", self.Results, self.Config.Fonts.Body, 18, Color3.fromRGB(116, 99, 75))
		empty.Size = UDim2.new(1, -8, 0, 70)
		empty.Text = if mode == "members" then "You are not in a squad." else "No matching players."
		empty.TextYAlignment = Enum.TextYAlignment.Center
		empty.ZIndex = 19
		return
	end

	for index, entry in ipairs(entries) do
		local row = makeCanvasGroup("Player_" .. tostring(entry.UserId), self.Results)
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -5, 0, rowHeight)
		row.ZIndex = 19

		local top = makeFrame("TopRule", row)
		top.Size = UDim2.new(1, 0, 0, 1)
		top.BackgroundColor3 = Color3.fromRGB(161, 138, 98)
		top.BackgroundTransparency = 0.64
		top.ZIndex = 19

		local avatarSize = if mode == "members" then 60 else 72
		local avatar = makeFrame("Avatar", row)
		avatar.Position = UDim2.fromOffset(0, math.floor((rowHeight - avatarSize) * 0.5))
		avatar.Size = UDim2.fromOffset(avatarSize, avatarSize)
		avatar.BackgroundColor3 = Color3.fromRGB(157, 141, 112)
		avatar.BackgroundTransparency = 0.6
		avatar.ZIndex = 19
		addCorner(avatar, avatarSize)
		local peopleWidth = if mode == "members" then 42 else 49
		addBoundedAsset(
			self.Config,
			avatar,
			"People",
			"People",
			(avatarSize - peopleWidth) * 0.5,
			math.floor((avatarSize - peopleWidth * 621 / 853) * 0.5),
			peopleWidth,
			20
		)

		local info = makeFrame("Identity", row)
		info.Position = UDim2.fromOffset(avatarSize + 19, 0)
		info.Size = UDim2.new(1, -(avatarSize + 19 + 170), 1, 0)
		info.ZIndex = 19
		local name = makeText("Name", info, self.Config.Fonts.Title, 25, COLOR_BROWN)
		name.Position = UDim2.fromOffset(0, math.floor(rowHeight * 0.5) - 30)
		name.Size = UDim2.new(1, 0, 0, 34)
		name.Text = entry.characterName
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 20

		local secondary = makeText("Secondary", info, self.Config.Fonts.Body, 17, Color3.fromRGB(121, 104, 80))
		secondary.Position = UDim2.fromOffset(0, math.floor(rowHeight * 0.5) + 4)
		secondary.Size = UDim2.new(1, 0, 0, 24)
		if mode == "members" then
			if entry.UserId == leaderUserId then
				secondary.Text = if entry.UserId == localUserId then "Leader · You" else "Leader"
			elseif entry.UserId == localUserId then
				secondary.Text = "You"
			else
				secondary.Text = "Member"
			end
		else
			secondary.Text = "@" .. entry.username
		end
		secondary.TextTruncate = Enum.TextTruncate.AtEnd
		secondary.ZIndex = 20

		if mode == "invite" and callbacks.Invite then
			local button = createAssetButton(
				self.Config,
				row,
				"Invite",
				"Primary",
				Vector2.new(365, math.floor((rowHeight - 48) * 0.5)),
				Vector2.new(163, 48),
				"Invite",
				Color3.fromRGB(255, 240, 213),
				25,
				20
			)
			button.Activated:Connect(function()
				(callbacks.Invite :: (number) -> ())(entry.UserId)
			end)
		elseif mode == "members"
			and callbacks.Remove
			and localUserId == leaderUserId
			and entry.UserId ~= localUserId then
			-- Use the separately uploaded PrimaryAlt asset as requested, even though
			-- its original PNG is byte-identical to Primary.
			local button = createAssetButton(
				self.Config,
				row,
				"Remove",
				"PrimaryAlt",
				Vector2.new(365, math.floor((rowHeight - 48) * 0.5)),
				Vector2.new(163, 48),
				"Remove",
				Color3.fromRGB(255, 240, 213),
				25,
				20
			)
			button.Activated:Connect(function()
				(callbacks.Remove :: (number) -> ())(entry.UserId)
			end)
		end
	end
end

function SquadView:SetMenuOpen(open: boolean)
	self.MenuTransitionRevision += 1
	local revision = self.MenuTransitionRevision
	cancelTween(self.MenuTween)
	cancelTween(self.MenuFadeTween)

	local base = self.MenuBasePosition or self.Menu.Position
	local offsetEnter = self.Config.Animation.PanelEnterOffsetY * self.Scale
	local offsetExit = self.Config.Animation.PanelExitOffsetY * self.Scale

	if self.ReducedMotion then
		self.Menu.Position = base
		self.Menu.GroupTransparency = if open then 0 else 1
		self.Menu.Visible = open
		return
	end

	if open then
		local wasVisible = self.Menu.Visible
		self.Menu.Visible = true
		if not wasVisible then
			self.Menu.GroupTransparency = 1
			self.Menu.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + offsetEnter)
		end
		local duration = self.Config.Animation.PanelEnter
		self.MenuTween = TweenService:Create(self.Menu, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = base,
		})
		self.MenuFadeTween = TweenService:Create(self.Menu, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 0,
		})
		self.MenuTween:Play()
		self.MenuFadeTween:Play()
	else
		if not self.Menu.Visible then
			return
		end
		local target = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + offsetExit)
		local duration = self.Config.Animation.PanelExit
		self.MenuTween = TweenService:Create(self.Menu, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = target,
		})
		self.MenuFadeTween = TweenService:Create(self.Menu, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})
		self.MenuTween:Play()
		self.MenuFadeTween:Play()
		self.MenuFadeTween.Completed:Connect(function()
			if self.MenuTransitionRevision == revision then
				self.Menu.Visible = false
				self.Menu.Position = base
			end
		end)
	end
end

function SquadView:SetInvitationVisible(visible: boolean)
	self.InviteTransitionRevision += 1
	local revision = self.InviteTransitionRevision
	cancelTween(self.InviteTween)
	cancelTween(self.InviteFadeTween)

	local base = self.InvitationBasePosition or self.Invitation.Position
	local offsetEnter = self.Config.Animation.PanelEnterOffsetY * self.Scale
	local offsetExit = self.Config.Animation.PanelExitOffsetY * self.Scale

	if self.ReducedMotion then
		self.Invitation.Position = base
		self.Invitation.GroupTransparency = if visible then 0 else 1
		self.Invitation.Visible = visible
		return
	end

	if visible then
		local wasVisible = self.Invitation.Visible
		self.Invitation.Visible = true
		if not wasVisible then
			self.Invitation.GroupTransparency = 1
			self.Invitation.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + offsetEnter)
		end
		local duration = self.Config.Animation.PanelEnter
		self.InviteTween = TweenService:Create(self.Invitation, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = base})
		self.InviteFadeTween = TweenService:Create(self.Invitation, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0})
		self.InviteTween:Play()
		self.InviteFadeTween:Play()
	else
		if not self.Invitation.Visible then
			return
		end
		local target = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + offsetExit)
		local duration = self.Config.Animation.PanelExit
		self.InviteTween = TweenService:Create(self.Invitation, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = target})
		self.InviteFadeTween = TweenService:Create(self.Invitation, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {GroupTransparency = 1})
		self.InviteTween:Play()
		self.InviteFadeTween:Play()
		self.InviteFadeTween.Completed:Connect(function()
			if self.InviteTransitionRevision == revision then
				self.Invitation.Visible = false
				self.Invitation.Position = base
			end
		end)
	end
end

function SquadView:SetInvitationContent(senderName: string, seconds: number)
	self.InvitationSender.Text = senderName
	self.InvitationExpiry.Text = tostring(math.max(0, math.ceil(seconds))) .. "s"
end

function SquadView:ShowNotice(text: string)
	self.NoticeRevision += 1
	local revision = self.NoticeRevision
	cancelTween(self.NoticeTween)
	if self.NoticeTimer then
		task.cancel(self.NoticeTimer)
		self.NoticeTimer = nil
	end

	self.NoticeText.Text = text
	self.SquadNotice.Visible = true
	if self.ReducedMotion then
		self.SquadNotice.GroupTransparency = 0
		self.NoticeTimer = task.delay(self.Config.Animation.NoticeHold, function()
			if self.Destroyed or self.NoticeRevision ~= revision then
				return
			end
			self.SquadNotice.Visible = false
			self.SquadNotice.GroupTransparency = 1
			self.NoticeText.Text = ""
		end)
		return
	end
	self.SquadNotice.GroupTransparency = 1
	local enter = TweenService:Create(
		self.SquadNotice,
		TweenInfo.new(self.Config.Animation.NoticeEnter, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{GroupTransparency = 0}
	)
	self.NoticeTween = enter
	enter:Play()

	self.NoticeTimer = task.delay(self.Config.Animation.NoticeHold, function()
		if self.Destroyed or self.NoticeRevision ~= revision then
			return
		end
		local exit = TweenService:Create(
			self.SquadNotice,
			TweenInfo.new(self.Config.Animation.NoticeExit, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{GroupTransparency = 1}
		)
		self.NoticeTween = exit
		exit:Play()
		exit.Completed:Connect(function()
			if self.NoticeRevision == revision then
				self.SquadNotice.Visible = false
				self.NoticeText.Text = ""
			end
		end)
	end)
end

function SquadView:_createHUDRow(member: MemberData, localUserId: number): CanvasGroup
	local row = makeCanvasGroup("Member_" .. tostring(member.UserId), self.HUDMembers)
	row.Size = UDim2.fromOffset(266, 58)
	row.ZIndex = 11
	row.GroupTransparency = 1

	local color = identityColor(self.Config, member.identityKey)
	local background = makeFrame("Background", row)
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(18, 23, 25)
	background.BackgroundTransparency = 0.25
	background.ZIndex = 11
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.65, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = background

	local accent = makeFrame("Accent", row)
	accent.Size = UDim2.new(0, 2, 1, 0)
	accent.BackgroundColor3 = color
	accent.BackgroundTransparency = 0
	accent.ZIndex = 12

	local symbol = addPlainAsset(
		self.Config,
		row,
		"Symbol",
		member.identityKey,
		Vector2.new(10, 14),
		Vector2.new(27, 29),
		13,
		color
	)
	symbol.ScaleType = Enum.ScaleType.Fit

	local name = makeText("Name", row, self.Config.Fonts.Title, 18, Color3.fromRGB(231, 223, 205))
	name.Position = UDim2.fromOffset(49, 8)
	name.Size = UDim2.fromOffset(185, 25)
	name.Text = member.characterName
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 13
	name:SetAttribute("MemberName", true)

	if member.UserId == localUserId then
		local you = makeText("You", row, self.Config.Fonts.Body, 9, Color3.fromRGB(194, 182, 160))
		you.Position = UDim2.fromOffset(198, 10)
		you.Size = UDim2.fromOffset(40, 18)
		you.Text = "YOU"
		you.TextXAlignment = Enum.TextXAlignment.Right
		you.ZIndex = 13
	end

	local track = makeFrame("HealthTrack", row)
	track.Position = UDim2.fromOffset(49, 39)
	track.Size = UDim2.fromOffset(185, 5)
	track.BackgroundColor3 = Color3.fromRGB(10, 15, 16)
	track.BackgroundTransparency = 0.31
	track.ClipsDescendants = true
	track.ZIndex = 12
	addCorner(track, 2)

	local fill = makeFrame("Fill", track)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLOR_HEALTH_A
	fill.BackgroundTransparency = 0
	fill.ZIndex = 13
	local hpGradient = Instance.new("UIGradient")
	hpGradient.Color = ColorSequence.new(COLOR_HEALTH_A, COLOR_HEALTH_B)
	hpGradient.Parent = fill
	fill:SetAttribute("HealthFill", true)

	return row
end

function SquadView:UpdateHUD(members: {MemberData}, localUserId: number)
	self.CurrentMembers = members
	self.SquadHUD.Visible = #members > 0
	self.HUDCount.Text = tostring(#members) .. " / " .. tostring(self.Config.MaxMembers)

	local present: {[number]: boolean} = {}
	for index, member in ipairs(members) do
		present[member.UserId] = true
		local row = self.HUDRows[member.UserId]
		local targetY = (index - 1) * 64
		if not row then
			row = self:_createHUDRow(member, localUserId)
			self.HUDRows[member.UserId] = row
			if self.ReducedMotion then
				row.Position = UDim2.fromOffset(0, targetY)
				row.GroupTransparency = 0
			else
				row.Position = UDim2.fromOffset(-10, targetY)
				TweenService:Create(row, TweenInfo.new(self.Config.Animation.HUDRowEnter, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(0, targetY),
					GroupTransparency = 0,
				}):Play()
			end
		else
			local name = row:FindFirstChild("Name")
			if name and name:IsA("TextLabel") then
				name.Text = member.characterName
			end
			if math.abs(row.Position.Y.Offset - targetY) > 0.1 then
				if self.ReducedMotion then
					row.Position = UDim2.fromOffset(0, targetY)
				else
					TweenService:Create(row, TweenInfo.new(self.Config.Animation.HUDRowReflow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Position = UDim2.fromOffset(0, targetY),
					}):Play()
				end
			end
		end

		local track = row:FindFirstChild("HealthTrack")
		local fill = track and track:FindFirstChild("Fill")
		if fill and fill:IsA("Frame") then
			local ratio = 0
			if member.maxHealth > 0 then
				ratio = math.clamp(member.health / member.maxHealth, 0, 1)
			end
			if self.ReducedMotion then
				fill.Size = UDim2.fromScale(ratio, 1)
			else
				TweenService:Create(fill, TweenInfo.new(self.Config.Animation.HealthTween, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(ratio, 1),
				}):Play()
			end
		end
	end

	for userId, row in pairs(self.HUDRows) do
		if not present[userId] then
			self.HUDRows[userId] = nil
			if self.ReducedMotion then
				row:Destroy()
			else
				local tween = TweenService:Create(row, TweenInfo.new(self.Config.Animation.HUDRowRemove, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(row.Position.X.Scale, row.Position.X.Offset - 12, row.Position.Y.Scale, row.Position.Y.Offset),
					GroupTransparency = 1,
				})
				tween:Play()
				tween.Completed:Connect(function()
					if row.Parent then
						row:Destroy()
					end
				end)
			end
		end
	end
end

function SquadView:_ensureMarker(member: MemberData): Frame
	local existing = self.MarkerRows[member.UserId]
	if existing then
		return existing
	end

	local marker = makeFrame("Marker_" .. tostring(member.UserId), self.AllyMarkers)
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.Size = UDim2.fromOffset(50, 50)
	marker.ZIndex = 6
	local color = identityColor(self.Config, member.identityKey)
	local symbol = addPlainAsset(self.Config, marker, "Symbol", member.identityKey, Vector2.new(6, 4), Vector2.new(29, 32), 7, color)
	symbol.AnchorPoint = Vector2.new(0.5, 0.5)
	symbol.Position = UDim2.fromOffset(20, 20)

	local arrow = makeFrame("Arrow", marker)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromOffset(42, 21)
	arrow.Size = UDim2.fromOffset(14, 14)
	arrow.ZIndex = 7
	arrow.Visible = false
	local a = makeFrame("A", arrow)
	a.AnchorPoint = Vector2.new(1, 0)
	a.Position = UDim2.fromOffset(11, 3)
	a.Size = UDim2.fromOffset(8, 2)
	a.Rotation = 45
	a.BackgroundColor3 = color
	a.BackgroundTransparency = 0
	a.ZIndex = 8
	local b = makeFrame("B", arrow)
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.fromOffset(11, 11)
	b.Size = UDim2.fromOffset(8, 2)
	b.Rotation = -45
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0
	b.ZIndex = 8

	self.MarkerRows[member.UserId] = marker
	return marker
end

function SquadView:UpdateMarkers(members: {MemberData}, localUserId: number, playersByUserId: {[number]: Player})
	local camera = Workspace.CurrentCamera
	if not camera then
		for _, marker in pairs(self.MarkerRows) do
			marker.Visible = false
		end
		return
	end

	local viewport = camera.ViewportSize
	local margin = 45 * self.Scale
	local present: {[number]: boolean} = {}

	for _, member in ipairs(members) do
		if member.UserId ~= localUserId then
			present[member.UserId] = true
			local marker = self:_ensureMarker(member)
			local player = playersByUserId[member.UserId]
			local character = player and player.Character
			local head = character and character:FindFirstChild("Head")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local basePart = if head and head:IsA("BasePart") then head elseif root and root:IsA("BasePart") then root else nil

			if not basePart then
				marker.Visible = false
			else
				local worldPoint = basePart.Position + Vector3.new(0, if basePart == head then 1.7 else 3.5, 0)
				local projected, onScreen = camera:WorldToViewportPoint(worldPoint)
				local localPoint = camera.CFrame:PointToObjectSpace(worldPoint)
				local inFront = localPoint.Z < -0.05
				local screen = Vector2.new(projected.X, projected.Y)
				local within = inFront
					and onScreen
					and screen.X >= margin
					and screen.X <= viewport.X - margin
					and screen.Y >= margin
					and screen.Y <= viewport.Y - margin

				local arrow = marker:FindFirstChild("Arrow") :: Frame?
				if within then
					marker.Position = UDim2.fromOffset(screen.X, screen.Y)
					marker.Visible = true
					if arrow then
						arrow.Visible = false
					end
				else
					local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
					local direction: Vector2
					if inFront then
						direction = screen - center
					else
						-- Behind-camera targets must flip their projected direction so the
						-- edge arrow points toward the shortest camera turn.
						direction = Vector2.new(-localPoint.X, localPoint.Y)
					end
					if direction.Magnitude < 0.001 then
						direction = Vector2.new(0, 1)
					end
					direction = direction.Unit
					local half = Vector2.new(math.max(1, viewport.X * 0.5 - margin), math.max(1, viewport.Y * 0.5 - margin))
					local sx = if math.abs(direction.X) > 0.0001 then half.X / math.abs(direction.X) else math.huge
					local sy = if math.abs(direction.Y) > 0.0001 then half.Y / math.abs(direction.Y) else math.huge
					local distance = math.min(sx, sy)
					local clamped = center + direction * distance
					marker.Position = UDim2.fromOffset(clamped.X, clamped.Y)
					marker.Visible = true
					if arrow then
						arrow.Visible = true
						arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X))
					end
				end
			end
		end
	end

	for userId, marker in pairs(self.MarkerRows) do
		if not present[userId] then
			self.MarkerRows[userId] = nil
			marker:Destroy()
		end
	end
end

function SquadView:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	cancelTween(self.MenuTween)
	cancelTween(self.MenuFadeTween)
	cancelTween(self.InviteTween)
	cancelTween(self.InviteFadeTween)
	cancelTween(self.NoticeTween)
	if self.NoticeTimer then
		task.cancel(self.NoticeTimer)
		self.NoticeTimer = nil
	end
	if self.CameraConnectionGetter then
		local connection = self.CameraConnectionGetter()
		if connection then
			connection:Disconnect()
		end
	end
	for _, connection in ipairs(self.Connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	if self.Gui then
		self.Gui:Destroy()
	end
end

return SquadView
