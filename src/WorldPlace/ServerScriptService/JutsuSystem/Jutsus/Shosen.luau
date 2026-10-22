-- ServerScriptService > JutsuSystem > Jutsus > Shosen
--
-- Ninjutsu médico · Shōsen no Jutsu, palma curativa (rango C, primera capa).
-- Canalizas 3 s curando 20 de vida en total:
--   - a un jugador herido que estés tocando (≤ 6 studs, delante de ti), o
--   - a ti mismo si no hay nadie.
-- Mientras canalizas vas muy lento. Se corta si te golpean, si te aturden, si te alejas
-- más de 4 studs de donde empezaste o si el otro se aleja. No cura a alguien Downed.
-- 2 sellos. Gasta mucho chakra (curar es fuerte en un juego con permadeath).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Ninjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Ninjutsu")
)

local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))

local Shosen = {}

Shosen.Id = "Shosen"
Shosen.TechniqueCategory = "Ninjutsu"
Shosen.MinimumLevel = 1
Shosen.SortOrder = 1030

Shosen.Config = {
	DisplayName = "Shōsen no Jutsu",
	TechniqueCategory = "Ninjutsu",
	MinimumLevel = 1,
	SortOrder = 1030,

	ChakraCost = 30,
	Cooldown = 30.0,
	CastTime = 0.5,

	TotalHeal = 20,
	Duration = 3.0,
	TickInterval = 0.25,
	AllyRange = 6,
	MaxCasterDrift = 4, -- si te mueves más que esto desde donde empezaste, se corta
	MaxAllyDistance = 8,
	ChannelStatus = "ShosenChannel",
}

Shosen.MarkerCastTimeout = 5.0
Shosen.ProjectileFallbackDelay = 2.0
Shosen.MinProjectileDelay = 0

local channels: {[Model]: number} = {}
local sequence = 0

local function canBeHealed(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
		and character:GetAttribute("IsDowned") ~= true
		and character:GetAttribute("DownedActionLocked") ~= true
end

-- Jugador herido que estás tocando, o nil
local function findAlly(character: Model, range: number): Model?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local best, bestDistance = nil, range
	for _, player in Players:GetPlayers() do
		local other = player.Character
		local otherRoot = other and other:FindFirstChild("HumanoidRootPart")
		local otherHumanoid = other and other:FindFirstChildOfClass("Humanoid")
		if other and other ~= character and otherRoot and otherHumanoid
			and otherHumanoid.Health < otherHumanoid.MaxHealth and canBeHealed(other) then
			local offset = otherRoot.Position - root.Position
			if offset.Magnitude <= bestDistance and root.CFrame.LookVector:Dot(offset.Unit) > 0.2 then
				best, bestDistance = other, offset.Magnitude
			end
		end
	end
	return best
end

return Ninjutsu.build(Shosen, function(context)
	local config = context.Config
	local caster: Model = context.Character
	local casterHumanoid = caster:FindFirstChildOfClass("Humanoid") :: Humanoid
	local casterRoot = caster:FindFirstChild("HumanoidRootPart") :: BasePart

	local target = findAlly(caster, config.AllyRange) or caster
	if not canBeHealed(target) then
		return
	end
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid") :: Humanoid
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart

	sequence += 1
	local id = sequence
	channels[caster] = id

	StatusEffectService.Apply(caster, config.ChannelStatus, { Duration = config.Duration })
	Ninjutsu.fxAll("ShosenStart", { Caster = caster, Target = target, Duration = config.Duration, Id = id })

	local startPosition = casterRoot.Position
	local lastCasterHealth = casterHumanoid.Health
	local healPerTick = config.TotalHeal * config.TickInterval / config.Duration
	local startedAt = os.clock()
	local nextTick = startedAt + config.TickInterval
	local connection: RBXScriptConnection? = nil

	local function stop(reason: string)
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if channels[caster] == id then
			channels[caster] = nil
		end
		if caster.Parent and StatusEffectService.Has(caster, config.ChannelStatus) then
			StatusEffectService.Remove(caster, config.ChannelStatus, "ShosenEnd")
		end
		Ninjutsu.fxAll("ShosenEnd", { Id = id, Reason = reason })
	end

	connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if channels[caster] ~= id or not caster.Parent or casterHumanoid.Health <= 0 then
			stop("Cancelled")
			return
		end
		-- Golpeado o aturdido: se corta
		if casterHumanoid.Health < lastCasterHealth - 0.01
			or caster:GetAttribute("IsStunned") == true
			or caster:GetAttribute("CombatRagdolled") == true then
			stop("Interrupted")
			return
		end
		lastCasterHealth = casterHumanoid.Health
		if (casterRoot.Position - startPosition).Magnitude > config.MaxCasterDrift then
			stop("Moved")
			return
		end
		if target ~= caster and (not target.Parent or not canBeHealed(target)
			or (targetRoot.Position - casterRoot.Position).Magnitude > config.MaxAllyDistance) then
			stop("TargetLost")
			return
		end
		if now >= nextTick then
			nextTick += config.TickInterval
			if canBeHealed(target) then
				targetHumanoid.Health = math.min(targetHumanoid.MaxHealth, targetHumanoid.Health + healPerTick)
				if target == caster then
					lastCasterHealth = casterHumanoid.Health
				end
			end
		end
		if now - startedAt >= config.Duration then
			stop("Done")
		end
	end)
end)
