-- ServerScriptService > JutsuSystem > Jutsus > EntonSpear
--
-- Clan Uchiha · Mangekyō · ojo de ataque: Enton: Black Spear (MangekyoCatalog, común).
-- Lo contrario de Amaterasu: un tiro de habilidad sin asistencia de puntería, muy avisado. Solo con
-- el Mangekyō activo y la lanza en tu ojo de ataque. Moldear las llamas negras es ninjutsu:
--   1. Sellos (4, pausados; con el Mangekyō van más rápido). Si te golpean, se cortan como cualquier jutsu.
--   2. La lanza se forma en la mano (FormTime, marcador "ReleaseStart" de la animación): todos la
--      ven y vas más lento (estado EntonSpearForming).
--   3. Sale al soltar (marcador "ProjectileSpawn") hacia donde apuntas en ese momento.
-- Con el Susanoo activo no hay sellos: la forma el brazo del Susanoo (SusanooFormTime, más lento),
-- sale de su mano, más grande (SusanooScale en tamaño y anchura del golpe), con el mismo daño y
-- cuesta más chakra (ChakraCostMultiplier).
-- El servidor no deja que salga antes de tiempo (sellos + formación), aunque el cliente lo pida.
-- En vuelo:
--   · Recta y muy rápida (Speed, hasta Range); atraviesa hasta Pierce enemigos y en el último se queda.
--   · A cada uno: ImpactDamage y llamas negras BurnDuration s (TechniqueKit > BlackFlames).
--   · Se bloquea de frente (360° con el Mangekyō; CombatInternal > ExternalBlockHit): daña la
--     guardia, no quema y la lanza se rompe. Si rompe la guardia, entra igual.
--   · Si se sustituye, arde su tronco (con su charco) y la lanza sigue.
--   · Si toca el suelo o una pared se clava y deja un charco pequeño (Puddle*).
-- Sube EyeStrain (fatiga ocular) puntos y, con la fatiga ocular alta, recarga más lento (CooldownMultiplier).
-- Visual: ClanFX "EntonSpearForm" (la lanza en la mano), "EntonSpearCancel" (se cortó antes de
-- lanzarla), "EntonSpear" (cada cliente dibuja el vuelo) y "EntonSpearEnd" (StarterPlayerScripts >
-- MangekyoClient). Animaciones: JutsuController (R6, EntonSpearThrow) y SusanooRemote "Throw"
-- (SusanooClient, SusanooThrow).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local BlackFlames = require(kit:WaitForChild("BlackFlames"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))
local susanooFolder = ReplicatedStorage:WaitForChild("Susanoo")
local SusanooConfig = require(susanooFolder:WaitForChild("SusanooConfig"))

local ABILITY = "EntonSpear" -- ojo de ataque (MangekyoAttack)
local FORMING_STATUS = "EntonSpearForming"

local EntonSpear = {}

EntonSpear.Id = "EntonSpear"
EntonSpear.TechniqueCategory = "Clan"
EntonSpear.MinimumLevel = 60
EntonSpear.SortOrder = 1105
-- Solo la aprende quien tiene la lanza en su ojo de ataque (el clan lo añade Clan.build)
EntonSpear.Requirements = {
	Learn = { PlayerAttributes = { MangekyoAttack = ABILITY } },
}

EntonSpear.Config = {
	DisplayName = "Enton: Black Spear",
	TechniqueCategory = "Clan",
	MinimumLevel = 60,
	SortOrder = 1105,

	ChakraCost = 25,
	Cooldown = 10.0,
	CastTime = 1.5, -- sellos + formar la lanza (la lectura del Sharingan lo usa)

	-- Tiempos mínimos que pone el servidor
	SealTime = 0.75, -- 4 sellos con el Mangekyō (≈ 0.92 s; margen de latencia)
	FormTime = 0.45, -- la lanza en la mano antes de poder lanzarla
	SusanooFormTime = 0.7,
	SusanooChakraMultiplier = 1.2, -- 25 → 30 con el Susanoo

	Speed = 200,
	Range = 130,
	HitRadius = 1.6, -- distancia al eje del cuerpo que cuenta como impacto
	WorldRadius = 0.35, -- grosor contra el mundo (fino: no se clava en cualquier esquina)
	Pierce = 2,

	ImpactDamage = 14,
	BurnDuration = 4.0,
	GuardDamage = 30,

	PuddleRadius = 2.5,
	PuddleDuration = 3.0,
	PuddleBurn = 2.0,

	SusanooScale = 2.2,
	EyeStrain = 6,

	-- De dónde sale (respecto al HumanoidRootPart): la mano al soltar en cada animación
	ThrowOrigin = Vector3.new(1.3, 0.95, -1.7), -- R6, EntonSpearThrow
	SusanooThrowOrigin = Vector3.new(3.4, 3.5, -6.6), -- SusanooThrow; X hacia el lado de su brazo
}

