--!strict
-- AttackController v4.6 - WeaponProfile Swing Timing + Safe Aerial Kick Handoff
-- StarterPlayer > StarterCharacterScripts > AttackController
--
-- Built from the current v4.0 ReliableLauncherAirMarkers branch.
--
-- Phase 1:
-- - New 5-hit animation set.
-- - M1_1-M1_5 all use authored "Hit" markers; no hardcoded finisher timing.
-- - Removes legacy M1_4 authored root-motion curve.
-- - Phase 1.1: M1 movement restriction reduced even further for a faster ninja feel.
-- - M1 can begin directly from Sprint; Sprint yields once IsAttacking becomes true.
-- - Existing timestamp / Motion Compensation protocol is preserved.
-- - Existing CombatMode / Downed / Stun / Dash / TreeJump / Surface rules preserved.
--
-- Future phases will add dedicated Running/Lunge Attack, Launcher/Uplift,
-- Aerial Attack and Clash; they are intentionally NOT mixed into this baseline.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local rootPart =
	character:WaitForChild("HumanoidRootPart") :: BasePart

local WeaponCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"WeaponCatalog"
		)
	)

local combatRemotes =
	ReplicatedStorage:
	WaitForChild("CombatRemotes")

local m1Request =
	combatRemotes:
	WaitForChild("M1Request")


-- =========================
-- M1 ANIMATIONS
-- =========================

local M1_1_ANIMATION_ID =
	"rbxassetid://104431855936125"

local M1_2_ANIMATION_ID =
	"rbxassetid://72283993977789"

local M1_3_ANIMATION_ID =
	"rbxassetid://123837934591896"

local M1_4_ANIMATION_ID =
	"rbxassetid://134382076834484"

local M1_5_ANIMATION_ID =
	"rbxassetid://85536933283172"

local M1_1_ANIMATION_SPEED = 1
local M1_2_ANIMATION_SPEED = 1
local M1_3_ANIMATION_SPEED = 1
local M1_4_ANIMATION_SPEED = 1
local M1_5_ANIMATION_SPEED = 1

local M1_FADE_IN = 0.04
local M1_FADE_OUT = 0.08

-- User QA timing.
local DEFAULT_LOCAL_ATTACK_INTERVAL = 0.40
local COMBO_RESET_WINDOW = 1.20

-- Prevent endless 5-hit loop spam.
--
-- This lock starts when M1_5 STARTS, not after its animation ends.
-- The M1_5 animation therefore consumes part of the lock naturally and the
-- player only feels the remaining short pause after the finisher.
--
-- Keep client/server values matched.
local FULL_COMBO_RESTART_LOCK = 1.10


-- =========================
-- M1 FORWARD LUNGE
-- =========================

local M1_LUNGE_DELAY = 0.08
local M1_LUNGE_DELTA_V = 5


-- =========================
-- M1 COMBAT MOVEMENT
-- =========================
--
-- SprintController remains the single owner of Humanoid.WalkSpeed.
-- AttackController only publishes a temporary speed CAP.
--
-- Phase 1 starts intentionally mobile. If QA says this is too free, these
-- isolated caps can be lowered later without touching hitboxes/timing.

-- Phase 1.1 starts deliberately fast/mobile.
-- These values are now meaningful because SprintController v1.12 grants
-- a dedicated attack-movement base speed instead of forcing attacks to Walk=16.
local M1_1_4_WINDUP_SPEED = 22.0
local M1_1_4_HIT_SPEED = 20.0
local M1_1_4_RECOVERY_SPEED = 22.0

local M1_5_WINDUP_SPEED = 21.0
local M1_5_HIT_SPEED = 19.0
local M1_5_RECOVERY_SPEED = 21.5

local M1_HIT_SPEED_HOLD = 0.045

local M1_END_RECOVERY_SPEED_1 = 22.0
local M1_END_RECOVERY_SPEED_2 = 24.0
local M1_END_RECOVERY_STEP_TIME = 0.025


-- =========================
-- LEGACY M1_4 ROOT MOTION
-- =========================
-- Removed in Combat Rework Phase 1.
-- The new M1_4 is a normal marker-driven attack and no longer owns a
-- frame-authored root-motion curve. Small forward pressure still comes from
-- performM1Lunge(), shared by all five M1s.

local DEBUG_ATTACK = false


-- =========================
-- STATE
-- =========================

local isAttacking = false
local attackSequence = 0
local lastAttackStart = -math.huge

local comboIndex = 1
local currentComboIndex = 1

-- Dedicated Launcher aerial chain. This is intentionally independent from
-- the grounded comboIndex/reset timers so Launcher M1 can never inherit or
-- skip terrestrial combo state.
local launcherAirComboIndex = 1

-- Per-track aerial marker context. Ground M1 keeps the original global marker
-- validation; Launcher air stores the exact sequence/combo/AirComboId that
-- started each track so a marker firing on the same frame as Track.Stopped
-- cannot be discarded by a newer global currentTrack/currentComboIndex.
local launcherAirPendingHitByTrack = {}

-- M1_5 has its authored Hit marker very late in the track. Roblox can deliver
-- Track.Stopped on the same evaluation frame as that marker. Launcher air
-- already has a per-track fallback; grounded M1_5 now gets the same instance-
-- bound protection without changing M1_1-M1_4 or granting client-authoritative
-- damage. The server still resolves the real hitbox/LOS/Block/damage.
local groundedFinisherPendingHitByTrack = {}

