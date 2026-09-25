--!strict
-- StarterPlayer > StarterPlayerScripts > WAYLESSDevMenu
--
-- WAYLESS unified developer menu v1.4 - Inventory Dev Tools.
--
-- Toggle: F7
--
-- Replaces the old separate client menus:
-- CharacterOriginDevMenu
-- ProgressionDevMenu
-- NinjaRankDevMenu
-- StatusEffectDevMenu
--
-- Existing server-authoritative remotes are reused.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local UserInputService =
	game:GetService("UserInputService")

local player =
	Players.LocalPlayer

local playerGui =
	player:WaitForChild(
		"PlayerGui"
	)

local originShared =
	ReplicatedStorage:
	WaitForChild(
		"CharacterOriginSystem"
	):
	WaitForChild(
		"Shared"
	)

local ClanDefinitions =
	require(
		originShared:
		WaitForChild(
			"ClanDefinitions"
		)
	)

local InventoryCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"InventoryCatalog"
		)
	)

---------------------------------------------------------------------
-- REMOTES
---------------------------------------------------------------------

local commonRemotes =
	ReplicatedStorage:
	WaitForChild(
		"Remotes"
	)

local devRequest =
	commonRemotes:
	WaitForChild(
		"WAYLESSDevRequest"
	) :: RemoteFunction

local progressionRequest =
	commonRemotes:
	WaitForChild(
		"ProgressionDevRequest"
	) :: RemoteFunction

local ninjaRankRequest =
	commonRemotes:
	WaitForChild(
		"NinjaRankDevRequest"
	) :: RemoteFunction

local originRequest =
	ReplicatedStorage:
	WaitForChild(
		"CharacterOriginSystem"
	):
	WaitForChild(
		"Remotes"
	):
	WaitForChild(
		"CharacterOriginDevRequest"
	) :: RemoteFunction

local lifecycleRequest =
	ReplicatedStorage:
	WaitForChild(
		"CharacterLifecycleSystem"
	):
	WaitForChild(
		"Remotes"
	):
	WaitForChild(
		"CharacterLifecycleDevRequest"
	) :: RemoteFunction

local inventoryDevRequest =
	ReplicatedStorage:
	WaitForChild(
		"InventoryDevRemotes"
	):
	WaitForChild(
		"Request"
	) :: RemoteFunction

local statusDevApply =
	ReplicatedStorage:
	WaitForChild(
		"StatusEffectRemotes"
	):
	WaitForChild(
		"DevApply"
	) :: RemoteEvent

---------------------------------------------------------------------
-- AUTHORIZATION
---------------------------------------------------------------------

local authorized = false

do
	local okCall,
		ok =
		pcall(
			function()
				local success =
				devRequest:
				InvokeServer(
					"CanUse"
				)

				return success
			end
		)

	authorized =
		okCall
		and ok == true
end

if not authorized then
	warn(
		"[WAYLESSDevMenu] Authorization failed"
	)

	return
end

---------------------------------------------------------------------
-- REMOVE OLD SCREEN GUIS
---------------------------------------------------------------------

local OLD_GUI_NAMES = {
	"CharacterOriginDevMenu",
	"ProgressionDevMenu",
	"NinjaRankDevMenu",
	"StatusEffectDevMenu",
}

for _, guiName in ipairs(
	OLD_GUI_NAMES
	) do
	local old =
		playerGui:
		FindFirstChild(
			guiName
		)

	if old then
		old:Destroy()
	end
end

local existing =
	playerGui:
	FindFirstChild(
		"WAYLESSDevMenu"
	)

if existing then
	existing:Destroy()
end

---------------------------------------------------------------------
-- UI HELPERS
---------------------------------------------------------------------

local gui =
	Instance.new("ScreenGui")

gui.Name =
	"WAYLESSDevMenu"

gui.ResetOnSpawn =
	false

gui.IgnoreGuiInset =
	false

gui.Enabled =
	true

gui.Parent =
	playerGui

local panel =
	Instance.new("Frame")

panel.Name =
	"Panel"

panel.AnchorPoint =
	Vector2.new(1, 0)

panel.Position =
	UDim2.new(
		1,
		-20,
		0,
		70
	)

panel.Size =
	UDim2.fromOffset(
		620,
		560
	)

panel.BackgroundTransparency =
	0.04

panel.BorderSizePixel =
	0

panel.Visible =
	false

panel.Parent =
	gui

local panelCorner =
	Instance.new("UICorner")

panelCorner.CornerRadius =
	UDim.new(0, 10)

panelCorner.Parent =
	panel

local header =
	Instance.new("TextLabel")

header.Size =
	UDim2.new(
		1,
		-24,
		0,
		34
	)

header.Position =
	UDim2.fromOffset(
		12,
		10
	)

header.BackgroundTransparency =
	1

header.Text =
	"WAYLESS • DEVELOPER MENU"

header.TextSize =
	18

header.Font =
	Enum.Font.GothamBold

header.TextXAlignment =
	Enum.TextXAlignment.Left

header.Parent =
	panel

local feedback =
	Instance.new("TextLabel")

feedback.Size =
	UDim2.new(
		1,
		-24,
		0,
		26
	)

feedback.Position =
	UDim2.fromOffset(
		12,
		44
	)

feedback.BackgroundTransparency =
	1

feedback.Text =
	"F7 toggles menu."

feedback.TextSize =
	12

