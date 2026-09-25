--!strict
-- ServerScriptService > MovementRestrictionService
--
-- Generic movement restriction service.
--
-- Any future jutsu/system can call:
--
-- MovementRestrictionService.Apply(character, {
--     Source = "Jutsu:FlameBreath",
--     Duration = 1.5,
--     BlockSprint = true,
--     MaxWalkSpeed = 16,
-- })
--
-- Replicated Character attributes:
--
-- Movement_SprintLocked
-- Movement_WalkSpeedCap
-- Movement_RestrictionUntil
-- Movement_RestrictionSources

local HttpService = game:GetService("HttpService")

local MovementRestrictionService = {}

export type RestrictionOptions = {
	Source: string?,
	Duration: number,
	BlockSprint: boolean?,
	MaxWalkSpeed: number?,
}

type Restriction = {
	Token: string,
	Source: string,
	ExpiresAt: number,
	BlockSprint: boolean,
	MaxWalkSpeed: number?,
}

type RestrictionBucket = {
	[string]: Restriction,
}

local restrictionsByCharacter: {[Model]: RestrictionBucket} = {}

local function getNow(): number
	return workspace:GetServerTimeNow()
end

local function clearReplicatedState(character: Model)
	if not character.Parent then
		return
	end

	character:SetAttribute("Movement_SprintLocked", false)
	character:SetAttribute("Movement_WalkSpeedCap", nil)
	character:SetAttribute("Movement_RestrictionUntil", nil)
	character:SetAttribute("Movement_RestrictionSources", nil)
end

local function recompute(character: Model)
	local bucket =
		restrictionsByCharacter[character]

	if not bucket then
		clearReplicatedState(character)
		return
	end

	local now =
		getNow()

	local sprintLocked =
		false

	local effectiveCap: number? =
		nil

	local latestExpiry =
		0

	local sourceSet: {[string]: boolean} =
		{}

	for token, restriction in pairs(bucket) do
		if restriction.ExpiresAt <= now then
			bucket[token] = nil
			continue
		end

		if restriction.BlockSprint then
			sprintLocked = true
		end

		if restriction.MaxWalkSpeed ~= nil then
			effectiveCap =
				if effectiveCap == nil
				then restriction.MaxWalkSpeed
				else math.min(
					effectiveCap,
					restriction.MaxWalkSpeed
				)
		end

		latestExpiry =
			math.max(
				latestExpiry,
				restriction.ExpiresAt
			)

		sourceSet[restriction.Source] =
			true
	end

	if next(bucket) == nil then
		restrictionsByCharacter[character] =
			nil

		clearReplicatedState(character)

		return
	end

	local sources: {string} =
		{}

	for source in pairs(sourceSet) do
		table.insert(
			sources,
			source
		)
	end

	table.sort(sources)

	if character.Parent then
		character:SetAttribute(
			"Movement_SprintLocked",
			sprintLocked
		)

		character:SetAttribute(
			"Movement_WalkSpeedCap",
			effectiveCap
		)

		character:SetAttribute(
			"Movement_RestrictionUntil",
			latestExpiry
		)

		character:SetAttribute(
			"Movement_RestrictionSources",
			table.concat(
				sources,
				","
			)
		)
	end

	-- Server-side safety cap.
	-- We only lower WalkSpeed; we never increase it.
	if effectiveCap ~= nil then
		local humanoid =
			character:
			FindFirstChildOfClass(
				"Humanoid"
			)

		if humanoid
			and humanoid.Health > 0
			and humanoid.WalkSpeed > effectiveCap then

			humanoid.WalkSpeed =
				effectiveCap
		end
	end
end

function MovementRestrictionService.Apply(
	character: Model,
	options: RestrictionOptions
): string

	assert(
		typeof(character) == "Instance"
			and character:IsA("Model"),
		"MovementRestrictionService.Apply requires a character Model"
	)

	local duration =
		math.max(
			0,
			options.Duration
		)

	local token =
		HttpService:
		GenerateGUID(
			false
		)

	if duration <= 0 then
		return token
	end

	local source =
		if typeof(options.Source) == "string"
		and options.Source ~= ""
		then options.Source
		else "Unknown"

	local maxWalkSpeed: number? =
		nil

	if typeof(options.MaxWalkSpeed) == "number" then
		maxWalkSpeed =
			math.max(
				0,
				options.MaxWalkSpeed
			)
	end

	local bucket =
		restrictionsByCharacter[character]

	if not bucket then
		bucket = {}
		restrictionsByCharacter[character] =
			bucket
	end

	local restriction: Restriction = {
		Token =
			token,

		Source =
			source,

		ExpiresAt =
			getNow()
			+ duration,

		BlockSprint =
			options.BlockSprint == true,

		MaxWalkSpeed =
			maxWalkSpeed,
	}

	bucket[token] =
		restriction

	recompute(
		character
	)

	task.delay(
		duration + 0.05,

		function()

			local currentBucket =
				restrictionsByCharacter[character]

			if not currentBucket then
				return
			end

			if currentBucket[token] ~= restriction then
				return
			end

			currentBucket[token] =
				nil

			recompute(
				character
			)
		end
	)

	return token
end

function MovementRestrictionService.Release(
	character: Model,
	token: string
)

	local bucket =
		restrictionsByCharacter[character]

	if not bucket then
		return
	end

	bucket[token] =
		nil

	recompute(
		character
	)
end

function MovementRestrictionService.ClearSource(
	character: Model,
	source: string
)

	local bucket =
		restrictionsByCharacter[character]

	if not bucket then
		return
	end

	for token, restriction in pairs(bucket) do
		if restriction.Source == source then
			bucket[token] = nil
		end
	end

	recompute(
		character
	)
end

function MovementRestrictionService.ClearAll(
	character: Model
)

	restrictionsByCharacter[character] =
		nil

	clearReplicatedState(
		character
	)
end

return MovementRestrictionService
