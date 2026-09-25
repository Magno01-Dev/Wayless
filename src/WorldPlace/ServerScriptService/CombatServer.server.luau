--!strict
-- CombatServer v24.19 - WeaponProfile M1 Integration + StatusCombatModifiers
-- ServerScriptService > CombatServer
--
-- Built directly from uploaded v20.2 stable source.
--
-- Preserved:
-- - DamageService / Armor gateway
-- - Motion Compensation / pose history
-- - Block / Guard / Guard Break
-- - ComboCounterService
-- - Substitution priority
-- - Downed / Mission NPC exclusions
-- - server-confirmed impact VFX
-- - general M1 hitstun duration (0.40) is NOT rebalanced in this phase
--
-- Phase 1:
-- - Server combo contract expanded from 4 -> 5 M1s.
-- - M1_1-M1_5 all resolve from the authored client "Hit" marker timestamp.
-- - Legacy M1_4 frame-46 scheduled impact is removed.
-- - Heavy finisher treatment moves from M1_4 -> M1_5.
-- - M1_5 gets short physical R6 ragdoll + moderate knockback/tumble.
-- - Ragdoll is skipped when DamageService already transitions the target Downed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local DamageService =
	require(
		script.Parent:
		WaitForChild("DamageService")
	)

local WeaponCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"WeaponCatalog"
		)
	)

local StatusCombatModifierService =
	require(
		script.Parent:
		WaitForChild("Services"):
		WaitForChild("StatusCombatModifierService")
	)

local ComboCounterService =
	require(
		script.Parent:
		WaitForChild(
			"ComboCounterService"
		)
	)

local combatRemotes =
	ReplicatedStorage:
	FindFirstChild("CombatRemotes")

if not combatRemotes then
	combatRemotes = Instance.new("Folder")
	combatRemotes.Name = "CombatRemotes"
	combatRemotes.Parent = ReplicatedStorage
end

local m1Request =
	combatRemotes:
	FindFirstChild("M1Request")

if not m1Request then
	m1Request = Instance.new("RemoteEvent")
	m1Request.Name = "M1Request"
	m1Request.Parent = combatRemotes
end

local lungeRequest =
	combatRemotes:
	FindFirstChild("LungeRequest")

if not lungeRequest then
	lungeRequest = Instance.new("RemoteEvent")
	lungeRequest.Name = "LungeRequest"
	lungeRequest.Parent = combatRemotes
end

local aerialKickEvent =
	combatRemotes:
	FindFirstChild("AerialKickEvent")

if not aerialKickEvent then
	aerialKickEvent = Instance.new("RemoteEvent")
	aerialKickEvent.Name = "AerialKickEvent"
	aerialKickEvent.Parent = combatRemotes
end

local blockRequest =
	combatRemotes:
	FindFirstChild("BlockRequest")

if not blockRequest then
	blockRequest = Instance.new("RemoteEvent")
	blockRequest.Name = "BlockRequest"
	blockRequest.Parent = combatRemotes
end

local blockImpact =
	combatRemotes:
	FindFirstChild("BlockImpact")

if not blockImpact then
	blockImpact = Instance.new("RemoteEvent")
	blockImpact.Name = "BlockImpact"
	blockImpact.Parent = combatRemotes
end

local blockBreak =
	combatRemotes:
	FindFirstChild("BlockBreak")

if not blockBreak then
	blockBreak = Instance.new("RemoteEvent")
	blockBreak.Name = "BlockBreak"
	blockBreak.Parent = combatRemotes
end


local combatImpactVFX =
	combatRemotes:
	FindFirstChild("CombatImpactVFX")

if not combatImpactVFX then
	combatImpactVFX = Instance.new("RemoteEvent")
	combatImpactVFX.Name = "CombatImpactVFX"
	combatImpactVFX.Parent = combatRemotes
end


-- TEMPORARY QA REMOTE.
-- Remove/disable after hitbox tuning is approved.
local hitboxDebugEvent =
	combatRemotes:
	FindFirstChild(
		"CombatHitboxDebug"
	)

if not hitboxDebugEvent then

	hitboxDebugEvent =
		Instance.new(
			"RemoteEvent"
		)

	hitboxDebugEvent.Name =
		"CombatHitboxDebug"

	hitboxDebugEvent.Parent =
		combatRemotes
end


local DEBUG_HITBOX_VISUALS =
	true

local DEBUG_HITBOX_LIFETIME =
	0.22


local function emitHitboxDebug(
	kind: string,
	label: string,
	boxCFrame: CFrame,
	boxSize: Vector3
)

	if not DEBUG_HITBOX_VISUALS then
		return
	end

	(hitboxDebugEvent :: RemoteEvent):
		FireAllClients(
			kind,
			label,
			boxCFrame,
			boxSize,
			DEBUG_HITBOX_LIFETIME
		)
end


-- =========================
-- M1 SETTINGS
-- =========================

-- PvP baseline:
-- 5 basic hits = 25 raw damage per complete combo before armor.
-- Finisher power comes from separation/control rather than bonus damage.
local M1_DAMAGE = 5
local M1_5_DAMAGE = 5

local M1_ARMOR_PROFILE = {
	Penetration = 0,
	DurabilityDamage = 1.00,
}

-- M1_5 physical finisher tuning.
-- Start moderate; balance after real PvP QA.
-- Stronger, readable finisher.
-- Long enough to visibly collapse/roll, short enough to return to combat.
local M1_5_KNOCKBACK_HORIZONTAL_SPEED = 46
local M1_5_KNOCKBACK_VERTICAL_SPEED = 8
local M1_5_RAGDOLL_DURATION = 0.95
local M1_5_RAGDOLL_LOCK_DURATION = 1.05

local MAX_ANIMATION_START_CLOCK_ERROR = 0.40
-- IMPORTANT:
-- Client remains authoritative for FEEL:
--   MIN_LOCAL_ATTACK_INTERVAL = 0.40
--   COMBO_RESET_WINDOW = 1.20
--   FULL_COMBO_RESTART_LOCK = 1.10
--
-- Server validation is intentionally a little more permissive to absorb
-- RemoteEvent jitter/batching. Exact client/server equality was causing a
-- valid local attack to occasionally arrive a few ms "too early", rejecting
-- that Start and desynchronizing the remaining combo numbers.
local SERVER_COMBO_SEQUENCE_WINDOW = 1.35

-- Client waits 1.10; server only needs to reject obvious early restart spam.
local SERVER_FULL_COMBO_RESTART_LOCK = 1.00

-- v18: deliberately tiny increase only.
-- FORWARD MELEE RECTANGLE
-- Rear face begins ~1 stud in front of HRP.
local HITBOX_SIZE =
	Vector3.new(
		7.5,
		5.5,
		9.0
	)

local HITBOX_FORWARD_OFFSET = 5.5

local MIN_HIT_TIME = 0.10
local MAX_HIT_TIME = 0.70
-- Client enforces 0.40. Server allows a small packet-jitter tolerance.
local MIN_SERVER_ATTACK_INTERVAL = 0.32


-- =========================
-- WEAPON M1 PROFILE
-- =========================
--
-- Existing CombatServer remains the ONLY M1 damage authority.
-- WeaponCombatServer is obsolete once this integration is installed.
--
-- An equipped weapon only overrides the grounded M1 profile while it is
-- actually Drawn. Holstered/no weapon preserves the canonical unarmed values.

local function getDrawnWeaponDefinition(
	character: Model
): any?

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


local function resolveGroundM1Damage(
	character: Model,
	comboNumber: number
): (number, string?)

	local defaultDamage =
		if comboNumber == 5
		then M1_5_DAMAGE
		else M1_DAMAGE

	local definition =
		getDrawnWeaponDefinition(
			character
		)

	if not definition
		or typeof(
			definition.Combat
		) ~= "table" then

		return defaultDamage,
			nil
	end

	local configuredDamage =
		definition.Combat.Damage

	if typeof(configuredDamage)
		~= "number" then

		return defaultDamage,
			tostring(
				definition.Id
			)
	end

	return math.max(
		0,
		configuredDamage
	),
		tostring(
			definition.Id
		)
end


local function resolveServerAttackInterval(
	character: Model
): number

	local definition =
		getDrawnWeaponDefinition(
			character
		)

	if not definition
		or typeof(
			definition.Combat
		) ~= "table" then

		return MIN_SERVER_ATTACK_INTERVAL
	end

	local swingInterval =
		definition.Combat.SwingInterval

	if typeof(swingInterval)
		~= "number" then

		return MIN_SERVER_ATTACK_INTERVAL
	end

	-- Client interval is the feel authority. Server keeps the same 80%
	-- jitter tolerance as the 0.40 -> 0.32 unarmed baseline.
	return math.max(
		0.10,
		swingInterval * 0.80
	)
end

-- Launcher air is a server-established 1v1 pair. The authored marker remains
-- primary, but a committed aerial Start gets a server failsafe so a marker
-- callback/packet race can never erase a legitimate strike.
local LAUNCHER_AIR_HIT_FAILSAFE_DELAY = 0.34
local LAUNCHER_AIR_MIN_START_INTERVAL = 0.30
local LAUNCHER_AIR_MIN_CONFIRMED_HIT_INTERVAL = 0.16


-- =========================
-- LUNGE / RUNNING ATTACK
-- =========================

local LUNGE_DAMAGE = 7

local LUNGE_ARMOR_PROFILE = {
	Penetration = 0,
	DurabilityDamage = 1.00,
}

-- Client cooldown is 3.00s.
-- Server is only 0.10s tolerant for packet/order jitter; the visible/player
-- cooldown remains the full 3.00s on the client.
local LUNGE_SERVER_COOLDOWN = 2.90

-- Client requires 24. Replicated velocity may lag a little in PvP.
local LUNGE_MIN_SERVER_HORIZONTAL_SPEED = 18
local LUNGE_MIN_SERVER_FORWARD_DOT = 0.05

-- Water Walk is maintained by client-owned surface constraints and its
-- replicated HRP velocity can momentarily lag/flatten at Lunge Start.
-- On server-confirmed Water Walk, require forward movement intent instead of
-- the terrestrial 18-stud replicated-speed gate.
local LUNGE_MIN_SERVER_WATER_MOVE_DOT = 0.25
local LUNGE_MIN_SERVER_WATER_HORIZONTAL_SPEED = 5.0

-- Marker timestamps remain authoritative for opening/closing the authored
-- attack window. Values are broad server sanity bounds, not animation timing.
local LUNGE_MIN_DAMAGE_MARKER_TIME = 0.03
local LUNGE_MAX_DAMAGE_MARKER_TIME = 1.70

-- Clash remains foundation only in this phase. The markers are now wired
-- server-side so a future resolver can consume the active window directly.
local LUNGE_MIN_CLASH_MARKER_TIME = 0.02
local LUNGE_MAX_CLASH_MARKER_TIME = 1.70

-- MOVING FORWARD DAMAGE RECTANGLE
--
-- User-facing target:
-- ~2 R6 characters wide and ~4 characters deep.
--
-- Rear face begins ~1 stud in front of the attacker so the attack cannot wrap
-- behind them. The box follows the attacker's HumanoidRootPart throughout the
-- DamageStart -> DamageEnd window.
local LUNGE_HITBOX_SIZE =
	Vector3.new(
		10.0,
		6.5,
		16.0
	)

local LUNGE_HITBOX_FORWARD_OFFSET = 9.0
local LUNGE_HITBOX_VERTICAL_OFFSET = -0.25

-- Server sweep sampling prevents tunneling if replication advances the
-- attacker several studs between Heartbeats.
local LUNGE_SWEEP_STEP_STUDS = 3.0
local LUNGE_SWEEP_MAX_STEPS = 10
local LUNGE_DAMAGE_WINDOW_HARD_TIMEOUT = 1.75

local LUNGE_HISTORY_TARGET_PADDING =
	Vector3.new(
		1.10,
		1.35,
		1.00
	)


-- Blocks an impossible immediate M1 overlap, but is shorter than the authored
-- Lunge animation so Lunge -> M1_1 remains responsive after recovery.
local LUNGE_MIN_M1_FOLLOWUP_TIME = 0.34


-- =========================
-- DEDICATED AERIAL AXE KICK
-- =========================

local AERIAL_KICK_DAMAGE = 9

local AERIAL_KICK_ARMOR_PROFILE = {
	Penetration = 0,
	DurabilityDamage = 1.00,
}

-- Axe Kick is pressure, not a space-maker. Keep only a modest physical push.
local AERIAL_KICK_KNOCKBACK_HORIZONTAL_SPEED = 18
local AERIAL_KICK_KNOCKBACK_VERTICAL_SPEED = 0

-- Guard pressure stays high, but blocked physical displacement is small.
local AERIAL_KICK_BLOCK_KNOCKBACK_SPEED = 10
local AERIAL_KICK_GUARD_BREAK_KNOCKBACK_SPEED = 18

-- High guard pressure preserved from the Spin Kick prototype.
local AERIAL_KICK_GUARD_DAMAGE = 40

local AERIAL_KICK_HITSTUN_DURATION = 0.24

local AERIAL_KICK_SERVER_COOLDOWN = 2.60
local AERIAL_KICK_STATE_TIMEOUT = 2.75

local AERIAL_KICK_HITBOX_SIZE =
	Vector3.new(
		7.0,
		7.5,
		7.0
	)

-- Axe Kick volume sits mostly BELOW the attacker rather than far in front.
local AERIAL_KICK_HITBOX_FORWARD_OFFSET = 1.25
local AERIAL_KICK_HITBOX_VERTICAL_OFFSET = -2.60

-- These validate when the authored Hit marker STARTS the contact phase.
-- Actual physical contact may occur later during the dive.
local AERIAL_KICK_MIN_HIT_TIME = 0.04
local AERIAL_KICK_MAX_HIT_TIME = 1.55

local AERIAL_KICK_CONTACT_MONITOR_MAX_DURATION = 0.90
local AERIAL_KICK_GROUND_RELEASE_DISTANCE = 4.25
local AERIAL_KICK_GROUND_RAY_DISTANCE = 12.0


-- =========================
-- MOTION COMPENSATION
-- =========================
--
-- We keep only a tiny history window. The client never sends a target or a
-- position; it only stamps authored Lunge marker times using
-- Workspace:GetServerTimeNow().
--
-- The server still decides:
-- - whether an attack exists
-- - combo order
-- - timing legality
-- - which target was inside the hitbox
-- - LOS / Block / damage
--
-- Historical compensation is only used for player-vs-player detection.
-- NPCs/dummies continue to use the normal physical overlap.

local M1_HISTORY_DURATION = 0.35
local M1_HISTORY_SAMPLE_INTERVAL = 1 / 60
local M1_MAX_REWIND = 0.18
local M1_FUTURE_TIMESTAMP_TOLERANCE = 0.035

-- Approximate R6 body allowance around the historical HumanoidRootPart.
-- This is intentionally conservative because the broad hitbox itself is
-- already forgiving.
local M1_HISTORY_TARGET_PADDING =
	Vector3.new(
		1.20,
		2.30,
		1.20
	)


-- =========================
-- AUDIO
-- =========================

local M1_SWING_SOUND_ID =
	"rbxassetid://138208560796742"

local M1_HIT_SOUND_ID =
	"rbxassetid://139119371910120"

local BLOCK_IMPACT_SOUND_ID =
	"rbxassetid://136811265205147"

local SWING_SOUND_DELAY = 0.10

local SWING_SOUND_VOLUME = 0.70
local HIT_SOUND_VOLUME = 0.85
local BLOCK_IMPACT_SOUND_VOLUME = 0.90

local SOUND_ROLLOFF_MAX_DISTANCE = 65


-- =========================
-- BLOCK / GUARD
-- =========================

local BLOCK_FRONT_DOT = 0.45

local GUARD_MAX = 100
local M1_GUARD_DAMAGE = 20
local M1_5_GUARD_DAMAGE = 30

local GUARD_REGEN_DELAY = 2.0
local GUARD_REGEN_RATE = 25.0

local GUARD_BREAK_STUN_DURATION = 0.85
local GUARD_BREAK_LOCK_DURATION = 3.0


-- =========================
-- HITSTUN
-- =========================

local M1_HIT_REACTION_ANIMATION_ID =
	"rbxassetid://83584048560435"

-- Required polish change.
local M1_HITSTUN_DURATION = 0.40

local M1_HIT_REACTION_SPEED = 1.0
local M1_HIT_REACTION_FADE_IN = 0.02
local M1_HIT_REACTION_FADE_OUT = 0.05


local DEBUG_M1 = true

