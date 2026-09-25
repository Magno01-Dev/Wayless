--!strict
-- StarterPlayer > StarterPlayerScripts > AccountProfileDevPanel
--
-- WAYLESS Account / Character Slot + Lifecycle QA panel v5.
-- Pairs with the SINGLE canonical AccountProfileDevTools v4 gateway.
--
-- This DOES NOT create a second developer menu.
-- It injects one ACCOUNT / SLOTS button + panel into the existing
-- PlayerGui.WAYLESSDevMenu ScreenGui, so its visibility follows the F7 menu.

print("[AccountProfileDevPanel] BOOT v5")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local commonRemotes = ReplicatedStorage:WaitForChild("CommonRemotes", 10)
if not commonRemotes then
	warn("[AccountProfileDevPanel] CommonRemotes missing after 10s")
	return
end

local requestObject = commonRemotes:WaitForChild("AccountProfileDevRequest", 10)
if not requestObject or not requestObject:IsA("RemoteFunction") then
	warn(
		"[AccountProfileDevPanel] AccountProfileDevRequest missing after 10s.",
		"Check ServerScriptService > AccountProfileDevTools v4."
	)
	return
end

local request = requestObject :: RemoteFunction

local authorized = false

do
	local okCall, result = pcall(function()
		return request:InvokeServer("CanUse")
	end)

	authorized = okCall and result == true
end

if not authorized then
	warn("[AccountProfileDevPanel] Authorization failed v5")
	return
end

print("[AccountProfileDevPanel] AUTHORIZED v5")

local devGui = playerGui:WaitForChild("WAYLESSDevMenu") :: ScreenGui
local devMenuPanel = devGui:WaitForChild("Panel") :: Frame

local oldRoot = devMenuPanel:FindFirstChild("AccountProfileDevPanelRoot")
if oldRoot then
	oldRoot:Destroy()
end

local root = Instance.new("Frame")
root.Name = "AccountProfileDevPanelRoot"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Position = UDim2.fromScale(0, 0)
root.ZIndex = 50
root.Parent = devMenuPanel

local openButton = Instance.new("TextButton")
openButton.Name = "AccountSlotsButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -14, 1, -44)
openButton.Size = UDim2.fromOffset(150, 30)
openButton.BackgroundColor3 = Color3.fromRGB(26, 29, 34)
openButton.BorderSizePixel = 0
openButton.Text = "ACCOUNT / SLOTS"
openButton.TextColor3 = Color3.fromRGB(235, 235, 235)
openButton.TextSize = 14
openButton.Font = Enum.Font.GothamBold
openButton.ZIndex = 51
openButton.Parent = root

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 6)
openCorner.Parent = openButton

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -14, 0, 46)
panel.Size = UDim2.fromOffset(430, 650)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 52
panel.Parent = root

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Color = Color3.fromRGB(110, 115, 125)
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 10)
title.Size = UDim2.new(1, -110, 0, 26)
title.Text = "ACCOUNT / CHARACTER SLOTS QA"
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.ZIndex = 53
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 8)
closeButton.Size = UDim2.fromOffset(32, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(43, 46, 54)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(235, 235, 235)
closeButton.TextSize = 13
closeButton.Font = Enum.Font.GothamBold
closeButton.ZIndex = 53
closeButton.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 5)
closeCorner.Parent = closeButton

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.fromOffset(16, 39)
statusLabel.Size = UDim2.new(1, -32, 0, 22)
statusLabel.Text = "Ready"
statusLabel.TextColor3 = Color3.fromRGB(175, 185, 195)
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Font = Enum.Font.Gotham
statusLabel.ZIndex = 53
statusLabel.Parent = panel

local sessionLabel = Instance.new("TextLabel")
sessionLabel.BackgroundTransparency = 1
sessionLabel.Position = UDim2.fromOffset(16, 60)
sessionLabel.Size = UDim2.new(1, -32, 0, 18)
sessionLabel.Text = "Session slot: ? | Next Play: ?"
sessionLabel.TextColor3 = Color3.fromRGB(205, 210, 218)
sessionLabel.TextSize = 11
sessionLabel.TextXAlignment = Enum.TextXAlignment.Left
sessionLabel.Font = Enum.Font.GothamSemibold
sessionLabel.ZIndex = 53
sessionLabel.Parent = panel

