-- ServerScriptService > JutsuSystem > Jutsus > Tsuki
--
-- Kenjutsu · Tsuki (rango D, primera capa). Estocada.
-- Avanzas un paso y clavas hacia el retículo: línea recta de 12 studs que atraviesa hasta
-- 2 enemigos (los más cercanos). 9 de daño y −45 de guardia si lo bloquean.
-- Daño escalado por el arma. Gasta stamina.

local ServerScriptService = game:GetService("ServerScriptService")

local Kenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Kenjutsu")
)

local Targets = require(game:GetService("ReplicatedStorage"):WaitForChild("Throwables"):WaitForChild("Targets"))

local Tsuki = {}

Tsuki.Id = "Tsuki"
Tsuki.TechniqueCategory = "Kenjutsu"
Tsuki.MinimumLevel = 1
Tsuki.SortOrder = 920

Tsuki.Config = {
	DisplayName = "Tsuki",
	TechniqueCategory = "Kenjutsu",
	MinimumLevel = 1,
	SortOrder = 920,

	StaminaCost = 20,
	Cooldown = 8.0,
	CastTime = 0.2,

	Range = 12,
	Width = 2.5, -- radio de la línea
	MaxTargets = 2,
	StepSpeed = 45,
	StepTime = 0.12,

	Hit = {
		Damage = 9,
		SourceId = "Tsuki",
		GuardDamage = 45,
		Hitstun = 0.4,
		Knockback = 18,
		BlockedKnockback = 14,
	},
}

Tsuki.MarkerCastTimeout = 3.0
Tsuki.ProjectileFallbackDelay = 1.0
Tsuki.MinProjectileDelay = 0

return Kenjutsu.build(Tsuki, function(context, forward)
	local config = context.Config
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)

	-- Paso adelante
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local step = Instance.new("LinearVelocity")
	step.Attachment0 = attachment
	step.RelativeTo = Enum.ActuatorRelativeTo.World
	step.MaxForce = 1e6
	step.VectorVelocity = forward * config.StepSpeed
	step.Parent = root
	task.delay(config.StepTime, function()
		step:Destroy()
		attachment:Destroy()
	end)

	Kenjutsu.fxAll("Tsuki", { Character = character, Direction = forward, Range = config.Range })

	-- Línea desde el pecho hacia adelante; los más cercanos primero
	local from = root.Position
	local to = from + forward * config.Range
	local hits = {}
	for _, candidate in Targets.list(character) do
		local bottom, top = Targets.bodySegment(candidate.Root.Position)
		local distance = Targets.segmentDistance(from, to, bottom, top)
		if distance <= config.Width + 1 and not Targets.castWorld(from, candidate.Root.Position - from, { character, candidate.Character }) then
			table.insert(hits, { Candidate = candidate, Along = (candidate.Root.Position - from):Dot(forward) })
		end
	end
	table.sort(hits, function(a, b)
		return a.Along < b.Along
	end)
	for i = 1, math.min(#hits, config.MaxTargets) do
		Kenjutsu.hit(context.Player, hits[i].Candidate.Character, config.Hit)
	end
end)
