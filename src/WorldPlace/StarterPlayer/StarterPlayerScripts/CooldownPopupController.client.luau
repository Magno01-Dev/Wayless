--!strict
-- CooldownPopupController v14 - Astra CooldownHUD integration
--
-- PLACE:
-- StarterPlayer > StarterPlayerScripts > CooldownPopupController [LocalScript]
--
-- VISUAL AUTHORITY:
-- CooldownHUD.zip / Layout.json + INSTALL.md supplied by Magno.
-- Do not retune layout, timing, colors, fonts, or animation values here.
--
-- BACKEND CONTRACT:
-- Existing CoreCooldown_<ActionId>_{Label,StartsAt,EndsAt} character attributes.
-- The HUD is presentation-only; gameplay/server systems remain authoritative.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- ASTRA ASSET IDS
-- ============================================================
-- AssetIds.json intentionally ships empty. Fill these only with the real
-- owner/group uploads for the supplied PNGs. Do not reuse the old HUD skin.
-- CloudEngraving should use the Roblox-ready 2.2x-brightness COPY produced
-- from the supplied original, per INSTALL.md. The original stays preserved.
local COOLDOWN_FRAME_IMAGE = ""
local CLOUD_ENGRAVING_IMAGE = ""

-- ============================================================
-- ASTRA REFERENCE / LAYOUT CONSTANTS
-- ============================================================
local REFERENCE_WIDTH = 1920
local REFERENCE_HEIGHT = 1080

local RIGHT_OFFSET = 22
local TOP_OFFSET = 410

local ROW_WIDTH = 240
local ROW_HEIGHT = 40
local ROW_PITCH = 44

local SURFACE_X = 10
local SURFACE_Y = 8
local SURFACE_WIDTH = 220
local SURFACE_HEIGHT = 23
local SURFACE_COLOR = Color3.fromRGB(0x12, 0x18, 0x19)
local SURFACE_TRANSPARENCY = 1 - 0.48

local CLOUD_TILE_WIDTH = 78
local CLOUD_TILE_HEIGHT = 78
local CLOUD_TRANSPARENCY = 1 - 0.45

local NAME_X = 31
local NAME_Y = 8
local NAME_WIDTH = 139
local NAME_HEIGHT = 18
local NAME_TEXT_SIZE = 15
local NAME_COLOR = Color3.fromRGB(0xE3, 0xD1, 0xAF)

local TIMER_X = 177
local TIMER_Y = 8
local TIMER_WIDTH = 39
local TIMER_HEIGHT = 18
local TIMER_TEXT_SIZE = 14
local TIMER_COLOR = Color3.fromRGB(0xF3, 0xE9, 0xD6)

local PROGRESS_X = 35
local PROGRESS_Y = 28
local PROGRESS_WIDTH = 174
local PROGRESS_HEIGHT = 2
local PROGRESS_COLOR = Color3.fromRGB(0xC3, 0xA7, 0x77)
local PROGRESS_TRANSPARENCY = 1 - 0.85

local READY_COLOR = Color3.fromRGB(0xE9, 0xCE, 0xA0)
local READY_DURATION = 1.0

local ENTRY_DURATION = 0.28
local ENTRY_FROM_X = 12
local EXIT_DURATION = 0.28
local EXIT_TRANSLATE_X = 18
local REFLOW_DURATION = 0.28

local TITLE_FONT = Font.new("rbxasset://fonts/families/Fondamento.json")
local NUMBER_FONT = Font.new("rbxasset://fonts/families/Merriweather.json")

local SURFACE_POLYGON: {{number}} = {
	{1, 0},
	{99, 0},
	{100, 10},
	{100, 90},
	{99, 100},
	{14, 100},
	{9, 79},
	{4, 70},
	{0, 45},
	{0, 10},
}

-- ============================================================
-- TECHNIQUE COOLDOWN PRESENTATION SPLIT
-- ============================================================
-- Techniques already render their cooldowns in TechniqueHotbarController.
-- This HUD remains for non-technique/core actions only.
local TECHNIQUE_SLOT_COUNT = 10

local function isTechniqueLoadoutAbility(abilityId: string): boolean
	for slotIndex = 1, TECHNIQUE_SLOT_COUNT do
		local techniqueId = player:GetAttribute("TechniqueLoadoutSlot_" .. tostring(slotIndex))
		if typeof(techniqueId) == "string"
			and techniqueId ~= ""
			and techniqueId == abilityId then
			return true
		end
	end

	return false
