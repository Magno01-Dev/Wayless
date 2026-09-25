--!strict
-- ProjectileServer v3.0 - Locked Target + Aim Assist + Guidance/Commit
-- ServerScriptService > ProjectileServer
--
-- Replaces:
-- KunaiServer
-- ShurikenServer
-- SenbonServer
--
-- Shared definitions live in:
-- ReplicatedStorage > ProjectileConfigs
--
-- Shared clash lives in:
-- ServerScriptService > ProjectileInteractionService
--
-- Shared projectile damage/armor pipeline:
-- ServerScriptService > ProjectileDamageService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local ProjectileConfigs =
	require(
		ReplicatedStorage:
		WaitForChild(
			"ProjectileConfigs"
		)
	)

local ProjectileInteractionService =
	require(
		script.Parent:
		WaitForChild(
			"ProjectileInteractionService"
		)
	)

local ProjectileDamageService =
	require(
		script.Parent:
		WaitForChild(
			"ProjectileDamageService"
		)
	)


local NinjaBagService =
	require(
		script.Parent:
		WaitForChild(
			"NinjaBagService"
		)
	)

local PROJECTILE_TARGET_TAG =
	"ProjectileTarget"

local CLIENT_AIM_MIN_DOT_WITH_TARGET =
	math.cos(
		math.rad(
			20
		)
	)

local GLOBAL_THROW_LOCK =
	0.16

local POST_CLASH_SEPARATION =
	0.28


-- =========================
-- PROJECTILE CLASH SFX
-- =========================
--
-- Global projectile-vs-projectile impact sound.
-- This is intentionally centralized here so every current and future
-- projectile automatically uses the same clash feedback unless we later add
-- per-projectile overrides.

local PROJECTILE_CLASH_AUDIO = {
	SoundId = "rbxassetid://91709243524873",

	Volume = 0.90,
	PlaybackSpeed = 1.00,

	StartTimePosition = 0.00,
	StartDelay = 0.00,

	Looped = false,

	RollOffMinDistance = 7,
	RollOffMaxDistance = 120,
	EmitterSize = 4,
}


local DEBUG_PROJECTILES =
	true

-- =========================
-- PROJECTILE PROFILE (v3)
-- =========================
--
-- Reusable per-projectile tuning profile.
--
-- Everything in PROFILE_DEFAULTS is only a DEFAULT. Any projectile may
-- override any field from:
--
-- ReplicatedStorage > ProjectileConfigs > <Projectile> > Guidance
--
-- Legacy v2.6 field names are still read, so this file keeps working with the
-- CURRENT ProjectileConfigs module without editing it. When a legacy name and
-- a new name both exist, the new name wins.
--
-- Future throwables (Fuma, variants, etc.) only need different NUMBERS here or
-- in their config entry; no new code path is required.

local PROFILE_DEFAULTS = {
	-- ---------- 1. TARGET SELECTION (release time only) ----------
	AimAssistConeDegrees = 16,
	AimAssistRange = 260,
	AimAssistMaxCorrectionDegrees = 16,
	AimAssistRequireLineOfSight = true,
	AimAssistDirectRayPriority = true,

	-- Angular error dominates the score; distance is only a tie-breaker.
	AimAssistAngleWeight = 1.0,
	AimAssistDistanceWeight = 0.012,

	-- ---------- 2 / 3. PREDICTION ----------
	PredictionStrength = 1.0,
	MaxPredictionTime = 0.55,
	MaxPredictionSpeed = 70,
	MaxLeadDistance = 60,

	-- Horizontal movement is what we want to lead. Falls, launchers and
	-- network corrections are mostly vertical, so they are damped hard.
	VerticalVelocityFactor = 0.35,

	-- Exponential smoothing applied to the sampled target velocity.
	-- 0 = frozen, 1 = raw AssemblyLinearVelocity (never use 1).
	PredictionSmoothing = 0.40,

	-- Any instantaneous velocity above this is treated as a knockback /
	-- teleport / replication artifact and is discarded, not clamped.
	IgnoreVelocityAbove = 220,

	-- Aim slightly above the HumanoidRootPart center (chest / torso mass).
	AimPointHeightOffset = 0.35,

	-- ---------- 6. DASH ----------
	DashPredictionEnabled = true,
	DashAssumedRemaining = 0.16,

	-- The Dash system is client-driven and does not publish DashDirection /
	-- DashSpeed / DashEndsAt, so the server also detects a dash from the
	-- replicated horizontal speed. Ground dash = 75, air dash = 105,
	-- normal sprint is well below this.
	DashSpeedThreshold = 58,
	DashMaxPredictionTime = 0.22,
	BreakTrackingOnDash = false,

	-- ---------- 4. GUIDANCE -> COMMIT ----------
	CanTrack = true,
	GuidanceHz = 15,
	GuidanceDuration = 1.50,

	-- Terminal commit is primarily TIME to impact, with a distance floor.
	CommitTime = 0.20,
	CommitDistance = 14,

	MidDistance = 45,
	AcquireRange = 300,

	SteeringStrength = 1.0,
	MaxTurnRateDegreesPerSecond = 120,
	TurnRateNearDegreesPerSecond = 120,
	TurnRateMidDegreesPerSecond = 95,
	TurnRateFarDegreesPerSecond = 70,
	RampTime = 0.12,

	-- 11. VISUAL: no correction at all below this angular error.
	AngularDeadzoneDegrees = 0.6,

	-- Hard cap on how far the projectile may ever deviate from the
	-- direction it was released with.
	MaxTrackingAngleDegrees = 32,

	VerticalAimWeight = 0.55,
	EvasiveLateralSpeed = 18,
	EvasiveTurnMultiplier = 1.25,
	GuidanceRequireLineOfSight = true,

	-- ---------- 9. SUBSTITUTION ----------
	BreakTrackingOnSubstitution = true,

	-- ---------- 10. HITBOX ----------
	-- Logical hitbox radius = visual bounding radius * HitboxScale.
	-- 1.25 is the QA starting point asked for (+15% .. +30% over the visual).
	HitboxScale = 1.25,
	HitboxRadiusMin = 0.35,
	HitboxRadiusMax = 2.25,

	-- ---------- 12. TELEGRAPHING ----------
	NearMissRadius = 3.25,
}


local profileCache: {[string]: any} =
	{}


