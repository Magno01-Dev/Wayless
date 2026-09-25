--!strict
-- WAYLESS
-- ProgressionDevTools v1.1 CentralDevAccess
--
-- Development-only Character XP / Level controls.
--
-- Studio:
--   Everyone in the Studio test session is authorized.
--
-- Published game:
--   Add tester UserIds to AUTHORIZED_USER_IDS below.
--
-- Commands:
--   /setlevel 45
--   /addxp 1000
--   /setxp 39625
--   /resetlevel
--   /getprogress
--
-- The dev menu uses the same server-authoritative actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local Services =
	ServerScriptService:WaitForChild("Services")

local Progression =
	require(
		Services:WaitForChild(
			"CharacterProgressionService"
		)
	)

local DeveloperAccessService =
	require(
		Services:WaitForChild(
			"DeveloperAccessService"
		)
	)

DeveloperAccessService.Start()

local AUTHORIZED_USER_IDS: { [number]: boolean } = {
	-- Add live tester UserIds here:
	-- [123456789] = true,
}

local function isAuthorized(player: Player): boolean
	return DeveloperAccessService.IsDeveloper(
		player
	)
end

local remotes =
	ReplicatedStorage:FindFirstChild("Remotes")

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local request =
	remotes:FindFirstChild(
		"ProgressionDevRequest"
	)

if request and not request:IsA("RemoteFunction") then
	request:Destroy()
	request = nil
end

if not request then
	request = Instance.new("RemoteFunction")
	request.Name = "ProgressionDevRequest"
	request.Parent = remotes
end

local function getSnapshotMessage(player: Player): string
	local snapshot =
		Progression.GetSnapshot(player)

	if snapshot.IsMaxLevel then
		return (
			"Lv%d | TotalXP %d | MAX"
		):format(
			snapshot.Level,
			snapshot.TotalXP
		)
	end

	return (
		"Lv%d | TotalXP %d | %d/%d XP"
	):format(
		snapshot.Level,
		snapshot.TotalXP,
		snapshot.XPIntoCurrentLevel,
		snapshot.XPRequiredForNextLevel
	)
end

local function feedback(
	player: Player,
	message: string
)
	player:SetAttribute(
		"ProgressionDevLastMessage",
		message
	)

	print(
		("[ProgressionDev] %s | %s"):format(
			player.Name,
			message
		)
	)
end

local function runAction(
	player: Player,
	action: string,
	value: any?
)
	if not isAuthorized(player) then
		return false, "Not authorized.", nil
	end

	if not Progression.IsInitialized(player) then
		return false, "Progression session not initialized.", nil
	end

	if action == "CanUse" then
		return true, "Authorized.", Progression.GetSnapshot(player)
	elseif action == "GetProgress" then
		local message = getSnapshotMessage(player)
		feedback(player, message)
		return true, message, Progression.GetSnapshot(player)
	elseif action == "SetLevel" then
		local level = tonumber(value)

		if not level then
			return false, "SetLevel requires a number.", nil
		end

		local snapshot =
			Progression.SetLevel(
				player,
				level,
				"DevSetLevel"
			)

		local message =
			("Set level -> Lv%d | TotalXP %d"):format(
				snapshot.Level,
				snapshot.TotalXP
			)

		feedback(player, message)
		return true, message, snapshot
	elseif action == "AddXP" then
		local amount = tonumber(value)

		if not amount then
			return false, "AddXP requires a number.", nil
		end

		if amount <= 0 then
			return false, "AddXP amount must be > 0.", nil
		end

		local snapshot, actuallyAdded =
			Progression.AddXP(
				player,
				amount,
				"DevAddXP"
			)

		local message =
			("+%d XP -> Lv%d | TotalXP %d"):format(
				actuallyAdded,
				snapshot.Level,
				snapshot.TotalXP
			)

		feedback(player, message)
		return true, message, snapshot
	elseif action == "SetXP" then
		local totalXP = tonumber(value)

		if not totalXP then
			return false, "SetXP requires a number.", nil
		end

		local snapshot =
			Progression.SetTotalXP(
				player,
				totalXP,
				"DevSetXP"
			)

		local message =
			("Set TotalXP -> %d | Lv%d"):format(
				snapshot.TotalXP,
				snapshot.Level
			)

		feedback(player, message)
		return true, message, snapshot
	elseif action == "Reset" then
		local snapshot =
			Progression.ResetProgress(
				player,
				"DevReset"
			)

		local message =
			"Progression reset -> Lv1 | TotalXP 0"

		feedback(player, message)
		return true, message, snapshot
	end

	return false, "Unknown action: " .. tostring(action), nil
end

(request :: RemoteFunction).OnServerInvoke =
	function(
		player: Player,
		action: string,
		value: any?
	)
	return runAction(
		player,
		action,
		value
	)
end

local function getPlayerFromTextSource(
	textSource: TextSource?
): Player?

	if not textSource then
		return nil
	end

	return Players:GetPlayerByUserId(
		textSource.UserId
	)
end

local function parseNumberArgument(
	unfilteredText: string
): number?

	local tokens = string.split(
		unfilteredText,
		" "
	)

	for index = #tokens, 1, -1 do
		local numberValue =
			tonumber(tokens[index])

		if numberValue then
			return numberValue
		end
	end

	return nil
end

local function createCommand(
	name: string,
	alias: string,
	callback: (
		Player,
		string
	) -> ()
)
	local existing =
		TextChatService:FindFirstChild(name)

	if existing then
		existing:Destroy()
	end

	local command =
		Instance.new("TextChatCommand")

	command.Name = name
	command.PrimaryAlias = alias
	command.Parent = TextChatService

	command.Triggered:Connect(
		function(
			textSource: TextSource,
			unfilteredText: string
		)
			local player =
				getPlayerFromTextSource(
					textSource
				)

			if not player
				or not isAuthorized(player) then

				return
			end

			callback(
				player,
				unfilteredText
			)
		end
	)
end

createCommand(
	"WAYLESS_SetLevel",
	"/setlevel",
	function(player, text)
		local value = parseNumberArgument(text)

		if not value then
			feedback(
				player,
				"Usage: /setlevel 45"
			)
			return
		end

		runAction(
			player,
			"SetLevel",
			value
		)
	end
)

createCommand(
	"WAYLESS_AddXP",
	"/addxp",
	function(player, text)
		local value = parseNumberArgument(text)

		if not value then
			feedback(
				player,
				"Usage: /addxp 1000"
			)
			return
		end

		runAction(
			player,
			"AddXP",
			value
		)
	end
)

createCommand(
	"WAYLESS_SetXP",
	"/setxp",
	function(player, text)
		local value = parseNumberArgument(text)

		if not value then
			feedback(
				player,
				"Usage: /setxp 39625"
			)
			return
		end

		runAction(
			player,
			"SetXP",
			value
		)
	end
)

createCommand(
	"WAYLESS_ResetLevel",
	"/resetlevel",
	function(player)
		runAction(
			player,
			"Reset"
		)
	end
)

createCommand(
	"WAYLESS_GetProgress",
	"/getprogress",
	function(player)
		runAction(
			player,
			"GetProgress"
		)
	end
)

print(
	"[ProgressionDevTools] READY v1.1 | CentralDevAccess=ON | TeamTestCompatible=ON"
)
