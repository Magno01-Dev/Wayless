--!strict
-- MissionServer v5.2 - Anywhere Abandon + Replicated Mission Assets
-- ServerScriptService > MissionServer [Script]

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

local MissionService =
	require(
		ServerScriptService:
		WaitForChild("MissionService")
	)

--==================================================
-- REMOTES
--==================================================

local Remotes =
	ReplicatedStorage:
	FindFirstChild("MissionRemotes")

if not Remotes then

	Remotes =
		Instance.new("Folder")

	Remotes.Name =
		"MissionRemotes"

	Remotes.Parent =
		ReplicatedStorage
end

local function GetRemote(
	Name
): RemoteEvent

	local Existing =
		Remotes:
		FindFirstChild(Name)

	if Existing
		and Existing:IsA("RemoteEvent") then

		return Existing
	end

	if Existing then
		Existing:Destroy()
	end

	local Remote =
		Instance.new("RemoteEvent")

	Remote.Name =
		Name

	Remote.Parent =
		Remotes

	return Remote
end

local OpenMissionDialogue =
	GetRemote("OpenMissionDialogue")

local CloseMissionDialogue =
	GetRemote("CloseMissionDialogue")

local BeginNPCInteraction =
	GetRemote("BeginNPCInteraction")

local CancelNPCInteraction =
	GetRemote("CancelNPCInteraction")

local NPCInteractionState =
	GetRemote("NPCInteractionState")

local EndDialogueSession =
	GetRemote("EndDialogueSession")

local AcceptMission =
	GetRemote("AcceptMission")

local AbandonMission =
	GetRemote("AbandonMission")

local BeginCollectObjective =
	GetRemote("BeginCollectObjective")

local CancelCollectObjective =
	GetRemote("CancelCollectObjective")

local CollectObjectiveState =
	GetRemote("CollectObjectiveState")

local ObjectiveVisibility =
	GetRemote("ObjectiveVisibility")

local ObjectiveCollectEffect =
	GetRemote("ObjectiveCollectEffect")

local MissionCompleted =
	GetRemote("MissionCompleted")

--==================================================
-- SETTINGS
--==================================================

local DIALOGUE_AUTHORIZATION_TIME =
	60

local NPC_CHECK_INTERVAL =
	0.05

local DIALOGUE_DISTANCE_CHECK_INTERVAL =
	0.10

local COLLECT_CHECK_INTERVAL =
	0.05

--==================================================
-- WORLD RESOLUTION
--==================================================

local NPCModels = {}
local CollectAssetFolders = {}

local function NormalizeName(
	Value
)

	return string.lower(
		string.gsub(
			Value,
			"%s+",
			""
		)
	)
end

local function ResolveNPC(
	NPCId
)

	local Cached =
		NPCModels[NPCId]

	if Cached
		and Cached.Parent then

		return Cached
	end

	local Definition =
		MissionDefinitions.GetNPC(
			NPCId
		)

	if not Definition then
		return nil
	end

	local Folder =
		workspace:
		FindFirstChild(
			Definition.WorkspaceFolder
		)

	if not Folder then
		return nil
	end

	local Wanted =
		NormalizeName(
			Definition.ModelName
		)

	for _, Object in ipairs(
		Folder:GetDescendants()
		) do

		if Object:IsA("Model")
			and NormalizeName(
				Object.Name
			) == Wanted then

			NPCModels[NPCId] =
				Object

			return Object
		end
	end

	for _, Object in ipairs(
		Folder:GetChildren()
		) do

		if Object:IsA("Model")
			and NormalizeName(
				Object.Name
			) == Wanted then

			NPCModels[NPCId] =
				Object

			return Object
		end
	end

	return nil
end

local function ResolveReplicatedAssetPath(
	Path
)

	if typeof(Path) ~= "table" then
		return nil
	end

	local Current =
		ReplicatedStorage

	for _, Name in ipairs(
		Path
		) do

		if typeof(Name) ~= "string"
			or Name == "" then

			return nil
		end

		Current =
			Current:
			FindFirstChild(
				Name
			)

		if not Current then
			return nil
		end
	end

	return Current
