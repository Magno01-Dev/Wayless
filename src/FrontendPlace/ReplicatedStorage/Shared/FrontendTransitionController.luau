--!strict
-- ReplicatedStorage > Shared > FrontendTransitionController
-- WAYLESS frontend screen transitions v1.1
--
-- Purpose:
--   Give full-screen frontend pages a short, restrained shinobi/ink transition
--   instead of hard-cutting one UI on top of another.
--
-- Visual language:
--   * charcoal ink fade
--   * subtle warm/red brush accent (uses MainMenuHUDAssets.brush_red when available)
--   * short background blur during the covered phase
--   * input blocker while transitioning
--
-- No page-specific knowledge lives here. The caller provides the swap callback.

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontendTransitionController = {}

local COVER_TIME = 0.17
local REVEAL_TIME = 0.24
local COVER_HOLD = 0.035
local MAX_BLUR = 11

local function tween(instance: Instance, info: TweenInfo, props: {[string]: any})
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

local function waitTween(t: Tween)
	-- A tween can already be finished by the time we start waiting for it.
	-- This matters when several tweens start together but have different
	-- durations. Waiting only for a future Completed signal in that case
	-- would deadlock the transition layer forever.
	local state = t.PlaybackState
	if state == Enum.PlaybackState.Completed or state == Enum.PlaybackState.Cancelled then
		return
	end

	local done = false
	local connection = t.Completed:Connect(function()
		done = true
	end)

	-- Close the small race between the PlaybackState check and connection.
	state = t.PlaybackState
	if state == Enum.PlaybackState.Completed or state == Enum.PlaybackState.Cancelled then
		done = true
	end

	-- Fail-safe: no cosmetic transition should ever be able to lock the UI.
	local deadline = os.clock() + 1.25
	while not done and os.clock() < deadline do
		task.wait()
	end

	connection:Disconnect()
end

local function resolveBrushImage(): string
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then
		return ""
	end

	local module = shared:FindFirstChild("MainMenuHUDAssets")
	if not module or not module:IsA("ModuleScript") then
		return ""
	end

	local ok, assets = pcall(require, module)
	if not ok or typeof(assets) ~= "table" or typeof(assets.Get) ~= "function" then
		return ""
	end

	local okGet, image = pcall(assets.Get, "brush_red")
	if okGet and typeof(image) == "string" then
		return image
	end

	return ""
end

