--!strict
-- ReplicatedStorage > Shared > ServerListView
-- WAYLESS ServerList v1 candidate — presentation defined by Astra ServerList.zip.

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

local DARK = Color3.fromRGB(18, 23, 25)
local CREAM = Color3.fromRGB(238, 226, 198)
local MUTED = Color3.fromRGB(194, 182, 160)
local GOLD = Color3.fromRGB(188, 162, 118)

local function makeFrame(name: string, parent: Instance): Frame
	local value = Instance.new("Frame")
	value.Name = name
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.Parent = parent
	return value
end

local function makeText(name: string, parent: Instance, font: Font, size: number, color: Color3): TextLabel
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

local function makeButton(name: string, parent: Instance, font: Font, size: number, color: Color3): TextButton
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

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function cancelTween(value: Tween?)
	if value then
		value:Cancel()
	end
end

local function addBoundedAsset(config: any, parent: Instance, name: string, key: string, visiblePosition: Vector2, visibleWidth: number, zIndex: number): ImageLabel
	local meta = config.AssetMeta[key]
	local bounds = meta.Bounds
	local scale = visibleWidth / bounds[3]

	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = config.Assets[key]
	image.ImageTransparency = 0
	image.ScaleType = Enum.ScaleType.Stretch
	image.Position = UDim2.fromOffset(
		visiblePosition.X - bounds[1] * scale,
		visiblePosition.Y - bounds[2] * scale
	)
	image.Size = UDim2.fromOffset(meta.Canvas.X * scale, meta.Canvas.Y * scale)
	image.ZIndex = zIndex
	image.Parent = parent
	return image
end