-- Forward declarations are required because Track.Stopped callbacks are wired
-- before the helper implementations later in this file.
local sendLauncherAirPendingHit:
	(AnimationTrack, string) -> boolean

local sendGroundFinisherPendingHit:
	(AnimationTrack, string) -> boolean

local comboExpiresAt = -math.huge
local comboResetToken = 0

-- Absolute local time when a new M1_1 is allowed after completing M1_5.
local fullComboLockedUntil = -math.huge
local fullComboCooldownToken = 0

local currentTrack: AnimationTrack? = nil

local currentAttackCancelled = false

-- Invalidates delayed movement-cap transitions whenever a newer attack,
-- cancel, stun, dash, death, etc. takes ownership.
local movementCapGeneration = 0



character:SetAttribute(
	"IsAttacking",
	false
)

character:SetAttribute(
	"AttackPhase",
	"None"
)

character:SetAttribute(
	"M1ComboIndex",
	comboIndex
)

character:SetAttribute(
	"ActiveM1",
	nil
)

character:SetAttribute(
	"M1MovementSpeedCap",
	nil
)

character:SetAttribute(
	"M1ComboCooldownActive",
	false
)

character:SetAttribute(
	"M1ComboCooldownEndsAt",
	nil
)


-- =========================
-- M1 MOVEMENT CAP HELPERS
-- =========================

local function setM1MovementSpeedCap(
	speed: number?
)
	if typeof(speed) == "number" then
		character:SetAttribute(
			"M1MovementSpeedCap",
			math.max(0, speed)
		)
	else
		character:SetAttribute(
			"M1MovementSpeedCap",
			nil
		)
	end
end


local function invalidateMovementCapTasks(): number
	movementCapGeneration += 1
	return movementCapGeneration
end


local function beginAttackMovementCap(
	comboNumber: number
)
	local generation =
		invalidateMovementCapTasks()

	if comboNumber == 5 then
		setM1MovementSpeedCap(
			M1_5_WINDUP_SPEED
		)
	else
		setM1MovementSpeedCap(
			M1_1_4_WINDUP_SPEED
		)
	end

	return generation
end


local function applyHitMovementDip(
	sequence: number,
	comboNumber: number
)
	local generation =
		movementCapGeneration

	setM1MovementSpeedCap(
		comboNumber == 5
			and M1_5_HIT_SPEED
			or M1_1_4_HIT_SPEED
	)

	task.delay(
		M1_HIT_SPEED_HOLD,
		function()

			if movementCapGeneration ~= generation
				or sequence ~= attackSequence
				or not isAttacking
				or currentComboIndex ~= comboNumber then

				return
			end

			setM1MovementSpeedCap(
				comboNumber == 5
					and M1_5_RECOVERY_SPEED
					or M1_1_4_RECOVERY_SPEED
			)
		end
	)
end


local function beginNormalMovementRecovery()
	local generation =
		invalidateMovementCapTasks()

	setM1MovementSpeedCap(
		M1_END_RECOVERY_SPEED_1
	)

	task.delay(
		M1_END_RECOVERY_STEP_TIME,
		function()

			if movementCapGeneration ~= generation
				or isAttacking then

				return
			end

			setM1MovementSpeedCap(
				M1_END_RECOVERY_SPEED_2
			)
		end
	)

	task.delay(
		M1_END_RECOVERY_STEP_TIME * 2,
		function()

			if movementCapGeneration ~= generation
				or isAttacking then

				return
			end

			setM1MovementSpeedCap(nil)
		end
	)
end


local function clearM1MovementCap()
	invalidateMovementCapTasks()
	setM1MovementSpeedCap(nil)
end


-- =========================
-- LOAD TRACKS
-- =========================

local m1Animations: {[string]: Animation} = {}
local m1Tracks: {[string]: AnimationTrack} = {}


local function createTrack(
	name: string,
	animationId: string
): AnimationTrack

	local animation =
		Instance.new("Animation")

	animation.Name = name
	animation.AnimationId = animationId

	local track =
		animator:
		LoadAnimation(
			animation
		)

	track.Priority =
		Enum.AnimationPriority.Action

	track.Looped = false

	m1Animations[name] =
		animation

	m1Tracks[name] =
		track

	return track
end


local m1_1Track =
	createTrack(
		"M1_1",
		M1_1_ANIMATION_ID
	)

local m1_2Track =
	createTrack(
		"M1_2",
		M1_2_ANIMATION_ID
	)

local m1_3Track =
	createTrack(
		"M1_3",
		M1_3_ANIMATION_ID
	)

local m1_4Track =
	createTrack(
		"M1_4",
		M1_4_ANIMATION_ID
	)

local m1_5Track =
	createTrack(
		"M1_5",
		M1_5_ANIMATION_ID
	)


-- =========================
-- MOVEMENT / STATE HELPERS
-- =========================

local function isDownedSystemLocked(): boolean

	return character:GetAttribute(
		"DownedActionLocked"
	) == true

		or character:GetAttribute(
			"IsDowned"
		) == true

		or character:GetAttribute(
			"IsCarried"
		) == true

		or character:GetAttribute(
			"IsExecuting"
		) == true

		or character:GetAttribute(
			"IsCarrying"
		) == true
end


