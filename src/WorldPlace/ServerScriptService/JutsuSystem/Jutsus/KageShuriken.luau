-- ServerScriptService > JutsuSystem > Jutsus > KageShuriken
--
-- Shurikenjutsu · Shuriken Kage Bunshin no Jutsu (primera capa).
-- Lanzas 1 shuriken real; a un tercio del camino se multiplica en 6 que se abren en abanico.
-- Gasta 1 shuriken de la Ninja Bag + chakra. 1 sello de mano.
-- Proyectiles: ReplicatedStorage > Throwables > Definitions > Tech_KageShuriken

local ServerScriptService = game:GetService("ServerScriptService")

local Shurikenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Shurikenjutsu")
)

local KageShuriken = {}

KageShuriken.Id = "KageShuriken"
KageShuriken.TechniqueCategory = "Shurikenjutsu"
KageShuriken.MinimumLevel = 1
KageShuriken.SortOrder = 600

KageShuriken.Config = {
	DisplayName = "Shuriken Kage Bunshin no Jutsu",
	TechniqueCategory = "Shurikenjutsu",
	MinimumLevel = 1,
	SortOrder = 600,

	ChakraCost = 15,
	Cooldown = 9.0,
	CastTime = 0.6,
}

KageShuriken.Weapon = "Tech_KageShuriken"
KageShuriken.Ammo = { Shuriken = 1 }

KageShuriken.MarkerCastTimeout = 6.0
KageShuriken.ProjectileFallbackDelay = 4.0
KageShuriken.MinProjectileDelay = 0.15

return Shurikenjutsu.build(KageShuriken)
