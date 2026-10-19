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

--[[
	LANZABLES DE EFECTO (v3)
	No dependen solo del daño directo: al caer, el servidor crea un efecto (Impact).

		ExplosiveKunai  tap: explota al impactar          · carga: se queda clavado; G lo detona (o solo a los 8 s)
		ExplosiveTag    tap: mina de proximidad visible    · carga: mina oculta (tarda más en armarse)
		NinjaWire       tap: gancho, te jala hacia el ancla · carga: amarra al objetivo (raíz + lentitud)
		Makibishi       tap: abrojos frente a ti           · carga: abrojos lejos, zona más grande
		SmokeBomb       tap: nube donde apuntas            · carga: nube grande a tus pies
		FlashBomb       tap: estalla al impactar           · carga: estalla en el aire donde apuntas

	Campos nuevos:
		Utility     no hace daño directo: no cuenta como amenaza para el contraataque
		NoCounter   con esta arma seleccionada, G nunca hace contraataque
		Explosion   daño en área (Radius, Damage, MinFalloff, Knockback, Lift)
		Levels[n].Range   alcance propio del nivel (si no, el del arma)
		Levels[n].NoTail  el proyectil termina en el punto de destino (no sigue de largo)
		Levels[n].Lob     parábola: pasado el destino cae con gravedad (nunca sigue hacia arriba)
		Levels[n].AtFeet  el destino es el suelo bajo tus pies
		Levels[n].Impact  qué pasa al caer:
			Kind      Explode | StickyTag | Mine | Anchor | Bind | Caltrops | Smoke | Flash
			          Suppress | SealZone | Mark | Poison (v3.1)
			OnWorld   al tocar el mundo        OnBody  al tocar a alguien
			OnEnd     al terminar el camino    Fuse    a los N s de vuelo (estalla donde esté)
			OnClash   si choca con otro proyectil, se activa ahí
]]

Definitions.ExplosiveKunai = {
	Id = "ExplosiveKunai",
	Asset = "Kunai",
	Visual = {
		Mode = "Point",
		Offset = CFrame.Angles(-math.pi / 2, 0, 0),
		Decoration = "TagWrap", -- sello de papel envuelto en el kunai
		Trail = { Color = Color3.fromRGB(255, 190, 120), Width = 0.3, Lifetime = 0.16 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 1, Speed = 0.95 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.9 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.9 },
	},
	Cooldown = 9,
	Range = 220,
	HitRadius = 1.1,
	EmbedDepth = 0.2,
	Armor = { Penetration = 0.12, DurabilityDamage = 1 },
	Clash = {
		Power = 45, Weight = 1, Radius = 0.75, Stability = 1, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 34, WinnerDeflect = 2, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.6, Range = 210 },
	CounterSpeed = 210,
	Explosion = {
		Radius = 9,
		Damage = 22,
		MinFalloff = 0.5, -- en el borde hace el 50 %
		Knockback = 38,
		Lift = 18,
		Armor = { Penetration = 0.3, DurabilityDamage = 1.5 },
	},
	Sticky = {
		MaxArmed = 2, -- sellos clavados a la vez por jugador
		WorldFuse = 8, -- clavado en el mundo: explota solo a los 8 s
		BodyFuse = 2.5, -- clavado en alguien: explota a los 2.5 s
	},
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 125,
			Curve = { Lateral = 0.06, Lift = 0.08, Ease = 0.25 },
			Damage = 6,
			Impact = { Kind = "Explode", OnWorld = true, OnBody = true, OnClash = true },
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Single",
			Speed = 150,
			Curve = { Lateral = 0.03, Lift = 0.04, Ease = 0.15 },
			Damage = 8,
			Glow = true,
			Trail = { Color = Color3.fromRGB(255, 140, 80), Width = 0.4, Lifetime = 0.2 },
			Impact = { Kind = "StickyTag", OnWorld = true, OnBody = true, OnClash = true },
		},
	},
}