local function isTreeJumpActive(): boolean

	return character:GetAttribute(
		"TreeJumpActive"
	) == true

		or character:GetAttribute(
			"IsTreeJumping"
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


local function isLauncherAirM1Context(): boolean

	return character:GetAttribute(
		"LauncherAirComboAttacker"
	) == true
		and character:GetAttribute(
			"AirM1Allowed"
		) == true
		and character:GetAttribute(
			"AirComboRole"
		) == "Attacker"
		and character:GetAttribute(
			"AirComboActive"
		) == true
end


local function isAirborne(): boolean

	local state =
		humanoid:GetState()

	return state ==
		Enum.HumanoidStateType.Jumping

		or state ==
		Enum.HumanoidStateType.Freefall
end


local function projectOnPlane(
	vector: Vector3,
	normal: Vector3
): Vector3

	return vector
	- normal
		* vector:Dot(normal)
end


local function getAttackForwardDirection(): Vector3?

	local forward =
		rootPart.CFrame.LookVector

	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		local surfaceNormal =
			character:
			GetAttribute(
				"SurfaceNormal"
			)

		if typeof(surfaceNormal)
			== "Vector3"
			and surfaceNormal.Magnitude
			> 0.05 then

			local projectedForward =
				projectOnPlane(
					forward,
					surfaceNormal.Unit
				)

			if projectedForward.Magnitude
				> 0.05 then

				return projectedForward.Unit
			end
		end
	end

	local flatForward =
		Vector3.new(
			forward.X,
			0,
			forward.Z
		)

	if flatForward.Magnitude > 0.05 then
		return flatForward.Unit
	end

	return nil
end


local function performM1Lunge(
	sequence: number
)
	task.delay(
		M1_LUNGE_DELAY,
		function()

			-- Launcher aerial M1 keeps the authored M1 animation/hit timing,
			-- but the air-hold constraint owns spacing. Do not inject the
			-- normal grounded forward impulse into that constraint.
			if isLauncherAirM1Context() then
				return
			end

			if sequence ~= attackSequence
				or not isAttacking
				or character:GetAttribute(
					"CombatSuppressed"
				) == true
					or character:GetAttribute(
						"IsDashing"
					) == true
					or character:GetAttribute(
						"IsStunned"
					) == true
					or isStatusCombatBlocked()
					or isDownedSystemLocked()
					or isTreeJumpActive() then

				return
			end

			local direction =
				getAttackForwardDirection()

			if not direction then
				return
			end

			rootPart:
				ApplyImpulse(
					direction
					* rootPart.AssemblyMass
					* M1_LUNGE_DELTA_V
				)
		end
	)
end


-- =========================
-- ATTACK VALIDATION
-- =========================

local function getDrawnWeaponDefinition(): any?

	if character:GetAttribute(
		"WeaponState"
		) ~= "Drawn" then

		return nil
	end

	local weaponId =
		character:GetAttribute(
			"EquippedWeaponId"
		)

	if typeof(weaponId) ~= "string"
		or weaponId == "" then

		return nil
	end

	return WeaponCatalog.Get(
		weaponId
	)
end


local function getLocalAttackInterval(): number

	-- Launcher aerial M1 keeps its current authored timing.
	if isLauncherAirM1Context() then
		return DEFAULT_LOCAL_ATTACK_INTERVAL
	end

	local definition =
		getDrawnWeaponDefinition()

	if not definition
		or typeof(
			definition.Combat
		) ~= "table" then

		return DEFAULT_LOCAL_ATTACK_INTERVAL
	end

	local swingInterval =
		definition.Combat.SwingInterval

	if typeof(swingInterval)
		~= "number" then

		return DEFAULT_LOCAL_ATTACK_INTERVAL
	end

	return math.max(
		0.15,
		swingInterval
	)
end


local function getWeaponSwingSpeedScale(): number

	-- Launcher aerial M1 remains unchanged for this first weapon pass.
	if isLauncherAirM1Context() then
		return 1
	end

	local definition =
		getDrawnWeaponDefinition()

	if not definition
		or typeof(
			definition.Combat
		) ~= "table" then

		return 1
	end

	local scale =
		definition.Combat.SwingSpeedScale

	if typeof(scale) ~= "number" then
		return 1
	end

	return math.clamp(
		scale,
		0.35,
		2.50
	)
end


local function canStartAttack(): boolean

	if isDownedSystemLocked() then
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

	if character:GetAttribute(
		"IsStunned"
		) == true
			or isStatusCombatBlocked() then
		return false
	end

	if isAttacking then
		return false
	end

	if character:GetAttribute(
		"IsBlocking"
		) == true then
		return false
	end

	if character:GetAttribute(
		"IsDashing"
		) == true then
		return false
	end

	-- Air Dash ballistic carry is still part of the Dash action.
	-- Keep this explicit even though normal M1 is currently grounded-only:
	-- future aerial attacks must not accidentally cancel the committed arc.
	if character:GetAttribute(
		"AirDashCarryActive"
		) == true then
		return false
	end

	if character:GetAttribute(
		"IsThrowingKunai"
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

	-- Normal M1 remains grounded-only. The sole exception is the explicit
	-- Launcher aerial-combo window published by LauncherController.
	if not isLauncherAirM1Context()
		and character:GetAttribute(
			"SurfaceWalking"
		) ~= true
			and isAirborne() then
		return false
	end

	if humanoid:GetState()
		== Enum.HumanoidStateType.Swimming then
		return false
	end

	if humanoid.PlatformStand then
		return false
	end

	-- After M1_5, the next combo cannot immediately restart at M1_1.
	if not isLauncherAirM1Context()
		and time() < fullComboLockedUntil then
		return false
	end

	if time()
		- lastAttackStart
			< getLocalAttackInterval() then
		return false
	end

	return true
end


-- =========================
-- COMBO HELPERS
-- =========================

local function getTrackForCombo(
	index: number
): AnimationTrack

	if index == 2 then
		return m1_2Track
	end

	if index == 3 then
		return m1_3Track
	end

	if index == 4 then
		return m1_4Track
	end

	if index == 5 then
		return m1_5Track
	end

	return m1_1Track
end


local function getSpeedForCombo(
	index: number
): number

	local baseSpeed: number

	if index == 2 then
		baseSpeed =
			M1_2_ANIMATION_SPEED

	elseif index == 3 then
		baseSpeed =
			M1_3_ANIMATION_SPEED

	elseif index == 4 then
		baseSpeed =
			M1_4_ANIMATION_SPEED

	elseif index == 5 then
		baseSpeed =
			M1_5_ANIMATION_SPEED

	else
		baseSpeed =
			M1_1_ANIMATION_SPEED
	end

	return baseSpeed
		* getWeaponSwingSpeedScale()
end


local function advanceCombo()

	if comboIndex >= 5 then
		comboIndex = 1
	else
		comboIndex += 1
	end

	character:SetAttribute(
		"M1ComboIndex",
		comboIndex
	)
end


local function advanceLauncherAirCombo()

	if launcherAirComboIndex >= 5 then
		launcherAirComboIndex = 1
	else
		launcherAirComboIndex += 1
	end

	-- Preserve the public combo attribute for HUD/debug consumers, but do not
	-- mutate the grounded comboIndex while the player is in Launcher air hold.
	character:SetAttribute(
		"M1ComboIndex",
		launcherAirComboIndex
	)
end


local function beginFullComboRestartLock()
	fullComboCooldownToken += 1

	local token =
		fullComboCooldownToken

	fullComboLockedUntil =
		time()
		+ FULL_COMBO_RESTART_LOCK

	character:SetAttribute(
		"M1ComboCooldownActive",
		true
	)

	character:SetAttribute(
		"M1ComboCooldownEndsAt",
		workspace:GetServerTimeNow()
			+ FULL_COMBO_RESTART_LOCK
	)

	if DEBUG_ATTACK then
		print(
			"[M1-Client] Full combo cooldown",
			string.format(
				"%.2fs",
				FULL_COMBO_RESTART_LOCK
			)
		)
	end

	task.delay(
		FULL_COMBO_RESTART_LOCK,
		function()

			if fullComboCooldownToken ~= token then
				return
			end

			fullComboLockedUntil =
				-math.huge

			character:SetAttribute(
				"M1ComboCooldownActive",
				false
			)

			character:SetAttribute(
				"M1ComboCooldownEndsAt",
				nil
			)

			if DEBUG_ATTACK then
				print(
					"[M1-Client] Full combo ready"
				)
			end
		end
	)
end


local function resetCombo()

	comboResetToken += 1
	comboExpiresAt = -math.huge

	comboIndex = 1
	currentComboIndex = 1

	character:SetAttribute(
		"M1ComboIndex",
		comboIndex
	)
end


local function disarmComboReset()

	comboResetToken += 1
	comboExpiresAt = -math.huge
end


local function armComboReset()

	comboResetToken += 1

	local token =
		comboResetToken

	comboExpiresAt =
		time()
		+ COMBO_RESET_WINDOW

	task.delay(
		COMBO_RESET_WINDOW,
		function()

			if comboResetToken ~= token
				or isAttacking
				or comboIndex == 1
				or time() < comboExpiresAt then
				return
			end

			if DEBUG_ATTACK then
				print(
					"[M1-Client] Combo reset by timeout"
				)
			end

			resetCombo()
		end
	)
end


-- =========================
-- ROOT MOTION
-- =========================
-- No M1-specific authored root motion in Combat Rework Phase 1.


-- =========================
-- END / START ATTACK
-- =========================

local function stopAllM1Tracks(
	fadeTime: number
)
	for _, track in pairs(
		m1Tracks
		) do
		if track.IsPlaying then
			track:
				Stop(
					fadeTime
				)
		end
	end
end


local function endAttack(
	sequence: number,
	fadeTime: number?,
	recoverMovement: boolean?
)
	if sequence ~= attackSequence
		or not isAttacking then
		return
	end

	isAttacking = false

	character:SetAttribute(
		"IsAttacking",
		false
	)

	character:SetAttribute(
		"AttackPhase",
		"None"
	)

	character:SetAttribute(
		"ActiveM1",
		nil
	)

	if currentTrack
		and currentTrack.IsPlaying then

		currentTrack:
			Stop(
				fadeTime
				or M1_FADE_OUT
			)
	end

	currentTrack = nil

	if recoverMovement == false then
		clearM1MovementCap()
	else
		beginNormalMovementRecovery()
	end
end


local function startAttack()

	if not canStartAttack() then
		return
	end

	local launcherAirContext =
		isLauncherAirM1Context()

	attackSequence += 1

	local sequence =
		attackSequence

	-- Grounded chains keep their existing timeout behavior. Launcher aerial
	-- chains use launcherAirComboIndex and therefore never inherit/reset from
	-- comboExpiresAt while suspended.
	if not launcherAirContext
		and comboIndex ~= 1
		and comboExpiresAt ~= -math.huge
		and time() > comboExpiresAt then

		resetCombo()
	end

	if not launcherAirContext then
		disarmComboReset()
	end

	currentComboIndex =
		launcherAirContext
		and launcherAirComboIndex
		or comboIndex

	currentAttackCancelled = false

	currentTrack =
		getTrackForCombo(
			currentComboIndex
		)

	lastAttackStart = time()
	isAttacking = true

	-- Keep the authored full-combo cooldown semantics. The Launcher server will
	-- end the aerial hold immediately when the authoritative M1_5 connects.
	if currentComboIndex == 5 then
		beginFullComboRestartLock()
	end

	beginAttackMovementCap(
		currentComboIndex
	)

	character:SetAttribute(
		"IsAttacking",
		true
	)

	character:SetAttribute(
		"AttackPhase",
		"Windup"
	)

	character:SetAttribute(
		"ActiveM1",
		currentComboIndex
	)

	stopAllM1Tracks(0)

	local thisTrack =
		currentTrack

	local animationStartedAt =
		workspace:
		GetServerTimeNow()

	if launcherAirContext then
		local airComboIdSnapshot = character:GetAttribute("AirComboId")
		if typeof(airComboIdSnapshot) == "number" then
			launcherAirPendingHitByTrack[thisTrack] = {
				sequence = sequence,
				comboNumber = currentComboIndex,
				airComboId = airComboIdSnapshot,
				sent = false,
			}
		end
	elseif currentComboIndex == 5 then
		groundedFinisherPendingHitByTrack[thisTrack] = {
			sequence = sequence,
			comboNumber = 5,
			sent = false,
		}
	end

	thisTrack:
		Play(
			M1_FADE_IN
		)

	thisTrack:
		AdjustSpeed(
			getSpeedForCombo(
				currentComboIndex
			)
		)

	m1Request:
		FireServer(
			"Start",
			sequence,
			currentComboIndex,
			animationStartedAt
		)

	performM1Lunge(
		sequence
	)

	if DEBUG_ATTACK then
		print(
			"[M1-Client] Start",
			sequence,
			"M1_"
				.. currentComboIndex,
			launcherAirContext
				and "[LAUNCHER-AIR]"
				or "[GROUND]"
		)
	end

	if launcherAirContext then
		advanceLauncherAirCombo()
	else
		advanceCombo()
	end

	local stoppedConnection:
		RBXScriptConnection?

	stoppedConnection =
		thisTrack.Stopped:
		Connect(
			function()

				if stoppedConnection then
					stoppedConnection:
					Disconnect()
				end

				if currentTrack ==
					thisTrack then

					local finishedCombo =
					currentComboIndex

					if launcherAirContext then
						local pendingAir = launcherAirPendingHitByTrack[thisTrack]
						if pendingAir and pendingAir.sent ~= true then
							-- Roblox can deliver Track.Stopped on the same evaluation frame as
							-- a late marker. Do not let that race erase a committed aerial M1.
							sendLauncherAirPendingHit(thisTrack, "TrackStoppedFallback")
						end
						launcherAirPendingHitByTrack[thisTrack] = nil
					elseif finishedCombo == 5 then
						local pendingGroundFinisher =
						groundedFinisherPendingHitByTrack[thisTrack]

						if pendingGroundFinisher
							and pendingGroundFinisher.sent ~= true
							and currentAttackCancelled ~= true then

							sendGroundFinisherPendingHit(
								thisTrack,
								"TrackStoppedFallback"
							)
						end

						groundedFinisherPendingHitByTrack[thisTrack] = nil
					end

					endAttack(
						sequence,
						0,
						true
					)

					if launcherAirContext then
						-- No grounded combo timeout runs while suspended. The dedicated
						-- aerial index remains armed until M1_5 or AirEnd.
						if finishedCombo >= 5 then
							launcherAirComboIndex = 1
						end
					elseif finishedCombo >= 5 then
						resetCombo()
					else
						armComboReset()
					end
				end
			end
		)
end


-- =========================
-- HIT MARKERS
-- =========================

sendLauncherAirPendingHit = function(
	track: AnimationTrack,
	source: string
): boolean
	local pending = launcherAirPendingHitByTrack[track]
	if not pending or pending.sent == true then
		return false
	end

	if not isLauncherAirM1Context()
		or character:GetAttribute("AirComboId") ~= pending.airComboId then
		return false
	end

	pending.sent = true

	local hitMarkerAt = workspace:GetServerTimeNow()

	if DEBUG_ATTACK then
		print(
			"[M1-Client] Launcher air HIT dispatch",
			pending.sequence,
			"M1_" .. tostring(pending.comboNumber),
			"source", source
		)
	end

	m1Request:FireServer(
		"Hit",
		pending.sequence,
		pending.comboNumber,
		nil,
		hitMarkerAt
	)

	return true
end

sendGroundFinisherPendingHit = function(
	track: AnimationTrack,
	source: string
): boolean
	local pending =
		groundedFinisherPendingHitByTrack[track]

	if not pending
		or pending.sent == true
		or currentAttackCancelled == true then

		return false
	end

	-- This fallback is exclusively for the grounded M1_5 track instance.
	-- It does not manufacture a target: CombatServer still performs the
	-- authoritative hitbox, LOS, Block and DamageService checks.
	if pending.comboNumber ~= 5 then
		return false
	end

	pending.sent = true

	local hitMarkerAt =
		workspace:GetServerTimeNow()

	if DEBUG_ATTACK then
		print(
			"[M1-Client] Ground M1_5 HIT dispatch",
			pending.sequence,
			"source",
			source
		)
	end

	m1Request:
		FireServer(
			"Hit",
			pending.sequence,
			5,
			nil,
			hitMarkerAt
		)

	return true
end


local function onHitMarker(
	track: AnimationTrack,
	comboNumber: number
)
	-- Launcher air markers are tied to the attack instance, not mutable global
	-- currentTrack/currentComboIndex. This removes the end-of-track race that
	-- intermittently discarded M1_1 (and then poisoned the rest of the chain).
	local pendingAir = launcherAirPendingHitByTrack[track]
	if pendingAir then
		if pendingAir.comboNumber ~= comboNumber then
			return
		end

		if currentTrack == track and isAttacking then
			character:SetAttribute("AttackPhase", "Hit")
			applyHitMovementDip(pendingAir.sequence, comboNumber)
		end

		sendLauncherAirPendingHit(track, "Marker")
		return
	end

	local pendingGroundFinisher =
		groundedFinisherPendingHitByTrack[track]

	if pendingGroundFinisher then
		if pendingGroundFinisher.comboNumber ~= comboNumber then
			return
		end

		if currentTrack == track
			and isAttacking then

			character:SetAttribute(
				"AttackPhase",
				"Hit"
			)

			applyHitMovementDip(
				pendingGroundFinisher.sequence,
				comboNumber
			)
		end

		sendGroundFinisherPendingHit(
			track,
			"Marker"
		)

		return
	end

	if not isAttacking
		or currentTrack ~= track
		or currentComboIndex ~= comboNumber then
		return
	end

	character:SetAttribute(
		"AttackPhase",
		"Hit"
	)

	applyHitMovementDip(
		attackSequence,
		comboNumber
	)

	-- v2.5: stamp the authored visual contact moment.
	local hitMarkerAt =
		workspace:
		GetServerTimeNow()

	if DEBUG_ATTACK then
		print(
			"[M1-Client] HIT marker",
			attackSequence,
			"M1_"
				.. comboNumber,
			"t=",
			string.format(
				"%.4f",
				hitMarkerAt
			)
		)
	end

	-- comboNumber is repeated for diagnostics/protocol clarity.
	-- nil keeps the Start-only animationStartedAt slot untouched.
	m1Request:
		FireServer(
			"Hit",
			attackSequence,
			comboNumber,
			nil,
			hitMarkerAt
		)

	task.defer(
		function()

			if isAttacking
				and currentTrack ==
				track then

				character:SetAttribute(
					"AttackPhase",
					"Recovery"
				)
			end
		end
	)
end


m1_1Track:
	GetMarkerReachedSignal(
		"Hit"
	):
	Connect(
		function()
			onHitMarker(
				m1_1Track,
				1
			)
		end
	)

m1_2Track:
	GetMarkerReachedSignal(
		"Hit"
	):
	Connect(
		function()
			onHitMarker(
				m1_2Track,
				2
			)
		end
	)

m1_3Track:
	GetMarkerReachedSignal(
		"Hit"
	):
	Connect(
		function()
			onHitMarker(
				m1_3Track,
				3
			)
		end
	)

m1_4Track:
	GetMarkerReachedSignal(
		"Hit"
	):
	Connect(
		function()
			onHitMarker(
				m1_4Track,
				4
			)
		end
	)

m1_5Track:
	GetMarkerReachedSignal(
		"Hit"
	):
	Connect(
		function()
			onHitMarker(
				m1_5Track,
				5
			)
		end
	)


-- =========================
-- LUNGE DIRECT HANDOFF
-- =========================

local LUNGE_BINDABLE_NAME =
	"LungeTryStart"

local lastMissingLungeEndpointWarn =
	-math.huge

local MISSING_LUNGE_ENDPOINT_WARN_INTERVAL =
	1.0

local LAUNCHER_BINDABLE_NAME =
	"LauncherTryStart"

local lastMissingLauncherEndpointWarn =
	-math.huge

local MISSING_LAUNCHER_ENDPOINT_WARN_INTERVAL =
	1.0

local AERIAL_KICK_BINDABLE_NAME =
	"AerialKickTryStart"

local lastMissingAerialKickEndpointWarn =
	-math.huge

local MISSING_AERIAL_KICK_ENDPOINT_WARN_INTERVAL =
	1.0


local function tryStartLauncherFromMouse1(): boolean

	local endpoint =
		character:
		FindFirstChild(
			LAUNCHER_BINDABLE_NAME
		)

	if not endpoint
		or not endpoint:
		IsA(
			"BindableFunction"
		) then

		if time()
			- lastMissingLauncherEndpointWarn >=
				MISSING_LAUNCHER_ENDPOINT_WARN_INTERVAL then

			lastMissingLauncherEndpointWarn =
				time()

			-- This is intentionally only a warning while Ctrl is held.
			-- Normal Mouse1 should not spam Output if Launcher is temporarily
			-- absent during installation.
			if UserInputService:IsKeyDown(
				Enum.KeyCode.LeftControl
				)
					or UserInputService:IsKeyDown(
						Enum.KeyCode.RightControl
					) then

				warn(
					"[AttackController] LauncherTryStart endpoint MISSING"
				)
			end
		end

		return false
	end

	local ok,
		consumed =
		pcall(
			function()

				return endpoint:
				Invoke()
			end
		)

	if not ok then

		warn(
			"[AttackController] LauncherTryStart invoke failed:",
			consumed
		)

		return false
	end

	return consumed ==
		true
end


local function tryStartAerialKickFromMouse1(): boolean

	-- AttackController already owns the authoritative local Mouse1 routing.
	-- Only hand the click to AerialKick while Humanoid is in a real airborne
	-- state. Do NOT use FloorMaterial here; custom movement can report Air for
	-- isolated frames while the character is physically grounded.
	if not isAirborne() then
		return false
	end

	local endpoint =
		character:
		FindFirstChild(
			AERIAL_KICK_BINDABLE_NAME
		)

	if not endpoint
		or not endpoint:IsA("BindableFunction") then

		-- Only warn while actually airborne; otherwise this endpoint is irrelevant.
		if isAirborne()
			and time() - lastMissingAerialKickEndpointWarn >=
			MISSING_AERIAL_KICK_ENDPOINT_WARN_INTERVAL then

			lastMissingAerialKickEndpointWarn =
				time()

			warn(
				"[AttackController] AerialKickTryStart endpoint MISSING"
			)
		end

		return false
	end

	local ok,
		consumed =
		pcall(
			function()
				return endpoint:Invoke()
			end
		)

	if not ok then
		warn(
			"[AttackController] AerialKickTryStart invoke failed:",
			consumed
		)

		return false
	end

	return consumed == true
end


local function tryStartLungeFromMouse1(): boolean

	local endpoint =
		character:
		FindFirstChild(
			LUNGE_BINDABLE_NAME
		)

	if not endpoint
		or not endpoint:
		IsA(
			"BindableFunction"
		) then

		if time()
			- lastMissingLungeEndpointWarn >=
				MISSING_LUNGE_ENDPOINT_WARN_INTERVAL then

			lastMissingLungeEndpointWarn =
				time()

			warn(
				"[AttackController] LungeTryStart endpoint MISSING",
				"| Lunge controller did not initialize or was destroyed"
			)
		end

		return false
	end

	local ok,
		started =
		pcall(
			function()

				return endpoint:
				Invoke()
			end
		)

	if not ok then

		warn(
			"[AttackController] LungeTryStart invoke failed:",
			started
		)

		return false
	end

	return started ==
		true
end


-- =========================
-- INPUT
-- =========================

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)

			if gameProcessed then
				return
			end

			if UserInputService:
				GetFocusedTextBox() then
				return
			end

			if input.UserInputType ~=
				Enum.UserInputType.MouseButton1 then
				return
			end

			-- AttackController remains the single Mouse1 owner.
			--
			-- Priority:
			-- 1) Ctrl + Mouse1 -> Launcher
			-- 2) existing eligible Lunge
			-- 3) real airborne Mouse1 -> Dedicated Aerial Spin Kick
			--    (except Launcher AirCombo, which keeps its dedicated Air M1s)
			-- 4) fallback -> normal M1
			--
			-- Lunge intentionally gets first refusal so this new system can
			-- never regress the already-approved grounded sprint attack.
			--
			-- LauncherTryStart returns TRUE when Ctrl+Mouse1 should be consumed,
			-- even when Launcher itself is on cooldown/blocked. This prevents an
			-- accidental normal M1/Lunge from firing underneath the special input.
			if tryStartLauncherFromMouse1() then

				return
			end

			if tryStartLungeFromMouse1() then

				return
			end

			if tryStartAerialKickFromMouse1() then

				return
			end

			startAttack()
		end
	)


