--!strict
-- StarterPlayer > StarterPlayerScripts > ShinobiHUDController.client.lua
--
-- WAYLESS Main Shinobi HUD v1.4 - Chakra + Stamina Integrated
--
-- Builds the HUD ONLY from the six supplied PNG assets.
-- No Roblox-generated borders, gradients, strokes, shadows or decoration.
--
-- MASTER DESIGN:
--   1407 x 250 px
--   Reference viewport: 1920 x 1080
--
-- LIVE INTEGRATION INCLUDED:
--   Health  -> Humanoid.Health / Humanoid.MaxHealth
--   Chakra  -> Character.Chakra / Character.MaxChakra
--   Stamina -> Character.Stamina / Character.MaxStamina
--   Armor   -> Character.ArmorDurability / Character.ArmorMaxDurability
--
-- Chakra/Stamina preserve the old HUD's 0.08 s smoothing.
-- Life Force remains prepared for its future authoritative contract.

---------------------------------------------------------------------
-- ASSETS
---------------------------------------------------------------------

local ASSETS = {
	Frame = "rbxassetid://112503787652081",
	Chakra = "rbxassetid://102707747507280",
	Health = "rbxassetid://124370733085294",
	Stamina = "rbxassetid://106112549177749",
	Armor = "rbxassetid://118091890535755",
	LifeForce = "rbxassetid://121601255529735",
}

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- MASTER CONFIG
---------------------------------------------------------------------

local GUI_NAME = "ShinobiHUD"

local DESIGN_VIEWPORT = Vector2.new(1920, 1080)
local HUD_DESIGN_SIZE = Vector2.new(1407, 250)

-- The upper HUD follows the actual size of the 10-slot hotbar.
--
-- 0.64 means:
--     Upper HUD UIScale = Hotbar UIScale * 0.64
--
-- With the hotbar capped at 0.80, this HUD caps at 0.512.
-- It can scale DOWN, but never gets larger on big windows.
local HUD_TO_HOTBAR_SCALE_RATIO =
	0.75

-- Visible gap between the lower edge of the upper HUD artwork and the
-- top edge of the hotbar. 0 = visually joined.
local HUD_VISUAL_GAP =
	-38

-- The 1407x250 source artwork contains transparent pixels below the
-- visible frame. Compensate for them so "gap = 0" really looks joined.
local HUD_BOTTOM_TRANSPARENT_INSET =
	82

-- Fallback only while the hotbar has not loaded yet.
local HUD_FALLBACK_MAX_SCALE =
	0.31

local FALLBACK_MAX_SIZE_REFERENCE_WIDTH =
	1792

local FALLBACK_BOTTOM_MARGIN =
	174

-- Global visual transparency for the upper HUD art.
local HUD_ART_TRANSPARENCY =
	0.10

-- Same smoothing used by the old ChakraHUDController/StaminaHUDController.
local RESOURCE_TWEEN_TIME =
	0.08

local HUD_ANCHOR_POINT = Vector2.new(0.5, 1)

---------------------------------------------------------------------
-- EXACT MASTER LAYOUT
-- DO NOT RECALCULATE THESE VALUES.
---------------------------------------------------------------------

local HUD_LAYOUT = {
	Frame = {
		Position = Vector2.new(0, 0),
		Size = Vector2.new(1407, 250),
	},

	Chakra = {
		Position = Vector2.new(86, 84),
		Size = Vector2.new(505, 70),
	},

	Health = {
		Position = Vector2.new(815, 84),
		Size = Vector2.new(505, 70),
	},

	Stamina = {
		Position = Vector2.new(135, 162),
		Size = Vector2.new(446, 33),
	},

	Armor = {
		Position = Vector2.new(825, 162),
		Size = Vector2.new(446, 33),
	},

	LifeForce = {
		Position = Vector2.new(623, 51),
		Size = Vector2.new(160, 160),
	},
}

---------------------------------------------------------------------
-- TYPES
---------------------------------------------------------------------

type LayoutEntry = {
	Position: Vector2,
	Size: Vector2,
}

type BarView = {
	Container: Frame,
	Fill: ImageLabel,
	Layout: LayoutEntry,
	ConsumeFromLeft: boolean,
}

---------------------------------------------------------------------
-- CLEAN OLD HUD
---------------------------------------------------------------------

