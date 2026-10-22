--!strict
-- ReplicatedStorage > Shared > ServerListConfig
-- WAYLESS ServerList v1.1 candidate — Astra ServerList.zip exact visual contract.

local ServerListConfig = {
	ReferenceViewport = Vector2.new(1920, 1080),

	Fonts = {
		Title = Font.new("rbxasset://fonts/families/Fondamento.json"),
		Body = Font.new("rbxasset://fonts/families/Merriweather.json"),
	},

	Assets = {
		HeaderFrame = "rbxassetid://134410389036793",
		TitleBrush = "rbxassetid://96150233450677",
		LeafBackground = "rbxassetid://124976450016156",
		SandBackground = "rbxassetid://117504804119338",
		MistBackground = "rbxassetid://140367900515787",
		CloudBackground = "rbxassetid://127336446597927",
		StoneBackground = "rbxassetid://109591695667841",
		PlayerCloud = "rbxassetid://85016819124762",
		Divider = "rbxassetid://75676522601489",
	},

	AssetMeta = {
		HeaderFrame = {
			Canvas = Vector2.new(2109, 746),
			Bounds = {67, 213, 1977, 306},
		},
		TitleBrush = {
			Canvas = Vector2.new(1774, 887),
			Bounds = {113, 311, 1546, 326},
		},
	},

	Layout = {
		Right = 30,
		Top = 35,
		Width = 306,
		Height = 466,

		ServerButton = {
			Position = Vector2.new(292, 22),
			Size = Vector2.new(110, 38),
		},

		Title = {
			Position = Vector2.new(17, 10),
			Size = Vector2.new(126, 35),
			FontSize = 25,
		},
		TitleBrush = {
			-- Exact approved preview geometry derived from the original full PNG
			-- after content-bounds compensation.
			Position = Vector2.new(-9.16, -28.21),
			Size = Vector2.new(206.55, 103.27),
		},
		PlayerCount = {
			Position = Vector2.new(183, 16),
			Size = Vector2.new(77, 22),
			FontSize = 10,
		},
		Close = {
			Position = Vector2.new(270, 8),
			Size = Vector2.new(26, 30),
			FontSize = 21,
		},
		DividerY = 52,
		DividerIcon = 14,

		List = {
			Position = Vector2.new(8, 67),
			Size = Vector2.new(290, 362),
		},

		Footer = {
			Position = Vector2.new(8, 438),
			Size = Vector2.new(290, 18),
			FontSize = 9,
		},

		VillageGap = 12,
		VillageWidth = 284,
		HeaderHeight = 44,
		HeaderFrame = {
			-- Exact approved preview geometry:
			-- 106.6768% width, -3.38897% left, -69.60784% top.
			Position = Vector2.new(-9.625, -30.598),
			Size = Vector2.new(302.962, 107.17),
		},
		HeaderBackgroundInset = Vector2.new(4, 3),

		PlayerRowHeight = 43,
		PlayerActionExtraHeight = 36,
	},

	Animation = {
		Join = 0.250,
		Leave = 0.180,
		Reflow = 0.240,
		ChangeVillage = 0.260,
		Collapse = 0.250,
		Open = 0.250,
		Close = 0.180,
	},

	-- The visual package treats names/colors/letters as configurable data.
	-- These are the WAYLESS labels currently used by this candidate.
	Villages = {
		{
			Key = "leaf",
			DisplayName = "KAZEHA",
			Letter = "K",
			Color = Color3.fromRGB(159, 207, 121),
			Background = "LeafBackground",
			Aliases = {"village_leaf", "leaf", "konoha", "kazeha"},
		},
		{
			Key = "sand",
			DisplayName = "SARYU",
			Letter = "S",
			Color = Color3.fromRGB(230, 185, 96),
			Background = "SandBackground",
			Aliases = {"village_sand", "sand", "sunagakure", "saryu"},
		},
		{
			Key = "mist",
			DisplayName = "KASUMI",
			Letter = "K",
			Color = Color3.fromRGB(125, 198, 223),
			Background = "MistBackground",
			Aliases = {"village_mist", "mist", "kirigakure", "kasumi"},
		},
		{
			Key = "cloud",
			DisplayName = "RAIKUMO",
			Letter = "R",
			Color = Color3.fromRGB(174, 154, 232),
			Background = "CloudBackground",
			Aliases = {"village_cloud", "cloud", "kumogakure", "raikumo"},
		},
		{
			Key = "stone",
			DisplayName = "IWAGANE",
			Letter = "I",
			Color = Color3.fromRGB(223, 148, 115),
			Background = "StoneBackground",
			Aliases = {"village_stone", "stone", "iwagakure", "iwagane"},
		},
	},

	Squad = {
		MaxMembers = 4,
		RemotesFolderName = "SquadRemotes",
		InviteRemoteName = "Invite",
		RequestStateRemoteName = "RequestState",
		SnapshotRemoteName = "SquadSnapshot",
	},

	Attributes = {
		CharacterName = "ShinobiDisplayName",
		VillageId = "ShinobiVillageId",
		Rank = "NinjaRankDisplayName",
	},
}

return table.freeze(ServerListConfig)
