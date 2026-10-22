-- ServerScriptService > JutsuSystem > Jutsus > KonohaReppu
--
-- Taijutsu · Konoha Reppū (rango D, primera capa). Barrida baja.
-- Arco de 140° frente a ti, 9 studs. A quien tenga los pies en el suelo: 6 de daño y cae
-- (~0.8 s sin moverse ni atacar). No se puede bloquear de pie; se esquiva saltando.
-- Gasta stamina.

local ServerScriptService = game:GetService("ServerScriptService")

local Taijutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Taijutsu")
)

local KonohaReppu = {}

KonohaReppu.Id = "KonohaReppu"
KonohaReppu.TechniqueCategory = "Taijutsu"
KonohaReppu.MinimumLevel = 1
KonohaReppu.SortOrder = 820

KonohaReppu.Config = {
	DisplayName = "Konoha Reppū",
	TechniqueCategory = "Taijutsu",
	MinimumLevel = 1,
	SortOrder = 820,

	StaminaCost = 20,
	Cooldown = 10.0,
	CastTime = 0.3,

	Range = 9,
	Arc = 140,
	-- Distancia máxima del HumanoidRootPart al suelo para contar como "de pie"
	-- (R6 de pie ≈ 3; saltando la supera)
	GroundedHeight = 3.8,

	Hit = {
		Damage = 6,
		SourceId = "KonohaReppu",
		Unblockable = true,
		Ragdoll = { Horizontal = 6, Vertical = 10, Duration = 0.8 },
	},
}

KonohaReppu.MarkerCastTimeout = 4.0
KonohaReppu.ProjectileFallbackDelay = 2.0
KonohaReppu.MinProjectileDelay = 0.05

return Taijutsu.build(KonohaReppu, function(context, forward)
	local config = context.Config
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)

	Taijutsu.fxAll("Reppu", { Character = character, Direction = forward, Range = config.Range })

	for _, candidate in Taijutsu.targetsAround(character, forward, config.Range, config.Arc, 4) do
		if Taijutsu.isGrounded(candidate.Character, config.GroundedHeight) then
			Taijutsu.hit(context.Player, candidate.Character, config.Hit)
		end
	end
end)
