--!strict
-- StarterPlayer > StarterPlayerScripts > AfterlifeController
--
-- WAYLESS Afterlife UI v1.
-- This Place intentionally has no normal combat/HUD scripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
task.spawn(function()
	require(script.Parent:WaitForChild("AfterlifeEffects")).Start()
end)

local system =
	ReplicatedStorage:
	WaitForChild("AfterlifeSystem", 20)

if not system then
	warn("[AfterlifeController] AfterlifeSystem missing")
	return
end

local remotes =
	system:WaitForChild("Remotes", 20)

if not remotes then
	warn("[AfterlifeController] Remotes missing")
	return
end

local requestObject =
	remotes:WaitForChild("AfterlifeRequest", 20)

if not requestObject
	or not requestObject:IsA("RemoteFunction") then

	warn("[AfterlifeController] AfterlifeRequest missing")
	return
end

local request = requestObject :: RemoteFunction

local gui = Instance.new("ScreenGui")
gui.Name = "AfterlifeUI"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = player:WaitForChild("PlayerGui")

local wash = Instance.new("Frame")
wash.Size = UDim2.fromScale(1, 1)
wash.BackgroundColor3 = Color3.fromRGB(3, 4, 7)
wash.BackgroundTransparency = 0.38
wash.BorderSizePixel = 0
wash.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.54)
panel.Size = UDim2.fromOffset(430, 360)
panel.BackgroundColor3 = Color3.fromRGB(11, 12, 17)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.45
stroke.Color = Color3.fromRGB(120, 130, 155)
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(20, 18)
title.Size = UDim2.new(1, -90, 0, 32)
title.Text = "THE AFTERLIFE"
title.TextColor3 = Color3.fromRGB(230, 233, 241)
title.TextSize = 23
title.Font = Enum.Font.GothamBold
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(24, 54)
subtitle.Size = UDim2.new(1, -48, 0, 38)
subtitle.Text =
	"Your life has ended. Decide what happens to this character."
subtitle.TextColor3 = Color3.fromRGB(160, 168, 185)
subtitle.TextSize = 12
subtitle.TextWrapped = true
subtitle.Font = Enum.Font.Gotham
subtitle.Parent = panel

local identity = Instance.new("TextLabel")
identity.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
identity.BorderSizePixel = 0
identity.Position = UDim2.fromOffset(24, 101)
identity.Size = UDim2.new(1, -48, 0, 54)
identity.Text = "Validating character..."
identity.TextColor3 = Color3.fromRGB(190, 197, 212)
identity.TextSize = 11
identity.TextWrapped = true
identity.Font = Enum.Font.Gotham
identity.Parent = panel

local identityCorner = Instance.new("UICorner")
identityCorner.CornerRadius = UDim.new(0, 5)
identityCorner.Parent = identity

local tokenLabel = Instance.new("TextLabel")
tokenLabel.BackgroundTransparency = 1
tokenLabel.Position = UDim2.fromOffset(24, 163)
tokenLabel.Size = UDim2.new(1, -48, 0, 22)
tokenLabel.Text = "Revival Tokens: ?"
tokenLabel.TextColor3 = Color3.fromRGB(195, 202, 217)
tokenLabel.TextSize = 12
tokenLabel.TextXAlignment = Enum.TextXAlignment.Left
tokenLabel.Font = Enum.Font.GothamSemibold
tokenLabel.Parent = panel

local function makeButton(
	text: string,
	x: number,
	y: number,
	w: number,
	h: number
): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(w, h)
	button.Position = UDim2.fromOffset(x, y)
	button.BackgroundColor3 = Color3.fromRGB(31, 35, 45)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 237, 242)
	button.TextSize = 12
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button

	return button
end

local reviveToken =
	makeButton(
		"REVIVE - TOKEN",
		24,
		195,
		180,
		38
	)

local reviveDev =
	makeButton(
		"REVIVE - DEV QA",
		226,
		195,
		180,
		38
	)

local wipe =
	makeButton(
		"WIPE CHARACTER",
		24,
		243,
		180,
		38
	)

local leave =
	makeButton(
		"LEAVE",
		226,
		243,
		180,
		38
	)

local confirm =
	makeButton(
		"CONFIRM WIPE",
		24,
		291,
		180,
		34
	)

local cancel =
	makeButton(
		"CANCEL",
		226,
		291,
		180,
		34
	)

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(24, 329)
status.Size = UDim2.new(1, -48, 0, 24)
status.Text = "Connecting..."
status.TextColor3 = Color3.fromRGB(170, 178, 195)
status.TextSize = 10
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.Parent = panel

local closeButton = makeButton("X", 380, 14, 32, 32)
closeButton.Name = "Close"
for _,button in ipairs({reviveToken,reviveDev,wipe,leave,confirm,cancel}) do
	button.Active=false
end
confirm.Visible=false
cancel.Visible=false
local currentState: any = nil
local cancelOnComplete = false
local busy = false