end

-- ============================================================
-- TYPES
-- ============================================================
type CooldownRecord = {
	id: string,
	label: string,
	duration: number,
	expiresAt: number,
	row: CanvasGroup,
	nameLabel: TextLabel,
	nameShadow: TextLabel,
	timerLabel: TextLabel,
	timerShadow: TextLabel,
	progress: Frame,
	layoutTween: Tween?,
	entryTween: Tween?,
	fadeTween: Tween?,
	removing: boolean,
	ready: boolean,
	readyUntil: number,
}

-- ============================================================
-- CLEAN OLD GUI NAMES / CREATE FIXED PACKAGE GUI
-- ============================================================
for _, oldName in ipairs({
	"CooldownHUD",
	"CooldownHUDGui",
	"CooldownPopupGui",
}) do
	local old = playerGui:FindFirstChild(oldName)
	if old then
		old:Destroy()
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CooldownHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 91
screenGui.Parent = playerGui

-- This frame gives us the actual drawable/safe coordinate space produced by
-- IgnoreGuiInset=false. Edge placement is anchored against this real space.
local safeBounds = Instance.new("Frame")
safeBounds.Name = "SafeBounds"
safeBounds.Size = UDim2.fromScale(1, 1)
safeBounds.BackgroundTransparency = 1
safeBounds.BorderSizePixel = 0
safeBounds.Parent = screenGui

local clipRoot = Instance.new("Frame")
clipRoot.Name = "CooldownListClip"
clipRoot.AnchorPoint = Vector2.new(1, 0)
clipRoot.BackgroundTransparency = 1
clipRoot.BorderSizePixel = 0
clipRoot.ClipsDescendants = true
clipRoot.Parent = safeBounds

local scaleContainer = Instance.new("Frame")
scaleContainer.Name = "ScaleContainer"
scaleContainer.BackgroundTransparency = 1
scaleContainer.BorderSizePixel = 0
scaleContainer.Position = UDim2.fromOffset(0, 0)
scaleContainer.Parent = clipRoot

local uiScale = Instance.new("UIScale")
uiScale.Name = "ReferenceUIScale"
uiScale.Scale = 1
uiScale.Parent = scaleContainer

local scrollingList = Instance.new("ScrollingFrame")
scrollingList.Name = "CooldownList"
scrollingList.Position = UDim2.fromOffset(0, 0)
scrollingList.BackgroundTransparency = 1
scrollingList.BorderSizePixel = 0
scrollingList.ClipsDescendants = true
scrollingList.CanvasSize = UDim2.fromOffset(ROW_WIDTH, 0)
scrollingList.CanvasPosition = Vector2.zero
scrollingList.ScrollBarThickness = 0
scrollingList.ScrollingDirection = Enum.ScrollingDirection.Y
scrollingList.ScrollingEnabled = true
scrollingList.ElasticBehavior = Enum.ElasticBehavior.Never
scrollingList.Parent = scaleContainer

-- ============================================================
-- STATE
-- ============================================================
local activeOrder: {CooldownRecord} = {}
local byId: {[string]: CooldownRecord} = {}
local characterConnections: {RBXScriptConnection} = {}
local globalConnections: {RBXScriptConnection} = {}
local ryoConnections: {RBXScriptConnection} = {}
local currentCharacter: Model? = nil
local currentScale = 1

-- ============================================================
-- LAYOUT / SAFE-AREA HELPERS
-- ============================================================
local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
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

	return math.min(
		viewport.X / REFERENCE_WIDTH,
		viewport.Y / REFERENCE_HEIGHT
	)
end

local function getRyoTopAbsoluteY(): number?
	local ryoGui = playerGui:FindFirstChild("RyoHUD")
	if not ryoGui then
		return nil
	end

	local container = ryoGui:FindFirstChild("Container")
	if not container or not container:IsA("GuiObject") then
		return nil
	end

	return container.AbsolutePosition.Y
end