local config = EntonSpear.Config

EntonSpear.MarkerCastTimeout = 4.0
EntonSpear.ProjectileFallbackDelay = 3.0
EntonSpear.MinProjectileDelay = 0 -- el mínimo lo pone OnCastMarker (depende del Susanoo)

local PUDDLE = {
	Radius = config.PuddleRadius,
	Duration = config.PuddleDuration,
	Burn = config.PuddleBurn,
	SourceId = ABILITY,
}

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

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function inSusanoo(character: Model?): boolean
	return character ~= nil and character:GetAttribute("SusanooActive") == true
end

function EntonSpear.Precheck(character: Model, _direction: Vector3): (boolean, string)
	local player = Players:GetPlayerFromCharacter(character)
	if not Clan.isMangekyoActive(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired" })
		return false, "MangekyoRequired"
	end
	-- Mangekyō encendido, pero tu ojo de ataque es otro
	if not hasMangekyoAbility(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired", Ability = config.DisplayName })
		return false, "MangekyoRequired"
	end
	return true, "OK"
end

-- Ceguera alta: recarga más lenta (JutsuServer)
function EntonSpear.CooldownMultiplier(player: Player): number
	return Clan.eyeStrainCooldownMultiplier(player)
end

-- Con el Susanoo cuesta más (JutsuServer)
function EntonSpear.ChakraCostMultiplier(player: Player): number
	return if inSusanoo(player.Character) then config.SusanooChakraMultiplier else 1
end

local blockHit: BindableFunction? = nil
local function externalBlockHit(): BindableFunction?
	if not blockHit then
		local internal = ServerStorage:FindFirstChild("CombatInternal")
		local found = internal and internal:FindFirstChild("ExternalBlockHit")
		blockHit = if found and found:IsA("BindableFunction") then found else nil
	end
	return blockHit
end

-- Impacto en un cuerpo: "Blocked" (la lanza se rompe), "Substituted" (arde el tronco y sigue) o "Hit"
local function strike(player: Player, target: Model, targetRoot: BasePart): string
	local block = externalBlockHit()
	if block then
		local ok, result = pcall(function()
			return block:Invoke(player, target, config.GuardDamage)
		end)
		if ok and result == "Blocked" then
			return "Blocked"
		end
	end
	local result = BlackFlames.ignite(target, player, config.BurnDuration, config.ImpactDamage, ABILITY)
	if result == "Substituted" then
		BlackFlames.burnLog(target, targetRoot.Position, player, PUDDLE)
		return "Substituted"
	end
	return "Hit"
end

local function canHit(target: Model): boolean
	return target:GetAttribute("SubstitutionHidden") ~= true
		and target:GetAttribute("CombatImmune") ~= true
		and target:GetAttribute("IsMissionNPC") ~= true
end

local function stopForming(caster: Model)
	if caster.Parent then
		StatusEffectService.Remove(caster, FORMING_STATUS, "Ended")
	end
end

local function throw(player: Player, caster: Model, direction: Vector3, susanoo: boolean)
	local root = rootOf(caster)
	local eye = eyeOf(caster)
	if not root or not eye then
		return
	end
	local scale = if susanoo then config.SusanooScale else 1

	-- Sale de la mano y va hacia lo que tocaba la mira
	local aim = direction.Unit
	local aimHit = Targets.castWorld(eye, aim * config.Range, { caster })
	local aimPoint = if aimHit then aimHit.Position else eye + aim * config.Range
	local origin = config.ThrowOrigin
	if susanoo then
		local side = SusanooConfig.Sides[SusanooConfig.Side]
		local o = config.SusanooThrowOrigin
		origin = Vector3.new(o.X * (side.ArmSign or 1), o.Y, o.Z)
	end
	local start = (root.CFrame * CFrame.new(origin)).Position
	local toAim = aimPoint - start
	local flight = if toAim.Magnitude > 1 and toAim.Unit:Dot(aim) > 0.5 then toAim.Unit else aim

	local id = HttpService:GenerateGUID(false)
	Clan.fxAll("EntonSpear", {
		Id = id,
		Character = caster,
		Start = start,
		Direction = flight,
		Speed = config.Speed,
		Range = config.Range,
		Scale = scale,
	})
	Clan.addEyeStrain(player, config.EyeStrain)

	local hitRadius = config.HitRadius * scale
	local worldRadius = config.WorldRadius * scale
	local position = start
	local travelled = 0
	local hits = 0
	local struck: {[Model]: boolean} = {}
	local busy = false
	local done = false
	local connection: RBXScriptConnection

	local function finish(at: Vector3, kind: string)
		if done then
			return
		end
		done = true
		connection:Disconnect()
		Clan.fxAll("EntonSpearEnd", { Id = id, Position = at, Direction = flight, Kind = kind, Scale = scale })
		if kind == "World" then
			BlackFlames.spawnPuddle(at, player, nil, PUDDLE)
		end
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		-- El daño puede ceder el hilo (Downed): un paso cada vez
		if busy or done then
			return
		end
		busy = true
		if player.Character ~= caster or not isAlive(caster) then
			finish(position, "Expire")
			busy = false
			return
		end
		local step = math.min(config.Speed * dt, config.Range - travelled)
		local substeps = math.max(1, math.ceil(step / 4))
		local length = step / substeps
		for _ = 1, substeps do
			local displacement = flight * length
			local wall = Targets.castWorld(position, displacement, { caster }, worldRadius)
			local reach = if wall then math.clamp((wall.Position - position):Dot(flight), 0, length) else length
			-- Cuerpos en el tramo (antes de la pared), del más cercano al más lejano
			local found = {}
			for _, candidate in Targets.list(caster) do
				local target = candidate.Character
				if not struck[target] and canHit(target) then
					local bottom, top = Targets.bodySegment(candidate.Root.Position)
					local distance, point = Targets.segmentDistance(position, position + flight * reach, bottom, top)
					if distance <= hitRadius then
						table.insert(found, { Target = target, Root = candidate.Root, Along = (point - position):Dot(flight) })
					end
				end
			end
			table.sort(found, function(a, b)
				return a.Along < b.Along
			end)
			for _, entry in found do
				struck[entry.Target] = true
				local at = position + flight * entry.Along
				local result = strike(player, entry.Target, entry.Root)
				if result == "Blocked" then
					finish(at, "Blocked")
					busy = false
					return
				elseif result == "Hit" then
					hits += 1
					if hits >= config.Pierce then
						finish(at, "Target")
						busy = false
						return
					end
				end
			end
			if wall then
				-- Contra el muro de Kagutsuchi se consume (sin clavarse ni charco)
				finish(wall.Position, if Targets.consumedBy(wall, wall.Position, flight) then "Consumed" else "World")
				busy = false
				return
			end
			position += displacement
			travelled += length
		end
		if travelled >= config.Range - 0.01 then
			finish(position, "Expire")
		end
		busy = false
	end)
end

local built = Clan.build(EntonSpear, "Uchiha", function(context, direction)
	local caster: Model = context.Character
	local player: Player = context.Player
	context.EntonThrown = true
	stopForming(caster)
	if not hasMangekyoAbility(caster) then
		Clan.fxAll("EntonSpearCancel", { Character = caster })
		return
	end
	throw(player, caster, direction, context.EntonSusanoo == true)
end)

local baseOnCastMarker = built.OnCastMarker

function built.OnCastStarted(context: any)
	context.EntonStartedAt = os.clock()
	context.EntonSusanoo = inSusanoo(context.Character)
end

-- Empieza a formarse la lanza en la mano (fin de los sellos)
local function startForming(context: any)
	if context.EntonFormAt then
		return
	end
	context.EntonFormAt = os.clock()
	local caster: Model = context.Character
	local susanoo = context.EntonSusanoo == true
	Clan.applyStatus(caster, FORMING_STATUS, { Duration = 2.0, SourcePlayer = context.Player })
	Clan.fxAll("EntonSpearForm", {
		Character = caster,
		Susanoo = susanoo,
		FormTime = if susanoo then config.SusanooFormTime else config.FormTime,
		Duration = 2.5,
	})
	if susanoo then
		local remote = susanooFolder:FindFirstChild("SusanooRemote")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireAllClients("Throw", caster)
		end
	end
end

function built.OnCastMarker(context: any, semanticMarker: string, source: string, markerPayload: any?)
	if semanticMarker == "ReleaseStart" then
		startForming(context)
		return
	end
	if semanticMarker ~= "ProjectileSpawn" or context.EntonSpawnScheduled then
		return
	end
	context.EntonSpawnScheduled = true
	startForming(context)
	-- No antes de los sellos y de que la lanza termine de formarse (margen de latencia)
	local susanoo = context.EntonSusanoo == true
	local formTime = if susanoo then config.SusanooFormTime else config.FormTime
	local earliest = context.EntonFormAt + formTime * 0.85
	if not susanoo then
		earliest = math.max(earliest, (context.EntonStartedAt or 0) + config.SealTime + formTime * 0.85)
	end
	local wait = earliest - os.clock()
	if wait > 0 then
		task.delay(wait, baseOnCastMarker, context, semanticMarker, source, markerPayload)
	else
		baseOnCastMarker(context, semanticMarker, source, markerPayload)
	end
end

-- Se cortó antes de lanzarla (golpe en los sellos, aturdido...): fuera la lanza de la mano
function built.OnCastEnded(context: any, _reason: string)
	if context.EntonFormAt and not context.EntonThrown and not context.EntonSpawnScheduled then
		stopForming(context.Character)
		Clan.fxAll("EntonSpearCancel", { Character = context.Character })
	end
end

return built