local function makeButton(
	parent: Instance,
	text: string,
	position: UDim2,
	size: UDim2
): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Color3.fromRGB(39, 43, 50)
	button.BorderSizePixel = 0
	button.Position = position
	button.Size = size
	button.Text = text
	button.TextColor3 = Color3.fromRGB(238, 238, 238)
	button.TextSize = 12
	button.Font = Enum.Font.GothamSemibold
	button.ZIndex = 53
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button

	return button
end

local grantChuunin = makeButton(
	panel,
	"GRANT CHUUNIN SLOT",
	UDim2.fromOffset(16, 88),
	UDim2.fromOffset(184, 32)
)

local grantJonin = makeButton(
	panel,
	"GRANT JONIN SLOT",
	UDim2.fromOffset(216, 88),
	UDim2.fromOffset(184, 32)
)

local grantPurchase = makeButton(
	panel,
	"PURCHASE TEST SLOT",
	UDim2.fromOffset(16, 126),
	UDim2.fromOffset(184, 32)
)

local refreshButton = makeButton(
	panel,
	"REFRESH",
	UDim2.fromOffset(216, 126),
	UDim2.fromOffset(86, 32)
)

local saveButton = makeButton(
	panel,
	"SAVE",
	UDim2.fromOffset(314, 126),
	UDim2.fromOffset(86, 32)
)

local clearNextButton = makeButton(
	panel,
	"NEXT=1",
	UDim2.fromOffset(314, 88),
	UDim2.fromOffset(86, 32)
)

local currenciesFrame = Instance.new("Frame")
currenciesFrame.BackgroundColor3 = Color3.fromRGB(23, 26, 31)
currenciesFrame.BorderSizePixel = 0
currenciesFrame.Position = UDim2.fromOffset(16, 168)
currenciesFrame.Size = UDim2.new(1, -32, 0, 122)
currenciesFrame.ZIndex = 53
currenciesFrame.Parent = panel

local currencyCorner = Instance.new("UICorner")
currencyCorner.CornerRadius = UDim.new(0, 6)
currencyCorner.Parent = currenciesFrame

local currencyLabels: {[string]: TextLabel} = {}

local renderSnapshot: (any) -> ()
local invokeAndRender: (string, any?) -> ()

local currencyRows = {
	{ Id = "ClanRerolls", Label = "Clan Rerolls" },
	{ Id = "NatureRerolls", Label = "Nature Rerolls" },
	{ Id = "RevivalTokens", Label = "Revival Tokens" },
}

for index, row in ipairs(currencyRows) do
	local y = 8 + ((index - 1) * 36)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.new(1, -90, 0, 28)
	label.Text = row.Label .. ": 0"
	label.TextColor3 = Color3.fromRGB(225, 225, 225)
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.Gotham
	label.ZIndex = 54
	label.Parent = currenciesFrame
	currencyLabels[row.Id] = label

	local addButton = makeButton(
		currenciesFrame,
		"+1",
		UDim2.new(1, -64, 0, y),
		UDim2.fromOffset(52, 28)
	)
	addButton.ZIndex = 54

	addButton.MouseButton1Click:Connect(function()
		statusLabel.Text = "Granting " .. row.Label .. "..."

		local okCall, response = pcall(function()
			return request:InvokeServer(
				"GrantCurrency",
				{
					CurrencyId = row.Id,
					Amount = 1,
				}
			)
		end)

		if not okCall then
			statusLabel.Text = "Remote error while granting currency"
			return
		end

		if typeof(response) ~= "table" then
			statusLabel.Text = "Invalid server response"
			return
		end

		statusLabel.Text = tostring(response.Reason or "Done")

		if response.Snapshot then
			renderSnapshot(response.Snapshot)
		end
	end)
end

