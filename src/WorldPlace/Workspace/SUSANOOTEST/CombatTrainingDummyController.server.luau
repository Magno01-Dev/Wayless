--!strict
-- CombatTrainingDummyController v2.2 PlayerLikeQA + StatusIndicators
--
-- INSTALL:
-- Place this Script DIRECTLY inside the R6 training dummy Model in Workspace.
--
-- PURPOSE
-- =======
-- Passive QA NPC that behaves like a player TARGET:
--
--   * normal idle while out of combat
--   * enters CombatMode when damaged
--   * combat idle while CombatMode is active
--   * generic hitstun on every health-damaging hit
--   * respects external Status_Stunned / IsStunned flags
--   * floating damage numbers ONLY on this dummy
--   * floating active-status indicators ONLY on this dummy
--   * effectively infinite health
--   * physics/knockback/Launcher compatible
--   * server network ownership
--   * ProjectileTarget + CombatDummy tags
--   * never attacks, blocks, parries, jumps or moves voluntarily
--
-- IMPORTANT
-- =========
-- This intentionally does NOT create/fake a Roblox Player.
-- CombatEntityService/DamageService should continue resolving this Model as
-- an NPC combat entity. The dummy mirrors player-facing CHARACTER STATE
-- attributes instead of pretending to be a Player instance.
--
-- ANIMATION CONFIGURATION
-- =======================
-- The controller resolves each animation in this order:
--
-- 1) String attribute on the dummy Model:
--      IdleAnimationId
--      CombatIdleAnimationId
--      HitstunAnimationId
--
-- 2) Animation object anywhere inside the dummy named:
--      IdleAnimation
--      CombatIdleAnimation
--      HitstunAnimation
--
-- 3) For NORMAL IDLE only, it can reuse the first idle Animation found
--    inside an existing "Animate" hierarchy before disabling that script.
--
-- Attribute values may be either:
--      "rbxassetid://123456789"
-- or:
--      "123456789"
--
-- No animation ID is invented by this script.

local CollectionService =
	game:GetService("CollectionService")

local TweenService =
	game:GetService("TweenService")

local Debris =
	game:GetService("Debris")

local character =
	script.Parent

if not character:IsA("Model") then
	error(
		"[CombatTrainingDummy] Script parent must be a Model"
	)
end

local humanoid =
	character:FindFirstChildOfClass(
		"Humanoid"
	)

if not humanoid then
	humanoid =
		character:WaitForChild(
			"Humanoid"
		) :: Humanoid
end

local root =
	character:FindFirstChild(
		"HumanoidRootPart"
	)

if not root
	or not root:IsA("BasePart") then

	error(
		"[CombatTrainingDummy] Missing HumanoidRootPart"
	)
end

local head =
	character:FindFirstChild(
		"Head"
	)

if not head
	or not head:IsA("BasePart") then

	error(
		"[CombatTrainingDummy] Missing Head"
	)
end

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local MAX_HEALTH =
	100_000

local DEFAULT_COMBAT_MODE_DURATION =
	8.0

local DEFAULT_HITSTUN_DURATION =
	0.28

local DAMAGE_NUMBER_LIFETIME =
	0.72

local DAMAGE_NUMBER_RISE =
	2.15

local DAMAGE_NUMBER_BASE_HEIGHT =
	2.55

local DAMAGE_NUMBER_X_SPREAD =
	0.72

local ANIMATION_FADE_TIME =
	0.10

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function readNumberAttribute(
	name: string,
	fallback: number,
	minimum: number,
	maximum: number
): number

	local value =
		character:GetAttribute(
			name
		)

	if typeof(value) ~= "number" then
		return fallback
	end

	return math.clamp(
		value,
		minimum,
		maximum
	)
end

