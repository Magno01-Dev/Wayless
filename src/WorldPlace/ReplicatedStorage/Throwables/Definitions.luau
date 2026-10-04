--[[
	Throwables.Definitions · ModuleScript en ReplicatedStorage.Throwables

	Cada arma tiene niveles: [0] = tap, [1..] = etapas de carga (mantener G).
	La identidad está en el patrón y la curva, no solo en el daño:

		Kunai     tap: arco con latigazo       · carga: POTENCIA (rápido, gana choques, clava al objetivo)
		Shuriken  tap: 1 por mano, convergen   · carga: CANTIDAD (2 y 3 por mano, abanico doble)
		Senbon    tap: ráfaga de 3 agujas      · carga: PRECISIÓN (1 aguja a punto vital, 2 acumulaciones)
		Fuma      tap: loop boomerang          · carga: KAGE SHURIKEN (un segundo fuma oculto en su sombra)

	Las claves (Kunai, Shuriken, Senbon, Fuma) deben coincidir con las de ProjectileConfigs,
	que sigue siendo la fuente de NinjaBag / Inventory.

	Curve:
		Lateral  curvatura hacia el costado (fracción de la distancia)
		Lift     curvatura hacia arriba
		Ease     > 0 sale rápido y frena; < 0 sale lento y acelera (entre -0.9 y 0.9)
]]

local Definitions = {}

Definitions.Kunai = {
	Id = "Kunai",
	Asset = "Kunai",
	SubstitutionFolder = "Kunais", -- el sistema de sustitución busca Kunai_* aquí
	SubstitutionPrefix = "Kunai_",
	Visual = {
		Mode = "Point",
		Offset = CFrame.Angles(-math.pi / 2, 0, 0),
		Trail = { Color = Color3.fromRGB(235, 240, 255), Width = 0.28, Lifetime = 0.14 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 1 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.9 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.9 },
	},
	Cooldown = 5,
	Range = 260,
	HitRadius = 1.1,
	EmbedDepth = 0.2,
	Armor = { Penetration = 0.12, DurabilityDamage = 1 },
	Clash = {
		Power = 50, Weight = 1.05, Radius = 0.75, Stability = 2, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 34, WinnerDeflect = 2, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.65, Range = 250 },
	CounterSpeed = 220,
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 150,
			Curve = { Lateral = 0.08, Lift = 0.06, Ease = 0.3 },
			Damage = 12,
		},
		[1] = {
			HoldTime = 0.45,
			Pattern = "Single",
			Speed = 240,
			Curve = { Lateral = 0.03, Lift = 0.02, Ease = 0.15 },
			Damage = 18,
			PowerMultiplier = 2.2, -- gana a todo salvo al fuma
			OnHit = { { Status = "KunaiPin" } },
			Glow = true,
			Trail = { Color = Color3.fromRGB(140, 200, 255), Width = 0.45, Lifetime = 0.2 },
		},
	},
}

Definitions.Shuriken = {
	Id = "Shuriken",
	Asset = "shuriken",
	Visual = {
		Mode = "Flat",
		TargetDiameter = 1.25,
		Spin = math.rad(1260),
		Trail = { Color = Color3.fromRGB(225, 230, 240), Width = 0.12, Lifetime = 0.17 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.92, Speed = 1.08 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.82, Speed = 1.08 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.8, Speed = 1.08 },
	},
	Cooldown = 4,
	Range = 240,
	HitRadius = 0.9,
	EmbedDepth = 0.18,
	Armor = { Penetration = 0.05, DurabilityDamage = 0.45 },
	Clash = {
		Power = 50, Weight = 0.8, Radius = 0.75, Stability = 1, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 38, WinnerDeflect = 6, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.6, Range = 240 },
	CounterSpeed = 230,
	Levels = {
		[0] = {
			Pattern = "Fan",
			Count = 1, -- por mano
			Stagger = 0.03,
			Speed = 165,
			Curve = { Lateral = 0.16, LateralStep = 0.09, Lift = 0.03, Ease = 0.2, TargetSpread = 1.1 },
			Damage = 4,
		},
		[1] = {
			HoldTime = 0.35,
			Pattern = "Fan",
			Count = 2,
			Stagger = 0.03,
			Speed = 165,
			Curve = { Lateral = 0.16, LateralStep = 0.09, Lift = 0.03, Ease = 0.2, TargetSpread = 1.1 },
			Damage = 4,
		},
		[2] = {
			HoldTime = 0.7,
			Pattern = "Fan",
			Count = 3,
			Stagger = 0.03,
			Speed = 165,
			Curve = { Lateral = 0.16, LateralStep = 0.09, Lift = 0.03, Ease = 0.2, TargetSpread = 1.1 },
			Damage = 4,
		},
	},
}