feedback.Font =
	Enum.Font.Gotham

feedback.TextXAlignment =
	Enum.TextXAlignment.Left

feedback.Parent =
	panel

local tabBar =
	Instance.new("Frame")

tabBar.Size =
	UDim2.new(
		1,
		-24,
		0,
		34
	)

tabBar.Position =
	UDim2.fromOffset(
		12,
		76
	)

tabBar.BackgroundTransparency =
	1

tabBar.Parent =
	panel

local tabLayout =
	Instance.new("UIListLayout")

tabLayout.FillDirection =
	Enum.FillDirection.Horizontal

tabLayout.Padding =
	UDim.new(0, 5)

tabLayout.Parent =
	tabBar

local content =
	Instance.new("Frame")

content.Size =
	UDim2.new(
		1,
		-24,
		1,
		-126
	)

content.Position =
	UDim2.fromOffset(
		12,
		116
	)

content.BackgroundTransparency =
	1

content.Parent =
	panel

local pages: {[string]: ScrollingFrame} = {}
local tabButtons: {[string]: TextButton} = {}
local currentPage = "Overview"

local function makePage(
	name: string
): ScrollingFrame
	local page =
		Instance.new(
			"ScrollingFrame"
		)

	page.Name =
		name

	page.Size =
		UDim2.fromScale(
			1,
			1
		)

	page.BackgroundTransparency =
		1

	page.BorderSizePixel =
		0

	page.ScrollBarThickness =
		6

	page.AutomaticCanvasSize =
		Enum.AutomaticSize.Y

	page.CanvasSize =
		UDim2.new()

	page.Visible =
		false

	page.Parent =
		content

	local padding =
		Instance.new(
			"UIPadding"
		)

	padding.PaddingBottom =
		UDim.new(0, 12)

	padding.Parent =
		page

	local layout =
		Instance.new(
			"UIListLayout"
		)

	layout.Padding =
		UDim.new(0, 8)

	layout.SortOrder =
		Enum.SortOrder.LayoutOrder

	layout.Parent =
		page

	pages[name] =
		page

	return page
end

local function makeLabel(
	parent: Instance,
	text: string,
	height: number,
	size: number,
	bold: boolean?
): TextLabel
	local label =
		Instance.new(
			"TextLabel"
		)

	label.Size =
		UDim2.new(
			1,
			-4,
			0,
			height
		)

	label.BackgroundTransparency =
		1

	label.Text =
		text

	label.TextSize =
		size

	label.Font =
		bold
		and Enum.Font.GothamBold
		or Enum.Font.Gotham

	label.TextXAlignment =
		Enum.TextXAlignment.Left

	label.TextYAlignment =
		Enum.TextYAlignment.Top

	label.TextWrapped =
		true

	label.Parent =
		parent

	return label
end

local function makeRow(
	parent: Instance,
	height: number?
): Frame
	local row =
		Instance.new(
			"Frame"
		)

	row.Size =
		UDim2.new(
			1,
			-4,
			0,
			height or 34
		)

	row.BackgroundTransparency =
		1

	row.Parent =
		parent

	local layout =
		Instance.new(
			"UIListLayout"
		)

	layout.FillDirection =
		Enum.FillDirection.Horizontal

	layout.Padding =
		UDim.new(0, 6)

	layout.Parent =
		row

	return row
end

local function makeButton(
	parent: Instance,
	text: string,
	widthScale: number,
	callback: () -> ()
): TextButton
	local button =
		Instance.new(
			"TextButton"
		)

	button.Size =
		UDim2.new(
			widthScale,
			-4,
			1,
			0
		)

	button.Text =
		text

	button.TextSize =
		12

	button.Font =
		Enum.Font.GothamMedium

	button.BorderSizePixel =
		0

	button.Parent =
		parent

	local corner =
		Instance.new(
			"UICorner"
		)

	corner.CornerRadius =
		UDim.new(0, 6)

	corner.Parent =
		button

	button.Activated:
		Connect(
			callback
		)

	return button
end

local function makeBox(
	parent: Instance,
	placeholder: string,
	widthScale: number
): TextBox
	local box =
		Instance.new(
			"TextBox"
		)

	box.Size =
		UDim2.new(
			widthScale,
			-4,
			1,
			0
		)

	box.PlaceholderText =
		placeholder

	box.Text =
		""

	box.ClearTextOnFocus =
		false

	box.TextSize =
		12

	box.Font =
		Enum.Font.Gotham

	box.BorderSizePixel =
		0

	box.Parent =
		parent

	local corner =
		Instance.new(
			"UICorner"
		)

	corner.CornerRadius =
		UDim.new(0, 6)

	corner.Parent =
		box

	return box
end

local function setFeedback(
	message: any
)
	feedback.Text =
		tostring(message)
end

---------------------------------------------------------------------
-- SAFE REQUEST HELPERS
---------------------------------------------------------------------

local function invokeOrigin(
	action: string,
	payload: any?
)
	local okCall,
		result =
		pcall(
			function()
				return originRequest:
				InvokeServer(
					action,
					payload
				)
			end
		)

	if not okCall then
		setFeedback(
			"Origin error: "
				.. tostring(result)
		)

		return
	end

	setFeedback(
		result.Reason
	)
end

