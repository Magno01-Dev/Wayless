-- ServerScriptService > JutsuSystem > Jutsus > Narakumi
--
-- Genjutsu · Narakumi no Jutsu (rango C, primera capa). Miedo.
-- Apuntas a alguien (≤ 70 studs, cono de 12° alrededor del retículo). Si te tiene en su campo
-- visual (cono de 140°, sin paredes en medio), durante 3 s ve el mundo distorsionado y se
-- mueve un 20 % más lento. 3 de daño.
-- Se rompe con Genjutsu Kai, recibiendo un golpe de 5 o más, o al acabar el tiempo.
-- Si te da la espalda, falla (el chakra se gasta igual).
-- 2 sellos.

local ServerScriptService = game:GetService("ServerScriptService")

local Genjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Genjutsu")
)

local RANGE = 70
local AIM_ANGLE = 12

local Narakumi = {}

Narakumi.Id = "Narakumi"
Narakumi.TechniqueCategory = "Genjutsu"
Narakumi.MinimumLevel = 1
Narakumi.SortOrder = 710

Narakumi.Config = {
	DisplayName = "Narakumi no Jutsu",
	TechniqueCategory = "Genjutsu",
	MinimumLevel = 1,
	SortOrder = 710,

	ChakraCost = 20,
	Cooldown = 14.0,
	CastTime = 0.6,

	Duration = 3.0,
	Damage = 3,
}

-- Sin nadie en la mira, el jutsu ni empieza
function Narakumi.Precheck(character: Model, direction: Vector3): (boolean, string)
	return Genjutsu.findTarget({ Character = character }, direction, RANGE, AIM_ANGLE) ~= nil, "NoTarget"
end

Narakumi.MarkerCastTimeout = 5.0
Narakumi.ProjectileFallbackDelay = 3.0
Narakumi.MinProjectileDelay = 0

return Genjutsu.build(Narakumi, function(context, direction)
	local config = context.Config
	local target = Genjutsu.findTarget(context, direction, RANGE, AIM_ANGLE)
	if not target then
		Genjutsu.fxTo(context.Player, "Fail", { Reason = "NoTarget" })
		return
	end

	local sees, reason = Genjutsu.canSee(target.Character, context.Character)
	if not sees then
		Genjutsu.fxTo(context.Player, "Fail", { Reason = reason })
		return
	end

	Genjutsu.apply(target, {
		Kind = "Narakumi",
		StatusId = "Narakumi",
		Duration = config.Duration,
		Damage = config.Damage,
		Attacker = context.Player,
		DamageService = context.DamageService,
	})
	Genjutsu.fxTo(context.Player, "Success", { Kind = "Narakumi", Target = target.Character })
end)