local oldGui = playerGui:FindFirstChild(GUI_NAME)

if oldGui then
	oldGui:Destroy()
end

---------------------------------------------------------------------
-- SCREEN GUI
---------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

---------------------------------------------------------------------
-- MAIN HUD
---------------------------------------------------------------------

local mainHUD = Instance.new("Frame")
mainHUD.Name = "MainHUD"
mainHUD.AnchorPoint = HUD_ANCHOR_POINT
mainHUD.Position = UDim2.new(
	0.5,
	0,
	1,
	-FALLBACK_BOTTOM_MARGIN
)
mainHUD.Size = UDim2.fromOffset(
	HUD_DESIGN_SIZE.X,
	HUD_DESIGN_SIZE.Y
)
mainHUD.BackgroundTransparency = 1
mainHUD.BorderSizePixel = 0
mainHUD.ClipsDescendants = false
mainHUD.Parent = screenGui

---------------------------------------------------------------------
-- THE ONE AND ONLY RESPONSIVE UISCALE
---------------------------------------------------------------------

local uiScale = Instance.new("UIScale")
uiScale.Name = "UIScale"
uiScale.Scale = 1
uiScale.Parent = mainHUD

---------------------------------------------------------------------
-- FRAME ART
---------------------------------------------------------------------

local mainHUDFrame = Instance.new("ImageLabel")
mainHUDFrame.Name = "MainHUDFrame"
mainHUDFrame.AnchorPoint = Vector2.zero
mainHUDFrame.Position = UDim2.fromOffset(
	HUD_LAYOUT.Frame.Position.X,
	HUD_LAYOUT.Frame.Position.Y
)
mainHUDFrame.Size = UDim2.fromOffset(
	HUD_LAYOUT.Frame.Size.X,
	HUD_LAYOUT.Frame.Size.Y
)
mainHUDFrame.BackgroundTransparency = 1
mainHUDFrame.BorderSizePixel = 0
mainHUDFrame.Image = ASSETS.Frame

-- Exact authored target dimensions take priority.
mainHUDFrame.ScaleType = Enum.ScaleType.Stretch
mainHUDFrame.ImageTransparency = HUD_ART_TRANSPARENCY

mainHUDFrame.ZIndex = 1
mainHUDFrame.Parent = mainHUD

---------------------------------------------------------------------
-- BAR FACTORY
---------------------------------------------------------------------

local function createBar(
	name: string,
	image: string,
	layout: LayoutEntry,
	consumeFromLeft: boolean
): BarView

	local container = Instance.new("Frame")
	container.Name = name .. "Container"
	container.AnchorPoint = Vector2.zero
	container.Position = UDim2.fromOffset(
		layout.Position.X,
		layout.Position.Y
	)
	container.Size = UDim2.fromOffset(
		layout.Size.X,
		layout.Size.Y
	)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.ZIndex = 2
	container.Parent = mainHUD

	local fill = Instance.new("ImageLabel")
	fill.Name = name .. "Fill"
	fill.AnchorPoint = Vector2.zero
	fill.Position = UDim2.fromOffset(0, 0)

	-- IMPORTANT:
	-- Fill always keeps its COMPLETE authored target size.
	-- Percentage changes only alter the clipping container.
	fill.Size = UDim2.fromOffset(
		layout.Size.X,
		layout.Size.Y
	)

	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Image = image
	fill.ScaleType = Enum.ScaleType.Stretch
	fill.ImageTransparency = HUD_ART_TRANSPARENCY
	fill.ZIndex = 2
	fill.Parent = container

	return {
		Container = container,
		Fill = fill,
		Layout = layout,
		ConsumeFromLeft = consumeFromLeft,
	}
end

---------------------------------------------------------------------
-- BARS
--
-- "ConsumeFromLeft = true":
-- the OUTER LEFT edge disappears first and the remaining fill stays
-- attached to the center/Life Force.
--
-- "ConsumeFromLeft = false":
-- the OUTER RIGHT edge disappears first and the remaining fill stays
-- attached to the center/Life Force.
---------------------------------------------------------------------

local chakraBar = createBar(
	"Chakra",
	ASSETS.Chakra,
	HUD_LAYOUT.Chakra,
	true
)

local healthBar = createBar(
	"Health",
	ASSETS.Health,
	HUD_LAYOUT.Health,
	false
)

