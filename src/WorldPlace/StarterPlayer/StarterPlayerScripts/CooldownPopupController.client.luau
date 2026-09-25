--!strict
-- CooldownPopupController v13 - CoreOnly Popup + Technique Hotbar Split
--
-- PLACE:
-- StarterPlayer > StarterPlayerScripts > CooldownPopupController
--
-- PURPOSE:
-- Temporary cooldown popups for CORE mechanics using a skinned bar art.
-- This remains generic and source-driven via CoreCooldown_* attributes.
--
-- ART:
-- rbxassetid://120582051620258
-- ImageTransparency = 0.35

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- TECHNIQUE COOLDOWN PRESENTATION SPLIT
-- ============================================================
--
-- Techniques already have their own cooldown presentation in the
-- 10-slot TechniqueHotbarController. This popup remains reserved for
-- non-technique CORE mechanics such as Launcher, Lunge, AerialKick,
-- Substitution, etc.
--
-- We identify active techniques from the same authoritative replicated
-- TechniqueLoadoutSlot_1 ... TechniqueLoadoutSlot_10 attributes.
local TECHNIQUE_SLOT_COUNT = 10

local function isTechniqueLoadoutAbility(abilityId: string): boolean
	for slotIndex = 1, TECHNIQUE_SLOT_COUNT do
		local techniqueId =
			player:GetAttribute(
				"TechniqueLoadoutSlot_"
				.. tostring(slotIndex)
			)

		if typeof(techniqueId) == "string"
			and techniqueId ~= ""
			and techniqueId == abilityId then

			return true
		end
	end

	return false
end

-- ============================================================
-- VISUAL / LAYOUT
-- ============================================================

local RIGHT_MARGIN = 10
local BASE_Y_SCALE = 0.50

-- Larger than v4 so the art reads clearly.
local POPUP_WIDTH = 252
local POPUP_HEIGHT = 66
local POPUP_GAP = 8

local ENTRY_FROM_BELOW = 16
local EXIT_RISE = 18

local ENTRY_TIME = 0.16
local EXIT_TIME = 0.16
local REFLOW_TIME = 0.18

-- When cooldown reaches zero, keep 0.0 visible in gold briefly,
-- then remove. We no longer show the word READY.
local ZERO_HOLD_TIME = 0.75
local UPDATE_INTERVAL = 0.035

local SKIN_IMAGE = "rbxassetid://124946606271089"
local SKIN_TRANSPARENCY = 0.35

-- Transparent-border trim without editing the uploaded asset:
-- render the skin slightly oversized inside the popup canvas.
local SKIN_OVERSCALE_X = 1.03
local SKIN_OVERSCALE_Y = 1.05

-- Artwork-aligned regions.
-- Long left bar body.
local TITLE_POS = UDim2.fromScale(0.165, 0.455)
local TITLE_SIZE = UDim2.fromScale(0.49, 0.18)

-- Right square cap.
local TIMER_BASE_POSITION = UDim2.fromScale(0.822, 0.455)
local TIMER_SIZE = UDim2.fromScale(0.13, 0.20)

-- Progress bar intentionally disabled in v9.
local PROGRESS_POS = UDim2.fromScale(0.085, 0.665)
local PROGRESS_SIZE = UDim2.fromScale(0, 0)

-- ============================================================
-- PALETTE
-- ============================================================

local COLOR_TEXT = Color3.fromRGB(238, 234, 224)
local COLOR_TIMER = Color3.fromRGB(196, 48, 39)
local COLOR_ZERO = Color3.fromRGB(220, 177, 76)
local COLOR_TRACK = Color3.fromRGB(40, 37, 33)
local COLOR_FILL = Color3.fromRGB(220, 177, 76)

-- ============================================================
-- TYPES
-- ============================================================

type PopupRecord = {
	id: string,
	label: string,
	duration: number,
	endsAt: number,
	canvas: CanvasGroup,
	skin: ImageLabel,
	title: TextLabel,
	timer: TextLabel,
	progressTrack: Frame,
	progressFill: Frame,
	layoutTween: Tween?,
	removing: boolean,
	inReadyState: boolean,
	readyUntil: number,
	statusTransitionToken: number,
	timerTween: Tween?,
	generation: number,
}

-- ============================================================
-- GUI ROOT
-- ============================================================

for _, oldName in ipairs({
	"CooldownHUDGui",
	"CooldownPopupGui",
	}) do
	local old = playerGui:FindFirstChild(oldName)
	if old then
		old:Destroy()
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CooldownPopupGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 91
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "CooldownPopupRoot"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = screenGui

