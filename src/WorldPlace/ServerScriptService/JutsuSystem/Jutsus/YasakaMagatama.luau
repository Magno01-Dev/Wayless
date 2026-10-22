-- ServerScriptService > JutsuSystem > Jutsus > YasakaMagatama
--
-- Clan Uchiha · Mangekyō · ojo de ataque: Yasaka no Magatama (MangekyoCatalog, común). Técnica del
-- Susanoo: tres magatama de chakra se forman en su mano, se juntan en un shuriken de tres tomoe y
-- salen girando hacia el enemigo. Solo con el Mangekyō activo y la técnica en tu ojo de ataque.
-- Sin sellos (es el Susanoo, no un ninjutsu): el aviso es la formación, que todos ven.
--   1. Marcador "ReleaseStart" (animación del R6): sin el Susanoo activo sale un brazo parcial del
--      Susanoo por tu espalda (EmergeTime) y, en su mano, se forman los magatama (FormTime). Vas
--      más lento mientras tanto (estado MagatamaForming).
--   2. Marcador "ProjectileSpawn" (al soltar, con la mira de ese momento): se lanza. El servidor no
--      deja que salga antes de que termine la formación.
--   3. Fija como objetivo a quien esté cerca de la mira (LockRange, cono LockAngle) y lo persigue
--      girando como mucho TurnRate °/s: corrige, pero no da la vuelta. Un dash lateral a tiempo lo
--      hace pasar de largo (si el objetivo queda a más de LoseLockAngle° de su rumbo, lo pierde).
--      Si el objetivo se sustituye, todos los que lo perseguían pierden el seguimiento y siguen
--      rectos. Sin objetivo, va hacia donde apuntabas.
--      No va recto: sale abierto en arco (CurveBends, hasta CurveAmplitude studs a mitad de camino)
--      y el arco se cierra justo al llegar. El seguimiento lo hace un punto guía ("carrier") que va
--      recto hacia el objetivo; el shuriken va desplazado de él según lo que lleva recorrido.
--   4. Al impactar: Damage, aturdimiento Hitstun y empuje Knockback en su dirección
--      (CombatInternal > ApplyStun / ExternalKnockback), y una explosión que hace SplashDamage a
--      los demás en SplashRadius. Se bloquea de frente (CombatInternal > ExternalBlockHit): daña
--      la guardia y se rompe. Una pared lo hace explotar.
-- Con el Susanoo activo: lo lanza su brazo, SusanooCount shurikens más grandes seguidos (uno cada
-- SusanooInterval), Susanoo* de daño cada uno, y cuesta más chakra (ChakraCostMultiplier).
-- Sube EyeStrain (fatiga ocular) puntos y, con la fatiga ocular alta, recarga más lento (CooldownMultiplier).
-- Visual: ClanFX "YasakaForm", "YasakaThrow", "YasakaPos" (posición cada 0,1 s), "YasakaLost",
-- "YasakaImpact" y "YasakaCancel" (StarterPlayerScripts > MangekyoClient); el brazo y sus
-- animaciones: SusanooRemote "Yasaka" / "YasakaCancel" (SusanooClient).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))
local susanooFolder = ReplicatedStorage:WaitForChild("Susanoo")
local SusanooConfig = require(susanooFolder:WaitForChild("SusanooConfig"))

local ABILITY = "YasakaMagatama" -- ojo de ataque (MangekyoAttack)
local FORMING_STATUS = "MagatamaForming"

local YasakaMagatama = {}

YasakaMagatama.Id = "YasakaMagatama"
YasakaMagatama.TechniqueCategory = "Clan"
YasakaMagatama.MinimumLevel = 60
YasakaMagatama.SortOrder = 1106
-- Es el Susanoo, sin sellos
YasakaMagatama.NoHandSigns = true
-- Solo la aprende quien tiene la técnica en su ojo de ataque (el clan lo añade Clan.build)
YasakaMagatama.Requirements = {
	Learn = { PlayerAttributes = { MangekyoAttack = ABILITY } },
}

