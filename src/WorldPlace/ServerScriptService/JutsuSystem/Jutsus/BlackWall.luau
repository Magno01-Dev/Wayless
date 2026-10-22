-- ServerScriptService > JutsuSystem > Jutsus > BlackWall
--
-- Clan Uchiha · Mangêkyō · ojo de control: Kagutsuchi: Black Wall (MangekyoCatalog, común). Las
-- llamas negras moldeadas en un muro que controla el espacio. Solo con el Mangekyō activo y el muro
-- en tu ojo de control. Moldear llamas negras es ninjutsu:
--   1. Sellos (3). Con el Susanoo activo no hay sellos, pero hay un windup más largo (SusanooWindup)
--      con llamas negras en el que lo lanza.
--   2. Al acabar, se marca en el suelo donde apuntas (hasta PlaceRange) una línea de brasas
--      (Telegraph s) y las llamas brotan: un arco de Width studs cóncavo hacia ti (radio Curve), que
--      sigue el suelo y dura Duration s.
-- Medidas pensadas contra TODO el movimiento (dash 22 studs, air dash con inercia de 105 studs/s,
-- doble salto ~18 studs de alto, air dash hacia arriba ~50-65): rodearlo cuesta un dash y por
-- encima no se pasa, porque cuenta como cruzar todo lo que haya hasta CrossHeight (la columna de
-- humo negro marca hasta dónde llega).
-- Qué hace:
--   · Bloquea proyectiles y jutsus y corta la línea de visión (Amaterasu, Tsukuyomi, genjutsus):
--     cada tramo tiene una barrera invisible (Workspace > MangekyoBarriers, atributo ProjectileBlocker)
--     en su propio grupo de colisión FlameBarrier, que no choca con nada: ni los personajes ni los
--     rayos normales (suelo, paredes, tree jump…) la ven. Solo la miran los proyectiles y las líneas
--     de visión, a propósito: Throwables > Targets.castBarrier / withBarrier (castWorld ya la incluye;
--     Fireball, Hosenka, Water/Air Bullet, Wind Blade, Lightning Senbon y Stone Shot la usan en su
--     rayo de mundo).
--   · Quien la cruza (menos quien lo lanzó y su squad): CrossDamage y llamas negras BurnDuration s
--     (TechniqueKit > BlackFlames), vuelve a su lado, aturdido RepelStun s (corta la inercia del
--     air dash) y empujado RepelSpeed. Quien se queda dentro de las llamas arde.
-- Sube EyeStrain (fatiga ocular) puntos y, con la fatiga ocular alta, recarga más lento (CooldownMultiplier).
-- Visual: ClanFX "BlackWallWindup", "BlackWallForm" (cada cliente dibuja el muro con muchas llamas
-- pequeñas) y "BlackWallRepel" (StarterPlayerScripts > MangekyoClient).

local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local BlackFlames = require(kit:WaitForChild("BlackFlames"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))

local ABILITY = "BlackWall" -- ojo de control (MangekyoControl)
local BARRIER_GROUP = "FlameBarrier" -- el mismo nombre en Throwables > Targets

local BlackWall = {}

BlackWall.Id = "BlackWall"
BlackWall.TechniqueCategory = "Clan"
BlackWall.MinimumLevel = 60
BlackWall.SortOrder = 1107
-- Solo la aprende quien tiene el muro en su ojo de control (el clan lo añade Clan.build)
BlackWall.Requirements = {
	Learn = { PlayerAttributes = { MangekyoControl = ABILITY } },
}

