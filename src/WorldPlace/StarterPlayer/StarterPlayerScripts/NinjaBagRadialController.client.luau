--!strict
-- StarterPlayer > StarterPlayerScripts > NinjaBagRadialController.client.lua
-- WAYLESS Ninja Bag Radial Menu v1.4 - Strong Zoom / Fade Animation
--
-- Reads the existing persistent Ninja Bag loadout:
--   NinjaBagSlot1Projectile ... NinjaBagSlot4Projectile
-- and inventory amounts:
--   InventoryAmount_<ProjectileId>
--
-- This radial does NOT reassign the prepared loadout. It only chooses the
-- local slot to use. The throw controller can read:
--   player:GetAttribute("NinjaBagSelectedSlot")
--
-- Local signal:
--   PlayerGui > WAYLESSNinjaBagRadialSignals > SelectedSlotChanged

---------------------------------------------------------------------
-- EASY MANUAL TUNING
---------------------------------------------------------------------
-- X bigger = RIGHT
-- X smaller = LEFT
-- Y bigger = DOWN
-- Y smaller = UP
--
-- All art positions are pixels inside the original 660 x 659 canvas.
---------------------------------------------------------------------

local OPEN_KEY = Enum.KeyCode.G
local HOLD_TO_OPEN = true

-- G must be held for this long before the radial appears.
-- A quick tap of G will NOT open the menu.
local HOLD_OPEN_DELAY = 0.22

---------------------------------------------------------------------
-- ANIMATION
---------------------------------------------------------------------
-- Intentionally noticeable. This uses a CanvasGroup so the WHOLE radial
-- fades together, while UIScale creates a strong pop/overshoot.

local ANIMATE_RADIAL = true

local OPEN_START_SCALE = 0.50
local OPEN_OVERSHOOT_SCALE = 1.10
local OPEN_POP_TIME = 0.18
local OPEN_SETTLE_TIME = 0.11

local CLOSE_SCALE = 0.70
local CLOSE_TIME = 0.12

local OPEN_START_Y_OFFSET = 0.026
local CLOSE_Y_OFFSET = 0.016

local OPEN_ROOT_ROTATION = -7
local CLOSE_ROOT_ROTATION = 5

-- Each slot wedge twists slightly into place.
local SLOT_OPEN_ROTATION_OFFSET = 9

local REQUIRE_EQUIPPED_BAG = true
local DEFAULT_SELECTED_SLOT = 1
local MOUSE_DEADZONE = 48

-- Whole radial
local CANVAS_WIDTH = 660
local CANVAS_HEIGHT = 659
local RADIAL_SCREEN_X = 0.50
local RADIAL_SCREEN_Y = 0.50
local RADIAL_SCALE = 0.68
local MIN_AUTO_SCALE = 0.46
local MAX_AUTO_SCALE = 0.86

-- 01_RADIAL_BACKPLATE
local BACKPLATE_X = 330
local BACKPLATE_Y = 329.5
local BACKPLATE_WIDTH = 660
local BACKPLATE_HEIGHT = 659
local BACKPLATE_ROTATION = 0

-- 02_SLOT_BASE / 03_SLOT_SELECTED
local SLOT_WIDTH = 250
local SLOT_HEIGHT = 185

-- Slot 1 = TOP
local SLOT_1_X = 330
local SLOT_1_Y = 135
local SLOT_1_ROTATION = 0
local SLOT_1_TEXT_X = 330
local SLOT_1_TEXT_Y = 132

-- Slot 2 = RIGHT
local SLOT_2_X = 525
local SLOT_2_Y = 329.5
local SLOT_2_ROTATION = 90
local SLOT_2_TEXT_X = 525
local SLOT_2_TEXT_Y = 329.5

-- Slot 3 = BOTTOM
local SLOT_3_X = 330
local SLOT_3_Y = 524
local SLOT_3_ROTATION = 180
local SLOT_3_TEXT_X = 330
local SLOT_3_TEXT_Y = 524

