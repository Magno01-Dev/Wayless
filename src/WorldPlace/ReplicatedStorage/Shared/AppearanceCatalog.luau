--!strict
-- ReplicatedStorage > Shared > AppearanceCatalog
--
-- WAYLESS Appearance Catalog v1.10 - optional gloves + stable 3D wearable definitions.
--
-- Data-only catalog shared by Frontend preview and World runtime.
-- All user-facing strings are English.
--
-- WAYLESS uses a fixed classic R6 body for every shinobi.
-- Body shape, body scaling and height are intentionally not customizable.
--
-- IMPORTANT:
-- Starter clothing uses classic ShirtTemplate / PantsTemplate content strings.
-- Character data stores only stable TopId / BottomId keys, never template URLs.
-- This allows clothing art to be replaced later without migrating Life data.
--
-- Facial appearance is modular: mouth, brows, nose and eyes are selected independently.

local AppearanceCatalog = {}

AppearanceCatalog.Version = 11

AppearanceCatalog.SkinTones = {
	{ Id = "S01", Color = Color3.fromRGB(250, 224, 204) },
	{ Id = "S02", Color = Color3.fromRGB(239, 203, 177) },
	{ Id = "S03", Color = Color3.fromRGB(224, 181, 145) },
	{ Id = "S04", Color = Color3.fromRGB(207, 158, 119) },
	{ Id = "S05", Color = Color3.fromRGB(190, 137, 98) },
	{ Id = "S06", Color = Color3.fromRGB(169, 116, 80) },
	{ Id = "S07", Color = Color3.fromRGB(145, 94, 65) },
	{ Id = "S08", Color = Color3.fromRGB(119, 75, 54) },
	{ Id = "S09", Color = Color3.fromRGB(94, 58, 45) },
	{ Id = "S10", Color = Color3.fromRGB(69, 43, 36) },
}

AppearanceCatalog.LegacySkinToneAliases = {
	Porcelain = "S01",
	Light = "S02",
	Warm = "S04",
	Tan = "S06",
	Brown = "S08",
	Deep = "S10",
}

AppearanceCatalog.FaceStyles = {
	{
		Id = "Default",
		DisplayName = "DEFAULT",
		-- Future custom face texture / decal asset.
		FaceTextureId = 0,
		Enabled = true,
	},
}

-- Legacy whole-face data remains only for older lives.
-- New characters use MouthStyleId + BrowStyleId + NoseStyleId + EyeStyleId.

AppearanceCatalog.MouthStyles = {
	{
		Id = "Mouth_01",
		DisplayName = "MOUTH 01",
		Image = "rbxassetid://71847983113877",
		Enabled = true,
	},
	{
		Id = "Mouth_02",
		DisplayName = "MOUTH 02",
		Image = "rbxassetid://78919137821395",
		Enabled = true,
	},
	{
		Id = "Mouth_03",
		DisplayName = "MOUTH 03",
		Image = "rbxassetid://73515539560996",
		Enabled = true,
	},
	{
		Id = "Mouth_04",
		DisplayName = "MOUTH 04",
		Image = "rbxassetid://104273461755089",
		Enabled = true,
	},
	{
		Id = "Mouth_05",
		DisplayName = "MOUTH 05",
		Image = "rbxassetid://124606179190612",
		Enabled = true,
	},
	{
		Id = "Mouth_06",
		DisplayName = "MOUTH 06",
		Image = "rbxassetid://129076230765718",
		Enabled = true,
	},
	{
		Id = "Mouth_07",
		DisplayName = "MOUTH 07",
		Image = "rbxassetid://104940263980708",
		Enabled = true,
	},
	{
		Id = "Mouth_08",
		DisplayName = "MOUTH 08",
		Image = "rbxassetid://95862088788089",
		Enabled = true,
	},
	{
		Id = "Mouth_09",
		DisplayName = "MOUTH 09",
		Image = "rbxassetid://101542721620455",
		Enabled = true,
	},
	{
		Id = "Mouth_10",
		DisplayName = "MOUTH 10",
		Image = "rbxassetid://101790561182781",
		Enabled = true,
	},
	{
		Id = "Mouth_11",
		DisplayName = "MOUTH 11",
		Image = "rbxassetid://98412553595484",
		Enabled = true,
	},
	{
		Id = "Mouth_12",
		DisplayName = "MOUTH 12",
		Image = "rbxassetid://75656211811482",
		Enabled = true,
	},
	{
		Id = "Mouth_13",
		DisplayName = "MOUTH 13",
		Image = "rbxassetid://99938180836888",
		Enabled = true,
	},
}

AppearanceCatalog.BrowStyles = {
	{
		Id = "Brows_01",
		DisplayName = "BROWS 01",
		Image = "rbxassetid://90848604567728",
		Enabled = true,
	},
	{
		Id = "Brows_02",
		DisplayName = "BROWS 02",
		Image = "rbxassetid://124548175202033",
		Enabled = true,
	},
	{
		Id = "Brows_03",
		DisplayName = "BROWS 03",
		Image = "rbxassetid://92800446329551",
		Enabled = true,
	},
	{
		Id = "Brows_04",
		DisplayName = "BROWS 04",
		Image = "rbxassetid://122790280773537",
		Enabled = true,
	},
	{
		Id = "Brows_05",
		DisplayName = "BROWS 05",
		Image = "rbxassetid://114702723888112",
		Enabled = true,
	},
	{
		Id = "Brows_06",
		DisplayName = "BROWS 06",
		Image = "rbxassetid://113652006023288",
		Enabled = true,
	},
	{
		Id = "Brows_07",
		DisplayName = "BROWS 07",
		Image = "rbxassetid://103851550395367",
		Enabled = true,
	},
	{
		Id = "Brows_08",
		DisplayName = "BROWS 08",
		Image = "rbxassetid://79762711665087",
		Enabled = true,
	},
	{
		Id = "Brows_09",
		DisplayName = "BROWS 09",
		Image = "rbxassetid://137944830034187",
		Enabled = true,
	},
	{
		Id = "Brows_10",
		DisplayName = "BROWS 10",
		Image = "rbxassetid://91864316096769",
		Enabled = true,
	},
}

AppearanceCatalog.NoseStyles = {
	{
		Id = "Nose_01",
		DisplayName = "NOSE 01",
		Image = "rbxassetid://137408802101020",
		Enabled = true,
	},
	{
		Id = "Nose_02",
		DisplayName = "NOSE 02",
		Image = "rbxassetid://118973156693372",
		Enabled = true,
	},
	{
		Id = "Nose_03",
		DisplayName = "NOSE 03",
		Image = "rbxassetid://77905703362061",
		Enabled = true,
	},
	{
		Id = "Nose_04",
		DisplayName = "NOSE 04",
		Image = "rbxassetid://138456847613410",
		Enabled = true,
	},
	{
		Id = "Nose_05",
		DisplayName = "NOSE 05",
		Image = "rbxassetid://107264131922840",
		Enabled = true,
	},
	{
		Id = "Nose_06",
		DisplayName = "NOSE 06",
		Image = "rbxassetid://131900543907746",
		Enabled = true,
	},
	{
		Id = "Nose_07",
		DisplayName = "NOSE 07",
		Image = "rbxassetid://112425630231842",
		Enabled = true,
	},
	{
		Id = "Nose_08",
		DisplayName = "NOSE 08",
		Image = "rbxassetid://83014739540414",
		Enabled = true,
	},
	{
		Id = "Nose_09",
		DisplayName = "NOSE 09",
		Image = "rbxassetid://93323143626722",
		Enabled = true,
	},
	{
		Id = "Nose_10",
		DisplayName = "NOSE 10",
		Image = "rbxassetid://86351315461818",
		Enabled = true,
	},
}