Definitions.ExplosiveTag = {
	Id = "ExplosiveTag",
	Asset = "", -- se dibuja por código (Visual.Procedural)
	Utility = true,
	NoCounter = true,
	Visual = {
		Mode = "Flat",
		Procedural = "Tag",
		Spin = math.rad(540),
		Trail = { Color = Color3.fromRGB(255, 220, 170), Width = 0.12, Lifetime = 0.12 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.7, Speed = 1.25 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.6, Speed = 1.4 },
	},
	Cooldown = 12,
	Range = 30,
	HitRadius = 0.8,
	EmbedDepth = 0,
	Assist = { MinRadius = 0, Angle = 0, MaxRadius = 0, Lead = 0, Range = 0 },
	Explosion = {
		Radius = 10,
		Damage = 26,
		MinFalloff = 0.5,
		Knockback = 42,
		Lift = 22,
		Armor = { Penetration = 0.3, DurabilityDamage = 1.5 },
	},
	Mine = {
		MaxArmed = 2, -- minas a la vez por jugador (la más vieja desaparece)
		TriggerRadius = 5.5,
		FuseDelay = 0.45, -- tiempo entre pisarla y la explosión (sisea y brilla)
		Lifetime = 45,
	},
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 70,
			Range = 30,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.28, Ease = -0.1 },
			Damage = 0,
			Impact = { Kind = "Mine", OnWorld = true, OnBody = true, ArmTime = 1.0, Hidden = false },
		},
		[1] = {
			HoldTime = 0.6,
			Pattern = "Single",
			Speed = 70,
			Range = 30,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.28, Ease = -0.1 },
			Damage = 0,
			Impact = { Kind = "Mine", OnWorld = true, OnBody = true, ArmTime = 2.0, Hidden = true },
		},
	},
}

Definitions.NinjaWire = {
	Id = "NinjaWire",
	Asset = "Kunai",
	NoCounter = true,
	Visual = {
		Mode = "Point",
		Offset = CFrame.Angles(-math.pi / 2, 0, 0),
		Wire = true, -- hilo desde la mano del lanzador hasta el kunai
		Trail = { Color = Color3.fromRGB(220, 225, 235), Width = 0.12, Lifetime = 0.1 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.9, Speed = 1.2 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.8 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.9, Speed = 1.1 },
	},
	Cooldown = 8,
	Range = 85,
	HitRadius = 1,
	EmbedDepth = 0.25,
	Armor = { Penetration = 0.1, DurabilityDamage = 0.5 },
	Clash = {
		Power = 40, Weight = 0.9, Radius = 0.7, Stability = 1, StabilityDamage = 1,
		CanBreak = false, MutualDeflect = 34, WinnerDeflect = 4, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 7, Lead = 0.65, Range = 85 },
	CounterSpeed = 200,
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 190,
			Curve = { Lateral = 0.02, Lift = 0.02, Ease = 0.1 },
			Damage = 5,
			Impact = {
				Kind = "Anchor",
				OnWorld = true,
				PullSpeed = 95,
				MaxPullTime = 1.1,
			},
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Single",
			Speed = 200,
			Curve = { Lateral = 0.02, Lift = 0.02, Ease = 0.1 },
			Damage = 6,
			Impact = {
				Kind = "Bind",
				OnBody = true,
				RootStatus = "WireBind", -- raíz corta (bloquea moverse y el dash)
				SlowStatus = "WireSlow", -- lentitud después
				TetherTime = 2.2, -- cuánto se ve el hilo atado
			},
		},
	},
}

