-- WAYLESS
-- NinjaRankServer v2.5 CHARACTER LIFE SHORT KEY + Teardown Safe + CentralDevAccess
--
-- ONE SERVER SCRIPT.
-- No ModuleScripts.
-- No Bootstrap.
-- No CharacterDataService dependency.
-- No CharacterProgressionService dependency.
--
-- Reads only player CharacterLevel attribute.
-- Stores Ninja Rank in its own DataStore.
--
-- Place:
-- ServerScriptService > NinjaRankServer
--
-- Rank chain:
-- Academy Student -> Genin -> Chunin -> Jonin
--
-- Level only controls PROMOTE eligibility.
-- It never auto-promotes.

print("[NinjaRankServer] BOOT v2.5 CharacterLifeShortKey + TeardownSafe + CentralDevAccess")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local STORE_NAME = "WAYLESS_NinjaRank_v1"
local DEFAULT_RANK = "AcademyStudent"
local AUTOSAVE_SECONDS = 60
local ENABLE_STUDIO_PERSISTENCE = true

local Services =
	ServerScriptService:
	WaitForChild("Services")

local DeveloperAccessService =
	require(
		Services:
		WaitForChild("DeveloperAccessService")
	)

local CharacterSessionSlotGate =
	require(
		Services:
		WaitForChild("CharacterSessionSlotGate")
	)

local CharacterLifeContextService =
	require(
		Services:
		WaitForChild("CharacterLifeContextService")
	)

DeveloperAccessService.Start()
CharacterLifeContextService.Start()

local RANKS = {
	AcademyStudent = {
		DisplayName = "Academy Student",
		Order = 1,
		MinimumLevel = 1,
	},
	Genin = {
		DisplayName = "Genin",
		Order = 2,
		MinimumLevel = 5,
	},
	Chunin = {
		DisplayName = "Chunin",
		Order = 3,
		MinimumLevel = 20,
	},
	Jonin = {
		DisplayName = "Jonin",
		Order = 4,
		MinimumLevel = 45,
	},
}

local ORDER_TO_ID = {
	[1] = "AcademyStudent",
	[2] = "Genin",
	[3] = "Chunin",
	[4] = "Jonin",
}

local ALIASES = {
	academy = "AcademyStudent",
	academystudent = "AcademyStudent",
	student = "AcademyStudent",
	genin = "Genin",
	chunin = "Chunin",
	jonin = "Jonin",
}

local sessions = {}
local store = DataStoreService:GetDataStore(STORE_NAME)

local function persistenceEnabled()
	if RunService:IsStudio() then
		return ENABLE_STUDIO_PERSISTENCE
	end

	return true
end

local function normalizeRank(value)
	if type(value) ~= "string" then
		return nil
	end

	if RANKS[value] then
		return value
	end

	local cleaned = string.lower(value)
	cleaned = string.gsub(cleaned, "[%s%p_%-]", "")

	return ALIASES[cleaned]
end

local function getLevel(player)
	local value = player:GetAttribute("CharacterLevel")

	if type(value) == "number" then
		return math.max(1, math.floor(value))
	end

	return 1
end

local function getNextRankId(rankId)
	local rank = RANKS[rankId]
	if not rank then
		return nil
	end

	return ORDER_TO_ID[rank.Order + 1]
end

local function replicate(player)
	local session = sessions[player]
	if not session then
		return
	end

	local rankId = session.RankId
	local rank = RANKS[rankId]

	if not rank then
		rankId = DEFAULT_RANK
		rank = RANKS[DEFAULT_RANK]
		session.RankId = rankId
	end

	local level = getLevel(player)
	local nextRankId = getNextRankId(rankId)
	local nextRank = nextRankId and RANKS[nextRankId] or nil
	local eligible = false

	if nextRank then
		eligible = level >= nextRank.MinimumLevel
	end

	player:SetAttribute("NinjaRank", rankId)
	player:SetAttribute("NinjaRankDisplayName", rank.DisplayName)
	player:SetAttribute("NinjaRankOrder", rank.Order)
	player:SetAttribute("NinjaRankEligibleForPromotion", eligible)
	player:SetAttribute("NinjaRankNext", nextRankId)
	player:SetAttribute(
		"NinjaRankNextDisplayName",
		nextRank and nextRank.DisplayName or nil
	)
	player:SetAttribute(
		"NinjaRankNextRequiredLevel",
		nextRank and nextRank.MinimumLevel or nil
	)