local function firstNumber(
	...: any
): number?

	for index = 1,
		select(
			"#",
			...
		) do

		local value =
			select(
				index,
				...
			)


		if typeof(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge then

			return value
		end
	end


	return nil
end


local function firstBoolean(
	...: any
): boolean?

	for index = 1,
		select(
			"#",
			...
		) do

		local value =
			select(
				index,
				...
			)


		if typeof(value) == "boolean" then
			return value
		end
	end


	return nil
end


local function buildProfile(
	config: any
): any

	local guidance =
		if typeof(config.Guidance) == "table"
		then config.Guidance
		else {}


	local mode =
		if typeof(guidance.Mode) == "string"
		then guidance.Mode
		else "None"


	-- LaunchAssist projectiles (Shuriken / Senbon today) keep their v2.6
	-- release behaviour byte for byte: same cone, same full snap.
	local isLaunchAssist =
		mode == "LaunchAssist"


	local defaults =
		PROFILE_DEFAULTS


	local legacyCone =
		firstNumber(
			guidance.AcquireConeDegrees
		)


	local aimAssistCone: number


	if firstNumber(guidance.AimAssistConeDegrees) then

		aimAssistCone =
			firstNumber(
				guidance.AimAssistConeDegrees
			) :: number

	elseif isLaunchAssist
		and legacyCone then

		aimAssistCone =
			legacyCone

	else

		aimAssistCone =
			math.min(
				legacyCone
				or defaults.AimAssistConeDegrees,
				defaults.AimAssistConeDegrees
			)
	end


	local aimAssistCorrection: number


	if firstNumber(guidance.AimAssistMaxCorrectionDegrees) then

		aimAssistCorrection =
			firstNumber(
				guidance.AimAssistMaxCorrectionDegrees
			) :: number

	elseif isLaunchAssist then

		-- v2.6 snapped fully to the intercept line for LaunchAssist.
		aimAssistCorrection =
			180

	else

		aimAssistCorrection =
			aimAssistCone
	end


	local commitDistance =
		firstNumber(
			guidance.CommitDistance
		)
		or defaults.CommitDistance


	local maxTurnRate =
		firstNumber(
			guidance.MaxTurnRateDegreesPerSecond,
			guidance.TurnRateNearDegreesPerSecond
		)
		or defaults.MaxTurnRateDegreesPerSecond


	local profile = {
		Id =
			tostring(
				config.Id
			),

		Mode =
			mode,

		-- ---------- target selection ----------
		AimAssistConeDegrees =
			aimAssistCone,

		AimAssistRange =
			firstNumber(
				guidance.AimAssistRange,
				guidance.AcquireRange
			)
			or defaults.AimAssistRange,

		AimAssistMaxCorrectionDegrees =
			aimAssistCorrection,

		AimAssistRequireLineOfSight =
			firstBoolean(
				guidance.AimAssistRequireLineOfSight
			)
			~= false,

		AimAssistDirectRayPriority =
			firstBoolean(
				guidance.AimAssistDirectRayPriority
			)
			~= false,

		AimAssistAngleWeight =
			firstNumber(
				guidance.AimAssistAngleWeight
			)
			or defaults.AimAssistAngleWeight,

		AimAssistDistanceWeight =
			firstNumber(
				guidance.AimAssistDistanceWeight
			)
			or defaults.AimAssistDistanceWeight,

		-- ---------- prediction ----------
		PredictionStrength =
			firstNumber(
				guidance.PredictionStrength,
				guidance.TargetVelocityFactor
			)
			or defaults.PredictionStrength,

		MaxPredictionTime =
			firstNumber(
				guidance.MaxPredictionTime,
				guidance.MaxInterceptTime
			)
			or defaults.MaxPredictionTime,

		MaxPredictionSpeed =
			firstNumber(
				guidance.MaxPredictionSpeed,
				guidance.MaxPredictionVelocity
			)
			or defaults.MaxPredictionSpeed,

		MaxLeadDistance =
			firstNumber(
				guidance.MaxLeadDistance
			)
			or defaults.MaxLeadDistance,

		VerticalVelocityFactor =
			firstNumber(
				guidance.VerticalVelocityFactor
			)
			or defaults.VerticalVelocityFactor,

		PredictionSmoothing =
			math.clamp(
				firstNumber(
					guidance.PredictionSmoothing
				)
				or defaults.PredictionSmoothing,
				0.05,
				0.95
			),

		IgnoreVelocityAbove =
			firstNumber(
				guidance.IgnoreVelocityAbove
			)
			or defaults.IgnoreVelocityAbove,

		AimPointHeightOffset =
			firstNumber(
				guidance.AimPointHeightOffset
			)
			or defaults.AimPointHeightOffset,

		-- ---------- dash ----------
		DashPredictionEnabled =
			firstBoolean(
				guidance.DashPredictionEnabled
			)
			~= false,

		DashAssumedRemaining =
			firstNumber(
				guidance.DashAssumedRemaining
			)
			or defaults.DashAssumedRemaining,

		DashSpeedThreshold =
			firstNumber(
				guidance.DashSpeedThreshold
			)
			or defaults.DashSpeedThreshold,

		DashMaxPredictionTime =
			firstNumber(
				guidance.DashMaxPredictionTime
			)
			or defaults.DashMaxPredictionTime,

		BreakTrackingOnDash =
			firstBoolean(
				guidance.BreakTrackingOnDash
			)
			== true,

		-- ---------- guidance / commit ----------
		CanTrack =
			mode == "Predictive"
			and firstBoolean(
				guidance.CanTrack
			)
			~= false,

		GuidanceHz =
			math.clamp(
				firstNumber(
					guidance.GuidanceHz
				)
				or defaults.GuidanceHz,
				5,
				60
			),

		GuidanceDuration =
			firstNumber(
				guidance.GuidanceDuration
			)
			or defaults.GuidanceDuration,

		CommitTime =
			firstNumber(
				guidance.CommitTime
			)
			or defaults.CommitTime,

		CommitDistance =
			commitDistance,

		MidDistance =
			firstNumber(
				guidance.MidDistance
			)
			or math.max(
				defaults.MidDistance,
				commitDistance * 3
			),

		AcquireRange =
			firstNumber(
				guidance.AcquireRange
			)
			or defaults.AcquireRange,

		SteeringStrength =
			firstNumber(
				guidance.SteeringStrength
			)
			or defaults.SteeringStrength,

		MaxTurnRateDegreesPerSecond =
			maxTurnRate,

		TurnRateNearDegreesPerSecond =
			firstNumber(
				guidance.TurnRateNearDegreesPerSecond
			)
			or maxTurnRate,

		TurnRateMidDegreesPerSecond =
			firstNumber(
				guidance.TurnRateMidDegreesPerSecond
			)
			or maxTurnRate * 0.80,

		TurnRateFarDegreesPerSecond =
			firstNumber(
				guidance.TurnRateFarDegreesPerSecond
			)
			or maxTurnRate * 0.60,

		RampTime =
			math.max(
				0.001,
				firstNumber(
					guidance.RampTime
				)
				or defaults.RampTime
			),

		AngularDeadzoneDegrees =
			firstNumber(
				guidance.AngularDeadzoneDegrees
			)
			or defaults.AngularDeadzoneDegrees,

		-- The legacy TrackMaxFromOriginalDegrees is kept as an ADDITIONAL hard
		-- ceiling, never as the value itself: 88 degrees is exactly what used
		-- to allow near U-turns.
		MaxTrackingAngleDegrees =
			math.min(
				firstNumber(
					guidance.MaxTrackingAngleDegrees
				)
				or defaults.MaxTrackingAngleDegrees,

				firstNumber(
					guidance.TrackMaxFromOriginalDegrees
				)
				or 180
			),

		VerticalAimWeight =
			firstNumber(
				guidance.VerticalAimWeight
			)
			or defaults.VerticalAimWeight,

		EvasiveLateralSpeed =
			firstNumber(
				guidance.EvasiveLateralSpeed
			)
			or defaults.EvasiveLateralSpeed,

		EvasiveTurnMultiplier =
			firstNumber(
				guidance.EvasiveTurnMultiplier
			)
			or defaults.EvasiveTurnMultiplier,

		GuidanceRequireLineOfSight =
			firstBoolean(
				guidance.GuidanceRequireLineOfSight
			)
			~= false,

		-- ---------- counters ----------
		BreakTrackingOnSubstitution =
			firstBoolean(
				guidance.BreakTrackingOnSubstitution
			)
			~= false,

		-- ---------- hitbox ----------
		HitboxRadius =
			firstNumber(
				config.HitboxRadius,
				guidance.HitboxRadius
			),

		HitboxScale =
			firstNumber(
				config.HitboxScale,
				guidance.HitboxScale
			)
			or defaults.HitboxScale,

		HitboxRadiusMin =
			firstNumber(
				guidance.HitboxRadiusMin
			)
			or defaults.HitboxRadiusMin,

		HitboxRadiusMax =
			firstNumber(
				guidance.HitboxRadiusMax
			)
			or defaults.HitboxRadiusMax,

		-- ---------- telegraphing ----------
		NearMissRadius =
			firstNumber(
				config.NearMissRadius,
				guidance.NearMissRadius
			)
			or defaults.NearMissRadius,
	}


	return profile
end


local function getProjectileProfile(
	config: any
): any

	local id =
		tostring(
			config.Id
		)


	local cached =
		profileCache[
	id
	]


	if cached then
		return cached
	end


	local profile =
		buildProfile(
			config
		)


	profileCache[
	id
	] =
		profile


	return profile
end

-- =========================
-- AUTOMATIC DEFENSIVE INTERCEPT
-- =========================
--
-- Reaction + resource choice are the skill checks.
-- Camera flick accuracy is NOT required.
--
-- Valid incoming threat:
-- server overrides the offensive camera direction with a physical intercept.
--
-- No incoming threat:
-- normal CombatAim behavior remains unchanged.

local DEFENSIVE_INTERCEPT_ENABLED =
	true

local DEFENSIVE_THREAT_RADIUS =
	3.65

local DEFENSIVE_THREAT_MAX_TIME =
	0.80

local DEFENSIVE_INTERCEPT_SAFETY_TIME =
	0.025

local DEFENSIVE_MAX_CANDIDATES =
	8


-- The counter animation is intentionally much faster than a normal
-- offensive throw. The server predicts against the actual defensive timing.
local DEFENSIVE_THROW_ANIMATION_SPEED =
	3.0

local DEFENSIVE_PREPARE_RELEASE_DELAY =
	40 / 60 / DEFENSIVE_THROW_ANIMATION_SPEED

local DEFENSIVE_PREPARE_LOOKAHEAD =
	DEFENSIVE_THREAT_MAX_TIME
	+ DEFENSIVE_PREPARE_RELEASE_DELAY
	+ 0.05

local DEFENSIVE_PREPARE_RATE_LIMIT =
	0.05


local warnedMissingIncomingThreatAPI =
	false

-- =========================
-- REMOTES
-- =========================

local remotes =
	ReplicatedStorage:
	FindFirstChild(
		"ProjectileRemotes"
	)

if not remotes then
	remotes =
		Instance.new(
			"Folder"
		)

	remotes.Name =
		"ProjectileRemotes"

	remotes.Parent =
		ReplicatedStorage
end


local requestRemote =
	remotes:
	FindFirstChild(
		"ProjectileRequest"
	)

if not requestRemote then
	requestRemote =
		Instance.new(
			"RemoteEvent"
		)

	requestRemote.Name =
		"ProjectileRequest"

	requestRemote.Parent =
		remotes
end

local projectileRequest =
	requestRemote :: RemoteEvent


-- Dedicated OFF-COMBAT defensive request.
--
-- Keeping this separate from ProjectileRequest restores the previously stable
-- offensive contract and prevents defensive-only validation from blocking
-- normal Combat Mode throws.
local defenseRequestInstance =
	remotes:
	FindFirstChild(
		"ProjectileDefenseRequest"
	)

if not defenseRequestInstance then
	defenseRequestInstance =
		Instance.new(
			"RemoteEvent"
		)

	defenseRequestInstance.Name =
		"ProjectileDefenseRequest"

	defenseRequestInstance.Parent =
		remotes
end

local projectileDefenseRequest =
	defenseRequestInstance :: RemoteEvent


-- Read-only server preflight.
--
-- Used only when CombatMode is OFF. It answers:
-- "If the throw animation begins NOW, is there a genuine enemy projectile
-- that is projected to remain interceptable at the release marker?"
--
-- It does NOT:
-- - consume ammo
-- - start cooldown
-- - enter CombatMode
-- - launch a projectile
local defensePrepareInstance =
	remotes:
	FindFirstChild(
		"ProjectileDefensePrepare"
	)

if not defensePrepareInstance then

	defensePrepareInstance =
		Instance.new(
			"RemoteFunction"
		)

	defensePrepareInstance.Name =
		"ProjectileDefensePrepare"

	defensePrepareInstance.Parent =
		remotes
end

local projectileDefensePrepare =
	defensePrepareInstance :: RemoteFunction


local acceptedRemote =
	remotes:
	FindFirstChild(
		"ProjectileThrowAccepted"
	)

if not acceptedRemote then
	acceptedRemote =
		Instance.new(
			"RemoteEvent"
		)

	acceptedRemote.Name =
		"ProjectileThrowAccepted"

	acceptedRemote.Parent =
		remotes
end

local projectileThrowAccepted =
	acceptedRemote :: RemoteEvent


local combatStateRemote =
	remotes:
	FindFirstChild(
		"ProjectileCombatState"
	)

if not combatStateRemote then
	combatStateRemote =
		Instance.new(
			"RemoteEvent"
		)

	combatStateRemote.Name =
		"ProjectileCombatState"

	combatStateRemote.Parent =
		remotes
end

local projectileCombatState =
	combatStateRemote :: RemoteEvent


-- Dedicated replicated VFX event.
--
-- IMPORTANT:
-- ParticleEmitter:Emit() is executed on each client, not on the server.
-- The server remains authoritative about WHEN and WHERE a clash occurred;
-- clients are only responsible for rendering the visual burst.
local clashVFXRemoteInstance =
	remotes:
	FindFirstChild(
		"ProjectileClashVFX"
	)

if not clashVFXRemoteInstance then
	clashVFXRemoteInstance =
		Instance.new(
			"RemoteEvent"
		)

	clashVFXRemoteInstance.Name =
		"ProjectileClashVFX"

	clashVFXRemoteInstance.Parent =
		remotes
end

local projectileClashVFX =
	clashVFXRemoteInstance :: RemoteEvent



-- Near-miss / telegraphing hook (section 12).
--
-- Fired to the DEFENDER when a projectile passes close to them without
-- connecting. Purely cosmetic: the client may play a whoosh, a camera shake or
-- nothing at all. Adding a listener is optional; nothing breaks without one.
local nearMissRemoteInstance =
	remotes:
	FindFirstChild(
		"ProjectileNearMiss"
	)

if not nearMissRemoteInstance then

	nearMissRemoteInstance =
		Instance.new(
			"RemoteEvent"
		)

	nearMissRemoteInstance.Name =
		"ProjectileNearMiss"

	nearMissRemoteInstance.Parent =
		remotes
end

local projectileNearMiss =
	nearMissRemoteInstance :: RemoteEvent


-- ============================================================
-- TRACKING BREAK HOOK
-- ============================================================
--
-- SERVER-ONLY BindableEvent used by mechanics that must HARD COUNTER
-- projectile tracking, above all Substitution / Kawarimi.
--
-- Usage from any other server script:
--
--   local hook = game:GetService("ServerStorage")
--       :WaitForChild("ProjectileTrackingBreak")
--
--   hook:Fire(character)          -- character = the Model being tracked
--
-- Effect:
-- every projectile currently locked onto that character drops its lock
-- immediately, keeps its current trajectory and NEVER re-acquires anyone.
--
-- This is additive. If nothing ever fires it, the attribute fallback below
-- still works.

local trackingBreakHook =
	ServerStorage:
	FindFirstChild(
		"ProjectileTrackingBreak"
	)

if not trackingBreakHook then

	trackingBreakHook =
		Instance.new(
			"BindableEvent"
		)

	trackingBreakHook.Name =
		"ProjectileTrackingBreak"

	trackingBreakHook.Parent =
		ServerStorage
end

local projectileTrackingBreak =
	trackingBreakHook :: BindableEvent
-- =========================
-- RUNTIME STATE
-- =========================

local templateCache: {[string]: Instance} =
	{}

local folderCache: {[string]: Instance} =
	{}

local cooldownEndsAt: {[Player]: {[string]: number}} =
	{}

local mirroredCombatMode: {[Player]: boolean} =
	{}

local lastCombatSync: {[Player]: number} =
	{}

local globalThrowEndsAt: {[Player]: number} =
	{}

local lastDefensePrepareAt: {[Player]: number} =
	{}


-- Timestamp of the last "stop tracking this character" signal.
-- Weak keys so a removed character never keeps the entry alive.
local trackingBreakStamp: {[Model]: number} =
	setmetatable(
		{},
		{
			__mode = "k",
		}
	) :: any


projectileTrackingBreak.Event:
	Connect(
		function(
			target: any
		)

			local targetModel: Model? =
			nil


			if typeof(target) == "Instance" then

				if target:IsA(
					"Model"
					) then

					targetModel =
					target

				elseif target:IsA(
					"Player"
					) then

					targetModel =
					target.Character
				end
			end


			if not targetModel then
				return
			end


			trackingBreakStamp[
			targetModel
			] =
			workspace:
			GetServerTimeNow()
		end
	)


-- Attributes any Substitution / Kawarimi implementation may already be using.
-- Checked as a fallback so the hard counter works even before the BindableEvent
-- above is wired in.
local SUBSTITUTION_FLAG_ATTRIBUTES = {
	-- Set by the Substitution server while the Kawarimi window is armed.
	-- This is the real, replicated, server-authored signal.
	"SubstitutionWindowActive",
	"SubstitutionActive",
	"IsSubstituting",
	"KawarimiActive",
	"SubstitutionTriggered",
}

local SUBSTITUTION_TIME_ATTRIBUTES = {
	"LastSubstitutionAt",
	"SubstitutionStartedAt",
	"KawarimiUsedAt",
}
-- =========================
-- BASIC HELPERS
-- =========================

local function isValidVector3(
	value: any
): boolean

	if typeof(value) ~= "Vector3" then
		return false
	end


	if value.X ~= value.X
		or value.Y ~= value.Y
		or value.Z ~= value.Z then

		return false
	end


	if math.abs(value.X) > 1e6
		or math.abs(value.Y) > 1e6
		or math.abs(value.Z) > 1e6 then

		return false
	end


	return true
end


local function safeUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	if vector.Magnitude > 0.001 then
		return vector.Unit
	end


	if fallback.Magnitude > 0.001 then
		return fallback.Unit
	end


	return Vector3.new(
		0,
		0,
		-1
	)
end


local function getConfig(
	projectileType: string
): any

	local config =
		ProjectileConfigs[
	projectileType
	]


	if typeof(config) ~= "table" then
		return nil
	end


	return config
end


local function resolveNinjaBagSlot(
	player: Player,
	slotValue: any
): (number?, string?, any?, string)

	if typeof(slotValue) ~= "number"
		or slotValue % 1 ~= 0 then

		return nil,
			nil,
			nil,
			"invalid slot"
	end


	local slotIndex =
		math.floor(
			slotValue
		)


	local canUse,
		projectileType,
		reason =
		NinjaBagService.CanUseSlot(
			player,
			slotIndex
		)


	if not projectileType then

		return slotIndex,
			nil,
			nil,
			reason
	end


	local config =
		getConfig(
			projectileType
		)


	if not config then

		return slotIndex,
			projectileType,
			nil,
			"invalid equipped projectile"
	end


	if not canUse then

		return slotIndex,
			projectileType,
			config,
			reason
	end


	return slotIndex,
		projectileType,
		config,
		"OK"
end


local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?, BasePart?)

	local character =
		player.Character


	if not character then
		return nil, nil, nil
	end


	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)


	local rootPart =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)


	if not humanoid
		or humanoid.Health <= 0
		or not rootPart
		or not rootPart:IsA(
			"BasePart"
		) then

		return nil, nil, nil
	end


	return character,
		humanoid,
		rootPart
end


local function canServerThrow(
	player: Player,
	character: Model,
	humanoid: Humanoid
): (boolean, string)

	if humanoid.Health <= 0 then
		return false, "dead"
	end


	if character:GetAttribute(
		"CombatSuppressed"
		) == true then

		return false,
			"CombatSuppressed"
	end


	if character:GetAttribute(
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
			) == true then

		return false,
			"Downed system lock"
	end


	if character:GetAttribute(
		"IsStunned"
		) == true then

		return false,
			"IsStunned"
	end


	if character:GetAttribute(
		"IsBlocking"
		) == true then

		return false,
			"IsBlocking"
	end


	if character:GetAttribute(
		"IsAttacking"
		) == true then

		return false,
			"IsAttacking"
	end


	if character:GetAttribute(
		"IsDashing"
		) == true then

		return false,
			"IsDashing"
	end


	if character:GetAttribute(
		"TreeJumpActive"
		) == true
			or character:GetAttribute(
				"IsTreeJumping"
			) == true then

		return false,
			"TreeJump"
	end


	local now =
		workspace:
		GetServerTimeNow()


	if now <
		(
			globalThrowEndsAt[
			player
			]
				or 0
		) then

		return false,
			"global throw lock"
	end


	return true,
		"OK"
end


local function publishCoreCooldown(
	character: Model,
	config: any,
	startsAt: number,
	endsAt: number
)

	local id =
		config.Id


	character:SetAttribute(
		"CoreCooldown_"
			.. id
			.. "_Label",
		id
	)


	character:SetAttribute(
		"CoreCooldown_"
			.. id
			.. "_StartsAt",
		startsAt
	)


	character:SetAttribute(
		"CoreCooldown_"
			.. id
			.. "_EndsAt",
		endsAt
	)
end

-- =========================
-- TEMPLATE / FOLDER
-- =========================

local function resolveTemplate(
	config: any
): Instance?

	local id =
		config.Id


	local cached =
		templateCache[
	id
	]


	if cached
		and cached.Parent then

		return cached
	end


	local assetName =
		config.AssetName


	local direct =
		ReplicatedStorage:
		FindFirstChild(
			assetName
		)


	if direct then

		templateCache[
		id
		] =
			direct

		return direct
	end


	local recursive =
		ReplicatedStorage:
		FindFirstChild(
			assetName,
			true
		)


	if recursive then

		templateCache[
		id
		] =
			recursive

		return recursive
	end


	local wanted =
		string.lower(
			assetName
		)


	for _, descendant in ipairs(
		ReplicatedStorage:
			GetDescendants()
		) do

		if string.lower(
			descendant.Name
			) == wanted then

			templateCache[
			id
			] =
				descendant


			return descendant
		end
	end


	warn(
		"[ProjectileServer] asset not found:",
		id,
		"expected=",
		assetName
	)


	return nil
end


local function getProjectileFolder(
	config: any
): Instance

	local folderName =
		config.FolderName


	local cached =
		folderCache[
	folderName
	]


	if cached
		and cached.Parent then

		return cached
	end


	local existing =
		workspace:
		FindFirstChild(
			folderName
		)


	if existing then

		folderCache[
		folderName
		] =
			existing


		return existing
	end


	local folderModel =
		Instance.new(
			"Model"
		)


	folderModel.Name =
		folderName


	folderModel.ModelStreamingMode =
		Enum.ModelStreamingMode.Persistent


	folderModel.Parent =
		workspace


	folderCache[
	folderName
	] =
		folderModel


	return folderModel
end