local function addPlainImage(parent: Instance, name: string, imageId: string, position: UDim2, size: UDim2, zIndex: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = imageId
	image.ImageTransparency = 0
	image.ScaleType = Enum.ScaleType.Fit
	image.Position = position
	image.Size = size
	image.ZIndex = zIndex
	image.Parent = parent
	return image
end

function ServerListView.new(config: any, playerGui: PlayerGui): View
	local self = setmetatable({}, ServerListView)
	self.Config = config
	self.PlayerGui = playerGui
	self.Destroyed = false
	self.ReducedMotion = false
	self.Scale = 1
	self.Open = false
	self.TransitionRevision = 0
	self.PanelTween = nil
	self.PanelFadeTween = nil
	self.CameraConnection = nil
	self.Connections = {}
	self.Collapsed = {}
	self.Sections = {}
	self.Rows = {}
	self.RowVillage = {}
	self.SelectedUserId = nil
	self.InviteCallback = nil
	self.InviteReasonCallback = nil
	self.LastEntries = {}
	self.RowConnections = {}
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

	self:_buildButton()
	self:_buildPanel()
	self:_bindViewport()
	self:_applyViewport()

	return self
end

function ServerListView:_buildButton()
	local layout = self.Config.Layout.ServerButton
	local button = makeButton("ServerButton", self.Gui, self.Config.Fonts.Body, 15, CREAM)
	button.Text = "Server"
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.BackgroundColor3 = Color3.fromRGB(21, 27, 28)
	button.BackgroundTransparency = 0.21
	button.Position = UDim2.fromOffset(layout.Position.X, layout.Position.Y)
	button.Size = UDim2.fromOffset(layout.Size.X, layout.Size.Y)
	button.ZIndex = 30
	addCorner(button, 7)

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
	panel.Size = UDim2.fromOffset(layout.Width, layout.Height)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Visible = false
	panel.GroupTransparency = 1
	panel.ZIndex = 20
	addCorner(panel, 8)
	self.Panel = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(112, 96, 73)
	stroke.Transparency = 0.52
	stroke.Thickness = 1
	stroke.Parent = panel

	local brushHost = makeFrame("TitleBrushHost", panel)
	brushHost.Position = UDim2.fromOffset(14, 6)
	brushHost.Size = UDim2.fromOffset(205, 52)
	brushHost.ClipsDescendants = true
	brushHost.ZIndex = 21

	addBoundedAsset(self.Config, brushHost, "TitleBrush", "TitleBrush", Vector2.new(4, 7), layout.TitleBrushVisibleWidth, 21)

	local title = makeText("Title", panel, self.Config.Fonts.Title, 24, CREAM)
	title.Position = UDim2.fromOffset(22, 11)
	title.Size = UDim2.fromOffset(185, 33)
	title.Text = "Server"
	title.ZIndex = 23

	local count = makeText("PlayerCount", panel, self.Config.Fonts.Body, 11, MUTED)
	count.Position = UDim2.fromOffset(190, 18)
	count.Size = UDim2.fromOffset(91, 22)
	count.Text = "0 players"
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = 23
	self.PlayerCount = count

	local topDivider = addPlainImage(panel, "TopDivider", self.Config.Assets.Divider, UDim2.fromOffset(18, 53), UDim2.fromOffset(270, 4), 22)
	topDivider.ImageTransparency = 0.62

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "VillageList"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(layout.PaddingX, 66)
	scroll.Size = UDim2.fromOffset(layout.Width - layout.PaddingX * 2, layout.ScrollAreaHeight)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.CanvasPosition = Vector2.zero
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Color3.fromRGB(158, 137, 105)
	scroll.ScrollBarImageTransparency = 0.28
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ClipsDescendants = true
	scroll.ZIndex = 22
	scroll.Parent = panel
	self.VillageList = scroll

	for _, village in ipairs(self.Config.Villages) do
		self:_createVillageSection(village)
	end

	panel.Parent = self.Gui
end

function ServerListView:_createVillageSection(village: any)
	local section = makeFrame("Village_" .. village.Key, self.VillageList)
	section.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, self.Config.Layout.VillageHeaderHeight)
	section.ZIndex = 23

	local header = makeButton("VillageHeader", section, self.Config.Fonts.Title, 17, CREAM)
	header.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, self.Config.Layout.VillageHeaderHeight)
	header.Text = ""
	header.ClipsDescendants = true
	header.ZIndex = 23

	local background = Instance.new("ImageLabel")
	background.Name = "Background"
	background.BackgroundTransparency = 1
	background.BorderSizePixel = 0
	background.Image = self.Config.Assets[village.Background]
	background.ScaleType = Enum.ScaleType.Crop
	background.Position = UDim2.fromOffset(3, 4)
	background.Size = UDim2.new(1, -6, 1, -8)
	background.ZIndex = 23
	background.Parent = header

	addBoundedAsset(self.Config, header, "HeaderFrame", "HeaderFrame", Vector2.new(0, 0), self.Config.Layout.VillageHeaderWidth, 24)

	local logo = makeText("VillageLogo", header, self.Config.Fonts.Title, 16, village.Color)
	logo.Position = UDim2.fromOffset(13, 10)
	logo.Size = UDim2.fromOffset(23, 23)
	logo.Text = village.Letter
	logo.TextXAlignment = Enum.TextXAlignment.Center
	logo.ZIndex = 26

	local name = makeText("VillageName", header, self.Config.Fonts.Title, 17, CREAM)
	name.Position = UDim2.fromOffset(46, 8)
	name.Size = UDim2.fromOffset(150, 27)
	name.Text = village.DisplayName
	name.ZIndex = 26

	local count = makeText("Count", header, self.Config.Fonts.Body, 11, MUTED)
	count.Position = UDim2.fromOffset(205, 11)
	count.Size = UDim2.fromOffset(44, 22)
	count.Text = "0"
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = 26

	local arrow = makeText("Arrow", header, Font.fromEnum(Enum.Font.Arial), 17, CREAM)
	arrow.Position = UDim2.fromOffset(251, 9)
	arrow.Size = UDim2.fromOffset(21, 24)
	arrow.Text = "⌄"
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.ZIndex = 26

	local content = makeFrame("Content", section)
	content.Position = UDim2.fromOffset(0, self.Config.Layout.VillageHeaderHeight)
	content.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, 0)
	content.ClipsDescendants = true
	content.ZIndex = 22

	local cloudLower = addPlainImage(content, "CloudLower", self.Config.Assets.PlayerCloud, UDim2.new(1, 3, 1, 1), UDim2.fromOffset(126, 63), 22)
	cloudLower.AnchorPoint = Vector2.new(1, 1)
	cloudLower.ImageTransparency = 0.76
	cloudLower.Visible = false

	local cloudUpper = addPlainImage(content, "CloudUpper", self.Config.Assets.PlayerCloud, UDim2.new(1, 2, 0, 15), UDim2.fromOffset(88, 44), 22)
	cloudUpper.AnchorPoint = Vector2.new(1, 0)
	cloudUpper.ImageTransparency = 0.89
	cloudUpper.Visible = false

	self.Sections[village.Key] = {
		Root = section,
		Header = header,
		Content = content,
		Count = count,
		Arrow = arrow,
		CloudLower = cloudLower,
		CloudUpper = cloudUpper,
	}

	table.insert(self.Connections, header.Activated:Connect(function()
		self:SetVillageCollapsed(village.Key, not self.Collapsed[village.Key])
	end))