local function normalizeAnimationId(
	value: any
): string?

	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed =
		string.gsub(
			value,
			"%s+",
			""
		)

	if trimmed == "" then
		return nil
	end

	if string.match(
		trimmed,
		"^rbxassetid://%d+$"
		) then
		return trimmed
	end

	if string.match(
		trimmed,
		"^%d+$"
		) then
		return "rbxassetid://"
			.. trimmed
	end

	return nil
end

local function findNamedAnimationId(
	name: string
): string?

	local instance =
		character:FindFirstChild(
			name,
			true
		)

	if instance
		and instance:IsA("Animation") then

		return normalizeAnimationId(
			instance.AnimationId
		)
	end

	return nil
end

local function findAnimateIdleId(): string?
	local animate =
		character:FindFirstChild(
			"Animate"
		)

	if not animate then
		return nil
	end

	local idleContainer =
		animate:FindFirstChild(
			"idle"
		)

	if idleContainer then
		for _, descendant in ipairs(
			idleContainer:GetDescendants()
			) do
			if descendant:IsA("Animation") then
				local id =
					normalizeAnimationId(
						descendant.AnimationId
					)

				if id then
					return id
				end
			end
		end
	end

	return nil
end

local function resolveAnimationId(
	attributeName: string,
	objectName: string,
	allowAnimateIdleFallback: boolean
): string?

	local fromAttribute =
		normalizeAnimationId(
			character:GetAttribute(
				attributeName
			)
		)

	if fromAttribute then
		return fromAttribute
	end

	local fromObject =
		findNamedAnimationId(
			objectName
		)

	if fromObject then
		return fromObject
	end

	if allowAnimateIdleFallback then
		return findAnimateIdleId()
	end

	return nil
end

---------------------------------------------------------------------
-- IDENTITY / COMBAT ENTITY FLAGS
---------------------------------------------------------------------

character:SetAttribute(
	"IsCombatDummy",
	true
)

character:SetAttribute(
	"TrainingDummy",
	true
)

character:SetAttribute(
	"PassiveNPC",
	true
)

character:SetAttribute(
	"CombatSuppressed",
	false
)

-- Unlike v1, CombatMode is NOT permanently asserted.
-- It activates after receiving damage.
character:SetAttribute(
	"CombatMode",
	false
)

character:SetAttribute(
	"DummyHitstunActive",
	false
)

character:SetAttribute(
	"DummyHitstunEndsAt",
	0
)

-- Explicitly passive combat flags.
character:SetAttribute(
	"IsAttacking",
	false
)

character:SetAttribute(
	"IsBlocking",
	false
)

character:SetAttribute(
	"IsParrying",
	false
)

if not CollectionService:HasTag(
	character,
	"ProjectileTarget"
	) then
	CollectionService:AddTag(
		character,
		"ProjectileTarget"
	)
end

if not CollectionService:HasTag(
	character,
	"CombatDummy"
	) then
	CollectionService:AddTag(
		character,
		"CombatDummy"
	)
end

---------------------------------------------------------------------
-- HUMANOID / PHYSICS
---------------------------------------------------------------------

humanoid.MaxHealth =
	MAX_HEALTH

humanoid.Health =
	MAX_HEALTH

humanoid.BreakJointsOnDeath =
	false

humanoid.AutoRotate =
	false

-- No voluntary locomotion.
humanoid.WalkSpeed =
	0

if humanoid.UseJumpPower then
	humanoid.JumpPower =
		0
else
	humanoid.JumpHeight =
		0
end

-- Keep physics states needed by knockback / launchers.
humanoid:SetStateEnabled(
	Enum.HumanoidStateType.Jumping,
	true
)

humanoid:SetStateEnabled(
	Enum.HumanoidStateType.Freefall,
	true
)

humanoid:SetStateEnabled(
	Enum.HumanoidStateType.FallingDown,
	true
)

humanoid:SetStateEnabled(
	Enum.HumanoidStateType.GettingUp,
	true
)

humanoid:SetStateEnabled(
	Enum.HumanoidStateType.Landed,
	true
)

