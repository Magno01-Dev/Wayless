--!strict
-- RyoHUDController v2 - Astra RyoHUD integration candidate
-- StarterPlayer > StarterPlayerScripts > RyoHUDController [LocalScript]
--
-- Presentation is defined by the user-supplied Astra RyoHUD package.
-- Currency remains server-authoritative through Player attribute "Ryo".
-- This client only renders confirmed balance changes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ATTRIBUTE_NAME = "Ryo"

-- Intentionally empty until the processed Astra assets are uploaded by the
-- experience owner/group and their real Roblox Image Asset IDs are supplied.
local MONEY_FRAME_IMAGE = ""
local CLOUD_ENGRAVING_IMAGE = ""

local REFERENCE_WIDTH = 1920
local REFERENCE_HEIGHT = 1080

local HUD_WIDTH = 205
local HUD_HEIGHT = 56
local RIGHT_OFFSET = 10
local BOTTOM_OFFSET = 24

local SURFACE_X = 19.27
local SURFACE_Y = 14.84
local SURFACE_WIDTH = 167.28
local SURFACE_HEIGHT = 24.64
local CLOUD_TILE_SIZE = 78

local DELTA_DURATION_IN = 0.225
local DELTA_DURATION_HOLD_RISE = 0.750
local DELTA_DURATION_OUT = 0.525

local TITLE_FONT = Font.new("rbxasset://fonts/families/Fondamento.json")
local NUMBERS_FONT = Font.new("rbxasset://fonts/families/Merriweather.json")

local COLOR_SURFACE = Color3.fromRGB(18, 24, 25)
local COLOR_BALANCE = Color3.fromRGB(243, 233, 214)
local COLOR_CURRENCY = Color3.fromRGB(198, 180, 147)
local COLOR_GAIN = Color3.fromRGB(165, 203, 176)
local COLOR_SPEND = Color3.fromRGB(211, 154, 142)

local SURFACE_TRANSPARENCY = 0.52
local CLOUD_TRANSPARENCY = 0.55

