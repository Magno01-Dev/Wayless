--!strict
-- ReplicatedStorage > Shared > MainMenuHUD
-- WAYLESS Main Menu HUD v1.2 - layered animated background integration
--
-- Source layout: WAYLESS_Menu_Inicial_Assets_v2.zip
-- Reference canvas: 1920x1080 for HUD content and animated background layers.
-- The layered background follows WAYLESS_Fondo_Animado/design.json + layout.json.
-- Until all seven animated PNG IDs are filled, the approved static background
-- remains active automatically, so this module can be installed before upload.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local assetsModule =
	script.Parent:FindFirstChild("MainMenuHUDAssets")
	or script.Parent:FindFirstChild("MainMenuHUDAssets_v3_ANIMATED_PLACEHOLDERS")
	or script.Parent:FindFirstChild("MainMenuHUDAssets_v2_FILLED")
	or script.Parent:FindFirstChild("MainMenuHUDAssets_v1_PLACEHOLDERS")

if not assetsModule or not assetsModule:IsA("ModuleScript") then
	error("[MainMenuHUD] MainMenuHUDAssets ModuleScript missing")
end

local Assets = require(assetsModule)

local animatedBackgroundModule =
	script.Parent:FindFirstChild("MainMenuAnimatedBackground")
	or script.Parent:FindFirstChild("MainMenuAnimatedBackground_v1")

if not animatedBackgroundModule or not animatedBackgroundModule:IsA("ModuleScript") then
	error("[MainMenuHUD] MainMenuAnimatedBackground ModuleScript missing")
end

local MainMenuAnimatedBackground = require(animatedBackgroundModule)

local MainMenuHUD = {}

local CANVAS_W = 1920
local CANVAS_H = 1080

local COLORS = {
	Text = Color3.fromRGB(233, 226, 212),
	SecondaryText = Color3.fromRGB(185, 190, 176),
	Tagline = Color3.fromRGB(213, 201, 174),
	Ink = Color3.fromRGB(14, 25, 22),
	Accent = Color3.fromRGB(133, 59, 52),
	WarmAccent = Color3.fromRGB(199, 154, 114),
	Divider = Color3.fromRGB(223, 213, 190),
	FallbackButton = Color3.fromRGB(13, 33, 29),
	FallbackPanel = Color3.fromRGB(11, 28, 24),
}

local function imageLabel(
	parent: Instance,
	name: string,
	key: string,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number
): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Position = UDim2.fromOffset(x, y)
	image.Size = UDim2.fromOffset(w, h)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = Assets.Get(key)
	image.ScaleType = Enum.ScaleType.Stretch
	image.ZIndex = z
	image.Parent = parent
	return image
end