YasakaMagatama.Config = {
	DisplayName = "Yasaka no Magatama",
	TechniqueCategory = "Clan",
	MinimumLevel = 60,
	SortOrder = 1106,

	ChakraCost = 30,
	Cooldown = 12.0,
	CastTime = 1.45, -- brazo + carga (la lectura del Sharingan lo usa)

	EmergeTime = 0.35, -- el brazo parcial sale de la espalda (sin el Susanoo activo)
	FormTime = 1.0, -- carga: el chakra se junta y los magatama se forman y se cierran en la mano

	Speed = 110,
	TurnRate = 120,
	Lifetime = 1.6,
	-- Arco: se abre hasta CurveAmplitude studs a mitad de camino (como mucho CurveRatio de la
	-- distancia, para que de cerca no se pase) y se cierra al llegar
	CurveAmplitude = 9,
	SusanooCurveAmplitude = 12,
	CurveRatio = 0.3,
	-- Hacia dónde se abre cada arco (X: hacia el lado del brazo, Y: hacia arriba): el primero hacia
	-- fuera; con el Susanoo, el segundo hacia el otro lado y el tercero por arriba
	CurveBends = {
		Vector2.new(1, 0.45),
		Vector2.new(-1, 0.35),
		Vector2.new(0.15, 1),
	},
	LockRange = 120,
	LockAngle = 22,
	LoseLockAngle = 100,
	Scale = 1.4, -- tamaño del shuriken (malla Magatama a escala 1: unos 2,8 studs de ancho)
	HitRadius = 2.4,
	WorldRadius = 0.6,

	Damage = 18,
	Hitstun = 0.45,
	Knockback = 24,
	GuardDamage = 35,
	SplashRadius = 6,
	SplashDamage = 6,

	SusanooCount = 3,
	SusanooInterval = 0.3,
	SusanooScale = 2.2,
	SusanooDamage = 11,
	SusanooKnockback = 16,
	SusanooSplashDamage = 4,
	SusanooChakraMultiplier = 1.2,

	EyeStrain = 5,

	-- Dónde está la mano del Susanoo al soltar cada uno (respecto al HumanoidRootPart; X hacia el
	-- lado de su brazo): YasakaThrow suelta en el primero; YasakaBarrage en los tres
	ThrowOrigins = {
		Vector3.new(1.3, 2.3, -7.0),
		Vector3.new(6.8, 2.0, -6.0),
		Vector3.new(3.2, 2.0, -7.4),
	},
}

local config = YasakaMagatama.Config

YasakaMagatama.MarkerCastTimeout = 3.0
YasakaMagatama.ProjectileFallbackDelay = 2.2
YasakaMagatama.MinProjectileDelay = 0 -- el mínimo lo pone OnCastMarker (depende del Susanoo)

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

local function isAlive(character: Model?): boolean
	if not character or not character.Parent then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function inSusanoo(character: Model?): boolean
	return character ~= nil and character:GetAttribute("SusanooActive") == true
end

function YasakaMagatama.Precheck(character: Model, _direction: Vector3): (boolean, string)
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
function YasakaMagatama.CooldownMultiplier(player: Player): number
	return Clan.eyeStrainCooldownMultiplier(player)
end

-- Con el Susanoo cuesta más (JutsuServer)
function YasakaMagatama.ChakraCostMultiplier(player: Player): number
	return if inSusanoo(player.Character) then config.SusanooChakraMultiplier else 1
end

local internal: {[string]: BindableFunction} = {}
local function combatInternal(name: string): BindableFunction?
	if not internal[name] then
		local folder = ServerStorage:FindFirstChild("CombatInternal")
		local found = folder and folder:FindFirstChild(name)
		if found and found:IsA("BindableFunction") then
			internal[name] = found
		end
	end
	return internal[name]
end

local function invokeInternal(name: string, ...: any): any
	local fn = combatInternal(name)
	if not fn then
		return nil
	end
	local ok, result = pcall(fn.Invoke, fn, ...)
	return if ok then result else nil
end

local function susanooRemote(): RemoteEvent?
	local remote = susanooFolder:FindFirstChild("SusanooRemote")
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

local function canHit(target: Model): boolean
	return target:GetAttribute("SubstitutionHidden") ~= true
		and target:GetAttribute("CombatImmune") ~= true
		and target:GetAttribute("IsMissionNPC") ~= true
end

local function damage(player: Player, target: Model, amount: number): string?
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local ok, resolution = pcall(DamageService.Apply, {
		TargetCharacter = target,
		TargetHumanoid = humanoid,
		TargetPlayer = Players:GetPlayerFromCharacter(target),
		Attacker = player,
		Damage = amount,
		SourceType = "Jutsu",
		SourceId = ABILITY,
	})
	return if ok and typeof(resolution) == "table" then resolution.Result else nil
end

