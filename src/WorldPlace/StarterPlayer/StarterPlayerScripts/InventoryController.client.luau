--!strict
-- StarterPlayer > StarterPlayerScripts > InventoryController
--
-- WAYLESS Shinobi Menu v5 - Split inventory / techniques / loadout
--
-- Toggle: M
--
-- Active:
--   Character
--   Techniques / Unlock
--   Technique Loadout (10 slots)
--
-- Inventory / Ninja Bag / Equipment now live in the dedicated TAB inventory HUD.
-- Dev Menu remains F7 and is completely separate.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local UserInputService =
	game:GetService(
		"UserInputService"
	)

local TweenService =
	game:GetService(
		"TweenService"
	)

local player =
	Players.LocalPlayer

local playerGui =
	player:WaitForChild(
		"PlayerGui"
	)

local InventoryCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"InventoryCatalog"
		)
	)

local equipmentRemotes =
	ReplicatedStorage:
	WaitForChild(
		"EquipmentRemotes"
	)

local equipmentEquipRequest =
	equipmentRemotes:
	WaitForChild(
		"EquipRequest"
	) :: RemoteEvent

local equipmentEquipResult =
	equipmentRemotes:
	WaitForChild(
		"EquipResult"
	) :: RemoteEvent

local ninjaBagRemotes =
	ReplicatedStorage:
	WaitForChild(
		"NinjaBagRemotes"
	)

local ninjaEquipRequest =
	ninjaBagRemotes:
	WaitForChild(
		"EquipRequest"
	) :: RemoteEvent

local ninjaEquipResult =
	ninjaBagRemotes:
	WaitForChild(
		"EquipResult"
	) :: RemoteEvent

local request =
	ReplicatedStorage:
	WaitForChild(
		"ShinobiMenuSystem"
	):
	WaitForChild(
		"Remotes"
	):
	WaitForChild(
		"Request"
	) :: RemoteFunction

local TOGGLE_KEY =
	Enum.KeyCode.M

local TAB_ORDER = {
	"Character",
	"Techniques",
	"Loadout",
}

local NATURE_FILTERS = {
	"All",
	"Fire",
	"Wind",
	"Lightning",
	"Earth",
	"Water",
	"Other",
}

local existing =
	playerGui:
	FindFirstChild(
		"WAYLESSShinobiMenu"
	)

if existing then
	existing:Destroy()
end

---------------------------------------------------------------------
-- THEME
---------------------------------------------------------------------

local C = {
	Backdrop =
		Color3.fromRGB(
			8,
			10,
			14
		),

	Panel =
		Color3.fromRGB(
			20,
			23,
			30
		),

	Panel2 =
		Color3.fromRGB(
			27,
			31,
			40
		),

	Panel3 =
		Color3.fromRGB(
			34,
			39,
			49
		),

	Text =
		Color3.fromRGB(
			236,
			238,
			242
		),

	SubText =
		Color3.fromRGB(
			156,
			163,
			176
		),

	Accent =
		Color3.fromRGB(
			194,
			64,
			64
		),

	AccentSoft =
		Color3.fromRGB(
			89,
			43,
			47
		),

	Good =
		Color3.fromRGB(
			67,
			156,
			103
		),

	Warn =
		Color3.fromRGB(
			190,
			142,
			54
		),

	Bad =
		Color3.fromRGB(
			168,
			69,
			69
		),

	Border =
		Color3.fromRGB(
			57,
			63,
			76
		),
}

local function corner(
	parent: Instance,
	radius: number
)
	local item =
		Instance.new(
			"UICorner"
		)

	item.CornerRadius =
		UDim.new(
			0,
			radius
		)

	item.Parent =
		parent
end

local function stroke(
	parent: Instance,
	transparency: number?
)
	local item =
		Instance.new(
			"UIStroke"
		)

	item.Color =
		C.Border

	item.Transparency =
		transparency
		or 0.25

	item.Thickness =
		1

	item.Parent =
		parent
end

local function padding(
	parent: Instance,
	value: number
)
	local item =
		Instance.new(
			"UIPadding"
		)

	item.PaddingTop =
		UDim.new(
			0,
			value
		)

	item.PaddingBottom =
		UDim.new(
			0,
			value
		)

	item.PaddingLeft =
		UDim.new(
			0,
			value
		)

	item.PaddingRight =
		UDim.new(
			0,
			value
		)

	item.Parent =
		parent
end

local function makeText(
	parent: Instance,
	text: string,
	size: number,
	bold: boolean?
): TextLabel
	local label =
		Instance.new(
			"TextLabel"
		)

	label.BackgroundTransparency =
		1

	label.Text =
		text

	label.TextColor3 =
		C.Text

	label.TextSize =
		size

	label.Font =
		bold
		and Enum.Font.GothamBold
		or Enum.Font.Gotham

	label.TextXAlignment =
		Enum.TextXAlignment.Left

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	label.Parent =
		parent

	return label
end

local function makeButton(
	parent: Instance,
	text: string
): TextButton
	local button =
		Instance.new(
			"TextButton"
		)

	button.AutoButtonColor =
		false

	button.BackgroundColor3 =
		C.Panel3

	button.Text =
		text

	button.TextColor3 =
		C.Text

	button.TextSize =
		14

	button.Font =
		Enum.Font.GothamSemibold

	button.Parent =
		parent

	corner(
		button,
		8
	)

	stroke(
		button,
		0.45
	)

	button.MouseEnter:
		Connect(
			function()
				TweenService:
				Create(
					button,
					TweenInfo.new(
						0.12
					),
					{
						BackgroundColor3 =
						C.AccentSoft,
					}
				):
				Play()
			end
		)

	button.MouseLeave:
		Connect(
			function()
				TweenService:
				Create(
					button,
					TweenInfo.new(
						0.12
					),
					{
						BackgroundColor3 =
						C.Panel3,
					}
				):
				Play()
			end
		)

	return button
end

---------------------------------------------------------------------
-- PLAYER / INVENTORY STATE HELPERS
---------------------------------------------------------------------

local function amountAttr(
	itemId: string
): string
	return "InventoryAmount_"
		.. itemId
end

local function equippedAttr(
	slotId: string
): string
	return "Equipped"
		.. slotId
end

local function quickSlotAttr(
	slotIndex: number
): string
	return "NinjaBagSlot"
		.. tostring(
			slotIndex
		)
		.. "Projectile"
end

local function getAmount(
	itemId: string
): number
	local value =
		player:GetAttribute(
			amountAttr(
				itemId
			)
		)

	if typeof(value) ~=
		"number" then

		return 0
	end

	return math.max(
		0,
		math.floor(
			value
		)
	)
end

local function getMaxAmount(
	itemId: string,
	fallback: number?
): number
	local value =
		player:GetAttribute(
			"InventoryMax_"
			.. itemId
		)

	if typeof(value) ==
		"number" then

		return math.max(
			0,
			math.floor(
				value
			)
		)
	end

	return math.max(
		0,
		math.floor(
			fallback
				or 0
		)
	)
end

local function getEquipped(
	slotId: string
): string?
	local value =
		player:GetAttribute(
			equippedAttr(
				slotId
			)
		)

	if typeof(value) ~=
		"string"
		or value == "" then

		return nil
	end

	return value
end

local function getQuickSlot(
	slotIndex: number
): string?
	local value =
		player:GetAttribute(
			quickSlotAttr(
				slotIndex
			)
		)

	if typeof(value) ~=
		"string"
		or value == "" then

		return nil
	end

	return value
end

