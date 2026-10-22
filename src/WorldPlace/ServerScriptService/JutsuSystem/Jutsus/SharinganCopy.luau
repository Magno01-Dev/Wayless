-- ServerScriptService > JutsuSystem > Jutsus > SharinganCopy
--
-- Clan Uchiha · Copia (3 tomoe despertados · nivel 45).
-- Con el Sharingan activo, la última técnica que LEÍSTE (alguien que tenías delante empezó a
-- lanzarla) queda copiada 12 s (TechniqueKit > Clan). Pulsar esta técnica la lanza tú:
-- sus sellos, su animación y su efecto, por un 30 % más de chakra. Se gasta al usarla.
-- Copia ninjutsu (elemental o no), genjutsu, taijutsu, kenjutsu y shurikenjutsu; nunca técnicas de
-- clan ni de Kekkei Genkai (Clan.Tuning.CopyCategories).
-- No hace falta saberla ni tenerla equipada. Si es de una naturaleza que no tienes, funciona pero su
-- daño va ×Clan.Tuning.CopyOffNaturePotency (0.8) durante CopyPotencyWindow s (hook de DamageService).
-- Cooldown propio de 20 s; el del jutsu copiado (si tú también lo tienes) no cambia.
--
-- Cómo funciona: JutsuServer llama a ResolveDelegate y lanza el jutsu copiado en lugar de este
-- (ver "DELEGACIÓN" en JutsuServer). Este módulo no se ejecuta nunca por sí mismo.

local ServerScriptService = game:GetService("ServerScriptService")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local TechniqueRegistry = require(ServerScriptService:WaitForChild("Services"):WaitForChild("TechniqueRegistry"))

local SharinganCopy = {}

SharinganCopy.Id = "SharinganCopy"
SharinganCopy.TechniqueCategory = "Clan"
SharinganCopy.MinimumLevel = 45
SharinganCopy.SortOrder = 1102

SharinganCopy.Config = {
	DisplayName = "Sharingan: Copy",
	TechniqueCategory = "Clan",
	MinimumLevel = 45,
	SortOrder = 1102,

	ChakraCost = 0, -- paga el jutsu copiado × Clan.Tuning.CopyCostMultiplier
	Cooldown = 20.0,
	CastTime = 0.1,
}

SharinganCopy.MarkerCastTimeout = 2.0
SharinganCopy.ProjectileFallbackDelay = 0.5
SharinganCopy.MinProjectileDelay = 0

-- JutsuServer: qué jutsu lanzar en su lugar
function SharinganCopy.ResolveDelegate(player: Player, character: Model?): (string?, string?, number?)
	if not character or not Clan.isModeActive(character, "SharinganActive") then
		Clan.fxTo(player, "Icon", { Icon = "SharinganRequired" })
		return nil, "SharinganRequired", nil
	end
	if Clan.sharinganTomoe(player) < Clan.Tuning.CopyMinTomoe then
		Clan.fxTo(player, "Icon", { Icon = "NotAwakened", Tomoe = Clan.Tuning.CopyMinTomoe })
		return nil, "TomoeRequired", nil
	end
	local jutsuId = Clan.getCopied(player)
	if not jutsuId then
		Clan.fxTo(player, "Icon", { Icon = "NothingCopied" })
		return nil, "NothingCopied", nil
	end
	return jutsuId, nil, Clan.Tuning.CopyCostMultiplier
end

-- ¿La técnica es de una naturaleza que el jugador no tiene?
local function isOffNature(player: Player, jutsuId: string): boolean
	local ok, entry = pcall(TechniqueRegistry.Get, jutsuId)
	local natureId = if ok and typeof(entry) == "table" then entry.NatureId else nil
	if typeof(natureId) ~= "string" then
		return false -- sin naturaleza (taijutsu, kenjutsu, genjutsu…): potencia normal
	end
	if player:GetAttribute("NatureInnate_" .. natureId) == true then
		return false
	end
	for _, key in { "Nature1Id", "Nature2Id", "Nature3Id" } do
		if player:GetAttribute(key) == natureId then
			return false
		end
	end
	return true
end

-- JutsuServer: el jutsu copiado salió (chakra pagado): se gasta la copia y, si no es de tu
-- naturaleza, su daño va reducido un rato
function SharinganCopy.OnDelegateCommitted(player: Player, jutsuId: string)
	Clan.consumeCopied(player)
	local character = player.Character
	if not character then
		return
	end
	if typeof(jutsuId) == "string" and isOffNature(player, jutsuId) then
		character:SetAttribute("CopyPotencyJutsu", jutsuId)
		character:SetAttribute("CopyPotency", Clan.Tuning.CopyOffNaturePotency)
		character:SetAttribute("CopyPotencyUntil", workspace:GetServerTimeNow() + Clan.Tuning.CopyPotencyWindow)
	else
		character:SetAttribute("CopyPotencyJutsu", nil)
	end
end

-- Daño de una técnica copiada fuera de tu naturaleza: ×CopyPotency mientras dure la ventana
DamageService.AddHook({
	ModifyDamage = function(context: any): number
		local attacker = context.Attacker
		local character = if typeof(attacker) == "Instance" and attacker:IsA("Player") then attacker.Character else nil
		if not character or context.SourceId == nil
			or character:GetAttribute("CopyPotencyJutsu") ~= context.SourceId then
			return 1
		end
		local untilAt = character:GetAttribute("CopyPotencyUntil")
		local potency = character:GetAttribute("CopyPotency")
		if typeof(untilAt) ~= "number" or workspace:GetServerTimeNow() > untilAt or typeof(potency) ~= "number" then
			return 1
		end
		return potency
	end,
})

-- Requisitos de clan y registro como técnica (nunca se ejecuta: siempre delega)
return Clan.build(SharinganCopy, "Uchiha", function(_context, _direction) end)