end

local function legacyKeyForSlot(player, slotId)
	return "Player_"
		.. tostring(player.UserId)
		.. "_Slot_"
		.. tostring(slotId)
end

local function previousLifeKey(player, lifeId)
	return "Player_"
		.. tostring(player.UserId)
		.. "_Life_"
		.. tostring(lifeId)
end

local function keyForLife(_player, lifeId)
	return "life_" .. tostring(lifeId)
end

local function savePlayer(player)
	local session = sessions[player]

	if not session then
		return true
	end

	if not persistenceEnabled() then
		session.Dirty = false
		return true
	end

	local rankToSave = session.RankId
	local slotId = session.SlotId
	local lifeId = session.LifeId

	CharacterSessionSlotGate.AssertLoadedSlot(
		player,
		slotId,
		"NinjaRankServer"
	)

	CharacterLifeContextService.AssertIdentity(
		player,
		slotId,
		lifeId,
		"NinjaRankServer"
	)

	local ok, err = pcall(function()
		store:UpdateAsync(
			keyForLife(player, lifeId),
			function()
				return {
					Rank = rankToSave,
				}
			end
		)
	end)

	if not ok then
		warn(
			"[NinjaRankServer] SAVE FAILED",
			player.Name,
			err
		)
		return false
	end

	session.Dirty = false
	session.PersistenceAvailable = true

	player:SetAttribute(
		"NinjaRankPersistent",
		true
	)

	print(
		"[NinjaRankServer] SAVED",
		player.Name,
		"Slot=" .. tostring(slotId),
		"Life=" .. tostring(lifeId),
		"Rank=" .. rankToSave
	)

	return true
end

local function loadPlayer(player)
	if sessions[player] then
		return
	end

	-- Resolve immutable Slot + Life identity before touching persistence.
	local slotId =
		CharacterSessionSlotGate.WaitForSlot(player)

	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	local lifeId = identity.LifeId
	local characterId = identity.CharacterId

	CharacterLifeContextService.AssertIdentity(
		player,
		slotId,
		lifeId,
		"NinjaRankServer"
	)

	local rankId = DEFAULT_RANK
	local persistenceAvailable = false
	local migratedLegacy = false

	if persistenceEnabled() then
		local ok, result = pcall(function()
			return store:GetAsync(
				keyForLife(player, lifeId)
			)
		end)

		if ok then
			persistenceAvailable = true

			if result == nil then
				local previousKey =
					previousLifeKey(
						player,
						lifeId
					)

				if #previousKey <= 50 then
					local previousOk, previousResult =
						pcall(function()
							return store:GetAsync(
								previousKey
							)
						end)

					if previousOk
						and previousResult ~= nil then
						result = previousResult
						migratedLegacy = true
					end
				end
			end

			if result == nil
				and identity.LegacyChildDataMigrationEligible == true then

				local legacyOk, legacyResult =
					pcall(function()
						return store:GetAsync(
							legacyKeyForSlot(
								player,
								slotId
							)
						)
					end)

				if legacyOk and legacyResult ~= nil then
					result = legacyResult
					migratedLegacy = true
				end
			end

			if type(result) == "table"
				and type(result.Rank) == "string" then

				rankId =
					normalizeRank(result.Rank)
					or DEFAULT_RANK
			end

			if migratedLegacy then
				local snapshot = {
					Version = 2,
					SlotId = slotId,
					LifeId = lifeId,
					CharacterId = characterId,
					Rank = rankId,
					MigratedAt = os.time(),
				}

				local migrateOk, migrateErr =
					pcall(function()
						store:UpdateAsync(
							keyForLife(
								player,
								lifeId
							),
							function(current)
								return current or snapshot
							end
						)
					end)

				if migrateOk then
					print(
						"[NinjaRankServer] LEGACY SLOT MIGRATED",
						player.Name,
						"Slot=" .. slotId,
						"Life=" .. lifeId
					)
				else
					warn(
						"[NinjaRankServer] LEGACY MIGRATION SAVE FAILED",
						player.Name,
						migrateErr
					)
				end
			end
		else
			warn(
				"[NinjaRankServer] LOAD FAILED; USING MEMORY ONLY",
				player.Name,
				result
			)
		end
	end

	sessions[player] = {
		SlotId = slotId,
		LifeId = lifeId,
		CharacterId = characterId,
		RankId = rankId,
		Dirty = false,
		PersistenceAvailable = persistenceAvailable,
	}

	CharacterSessionSlotGate.AssertLoadedSlot(
		player,
		slotId,
		"NinjaRankServer"
	)

	player:SetAttribute(
		"NinjaRankPersistent",
		persistenceAvailable
	)
	player:SetAttribute(
		"NinjaRankSlotId",
		slotId
	)
	player:SetAttribute(
		"NinjaRankLifeId",
		lifeId
	)
	player:SetAttribute(
		"NinjaRankCharacterId",
		characterId
	)

	replicate(player)

	player:GetAttributeChangedSignal(
		"CharacterLevel"
	):Connect(function()
		if sessions[player] then
			replicate(player)
		end
	end)

	print(
		"[NinjaRankServer] LOADED",
		player.Name,
		"Slot=" .. tostring(slotId),
		"Life=" .. tostring(lifeId),
		"Rank=" .. rankId,
		"Level=" .. tostring(getLevel(player)),
		"Persistent=" .. tostring(persistenceAvailable)
	)
