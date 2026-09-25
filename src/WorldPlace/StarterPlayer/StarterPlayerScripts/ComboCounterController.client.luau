--!strict
-- ComboCounterController v1.1 - Left Minimal Small + Transparent
-- StarterPlayer > StarterPlayerScripts > ComboCounterController [LocalScript]
--
-- Code-only UI.
-- No external image asset required.
--
-- Approved visual direction:
-- Option 1, moved to LEFT side.
-- v1.1 tuning: smaller overall footprint and slightly more transparency.
--
-- Server authority:
-- This LocalScript never counts clicks.
-- It only presents ComboHitConfirmed from ComboCounterService.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local TweenService =
	game:GetService("TweenService")


local player =
	Players.LocalPlayer


-- =========================
-- VISUAL SETTINGS
-- =========================

local HUD_POSITION =
	UDim2.fromScale(
		0.055,
		0.50
	)

local HUD_SIZE =
	UDim2.fromOffset(
		178,
		108
	)

local BASE_VISIBLE_SCALE =
	0.86

local MIN_VISIBLE_COMBO =
	2

local DEFAULT_COMBO_TIMEOUT =
	1.75

local FADE_IN_TIME =
	0.10

local FADE_OUT_TIME =
	0.20

local BASE_NUMBER_TRANSPARENCY =
	0.10

local BASE_NUMBER_SHADOW_TRANSPARENCY =
	0.42

local BASE_TEXT_TRANSPARENCY =
	0.14

local BASE_ACCENT_TRANSPARENCY =
	0.16

local BASE_ACCENT_TIP_TRANSPARENCY =
	0.12

local BASE_ACCENT_GLOW_TRANSPARENCY =
	0.82


-- =========================
-- GUI ROOT
-- =========================

local playerGui =
	player:
	WaitForChild(
		"PlayerGui"
	)


local oldGui =
	playerGui:
	FindFirstChild(
		"ComboCounterGui"
	)

if oldGui then
	oldGui:Destroy()
end


local screenGui =
	Instance.new("ScreenGui")

screenGui.Name =
	"ComboCounterGui"

screenGui.ResetOnSpawn =
	false

screenGui.IgnoreGuiInset =
	true

screenGui.DisplayOrder =
	45

screenGui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

screenGui.Parent =
	playerGui


local root =
	Instance.new("Frame")

root.Name =
	"Root"

root.AnchorPoint =
	Vector2.new(
		0,
		0.5
	)

root.Position =
	HUD_POSITION

root.Size =
	HUD_SIZE

root.BackgroundTransparency =
	1

root.Visible =
	false

root.Parent =
	screenGui


local rootScale =
	Instance.new("UIScale")

rootScale.Name =
	"ImpactScale"

rootScale.Scale =
	1

rootScale.Parent =
	root


-- =========================
-- CODE-ONLY BRUSH BACKING
-- =========================

local brushGroup =
	Instance.new("Frame")

brushGroup.Name =
	"BrushBacking"

brushGroup.AnchorPoint =
	Vector2.new(
		0,
		0.5
	)

brushGroup.Position =
	UDim2.fromScale(
		0,
		0.52
	)

brushGroup.Size =
	UDim2.fromScale(
		0.96,
		0.72
	)

brushGroup.BackgroundTransparency =
	1

brushGroup.ZIndex =
	1

brushGroup.Parent =
	root


type BrushDefinition = {
	pos: UDim2,
	size: UDim2,
	rotation: number,
	transparency: number,
}


local brushDefinitions: {BrushDefinition} = {
	{
		pos = UDim2.fromScale(0.03, 0.18),
		size = UDim2.fromScale(0.88, 0.25),
		rotation = -4,
		transparency = 0.20,
	},
	{
		pos = UDim2.fromScale(0.00, 0.34),
		size = UDim2.fromScale(0.96, 0.27),
		rotation = 2,
		transparency = 0.14,
	},
	{
		pos = UDim2.fromScale(0.05, 0.49),
		size = UDim2.fromScale(0.86, 0.28),
		rotation = -2,
		transparency = 0.10,
	},
	{
		pos = UDim2.fromScale(0.09, 0.62),
		size = UDim2.fromScale(0.78, 0.22),
		rotation = 4,
		transparency = 0.22,
	},
	{
		pos = UDim2.fromScale(0.13, 0.08),
		size = UDim2.fromScale(0.65, 0.16),
		rotation = 7,
		transparency = 0.42,
	},
	{
		pos = UDim2.fromScale(0.12, 0.76),
		size = UDim2.fromScale(0.71, 0.13),
		rotation = -6,
		transparency = 0.36,
	},
}