Definitions.Makibishi = {
	Id = "Makibishi",
	Asset = "",
	Utility = true,
	NoCounter = true,
	Visual = {
		Mode = "Point",
		Procedural = "Pouch",
		Trail = { Color = Color3.fromRGB(150, 140, 125), Width = 0.1, Lifetime = 0.1 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.6, Speed = 1.3 },
	},
	Cooldown = 10,
	Range = 45,
	HitRadius = 0.8,
	EmbedDepth = 0,
	Assist = { MinRadius = 0, Angle = 0, MaxRadius = 0, Lead = 0, Range = 0 },
	Field = {
		Damage = 3,
		SlowStatus = "CaltropSlow",
		HitInterval = 1.0, -- cada cuánto puede volver a herir a la misma persona
		Height = 3.6, -- altura máxima de los pies sobre el suelo para pisarlos (saltar los evita)
	},
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 60,
			Range = 16,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.3, Ease = -0.1 },
			Damage = 0,
			Impact = { Kind = "Caltrops", OnWorld = true, OnBody = true, Radius = 6, Duration = 12, Count = 16 },
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Single",
			Speed = 75,
			Range = 45,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.3, Ease = -0.1 },
			Damage = 0,
			Impact = { Kind = "Caltrops", OnWorld = true, OnBody = true, Radius = 8, Duration = 12, Count = 24 },
		},
	},
}

Definitions.SmokeBomb = {
	Id = "SmokeBomb",
	Asset = "",
	Utility = true,
	NoCounter = true,
	Visual = {
		Mode = "Point",
		Procedural = "Ball",
		Color = Color3.fromRGB(70, 70, 75),
		Trail = { Color = Color3.fromRGB(170, 170, 170), Width = 0.15, Lifetime = 0.12 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.6, Speed = 1.2 },
	},
	Cooldown = 20,
	Range = 45,
	HitRadius = 0.8,
	EmbedDepth = 0,
	Assist = { MinRadius = 0, Angle = 0, MaxRadius = 0, Lead = 0, Range = 0 },
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 80,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.22, Ease = -0.05 },
			Damage = 0,
			Impact = { Kind = "Smoke", OnWorld = true, OnBody = true, Radius = 12, Duration = 7 },
		},
		[1] = {
			HoldTime = 0.4,
			Pattern = "Single",
			Speed = 60,
			AtFeet = true,
			Curve = { Lateral = 0, Lift = 0.05, Ease = 0 },
			Damage = 0,
			Impact = { Kind = "Smoke", OnWorld = true, OnBody = true, OnEnd = true, Radius = 16, Duration = 8 },
		},
	},
}

Definitions.FlashBomb = {
	Id = "FlashBomb",
	Asset = "",
	Utility = true,
	NoCounter = true,
	Visual = {
		Mode = "Point",
		Procedural = "Ball",
		Color = Color3.fromRGB(235, 225, 200),
		Trail = { Color = Color3.fromRGB(255, 250, 230), Width = 0.15, Lifetime = 0.12 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.6, Speed = 1.2 },
	},
	Cooldown = 18,
	Range = 60,
	HitRadius = 0.8,
	EmbedDepth = 0,
	Assist = { MinRadius = 0, Angle = 0, MaxRadius = 0, Lead = 0, Range = 0 },
	Flash = {
		ConeAngle = 70, -- medio ángulo: ciega si miras a menos de 70° de la luz (cono de 140°)
	},
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 110,
			Curve = { Lateral = 0, Lift = 0.12, Ease = 0 },
			Damage = 0,
			Impact = { Kind = "Flash", OnWorld = true, OnBody = true, Fuse = 1.3, Radius = 45, Duration = 1.6 },
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Single",
			Speed = 110,
			Range = 60,
			NoTail = true,
			Curve = { Lateral = 0, Lift = 0.12, Ease = 0 },
			Damage = 0,
			Impact = { Kind = "Flash", OnWorld = true, OnBody = true, OnEnd = true, Radius = 55, Duration = 2 },
		},
	},
}

--[[
	v3.1
		ChakraSeal   tap: sello de supresión: sin jutsus ni cargar chakra 2.5 s · carga: zona sellada en el suelo
		TrackerSeal  tap: marca 20 s (el que lanza ve al marcado a través de paredes) · carga: marca de 45 s
		PoisonBomb   tap: nube de veneno (daño por segundo + menos regeneración de chakra) · carga: nube grande y larga
]]