-- Slot 4 = LEFT
local SLOT_4_X = 135
local SLOT_4_Y = 329.5
local SLOT_4_ROTATION = 270
local SLOT_4_TEXT_X = 135
local SLOT_4_TEXT_Y = 329.5

-- Slot text
local SLOT_TEXT_WIDTH = 150
local SLOT_TEXT_HEIGHT = 34
local SLOT_TEXT_GLOBAL_OFFSET_X = 0
local SLOT_TEXT_GLOBAL_OFFSET_Y = 29
local SLOT_AMOUNT_OFFSET_Y = 29
local SLOT_NAME_TEXT_SIZE = 15
local SLOT_AMOUNT_TEXT_SIZE = 19

-- Throwable icon inside each equipped slot.
-- Set the individual X/Y values below if an icon needs manual tuning.
local SLOT_ICON_WIDTH = 64
local SLOT_ICON_HEIGHT = 64
local SLOT_ICON_TRANSPARENCY = 0.02

local SLOT_1_ICON_X = 330
local SLOT_1_ICON_Y = 111

local SLOT_2_ICON_X = 525
local SLOT_2_ICON_Y = 308

local SLOT_3_ICON_X = 330
local SLOT_3_ICON_Y = 503

local SLOT_4_ICON_X = 135
local SLOT_4_ICON_Y = 308

-- 04_CENTER_BASE
local CENTER_BASE_X = 330
local CENTER_BASE_Y = 329.5
local CENTER_BASE_WIDTH = 190
local CENTER_BASE_HEIGHT = 186
local CENTER_BASE_ROTATION = 0

-- 05_BAG_ICON
local BAG_ICON_X = 330
local BAG_ICON_Y = 322
local BAG_ICON_WIDTH = 118
local BAG_ICON_HEIGHT = 131
local BAG_ICON_ROTATION = 0

-- Transparency / contrast
-- 0 = opaque, 1 = invisible.
local BACKPLATE_TRANSPARENCY = 0.42
local SLOT_BASE_TRANSPARENCY = 0.30
local SLOT_SELECTED_TRANSPARENCY = 0.12
local CENTER_BASE_TRANSPARENCY = 0.28
local BAG_ICON_TRANSPARENCY = 0.12

-- Bright text + dark stroke so it remains readable over every slot.
local SLOT_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local SLOT_AMOUNT_COLOR = Color3.fromRGB(255, 255, 255)
local EMPTY_TEXT_COLOR = Color3.fromRGB(190, 190, 190)
local TEXT_STROKE_COLOR = Color3.fromRGB(18, 14, 12)
local TEXT_STROKE_TRANSPARENCY = 0.08
local DISPLAY_ORDER = 120

-- Destroy obsolete top-level Ninja Bag HUD/radial ScreenGuis.
-- This does NOT touch WAYLESSShinobiMenu, so the loadout editor remains intact.
local REMOVE_OLD_NINJA_BAG_SCREEN_GUIS = true

-- Assets
local ASSET_RADIAL_BACKPLATE = 106728581982085
local ASSET_SLOT_BASE = 72446310064293
local ASSET_SLOT_SELECTED = 139317593908298
local ASSET_CENTER_BASE = 70528337179835
local ASSET_BAG_ICON = 92077971890500

-- Throwable icons. These are shown ONLY when that throwable is assigned
-- to the corresponding Ninja Bag slot.
local THROWABLE_ICON_ASSETS: {[string]: number} = {
	Kunai = 99778116582383,
	Shuriken = 121318509440518,
	Fuma = 128301024821304,
	Senbon = 136494522430092,
}

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local InventoryCatalog =
	require(ReplicatedStorage:WaitForChild("InventoryCatalog"))

---------------------------------------------------------------------
-- REMOVE OBSOLETE TOP-LEVEL NINJA BAG HUD
---------------------------------------------------------------------

local function isOldNinjaBagScreenGui(instance: Instance): boolean
	if not instance:IsA("ScreenGui") then
		return false
	end

	if instance.Name == "WAYLESSNinjaBagRadial"
		or instance.Name == "WAYLESSShinobiMenu" then
		return false
	end

	local lowerName = string.lower(instance.Name)

	return string.find(lowerName, "ninjabag", 1, true) ~= nil
		or string.find(lowerName, "ninja_bag", 1, true) ~= nil
		or string.find(lowerName, "throwablehotbar", 1, true) ~= nil
		or string.find(lowerName, "projectilehotbar", 1, true) ~= nil