local function invokeProgression(
	action: string,
	value: any?
)
	local okCall,
		success,
		message =
		pcall(
			function()
				return progressionRequest:
				InvokeServer(
					action,
					value
				)
			end
		)

	if not okCall then
		setFeedback(
			"Progression error: "
				.. tostring(success)
		)

		return
	end

	setFeedback(message)
end

local function invokeRank(
	action: string,
	value: any?
)
	local okCall,
		success,
		message =
		pcall(
			function()
				return ninjaRankRequest:
				InvokeServer(
					action,
					value
				)
			end
		)

	if not okCall then
		setFeedback(
			"Rank error: "
				.. tostring(success)
		)

		return
	end

	setFeedback(message)
end

local function invokeDev(
	action: string,
	value: any?
)
	local okCall,
		success,
		message =
		pcall(
			function()
				return devRequest:
				InvokeServer(
					action,
					value
				)
			end
		)

	if not okCall then
		setFeedback(
			"Dev error: "
				.. tostring(success)
		)

		return
	end

	setFeedback(message)
end

local function invokeLifecycle(
	action: string,
	payload: any?
)
	local okCall,
		result =
		pcall(
			function()
				return lifecycleRequest:
				InvokeServer(
					action,
					payload
				)
			end
		)

	if not okCall then
		setFeedback(
			"Lifecycle error: "
				.. tostring(result)
		)

		return
	end

	if typeof(result) ==
		"table" then

		setFeedback(
			result.Reason
				or result.Ok
				or "Lifecycle request complete"
		)

	else
		setFeedback(
			result
		)
	end
end

local function invokeInventoryDev(
	action: string,
	payload: any?
)
	local okCall,
		result =
		pcall(
			function()
				return inventoryDevRequest:
				InvokeServer(
					action,
					payload
				)
			end
		)

	if not okCall then
		setFeedback(
			"Inventory dev error: "
				.. tostring(result)
		)

		return
	end

	if typeof(result) ==
		"table" then

		if result.ItemId ~= nil
			and result.Amount ~= nil then

			setFeedback(
				tostring(
					result.ItemId
				)
					.. " = "
					.. tostring(
						result.Amount
					)
					.. " | "
					.. tostring(
						result.Reason
					)
			)
		else
			setFeedback(
				result.Reason
					or result.Ok
					or "Inventory request complete"
			)
		end
	else
		setFeedback(
			result
		)
	end
end

local function applyStatus(
	effectId: string
)
	statusDevApply:
		FireServer(
			"Apply",
			effectId
		)

	setFeedback(
		"Apply status: "
			.. effectId
	)
end

local function clearStatuses()
	statusDevApply:
		FireServer(
			"Clear"
		)

	setFeedback(
		"Clear statuses requested"
	)
end

---------------------------------------------------------------------
-- OVERVIEW
---------------------------------------------------------------------

local overview =
	makePage(
		"Overview"
	)

makeLabel(
	overview,
	"CURRENT CHARACTER",
	24,
	13,
	true
)

local overviewState =
	makeLabel(
		overview,
		"",
		220,
		13,
		false
	)

---------------------------------------------------------------------
-- ORIGIN
---------------------------------------------------------------------

local originPage =
	makePage(
		"Origin"
	)

local originState =
	makeLabel(
		originPage,
		"",
		170,
		13,
		false
	)

makeLabel(
	originPage,
	"VILLAGE",
	22,
	12,
	true
)

local villages = {
	"Leaf",
	"Sand",
	"Mist",
	"Cloud",
	"Stone",
}

for startIndex = 1, #villages, 3 do
	local row =
		makeRow(
			originPage
		)

	for offset = 0, 2 do
		local villageId =
			villages[
		startIndex
			+ offset
		]

		if villageId then
			makeButton(
				row,
				villageId,
				1 / 3,
				function()
					invokeOrigin(
						"SetVillage",
						{
							VillageId =
								villageId,
						}
					)
				end
			)
		end
	end
end

makeLabel(
	originPage,
	"CLAN",
	22,
	12,
	true
)

for startIndex = 1,
	#ClanDefinitions.Order,
	4 do

	local row =
		makeRow(
			originPage
		)

	for offset = 0, 3 do
		local clanId =
			ClanDefinitions.Order[
		startIndex
			+ offset
		]

		if clanId then
			local definition =
				ClanDefinitions.Get(
					clanId
				)

			makeButton(
				row,
				definition
					and definition.DisplayName
					or clanId,
				0.25,
				function()
					invokeOrigin(
						"SetClan",
						{
							ClanId =
								clanId,
						}
					)
				end
			)
		end
	end
end

local clanRandomRow =
	makeRow(
		originPage
	)

makeButton(
	clanRandomRow,
	"Random Clan",
	1,
	function()
		invokeOrigin(
			"RandomizeClan"
		)
	end
)

makeLabel(
	originPage,
	"KG POTENTIAL",
	22,
	12,
	true
)

local kgPotentialRow =
	makeRow(
		originPage
	)

makeButton(
	kgPotentialRow,
	"Reroll",
	1 / 3,
	function()
		invokeOrigin(
			"RerollKGPotential"
		)
	end
)

makeButton(
	kgPotentialRow,
	"Force YES",
	1 / 3,
	function()
		invokeOrigin(
			"ForceKGPotential",
			{
				Qualified =
					true,
			}
		)
	end
)

makeButton(
	kgPotentialRow,
	"Force NO",
	1 / 3,
	function()
		invokeOrigin(
			"ForceKGPotential",
			{
				Qualified =
					false,
			}
		)
	end
)