-- =========================
-- CANCEL
-- =========================

local function cancelCurrentAttack()

	if not isAttacking then
		return
	end

	currentAttackCancelled = true

	local cancelledCombo =
		currentComboIndex

	endAttack(
		attackSequence,
		0.05,
		false
	)

	-- If the finisher itself was interrupted, do not punish the player with
	-- the completed-combo restart lock.
	if cancelledCombo == 5 then
		fullComboCooldownToken += 1
		fullComboLockedUntil = -math.huge

		character:SetAttribute(
			"M1ComboCooldownActive",
			false
		)

		character:SetAttribute(
			"M1ComboCooldownEndsAt",
			nil
		)
	end

	resetCombo()
end


-- =========================
-- LAUNCHER AIR COMBO SYNC
-- =========================
-- A Launcher aerial string is a fresh combat chain. It must not inherit a
-- partially completed grounded combo (for example M1_3) because the server
-- correctly expects a fresh M1_1 after the Launcher handoff.
local launcherAirM1WasActive = false

local function clearFullComboRestartLockForLauncherAir()
	fullComboCooldownToken += 1
	fullComboLockedUntil = -math.huge

	character:SetAttribute(
		"M1ComboCooldownActive",
		false
	)

	character:SetAttribute(
		"M1ComboCooldownEndsAt",
		nil
	)