BlackWall.Config = {
	DisplayName = "Kagutsuchi: Black Wall",
	TechniqueCategory = "Clan",
	MinimumLevel = 60,
	SortOrder = 1107,

	ChakraCost = 30,
	Cooldown = 18.0,
	CastTime = 1.3, -- sellos + línea de brasas (la lectura del Sharingan lo usa)

	SealTime = 0.55, -- 3 sellos con el Mangekyō (margen de latencia)
	SusanooWindup = 0.6, -- sin sellos, pero se carga más
	Telegraph = 0.6, -- la línea de brasas antes de que brote (corriendo se recorren ~26 studs)
	RiseTime = 0.35, -- lo que tardan las llamas en subir (solo visual: bloquea desde que brota)

	PlaceRange = 50,
	MinDistance = 8, -- no pegado a ti
	SegmentLength = 4, -- cada tramo de la barrera
	Thickness = 3.5, -- grosor de las llamas: estar dentro quema

	Width = 44,
	Curve = 40, -- radio del arco (los extremos se cierran hacia ti ~6 studs)
	Height = 22, -- llamas visibles
	SmokeHeight = 50, -- columna de humo negro (visual)
	CrossHeight = 55, -- hasta dónde cuenta como cruzarlo y bloquea
	Duration = 6.0,

	SusanooWidth = 70,
	SusanooCurve = 45,
	SusanooHeight = 30,
	SusanooSmokeHeight = 65,
	SusanooCrossHeight = 70,
	SusanooDuration = 7.0,

	CrossDamage = 8,
	BurnDuration = 3.0, -- 2.5 cada 0.5 s (BlackFlames)
	InsideBurn = 1.5, -- se renueva mientras sigas dentro de las llamas
	RepelStun = 0.3,
	RepelSpeed = 45,
	RepelCooldown = 0.8, -- tras devolverlo, no cuenta otro cruce

	EyeStrain = 8,
}

local config = BlackWall.Config

BlackWall.MarkerCastTimeout = 3.0
BlackWall.ProjectileFallbackDelay = 2.0
BlackWall.MinProjectileDelay = 0 -- el mínimo lo pone OnCastMarker

-- Grupo de colisión de la barrera: no choca con ningún otro (solo consigo mismo, que es con lo que
-- la consulta Targets.castBarrier)
pcall(function()
	PhysicsService:RegisterCollisionGroup(BARRIER_GROUP)
end)
for _, group in PhysicsService:GetRegisteredCollisionGroups() do
	if group.name ~= BARRIER_GROUP then
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(BARRIER_GROUP, group.name, false)
		end)
	end
end

local barrierFolder = Workspace:FindFirstChild("MangekyoBarriers")
if not barrierFolder then
	barrierFolder = Instance.new("Folder")
	barrierFolder.Name = "MangekyoBarriers"
	barrierFolder.Parent = Workspace
end

local function hasMangekyoAbility(character: Model): boolean
	return Clan.isMangekyoActive(character) and character:GetAttribute("MangekyoControl") == ABILITY
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

local function inSusanoo(character: Model?): boolean
	return character ~= nil and character:GetAttribute("SusanooActive") == true
end

function BlackWall.Precheck(character: Model, _direction: Vector3): (boolean, string)
	local player = Players:GetPlayerFromCharacter(character)
	if not Clan.isMangekyoActive(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired" })
		return false, "MangekyoRequired"
	end
	-- Mangekyō encendido, pero tu ojo de control es otro
	if not hasMangekyoAbility(character) then
		Clan.fxTo(player, "Icon", { Icon = "MangekyoRequired", Ability = config.DisplayName })
		return false, "MangekyoRequired"
	end
	return true, "OK"
end

-- Ceguera alta: recarga más lenta (JutsuServer)
function BlackWall.CooldownMultiplier(player: Player): number
	return Clan.eyeStrainCooldownMultiplier(player)
end

local internal: { [string]: BindableFunction } = {}
local function invokeInternal(name: string, ...: any): any
	if not internal[name] then
		local folder = ServerStorage:FindFirstChild("CombatInternal")
		local found = folder and folder:FindFirstChild(name)
		if not (found and found:IsA("BindableFunction")) then
			return nil
		end
		internal[name] = found
	end
	local fn = internal[name]
	local ok, result = pcall(fn.Invoke, fn, ...)
	return if ok then result else nil
end

local squadService: any = nil
local function areSquadmates(a: Player?, b: Player?): boolean
	if not a or not b then
		return false
	end
	if squadService == nil then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("Services"):WaitForChild("SquadService"))
		end)
		squadService = if ok then result else false
	end
	if not squadService or typeof(squadService.AreSquadmates) ~= "function" then
		return false
	end
	local ok, result = pcall(squadService.AreSquadmates, a, b)
	return ok and result == true
end

type Size = { Width: number, Curve: number, Height: number, SmokeHeight: number, CrossHeight: number, Duration: number }