local staminaBar = createBar(
	"Stamina",
	ASSETS.Stamina,
	HUD_LAYOUT.Stamina,
	true
)

local armorBar = createBar(
	"Armor",
	ASSETS.Armor,
	HUD_LAYOUT.Armor,
	false
)

---------------------------------------------------------------------
-- LIFE FORCE
---------------------------------------------------------------------

local lifeForceContainer = Instance.new("Frame")
lifeForceContainer.Name = "LifeForceContainer"
lifeForceContainer.AnchorPoint = Vector2.zero
lifeForceContainer.Position = UDim2.fromOffset(
	HUD_LAYOUT.LifeForce.Position.X,
	HUD_LAYOUT.LifeForce.Position.Y
)
lifeForceContainer.Size = UDim2.fromOffset(
	HUD_LAYOUT.LifeForce.Size.X,
	HUD_LAYOUT.LifeForce.Size.Y
)
lifeForceContainer.BackgroundTransparency = 1
lifeForceContainer.BorderSizePixel = 0
lifeForceContainer.ClipsDescendants = false
lifeForceContainer.ZIndex = 3
lifeForceContainer.Parent = mainHUD

local lifeForceFill = Instance.new("ImageLabel")
lifeForceFill.Name = "LifeForceFill"
lifeForceFill.AnchorPoint = Vector2.zero
lifeForceFill.Position = UDim2.fromOffset(0, 0)
lifeForceFill.Size = UDim2.fromOffset(
	HUD_LAYOUT.LifeForce.Size.X,
	HUD_LAYOUT.LifeForce.Size.Y
)
lifeForceFill.BackgroundTransparency = 1
lifeForceFill.BorderSizePixel = 0
lifeForceFill.Image = ASSETS.LifeForce
lifeForceFill.ScaleType = Enum.ScaleType.Stretch
lifeForceFill.ImageTransparency = HUD_ART_TRANSPARENCY
lifeForceFill.ZIndex = 3
lifeForceFill.Parent = lifeForceContainer

---------------------------------------------------------------------
-- BAR UPDATE LOGIC
---------------------------------------------------------------------

local function clampAlpha(alpha: number): number
	return math.clamp(alpha, 0, 1)
end

local function setBarAlpha(
	bar: BarView,
	alpha: number
)
	alpha = clampAlpha(alpha)

	local fullPosition = bar.Layout.Position
	local fullSize = bar.Layout.Size

	local visibleWidth = fullSize.X * alpha
	local hiddenWidth = fullSize.X - visibleWidth

	if bar.ConsumeFromLeft then
		-------------------------------------------------------------
		-- CHAKRA / STAMINA
		--
		-- Outer LEFT edge empties first.
		-- Container moves right as it shrinks.
		-- Fill moves left by the same amount so the PNG itself is
		-- NEVER compressed or stretched by the percentage.
		-------------------------------------------------------------

		bar.Container.Position = UDim2.fromOffset(
			fullPosition.X + hiddenWidth,
			fullPosition.Y
		)

		bar.Container.Size = UDim2.fromOffset(
			visibleWidth,
			fullSize.Y
		)

		bar.Fill.Position = UDim2.fromOffset(
			-hiddenWidth,
			0
		)
	else
		-------------------------------------------------------------
		-- HEALTH / ARMOR
		--
		-- Outer RIGHT edge empties first.
		-- Container stays attached to its left/center-facing edge.
		-------------------------------------------------------------

		bar.Container.Position = UDim2.fromOffset(
			fullPosition.X,
			fullPosition.Y
		)

		bar.Container.Size = UDim2.fromOffset(
			visibleWidth,
			fullSize.Y
		)

		bar.Fill.Position = UDim2.fromOffset(
			0,
			0
		)
	end

	-- Full PNG dimensions never change with alpha.
	bar.Fill.Size = UDim2.fromOffset(
		fullSize.X,
		fullSize.Y
	)
end

---------------------------------------------------------------------
-- PUBLIC-STYLE SETTERS
--
-- These are local functions in this controller by design.
-- Future authoritative resource bindings should call these functions.
---------------------------------------------------------------------

local function SetHealth(alpha: number)
	setBarAlpha(
		healthBar,
		alpha
	)
end

local function SetChakra(alpha: number)
	setBarAlpha(
		chakraBar,
		alpha
	)
end

