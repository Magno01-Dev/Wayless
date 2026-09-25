--!strict
-- MissionService v1 - Generic Server Mission State
-- ServerScriptService > MissionService [ModuleScript]

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local ServerScriptService =
	game:GetService("ServerScriptService")

local MissionDefinitions =
	require(
		ReplicatedStorage:
		WaitForChild("MissionDefinitions")
	)

local RyoService =
	require(
		ServerScriptService:
		WaitForChild("RyoService")
	)

local MissionService = {}

type MissionState = {
	ActiveMissionId: string,
	Progress: number,
	UniqueProgress: {[string]: boolean},
	LastCompletedMissionId: string,
	CompletedCount: number,
}

local States: {[Player]: MissionState} = {}

local function newState(): MissionState
	return {
		ActiveMissionId = "",
		Progress = 0,
		UniqueProgress = {},
		LastCompletedMissionId = "",
		CompletedCount = 0,
	}
end

local function getDefinition(
	missionId: string
): any?

	return MissionDefinitions.GetMission(missionId)
end

local function getRequired(
	definition: any?
): number

	if not definition
		or typeof(definition.Objective) ~= "table" then

		return 0
	end

	return math.max(
		0,
		math.floor(
			tonumber(definition.Objective.Required) or 0
		)
	)
end

local function getRewardRyo(
	definition: any?
): number

	if not definition
		or typeof(definition.Rewards) ~= "table" then

		return 0
	end

	return math.max(
		0,
		math.floor(
			tonumber(definition.Rewards.Ryo) or 0
		)
	)
end

local function syncLegacyCleanTheVillage(
	player: Player,
	state: MissionState
)

	local legacyDefinition =
		getDefinition("CleanTheVillage")

	local active =
		state.ActiveMissionId == "CleanTheVillage"

	player:SetAttribute(
		"CleanTheVillageActive",
		active
	)

	player:SetAttribute(
		"CleanTheVillageProgress",
		if active then state.Progress else 0
	)

	player:SetAttribute(
		"CleanTheVillageRequired",
		getRequired(legacyDefinition)
	)

	player:SetAttribute(
		"CleanTheVillageRewardRyo",
		getRewardRyo(legacyDefinition)
	)
end

local function syncPlayer(
	player: Player
)

	local state = States[player]

	if not state then
		return
	end

	local definition =
		if state.ActiveMissionId ~= ""
		then getDefinition(state.ActiveMissionId)
		else nil

	local objective =
		definition and definition.Objective or nil

	player:SetAttribute(
		"ActiveMissionId",
		state.ActiveMissionId
	)

	player:SetAttribute(
		"MissionActive",
		state.ActiveMissionId ~= ""
	)

	player:SetAttribute(
		"MissionProgress",
		state.Progress
	)

	player:SetAttribute(
		"MissionRequired",
		getRequired(definition)
	)

	player:SetAttribute(
		"MissionRewardRyo",
		getRewardRyo(definition)
	)

	player:SetAttribute(
		"MissionObjectiveType",
		if objective
			and typeof(objective.Type) == "string"
			then objective.Type
			else ""
	)

	player:SetAttribute(
		"MissionNPCId",
		if definition
			and typeof(definition.NPCId) == "string"
			then definition.NPCId
			else ""
	)

	player:SetAttribute(
		"MissionLastCompletedId",
		state.LastCompletedMissionId
	)

	player:SetAttribute(
		"MissionCompletedCount",
		state.CompletedCount
	)

	syncLegacyCleanTheVillage(player, state)

	player:SetAttribute(
		"MissionSystemReady",
		true
	)
end

function MissionService.InitializePlayer(
	player: Player
)

	if not States[player] then
		States[player] = newState()
	end

	player:SetAttribute(
		"MissionSystemReady",
		false
	)

	syncPlayer(player)
end

function MissionService.GetState(
	player: Player
): MissionState?

	return States[player]
end

function MissionService.GetActiveMissionId(
	player: Player
): string?

	local state = States[player]

	if not state
		or state.ActiveMissionId == "" then

		return nil
	end

	return state.ActiveMissionId
end

function MissionService.GetActiveDefinition(
	player: Player
): any?

	local missionId =
		MissionService.GetActiveMissionId(player)

	if not missionId then
		return nil
	end

	return getDefinition(missionId)
end

function MissionService.IsMissionActive(
	player: Player,
	missionId: string
): boolean

	return MissionService.GetActiveMissionId(player) ==
		missionId
end

function MissionService.HasUniqueProgress(
	player: Player,
	key: string
): boolean

	local state = States[player]

	return state ~= nil
		and state.UniqueProgress[key] == true
end

