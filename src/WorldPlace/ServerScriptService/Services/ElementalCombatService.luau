--!strict
-- ServerScriptService > Services > ElementalCombatService
--
-- WAYLESS elemental state + reaction gateway v3 StatusBalance.
--
-- PROC RULE:
-- A registered elemental technique that lands a valid DamageService hit gets
-- ONE server-authoritative status proc roll per target per cast.
--
-- Multi-hit techniques do NOT receive a new roll on every tick/projectile.
-- Individual elemental jutsus must NOT manually implement their basic state.
--
-- Current jutsu modules do not all forward CastToken through DamageService,
-- so this service uses the live JutsuCastToken character attribute when
-- available and a 2-second same-source/technique/target lock as a safe fallback.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local ServerScriptService =
	game:GetService("ServerScriptService")

local services =
	ServerScriptService:
	WaitForChild("Services")

local DamageService = require(
	ServerScriptService:
		WaitForChild("DamageService")
)

local StatusEffectService = require(
	services:
		WaitForChild("StatusEffectService")
)

local TechniqueRegistry = require(
	services:
		WaitForChild("TechniqueRegistry")
)

local shared =
	ReplicatedStorage:
	WaitForChild("CharacterOriginSystem"):
	WaitForChild("Shared")

local NatureDefinitions = require(
	shared:
		WaitForChild("NatureDefinitions")
)

local ReactionDefinitions = require(
	shared:
		WaitForChild("ElementalReactionDefinitions")
)

local Service = {}

local started = false
local originalDamageApply: any = nil

local originalStatusApply: any = nil
local originalStatusHas: any = nil
local originalStatusRemove: any = nil
local originalGetDefinition: any = nil

local reactionBindable =
	Instance.new("BindableEvent")

Service.ReactionOccurred =
	reactionBindable.Event

local BODY_HIT_RESULTS = {
	Damaged = true,
	Downed = true,
	DamagedNPC = true,
}

local STATUS_BY_NATURE = {
	Fire = "Burning",
	Wind = "Unsteady",
	Lightning = "Charged",
	Earth = "Heavy",
	Water = "Wet",
}

local ELEMENTAL_STATUS_IDS = {
	Burning = true,
	Unsteady = true,
	Charged = true,
	Heavy = true,
	Wet = true,
}

---------------------------------------------------------------------
-- ELEMENTAL STATUS PROC BALANCE
--
-- Chance is 0.0 - 1.0 and is rolled ONCE per target per cast.
--
-- 0.00 = this technique never applies the basic elemental status.
-- 1.00 = guaranteed when a valid body hit lands.
--
-- These values are intentionally centralized here for the first balance
-- pass. A jutsu may override its value later through:
--
--     Module.ElementalStatus.Chance
-- or:
--     Module.Config.ElementalStatus.Chance
---------------------------------------------------------------------

local TECHNIQUE_STATUS_PROC_CHANCE: {[string]: number} = {
	-- Fire -> Burning
	Fireball = 0.35,
	Hosenka = 0.20,
	FlameBreath = 0.20,
	FlameWave = 0.40,

	-- Water -> Wet
	WaterBullet = 0.35,
	WaterWave = 0.50,
	WaterWhip = 0.30,
	WaterPrison = 1.00,

	-- Wind -> Unsteady
	AirBullet = 0.25,
	WindBlade = 0.35,
	GalePalm = 0.00,
	WindSweep = 0.35,

	-- Lightning -> Charged
	LightningBolt = 0.40,
	LightningStream = 0.25,
	StaticBurst = 0.30,
	LightningSenbon = 0.20,

	-- Earth -> Heavy
	StoneShot = 0.40,
	EarthWall = 0.00,
	EarthSpikes = 0.30,
	EarthTremor = 0.50,
}