Definitions.ChakraSeal = {
	Id = "ChakraSeal",
	Asset = "",
	NoCounter = true,
	Visual = {
		Mode = "Flat",
		Procedural = "Tag",
		Kanji = "封", -- "sellar"
		Ink = Color3.fromRGB(60, 70, 190),
		Spin = math.rad(720),
		Trail = { Color = Color3.fromRGB(140, 160, 255), Width = 0.14, Lifetime = 0.14 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.7, Speed = 1.3 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.6, Speed = 1.3 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.6, Speed = 1.4 },
	},
	Cooldown = 14,
	Range = 120,
	HitRadius = 1,
	EmbedDepth = 0,
	Armor = { Penetration = 0, DurabilityDamage = 0.2 },
	Clash = {
		Power = 30, Weight = 0.5, Radius = 0.6, Stability = 1, StabilityDamage = 1,
		CanBreak = false, MutualDeflect = 40, WinnerDeflect = 10, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.65, Range = 120 },
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 150,
			Curve = { Lateral = 0.06, Lift = 0.04, Ease = 0.2 },
			Damage = 2,
			Impact = { Kind = "Suppress", OnBody = true, Status = "SealSuppressed", Duration = 2.5 },
		},
		[1] = {
			HoldTime = 0.6,
			Pattern = "Single",
			Speed = 80,
			Range = 40,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.25, Ease = -0.1 },
			Damage = 0,
			-- Zona: quien esté dentro (menos el que la puso) no puede hacer jutsus ni cargar chakra
			Impact = { Kind = "SealZone", OnWorld = true, OnBody = true, Status = "SealZone", Radius = 8, Duration = 6 },
		},
	},
}

Definitions.TrackerSeal = {
	Id = "TrackerSeal",
	Asset = "",
	NoCounter = true,
	Visual = {
		Mode = "Flat",
		Procedural = "Tag",
		Kanji = "追", -- "perseguir"
		Ink = Color3.fromRGB(190, 90, 20),
		Spin = math.rad(720),
		Trail = { Color = Color3.fromRGB(255, 170, 90), Width = 0.12, Lifetime = 0.12 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.7, Speed = 1.35 },
		Hit = { Id = "rbxassetid://2782131222", Volume = 0.5, Speed = 1.4 },
		Stick = { Id = "rbxassetid://9116197517", Volume = 0.6, Speed = 1.4 },
	},
	Cooldown = 12,
	Range = 160,
	HitRadius = 1,
	EmbedDepth = 0,
	Armor = { Penetration = 0, DurabilityDamage = 0.2 },
	Clash = {
		Power = 30, Weight = 0.5, Radius = 0.6, Stability = 1, StabilityDamage = 1,
		CanBreak = false, MutualDeflect = 40, WinnerDeflect = 10, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.7, Range = 160 },
	Mark = {
		MaxMarks = 2, -- personas marcadas a la vez por jugador (la marca más vieja se borra)
	},
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 170,
			Curve = { Lateral = 0.05, Lift = 0.03, Ease = 0.2 },
			Damage = 3,
			Impact = { Kind = "Mark", OnBody = true, Duration = 20 },
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Single",
			Speed = 120,
			Curve = { Lateral = 0.05, Lift = 0.05, Ease = 0.2 },
			Damage = 1,
			Impact = { Kind = "Mark", OnBody = true, Duration = 45 },
		},
	},
}