makeLabel(
	originPage,
	"NATURES",
	22,
	12,
	true
)

local natureRowA =
	makeRow(originPage)

makeButton(
	natureRowA,
	"Primary N1",
	0.5,
	function()
		invokeOrigin(
			"SetPrimaryNature",
			{
				NatureId =
					player:GetAttribute(
						"Nature1Id"
					),
			}
		)
	end
)

makeButton(
	natureRowA,
	"Primary N2",
	0.5,
	function()
		invokeOrigin(
			"SetPrimaryNature",
			{
				NatureId =
					player:GetAttribute(
						"Nature2Id"
					),
			}
		)
	end
)

local natureRowB =
	makeRow(originPage)

makeButton(
	natureRowB,
	"Unlock N2",
	0.5,
	function()
		invokeOrigin(
			"UnlockNature",
			{
				NatureId =
					player:GetAttribute(
						"Nature2Id"
					),
			}
		)
	end
)

makeButton(
	natureRowB,
	"Unlock N3",
	0.5,
	function()
		local n3 =
			player:GetAttribute(
				"Nature3Id"
			)

		if not n3 then
			setFeedback(
				"No Nature3 on this character"
			)

			return
		end

		invokeOrigin(
			"UnlockNature",
			{
				NatureId =
					n3,
			}
		)
	end
)

local originActionsA =
	makeRow(originPage)

makeButton(
	originActionsA,
	"Regenerate Genetics",
	1,
	function()
		invokeOrigin(
			"RegenerateGenetics"
		)
	end
)

local originActionsB =
	makeRow(originPage)

makeButton(
	originActionsB,
	"Toggle Rogue",
	0.5,
	function()
		invokeOrigin(
			"SetRogue",
			{
				IsRogue =
					player:GetAttribute(
						"IsRogue"
					) ~= true,
			}
		)
	end
)

makeButton(
	originActionsB,
	"Save Origin",
	0.5,
	function()
		invokeOrigin(
			"Save"
		)
	end
)

---------------------------------------------------------------------
-- PROGRESSION
---------------------------------------------------------------------

local progressionPage =
	makePage(
		"Progression"
	)

local progressionState =
	makeLabel(
		progressionPage,
		"",
		74,
		13,
		false
	)

local levelRow =
	makeRow(progressionPage)

makeButton(
	levelRow,
	"-1 Level",
	0.5,
	function()
		local level =
			player:GetAttribute(
				"CharacterLevel"
			) or 1

		invokeProgression(
			"SetLevel",
			level - 1
		)
	end
)

makeButton(
	levelRow,
	"+1 Level",
	0.5,
	function()
		local level =
			player:GetAttribute(
				"CharacterLevel"
			) or 1

		invokeProgression(
			"SetLevel",
			level + 1
		)
	end
)

local xpRow =
	makeRow(progressionPage)

makeButton(
	xpRow,
	"+100 XP",
	0.5,
	function()
		invokeProgression(
			"AddXP",
			100
		)
	end
)

makeButton(
	xpRow,
	"+1000 XP",
	0.5,
	function()
		invokeProgression(
			"AddXP",
			1000
		)
	end
)

makeLabel(
	progressionPage,
	"LEVEL GATES",
	22,
	12,
	true
)

local gateRowA =
	makeRow(progressionPage)

for _, gate in ipairs({
	5,
	20,
	45,
	}) do
	makeButton(
		gateRowA,
		"Lv"
			.. tostring(gate),
		1 / 3,
		function()
			invokeProgression(
				"SetLevel",
				gate
			)
		end
	)
end

local gateRowB =
	makeRow(progressionPage)

for _, gate in ipairs({
	70,
	100,
	}) do
	makeButton(
		gateRowB,
		"Lv"
			.. tostring(gate),
		0.5,
		function()
			invokeProgression(
				"SetLevel",
				gate
			)
		end
	)
end

local customXPRow =
	makeRow(progressionPage)

local xpBox =
	makeBox(
		customXPRow,
		"XP amount",
		0.62
	)

makeButton(
	customXPRow,
	"Add XP",
	0.38,
	function()
		invokeProgression(
			"AddXP",
			tonumber(
				xpBox.Text
			)
		)
	end
)

local customLevelRow =
	makeRow(progressionPage)

local levelBox =
	makeBox(
		customLevelRow,
		"Level 1-100",
		0.62
	)

makeButton(
	customLevelRow,
	"Set Level",
	0.38,
	function()
		invokeProgression(
			"SetLevel",
			tonumber(
				levelBox.Text
			)
		)
	end
)

local resetRow =
	makeRow(progressionPage)

makeButton(
	resetRow,
	"RESET TO Lv1",
	1,
	function()
		invokeProgression(
			"Reset"
		)
	end
)

---------------------------------------------------------------------
-- NINJA RANK
---------------------------------------------------------------------

local rankPage =
	makePage(
		"Rank"
	)

local rankState =
	makeLabel(
		rankPage,
		"",
		90,
		13,
		false
	)

local rankRowA =
	makeRow(rankPage)

makeButton(
	rankRowA,
	"Academy",
	0.5,
	function()
		invokeRank(
			"SetRank",
			"AcademyStudent"
		)
	end
)

