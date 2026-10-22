-- ServerScriptService > JutsuSystem > Jutsus > Kesagiri
--
-- Kenjutsu · Kesagiri (rango D, primera capa). Corte diagonal pesado.
-- Lento: el arma brilla desde que empieza la animación (M1_5 a velocidad reducida, se ve
-- venir) y en su marcador "Hit" corta en arco frente a ti (8 studs, 110°). 14 de daño.
-- Si te lo bloquean, ROMPE LA GUARDIA de golpe. Castiga a quien se queda bloqueando.
-- Si te golpean durante la preparación, no sale. Daño escalado por el arma. Gasta stamina.

local ServerScriptService = game:GetService("ServerScriptService")

local Kenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Kenjutsu")
)

local Kesagiri = {}

Kesagiri.Id = "Kesagiri"
Kesagiri.TechniqueCategory = "Kenjutsu"
Kesagiri.MinimumLevel = 1
Kesagiri.SortOrder = 930

Kesagiri.Config = {
	DisplayName = "Kesagiri",
	TechniqueCategory = "Kenjutsu",
	MinimumLevel = 1,
	SortOrder = 930,

	StaminaCost = 25,
	Cooldown = 12.0,
	CastTime = 0.2,

	Range = 8,
	Arc = 110,

	Hit = {
		Damage = 14,
		SourceId = "Kesagiri",
		GuardDamage = 999, -- bloqueado = guardia rota
		Hitstun = 0.6,
		Knockback = 20,
		Heavy = true,
	},
}

Kesagiri.MarkerCastTimeout = 4.0
Kesagiri.ProjectileFallbackDelay = 1.5
Kesagiri.MinProjectileDelay = 0

Kenjutsu.build(Kesagiri, function(context, forward)
	local config = context.Config
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)

	Kenjutsu.fxAll("Kesagiri", { Character = character, Direction = forward, Range = config.Range })
	for _, candidate in Kenjutsu.targetsAround(character, forward, config.Range, config.Arc, 5) do
		Kenjutsu.hit(context.Player, candidate.Character, config.Hit)
	end
end)

-- El arma brilla desde el inicio de la animación: aviso para el rival
local baseOnCastMarker = Kesagiri.OnCastMarker
function Kesagiri.OnCastMarker(context: any, semanticMarker: string, source: string, markerPayload: any?)
	if semanticMarker == "ReleaseStart" and not context.KesagiriGlint then
		context.KesagiriGlint = true
		Kenjutsu.fxAll("KesagiriWindup", { Character = context.Character, Duration = 0.6 })
	end
	baseOnCastMarker(context, semanticMarker, source, markerPayload)
end

return Kesagiri
