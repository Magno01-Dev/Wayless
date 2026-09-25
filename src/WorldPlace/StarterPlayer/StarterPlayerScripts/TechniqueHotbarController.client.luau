--!strict
-- StarterPlayer > StarterPlayerScripts > TechniqueHotbarController
--
-- WAYLESS Technique Hotbar v10.2 - Smaller + 25% Transparency + Readable Text
--
-- REPLACES the old hotbar visuals while preserving the existing gameplay
-- contracts:
--
--   Player.TechniqueLoadoutSlot_1 ... TechniqueLoadoutSlot_10
--   Player.TechniqueLoadoutReady
--
--   Character.CoreCooldown_<TechniqueId>_StartsAt
--   Character.CoreCooldown_<TechniqueId>_EndsAt
--
-- JutsuController / JutsuServer remain authoritative.
--
-- IMPORTANT VISUAL RULES:
--   - No hover art.
--   - No selected art.
--   - No shadow/glow art.
--   - No separate key-plate image.
--   - No 10_SLOT_DIVIDER.
--   - Only the supplied NEW hotbar assets are assembled.
--
-- Master art canvas: 1505 x 220

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local RunService =
	game:GetService(
		"RunService"
	)

local ContentProvider =
	game:GetService(
		"ContentProvider"
	)

local player =
	Players.LocalPlayer

local playerGui =
	player:WaitForChild(
		"PlayerGui"
	)

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local GUI_NAME =
	"WAYLESSTechniqueHotbar"

local SLOT_COUNT =
	10

---------------------------------------------------------------------
-- MASTER CANVAS
---------------------------------------------------------------------

local MASTER_WIDTH =
	1505

local MASTER_HEIGHT =
	220

-- Position on screen.
local SCREEN_X =
	0.5

local BOTTOM_MARGIN =
	12

-- Maximum hotbar size.
-- At 1792 px wide the hotbar reaches this size and NEVER grows beyond it.
-- Smaller screens scale it down proportionally.
local HOTBAR_MAX_SCALE =
	0.62

local MAX_SIZE_REFERENCE_WIDTH =
	1792

local HOTBAR_MIN_SCALE =
	0.42

local VIEWPORT_WIDTH_USAGE =
	0.96

-- Global visual transparency for the assembled hotbar art.
local HOTBAR_ART_TRANSPARENCY =
	0.10

---------------------------------------------------------------------
-- ASSETS
---------------------------------------------------------------------

-- 01_HOTBAR_BACKPLATE
local ASSET_BACKPLATE =
	131394608800717

-- 02_SLOT_BASE
local ASSET_SLOT_BASE =
	111953956465598

-- 16_GAP_MARKER_OPTIONAL
local ASSET_GAP_MARKER =
	85646355771763

-- 14_EDGE_ACCENT_LEFT_OPTIONAL
local ASSET_EDGE_LEFT =
	105535301400055

-- 15_EDGE_ACCENT_RIGHT_OPTIONAL
local ASSET_EDGE_RIGHT =
	80501898595770

---------------------------------------------------------------------
-- ART LAYOUT - EXACT MASTER COORDINATES
---------------------------------------------------------------------

-- Backplate
local BACKPLATE_X =
	20

local BACKPLATE_Y =
	58

local BACKPLATE_WIDTH =
	1465

local BACKPLATE_HEIGHT =
	105

-- Slots
local SLOT_WIDTH =
	126

local SLOT_HEIGHT =
	123

local SLOT_Y =
	42

local SLOT_X: {[number]: number} = {
	[1] = 85,
	[2] = 218,
	[3] = 351,
	[4] = 484,
	[5] = 617,

	[6] = 761,
	[7] = 894,
	[8] = 1027,
	[9] = 1160,
	[10] = 1293,
}

---------------------------------------------------------------------
-- OPTIONAL GAP MARKER
---------------------------------------------------------------------

local USE_GAP_MARKER =
	true

-- Center requested around X=752.
local GAP_MARKER_CENTER_X =
	752

-- Easy manual tuning if the uploaded PNG includes transparent margins.
local GAP_MARKER_CENTER_Y =
	103

local GAP_MARKER_WIDTH =
	34

local GAP_MARKER_HEIGHT =
	92

---------------------------------------------------------------------
-- OPTIONAL EDGE ACCENTS
---------------------------------------------------------------------

local USE_EDGE_ACCENTS =
	true

-- These align only to the backplate, never over the slots.
local EDGE_LEFT_X =
	22