makeButton(
	rankRowA,
	"Genin",
	0.5,
	function()
		invokeRank(
			"SetRank",
			"Genin"
		)
	end
)

local rankRowB =
	makeRow(rankPage)

makeButton(
	rankRowB,
	"Chūnin",
	0.5,
	function()
		invokeRank(
			"SetRank",
			"Chunin"
		)
	end
)

makeButton(
	rankRowB,
	"Jōnin",
	0.5,
	function()
		invokeRank(
			"SetRank",
			"Jonin"
		)
	end
)

local rankPromote =
	makeRow(rankPage)

makeButton(
	rankPromote,
	"PROMOTE (CHECK LEVEL)",
	1,
	function()
		invokeRank(
			"Promote"
		)
	end
)

---------------------------------------------------------------------
-- STATUS EFFECTS
---------------------------------------------------------------------

local statusPage =
	makePage(
		"Status"
	)

local statusState =
	makeLabel(
		statusPage,
		"",
		120,
		13,
		false
	)

makeLabel(
	statusPage,
	"ELEMENTAL",
	22,
	12,
	true
)

local elementalStatuses = {
	"Burning",
	"Unsteady",
	"Charged",
	"Heavy",
	"Wet",
}

for startIndex = 1, #elementalStatuses, 3 do
	local row =
		makeRow(statusPage)

	for offset = 0, 2 do
		local effectId =
			elementalStatuses[
		startIndex
			+ offset
		]

		if effectId then
			makeButton(
				row,
				effectId,
				1 / 3,
				function()
					applyStatus(
						effectId
					)
				end
			)
		end
	end
end

makeLabel(
	statusPage,
	"GENERIC",
	22,
	12,
	true
)

local genericStatuses = {
	"Poison",
	"Bleed",
	"Slow",
	"Stun",
	"ChakraSuppression",
}

for startIndex = 1, #genericStatuses, 3 do
	local row =
		makeRow(statusPage)

	for offset = 0, 2 do
		local effectId =
			genericStatuses[
		startIndex
			+ offset
		]

		if effectId then
			makeButton(
				row,
				effectId,
				1 / 3,
				function()
					applyStatus(
						effectId
					)
				end
			)
		end
	end
end

local clearRow =
	makeRow(statusPage)

makeButton(
	clearRow,
	"CLEAR ALL STATUS EFFECTS",
	1,
	clearStatuses
)

---------------------------------------------------------------------
-- DEVELOPER
---------------------------------------------------------------------

local devPage =
	makePage(
		"Developer"
	)

local devState =
	makeLabel(
		devPage,
		"",
		190,
		13,
		false
	)

local bypassRow =
	makeRow(devPage)

makeButton(
	bypassRow,
	"Content Bypass ON",
	0.5,
	function()
		invokeDev(
			"SetContentBypass",
			true
		)
	end
)

makeButton(
	bypassRow,
	"Content Bypass OFF",
	0.5,
	function()
		invokeDev(
			"SetContentBypass",
			false
		)
	end
)

makeLabel(
	devPage,
	"Content Bypass ignores learned-technique, nature, village/origin and Rogue requirements. It does NOT bypass chakra, cooldown, stun, combat-state or server-authority checks.",
	90,
	12,
	false
)

makeLabel(
	devPage,
	"CHARACTER LIFECYCLE FOUNDATION",
	22,
	12,
	true
)

local lifecycleRow =
	makeRow(
		devPage
	)

makeButton(
	lifecycleRow,
	"Simulate New Life",
	1,
	function()
		invokeLifecycle(
			"SimulateNewLife",
			{
				Reason =
					"DeveloperSimulation",
			}
		)
	end
)

makeLabel(
	devPage,
	"Current New Life rule: reroll Natural KG Potential only. Clan, natures, level, rank, learned techniques, village, affiliation, Rogue state, inventory and all other data are preserved. No Life Force or real final wipe exists yet.",
	105,
	12,
	false
)

makeLabel(
	devPage,
	"INVENTORY QA",
	22,
	12,
	true
)

makeLabel(
	devPage,
	"Inventory starts empty and persists by Character Slot. Use these controls instead of forced QA quantities. Throwable grants still respect equipped Ninja Bag capacity.",
	72,
	12,
	false
)

local inventoryManualRow =
	makeRow(
		devPage
	)

local inventoryItemBox =
	makeBox(
		inventoryManualRow,
		"ItemId",
		0.40
	)

local inventoryAmountBox =
	makeBox(
		inventoryManualRow,
		"Amount",
		0.18
	)

inventoryAmountBox.Text =
	"1"

makeButton(
	inventoryManualRow,
	"ADD",
	0.21,
	function()
		local amount =
			tonumber(
				inventoryAmountBox.Text
			)

		if not amount then
			setFeedback(
				"Inventory: invalid amount"
			)
			return
		end

		invokeInventoryDev(
			"AddItem",
			{
				ItemId =
					inventoryItemBox.Text,

				Amount =
					amount,
			}
		)
	end
)

makeButton(
	inventoryManualRow,
	"SET",
	0.21,
	function()
		local amount =
			tonumber(
				inventoryAmountBox.Text
			)

		if not amount then
			setFeedback(
				"Inventory: invalid amount"
			)
			return
		end

		invokeInventoryDev(
			"SetItem",
			{
				ItemId =
					inventoryItemBox.Text,

				Amount =
					amount,
			}
		)
	end
)

