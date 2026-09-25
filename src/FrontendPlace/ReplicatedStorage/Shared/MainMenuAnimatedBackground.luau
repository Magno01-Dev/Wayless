--!strict
-- ReplicatedStorage > Shared > MainMenuAnimatedBackground
-- WAYLESS layered animated main-menu background v1.
--
-- Source package: WAYLESS_Fondo_Animado.zip
-- Reference files: design.json + layout.json
-- Reference canvas: 1920 x 1080
--
-- The module uses only PNG ImageLabels and client-side animation. It does not
-- require VideoFrame. All authored coordinates remain in the 1920x1080 logical
-- canvas; the entire visual canvas is cover-scaled as one unit so the waterfall,
-- rocks, clouds, mist and birds stay aligned on non-16:9 displays.

local RunService = game:GetService("RunService")

local assetsModule =
	script.Parent:FindFirstChild("MainMenuHUDAssets")
	or script.Parent:FindFirstChild("MainMenuHUDAssets_v3_ANIMATED_PLACEHOLDERS")
	or script.Parent:FindFirstChild("MainMenuHUDAssets_v2_FILLED")

if not assetsModule or not assetsModule:IsA("ModuleScript") then
	error("[MainMenuAnimatedBackground] MainMenuHUDAssets ModuleScript missing")
end

local Assets = require(assetsModule)

local MainMenuAnimatedBackground = {}

local CANVAS_W = 1920
local CANVAS_H = 1080
local LOOP_SECONDS = 24
local TAU = math.pi * 2

local REQUIRED_KEYS = {
	"valley_clean",
	"cloud",
	"mist",
	"water_0",
	"water_1",
	"water_2",
	"birds",
}

local WATER = {
	x = 1137,
	y = 351,
	width = 250,
	height = 467,
	frameWidth = 256,
	frameHeight = 512,
	frameCount = 24,
	framesPerSheet = 8,
	fps = 12,
	opacity = 0.62,
}

local CLOUDS = {
	{
		x = 715,
		y = -15,
		width = 720,
		height = 144,
		amplitudeX = 105,
		phase = 0,
		opacity = 0.62,
	},
	{
		x = 1320,
		y = -12,
		width = 670,
		height = 110,
		amplitudeX = 70,
		phase = 2.1,
		opacity = 0.45,
	},
}

local MIST = {
	{
		x = 1050,
		y = 715,
		width = 460,
		height = 125,
		amplitudeX = 18,
		amplitudeY = 5,
		phase = 0,
		period = 12,
		opacity = 0.30,
	},
	{
		x = 1080,
		y = 750,
		width = 370,
		height = 90,
		amplitudeX = 24,
		amplitudeY = 4,
		phase = 2.2,
		period = 8,
		opacity = 0.24,
	},
}

local BIRDS = {
	frameWidth = 64,
	frameHeight = 32,
	frames = 8,
	flapSeconds = 0.6,
	travelSeconds = 24,
	fromX = 720,
	toX = 1740,
	baseY = 61,
	width = 18,
	height = 9,
	phases = { 0, 0.025, 0.052 },
	fadeFraction = 0.18,
}

local function allAssetsReady(): boolean
	for _, key in ipairs(REQUIRED_KEYS) do
		if not Assets.Has(key) then
			return false
		end
	end
	return true
end

local function newImage(
	parent: Instance,
	name: string,
	key: string,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number,
	opacity: number?
): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Position = UDim2.fromOffset(x, y)
	image.Size = UDim2.fromOffset(w, h)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = Assets.Get(key)
	image.ScaleType = Enum.ScaleType.Stretch
	image.ImageTransparency = 1 - math.clamp(opacity or 1, 0, 1)
	image.ZIndex = z
	image.Parent = parent
	return image
end

local function applyWaterFrame(image: ImageLabel, frameIndex: number, opacity: number)
	local normalized = frameIndex % WATER.frameCount
	local sheetIndex = math.floor(normalized / WATER.framesPerSheet)
	local localIndex = normalized % WATER.framesPerSheet
	local column = localIndex % 4
	local row = math.floor(localIndex / 4)

	image.Image = Assets.Get("water_" .. tostring(sheetIndex))
	image.ImageRectSize = Vector2.new(WATER.frameWidth, WATER.frameHeight)
	image.ImageRectOffset = Vector2.new(
		column * WATER.frameWidth,
		row * WATER.frameHeight
	)
	image.ImageTransparency = 1 - math.clamp(opacity, 0, 1)
end

