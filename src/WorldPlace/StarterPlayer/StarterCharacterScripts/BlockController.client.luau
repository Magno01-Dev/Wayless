--!strict
-- BlockController v11 - Launcher Air Defense + Status Combat Gate
-- StarterPlayer > StarterCharacterScripts > BlockController
--
-- F = mantener Block
--
-- v9:
-- - BlockHold ahora usa la animacion upper-body 102348484921328.
-- - La locomocion normal (Walk) queda libre para controlar Torso/Legs porque
--   la animacion fue creada sin keyframes en esas partes en Moon Animator.
-- - BlockStart y BlockImpact se preservan exactamente como en v8.
-- - No modifica WalkSpeed, AutoRotate, SurfaceWalking, WaterWalking ni Dash.

local UserInputService =
	game:GetService("UserInputService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


-- =========================
-- CHARACTER
-- =========================

local character =
	script.Parent

local humanoid =
	character:WaitForChild(
		"Humanoid"
	)

local animator =
	humanoid:WaitForChild(
		"Animator"
	)


-- =========================
-- REMOTES
-- =========================

local combatRemotes =
	ReplicatedStorage:WaitForChild(
		"CombatRemotes"
	)

local blockRequest =
	combatRemotes:WaitForChild(
		"BlockRequest"
	)

local blockImpactRemote =
	combatRemotes:WaitForChild(
		"BlockImpact"
	)

local blockBreakRemote =
	combatRemotes:WaitForChild(
		"BlockBreak"
	)


-- =========================
-- SETTINGS
-- =========================

local BLOCK_KEY =
	Enum.KeyCode.F

local BLOCK_START_ANIMATION_ID =
	"rbxassetid://83666836764911"

-- v9: nueva pose de bloqueo creada en Moon Animator solo con Upper Body.
-- Debe NO tener keyframes en Torso / Left Leg / Right Leg / HumanoidRootPart.
local BLOCK_HOLD_ANIMATION_ID =
	"rbxassetid://102348484921328"

local BLOCK_IMPACT_ANIMATION_ID =
	"rbxassetid://124810538040844"

local BLOCK_START_SPEED =
	1.35

local BLOCK_HOLD_SPEED =
	1.0

local BLOCK_IMPACT_SPEED =
	1.0

local BLOCK_START_FADE_IN =
	0.05

local BLOCK_HOLD_FADE_IN =
	0.04

local BLOCK_IMPACT_FADE_IN =
	0.02

local BLOCK_IMPACT_FADE_OUT =
	0.05

local BLOCK_RELEASE_FADE =
	0.10


-- =========================
-- STATE
-- =========================

local blockHeld =
	false

local isBlocking =
	false

local blockGeneration =
	0


character:SetAttribute(
	"IsBlocking",
	false
)

character:SetAttribute(
	"BlockPhase",
	"None"
)


-- =========================
-- ANIMATIONS
-- =========================

local blockStartAnimation =
	Instance.new("Animation")

blockStartAnimation.Name =
	"BlockStart"

blockStartAnimation.AnimationId =
	BLOCK_START_ANIMATION_ID


local blockStartTrack =
	animator:LoadAnimation(
		blockStartAnimation
	)

blockStartTrack.Priority =
	Enum.AnimationPriority.Action

blockStartTrack.Looped =
	false


local blockHoldAnimation =
	Instance.new("Animation")

blockHoldAnimation.Name =
	"BlockHoldUpperBody"

blockHoldAnimation.AnimationId =
	BLOCK_HOLD_ANIMATION_ID


local blockHoldTrack =
	animator:LoadAnimation(
		blockHoldAnimation
	)

-- Action gana sobre los brazos de Walk, mientras los joints que no existen
-- en esta animacion siguen siendo controlados por la locomocion.
blockHoldTrack.Priority =
	Enum.AnimationPriority.Action

blockHoldTrack.Looped =
	true


local blockImpactAnimation =
	Instance.new("Animation")

blockImpactAnimation.Name =
	"BlockImpact"

blockImpactAnimation.AnimationId =
	BLOCK_IMPACT_ANIMATION_ID


local blockImpactTrack =
	animator:LoadAnimation(
		blockImpactAnimation
	)

blockImpactTrack.Priority =
	Enum.AnimationPriority.Action2

blockImpactTrack.Looped =
	false


-- =========================
-- HELPERS
-- =========================

local function isTreeJumpActive()

	return character:GetAttribute(
		"TreeJumpActive"
	) == true
		or character:GetAttribute(
			"IsTreeJumping"
		) == true
end


local function isAirborne()

	local state =
		humanoid:GetState()

	return state ==
		Enum.HumanoidStateType.Jumping
		or state ==
		Enum.HumanoidStateType.Freefall
end


local function isDownedSystemLocked(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsCarrying") == true
end


local function isLauncherAirVictim(): boolean
	return character:GetAttribute(
		"AirComboServerActive"
	) == true
		and character:GetAttribute(
			"AirComboRole"
		) == "Victim"
		and character:GetAttribute(
			"LauncherAirComboVictim"
		) == true
end


local function isStatusCombatBlocked(): boolean
	return character:GetAttribute(
		"Status_AttackBlocked"
	) == true

		or character:GetAttribute(
			"Status_Stunned"
		) == true
end


local function canStartBlock()
	if isDownedSystemLocked() then
		return false
	end

	if character:GetAttribute(
		"GuardBroken"
		) == true then
		return false
	end

	if character:GetAttribute(
		"CombatMode"
		) ~= true then
		return false
	end

	if character:GetAttribute(
		"CombatSuppressed"
		) == true then
		return false
	end

	if humanoid.Health <= 0 then
		return false
	end

	if (
		character:GetAttribute(
			"IsStunned"
		) == true
			and not isLauncherAirVictim()
		)
			or isStatusCombatBlocked() then
		return false
	end

	if isBlocking then
		return false
	end

	if character:GetAttribute(
		"IsAttacking"
		) == true then
		return false
	end

	if character:GetAttribute(
		"IsDashing"
		) == true then
		return false
	end

	if character:GetAttribute(
		"IsSprinting"
		) == true then
		return false
	end

	if isTreeJumpActive() then
		return false
	end

	if character:GetAttribute(
		"SurfaceJumping"
		) == true then
		return false
	end

	if isAirborne()
		and not isLauncherAirVictim() then
		return false
	end

	if humanoid:GetState() ==
		Enum.HumanoidStateType.Swimming then
		return false
	end

	if humanoid.PlatformStand then
		return false
	end

	return true
end


-- =========================
-- STOP TRACKS
-- =========================

local function stopBlockTracks(
	fadeTime
)

	if blockStartTrack.IsPlaying then
		blockStartTrack:Stop(
			fadeTime
		)
	end

	if blockHoldTrack.IsPlaying then
		blockHoldTrack:Stop(
			fadeTime
		)
	end

	if blockImpactTrack.IsPlaying then
		blockImpactTrack:Stop(
			fadeTime
		)
	end
end


-- =========================
-- END BLOCK
-- =========================

local function endBlock(
	fadeTime
)

	if not isBlocking
		and not blockStartTrack.IsPlaying
		and not blockHoldTrack.IsPlaying then
		return
	end

	blockGeneration += 1

	isBlocking =
		false

	character:SetAttribute(
		"IsBlocking",
		false
	)

	character:SetAttribute(
		"BlockPhase",
		"None"
	)

	blockRequest:FireServer(
		"End"
	)

	stopBlockTracks(
		fadeTime
			or BLOCK_RELEASE_FADE
	)
end


-- =========================
-- BLOCK HOLD
-- =========================

local function beginBlockHold(
	generation
)

	if generation ~=
		blockGeneration then
		return
	end

	if not isBlocking
		or not blockHeld then
		return
	end

	if character:GetAttribute(
		"CombatMode"
		) ~= true then
		endBlock(
			BLOCK_RELEASE_FADE
		)
		return
	end

	character:SetAttribute(
		"BlockPhase",
		"Hold"
	)

	if blockImpactTrack.IsPlaying then
		return
	end

	if not blockHoldTrack.IsPlaying then
		blockHoldTrack:Play(
			BLOCK_HOLD_FADE_IN
		)

		blockHoldTrack:AdjustSpeed(
			BLOCK_HOLD_SPEED
		)
	end
end


-- =========================
-- START BLOCK
-- =========================

local function startBlock()

	if not canStartBlock() then
		return
	end

	blockGeneration += 1

	local generation =
		blockGeneration

	isBlocking =
		true

	character:SetAttribute(
		"IsBlocking",
		true
	)

	character:SetAttribute(
		"BlockPhase",
		"Start"
	)

	blockRequest:FireServer(
		"Start"
	)

	if blockHoldTrack.IsPlaying then
		blockHoldTrack:Stop(
			0
		)
	end

	if blockImpactTrack.IsPlaying then
		blockImpactTrack:Stop(
			0
		)
	end

	if blockStartTrack.IsPlaying then
		blockStartTrack:Stop(
			0
		)
	end

	blockStartTrack:Play(
		BLOCK_START_FADE_IN
	)

	blockStartTrack:AdjustSpeed(
		BLOCK_START_SPEED
	)

	local connection

	connection =
		blockStartTrack.Stopped:Connect(
			function()

				connection:Disconnect()

				beginBlockHold(
					generation
				)
			end
		)
end


-- =========================
-- BLOCK IMPACT
-- =========================

local impactGeneration =
	0


local function playBlockImpact()

	if not isBlocking
		or not blockHeld then
		return
	end

	impactGeneration += 1

	local generation =
		impactGeneration

	if blockStartTrack.IsPlaying then
		blockStartTrack:Stop(
			0.02
		)
	end

	if blockHoldTrack.IsPlaying then
		blockHoldTrack:Stop(
			0.02
		)
	end

	if blockImpactTrack.IsPlaying then
		blockImpactTrack:Stop(
			0
		)
	end

	character:SetAttribute(
		"BlockPhase",
		"Impact"
	)

	blockImpactTrack:Play(
		BLOCK_IMPACT_FADE_IN
	)

	blockImpactTrack:AdjustSpeed(
		BLOCK_IMPACT_SPEED
	)

	local connection

	connection =
		blockImpactTrack.Stopped:Connect(
			function()

				connection:Disconnect()

				if generation ~=
					impactGeneration then
					return
				end

				if not isBlocking
					or not blockHeld
					or character:GetAttribute(
						"CombatMode"
					) ~= true
					or character:GetAttribute(
						"CombatSuppressed"
					) == true then
					return
				end

				character:SetAttribute(
					"BlockPhase",
					"Hold"
				)

				if not blockHoldTrack.IsPlaying then
					blockHoldTrack:Play(
						BLOCK_IMPACT_FADE_OUT
					)

					blockHoldTrack:AdjustSpeed(
						BLOCK_HOLD_SPEED
					)
				end
			end
		)
end


blockImpactRemote.OnClientEvent:Connect(
	function()
		playBlockImpact()
	end
)


-- =========================
-- BLOCK BREAK
-- =========================

blockBreakRemote.OnClientEvent:Connect(
	function(
		_brokenUntil
	)
		blockHeld =
			false

		impactGeneration +=
			1

		endBlock(
			0.03
		)

		character:SetAttribute(
			"BlockPhase",
			"Broken"
		)
	end
)


-- =========================
-- INPUT
-- =========================

UserInputService.InputBegan:Connect(
	function(
		input,
		gameProcessed
	)

		if input.KeyCode ~=
			BLOCK_KEY then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		if gameProcessed then
			return
		end

		blockHeld =
			true

		startBlock()
	end
)


UserInputService.InputEnded:Connect(
	function(
		input
	)

		if input.KeyCode ~=
			BLOCK_KEY then
			return
		end

		blockHeld =
			false

		endBlock(
			BLOCK_RELEASE_FADE
		)
	end
)


-- =========================
-- CANCEL CONDITIONS
-- =========================

character:GetAttributeChangedSignal(
	"GuardBroken"
):Connect(
	function()

		if character:GetAttribute(
			"GuardBroken"
			) == true then
			blockHeld =
				false

			endBlock(
				0.03
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"CombatMode"
):Connect(
	function()

		if character:GetAttribute(
			"CombatMode"
			) ~= true then
			blockHeld =
				false

			endBlock(
				BLOCK_RELEASE_FADE
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"CombatSuppressed"
):Connect(
	function()

		if character:GetAttribute(
			"CombatSuppressed"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


for _, statusBlockAttribute in ipairs({
	"IsStunned",
	"Status_AttackBlocked",
	"Status_Stunned",
	}) do
	character:GetAttributeChangedSignal(
		statusBlockAttribute
	):Connect(
		function()

			if character:GetAttribute(
				statusBlockAttribute
				) == true then

				if statusBlockAttribute == "IsStunned"
					and isLauncherAirVictim() then

					return
				end

				blockHeld =
					false

				endBlock(
					0.03
				)
			end
		end
	)
end


character:GetAttributeChangedSignal(
	"IsAttacking"
):Connect(
	function()

		if character:GetAttribute(
			"IsAttacking"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"IsDashing"
):Connect(
	function()

		if character:GetAttribute(
			"IsDashing"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"IsSprinting"
):Connect(
	function()

		if character:GetAttribute(
			"IsSprinting"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"TreeJumpActive"
):Connect(
	function()

		if character:GetAttribute(
			"TreeJumpActive"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"IsTreeJumping"
):Connect(
	function()

		if character:GetAttribute(
			"IsTreeJumping"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


character:GetAttributeChangedSignal(
	"SurfaceJumping"
):Connect(
	function()

		if character:GetAttribute(
			"SurfaceJumping"
			) == true then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


humanoid.StateChanged:Connect(
	function(
		_,
		newState
	)

		if not isBlocking then
			return
		end

		local launcherAirVictim =
			isLauncherAirVictim()

		if (
			(
				newState ==
					Enum.HumanoidStateType.Jumping
					or newState ==
					Enum.HumanoidStateType.Freefall
			)
				and not launcherAirVictim
			)
				or newState ==
				Enum.HumanoidStateType.Swimming
				or newState ==
				Enum.HumanoidStateType.Dead then
			blockHeld =
				false

			endBlock(
				0.05
			)
		end
	end
)


for _, attributeName in ipairs({
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsExecuting",
	"IsCarrying",
	}) do
	character:GetAttributeChangedSignal(attributeName):Connect(function()
		if isDownedSystemLocked() then
			blockHeld = false
			endBlock(0.03)
		end
	end)
end


humanoid.Died:Connect(
	function()
		blockHeld =
			false

		endBlock(
			0
		)
	end
)


-- =========================
-- CLEANUP
-- =========================

script.Destroying:Connect(
	function()
		blockHeld =
			false

		endBlock(
			0
		)

		blockStartAnimation:Destroy()
		blockHoldAnimation:Destroy()
		blockImpactAnimation:Destroy()
	end
)


print(
	"[BlockController] READY v11 LauncherAirDefense + StatusCombatGate"
		.. " | HoldAnimation=102348484921328"
		.. " | WalkLayering=ON"
		.. " | BlockStart=PRESERVED"
		.. " | BlockImpact=PRESERVED"
)