for index,
	definition in ipairs(
		brushDefinitions
	) do

	local strip =
		Instance.new("Frame")

	strip.Name =
		"BrushStrip_"
		.. tostring(
			index
		)

	strip.AnchorPoint =
		Vector2.new(
			0,
			0.5
		)

	strip.Position =
		definition.pos

	strip.Size =
		definition.size

	strip.Rotation =
		definition.rotation

	strip.BackgroundColor3 =
		Color3.fromRGB(
			4,
			4,
			5
		)

	strip.BackgroundTransparency =
		definition.transparency

	strip.BorderSizePixel =
		0

	strip.ZIndex =
		1

	strip:SetAttribute(
		"BaseTransparency",
		definition.transparency
	)

	strip.Parent =
		brushGroup


	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(
			0,
			5
		)

	corner.Parent =
		strip
end


-- =========================
-- NUMBER
-- =========================

local numberShadow =
	Instance.new("TextLabel")

numberShadow.Name =
	"ComboNumberShadow"

numberShadow.Position =
	UDim2.fromOffset(
		25,
		8
	)

numberShadow.Size =
	UDim2.fromOffset(
		98,
		60
	)

numberShadow.BackgroundTransparency =
	1

numberShadow.Font =
	Enum.Font.GothamBlack

numberShadow.Text =
	"2"

numberShadow.TextColor3 =
	Color3.fromRGB(
		0,
		0,
		0
	)

numberShadow.TextTransparency =
	BASE_NUMBER_SHADOW_TRANSPARENCY

numberShadow.TextSize =
	56

numberShadow.TextXAlignment =
	Enum.TextXAlignment.Left

numberShadow.TextYAlignment =
	Enum.TextYAlignment.Center

numberShadow.ZIndex =
	2

numberShadow.Parent =
	root


local numberLabel =
	Instance.new("TextLabel")

numberLabel.Name =
	"ComboNumber"

numberLabel.Position =
	UDim2.fromOffset(
		21,
		4
	)

numberLabel.Size =
	UDim2.fromOffset(
		98,
		60
	)

numberLabel.BackgroundTransparency =
	1

numberLabel.Font =
	Enum.Font.GothamBlack

numberLabel.Text =
	"2"

numberLabel.TextColor3 =
	Color3.fromRGB(
		246,
		246,
		244
	)

numberLabel.TextTransparency =
	BASE_NUMBER_TRANSPARENCY

numberLabel.TextStrokeColor3 =
	Color3.fromRGB(
		0,
		0,
		0
	)

numberLabel.TextStrokeTransparency =
	0.12

numberLabel.TextSize =
	56

numberLabel.TextXAlignment =
	Enum.TextXAlignment.Left

numberLabel.TextYAlignment =
	Enum.TextYAlignment.Center

numberLabel.ZIndex =
	4

numberLabel.Parent =
	root


-- =========================
-- HIT COMBO
-- =========================

local comboText =
	Instance.new("TextLabel")

comboText.Name =
	"HitComboText"

comboText.Position =
	UDim2.fromOffset(
		23,
		62
	)

comboText.Size =
	UDim2.fromOffset(
		132,
		22
	)

comboText.BackgroundTransparency =
	1

comboText.Font =
	Enum.Font.GothamBold

comboText.Text =
	"HIT COMBO"

comboText.TextColor3 =
	Color3.fromRGB(
		240,
		240,
		238
	)

comboText.TextTransparency =
	BASE_TEXT_TRANSPARENCY

comboText.TextStrokeColor3 =
	Color3.fromRGB(
		0,
		0,
		0
	)

comboText.TextStrokeTransparency =
	0.28

comboText.TextSize =
	16

comboText.TextXAlignment =
	Enum.TextXAlignment.Left

comboText.TextYAlignment =
	Enum.TextYAlignment.Center

comboText.ZIndex =
	4

comboText.Parent =
	root


-- =========================
-- RED ACCENT
-- =========================

local accentGlow =
	Instance.new("Frame")

accentGlow.Name =
	"AccentGlow"

accentGlow.Position =
	UDim2.fromOffset(
		22,
		86
	)

