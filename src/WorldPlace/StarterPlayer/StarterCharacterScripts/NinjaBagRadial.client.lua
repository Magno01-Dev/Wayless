--[[
	NinjaBagRadial · LocalScript en StarterPlayer.StarterCharacterScripts
	Mantener T → menú radial de la Ninja Bag · mover el mouse hacia un slot · soltar T = elegir.
	También dibuja el indicador del arma seleccionada (abajo a la derecha, solo en CombatMode).
	Mismo estilo visual que el prototipo anterior.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local folder = ReplicatedStorage:WaitForChild("Throwables")
local Config = require(folder:WaitForChild("Config"))
local ProjectileConfigs = require(ReplicatedStorage:WaitForChild("ProjectileConfigs"))

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

local SLOT_COUNT = Config.SlotCount
local DEADZONE = 42

local COLOR_PANEL = Color3.fromRGB(14, 14, 16)
local COLOR_PANEL_SOFT = Color3.fromRGB(22, 22, 25)
local COLOR_GOLD = Color3.fromRGB(190, 151, 76)
local COLOR_GOLD_DIM = Color3.fromRGB(116, 92, 50)
local COLOR_RED = Color3.fromRGB(148, 47, 42)
local COLOR_TEXT = Color3.fromRGB(232, 228, 216)
local COLOR_TEXT_DIM = Color3.fromRGB(145, 141, 132)
local COLOR_LOCKED = Color3.fromRGB(72, 72, 76)

local SLOT_POSITIONS = {
	UDim2.fromScale(0.5, 0.13), -- 1 arriba
	UDim2.fromScale(0.87, 0.5), -- 2 derecha
	UDim2.fromScale(0.5, 0.87), -- 3 abajo
	UDim2.fromScale(0.13, 0.5), -- 4 izquierda
}

-- Datos de la bolsa ------------------------------------------------------------------

local function getSlotProjectile(slot)
	local value = player:GetAttribute("NinjaBagSlot" .. slot .. "Projectile")
	if typeof(value) == "string" and value ~= "" and ProjectileConfigs[value] then
		return value
	end
	return nil
end

local function getAmount(projectile)
	if not projectile then
		return 0
	end
	local value = player:GetAttribute("NinjaBagAmount_" .. projectile)
	return if typeof(value) == "number" then math.max(0, math.floor(value)) else 0
end

local function presentation(projectile)
	if not projectile then
		return "VACÍO", "SIN EQUIPAR"
	end
	local bag = ProjectileConfigs[projectile] and ProjectileConfigs[projectile].NinjaBag
	if typeof(bag) == "table" then
		return bag.DisplayName or string.upper(projectile), bag.Subtitle or "LANZABLE"
	end
	return string.upper(projectile), "LANZABLE"
end

local selectedSlot = player:GetAttribute("NinjaBagSelectedSlot")
selectedSlot = if typeof(selectedSlot) == "number" and selectedSlot >= 1 and selectedSlot <= SLOT_COUNT then math.floor(selectedSlot) else 1
player:SetAttribute("NinjaBagSelectedSlot", selectedSlot)
player:SetAttribute("NinjaBagRadialOpen", false)

-- Construcción de la UI ------------------------------------------------------------------

local function corner(parent, radius)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = radius
	instance.Parent = parent
end

local function stroke(parent, color, transparency, thickness)
	local instance = Instance.new("UIStroke")
	instance.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	instance.Color = color
	instance.Transparency = transparency
	instance.Thickness = thickness
	instance.Parent = parent
	return instance
end

local function label(parent, text, position, size, font, textSize, color, alignment)
	local instance = Instance.new("TextLabel")
	instance.BackgroundTransparency = 1
	instance.Position = position
	instance.Size = size
	instance.Font = font
	instance.Text = text
	instance.TextSize = textSize
	instance.TextColor3 = color
	instance.TextXAlignment = alignment
	instance.TextTruncate = Enum.TextTruncate.AtEnd
	instance.Parent = parent
	return instance
end

local function accentBar(parent, color, transparency)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 3, 1, 0)
	bar.BackgroundColor3 = color
	bar.BackgroundTransparency = transparency
	bar.BorderSizePixel = 0
	bar.Parent = parent
	corner(bar, UDim.new(0, 4))
	return bar
end

local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("NinjaBagUI")
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "NinjaBagUI"
gui.ResetOnSpawn = true
gui.IgnoreGuiInset = true
gui.DisplayOrder = 80
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Indicador del arma seleccionada
local indicator = Instance.new("Frame")
indicator.AnchorPoint = Vector2.new(1, 1)
indicator.Position = UDim2.new(1, -30, 1, -72)
indicator.Size = UDim2.fromOffset(194, 44)
indicator.BackgroundColor3 = COLOR_PANEL
indicator.BackgroundTransparency = 0.18
indicator.BorderSizePixel = 0
indicator.Parent = gui
corner(indicator, UDim.new(0, 5))
stroke(indicator, COLOR_GOLD_DIM, 0.38, 1)
accentBar(indicator, COLOR_RED, 0.06)

local indicatorCategory = label(indicator, "", UDim2.fromOffset(12, 4), UDim2.fromOffset(118, 14), Enum.Font.GothamMedium, 9, COLOR_TEXT_DIM, Enum.TextXAlignment.Left)
local indicatorName = label(indicator, "", UDim2.fromOffset(12, 17), UDim2.new(1, -100, 0, 22), Enum.Font.GothamBold, 14, COLOR_TEXT, Enum.TextXAlignment.Left)
local indicatorAmount = label(indicator, "", UDim2.new(1, -78, 0, 17), UDim2.fromOffset(38, 22), Enum.Font.GothamBold, 12, COLOR_GOLD, Enum.TextXAlignment.Right)

local keyFrame = Instance.new("Frame")
keyFrame.AnchorPoint = Vector2.new(1, 0.5)
keyFrame.Position = UDim2.new(1, -8, 0.5, 0)
keyFrame.Size = UDim2.fromOffset(29, 28)
keyFrame.BackgroundColor3 = COLOR_PANEL_SOFT
keyFrame.BackgroundTransparency = 0.04
keyFrame.BorderSizePixel = 0
keyFrame.Parent = indicator
corner(keyFrame, UDim.new(0, 4))
stroke(keyFrame, COLOR_GOLD, 0.16, 1)
label(keyFrame, Config.ThrowKey.Name, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.Font.GothamBold, 14, COLOR_GOLD, Enum.TextXAlignment.Center)

-- Radial
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Visible = false
dim.Parent = gui

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(392, 392)
root.BackgroundTransparency = 1
root.Parent = dim

local rootScale = Instance.new("UIScale")
rootScale.Scale = 0.92
rootScale.Parent = root

local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromOffset(258, 258)
ring.BackgroundColor3 = COLOR_PANEL
ring.BackgroundTransparency = 0.62
ring.BorderSizePixel = 0
ring.Parent = root
corner(ring, UDim.new(1, 0))
stroke(ring, COLOR_GOLD_DIM, 0.72, 1)

local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(104, 104)
center.BackgroundColor3 = COLOR_PANEL
center.BackgroundTransparency = 0.08
center.BorderSizePixel = 0
center.Parent = root
corner(center, UDim.new(1, 0))
stroke(center, COLOR_GOLD, 0.26, 1.2)
label(center, "NINJA BAG", UDim2.fromOffset(7, 19), UDim2.new(1, -14, 0, 20), Enum.Font.GothamBold, 12, COLOR_GOLD, Enum.TextXAlignment.Center)
local centerLabel = label(center, "", UDim2.fromOffset(7, 42), UDim2.new(1, -14, 0, 22), Enum.Font.GothamBold, 13, COLOR_TEXT, Enum.TextXAlignment.Center)
label(center, "SUELTA " .. Config.BagKey.Name, UDim2.fromOffset(7, 69), UDim2.new(1, -14, 0, 14), Enum.Font.GothamMedium, 8, COLOR_TEXT_DIM, Enum.TextXAlignment.Center)

local centerAccent = Instance.new("Frame")
centerAccent.AnchorPoint = Vector2.new(0.5, 0)
centerAccent.Position = UDim2.new(0.5, 0, 0, 8)
centerAccent.Size = UDim2.fromOffset(24, 2)
centerAccent.BackgroundColor3 = COLOR_RED
centerAccent.BackgroundTransparency = 0.05
centerAccent.BorderSizePixel = 0
centerAccent.Parent = center

local slots = {}
for slot = 1, SLOT_COUNT do
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = SLOT_POSITIONS[slot] or UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(142, 64)
	frame.BackgroundColor3 = COLOR_PANEL
	frame.BackgroundTransparency = 0.28
	frame.BorderSizePixel = 0
	frame.Parent = root
	corner(frame, UDim.new(0, 5))
	slots[slot] = {
		Frame = frame,
		Stroke = stroke(frame, COLOR_GOLD_DIM, 0.52, 1),
		Accent = accentBar(frame, COLOR_GOLD_DIM, 0.58),
		Index = label(frame, string.format("SLOT %02d", slot), UDim2.fromOffset(12, 4), UDim2.fromOffset(64, 14), Enum.Font.GothamMedium, 9, COLOR_GOLD, Enum.TextXAlignment.Left),
		Name = label(frame, "", UDim2.fromOffset(12, 18), UDim2.new(1, -62, 0, 22), Enum.Font.GothamBold, 13, COLOR_TEXT, Enum.TextXAlignment.Left),
		Amount = label(frame, "", UDim2.new(1, -50, 0, 18), UDim2.fromOffset(38, 22), Enum.Font.GothamBold, 12, COLOR_GOLD, Enum.TextXAlignment.Right),
		Subtitle = label(frame, "", UDim2.fromOffset(12, 42), UDim2.new(1, -20, 0, 15), Enum.Font.GothamMedium, 8, COLOR_TEXT_DIM, Enum.TextXAlignment.Left),
	}
end

-- Actualización -------------------------------------------------------------------------

local radialOpen = false
local hoveredSlot = nil

local function refreshIndicator()
	local projectile = getSlotProjectile(selectedSlot)
	local name = presentation(projectile)
	local amount = getAmount(projectile)
	indicatorCategory.Text = string.format("SLOT %02d  •  LANZABLE", selectedSlot)
	indicatorName.Text = name
	indicatorAmount.Text = if projectile then string.format("×%02d", amount) else "--"
	indicatorAmount.TextColor3 = if projectile and amount <= 0 then COLOR_RED else COLOR_GOLD
	indicator.Visible = character:GetAttribute("CombatMode") == true
end

local function refreshSlots(highlighted)
	for slot, ui in slots do
		local projectile = getSlotProjectile(slot)
		local name, subtitle = presentation(projectile)
		local amount = getAmount(projectile)
		local empty = projectile == nil
		local depleted = not empty and amount <= 0
		ui.Name.Text = name
		ui.Name.TextColor3 = if empty or depleted then COLOR_TEXT_DIM else COLOR_TEXT
		ui.Subtitle.Text = if depleted then "AGOTADO" else subtitle
		ui.Subtitle.TextColor3 = if depleted then COLOR_RED else COLOR_TEXT_DIM
		ui.Amount.Text = if empty then "--" else string.format("×%02d", amount)
		ui.Amount.TextColor3 = if depleted then COLOR_RED elseif empty then COLOR_TEXT_DIM else COLOR_GOLD

		local warning = empty or depleted
		if slot == highlighted then
			ui.Frame.BackgroundColor3, ui.Frame.BackgroundTransparency = COLOR_PANEL_SOFT, 0.08
			ui.Stroke.Color, ui.Stroke.Transparency, ui.Stroke.Thickness = if warning then COLOR_RED else COLOR_GOLD, 0, 2.2
			ui.Accent.BackgroundColor3, ui.Accent.BackgroundTransparency = COLOR_RED, 0
		elseif slot == selectedSlot then
			ui.Frame.BackgroundColor3, ui.Frame.BackgroundTransparency = COLOR_PANEL_SOFT, 0.16
			ui.Stroke.Color, ui.Stroke.Transparency, ui.Stroke.Thickness = if warning then COLOR_RED else COLOR_GOLD, 0.22, 1.4
			ui.Accent.BackgroundColor3, ui.Accent.BackgroundTransparency = if warning then COLOR_RED else COLOR_GOLD, 0.18
		else
			ui.Frame.BackgroundColor3, ui.Frame.BackgroundTransparency = COLOR_PANEL, 0.28
			ui.Stroke.Color, ui.Stroke.Transparency, ui.Stroke.Thickness = if warning then COLOR_LOCKED else COLOR_GOLD_DIM, 0.52, 1
			ui.Accent.BackgroundColor3, ui.Accent.BackgroundTransparency = if warning then COLOR_RED else COLOR_GOLD_DIM, 0.58
		end
	end

	local centerSlot = highlighted or selectedSlot
	local projectile = getSlotProjectile(centerSlot)
	local amount = getAmount(projectile)
	centerLabel.Text = if projectile then presentation(projectile) .. string.format(" ×%02d", amount) else "SLOT VACÍO"
	centerLabel.TextColor3 = if projectile and amount > 0 then COLOR_TEXT else COLOR_RED
end

local function refreshAll()
	refreshIndicator()
	refreshSlots(hoveredSlot)
end

-- Radial ---------------------------------------------------------------------------------

local previousMouseBehavior = UserInputService.MouseBehavior
local previousMouseIcon = UserInputService.MouseIconEnabled

local function canOpen()
	if humanoid.Health <= 0 or player:GetAttribute("NinjaBagLoadoutOpen") == true then
		return false
	end
	for _, name in { "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting" } do
		if character:GetAttribute(name) == true then
			return false
		end
	end
	return character:GetAttribute("IsThrowingProjectile") ~= true
end

local function hoveredFromMouse()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	local mouse = UserInputService:GetMouseLocation() - inset
	local delta = mouse - camera.ViewportSize * 0.5
	if delta.Magnitude < DEADZONE then
		return nil
	end
	local angle = math.deg(math.atan2(delta.Y, delta.X))
	if angle >= -45 and angle < 45 then
		return 2
	elseif angle >= 45 and angle < 135 then
		return 3
	elseif angle >= -135 and angle < -45 then
		return 1
	end
	return 4
end

local function open()
	if radialOpen or not canOpen() then
		return
	end
	radialOpen = true
	hoveredSlot = nil
	player:SetAttribute("NinjaBagRadialOpen", true)
	previousMouseBehavior = UserInputService.MouseBehavior
	previousMouseIcon = UserInputService.MouseIconEnabled
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	dim.Visible = true
	dim.BackgroundTransparency = 1
	rootScale.Scale = 0.92
	refreshSlots(nil)
	TweenService:Create(dim, TweenInfo.new(0.1), { BackgroundTransparency = 0.9 }):Play()
	TweenService:Create(rootScale, TweenInfo.new(0.11), { Scale = 1 }):Play()
end

local function close(commit)
	if not radialOpen then
		return
	end
	radialOpen = false
	if commit and hoveredSlot then
		selectedSlot = hoveredSlot
		player:SetAttribute("NinjaBagSelectedSlot", selectedSlot)
	end
	hoveredSlot = nil
	player:SetAttribute("NinjaBagRadialOpen", false)
	UserInputService.MouseBehavior = previousMouseBehavior
	UserInputService.MouseIconEnabled = previousMouseIcon
	refreshAll()
	TweenService:Create(dim, TweenInfo.new(0.08), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(rootScale, TweenInfo.new(0.08), { Scale = 0.96 }):Play()
	task.delay(0.085, function()
		if not radialOpen then
			dim.Visible = false
		end
	end)
end

local connections = {}

table.insert(connections, RunService.RenderStepped:Connect(function()
	if not radialOpen then
		return
	end
	-- Otros sistemas de cámara intentan bloquear el mouse: mientras el radial está abierto manda él
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local hovered = hoveredFromMouse()
	if hovered ~= hoveredSlot then
		hoveredSlot = hovered
		refreshSlots(hoveredSlot)
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Config.BagKey or UserInputService:GetFocusedTextBox() then
		return
	end
	open()
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.BagKey then
		close(true)
	end
end))

-- Cambios de datos y de estado -------------------------------------------------------------

for slot = 1, SLOT_COUNT do
	table.insert(connections, player:GetAttributeChangedSignal("NinjaBagSlot" .. slot .. "Projectile"):Connect(refreshAll))
end
for projectile in ProjectileConfigs do
	table.insert(connections, player:GetAttributeChangedSignal("NinjaBagAmount_" .. projectile):Connect(refreshAll))
end
table.insert(connections, player:GetAttributeChangedSignal("NinjaBagSelectedSlot"):Connect(function()
	local value = player:GetAttribute("NinjaBagSelectedSlot")
	if typeof(value) == "number" then
		selectedSlot = math.clamp(math.floor(value), 1, SLOT_COUNT)
	end
	refreshAll()
end))
table.insert(connections, player:GetAttributeChangedSignal("NinjaBagLoadoutOpen"):Connect(function()
	if player:GetAttribute("NinjaBagLoadoutOpen") == true then
		close(false)
	end
end))

for _, name in { "CombatMode", "CombatSuppressed", "IsDashing", "IsStunned", "Status_Stunned" } do
	table.insert(connections, character:GetAttributeChangedSignal(name):Connect(function()
		refreshIndicator()
		if name ~= "CombatMode" and character:GetAttribute(name) == true then
			close(false)
		end
	end))
end

local function cleanup()
	close(false)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)

refreshAll()