---------------------------------------------------------------------
-- CANONICAL ELEMENTAL STATUS BALANCE v1
--
-- Design rule:
-- Burning is the ONLY basic elemental state that deals extra damage.
-- Wet / Unsteady / Charged / Heavy are utility/setup states.
--
-- Reapplying the same elemental status NEVER stacks it. A successful
-- re-proc refreshes the status to one clean instance.
---------------------------------------------------------------------

local STATUS_BALANCE = {
	Burning = {
		Duration = 3.5,

		-- StatusEffectRuntime multiplies the authored Burning DOT by
		-- Metadata.ElementalPotency. 0.50 therefore halves its current
		-- authored DOT without bypassing StatusEffectService.
		Potency = 0.50,
	},

	Wet = {
		Duration = 5.0,
		Potency = 1.0,
	},

	Unsteady = {
		Duration = 4.0,
		Potency = 1.0,

		KnockbackReceivedMultiplier = 1.15,
		GuardPressureTakenMultiplier = 1.10,
	},

	Charged = {
		Duration = 4.0,
		Potency = 1.0,
	},

	Heavy = {
		Duration = 4.0,
		Potency = 1.0,

		DashDistanceMultiplier = 0.85,
		JumpMultiplier = 0.90,
		AirControlMultiplier = 0.90,
	},
}

local PROC_FALLBACK_LOCK_SECONDS =
	2.0

local PROC_HISTORY_TTL =
	15.0

local procRandom =
	Random.new()

-- Weak target keys prevent destroyed characters from being retained forever.
local procRollHistory: any =
	setmetatable(
		{},
		{
			__mode = "k",
		}
	)

local warnedMissingProcChance:
	{[string]: boolean} =
	{}

local CONDUCTIVE_STAGGER_COOLDOWN =
	1.25

local function now(): number
	return workspace:GetServerTimeNow()
end

local function canonicalEffectId(
	effectId: string
): string
	if effectId == "Burn" then
		return "Burning"
	end
	return effectId
end

local function installLegacyStatusAlias()
	originalStatusApply =
		StatusEffectService.Apply

	originalStatusHas =
		StatusEffectService.Has

	originalStatusRemove =
		StatusEffectService.Remove

	originalGetDefinition =
		StatusEffectService.GetDefinition

	StatusEffectService.Apply =
		function(
			character: Model,
			effectId: string,
			options: any?
		)
		return originalStatusApply(
			character,
			canonicalEffectId(effectId),
			options
		)
	end

	StatusEffectService.Has =
		function(
			character: Model,
			effectId: string
		)
		return originalStatusHas(
			character,
			canonicalEffectId(effectId)
		)
	end

	StatusEffectService.Remove =
		function(
			character: Model,
			effectId: string,
			reason: string?
		)
		return originalStatusRemove(
			character,
			canonicalEffectId(effectId),
			reason
		)
	end

	StatusEffectService.GetDefinition =
		function(effectId: string)
			return originalGetDefinition(
				canonicalEffectId(effectId)
			)
		end
end

local function setMultiplier(
	character: Model,
	name: string,
	value: number
)
	character:SetAttribute(
		name,
		value
	)
end

local function getBalancedNumber(
	statusId: string,
	fieldName: string,
	fallback: number
): number

	local balance =
		STATUS_BALANCE[
	statusId
	]

	if typeof(balance) == "table" then
		local value =
			balance[
		fieldName
		]

		if typeof(value) == "number" then
			return value
		end
	end

	return fallback
end