end

local function removeOldNinjaBagScreenGuis()
	if not REMOVE_OLD_NINJA_BAG_SCREEN_GUIS then
		return
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if isOldNinjaBagScreenGui(child) then
			child:Destroy()
		end
	end
end

removeOldNinjaBagScreenGuis()

playerGui.ChildAdded:Connect(
	function(child: Instance)
		if REMOVE_OLD_NINJA_BAG_SCREEN_GUIS
			and isOldNinjaBagScreenGui(child) then

			task.defer(
				function()
					if child.Parent == playerGui then
						child:Destroy()
					end
				end
			)
		end
	end
)

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function asset(id: number): string
	return "rbxassetid://" .. tostring(id)
end

local function quickSlotAttr(slotIndex: number): string
	return "NinjaBagSlot" .. tostring(slotIndex) .. "Projectile"
end

local function amountAttr(itemId: string): string
	return "InventoryAmount_" .. itemId
end

local function getSlotProjectile(slotIndex: number): string?
	local value = player:GetAttribute(quickSlotAttr(slotIndex))
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function getAmount(itemId: string?): number
	if not itemId then
		return 0
	end
	local value = player:GetAttribute(amountAttr(itemId))
	if typeof(value) ~= "number" then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function getDisplayName(itemId: string?): string
	if not itemId then
		return "EMPTY"
	end
	local item = InventoryCatalog.GetItem(itemId)
	if item
		and typeof(item.DisplayName) == "string"
		and item.DisplayName ~= "" then
		return item.DisplayName
	end
	return string.upper(itemId)
end

local function hasEquippedBag(): boolean
	local bag = player:GetAttribute("EquippedNinjaBag")
	local capacity = player:GetAttribute("NinjaBagCapacity")
	return typeof(bag) == "string"
		and bag ~= ""
		and typeof(capacity) == "number"
		and capacity > 0
end

local function isCharacterBlocked(): boolean
	local character = player.Character
	if not character then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true
	end

	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsCarrying") == true
		or character:GetAttribute("IsExecuting") == true
end

---------------------------------------------------------------------
-- SLOT LAYOUT
---------------------------------------------------------------------

type SlotLayout = {
	X: number,
	Y: number,
	Rotation: number,
	TextX: number,
	TextY: number,
}

local SLOT_LAYOUT: {[number]: SlotLayout} = {
	[1] = {
		X = SLOT_1_X, Y = SLOT_1_Y, Rotation = SLOT_1_ROTATION,
		TextX = SLOT_1_TEXT_X, TextY = SLOT_1_TEXT_Y,
	},
	[2] = {
		X = SLOT_2_X, Y = SLOT_2_Y, Rotation = SLOT_2_ROTATION,
		TextX = SLOT_2_TEXT_X, TextY = SLOT_2_TEXT_Y,
	},
	[3] = {
		X = SLOT_3_X, Y = SLOT_3_Y, Rotation = SLOT_3_ROTATION,
		TextX = SLOT_3_TEXT_X, TextY = SLOT_3_TEXT_Y,
	},
	[4] = {
		X = SLOT_4_X, Y = SLOT_4_Y, Rotation = SLOT_4_ROTATION,
		TextX = SLOT_4_TEXT_X, TextY = SLOT_4_TEXT_Y,
	},
}

---------------------------------------------------------------------
-- CLEAR OLD LOCAL UI
---------------------------------------------------------------------

local oldGui = playerGui:FindFirstChild("WAYLESSNinjaBagRadial")
if oldGui then
	oldGui:Destroy()
end

local oldSignals = playerGui:FindFirstChild("WAYLESSNinjaBagRadialSignals")
if oldSignals then
	oldSignals:Destroy()
end

---------------------------------------------------------------------
-- LOCAL SIGNAL
---------------------------------------------------------------------