-- Gira v hacia goal como mucho maxAngle radianes
local function turnToward(v: Vector3, goal: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(v:Dot(goal), -1, 1))
	if angle <= maxAngle or angle < 1e-4 then
		return goal
	end
	local axis = v:Cross(goal)
	if axis.Magnitude < 1e-4 then
		axis = if math.abs(v.Y) < 0.9 then Vector3.yAxis:Cross(v) else Vector3.xAxis:Cross(v)
	end
	return (CFrame.fromAxisAngle(axis.Unit, maxAngle) * v).Unit
end

local function aimPointOf(target: Model): Vector3?
	local root = rootOf(target)
	return if root then root.Position + Vector3.yAxis * 0.5 else nil
end

type Shot = {
	Index: number,
	Remaining: number,
	Origin: Vector3,
	Direction: Vector3,
	Target: Model?,
	AimPoint: Vector3, -- sin objetivo, hacia dónde va
	Curve: Vector3, -- hacia dónde se abre el arco (unitario × amplitud)
	Scale: number,
	Damage: number,
	Knockback: number,
	SplashDamage: number,
}

-- Desvío del arco: perpendicular al rumbo, máximo a mitad de camino y cero al salir y al llegar
-- (MangekyoClient hace la misma cuenta)
local function curveOffset(direction: Vector3, curve: Vector3, progress: number): Vector3
	local lateral = curve - direction * curve:Dot(direction)
	if lateral.Magnitude < 1e-3 then
		return Vector3.zero
	end
	return lateral.Unit * curve.Magnitude * math.sin(math.pi * progress)
end

local function launch(player: Player, caster: Model, shot: Shot)
	local id = HttpService:GenerateGUID(false)
	-- carrier persigue al objetivo en línea recta; position (lo que golpea) va desplazado en arco
	local carrier = shot.Origin
	local position = shot.Origin
	local direction = shot.Direction
	local moving = direction
	local target = shot.Target
	local aimPoint: Vector3? = if target then nil else shot.AimPoint
	local ratio = shot.Scale / config.Scale
	local hitRadius = config.HitRadius * ratio
	local worldRadius = config.WorldRadius * ratio
	local turnRate = math.rad(config.TurnRate)
	local function goalOf(): Vector3?
		if target then
			return aimPointOf(target)
		end
		return aimPoint
	end
	local firstGoal = goalOf()
	-- Recorrido total estimado (lo recorrido + lo que falta): con él se sabe por dónde va el arco
	local traveled = 0
	local total = if firstGoal then math.max((firstGoal - carrier).Magnitude, 1) else config.Speed * config.Lifetime
	local progress = 0
	Clan.fxAll("YasakaThrow", {
		Id = id,
		Character = caster,
		Index = shot.Index,
		Remaining = shot.Remaining,
		Start = position,
		Direction = direction,
		Speed = config.Speed,
		TurnRate = config.TurnRate,
		Target = target,
		AimPoint = aimPoint,
		Curve = shot.Curve,
		Total = total,
		Scale = shot.Scale,
		Lifetime = config.Lifetime,
	})

	local started = os.clock()
	local lastSnapshot = started
	local busy = false
	local done = false
	local connection: RBXScriptConnection

	local function finish(at: Vector3, kind: string, struck: Model?)
		if done then
			return
		end
		done = true
		connection:Disconnect()
		Clan.fxAll("YasakaImpact", {
			Id = id,
			Position = at,
			Direction = moving,
			Kind = kind,
			Scale = shot.Scale,
			Target = struck,
		})
		-- Explosión: daña a los demás de alrededor (no al que recibió el golpe ni si se bloqueó)
		if kind == "Hit" or kind == "World" then
			for _, candidate in Targets.list(caster) do
				local other = candidate.Character
				if other ~= struck and canHit(other)
					and (candidate.Root.Position - at).Magnitude <= config.SplashRadius * ratio then
					task.spawn(damage, player, other, shot.SplashDamage)
				end
			end
		end
	end

	local function loseTarget()
		if target then
			target = nil
			Clan.fxAll("YasakaLost", { Id = id })
		end
	end

	local function impact(struck: Model, at: Vector3)
		if invokeInternal("ExternalBlockHit", player, struck, config.GuardDamage) == "Blocked" then
			finish(at, "Blocked", struck)
			return
		end
		local result = damage(player, struck, shot.Damage)
		if result == "Substituted" then
			finish(at, "Substituted", struck)
			return
		end
		if isAlive(struck) then
			-- Empuje en horizontal (el arco de arriba llega cayendo)
			local push = Vector3.new(moving.X, 0, moving.Z)
			push = if push.Magnitude > 0.1 then push.Unit else direction
			invokeInternal("ApplyStun", struck, config.Hitstun, true)
			invokeInternal("ExternalKnockback", struck, push, shot.Knockback)
		end
		finish(at, "Hit", struck)
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		-- El daño puede ceder el hilo (Downed): un paso cada vez
		if busy or done then
			return
		end
		busy = true
		local now = os.clock()
		if now - started >= config.Lifetime then
			finish(position, "Expire", nil)
			busy = false
			return
		end
		-- Seguimiento: corrige el rumbo hacia el objetivo, sin dar la vuelta
		if target then
			local goal = aimPointOf(target)
			if not isAlive(target) or not goal or target:GetAttribute("SubstitutionHidden") == true then
				loseTarget()
			else
				local toGoal = goal - carrier
				if toGoal.Magnitude > 0.5 then
					local desired = toGoal.Unit
					if math.deg(math.acos(math.clamp(direction:Dot(desired), -1, 1))) > config.LoseLockAngle then
						loseTarget()
					else
						direction = turnToward(direction, desired, turnRate * dt)
					end
				end
			end
		end
		-- El guía avanza recto; el shuriken va desplazado en arco según lo recorrido
		local step = config.Speed * dt
		local nextCarrier = carrier + direction * step
		traveled += step
		local goal = goalOf()
		if goal then
			total = traveled + (goal - nextCarrier).Magnitude
		end
		progress = math.max(progress, math.clamp(traveled / math.max(total, 1), 0, 1))
		local nextPosition = nextCarrier + curveOffset(direction, shot.Curve, progress)
		local path = nextPosition - position
		local pathLength = path.Magnitude
		if pathLength > 1e-3 then
			moving = path.Unit
		end
		local substeps = math.max(1, math.ceil(pathLength / 3))
		local length = pathLength / substeps
		for _ = 1, substeps do
			local displacement = moving * length
			local wall = Targets.castWorld(position, displacement, { caster }, worldRadius)
			local reach = if wall then math.clamp((wall.Position - position):Dot(moving), 0, length) else length
			local nearest: Model? = nil
			local nearestAlong = math.huge
			for _, candidate in Targets.list(caster) do
				local other = candidate.Character
				if canHit(other) then
					local bottom, top = Targets.bodySegment(candidate.Root.Position)
					local distance, point = Targets.segmentDistance(position, position + moving * reach, bottom, top)
					local along = (point - position):Dot(moving)
					if distance <= hitRadius and along < nearestAlong then
						nearest, nearestAlong = other, along
					end
				end
			end
			if nearest then
				impact(nearest, position + moving * math.max(nearestAlong, 0))
				busy = false
				return
			end
			if wall then
				-- Contra el muro de Kagutsuchi se consume (sin explosión)
				finish(wall.Position, if Targets.consumedBy(wall, wall.Position, moving) then "Consumed" else "World", nil)
				busy = false
				return
			end
			position += displacement
		end
		carrier = nextCarrier
		position = nextPosition
		if now - lastSnapshot >= 0.1 then
			lastSnapshot = now
			Clan.fxAll("YasakaPos", {
				Id = id,
				Carrier = carrier,
				Direction = direction,
				Traveled = traveled,
				Progress = progress,
			})
		end
		busy = false
	end)
