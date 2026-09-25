
--!strict
-- ReplicatedStorage > Shared > SlotSelectorHUD
-- WAYLESS Character Slots / Bingo Book HUD.
--
-- Asset-driven slot selector with:
--  * Desk background + gradient shade
--  * 5-column scrolling card grid
--  * Alive / Afterlife / Empty states
--  * Delete-confirmation modal requiring DELETE
--  * Per-slot ViewportFrame placeholder hook for real character portraits
--
-- Install together with SlotSelectorHUDAssets. All assets may remain at ID 0;
-- the HUD will still render functional fallbacks until Roblox asset IDs exist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CANVAS_W = 1920
local CANVAS_H = 1080

local COLORS = {
	ink = Color3.fromRGB(52, 49, 40),
	muted = Color3.fromRGB(116, 107, 92),
	accent = Color3.fromRGB(133, 59, 52),
	cream = Color3.fromRGB(238, 226, 204),
	desk = Color3.fromRGB(52, 31, 20),
	shadeDark = Color3.fromRGB(18, 14, 11),
	paper = Color3.fromRGB(241, 233, 218),
	line = Color3.fromRGB(206, 191, 164),
}

local STATE_LABELS = {
	alive = "Select",
	afterlife = "Afterlife",
	empty = "Create character",
}

local VILLAGE_ICON_KEYS = {
	leaf = "village_leaf",
	sand = "village_sand",
	mist = "village_mist",
	stone = "village_stone",
	cloud = "village_cloud",
}

local VILLAGE_NAMES = {
	leaf = "Hidden Leaf",
	sand = "Hidden Sand",
	mist = "Hidden Mist",
	stone = "Hidden Stone",
	cloud = "Hidden Cloud",
}

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local assetsModule = Shared and (
	Shared:FindFirstChild("SlotSelectorHUDAssets")
		or Shared:FindFirstChild("SlotSelectorHUDAssets_v1")
)

local Assets = {
	Get = function(_key: string): string
		return ""
	end,
	Has = function(_key: string): boolean
		return false
	end,
}

if assetsModule and assetsModule:IsA("ModuleScript") then
	local ok, result = pcall(require, assetsModule)
	if ok and typeof(result) == "table" then
		Assets = result
	else
		warn("[SlotSelectorHUD] Failed to require assets module", result)
	end
end

local function create(instanceClass: string, props: {[string]: any}?): Instance
	local instance = Instance.new(instanceClass)
	if props then
		for key, value in pairs(props) do
			(instance :: any)[key] = value
		end
	end
	return instance
end

local function imageId(key: string): string
	return Assets.Get(key)
end

local function assetExists(key: string): boolean
	return Assets.Has(key)
end

local function fitCanvas(canvasRoot: Frame, canvas: Frame)
	local scale = create("UIScale", {Parent = canvas})

	local function update()
		local size = canvasRoot.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local factor = math.min(size.X / CANVAS_W, size.Y / CANVAS_H)
		scale.Scale = factor
		canvas.Position = UDim2.fromOffset(
			math.floor((size.X - CANVAS_W * factor) * 0.5 + 0.5),
			math.floor((size.Y - CANVAS_H * factor) * 0.5 + 0.5)
		)
	end

	canvasRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	task.defer(update)
end

