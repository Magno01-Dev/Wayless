-- ServerScriptService > JutsuSystem > Jutsus > KoriShinchu
--
-- Genjutsu · Kori Shinchū no Jutsu (rango C, primera capa).
-- Durante 4 s los demás no ven tu nombre ni tu indicador, y la asistencia de apuntado no te
-- fija (atributo GenjutsuHidden en tu personaje). Tu cuerpo sigue viéndose.
-- No necesita que nadie te mire: es una ilusión sobre ti mismo.
-- 2 sellos.

local ServerScriptService = game:GetService("ServerScriptService")

local Genjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Genjutsu")
)

local KoriShinchu = {}

KoriShinchu.Id = "KoriShinchu"
KoriShinchu.TechniqueCategory = "Genjutsu"
KoriShinchu.MinimumLevel = 1
KoriShinchu.SortOrder = 720

KoriShinchu.Config = {
	DisplayName = "Kori Shinchū no Jutsu",
	TechniqueCategory = "Genjutsu",
	MinimumLevel = 1,
	SortOrder = 720,

	ChakraCost = 22,
	Cooldown = 18.0,
	CastTime = 0.6,

	Duration = 4.0,
}

KoriShinchu.MarkerCastTimeout = 5.0
KoriShinchu.ProjectileFallbackDelay = 3.0
KoriShinchu.MinProjectileDelay = 0

return Genjutsu.build(KoriShinchu, function(context)
	local character: Model = context.Character
	local duration = context.Config.Duration

	-- Un token por uso: si lo vuelves a usar antes de que termine, no se corta antes de tiempo
	local token = (character:GetAttribute("GenjutsuHiddenToken") or 0) + 1
	character:SetAttribute("GenjutsuHiddenToken", token)
	character:SetAttribute("GenjutsuHidden", true)
	Genjutsu.fxAll("Hidden", { Character = character, Duration = duration })

	task.delay(duration, function()
		if character.Parent and character:GetAttribute("GenjutsuHiddenToken") == token then
			character:SetAttribute("GenjutsuHidden", false)
		end
	end)
end)