AppearanceCatalog.EyeStyles = {
	{
		Id = "Eyes_01",
		DisplayName = "EYES 01",
		Image = "rbxassetid://126836416509295",
		Variants = {
			Sharingan = "rbxassetid://102923811965916",
		},
		Enabled = true,
	},
	{
		Id = "Eyes_02",
		DisplayName = "EYES 02",
		Image = "rbxassetid://139776517559289",
		Variants = {
			Sharingan = "rbxassetid://120034302565938",
		},
		Enabled = true,
	},
	{
		Id = "Eyes_03",
		DisplayName = "EYES 03",
		Image = "rbxassetid://92383275188099",
		Variants = {},
		Enabled = true,
	},
	{
		Id = "Eyes_04",
		DisplayName = "EYES 04",
		Image = "rbxassetid://107099388557874",
		Variants = {
			Sharingan = "rbxassetid://128152857011979",
		},
		Enabled = true,
	},
	{
		Id = "Eyes_05",
		DisplayName = "EYES 05",
		Image = "rbxassetid://126076946216127",
		Variants = {
			Sharingan = "rbxassetid://98522530449219",
		},
		Enabled = true,
	},
	{
		Id = "Eyes_06",
		DisplayName = "EYES 06",
		Image = "rbxassetid://78408569839713",
		Variants = {},
		Enabled = true,
	},
	{
		Id = "Eyes_07",
		DisplayName = "EYES 07",
		Image = "rbxassetid://127934761556709",
		Variants = {},
		Enabled = true,
	},
	{
		Id = "Eyes_08",
		DisplayName = "EYES 08",
		Image = "rbxassetid://96627282523419",
		Variants = {},
		Enabled = true,
	},
	{
		Id = "Eyes_09",
		DisplayName = "EYES 09",
		Image = "rbxassetid://114329564234938",
		Variants = {},
		Enabled = true,
	},
}