end

local function syncLauncherAirComboState()
	local activeNow =
		isLauncherAirM1Context()

	if activeNow
		and not launcherAirM1WasActive then

		if isAttacking then
			cancelCurrentAttack()
		else
			resetCombo()
		end

		clearFullComboRestartLockForLauncherAir()
		launcherAirComboIndex = 1

		character:SetAttribute(
			"M1ComboIndex",
			launcherAirComboIndex
		)

		if DEBUG_ATTACK then
			print(
				"[M1-Client] Launcher air combo armed",
				"fresh=M1_1"
			)
		end
	elseif not activeNow
		and launcherAirM1WasActive then

		launcherAirComboIndex = 1

		-- AIR END can arrive while M1_5 is still locally playing. This happens
		-- legitimately when the server confirms M1_5 via its StartFailsafe and
		-- ends the Launcher before Roblox fires the local M1_5 marker/Stopped.
		--
		-- Previously that left isAttacking/IsAttacking and the M1 movement cap
		-- alive indefinitely. Dash appeared to "fix" the character only because
		-- the IsDashing listener calls cancelCurrentAttack(). AIR END itself must
		-- own this cleanup instead.
		local hadLiveAirAttack = isAttacking

		for pendingTrack in pairs(launcherAirPendingHitByTrack) do
			launcherAirPendingHitByTrack[pendingTrack] = nil
		end

		if hadLiveAirAttack then
			cancelCurrentAttack()
		else
			-- Defensive normalization for any attribute/local-state mismatch.
			stopAllM1Tracks(0.03)
			clearM1MovementCap()
			resetCombo()

			character:SetAttribute(
				"IsAttacking",
				false
			)
			character:SetAttribute(
				"AttackPhase",
				"None"
			)
			character:SetAttribute(
				"ActiveM1",
				nil
			)
		end

		if DEBUG_ATTACK then
			print(
				"[M1-Client] Launcher air combo released",
				hadLiveAirAttack
					and "forced-active-M1-cleanup"
					or "clean"
			)
		end
	end

	launcherAirM1WasActive =
		activeNow
