local TweenService = game:GetService("TweenService")

local Builder = {}

local BASE_OFFSET = Vector2.new(280, 10)
local STATUS_SCALE = 1.16
local STATUS_PIVOT = Vector2.new(831, 125) - BASE_OFFSET
local STATUS_TRANSLATE = Vector2.new(0, 24)
local CANVAS_SIZE = Vector2.new(1210, 239)
local BOTTOM_MARGIN = 40
local WIDTH_AT_1920 = 1100

local SLOT_LAYOUT = {
	{"1", 48, 136, 99, 99},
	{"2", 146, 136, 99, 99},
	{"3", 244, 136, 99, 99},
	{"4", 342, 136, 99, 99},
	{"5", 440, 136, 99, 99},
	{"6", 538, 136, 99, 99},
	{"7", 636, 136, 99, 99},
	{"8", 734, 136, 99, 99},
	{"9", 832, 136, 99, 99},
	{"0", 930, 136, 99, 99},
	{"G", 1051, 136, 99, 99},
}

local PRIMARY = {
	health = {
		sourcePosition = Vector2.new(449, 68),
		size = Vector2.new(348, 31.68602825745683),
		numberPosition = Vector2.new(709, 64),
		frame = "pair03_health_frame",
		track = "curved_health_track",
		fill = "curved_health_fill",
		trail = "curved_health_fill",
		clipAnchorRight = true,
		auraColor = Color3.fromRGB(161, 70, 73),
		outerAuraColor = Color3.fromRGB(116, 49, 54),
	},
	chakra = {
		sourcePosition = Vector2.new(865, 68),
		size = Vector2.new(348, 31.68602825745683),
		numberPosition = Vector2.new(894, 64),
		frame = "pair03_chakra_frame",
		track = "curved_chakra_track",
		fill = "curved_chakra_fill",
		trail = "curved_chakra_fill",
		clipAnchorRight = false,
		auraColor = Color3.fromRGB(91, 177, 242),
		outerAuraColor = Color3.fromRGB(47, 115, 176),
	},
}

local SECONDARY = {
	armor = {
		sourcePosition = Vector2.new(488, 97),
		size = Vector2.new(242, 15.191629955947137),
		numberPosition = Vector2.new(795, 105.79515418502203),
		frame = "pair03_armor_frame",
		track = "curved_armor_track",
		fill = "curved_armor_fill",
		trail = "curved_armor_fill",
		clipAnchorRight = false,
		textXAlignment = Enum.TextXAlignment.Right,
		auraColor = Color3.fromRGB(142, 146, 151),
		outerAuraColor = Color3.fromRGB(101, 105, 110),
	},
	stamina = {
		sourcePosition = Vector2.new(932, 97),
		size = Vector2.new(242, 15.191629955947137),
		numberPosition = Vector2.new(867, 105.79515418502203),
		frame = "pair03_stamina_frame",
		track = "curved_stamina_track",
		fill = "curved_stamina_fill",
		trail = "curved_stamina_fill",
		clipAnchorRight = false,
		textXAlignment = Enum.TextXAlignment.Left,
		auraColor = Color3.fromRGB(209, 161, 74),
		outerAuraColor = Color3.fromRGB(154, 113, 42),
	},
}

local LIFE_FORCE = {
	frameRect = {798, 29, 66, 92},
	energyRect = {807, 63, 48, 48},
	numberPosition = Vector2.new(831, 94),
}

local function v2(x, y)
	return Vector2.new(x, y)
end

local function applyStatusTransform(point)
	local localPoint = point - BASE_OFFSET
	return STATUS_PIVOT + (localPoint - STATUS_PIVOT) * STATUS_SCALE + STATUS_TRANSLATE
end

local function rectFromSource(x, y, w, h)
	local pos = applyStatusTransform(Vector2.new(x, y))
	return pos, Vector2.new(w, h) * STATUS_SCALE
end