AppearanceCatalog.ClothingColors = {
	{
		Id = "Beige",
		DisplayName = "BEIGE",
		TopIds = {
			"StarterTop_Beige_01",
			"StarterTop_Beige_02",
			"StarterTop_Beige_03",
			"StarterTop_Beige_04",
			"StarterTop_Beige_05",
			"StarterTop_Beige_06",
		},
		BottomIds = {
			"StarterBottom_Beige_01",
			"StarterBottom_Beige_02",
			"StarterBottom_Beige_03",
			"StarterBottom_Beige_04",
			"StarterBottom_Beige_05",
			"StarterBottom_Beige_06",
		},
		Enabled = true,
	},
	{
		Id = "Blue",
		DisplayName = "BLUE",
		TopIds = {
			"StarterTop_Blue_01",
			"StarterTop_Blue_02",
			"StarterTop_Blue_03",
			"StarterTop_Blue_04",
			"StarterTop_Blue_05",
			"StarterTop_Blue_06",
		},
		BottomIds = {
			"StarterBottom_Blue_01",
			"StarterBottom_Blue_02",
			"StarterBottom_Blue_03",
			"StarterBottom_Blue_04",
			"StarterBottom_Blue_05",
			"StarterBottom_Blue_06",
		},
		Enabled = true,
	},
	{
		Id = "Brown",
		DisplayName = "BROWN",
		TopIds = {
			"StarterTop_Brown_01",
			"StarterTop_Brown_02",
			"StarterTop_Brown_03",
			"StarterTop_Brown_04",
			"StarterTop_Brown_05",
			"StarterTop_Brown_06",
		},
		BottomIds = {
			"StarterBottom_Brown_01",
			"StarterBottom_Brown_02",
			"StarterBottom_Brown_03",
			"StarterBottom_Brown_04",
			"StarterBottom_Brown_05",
			"StarterBottom_Brown_06",
		},
		Enabled = true,
	},
	{
		Id = "Charcoal",
		DisplayName = "CHARCOAL",
		TopIds = {
			"StarterTop_Charcoal_01",
			"StarterTop_Charcoal_02",
			"StarterTop_Charcoal_03",
			"StarterTop_Charcoal_04",
			"StarterTop_Charcoal_05",
			"StarterTop_Charcoal_06",
		},
		BottomIds = {
			"StarterBottom_Charcoal_01",
			"StarterBottom_Charcoal_02",
			"StarterBottom_Charcoal_03",
			"StarterBottom_Charcoal_04",
			"StarterBottom_Charcoal_05",
			"StarterBottom_Charcoal_06",
		},
		Enabled = true,
	},
	{
		Id = "DarkBrown",
		DisplayName = "DARKBROWN",
		TopIds = {
			"StarterTop_DarkBrown_01",
			"StarterTop_DarkBrown_02",
			"StarterTop_DarkBrown_03",
			"StarterTop_DarkBrown_04",
			"StarterTop_DarkBrown_05",
			"StarterTop_DarkBrown_06",
		},
		BottomIds = {
			"StarterBottom_DarkBrown_01",
			"StarterBottom_DarkBrown_02",
			"StarterBottom_DarkBrown_03",
			"StarterBottom_DarkBrown_04",
			"StarterBottom_DarkBrown_05",
			"StarterBottom_DarkBrown_06",
		},
		Enabled = true,
	},
	{
		Id = "DarkPurple",
		DisplayName = "DARKPURPLE",
		TopIds = {
			"StarterTop_DarkPurple_01",
			"StarterTop_DarkPurple_02",
			"StarterTop_DarkPurple_03",
			"StarterTop_DarkPurple_04",
			"StarterTop_DarkPurple_05",
			"StarterTop_DarkPurple_06",
		},
		BottomIds = {
			"StarterBottom_DarkPurple_01",
			"StarterBottom_DarkPurple_02",
			"StarterBottom_DarkPurple_03",
			"StarterBottom_DarkPurple_04",
			"StarterBottom_DarkPurple_05",
			"StarterBottom_DarkPurple_06",
		},
		Enabled = true,
	},
	{
		Id = "DeepRed",
		DisplayName = "DEEPRED",
		TopIds = {
			"StarterTop_DeepRed_01",
			"StarterTop_DeepRed_02",
			"StarterTop_DeepRed_03",
			"StarterTop_DeepRed_04",
			"StarterTop_DeepRed_05",
			"StarterTop_DeepRed_06",
		},
		BottomIds = {
			"StarterBottom_DeepRed_01",
			"StarterBottom_DeepRed_02",
			"StarterBottom_DeepRed_03",
			"StarterBottom_DeepRed_04",
			"StarterBottom_DeepRed_05",
			"StarterBottom_DeepRed_06",
		},
		Enabled = true,
	},
	{
		Id = "Gray",
		DisplayName = "GRAY",
		TopIds = {
			"StarterTop_Gray_01",
			"StarterTop_Gray_02",
			"StarterTop_Gray_03",
			"StarterTop_Gray_04",
			"StarterTop_Gray_05",
			"StarterTop_Gray_06",
		},
		BottomIds = {
			"StarterBottom_Gray_01",
			"StarterBottom_Gray_02",
			"StarterBottom_Gray_03",
			"StarterBottom_Gray_04",
			"StarterBottom_Gray_05",
			"StarterBottom_Gray_06",
		},
		Enabled = true,
	},
	{
		Id = "Green",
		DisplayName = "GREEN",
		TopIds = {
			"StarterTop_Green_01",
			"StarterTop_Green_02",
			"StarterTop_Green_03",
			"StarterTop_Green_04",
			"StarterTop_Green_05",
			"StarterTop_Green_06",
		},
		BottomIds = {
			"StarterBottom_Green_01",
			"StarterBottom_Green_02",
			"StarterBottom_Green_03",
			"StarterBottom_Green_04",
			"StarterBottom_Green_05",
			"StarterBottom_Green_06",
		},
		Enabled = true,
	},
	{
		Id = "LightBlue",
		DisplayName = "LIGHTBLUE",
		TopIds = {
			"StarterTop_LightBlue_01",
			"StarterTop_LightBlue_02",
			"StarterTop_LightBlue_03",
			"StarterTop_LightBlue_04",
			"StarterTop_LightBlue_05",
			"StarterTop_LightBlue_06",
		},
		BottomIds = {
			"StarterBottom_LightBlue_01",
			"StarterBottom_LightBlue_02",
			"StarterBottom_LightBlue_03",
			"StarterBottom_LightBlue_04",
			"StarterBottom_LightBlue_05",
			"StarterBottom_LightBlue_06",
		},
		Enabled = true,
	},
	{
		Id = "LightPurple",
		DisplayName = "LIGHTPURPLE",
		TopIds = {
			"StarterTop_LightPurple_01",
			"StarterTop_LightPurple_02",
			"StarterTop_LightPurple_03",
			"StarterTop_LightPurple_04",
			"StarterTop_LightPurple_05",
			"StarterTop_LightPurple_06",
		},
		BottomIds = {
			"StarterBottom_LightPurple_01",
			"StarterBottom_LightPurple_02",
			"StarterBottom_LightPurple_03",
			"StarterBottom_LightPurple_04",
			"StarterBottom_LightPurple_05",
			"StarterBottom_LightPurple_06",
		},
		Enabled = true,
	},
	{
		Id = "MutedGreen",
		DisplayName = "MUTEDGREEN",
		TopIds = {
			"StarterTop_MutedGreen_01",
			"StarterTop_MutedGreen_02",
			"StarterTop_MutedGreen_03",
			"StarterTop_MutedGreen_04",
			"StarterTop_MutedGreen_05",
			"StarterTop_MutedGreen_06",
		},
		BottomIds = {
			"StarterBottom_MutedGreen_01",
			"StarterBottom_MutedGreen_02",
			"StarterBottom_MutedGreen_03",
			"StarterBottom_MutedGreen_04",
			"StarterBottom_MutedGreen_05",
			"StarterBottom_MutedGreen_06",
		},
		Enabled = true,
	},
	{
		Id = "OffWhite",
		DisplayName = "OFFWHITE",
		TopIds = {
			"StarterTop_OffWhite_01",
			"StarterTop_OffWhite_02",
			"StarterTop_OffWhite_03",
			"StarterTop_OffWhite_04",
			"StarterTop_OffWhite_05",
			"StarterTop_OffWhite_06",
		},
		BottomIds = {
			"StarterBottom_OffWhite_01",
			"StarterBottom_OffWhite_02",
			"StarterBottom_OffWhite_03",
			"StarterBottom_OffWhite_04",
			"StarterBottom_OffWhite_05",
			"StarterBottom_OffWhite_06",
		},
		Enabled = true,
	},
	{
		Id = "Orange",
		DisplayName = "ORANGE",
		TopIds = {
			"StarterTop_Orange_01",
			"StarterTop_Orange_02",
			"StarterTop_Orange_03",
			"StarterTop_Orange_04",
			"StarterTop_Orange_05",
			"StarterTop_Orange_06",
		},
		BottomIds = {
			"StarterBottom_Orange_01",
			"StarterBottom_Orange_02",
			"StarterBottom_Orange_03",
			"StarterBottom_Orange_04",
			"StarterBottom_Orange_05",
			"StarterBottom_Orange_06",
		},
		Enabled = true,
	},
	{
		Id = "Pink",
		DisplayName = "PINK",
		TopIds = {
			"StarterTop_Pink_01",
			"StarterTop_Pink_02",
			"StarterTop_Pink_03",
			"StarterTop_Pink_04",
			"StarterTop_Pink_05",
			"StarterTop_Pink_06",
		},
		BottomIds = {
			"StarterBottom_Pink_01",
			"StarterBottom_Pink_02",
			"StarterBottom_Pink_03",
			"StarterBottom_Pink_04",
			"StarterBottom_Pink_05",
			"StarterBottom_Pink_06",
		},
		Enabled = true,
	},
	{
		Id = "SlateGray",
		DisplayName = "SLATEGRAY",
		TopIds = {
			"StarterTop_SlateGray_01",
			"StarterTop_SlateGray_02",
			"StarterTop_SlateGray_03",
			"StarterTop_SlateGray_04",
			"StarterTop_SlateGray_05",
			"StarterTop_SlateGray_06",
		},
		BottomIds = {
			"StarterBottom_SlateGray_01",
			"StarterBottom_SlateGray_02",
			"StarterBottom_SlateGray_03",
			"StarterBottom_SlateGray_04",
			"StarterBottom_SlateGray_05",
			"StarterBottom_SlateGray_06",
		},
		Enabled = true,
	},
	{
		Id = "Yellow",
		DisplayName = "YELLOW",
		TopIds = {
			"StarterTop_Yellow_01",
			"StarterTop_Yellow_02",
			"StarterTop_Yellow_03",
			"StarterTop_Yellow_04",
			"StarterTop_Yellow_05",
			"StarterTop_Yellow_06",
		},
		BottomIds = {
			"StarterBottom_Yellow_01",
			"StarterBottom_Yellow_02",
			"StarterBottom_Yellow_03",
			"StarterBottom_Yellow_04",
			"StarterBottom_Yellow_05",
			"StarterBottom_Yellow_06",
		},
		Enabled = true,
	},
}