end

for _, airAttributeName in ipairs({
	"AirM1Allowed",
	"LauncherAirComboAttacker",
	"AirComboRole",
	"AirComboActive",
	}) do
	character:
		GetAttributeChangedSignal(
			airAttributeName
		):
		Connect(
			syncLauncherAirComboState
		)
end


character:
	GetAttributeChangedSignal(
		"CombatMode"
	):
	Connect(
		function()
			if character:GetAttribute(
				"CombatMode"
				) ~= true then

				cancelCurrentAttack()
				resetCombo()
			end
		end
	)

character:
	GetAttributeChangedSignal(
		"CombatSuppressed"
	):
	Connect(
		function()
			if character:GetAttribute(
				"CombatSuppressed"
				) == true then

				cancelCurrentAttack()
			end
		end
	)

for _, statusBlockAttribute in ipairs({
	"IsStunned",
	"Status_AttackBlocked",
	"Status_Stunned",
	}) do
	character:
		GetAttributeChangedSignal(
			statusBlockAttribute
		):
		Connect(
			function()
				if character:GetAttribute(
					statusBlockAttribute
					) == true then

					cancelCurrentAttack()
				end
			end
		)
end

character:
	GetAttributeChangedSignal(
		"IsDashing"
	):
	Connect(
		function()
			if character:GetAttribute(
				"IsDashing"
				) == true then

				cancelCurrentAttack()
			end
		end
	)


