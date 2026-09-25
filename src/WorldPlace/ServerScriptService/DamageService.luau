--!strict
-- DamageService v1.1 - Multiplicative Penetration + Shared Armor Gateway
-- ServerScriptService > DamageService [ModuleScript]
--
-- Future combat damage (M1, projectiles, weapons, jutsus, explosions) should
-- route through this module instead of duplicating Armor logic.
--
-- Order:
-- 1) calculate provisional Armor mitigation
-- 2) forward final damage to DownedInternal.ApplyDamage for player targets
-- 3) only if the body was actually hit, commit Armor durability loss
--
-- This preserves CombatTag / Substitution / Downed / Execute behavior and
-- ensures Kawarimi never consumes Armor durability.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local downedInternal = ServerStorage:WaitForChild("DownedInternal")
local applyDownedDamage = downedInternal:WaitForChild("ApplyDamage") :: BindableFunction

local DamageService = {}

export type ArmorProfile = {
	Penetration: number?,
	DurabilityDamage: number?,
}

export type DamageContext = {
	TargetCharacter: Model,
	TargetHumanoid: Humanoid,
	TargetPlayer: Player?,
	Attacker: Player?,
	Damage: number,
	SourceType: string?,
	SourceId: string?,
	Armor: ArmorProfile?,
	IgnoreArmor: boolean?,
}

export type DamageResolution = {
	Result: string,
	BaseDamage: number,
	FinalDamage: number,
	AbsorbedDamage: number,
	DurabilityDamage: number,
	ArmorApplied: boolean,
	ArmorCondition: number,
	ArmorResistance: number,
	EffectiveResistance: number,
	Penetration: number,
	SourceType: string,
	SourceId: string,
}

local BODY_HIT_RESULTS: {[string]: boolean} = {
	Damaged = true,
	Downed = true,
}

local function normalizeFraction(value: any): number
	if typeof(value) ~= "number" then
		return 0
	end

	local numberValue = value
	if numberValue > 1 then
		numberValue /= 100
	end

	return math.clamp(numberValue, 0, 0.95)
end

