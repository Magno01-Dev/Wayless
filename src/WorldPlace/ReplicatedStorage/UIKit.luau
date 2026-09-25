--!strict
--[[
	House UI Kit — reusable, scale-first Roblox GUI builder.
]]
local UIKit = {}

UIKit.Tokens = {
	Font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal),
	Stroke = {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 2,
		Join = Enum.LineJoinMode.Round,
	},
	Corner = UDim.new(0.18, 0),
	PanelCorner = UDim.new(0.04, 0),
	Text = Color3.fromRGB(255, 255, 255),
	TextStroke = Color3.fromRGB(0, 0, 0),
	PanelFill = Color3.fromRGB(18, 18, 22),
	PanelTransparency = 0.45,
	PanelSize = UDim2.fromScale(0.62, 0.62),
	PanelAspect = 1.58,
	Accent = {
		Coin   = { ColorSequence.new(Color3.fromRGB(120, 230, 60), Color3.fromRGB(255, 224, 60)),  Color3.fromRGB(28, 78, 12) },
		Power  = { ColorSequence.new(Color3.fromRGB(255, 196, 64), Color3.fromRGB(255, 96, 32)),   Color3.fromRGB(92, 36, 8) },
		Speed  = { ColorSequence.new(Color3.fromRGB(96, 196, 255), Color3.fromRGB(64, 96, 255)),   Color3.fromRGB(16, 24, 96) },
		Buy    = { ColorSequence.new(Color3.fromRGB(120, 230, 60), Color3.fromRGB(60, 170, 40)),   Color3.fromRGB(20, 60, 16) },
		Danger = { ColorSequence.new(Color3.fromRGB(255, 64, 64),  Color3.fromRGB(200, 24, 48)),   Color3.fromRGB(90, 0, 0) },
		Gold   = { ColorSequence.new(Color3.fromRGB(255, 214, 92), Color3.fromRGB(255, 160, 40)),  Color3.fromRGB(110, 62, 0) },
		Neutral= { ColorSequence.new(Color3.fromRGB(150, 150, 160), Color3.fromRGB(96, 96, 110)),  Color3.fromRGB(20, 20, 24) },
	},
}

local T = UIKit.Tokens

local function stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = T.Stroke.Join
	s.Color = color or T.Stroke.Color
	s.Thickness = thickness or T.Stroke.Thickness
	s.Parent = parent
	return s
end

local function corner(parent: Instance, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or T.Corner
	c.Parent = parent
	return c
end

local function gradient(parent: Instance, seq: ColorSequence, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = seq
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function ratio(parent: Instance, value: number): UIAspectRatioConstraint
	local r = Instance.new("UIAspectRatioConstraint")
	r.AspectRatio = value
	r.DominantAxis = Enum.DominantAxis.Width
	r.AspectType = Enum.AspectType.FitWithinMaxSize
	r.Parent = parent
	return r
end

local function styledLabel(text: string, parent: Instance): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = T.Font
	lbl.Text = text
	lbl.TextColor3 = T.Text
	lbl.TextScaled = true
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Parent = parent
	stroke(lbl)
	return lbl
end

UIKit.stroke = stroke
UIKit.corner = corner
UIKit.gradient = gradient
UIKit.ratio = ratio

function UIKit.ScreenGui(name: string?, parent: Instance?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name or "GUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if parent then
		gui.Parent = parent
	else
		local Players = game:GetService("Players")
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			gui.Parent = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui")
		else
			gui.Parent = game:GetService("StarterGui")
		end
	end
	return gui
end

export type PanelResult = { Frame: Frame, Title: Frame, Content: ScrollingFrame, Close: ImageButton }

function UIKit.Panel(opts): PanelResult
	opts = opts or {}

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = T.PanelSize
	panel.BackgroundColor3 = T.PanelFill
	panel.BackgroundTransparency = T.PanelTransparency
	panel.BorderSizePixel = 0
	panel.Visible = opts.visible ~= false
	panel.Parent = opts.parent
	corner(panel, T.PanelCorner)
	stroke(panel, T.Stroke.Color, T.Stroke.Thickness + 1)
	ratio(panel, T.PanelAspect)

	local title = Instance.new("Frame")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0)
	title.Size = UDim2.fromScale(1, 0.14)
	title.BackgroundTransparency = 1
	title.ZIndex = 2
	title.Parent = panel

	local titleLabel = styledLabel(opts.title or "Title", title)
	titleLabel.Size = UDim2.fromScale(0.6, 0.6)
	titleLabel.Position = UDim2.fromScale(0.45, 0.5)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromScale(0.95, 0.5)
	close.Size = UDim2.fromScale(0.8, 0.8)
	close.BackgroundColor3 = Color3.fromRGB(214, 64, 64)
	close.AutoButtonColor = true
	close.ZIndex = 3
	close.Parent = title
	corner(close)
	stroke(close)
	ratio(close, 1)
	gradient(close, T.Accent.Danger[1])
	local x = styledLabel("X", close)
	x.Size = UDim2.fromScale(0.7, 0.7)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.57)
	content.Size = UDim2.fromScale(0.92, 0.78)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 0
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ZIndex = 1
	content.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.012, 0)
	list.Parent = content

	return { Frame = panel, Title = title, Content = content, Close = close }
end

return UIKit
