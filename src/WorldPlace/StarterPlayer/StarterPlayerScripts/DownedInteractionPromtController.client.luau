--!strict
-- DownedInteractionPromptController v3 - Grounded Freefall Aware Prompt
-- StarterPlayer > StarterPlayerScripts > DownedInteractionPromptController
--
-- VISUAL ONLY.
-- Does NOT send Carry/Execute requests and does NOT replace DownedController.
-- Your existing DownedController continues handling:
--   V = Carry
--   B = Execute
--
-- This script:
-- - Finds the nearest valid Downed player within the same 8-stud range as DownedServer v23.
-- - Shows a compact polished "V Carry | B Execute" prompt only while interaction is valid.
-- - Draws a client-only gold ring on the ground under the selected Downed target.
-- - Automatically hides everything when the target leaves range, is carried,
--   becomes airborne, starts recovering, is being executed, or the local player
--   cannot currently start an interaction.
-- - Creates ALL UI and ring visuals from code. No PNG/UI setup is required.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer


-- ============================================================
-- CONFIG
-- ============================================================

-- Must match DownedServer v23.
local INTERACTION_RANGE = 8

-- Target scan rate. Visual positioning still updates every rendered frame.
local TARGET_SCAN_INTERVAL = 0.06

-- Screen-space prompt placement relative to the Downed target.
local PROMPT_SCREEN_OFFSET = Vector2.new(42, 78)

-- Ring.
local RING_RADIUS = 3.45
local RING_HEIGHT_ABOVE_GROUND = 0.045
local RING_SEGMENTS = 32

local RING_CORE_WIDTH = 0.055
local RING_GLOW_WIDTH = 0.18

local RING_GROUND_RAY_START = 7
local RING_GROUND_RAY_LENGTH = 22

-- UI.
local PROMPT_WIDTH = 258
local PROMPT_HEIGHT = 46

local UI_FADE_TIME = 0.12

-- Visual palette.
local COLOR_PANEL = Color3.fromRGB(20, 18, 15)
local COLOR_PANEL_2 = Color3.fromRGB(31, 27, 21)
local COLOR_KEY = Color3.fromRGB(25, 24, 22)

local COLOR_GOLD = Color3.fromRGB(196, 150, 58)
local COLOR_GOLD_BRIGHT = Color3.fromRGB(232, 187, 83)

local COLOR_TEXT = Color3.fromRGB(242, 239, 230)
local COLOR_TEXT_DIM = Color3.fromRGB(211, 205, 191)


-- ============================================================
-- LOCAL CHARACTER
-- ============================================================

local localCharacter: Model? = nil
local localHumanoid: Humanoid? = nil
local localRoot: BasePart? = nil

local function bindLocalCharacter(character: Model)
	localCharacter = character

	local humanoid =
		character:WaitForChild("Humanoid") :: Humanoid

	local root =
		character:WaitForChild("HumanoidRootPart") :: BasePart

	localHumanoid = humanoid
	localRoot = root
end

if LOCAL_PLAYER.Character then
	task.spawn(
		bindLocalCharacter,
		LOCAL_PLAYER.Character
	)
end

LOCAL_PLAYER.CharacterAdded:Connect(
	function(character: Model)
		bindLocalCharacter(character)
	end
)


-- ============================================================
-- UI CREATION
-- ============================================================

local playerGui =
	LOCAL_PLAYER:WaitForChild("PlayerGui")

local oldGui =
	playerGui:FindFirstChild(
		"DownedInteractionPromptGui"
	)

if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DownedInteractionPromptGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 80
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui


local promptGroup = Instance.new("CanvasGroup")
promptGroup.Name = "PromptGroup"
promptGroup.AnchorPoint = Vector2.new(0.5, 0.5)
promptGroup.Size =
	UDim2.fromOffset(
		PROMPT_WIDTH,
		PROMPT_HEIGHT
	)

promptGroup.BackgroundTransparency = 1
promptGroup.GroupTransparency = 1
promptGroup.Visible = false
promptGroup.ZIndex = 20
promptGroup.Parent = screenGui


