-- ServerScriptService > JutsuSystem > Jutsus > GokaMekkyaku
--
-- Clan Uchiha · Mangekyō · ojo de ataque: Katon: Gōka Mekkyaku (MangekyoCatalog, común). La gran
-- llamarada de Madara: no es un proyectil, es fuego que sale de la boca sin parar y se amontona
-- hasta cubrir el terreno. Solo con el Mangekyō activo y la técnica en tu ojo de ataque.
--   1. Sellos (4, pausados, como Enton: Black Spear). Si te golpean, se cortan.
--   2. Tomas aire (InhaleTime, marcador "ReleaseStart"): el fuego brilla en la boca. Es el aviso.
--   3. Escupes fuego ChannelTime s (estado GokaChanneling: casi quieto, sin atacar). Cada
--      TickTime salen CellsPerTick llamas en un abanico de FanAngle° hacia donde miras; avanzan
--      a FrontSpeed (algo menos que un sprint) y se agrandan (CellStartRadius → CellEndRadius)
--      hasta Reach studs o la primera pared. El abanico gira hacia donde miras a TurnRate °/s.
--      Un golpe de InterruptDamage o más, o quedar aturdido, corta el aliento.
--   4. Lo que ya salió sigue ardiendo LingerTime s después de cortar o acabar.
-- Daño: al alcanzarte FrontDamage y la quemadura normal (Burning); si sigues dentro, InsideDamage
-- cada InsideTick. Se escapa saliendo del abanico por los lados o alejándose antes de que llegue;
-- no se bloquea y la sustitución esquiva el golpe.
-- Con el Susanoo activo: sin sellos, SusanooWindup de preparación, abanico y alcance mayores
-- (Susanoo*), gira más lento y los golpes no lo cortan (las costillas lo protegen).
-- Fuego normal: la afinidad Katon del Uchiha (+10 %, Clan.Tuning.UchihaKatonMultiplier) se aplica
-- aquí (no lleva NatureId, que exigiría tener el Fuego desbloqueado).
-- Sube EyeStrain (fatiga ocular) puntos y, con la fatiga ocular alta, recarga más lento (CooldownMultiplier).
-- Visual: ClanFX "GokaInhale", "GokaBreathStart", "GokaCells", "GokaBreathEnd" y "GokaCancel"
-- (StarterPlayerScripts > MangekyoClient).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local kit = ServerScriptService:WaitForChild("JutsuSystem"):WaitForChild("TechniqueKit")
local Clan = require(kit:WaitForChild("Clan"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))

local ABILITY = "GokaMekkyaku" -- ojo de ataque (MangekyoAttack)
local CHANNEL_STATUS = "GokaChanneling"

local GokaMekkyaku = {}

GokaMekkyaku.Id = "GokaMekkyaku"
GokaMekkyaku.TechniqueCategory = "Clan"
GokaMekkyaku.MinimumLevel = 60
GokaMekkyaku.SortOrder = 1106
-- Solo la aprende quien tiene la técnica en su ojo de ataque (el clan lo añade Clan.build)
GokaMekkyaku.Requirements = {
	Learn = { PlayerAttributes = { MangekyoAttack = ABILITY } },
}

GokaMekkyaku.Config = {
	DisplayName = "Katon: Gōka Mekkyaku",
	TechniqueCategory = "Clan",
	MinimumLevel = 60,
	SortOrder = 1106,

	ChakraCost = 40,
	Cooldown = 18.0,
	CastTime = 1.3, -- sellos + tomar aire (la lectura del Sharingan lo usa)

	-- Tiempos mínimos que pone el servidor
	SealTime = 0.75, -- 4 sellos con el Mangekyō
	InhaleTime = 0.4,
	SusanooWindup = 0.7,

	ChannelTime = 2.0,
	TickTime = 0.1,
	CellsPerTick = 2,
	FanAngle = 70,
	Reach = 60,
	FrontSpeed = 38,
	CellStartRadius = 3,
	CellEndRadius = 9,
	CellHeight = 12,
	TurnRate = 60,
	InterruptDamage = 5,
	LingerTime = 3.0,

	SusanooFanMultiplier = 1.3,
	SusanooReach = 75,
	SusanooTurnRate = 35,

	FrontDamage = 12,
	InsideDamage = 2.5,
	InsideTick = 0.5,

	EyeStrain = 6,
}

local config = GokaMekkyaku.Config

GokaMekkyaku.MarkerCastTimeout = 4.0
GokaMekkyaku.ProjectileFallbackDelay = 3.0
GokaMekkyaku.MinProjectileDelay = 0 -- el mínimo lo pone OnCastMarker (depende del Susanoo)