local function getHardBlockReason(): string?
	local character =
		player.Character

	if not character then
		return "No character"
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return "Character unavailable"
	end

	if character:GetAttribute(
		"DownedActionLocked"
		) == true
			or character:GetAttribute(
				"IsDowned"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true
			or character:GetAttribute(
				"IsCarrying"
			) == true
			or character:GetAttribute(
				"IsExecuting"
			) == true then

		return "Character action locked"
	end

	return nil
end

local function isReadOnly(): boolean
	local character =
		player.Character

	return character ~= nil
		and character:GetAttribute(
			"CombatTagged"
		) == true
end

local function inventoryMutationsReady(): boolean
	return player:GetAttribute(
		"InventoryPersistenceReady"
	) == true
		and not isReadOnly()
end

local function itemDisplayName(
	itemId: string?
): string
	if not itemId then
		return "Empty"
	end

	local item =
		InventoryCatalog.GetItem(
			itemId
		)

	return item
		and tostring(
			item.DisplayName
			or item.Id
		)
		or itemId
end

---------------------------------------------------------------------
-- ROOT
---------------------------------------------------------------------

local gui =
	Instance.new(
		"ScreenGui"
	)

gui.Name =
	"WAYLESSShinobiMenu"

gui.ResetOnSpawn =
	false

gui.IgnoreGuiInset =
	false

gui.DisplayOrder =
	40

gui.Enabled =
	false

gui.Parent =
	playerGui

local dim =
	Instance.new(
		"Frame"
	)

dim.Name =
	"Dim"

dim.BackgroundColor3 =
	Color3.new(
		0,
		0,
		0
	)

dim.BackgroundTransparency =
	0.35

dim.Size =
	UDim2.fromScale(
		1,
		1
	)

dim.Parent =
	gui

local main =
	Instance.new(
		"Frame"
	)

main.Name =
	"Main"

main.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

main.Position =
	UDim2.fromScale(
		0.5,
		0.5
	)

main.Size =
	UDim2.fromScale(
		0.82,
		0.80
	)

main.BackgroundColor3 =
	C.Backdrop

main.Parent =
	gui

corner(
	main,
	12
)

stroke(
	main,
	0.05
)

local sizeConstraint =
	Instance.new(
		"UISizeConstraint"
	)

sizeConstraint.MinSize =
	Vector2.new(
		760,
		500
	)

sizeConstraint.MaxSize =
	Vector2.new(
		1220,
		780
	)

sizeConstraint.Parent =
	main

---------------------------------------------------------------------
-- HEADER
---------------------------------------------------------------------

local header =
	Instance.new(
		"Frame"
	)

header.Name =
	"Header"

header.BackgroundColor3 =
	C.Panel

header.Size =
	UDim2.new(
		1,
		0,
		0,
		68
	)

header.Parent =
	main

corner(
	header,
	12
)

local headerMask =
	Instance.new(
		"Frame"
	)

headerMask.BackgroundColor3 =
	C.Panel

headerMask.BorderSizePixel =
	0

headerMask.Position =
	UDim2.new(
		0,
		0,
		1,
		-12
	)

headerMask.Size =
	UDim2.new(
		1,
		0,
		0,
		12
	)

headerMask.Parent =
	header

local title =
	makeText(
		header,
		"SHINOBI MENU",
		22,
		true
	)

title.Position =
	UDim2.new(
		0,
		22,
		0,
		7
	)

title.Size =
	UDim2.new(
		0.6,
		0,
		0,
		28
	)

local subtitle =
	makeText(
		header,
		"Character • Techniques • Loadout",
		12,
		false
	)

subtitle.TextColor3 =
	C.SubText

subtitle.Position =
	UDim2.new(
		0,
		22,
		0,
		35
	)

subtitle.Size =
	UDim2.new(
		0.75,
		0,
		0,
		22
	)

local close =
	makeButton(
		header,
		"×"
	)

close.AnchorPoint =
	Vector2.new(
		1,
		0.5
	)

close.Position =
	UDim2.new(
		1,
		-18,
		0.5,
		0
	)

close.Size =
	UDim2.fromOffset(
		38,
		38
	)

close.TextSize =
	22

---------------------------------------------------------------------
-- NAV
---------------------------------------------------------------------

local nav =
	Instance.new(
		"Frame"
	)

nav.Name =
	"Navigation"

nav.BackgroundColor3 =
	C.Panel

nav.Position =
	UDim2.new(
		0,
		0,
		0,
		69
	)

nav.Size =
	UDim2.new(
		0,
		190,
		1,
		-69
	)

nav.Parent =
	main

padding(
	nav,
	14
)

local navList =
	Instance.new(
		"UIListLayout"
	)

navList.FillDirection =
	Enum.FillDirection.Vertical

navList.Padding =
	UDim.new(
		0,
		8
	)

navList.SortOrder =
	Enum.SortOrder.LayoutOrder

navList.Parent =
	nav

local navButtons: {[string]: TextButton} =
	{}

---------------------------------------------------------------------
-- CONTENT
---------------------------------------------------------------------

local content =
	Instance.new(
		"Frame"
	)

content.Name =
	"Content"

content.BackgroundTransparency =
	1

content.Position =
	UDim2.new(
		0,
		191,
		0,
		69
	)

content.Size =
	UDim2.new(
		1,
		-191,
		1,
		-69
	)

content.ClipsDescendants =
	true

content.Parent =
	main

local pages: {[string]: Frame} =
	{}

local activeTab =
	"Character"

local activeNatureFilter =
	"All"

local lastTechniqueSnapshot: any =
	nil

local refreshLoadout: (() -> ())? =
	nil

local openTechniquePicker: ((
	number
	) -> ())? =
	nil

local previousMouseBehavior =
	UserInputService.MouseBehavior

local previousMouseIconEnabled =
	UserInputService.MouseIconEnabled

local isOpen =
	false

local function makePage(
	name: string
): Frame
	local page =
		Instance.new(
			"Frame"
		)

	page.Name =
		name

	page.BackgroundTransparency =
		1

	page.Size =
		UDim2.fromScale(
			1,
			1
		)

	page.Visible =
		false

	page.Parent =
		content

	pages[name] =
		page

	return page
end

for _, tabName in ipairs(
	TAB_ORDER
	) do
	local button =
		makeButton(
			nav,
			tabName
		)

	button.Name =
		tabName
		.. "Button"

	button.Size =
		UDim2.new(
			1,
			0,
			0,
			44
		)

	navButtons[tabName] =
		button
end

local navHint =
	makeText(
		nav,
		"M  Close Menu",
		11,
		false
	)

navHint.TextColor3 =
	C.SubText

navHint.LayoutOrder =
	100

navHint.Size =
	UDim2.new(
		1,
		0,
		0,
		34
	)

---------------------------------------------------------------------
-- CHARACTER PAGE
---------------------------------------------------------------------

local characterPage =
	makePage(
		"Character"
	)

local characterHeader =
	makeText(
		characterPage,
		"CHARACTER",
		24,
		true
	)

characterHeader.Position =
	UDim2.fromOffset(
		28,
		22
	)

characterHeader.Size =
	UDim2.new(
		1,
		-56,
		0,
		34
	)

local characterSub =
	makeText(
		characterPage,
		"Your current shinobi profile.",
		13,
		false
	)

characterSub.TextColor3 =
	C.SubText

characterSub.Position =
	UDim2.fromOffset(
		28,
		56
	)

characterSub.Size =
	UDim2.new(
		1,
		-56,
		0,
		24
	)

local characterScroll =
	Instance.new(
		"ScrollingFrame"
	)

characterScroll.BackgroundTransparency =
	1

characterScroll.BorderSizePixel =
	0

characterScroll.Position =
	UDim2.fromOffset(
		28,
		94
	)

characterScroll.Size =
	UDim2.new(
		1,
		-56,
		1,
		-120
	)

characterScroll.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

characterScroll.CanvasSize =
	UDim2.new()

characterScroll.ScrollBarThickness =
	4

characterScroll.Parent =
	characterPage

local characterGrid =
	Instance.new(
		"UIGridLayout"
	)

characterGrid.CellPadding =
	UDim2.fromOffset(
		12,
		12
	)

characterGrid.CellSize =
	UDim2.new(
		0.5,
		-6,
		0,
		142
	)

characterGrid.SortOrder =
	Enum.SortOrder.LayoutOrder

characterGrid.Parent =
	characterScroll

local characterCards: {[string]: TextLabel} =
	{}

local function makeInfoCard(
	key: string,
	titleText: string,
	layoutOrder: number
)
	local card =
		Instance.new(
			"Frame"
		)

	card.BackgroundColor3 =
		C.Panel2

	card.LayoutOrder =
		layoutOrder

	card.Parent =
		characterScroll

	corner(
		card,
		10
	)

	stroke(
		card,
		0.55
	)

	local heading =
		makeText(
			card,
			titleText,
			12,
			true
		)

	heading.TextColor3 =
		C.SubText

	heading.Position =
		UDim2.fromOffset(
			16,
			10
		)

	heading.Size =
		UDim2.new(
			1,
			-32,
			0,
			22
		)

	local value =
		makeText(
			card,
			"",
			17,
			true
		)

	value.TextWrapped =
		true

	value.TextYAlignment =
		Enum.TextYAlignment.Top

	value.Position =
		UDim2.fromOffset(
			16,
			39
		)

	value.Size =
		UDim2.new(
			1,
			-32,
			1,
			-50
		)

	characterCards[key] =
		value
end

makeInfoCard(
	"Progression",
	"PROGRESSION",
	1
)

makeInfoCard(
	"Identity",
	"IDENTITY",
	2
)

makeInfoCard(
	"Village",
	"VILLAGE / AFFILIATION",
	3
)

makeInfoCard(
	"Natures",
	"CHAKRA NATURES",
	4
)

local function boolText(
	value: boolean
): string
	return value
		and "Yes"
		or "No"
end

local function getUnlockedNatures(): string
	local order = {
		"Fire",
		"Wind",
		"Lightning",
		"Earth",
		"Water",
	}

	local found = {}

	for _, natureId in ipairs(
		order
		) do
		if player:GetAttribute(
			"NatureUnlocked_"
				.. natureId
			) == true then

			table.insert(
				found,
				natureId
			)
		end
	end

	return #found > 0
		and table.concat(
			found,
			", "
		)
		or "None"
end

local function refreshCharacter()
	local level =
		player:GetAttribute(
			"CharacterLevel"
		) or 1

	local totalXP =
		player:GetAttribute(
			"CharacterTotalXP"
		) or 0

	local xpInto =
		player:GetAttribute(
			"CharacterXPIntoLevel"
		) or 0

	local xpRequired =
		player:GetAttribute(
			"CharacterXPRequired"
		) or 0

	local rank =
		player:GetAttribute(
			"NinjaRankDisplayName"
		)
		or player:GetAttribute(
			"NinjaRank"
		)
		or "Loading"

	characterCards.Progression.Text =
		"Level "
		.. tostring(level)
		.. "\n"
		.. tostring(xpInto)
		.. " / "
		.. tostring(xpRequired)
		.. " XP to next level"
		.. "\nTotal XP: "
		.. tostring(totalXP)
		.. "\nRank: "
		.. tostring(rank)

	local clan =
		player:GetAttribute(
			"ClanDisplayName"
		)
		or player:GetAttribute(
			"ClanId"
		)
		or "Loading"

	local kgAvailable =
		player:GetAttribute(
			"NaturalKGAvailable"
		) == true

	local kgId =
		player:GetAttribute(
			"NaturalKGId"
		)

	characterCards.Identity.Text =
		"Clan: "
		.. tostring(clan)
		.. "\nKG: "
		.. (
			kgAvailable
			and tostring(
				kgId
				or "Available"
			)
			or "None expressed"
		)
		.. "\nActive Slot: "
		.. tostring(
			player:GetAttribute(
				"CharacterSlotId"
			)
			or "1"
		)

	local origin =
		player:GetAttribute(
			"OriginVillageId"
		)
		or "Loading"

	local affiliation =
		player:GetAttribute(
			"AffiliationVillageId"
		)
		or "None"

	local rogue =
		player:GetAttribute(
			"IsRogue"
		) == true

	characterCards.Village.Text =
		"Origin: "
		.. tostring(origin)
		.. "\nAffiliation: "
		.. tostring(affiliation)
		.. "\nRogue: "
		.. boolText(
			rogue
		)

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

	local innate = {}

	if n1 then
		table.insert(
			innate,
			tostring(n1)
		)
	end

	if n2 then
		table.insert(
			innate,
			tostring(n2)
		)
	end

	if n3 then
		table.insert(
			innate,
			tostring(n3)
		)
	end

	characterCards.Natures.Text =
		"Innate: "
		.. (
			#innate > 0
			and table.concat(
				innate,
				", "
			)
			or "Loading"
		)
		.. "\nPrimary: "
		.. tostring(
			player:GetAttribute(
				"PrimaryNatureId"
			)
			or "Not chosen"
		)
		.. "\nUnlocked: "
		.. getUnlockedNatures()
end

---------------------------------------------------------------------
-- TECHNIQUES PAGE
---------------------------------------------------------------------

local techniquesPage =
	makePage(
		"Techniques"
	)

local techniquesHeader =
	makeText(
		techniquesPage,
		"TECHNIQUES",
		24,
		true
	)

techniquesHeader.Position =
	UDim2.fromOffset(
		28,
		22
	)

techniquesHeader.Size =
	UDim2.new(
		0.55,
		0,
		0,
		34
	)

local techniqueSummary =
	makeText(
		techniquesPage,
		"Loading techniques...",
		12,
		false
	)

techniqueSummary.TextColor3 =
	C.SubText

techniqueSummary.Position =
	UDim2.fromOffset(
		28,
		56
	)

techniqueSummary.Size =
	UDim2.new(
		0.6,
		0,
		0,
		24
	)

local refreshButton =
	makeButton(
		techniquesPage,
		"Refresh"
	)

refreshButton.AnchorPoint =
	Vector2.new(
		1,
		0
	)

refreshButton.Position =
	UDim2.new(
		1,
		-28,
		0,
		24
	)

refreshButton.Size =
	UDim2.fromOffset(
		92,
		34
	)

local filters =
	Instance.new(
		"Frame"
	)

filters.BackgroundTransparency =
	1

filters.Position =
	UDim2.fromOffset(
		28,
		88
	)

filters.Size =
	UDim2.new(
		1,
		-56,
		0,
		36
	)

filters.Parent =
	techniquesPage

local filterList =
	Instance.new(
		"UIListLayout"
	)

filterList.FillDirection =
	Enum.FillDirection.Horizontal

filterList.Padding =
	UDim.new(
		0,
		7
	)

filterList.SortOrder =
	Enum.SortOrder.LayoutOrder

filterList.Parent =
	filters

local filterButtons: {[string]: TextButton} =
	{}

for _, filterName in ipairs(
	NATURE_FILTERS
	) do
	local button =
		makeButton(
			filters,
			filterName
		)

	button.Size =
		UDim2.fromOffset(
			filterName == "Lightning"
			and 86
			or 72,
			32
		)

	button.TextSize =
		12

	filterButtons[filterName] =
		button
end

local techniqueScroll =
	Instance.new(
		"ScrollingFrame"
	)

techniqueScroll.BackgroundTransparency =
	1

techniqueScroll.BorderSizePixel =
	0

techniqueScroll.Position =
	UDim2.fromOffset(
		28,
		138
	)

techniqueScroll.Size =
	UDim2.new(
		1,
		-56,
		1,
		-168
	)

techniqueScroll.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

techniqueScroll.CanvasSize =
	UDim2.new()

techniqueScroll.ScrollBarThickness =
	5

techniqueScroll.Parent =
	techniquesPage

local techniqueList =
	Instance.new(
		"UIListLayout"
	)

techniqueList.Padding =
	UDim.new(
		0,
		10
	)

techniqueList.SortOrder =
	Enum.SortOrder.LayoutOrder

techniqueList.Parent =
	techniqueScroll

local emptyTechniques =
	makeText(
		techniqueScroll,
		"No techniques match this filter.",
		14,
		false
	)

emptyTechniques.TextColor3 =
	C.SubText

emptyTechniques.Size =
	UDim2.new(
		1,
		0,
		0,
		50
	)

emptyTechniques.Visible =
	false

local feedback =
	makeText(
		techniquesPage,
		"",
		12,
		false
	)

feedback.TextColor3 =
	C.SubText

feedback.AnchorPoint =
	Vector2.new(
		0,
		1
	)

feedback.Position =
	UDim2.new(
		0,
		28,
		1,
		-8
	)

feedback.Size =
	UDim2.new(
		1,
		-56,
		0,
		24
	)

local techniqueCards = {}

local function setFeedback(
	text: string,
	kind: string?
)
	feedback.Text =
		text

	if kind == "good" then
		feedback.TextColor3 =
			C.Good

	elseif kind == "bad" then
		feedback.TextColor3 =
			C.Bad

	else
		feedback.TextColor3 =
			C.SubText
	end
end

local reasonLabels = {
	LevelTooLow =
		"Level requirement not met",

	MissingUnlockedNature =
		"Required nature is locked",

	MissingAnyUnlockedNature =
		"Required nature is locked",

	WrongClan =
		"Clan requirement not met",

	MissingNaturalKG =
		"KG requirement not met",

	WrongNaturalKGPotential =
		"KG Potential requirement not met",

	MissingRequiredTechnique =
		"Previous technique required",

	WrongVillageAffiliation =
		"Affiliation requirement not met",

	WrongOriginVillage =
		"Origin requirement not met",

	WrongRogueStatus =
		"Rogue requirement not met",

	ProgressionNotReady =
		"Progression is still loading",

	OriginNotReady =
		"Character origin is still loading",

	TechniqueLearningNotReady =
		"Technique data is still loading",

	CombatTagged =
		"Read only while in combat",

	CharacterActionLocked =
		"Character action locked",

	DeveloperBypass =
		"Developer bypass",
}

local function clearTechniqueCards()
	for _, card in ipairs(
		techniqueCards
		) do
		card:Destroy()
	end

	table.clear(
		techniqueCards
	)
end

local function statusColor(
	status: string
): Color3
	if status ==
		"UNLOCKED" then

		return C.Good
	end

	if status ==
		"AVAILABLE" then

		return C.Warn
	end

	return C.Bad
end

local function requirementString(
	items: any
): string
	if typeof(items)
		~= "table"
		or #items == 0 then

		return "No additional requirements"
	end

	local pieces = {}

	for _, item in ipairs(
		items
		) do
		local marker =
			item.Met
			and "✓"
			or "×"

		table.insert(
			pieces,
			marker
				.. " "
				.. tostring(
					item.Label
				)
		)
	end

	return table.concat(
		pieces,
		"   "
	)
end

local function matchesFilter(
	technique: any
): boolean
	if activeNatureFilter ==
		"All" then

		return true
	end

	if activeNatureFilter ==
		"Other" then

		return technique.NatureId
			== nil
	end

	return technique.NatureId
		== activeNatureFilter
end

local refreshTechniques: (() -> ())? =
	nil

local function renderTechniqueSnapshot(
	snapshot: any
)
	clearTechniqueCards()

	lastTechniqueSnapshot =
		snapshot

	if typeof(snapshot)
		~= "table"
		or snapshot.Ok
		~= true then

		techniqueSummary.Text =
			"Technique data unavailable"

		emptyTechniques.Text =
			reasonLabels[
		typeof(snapshot) == "table"
			and snapshot.Reason
			or ""
		]
			or tostring(
				typeof(snapshot) == "table"
				and snapshot.Reason
				or "Request failed"
			)

		emptyTechniques.Visible =
			true

		return
	end

	techniqueSummary.Text =
		tostring(
			snapshot.LearnedCount
			or 0
		)
		.. " unlocked  •  "
		.. tostring(
			snapshot.RegisteredCount
			or 0
		)
		.. " registered"

	local visibleCount =
		0

	for _, technique in ipairs(
		snapshot.Techniques
			or {}
		) do
		if matchesFilter(
			technique
			) then

			visibleCount += 1

			local card =
				Instance.new(
					"Frame"
				)

			card.Name =
				tostring(
					technique.Id
				)

			card.BackgroundColor3 =
				C.Panel2

			card.Size =
				UDim2.new(
					1,
					-8,
					0,
					112
				)

			card.LayoutOrder =
				visibleCount

			card.Parent =
				techniqueScroll

			table.insert(
				techniqueCards,
				card
			)

			corner(
				card,
				10
			)

			stroke(
				card,
				0.55
			)

			local name =
				makeText(
					card,
					tostring(
						technique.DisplayName
					),
					16,
					true
				)

			name.Position =
				UDim2.fromOffset(
					16,
					10
				)

			name.Size =
				UDim2.new(
					1,
					-160,
					0,
					24
				)

			local meta =
				makeText(
					card,
					"Level "
					.. tostring(
						technique.MinimumLevel
						or 1
					)
					.. "  •  "
					.. tostring(
						technique.NatureId
						or technique.Category
						or "Technique"
					),
					12,
					false
				)

			meta.TextColor3 =
				C.SubText

			meta.Position =
				UDim2.fromOffset(
					16,
					36
				)

			meta.Size =
				UDim2.new(
					1,
					-170,
					0,
					20
				)

			local req =
				makeText(
					card,
					requirementString(
						technique.Requirements
					),
					11,
					false
				)

			req.TextColor3 =
				C.SubText

			req.TextWrapped =
				true

			req.Position =
				UDim2.fromOffset(
					16,
					61
				)

			req.Size =
				UDim2.new(
					1,
					-170,
					0,
					38
				)

			local status =
				makeText(
					card,
					tostring(
						technique.Status
					),
					11,
					true
				)

			status.TextColor3 =
				statusColor(
					tostring(
						technique.Status
					)
				)

			status.TextXAlignment =
				Enum.TextXAlignment.Right

			status.Position =
				UDim2.new(
					1,
					-142,
					0,
					12
				)

			status.Size =
				UDim2.fromOffset(
					126,
					20
				)

			local action =
				makeButton(
					card,
					technique.Learned
					and "Unlocked"
					or (
						technique.CanUnlock
						and "Unlock"
						or "Locked"
					)
				)

			action.AnchorPoint =
				Vector2.new(
					1,
					1
				)

			action.Position =
				UDim2.new(
					1,
					-16,
					1,
					-14
				)

			action.Size =
				UDim2.fromOffset(
					116,
					34
				)

			if technique.Learned then
				action.BackgroundColor3 =
					C.Good

				action.Active =
					false

				action.AutoButtonColor =
					false

			elseif technique.CanUnlock
				and isReadOnly() then

				action.Active =
					false

				action.Text =
					"Read Only"

				action.BackgroundColor3 =
					C.Panel3

			elseif technique.CanUnlock then
				action.BackgroundColor3 =
					C.Accent

				action.Activated:
					Connect(
						function()
							action.Active =
							false

							action.Text =
							"Unlocking..."

							task.spawn(
								function()
									local okCall,
									result =
									pcall(
										function()
											return request:
											InvokeServer(
												"UnlockTechnique",
												{
													TechniqueId =
													technique.Id,
												}
											)
										end
									)

									if not okCall then
										setFeedback(
											"Unlock request failed",
											"bad"
										)

										if refreshTechniques then
											refreshTechniques()
										end

										return
									end

									if typeof(result) ==
										"table"
										and result.Ok
										== true then

										setFeedback(
											"Unlocked "
											.. tostring(
												technique.DisplayName
											),
											"good"
										)

									else
										local reason =
										typeof(result) == "table"
										and result.Reason
										or "UnlockDenied"

										setFeedback(
											reasonLabels[
											tostring(
												reason
											)
											]
											or tostring(
												reason
											),
											"bad"
										)
									end

									if typeof(result)
										== "table"
										and typeof(
											result.Snapshot
										) == "table" then

										renderTechniqueSnapshot(
											result.Snapshot
										)

									elseif refreshTechniques then
										refreshTechniques()
									end
								end
							)
						end
					)

			else
				action.Active =
					false

				action.Text =
					"Locked"

				action.BackgroundColor3 =
					C.Panel3

				local why =
					reasonLabels[
				tostring(
					technique.LockReason
				)
				]

				if why then
					action.Text =
						"Locked"
				end
			end
		end
	end

	emptyTechniques.Visible =
		visibleCount == 0

	emptyTechniques.Text =
		"No techniques match "
		.. activeNatureFilter
		.. "."
end

refreshTechniques =
	function()
		setFeedback(
			"Refreshing..."
		)

		task.spawn(
			function()
				local okCall,
				snapshot =
				pcall(
					function()
						return request:
						InvokeServer(
							"GetTechniques"
						)
					end
				)

				if not okCall then
					setFeedback(
						"Technique request failed",
						"bad"
					)

					return
				end

				renderTechniqueSnapshot(
					snapshot
				)

				setFeedback(
					""
				)
			end
		)
	end

refreshButton.Activated:
	Connect(
		function()
			if refreshTechniques then
				refreshTechniques()
			end
		end
	)

for filterName,
	button in pairs(
		filterButtons
	) do

	button.Activated:
		Connect(
			function()
				activeNatureFilter =
				filterName

				for name,
					candidate in pairs(
						filterButtons
					) do

					candidate.BackgroundColor3 =
					name == activeNatureFilter
					and C.AccentSoft
					or C.Panel3
				end

				if lastTechniqueSnapshot then
					renderTechniqueSnapshot(
						lastTechniqueSnapshot
					)
				end
			end
		)
end

filterButtons.All.BackgroundColor3 =
	C.AccentSoft

---------------------------------------------------------------------
-- TECHNIQUE LOADOUT PAGE
---------------------------------------------------------------------

local loadoutPage =
	makePage(
		"Loadout"
	)

local loadoutHeader =
	makeText(
		loadoutPage,
		"TECHNIQUE LOADOUT",
		24,
		true
	)

loadoutHeader.Position =
	UDim2.fromOffset(
		28,
		22
	)

loadoutHeader.Size =
	UDim2.new(
		0.6,
		0,
		0,
		34
	)

local loadoutSummary =
	makeText(
		loadoutPage,
		"Loading technique loadout...",
		12,
		false
	)

loadoutSummary.TextColor3 =
	C.SubText

loadoutSummary.Position =
	UDim2.fromOffset(
		28,
		56
	)

loadoutSummary.Size =
	UDim2.new(
		1,
		-56,
		0,
		38
	)

local loadoutRefresh =
	makeButton(
		loadoutPage,
		"Refresh"
	)

loadoutRefresh.AnchorPoint =
	Vector2.new(
		1,
		0
	)

loadoutRefresh.Position =
	UDim2.new(
		1,
		-28,
		0,
		24
	)

loadoutRefresh.Size =
	UDim2.fromOffset(
		104,
		32
	)

local loadoutScroll =
	Instance.new(
		"ScrollingFrame"
	)

loadoutScroll.BackgroundTransparency =
	1

loadoutScroll.BorderSizePixel =
	0

loadoutScroll.Position =
	UDim2.fromOffset(
		28,
		102
	)

loadoutScroll.Size =
	UDim2.new(
		1,
		-56,
		1,
		-130
	)

loadoutScroll.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

loadoutScroll.CanvasSize =
	UDim2.new()

loadoutScroll.ScrollBarThickness =
	5

loadoutScroll.Parent =
	loadoutPage

local loadoutGrid =
	Instance.new(
		"UIGridLayout"
	)

loadoutGrid.CellPadding =
	UDim2.fromOffset(
		12,
		12
	)

loadoutGrid.CellSize =
	UDim2.new(
		0.5,
		-6,
		0,
		118
	)

loadoutGrid.SortOrder =
	Enum.SortOrder.LayoutOrder

loadoutGrid.Parent =
	loadoutScroll

local loadoutSlotNames: {[number]: TextLabel} =
	{}

local loadoutSlotMeta: {[number]: TextLabel} =
	{}

local loadoutSlotButtons: {[number]: TextButton} =
	{}

for slotIndex = 1, 10 do
	local card =
		Instance.new(
			"Frame"
		)

	card.Name =
		"TechniqueSlot"
		.. tostring(
			slotIndex
		)

	card.BackgroundColor3 =
		C.Panel2

	card.LayoutOrder =
		slotIndex

	card.Parent =
		loadoutScroll

	corner(
		card,
		10
	)

	stroke(
		card,
		0.55
	)

	local slotLabel =
		makeText(
			card,
			"SLOT "
			.. tostring(
				slotIndex
			),
			11,
			true
		)

	slotLabel.TextColor3 =
		C.SubText

	slotLabel.Position =
		UDim2.fromOffset(
			14,
			10
		)

	slotLabel.Size =
		UDim2.new(
			1,
			-132,
			0,
			18
		)

	local techniqueName =
		makeText(
			card,
			"Empty",
			16,
			true
		)

	techniqueName.Position =
		UDim2.fromOffset(
			14,
			32
		)

	techniqueName.Size =
		UDim2.new(
			1,
			-132,
			0,
			28
		)

	loadoutSlotNames[
	slotIndex
	] =
		techniqueName

	local meta =
		makeText(
			card,
			"No technique assigned",
			11,
			false
		)

	meta.TextColor3 =
		C.SubText

	meta.Position =
		UDim2.fromOffset(
			14,
			64
		)

	meta.Size =
		UDim2.new(
			1,
			-132,
			0,
			36
		)

	loadoutSlotMeta[
	slotIndex
	] =
		meta

	local assign =
		makeButton(
			card,
			"Assign"
		)

	assign.AnchorPoint =
		Vector2.new(
			1,
			0.5
		)

	assign.Position =
		UDim2.new(
			1,
			-14,
			0.5,
			5
		)

	assign.Size =
		UDim2.fromOffset(
			104,
			36
		)

	loadoutSlotButtons[
	slotIndex
	] =
		assign

	assign.Activated:
		Connect(
			function()
				if isReadOnly() then
					setFeedback(
						"Loadout is read only right now",
						"bad"
					)

					return
				end

				if openTechniquePicker then
					openTechniquePicker(
						slotIndex
					)
				end
			end
		)
end

local function renderLoadoutSnapshot(
	snapshot: any
)
	if typeof(snapshot)
		~= "table"
		or snapshot.Ok
		~= true then

		loadoutSummary.Text =
			"Technique loadout unavailable: "
			.. tostring(
				typeof(snapshot) == "table"
				and snapshot.Reason
				or "Request failed"
			)

		loadoutSummary.TextColor3 =
			C.Bad

		for slotIndex = 1, 10 do
			loadoutSlotNames[
			slotIndex
			].Text =
				"Unavailable"

			loadoutSlotMeta[
			slotIndex
			].Text =
				"Loadout data is not ready"

			loadoutSlotButtons[
			slotIndex
			].Text =
				"Unavailable"

			loadoutSlotButtons[
			slotIndex
			].Active =
				false
		end

		return
	end

	loadoutSummary.TextColor3 =
		C.SubText

	loadoutSummary.Text =
		tostring(
			snapshot.SlotCount
			or 10
		)
		.. " technique slots"
		.. (
			isReadOnly()
			and "  •  Read only"
			or "  •  Click a slot to assign an unlocked technique"
		)

	local bySlot = {}

	for _, slot in ipairs(
		snapshot.Slots
			or {}
		) do
		local slotIndex =
			tonumber(
				slot.SlotIndex
			)

		if slotIndex then
			bySlot[
			slotIndex
			] =
				slot
		end
	end

	for slotIndex = 1, 10 do
		local slot =
			bySlot[
		slotIndex
		]

		local techniqueId =
			slot
			and slot.TechniqueId
			or nil

		if techniqueId then
			loadoutSlotNames[
			slotIndex
			].Text =
				tostring(
					slot.DisplayName
					or techniqueId
				)

			loadoutSlotNames[
			slotIndex
			].TextColor3 =
				C.Text

			local nature =
				tostring(
					slot.NatureId
					or "Non-elemental"
				)

			local category =
				tostring(
					slot.Category
					or "Technique"
				)

			loadoutSlotMeta[
			slotIndex
			].Text =
				nature
				.. "  •  "
				.. category

			loadoutSlotButtons[
			slotIndex
			].Text =
				isReadOnly()
				and "Read Only"
				or "Change"

		else
			loadoutSlotNames[
			slotIndex
			].Text =
				"Empty"

			loadoutSlotNames[
			slotIndex
			].TextColor3 =
				C.SubText

			loadoutSlotMeta[
			slotIndex
			].Text =
				"No technique assigned"

			loadoutSlotButtons[
			slotIndex
			].Text =
				isReadOnly()
				and "Read Only"
				or "Assign"
		end

		loadoutSlotButtons[
		slotIndex
		].Active =
			not isReadOnly()
	end
end

refreshLoadout =
	function()
		setFeedback(
			"Refreshing loadout..."
		)

		task.spawn(
			function()
				local okCall,
				snapshot =
				pcall(
					function()
						return request:
						InvokeServer(
							"GetLoadout"
						)
					end
				)

				if not okCall then
					setFeedback(
						"Loadout request failed",
						"bad"
					)

					renderLoadoutSnapshot(
						{
							Ok = false,
							Reason =
							"RequestFailed",
						}
					)

					return
				end

				renderLoadoutSnapshot(
					snapshot
				)

				if typeof(snapshot) ==
					"table"
					and snapshot.Ok
					== true then

					setFeedback(
						""
					)
				else
					setFeedback(
						typeof(snapshot) == "table"
						and snapshot.Reason
						or "Loadout unavailable",
						"bad"
					)
				end
			end
		)
	end

loadoutRefresh.Activated:
	Connect(
		function()
			if refreshLoadout then
				refreshLoadout()
			end
		end
	)

---------------------------------------------------------------------
-- SHARED INVENTORY PICKER
---------------------------------------------------------------------

local picker =
	Instance.new(
		"Frame"
	)

picker.Name =
	"Picker"

picker.BackgroundColor3 =
	C.Panel

picker.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

picker.Position =
	UDim2.fromScale(
		0.5,
		0.5
	)

picker.Size =
	UDim2.new(
		0.68,
		0,
		0.78,
		0
	)

picker.Visible =
	false

picker.ZIndex =
	20

picker.Parent =
	content

corner(
	picker,
	12
)

stroke(
	picker,
	0.05
)

local pickerTitle =
	makeText(
		picker,
		"SELECT",
		18,
		true
	)

pickerTitle.ZIndex =
	21

pickerTitle.Position =
	UDim2.fromOffset(
		18,
		14
	)

pickerTitle.Size =
	UDim2.new(
		1,
		-74,
		0,
		30
	)

local pickerClose =
	makeButton(
		picker,
		"×"
	)

pickerClose.ZIndex =
	21

pickerClose.AnchorPoint =
	Vector2.new(
		1,
		0
	)

pickerClose.Position =
	UDim2.new(
		1,
		-14,
		0,
		12
	)

pickerClose.Size =
	UDim2.fromOffset(
		36,
		34
	)

local pickerScroll =
	Instance.new(
		"ScrollingFrame"
	)

pickerScroll.BackgroundTransparency =
	1

pickerScroll.BorderSizePixel =
	0

pickerScroll.Position =
	UDim2.fromOffset(
		16,
		56
	)

pickerScroll.Size =
	UDim2.new(
		1,
		-32,
		1,
		-72
	)

pickerScroll.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

pickerScroll.CanvasSize =
	UDim2.new()

pickerScroll.ScrollBarThickness =
	4

pickerScroll.ZIndex =
	21

pickerScroll.Parent =
	picker

local pickerList =
	Instance.new(
		"UIListLayout"
	)

pickerList.Padding =
	UDim.new(
		0,
		8
	)

pickerList.SortOrder =
	Enum.SortOrder.LayoutOrder

pickerList.Parent =
	pickerScroll

local pickerGenerated = {}

local function closePicker()
	picker.Visible =
		false

	for _, instance in ipairs(
		pickerGenerated
		) do
		instance:Destroy()
	end

	table.clear(
		pickerGenerated
	)
end

pickerClose.Activated:
	Connect(
		closePicker
	)

local function openPicker(
	titleText: string,
	choices: {any},
	onChoose: (string?) -> (),
	allowClear: boolean
)
	closePicker()

	pickerTitle.Text =
		titleText

	local function addChoice(
		itemId: string?,
		displayText: string,
		subText: string
	)
		local row =
			Instance.new(
				"Frame"
			)

		row.BackgroundColor3 =
			C.Panel2

		row.Size =
			UDim2.new(
				1,
				-6,
				0,
				62
			)

		row.ZIndex =
			21

		row.Parent =
			pickerScroll

		table.insert(
			pickerGenerated,
			row
		)

		corner(
			row,
			8
		)

		local name =
			makeText(
				row,
				displayText,
				14,
				true
			)

		name.ZIndex =
			22

		name.Position =
			UDim2.fromOffset(
				14,
				8
			)

		name.Size =
			UDim2.new(
				1,
				-132,
				0,
				22
			)

		local sub =
			makeText(
				row,
				subText,
				11,
				false
			)

		sub.TextColor3 =
			C.SubText

		sub.ZIndex =
			22

		sub.Position =
			UDim2.fromOffset(
				14,
				32
			)

		sub.Size =
			UDim2.new(
				1,
				-132,
				0,
				18
			)

		local choose =
			makeButton(
				row,
				itemId
				and "Select"
				or "Clear"
			)

		choose.ZIndex =
			22

		choose.AnchorPoint =
			Vector2.new(
				1,
				0.5
			)

		choose.Position =
			UDim2.new(
				1,
				-12,
				0.5,
				0
			)

		choose.Size =
			UDim2.fromOffset(
				96,
				34
			)

		if isReadOnly() then
			choose.Active =
				false

			choose.Text =
				"Read Only"
		else
			choose.Activated:
				Connect(
					function()
						closePicker()

						onChoose(
							itemId
						)
					end
				)
		end
	end

	if allowClear then
		addChoice(
			nil,
			"Empty",
			"Clear this slot"
		)
	end

	for _, item in ipairs(
		choices
		) do
		addChoice(
			item.Id,
			tostring(
				item.DisplayName
					or item.Id
			),
			tostring(
				item.Description
					or item.Kind
					or "Item"
			)
				.. "  •  Owned "
				.. tostring(
					getAmount(
						item.Id
					)
				)
		)
	end

	picker.Visible =
		true
end

local function loadoutReasonText(
	reason: any
): string
	local labels = {
		InvalidSlotIndex =
			"Invalid technique slot",

		TechniqueLoadoutNotReady =
			"Technique loadout is still loading",

		InvalidTechniqueId =
			"Invalid technique",

		UnknownTechnique =
			"Unknown technique",

		TechniqueNotLearned =
			"That technique is not unlocked",

		RequestThrottled =
			"Please wait a moment",

		CombatTagged =
			"Loadout is read only while in combat",

		CharacterActionLocked =
			"Loadout cannot change during this action",

		NoChange =
			"No change",

		TechniqueAssigned =
			"Technique assigned",

		TechniqueAssignedSavePending =
			"Technique assigned; save pending",

		SlotCleared =
			"Slot cleared",

		SlotClearedSavePending =
			"Slot cleared; save pending",
	}

	return labels[
	tostring(
		reason
	)
	]
		or tostring(
			reason
			or "Loadout update failed"
		)
end

local function submitLoadoutSlot(
	slotIndex: number,
	techniqueId: string?
)
	setFeedback(
		"Updating loadout..."
	)

	task.spawn(
		function()
			local okCall,
			result =
				pcall(
					function()
						return request:
						InvokeServer(
							"SetLoadoutSlot",
							{
								SlotIndex =
								slotIndex,

								TechniqueId =
								techniqueId,
							}
						)
					end
				)

			if not okCall then
				setFeedback(
					"Loadout update failed",
					"bad"
				)

				if refreshLoadout then
					refreshLoadout()
				end

				return
			end

			local success =
				typeof(result) ==
				"table"
				and result.Ok
				== true

			setFeedback(
				loadoutReasonText(
					typeof(result) ==
						"table"
						and result.Reason
						or result
				),
				success
					and "good"
					or "bad"
			)

			if typeof(result) ==
				"table"
				and typeof(
					result.Snapshot
				) == "table" then

				renderLoadoutSnapshot(
					result.Snapshot
				)

			elseif refreshLoadout then
				refreshLoadout()
			end
		end
	)
end

openTechniquePicker =
	function(
		slotIndex: number
	)
	closePicker()

	pickerTitle.Text =
		"SELECT TECHNIQUE • SLOT "
		.. tostring(
			slotIndex
		)

	task.spawn(
		function()
			local okCall,
			snapshot =
				pcall(
					function()
						return request:
						InvokeServer(
							"GetTechniques"
						)
					end
				)

			if not okCall
				or typeof(snapshot)
				~= "table"
				or snapshot.Ok
				~= true then

				setFeedback(
					"Could not load unlocked techniques",
					"bad"
				)

				return
			end

			local learned = {}

			for _, technique in ipairs(
				snapshot.Techniques
					or {}
				) do
				if technique.Learned
					== true then

					table.insert(
						learned,
						technique
					)
				end
			end

			table.sort(
				learned,
				function(
					a: any,
					b: any
				): boolean
					return tostring(
						a.DisplayName
							or a.Id
					) < tostring(
						b.DisplayName
							or b.Id
					)
				end
			)

			local function addTechniqueChoice(
				techniqueId: string?,
				displayText: string,
				subText: string,
				clearChoice: boolean
			)
				local row =
					Instance.new(
						"Frame"
					)

				row.BackgroundColor3 =
					C.Panel2

				row.Size =
					UDim2.new(
						1,
						-6,
						0,
						62
					)

				row.ZIndex =
					21

				row.Parent =
					pickerScroll

				table.insert(
					pickerGenerated,
					row
				)

				corner(
					row,
					8
				)

				local name =
					makeText(
						row,
						displayText,
						14,
						true
					)

				name.ZIndex =
					22

				name.Position =
					UDim2.fromOffset(
						14,
						8
					)

				name.Size =
					UDim2.new(
						1,
						-132,
						0,
						22
					)

				local sub =
					makeText(
						row,
						subText,
						11,
						false
					)

				sub.TextColor3 =
					C.SubText

				sub.ZIndex =
					22

				sub.Position =
					UDim2.fromOffset(
						14,
						32
					)

				sub.Size =
					UDim2.new(
						1,
						-132,
						0,
						18
					)

				local choose =
					makeButton(
						row,
						clearChoice
						and "Clear"
						or "Select"
					)

				choose.ZIndex =
					22

				choose.AnchorPoint =
					Vector2.new(
						1,
						0.5
					)

				choose.Position =
					UDim2.new(
						1,
						-12,
						0.5,
						0
					)

				choose.Size =
					UDim2.fromOffset(
						96,
						34
					)

				if isReadOnly() then
					choose.Active =
						false

					choose.Text =
						"Read Only"

				else
					choose.Activated:
						Connect(
							function()
								closePicker()

								submitLoadoutSlot(
									slotIndex,
									techniqueId
								)
							end
						)
				end
			end

			addTechniqueChoice(
				nil,
				"Empty",
				"Clear this technique slot",
				true
			)

			for _, technique in ipairs(
				learned
				) do
				local nature =
					tostring(
						technique.NatureId
						or "Non-elemental"
					)

				local category =
					tostring(
						technique.Category
						or "Technique"
					)

				addTechniqueChoice(
					technique.Id,
					tostring(
						technique.DisplayName
							or technique.Id
					),
					nature
						.. "  •  "
						.. category,
					false
				)
			end

			if #learned == 0 then
				setFeedback(
					"No unlocked techniques available",
					"bad"
				)
			else
				setFeedback(
					""
				)
			end

			picker.Visible =
				true
		end
	)
end

---------------------------------------------------------------------
-- INVENTORY PAGE
---------------------------------------------------------------------

local inventoryPage =
	makePage(
		"Inventory"
	)

local inventoryHeader =
	makeText(
		inventoryPage,
		"INVENTORY",
		24,
		true
	)

inventoryHeader.Position =
	UDim2.fromOffset(
		28,
		22
	)

inventoryHeader.Size =
	UDim2.new(
		0.6,
		0,
		0,
		34
	)

local inventorySummary =
	makeText(
		inventoryPage,
		"Loading inventory...",
		12,
		false
	)

inventorySummary.TextColor3 =
	C.SubText

inventorySummary.Position =
	UDim2.fromOffset(
		28,
		56
	)

inventorySummary.Size =
	UDim2.new(
		1,
		-56,
		0,
		24
	)

local inventoryCategoryBar =
	Instance.new(
		"Frame"
	)

inventoryCategoryBar.BackgroundTransparency =
	1

inventoryCategoryBar.Position =
	UDim2.fromOffset(
		28,
		88
	)

inventoryCategoryBar.Size =
	UDim2.new(
		1,
		-56,
		0,
		34
	)

inventoryCategoryBar.Parent =
	inventoryPage

local inventoryCategoryLayout =
	Instance.new(
		"UIListLayout"
	)

inventoryCategoryLayout.FillDirection =
	Enum.FillDirection.Horizontal

inventoryCategoryLayout.Padding =
	UDim.new(
		0,
		6
	)

inventoryCategoryLayout.Parent =
	inventoryCategoryBar

local inventoryCategoryButtons: {[string]: TextButton} =
	{}

local inventoryCategory =
	"All"

for _, definition in ipairs(
	InventoryCatalog.Categories
	) do
	local button =
		makeButton(
			inventoryCategoryBar,
			tostring(
				definition.DisplayName
			)
		)

	button.Size =
		UDim2.fromOffset(
			82,
			30
		)

	button.TextSize =
		11

	inventoryCategoryButtons[
	definition.Id
	] =
		button
end

local inventoryScroll =
	Instance.new(
		"ScrollingFrame"
	)

inventoryScroll.BackgroundTransparency =
	1

inventoryScroll.BorderSizePixel =
	0

inventoryScroll.Position =
	UDim2.fromOffset(
		28,
		136
	)

inventoryScroll.Size =
	UDim2.new(
		1,
		-56,
		1,
		-164
	)

inventoryScroll.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

inventoryScroll.CanvasSize =
	UDim2.new()

inventoryScroll.ScrollBarThickness =
	5

inventoryScroll.Parent =
	inventoryPage

local inventoryList =
	Instance.new(
		"UIListLayout"
	)

inventoryList.Padding =
	UDim.new(
		0,
		9
	)

inventoryList.Parent =
	inventoryScroll

local inventoryGenerated = {}

local function clearInventoryCards()
	for _, instance in ipairs(
		inventoryGenerated
		) do
		instance:Destroy()
	end

	table.clear(
		inventoryGenerated
	)
end

local function refreshInventory()
	clearInventoryCards()

	local ready =
		player:GetAttribute(
			"InventoryPersistenceReady"
		) == true

	local allItems =
		InventoryCatalog.GetItemsByCategory(
			inventoryCategory
		)

	local ownedCount = 0
	local totalUnits = 0

	for _, item in ipairs(
		InventoryCatalog.GetAllItems()
		) do
		local amount =
			getAmount(
				item.Id
			)

		if amount > 0 then
			ownedCount += 1
			totalUnits += amount
		end
	end

	inventorySummary.Text =
		(
			ready
			and "Persistent inventory"
			or "Inventory persistence loading..."
		)
		.. "  •  "
		.. tostring(
			ownedCount
		)
		.. " item types  •  "
		.. tostring(
			totalUnits
		)
		.. " total units"

	for index, item in ipairs(
		allItems
		) do
		local amount =
			getAmount(
				item.Id
			)

		local maxAmount =
			getMaxAmount(
				item.Id,
				item.MaxAmount
			)

		local card =
			Instance.new(
				"Frame"
			)

		card.BackgroundColor3 =
			C.Panel2

		card.Size =
			UDim2.new(
				1,
				-8,
				0,
				82
			)

		card.LayoutOrder =
			index

		card.Parent =
			inventoryScroll

		table.insert(
			inventoryGenerated,
			card
		)

		corner(
			card,
			9
		)

		stroke(
			card,
			0.6
		)

		local name =
			makeText(
				card,
				tostring(
					item.DisplayName
					or item.Id
				),
				15,
				true
			)

		name.Position =
			UDim2.fromOffset(
				14,
				10
			)

		name.Size =
			UDim2.new(
				1,
				-160,
				0,
				24
			)

		local description =
			makeText(
				card,
				tostring(
					item.Description
					or item.Kind
					or "Item"
				),
				11,
				false
			)

		description.TextColor3 =
			C.SubText

		description.Position =
			UDim2.fromOffset(
				14,
				38
			)

		description.Size =
			UDim2.new(
				1,
				-160,
				0,
				28
			)

		local amountLabel =
			makeText(
				card,
				tostring(amount)
				.. " / "
				.. tostring(maxAmount),
				15,
				true
			)

		amountLabel.TextXAlignment =
			Enum.TextXAlignment.Right

		amountLabel.AnchorPoint =
			Vector2.new(
				1,
				0.5
			)

		amountLabel.Position =
			UDim2.new(
				1,
				-16,
				0.5,
				0
			)

		amountLabel.Size =
			UDim2.fromOffset(
				128,
				30
			)

		amountLabel.TextColor3 =
			amount > 0
			and C.Good
			or C.SubText
	end
end

for categoryId,
	button in pairs(
		inventoryCategoryButtons
	) do

	button.Activated:
		Connect(
			function()
				inventoryCategory =
				categoryId

				for id,
					candidate in pairs(
						inventoryCategoryButtons
					) do

					candidate.BackgroundColor3 =
					id == inventoryCategory
					and C.AccentSoft
					or C.Panel3
				end

				refreshInventory()
			end
		)
end

inventoryCategoryButtons.All.BackgroundColor3 =
	C.AccentSoft

---------------------------------------------------------------------
-- NINJA BAG PAGE
---------------------------------------------------------------------

local ninjaBagPage =
	makePage(
		"Ninja Bag"
	)

local ninjaBagHeader =
	makeText(
		ninjaBagPage,
		"NINJA BAG",
		24,
		true
	)

ninjaBagHeader.Position =
	UDim2.fromOffset(
		28,
		22
	)

ninjaBagHeader.Size =
	UDim2.new(
		0.6,
		0,
		0,
		34
	)

local ninjaBagSummary =
	makeText(
		ninjaBagPage,
		"",
		12,
		false
	)

ninjaBagSummary.TextColor3 =
	C.SubText

ninjaBagSummary.Position =
	UDim2.fromOffset(
		28,
		56
	)

ninjaBagSummary.Size =
	UDim2.new(
		1,
		-56,
		0,
		44
	)

local ninjaSlotContainer =
	Instance.new(
		"Frame"
	)

ninjaSlotContainer.BackgroundTransparency =
	1

ninjaSlotContainer.Position =
	UDim2.fromOffset(
		28,
		112
	)

ninjaSlotContainer.Size =
	UDim2.new(
		1,
		-56,
		1,
		-140
	)

ninjaSlotContainer.Parent =
	ninjaBagPage

local ninjaSlotGrid =
	Instance.new(
		"UIGridLayout"
	)

ninjaSlotGrid.CellPadding =
	UDim2.fromOffset(
		12,
		12
	)

ninjaSlotGrid.CellSize =
	UDim2.new(
		0.5,
		-6,
		0,
		145
	)

ninjaSlotGrid.Parent =
	ninjaSlotContainer

local ninjaSlotFrames: {[number]: Frame} =
	{}

local ninjaSlotNames: {[number]: TextLabel} =
	{}

local ninjaSlotAmounts: {[number]: TextLabel} =
	{}

for slotIndex = 1, 4 do
	local card =
		Instance.new(
			"Frame"
		)

	card.BackgroundColor3 =
		C.Panel2

	card.LayoutOrder =
		slotIndex

	card.Parent =
		ninjaSlotContainer

	ninjaSlotFrames[
	slotIndex
	] =
		card

	corner(
		card,
		10
	)

	stroke(
		card,
		0.55
	)

	local slotLabel =
		makeText(
			card,
			"SLOT "
			.. tostring(
				slotIndex
			),
			11,
			true
		)

	slotLabel.TextColor3 =
		C.SubText

	slotLabel.Position =
		UDim2.fromOffset(
			14,
			10
		)

	slotLabel.Size =
		UDim2.new(
			1,
			-28,
			0,
			20
		)

	local itemName =
		makeText(
			card,
			"Empty",
			16,
			true
		)

	itemName.Position =
		UDim2.fromOffset(
			14,
			34
		)

	itemName.Size =
		UDim2.new(
			1,
			-28,
			0,
			26
		)

	ninjaSlotNames[
	slotIndex
	] =
		itemName

	local amount =
		makeText(
			card,
			"0",
			12,
			false
		)

	amount.TextColor3 =
		C.SubText

	amount.Position =
		UDim2.fromOffset(
			14,
			62
		)

	amount.Size =
		UDim2.new(
			1,
			-28,
			0,
			20
		)

	ninjaSlotAmounts[
	slotIndex
	] =
		amount

	local change =
		makeButton(
			card,
			"Change"
		)

	change.AnchorPoint =
		Vector2.new(
			0,
			1
		)

	change.Position =
		UDim2.new(
			0,
			14,
			1,
			-12
		)

	change.Size =
		UDim2.new(
			1,
			-28,
			0,
			34
		)

	change.Activated:
		Connect(
			function()
				if not inventoryMutationsReady() then
					return
				end

				local choices = {}

				for _, item in ipairs(
					InventoryCatalog.GetNinjaBagItems()
					) do
					if player:GetAttribute(
						"NinjaBagUnlocked_"
						.. item.Id
						) ~= false then

						table.insert(
							choices,
							item
						)
					end
				end

				openPicker(
					"NINJA BAG SLOT "
					.. tostring(
						slotIndex
					),
					choices,
					function(
						itemId: string?
					)
						ninjaEquipRequest:
						FireServer(
							slotIndex,
							itemId
						)
					end,
					true
				)
			end
		)
end

local function refreshNinjaBag()
	local bag =
		getEquipped(
			"NinjaBag"
		)

	local used =
		player:GetAttribute(
			"NinjaBagUsedCapacity"
		) or 0

	local capacity =
		player:GetAttribute(
			"NinjaBagCapacity"
		) or 0

	ninjaBagSummary.Text =
		"Equipped: "
		.. itemDisplayName(
			bag
		)
		.. "  •  Capacity "
		.. tostring(
			used
		)
		.. " / "
		.. tostring(
			capacity
		)
		.. (
			isReadOnly()
			and "  •  READ ONLY IN COMBAT"
			or ""
		)

	for slotIndex = 1, 4 do
		local itemId =
			getQuickSlot(
				slotIndex
			)

		ninjaSlotNames[
		slotIndex
		].Text =
			itemDisplayName(
				itemId
			)

		if itemId then
			ninjaSlotAmounts[
			slotIndex
			].Text =
				"Owned: "
				.. tostring(
					getAmount(
						itemId
					)
				)
		else
			ninjaSlotAmounts[
			slotIndex
			].Text =
				"No throwable assigned"
		end
	end
end

---------------------------------------------------------------------
-- EQUIPMENT PAGE
---------------------------------------------------------------------

local equipmentPage =
	makePage(
		"Equipment"
	)

local equipmentHeader =
	makeText(
		equipmentPage,
		"EQUIPMENT",
		24,
		true
	)

equipmentHeader.Position =
	UDim2.fromOffset(
		28,
		22
	)

equipmentHeader.Size =
	UDim2.new(
		0.6,
		0,
		0,
		34
	)

local equipmentSummary =
	makeText(
		equipmentPage,
		"",
		12,
		false
	)

equipmentSummary.TextColor3 =
	C.SubText

equipmentSummary.Position =
	UDim2.fromOffset(
		28,
		56
	)

equipmentSummary.Size =
	UDim2.new(
		1,
		-56,
		0,
		34
	)

local equipmentContainer =
	Instance.new(
		"Frame"
	)

equipmentContainer.BackgroundTransparency =
	1

equipmentContainer.Position =
	UDim2.fromOffset(
		28,
		100
	)

equipmentContainer.Size =
	UDim2.new(
		1,
		-56,
		1,
		-126
	)

equipmentContainer.Parent =
	equipmentPage

local equipmentList =
	Instance.new(
		"UIListLayout"
	)

equipmentList.Padding =
	UDim.new(
		0,
		10
	)

equipmentList.Parent =
	equipmentContainer

local equipmentNames: {[string]: TextLabel} =
	{}

local equipmentDetails: {[string]: TextLabel} =
	{}

for _, definition in ipairs(
	InventoryCatalog.EquipmentSlots
	) do
	if definition.Active ==
		true then

		local slotId =
			definition.Id

		local card =
			Instance.new(
				"Frame"
			)

		card.BackgroundColor3 =
			C.Panel2

		card.Size =
			UDim2.new(
				1,
				0,
				0,
				92
			)

		card.Parent =
			equipmentContainer

		corner(
			card,
			10
		)

		stroke(
			card,
			0.55
		)

		local slotName =
			makeText(
				card,
				tostring(
					definition.DisplayName
				),
				11,
				true
			)

		slotName.TextColor3 =
			C.SubText

		slotName.Position =
			UDim2.fromOffset(
				14,
				10
			)

		slotName.Size =
			UDim2.new(
				1,
				-150,
				0,
				20
			)

		local itemName =
			makeText(
				card,
				"Empty",
				16,
				true
			)

		itemName.Position =
			UDim2.fromOffset(
				14,
				32
			)

		itemName.Size =
			UDim2.new(
				1,
				-150,
				0,
				24
			)

		equipmentNames[
		slotId
		] =
			itemName

		local details =
			makeText(
				card,
				"",
				11,
				false
			)

		details.TextColor3 =
			C.SubText

		details.Position =
			UDim2.fromOffset(
				14,
				58
			)

		details.Size =
			UDim2.new(
				1,
				-150,
				0,
				20
			)

		equipmentDetails[
		slotId
		] =
			details

		local change =
			makeButton(
				card,
				"Change"
			)

		change.AnchorPoint =
			Vector2.new(
				1,
				0.5
			)

		change.Position =
			UDim2.new(
				1,
				-14,
				0.5,
				0
			)

		change.Size =
			UDim2.fromOffset(
				110,
				36
			)

		change.Activated:
			Connect(
				function()
					if not inventoryMutationsReady() then
						return
					end

					local choices = {}

					for _, item in ipairs(
						InventoryCatalog
						.GetItemsForEquipmentSlot(
							slotId
						)
						) do
						if getAmount(
							item.Id
							) > 0
							and player:GetAttribute(
								"InventoryUnlocked_"
								.. item.Id
							) ~= false then

							table.insert(
								choices,
								item
							)
						end
					end

					openPicker(
						tostring(
							definition.DisplayName
						),
						choices,
						function(
							itemId: string?
						)
							equipmentEquipRequest:
							FireServer(
								slotId,
								itemId
							)
						end,
						true
					)
				end
			)
	end
end

local function refreshEquipment()
	equipmentSummary.Text =
		(
			player:GetAttribute(
				"InventoryPersistenceReady"
			) == true
			and "Persistent equipment"
			or "Equipment loading..."
		)
		.. (
			isReadOnly()
			and "  •  READ ONLY IN COMBAT"
			or ""
		)

	for _, definition in ipairs(
		InventoryCatalog.EquipmentSlots
		) do
		if definition.Active ==
			true then

			local slotId =
				definition.Id

			local itemId =
				getEquipped(
					slotId
				)

			equipmentNames[
			slotId
			].Text =
				itemDisplayName(
					itemId
				)

			local detail =
				"No item equipped"

			if itemId then
				local item =
					InventoryCatalog.GetItem(
						itemId
					)

				if slotId ==
					"Armor"
					and item
					and typeof(
						item.Armor
					) == "table" then

					local durability =
						player:GetAttribute(
							"EquipmentDurability_"
							.. itemId
						) or 0

					detail =
						"Durability "
						.. tostring(
							math.floor(
								durability
							)
						)
						.. " / "
						.. tostring(
							item.Armor.MaxDurability
							or 0
						)
						.. "  •  Resistance "
						.. tostring(
							math.floor(
								(
									item.Armor.Resistance
									or 0
								)
								* 100
							)
						)
						.. "%"

				elseif slotId ==
					"NinjaBag"
					and item
					and typeof(
						item.NinjaBagEquipment
					) == "table" then

					detail =
						"Capacity "
						.. tostring(
							item.NinjaBagEquipment.Capacity
							or 0
						)

				elseif item then
					detail =
						tostring(
							item.Description
							or item.Kind
							or "Equipped"
						)
				end
			end

			equipmentDetails[
			slotId
			].Text =
				detail
		end
	end
end

equipmentEquipResult.OnClientEvent:
	Connect(
		function(
			success: boolean,
			_slotId: any,
			_itemId: any,
			reason: any
		)
			if success then
				setFeedback(
					"Equipment updated",
					"good"
				)
			else
				setFeedback(
					"Equipment: "
					.. tostring(
						reason
					),
					"bad"
				)
			end

			if isOpen then
				refreshEquipment()
				refreshNinjaBag()
				refreshInventory()
			end
		end
	)

ninjaEquipResult.OnClientEvent:
	Connect(
		function(
			success: boolean,
			_slotIndex: any,
			_projectileType: any,
			reason: any
		)
			if success then
				setFeedback(
					"Ninja Bag updated",
					"good"
				)
			else
				setFeedback(
					"Ninja Bag: "
					.. tostring(
						reason
					),
					"bad"
				)
			end

			if isOpen then
				refreshNinjaBag()
			end
		end
	)

---------------------------------------------------------------------
-- TAB / OPEN STATE
---------------------------------------------------------------------

local function selectTab(
	tabName: string
)
	if not pages[tabName] then
		return
	end

	activeTab =
		tabName

	for name,
		page in pairs(
			pages
		) do
		page.Visible =
			name == tabName
	end

	for name,
		button in pairs(
			navButtons
		) do
		button.BackgroundColor3 =
			name == tabName
			and C.AccentSoft
			or C.Panel3
	end

	if tabName ==
		"Character" then

		refreshCharacter()

	elseif tabName ==
		"Techniques"
		and refreshTechniques then

		refreshTechniques()

	elseif tabName ==
		"Loadout"
		and refreshLoadout then

		refreshLoadout()

	elseif tabName ==
		"Inventory" then

		refreshInventory()

	elseif tabName ==
		"Ninja Bag" then

		refreshNinjaBag()

	elseif tabName ==
		"Equipment" then

		refreshEquipment()
	end
end

for tabName,
	button in pairs(
		navButtons
	) do

	button.Activated:
		Connect(
			function()
				selectTab(
					tabName
				)
			end
		)
end

local function setOpen(
	open: boolean
)
	if isOpen ==
		open then

		return
	end

	if open then
		local hardBlock =
			getHardBlockReason()

		if hardBlock then
			warn(
				"[InventoryController] Menu blocked:",
				hardBlock
			)

			return
		end
	end

	isOpen =
		open

	player:SetAttribute(
		"InventoryOpen",
		open
	)

	player:SetAttribute(
		"NinjaBagLoadoutOpen",
		open
	)

	if open then
		previousMouseBehavior =
			UserInputService.MouseBehavior

		previousMouseIconEnabled =
			UserInputService.MouseIconEnabled

		UserInputService.MouseBehavior =
			Enum.MouseBehavior.Default

		UserInputService.MouseIconEnabled =
			true

		gui.Enabled =
			true

		main.Position =
			UDim2.fromScale(
				0.5,
				0.515
			)

		TweenService:
			Create(
				main,
				TweenInfo.new(
					0.14,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					Position =
					UDim2.fromScale(
						0.5,
						0.5
					),
				}
			):
			Play()

		selectTab(
			activeTab
		)

	else
		closePicker()

		gui.Enabled =
			false

		UserInputService.MouseBehavior =
			previousMouseBehavior

		UserInputService.MouseIconEnabled =
			previousMouseIconEnabled
	end
end

close.Activated:
	Connect(
		function()
			setOpen(
				false
			)
		end
	)

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)
			if gameProcessed then
				return
			end

			if UserInputService:
				GetFocusedTextBox() then

				return
			end

			if input.KeyCode ==
				TOGGLE_KEY then

				setOpen(
					not isOpen
				)
			end
		end
	)

