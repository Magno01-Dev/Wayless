-- ServerScriptService > JutsuSystem > Jutsus > SofushaSanNoTachi
--
-- Shurikenjutsu · Sōfūsha San no Tachi (primera capa).
-- 3 shurikens con hilo: uno por la izquierda, otro por la derecha y otro por arriba.
-- Llegan juntos; si alguno da, el hilo ata al objetivo (WireBind 0.7 s + WireSlow 2.2 s),
-- una sola vez por lanzamiento.
-- Gasta 3 shurikens + 1 hilo ninja de la Ninja Bag + chakra. Sin sellos.
-- Proyectiles: ReplicatedStorage > Throwables > Definitions > Tech_Sofusha

local ServerScriptService = game:GetService("ServerScriptService")

local Shurikenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Shurikenjutsu")
)

local SofushaSanNoTachi = {}

SofushaSanNoTachi.Id = "SofushaSanNoTachi"
SofushaSanNoTachi.TechniqueCategory = "Shurikenjutsu"
SofushaSanNoTachi.MinimumLevel = 1
SofushaSanNoTachi.SortOrder = 610

SofushaSanNoTachi.Config = {
	DisplayName = "Sōfūsha San no Tachi",
	TechniqueCategory = "Shurikenjutsu",
	MinimumLevel = 1,
	SortOrder = 610,

	ChakraCost = 12,
	Cooldown = 14.0,
	CastTime = 0.5,
}

SofushaSanNoTachi.Weapon = "Tech_Sofusha"
SofushaSanNoTachi.Ammo = { Shuriken = 3, NinjaWire = 1 }

SofushaSanNoTachi.MarkerCastTimeout = 6.0
SofushaSanNoTachi.ProjectileFallbackDelay = 4.0
SofushaSanNoTachi.MinProjectileDelay = 0.15

return Shurikenjutsu.build(SofushaSanNoTachi)