for _, descendant in ipairs(
	character:GetDescendants()
	) do
	if descendant:IsA("BasePart") then
		descendant.Anchored =
			false
	end
end

root.CanCollide =
	false

pcall(function()
	root:SetNetworkOwner(nil)
end)

root.AssemblyLinearVelocity =
	Vector3.zero

root.AssemblyAngularVelocity =
	Vector3.zero

---------------------------------------------------------------------
-- ANIMATOR
---------------------------------------------------------------------

local animator =
	humanoid:FindFirstChildOfClass(
		"Animator"
	)

if not animator then
	animator =
		Instance.new(
			"Animator"
		)

	animator.Parent =
		humanoid
end

-- Harvest a possible idle before disabling another Animate controller.
local normalIdleAnimationId =
	resolveAnimationId(
		"IdleAnimationId",
		"IdleAnimation",
		true
	)

local combatIdleAnimationId =
	resolveAnimationId(
		"CombatIdleAnimationId",
		"CombatIdleAnimation",
		false
	)

local hitstunAnimationId =
	resolveAnimationId(
		"HitstunAnimationId",
		"HitstunAnimation",
		false
	)

-- Prevent another NPC Animate script from fighting this controller.
local animate =
	character:FindFirstChild(
		"Animate"
	)

if animate
	and (
		animate:IsA("Script")
			or animate:IsA("LocalScript")
	) then

	animate.Enabled =
		false
end