local function SetStamina(alpha: number)
	setBarAlpha(
		staminaBar,
		alpha
	)
end

local function SetArmor(alpha: number)
	setBarAlpha(
		armorBar,
		alpha
	)
end

local lifeForceAlpha = 1

local function SetLifeForce(alpha: number)
	lifeForceAlpha = clampAlpha(alpha)

	-- Life Force will ultimately use a radial mask.
	-- Until that mask exists, preserve the authored 160x160 PNG without
	-- applying an incorrect horizontal crop.
	--
	-- Temporary opacity fallback until a radial mask is added.
	-- 25% transparency at full value, fading out toward empty.
	lifeForceFill.ImageTransparency =
		HUD_ART_TRANSPARENCY
		+ (
			1 - HUD_ART_TRANSPARENCY
		)
		* (
			1 - lifeForceAlpha
		)
end

---------------------------------------------------------------------
-- INITIAL FULL STATE
---------------------------------------------------------------------

SetHealth(1)
SetChakra(1)
SetStamina(1)
SetArmor(1)
SetLifeForce(1)

---------------------------------------------------------------------
-- RESPONSIVE SCALE + ALIGNMENT TO THE 10-SLOT HOTBAR
--
-- IMPORTANT:
-- The six HUD pieces NEVER receive independent responsive calculations.
-- HUD_LAYOUT remains untouched.
--
-- When WAYLESSTechniqueHotbar exists:
--   1. Read its real ResponsiveScale.
--   2. Scale this entire HUD proportionally to it.
--   3. Place this HUD directly above Slot_1 with an 8 px screen-space gap.
--
-- This makes the relationship shown in the reference survive resolution
-- changes and later hotbar scale adjustments.
--
-- If the hotbar is temporarily unavailable, a normal 1920x1080 fallback
-- scale/position is used.
---------------------------------------------------------------------

local viewportConnection: RBXScriptConnection? = nil

local hotbarScaleConnection: RBXScriptConnection? = nil
local hotbarSlotPositionConnection: RBXScriptConnection? = nil
local hotbarSlotSizeConnection: RBXScriptConnection? = nil
local hotbarAncestryConnection: RBXScriptConnection? = nil

local boundHotbarGui: ScreenGui? = nil
local boundHotbarSlot: GuiObject? = nil
local boundHotbarScale: UIScale? = nil

local function disconnectHotbarConnections()
	if hotbarScaleConnection then
		hotbarScaleConnection:Disconnect()
		hotbarScaleConnection = nil
	end

	if hotbarSlotPositionConnection then
		hotbarSlotPositionConnection:Disconnect()
		hotbarSlotPositionConnection = nil
	end

	if hotbarSlotSizeConnection then
		hotbarSlotSizeConnection:Disconnect()
		hotbarSlotSizeConnection = nil
	end

	if hotbarAncestryConnection then
		hotbarAncestryConnection:Disconnect()
		hotbarAncestryConnection = nil
	end

	boundHotbarGui = nil
	boundHotbarSlot = nil
	boundHotbarScale = nil
end

local function calculateFallbackHUDScale(
	viewport: Vector2
): number

	if viewport.X <= 0
		or viewport.Y <= 0 then

		return HUD_FALLBACK_MAX_SCALE
	end

	local downwardScale =
		math.min(
			1,
			viewport.X
			/ FALLBACK_MAX_SIZE_REFERENCE_WIDTH
		)

	return
		HUD_FALLBACK_MAX_SCALE
		* downwardScale
end

local function refreshHUDScaleAndPosition()
	local camera =
		Workspace.CurrentCamera

	if not camera then
		return
	end

	-------------------------------------------------------------
	-- Preferred mode:
	-- follow the actual 10-slot hotbar.
	-------------------------------------------------------------

	if boundHotbarSlot
		and boundHotbarSlot.Parent
		and boundHotbarScale
		and boundHotbarScale.Parent then

		-- Follow the actual hotbar scale directly.
		-- Since the hotbar is capped, the upper HUD is capped too.
		uiScale.Scale =
			boundHotbarScale.Scale
			* HUD_TO_HOTBAR_SCALE_RATIO

		local hotbarSlotTopY =
			boundHotbarSlot.AbsolutePosition.Y

		-- MainHUD AnchorPoint.Y = 1, so Position.Y is its mathematical bottom.
		-- The source PNG has transparent bottom padding; compensate for it
		-- so the visible artwork actually touches the hotbar.
		local transparentInsetScreen =
			HUD_BOTTOM_TRANSPARENT_INSET
			* uiScale.Scale

		mainHUD.Position =
			UDim2.new(
				0.5,
				0,
				0,
				hotbarSlotTopY
				+ transparentInsetScreen
				- HUD_VISUAL_GAP
			)

		return
	end

	-------------------------------------------------------------
	-- Fallback mode:
	-- hotbar has not appeared yet.
	-------------------------------------------------------------

	local fallbackScale =
		calculateFallbackHUDScale(
			camera.ViewportSize
		)

	uiScale.Scale =
		fallbackScale

	mainHUD.Position =
		UDim2.new(
			0.5,
			0,
			1,
			-FALLBACK_BOTTOM_MARGIN
		)