-- Shadow.
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position =
	UDim2.new(
		0.5,
		0,
		0.5,
		3
	)

shadow.Size =
	UDim2.new(
		1,
		6,
		1,
		6
	)

shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.56
shadow.BorderSizePixel = 0
shadow.ZIndex = 20
shadow.Parent = promptGroup

local shadowCorner =
	Instance.new("UICorner")

shadowCorner.CornerRadius =
	UDim.new(0, 9)

shadowCorner.Parent = shadow


-- Main panel.
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromScale(1, 1)
panel.BackgroundColor3 = COLOR_PANEL
panel.BackgroundTransparency = 0.50
panel.BorderSizePixel = 0
panel.ZIndex = 21
panel.Parent = promptGroup

local panelCorner =
	Instance.new("UICorner")

panelCorner.CornerRadius =
	UDim.new(0, 8)

panelCorner.Parent = panel

local panelStroke =
	Instance.new("UIStroke")

panelStroke.Color = COLOR_GOLD
panelStroke.Thickness = 1.15
panelStroke.Transparency = 0.17
panelStroke.ApplyStrokeMode =
	Enum.ApplyStrokeMode.Border

panelStroke.Parent = panel


-- Very subtle top sheen.
local sheen = Instance.new("Frame")
sheen.Name = "TopSheen"
sheen.Position = UDim2.fromOffset(7, 4)
sheen.Size =
	UDim2.new(
		1,
		-14,
		0,
		1
	)

sheen.BackgroundColor3 =
	COLOR_GOLD_BRIGHT

sheen.BackgroundTransparency = 0.62
sheen.BorderSizePixel = 0
sheen.ZIndex = 22
sheen.Parent = panel


-- Small accent caps.
local leftAccent = Instance.new("Frame")
leftAccent.Name = "LeftAccent"
leftAccent.AnchorPoint = Vector2.new(0, 0.5)
leftAccent.Position = UDim2.new(0, 0, 0.5, 0)
leftAccent.Size = UDim2.fromOffset(3, 24)
leftAccent.BackgroundColor3 = COLOR_GOLD_BRIGHT
leftAccent.BackgroundTransparency = 0.18
leftAccent.BorderSizePixel = 0
leftAccent.ZIndex = 23
leftAccent.Parent = panel

local leftAccentCorner =
	Instance.new("UICorner")

leftAccentCorner.CornerRadius =
	UDim.new(1, 0)

leftAccentCorner.Parent = leftAccent


local rightAccent = leftAccent:Clone()
rightAccent.Name = "RightAccent"
rightAccent.AnchorPoint = Vector2.new(1, 0.5)
rightAccent.Position = UDim2.new(1, 0, 0.5, 0)
rightAccent.Parent = panel


-- Center divider.
local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.AnchorPoint = Vector2.new(0.5, 0.5)
divider.Position = UDim2.fromScale(0.5, 0.5)
divider.Size = UDim2.fromOffset(1, 25)
divider.BackgroundColor3 = COLOR_GOLD
divider.BackgroundTransparency = 0.55
divider.BorderSizePixel = 0
divider.ZIndex = 23
divider.Parent = panel


