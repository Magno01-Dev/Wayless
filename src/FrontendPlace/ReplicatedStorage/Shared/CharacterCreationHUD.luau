--!strict
-- ReplicatedStorage > Shared > CharacterCreationHUD
-- WAYLESS Character Creation HUD v2 - static Astra text labels
-- Astra asset layout integration, 1920x1080 reference canvas.

local Workspace = game:GetService("Workspace")

-- Prefer the canonical runtime name, but support the imported filenames used
-- by the supplied WAYLESS asset modules. This prevents an infinite yield when
-- Studio keeps the .luau source filename as the ModuleScript name.
local assetsModule =
	script.Parent:FindFirstChild("CharacterCreationHUDAssets")
	or script.Parent:FindFirstChild("CharacterCreationHUDAssets_v2_FILLED")
	or script.Parent:FindFirstChild("CharacterCreationHUDAssets_v2_STATIC_ASTRA_LABELS")

if not assetsModule
	or not assetsModule:IsA("ModuleScript") then

	error(
		"[CharacterCreationHUD] CharacterCreationHUDAssets ModuleScript missing. "
			.. "Use CharacterCreationHUDAssets (preferred) or "
			.. "CharacterCreationHUDAssets_v2_FILLED."
	)
end

local Assets = require(assetsModule)

local CharacterCreationHUD = {}

local CANVAS_W = 1920
local CANVAS_H = 1080
local INK = Color3.fromRGB(48, 46, 40)
local ACCENT = Color3.fromRGB(133, 59, 52)
local PAPER = Color3.fromRGB(227, 218, 198)
local SCENE_HINT = Color3.fromRGB(236, 229, 216)

local function scaledRect(x: number, y: number, w: number, h: number): UDim2
	return UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
end

local function imageLabel(
	parent: Instance,
	name: string,
	assetKey: string,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number,
	fallback: Color3?
): ImageLabel
	local pos, size = scaledRect(x, y, w, h)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Position = pos
	image.Size = size
	-- Image assets must keep their own alpha. Never paint a code-generated
	-- rectangle behind the PNG (the scroll panels already contain their
	-- complete visual treatment).
	image.BackgroundColor3 = fallback or Color3.new(1, 1, 1)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = Assets.Get(assetKey)
	image.ScaleType = Enum.ScaleType.Stretch
	image.ZIndex = z
	image.Parent = parent
	return image
end

local function imageButton(
	parent: Instance,
	name: string,
	assetKey: string,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number
): ImageButton
	local pos, size = scaledRect(x, y, w, h)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.Position = pos
	button.Size = size
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Image = Assets.Get(assetKey)
	button.ScaleType = Enum.ScaleType.Stretch
	button.AutoButtonColor = false
	button.ZIndex = z
	button.Parent = parent
	return button
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
	alignment: Enum.TextXAlignment?,
	z: number
): TextLabel
	local pos, size = scaledRect(x, y, w, h)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = pos
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = INK
	label.TextSize = textSize
	label.Font = Enum.Font.Garamond
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = z
	label.Parent = parent
	return label
end

local function selector(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	initialText: string,
	valueIsButton: boolean?
): (ImageButton, TextLabel | TextButton, ImageButton)
	imageLabel(parent, name .. "Background", "selector", x, y, w, h, 112, PAPER)

	local arrowW = math.floor(math.min(42, h))
	local left = imageButton(parent, name .. "Left", "arrow_left", x + 5, y + 5, arrowW - 8, h - 10, 115)
	local right = imageButton(parent, name .. "Right", "arrow_right", x + w - arrowW + 3, y + 5, arrowW - 8, h - 10, 115)

	local value: TextLabel | TextButton
	if valueIsButton then
		local button = Instance.new("TextButton")
		button.Name = name .. "Value"
		button.Position = UDim2.fromOffset(x + arrowW, y)
		button.Size = UDim2.fromOffset(w - arrowW * 2, h)
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Text = initialText
		button.TextColor3 = INK
		button.TextSize = 21
		button.Font = Enum.Font.Garamond
		button.TextXAlignment = Enum.TextXAlignment.Center
		button.TextYAlignment = Enum.TextYAlignment.Center
		button.AutoButtonColor = false
		button.ZIndex = 116
		button.Parent = parent
		value = button
	else
		value = textLabel(
			parent,
			name .. "Value",
			initialText,
			x + arrowW,
			y,
			w - arrowW * 2,
			h,
			21,
			Enum.TextXAlignment.Center,
			116
		)
	end

	return left, value, right
