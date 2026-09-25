--!nocheck
-- WAYLESS Inventory v4.1 — ASTRA FINAL-14 STRICT + POLISH
-- StarterPlayer > StarterPlayerScripts > InventoryBandsHUD
--
-- Rebuilt against WAYLESS_Inventario_FINAL.zip as the sole visual source of truth:
--   layout.json
--   design.json
--   palette.json
--   popovers/layout.json
--   popovers/design.json
--   popovers/ninja_bag_picker.json
--   scroll/design.json
--
-- Backend compatibility retained with the existing WAYLESS inventory,
-- equipment, ninja bag and item-action remotes.
-- v4.1 adds motion polish and an optional sound palette without changing FINAL-14 geometry.

local App = {}
local S = {
	Players = game:GetService("Players"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	UserInputService = game:GetService("UserInputService"),
	ContextActionService = game:GetService("ContextActionService"),
	TweenService = game:GetService("TweenService"),
	TextService = game:GetService("TextService"),
	RunService = game:GetService("RunService"),
}

S.player = S.Players.LocalPlayer
S.playerGui = S.player:WaitForChild("PlayerGui")
S.catalog = require(S.ReplicatedStorage:WaitForChild("InventoryCatalog"))
S.rawAssets = require(S.ReplicatedStorage:WaitForChild("InventoryHUDAssets"))

local UISounds = nil
do
	local soundModule = S.ReplicatedStorage:FindFirstChild("InventoryUISounds")
	if soundModule and soundModule:IsA("ModuleScript") then
		local ok, result = pcall(require, soundModule)
		if ok and typeof(result) == "table" then
			UISounds = result
		else
			warn("[InventoryBandsHUD] InventoryUISounds could not be loaded:", result)
		end
	end
end

local function assetReady(v)
	return typeof(v) == "string" and v ~= "" and v ~= "rbxassetid://0"
end

local function resolveAsset(primary, fallback)
	if assetReady(primary) then return primary end
	if assetReady(fallback) then return fallback end
	return ""
end

local R = S.rawAssets
local F = R.Final or {}
local FC = F.Components or {}
local FI = F.Icons or {}
local FT = F.Titles or {}
local FG = F.Guides or {}
local FS = F.Scroll or {}
local FP = F.Popovers or {}

local A = {
	Components = {
		CategoryBand = resolveAsset(FC.CategoryBand, R.Components.CategoryBand),
		IdentityBand = resolveAsset(FC.IdentityBand, R.Components.IdentityBand),
		BagBand = resolveAsset(FC.BagBand, R.Components.BagBand),
		EquipmentBand = resolveAsset(FC.EquipmentBand, R.Components.EquipmentBand),
		SearchField = resolveAsset(FC.SearchField, R.Components.SearchField),
		Keycap = resolveAsset(FC.Keycap, R.Components.Keycap),
		PortraitFrame = resolveAsset(FC.PortraitFrame, ""),
		XPBackground = resolveAsset(FC.XPBackground, ""),
		XPFill = resolveAsset(FC.XPFill, ""),
	},
	Titles = {
		Inventory = resolveAsset(FT.Inventory, ""),
		Character = resolveAsset(FT.Character, ""),
		NinjaBag = resolveAsset(FT.NinjaBag, ""),
		Equipment = resolveAsset(FT.Equipment, ""),
		Weapons = resolveAsset(FT.Weapons, ""),
		EquipmentCategory = resolveAsset(FT.EquipmentCategory, ""),
		Consumables = resolveAsset(FT.Consumables, ""),
		Materials = resolveAsset(FT.Materials, ""),
	},
	Icons = {
		Search = resolveAsset(FI.Search, R.Icons.Search),
		Close = resolveAsset(FI.Close, R.Icons.Close),
		Village = resolveAsset(FI.Village, R.Icons.Village),
		Weapon = resolveAsset(FI.Weapon, R.Icons.Weapon),
		Headband = resolveAsset(FI.Headband, R.Icons.Headband),
		Armor = resolveAsset(FI.Armor, R.Icons.Armor),
		Mask = resolveAsset(FI.Mask, R.Icons.Mask),
		Cloak = resolveAsset(FI.Cloak, R.Icons.Cloak),
		HeadAccessory = resolveAsset(FI.HeadAccessory, R.Icons.HeadAccessory),
		OffHand = resolveAsset(FI.OffHand, R.Icons.OffHand),
		Accessories = resolveAsset(FI.Accessories, R.Icons.Accessories),
		Bag = resolveAsset(FI.Bag, R.Icons.Bag),
		Consumables = resolveAsset(FI.Consumables, R.Icons.Consumables),
		Materials = resolveAsset(FI.Materials, R.Icons.Materials),
		Scroll = resolveAsset(FI.Scroll, ""),
		Shuriken = resolveAsset(FI.Shuriken, ""),
		Herb = resolveAsset(FI.Herb, ""),
	},
	Guides = {
		Weapon = resolveAsset(FG.Weapon, R.Icons.Weapon),
		Headband = resolveAsset(FG.Headband, R.Icons.Headband),
		Armor = resolveAsset(FG.Armor, R.Icons.Armor),
		Mask = resolveAsset(FG.Mask, R.Icons.Mask),
		Cloak = resolveAsset(FG.Cloak, R.Icons.Cloak),
		HeadAccessory = resolveAsset(FG.HeadAccessory, R.Icons.HeadAccessory),
		OffHand = resolveAsset(FG.OffHand, R.Icons.OffHand),
		Accessories = resolveAsset(FG.Accessories, R.Icons.Accessories),
		Throwables = resolveAsset(FG.Throwables, resolveAsset(FG.Bag, R.Icons.Bag)),
		Consumables = resolveAsset(FG.Consumables, R.Icons.Consumables),
		Materials = resolveAsset(FG.Materials, R.Icons.Materials),
		Scroll = resolveAsset(FG.Scroll, ""),
	},
	Scroll = {
		Top = resolveAsset(FS.RuleLeft, ""),
		Bottom = resolveAsset(FS.RuleRight, ""),
		Thumb = resolveAsset(FS.Thumb, R.Components.ScrollThumb),
	},
	Pop = {
		Washi = resolveAsset(FP.WashiSurface, R.Popovers.WashiSurface),
		Frame = resolveAsset(FP.PanelFrame, R.Popovers.PanelFrame),
		Divider = resolveAsset(FP.Divider, R.Popovers.Divider),
		RowNormal = resolveAsset(FP.RowNormal, R.Popovers.RowNormal),
		RowHover = resolveAsset(FP.RowHover, R.Popovers.RowHover),
		RowPressed = resolveAsset(FP.RowPressed, R.Popovers.RowPressed),
		RowDisabled = resolveAsset(FP.RowDisabled, R.Popovers.RowDisabled),
		RowDangerHover = resolveAsset(FP.RowDangerHover, R.Popovers.RowDangerHover),
		Lock = resolveAsset(FP.Lock, R.Popovers.Lock),
		Unlock = resolveAsset(FP.Unlock, R.Popovers.Unlock),
		Drop = resolveAsset(FP.Drop, R.Popovers.Drop),
		Equip = resolveAsset(FP.Equip, R.Popovers.Equip),
		Consume = resolveAsset(FP.Consume, R.Popovers.Consume),
		CategoryWeapons = resolveAsset(FP.CategoryWeapons, ""),
		CategoryEquipment = resolveAsset(FP.CategoryEquipment, ""),
		CategoryConsumables = resolveAsset(FP.CategoryConsumables, ""),
		CategoryMaterials = resolveAsset(FP.CategoryMaterials, ""),
		PickerTL = resolveAsset(FP.PickerTL, ""),
		PickerTR = resolveAsset(FP.PickerTR, ""),
		PickerBL = resolveAsset(FP.PickerBL, ""),
		PickerBR = resolveAsset(FP.PickerBR, ""),
		RuleLeft = resolveAsset(FP.RuleLeft, ""),
		RuleRight = resolveAsset(FP.RuleRight, ""),
		TipCornerTL = resolveAsset(FP.TipCornerTL, ""),
		TipCornerBR = resolveAsset(FP.TipCornerBR, ""),
		TipRuleEnd = resolveAsset(FP.TipRuleEnd, ""),
	},
}

A.Slots = {
	weapons = FC.Weapons or {},
	equipment = FC.Equipment or {},
	consumables = FC.Consumables or {},
	materials = FC.Materials or {},
}

local CFG = {
	CanvasW = 1920,
	CanvasH = 1080,
	MinScale = 0.69,
	TooltipDelay = 0.45,
	Colors = {
		Text = Color3.fromRGB(231, 223, 205),
		SubText = Color3.fromRGB(182, 170, 148),
		Ink = Color3.fromRGB(52, 49, 40),
		InkSecondary = Color3.fromRGB(123, 112, 89),
		Danger = Color3.fromRGB(163, 83, 73),
		Disabled = Color3.fromRGB(170, 160, 140),
		Parchment = Color3.fromRGB(188, 162, 118),
		Weapons = Color3.fromRGB(131, 185, 214),
		Equipment = Color3.fromRGB(143, 198, 160),
		Consumables = Color3.fromRGB(228, 191, 113),
		Materials = Color3.fromRGB(212, 159, 135),
	},
	Categories = {
		{Id="weapons", Label="Weapons", Title="Weapons", TitleW=132},
		{Id="equipment", Label="Equipment", Title="EquipmentCategory", TitleW=150},
		{Id="consumables", Label="Consumables", Title="Consumables", TitleW=170},
		{Id="materials", Label="Materials", Title="Materials", TitleW=140},
	},
	Village = {
		Leaf = "Hidden Leaf", Sand = "Hidden Sand", Mist = "Hidden Mist",
		Cloud = "Hidden Cloud", Stone = "Hidden Stone",
	},
	Equipment = {
		{Id="weapon", Label="Weapon", X=1570, Y=502, LabelY=577, Guide="Weapon", ServerSlot="Weapon", Mutable=true},
		{Id="headband", Label="Headband", X=1648, Y=502, LabelY=577, Guide="Headband", ServerSlot="Headband"},
		{Id="armor", Label="Armor", X=1726, Y=502, LabelY=577, Guide="Armor", ServerSlot="Armor", Mutable=true},
		{Id="mask", Label="Mask", X=1804, Y=502, LabelY=577, Guide="Mask", ServerSlot="Mask"},
		{Id="cloak", Label="Cloak", X=1570, Y=604, LabelY=679, Guide="Cloak", ServerSlot="Cloak"},
		{Id="head_accessory", Label="Head acc.", X=1648, Y=604, LabelY=679, Guide="HeadAccessory", ServerSlot="HeadAccessory"},
		{Id="off_hand", Label="Off hand", X=1726, Y=604, LabelY=679, Guide="OffHand", ServerSlot="OffHand"},
		{Id="accessories", Label="Accessories", X=1804, Y=604, LabelY=679, Guide="Accessories", ServerSlot="Accessories"},
	},
}

-- FINAL-14 embedded layout constants. These values are transcribed directly
-- from Astra's JSON manifests. Runtime-only behavior (data bindings/remotes) lives
-- outside this table; visual geometry should not drift from these values.
local FINAL14 = {
	Canvas = { W=1920, H=1080 },
	Inventory = { X=28, Y=130, W=520, H=868, HeaderH=51, Columns=7, Cell=64, GapX=7, GapY=12, SectionGap=12, FooterH=17 },
	Search = { X=28, Y=72, W=520, H=40 },
	Identity = { X=1556, Y=80, W=336, H=166, PortraitX=1570, PortraitY=126, PortraitW=68, PortraitH=68 },
	Bag = { X=1556, Y=272, W=336, H=146 },
	Equipment = { X=1556, Y=444, W=336, H=270 },
	Popover = {
		SurfaceOpacity=0.85,
		Tooltip={ W=340, MinW=240, MaxW=360, Margin=16, Gap=12, Padding=18, Title=22, TitleLine=28, Category=11, CategoryLine=16, CategoryGap=5, Desc=18, DescLine=25, DescGap=13, Locked=14, LockedLine=20, LockedGap=12 },
		Context={ W=232, MinW=200, MaxW=300, Padding=8, RowH=40, IconX=12, IconY=10, IconW=20, IconH=20, LabelX=44, RightPad=12, SeparatorTop=4, SeparatorBottom=4 },
		Picker={ W=272, MaxRows=5, RowH=48, HeaderH=40, FooterH=36, Thumb=32 },
	},
}

local UI = {}
local State = {
	LastXP = nil,
	LastLevel = nil,
	XPAnimToken = 0,
	Open = false,
	Search = "",
	TooltipToken = 0,
	HoveredItemId = nil,
	ContextItemId = nil,
	PickerSlot = nil,
	PickerPending = false,
	PendingAction = false,
	FeedbackToken = 0,
	AnimationToken = 0,
	EdgeOffset = 0,
	Scale = 1,
	TabDown = false,
	LastToggle = -math.huge,
}

local Remotes = {}
do
	local eq = S.ReplicatedStorage:WaitForChild("EquipmentRemotes")
	Remotes.EquipRequest = eq:WaitForChild("EquipRequest")
	Remotes.EquipResult = eq:WaitForChild("EquipResult")
	local nb = S.ReplicatedStorage:WaitForChild("NinjaBagRemotes")
	Remotes.BagRequest = nb:WaitForChild("EquipRequest")
	Remotes.BagResult = nb:WaitForChild("EquipResult")
	local ar = S.ReplicatedStorage:FindFirstChild("InventoryActionRemotes")
	Remotes.ActionRequest = ar and ar:FindFirstChild("RequestAction") or nil
	if Remotes.ActionRequest and not Remotes.ActionRequest:IsA("RemoteFunction") then
		Remotes.ActionRequest = nil
	end
end

-- --------------------------------------------------------------------------
-- Data helpers
-- --------------------------------------------------------------------------
function App.amountAttr(itemId) return "InventoryAmount_" .. itemId end
function App.lockAttr(itemId) return "InventoryLocked_" .. itemId end
function App.equippedAttr(slotId) return "Equipped" .. slotId end
function App.bagAttr(i) return "NinjaBagSlot" .. tostring(i) .. "Projectile" end

function App.getAmount(itemId)
	local n = S.player:GetAttribute(App.amountAttr(itemId))
	return typeof(n) == "number" and math.max(0, math.floor(n)) or 0
end

function App.getEquipped(slotId)
	local v = S.player:GetAttribute(App.equippedAttr(slotId))
	return typeof(v) == "string" and v ~= "" and v or nil
end

function App.getBag(i)
	local v = S.player:GetAttribute(App.bagAttr(i))
	return typeof(v) == "string" and v ~= "" and v or nil
end

function App.isLocked(itemId)
	return S.player:GetAttribute(App.lockAttr(itemId)) == true
end

function App.firstString(names)
	for _, name in ipairs(names) do
		local v = S.player:GetAttribute(name)
		if typeof(v) == "string" and v ~= "" then return v end
	end
	return nil
end

function App.firstNumber(names)
	for _, name in ipairs(names) do
		local v = S.player:GetAttribute(name)
		if typeof(v) == "number" then return v end
	end
	return nil
end

function App.characterInfo()
	local villageRaw = App.firstString({"AffiliationVillageId","OriginVillageId","VillageId","Village","VillageName"})
	return {
		GivenName = App.firstString({"CharacterGivenName","GivenName","CharacterName","FirstName","Name"}) or S.player.DisplayName,
		Surname = App.firstString({"CharacterSurname","Surname","FamilyName","LastName","ClanSurname","ClanDisplayName","ClanId"}) or "",
		Level = App.firstNumber({"CharacterLevel","Level"}) or 1,
		Village = CFG.Village[villageRaw] or villageRaw or "Unknown",
		Rank = App.firstString({"NinjaRankDisplayName","NinjaRank"}) or "Academy Student",
		XP = math.max(0, math.floor(App.firstNumber({"CharacterXPIntoLevel"}) or 0)),
		XPRequired = math.max(0, math.floor(App.firstNumber({"CharacterXPRequired"}) or 0)),
	}
end

function App.category(item)
	if item.Category == "Weapons" then return "weapons" end
	if item.Category == "Armor" or item.EquipmentSlot == "Armor" then return "equipment" end
	if item.Category == "Consumables" or item.Kind == "Consumable" then return "consumables" end
	if item.EquipmentSlot and item.EquipmentSlot ~= "Weapon" then return "equipment" end
	if item.NinjaBagEquippable == true then return "weapons" end
	if item.Category == "Tools" then return "consumables" end
	return "materials"
end

function App.categoryDisplay(id)
	for _, c in ipairs(CFG.Categories) do
		if c.Id == id then return c.Label end
	end
	return id
end

function App.categoryColor(id)
	if id == "weapons" then return CFG.Colors.Weapons end
	if id == "equipment" then return CFG.Colors.Equipment end
	if id == "consumables" then return CFG.Colors.Consumables end
	return CFG.Colors.Materials
end

function App.categoryAccent(id)
	if id == "weapons" then return A.Pop.CategoryWeapons end
	if id == "equipment" then return A.Pop.CategoryEquipment end
	if id == "consumables" then return A.Pop.CategoryConsumables end
	return A.Pop.CategoryMaterials
end

function App.realThumbnail(item)
	for _, key in ipairs({"Thumbnail","ThumbnailImage","Image","Icon"}) do
		local v = item[key]
		if assetReady(v) then return v end
	end
	return nil
end

function App.guideFor(item)
	local slot = tostring(item.EquipmentSlot or "")
	if slot == "Weapon" then return A.Guides.Weapon end
	if slot == "Armor" then return A.Guides.Armor end
	if slot == "Headband" then return A.Guides.Headband end
	if slot == "Mask" then return A.Guides.Mask end
	if slot == "Cloak" then return A.Guides.Cloak end
	if item.NinjaBagEquippable == true then return A.Guides.Throwables end
	local cat = App.category(item)
	if cat == "equipment" then return A.Guides.Armor end
	if cat == "consumables" then return A.Guides.Consumables end
	if cat == "materials" then return A.Guides.Materials end
	return A.Guides.Weapon
end

function App.fallbackItemIcon(item)
	local real = App.realThumbnail(item)
	if real then return real end
	local cat = App.category(item)
	if item.NinjaBagEquippable == true and assetReady(A.Icons.Shuriken) then return A.Icons.Shuriken end
	if cat == "weapons" then return A.Icons.Weapon end
	if cat == "equipment" then return A.Icons.Armor end
	if cat == "consumables" then return A.Icons.Consumables end
	return A.Icons.Materials
end

function App.isCharacterEquipped(itemId)
	for _, e in ipairs(CFG.Equipment) do
		if App.getEquipped(e.ServerSlot) == itemId then return true end
	end
	return false
end

function App.canEquip(item)
	return item.EquipmentSlot == "Weapon" or item.EquipmentSlot == "Armor"
end
function App.canConsume(item)
	return item.Kind == "Consumable" or item.Category == "Consumables" or item.Consumable == true
end
function App.canDrop(item)
	return item.NoDrop ~= true and App.getAmount(item.Id) > 0
end
function App.canBag(item)
	return item.NinjaBagEquippable == true
end

function App.getOwned()
	local out = {}
	for _, item in ipairs(S.catalog.GetAllItems()) do
		if App.getAmount(item.Id) > 0 or App.isCharacterEquipped(item.Id) then
			table.insert(out, item)
		end
	end
	table.sort(out, function(a,b)
		local ca, cb = App.category(a), App.category(b)
		if ca == cb then return tostring(a.DisplayName or a.Id) < tostring(b.DisplayName or b.Id) end
		return ca < cb
	end)
	return out
end

function App.itemState(itemId)
	local item = S.catalog.GetItem(itemId)
	if not item then return nil end
	return {
		Id=itemId,
		Item=item,
		Name=tostring(item.DisplayName or item.Id),
		Category=App.category(item),
		Description=tostring(item.Description or ""),
		Quantity=App.getAmount(itemId),
		CanEquip=App.canEquip(item),
		IsEquipped=App.isCharacterEquipped(itemId),
		CanConsume=App.canConsume(item),
		CanDrop=App.canDrop(item),
		IsLocked=App.isLocked(itemId),
	}
end

-- --------------------------------------------------------------------------
-- Generic UI helpers
-- --------------------------------------------------------------------------
function App.image(parent, name, image, x,y,w,h,z)
	local o = Instance.new("ImageLabel")
	o.Name = name or "Image"
	o.BackgroundTransparency = 1
	o.BorderSizePixel = 0
	o.Image = image or ""
	o.Position = UDim2.fromOffset(x or 0, y or 0)
	o.Size = UDim2.fromOffset(w or 0, h or 0)
	o.ZIndex = z or 1
	o.Parent = parent
	return o
end

function App.text(parent, name, text, x,y,w,h,font,size,color,z)
	local o = Instance.new("TextLabel")
	o.Name = name or "Text"
	o.BackgroundTransparency = 1
	o.BorderSizePixel = 0
	o.Text = text or ""
	o.Position = UDim2.fromOffset(x or 0, y or 0)
	o.Size = UDim2.fromOffset(w or 0, h or 0)
	o.Font = font or Enum.Font.Garamond
	o.TextSize = size or 16
	o.TextColor3 = color or CFG.Colors.Text
	o.TextXAlignment = Enum.TextXAlignment.Left
	o.TextYAlignment = Enum.TextYAlignment.Center
	o.ZIndex = z or 1
	o.Parent = parent
	return o
end

function App.button(parent, name, x,y,w,h,z)
	local o = Instance.new("ImageButton")
	o.Name = name or "Button"
	o.BackgroundTransparency = 1
	o.BorderSizePixel = 0
	o.AutoButtonColor = false
	o.Position = UDim2.fromOffset(x or 0,y or 0)
	o.Size = UDim2.fromOffset(w or 0,h or 0)
	o.ZIndex = z or 1
	o.Parent = parent
	return o
end

function App.slotAsset(category, mode)
	local set = A.Slots[category] or {}
	local keyMap = {
		normal = "Normal",
		hover = "Hover",
		selected = "Selected",
		equipped = "Equipped",
		disabled = "Disabled",
		drop_valid = "DropValid",
		drop_invalid = "DropInvalid",
	}
	local v = set[keyMap[mode] or "Normal"]
	if assetReady(v) then return v end
	if assetReady(set.Normal) then return set.Normal end
	local map = {
		normal = resolveAsset(FC.SlotNormal, R.Components.SlotNormal),
		hover = resolveAsset(FC.SlotHover, R.Components.SlotHover),
		selected = resolveAsset(FC.SlotSelected, R.Components.SlotSelected),
		equipped = resolveAsset(FC.SlotEquipped, R.Components.SlotEquipped),
		disabled = resolveAsset(FC.SlotDisabled, R.Components.SlotDisabled),
		drop_valid = resolveAsset(FC.SlotDropValid, R.Components.SlotDropValid),
		drop_invalid = resolveAsset(FC.SlotDropInvalid, R.Components.SlotDropInvalid),
	}
	return map[mode] or map.normal
end

function App.setSlot(button, category, mode)
	button:SetAttribute("InventoryCategory", category)
	button:SetAttribute("InventoryMode", mode)
	button.Image = App.slotAsset(category, mode)
end

-- --------------------------------------------------------------------------
-- v4.1 polish helpers — visual geometry always returns to FINAL-14 values
-- --------------------------------------------------------------------------
function App.playSound(eventName)
	if UISounds and typeof(UISounds.Play) == "function" then
		pcall(UISounds.Play, eventName)
	end
end

function App.tweenVisual(gui, position, size, duration, style, direction)
	if not gui or not gui.Parent then return end
	S.TweenService:Create(
		gui,
		TweenInfo.new(duration or 0.1, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		{Position=position, Size=size}
	):Play()
end

function App.slotContentHover(button, entering)
	-- v4.1.1: restore the approved feel from the earlier HUD polish pass:
	-- the WHOLE slot lifts/scales on hover, not only its thumbnail/guide.
	-- Geometry still returns to FINAL-14 values on MouseLeave.
	local scale=button:FindFirstChild("PolishHoverScale")
	if not scale then
		scale=Instance.new("UIScale")
		scale.Name="PolishHoverScale"
		scale.Scale=1
		scale.Parent=button
	end
	local target=entering and 1.045 or 1
	S.TweenService:Create(
		scale,
		TweenInfo.new(0.10,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Scale=target}
	):Play()
end

function App.slotContentPress(button)
	for _,name in ipairs({"Guide","Thumbnail"}) do
		local visual=button:FindFirstChild(name)
		if visual and visual:IsA("GuiObject") then
			App.tweenVisual(visual,UDim2.fromOffset(9,7),UDim2.fromOffset(46,46),0.045,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
			task.delay(0.05,function()
				if visual.Parent then
					App.tweenVisual(visual,UDim2.fromOffset(8,6),UDim2.fromOffset(48,48),0.075,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
				end
			end)
		end
	end
end

function App.pulseButton(button)
	if not button or not button.Parent then return end
	local scale=button:FindFirstChild("PolishPulseScale")
	if not scale then
		scale=Instance.new("UIScale")
		scale.Name="PolishPulseScale"
		scale.Scale=1
		scale.Parent=button
	end
	scale.Scale=0.92
	S.TweenService:Create(scale,TweenInfo.new(0.10,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.045}):Play()
	task.delay(0.11,function()
		if scale.Parent then
			S.TweenService:Create(scale,TweenInfo.new(0.09,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1}):Play()
		end
	end)
end

function App.shakeButton(button)
	if not button or not button.Parent then return end
	local original=button.Position
	local x=original.X.Offset; local y=original.Y.Offset
	local seq={-3,3,-2,2,0}
	for i,dx in ipairs(seq) do
		task.delay((i-1)*0.035,function()
			if button.Parent then button.Position=UDim2.fromOffset(x+dx,y) end
		end)
	end
end

function App.measure(text, size, width, font)
	return S.TextService:GetTextSize(text, size, font or Enum.Font.Garamond, Vector2.new(width, 1000))
end

-- --------------------------------------------------------------------------
-- Root + scale + edge anchoring
-- --------------------------------------------------------------------------
function App.buildRoot()
	local old = S.playerGui:FindFirstChild("WAYLESSInventoryBandsHUD")
	if old then old:Destroy() end

	UI.Gui = Instance.new("ScreenGui")
	UI.Gui.Name = "WAYLESSInventoryBandsHUD"
	UI.Gui.ResetOnSpawn = false
	UI.Gui.IgnoreGuiInset = true
	UI.Gui.DisplayOrder = 42
	UI.Gui.Enabled = false
	UI.Gui.Parent = S.playerGui

	UI.Root = Instance.new("Frame")
	UI.Root.BackgroundTransparency = 1
	UI.Root.Size = UDim2.fromScale(1,1)
	UI.Root.Parent = UI.Gui

	UI.Canvas = Instance.new("Frame")
	UI.Canvas.Name = "ReferenceCanvas"
	UI.Canvas.AnchorPoint = Vector2.new(0.5,0.5)
	UI.Canvas.Position = UDim2.fromScale(0.5,0.5)
	UI.Canvas.Size = UDim2.fromOffset(CFG.CanvasW, CFG.CanvasH)
	UI.Canvas.BackgroundTransparency = 1
	UI.Canvas.Parent = UI.Root

	UI.Scale = Instance.new("UIScale")
	UI.Scale.Parent = UI.Canvas

	UI.LeftGroup = Instance.new("CanvasGroup")
	UI.LeftGroup.Name = "LeftBand"
	UI.LeftGroup.BackgroundTransparency = 1
	UI.LeftGroup.Size = UDim2.fromScale(1,1)
	UI.LeftGroup.GroupTransparency = 0
	UI.LeftGroup.Parent = UI.Canvas

	UI.RightGroup = Instance.new("CanvasGroup")
	UI.RightGroup.Name = "RightBand"
	UI.RightGroup.BackgroundTransparency = 1
	UI.RightGroup.Size = UDim2.fromScale(1,1)
	UI.RightGroup.GroupTransparency = 0
	UI.RightGroup.Parent = UI.Canvas

	UI.Overlay = Instance.new("Frame")
	UI.Overlay.Name = "FloatingUI"
	UI.Overlay.BackgroundTransparency = 1
	UI.Overlay.Size = UDim2.fromScale(1,1)
	UI.Overlay.ZIndex = 40
	UI.Overlay.Parent = UI.Canvas

	UI.Feedback = Instance.new("TextLabel")
	UI.Feedback.BackgroundTransparency = 1
	UI.Feedback.AnchorPoint = Vector2.new(0.5,1)
	UI.Feedback.Position = UDim2.fromScale(0.5,0.88)
	UI.Feedback.Size = UDim2.fromOffset(520,28)
	UI.Feedback.Font = Enum.Font.Garamond
	UI.Feedback.TextSize = 18
	UI.Feedback.TextColor3 = CFG.Colors.Text
	UI.Feedback.TextStrokeTransparency = 0.55
	UI.Feedback.TextTransparency = 1
	UI.Feedback.ZIndex = 200
	UI.Feedback.Parent = UI.Root
end

function App.updateScale()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local vp = camera.ViewportSize
	local raw = math.min(vp.X/CFG.CanvasW, vp.Y/CFG.CanvasH)
	local scale = math.max(CFG.MinScale, raw)
	State.Scale = scale
	UI.Scale.Scale = scale

	local visibleRefW = vp.X / scale
	local offset = math.max(0, (visibleRefW - CFG.CanvasW) * 0.5)
	State.EdgeOffset = offset
	UI.LeftGroup.Position = UDim2.fromOffset(-offset, 0)
	UI.RightGroup.Position = UDim2.fromOffset(offset, 0)
end

-- --------------------------------------------------------------------------
-- Left inventory — exact layout.json geometry
-- --------------------------------------------------------------------------
function App.buildLeft()
	UI.InventoryTitle = App.image(UI.LeftGroup,"InventoryTitle",A.Titles.Inventory,28,26,190,31,4)
	if not assetReady(A.Titles.Inventory) then
		UI.InventoryTitle.Visible = false
		UI.InventoryTitleText = App.text(UI.LeftGroup,"InventoryTitleText","INVENTORY",28,26,520,30,Enum.Font.Garamond,22,CFG.Colors.Text,4)
	end

	UI.Search = App.image(UI.LeftGroup,"SearchField",A.Components.SearchField,28,72,520,40,3)
	UI.SearchIcon = App.image(UI.Search,"SearchIcon",A.Icons.Search,10,8,24,24,4)
	UI.SearchBox = Instance.new("TextBox")
	UI.SearchBox.BackgroundTransparency = 1
	UI.SearchBox.ClearTextOnFocus = false
	UI.SearchBox.PlaceholderText = "Search items…"
	UI.SearchBox.PlaceholderColor3 = CFG.Colors.SubText
	UI.SearchBox.TextColor3 = CFG.Colors.Text
	UI.SearchBox.Text = ""
	UI.SearchBox.Position = UDim2.fromOffset(40,0)
	UI.SearchBox.Size = UDim2.new(1,-48,1,0)
	UI.SearchBox.Font = Enum.Font.SourceSans
	UI.SearchBox.TextSize = 18
	UI.SearchBox.TextXAlignment = Enum.TextXAlignment.Left
	UI.SearchBox.ZIndex = 5
	UI.SearchBox.Parent = UI.Search

	UI.InventoryScroll = Instance.new("ScrollingFrame")
	UI.InventoryScroll.Name = "InventoryScroll"
	UI.InventoryScroll.BackgroundTransparency = 1
	UI.InventoryScroll.BorderSizePixel = 0
	UI.InventoryScroll.Position = UDim2.fromOffset(28,130)
	UI.InventoryScroll.Size = UDim2.fromOffset(520,868)
	UI.InventoryScroll.CanvasSize = UDim2.fromOffset(0,868)
	UI.InventoryScroll.ScrollBarThickness = 0
	UI.InventoryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	UI.InventoryScroll.ClipsDescendants = true
	UI.InventoryScroll.ZIndex = 2
	UI.InventoryScroll.Parent = UI.LeftGroup

	UI.InventoryContent = Instance.new("Frame")
	UI.InventoryContent.BackgroundTransparency = 1
	UI.InventoryContent.Size = UDim2.fromOffset(520,868)
	UI.InventoryContent.Parent = UI.InventoryScroll

	App.buildScrollChrome(UI.LeftGroup, "InventoryChrome", 551,130,864, UI.InventoryScroll, false)
end

function App.buildScrollChrome(parent, name, x,y,h, scrollingFrame, isPicker)
	local chrome = Instance.new("Frame")
	chrome.Name = name
	chrome.BackgroundTransparency = 1
	chrome.Position = UDim2.fromOffset(x,y)
	chrome.Size = UDim2.fromOffset(20,h)
	chrome.ZIndex = isPicker and 90 or 8
	chrome.Parent = parent

	local top = App.image(chrome,"Top",A.Scroll.Top,3.25,2,13.5,11,chrome.ZIndex+1)
	top.ScaleType = Enum.ScaleType.Fit
	local bottom = App.image(chrome,"Bottom",A.Scroll.Bottom,2.75,h-13,14.5,11,chrome.ZIndex+1)
	bottom.ScaleType = Enum.ScaleType.Fit

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = CFG.Colors.Parchment
	line.BackgroundTransparency = 0.74
	line.BorderSizePixel = 0
	line.Position = UDim2.fromOffset(10,15)
	line.Size = UDim2.fromOffset(1,h-30)
	line.ZIndex = chrome.ZIndex
	line.Parent = chrome

	local thumb = App.image(chrome,"Thumb",A.Scroll.Thumb,0,15,20,84,chrome.ZIndex+2)
	thumb.ScaleType = Enum.ScaleType.Slice
	thumb.SliceCenter = Rect.new(0,7,20,77)

	local drag = App.button(chrome,"ThumbHit",0,15,20,84,chrome.ZIndex+3)
	drag.ImageTransparency = 1

	local entry = {Root=chrome, Thumb=thumb, Drag=drag, Scroll=scrollingFrame, Height=h, Dragging=false, DragY=0, StartOffset=0}
	if isPicker then UI.PickerScrollChrome = entry else UI.InventoryScrollChrome = entry end

	local function update()
		local viewH = scrollingFrame.AbsoluteWindowSize.Y / math.max(State.Scale,0.001)
		if viewH <= 0 then viewH = scrollingFrame.Size.Y.Offset end
		local contentH = scrollingFrame.CanvasSize.Y.Offset
		local overflow = math.max(0, contentH - viewH)
		chrome.Visible = overflow > 0.5
		if overflow <= 0.5 then return end
		local usable = h - 30
		local thumbH = math.clamp(usable * (viewH/contentH),32,usable)
		local alpha = math.clamp(scrollingFrame.CanvasPosition.Y/overflow,0,1)
		local yy = 15 + (usable-thumbH)*alpha
		thumb.Position = UDim2.fromOffset(0,yy)
		thumb.Size = UDim2.fromOffset(20,thumbH)
		drag.Position = UDim2.fromOffset(0,yy)
		drag.Size = UDim2.fromOffset(20,thumbH)
	end
	entry.Update = update

	drag.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			entry.Dragging = true
			entry.DragY = input.Position.Y
			entry.StartOffset = scrollingFrame.CanvasPosition.Y
		end
	end)
	S.UserInputService.InputChanged:Connect(function(input)
		if not entry.Dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		local viewH = scrollingFrame.AbsoluteWindowSize.Y / math.max(State.Scale,0.001)
		local contentH = scrollingFrame.CanvasSize.Y.Offset
		local overflow = math.max(0,contentH-viewH)
		local usable = h-30
		local thumbH = thumb.Size.Y.Offset
		local travel = math.max(1,usable-thumbH)
		local deltaRef = (input.Position.Y-entry.DragY)/math.max(State.Scale,0.001)
		local newOffset = math.clamp(entry.StartOffset + (deltaRef/travel)*overflow,0,overflow)
		scrollingFrame.CanvasPosition = Vector2.new(0,newOffset)
	end)
	S.UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then entry.Dragging=false end
	end)
	scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
	scrollingFrame:GetPropertyChangedSignal("CanvasSize"):Connect(update)
	task.defer(update)
	return entry
end

function App.clearInventoryContent()
	for _, child in ipairs(UI.InventoryContent:GetChildren()) do child:Destroy() end
	UI.ItemButtons = {}
end

function App.buildCategoryBand(parent,name,y,h)
	local holder=Instance.new("Frame")
	holder.Name=name
	holder.BackgroundTransparency=1
	holder.BorderSizePixel=0
	holder.Position=UDim2.fromOffset(0,y)
	holder.Size=UDim2.fromOffset(520,h)
	holder.ClipsDescendants=true
	holder.ZIndex=2
	holder.Parent=parent

	-- category_band.png is authored at exactly 520x208. Astra explicitly says
	-- ornamental PNGs must not be compressed. At the authored 2-row height use
	-- the untouched source. For dynamic heights preserve the complete 45 px
	-- header and 23 px footer as fixed crops; only the neutral charcoal center
	-- grows/shrinks. This keeps the top-right cloud and bottom seal at native size.
	if h==208 then
		local full=App.image(holder,"Background",A.Components.CategoryBand,0,0,520,208,2)
		full.ScaleType=Enum.ScaleType.Stretch
	else
		local middle=Instance.new("Frame")
		middle.Name="NeutralCenter"
		middle.BackgroundColor3=Color3.fromRGB(20,20,20)
		middle.BackgroundTransparency=1-(122/255)
		middle.BorderSizePixel=0
		middle.Position=UDim2.fromOffset(1,45)
		middle.Size=UDim2.fromOffset(518,math.max(0,h-68))
		middle.ZIndex=2
		middle.Parent=holder

		local top=App.image(holder,"HeaderSlice",A.Components.CategoryBand,0,0,520,45,3)
		top.ScaleType=Enum.ScaleType.Stretch
		top.ImageRectOffset=Vector2.new(0,0)
		top.ImageRectSize=Vector2.new(520,45)

		local bottom=App.image(holder,"FooterSlice",A.Components.CategoryBand,0,h-23,520,23,3)
		bottom.ScaleType=Enum.ScaleType.Stretch
		bottom.ImageRectOffset=Vector2.new(0,185)
		bottom.ImageRectSize=Vector2.new(520,23)

		local borderColor=Color3.fromRGB(81,71,56)
		for _,x in ipairs({0,519}) do
			local side=Instance.new("Frame")
			side.Name=x==0 and "LeftBorder" or "RightBorder"
			side.BackgroundColor3=borderColor
			side.BackgroundTransparency=1-(150/255)
			side.BorderSizePixel=0
			side.Position=UDim2.fromOffset(x,45)
			side.Size=UDim2.fromOffset(1,math.max(0,h-68))
			side.ZIndex=3
			side.Parent=holder
		end
	end
	return holder
end

function App.renderInventory()
	App.clearInventoryContent()
	App.hideTooltip()
	App.hideContext()

	local search=string.lower(State.Search)
	local filtered={}
	for _,item in ipairs(App.getOwned()) do
		local hay=string.lower(tostring(item.DisplayName or item.Id).." "..tostring(item.Description or ""))
		if search=="" or string.find(hay,search,1,true) then table.insert(filtered,item) end
	end

	local y=0
	for _,c in ipairs(CFG.Categories) do
		local items={}
		for _,item in ipairs(filtered) do if App.category(item)==c.Id then table.insert(items,item) end end
		local rows=math.max(1,math.ceil(#items/FINAL14.Inventory.Columns))
		local sectionH=FINAL14.Inventory.HeaderH + rows*FINAL14.Inventory.Cell + math.max(0,rows-1)*FINAL14.Inventory.GapY + FINAL14.Inventory.FooterH

		local band=App.buildCategoryBand(UI.InventoryContent,c.Id.."Band",y,sectionH)

		-- These transforms reproduce Astra's approved 1920x1080 overlay exactly.
		-- The reference_art titles include their underline/spiral and intentionally
		-- sit over category_band's straight header rule.
		local titleAsset=A.Titles[c.Title]
		if assetReady(titleAsset) then
			local title=App.image(band,c.Id.."Title",titleAsset,25,4,c.TitleW,31,6)
			title.ScaleType=Enum.ScaleType.Stretch
		else
			App.text(band,c.Id.."TitleText",c.Label,14,9,480,25,Enum.Font.Garamond,20,CFG.Colors.Text,6)
		end

		if #items==0 then
			local empty=App.text(band,"Empty","No items",14,52,480,28,Enum.Font.SourceSans,14,CFG.Colors.SubText,6)
			empty.TextTransparency=0.25
		else
			for index,item in ipairs(items) do
				local col=(index-1)%FINAL14.Inventory.Columns
				local row=math.floor((index-1)/FINAL14.Inventory.Columns)
				App.createInventorySlot(band,item,c.Id,14+col*(FINAL14.Inventory.Cell+FINAL14.Inventory.GapX),51+row*(FINAL14.Inventory.Cell+FINAL14.Inventory.GapY))
			end
		end
		y+=sectionH+FINAL14.Inventory.SectionGap
	end

	local contentH=math.max(FINAL14.Inventory.H,y-FINAL14.Inventory.SectionGap)
	UI.InventoryContent.Size=UDim2.fromOffset(FINAL14.Inventory.W,contentH)
	UI.InventoryScroll.CanvasSize=UDim2.fromOffset(0,contentH)
	if UI.InventoryScrollChrome then UI.InventoryScrollChrome.Update() end
end

function App.createInventorySlot(parent,item,category,x,y)
	local b = App.button(parent,item.Id,x,y,64,64,4)
	App.setSlot(b,category,App.isCharacterEquipped(item.Id) and "equipped" or "normal")

	local guide = App.image(b,"Guide",App.guideFor(item),8,6,48,48,5)
	guide.ScaleType = Enum.ScaleType.Fit
	guide.ImageTransparency = 0.78

	local thumbAsset = App.realThumbnail(item)
	if assetReady(thumbAsset) then
		local thumb = App.image(b,"Thumbnail",thumbAsset,8,6,48,48,6)
		thumb.ScaleType = Enum.ScaleType.Fit
	end

	local qty = App.getAmount(item.Id)
	if qty > 1 then
		local t = App.text(b,"Quantity",tostring(qty),5,3,54,23,Enum.Font.SourceSansBold,19,Color3.new(1,1,1),8)
		t.TextStrokeColor3 = Color3.fromRGB(22,22,22)
		t.TextStrokeTransparency = 0.15
		t.TextXAlignment = Enum.TextXAlignment.Left
	end

	b.MouseEnter:Connect(function()
		App.slotContentHover(b,true)
		App.setSlot(b,category,"hover")
		App.scheduleTooltip(item.Id,b)
	end)
	b.MouseLeave:Connect(function()
		App.slotContentHover(b,false)
		App.cancelTooltip(item.Id)
		App.setSlot(b,category,App.isCharacterEquipped(item.Id) and "equipped" or "normal")
	end)
	b.MouseButton1Down:Connect(function() App.slotContentPress(b) end)
	b.MouseButton2Click:Connect(function() App.openContext(item.Id) end)
	UI.ItemButtons[item.Id] = b
end

-- --------------------------------------------------------------------------
-- Right identity + bag + equipment — exact absolute placements
-- --------------------------------------------------------------------------
function App.buildRight()
	App.buildIdentity()
	App.buildBag()
	App.buildEquipment()

	UI.Close = App.button(UI.RightGroup,"Close",1860,28,32,32,10)
	UI.Close.Image = A.Icons.Close
	UI.Close.MouseButton1Click:Connect(function() App.close() end)
end

function App.buildIdentity()
	UI.IdentityBand = App.image(UI.RightGroup,"IdentityBand",A.Components.IdentityBand,1556,80,336,166,2)
	if assetReady(A.Titles.Character) then App.image(UI.RightGroup,"CharacterTitle",A.Titles.Character,1579,84,170,31,5) end

	UI.Portrait = Instance.new("ViewportFrame")
	UI.Portrait.Name="Portrait"
	UI.Portrait.BackgroundTransparency=1
	UI.Portrait.Position=UDim2.fromOffset(1570,126)
	UI.Portrait.Size=UDim2.fromOffset(68,68)
	UI.Portrait.Ambient=Color3.fromRGB(190,190,190)
	UI.Portrait.LightColor=Color3.fromRGB(255,244,220)
	UI.Portrait.LightDirection=Vector3.new(-1,-1,-1)
	UI.Portrait.ZIndex=4
	UI.Portrait.Parent=UI.RightGroup
	UI.PortraitWorld=Instance.new("WorldModel")
	UI.PortraitWorld.Parent=UI.Portrait
	UI.PortraitCamera=Instance.new("Camera")
	UI.PortraitCamera.FieldOfView=30
	UI.PortraitCamera.Parent=UI.Portrait
	UI.Portrait.CurrentCamera=UI.PortraitCamera
	local pf=App.image(UI.RightGroup,"PortraitFrame",A.Components.PortraitFrame,1570,126,68,68,6)
	pf.ScaleType=Enum.ScaleType.Fit

	-- User-approved alignment: character text begins at the portrait's top edge.
	UI.Name = App.text(UI.RightGroup,"Name","",1650,126,225,24,Enum.Font.Garamond,21,CFG.Colors.Text,6)
	UI.Village = App.text(UI.RightGroup,"Village","",1650,150,225,18,Enum.Font.SourceSans,14,CFG.Colors.SubText,6)
	UI.Rank = App.text(UI.RightGroup,"Rank","",1650,171,225,19,Enum.Font.Garamond,15,CFG.Colors.Parchment,6)
	-- Keep both labels fully above the visible XP bar, never drawn on top of it.
	UI.Level = App.text(UI.RightGroup,"Level","",1570,195,105,18,Enum.Font.SourceSansSemibold,14,CFG.Colors.Text,7)
	UI.XPLabel = App.text(UI.RightGroup,"XPLabel","",1780,195,96,18,Enum.Font.SourceSansSemibold,14,CFG.Colors.Text,7)
	UI.XPLabel.TextXAlignment=Enum.TextXAlignment.Right

	UI.XPCanvas=Instance.new("Frame")
	UI.XPCanvas.BackgroundTransparency=1
	UI.XPCanvas.Position=UDim2.fromOffset(1555,166)
	UI.XPCanvas.Size=UDim2.fromOffset(340,113.333)
	UI.XPCanvas.ClipsDescendants=false
	UI.XPCanvas.ZIndex=2
	UI.XPCanvas.Parent=UI.RightGroup
	UI.XPBackground=App.image(UI.XPCanvas,"XPBackground",A.Components.XPBackground,0,0,340,113.333,2)
	UI.XPBackground.ScaleType=Enum.ScaleType.Fit
	UI.XPFill=App.image(UI.XPCanvas,"XPFill",A.Components.XPFill,0,0,340,113.333,3)
	UI.XPFill.ScaleType=Enum.ScaleType.Fit
	UI.XPGradient=Instance.new("UIGradient")
	UI.XPGradient.Parent=UI.XPFill
end

function App.rebuildPortrait()
	for _, child in ipairs(UI.PortraitWorld:GetChildren()) do child:Destroy() end
	local char=S.player.Character
	if not char then return end
	local old=char.Archivable
	char.Archivable=true
	local ok,clone=pcall(function() return char:Clone() end)
	char.Archivable=old
	if not ok or not clone then return end
	for _,d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false; d.CanTouch=false; d.CanQuery=false
		elseif d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
	local root=clone:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then root.Transparency=1 end
	clone.Parent=UI.PortraitWorld
	local head=clone:FindFirstChild("Head")
	local torso=clone:FindFirstChild("UpperTorso") or clone:FindFirstChild("Torso")
	if not (head and head:IsA("BasePart")) then return end
	local focus=head.Position+Vector3.new(0,-0.38,0)
	if torso and torso:IsA("BasePart") then
		focus=Vector3.new((head.Position.X+torso.Position.X)*0.5,head.Position.Y-0.38,(head.Position.Z+torso.Position.Z)*0.5)
	end
	local forward=Vector3.new(0,0,-1)
	if root and root:IsA("BasePart") then forward=root.CFrame.LookVector elseif torso and torso:IsA("BasePart") then forward=torso.CFrame.LookVector end
	forward=Vector3.new(forward.X,0,forward.Z)
	if forward.Magnitude<0.001 then forward=Vector3.new(0,0,-1) else forward=forward.Unit end
	-- Further than v2.4.0: shoulders/head framing instead of face close-up.
	local cameraPos=focus+forward*7.8+Vector3.new(0,0.03,0)
	UI.PortraitCamera.CFrame=CFrame.lookAt(cameraPos,focus,Vector3.yAxis)
end

function App.setXP(ratio)
	ratio=math.clamp(ratio,0,1)
	if ratio<=0 then UI.XPGradient.Transparency=NumberSequence.new(1)
	elseif ratio>=1 then UI.XPGradient.Transparency=NumberSequence.new(0)
	else
		local edge=math.min(1,ratio+0.002)
		UI.XPGradient.Transparency=NumberSequence.new({
			NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(ratio,0),
			NumberSequenceKeypoint.new(edge,1),NumberSequenceKeypoint.new(1,1),
		})
	end
end

function App.refreshIdentity()
	local i=App.characterInfo()
	UI.Name.Text=i.GivenName..(i.Surname~="" and (" "..i.Surname) or "")
	UI.Village.Text=i.Village
	UI.Rank.Text=i.Rank
	UI.Level.Text="LEVEL "..tostring(i.Level)
	UI.XPLabel.Text=tostring(i.XP).."/"..tostring(i.XPRequired)
	local ratio=i.XPRequired>0 and math.clamp(i.XP/i.XPRequired,0,1) or 0
	if State.LastXP==nil then
		State.LastXP=ratio
		App.setXP(ratio)
	elseif math.abs(ratio-State.LastXP)<0.0001 then
		App.setXP(ratio)
	else
		State.XPAnimToken+=1
		local token=State.XPAnimToken
		local start=State.LastXP
		State.LastXP=ratio
		task.spawn(function()
			local duration=0.38
			local t0=os.clock()
			while token==State.XPAnimToken do
				local alpha=math.clamp((os.clock()-t0)/duration,0,1)
				local eased=1-(1-alpha)^3
				App.setXP(start+(ratio-start)*eased)
				if alpha>=1 then break end
				S.RunService.RenderStepped:Wait()
			end
		end)
	end
	if State.LastLevel~=nil and i.Level>State.LastLevel then
		App.playSound("LevelUp")
		local original=UI.XPFill.ImageTransparency
		UI.XPFill.ImageTransparency=0.18
		S.TweenService:Create(UI.XPFill,TweenInfo.new(0.24,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{ImageTransparency=original}):Play()
	end
	State.LastLevel=i.Level
	App.rebuildPortrait()
end

function App.buildBag()
	UI.BagBand=App.image(UI.RightGroup,"BagBand",A.Components.BagBand,1556,272,336,146,2)
	if assetReady(A.Titles.NinjaBag) then App.image(UI.RightGroup,"BagTitle",A.Titles.NinjaBag,1579,276,151,31,5) end
	local key=App.image(UI.RightGroup,"BagKeycap",A.Components.Keycap,1856,281,24,24,6)
	local keyText=App.text(key,"Key","G",0,0,24,24,Enum.Font.SourceSansSemibold,14,CFG.Colors.Text,9)
	keyText.TextXAlignment=Enum.TextXAlignment.Center
	keyText.TextStrokeColor3=Color3.fromRGB(20,20,20)
	keyText.TextStrokeTransparency=0.55
	UI.BagSlots={}
	for i=1,4 do
		App.createBagSlot(i,1570+(i-1)*78,325)
	end
end

function App.createBagSlot(index,x,y)
	local b=App.button(UI.RightGroup,"BagSlot"..index,x,y,64,64,5)
	App.setSlot(b,"equipment","normal")
	local num=App.text(b,"Number",tostring(index),4,2,16,14,Enum.Font.SourceSans,12,CFG.Colors.Text,8)
	local guide=App.image(b,"Guide",A.Guides.Throwables,8,6,48,48,6)
	guide.ImageTransparency=0.78; guide.ScaleType=Enum.ScaleType.Fit
	local thumb=App.image(b,"Thumbnail","",8,6,48,48,7); thumb.ScaleType=Enum.ScaleType.Fit
	local edit=App.text(UI.RightGroup,"BagEdit"..index,"Edit",x,y+68,64,20,Enum.Font.SourceSans,13,CFG.Colors.Text,6)
	edit.TextXAlignment=Enum.TextXAlignment.Center
	local hit=Instance.new("TextButton")
	hit.BackgroundTransparency=1; hit.Text=""; hit.Position=edit.Position; hit.Size=edit.Size; hit.ZIndex=7; hit.Parent=UI.RightGroup
	b.MouseEnter:Connect(function()
		App.slotContentHover(b,true)
		local id=App.getBag(index)
		local item=id and S.catalog.GetItem(id)
		App.setSlot(b,item and App.category(item) or "equipment","hover")
		if id and not State.PickerSlot then App.scheduleTooltip(id,b) end
	end)
	b.MouseLeave:Connect(function() App.slotContentHover(b,false); App.cancelTooltip(nil); App.refreshBag() end)
	b.MouseButton1Down:Connect(function() App.slotContentPress(b) end)
	local function openPicker() App.openPicker(index) end
	b.MouseButton1Click:Connect(openPicker); hit.MouseButton1Click:Connect(openPicker)
	UI.BagSlots[index]={Button=b,Thumbnail=thumb,Edit=edit}
end

function App.refreshBag()
	for i=1,4 do
		local entry=UI.BagSlots[i]
		local id=App.getBag(i)
		if id then
			local item=S.catalog.GetItem(id)
			local cat=item and App.category(item) or "equipment"
			entry.Thumbnail.Image=item and (App.realThumbnail(item) or "") or ""
			App.setSlot(entry.Button,cat,"normal")
		else
			entry.Thumbnail.Image=""
			App.setSlot(entry.Button,"equipment","normal")
		end
	end
end

function App.buildEquipment()
	UI.EquipmentBand=App.image(UI.RightGroup,"EquipmentBand",A.Components.EquipmentBand,1556,444,336,270,2)
	if assetReady(A.Titles.Equipment) then App.image(UI.RightGroup,"EquipmentTitle",A.Titles.Equipment,1579,449,179,31,5) end
	UI.EquipmentSlots={}
	for _,e in ipairs(CFG.Equipment) do
		local b=App.button(UI.RightGroup,"Equip_"..e.Id,e.X,e.Y,64,64,5)
		App.setSlot(b,"equipment","normal")
		local guide=App.image(b,"Guide",A.Guides[e.Guide] or "",8,6,48,48,6); guide.ScaleType=Enum.ScaleType.Fit; guide.ImageTransparency=0.78
		local thumb=App.image(b,"Thumbnail","",8,6,48,48,7); thumb.ScaleType=Enum.ScaleType.Fit
		local lab=App.text(UI.RightGroup,"Label_"..e.Id,e.Label,e.X,e.LabelY,64,20,Enum.Font.SourceSans,13,CFG.Colors.Text,6); lab.TextXAlignment=Enum.TextXAlignment.Center
		b.MouseEnter:Connect(function() App.slotContentHover(b,true); App.setSlot(b,"equipment","hover") end)
		b.MouseLeave:Connect(function() App.slotContentHover(b,false); App.refreshEquipment() end)
		b.MouseButton1Down:Connect(function() App.slotContentPress(b) end)
		b.MouseButton1Click:Connect(function()
			if not e.Mutable then return end
			local current=App.getEquipped(e.ServerSlot)
			if current then Remotes.EquipRequest:FireServer(e.ServerSlot,"") else App.feedback("Right-click a compatible inventory item to equip","subtle") end
		end)
		UI.EquipmentSlots[e.Id]={Button=b,Thumbnail=thumb,Config=e}
	end
end

function App.refreshEquipment()
	for _,entry in pairs(UI.EquipmentSlots) do
		local e=entry.Config
		local id=App.getEquipped(e.ServerSlot)
		if id then
			local item=S.catalog.GetItem(id)
			entry.Thumbnail.Image=item and (App.realThumbnail(item) or "") or ""
			App.setSlot(entry.Button,"equipment","equipped")
		else
			entry.Thumbnail.Image=""
			App.setSlot(entry.Button,"equipment","normal")
		end
	end
end

-- --------------------------------------------------------------------------
-- FINAL-14 popover primitives — new implementation, no legacy offsets
-- --------------------------------------------------------------------------
function App.paperFrame(parent,z,kind)
	-- Astra: use only the central 11.54%-88.46% of the washi source, at 85%
	-- opacity, without empty transparent margins. Implement it proportionally so
	-- Roblox-side source resizing cannot invalidate pixel ImageRect coordinates.
	local clip=Instance.new("Frame")
	clip.Name="WashiClip"
	clip.BackgroundTransparency=1
	clip.BorderSizePixel=0
	clip.Size=UDim2.fromScale(1,1)
	clip.ClipsDescendants=true
	clip.ZIndex=z
	clip.Parent=parent

	local interior=0.8846-0.1154 -- 0.7692 of the source is usable paper
	local overscan=1/interior
	local paper=App.image(clip,"Washi",A.Pop.Washi,0,0,1,1,z)
	paper.AnchorPoint=Vector2.new(0.5,0.5)
	paper.Position=UDim2.fromScale(0.5,0.5)
	paper.Size=UDim2.fromScale(overscan,overscan)
	paper.ScaleType=Enum.ScaleType.Stretch
	paper.ImageTransparency=1-FINAL14.Popover.SurfaceOpacity
	paper.BackgroundTransparency=1

	-- panel_frame is an overlay only; it has no paper fill. Keep it sliced as
	-- specified by popovers/design.json.
	local frame=App.image(parent,"PanelFrame",A.Pop.Frame,0,0,1,1,z+19)
	frame.Size=UDim2.fromScale(1,1)
	frame.ScaleType=Enum.ScaleType.Slice
	frame.SliceCenter=Rect.new(16,16,48,48)

	if kind=="tooltip" then
		if assetReady(A.Pop.TipCornerTL) then
			local i=App.image(parent,"TipCornerTL",A.Pop.TipCornerTL,0,0,52.5,37.5,z+20)
			i.ScaleType=Enum.ScaleType.Fit
		end
		if assetReady(A.Pop.TipCornerBR) then
			local i=App.image(parent,"TipCornerBR",A.Pop.TipCornerBR,0,0,54.5,31.5,z+20)
			i.AnchorPoint=Vector2.new(1,1)
			i.Position=UDim2.fromScale(1,1)
			i.ScaleType=Enum.ScaleType.Fit
		end
	else
		local corners={
			{A.Pop.PickerTL,39,33,Vector2.new(0,0),UDim2.fromScale(0,0)},
			{A.Pop.PickerTR,39,33,Vector2.new(1,0),UDim2.fromScale(1,0)},
			{A.Pop.PickerBL,43.5,32,Vector2.new(0,1),UDim2.fromScale(0,1)},
			{A.Pop.PickerBR,41.5,32,Vector2.new(1,1),UDim2.fromScale(1,1)},
		}
		for n,c in ipairs(corners) do
			if assetReady(c[1]) then
				local i=App.image(parent,"Corner"..n,c[1],0,0,c[2],c[3],z+20)
				i.AnchorPoint=c[4]
				i.Position=c[5]
				i.ScaleType=Enum.ScaleType.Fit
			end
		end
	end
	return paper,frame
end

function App.rule(parent,y,x0,x1,z)
	local leftW,rightW=13.5,14.5
	if assetReady(A.Pop.RuleLeft) then
		local l=App.image(parent,"RuleLeft",A.Pop.RuleLeft,x0,y-5,13.5,11,z+1)
		l.ScaleType=Enum.ScaleType.Fit
	end
	if assetReady(A.Pop.RuleRight) then
		local r=App.image(parent,"RuleRight",A.Pop.RuleRight,x1-rightW,y-5,14.5,11,z+1)
		r.ScaleType=Enum.ScaleType.Fit
	end
	local line=Instance.new("Frame")
	line.BackgroundColor3=Color3.fromRGB(123,112,89)
	line.BackgroundTransparency=0.42
	line.BorderSizePixel=0
	line.Position=UDim2.fromOffset(x0+leftW,y)
	line.Size=UDim2.fromOffset(math.max(1,x1-x0-leftW-rightW),1)
	line.ZIndex=z
	line.Parent=parent
end

function App.tipRule(parent,x0,y,x1,z)
	local endW=41.5
	local line=Instance.new("Frame")
	line.BackgroundColor3=Color3.fromRGB(123,112,89)
	line.BackgroundTransparency=0.42
	line.BorderSizePixel=0
	line.Position=UDim2.fromOffset(x0,y)
	line.Size=UDim2.fromOffset(math.max(1,x1-x0-endW+4),1)
	line.ZIndex=z
	line.Parent=parent
	if assetReady(A.Pop.TipRuleEnd) then
		local tip=App.image(parent,"TipRuleEnd",A.Pop.TipRuleEnd,x1-endW,y-9,41.5,18,z+1)
		tip.ScaleType=Enum.ScaleType.Fit
	end
end

function App.buildPopovers()
	UI.Tooltip=Instance.new("Frame")
	UI.Tooltip.Name="Tooltip"; UI.Tooltip.BackgroundTransparency=1; UI.Tooltip.Visible=false; UI.Tooltip.ZIndex=50; UI.Tooltip.Parent=UI.Overlay
	UI.TooltipScale=Instance.new("UIScale"); UI.TooltipScale.Parent=UI.Tooltip

	UI.Context=Instance.new("Frame")
	UI.Context.Name="ContextMenu"; UI.Context.BackgroundTransparency=1; UI.Context.Visible=false; UI.Context.ZIndex=60; UI.Context.Parent=UI.Overlay
	UI.ContextScale=Instance.new("UIScale"); UI.ContextScale.Parent=UI.Context

	UI.Picker=Instance.new("Frame")
	UI.Picker.Name="NinjaBagPicker"; UI.Picker.BackgroundTransparency=1; UI.Picker.Visible=false; UI.Picker.ZIndex=70; UI.Picker.Parent=UI.Overlay
	UI.PickerScale=Instance.new("UIScale"); UI.PickerScale.Parent=UI.Picker
end

function App.hideTooltip()
	State.TooltipToken+=1; State.HoveredItemId=nil; UI.Tooltip.Visible=false
end
function App.cancelTooltip(itemId)
	State.TooltipToken+=1
	if itemId==nil or State.HoveredItemId==itemId then State.HoveredItemId=nil end
	UI.Tooltip.Visible=false
end
function App.scheduleTooltip(itemId,anchor)
	if State.PickerSlot then return end
	State.TooltipToken+=1
	local token=State.TooltipToken
	State.HoveredItemId=itemId
	task.delay(CFG.TooltipDelay,function()
		if not State.Open or token~=State.TooltipToken or State.HoveredItemId~=itemId or State.ContextItemId or State.PickerSlot then return end
		App.showTooltip(itemId,anchor)
	end)
end

function App.clearChildren(frame)
	for _,c in ipairs(frame:GetChildren()) do if not c:IsA("UIScale") then c:Destroy() end end
end

function App.showTooltip(itemId,anchor)
	local st=App.itemState(itemId); if not st then return end
	App.clearChildren(UI.Tooltip)

	local P=FINAL14.Popover.Tooltip
	local width=P.W
	local pad=P.Padding
	local iconSize=52
	local titleX=pad+iconSize+12
	local titleW=width-titleX-pad
	local titleText=st.Name
	local titleMeasured=App.measure(titleText,P.Title,titleW,Enum.Font.Garamond)
	local titleH=math.max(P.TitleLine,titleMeasured.Y)
	local categoryText=string.upper(App.categoryDisplay(st.Category))
	local categoryY=pad+titleH+P.CategoryGap
	local descriptionY=categoryY+P.CategoryLine+P.DescGap
	local descH=st.Description~="" and math.max(P.DescLine,App.measure(st.Description,P.Desc,width-pad*2,Enum.Font.Garamond).Y) or 0
	local cursor=descriptionY
	if descH>0 then cursor+=descH end
	if st.Quantity>1 then cursor+=8+P.LockedLine end
	if st.IsLocked then cursor+=P.LockedGap+P.LockedLine end
	local height=math.max(116,cursor+pad)

	UI.Tooltip.Size=UDim2.fromOffset(width,height)
	App.paperFrame(UI.Tooltip,50,"tooltip")

	local itemIcon=App.guideFor(st.Item)
	if assetReady(itemIcon) then
		local im=App.image(UI.Tooltip,"CategoryIcon",itemIcon,pad,pad+8,iconSize,iconSize,54)
		im.ScaleType=Enum.ScaleType.Fit
		im.ImageColor3=Color3.fromRGB(123,112,89)
		im.ImageTransparency=0.70
	end

	local title=App.text(UI.Tooltip,"Title",titleText,titleX,pad,titleW,titleH,Enum.Font.Garamond,P.Title,CFG.Colors.Ink,54)
	title.TextWrapped=true; title.TextYAlignment=Enum.TextYAlignment.Top
	local meta=App.text(UI.Tooltip,"Category",categoryText,titleX,categoryY,titleW,P.CategoryLine,Enum.Font.Garamond,P.Category,CFG.Colors.InkSecondary,54)
	meta.TextYAlignment=Enum.TextYAlignment.Top

	-- Approved mockup: the category label is followed by the parchment rule;
	-- there is no legacy full-width blue line underneath it.
	local metaW=math.min(titleW-52,App.measure(categoryText,P.Category,titleW,Enum.Font.Garamond).X)
	local ruleX=titleX+metaW+18
	App.tipRule(UI.Tooltip,ruleX,categoryY+math.floor(P.CategoryLine/2)+3,width-pad,53)

	cursor=descriptionY
	if st.Description~="" then
		local d=App.text(UI.Tooltip,"Description",st.Description,pad,cursor,width-pad*2,descH,Enum.Font.Garamond,P.Desc,CFG.Colors.Ink,54)
		d.TextWrapped=true; d.TextYAlignment=Enum.TextYAlignment.Top
		cursor+=descH
	end
	if st.Quantity>1 then
		cursor+=8
		local q=App.text(UI.Tooltip,"Quantity","Quantity: "..tostring(st.Quantity),pad,cursor,width-pad*2,P.LockedLine,Enum.Font.Garamond,P.Locked,CFG.Colors.InkSecondary,54)
		q.TextYAlignment=Enum.TextYAlignment.Top
		cursor+=P.LockedLine
	end
	if st.IsLocked then
		cursor+=P.LockedGap
		local l=App.text(UI.Tooltip,"Locked","Locked — protected from dropping",pad,cursor,width-pad*2,P.LockedLine,Enum.Font.Garamond,P.Locked,CFG.Colors.InkSecondary,54)
		l.TextWrapped=true; l.TextYAlignment=Enum.TextYAlignment.Top
	end

	local apos=anchor.AbsolutePosition; local asize=anchor.AbsoluteSize; local cpos=UI.Canvas.AbsolutePosition; local sc=State.Scale
	local x=(apos.X-cpos.X+asize.X)/sc+P.Gap
	local y=(apos.Y-cpos.Y)/sc
	if x+width>CFG.CanvasW-P.Margin then x=(apos.X-cpos.X)/sc-width-P.Gap end
	x=math.clamp(x,P.Margin,CFG.CanvasW-width-P.Margin)
	y=math.clamp(y,P.Margin,CFG.CanvasH-height-P.Margin)
	local finalPos=UDim2.fromOffset(x,y)
	UI.Tooltip.Position=UDim2.fromOffset(x,y+4)
	UI.TooltipScale.Scale=0.975; UI.Tooltip.Visible=true
	App.playSound("TooltipOpen")
	S.TweenService:Create(UI.TooltipScale,TweenInfo.new(0.11,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Scale=1}):Play()
	S.TweenService:Create(UI.Tooltip,TweenInfo.new(0.11,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=finalPos}):Play()
end

function App.hideContext()
	State.ContextItemId=nil; UI.Context.Visible=false
end

function App.actionRequest(action,payload)
	if not Remotes.ActionRequest then return {Ok=false,Reason="ActionRemoteMissing"} end
	local ok,res=pcall(function() return Remotes.ActionRequest:InvokeServer(action,payload) end)
	if not ok or typeof(res)~="table" then return {Ok=false,Reason="RequestFailed"} end
	return res
end

function App.performAction(action,itemId)
	if State.PendingAction then return end
	State.PendingAction=true
	local st=App.itemState(itemId)
	if not st then State.PendingAction=false return end
	local function finish(msg,bad,keep)
		State.PendingAction=false
		if msg then App.feedback(msg,bad and "bad" or nil) end
		App.refreshAll()
		if not keep then App.hideContext() end
	end
	if action=="Equip" then
		Remotes.EquipRequest:FireServer(st.Item.EquipmentSlot,itemId); finish("Equip request sent",false,false)
	elseif action=="Unequip" then
		Remotes.EquipRequest:FireServer(st.Item.EquipmentSlot,""); finish("Unequip request sent",false,false)
	elseif action=="Consume" then
		local r=App.actionRequest("Consume",{ItemId=itemId})
		if r.Ok then App.playSound("Consume") else App.playSound("Denied") end
		finish(r.Ok and "Item consumed" or tostring(r.Reason or "Consume failed"),r.Ok~=true,r.Ok~=true)
	elseif action=="Drop" then
		local r=App.actionRequest("Drop",{ItemId=itemId})
		if r.Ok then App.playSound("Drop") else App.playSound("Denied"); local b=UI.ItemButtons[itemId]; if b then App.shakeButton(b) end end
		finish(r.Ok and "Item dropped" or tostring(r.Reason or "Drop failed"),r.Ok~=true,r.Ok~=true)
	elseif action=="Lock" or action=="Unlock" then
		local r=App.actionRequest("SetLocked",{ItemId=itemId,Locked=action=="Lock"})
		if r.Ok then App.playSound(action) else App.playSound("Denied") end
		finish(r.Ok and (action=="Lock" and "Item locked" or "Item unlocked") or tostring(r.Reason or "Lock update failed"),r.Ok~=true,r.Ok~=true)
	else finish("Unsupported action",true,true) end
end

function App.openContext(itemId)
	local st=App.itemState(itemId); if not st then return end
	App.hideTooltip(); State.ContextItemId=itemId; App.clearChildren(UI.Context)
	local C=FINAL14.Popover.Context
	local actions={}
	if st.CanEquip then table.insert(actions,{Id=st.IsEquipped and "Unequip" or "Equip",Icon=A.Pop.Equip,Enabled=true}) end
	if st.CanConsume then table.insert(actions,{Id="Consume",Icon=A.Pop.Consume,Enabled=true}) end
	if st.CanDrop then table.insert(actions,{Id="Drop",Icon=A.Pop.Drop,Enabled=not st.IsLocked,Danger=true,Help=st.IsLocked and "Unlock to drop" or nil}) end
	local hasPrimary=#actions>0
	table.insert(actions,{Separator=hasPrimary})
	table.insert(actions,{Id=st.IsLocked and "Unlock" or "Lock",Icon=st.IsLocked and A.Pop.Unlock or A.Pop.Lock,Enabled=true})

	local help=nil
	local y=C.Padding
	for _,a in ipairs(actions) do
		if a.Separator then y+=C.SeparatorTop+1+C.SeparatorBottom
		elseif a.Id then y+=C.RowH; if not a.Enabled and a.Help then help=a.Help end end
	end
	local helpH=help and 20 or 0
	local height=y+C.Padding+helpH
	local width=C.W
	UI.Context.Size=UDim2.fromOffset(width,height)
	App.paperFrame(UI.Context,60,"menu")

	y=C.Padding
	for _,a in ipairs(actions) do
		if a.Separator then
			y+=C.SeparatorTop
			App.rule(UI.Context,y,C.Padding,width-C.Padding,64)
			y+=1+C.SeparatorBottom
		elseif a.Id then
			local row=App.button(UI.Context,"Action_"..a.Id,C.Padding,y,width-C.Padding*2,C.RowH,63)
			row.Image=a.Enabled and A.Pop.RowNormal or A.Pop.RowDisabled
			row.ScaleType=Enum.ScaleType.Stretch
			if assetReady(a.Icon) then
				local ic=App.image(row,"Icon",a.Icon,C.IconX,C.IconY,C.IconW,C.IconH,65)
				ic.ScaleType=Enum.ScaleType.Fit
			end
			local lab=App.text(row,"Label",a.Id,C.LabelX,0,width-C.Padding*2-C.LabelX-C.RightPad,C.RowH,Enum.Font.Garamond,18,a.Enabled and (a.Danger and CFG.Colors.Danger or CFG.Colors.Ink) or CFG.Colors.Disabled,65)
			row.MouseEnter:Connect(function() if a.Enabled then row.Image=a.Danger and A.Pop.RowDangerHover or A.Pop.RowHover end end)
			row.MouseLeave:Connect(function() row.Image=a.Enabled and A.Pop.RowNormal or A.Pop.RowDisabled end)
			row.MouseButton1Down:Connect(function() if a.Enabled then row.Image=A.Pop.RowPressed end end)
			row.MouseButton1Click:Connect(function()
				if a.Enabled then
					App.performAction(a.Id,itemId)
				elseif a.Help then
					App.playSound("Denied")
					local sourceButton=UI.ItemButtons[itemId]
					if sourceButton then App.shakeButton(sourceButton) end
					App.feedback(a.Help,"bad")
				end
			end)
			y+=C.RowH
		end
	end
	if help then App.text(UI.Context,"Help",help,16,y,width-32,20,Enum.Font.Garamond,14,CFG.Colors.InkSecondary,65) end

	local m=S.UserInputService:GetMouseLocation(); local cp=UI.Canvas.AbsolutePosition; local sc=State.Scale
	local x=(m.X-cp.X)/sc; local yy=(m.Y-cp.Y)/sc
	x=math.clamp(x,16,CFG.CanvasW-width-16); yy=math.clamp(yy,16,CFG.CanvasH-height-16)
	local finalPos=UDim2.fromOffset(x,yy)
	UI.Context.Position=UDim2.fromOffset(x,yy+4); UI.ContextScale.Scale=0.975; UI.Context.Visible=true
	App.playSound("ContextOpen")
	S.TweenService:Create(UI.ContextScale,TweenInfo.new(0.11,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Scale=1}):Play()
	S.TweenService:Create(UI.Context,TweenInfo.new(0.11,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=finalPos}):Play()
end

function App.hidePicker()
	State.PickerSlot=nil; State.PickerPending=false; UI.Picker.Visible=false
end

function App.openPicker(slotIndex)
	App.hideTooltip(); App.hideContext(); State.PickerSlot=slotIndex; State.PickerPending=false; App.clearChildren(UI.Picker)
	local P=FINAL14.Popover.Picker
	local items={}
	for _,item in ipairs(App.getOwned()) do if App.canBag(item) then table.insert(items,item) end end
	table.sort(items,function(a,b) return tostring(a.DisplayName or a.Id)<tostring(b.DisplayName or b.Id) end)

	local visibleRows=math.max(1,math.min(P.MaxRows,#items))
	local listH=visibleRows*P.RowH
	local height=P.HeaderH+listH+P.FooterH
	local width=P.W
	UI.Picker.Size=UDim2.fromOffset(width,height)
	App.paperFrame(UI.Picker,70,"menu")
	App.text(UI.Picker,"Header","NINJA BAG · SLOT "..tostring(slotIndex),18,5,width-36,30,Enum.Font.Garamond,18,CFG.Colors.Ink,76)

	local list=Instance.new("ScrollingFrame")
	list.Name="List"; list.BackgroundTransparency=1; list.BorderSizePixel=0
	list.Position=UDim2.fromOffset(8,P.HeaderH); list.Size=UDim2.fromOffset(width-16,listH)
	list.CanvasSize=UDim2.fromOffset(0,math.max(listH,#items*P.RowH)); list.ScrollBarThickness=0
	list.ClipsDescendants=true; list.ZIndex=73; list.Parent=UI.Picker
	local overflow=#items>P.MaxRows
	local rowWidth=width-16-(overflow and 20 or 0)
	local current=App.getBag(slotIndex)

	if #items==0 then
		App.text(list,"Empty","No compatible items",16,0,rowWidth-32,P.RowH,Enum.Font.Garamond,18,CFG.Colors.Ink,76)
	else
		for idx,item in ipairs(items) do
			local yy=(idx-1)*P.RowH
			local row=App.button(list,"Row_"..item.Id,0,yy,rowWidth,P.RowH,75); row.ImageTransparency=1
			local icon=App.fallbackItemIcon(item)
			if assetReady(icon) then
				local im=App.image(row,"Thumbnail",icon,10,8,P.Thumb,P.Thumb,77)
				im.ScaleType=Enum.ScaleType.Fit
				im.ImageTransparency=App.realThumbnail(item) and 0 or 0.45
			end
			local name=App.text(row,"Name",tostring(item.DisplayName or item.Id),50,0,rowWidth-108,P.RowH,Enum.Font.Garamond,17,CFG.Colors.Ink,77)
			name.TextTruncate=Enum.TextTruncate.AtEnd
			local q=App.text(row,"Qty","x"..tostring(App.getAmount(item.Id)),rowWidth-54,5,46,17,Enum.Font.SourceSansSemibold,12,CFG.Colors.Ink,78); q.TextXAlignment=Enum.TextXAlignment.Right
			if current==item.Id then local eq=App.text(row,"Equipped","Equipped",rowWidth-82,25,74,15,Enum.Font.SourceSans,10,Color3.fromRGB(90,120,80),78); eq.TextXAlignment=Enum.TextXAlignment.Right end
			if App.isLocked(item.Id) and assetReady(A.Pop.Lock) then local lock=App.image(row,"Lock",A.Pop.Lock,rowWidth-23,27,11,11,79); lock.ScaleType=Enum.ScaleType.Fit end
			-- Approved picker mockup uses the parchment ornamental separator, not
			-- the legacy bright category strip.
			App.rule(list,yy+P.RowH-6,0,rowWidth,80)
			row.MouseButton1Click:Connect(function()
				if State.PickerPending then return end
				State.PickerPending=true
				Remotes.BagRequest:FireServer(slotIndex,item.Id)
				App.feedback("Assigning "..tostring(item.DisplayName or item.Id).."…","subtle")
			end)
		end
	end

	local footer=Instance.new("TextButton")
	footer.BackgroundTransparency=1; footer.Text="Clear slot"; footer.Font=Enum.Font.Garamond; footer.TextSize=16; footer.TextColor3=CFG.Colors.Danger
	footer.Position=UDim2.fromOffset(8,P.HeaderH+listH); footer.Size=UDim2.fromOffset(width-16,P.FooterH); footer.ZIndex=77; footer.Parent=UI.Picker
	footer.MouseButton1Click:Connect(function()
		if State.PickerPending then return end
		State.PickerPending=true; Remotes.BagRequest:FireServer(slotIndex,""); App.feedback("Clearing Ninja Bag slot "..slotIndex.."…","subtle")
	end)
	if overflow then App.buildScrollChrome(UI.Picker,"PickerChrome",width-28,P.HeaderH,listH,list,true) end

	local preferredX=1556+State.EdgeOffset-width-12
	local y=272
	local px=math.clamp(preferredX,16,CFG.CanvasW-width-16)
	local py=math.clamp(y,16,CFG.CanvasH-height-16)
	local finalPos=UDim2.fromOffset(px,py)
	UI.Picker.Position=UDim2.fromOffset(px+12,py)
	UI.PickerScale.Scale=0.98; UI.Picker.Visible=true
	App.playSound("BagOpen")
	S.TweenService:Create(UI.PickerScale,TweenInfo.new(0.13,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Scale=1}):Play()
	S.TweenService:Create(UI.Picker,TweenInfo.new(0.13,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=finalPos}):Play()
end

-- --------------------------------------------------------------------------
-- Feedback + open/close + refresh
-- --------------------------------------------------------------------------
function App.feedback(text,tone)
	State.FeedbackToken+=1; local token=State.FeedbackToken
	UI.Feedback.Text=text or ""
	UI.Feedback.TextColor3=tone=="bad" and CFG.Colors.Danger or CFG.Colors.Text
	S.TweenService:Create(UI.Feedback,TweenInfo.new(0.1),{TextTransparency=0}):Play()
	task.delay(1.85,function()
		if token~=State.FeedbackToken then return end
		S.TweenService:Create(UI.Feedback,TweenInfo.new(0.22),{TextTransparency=1}):Play()
	end)
end

function App.refreshAll()
	App.refreshIdentity(); App.renderInventory(); App.refreshBag(); App.refreshEquipment()
end

function App.open()
	if State.Open then return end
	State.Open=true; State.AnimationToken+=1; local token=State.AnimationToken
	UI.Gui.Enabled=true; App.updateScale(); App.refreshAll()
	App.playSound("Open")
	UI.LeftGroup.GroupTransparency=1; UI.RightGroup.GroupTransparency=1
	local leftTarget=UDim2.fromOffset(-State.EdgeOffset,0); local rightTarget=UDim2.fromOffset(State.EdgeOffset,0)
	UI.LeftGroup.Position=UDim2.fromOffset(-State.EdgeOffset-54,0); UI.RightGroup.Position=UDim2.fromOffset(State.EdgeOffset+54,0)
	S.TweenService:Create(UI.LeftGroup,TweenInfo.new(0.24,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{GroupTransparency=0,Position=leftTarget}):Play()
	S.TweenService:Create(UI.RightGroup,TweenInfo.new(0.24,Enum.EasingStyle.Quart,Enum.EasingDirection.Out,0,false,0.035),{GroupTransparency=0,Position=rightTarget}):Play()
end

function App.close()
	if not State.Open then return end
	State.Open=false; State.AnimationToken+=1; local token=State.AnimationToken
	App.hideTooltip(); App.hideContext(); App.hidePicker(); UI.SearchBox:ReleaseFocus(); State.FeedbackToken+=1; UI.Feedback.TextTransparency=1
	App.playSound("Close")
	local left=UDim2.fromOffset(-State.EdgeOffset-34,0); local right=UDim2.fromOffset(State.EdgeOffset+34,0)
	S.TweenService:Create(UI.LeftGroup,TweenInfo.new(0.16,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{GroupTransparency=1,Position=left}):Play()
	S.TweenService:Create(UI.RightGroup,TweenInfo.new(0.16,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{GroupTransparency=1,Position=right}):Play()
	task.delay(0.17,function() if token==State.AnimationToken and not State.Open then UI.Gui.Enabled=false end end)
end

function App.toggle(source)
	if S.UserInputService:GetFocusedTextBox() then return end
	local now=os.clock(); if now-State.LastToggle<0.18 then return end; State.LastToggle=now
	if State.Open then App.close() else App.open() end
	print("[InventoryBandsHUD] TAB toggle | Source="..source.." | Open="..tostring(State.Open))
end

-- --------------------------------------------------------------------------
-- Connections
-- --------------------------------------------------------------------------
function App.connect()
	UI.SearchBox:GetPropertyChangedSignal("Text"):Connect(function() State.Search=UI.SearchBox.Text; if State.Open then App.renderInventory() end end)

	local function tabAction(_,inputState)
		if inputState==Enum.UserInputState.Begin then App.toggle("ContextActionService") end
		return Enum.ContextActionResult.Sink
	end
	S.ContextActionService:UnbindAction("WAYLESS_Inventory_TAB")
	S.ContextActionService:BindActionAtPriority("WAYLESS_Inventory_TAB",tabAction,false,Enum.ContextActionPriority.High.Value+10000,Enum.KeyCode.Tab)

	S.UserInputService.InputBegan:Connect(function(input,processed)
		if input.UserInputType==Enum.UserInputType.Keyboard then
			if input.KeyCode==Enum.KeyCode.Tab then App.toggle("UserInputService"); return end
			if State.Open and input.KeyCode==Enum.KeyCode.Escape then
				if State.PickerSlot then App.hidePicker() elseif State.ContextItemId then App.hideContext() else App.close() end
				return
			end
		end
		if processed or not State.Open then return end
		if input.UserInputType==Enum.UserInputType.MouseButton1 then
			local objs=S.playerGui:GetGuiObjectsAtPosition(input.Position.X,input.Position.Y)
			local inContext=false; local inPicker=false
			for _,o in ipairs(objs) do
				if o==UI.Context or o:IsDescendantOf(UI.Context) then inContext=true end
				if o==UI.Picker or o:IsDescendantOf(UI.Picker) then inPicker=true end
			end
			if not inContext then App.hideContext() end
			if State.PickerSlot and not inPicker then App.hidePicker() end
		end
	end)

	S.RunService.RenderStepped:Connect(function()
		local down=S.UserInputService:IsKeyDown(Enum.KeyCode.Tab)
		if down and not State.TabDown then App.toggle("RenderStepPoll") end
		State.TabDown=down
		if State.Open then
			if UI.InventoryScrollChrome then UI.InventoryScrollChrome.Update() end
			if UI.PickerScrollChrome and UI.PickerScrollChrome.Root.Parent then UI.PickerScrollChrome.Update() end
		end
	end)

	local camera=workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() App.updateScale() end) end

	S.player.AttributeChanged:Connect(function(attr)
		if not State.Open then return end
		if string.sub(attr,1,16)=="InventoryAmount_" or string.sub(attr,1,16)=="InventoryLocked_" or string.sub(attr,1,8)=="Equipped" or string.sub(attr,1,12)=="NinjaBagSlot" then App.refreshAll(); return end
		if attr=="CharacterLevel" or attr=="CharacterXPIntoLevel" or attr=="CharacterXPRequired" or attr=="NinjaRank" or attr=="NinjaRankDisplayName" or attr=="OriginVillageId" or attr=="AffiliationVillageId" or attr=="GivenName" or attr=="Surname" or attr=="ClanId" then App.refreshIdentity() end
	end)

	S.player.CharacterAdded:Connect(function() task.delay(0.5,function() if State.Open then App.refreshIdentity() end end) end)

	Remotes.EquipResult.OnClientEvent:Connect(function(success,slot,item,reason)
		App.feedback(success and "Equipment updated" or ("Equipment: "..tostring(reason or "Failed")),success and nil or "bad")
		if success then App.playSound((typeof(item)=="string" and item~="") and "Equip" or "Unequip") else App.playSound("Denied") end
		if State.Open then
			App.refreshAll()
			task.defer(function()
				for _,entry in pairs(UI.EquipmentSlots or {}) do
					local cfg=entry.Config
					if cfg and cfg.ServerSlot==slot then App.pulseButton(entry.Button); break end
				end
			end)
		end
	end)
	Remotes.BagResult.OnClientEvent:Connect(function(success,slot,item,reason)
		App.feedback(success and "Ninja Bag updated" or ("Ninja Bag: "..tostring(reason or "Failed")),success and nil or "bad")
		if success then App.playSound("BagAssign") else App.playSound("Denied") end
		State.PickerPending=false
		if success then App.hidePicker() end
		if State.Open then
			App.refreshAll()
			task.defer(function()
				local entry=UI.BagSlots and UI.BagSlots[tonumber(slot)]
				if entry then App.pulseButton(entry.Button) end
			end)
		end
	end)
end

-- --------------------------------------------------------------------------
-- FINAL-14 asset audit
-- --------------------------------------------------------------------------
function App.auditFinal14Assets()
	local required={
		{"components/category_band",A.Components.CategoryBand},{"components/identity_band",A.Components.IdentityBand},{"components/bag_band",A.Components.BagBand},{"components/equipment_band",A.Components.EquipmentBand},{"components/search_field",A.Components.SearchField},{"components/keycap",A.Components.Keycap},{"components/portrait_frame",A.Components.PortraitFrame},{"user_xp/XP_Background",A.Components.XPBackground},{"user_xp/XP_Fill",A.Components.XPFill},
		{"title/inventory",A.Titles.Inventory},{"title/character",A.Titles.Character},{"title/ninja_bag",A.Titles.NinjaBag},{"title/equipment",A.Titles.Equipment},{"title/weapons",A.Titles.Weapons},{"title/equipment_category",A.Titles.EquipmentCategory},{"title/consumables",A.Titles.Consumables},{"title/materials",A.Titles.Materials},
		{"popover/washi",A.Pop.Washi},{"popover/panel_frame",A.Pop.Frame},{"popover/picker_tl",A.Pop.PickerTL},{"popover/picker_tr",A.Pop.PickerTR},{"popover/picker_bl",A.Pop.PickerBL},{"popover/picker_br",A.Pop.PickerBR},{"popover/rule_left",A.Pop.RuleLeft},{"popover/rule_right",A.Pop.RuleRight},{"popover/tip_corner_tl",A.Pop.TipCornerTL},{"popover/tip_corner_br",A.Pop.TipCornerBR},{"popover/tip_rule_end",A.Pop.TipRuleEnd},
		{"scroll/top",A.Scroll.Top},{"scroll/bottom",A.Scroll.Bottom},{"scroll/thumb",A.Scroll.Thumb},
	}
	local missing={}
	for _,entry in ipairs(required) do if not assetReady(entry[2]) then table.insert(missing,entry[1]) end end
	if #missing>0 then warn("[InventoryBandsHUD] FINAL-14 missing assets: "..table.concat(missing,", ")) else print("[InventoryBandsHUD] FINAL-14 asset audit OK | required="..tostring(#required)) end
end

-- --------------------------------------------------------------------------
-- Build
-- --------------------------------------------------------------------------
App.auditFinal14Assets()
App.buildRoot()
App.buildLeft()
App.buildRight()
App.buildPopovers()
App.updateScale()
App.connect()

print("[InventoryBandsHUD] READY v4.1.1 | ASTRA_FINAL14_STRICT | Polish=ON | UISounds=OPTIONAL_PLACEHOLDERS | VisualGeometry=UNCHANGED")
