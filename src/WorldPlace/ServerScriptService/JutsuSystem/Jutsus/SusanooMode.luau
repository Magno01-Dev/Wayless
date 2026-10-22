-- ServerScriptService > JutsuSystem > Jutsus > SusanooMode
--
-- Clan Uchiha · Susanoo (mantener Z; Clan.resolveAwaken "Susanoo").
-- Modo encima del Mangekyō (si no estaba, lo enciende también). Mientras está activo gasta chakra
-- y ciega poco a poco (modeDefinitions.SusanooActive en TechniqueKit > Clan). Sus efectos (brazo
-- en los M1) los leen los sistemas de combate por el atributo SusanooActive. Mantener Z otra vez
-- lo apaga (el Mangekyō sigue).

local ServerScriptService = game:GetService("ServerScriptService")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)

local SusanooMode = {}

SusanooMode.Id = "SusanooMode"
SusanooMode.TechniqueCategory = "Clan"
SusanooMode.MinimumLevel = 1
SusanooMode.SortOrder = 1103

SusanooMode.Config = {
	DisplayName = "Susanoo",
	TechniqueCategory = "Clan",
	MinimumLevel = 1,
	SortOrder = 1103,

	ChakraCost = 25,
	Cooldown = 3,
	CastTime = 0.1,
}

SusanooMode.MarkerCastTimeout = 2.0
SusanooMode.ProjectileFallbackDelay = 0.5
SusanooMode.MinProjectileDelay = 0

return Clan.buildCustomMode(SusanooMode, "Uchiha", {
	Execute = function(context)
		local player, character = context.Player, context.Character
		if not Clan.isMangekyoActive(character) then
			Clan.setMangekyoMode(player, character, true)
		end
		if Clan.isMangekyoActive(character) then
			Clan.startMode(player, character, Clan.getModeDefinition("SusanooActive"))
		end
	end,
	IsActive = function(character: Model): boolean
		return character:GetAttribute("SusanooActive") == true
	end,
	TurnOff = function(character: Model)
		Clan.stopMode(character, "SusanooActive")
	end,
})