function MissionService.Accept(
	player: Player,
	missionId: string
): (boolean, string)

	local definition =
		getDefinition(missionId)

	if not definition
		or definition.Enabled ~= true then

		return false, "INVALID_MISSION"
	end

	local state = States[player]

	if not state then
		MissionService.InitializePlayer(player)
		state = States[player]
	end

	if state.ActiveMissionId ~= "" then
		return false, "MISSION_ALREADY_ACTIVE"
	end

	state.ActiveMissionId = missionId
	state.Progress = 0
	state.UniqueProgress = {}

	syncPlayer(player)

	print(
		"[MissionService] ACCEPT",
		player.Name,
		missionId
	)

	return true, "OK"
end

function MissionService.Abandon(
	player: Player
): (boolean, string, string?)

	local state = States[player]

	if not state
		or state.ActiveMissionId == "" then

		return false, "NO_ACTIVE_MISSION", nil
	end

	local oldMissionId =
		state.ActiveMissionId

	state.ActiveMissionId = ""
	state.Progress = 0
	state.UniqueProgress = {}

	syncPlayer(player)

	print(
		"[MissionService] ABANDON",
		player.Name,
		oldMissionId
	)

	return true, "OK", oldMissionId
end

local function tryComplete(
	player: Player,
	state: MissionState,
	definition: any
): (boolean, string, any?)

	local required =
		getRequired(definition)

	if required <= 0
		or state.Progress < required then

		return false, "NOT_COMPLETE", nil
	end

	local missionId =
		state.ActiveMissionId

	local rewardRyo =
		getRewardRyo(definition)

	local newBalance =
		RyoService.Get(player)

	if rewardRyo > 0 then

		local success,
			balance,
			errorMessage =
			RyoService.Add(
				player,
				rewardRyo,
				"Mission:" .. missionId
			)

		if not success then
			return false,
				errorMessage or "REWARD_FAILED",
				nil
		end

		newBalance = balance
	end

	local completedProgress =
		state.Progress

	state.LastCompletedMissionId =
		missionId

	state.CompletedCount += 1

	state.ActiveMissionId = ""
	state.Progress = 0
	state.UniqueProgress = {}

	syncPlayer(player)

	local result = {
		MissionId = missionId,
		Progress = completedProgress,
		Required = required,
		RewardRyo = rewardRyo,
		NewRyoBalance = newBalance,
	}

	print(
		"[MissionService] COMPLETE",
		player.Name,
		missionId,
		"RewardRyo",
		rewardRyo
	)

	return true, "COMPLETED", result
end

function MissionService.AddProgress(
	player: Player,
	missionId: string,
	amount: number,
	uniqueKey: string?
): (boolean, string, any?)

	local state = States[player]

	if not state
		or state.ActiveMissionId ~= missionId then

		return false, "MISSION_NOT_ACTIVE", nil
	end

	local definition =
		getDefinition(missionId)

	if not definition then
		return false, "INVALID_MISSION", nil
	end

	if uniqueKey
		and uniqueKey ~= "" then

		if state.UniqueProgress[uniqueKey] then

			local completed,
				reason,
				completion =
				tryComplete(
					player,
					state,
					definition
				)

			if completed then
				return true, reason, completion
			end

			return false, "ALREADY_COUNTED", nil
		end

		state.UniqueProgress[uniqueKey] = true
	end

	local required =
		getRequired(definition)

	local safeAmount =
		math.max(
			0,
			math.floor(
				tonumber(amount) or 0
			)
		)

	if safeAmount <= 0 then
		return false, "INVALID_PROGRESS", nil
	end

	state.Progress =
		math.min(
			required,
			state.Progress + safeAmount
		)

	syncPlayer(player)

	local completed,
		reason,
		completion =
		tryComplete(
			player,
			state,
			definition
		)

	if completed then
		return true, reason, completion
	end

	return true,
		"PROGRESSED",
		{
			MissionId = missionId,
			Progress = state.Progress,
			Required = required,
			Completed = false,
		}
end

function MissionService.MarkCollected(
	player: Player,
	missionId: string,
	objectId: string
): (boolean, string, any?)

	local definition =
		getDefinition(missionId)

	if not definition
		or typeof(definition.Objective) ~= "table"
		or definition.Objective.Type ~= "Collect" then

		return false, "NOT_COLLECT_MISSION", nil
	end

	return MissionService.AddProgress(
		player,
		missionId,
		1,
		"Collect:" .. objectId
	)
end

Players.PlayerRemoving:
	Connect(
		function(player: Player)
			States[player] = nil
		end
	)

print(
	"[MissionService] READY v1"
		.. " | GenericState=ON"
		.. " | OneActiveMission=ON"
		.. " | RyoRewards=ON"
)

return MissionService