AppearanceCatalog.StarterTops = {
	{
		Id = "StarterTop_Beige_01",
		DisplayName = "BEIGE TOP 01",
		ColorId = "Beige",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://70521895410432",
		Enabled = true,
	},
	{
		Id = "StarterTop_Beige_02",
		DisplayName = "BEIGE TOP 02",
		ColorId = "Beige",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://133246561836644",
		Enabled = true,
	},
	{
		Id = "StarterTop_Beige_03",
		DisplayName = "BEIGE TOP 03",
		ColorId = "Beige",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://96324192533500",
		Enabled = true,
	},
	{
		Id = "StarterTop_Beige_04",
		DisplayName = "BEIGE TOP 04",
		ColorId = "Beige",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://109455122745074",
		Enabled = true,
	},
	{
		Id = "StarterTop_Beige_05",
		DisplayName = "BEIGE TOP 05",
		ColorId = "Beige",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://92348081143714",
		Enabled = true,
	},
	{
		Id = "StarterTop_Beige_06",
		DisplayName = "BEIGE TOP 06",
		ColorId = "Beige",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://130138497674991",
		Enabled = true,
	},
	{
		Id = "StarterTop_Blue_01",
		DisplayName = "BLUE TOP 01",
		ColorId = "Blue",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://79264608243905",
		Enabled = true,
	},
	{
		Id = "StarterTop_Blue_02",
		DisplayName = "BLUE TOP 02",
		ColorId = "Blue",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://139535804536679",
		Enabled = true,
	},
	{
		Id = "StarterTop_Blue_03",
		DisplayName = "BLUE TOP 03",
		ColorId = "Blue",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://114154715061102",
		Enabled = true,
	},
	{
		Id = "StarterTop_Blue_04",
		DisplayName = "BLUE TOP 04",
		ColorId = "Blue",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://84636518116569",
		Enabled = true,
	},
	{
		Id = "StarterTop_Blue_05",
		DisplayName = "BLUE TOP 05",
		ColorId = "Blue",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://90059241380602",
		Enabled = true,
	},
	{
		Id = "StarterTop_Blue_06",
		DisplayName = "BLUE TOP 06",
		ColorId = "Blue",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://79162086313425",
		Enabled = true,
	},
	{
		Id = "StarterTop_Brown_01",
		DisplayName = "BROWN TOP 01",
		ColorId = "Brown",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://74745067925538",
		Enabled = true,
	},
	{
		Id = "StarterTop_Brown_02",
		DisplayName = "BROWN TOP 02",
		ColorId = "Brown",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://131816697716836",
		Enabled = true,
	},
	{
		Id = "StarterTop_Brown_03",
		DisplayName = "BROWN TOP 03",
		ColorId = "Brown",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://125105638536839",
		Enabled = true,
	},
	{
		Id = "StarterTop_Brown_04",
		DisplayName = "BROWN TOP 04",
		ColorId = "Brown",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://111803660434122",
		Enabled = true,
	},
	{
		Id = "StarterTop_Brown_05",
		DisplayName = "BROWN TOP 05",
		ColorId = "Brown",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://105358771952033",
		Enabled = true,
	},
	{
		Id = "StarterTop_Brown_06",
		DisplayName = "BROWN TOP 06",
		ColorId = "Brown",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://134313158846036",
		Enabled = true,
	},
	{
		Id = "StarterTop_Charcoal_01",
		DisplayName = "CHARCOAL TOP 01",
		ColorId = "Charcoal",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://114096541681827",
		Enabled = true,
	},
	{
		Id = "StarterTop_Charcoal_02",
		DisplayName = "CHARCOAL TOP 02",
		ColorId = "Charcoal",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://74479969120854",
		Enabled = true,
	},
	{
		Id = "StarterTop_Charcoal_03",
		DisplayName = "CHARCOAL TOP 03",
		ColorId = "Charcoal",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://122393939193599",
		Enabled = true,
	},
	{
		Id = "StarterTop_Charcoal_04",
		DisplayName = "CHARCOAL TOP 04",
		ColorId = "Charcoal",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://111203259623556",
		Enabled = true,
	},
	{
		Id = "StarterTop_Charcoal_05",
		DisplayName = "CHARCOAL TOP 05",
		ColorId = "Charcoal",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://86804022818297",
		Enabled = true,
	},
	{
		Id = "StarterTop_Charcoal_06",
		DisplayName = "CHARCOAL TOP 06",
		ColorId = "Charcoal",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://91091832361646",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkBrown_01",
		DisplayName = "DARKBROWN TOP 01",
		ColorId = "DarkBrown",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://134890506049357",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkBrown_02",
		DisplayName = "DARKBROWN TOP 02",
		ColorId = "DarkBrown",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://77246470450738",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkBrown_03",
		DisplayName = "DARKBROWN TOP 03",
		ColorId = "DarkBrown",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://90974125790036",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkBrown_04",
		DisplayName = "DARKBROWN TOP 04",
		ColorId = "DarkBrown",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://81044071228616",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkBrown_05",
		DisplayName = "DARKBROWN TOP 05",
		ColorId = "DarkBrown",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://76263144227043",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkBrown_06",
		DisplayName = "DARKBROWN TOP 06",
		ColorId = "DarkBrown",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://107399337930899",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkPurple_01",
		DisplayName = "DARKPURPLE TOP 01",
		ColorId = "DarkPurple",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://127774041700931",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkPurple_02",
		DisplayName = "DARKPURPLE TOP 02",
		ColorId = "DarkPurple",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://139779095117012",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkPurple_03",
		DisplayName = "DARKPURPLE TOP 03",
		ColorId = "DarkPurple",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://139090258471457",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkPurple_04",
		DisplayName = "DARKPURPLE TOP 04",
		ColorId = "DarkPurple",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://99222423539694",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkPurple_05",
		DisplayName = "DARKPURPLE TOP 05",
		ColorId = "DarkPurple",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://88779421977807",
		Enabled = true,
	},
	{
		Id = "StarterTop_DarkPurple_06",
		DisplayName = "DARKPURPLE TOP 06",
		ColorId = "DarkPurple",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://128281856254797",
		Enabled = true,
	},
	{
		Id = "StarterTop_DeepRed_01",
		DisplayName = "DEEPRED TOP 01",
		ColorId = "DeepRed",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://80023850237388",
		Enabled = true,
	},
	{
		Id = "StarterTop_DeepRed_02",
		DisplayName = "DEEPRED TOP 02",
		ColorId = "DeepRed",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://92000647625001",
		Enabled = true,
	},
	{
		Id = "StarterTop_DeepRed_03",
		DisplayName = "DEEPRED TOP 03",
		ColorId = "DeepRed",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://96112427479178",
		Enabled = true,
	},
	{
		Id = "StarterTop_DeepRed_04",
		DisplayName = "DEEPRED TOP 04",
		ColorId = "DeepRed",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://94796890816073",
		Enabled = true,
	},
	{
		Id = "StarterTop_DeepRed_05",
		DisplayName = "DEEPRED TOP 05",
		ColorId = "DeepRed",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://103601036013839",
		Enabled = true,
	},
	{
		Id = "StarterTop_DeepRed_06",
		DisplayName = "DEEPRED TOP 06",
		ColorId = "DeepRed",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://87586841864436",
		Enabled = true,
	},
	{
		Id = "StarterTop_Gray_01",
		DisplayName = "GRAY TOP 01",
		ColorId = "Gray",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://85040754330057",
		Enabled = true,
	},
	{
		Id = "StarterTop_Gray_02",
		DisplayName = "GRAY TOP 02",
		ColorId = "Gray",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://111154465321433",
		Enabled = true,
	},
	{
		Id = "StarterTop_Gray_03",
		DisplayName = "GRAY TOP 03",
		ColorId = "Gray",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://83150342758969",
		Enabled = true,
	},
	{
		Id = "StarterTop_Gray_04",
		DisplayName = "GRAY TOP 04",
		ColorId = "Gray",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://125667056262708",
		Enabled = true,
	},
	{
		Id = "StarterTop_Gray_05",
		DisplayName = "GRAY TOP 05",
		ColorId = "Gray",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://78350859269534",
		Enabled = true,
	},
	{
		Id = "StarterTop_Gray_06",
		DisplayName = "GRAY TOP 06",
		ColorId = "Gray",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://101893141483073",
		Enabled = true,
	},
	{
		Id = "StarterTop_Green_01",
		DisplayName = "GREEN TOP 01",
		ColorId = "Green",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://91452635408871",
		Enabled = true,
	},
	{
		Id = "StarterTop_Green_02",
		DisplayName = "GREEN TOP 02",
		ColorId = "Green",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://136037892126486",
		Enabled = true,
	},
	{
		Id = "StarterTop_Green_03",
		DisplayName = "GREEN TOP 03",
		ColorId = "Green",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://72867761039444",
		Enabled = true,
	},
	{
		Id = "StarterTop_Green_04",
		DisplayName = "GREEN TOP 04",
		ColorId = "Green",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://79449292328177",
		Enabled = true,
	},
	{
		Id = "StarterTop_Green_05",
		DisplayName = "GREEN TOP 05",
		ColorId = "Green",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://134654109370411",
		Enabled = true,
	},
	{
		Id = "StarterTop_Green_06",
		DisplayName = "GREEN TOP 06",
		ColorId = "Green",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://132869836698792",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightBlue_01",
		DisplayName = "LIGHTBLUE TOP 01",
		ColorId = "LightBlue",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://93134621400057",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightBlue_02",
		DisplayName = "LIGHTBLUE TOP 02",
		ColorId = "LightBlue",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://118357367672974",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightBlue_03",
		DisplayName = "LIGHTBLUE TOP 03",
		ColorId = "LightBlue",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://98212661483654",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightBlue_04",
		DisplayName = "LIGHTBLUE TOP 04",
		ColorId = "LightBlue",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://101507220748126",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightBlue_05",
		DisplayName = "LIGHTBLUE TOP 05",
		ColorId = "LightBlue",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://124317615793791",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightBlue_06",
		DisplayName = "LIGHTBLUE TOP 06",
		ColorId = "LightBlue",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://108795357811903",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightPurple_01",
		DisplayName = "LIGHTPURPLE TOP 01",
		ColorId = "LightPurple",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://70408866215016",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightPurple_02",
		DisplayName = "LIGHTPURPLE TOP 02",
		ColorId = "LightPurple",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://74286142617033",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightPurple_03",
		DisplayName = "LIGHTPURPLE TOP 03",
		ColorId = "LightPurple",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://77224194323743",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightPurple_04",
		DisplayName = "LIGHTPURPLE TOP 04",
		ColorId = "LightPurple",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://133821793654033",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightPurple_05",
		DisplayName = "LIGHTPURPLE TOP 05",
		ColorId = "LightPurple",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://97204332512014",
		Enabled = true,
	},
	{
		Id = "StarterTop_LightPurple_06",
		DisplayName = "LIGHTPURPLE TOP 06",
		ColorId = "LightPurple",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://79815145008474",
		Enabled = true,
	},
	{
		Id = "StarterTop_MutedGreen_01",
		DisplayName = "MUTEDGREEN TOP 01",
		ColorId = "MutedGreen",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://93501780318982",
		Enabled = true,
	},
	{
		Id = "StarterTop_MutedGreen_02",
		DisplayName = "MUTEDGREEN TOP 02",
		ColorId = "MutedGreen",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://132889864791326",
		Enabled = true,
	},
	{
		Id = "StarterTop_MutedGreen_03",
		DisplayName = "MUTEDGREEN TOP 03",
		ColorId = "MutedGreen",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://111811255369322",
		Enabled = true,
	},
	{
		Id = "StarterTop_MutedGreen_04",
		DisplayName = "MUTEDGREEN TOP 04",
		ColorId = "MutedGreen",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://116140038500221",
		Enabled = true,
	},
	{
		Id = "StarterTop_MutedGreen_05",
		DisplayName = "MUTEDGREEN TOP 05",
		ColorId = "MutedGreen",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://82823471672887",
		Enabled = true,
	},
	{
		Id = "StarterTop_MutedGreen_06",
		DisplayName = "MUTEDGREEN TOP 06",
		ColorId = "MutedGreen",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://123586084197972",
		Enabled = true,
	},
	{
		Id = "StarterTop_OffWhite_01",
		DisplayName = "OFFWHITE TOP 01",
		ColorId = "OffWhite",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://103968678820112",
		Enabled = true,
	},
	{
		Id = "StarterTop_OffWhite_02",
		DisplayName = "OFFWHITE TOP 02",
		ColorId = "OffWhite",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://98125243032736",
		Enabled = true,
	},
	{
		Id = "StarterTop_OffWhite_03",
		DisplayName = "OFFWHITE TOP 03",
		ColorId = "OffWhite",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://136428420324011",
		Enabled = true,
	},
	{
		Id = "StarterTop_OffWhite_04",
		DisplayName = "OFFWHITE TOP 04",
		ColorId = "OffWhite",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://123699063525231",
		Enabled = true,
	},
	{
		Id = "StarterTop_OffWhite_05",
		DisplayName = "OFFWHITE TOP 05",
		ColorId = "OffWhite",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://80269479723387",
		Enabled = true,
	},
	{
		Id = "StarterTop_OffWhite_06",
		DisplayName = "OFFWHITE TOP 06",
		ColorId = "OffWhite",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://72406143361229",
		Enabled = true,
	},
	{
		Id = "StarterTop_Orange_01",
		DisplayName = "ORANGE TOP 01",
		ColorId = "Orange",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://74401484444080",
		Enabled = true,
	},
	{
		Id = "StarterTop_Orange_02",
		DisplayName = "ORANGE TOP 02",
		ColorId = "Orange",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://85466814370930",
		Enabled = true,
	},
	{
		Id = "StarterTop_Orange_03",
		DisplayName = "ORANGE TOP 03",
		ColorId = "Orange",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://74139879658331",
		Enabled = true,
	},
	{
		Id = "StarterTop_Orange_04",
		DisplayName = "ORANGE TOP 04",
		ColorId = "Orange",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://117559103224287",
		Enabled = true,
	},
	{
		Id = "StarterTop_Orange_05",
		DisplayName = "ORANGE TOP 05",
		ColorId = "Orange",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://78083171084239",
		Enabled = true,
	},
	{
		Id = "StarterTop_Orange_06",
		DisplayName = "ORANGE TOP 06",
		ColorId = "Orange",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://114698436556042",
		Enabled = true,
	},
	{
		Id = "StarterTop_Pink_01",
		DisplayName = "PINK TOP 01",
		ColorId = "Pink",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://79851931296877",
		Enabled = true,
	},
	{
		Id = "StarterTop_Pink_02",
		DisplayName = "PINK TOP 02",
		ColorId = "Pink",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://85769493279590",
		Enabled = true,
	},
	{
		Id = "StarterTop_Pink_03",
		DisplayName = "PINK TOP 03",
		ColorId = "Pink",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://71402203303763",
		Enabled = true,
	},
	{
		Id = "StarterTop_Pink_04",
		DisplayName = "PINK TOP 04",
		ColorId = "Pink",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://91545349752114",
		Enabled = true,
	},
	{
		Id = "StarterTop_Pink_05",
		DisplayName = "PINK TOP 05",
		ColorId = "Pink",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://105093172892129",
		Enabled = true,
	},
	{
		Id = "StarterTop_Pink_06",
		DisplayName = "PINK TOP 06",
		ColorId = "Pink",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://134718851471015",
		Enabled = true,
	},
	{
		Id = "StarterTop_SlateGray_01",
		DisplayName = "SLATEGRAY TOP 01",
		ColorId = "SlateGray",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://117687230906987",
		Enabled = true,
	},
	{
		Id = "StarterTop_SlateGray_02",
		DisplayName = "SLATEGRAY TOP 02",
		ColorId = "SlateGray",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://132517911563206",
		Enabled = true,
	},
	{
		Id = "StarterTop_SlateGray_03",
		DisplayName = "SLATEGRAY TOP 03",
		ColorId = "SlateGray",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://86585025405323",
		Enabled = true,
	},
	{
		Id = "StarterTop_SlateGray_04",
		DisplayName = "SLATEGRAY TOP 04",
		ColorId = "SlateGray",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://76161513538680",
		Enabled = true,
	},
	{
		Id = "StarterTop_SlateGray_05",
		DisplayName = "SLATEGRAY TOP 05",
		ColorId = "SlateGray",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://98085634970759",
		Enabled = true,
	},
	{
		Id = "StarterTop_SlateGray_06",
		DisplayName = "SLATEGRAY TOP 06",
		ColorId = "SlateGray",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://91266364818594",
		Enabled = true,
	},
	{
		Id = "StarterTop_Yellow_01",
		DisplayName = "YELLOW TOP 01",
		ColorId = "Yellow",
		VariantIndex = 1,
		ShirtTemplate = "rbxassetid://85678936189096",
		Enabled = true,
	},
	{
		Id = "StarterTop_Yellow_02",
		DisplayName = "YELLOW TOP 02",
		ColorId = "Yellow",
		VariantIndex = 2,
		ShirtTemplate = "rbxassetid://127577639995087",
		Enabled = true,
	},
	{
		Id = "StarterTop_Yellow_03",
		DisplayName = "YELLOW TOP 03",
		ColorId = "Yellow",
		VariantIndex = 3,
		ShirtTemplate = "rbxassetid://133048641837924",
		Enabled = true,
	},
	{
		Id = "StarterTop_Yellow_04",
		DisplayName = "YELLOW TOP 04",
		ColorId = "Yellow",
		VariantIndex = 4,
		ShirtTemplate = "rbxassetid://74338491865392",
		Enabled = true,
	},
	{
		Id = "StarterTop_Yellow_05",
		DisplayName = "YELLOW TOP 05",
		ColorId = "Yellow",
		VariantIndex = 5,
		ShirtTemplate = "rbxassetid://121597835372865",
		Enabled = true,
	},
	{
		Id = "StarterTop_Yellow_06",
		DisplayName = "YELLOW TOP 06",
		ColorId = "Yellow",
		VariantIndex = 6,
		ShirtTemplate = "rbxassetid://75381376556425",
		Enabled = true,
	},
}

