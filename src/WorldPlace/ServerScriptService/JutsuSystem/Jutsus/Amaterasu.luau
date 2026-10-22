-- ServerScriptService > JutsuSystem > Jutsus > Amaterasu
--
-- Clan Uchiha · Mangekyō · ojo de ataque: Amaterasu (MangekyoCatalog).
-- Solo con el Mangekyō activo (doble toque de Z) y Amaterasu en tu ojo de ataque. Se lanza siempre,
-- haya o no alguien:
--   · Si hay alguien cerca de la mira (≤ Range studs, cono AimAngle), la mirada lo sigue durante
--     Windup: tus ojos brillan, suena el Mangekyō y bajo él va un círculo de humo negro que se
--     cierra al final (el aviso). Al acabar prende SOBRE él: caminar o correr no lo salva. Solo
--     lo esquiva quien en los últimos DodgeWindow s se desplazó ≥ DodgeDistance studs (un dash
--     a tiempo; un dash temprano no sirve porque la mirada lo sigue), quien se sustituye (arde
--     el tronco) o quien queda tras una pared o a más de Range × 1,15.
--     Si le da, arde en llamas negras BurnDuration s: ImpactDamage al prender y TickDamage cada
--     TickInterval. Nada que apague el fuego normal lo apaga (no es Burning). Donde prende (o
--     donde estaba al esquivarlo) queda un charco de fuego negro.
--   · Si se sustituye (antes o durante la quemadura), arde su tronco y el charco queda allí.
--   · Si no había nadie, o falla por otra razón (se cubrió, se alejó), el fuego prende donde
--     apuntabas (lo primero que toca la mira, hasta Range) y deja el área ardiendo.
-- El charco dura PuddleDuration s y prende a quien lo pise (menos a ti).
-- Sube EyeStrain (fatiga ocular) puntos (Clan.addEyeStrain) y, con la fatiga ocular alta, recarga más lento
-- (CooldownMultiplier, lo aplica JutsuServer).
-- Las llamas, el charco y el tronco que arde son los de TechniqueKit > BlackFlames (compartidos
-- con las demás llamas negras; los ticks de daño están en BlackFlames.Tuning).
-- Visual: ClanFX "AmaterasuWindup" / "AmaterasuPuddle" y el atributo del personaje
-- AmaterasuBurning + etiqueta "AmaterasuBurning" (también NPCs y el tronco;
-- StarterPlayerScripts > MangekyoClient). El aviso de los ojos es "SharinganWindup" (ClanClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local Genjutsu = require(kit:WaitForChild("Genjutsu"))
local BlackFlames = require(kit:WaitForChild("BlackFlames"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))

local ABILITY = "Amaterasu" -- ojo de ataque (MangekyoAttack)

local Amaterasu = {}

Amaterasu.Id = "Amaterasu"
Amaterasu.TechniqueCategory = "Clan"
Amaterasu.MinimumLevel = 60
Amaterasu.SortOrder = 1103
-- Con la mirada, sin sellos
Amaterasu.NoHandSigns = true
-- Solo la aprende quien tiene Amaterasu en su ojo de ataque (el clan lo añade Clan.build)
Amaterasu.Requirements = {
	Learn = { PlayerAttributes = { MangekyoAttack = ABILITY } },
}

Amaterasu.Config = {
	DisplayName = "Amaterasu",
	TechniqueCategory = "Clan",
	MinimumLevel = 60,
	SortOrder = 1103,

	ChakraCost = 30,
	Cooldown = 16.0,
	CastTime = 0.6,

	Range = 150,
	AimAngle = 25, -- asistencia: a quien esté así de cerca de la mira le llega la llama
	Windup = 0.6,
	-- Esquivar: desplazarse esto en la ventana final (caminar 16 y correr 44 studs/s no llegan;
	-- un dash a 75 sí)
	DodgeWindow = 0.2,
	DodgeDistance = 10,

	ImpactDamage = 8,
	BurnDuration = 6.0, -- daño por tick: BlackFlames.Tuning

	PuddleRadius = 3.5,
	PuddleDuration = 6.0,
	PuddleBurn = 3.0, -- s de llamas al pisar el charco (se renuevan mientras sigas dentro)

	EyeStrain = 10,
}

local config = Amaterasu.Config

Amaterasu.MarkerCastTimeout = 3.0
Amaterasu.ProjectileFallbackDelay = 0.5
Amaterasu.MinProjectileDelay = 0

local function hasMangekyoAbility(character: Model): boolean
	return Clan.isMangekyoActive(character) and character:GetAttribute("MangekyoAttack") == ABILITY
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function eyeOf(character: Model): Vector3?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = rootOf(character)
	return if root then root.Position + Vector3.yAxis * 1.5 else nil
end

-- Solo hace falta el Mangekyō: sin nadie en la mira también se lanza (arde donde apuntas)
function Amaterasu.Precheck(character: Model, _direction: Vector3): (boolean, string)
	local player = Players:GetPlayerFromCharacter(character)
	if not Clan.isMangekyoActive(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired" })
		return false, "MangekyoRequired"
	end
	-- Mangekyō encendido, pero tu ojo de ataque es otro
	if not hasMangekyoAbility(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired", Ability = "Amaterasu" })
		return false, "MangekyoRequired"
	end
	return true, "OK"
end

-- Ceguera alta: recarga más lenta (JutsuServer)
function Amaterasu.CooldownMultiplier(player: Player): number
	return Clan.eyeStrainCooldownMultiplier(player)
end

-- Llamas negras (TechniqueKit > BlackFlames) con los valores de Amaterasu ---------------------

local PUDDLE = {
	Radius = config.PuddleRadius,
	Duration = config.PuddleDuration,
	Burn = config.PuddleBurn,
	SourceId = "Amaterasu",
}

local function spawnPuddle(position: Vector3, attacker: Player?, ignore: Instance?)
	BlackFlames.spawnPuddle(position, attacker, ignore, PUDDLE)
end

local function burnLog(victim: Model, near: Vector3, attacker: Player?)
	BlackFlames.burnLog(victim, near, attacker, PUDDLE)
end

local function ignite(target: Model, attacker: Player?, duration: number, impact: number?): string?
	return BlackFlames.ignite(target, attacker, duration, impact, "Amaterasu")
end

-- Ejecución ----------------------------------------------------------------------------------

-- Lo primero que toca la mira (hasta Range); si no toca nada, el punto a Range
local function aimPoint(caster: Model, direction: Vector3): Vector3?
	local eye = eyeOf(caster)
	if not eye then
		return nil
	end
	local hit = Targets.castWorld(eye, direction.Unit * config.Range, { caster })
	return if hit then hit.Position else eye + direction.Unit * config.Range
end

return Clan.build(Amaterasu, "Uchiha", function(context, direction)
	local caster: Model = context.Character
	local player: Player = context.Player
	local target = Clan.findTarget(context, direction, config.Range, config.AimAngle)
	local aimedAt = aimPoint(caster, direction)

	-- Aviso: ojos (ClanClient) y, si hay víctima, humo negro sobre ella (MangekyoClient)
	Clan.fxAll("SharinganWindup", { Character = caster, Target = target and target.Character, Duration = config.Windup })
	if target then
		Clan.fxAll("AmaterasuWindup", {
			Character = caster,
			Target = target.Character,
			Duration = config.Windup,
			DodgeWindow = config.DodgeWindow,
		})
	end
	Clan.addEyeStrain(player, config.EyeStrain)

	local victim: Model? = target and target.Character
	local lastSeen = target and target.Root.Position

	-- Posiciones de la víctima durante la mirada (para ver si esquivó en la ventana final)
	local history: {{ At: number, Position: Vector3 }} = {}
	if victim then
		task.spawn(function()
			local started = os.clock()
			while os.clock() - started < config.Windup + 0.1 and victim.Parent do
				local root = rootOf(victim)
				if root then
					table.insert(history, { At = os.clock(), Position = root.Position })
				end
				task.wait()
			end
		end)
	end
	local function positionAt(time: number): Vector3?
		local best = nil
		for _, sample in history do
			if sample.At <= time then
				best = sample.Position
			end
		end
		return best or (history[1] and history[1].Position)
	end

	task.delay(config.Windup, function()
		local humanoid = caster:FindFirstChildOfClass("Humanoid")
		if not caster.Parent or player.Character ~= caster or not humanoid or humanoid.Health <= 0
			or not hasMangekyoAbility(caster) then
			return
		end

		if victim then
			local victimRoot = rootOf(victim)
			if victimRoot and victim:GetAttribute("SubstitutionHidden") ~= true then
				lastSeen = victimRoot.Position
			end
			-- Se sustituyó durante la mirada: arde su tronco
			if victim:GetAttribute("SubstitutionHidden") == true then
				burnLog(victim, lastSeen :: Vector3, player)
				Genjutsu.fxTo(player, "Fail", { Reason = "Substituted" })
				return
			end
			local victimHumanoid = victim:FindFirstChildOfClass("Humanoid")
			local eye, victimEye = eyeOf(caster), eyeOf(victim)
			local inSight = victim.Parent ~= nil and victimHumanoid ~= nil and victimHumanoid.Health > 0
				and eye ~= nil and victimEye ~= nil
				and (victimEye - eye).Magnitude <= config.Range * 1.15
				and Targets.castWorld(eye, victimEye - eye, { caster, victim }) == nil
			-- ¿Esquivó? Cuánto se desplazó en la ventana final
			local now = os.clock()
			local before = positionAt(now - config.DodgeWindow)
			local current = victimRoot and victimRoot.Position
			local dodged = false
			if before and current then
				local moved = current - before
				dodged = Vector3.new(moved.X, 0, moved.Z).Magnitude >= config.DodgeDistance
			end
			if inSight and dodged then
				-- La llama prende donde estaba al empezar a esquivar
				spawnPuddle(before :: Vector3, player, victim)
				Genjutsu.fxTo(player, "Fail", { Reason = "Dodged" })
				return
			end
			if inSight then
				local result = ignite(victim, player, config.BurnDuration, config.ImpactDamage)
				if result == "Substituted" then
					burnLog(victim, lastSeen :: Vector3, player)
					Genjutsu.fxTo(player, "Fail", { Reason = "Substituted" })
				else
					spawnPuddle(lastSeen :: Vector3, player, victim)
					Genjutsu.fxTo(player, "Success", { Kind = "Amaterasu", Target = victim })
				end
				return
			end
		end

		-- Sin nadie, o falló (se cubrió, se alejó): arde donde apuntabas
		if aimedAt then
			spawnPuddle(aimedAt, player, nil)
		end
	end)
end)