local function cloneProjectile(
	player: Player,
	config: any
): (Model?, BasePart?)

	local template =
		resolveTemplate(
			config
		)


	if not template then
		return nil, nil
	end


	local clone =
		template:
		Clone()


	local model: Model


	if clone:IsA(
		"Model"
		) then

		model =
			clone

	else

		model =
			Instance.new(
				"Model"
			)


		clone.Parent =
			model
	end


	model.Name =
		config.ModelPrefix
		.. player.Name


	local mainPart: BasePart? =
		model.PrimaryPart


	if not mainPart then

		for _, descendant in ipairs(
			model:
				GetDescendants()
			) do

			if descendant:IsA(
				"BasePart"
				) then

				mainPart =
					descendant


				model.PrimaryPart =
					descendant


				break
			end
		end
	end


	if not mainPart then

		warn(
			"[ProjectileServer]",
			config.Id,
			"asset has no BasePart"
		)


		model:
			Destroy()


		return nil, nil
	end


	for _, descendant in ipairs(
		model:
			GetDescendants()
		) do

		if descendant:IsA(
			"BasePart"
			) then

			descendant.Anchored =
				true

			descendant.CanCollide =
				false

			descendant.CanTouch =
				false

			descendant.CanQuery =
				true

			descendant.Massless =
				true
		end
	end


	local visual =
		config.Visual


	if visual.ScaleMode ==
		"TargetDiameter" then

		local _boxCFrame,
			boxSize =
			model:
			GetBoundingBox()


		local largest =
			math.max(
				boxSize.X,
				boxSize.Y,
				boxSize.Z
			)


		if largest > 0.001 then

			local scaleFactor =
				visual.TargetDiameter
				/ largest


			local ok,
				currentScale =
				pcall(
					function()

						return model:
						GetScale()
					end
				)


			if ok
				and typeof(currentScale) ==
				"number" then

				model:
					ScaleTo(
						currentScale
						* scaleFactor
					)
			end
		end
	end


	return model,
		mainPart
end

-- =========================
-- THROW ORIGIN
-- =========================

local function getThrowOrigin(
	character: Model,
	rootPart: BasePart,
	projectileType: string
): Vector3

	local explicitName =
		projectileType
		.. "ThrowOrigin"


	local explicit =
		character:
		FindFirstChild(
			explicitName,
			true
		)


	if explicit
		and explicit:IsA(
			"Attachment"
		) then

		return explicit.WorldPosition
	end


	-- Generic throwables use LEFT ARM so the RIGHT ARM can remain
	-- available for future Kenjutsu weapon ownership.
	local leftArm =
		character:
		FindFirstChild(
			"Left Arm"
		)


	if leftArm
		and leftArm:IsA(
			"BasePart"
		) then

		return leftArm.Position
		- leftArm.CFrame.UpVector
			* (
				leftArm.Size.Y
				* 0.28
			)
			+ leftArm.CFrame.LookVector
			* 0.12
	end


	return rootPart.Position
		+ rootPart.CFrame.LookVector
		* 1.7
end


-- ============================================================
-- CLIENT RELEASE ORIGIN COMPENSATION
-- ============================================================
--
-- The shooter owns character movement on the client. During a sprint the
-- client's visible hand can therefore be several studs ahead of the server's
-- latest replicated character pose by the time the "release" RemoteEvent
-- arrives.
--
-- ThrowableController already sends the exact Left Arm world position sampled
-- at the animation's release marker. We use that snapshot as the preferred
-- spawn origin, but only inside a bounded server-authoritative envelope.
--
-- This is NOT free client teleport authority:
-- 1. Server calculates its own hand origin.
-- 2. Server predicts a small amount using measured network ping + velocity.
-- 3. Client release origin is accepted only within a dynamic correction radius.
-- 4. Larger deltas are clamped rather than trusted.
--
-- At SprintSpeed 40 this gives enough room for normal replication delay while
-- preventing a client from spawning a projectile arbitrarily far away.

local RELEASE_ORIGIN_BASE_ALLOWANCE =
	2.25

local RELEASE_ORIGIN_VELOCITY_WINDOW =
	0.14

local RELEASE_ORIGIN_MAX_CORRECTION =
	8.0

local RELEASE_ORIGIN_MAX_PREDICTION_TIME =
	0.18


local function getOneWayNetworkTime(
	player: Player
): number

	local ok,
		ping =
		pcall(
			function()

				return player:
				GetNetworkPing()
			end
		)


	if not ok
		or typeof(ping) ~= "number"
		or ping < 0 then

		return 0
	end


	-- GetNetworkPing is treated as round-trip latency here.
	return math.clamp(
		ping * 0.5,
		0,
		RELEASE_ORIGIN_MAX_PREDICTION_TIME
	)
end


local function resolveReleaseOrigin(
	player: Player,
	character: Model,
	rootPart: BasePart,
	projectileType: string,
	clientReleaseOrigin: any
): (Vector3, string, number)

	local serverOrigin =
		getThrowOrigin(
			character,
			rootPart,
			projectileType
		)


	if not isValidVector3(
		clientReleaseOrigin
		) then

		return serverOrigin,
			"ServerOrigin",
			0
	end


	local velocity =
		rootPart.AssemblyLinearVelocity


	local predictionTime =
		math.clamp(
			getOneWayNetworkTime(
				player
			)
			+ 1 / 60,
			0,
			RELEASE_ORIGIN_MAX_PREDICTION_TIME
		)


	local predictedServerOrigin =
		serverOrigin
		+ velocity
		* predictionTime


	local dynamicAllowance =
		math.clamp(
			RELEASE_ORIGIN_BASE_ALLOWANCE
			+ velocity.Magnitude
			* RELEASE_ORIGIN_VELOCITY_WINDOW,
			RELEASE_ORIGIN_BASE_ALLOWANCE,
			RELEASE_ORIGIN_MAX_CORRECTION
		)


	local delta =
		clientReleaseOrigin
	- predictedServerOrigin


	if delta.Magnitude <=
		dynamicAllowance then

		return clientReleaseOrigin,
			"ClientReleaseSnapshot",
			delta.Magnitude
	end


	if delta.Magnitude <= 0.001 then

		return predictedServerOrigin,
			"PredictedServerOrigin",
			0
	end


	return predictedServerOrigin
		+ delta.Unit
		* dynamicAllowance,
		"ClientReleaseClamped",
		delta.Magnitude
end

-- =========================
-- TARGETING
-- =========================

local function hasLineOfSight(
	fromPosition: Vector3,
	targetCharacter: Model,
	targetPosition: Vector3,
	ignoreList: {Instance}
): boolean

	local delta =
		targetPosition
	- fromPosition


	if delta.Magnitude <= 0.01 then
		return true
	end


	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	params.FilterDescendantsInstances =
		ignoreList


	params.IgnoreWater =
		true


	local result =
		workspace:
		Raycast(
			fromPosition,
			delta,
			params
		)


	if not result then
		return true
	end


	return result.Instance:
		IsDescendantOf(
			targetCharacter
		)
end


local function getTargetCharacterFromPart(
	part: BasePart
): (Model?, Humanoid?, BasePart?)

	local current: Instance? =
		part


	while current
		and current ~= workspace do

		if current:IsA(
			"Model"
			) then

			local humanoid =
				current:
				FindFirstChildOfClass(
					"Humanoid"
				)


			local root =
				current:
				FindFirstChild(
					"HumanoidRootPart"
				)


			if humanoid
				and root
				and root:IsA(
					"BasePart"
				) then

				return current,
					humanoid,
					root
			end
		end


		current =
			current.Parent
	end


	return nil,
		nil,
		nil
end


-- ------------------------------------------------------------
-- 1. TARGET SELECTION
-- ------------------------------------------------------------
--
-- The target is chosen ONCE, at release, and is then locked to that projectile
-- for the rest of its life.
--
-- There is NO re-acquisition in flight. If the lock is lost for any reason the
-- projectile keeps its current trajectory and never looks for anybody else.
--
-- Selection order:
-- 1) DIRECT RAY. If the release line physically hits a valid character first,
--    that character IS the intent. A dummy standing behind it can never win.
-- 2) CONE SCORE. Angular error dominates; distance is only a tie-breaker.

type LockedTarget = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
}


local function isValidTargetCharacter(
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	throwerCharacter: Model
): boolean

	if targetCharacter ==
		throwerCharacter then

		return false
	end


	if targetHumanoid.Health <= 0 then
		return false
	end


	if targetCharacter:GetAttribute(
		"IsDowned"
		) == true then

		return false
	end


	-- Mission NPCs are interaction actors and already immune inside
	-- DamageService. They must never steal aim assist either.
	if targetCharacter:GetAttribute(
		"IsMissionNPC"
		) == true then

		return false
	end


	return true
end


local function buildLockedTarget(
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	targetRoot: BasePart
): LockedTarget

	return {
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
	}
end


local function getAimPointForRoot(
	targetRoot: BasePart,
	profile: any
): Vector3

	-- Center of mass / chest rather than the exact HRP center.
	return targetRoot.Position
		+ Vector3.yAxis
		* profile.AimPointHeightOffset
end


local function considerTarget(
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	targetRoot: BasePart,
	throwerCharacter: Model,
	origin: Vector3,
	aimDirection: Vector3,
	maxRange: number,
	coneDot: number,
	profile: any,
	currentBestScore: number
): (LockedTarget?, number)

	if not isValidTargetCharacter(
		targetCharacter,
		targetHumanoid,
		throwerCharacter
		) then

		return nil,
			currentBestScore
	end


	local aimPoint =
		getAimPointForRoot(
			targetRoot,
			profile
		)


	local delta =
		aimPoint
	- origin


	local distance =
		delta.Magnitude


	if distance <= 0.01
		or distance > maxRange then

		return nil,
			currentBestScore
	end


	local dot =
		math.clamp(
			aimDirection:
			Dot(
				delta.Unit
			),
			-1,
			1
		)


	-- Anything clearly outside the launch direction is never a candidate.
	if dot < coneDot then

		return nil,
			currentBestScore
	end


	if profile.AimAssistRequireLineOfSight
		and not hasLineOfSight(
			origin,
			targetCharacter,
			aimPoint,
			{
				throwerCharacter,
			}
		) then

		return nil,
			currentBestScore
	end


	-- INTENT SCORE.
	--
	-- Angular error is expressed in degrees so the weights stay readable.
	-- A character almost exactly under the crosshair beats a farther dummy
	-- that merely happens to be inside the cone.
	local angleDegrees =
		math.deg(
			math.acos(
				dot
			)
		)


	local score =
		angleDegrees
		* profile.AimAssistAngleWeight
		+ distance
		* profile.AimAssistDistanceWeight


	if score >= currentBestScore then

		return nil,
			currentBestScore
	end


	return buildLockedTarget(
		targetCharacter,
		targetHumanoid,
		targetRoot
	),
		score
end


local function resolveDirectRayTarget(
	throwerCharacter: Model,
	origin: Vector3,
	aimDirection: Vector3,
	range: number
): LockedTarget?

	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	local exclusions: {Instance} = {
		throwerCharacter,
	}


	local missionNPCs =
		workspace:
		FindFirstChild(
			"Missions NPC"
		)


	if missionNPCs then

		table.insert(
			exclusions,
			missionNPCs
		)
	end


	params.FilterDescendantsInstances =
		ProjectileInteractionService.BuildRaycastExclusions(
			exclusions
		)


	params.IgnoreWater =
		true


	local result =
		workspace:
		Raycast(
			origin,
			aimDirection
			* range,
			params
		)


	if not result then
		return nil
	end


	local targetCharacter,
		targetHumanoid,
		targetRoot =
		getTargetCharacterFromPart(
			result.Instance :: BasePart
		)


	if not targetCharacter
		or not targetHumanoid
		or not targetRoot then

		return nil
	end


	if not isValidTargetCharacter(
		targetCharacter,
		targetHumanoid,
		throwerCharacter
		) then

		return nil
	end


	return buildLockedTarget(
		targetCharacter,
		targetHumanoid,
		targetRoot
	)
end


local function acquireLockedTarget(
	thrower: Player,
	throwerCharacter: Model,
	origin: Vector3,
	aimDirection: Vector3,
	profile: any
): (LockedTarget?, string)

	local range =
		profile.AimAssistRange


	-- ---- 1) direct ray = explicit intent ----
	if profile.AimAssistDirectRayPriority then

		local direct =
			resolveDirectRayTarget(
				throwerCharacter,
				origin,
				aimDirection,
				range
			)


		if direct then

			return direct,
				"DirectRay"
		end
	end


	-- ---- 2) assistance cone ----
	local coneDot =
		math.cos(
			math.rad(
				profile.AimAssistConeDegrees
			)
		)


	local best: LockedTarget? =
		nil


	local bestScore =
		math.huge


	local considered: {[Model]: boolean} =
		{}


	for _, targetPlayer in ipairs(
		Players:
			GetPlayers()
		) do

		if targetPlayer == thrower then
			continue
		end


		local targetCharacter,
			targetHumanoid,
			targetRoot =
			getAliveCharacter(
				targetPlayer
			)


		if targetCharacter
			and targetHumanoid
			and targetRoot then

			considered[
			targetCharacter
			] =
				true


			local candidate,
				score =
				considerTarget(
					targetCharacter,
					targetHumanoid,
					targetRoot,
					throwerCharacter,
					origin,
					aimDirection,
					range,
					coneDot,
					profile,
					bestScore
				)


			if candidate then

				best =
					candidate

				bestScore =
					score
			end
		end
	end


	for _, tagged in ipairs(
		CollectionService:
			GetTagged(
				PROJECTILE_TARGET_TAG
			)
		) do

		local targetCharacter: Model? =
			nil


		if tagged:IsA(
			"Model"
			) then

			targetCharacter =
				tagged

		else

			targetCharacter =
				tagged:
				FindFirstAncestorOfClass(
					"Model"
				)
		end


		if not targetCharacter
			or considered[
			targetCharacter
			] then

			continue
		end


		considered[
		targetCharacter
		] =
			true


		local humanoid =
			targetCharacter:
			FindFirstChildOfClass(
				"Humanoid"
			)


		local root =
			targetCharacter:
			FindFirstChild(
				"HumanoidRootPart"
			)


		if not humanoid
			or not root
			or not root:IsA(
				"BasePart"
			) then

			continue
		end


		local candidate,
			score =
			considerTarget(
				targetCharacter,
				humanoid,
				root,
				throwerCharacter,
				origin,
				aimDirection,
				range,
				coneDot,
				profile,
				bestScore
			)


		if candidate then

			best =
				candidate

			bestScore =
				score
		end
	end


	if best then

		return best,
			"Cone"
	end


	return nil,
		"None"
end



-- =========================
-- INTERCEPT MATH
-- =========================

local function calculateInterceptPoint(
	projectilePosition: Vector3,
	targetPosition: Vector3,
	targetVelocity: Vector3,
	projectileSpeed: number,
	targetVelocityFactor: number,
	maxInterceptTime: number,
	maxLeadDistance: number
): Vector3

	local predictionVelocity =
		targetVelocity
		* targetVelocityFactor


	local relative =
		targetPosition
	- projectilePosition


	local a =
		predictionVelocity:
		Dot(
			predictionVelocity
		)
	- projectileSpeed
		* projectileSpeed


	local b =
		2
		* relative:
		Dot(
			predictionVelocity
		)


	local c =
		relative:
		Dot(
			relative
		)


	local interceptTime: number? =
		nil


	if math.abs(a) < 1e-5 then

		if math.abs(b) > 1e-5 then

			local candidate =
				-c / b


			if candidate > 0 then

				interceptTime =
					candidate
			end
		end

	else

		local discriminant =
			b * b
		- 4
			* a
			* c


		if discriminant >= 0 then

			local root =
				math.sqrt(
					discriminant
				)


			local t1 =
				(
					-b
					- root
				)
				/ (
					2 * a
				)


			local t2 =
				(
					-b
					+ root
				)
				/ (
					2 * a
				)


			if t1 > 0
				and t2 > 0 then

				interceptTime =
					math.min(
						t1,
						t2
					)

			elseif t1 > 0 then

				interceptTime =
					t1

			elseif t2 > 0 then

				interceptTime =
					t2
			end
		end
	end


	if not interceptTime then

		interceptTime =
			relative.Magnitude
			/ projectileSpeed
	end


	interceptTime =
		math.clamp(
			interceptTime,
			0,
			maxInterceptTime
		)


	local leadOffset =
		predictionVelocity
		* interceptTime


	if leadOffset.Magnitude >
		maxLeadDistance then

		leadOffset =
			leadOffset.Unit
			* maxLeadDistance
	end


	return targetPosition
		+ leadOffset