local function makeText(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3)
	return create("TextLabel", {
		Name = name,
		Parent = parent,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Text = text,
		TextColor3 = color,
		TextSize = size,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

local function makeImage(parent: Instance, name: string, key: string, x: number, y: number, w: number, h: number, z: number?, fallback: Color3?)
	local image = create("ImageLabel", {
		Name = name,
		Parent = parent,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BorderSizePixel = 0,
		ZIndex = z or 1,
		ScaleType = Enum.ScaleType.Stretch,
	})

	local content = imageId(key)
	if content ~= "" then
		image.Image = content
	else
		image.Image = ""
		image.BackgroundTransparency = fallback and 0 or 1
		image.BackgroundColor3 = fallback or Color3.new(1, 1, 1)
	end

	return image
end

local function makeFallbackCardPaper(parent: Instance, x: number, y: number, w: number, h: number)
	local frame = create("Frame", {
		Parent = parent,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = COLORS.paper,
		BorderSizePixel = 0,
	})
	create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
	local stroke = create("UIStroke", {
		Parent = frame,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(206, 191, 164),
		Thickness = 1,
		Transparency = 0.1,
	})
	return frame, stroke
end

local function makeButtonState(parent: Instance, name: string, x: number, y: number, w: number, h: number, labelText: string?, callbacks: {[string]: (() -> ())?}, assets: {[string]: string?}?, fallbackColor: Color3?)
	local holder = create("Frame", {
		Name = name,
		Parent = parent,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
	})

	local bg = create("ImageLabel", {
		Name = "Bg",
		Parent = holder,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
	})

	local normal = assets and assets.normal or ""
	local hover = assets and assets.hover or normal
	local pressed = assets and assets.pressed or hover
	local disabled = assets and assets.disabled or normal

	if normal ~= "" then
		bg.Image = normal
	else
		bg.BackgroundTransparency = 0
		bg.BackgroundColor3 = fallbackColor or COLORS.paper
		create("UIStroke", {
			Parent = bg,
			Color = Color3.fromRGB(192, 180, 159),
			Thickness = 1,
			Transparency = 0.15,
		})
	end

	local button = create("TextButton", {
		Name = "Button",
		Parent = holder,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
	})

	local textLabel = create("TextLabel", {
		Name = "Label",
		Parent = holder,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = labelText or "",
		TextColor3 = COLORS.ink,
		TextSize = 16,
		Font = Enum.Font.Garamond,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	local enabled = true
	local hovered = false
	local pressedInside = false

	local function refresh()
		if not enabled then
			bg.Image = disabled ~= "" and disabled or normal
			textLabel.TextTransparency = 0.45
			return
		end
		textLabel.TextTransparency = 0
		if pressedInside then
			bg.Image = pressed ~= "" and pressed or hover
		elseif hovered then
			bg.Image = hover ~= "" and hover or normal
		else
			bg.Image = normal
		end
	end

	button.MouseEnter:Connect(function()
		hovered = true
		refresh()
		if callbacks.hover then callbacks.hover() end
	end)

	button.MouseLeave:Connect(function()
		hovered = false
		pressedInside = false
		refresh()
	end)

	button.MouseButton1Down:Connect(function()
		if not enabled then return end
		pressedInside = true
		refresh()
	end)

	button.MouseButton1Up:Connect(function()
		if not enabled then return end
		pressedInside = false
		refresh()
	end)

	button.MouseButton1Click:Connect(function()
		if not enabled then return end
		if callbacks.click then callbacks.click() end
	end)

	refresh()

	return {
		Root = holder,
		Bg = bg,
		Button = button,
		Label = textLabel,
		SetText = function(text: string)
			textLabel.Text = text
		end,
		SetEnabled = function(value: boolean)
			enabled = value
			button.Active = value
			refresh()
		end,
	}
end

local SlotSelectorHUD = {}

function SlotSelectorHUD.Create(parent: Instance, callbacks: {[string]: any}?)
	callbacks = callbacks or {}

	local state = {
		slotViews = {} :: {any},
		selectedSlotId = nil :: string?,
		hoveredSlotId = nil :: string?,
		deleteTarget = nil :: any,
		deletePending = false,
	}

	local root = create("Frame", {
		Name = "SlotSelectorHUDRoot",
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = true,
	})

	local bg = create("ImageLabel", {
		Name = "Desk",
		Parent = root,
		BackgroundColor3 = COLORS.desk,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
	})
	if assetExists("desk") then
		bg.Image = imageId("desk")
	end

	local shade = create("Frame", {
		Name = "Shade",
		Parent = root,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = COLORS.shadeDark,
	})
	create("UIGradient", {
		Parent = shade,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.shadeDark),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(16, 14, 9)),
			ColorSequenceKeypoint.new(1, COLORS.shadeDark),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.39),
			NumberSequenceKeypoint.new(0.3, 0.96),
			NumberSequenceKeypoint.new(1, 0.6),
		}),
	})

	local canvas = create("Frame", {
		Name = "Canvas",
		Parent = root,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CANVAS_W, CANVAS_H),
	})
	fitCanvas(root, canvas)

	local eyebrow = makeText(canvas, "Eyebrow", "WAYLESS / THE BINGO BOOK", 188, 45, 650, 22, 14, Color3.fromRGB(200, 185, 157))
	eyebrow.Font = Enum.Font.Garamond

	local title: Instance
	if assetExists("title") then
		title = makeImage(canvas, "Title", "title", 183, 69, 480, 70, 3, nil)
	else
		title = makeText(canvas, "TitleText", "Character Slots", 183, 66, 580, 76, 34, COLORS.cream)
		local titleText = title :: TextLabel
		titleText.Font = Enum.Font.Garamond
		titleText.TextScaled = false
	end

	local subtitle = makeText(canvas, "Subtitle", "Choose the story you want to continue.", 188, 153, 900, 26, 18, Color3.fromRGB(199, 187, 165))

	local buyButtonControl = makeButtonState(
		canvas,
		"BuySlot",
		1504,
		98,
		228,
		50,
		"+  Buy character slot",
		{
			click = function()
				if callbacks.onBuySlot then callbacks.onBuySlot() end
			end,
		},
		assetExists("buy_slot") and {
			normal = imageId("buy_slot"),
			hover = imageId("buy_slot"),
			pressed = imageId("buy_slot"),
			disabled = imageId("buy_slot"),
		} or nil,
		COLORS.accent
	)
	buyButtonControl.Label.TextColor3 = COLORS.cream
	buyButtonControl.Label.Font = Enum.Font.Garamond
	buyButtonControl.Label.TextSize = 21

	local scrollFrame = create("ScrollingFrame", {
		Name = "GridScroll",
		Parent = canvas,
		Position = UDim2.fromOffset(188, 210),
		Size = UDim2.fromOffset(1544, 727),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(1544, 727),
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ClipsDescendants = true,
	})

	local track = makeImage(canvas, "ScrollTrack", "scroll_track", 1758, 210, 4, 727, 3, Color3.fromRGB(109, 100, 88))
	track.BackgroundTransparency = assetExists("scroll_track") and 1 or 0.4
	local thumb = makeImage(canvas, "ScrollThumb", "scroll_thumb", 1758, 210, 4, 80, 4, COLORS.cream)
	thumb.BackgroundTransparency = assetExists("scroll_thumb") and 1 or 0

	local countLabel = makeText(canvas, "Count", "0 SLOTS", 1550, 986, 182, 24, 14, Color3.fromRGB(200, 185, 157))
	countLabel.TextXAlignment = Enum.TextXAlignment.Right

	local hint = makeText(canvas, "Hint", "Select a record to continue. Empty records open character creation.", 380, 987, 1160, 28, 15, Color3.fromRGB(181, 167, 143))
	hint.TextXAlignment = Enum.TextXAlignment.Center

	local backButton = create("TextButton", {
		Name = "Back",
		Parent = canvas,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(188, 980),
		Size = UDim2.fromOffset(130, 38),
		Text = "‹ Back",
		Font = Enum.Font.Garamond,
		TextSize = 23,
		TextColor3 = COLORS.cream,
		AutoButtonColor = false,
	})
	backButton.TextXAlignment = Enum.TextXAlignment.Left
	backButton.MouseButton1Click:Connect(function()
		if callbacks.onBack then callbacks.onBack() end
	end)

	local modalScrim = makeImage(root, "ModalScrim", "modal_scrim", 0, 0, 1, 1, 20, Color3.fromRGB(0, 0, 0))
	modalScrim.Size = UDim2.fromScale(1, 1)
	modalScrim.Position = UDim2.fromScale(0, 0)
	modalScrim.Visible = false
	modalScrim.BackgroundTransparency = assetExists("modal_scrim") and 1 or 0.35

	-- Full-screen input shield. The visual scrim is only an ImageLabel, so by
	-- itself it does not stop mouse/touch input from reaching slot cards below.
	-- This transparent TextButton sits above the entire selector but below the
	-- delete modal, swallowing clicks while confirmation is open.
	local modalInputBlocker = create("TextButton", {
		Name = "ModalInputBlocker",
		Parent = root,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Active = true,
		Selectable = false,
		Visible = false,
		ZIndex = 22,
	})

	-- Deliberately do nothing when the player clicks outside the modal.
	-- The confirmation must be explicitly Cancelled or completed.
	modalInputBlocker.MouseButton1Click:Connect(function() end)

	local modal = create("Frame", {
		Name = "DeleteModal",
		Parent = canvas,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(640, 330),
		Size = UDim2.fromOffset(640, 418),
		Visible = false,
		ZIndex = 25,
	})
	local modalPanel = makeImage(modal, "Panel", "modal_panel", 0, 0, 640, 418, 25, COLORS.paper)
	modalPanel.BackgroundTransparency = assetExists("modal_panel") and 1 or 0

	local modalTitle = makeText(modal, "Title", "Send character to Afterlife?", 54, 34, 532, 42, 34, COLORS.ink)
	modalTitle.ZIndex = 26
	local modalIdentity = makeText(modal, "Identity", "Name · Slot 01", 54, 85, 532, 32, 22, COLORS.accent)
	modalIdentity.ZIndex = 26
	local modalWarning = makeText(modal, "Warning", "This marks this life as dead and sends it to Afterlife.", 54, 130, 532, 28, 19, COLORS.ink)
	modalWarning.ZIndex = 26
	local modalRetention = makeText(modal, "Retention", "You can choose Revive or Wipe from Afterlife.", 54, 162, 532, 25, 17, COLORS.muted)
	modalRetention.ZIndex = 26
	local modalInstruction = makeText(modal, "Instruction", "Type DELETE to confirm.", 54, 202, 532, 26, 18, COLORS.ink)
	modalInstruction.ZIndex = 26
	local modalError = makeText(modal, "Error", "", 54, 292, 532, 20, 16, Color3.fromRGB(141, 45, 45))
	modalError.ZIndex = 26

	local inputBg = makeImage(modal, "InputBg", "delete_input_normal", 54, 239, 532, 52, 25, COLORS.paper)
	local inputBox = create("TextBox", {
		Name = "Input",
		Parent = modal,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(54, 239),
		Size = UDim2.fromOffset(532, 52),
		PlaceholderText = "Enter DELETE",
		PlaceholderColor3 = COLORS.muted,
		Text = "",
		ClearTextOnFocus = false,
		Font = Enum.Font.Garamond,
		TextColor3 = COLORS.ink,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})
	create("UIPadding", {
		Parent = inputBox,
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
	})

	local modalCancel = makeButtonState(
		modal,
		"Cancel",
		54,
		339,
		205,
		43,
		"Cancel",
		{
			click = function()
				state.deleteTarget = nil
				modal.Visible = false
				modalScrim.Visible = false
				modalInputBlocker.Visible = false
				scrollFrame.ScrollingEnabled = true
				inputBox.Text = ""
				modalError.Text = ""
				if callbacks.onDeleteCancelled then callbacks.onDeleteCancelled() end
			end,
		},
		{
			normal = imageId("action_normal"),
			hover = imageId("action_hover"),
			pressed = imageId("action_pressed"),
			disabled = imageId("action_disabled"),
		},
		COLORS.paper
	)
	modalCancel.Root.ZIndex = 26
	modalCancel.Bg.ZIndex = 26
	modalCancel.Button.ZIndex = 28
	modalCancel.Label.ZIndex = 27
	modalCancel.Label.Font = Enum.Font.Garamond
	modalCancel.Label.TextSize = 18

	local modalConfirm = makeButtonState(
		modal,
		"Confirm",
		309,
		339,
		277,
		43,
		"Send to Afterlife",
		{ click = function() end },
		{
			normal = imageId("action_disabled"),
			hover = imageId("action_hover"),
			pressed = imageId("action_pressed"),
			disabled = imageId("action_disabled"),
		},
		COLORS.accent
	)
	modalConfirm.Root.ZIndex = 26
	modalConfirm.Bg.ZIndex = 26
	modalConfirm.Button.ZIndex = 28
	modalConfirm.Label.ZIndex = 27
	modalConfirm.Label.Font = Enum.Font.Garamond
	modalConfirm.Label.TextSize = 18
	modalConfirm.Label.TextColor3 = COLORS.cream

	local function updateThumb()
		local visibleHeight = scrollFrame.AbsoluteWindowSize.Y
		local canvasHeight = math.max(scrollFrame.AbsoluteCanvasSize.Y, visibleHeight)
		local needsScroll = canvasHeight > visibleHeight + 1
		track.Visible = needsScroll
		thumb.Visible = needsScroll
		if not needsScroll then
			return
		end
		local ratio = math.clamp(visibleHeight / canvasHeight, 0.08, 1)
		local thumbHeight = math.max(60, math.floor(727 * ratio + 0.5))
		local maxScroll = math.max(1, canvasHeight - visibleHeight)
		local maxTravel = 727 - thumbHeight
		local t = math.clamp(scrollFrame.CanvasPosition.Y / maxScroll, 0, 1)
		thumb.Position = UDim2.fromOffset(1758, 210 + math.floor(maxTravel * t + 0.5))
		thumb.Size = UDim2.fromOffset(4, thumbHeight)
	end

	scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(updateThumb)
	scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateThumb)
	scrollFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(updateThumb)

	local function setInputState(mode: string)
		local key = "delete_input_normal"
		if mode == "focus" then
			key = "delete_input_focus"
		elseif mode == "error" then
			key = "delete_input_error"
		end
		local img = imageId(key)
		inputBg.Image = img
		if img == "" then
			inputBg.BackgroundTransparency = 0
			inputBg.BackgroundColor3 = (mode == "error") and Color3.fromRGB(255, 229, 229) or COLORS.paper
		else
			inputBg.BackgroundTransparency = 1
		end
	end

	local function refreshConfirmButton()
		local enabled = (inputBox.Text == "DELETE") and (not state.deletePending)
		modalConfirm.SetEnabled(enabled)
	end

	inputBox.Focused:Connect(function()
		setInputState("focus")
	end)
	inputBox.FocusLost:Connect(function(_enterPressed)
		if inputBox.Text ~= "DELETE" then
			setInputState("normal")
		end
		refreshConfirmButton()
	end)
	inputBox:GetPropertyChangedSignal("Text"):Connect(function()
		modalError.Text = ""
		if inputBox.Text == "" then
			setInputState("normal")
		elseif inputBox.Text == "DELETE" then
			setInputState("focus")
		else
			setInputState("error")
		end
		refreshConfirmButton()
	end)

	modalConfirm.Button.MouseButton1Click:Connect(function()
		if inputBox.Text ~= "DELETE" or state.deletePending or state.deleteTarget == nil then
			return
		end
		state.deletePending = true
		refreshConfirmButton()
		local ok = true
		local message = nil
		if callbacks.onDeleteConfirmed then
			local resultA, resultB = callbacks.onDeleteConfirmed(state.deleteTarget)
			if resultA == false then
				ok = false
				message = resultB
			end
		end
		state.deletePending = false
		if ok then
			state.deleteTarget = nil
			modal.Visible = false
			modalScrim.Visible = false
			modalInputBlocker.Visible = false
			scrollFrame.ScrollingEnabled = true
			inputBox.Text = ""
			modalError.Text = ""
			setInputState("normal")
			refreshConfirmButton()
		else
			modalError.Text = tostring(message or "Could not delete this character.")
			setInputState("error")
			refreshConfirmButton()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not modal.Visible then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			modalCancel.Button:Activate()
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			if inputBox.Text == "DELETE" and not state.deletePending then
				modalConfirm.Button:Activate()
			end
		end
	end)

	local cardRoots = {} :: {[string]: Frame}

	local function clearCards()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			child:Destroy()
		end
		table.clear(cardRoots)
	end

	local function showDeleteModal(slotView: any)
		state.deleteTarget = slotView
		state.deletePending = false
		modalIdentity.Text = string.format("%s · Slot %02d", tostring(slotView.displayName or "Unknown"), tonumber(slotView.slotIndex) or 0)
		modalError.Text = ""
		inputBox.Text = ""
		setInputState("normal")
		refreshConfirmButton()
		modal.Visible = true
		modalScrim.Visible = true
		modalInputBlocker.Visible = true
		scrollFrame.ScrollingEnabled = false
		task.defer(function()
			inputBox:CaptureFocus()
		end)
	end

	local function refreshSelectionVisuals()
		for slotId, card in pairs(cardRoots) do
			local selectedOverlay = card:FindFirstChild("SelectedOverlay")
			local hoverOverlay = card:FindFirstChild("HoverOverlay")
			local selectedDot = card:FindFirstChild("SelectedDot")
			if selectedOverlay and selectedOverlay:IsA("GuiObject") then
				selectedOverlay.Visible = state.selectedSlotId ~= nil and slotId == state.selectedSlotId
			end
			if hoverOverlay and hoverOverlay:IsA("GuiObject") then
				hoverOverlay.Visible = state.hoveredSlotId ~= nil and slotId == state.hoveredSlotId and state.selectedSlotId ~= slotId
			end
			if selectedDot and selectedDot:IsA("GuiObject") then
				selectedDot.Visible = state.selectedSlotId ~= nil and slotId == state.selectedSlotId
			end
		end
	end

	local function buildCard(slotView: any, layoutIndex: number)
		local x = ((layoutIndex - 1) % 5) * 314
		local y = math.floor((layoutIndex - 1) / 5) * 377
		local rootButton = create("TextButton", {
			Name = tostring(slotView.slotId),
			Parent = scrollFrame,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(288, 350),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
		})
		rootButton.LayoutOrder = layoutIndex

		local cardVisual: GuiObject
		if assetExists("card_base") then
			cardVisual = makeImage(rootButton, "Base", "card_base", 0, 0, 288, 350, 1, nil)
		else
			cardVisual = makeFallbackCardPaper(rootButton, 0, 0, 288, 350)
		end

		local selectedOverlay = makeImage(rootButton, "SelectedOverlay", "card_selected", 0, 0, 288, 350, 8, nil)
		selectedOverlay.Visible = false
		if not assetExists("card_selected") then
			selectedOverlay.BackgroundTransparency = 1
			create("UIStroke", {
				Parent = selectedOverlay,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = COLORS.accent,
				Thickness = 2,
				Transparency = 0.05,
			})
		end

		local hoverOverlay = makeImage(rootButton, "HoverOverlay", "card_hover", 0, 0, 288, 350, 7, nil)
		hoverOverlay.Visible = false
		if not assetExists("card_hover") then
			hoverOverlay.BackgroundTransparency = 1
			create("UIStroke", {
				Parent = hoverOverlay,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(178, 153, 120),
				Thickness = 1,
				Transparency = 0.35,
			})
		end

		local number = makeText(rootButton, "Number", string.format("SLOT %02d", tonumber(slotView.slotIndex) or layoutIndex), 18, 10, 210, 20, 12, COLORS.muted)
		number.Font = Enum.Font.Garamond
		number.ZIndex = 2

		local portraitBg = makeImage(rootButton, "PortraitBg", "portrait_backdrop", 18, 38, 252, 178, 1, Color3.fromRGB(211, 206, 197))
		portraitBg.BackgroundTransparency = assetExists("portrait_backdrop") and 1 or 0

		if slotView.state == "empty" then
			local emptyPortrait = makeImage(rootButton, "EmptyPortrait", "empty_portrait", 18, 38, 252, 178, 2, Color3.fromRGB(239, 234, 223))
			emptyPortrait.BackgroundTransparency = assetExists("empty_portrait") and 1 or 0
			if not assetExists("empty_portrait") then
				local plus = makeText(rootButton, "Plus", "+", 18, 92, 252, 70, 42, COLORS.ink)
				plus.ZIndex = 3
				plus.TextXAlignment = Enum.TextXAlignment.Center
			end
		else
			local viewport = create("ViewportFrame", {
				Name = "PortraitViewport",
				Parent = rootButton,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(18, 38),
				Size = UDim2.fromOffset(252, 178),
				BorderSizePixel = 0,
				ZIndex = 2,
				Ambient = Color3.fromRGB(200, 200, 200),
				LightColor = Color3.fromRGB(255, 255, 255),
				LightDirection = Vector3.new(-1, -1, -1),
			})
			local loadingText = makeText(rootButton, "PortraitLoading", "Loading...", 18, 106, 252, 34, 15, COLORS.muted)
			loadingText.ZIndex = 3
			loadingText.TextXAlignment = Enum.TextXAlignment.Center

			if callbacks.onRenderPortrait then
				task.defer(function()
					callbacks.onRenderPortrait(viewport, slotView)
				end)
			else
				loadingText.Text = "Portrait"
			end
		end

		local portraitFrame = makeImage(rootButton, "PortraitFrame", "portrait_frame", 16, 36, 256, 182, 4, nil)
		if not assetExists("portrait_frame") then
			portraitFrame.BackgroundTransparency = 1
			create("UIStroke", {
				Parent = portraitFrame,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(209, 196, 175),
				Thickness = 1,
				Transparency = 0.15,
			})
		end

		if slotView.state == "afterlife" then
			-- Monochrome/dead-state wash. This sits over only the portrait and
			-- below the portrait frame / X / AFTERLIFE stamp, so the card art
			-- and state markers keep their original colors.
			local monochromeFilter = create("Frame", {
				Name = "AfterlifeMonochromeFilter",
				Parent = rootButton,
				BackgroundColor3 = Color3.fromRGB(148, 148, 148),
				BackgroundTransparency = 0.32,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(18, 38),
				Size = UDim2.fromOffset(252, 178),
				ZIndex = 3,
				Active = false,
			})

			local cross = makeImage(rootButton, "AfterlifeCross", "afterlife_cross", 18, 38, 252, 178, 5, nil)
			if not assetExists("afterlife_cross") then
				cross.BackgroundTransparency = 1
				local diagA = create("Frame", {Parent = cross, BackgroundColor3 = COLORS.ink, BorderSizePixel = 0, Size = UDim2.fromOffset(310, 8), Position = UDim2.fromOffset(-25, 84), Rotation = 36})
				local diagB = create("Frame", {Parent = cross, BackgroundColor3 = COLORS.ink, BorderSizePixel = 0, Size = UDim2.fromOffset(310, 8), Position = UDim2.fromOffset(-25, 84), Rotation = -36})
				diagA.ZIndex = 5
				diagB.ZIndex = 5
			end
			local stamp = makeImage(rootButton, "AfterlifeStamp", "afterlife_stamp", 132, 186, 126, 28, 6, nil)
			stamp.Rotation = -3.44
			if not assetExists("afterlife_stamp") then
				stamp.BackgroundTransparency = 1
				local stampText = makeText(stamp, "StampText", "AFTERLIFE", 0, 0, 126, 28, 17, COLORS.accent)
				stampText.Font = Enum.Font.Garamond
				stampText.TextXAlignment = Enum.TextXAlignment.Center
			end
		end

		if slotView.state == "empty" then
			local emptyTitle = makeText(rootButton, "EmptyTitle", "Empty slot", 18, 219, 252, 30, 23, COLORS.ink)
			emptyTitle.ZIndex = 3
			emptyTitle.TextXAlignment = Enum.TextXAlignment.Center
			local emptySubtitle = makeText(rootButton, "EmptySubtitle", "Begin a new story", 18, 255, 252, 24, 15, COLORS.muted)
			emptySubtitle.ZIndex = 3
			emptySubtitle.TextXAlignment = Enum.TextXAlignment.Center
		else
			local displayName = tostring(slotView.displayName or "Unnamed")
			local nameLabel = makeText(rootButton, "Name", displayName, 18, 222, 252, 32, 23, COLORS.ink)
			nameLabel.ZIndex = 3
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

			local villageIconKey = VILLAGE_ICON_KEYS[tostring(slotView.villageId)]
			local villageIcon = makeImage(rootButton, "VillageIcon", villageIconKey or "", 18, 257, 24, 24, 3, nil)
			if villageIconKey == nil or villageIcon.Image == "" then
				villageIcon.BackgroundTransparency = 1
				local mark = makeText(villageIcon, "Dot", "✦", 0, -2, 24, 24, 14, COLORS.muted)
				mark.TextXAlignment = Enum.TextXAlignment.Center
			end
			local villageText = makeText(rootButton, "VillageName", tostring(slotView.villageName or VILLAGE_NAMES.leaf), 48, 258, 146, 24, 16, COLORS.ink)
			villageText.ZIndex = 3
			villageText.TextTruncate = Enum.TextTruncate.AtEnd

			local levelText = makeText(rootButton, "Level", "LV. " .. tostring(slotView.level or 1), 198, 258, 69, 24, 16, COLORS.ink)
			levelText.ZIndex = 3
			levelText.TextXAlignment = Enum.TextXAlignment.Right
		end

		local separator = makeImage(rootButton, "Separator", "separator", 18, 288, 252, 4, 3, Color3.fromRGB(210, 198, 175))
		separator.BackgroundTransparency = assetExists("separator") and 1 or 0.15

		local primaryX = 18
		local primaryW = 158
		if slotView.state == "empty" then
			primaryX = 65
		elseif slotView.state == "afterlife" then
			primaryX = 18
			primaryW = 252
		end

		local primary = makeButtonState(
			rootButton,
			"PrimaryAction",
			primaryX,
			301,
			primaryW,
			34,
			STATE_LABELS[slotView.state] or "Select",
			{
				click = function()
					state.selectedSlotId = tostring(slotView.slotId)
					refreshSelectionVisuals()
					if callbacks.onPrimaryAction then callbacks.onPrimaryAction(slotView) end
				end,
			},
			{
				normal = imageId("action_normal"),
				hover = imageId("action_hover"),
				pressed = imageId("action_pressed"),
				disabled = imageId("action_disabled"),
			},
			slotView.state == "afterlife" and Color3.fromRGB(231, 222, 207) or COLORS.paper
		)
		primary.Label.Font = Enum.Font.Garamond
		primary.Label.TextSize = 16

		if slotView.state == "alive" then
			local deleteHolder = create("Frame", {
				Name = "DeleteAction",
				Parent = rootButton,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(194, 301),
				Size = UDim2.fromOffset(74, 34),
			})
			local deleteBg = makeImage(deleteHolder, "Bg", "delete_action", 0, 0, 74, 34, 3, COLORS.paper)
			if not assetExists("delete_action") then
				deleteBg.BackgroundTransparency = 0
				create("UIStroke", {Parent = deleteBg, Color = Color3.fromRGB(192,180,159), Thickness = 1, Transparency = 0.1})
			end
			local deleteButton = create("TextButton", {
				Parent = deleteHolder,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Text = "",
				AutoButtonColor = false,
				ZIndex = 4,
			})
			-- delete_action is a complete baked button asset (trash icon + DELETE label).
			-- Only build icon/text fallbacks when that complete asset is missing.
			if not assetExists("delete_action") then
				local trashIcon = makeImage(deleteHolder, "Trash", "trash", 10, 9, 14, 16, 4, nil)
				if trashIcon.Image == "" then
					trashIcon.BackgroundTransparency = 1
					local t = makeText(trashIcon, "T", "🗑", -2, -4, 20, 20, 10, COLORS.ink)
					t.TextXAlignment = Enum.TextXAlignment.Center
				end
				local deleteText = makeText(deleteHolder, "DeleteText", "Delete", 26, 0, 40, 34, 16, COLORS.accent)
				deleteText.ZIndex = 4
			end
			deleteButton.MouseButton1Click:Connect(function()
				state.selectedSlotId = tostring(slotView.slotId)
				refreshSelectionVisuals()
				showDeleteModal(slotView)
			end)
		end

		local selectedDot = create("Frame", {
			Name = "SelectedDot",
			Parent = rootButton,
			BackgroundColor3 = COLORS.accent,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(265, 17),
			Size = UDim2.fromOffset(6, 6),
			Visible = false,
			ZIndex = 9,
		})
		create("UICorner", {Parent = selectedDot, CornerRadius = UDim.new(1, 0)})

		rootButton.MouseEnter:Connect(function()
			state.hoveredSlotId = tostring(slotView.slotId)
			refreshSelectionVisuals()
		end)
		rootButton.MouseLeave:Connect(function()
			if state.hoveredSlotId == tostring(slotView.slotId) then
				state.hoveredSlotId = nil
				refreshSelectionVisuals()
			end
		end)
		rootButton.MouseButton1Click:Connect(function()
			state.selectedSlotId = tostring(slotView.slotId)
			refreshSelectionVisuals()
			if callbacks.onPrimaryAction then callbacks.onPrimaryAction(slotView) end
		end)

		cardRoots[tostring(slotView.slotId)] = rootButton
		refreshSelectionVisuals()
	end

	local api = {}

	function api.SetVisible(visible: boolean)
		root.Visible = visible
	end

	function api.SetSelectedSlot(slotId: string?)
		state.selectedSlotId = slotId and tostring(slotId) or nil
		refreshSelectionVisuals()
	end

	function api.SetSlots(slots: {any})
		state.slotViews = slots
		countLabel.Text = tostring(#slots) .. " SLOTS"
		clearCards()
		for index, slotView in ipairs(slots) do
			buildCard(slotView, index)
		end
		local rows = math.max(1, math.ceil(#slots / 5))
		local contentHeight = math.max(727, rows * 377 - 27)
		scrollFrame.CanvasSize = UDim2.fromOffset(1544, contentHeight)
		updateThumb()
		refreshSelectionVisuals()
	end

	function api.OpenDeleteModal(slotView: any)
		showDeleteModal(slotView)
	end

	function api.Destroy()
		root:Destroy()
	end

	return api
end

return SlotSelectorHUD