local inventoryItems =
	InventoryCatalog.GetAllItems()

for startIndex = 1,
	#inventoryItems,
	2 do

	local row =
		makeRow(
			devPage
		)

	for offset = 0, 1 do
		local item =
			inventoryItems[
		startIndex
			+ offset
		]

		if item then
			local grantAmount =
				item.NinjaBagEquippable
				and 5
				or 1

			makeButton(
				row,
				"+"
					.. tostring(
						grantAmount
					)
					.. " "
					.. tostring(
						item.DisplayName
						or item.Id
					),
				0.5,
				function()
					invokeInventoryDev(
						"AddItem",
						{
							ItemId =
								item.Id,

							Amount =
								grantAmount,
						}
					)
				end
			)
		end
	end
end

local inventorySaveRow =
	makeRow(
		devPage
	)

makeButton(
	inventorySaveRow,
	"SAVE INVENTORY NOW",
	1,
	function()
		invokeInventoryDev(
			"Save"
		)
	end
)

---------------------------------------------------------------------
-- REFRESH
---------------------------------------------------------------------

local function getUnlockedNatures(): string
	local unlocked = {}

	for _, natureId in ipairs({
		"Fire",
		"Wind",
		"Lightning",
		"Earth",
		"Water",
		}) do
		if player:GetAttribute(
			"NatureUnlocked_"
				.. natureId
			) == true then

			table.insert(
				unlocked,
				natureId
			)
		end
	end

	if #unlocked == 0 then
		return "none"
	end

	return table.concat(
		unlocked,
		", "
	)
end

local function statusOn(
	name: string
): string
	return player:GetAttribute(
		"Status_"
			.. name
	) == true
		and "ON"
		or "-"
end