local lifecycleFrame = Instance.new("Frame")
lifecycleFrame.BackgroundColor3 = Color3.fromRGB(23, 26, 31)
lifecycleFrame.BorderSizePixel = 0
lifecycleFrame.Position = UDim2.fromOffset(16, 300)
lifecycleFrame.Size = UDim2.new(1, -32, 0, 180)
lifecycleFrame.ZIndex = 53
lifecycleFrame.Parent = panel

local lifecycleCorner = Instance.new("UICorner")
lifecycleCorner.CornerRadius = UDim.new(0, 6)
lifecycleCorner.Parent = lifecycleFrame

local lifecycleTitle = Instance.new("TextLabel")
lifecycleTitle.BackgroundTransparency = 1
lifecycleTitle.Position = UDim2.fromOffset(12, 7)
lifecycleTitle.Size = UDim2.new(1, -24, 0, 18)
lifecycleTitle.Text = "ACTIVE LIFE QA"
lifecycleTitle.TextColor3 = Color3.fromRGB(225, 225, 225)
lifecycleTitle.TextSize = 12
lifecycleTitle.TextXAlignment = Enum.TextXAlignment.Left
lifecycleTitle.Font = Enum.Font.GothamBold
lifecycleTitle.ZIndex = 54
lifecycleTitle.Parent = lifecycleFrame

local lifecycleIdentityLabel = Instance.new("TextLabel")
lifecycleIdentityLabel.BackgroundTransparency = 1
lifecycleIdentityLabel.Position = UDim2.fromOffset(12, 27)
lifecycleIdentityLabel.Size = UDim2.new(1, -24, 0, 32)
lifecycleIdentityLabel.Text = "Slot ? | State ? | Life ?"
lifecycleIdentityLabel.TextColor3 = Color3.fromRGB(190, 198, 208)
lifecycleIdentityLabel.TextSize = 10
lifecycleIdentityLabel.TextWrapped = true
lifecycleIdentityLabel.TextXAlignment = Enum.TextXAlignment.Left
lifecycleIdentityLabel.TextYAlignment = Enum.TextYAlignment.Top
lifecycleIdentityLabel.Font = Enum.Font.Gotham
lifecycleIdentityLabel.ZIndex = 54
lifecycleIdentityLabel.Parent = lifecycleFrame

local markDeathButton = makeButton(
	lifecycleFrame,
	"MARK FINAL DEATH",
	UDim2.fromOffset(12, 66),
	UDim2.fromOffset(122, 28)
)
markDeathButton.ZIndex = 54

local reviveButton = makeButton(
	lifecycleFrame,
	"REVIVE",
	UDim2.fromOffset(140, 66),
	UDim2.fromOffset(76, 28)
)
reviveButton.ZIndex = 54

local armWipeButton = makeButton(
	lifecycleFrame,
	"ARM WIPE",
	UDim2.fromOffset(222, 66),
	UDim2.fromOffset(80, 28)
)
armWipeButton.ZIndex = 54

local confirmWipeButton = makeButton(
	lifecycleFrame,
	"CONFIRM",
	UDim2.fromOffset(308, 66),
	UDim2.fromOffset(80, 28)
)
confirmWipeButton.ZIndex = 54

local cancelWipeButton = makeButton(
	lifecycleFrame,
	"CANCEL WIPE",
	UDim2.fromOffset(12, 102),
	UDim2.fromOffset(122, 28)
)
cancelWipeButton.ZIndex = 54

local createNextLifeButton = makeButton(
	lifecycleFrame,
	"CREATE NEXT LIFE",
	UDim2.fromOffset(140, 102),
	UDim2.fromOffset(162, 28)
)
createNextLifeButton.ZIndex = 54

local rejoinLabel = Instance.new("TextLabel")
rejoinLabel.BackgroundTransparency = 1
rejoinLabel.Position = UDim2.fromOffset(308, 102)
rejoinLabel.Size = UDim2.fromOffset(80, 28)
rejoinLabel.Text = ""
rejoinLabel.TextColor3 = Color3.fromRGB(255, 205, 120)
rejoinLabel.TextSize = 10
rejoinLabel.TextWrapped = true
rejoinLabel.Font = Enum.Font.GothamBold
rejoinLabel.ZIndex = 54
rejoinLabel.Parent = lifecycleFrame