end

local function tryBindTechniqueHotbar(): boolean
	local hotbarGui =
		playerGui:
		FindFirstChild(
			"WAYLESSTechniqueHotbar"
		)

	if not hotbarGui
		or not hotbarGui:IsA(
			"ScreenGui"
		) then

		return false
	end

	local hotbarRoot =
		hotbarGui:
		FindFirstChild(
			"Root"
		)

	if not hotbarRoot
		or not hotbarRoot:IsA(
			"GuiObject"
		) then

		return false
	end

	local responsiveScale =
		hotbarRoot:
		FindFirstChild(
			"ResponsiveScale"
		)

	local slotOne =
		hotbarRoot:
		FindFirstChild(
			"Slot_1"
		)

	if not responsiveScale
		or not responsiveScale:IsA(
			"UIScale"
		)
			or not slotOne
			or not slotOne:IsA(
				"GuiObject"
			) then

		return false
	end

	disconnectHotbarConnections()

	boundHotbarGui =
		hotbarGui

	boundHotbarScale =
		responsiveScale

	boundHotbarSlot =
		slotOne

	hotbarScaleConnection =
		responsiveScale:
		GetPropertyChangedSignal(
			"Scale"
		):
		Connect(
			refreshHUDScaleAndPosition
		)

	hotbarSlotPositionConnection =
		slotOne:
		GetPropertyChangedSignal(
			"AbsolutePosition"
		):
		Connect(
			refreshHUDScaleAndPosition
		)

	hotbarSlotSizeConnection =
		slotOne:
		GetPropertyChangedSignal(
			"AbsoluteSize"
		):
		Connect(
			refreshHUDScaleAndPosition
		)

	hotbarAncestryConnection =
		hotbarGui.AncestryChanged:
		Connect(
			function(
				_child: Instance,
				parent: Instance?
			)
				if parent == nil then
					disconnectHotbarConnections()
					refreshHUDScaleAndPosition()
				end
			end
		)

	refreshHUDScaleAndPosition()

	return true
end

local function bindCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera =
		Workspace.CurrentCamera

	if not camera then
		return
	end

	viewportConnection =
		camera:
		GetPropertyChangedSignal(
			"ViewportSize"
		):
		Connect(
			function()
				-- The hotbar controller will update its ResponsiveScale too.
				-- Defer one frame so we read its final new scale/position.
				task.defer(
					refreshHUDScaleAndPosition
				)
			end
		)

	refreshHUDScaleAndPosition()
end

Workspace:
	GetPropertyChangedSignal(
		"CurrentCamera"
	):
	Connect(
		bindCamera
	)

playerGui.ChildAdded:
	Connect(
		function(
			child: Instance
		)
			if child.Name
				== "WAYLESSTechniqueHotbar" then

				task.defer(
					function()
						-- The hotbar builds Root/Slot_1 immediately after
						-- ScreenGui creation, but allow a few frames if needed.
						for _ = 1, 20 do
							if tryBindTechniqueHotbar() then
								return
							end

							task.wait()
						end
					end
				)
			end
		end
	)

bindCamera()

if not tryBindTechniqueHotbar() then
	task.spawn(
		function()
			for _ = 1, 40 do
				if tryBindTechniqueHotbar() then
					return
				end

				task.wait(
					0.10
				)
			end
		end
	)
end

---------------------------------------------------------------------
-- LIVE HEALTH BINDING
---------------------------------------------------------------------

local characterConnections: {RBXScriptConnection} = {}