local function refresh()
	local level =
		player:GetAttribute(
			"CharacterLevel"
		) or 1

	local totalXP =
		player:GetAttribute(
			"CharacterTotalXP"
		) or 0

	local rank =
		player:GetAttribute(
			"NinjaRankDisplayName"
		)
		or player:GetAttribute(
			"NinjaRank"
		)
		or "Loading"

	local n1 =
		player:GetAttribute(
			"Nature1Id"
		)

	local n2 =
		player:GetAttribute(
			"Nature2Id"
		)

	local n3 =
		player:GetAttribute(
			"Nature3Id"
		)

	local originVillage =
		player:GetAttribute(
			"OriginVillageId"
		)

	local affiliation =
		player:GetAttribute(
			"AffiliationVillageId"
		)

	local rogue =
		player:GetAttribute(
			"IsRogue"
		) == true

	local clanId =
		player:GetAttribute(
			"ClanId"
		)

	local clanDisplay =
		player:GetAttribute(
			"ClanDisplayName"
		)
		or clanId
		or "Loading"

	local kgRoll =
		player:GetAttribute(
			"NaturalKGPotentialRoll"
		)

	local kgChance =
		player:GetAttribute(
			"NaturalKGPotentialChance"
		) or 0.33

	local kgQualified =
		player:GetAttribute(
			"NaturalKGPotentialQualified"
		) == true

	local kgEligible =
		player:GetAttribute(
			"NaturalKGEligible"
		) == true

	local kgAvailable =
		player:GetAttribute(
			"NaturalKGAvailable"
		) == true

	local kgId =
		player:GetAttribute(
			"NaturalKGId"
		)

	local bypass =
		player:GetAttribute(
			"DevContentBypassEnabled"
		) == true

	overviewState.Text =
		("Level: %d | XP: %d | Rank: %s\n")
		:format(
			level,
			totalXP,
			tostring(rank)
		)
		.. "Origin Village: "
		.. tostring(originVillage)
		.. " | Affiliation: "
		.. tostring(affiliation)
		.. " | Rogue: "
		.. tostring(rogue)
		.. "\nClan: "
		.. tostring(clanDisplay)
		.. " | KG Potential: "
		.. (
			kgQualified
			and "YES"
			or "NO"
		)
		.. " | KG Available: "
		.. tostring(kgAvailable)
		.. "\nNatures: "
		.. tostring(n1)
		.. " + "
		.. tostring(n2)
		.. (
			n3
			and (
				" + "
				.. tostring(n3)
			)
			or ""
		)
		.. "\nPrimary: "
		.. tostring(
			player:GetAttribute(
				"PrimaryNatureId"
			)
		)
		.. " | Unlocked: "
		.. getUnlockedNatures()
		.. "\nDev Content Bypass: "
		.. tostring(bypass)
		.. " | Learned Techniques: "
		.. tostring(
			player:GetAttribute(
				"TechniqueLearnedCount"
			) or 0
		)
		.. "\nElemental Status: Burning="
		.. statusOn("Burning")
		.. " Unsteady="
		.. statusOn("Unsteady")
		.. " Charged="
		.. statusOn("Charged")
		.. " Heavy="
		.. statusOn("Heavy")
		.. " Wet="
		.. statusOn("Wet")

	originState.Text =
		"Origin Village: "
		.. tostring(originVillage)
		.. " | Affiliation: "
		.. tostring(affiliation)
		.. " | Rogue: "
		.. tostring(rogue)
		.. "\nClan: "
		.. tostring(clanDisplay)
		.. " ["
		.. tostring(clanId)
		.. "]"
		.. "\nKG Potential: "
		.. (
			kgQualified
			and "QUALIFIED"
			or "NOT QUALIFIED"
		)
		.. " | Roll: "
		.. (
			typeof(kgRoll) == "number"
			and string.format(
				"%.4f",
				kgRoll
			)
			or "?"
		)
		.. " < "
		.. string.format(
			"%.2f",
			kgChance
		)
		.. "\nKG Eligible: "
		.. tostring(kgEligible)
		.. " | Available: "
		.. tostring(kgAvailable)
		.. " | KG Id: "
		.. tostring(kgId)
		.. "\nNatures: "
		.. tostring(n1)
		.. " + "
		.. tostring(n2)
		.. (
			n3
			and (
				" + "
				.. tostring(n3)
			)
			or ""
		)
		.. "\nPrimary: "
		.. tostring(
			player:GetAttribute(
				"PrimaryNatureId"
			)
		)
		.. " | Unlocked: "
		.. getUnlockedNatures()

	local into =
		player:GetAttribute(
			"CharacterXPIntoLevel"
		) or 0

	local required =
		player:GetAttribute(
			"CharacterXPRequired"
		) or 0

	progressionState.Text =
		("Level %d | TotalXP %d\nCurrent Level XP: %d / %d")
		:format(
			level,
			totalXP,
			into,
			required
		)

	local nextRank =
		player:GetAttribute(
			"NinjaRankNextDisplayName"
		)

	local nextRequired =
		player:GetAttribute(
			"NinjaRankNextRequiredLevel"
		)

	local eligible =
		player:GetAttribute(
			"NinjaRankEligibleForPromotion"
		) == true

	rankState.Text =
		"Rank: "
		.. tostring(rank)
		.. " | Level: "
		.. tostring(level)
		.. "\nNext: "
		.. tostring(nextRank)
		.. " @ Lv"
		.. tostring(nextRequired)
		.. " | Eligible: "
		.. tostring(eligible)
		.. " | Persistent: "
		.. tostring(
			player:GetAttribute(
				"NinjaRankPersistent"
			) == true
		)

	statusState.Text =
		"Burning: "
		.. statusOn("Burning")
		.. " | Unsteady: "
		.. statusOn("Unsteady")
		.. " | Charged: "
		.. statusOn("Charged")
		.. "\nHeavy: "
		.. statusOn("Heavy")
		.. " | Wet: "
		.. statusOn("Wet")
		.. "\nKB Received x"
		.. tostring(
			player.Character
			and player.Character:GetAttribute(
				"Status_KnockbackReceivedMultiplier"
			)
			or 1
		)
		.. " | Guard Pressure x"
		.. tostring(
			player.Character
			and player.Character:GetAttribute(
				"Status_GuardPressureTakenMultiplier"
			)
			or 1
		)
		.. "\nDash x"
		.. tostring(
			player.Character
			and player.Character:GetAttribute(
				"Status_DashDistanceMultiplier"
			)
			or 1
		)
		.. " | Jump x"
		.. tostring(
			player.Character
			and player.Character:GetAttribute(
				"Status_JumpMultiplier"
			)
			or 1
		)
		.. " | Air x"
		.. tostring(
			player.Character
			and player.Character:GetAttribute(
				"Status_AirControlMultiplier"
			)
			or 1
		)

	local activeSlotId =
		player:GetAttribute(
			"CharacterSlotId"
		)
		or player:GetAttribute(
			"CharacterActiveSlotId"
		)
		or "1"

	devState.Text =
		"Is Developer: "
		.. tostring(
			player:GetAttribute(
				"IsWaylessDeveloper"
			) == true
		)
		.. "\nContent Bypass: "
		.. tostring(bypass)
		.. "\nActive Slot: "
		.. tostring(activeSlotId)
		.. " | Slot Mode: "
		.. tostring(
			player:GetAttribute(
				"CharacterSlotContextMode"
			)
			or "Loading"
		)
		.. "\nLifecycle Ready: "
		.. tostring(
			player:GetAttribute(
				"CharacterLifecycleReady"
			) == true
		)
		.. " | Transition Serial: "
		.. tostring(
			player:GetAttribute(
				"CharacterLifecycleTransitionSerial"
			) or 0
		)
		.. "\nLast Lifecycle Action: "
		.. tostring(
			player:GetAttribute(
				"CharacterLifecycleLastAction"
			)
			or "None"
		)
		.. "\nInventory Persistence: "
		.. tostring(
			player:GetAttribute(
				"InventoryPersistenceReady"
			) == true
		)
		.. " | Dirty: "
		.. tostring(
			player:GetAttribute(
				"InventoryPersistenceDirty"
			) == true
		)
		.. "\nTechnique Learning Ready: "
		.. tostring(
			player:GetAttribute(
				"TechniqueLearningReady"
			) == true
		)
		.. " | Known: "
		.. tostring(
			player:GetAttribute(
				"TechniqueLearnedCount"
			) or 0
		)
end

---------------------------------------------------------------------
-- TABS
---------------------------------------------------------------------

local TAB_ORDER = {
	"Overview",
	"Origin",
	"Progression",
	"Rank",
	"Status",
	"Developer",
}

local function showPage(
	name: string
)
	currentPage =
		name

	for pageName,
		page in pairs(
			pages
		) do

		page.Visible =
			pageName == name
	end

	for tabName,
		button in pairs(
			tabButtons
		) do

		button.Text =
			tabName == name
			and (
				"["
				.. tabName
				.. "]"
			)
			or tabName
	end

	refresh()