local function textLabel(
	parent: Instance,
	name: string,
	text: string,
	x: number,
	y: number,
	w: number,
	h: number,
	textSize: number,
	color: Color3,
	xAlignment: Enum.TextXAlignment,
	z: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(w, h)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = Enum.Font.Garamond
	label.TextXAlignment = xAlignment
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = z
	label.Parent = parent
	return label
end

local function makeFallbackButtonVisual(button: ImageButton, labelText: string): Frame
	local fallback = Instance.new("Frame")
	fallback.Name = "FallbackVisual"
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.BackgroundColor3 = COLORS.FallbackButton
	fallback.BackgroundTransparency = 0.13
	fallback.BorderSizePixel = 0
	fallback.ZIndex = button.ZIndex
	fallback.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Divider
	stroke.Transparency = 0.72
	stroke.Thickness = 1
	stroke.Parent = fallback

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(34, 0)
	label.Size = UDim2.new(1, -72, 1, 0)
	label.Text = labelText
	label.TextColor3 = COLORS.Text
	label.TextSize = 26
	label.Font = Enum.Font.Garamond
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = button.ZIndex + 1
	label.Parent = fallback

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Icon"
	arrow.BackgroundTransparency = 1
	arrow.Position = UDim2.new(1, -46, 0, 0)
	arrow.Size = UDim2.fromOffset(32, 68)
	arrow.Text = labelText == "Quickplay" and ">>" or (labelText == "Settings" and "S" or (labelText == "Credits" and "C" or ">"))
	arrow.TextColor3 = COLORS.Text
	arrow.TextSize = 20
	arrow.Font = Enum.Font.Garamond
	arrow.ZIndex = button.ZIndex + 1
	arrow.Parent = fallback

	return fallback
end

local function makeStateButton(
	parent: Instance,
	id: string,
	labelText: string,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number
): (ImageButton, (boolean) -> ())
	local button = Instance.new("ImageButton")
	button.Name = id .. "Button"
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(w, h)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Selectable = true
	button.ZIndex = z
	button.Parent = parent

	local fallback = makeFallbackButtonVisual(button, labelText)
	local enabled = true
	local hovered = false
	local pressed = false
	local selected = false

	local function apply()
		local suffix = "normal"
		if not enabled then
			suffix = "disabled"
		elseif pressed then
			suffix = "pressed"
		elseif hovered or selected then
			suffix = "hover"
		end

		local key = string.lower(id) .. "_" .. suffix
		button.Image = Assets.Get(key)
		fallback.Visible = not Assets.Has(key)
		button.Active = enabled
		button.Selectable = enabled

		if fallback.Visible then
			fallback.BackgroundColor3 =
				suffix == "hover" and COLORS.Accent
				or suffix == "pressed" and Color3.fromRGB(99, 43, 39)
				or COLORS.FallbackButton
			fallback.BackgroundTransparency = suffix == "disabled" and 0.5 or 0.13
			local label = fallback:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.TextTransparency = suffix == "disabled" and 0.45 or 0
			end
		end
	end

	button.MouseEnter:Connect(function()
		hovered = true
		apply()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		apply()
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			pressed = true
			apply()
		end
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		apply()
	end)
	button.SelectionGained:Connect(function()
		selected = true
		apply()
	end)
	button.SelectionLost:Connect(function()
		selected = false
		pressed = false
		apply()
	end)

	local function setEnabled(value: boolean)
		enabled = value
		if not enabled then
			pressed = false
		end
		apply()
	end

	apply()
	return button, setEnabled
end

local function buildPatchNotes(canvas: Frame): (ScrollingFrame, ImageLabel)
	local panel = imageLabel(canvas, "PatchPanel", "patch_panel", 1418, 677, 440, 336, 30)
	if not Assets.Has("patch_panel") then
		panel.BackgroundColor3 = COLORS.FallbackPanel
		panel.BackgroundTransparency = 0.08
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.Divider
		stroke.Transparency = 0.73
		stroke.Parent = panel
	end

	local headingImage = imageLabel(canvas, "PatchHeading", "patch_heading", 1443, 696, 300, 36, 33)
	local headingFallback = textLabel(
		canvas,
		"PatchTitleFallback",
		"PATCH NOTES",
		1443,
		697,
		330,
		30,
		20,
		COLORS.Text,
		Enum.TextXAlignment.Left,
		33
	)
	headingFallback.Visible = not Assets.Has("patch_heading")
	headingImage.Visible = Assets.Has("patch_heading")

	textLabel(canvas, "PatchNumber", "01", 1800, 700, 24, 24, 15, Color3.fromRGB(179, 175, 160), Enum.TextXAlignment.Right, 33)

	local body = Instance.new("ScrollingFrame")
	body.Name = "PatchContent"
	body.Position = UDim2.fromOffset(1441, 763)
	body.Size = UDim2.fromOffset(385, 221)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 0
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ClipsDescendants = true
	body.ZIndex = 34
	body.Parent = canvas

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 20)
	padding.PaddingTop = UDim.new(0, 2)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = body

	local order = 0
	local function addText(name: string, text: string, size: number, color: Color3, height: number, wrapped: boolean?)
		order += 1
		local l = Instance.new("TextLabel")
		l.Name = name
		l.LayoutOrder = order
		l.Size = UDim2.new(1, 0, 0, height)
		l.AutomaticSize = wrapped and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextColor3 = color
		l.TextSize = size
		l.Font = Enum.Font.Garamond
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.TextWrapped = wrapped == true
		l.ZIndex = 35
		l.Parent = body
		return l
	end

	local function addRule()
		order += 1
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.LayoutOrder = order
		rule.Size = UDim2.new(1, 0, 0, 1)
		rule.BackgroundColor3 = Color3.fromRGB(197, 194, 171)
		rule.BackgroundTransparency = 0.85
		rule.BorderSizePixel = 0
		rule.ZIndex = 35
		rule.Parent = body
	end

	addText("Category", "MENU PREVIEW", 12, COLORS.WarmAccent, 18)
	addText("Title", "A new beginning", 26, COLORS.Text, 34)
	addText("Summary", "A space for every update.", 17, COLORS.SecondaryText, 26)
	addRule()
	addText("WhatsNew", "WHAT’S NEW", 12, Color3.fromRGB(211, 189, 150), 18)
	addText("Item1", "New features and content appear here.", 16, COLORS.SecondaryText, 25, true)
	addText("Item2", "Scroll to read longer release notes.", 16, COLORS.SecondaryText, 25, true)
	addRule()
	addText("Improvements", "IMPROVEMENTS", 12, Color3.fromRGB(211, 189, 150), 18)
	addText("Item3", "Main menu visual integration prepared for live assets.", 16, COLORS.SecondaryText, 25, true)
	addText("Item4", "The patch feed will be connected to real release notes later.", 16, COLORS.SecondaryText, 25, true)

	local track = imageLabel(canvas, "PatchScrollTrack", "scroll_track", 1835, 764, 3, 220, 36)
	local thumb = imageLabel(canvas, "PatchScrollThumb", "scroll_thumb", 1835, 765, 3, 70, 37)
	if not Assets.Has("scroll_track") then
		track.BackgroundColor3 = COLORS.Divider
		track.BackgroundTransparency = 0.84
	end
	if not Assets.Has("scroll_thumb") then
		thumb.BackgroundColor3 = COLORS.Text
		thumb.BackgroundTransparency = 0.22
	end

	local function updateThumb()
		local viewH = math.max(1, body.AbsoluteSize.Y)
		local contentH = math.max(viewH, body.AbsoluteCanvasSize.Y)
		local trackH = 220
		local thumbH = math.clamp(math.floor(trackH * (viewH / contentH) + 0.5), 28, trackH)
		local maxScroll = math.max(1, contentH - viewH)
		local progress = math.clamp(body.CanvasPosition.Y / maxScroll, 0, 1)
		local travel = math.max(0, trackH - thumbH)
		thumb.Position = UDim2.fromOffset(1835, 764 + math.floor(travel * progress + 0.5))
		thumb.Size = UDim2.fromOffset(3, thumbH)
		thumb.Visible = contentH > viewH + 1
		track.Visible = thumb.Visible
	end

	body:GetPropertyChangedSignal("CanvasPosition"):Connect(updateThumb)
	body:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateThumb)
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateThumb)
	task.defer(updateThumb)

	return body, panel