local EDGE_LEFT_Y =
	72

local EDGE_RIGHT_X =
	1429

local EDGE_RIGHT_Y =
	72

local EDGE_WIDTH =
	54

local EDGE_HEIGHT =
	76

---------------------------------------------------------------------
-- DYNAMIC CONTENT LAYOUT INSIDE EACH SLOT
---------------------------------------------------------------------

-- Main technique label.
local TECHNIQUE_TEXT_X =
	13

local TECHNIQUE_TEXT_Y =
	22

local TECHNIQUE_TEXT_WIDTH =
	100

local TECHNIQUE_TEXT_HEIGHT =
	62

local TECHNIQUE_TEXT_MIN_SIZE =
	8

local TECHNIQUE_TEXT_MAX_SIZE =
	14

-- Cooldown number.
local COOLDOWN_TEXT_X =
	17

local COOLDOWN_TEXT_Y =
	18

local COOLDOWN_TEXT_WIDTH =
	92

local COOLDOWN_TEXT_HEIGHT =
	72

local COOLDOWN_TEXT_SIZE =
	24

-- Key text.
-- The key support is already part of 02_SLOT_BASE.
local KEY_TEXT_X =
	43

local KEY_TEXT_Y =
	93

local KEY_TEXT_WIDTH =
	40

local KEY_TEXT_HEIGHT =
	24

local KEY_TEXT_SIZE =
	15

local KEY_LABELS: {[number]: string} = {
	[1] = "1",
	[2] = "2",
	[3] = "3",
	[4] = "4",
	[5] = "5",
	[6] = "6",
	[7] = "7",
	[8] = "8",
	[9] = "9",
	[10] = "0",
}

---------------------------------------------------------------------
-- TEXT COLORS
---------------------------------------------------------------------

local TECHNIQUE_TEXT_COLOR =
	Color3.fromRGB(
		233,
		221,
		194
	)

local KEY_TEXT_COLOR =
	Color3.fromRGB(
		245,
		233,
		206
	)

local COOLDOWN_TEXT_COLOR =
	Color3.fromRGB(
		250,
		241,
		224
	)

local COOLDOWN_STROKE_COLOR =
	Color3.fromRGB(
		20,
		16,
		13
	)

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function asset(
	id: number
): string

	return
		"rbxassetid://"
		.. tostring(
			id
		)
end

local function slotAttributeName(
	slotIndex: number
): string

	return
		"TechniqueLoadoutSlot_"
		.. tostring(
			slotIndex
		)
end

local function getTechniqueId(
	slotIndex: number
): string?

	local value =
		player:GetAttribute(
			slotAttributeName(
				slotIndex
			)
		)

	if typeof(value) ~= "string"
		or value == "" then

		return nil
	end

	return value
end

local function formatTechniqueDisplayName(
	displayName: string
): string

	local compact =
		displayName:gsub(
			"^%s*[^:]-[Ss]tyle:%s*",
			""
		)

	compact =
		compact:gsub(
			"%s+[Jj][Uu][Tt][Ss][Uu]%s*$",
			""
		)

	return compact
end

---------------------------------------------------------------------
-- REMOVE OLD HOTBAR
---------------------------------------------------------------------

local existing =
	playerGui:
	FindFirstChild(
		GUI_NAME
	)

if existing then
	existing:
		Destroy()
end

---------------------------------------------------------------------
-- ROOT GUI
---------------------------------------------------------------------

local screenGui =
	Instance.new(
		"ScreenGui"
	)

screenGui.Name =
	GUI_NAME

screenGui.ResetOnSpawn =
	false

screenGui.IgnoreGuiInset =
	true

screenGui.DisplayOrder =
	25

screenGui.Enabled =
	false

screenGui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

screenGui.Parent =
	playerGui

local root =
	Instance.new(
		"Frame"
	)

root.Name =
	"Root"

root.AnchorPoint =
	Vector2.new(
		0.5,
		1
	)

root.Position =
	UDim2.new(
		SCREEN_X,
		0,
		1,
		-BOTTOM_MARGIN
	)

root.Size =
	UDim2.fromOffset(
		MASTER_WIDTH,
		MASTER_HEIGHT
	)

root.BackgroundTransparency =
	1

root.BorderSizePixel =
	0

root.Parent =
	screenGui

local responsiveScale =
	Instance.new(
		"UIScale"
	)

responsiveScale.Name =
	"ResponsiveScale"

responsiveScale.Scale =
	HOTBAR_SCALE