end


local function calculateSurfaceRelativeInterceptPoint(
	projectilePosition: Vector3,
	targetPosition: Vector3,
	targetVelocity: Vector3,
	projectileSpeed: number,
	guidanceUp: Vector3,
	guidance: any
): Vector3

	local safeUp =
		safeUnit(
			guidanceUp,
			Vector3.yAxis
		)


	local verticalVelocity =
		safeUp
		* targetVelocity:
		Dot(
			safeUp
		)


	local planarVelocity =
		targetVelocity
	- verticalVelocity


	local predictionVelocity =
		(
			planarVelocity
			+ verticalVelocity
			* guidance.VerticalVelocityFactor
		)
		* guidance.TargetVelocityFactor


	return calculateInterceptPoint(
		projectilePosition,
		targetPosition,
		predictionVelocity,
		projectileSpeed,
		1.0,
		guidance.MaxInterceptTime,
		guidance.MaxLeadDistance
	)
end


local function rotateTowards(
	current: Vector3,
	desired: Vector3,
	maxRadians: number
): Vector3

	local currentUnit =
		safeUnit(
			current,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local desiredUnit =
		safeUnit(
			desired,
			currentUnit
		)


	local dot =
		math.clamp(
			currentUnit:
			Dot(
				desiredUnit
			),
			-1,
			1
		)


	local angle =
		math.acos(
			dot
		)


	if angle < 0.0001 then
		return desiredUnit
	end


	local alpha =
		math.min(
			1,
			maxRadians
			/ angle
		)


	local mixed =
		currentUnit:
		Lerp(
			desiredUnit,
			alpha
		)


	return safeUnit(
		mixed,
		currentUnit
	)
end


local function smoothStep01(
	value: number
): number

	local x =
		math.clamp(
			value,
			0,
			1
		)


	return x
		* x
		* (
			3
			- 2 * x
		)
end


local function getGuidanceTurnRate(
	distance: number,
	guidance: any
): number

	if distance >=
		guidance.MidDistance then

		local alpha =
			math.clamp(
				(
					distance
					- guidance.MidDistance
				)
				/ math.max(
					0.001,
					guidance.AcquireRange
					- guidance.MidDistance
				),
				0,
				1
			)


		return guidance.TurnRateMidDegreesPerSecond
			+ (
				guidance.TurnRateFarDegreesPerSecond
				- guidance.TurnRateMidDegreesPerSecond
			)
			* alpha
	end


	local alpha =
		math.clamp(
			(
				distance
				- guidance.CommitDistance
			)
			/ math.max(
				0.001,
				guidance.MidDistance
				- guidance.CommitDistance
			),
			0,
			1
		)


	return guidance.TurnRateNearDegreesPerSecond
		+ (
			guidance.TurnRateMidDegreesPerSecond
			- guidance.TurnRateNearDegreesPerSecond
		)
		* alpha
end


local function buildSurfaceBiasedDirection(
	currentDirection: Vector3,
	toIntercept: Vector3,
	guidanceUp: Vector3,
	guidance: any
): Vector3

	if toIntercept.Magnitude <= 0.001 then
		return currentDirection
	end


	local desired =
		toIntercept.Unit


	local safeUp =
		safeUnit(
			guidanceUp,
			Vector3.yAxis
		)


	local desiredVertical =
		safeUp
		* desired:
		Dot(
			safeUp
		)


	local desiredPlanar =
		desired
	- desiredVertical


	if desiredPlanar.Magnitude <= 0.001 then
		return desired
	end


	desiredPlanar =
		desiredPlanar.Unit


	local currentVerticalAmount =
		currentDirection:
		Dot(
			safeUp
		)


	local desiredVerticalAmount =
		desired:
		Dot(
			safeUp
		)


	local blendedVerticalAmount =
		currentVerticalAmount
		+ (
			desiredVerticalAmount
			- currentVerticalAmount
		)
		* guidance.VerticalAimWeight


	return safeUnit(
		desiredPlanar
			+ safeUp
			* blendedVerticalAmount,
		desired
	)
end


-- =========================
-- 3. PREDICTIVE AIM HELPERS
-- =========================

local function angleBetweenDegrees(
	a: Vector3,
	b: Vector3
): number

	local unitA =
		safeUnit(
			a,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local unitB =
		safeUnit(
			b,
			unitA
		)


	return math.deg(
		math.acos(
			math.clamp(
				unitA:
					Dot(
						unitB
					),
				-1,
				1
			)
		)
	)
end


-- Raw AssemblyLinearVelocity is never used directly.
--
-- Knockback, Launcher, falls and network corrections all produce spikes that
-- would throw the predicted point somewhere absurd, so:
-- - absurd samples are DISCARDED (not clamped)
-- - vertical motion is damped hard
-- - the remainder is clamped to MaxPredictionSpeed
local function sanitizeVelocitySample(
	velocity: Vector3,
	up: Vector3,
	profile: any
): Vector3

	if not isValidVector3(
		velocity
		) then

		return Vector3.zero
	end


	if velocity.Magnitude >
		profile.IgnoreVelocityAbove then

		return Vector3.zero
	end


	local safeUp =
		safeUnit(
			up,
			Vector3.yAxis
		)


	local vertical =
		safeUp
		* velocity:
		Dot(
			safeUp
		)


	local horizontal =
		velocity
	- vertical


	local filtered =
		horizontal
		+ vertical
		* profile.VerticalVelocityFactor


	if filtered.Magnitude >
		profile.MaxPredictionSpeed then

		filtered =
			filtered.Unit
			* profile.MaxPredictionSpeed
	end


	return filtered
end


-- ============================================================
-- 6. DASH STATE
-- ============================================================
--
-- Reads whatever the Dash system publishes on the character.
--
-- REQUIRED  : IsDashing (boolean)      -- already used by this codebase
-- OPTIONAL  : DashDirection (Vector3)  -- or DashDirectionX/Y/Z (numbers)
-- OPTIONAL  : DashSpeed (number)
-- OPTIONAL  : DashEndsAt / DashEndTime (workspace:GetServerTimeNow() based)
--
-- With only IsDashing available the projectile still degrades safely: it uses a
-- short assumed remaining dash time instead of extrapolating velocity forever.
local function readDashState(
	character: Model,
	root: BasePart?,
	profile: any
): (boolean, Vector3?, number?, number?)

	local flagged =
		character:GetAttribute(
			"IsDashing"
		) == true


	-- DashController is a LocalScript: IsDashing may never reach the server.
	-- The replicated horizontal speed always does, so a burst clearly above
	-- sprint speed is treated as a dash even with no attribute at all.
	local burst =
		false


	local burstVelocity =
		Vector3.zero


	if root then

		local velocity =
			root.AssemblyLinearVelocity


		if isValidVector3(
			velocity
			) then

			burstVelocity =
				Vector3.new(
					velocity.X,
					0,
					velocity.Z
				)


			burst =
				burstVelocity.Magnitude >=
				profile.DashSpeedThreshold
		end
	end


	if not flagged
		and not burst then

		return false,
			nil,
			nil,
			nil
	end


	local direction: Vector3? =
		nil


	local rawDirection =
		character:GetAttribute(
			"DashDirection"
		)


	if typeof(rawDirection) == "Vector3"
		and isValidVector3(
			rawDirection
		)
			and rawDirection.Magnitude > 0.01 then

		direction =
			rawDirection.Unit

	else

		local x =
			character:GetAttribute(
				"DashDirectionX"
			)

		local y =
			character:GetAttribute(
				"DashDirectionY"
			)

		local z =
			character:GetAttribute(
				"DashDirectionZ"
			)


		if typeof(x) == "number"
			and typeof(y) == "number"
			and typeof(z) == "number" then

			local candidate =
				Vector3.new(
					x,
					y,
					z
				)


			if isValidVector3(
				candidate
				)
					and candidate.Magnitude > 0.01 then

				direction =
					candidate.Unit
			end
		end
	end


	if not direction
		and burstVelocity.Magnitude > 1 then

		direction =
			burstVelocity.Unit
	end


	local speed: number? =
		nil


	local rawSpeed =
		character:GetAttribute(
			"DashSpeed"
		)


	if typeof(rawSpeed) == "number"
		and rawSpeed > 0 then

		speed =
			rawSpeed

	elseif burstVelocity.Magnitude > 1 then

		speed =
			math.min(
				burstVelocity.Magnitude,
				profile.IgnoreVelocityAbove
			)
	end


	local remaining: number? =
		nil


	local endsAt =
		character:GetAttribute(
			"DashEndsAt"
		)
		or character:GetAttribute(
			"DashEndTime"
		)


	if typeof(endsAt) == "number" then

		remaining =
			math.max(
				0,
				endsAt
				- workspace:
				GetServerTimeNow()
			)
	end


	return true,
		direction,
		speed,
		remaining
end


-- 9. SUBSTITUTION: attribute fallback for the hard tracking counter.
local function hasSubstitutionSignal(
	character: Model,
	sinceTime: number
): boolean

	for _, attributeName in ipairs(
		SUBSTITUTION_FLAG_ATTRIBUTES
		) do

		if character:GetAttribute(
			attributeName
			) == true then

			return true
		end
	end


	for _, attributeName in ipairs(
		SUBSTITUTION_TIME_ATTRIBUTES
		) do

		local stamp =
			character:GetAttribute(
				attributeName
			)


		if typeof(stamp) == "number"
			and stamp >= sinceTime then

			return true
		end
	end


	return false
end


-- Rotates towards a desired direction with a hard degrees-per-second cap and
-- an angular deadzone, and reports how many degrees were actually applied.
local function steerTowards(
	current: Vector3,
	desired: Vector3,
	maxDegrees: number,
	deadzoneDegrees: number
): (Vector3, number)

	local errorDegrees =
		angleBetweenDegrees(
			current,
			desired
		)


	-- 11. VISUAL: below the deadzone we simply do not correct. This is what
	-- removes the constant micro-zigzag.
	if errorDegrees <= deadzoneDegrees then

		return current,
			0
	end


	local appliedDegrees =
		math.min(
			errorDegrees,
			math.max(
				0,
				maxDegrees
			)
		)


	if appliedDegrees <= 0 then

		return current,
			0
	end


	return rotateTowards(
		current,
		desired,
		math.rad(
			appliedDegrees
		)
	),
		appliedDegrees
end


-- Shortest distance between a moving segment and a point, plus whether the
-- closest approach already happened inside this step.
local function closestApproachToPoint(
	fromPosition: Vector3,
	toPosition: Vector3,
	point: Vector3
): (number, Vector3, number)

	local segment =
		toPosition
	- fromPosition


	local lengthSquared =
		segment:
		Dot(
			segment
		)


	if lengthSquared <= 1e-6 then

		return (
			point
			- fromPosition
		).Magnitude,
			fromPosition,
			0
	end


	local alpha =
		math.clamp(
			(
				point
				- fromPosition
			):
			Dot(
				segment
			)
			/ lengthSquared,
			0,
			1
		)


	local closest =
		fromPosition
		+ segment
		* alpha


	return (
		point
		- closest
	).Magnitude,
		closest,
		alpha
end


-- Full predictive aim point for a locked target.
--
-- PredictedPosition = AimPoint + FilteredVelocity * ClampedPredictionTime
--
-- with the intercept time solved against the projectile speed, clamped by
-- MaxPredictionTime, and the lead offset clamped by MaxLeadDistance.
--
-- While the target is dashing we do NOT extrapolate velocity forever: we use
-- DashDirection / DashSpeed / remaining dash time to estimate a sane
-- ExpectedDashEnd instead.
local function computeInterceptForTarget(
	fromPosition: Vector3,
	locked: LockedTarget,
	filteredVelocity: Vector3,
	up: Vector3,
	projectileSpeed: number,
	profile: any,
	dashing: boolean?,
	dashDirection: Vector3?,
	dashSpeed: number?,
	dashRemaining: number?
): Vector3

	local aimPoint =
		getAimPointForRoot(
			locked.root,
			profile
		)


	local safeSpeed =
		math.max(
			1,
			projectileSpeed
		)


	if dashing
		and profile.DashPredictionEnabled then

		local direction =
			dashDirection


		if not direction then

			local velocity =
				locked.root.AssemblyLinearVelocity


			if isValidVector3(
				velocity
				)
					and velocity.Magnitude > 1 then

				direction =
					velocity.Unit
			end
		end


		if direction then

			local speed =
				dashSpeed


			if not speed then

				speed =
					math.min(
						locked.root.AssemblyLinearVelocity.Magnitude,
						profile.IgnoreVelocityAbove
					)
			end


			local travelTime =
				(
					aimPoint
					- fromPosition
				).Magnitude
				/ safeSpeed


			local dashTime =
				math.clamp(
					math.min(
						dashRemaining
						or profile.DashAssumedRemaining,
						travelTime
					),
					0,
					profile.DashMaxPredictionTime
				)


			return aimPoint
				+ direction
				* (
					speed
					* dashTime
				)
		end
	end


	local predictionVelocity =
		filteredVelocity
		* profile.PredictionStrength


	return calculateInterceptPoint(
		fromPosition,
		aimPoint,
		predictionVelocity,
		safeSpeed,
		1.0,
		profile.MaxPredictionTime,
		profile.MaxLeadDistance
	)
end


-- 10. HITBOX
--
-- The swept cast already prevents tunneling. This radius only makes the
-- LOGICAL hitbox slightly more permissive than the visual mesh, using the
-- cross-section of the model (the long axis is covered by the sweep).
local function computeHitboxRadius(
	model: Model,
	profile: any
): number

	if profile.HitboxRadius then

		return math.clamp(
			profile.HitboxRadius,
			profile.HitboxRadiusMin,
			profile.HitboxRadiusMax
		)
	end


	local visualRadius =
		0.4


	local ok,
		boxSize =
		pcall(
			function()

				local _boxCFrame,
				size =
				model:
				GetBoundingBox()


				return size
			end
		)


	if ok
		and typeof(boxSize) == "Vector3" then

		local axes = {
			boxSize.X,
			boxSize.Y,
			boxSize.Z,
		}


		table.sort(
			axes
		)


		visualRadius =
			math.max(
				axes[1],
				axes[2]
			)
			* 0.5
	end


	return math.clamp(
		visualRadius
			* profile.HitboxScale,
		profile.HitboxRadiusMin,
		profile.HitboxRadiusMax
	)
end
-- =========================
-- DEFENSIVE INTERCEPT MATH
-- =========================

local function calculateMovingProjectileIntercept(
	counterOrigin: Vector3,
	counterSpeed: number,
	threat: any
): (Vector3?, Vector3?, number?)

	local targetVelocity =
		threat.Direction
		* threat.Speed


	local relative =
		threat.Position
	- counterOrigin


	-- Solve:
	-- |relative + targetVelocity*t| = counterSpeed*t
	local a =
		targetVelocity:
		Dot(
			targetVelocity
		)
	- counterSpeed
		* counterSpeed


	local b =
		2
		* relative:
		Dot(
			targetVelocity
		)


	local c =
		relative:
		Dot(
			relative
		)


	local interceptTime: number? =
		nil


	if math.abs(a) <
		1e-6 then

		if math.abs(b) >
			1e-6 then

			local candidate =
				-c / b


			if candidate > 0 then

				interceptTime =
					candidate
			end
		end

	else

		local discriminant =
			b * b
		- 4
			* a
			* c


		if discriminant >= 0 then

			local root =
				math.sqrt(
					discriminant
				)


			local t1 =
				(
					-b
					- root
				)
				/ (
					2 * a
				)


			local t2 =
				(
					-b
					+ root
				)
				/ (
					2 * a
				)


			if t1 > 0
				and t2 > 0 then

				interceptTime =
					math.min(
						t1,
						t2
					)

			elseif t1 > 0 then

				interceptTime =
					t1

			elseif t2 > 0 then

				interceptTime =
					t2
			end
		end
	end


	if not interceptTime then

		return nil,
			nil,
			nil
	end


	local interceptPoint =
		threat.Position
		+ targetVelocity
		* interceptTime


	local delta =
		interceptPoint
	- counterOrigin


	if delta.Magnitude <=
		0.001 then

		return nil,
			nil,
			nil
	end


	return interceptPoint,
		delta.Unit,
		interceptTime
end


local function selectDefensiveIntercept(
	player: Player,
	character: Model,
	rootPart: BasePart,
	config: any
): (Vector3?, any?)

	if not DEFENSIVE_INTERCEPT_ENABLED then

		return nil,
			nil
	end


	local origin =
		getThrowOrigin(
			character,
			rootPart,
			config.Id
		)


	local getIncomingThreats =
		ProjectileInteractionService.GetIncomingThreats


	-- Compatibility guard:
	--
	-- ProjectileInteractionService v2 did not expose GetIncomingThreats().
	-- A mismatched ModuleScript must NEVER break normal offensive throws.
	--
	-- With an old service:
	-- - offensive throwing continues normally
	-- - defensive auto-intercept is temporarily unavailable
	-- - Output tells us exactly which dependency is outdated
	if typeof(
		getIncomingThreats
		) ~= "function" then

		if not warnedMissingIncomingThreatAPI then

			warnedMissingIncomingThreatAPI =
				true


			warn(
				"[ProjectileServer] ProjectileInteractionService is OUTDATED: "
					.. "GetIncomingThreats() is missing. "
					.. "Install ProjectileInteractionService_v3_IncomingThreats. "
					.. "Offensive throws remain enabled; Auto Defensive Intercept is disabled until fixed."
			)
		end


		return nil,
			nil
	end


	local threats =
		getIncomingThreats(
			player.UserId,
			rootPart.Position,
			DEFENSIVE_THREAT_RADIUS,
			DEFENSIVE_THREAT_MAX_TIME
		)


	local checked =
		0


	for _,
		threat in ipairs(
			threats
		) do

		checked +=
			1


		if checked >
			DEFENSIVE_MAX_CANDIDATES then

			break
		end


		local interceptPoint,
			interceptDirection,
			interceptTime =
			calculateMovingProjectileIntercept(
				origin,
				config.Speed,
				threat
			)


		if not interceptPoint
			or not interceptDirection
			or not interceptTime then

			continue
		end


		-- No magical save after the incoming projectile has effectively
		-- reached the player.
		if interceptTime >
			threat.TimeToImpact
			- DEFENSIVE_INTERCEPT_SAFETY_TIME then

			continue
		end


		if (
			interceptPoint
			- origin
			).Magnitude >
			config.Range then

			continue
		end


		return interceptDirection,
			threat
	end


	return nil,
		nil
end


local function selectDefensiveInterceptAtRelease(
	player: Player,
	character: Model,
	rootPart: BasePart,
	config: any
): (Vector3?, any?)

	if not DEFENSIVE_INTERCEPT_ENABLED then

		return nil,
			nil
	end


	local getIncomingThreats =
		ProjectileInteractionService.GetIncomingThreats


	if typeof(
		getIncomingThreats
		) ~= "function" then

		return nil,
			nil
	end


	-- PREPARE looks farther ahead than the real release validation because
	-- the animation itself takes ~0.533 sec to reach the release marker.
	local threats =
		getIncomingThreats(
			player.UserId,
			rootPart.Position,
			DEFENSIVE_THREAT_RADIUS,
			DEFENSIVE_PREPARE_LOOKAHEAD
		)


	local releaseDelay =
		DEFENSIVE_PREPARE_RELEASE_DELAY


	local currentOrigin =
		getThrowOrigin(
			character,
			rootPart,
			config.Id
		)


	local predictedOrigin =
		currentOrigin
		+ rootPart.AssemblyLinearVelocity
		* releaseDelay


	local checked =
		0


	for _,
		threat in ipairs(
			threats
		) do

		checked +=
			1


		if checked >
			DEFENSIVE_MAX_CANDIDATES then

			break
		end


		local futureTimeToImpact =
			threat.TimeToImpact
		- releaseDelay


		-- By the time the hand releases, this threat would already have hit
		-- or be too close to resolve safely.
		if futureTimeToImpact <=
			DEFENSIVE_INTERCEPT_SAFETY_TIME then

			continue
		end


		-- The actual release handler only considers the normal short threat
		-- horizon. Require the predicted threat to fall inside that same
		-- horizon so PREPARE does not authorize animations too early.
		if futureTimeToImpact >
			DEFENSIVE_THREAT_MAX_TIME then

			continue
		end


		local futureThreat = {
			Model =
				threat.Model,

			ProjectileType =
				threat.ProjectileType,

			OwnerUserId =
				threat.OwnerUserId,

			Position =
				threat.Position
				+ threat.Direction
				* threat.Speed
				* releaseDelay,

			Direction =
				threat.Direction,

			Speed =
				threat.Speed,

			TimeToImpact =
				futureTimeToImpact,

			ClosestDistance =
				threat.ClosestDistance,

			ClosestPoint =
				threat.ClosestPoint,
		}


		local interceptPoint,
			interceptDirection,
			interceptTime =
			calculateMovingProjectileIntercept(
				predictedOrigin,
				config.Speed,
				futureThreat
			)


		if not interceptPoint
			or not interceptDirection
			or not interceptTime then

			continue
		end


		if interceptTime >
			futureTimeToImpact
			- DEFENSIVE_INTERCEPT_SAFETY_TIME then

			continue
		end


		if (
			interceptPoint
			- predictedOrigin
			).Magnitude >
			config.Range then

			continue
		end


		return interceptDirection,
			threat
	end


	return nil,
		nil
end


-- =========================
-- VISUAL ORIENTATION
-- =========================

local function detectThinAxis(
	mainPart: BasePart
): string

	local size =
		mainPart.Size


	if size.X <= size.Y
		and size.X <= size.Z then

		return "X"
	end


	if size.Y <= size.X
		and size.Y <= size.Z then

		return "Y"
	end


	return "Z"
end


local function detectLongAxis(
	mainPart: BasePart
): string

	local size =
		mainPart.Size


	if size.X >= size.Y
		and size.X >= size.Z then

		return "X"
	end


	if size.Y >= size.X
		and size.Y >= size.Z then

		return "Y"
	end


	return "Z"
end


local function getShurikenPlaneCorrection(
	spinAxis: string
): CFrame

	if spinAxis == "X" then

		return CFrame.Angles(
			0,
			0,
			math.rad(
				90
			)
		)
	end


	if spinAxis == "Z" then

		return CFrame.Angles(
			math.rad(
				-90
			),
			0,
			0
		)
	end


	return CFrame.identity
end


local function getSenbonLongAxisCorrection(
	longAxis: string
): CFrame

	if longAxis == "X" then

		return CFrame.Angles(
			0,
			math.rad(
				90
			),
			0
		)
	end


	if longAxis == "Y" then

		return CFrame.Angles(
			math.rad(
				-90
			),
			0,
			0
		)
	end


	return CFrame.identity
end


local function buildLookAt(
	position: Vector3,
	direction: Vector3
): CFrame

	local safeDirection =
		safeUnit(
			direction,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local up =
		Vector3.yAxis


	if math.abs(
		safeDirection:
			Dot(
				up
			)
		) > 0.98 then

		up =
			Vector3.xAxis
	end


	return CFrame.lookAt(
		position,
		position
			+ safeDirection,
		up
	)
end


local function buildVisualCFrame(
	config: any,
	position: Vector3,
	direction: Vector3,
	spinAngle: number,
	assetCorrection: CFrame
): CFrame

	local visual =
		config.Visual


	local artCorrection =
		CFrame.Angles(
			visual.PitchOffset
			or 0,
			visual.YawOffset
			or 0,
			visual.RollOffset
			or 0
		)


	if visual.Mode ==
		"FlatAutoSpin" then

		return buildLookAt(
			position,
			direction
		)
			* CFrame.Angles(
				0,
				spinAngle,
				0
			)
			* assetCorrection
			* artCorrection
	end


	return buildLookAt(
		position,
		direction
	)
		* assetCorrection
		* artCorrection
end

-- =========================
-- TRAILS
-- =========================

local function createProjectileTrail(
	config: any,
	mainPart: BasePart,
	orientationAxis: string?
): Trail?

	local trailConfig =
		config.Visual.Trail


	if not trailConfig
		or trailConfig.Enabled ~= true then

		return nil
	end


	local attachment0 =
		Instance.new(
			"Attachment"
		)


	local attachment1 =
		Instance.new(
			"Attachment"
		)


	if trailConfig.Kind ==
		"Kunai" then

		local halfWidth =
			math.clamp(
				mainPart.Size.X
				* 0.30,
				trailConfig.MinHalfWidth,
				trailConfig.MaxHalfWidth
			)


		attachment0.Position =
			Vector3.new(
				-halfWidth,
				0,
				0
			)


		attachment1.Position =
			Vector3.new(
				halfWidth,
				0,
				0
			)

	else

		local width =
			trailConfig.Width


		local offset =
			Vector3.zero


		if orientationAxis == "X" then

			offset =
				Vector3.new(
					0,
					width * 0.5,
					0
				)

		elseif orientationAxis == "Y" then

			offset =
				Vector3.new(
					width * 0.5,
					0,
					0
				)

		else

			offset =
				Vector3.new(
					width * 0.5,
					0,
					0
				)
		end


		attachment0.Position =
			offset


		attachment1.Position =
			-offset
	end


	attachment0.Name =
		config.Id
		.. "TrailA"


	attachment1.Name =
		config.Id
		.. "TrailB"


	attachment0.Parent =
		mainPart


	attachment1.Parent =
		mainPart


	local trail =
		Instance.new(
			"Trail"
		)


	trail.Name =
		config.Id
		.. "Trail"


	trail.Attachment0 =
		attachment0


	trail.Attachment1 =
		attachment1


	trail.Enabled =
		true


	trail.FaceCamera =
		trailConfig.FaceCamera
		~= false


	trail.Lifetime =
		trailConfig.Lifetime


	trail.MinLength =
		trailConfig.MinLength
		or 0.05


	trail.LightEmission =
		trailConfig.LightEmission
		or 0


	trail.LightInfluence =
		trailConfig.LightInfluence
		or 0


	trail.Color =
		ColorSequence.new(
			Color3.fromRGB(
				255,
				255,
				255
			)
		)


	if trailConfig.Kind ==
		"Kunai" then

		trail.Transparency =
			NumberSequence.new(
				{
					NumberSequenceKeypoint.new(
						0.00,
						0.10
					),

					NumberSequenceKeypoint.new(
						0.25,
						0.18
					),

					NumberSequenceKeypoint.new(
						0.65,
						0.50
					),

					NumberSequenceKeypoint.new(
						1.00,
						1.00
					),
				}
			)


		trail.WidthScale =
			NumberSequence.new(
				{
					NumberSequenceKeypoint.new(
						0.00,
						1.00
					),

					NumberSequenceKeypoint.new(
						0.45,
						0.72
					),

					NumberSequenceKeypoint.new(
						1.00,
						0.00
					),
				}
			)

	else

		trail.Transparency =
			NumberSequence.new(
				{
					NumberSequenceKeypoint.new(
						0,
						0.14
					),

					NumberSequenceKeypoint.new(
						0.55,
						0.40
					),

					NumberSequenceKeypoint.new(
						1,
						1
					),
				}
			)
	end


	trail.Parent =
		mainPart


	return trail
end


local function disableTrail(
	trail: Trail?
)

	if trail
		and trail.Parent then

		trail.Enabled =
			false
	end
end

-- =========================
-- AUDIO
-- =========================

local function createSpatialSound(
	parentPart: BasePart,
	name: string,
	audioConfig: any,
	volumeMultiplier: number
): Sound

	local sound =
		Instance.new(
			"Sound"
		)


	sound.Name =
		name


	sound.SoundId =
		audioConfig.SoundId


	sound.Volume =
		audioConfig.Volume
		* volumeMultiplier


	sound.PlaybackSpeed =
		audioConfig.PlaybackSpeed


	sound.TimePosition =
		math.max(
			0,
			audioConfig.StartTimePosition
			or 0
		)


	sound.Looped =
		audioConfig.Looped
		== true


	sound.RollOffMode =
		Enum.RollOffMode.Inverse


	sound.RollOffMinDistance =
		audioConfig.RollOffMinDistance
		or 5


	sound.RollOffMaxDistance =
		audioConfig.RollOffMaxDistance
		or 100


	sound.EmitterSize =
		audioConfig.EmitterSize
		or 1


	sound.Parent =
		parentPart


	local function playNow()

		if sound.Parent then

			sound:
				Play()
		end
	end


	local delayTime =
		audioConfig.StartDelay
		or 0


	if delayTime > 0 then

		task.delay(
			delayTime,
			playNow
		)

	else

		playNow()
	end


	return sound
end


local function createImpactSoundAnchor(
	position: Vector3,
	name: string
): BasePart

	local anchor =
		Instance.new(
			"Part"
		)


	anchor.Name =
		name


	anchor.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)


	anchor.Anchored =
		true


	anchor.CanCollide =
		false


	anchor.CanTouch =
		false


	anchor.CanQuery =
		false


	anchor.Transparency =
		1


	anchor.CFrame =
		CFrame.new(
			position
		)


	anchor.Parent =
		workspace


	Debris:AddItem(
		anchor,
		5
	)


	return anchor
end


local function playImpactSound(
	config: any,
	position: Vector3,
	channelName: string
)

	local audioConfig =
		config.Audio[
	channelName
	]


	if not audioConfig then
		return
	end


	local anchor =
		createImpactSoundAnchor(
			position,
			config.Id
			.. channelName
			.. "SoundAnchor"
		)


	local sound =
		createSpatialSound(
			anchor,
			config.Id
			.. channelName,
			audioConfig,
			1
		)


	sound.Looped =
		false


	Debris:AddItem(
		sound,
		4
	)
end


local function playProjectileClashSound(
	position: Vector3
)

	local anchor =
		createImpactSoundAnchor(
			position,
			"ProjectileClashSoundAnchor"
		)


	local sound =
		createSpatialSound(
			anchor,
			"ProjectileClash",
			PROJECTILE_CLASH_AUDIO,
			1
		)


	sound.Looped =
		false


	Debris:AddItem(
		sound,
		4
	)
end

-- =========================
-- 15. CENTRAL PROJECTILE SCHEDULER
-- =========================
--
-- Every live projectile used to own a private RunService.Heartbeat connection.
-- They now share ONE connection.
--
-- Per-projectile behaviour is identical; the per-frame connection overhead and
-- the risk of leaking a connection are not.

type ProjectileStepEntry = {
	step: (dt: number) -> (),
	alive: boolean,
}

local projectileSteps: {ProjectileStepEntry} =
	{}

local projectileStepCount =
	0


local function registerProjectileStep(
	step: (dt: number) -> ()
): () -> ()

	local entry: ProjectileStepEntry = {
		step =
			step,

		alive =
			true,
	}


	projectileStepCount +=
		1


	projectileSteps[
	projectileStepCount
	] =
		entry


	return function()

		entry.alive =
			false
	end
end


RunService.Heartbeat:
	Connect(
		function(
			dt: number
		)

			-- Compact first so dead entries never accumulate.
			local writeIndex =
			0


			for index = 1,
				projectileStepCount do

				local entry =
				projectileSteps[
				index
				]


				if entry
					and entry.alive then

					writeIndex +=
					1


					if writeIndex ~= index then

						projectileSteps[
						writeIndex
						] =
						entry
					end
				end
			end


			for index = projectileStepCount,
				writeIndex + 1,
				-1 do

				projectileSteps[
				index
				] =
				nil
			end


			projectileStepCount =
			writeIndex


			-- The loop bound is captured here, so projectiles spawned during
			-- this frame simply start on the next one.
			for index = 1,
				projectileStepCount do

				local entry =
				projectileSteps[
				index
				]


				if entry
					and entry.alive then

					local ok,
					err =
					pcall(
						entry.step,
						dt
					)


					if not ok then

						entry.alive =
						false


						warn(
							"[ProjectileServer] projectile step error:",
							err
						)
					end
				end
			end
		end
	)

-- =========================
-- SPAWN ONE PROJECTILE
-- =========================

local function spawnProjectile(
	player: Player,
	config: any,
	targetPosition: Vector3,
	clientAimDirection: Vector3,
	originOffset: Vector3,
	forcedDefensiveDirection: Vector3?,
	baseOriginOverride: Vector3?
)

	local character,
		humanoid,
		rootPart =
		getAliveCharacter(
			player
		)


	if not character
		or not humanoid
		or not rootPart then

		return
	end


	local profile =
		getProjectileProfile(
			config
		)


	local baseOrigin =
		if baseOriginOverride
		and isValidVector3(
			baseOriginOverride
		)
		then baseOriginOverride
		else getThrowOrigin(
			character,
			rootPart,
			config.Id
		)


	local origin =
		baseOrigin
		+ originOffset


	local delta =
		targetPosition
	- baseOrigin


	if delta.Magnitude < 0.1 then

		delta =
			rootPart.CFrame.LookVector
			* 50
	end


	local serverTargetDirection =
		delta.Unit


	local rawAimDirection =
		serverTargetDirection


	if clientAimDirection.Magnitude >
		0.05
			and clientAimDirection:
			Dot(
				serverTargetDirection
			) >=
			CLIENT_AIM_MIN_DOT_WITH_TARGET then

		rawAimDirection =
			clientAimDirection.Unit
	end


	local defensiveMode =
		forcedDefensiveDirection ~= nil


	local direction =
		if forcedDefensiveDirection
		and forcedDefensiveDirection.Magnitude >
		0.001
		then forcedDefensiveDirection.Unit
		else rawAimDirection


	local guidanceUp =
		safeUnit(
			rootPart.CFrame.UpVector,
			Vector3.yAxis
		)


	-- ============================================================
	-- TARGET LOCK + 2. INITIAL AIM ASSIST
	-- ============================================================
	--
	-- Chosen ONCE, here. Never re-evaluated in flight.
	--
	-- A DefensiveIntercept counter keeps its physically solved line and never
	-- acquires a character, exactly as in v2.6.

	local lockedTarget: LockedTarget? =
		nil


	local lockSource =
		"None"


	local filteredTargetVelocity =
		Vector3.zero


	if not defensiveMode
		and profile.Mode ~= "None" then

		local candidate,
			source =
			acquireLockedTarget(
				player,
				character,
				origin,

				-- IMPORTANT
				-- ---------
				-- Selection uses the UNBIASED reticle line, not the client's
				-- aim direction.
				--
				-- ProjectileLaunchArcController deliberately rotates
				-- CombatAim.GetDirectionFromOrigin away from the reticle to
				-- create the visual launch arc. That bias must never be able
				-- to change WHICH character the throw intends to hit; it may
				-- only change the initial flight direction.
				serverTargetDirection,
				profile
			)


		if candidate then

			lockedTarget =
				candidate


			lockSource =
				source


			filteredTargetVelocity =
				sanitizeVelocitySample(
					candidate.root.AssemblyLinearVelocity,
					guidanceUp,
					profile
				)


			local dashing,
				dashDirection,
				dashSpeed,
				dashRemaining =
				readDashState(
					candidate.character,
					candidate.root,
					profile
				)


			local interceptPoint =
				computeInterceptForTarget(
					origin,
					candidate,
					filteredTargetVelocity,
					guidanceUp,
					config.Speed,
					profile,
					dashing,
					dashDirection,
					dashSpeed,
					dashRemaining
				)


			local toIntercept =
				interceptPoint
			- origin


			if toIntercept.Magnitude > 0.01 then

				-- The aim assist carries most of the accuracy, but it can
				-- never rotate the throw further than the configured
				-- correction budget.
				direction =
					rotateTowards(
						direction,
						toIntercept.Unit,
						math.rad(
							profile.AimAssistMaxCorrectionDegrees
						)
					)
			end
		end
	end


	local initialDirection =
		direction


	local model,
		mainPart =
		cloneProjectile(
			player,
			config
		)


	if not model
		or not mainPart then

		return
	end


	local visual =
		config.Visual


	local orientationAxis: string? =
		nil


	local assetCorrection =
		CFrame.identity


	if visual.Mode ==
		"FlatAutoSpin" then

		orientationAxis =
			detectThinAxis(
				mainPart
			)


		assetCorrection =
			getShurikenPlaneCorrection(
				orientationAxis
			)


		model:SetAttribute(
			"DetectedSpinAxis",
			orientationAxis
		)


	elseif visual.Mode ==
		"LongAxis" then

		orientationAxis =
			detectLongAxis(
				mainPart
			)


		assetCorrection =
			getSenbonLongAxisCorrection(
				orientationAxis
			)


		model:SetAttribute(
			"DetectedLongAxis",
			orientationAxis
		)
	end


	local spinAngle =
		0


	model:
		PivotTo(
			buildVisualCFrame(
				config,
				origin,
				direction,
				spinAngle,
				assetCorrection
			)
		)


	model.Parent =
		getProjectileFolder(
			config
		)


	local hitboxRadius =
		computeHitboxRadius(
			model,
			profile
		)


	-- ============================================================
	-- FLIGHT STATE
	-- ============================================================

	local hasHit =
		false


	local traveled =
		0.0


	local startTime =
		time()


	local lockAcquiredAt =
		workspace:
		GetServerTimeNow()


	local currentPosition =
		origin


	-- Guidance is only ever active for a projectile that:
	-- - is not a defensive counter
	-- - uses the Predictive profile
	-- - actually locked a target at release
	local trackingActive =
		not defensiveMode
		and profile.CanTrack
		and lockedTarget ~= nil


	local committed =
		not trackingActive


	local desiredDirection =
		direction


	local totalTurnDegrees =
		0


	local turnBudgetDegrees =
		profile.MaxTrackingAngleDegrees
		* 1.5


	local guidanceInterval =
		1 / profile.GuidanceHz


	-- Primed so the first guidance tick runs on the very first frame instead
	-- of one interval later.
	local guidanceAccumulator =
		guidanceInterval


	-- Kept separately from lockedTarget so near-miss feedback still works
	-- after the lock has been broken.
	local telegraphTarget =
		lockedTarget


	local nearMissFired =
		false


	local unregisterStep: (() -> ())? =
		nil


	local function stopStep()

		if unregisterStep then

			unregisterStep()


			unregisterStep =
				nil
		end
	end


	-- ============================================================
	-- REPLICATED STATE (hooks for client VFX / SFX / future systems)
	-- ============================================================

	model:SetAttribute(
		"GuidanceMode",
		if defensiveMode
			then "DefensiveIntercept"
			else profile.Mode
	)


	model:SetAttribute(
		"DefensiveIntercept",
		defensiveMode
	)


	model:SetAttribute(
		"ArmorPenetration",
		config.Armor.Penetration
	)


	model:SetAttribute(
		"ArmorDurabilityDamageMultiplier",
		config.Armor.DurabilityDamage
	)


	model:SetAttribute(
		"ProjectileHitboxRadius",
		hitboxRadius
	)


	model:SetAttribute(
		"ProjectileLockSource",
		lockSource
	)


	model:SetAttribute(
		"ProjectileLockedTargetUserId",
		if lockedTarget
			and lockedTarget.player
			then lockedTarget.player.UserId
			else 0
	)


	model:SetAttribute(
		"ProjectileGuidancePhase",
		if trackingActive
			then "Guidance"
			else "Committed"
	)


	model:SetAttribute(
		"ProjectileCommitted",
		not trackingActive
	)


	-- Legacy Kunai attributes preserved byte for byte.
	if config.Id == "Kunai" then

		model:SetAttribute(
			"GuidanceUpX",
			guidanceUp.X
		)


		model:SetAttribute(
			"GuidanceUpY",
			guidanceUp.Y
		)


		model:SetAttribute(
			"GuidanceUpZ",
			guidanceUp.Z
		)


		model:SetAttribute(
			"GuidanceCommitted",
			not trackingActive
		)
	end


	local trail =
		createProjectileTrail(
			config,
			mainPart,
			orientationAxis
		)


	local patternCount =
		math.max(
			1,
			config.Pattern.Count
			or 1
		)


	-- Multiple travel emitters in one volley should not simply triple perceived
	-- loudness. sqrt normalization preserves presence without a huge volume jump.
	local travelVolumeMultiplier =
		1
		/ math.sqrt(
			patternCount
		)


	local travelSound =
		createSpatialSound(
			mainPart,
			config.Id
			.. "Travel",
			config.Audio.Travel,
			travelVolumeMultiplier
		)


	local function stopTravel()

		if travelSound.Parent then

			travelSound:
				Stop()


			travelSound:
				Destroy()
		end
	end


	local function destroyVisual(
		delayTime: number
	)

		if model.Parent then

			Debris:AddItem(
				model,
				delayTime
			)
		end
	end


	local function disableProjectileCollisionQuery(
		projectileModel: Model
	)

		-- A projectile that has already LOST a clash may remain visible for a
		-- fraction of a second so its trail/fade can finish.
		--
		-- It must stop existing PHYSICALLY immediately.
		--
		-- Otherwise the winning projectile can raycast the lingering visual on
		-- the next Heartbeat and incorrectly stop as if it hit the world.
		for _,
			descendant in ipairs(
				projectileModel:GetDescendants()
			) do

			if descendant:IsA(
				"BasePart"
				) then

				descendant.CanQuery =
					false

				descendant.CanCollide =
					false

				descendant.CanTouch =
					false
			end
		end
	end


	-- ============================================================
	-- TRACKING BREAK
	-- ============================================================
	--
	-- Once tracking is broken it is NEVER restored and no other character is
	-- ever acquired. The projectile simply keeps flying.

	local function breakTracking(
		reason: string
	)

		if committed
			and not trackingActive then

			return
		end


		trackingActive =
			false


		committed =
			true


		lockedTarget =
			nil


		desiredDirection =
			direction


		if model.Parent then

			model:SetAttribute(
				"ProjectileGuidancePhase",
				"Committed"
			)


			model:SetAttribute(
				"ProjectileCommitted",
				true
			)


			model:SetAttribute(
				"ProjectileTrackingBreakReason",
				reason
			)


			if config.Id == "Kunai" then

				model:SetAttribute(
					"GuidanceCommitted",
					true
				)
			end
		end


		if DEBUG_PROJECTILES then

			print(
				"[ProjectileServer] TRACKING BREAK",
				config.Id,
				reason
			)
		end
	end


	local function destroyFromClash(
		reason: string,
		impactPosition: Vector3
	)

		if hasHit then
			return
		end


		hasHit =
			true


		-- IMPORTANT:
		-- neutralize collision/query BEFORE unregistering the loser.
		-- The visual may stay alive briefly, but heavy winners such as Fuma
		-- must be able to continue through the exact same space.
		disableProjectileCollisionQuery(
			model
		)


		breakTracking(
			"ClashDestroy"
		)


		stopStep()


		stopTravel()


		disableTrail(
			trail
		)


		ProjectileInteractionService.Unregister(
			model
		)


		-- Hold the final point long enough for a tiny fade/read.
		model:
			PivotTo(
				buildVisualCFrame(
					config,
					impactPosition,
					direction,
					spinAngle,
					assetCorrection
				)
			)


		destroyVisual(
			math.max(
				0.08,
				(
					visual.Trail
						and visual.Trail.Lifetime
						or 0
				)
					+ 0.05
			)
		)


		if DEBUG_PROJECTILES then

			print(
				"[ProjectileServer] CLASH DESTROY",
				config.Id,
				reason
			)
		end
	end


	ProjectileInteractionService.Register(
		model,
		{
			ProjectileType =
				config.Id,

			OwnerUserId =
				player.UserId,

			Speed =
				config.Speed,

			ClashPower =
				config.Clash.Power,

			Weight =
				config.Clash.Weight,

			ClashRadius =
				config.Clash.Radius,

			CanClash =
				config.Clash.CanClash,

			CanBreak =
				config.Clash.CanBreak,

			MutualDeflectAngleDegrees =
				config.Clash.MutualDeflectAngleDegrees,

			WinnerDeflectAngleDegrees =
				config.Clash.WinnerDeflectAngleDegrees,

			BreakPowerRatio =
				config.Clash.BreakPowerRatio,

			ClashStability =
				config.Clash.Stability,

			StabilityDamage =
				config.Clash.StabilityDamage,
		},
		{
			GetDirection =
				function()

					return direction
				end,

			SetDirection =
				function(
					newDirection: Vector3,
					reason: string
				)

				if newDirection.Magnitude <=
					0.001 then

					return
				end


				direction =
					newDirection.Unit


				-- 7 / 8. Any clash, deflection or counter permanently ends
				-- tracking for EVERY projectile type, not just Kunai.
				breakTracking(
					"Clash:"
						.. reason
				)
			end,

			Destroy =
				destroyFromClash,
		},
		currentPosition
	)


	if DEBUG_PROJECTILES then

		print(
			"[ProjectileServer] SPAWN",
			config.Id,
			player.Name,
			"origin=",
			origin,
			"damage=",
			config.Damage,
			"stability=",
			config.Clash.Stability,
			"lock=",
			lockSource,
			"hitbox=",
			string.format(
				"%.2f",
				hitboxRadius
			),
			"mode=",
			if defensiveMode
				then "DEFENSIVE"
				else "OFFENSIVE"
		)
	end


	-- ============================================================
	-- 4. GUIDANCE PHASE (low frequency)
	-- ============================================================

	local function updateGuidance()

		if not trackingActive
			or committed then

			return
		end


		local target =
			lockedTarget


		if not target then

			breakTracking(
				"NoTarget"
			)


			return
		end


		-- Target died, despawned or went down: lose tracking, keep flying.
		if not target.character.Parent
			or not target.root.Parent
			or target.humanoid.Health <= 0
			or target.character:GetAttribute(
				"IsDowned"
			) == true then

			breakTracking(
				"TargetInvalid"
			)


			return
		end


		-- 9. SUBSTITUTION / KAWARIMI: hard counter to tracking.
		if profile.BreakTrackingOnSubstitution then

			local stamp =
				trackingBreakStamp[
			target.character
			]


			if (
				stamp
					and stamp >= lockAcquiredAt
				)
					or hasSubstitutionSignal(
						target.character,
						lockAcquiredAt
					) then

				breakTracking(
					"Substitution"
				)


				return
			end
		end


		if time()
			- startTime >
			profile.GuidanceDuration then

			breakTracking(
				"GuidanceWindowElapsed"
			)


			return
		end


		local dashing,
			dashDirection,
			dashSpeed,
			dashRemaining =
			readDashState(
				target.character,
				target.root,
				profile
			)


		if dashing
			and profile.BreakTrackingOnDash then

			breakTracking(
				"Dash"
			)


			return
		end


		-- Smoothed velocity. Never the raw instantaneous value.
		local sample =
			sanitizeVelocitySample(
				target.root.AssemblyLinearVelocity,
				guidanceUp,
				profile
			)


		filteredTargetVelocity =
			filteredTargetVelocity:
			Lerp(
				sample,
				profile.PredictionSmoothing
			)


		local aimPoint =
			getAimPointForRoot(
				target.root,
				profile
			)


		local distance =
			(
				aimPoint
				- currentPosition
			).Magnitude


		local timeToImpact =
			distance
			/ math.max(
				1,
				config.Speed
			)


		-- ---- TERMINAL COMMIT ----
		--
		-- Decided by estimated time to impact, with a distance floor.
		-- After this point the trajectory is frozen, which is exactly what
		-- makes a well timed lateral Dash work.
		if timeToImpact <=
			profile.CommitTime
			or distance <=
			profile.CommitDistance then

			breakTracking(
				"TerminalCommit"
			)


			return
		end


		local interceptPoint =
			computeInterceptForTarget(
				currentPosition,
				target,
				filteredTargetVelocity,
				guidanceUp,
				config.Speed,
				profile,
				dashing,
				dashDirection,
				dashSpeed,
				dashRemaining
			)


		local toIntercept =
			interceptPoint
		- currentPosition


		if toIntercept.Magnitude <= 0.01 then
			return
		end


		-- 11. Never allow an absurd turn away from the released line.
		if angleBetweenDegrees(
			initialDirection,
			toIntercept
			) >
			profile.MaxTrackingAngleDegrees then

			breakTracking(
				"OutsideTrackingCone"
			)


			return
		end


		if profile.GuidanceRequireLineOfSight
			and not hasLineOfSight(
				currentPosition,
				target.character,
				interceptPoint,
				{
					character,
					model,
				}
			) then

			breakTracking(
				"LineOfSightLost"
			)


			return
		end


		desiredDirection =
			buildSurfaceBiasedDirection(
				direction,
				toIntercept,
				guidanceUp,
				profile
			)
	end


	-- ============================================================
	-- STEERING (every frame, for smooth visuals)
	-- ============================================================

	local function applySteering(
		dt: number
	)

		if committed
			or not trackingActive then

			return
		end


		local target =
			lockedTarget


		if not target
			or not target.root.Parent then

			return
		end


		local distance =
			(
				getAimPointForRoot(
					target.root,
					profile
				)
				- currentPosition
			).Magnitude


		local turnRate =
			getGuidanceTurnRate(
				distance,
				profile
			)


		local rampAlpha =
			smoothStep01(
				(
					time()
					- startTime
				)
				/ profile.RampTime
			)


		turnRate =
			turnRate
			* rampAlpha
			* profile.SteeringStrength


		-- Legacy evasive behaviour preserved, but still capped.
		local lateralVelocity =
			filteredTargetVelocity
		- direction
			* filteredTargetVelocity:
			Dot(
				direction
			)


		if lateralVelocity.Magnitude >=
			profile.EvasiveLateralSpeed then

			turnRate *=
				profile.EvasiveTurnMultiplier
		end


		turnRate =
			math.min(
				turnRate,
				profile.MaxTurnRateDegreesPerSecond
			)


		local newDirection,
			appliedDegrees =
			steerTowards(
				direction,
				desiredDirection,
				turnRate
				* dt,
				profile.AngularDeadzoneDegrees
			)


		if appliedDegrees <= 0 then
			return
		end


		direction =
			newDirection


		totalTurnDegrees +=
			appliedDegrees


		if totalTurnDegrees >=
			turnBudgetDegrees then

			breakTracking(
				"TurnBudgetSpent"
			)
		end
	end


	-- ============================================================
	-- 10. HIT DETECTION (swept, no .Touched, no tunneling)
	-- ============================================================

	local function buildCastParams(): RaycastParams

		local params =
			RaycastParams.new()


		params.FilterType =
			Enum.RaycastFilterType.Exclude


		local worldExclusions: {Instance} = {
			character,
			model,
		}


		-- Mission NPCs are interaction actors, not projectile cover.
		local missionNPCs =
			workspace:FindFirstChild(
				"Missions NPC"
			)


		if missionNPCs then

			table.insert(
				worldExclusions,
				missionNPCs
			)
		end


		params.FilterDescendantsInstances =
			ProjectileInteractionService.BuildRaycastExclusions(
				worldExclusions
			)


		params.IgnoreWater =
			true


		return params
	end


	-- Two swept passes:
	--
	-- 1) precise raycast    -> authoritative for WORLD geometry
	-- 2) swept spherecast   -> may only ADD character hits
	--
	-- A fat cast can never make the projectile stop early on a wall, so the
	-- permissive hitbox stays visually fair.
	local function resolveHit(
		fromPosition: Vector3,
		toPosition: Vector3
	): RaycastResult?

		local params =
			buildCastParams()


		local rayDirection =
			toPosition
		- fromPosition


		local preciseHit =
			workspace:
			Raycast(
				fromPosition,
				rayDirection,
				params
			)


		if hitboxRadius <= 0.01 then
			return preciseHit
		end


		local ok,
			sphereHit =
			pcall(
				function()

					return workspace:
					Spherecast(
						fromPosition,
						hitboxRadius,
						rayDirection,
						params
					)
				end
			)


		if not ok
			or not sphereHit then

			return preciseHit
		end


		local sphereCharacter,
			sphereHumanoid =
			getTargetCharacterFromPart(
				sphereHit.Instance :: BasePart
			)


		if not sphereCharacter
			or not sphereHumanoid
			or not isValidTargetCharacter(
				sphereCharacter,
				sphereHumanoid,
				character
			) then

			return preciseHit
		end


		if not preciseHit
			or sphereHit.Distance <=
			preciseHit.Distance
			+ 0.001 then

			return sphereHit
		end


		return preciseHit
	end


	-- ============================================================
	-- FLIGHT STEP
	-- ============================================================

	local function step(
		dt: number
	)

		if hasHit then
			return
		end


		if not model.Parent
			or not mainPart.Parent then

			hasHit =
				true


			stopStep()


			stopTravel()


			ProjectileInteractionService.Unregister(
				model
			)


			return
		end


		if time() - startTime >
			config.Lifetime
				or traveled >
			config.Range then

			hasHit =
				true


			stopStep()


			stopTravel()


			disableTrail(
				trail
			)


			ProjectileInteractionService.Unregister(
				model
			)


			destroyVisual(
				(
					visual.Trail
						and visual.Trail.Lifetime
						or 0
				)
					+ 0.05
			)


			return
		end


		-- ---------------------------------------------
		-- GUIDANCE (10-20 Hz) + STEERING (every frame)
		-- ---------------------------------------------

		if trackingActive
			and not committed then

			guidanceAccumulator +=
				dt


			if guidanceAccumulator >=
				guidanceInterval then

				guidanceAccumulator =
					0


				updateGuidance()
			end


			applySteering(
				dt
			)
		end


		local stepDistance =
			config.Speed
			* dt


		local nextPosition =
			currentPosition
			+ direction
			* stepDistance


		local rayDirection =
			nextPosition
		- currentPosition


		if rayDirection.Magnitude <=
			0.001 then

			return
		end


		-- ---------------------------------------------
		-- 7. PROJECTILE VS PROJECTILE
		-- ---------------------------------------------

		local clashResult =
			ProjectileInteractionService.CheckSegment(
				model,
				currentPosition,
				nextPosition
			)


		if clashResult then

			-- One spatial sound at the actual projectile contact point.
			-- Pair locking inside ProjectileInteractionService prevents the
			-- same pair from resolving twice.
			playProjectileClashSound(
				clashResult.impactPosition
			)


			-- Render the clash spark VFX for EVERY valid projectile clash.
			--
			-- We intentionally keep the existing client event name
			-- "KunaiClash" for backwards compatibility with the LocalScript.
			projectileClashVFX:FireAllClients(
				"KunaiClash",
				clashResult.impactPosition
			)


			-- The SetDirection callback already broke tracking; this is the
			-- safety net for a clash that did not rotate anything.
			breakTracking(
				"ClashResolved"
			)


			if DEBUG_PROJECTILES then

				local otherProjectileType =
					if clashResult.otherModel
					then clashResult.otherModel:GetAttribute(
						"ProjectileType"
					)
					else nil


				print(
					"[ProjectileServer] PROJECTILE CLASH VFX SENT",
					config.Id,
					"vs",
					otherProjectileType,
					clashResult.impactPosition
				)
			end


			if clashResult.selfDestroyed
				or hasHit then

				return
			end


			if DEBUG_PROJECTILES then

				print(
					"[ProjectileServer] CLASH CONTINUE",
					config.Id,
					"outcome=",
					clashResult.outcome,
					"stability=",
					model:GetAttribute(
						"ProjectileClashStabilityRemaining"
					)
				)
			end


			local previous =
				currentPosition


			currentPosition =
				clashResult.impactPosition
				+ direction
				* POST_CLASH_SEPARATION


			traveled +=
				(
					currentPosition
					- previous
				).Magnitude


			if visual.Mode ==
				"FlatAutoSpin" then

				spinAngle +=
					visual.SpinSpeedRadiansPerSecond
					* dt
			end


			model:
				PivotTo(
					buildVisualCFrame(
						config,
						currentPosition,
						direction,
						spinAngle,
						assetCorrection
					)
				)


			ProjectileInteractionService.UpdatePosition(
				model,
				currentPosition
			)


			return
		end


		-- ---------------------------------------------
		-- WORLD / CHARACTER HIT
		-- ---------------------------------------------

		local hit =
			resolveHit(
				currentPosition,
				nextPosition
			)


		if hit then

			hasHit =
				true


			stopStep()


			stopTravel()


			disableTrail(
				trail
			)


			ProjectileInteractionService.Unregister(
				model
			)


			local hitPosition =
				hit.Position


			local hitPart =
				hit.Instance :: BasePart


			local targetCharacter,
				targetHumanoid =
				getTargetCharacterFromPart(
					hitPart
				)


			if targetCharacter
				and targetHumanoid
				and targetCharacter ~=
				character
				and targetHumanoid.Health >
				0
					and targetCharacter:GetAttribute(
						"IsDowned"
					) ~= true then

				local targetPlayer =
					Players:
					GetPlayerFromCharacter(
						targetCharacter
					)


				local damageResult =
					ProjectileDamageService.Apply(
						targetCharacter,
						targetHumanoid,
						targetPlayer,
						player,
						config
					)


				-- Preserve the current Kawarimi rule:
				-- no body-hit audio when Substitution consumes the hit.
				if damageResult ~=
					"Substituted" then

					playImpactSound(
						config,
						hitPosition,
						"Hit"
					)
				end


				-- Kunai substitution currently searches live
				-- Workspace.Kunais/Kunai_* models near the old body.
				-- Keep the object briefly so that system can claim it.
				model:
					PivotTo(
						buildVisualCFrame(
							config,
							hitPosition,
							direction,
							spinAngle,
							assetCorrection
						)
					)


				destroyVisual(
					if damageResult ==
						"Substituted"
						then 0.35
						else math.max(
							0.10,
							(
								visual.Trail
								and visual.Trail.Lifetime
								or 0
							)
							+ 0.05
						)
				)


				return
			end


			local stuckPosition =
				hitPosition
			- direction
				* config.EmbedDepth


			model:
				PivotTo(
					buildVisualCFrame(
						config,
						stuckPosition,
						direction,
						spinAngle,
						assetCorrection
					)
				)


			playImpactSound(
				config,
				hitPosition,
				"Stick"
			)


			destroyVisual(
				config.StuckTime
			)


			return
		end


		-- ---------------------------------------------
		-- 12. NEAR MISS TELEGRAPH
		-- ---------------------------------------------

		if not nearMissFired
			and telegraphTarget
			and telegraphTarget.player
			and telegraphTarget.root.Parent
			and profile.NearMissRadius > 0 then

			local missDistance,
				closestPoint,
				alpha =
				closestApproachToPoint(
					currentPosition,
					nextPosition,
					getAimPointForRoot(
						telegraphTarget.root,
						profile
					)
				)


			if alpha < 1
				and missDistance <=
				profile.NearMissRadius then

				nearMissFired =
					true


				projectileNearMiss:
					FireClient(
						telegraphTarget.player,
						config.Id,
						closestPoint,
						missDistance
					)
			end
		end


		currentPosition =
			nextPosition


		traveled +=
			stepDistance


		if visual.Mode ==
			"FlatAutoSpin" then

			spinAngle +=
				visual.SpinSpeedRadiansPerSecond
				* dt
		end


		model:
			PivotTo(
				buildVisualCFrame(
					config,
					currentPosition,
					direction,
					spinAngle,
					assetCorrection
				)
			)


		ProjectileInteractionService.UpdatePosition(
			model,
			currentPosition
		)
	end


	unregisterStep =
		registerProjectileStep(
			step
		)