local function createAction(
	name: string,
	keyText: string,
	actionText: string,
	xPosition: number
)
	local action = Instance.new("Frame")
	action.Name = name
	action.AnchorPoint = Vector2.new(0, 0.5)
	action.Position =
		UDim2.new(
			0,
			xPosition,
			0.5,
			0
		)

	action.Size =
		UDim2.fromOffset(
			116,
			34
		)

	action.BackgroundColor3 = COLOR_PANEL_2
	action.BackgroundTransparency = 1
	action.BorderSizePixel = 0
	action.ZIndex = 24
	action.Parent = panel


	local key = Instance.new("Frame")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.Position = UDim2.new(0, 5, 0.5, 0)
	key.Size = UDim2.fromOffset(30, 30)
	key.BackgroundColor3 = COLOR_KEY
	key.BackgroundTransparency = 0.02
	key.BorderSizePixel = 0
	key.ZIndex = 25
	key.Parent = action

	local keyCorner =
		Instance.new("UICorner")

	keyCorner.CornerRadius =
		UDim.new(0, 5)

	keyCorner.Parent = key

	local keyStroke =
		Instance.new("UIStroke")

	keyStroke.Color = COLOR_GOLD
	keyStroke.Thickness = 1
	keyStroke.Transparency = 0.12
	keyStroke.Parent = key


	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyText"
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = keyText
	keyLabel.TextColor3 = COLOR_TEXT
	keyLabel.TextSize = 17
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextXAlignment =
		Enum.TextXAlignment.Center

	keyLabel.TextYAlignment =
		Enum.TextYAlignment.Center

	keyLabel.ZIndex = 26
	keyLabel.Parent = key


	local actionLabel =
		Instance.new("TextLabel")

	actionLabel.Name = "ActionText"
	actionLabel.Position =
		UDim2.fromOffset(
			43,
			0
		)

	actionLabel.Size =
		UDim2.new(
			1,
			-43,
			1,
			0
		)

	actionLabel.BackgroundTransparency = 1
	actionLabel.Text = actionText
	actionLabel.TextColor3 = COLOR_TEXT_DIM
	actionLabel.TextSize = 15
	actionLabel.Font = Enum.Font.GothamMedium
	actionLabel.TextXAlignment =
		Enum.TextXAlignment.Left

	actionLabel.TextYAlignment =
		Enum.TextYAlignment.Center

	actionLabel.ZIndex = 25
	actionLabel.Parent = action

	return action
end


createAction(
	"Carry",
	"V",
	"Carry",
	7
)

createAction(
	"Execute",
	"B",
	"Execute",
	135
)


-- ============================================================
-- WORLD RING
-- ============================================================

local oldRing =
	Workspace:FindFirstChild(
		"__LocalDownedInteractionRing"
	)

if oldRing then
	oldRing:Destroy()
end


local ringAnchor = Instance.new("Part")
ringAnchor.Name = "__LocalDownedInteractionRing"
ringAnchor.Size = Vector3.new(0.15, 0.15, 0.15)
ringAnchor.Transparency = 1
ringAnchor.Anchored = true
ringAnchor.CanCollide = false
ringAnchor.CanTouch = false
ringAnchor.CanQuery = false
ringAnchor.CastShadow = false
ringAnchor.Locked = true
ringAnchor.Parent = Workspace


local ringCoreBeams: {Beam} = {}
local ringGlowBeams: {Beam} = {}
local ringAttachments: {Attachment} = {}


for index = 1, RING_SEGMENTS do
	local angle =
		((index - 1) / RING_SEGMENTS)
		* math.pi
		* 2

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"RingPoint_"
		.. tostring(index)

	attachment.Position =
		Vector3.new(
			math.cos(angle)
			* RING_RADIUS,
			0,
			math.sin(angle)
			* RING_RADIUS
		)

	attachment.Parent = ringAnchor

	table.insert(
		ringAttachments,
		attachment
	)
end


for index = 1, RING_SEGMENTS do
	local nextIndex =
		(index % RING_SEGMENTS)
		+ 1

	local core = Instance.new("Beam")
	core.Name =
		"RingCore_"
		.. tostring(index)

	core.Attachment0 =
		ringAttachments[index]

	core.Attachment1 =
		ringAttachments[nextIndex]

	core.Width0 = RING_CORE_WIDTH
	core.Width1 = RING_CORE_WIDTH

	core.Color =
		ColorSequence.new(
			COLOR_GOLD_BRIGHT
		)

	core.Transparency =
		NumberSequence.new(0.11)

	core.LightEmission = 0.9
	core.LightInfluence = 0
	core.FaceCamera = true
	core.Enabled = false
	core.Parent = ringAnchor

	table.insert(
		ringCoreBeams,
		core
	)


	local glow = Instance.new("Beam")
	glow.Name =
		"RingGlow_"
		.. tostring(index)

	glow.Attachment0 =
		ringAttachments[index]

	glow.Attachment1 =
		ringAttachments[nextIndex]

	glow.Width0 = RING_GLOW_WIDTH
	glow.Width1 = RING_GLOW_WIDTH

	glow.Color =
		ColorSequence.new(
			COLOR_GOLD
		)

	glow.Transparency =
		NumberSequence.new(0.76)

	glow.LightEmission = 0.75
	glow.LightInfluence = 0
	glow.FaceCamera = true
	glow.Enabled = false
	glow.Parent = ringAnchor

	table.insert(
		ringGlowBeams,
		glow
	)