Definitions.Senbon = {
	Id = "Senbon",
	Asset = "senbon",
	Visual = {
		Mode = "Point", -- el eje largo se detecta solo
		Trail = { Color = Color3.fromRGB(255, 255, 255), Width = 0.06, Lifetime = 0.1 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.82, Speed = 1.15 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.72, Speed = 1.15 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.65, Speed = 1.15 },
	},
	Cooldown = 3,
	Range = 280,
	HitRadius = 0.7,
	EmbedDepth = 0.12,
	Armor = { Penetration = 0.25, DurabilityDamage = 0.15 },
	Clash = {
		Power = 45, Weight = 0.45, Radius = 0.55, Stability = 1, StabilityDamage = 1,
		CanBreak = false, MutualDeflect = 42, WinnerDeflect = 12, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2, Angle = 4.5, MaxRadius = 6, Lead = 0.7, Range = 260 },
	CounterSpeed = 260,
	Levels = {
		[0] = {
			Pattern = "Burst",
			Count = 3,
			Stagger = 0.04,
			Spacing = 0.3,
			Speed = 230,
			Curve = { Lateral = 0, Lift = 0.01, Ease = 0.05 },
			Damage = 3,
			OnHit = { { Status = "SenbonNeedle", Stacks = 1, ParalyzeAt = 3, Paralysis = "SenbonParalysis" } },
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Burst",
			Count = 1,
			Stagger = 0,
			Spacing = 0,
			Speed = 320,
			Curve = { Lateral = 0, Lift = 0, Ease = 0 },
			Damage = 6,
			Focus = true, -- el retículo se cierra mientras cargas
			Assist = { MinRadius = 1.5, Angle = 3, MaxRadius = 4, Lead = 0.8, Range = 280 },
			OnHit = { { Status = "SenbonNeedle", Stacks = 2, ParalyzeAt = 3, Paralysis = "SenbonParalysis" } },
		},
	},
}

Definitions.Fuma = {
	Id = "Fuma",
	Asset = "Fuma Shuriken",
	AirAnimation = "Heavy", -- usa Config.AirAnimations.Heavy si tiene ID
	Visual = {
		Mode = "Flat",
		Spin = math.rad(720),
		Trail = { Color = Color3.fromRGB(210, 215, 225), Width = 0.5, Lifetime = 0.22 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 1.1, Speed = 0.82 },
		Travel = { Id = "rbxassetid://138958784062039", Volume = 0.55, Speed = 0.82 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 1.05, Speed = 0.82 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 1, Speed = 0.82 },
	},
	Cooldown = 7,
	Range = 200,
	HitRadius = 2.4,
	EmbedDepth = 0.32,
	Armor = { Penetration = 0.18, DurabilityDamage = 1.55 },
	Clash = {
		Power = 82, Weight = 1.7, Radius = 2.65, Stability = 4, StabilityDamage = 2,
		CanBreak = true, MutualDeflect = 22, WinnerDeflect = 0.75, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 3, Angle = 7, MaxRadius = 9, Lead = 0.55, Range = 200 },
	CounterSpeed = 170,
	Catch = { Radius = 7, Refund = true, CooldownMultiplier = 0.5 },
	Levels = {
		[0] = {
			Pattern = "Boomerang",
			Speed = 95,
			Curve = { Lateral = 0.42, Lift = 0.04, Ease = 0.3 },
			Damage = 20,
			Pierce = true,
		},
		[1] = {
			HoldTime = 0.6,
			Pattern = "Kage",
			Speed = 95,
			Curve = { Lateral = 0.42, Lift = 0.04, Ease = 0.3, Split = 0.55, KageOffset = 2.5, KageLateral = 0.18, KageDelay = 0.08, KageDrop = 0.7 },
			Damage = 20,
			Pierce = true,
		},
	},
}

-- Nivel más alto disponible
function Definitions.maxLevel(definition)
	local level = 0
	while definition.Levels[level + 1] do
		level += 1
	end
	return level
end

return Definitions