end

-- =========================
-- VOLLEY PATTERNS
-- =========================

local function launchVolley(
	player: Player,
	config: any,
	targetPosition: Vector3,
	aimDirection: Vector3,
	initialDefensiveDirection: Vector3?,
	releaseOriginSnapshot: Vector3?
)

	local character,
		_humanoid,
		rootPart =
		getAliveCharacter(
			player
		)


	if not character
		or not rootPart then

		return
	end


	local pattern =
		config.Pattern


	local releaseRootPosition =
		rootPart.Position


	local function getReleaseOriginForRoot(
		liveRoot: BasePart
	): Vector3?

		if not releaseOriginSnapshot
			or not isValidVector3(
				releaseOriginSnapshot
			) then

			return nil
		end


		-- Sequential volleys happen a few frames after the initial release.
		-- Carry the validated release snapshot forward by the character's
		-- actual server-observed displacement so later members do not appear
		-- to come from behind a moving shooter.
		return releaseOriginSnapshot
			+ (
				liveRoot.Position
				- releaseRootPosition
			)
	end


	local count =
		math.max(
			1,
			pattern.Count
			or 1
		)


	local defensiveVolley =
		initialDefensiveDirection ~= nil


	if pattern.Mode ==
		"Sequential" then

		for index = 1,
			count do

			local delayTime =
				(index - 1)
				* pattern.Interval


			task.delay(
				delayTime,
				function()

					local liveCharacter,
					liveHumanoid,
					liveRoot =
						getAliveCharacter(
							player
						)


					if not liveCharacter
						or not liveHumanoid
						or not liveRoot then

						return
					end


					local memberDefensiveDirection =
						initialDefensiveDirection


					-- A defensive sequential volley may refresh its line for
					-- later members. This is useful after the first clash has
					-- changed the incoming projectile's trajectory.
					if defensiveVolley then

						local freshDirection =
							selectDefensiveIntercept(
								player,
								liveCharacter,
								liveRoot,
								config
							)


						if freshDirection then

							memberDefensiveDirection =
								freshDirection
						end
					end


					spawnProjectile(
						player,
						config,
						targetPosition,
						aimDirection,
						Vector3.zero,
						memberDefensiveDirection,
						getReleaseOriginForRoot(
							liveRoot
						)
					)
				end
			)
		end


		return
	end


	if pattern.Mode ==
		"Parallel" then

		local right =
			safeUnit(
				rootPart.CFrame.RightVector,
				Vector3.xAxis
			)


		local center =
			(count + 1)
			* 0.5


		for index = 1,
			count do

			local slot =
				index
			- center


			local offset =
				right
				* slot
				* pattern.Spacing


			spawnProjectile(
				player,
				config,
				targetPosition,
				aimDirection,
				offset,
				initialDefensiveDirection,
				getReleaseOriginForRoot(
					rootPart
				)
			)
		end


		return
	end


	spawnProjectile(
		player,
		config,
		targetPosition,
		aimDirection,
		Vector3.zero,
		initialDefensiveDirection,
		getReleaseOriginForRoot(
			rootPart
		)
	)