end

local function makePlaceholderModal(canvas: Frame): (Frame, TextLabel, TextLabel, TextButton)
	local modal = Instance.new("Frame")
	modal.Name = "PlaceholderModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(520, 250)
	modal.BackgroundColor3 = Color3.fromRGB(10, 24, 21)
	modal.BackgroundTransparency = 0.04
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 100
	modal.Parent = canvas

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Divider
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.Parent = modal

	local title = textLabel(modal, "Title", "", 34, 28, 452, 42, 28, COLORS.Text, Enum.TextXAlignment.Left, 101)
	local message = textLabel(modal, "Message", "", 34, 84, 452, 78, 17, COLORS.SecondaryText, Enum.TextXAlignment.Left, 101)
	message.TextWrapped = true
	message.TextYAlignment = Enum.TextYAlignment.Top

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Position = UDim2.new(1, -150, 1, -60)
	close.Size = UDim2.fromOffset(116, 36)
	close.BackgroundColor3 = COLORS.Accent
	close.BorderSizePixel = 0
	close.Text = "Close"
	close.TextColor3 = COLORS.Text
	close.TextSize = 17
	close.Font = Enum.Font.Garamond
	close.AutoButtonColor = false
	close.ZIndex = 102
	close.Parent = modal
	close.MouseButton1Click:Connect(function()
		modal.Visible = false
	end)

	return modal, title, message, close
end

