--!strict
-- ServerScriptService > Services > DeveloperAccessService
--
-- WAYLESS centralized developer content bypass v1.1 TeamTestAccess.
--
-- This bypass is for CONTENT / PROGRESSION REQUIREMENTS only.
--
-- It does NOT bypass:
-- - chakra
-- - cooldowns
-- - combat state
-- - stun
-- - damage validation
-- - server authority
--
-- Studio local tests:
-- Every tester is automatically considered a developer.
--
-- Team Test:
-- Team Test servers can behave like hosted/reserved servers instead of a
-- normal Studio server. When enabled below, players inside that session are
-- automatically authorized for dev testing.
--
-- Live:
-- Place creator is automatically a developer when CreatorType = User.
-- Add additional trusted UserIds to LIVE_DEVELOPER_USER_IDS if needed.

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local DeveloperAccessService = {}

---------------------------------------------------------------------
-- TEAM TEST ACCESS
--
-- Roblox Team Test can run on a hosted server where server-side IsStudio()
-- is not sufficient by itself. A common server-side signature is:
--
--     game.PrivateServerId ~= ""
--     game.PrivateServerOwnerId == 0
--
-- IMPORTANT:
-- That same signature can also describe developer-created reserved servers.
-- WAYLESS does not currently use reserved servers for production gameplay,
-- so this is ON for collaborative testing now.
--
-- If WAYLESS later begins using reserved servers in production, set this
-- false and move team developers into LIVE_DEVELOPER_USER_IDS or a trusted
-- group-rank rule before shipping that feature.
---------------------------------------------------------------------

local ENABLE_TEAM_TEST_RESERVED_SERVER_ACCESS =
	true

local function isTeamTestLikeServer(): boolean
	return ENABLE_TEAM_TEST_RESERVED_SERVER_ACCESS
		and game.PrivateServerId ~= ""
		and game.PrivateServerOwnerId == 0
end

---------------------------------------------------------------------
-- OPTIONAL LIVE DEV WHITELIST
--
-- Example:
-- [123456789] = true,
--
-- Studio testers do NOT need to be added here.
---------------------------------------------------------------------

local LIVE_DEVELOPER_USER_IDS: {[number]: boolean} = {
}

local started = false
local chatConnections: {[Player]: RBXScriptConnection} = {}

local function getAuthorizationReason(
	player: Player
): string?
	if RunService:IsStudio() then
		return "Studio"
	end

	if isTeamTestLikeServer() then
		return "TeamTestReservedServer"
	end

	if game.CreatorType == Enum.CreatorType.User
		and player.UserId == game.CreatorId then

		return "Creator"
	end

	if LIVE_DEVELOPER_USER_IDS[
		player.UserId
		] == true then

		return "LiveWhitelist"
	end

	return nil
end

local function isAuthorizedDeveloper(
	player: Player
): boolean
	return getAuthorizationReason(
		player
	) ~= nil
end

local function publish(
	player: Player
)
	local isDeveloper =
		isAuthorizedDeveloper(
			player
		)

	player:SetAttribute(
		"IsWaylessDeveloper",
		isDeveloper
	)

	player:SetAttribute(
		"DeveloperAccessReason",
		getAuthorizationReason(
			player
		)
	)

	if not isDeveloper then
		player:SetAttribute(
			"DevContentBypassEnabled",
			false
		)

		return
	end

	-- Default ON for authorized developers.
	-- Preserve an explicit false set during this server session.
	if player:GetAttribute(
		"DevContentBypassEnabled"
		) == nil then

		player:SetAttribute(
			"DevContentBypassEnabled",
			true
		)
	end
end

function DeveloperAccessService.IsDeveloper(
	player: Player
): boolean
	return isAuthorizedDeveloper(
		player
	)
end

function DeveloperAccessService.HasContentBypass(
	player: Player
): boolean
	if not isAuthorizedDeveloper(
		player
		) then
		return false
	end

	local value =
		player:GetAttribute(
			"DevContentBypassEnabled"
		)

	-- If another system queries before Start() publishes attributes,
	-- authorized developers still default to bypass ON.
	if value == nil then
		return true
	end

	return value == true
end

function DeveloperAccessService.SetContentBypass(
	player: Player,
	enabled: boolean
): (boolean, string)
	if not isAuthorizedDeveloper(
		player
		) then

		return false, "NotDeveloper"
	end

	if typeof(enabled) ~= "boolean" then
		return false, "InvalidValue"
	end

	player:SetAttribute(
		"DevContentBypassEnabled",
		enabled
	)

	print(
		"[DeveloperAccessService]",
		player.Name,
		"ContentBypass="
			.. tostring(enabled)
	)

	return true,
		enabled
		and "DeveloperBypassEnabled"
		or "DeveloperBypassDisabled"
end

local function onChat(
	player: Player,
	message: string
)
	local normalized =
		string.lower(
			string.gsub(
				message,
				"^%s*(.-)%s*$",
				"%1"
			)
		)

	if normalized == "/devbypass on" then
		DeveloperAccessService.SetContentBypass(
			player,
			true
		)

	elseif normalized == "/devbypass off" then
		DeveloperAccessService.SetContentBypass(
			player,
			false
		)

	elseif normalized == "/devbypass"
		or normalized == "/devbypass status" then

		if isAuthorizedDeveloper(player) then
			print(
				"[DeveloperAccessService]",
				player.Name,
				"ContentBypass="
					.. tostring(
						DeveloperAccessService.HasContentBypass(
							player
						)
					)
			)
		end
	end
end

local function onPlayerAdded(
	player: Player
)
	publish(player)

	if chatConnections[player] then
		chatConnections[player]:
			Disconnect()
	end

	chatConnections[player] =
		player.Chatted:
		Connect(
			function(message)
				onChat(
					player,
					message
				)
			end
		)
end

local function onPlayerRemoving(
	player: Player
)
	local connection =
		chatConnections[player]

	if connection then
		connection:Disconnect()
		chatConnections[player] = nil
	end
end

function DeveloperAccessService.Start()
	if started then
		return
	end

	started = true

	Players.PlayerAdded:
		Connect(
			onPlayerAdded
		)

	Players.PlayerRemoving:
		Connect(
			onPlayerRemoving
		)

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(
			onPlayerAdded,
			player
		)
	end

	print(
		"[DeveloperAccessService] READY v1.1 TeamTestAccess"
			.. " | StudioAutoDev="
			.. tostring(
				RunService:IsStudio()
			)
			.. " | TeamTestReservedAccess="
			.. tostring(
				ENABLE_TEAM_TEST_RESERVED_SERVER_ACCESS
			)
			.. " | TeamTestSignature="
			.. tostring(
				isTeamTestLikeServer()
			)
			.. " | DefaultContentBypass=ON"
			.. " | Command=/devbypass on|off|status"
	)
end

return DeveloperAccessService