local function recomputeElementalAttributes(
	character: Model
)
	if not character.Parent then
		return
	end

	local burning =
		StatusEffectService.Has(
			character,
			"Burning"
		)

	local unsteady =
		StatusEffectService.Has(
			character,
			"Unsteady"
		)

	local charged =
		StatusEffectService.Has(
			character,
			"Charged"
		)

	local heavy =
		StatusEffectService.Has(
			character,
			"Heavy"
		)

	local wet =
		StatusEffectService.Has(
			character,
			"Wet"
		)

	character:SetAttribute(
		"Status_Burning",
		burning
	)

	character:SetAttribute(
		"Status_Unsteady",
		unsteady
	)

	character:SetAttribute(
		"Status_Charged",
		charged
	)

	character:SetAttribute(
		"Status_Heavy",
		heavy
	)

	character:SetAttribute(
		"Status_Wet",
		wet
	)

	-----------------------------------------------------------------
	-- UNSTEADY
	--
	-- No bonus damage. It makes displacement and guard pressure more
	-- dangerous while the state is active.
	-----------------------------------------------------------------

	setMultiplier(
		character,
		"Status_KnockbackReceivedMultiplier",
		unsteady
			and getBalancedNumber(
				"Unsteady",
				"KnockbackReceivedMultiplier",
				1.15
			)
			or 1.0
	)

	setMultiplier(
		character,
		"Status_GuardPressureTakenMultiplier",
		unsteady
			and getBalancedNumber(
				"Unsteady",
				"GuardPressureTakenMultiplier",
				1.10
			)
			or 1.0
	)

	-----------------------------------------------------------------
	-- HEAVY
	--
	-- No bonus damage. Mobility penalty only.
	-----------------------------------------------------------------

	setMultiplier(
		character,
		"Status_DashDistanceMultiplier",
		heavy
			and getBalancedNumber(
				"Heavy",
				"DashDistanceMultiplier",
				0.85
			)
			or 1.0
	)

	setMultiplier(
		character,
		"Status_JumpMultiplier",
		heavy
			and getBalancedNumber(
				"Heavy",
				"JumpMultiplier",
				0.90
			)
			or 1.0
	)

	setMultiplier(
		character,
		"Status_AirControlMultiplier",
		heavy
			and getBalancedNumber(
				"Heavy",
				"AirControlMultiplier",
				0.90
			)
			or 1.0
	)

	-----------------------------------------------------------------
	-- WET / CHARGED
	--
	-- Intentionally no raw damage and no generic movement penalty.
	-- Their value is reaction/setup utility.
	-----------------------------------------------------------------

	if not burning then
		character:SetAttribute(
			"ElementalPotency_Burning",
			nil
		)
	end
end

local function getTechniqueProcChance(
	entry: any,
	techniqueId: string
): number

	local module =
		entry.Module

	local config =
		entry.Config

	local tuning =
		if typeof(module) == "table"
		then module.ElementalStatus
		else nil

	if tuning == nil
		and typeof(config) == "table" then

		tuning =
			config.ElementalStatus
	end

	if typeof(tuning) == "table"
		and typeof(tuning.Chance) == "number" then

		return math.clamp(
			tuning.Chance,
			0,
			1
		)
	end

	local authored =
		TECHNIQUE_STATUS_PROC_CHANCE[
	techniqueId
	]

	if typeof(authored) == "number" then
		return math.clamp(
			authored,
			0,
			1
		)
	end

	-- Fail closed for future elemental techniques until a proc chance is
	-- deliberately authored. This prevents new content from silently
	-- receiving a guaranteed status.
	if not warnedMissingProcChance[
		techniqueId
		] then
		warnedMissingProcChance[
		techniqueId
		] = true

		warn(
			"[ElementalCombatService] MISSING proc chance",
			techniqueId,
			"Fallback=0%"
		)
	end

	return 0
end

local function getLiveCastToken(
	sourcePlayer: Player?,
	techniqueId: string,
	contactContext: any?
): string?

	if typeof(contactContext) == "table" then
		local directToken =
			contactContext.CastToken

		if typeof(directToken) == "string"
			and directToken ~= "" then

			return directToken
		end
	end

	if not sourcePlayer then
		return nil
	end

	local sourceCharacter =
		sourcePlayer.Character

	if not sourceCharacter then
		return nil
	end

	local castingId =
		sourceCharacter:GetAttribute(
			"JutsuCastingId"
		)

	local castToken =
		sourceCharacter:GetAttribute(
			"JutsuCastToken"
		)

	if castingId == techniqueId
		and typeof(castToken) == "string"
		and castToken ~= "" then

		return castToken
	end

	return nil