local watchedAttributes = {
	"CharacterLevel",
	"CharacterTotalXP",
	"CharacterXPIntoLevel",
	"CharacterXPRequired",
	"NinjaRank",
	"NinjaRankDisplayName",
	"OriginVillageId",
	"AffiliationVillageId",
	"IsRogue",
	"ClanId",
	"ClanDisplayName",
	"Nature1Id",
	"Nature2Id",
	"Nature3Id",
	"PrimaryNatureId",
	"NatureUnlocked_Fire",
	"NatureUnlocked_Wind",
	"NatureUnlocked_Lightning",
	"NatureUnlocked_Earth",
	"NatureUnlocked_Water",
	"NaturalKGAvailable",
	"NaturalKGId",
	"CharacterSlotId",
	"InventoryPersistenceReady",
}

for _, attributeName in ipairs(
	watchedAttributes
	) do
	player:GetAttributeChangedSignal(
		attributeName
	):
		Connect(
			function()
				if isOpen
					and activeTab
					== "Character" then

					refreshCharacter()
				end
			end
		)
end

local function refreshActiveInventoryPage()
	if not isOpen then
		return
	end

	if activeTab ==
		"Inventory" then

		refreshInventory()

	elseif activeTab ==
		"Ninja Bag" then

		refreshNinjaBag()

	elseif activeTab ==
		"Equipment" then

		refreshEquipment()
	end