print(
	"[CombatServer] READY v24.19 WeaponProfiles+StatusCombatModifiers"
		.. " | 5HitCombo=ON"
		.. " | MarkerDrivenM1_1_5=ON"
		.. " | M1_5PhysicalFinisher=ON"
		.. " | Hitstun0.40=PRESERVED"
		.. " | MotionComp=ON"
		.. " | Hitbox4.7=ON"
		.. " | FullComboCooldown=1.10"
		.. " | WeaponM1Damage=ON | WeaponSwingInterval=ON | MinAttackInterval=PROFILED"
		.. " | RunningLunge=ON"
		.. " | LungeDamage=DamageStart->DamageEnd"
		.. " | LungeMovingSweep=ON"
		.. " | LungeSingleHitPerTarget=ON"
		.. " | LungeBaseDamage="
		.. tostring(
			LUNGE_DAMAGE
		)
		.. " | LungeServerCooldown="
		.. tostring(
			LUNGE_SERVER_COOLDOWN
		)
		.. "s"
		.. " | LungeClashFoundation=MARKER_WIRED | WaterLungeHandshake=CLIENT_FLAG+SERVER_WATER_RAY | WaterLungeLOS=IGNORE_TERRAIN_WATER"
		.. " | TEMP_HitboxDebug=ON"
		.. " | M1Box=ForwardRect"
		.. " | LungeBox=10x6.5x16 | AerialAxeKick=PURE_VERTICAL Damage9 KB18 Guard40 WallImpact=OFF HitVFX=HeavyHit5_Shoot01 BlockVFX=SharedCurrent BreakVFX=SharedCurrent HitFreeze=TARGET_OR_GROUND_OR_0.90s | LauncherAirM1Sequence=HIT_CONFIRMED_1_TO_5 | LauncherAirPairHit=SERVER_AUTHORITATIVE | AirMarkerFailsafe=ON | AirHitBackfill=ON | M1_5EndsAir=ON"
)



-- =========================
-- STATE
-- =========================

local attackStates = {}
local blockStates = {}
local serverComboStates = {}

-- Launcher aerial M1 has its own server sequence keyed by AirComboId. It never
-- consumes or inherits grounded combo state.
local launcherAirM1States = {}

local lungeStates = {}
local lungeCooldownUntil = {}

local aerialKickStates = {}
local aerialKickCooldownUntil = {}

type GuardState = {
	value: number,
	lastDamageAt: number,
	brokenUntil: number,
	lastReplicatedValue: number,
}

type PoseSample = {
	t: number,
	cf: CFrame,
}

local guardStates: {[Player]: GuardState} = {}

local stunVersions =
	setmetatable(
		{},
		{
			__mode = "k",
		}
	)

local hitReactionTracks =
	setmetatable(
		{},
		{
			__mode = "k",
		}
	)

local poseHistories: {[Model]: {PoseSample}} =
	setmetatable(
		{},
		{
			__mode = "k",
		}
	)


-- =========================
-- CHARACTER HELPERS
-- =========================

local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?, BasePart?)

	local character = player.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid =
		character:
		FindFirstChildOfClass("Humanoid")

	local rootPart =
		character:
		FindFirstChild("HumanoidRootPart")

	if not humanoid
		or humanoid.Health <= 0
		or not rootPart
		or not rootPart:IsA("BasePart") then

		return nil, nil, nil
	end

	return character, humanoid, rootPart
end


local function getTargetCharacterFromPart(
	part: Instance
): (Model?, Humanoid?, BasePart?)

	local current: Instance? = part

	while current
		and current ~= workspace do

		if current:IsA("Model") then
			local humanoid =
				current:
				FindFirstChildOfClass("Humanoid")

			local rootPart =
				current:
				FindFirstChild("HumanoidRootPart")

			if humanoid
				and rootPart
				and rootPart:IsA("BasePart") then

				return current,
					humanoid,
					rootPart
			end
		end

		current = current.Parent
	end

	return nil, nil, nil
end


local function canReceiveM1Hit(
	targetCharacter: Model
): boolean

	if targetCharacter:GetAttribute(
		"IsMissionNPC"
		) == true then
		return false
	end

	if targetCharacter:GetAttribute(
		"IsBeingExecuted"
		) == true then
		return false
	end

	-- M1_5 creates separation/reset instead of a free grounded extension.
	-- During the short physical finisher, normal M1s cannot re-catch the victim.
	if targetCharacter:GetAttribute(
		"CombatRagdolled"
		) == true then
		return false
	end

	-- Executor remains hittable so an enemy can cancel the Execute.
	if targetCharacter:GetAttribute(
		"IsExecuting"
		) == true then
		return true
	end

	if targetCharacter:GetAttribute(
		"DownedActionLocked"
		) == true then
		return false
	end

	if targetCharacter:GetAttribute(
		"IsDowned"
		) == true then
		return false
	end

	if targetCharacter:GetAttribute(
		"IsCarried"
		) == true then
		return false
	end

	return true
end


local function buildLOSExclusions(
	attackerCharacter: Model,
	targetCharacter: Model?
): {Instance}

	local exclusions: {Instance} = {
		attackerCharacter,
	}

	if targetCharacter then
		table.insert(
			exclusions,
			targetCharacter
		)
	end

	local missionNPCs =
		workspace:
		FindFirstChild("Missions NPC")

	if missionNPCs then
		table.insert(
			exclusions,
			missionNPCs
		)
	end

	return exclusions
end


local function hasLiveLineOfSight(
	attackerCharacter: Model,
	targetCharacter: Model,
	attackerRoot: BasePart,
	targetRoot: BasePart,
	ignoreWater: boolean?
): boolean

	local direction =
		targetRoot.Position
	- attackerRoot.Position

	if direction.Magnitude < 0.01 then
		return true
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	-- Preserve the original behavior for live overlap:
	-- target itself is NOT excluded; hitting its body counts as clear LOS.
	local exclusions: {Instance} = {
		attackerCharacter,
	}

	local missionNPCs =
		workspace:
		FindFirstChild("Missions NPC")

	if missionNPCs then
		table.insert(
			exclusions,
			missionNPCs
		)
	end

	params.FilterDescendantsInstances =
		exclusions

	params.IgnoreWater =
		ignoreWater == true

	local hit =
		workspace:
		Raycast(
			attackerRoot.Position,
			direction,
			params
		)

	if not hit then
		return true
	end

	return hit.Instance:
		IsDescendantOf(
			targetCharacter
		)
end


local function hasHistoricalLineOfSight(
	attackerCharacter: Model,
	targetCharacter: Model,
	attackerPosition: Vector3,
	targetPosition: Vector3,
	ignoreWater: boolean?
): boolean

	local direction =
		targetPosition
	- attackerPosition

	if direction.Magnitude < 0.01 then
		return true
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	-- For historical positions both live character models are excluded.
	-- Static world geometry still blocks the ray.
	params.FilterDescendantsInstances =
		buildLOSExclusions(
			attackerCharacter,
			targetCharacter
		)

	params.IgnoreWater =
		ignoreWater == true

	local hit =
		workspace:
		Raycast(
			attackerPosition,
			direction,
			params
		)

	return hit == nil
end


-- =========================
-- POSE HISTORY
-- =========================

local function recordPose(
	character: Model,
	rootPart: BasePart,
	now: number
)
	local history =
		poseHistories[
	character
	]

	if not history then
		history = {}
		poseHistories[
		character
		] = history
	end

	table.insert(
		history,
		{
			t = now,
			cf = rootPart.CFrame,
		}
	)

	local cutoff =
		now
	- M1_HISTORY_DURATION

	while #history > 2
		and history[1].t < cutoff do

		table.remove(
			history,
			1
		)
	end
end


local function getPoseAt(
	character: Model,
	targetTime: number
): CFrame?

	local history =
		poseHistories[
	character
	]

	if not history
		or #history == 0 then

		return nil
	end

	if #history == 1 then
		return history[1].cf
	end

	if targetTime <=
		history[1].t then

		return history[1].cf
	end

	for index = 2,
		#history do

		local previous =
			history[
		index - 1
		]

		local current =
			history[
		index
		]

		if targetTime <=
			current.t then

			local span =
				current.t
			- previous.t

			if span <= 0.0001 then
				return current.cf
			end

			local alpha =
				math.clamp(
					(
						targetTime
						- previous.t
					)
					/ span,
					0,
					1
				)

			return previous.cf:
				Lerp(
					current.cf,
					alpha
				)
		end
	end

	return history[
	#history
	].cf
end


local poseHistoryAccumulator = 0

RunService.Heartbeat:Connect(
	function(
		deltaTime: number
	)

		poseHistoryAccumulator +=
			deltaTime

		if poseHistoryAccumulator <
			M1_HISTORY_SAMPLE_INTERVAL then

			return
		end

		poseHistoryAccumulator = 0

		local now =
			workspace:
			GetServerTimeNow()

		for _, player in ipairs(
			Players:GetPlayers()
			) do

			local character,
			_humanoid,
			rootPart =
				getAliveCharacter(
					player
				)

			if character
				and rootPart then

				recordPose(
					character,
					rootPart,
					now
				)
			end
		end
	end
)


-- =========================
-- SOUND
-- =========================

local function playCombatSound(
	parentPart: BasePart?,
	soundId: string,
	volume: number,
	playbackSpeed: number?
)
	if not parentPart
		or not parentPart:IsA("BasePart") then

		return
	end

	local sound =
		Instance.new("Sound")

	sound.SoundId = soundId
	sound.Volume = volume

	sound.PlaybackSpeed =
		playbackSpeed
		or 1.0

	sound.RollOffMode =
		Enum.RollOffMode.Inverse

	sound.RollOffMaxDistance =
		SOUND_ROLLOFF_MAX_DISTANCE

	sound.Parent = parentPart
	sound:Play()

	Debris:AddItem(
		sound,
		3
	)
end


local function emitCombatImpactVFX(
	effectType: string,
	attackerPlayer: Player,
	defenderPlayer: Player?,
	attackerRoot: BasePart,
	targetRoot: BasePart,
	comboNumber: number
)
	-- v20.2 FIX:
	-- v20/v20.1 called an undefined safeUnit helper here, so execution stopped
	-- before CombatImpactVFX:FireAllClients().
	local delta =
		targetRoot.Position
	- attackerRoot.Position

	local impactDirection =
		if delta.Magnitude > 0.001
		then delta.Unit
		else attackerRoot.CFrame.LookVector

	-- v20.1:
	-- Put the effect on the TARGET SURFACE that faces the attacker instead of
	-- inside HumanoidRootPart/Torso. The previous center point was frequently
	-- hidden completely by the R6 body.
	local impactPosition =
		targetRoot.Position
	- impactDirection * 0.92
		+ Vector3.new(
			0,
			0.48,
			0
		)

	combatImpactVFX:
		FireAllClients(
			effectType,
			impactPosition,
			impactDirection,
			comboNumber,
			attackerPlayer.UserId,
			defenderPlayer
			and defenderPlayer.UserId
			or 0
		)
end


local function scheduleSwingSound(
	player: Player,
	sequence: number,
	_comboNumber: number,
	_animationStartedAt: number
)
	task.delay(
		SWING_SOUND_DELAY,
		function()

			local state =
				attackStates[
			player
			]

			if not state
				or state.sequence ~= sequence
				or state.hitUsed then

				return
			end

			local _character,
			_humanoid,
			attackerRoot =
				getAliveCharacter(
					player
				)

			if not attackerRoot then
				return
			end

			playCombatSound(
				attackerRoot,
				M1_SWING_SOUND_ID,
				SWING_SOUND_VOLUME
			)
		end
	)
end


-- =========================
-- M1_5 PHYSICAL FINISHER
-- =========================

local function projectOnPlane(
	vector: Vector3,
	normal: Vector3
): Vector3

	return vector
	- normal
		* vector:Dot(normal)
end


local function getM1_5KnockbackDirection(
	attackerCharacter: Model,
	attackerRoot: BasePart,
	targetRoot: BasePart
): Vector3?

	local away =
		targetRoot.Position
	- attackerRoot.Position


	if attackerCharacter:GetAttribute(
		"SurfaceWalking"
		) == true then

		local surfaceNormal =
			attackerCharacter:
			GetAttribute(
				"SurfaceNormal"
			)


		if typeof(surfaceNormal)
			== "Vector3"
			and surfaceNormal.Magnitude
			> 0.05 then

			away =
				projectOnPlane(
					away,
					surfaceNormal.Unit
				)


			if away.Magnitude <
				0.05 then

				away =
					projectOnPlane(
						attackerRoot.CFrame.LookVector,
						surfaceNormal.Unit
					)
			end
		end

	else

		away =
			Vector3.new(
				away.X,
				0,
				away.Z
			)


		if away.Magnitude <
			0.05 then

			local look =
				attackerRoot.CFrame.LookVector


			away =
				Vector3.new(
					look.X,
					0,
					look.Z
				)
		end
	end


	if away.Magnitude <
		0.05 then

		return nil
	end


	return away.Unit
end


-- Multiplayer-safe R6 ragdoll:
-- NEVER disable RootJoint or Neck.
--
-- The Humanoid core (HRP <-> Torso <-> Head) stays structurally intact while
-- PlatformStand + physics rotates/drops that core naturally.
-- Arms/legs are the only Motor6Ds converted to temporary BallSockets.
--
-- This avoids the R6 death/replication race that can occur when Neck or
-- RootJoint is physically disconnected during a live multiplayer character.
local R6_RAGDOLL_MOTOR_NAMES = {
	["Right Shoulder"] = true,
	["Left Shoulder"] = true,
	["Right Hip"] = true,
	["Left Hip"] = true,
}


local R6_RAGDOLL_COLLIDABLE_PARTS = {
	-- Head intentionally keeps its original collision state because Neck stays
	-- motor-connected to the Torso.
	Torso = true,
	["Right Arm"] = true,
	["Left Arm"] = true,
	["Right Leg"] = true,
	["Left Leg"] = true,
}


type RagdollMotorState = {
	motor: Motor6D,
	enabled: boolean,
}


type RagdollCollisionState = {
	part: BasePart,
	canCollide: boolean,
}


local function createRagdollConstraint(
	motor: Motor6D,
	created: {Instance}
)

	local part0 =
		motor.Part0

	local part1 =
		motor.Part1


	if not part0
		or not part1
		or not part0:IsA(
			"BasePart"
		)
			or not part1:IsA(
				"BasePart"
			) then

		return
	end


	local attachment0 =
		Instance.new(
			"Attachment"
		)

	attachment0.Name =
		"__CombatRagdollA0_"
		.. motor.Name

	attachment0.CFrame =
		motor.C0

	attachment0.Parent =
		part0


	local attachment1 =
		Instance.new(
			"Attachment"
		)

	attachment1.Name =
		"__CombatRagdollA1_"
		.. motor.Name

	attachment1.CFrame =
		motor.C1

	attachment1.Parent =
		part1


	local socket =
		Instance.new(
			"BallSocketConstraint"
		)

	socket.Name =
		"__CombatRagdollSocket_"
		.. motor.Name

	socket.Attachment0 =
		attachment0

	socket.Attachment1 =
		attachment1

	socket.LimitsEnabled =
		true

	socket.TwistLimitsEnabled =
		true


	if motor.Name ==
		"Neck" then

		socket.UpperAngle =
			35

		socket.TwistLowerAngle =
			-30

		socket.TwistUpperAngle =
			30

	elseif motor.Name ==
		"RootJoint" then

		socket.UpperAngle =
			30

		socket.TwistLowerAngle =
			-25

		socket.TwistUpperAngle =
			25

	else

		socket.UpperAngle =
			65

		socket.TwistLowerAngle =
			-55

		socket.TwistUpperAngle =
			55
	end


	socket.Parent =
		part0


	local noCollision =
		Instance.new(
			"NoCollisionConstraint"
		)

	noCollision.Name =
		"__CombatRagdollNoCollision_"
		.. motor.Name

	noCollision.Part0 =
		part0

	noCollision.Part1 =
		part1

	noCollision.Parent =
		part0


	table.insert(
		created,
		attachment0
	)

	table.insert(
		created,
		attachment1
	)

	table.insert(
		created,
		socket
	)

	table.insert(
		created,
		noCollision
	)
end


local function stopM1HitReactionForRagdoll(
	targetCharacter: Model
)
	local track =
		hitReactionTracks[
	targetCharacter
	]

	if track
		and track.IsPlaying then

		track:Stop(
			0.02
		)
	end
end