local function shortId(value: any): string
	local text = tostring(value or "-")
	if #text <= 22 then
		return text
	end

	return string.sub(text, 1, 9)
		.. "..."
		.. string.sub(text, -8)
end

local function setButton(
	button: TextButton,
	enabled: boolean,
	visible: boolean?
)
	button.Visible =
		visible == nil
		and true
		or visible

	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency =
		enabled and 0 or 0.48
	button.BackgroundTransparency =
		enabled and 0 or 0.35
end

local function render(response: any)
	if typeof(response) ~= "table" then
		status.Text = "Invalid Afterlife response."
		return
	end

	currentState = response

	identity.Text =
		"Slot "
		.. tostring(response.SlotId or "?")
		.. "  |  "
		.. tostring(response.SlotState or "Validating")
		.. "\nLife "
		.. shortId(response.LifeId)
		.. "  |  Character "
		.. shortId(response.CharacterId)

	tokenLabel.Text =
		"Revival Tokens: "
		.. tostring(
			response.RevivalTokens or 0
		)

	local ready =
		response.Ready == true
		and response.SlotState
		== "DeadAwaitingDecision"
		and not busy

	setButton(
		reviveToken,
		ready
			and (tonumber(response.RevivalTokens) or 0) > 0
	)

	setButton(
		reviveDev,
		ready
			and response.CanDeveloperRevive == true,
		response.CanDeveloperRevive == true
	)

	setButton(
		wipe,
		ready
			and response.WipeArmed ~= true
	)

	setButton(
		leave,
		ready
	)

	setButton(
		confirm,
		ready
			and response.WipeArmed == true,
		response.WipeArmed == true
	)

	setButton(
		cancel,
		ready
			and response.WipeArmed == true,
		response.WipeArmed == true
	)

	if response.WipeArmed == true then
		status.Text =
			"WIPE ARMED � "
			.. tostring(
				response.WipeSecondsRemaining or 0
			)
			.. "s remaining. This archives the current life and empties the slot."
	else
		status.Text =
			tostring(
				response.Reason or "Ready"
			)
	end
end

local function invoke(action: string)
	if busy then return end
	busy=true
	if currentState then render(currentState) end
	status.Text=action .. "..."
	local ok, response=pcall(function() return request:InvokeServer(action) end)
	if cancelOnComplete then
		cancelOnComplete=false
		local cancelled, state=pcall(function() return request:InvokeServer("CancelWipe") end)
		if cancelled then ok=true; response=state end
	end
	busy=false
	if ok then render(response) else
		if currentState then render(currentState) end
		status.Text="Request failed: " .. action
	end
end

local function closeMenu()
	gui.Enabled = false
	confirm.Visible = false
	cancel.Visible = false
	if busy then cancelOnComplete = true else task.spawn(invoke, "CancelWipe") end
end
closeButton.Activated:Connect(closeMenu)
player.CharacterRemoving:Connect(closeMenu)
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who and who ~= player then return end
	local room = workspace:FindFirstChild("WAYLESS_Afterlife")
	if prompt.Name ~= "AfterlifePrompt" or not room or not prompt:IsDescendantOf(room) then return end
	if gui.Enabled or busy then return end
	gui.Enabled = true
	invoke("GetState")
end)
RunService.Heartbeat:Connect(function()
	if not gui.Enabled then return end
	local room = workspace:FindFirstChild("WAYLESS_Afterlife")
	local marker = room and room:FindFirstChild("HagoromoAnchor")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not marker or not marker:IsA("BasePart") or not root or not root:IsA("BasePart")
		or (root.Position - marker.Position).Magnitude > 16 then closeMenu() end
end)

reviveToken.MouseButton1Click:Connect(function()
	invoke("ReviveWithToken")
end)

reviveDev.MouseButton1Click:Connect(function()
	invoke("ReviveDeveloper")
end)

wipe.MouseButton1Click:Connect(function()
	invoke("ArmWipe")
end)

confirm.MouseButton1Click:Connect(function()
	invoke("ConfirmWipe")
end)

cancel.MouseButton1Click:Connect(function()
	invoke("CancelWipe")
end)

leave.MouseButton1Click:Connect(function()
	invoke("Leave")
end)

task.spawn(function()
	for _ = 1, 40 do
		local ok, response =
			pcall(function()
				return request:InvokeServer(
					"GetState"
				)
			end)

		if ok
			and typeof(response) == "table"
			and response.Ready == true then

			render(response)
			return
		end

		if ok
			and typeof(response) == "table" then
			render(response)
		end

		task.wait(0.5)
	end

	status.Text =
		"Afterlife validation timed out. Re-enter through a valid death handoff."
end)

print(
	"[AfterlifeController] READY v1"
		.. " | RevivalToken=ON"
		.. " | WipeDoubleConfirm=ON"
		.. " | Leave=ON"
)