character:
	GetAttributeChangedSignal(
		"TreeJumpActive"
	):
	Connect(
		function()
			if character:GetAttribute(
				"TreeJumpActive"
				) == true then

				cancelCurrentAttack()
			end
		end
	)

character:
	GetAttributeChangedSignal(
		"IsTreeJumping"
	):
	Connect(
		function()
			if character:GetAttribute(
				"IsTreeJumping"
				) == true then

				cancelCurrentAttack()
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

	character:
		GetAttributeChangedSignal(
			attributeName
		):
		Connect(
			function()

				if isDownedSystemLocked() then
					cancelCurrentAttack()
					resetCombo()
				end
			end
		)
end


humanoid.Died:
	Connect(
		function()

			cancelCurrentAttack()
			resetCombo()
		end
	)


script.Destroying:
	Connect(
		function()

			cancelCurrentAttack()
			clearM1MovementCap()


			stopAllM1Tracks(0)

			for _, animation in pairs(
				m1Animations
				) do

				animation:
				Destroy()
			end
		end
	)


print(
	"[AttackController] READY v4.6 WeaponProfiles+SafeAerialKickHandoff"
		.. " | WeaponSwingProfile=ON | 5HitCombo=ON"
		.. " | MarkerDrivenM1_1_5=ON"
		.. " | LegacyM1_4RootMotion=OFF"
		.. " | AgileMovementCaps=ON"
		.. " | SprintToM1=ON"
		.. " | FullComboCooldown=1.10"
		.. " | LungeInputHandoff=ON | LauncherInputHandoff=ON | AerialKickHandoff=ON | Ctrl+M1=Launcher | LauncherAirM1=HOLD_ONLY_DEDICATED_1_TO_5 | AirMarkerInstanceBinding=ON | AirMarkerStoppedFallback=ON | AirEndForcedM1Cleanup=ON | GroundM1_5InstanceBinding=ON | GroundM1_5StoppedFallback=ON | StatusCombatGate=ON"
)