end

local function stopForming(caster: Model)
	if caster.Parent then
		StatusEffectService.Remove(caster, FORMING_STATUS, "Ended")
	end
end

local function cancel(caster: Model)
	stopForming(caster)
	Clan.fxAll("YasakaCancel", { Character = caster })
	local remote = susanooRemote()
	if remote then
		remote:FireAllClients("YasakaCancel", caster)
	end
end

local function throwAll(player: Player, caster: Model, direction: Vector3, susanoo: boolean, context: any)
	local root = rootOf(caster)
	local eye = eyeOf(caster)
	if not root or not eye then
		cancel(caster)
		return
	end
	local aim = direction.Unit
	local aimHit = Targets.castWorld(eye, aim * config.LockRange, { caster })
	local aimPoint = if aimHit then aimHit.Position else eye + aim * config.LockRange
	local locked = Clan.findTarget(context, aim, config.LockRange, config.LockAngle)
	local target: Model? = if locked then locked.Character else nil
	local count = if susanoo then config.SusanooCount else 1
	local side = SusanooConfig.Sides[SusanooConfig.Side]
	local armSign = side.ArmSign or 1
	local right = aim:Cross(Vector3.yAxis)
	right = if right.Magnitude > 0.01 then right.Unit else root.CFrame.RightVector
	Clan.addEyeStrain(player, config.EyeStrain)

	for index = 1, count do
		if index > 1 then
			task.wait(config.SusanooInterval)
		end
		local current = rootOf(caster)
		if player.Character ~= caster or not isAlive(caster) or not current
			or caster:GetAttribute("IsStunned") == true or caster:GetAttribute("IsDowned") == true
			or not hasMangekyoAbility(caster) then
			cancel(caster)
			return
		end
		local o = config.ThrowOrigins[if susanoo then index else 1]
		local origin = (current.CFrame * CFrame.new(o.X * armSign, o.Y, o.Z)).Position
		-- Un objetivo que se sustituyó no se vuelve a fijar
		if target and (not isAlive(target) or target:GetAttribute("SubstitutionHidden") == true) then
			target = nil
		end
		local goal = if target then aimPointOf(target) else nil
		local toward = (goal or aimPoint) - origin
		local launchDirection = if toward.Magnitude > 1 then toward.Unit else aim
		local bend = config.CurveBends[if susanoo then index else 1] or config.CurveBends[1]
		local bendVector = right * (bend.X * armSign) + Vector3.yAxis * bend.Y
		local amplitude = math.min(if susanoo then config.SusanooCurveAmplitude else config.CurveAmplitude,
			toward.Magnitude * config.CurveRatio)
		launch(player, caster, {
			Index = index,
			Remaining = count - index,
			Origin = origin,
			Direction = launchDirection,
			Target = target,
			AimPoint = aimPoint,
			Curve = bendVector.Unit * amplitude,
			Scale = if susanoo then config.SusanooScale else config.Scale,
			Damage = if susanoo then config.SusanooDamage else config.Damage,
			Knockback = if susanoo then config.SusanooKnockback else config.Knockback,
			SplashDamage = if susanoo then config.SusanooSplashDamage else config.SplashDamage,
		})
	end
	stopForming(caster)