local function beginM1_5Ragdoll(
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	targetRoot: BasePart,
	defenderPlayer: Player?,
	knockbackDirection: Vector3
)

	if targetHumanoid.Health <= 0 then
		return
	end

	local healthBeforeRagdoll =
		targetHumanoid.Health

	if targetCharacter:GetAttribute(
		"CombatRagdolled"
		) == true then

		return
	end


	targetCharacter:SetAttribute(
		"CombatRagdolled",
		true
	)

	-- Take physics ownership BEFORE changing joints/state so multiplayer sees
	-- the collapse and knockback as one immediate authoritative event.
	pcall(
		function()
			targetRoot:SetNetworkOwner(
				nil
			)
		end
	)

	-- A previous M1 hit reaction can still be playing when M1_5 connects.
	-- Stop it immediately; otherwise its Action pose can visually mask the
	-- beginning of the physical collapse.
	stopM1HitReactionForRagdoll(
		targetCharacter
	)


	local oldAutoRotate =
		targetHumanoid.AutoRotate

	local oldPlatformStand =
		targetHumanoid.PlatformStand

	-- RootJoint and Neck remain enabled for the entire reaction.
	-- No RequiresNeck mutation is necessary.
	local motorStates: {RagdollMotorState} =
		{}

	local collisionStates: {RagdollCollisionState} =
		{}

	local created: {Instance} =
		{}


	for _, descendant in ipairs(
		targetCharacter:GetDescendants()
		) do

		if descendant:IsA(
			"Motor6D"
			)
				and R6_RAGDOLL_MOTOR_NAMES[
			descendant.Name
			] == true
				and descendant.Part0
				and descendant.Part1 then

			table.insert(
				motorStates,
				{
					motor =
						descendant,

					enabled =
						descendant.Enabled,
				}
			)


			createRagdollConstraint(
				descendant,
				created
			)


			descendant.Enabled =
				false
		end
	end


	for _, child in ipairs(
		targetCharacter:GetChildren()
		) do

		if child:IsA(
			"BasePart"
			) then

			table.insert(
				collisionStates,
				{
					part =
						child,

					canCollide =
						child.CanCollide,
				}
			)


			if child ==
				targetRoot then

				child.CanCollide =
					false

			elseif R6_RAGDOLL_COLLIDABLE_PARTS[
				child.Name
				] == true then

				child.CanCollide =
					true
			end
		end
	end


	targetHumanoid.AutoRotate =
		false

	targetHumanoid.PlatformStand =
		true


	pcall(
		function()

			targetHumanoid:
				ChangeState(
					Enum.HumanoidStateType.Physics
				)
		end
	)


	local currentVelocity =
		targetRoot.AssemblyLinearVelocity

	-- Diagnostic only: physical reaction must never alter Health by itself.
	-- If QA ever shows a health drop here, another damage/fall system is
	-- reacting to the physics and we will have an exact server-side trace.
	if DEBUG_M1 then
		task.delay(
			0.08,
			function()
				if targetHumanoid.Parent then
					print(
						"[M1-Server] M1_5 ragdoll health check",
						targetCharacter.Name,
						"before",
						healthBeforeRagdoll,
						"after",
						targetHumanoid.Health
					)
				end
			end
		)
	end


	local knockbackReceivedMultiplier =
		StatusCombatModifierService
		.GetKnockbackReceivedMultiplier(
			targetCharacter
		)

	targetRoot.AssemblyLinearVelocity =
		Vector3.new(
			knockbackDirection.X
			* M1_5_KNOCKBACK_HORIZONTAL_SPEED
			* knockbackReceivedMultiplier,

			math.max(
				currentVelocity.Y,
				0
			)
			+ M1_5_KNOCKBACK_VERTICAL_SPEED
			* knockbackReceivedMultiplier,

			knockbackDirection.Z
			* M1_5_KNOCKBACK_HORIZONTAL_SPEED
			* knockbackReceivedMultiplier
		)


	local torso =
		targetCharacter:
		FindFirstChild(
			"Torso"
		)


	if torso
		and torso:IsA(
			"BasePart"
		) then

		torso.AssemblyAngularVelocity =
			torso.AssemblyAngularVelocity
			+ Vector3.new(
				knockbackDirection.Z
				* 4.0,
				1.65,
				-knockbackDirection.X
				* 4.0
			)
	end


	task.delay(
		M1_5_RAGDOLL_DURATION,
		function()

			if not targetCharacter.Parent then

				return
			end


			for _, state in ipairs(
				motorStates
				) do

				if state.motor.Parent then

					state.motor.Enabled =
						state.enabled
				end
			end


			for _, instance in ipairs(
				created
				) do

				if instance.Parent then

					instance:
						Destroy()
				end
			end


			for _, state in ipairs(
				collisionStates
				) do

				if state.part.Parent then

					state.part.CanCollide =
						state.canCollide
				end
			end


			if targetHumanoid.Parent
				and targetHumanoid.Health >
				0 then

				targetHumanoid.PlatformStand =
					oldPlatformStand

				targetHumanoid.AutoRotate =
					oldAutoRotate


				if targetCharacter:GetAttribute(
					"IsDowned"
					) ~= true
						and targetCharacter:GetAttribute(
							"DownedActionLocked"
						) ~= true then

					pcall(
						function()

							targetHumanoid:
								ChangeState(
									Enum.HumanoidStateType.GettingUp
								)
						end
					)
				end
			end


			-- Mark the physical finisher over before giving character physics
			-- back to its normal network owner.
			targetCharacter:SetAttribute(
				"CombatRagdolled",
				false
			)

			pcall(
				function()

					if defenderPlayer
						and defenderPlayer.Character ==
						targetCharacter then

						targetRoot:
							SetNetworkOwner(
								defenderPlayer
							)

					else

						targetRoot:
							SetNetworkOwnershipAuto()
					end
				end
			)

			-- Motion Compensation should not interpolate across a server-owned
			-- ragdoll -> client-owned recovery discontinuity.
			poseHistories[
			targetCharacter
			] = {}

			recordPose(
				targetCharacter,
				targetRoot,
				workspace:
					GetServerTimeNow()
			)
		end
	)
end


local function applyM1_5FinisherPhysics(
	attackerCharacter: Model,
	attackerRoot: BasePart,
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	targetRoot: BasePart,
	defenderPlayer: Player?
)

	if targetHumanoid.Health <=
		0 then

		return
	end


	local direction =
		getM1_5KnockbackDirection(
			attackerCharacter,
			attackerRoot,
			targetRoot
		)


	if not direction then

		return
	end


	beginM1_5Ragdoll(
		targetCharacter,
		targetHumanoid,
		targetRoot,
		defenderPlayer,
		direction
	)
end


-- =========================
-- HIT REACTION / STUN
-- =========================

local function getHitReactionTrack(
	targetCharacter: Model
): AnimationTrack?

	local cached =
		hitReactionTracks[
	targetCharacter
	]

	if cached then
		return cached
	end

	local humanoid =
		targetCharacter:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid then
		return nil
	end

	local animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)

	if not animator then
		animator =
			Instance.new("Animator")

		animator.Parent =
			humanoid
	end

	local animation =
		Instance.new("Animation")

	animation.Name =
		"M1HitReaction"

	animation.AnimationId =
		M1_HIT_REACTION_ANIMATION_ID

	local track =
		animator:
		LoadAnimation(
			animation
		)

	animation:
		Destroy()

	track.Priority =
		Enum.AnimationPriority.Action3

	track.Looped = false

	hitReactionTracks[
	targetCharacter
	] = track

	return track
end


local function playHitReaction(
	targetCharacter: Model
)
	local track =
		getHitReactionTrack(
			targetCharacter
		)

	if not track then
		return
	end

	if track.IsPlaying then
		track:
			Stop(0)
	end

	track:
		Play(
			M1_HIT_REACTION_FADE_IN
		)

	track:
		AdjustSpeed(
			M1_HIT_REACTION_SPEED
		)
end


local function applyStun(
	targetCharacter: Model,
	duration: number,
	playReaction: boolean
)
	local humanoid =
		targetCharacter:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return
	end

	local now = time()
	local requestedEnd = now + duration
	local existingEnd = targetCharacter:GetAttribute("StunEndsAt")
	local effectiveEnd = requestedEnd

	-- Never let a short M1 hitstun shorten a longer owner lock such as the
	-- Launcher aerial victim window. New stuns may extend, never truncate.
	if typeof(existingEnd) == "number"
		and existingEnd > effectiveEnd then

		effectiveEnd = existingEnd
	end

	local version =
		(
			stunVersions[
			targetCharacter
			] or 0
		) + 1

	stunVersions[
	targetCharacter
	] = version

	targetCharacter:
		SetAttribute(
			"IsStunned",
			true
		)

	targetCharacter:
		SetAttribute(
			"StunEndsAt",
			effectiveEnd
		)

	if playReaction then
		playHitReaction(
			targetCharacter
		)
	end

	task.delay(
		math.max(0, effectiveEnd - now),
		function()

			if not targetCharacter.Parent then
				return
			end

			if stunVersions[
				targetCharacter
				] ~= version then

				return
			end

			local liveEnd = targetCharacter:GetAttribute("StunEndsAt")
			if typeof(liveEnd) == "number"
				and liveEnd > time() + 0.01 then

				return
			end

			targetCharacter:
				SetAttribute(
					"IsStunned",
					false
				)

			targetCharacter:
				SetAttribute(
					"StunEndsAt",
					nil
				)
		end
	)
end


local function applyM1Hitstun(
	targetCharacter: Model
)
	applyStun(
		targetCharacter,
		M1_HITSTUN_DURATION,
		true
	)
end


local function applyBlockBreakStun(
	targetCharacter: Model
)
	applyStun(
		targetCharacter,
		GUARD_BREAK_STUN_DURATION,
		true
	)
end


-- =========================
-- GUARD
-- =========================

local function replicateGuardState(
	player: Player,
	state: GuardState
)
	local character =
		player.Character

	if not character then
		return
	end

	local roundedValue =
		math.clamp(
			math.round(
				state.value
				* 10
			) / 10,
			0,
			GUARD_MAX
		)

	character:
		SetAttribute(
			"Guard",
			roundedValue
		)

	character:
		SetAttribute(
			"MaxGuard",
			GUARD_MAX
		)

	character:
		SetAttribute(
			"GuardBroken",
			workspace:
			GetServerTimeNow()
			< state.brokenUntil
		)

	character:
		SetAttribute(
			"GuardBrokenUntil",
			state.brokenUntil
		)

	state.lastReplicatedValue =
		roundedValue
end


local function getGuardState(
	player: Player
): GuardState

	local existing =
		guardStates[
	player
	]

	if existing then
		return existing
	end

	local state: GuardState = {
		value = GUARD_MAX,
		lastDamageAt = -math.huge,
		brokenUntil = 0,
		lastReplicatedValue = -1,
	}

	guardStates[
	player
	] = state

	replicateGuardState(
		player,
		state
	)

	return state
end


local function isGuardBreakLocked(
	player: Player
): boolean

	local state =
		getGuardState(
			player
		)

	return workspace:
		GetServerTimeNow()
		< state.brokenUntil
end


local function breakGuard(
	defenderPlayer: Player,
	targetCharacter: Model,
	targetRoot: BasePart,
	state: GuardState
)
	local now =
		workspace:
		GetServerTimeNow()

	state.value = 0

	state.brokenUntil =
		now
		+ GUARD_BREAK_LOCK_DURATION

	state.lastDamageAt =
		now

	blockStates[
	defenderPlayer
	] = nil

	replicateGuardState(
		defenderPlayer,
		state
	)

	playCombatSound(
		targetRoot,
		BLOCK_IMPACT_SOUND_ID,
		BLOCK_IMPACT_SOUND_VOLUME * 1.08,
		0.84
	)

	blockBreak:
		FireClient(
			defenderPlayer,
			state.brokenUntil
		)

	applyBlockBreakStun(
		targetCharacter
	)

	if DEBUG_M1 then
		print(
			"[Guard-Server] BLOCK BREAK:",
			defenderPlayer.Name,
			"Guard=0",
			"lock=",
			GUARD_BREAK_LOCK_DURATION
		)
	end
end


local function applyGuardDamage(
	defenderPlayer: Player,
	targetCharacter: Model,
	targetRoot: BasePart,
	comboNumber: number
): boolean

	local state =
		getGuardState(
			defenderPlayer
		)

	local baseGuardDamage =
		if comboNumber == 5
		then M1_5_GUARD_DAMAGE
		else M1_GUARD_DAMAGE

	local guardDamage =
		baseGuardDamage
		* StatusCombatModifierService
		.GetGuardPressureTakenMultiplier(
			targetCharacter
		)

	state.lastDamageAt =
		workspace:
		GetServerTimeNow()

	state.value =
		math.max(
			0,
			state.value
			- guardDamage
		)

	replicateGuardState(
		defenderPlayer,
		state
	)

	if DEBUG_M1 then
		print(
			"[Guard-Server]",
			defenderPlayer.Name,
			"-",
			guardDamage,
			"=>",
			state.value,
			"/",
			GUARD_MAX
		)
	end

	if state.value <= 0 then
		breakGuard(
			defenderPlayer,
			targetCharacter,
			targetRoot,
			state
		)

		return true
	end

	return false
end


local function applyDirectGuardDamage(
	defenderPlayer: Player,
	targetCharacter: Model,
	targetRoot: BasePart,
	guardDamage: number
): boolean

	local state =
		getGuardState(
			defenderPlayer
		)

	local finalGuardDamage =
		guardDamage
		* StatusCombatModifierService
		.GetGuardPressureTakenMultiplier(
			targetCharacter
		)

	state.lastDamageAt =
		workspace:GetServerTimeNow()

	state.value =
		math.max(
			0,
			state.value - finalGuardDamage
		)

	replicateGuardState(
		defenderPlayer,
		state
	)

	if DEBUG_M1 then
		print(
			"[AerialKick-Guard]",
			defenderPlayer.Name,
			"-",
			finalGuardDamage,
			"=>",
			state.value,
			"/",
			GUARD_MAX
		)
	end

	if state.value <= 0 then
		breakGuard(
			defenderPlayer,
			targetCharacter,
			targetRoot,
			state
		)

		return true
	end

	return false
end


local guardRegenAccumulator = 0

RunService.Heartbeat:Connect(
	function(
		deltaTime: number
	)

		guardRegenAccumulator +=
			deltaTime

		if guardRegenAccumulator < 0.10 then
			return
		end

		local step =
			guardRegenAccumulator

		guardRegenAccumulator = 0

		local now =
			workspace:
			GetServerTimeNow()

		for player,
			state in pairs(
				guardStates
			) do

			local character =
				player.Character

			if not character
				or not character.Parent then

				continue
			end

			local blockState =
				blockStates[
			player
			]

			local activelyBlocking =
				blockState ~= nil
				and blockState.active
				== true

			if not activelyBlocking
				and state.value
				< GUARD_MAX
				and now
				- state.lastDamageAt
					>= GUARD_REGEN_DELAY then

				state.value =
					math.min(
						GUARD_MAX,
						state.value
						+ GUARD_REGEN_RATE
						* step
					)

				local rounded =
					math.round(
						state.value
						* 10
					) / 10

				if rounded ~=
					state.lastReplicatedValue then

					replicateGuardState(
						player,
						state
					)
				end
			end

			if now >=
				state.brokenUntil
				and character:
				GetAttribute(
					"GuardBroken"
				) == true then

				replicateGuardState(
					player,
					state
				)
			end
		end
	end
)


-- =========================
-- BLOCK TEST
-- =========================

local function isBlockingAttack(
	defenderPlayer: Player?,
	defenderRoot: BasePart,
	attackerRoot: BasePart,
	defenderPose: CFrame?,
	attackerPose: CFrame?
): boolean

	if not defenderPlayer then
		return false
	end

	local defenderCharacter =
		defenderPlayer.Character

	if defenderCharacter
		and defenderCharacter:
		GetAttribute(
			"SubstitutionWindowActive"
		) == true then

		return false
	end

	local blockState =
		blockStates[
	defenderPlayer
	]

	if not blockState
		or not blockState.active then

		return false
	end

	local defenderFrame =
		defenderPose
		or defenderRoot.CFrame

	local attackerFrame =
		attackerPose
		or attackerRoot.CFrame

	local toAttacker =
		attackerFrame.Position
	- defenderFrame.Position

	if toAttacker.Magnitude < 0.01 then
		return true
	end

	local frontDot =
		defenderFrame.LookVector:
		Dot(
			toAttacker.Unit
		)

	return frontDot
		>= BLOCK_FRONT_DOT
end


-- =========================
-- MOTION-COMP HITBOX HELPERS
-- =========================

local function historicalRootInsideHitbox(
	attackerPose: CFrame,
	targetPose: CFrame
): boolean

	local hitboxPose =
		attackerPose
		* CFrame.new(
			0,
			0,
			-HITBOX_FORWARD_OFFSET
		)

	local localPosition =
		hitboxPose:
		PointToObjectSpace(
			targetPose.Position
		)

	local half =
		HITBOX_SIZE
		* 0.5

	return math.abs(localPosition.X)
		<= half.X
		+ M1_HISTORY_TARGET_PADDING.X

		and math.abs(localPosition.Y)
		<= half.Y
		+ M1_HISTORY_TARGET_PADDING.Y

		and math.abs(localPosition.Z)
		<= half.Z
		+ M1_HISTORY_TARGET_PADDING.Z
