local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local assetsModule = script.Parent:FindFirstChild("ServerSelectorHUDAssets")
	or script.Parent:FindFirstChild("ServerSelectorHUDAssets_v1")
local assets = if assetsModule then require(assetsModule) else {}

local ServerSelectorHUD = {}

local INK = Color3.fromRGB(52, 49, 40)
local MUTED = Color3.fromRGB(118, 110, 96)
local ACCENT = Color3.fromRGB(133, 59, 52)
local CREAM = Color3.fromRGB(238, 226, 204)
local FAINT = Color3.fromRGB(224, 214, 193)

local function asset(id: any): string
	id = tonumber(id) or 0
	return id > 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local function create(parent: Instance, className: string, props: {[string]: any}?)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function makeImage(parent: Instance, name: string, imageId: any, size: UDim2, position: UDim2, z: number, scaleType: Enum.ScaleType?)
	local image = create(parent, "ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = asset(imageId),
		ScaleType = scaleType or Enum.ScaleType.Stretch,
		Size = size,
		Position = position,
		ZIndex = z,
	})
	return image
end

local function makeText(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, z: number, textSize: number, color: Color3?, alignX: Enum.TextXAlignment?, bold: boolean?)
	local label = create(parent, "TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = color or INK,
		TextSize = textSize,
		Font = bold and Enum.Font.Garamond or Enum.Font.Garamond,
		TextXAlignment = alignX or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = size,
		Position = position,
		ZIndex = z,
	})
	return label
end

local function setVisible(list: {Instance}, visible: boolean)
	for _, object in ipairs(list) do
		if object and object.Parent then
			(object :: any).Visible = visible
		end
	end
end

local function applyImage(imageObject: ImageLabel | ImageButton, imageId: any)
	local value = asset(imageId)
	if value ~= "" then
		imageObject.Image = value
		imageObject.ImageTransparency = 0
	else
		imageObject.Image = ""
		imageObject.ImageTransparency = 1
	end
end

local function styleActionButton(container: Instance, config: {[string]: any})
	local button = create(container, "ImageButton", {
		Name = config.Name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = config.Size,
		Position = config.Position,
		ZIndex = config.ZIndex,
	})
	local bg = create(button, "ImageLabel", {
		Name = "Background",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = asset(config.Normal),
		ScaleType = Enum.ScaleType.Stretch,
		Size = UDim2.fromScale(1, 1),
		ZIndex = config.ZIndex,
	})
	local fallback = create(button, "Frame", {
		Name = "Fallback",
		BackgroundColor3 = config.Primary and ACCENT or FAINT,
		BackgroundTransparency = 0,
		BorderColor3 = Color3.fromRGB(209, 194, 170),
		BorderSizePixel = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = config.ZIndex - 1,
	})
	create(fallback, "UICorner", { CornerRadius = UDim.new(0, 0) })
	local icon = nil
	if config.Icon then
		icon = create(button, "ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = asset(config.Icon),
			Size = config.IconSize,
			Position = config.IconPosition,
			ZIndex = config.ZIndex + 1,
		})
	end
	local text = create(button, "TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = config.Text,
		TextColor3 = config.TextColor,
		TextSize = config.TextSize,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = config.ZIndex + 1,
	})
	if config.TextPaddingLeft then
		text.Position = UDim2.fromOffset(config.TextPaddingLeft, 0)
		text.Size = UDim2.new(1, -config.TextPaddingLeft, 1, 0)
	end

	local state = {
		disabled = false,
		pressed = false,
		hover = false,
	}

	local function refreshVisuals()
		local imageId = config.Normal
		local textColor = config.TextColor
		local bgColor = config.Primary and ACCENT or FAINT
		local bgTransparency = 0
		if state.disabled then
			imageId = config.Disabled
			textColor = config.DisabledTextColor or textColor:Lerp(Color3.new(1,1,1), 0.35)
			bgTransparency = 0.3
		elseif state.pressed then
			imageId = config.Pressed
			bgColor = config.Primary and Color3.fromRGB(120, 50, 44) or Color3.fromRGB(233, 223, 202)
		elseif state.hover then
			imageId = config.Hover
			bgColor = config.Primary and Color3.fromRGB(146, 68, 61) or Color3.fromRGB(241, 233, 214)
		end
		applyImage(bg, imageId)
		text.TextColor3 = textColor
		fallback.BackgroundColor3 = bgColor
		fallback.BackgroundTransparency = bgTransparency
		button.Active = not state.disabled
	end

	button.MouseEnter:Connect(function()
		state.hover = true
		refreshVisuals()
	end)
	button.MouseLeave:Connect(function()
		state.hover = false
		state.pressed = false
		refreshVisuals()
	end)
	button.MouseButton1Down:Connect(function()
		state.pressed = true
		refreshVisuals()
	end)
	button.MouseButton1Up:Connect(function()
		state.pressed = false
		refreshVisuals()
	end)

	refreshVisuals()

	return {
		Root = button,
		Label = text,
		SetDisabled = function(flag: boolean)
			state.disabled = flag
			refreshVisuals()
		end,
		SetText = function(value: string)
			text.Text = value
		end,
	}
