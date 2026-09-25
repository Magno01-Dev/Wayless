--!strict
-- ReplicatedStorage > InventoryHUDAssets
-- WAYLESS Inventory FINAL-14
-- ASTRA STRICT COMPLETE ASSET MAP v4.0
--
-- Source of truth:
--   WAYLESS_Inventario_FINAL.zip
--   design.json
--   layout.json
--   popovers/design.json
--   popovers/layout.json
--   popovers/ninja_bag_picker.json
--   scroll/design.json
--
-- NOTE:
-- Roblox censored the uploaded name "picker_tr" as #########.
-- Confirmed asset id: 101275878205876.
--
-- The top-level tables preserve the old approved assets only as emergency
-- compatibility fallbacks for older code. FINAL is the authoritative map
-- for the current inventory rebuild.

local function asset(id: number): string
	return "rbxassetid://" .. tostring(id)
end

local Assets = {
	----------------------------------------------------------------
	-- LEGACY FALLBACKS
	----------------------------------------------------------------
	Components = {
		CategoryBand = asset(113747798113087),
		IdentityBand = asset(84557636995599),
		BagBand = asset(116106390100566),
		EquipmentBand = asset(91401900257858),
		SearchField = asset(118716857072661),
		CountChip = asset(96166780971340),
		Keycap = asset(97984695195373),
		ScrollTrack = asset(73247021399710),
		ScrollThumb = asset(119891576395268),
		SlotNormal = asset(139623807016547),
		SlotHover = asset(103108123924655),
		SlotSelected = asset(123671101379757),
		SlotEquipped = asset(139289487292275),
		SlotDisabled = asset(97595778243829),
		SlotDropValid = asset(75302151407748),
		SlotDropInvalid = asset(129479344419462),
	},

	Icons = {
		Weapon = asset(132656098266896),
		Headband = asset(127625267623166),
		Armor = asset(116537067976814),
		Mask = asset(116202366002433),
		Cloak = asset(71705282011676),
		HeadAccessory = asset(93671679316182),
		OffHand = asset(99652164496337),
		Accessories = asset(107441737452215),
		Bag = asset(126946542422034),
		Consumables = asset(73162703224684),
		Materials = asset(107914112003163),
		Search = asset(91542012837330),
		Close = asset(94313623617173),
		Chevron = asset(139107973411051),
		Village = asset(78985424026177),
	},

	Popovers = {
		WashiSurface = asset(133982885326395),
		PanelFrame = asset(113492285271741),
		Divider = asset(75791713398306),
		RowNormal = asset(109351331684393),
		RowHover = asset(93639744680395),
		RowPressed = asset(116408840284036),
		RowDisabled = asset(77860402394639),
		RowDangerHover = asset(77212085369254),
		Lock = asset(129667769111766),
		Unlock = asset(81331697332726),
		Drop = asset(116602091755298),
		Equip = asset(80769612846479),
		Consume = asset(136983591456029),
	},

	----------------------------------------------------------------
	-- FINAL-14 AUTHORITATIVE MAP
	----------------------------------------------------------------
	Final = {
		Components = {
			-- Main bands / controls
			CategoryBand = asset(113178748481697),
			IdentityBand = asset(112970597357071),
			BagBand = asset(94253703325853),
			EquipmentBand = asset(131397578114303),
			SearchField = asset(104554957695387),
			CountChip = asset(70916583747717),
			Keycap = asset(131636613468266),
			PortraitFrame = asset(123284214095590),

			-- Scroll helpers also exposed here because older HUD revisions
			-- resolve them through Components.
			ScrollTrack = asset(85138581077969),
			ScrollThumb = asset(99298977169302),

			-- Original Photoshop XP pair
			XPBackground = asset(136138232404285),
			XPFill = asset(75334400445760),

			-- Compact / exact XP helpers
			XPTrack = asset(117005667667469),
			XPFillCompact = asset(104321213951283),
			XPOrnament = asset(110113690813311),
			XPLeftExact = asset(97073140858281),
			XPRightExact = asset(134189238277894),

			-- Generic slot states
			SlotNormal = asset(119766069684751),
			SlotHover = asset(110713494461947),
			SlotSelected = asset(137863366000945),
			SlotEquipped = asset(117520405110078),
			SlotDisabled = asset(98487736478397),
			SlotDropValid = asset(89850566882426),
			SlotDropInvalid = asset(119851195008539),

			-- Category-specific states
			Weapons = {
				Normal = asset(79347808525533),
				Hover = asset(92413630261662),
				Selected = asset(90496346809884),
				Equipped = asset(137693343686690),
				Disabled = asset(76193825512368),
				DropValid = asset(103995067913744),
				DropInvalid = asset(125529127324458),
			},

			Equipment = {
				Normal = asset(89681000667486),
				Hover = asset(133724230892712),
				Selected = asset(135587719663159),
				Equipped = asset(97146070259875),
				Disabled = asset(133159333259568),
				DropValid = asset(93765142676723),
				DropInvalid = asset(76280180833127),
			},

			Consumables = {
				Normal = asset(79447963743482),
				Hover = asset(124705848940927),
				Selected = asset(127859333630705),
				Equipped = asset(118625436535418),
				Disabled = asset(79539977611073),
				DropValid = asset(98404646094540),
				DropInvalid = asset(87937975650498),
			},

			Materials = {
				Normal = asset(86287448891105),
				Hover = asset(114755438108124),
				Selected = asset(119977388783352),
				Equipped = asset(91931415038851),
				Disabled = asset(115212098310108),
				DropValid = asset(124627115209757),
				DropInvalid = asset(102107941547317),
			},
		},

		----------------------------------------------------------------
		-- RASTER TITLES USED BY layout.json
		-- These map to reference_art/*, NOT components/title_* helpers.
		----------------------------------------------------------------
		Titles = {
			Inventory = asset(92683180057329),
			Character = asset(102988833852036),
			NinjaBag = asset(117867577053871),
			Equipment = asset(75301974936986),
			Weapons = asset(90156169222249),
			EquipmentCategory = asset(71618787519052),
			Consumables = asset(101682380103927),
			Materials = asset(103915393240971),
		},

		----------------------------------------------------------------
		-- BACKGROUND GUIDE / ITEM ICONS
		--
		-- In the FINAL package, these supplied guide PNGs are byte-identical
		-- to their matching icons:
		--   icons/weapon.png       == icons/supplied/Weapon.png
		--   icons/bag.png          == icons/supplied/Throwables.png
		--   icons/consumables.png  == icons/supplied/Consumables.png
		--   icons/materials.png    == icons/supplied/Materials.png
		----------------------------------------------------------------
		Guides = {
			Weapon = asset(105067031002627),
			Headband = asset(122999444232347),
			Armor = asset(136203254949335),
			Mask = asset(121378596560547),
			Cloak = asset(111764214217292),
			HeadAccessory = asset(132283886964584), -- Accessories guide per FINAL guide
			OffHand = asset(105067031002627),       -- Weapon guide per FINAL guide
			Accessories = asset(132283886964584),

			Bag = asset(114723796472436),
			Throwables = asset(114723796472436),

			Consumables = asset(74424134957632),
			Materials = asset(103915393240971),
			Scroll = asset(123280298893615),

			-- Not currently shown as dedicated equipment slots in the FINAL HUD.
			-- Keep safe aliases instead of 0 so no UI becomes blank if queried.
			Food = asset(74424134957632),
			Gloves = asset(132283886964584),
			Shoes = asset(132283886964584),
			Tools = asset(105067031002627),
			Misc = asset(103915393240971),
			MissionItems = asset(103915393240971),
		},

		Icons = {
			Search = asset(73027886177311),
			Close = asset(114358999387490),
			Chevron = asset(91996519737941),
			Village = asset(112622015832074),

			Weapon = asset(105067031002627),
			Headband = asset(122999444232347),
			Armor = asset(136203254949335),
			Mask = asset(121378596560547),
			Cloak = asset(111764214217292),
			HeadAccessory = asset(99994474759843),
			OffHand = asset(101816590199491),
			Accessories = asset(132283886964584),

			Bag = asset(114723796472436),
			Consumables = asset(74424134957632),
			Materials = asset(103915393240971),
			Scroll = asset(123280298893615),
			Shuriken = asset(77557123885426),
			Herb = asset(111613648966041),
		},

		----------------------------------------------------------------
		-- APPROVED INVENTORY SCROLL
		-- scroll/design.json
		----------------------------------------------------------------
		Scroll = {
			TrackInventory = asset(135443457699502),
			RuleLeft = asset(96401117372925),
			RuleRight = asset(87526723013706),
			Thumb = asset(99298977169302),
		},

		----------------------------------------------------------------
		-- POPOVERS
		-- popovers/design.json + popovers/layout.json
		----------------------------------------------------------------
		Popovers = {
			WashiSurface = asset(81579831556140),
			PanelFrame = asset(87246749766716),
			Divider = asset(128760090485357),

			RowNormal = asset(96710365785563),
			RowHover = asset(92598756446827),
			RowPressed = asset(134204316225230),
			RowDisabled = asset(121906289360824),
			RowDangerHover = asset(73290041989596),

			Lock = asset(122818071157113),
			Unlock = asset(109191325460439),
			Drop = asset(99147577907215),
			Equip = asset(86862283118426),
			Consume = asset(100832221698845),

			CategoryWeapons = asset(128953350245413),
			CategoryEquipment = asset(119210435123750),
			CategoryConsumables = asset(109041160871372),
			CategoryMaterials = asset(138617177809087),

			-- Extracted fixed-size ornament/end-cap assets.
			PickerTL = asset(133262258649223),
			PickerTR = asset(101275878205876), -- uploaded as #########, confirmed picker_tr
			PickerBL = asset(89308594650617),
			PickerBR = asset(139007291880431),

			RuleLeft = asset(102131339337857),
			RuleRight = asset(110881033074075),

			TipCornerTL = asset(114771024461930),
			TipCornerBR = asset(111655857404697),
			TipRuleEnd = asset(82581671985340),
		},

		----------------------------------------------------------------
		-- OTHER UPLOADED FINAL ASSETS
		-- Kept explicitly named so they are not accidentally mistaken for
		-- reference_art titles or active layout pieces.
		----------------------------------------------------------------
		Reference = {
			ReferenceAtlas = asset(79313257756292),
			PortraitSample = asset(103939651425107),
			XPReference = asset(101889788404938),

			TitleSpiral = asset(103652357191462),
			TitleEquipment = asset(118313722028595),
			TitleEquipmentCategory = asset(105223771212610),
			TitleConsumables = asset(138008654109099),
			TitleMaterials = asset(76418476783906),

			CornerLeft = asset(101393227020580),
			CornerRight = asset(82633422750979),

			CategoryWeapons = asset(128953350245413),
			CategoryEquipment = asset(119210435123750),
			CategoryConsumables = asset(109041160871372),
			CategoryMaterials = asset(138617177809087),
		},
	},
}

return Assets