end

local function ResolveCollectAssetFolder(
	MissionId
)

	local Cached =
		CollectAssetFolders[MissionId]

	if Cached
		and Cached.Parent then

		return Cached
	end

	local Definition =
		MissionDefinitions.GetMission(
			MissionId
		)

	if not Definition
		or typeof(
			Definition.Objective
		) ~= "table"
			or Definition.Objective.Type ~= "Collect" then

		return nil
	end

	local Folder =
		ResolveReplicatedAssetPath(
			Definition.Objective.AssetPath
		)

	if Folder then

		CollectAssetFolders[MissionId] =
			Folder
	end

	return Folder
end

local function GetModelRoot(
	Model
)

	local Root =
		Model:
		FindFirstChild(
			"HumanoidRootPart",
			true
		)

	if Root
		and Root:IsA("BasePart") then

		return Root
	end

	return Model:
		FindFirstChildWhichIsA(
			"BasePart",
			true
		)
end

local function GetObjectCenter(
	Object
)

	if Object:IsA("BasePart") then
		return Object.Position
	end

	local Center =
		Vector3.zero

	local Count =
		0

	for _, Descendant in ipairs(
		Object:GetDescendants()
		) do

		if Descendant:IsA("BasePart") then

			Center +=
				Descendant.Position

			Count +=
				1
		end
	end

	if Count <= 0 then
		return nil
	end

	return Center / Count
end

--==================================================
-- WORLD SAFETY
--==================================================

local function ProtectMissionNPC(
	NPCId
)

	local Model =
		ResolveNPC(NPCId)

	if not Model then

		warn(
			"[MissionServer] NPC missing:",
			NPCId
		)

		return
	end

	Model:SetAttribute(
		"IsMissionNPC",
		true
	)

	Model:SetAttribute(
		"MissionNPCId",
		NPCId
	)

	local Humanoid =
		Model:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if Humanoid then

		Humanoid.MaxHealth =
			math.huge

		Humanoid.Health =
			math.huge

		Humanoid.BreakJointsOnDeath =
			false

		Humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Dead,
			false
		)

		Humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Ragdoll,
			false
		)

		Humanoid:SetStateEnabled(
			Enum.HumanoidStateType.FallingDown,
			false
		)

		Humanoid.HealthChanged:
			Connect(
				function()

					if Humanoid.Health <
						math.huge then

						Humanoid.Health =
						math.huge
					end
				end
			)
	end

	local Root =
		GetModelRoot(Model)

	if Root then
		Root.Anchored = true
	end

	for _, Descendant in ipairs(
		Model:GetDescendants()
		) do

		if Descendant:IsA("BasePart") then

			Descendant.CanCollide =
				false

			Descendant.CanTouch =
				false

			Descendant.CanQuery =
				true
		end
	end
end

local function ValidateCollectAssetFolder(
	MissionId
)

	local Folder =
		ResolveCollectAssetFolder(
			MissionId
		)

	if not Folder then

		warn(
			"[MissionServer] Collect AssetPath missing:",
			MissionId
		)

		return
	end

	local Definition =
		MissionDefinitions.GetMission(
			MissionId
		)

	local Required =
		if Definition
		and Definition.Objective
		then tonumber(
			Definition.Objective.Required
		) or 0
		else 0

	local SeenNames = {}
	local ValidObjects = 0

	for _, Object in ipairs(
		Folder:GetChildren()
		) do

		if SeenNames[
			Object.Name
			] then

			warn(
				"[MissionServer] Duplicate mission object name:",
				MissionId,
				Object.Name
			)

		else

			SeenNames[
			Object.Name
			] =
				true
		end

		if GetObjectCenter(
			Object
			) then

			ValidObjects +=
				1

		else

			warn(
				"[MissionServer] Mission object has no BasePart:",
				MissionId,
				Object.Name
			)
		end
	end

	if ValidObjects <
		Required then

		warn(
			"[MissionServer] Not enough collect assets:",
			MissionId,
			"required",
			Required,
			"found",
			ValidObjects
		)
	end

	print(
		"[MissionServer] Collect assets ready:",
		MissionId,
		ValidObjects
	)