local BODY_HIT = { Damaged = true, Downed = true, DamagedNPC = true }

local function hasMangekyoAbility(character: Model): boolean
	return Clan.isMangekyoActive(character) and character:GetAttribute("MangekyoAttack") == ABILITY
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function inSusanoo(character: Model?): boolean
	return character ~= nil and character:GetAttribute("SusanooActive") == true
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.05 then f.Unit else nil
end

function GokaMekkyaku.Precheck(character: Model, _direction: Vector3): (boolean, string)
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
function GokaMekkyaku.CooldownMultiplier(player: Player): number
	return Clan.eyeStrainCooldownMultiplier(player)
end

local function burn(player: Player, target: Model, humanoid: Humanoid, amount: number, applyStatus: boolean)
	local ok, resolution = pcall(DamageService.Apply, {
		TargetCharacter = target,
		TargetHumanoid = humanoid,
		TargetPlayer = Players:GetPlayerFromCharacter(target),
		Attacker = player,
		Damage = amount * (Clan.Tuning.UchihaKatonMultiplier or 1),
		SourceType = "Jutsu",
		SourceId = ABILITY,
	})
	local result = if ok and typeof(resolution) == "table" then resolution.Result else nil
	if applyStatus and BODY_HIT[result or ""] then
		pcall(StatusEffectService.Apply, target, "Burning", {
			SourcePlayer = player,
			SourceCharacter = player.Character,
		})
	end
end

local function canHit(target: Model): boolean
	return target:GetAttribute("SubstitutionHidden") ~= true
		and target:GetAttribute("CombatImmune") ~= true
		and target:GetAttribute("IsMissionNPC") ~= true
end

-- Gira v hacia goal como mucho maxAngle radianes (en horizontal)
local function turnToward(v: Vector3, goal: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(v:Dot(goal), -1, 1))
	if angle <= maxAngle or angle < 1e-3 then
		return goal
	end
	local sign = if v:Cross(goal).Y >= 0 then 1 else -1
	return (CFrame.Angles(0, sign * maxAngle, 0) * v).Unit
end

type Cell = { Origin: Vector3, Direction: Vector3, Distance: number, BornAt: number }

local function breathe(player: Player, caster: Model, initial: Vector3, susanoo: boolean)
	local root = rootOf(caster)
	if not root then
		return
	end
	local direction = flat(initial) or flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local ground = Targets.castWorld(root.Position, Vector3.new(0, -12, 0), { caster })
	local groundY = if ground then ground.Position.Y else root.Position.Y - 3
	local fan = math.rad(config.FanAngle * (if susanoo then config.SusanooFanMultiplier else 1))
	local reach = if susanoo then config.SusanooReach else config.Reach
	local turnRate = math.rad(if susanoo then config.SusanooTurnRate else config.TurnRate)

	local id = HttpService:GenerateGUID(false)
	Clan.applyStatus(caster, CHANNEL_STATUS, { Duration = config.ChannelTime + 0.2, SourcePlayer = player })
	Clan.fxAll("GokaBreathStart", { Id = id, Character = caster, Susanoo = susanoo, Duration = config.ChannelTime })
	Clan.addEyeStrain(player, config.EyeStrain)

	local cells: {Cell} = {}
	local endedAt: number? = nil
	local struck: {[Model]: number} = {} -- última vez que le quemó estar dentro

	-- Daño: quien está dentro de alguna llama
	task.spawn(function()
		while not endedAt or os.clock() < endedAt + config.LingerTime do
			local now = os.clock()
			for _, candidate in Targets.list(caster) do
				local target = candidate.Character
				if canHit(target) then
					local position = candidate.Root.Position
					local height = position.Y - groundY
					if height > -3 and height < config.CellHeight then
						local inside = false
						for _, cell in cells do
							local travelled = math.min((now - cell.BornAt) * config.FrontSpeed, cell.Distance)
							local radius = config.CellStartRadius
								+ (config.CellEndRadius - config.CellStartRadius) * math.clamp(travelled / reach, 0, 1)
							local center = cell.Origin + cell.Direction * travelled
							local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
							if offset.Magnitude <= radius then
								inside = true
								break
							end
						end
						if inside then
							local last = struck[target]
							if not last then
								struck[target] = now
								task.spawn(burn, player, target, candidate.Humanoid, config.FrontDamage, true)
							elseif now - last >= config.InsideTick then
								struck[target] = now
								task.spawn(burn, player, target, candidate.Humanoid, config.InsideDamage, false)
							end
						end
					end
				end
			end
			task.wait(0.1)
		end
	end)

	-- El aliento
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	local lastHealth = if humanoid then humanoid.Health else 0
	local started = os.clock()
	local tick = 0
	while os.clock() - started < config.ChannelTime do
		if player.Character ~= caster or not caster.Parent or not humanoid or humanoid.Health <= 0
			or not rootOf(caster) or caster:GetAttribute("IsDowned") == true then
			break
		end
		-- Un golpe o quedar aturdido corta el aliento (con el Susanoo, no)
		if not susanoo and (caster:GetAttribute("IsStunned") == true
			or humanoid.Health <= lastHealth - config.InterruptDamage) then
			break
		end
		lastHealth = math.max(lastHealth, humanoid.Health)
		local current = rootOf(caster) :: BasePart
		local look = flat(current.CFrame.LookVector)
		if look then
			direction = turnToward(direction, look, turnRate * config.TickTime)
		end
		local origin = Vector3.new(current.Position.X, groundY, current.Position.Z) + direction * 2
		local batch = {}
		local now = os.clock()
		for k = 1, config.CellsPerTick do
			-- un lado y el otro del abanico, al azar dentro de cada mitad
			local half = if (tick + k) % 2 == 0 then 1 else -1
			local angle = half * math.random() * fan / 2
			local cellDirection = (CFrame.Angles(0, angle, 0) * direction).Unit
			local distance = reach * (0.55 + 0.45 * math.random())
			local wall = Targets.castWorld(origin + Vector3.yAxis * 2, cellDirection * distance, { caster })
			if wall then
				distance = math.max(2, (wall.Position - (origin + Vector3.yAxis * 2)).Magnitude - 1)
			end
			local cell = { Origin = origin, Direction = cellDirection, Distance = distance, BornAt = now }
			table.insert(cells, cell)
			table.insert(batch, { Origin = origin, Direction = cellDirection, Distance = distance })
		end
		Clan.fxAll("GokaCells", {
			Id = id,
			Cells = batch,
			Speed = config.FrontSpeed,
			StartRadius = config.CellStartRadius,
			EndRadius = config.CellEndRadius,
			Reach = reach,
		})
		tick += 1
		task.wait(config.TickTime)
	end
	endedAt = os.clock()
	if caster.Parent then
		StatusEffectService.Remove(caster, CHANNEL_STATUS, "Ended")
	end
	Clan.fxAll("GokaBreathEnd", { Id = id, Character = caster, Linger = config.LingerTime })