end

for _, name in ipairs(
	TAB_ORDER
	) do
	local button =
		Instance.new(
			"TextButton"
		)

	button.Size =
		UDim2.new(
			1 / #TAB_ORDER,
			-5,
			1,
			0
		)

	button.Text =
		name

	button.TextSize =
		11

	button.Font =
		Enum.Font.GothamMedium

	button.BorderSizePixel =
		0

	button.Parent =
		tabBar

	local corner =
		Instance.new(
			"UICorner"
		)

	corner.CornerRadius =
		UDim.new(0, 5)

	corner.Parent =
		button

	button.Activated:
		Connect(
			function()
				showPage(
					name
				)
			end
		)

	tabButtons[name] =
		button
end

---------------------------------------------------------------------
-- LIVE REFRESH
---------------------------------------------------------------------

local watchedAttributes = {
	"CharacterLevel",
	"CharacterTotalXP",
	"CharacterXPIntoLevel",
	"CharacterXPRequired",
	"NinjaRank",
	"NinjaRankDisplayName",
	"NinjaRankEligibleForPromotion",
	"NinjaRankNextDisplayName",
	"NinjaRankNextRequiredLevel",
	"NinjaRankPersistent",
	"OriginVillageId",
	"AffiliationVillageId",
	"IsRogue",
	"ClanId",
	"ClanDisplayName",
	"ClanArchetype",
	"NaturalKGPotentialRoll",
	"NaturalKGPotentialChance",
	"NaturalKGPotentialQualified",
	"NaturalKGEligible",
	"NaturalKGAvailable",
	"NaturalKGId",
	"Nature1Id",
	"Nature2Id",
	"Nature3Id",
	"PrimaryNatureId",
	"NatureUnlocked_Fire",
	"NatureUnlocked_Wind",
	"NatureUnlocked_Lightning",
	"NatureUnlocked_Earth",
	"NatureUnlocked_Water",
	"DevContentBypassEnabled",
	"IsWaylessDeveloper",
	"TechniqueLearningReady",
	"TechniqueLearnedCount",
	"CharacterSlotId",
	"CharacterActiveSlotId",
	"CharacterSlotContextReady",
	"CharacterSlotContextMode",
	"CharacterRealSlotSelectionEnabled",
	"CharacterLifecycleReady",
	"CharacterLifecyclePolicyVersion",
	"CharacterLifecycleActiveSlotId",
	"CharacterLifecycleTransitionSerial",
	"CharacterLifecycleLastAction",
	"CharacterLifecycleLastReason",
	"InventoryPersistenceReady",
	"InventoryPersistenceDirty",
	"InventoryPersistenceLoadFailed",
	"InventoryPersistenceSlotId",
}

for _, attributeName in ipairs(
	watchedAttributes
	) do
	player:
		GetAttributeChangedSignal(
			attributeName
		):
		Connect(
			refresh
		)
end

local characterConnections: {RBXScriptConnection} = {}

local function bindCharacter(
	character: Model?
)
	for _, connection in ipairs(
		characterConnections
		) do
		connection:Disconnect()
	end

	table.clear(
		characterConnections
	)

	if not character then
		refresh()
		return
	end

	for _, attributeName in ipairs({
		"Status_Burning",
		"Status_Unsteady",
		"Status_Charged",
		"Status_Heavy",
		"Status_Wet",
		"Status_KnockbackReceivedMultiplier",
		"Status_GuardPressureTakenMultiplier",
		"Status_DashDistanceMultiplier",
		"Status_JumpMultiplier",
		"Status_AirControlMultiplier",
		}) do
		table.insert(
			characterConnections,
			character:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(
					refresh
				)
		)
	end

	refresh()
end

player.CharacterAdded:
	Connect(
		bindCharacter
	)

bindCharacter(
	player.Character
)

---------------------------------------------------------------------
-- TOGGLE
---------------------------------------------------------------------

local menuOpen =
	false

local function setMenuOpen(
	isOpen: boolean
)
	menuOpen =
		isOpen

	panel.Visible =
		isOpen

	if isOpen then
		showPage(
			currentPage
		)
	end

	print(
		"[WAYLESSDevMenu] TOGGLE",
		isOpen
			and "OPEN"
			or "CLOSED"
	)
end

local function toggleMenu()
	setMenuOpen(
		not menuOpen
	)
end

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			_gameProcessed: boolean
		)
			-- Studio can mark function keys as processed.
			-- For the dev-menu toggle we intentionally do not reject
			-- the input based on gameProcessed.
			if UserInputService:
				GetFocusedTextBox() then

				return
			end

			if input.KeyCode
				== Enum.KeyCode.F7
				or input.KeyCode
				== Enum.KeyCode.RightShift then

				toggleMenu()
			end
		end
	)

setMenuOpen(false)

showPage(
	"Overview"
)

print(
	"[WAYLESSDevMenu] READY v1.4 InventoryPersistence"
		.. " | Toggle=F7+RightShift"
		.. " | Tabs=Overview+Origin+Progression+Rank+Status+Developer"
		.. " | Clans=8"
		.. " | KGPotential=ON"
		.. " | SlotContext=FallbackSingleSlot"
		.. " | NewLifeSimulation=ON"
		.. " | InventoryDevTools=ON"
		.. " | UnifiedOldMenus=OFF"
)