end


local ringEnabled = false

local function setRingEnabled(
	enabled: boolean
)
	if ringEnabled == enabled then
		return
	end

	ringEnabled = enabled

	for _, beam in ipairs(
		ringCoreBeams
		) do
		beam.Enabled = enabled
	end

	for _, beam in ipairs(
		ringGlowBeams
		) do
		beam.Enabled = enabled
	end
end


-- ============================================================
-- GROUNDED INTERACTION CHECK
-- ============================================================

local INTERACTION_GROUND_RAY_DISTANCE = 4.5
local INTERACTION_MAX_GROUNDED_VERTICAL_SPEED = 7


local function makeInteractionGroundParams(
	localCharacterToIgnore: Model
): RaycastParams

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater = false
	params.RespectCanCollide = true

	local exclusions: {Instance} = {
		localCharacterToIgnore,
	}

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		local character =
			player.Character

		if character
			and character
			~= localCharacterToIgnore then

			table.insert(
				exclusions,
				character
			)
		end
	end

	params.FilterDescendantsInstances =
		exclusions

	return params
end


local function isLocalPlayerPhysicallyGrounded(
	character: Model,
	humanoid: Humanoid,
	root: BasePart
): boolean

	if humanoid.FloorMaterial
		~= Enum.Material.Air then

		return true
	end

	if math.abs(
		root.AssemblyLinearVelocity.Y
		) > INTERACTION_MAX_GROUNDED_VERTICAL_SPEED then

		return false
	end

	local result =
		workspace:Raycast(
			root.Position,
			Vector3.new(
				0,
				-INTERACTION_GROUND_RAY_DISTANCE,
				0
			),
			makeInteractionGroundParams(
				character
			)
		)

	return result ~= nil
end


-- ============================================================
-- TARGETING
-- ============================================================

local currentTargetPlayer: Player? = nil
local currentTargetCharacter: Model? = nil
local currentTargetRoot: BasePart? = nil

local function isTruthyAttribute(
	character: Model,
	name: string
): boolean
	return character:GetAttribute(name) == true
end


local function canLocalPlayerInteract(): boolean
	local character = localCharacter
	local humanoid = localHumanoid
	local root = localRoot

	if not character
		or not humanoid
		or not root
		or humanoid.Health <= 0 then

		return false
	end

	local state =
		humanoid:GetState()

	if state ==
		Enum.HumanoidStateType.Jumping then

		return false
	end

	if state ==
		Enum.HumanoidStateType.Swimming then

		return false
	end

	if state ==
		Enum.HumanoidStateType.Freefall
		and not isLocalPlayerPhysicallyGrounded(
			character,
			humanoid,
			root
		) then

		return false
	end

	-- While already carrying somebody, V is Drop.
	-- This prompt is specifically for starting Carry/Execute,
	-- so it is hidden.
	if isTruthyAttribute(
		character,
		"IsCarrying"
		) then
		return false
	end

	if isTruthyAttribute(
		character,
		"DownedActionLocked"
		)
			or isTruthyAttribute(
				character,
				"IsDowned"
			)
			or isTruthyAttribute(
				character,
				"IsCarried"
			)
			or isTruthyAttribute(
				character,
				"IsExecuting"
			)
			or isTruthyAttribute(
				character,
				"IsStunned"
			)
			or isTruthyAttribute(
				character,
				"IsDashing"
			)
			or isTruthyAttribute(
				character,
				"IsAttacking"
			)
			or isTruthyAttribute(
				character,
				"IsBlocking"
			)
			or isTruthyAttribute(
				character,
				"IsSprinting"
			)
			or isTruthyAttribute(
				character,
				"TreeJumpActive"
			)
			or isTruthyAttribute(
				character,
				"IsTreeJumping"
			)
			or isTruthyAttribute(
				character,
				"SurfaceJumping"
			) then

		return false
	end

	return true