local function loadTrack(
	animationId: string?,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?

	if not animationId then
		return nil
	end

	local animation =
		Instance.new(
			"Animation"
		)

	animation.AnimationId =
		animationId

	local ok,
		result =
		pcall(function()
			return animator:LoadAnimation(
				animation
			)
		end)

	animation:Destroy()

	if not ok then
		warn(
			"[CombatTrainingDummy] Animation load failed",
			animationId,
			result
		)

		return nil
	end

	local track =
		result :: AnimationTrack

	track.Priority =
		priority

	track.Looped =
		looped

	return track
end

local normalIdleTrack =
	loadTrack(
		normalIdleAnimationId,
		Enum.AnimationPriority.Idle,
		true
	)

local combatIdleTrack =
	loadTrack(
		combatIdleAnimationId,
		Enum.AnimationPriority.Idle,
		true
	)

local hitstunTrack =
	loadTrack(
		hitstunAnimationId,
		Enum.AnimationPriority.Action3,
		false
	)

---------------------------------------------------------------------
-- ANIMATION STATE
---------------------------------------------------------------------

local function stopTrack(
	track: AnimationTrack?
)
	if track
		and track.IsPlaying then

		track:Stop(
			ANIMATION_FADE_TIME
		)
	end
end

local function playLoop(
	track: AnimationTrack?
)
	if not track then
		return
	end

	if not track.IsPlaying then
		track:Play(
			ANIMATION_FADE_TIME,
			1,
			1
		)
	end
end

local function isStunned(): boolean
	return character:GetAttribute(
		"DummyHitstunActive"
	) == true
		or character:GetAttribute(
			"Status_Stunned"
		) == true
		or character:GetAttribute(
			"IsStunned"
		) == true
end

local function refreshIdleAnimation()
	if isStunned() then
		stopTrack(
			normalIdleTrack
		)

		stopTrack(
			combatIdleTrack
		)

		return
	end

	if character:GetAttribute(
		"CombatMode"
		) == true then

		stopTrack(
			normalIdleTrack
		)

		if combatIdleTrack then
			playLoop(
				combatIdleTrack
			)
		else
			-- Safe visual fallback until a combat idle is configured.
			playLoop(
				normalIdleTrack
			)
		end

	else
		stopTrack(
			combatIdleTrack
		)

		playLoop(
			normalIdleTrack
		)
	end
end

local function playHitReaction()
	stopTrack(
		normalIdleTrack
	)

	stopTrack(
		combatIdleTrack
	)

	if hitstunTrack then
		if hitstunTrack.IsPlaying then
			hitstunTrack:Stop(0)
		end

		hitstunTrack.TimePosition =
			0

		hitstunTrack:Play(
			0.03,
			1,
			1
		)
	end
end

if hitstunTrack then
	hitstunTrack.Stopped:Connect(function()
		refreshIdleAnimation()
	end)
end

character:GetAttributeChangedSignal(
	"CombatMode"
):Connect(
	refreshIdleAnimation
)

character:GetAttributeChangedSignal(
	"Status_Stunned"
):Connect(
	refreshIdleAnimation
)

---------------------------------------------------------------------
-- ACTIVE STATUS INDICATOR
---------------------------------------------------------------------
--
-- The canonical elemental statuses currently replicate as character
-- attributes:
--
--   Status_Burning
--   Status_Unsteady
--   Status_Charged
--   Status_Heavy
--   Status_Wet
--
-- Generic effects are also supported here for QA when present.
-- This is presentation-only; it never applies/removes any status.

type StatusVisualDefinition = {
	DisplayName: string,
	Color: Color3,
	Aliases: {string},
}

local STATUS_VISUALS: {StatusVisualDefinition} = {
	{
		DisplayName = "BURNING",
		Color = Color3.fromRGB(255, 119, 54),
		Aliases = {
			"Status_Burning",
			"Status_Burn",
		},
	},
	{
		DisplayName = "WET",
		Color = Color3.fromRGB(79, 169, 255),
		Aliases = {
			"Status_Wet",
		},
	},
	{
		DisplayName = "UNSTEADY",
		Color = Color3.fromRGB(165, 236, 186),
		Aliases = {
			"Status_Unsteady",
		},
	},
	{
		DisplayName = "CHARGED",
		Color = Color3.fromRGB(231, 219, 98),
		Aliases = {
			"Status_Charged",
		},
	},
	{
		DisplayName = "HEAVY",
		Color = Color3.fromRGB(154, 125, 94),
		Aliases = {
			"Status_Heavy",
		},
	},
	{
		DisplayName = "POISON",
		Color = Color3.fromRGB(153, 104, 209),
		Aliases = {
			"Status_Poison",
		},
	},
	{
		DisplayName = "BLEED",
		Color = Color3.fromRGB(215, 75, 75),
		Aliases = {
			"Status_Bleed",
		},
	},
	{
		DisplayName = "SLOW",
		Color = Color3.fromRGB(112, 195, 219),
		Aliases = {
			"Status_Slow",
		},
	},
	{
		DisplayName = "STUN",
		Color = Color3.fromRGB(244, 231, 130),
		Aliases = {
			"Status_Stunned",
		},
	},
	{
		DisplayName = "CHAKRA SUPPRESSION",
		Color = Color3.fromRGB(181, 120, 223),
		Aliases = {
			"Status_ChakraSuppression",
			"Status_ChakraSuppressed",
		},
	},
}

local statusGui =
	Instance.new(
		"BillboardGui"
	)

statusGui.Name =
	"TrainingDummyStatusIndicator"

statusGui.Adornee =
	head

statusGui.Size =
	UDim2.fromOffset(
		260,
		116
	)

statusGui.StudsOffsetWorldSpace =
	Vector3.new(
		0,
		4.9,
		0
	)

statusGui.AlwaysOnTop =
	true

statusGui.LightInfluence =
	0

statusGui.MaxDistance =
	140

statusGui.Enabled =
	false

statusGui.Parent =
	head

local statusContainer =
	Instance.new(
		"Frame"
	)

statusContainer.Name =
	"StatusContainer"

statusContainer.Size =
	UDim2.fromScale(
		1,
		1
	)

statusContainer.BackgroundTransparency =
	1

statusContainer.Parent =
	statusGui

local grid =
	Instance.new(
		"UIGridLayout"
	)

grid.CellSize =
	UDim2.fromOffset(
		124,
		25
	)

grid.CellPadding =
	UDim2.fromOffset(
		5,
		4
	)

grid.FillDirectionMaxCells =
	2

grid.HorizontalAlignment =
	Enum.HorizontalAlignment.Center

grid.VerticalAlignment =
	Enum.VerticalAlignment.Center

grid.SortOrder =
	Enum.SortOrder.LayoutOrder

grid.Parent =
	statusContainer

local activeStatusLabels:
	{[string]: TextLabel} =
	{}

local function isStatusDefinitionActive(
	definition: StatusVisualDefinition
): boolean

	for _, attributeName in ipairs(
		definition.Aliases
		) do
		if character:GetAttribute(
			attributeName
			) == true then

			return true
		end
	end

	return false
end

local function createStatusLabel(
	definition: StatusVisualDefinition,
	layoutOrder: number
): TextLabel

	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"Status_"
		.. definition.DisplayName

	label.LayoutOrder =
		layoutOrder

	label.BackgroundColor3 =
		definition.Color

	label.BackgroundTransparency =
		0.12

	label.BorderSizePixel =
		0

	label.Text =
		definition.DisplayName

	label.Font =
		Enum.Font.GothamBold

	label.TextSize =
		13

	label.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	label.TextStrokeColor3 =
		Color3.fromRGB(
			20,
			20,
			20
		)

	label.TextStrokeTransparency =
		0.35

	local corner =
		Instance.new(
			"UICorner"
		)

	corner.CornerRadius =
		UDim.new(
			0,
			6
		)

	corner.Parent =
		label

	local stroke =
		Instance.new(
			"UIStroke"
		)

	stroke.Thickness =
		1

	stroke.Transparency =
		0.25

	stroke.Color =
		Color3.fromRGB(
			255,
			255,
			255
		)

	stroke.Parent =
		label

	return label
end

local function refreshStatusIndicator()
	local activeCount =
		0

	for index, definition in ipairs(
		STATUS_VISUALS
		) do
		local key =
			definition.DisplayName

		local isActive =
			isStatusDefinitionActive(
				definition
			)

		local existing =
			activeStatusLabels[
		key
		]

		if isActive then
			activeCount += 1

			if not existing then
				existing =
					createStatusLabel(
						definition,
						index
					)

				existing.Parent =
					statusContainer

				activeStatusLabels[
				key
				] = existing
			end

			existing.Visible =
				true
		elseif existing then
			existing.Visible =
				false
		end
	end

	statusGui.Enabled =
		activeCount > 0
end

-- Listen to every supported replicated status alias.
local watchedStatusAttributes:
	{[string]: boolean} =
	{}

for _, definition in ipairs(
	STATUS_VISUALS
	) do
	for _, attributeName in ipairs(
		definition.Aliases
		) do
		if not watchedStatusAttributes[
			attributeName
			] then

			watchedStatusAttributes[
			attributeName
			] = true

			character:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(
					refreshStatusIndicator
				)
		end
	end
end

refreshStatusIndicator()

---------------------------------------------------------------------
-- COMBAT MODE
---------------------------------------------------------------------

local lastDamageTime =
	-math.huge

local combatToken =
	0

local function enterCombatMode()
	lastDamageTime =
		os.clock()

	if character:GetAttribute(
		"CombatMode"
		) ~= true then

		character:SetAttribute(
			"CombatMode",
			true
		)
	end

	character:SetAttribute(
		"CombatModeSource",
		"TrainingDummyDamage"
	)

	character:SetAttribute(
		"CombatModeLastHitAt",
		lastDamageTime
	)

	combatToken += 1
	local myToken =
		combatToken

	local duration =
		readNumberAttribute(
			"DummyCombatModeDuration",
			DEFAULT_COMBAT_MODE_DURATION,
			0.5,
			60
		)

	task.delay(
		duration,
		function()
			if myToken ~= combatToken then
				return
			end

			if not character.Parent then
				return
			end

			if os.clock() - lastDamageTime
				< duration then

				return
			end

			character:SetAttribute(
				"CombatMode",
				false
			)

			character:SetAttribute(
				"CombatModeSource",
				nil
			)
		end
	)
end

---------------------------------------------------------------------
-- GENERIC PLAYER-LIKE HITSTUN
---------------------------------------------------------------------

local hitstunToken =
	0

local ownsGenericIsStunned =
	false

local function applyHitstun()
	hitstunToken += 1

	local myToken =
		hitstunToken

	local duration =
		readNumberAttribute(
			"DummyHitstunDuration",
			DEFAULT_HITSTUN_DURATION,
			0.05,
			3.0
		)

	character:SetAttribute(
		"DummyHitstunActive",
		true
	)

	character:SetAttribute(
		"DummyHitstunEndsAt",
		os.clock() + duration
	)

	-- Match the generic character contract used by combat/movement systems.
	if character:GetAttribute(
		"IsStunned"
		) ~= true then

		ownsGenericIsStunned =
			true

		character:SetAttribute(
			"IsStunned",
			true
		)
	end

	playHitReaction()

	task.delay(
		duration,
		function()
			if myToken ~= hitstunToken then
				return
			end

			if not character.Parent then
				return
			end

			character:SetAttribute(
				"DummyHitstunActive",
				false
			)

			character:SetAttribute(
				"DummyHitstunEndsAt",
				0
			)

			-- Never clear a canonical status stun.
			if ownsGenericIsStunned
				and character:GetAttribute(
					"Status_Stunned"
				) ~= true then

				character:SetAttribute(
					"IsStunned",
					false
				)

				ownsGenericIsStunned =
					false
			end

			refreshIdleAnimation()
		end
	)
end

---------------------------------------------------------------------
-- FLOATING DAMAGE NUMBERS
---------------------------------------------------------------------

local floatingIndex =
	0

local function formatDamage(
	damage: number
): string

	local rounded =
		math.round(
			damage
		)

	if math.abs(
		damage - rounded
		) < 0.05 then

		return tostring(
			rounded
		)
	end

	return string.format(
		"%.1f",
		damage
	)
end

local function spawnDamageNumber(
	damage: number
)
	if damage <= 0 then
		return
	end

	floatingIndex += 1

	local gui =
		Instance.new(
			"BillboardGui"
		)

	gui.Name =
		"TrainingDummyDamage_"
		.. tostring(
			floatingIndex
		)

	gui.Adornee =
		head

	gui.Size =
		UDim2.fromOffset(
			120,
			52
		)

	local randomX =
		(
			math.random()
			* 2
			- 1
		)
		* DAMAGE_NUMBER_X_SPREAD

	local startOffset =
		Vector3.new(
			randomX,
			DAMAGE_NUMBER_BASE_HEIGHT
			+ math.random() * 0.28,
			0
		)

	gui.StudsOffsetWorldSpace =
		startOffset

	gui.AlwaysOnTop =
		true

	gui.LightInfluence =
		0

	gui.MaxDistance =
		120

	gui.Parent =
		head

	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"Damage"

	label.Size =
		UDim2.fromScale(
			1,
			1
		)

	label.BackgroundTransparency =
		1

	label.Text =
		formatDamage(
			damage
		)

	label.Font =
		Enum.Font.GothamBold

	label.TextScaled =
		true

	label.TextColor3 =
		Color3.fromRGB(
			255,
			236,
			214
		)

	label.TextStrokeColor3 =
		Color3.fromRGB(
			55,
			20,
			15
		)

	label.TextStrokeTransparency =
		0.15

	label.Parent =
		gui

	local riseTween =
		TweenService:Create(
			gui,
			TweenInfo.new(
				DAMAGE_NUMBER_LIFETIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				StudsOffsetWorldSpace =
				startOffset
				+ Vector3.new(
					0,
					DAMAGE_NUMBER_RISE,
					0
				),
			}
		)

	local fadeTween =
		TweenService:Create(
			label,
			TweenInfo.new(
				DAMAGE_NUMBER_LIFETIME
				* 0.55,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.Out,
				0,
				false,
				DAMAGE_NUMBER_LIFETIME
				* 0.45
			),
			{
				TextTransparency =
				1,

				TextStrokeTransparency =
				1,
			}
		)

	riseTween:Play()
	fadeTween:Play()

	Debris:AddItem(
		gui,
		DAMAGE_NUMBER_LIFETIME
			+ 0.15
	)
end

---------------------------------------------------------------------
-- DAMAGE DETECTION + INFINITE HEALTH
---------------------------------------------------------------------

local restoringHealth =
	false

local lastObservedHealth =
	humanoid.Health

local restoreQueued =
	false

local function queueHealthRestore()
	if restoreQueued then
		return
	end

	restoreQueued =
		true

	task.defer(function()
		restoreQueued =
			false

		if not humanoid.Parent then
			return
		end

		restoringHealth =
			true

		humanoid.MaxHealth =
			MAX_HEALTH

		humanoid.Health =
			MAX_HEALTH

		lastObservedHealth =
			MAX_HEALTH

		restoringHealth =
			false
	end)
end

humanoid.HealthChanged:Connect(
	function(currentHealth: number)
		if restoringHealth then
			lastObservedHealth =
				currentHealth

			return
		end

		local previous =
			lastObservedHealth

		lastObservedHealth =
			currentHealth

		if currentHealth < previous then
			local damage =
				previous
			- currentHealth

			character:SetAttribute(
				"DummyLastDamage",
				damage
			)

			character:SetAttribute(
				"DummyLastDamageAt",
				os.clock()
			)

			spawnDamageNumber(
				damage
			)

			enterCombatMode()
			applyHitstun()
		end

		if currentHealth < MAX_HEALTH then
			queueHealthRestore()
		end
	end
)

---------------------------------------------------------------------
-- EXTERNAL STATUS STUN PRESENTATION
---------------------------------------------------------------------

character:GetAttributeChangedSignal(
	"Status_Stunned"
):Connect(function()
	if character:GetAttribute(
		"Status_Stunned"
		) == true then

		enterCombatMode()
		playHitReaction()
	else
		refreshIdleAnimation()
	end
end)

---------------------------------------------------------------------
-- KEEP PASSIVE FLAGS PASSIVE
---------------------------------------------------------------------

local PASSIVE_FALSE_ATTRIBUTES = {
	"IsAttacking",
	"IsBlocking",
	"IsParrying",
}

for _, attributeName in ipairs(
	PASSIVE_FALSE_ATTRIBUTES
	) do
	character:
		GetAttributeChangedSignal(
			attributeName
		):
		Connect(function()
			if character:GetAttribute(
				attributeName
				) == true then

				character:SetAttribute(
					attributeName,
					false
				)
			end
		end)
end

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

refreshIdleAnimation()

print(
	"[CombatTrainingDummy] READY v2.2 PlayerLikeQA"
		.. " | Passive=ON"
		.. " | CombatOnDamage=ON"
		.. " | GenericHitstun=ON"
		.. " | DamageNumbers=ON"
		.. " | StatusIndicators=ON"
		.. " | PhysicsMovable=ON"
		.. " | ServerNetworkOwner=ON"
		.. " | ProjectileTarget=ON"
		.. " | CombatDummyTag=ON"
		.. " | IdleAnim="
		.. tostring(
			normalIdleAnimationId
			or "NOT_CONFIGURED"
		)
		.. " | CombatIdleAnim="
		.. tostring(
			combatIdleAnimationId
			or "NOT_CONFIGURED"
		)
		.. " | HitstunAnim="
		.. tostring(
			hitstunAnimationId
			or "NOT_CONFIGURED"
		)
)