-- ============================================================
-- STATE
-- ============================================================

local activeOrder: {PopupRecord} = {}
local byId: {[string]: PopupRecord} = {}
local nextGeneration = 0
local characterConnections: {RBXScriptConnection} = {}
local currentCharacter: Model? = nil

-- ============================================================
-- HELPERS
-- ============================================================

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function targetPositionForIndex(index: number): UDim2
	local yOffset = (index - 1) * (POPUP_HEIGHT + POPUP_GAP)
	return UDim2.new(1, -RIGHT_MARGIN, BASE_Y_SCALE, yOffset)
end

local function formatRemaining(remaining: number): string
	if remaining >= 10 then
		return string.format("%.0f", remaining)
	end
	return string.format("%.1f", math.max(0, remaining))
end

local function cancelLayoutTween(record: PopupRecord)
	if record.layoutTween then
		record.layoutTween:Cancel()
		record.layoutTween = nil
	end
end

local function reflow()
	for index, record in ipairs(activeOrder) do
		if record.removing or not record.canvas.Parent then
			continue
		end

		cancelLayoutTween(record)
		record.layoutTween = TweenService:Create(
			record.canvas,
			TweenInfo.new(REFLOW_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = targetPositionForIndex(index) }
		)
		record.layoutTween:Play()
	end
end

local function createPopupVisual(id: string, label: string): PopupRecord
	nextGeneration += 1
	local generation = nextGeneration

	local canvas = Instance.new("CanvasGroup")
	canvas.Name = id .. "Cooldown"
	canvas.AnchorPoint = Vector2.new(1, 0.5)
	canvas.Size = UDim2.fromOffset(POPUP_WIDTH, POPUP_HEIGHT)
	canvas.BackgroundTransparency = 1
	canvas.GroupTransparency = 1
	canvas.ZIndex = 50
	canvas.Parent = root

	local skin = Instance.new("ImageLabel")
	skin.Name = "Skin"
	skin.AnchorPoint = Vector2.new(0.5, 0.5)
	skin.Position = UDim2.fromScale(0.5, 0.5)
	skin.BackgroundTransparency = 1
	skin.Size = UDim2.fromScale(
		SKIN_OVERSCALE_X,
		SKIN_OVERSCALE_Y
	)
	skin.Image = SKIN_IMAGE
	skin.ImageTransparency = SKIN_TRANSPARENCY
	skin.ScaleType = Enum.ScaleType.Fit
	skin.ZIndex = 51
	skin.Parent = canvas

	local title = Instance.new("TextLabel")
	title.Name = "AbilityName"
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = TITLE_POS
	title.Size = TITLE_SIZE
	title.BackgroundTransparency = 1
	title.Text = label
	title.TextColor3 = COLOR_TEXT
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.70
	title.Font = Enum.Font.GothamSemibold
	title.TextScaled = false
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 53
	title.Parent = skin

	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 12
	titleConstraint.MaxTextSize = 12
	titleConstraint.Parent = title

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0.5, 0.5)
	timer.Position = TIMER_BASE_POSITION
	timer.Size = TIMER_SIZE
	timer.BackgroundTransparency = 1
	timer.Text = "0.0"
	timer.TextColor3 = COLOR_TIMER
	timer.TextStrokeColor3 = Color3.new(0, 0, 0)
	timer.TextStrokeTransparency = 0.34
	timer.Font = Enum.Font.GothamBold
	timer.TextScaled = false
	timer.TextXAlignment = Enum.TextXAlignment.Center
	timer.TextYAlignment = Enum.TextYAlignment.Center
	timer.ZIndex = 54
	timer.Parent = skin

	local timerConstraint = Instance.new("UITextSizeConstraint")
	timerConstraint.MinTextSize = 14
	timerConstraint.MaxTextSize = 14
	timerConstraint.Parent = timer

	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "ProgressTrack"
	progressTrack.AnchorPoint = Vector2.new(0, 0)
	progressTrack.Position = PROGRESS_POS
	progressTrack.Size = PROGRESS_SIZE
	progressTrack.BackgroundTransparency = 1
	progressTrack.BorderSizePixel = 0
	progressTrack.Visible = false
	progressTrack.ZIndex = 52
	progressTrack.Parent = skin

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Progress"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundTransparency = 1
	progressFill.BorderSizePixel = 0
	progressFill.Visible = false
	progressFill.ZIndex = 53
	progressFill.Parent = progressTrack

	return {
		id = id,
		label = label,
		duration = 1,
		endsAt = 0,
		canvas = canvas,
		skin = skin,
		title = title,
		timer = timer,
		progressTrack = progressTrack,
		progressFill = progressFill,
		layoutTween = nil,
		removing = false,
		inReadyState = false,
		readyUntil = 0,
		statusTransitionToken = 0,
		timerTween = nil,
		generation = generation,
	}
