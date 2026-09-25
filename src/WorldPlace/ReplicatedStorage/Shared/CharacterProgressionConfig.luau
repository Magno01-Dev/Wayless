--!strict
-- WAYLESS
-- CharacterProgressionConfig v1.0
--
-- Shared configuration for Character Level / XP.
-- Level is derived from TotalXP. TotalXP is the source of truth.

local Config = {}

Config.MIN_LEVEL = 1
Config.MAX_LEVEL = 100

function Config.GetXPRequiredForNextLevel(level: number): number
	level = math.floor(level)

	if level < Config.MIN_LEVEL then
		level = Config.MIN_LEVEL
	end

	if level >= Config.MAX_LEVEL then
		return 0
	end

	if level <= 4 then
		return 250
	elseif level <= 19 then
		return 400 + 25 * (level - 5)
	elseif level <= 44 then
		return 900 + 25 * (level - 20)
	elseif level <= 69 then
		return 1600 + 25 * (level - 45)
	else
		return 2200 + 30 * (level - 70)
	end
end

local totalXPAtLevel: { [number]: number } = {}
totalXPAtLevel[Config.MIN_LEVEL] = 0

do
	local runningTotal = 0

	for level = Config.MIN_LEVEL, Config.MAX_LEVEL - 1 do
		runningTotal += Config.GetXPRequiredForNextLevel(level)
		totalXPAtLevel[level + 1] = runningTotal
	end
end

Config.MAX_TOTAL_XP = totalXPAtLevel[Config.MAX_LEVEL]

function Config.GetTotalXPForLevel(level: number): number
	level = math.clamp(
		math.floor(level),
		Config.MIN_LEVEL,
		Config.MAX_LEVEL
	)

	return totalXPAtLevel[level]
end

function Config.GetLevelFromTotalXP(totalXP: number): number
	totalXP = math.clamp(
		math.floor(totalXP),
		0,
		Config.MAX_TOTAL_XP
	)

	local low = Config.MIN_LEVEL
	local high = Config.MAX_LEVEL

	while low <= high do
		local mid = math.floor((low + high) / 2)
		local threshold = totalXPAtLevel[mid]

		if threshold <= totalXP then
			if mid == Config.MAX_LEVEL
				or totalXPAtLevel[mid + 1] > totalXP then

				return mid
			end

			low = mid + 1
		else
			high = mid - 1
		end
	end

	return Config.MIN_LEVEL
end

export type ProgressSnapshot = {
	Level: number,
	TotalXP: number,
	XPIntoCurrentLevel: number,
	XPRequiredForNextLevel: number,
	ProgressPercent: number,
	IsMaxLevel: boolean,
}

function Config.GetSnapshotFromTotalXP(totalXP: number): ProgressSnapshot
	totalXP = math.clamp(
		math.floor(totalXP),
		0,
		Config.MAX_TOTAL_XP
	)

	local level = Config.GetLevelFromTotalXP(totalXP)
	local levelStartXP = Config.GetTotalXPForLevel(level)
	local required = Config.GetXPRequiredForNextLevel(level)
	local intoLevel = totalXP - levelStartXP
	local isMax = level >= Config.MAX_LEVEL

	local progress = 1

	if not isMax and required > 0 then
		progress = math.clamp(
			intoLevel / required,
			0,
			1
		)
	end

	return {
		Level = level,
		TotalXP = totalXP,
		XPIntoCurrentLevel = if isMax then 0 else intoLevel,
		XPRequiredForNextLevel = required,
		ProgressPercent = progress,
		IsMaxLevel = isMax,
	}
end

return Config