accentGlow.Size =
	UDim2.fromOffset(
		118,
		6
	)

accentGlow.BackgroundColor3 =
	Color3.fromRGB(
		145,
		8,
		13
	)

accentGlow.BackgroundTransparency =
	BASE_ACCENT_GLOW_TRANSPARENCY

accentGlow.BorderSizePixel =
	0

accentGlow.Rotation =
	-1

accentGlow.ZIndex =
	3

accentGlow.Parent =
	root


local accent =
	Instance.new("Frame")

accent.Name =
	"RedAccent"

accent.Position =
	UDim2.fromOffset(
		23,
		88
	)

accent.Size =
	UDim2.fromOffset(
		108,
		2
	)

accent.BackgroundColor3 =
	Color3.fromRGB(
		178,
		19,
		24
	)

accent.BackgroundTransparency =
	BASE_ACCENT_TRANSPARENCY

accent.BorderSizePixel =
	0

accent.Rotation =
	-1

accent.ZIndex =
	5

accent.Parent =
	root


local accentTip =
	Instance.new("Frame")

accentTip.Name =
	"AccentTip"

accentTip.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

accentTip.Position =
	UDim2.fromOffset(
		133,
		89
	)

accentTip.Size =
	UDim2.fromOffset(
		12,
		2
	)

accentTip.BackgroundColor3 =
	Color3.fromRGB(
		235,
		54,
		44
	)

accentTip.BackgroundTransparency =
	BASE_ACCENT_TIP_TRANSPARENCY

accentTip.BorderSizePixel =
	0

accentTip.Rotation =
	-4

accentTip.ZIndex =
	6

accentTip.Parent =
	root


-- =========================
-- ANIMATION
-- =========================

local displayGeneration =
	0

local currentlyVisible =
	false


local function setGroupTransparency(
	alpha: number
)

	alpha =
		math.clamp(
			alpha,
			0,
			1
		)

	numberLabel.TextTransparency =
		math.clamp(
			BASE_NUMBER_TRANSPARENCY
			+ alpha * (
				1 - BASE_NUMBER_TRANSPARENCY
			),
			0,
			1
		)

	numberShadow.TextTransparency =
		math.clamp(
			BASE_NUMBER_SHADOW_TRANSPARENCY
			+ alpha * (
				1 - BASE_NUMBER_SHADOW_TRANSPARENCY
			),
			0,
			1
		)

	comboText.TextTransparency =
		math.clamp(
			BASE_TEXT_TRANSPARENCY
			+ alpha * (
				1 - BASE_TEXT_TRANSPARENCY
			),
			0,
			1
		)

	accent.BackgroundTransparency =
		math.clamp(
			BASE_ACCENT_TRANSPARENCY
			+ alpha * (
				1 - BASE_ACCENT_TRANSPARENCY
			),
			0,
			1
		)

	accentTip.BackgroundTransparency =
		math.clamp(
			BASE_ACCENT_TIP_TRANSPARENCY
			+ alpha * (
				1 - BASE_ACCENT_TIP_TRANSPARENCY
			),
			0,
			1
		)

	accentGlow.BackgroundTransparency =
		math.clamp(
			BASE_ACCENT_GLOW_TRANSPARENCY
			+ alpha * (
				1 - BASE_ACCENT_GLOW_TRANSPARENCY
			),
			0,
			1
		)


	for _,
		child in ipairs(
			brushGroup:
				GetChildren()
		) do

		if child:IsA("Frame") then

			local baseTransparency =
				child:GetAttribute(
					"BaseTransparency"
				)

			if typeof(baseTransparency)
				== "number" then

				child.BackgroundTransparency =
					math.clamp(
						baseTransparency
						+ alpha,
						0,
						1
					)
			end
		end
	end
end


local function hideImmediate()

	displayGeneration += 1

	currentlyVisible =
		false

	root.Visible =
		false

	rootScale.Scale =
		BASE_VISIBLE_SCALE

	root.Position =
		HUD_POSITION
end


local function fadeOut(
	generation: number
)

	if generation ~=
		displayGeneration then

		return
	end


	local fadeValue =
		Instance.new("NumberValue")

	fadeValue.Value =
		0


	local changedConnection =
		fadeValue.Changed:
		Connect(
			function(
				value
			)

				setGroupTransparency(
					value
				)
			end
		)


	local tween =
		TweenService:
		Create(
			fadeValue,
			TweenInfo.new(
				FADE_OUT_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value = 1
			}
		)


	tween.Completed:
		Connect(
			function()

				changedConnection:
				Disconnect()

				fadeValue:
				Destroy()


				if generation ==
					displayGeneration then

					root.Visible =
					false

					currentlyVisible =
					false
				end
			end
		)


	tween:
		Play()
