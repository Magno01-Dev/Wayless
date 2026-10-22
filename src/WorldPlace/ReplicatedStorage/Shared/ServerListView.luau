--!strict
-- ReplicatedStorage > Shared > ServerListView
-- WAYLESS ServerList v1.1 candidate.
-- Visual authority: ServerList.zip > reference/assets/server_refined/index.html
-- No invented outer panel/background.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ServerListView = {}
ServerListView.__index = ServerListView

export type PlayerEntry = {
	UserId: number,
	CharacterName: string,
	Username: string,
	VillageKey: string,
	Rank: string,
}

export type View = typeof(setmetatable({} :: any, ServerListView))

local CREAM = Color3.fromRGB(231, 223, 205)
local MUTED = Color3.fromRGB(182, 170, 148)
local GOLD = Color3.fromRGB(188, 162, 118)
local CHARCOAL = Color3.fromRGB(22, 22, 22)

local function frame(name: string, parent: Instance): Frame
	local value = Instance.new("Frame")
	value.Name = name
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.Parent = parent
	return value
end

local function textLabel(
	name: string,
	parent: Instance,
	font: Font,
	size: number,
	color: Color3
): TextLabel
	local value = Instance.new("TextLabel")
	value.Name = name
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.FontFace = font
	value.Text = ""
	value.TextColor3 = color
	value.TextSize = size
	value.TextScaled = false
	value.TextWrapped = false
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextYAlignment = Enum.TextYAlignment.Center
	value.Parent = parent
	return value
end

local function textButton(
	name: string,
	parent: Instance,
	font: Font,
	size: number,
	color: Color3
): TextButton
	local value = Instance.new("TextButton")
	value.Name = name
	value.AutoButtonColor = false
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.FontFace = font
	value.Text = ""
	value.TextColor3 = color
	value.TextSize = size
	value.TextScaled = false
	value.Parent = parent
	return value
end

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function cancelTween(value: Tween?)
	if value then
		value:Cancel()
	end
end

local function plainImage(
	parent: Instance,
	name: string,
	imageId: string,
	position: UDim2,
	size: UDim2,
	zIndex: number,
	scaleType: Enum.ScaleType?
): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = imageId
	image.ImageTransparency = 0
	image.ScaleType = scaleType or Enum.ScaleType.Fit
	image.Position = position
	image.Size = size
	image.ZIndex = zIndex
	image.Parent = parent
	return image
end

local function makeLine(parent: Instance, name: string, position: UDim2, size: UDim2, transparency: number)
	local value = Instance.new("Frame")
	value.Name = name
	value.BackgroundColor3 = GOLD
	value.BackgroundTransparency = transparency
	value.BorderSizePixel = 0
	value.Position = position
	value.Size = size
	value.ZIndex = 22
	value.Parent = parent
	return value
end

function ServerListView.new(config: any, playerGui: PlayerGui): View
	local self = setmetatable({}, ServerListView)

	self.Config = config
	self.PlayerGui = playerGui
	self.Destroyed = false
	self.ReducedMotion = false
	self.Open = false
	self.Scale = 1

	self.Connections = {}
	self.CameraConnection = nil
	self.TransitionRevision = 0
	self.PanelTween = nil
	self.PanelFadeTween = nil

	self.Collapsed = {}
	self.Sections = {}
	self.Rows = {}
	self.RowConnections = {}
	self.RowData = {}
	self.LastEntries = {}
	self.SelectedUserId = nil
	self.InviteCallback = nil
	self.InviteReasonCallback = nil
	self.NewRows = {}
	self.MovedRows = {}

	local previous = playerGui:FindFirstChild("ServerList")
	if previous then
		previous:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ServerList"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 76
	gui.Parent = playerGui
	self.Gui = gui

	self:_buildAccessButton()
	self:_buildPanel()
	self:_bindViewport()
	self:_applyViewport()

	return self
end

function ServerListView:_buildAccessButton()
	local spec = self.Config.Layout.ServerButton
	local button = textButton("ServerButton", self.Gui, self.Config.Fonts.Body, 15, CREAM)
	button.Text = "Server"
	button.BackgroundColor3 = Color3.fromRGB(21, 27, 28)
	button.BackgroundTransparency = 0.21
	button.Position = UDim2.fromOffset(spec.Position.X, spec.Position.Y)
	button.Size = UDim2.fromOffset(spec.Size.X, spec.Size.Y)
	button.ZIndex = 30
	corner(button, 7)

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = Color3.fromRGB(48, 55, 51)
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Color3.fromRGB(21, 27, 28)
	end)

	self.ServerButton = button