local function disconnectCharacterConnections()
	for _,
		connection
		in ipairs(
			characterConnections
		) do
		connection:Disconnect()
	end

	table.clear(
		characterConnections
	)
end

local function bindHealth(
	character: Model
)
	local humanoid =
		character:
		WaitForChild(
			"Humanoid"
		) :: Humanoid

	local function refreshHealth()
		local maxHealth =
			humanoid.MaxHealth

		if maxHealth <= 0 then
			SetHealth(0)
			return
		end

		SetHealth(
			humanoid.Health
				/ maxHealth
		)
	end

	table.insert(
		characterConnections,
		humanoid.HealthChanged:
			Connect(
				function()
					refreshHealth()
				end
			)
	)

	table.insert(
		characterConnections,
		humanoid:
			GetPropertyChangedSignal(
				"MaxHealth"
			):
			Connect(
				refreshHealth
			)
	)

	refreshHealth()
end

---------------------------------------------------------------------
-- LIVE CHAKRA / STAMINA BINDING
--
-- Recovered directly from the old working HUD controllers:
--
--   Character.Chakra
--   Character.MaxChakra
--   Character.ChakraCharging
--
--   Character.Stamina
--   Character.MaxStamina
--
-- ChakraCharging is still an authoritative character attribute, but the
-- new six-PNG HUD has no separate "CHARGING" label/art, so this controller
-- does not invent one. The bar itself follows Chakra normally.
---------------------------------------------------------------------

local boundCharacter: Model? =
	nil

local displayedChakra =
	Instance.new(
		"NumberValue"
	)

displayedChakra.Name =
	"DisplayedChakra"

displayedChakra.Value =
	100

displayedChakra.Parent =
	script

local displayedStamina =
	Instance.new(
		"NumberValue"
	)

displayedStamina.Name =
	"DisplayedStamina"

displayedStamina.Value =
	100

displayedStamina.Parent =
	script

local chakraTween: Tween? =
	nil

local staminaTween: Tween? =
	nil

local function getPositiveCharacterAttribute(
	character: Model,
	attributeName: string,
	fallback: number
): number

	local value =
		character:GetAttribute(
			attributeName
		)

	if typeof(value) == "number"
		and value > 0 then

		return value
	end

	return fallback
end

local function stopChakraTween()
	if chakraTween then
		chakraTween:Cancel()
		chakraTween = nil
	end
end

local function stopStaminaTween()
	if staminaTween then
		staminaTween:Cancel()
		staminaTween = nil
	end
end

local function refreshDisplayedChakra()
	local character =
		boundCharacter

	if not character
		or not character.Parent then

		return
	end

	local maxChakra =
		getPositiveCharacterAttribute(
			character,
			"MaxChakra",
			100
		)

	SetChakra(
		math.clamp(
			displayedChakra.Value,
			0,
			maxChakra
		)
			/ maxChakra
	)
end

local function refreshDisplayedStamina()
	local character =
		boundCharacter

	if not character
		or not character.Parent then

		return
	end

	local maxStamina =
		getPositiveCharacterAttribute(
			character,
			"MaxStamina",
			100
		)

	SetStamina(
		math.clamp(
			displayedStamina.Value,
			0,
			maxStamina
		)
			/ maxStamina
	)
end

displayedChakra.Changed:
	Connect(
		refreshDisplayedChakra
	)

displayedStamina.Changed:
	Connect(
		refreshDisplayedStamina
	)

local function updateChakraFromAttributes(
	character: Model,
	immediate: boolean
)
	local maxChakra =
		getPositiveCharacterAttribute(
			character,
			"MaxChakra",
			100
		)

	local chakra =
		character:GetAttribute(
			"Chakra"
		)

	if typeof(chakra) ~= "number" then
		return
	end

	chakra =
		math.clamp(
			chakra,
			0,
			maxChakra
		)

	stopChakraTween()

	if immediate then
		displayedChakra.Value =
			chakra

		refreshDisplayedChakra()
		return
	end

	chakraTween =
		TweenService:
		Create(
			displayedChakra,
			TweenInfo.new(
				RESOURCE_TWEEN_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value = chakra,
			}
		)

	chakraTween:
		Play()
end