end

for _, item in ipairs(
	InventoryCatalog.GetAllItems()
	) do
	player:
		GetAttributeChangedSignal(
			"InventoryAmount_"
			.. item.Id
		):
		Connect(
			refreshActiveInventoryPage
		)

	if item.EquipmentSlot ==
		"Armor" then

		player:
			GetAttributeChangedSignal(
				"EquipmentDurability_"
				.. item.Id
			):
			Connect(
				refreshActiveInventoryPage
			)
	end
end

for _, definition in ipairs(
	InventoryCatalog.EquipmentSlots
	) do
	player:
		GetAttributeChangedSignal(
			"Equipped"
			.. definition.Id
		):
		Connect(
			refreshActiveInventoryPage
		)
end

for slotIndex = 1, 4 do
	player:
		GetAttributeChangedSignal(
			"NinjaBagSlot"
			.. tostring(
				slotIndex
			)
			.. "Projectile"
		):
		Connect(
			refreshActiveInventoryPage
		)
end

player:
	GetAttributeChangedSignal(
		"NinjaBagCapacity"
	):
	Connect(
		refreshActiveInventoryPage
	)

player:
	GetAttributeChangedSignal(
		"NinjaBagUsedCapacity"
	):
	Connect(
		refreshActiveInventoryPage
	)