responsiveScale.Parent =
	root

---------------------------------------------------------------------
-- IMAGE FACTORY
---------------------------------------------------------------------

local function makeImage(
	name: string,
	imageId: number,
	x: number,
	y: number,
	width: number,
	height: number,
	zIndex: number
): ImageLabel

	local image =
		Instance.new(
			"ImageLabel"
		)

	image.Name =
		name

	image.Position =
		UDim2.fromOffset(
			x,
			y
		)

	image.Size =
		UDim2.fromOffset(
			width,
			height
		)

	image.BackgroundTransparency =
		1

	image.BorderSizePixel =
		0

	image.Image =
		asset(
			imageId
		)

	image.ImageTransparency =
		HOTBAR_ART_TRANSPARENCY

	image.ScaleType =
		Enum.ScaleType.Fit

	image.ZIndex =
		zIndex

	image.Parent =
		root

	return image
end

---------------------------------------------------------------------
-- BACKPLATE
---------------------------------------------------------------------

local backplate =
	makeImage(
		"01_HOTBAR_BACKPLATE",
		ASSET_BACKPLATE,
		BACKPLATE_X,
		BACKPLATE_Y,
		BACKPLATE_WIDTH,
		BACKPLATE_HEIGHT,
		1
	)

---------------------------------------------------------------------
-- GAP MARKER
---------------------------------------------------------------------

local gapMarker: ImageLabel? =
	nil

if USE_GAP_MARKER then

	gapMarker =
		makeImage(
			"16_GAP_MARKER_OPTIONAL",
			ASSET_GAP_MARKER,
			GAP_MARKER_CENTER_X
			- GAP_MARKER_WIDTH * 0.5,
			GAP_MARKER_CENTER_Y
			- GAP_MARKER_HEIGHT * 0.5,
			GAP_MARKER_WIDTH,
			GAP_MARKER_HEIGHT,
			2
		)
end

---------------------------------------------------------------------
-- EDGE ACCENTS
---------------------------------------------------------------------

local edgeLeft: ImageLabel? =
	nil

local edgeRight: ImageLabel? =
	nil

if USE_EDGE_ACCENTS then

	edgeLeft =
		makeImage(
			"14_EDGE_ACCENT_LEFT_OPTIONAL",
			ASSET_EDGE_LEFT,
			EDGE_LEFT_X,
			EDGE_LEFT_Y,
			EDGE_WIDTH,
			EDGE_HEIGHT,
			2
		)

	edgeRight =
		makeImage(
			"15_EDGE_ACCENT_RIGHT_OPTIONAL",
			ASSET_EDGE_RIGHT,
			EDGE_RIGHT_X,
			EDGE_RIGHT_Y,
			EDGE_WIDTH,
			EDGE_HEIGHT,
			2
		)
end

---------------------------------------------------------------------
-- SLOT VIEWS
---------------------------------------------------------------------

type SlotView = {
	Root: Frame,
	Base: ImageLabel,
	NameLabel: TextLabel,
	CooldownLabel: TextLabel,
	KeyLabel: TextLabel,
}

local slotViews:
	{[number]: SlotView} =
	{}

local displayNamesById:
	{[string]: string} =
	{}

local function makeTechniqueText(
	parent: Instance
): TextLabel

	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"TechniqueName"

	label.Position =
		UDim2.fromOffset(
			TECHNIQUE_TEXT_X,
			TECHNIQUE_TEXT_Y
		)

	label.Size =
		UDim2.fromOffset(
			TECHNIQUE_TEXT_WIDTH,
			TECHNIQUE_TEXT_HEIGHT
		)

	label.BackgroundTransparency =
		1

	label.BorderSizePixel =
		0

	label.Font =
		Enum.Font.Garamond

	label.Text =
		""

	label.TextColor3 =
		TECHNIQUE_TEXT_COLOR

	label.TextStrokeColor3 =
		Color3.fromRGB(
			20,
			15,
			10
		)

	label.TextStrokeTransparency =
		0.35

	label.TextScaled =
		true

	label.TextWrapped =
		true

	label.TextXAlignment =
		Enum.TextXAlignment.Center

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	label.TextTruncate =
		Enum.TextTruncate.AtEnd

	label.ZIndex =
		5

	local constraint =
		Instance.new(
			"UITextSizeConstraint"
		)

	constraint.MinTextSize =
		TECHNIQUE_TEXT_MIN_SIZE

	constraint.MaxTextSize =
		TECHNIQUE_TEXT_MAX_SIZE

	constraint.Parent =
		label

	label.Parent =
		parent

	return label