local function sizeOf(susanoo: boolean): Size
	if susanoo then
		return {
			Width = config.SusanooWidth,
			Curve = config.SusanooCurve,
			Height = config.SusanooHeight,
			SmokeHeight = config.SusanooSmokeHeight,
			CrossHeight = config.SusanooCrossHeight,
			Duration = config.SusanooDuration,
		}
	end
	return {
		Width = config.Width,
		Curve = config.Curve,
		Height = config.Height,
		SmokeHeight = config.SmokeHeight,
		CrossHeight = config.CrossHeight,
		Duration = config.Duration,
	}
end

-- Tramos del arco, apoyados en el suelo. Cada CFrame: en la base del tramo, LookVector hacia fuera
-- (lejos de quien lo lanza), RightVector a lo largo del muro
local function buildSegments(caster: Model, center: Vector3, normal: Vector3, size: Size): ({ CFrame }, number)
	local right = normal:Cross(Vector3.yAxis).Unit
	local arcCenter = center - normal * size.Curve
	local span = size.Width / size.Curve
	local count = math.max(3, math.ceil(size.Width / config.SegmentLength))
	local length = size.Width / count
	local segments = {}
	for i = 1, count do
		local angle = -span / 2 + span * (i - 0.5) / count
		local outward = normal * math.cos(angle) + right * math.sin(angle)
		local position = arcCenter + outward * size.Curve
		-- Sigue el suelo (si no lo encuentra, a la altura del centro)
		local ground = Targets.castWorld(position + Vector3.yAxis * 8, Vector3.new(0, -40, 0), { caster })
		local base = if ground then ground.Position else Vector3.new(position.X, center.Y, position.Z)
		segments[i] = CFrame.lookAt(base, base + outward)
	end
	return segments, length
end

-- Una barrera invisible con colisión por tramo: la miran los proyectiles y las líneas de visión
local function spawnBarriers(segments: { CFrame }, length: number, size: Size): { BasePart }
	local parts = {}
	local tall = size.CrossHeight + 4
	for i, frame in segments do
		local part = Instance.new("Part")
		part.Name = "BlackWallBarrier"
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(length + 0.4, tall, 1)
		part.CFrame = frame * CFrame.new(0, tall / 2 - 4, 0)
		part.CollisionGroup = BARRIER_GROUP
		part:SetAttribute("FlameBarrier", true)
		part:SetAttribute("ProjectileBlocker", true)
		part.Parent = barrierFolder
		parts[i] = part
	end
	return parts
end

