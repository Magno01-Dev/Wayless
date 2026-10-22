-- ServerScriptService > JutsuSystem > TechniqueKit > BlackFlames  (ModuleScript)
--
-- Llamas negras del Mangekyō (Amaterasu, Enton: Black Spear y las que vengan). Un solo fuego por
-- víctima: si ya arde, se renueva (dura lo que más quede) y los ticks no se suman.
--   BlackFlames.ignite(target, attacker, duration, impact?, sourceId?)
--       -> "Ignited" | "Substituted" (el impacto lo esquivó con la sustitución: no prende) | nil
--   BlackFlames.spawnPuddle(position, attacker, ignore?, opts)  charco que prende a quien lo pise
--       (menos a quien lo lanzó); opts = { Radius, Duration, Burn, SourceId? }
--   BlackFlames.burnLog(victim, near, attacker, opts)  se sustituyó: arde su tronco (el que dejó
--       cerca de near) y el charco queda allí
-- Nada que apague el fuego normal lo apaga (no es Burning). Si se sustituye mientras arde, arde su
-- tronco. Visual: atributo del personaje AmaterasuBurning + etiqueta "AmaterasuBurning" (también
-- NPCs y el tronco) y ClanFX "AmaterasuPuddle" (StarterPlayerScripts > MangekyoClient).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Clan = require(script.Parent:WaitForChild("Clan"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))

local TAG = "AmaterasuBurning"

local BlackFlames = {}

BlackFlames.Tuning = {
	TickInterval = 0.5,
	TickDamage = 2.5,
	LogSearchRadius = 15, -- studs alrededor de donde estaba quien se sustituyó
	-- Charco del tronco cuando se sustituye mientras arde
	LogPuddle = { Radius = 3.5, Duration = 6.0, Burn = 3.0 },
}

local tuning = BlackFlames.Tuning

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

type Burn = { EndsAt: number, Attacker: Player?, SourceId: string }
local burning: {[Model]: Burn} = {}

-- Prende a quien lo pise (menos a quien lo lanzó)
function BlackFlames.spawnPuddle(position: Vector3, attacker: Player?, ignore: Instance?, opts: {[string]: any})
	local casterCharacter = attacker and attacker.Character
	local ground = Targets.castWorld(position + Vector3.yAxis * 2, Vector3.new(0, -40, 0), { casterCharacter, ignore })
	local center = if ground then ground.Position else position - Vector3.new(0, 3, 0)
	Clan.fxAll("AmaterasuPuddle", { Position = center, Radius = opts.Radius, Duration = opts.Duration })
	local endsAt = os.clock() + opts.Duration
	task.spawn(function()
		while os.clock() < endsAt do
			task.wait(0.25)
			for _, candidate in Targets.list(casterCharacter) do
				local root = candidate.Root
				local offset = root.Position - center
				if candidate.Character ~= casterCharacter
					and Vector3.new(offset.X, 0, offset.Z).Magnitude <= opts.Radius
					and offset.Y > -1 and offset.Y < 5
					and candidate.Character:GetAttribute("SubstitutionHidden") ~= true then
					BlackFlames.ignite(candidate.Character, attacker, opts.Burn, nil, opts.SourceId)
				end
			end
		end
	end)
end

-- Se sustituyó: arde su tronco (el que dejó cerca de donde estaba) y el charco queda allí
function BlackFlames.burnLog(victim: Model, near: Vector3, attacker: Player?, opts: {[string]: any})
	local owner = Players:GetPlayerFromCharacter(victim)
	local logs = Workspace:FindFirstChild("SubstitutionLogs")
	local best: Instance?, bestDistance = nil, tuning.LogSearchRadius
	if owner and logs then
		for _, log in logs:GetChildren() do
			if log:GetAttribute("SubstitutionOwnerUserId") == owner.UserId then
				local position = if log:IsA("Model") then log:GetPivot().Position
					elseif log:IsA("BasePart") then log.Position
					else nil
				if position and (position - near).Magnitude <= bestDistance then
					best, bestDistance = log, (position - near).Magnitude
				end
			end
		end
	end
	if best then
		CollectionService:AddTag(best, TAG)
		local position = if best:IsA("Model") then best:GetPivot().Position else (best :: BasePart).Position
		BlackFlames.spawnPuddle(position, attacker, best, opts)
	else
		BlackFlames.spawnPuddle(near, attacker, victim, opts)
	end
end

local function damage(target: Model, humanoid: Humanoid, attacker: Player?, amount: number, sourceId: string): string?
	local ok, resolution = pcall(DamageService.Apply, {
		TargetCharacter = target,
		TargetHumanoid = humanoid,
		TargetPlayer = Players:GetPlayerFromCharacter(target),
		Attacker = attacker,
		Damage = amount,
		SourceType = "Jutsu",
		SourceId = sourceId,
		IgnoreArmor = true,
	})
	return if ok and typeof(resolution) == "table" then resolution.Result else nil
end

local function extinguish(target: Model)
	burning[target] = nil
	if target.Parent then
		target:SetAttribute("AmaterasuBurning", nil)
		CollectionService:RemoveTag(target, TAG)
		StatusEffectService.Remove(target, "Amaterasu", "Ended")
	end
end

-- Prende (o renueva) las llamas: duran lo que más quede
function BlackFlames.ignite(target: Model, attacker: Player?, duration: number, impact: number?, sourceId: string?): string?
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local source = sourceId or "Amaterasu"
	if impact and impact > 0 then
		local result = damage(target, humanoid, attacker, impact, source)
		if result == "Substituted" then
			return result
		end
	end
	local now = os.clock()
	local entry = burning[target]
	if entry then
		entry.EndsAt = math.max(entry.EndsAt, now + duration)
		entry.Attacker = attacker or entry.Attacker
	else
		entry = { EndsAt = now + duration, Attacker = attacker, SourceId = source }
		burning[target] = entry
		target:SetAttribute("AmaterasuBurning", true)
		CollectionService:AddTag(target, TAG)
		task.spawn(function()
			while burning[target] == entry do
				task.wait(tuning.TickInterval)
				if burning[target] ~= entry then
					return
				end
				local currentHumanoid = target:FindFirstChildOfClass("Humanoid")
				if not target.Parent or not currentHumanoid or currentHumanoid.Health <= 0 or os.clock() >= entry.EndsAt then
					break
				end
				local root = rootOf(target)
				local result = damage(target, currentHumanoid, entry.Attacker, tuning.TickDamage, entry.SourceId)
				if result == "Substituted" then
					-- Escapó con la sustitución: arde el tronco (charco corto)
					if root then
						local puddle = table.clone(tuning.LogPuddle)
						puddle.SourceId = entry.SourceId
						BlackFlames.burnLog(target, root.Position, entry.Attacker, puddle)
					end
					break
				end
			end
			if burning[target] == entry then
				extinguish(target)
			end
		end)
	end
	Clan.applyStatus(target, "Amaterasu", { Duration = entry.EndsAt - now, SourcePlayer = attacker })
	return "Ignited"
end

Players.PlayerRemoving:Connect(function(player)
	local character = player.Character
	if character then
		burning[character] = nil
	end
end)

return BlackFlames
