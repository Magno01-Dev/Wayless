--!strict
-- MissionDefinitions v1.1 - Client-Local Mission Assets
-- ReplicatedStorage > MissionDefinitions [ModuleScript]

local MissionDefinitions = {}

MissionDefinitions.NPCs = {
	Sasuke = {
		Id = "Sasuke",
		DisplayName = "SASUKE",
		WorkspaceFolder = "Missions NPC",
		ModelName = "Sasuke",
		InteractionDistance = 10,
		HoldDuration = 0.45,

		Prompt = {
			Action = "INTERACT",
			Hint = "SASUKE  •  HOLD E",
			BillboardMaxDistance = 40,
			VisualTolerance = 0.35,
		},
	},
}

MissionDefinitions.Missions = {
	CleanTheVillage = {
		Id = "CleanTheVillage",
		Enabled = true,
		OfferPriority = 100,

		Title = "CLEAN THE VILLAGE",
		TrackerTitle = "CLEAN THE VILLAGE",
		NPCId = "Sasuke",

		Description =
			"Collect 8 pieces of trash around the village.",

		Dialogue = {
			Offer = {
				"Hey.",
				"The village is a mess.",
				"I need you to clean it up.",
				"Collect {Required} pieces of trash.",
				"Come back when you're done.",
			},

			Active =
				"You already have this mission in progress.",

			Busy =
				"Finish your current mission first.",
		},

		Objective = {
			Type = "Collect",
			Required = 8,

			-- The authored collectible templates stay outside Workspace.
			-- AssetPath is relative to ReplicatedStorage.
			SpawnMode = "ClientLocal",

			AssetPath = {
				"MissionAssets",
				"CleanTheVillage",
				"MissionTrash",
			},

			RuntimeFolderName = "MissionTrash",

			InteractionDistance = 8,
			HoldDuration = 2.0,
			TrackerLabel = "TRASH",

			Prompt = {
				Action = "HOLD  •  COLLECT",
				Hint = "KEEP E PRESSED",
				BillboardMaxDistance = 20,
			},

			Animation = {
				-- Replace 0 with the future R6 pickup animation ID.
				Id = 0,
				Speed = 1.0,
				FadeTime = 0.08,
			},
		},

		Rewards = {
			Ryo = 5,
		},

		Completion = {
			VFXDelay = 3.0,
		},
	},
}

function MissionDefinitions.GetMission(
	missionId: string
): any?

	return MissionDefinitions.Missions[
	missionId
	]
end

function MissionDefinitions.GetNPC(
	npcId: string
): any?

	return MissionDefinitions.NPCs[
	npcId
	]
end

function MissionDefinitions.GetAllMissionIds(): {string}

	local ids = {}

	for missionId, definition in pairs(
		MissionDefinitions.Missions
		) do
		if definition.Enabled == true then
			table.insert(ids, missionId)
		end
	end

	table.sort(ids)

	return ids
end

function MissionDefinitions.GetAllNPCIds(): {string}

	local ids = {}

	for npcId in pairs(
		MissionDefinitions.NPCs
		) do
		table.insert(ids, npcId)
	end

	table.sort(ids)

	return ids
end

function MissionDefinitions.GetMissionsForNPC(
	npcId: string
): {any}

	local result = {}

	for _, definition in pairs(
		MissionDefinitions.Missions
		) do
		if definition.Enabled == true
			and definition.NPCId == npcId then

			table.insert(result, definition)
		end
	end

	table.sort(
		result,
		function(a, b)
			return (
				tonumber(a.OfferPriority) or 0
			) > (
				tonumber(b.OfferPriority) or 0
			)
		end
	)

	return result
end

function MissionDefinitions.GetCollectMissions(): {any}

	local result = {}

	for _, definition in pairs(
		MissionDefinitions.Missions
		) do
		if definition.Enabled == true
			and typeof(definition.Objective) == "table"
			and definition.Objective.Type == "Collect" then

			table.insert(result, definition)
		end
	end

	return result
end

function MissionDefinitions.FormatText(
	text: string,
	missionId: string
): string

	local definition =
		MissionDefinitions.GetMission(missionId)

	if not definition then
		return text
	end

	local objective =
		definition.Objective or {}

	local rewards =
		definition.Rewards or {}

	local replacements = {
		Required = tostring(objective.Required or 0),
		RewardRyo = tostring(rewards.Ryo or 0),
		Title = tostring(definition.Title or missionId),
	}

	local result = text

	for token, value in pairs(replacements) do
		result =
			string.gsub(
				result,
				"{" .. token .. "}",
				value
			)
	end

	return result
end

return MissionDefinitions