end

local function makeCooldownText(
	parent: Instance
): TextLabel

	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"CooldownText"

	label.Position =
		UDim2.fromOffset(
			COOLDOWN_TEXT_X,
			COOLDOWN_TEXT_Y
		)

	label.Size =
		UDim2.fromOffset(
			COOLDOWN_TEXT_WIDTH,
			COOLDOWN_TEXT_HEIGHT
		)

	label.BackgroundTransparency =
		1

	label.BorderSizePixel =
		0

	label.Font =
		Enum.Font.GothamBlack

	label.Text =
		""

	label.TextColor3 =
		COOLDOWN_TEXT_COLOR

	label.TextStrokeColor3 =
		COOLDOWN_STROKE_COLOR

	label.TextStrokeTransparency =
		0.15

	label.TextSize =
		COOLDOWN_TEXT_SIZE

	label.TextXAlignment =
		Enum.TextXAlignment.Center

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	label.Visible =
		false

	label.ZIndex =
		7

	label.Parent =
		parent

	return label
end

local function makeKeyText(
	parent: Instance,
	slotIndex: number
): TextLabel

	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"Key"

	label.Position =
		UDim2.fromOffset(
			KEY_TEXT_X,
			KEY_TEXT_Y
		)

	label.Size =
		UDim2.fromOffset(
			KEY_TEXT_WIDTH,
			KEY_TEXT_HEIGHT
		)

	label.BackgroundTransparency =
		1

	label.BorderSizePixel =
		0

	label.Font =
		Enum.Font.GothamBold

	label.Text =
		KEY_LABELS[
	slotIndex
	]

	label.TextColor3 =
		KEY_TEXT_COLOR

	label.TextStrokeColor3 =
		Color3.fromRGB(
			30,
			22,
			13
		)

	label.TextStrokeTransparency =
		0.30

	label.TextSize =
		KEY_TEXT_SIZE

	label.TextXAlignment =
		Enum.TextXAlignment.Center

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	label.ZIndex =
		8

	label.Parent =
		parent

	return label
end

local function createSlot(
	slotIndex: number
): SlotView

	local slotRoot =
		Instance.new(
			"Frame"
		)

	slotRoot.Name =
		"Slot_"
		.. tostring(
			slotIndex
		)

	slotRoot.Position =
		UDim2.fromOffset(
			SLOT_X[
			slotIndex
			],
			SLOT_Y
		)

	slotRoot.Size =
		UDim2.fromOffset(
			SLOT_WIDTH,
			SLOT_HEIGHT
		)

	slotRoot.BackgroundTransparency =
		1

	slotRoot.BorderSizePixel =
		0

	slotRoot.ClipsDescendants =
		false

	slotRoot.ZIndex =
		3

	slotRoot.Parent =
		root

	local slotBase =
		Instance.new(
			"ImageLabel"
		)

	slotBase.Name =
		"02_SLOT_BASE"

	slotBase.Size =
		UDim2.fromScale(
			1,
			1
		)

	slotBase.BackgroundTransparency =
		1

	slotBase.BorderSizePixel =
		0

	slotBase.Image =
		asset(
			ASSET_SLOT_BASE
		)

	slotBase.ImageTransparency =
		HOTBAR_ART_TRANSPARENCY

	slotBase.ScaleType =
		Enum.ScaleType.Fit

	slotBase.ZIndex =
		3

	slotBase.Parent =
		slotRoot

	local nameLabel =
		makeTechniqueText(
			slotRoot
		)

	local cooldownLabel =
		makeCooldownText(
			slotRoot
		)

	local keyLabel =
		makeKeyText(
			slotRoot,
			slotIndex
		)

	return {
		Root =
			slotRoot,

		Base =
			slotBase,

		NameLabel =
			nameLabel,

		CooldownLabel =
			cooldownLabel,

		KeyLabel =
			keyLabel,
	}
end

for slotIndex = 1,
	SLOT_COUNT do

	slotViews[
	slotIndex
	] =
		createSlot(
			slotIndex
		)
end

---------------------------------------------------------------------
-- RESPONSIVE SCALE
---------------------------------------------------------------------