end

function ServerSelectorHUD.Create(gui: ScreenGui, parent: Instance, callbacks: {[string]: any})
	local root = create(parent, "Frame", {
		Name = "ServerSelectorHUDRoot",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	})

	local backdrop = makeImage(root, "Backdrop", assets.Backdrop, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 1, Enum.ScaleType.Crop)
	if backdrop.Image == "" then
		create(root, "Frame", {
			Name = "BackdropFallback",
			BackgroundColor3 = Color3.fromRGB(16, 20, 18),
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		})
	end

	local canvas = create(root, "Frame", {
		Name = "ReferenceCanvas",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(1920, 1080),
		Position = UDim2.fromOffset(0, 0),
		ZIndex = 2,
	})
	local canvasScale = create(canvas, "UIScale", {
		Scale = 1,
	})

	local function updateCanvasScale()
		local viewport = root.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local factor = math.min(viewport.X / 1920, viewport.Y / 1080)
		canvasScale.Scale = factor
		canvas.Position = UDim2.fromOffset(
			math.floor((viewport.X - 1920 * factor) * 0.5 + 0.5),
			math.floor((viewport.Y - 1080 * factor) * 0.5 + 0.5)
		)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvasScale)
	task.defer(updateCanvasScale)

	local paper = makeImage(canvas, "Paper", assets.PaperPanel, UDim2.fromOffset(1320, 890), UDim2.fromOffset(300, 100), 2)
	local paperFallback = create(canvas, "Frame", {
		Name = "PaperFallback",
		BackgroundColor3 = CREAM,
		BorderColor3 = Color3.fromRGB(170, 156, 130),
		BorderSizePixel = 1,
		Size = paper.Size,
		Position = paper.Position,
		ZIndex = 1,
		Visible = paper.Image == "",
	})

	local titleImage = makeImage(canvas, "Title", assets.Title, UDim2.fromOffset(325, 60), UDim2.fromOffset(368, 142), 4)
	if titleImage.Image == "" then
		makeText(canvas, "TitleFallback", "Servers", UDim2.fromOffset(325, 60), UDim2.fromOffset(368, 142), 4, 34, INK, Enum.TextXAlignment.Left, true)
	end

	local headerRule = makeImage(canvas, "HeaderRule", assets.SectionRule, UDim2.fromOffset(1180, 8), UDim2.fromOffset(370, 278), 4)
	create(canvas, "Frame", {
		Name = "HeaderRuleFallback",
		BackgroundColor3 = Color3.fromRGB(188, 175, 145),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(370, 281),
		Size = UDim2.fromOffset(1180, 2),
		ZIndex = 3,
		Visible = headerRule.Image == "",
	})

	makeText(canvas, "ServerHeader", "SERVER", UDim2.fromOffset(440, 24), UDim2.fromOffset(390, 314), 4, 15, MUTED, Enum.TextXAlignment.Left, true)
	makeText(canvas, "PlayersHeader", "PLAYERS", UDim2.fromOffset(150, 24), UDim2.fromOffset(949, 314), 4, 15, MUTED, Enum.TextXAlignment.Center, true)
	makeText(canvas, "RegionHeader", "REGION", UDim2.fromOffset(192, 24), UDim2.fromOffset(1094, 314), 4, 15, MUTED, Enum.TextXAlignment.Center, true)

	local quickplay = styleActionButton(canvas, {
		Name = "QuickplayButton",
		Size = UDim2.fromOffset(236, 54),
		Position = UDim2.fromOffset(1304, 177),
		ZIndex = 5,
		Normal = assets.ButtonPrimaryNormal,
		Hover = assets.ButtonPrimaryHover,
		Pressed = assets.ButtonPrimaryPressed,
		Disabled = assets.ButtonPrimaryDisabled,
		Primary = true,
		Text = "Quickplay",
		TextSize = 23,
		TextColor = CREAM,
		DisabledTextColor = CREAM:Lerp(MUTED, 0.4),
	})
	quickplay.Root.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onQuickplay then
			callbacks.onQuickplay()
		end
	end)

	local refresh = styleActionButton(canvas, {
		Name = "RefreshButton",
		Size = UDim2.fromOffset(168, 54),
		Position = UDim2.fromOffset(1110, 177),
		ZIndex = 5,
		Normal = assets.ButtonSecondaryNormal,
		Hover = assets.ButtonSecondaryHover,
		Pressed = assets.ButtonSecondaryPressed,
		Disabled = assets.ButtonSecondaryDisabled,
		Primary = false,
		Text = "Refresh",
		TextSize = 22,
		TextColor = INK,
		DisabledTextColor = MUTED,
		Icon = assets.IconRefresh,
		IconSize = UDim2.fromOffset(23, 23),
		IconPosition = UDim2.fromOffset(18, 15),
		TextPaddingLeft = 22,
	})
	refresh.Root.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onRefresh then
			callbacks.onRefresh()
		end
	end)

	local back = create(canvas, "TextButton", {
		Name = "BackButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(135, 38),
		Position = UDim2.fromOffset(370, 929),
		ZIndex = 5,
	})
	create(back, "TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Text = "Back",
		TextColor3 = INK,
		TextSize = 22,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -28, 1, 0),
		Position = UDim2.fromOffset(28, 0),
		ZIndex = 6,
	})
	create(back, "ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = asset(assets.IconBack),
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(3, 5),
		ZIndex = 6,
	})
	back.MouseButton1Click:Connect(function()
		if callbacks and callbacks.onBack then
			callbacks.onBack()
		end
	end)

	create(canvas, "Frame", {
		Name = "FooterRule",
		BackgroundColor3 = Color3.fromRGB(107, 96, 71),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(370, 911),
		Size = UDim2.fromOffset(1180, 1),
		ZIndex = 4,
	})

	local listContainer = create(canvas, "Frame", {
		Name = "ListContainer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(370, 365),
		Size = UDim2.fromOffset(1180, 492),
		ZIndex = 4,
	})

	local list = create(listContainer, "ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(1180, 492),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 6,
		TopImage = asset(assets.ScrollThumb),
		MidImage = asset(assets.ScrollThumb),
		BottomImage = asset(assets.ScrollThumb),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ZIndex = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ClipsDescendants = true,
	})
	list.ScrollBarImageColor3 = Color3.fromRGB(163, 149, 126)
	list.ScrollBarImageTransparency = 0.1

	local layout = create(list, "UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, math.max(0, layout.AbsoluteContentSize.Y))
	end)

	local stateIcon = create(canvas, "ImageLabel", {
		Name = "StateIcon",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(918, 476),
		ZIndex = 6,
		Visible = false,
	})
	local stateTitle = create(canvas, "TextLabel", {
		Name = "StateTitle",
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = INK,
		TextSize = 32,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromOffset(960, 44),
		Position = UDim2.fromOffset(480, 593),
		ZIndex = 6,
		Visible = false,
	})
	local stateDescription = create(canvas, "TextLabel", {
		Name = "StateDescription",
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = MUTED,
		TextSize = 21,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromOffset(960, 32),
		Position = UDim2.fromOffset(480, 645),
		ZIndex = 6,
		Visible = false,
	})
	local statusHint = create(canvas, "TextLabel", {
		Name = "StatusHint",
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = MUTED,
		TextSize = 18,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromOffset(280, 24),
		Position = UDim2.fromOffset(1260, 242),
		ZIndex = 5,
	})

	local currentRows: {Frame} = {}
	local currentServerMap = {}
	local cachedServers: {any} = {}
	local joinableCount = 0
	local stateName = "loading"
	local requestPending = false
	local joiningServerId: string? = nil
	local statusToken = 0

	local function clearRows()
		for _, row in ipairs(currentRows) do
			row:Destroy()
		end
		table.clear(currentRows)
		table.clear(currentServerMap)
	end

	local function setMessage(iconId: any, title: string, description: string)
		stateIcon.Visible = true
		stateTitle.Visible = true
		stateDescription.Visible = true
		stateIcon.Image = asset(iconId)
		if stateIcon.Image == "" then
			stateIcon.Image = ""
			stateIcon.ImageTransparency = 1
		else
			stateIcon.ImageTransparency = 0
		end
		stateTitle.Text = title
		stateDescription.Text = description
	end

	local function hideMessage()
		stateIcon.Visible = false
		stateTitle.Visible = false
		stateDescription.Visible = false
	end

	local function updateButtons()
		local hasJoinable = joinableCount > 0
		local joining = joiningServerId ~= nil
		quickplay.SetDisabled(requestPending or joining or not hasJoinable)
		refresh.SetDisabled(requestPending or joining)
		if requestPending then
			refresh.SetText("Refreshing…")
		elseif stateName == "loading" then
			refresh.SetText("Refresh")
		else
			refresh.SetText("Refresh")
		end
	end

	local function makeRow(server: any, order: number)
		local row = create(list, "Frame", {
			Name = "ServerRow_" .. tostring(order),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1180, 72),
			LayoutOrder = order,
			ZIndex = 4,
		})
		local bg = create(row, "ImageLabel", {
			Name = "Background",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Image = asset(assets.RowNormal),
			ZIndex = 4,
		})
		local fallback = create(row, "Frame", {
			Name = "Fallback",
			BackgroundColor3 = Color3.fromRGB(244, 236, 220),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		})
		local accent = create(row, "Frame", {
			Name = "Accent",
			BackgroundColor3 = ACCENT,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(3, 40),
			Position = UDim2.fromOffset(0, 16),
			ZIndex = 5,
			Visible = false,
		})

		local name = makeText(row, "Name", tostring(server.displayName or "Unknown Server"), UDim2.fromOffset(565, 36), UDim2.fromOffset(20, 18), 5, 26, INK, Enum.TextXAlignment.Left, false)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local maxPlayersValue = tonumber(server.maxPlayers) or 0
		local playersText = tostring(server.playerCount or 0) .. " / " .. (maxPlayersValue > 0 and tostring(maxPlayersValue) or "?")
		local players = makeText(row, "Players", playersText, UDim2.fromOffset(150, 30), UDim2.fromOffset(579, 21), 5, 22, INK, Enum.TextXAlignment.Center, false)
		local region = makeText(row, "Region", tostring(server.regionLabel or "Unknown"), UDim2.fromOffset(192, 30), UDim2.fromOffset(724, 21), 5, 22, MUTED, Enum.TextXAlignment.Center, false)
		region.TextTruncate = Enum.TextTruncate.AtEnd

		local joinButton = styleActionButton(row, {
			Name = "JoinButton",
			Size = UDim2.fromOffset(152, 46),
			Position = UDim2.fromOffset(997, 13),
			ZIndex = 6,
			Normal = assets.ButtonSecondaryNormal,
			Hover = assets.ButtonSecondaryHover,
			Pressed = assets.ButtonSecondaryPressed,
			Disabled = assets.ButtonSecondaryDisabled,
			Primary = false,
			Text = "Join",
			TextSize = 22,
			TextColor = INK,
			DisabledTextColor = MUTED,
		})

		local maxPlayersForJoin = tonumber(server.maxPlayers) or 0
		local joinable = server.joinable ~= false
			and (maxPlayersForJoin <= 0 or (tonumber(server.playerCount) or 0) < maxPlayersForJoin)
		local function refreshRowVisual(hovering: boolean?)
			local disabled = not joinable or joiningServerId ~= nil
			local img = assets.RowNormal
			if disabled then
				img = assets.RowDisabled
				name.TextColor3 = MUTED
				players.TextColor3 = MUTED
				region.TextColor3 = MUTED
				fallback.BackgroundTransparency = 0.4
			else
				name.TextColor3 = INK
				players.TextColor3 = INK
				region.TextColor3 = MUTED
				fallback.BackgroundTransparency = 0.25
				if hovering then
					img = assets.RowHover
				end
			end
			applyImage(bg, img)
			accent.Visible = hovering == true and not disabled
			joinButton.SetDisabled(disabled)
			if joiningServerId == server.serverId then
				joinButton.SetText("Joining…")
				joinButton.SetDisabled(true)
			elseif not joinable then
				joinButton.SetText("Full")
				joinButton.SetDisabled(true)
			else
				joinButton.SetText("Join")
			end
		end

		row.MouseEnter:Connect(function()
			refreshRowVisual(true)
		end)
		row.MouseLeave:Connect(function()
			refreshRowVisual(false)
		end)
		joinButton.Root.MouseButton1Click:Connect(function()
			if not joinable or joiningServerId ~= nil then
				return
			end
			joiningServerId = server.serverId
			refreshRowVisual(false)
			updateButtons()
			if callbacks and callbacks.onJoin then
				callbacks.onJoin(server)
			end
		end)
		refreshRowVisual(false)

		table.insert(currentRows, row)
		currentServerMap[tostring(server.serverId or order)] = {Row = row, Refresh = refreshRowVisual, Data = server}
	end

	local api = {}

	function api.SetServers(servers: {any})
		cachedServers = servers or {}
		joinableCount = 0
		for _, server in ipairs(cachedServers) do
			if typeof(server) == "table" then
				local maxPlayersValue = tonumber(server.maxPlayers) or 0
				if server.joinable ~= false
					and (maxPlayersValue <= 0 or (tonumber(server.playerCount) or 0) < maxPlayersValue) then
					joinableCount += 1
				end
			end
		end
		clearRows()
		if #cachedServers > 0 then
			for index, server in ipairs(cachedServers) do
				makeRow(server, index)
			end
			list.Visible = true
			hideMessage()
			stateName = "ready"
		else
			list.Visible = false
			setMessage(assets.IconServers, "No servers available", "Refresh to check again.")
			stateName = "empty"
		end
		joiningServerId = nil
		updateButtons()
	end

	function api.SetState(newState: string, payload: {[string]: any}?)
		stateName = newState
		local info = payload or {}
		if newState == "loading" then
			clearRows()
			cachedServers = {}
			joinableCount = 0
			list.Visible = false
			setMessage(assets.IconRefresh, "Finding servers…", "This may take a moment.")
		elseif newState == "error" then
			if info.keepExisting == true and #cachedServers > 0 then
				list.Visible = true
				hideMessage()
				statusToken += 1
				local token = statusToken
				statusHint.Text = info.description or "Couldn’t refresh. Showing previous list."
				task.delay(4, function()
					if token == statusToken and not requestPending then
						statusHint.Text = ""
					end
				end)
				stateName = "ready"
			else
				clearRows()
				cachedServers = {}
				joinableCount = 0
				list.Visible = false
				setMessage(assets.IconWarning, "Couldn’t load servers", info.description or "Please refresh and try again.")
			end
		elseif newState == "empty" then
			clearRows()
			cachedServers = {}
			joinableCount = 0
			list.Visible = false
			setMessage(assets.IconServers, "No servers available", "Refresh to check again.")
		elseif newState == "ready" then
			api.SetServers(info.servers or cachedServers)
			return
		end
		joiningServerId = nil
		updateButtons()
	end

	function api.SetRefreshing(flag: boolean)
		requestPending = flag
		statusToken += 1
		statusHint.Text = flag and "Refreshing server list…" or ""
		updateButtons()
		if flag and #cachedServers > 0 then
			list.Visible = true
			hideMessage()
		end
	end

	function api.SetJoinPending(serverId: string?)
		joiningServerId = serverId
		for _, info in pairs(currentServerMap) do
			info.Refresh(false)
		end
		updateButtons()
	end

	function api.ResetJoinPending()
		joiningServerId = nil
		for _, info in pairs(currentServerMap) do
			info.Refresh(false)
		end
		updateButtons()
	end

	function api.ShowStatus(textValue: string, duration: number?)
		statusToken += 1
		local token = statusToken
		statusHint.Text = textValue
		if textValue ~= "" then
			task.delay(duration or 4, function()
				if token == statusToken and not requestPending then
					statusHint.Text = ""
				end
			end)
		end
	end

	function api.GetCachedServers(): {any}
		return cachedServers
	end

	function api.GetRoot()
		return root
	end

	function api.SetVisible(visible: boolean)
		root.Visible = visible
	end

	function api.Show()
		root.Visible = true
	end

	function api.Hide()
		root.Visible = false
	end

	api.SetState("loading")
	return api
end

return ServerSelectorHUD
