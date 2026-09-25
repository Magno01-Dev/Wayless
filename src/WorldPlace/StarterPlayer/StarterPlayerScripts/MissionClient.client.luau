--!strict
-- MissionClient v5.2.1 - Generic Abandon Confirmation Text
-- StarterPlayer > StarterPlayerScripts > MissionClient [LocalScript]

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Debris =
	game:GetService("Debris")

local TweenService =
	game:GetService("TweenService")

local RunService =
	game:GetService("RunService")

local ContextActionService =
	game:GetService("ContextActionService")

local Player =
	Players.LocalPlayer

local PlayerGui =
	Player:WaitForChild("PlayerGui")

local MissionDefinitions =
	require(
		ReplicatedStorage:
		WaitForChild("MissionDefinitions")
	)

local Remotes =
	ReplicatedStorage:
	WaitForChild("MissionRemotes")

local OpenMissionDialogue =
	Remotes:WaitForChild("OpenMissionDialogue")

local CloseMissionDialogue =
	Remotes:WaitForChild("CloseMissionDialogue")

local BeginNPCInteraction =
	Remotes:WaitForChild("BeginNPCInteraction")

local CancelNPCInteraction =
	Remotes:WaitForChild("CancelNPCInteraction")

local NPCInteractionState =
	Remotes:WaitForChild("NPCInteractionState")

local EndDialogueSession =
	Remotes:WaitForChild("EndDialogueSession")

local AcceptMission =
	Remotes:WaitForChild("AcceptMission")

local AbandonMission =
	Remotes:WaitForChild("AbandonMission")

local BeginCollectObjective =
	Remotes:WaitForChild("BeginCollectObjective")

local CancelCollectObjective =
	Remotes:WaitForChild("CancelCollectObjective")

local CollectObjectiveState =
	Remotes:WaitForChild("CollectObjectiveState")

local ObjectiveVisibility =
	Remotes:WaitForChild("ObjectiveVisibility")

local ObjectiveCollectEffect =
	Remotes:WaitForChild("ObjectiveCollectEffect")

local MissionCompleted =
	Remotes:WaitForChild("MissionCompleted")

--==================================================
-- SETTINGS
--==================================================

local COLLECT_CONTEXT_PRIORITY =
	5000

local NPC_CONTEXT_PRIORITY =
	4900

local TARGET_SCAN_INTERVAL =
	0.06

local RYO_ICON =
	"rbxassetid://86885621640262"

--==================================================
-- COLORS
--==================================================

local COLOR_PANEL =
	Color3.fromRGB(
		14,
		14,
		16
	)

local COLOR_RAISED =
	Color3.fromRGB(
		24,
		24,
		27
	)

local COLOR_GOLD =
	Color3.fromRGB(
		190,
		151,
		76
	)

local COLOR_GOLD_DIM =
	Color3.fromRGB(
		116,
		92,
		50
	)

local COLOR_RED =
	Color3.fromRGB(
		148,
		47,
		42
	)

local COLOR_TEXT =
	Color3.fromRGB(
		232,
		228,
		216
	)

local COLOR_TEXT_DIM =
	Color3.fromRGB(
		145,
		141,
		132
	)

--==================================================
-- UI HELPERS
--==================================================

local function AddCorner(
	Parent,
	Radius
)

	local Corner =
		Instance.new("UICorner")

	Corner.CornerRadius =
		UDim.new(
			0,
			Radius
		)

	Corner.Parent =
		Parent
end

local function AddStroke(
	Parent,
	Color,
	Transparency,
	Thickness
)

	local Stroke =
		Instance.new("UIStroke")

	Stroke.ApplyStrokeMode =
		Enum.ApplyStrokeMode.Border

	Stroke.Color =
		Color

	Stroke.Transparency =
		Transparency

	Stroke.Thickness =
		Thickness

	Stroke.Parent =
		Parent

	return Stroke
end

local function CreateLabel(
	Parent,
	Name,
	Text,
	Position,
	Size,
	Font,
	TextSize,
	Color,
	XAlignment
)

	local Label =
		Instance.new("TextLabel")

	Label.Name =
		Name

	Label.BackgroundTransparency =
		1

	Label.Position =
		Position

	Label.Size =
		Size

	Label.Font =
		Font

	Label.Text =
		Text

	Label.TextSize =
		TextSize

	Label.TextColor3 =
		Color

	Label.TextXAlignment =
		XAlignment

	Label.TextYAlignment =
		Enum.TextYAlignment.Center

	Label.TextWrapped =
		true

	Label.Parent =
		Parent

	return Label
end

local function CreateButton(
	Parent,
	Name,
	Text,
	Position,
	Size,
	AccentColor
)

	local Button =
		Instance.new("TextButton")

	Button.Name =
		Name

	Button.Text =
		Text

	Button.Position =
		Position

	Button.Size =
		Size

	Button.BackgroundColor3 =
		COLOR_RAISED

	Button.BackgroundTransparency =
		0.10

	Button.BorderSizePixel =
		0

	Button.AutoButtonColor =
		false

	Button.Font =
		Enum.Font.GothamBold

	Button.TextSize =
		10

	Button.TextColor3 =
		COLOR_TEXT

	Button.Parent =
		Parent

	AddCorner(
		Button,
		4
	)

	AddStroke(
		Button,
		AccentColor,
		0.34,
		1
	)

	return Button
end

local function DecoratePanel(
	Frame,
	AccentColor
)

	Frame.BackgroundColor3 =
		COLOR_PANEL

	Frame.BackgroundTransparency =
		0.08

	Frame.BorderSizePixel =
		0

	AddCorner(
		Frame,
		6
	)

	AddStroke(
		Frame,
		COLOR_GOLD_DIM,
		0.34,
		1
	)

	local Accent =
		Instance.new("Frame")

	Accent.Size =
		UDim2.new(
			1,
			0,
			0,
			2
		)

	Accent.BackgroundColor3 =
		AccentColor

	Accent.BackgroundTransparency =
		0.04

	Accent.BorderSizePixel =
		0

	Accent.ZIndex =
		Frame.ZIndex + 1

	Accent.Parent =
		Frame
end

--==================================================
-- COMMON STATE
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

local function GetInteractionBlockReason()

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

--==================================================
-- WORLD RESOLUTION
--==================================================

local NPCCache = {}
local CollectAssetFolderCache = {}
local RuntimeMissionFolders = {}

-- Created only by this LocalScript while the game is running.
-- It does not exist in Studio edit mode and does not replicate to other players.
local RuntimeRoot =
	Instance.new("Folder")

RuntimeRoot.Name =
	"_MissionRuntimeLocal_"
	.. tostring(
		Player.UserId
	)

RuntimeRoot.Parent =
	workspace

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
		NPCCache[NPCId]

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

			NPCCache[NPCId] =
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

			NPCCache[NPCId] =
				Object

			return Object
		end
	end

	return nil
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

local function GetNPCAdornee(
	NPCId
)

	local Model =
		ResolveNPC(
			NPCId
		)

	if not Model then
		return nil
	end

	local Head =
		Model:
		FindFirstChild(
			"Head",
			true
		)

	if Head
		and Head:IsA("BasePart") then

		return Head
	end

	return GetModelRoot(
		Model
	)
end

