-- ServerScriptService > JutsuSystem > Jutsus > KunaiRain
--
-- Shurikenjutsu · Lluvia de kunai (primera capa).
-- Lanzas la ráfaga hacia arriba; el suelo se marca en rojo y ~1 s después caen 10 kunai
-- (5 reales multiplicados con chakra) en un círculo de radio 6 donde apuntabas.
-- Se ve venir: salir del círculo lo esquiva.
-- Gasta 5 kunai de la Ninja Bag + chakra. Sin sellos.
-- Proyectiles: ReplicatedStorage > Throwables > Definitions > Tech_KunaiRain

local ServerScriptService = game:GetService("ServerScriptService")

local Shurikenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Shurikenjutsu")
)

local KunaiRain = {}

KunaiRain.Id = "KunaiRain"
KunaiRain.TechniqueCategory = "Shurikenjutsu"
KunaiRain.MinimumLevel = 1
KunaiRain.SortOrder = 620

KunaiRain.Config = {
	DisplayName = "Kunai Rain",
	TechniqueCategory = "Shurikenjutsu",
	MinimumLevel = 1,
	SortOrder = 620,

	ChakraCost = 18,
	Cooldown = 16.0,
	CastTime = 0.5,
}

KunaiRain.Weapon = "Tech_KunaiRain"
KunaiRain.Ammo = { Kunai = 5 }
KunaiRain.GroundTarget = true

KunaiRain.MarkerCastTimeout = 6.0
KunaiRain.ProjectileFallbackDelay = 4.0
KunaiRain.MinProjectileDelay = 0.15

return Shurikenjutsu.build(KunaiRain)