local enterAfterlifeButton = makeButton(
	lifecycleFrame,
	"FINAL DEATH -> AFTERLIFE",
	UDim2.fromOffset(12, 138),
	UDim2.fromOffset(212, 28)
)
enterAfterlifeButton.ZIndex = 54

local afterlifeHint = Instance.new("TextLabel")
afterlifeHint.BackgroundTransparency = 1
afterlifeHint.Position = UDim2.fromOffset(232, 138)
afterlifeHint.Size = UDim2.fromOffset(156, 28)
afterlifeHint.Text = "Published Experience only"
afterlifeHint.TextColor3 = Color3.fromRGB(150, 158, 175)
afterlifeHint.TextSize = 9
afterlifeHint.TextWrapped = true
afterlifeHint.Font = Enum.Font.Gotham
afterlifeHint.ZIndex = 54
afterlifeHint.Parent = lifecycleFrame

local function setActionEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = enabled and 0 or 0.45
	button.BackgroundTransparency = enabled and 0 or 0.35
end

local lifecycleWipeArmed = false
local lifecycleRequiresRejoin = false

local slotsHeader = Instance.new("TextLabel")
slotsHeader.BackgroundTransparency = 1
slotsHeader.Position = UDim2.fromOffset(16, 490)
slotsHeader.Size = UDim2.new(1, -32, 0, 24)
slotsHeader.Text = "SLOTS"
slotsHeader.TextColor3 = Color3.fromRGB(205, 210, 218)
slotsHeader.TextSize = 12
slotsHeader.TextXAlignment = Enum.TextXAlignment.Left
slotsHeader.Font = Enum.Font.GothamBold
slotsHeader.ZIndex = 53
slotsHeader.Parent = panel

local slotsScroll = Instance.new("ScrollingFrame")
slotsScroll.BackgroundColor3 = Color3.fromRGB(13, 15, 18)
slotsScroll.BorderSizePixel = 0
slotsScroll.Position = UDim2.fromOffset(16, 516)
slotsScroll.Size = UDim2.new(1, -32, 1, -532)
slotsScroll.ScrollBarThickness = 5
slotsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
slotsScroll.CanvasSize = UDim2.fromOffset(0, 0)
slotsScroll.ZIndex = 53
slotsScroll.Parent = panel

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = slotsScroll

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 7)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = slotsScroll

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = slotsScroll

local function natureText(origin: any): string
	if typeof(origin) ~= "table" then
		return "Origin pending"
	end

	local parts = {}
	if origin.Nature1Id then
		table.insert(parts, tostring(origin.Nature1Id))
	end
	if origin.Nature2Id then
		table.insert(parts, tostring(origin.Nature2Id))
	end
	if origin.Nature3Id then
		table.insert(parts, tostring(origin.Nature3Id))
	end

	return #parts > 0 and table.concat(parts, " + ") or "No natures"
end

local function sortedSlotIds(slots: any): {string}
	local result = {}

	if typeof(slots) == "table" then
		for rawId in pairs(slots) do
			table.insert(result, tostring(rawId))
		end
	end

	table.sort(result, function(a, b)
		return (tonumber(a) or math.huge) < (tonumber(b) or math.huge)
	end)

	return result
end