end

for _, NPCId in ipairs(
	MissionDefinitions.GetAllNPCIds()
	) do

	ProtectMissionNPC(
		NPCId
	)
end

for _, Definition in ipairs(
	MissionDefinitions.GetCollectMissions()
	) do

	ValidateCollectAssetFolder(
		Definition.Id
	)
end

--==================================================
-- CHARACTER STATE
--==================================================

local BlockingAttributes = {
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsCarrying",
	"IsExecuting",
	"IsBeingExecuted",
	"IsRecovering",
	"IsStunned",
	"IsDashing",
	"TreeJumpActive",
	"IsTreeJumping",
}

local function GetCharacterStateBlockReason(
	Player
)

	if Player:GetAttribute(
		"InventoryOpen"
		) == true then

		return "INVENTORY"
	end

	local Character =
		Player.Character

	if not Character then
		return "NO_CHARACTER"
	end

	local Humanoid =
		Character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not Humanoid
		or Humanoid.Health <= 0 then

		return "DEAD"
	end

	if Character:GetAttribute(
		"CombatMode"
		) == true then

		return "COMBAT_MODE"
	end

	if Character:GetAttribute(
		"CombatTagged"
		) == true then

		return "COMBAT_TAG"
	end

	for _, AttributeName in ipairs(
		BlockingAttributes
		) do

		if Character:GetAttribute(
			AttributeName
			) == true then

			return AttributeName
		end
	end

	return nil
end

local function GetPlayerDistanceToNPC(
	Player,
	NPCId
)

	local Character =
		Player.Character

	local NPC =
		ResolveNPC(
			NPCId
		)

	if not Character
		or not NPC then

		return math.huge
	end

	local PlayerRoot =
		Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	local NPCRoot =
		GetModelRoot(
			NPC
		)

	if not PlayerRoot
		or not PlayerRoot:IsA("BasePart")
		or not NPCRoot then

		return math.huge
	end

	return (
		PlayerRoot.Position
		- NPCRoot.Position
	).Magnitude
end

local function IsPlayerNearNPC(
	Player,
	NPCId
)

	local Definition =
		MissionDefinitions.GetNPC(
			NPCId
		)

	if not Definition then
		return false
	end

	local Distance =
		tonumber(
			Definition.InteractionDistance
		) or 0

	return GetPlayerDistanceToNPC(
		Player,
		NPCId
	) <= Distance
end

--==================================================
-- PLAYER SETUP
--==================================================

local function SetupPlayer(
	Player
)

	MissionService.InitializePlayer(
		Player
	)
end

Players.PlayerAdded:
	Connect(
		SetupPlayer
	)

for _, Player in ipairs(
	Players:GetPlayers()
	) do

	SetupPlayer(
		Player
	)
end

--==================================================
-- INTERACTION STATE
--==================================================

local NPCHolds = {}
local CollectHolds = {}
local DialogueSessions = {}

local function ClearCharacterMissionInteraction(
	Player,
	ExpectedPrefix
)

	local Character =
		Player.Character

	if not Character then
		return
	end

	local CurrentType =
		Character:GetAttribute(
			"MissionInteractionType"
		)

	if ExpectedPrefix
		and typeof(CurrentType) == "string"
		and not string.find(
			CurrentType,
			ExpectedPrefix,
			1,
			true
		) then

		return
	end

	Character:SetAttribute(
		"MissionInteractionActive",
		false
	)

	Character:SetAttribute(
		"MissionInteractionType",
		""
	)
end

local function ClearNPCHold(
	Player,
	NotifyClient,
	Reason
)

	local State =
		NPCHolds[Player]

	NPCHolds[Player] =
		nil

	ClearCharacterMissionInteraction(
		Player,
		"NPC:"
	)

	if NotifyClient
		and State then

		NPCInteractionState:FireClient(
			Player,
			"Cancelled",
			State.NPCId,
			Reason
		)
	end
end