end


local function isValidDownedTarget(
	player: Player
): (boolean, Model?, BasePart?)

	if player == LOCAL_PLAYER then
		return false, nil, nil
	end

	local character =
		player.Character

	if not character then
		return false, nil, nil
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid
		or not root
		or not root:IsA("BasePart")
		or humanoid.Health <= 0 then

		return false, nil, nil
	end

	if character:GetAttribute(
		"IsDowned"
		) ~= true then

		return false, nil, nil
	end

	if character:GetAttribute(
		"IsCarried"
		) == true
			or character:GetAttribute(
				"IsDownedAirborne"
			) == true
			or character:GetAttribute(
				"IsRecovering"
			) == true
			or character:GetAttribute(
				"IsBeingExecuted"
			) == true then

		return false, nil, nil
	end

	return true, character, root
end


local function findNearestTarget()
	if not canLocalPlayerInteract() then
		return nil, nil, nil
	end

	local requesterRoot = localRoot

	if not requesterRoot then
		return nil, nil, nil
	end

	local bestPlayer: Player? = nil
	local bestCharacter: Model? = nil
	local bestRoot: BasePart? = nil

	local bestDistance = math.huge

	for _, targetPlayer in ipairs(
		Players:GetPlayers()
		) do

		local valid,
			targetCharacter,
			targetRoot =
			isValidDownedTarget(
				targetPlayer
			)

		if valid
			and targetCharacter
			and targetRoot then

			local distance =
				(
					targetRoot.Position
					- requesterRoot.Position
				).Magnitude

			if distance <= INTERACTION_RANGE
				and distance < bestDistance then

				bestDistance = distance
				bestPlayer = targetPlayer
				bestCharacter = targetCharacter
				bestRoot = targetRoot
			end
		end
	end

	return bestPlayer,
		bestCharacter,
		bestRoot
end


-- ============================================================
-- PROMPT VISIBILITY
-- ============================================================

local visibilityVersion = 0
local promptShown = false
local activeTween: Tween? = nil

local function setPromptShown(
	shown: boolean
)
	if promptShown == shown then
		return
	end

	promptShown = shown
	visibilityVersion += 1

	local thisVersion =
		visibilityVersion

	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	if shown then
		promptGroup.Visible = true

		activeTween =
			TweenService:Create(
				promptGroup,
				TweenInfo.new(
					UI_FADE_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					GroupTransparency = 0
				}
			)

		activeTween:Play()
	else
		activeTween =
			TweenService:Create(
				promptGroup,
				TweenInfo.new(
					UI_FADE_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					GroupTransparency = 1
				}
			)

		activeTween:Play()

		activeTween.Completed:Connect(
			function()
				if visibilityVersion
					~= thisVersion then

					return
				end

				if not promptShown then
					promptGroup.Visible =
						false
				end
			end
		)
	end
end


local function clearTarget()
	currentTargetPlayer = nil
	currentTargetCharacter = nil
	currentTargetRoot = nil

	setPromptShown(false)
	setRingEnabled(false)
end


local function setTarget(
	player: Player?,
	character: Model?,
	root: BasePart?
)
	if not player
		or not character
		or not root then

		clearTarget()
		return
	end

	currentTargetPlayer = player
	currentTargetCharacter = character
	currentTargetRoot = root

	setRingEnabled(true)
end


-- ============================================================
-- GROUND / RING PLACEMENT
-- ============================================================

local function getCharacterExclusionList(): {Instance}
	local exclusions: {Instance} = {}

	for _, player in ipairs(
		Players:GetPlayers()
		) do

		local character =
			player.Character

		if character then
			table.insert(
				exclusions,
				character
			)
		end
	end

	return exclusions
