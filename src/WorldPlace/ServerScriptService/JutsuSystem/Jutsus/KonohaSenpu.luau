-- ServerScriptService > JutsuSystem > Jutsus > KonohaSenpu
--
-- Taijutsu · Konoha Senpū (rango C, primera capa).
-- Patada giratoria de 2 golpes alrededor tuyo (radio 8, 360°): 6 + 6 de daño.
-- El primero aturde (mantiene el combo), el segundo empuja. Se puede usar en medio del
-- combo de M1 para extenderlo. Gasta stamina.

local ServerScriptService = game:GetService("ServerScriptService")

local Taijutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Taijutsu")
)

local KonohaSenpu = {}

KonohaSenpu.Id = "KonohaSenpu"
KonohaSenpu.TechniqueCategory = "Taijutsu"
KonohaSenpu.MinimumLevel = 1
KonohaSenpu.SortOrder = 810

KonohaSenpu.Config = {
	DisplayName = "Konoha Senpū",
	TechniqueCategory = "Taijutsu",
	MinimumLevel = 1,
	SortOrder = 810,

	StaminaCost = 20,
	Cooldown = 9.0,
	CastTime = 0.3,

	Radius = 8,
	SecondHitDelay = 0.2,

	FirstHit = {
		Damage = 6,
		SourceId = "KonohaSenpu",
		GuardDamage = 20,
		Hitstun = 0.55,
		ComboNumber = 3,
	},
	SecondHit = {
		Damage = 6,
		SourceId = "KonohaSenpu",
		GuardDamage = 25,
		Hitstun = 0.45,
		Knockback = 30,
		BlockedKnockback = 14,
		Heavy = true,
	},
}

KonohaSenpu.MarkerCastTimeout = 4.0
KonohaSenpu.ProjectileFallbackDelay = 2.0
KonohaSenpu.MinProjectileDelay = 0.05

local function spinHit(context: any, spec: {[string]: any})
	local character: Model = context.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not character.Parent or not humanoid or humanoid.Health <= 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local forward = Taijutsu.flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	for _, candidate in Taijutsu.targetsAround(character, forward, context.Config.Radius, 360, 5) do
		Taijutsu.hit(context.Player, candidate.Character, spec)
	end
end

return Taijutsu.build(KonohaSenpu, function(context)
	local config = context.Config
	Taijutsu.fxAll("Senpu", { Character = context.Character, Radius = config.Radius })
	spinHit(context, config.FirstHit)
	task.delay(config.SecondHitDelay, function()
		if context.Character:GetAttribute("IsStunned") ~= true then
			spinHit(context, config.SecondHit)
		end
	end)
end)