end

local function cancelTimerTween(record: PopupRecord)
	if record.timerTween then
		record.timerTween:Cancel()
		record.timerTween = nil
	end
end

local function removeFromOrder(record: PopupRecord)
	for index, item in ipairs(activeOrder) do
		if item == record then
			table.remove(activeOrder, index)
			return
		end
	end
end

local function beginRemove(record: PopupRecord)
	if record.removing then
		return
	end

	record.removing = true
	record.statusTransitionToken += 1
	cancelTimerTween(record)

	if byId[record.id] == record then
		byId[record.id] = nil
	end

	removeFromOrder(record)
	reflow()
	cancelLayoutTween(record)

	local exitTarget = UDim2.new(
		record.canvas.Position.X.Scale,
		record.canvas.Position.X.Offset,
		record.canvas.Position.Y.Scale,
		record.canvas.Position.Y.Offset - EXIT_RISE
	)

	local positionTween = TweenService:Create(
		record.canvas,
		TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = exitTarget }
	)

	local fadeTween = TweenService:Create(
		record.canvas,
		TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ GroupTransparency = 1 }
	)

	positionTween:Play()
	fadeTween:Play()

	fadeTween.Completed:Once(function()
		if record.canvas.Parent then
			record.canvas:Destroy()
		end
	end)
end

local function showCooldown(id: string, label: string, duration: number, endsAt: number?)
	if typeof(id) ~= "string"
		or id == ""
		or typeof(label) ~= "string"
		or label == ""
		or typeof(duration) ~= "number"
		or duration <= 0
		or duration ~= duration then
		return
	end

	local now = Workspace:GetServerTimeNow()
	local finalEndsAt = if typeof(endsAt) == "number" and endsAt > now then endsAt else now + duration

	local existing = byId[id]
	if existing and not existing.removing and existing.canvas.Parent then
		existing.label = label
		existing.title.Text = label
		existing.duration = duration
		existing.endsAt = finalEndsAt
		existing.inReadyState = false
		existing.readyUntil = 0
		existing.statusTransitionToken += 1
		cancelTimerTween(existing)
		existing.timer.TextColor3 = COLOR_TIMER
		existing.timer.TextTransparency = 0
		existing.timer.TextStrokeTransparency = 0.34
		existing.timer.Position = TIMER_BASE_POSITION
		existing.progressFill.BackgroundColor3 = COLOR_FILL
		return
	end

	local record = createPopupVisual(id, label)
	record.duration = duration
	record.endsAt = finalEndsAt

	byId[id] = record
	table.insert(activeOrder, record)

	local targetIndex = #activeOrder
	local target = targetPositionForIndex(targetIndex)

	record.canvas.Position = UDim2.new(target.X.Scale, target.X.Offset, target.Y.Scale, target.Y.Offset + ENTRY_FROM_BELOW)
	record.canvas.GroupTransparency = 1

	local positionTween = TweenService:Create(
		record.canvas,
		TweenInfo.new(ENTRY_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = target }
	)

	local fadeTween = TweenService:Create(
		record.canvas,
		TweenInfo.new(ENTRY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	)

	record.layoutTween = positionTween
	positionTween:Play()
	fadeTween:Play()
end

-- ============================================================
-- GENERIC CORE COOLDOWN CONTRACT
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
	-- Jutsu/technique cooldowns belong exclusively to the 10-slot hotbar.
	if isTechniqueLoadoutAbility(abilityId) then
		return
	end

	local character = currentCharacter
	if not character or not character.Parent then
		return
	end

	local now = Workspace:GetServerTimeNow()
	local endsAt = character:GetAttribute(CORE_PREFIX .. abilityId .. ENDS_SUFFIX)
	if typeof(endsAt) ~= "number" or endsAt <= now then
		return
	end

	local startsAt = character:GetAttribute(CORE_PREFIX .. abilityId .. STARTS_SUFFIX)
	local duration: number
	if typeof(startsAt) == "number" and startsAt < endsAt then
		duration = endsAt - startsAt
	else
		duration = math.max(endsAt - now, 0.001)
	end

	local label = character:GetAttribute(CORE_PREFIX .. abilityId .. LABEL_SUFFIX)
	if typeof(label) ~= "string" or label == "" then
		label = defaultLabelFromId(abilityId)
	end

	showCooldown(abilityId, label, duration, endsAt)
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
	currentCharacter = character

	table.insert(
		characterConnections,
		character.AttributeChanged:Connect(function(attributeName: string)
			local abilityId = getAbilityIdFromEndsAttribute(attributeName)
			if abilityId then
				syncCoreCooldown(abilityId)
			end
		end)
	)

	task.defer(syncAllCoreCooldowns)
end

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function(character: Model)
	if currentCharacter == character then
		clearCharacterConnections()
		currentCharacter = nil
	end
end)