local function updateListCanvasSize()
	local totalHeight = 0
	if #activeOrder > 0 then
		totalHeight = ((#activeOrder - 1) * ROW_PITCH) + ROW_HEIGHT
	end

	scrollingList.CanvasSize = UDim2.fromOffset(ROW_WIDTH, totalHeight)
end

local function updateScaleAndBounds()
	currentScale = getReferenceScale()
	uiScale.Scale = currentScale

	local safeAbsoluteTop = safeBounds.AbsolutePosition.Y
	local safeAbsoluteBottom = safeAbsoluteTop + safeBounds.AbsoluteSize.Y
	local clipBottom = safeAbsoluteBottom

	local ryoTop = getRyoTopAbsoluteY()
	if ryoTop then
		clipBottom = math.min(clipBottom, ryoTop)
	end

	local rootTop = safeAbsoluteTop + (TOP_OFFSET * currentScale)
	local availableHeightPixels = math.max(0, clipBottom - rootTop)
	local availableHeightReference = if currentScale > 0
		then availableHeightPixels / currentScale
		else 0

	clipRoot.Position = UDim2.new(1, -(RIGHT_OFFSET * currentScale), 0, TOP_OFFSET * currentScale)
	clipRoot.Size = UDim2.fromOffset(ROW_WIDTH * currentScale, availableHeightPixels)

	scaleContainer.Size = UDim2.fromOffset(ROW_WIDTH, availableHeightReference)
	scrollingList.Size = UDim2.fromOffset(ROW_WIDTH, availableHeightReference)
end

local function clearRyoConnections()
	for _, connection in ipairs(ryoConnections) do
		connection:Disconnect()
	end
	table.clear(ryoConnections)
end

local function bindRyoBounds()
	clearRyoConnections()

	local ryoGui = playerGui:FindFirstChild("RyoHUD")
	if not ryoGui then
		updateScaleAndBounds()
		return
	end

	local container = ryoGui:FindFirstChild("Container")
	if container and container:IsA("GuiObject") then
		table.insert(ryoConnections, container:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateScaleAndBounds))
		table.insert(ryoConnections, container:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScaleAndBounds))
	end

	updateScaleAndBounds()
end