end

local built = Clan.build(GokaMekkyaku, "Uchiha", function(context, direction)
	local caster: Model = context.Character
	local player: Player = context.Player
	context.GokaReleased = true
	if not hasMangekyoAbility(caster) then
		Clan.fxAll("GokaCancel", { Character = caster })
		return
	end
	task.spawn(breathe, player, caster, direction, context.GokaSusanoo == true)
end)

local baseOnCastMarker = built.OnCastMarker

function built.OnCastStarted(context: any)
	context.GokaStartedAt = os.clock()
	context.GokaSusanoo = inSusanoo(context.Character)
end

-- Toma aire (fin de los sellos)
local function startInhale(context: any)
	if context.GokaInhaleAt then
		return
	end
	context.GokaInhaleAt = os.clock()
	local susanoo = context.GokaSusanoo == true
	Clan.fxAll("GokaInhale", {
		Character = context.Character,
		Susanoo = susanoo,
		Duration = if susanoo then config.SusanooWindup else config.InhaleTime,
	})
end

function built.OnCastMarker(context: any, semanticMarker: string, source: string, markerPayload: any?)
	if semanticMarker == "ReleaseStart" then
		startInhale(context)
		return
	end
	if semanticMarker ~= "ProjectileSpawn" or context.GokaScheduled then
		return
	end
	context.GokaScheduled = true
	startInhale(context)
	-- No antes de los sellos y de tomar aire (margen de latencia)
	local susanoo = context.GokaSusanoo == true
	local windup = if susanoo then config.SusanooWindup else config.InhaleTime
	local earliest = context.GokaInhaleAt + windup * 0.9
	if not susanoo then
		earliest = math.max(earliest, (context.GokaStartedAt or 0) + config.SealTime + windup * 0.9)
	end
	local wait = earliest - os.clock()
	if wait > 0 then
		task.delay(wait, baseOnCastMarker, context, semanticMarker, source, markerPayload)
	else
		baseOnCastMarker(context, semanticMarker, source, markerPayload)
	end
end

-- Se cortó antes de soltarla: fuera el fuego de la boca
function built.OnCastEnded(context: any, _reason: string)
	if context.GokaInhaleAt and not context.GokaReleased and not context.GokaScheduled then
		Clan.fxAll("GokaCancel", { Character = context.Character })
	end
end

return built