end


local function scheduleHide(
	timeout: number
)

	displayGeneration += 1

	local generation =
		displayGeneration


	task.delay(
		timeout,
		function()

			if generation ~=
				displayGeneration then

				return
			end


			fadeOut(
				generation
			)
		end
	)
end


local function playFirstAppearance()

	root.Visible =
		true

	currentlyVisible =
		true

	setGroupTransparency(
		1
	)

	rootScale.Scale =
		0.72

	root.Position =
		HUD_POSITION
		+ UDim2.fromOffset(
			-18,
			0
		)


	local fadeValue =
		Instance.new("NumberValue")

	fadeValue.Value =
		1


	local changedConnection =
		fadeValue.Changed:
		Connect(
			function(
				value
			)

				setGroupTransparency(
					value
				)
			end
		)


	local fadeTween =
		TweenService:
		Create(
			fadeValue,
			TweenInfo.new(
				FADE_IN_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value = 0
			}
		)


	local scaleTween =
		TweenService:
		Create(
			rootScale,
			TweenInfo.new(
				0.15,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{
				Scale = BASE_VISIBLE_SCALE
			}
		)


	local positionTween =
		TweenService:
		Create(
			root,
			TweenInfo.new(
				0.14,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Position =
				HUD_POSITION
			}
		)


	fadeTween.Completed:
		Connect(
			function()

				changedConnection:
				Disconnect()

				fadeValue:
				Destroy()

				setGroupTransparency(
					0
				)
			end
		)


	fadeTween:
		Play()

	scaleTween:
		Play()

	positionTween:
		Play()
end


local function playCountPunch()

	root.Visible =
		true

	currentlyVisible =
		true

	setGroupTransparency(
		0
	)


	rootScale.Scale =
		0.98


	local downTween =
		TweenService:
		Create(
			rootScale,
			TweenInfo.new(
				0.075,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Scale = 0.82
			}
		)


	downTween.Completed:
		Connect(
			function()

				TweenService:
				Create(
					rootScale,
					TweenInfo.new(
						0.10,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out
					),
					{
						Scale = BASE_VISIBLE_SCALE
					}
				):
				Play()
			end
		)


	downTween:
		Play()


	accent.Size =
		UDim2.fromOffset(
			28,
			2
		)


	TweenService:
		Create(
			accent,
			TweenInfo.new(
				0.13,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.Out
			),
			{
				Size =
				UDim2.fromOffset(
					142,
					3
				)
			}
		):
		Play()
end


local function showCombo(
	count: number,
	timeout: number
)

	if count <
		MIN_VISIBLE_COMBO then

		hideImmediate()

		return
	end


	local wasVisible =
		currentlyVisible


	numberLabel.Text =
		tostring(
			count
		)

	numberShadow.Text =
		numberLabel.Text


	if wasVisible then
		playCountPunch()
	else
		playFirstAppearance()
	end


	scheduleHide(
		timeout
	)
end


-- =========================
-- SERVER FEEDBACK
-- =========================

local combatRemotes =
	ReplicatedStorage:
	WaitForChild(
		"CombatRemotes"
	)


local comboConfirmed =
	combatRemotes:
	WaitForChild(
		"ComboHitConfirmed"
	)


comboConfirmed.OnClientEvent:
	Connect(
		function(
			count,
			_targetCharacter,
			_sourceType,
			_sourceId,
			serverTimeout
		)

			if typeof(count)
				~= "number" then

				return
			end


			local timeout =
			if typeof(serverTimeout)
			== "number"
			then math.clamp(
				serverTimeout,
				0.5,
				5
			)
			else DEFAULT_COMBO_TIMEOUT


			showCombo(
				math.max(
					0,
					math.floor(
						count
					)
				),
				timeout
			)
		end
	)


print(
	"[ComboCounterController] READY v1.1"
		.. " | LeftMinimal=ON"
		.. " | ServerConfirmedOnly=ON"
		.. " | StartsAt2=ON"
		.. " | SmallerTransparent=ON"
)
