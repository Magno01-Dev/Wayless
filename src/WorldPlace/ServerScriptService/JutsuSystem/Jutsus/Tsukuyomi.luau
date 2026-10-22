-- ServerScriptService > JutsuSystem > Jutsus > Tsukuyomi
--
-- Clan Uchiha · Mangekyō · ojo de control: Tsukuyomi (MangekyoCatalog).
-- Solo con el Mangekyō activo y Tsukuyomi en tu ojo de control. Miras a alguien (≤ Range studs, cono AimAngle) y, si
-- al acabar el Windup te tiene en su campo visual (contacto visual: 140°, sin paredes), queda
-- atrapado Duration s: no se mueve, no ataca y recibe TickDamage cada TickInterval (el
-- tormento del genjutsu). No lo rompen los golpes (Genjutsu.apply con Unbreakable) pero sí
-- Genjutsu Kai y se puede rebotar con el Genjutsu Kaeshi; con el Sharingan activo dura menos
-- (pasiva del clan). Si no te mira, falla (el chakra se gasta igual). Al soltarse, la víctima queda
-- ImmunityAfter s inmune a otro control (no entra si ya estaba inmune).
-- Sube EyeStrain (fatiga ocular) puntos; con la fatiga ocular alta recarga más lento (CooldownMultiplier).
-- Visual: GenjutsuFX "Start" con Kind "Tsukuyomi" (pantalla de la víctima: cielo rojo y luna
-- negra) y ClanFX "TsukuyomiBind" (lo ven todos), en StarterPlayerScripts > MangekyoClient.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local Genjutsu = require(kit:WaitForChild("Genjutsu"))

local ABILITY = "Tsukuyomi" -- ojo de control (MangekyoControl)

local Tsukuyomi = {}

Tsukuyomi.Id = "Tsukuyomi"
Tsukuyomi.TechniqueCategory = "Clan"
Tsukuyomi.MinimumLevel = 60
Tsukuyomi.SortOrder = 1104
Tsukuyomi.NoHandSigns = true
Tsukuyomi.Requirements = {
	Learn = { PlayerAttributes = { MangekyoControl = ABILITY } },
}

Tsukuyomi.Config = {
	DisplayName = "Tsukuyomi",
	TechniqueCategory = "Clan",
	MinimumLevel = 60,
	SortOrder = 1104,

	ChakraCost = 35,
	Cooldown = 30.0,
	CastTime = 0.35,

	Range = 30,
	AimAngle = 12,
	Windup = 0.35,

	Duration = 2.0,
	ImmunityAfter = 4.0, -- s sin que le entre otro control al soltarse (controles encadenados)
	TickInterval = 0.25,
	TickDamage = 1.5,

	EyeStrain = 15,
}

local config = Tsukuyomi.Config

Tsukuyomi.MarkerCastTimeout = 3.0
Tsukuyomi.ProjectileFallbackDelay = 0.5
Tsukuyomi.MinProjectileDelay = 0

local function hasMangekyoAbility(character: Model): boolean
	return Clan.isMangekyoActive(character) and character:GetAttribute("MangekyoControl") == ABILITY
end

function Tsukuyomi.Precheck(character: Model, direction: Vector3): (boolean, string)
	local player = Players:GetPlayerFromCharacter(character)
	if not Clan.isMangekyoActive(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired" })
		return false, "MangekyoRequired"
	end
	-- Mangekyō encendido, pero tu ojo de control es otro
	if not hasMangekyoAbility(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired", Ability = "Tsukuyomi" })
		return false, "MangekyoRequired"
	end
	return Clan.findTarget({ Character = character }, direction, config.Range, config.AimAngle) ~= nil, "NoTarget"
end

function Tsukuyomi.CooldownMultiplier(player: Player): number
	return Clan.eyeStrainCooldownMultiplier(player)
end

return Clan.build(Tsukuyomi, "Uchiha", function(context, direction)
	local caster: Model = context.Character
	local player: Player = context.Player
	local target = Clan.findTarget(context, direction, config.Range, config.AimAngle)
	if not target then
		Genjutsu.fxTo(player, "Fail", { Reason = "NoTarget" })
		return
	end

	-- Aviso: suena el Mangekyō y los ojos brillan (ClanClient). Oírlo es la pista para apartar la mirada
	Clan.fxAll("SharinganWindup", { Character = caster, Target = target.Character, Duration = config.Windup })
	Clan.addEyeStrain(player, config.EyeStrain)

	task.delay(config.Windup, function()
		local humanoid = caster:FindFirstChildOfClass("Humanoid")
		if not caster.Parent or player.Character ~= caster or not humanoid or humanoid.Health <= 0
			or not hasMangekyoAbility(caster)
			or not target.Character.Parent or target.Humanoid.Health <= 0 then
			return
		end
		local sees, reason = Genjutsu.canSee(target.Character, caster)
		if not sees then
			Genjutsu.fxTo(player, "Fail", { Reason = reason })
			return
		end
		local applied = Genjutsu.apply(target, {
			Kind = "Tsukuyomi",
			StatusId = "TsukuyomiBind",
			Duration = config.Duration,
			Attacker = player,
			DamageService = context.DamageService,
			Unbreakable = true,
			Paralyze = true,
			ImmunityAfter = config.ImmunityAfter,
			-- La víctima ve el iris de quien la atrapó
			Visual = { Type = caster:GetAttribute("MangekyoIris") },
		})
		if not applied then
			return
		end
		local victim: Model = target.Character
		Genjutsu.fxTo(player, "Success", { Kind = "Tsukuyomi", Target = victim })
		Clan.fxAll("TsukuyomiBind", { Character = caster, Target = victim, Type = caster:GetAttribute("MangekyoIris") })
		if Players:GetPlayerFromCharacter(victim) then
			Clan.addMastery(player, Clan.Tuning.Mastery.GenjutsuLanded, "Genjutsu")
		end

		-- Tormento: daño mientras siga dentro (cada tick es menor que Genjutsu.BreakDamage)
		task.spawn(function()
			while victim.Parent and victim:GetAttribute("InGenjutsu") == "Tsukuyomi" do
				task.wait(config.TickInterval)
				if victim:GetAttribute("InGenjutsu") ~= "Tsukuyomi" then
					break
				end
				local victimHumanoid = victim:FindFirstChildOfClass("Humanoid")
				if not victimHumanoid or victimHumanoid.Health <= 0 then
					break
				end
				pcall(context.DamageService.Apply, {
					TargetCharacter = victim,
					TargetHumanoid = victimHumanoid,
					TargetPlayer = Players:GetPlayerFromCharacter(victim),
					Attacker = player,
					Damage = config.TickDamage,
					SourceType = "Genjutsu",
					SourceId = "Tsukuyomi",
					IgnoreArmor = true,
				})
			end
		end)
	end)
end)