end

local function consumeProcRoll(
	sourcePlayer: Player?,
	targetCharacter: Model,
	techniqueId: string,
	contactContext: any?
): (boolean, string)

	local current =
		now()

	local history =
		procRollHistory[
	targetCharacter
	]

	if typeof(history) ~= "table" then
		history = {}
		procRollHistory[
		targetCharacter
		] = history
	end

	-- Opportunistic cleanup.
	for key, timestamp in pairs(
		history
		) do
		if typeof(timestamp) ~= "number"
			or current - timestamp
			> PROC_HISTORY_TTL then

			history[key] =
				nil
		end
	end

	local sourceKey =
		if sourcePlayer
		then tostring(
			sourcePlayer.UserId
		)
		else "NPC"

	local fallbackKey =
		sourceKey
		.. "|"
		.. techniqueId
		.. "|Fallback"

	local castToken =
		getLiveCastToken(
			sourcePlayer,
			techniqueId,
			contactContext
		)

	if castToken then
		local exactKey =
			sourceKey
			.. "|"
			.. techniqueId
			.. "|"
			.. castToken

		if typeof(
			history[
			exactKey
			]
			) == "number" then

			return false,
				"DuplicateCastProcRoll"
		end

		-- If an earlier hit from this same cast had already fallen back
		-- before the live token was readable, do not grant another roll.
		local fallbackAt =
			history[
		fallbackKey
		]

		if typeof(fallbackAt) == "number"
			and current - fallbackAt
			< PROC_FALLBACK_LOCK_SECONDS then

			history[
			exactKey
			] = current

			return false,
				"DuplicateFallbackProcRoll"
		end

		history[
		exactKey
		] = current

		-- Also stamp fallback protection so late projectile/tick contacts
		-- from this cast cannot reroll after JutsuCastToken is cleared.
		history[
		fallbackKey
		] = current

		return true, "ExactCastToken"
	end

	local lastFallback =
		history[
	fallbackKey
	]

	if typeof(lastFallback) == "number"
		and current - lastFallback
		< PROC_FALLBACK_LOCK_SECONDS then

		return false,
			"DuplicateFallbackProcRoll"
	end

	history[
	fallbackKey
	] = current

	return true, "FallbackLock"
end

local function publishProcQA(
	targetCharacter: Model,
	techniqueId: string,
	statusId: string,
	chance: number,
	roll: number?,
	succeeded: boolean,
	reason: string
)
	if targetCharacter:GetAttribute(
		"TrainingDummy"
		) ~= true
			and targetCharacter:GetAttribute(
				"IsCombatDummy"
			) ~= true then

		return
	end

	targetCharacter:SetAttribute(
		"ElementalProc_LastTechnique",
		techniqueId
	)

	targetCharacter:SetAttribute(
		"ElementalProc_LastStatus",
		statusId
	)

	targetCharacter:SetAttribute(
		"ElementalProc_LastChance",
		chance
	)

	targetCharacter:SetAttribute(
		"ElementalProc_LastRoll",
		roll
	)

	targetCharacter:SetAttribute(
		"ElementalProc_LastSucceeded",
		succeeded
	)

	targetCharacter:SetAttribute(
		"ElementalProc_LastReason",
		reason
	)

	targetCharacter:SetAttribute(
		"ElementalProc_LastAt",
		now()
	)
end