Definitions.PoisonBomb = {
	Id = "PoisonBomb",
	Asset = "",
	Utility = true,
	NoCounter = true,
	Visual = {
		Mode = "Point",
		Procedural = "Ball",
		Color = Color3.fromRGB(95, 60, 120),
		Trail = { Color = Color3.fromRGB(150, 200, 90), Width = 0.15, Lifetime = 0.12 },
	},
	Audio = {
		Launch = { Id = "rbxassetid://138958784062039", Volume = 0.6, Speed = 1.2 },
	},
	Cooldown = 16,
	Range = 45,
	HitRadius = 0.8,
	EmbedDepth = 0,
	Assist = { MinRadius = 0, Angle = 0, MaxRadius = 0, Lead = 0, Range = 0 },
	Poison = {
		Status = "Poisoned", -- menos regeneración de chakra (StatusEffectDefinitions)
		TickInterval = 0.5,
		Linger = 3, -- segundos que sigue haciendo daño después de salir de la nube
	},
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 80,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.22, Ease = -0.05 },
			Damage = 0,
			Impact = { Kind = "Poison", OnWorld = true, OnBody = true, Radius = 9, Duration = 7, TickDamage = 2 },
		},
		[1] = {
			HoldTime = 0.5,
			Pattern = "Single",
			Speed = 75,
			Lob = true,
			Curve = { Lateral = 0, Lift = 0.22, Ease = -0.05 },
			Damage = 0,
			Impact = { Kind = "Poison", OnWorld = true, OnBody = true, Radius = 13, Duration = 10, TickDamage = 1.5 },
		},
	},
}

--[[
	SHURIKENJUTSU (v3.2)
	Proyectiles de las técnicas de shurikenjutsu. No van en la Ninja Bag (Technique = true):
	los lanza el servidor cuando un jutsu (JutsuSystem > Jutsus) llega a su marcador de salida,
	a través de ServerStorage > ThrowablesInternal > SpawnTechnique. La munición la gasta el jutsu.

		Tech_KageShuriken  Shuriken Kage Bunshin: 1 shuriken que se multiplica en 6 (patrón Split)
		Tech_Sofusha       Sōfūsha San no Tachi: 3 shurikens con hilo que rodean y atan (patrón Surround)
		Tech_KunaiRain     Lluvia de kunai: sube y cae sobre una zona marcada (patrón Rain)
		Tech_Soshujin      Kunai guiado: con la tecla del jutsu se redirige 1 vez en vuelo (Redirect)
]]

local SHURIKEN_AUDIO = {
	Launch = { Id = "rbxassetid://138958784062039", Volume = 0.92, Speed = 1.08 },
	Hit = { Id = "rbxassetid://2782131222", Volume = 0.82, Speed = 1.08 },
	Stick = { Id = "rbxassetid://9116197517", Volume = 0.8, Speed = 1.08 },
}

local KUNAI_AUDIO = {
	Launch = { Id = "rbxassetid://138958784062039", Volume = 1 },
	Hit = { Id = "rbxassetid://2782131222", Volume = 0.9 },
	Stick = { Id = "rbxassetid://9116197517", Volume = 0.9 },
}

Definitions.Tech_KageShuriken = {
	Id = "Tech_KageShuriken",
	Technique = true,
	Asset = "shuriken",
	Visual = {
		Mode = "Flat",
		TargetDiameter = 1.25,
		Spin = math.rad(1260),
		Trail = { Color = Color3.fromRGB(200, 215, 255), Width = 0.12, Lifetime = 0.17 },
	},
	Audio = SHURIKEN_AUDIO,
	Range = 200,
	HitRadius = 0.9,
	EmbedDepth = 0.18,
	Armor = { Penetration = 0.05, DurabilityDamage = 0.45 },
	Clash = {
		Power = 50, Weight = 0.8, Radius = 0.75, Stability = 1, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 38, WinnerDeflect = 6, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.6, Range = 200 },
	Levels = {
		[0] = {
			Pattern = "Split",
			Count = 6, -- el original + 5 copias
			Speed = 165,
			Curve = { Lateral = 0.04, Lift = 0.03, Ease = 0.2, Split = 0.3, Spread = 1.6 },
			Damage = 5,
		},
	},
}