local function sanitizeDamage(value: any): number
	if typeof(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge then
		return 0
	end

	return math.max(0, value)
end

function DamageService.GetArmorSnapshot(character: Model): {
	hasArmor: boolean,
	resistance: number,
	durability: number,
	maxDurability: number,
	condition: number,
	}
	local resistance = normalizeFraction(character:GetAttribute("ArmorResistance"))

	local durabilityValue = character:GetAttribute("ArmorDurability")
	local maxDurabilityValue = character:GetAttribute("ArmorMaxDurability")

	local durability = if typeof(durabilityValue) == "number"
		then math.max(0, durabilityValue)
		else 0

	local maxDurability = if typeof(maxDurabilityValue) == "number"
		then math.max(0, maxDurabilityValue)
		else 0

	local condition = if maxDurability > 0
		then math.clamp(durability / maxDurability, 0, 1)
		else 0

	local hasArmor = resistance > 0
		and maxDurability > 0
		and durability > 0
		and condition > 0

	return {
		hasArmor = hasArmor,
		resistance = resistance,
		durability = durability,
		maxDurability = maxDurability,
		condition = condition,
	}
end

function DamageService.CalculateArmor(
	character: Model,
	baseDamage: number,
	armorProfile: ArmorProfile?,
	ignoreArmor: boolean?
): (number, number, number, boolean, number, number, number, number)
	local safeBaseDamage = sanitizeDamage(baseDamage)
	local snapshot = DamageService.GetArmorSnapshot(character)

	if ignoreArmor == true or not snapshot.hasArmor or safeBaseDamage <= 0 then
		return safeBaseDamage, 0, 0, false,
			snapshot.condition, snapshot.resistance, 0, 0
	end

	local penetration = normalizeFraction(
		armorProfile and armorProfile.Penetration or 0
	)

	local effectiveResistance = snapshot.resistance * snapshot.condition

	-- Penetration is the FRACTION of the armor's current effective
	-- resistance ignored by this source.
	--
	-- Example:
	-- 15% resistance + 18% penetration
	-- -> 15% * (1 - 0.18)
	-- -> 12.3% resistance remains.
	--
	-- This avoids the old behavior where any penetration number larger
	-- than the armor percentage completely bypassed the armor.
	local remainingResistance =
		effectiveResistance
		* (1 - penetration)

	local finalDamage = safeBaseDamage * (1 - remainingResistance)
	local absorbedDamage = math.max(0, safeBaseDamage - finalDamage)

	local durabilityMultiplier = if armorProfile
		and typeof(armorProfile.DurabilityDamage) == "number"
		then math.max(0, armorProfile.DurabilityDamage)
		else 1

	local durabilityDamage = absorbedDamage * durabilityMultiplier

	return finalDamage,
		absorbedDamage,
		durabilityDamage,
		true,
		snapshot.condition,
		snapshot.resistance,
		effectiveResistance,
		penetration
end

local function commitArmorDurabilityDamage(character: Model, durabilityDamage: number)
	if durabilityDamage <= 0 then
		return
	end

	local currentValue = character:GetAttribute("ArmorDurability")
	if typeof(currentValue) ~= "number" then
		return
	end

	local newValue = math.max(0, currentValue - durabilityDamage)

	character:SetAttribute("ArmorDurability", newValue)
	character:SetAttribute("ArmorLastDamageAt", workspace:GetServerTimeNow())
	character:SetAttribute("ArmorBroken", newValue <= 0)
end

local function shouldCommitArmorDamage(result: string, targetPlayer: Player?): boolean
	if targetPlayer == nil then
		return result == "DamagedNPC"
	end

	-- This deliberately excludes Substituted, AlreadyDowned, BeingExecuted,
	-- ForceField and FinalDeath because no normal body damage was applied.
	return BODY_HIT_RESULTS[result] == true
end

function DamageService.Apply(context: DamageContext): DamageResolution
	local targetCharacter = context.TargetCharacter
	local targetHumanoid = context.TargetHumanoid
	local targetPlayer = context.TargetPlayer

	if targetPlayer == nil then
		targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	end

	local baseDamage = sanitizeDamage(context.Damage)

	-- Mission NPCs are interaction actors, not combat targets.
	-- This is a final shared-gateway safety net for future jutsus/weapons.
	if targetCharacter:GetAttribute(
		"IsMissionNPC"
		) == true then

		return {
			Result = "MissionNPC",
			BaseDamage = baseDamage,
			FinalDamage = 0,
			AbsorbedDamage = 0,
			DurabilityDamage = 0,
			ArmorApplied = false,
			ArmorCondition = 0,
			ArmorResistance = 0,
			EffectiveResistance = 0,
			Penetration = 0,
			SourceType = context.SourceType or "Unknown",
			SourceId = context.SourceId or "",
		}
	end

	local finalDamage,
		absorbedDamage,
		provisionalDurabilityDamage,
		armorApplied,
		armorCondition,
		armorResistance,
		effectiveResistance,
		penetration = DamageService.CalculateArmor(
			targetCharacter,
			baseDamage,
			context.Armor,
			context.IgnoreArmor
		)

	local result: string

	if targetPlayer then
		local rawResult = applyDownedDamage:Invoke(
			targetPlayer,
			finalDamage,
			context.Attacker
		)

		result = if typeof(rawResult) == "string"
			then rawResult
			else tostring(rawResult)
	else
		targetHumanoid:TakeDamage(finalDamage)
		result = "DamagedNPC"
	end

	local committedDurabilityDamage = 0

	if armorApplied and shouldCommitArmorDamage(result, targetPlayer) then
		committedDurabilityDamage = provisionalDurabilityDamage
		commitArmorDurabilityDamage(targetCharacter, committedDurabilityDamage)
	end

	return {
		Result = result,
		BaseDamage = baseDamage,
		FinalDamage = finalDamage,
		AbsorbedDamage = absorbedDamage,
		DurabilityDamage = committedDurabilityDamage,
		ArmorApplied = armorApplied,
		ArmorCondition = armorCondition,
		ArmorResistance = armorResistance,
		EffectiveResistance = effectiveResistance,
		Penetration = penetration,
		SourceType = context.SourceType or "Unknown",
		SourceId = context.SourceId or "",
	}
end

print(
	"[DamageService] READY v1.1"
		.. " | ArmorGateway=ON"
		.. " | Penetration=Multiplicative"
		.. " | DownedGateway=ON"
		.. " | SubstitutionSafe=ON"
)

return DamageService
