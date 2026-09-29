--!strict
-- ReplicatedStorage > Shared > SquadConfig
-- WAYLESS Squad v1 candidate — Astra SquadUI contract.

local SquadConfig = {
	MaxMembers = 4,
	InvitationExpirySeconds = 30,
	InviteRequestCooldownSeconds = 0.75,
	SnapshotHealthThrottleSeconds = 0.05,

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

	-- Intentionally empty until Magno uploads the exact PNGs from SquadUI.zip
	-- and supplies their Roblox Image Asset IDs. PrimaryAlt is byte-identical
	-- to Primary and may reuse the same ID.
	Assets = {
		Crosshair = "",
		fire = "",
		Invitation = "",
		lightning = "",
		Panel = "",
		People = "",
		Primary = "",
		PrimaryAlt = "",
		Secondary = "",
		Title = "",
		water = "",
		wind = "",
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