end


local function getRingGroundCFrame(
	targetRoot: BasePart
): CFrame?
	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		getCharacterExclusionList()

	params.IgnoreWater = false

	local rayOrigin =
		targetRoot.Position
		+ Vector3.new(
			0,
			RING_GROUND_RAY_START,
			0
		)

	local result =
		Workspace:Raycast(
			rayOrigin,
			Vector3.new(
				0,
				-RING_GROUND_RAY_LENGTH,
				0
			),
			params
		)

	if not result then
		return nil
	end

	local up =
		result.Normal.Unit

	local reference =
		Vector3.xAxis

	if math.abs(
		up:Dot(reference)
		) > 0.94 then

		reference =
			Vector3.zAxis
	end

	local right =
		up:Cross(
			reference
		).Unit

	local back =
		right:Cross(
			up
		).Unit

	local position =
		result.Position
		+ up
		* RING_HEIGHT_ABOVE_GROUND

	return CFrame.fromMatrix(
		position,
		right,
		up,
		back
	)
end


-- ============================================================
-- UPDATE
-- ============================================================

local scanAccumulator = 0

RunService.RenderStepped:Connect(
	function(deltaTime: number)
		scanAccumulator += deltaTime

		if scanAccumulator
			>= TARGET_SCAN_INTERVAL then

			scanAccumulator = 0

			local targetPlayer,
			targetCharacter,
			targetRoot =
				findNearestTarget()

			setTarget(
				targetPlayer,
				targetCharacter,
				targetRoot
			)
		end


		local targetRoot =
			currentTargetRoot

		local targetCharacter =
			currentTargetCharacter

		if not targetRoot
			or not targetCharacter
			or not targetRoot.Parent
			or not targetCharacter.Parent then

			clearTarget()
			return
		end


		-- Revalidate between target scans so transitions such as
		-- Carry / Execute / Recovery hide immediately.
		local targetPlayer =
			currentTargetPlayer

		if not targetPlayer then
			clearTarget()
			return
		end

		local stillValid =
			select(
				1,
				isValidDownedTarget(
					targetPlayer
				)
			)

		if not stillValid
			or not canLocalPlayerInteract() then

			clearTarget()
			return
		end


		-- Ring.
		local ringCFrame =
			getRingGroundCFrame(
				targetRoot
			)

		if ringCFrame then
			ringAnchor.CFrame =
				ringCFrame

			setRingEnabled(true)
		else
			setRingEnabled(false)
		end


		-- Prompt projected next to the target.
		local camera =
			Workspace.CurrentCamera

		if not camera then
			setPromptShown(false)
			return
		end

		local viewportPoint,
		onScreen =
			camera:
			WorldToViewportPoint(
				targetRoot.Position
			)

		if not onScreen
			or viewportPoint.Z <= 0 then

			setPromptShown(false)
			return
		end

		local viewportSize =
			camera.ViewportSize

		local desiredX =
			viewportPoint.X
			+ PROMPT_SCREEN_OFFSET.X

		local desiredY =
			viewportPoint.Y
			+ PROMPT_SCREEN_OFFSET.Y

		local halfWidth =
			PROMPT_WIDTH * 0.5

		local halfHeight =
			PROMPT_HEIGHT * 0.5

		desiredX =
			math.clamp(
				desiredX,
				halfWidth + 8,
				viewportSize.X
				- halfWidth
				- 8
			)

		desiredY =
			math.clamp(
				desiredY,
				halfHeight + 8,
				viewportSize.Y
				- halfHeight
				- 8
			)

		promptGroup.Position =
			UDim2.fromOffset(
				desiredX,
				desiredY
			)

		setPromptShown(true)
	end
)


-- ============================================================
-- CLEANUP
-- ============================================================

script.Destroying:Connect(
	function()
		if activeTween then
			activeTween:Cancel()
		end

		if screenGui.Parent then
			screenGui:Destroy()
		end

		if ringAnchor.Parent then
			ringAnchor:Destroy()
		end
	end
)