end

function ServerListView:_buildPanel()
	local layout = self.Config.Layout

	local panel = Instance.new("CanvasGroup")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = false
	panel.Size = UDim2.fromOffset(layout.Width, layout.Height)
	panel.Visible = false
	panel.GroupTransparency = 1
	panel.ZIndex = 20
	panel.Parent = self.Gui
	self.Panel = panel

	-- Approved TitleBrush: full source PNG, uniform scale, alpha-offset compensated.
	local brush = plainImage(
		panel,
		"TitleBrush",
		self.Config.Assets.TitleBrush,
		UDim2.fromOffset(layout.TitleBrush.Position.X, layout.TitleBrush.Position.Y),
		UDim2.fromOffset(layout.TitleBrush.Size.X, layout.TitleBrush.Size.Y),
		20,
		Enum.ScaleType.Fit
	)
	brush.ImageTransparency = 0
	self.TitleBrush = brush

	local title = textLabel(
		"Title",
		panel,
		self.Config.Fonts.Title,
		layout.Title.FontSize,
		Color3.fromRGB(240, 228, 201)
	)
	title.Position = UDim2.fromOffset(layout.Title.Position.X, layout.Title.Position.Y)
	title.Size = UDim2.fromOffset(layout.Title.Size.X, layout.Title.Size.Y)
	title.Text = "Server"
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.55
	title.ZIndex = 24
	self.Title = title

	local countSpec = layout.PlayerCount
	local count = textLabel(
		"PlayerCount",
		panel,
		self.Config.Fonts.Body,
		countSpec.FontSize,
		MUTED
	)
	count.Position = UDim2.fromOffset(countSpec.Position.X, countSpec.Position.Y)
	count.Size = UDim2.fromOffset(countSpec.Size.X, countSpec.Size.Y)
	count.Text = "0 players"
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextTransparency = 0.2
	count.ZIndex = 24
	self.PlayerCount = count

	local closeSpec = layout.Close
	local close = textButton(
		"Close",
		panel,
		Font.fromEnum(Enum.Font.Arial),
		closeSpec.FontSize,
		GOLD
	)
	close.Position = UDim2.fromOffset(closeSpec.Position.X, closeSpec.Position.Y)
	close.Size = UDim2.fromOffset(closeSpec.Size.X, closeSpec.Size.Y)
	close.Text = "×"
	close.TextTransparency = 0.35
	close.ZIndex = 25
	close.MouseEnter:Connect(function()
		close.TextTransparency = 0
	end)
	close.MouseLeave:Connect(function()
		close.TextTransparency = 0.35
	end)
	self.CloseButton = close

	local dividerY = layout.DividerY
	local iconSize = layout.DividerIcon
	local iconX = (layout.Width - iconSize) * 0.5

	local leftLine = makeLine(
		panel,
		"DividerLeft",
		UDim2.fromOffset(12, dividerY + math.floor(iconSize * 0.5)),
		UDim2.fromOffset(iconX - 20, 1),
		0.45
	)
	self.DividerLeft = leftLine

	local rightLine = makeLine(
		panel,
		"DividerRight",
		UDim2.fromOffset(iconX + iconSize + 8, dividerY + math.floor(iconSize * 0.5)),
		UDim2.fromOffset(layout.Width - (iconX + iconSize + 20), 1),
		0.45
	)
	self.DividerRight = rightLine

	local dividerIcon = plainImage(
		panel,
		"Divider",
		self.Config.Assets.Divider,
		UDim2.fromOffset(iconX, dividerY),
		UDim2.fromOffset(iconSize, iconSize),
		23,
		Enum.ScaleType.Fit
	)
	dividerIcon.ImageColor3 = GOLD
	dividerIcon.ImageTransparency = 0.25

	local listSpec = layout.List
	local list = Instance.new("ScrollingFrame")
	list.Name = "VillageList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(listSpec.Position.X, listSpec.Position.Y)
	list.Size = UDim2.fromOffset(listSpec.Size.X, listSpec.Size.Y)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.CanvasPosition = Vector2.zero
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = GOLD
	list.ScrollBarImageTransparency = 0.62
	list.ClipsDescendants = true
	list.ZIndex = 21
	list.Parent = panel
	self.VillageList = list

	for _, village in ipairs(self.Config.Villages) do
		self:_createVillageSection(village)
	end

	local footSpec = layout.Footer
	local foot = textLabel(
		"Footer",
		panel,
		self.Config.Fonts.Body,
		footSpec.FontSize,
		MUTED
	)
	foot.Position = UDim2.fromOffset(footSpec.Position.X, footSpec.Position.Y)
	foot.Size = UDim2.fromOffset(footSpec.Size.X, footSpec.Size.Y)
	foot.Text = "Select a player · invite to squad"
	foot.TextXAlignment = Enum.TextXAlignment.Center
	foot.TextTransparency = 0.45
	foot.ZIndex = 23
	self.Footer = foot