renderSnapshot = function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		statusLabel.Text = "Snapshot missing"
		return
	end

	local currencies = snapshot.Currencies
	if typeof(currencies) == "table" then
		currencyLabels.ClanRerolls.Text =
			"Clan Rerolls: " .. tostring(currencies.ClanRerolls or 0)
		currencyLabels.NatureRerolls.Text =
			"Nature Rerolls: " .. tostring(currencies.NatureRerolls or 0)
		currencyLabels.RevivalTokens.Text =
			"Revival Tokens: " .. tostring(currencies.RevivalTokens or 0)
	end

	for _, child in ipairs(slotsScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local slots = snapshot.Slots

	local activeSlotId =
		tostring(
			player:GetAttribute("CharacterActiveSlotId")
			or "?"
		)

	local activeSlot =
		typeof(slots) == "table"
		and slots[activeSlotId]
		or nil

	local activeState =
		typeof(activeSlot) == "table"
		and tostring(activeSlot.State or "?")
		or "?"

	local activeLife =
		typeof(activeSlot) == "table"
		and activeSlot.CurrentLife
		or nil

	local lifeId =
		typeof(activeLife) == "table"
		and tostring(activeLife.LifeId or "-")
		or "-"

	local characterId =
		typeof(activeLife) == "table"
		and tostring(activeLife.CharacterId or "-")
		or "-"

	local function shortId(value: string): string
		if #value <= 18 then
			return value
		end
		return string.sub(value, 1, 8)
			.. "..."
			.. string.sub(value, -7)
	end

	lifecycleIdentityLabel.Text =
		"Slot " .. activeSlotId
		.. " | " .. activeState
		.. " | Life " .. shortId(lifeId)
		.. "\nCharacter " .. shortId(characterId)

	local mustExit =
		player:GetAttribute("CharacterLifecycleMustExitSession") == true
		or lifecycleRequiresRejoin

	setActionEnabled(
		markDeathButton,
		activeState == "Alive"
			and not mustExit
	)

	setActionEnabled(
		reviveButton,
		activeState == "DeadAwaitingDecision"
			and not mustExit
	)

	setActionEnabled(
		armWipeButton,
		activeState == "DeadAwaitingDecision"
			and not mustExit
	)

	setActionEnabled(
		confirmWipeButton,
		activeState == "DeadAwaitingDecision"
			and lifecycleWipeArmed
			and not mustExit
	)

	setActionEnabled(
		cancelWipeButton,
		lifecycleWipeArmed
			and not mustExit
	)

	setActionEnabled(
		createNextLifeButton,
		(activeState == "Empty" or activeState == "Creating")
			and mustExit
	)

	setActionEnabled(
		enterAfterlifeButton,
		(activeState == "Alive"
			or activeState == "DeadAwaitingDecision")
			and not mustExit
	)

	rejoinLabel.Text =
		mustExit
		and "STOP -> PLAY"
		or (lifecycleWipeArmed and "WIPE ARMED" or "")

	for order, slotId in ipairs(sortedSlotIds(slots)) do
		local slot = slots[slotId]
		if typeof(slot) == "table" then
			local card = Instance.new("Frame")
			card.Name = "Slot_" .. slotId
			card.BackgroundColor3 = Color3.fromRGB(28, 31, 37)
			card.BorderSizePixel = 0
			card.Size = UDim2.new(1, -2, 0, 104)
			card.LayoutOrder = order
			card.ZIndex = 54
			card.Parent = slotsScroll

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 5)
			cardCorner.Parent = card

			local heading = Instance.new("TextLabel")
			heading.BackgroundTransparency = 1
			heading.Position = UDim2.fromOffset(10, 6)
			heading.Size = UDim2.new(1, -126, 0, 20)
			heading.Text = string.format(
				"SLOT %s  |  %s  |  %s",
				slotId,
				tostring(slot.UnlockSource or "?"),
				tostring(slot.State or "?")
			)
			heading.TextColor3 = Color3.fromRGB(240, 240, 240)
			heading.TextSize = 12
			heading.TextXAlignment = Enum.TextXAlignment.Left
			heading.Font = Enum.Font.GothamBold
			heading.ZIndex = 55
			heading.Parent = card

			local origin = slot.PermanentOrigin

			local originLabel = Instance.new("TextLabel")
			originLabel.BackgroundTransparency = 1
			originLabel.Position = UDim2.fromOffset(10, 29)
			originLabel.Size = UDim2.new(1, -126, 0, 18)
			originLabel.Text =
				"Clan: "
				.. tostring(typeof(origin) == "table" and origin.ClanId or "Pending")
				.. "   |   Natures: "
				.. natureText(origin)
			originLabel.TextColor3 = Color3.fromRGB(205, 210, 216)
			originLabel.TextSize = 11
			originLabel.TextXAlignment = Enum.TextXAlignment.Left
			originLabel.Font = Enum.Font.Gotham
			originLabel.ZIndex = 55
			originLabel.Parent = card

			local life = slot.CurrentLife
			local lifeText = "No current life"
			if typeof(life) == "table" then
				lifeText = string.format(
					"Life #%s  |  %s  |  Revivals: %s",
					tostring(life.LifeNumber or slot.LifeCounter or 0),
					tostring(life.State or slot.State or "?"),
					tostring(life.RevivalCount or 0)
				)
			end

			local lifeLabel = Instance.new("TextLabel")
			lifeLabel.BackgroundTransparency = 1
			lifeLabel.Position = UDim2.fromOffset(10, 51)
			lifeLabel.Size = UDim2.new(1, -126, 0, 18)
			lifeLabel.Text = lifeText
			lifeLabel.TextColor3 = Color3.fromRGB(165, 175, 186)
			lifeLabel.TextSize = 11
			lifeLabel.TextXAlignment = Enum.TextXAlignment.Left
			lifeLabel.Font = Enum.Font.Gotham
			lifeLabel.ZIndex = 55
			lifeLabel.Parent = card

			local actionButton = makeButton(
				card,
				"",
				UDim2.new(1, -112, 0, 31),
				UDim2.fromOffset(102, 34)
			)
			actionButton.ZIndex = 56

			if tostring(slot.State) == "Empty" or tostring(slot.State) == "Creating" then
				local activeSlot = tostring(player:GetAttribute("CharacterActiveSlotId") or "")
				if activeSlot == slotId
					and player:GetAttribute("CharacterLifecycleMustExitSession") == true then

					actionButton.Text = "LIFECYCLE ABOVE"
					actionButton.AutoButtonColor = false
					actionButton.Active = false
				else
					actionButton.Text = "CREATE QA LIFE"
					actionButton.MouseButton1Click:Connect(function()
						invokeAndRender("CreateTestLife", { SlotId = slotId })
					end)
				end
			elseif tostring(slot.State) == "Alive" then
				local activeSlot = tostring(player:GetAttribute("CharacterActiveSlotId") or "")
				if activeSlot == slotId then
					if player:GetAttribute("CharacterLifecycleMustExitSession") == true then
						actionButton.Text = "REJOIN REQUIRED"
					else
						actionButton.Text = "ACTIVE NOW"
					end
					actionButton.AutoButtonColor = false
					actionButton.Active = false
				else
					actionButton.Text = "USE NEXT PLAY"
					actionButton.MouseButton1Click:Connect(function()
						print(
							"[AccountProfileDevPanel] CLICK USE NEXT PLAY",
							"Slot=" .. slotId
						)
						statusLabel.Text = "Requesting next play Slot " .. slotId .. "..."
						invokeAndRender("SetNextSessionSlot", { SlotId = slotId })
					end)
				end
			elseif tostring(slot.State) == "DeadAwaitingDecision" then
				actionButton.Text = "RETURN AFTERLIFE"
				actionButton.MouseButton1Click:Connect(function()
					print(
						"[AccountProfileDevPanel] CLICK RETURN AFTERLIFE",
						"Slot=" .. slotId
					)
					statusLabel.Text =
						"Returning dead Slot "
						.. slotId
						.. " to Afterlife..."

					invokeAndRender(
						"ReturnDeadSlotToAfterlife",
						{
							SlotId = slotId,
						}
					)
				end)
			else
				actionButton.Text = "UNAVAILABLE"
				actionButton.AutoButtonColor = false
				actionButton.Active = false
			end
		end
	end

	local entitlements = snapshot.Entitlements
	if lifecycleRequiresRejoin then
		statusLabel.Text = "REJOIN REQUIRED — create next life first if slot is Empty"
	elseif lifecycleWipeArmed then
		statusLabel.Text = "WIPE ARMED — confirm or cancel"
	elseif typeof(entitlements) == "table" then
		statusLabel.Text = string.format(
			"Slots=%d | Chuunin=%s | Jonin=%s | Purchased=%s",
			#sortedSlotIds(snapshot.Slots),
			tostring(entitlements.ChuuninSlotGranted == true),
			tostring(entitlements.JoninSlotGranted == true),
			tostring(entitlements.PurchasedSlotCount or 0)
		)
	end