end

local built = Clan.build(YasakaMagatama, "Uchiha", function(context, direction)
	local caster: Model = context.Character
	local player: Player = context.Player
	context.YasakaThrown = true
	if not hasMangekyoAbility(caster) then
		cancel(caster)
		return
	end
	task.spawn(throwAll, player, caster, direction, context.YasakaSusanoo == true, context)
end)

local baseOnCastMarker = built.OnCastMarker

function built.OnCastStarted(context: any)
	context.YasakaStartedAt = os.clock()
	context.YasakaSusanoo = inSusanoo(context.Character)
end

-- Sale el brazo (sin el Susanoo activo) y se forman los magatama en su mano
local function startForming(context: any)
	if context.YasakaFormAt then
		return
	end
	context.YasakaFormAt = os.clock()
	local caster: Model = context.Character
	local susanoo = context.YasakaSusanoo == true
	local count = if susanoo then config.SusanooCount else 1
	Clan.applyStatus(caster, FORMING_STATUS, { Duration = 2.6, SourcePlayer = context.Player })
	Clan.fxAll("YasakaForm", {
		Character = caster,
		Susanoo = susanoo,
		Count = count,
		Delay = if susanoo then 0 else config.EmergeTime,
		FormTime = config.FormTime,
		Scale = if susanoo then config.SusanooScale else config.Scale,
	})
	local remote = susanooRemote()
	if remote then
		remote:FireAllClients("Yasaka", caster, {
			Partial = not susanoo,
			Animation = if susanoo then "YasakaBarrage" else "YasakaThrow",
			Duration = if susanoo then 2.6 else 2.5,
			Fade = config.EmergeTime, -- el brazo parcial sale a la vez que empieza la carga
		})
	end
end

function built.OnCastMarker(context: any, semanticMarker: string, source: string, markerPayload: any?)
	if semanticMarker == "ReleaseStart" then
		startForming(context)
		return
	end
	if semanticMarker ~= "ProjectileSpawn" or context.YasakaScheduled then
		return
	end
	context.YasakaScheduled = true
	startForming(context)
	-- No antes de que el brazo salga y los magatama se formen (margen de latencia)
	local windup = config.FormTime + (if context.YasakaSusanoo then 0 else config.EmergeTime)
	local wait = context.YasakaFormAt + windup * 0.85 - os.clock()
	if wait > 0 then
		task.delay(wait, baseOnCastMarker, context, semanticMarker, source, markerPayload)
	else
		baseOnCastMarker(context, semanticMarker, source, markerPayload)
	end
end

-- Se cortó antes de lanzar: fuera el brazo y los magatama
function built.OnCastEnded(context: any, _reason: string)
	if context.YasakaFormAt and not context.YasakaThrown and not context.YasakaScheduled then
		cancel(context.Character)
	end
end

return built