end


local function sanitizeHitMarkerTime(
	state: any,
	clientHitAt: any
): (number, number)

	local serverNow =
		workspace:
		GetServerTimeNow()

	if typeof(clientHitAt)
		~= "number" then

		return serverNow,
			0
	end

	if clientHitAt >
		serverNow
			+ M1_FUTURE_TIMESTAMP_TOLERANCE then

		return serverNow,
			0
	end

	local attackEarliest =
		state.animationStartedAt
		+ MIN_HIT_TIME
	- 0.04

	local attackLatest =
		state.animationStartedAt
		+ MAX_HIT_TIME
		+ 0.04

	if clientHitAt <
		attackEarliest
		or clientHitAt >
		attackLatest then

		return serverNow,
			0
	end

	local impactTime =
		math.clamp(
			clientHitAt,
			serverNow
			- M1_MAX_REWIND,
			serverNow
		)

	return impactTime,
		serverNow
	- impactTime
end


local function sanitizeLungeMarkerTime(
	state: any,
	clientMarkerAt: any
): (number, number)

	local serverNow =
		workspace:
		GetServerTimeNow()

	if typeof(clientMarkerAt)
		~= "number" then

		return serverNow, 0
	end

	if clientMarkerAt >
		serverNow
			+ M1_FUTURE_TIMESTAMP_TOLERANCE then

		return serverNow, 0
	end

	local earliest =
		state.animationStartedAt
		+ LUNGE_MIN_DAMAGE_MARKER_TIME
	- 0.04

	local latest =
		state.animationStartedAt
		+ LUNGE_MAX_DAMAGE_MARKER_TIME
		+ 0.04

	if clientMarkerAt < earliest
		or clientMarkerAt > latest then

		return serverNow, 0
	end

	local impactTime =
		math.clamp(
			clientMarkerAt,
			serverNow - M1_MAX_REWIND,
			serverNow
		)

	return impactTime,
		serverNow - impactTime
end


type HitCandidate = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	compensated: boolean,
	targetPose: CFrame?,
	launcherAirPaired: boolean?,
}


local function addLauncherAirPairedCandidate(
	candidates: {[Model]: HitCandidate},
	attackerCharacter: Model
)
	if attackerCharacter:GetAttribute(
		"AirComboServerActive"
		) ~= true
			or attackerCharacter:GetAttribute(
				"AirComboRole"
			) ~= "Attacker"
			or attackerCharacter:GetAttribute(
				"LauncherAirComboAttacker"
			) ~= true then

		return
	end

	local attackerAirComboId =
		attackerCharacter:GetAttribute(
			"AirComboId"
		)

	if typeof(attackerAirComboId)
		~= "number" then

		return
	end

	local targetRef =
		attackerCharacter:
		FindFirstChild(
			"LauncherAirTarget"
		)

	if not targetRef
		or not targetRef:IsA(
			"ObjectValue"
		) then

		return
	end

	local targetCharacter =
		targetRef.Value

	if not targetCharacter
		or not targetCharacter:IsA(
			"Model"
		)
			or targetCharacter ==
			attackerCharacter then

		return
	end

	if targetCharacter:GetAttribute(
		"AirComboServerActive"
		) ~= true
			or targetCharacter:GetAttribute(
				"AirComboRole"
			) ~= "Victim"
			or targetCharacter:GetAttribute(
				"LauncherAirComboVictim"
			) ~= true
			or targetCharacter:GetAttribute(
				"AirComboId"
			) ~= attackerAirComboId then

		return
	end

	local targetHumanoid =
		targetCharacter:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local targetRoot =
		targetCharacter:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not targetHumanoid
		or targetHumanoid.Health <= 0
		or not targetRoot
		or not targetRoot:IsA(
			"BasePart"
		)
			or not canReceiveM1Hit(
				targetCharacter
			) then

		return
	end

	candidates[
	targetCharacter
	] = {
		character =
			targetCharacter,

		humanoid =
			targetHumanoid,

		root =
			targetRoot,

		player =
			Players:
			GetPlayerFromCharacter(
				targetCharacter
			),

		compensated =
			false,

		targetPose =
			nil,

		launcherAirPaired =
			true,
	}
end


local function addLiveCandidates(
	candidates: {[Model]: HitCandidate},
	attackerCharacter: Model,
	attackerRoot: BasePart
)
	local hitboxCFrame =
		attackerRoot.CFrame
		* CFrame.new(
			0,
			0,
			-HITBOX_FORWARD_OFFSET
		)

	emitHitboxDebug(
		"M1_LIVE",
		"M1 LIVE",
		hitboxCFrame,
		HITBOX_SIZE
	)

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		attackerCharacter,
	}

	local parts =
		workspace:
		GetPartBoundsInBox(
			hitboxCFrame,
			HITBOX_SIZE,
			overlapParams
		)

	for _, part in ipairs(
		parts
		) do
		local targetCharacter,
			targetHumanoid,
			targetRoot =
			getTargetCharacterFromPart(
				part
			)

		if targetCharacter
			and targetHumanoid
			and targetRoot
			and targetCharacter
			~= attackerCharacter
			and targetHumanoid.Health > 0
			and canReceiveM1Hit(
				targetCharacter
			) then

			if not candidates[
				targetCharacter
				] then

				candidates[
				targetCharacter
				] = {
					character =
						targetCharacter,

					humanoid =
						targetHumanoid,

					root =
						targetRoot,

					player =
						Players:
						GetPlayerFromCharacter(
							targetCharacter
						),

					compensated =
						false,

					targetPose =
						nil,
				}
			end
		end
	end
end


local function addHistoricalPlayerCandidates(
	candidates: {[Model]: HitCandidate},
	attackerPlayer: Player,
	attackerCharacter: Model,
	attackerPose: CFrame,
	impactTime: number
)
	local debugHistoricalBox =
		attackerPose
		* CFrame.new(
			0,
			0,
			-HITBOX_FORWARD_OFFSET
		)

	emitHitboxDebug(
		"M1_REWIND",
		"M1 REWIND",
		debugHistoricalBox,
		HITBOX_SIZE
	)

	for _, targetPlayer in ipairs(
		Players:GetPlayers()
		) do

		if targetPlayer ==
			attackerPlayer then

			continue
		end

		local targetCharacter,
			targetHumanoid,
			targetRoot =
			getAliveCharacter(
				targetPlayer
			)

		if not targetCharacter
			or not targetHumanoid
			or not targetRoot
			or not canReceiveM1Hit(
				targetCharacter
			) then

			continue
		end

		if candidates[
			targetCharacter
			] then

			continue
		end

		local targetPose =
			getPoseAt(
				targetCharacter,
				impactTime
			)

		if not targetPose then
			continue
		end

		if historicalRootInsideHitbox(
			attackerPose,
			targetPose
			) then

			candidates[
			targetCharacter
			] = {
				character =
					targetCharacter,

				humanoid =
					targetHumanoid,

				root =
					targetRoot,

				player =
					targetPlayer,

				compensated =
					true,

				targetPose =
					targetPose,
			}
		end
	end
end


-- =========================
-- DAMAGE RESOLUTION
-- =========================

local function requestLauncherAirFinishAfterM1_5(
	attackerPlayer: Player,
	attackerCharacter: Model,
	candidate: HitCandidate,
	comboNumber: number,
	damageResult: string
)
	if comboNumber ~= 5
		or candidate.launcherAirPaired ~= true
		or damageResult == "Substituted"
		or damageResult == "AlreadyDowned"
		or damageResult == "BeingExecuted" then
		return
	end

	local airComboId =
		attackerCharacter:GetAttribute(
			"AirComboId"
		)

	if typeof(airComboId) ~= "number" then
		return
	end

	local control =
		game:GetService("ServerScriptService"):
		FindFirstChild(
			"LauncherAirComboControl"
		)

	if not control
		or not control:IsA(
			"BindableEvent"
		) then
		if DEBUG_M1 then
			warn(
				"[M1-Server] LauncherAirComboControl missing on M1_5"
			)
		end
		return
	end

	if DEBUG_M1 then
		print(
			"[M1-Server] Launcher aerial M1_5 confirmed -> AirEnd",
			attackerPlayer.Name,
			"airCombo",
			airComboId
		)
	end

	control:Fire(
		"M1_5Confirmed",
		attackerPlayer,
		airComboId
	)
end


local function processM1Candidate(
	attackerPlayer: Player,
	attackerCharacter: Model,
	attackerRoot: BasePart,
	attackerPose: CFrame,
	candidate: HitCandidate,
	comboNumber: number,
	rewindSeconds: number
): boolean
	local targetCharacter =
		candidate.character

	local targetHumanoid =
		candidate.humanoid

	local targetRoot =
		candidate.root

	if not targetCharacter.Parent
		or not targetRoot.Parent
		or targetHumanoid.Health <= 0
		or not canReceiveM1Hit(
			targetCharacter
		) then

		return false
	end

	local hasLOS: boolean

	-- During an active Launcher aerial string, the server already owns the
	-- attacker/victim pairing. Do not reject early aerial M1s merely because
	-- the attacker's client-owned HRP replication is a few frames behind the
	-- server-owned NPC (or the other player's replicated hold position).
	if candidate.launcherAirPaired == true then
		hasLOS = true
	elseif candidate.compensated
		and candidate.targetPose then

		hasLOS =
			hasHistoricalLineOfSight(
				attackerCharacter,
				targetCharacter,
				attackerPose.Position,
				candidate.targetPose.Position
			)
	else
		hasLOS =
			hasLiveLineOfSight(
				attackerCharacter,
				targetCharacter,
				attackerRoot,
				targetRoot
			)
	end

	if not hasLOS then
		return false
	end

	local defenderPlayer =
		candidate.player
		or Players:
		GetPlayerFromCharacter(
			targetCharacter
		)

	local blocked =
		isBlockingAttack(
			defenderPlayer,
			targetRoot,
			attackerRoot,
			candidate.compensated
			and candidate.targetPose
			or nil,
			candidate.compensated
			and attackerPose
			or nil
		)

	if blocked then
		local guardWasBroken = false

		if defenderPlayer then
			guardWasBroken =
				applyGuardDamage(
					defenderPlayer,
					targetCharacter,
					targetRoot,
					comboNumber
				)
		end

		if not guardWasBroken then
			playCombatSound(
				targetRoot,
				BLOCK_IMPACT_SOUND_ID,
				BLOCK_IMPACT_SOUND_VOLUME,
				0.96
			)

			if defenderPlayer then
				blockImpact:
					FireClient(
						defenderPlayer
					)
			end
		end


		emitCombatImpactVFX(
			guardWasBroken
				and "GuardBreak"
				or "Block",
			attackerPlayer,
			defenderPlayer,
			attackerRoot,
			targetRoot,
			comboNumber
		)


		if DEBUG_M1 then
			print(
				"[M1-Server]",
				attackerPlayer.Name,
				guardWasBroken
					and "BROKE GUARD of"
					or "was BLOCKED by",
				defenderPlayer
					and defenderPlayer.Name
					or targetCharacter.Name,
				candidate.compensated
					and string.format(
						"[rewind %.3f]",
						rewindSeconds
					)
					or "[live]"
			)
		end

		return false
	end

	local damageAmount: number
	local activeWeaponId: string?

	if candidate.launcherAirPaired == true then

		-- Launcher aerial strings remain on their existing unarmed tuning
		-- until weapon-specific aerial combat is authored.
		damageAmount =
			if comboNumber == 5
			then M1_5_DAMAGE
			else M1_DAMAGE

		activeWeaponId =
			nil
	else
		damageAmount,
			activeWeaponId =
			resolveGroundM1Damage(
				attackerCharacter,
				comboNumber
			)
	end

	local damageResolution =
		DamageService.Apply(
			{
				TargetCharacter =
				targetCharacter,

				TargetHumanoid =
				targetHumanoid,

				TargetPlayer =
				defenderPlayer,

				Attacker =
				attackerPlayer,

				Damage =
				damageAmount,

				SourceType =
				"M1",

				SourceId =
				"M1_"
				.. tostring(
					comboNumber
				),

				Armor =
				M1_ARMOR_PROFILE,
			}
		)

	local damageResult =
		damageResolution.Result

	local wasSubstituted =
		damageResult ==
		"Substituted"

	local targetRemainsStanding =
		not wasSubstituted
		and damageResult ~= "Downed"
		and damageResult ~= "AlreadyDowned"
		and damageResult ~= "BeingExecuted"
		and targetHumanoid.Health > 0

	-- M1_5 physical response starts immediately after authoritative damage.
	-- Do this before sound/VFX/combo bookkeeping so the replicated body reaction
	-- is tied as closely as possible to the authored Hit marker.
	if targetRemainsStanding
		and comboNumber == 5 then

		local targetIsLauncherAirVictim =
			targetCharacter:GetAttribute("LauncherAirComboVictim") == true
			or (
				targetCharacter:GetAttribute("AirComboServerActive") == true
				and targetCharacter:GetAttribute("AirComboRole") == "Victim"
			)

		if targetIsLauncherAirVictim then
			-- Keep M1_5 damage / hit confirmation / VFX, but do NOT let its
			-- grounded ragdoll + knockback fight the Launcher air hold.
			-- A dedicated aerial finisher/ground slam can own that later.
			if DEBUG_M1 then
				print(
					"[M1-Server] M1_5 aerial victim physics suppressed",
					targetCharacter.Name
				)
			end
		else
			applyStun(
				targetCharacter,
				M1_5_RAGDOLL_LOCK_DURATION,
				false
			)

			applyM1_5FinisherPhysics(
				attackerCharacter,
				attackerRoot,
				targetCharacter,
				targetHumanoid,
				targetRoot,
				defenderPlayer
			)
		end
	end


	-- =========================
	-- SERVER-CONFIRMED COMBO
	-- =========================
	--
	-- We are already past:
	-- - server hitbox validation
	-- - line of sight
	-- - Block
	-- - DamageService
	--
	-- A substituted or downed-locked target does not count.
	local comboHitConfirmed =
		not wasSubstituted
		and damageResult ~= "AlreadyDowned"
		and damageResult ~= "BeingExecuted"


	if comboHitConfirmed then

		ComboCounterService.RecordHit(
			attackerPlayer,
			targetCharacter,
			"M1",
			"M1_"
				.. tostring(
					comboNumber
				)
		)
	end


	if not wasSubstituted then
		local hitPlaybackSpeed =
			if comboNumber == 5
			then 0.86
			elseif comboNumber == 3
			then 1.04
			elseif comboNumber == 2
			then 1.00
			else 0.97

		local hitVolume =
			if comboNumber == 5
			then HIT_SOUND_VOLUME * 1.14
			else HIT_SOUND_VOLUME

		playCombatSound(
			targetRoot,
			M1_HIT_SOUND_ID,
			hitVolume,
			hitPlaybackSpeed
		)


		emitCombatImpactVFX(
			comboNumber == 5
				and "HeavyHit"
				or "Hit",
			attackerPlayer,
			defenderPlayer,
			attackerRoot,
			targetRoot,
			comboNumber
		)
	end

	if targetRemainsStanding
		and comboNumber ~= 5 then

		applyM1Hitstun(
			targetCharacter
		)
	end

	if DEBUG_M1 then
		print(
			"[M1-Server]",
			attackerPlayer.Name,
			"hit",
			targetCharacter.Name,
			"base",
			damageAmount,
			"final",
			string.format(
				"%.2f",
				damageResolution.FinalDamage
			),
			"armorDur",
			string.format(
				"%.2f",
				damageResolution.DurabilityDamage
			),
			"via M1_"
				.. comboNumber,
			activeWeaponId
				and (
					"weapon="
					.. activeWeaponId
				)
				or "weapon=UNARMED",
			"result",
			damageResult,
			candidate.launcherAirPaired == true
				and "[LAUNCHER-AIR-PAIR]"
				or (
					candidate.compensated
					and string.format(
						"[MOTION-COMP %.3fs]",
						rewindSeconds
					)
					or "[LIVE]"
				)
		)
	end

	requestLauncherAirFinishAfterM1_5(
		attackerPlayer,
		attackerCharacter,
		candidate,
		comboNumber,
		damageResult
	)


	return comboHitConfirmed
end


local function performM1Hitbox(
	player: Player,
	comboNumber: number,
	impactTime: number?
): boolean
	local attackerCharacter,
		_humanoid,
		attackerRoot =
		getAliveCharacter(
			player
		)

	if not attackerCharacter
		or not attackerRoot then

		return false
	end

	local serverNow =
		workspace:
		GetServerTimeNow()

	local resolvedImpactTime =
		if typeof(impactTime)
		== "number"
		then math.clamp(
			impactTime,
			serverNow
			- M1_MAX_REWIND,
			serverNow
		)
		else serverNow

	local rewindSeconds =
		serverNow
	- resolvedImpactTime

	local attackerPose =
		getPoseAt(
			attackerCharacter,
			resolvedImpactTime
		)
		or attackerRoot.CFrame

	local candidates: {[Model]: HitCandidate} =
		{}

	-- Launcher aerial combat is a server-established pair. Add that paired
	-- victim first so hit registration does not depend on client/server
	-- convergence of the suspended attacker root.
	addLauncherAirPairedCandidate(
		candidates,
		attackerCharacter
	)

	-- Baseline/current-world overlap: preserves existing behavior everywhere
	-- else and can still add unrelated valid targets if they are truly inside
	-- the normal melee box.
	addLiveCandidates(
		candidates,
		attackerCharacter,
		attackerRoot
	)

	-- Extra PvP reconciliation for moving players.
	addHistoricalPlayerCandidates(
		candidates,
		player,
		attackerCharacter,
		attackerPose,
		resolvedImpactTime
	)

	if DEBUG_M1 then
		for targetCharacter,
			candidate in pairs(
				candidates
			) do

			if candidate.launcherAirPaired == true then
				print(
					"[M1-Server] Launcher air pair candidate",
					player.Name,
					"->",
					targetCharacter.Name,
					"M1_"
						.. tostring(
							comboNumber
						)
				)
			end
		end
	end

	if DEBUG_M1
		and next(
			candidates
		) == nil then

		print(
			"[M1-Server] No hitbox candidates",
			player.Name,
			"M1_"
				.. tostring(
					comboNumber
				),
			"rewind",
			string.format(
				"%.3f",
				rewindSeconds
			)
		)
	end

	local anyConfirmedHit = false

	for _targetCharacter,
		candidate in pairs(
			candidates
		) do

		local confirmed = processM1Candidate(
			player,
			attackerCharacter,
			attackerRoot,
			attackerPose,
			candidate,
			comboNumber,
			rewindSeconds
		)

		if confirmed then
			anyConfirmedHit = true
		end
	end

	return anyConfirmedHit
end


-- =========================
-- LUNGE DAMAGE / HITBOX
-- =========================

local function historicalRootInsideLungeHitbox(
	attackerPose: CFrame,
	targetPose: CFrame
): boolean

	local hitboxPose =
		attackerPose
		* CFrame.new(
			0,
			LUNGE_HITBOX_VERTICAL_OFFSET,
			-LUNGE_HITBOX_FORWARD_OFFSET
		)

	local localPosition =
		hitboxPose:
		PointToObjectSpace(
			targetPose.Position
		)

	local half =
		LUNGE_HITBOX_SIZE
		* 0.5

	return math.abs(
		localPosition.X
	) <= half.X
		+ LUNGE_HISTORY_TARGET_PADDING.X

		and math.abs(
			localPosition.Y
		) <= half.Y
		+ LUNGE_HISTORY_TARGET_PADDING.Y

		and math.abs(
			localPosition.Z
		) <= half.Z
		+ LUNGE_HISTORY_TARGET_PADDING.Z
end


local function addLiveLungeCandidates(
	candidates: {[Model]: HitCandidate},
	attackerCharacter: Model,
	attackerPose: CFrame,
	emitDebug: boolean?
)
	-- `attackerPose` is whichever pose this caller wants to evaluate.
	-- v22.7 uses current server pose for live overlap and historical pose only
	-- for the dedicated PvP rewind test below.
	local hitboxCFrame =
		attackerPose
		* CFrame.new(
			0,
			LUNGE_HITBOX_VERTICAL_OFFSET,
			-LUNGE_HITBOX_FORWARD_OFFSET
		)

	if emitDebug ~= false then
		emitHitboxDebug(
			"LUNGE_LIVE",
			"LUNGE LIVE",
			hitboxCFrame,
			LUNGE_HITBOX_SIZE
		)
	end

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		attackerCharacter,
	}

	local parts =
		workspace:
		GetPartBoundsInBox(
			hitboxCFrame,
			LUNGE_HITBOX_SIZE,
			overlapParams
		)

	for _,
		part in ipairs(
			parts
		) do

		local targetCharacter,
			targetHumanoid,
			targetRoot =
			getTargetCharacterFromPart(
				part
			)

		if targetCharacter
			and targetHumanoid
			and targetRoot
			and targetCharacter ~=
			attackerCharacter
			and targetHumanoid.Health > 0
			and canReceiveM1Hit(
				targetCharacter
			)
				and not candidates[
			targetCharacter
			] then

			candidates[
			targetCharacter
			] = {
				character =
					targetCharacter,

				humanoid =
					targetHumanoid,

				root =
					targetRoot,

				player =
					Players:
					GetPlayerFromCharacter(
						targetCharacter
					),

				compensated =
					false,

				targetPose =
					nil,
			}
		end
	end