end

function ServerListView:_createVillageSection(village: any)
	local width = self.Config.Layout.VillageWidth
	local headerHeight = self.Config.Layout.HeaderHeight

	local root = Instance.new("Frame")
	root.Name = "Village_" .. village.Key
	root.BackgroundColor3 = CHARCOAL
	root.BackgroundTransparency = 0.22
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Size = UDim2.fromOffset(width, headerHeight)
	root.ZIndex = 22
	root.Parent = self.VillageList

	-- Header button itself is transparent. Background + common frame are separate layers.
	local header = textButton("VillageHeader", root, self.Config.Fonts.Title, 17, CREAM)
	header.Size = UDim2.fromOffset(width, headerHeight)
	header.Text = ""
	header.ClipsDescendants = false
	header.ZIndex = 26

	local bgInset = self.Config.Layout.HeaderBackgroundInset
	local backgroundClip = frame("BackgroundClip", header)
	backgroundClip.Position = UDim2.fromOffset(bgInset.X, bgInset.Y)
	backgroundClip.Size = UDim2.fromOffset(width - bgInset.X * 2, headerHeight - bgInset.Y * 2)
	backgroundClip.ClipsDescendants = true
	backgroundClip.ZIndex = 23

	-- Roblox has no polygon clip-path. Keep the background inside the approved
	-- frame contour instead of stretching/flattening it into HeaderFrame.
	local background = plainImage(
		backgroundClip,
		"Background",
		self.Config.Assets[village.Background],
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 1),
		23,
		Enum.ScaleType.Crop
	)
	background.AnchorPoint = Vector2.zero

	local hf = self.Config.Layout.HeaderFrame
	plainImage(
		header,
		"HeaderFrame",
		self.Config.Assets.HeaderFrame,
		UDim2.fromOffset(hf.Position.X, hf.Position.Y),
		UDim2.fromOffset(hf.Size.X, hf.Size.Y),
		24,
		Enum.ScaleType.Fit
	)

	local logo = textLabel("VillageLogo", header, self.Config.Fonts.Body, 10, Color3.fromRGB(241, 229, 203))
	logo.Position = UDim2.fromOffset(10, 10)
	logo.Size = UDim2.fromOffset(23, 23)
	logo.Text = village.Letter
	logo.TextXAlignment = Enum.TextXAlignment.Center
	logo.BackgroundColor3 = Color3.fromRGB(17, 24, 32)
	logo.BackgroundTransparency = 0.46
	logo.ZIndex = 28
	corner(logo, 3)

	local logoStroke = Instance.new("UIStroke")
	logoStroke.Color = GOLD
	logoStroke.Transparency = 0.4
	logoStroke.Thickness = 1
	logoStroke.Parent = logo

	local villageName = textLabel("VillageName", header, self.Config.Fonts.Title, 17, Color3.fromRGB(245, 238, 219))
	villageName.Position = UDim2.fromOffset(42, 8)
	villageName.Size = UDim2.fromOffset(166, 28)
	villageName.Text = village.DisplayName
	villageName.TextStrokeColor3 = Color3.new(0, 0, 0)
	villageName.TextStrokeTransparency = 0.35
	villageName.ZIndex = 28

	local count = textLabel("Count", header, self.Config.Fonts.Body, 11, Color3.fromRGB(255, 241, 215))
	count.Position = UDim2.fromOffset(213, 10)
	count.Size = UDim2.fromOffset(40, 24)
	count.Text = "0"
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextStrokeColor3 = Color3.new(0, 0, 0)
	count.TextStrokeTransparency = 0.45
	count.ZIndex = 28

	local arrow = textLabel("Arrow", header, Font.fromEnum(Enum.Font.Arial), 15, Color3.fromRGB(255, 240, 215))
	arrow.Position = UDim2.fromOffset(256, 10)
	arrow.Size = UDim2.fromOffset(18, 23)
	arrow.Text = "⌄"
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.ZIndex = 28

	local content = frame("Content", root)
	content.Position = UDim2.fromOffset(0, headerHeight)
	content.Size = UDim2.fromOffset(width, 0)
	content.ClipsDescendants = true
	content.ZIndex = 23

	local lowerCloud = plainImage(
		content,
		"LowerCloud",
		self.Config.Assets.PlayerCloud,
		UDim2.new(1, 3, 1, 1),
		UDim2.fromOffset(126, 63),
		23,
		Enum.ScaleType.Fit
	)
	lowerCloud.AnchorPoint = Vector2.new(1, 1)
	lowerCloud.ImageTransparency = 0.76
	lowerCloud.Visible = false

	local upperCloud = plainImage(
		content,
		"UpperCloud",
		self.Config.Assets.PlayerCloud,
		UDim2.new(1, 2, 0, 15),
		UDim2.fromOffset(88, 44),
		23,
		Enum.ScaleType.Fit
	)
	upperCloud.AnchorPoint = Vector2.new(1, 0)
	upperCloud.ImageTransparency = 0.89
	upperCloud.Visible = false

	self.Sections[village.Key] = {
		Root = root,
		Header = header,
		Content = content,
		Count = count,
		Arrow = arrow,
		LowerCloud = lowerCloud,
		UpperCloud = upperCloud,
		Village = village,
	}

	table.insert(self.Connections, header.MouseEnter:Connect(function()
		background.ImageColor3 = Color3.fromRGB(255, 255, 255)
	end))
	table.insert(self.Connections, header.MouseLeave:Connect(function()
		background.ImageColor3 = Color3.fromRGB(245, 245, 245)
	end))
	table.insert(self.Connections, header.Activated:Connect(function()
		self:SetVillageCollapsed(village.Key, not self.Collapsed[village.Key])
	end))
