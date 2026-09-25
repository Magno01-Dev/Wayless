--!strict
-- WAYLESS
-- CharacterProgressionService v1.1 - External Data Lifecycle
--
-- SERVER AUTHORITATIVE.
--
-- IMPORTANT:
-- This version is intentionally MEMORY-ONLY.
-- Rejoining / restarting the server resets progression unless a future
-- slot/data service passes saved Progression data into InitializePlayer().
--
-- Future persistence contract:
--   CharacterProgressionService.InitializePlayer(player, slotData.Progression)
--   slotData.Progression = CharacterProgressionService.ExportPlayerData(player)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(
	Shared:WaitForChild("CharacterProgressionConfig")
)

type Session = {
	TotalXP: number,
}

type LoadData = {
	Level: number?,
	TotalXP: number?,
}

local CharacterProgressionService = {}

local sessions: { [Player]: Session } = {}

local levelChangedBindable = Instance.new("BindableEvent")
local xpChangedBindable = Instance.new("BindableEvent")

CharacterProgressionService.LevelChanged =
	levelChangedBindable.Event

CharacterProgressionService.XPChanged =
	xpChangedBindable.Event

local function assertPlayer(player: Player)
	if typeof(player) ~= "Instance"
		or not player:IsA("Player") then

		error(
			"CharacterProgressionService expected Player",
			3
		)
	end
end

local function getSession(player: Player): Session
	local session = sessions[player]

	if not session then
		error(
			(
				"CharacterProgressionService: %s is not initialized"
			):format(player.Name),
			3
		)
	end

	return session
end

local function replicate(
	player: Player,
	totalXP: number
)
	local snapshot =
		Config.GetSnapshotFromTotalXP(totalXP)

	player:SetAttribute(
		"CharacterLevel",
		snapshot.Level
	)

	player:SetAttribute(
		"CharacterTotalXP",
		snapshot.TotalXP
	)

	player:SetAttribute(
		"CharacterXPIntoLevel",
		snapshot.XPIntoCurrentLevel
	)

	player:SetAttribute(
		"CharacterXPRequired",
		snapshot.XPRequiredForNextLevel
	)

	player:SetAttribute(
		"CharacterXPProgress",
		snapshot.ProgressPercent
	)

	player:SetAttribute(
		"CharacterMaxLevel",
		snapshot.IsMaxLevel
	)
end

function CharacterProgressionService.IsInitialized(
	player: Player
): boolean

	return sessions[player] ~= nil
end

function CharacterProgressionService.InitializePlayer(
	player: Player,
	loadData: LoadData?
)
	assertPlayer(player)

	if sessions[player] then
		return CharacterProgressionService.GetSnapshot(player)
	end

	local totalXP = 0

	if loadData then
		if typeof(loadData.TotalXP) == "number" then
			totalXP = loadData.TotalXP
		elseif typeof(loadData.Level) == "number" then
			-- Compatibility fallback only.
			-- TotalXP remains the canonical persisted value.
			totalXP =
				Config.GetTotalXPForLevel(
					loadData.Level
				)
		end
	end

	totalXP = math.clamp(
		math.floor(totalXP),
		0,
		Config.MAX_TOTAL_XP
	)

	sessions[player] = {
		TotalXP = totalXP,
	}

	replicate(player, totalXP)

	return CharacterProgressionService.GetSnapshot(player)
end

function CharacterProgressionService.ReleasePlayer(
	player: Player
)
	assertPlayer(player)
	sessions[player] = nil
end

function CharacterProgressionService.GetSnapshot(
	player: Player
): Config.ProgressSnapshot

	assertPlayer(player)

	local session = getSession(player)

	return Config.GetSnapshotFromTotalXP(
		session.TotalXP
	)
end

function CharacterProgressionService.ExportPlayerData(
	player: Player
): LoadData

	local snapshot =
		CharacterProgressionService.GetSnapshot(player)

	return {
		Level = snapshot.Level,
		TotalXP = snapshot.TotalXP,
	}
end

local function setTotalXPInternal(
	player: Player,
	newTotalXP: number,
	source: string
)
	local session = getSession(player)

	local oldSnapshot =
		Config.GetSnapshotFromTotalXP(
			session.TotalXP
		)

	newTotalXP = math.clamp(
		math.floor(newTotalXP),
		0,
		Config.MAX_TOTAL_XP
	)

	session.TotalXP = newTotalXP

	local newSnapshot =
		Config.GetSnapshotFromTotalXP(
			newTotalXP
		)

	replicate(player, newTotalXP)

	if newSnapshot.TotalXP ~= oldSnapshot.TotalXP then
		xpChangedBindable:Fire(
			player,
			oldSnapshot,
			newSnapshot,
			source
		)
	end

	if newSnapshot.Level ~= oldSnapshot.Level then
		levelChangedBindable:Fire(
			player,
			oldSnapshot.Level,
			newSnapshot.Level,
			newSnapshot.Level - oldSnapshot.Level,
			source
		)
	end

	return newSnapshot
end

function CharacterProgressionService.AddXP(
	player: Player,
	amount: number,
	source: string?
)
	assertPlayer(player)

	if typeof(amount) ~= "number"
		or amount ~= amount
		or amount == math.huge
		or amount == -math.huge then

		error(
			"CharacterProgressionService.AddXP received invalid amount",
			2
		)
	end

	amount = math.floor(amount)

	if amount <= 0 then
		return CharacterProgressionService.GetSnapshot(player), 0
	end

	local session = getSession(player)
	local before = session.TotalXP

	local snapshot =
		setTotalXPInternal(
			player,
			before + amount,
			source or "Unknown"
		)

	local actuallyAdded =
		snapshot.TotalXP - before

	return snapshot, actuallyAdded
end

function CharacterProgressionService.SetTotalXP(
	player: Player,
	totalXP: number,
	source: string?
)
	assertPlayer(player)

	if typeof(totalXP) ~= "number"
		or totalXP ~= totalXP
		or totalXP == math.huge
		or totalXP == -math.huge then

		error(
			"CharacterProgressionService.SetTotalXP received invalid totalXP",
			2
		)
	end

	return setTotalXPInternal(
		player,
		totalXP,
		source or "SetTotalXP"
	)
end

function CharacterProgressionService.SetLevel(
	player: Player,
	level: number,
	source: string?
)
	assertPlayer(player)

	if typeof(level) ~= "number"
		or level ~= level
		or level == math.huge
		or level == -math.huge then

		error(
			"CharacterProgressionService.SetLevel received invalid level",
			2
		)
	end

	level = math.clamp(
		math.floor(level),
		Config.MIN_LEVEL,
		Config.MAX_LEVEL
	)

	-- SetLevel always places the character at the exact beginning
	-- of the requested level, preventing Level/TotalXP mismatch.
	return setTotalXPInternal(
		player,
		Config.GetTotalXPForLevel(level),
		source or "SetLevel"
	)
end

function CharacterProgressionService.ResetProgress(
	player: Player,
	source: string?
)
	return setTotalXPInternal(
		player,
		0,
		source or "ResetProgress"
	)
end

function CharacterProgressionService.GetConfig()
	return Config
end

-- Player lifecycle is intentionally owned by CharacterDataService.
-- It saves persistent slot data before calling ReleasePlayer().

return CharacterProgressionService
