-- ServerScriptService > JutsuSystem > Jutsus > Byakugan
--
-- Clan Hyūga · Byakugan (etapa 1 · Despertar).
-- Modo: la misma tecla lo activa y lo desactiva. Activarlo cuesta 10 de chakra; activo gasta
-- 2 de chakra por segundo y NO regeneras chakra (estado DojutsuActive).
-- Mientras está activo (lo dibuja ClanClient en TU pantalla):
--   - ves a todos los jugadores a ≤ 45 studs a través de las paredes;
--   - ves a través del humo, del Henge (ves el cuerpo real), de los clones ilusorios
--     (marcados como falsos) y de las minas ocultas.
-- La pasiva Jūken (tenketsu) es del clan y funciona siempre, con o sin Byakugan.

local ServerScriptService = game:GetService("ServerScriptService")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)

local Byakugan = {}

Byakugan.Id = "Byakugan"
Byakugan.TechniqueCategory = "Clan"
Byakugan.MinimumLevel = 1
Byakugan.SortOrder = 1110

Byakugan.Config = {
	DisplayName = "Byakugan",
	TechniqueCategory = "Clan",
	MinimumLevel = 1,
	SortOrder = 1110,

	ChakraCost = 10,
	Cooldown = 1.5,
	CastTime = 0.1,
}

Byakugan.MarkerCastTimeout = 2.0
Byakugan.ProjectileFallbackDelay = 0.5
Byakugan.MinProjectileDelay = 0

return Clan.buildMode(Byakugan, "Hyuga", {
	Attribute = "ByakuganActive",
	DrainPerSecond = 2,
	Status = "DojutsuActive",
})