end

local function setRank(player, requestedRank, bypassRequirements)
	local session = sessions[player]

	if not session then
		return false, "Rank session is not loaded."
	end

	local newRankId = normalizeRank(requestedRank)

	if not newRankId then
		return false, "Invalid Ninja Rank: " .. tostring(requestedRank)
	end

	local currentRank = RANKS[session.RankId]
	local targetRank = RANKS[newRankId]

	if not bypassRequirements then
		if targetRank.Order < currentRank.Order then
			return false, "Normal promotion cannot demote."
		end

		if targetRank.Order > currentRank.Order + 1 then
			return false, "Normal promotion advances one rank at a time."
		end

		if targetRank.Order == currentRank.Order + 1 then
			local level = getLevel(player)

			if level < targetRank.MinimumLevel then
				return false,
					targetRank.DisplayName
					.. " requires Character Level "
					.. tostring(targetRank.MinimumLevel)
					.. "."
			end
		end
	end

	session.RankId = newRankId
	session.Dirty = true

	replicate(player)

	-- Immediate save for dev/testing changes.
	task.spawn(function()
		savePlayer(player)
	end)

	print(
		"[NinjaRankServer] RANK CHANGED",
		player.Name,
		"Slot=" .. tostring(session.SlotId),
		"Rank=" .. newRankId
	)

	return true,
		"Rank -> "
		.. targetRank.DisplayName
end

local function promote(player)
	local session = sessions[player]

	if not session then
		return false, "Rank session is not loaded."
	end

	local nextRankId =
		getNextRankId(
			session.RankId
		)

	if not nextRankId then
		return false,
			"Already at maximum linear Ninja Rank."
	end

	return setRank(
		player,
		nextRankId,
		false
	)
end

-- Create remote immediately.
local remotes =
	ReplicatedStorage:FindFirstChild(
		"Remotes"
	)

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local request =
	remotes:FindFirstChild(
		"NinjaRankDevRequest"
	)

if request
	and not request:IsA(
		"RemoteFunction"
	) then

	request:Destroy()
	request = nil
end

if not request then
	request = Instance.new("RemoteFunction")
	request.Name = "NinjaRankDevRequest"
	request.Parent = remotes
end

print(
	"[NinjaRankServer] REMOTE READY"
)

local function isAuthorized(player)
	return DeveloperAccessService.IsDeveloper(
		player
	)
end