end


local function addHistoricalLungePlayerCandidates(
	candidates: {[Model]: HitCandidate},
	attackerPlayer: Player,
	attackerCharacter: Model,
	attackerPose: CFrame,
	impactTime: number,
	emitDebug: boolean?
)
	local rewindHitboxCFrame =
		attackerPose
		* CFrame.new(
			0,
			LUNGE_HITBOX_VERTICAL_OFFSET,
			-LUNGE_HITBOX_FORWARD_OFFSET
		)

	if emitDebug ~= false then
		emitHitboxDebug(
			"LUNGE_REWIND",
			"LUNGE REWIND",
			rewindHitboxCFrame,
			LUNGE_HITBOX_SIZE
		)
	end

	for _,
		targetPlayer in ipairs(
			Players:
				GetPlayers()
		) do

		if targetPlayer ==
			attackerPlayer then

			continue
		end

		local targetCharacter,
			targetHumanoid,
			targetRoot =
			getAliveCharacter(
				targetPlayer
			)

		if not targetCharacter
			or not targetHumanoid
			or not targetRoot
			or not canReceiveM1Hit(
				targetCharacter
			)
				or candidates[
			targetCharacter
			] then

			continue
		end

		local targetPose =
			getPoseAt(
				targetCharacter,
				impactTime
			)

		if not targetPose then
			continue
		end

		if historicalRootInsideLungeHitbox(
			attackerPose,
			targetPose
			) then

			candidates[
			targetCharacter
			] = {
				character =
					targetCharacter,

				humanoid =
					targetHumanoid,

				root =
					targetRoot,

				player =
					targetPlayer,

				compensated =
					true,

				targetPose =
					targetPose,
			}
		end
	end
end




local function processLungeCandidate(
	attackerPlayer: Player,
	attackerCharacter: Model,
	attackerRoot: BasePart,
	attackerPose: CFrame,
	candidate: HitCandidate,
	rewindSeconds: number
): boolean
	local targetCharacter = candidate.character
	local targetHumanoid = candidate.humanoid
	local targetRoot = candidate.root

	if not targetCharacter.Parent
		or not targetRoot.Parent
		or targetHumanoid.Health <= 0
		or not canReceiveM1Hit(targetCharacter) then
		return false
	end

	local hasLOS: boolean

	-- Terrain Water must not become an invisible wall for a Lunge that the
	-- server already accepted from Chakra Feet Water Walk.
	local targetPlayerForWater =
		Players:GetPlayerFromCharacter(
			targetCharacter
		)

	local ignoreWaterLOS =
		attackerCharacter:GetAttribute(
			"ServerLungeWaterWalk"
		) == true
		or (
			targetPlayerForWater ~= nil
			and targetCharacter:GetAttribute(
				"ServerLungeWaterWalk"
			) == true
		)

	if candidate.compensated and candidate.targetPose then
		hasLOS = hasHistoricalLineOfSight(
			attackerCharacter,
			targetCharacter,
			attackerPose.Position,
			candidate.targetPose.Position,
			ignoreWaterLOS
		)
	else
		hasLOS = hasLiveLineOfSight(
			attackerCharacter,
			targetCharacter,
			attackerRoot,
			targetRoot,
			ignoreWaterLOS
		)
	end

	if not hasLOS then
		return false
	end

	local defenderPlayer =
		candidate.player
		or Players:GetPlayerFromCharacter(targetCharacter)

	local blocked = isBlockingAttack(
		defenderPlayer,
		targetRoot,
		attackerRoot,
		candidate.compensated and candidate.targetPose or nil,
		candidate.compensated and attackerPose or nil
	)

	if blocked then
		local guardWasBroken = false

		if defenderPlayer then
			-- First pass uses normal M1 guard pressure.
			guardWasBroken = applyGuardDamage(
				defenderPlayer,
				targetCharacter,
				targetRoot,
				1
			)
		end

		if not guardWasBroken then
			playCombatSound(
				targetRoot,
				BLOCK_IMPACT_SOUND_ID,
				BLOCK_IMPACT_SOUND_VOLUME,
				0.96
			)

			if defenderPlayer then
				blockImpact:FireClient(defenderPlayer)
			end
		end

		emitCombatImpactVFX(
			guardWasBroken and "GuardBreak" or "Block",
			attackerPlayer,
			defenderPlayer,
			attackerRoot,
			targetRoot,
			0
		)

		if DEBUG_M1 then
			print(
				"[Lunge-Server]",
				attackerPlayer.Name,
				guardWasBroken and "BROKE GUARD of" or "was BLOCKED by",
				defenderPlayer and defenderPlayer.Name or targetCharacter.Name
			)
		end

		return true
	end

	local damageResolution = DamageService.Apply({
		TargetCharacter = targetCharacter,
		TargetHumanoid = targetHumanoid,
		TargetPlayer = defenderPlayer,
		Attacker = attackerPlayer,
		Damage = LUNGE_DAMAGE,
		SourceType = "Lunge",
		SourceId = "RunningAttack",
		Armor = LUNGE_ARMOR_PROFILE,
	})

	local damageResult = damageResolution.Result
	local wasSubstituted = damageResult == "Substituted"

	local targetRemainsStanding =
		not wasSubstituted
		and damageResult ~= "Downed"
		and damageResult ~= "AlreadyDowned"
		and damageResult ~= "BeingExecuted"
		and targetHumanoid.Health > 0

	local comboHitConfirmed =
		not wasSubstituted
		and damageResult ~= "AlreadyDowned"
		and damageResult ~= "BeingExecuted"

	if comboHitConfirmed then
		ComboCounterService.RecordHit(
			attackerPlayer,
			targetCharacter,
			"Lunge",
			"RunningAttack"
		)
	end

	if not wasSubstituted then
		playCombatSound(
			targetRoot,
			M1_HIT_SOUND_ID,
			HIT_SOUND_VOLUME * 1.03,
			0.96
		)

		emitCombatImpactVFX(
			"Hit",
			attackerPlayer,
			defenderPlayer,
			attackerRoot,
			targetRoot,
			0
		)
	end

	if targetRemainsStanding then
		applyM1Hitstun(targetCharacter)
	end

	if DEBUG_M1 then
		print(
			"[Lunge-Server]",
			attackerPlayer.Name,
			"hit",
			targetCharacter.Name,
			"base",
			LUNGE_DAMAGE,
			"final",
			string.format("%.2f", damageResolution.FinalDamage),
			"result",
			damageResult,
			candidate.compensated
				and string.format("[MOTION-COMP %.3fs]", rewindSeconds)
				or "[LIVE]"
		)
	end

	return true
end


local function evaluateLungeSweepPose(
	player: Player,
	state: any,
	attackerCharacter: Model,
	attackerRoot: BasePart,
	attackerPose: CFrame,
	sampleTime: number,
	emitDebug: boolean
)
	local candidates: {[Model]: HitCandidate} = {}

	-- Live overlap catches NPCs/dummies and current-world player contacts.
	addLiveLungeCandidates(
		candidates,
		attackerCharacter,
		attackerPose,
		emitDebug
	)

	-- Historical player roots give a small PvP motion-compensation allowance.
	addHistoricalLungePlayerCandidates(
		candidates,
		player,
		attackerCharacter,
		attackerPose,
		sampleTime,
		emitDebug
	)

	local rewindSeconds =
		math.max(
			0,
			workspace:GetServerTimeNow()
			- sampleTime
		)

	for targetCharacter,
		candidate in pairs(
			candidates
		) do

		-- One interaction per target per Lunge. A block, substitution, damage,
		-- downing, etc. all consume that target for this attack window.
		if state.hitTargets[
			targetCharacter
			] then

			continue
		end

		local consumed =
			processLungeCandidate(
				player,
				attackerCharacter,
				attackerRoot,
				attackerPose,
				candidate,
				rewindSeconds
			)

		if consumed then

			state.hitTargets[
			targetCharacter
			] = true

			state.anyInteraction =
				true
		end
	end
end


local function performLungeDamageSweep(
	player: Player,
	state: any,
	fromPose: CFrame,
	toPose: CFrame,
	fromTime: number,
	toTime: number
)
	local attackerCharacter,
		_humanoid,
		attackerRoot =
		getAliveCharacter(
			player
		)

	if not attackerCharacter
		or not attackerRoot then

		return
	end

	local distance =
		(
			toPose.Position
			- fromPose.Position
		).Magnitude

	local steps =
		math.clamp(
			math.ceil(
				distance
				/ LUNGE_SWEEP_STEP_STUDS
			),
			1,
			LUNGE_SWEEP_MAX_STEPS
		)

	for index = 1,
		steps do

		local alpha =
			index
			/ steps

		local samplePose =
			fromPose:
			Lerp(
				toPose,
				alpha
			)

		local sampleTime =
			fromTime
			+ (
				toTime
				- fromTime
			)
			* alpha

		-- Draw only the newest box in each server sweep. Intermediate samples
		-- still query collision, but do not flood the TEMP visualizer.
		evaluateLungeSweepPose(
			player,
			state,
			attackerCharacter,
			attackerRoot,
			samplePose,
			sampleTime,
			index == steps
		)
	end

	state.lastDamagePose =
		toPose

	state.lastDamageSampleAt =
		toTime
end


local function isLungeStartNearGround(
	character: Model,
	rootPart: BasePart
): boolean

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}

	params.IgnoreWater =
		true

	-- The client may already have reached the early Launch marker by the time
	-- physics replication reaches the server. Validate "started near ground"
	-- rather than requiring FloorMaterial to still be non-Air at receipt.
	local result =
		workspace:
		Raycast(
			rootPart.Position
			+ Vector3.new(
				0,
				0.5,
				0
			),
			Vector3.new(
				0,
				-7.0,
				0
			),
			params
		)

	return result ~= nil
		and result.Normal.Y >= 0.45
end


local function isLungeStartNearWaterSurface(
	character: Model,
	rootPart: BasePart
): boolean

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}

	-- Unlike the normal ground probe, this probe MUST see Terrain Water.
	params.IgnoreWater =
		false

	local result =
		workspace:
		Raycast(
			rootPart.Position
			+ Vector3.new(
				0,
				0.75,
				0
			),
			Vector3.new(
				0,
				-8.0,
				0
			),
			params
		)

	return result ~= nil
		and result.Material == Enum.Material.Water
		and result.Normal.Y >= 0.35
end


local function getLungeStartHorizontalData(
	rootPart: BasePart,
	humanoid: Humanoid
): (number, number, Vector3, number)
	local velocity =
		rootPart.AssemblyLinearVelocity

	local horizontalVelocity =
		Vector3.new(
			velocity.X,
			0,
			velocity.Z
		)

	local look =
		rootPart.CFrame.LookVector

	local horizontalLook =
		Vector3.new(
			look.X,
			0,
			look.Z
		)

	local move =
		humanoid.MoveDirection

	local horizontalMove =
		Vector3.new(
			move.X,
			0,
			move.Z
		)

	local speed =
		horizontalVelocity.Magnitude

	local velocityForwardDot =
		-1

	if speed > 0.05
		and horizontalLook.Magnitude > 0.05 then

		velocityForwardDot =
			horizontalVelocity.Unit:
			Dot(
				horizontalLook.Unit
			)
	end

	local moveForwardDot =
		-1

	if horizontalMove.Magnitude > 0.05
		and horizontalLook.Magnitude > 0.05 then

		moveForwardDot =
			horizontalMove.Unit:
			Dot(
				horizontalLook.Unit
			)
	end

	local direction =
		if horizontalVelocity.Magnitude > 0.05
		then horizontalVelocity.Unit
		elseif horizontalMove.Magnitude > 0.05
		then horizontalMove.Unit
		elseif horizontalLook.Magnitude > 0.05
		then horizontalLook.Unit
		else Vector3.new(
			0,
			0,
			-1
		)

	return speed,
		velocityForwardDot,
		direction,
		moveForwardDot
end