AppearanceCatalog.StarterBottoms = {
	{
		Id = "StarterBottom_Beige_01",
		DisplayName = "BEIGE BOTTOM 01",
		ColorId = "Beige",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://115442403666948",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Beige_02",
		DisplayName = "BEIGE BOTTOM 02",
		ColorId = "Beige",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://93513181509708",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Beige_03",
		DisplayName = "BEIGE BOTTOM 03",
		ColorId = "Beige",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://94869159030731",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Beige_04",
		DisplayName = "BEIGE BOTTOM 04",
		ColorId = "Beige",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://75148316547965",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Beige_05",
		DisplayName = "BEIGE BOTTOM 05",
		ColorId = "Beige",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://119854320976649",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Beige_06",
		DisplayName = "BEIGE BOTTOM 06",
		ColorId = "Beige",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://103665166736917",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Blue_01",
		DisplayName = "BLUE BOTTOM 01",
		ColorId = "Blue",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://108071810527062",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Blue_02",
		DisplayName = "BLUE BOTTOM 02",
		ColorId = "Blue",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://106469458108494",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Blue_03",
		DisplayName = "BLUE BOTTOM 03",
		ColorId = "Blue",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://125893228499026",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Blue_04",
		DisplayName = "BLUE BOTTOM 04",
		ColorId = "Blue",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://103767881209955",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Blue_05",
		DisplayName = "BLUE BOTTOM 05",
		ColorId = "Blue",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://115919311029788",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Blue_06",
		DisplayName = "BLUE BOTTOM 06",
		ColorId = "Blue",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://133469326354270",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Brown_01",
		DisplayName = "BROWN BOTTOM 01",
		ColorId = "Brown",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://125779362590745",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Brown_02",
		DisplayName = "BROWN BOTTOM 02",
		ColorId = "Brown",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://138875896374851",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Brown_03",
		DisplayName = "BROWN BOTTOM 03",
		ColorId = "Brown",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://90834773223064",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Brown_04",
		DisplayName = "BROWN BOTTOM 04",
		ColorId = "Brown",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://80968613909695",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Brown_05",
		DisplayName = "BROWN BOTTOM 05",
		ColorId = "Brown",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://99932278601201",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Brown_06",
		DisplayName = "BROWN BOTTOM 06",
		ColorId = "Brown",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://102512284506298",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Charcoal_01",
		DisplayName = "CHARCOAL BOTTOM 01",
		ColorId = "Charcoal",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://138637941176160",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Charcoal_02",
		DisplayName = "CHARCOAL BOTTOM 02",
		ColorId = "Charcoal",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://125268517209813",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Charcoal_03",
		DisplayName = "CHARCOAL BOTTOM 03",
		ColorId = "Charcoal",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://84616465102508",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Charcoal_04",
		DisplayName = "CHARCOAL BOTTOM 04",
		ColorId = "Charcoal",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://105365058428452",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Charcoal_05",
		DisplayName = "CHARCOAL BOTTOM 05",
		ColorId = "Charcoal",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://121468851596596",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Charcoal_06",
		DisplayName = "CHARCOAL BOTTOM 06",
		ColorId = "Charcoal",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://103433775017127",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkBrown_01",
		DisplayName = "DARKBROWN BOTTOM 01",
		ColorId = "DarkBrown",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://128209413747404",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkBrown_02",
		DisplayName = "DARKBROWN BOTTOM 02",
		ColorId = "DarkBrown",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://114501465370399",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkBrown_03",
		DisplayName = "DARKBROWN BOTTOM 03",
		ColorId = "DarkBrown",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://104271079264347",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkBrown_04",
		DisplayName = "DARKBROWN BOTTOM 04",
		ColorId = "DarkBrown",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://95055665931547",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkBrown_05",
		DisplayName = "DARKBROWN BOTTOM 05",
		ColorId = "DarkBrown",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://78345334798229",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkBrown_06",
		DisplayName = "DARKBROWN BOTTOM 06",
		ColorId = "DarkBrown",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://117851110938871",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkPurple_01",
		DisplayName = "DARKPURPLE BOTTOM 01",
		ColorId = "DarkPurple",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://116836260187105",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkPurple_02",
		DisplayName = "DARKPURPLE BOTTOM 02",
		ColorId = "DarkPurple",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://77547320169776",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkPurple_03",
		DisplayName = "DARKPURPLE BOTTOM 03",
		ColorId = "DarkPurple",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://134506953321774",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkPurple_04",
		DisplayName = "DARKPURPLE BOTTOM 04",
		ColorId = "DarkPurple",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://138658221248198",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkPurple_05",
		DisplayName = "DARKPURPLE BOTTOM 05",
		ColorId = "DarkPurple",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://103449958814112",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DarkPurple_06",
		DisplayName = "DARKPURPLE BOTTOM 06",
		ColorId = "DarkPurple",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://105999317677773",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DeepRed_01",
		DisplayName = "DEEPRED BOTTOM 01",
		ColorId = "DeepRed",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://105658135998706",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DeepRed_02",
		DisplayName = "DEEPRED BOTTOM 02",
		ColorId = "DeepRed",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://79896317333529",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DeepRed_03",
		DisplayName = "DEEPRED BOTTOM 03",
		ColorId = "DeepRed",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://115428652500650",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DeepRed_04",
		DisplayName = "DEEPRED BOTTOM 04",
		ColorId = "DeepRed",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://111403900410897",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DeepRed_05",
		DisplayName = "DEEPRED BOTTOM 05",
		ColorId = "DeepRed",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://115652385311791",
		Enabled = true,
	},
	{
		Id = "StarterBottom_DeepRed_06",
		DisplayName = "DEEPRED BOTTOM 06",
		ColorId = "DeepRed",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://78721139728318",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Gray_01",
		DisplayName = "GRAY BOTTOM 01",
		ColorId = "Gray",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://118969368396781",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Gray_02",
		DisplayName = "GRAY BOTTOM 02",
		ColorId = "Gray",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://116738218702630",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Gray_03",
		DisplayName = "GRAY BOTTOM 03",
		ColorId = "Gray",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://85669124672013",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Gray_04",
		DisplayName = "GRAY BOTTOM 04",
		ColorId = "Gray",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://104596346901705",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Gray_05",
		DisplayName = "GRAY BOTTOM 05",
		ColorId = "Gray",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://140551331019530",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Gray_06",
		DisplayName = "GRAY BOTTOM 06",
		ColorId = "Gray",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://76578160925449",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Green_01",
		DisplayName = "GREEN BOTTOM 01",
		ColorId = "Green",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://116439775363897",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Green_02",
		DisplayName = "GREEN BOTTOM 02",
		ColorId = "Green",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://99109783291418",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Green_03",
		DisplayName = "GREEN BOTTOM 03",
		ColorId = "Green",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://91787117719447",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Green_04",
		DisplayName = "GREEN BOTTOM 04",
		ColorId = "Green",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://121959162731096",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Green_05",
		DisplayName = "GREEN BOTTOM 05",
		ColorId = "Green",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://137504402457639",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Green_06",
		DisplayName = "GREEN BOTTOM 06",
		ColorId = "Green",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://76529872611289",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightBlue_01",
		DisplayName = "LIGHTBLUE BOTTOM 01",
		ColorId = "LightBlue",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://95499775655427",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightBlue_02",
		DisplayName = "LIGHTBLUE BOTTOM 02",
		ColorId = "LightBlue",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://105449298751443",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightBlue_03",
		DisplayName = "LIGHTBLUE BOTTOM 03",
		ColorId = "LightBlue",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://111690544128425",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightBlue_04",
		DisplayName = "LIGHTBLUE BOTTOM 04",
		ColorId = "LightBlue",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://108685545928323",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightBlue_05",
		DisplayName = "LIGHTBLUE BOTTOM 05",
		ColorId = "LightBlue",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://90066150390407",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightBlue_06",
		DisplayName = "LIGHTBLUE BOTTOM 06",
		ColorId = "LightBlue",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://126453259835038",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightPurple_01",
		DisplayName = "LIGHTPURPLE BOTTOM 01",
		ColorId = "LightPurple",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://94260190034943",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightPurple_02",
		DisplayName = "LIGHTPURPLE BOTTOM 02",
		ColorId = "LightPurple",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://80193617216799",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightPurple_03",
		DisplayName = "LIGHTPURPLE BOTTOM 03",
		ColorId = "LightPurple",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://97801180973935",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightPurple_04",
		DisplayName = "LIGHTPURPLE BOTTOM 04",
		ColorId = "LightPurple",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://120443783161812",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightPurple_05",
		DisplayName = "LIGHTPURPLE BOTTOM 05",
		ColorId = "LightPurple",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://127586377396365",
		Enabled = true,
	},
	{
		Id = "StarterBottom_LightPurple_06",
		DisplayName = "LIGHTPURPLE BOTTOM 06",
		ColorId = "LightPurple",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://80937679958671",
		Enabled = true,
	},
	{
		Id = "StarterBottom_MutedGreen_01",
		DisplayName = "MUTEDGREEN BOTTOM 01",
		ColorId = "MutedGreen",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://84919000341290",
		Enabled = true,
	},
	{
		Id = "StarterBottom_MutedGreen_02",
		DisplayName = "MUTEDGREEN BOTTOM 02",
		ColorId = "MutedGreen",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://115682632268863",
		Enabled = true,
	},
	{
		Id = "StarterBottom_MutedGreen_03",
		DisplayName = "MUTEDGREEN BOTTOM 03",
		ColorId = "MutedGreen",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://110167537261917",
		Enabled = true,
	},
	{
		Id = "StarterBottom_MutedGreen_04",
		DisplayName = "MUTEDGREEN BOTTOM 04",
		ColorId = "MutedGreen",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://82897679510818",
		Enabled = true,
	},
	{
		Id = "StarterBottom_MutedGreen_05",
		DisplayName = "MUTEDGREEN BOTTOM 05",
		ColorId = "MutedGreen",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://109529121336278",
		Enabled = true,
	},
	{
		Id = "StarterBottom_MutedGreen_06",
		DisplayName = "MUTEDGREEN BOTTOM 06",
		ColorId = "MutedGreen",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://132115858765524",
		Enabled = true,
	},
	{
		Id = "StarterBottom_OffWhite_01",
		DisplayName = "OFFWHITE BOTTOM 01",
		ColorId = "OffWhite",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://114626150337819",
		Enabled = true,
	},
	{
		Id = "StarterBottom_OffWhite_02",
		DisplayName = "OFFWHITE BOTTOM 02",
		ColorId = "OffWhite",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://75507575508512",
		Enabled = true,
	},
	{
		Id = "StarterBottom_OffWhite_03",
		DisplayName = "OFFWHITE BOTTOM 03",
		ColorId = "OffWhite",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://112927428810465",
		Enabled = true,
	},
	{
		Id = "StarterBottom_OffWhite_04",
		DisplayName = "OFFWHITE BOTTOM 04",
		ColorId = "OffWhite",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://113569648185386",
		Enabled = true,
	},
	{
		Id = "StarterBottom_OffWhite_05",
		DisplayName = "OFFWHITE BOTTOM 05",
		ColorId = "OffWhite",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://86787586630195",
		Enabled = true,
	},
	{
		Id = "StarterBottom_OffWhite_06",
		DisplayName = "OFFWHITE BOTTOM 06",
		ColorId = "OffWhite",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://98590786541996",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Orange_01",
		DisplayName = "ORANGE BOTTOM 01",
		ColorId = "Orange",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://72032060773686",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Orange_02",
		DisplayName = "ORANGE BOTTOM 02",
		ColorId = "Orange",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://103861827663879",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Orange_03",
		DisplayName = "ORANGE BOTTOM 03",
		ColorId = "Orange",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://93004603379676",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Orange_04",
		DisplayName = "ORANGE BOTTOM 04",
		ColorId = "Orange",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://112484245413771",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Orange_05",
		DisplayName = "ORANGE BOTTOM 05",
		ColorId = "Orange",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://133766451243688",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Orange_06",
		DisplayName = "ORANGE BOTTOM 06",
		ColorId = "Orange",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://77326736517052",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Pink_01",
		DisplayName = "PINK BOTTOM 01",
		ColorId = "Pink",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://129612130645712",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Pink_02",
		DisplayName = "PINK BOTTOM 02",
		ColorId = "Pink",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://94113045273668",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Pink_03",
		DisplayName = "PINK BOTTOM 03",
		ColorId = "Pink",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://79860271593871",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Pink_04",
		DisplayName = "PINK BOTTOM 04",
		ColorId = "Pink",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://90324680242737",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Pink_05",
		DisplayName = "PINK BOTTOM 05",
		ColorId = "Pink",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://119154700443040",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Pink_06",
		DisplayName = "PINK BOTTOM 06",
		ColorId = "Pink",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://88225242831261",
		Enabled = true,
	},
	{
		Id = "StarterBottom_SlateGray_01",
		DisplayName = "SLATEGRAY BOTTOM 01",
		ColorId = "SlateGray",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://104679834273142",
		Enabled = true,
	},
	{
		Id = "StarterBottom_SlateGray_02",
		DisplayName = "SLATEGRAY BOTTOM 02",
		ColorId = "SlateGray",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://81301415281589",
		Enabled = true,
	},
	{
		Id = "StarterBottom_SlateGray_03",
		DisplayName = "SLATEGRAY BOTTOM 03",
		ColorId = "SlateGray",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://116986878104524",
		Enabled = true,
	},
	{
		Id = "StarterBottom_SlateGray_04",
		DisplayName = "SLATEGRAY BOTTOM 04",
		ColorId = "SlateGray",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://115310197191164",
		Enabled = true,
	},
	{
		Id = "StarterBottom_SlateGray_05",
		DisplayName = "SLATEGRAY BOTTOM 05",
		ColorId = "SlateGray",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://133502532243146",
		Enabled = true,
	},
	{
		Id = "StarterBottom_SlateGray_06",
		DisplayName = "SLATEGRAY BOTTOM 06",
		ColorId = "SlateGray",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://105214847382971",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Yellow_01",
		DisplayName = "YELLOW BOTTOM 01",
		ColorId = "Yellow",
		VariantIndex = 1,
		PantsTemplate = "rbxassetid://73591284164673",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Yellow_02",
		DisplayName = "YELLOW BOTTOM 02",
		ColorId = "Yellow",
		VariantIndex = 2,
		PantsTemplate = "rbxassetid://103231347251799",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Yellow_03",
		DisplayName = "YELLOW BOTTOM 03",
		ColorId = "Yellow",
		VariantIndex = 3,
		PantsTemplate = "rbxassetid://119983733431837",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Yellow_04",
		DisplayName = "YELLOW BOTTOM 04",
		ColorId = "Yellow",
		VariantIndex = 4,
		PantsTemplate = "rbxassetid://131425407685408",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Yellow_05",
		DisplayName = "YELLOW BOTTOM 05",
		ColorId = "Yellow",
		VariantIndex = 5,
		PantsTemplate = "rbxassetid://107058005097176",
		Enabled = true,
	},
	{
		Id = "StarterBottom_Yellow_06",
		DisplayName = "YELLOW BOTTOM 06",
		ColorId = "Yellow",
		VariantIndex = 6,
		PantsTemplate = "rbxassetid://120111150937328",
		Enabled = true,
	},
}


