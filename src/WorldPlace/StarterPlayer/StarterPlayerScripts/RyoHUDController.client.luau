--!strict
-- RyoHUDController - compact coin + lower ornament
-- StarterPlayer > StarterPlayerScripts > RyoHUDController [LocalScript]
--
-- Upload the two supplied PNGs and set their IDs below. Replace the existing LocalScript.
-- Currency remains server-authoritative through Player attribute "Ryo".
-- This client only renders confirmed balance changes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ATTRIBUTE_NAME = "Ryo"

-- Paste the numeric IDs between quotes (rbxassetid:// prefix also accepted).
local COIN_ASSET_ID = "128540275309363" -- RyoCoin.png
local TRIM_ASSET_ID = "119486248350752" -- RyoUnderline.png

local function assetUri(id: string): string
	if id == "" then return "" end
	if string.match(id, "^%d+$") then return "rbxassetid://" .. id end
	return id
end

local REFERENCE_WIDTH = 1920
local REFERENCE_HEIGHT = 1080

local HUD_WIDTH = 224
local HUD_HEIGHT = 48
local LEFT_OFFSET = 24
local BOTTOM_OFFSET = 24


local DELTA_DURATION_IN = 0.225
local DELTA_DURATION_HOLD_RISE = 0.750
local DELTA_DURATION_OUT = 0.525

local NUMBERS_FONT = Font.new("rbxasset://fonts/families/Merriweather.json")

local COLOR_SURFACE = Color3.fromRGB(18, 24, 25)
local COLOR_BALANCE = Color3.fromRGB(243, 233, 214)
local COLOR_GAIN = Color3.fromRGB(165, 203, 176)
local COLOR_SPEND = Color3.fromRGB(211, 154, 142)


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
root.AnchorPoint = Vector2.new(0, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.ClipsDescendants = false
root.Parent = gui

-- Fixed line height keeps comma descenders from changing vertical alignment.
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

-- Open-ended compact currency treatment; no legacy frame artwork.
local surface = Instance.new("Frame")
surface.Name = "Surface"
surface.Position = UDim2.fromOffset(0, 3)
surface.Size = UDim2.fromOffset(222, 35)
surface.BackgroundColor3 = Color3.fromRGB(20, 24, 21)
surface.BackgroundTransparency = 0
surface.BorderSizePixel = 0
surface.Parent = canvas
local fade = Instance.new("UIGradient")
fade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.16, 0.35),
	NumberSequenceKeypoint.new(0.70, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
fade.Parent = surface
-- Final PNGs already have transparent padding cropped. Do not crop them again.
local function artwork(name: string, id: string, x: number, y: number, w: number, h: number, z: number)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Position = UDim2.fromOffset(x, y)
	image.Size = UDim2.fromOffset(w, h)
	image.Image = assetUri(id)
	image.ScaleType = Enum.ScaleType.Stretch
	image.ZIndex = z
	image.Parent = canvas
	return image
end

-- Coin core: x=10, y=6.6, 28x27.8. Extra PNG padding holds its 0.8px outline.
artwork("RyoCoin", COIN_ASSET_ID, 9, 5.5982, 30, 29.8036, 3)
-- Cloud renders in front of the coin, as approved.
artwork("GoldAccent", TRIM_ASSET_ID, 2, 25, 216, 20, 4)

local balanceGroup = Instance.new("Frame")
balanceGroup.Name = "BalanceGroup"
balanceGroup.Position = UDim2.fromOffset(46, 4.5)
balanceGroup.Size = UDim2.fromOffset(168, 32)
balanceGroup.BackgroundTransparency = 1
balanceGroup.BorderSizePixel = 0
balanceGroup.ZIndex = 4
balanceGroup.Parent = canvas

local balanceLayout = Instance.new("UIListLayout")
balanceLayout.Name = "Layout"
balanceLayout.FillDirection = Enum.FillDirection.Horizontal
balanceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
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
balanceLabel.TextSize = 22
balanceLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 18)
balanceLabel.TextStrokeTransparency = 0.55
balanceLabel.TextScaled = false
balanceLabel.TextWrapped = false
balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
balanceLabel.TextYAlignment = Enum.TextYAlignment.Center
balanceLabel.ZIndex = 5
balanceLabel.Parent = balanceGroup

local deltaRoot = Instance.new("Frame")
deltaRoot.Name = "Delta"
deltaRoot.Position = UDim2.fromOffset(46, -20)
deltaRoot.Size = UDim2.fromOffset(168, 20)
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
deltaShadow.TextXAlignment = Enum.TextXAlignment.Left
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
deltaLabel.TextXAlignment = Enum.TextXAlignment.Left
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

	return math.clamp(math.min(viewport.X / REFERENCE_WIDTH, viewport.Y / REFERENCE_HEIGHT), 0.85, 1.15)
end

local function updateScaleAndPlacement()
	local scale = getReferenceScale()
	uiScale.Scale = scale
	root.Position = UDim2.new(0, LEFT_OFFSET * scale, 1, -BOTTOM_OFFSET * scale)
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

if COIN_ASSET_ID == "" or TRIM_ASSET_ID == "" then
	warn("[RyoHUDController] Set COIN_ASSET_ID and TRIM_ASSET_ID at the top of this script.")
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

print("[RyoHUDController] Compact RyoHUD ready | Backend=Player.Ryo | Persistence unchanged")