end

local function createHairInput(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number
): TextBox
	local normal = imageLabel(parent, name .. "Background", "hair_input", x, y, w, h, 112, PAPER)
	local focused = imageLabel(parent, name .. "Focus", "hair_input_focus", x, y, w, h, 113, nil)
	focused.Visible = false

	local box = Instance.new("TextBox")
	box.Name = name
	box.Position = UDim2.fromOffset(x + 14, y)
	box.Size = UDim2.fromOffset(w - 28, h)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.PlaceholderText = "Enter Hair ID"
	box.PlaceholderColor3 = Color3.fromRGB(126, 118, 105)
	box.Text = ""
	box.TextColor3 = INK
	box.TextSize = 21
	box.Font = Enum.Font.Garamond
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.ZIndex = 116
	box.Parent = parent

	box.Focused:Connect(function()
		focused.Visible = true
		normal.ImageTransparency = 0.18
	end)

	box.FocusLost:Connect(function()
		focused.Visible = false
		normal.ImageTransparency = 0
	end)

	return box
end

local function createNameInput(parent: Instance): TextBox
	local x, y, w, h = 272, 198, 254, 44
	local normal = imageLabel(parent, "NameBackground", "hair_input", x, y, w, h, 112, PAPER)
	local focused = imageLabel(parent, "NameFocus", "hair_input_focus", x, y, w, h, 113, nil)
	focused.Visible = false

	local box = Instance.new("TextBox")
	box.Name = "ShinobiName"
	box.Position = UDim2.fromOffset(x + 14, y)
	box.Size = UDim2.fromOffset(w - 28, h)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.PlaceholderText = "Enter Name"
	box.PlaceholderColor3 = Color3.fromRGB(126, 118, 105)
	box.Text = ""
	box.TextColor3 = INK
	box.TextSize = 21
	box.Font = Enum.Font.Garamond
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.ZIndex = 116
	box.Parent = parent

	box.Focused:Connect(function()
		focused.Visible = true
		normal.ImageTransparency = 0.18
	end)

	box.FocusLost:Connect(function()
		focused.Visible = false
		normal.ImageTransparency = 0
	end)

	return box
end

local function actionButton(
	parent: Instance,
	name: string,
	assetKey: string,
	text: string,
	x: number,
	y: number,
	w: number,
	h: number
): ImageButton
	local button = imageButton(parent, name, assetKey, x, y, w, h, 120)
	button.BackgroundColor3 = assetKey == "primary" and ACCENT or PAPER
	button.BackgroundTransparency = Assets.Has(assetKey) and 1 or 0.05

	local label = textLabel(
		button,
		"Label",
		text,
		0,
		0,
		w,
		h,
		22,
		Enum.TextXAlignment.Center,
		121
	)
	label.Position = UDim2.fromScale(0, 0)
	label.TextColor3 = assetKey == "primary" and Color3.fromRGB(248, 242, 231) or INK
	return button
end

local function setDynamicIcon(icon: ImageLabel, assetKey: string)
	icon.Image = Assets.Get(assetKey)
	icon.BackgroundTransparency = 1
end