function MainMenuHUD.Create(screenGui: ScreenGui): {[string]: any}
	local root = Instance.new("Frame")
	root.Name = "MainMenuRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(3, 7, 7)
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.ZIndex = 1
	root.Parent = screenGui

	-- Layered animated environment. It is safe to install before its PNG IDs:
	-- when any required animated asset is missing, Ready=false and the approved
	-- static background below remains visible.
	local animatedBackground = MainMenuAnimatedBackground.Create(root)

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas1920x1080"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(CANVAS_W, CANVAS_H)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ZIndex = 3
	canvas.Parent = root

	local scale = Instance.new("UIScale")
	scale.Name = "ViewportScale"
	scale.Parent = canvas

	local function updateScale()
		local camera = Workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(CANVAS_W, CANVAS_H)
		scale.Scale = math.min(viewport.X / CANVAS_W, viewport.Y / CANVAS_H)
	end
	updateScale()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	-- Fullscreen art is intentionally OUTSIDE the fixed 1920x1080 content canvas.
	-- This prevents pillarboxing/black side bars on wider desktop viewports while
	-- keeping all HUD controls on the exact authored 1920x1080 layout grid.
	local background = Instance.new("ImageLabel")
	background.Name = "TemporaryBackground"
	background.Position = UDim2.fromScale(0, 0)
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundTransparency = 1
	background.BorderSizePixel = 0
	background.Image = Assets.Get("background")
	background.ScaleType = Enum.ScaleType.Crop
	background.ZIndex = 1
	background.Visible = not animatedBackground.Ready
	background.Parent = root
	if not Assets.Has("background") then
		background.BackgroundColor3 = Color3.fromRGB(17, 36, 31)
		background.BackgroundTransparency = 0
	end

	local shade = Instance.new("ImageLabel")
	shade.Name = "MenuShade"
	shade.Position = UDim2.fromScale(0, 0)
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Image = Assets.Get("menu_shade")
	shade.ScaleType = Enum.ScaleType.Crop
	shade.ZIndex = 2
	shade.Parent = root
	if not Assets.Has("menu_shade") then
		shade.BackgroundColor3 = Color3.fromRGB(3, 12, 10)
		shade.BackgroundTransparency = 0.35
	end

	local logo = imageLabel(canvas, "WAYLESSLogo", "logo", 74, 112, 498, 498, 6)
	local logoFallback = textLabel(canvas, "LogoFallback", "WAYLESS", 74, 260, 498, 120, 76, COLORS.Text, Enum.TextXAlignment.Center, 6)
	logoFallback.Font = Enum.Font.Garamond
	logoFallback.Visible = not Assets.Has("logo")
	logo.Visible = Assets.Has("logo")

	textLabel(canvas, "Tagline", "FORGE YOUR OWN PATH", 100, 574, 450, 24, 15, COLORS.Tagline, Enum.TextXAlignment.Center, 8)
	local rule = imageLabel(canvas, "SectionRule", "section_rule", 157, 614, 310, 4, 8)
	if not Assets.Has("section_rule") then
		rule.BackgroundColor3 = COLORS.WarmAccent
		rule.BackgroundTransparency = 0.25
	end

	local playButton, setPlayEnabled = makeStateButton(canvas, "Play", "Play", 145, 644, 358, 68, 10)
	local quickplayButton, setQuickplayEnabled = makeStateButton(canvas, "Quickplay", "Quickplay", 145, 724, 358, 68, 11)
	local creditsButton, setCreditsEnabled = makeStateButton(canvas, "Credits", "Credits", 145, 804, 358, 68, 12)
	local settingsButton, setSettingsEnabled = makeStateButton(canvas, "Settings", "Settings", 145, 884, 358, 68, 13)

	local patchBody, patchPanel = buildPatchNotes(canvas)

	textLabel(canvas, "FooterBrand", "WAYLESS", 68, 1027, 72, 18, 12, Color3.fromRGB(209, 212, 197), Enum.TextXAlignment.Left, 20).TextTransparency = 0.5
	local separator = Instance.new("Frame")
	separator.Name = "FooterSeparator"
	separator.Position = UDim2.fromOffset(143, 1030)
	separator.Size = UDim2.fromOffset(1, 12)
	separator.BackgroundColor3 = Color3.fromRGB(209, 212, 197)
	separator.BackgroundTransparency = 0.77
	separator.BorderSizePixel = 0
	separator.ZIndex = 20
	separator.Parent = canvas
	textLabel(canvas, "FooterSection", "MAIN MENU", 158, 1027, 180, 18, 11, Color3.fromRGB(209, 212, 197), Enum.TextXAlignment.Left, 20).TextTransparency = 0.5

	local modal, modalTitle, modalMessage, modalClose = makePlaceholderModal(canvas)

	local refs: {[string]: any} = {
		root = root,
		canvas = canvas,
		background = background,
		animatedBackground = animatedBackground,
		animatedBackgroundReady = animatedBackground.Ready,
		shade = shade,
		logo = logo,
		playButton = playButton,
		quickplayButton = quickplayButton,
		creditsButton = creditsButton,
		settingsButton = settingsButton,
		patchBody = patchBody,
		patchPanel = patchPanel,
		placeholderModal = modal,
		placeholderCloseButton = modalClose,
		setPlayEnabled = setPlayEnabled,
		setQuickplayEnabled = setQuickplayEnabled,
		setCreditsEnabled = setCreditsEnabled,
		setSettingsEnabled = setSettingsEnabled,
	}

	function refs.SetVisible(visible: boolean)
		root.Visible = visible
		animatedBackground.SetActive(visible)
		if visible then
			local lastType = UserInputService:GetLastInputType()
			if lastType == Enum.UserInputType.Gamepad1
				or lastType == Enum.UserInputType.Gamepad2
				or lastType == Enum.UserInputType.Gamepad3
				or lastType == Enum.UserInputType.Gamepad4 then
				GuiService.SelectedObject = playButton
			end
		else
			if GuiService.SelectedObject
				and GuiService.SelectedObject:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
			modal.Visible = false
		end
	end

	function refs.ShowPlaceholder(title: string, message: string)
		modalTitle.Text = title
		modalMessage.Text = message
		modal.Visible = true
	end

	function refs.SetBackgroundVisible(visible: boolean)
		if animatedBackground.Ready then
			animatedBackground.SetVisible(visible)
			background.Visible = false
		else
			background.Visible = visible
		end
	end

	-- Create() returns with the Main Menu visible; start animation immediately
	-- when the seven layered assets are present. showPage() will pause it whenever
	-- the player leaves the Main Menu.
	animatedBackground.SetActive(root.Visible)

	setQuickplayEnabled(false)
	return refs
end

return MainMenuHUD