end

function ServerListView:_createPlayerRow(entry: PlayerEntry): CanvasGroup
	local row = Instance.new("CanvasGroup")
	row.Name = "PlayerRow_" .. tostring(entry.UserId)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, self.Config.Layout.PlayerRowHeight)
	row.ClipsDescendants = true
	row.GroupTransparency = if self.ReducedMotion then 0 else 1
	row.ZIndex = 25
	row.Parent = self.VillageList

	local background = makeFrame("Background", row)
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = DARK
	background.BackgroundTransparency = 0.19
	background.ZIndex = 23
	addCorner(background, 4)

	local cloud = addPlainImage(row, "RowCloud", self.Config.Assets.PlayerCloud, UDim2.new(1, 2, 0.5, 0), UDim2.fromOffset(94, 47), 24)
	cloud.AnchorPoint = Vector2.new(1, 0.5)
	cloud.ImageTransparency = 0.82

	local selectButton = makeButton("PlayerSelect", row, self.Config.Fonts.Body, 16, CREAM)
	selectButton.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, self.Config.Layout.PlayerRowHeight)
	selectButton.Text = ""
	selectButton.ZIndex = 27

	local name = makeText("CharacterName", row, self.Config.Fonts.Body, 16, CREAM)
	name.Position = UDim2.fromOffset(34, 4)
	name.Size = UDim2.fromOffset(184, 22)
	name.Text = entry.CharacterName
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 26

	local username = makeText("Username", row, self.Config.Fonts.Body, 12, MUTED)
	username.Position = UDim2.fromOffset(34, 23)
	username.Size = UDim2.fromOffset(184, 17)
	username.Text = "@" .. entry.Username
	username.TextTruncate = Enum.TextTruncate.AtEnd
	username.ZIndex = 26

	local rank = makeText("Rank", row, self.Config.Fonts.Body, 9, MUTED)
	rank.Position = UDim2.fromOffset(218, 12)
	rank.Size = UDim2.fromOffset(50, 16)
	rank.Text = entry.Rank
	rank.TextTruncate = Enum.TextTruncate.AtEnd
	rank.TextXAlignment = Enum.TextXAlignment.Right
	rank.ZIndex = 26

	local divider = addPlainImage(row, "Divider", self.Config.Assets.Divider, UDim2.new(0, 22, 1, -2), UDim2.fromOffset(240, 3), 24)
	divider.ImageTransparency = 0.72

	local invite = makeButton("InviteAction", row, self.Config.Fonts.Title, 12, CREAM)
	invite.Position = UDim2.fromOffset(34, 45)
	invite.Size = UDim2.fromOffset(218, 22)
	invite.Text = "Invite to squad"
	invite.TextXAlignment = Enum.TextXAlignment.Left
	invite.Visible = false
	invite.ZIndex = 28

	self.Rows[entry.UserId] = row
	local bundle = {}
	self.RowConnections[entry.UserId] = bundle

	local showingUsername = false
	local function refreshName()
		if showingUsername then
			name.Text = "@" .. entry.Username
			username.Text = ""
		else
			name.Text = entry.CharacterName
			username.Text = "@" .. entry.Username
		end
	end

	table.insert(bundle, selectButton.MouseEnter:Connect(function()
		showingUsername = true
		refreshName()
	end))
	table.insert(bundle, selectButton.MouseLeave:Connect(function()
		showingUsername = false
		refreshName()
	end))
	table.insert(bundle, selectButton.SelectionGained:Connect(function()
		showingUsername = true
		refreshName()
	end))
	table.insert(bundle, selectButton.SelectionLost:Connect(function()
		showingUsername = false
		refreshName()
	end))
	table.insert(bundle, selectButton.Activated:Connect(function()
		self.SelectedUserId = if self.SelectedUserId == entry.UserId then nil else entry.UserId
		self:_refreshSelection()
		self:_layout(true)
	end))
	table.insert(bundle, invite.Activated:Connect(function()
		if self.InviteCallback then
			self.InviteCallback(entry.UserId)
		end
	end))

	return row