local function getStatusTuning(
	entry: any,
	statusId: string
): (boolean, number?, number)

	local module =
		entry.Module

	local config =
		entry.Config

	local balance =
		STATUS_BALANCE[
	statusId
	]

	local defaultDuration =
		if typeof(balance) == "table"
		and typeof(balance.Duration) == "number"
		then balance.Duration
		else nil

	local defaultPotency =
		if typeof(balance) == "table"
		and typeof(balance.Potency) == "number"
		then math.max(
			0,
			balance.Potency
		)
		else 1.0

	local tuning =
		if typeof(module) == "table"
		then module.ElementalStatus
		else nil

	if tuning == nil
		and typeof(config) == "table" then

		tuning =
			config.ElementalStatus
	end

	if typeof(tuning) == "table" then
		if tuning.Enabled == false then
			return false, nil, defaultPotency
		end

		local duration =
			typeof(tuning.Duration) == "number"
			and math.max(
				0.05,
				tuning.Duration
			)
			or defaultDuration

		local potency =
			typeof(tuning.Potency) == "number"
			and math.max(
				0,
				tuning.Potency
			)
			or defaultPotency

		return true, duration, potency
	end

	-- Existing Fireball config compatibility.
	-- Preserve only the legacy Enabled switch. Duration/potency are now
	-- centrally owned by STATUS_BALANCE so Fireball follows the same
	-- canonical Burning rules as every other Katon technique.
	if statusId == "Burning"
		and typeof(config) == "table"
		and typeof(config.Burn) == "table" then

		if config.Burn.Enabled == false then
			return false, nil, defaultPotency
		end

		return true,
			defaultDuration,
			defaultPotency
	end

	return true,
		defaultDuration,
		defaultPotency
end

local function getReactionCandidates(
	targetCharacter: Model,
	incomingNatureId: string
): {any}

	local result = {}

	for _, existingNatureId in ipairs(
		NatureDefinitions.Order
		) do
		if existingNatureId == incomingNatureId then
			continue
		end

		local statusId =
			STATUS_BY_NATURE[
		existingNatureId
		]

		if statusId
			and StatusEffectService.Has(
				targetCharacter,
				statusId
			) then

			local reaction =
				ReactionDefinitions.GetByNatures(
					incomingNatureId,
					existingNatureId
				)

			if reaction then
				table.insert(
					result,
					{
						ExistingNatureId =
							existingNatureId,

						Reaction =
							reaction,
					}
				)
			end
		end
	end

	return result
end

local function publishReaction(
	targetCharacter: Model,
	reaction: any,
	incomingNatureId: string,
	existingNatureId: string,
	sourcePlayer: Player?,
	techniqueId: string
)
	local current =
		now()

	targetCharacter:SetAttribute(
		"ElementalReaction_LastId",
		reaction.Id
	)

	targetCharacter:SetAttribute(
		"ElementalReaction_LastAt",
		current
	)

	targetCharacter:SetAttribute(
		"ElementalReaction_LastIncomingNature",
		incomingNatureId
	)

	targetCharacter:SetAttribute(
		"ElementalReaction_LastExistingNature",
		existingNatureId
	)

	targetCharacter:SetAttribute(
		"ElementalReaction_LastTechnique",
		techniqueId
	)

	targetCharacter:SetAttribute(
		"ElementalReaction_LastSourceUserId",
		sourcePlayer
			and sourcePlayer.UserId
			or 0
	)

	reactionBindable:Fire(
		{
			ReactionId =
				reaction.Id,

			Definition =
				reaction,

			TargetCharacter =
				targetCharacter,

			IncomingNatureId =
				incomingNatureId,

			ExistingNatureId =
				existingNatureId,

			SourcePlayer =
				sourcePlayer,

			SourceTechniqueId =
				techniqueId,

			At =
				current,
		}
	)

	print(
		"[ElementalCombatService] REACTION",
		reaction.Id,
		targetCharacter.Name,
		existingNatureId
			.. "+"
			.. incomingNatureId,
		"Source="
			.. techniqueId
	)
end

