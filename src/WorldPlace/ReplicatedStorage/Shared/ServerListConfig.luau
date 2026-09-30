--!strict
-- ReplicatedStorage > Shared > ServerListConfig
-- WAYLESS ServerList v1 candidate — Astra ServerList.zip contract.

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
		Top = 83,
		Width = 306,
		Height = 466,
		PaddingX = 10,
		PaddingY = 8,
		ScrollAreaHeight = 362,

		ServerButton = {
			Position = Vector2.new(292, 22),
			Size = Vector2.new(110, 38),
		},

		TitleBrushVisibleWidth = 180,
		VillageGap = 12,
		VillageHeaderWidth = 284,
		VillageHeaderHeight = 44,
		PlayerRowHeight = 43,
		PlayerRowExpandedHeight = 73,
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

	Villages = {
		{Key = "leaf", DisplayName = "KAZEHA", Letter = "K", Color = Color3.fromRGB(159, 207, 121), Background = "LeafBackground", Aliases = {"village_leaf", "leaf", "konoha", "kazeha"}},
		{Key = "sand", DisplayName = "SARYU", Letter = "S", Color = Color3.fromRGB(230, 185, 96), Background = "SandBackground", Aliases = {"village_sand", "sand", "sunagakure", "saryu"}},
		{Key = "mist", DisplayName = "KASUMI", Letter = "K", Color = Color3.fromRGB(125, 198, 223), Background = "MistBackground", Aliases = {"village_mist", "mist", "kirigakure", "kasumi"}},
		{Key = "cloud", DisplayName = "RAIKUMO", Letter = "R", Color = Color3.fromRGB(174, 154, 232), Background = "CloudBackground", Aliases = {"village_cloud", "cloud", "kumogakure", "raikumo"}},
		{Key = "stone", DisplayName = "IWAGANE", Letter = "I", Color = Color3.fromRGB(223, 148, 115), Background = "StoneBackground", Aliases = {"village_stone", "stone", "iwagakure", "iwagane"}},
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