end

function ServerListView:_destroyRow(userId: number)
	local row = self.Rows[userId]
	if not row then return end
	self.Rows[userId] = nil
	self.RowVillage[userId] = nil

	local bundle = self.RowConnections[userId]
	if bundle then
		for _, connection in ipairs(bundle) do
			if connection.Connected then connection:Disconnect() end
		end
	end
	self.RowConnections[userId] = nil

	if self.SelectedUserId == userId then self.SelectedUserId = nil end

	if self.ReducedMotion then
		row:Destroy()
		return
	end

	local tween = TweenService:Create(
		row,
		TweenInfo.new(self.Config.Animation.Leave, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			Position = UDim2.new(row.Position.X.Scale, row.Position.X.Offset + 8, row.Position.Y.Scale, row.Position.Y.Offset),
			GroupTransparency = 1,
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		if row.Parent then row:Destroy() end
	end)
end

function ServerListView:_updatePlayerRow(row: CanvasGroup, entry: PlayerEntry)
	local name = row:FindFirstChild("CharacterName") :: TextLabel?
	local username = row:FindFirstChild("Username") :: TextLabel?
	local rank = row:FindFirstChild("Rank") :: TextLabel?
	if name then name.Text = entry.CharacterName end
	if username then username.Text = "@" .. entry.Username end
	if rank then rank.Text = entry.Rank end
end

function ServerListView:_refreshSelection()
	for userId, row in pairs(self.Rows) do
		local selected = self.SelectedUserId == userId
		local invite = row:FindFirstChild("InviteAction") :: TextButton?
		local background = row:FindFirstChild("Background") :: Frame?
		if invite then
			invite.Visible = selected
			if selected and self.InviteReasonCallback then
				local reason = self.InviteReasonCallback(userId)
				invite.Text = if reason == "" then "Invite to squad" else reason
				invite.Active = reason == ""
				invite.TextTransparency = if reason == "" then 0 else 0.35
			end
		end
		if background then
			background.BackgroundTransparency = if selected then 0.05 else 0.19
		end
	end
end

function ServerListView:SetInvitationAdapter(inviteCallback: (number) -> (), reasonCallback: (number) -> string)
	self.InviteCallback = inviteCallback
	self.InviteReasonCallback = reasonCallback
	self:_refreshSelection()
end

function ServerListView:SetVillageCollapsed(villageKey: string, collapsed: boolean)
	if self.Collapsed[villageKey] == collapsed then return end
	self.Collapsed[villageKey] = collapsed
	local section = self.Sections[villageKey]
	if section then section.Arrow.Text = if collapsed then "›" else "⌄" end
	self:_layout(true, self.Config.Animation.Collapse)
end

function ServerListView:UpdateRoster(entries: {PlayerEntry})
	local oldScroll = self.VillageList.CanvasPosition
	local nextById: {[number]: PlayerEntry} = {}
	local counts: {[string]: number} = {}

	for _, village in ipairs(self.Config.Villages) do
		counts[village.Key] = 0
	end

	for _, entry in ipairs(entries) do
		nextById[entry.UserId] = entry
		counts[entry.VillageKey] = (counts[entry.VillageKey] or 0) + 1

		local row = self.Rows[entry.UserId]
		local previousVillage = self.RowVillage[entry.UserId]
		if not row then
			row = self:_createPlayerRow(entry)
			self.RowVillage[entry.UserId] = entry.VillageKey
			self.NewRows[entry.UserId] = true
		elseif previousVillage ~= entry.VillageKey then
			self.RowVillage[entry.UserId] = entry.VillageKey
			self.MovedRows[entry.UserId] = true
		end
		self:_updatePlayerRow(row, entry)
	end

	for userId in pairs(self.Rows) do
		if not nextById[userId] then self:_destroyRow(userId) end
	end

	self.LastEntries = entries
	self.PlayerCount.Text = tostring(#entries) .. (if #entries == 1 then " player" else " players")

	for _, village in ipairs(self.Config.Villages) do
		local section = self.Sections[village.Key]
		if section then
			local count = counts[village.Key] or 0
			section.Count.Text = tostring(count)
			section.CloudLower.Visible = count >= 1
			section.CloudUpper.Visible = count >= 3
			if count == 1 then
				section.CloudLower.Size = UDim2.fromOffset(94, 47)
				section.CloudLower.ImageTransparency = 0.82
			else
				section.CloudLower.Size = UDim2.fromOffset(126, 63)
				section.CloudLower.ImageTransparency = 0.76
			end
		end
	end

	self:_refreshSelection()
	self:_layout(true)

	task.defer(function()
		if self.Destroyed then return end
		local maxY = math.max(0, self.VillageList.AbsoluteCanvasSize.Y - self.VillageList.AbsoluteWindowSize.Y)
		self.VillageList.CanvasPosition = Vector2.new(0, math.clamp(oldScroll.Y, 0, maxY))
	end)
end

function ServerListView:_layout(animated: boolean, overrideDuration: number?)
	local y = 0
	local rowHeight = self.Config.Layout.PlayerRowHeight
	local expandedHeight = self.Config.Layout.PlayerRowExpandedHeight
	local gap = self.Config.Layout.VillageGap
	local duration = overrideDuration or self.Config.Animation.Reflow
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, village in ipairs(self.Config.Villages) do
		local section = self.Sections[village.Key]
		local rows = {}
		for _, entry in ipairs(self.LastEntries) do
			if entry.VillageKey == village.Key then table.insert(rows, entry) end
		end
		table.sort(rows, function(a, b)
			local an = string.lower(a.CharacterName)
			local bn = string.lower(b.CharacterName)
			if an == bn then return string.lower(a.Username) < string.lower(b.Username) end
			return an < bn
		end)

		local collapsed = self.Collapsed[village.Key] == true
		local contentHeight = 0
		if not collapsed then
			for _, entry in ipairs(rows) do
				contentHeight += if self.SelectedUserId == entry.UserId then expandedHeight else rowHeight
			end
		end
		local sectionHeight = self.Config.Layout.VillageHeaderHeight + contentHeight

		if animated and not self.ReducedMotion then
			TweenService:Create(section.Root, tweenInfo, {
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, sectionHeight),
			}):Play()
			TweenService:Create(section.Content, tweenInfo, {
				Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, contentHeight),
			}):Play()
		else
			section.Root.Position = UDim2.fromOffset(0, y)
			section.Root.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, sectionHeight)
			section.Content.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, contentHeight)
		end

		local rowY = y + self.Config.Layout.VillageHeaderHeight
		for _, entry in ipairs(rows) do
			local row = self.Rows[entry.UserId]
			if row then
				local targetHeight = if self.SelectedUserId == entry.UserId then expandedHeight else rowHeight
				row.Visible = not collapsed
				if not collapsed then
					local targetPosition = UDim2.fromOffset(0, rowY)
					if self.ReducedMotion or not animated then
						row.Position = targetPosition
						row.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, targetHeight)
						row.GroupTransparency = 0
					elseif self.NewRows[entry.UserId] then
						row.Position = UDim2.fromOffset(8, rowY)
						row.Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, targetHeight)
						row.GroupTransparency = 1
						TweenService:Create(row, TweenInfo.new(self.Config.Animation.Join, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Position = targetPosition,
							GroupTransparency = 0,
						}):Play()
					elseif self.MovedRows[entry.UserId] then
						TweenService:Create(row, TweenInfo.new(self.Config.Animation.ChangeVillage, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Position = targetPosition,
							Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, targetHeight),
							GroupTransparency = 0,
						}):Play()
					else
						TweenService:Create(row, tweenInfo, {
							Position = targetPosition,
							Size = UDim2.fromOffset(self.Config.Layout.VillageHeaderWidth, targetHeight),
							GroupTransparency = 0,
						}):Play()
					end
					rowY += targetHeight
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
		self.Panel.Position = UDim2.new(finalPosition.X.Scale, finalPosition.X.Offset + 8 * self.Scale, finalPosition.Y.Scale, finalPosition.Y.Offset)
		self.Panel.GroupTransparency = 1
		self.PanelTween = TweenService:Create(self.Panel, TweenInfo.new(self.Config.Animation.Open, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = finalPosition})
		self.PanelFadeTween = TweenService:Create(self.Panel, TweenInfo.new(self.Config.Animation.Open, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0})
		self.PanelTween:Play()
		self.PanelFadeTween:Play()
	else
		self.PanelTween = TweenService:Create(self.Panel, TweenInfo.new(self.Config.Animation.Close, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(self.Panel.Position.X.Scale, self.Panel.Position.X.Offset + 6 * self.Scale, self.Panel.Position.Y.Scale, self.Panel.Position.Y.Offset)
		})
		self.PanelFadeTween = TweenService:Create(self.Panel, TweenInfo.new(self.Config.Animation.Close, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {GroupTransparency = 1})
		self.PanelTween:Play()
		self.PanelFadeTween:Play()
		self.PanelFadeTween.Completed:Connect(function()
			if not self.Destroyed and self.TransitionRevision == revision and not self.Open then
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
	if not camera then return end

	local viewport = camera.ViewportSize
	local reference = self.Config.ReferenceViewport
	local scale = math.min(viewport.X / reference.X, viewport.Y / reference.Y)
	self.Scale = scale

	self.ServerButton.Position = UDim2.fromOffset(
		self.Config.Layout.ServerButton.Position.X * scale,
		self.Config.Layout.ServerButton.Position.Y * scale
	)
	self.ServerButton.Size = UDim2.fromOffset(
		self.Config.Layout.ServerButton.Size.X * scale,
		self.Config.Layout.ServerButton.Size.Y * scale
	)

	self.Panel.Position = UDim2.new(1, -self.Config.Layout.Right * scale, 0, self.Config.Layout.Top * scale)

	local uniformScale = self.Panel:FindFirstChild("UniformScale") :: UIScale?
	if not uniformScale then
		uniformScale = Instance.new("UIScale")
		uniformScale.Name = "UniformScale"
		uniformScale.Parent = self.Panel
	end
	uniformScale.Scale = scale
	self.Panel.Size = UDim2.fromOffset(self.Config.Layout.Width, self.Config.Layout.Height)
end

function ServerListView:_bindViewport()
	local function bindCamera(camera: Camera?)
		if self.CameraConnection then
			self.CameraConnection:Disconnect()
			self.CameraConnection = nil
		end
		if camera then
			self.CameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:_applyViewport()
			end)
		end
		self:_applyViewport()
	end

	bindCamera(Workspace.CurrentCamera)
	table.insert(self.Connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(Workspace.CurrentCamera)
	end))
end

function ServerListView:RefreshSelection()
	self:_refreshSelection()
end

function ServerListView:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true

	cancelTween(self.PanelTween)
	cancelTween(self.PanelFadeTween)

	if self.CameraConnection and self.CameraConnection.Connected then
		self.CameraConnection:Disconnect()
	end

	for _, bundle in pairs(self.RowConnections) do
		for _, connection in ipairs(bundle) do
			if connection.Connected then connection:Disconnect() end
		end
	end

	for _, connection in ipairs(self.Connections) do
		if connection.Connected then connection:Disconnect() end
	end

	if self.Gui then self.Gui:Destroy() end
end

return ServerListView