end

function ServerListView:_disconnectRow(userId: number)
	local list = self.RowConnections[userId]
	if list then
		for _, connection in ipairs(list) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
	end
	self.RowConnections[userId] = nil
end

function ServerListView:_createPlayerRow(entry: PlayerEntry, villageKey: string): CanvasGroup
	local section = self.Sections[villageKey]
	local content = section.Content

	local item = Instance.new("CanvasGroup")
	item.Name = "PlayerRow_" .. tostring(entry.UserId)
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	item.ClipsDescendants = true
	item.Size = UDim2.fromOffset(self.Config.Layout.VillageWidth, self.Config.Layout.PlayerRowHeight)
	item.GroupTransparency = if self.ReducedMotion then 0 else 1
	item.ZIndex = 25
	item.Parent = content

	local selectButton = textButton("PlayerSelect", item, self.Config.Fonts.Body, 16, CREAM)
	selectButton.Position = UDim2.fromOffset(0, 0)
	selectButton.Size = UDim2.fromOffset(self.Config.Layout.VillageWidth, self.Config.Layout.PlayerRowHeight)
	selectButton.Text = ""
	selectButton.BackgroundTransparency = 1
	selectButton.ZIndex = 27

	local topRule = Instance.new("Frame")
	topRule.Name = "TopRule"
	topRule.BackgroundColor3 = GOLD
	topRule.BackgroundTransparency = 0.95
	topRule.BorderSizePixel = 0
	topRule.Position = UDim2.fromOffset(7, 0)
	topRule.Size = UDim2.new(1, -14, 0, 1)
	topRule.ZIndex = 25
	topRule.Parent = item

	local character = textLabel("CharacterName", item, self.Config.Fonts.Title, 16, CREAM)
	character.Position = UDim2.fromOffset(34, 4)
	character.Size = UDim2.fromOffset(200, 20)
	character.Text = entry.CharacterName
	character.TextTruncate = Enum.TextTruncate.AtEnd
	character.TextStrokeColor3 = Color3.new(0, 0, 0)
	character.TextStrokeTransparency = 0.55
	character.ZIndex = 26

	local you = textLabel("You", item, self.Config.Fonts.Body, 8, GOLD)
	you.Position = UDim2.fromOffset(236, 7)
	you.Size = UDim2.fromOffset(30, 15)
	you.Text = ""
	you.TextXAlignment = Enum.TextXAlignment.Right
	you.TextTransparency = 0.2
	you.ZIndex = 26

	local rank = textLabel("Rank", item, self.Config.Fonts.Body, 9, MUTED)
	rank.Position = UDim2.fromOffset(34, 23)
	rank.Size = UDim2.fromOffset(218, 14)
	rank.Text = entry.Rank
	rank.TextTruncate = Enum.TextTruncate.AtEnd
	rank.TextTransparency = 0.18
	rank.ZIndex = 26

	local chevron = textLabel("Chevron", item, Font.fromEnum(Enum.Font.Arial), 16, GOLD)
	chevron.Position = UDim2.fromOffset(258, 11)
	chevron.Size = UDim2.fromOffset(16, 20)
	chevron.Text = "›"
	chevron.TextXAlignment = Enum.TextXAlignment.Center
	chevron.TextTransparency = 1
	chevron.ZIndex = 27

	local action = textButton("InviteAction", item, self.Config.Fonts.Title, 12, CREAM)
	action.Position = UDim2.fromOffset(33, 47)
	action.Size = UDim2.fromOffset(213, 26)
	action.Text = "Invite to squad"
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
	action.BackgroundTransparency = 0.39
	action.BorderSizePixel = 0
	action.Visible = false
	action.ZIndex = 28
	corner(action, 2)

	local actionStroke = Instance.new("UIStroke")
	actionStroke.Name = "Stroke"
	actionStroke.Color = GOLD
	actionStroke.Transparency = 0.67
	actionStroke.Thickness = 1
	actionStroke.Parent = action

	self.Rows[entry.UserId] = item
	self.RowData[entry.UserId] = entry

	local bundle = {}
	self.RowConnections[entry.UserId] = bundle

	local hover = false
	local focused = false

	local function refreshName()
		local useUsername = hover or focused
		if useUsername then
			character.FontFace = self.Config.Fonts.Body
			character.TextSize = 12
			character.Text = "@" .. entry.Username
			character.TextColor3 = section.Village.Color
		else
			character.FontFace = self.Config.Fonts.Title
			character.TextSize = 16
			character.Text = entry.CharacterName
			character.TextColor3 = CREAM
		end
	end

	local function setHoverVisual(active: boolean)
		if active or self.SelectedUserId == entry.UserId then
			selectButton.BackgroundColor3 = section.Village.Color
			selectButton.BackgroundTransparency = 0.9
			chevron.TextTransparency = 0.35
		else
			selectButton.BackgroundTransparency = 1
			chevron.TextTransparency = 1
		end
	end

	table.insert(bundle, selectButton.MouseEnter:Connect(function()
		hover = true
		refreshName()
		setHoverVisual(true)
	end))
	table.insert(bundle, selectButton.MouseLeave:Connect(function()
		hover = false
		refreshName()
		setHoverVisual(false)
	end))
	table.insert(bundle, selectButton.SelectionGained:Connect(function()
		focused = true
		refreshName()
		setHoverVisual(true)
	end))
	table.insert(bundle, selectButton.SelectionLost:Connect(function()
		focused = false
		refreshName()
		setHoverVisual(false)
	end))
	table.insert(bundle, selectButton.Activated:Connect(function()
		self.SelectedUserId = if self.SelectedUserId == entry.UserId then nil else entry.UserId
		self:_refreshSelection()
		self:_layout(true)
	end))
	table.insert(bundle, action.Activated:Connect(function()
		if self.InviteCallback then
			self.InviteCallback(entry.UserId)
		end
	end))
	table.insert(bundle, action.MouseEnter:Connect(function()
		if action.Active then
			action.BackgroundTransparency = 0.15
			actionStroke.Transparency = 0
		end
	end))
	table.insert(bundle, action.MouseLeave:Connect(function()
		action.BackgroundTransparency = 0.39
		actionStroke.Transparency = 0.67
	end))

	return item