local function serverComboAllowsLunge(
	player: Player,
	now: number
): boolean
	local state = serverComboStates[player]

	if not state then
		return true
	end

	if now < (state.fullComboLockedUntil or -math.huge) then
		return false
	end

	if now - state.lastStartedAt > SERVER_COMBO_SEQUENCE_WINDOW then
		state.nextCombo = 1
		return true
	end

	return state.nextCombo == 1
end


local function clearLungeState(
	player: Player,
	sequence: number?
)
	local state = lungeStates[player]

	if sequence and state and state.sequence ~= sequence then
		return
	end

	lungeStates[player] = nil

	local character = player.Character
	if character then
		character:SetAttribute("ServerLungeActive", false)
		character:SetAttribute("ServerLungeDamageActive", false)
		character:SetAttribute("ServerLungeClashActive", false)
		character:SetAttribute("ServerLungeDirection", nil)
		character:SetAttribute("ServerLungeWaterWalk", false)
	end
end


local function scheduleLungeSwingSound(
	player: Player,
	sequence: number
)
	task.delay(SWING_SOUND_DELAY, function()
		local state = lungeStates[player]
		if not state or state.sequence ~= sequence or state.anyInteraction then
			return
		end

		local _character, _humanoid, root = getAliveCharacter(player)
		if root then
			playCombatSound(
				root,
				M1_SWING_SOUND_ID,
				SWING_SOUND_VOLUME,
				0.94
			)
		end
	end)
end


-- =========================
-- ACTION LOCK
-- =========================

local function isDownedSystemLocked(
	character: Model
): boolean

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


-- =========================
-- LUNGE MOVING DAMAGE WINDOW
-- =========================
--
-- Server-authoritative continuous sweep. The client only opens/closes the
-- authored window through animation markers; it never chooses targets.

RunService.Heartbeat:
	Connect(
		function()

			local now =
			workspace:
			GetServerTimeNow()

			for player,
				state in pairs(
					lungeStates
				) do

				if state.damageActive
					~= true then

					continue
				end

				if now
					- (
						state.damageOpenedAt
						or now
					)
					> LUNGE_DAMAGE_WINDOW_HARD_TIMEOUT then

					state.damageActive =
					false

					local timeoutCharacter =
					player.Character

					if timeoutCharacter then
						timeoutCharacter:SetAttribute(
							"ServerLungeDamageActive",
							false
						)
					end

					if DEBUG_M1 then
						warn(
							"[Lunge-Server] Damage window hard-timeout",
							player.Name,
							state.sequence
						)
					end

					continue
				end

				local character,
				_humanoid,
				root =
				getAliveCharacter(
					player
				)

				if not character
					or not root
					or isDownedSystemLocked(
						character
					)
					or character:GetAttribute(
						"IsStunned"
					) == true then

					clearLungeState(
						player,
						state.sequence
					)

					continue
				end

				local previousPose =
				state.lastDamagePose
				or root.CFrame

				local previousTime =
				state.lastDamageSampleAt
				or now

				performLungeDamageSweep(
					player,
					state,
					previousPose,
					root.CFrame,
					previousTime,
					now
				)
			end
		end
	)


-- =========================
-- DEDICATED AERIAL AXE KICK
-- =========================

local function isAerialKickServerAirborne(
	humanoid: Humanoid
): boolean

	local state =
		humanoid:GetState()

	return state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
end


local function clearAerialKickState(
	player: Player
)
	aerialKickStates[player] = nil
end


local function getHorizontalDirection(
	vector: Vector3,
	fallback: Vector3
): Vector3

	local flat =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if flat.Magnitude > 0.001 then
		return flat.Unit
	end

	local flatFallback =
		Vector3.new(
			fallback.X,
			0,
			fallback.Z
		)

	if flatFallback.Magnitude > 0.001 then
		return flatFallback.Unit
	end

	return Vector3.new(0, 0, -1)
end


local function restoreKickTargetNetworkOwner(
	targetRoot: BasePart,
	defenderPlayer: Player?,
	targetCharacter: Model,
	delaySeconds: number
)
	task.delay(
		delaySeconds,
		function()
			if not targetRoot.Parent then
				return
			end

			pcall(
				function()
					if defenderPlayer
						and defenderPlayer.Character == targetCharacter then

						targetRoot:SetNetworkOwner(
							defenderPlayer
						)
					else
						targetRoot:SetNetworkOwnershipAuto()
					end
				end
			)
		end
	)
end


local function applyAerialKickKnockback(
	attackerCharacter: Model,
	attackerRoot: BasePart,
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	targetRoot: BasePart,
	defenderPlayer: Player?,
	horizontalSpeed: number
)
	if targetHumanoid.Health <= 0 then
		return
	end

	local direction =
		getHorizontalDirection(
			targetRoot.Position
			- attackerRoot.Position,
			attackerRoot.CFrame.LookVector
		)

	pcall(
		function()
			targetRoot:SetNetworkOwner(
				nil
			)
		end
	)

	local currentY =
		targetRoot.AssemblyLinearVelocity.Y

	local finalHorizontalSpeed =
		horizontalSpeed
		* StatusCombatModifierService
		.GetKnockbackReceivedMultiplier(
			targetCharacter
		)

	targetRoot.AssemblyLinearVelocity =
		Vector3.new(
			direction.X
			* finalHorizontalSpeed,
			math.min(
				currentY,
				AERIAL_KICK_KNOCKBACK_VERTICAL_SPEED
			),
			direction.Z
			* finalHorizontalSpeed
		)

	-- Keep the body upright/control-capable. This attack is explicitly NOT a ragdoll.
	targetRoot.AssemblyAngularVelocity =
		Vector3.zero

	restoreKickTargetNetworkOwner(
		targetRoot,
		defenderPlayer,
		targetCharacter,
		0.24
	)
end


local function findAerialKickTarget(
	attackerCharacter: Model,
	attackerRoot: BasePart
): (Model?, Humanoid?, BasePart?, Player?)

	local hitboxCFrame =
		attackerRoot.CFrame
		* CFrame.new(
			0,
			AERIAL_KICK_HITBOX_VERTICAL_OFFSET,
			-AERIAL_KICK_HITBOX_FORWARD_OFFSET
		)

	emitHitboxDebug(
		"AERIAL_KICK",
		"AERIAL AXE KICK",
		hitboxCFrame,
		AERIAL_KICK_HITBOX_SIZE
	)

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		attackerCharacter,
	}

	local parts =
		workspace:GetPartBoundsInBox(
			hitboxCFrame,
			AERIAL_KICK_HITBOX_SIZE,
			overlapParams
		)

	local bestCharacter: Model? =
		nil

	local bestHumanoid: Humanoid? =
		nil

	local bestRoot: BasePart? =
		nil

	local bestPlayer: Player? =
		nil

	local bestDistance =
		math.huge

	local seen: {[Model]: boolean} =
		{}

	for _, part in ipairs(parts) do
		local targetCharacter,
			targetHumanoid,
			targetRoot =
			getTargetCharacterFromPart(
				part
			)

		if targetCharacter
			and targetHumanoid
			and targetRoot
			and targetCharacter ~= attackerCharacter
			and not seen[targetCharacter]
			and targetHumanoid.Health > 0
			and canReceiveM1Hit(targetCharacter) then

			seen[targetCharacter] =
				true

			if hasLiveLineOfSight(
				attackerCharacter,
				targetCharacter,
				attackerRoot,
				targetRoot
				) then

				local distance =
					(
						targetRoot.Position
						- attackerRoot.Position
					).Magnitude

				if distance <
					bestDistance then

					bestDistance =
						distance

					bestCharacter =
						targetCharacter

					bestHumanoid =
						targetHumanoid

					bestRoot =
						targetRoot

					bestPlayer =
						Players:
						GetPlayerFromCharacter(
							targetCharacter
						)
				end
			end
		end
	end

	return bestCharacter,
		bestHumanoid,
		bestRoot,
		bestPlayer
end


local function applyAerialKickTargetHit(
	player: Player,
	state: any
): boolean

	if state.hitUsed
		or state.damageOpen ~= true then

		return false
	end

	local character,
		humanoid,
		attackerRoot =
		getAliveCharacter(
			player
		)

	if not character
		or not humanoid
		or not attackerRoot then

		return false
	end

	local targetCharacter,
		targetHumanoid,
		targetRoot,
		defenderPlayer =
		findAerialKickTarget(
			character,
			attackerRoot
		)

	if not targetCharacter
		or not targetHumanoid
		or not targetRoot then

		return false
	end

	-- Contact is real now. From this point the dive can only resolve once.
	state.hitUsed =
		true

	state.hitMonitoring =
		false

	local blocked =
		isBlockingAttack(
			defenderPlayer,
			targetRoot,
			attackerRoot,
			nil,
			nil
		)

	if blocked then
		local guardWasBroken =
			false

		if defenderPlayer then
			guardWasBroken =
				applyDirectGuardDamage(
					defenderPlayer,
					targetCharacter,
					targetRoot,
					AERIAL_KICK_GUARD_DAMAGE
				)
		end

		if not guardWasBroken then
			playCombatSound(
				targetRoot,
				BLOCK_IMPACT_SOUND_ID,
				BLOCK_IMPACT_SOUND_VOLUME,
				0.92
			)

			if defenderPlayer then
				blockImpact:
					FireClient(
						defenderPlayer
					)
			end
		end

		emitCombatImpactVFX(
			guardWasBroken
				and "GuardBreak"
				or "Block",
			player,
			defenderPlayer,
			attackerRoot,
			targetRoot,
			0
		)

		applyAerialKickKnockback(
			character,
			attackerRoot,
			targetCharacter,
			targetHumanoid,
			targetRoot,
			defenderPlayer,
			guardWasBroken
				and AERIAL_KICK_GUARD_BREAK_KNOCKBACK_SPEED
				or AERIAL_KICK_BLOCK_KNOCKBACK_SPEED
		)

		aerialKickEvent:
			FireClient(
				player,
				guardWasBroken
				and "GuardBreak"
				or "Blocked",
				state.sequence
			)

		if DEBUG_M1 then
			print(
				"[AerialKick-Server] CONTACT",
				player.Name,
				guardWasBroken
					and "GUARD BREAK"
					or "BLOCKED",
				targetCharacter.Name
			)
		end

		return true
	end

	local damageResolution =
		DamageService.Apply(
			{
				TargetCharacter =
				targetCharacter,

				TargetHumanoid =
				targetHumanoid,

				TargetPlayer =
				defenderPlayer,

				Attacker =
				player,

				Damage =
				AERIAL_KICK_DAMAGE,

				SourceType =
				"AerialKick",

				SourceId =
				"AerialAxeKick",

				Armor =
				AERIAL_KICK_ARMOR_PROFILE,
			}
		)

	local damageResult =
		damageResolution.Result

	local wasSubstituted =
		damageResult == "Substituted"

	local targetRemainsStanding =
		not wasSubstituted
		and damageResult ~= "Downed"
		and damageResult ~= "AlreadyDowned"
		and damageResult ~= "BeingExecuted"
		and targetHumanoid.Health > 0

	if targetRemainsStanding then
		applyStun(
			targetCharacter,
			AERIAL_KICK_HITSTUN_DURATION,
			true
		)

		applyAerialKickKnockback(
			character,
			attackerRoot,
			targetCharacter,
			targetHumanoid,
			targetRoot,
			defenderPlayer,
			AERIAL_KICK_KNOCKBACK_HORIZONTAL_SPEED
		)
	end

	if not wasSubstituted then
		-- Current KMZ-produced CombatImpactVFX contract:
		-- HeavyHit + combo 5 => ReplicatedStorage/VFX/HitVFX/Shoot-01.
		-- Avoid generic Hit combo 0, which is outside the authored M1 mapping.
		emitCombatImpactVFX(
			"HeavyHit",
			player,
			defenderPlayer,
			attackerRoot,
			targetRoot,
			5
		)
	end

	aerialKickEvent:
		FireClient(
			player,
			wasSubstituted
			and "Substituted"
			or "HitConfirmed",
			state.sequence
		)

	if DEBUG_M1 then
		print(
			"[AerialKick-Server] CONTACT HIT",
			player.Name,
			"->",
			targetCharacter.Name,
			"damage",
			AERIAL_KICK_DAMAGE,
			"knockback",
			AERIAL_KICK_KNOCKBACK_HORIZONTAL_SPEED,
			"result",
			damageResult
		)
	end

	return true
end


local function getAerialKickStaticGroundDistance(
	attackerCharacter: Model,
	attackerRoot: BasePart
): number?

	local exclusions: {Instance} = {
		attackerCharacter,
	}

	for _ = 1, 10 do
		local params =
			RaycastParams.new()

		params.FilterType =
			Enum.RaycastFilterType.Exclude

		params.FilterDescendantsInstances =
			exclusions

		params.IgnoreWater =
			false

		local result =
			workspace:Raycast(
				attackerRoot.Position,
				Vector3.new(
					0,
					-AERIAL_KICK_GROUND_RAY_DISTANCE,
					0
				),
				params
			)

		if not result then
			return nil
		end

		local characterHit =
			select(
				1,
				getTargetCharacterFromPart(
					result.Instance
				)
			)

		if characterHit then
			table.insert(
				exclusions,
				characterHit
			)
		else
			return result.Distance
		end
	end

	return nil
end


local function tryResolveAerialKickContact(
	player: Player,
	state: any,
	source: string
): boolean

	if state.hitUsed
		or state.hitMonitoring ~= true then

		return true
	end

	-- Target contact ALWAYS wins over ground release when both are nearby.
	if applyAerialKickTargetHit(
		player,
		state
		) then

		return true
	end

	local character,
		humanoid,
		attackerRoot =
		getAliveCharacter(
			player
		)

	if not character
		or not humanoid
		or not attackerRoot then

		state.hitUsed =
			true

		state.hitMonitoring =
			false

		return true
	end

	local groundDistance =
		getAerialKickStaticGroundDistance(
			character,
			attackerRoot
		)

	if groundDistance
		and groundDistance <=
		AERIAL_KICK_GROUND_RELEASE_DISTANCE then

		state.hitUsed =
			true

		state.hitMonitoring =
			false

		aerialKickEvent:
			FireClient(
				player,
				"GroundRelease",
				state.sequence,
				groundDistance
			)

		if DEBUG_M1 then
			print(
				"[AerialKick-Server] GROUND RELEASE",
				player.Name,
				state.sequence,
				"distance",
				string.format(
					"%.2f",
					groundDistance
				),
				"source",
				source
			)
		end

		return true
	end

	return false
end


local function startAerialKickContactMonitor(
	player: Player,
	state: any,
	clientHitAt: number?
)
	if state.hitUsed
		or state.hitMonitoring == true
		or state.damageOpen ~= true then

		return
	end

	local now =
		workspace:GetServerTimeNow()

	local elapsed =
		now
	- state.startedAt

	if elapsed < AERIAL_KICK_MIN_HIT_TIME
		or elapsed > AERIAL_KICK_MAX_HIT_TIME then

		state.hitUsed =
			true

		if DEBUG_M1 then
			warn(
				"[AerialKick-Server] Hit marker rejected timing",
				player.Name,
				string.format(
					"%.3f",
					elapsed
				)
			)
		end

		aerialKickEvent:
			FireClient(
				player,
				"ContactTimeout",
				state.sequence,
				"MarkerTiming"
			)

		return
	end

	state.hitMonitoring =
		true

	state.hitMonitorStartedAt =
		now

	if DEBUG_M1 then
		print(
			"[AerialKick-Server] CONTACT MONITOR START",
			player.Name,
			state.sequence
		)
	end

	-- Immediate frame first.
	if tryResolveAerialKickContact(
		player,
		state,
		"HitMarkerImmediate"
		) then

		return
	end

	task.spawn(
		function()
			while true do
				RunService.Heartbeat:
					Wait()

				local current =
					aerialKickStates[player]

				if current ~= state
					or state.hitUsed
					or state.hitMonitoring ~= true then

					return
				end

				if tryResolveAerialKickContact(
					player,
					state,
					"Heartbeat"
					) then

					return
				end

				local age =
					workspace:GetServerTimeNow()
				- state.hitMonitorStartedAt

				if age >=
					AERIAL_KICK_CONTACT_MONITOR_MAX_DURATION then

					state.hitUsed =
						true

					state.hitMonitoring =
						false

					aerialKickEvent:
						FireClient(
							player,
							"ContactTimeout",
							state.sequence,
							"MaxDuration"
						)

					if DEBUG_M1 then
						warn(
							"[AerialKick-Server] CONTACT TIMEOUT",
							player.Name,
							state.sequence,
							string.format(
								"%.2f",
								age
							)
						)
					end

					return
				end
			end
		end
	)
end