local loadoutRefreshQueued =
	false

local function refreshActiveLoadoutPage()
	if loadoutRefreshQueued then
		return
	end

	if not isOpen
		or activeTab ~=
		"Loadout"
		or not refreshLoadout then

		return
	end

	loadoutRefreshQueued =
		true

	task.defer(
		function()
			loadoutRefreshQueued =
				false

			if isOpen
				and activeTab ==
				"Loadout"
				and refreshLoadout then

				refreshLoadout()
			end
		end
	)
end

player:
	GetAttributeChangedSignal(
		"TechniqueLoadoutReady"
	):
	Connect(
		refreshActiveLoadoutPage
	)

for slotIndex = 1, 10 do
	player:
		GetAttributeChangedSignal(
			"TechniqueLoadoutSlot_"
			.. tostring(
				slotIndex
			)
		):
		Connect(
			refreshActiveLoadoutPage
		)
end

local function connectLearnedFolder(
	folder: Instance
)
	folder.ChildAdded:
		Connect(
			function()
				if not isOpen then
					return
				end

				if activeTab ==
					"Techniques"
					and refreshTechniques then

					refreshTechniques()

				elseif activeTab ==
					"Loadout"
					and refreshLoadout then

					refreshLoadout()
				end
			end
		)

	folder.ChildRemoved:
		Connect(
			function()
				if not isOpen then
					return
				end

				if activeTab ==
					"Techniques"
					and refreshTechniques then

					refreshTechniques()

				elseif activeTab ==
					"Loadout"
					and refreshLoadout then

					refreshLoadout()
				end
			end
		)
end

local learnedFolder =
	player:FindFirstChild(
		"LearnedTechniques"
	)

if learnedFolder then
	connectLearnedFolder(
		learnedFolder
	)
end

player.ChildAdded:
	Connect(
		function(
			child: Instance
		)
			if child.Name ==
				"LearnedTechniques"
				and child:IsA(
					"Folder"
				) then

				connectLearnedFolder(
					child
				)
			end
		end
	)

player:SetAttribute(
	"InventoryOpen",
	false
)

player:SetAttribute(
	"NinjaBagLoadoutOpen",
	false
)

selectTab(
	"Character"
)

refreshCharacter()

print(
	"[InventoryController] READY v5 SplitShinobiMenu"
		.. " | Toggle=M"
		.. " | Character=ON"
		.. " | TechniquesUnlock=ON"
		.. " | TechniqueLoadout=10"
		.. " | LoadoutPersistence=ON"
		.. " | LearnedOnly=ON"
		.. " | Inventory=SEPARATE_TAB_HUD"
		.. " | CombatTagReadOnly=ON"
		.. " | PersistenceAware=ON"
)
