--!strict
-- DamageService v1.4 - Multiplicative Penetration + Shared Armor Gateway + Counter Stance + Chakura Nagashi + Hooks
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

-- v1.2 · Postura de contraataque (taijutsu)
-- Si el objetivo tiene CounterStanceUntil (tiempo del servidor) vigente y el golpe es cuerpo
-- a cuerpo, el golpe se esquiva: se devuelve "Substituted" (todos los sistemas ya lo tratan
-- como "no le diste": sin daño, aturdimiento, combo ni armadura) y se avisa por
-- ServerStorage > CombatInternal > CounterTriggered(defensor, atacante, tipo).
local MELEE_SOURCE_TYPES: {[string]: boolean} = {
	M1 = true,
	Lunge = true,
	AerialKick = true,
	Launcher = true,
	Taijutsu = true,
	Kenjutsu = true,
}

-- v1.3 · Chakura Nagashi (kenjutsu)
-- Mientras el atacante tenga ChakraFlowElement + ChakraFlowUntil vigentes y el arma
-- desenvainada, sus golpes con arma (M1 y Kenjutsu) hacen más daño y, si dan en el cuerpo,
-- aplican el estado elemental canónico de ese elemento.
local CHAKRA_FLOW_SOURCE_TYPES: {[string]: boolean} = {
	M1 = true,
	Kenjutsu = true,
}
local CHAKRA_FLOW_DAMAGE_MULTIPLIER = 1.35
local CHAKRA_FLOW_STATUS: {[string]: string} = {
	Fire = "Burning",
	Wind = "Unsteady",
	Lightning = "Charged",
	Earth = "Heavy",
	Water = "Wet",
}

local statusEffectService: any = nil

local function applyChakraFlowStatus(targetCharacter: Model, attacker: Player, element: string)
	local statusId = CHAKRA_FLOW_STATUS[element]
	if not statusId then
		return
	end
	if statusEffectService == nil then
		local ok, result = pcall(function()
			return require(game:GetService("ServerScriptService"):WaitForChild("Services"):WaitForChild("StatusEffectService"))
		end)
		statusEffectService = if ok then result else false
	end
	if statusEffectService then
		pcall(statusEffectService.Apply, targetCharacter, statusId, {
			SourcePlayer = attacker,
			SourceCharacter = attacker.Character,
		})
	end
end

-- v1.4 · Ganchos de daño (pasivas de clan, etc.)
-- DamageService.AddHook({
--     ModifyDamage = function(context) -> número (multiplicador del daño base) o nil,
--     AfterHit = function(context, result) -> (), -- solo si el golpe dio en el cuerpo
-- })
-- Se ejecutan protegidos (pcall): un error en un gancho no rompe el daño.
type DamageHook = {
	ModifyDamage: ((any) -> number?)?,
	AfterHit: ((any, string) -> ())?,
}

local damageHooks: {DamageHook} = {}

function DamageService.AddHook(hook: DamageHook)
	table.insert(damageHooks, hook)
end

-- Elemento activo de Chakura Nagashi del atacante para este golpe (o nil)
local function getChakraFlowElement(context: any): string?
	local attacker = context.Attacker
	local attackerCharacter = attacker and attacker.Character
	if not attackerCharacter
		or CHAKRA_FLOW_SOURCE_TYPES[context.SourceType or ""] ~= true
		or attackerCharacter:GetAttribute("WeaponState") ~= "Drawn" then
		return nil
	end
	local element = attackerCharacter:GetAttribute("ChakraFlowElement")
	local untilTime = attackerCharacter:GetAttribute("ChakraFlowUntil")
	if typeof(element) ~= "string" or typeof(untilTime) ~= "number"
		or workspace:GetServerTimeNow() > untilTime then
		return nil
	end
	return element
end

local counterTriggered: BindableEvent? = nil

local function getCounterTriggered(): BindableEvent
	if counterTriggered and counterTriggered.Parent then
		return counterTriggered
	end
	local folder = ServerStorage:FindFirstChild("CombatInternal")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatInternal"
		folder.Parent = ServerStorage
	end
	local found = folder:FindFirstChild("CounterTriggered")
	if not found then
		found = Instance.new("BindableEvent")
		found.Name = "CounterTriggered"
		found.Parent = folder
	end
	counterTriggered = found :: BindableEvent
	return counterTriggered :: BindableEvent
end

task.spawn(getCounterTriggered)

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

	-- Postura de contraataque: esquiva el golpe cuerpo a cuerpo y avisa (una vez)
	if context.Attacker
		and MELEE_SOURCE_TYPES[context.SourceType or ""] == true then

		local stanceUntil = targetCharacter:GetAttribute("CounterStanceUntil")

		if typeof(stanceUntil) == "number"
			and workspace:GetServerTimeNow() <= stanceUntil then

			targetCharacter:SetAttribute("CounterStanceUntil", nil)
			getCounterTriggered():Fire(targetCharacter, context.Attacker, context.SourceType)

			return {
				Result = "Substituted",
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
	end

	local chakraFlowElement = getChakraFlowElement(context)
	if chakraFlowElement then
		baseDamage *= CHAKRA_FLOW_DAMAGE_MULTIPLIER
	end

	for _, hook in damageHooks do
		if hook.ModifyDamage then
			local ok, multiplier = pcall(hook.ModifyDamage, context)
			if ok and typeof(multiplier) == "number" and multiplier >= 0 then
				baseDamage *= multiplier
			end
		end
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

	-- Chakura Nagashi: el golpe que da en el cuerpo aplica el estado de su elemento
	if chakraFlowElement and context.Attacker
		and (BODY_HIT_RESULTS[result] == true or result == "DamagedNPC") then
		applyChakraFlowStatus(targetCharacter, context.Attacker, chakraFlowElement)
	end

	if BODY_HIT_RESULTS[result] == true or result == "DamagedNPC" then
		for _, hook in damageHooks do
			if hook.AfterHit then
				local ok, err = pcall(hook.AfterHit, context, result)
				if not ok then
					warn("[DamageService] AfterHit hook error:", err)
				end
			end
		end
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
