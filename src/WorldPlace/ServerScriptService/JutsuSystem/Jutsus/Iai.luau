-- ServerScriptService > JutsuSystem > Jutsus > Iai
--
-- Kenjutsu · Iai (rango C, primera capa). Corte de desenvaine.
-- Instantáneo: corte en línea frente a ti (11 studs, arco estrecho), desenvainando el arma
-- si estaba enfundada. 10 de daño, −30 de guardia si lo bloquean.
-- CONTRAATAQUE: si lo usas hasta 0.8 s después de bloquear un golpe, el corte es imparable,
-- hace 16 de daño y aturde 0.9 s.
-- Daño escalado por el arma (katana = referencia). Gasta stamina.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Kenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Kenjutsu")
)

local Iai = {}

Iai.Id = "Iai"
Iai.TechniqueCategory = "Kenjutsu"
Iai.MinimumLevel = 1
Iai.SortOrder = 900

Iai.Config = {
	DisplayName = "Iai",
	TechniqueCategory = "Kenjutsu",
	MinimumLevel = 1,
	SortOrder = 900,

	StaminaCost = 20,
	Cooldown = 8.0,
	CastTime = 0.15,

	Range = 11,
	Arc = 50,
	CounterWindow = 0.8, -- segundos después de bloquear en los que Iai es contraataque

	Hit = {
		Damage = 10,
		SourceId = "Iai",
		GuardDamage = 30,
		Hitstun = 0.45,
		Knockback = 12,
		BlockedKnockback = 10,
	},
	CounterHit = {
		Damage = 16,
		SourceId = "IaiCounter",
		Unblockable = true,
		Hitstun = 0.9,
		Knockback = 20,
		Heavy = true,
	},
}

Iai.MarkerCastTimeout = 3.0
Iai.ProjectileFallbackDelay = 1.0
Iai.MinProjectileDelay = 0

return Kenjutsu.build(Iai, function(context, forward)
	local config = context.Config
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)

	local lastBlocked = character:GetAttribute("LastBlockedAt")
	local isCounter = typeof(lastBlocked) == "number"
		and Workspace:GetServerTimeNow() - lastBlocked <= config.CounterWindow

	Kenjutsu.fxAll("Iai", {
		Character = character,
		Direction = forward,
		Range = config.Range,
		Counter = isCounter,
	})

	local spec = if isCounter then config.CounterHit else config.Hit
	for _, candidate in Kenjutsu.targetsAround(character, forward, config.Range, config.Arc, 5) do
		Kenjutsu.hit(context.Player, candidate.Character, spec)
	end
end)