local function ClearCollectHold(
	Player,
	NotifyClient,
	Reason
)

	local State =
		CollectHolds[Player]

	CollectHolds[Player] =
		nil

	ClearCharacterMissionInteraction(
		Player,
		"Collect:"
	)

	if NotifyClient
		and State then

		CollectObjectiveState:FireClient(
			Player,
			"Cancelled",
			State.MissionId,
			State.ObjectId,
			Reason
		)
	end
end

local function ClearDialogueSession(
	Player,
	NotifyClient,
	Reason
)

	local State =
		DialogueSessions[Player]

	DialogueSessions[Player] =
		nil

	if NotifyClient
		and State then

		CloseMissionDialogue:FireClient(
			Player,
			Reason
		)
	end
end

Players.PlayerRemoving:
	Connect(
		function(Player)

			ClearNPCHold(
				Player,
				false,
				"PLAYER_LEAVING"
			)

			ClearCollectHold(
				Player,
				false,
				"PLAYER_LEAVING"
			)

			ClearDialogueSession(
				Player,
				false,
				"PLAYER_LEAVING"
			)
		end
	)

--==================================================
-- DIALOGUE
--==================================================

local function ChooseOfferForNPC(
	NPCId
)

	local Offers =
		MissionDefinitions.GetMissionsForNPC(
			NPCId
		)

	return Offers[1]
end

local function StartDialogueSession(
	Player,
	NPCId,
	MissionId
)

	ClearDialogueSession(
		Player,
		false,
		"REPLACED"
	)

	local State = {
		Token = {},
		NPCId = NPCId,
		MissionId = MissionId,
		ExpiresAt =
			os.clock()
			+ DIALOGUE_AUTHORIZATION_TIME,
	}

	DialogueSessions[Player] =
		State

	task.spawn(
		function()

			while DialogueSessions[Player] ==
				State do

				task.wait(
					DIALOGUE_DISTANCE_CHECK_INTERVAL
				)

				if DialogueSessions[Player] ~=
					State then

					return
				end

				if os.clock() >
					State.ExpiresAt then

					ClearDialogueSession(
						Player,
						true,
						"SESSION_EXPIRED"
					)

					return
				end

				if not IsPlayerNearNPC(
					Player,
					NPCId
					) then

					ClearDialogueSession(
						Player,
						true,
						"TOO_FAR"
					)

					return
				end

				local Block =
					GetCharacterStateBlockReason(
						Player
					)

				if Block then

					ClearDialogueSession(
						Player,
						true,
						Block
					)

					return
				end
			end
		end
	)
end

local function OpenNPCDialogue(
	Player,
	NPCId
)

	local ActiveMissionId =
		MissionService.GetActiveMissionId(
			Player
		)

	if ActiveMissionId then

		local ActiveDefinition =
			MissionDefinitions.GetMission(
				ActiveMissionId
			)

		StartDialogueSession(
			Player,
			NPCId,
			ActiveMissionId
		)

		if ActiveDefinition
			and ActiveDefinition.NPCId ==
			NPCId then

			OpenMissionDialogue:FireClient(
				Player,
				NPCId,
				ActiveMissionId,
				"ActiveMission"
			)

		else

			OpenMissionDialogue:FireClient(
				Player,
				NPCId,
				ActiveMissionId,
				"Busy"
			)
		end

		return
	end

	local Offer =
		ChooseOfferForNPC(
			NPCId
		)

	if not Offer then

		StartDialogueSession(
			Player,
			NPCId,
			nil
		)

		OpenMissionDialogue:FireClient(
			Player,
			NPCId,
			"",
			"NoMission"
		)

		return
	end

	StartDialogueSession(
		Player,
		NPCId,
		Offer.Id
	)

	OpenMissionDialogue:FireClient(
		Player,
		NPCId,
		Offer.Id,
		"Offer"
	)
end

--==================================================
-- NPC HOLD E
--==================================================

