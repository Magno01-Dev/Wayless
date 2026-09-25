--!strict
-- ServerScriptService > WAYLESSDevBridge
--
-- Small centralized bridge used by the unified WAYLESS developer menu.
--
-- Existing specialized server remotes stay authoritative for their own
-- systems. This bridge only handles common developer access/bypass state.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local ServerScriptService =
	game:GetService("ServerScriptService")

local DeveloperAccessService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("DeveloperAccessService")
)

DeveloperAccessService.Start()

local remotes =
	ReplicatedStorage:
	FindFirstChild("Remotes")

if not remotes then
	remotes =
		Instance.new("Folder")

	remotes.Name =
		"Remotes"

	remotes.Parent =
		ReplicatedStorage
end

local existing =
	remotes:FindFirstChild(
		"WAYLESSDevRequest"
	)

if existing
	and not existing:IsA(
		"RemoteFunction"
	) then

	existing:Destroy()
	existing = nil
end

local request =
	existing :: RemoteFunction?

if not request then
	request =
		Instance.new(
			"RemoteFunction"
		)

	request.Name =
		"WAYLESSDevRequest"

	request.Parent =
		remotes
end

local function snapshot(
	player: Player
)
	return {
		IsDeveloper =
			DeveloperAccessService.IsDeveloper(
				player
			),

		ContentBypass =
			DeveloperAccessService.HasContentBypass(
				player
			),

		TechniqueLearnedCount =
			player:GetAttribute(
				"TechniqueLearnedCount"
			) or 0,

		TechniqueLearningReady =
			player:GetAttribute(
				"TechniqueLearningReady"
			) == true,
	}
end

(request :: RemoteFunction).OnServerInvoke =
	function(
		player: Player,
		action: string,
		value: any?
	)
	if not DeveloperAccessService.IsDeveloper(
		player
		) then

		return false,
			"NotDeveloper",
			nil
	end

	if action == "CanUse"
		or action == "GetStatus" then

		return true,
			"Authorized",
			snapshot(player)

	elseif action == "SetContentBypass" then
		local enabled =
			value == true

		local ok,
			reason =
			DeveloperAccessService
			.SetContentBypass(
				player,
				enabled
			)

		return ok,
			reason,
			snapshot(player)
	end

	return false,
		"UnknownAction",
		nil
end

print(
	"[WAYLESSDevBridge] READY v1"
		.. " | UnifiedMenuAccess=ON"
		.. " | ContentBypassControl=ON"
)