local function calculateResponsiveScale(
	viewportSize: Vector2
): number

	if viewportSize.X <= 0
		or viewportSize.Y <= 0 then

		return HOTBAR_MAX_SCALE
	end

	-- Shrink-only responsive behavior.
	-- Larger windows cannot make the hotbar bigger than the approved size.
	local downwardScale =
		math.min(
			1,
			viewportSize.X
			/ MAX_SIZE_REFERENCE_WIDTH
		)

	-- Keep the complete 1505 px master on-screen on narrow viewports.
	local fitScale =
		(
			viewportSize.X
			* VIEWPORT_WIDTH_USAGE
		)
		/ MASTER_WIDTH

	local final =
		math.min(
			HOTBAR_MAX_SCALE
			* downwardScale,
			fitScale
		)

	return
		math.max(
			HOTBAR_MIN_SCALE,
			final
		)
end

local viewportConnection:
	RBXScriptConnection? =
	nil

local function refreshResponsiveScale()

	local camera =
		workspace.CurrentCamera

	if not camera then
		return
	end

	responsiveScale.Scale =
		calculateResponsiveScale(
			camera.ViewportSize
		)
end

local function bindCamera()

	if viewportConnection then

		viewportConnection:
			Disconnect()

		viewportConnection =
			nil
	end

	local camera =
		workspace.CurrentCamera

	if camera then

		viewportConnection =
			camera:
			GetPropertyChangedSignal(
				"ViewportSize"
			):
			Connect(
				refreshResponsiveScale
			)

		refreshResponsiveScale()
	end
end

workspace:
	GetPropertyChangedSignal(
		"CurrentCamera"
	):
	Connect(
		bindCamera
	)

bindCamera()

---------------------------------------------------------------------
-- TECHNIQUE NAME CATALOG
---------------------------------------------------------------------

local catalogRefreshBusy =
	false

local function getMenuRequest():
	RemoteFunction?

	local system =
		ReplicatedStorage:
		FindFirstChild(
			"ShinobiMenuSystem"
		)

	if not system then
		return nil
	end

	local remotes =
		system:
		FindFirstChild(
			"Remotes"
		)

	if not remotes then
		return nil
	end

	local request =
		remotes:
		FindFirstChild(
			"Request"
		)

	if request
		and request:IsA(
			"RemoteFunction"
		) then

		return request
	end

	return nil
end

local function refreshTechniqueNames()

	if catalogRefreshBusy then
		return
	end

	catalogRefreshBusy =
		true

	task.spawn(
		function()

			local request =
				getMenuRequest()

			if request then

				local ok,
				response =
					pcall(
						function()

							return
							request:
							InvokeServer(
								"GetTechniques",
								{}
							)
						end
					)

				if ok
					and typeof(response)
					== "table" then

					local techniques =
						response.Techniques

					if typeof(techniques)
						== "table" then

						for _,
							technique
							in ipairs(
								techniques
							) do

							if typeof(technique)
								== "table"
								and typeof(
									technique.Id
								) == "string"
									and typeof(
										technique.DisplayName
									) == "string" then

								displayNamesById[
								technique.Id
								] =
									formatTechniqueDisplayName(
										technique.DisplayName
									)
							end
						end
					end
				end
			end

			catalogRefreshBusy =
				false
		end
	)
end

---------------------------------------------------------------------
-- COOLDOWN HELPERS
---------------------------------------------------------------------

local function getCooldownRemaining(
	character: Model?,
	techniqueId: string
): number

	if not character then
		return 0
	end

	local endValue =
		character:
		GetAttribute(
			"CoreCooldown_"
			.. techniqueId
			.. "_EndsAt"
		)

	if typeof(endValue)
		~= "number" then

		return 0
	end

	return
		math.max(
			0,
			endValue
			- workspace:
			GetServerTimeNow()
		)
end

---------------------------------------------------------------------
-- RENDER
---------------------------------------------------------------------

local function updateSlotStatic(
	slotIndex: number
)

	local view =
		slotViews[
	slotIndex
	]

	local techniqueId =
		getTechniqueId(
			slotIndex
		)

	if not techniqueId then

		view.NameLabel.Text =
			""

		view.CooldownLabel.Text =
			""

		view.CooldownLabel.Visible =
			false

		return
	end

	local displayName =
		displayNamesById[
	techniqueId
	]
		or formatTechniqueDisplayName(
			techniqueId
		)

	view.NameLabel.Text =
		displayName
end