if player.Character then
	bindCharacter(player.Character)
end

-- If a technique is moved into the loadout while a generic popup with the
-- same Id already exists, remove that row immediately. This keeps the
-- presentation contract correct even without restarting the client.
for slotIndex = 1, TECHNIQUE_SLOT_COUNT do
	local attributeName =
		"TechniqueLoadoutSlot_"
		.. tostring(slotIndex)

	player:
		GetAttributeChangedSignal(
			attributeName
		):
		Connect(function()
			local techniqueId =
			player:GetAttribute(
				attributeName
			)

			if typeof(techniqueId) ~= "string"
				or techniqueId == "" then

				return
			end

			local existing =
			byId[techniqueId]

			if existing
				and not existing.removing then

				beginRemove(
					existing
				)
			end
		end)
end

-- ============================================================
-- TIMER UPDATE / REMOVAL
-- ============================================================

local accumulator = 0

RunService.RenderStepped:Connect(function(deltaTime: number)
	accumulator += deltaTime
	if accumulator < UPDATE_INTERVAL then
		return
	end
	accumulator = 0

	local now = Workspace:GetServerTimeNow()
	local snapshot = table.clone(activeOrder)

	for _, record in ipairs(snapshot) do
		if record.removing or not record.canvas.Parent then
			continue
		end

		local remaining = record.endsAt - now

		if remaining <= 0 then
			if not record.inReadyState then
				record.inReadyState = true
				record.readyUntil = now + ZERO_HOLD_TIME
				record.statusTransitionToken += 1
				cancelTimerTween(record)

				record.timer.Text = "0.0"
				record.timer.TextColor3 = COLOR_ZERO
				record.timer.TextTransparency = 0
				record.timer.TextStrokeTransparency = 0.34
				record.timer.Position = TIMER_BASE_POSITION

				record.progressFill.Size = UDim2.fromScale(0, 1)
				record.progressFill.BackgroundColor3 = COLOR_FILL
			elseif now >= record.readyUntil then
				beginRemove(record)
			end

			continue
		end

		if record.inReadyState then
			record.statusTransitionToken += 1
			cancelTimerTween(record)
		end

		record.inReadyState = false
		record.readyUntil = 0
		record.timer.TextColor3 = COLOR_TIMER
		record.timer.TextTransparency = 0
		record.timer.TextStrokeTransparency = 0.34
		record.timer.Position = TIMER_BASE_POSITION
		record.timer.Text = formatRemaining(remaining)

		local ratio = math.clamp(remaining / math.max(record.duration, 0.001), 0, 1)
		record.progressFill.Size = UDim2.fromScale(ratio, 1)
	end
end)

print(
	"[CooldownPopup] READY v13 CoreOnlyTechniqueSplit"
		.. " | generic CoreCooldown_* contract"
		.. " | Skin=124946606271089"
		.. " | Transparency=35%"
		.. " | LargerBar=OFF"
		.. " | SmallerBar=ON"
		.. " | NoProgressBar=ON"
		.. " | ReadyText=OFF"
		.. " | ZeroHoldGold=ON"
		.. " | titleAligned=SHIFTED_RIGHT_A_LOT"
		.. " | timerAligned=ORIGINAL_X_HIGHER_Y"
		.. " | TechniqueCooldownPopup=OFF"
		.. " | TechniqueCooldownHotbar=ON"
		.. " | CoreMechanicPopup=ON"
		.. " | fixedTextSize=ON"
		.. " | transparentBorderTrim=ON"
		.. " | skinOverscale=1.03x1.05"
		.. " | right stack"
)