AppearanceCatalog.ShoesStyles = {
	{
		Id = "Shoes_01",
		DisplayName = "SHOES 01",
		AssetId = 84851731317299,
		Enabled = true,
	},
}

AppearanceCatalog.GlovesStyles = {
	{
		Id = "Gloves_None",
		DisplayName = "NONE",
		None = true,
		Enabled = true,
	},
	{
		Id = "Gloves_01",
		DisplayName = "GLOVES 01",
		AssetId = 122740335382636,
		Enabled = true,
	},
}

AppearanceCatalog.Defaults = {
	SkinToneId = "S05",

	-- Legacy only.
	FaceStyleId = "Default",

	MouthStyleId = "Mouth_01",
	BrowStyleId = "Brows_01",
	NoseStyleId = "Nose_01",
	EyeStyleId = "Eyes_01",

	ShoesStyleId = "Shoes_01",
	GlovesStyleId = "Gloves_None",

	StarterTopId = "StarterTop_Beige_01",
	StarterBottomId = "StarterBottom_Beige_01",
}

-- EyeStyleId is the permanent base eye shape selected by the player.
-- Doujutsu variants are runtime-only and never selectable in Character Creation.
-- Current runtime variant key: "Sharingan".
-- Missing matching variants intentionally fall back to Base.
AppearanceCatalog.DefaultEyeVariantId = "Base"