aerialKickEvent.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: string,
			sequence: number,
			clientTimestamp: number?
		)

			if typeof(action) ~= "string"
				or typeof(sequence) ~= "number" then

				return
			end

			local now =
			workspace:GetServerTimeNow()

			if action == "Start" then
				local character,
				humanoid,
				root =
				getAliveCharacter(
					player
				)

				if not character
					or not humanoid
					or not root then

					return
				end

				local rejectReason: string? =
				nil

				-- CombatMode is owned by the local CombatController in the
				-- current combat architecture. The client AttackController +
				-- AerialKickController already require CombatMode=true before
				-- this RemoteEvent can be sent during normal play.
				--
				-- Do NOT reject here from the server's Character attribute:
				-- that value is not the authoritative mirror used by this
				-- combat stack and was rejecting every legitimate Aerial Kick.
				if character:GetAttribute("IsStunned") == true then
					rejectReason = "IsStunned"
				elseif character:GetAttribute("Status_AttackBlocked") == true then
					rejectReason = "Status_AttackBlocked"
				elseif character:GetAttribute("Status_Stunned") == true then
					rejectReason = "Status_Stunned"
				elseif character:GetAttribute("CombatSuppressed") == true then
					rejectReason = "CombatSuppressed"
				elseif character:GetAttribute("JutsuCasting") == true then
					rejectReason = "JutsuCasting"
				elseif isDownedSystemLocked(character) then
					rejectReason = "DownedLocked"
				elseif not isAerialKickServerAirborne(humanoid) then
					rejectReason = "NotAirborne"
				elseif character:GetAttribute("AirComboServerActive") == true then
					rejectReason = "LauncherAirCombo"
				elseif now <
					(aerialKickCooldownUntil[player] or -math.huge) then

					rejectReason = "Cooldown"
				end

				if rejectReason then
					if DEBUG_M1 then
						print(
							"[AerialKick-Server] START REJECT",
							player.Name,
							sequence,
							rejectReason,
							"state",
							humanoid:GetState().Name,
							"floor",
							humanoid.FloorMaterial.Name,
							"velocityY",
							string.format(
								"%.2f",
								root.AssemblyLinearVelocity.Y
							)
						)
					end

					aerialKickEvent:
					FireClient(
						player,
						"StartRejected",
						sequence,
						rejectReason
					)

					return
				end

				aerialKickCooldownUntil[player] =
				now
				+ AERIAL_KICK_SERVER_COOLDOWN

				aerialKickStates[player] = {
					sequence = sequence,
					startedAt = now,
					damageOpen = false,
					hitUsed = false,
					hitMonitoring = false,
					hitMonitorStartedAt = -math.huge,
				}

				task.delay(
					AERIAL_KICK_STATE_TIMEOUT,
					function()
						local current =
						aerialKickStates[player]

						if current
							and current.sequence == sequence then

							clearAerialKickState(
								player
							)
						end
					end
				)

				if DEBUG_M1 then
					print(
						"[AerialKick-Server] START",
						player.Name,
						sequence
					)
				end

				return
			end

			local state =
			aerialKickStates[player]

			if not state
				or state.sequence ~= sequence then

				return
			end

			if action == "DamageStart" then
				state.damageOpen =
				true

				return
			end

			if action == "Hit" then
				startAerialKickContactMonitor(
					player,
					state,
					clientTimestamp
				)

				return
			end

			if action == "GroundApproach" then
				if state.hitMonitoring == true
					and not state.hitUsed then

					tryResolveAerialKickContact(
						player,
						state,
						"ClientGroundApproach"
					)
				end

				return
			end

			if action == "DamageEnd" then
				-- Once Hit marker starts the live contact dive, its monitor owns
				-- resolution even if the authored DamageEnd arrives afterward.
				if state.hitMonitoring ~= true then
					state.damageOpen =
					false
				end

				return
			end

			if action == "End"
				or action == "Cancel" then

				clearAerialKickState(
					player
				)

				return
			end
		end
	)


-- =========================
-- BLOCK REQUEST
-- =========================

blockRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: string
		)

			if action == "Start" then
				local character,
				humanoid =
				getAliveCharacter(
					player
				)

				if not character
					or not humanoid then

					return
				end

				if humanoid:GetState()
					== Enum.HumanoidStateType.Swimming then

					return
				end

				if character:GetAttribute(
					"JutsuCasting"
					) == true then

					return
				end

				local launcherAirVictim =
				character:GetAttribute(
					"AirComboServerActive"
				) == true
				and character:GetAttribute(
					"AirComboRole"
				) == "Victim"
				and character:GetAttribute(
					"LauncherAirComboVictim"
				) == true

				if character:GetAttribute(
					"IsStunned"
					) == true
					and not launcherAirVictim then

					return
				end

				if isDownedSystemLocked(
					character
					) then

					return
				end

				local guardState =
				getGuardState(
					player
				)

				if isGuardBreakLocked(
					player
					) then

					if DEBUG_M1 then
						print(
							"[Block-Server] REJECT GuardBroken",
							player.Name,
							"remaining=",
							string.format(
								"%.2f",
								math.max(
									0,
									guardState.brokenUntil
									- workspace:
									GetServerTimeNow()
								)
							)
						)
					end

					return
				end

				blockStates[
				player
				] = {
					active = true,
					startedAt = time(),
				}

				if DEBUG_M1 then
					print(
						"[Block-Server] Start",
						player.Name
					)
				end

			elseif action == "End" then

				blockStates[
				player
				] = nil

				if DEBUG_M1 then
					print(
						"[Block-Server] End",
						player.Name
					)
				end
			end
		end
	)


-- =========================
-- CLIENT ANIMATION START SANITIZATION
-- =========================
-- Kept for marker timestamp validation / Motion Compensation.

local function sanitizeAnimationStartedAt(
	clientStartedAt: number?
): number

	local serverNow =
		workspace:
		GetServerTimeNow()

	if typeof(clientStartedAt)
		~= "number" then

		return serverNow
	end

	if math.abs(
		clientStartedAt
		- serverNow
		) > MAX_ANIMATION_START_CLOCK_ERROR then

		return serverNow
	end

	return clientStartedAt
end


-- =========================
-- SERVER COMBO VALIDATION
-- =========================

local function getLauncherAirM1State(
	player: Player
): any?
	local character = player.Character

	if not character
		or character:GetAttribute("LauncherAirComboAttacker") ~= true
		or character:GetAttribute("AirM1Allowed") ~= true
		or character:GetAttribute("AirComboRole") ~= "Attacker"
		or character:GetAttribute("AirComboServerActive") ~= true then
		return nil
	end

	local airComboId = character:GetAttribute("AirComboId")
	if typeof(airComboId) ~= "number" then
		return nil
	end

	local airState = launcherAirM1States[player]
	if not airState or airState.airComboId ~= airComboId then
		airState = {
			airComboId = airComboId,
			nextStartCombo = 1,
			nextHitCombo = 1,
			confirmedHits = 0,
			lastStartedAt = -math.huge,
			lastHitAt = -math.huge,
			startedCombos = {},
		}
		launcherAirM1States[player] = airState

		local groundState = serverComboStates[player]
		if groundState then
			groundState.fullComboLockedUntil = -math.huge
		end
	end

	return airState
end


local function acceptComboNumber(
	player: Player,
	requestedCombo: number,
	now: number
): number?
	local airState = getLauncherAirM1State(player)

	-- Launcher Start is a commitment signal, not the damage authority. Never
	-- deadlock the aerial chain because a prior Start/Hit arrived on a different
	-- frame. HIT confirmation order below remains strictly 1 -> 5.
	if airState then
		if now - airState.lastStartedAt < LAUNCHER_AIR_MIN_START_INTERVAL then
			if DEBUG_M1 then
				warn(
					"[M1-Server] Launcher air START rejected by interval",
					player.Name,
					string.format("%.3f", now - airState.lastStartedAt)
				)
			end
			return nil
		end

		if requestedCombo ~= airState.nextStartCombo and DEBUG_M1 then
			warn(
				"[M1-Server] Launcher air START resync:",
				player.Name,
				"airCombo", airState.airComboId,
				"requested", requestedCombo,
				"expected", airState.nextStartCombo,
				"hitExpected", airState.nextHitCombo
			)
		end

		airState.lastStartedAt = now
		airState.startedCombos[requestedCombo] = true

		if requestedCombo >= 5 then
			airState.nextStartCombo = 1
		else
			airState.nextStartCombo = requestedCombo + 1
		end
		return requestedCombo
	end

	launcherAirM1States[player] = nil

	local state = serverComboStates[player]
	if not state then
		state = {
			nextCombo = 1,
			lastStartedAt = -math.huge,
			fullComboLockedUntil = -math.huge,
		}
		serverComboStates[player] = state
	end

	if now - state.lastStartedAt > SERVER_COMBO_SEQUENCE_WINDOW then
		if DEBUG_M1 and state.nextCombo ~= 1 then
			print(
				"[M1-Server] Combo server timeout reset",
				player.Name,
				"expected",
				state.nextCombo
			)
		end
		state.nextCombo = 1
	end

	if requestedCombo == 1
		and now < (state.fullComboLockedUntil or -math.huge) then
		if DEBUG_M1 then
			print(
				"[M1-Server] Full combo cooldown reject",
				player.Name,
				string.format(
					"%.2fs",
					math.max(0, state.fullComboLockedUntil - now)
				)
			)
		end
		return nil
	end

	if requestedCombo == 1 then
		state.nextCombo = 2
		state.lastStartedAt = now
		return 1
	end

	if requestedCombo ~= state.nextCombo then
		if DEBUG_M1 then
			warn(
				"[M1-Server] Combo order rejected:",
				player.Name,
				"requested",
				requestedCombo,
				"expected",
				state.nextCombo
			)
		end
		return nil
	end

	if requestedCombo >= 5 then
		state.nextCombo = 1
		state.fullComboLockedUntil = now + SERVER_FULL_COMBO_RESTART_LOCK
	else
		state.nextCombo = requestedCombo + 1
	end
	state.lastStartedAt = now
	return requestedCombo
end


local function resolveLauncherAirHit(
	player: Player,
	airState: any,
	requestedAirHit: number,
	impactTime: number?,
	source: string
): boolean
	local currentAirState = getLauncherAirM1State(player)
	if not currentAirState
		or currentAirState ~= airState
		or currentAirState.airComboId ~= airState.airComboId then
		return false
	end

	if requestedAirHit ~= currentAirState.nextHitCombo then
		return false
	end

	local now = time()
	if now - currentAirState.lastHitAt < LAUNCHER_AIR_MIN_CONFIRMED_HIT_INTERVAL then
		return false
	end

	local hitConfirmed = performM1Hitbox(
		player,
		requestedAirHit,
		impactTime
	)

	if not hitConfirmed then
		if DEBUG_M1 then
			warn(
				"[M1-Server] Launcher air expected hit produced no confirmed target",
				player.Name,
				"M1_" .. requestedAirHit,
				"source", source
			)
		end
		return false
	end

	currentAirState.lastHitAt = now
	currentAirState.confirmedHits += 1
	currentAirState.startedCombos[requestedAirHit] = nil

	if requestedAirHit >= 5 then
		currentAirState.nextHitCombo = 1
	else
		currentAirState.nextHitCombo = requestedAirHit + 1
	end

	if DEBUG_M1 then
		print(
			"[M1-Server] Launcher air confirmed sequence",
			player.Name,
			currentAirState.confirmedHits .. "/5",
			"M1_" .. requestedAirHit,
			"source", source
		)
	end

	return true
end


local function resetServerCombo(
	player: Player
)
	launcherAirM1States[player] = nil

	serverComboStates[
	player
	] = {
		nextCombo = 1,
		lastStartedAt = -math.huge,
		fullComboLockedUntil = -math.huge,
	}
end


-- =========================
-- LUNGE REQUEST
-- =========================
--
-- Start:
-- FireServer("Start", sequence, animationStartedAt)
--
-- Authored markers:
-- FireServer("DamageStart" | "DamageEnd" | "ClashStart" | "ClashEnd",
--            sequence, markerAt)
--
-- Damage is NOT a one-frame request anymore.
-- DamageStart opens a moving server-authoritative forward volume.
-- DamageEnd closes it.
--
-- End/Cancel:
-- FireServer("End" | "Cancel", sequence)

lungeRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: string,
			sequence: number,
			clientTimestamp: number?,
			clientWaterWalk: boolean?
		)
			if typeof(sequence) ~= "number" then
				return
			end

			local now = time()

			if action == "Start" then
				local character, humanoid, root = getAliveCharacter(player)
				if not character or not humanoid or not root then
					return
				end

				if character:GetAttribute("IsStunned") == true
					or character:GetAttribute("JutsuCasting") == true
					or isDownedSystemLocked(character)
					or character:GetAttribute("CombatRagdolled") == true then
					return
				end

				local surfaceWalking =
				character:GetAttribute("SurfaceWalking") == true

				-- SurfaceController is client-owned, so its WaterWalking attribute
				-- is not authoritative on the server. LungeController explicitly
				-- includes its Water Walk state in Start; the server then validates
				-- that claim against an actual Terrain Water surface under the feet.
				local requestedWaterWalk =
				clientWaterWalk == true

				local waterWalkGrounded =
				requestedWaterWalk
				and isLungeStartNearWaterSurface(
					character,
					root
				)

				-- Water Walk is virtual flat ground for Lunge. Normal ground keeps
				-- the original solid-ground validation.
				if not waterWalkGrounded
					and not isLungeStartNearGround(
						character,
						root
					) then

					if DEBUG_M1 then
						warn(
							"[Lunge-Server] Start rejected: not near valid ground",
							player.Name,
							"requestedWaterWalk",
							requestedWaterWalk,
							"waterRay",
							waterWalkGrounded
						)
					end

					return
				end

				-- Walls/ceilings stay excluded. Water Walking is explicitly allowed.
				if surfaceWalking and not waterWalkGrounded then
					return
				end

				if now < (lungeCooldownUntil[player] or -math.huge) then
					return
				end

				if not serverComboAllowsLunge(player, now) then
					if DEBUG_M1 then
						warn(
							"[Lunge-Server] Start rejected: combo not at opener",
							player.Name
						)
					end
					return
				end

				local speed,
				forwardDot,
				lungeDirection,
				moveForwardDot =
				getLungeStartHorizontalData(
					root,
					humanoid
				)

				local movementAccepted: boolean

				if waterWalkGrounded then
					-- SurfaceController owns Water Walk locomotion and can flatten/
					-- delay replicated AssemblyLinearVelocity around this exact frame.
					-- The server already verified WaterWalking+SurfaceWalking, so use
					-- replicated movement intent/facing as the Water Walk start gate.
					movementAccepted =
					moveForwardDot
					>= LUNGE_MIN_SERVER_WATER_MOVE_DOT
					or (
						speed
						>= LUNGE_MIN_SERVER_WATER_HORIZONTAL_SPEED
						and forwardDot
						>= LUNGE_MIN_SERVER_FORWARD_DOT
					)

					if moveForwardDot > -0.5 then
						local move =
						humanoid.MoveDirection

						local horizontalMove =
						Vector3.new(
							move.X,
							0,
							move.Z
						)

						if horizontalMove.Magnitude > 0.05 then
							lungeDirection =
							horizontalMove.Unit
						end
					end
				else
					movementAccepted =
					speed
					>= LUNGE_MIN_SERVER_HORIZONTAL_SPEED
					and forwardDot
					>= LUNGE_MIN_SERVER_FORWARD_DOT
				end

				if not movementAccepted then

					if DEBUG_M1 then
						warn(
							"[Lunge-Server] Start rejected: movement",
							player.Name,
							"waterWalk",
							waterWalkGrounded,
							"speed",
							string.format("%.1f", speed),
							"velocityDot",
							string.format("%.2f", forwardDot),
							"moveDot",
							string.format("%.2f", moveForwardDot)
						)
					end

					return
				end

				local animationStartedAt =
				sanitizeAnimationStartedAt(
					clientTimestamp
				)

				lungeStates[player] = {
					sequence = sequence,
					startedAt = now,
					animationStartedAt = animationStartedAt,
					startedOnWaterWalk = waterWalkGrounded,
					serverDirection = lungeDirection,

					damageActive = false,
					damageStartReceived = false,
					damageEndReceived = false,
					damageOpenedAt = nil,

					hitTargets = {},
					anyInteraction = false,

					lastDamagePose = nil,
					lastDamageSampleAt = nil,

					clashActive = false,
				}

				lungeCooldownUntil[player] =
				now
				+ LUNGE_SERVER_COOLDOWN

				character:SetAttribute(
					"ServerLungeActive",
					true
				)

				character:SetAttribute(
					"ServerLungeDamageActive",
					false
				)

				character:SetAttribute(
					"ServerLungeClashActive",
					false
				)

				character:SetAttribute(
					"ServerLungeDirection",
					lungeDirection
				)

				character:SetAttribute(
					"ServerLungeWaterWalk",
					waterWalkGrounded
				)

				scheduleLungeSwingSound(
					player,
					sequence
				)

				task.delay(
					2.10,
					function()

						local state =
						lungeStates[
						player
						]

						if state
							and state.sequence == sequence
							and time()
							- state.startedAt
							>= 2.00 then

							clearLungeState(
								player,
								sequence
							)
						end
					end
				)

				if DEBUG_M1 then
					print(
						"[Lunge-Server] Start",
						player.Name,
						sequence,
						"speed",
						string.format(
							"%.1f",
							speed
						),
						"waterWalk",
						waterWalkGrounded
					)
				end

				return
			end


			if action == "End"
				or action == "Cancel" then

				clearLungeState(
					player,
					sequence
				)

				return
			end


			local state =
			lungeStates[
			player
			]

			if not state
				or state.sequence ~= sequence then

				return
			end


			local elapsed =
			now
			- state.startedAt


			if action == "ClashStart" then

				if elapsed
					< LUNGE_MIN_CLASH_MARKER_TIME
					or elapsed
					> LUNGE_MAX_CLASH_MARKER_TIME then

					return
				end

				if state.clashActive then
					return
				end

				state.clashActive =
				true

				local character =
				player.Character

				if character then
					character:SetAttribute(
						"ServerLungeClashActive",
						true
					)
				end

				if DEBUG_M1 then
					print(
						"[Lunge-Server] ClashStart",
						player.Name,
						sequence
					)
				end

				return
			end


			if action == "ClashEnd" then

				state.clashActive =
				false

				local character =
				player.Character

				if character then
					character:SetAttribute(
						"ServerLungeClashActive",
						false
					)
				end

				if DEBUG_M1 then
					print(
						"[Lunge-Server] ClashEnd",
						player.Name,
						sequence
					)
				end

				return
			end


			if action == "DamageStart" then

				if state.damageStartReceived
					or elapsed
					< LUNGE_MIN_DAMAGE_MARKER_TIME
					or elapsed
					> LUNGE_MAX_DAMAGE_MARKER_TIME then

					return
				end

				local attackerCharacter,
				_attackerHumanoid,
				attackerRoot =
				getAliveCharacter(
					player
				)

				if not attackerCharacter
					or not attackerRoot
					or isDownedSystemLocked(
						attackerCharacter
					)
					or attackerCharacter:GetAttribute(
						"IsStunned"
					) == true then

					clearLungeState(
						player,
						sequence
					)

					return
				end

				state.damageStartReceived =
				true

				state.damageActive =
				true

				state.damageOpenedAt =
				workspace:
				GetServerTimeNow()

				local impactTime,
				rewindSeconds =
				sanitizeLungeMarkerTime(
					state,
					clientTimestamp
				)

				local startPose =
				getPoseAt(
					attackerCharacter,
					impactTime
				)
				or attackerRoot.CFrame

				state.lastDamagePose =
				startPose

				state.lastDamageSampleAt =
				impactTime

				attackerCharacter:SetAttribute(
					"ServerLungeDamageActive",
					true
				)

				-- Catch up the first segment that may have elapsed while the
				-- marker RemoteEvent was travelling to the server.
				local serverNow =
				workspace:
				GetServerTimeNow()

				performLungeDamageSweep(
					player,
					state,
					startPose,
					attackerRoot.CFrame,
					impactTime,
					serverNow
				)

				if DEBUG_M1 then
					print(
						"[Lunge-Server] DamageStart",
						player.Name,
						sequence,
						"rewind",
						string.format(
							"%.3fs",
							rewindSeconds
						),
						"box",
						tostring(
							LUNGE_HITBOX_SIZE
						)
					)
				end

				return
			end


			if action == "DamageEnd" then

				if state.damageEndReceived then
					return
				end

				state.damageEndReceived =
				true

				local attackerCharacter,
				_attackerHumanoid,
				attackerRoot =
				getAliveCharacter(
					player
				)

				if attackerCharacter
					and attackerRoot
					and state.damageStartReceived then

					local impactTime =
					select(
						1,
						sanitizeLungeMarkerTime(
							state,
							clientTimestamp
						)
					)

					-- If the last server sweep is still behind the authored end
					-- marker, close that final historical segment exactly at the
					-- marker pose. Never sweep backwards if Heartbeat already
					-- advanced farther.
					local lastTime =
					state.lastDamageSampleAt
					or impactTime

					if lastTime
						<= impactTime then

						local endPose =
						getPoseAt(
							attackerCharacter,
							impactTime
						)
						or attackerRoot.CFrame

						performLungeDamageSweep(
							player,
							state,
							state.lastDamagePose
							or endPose,
							endPose,
							lastTime,
							impactTime
						)
					end
				end

				state.damageActive =
				false

				if attackerCharacter then
					attackerCharacter:SetAttribute(
						"ServerLungeDamageActive",
						false
					)
				end

				if DEBUG_M1 then

					local targetCount =
					0

					for _targetCharacter,
						_wasConsumed in pairs(
							state.hitTargets
						) do

						targetCount +=
						1
					end

					print(
						"[Lunge-Server] DamageEnd",
						player.Name,
						sequence,
						"targetsConsumed",
						targetCount
					)
				end

				return
			end
		end
	)


-- =========================
-- M1 REQUEST
-- =========================
--
-- Contract:
--
-- Start:
-- FireServer("Start", sequence, comboNumber, animationStartedAt)
--
-- Hit v18:
-- FireServer("Hit", sequence, comboNumber, nil, hitMarkerAt)
--
-- Old clients that send only ("Hit", sequence) still work, but receive no
-- historical rewind and therefore behave like v17.1.

m1Request.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: string,
			sequence: number,
			comboNumber: number?,
			clientAnimationStartedAt: number?,
			clientHitAt: number?
		)

			if typeof(sequence)
				~= "number" then

				return
			end

			local now =
			time()

			if action == "Start" then

				local activeLunge = lungeStates[player]
				if activeLunge then
					local lungeElapsed = now - activeLunge.startedAt
					if lungeElapsed < LUNGE_MIN_M1_FOLLOWUP_TIME then
						if DEBUG_M1 then
							warn(
								"[M1-Server] Start rejected: overlaps Lunge",
								player.Name,
								string.format("%.3f", lungeElapsed)
							)
						end
						return
					end

					clearLungeState(player)
				end

				local character =
				getAliveCharacter(
					player
				)

				if not character then
					return
				end

				if character:GetAttribute(
					"IsStunned"
					) == true then

					return
				end

				if character:GetAttribute(
					"JutsuCasting"
					) == true then

					return
				end

				if isDownedSystemLocked(
					character
					) then

					return
				end

				local previousState =
				attackStates[
				player
				]

				local launcherAirState =
				getLauncherAirM1State(player)

				-- Packet arrival spacing stays for ground M1. Launcher air is
				-- protected by strict authored START/HIT sequence instead.
				local serverAttackInterval =
				resolveServerAttackInterval(
					character
				)

				if not launcherAirState
					and previousState
					and now
					- previousState.startedAt
					< serverAttackInterval then

					if DEBUG_M1 then
						warn(
							"[M1-Server] Start rejected by interval",
							player.Name,
							string.format(
								"%.3f < %.3f",
								now - previousState.startedAt,
								serverAttackInterval
							)
						)
					end

					return
				end

				local requestedComboNumber =
				if typeof(comboNumber)
				== "number"
				and comboNumber >= 1
				and comboNumber <= 5
				then math.floor(
					comboNumber
				)
				else 1

				local acceptedComboNumber =
				acceptComboNumber(
					player,
					requestedComboNumber,
					now
				)

				if not acceptedComboNumber then
					return
				end

				local animationStartedAt =
				sanitizeAnimationStartedAt(
					clientAnimationStartedAt
				)

				attackStates[
				player
				] = {
					sequence =
					sequence,

					startedAt =
					now,

					hitUsed =
					false,

					comboNumber =
					acceptedComboNumber,

					animationStartedAt =
					animationStartedAt,

					launcherAirComboId =
					launcherAirState
					and launcherAirState.airComboId
					or nil,
				}

				scheduleSwingSound(
					player,
					sequence,
					acceptedComboNumber,
					animationStartedAt
				)


				if DEBUG_M1 then
					print(
						"[M1-Server] Start",
						player.Name,
						sequence,
						"M1_"
						.. acceptedComboNumber
					)
				end

				if launcherAirState then
					local airStateSnapshot = launcherAirState
					local airComboIdSnapshot = launcherAirState.airComboId
					local comboSnapshot = acceptedComboNumber

					task.delay(
						LAUNCHER_AIR_HIT_FAILSAFE_DELAY,
						function()
							local currentAirState = getLauncherAirM1State(player)
							if not currentAirState
								or currentAirState ~= airStateSnapshot
								or currentAirState.airComboId ~= airComboIdSnapshot
								or currentAirState.nextHitCombo ~= comboSnapshot
								or currentAirState.startedCombos[comboSnapshot] ~= true then
								return
							end

							if DEBUG_M1 then
								warn(
									"[M1-Server] Launcher air marker FAILSAFE",
									player.Name,
									"airCombo", airComboIdSnapshot,
									"M1_" .. comboSnapshot
								)
							end

							resolveLauncherAirHit(
								player,
								currentAirState,
								comboSnapshot,
								workspace:GetServerTimeNow(),
								"StartFailsafe"
							)
						end
					)
				end

				return
			end

			if action ~= "Hit" then
				return
			end

			local state =
			attackStates[
			player
			]

			local launcherAirState =
			getLauncherAirM1State(player)

			-- Never reinterpret a late Launcher-air Hit packet as a normal M1 after
			-- M2, Kawarimi, M1_5 or timeout already ended that aerial pair.
			if state
				and typeof(state.launcherAirComboId) == "number"
				and (
					not launcherAirState
					or launcherAirState.airComboId ~= state.launcherAirComboId
				) then

				if DEBUG_M1 then
					warn(
						"[M1-Server] stale Launcher air HIT discarded after AirEnd",
						player.Name,
						"airCombo",
						state.launcherAirComboId,
						"sequence",
						sequence
					)
				end

				attackStates[player] = nil
				launcherAirM1States[player] = nil
				return
			end

			-- Launcher air has a server-established target pair and a redundant hit
			-- path. Marker is primary; Start-failsafe/backfill prevents a marker race
			-- from poisoning the remainder of the 1 -> 5 sequence.
			if launcherAirState then
				local requestedAirHit =
				if typeof(comboNumber) == "number"
				then math.floor(comboNumber)
				else -1

				if requestedAirHit < 1 or requestedAirHit > 5 then
					return
				end

				-- If a later marker arrives while an earlier committed Start is still
				-- unresolved, resolve the missing committed strike first. This is safe
				-- because LauncherServerCore already fixed the attacker/victim pair.
				while requestedAirHit > launcherAirState.nextHitCombo do
					local missingCombo = launcherAirState.nextHitCombo
					if launcherAirState.startedCombos[missingCombo] ~= true then
						break
					end

					if DEBUG_M1 then
						warn(
							"[M1-Server] Launcher air backfill before later marker",
							player.Name,
							"missing", missingCombo,
							"arrived", requestedAirHit
						)
					end

					if not resolveLauncherAirHit(
						player,
						launcherAirState,
						missingCombo,
						workspace:GetServerTimeNow(),
						"Backfill"
						) then
						break
					end
				end

				if requestedAirHit ~= launcherAirState.nextHitCombo then
					if DEBUG_M1 then
						warn(
							"[M1-Server] Launcher air HIT ignored after recovery:",
							player.Name,
							"airCombo", launcherAirState.airComboId,
							"requested", requestedAirHit,
							"expected", launcherAirState.nextHitCombo
						)
					end
					return
				end

				local impactTime = workspace:GetServerTimeNow()
				if state
					and state.sequence == sequence
					and not state.hitUsed then
					state.hitUsed = true
					impactTime = select(
						1,
						sanitizeHitMarkerTime(state, clientHitAt)
					)
				end

				resolveLauncherAirHit(
					player,
					launcherAirState,
					requestedAirHit,
					impactTime,
					"Marker"
				)
				return
			end

			if not state
				or state.sequence ~= sequence
				or state.hitUsed then
				return
			end


			local elapsed =
			now
			- state.startedAt

			if elapsed < MIN_HIT_TIME
				or elapsed > MAX_HIT_TIME then

				if DEBUG_M1 then
					warn(
						"[M1-Server] Hit rejected by timing:",
						player.Name,
						elapsed
					)
				end

				return
			end

			local attackerCharacter =
			player.Character

			if not attackerCharacter
				or isDownedSystemLocked(
					attackerCharacter
				) then

				attackStates[
				player
				] = nil

				return
			end

			if attackerCharacter:GetAttribute(
				"IsStunned"
				) == true then

				attackStates[
				player
				] = nil

				return
			end

			state.hitUsed = true

			local impactTime,
			rewindSeconds =
			sanitizeHitMarkerTime(
				state,
				clientHitAt
			)

			if DEBUG_M1
				and rewindSeconds > 0.001 then

				print(
					"[M1-Server] marker rewind",
					player.Name,
					"M1_"
					.. state.comboNumber,
					string.format(
						"%.3fs",
						rewindSeconds
					)
				)
			end

			performM1Hitbox(
				player,
				state.comboNumber,
				impactTime
			)
		end
	)


-- =========================
-- CHARACTER INIT / CLEANUP
-- =========================

local function initializeCombatCharacter(
	player: Player,
	character: Model
)
	attackStates[
	player
	] = nil

	blockStates[
	player
	] = nil

	lungeStates[player] = nil
	lungeCooldownUntil[player] = nil
	character:SetAttribute("ServerLungeActive", false)
	character:SetAttribute("ServerLungeDamageActive", false)
	character:SetAttribute("ServerLungeClashActive", false)
	character:SetAttribute("ServerLungeDirection", nil)
	character:SetAttribute("ServerLungeWaterWalk", false)

	local guardState =
		getGuardState(
			player
		)

	guardState.value =
		GUARD_MAX

	guardState.lastDamageAt =
		-math.huge

	guardState.brokenUntil =
		0

	guardState.lastReplicatedValue =
		-1

	replicateGuardState(
		player,
		guardState
	)

	resetServerCombo(
		player
	)

	stunVersions[
	character
	] = 0

	poseHistories[
	character
	] = {}

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if root
		and root:IsA("BasePart") then

		recordPose(
			character,
			root,
			workspace:
				GetServerTimeNow()
		)
	end

	character:
		SetAttribute(
			"IsStunned",
			false
		)

	character:
		SetAttribute(
			"StunEndsAt",
			nil
		)

	local function clearCombatRequestsIfLocked()

		if isDownedSystemLocked(
			character
			)
				or character:GetAttribute(
					"JutsuCasting"
				) == true then

			attackStates[
			player
			] = nil

			blockStates[
			player
			] = nil

			clearLungeState(player)
			clearAerialKickState(player)
		end
	end

	character:
		GetAttributeChangedSignal(
			"DownedActionLocked"
		):
		Connect(
			clearCombatRequestsIfLocked
		)

	character:
		GetAttributeChangedSignal(
			"IsCarrying"
		):
		Connect(
			clearCombatRequestsIfLocked
		)

	character:
		GetAttributeChangedSignal(
			"IsExecuting"
		):
		Connect(
			clearCombatRequestsIfLocked
		)

	character:
		GetAttributeChangedSignal(
			"JutsuCasting"
		):
		Connect(
			clearCombatRequestsIfLocked
		)

	character:
		GetAttributeChangedSignal(
			"AirComboServerActive"
		):
		Connect(
			function()
				if character:GetAttribute(
					"AirComboServerActive"
					) == true then
					return
				end

				local activeAttack = attackStates[player]
				if activeAttack
					and typeof(activeAttack.launcherAirComboId) == "number" then
					attackStates[player] = nil
				end

				launcherAirM1States[player] = nil
			end
		)
end


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			local character =
			player.Character

			if character then
				poseHistories[
				character
				] = nil
			end

			attackStates[
			player
			] = nil

			blockStates[
			player
			] = nil

			guardStates[
			player
			] = nil

			serverComboStates[
			player
			] = nil

			launcherAirM1States[player] = nil

			lungeStates[player] = nil
			lungeCooldownUntil[player] = nil

			aerialKickStates[player] = nil
			aerialKickCooldownUntil[player] = nil
		end
	)


Players.PlayerAdded:
	Connect(
		function(
			player: Player
		)

			player.CharacterAdded:
			Connect(
				function(
					character: Model
				)

					initializeCombatCharacter(
						player,
						character
					)
				end
			)
		end
	)


for _, player in ipairs(
	Players:GetPlayers()
	) do

	if player.Character then
		initializeCombatCharacter(
			player,
			player.Character
		)
	end

	player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				initializeCombatCharacter(
					player,
					character
				)
			end
		)
end
