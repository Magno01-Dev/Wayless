--!strict
-- ReplicatedStorage > Shared > SquadConfig
-- WAYLESS Squad v1 candidate — Astra SquadUI contract.

local SquadConfig = {
	MaxMembers = 4,
	InvitationExpirySeconds = 30,
	InviteRequestCooldownSeconds = 0.75,
	SnapshotHealthThrottleSeconds = 0.05,

	ReferenceViewport = Vector2.new(1920, 1080),
	Fonts = {
		Title = Font.new("rbxasset://fonts/families/Fondamento.json"),
		Body = Font.new("rbxasset://fonts/families/Merriweather.json"),
	},

	Identities = {
		{
			Key = "lightning",
			Color = Color3.fromRGB(217, 189, 105),
		},
		{
			Key = "water",
			Color = Color3.fromRGB(138, 190, 208),
		},
		{
			Key = "fire",
			Color = Color3.fromRGB(208, 129, 112),
		},
		{
			Key = "wind",
			Color = Color3.fromRGB(142, 194, 160),
		},
	},

	Assets = {
		Crosshair = "rbxassetid://112831112483463",
		fire = "rbxassetid://117612844001558",
		Invitation = "rbxassetid://113609197797942",
		lightning = "rbxassetid://76202652952385",
		Panel = "rbxassetid://127547349491217",
		People = "rbxassetid://95553232036371",
		Primary = "rbxassetid://85135578791471",
		PrimaryAlt = "rbxassetid://115809224504067",
		Secondary = "rbxassetid://76475878603946",
		Title = "rbxassetid://110844918101032",
		water = "rbxassetid://80153435846771",
		wind = "rbxassetid://123120401552004",
	},

	AssetMeta = {
		Panel = {Canvas = Vector2.new(1086, 1448), Bounds = Vector4.new(51, 64, 985, 1338)},
		Invitation = {Canvas = Vector2.new(1620, 971), Bounds = Vector4.new(79, 128, 1464, 729)},
		People = {Canvas = Vector2.new(1254, 1254), Bounds = Vector4.new(220, 356, 853, 621)},
		Primary = {Canvas = Vector2.new(2172, 724), Bounds = Vector4.new(149, 102, 1874, 510)},
		PrimaryAlt = {Canvas = Vector2.new(2172, 724), Bounds = Vector4.new(149, 102, 1874, 510)},
		Secondary = {Canvas = Vector2.new(2172, 724), Bounds = Vector4.new(152, 98, 1870, 508)},
		Title = {Canvas = Vector2.new(2126, 740), Bounds = Vector4.new(64, 91, 1802, 567)},
	},

	Layout = {
		Social = {Position = Vector2.new(170, 22), Size = Vector2.new(110, 38)},
		Menu = {Position = Vector2.new(1415, 125), Size = Vector2.new(425.6, 579.2), CanvasSize = Vector2.new(608, 820), LocalScale = 0.7},
		Invitation = {Position = Vector2.new(48, 825), Size = Vector2.new(351, 175.5), CanvasSize = Vector2.new(585, 292.5), LocalScale = 0.6},
		HUD = {Position = Vector2.new(38, 290), Size = Vector2.new(266, 290)},
		NoticeTop = 92,
	},

	Animation = {
		PanelEnter = 0.260,
		PanelExit = 0.180,
		PanelEnterOffsetY = 10,
		PanelExitOffsetY = 6,
		HUDRowEnter = 0.300,
		HUDRowRemove = 0.180,
		HUDRowReflow = 0.260,
		HealthTween = 0.500,
		NoticeEnter = 0.250,
		NoticeHold = 3.500,
		NoticeExit = 0.450,
	},

	RemotesFolderName = "SquadRemotes",
	RemoteNames = {
		Invite = "Invite",
		Respond = "Respond",
		Remove = "Remove",
		Leave = "Leave",
		RequestState = "RequestState",
		SquadSnapshot = "SquadSnapshot",
		Invitation = "Invitation",
		InvitationResult = "InvitationResult",
		SquadNotice = "SquadNotice",
	},
}

return table.freeze(SquadConfig)
