-- ServerScriptService > JutsuSystem > Jutsus > Mangekyo
--
-- Clan Uchiha · Mangekyō Sharingan (doble toque de Z; Clan.resolveAwaken "Mangekyo").
-- No es un modo aparte: sube el Sharingan a Mangekyō (Clan.setMangekyoMode). Con el Sharingan
-- apagado lo enciende ya en Mangekyō. El mismo doble toque lo apaga (apaga el Sharingan entero).
-- Requiere haberlo despertado (etapa 4) y no estar al máximo de ceguera (Clan.resolveAwaken).

local ServerScriptService = game:GetService("ServerScriptService")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)

local Mangekyo = {}

Mangekyo.Id = "Mangekyo"
Mangekyo.TechniqueCategory = "Clan"
Mangekyo.MinimumLevel = 1
Mangekyo.SortOrder = 1102

Mangekyo.Config = {
	DisplayName = "Mangekyō Sharingan",
	TechniqueCategory = "Clan",
	MinimumLevel = 1,
	SortOrder = 1102,

	ChakraCost = 12,
	Cooldown = 1.5,
	CastTime = 0.1,
}

Mangekyo.MarkerCastTimeout = 2.0
Mangekyo.ProjectileFallbackDelay = 0.5
Mangekyo.MinProjectileDelay = 0

return Clan.buildCustomMode(Mangekyo, "Uchiha", {
	Execute = function(context)
		Clan.setMangekyoMode(context.Player, context.Character, true)
	end,
	IsActive = function(character: Model): boolean
		return Clan.isMangekyoActive(character)
	end,
	TurnOff = function(character: Model)
		Clan.stopMode(character, "SharinganActive")
	end,
})