local function findById(list: {{[string]: any}}, id: string): {[string]: any}?
	for _, entry in ipairs(list) do
		if entry.Id == id then
			return entry
		end
	end

	return nil
end

function AppearanceCatalog.ResolveSkinToneId(raw: any): string?
	if typeof(raw) ~= "string" or raw == "" then
		return nil
	end

	local alias = AppearanceCatalog.LegacySkinToneAliases[raw]
	if alias then
		return alias
	end

	return findById(AppearanceCatalog.SkinTones, raw) and raw or nil
end

function AppearanceCatalog.GetSkinTone(id: string): {[string]: any}?
	local resolved = AppearanceCatalog.ResolveSkinToneId(id)
	return resolved and findById(AppearanceCatalog.SkinTones, resolved) or nil
end

function AppearanceCatalog.GetFaceStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.FaceStyles, id)
end

function AppearanceCatalog.GetMouthStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.MouthStyles, id)
end

function AppearanceCatalog.GetBrowStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.BrowStyles, id)
end

function AppearanceCatalog.GetNoseStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.NoseStyles, id)
end

function AppearanceCatalog.GetEyeStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.EyeStyles, id)
end

function AppearanceCatalog.GetEyeImage(
	eyeStyleId: string,
	variantId: any
): string?
	local entry =
		AppearanceCatalog.GetEyeStyle(
			eyeStyleId
		)

	if not entry then
		return nil
	end

	if typeof(variantId) == "string"
		and variantId ~= ""
		and variantId ~= "Base"
		and typeof(entry.Variants) == "table" then

		local variant =
			entry.Variants[variantId]

		if typeof(variant) == "string"
			and variant ~= "" then

			return variant
		end
	end

	return typeof(entry.Image) == "string"
		and entry.Image
		or nil
