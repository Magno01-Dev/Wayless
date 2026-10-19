-- ServerScriptService > JutsuSystem > Jutsus > Sharingan
--
-- Clan Uchiha · Sharingan, 1 tomoe (etapa 1 · Despertar).
-- Modo: la misma tecla lo activa y lo desactiva. Activarlo cuesta 10 de chakra; activo gasta
-- 2 de chakra por segundo y NO regeneras chakra (estado DojutsuActive).
-- Mientras está activo ves sobre la cabeza de los demás QUÉ JUTSU están preparando (nombre
-- y anillo) desde que empiezan los sellos (ClanClient lee JutsuCastingName).
-- Los ojos rojos se ven: el rival sabe cuándo lo tienes activo.
-- Se apaga solo sin chakra, con el chakra suprimido o al quedar Downed.

local ServerScriptService = game:GetService("ServerScriptService")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)

local Sharingan = {}

Sharingan.Id = "Sharingan"
Sharingan.TechniqueCategory = "Clan"
Sharingan.MinimumLevel = 1
Sharingan.SortOrder = 1100

Sharingan.Config = {
	DisplayName = "Sharingan",
	TechniqueCategory = "Clan",
	MinimumLevel = 1,
	SortOrder = 1100,

	ChakraCost = 10,
	Cooldown = 1.5,
	CastTime = 0.1,
}

Sharingan.MarkerCastTimeout = 2.0
Sharingan.ProjectileFallbackDelay = 0.5
Sharingan.MinProjectileDelay = 0

return Clan.buildMode(Sharingan, "Uchiha", {
	Attribute = "SharinganActive",
	DrainPerSecond = 2,
	Status = "DojutsuActive",
})