local function updateSlotCooldown(
	slotIndex: number,
	character: Model?
)

	local view =
		slotViews[
	slotIndex
	]

	local techniqueId =
		getTechniqueId(
			slotIndex
		)

	if not techniqueId then

		view.CooldownLabel.Visible =
			false

		view.NameLabel.TextTransparency =
			0

		return
	end

	local remaining =
		getCooldownRemaining(
			character,
			techniqueId
		)

	if remaining <= 0 then

		view.CooldownLabel.Visible =
			false

		view.CooldownLabel.Text =
			""

		view.NameLabel.TextTransparency =
			0

		return
	end

	-- No cooldown texture is added because it was NOT included in the
	-- supplied asset list for this new hotbar pass.
	-- Only the dynamic number remains.
	view.CooldownLabel.Text =
		if remaining >= 10
		then tostring(
			math.ceil(
				remaining
			)
		)
		else string.format(
			"%.1f",
			remaining
		)

	view.CooldownLabel.Visible =
		true

	view.NameLabel.TextTransparency =
		0.72
end

local function updateVisibility()

	local ready =
		player:GetAttribute(
			"TechniqueLoadoutReady"
		) == true

	local menuOpen =
		player:GetAttribute(
			"InventoryOpen"
		) == true
		or player:GetAttribute(
			"NinjaBagLoadoutOpen"
		) == true

	screenGui.Enabled =
		ready
		and not menuOpen
end

local function renderAll()

	for slotIndex = 1,
		SLOT_COUNT do

		updateSlotStatic(
			slotIndex
		)
	end

	updateVisibility()
end

---------------------------------------------------------------------
-- PLAYER ATTRIBUTE SIGNALS
---------------------------------------------------------------------

player:
	GetAttributeChangedSignal(
		"TechniqueLoadoutReady"
	):
	Connect(
		function()

			renderAll()

			if player:GetAttribute(
				"TechniqueLoadoutReady"
				) == true then

				refreshTechniqueNames()
			end
		end
	)

player:
	GetAttributeChangedSignal(
		"InventoryOpen"
	):
	Connect(
		updateVisibility
	)

player:
	GetAttributeChangedSignal(
		"NinjaBagLoadoutOpen"
	):
	Connect(
		updateVisibility
	)

for slotIndex = 1,
	SLOT_COUNT do

	player:
		GetAttributeChangedSignal(
			slotAttributeName(
				slotIndex
			)
		):
		Connect(
			function()

				updateSlotStatic(
					slotIndex
				)
			end
		)
end

---------------------------------------------------------------------
-- COOLDOWN UPDATE LOOP
---------------------------------------------------------------------

local accumulator =
	0

RunService.Heartbeat:
	Connect(
		function(
			deltaTime: number
		)

			accumulator +=
			deltaTime

			if accumulator <
				0.05 then

				return
			end

			accumulator =
			0

			if not screenGui.Enabled then
				return
			end

			local character =
			player.Character

			for slotIndex = 1,
				SLOT_COUNT do

				updateSlotCooldown(
					slotIndex,
					character
				)
			end
		end
	)

---------------------------------------------------------------------
-- PRELOAD
---------------------------------------------------------------------

task.spawn(
	function()

		local preload: {Instance} = {
			backplate,
		}

		if gapMarker then
			table.insert(
				preload,
				gapMarker
			)
		end

		if edgeLeft then
			table.insert(
				preload,
				edgeLeft
			)
		end

		if edgeRight then
			table.insert(
				preload,
				edgeRight
			)
		end

		for slotIndex = 1,
			SLOT_COUNT do

			table.insert(
				preload,
				slotViews[
				slotIndex
				].Base
			)
		end

		pcall(
			function()

				ContentProvider:
					PreloadAsync(
						preload
					)
			end
		)
	end
)

---------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------

renderAll()

if player:GetAttribute(
	"TechniqueLoadoutReady"
	) == true then

	refreshTechniqueNames()

else

	task.spawn(
		function()

			for _ = 1,
				40 do

				if player:GetAttribute(
					"TechniqueLoadoutReady"
					) == true then

					refreshTechniqueNames()
					renderAll()

					return
				end

				task.wait(
					0.25
				)
			end
		end
	)
end

print(
	"[TechniqueHotbarController] READY v10.2"
		.. " | NewHotbarAssets=ON"
		.. " | Slots=10"
		.. " | Hover=OFF"
		.. " | Selected=OFF"
		.. " | ShadowGlow=OFF"
		.. " | SeparateKeyPlate=OFF"
		.. " | GapMarker=ON"
		.. " | EdgeAccents=ON"
		.. " | MaxScale=0.62"
		.. " | ArtTransparency=0.25"
		.. " | ReadableText=ON"
)