function CharacterCreationHUD.Create(screenGui: ScreenGui, page: Frame): {[string]: any}
	page.Parent = screenGui
	page.AnchorPoint = Vector2.new(0, 0)
	page.Position = UDim2.fromScale(0, 0)
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.ClipsDescendants = false
	page.ZIndex = 100

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas1920x1080"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(CANVAS_W, CANVAS_H)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ZIndex = 101
	canvas.Parent = page

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ViewportScale"
	uiScale.Scale = 1
	uiScale.Parent = canvas

	local function updateScale()
		local camera = Workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(CANVAS_W, CANVAS_H)
		uiScale.Scale = math.min(viewport.X / CANVAS_W, viewport.Y / CANVAS_H)
	end
	updateScale()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	imageLabel(canvas, "LeftPanel", "panel", 35, 26, 575, 967, 102, PAPER)
	imageLabel(canvas, "RightPanel", "panel", 1310, 26, 575, 967, 102, PAPER)
	imageLabel(canvas, "Title", "title", 611, 37, 698, 108, 104, nil)
	imageLabel(canvas, "TitleUnderline", "title_underline", 643, 149, 634, 15, 104, nil)

	local subtitle = textLabel(canvas, "Subtitle", "FORGE YOUR PATH. A HIGHER SELF AWAITS", 650, 164, 620, 28, 15, Enum.TextXAlignment.Center, 106)
	subtitle.TextColor3 = SCENE_HINT
	subtitle.Font = Enum.Font.Garamond

	local info = textLabel(canvas, "CreationInfo", "", 635, 192, 650, 34, 14, Enum.TextXAlignment.Center, 106)
	info.TextColor3 = Color3.fromRGB(220, 211, 195)
	info.TextWrapped = true

	local function heading(x: number, y: number, iconKey: string, headingKey: string, name: string)
		imageLabel(canvas, name .. "Wash", "heading_wash", x, y, 395, 67, 106, nil)
		imageLabel(canvas, name .. "Icon", iconKey, x + 4, y + 12, 48, 48, 107, nil)
		imageLabel(canvas, name .. "Heading", headingKey, x + 71, y + 3, 330, 59, 107, nil)
	end

	heading(121, 131, "icon_identity", "heading_identity", "Identity")
	heading(121, 376, "icon_skin", "heading_skin", "Skin")
	heading(121, 556, "icon_hair", "heading_hair", "Hair")
	heading(1396, 131, "icon_face", "heading_face", "Face")
	heading(1396, 450, "icon_clothing", "heading_clothing", "Clothing")
	heading(1396, 718, "icon_accessories", "heading_accessories", "Accessories")

	textLabel(canvas, "NameLabel", "Name", 125, 198, 125, 44, 23, Enum.TextXAlignment.Left, 116)
	local nameBox = createNameInput(canvas)

	imageLabel(canvas, "VillageLabel", "label_village", 125, 252, 150, 36, 116, nil)
	local villageLeft, villageValue, villageRight = selector(canvas, "Village", 272, 246, 197, 48, "Hidden Leaf", true)
	local villageIcon = imageLabel(canvas, "VillageIcon", "village_leaf", 479, 248, 44, 44, 116, nil)

	imageLabel(canvas, "NatureLabel", "label_nature", 125, 307, 150, 36, 116, nil)
	local natureLeft, natureValue, natureRight = selector(canvas, "Nature", 272, 300, 197, 48, "Fire", true)
	local natureIcon = imageLabel(canvas, "NatureIcon", "element_fire", 479, 302, 44, 44, 116, nil)

	imageLabel(canvas, "LeftSeparator1", "separator", 125, 354, 402, 10, 108, nil)
	imageLabel(canvas, "LeftSeparator2", "separator", 125, 539, 402, 10, 108, nil)

	local skinSwatchFrame = Instance.new("Frame")
	skinSwatchFrame.Name = "SkinSwatches"
	skinSwatchFrame.Position = UDim2.fromOffset(125, 459)
	skinSwatchFrame.Size = UDim2.fromOffset(402, 60)
	skinSwatchFrame.BackgroundTransparency = 1
	skinSwatchFrame.BorderSizePixel = 0
	skinSwatchFrame.Visible = true
	skinSwatchFrame.ClipsDescendants = false
	skinSwatchFrame.ZIndex = 140
	skinSwatchFrame.Parent = canvas

	local skinLayout = Instance.new("UIListLayout")
	skinLayout.FillDirection = Enum.FillDirection.Horizontal
	skinLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	skinLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	skinLayout.Padding = UDim.new(0, 6)
	skinLayout.SortOrder = Enum.SortOrder.LayoutOrder
	skinLayout.Parent = skinSwatchFrame

	local hairIdBoxes: {TextBox} = {}
	for index, y in ipairs({630, 687, 744, 801}) do
		imageLabel(
			canvas,
			"HairLabel" .. tostring(index),
			"label_hair_" .. tostring(index),
			125,
			y + 6,
			150,
			36,
			116,
			nil
		)
		table.insert(hairIdBoxes, createHairInput(canvas, "HairID" .. tostring(index), 271, y, 254, 48))
	end
	local hairHint = textLabel(canvas, "HairHint", "Paste a Roblox hair asset ID", 271, 854, 254, 26, 14, Enum.TextXAlignment.Center, 116)
	hairHint.TextColor3 = Color3.fromRGB(107, 94, 79)

	imageLabel(canvas, "EyesLabel", "label_eyes", 1400, 218, 150, 36, 116, nil)
	imageLabel(canvas, "BrowsLabel", "label_brows", 1400, 272, 150, 36, 116, nil)
	imageLabel(canvas, "NoseLabel", "label_nose", 1400, 326, 150, 36, 116, nil)
	imageLabel(canvas, "MouthLabel", "label_mouth", 1400, 380, 150, 36, 116, nil)

	local eyeLeft, eyeValue, eyeRight = selector(canvas, "Eyes", 1547, 215, 246, 48, "01 / 09", false)
	local browLeft, browValue, browRight = selector(canvas, "Brows", 1547, 269, 246, 48, "01 / 10", false)
	local noseLeft, noseValue, noseRight = selector(canvas, "Nose", 1547, 323, 246, 48, "01 / 10", false)
	local mouthLeft, mouthValue, mouthRight = selector(canvas, "Mouth", 1547, 377, 246, 48, "01 / 13", false)

	imageLabel(canvas, "RightSeparator1", "separator", 1400, 436, 402, 10, 108, nil)
	imageLabel(canvas, "RightSeparator2", "separator", 1400, 704, 402, 10, 108, nil)

	imageLabel(canvas, "ColorLabel", "label_color", 1400, 531, 150, 36, 116, nil)
	imageLabel(canvas, "TopLabel", "label_top", 1400, 585, 150, 36, 116, nil)
	imageLabel(canvas, "BottomLabel", "label_bottom", 1400, 639, 150, 36, 116, nil)
	local colorLeft, colorValue, colorRight = selector(canvas, "Color", 1547, 528, 246, 48, "01 / 17", false)
	local topLeft, topValue, topRight = selector(canvas, "Top", 1547, 582, 246, 48, "01 / 06", false)
	local bottomLeft, bottomValue, bottomRight = selector(canvas, "Bottom", 1547, 636, 246, 48, "01 / 06", false)

	imageLabel(canvas, "ShoesLabel", "label_shoes", 1400, 796, 150, 36, 116, nil)
	imageLabel(canvas, "GlovesLabel", "label_gloves", 1400, 849, 150, 36, 116, nil)
	local shoesLeft, shoesValue, shoesRight = selector(canvas, "Shoes", 1547, 793, 246, 48, "01 / 01", false)
	local glovesLeft, glovesValue, glovesRight = selector(canvas, "Gloves", 1547, 846, 246, 48, "NONE", false)

	imageLabel(canvas, "SceneControls", "scene_controls", 759, 920, 440, 52, 108, nil)

	local statusLabel = textLabel(canvas, "Status", "", 610, 971, 700, 20, 14, Enum.TextXAlignment.Center, 116)
	statusLabel.TextColor3 = SCENE_HINT

	local backButton = actionButton(canvas, "Back", "secondary", "Back", 606, 996, 197, 62)
	local cancelButton = actionButton(canvas, "Cancel", "secondary", "Cancel", 827, 996, 207, 62)
	local createButton = actionButton(canvas, "CreateCharacter", "primary", "Create Character", 1058, 996, 273, 62)

	-- Invisible compatibility controls. Drag + wheel are the visible scene controls.
	local hiddenControls = Instance.new("Frame")
	hiddenControls.Name = "CompatibilityControls"
	hiddenControls.Position = UDim2.fromOffset(-500, -500)
	hiddenControls.Size = UDim2.fromOffset(10, 10)
	hiddenControls.BackgroundTransparency = 1
	hiddenControls.Visible = true
	hiddenControls.Parent = canvas

	local function hiddenButton(name: string): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(1, 1)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.Parent = hiddenControls
		return b
	end

	local sceneHitbox = Instance.new("Frame")
	sceneHitbox.Name = "SceneHitbox"
	sceneHitbox.Position = UDim2.fromOffset(610, 218)
	sceneHitbox.Size = UDim2.fromOffset(700, 690)
	sceneHitbox.BackgroundTransparency = 1
	sceneHitbox.BorderSizePixel = 0
	sceneHitbox.Active = false
	sceneHitbox.ZIndex = 101
	sceneHitbox.Parent = canvas

	local refs: {[string]: any} = {
		canvas = canvas,
		info = info,
		statusLabel = statusLabel,
		nameBox = nameBox,
		skinSwatchFrame = skinSwatchFrame,
		hairIdBoxes = hairIdBoxes,
		sceneHitbox = sceneHitbox,
		villageLeftButton = villageLeft,
		villageValueButton = villageValue,
		villageRightButton = villageRight,
		natureLeftButton = natureLeft,
		natureValueButton = natureValue,
		natureRightButton = natureRight,
		villageIcon = villageIcon,
		natureIcon = natureIcon,
		eyeLeftButton = eyeLeft,
		eyeStyleValue = eyeValue,
		eyeRightButton = eyeRight,
		browLeftButton = browLeft,
		browStyleValue = browValue,
		browRightButton = browRight,
		noseLeftButton = noseLeft,
		noseStyleValue = noseValue,
		noseRightButton = noseRight,
		mouthLeftButton = mouthLeft,
		mouthStyleValue = mouthValue,
		mouthRightButton = mouthRight,
		colorLeftButton = colorLeft,
		colorValue = colorValue,
		colorRightButton = colorRight,
		topLeftButton = topLeft,
		starterTopValue = topValue,
		topRightButton = topRight,
		bottomLeftButton = bottomLeft,
		starterBottomValue = bottomValue,
		bottomRightButton = bottomRight,
		shoesLeftButton = shoesLeft,
		shoesStyleValue = shoesValue,
		shoesRightButton = shoesRight,
		glovesLeftButton = glovesLeft,
		glovesStyleValue = glovesValue,
		glovesRightButton = glovesRight,
		backButton = backButton,
		cancelButton = cancelButton,
		createButton = createButton,
		rotateLeftButton = hiddenButton("RotateLeft"),
		rotateRightButton = hiddenButton("RotateRight"),
		zoomInButton = hiddenButton("ZoomIn"),
		zoomOutButton = hiddenButton("ZoomOut"),
		resetViewButton = hiddenButton("ResetView"),
	}

	refs.setVillageIcon = function(displayName: string)
		local keyByName = {
			["Hidden Leaf"] = "village_leaf",
			["Hidden Sand"] = "village_sand",
			["Hidden Mist"] = "village_mist",
			["Hidden Stone"] = "village_stone",
			["Hidden Cloud"] = "village_cloud",
		}
		setDynamicIcon(villageIcon, keyByName[displayName] or "village_leaf")
	end

	refs.setNatureIcon = function(displayName: string)
		local keyByName = {
			Fire = "element_fire",
			Water = "element_water",
			Earth = "element_earth",
			Lightning = "element_lightning",
			Wind = "element_wind",
		}
		setDynamicIcon(natureIcon, keyByName[displayName] or "element_fire")
	end

	return refs
end

return CharacterCreationHUD