local function handleBuiltInReaction(
	targetCharacter: Model,
	reaction: any,
	sourcePlayer: Player?,
	techniqueId: string
)
	if reaction.Behavior
		~= "ConductiveMicroStagger" then

		return
	end

	local current =
		now()

	local readyAt =
		targetCharacter:GetAttribute(
			"ElementalConductiveStaggerReadyAt"
		)

	if typeof(readyAt) ~= "number"
		or current >= readyAt then

		targetCharacter:SetAttribute(
			"ElementalConductiveStaggerReadyAt",
			current
				+ CONDUCTIVE_STAGGER_COOLDOWN
		)

		StatusEffectService.Apply(
			targetCharacter,
			"ElementalMicroStagger",
			{
				Duration = 0.24,

				SourcePlayer =
					sourcePlayer,

				SourceCharacter =
					sourcePlayer
					and sourcePlayer.Character
					or nil,

				Metadata = {
					ReactionId =
						"Conductive",

					SourceTechnique =
						techniqueId,
				},
			}
		)
	end

	-- Charged is the consumable reaction state.
	StatusEffectService.Remove(
		targetCharacter,
		"Charged",
		"Reaction:Conductive"
	)
end

function Service.ProcessTechniqueContact(
	sourcePlayer: Player?,
	targetCharacter: Model,
	techniqueId: string,
	contactContext: any?
): (boolean, string)

	local entry =
		TechniqueRegistry.Get(
			techniqueId
		)

	if not entry then
		return false, "UnknownTechnique"
	end

	local natureId =
		entry.NatureId

	if typeof(natureId) ~= "string" then
		return false, "NonElementalTechnique"
	end

	local statusId =
		STATUS_BY_NATURE[
	natureId
	]

	if not statusId then
		return false, "UnknownNatureStatus"
	end

	local enabled,
		duration,
		potency =
		getStatusTuning(
			entry,
			statusId
		)

	if not enabled then
		return false, "ElementalStatusDisabled"
	end

	local procChance =
		getTechniqueProcChance(
			entry,
			techniqueId
		)

	if procChance <= 0 then
		publishProcQA(
			targetCharacter,
			techniqueId,
			statusId,
			procChance,
			nil,
			false,
			"ProcChanceZero"
		)

		return false, "ProcChanceZero"
	end

	-- IMPORTANT:
	-- Consume the roll opportunity BEFORE randomizing. A failed first roll
	-- still consumes this target's roll for the cast, so multi-hit moves
	-- cannot brute-force a proc by ticking repeatedly.
	local canRoll,
		rollReason =
		consumeProcRoll(
			sourcePlayer,
			targetCharacter,
			techniqueId,
			contactContext
		)

	if not canRoll then
		return false, rollReason
	end

	local roll: number? =
		nil

	local procSucceeded =
		false

	if procChance >= 1 then
		procSucceeded =
			true
	else
		roll =
			procRandom:NextNumber()

		procSucceeded =
			roll < procChance
	end

	publishProcQA(
		targetCharacter,
		techniqueId,
		statusId,
		procChance,
		roll,
		procSucceeded,
		procSucceeded
			and "ProcSucceeded"
			or "ProcChanceFailed"
	)

	if targetCharacter:GetAttribute(
		"TrainingDummy"
		) == true
			or targetCharacter:GetAttribute(
				"IsCombatDummy"
			) == true then

		targetCharacter:SetAttribute(
			"ElementalProc_LastDuration",
			duration
		)

		targetCharacter:SetAttribute(
			"ElementalProc_LastPotency",
			potency
		)
	end

	if not procSucceeded then
		return false, "ProcChanceFailed"
	end

	-- Reactions are intentionally gated behind a successful elemental proc
	-- during this balance pass. A non-proc hit deals its normal technique
	-- damage but does not also trigger a reaction.
	--
	-- Snapshot before incoming status is applied.
	local reactions =
		getReactionCandidates(
			targetCharacter,
			natureId
		)

	local metadata = {
		SourceType =
			"Technique",

		SourceTechnique =
			techniqueId,

		SourceNature =
			natureId,

		ElementalPotency =
			potency,
	}

	-----------------------------------------------------------------
	-- SINGLE INSTANCE / REFRESH ONLY
	--
	-- We deliberately remove the existing instance before reapplying.
	-- This guarantees elemental statuses cannot accumulate stacks even if
	-- the underlying generic StatusEffect definition allows stacking.
	-----------------------------------------------------------------

	if StatusEffectService.Has(
		targetCharacter,
		statusId
		) then
		StatusEffectService.Remove(
			targetCharacter,
			statusId,
			"ElementalStatusRefresh"
		)
	end

	if statusId == "Burning" then
		targetCharacter:SetAttribute(
			"ElementalPotency_Burning",
			potency
		)

		metadata.ElementalPotency =
			potency
	end

	StatusEffectService.Apply(
		targetCharacter,
		statusId,
		{
			Duration =
				duration,

			Stacks =
				1,

			SourcePlayer =
				sourcePlayer,

			SourceCharacter =
				sourcePlayer
				and sourcePlayer.Character
				or nil,

			Metadata =
				metadata,
		}
	)

	recomputeElementalAttributes(
		targetCharacter
	)

	for _, candidate in ipairs(
		reactions
		) do
		publishReaction(
			targetCharacter,
			candidate.Reaction,
			natureId,
			candidate.ExistingNatureId,
			sourcePlayer,
			techniqueId
		)

		handleBuiltInReaction(
			targetCharacter,
			candidate.Reaction,
			sourcePlayer,
			techniqueId
		)
	end

	return true, statusId