function FrontendTransitionController.Create(parent: Instance)
	local root = Instance.new("Frame")
	root.Name = "FrontendTransitionLayer"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = 900
	root.Parent = parent

	local blocker = Instance.new("TextButton")
	blocker.Name = "InputBlocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.Active = true
	blocker.Modal = true
	blocker.ZIndex = 901
	blocker.Parent = root

	local ink = Instance.new("Frame")
	ink.Name = "Ink"
	ink.Size = UDim2.fromScale(1, 1)
	ink.BackgroundColor3 = Color3.fromRGB(10, 8, 7)
	ink.BackgroundTransparency = 1
	ink.BorderSizePixel = 0
	ink.ZIndex = 902
	ink.Parent = root

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 0
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 6, 5)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(18, 13, 11)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 6, 5)),
	})
	gradient.Parent = ink

	local brushImage = resolveBrushImage()
	local brush = Instance.new("ImageLabel")
	brush.Name = "BrushAccent"
	brush.AnchorPoint = Vector2.new(0.5, 0.5)
	brush.Size = UDim2.new(0.54, 0, 0, 54)
	brush.BackgroundTransparency = 1
	brush.Image = brushImage
	brush.ImageTransparency = 1
	brush.ScaleType = Enum.ScaleType.Stretch
	brush.ZIndex = 903
	brush.Parent = root

	local fallbackAccent = Instance.new("Frame")
	fallbackAccent.Name = "FallbackAccent"
	fallbackAccent.AnchorPoint = Vector2.new(0.5, 0.5)
	fallbackAccent.Size = UDim2.new(0.46, 0, 0, 2)
	fallbackAccent.BackgroundColor3 = Color3.fromRGB(122, 50, 43)
	fallbackAccent.BackgroundTransparency = 1
	fallbackAccent.BorderSizePixel = 0
	fallbackAccent.ZIndex = 903
	fallbackAccent.Visible = brushImage == ""
	fallbackAccent.Parent = root

	local blur = Lighting:FindFirstChild("WAYLESSFrontendTransitionBlur")
	if blur and not blur:IsA("BlurEffect") then
		blur:Destroy()
		blur = nil
	end
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "WAYLESSFrontendTransitionBlur"
		blur.Size = 0
		blur.Enabled = false
		blur.Parent = Lighting
	end
	local blurEffect = blur :: BlurEffect

	local busy = false
	local destroyed = false

	local api = {}

	local function resetVisuals()
		ink.BackgroundTransparency = 1
		brush.ImageTransparency = 1
		fallbackAccent.BackgroundTransparency = 1
		blurEffect.Size = 0
		blurEffect.Enabled = false
		root.Visible = false
	end

	local function animateCover(direction: string)
		root.Visible = true
		blurEffect.Enabled = true

		local forward = direction ~= "Back"
		local startX = forward and -0.20 or 1.20
		local endX = 0.50
		brush.Position = UDim2.fromScale(startX, 0.52)
		fallbackAccent.Position = UDim2.fromScale(startX, 0.52)

		local inkTween = tween(
			ink,
			TweenInfo.new(COVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0.045}
		)
		tween(
			blurEffect,
			TweenInfo.new(COVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = MAX_BLUR}
		)
		local brushTween = tween(
			brush,
			TweenInfo.new(COVER_TIME * 0.92, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(endX, 0.52),
				ImageTransparency = brushImage ~= "" and 0.38 or 1,
			}
		)
		tween(
			fallbackAccent,
			TweenInfo.new(COVER_TIME * 0.92, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(endX, 0.52),
				BackgroundTransparency = brushImage == "" and 0.38 or 1,
			}
		)

		-- Ink is deliberately the longest cover tween. Waiting for it is
		-- sufficient; the brush tween is slightly shorter and may already have
		-- completed by this point.
		waitTween(inkTween)
	end

	local function animateReveal(direction: string)
		local forward = direction ~= "Back"
		local endX = forward and 1.20 or -0.20

		local inkTween = tween(
			ink,
			TweenInfo.new(REVEAL_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{BackgroundTransparency = 1}
		)
		tween(
			blurEffect,
			TweenInfo.new(REVEAL_TIME * 0.88, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Size = 0}
		)
		tween(
			brush,
			TweenInfo.new(REVEAL_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{
				Position = UDim2.fromScale(endX, 0.52),
				ImageTransparency = 1,
			}
		)
		tween(
			fallbackAccent,
			TweenInfo.new(REVEAL_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{
				Position = UDim2.fromScale(endX, 0.52),
				BackgroundTransparency = 1,
			}
		)

		waitTween(inkTween)
		resetVisuals()
	end

	function api.Run(swapCallback: () -> (), options: {[string]: any}?): boolean
		if destroyed then
			swapCallback()
			return false
		end

		while busy do
			task.wait()
		end
		busy = true

		local opts = options or {}
		local direction = tostring(opts.Direction or "Forward")

		local ok, err = pcall(function()
			animateCover(direction)
			if COVER_HOLD > 0 then
				task.wait(COVER_HOLD)
			end
			swapCallback()
			animateReveal(direction)
		end)

		if not ok then
			warn("[FrontendTransitionController] transition failed", err)
			resetVisuals()
		end

		busy = false
		return ok
	end

	function api.IsBusy(): boolean
		return busy
	end

	function api.Destroy()
		destroyed = true
		resetVisuals()
		root:Destroy()
	end

	return api
end

return FrontendTransitionController