local function makeFrame(parent, name, position, size, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(position.X, position.Y)
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function makeImage(parent, name, image, position, size, z)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = image or ""
	img.ScaleType = Enum.ScaleType.Stretch
	img.Position = UDim2.fromOffset(position.X, position.Y)
	img.Size = UDim2.fromOffset(size.X, size.Y)
	img.ZIndex = z or 1
	img.Parent = parent
	return img
end

local function makeText(parent, name, text, position, size, z)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text or ""
	label.Font = Enum.Font.Garamond
	label.TextColor3 = Color3.fromRGB(245, 239, 223)
	label.TextStrokeTransparency = 0.85
	label.TextScaled = false
	label.TextSize = 13
	label.TextWrapped = false
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.ZIndex = z or 1
	label.Parent = parent
	return label
end

local function setAnchor(guiObject, x, y)
	guiObject.AnchorPoint = Vector2.new(x, y)
	return guiObject
end

local function updateScale(root, scaleObject)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local targetWidth = viewport.X * (WIDTH_AT_1920 / 1920)
	scaleObject.Scale = targetWidth / CANVAS_SIZE.X
	root.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
end

local function createBar(parent, assets, id, config, zBase)
	local pos, size = rectFromSource(config.sourcePosition.X, config.sourcePosition.Y, config.size.X, config.size.Y)
	local holder = makeFrame(parent, id .. "Bar", pos, size, zBase)
	setAnchor(holder, 0, 0)

	local track = makeImage(holder, "Track", assets.Bars[config.track], v2(0, 0), size, zBase)
	local trailClip = makeFrame(holder, "TrailClip", v2(0, 0), size, zBase + 1)
	trailClip.ClipsDescendants = true
	trailClip.BackgroundTransparency = 1
	trailClip.Size = UDim2.fromScale(1, 1)
	if config.clipAnchorRight then
		trailClip.AnchorPoint = Vector2.new(1, 0)
		trailClip.Position = UDim2.fromScale(1, 0)
	end
	local trailImage = makeImage(trailClip, "TrailImage", assets.Bars[config.trail], v2(0, 0), size, zBase + 1)
	if config.clipAnchorRight then
		setAnchor(trailImage, 1, 0)
		trailImage.Position = UDim2.fromScale(1, 0)
	end
	local clip = makeFrame(holder, "Clip", v2(0, 0), size, zBase + 2)
	clip.ClipsDescendants = true
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	if config.clipAnchorRight then
		clip.AnchorPoint = Vector2.new(1, 0)
		clip.Position = UDim2.fromScale(1, 0)
	end
	local fillImage = makeImage(clip, "FillImage", assets.Bars[config.fill], v2(0, 0), size, zBase + 2)
	if config.clipAnchorRight then
		setAnchor(fillImage, 1, 0)
		fillImage.Position = UDim2.fromScale(1, 0)
	end

	local outerAura = makeImage(holder, "OuterAura", assets.Bars[config.fill], v2(-6, -6), size + v2(12, 12), zBase)
	outerAura.ImageColor3 = config.outerAuraColor
	outerAura.ImageTransparency = 1
	local aura = makeImage(holder, "Aura", assets.Bars[config.fill], v2(-3, -3), size + v2(6, 6), zBase + 1)
	aura.ImageColor3 = config.auraColor
	aura.ImageTransparency = 1

	local frame = makeImage(holder, "Frame", assets.Bars[config.frame], v2(0, 0), size, zBase + 3)
	track.ImageTransparency = 0
	frame.ImageTransparency = 0

	local labelPos = applyStatusTransform(config.numberPosition)
	local label = makeText(parent, id .. "Label", "0 / 0", labelPos + v2(0, -16), v2(120, 20), zBase + 4)
	setAnchor(label, 0.5, 0)
	if config.textXAlignment then
		label.TextXAlignment = config.textXAlignment
		setAnchor(label, config.textXAlignment == Enum.TextXAlignment.Right and 1 or 0, 0)
	end
	label.TextSize = if id == "health" or id == "chakra" then 15 else 12

	return {
		Holder = holder,
		Track = track,
		TrailClip = trailClip,
		TrailImage = trailImage,
		Clip = clip,
		FillImage = fillImage,
		Frame = frame,
		Aura = aura,
		OuterAura = outerAura,
		Label = label,
	}
end

local function createStateRenderer(parent, leftBarView, rightBarView)
	local state = {
		pitch = 26,
		iconSize = 24,
		gap = 6,
		maxVisible = 9,
		nodes = { benefit = {}, negative = {} },
	}

	local leftRow = makeFrame(parent, "BenefitStateRow", v2(leftBarView.Holder.Position.X.Offset, leftBarView.Holder.Position.Y.Offset - 28), v2(260, 28), 30)
	local rightRow = makeFrame(parent, "NegativeStateRow", v2(rightBarView.Holder.Position.X.Offset + rightBarView.Holder.Size.X.Offset - 260, rightBarView.Holder.Position.Y.Offset - 28), v2(260, 28), 30)
	state.rows = {
		benefit = leftRow,
		negative = rightRow,
	}

	local function makeNode(kind, id, icon)
		local row = state.rows[kind]
		local holder = makeFrame(row, kind .. "_" .. id, v2(0, 2), v2(24, 24), 30)
		local img = makeImage(holder, "Icon", icon, v2(0, 0), v2(24, 24), 30)
		img.ScaleType = Enum.ScaleType.Fit
		local stacks = makeText(holder, "Stacks", "", v2(14, 10), v2(18, 14), 31)
		stacks.TextSize = 11
		stacks.TextXAlignment = Enum.TextXAlignment.Right
		stacks.TextYAlignment = Enum.TextYAlignment.Bottom
		holder.BackgroundTransparency = 1
		holder.Visible = true
		return { Holder = holder, Icon = img, Stacks = stacks, Kind = kind, Id = id }
	end

	local function makeMarker(kind)
		local row = state.rows[kind]
		local marker = makeText(row, kind .. "Marker", "+0", v2(0, 2), v2(28, 24), 32)
		marker.TextSize = 14
		marker.Visible = false
		marker.TextStrokeTransparency = 0.75
		marker.TextColor3 = Color3.fromRGB(245, 239, 223)
		return marker
	end

	state.markers = {
		benefit = makeMarker("benefit"),
		negative = makeMarker("negative"),
	}

	local function targetPosition(kind, index)
		if kind == "benefit" then
			return UDim2.fromOffset((index - 1) * state.pitch, 2)
		else
			return UDim2.fromOffset(260 - state.iconSize - (index - 1) * state.pitch, 2)
		end
	end

	local function markerPosition(kind, overflowIndex)
		if kind == "benefit" then
			return UDim2.fromOffset((overflowIndex - 1) * state.pitch, 0)
		else
			return UDim2.fromOffset(260 - 28 - (overflowIndex - 1) * state.pitch, 0)
		end
	end

	function state:Render(activeList)
		local grouped = { benefit = {}, negative = {} }
		for _, entry in ipairs(activeList) do
			table.insert(grouped[entry.kind], entry)
		end

		for kind, list in pairs(grouped) do
			local visibleCount = math.min(#list, self.maxVisible)
			local visibleIds = {}
			for index = 1, visibleCount do
				local entry = list[index]
				visibleIds[entry.id] = true
				local node = self.nodes[kind][entry.id]
				local isNew = false
				if not node then
					node = makeNode(kind, entry.id, entry.icon)
					self.nodes[kind][entry.id] = node
					isNew = true
				end
				node.Icon.Image = entry.icon or ""
				node.Stacks.Text = entry.stacks and entry.stacks > 1 and ("x" .. tostring(entry.stacks)) or ""
				node.Holder.Visible = true
				if isNew then
					local startOffset = if kind == "benefit" then -self.iconSize else 260 + self.iconSize
					node.Holder.Position = UDim2.fromOffset(startOffset, 2)
				end
				TweenService:Create(node.Holder, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = targetPosition(kind, index),
				}):Play()
			end

			for id, node in pairs(self.nodes[kind]) do
				if not visibleIds[id] then
					node.Holder.Visible = false
				end
			end

			local overflow = math.max(0, #list - self.maxVisible)
			local marker = self.markers[kind]
			marker.Visible = overflow > 0
			if overflow > 0 then
				marker.Text = "+" .. tostring(overflow)
				marker.Position = markerPosition(kind, self.maxVisible + 1)
			end
		end
	end

	return state
end

function Builder.Build(playerGui, assets, options)
	options = options or {}
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = options.screenGuiName or "WAYLESSCombatHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local root = makeFrame(screenGui, "Root", v2(0, 0), CANVAS_SIZE, 1)
	setAnchor(root, 0.5, 1)
	local scaleObject = Instance.new("UIScale")
	scaleObject.Parent = root
	updateScale(root, scaleObject)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		updateScale(root, scaleObject)
	end)
	game:GetService("RunService").RenderStepped:Connect(function()
		updateScale(root, scaleObject)
	end)

	local bars = {
		health = createBar(root, assets, "health", PRIMARY.health, 10),
		chakra = createBar(root, assets, "chakra", PRIMARY.chakra, 10),
		armor = createBar(root, assets, "armor", SECONDARY.armor, 12),
		stamina = createBar(root, assets, "stamina", SECONDARY.stamina, 12),
	}

	local orbFramePos, orbFrameSize = rectFromSource(LIFE_FORCE.frameRect[1], LIFE_FORCE.frameRect[2], LIFE_FORCE.frameRect[3], LIFE_FORCE.frameRect[4])
	local orbEnergyPos, orbEnergySize = rectFromSource(LIFE_FORCE.energyRect[1], LIFE_FORCE.energyRect[2], LIFE_FORCE.energyRect[3], LIFE_FORCE.energyRect[4])
	local orb = {}
	orb.Frame = makeImage(root, "LifeForceFrame", assets.Bars.life_force_frame, orbFramePos, orbFrameSize, 18)
	orb.Flame = makeImage(root, "LifeForceFlame", assets.Animation.ring_sheet, orbFramePos + v2(-16, -10), orbFrameSize + v2(32, 20), 16)
	orb.Flame.ScaleType = Enum.ScaleType.Stretch
	orb.EnergyClip = makeFrame(root, "LifeForceEnergyClip", orbEnergyPos, orbEnergySize, 17)
	orb.EnergyClip.ClipsDescendants = true
	orb.Energy = makeImage(orb.EnergyClip, "LifeForceEnergy", assets.Animation.orb_volume ~= "" and assets.Animation.orb_volume or assets.Bars.life_force_energy, v2(0, 0), orbEnergySize, 17)
	orb.HitArea = makeFrame(root, "LifeForceHitArea", orbFramePos + v2(-12, -12), orbFrameSize + v2(24, 24), 19)
	orb.HitArea.BackgroundTransparency = 1
	orb.Percent = makeText(root, "LifeForcePercent", "0%", applyStatusTransform(LIFE_FORCE.numberPosition) + v2(0, 5), v2(54, 16), 20)
	setAnchor(orb.Percent, 0.5, 0)
	orb.Percent.TextSize = 12
	orb.Percent.Visible = false

	local slots = {}
	for _, info in ipairs(SLOT_LAYOUT) do
		local key, x, y, w, h = info[1], info[2], info[3], info[4], info[5]
		local slotRoot = makeFrame(root, "Slot" .. key, v2(x, y), v2(w, h), 4)
		local frameImage = makeImage(slotRoot, "FrameImage", assets.Slots.default, v2(0, 0), v2(w, h), 4)
		local itemImage = makeImage(slotRoot, "ItemImage", "", v2(12, 11), v2(w - 24, h - 24), 5)
		itemImage.ScaleType = Enum.ScaleType.Fit
		local shade = makeFrame(slotRoot, "Shade", v2(0, 0), v2(w, h), 6)
		shade.BackgroundTransparency = 1
		local timer = makeText(slotRoot, "Timer", "", v2(0, 33), v2(w, 20), 7)
		timer.TextSize = 20
		timer.TextXAlignment = Enum.TextXAlignment.Center
		timer.TextYAlignment = Enum.TextYAlignment.Center
		local keyLabel = makeText(slotRoot, "KeyLabel", key, v2(7, 2), v2(18, 16), 8)
		keyLabel.TextSize = 14
		keyLabel.TextXAlignment = Enum.TextXAlignment.Left
		keyLabel.TextYAlignment = Enum.TextYAlignment.Top
		slots[key] = {
			Root = slotRoot,
			FrameImage = frameImage,
			ItemImage = itemImage,
			Shade = shade,
			Timer = timer,
			KeyLabel = keyLabel,
		}
	end

	local stateRenderer = createStateRenderer(root, bars.health, bars.chakra)

	return {
		ScreenGui = screenGui,
		Root = root,
		Bars = bars,
		Orb = orb,
		Slots = slots,
		RenderStates = function(activeList)
			stateRenderer:Render(activeList)
		end,
		Destroy = function()
			screenGui:Destroy()
		end,
	}
end

return Builder
