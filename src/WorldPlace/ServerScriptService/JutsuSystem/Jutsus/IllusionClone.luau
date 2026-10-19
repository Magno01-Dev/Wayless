-- ServerScriptService > JutsuSystem > Jutsus > IllusionClone
--
-- Genjutsu · Bunshin no Jutsu, clones ilusorios de academia (rango D, primera capa).
-- 2 copias tuyas salen corriendo en diagonal durante 4 s. No hacen daño, no tienen cuerpo
-- y se deshacen en humo si alguien las toca. Sirven para confundir quién es el real.
-- Las dibuja cada cliente (GenjutsuClient); el servidor solo lo anuncia.
-- 2 sellos.

local ServerScriptService = game:GetService("ServerScriptService")

local Genjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Genjutsu")
)

local IllusionClone = {}

IllusionClone.Id = "IllusionClone"
IllusionClone.TechniqueCategory = "Genjutsu"
IllusionClone.MinimumLevel = 1
IllusionClone.SortOrder = 730

IllusionClone.Config = {
	DisplayName = "Bunshin no Jutsu",
	TechniqueCategory = "Genjutsu",
	MinimumLevel = 1,
	SortOrder = 730,

	ChakraCost = 10,
	Cooldown = 12.0,
	CastTime = 0.5,

	Duration = 4.0,
	Count = 2,
	Speed = 20,
}

IllusionClone.MarkerCastTimeout = 5.0
IllusionClone.ProjectileFallbackDelay = 3.0
IllusionClone.MinProjectileDelay = 0

return Genjutsu.build(IllusionClone, function(context)
	local config = context.Config
	Genjutsu.fxAll("Clones", {
		Character = context.Character,
		Duration = config.Duration,
		Count = config.Count,
		Speed = config.Speed,
		Seed = math.random(1, 1000000),
	})
end)
