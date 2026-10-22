-- ServerScriptService > JutsuSystem > Jutsus > GenjutsuSharingan
--
-- Clan Uchiha · Genjutsu: Sharingan (2 tomoe despertados · nivel 20).
-- Solo con el Sharingan activo. Apuntas a alguien (≤ 55 studs con 2 tomoe, 65 con 3; cono de
-- 12° alrededor del retículo): durante 0,4 s suena el Sharingan desde ti y tus ojos brillan (no
-- hay aviso en pantalla: oírlo es la pista para apartar la mirada) y, si al acabar te tiene en
-- su campo visual (140°, sin paredes), queda paralizado 1,2 s: no se mueve ni ataca
-- (estado SharinganBind).
-- Es un genjutsu: lo rompe recibir un golpe de 5 o más (sirve para abrir, no para encadenar),
-- y si el objetivo también tiene el Sharingan activo le dura la mitad.
-- Sin sellos: es la mirada. Si no te mira cuando acaban de girar los tomoe, falla (el chakra
-- se gasta igual). Sin Sharingan o sin nadie en la mira, ni empieza.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local Genjutsu = require(kit:WaitForChild("Genjutsu"))

local AIM_ANGLE = 12

-- Alcance según los tomoe de quien lo lanza (Clan.Tuning)
local function rangeOf(character: Model): number
	local tomoe = Clan.sharinganTomoe(Players:GetPlayerFromCharacter(character))
	return Clan.Tuning.GenjutsuSharinganRangeByTomoe[tomoe] or 55
end

local GenjutsuSharingan = {}

GenjutsuSharingan.Id = "GenjutsuSharingan"
GenjutsuSharingan.TechniqueCategory = "Clan"
GenjutsuSharingan.MinimumLevel = 20
GenjutsuSharingan.SortOrder = 1101
-- Con la mirada, sin sellos: sin sonidos de sellos (suena solo el aviso del Sharingan)
GenjutsuSharingan.NoHandSigns = true

GenjutsuSharingan.Config = {
	DisplayName = "Genjutsu: Sharingan",
	TechniqueCategory = "Clan",
	MinimumLevel = 20,
	SortOrder = 1101,

	ChakraCost = 20,
	Cooldown = 18.0,
	CastTime = 0.4,

	Windup = 0.4,
	Duration = 1.2,
	ImmunityAfter = 2.0, -- s sin que le entre otra parálisis al soltarse (controles encadenados)
}

function GenjutsuSharingan.Precheck(character: Model, direction: Vector3): (boolean, string)
	local player = Players:GetPlayerFromCharacter(character)
	if not Clan.isModeActive(character, "SharinganActive") then
		Clan.fxTo(player, "Icon", { Icon = "SharinganRequired" })
		return false, "SharinganRequired"
	end
	if Clan.sharinganTomoe(player) < 2 then
		Clan.fxTo(player, "Icon", { Icon = "NotAwakened", Tomoe = 2 })
		return false, "TomoeRequired"
	end
	return Clan.findTarget({ Character = character }, direction, rangeOf(character), AIM_ANGLE) ~= nil, "NoTarget"
end

GenjutsuSharingan.MarkerCastTimeout = 3.0
GenjutsuSharingan.ProjectileFallbackDelay = 0.5
GenjutsuSharingan.MinProjectileDelay = 0

return Clan.build(GenjutsuSharingan, "Uchiha", function(context, direction)
	local config = context.Config
	local caster: Model = context.Character
	local target = Clan.findTarget(context, direction, rangeOf(caster), AIM_ANGLE)
	if not target then
		Genjutsu.fxTo(context.Player, "Fail", { Reason = "NoTarget" })
		return
	end

	-- Aviso: suena el Sharingan desde ti y tus ojos brillan (ClanClient)
	Clan.fxAll("SharinganWindup", { Character = caster, Target = target.Character, Duration = config.Windup })

	task.delay(config.Windup, function()
		local humanoid = caster:FindFirstChildOfClass("Humanoid")
		if not caster.Parent or context.Player.Character ~= caster or not humanoid or humanoid.Health <= 0
			or not Clan.isModeActive(caster, "SharinganActive")
			or not target.Character.Parent or target.Humanoid.Health <= 0 then
			return
		end
		local sees, reason = Genjutsu.canSee(target.Character, caster)
		if not sees then
			Genjutsu.fxTo(context.Player, "Fail", { Reason = reason })
			return
		end
		local tomoe = math.clamp(Clan.sharinganTomoe(context.Player), 1, 3)
		local applied = Genjutsu.apply(target, {
			Kind = "GenjutsuSharingan",
			StatusId = "SharinganBind",
			Duration = config.Duration,
			Attacker = context.Player,
			DamageService = context.DamageService,
			-- La víctima ve el Sharingan con los tomoe de quien la atrapó
			Visual = { Tomoe = tomoe },
			Paralyze = true,
			ImmunityAfter = config.ImmunityAfter,
		})
		if applied then
			Genjutsu.fxTo(context.Player, "Success", { Kind = "GenjutsuSharingan", Target = target.Character })
			-- Los demás ven a la víctima paralizada mientras dure (ClanClient sigue el atributo InGenjutsu)
			Clan.fxAll("SharinganBind", { Character = caster, Target = target.Character, Tomoe = tomoe })
			-- Maestría solo contra jugadores
			if Players:GetPlayerFromCharacter(target.Character) then
				Clan.addMastery(context.Player, Clan.Tuning.Mastery.GenjutsuLanded, "Genjutsu")
			end
		end
	end)
end)