BeginNPCInteraction.OnServerEvent:
	Connect(
		function(
			Player,
			NPCId
		)

			if typeof(NPCId) ~=
				"string" then

				return
			end

			local Definition =
			MissionDefinitions.GetNPC(
				NPCId
			)

			if not Definition then
				return
			end

			if NPCHolds[Player]
				or CollectHolds[Player] then

				return
			end

			local Character =
			Player.Character

			if not Character then
				return
			end

			if Character:GetAttribute(
				"MissionInteractionActive"
				) == true then

				return
			end

			local Block =
			GetCharacterStateBlockReason(
				Player
			)

			if Block
				or not IsPlayerNearNPC(
					Player,
					NPCId
				) then

				NPCInteractionState:FireClient(
					Player,
					"Cancelled",
					NPCId,
					Block or "TOO_FAR"
				)

				return
			end

			local Duration =
			math.max(
				0.05,
				tonumber(
					Definition.HoldDuration
				) or 0.45
			)

			local State = {
				Token = {},
				NPCId = NPCId,
				Character = Character,
			}

			NPCHolds[Player] =
			State

			Character:SetAttribute(
				"MissionInteractionActive",
				true
			)

			Character:SetAttribute(
				"MissionInteractionType",
				"NPC:" .. NPCId
			)

			NPCInteractionState:FireClient(
				Player,
				"Started",
				NPCId,
				Duration
			)

			task.spawn(
				function()

					local StartedAt =
					os.clock()

					while os.clock()
						- StartedAt <
						Duration do

						task.wait(
							NPC_CHECK_INTERVAL
						)

						if NPCHolds[Player] ~=
							State then

							return
						end

						if Player.Character ~=
							Character then

							ClearNPCHold(
								Player,
								true,
								"CHARACTER_CHANGED"
							)

							return
						end

						local CurrentBlock =
						GetCharacterStateBlockReason(
							Player
						)

						if CurrentBlock
							or not IsPlayerNearNPC(
								Player,
								NPCId
							) then

							ClearNPCHold(
								Player,
								true,
								CurrentBlock or "TOO_FAR"
							)

							return
						end
					end

					if NPCHolds[Player] ~=
						State then

						return
					end

					NPCHolds[Player] =
					nil

					ClearCharacterMissionInteraction(
						Player,
						"NPC:"
					)

					NPCInteractionState:FireClient(
						Player,
						"Completed",
						NPCId,
						Duration
					)

					OpenNPCDialogue(
						Player,
						NPCId
					)
				end
			)
		end
	)

CancelNPCInteraction.OnServerEvent:
	Connect(
		function(
			Player,
			NPCId
		)

			local State =
			NPCHolds[Player]

			if not State then
				return
			end

			if typeof(NPCId) == "string"
				and State.NPCId ~= NPCId then

				return
			end

			ClearNPCHold(
				Player,
				true,
				"INPUT_RELEASED"
			)
		end
	)

EndDialogueSession.OnServerEvent:
	Connect(
		function(Player)

			ClearDialogueSession(
				Player,
				false,
				"CLIENT_CLOSED"
			)
		end
	)

--==================================================
-- ACCEPT / ABANDON
--==================================================

AcceptMission.OnServerEvent:
	Connect(
		function(
			Player,
			MissionId
		)

			if typeof(MissionId) ~=
				"string" then

				return
			end

			local Definition =
			MissionDefinitions.GetMission(
				MissionId
			)

			if not Definition
				or Definition.Enabled ~= true then

				return
			end

			local Session =
			DialogueSessions[Player]

			if not Session
				or Session.MissionId ~= MissionId
				or Session.NPCId ~= Definition.NPCId
				or os.clock() >
				Session.ExpiresAt then

				warn(
					"[MissionServer] Accept rejected:",
					Player.Name,
					MissionId
				)

				return
			end

			local Block =
			GetCharacterStateBlockReason(
				Player
			)

			if Block
				or not IsPlayerNearNPC(
					Player,
					Session.NPCId
				) then

				ClearDialogueSession(
					Player,
					true,
					Block or "TOO_FAR"
				)

				return
			end

			local Success,
			Reason =
			MissionService.Accept(
				Player,
				MissionId
			)

			if not Success then

				warn(
					"[MissionServer] Accept failed:",
					Player.Name,
					MissionId,
					Reason
				)

				return
			end

			ClearDialogueSession(
				Player,
				true,
				"MISSION_ACCEPTED"
			)

			if typeof(
				Definition.Objective
				) == "table"
				and Definition.Objective.Type ==
				"Collect" then

				ObjectiveVisibility:FireClient(
					Player,
					"ShowAll",
					MissionId,
					""
				)
			end
		end
	)