function MainMenuAnimatedBackground.Create(parent: Frame): {[string]: any}
	local ready = allAssetsReady()

	local visualRoot = Instance.new("Frame")
	visualRoot.Name = "AnimatedBackgroundRoot"
	visualRoot.Size = UDim2.fromScale(1, 1)
	visualRoot.BackgroundTransparency = 1
	visualRoot.BorderSizePixel = 0
	visualRoot.ClipsDescendants = true
	visualRoot.ZIndex = 1
	visualRoot.Visible = ready
	visualRoot.Parent = parent

	local canvas = Instance.new("Frame")
	canvas.Name = "AnimatedCanvas1920x1080"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(CANVAS_W, CANVAS_H)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ZIndex = 1
	canvas.Parent = visualRoot

	local coverScale = Instance.new("UIScale")
	coverScale.Name = "CoverScale"
	coverScale.Parent = canvas

	local base = newImage(canvas, "ValleyClean", "valley_clean", 0, 0, CANVAS_W, CANVAS_H, 1, 1)

	local cloudImages = {}
	for i, spec in ipairs(CLOUDS) do
		local image = newImage(
			canvas,
			"Cloud" .. tostring(i),
			"cloud",
			spec.x,
			spec.y,
			spec.width,
			spec.height,
			2,
			spec.opacity
		)
		table.insert(cloudImages, image)
	end

	local waterA = newImage(
		canvas,
		"WaterFrameA",
		"water_0",
		WATER.x,
		WATER.y,
		WATER.width,
		WATER.height,
		3,
		WATER.opacity
	)
	local waterB = newImage(
		canvas,
		"WaterFrameB",
		"water_0",
		WATER.x,
		WATER.y,
		WATER.width,
		WATER.height,
		3,
		0
	)

	local mistImages = {}
	for i, spec in ipairs(MIST) do
		local image = newImage(
			canvas,
			"Mist" .. tostring(i),
			"mist",
			spec.x,
			spec.y,
			spec.width,
			spec.height,
			4,
			spec.opacity
		)
		table.insert(mistImages, image)
	end

	local birdImages = {}
	for i = 1, #BIRDS.phases do
		local image = newImage(
			canvas,
			"Bird" .. tostring(i),
			"birds",
			BIRDS.fromX,
			BIRDS.baseY,
			BIRDS.width,
			BIRDS.height,
			5,
			0
		)
		image.ImageRectSize = Vector2.new(BIRDS.frameWidth, BIRDS.frameHeight)
		table.insert(birdImages, image)
	end

	local function updateCoverScale()
		local viewport = parent.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		coverScale.Scale = math.max(viewport.X / CANVAS_W, viewport.Y / CANVAS_H)
	end

	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCoverScale)
	task.defer(updateCoverScale)

	local elapsed = 0
	local renderConnection: RBXScriptConnection? = nil
	local active = false
	local backgroundVisible = true

	local function render(t: number)
		local loopT = t % LOOP_SECONDS

		-- Clouds: 24-second horizontal sinusoidal drift.
		for i, spec in ipairs(CLOUDS) do
			local x = spec.x
				+ spec.amplitudeX
				* math.sin((TAU * loopT / LOOP_SECONDS) + spec.phase)
			cloudImages[i].Position = UDim2.fromOffset(x, spec.y)
			cloudImages[i].ImageTransparency = 1 - spec.opacity
		end

		-- Water: 12 fps / 24 frames, cross-faded between adjacent frames.
		local waterFrame = (loopT * WATER.fps) % WATER.frameCount
		local currentIndex = math.floor(waterFrame)
		local alpha = waterFrame - currentIndex
		local nextIndex = (currentIndex + 1) % WATER.frameCount
		applyWaterFrame(waterA, currentIndex, WATER.opacity * (1 - alpha))
		applyWaterFrame(waterB, nextIndex, WATER.opacity * alpha)

		-- Mist: independent sinusoidal x/y drift and subtle breathing opacity.
		for i, spec in ipairs(MIST) do
			local p = (TAU * loopT / spec.period) + spec.phase
			local x = spec.x + spec.amplitudeX * math.sin(p)
			local y = spec.y + spec.amplitudeY * math.cos(p)
			local opacity = spec.opacity * (0.82 + 0.18 * math.sin(p))
			mistImages[i].Position = UDim2.fromOffset(x, y)
			mistImages[i].ImageTransparency = 1 - math.clamp(opacity, 0, 1)
		end

		-- Birds: three phase-offset birds travel across the sky over 24 seconds.
		for zeroIndex = 0, #BIRDS.phases - 1 do
			local phase = BIRDS.phases[zeroIndex + 1]
			local u = ((loopT / BIRDS.travelSeconds) + phase) % 1
			local x = BIRDS.fromX + (BIRDS.toX - BIRDS.fromX) * u
			local y = BIRDS.baseY + zeroIndex * 13 + 5 * math.sin(TAU * u)
			local fade = math.max(
				0,
				math.min(
					1,
					u / BIRDS.fadeFraction,
					(1 - u) / BIRDS.fadeFraction
				)
			)
			local opacity = 0.7 * fade
			local flapPhase = ((loopT / BIRDS.flapSeconds) + zeroIndex * 0.16) % 1
			local frame = math.clamp(math.floor(flapPhase * BIRDS.frames), 0, BIRDS.frames - 1)
			local image = birdImages[zeroIndex + 1]
			image.Position = UDim2.fromOffset(x, y)
			image.ImageRectOffset = Vector2.new(frame * BIRDS.frameWidth, 0)
			image.ImageTransparency = 1 - opacity
		end
	end

	local function disconnectRender()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
	end

	local function refreshRunningState()
		local shouldRun = ready and active and backgroundVisible and visualRoot.Visible
		if shouldRun then
			if not renderConnection then
				renderConnection = RunService.RenderStepped:Connect(function(dt: number)
					elapsed += dt
					render(elapsed)
				end)
			end
		else
			disconnectRender()
		end
	end

	-- Seed all sprite rectangles and positions immediately.
	render(0)

	local refs: {[string]: any} = {
		root = visualRoot,
		canvas = canvas,
		base = base,
		waterA = waterA,
		waterB = waterB,
		clouds = cloudImages,
		mist = mistImages,
		birds = birdImages,
		Ready = ready,
	}

	function refs.SetActive(value: boolean)
		active = value
		refreshRunningState()
	end

	function refs.SetVisible(value: boolean)
		backgroundVisible = value
		visualRoot.Visible = ready and value
		refreshRunningState()
	end

	function refs.Destroy()
		disconnectRender()
		visualRoot:Destroy()
	end

	return refs
end

function MainMenuAnimatedBackground.AssetsReady(): boolean
	return allAssetsReady()
end

return MainMenuAnimatedBackground