end

local function processDamageResolution(
	context: any,
	resolution: any
)
	if typeof(context) ~= "table"
		or typeof(resolution) ~= "table" then

		return
	end

	if BODY_HIT_RESULTS[
		resolution.Result
		] ~= true then

		return
	end

	if context.SourceType ~= "Jutsu"
		and context.SourceType ~= "Technique" then

		return
	end

	if typeof(context.SourceId) ~= "string"
		or context.SourceId == "" then

		return
	end

	local target =
		context.TargetCharacter

	if typeof(target) ~= "Instance"
		or not target:IsA("Model")
		or not target.Parent then

		return
	end

	local sourcePlayer =
		context.Attacker

	if typeof(sourcePlayer) ~= "Instance"
		or not sourcePlayer:IsA("Player") then

		sourcePlayer = nil
	end

	Service.ProcessTechniqueContact(
		sourcePlayer,
		target,
		context.SourceId,
		context
	)
end

local function installDamageHook()
	originalDamageApply =
		DamageService.Apply

	DamageService.Apply =
		function(context: any)
			local resolution =
			originalDamageApply(
				context
			)

			processDamageResolution(
				context,
				resolution
			)

			return resolution
		end
end

function Service.Start()
	if started then
		return
	end

	started = true

	installLegacyStatusAlias()
	installDamageHook()

	StatusEffectService.Applied:
		Connect(
			function(
				character: Model,
				effectId: string
			)
				if ELEMENTAL_STATUS_IDS[
					effectId
					] then

					recomputeElementalAttributes(
						character
					)
				end
			end
		)

	StatusEffectService.Removed:
		Connect(
			function(
				character: Model,
				effectId: string
			)
				if ELEMENTAL_STATUS_IDS[
					effectId
					] then

					recomputeElementalAttributes(
						character
					)
				end
			end
		)

	print(
		"[ElementalCombatService] READY v3 StatusBalance"
			.. " | AutoDamageHook=ON"
			.. " | StatusProcChance=ON"
			.. " | MultiHitSingleRoll=ON"
			.. " | SingleInstanceRefresh=ON"
			.. " | BurningPotency=0.50"
			.. " | WetUtilityOnly=ON"
			.. " | ChargedUtilityOnly=ON"
			.. " | UnsteadyKB=1.15"
			.. " | HeavyDash=0.85"
			.. " | ReactionsRequireProc=ON"
			.. " | ConductiveMicroStagger=ON"
	)
end

return Service