request.OnServerInvoke =
	function(player, action, value)
		if not isAuthorized(player) then
			return false,
			"Not authorized."
		end

		if action == "CanUse" then
			return true,
			"Authorized."
		end

		if not sessions[player] then
			return false,
			"Ninja Rank is still loading."
		end

		if action == "GetRank" then
			local rankId =
			sessions[player].RankId

			local rank =
			RANKS[rankId]

			return true,
			rank.DisplayName

		elseif action == "SetRank" then
			return setRank(
				player,
				value,
				true
			)

		elseif action == "Promote" then
			return promote(player)
		end

		return false,
		"Unknown action."
	end

local function getPlayerFromTextSource(source)
	if not source then
		return nil
	end

	return Players:GetPlayerByUserId(
		source.UserId
	)
end

local function createCommand(name, alias, callback)
	local old =
		TextChatService:FindFirstChild(
			name
		)

	if old then
		old:Destroy()
	end

	local command =
		Instance.new(
			"TextChatCommand"
		)

	command.Name = name
	command.PrimaryAlias = alias
	command.Parent = TextChatService

	command.Triggered:Connect(
		function(source, text)
			local player =
				getPlayerFromTextSource(
					source
				)

			if not player
				or not isAuthorized(player) then

				return
			end

			callback(
				player,
				text
			)
		end
	)
end

createCommand(
	"WAYLESS_SetNinjaRank",
	"/setrank",
	function(player, text)
		local pieces =
			string.split(
				text,
				" "
			)

		local value =
			pieces[#pieces]

		if not value
			or value == ""
			or value == "/setrank" then

			print(
				"[NinjaRankServer] Usage: /setrank genin"
			)

			return
		end

		local ok, message =
			setRank(
				player,
				value,
				true
			)

		print(
			"[NinjaRankServer]",
			player.Name,
			ok,
			message
		)
	end
)

createCommand(
	"WAYLESS_PromoteNinjaRank",
	"/promoterank",
	function(player)
		local ok, message =
			promote(player)

		print(
			"[NinjaRankServer]",
			player.Name,
			ok,
			message
		)
	end
)

createCommand(
	"WAYLESS_GetNinjaRank",
	"/getrank",
	function(player)
		local session =
			sessions[player]

		if session then
			print(
				"[NinjaRankServer]",
				player.Name,
				"Rank="
					.. session.RankId
			)
		end
	end
)

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.spawn(
		loadPlayer,
		player
	)
end

Players.PlayerAdded:Connect(
	function(player)
		task.spawn(
			loadPlayer,
			player
		)
	end
)

Players.PlayerRemoving:Connect(
	function(player)
		local ok, err = pcall(
			savePlayer,
			player
		)

		if not ok then
			warn(
				"[NinjaRankServer] PLAYER REMOVING SAVE ERROR",
				player.Name,
				err
			)
		end

		sessions[player] = nil
	end
)

task.spawn(function()
	while true do
		task.wait(
			AUTOSAVE_SECONDS
		)

		for player, session in pairs(sessions) do
			if player.Parent == Players
				and session.Dirty then

				task.spawn(
					savePlayer,
					player
				)
			end
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	local finished = 0

	for _ in pairs(sessions) do
		pending = pending + 1
	end

	if pending == 0 then
		return
	end

	local done =
		Instance.new(
			"BindableEvent"
		)

	for player in pairs(sessions) do
		task.spawn(function()
			local ok, err = pcall(
				savePlayer,
				player
			)

			if not ok then
				warn(
					"[NinjaRankServer] BIND TO CLOSE SAVE ERROR",
					player.Name,
					err
				)
			end

			-- ALWAYS release the shutdown barrier.
			finished =
				finished + 1

			if finished >= pending then
				done:Fire()
			end
		end)
	end

	if finished < pending then
		done.Event:Wait()
	end

	done:Destroy()
end)

print(
	"[NinjaRankServer] READY v2.5 CHARACTER LIFE | ShortLifeKey=ON | LegacySlotMigration=ON | TeardownSafe=ON | CentralDevAccess=ON"
)