Definitions.Tech_Sofusha = {
	Id = "Tech_Sofusha",
	Technique = true,
	Asset = "shuriken",
	Visual = {
		Mode = "Flat",
		TargetDiameter = 1.5,
		Spin = math.rad(1080),
		Wire = true,
		Trail = { Color = Color3.fromRGB(225, 230, 240), Width = 0.14, Lifetime = 0.17 },
	},
	Audio = SHURIKEN_AUDIO,
	Range = 110,
	HitRadius = 1,
	EmbedDepth = 0.18,
	Armor = { Penetration = 0.08, DurabilityDamage = 0.6 },
	Clash = {
		Power = 55, Weight = 0.9, Radius = 0.8, Stability = 1, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 36, WinnerDeflect = 5, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 3, Angle = 7, MaxRadius = 9, Lead = 0.7, Range = 110 },
	Levels = {
		[0] = {
			Pattern = "Surround",
			Speed = 120,
			Stagger = 0.04,
			Curve = { Lateral = 0.55, Lift = 0.1, Ease = 0.1 },
			Damage = 6,
			Impact = {
				Kind = "Bind",
				OnBody = true,
				OncePerThrow = true, -- 3 shurikens, una sola atadura
				RootStatus = "WireBind",
				SlowStatus = "WireSlow",
				TetherTime = 2.2,
			},
		},
	},
}

Definitions.Tech_KunaiRain = {
	Id = "Tech_KunaiRain",
	Technique = true,
	Asset = "Kunai",
	Visual = {
		Mode = "Point",
		Offset = CFrame.Angles(-math.pi / 2, 0, 0),
		Trail = { Color = Color3.fromRGB(235, 240, 255), Width = 0.22, Lifetime = 0.12 },
	},
	Audio = KUNAI_AUDIO,
	Range = 90,
	HitRadius = 1,
	EmbedDepth = 0.25,
	Armor = { Penetration = 0.12, DurabilityDamage = 1 },
	Clash = {
		Power = 50, Weight = 1, Radius = 0.7, Stability = 1, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 34, WinnerDeflect = 2, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 3, Angle = 6, MaxRadius = 8, Lead = 0.9, Range = 90 },
	Telegraph = true, -- marca el suelo donde va a caer
	Levels = {
		[0] = {
			Pattern = "Rain",
			Count = 10, -- 5 kunai reales multiplicados con chakra
			Speed = 140,
			Stagger = 0.03,
			Curve = { Lateral = 0, Lift = 0, Ease = 0 },
			Rain = {
				Radius = 6,
				RiseHeight = 28,
				DropHeight = 45,
				FallSpeed = 150,
				FallDelay = 0.6,
			},
			Damage = 7,
		},
	},
}

Definitions.Tech_Soshujin = {
	Id = "Tech_Soshujin",
	Technique = true,
	Asset = "Kunai",
	Visual = {
		Mode = "Point",
		Offset = CFrame.Angles(-math.pi / 2, 0, 0),
		Wire = true,
		Trail = { Color = Color3.fromRGB(170, 210, 255), Width = 0.3, Lifetime = 0.18 },
	},
	Audio = KUNAI_AUDIO,
	Range = 160,
	HitRadius = 1.1,
	EmbedDepth = 0.2,
	Armor = { Penetration = 0.12, DurabilityDamage = 1 },
	Clash = {
		Power = 55, Weight = 1.05, Radius = 0.75, Stability = 2, StabilityDamage = 1,
		CanBreak = true, MutualDeflect = 34, WinnerDeflect = 2, BreakRatio = 1.3,
	},
	Assist = { MinRadius = 2.5, Angle = 6, MaxRadius = 8, Lead = 0.65, Range = 160 },
	Levels = {
		[0] = {
			Pattern = "Single",
			Speed = 150,
			Curve = { Lateral = 0.05, Lift = 0.04, Ease = 0.2 },
			Damage = 14,
			Redirect = {
				Speed = 210, -- velocidad después de redirigirlo
				MaxDistance = 220, -- el nuevo destino no puede estar más lejos que esto del lanzador
			},
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