local oldGui = playerGui:FindFirstChild("RyoHUD")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "RyoHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Keep the stable Container name because other HUD systems use its absolute
-- screen bounds to avoid overlap.
local root = Instance.new("Frame")
root.Name = "Container"
root.AnchorPoint = Vector2.new(1, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.ClipsDescendants = false
root.Parent = gui

-- The outer Container is sized in rendered pixels. The inner Canvas holds the
-- exact 1920x1080 reference-space layout and receives the package UIScale.
local canvas = Instance.new("Frame")
canvas.Name = "Canvas"
canvas.Position = UDim2.fromOffset(0, 0)
canvas.Size = UDim2.fromOffset(HUD_WIDTH, HUD_HEIGHT)
canvas.BackgroundTransparency = 1
canvas.BorderSizePixel = 0
canvas.ClipsDescendants = false
canvas.Parent = root

local uiScale = Instance.new("UIScale")
uiScale.Name = "ReferenceScale"
uiScale.Scale = 1
uiScale.Parent = canvas

local surface = Instance.new("Frame")
surface.Name = "Surface"
surface.Position = UDim2.fromOffset(SURFACE_X, SURFACE_Y)
surface.Size = UDim2.fromOffset(SURFACE_WIDTH, SURFACE_HEIGHT)
surface.BackgroundTransparency = 1
surface.BorderSizePixel = 0
surface.ClipsDescendants = false
surface.ZIndex = 1
surface.Parent = canvas

type Point = {
	x: number,
	y: number,
}

local SURFACE_POLYGON: {Point} = {
	{x = 1, y = 0},
	{x = 99, y = 0},
	{x = 100, y = 10},
	{x = 100, y = 90},
	{x = 99, y = 100},
	{x = 20, y = 100},
	{x = 13, y = 80},
	{x = 0, y = 70},
	{x = 0, y = 10},
}

local function getPolygonSpanAtY(yPixels: number): (number, number)
	local yPercent = (yPixels / SURFACE_HEIGHT) * 100
	local intersections: {number} = {}

	for index = 1, #SURFACE_POLYGON do
		local a = SURFACE_POLYGON[index]
		local b = SURFACE_POLYGON[(index % #SURFACE_POLYGON) + 1]

		if a.y ~= b.y then
			local minY = math.min(a.y, b.y)
			local maxY = math.max(a.y, b.y)

			if yPercent >= minY and yPercent < maxY then
				local t = (yPercent - a.y) / (b.y - a.y)
				local xPercent = a.x + (b.x - a.x) * t
				table.insert(intersections, xPercent)
			end
		end
	end

	table.sort(intersections)

	if #intersections < 2 then
		return 0, 0
	end

	local left = (intersections[1] / 100) * SURFACE_WIDTH
	local right = (intersections[#intersections] / 100) * SURFACE_WIDTH
	return left, right
end

-- Roblox has no CSS clip-path. Rasterize the exact Astra polygon with
-- horizontal reference-pixel strips. Each strip clips the same globally
-- aligned tiled cloud image, so the texture does not restart at polygon edges.
local stripCount = math.ceil(SURFACE_HEIGHT)
for stripIndex = 0, stripCount - 1 do
	local y = stripIndex
	local stripHeight = math.min(1, SURFACE_HEIGHT - y)
	if stripHeight <= 0 then
		break
	end

	local left, right = getPolygonSpanAtY(y + stripHeight * 0.5)
	local width = math.max(0, right - left)

	if width > 0 then
		local strip = Instance.new("Frame")
		strip.Name = string.format("MaskStrip_%02d", stripIndex + 1)
		strip.Position = UDim2.fromOffset(left, y)
		strip.Size = UDim2.fromOffset(width, stripHeight)
		strip.BackgroundColor3 = COLOR_SURFACE
		strip.BackgroundTransparency = SURFACE_TRANSPARENCY
		strip.BorderSizePixel = 0
		strip.ClipsDescendants = true
		strip.ZIndex = 1
		strip.Parent = surface

		local clouds = Instance.new("ImageLabel")
		clouds.Name = "Clouds"
		clouds.Position = UDim2.fromOffset(-left, -y)
		clouds.Size = UDim2.fromOffset(SURFACE_WIDTH, SURFACE_HEIGHT)
		clouds.BackgroundTransparency = 1
		clouds.BorderSizePixel = 0
		clouds.Image = CLOUD_ENGRAVING_IMAGE
		clouds.ImageTransparency = CLOUD_TRANSPARENCY
		clouds.ScaleType = Enum.ScaleType.Tile
		clouds.TileSize = UDim2.fromOffset(CLOUD_TILE_SIZE, CLOUD_TILE_SIZE)
		clouds.ZIndex = 2
		clouds.Parent = strip
	end
end

local frame = Instance.new("ImageLabel")
frame.Name = "Frame"
frame.Position = UDim2.fromOffset(0, 0)
frame.Size = UDim2.fromOffset(HUD_WIDTH, HUD_HEIGHT)
frame.BackgroundTransparency = 1
frame.BorderSizePixel = 0
frame.Image = MONEY_FRAME_IMAGE
frame.ImageTransparency = 0
frame.ScaleType = Enum.ScaleType.Stretch
frame.ZIndex = 3
frame.Parent = canvas

local balanceGroup = Instance.new("Frame")
balanceGroup.Name = "BalanceGroup"
balanceGroup.Position = UDim2.fromOffset(60, 15.12)
balanceGroup.Size = UDim2.fromOffset(119, 23.52)
balanceGroup.BackgroundTransparency = 1
balanceGroup.BorderSizePixel = 0
balanceGroup.ZIndex = 4
balanceGroup.Parent = canvas

local balanceLayout = Instance.new("UIListLayout")
balanceLayout.Name = "Layout"
balanceLayout.FillDirection = Enum.FillDirection.Horizontal
balanceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
balanceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
balanceLayout.SortOrder = Enum.SortOrder.LayoutOrder
balanceLayout.Padding = UDim.new(0, 6)
balanceLayout.Parent = balanceGroup

local balanceLabel = Instance.new("TextLabel")
balanceLabel.Name = "Balance"
balanceLabel.LayoutOrder = 1
balanceLabel.AutomaticSize = Enum.AutomaticSize.X
balanceLabel.Size = UDim2.new(0, 0, 1, 0)
balanceLabel.BackgroundTransparency = 1
balanceLabel.BorderSizePixel = 0
balanceLabel.FontFace = NUMBERS_FONT
balanceLabel.Text = "0"
balanceLabel.TextColor3 = COLOR_BALANCE
balanceLabel.TextSize = 14
balanceLabel.TextScaled = false
balanceLabel.TextWrapped = false
balanceLabel.TextXAlignment = Enum.TextXAlignment.Center
balanceLabel.TextYAlignment = Enum.TextYAlignment.Center
balanceLabel.ZIndex = 4
balanceLabel.Parent = balanceGroup

local currencyLabel = Instance.new("TextLabel")
currencyLabel.Name = "Currency"
currencyLabel.LayoutOrder = 2
currencyLabel.AutomaticSize = Enum.AutomaticSize.X
currencyLabel.Size = UDim2.new(0, 0, 1, 0)
currencyLabel.BackgroundTransparency = 1
currencyLabel.BorderSizePixel = 0
currencyLabel.FontFace = TITLE_FONT
currencyLabel.Text = "Ryo"
currencyLabel.TextColor3 = COLOR_CURRENCY
currencyLabel.TextSize = 14
currencyLabel.TextScaled = false
currencyLabel.TextWrapped = false
currencyLabel.TextXAlignment = Enum.TextXAlignment.Center
currencyLabel.TextYAlignment = Enum.TextYAlignment.Center
currencyLabel.ZIndex = 4
currencyLabel.Parent = balanceGroup

local deltaRoot = Instance.new("Frame")
deltaRoot.Name = "Delta"
deltaRoot.Position = UDim2.fromOffset(60, -10)
deltaRoot.Size = UDim2.fromOffset(119, 20)
deltaRoot.BackgroundTransparency = 1
deltaRoot.BorderSizePixel = 0
deltaRoot.ClipsDescendants = false
deltaRoot.ZIndex = 5
deltaRoot.Parent = canvas

local deltaMover = Instance.new("Frame")
deltaMover.Name = "Mover"
deltaMover.Position = UDim2.fromOffset(0, 5)
deltaMover.Size = UDim2.fromScale(1, 1)
deltaMover.BackgroundTransparency = 1
deltaMover.BorderSizePixel = 0
deltaMover.ZIndex = 5
deltaMover.Parent = deltaRoot

local deltaShadow = Instance.new("TextLabel")
deltaShadow.Name = "Shadow"
deltaShadow.Position = UDim2.fromOffset(0, 1)
deltaShadow.Size = UDim2.fromScale(1, 1)
deltaShadow.BackgroundTransparency = 1
deltaShadow.BorderSizePixel = 0
deltaShadow.FontFace = NUMBERS_FONT
deltaShadow.Text = ""
deltaShadow.TextColor3 = Color3.new(0, 0, 0)
deltaShadow.TextSize = 14
deltaShadow.TextScaled = false
deltaShadow.TextTransparency = 1
deltaShadow.TextXAlignment = Enum.TextXAlignment.Center
deltaShadow.TextYAlignment = Enum.TextYAlignment.Center
deltaShadow.ZIndex = 5
deltaShadow.Parent = deltaMover

local deltaLabel = Instance.new("TextLabel")
deltaLabel.Name = "Text"
deltaLabel.Position = UDim2.fromOffset(0, 0)
deltaLabel.Size = UDim2.fromScale(1, 1)
deltaLabel.BackgroundTransparency = 1
deltaLabel.BorderSizePixel = 0
deltaLabel.FontFace = NUMBERS_FONT
deltaLabel.Text = ""
deltaLabel.TextColor3 = COLOR_GAIN
deltaLabel.TextSize = 14
deltaLabel.TextScaled = false
deltaLabel.TextTransparency = 1
deltaLabel.TextXAlignment = Enum.TextXAlignment.Center
deltaLabel.TextYAlignment = Enum.TextYAlignment.Center
deltaLabel.ZIndex = 6
deltaLabel.Parent = deltaMover

local connections: {RBXScriptConnection} = {}
local cameraViewportConnection: RBXScriptConnection? = nil
local currentTween: Tween? = nil
local destroyed = false

local function track(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, connection)
	return connection
end

local function formatNumber(value: number): string
	local text = tostring(value)
	local formatted = text

	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end

	return formatted
end

local function isValidBalance(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
		and value % 1 == 0
end

local function getReferenceScale(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end

	return math.min(viewport.X / REFERENCE_WIDTH, viewport.Y / REFERENCE_HEIGHT)
end

local function updateScaleAndPlacement()
	local scale = getReferenceScale()
	uiScale.Scale = scale
	root.Position = UDim2.new(1, -RIGHT_OFFSET * scale, 1, -BOTTOM_OFFSET * scale)
	root.Size = UDim2.fromOffset(HUD_WIDTH * scale, HUD_HEIGHT * scale)
end

local function bindCurrentCamera()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScaleAndPlacement)
	end

	updateScaleAndPlacement()
end

track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera))
bindCurrentCamera()

local reducedMotion = false
local reducedMotionConnection: RBXScriptConnection? = nil

do
	local okService, userGameSettings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)

	if okService and userGameSettings then
		local okValue, value = pcall(function()
			return (userGameSettings :: any).ReducedMotion
		end)

		if okValue and typeof(value) == "boolean" then
			reducedMotion = value

			local okSignal, signal = pcall(function()
				return (userGameSettings :: any):GetPropertyChangedSignal("ReducedMotion")
			end)

			if okSignal and signal then
				reducedMotionConnection = signal:Connect(function()
					local okUpdated, updated = pcall(function()
						return (userGameSettings :: any).ReducedMotion
					end)
					if okUpdated and typeof(updated) == "boolean" then
						reducedMotion = updated
					end
				end)
			end
		end
	end
end

local function setDeltaTransparency(value: number)
	deltaLabel.TextTransparency = value
	-- Package specifies a 0,+1 shadow offset; keep it deliberately subtle.
	deltaShadow.TextTransparency = math.clamp(value + 0.55, 0, 1)
end

local function tweenDelta(duration: number, yOffset: number, transparency: number): boolean
	if destroyed then
		return false
	end

	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	local tween = TweenService:Create(
		deltaMover,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{Position = UDim2.fromOffset(0, yOffset)}
	)
	currentTween = tween

	local textTween = TweenService:Create(
		deltaLabel,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{TextTransparency = transparency}
	)

	local shadowTarget = math.clamp(transparency + 0.55, 0, 1)
	local shadowTween = TweenService:Create(
		deltaShadow,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{TextTransparency = shadowTarget}
	)

	tween:Play()
	textTween:Play()
	shadowTween:Play()
	tween.Completed:Wait()

	if currentTween == tween then
		currentTween = nil
	end

	return not destroyed
end

local deltaQueue: {number} = {}
local deltaBusy = false

local function sameSign(a: number, b: number): boolean
	return (a > 0 and b > 0) or (a < 0 and b < 0)
end

local playNextDelta: () -> ()

local function playDelta(delta: number)
	if destroyed then
		return
	end

	local magnitude = math.abs(delta)
	local text = if delta > 0
		then "+" .. formatNumber(magnitude)
		else "−" .. formatNumber(magnitude)

	local color = if delta > 0 then COLOR_GAIN else COLOR_SPEND
	deltaLabel.Text = text
	deltaShadow.Text = text
	deltaLabel.TextColor3 = color

	deltaMover.Position = UDim2.fromOffset(0, if reducedMotion then 0 else 5)
	setDeltaTransparency(1)

	if reducedMotion then
		if not tweenDelta(DELTA_DURATION_IN, 0, 0) then
			return
		end
		task.wait(DELTA_DURATION_HOLD_RISE)
		if destroyed then
			return
		end
		tweenDelta(DELTA_DURATION_OUT, 0, 1)
	else
		if not tweenDelta(DELTA_DURATION_IN, 0, 0) then
			return
		end
		if not tweenDelta(DELTA_DURATION_HOLD_RISE, -9, 0) then
			return
		end
		tweenDelta(DELTA_DURATION_OUT, -15, 1)
	end
end

playNextDelta = function()
	if destroyed or deltaBusy or #deltaQueue == 0 then
		return
	end

	deltaBusy = true
	local delta = table.remove(deltaQueue, 1)

	task.spawn(function()
		playDelta(delta)
		deltaBusy = false
		if not destroyed then
			playNextDelta()
		end
	end)
end

local function enqueueDelta(delta: number)
	if delta == 0 then
		return
	end

	-- Only waiting notices merge. Never merge into the notice currently visible,
	-- and never cancel a gain against a spend.
	if #deltaQueue > 0 then
		local lastIndex = #deltaQueue
		local lastDelta = deltaQueue[lastIndex]
		if sameSign(lastDelta, delta) then
			deltaQueue[lastIndex] = lastDelta + delta
			return
		end
	end

	table.insert(deltaQueue, delta)
	playNextDelta()
end

local currentBalance: number? = nil

local function SetBalance(authoritativeBalance: number, notify: boolean): boolean
	if not isValidBalance(authoritativeBalance) then
		warn("[RyoHUDController] rejected invalid authoritative balance:", authoritativeBalance)
		return false
	end

	local previous = currentBalance
	currentBalance = authoritativeBalance

	-- Astra contract: the visible balance changes immediately, before feedback.
	balanceLabel.Text = formatNumber(authoritativeBalance)

	if notify and previous ~= nil then
		local delta = authoritativeBalance - previous
		if delta ~= 0 then
			enqueueDelta(delta)
		end
	end

	return true
end

local function syncFromAttribute(notify: boolean)
	local value = player:GetAttribute(ATTRIBUTE_NAME)
	if isValidBalance(value) then
		SetBalance(value :: number, notify and currentBalance ~= nil)
	end
end

track(player:GetAttributeChangedSignal(ATTRIBUTE_NAME):Connect(function()
	syncFromAttribute(true)
end))

-- Initial authoritative sync is silent. If the server attribute has not arrived
-- yet, the first valid attribute update is also treated as initial sync.
syncFromAttribute(false)

if MONEY_FRAME_IMAGE == "" then
	warn("[RyoHUDController] MoneyFrame Image Asset ID is not set yet")
end

if CLOUD_ENGRAVING_IMAGE == "" then
	warn("[RyoHUDController] CloudEngraving Image Asset ID is not set yet")
end

track(script.Destroying:Connect(function()
	destroyed = true

	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end

	if reducedMotionConnection then
		reducedMotionConnection:Disconnect()
		reducedMotionConnection = nil
	end

	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
end))

print("[RyoHUDController] Astra RyoHUD candidate ready | Backend=Player.Ryo | Persistence unchanged")