local signalsFolder = Instance.new("Folder")
signalsFolder.Name = "WAYLESSNinjaBagRadialSignals"
signalsFolder.Parent = playerGui

local selectedSlotChanged = Instance.new("BindableEvent")
selectedSlotChanged.Name = "SelectedSlotChanged"
selectedSlotChanged.Parent = signalsFolder

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "WAYLESSNinjaBagRadial"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local root = Instance.new("CanvasGroup")
root.Name = "RadialCanvas"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(RADIAL_SCREEN_X, RADIAL_SCREEN_Y)
root.Size = UDim2.fromOffset(CANVAS_WIDTH, CANVAS_HEIGHT)
root.BackgroundTransparency = 1
root.GroupTransparency = 0
root.Rotation = 0
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Scale = RADIAL_SCALE
uiScale.Parent = root

-- Final responsive scale calculated from the current viewport.
local responsiveTargetScale =
	RADIAL_SCALE

local function makeImage(
	name: string,
	imageId: number,
	x: number,
	y: number,
	width: number,
	height: number,
	rotation: number,
	zIndex: number,
	imageTransparency: number?
): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromOffset(x, y)
	image.Size = UDim2.fromOffset(width, height)
	image.BackgroundTransparency = 1
	image.Image = asset(imageId)
	image.ScaleType = Enum.ScaleType.Fit
	image.Rotation = rotation
	image.ZIndex = zIndex
	image.ImageTransparency = imageTransparency or 0
	image.Parent = root
	return image
end