end

invokeAndRender = function(action: string, payload: any?)
	statusLabel.Text = action .. "..."

	local okCall, response = pcall(function()
		return request:InvokeServer(action, payload)
	end)

	if not okCall then
		warn(
			"[AccountProfileDevPanel] REMOTE ERROR",
			action,
			response
		)
		statusLabel.Text = "Remote error: " .. action
		return
	end

	if typeof(response) ~= "table" then
		statusLabel.Text = "Invalid server response"
		return
	end

	statusLabel.Text = tostring(response.Reason or "Done")

	lifecycleWipeArmed = response.WipeArmed == true
	lifecycleRequiresRejoin = response.RequiresRejoin == true

	if response.WipeArmed == true then
		statusLabel.Text =
			"WIPE ARMED — confirm within "
			.. tostring(response.WipeSecondsRemaining or 0)
			.. "s"
	elseif response.RequiresRejoin == true
		and response.Reason == "NewLifeCreatedStopAndRejoin" then

		statusLabel.Text = "NEW LIFE CREATED — STOP -> PLAY NOW"
	end

	print(
		"[AccountProfileDevPanel] RESPONSE",
		"Action=" .. action,
		"Ok=" .. tostring(response.Ok),
		"Reason=" .. tostring(response.Reason),
		"Slot=" .. tostring(response.SlotId or "-"),
		"Next=" .. tostring(response.NextStudioSlotId or "-")
	)

	local active = tostring(response.ActiveSlotId or player:GetAttribute("CharacterActiveSlotId") or "?")
	local nextSlot = tostring(response.NextStudioSlotId or "1")
	local source = tostring(response.SelectionSource or player:GetAttribute("CharacterSlotSelectionSource") or "?")
	sessionLabel.Text = "Session slot: " .. active .. " (" .. source .. ") | Next Play: " .. nextSlot

	if response.Snapshot then
		renderSnapshot(response.Snapshot)
	end