end

function AppearanceCatalog.GetShoesStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.ShoesStyles, id)
end

function AppearanceCatalog.GetGlovesStyle(id: string): {[string]: any}?
	return findById(AppearanceCatalog.GlovesStyles, id)
end

function AppearanceCatalog.IsValidShoesStyle(id: string): boolean
	local entry = AppearanceCatalog.GetShoesStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidGlovesStyle(id: string): boolean
	local entry = AppearanceCatalog.GetGlovesStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.GetClothingColor(id: string): {[string]: any}?
	return findById(AppearanceCatalog.ClothingColors, id)
end

function AppearanceCatalog.IsValidClothingColor(id: string): boolean
	local entry = AppearanceCatalog.GetClothingColor(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.GetStarterTop(id: string): {[string]: any}?
	return findById(AppearanceCatalog.StarterTops, id)
end

function AppearanceCatalog.GetStarterBottom(id: string): {[string]: any}?
	return findById(AppearanceCatalog.StarterBottoms, id)
end

function AppearanceCatalog.IsValidFaceStyle(id: string): boolean
	local entry = AppearanceCatalog.GetFaceStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidMouthStyle(id: string): boolean
	local entry = AppearanceCatalog.GetMouthStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidBrowStyle(id: string): boolean
	local entry = AppearanceCatalog.GetBrowStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidNoseStyle(id: string): boolean
	local entry = AppearanceCatalog.GetNoseStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidEyeStyle(id: string): boolean
	local entry = AppearanceCatalog.GetEyeStyle(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidStarterTop(id: string): boolean
	local entry = AppearanceCatalog.GetStarterTop(id)
	return entry ~= nil and entry.Enabled ~= false
end

function AppearanceCatalog.IsValidStarterBottom(id: string): boolean
	local entry = AppearanceCatalog.GetStarterBottom(id)
	return entry ~= nil and entry.Enabled ~= false
end

return AppearanceCatalog