end

-- =========================
-- REMOTE HANDLERS
-- =========================

projectileCombatState.OnServerEvent:
	Connect(
		function(
			player: Player,
			active: any
		)

			if typeof(active) ~=
				"boolean" then

				return
			end


			local now =
			time()


			local previous =
			lastCombatSync[
			player
			]
			or -math.huge


			if now - previous <
				0.02 then

				return
			end


			lastCombatSync[
			player
			] =
			now


			mirroredCombatMode[
			player
			] =
			active
		end
	)


projectileRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			slotValue: any,
			targetPosition: any,
			clientAimDirection: any,
			clientReleaseOrigin: any
		)

			local slotIndex,
			projectileType,
			config,
			slotReason =
			resolveNinjaBagSlot(
				player,
				slotValue
			)


			if not slotIndex
				or not projectileType
				or not config
				or slotReason ~= "OK" then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] BAG REJECT",
						player.Name,
						"slot=",
						slotValue,
						slotReason
					)
				end


				return
			end


			if not isValidVector3(
				targetPosition
				)
				or not isValidVector3(
					clientAimDirection
				) then

				return
			end


			local character,
			humanoid,
			rootPart =
			getAliveCharacter(
				player
			)


			if not character
				or not humanoid
				or not rootPart then

				return
			end


			local allowed,
			reason =
			canServerThrow(
				player,
				character,
				humanoid
			)


			if not allowed then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] REJECT",
						projectileType,
						player.Name,
						reason
					)
				end


				return
			end


			-- NORMAL ProjectileRequest is Combat Mode only.
			-- This is the same separation that existed before off-combat
			-- defensive reactions were introduced.
			if mirroredCombatMode[
				player
				] ~= true then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] REJECT",
						projectileType,
						player.Name,
						"CombatMode OFF on offensive request"
					)
				end


				return
			end


			local now =
			workspace:
			GetServerTimeNow()


			local playerCooldowns =
			cooldownEndsAt[
			player
			]


			if not playerCooldowns then

				playerCooldowns =
				{}


				cooldownEndsAt[
				player
				] =
				playerCooldowns
			end


			local currentEnd =
			playerCooldowns[
			projectileType
			]
			or 0


			if now < currentEnd then
				return
			end


			local origin,
			originMode,
			originRawDelta =
			resolveReleaseOrigin(
				player,
				character,
				rootPart,
				projectileType,
				clientReleaseOrigin
			)


			if DEBUG_PROJECTILES
				and originMode ~=
				"ServerOrigin" then

				print(
					"[ProjectileServer] RELEASE ORIGIN",
					player.Name,
					projectileType,
					"mode=",
					originMode,
					"rawDelta=",
					string.format(
						"%.2f",
						originRawDelta
					),
					"speed=",
					string.format(
						"%.2f",
						rootPart.AssemblyLinearVelocity.Magnitude
					)
				)
			end


			local defensiveDirection,
			defensiveThreat =
			selectDefensiveIntercept(
				player,
				character,
				rootPart,
				config
			)


			-- A defensive threat can be behind the camera, so the client's
			-- offensive target distance is irrelevant in that case.
			if not defensiveThreat
				and (
					targetPosition
					- origin
				).Magnitude >
				config.Range
				+ 250 then

				return
			end


			local consumed,
			consumedProjectileType,
			remainingAmmo,
			consumeReason =
			NinjaBagService.ConsumeSlot(
				player,
				slotIndex,
				1
			)


			if not consumed
				or consumedProjectileType ~=
				projectileType then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] BAG CONSUME REJECT",
						player.Name,
						"slot=",
						slotIndex,
						projectileType,
						consumeReason
					)
				end


				return
			end


			local newEnd =
			now
			+ config.Cooldown


			playerCooldowns[
			projectileType
			] =
			newEnd


			globalThrowEndsAt[
			player
			] =
			now
			+ GLOBAL_THROW_LOCK


			publishCoreCooldown(
				character,
				config,
				now,
				newEnd
			)


			-- One accepted event / one local launch sound PER VOLLEY.
			projectileThrowAccepted:
			FireClient(
				player,
				projectileType,
				if defensiveThreat
				then "DefensiveIntercept"
				else "Offensive",
				defensiveThreat
				and defensiveThreat.ProjectileType
				or nil,
				false,
				slotIndex,
				remainingAmmo
			)


			if DEBUG_PROJECTILES
				and defensiveThreat then

				print(
					"[ProjectileServer] AUTO INTERCEPT",
					player.Name,
					config.Id,
					"vs",
					defensiveThreat.ProjectileType,
					"TTI=",
					string.format(
						"%.3f",
						defensiveThreat.TimeToImpact
					),
					"autoCombat=",
					false,
					"slot=",
					slotIndex,
					"ammo=",
					remainingAmmo
				)
			end


			launchVolley(
				player,
				config,
				targetPosition,
				safeUnit(
					clientAimDirection,
					rootPart.CFrame.LookVector
				),
				defensiveDirection,
				origin
			)
		end
	)