end

enterAfterlifeButton.MouseButton1Click:Connect(function()
	invokeAndRender("EnterAfterlife")
end)

markDeathButton.MouseButton1Click:Connect(function()
	invokeAndRender("MarkFinalDeath")
end)

reviveButton.MouseButton1Click:Connect(function()
	invokeAndRender("ReviveCurrentLife")
end)

armWipeButton.MouseButton1Click:Connect(function()
	invokeAndRender("ArmFinalWipe")
end)

confirmWipeButton.MouseButton1Click:Connect(function()
	invokeAndRender("ConfirmFinalWipe")
end)

cancelWipeButton.MouseButton1Click:Connect(function()
	invokeAndRender("CancelFinalWipe")
end)

createNextLifeButton.MouseButton1Click:Connect(function()
	invokeAndRender("CreateNextLifeAfterWipe")
end)

grantChuunin.MouseButton1Click:Connect(function()
	invokeAndRender("GrantChuuninSlot")
end)

grantJonin.MouseButton1Click:Connect(function()
	invokeAndRender("GrantJoninSlot")
end)

grantPurchase.MouseButton1Click:Connect(function()
	invokeAndRender("GrantPurchasedSlot")
end)

refreshButton.MouseButton1Click:Connect(function()
	invokeAndRender("GetSnapshot")
end)

saveButton.MouseButton1Click:Connect(function()
	invokeAndRender("Save")
end)

clearNextButton.MouseButton1Click:Connect(function()
	invokeAndRender("ClearNextSessionSlot")
end)

openButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible

	if panel.Visible then
		invokeAndRender("GetSnapshot")
	end
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

-- Initial fetch prepares the panel even before it is opened.
task.defer(function()
	invokeAndRender("GetSnapshot")
end)

print(
	"[AccountProfileDevPanel] READY v7 DeadSlotReturn"
		.. " | InjectedInto=WAYLESSDevMenu"
		.. " | F7VisibilityFixed=ON | NextPlaySelection=ON | LifecycleQA=ON | HotSwitch=OFF"
)