local function spawnWall(player: Player, caster: Model, direction: Vector3, susanoo: boolean)
	local root = rootOf(caster)
	local eye = eyeOf(caster)
	if not root or not eye then
		return
	end
	local size = sizeOf(susanoo)

	-- Dónde: lo que toca la mira (hasta PlaceRange), apoyado en el suelo
	local aim = if direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	local normal = flat.Unit
	local aimHit = Targets.castWorld(eye, aim * config.PlaceRange, { caster })
	local point = if aimHit then aimHit.Position else eye + aim * config.PlaceRange
	local offset = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	if offset:Dot(normal) < config.MinDistance then
		point = root.Position + normal * config.MinDistance
	end
	local ground = Targets.castWorld(point + Vector3.yAxis * 6, Vector3.new(0, -80, 0), { caster })
	local center = if ground then ground.Position else point - Vector3.yAxis * 3
	local segments, length = buildSegments(caster, center, normal, size)

	local id = HttpService:GenerateGUID(false)
	Clan.fxAll("BlackWallForm", {
		Id = id,
		Character = caster,
		Segments = segments,
		SegmentLength = length,
		Height = size.Height,
		SmokeHeight = size.SmokeHeight,
		Thickness = config.Thickness,
		Telegraph = config.Telegraph,
		RiseTime = config.RiseTime,
		Duration = size.Duration,
		Susanoo = susanoo,
	})
	Clan.addEyeStrain(player, config.EyeStrain)

	task.wait(config.Telegraph)
	local barriers = spawnBarriers(segments, length, size)
	local endsAt = os.clock() + size.Duration
	local half = length / 2 + 0.25
	local previous: { [Model]: Vector3 } = {}
	local repelledUntil: { [Model]: number } = {}
	local insideBurnAt: { [Model]: number } = {}
	local busy = false
	local connection: RBXScriptConnection

	-- Lo devuelve a su lado, aturdido (corta la inercia del air dash) y empujado lejos
	local function repel(target: Model, targetRoot: BasePart, frame: CFrame, localPoint: Vector3, side: number)
		local result = BlackFlames.ignite(target, player, config.BurnDuration, config.CrossDamage, ABILITY)
		local world = frame:PointToWorldSpace(localPoint)
		Clan.fxAll("BlackWallRepel", { Position = world, Normal = frame.LookVector * -side })
		if result == "Substituted" then
			return
		end
		local back = frame:PointToWorldSpace(Vector3.new(localPoint.X, math.max(localPoint.Y, 3), -side * (config.Thickness / 2 + 2.5)))
		local facing = targetRoot.CFrame.Rotation
		pcall(function()
			target:PivotTo(CFrame.new(back) * facing)
			targetRoot.AssemblyLinearVelocity = Vector3.zero
		end)
		invokeInternal("ApplyStun", target, config.RepelStun, true)
		invokeInternal("ExternalKnockback", target, frame.LookVector * side, config.RepelSpeed)
	end

	connection = RunService.Heartbeat:Connect(function()
		if busy then
			return
		end
		busy = true
		local now = os.clock()
		if now >= endsAt then
			connection:Disconnect()
			for _, part in barriers do
				part:Destroy()
			end
			busy = false
			return
		end
		local casterPlayer = player
		for _, candidate in Targets.list(caster) do
			local target = candidate.Character
			local targetRoot = candidate.Root
			local current = targetRoot.Position
			local last = previous[target] or current
			previous[target] = current
			local friendly = areSquadmates(casterPlayer, Players:GetPlayerFromCharacter(target))
			if friendly or target:GetAttribute("SubstitutionHidden") == true or target:GetAttribute("CombatImmune") == true then
				continue
			end
			local crossed = false
			for _, frame in segments do
				local a = frame:PointToObjectSpace(last)
				local b = frame:PointToObjectSpace(current)
				-- Cruzó el plano del tramo (a cualquier altura hasta CrossHeight)
				if not crossed and (a.Z > 0) ~= (b.Z > 0) and (repelledUntil[target] or 0) < now then
					local t = a.Z / (a.Z - b.Z)
					local hit = a:Lerp(b, t)
					if math.abs(hit.X) <= half and hit.Y >= -4 and hit.Y <= size.CrossHeight then
						crossed = true
						repelledUntil[target] = now + config.RepelCooldown
						previous[target] = nil
						task.spawn(repel, target, targetRoot, frame, hit, if a.Z > 0 then 1 else -1)
					end
				end
				-- Dentro de las llamas: arde
				if math.abs(b.Z) <= config.Thickness / 2 and math.abs(b.X) <= half
					and b.Y >= -4 and b.Y <= size.Height and (insideBurnAt[target] or 0) <= now then
					insideBurnAt[target] = now + 0.5
					task.spawn(BlackFlames.ignite, target, player, config.InsideBurn, nil, ABILITY)
				end
			end
		end
		busy = false
	end)
end

local built = Clan.build(BlackWall, "Uchiha", function(context, direction)
	local caster: Model = context.Character
	local player: Player = context.Player
	context.BlackWallPlaced = true
	if not hasMangekyoAbility(caster) then
		return
	end
	task.spawn(spawnWall, player, caster, direction, context.BlackWallSusanoo == true)
end)

local baseOnCastMarker = built.OnCastMarker

function built.OnCastStarted(context: any)
	context.BlackWallStartedAt = os.clock()
	context.BlackWallSusanoo = inSusanoo(context.Character)
end

function built.OnCastMarker(context: any, semanticMarker: string, source: string, markerPayload: any?)
	if semanticMarker ~= "ProjectileSpawn" or context.BlackWallScheduled then
		return
	end
	context.BlackWallScheduled = true
	-- No antes de los sellos (o del windup del Susanoo, que se ve en quien lo lanza)
	local susanoo = context.BlackWallSusanoo == true
	local earliest = (context.BlackWallStartedAt or os.clock()) + config.SealTime
	if susanoo then
		earliest = os.clock() + config.SusanooWindup
		Clan.fxAll("BlackWallWindup", { Character = context.Character, Duration = config.SusanooWindup })
	end
	local wait = earliest - os.clock()
	if wait > 0 then
		task.delay(wait, baseOnCastMarker, context, semanticMarker, source, markerPayload)
	else
		baseOnCastMarker(context, semanticMarker, source, markerPayload)
	end
end

return built