-- ============================================================
-- OFF-COMBAT DEFENSIVE REQUEST
-- ============================================================
--
-- This remote has NO offensive fallback.
--
-- If there is no valid incoming threat:
-- reject without cooldown.
--
-- If there is a valid physically interceptable threat:
-- launch the selected projectile in DefensiveIntercept mode and ask the client
-- to enter Combat Mode after server acceptance.

projectileDefensePrepare.OnServerInvoke =
	function(
		player: Player,
		slotValue: any
	)

	local nowClock =
		time()


	local lastPrepare =
		lastDefensePrepareAt[
	player
	]
		or -math.huge


	if nowClock - lastPrepare <
		DEFENSIVE_PREPARE_RATE_LIMIT then

		return false,
			"prepare rate limit"
	end


	lastDefensePrepareAt[
	player
	] =
		nowClock


	local slotIndex,
		projectileType,
		config,
		slotReason =
		resolveNinjaBagSlot(
			player,
			slotValue
		)


	if not slotIndex
		or not projectileType
		or not config
		or slotReason ~= "OK" then

		return false,
			"bag: "
			.. tostring(
				slotReason
			)
	end


	local character,
		humanoid,
		rootPart =
		getAliveCharacter(
			player
		)


	if not character
		or not humanoid
		or not rootPart then

		return false,
			"character unavailable"
	end


	local allowed,
		reason =
		canServerThrow(
			player,
			character,
			humanoid
		)


	if not allowed then

		return false,
			reason
	end


	-- DefensiveCounter is valid both inside and outside CombatMode.


	local now =
		workspace:
		GetServerTimeNow()


	local playerCooldowns =
		cooldownEndsAt[
	player
	]


	if playerCooldowns then

		local currentEnd =
			playerCooldowns[
		projectileType
		]
			or 0


		if now < currentEnd then

			return false,
				"projectile cooldown"
		end
	end


	local defensiveDirection,
		defensiveThreat =
		selectDefensiveInterceptAtRelease(
			player,
			character,
			rootPart,
			config
		)


	if not defensiveDirection
		or not defensiveThreat then

		return false,
			"no projected intercept"
	end


	if DEBUG_PROJECTILES then

		print(
			"[ProjectileServer] DEFENSE PREPARE OK",
			player.Name,
			projectileType,
			"vs",
			defensiveThreat.ProjectileType,
			"TTI=",
			string.format(
				"%.3f",
				defensiveThreat.TimeToImpact
			),
			"releaseDelay=",
			string.format(
				"%.3f",
				DEFENSIVE_PREPARE_RELEASE_DELAY
			)
		)
	end


	return true,
		"OK",
		defensiveThreat.ProjectileType,
		defensiveThreat.TimeToImpact