local function updateStaminaFromAttributes(
	character: Model,
	immediate: boolean
)
	local maxStamina =
		getPositiveCharacterAttribute(
			character,
			"MaxStamina",
			100
		)

	local stamina =
		character:GetAttribute(
			"Stamina"
		)

	if typeof(stamina) ~= "number" then
		return
	end

	stamina =
		math.clamp(
			stamina,
			0,
			maxStamina
		)

	stopStaminaTween()

	if immediate then
		displayedStamina.Value =
			stamina

		refreshDisplayedStamina()
		return
	end

	staminaTween =
		TweenService:
		Create(
			displayedStamina,
			TweenInfo.new(
				RESOURCE_TWEEN_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value = stamina,
			}
		)

	staminaTween:
		Play()
end

local function bindChakra(
	character: Model
)
	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"Chakra"
			):
			Connect(
				function()
					updateChakraFromAttributes(
						character,
						false
					)
				end
			)
	)

	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"MaxChakra"
			):
			Connect(
				function()
					updateChakraFromAttributes(
						character,
						true
					)
				end
			)
	)

	updateChakraFromAttributes(
		character,
		true
	)
end

local function bindStamina(
	character: Model
)
	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"Stamina"
			):
			Connect(
				function()
					updateStaminaFromAttributes(
						character,
						false
					)
				end
			)
	)

	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"MaxStamina"
			):
			Connect(
				function()
					updateStaminaFromAttributes(
						character,
						true
					)
				end
			)
	)

	updateStaminaFromAttributes(
		character,
		true
	)
end

---------------------------------------------------------------------
-- LIVE ARMOR DURABILITY BINDING
--
-- Existing WAYLESS EquipmentService publishes:
--
--   Character.EquippedArmorId
--   Character.ArmorDurability
--   Character.ArmorMaxDurability
--   Character.ArmorBroken
--
-- Therefore this HUD does NOT invent or duplicate armor state.
---------------------------------------------------------------------

local function bindArmorDurability(
	character: Model
)
	local function refreshArmor()
		local durability =
			character:GetAttribute(
				"ArmorDurability"
			)

		local maxDurability =
			character:GetAttribute(
				"ArmorMaxDurability"
			)

		local broken =
			character:GetAttribute(
				"ArmorBroken"
			) == true

		if broken then
			SetArmor(0)
			return
		end

		if typeof(durability) ~= "number"
			or typeof(maxDurability) ~= "number"
			or maxDurability <= 0 then

			-- No functional armor equipped.
			SetArmor(0)
			return
		end

		SetArmor(
			durability
				/ maxDurability
		)
	end

	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"ArmorDurability"
			):
			Connect(
				refreshArmor
			)
	)

	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"ArmorMaxDurability"
			):
			Connect(
				refreshArmor
			)
	)

	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"ArmorBroken"
			):
			Connect(
				refreshArmor
			)
	)

	table.insert(
		characterConnections,
		character:
			GetAttributeChangedSignal(
				"EquippedArmorId"
			):
			Connect(
				refreshArmor
			)
	)

	refreshArmor()
end

---------------------------------------------------------------------
-- CHARACTER BINDING
---------------------------------------------------------------------

local function bindCharacter(
	character: Model
)
	disconnectCharacterConnections()

	stopChakraTween()
	stopStaminaTween()

	boundCharacter =
		character

	-- Default visual state while authoritative character data resolves.
	SetHealth(1)
	SetChakra(1)
	SetStamina(1)
	SetArmor(1)

	bindHealth(
		character
	)

	bindChakra(
		character
	)

	bindStamina(
		character
	)

	bindArmorDurability(
		character
	)
end

player.CharacterAdded:
	Connect(
		bindCharacter
	)

if player.Character then
	task.spawn(
		bindCharacter,
		player.Character
	)
end

---------------------------------------------------------------------
-- READY
---------------------------------------------------------------------

print(
	"[ShinobiHUDController] READY v1.4"
		.. " | Exact1407x250Layout=ON"
		.. " | HUDToHotbarRatio=0.50"
		.. " | HotbarAlignment=ON"
		.. " | VisualGap=-6"
		.. " | ArtTransparency=0.25"
		.. " | MaxGrowth=OFF"
		.. " | ResponsiveUIScale=ON"
		.. " | HealthBinding=ON"
		.. " | ChakraBinding=ON"
		.. " | StaminaBinding=ON"
		.. " | ArmorDurabilityBinding=ON"
		.. " | LifeForceRadialMask=PENDING"
)
