-- ServerScriptService > JutsuSystem > Jutsus > Soshujin
--
-- Shurikenjutsu · Sōshūjin, kunai guiado con hilo (primera capa).
-- Lanzas un kunai con hilo (14 de daño). Mientras vuela, volver a presionar la tecla de este
-- jutsu lo redirige UNA vez hacia donde apuntas, más rápido (lo maneja ThrowController v3.2).
-- Gasta 1 kunai de la Ninja Bag + chakra. Sin sellos.
-- Proyectiles: ReplicatedStorage > Throwables > Definitions > Tech_Soshujin
--
-- El Id "Soshujin" debe coincidir con Throwables.Config.RedirectTechnique.

local ServerScriptService = game:GetService("ServerScriptService")

local Shurikenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Shurikenjutsu")
)

local Soshujin = {}

Soshujin.Id = "Soshujin"
Soshujin.TechniqueCategory = "Shurikenjutsu"
Soshujin.MinimumLevel = 1
Soshujin.SortOrder = 630

Soshujin.Config = {
	DisplayName = "Sōshūjin",
	TechniqueCategory = "Shurikenjutsu",
	MinimumLevel = 1,
	SortOrder = 630,

	ChakraCost = 8,
	-- Más largo que el vuelo del kunai: así la segunda pulsación no vuelve a lanzar el jutsu
	Cooldown = 7.0,
	CastTime = 0.4,
}

Soshujin.Weapon = "Tech_Soshujin"
Soshujin.Ammo = { Kunai = 1 }

Soshujin.MarkerCastTimeout = 6.0
Soshujin.ProjectileFallbackDelay = 4.0
Soshujin.MinProjectileDelay = 0.1

return Shurikenjutsu.build(Soshujin)