local function GetNPCDistance(
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
		CollectAssetFolderCache[
	MissionId
	]

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

		CollectAssetFolderCache[
		MissionId
		] =
			Folder
	end

	return Folder
end

local function ResolveCollectRuntimeFolder(
	MissionId
)

	local Cached =
		RuntimeMissionFolders[
	MissionId
	]

	if Cached
		and Cached.Parent then

		return Cached
	end

	local Folder =
		RuntimeRoot:
		FindFirstChild(
			MissionId
		)

	if Folder then

		RuntimeMissionFolders[
		MissionId
		] =
			Folder
	end

	return Folder
end

local function GetObjectParts(
	Object
)

	local Parts = {}

	if Object:IsA("BasePart") then

		table.insert(
			Parts,
			Object
		)
	end

	for _, Descendant in ipairs(
		Object:GetDescendants()
		) do

		if Descendant:IsA("BasePart") then

			table.insert(
				Parts,
				Descendant
			)
		end
	end

	return Parts
end

local function GetObjectCenter(
	Object
)

	local Parts =
		GetObjectParts(
			Object
		)

	if #Parts <= 0 then
		return nil
	end

	local Center =
		Vector3.zero

	for _, Part in ipairs(
		Parts
		) do

		Center +=
			Part.Position
	end

	return Center / #Parts
end

local function GetObjectAdornee(
	Object
)

	if not Object then
		return nil
	end

	if Object:IsA("BasePart") then
		return Object
	end

	return Object:
		FindFirstChildWhichIsA(
			"BasePart",
			true
		)
end

--==================================================
-- CLIENT-LOCAL MISSION RUNTIME
--==================================================

local function PrepareRuntimeClone(
	Object,
	MissionId
)

	Object:SetAttribute(
		"MissionRuntimeClone",
		true
	)

	Object:SetAttribute(
		"MissionId",
		MissionId
	)

	Object:SetAttribute(
		"MissionObjectId",
		Object.Name
	)

	for _, Descendant in ipairs(
		Object:GetDescendants()
		) do

		if Descendant:IsA("BasePart") then

			Descendant.Anchored =
				true

			Descendant.CanCollide =
				false

			Descendant.CanTouch =
				false

			Descendant.CanQuery =
				false

			Descendant.AssemblyLinearVelocity =
				Vector3.zero

			Descendant.AssemblyAngularVelocity =
				Vector3.zero

		elseif Descendant:IsA("Script")
			or Descendant:IsA("LocalScript") then

			Descendant:Destroy()
		end
	end

	if Object:IsA("BasePart") then

		Object.Anchored =
			true

		Object.CanCollide =
			false

		Object.CanTouch =
			false

		Object.CanQuery =
			false

		Object.AssemblyLinearVelocity =
			Vector3.zero

		Object.AssemblyAngularVelocity =
			Vector3.zero
	end
end

local function DestroyCollectRuntime(
	MissionId
)

	local Folder =
		ResolveCollectRuntimeFolder(
			MissionId
		)

	if Folder then
		Folder:Destroy()
	end

	RuntimeMissionFolders[
	MissionId
	] =
		nil
end

local function SpawnCollectRuntime(
	MissionId
)

	local Existing =
		ResolveCollectRuntimeFolder(
			MissionId
		)

	if Existing then
		return Existing
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

	local SourceFolder =
		ResolveCollectAssetFolder(
			MissionId
		)

	if not SourceFolder then

		warn(
			"[MissionClient] Missing mission AssetPath:",
			MissionId
		)

		return nil
	end

	local RuntimeFolder =
		Instance.new("Folder")

	RuntimeFolder.Name =
		MissionId

	RuntimeFolder:SetAttribute(
		"MissionRuntime",
		true
	)

	RuntimeFolder:SetAttribute(
		"MissionId",
		MissionId
	)

	RuntimeFolder.Parent =
		RuntimeRoot

	RuntimeMissionFolders[
	MissionId
	] =
		RuntimeFolder

	for _, Template in ipairs(
		SourceFolder:GetChildren()
		) do

		local Success,
			Clone =
			pcall(
				function()

					return Template:Clone()
				end
			)

		if Success
			and Clone then

			PrepareRuntimeClone(
				Clone,
				MissionId
			)

			Clone.Parent =
				RuntimeFolder

		else

			warn(
				"[MissionClient] Failed to clone mission asset:",
				MissionId,
				Template.Name
			)
		end
	end

	return RuntimeFolder
end

local function DestroyRuntimeObject(
	MissionId,
	ObjectId
)

	local Folder =
		ResolveCollectRuntimeFolder(
			MissionId
		)

	if not Folder then
		return
	end

	local Object =
		Folder:
		FindFirstChild(
			ObjectId
		)

	if Object then
		Object:Destroy()
	end
end

--==================================================
-- GUI
--==================================================

local OldGUI =
	PlayerGui:
	FindFirstChild(
		"MissionGUI"
	)

if OldGUI then
	OldGUI:Destroy()
end

local GUI =
	Instance.new("ScreenGui")

GUI.Name =
	"MissionGUI"

GUI.ResetOnSpawn =
	false

GUI.IgnoreGuiInset =
	true

GUI.DisplayOrder =
	72

GUI.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

GUI.Parent =
	PlayerGui

-- Dialogue
local Dialogue =
	Instance.new("Frame")

Dialogue.Name =
	"Dialogue"

Dialogue.AnchorPoint =
	Vector2.new(
		0.5,
		1
	)

Dialogue.Size =
	UDim2.fromOffset(
		560,
		118
	)

Dialogue.Position =
	UDim2.new(
		0.5,
		0,
		1,
		-82
	)

Dialogue.Visible =
	false

Dialogue.ZIndex =
	20

Dialogue.Parent =
	GUI

DecoratePanel(
	Dialogue,
	COLOR_GOLD
)

local DialogueName =
	CreateLabel(
		Dialogue,
		"Name",
		"NPC",
		UDim2.fromOffset(
			16,
			10
		),
		UDim2.fromOffset(
			180,
			18
		),
		Enum.Font.GothamBold,
		11,
		COLOR_GOLD,
		Enum.TextXAlignment.Left
	)

DialogueName.ZIndex =
	21

local DialogueText =
	CreateLabel(
		Dialogue,
		"DialogueText",
		"",
		UDim2.fromOffset(
			16,
			32
		),
		UDim2.new(
			1,
			-32,
			0,
			48
		),
		Enum.Font.Gotham,
		13,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

DialogueText.TextYAlignment =
	Enum.TextYAlignment.Top

DialogueText.ZIndex =
	21

local ContinueButton =
	CreateButton(
		Dialogue,
		"Continue",
		"CONTINUE",
		UDim2.new(
			1,
			-126,
			1,
			-34
		),
		UDim2.fromOffset(
			110,
			24
		),
		COLOR_GOLD
	)

ContinueButton.ZIndex =
	22

-- Offer
local MissionOffer =
	Instance.new("Frame")

MissionOffer.Name =
	"MissionOffer"

MissionOffer.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

MissionOffer.Size =
	UDim2.fromOffset(
		380,
		190
	)

MissionOffer.Position =
	UDim2.fromScale(
		0.5,
		0.52
	)

MissionOffer.Visible =
	false

MissionOffer.ZIndex =
	20

MissionOffer.Parent =
	GUI

DecoratePanel(
	MissionOffer,
	COLOR_GOLD
)

local OfferTitle =
	CreateLabel(
		MissionOffer,
		"Title",
		"MISSION",
		UDim2.fromOffset(
			16,
			11
		),
		UDim2.new(
			1,
			-48,
			0,
			22
		),
		Enum.Font.GothamBold,
		13,
		COLOR_GOLD,
		Enum.TextXAlignment.Left
	)

OfferTitle.ZIndex =
	21

local CloseOffer =
	CreateButton(
		MissionOffer,
		"Close",
		"×",
		UDim2.new(
			1,
			-36,
			0,
			8
		),
		UDim2.fromOffset(
			26,
			26
		),
		COLOR_GOLD_DIM
	)

CloseOffer.TextSize =
	16

CloseOffer.ZIndex =
	22

local OfferDescription =
	CreateLabel(
		MissionOffer,
		"Description",
		"",
		UDim2.fromOffset(
			16,
			42
		),
		UDim2.new(
			1,
			-32,
			0,
			42
		),
		Enum.Font.Gotham,
		11,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

OfferDescription.TextYAlignment =
	Enum.TextYAlignment.Top

OfferDescription.ZIndex =
	21

local ObjectivePill =
	Instance.new("Frame")

ObjectivePill.Position =
	UDim2.fromOffset(
		16,
		94
	)

ObjectivePill.Size =
	UDim2.fromOffset(
		165,
		30
	)

ObjectivePill.BackgroundColor3 =
	COLOR_RAISED

ObjectivePill.BackgroundTransparency =
	0.12

ObjectivePill.BorderSizePixel =
	0

ObjectivePill.ZIndex =
	21

ObjectivePill.Parent =
	MissionOffer

AddCorner(
	ObjectivePill,
	4
)

local ObjectiveText =
	CreateLabel(
		ObjectivePill,
		"Objective",
		"OBJECTIVE  0 / 0",
		UDim2.fromOffset(
			9,
			0
		),
		UDim2.new(
			1,
			-18,
			1,
			0
		),
		Enum.Font.GothamMedium,
		9,
		COLOR_TEXT_DIM,
		Enum.TextXAlignment.Left
	)

ObjectiveText.ZIndex =
	22

local RewardPill =
	Instance.new("Frame")

RewardPill.Position =
	UDim2.fromOffset(
		191,
		94
	)

RewardPill.Size =
	UDim2.fromOffset(
		105,
		30
	)

RewardPill.BackgroundColor3 =
	COLOR_RAISED

RewardPill.BackgroundTransparency =
	0.12

RewardPill.BorderSizePixel =
	0

RewardPill.ZIndex =
	21

RewardPill.Parent =
	MissionOffer

AddCorner(
	RewardPill,
	4
)

local RewardIcon =
	Instance.new("ImageLabel")

RewardIcon.BackgroundTransparency =
	1

RewardIcon.Position =
	UDim2.fromOffset(
		8,
		5
	)

RewardIcon.Size =
	UDim2.fromOffset(
		20,
		20
	)

RewardIcon.Image =
	RYO_ICON

RewardIcon.ScaleType =
	Enum.ScaleType.Fit

RewardIcon.ZIndex =
	22

RewardIcon.Parent =
	RewardPill

local RewardText =
	CreateLabel(
		RewardPill,
		"Reward",
		"0 RYŌ",
		UDim2.fromOffset(
			32,
			0
		),
		UDim2.new(
			1,
			-38,
			1,
			0
		),
		Enum.Font.GothamBold,
		9,
		COLOR_GOLD,
		Enum.TextXAlignment.Left
	)

RewardText.ZIndex =
	22

local AcceptButton =
	CreateButton(
		MissionOffer,
		"Accept",
		"ACCEPT",
		UDim2.new(
			1,
			-126,
			1,
			-42
		),
		UDim2.fromOffset(
			110,
			28
		),
		COLOR_GOLD
	)

AcceptButton.ZIndex =
	22

-- Active mission
local ActiveDialog =
	Instance.new("Frame")

ActiveDialog.Name =
	"ActiveMission"

ActiveDialog.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

ActiveDialog.Size =
	UDim2.fromOffset(
		360,
		158
	)

ActiveDialog.Position =
	UDim2.fromScale(
		0.5,
		0.52
	)

ActiveDialog.Visible =
	false

ActiveDialog.ZIndex =
	40

ActiveDialog.Parent =
	GUI

DecoratePanel(
	ActiveDialog,
	COLOR_GOLD
)

local ActiveTitle =
	CreateLabel(
		ActiveDialog,
		"Title",
		"MISSION IN PROGRESS",
		UDim2.fromOffset(
			16,
			11
		),
		UDim2.new(
			1,
			-32,
			0,
			20
		),
		Enum.Font.GothamBold,
		12,
		COLOR_GOLD,
		Enum.TextXAlignment.Left
	)

ActiveTitle.ZIndex =
	41

local ActiveDescription =
	CreateLabel(
		ActiveDialog,
		"Description",
		"",
		UDim2.fromOffset(
			16,
			39
		),
		UDim2.new(
			1,
			-32,
			0,
			38
		),
		Enum.Font.Gotham,
		10,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

ActiveDescription.TextYAlignment =
	Enum.TextYAlignment.Top

ActiveDescription.ZIndex =
	41

local ContinueMission =
	CreateButton(
		ActiveDialog,
		"Continue",
		"CONTINUE",
		UDim2.fromOffset(
			16,
			108
		),
		UDim2.fromOffset(
			150,
			30
		),
		COLOR_GOLD
	)

ContinueMission.ZIndex =
	42

local AbandonButton =
	CreateButton(
		ActiveDialog,
		"Abandon",
		"ABANDON",
		UDim2.new(
			1,
			-166,
			0,
			108
		),
		UDim2.fromOffset(
			150,
			30
		),
		COLOR_RED
	)

AbandonButton.TextColor3 =
	COLOR_RED

AbandonButton.ZIndex =
	42

-- Confirm abandon
local ConfirmDialog =
	Instance.new("Frame")

ConfirmDialog.Name =
	"ConfirmAbandon"

ConfirmDialog.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

ConfirmDialog.Size =
	UDim2.fromOffset(
		340,
		150
	)

ConfirmDialog.Position =
	UDim2.fromScale(
		0.5,
		0.52
	)

ConfirmDialog.Visible =
	false

ConfirmDialog.ZIndex =
	50

ConfirmDialog.Parent =
	GUI

DecoratePanel(
	ConfirmDialog,
	COLOR_RED
)

local ConfirmTitle =
	CreateLabel(
		ConfirmDialog,
		"Title",
		"ABANDON MISSION?",
		UDim2.fromOffset(
			16,
			12
		),
		UDim2.new(
			1,
			-32,
			0,
			20
		),
		Enum.Font.GothamBold,
		12,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

ConfirmTitle.ZIndex =
	51

local ConfirmDescription =
	CreateLabel(
		ConfirmDialog,
		"Description",
		"Current mission progress will be lost.",
		UDim2.fromOffset(
			16,
			43
		),
		UDim2.new(
			1,
			-32,
			0,
			34
		),
		Enum.Font.Gotham,
		10,
		COLOR_TEXT_DIM,
		Enum.TextXAlignment.Left
	)

ConfirmDescription.TextYAlignment =
	Enum.TextYAlignment.Top

ConfirmDescription.ZIndex =
	51

local ConfirmAbandon =
	CreateButton(
		ConfirmDialog,
		"Confirm",
		"ABANDON",
		UDim2.fromOffset(
			16,
			103
		),
		UDim2.fromOffset(
			146,
			28
		),
		COLOR_RED
	)

ConfirmAbandon.TextColor3 =
	COLOR_RED

ConfirmAbandon.ZIndex =
	52

local CancelAbandon =
	CreateButton(
		ConfirmDialog,
		"Cancel",
		"CANCEL",
		UDim2.new(
			1,
			-162,
			0,
			103
		),
		UDim2.fromOffset(
			146,
			28
		),
		COLOR_GOLD_DIM
	)

CancelAbandon.ZIndex =
	52

-- Tracker
local MissionTracker =
	Instance.new("Frame")

MissionTracker.Name =
	"MissionTracker"

MissionTracker.AnchorPoint =
	Vector2.new(
		1,
		0
	)

MissionTracker.Position =
	UDim2.new(
		1,
		-22,
		0,
		76
	)

MissionTracker.Size =
	UDim2.fromOffset(
		238,
		68
	)

MissionTracker.BackgroundColor3 =
	COLOR_PANEL

MissionTracker.BackgroundTransparency =
	0.18

MissionTracker.BorderSizePixel =
	0

MissionTracker.Visible =
	false

MissionTracker.ZIndex =
	10

MissionTracker.Parent =
	GUI

AddCorner(
	MissionTracker,
	5
)

AddStroke(
	MissionTracker,
	COLOR_GOLD_DIM,
	0.48,
	1
)

local TrackerAccent =
	Instance.new("Frame")

TrackerAccent.Size =
	UDim2.new(
		0,
		3,
		1,
		0
	)

TrackerAccent.BackgroundColor3 =
	COLOR_RED

TrackerAccent.BackgroundTransparency =
	0.08

TrackerAccent.BorderSizePixel =
	0

TrackerAccent.ZIndex =
	11

TrackerAccent.Parent =
	MissionTracker

AddCorner(
	TrackerAccent,
	4
)

local TrackerTitle =
	CreateLabel(
		MissionTracker,
		"Title",
		"MISSION",
		UDim2.fromOffset(
			12,
			6
		),
		UDim2.new(
			1,
			-52,
			0,
			17
		),
		Enum.Font.GothamBold,
		9,
		COLOR_GOLD,
		Enum.TextXAlignment.Left
	)

TrackerTitle.ZIndex =
	11

local TrackerAbandonButton =
	CreateButton(
		MissionTracker,
		"AbandonMission",
		"×",
		UDim2.new(
			1,
			-31,
			0,
			6
		),
		UDim2.fromOffset(
			21,
			21
		),
		COLOR_RED
	)

TrackerAbandonButton.TextSize =
	14

TrackerAbandonButton.TextColor3 =
	COLOR_TEXT_DIM

TrackerAbandonButton.BackgroundTransparency =
	0.35

TrackerAbandonButton.ZIndex =
	13

local TrackerProgress =
	CreateLabel(
		MissionTracker,
		"Progress",
		"0 / 0",
		UDim2.fromOffset(
			12,
			24
		),
		UDim2.new(
			1,
			-24,
			0,
			17
		),
		Enum.Font.GothamMedium,
		9,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

TrackerProgress.ZIndex =
	11

local TrackerBar =
	Instance.new("Frame")

TrackerBar.Position =
	UDim2.fromOffset(
		12,
		49
	)

TrackerBar.Size =
	UDim2.new(
		1,
		-24,
		0,
		5
	)

TrackerBar.BackgroundColor3 =
	COLOR_RAISED

TrackerBar.BackgroundTransparency =
	0.10

TrackerBar.BorderSizePixel =
	0

TrackerBar.ZIndex =
	11

TrackerBar.Parent =
	MissionTracker

AddCorner(
	TrackerBar,
	3
)

local TrackerFill =
	Instance.new("Frame")

TrackerFill.Size =
	UDim2.fromScale(
		0,
		1
	)

TrackerFill.BackgroundColor3 =
	COLOR_GOLD

TrackerFill.BorderSizePixel =
	0

TrackerFill.ZIndex =
	12

TrackerFill.Parent =
	TrackerBar

AddCorner(
	TrackerFill,
	3
)

--==================================================
-- MODAL STATE
--==================================================

local CurrentDialogueNPCId =
	nil

local CurrentDialogueMissionId =
	nil

local CurrentDialogueMode =
	""

local DialogueLines = {}

local CurrentLine =
	1

local AbandonConfirmReturnToActiveDialog =
	false

local function AnyModalOpen()

	return Dialogue.Visible
		or MissionOffer.Visible
		or ActiveDialog.Visible
		or ConfirmDialog.Visible
end

local function SyncMissionUIOpen()

	Player:SetAttribute(
		"MissionUIOpen",
		AnyModalOpen()
	)
end

local function CloseMissionWindows(
	NotifyServer
)

	Dialogue.Visible =
		false

	MissionOffer.Visible =
		false

	ActiveDialog.Visible =
		false

	ConfirmDialog.Visible =
		false

	CurrentDialogueNPCId =
		nil

	CurrentDialogueMissionId =
		nil

	CurrentDialogueMode =
		""

	DialogueLines =
		{}

	CurrentLine =
		1

	SyncMissionUIOpen()

	if NotifyServer == true then

		EndDialogueSession:FireServer()
	end
end

for _, Window in ipairs({
	Dialogue,
	MissionOffer,
	ActiveDialog,
	ConfirmDialog,
	}) do

	Window:GetPropertyChangedSignal(
		"Visible"
	):Connect(
		SyncMissionUIOpen
	)
end

--==================================================
-- ACTIVE MISSION / TRACKER
--==================================================

local function GetActiveMission()

	local Active =
		Player:GetAttribute(
			"MissionActive"
		) == true

	local MissionId =
		Player:GetAttribute(
			"ActiveMissionId"
		)

	if not Active
		or typeof(MissionId) ~= "string"
		or MissionId == "" then

		return nil, nil
	end

	return MissionId,
		MissionDefinitions.GetMission(
			MissionId
		)
end

local function OpenAbandonConfirmation()

	local MissionId,
		Definition =
		GetActiveMission()

	if not MissionId
		or not Definition then

		return
	end

	AbandonConfirmReturnToActiveDialog =
		ActiveDialog.Visible

	Dialogue.Visible =
		false

	MissionOffer.Visible =
		false

	ActiveDialog.Visible =
		false

	ConfirmDialog.Visible =
		true

	ConfirmTitle.Text =
		"ABANDON MISSION?"

	ConfirmDescription.Text =
		"Are you sure you want to abandon the current mission? You will lose all progress."

	SyncMissionUIOpen()
end

local function RefreshTracker()

	local MissionId,
		Definition =
		GetActiveMission()

	if not MissionId
		or not Definition then

		MissionTracker.Visible =
			false

		if ConfirmDialog.Visible then

			ConfirmDialog.Visible =
				false
		end

		AbandonConfirmReturnToActiveDialog =
			false

		return
	end

	local Progress =
		tonumber(
			Player:GetAttribute(
				"MissionProgress"
			)
		) or 0

	local Required =
		tonumber(
			Player:GetAttribute(
				"MissionRequired"
			)
		) or 0

	local Objective =
		Definition.Objective or {}

	TrackerTitle.Text =
		Definition.TrackerTitle
		or Definition.Title
		or MissionId

	TrackerProgress.Text =
		tostring(
			Objective.TrackerLabel
			or "PROGRESS"
		)
		.. "  "
		.. tostring(Progress)
		.. " / "
		.. tostring(Required)

	local Ratio =
		if Required > 0
		then math.clamp(
			Progress / Required,
			0,
			1
		)
		else 0

	TrackerFill.Size =
		UDim2.fromScale(
			Ratio,
			1
		)

	MissionTracker.Visible =
		Player:GetAttribute(
			"InventoryOpen"
		) ~= true
		and not AnyModalOpen()
end

local function FillOffer(
	MissionId
)

	local Definition =
		MissionDefinitions.GetMission(
			MissionId
		)

	if not Definition then
		return
	end

	local Objective =
		Definition.Objective or {}

	local Rewards =
		Definition.Rewards or {}

	OfferTitle.Text =
		Definition.Title
		or MissionId

	OfferDescription.Text =
		MissionDefinitions.FormatText(
			Definition.Description or "",
			MissionId
		)

	ObjectiveText.Text =
		"OBJECTIVE  0 / "
		.. tostring(
			Objective.Required or 0
		)

	RewardText.Text =
		tostring(
			Rewards.Ryo or 0
		)
		.. " RYŌ"
end

--==================================================
-- DIALOGUE
--==================================================

local function UpdateDialogue()

	if CurrentLine >
		#DialogueLines then

		Dialogue.Visible =
			false

		if CurrentDialogueMode == "Offer"
			and CurrentDialogueMissionId then

			FillOffer(
				CurrentDialogueMissionId
			)

			MissionOffer.Visible =
				true

		else

			CloseMissionWindows(
				true
			)
		end

		return
	end

	DialogueText.Text =
		DialogueLines[CurrentLine]
end

ContinueButton.MouseButton1Click:
	Connect(
		function()

			CurrentLine +=
			1

			UpdateDialogue()
		end
	)

CloseOffer.MouseButton1Click:
	Connect(
		function()

			CloseMissionWindows(
				true
			)
		end
	)

AcceptButton.MouseButton1Click:
	Connect(
		function()

			if not CurrentDialogueMissionId then
				return
			end

			AcceptMission:FireServer(
				CurrentDialogueMissionId
			)
		end
	)

ContinueMission.MouseButton1Click:
	Connect(
		function()

			CloseMissionWindows(
				true
			)
		end
	)

TrackerAbandonButton.MouseButton1Click:
	Connect(
		function()

			OpenAbandonConfirmation()
		end
	)

AbandonButton.MouseButton1Click:
	Connect(
		function()

			OpenAbandonConfirmation()
		end
	)

CancelAbandon.MouseButton1Click:
	Connect(
		function()

			ConfirmDialog.Visible =
			false

			if AbandonConfirmReturnToActiveDialog then

				ActiveDialog.Visible =
				true
			end

			AbandonConfirmReturnToActiveDialog =
			false

			RefreshTracker()
		end
	)

ConfirmAbandon.MouseButton1Click:
	Connect(
		function()

			ConfirmDialog.Visible =
			false

			AbandonConfirmReturnToActiveDialog =
			false

			AbandonMission:FireServer()

			RefreshTracker()
		end
	)

OpenMissionDialogue.OnClientEvent:
	Connect(
		function(
			NPCId,
			MissionId,
			Mode
		)

			if typeof(NPCId) ~= "string"
				or typeof(Mode) ~= "string" then

				return
			end

			CloseMissionWindows(
				false
			)

			local NPCDefinition =
			MissionDefinitions.GetNPC(
				NPCId
			)

			CurrentDialogueNPCId =
			NPCId

			CurrentDialogueMissionId =
			if typeof(MissionId) == "string"
			and MissionId ~= ""
			then MissionId
			else nil

			CurrentDialogueMode =
			Mode

			DialogueName.Text =
			if NPCDefinition
			then NPCDefinition.DisplayName
			or NPCId
			else NPCId

			if Mode == "Offer"
				and CurrentDialogueMissionId then

				local Definition =
				MissionDefinitions.GetMission(
					CurrentDialogueMissionId
				)

				if not Definition then
					return
				end

				DialogueLines = {}

				local Source =
				if typeof(
					Definition.Dialogue
				) == "table"
				and typeof(
					Definition.Dialogue.Offer
				) == "table"
				then Definition.Dialogue.Offer
				else {}

				for _, Line in ipairs(
					Source
					) do

					table.insert(
						DialogueLines,
						MissionDefinitions.FormatText(
							Line,
							CurrentDialogueMissionId
						)
					)
				end

				CurrentLine =
				1

				Dialogue.Visible =
				true

				UpdateDialogue()

			elseif Mode == "ActiveMission"
				and CurrentDialogueMissionId then

				local Definition =
				MissionDefinitions.GetMission(
					CurrentDialogueMissionId
				)

				ActiveTitle.Text =
				"MISSION IN PROGRESS"

				ActiveDescription.Text =
				if Definition
				and typeof(
					Definition.Dialogue
				) == "table"
				then Definition.Dialogue.Active
				or "You already have an active mission."
				else "You already have an active mission."

				ActiveDialog.Visible =
				true

			elseif Mode == "Busy"
				and CurrentDialogueMissionId then

				local Definition =
				MissionDefinitions.GetMission(
					CurrentDialogueMissionId
				)

				DialogueLines = {
					if Definition
					and typeof(
						Definition.Dialogue
					) == "table"
					then Definition.Dialogue.Busy
					or "Finish your current mission first."
					else "Finish your current mission first.",
				}

				CurrentLine =
				1

				Dialogue.Visible =
				true

				UpdateDialogue()

			else

				DialogueLines = {
					"I have nothing for you right now.",
				}

				CurrentLine =
				1

				Dialogue.Visible =
				true

				UpdateDialogue()
			end

			RefreshTracker()
		end
	)

CloseMissionDialogue.OnClientEvent:
	Connect(
		function()

			CloseMissionWindows(
				false
			)

			RefreshTracker()
		end
	)

--==================================================
-- COLLECT PROMPT
--==================================================

local CollectPrompt =
	Instance.new("BillboardGui")

CollectPrompt.Name =
	"MissionCollectPrompt"

CollectPrompt.Size =
	UDim2.fromOffset(
		174,
		40
	)

CollectPrompt.StudsOffset =
	Vector3.new(
		0,
		2.35,
		0
	)

CollectPrompt.AlwaysOnTop =
	true

CollectPrompt.Enabled =
	false

CollectPrompt.Parent =
	GUI

local CollectPanel =
	Instance.new("Frame")

CollectPanel.Size =
	UDim2.fromScale(
		1,
		1
	)

CollectPanel.BackgroundColor3 =
	COLOR_PANEL

CollectPanel.BackgroundTransparency =
	0.46

CollectPanel.BorderSizePixel =
	0

CollectPanel.Parent =
	CollectPrompt

AddCorner(
	CollectPanel,
	6
)

AddStroke(
	CollectPanel,
	COLOR_GOLD,
	0.18,
	1
)

local CollectAccent =
	Instance.new("Frame")

CollectAccent.Size =
	UDim2.new(
		0,
		3,
		1,
		0
	)

CollectAccent.BackgroundColor3 =
	COLOR_GOLD

CollectAccent.BorderSizePixel =
	0

CollectAccent.Parent =
	CollectPanel

AddCorner(
	CollectAccent,
	5
)

local CollectKey =
	Instance.new("Frame")

CollectKey.Position =
	UDim2.fromOffset(
		10,
		7
	)

CollectKey.Size =
	UDim2.fromOffset(
		27,
		24
	)

CollectKey.BackgroundColor3 =
	COLOR_RAISED

CollectKey.BorderSizePixel =
	0

CollectKey.Parent =
	CollectPanel

AddCorner(
	CollectKey,
	4
)

AddStroke(
	CollectKey,
	COLOR_GOLD_DIM,
	0.30,
	1
)

CreateLabel(
	CollectKey,
	"Key",
	"E",
	UDim2.fromScale(
		0,
		0
	),
	UDim2.fromScale(
		1,
		1
	),
	Enum.Font.GothamBold,
	10,
	COLOR_GOLD,
	Enum.TextXAlignment.Center
)

local CollectAction =
	CreateLabel(
		CollectPanel,
		"Action",
		"HOLD  •  COLLECT",
		UDim2.fromOffset(
			46,
			4
		),
		UDim2.new(
			1,
			-56,
			0,
			20
		),
		Enum.Font.GothamBold,
		9,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

local CollectHint =
	CreateLabel(
		CollectPanel,
		"Hint",
		"KEEP E PRESSED",
		UDim2.fromOffset(
			46,
			20
		),
		UDim2.new(
			1,
			-56,
			0,
			12
		),
		Enum.Font.GothamMedium,
		7,
		COLOR_TEXT_DIM,
		Enum.TextXAlignment.Left
	)

local CollectBar =
	Instance.new("Frame")

CollectBar.Position =
	UDim2.new(
		0,
		7,
		1,
		-5
	)

CollectBar.Size =
	UDim2.new(
		1,
		-14,
		0,
		2
	)

CollectBar.BackgroundColor3 =
	COLOR_RAISED

CollectBar.BorderSizePixel =
	0

CollectBar.Parent =
	CollectPanel

local CollectFill =
	Instance.new("Frame")

CollectFill.Size =
	UDim2.fromScale(
		0,
		1
	)

CollectFill.BackgroundColor3 =
	COLOR_GOLD

CollectFill.BorderSizePixel =
	0

CollectFill.Parent =
	CollectBar

local CollectHighlight =
	Instance.new("Highlight")

CollectHighlight.Name =
	"MissionCollectHighlight"

CollectHighlight.DepthMode =
	Enum.HighlightDepthMode.AlwaysOnTop

CollectHighlight.FillTransparency =
	1

CollectHighlight.OutlineColor =
	COLOR_GOLD

CollectHighlight.OutlineTransparency =
	0.30

CollectHighlight.Enabled =
	false

CollectHighlight.Parent =
	workspace.CurrentCamera

local CurrentCollectMissionId =
	nil

local CurrentCollectTarget =
	nil

local CollectBound =
	false

local HoldingCollect =
	false

local CollectStartedAt =
	0

local CollectDuration =
	2

local CollectAnimationTrack =
	nil

local function StopCollectAnimation()

	if CollectAnimationTrack then

		pcall(
			function()

				local Definition =
					CurrentCollectMissionId
					and MissionDefinitions.GetMission(
						CurrentCollectMissionId
					)
					or nil

				local FadeTime =
					Definition
					and Definition.Objective
					and Definition.Objective.Animation
					and tonumber(
						Definition.Objective.Animation.FadeTime
					)
					or 0.08

				CollectAnimationTrack:Stop(
					FadeTime
				)
			end
		)

		CollectAnimationTrack =
			nil
	end
end

local function StartCollectAnimation()

	StopCollectAnimation()

	if not CurrentCollectMissionId then
		return
	end

	local Definition =
		MissionDefinitions.GetMission(
			CurrentCollectMissionId
		)

	if not Definition
		or typeof(
			Definition.Objective
		) ~= "table"
			or typeof(
				Definition.Objective.Animation
			) ~= "table" then

		return
	end

	local AnimationConfig =
		Definition.Objective.Animation

	local AnimationId =
		tonumber(
			AnimationConfig.Id
		) or 0

	if AnimationId <= 0 then
		return
	end

	local Character =
		Player.Character

	if not Character then
		return
	end

	local Humanoid =
		Character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not Humanoid then
		return
	end

	local Animator =
		Humanoid:
		FindFirstChildOfClass(
			"Animator"
		)

	if not Animator then

		Animator =
			Instance.new("Animator")

		Animator.Parent =
			Humanoid
	end

	local Animation =
		Instance.new("Animation")

	Animation.AnimationId =
		"rbxassetid://"
		.. tostring(
			AnimationId
		)

	local Success,
		Track =
		pcall(
			function()

				return Animator:
				LoadAnimation(
					Animation
				)
			end
		)

	Animation:Destroy()

	if not Success
		or not Track then

		return
	end

	CollectAnimationTrack =
		Track

	Track.Priority =
		Enum.AnimationPriority.Action

	Track.Looped =
		false

	Track:Play(
		tonumber(
			AnimationConfig.FadeTime
		) or 0.08,
		1,
		tonumber(
			AnimationConfig.Speed
		) or 1
	)
end

local function ResetCollectVisual()

	HoldingCollect =
		false

	CollectStartedAt =
		0

	CollectFill.Size =
		UDim2.fromScale(
			0,
			1
		)

	CollectAction.Text =
		"HOLD  •  COLLECT"

	CollectHint.Text =
		"KEEP E PRESSED"

	StopCollectAnimation()
end

local function CancelCollect(
	SendServer
)

	if not HoldingCollect then
		return
	end

	if SendServer
		and CurrentCollectMissionId
		and CurrentCollectTarget then

		CancelCollectObjective:FireServer(
			CurrentCollectMissionId,
			CurrentCollectTarget.Name
		)
	end

	ResetCollectVisual()
end

local function CollectContextAction(
	_ActionName,
	InputState,
	_InputObject
)

	if InputState ==
		Enum.UserInputState.Begin then

		if not CurrentCollectMissionId
			or not CurrentCollectTarget
			or GetInteractionBlockReason()
			or AnyModalOpen() then

			return Enum.ContextActionResult.Sink
		end

		local Definition =
			MissionDefinitions.GetMission(
				CurrentCollectMissionId
			)

		if not Definition then
			return Enum.ContextActionResult.Sink
		end

		HoldingCollect =
			true

		CollectStartedAt =
			time()

		CollectDuration =
			tonumber(
				Definition.Objective.HoldDuration
			) or 2

		CollectAction.Text =
			"COLLECTING..."

		CollectHint.Text =
			"RELEASE TO CANCEL"

		StartCollectAnimation()

		BeginCollectObjective:FireServer(
			CurrentCollectMissionId,
			CurrentCollectTarget.Name
		)

	elseif InputState ==
		Enum.UserInputState.End
		or InputState ==
		Enum.UserInputState.Cancel then

		CancelCollect(
			true
		)
	end

	return Enum.ContextActionResult.Sink
end

local function SetCollectBound(
	Bound
)

	if Bound == CollectBound then
		return
	end

	CollectBound =
		Bound

	if Bound then

		ContextActionService:
			BindActionAtPriority(
				"MissionCollectHoldE",
				CollectContextAction,
				false,
				COLLECT_CONTEXT_PRIORITY,
				Enum.KeyCode.E
			)

	else

		ContextActionService:
			UnbindAction(
				"MissionCollectHoldE"
			)
	end
end

local function SetCollectTarget(
	MissionId,
	Target
)

	if CurrentCollectMissionId == MissionId
		and CurrentCollectTarget == Target then

		return
	end

	if HoldingCollect then

		CancelCollect(
			true
		)
	end

	CurrentCollectMissionId =
		MissionId

	CurrentCollectTarget =
		Target

	local Adornee =
		GetObjectAdornee(
			Target
		)

	CollectPrompt.Adornee =
		Adornee

	CollectHighlight.Adornee =
		Target

	local Definition =
		MissionId
		and MissionDefinitions.GetMission(
			MissionId
		)
		or nil

	if Definition
		and Definition.Objective
		and Definition.Objective.Prompt then

		CollectAction.Text =
			Definition.Objective.Prompt.Action
			or "HOLD  •  COLLECT"

		CollectHint.Text =
			Definition.Objective.Prompt.Hint
			or "KEEP E PRESSED"

		CollectPrompt.MaxDistance =
			tonumber(
				Definition.Objective.Prompt.BillboardMaxDistance
			) or 20
	end

	CollectPrompt.Enabled =
		Adornee ~= nil

	CollectHighlight.Enabled =
		Target ~= nil

	SetCollectBound(
		CollectPrompt.Enabled
	)

	if not Target then
		ResetCollectVisual()
	end
end

local function FindNearestCollectTarget()

	local MissionId,
		Definition =
		GetActiveMission()

	if not MissionId
		or not Definition
		or typeof(
			Definition.Objective
		) ~= "table"
			or Definition.Objective.Type ~= "Collect"
			or AnyModalOpen()
			or GetInteractionBlockReason() then

		return nil, nil
	end

	local Folder =
		ResolveCollectRuntimeFolder(
			MissionId
		)

	local Character =
		Player.Character

	if not Folder
		or not Character then

		return nil, nil
	end

	local Root =
		Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not Root
		or not Root:IsA("BasePart") then

		return nil, nil
	end

	local MaxDistance =
		tonumber(
			Definition.Objective.InteractionDistance
		) or 8

	local Best =
		nil

	local BestDistance =
		MaxDistance

	for _, Object in ipairs(
		Folder:GetChildren()
		) do

		if Object:GetAttribute(
			"MissionCollectedLocal"
			) == true then

			continue
		end

		local Center =
			GetObjectCenter(
				Object
			)

		if not Center then
			continue
		end

		local Distance =
			(
				Root.Position
				- Center
			).Magnitude

		if Distance <= BestDistance then

			Best =
				Object

			BestDistance =
				Distance
		end
	end

	return MissionId, Best
end

CollectObjectiveState.OnClientEvent:
	Connect(
		function(
			State,
			MissionId,
			ObjectId,
			Value
		)

			if State == "Started" then

				CollectDuration =
				tonumber(Value)
				or CollectDuration

			elseif State == "Cancelled" then

				ResetCollectVisual()

			elseif State == "Completed" then

				ResetCollectVisual()

				if CurrentCollectMissionId ==
					MissionId
					and CurrentCollectTarget
					and CurrentCollectTarget.Name ==
					ObjectId then

					SetCollectTarget(
						nil,
						nil
					)
				end
			end
		end
	)

RunService.RenderStepped:
	Connect(
		function()

			if not HoldingCollect then
				return
			end

			local Ratio =
			math.clamp(
				(
					time()
					- CollectStartedAt
				) / math.max(
					0.01,
					CollectDuration
				),
				0,
				1
			)

			CollectFill.Size =
			UDim2.fromScale(
				Ratio,
				1
			)

			if Ratio >= 1 then

				CollectHint.Text =
				"FINISHING..."
			end
		end
	)

--==================================================
-- NPC PROMPT
--==================================================

local NPCPrompt =
	Instance.new("BillboardGui")

NPCPrompt.Name =
	"MissionNPCPrompt"

NPCPrompt.Size =
	UDim2.fromOffset(
		144,
		34
	)

NPCPrompt.StudsOffset =
	Vector3.new(
		0,
		1.35,
		0
	)

NPCPrompt.AlwaysOnTop =
	true

NPCPrompt.Enabled =
	false

NPCPrompt.Parent =
	GUI

local NPCPanel =
	Instance.new("Frame")

NPCPanel.Size =
	UDim2.fromScale(
		1,
		1
	)

NPCPanel.BackgroundColor3 =
	COLOR_PANEL

NPCPanel.BackgroundTransparency =
	0.46

NPCPanel.BorderSizePixel =
	0

NPCPanel.Parent =
	NPCPrompt

AddCorner(
	NPCPanel,
	6
)

AddStroke(
	NPCPanel,
	COLOR_GOLD,
	0.18,
	1
)

local NPCAccent =
	Instance.new("Frame")

NPCAccent.Size =
	UDim2.new(
		0,
		3,
		1,
		0
	)

NPCAccent.BackgroundColor3 =
	COLOR_GOLD

NPCAccent.BorderSizePixel =
	0

NPCAccent.Parent =
	NPCPanel

AddCorner(
	NPCAccent,
	5
)

local NPCKey =
	Instance.new("Frame")

NPCKey.Position =
	UDim2.fromOffset(
		8,
		6
	)

NPCKey.Size =
	UDim2.fromOffset(
		24,
		22
	)

NPCKey.BackgroundColor3 =
	COLOR_RAISED

NPCKey.BorderSizePixel =
	0

NPCKey.Parent =
	NPCPanel

AddCorner(
	NPCKey,
	4
)

AddStroke(
	NPCKey,
	COLOR_GOLD_DIM,
	0.30,
	1
)

CreateLabel(
	NPCKey,
	"Key",
	"E",
	UDim2.fromScale(
		0,
		0
	),
	UDim2.fromScale(
		1,
		1
	),
	Enum.Font.GothamBold,
	10,
	COLOR_GOLD,
	Enum.TextXAlignment.Center
)

local NPCAction =
	CreateLabel(
		NPCPanel,
		"Action",
		"INTERACT",
		UDim2.fromOffset(
			40,
			2
		),
		UDim2.new(
			1,
			-48,
			0,
			18
		),
		Enum.Font.GothamBold,
		9,
		COLOR_TEXT,
		Enum.TextXAlignment.Left
	)

local NPCHint =
	CreateLabel(
		NPCPanel,
		"Hint",
		"NPC • HOLD E",
		UDim2.fromOffset(
			40,
			17
		),
		UDim2.new(
			1,
			-48,
			0,
			11
		),
		Enum.Font.GothamMedium,
		7,
		COLOR_TEXT_DIM,
		Enum.TextXAlignment.Left
	)

local NPCBar =
	Instance.new("Frame")

NPCBar.Position =
	UDim2.new(
		0,
		7,
		1,
		-4
	)

NPCBar.Size =
	UDim2.new(
		1,
		-14,
		0,
		1
	)

NPCBar.BackgroundColor3 =
	COLOR_RAISED

NPCBar.BorderSizePixel =
	0

NPCBar.Parent =
	NPCPanel

local NPCFill =
	Instance.new("Frame")

NPCFill.Size =
	UDim2.fromScale(
		0,
		1
	)

NPCFill.BackgroundColor3 =
	COLOR_GOLD

NPCFill.BorderSizePixel =
	0

NPCFill.Parent =
	NPCBar

local CurrentNPCId =
	nil

local NPCBound =
	false

local HoldingNPC =
	false

local NPCStartedAt =
	0

local NPCDuration =
	0.45

local function ResetNPCVisual()

	HoldingNPC =
		false

	NPCStartedAt =
		0

	NPCFill.Size =
		UDim2.fromScale(
			0,
			1
		)

	local Definition =
		CurrentNPCId
		and MissionDefinitions.GetNPC(
			CurrentNPCId
		)
		or nil

	NPCAction.Text =
		if Definition
		and Definition.Prompt
		then Definition.Prompt.Action
		or "INTERACT"
		else "INTERACT"

	NPCHint.Text =
		if Definition
		and Definition.Prompt
		then Definition.Prompt.Hint
		or (
			Definition.DisplayName
			.. " • HOLD E"
		)
		else "NPC • HOLD E"
end

local function CancelNPCHold(
	SendServer
)

	if not HoldingNPC then
		return
	end

	if SendServer
		and CurrentNPCId then

		CancelNPCInteraction:FireServer(
			CurrentNPCId
		)
	end

	ResetNPCVisual()
end

local function NPCContextAction(
	_ActionName,
	InputState,
	_InputObject
)

	if InputState ==
		Enum.UserInputState.Begin then

		if not CurrentNPCId
			or CurrentCollectTarget ~= nil
			or AnyModalOpen()
			or GetInteractionBlockReason() then

			return Enum.ContextActionResult.Sink
		end

		local Definition =
			MissionDefinitions.GetNPC(
				CurrentNPCId
			)

		if not Definition then
			return Enum.ContextActionResult.Sink
		end

		HoldingNPC =
			true

		NPCStartedAt =
			time()

		NPCDuration =
			tonumber(
				Definition.HoldDuration
			) or 0.45

		NPCAction.Text =
			"INTERACTING"

		NPCHint.Text =
			"HOLD E"

		BeginNPCInteraction:FireServer(
			CurrentNPCId
		)

	elseif InputState ==
		Enum.UserInputState.End
		or InputState ==
		Enum.UserInputState.Cancel then

		CancelNPCHold(
			true
		)
	end

	return Enum.ContextActionResult.Sink
end

local function SetNPCBound(
	Bound
)

	if Bound == NPCBound then
		return
	end

	NPCBound =
		Bound

	if Bound then

		ContextActionService:
			BindActionAtPriority(
				"MissionNPCHoldE",
				NPCContextAction,
				false,
				NPC_CONTEXT_PRIORITY,
				Enum.KeyCode.E
			)

	else

		ContextActionService:
			UnbindAction(
				"MissionNPCHoldE"
			)
	end
end

local function SetNPC(
	NPCId
)

	if CurrentNPCId == NPCId then
		return
	end

	if HoldingNPC then

		CancelNPCHold(
			true
		)
	end

	CurrentNPCId =
		NPCId

	local Adornee =
		NPCId
		and GetNPCAdornee(
			NPCId
		)
		or nil

	NPCPrompt.Adornee =
		Adornee

	local Definition =
		NPCId
		and MissionDefinitions.GetNPC(
			NPCId
		)
		or nil

	if Definition
		and Definition.Prompt then

		NPCAction.Text =
			Definition.Prompt.Action
			or "INTERACT"

		NPCHint.Text =
			Definition.Prompt.Hint
			or (
				Definition.DisplayName
				.. " • HOLD E"
			)

		NPCPrompt.MaxDistance =
			tonumber(
				Definition.Prompt.BillboardMaxDistance
			) or 40
	end

	NPCPrompt.Enabled =
		Adornee ~= nil

	SetNPCBound(
		NPCPrompt.Enabled
	)

	if not NPCId then
		ResetNPCVisual()
	end
end

local function FindNearestNPC()

	if AnyModalOpen()
		or GetInteractionBlockReason()
		or CurrentCollectTarget ~= nil then

		return nil
	end

	local BestId =
		nil

	local BestDistance =
		math.huge

	for _, NPCId in ipairs(
		MissionDefinitions.GetAllNPCIds()
		) do

		local Definition =
			MissionDefinitions.GetNPC(
				NPCId
			)

		if not Definition then
			continue
		end

		local MaxDistance =
			(
				tonumber(
					Definition.InteractionDistance
				) or 0
			) + (
			Definition.Prompt
				and tonumber(
					Definition.Prompt.VisualTolerance
				)
				or 0
		)

		local Distance =
			GetNPCDistance(
				NPCId
			)

		if Distance <= MaxDistance
			and Distance <
			BestDistance then

			BestDistance =
				Distance

			BestId =
				NPCId
		end
	end

	return BestId
end

NPCInteractionState.OnClientEvent:
	Connect(
		function(
			State,
			NPCId,
			Value
		)

			if State == "Started" then

				NPCDuration =
				tonumber(Value)
				or NPCDuration

			elseif State == "Cancelled" then

				ResetNPCVisual()

			elseif State == "Completed" then

				ResetNPCVisual()

				NPCPrompt.Enabled =
				false

				SetNPCBound(
					false
				)
			end
		end
	)

RunService.RenderStepped:
	Connect(
		function()

			if not HoldingNPC then
				return
			end

			local Ratio =
			math.clamp(
				(
					time()
					- NPCStartedAt
				) / math.max(
					0.01,
					NPCDuration
				),
				0,
				1
			)

			NPCFill.Size =
			UDim2.fromScale(
				Ratio,
				1
			)
		end
	)

--==================================================
-- OBJECTIVE EVENTS
--==================================================

ObjectiveVisibility.OnClientEvent:
	Connect(
		function(
			Action,
			MissionId,
			ObjectId
		)

			if typeof(Action) ~= "string"
				or typeof(MissionId) ~= "string" then

				return
			end

			if Action == "ShowAll" then

				SpawnCollectRuntime(
					MissionId
				)

			elseif Action == "HideAll" then

				DestroyCollectRuntime(
					MissionId
				)

			elseif Action == "HideOne"
				and typeof(ObjectId) == "string" then

				DestroyRuntimeObject(
					MissionId,
					ObjectId
				)
			end
		end
	)

ObjectiveCollectEffect.OnClientEvent:
	Connect(
		function(
			MissionId,
			ObjectId
		)

			if typeof(MissionId) ~= "string"
				or typeof(ObjectId) ~= "string" then

				return
			end

			local Folder =
			ResolveCollectRuntimeFolder(
				MissionId
			)

			local Object =
			Folder
			and Folder:
			FindFirstChild(
				ObjectId
			)
			or nil

			if not Object then
				return
			end

			local Center =
			GetObjectCenter(
				Object
			)

			if not Center then
				return
			end

			-- The collected clone is destroyed immediately after this event.
			-- Keep the confirmation UI on an independent local anchor.
			local EffectAnchor =
			Instance.new("Part")

			EffectAnchor.Name =
			"MissionCollectEffectAnchor"

			EffectAnchor.Size =
			Vector3.new(
				0.1,
				0.1,
				0.1
			)

			EffectAnchor.CFrame =
			CFrame.new(
				Center
			)

			EffectAnchor.Anchored =
			true

			EffectAnchor.CanCollide =
			false

			EffectAnchor.CanTouch =
			false

			EffectAnchor.CanQuery =
			false

			EffectAnchor.Transparency =
			1

			EffectAnchor.Parent =
			RuntimeRoot

			local Billboard =
			Instance.new(
				"BillboardGui"
			)

			Billboard.Name =
			"MissionCollectedIndicator"

			Billboard.Size =
			UDim2.fromOffset(
				82,
				22
			)

			Billboard.StudsOffset =
			Vector3.new(
				0,
				2.5,
				0
			)

			Billboard.AlwaysOnTop =
			true

			Billboard.Adornee =
			EffectAnchor

			Billboard.Parent =
			EffectAnchor

			local Text =
			CreateLabel(
				Billboard,
				"Text",
				"COLLECTED",
				UDim2.fromScale(
					0,
					0
				),
				UDim2.fromScale(
					1,
					1
				),
				Enum.Font.GothamBold,
				9,
				COLOR_GOLD,
				Enum.TextXAlignment.Center
			)

			Text.TextStrokeTransparency =
			0.45

			Debris:AddItem(
				EffectAnchor,
				1.15
			)
		end
	)

--==================================================
-- COMPLETION VFX
--==================================================

local LastCompletionVFX =
	0

local function CreateCompletionEmitter(
	Parent,
	Lifetime,
	Speed,
	Spread,
	SizeStart,
	SizeEnd,
	Acceleration
)

	local Emitter =
		Instance.new("ParticleEmitter")

	Emitter.Enabled =
		false

	Emitter.Rate =
		0

	Emitter.Lifetime =
		Lifetime

	Emitter.Speed =
		Speed

	Emitter.SpreadAngle =
		Vector2.new(
			Spread,
			Spread
		)

	Emitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				SizeStart
			),
			NumberSequenceKeypoint.new(
				1,
				SizeEnd
			),
		})

	Emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.05
			),
			NumberSequenceKeypoint.new(
				0.75,
				0.10
			),
			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	Emitter.Acceleration =
		Acceleration

	Emitter.LightEmission =
		1

	Emitter.Shape =
		Enum.ParticleEmitterShape.Sphere

	Emitter.Texture =
		"rbxasset://textures/particles/sparkles_main.dds"

	Emitter.Parent =
		Parent

	return Emitter
end

local function PlayMissionCompletionVFX()

	if os.clock()
		- LastCompletionVFX <
			3 then

		return
	end

	LastCompletionVFX =
		os.clock()

	local Character =
		Player.Character

	if not Character then
		return
	end

	local Root =
		Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not Root
		or not Root:IsA("BasePart") then

		return
	end

	local Attachment =
		Instance.new("Attachment")

	Attachment.Name =
		"MissionCompletionVFX"

	Attachment.Parent =
		Root

	local Burst =
		CreateCompletionEmitter(
			Attachment,
			NumberRange.new(
				0.7,
				1.25
			),
			NumberRange.new(
				8,
				16
			),
			180,
			0.22,
			0.03,
			Vector3.new(
				0,
				-4,
				0
			)
		)

	Burst:Emit(
		38
	)

	local Gold =
		CreateCompletionEmitter(
			Attachment,
			NumberRange.new(
				0.8,
				1.35
			),
			NumberRange.new(
				5,
				11
			),
			90,
			0.15,
			0.015,
			Vector3.new(
				0,
				5,
				0
			)
		)

	Gold.Color =
		ColorSequence.new({
			ColorSequenceKeypoint.new(
				0,
				Color3.fromRGB(
					255,
					235,
					150
				)
			),
			ColorSequenceKeypoint.new(
				0.5,
				Color3.fromRGB(
					255,
					200,
					65
				)
			),
			ColorSequenceKeypoint.new(
				1,
				Color3.new(
					1,
					1,
					1
				)
			),
		})

	Gold:Emit(
		28
	)

	local Light =
		Instance.new("PointLight")

	Light.Color =
		Color3.fromRGB(
			255,
			215,
			110
		)

	Light.Brightness =
		6

	Light.Range =
		16

	Light.Shadows =
		false

	Light.Parent =
		Attachment

	TweenService:Create(
		Light,
		TweenInfo.new(
			0.45,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			Brightness = 0,
			Range = 0,
		}
	):Play()

	Debris:AddItem(
		Attachment,
		3
	)
end

MissionCompleted.OnClientEvent:
	Connect(
		function(
			MissionId
		)

			if typeof(MissionId) ~= "string" then
				return
			end

			local Definition =
			MissionDefinitions.GetMission(
				MissionId
			)

			local DelayTime =
			if Definition
			and typeof(
				Definition.Completion
			) == "table"
			then tonumber(
				Definition.Completion.VFXDelay
			) or 3
			else 3

			RefreshTracker()

			task.delay(
				DelayTime,
				function()

					if Player.Parent then

						PlayMissionCompletionVFX()
					end
				end
			)
		end
	)

--==================================================
-- TARGET SCAN
--==================================================

task.spawn(
	function()

		while GUI.Parent do

			local MissionId,
			CollectTarget =
				FindNearestCollectTarget()

			SetCollectTarget(
				MissionId,
				CollectTarget
			)

			if CollectTarget then

				SetNPC(
					nil
				)

			else

				SetNPC(
					FindNearestNPC()
				)
			end

			-- Local responsiveness only.
			-- Server separately owns the real dialogue authorization.
			if AnyModalOpen()
				and CurrentDialogueNPCId then

				local Definition =
					MissionDefinitions.GetNPC(
						CurrentDialogueNPCId
					)

				if Definition
					and GetNPCDistance(
						CurrentDialogueNPCId
					) >
					(
						tonumber(
							Definition.InteractionDistance
						) or 0
					) then

					CloseMissionWindows(
						false
					)
				end
			end

			RefreshTracker()

			task.wait(
				TARGET_SCAN_INTERVAL
			)
		end
	end
)

--==================================================
-- CHARACTER / INVENTORY COMPATIBILITY
--==================================================

local CharacterConnections = {}

local function DisconnectCharacter()

	for _, Connection in ipairs(
		CharacterConnections
		) do

		Connection:Disconnect()
	end

	table.clear(
		CharacterConnections
	)
end

local function CancelAllInteractions()

	if HoldingCollect then

		CancelCollect(
			true
		)
	end

	if HoldingNPC then

		CancelNPCHold(
			true
		)
	end

	SetCollectTarget(
		nil,
		nil
	)

	SetNPC(
		nil
	)
end

local function BindCharacter(
	Character
)

	DisconnectCharacter()

	for _, AttributeName in ipairs(
		BlockingAttributes
		) do

		table.insert(
			CharacterConnections,
			Character:
				GetAttributeChangedSignal(
					AttributeName
				):
				Connect(
					function()

						if GetInteractionBlockReason() then

							CancelAllInteractions()

							CloseMissionWindows(
								false
							)
						end
					end
				)
		)
	end

	for _, AttributeName in ipairs({
		"CombatMode",
		"CombatTagged",
		}) do

		table.insert(
			CharacterConnections,
			Character:
				GetAttributeChangedSignal(
					AttributeName
				):
				Connect(
					function()

						if GetInteractionBlockReason() then

							CancelAllInteractions()

							CloseMissionWindows(
								false
							)
						end
					end
				)
		)
	end
end

if Player.Character then

	BindCharacter(
		Player.Character
	)
end

Player.CharacterAdded:
	Connect(
		function(
			Character
		)

			CancelAllInteractions()

			CloseMissionWindows(
				false
			)

			BindCharacter(
				Character
			)
		end
	)

Player:GetAttributeChangedSignal(
	"InventoryOpen"
):Connect(
	function()

		if Player:GetAttribute(
			"InventoryOpen"
			) == true then

			CancelAllInteractions()

			CloseMissionWindows(
				false
			)
		end

		RefreshTracker()
	end
)

for _, AttributeName in ipairs({
	"MissionActive",
	"ActiveMissionId",
	"MissionProgress",
	"MissionRequired",
	"MissionRewardRyo",
	}) do

	Player:GetAttributeChangedSignal(
		AttributeName
	):Connect(
		RefreshTracker
	)
end

script.Destroying:
	Connect(
		function()

			Player:SetAttribute(
				"MissionUIOpen",
				false
			)

			CancelAllInteractions()

			SetCollectBound(
				false
			)

			SetNPCBound(
				false
			)

			StopCollectAnimation()

			if CollectHighlight then
				CollectHighlight:Destroy()
			end

			if RuntimeRoot
				and RuntimeRoot.Parent then

				RuntimeRoot:Destroy()
			end

			DisconnectCharacter()
		end
	)

--==================================================
-- INITIAL STATE
--==================================================

local Deadline =
	time() + 8

while Player:GetAttribute(
	"MissionSystemReady"
	) ~= true
		and time() < Deadline do

	task.wait(
		0.05
	)
end

local InitialMissionId,
	InitialDefinition =
	GetActiveMission()

if InitialMissionId
	and InitialDefinition
	and InitialDefinition.Objective
	and InitialDefinition.Objective.Type ==
	"Collect" then

	SpawnCollectRuntime(
		InitialMissionId
	)
end

SyncMissionUIOpen()
RefreshTracker()

print(
	"[MissionClient] READY v5.2.1"
		.. " | GenericFramework=ON"
		.. " | CompactHUD=ON"
		.. " | MissionAssets=ClientLocal"
		.. " | TrackerAbandon=ON"
		.. " | HoldE=ON"
)
