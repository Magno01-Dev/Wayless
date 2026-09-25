--!strict
-- RyoHUDController v1 - Compact Static Currency HUD
-- StarterPlayer > StarterPlayerScripts > RyoHUDController [LocalScript]
--
-- Bottom-right static Ryō display.
-- No popup animation.
-- No cooldown behavior.
--
-- Icon:
-- 86885621640262

local Players =
	game:GetService(
		"Players"
	)


local player =
	Players.LocalPlayer


local RYO_ICON =
	"rbxassetid://86885621640262"


-- =========================
-- LAYOUT
-- =========================

local HUD_WIDTH =
	132

local HUD_HEIGHT =
	34

local RIGHT_OFFSET =
	22

local BOTTOM_OFFSET =
	20

local ICON_SIZE =
	26


-- =========================
-- VISUALS
-- =========================

local COLOR_PANEL =
	Color3.fromRGB(
		14,
		14,
		16
	)

local COLOR_GOLD =
	Color3.fromRGB(
		190,
		151,
		76
	)

local COLOR_GOLD_DIM =
	Color3.fromRGB(
		116,
		92,
		50
	)

local COLOR_TEXT =
	Color3.fromRGB(
		232,
		228,
		216
	)


local function formatNumber(
	value: number
): string

	local integer =
		math.max(
			0,
			math.floor(
				value
			)
		)


	local text =
		tostring(
			integer
		)


	while true do

		local replaced,
			count =
			string.gsub(
				text,
				"^(-?%d+)(%d%d%d)",
				"%1,%2"
			)


		text =
			replaced


		if count == 0 then
			break
		end
	end


	return text
end


local function getRyo(): number

	local value =
		player:GetAttribute(
			"Ryo"
		)


	if typeof(value) ~= "number" then
		return 0
	end


	return math.max(
		0,
		math.floor(
			value
		)
	)
end


local playerGui =
	player:
	WaitForChild(
		"PlayerGui"
	)


local old =
	playerGui:
	FindFirstChild(
		"RyoHUD"
	)


if old then

	old:
		Destroy()
end


local gui =
	Instance.new(
		"ScreenGui"
	)


gui.Name =
	"RyoHUD"


gui.ResetOnSpawn =
	false


gui.IgnoreGuiInset =
	true


gui.DisplayOrder =
	40


gui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling


gui.Parent =
	playerGui


local root =
	Instance.new(
		"Frame"
	)


root.Name =
	"Container"


root.AnchorPoint =
	Vector2.new(
		1,
		1
	)


root.Position =
	UDim2.new(
		1,
		-RIGHT_OFFSET,
		1,
		-BOTTOM_OFFSET
	)


root.Size =
	UDim2.fromOffset(
		HUD_WIDTH,
		HUD_HEIGHT
	)


root.BackgroundColor3 =
	COLOR_PANEL


root.BackgroundTransparency =
	0.22


root.BorderSizePixel =
	0


root.Parent =
	gui


local corner =
	Instance.new(
		"UICorner"
	)


corner.CornerRadius =
	UDim.new(
		0,
		5
	)


corner.Parent =
	root


local border =
	Instance.new(
		"UIStroke"
	)


border.ApplyStrokeMode =
	Enum.ApplyStrokeMode.Border


border.Color =
	COLOR_GOLD_DIM


border.Transparency =
	0.42


border.Thickness =
	1


border.Parent =
	root


local accent =
	Instance.new(
		"Frame"
	)


accent.Name =
	"Accent"


accent.Position =
	UDim2.fromOffset(
		0,
		0
	)


accent.Size =
	UDim2.new(
		0,
		3,
		1,
		0
	)


accent.BackgroundColor3 =
	COLOR_GOLD


accent.BackgroundTransparency =
	0.10


accent.BorderSizePixel =
	0


accent.Parent =
	root


local accentCorner =
	Instance.new(
		"UICorner"
	)


accentCorner.CornerRadius =
	UDim.new(
		0,
		4
	)


accentCorner.Parent =
	accent


local icon =
	Instance.new(
		"ImageLabel"
	)


icon.Name =
	"RyoIcon"


icon.BackgroundTransparency =
	1


icon.Position =
	UDim2.fromOffset(
		8,
		4
	)


icon.Size =
	UDim2.fromOffset(
		ICON_SIZE,
		ICON_SIZE
	)


icon.Image =
	RYO_ICON


icon.ScaleType =
	Enum.ScaleType.Fit


icon.Parent =
	root


local amount =
	Instance.new(
		"TextLabel"
	)


amount.Name =
	"Amount"


amount.BackgroundTransparency =
	1


amount.Position =
	UDim2.fromOffset(
		40,
		0
	)


amount.Size =
	UDim2.new(
		1,
		-48,
		1,
		0
	)


amount.Font =
	Enum.Font.GothamBold


amount.TextSize =
	13


amount.TextColor3 =
	COLOR_TEXT


amount.TextXAlignment =
	Enum.TextXAlignment.Right


amount.TextYAlignment =
	Enum.TextYAlignment.Center


amount.Text =
	formatNumber(
		getRyo()
	)


amount.Parent =
	root


local function refresh()

	amount.Text =
		formatNumber(
			getRyo()
		)
end


player:
	GetAttributeChangedSignal(
		"Ryo"
	):
	Connect(
		refresh
	)


refresh()


print(
	"[RyoHUDController] READY v1"
		.. " | Icon=86885621640262"
		.. " | BottomRight=ON"
		.. " | Static=ON"
)
