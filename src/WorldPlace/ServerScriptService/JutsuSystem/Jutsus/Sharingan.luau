-- ServerScriptService > JutsuSystem > Jutsus > Sharingan
--
-- Clan Uchiha · Sharingan.
-- Modo en la tecla Z (despertar del clan, Clan.resolveAwaken): no va en un slot. La misma
-- tecla lo activa y lo desactiva (apagarlo responde siempre, aunque estés aturdido o en
-- cooldown). Activarlo cuesta 8 de chakra; activo gasta chakra por segundo y NO regeneras
-- chakra (estado DojutsuActive).
-- Tomoe = etapa despertada (Clan: nivel + maestría; el primero despierta en peligro). Más
-- tomoe: menos gasto (1,5 / 1,25 / 1,0 por s), más alcance de lectura (90 / 110 / 130),
-- sellos más rápidos (10 / 20 / 30 %) y, desde 2, romper sellos y Genjutsu: Sharingan.
-- Mientras está activo, el personaje lleva SharinganTomoe y SealSpeedMultiplier.
-- Mientras está activo:
--   - lees los jutsus de quien tengas delante (campo visual de 140°, sin paredes, ≤ 60 studs):
--     nombre, barra de sellos y hacia dónde va a salir (TechniqueKit > Clan · ClanClient);
--   - los clones ilusorios que veas se marcan como falsos;
--   - los genjutsu que te lancen duran la mitad.
-- Los ojos rojos se ven (variante "Sharingan" de AppearanceCatalog): el rival sabe cuándo lo
-- tienes activo.
-- Se apaga solo sin chakra, con el chakra suprimido, al quedar Downed o si lo quitas del loadout.

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

	ChakraCost = 8,
	Cooldown = 1.5,
	CastTime = 0.1,
}

Sharingan.MarkerCastTimeout = 2.0
Sharingan.ProjectileFallbackDelay = 0.5
Sharingan.MinProjectileDelay = 0

return Clan.buildMode(Sharingan, "Uchiha", {
	Attribute = "SharinganActive",
	DrainPerSecond = 1.5,
	Status = "DojutsuActive",
	EyeVariant = "Sharingan",

	-- Al activarlo: drenaje, ojos y SharinganTomoe según el nivel. En Mangekyō (doble Z,
	-- Clan.mangekyoConfig) gasta más y añade MangekyoActive y las partes del Mangekyō propio (MangekyoAttack, MangekyoControl, MangekyoColor, MangekyoIris, MangekyoWeapon).
	Configure = function(player: Player)
		local tomoe = math.clamp(Clan.sharinganTomoe(player), 1, 3)
		local config = {
			DrainPerSecond = Clan.Tuning.SharinganDrainByTomoe[tomoe],
			EyeVariant = Clan.sharinganEyeVariant(player, tomoe),
			Attributes = {
				SharinganTomoe = tomoe,
				SealSpeedMultiplier = Clan.Tuning.SealSpeedByTomoe[tomoe],
			} :: {[string]: any},
		}
		local mangekyo = Clan.mangekyoConfig(player)
		if mangekyo then
			config.DrainPerSecond = mangekyo.DrainPerSecond
			for name, value in mangekyo.Attributes do
				config.Attributes[name] = value
			end
		end
		return config
	end,
})