end

function ServerListView:_updateRow(userId: number, entry: PlayerEntry)
	local row = self.Rows[userId]
	if not row then
		return
	end

	self.RowData[userId] = entry

	local character = row:FindFirstChild("CharacterName") :: TextLabel?
	local rank = row:FindFirstChild("Rank") :: TextLabel?
	local you = row:FindFirstChild("You") :: TextLabel?

	if character and character.Text:sub(1, 1) ~= "@" then
		character.Text = entry.CharacterName
	end
	if rank then
		rank.Text = entry.Rank
	end
	if you then
		you.Text = if userId == self.LocalUserId then "YOU" else ""
	end
end

function ServerListView:_destroyRow(userId: number)
	local row = self.Rows[userId]
	if not row then
		return
	end

	self.Rows[userId] = nil
	self.RowData[userId] = nil
	self:_disconnectRow(userId)

	if self.SelectedUserId == userId then
		self.SelectedUserId = nil
	end

	if self.ReducedMotion then
		row:Destroy()
		return
	end

	local tween = TweenService:Create(
		row,
		TweenInfo.new(self.Config.Animation.Leave, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			GroupTransparency = 1,
			Position = UDim2.new(
				row.Position.X.Scale,
				row.Position.X.Offset + 12,
				row.Position.Y.Scale,
				row.Position.Y.Offset
			),
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		if row.Parent then
			row:Destroy()
		end
	end)
end

function ServerListView:SetLocalUserId(userId: number)
	self.LocalUserId = userId
	for rowUserId in pairs(self.Rows) do
		local data = self.RowData[rowUserId]
		if data then
			self:_updateRow(rowUserId, data)
		end
	end
end

function ServerListView:SetInvitationAdapter(
	inviteCallback: (number) -> (),
	reasonCallback: (number) -> string
)
	self.InviteCallback = inviteCallback
	self.InviteReasonCallback = reasonCallback
	self:_refreshSelection()
end

function ServerListView:_refreshSelection()
	for userId, row in pairs(self.Rows) do
		local selected = self.SelectedUserId == userId
		local selectButton = row:FindFirstChild("PlayerSelect") :: TextButton?
		local chevron = row:FindFirstChild("Chevron") :: TextLabel?
		local action = row:FindFirstChild("InviteAction") :: TextButton?

		if selectButton then
			selectButton.BackgroundTransparency = if selected then 0.9 else 1
		end
		if chevron then
			chevron.TextTransparency = if selected then 0.35 else 1
		end

		if action then
			action.Visible = selected
			if selected and self.InviteReasonCallback then
				local reason = self.InviteReasonCallback(userId)
				local available = reason == ""
				action.Text = if available then "Invite to squad" else reason
				action.Active = available
				action.TextTransparency = if available then 0 else 0.35
			end
		end
	end
end

function ServerListView:SetVillageCollapsed(villageKey: string, collapsed: boolean)
	if self.Collapsed[villageKey] == collapsed then
		return
	end

	self.Collapsed[villageKey] = collapsed
	local section = self.Sections[villageKey]
	if section then
		section.Arrow.Text = if collapsed then "›" else "⌄"
	end

	self:_layout(true, self.Config.Animation.Collapse)
end

function ServerListView:UpdateRoster(entries: {PlayerEntry})
	local oldScroll = self.VillageList.CanvasPosition
	local incoming: {[number]: PlayerEntry} = {}

	for _, entry in ipairs(entries) do
		incoming[entry.UserId] = entry

		local existing = self.Rows[entry.UserId]
		local oldData = self.RowData[entry.UserId]
		if not existing then
			self:_createPlayerRow(entry, entry.VillageKey)
			self.NewRows[entry.UserId] = true
		elseif oldData and oldData.VillageKey ~= entry.VillageKey then
			local row = existing
			row.Parent = self.Sections[entry.VillageKey].Content
			self.MovedRows[entry.UserId] = true
		end

		self:_updateRow(entry.UserId, entry)
	end

	for userId in pairs(self.Rows) do
		if not incoming[userId] then
			self:_destroyRow(userId)
		end
	end

	self.LastEntries = entries
	self.PlayerCount.Text = tostring(#entries) .. (if #entries == 1 then " player" else " players")

	for _, village in ipairs(self.Config.Villages) do
		local section = self.Sections[village.Key]
		local count = 0
		for _, entry in ipairs(entries) do
			if entry.VillageKey == village.Key then
				count += 1
			end
		end

		section.Count.Text = tostring(count)
		section.LowerCloud.Visible = count >= 1
		section.UpperCloud.Visible = count >= 3

		if count == 1 then
			section.LowerCloud.Size = UDim2.fromOffset(94, 47)
			section.LowerCloud.ImageTransparency = 0.82
		else
			section.LowerCloud.Size = UDim2.fromOffset(126, 63)
			section.LowerCloud.ImageTransparency = 0.76
		end
	end

	self:_refreshSelection()
	self:_layout(true)

	task.defer(function()
		if self.Destroyed then
			return
		end

		local maxY = math.max(
			0,
			self.VillageList.AbsoluteCanvasSize.Y - self.VillageList.AbsoluteWindowSize.Y
		)
		self.VillageList.CanvasPosition =
			Vector2.new(0, math.clamp(oldScroll.Y, 0, maxY))
	end)
end

function ServerListView:_layout(animated: boolean, overrideDuration: number?)
	local width = self.Config.Layout.VillageWidth
	local headerHeight = self.Config.Layout.HeaderHeight
	local baseRowHeight = self.Config.Layout.PlayerRowHeight
	local extra = self.Config.Layout.PlayerActionExtraHeight
	local gap = self.Config.Layout.VillageGap
	local y = 0

	for _, village in ipairs(self.Config.Villages) do
		local section = self.Sections[village.Key]
		local collapsed = self.Collapsed[village.Key] == true

		local rows = {}
		for _, entry in ipairs(self.LastEntries) do
			if entry.VillageKey == village.Key then
				table.insert(rows, entry)
			end
		end

		table.sort(rows, function(a, b)
			local aName = string.lower(a.CharacterName)
			local bName = string.lower(b.CharacterName)
			if aName == bName then
				return string.lower(a.Username) < string.lower(b.Username)
			end
			return aName < bName
		end)

		local contentHeight = 0
		if not collapsed then
			for _, entry in ipairs(rows) do
				contentHeight += baseRowHeight
					+ (if self.SelectedUserId == entry.UserId then extra else 0)
			end
		end

		local sectionHeight = headerHeight + contentHeight
		local duration = overrideDuration or self.Config.Animation.Reflow
		local sectionTweenInfo =
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		if animated and not self.ReducedMotion then
			TweenService:Create(
				section.Root,
				sectionTweenInfo,
				{
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.fromOffset(width, sectionHeight),
				}
			):Play()

			TweenService:Create(
				section.Content,
				sectionTweenInfo,
				{Size = UDim2.fromOffset(width, contentHeight)}
			):Play()
		else
			section.Root.Position = UDim2.fromOffset(0, y)
			section.Root.Size = UDim2.fromOffset(width, sectionHeight)
			section.Content.Size = UDim2.fromOffset(width, contentHeight)
		end

		local rowY = 0
		for _, entry in ipairs(rows) do
			local row = self.Rows[entry.UserId]
			if row then
				local selected = self.SelectedUserId == entry.UserId
				local rowHeight = baseRowHeight + (if selected then extra else 0)
				row.Visible = not collapsed

				if not collapsed then
					local targetPosition = UDim2.fromOffset(0, rowY)
					local tweenDuration = duration

					if self.NewRows[entry.UserId] then
						tweenDuration = self.Config.Animation.Join
					elseif self.MovedRows[entry.UserId] then
						tweenDuration = self.Config.Animation.ChangeVillage
					end

					if animated and not self.ReducedMotion then
						if self.NewRows[entry.UserId] then
							row.Position = UDim2.fromOffset(8, rowY)
							row.GroupTransparency = 1
						elseif self.MovedRows[entry.UserId] then
							row.Position = UDim2.fromOffset(8, rowY)
						end

						TweenService:Create(
							row,
							TweenInfo.new(
								tweenDuration,
								Enum.EasingStyle.Quad,
								Enum.EasingDirection.Out
							),
							{
								Position = targetPosition,
								Size = UDim2.fromOffset(width, rowHeight),
								GroupTransparency = 0,
							}
						):Play()
					else
						row.Position = targetPosition
						row.Size = UDim2.fromOffset(width, rowHeight)
						row.GroupTransparency = 0
					end

					local selectButton =
						row:FindFirstChild("PlayerSelect") :: TextButton?
					if selectButton then
						selectButton.Size =
							UDim2.fromOffset(width, baseRowHeight)
					end

					rowY += rowHeight
				end
			end
		end

		y += sectionHeight + gap
	end

	y = math.max(0, y - gap)
	self.VillageList.CanvasSize = UDim2.fromOffset(0, y)
	table.clear(self.NewRows)
	table.clear(self.MovedRows)
end

function ServerListView:SetOpen(open: boolean)
	self.Open = open
	self.TransitionRevision += 1
	local revision = self.TransitionRevision

	cancelTween(self.PanelTween)
	cancelTween(self.PanelFadeTween)

	if self.ReducedMotion then
		self.Panel.Visible = open
		self.Panel.GroupTransparency = if open then 0 else 1
		self:_applyViewport()
		return
	end

	if open then
		self.Panel.Visible = true
		self:_applyViewport()

		local finalPosition = self.Panel.Position
		self.Panel.Position = UDim2.new(
			finalPosition.X.Scale,
			finalPosition.X.Offset + 8,
			finalPosition.Y.Scale,
			finalPosition.Y.Offset
		)
		self.Panel.GroupTransparency = 1

		self.PanelTween = TweenService:Create(
			self.Panel,
			TweenInfo.new(
				self.Config.Animation.Open,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{Position = finalPosition}
		)
		self.PanelFadeTween = TweenService:Create(
			self.Panel,
			TweenInfo.new(
				self.Config.Animation.Open,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{GroupTransparency = 0}
		)

		self.PanelTween:Play()
		self.PanelFadeTween:Play()
	else
		self.PanelTween = TweenService:Create(
			self.Panel,
			TweenInfo.new(
				self.Config.Animation.Close,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			),
			{
				Position = UDim2.new(
					self.Panel.Position.X.Scale,
					self.Panel.Position.X.Offset + 6,
					self.Panel.Position.Y.Scale,
					self.Panel.Position.Y.Offset
				),
			}
		)
		self.PanelFadeTween = TweenService:Create(
			self.Panel,
			TweenInfo.new(
				self.Config.Animation.Close,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			),
			{GroupTransparency = 1}
		)

		self.PanelTween:Play()
		self.PanelFadeTween:Play()
		self.PanelFadeTween.Completed:Connect(function()
			if not self.Destroyed
				and self.TransitionRevision == revision
				and not self.Open then

				self.Panel.Visible = false
			end
		end)
	end
end

function ServerListView:SetReducedMotion(enabled: boolean)
	self.ReducedMotion = enabled

	if enabled then
		cancelTween(self.PanelTween)
		cancelTween(self.PanelFadeTween)
		self.Panel.Visible = self.Open
		self.Panel.GroupTransparency = if self.Open then 0 else 1
		self:_applyViewport()
		self:_layout(false)
	end
end

function ServerListView:_applyViewport()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	local reference = self.Config.ReferenceViewport
	local scale = math.min(viewport.X / reference.X, viewport.Y / reference.Y)
	self.Scale = scale

	local buttonSpec = self.Config.Layout.ServerButton
	self.ServerButton.Position =
		UDim2.fromOffset(
			buttonSpec.Position.X * scale,
			buttonSpec.Position.Y * scale
		)
	self.ServerButton.Size =
		UDim2.fromOffset(
			buttonSpec.Size.X * scale,
			buttonSpec.Size.Y * scale
		)

	self.Panel.Position =
		UDim2.new(
			1,
			-self.Config.Layout.Right * scale,
			0,
			self.Config.Layout.Top * scale
		)

	local uniformScale = self.Panel:FindFirstChild("UniformScale") :: UIScale?
	if not uniformScale then
		uniformScale = Instance.new("UIScale")
		uniformScale.Name = "UniformScale"
		uniformScale.Parent = self.Panel
	end
	uniformScale.Scale = scale
end

function ServerListView:_bindViewport()
	local function bindCamera(camera: Camera?)
		if self.CameraConnection then
			self.CameraConnection:Disconnect()
			self.CameraConnection = nil
		end

		if camera then
			self.CameraConnection =
				camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					self:_applyViewport()
				end)
		end

		self:_applyViewport()
	end

	bindCamera(Workspace.CurrentCamera)

	table.insert(
		self.Connections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindCamera(Workspace.CurrentCamera)
		end)
	)
end

function ServerListView:RefreshSelection()
	self:_refreshSelection()
end

function ServerListView:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	cancelTween(self.PanelTween)
	cancelTween(self.PanelFadeTween)

	if self.CameraConnection and self.CameraConnection.Connected then
		self.CameraConnection:Disconnect()
	end
	self.CameraConnection = nil

	for userId in pairs(self.RowConnections) do
		self:_disconnectRow(userId)
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

return ServerListView