end


projectileDefenseRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			slotValue: any,
			clientReleaseOrigin: any
		)

			local slotIndex,
			projectileType,
			config,
			slotReason =
			resolveNinjaBagSlot(
				player,
				slotValue
			)


			if not slotIndex
				or not projectileType
				or not config
				or slotReason ~= "OK" then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] DEFENSE BAG REJECT",
						player.Name,
						"slot=",
						slotValue,
						slotReason
					)
				end


				return
			end


			local character,
			humanoid,
			rootPart =
			getAliveCharacter(
				player
			)


			if not character
				or not humanoid
				or not rootPart then

				return
			end


			local allowed,
			reason =
			canServerThrow(
				player,
				character,
				humanoid
			)


			if not allowed then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] DEFENSE REJECT",
						projectileType,
						player.Name,
						reason
					)
				end


				return
			end


			-- DefensiveIntercept remains legal while already in CombatMode.


			local now =
			workspace:
			GetServerTimeNow()


			local playerCooldowns =
			cooldownEndsAt[
			player
			]


			if not playerCooldowns then

				playerCooldowns =
				{}


				cooldownEndsAt[
				player
				] =
				playerCooldowns
			end


			local currentEnd =
			playerCooldowns[
			projectileType
			]
			or 0


			if now < currentEnd then

				return
			end


			local defensiveDirection,
			defensiveThreat =
			selectDefensiveIntercept(
				player,
				character,
				rootPart,
				config
			)


			if not defensiveDirection
				or not defensiveThreat then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] DEFENSE REJECT",
						projectileType,
						player.Name,
						"no valid incoming threat"
					)
				end


				return
			end


			local consumed,
			consumedProjectileType,
			remainingAmmo,
			consumeReason =
			NinjaBagService.ConsumeSlot(
				player,
				slotIndex,
				1
			)


			if not consumed
				or consumedProjectileType ~=
				projectileType then

				if DEBUG_PROJECTILES then

					print(
						"[ProjectileServer] DEFENSE BAG CONSUME REJECT",
						player.Name,
						"slot=",
						slotIndex,
						projectileType,
						consumeReason
					)
				end


				return
			end


			local newEnd =
			now
			+ config.Cooldown


			playerCooldowns[
			projectileType
			] =
			newEnd


			globalThrowEndsAt[
			player
			] =
			now
			+ GLOBAL_THROW_LOCK


			publishCoreCooldown(
				character,
				config,
				now,
				newEnd
			)


			local wasCombatMode =
			mirroredCombatMode[
			player
			] == true


			-- Successful off-combat counters still auto-enter CombatMode.
			-- In-combat counters simply preserve the existing mode.
			mirroredCombatMode[
			player
			] =
			true


			projectileThrowAccepted:
			FireClient(
				player,
				projectileType,
				"DefensiveIntercept",
				defensiveThreat.ProjectileType,
				not wasCombatMode,
				slotIndex,
				remainingAmmo
			)


			if DEBUG_PROJECTILES then

				print(
					"[ProjectileServer] DEFENSIVE INTERCEPT",
					player.Name,
					config.Id,
					"vs",
					defensiveThreat.ProjectileType,
					"TTI=",
					string.format(
						"%.3f",
						defensiveThreat.TimeToImpact
					),
					"combatWasOn=",
					wasCombatMode,
					"autoCombat=",
					not wasCombatMode,
					"slot=",
					slotIndex,
					"ammo=",
					remainingAmmo
				)
			end


			local origin,
			originMode,
			originRawDelta =
			resolveReleaseOrigin(
				player,
				character,
				rootPart,
				projectileType,
				clientReleaseOrigin
			)


			if DEBUG_PROJECTILES
				and originMode ~=
				"ServerOrigin" then

				print(
					"[ProjectileServer] DEFENSE RELEASE ORIGIN",
					player.Name,
					projectileType,
					"mode=",
					originMode,
					"rawDelta=",
					string.format(
						"%.2f",
						originRawDelta
					)
				)
			end


			local syntheticTarget =
			origin
			+ defensiveDirection
			* math.min(
				config.Range,
				300
			)


			launchVolley(
				player,
				config,
				syntheticTarget,
				defensiveDirection,
				defensiveDirection,
				origin
			)
		end
	)


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			cooldownEndsAt[
			player
			] =
			nil


			mirroredCombatMode[
			player
			] =
			nil


			lastCombatSync[
			player
			] =
			nil


			globalThrowEndsAt[
			player
			] =
			nil


			lastDefensePrepareAt[
			player
			] =
			nil
		end
	)


task.defer(
	function()

		for projectileType,
			config in pairs(
				ProjectileConfigs
			) do

			local template =
				resolveTemplate(
					config
				)


			if template then

				print(
					"[ProjectileServer] TEMPLATE",
					projectileType,
					"->",
					template:GetFullName(),
					"class=",
					template.ClassName
				)
			end
		end
	end
)


print(
	"[ProjectileServer] READY v3.0 LockedTarget + AimAssist + Guidance/Commit"
		.. " | TargetLock=ReleaseOnly"
		.. " | Reacquisition=OFF"
		.. " | DirectRayIntent=ON"
		.. " | PredictiveAim=Filtered"
		.. " | DashAwarePrediction=ON"
		.. " | TerminalCommit=TimeToImpact"
		.. " | AngularDeadzone=ON"
		.. " | SweptHitbox=Spherecast"
		.. " | CentralScheduler=ON"
		.. " | GuidanceHz=15"
		.. " | SubstitutionHardCounter=ON"
		.. " | ClashBreaksTracking=ALL"
		.. " | NearMissRemote=ON"
		.. " | Kunai=Single"
		.. " | Shuriken=Sequentialx3"
		.. " | Senbon=Parallelx3"
		.. " | ArmorReady=ON"
		.. " | ClashStability=ON"
		.. " | AutoDefensiveIntercept=ON"
		.. " | OffCombatDefense=ON"
		.. " | DefensivePreflight=ON"
		.. " | CombatCounterPriority=ON"
		.. " | DefensiveThrowSpeed=3.0"
		.. " | DefensivePrepareReleaseDelay=0.222"
		.. " | CounterAutoCombat=ON"
		.. " | ThreatAPIGuard=ON"
		.. " | ClashGhostFix=ON"
		.. " | HeavyWinnerContinuation=ON"
		.. " | ProjectileClashSFX=91709243524873"
		.. " | ClashVFXRemote=ON"
		.. " | NinjaBagSlots=4"
		.. " | ThrowHand=Left"
		.. " | ReleaseOriginCompensation=ON"
		.. " | ReleaseOriginMaxCorrection=8"
		.. " | ServerAmmo=ON"
)