AbandonMission.OnServerEvent:
	Connect(
		function(Player)

			-- Abandoning your own mission is allowed from anywhere.
			-- It does not require an NPC dialogue session or NPC proximity.
			--
			-- The server still owns the authoritative mission state and first
			-- verifies that the player actually has an active mission.

			local MissionId =
			MissionService.GetActiveMissionId(
				Player
			)

			if not MissionId then
				return
			end

			ClearCollectHold(
				Player,
				true,
				"MISSION_ABANDONED"
			)

			ClearNPCHold(
				Player,
				true,
				"MISSION_ABANDONED"
			)

			-- If the player abandoned while an NPC window was open,
			-- revoke that authorization too.
			ClearDialogueSession(
				Player,
				true,
				"MISSION_ABANDONED"
			)

			local Success,
			_,
			OldMissionId =
			MissionService.Abandon(
				Player
			)

			if not Success
				or not OldMissionId then

				return
			end

			ObjectiveVisibility:FireClient(
				Player,
				"HideAll",
				OldMissionId,
				""
			)

			print(
				"[MissionServer] ABANDON FROM HUD:",
				Player.Name,
				OldMissionId
			)
		end
	)

--==================================================
-- COLLECT VALIDATION
--==================================================

local function ValidateCollect(
	Player,
	MissionId,
	ObjectId,
	AllowOwnInteraction
)

	if not MissionService.IsMissionActive(
		Player,
		MissionId
		) then

		return nil,
			"MISSION_NOT_ACTIVE"
	end

	local Definition =
		MissionDefinitions.GetMission(
			MissionId
		)

	if not Definition
		or typeof(
			Definition.Objective
		) ~= "table"
			or Definition.Objective.Type ~= "Collect" then

		return nil,
			"INVALID_OBJECTIVE"
	end

	local Character =
		Player.Character

	if not Character then

		return nil,
			"NO_CHARACTER"
	end

	if not AllowOwnInteraction
		and Character:GetAttribute(
			"MissionInteractionActive"
		) == true then

		return nil,
			"OTHER_INTERACTION"
	end

	local Block =
		GetCharacterStateBlockReason(
			Player
		)

	if Block then
		return nil, Block
	end

	if MissionService.HasUniqueProgress(
		Player,
		"Collect:" .. ObjectId
		) then

		return nil,
			"ALREADY_COLLECTED"
	end

	local Folder =
		ResolveCollectAssetFolder(
			MissionId
		)

	if not Folder then

		return nil,
			"FOLDER_MISSING"
	end

	local Object =
		Folder:
		FindFirstChild(
			ObjectId
		)

	if not Object then

		return nil,
			"OBJECT_MISSING"
	end

	local Center =
		GetObjectCenter(
			Object
		)

	if not Center then

		return nil,
			"NO_PARTS"
	end

	local Root =
		Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not Root
		or not Root:IsA("BasePart") then

		return nil,
			"NO_ROOT"
	end

	local Distance =
		tonumber(
			Definition.Objective.InteractionDistance
		) or 0

	if (
		Root.Position
		- Center
		).Magnitude >
		Distance then

		return nil,
			"TOO_FAR"
	end

	return Object,
		nil
end

--==================================================
-- COLLECT HOLD E
--==================================================