local function makeText(
	name: string,
	x: number,
	y: number,
	width: number,
	height: number,
	textSize: number,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = color
	label.TextStrokeColor3 = TEXT_STROKE_COLOR
	label.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
	label.TextSize = textSize
	label.Font = Enum.Font.Garamond
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 5
	label.Parent = root
	return label
end

local backplate =
	makeImage(
		"01_RADIAL_BACKPLATE",
		ASSET_RADIAL_BACKPLATE,
		BACKPLATE_X,
		BACKPLATE_Y,
		BACKPLATE_WIDTH,
		BACKPLATE_HEIGHT,
		BACKPLATE_ROTATION,
		1,
		BACKPLATE_TRANSPARENCY
	)

type SlotUi = {
	Art: ImageLabel,
	Icon: ImageLabel,
	Name: TextLabel,
	Amount: TextLabel,
}

local slots: {[number]: SlotUi} = {}

local SLOT_ICON_POSITIONS: {[number]: Vector2} = {
	[1] = Vector2.new(SLOT_1_ICON_X, SLOT_1_ICON_Y),
	[2] = Vector2.new(SLOT_2_ICON_X, SLOT_2_ICON_Y),
	[3] = Vector2.new(SLOT_3_ICON_X, SLOT_3_ICON_Y),
	[4] = Vector2.new(SLOT_4_ICON_X, SLOT_4_ICON_Y),
}

for slotIndex = 1, 4 do
	local layout = SLOT_LAYOUT[slotIndex]

	local art =
		makeImage(
			"Slot" .. tostring(slotIndex) .. "_Art",
			ASSET_SLOT_BASE,
			layout.X,
			layout.Y,
			SLOT_WIDTH,
			SLOT_HEIGHT,
			layout.Rotation,
			3,
			SLOT_BASE_TRANSPARENCY
		)

	local iconPosition = SLOT_ICON_POSITIONS[slotIndex]

	local itemIcon =
		makeImage(
			"Slot" .. tostring(slotIndex) .. "_ThrowableIcon",
			1,
			iconPosition.X,
			iconPosition.Y,
			SLOT_ICON_WIDTH,
			SLOT_ICON_HEIGHT,
			0,
			5,
			SLOT_ICON_TRANSPARENCY
		)

	itemIcon.Image = ""
	itemIcon.Visible = false

	local nameLabel =
		makeText(
			"Slot" .. tostring(slotIndex) .. "_Name",
			layout.TextX + SLOT_TEXT_GLOBAL_OFFSET_X,
			layout.TextY + SLOT_TEXT_GLOBAL_OFFSET_Y,
			SLOT_TEXT_WIDTH,
			SLOT_TEXT_HEIGHT,
			SLOT_NAME_TEXT_SIZE,
			SLOT_TEXT_COLOR
		)

	local amountLabel =
		makeText(
			"Slot" .. tostring(slotIndex) .. "_Amount",
			layout.TextX + SLOT_TEXT_GLOBAL_OFFSET_X,
			layout.TextY + SLOT_TEXT_GLOBAL_OFFSET_Y + SLOT_AMOUNT_OFFSET_Y,
			SLOT_TEXT_WIDTH,
			26,
			SLOT_AMOUNT_TEXT_SIZE,
			SLOT_AMOUNT_COLOR
		)

	slots[slotIndex] = {
		Art = art,
		Icon = itemIcon,
		Name = nameLabel,
		Amount = amountLabel,
	}
end

local centerBase =
	makeImage(
		"04_CENTER_BASE",
		ASSET_CENTER_BASE,
		CENTER_BASE_X,
		CENTER_BASE_Y,
		CENTER_BASE_WIDTH,
		CENTER_BASE_HEIGHT,
		CENTER_BASE_ROTATION,
		6,
		CENTER_BASE_TRANSPARENCY
	)

local bagIcon =
	makeImage(
		"05_BAG_ICON",
		ASSET_BAG_ICON,
		BAG_ICON_X,
		BAG_ICON_Y,
		BAG_ICON_WIDTH,
		BAG_ICON_HEIGHT,
		BAG_ICON_ROTATION,
		7,
		BAG_ICON_TRANSPARENCY
	)

---------------------------------------------------------------------
-- STATE / REFRESH
---------------------------------------------------------------------

local isOpen = false
local selectedSlot = DEFAULT_SELECTED_SLOT

local existingSelection = player:GetAttribute("NinjaBagSelectedSlot")
if typeof(existingSelection) == "number"
	and existingSelection >= 1
	and existingSelection <= 4 then
	selectedSlot = math.floor(existingSelection)
end

player:SetAttribute("NinjaBagSelectedSlot", selectedSlot)

local previousMouseBehavior = UserInputService.MouseBehavior
local previousMouseIconEnabled = UserInputService.MouseIconEnabled

local function refreshSlots()
	for slotIndex = 1, 4 do
		local projectileId = getSlotProjectile(slotIndex)
		local amount = getAmount(projectileId)
		local slotUi = slots[slotIndex]

		local iconAsset =
			projectileId
			and THROWABLE_ICON_ASSETS[projectileId]
			or nil

		if iconAsset then
			slotUi.Icon.Image = asset(iconAsset)
			slotUi.Icon.Visible = true
		else
			slotUi.Icon.Image = ""
			slotUi.Icon.Visible = false
		end

		if projectileId then
			slotUi.Name.Text = getDisplayName(projectileId)
			slotUi.Amount.Text = tostring(amount)

			if amount > 0 then
				slotUi.Name.TextColor3 = SLOT_TEXT_COLOR
				slotUi.Amount.TextColor3 = SLOT_AMOUNT_COLOR
			else
				slotUi.Name.TextColor3 = EMPTY_TEXT_COLOR
				slotUi.Amount.TextColor3 = EMPTY_TEXT_COLOR
			end
		else
			slotUi.Name.Text = "EMPTY"
			slotUi.Amount.Text = "0"
			slotUi.Name.TextColor3 = EMPTY_TEXT_COLOR
			slotUi.Amount.TextColor3 = EMPTY_TEXT_COLOR
		end
	end
end

local function refreshSelection()
	for slotIndex = 1, 4 do
		local selected = slotIndex == selectedSlot

		slots[slotIndex].Art.Image =
			asset(
				if selected
				then ASSET_SLOT_SELECTED
				else ASSET_SLOT_BASE
			)

		slots[slotIndex].Art.ImageTransparency =
			if selected
			then SLOT_SELECTED_TRANSPARENCY
			else SLOT_BASE_TRANSPARENCY
	end
end

---------------------------------------------------------------------
-- OPEN / CLOSE VISUAL ANIMATION
---------------------------------------------------------------------

local animationSerial =
	0

local activeTweens: {Tween} =
	{}

local function cancelActiveTweens()
	for _, tween in ipairs(activeTweens) do
		pcall(
			function()
				tween:Cancel()
			end
		)
	end

	table.clear(
		activeTweens
	)
end

local function tween(
	instance: Instance,
	info: TweenInfo,
	properties: {[string]: any}
): Tween
	local created =
		TweenService:Create(
			instance,
			info,
			properties
		)

	table.insert(
		activeTweens,
		created
	)

	created:Play()

	return created
end

local function targetSlotTransparency(
	slotIndex: number
): number
	return if slotIndex == selectedSlot
		then SLOT_SELECTED_TRANSPARENCY
		else SLOT_BASE_TRANSPARENCY
end

local function restoreRadialVisuals()
	root.Position =
		UDim2.fromScale(
			RADIAL_SCREEN_X,
			RADIAL_SCREEN_Y
		)

	root.Rotation =
		0

	root.GroupTransparency =
		0

	uiScale.Scale =
		responsiveTargetScale

	for slotIndex = 1, 4 do
		local slotUi =
			slots[
		slotIndex
		]

		slotUi.Art.Rotation =
			SLOT_LAYOUT[
		slotIndex
		].Rotation

		slotUi.Art.ImageTransparency =
			targetSlotTransparency(
				slotIndex
			)
	end
end

local function prepareOpenAnimation()
	root.Position =
		UDim2.fromScale(
			RADIAL_SCREEN_X,
			RADIAL_SCREEN_Y
			+ OPEN_START_Y_OFFSET
		)

	root.Rotation =
		OPEN_ROOT_ROTATION

	-- Whole menu starts invisible.
	root.GroupTransparency =
		1

	-- Strongly smaller so the zoom-in is unmistakable.
	uiScale.Scale =
		responsiveTargetScale
		* OPEN_START_SCALE

	for slotIndex = 1, 4 do
		local slotUi =
			slots[
		slotIndex
		]

		slotUi.Art.Rotation =
			SLOT_LAYOUT[
		slotIndex
		].Rotation
			+ (
				if slotIndex % 2 == 0
				then SLOT_OPEN_ROTATION_OFFSET
				else -SLOT_OPEN_ROTATION_OFFSET
			)
	end
end

local function animateOpen()
	animationSerial +=
		1

	local serial =
		animationSerial

	cancelActiveTweens()

	if not ANIMATE_RADIAL then
		restoreRadialVisuals()
		return
	end

	prepareOpenAnimation()

	local popInfo =
		TweenInfo.new(
			OPEN_POP_TIME,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)

	local fadeInfo =
		TweenInfo.new(
			OPEN_POP_TIME * 0.78,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)

	local settleInfo =
		TweenInfo.new(
			OPEN_SETTLE_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)

	local movementTween =
		tween(
			root,
			popInfo,
			{
				Position =
				UDim2.fromScale(
					RADIAL_SCREEN_X,
					RADIAL_SCREEN_Y
				),

				Rotation =
				0,
			}
		)

	tween(
		root,
		fadeInfo,
		{
			GroupTransparency =
				0,
		}
	)

	tween(
		uiScale,
		popInfo,
		{
			Scale =
				responsiveTargetScale
				* OPEN_OVERSHOOT_SCALE,
		}
	)

	for slotIndex = 1, 4 do
		tween(
			slots[
			slotIndex
			].Art,
			popInfo,
			{
				Rotation =
					SLOT_LAYOUT[
				slotIndex
				].Rotation,
			}
		)
	end

	movementTween.Completed:
		Once(
			function()
				if serial ~= animationSerial
					or not isOpen then

					return
				end

				tween(
					uiScale,
					settleInfo,
					{
						Scale =
						responsiveTargetScale,
					}
				)
			end
		)
end

local function animateClose(
	onFinished: () -> ()
)
	animationSerial +=
		1

	local serial =
		animationSerial

	cancelActiveTweens()

	if not ANIMATE_RADIAL then
		onFinished()
		return
	end

	local closeInfo =
		TweenInfo.new(
			CLOSE_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)

	local closeTween =
		tween(
			root,
			closeInfo,
			{
				Position =
				UDim2.fromScale(
					RADIAL_SCREEN_X,
					RADIAL_SCREEN_Y
					+ CLOSE_Y_OFFSET
				),

				Rotation =
				CLOSE_ROOT_ROTATION,

				GroupTransparency =
				1,
			}
		)

	tween(
		uiScale,
		closeInfo,
		{
			Scale =
				responsiveTargetScale
				* CLOSE_SCALE,
		}
	)

	closeTween.Completed:
		Once(
			function()
				if serial ~= animationSerial then
					return
				end

				onFinished()
			end
		)
end

local function setSelectedSlot(slotIndex: number, fireSignal: boolean?)
	if slotIndex < 1 or slotIndex > 4 or slotIndex == selectedSlot then
		return
	end

	selectedSlot = slotIndex
	player:SetAttribute("NinjaBagSelectedSlot", selectedSlot)
	refreshSelection()

	if fireSignal ~= false then
		selectedSlotChanged:Fire(
			selectedSlot,
			getSlotProjectile(selectedSlot)
		)
	end
end

---------------------------------------------------------------------
-- RESPONSIVE SCALE
---------------------------------------------------------------------

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	local fitScale =
		math.min(
			viewport.X / CANVAS_WIDTH,
			viewport.Y / CANVAS_HEIGHT
		) * 0.88

	responsiveTargetScale =
		math.clamp(
			RADIAL_SCALE * fitScale,
			MIN_AUTO_SCALE,
			MAX_AUTO_SCALE
		)

	if not gui.Enabled then
		uiScale.Scale =
			responsiveTargetScale
	end
end

---------------------------------------------------------------------
-- MOUSE SELECTION
---------------------------------------------------------------------

local function updateSelectionFromMouse()
	if not isOpen then
		return
	end

	local mouse = UserInputService:GetMouseLocation()
	local rootPosition = root.AbsolutePosition
	local rootSize = root.AbsoluteSize

	local center =
		Vector2.new(
			rootPosition.X + rootSize.X * 0.5,
			rootPosition.Y + rootSize.Y * 0.5
		)

	local delta = mouse - center

	if delta.Magnitude < MOUSE_DEADZONE * uiScale.Scale then
		return
	end

	local angle = math.deg(math.atan2(delta.Y, delta.X))
	local newSlot: number

	if angle >= -45 and angle < 45 then
		newSlot = 2 -- right
	elseif angle >= 45 and angle < 135 then
		newSlot = 3 -- bottom
	elseif angle >= 135 or angle < -135 then
		newSlot = 4 -- left
	else
		newSlot = 1 -- top
	end

	setSelectedSlot(newSlot, true)
end

---------------------------------------------------------------------
-- OPEN / CLOSE
---------------------------------------------------------------------

local function canOpen(): boolean
	if player:GetAttribute("NinjaBagReady") ~= true then
		return false
	end
	if REQUIRE_EQUIPPED_BAG and not hasEquippedBag() then
		return false
	end
	if isCharacterBlocked() then
		return false
	end
	return true
end

local function openRadial()
	if isOpen or not canOpen() then
		return
	end

	isOpen = true
	previousMouseBehavior = UserInputService.MouseBehavior
	previousMouseIconEnabled = UserInputService.MouseIconEnabled

	updateScale()
	refreshSlots()
	refreshSelection()

	-- Prepare BEFORE enabling so there is no single-frame flash at full size.
	if ANIMATE_RADIAL then
		prepareOpenAnimation()
	else
		restoreRadialVisuals()
	end

	gui.Enabled = true

	animateOpen()

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

local function closeRadial()
	if not isOpen then
		return
	end

	isOpen = false

	-- Gameplay input returns immediately; the visual can finish closing.
	UserInputService.MouseBehavior = previousMouseBehavior
	UserInputService.MouseIconEnabled = previousMouseIconEnabled

	player:SetAttribute("NinjaBagSelectedSlot", selectedSlot)
	selectedSlotChanged:Fire(
		selectedSlot,
		getSlotProjectile(selectedSlot)
	)

	animateClose(
		function()
			if isOpen then
				return
			end

			gui.Enabled =
				false

			restoreRadialVisuals()
		end
	)
end

local function toggleRadial()
	if isOpen then
		closeRadial()
	else
		openRadial()
	end
end

---------------------------------------------------------------------
-- INPUT
---------------------------------------------------------------------

-- Prevents a delayed open from firing after G was already released.
local openKeyHeld =
	false

local holdGeneration =
	0

UserInputService.InputBegan:Connect(
	function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end

		if input.KeyCode ~= OPEN_KEY then
			return
		end

		if HOLD_TO_OPEN then
			-- Ignore keyboard auto-repeat / duplicate began events.
			if openKeyHeld then
				return
			end

			openKeyHeld =
				true

			holdGeneration +=
				1

			local thisGeneration =
				holdGeneration

			task.delay(
				HOLD_OPEN_DELAY,
				function()
					-- Only open if the SAME G press is still being held.
					if not openKeyHeld
						or thisGeneration ~= holdGeneration then

						return
					end

					openRadial()
				end
			)
		else
			toggleRadial()
		end
	end
)

UserInputService.InputEnded:Connect(
	function(input: InputObject, _gameProcessed: boolean)
		if input.KeyCode ~= OPEN_KEY then
			return
		end

		if HOLD_TO_OPEN then
			openKeyHeld =
				false

			-- Invalidates any pending task.delay from this press.
			holdGeneration +=
				1

			closeRadial()
		end
	end
)

UserInputService.InputChanged:Connect(
	function(input: InputObject, _gameProcessed: boolean)
		if isOpen
			and input.UserInputType == Enum.UserInputType.MouseMovement then
			updateSelectionFromMouse()
		end
	end
)

---------------------------------------------------------------------
-- ATTRIBUTE WATCHERS
---------------------------------------------------------------------

for slotIndex = 1, 4 do
	player:GetAttributeChangedSignal(
		quickSlotAttr(slotIndex)
	):Connect(refreshSlots)
end

for _, item in ipairs(InventoryCatalog.GetNinjaBagItems()) do
	if typeof(item.Id) == "string" then
		player:GetAttributeChangedSignal(
			amountAttr(item.Id)
		):Connect(refreshSlots)
	end
end

player:GetAttributeChangedSignal("EquippedNinjaBag"):Connect(
	function()
		if isOpen
			and REQUIRE_EQUIPPED_BAG
			and not hasEquippedBag() then
			closeRadial()
		end
	end
)

player:GetAttributeChangedSignal("NinjaBagCapacity"):Connect(
	function()
		if isOpen
			and REQUIRE_EQUIPPED_BAG
			and not hasEquippedBag() then
			closeRadial()
		end
	end
)

---------------------------------------------------------------------
-- CAMERA / PRELOAD
---------------------------------------------------------------------

local cameraConnection: RBXScriptConnection? = nil

local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	cameraConnection =
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	updateScale()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

task.spawn(
	function()
		pcall(
			function()
				ContentProvider:PreloadAsync({
					backplate,
					centerBase,
					bagIcon,
					slots[1].Art,
					slots[2].Art,
					slots[3].Art,
					slots[4].Art,
					asset(THROWABLE_ICON_ASSETS.Kunai),
					asset(THROWABLE_ICON_ASSETS.Shuriken),
					asset(THROWABLE_ICON_ASSETS.Fuma),
					asset(THROWABLE_ICON_ASSETS.Senbon),
				})
			end
		)
	end
)

refreshSlots()
refreshSelection()

print(
	"[NinjaBagRadialController] READY v1.4"
		.. " | Key=" .. OPEN_KEY.Name
		.. " | Slots=4"
		.. " | ExistingLoadoutAttributes=ON"
		.. " | Selected=NinjaBagSelectedSlot"
)
