-- ServerScriptService > JutsuSystem > Jutsus > CounterStance
--
-- Taijutsu · Postura de contraataque (rango D, primera capa).
-- 0.5 s de postura. Si te golpean cuerpo a cuerpo (M1, ataque corriendo, patada aérea,
-- launcher o taijutsu) en ese momento: esquivas, apareces a su espalda y le devuelves un
-- golpe imparable (8 de daño, aturde y empuja).
-- Si nadie te ataca, quedas expuesto 0.35 s (aturdido). Gasta stamina.
--
-- Requiere DamageService v1.2 (esquiva el golpe y avisa por CombatInternal > CounterTriggered).

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Taijutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Taijutsu")
)

local CounterStance = {}

CounterStance.Id = "CounterStance"
CounterStance.TechniqueCategory = "Taijutsu"
CounterStance.MinimumLevel = 1
CounterStance.SortOrder = 830

CounterStance.Config = {
	DisplayName = "Counter Stance",
	TechniqueCategory = "Taijutsu",
	MinimumLevel = 1,
	SortOrder = 830,

	StaminaCost = 15,
	Cooldown = 12.0,
	CastTime = 0.15,

	Window = 0.5,
	WhiffStun = 0.35,
	BehindDistance = 3.2,

	Hit = {
		Damage = 8,
		SourceId = "CounterStance",
		Unblockable = true,
		Hitstun = 0.7,
		Knockback = 28,
		Heavy = true,
	},
}

CounterStance.MarkerCastTimeout = 3.0
CounterStance.ProjectileFallbackDelay = 1.0
CounterStance.MinProjectileDelay = 0

local stances: {[Model]: {Token: number, Countered: boolean}} = {}

Taijutsu.onCounter(function(defender: Model, attacker: Player, _sourceType: string)
	local stance = stances[defender]
	local defenderPlayer = Players:GetPlayerFromCharacter(defender)
	local attackerCharacter = attacker.Character
	local defenderRoot = defender:FindFirstChild("HumanoidRootPart")
	local attackerRoot = attackerCharacter and attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not stance or not defenderPlayer or not attackerCharacter
		or not defenderRoot or not attackerRoot then
		return
	end
	stance.Countered = true

	-- Aparece a la espalda del atacante, mirándolo
	local from = defenderRoot.Position
	local behind = (attackerRoot.CFrame * CFrame.new(0, 0, CounterStance.Config.BehindDistance)).Position
	defender:PivotTo(CFrame.lookAt(behind, Vector3.new(attackerRoot.Position.X, behind.Y, attackerRoot.Position.Z)))
	Taijutsu.fxAll("Counter", { Character = defender, From = from, To = behind })

	task.wait(0.05)
	Taijutsu.hit(defenderPlayer, attackerCharacter, CounterStance.Config.Hit)
	Taijutsu.fxAll("Impact", { Position = attackerRoot.Position, Heavy = true })
end)

return Taijutsu.build(CounterStance, function(context)
	local config = context.Config
	local character: Model = context.Character
	local token = (stances[character] and stances[character].Token or 0) + 1
	local stance = { Token = token, Countered = false }
	stances[character] = stance

	character:SetAttribute("CounterStanceUntil", Workspace:GetServerTimeNow() + config.Window)
	Taijutsu.fxAll("Stance", { Character = character, Duration = config.Window })

	task.delay(config.Window + 0.05, function()
		if stances[character] ~= stance then
			return
		end
		stances[character] = nil
		if character.Parent then
			character:SetAttribute("CounterStanceUntil", nil)
		end
		-- Nadie atacó: quedas expuesto
		if not stance.Countered and character.Parent then
			Taijutsu.stun(character, config.WhiffStun, false)
			Taijutsu.fxTo(context.Player, "StanceWhiff", {})
		end
	end)
end)