BeginCollectObjective.OnServerEvent:
	Connect(
		function(
			Player,
			MissionId,
			ObjectId
		)

			if typeof(MissionId) ~= "string"
				or typeof(ObjectId) ~=
				"string" then

				return
			end

			if CollectHolds[Player]
				or NPCHolds[Player] then

				return
			end

			local Object,
			Error =
			ValidateCollect(
				Player,
				MissionId,
				ObjectId,
				false
			)

			if not Object then

				CollectObjectiveState:FireClient(
					Player,
					"Cancelled",
					MissionId,
					ObjectId,
					Error or "INVALID"
				)

				return
			end

			local Definition =
			MissionDefinitions.GetMission(
				MissionId
			)

			local Duration =
			math.max(
				0.05,
				tonumber(
					Definition.Objective.HoldDuration
				) or 2
			)

			local Character =
			Player.Character

			if not Character then
				return
			end

			local State = {
				Token = {},
				MissionId = MissionId,
				ObjectId = ObjectId,
				Character = Character,
			}

			CollectHolds[Player] =
			State

			Character:SetAttribute(
				"MissionInteractionActive",
				true
			)

			Character:SetAttribute(
				"MissionInteractionType",
				"Collect:" .. MissionId
			)

			CollectObjectiveState:FireClient(
				Player,
				"Started",
				MissionId,
				ObjectId,
				Duration
			)

			task.spawn(
				function()

					local StartedAt =
					os.clock()

					while os.clock()
						- StartedAt <
						Duration do

						task.wait(
							COLLECT_CHECK_INTERVAL
						)

						if CollectHolds[Player] ~=
							State then

							return
						end

						if Player.Character ~=
							Character then

							ClearCollectHold(
								Player,
								true,
								"CHARACTER_CHANGED"
							)

							return
						end

						local CurrentObject,
						CurrentError =
						ValidateCollect(
							Player,
							MissionId,
							ObjectId,
							true
						)

						if not CurrentObject then

							ClearCollectHold(
								Player,
								true,
								CurrentError or "CANCELLED"
							)

							return
						end
					end

					if CollectHolds[Player] ~=
						State then

						return
					end

					local FinalObject,
					FinalError =
					ValidateCollect(
						Player,
						MissionId,
						ObjectId,
						true
					)

					if not FinalObject then

						ClearCollectHold(
							Player,
							true,
							FinalError or "CANCELLED"
						)

						return
					end

					CollectHolds[Player] =
					nil

					ClearCharacterMissionInteraction(
						Player,
						"Collect:"
					)

					local Success,
					Reason,
					Result =
					MissionService.MarkCollected(
						Player,
						MissionId,
						ObjectId
					)

					if not Success then

						CollectObjectiveState:FireClient(
							Player,
							"Cancelled",
							MissionId,
							ObjectId,
							Reason
						)

						return
					end

					CollectObjectiveState:FireClient(
						Player,
						"Completed",
						MissionId,
						ObjectId,
						Duration
					)

					ObjectiveCollectEffect:FireClient(
						Player,
						MissionId,
						ObjectId
					)

					ObjectiveVisibility:FireClient(
						Player,
						"HideOne",
						MissionId,
						ObjectId
					)

					if Reason == "COMPLETED"
						and Result then

						ObjectiveVisibility:FireClient(
							Player,
							"HideAll",
							MissionId,
							""
						)

						MissionCompleted:FireClient(
							Player,
							MissionId,
							Result.RewardRyo,
							Result.NewRyoBalance
						)
					end
				end
			)
		end
	)

CancelCollectObjective.OnServerEvent:
	Connect(
		function(
			Player,
			MissionId,
			ObjectId
		)

			local State =
			CollectHolds[Player]

			if not State then
				return
			end

			if typeof(MissionId) == "string"
				and State.MissionId ~= MissionId then

				return
			end

			if typeof(ObjectId) == "string"
				and State.ObjectId ~= ObjectId then

				return
			end

			ClearCollectHold(
				Player,
				true,
				"INPUT_RELEASED"
			)
		end
	)

print(
	"[MissionServer] READY v5.2"
		.. " | GenericFramework=ON"
		.. " | GenericNPCPrompt=ON"
		.. " | CollectAssets=ReplicatedStorage"
		.. " | AnywhereAbandon=ON"
		.. " | CollectAdapter=ON"
		.. " | ProximityDialogue=ON"
)