-- ============================================================
-- ASTRA POLYGON RASTERIZATION
-- ============================================================
local function polygonSpanAtPercent(yPercent: number): (number, number)
	local intersections: {number} = {}
	local pointCount = #SURFACE_POLYGON

	for index = 1, pointCount do
		local a = SURFACE_POLYGON[index]
		local b = SURFACE_POLYGON[(index % pointCount) + 1]
		local ax = a[1]
		local ay = a[2]
		local bx = b[1]
		local by = b[2]

		if ay ~= by then
			local lowY = math.min(ay, by)
			local highY = math.max(ay, by)

			-- Half-open edge test avoids double-counting polygon vertices.
			if yPercent >= lowY and yPercent < highY then
				local t = (yPercent - ay) / (by - ay)
				table.insert(intersections, ax + ((bx - ax) * t))
			end
		end
	end

	table.sort(intersections)
	if #intersections < 2 then
		return 0, 0
	end

	return intersections[1], intersections[#intersections]
end

local function createSurface(row: CanvasGroup)
	for pixelY = 0, SURFACE_HEIGHT - 1 do
		local yPercent = ((pixelY + 0.5) / SURFACE_HEIGHT) * 100
		local minPercent, maxPercent = polygonSpanAtPercent(yPercent)

		if maxPercent > minPercent then
			local localX = (minPercent / 100) * SURFACE_WIDTH
			local localWidth = ((maxPercent - minPercent) / 100) * SURFACE_WIDTH

			local stripe = Instance.new("Frame")
			stripe.Name = "SurfaceRow_" .. tostring(pixelY + 1)
			stripe.Position = UDim2.fromOffset(SURFACE_X + localX, SURFACE_Y + pixelY)
			stripe.Size = UDim2.fromOffset(localWidth, 1)
			stripe.BackgroundColor3 = SURFACE_COLOR
			stripe.BackgroundTransparency = SURFACE_TRANSPARENCY
			stripe.BorderSizePixel = 0
			stripe.ClipsDescendants = true
			stripe.ZIndex = 1
			stripe.Parent = row

			local clouds = Instance.new("ImageLabel")
			clouds.Name = "Clouds"
			clouds.Position = UDim2.fromOffset(-localX, -pixelY)
			clouds.Size = UDim2.fromOffset(SURFACE_WIDTH, SURFACE_HEIGHT)
			clouds.BackgroundTransparency = 1
			clouds.Image = CLOUD_ENGRAVING_IMAGE
			clouds.ImageTransparency = CLOUD_TRANSPARENCY
			clouds.ScaleType = Enum.ScaleType.Tile
			clouds.TileSize = UDim2.fromOffset(CLOUD_TILE_WIDTH, CLOUD_TILE_HEIGHT)
			clouds.ZIndex = 2
			clouds.Parent = stripe
		end
	end
end

-- ============================================================
-- TEXT HELPERS
-- ============================================================
local function createTextPair(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	width: number,
	height: number,
	fontFace: Font,
	textSize: number,
	color: Color3,
	alignment: Enum.TextXAlignment
): (TextLabel, TextLabel)
	local shadow = Instance.new("TextLabel")
	shadow.Name = name .. "Shadow"
	shadow.Position = UDim2.fromOffset(x, y + 1)
	shadow.Size = UDim2.fromOffset(width, height)
	shadow.BackgroundTransparency = 1
	shadow.BorderSizePixel = 0
	shadow.FontFace = fontFace
	shadow.TextSize = textSize
	shadow.TextScaled = false
	shadow.TextWrapped = false
	shadow.TextColor3 = Color3.new(0, 0, 0)
	shadow.TextXAlignment = alignment
	shadow.TextYAlignment = Enum.TextYAlignment.Center
	shadow.TextTruncate = Enum.TextTruncate.AtEnd
	shadow.ZIndex = 4
	shadow.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = fontFace
	label.TextSize = textSize
	label.TextScaled = false
	label.TextWrapped = false
	label.TextColor3 = color
	label.TextXAlignment = alignment
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 4
	label.Parent = parent

	return label, shadow
end

local function setTextPair(label: TextLabel, shadow: TextLabel, text: string)
	label.Text = text
	shadow.Text = text
end

local function setTimerFont(record: CooldownRecord, fontFace: Font)
	record.timerLabel.FontFace = fontFace
	record.timerShadow.FontFace = fontFace
end

-- ============================================================
-- ROW CREATION
-- ============================================================
local function createCooldownRow(actionId: string, displayName: string): CooldownRecord
	local row = Instance.new("CanvasGroup")
	row.Name = actionId .. "Cooldown"
	row.Size = UDim2.fromOffset(ROW_WIDTH, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.ClipsDescendants = true
	row.GroupTransparency = 1
	row.ZIndex = 1
	row.Parent = scrollingList

	createSurface(row)

	local frame = Instance.new("ImageLabel")
	frame.Name = "Frame"
	frame.Position = UDim2.fromOffset(0, 0)
	frame.Size = UDim2.fromOffset(ROW_WIDTH, ROW_HEIGHT)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Image = COOLDOWN_FRAME_IMAGE
	frame.ImageTransparency = 0
	frame.ScaleType = Enum.ScaleType.Stretch
	frame.ZIndex = 3
	frame.Parent = row

	local nameLabel, nameShadow = createTextPair(
		row,
		"Name",
		NAME_X,
		NAME_Y,
		NAME_WIDTH,
		NAME_HEIGHT,
		TITLE_FONT,
		NAME_TEXT_SIZE,
		NAME_COLOR,
		Enum.TextXAlignment.Left
	)
	setTextPair(nameLabel, nameShadow, displayName)

	local timerLabel, timerShadow = createTextPair(
		row,
		"Timer",
		TIMER_X,
		TIMER_Y,
		TIMER_WIDTH,
		TIMER_HEIGHT,
		NUMBER_FONT,
		TIMER_TEXT_SIZE,
		TIMER_COLOR,
		Enum.TextXAlignment.Right
	)
	setTextPair(timerLabel, timerShadow, "")

	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Position = UDim2.fromOffset(PROGRESS_X, PROGRESS_Y)
	progress.Size = UDim2.fromOffset(PROGRESS_WIDTH, PROGRESS_HEIGHT)
	progress.BackgroundColor3 = PROGRESS_COLOR
	progress.BackgroundTransparency = PROGRESS_TRANSPARENCY
	progress.BorderSizePixel = 0
	progress.ZIndex = 4
	progress.Parent = row

	return {
		id = actionId,
		label = displayName,
		duration = 1,
		expiresAt = 0,
		row = row,
		nameLabel = nameLabel,
		nameShadow = nameShadow,
		timerLabel = timerLabel,
		timerShadow = timerShadow,
		progress = progress,
		layoutTween = nil,
		entryTween = nil,
		fadeTween = nil,
		removing = false,
		ready = false,
		readyUntil = 0,
	}
end

-- ============================================================
-- ORDER / ANIMATION
-- ============================================================
local function indexOf(record: CooldownRecord): number?
	for index, item in ipairs(activeOrder) do
		if item == record then
			return index
		end
	end
	return nil
end

local function targetPositionForIndex(index: number): UDim2
	return UDim2.fromOffset(0, (index - 1) * ROW_PITCH)
end

local function reflow(skipRecord: CooldownRecord?)
	updateListCanvasSize()

	for index, record in ipairs(activeOrder) do
		if record == skipRecord then
			continue
		end

		if record.removing or not record.row.Parent then
			continue
		end

		cancelTween(record.layoutTween)
		record.layoutTween = TweenService:Create(
			record.row,
			TweenInfo.new(REFLOW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = targetPositionForIndex(index)}
		)
		record.layoutTween:Play()
	end
end

local function beginRemove(record: CooldownRecord)
	if record.removing then
		return
	end

	record.removing = true
	if byId[record.id] == record then
		byId[record.id] = nil
	end

	local orderIndex = indexOf(record)
	if orderIndex then
		table.remove(activeOrder, orderIndex)
	end

	cancelTween(record.layoutTween)
	cancelTween(record.entryTween)
	cancelTween(record.fadeTween)

	local currentPosition = record.row.Position
	local exitTarget = UDim2.new(
		currentPosition.X.Scale,
		currentPosition.X.Offset + EXIT_TRANSLATE_X,
		currentPosition.Y.Scale,
		currentPosition.Y.Offset
	)

	record.layoutTween = TweenService:Create(
		record.row,
		TweenInfo.new(EXIT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = exitTarget}
	)
	record.fadeTween = TweenService:Create(
		record.row,
		TweenInfo.new(EXIT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{GroupTransparency = 1}
	)

	record.layoutTween:Play()
	record.fadeTween:Play()
	reflow()

	record.fadeTween.Completed:Once(function()
		if record.row.Parent then
			record.row:Destroy()
		end
	end)
end

local function removeImmediate(record: CooldownRecord)
	if byId[record.id] == record then
		byId[record.id] = nil
	end

	local orderIndex = indexOf(record)
	if orderIndex then
		table.remove(activeOrder, orderIndex)
	end

	cancelTween(record.layoutTween)
	cancelTween(record.entryTween)
	cancelTween(record.fadeTween)

	if record.row.Parent then
		record.row:Destroy()
	end
end

-- ============================================================
-- ASTRA API
-- ============================================================
local function StartCooldown(
	actionId: string,
	displayName: string,
	durationSeconds: number,
	expiresAt: number
)
	if actionId == ""
		or displayName == ""
		or durationSeconds <= 0
		or durationSeconds ~= durationSeconds then
		return
	end

	local serverNow = Workspace:GetServerTimeNow()
	local resolvedExpiresAt = if expiresAt > serverNow
		then expiresAt
		else serverNow + durationSeconds

	local existing = byId[actionId]
	if existing and not existing.removing and existing.row.Parent then
		existing.label = displayName
		existing.duration = durationSeconds
		existing.expiresAt = resolvedExpiresAt
		existing.ready = false
		existing.readyUntil = 0
		existing.progress.Visible = true
		existing.timerLabel.TextColor3 = TIMER_COLOR
		setTimerFont(existing, NUMBER_FONT)
		setTextPair(existing.nameLabel, existing.nameShadow, displayName)
		return
	end

	local record = createCooldownRow(actionId, displayName)
	record.duration = durationSeconds
	record.expiresAt = resolvedExpiresAt

	byId[actionId] = record
	table.insert(activeOrder, 1, record)

	local target = targetPositionForIndex(1)
	record.row.Position = UDim2.fromOffset(ENTRY_FROM_X, target.Y.Offset)
	record.row.GroupTransparency = 1

	record.entryTween = TweenService:Create(
		record.row,
		TweenInfo.new(ENTRY_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = target}
	)
	record.fadeTween = TweenService:Create(
		record.row,
		TweenInfo.new(ENTRY_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{GroupTransparency = 0}
	)

	updateListCanvasSize()
	reflow(record)
	record.entryTween:Play()
	record.fadeTween:Play()
end

local function RemoveCooldown(actionId: string)
	local record = byId[actionId]
	if record then
		beginRemove(record)
	end
end

local function Clear()
	local snapshot = table.clone(activeOrder)
	for _, record in ipairs(snapshot) do
		beginRemove(record)
	end
end

local function clearImmediate()
	local snapshot = table.clone(activeOrder)
	for _, record in ipairs(snapshot) do
		removeImmediate(record)
	end
	table.clear(activeOrder)
	table.clear(byId)
	updateListCanvasSize()
end

-- ============================================================
-- GENERIC CORE COOLDOWN BACKEND ADAPTER
-- ============================================================
local CORE_PREFIX = "CoreCooldown_"
local ENDS_SUFFIX = "_EndsAt"
local STARTS_SUFFIX = "_StartsAt"
local LABEL_SUFFIX = "_Label"

local function getAbilityIdFromEndsAttribute(attributeName: string): string?
	if string.sub(attributeName, 1, #CORE_PREFIX) ~= CORE_PREFIX then
		return nil
	end
	if string.sub(attributeName, -#ENDS_SUFFIX) ~= ENDS_SUFFIX then
		return nil
	end

	local abilityId = string.sub(attributeName, #CORE_PREFIX + 1, #attributeName - #ENDS_SUFFIX)
	if abilityId == "" then
		return nil
	end

	return abilityId
end

local function defaultLabelFromId(abilityId: string): string
	return string.gsub(abilityId, "(%l)(%u)", "%1 %2")
end

local function syncCoreCooldown(abilityId: string)
	if isTechniqueLoadoutAbility(abilityId) then
		RemoveCooldown(abilityId)
		return
	end

	local character = currentCharacter
	if not character or not character.Parent then
		return
	end

	local serverNow = Workspace:GetServerTimeNow()
	local endsAt = character:GetAttribute(CORE_PREFIX .. abilityId .. ENDS_SUFFIX)
	if typeof(endsAt) ~= "number" or endsAt <= serverNow then
		return
	end

	local startsAt = character:GetAttribute(CORE_PREFIX .. abilityId .. STARTS_SUFFIX)
	local duration: number
	if typeof(startsAt) == "number" and startsAt < endsAt then
		duration = endsAt - startsAt
	else
		duration = math.max(endsAt - serverNow, 0.001)
	end

	local label = character:GetAttribute(CORE_PREFIX .. abilityId .. LABEL_SUFFIX)
	if typeof(label) ~= "string" or label == "" then
		label = defaultLabelFromId(abilityId)
	end

	StartCooldown(abilityId, label, duration, endsAt)
end

local function syncAllCoreCooldowns()
	local character = currentCharacter
	if not character or not character.Parent then
		return
	end

	for attributeName in pairs(character:GetAttributes()) do
		local abilityId = getAbilityIdFromEndsAttribute(attributeName)
		if abilityId then
			syncCoreCooldown(abilityId)
		end
	end
end

-- ============================================================
-- CHARACTER BINDING
-- ============================================================
local function clearCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function bindCharacter(character: Model)
	clearCharacterConnections()
	clearImmediate()
	currentCharacter = character

	table.insert(characterConnections, character.AttributeChanged:Connect(function(attributeName: string)
		local abilityId = getAbilityIdFromEndsAttribute(attributeName)
		if abilityId then
			syncCoreCooldown(abilityId)
		end
	end))

	task.defer(syncAllCoreCooldowns)
end

table.insert(globalConnections, player.CharacterAdded:Connect(bindCharacter))
table.insert(globalConnections, player.CharacterRemoving:Connect(function(character: Model)
	if currentCharacter == character then
		clearCharacterConnections()
		currentCharacter = nil
		clearImmediate()
	end
end))

if player.Character then
	bindCharacter(player.Character)
end

-- If a core action is moved into the technique hotbar while its generic row is
-- visible, remove it so the two cooldown presentations never duplicate.
for slotIndex = 1, TECHNIQUE_SLOT_COUNT do
	local attributeName = "TechniqueLoadoutSlot_" .. tostring(slotIndex)
	table.insert(globalConnections, player:GetAttributeChangedSignal(attributeName):Connect(function()
		local techniqueId = player:GetAttribute(attributeName)
		if typeof(techniqueId) == "string" and techniqueId ~= "" then
			RemoveCooldown(techniqueId)
		end
	end))
end

-- ============================================================
-- TIME / READY STATE
-- ============================================================
table.insert(globalConnections, RunService.RenderStepped:Connect(function()
	local serverNow = Workspace:GetServerTimeNow()
	local snapshot = table.clone(activeOrder)

	for _, record in ipairs(snapshot) do
		if record.removing or not record.row.Parent then
			continue
		end

		local remaining = math.max(0, record.expiresAt - serverNow)

		if remaining <= 0 then
			if not record.ready then
				record.ready = true
				record.readyUntil = serverNow + READY_DURATION
				record.progress.Visible = false
				record.timerLabel.TextColor3 = READY_COLOR
				setTimerFont(record, TITLE_FONT)
				setTextPair(record.timerLabel, record.timerShadow, "Ready")
			elseif serverNow >= record.readyUntil then
				beginRemove(record)
			end

			continue
		end

		if record.ready then
			-- A same-ID refresh during Ready immediately restores active state.
			record.ready = false
			record.readyUntil = 0
			record.progress.Visible = true
			record.timerLabel.TextColor3 = TIMER_COLOR
			setTimerFont(record, NUMBER_FONT)
		end

		local secondsText = tostring(math.ceil(remaining)) .. "s"
		setTextPair(record.timerLabel, record.timerShadow, secondsText)

		local ratio = math.clamp(remaining / math.max(record.duration, 0.001), 0, 1)
		record.progress.Size = UDim2.fromOffset(PROGRESS_WIDTH * ratio, PROGRESS_HEIGHT)
	end
end))

-- ============================================================
-- SAFE-AREA / MONEY-HUD BINDING
-- ============================================================
table.insert(globalConnections, safeBounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScaleAndBounds))
table.insert(globalConnections, safeBounds:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateScaleAndBounds))
table.insert(globalConnections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScaleAndBounds))

table.insert(globalConnections, playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "RyoHUD" then
		task.defer(bindRyoBounds)
	end
end))

table.insert(globalConnections, playerGui.ChildRemoved:Connect(function(child: Instance)
	if child.Name == "RyoHUD" then
		clearRyoConnections()
		task.defer(updateScaleAndBounds)
	end
end))

local camera = Workspace.CurrentCamera
if camera then
	table.insert(globalConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScaleAndBounds))
end

bindRyoBounds()
task.defer(updateScaleAndBounds)

-- ============================================================
-- ASSET-ID GUARD
-- ============================================================
if COOLDOWN_FRAME_IMAGE == "" or CLOUD_ENGRAVING_IMAGE == "" then
	warn(
		"[CooldownHUD] Astra layout installed, but AssetIds are still empty. "
			.. "Upload CooldownFrame.png and the Roblox-ready CloudEngraving 2.2x brightness copy, "
			.. "then set their real rbxassetid:// values in CooldownPopupController."
	)
end

script.Destroying:Connect(function()
	clearCharacterConnections()
	clearRyoConnections()

	for _, connection in ipairs(globalConnections) do
		connection:Disconnect()
	end
	table.clear(globalConnections)

	clearImmediate()
end)

print(
	"[CooldownHUD] READY v14 AstraSpec"
		.. " | CoreCooldown backend"
		.. " | 240x40 rows"
		.. " | newestTop=ON"
		.. " | Ready1s=ON"
		.. " | safeArea=ON"
		.. " | ryoClip=ON"
		.. " | assetIds="
		.. ((COOLDOWN_FRAME_IMAGE ~= "" and CLOUD_ENGRAVING_IMAGE ~= "") and "READY" or "PENDING")
)

-- Keep the exact API names present in this controller for future local adapters.
-- Existing gameplay systems currently enter through CoreCooldown_* attributes.
local _apiKeepalive = {
	StartCooldown = StartCooldown,
	RemoveCooldown = RemoveCooldown,
	Clear = Clear,
}
if false then
	print(_apiKeepalive)
end
