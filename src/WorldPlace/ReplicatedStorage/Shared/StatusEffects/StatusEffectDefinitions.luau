--!strict
-- ReplicatedStorage > Shared > StatusEffects > StatusEffectDefinitions
-- WAYLESS common status registry.
--
-- Canonical elemental states:
-- Fire -> Burning
-- Wind -> Unsteady
-- Lightning -> Charged
-- Earth -> Heavy
-- Water -> Wet
--
-- Same elemental state refreshes and NEVER stacks.

local Definitions = {
	-----------------------------------------------------------------
	-- EXISTING GENERIC EFFECTS
	-----------------------------------------------------------------

	Poison = {
		DisplayName = "Poison",
		Category = "DamageOverTime",
		DefaultDuration = 8.0,
		TickInterval = 1.0,
		MaxStacks = 3,
		Stacking = "StackRefresh",

		Damage = {
			AmountPerStack = 2.0,
			DamageType = "Poison",
		},

		Flags = {},
		Modifiers = {},
	},

	Bleed = {
		DisplayName = "Bleed",
		Category = "DamageOverTime",
		DefaultDuration = 6.0,
		TickInterval = 0.75,
		MaxStacks = 4,
		Stacking = "StackRefresh",

		Damage = {
			AmountPerStack = 1.25,
			DamageType = "Bleed",
		},

		Flags = {},
		Modifiers = {},
	},

	Slow = {
		DisplayName = "Slow",
		Category = "Control",
		DefaultDuration = 4.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.60,
		},
	},

	Stun = {
		DisplayName = "Stun",
		Category = "HardControl",
		DefaultDuration = 1.25,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			Stunned = true,
			MovementBlocked = true,
			AttackBlocked = true,
		},
		Modifiers = {},
	},

	ChakraSuppression = {
		DisplayName = "Chakra Suppression",
		Category = "ChakraControl",
		DefaultDuration = 6.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			ChakraSuppressed = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {
			ChakraRegenMultiplier = 0.20,
		},
	},

	-----------------------------------------------------------------
	-- CANONICAL ELEMENTAL STATES
	-----------------------------------------------------------------

	Burning = {
		DisplayName = "Burning",
		Category = "Elemental",
		ElementNatureId = "Fire",
		DefaultDuration = 4.0,
		TickInterval = 1.0,
		MaxStacks = 1,
		Stacking = "Refresh",
		PreserveHighestPotency = true,

		Damage = {
			AmountPerStack = 1.0,
			DamageType = "Burning",
		},

		Flags = {},
		Modifiers = {},
	},

	Unsteady = {
		DisplayName = "Unsteady",
		Category = "Elemental",
		ElementNatureId = "Wind",
		DefaultDuration = 3.5,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {},
	},

	Charged = {
		DisplayName = "Charged",
		Category = "Elemental",
		ElementNatureId = "Lightning",
		DefaultDuration = 4.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {},
	},

	Heavy = {
		DisplayName = "Heavy",
		Category = "Elemental",
		ElementNatureId = "Earth",
		DefaultDuration = 4.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {},
	},

	Wet = {
		DisplayName = "Wet",
		Category = "Elemental",
		ElementNatureId = "Water",
		DefaultDuration = 6.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {},
	},
--[[
	Pegar estas entradas DENTRO de la tabla `Definitions` de
	ReplicatedStorage > Shared > StatusEffects > StatusEffectDefinitions
	(por ejemplo, justo antes de la sección "INTERNAL REACTION EFFECT").

	No hace falta tocar StatusEffectService.
]]

	-----------------------------------------------------------------
	-- LANZABLES
	-----------------------------------------------------------------

	-- Kunai cargado: clava al objetivo un instante
	KunaiPin = {
		DisplayName = "Pinned",
		Category = "HardControl",
		DefaultDuration = 0.35,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			MovementBlocked = true,
			AttackBlocked = true,
		},
		Modifiers = {},
	},

	-- Senbon: cada aguja acumula (máx. 3). Al llegar a 3, el servidor la cambia por SenbonParalysis.
	SenbonNeedle = {
		DisplayName = "Needles",
		Category = "Control",
		DefaultDuration = 5.0,
		TickInterval = nil,
		MaxStacks = 3,
		Stacking = "StackRefresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.88,
		},
	},

	SenbonParalysis = {
		DisplayName = "Numbed",
		Category = "HardControl",
		DefaultDuration = 1.2,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			AttackBlocked = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {
			MoveSpeedMultiplier = 0.5,
		},
	},

	-- Mientras se carga un lanzable (mantener G): más lento
	ThrowCharging = {
		DisplayName = "Charging Throw",
		Category = "Self",
		DefaultDuration = 8.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.7,
		},
	},

	-----------------------------------------------------------------
	-- INTERNAL REACTION EFFECT
	-----------------------------------------------------------------

	ElementalMicroStagger = {
		DisplayName = "Micro Stagger",
		Category = "ElementalReaction",
		DefaultDuration = 0.24,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Ignore",

		Flags = {
			Stunned = true,
			MovementBlocked = true,
			AttackBlocked = true,
		},

		Modifiers = {},
	},
	--[[
	Pegar estas entradas DENTRO de la tabla `Definitions` de
	ReplicatedStorage > Shared > StatusEffects > StatusEffectDefinitions
	(por ejemplo, después de las de ninjutsu).

	Clanes · etapa 1 (PLANEACION_CLANES.md).
]]

	-----------------------------------------------------------------
	-- CLANES
	-----------------------------------------------------------------

	-- Sustitución: invisible un momento y más rápido para colocarte (SubstitutionServer)
	SubstitutionVanish = {
		DisplayName = "Vanish",
		Category = "Self",
		DefaultDuration = 0.65,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 1.35,
		},
	},

	-- Amaterasu (Mangekyō de Itachi): llamas negras. Solo marca el estado (lo ve el HUD); el daño lo
	-- hace Jutsus > Amaterasu. No es "Elemental": nada que limpie el fuego normal lo apaga.
	Amaterasu = {
		DisplayName = "Amaterasu",
		Category = "Clan",
		DefaultDuration = 6.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {},
	},

	-- Enton: Black Spear: mientras la lanza se forma en la mano vas más lento
	EntonSpearForming = {
		DisplayName = "Forming Spear",
		Category = "Self",
		DefaultDuration = 2.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.6,
		},
	},

	-- Katon: Gōka Mekkyaku: mientras escupe fuego se queda casi quieto y no puede atacar
	GokaChanneling = {
		DisplayName = "Breathing Fire",
		Category = "Self",
		DefaultDuration = 2.5,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			AttackBlocked = true,
		},
		Modifiers = {
			MoveSpeedMultiplier = 0.05,
		},
	},

	-- Yasaka no Magatama: mientras se forman los magatama en la mano del Susanoo vas más lento
	MagatamaForming = {
		DisplayName = "Forming Magatama",
		Category = "Self",
		DefaultDuration = 2.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.65,
		},
	},

	-- Sharingan / Byakugan activos: no regeneras chakra mientras tengas el dōjutsu
	DojutsuActive = {
		DisplayName = "Dōjutsu",
		Category = "Self",
		DefaultDuration = 3600,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			ChakraRegenMultiplier = 0,
		},
	},

	-- Hyūga (Jūken): tenketsu cerrados, regeneras menos chakra
	TenketsuClosed = {
		DisplayName = "Tenketsu Closed",
		Category = "ChakraControl",
		DefaultDuration = 8.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			ChakraRegenMultiplier = 0.6,
		},
	},

	-- Hyūga (Jūken): 5 tenketsu cerrados, sin chakra un momento
	TenketsuSealed = {
		DisplayName = "Tenketsu Sealed",
		Category = "ChakraControl",
		DefaultDuration = 2.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			ChakraSuppressed = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {},
	},

	-- Uzumaki (Fūin de marcas): sin jutsus ni cargar chakra
	UzumakiSealed = {
		DisplayName = "Sealed (Uzumaki)",
		Category = "ChakraControl",
		DefaultDuration = 3.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			ChakraSuppressed = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {},
	},

	-- Nara (Kagemane): el atrapado no se mueve por su cuenta ni ataca (lo mueve la sombra)
	ShadowBound = {
		DisplayName = "Shadow Bound",
		Category = "HardControl",
		DefaultDuration = 1.5,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			MovementBlocked = true,
			AttackBlocked = true,
		},
		Modifiers = {},
	},

	-- Nara (Kagemane): mientras sostienes la sombra no puedes atacar
	ShadowHolding = {
		DisplayName = "Holding Shadow",
		Category = "Self",
		DefaultDuration = 1.5,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			AttackBlocked = true,
		},
		Modifiers = {},
	},
--[[
	Pegar estas entradas DENTRO de la tabla `Definitions` de
	ReplicatedStorage > Shared > StatusEffects > StatusEffectDefinitions
	(por ejemplo, después de las de los lanzables).

	Category = "Genjutsu": Genjutsu Kai quita todos los estados de esta categoría
	(StatusEffectService.Clear(personaje, "Genjutsu")).
]]

	-----------------------------------------------------------------
	-- GENJUTSU
	-----------------------------------------------------------------

	-- Narakumi: miedo. La visión distorsionada la dibuja GenjutsuClient; esto es la lentitud.
	Narakumi = {
		DisplayName = "Fear",
		Category = "Genjutsu",
		DefaultDuration = 3.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.8,
		},
	},

	-- Tsukuyomi (Mangekyō de Itachi): atrapado en el genjutsu, sin moverse ni atacar. No lo rompen
	-- los golpes (Genjutsu.apply con Unbreakable); el daño lo hace el propio jutsu.
	TsukuyomiBind = {
		DisplayName = "Tsukuyomi",
		Category = "Genjutsu",
		DefaultDuration = 2.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			MovementBlocked = true,
			AttackBlocked = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {},
	},

	-- Genjutsu: Sharingan (Uchiha): paralizado por la mirada. Lo rompe un golpe de 5 o más.
	SharinganBind = {
		DisplayName = "Paralyzed (Sharingan)",
		Category = "Genjutsu",
		DefaultDuration = 1.2,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			MovementBlocked = true,
			AttackBlocked = true,
		},
		Modifiers = {},
	},
--[[
	Pegar esta entrada DENTRO de la tabla `Definitions` de
	ReplicatedStorage > Shared > StatusEffects > StatusEffectDefinitions
	(por ejemplo, después de las de genjutsu).
]]

	-----------------------------------------------------------------
	-- NINJUTSU GENERAL
	-----------------------------------------------------------------

	-- Shōsen no Jutsu: mientras canalizas la curación vas muy lento
	ShosenChannel = {
		DisplayName = "Channeling",
		Category = "Self",
		DefaultDuration = 3.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.35,
		},
	},
--[[
	Pegar estas entradas DENTRO de la tabla `Definitions` de
	ReplicatedStorage > Shared > StatusEffects > StatusEffectDefinitions
	(por ejemplo, justo antes de la sección "INTERNAL REACTION EFFECT").

	No hace falta tocar StatusEffectService.
]]

	-----------------------------------------------------------------
	-- LANZABLES
	-----------------------------------------------------------------

	-- Kunai cargado: clava al objetivo un instante
	KunaiPin = {
		DisplayName = "Pinned",
		Category = "HardControl",
		DefaultDuration = 0.35,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			MovementBlocked = true,
			AttackBlocked = true,
		},
		Modifiers = {},
	},

	-- Senbon: cada aguja acumula (máx. 3). Al llegar a 3, el servidor la cambia por SenbonParalysis.
	SenbonNeedle = {
		DisplayName = "Needles",
		Category = "Control",
		DefaultDuration = 5.0,
		TickInterval = nil,
		MaxStacks = 3,
		Stacking = "StackRefresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.88,
		},
	},

	SenbonParalysis = {
		DisplayName = "Numbed",
		Category = "HardControl",
		DefaultDuration = 1.2,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			AttackBlocked = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {
			MoveSpeedMultiplier = 0.5,
		},
	},

	-- Hilo ninja cargado: atado un instante (no puede moverse ni dashear)…
	WireBind = {
		DisplayName = "Bound",
		Category = "HardControl",
		DefaultDuration = 0.7,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			MovementBlocked = true,
		},
		Modifiers = {},
	},

	-- …y después lento mientras se suelta del hilo
	WireSlow = {
		DisplayName = "Tangled",
		Category = "Control",
		DefaultDuration = 2.2,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.5,
		},
	},

	-- Makibishi: pisar abrojos
	CaltropSlow = {
		DisplayName = "Caltrops",
		Category = "Control",
		DefaultDuration = 1.6,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.55,
		},
	},

	-- Sello de supresión: sin jutsus ni cargar chakra (requiere el JutsuServer de JutsuFixes)
	SealSuppressed = {
		DisplayName = "Sealed",
		Category = "ChakraControl",
		DefaultDuration = 2.5,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			ChakraSuppressed = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {},
	},

	-- Dentro de una zona sellada (se renueva cada 0.1 s mientras sigas dentro)
	SealZone = {
		DisplayName = "Seal Zone",
		Category = "ChakraControl",
		DefaultDuration = 0.4,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {
			ChakraSuppressed = true,
			ChakraChargeBlocked = true,
		},
		Modifiers = {},
	},

	-- Bomba de veneno: el daño lo hace ThrowableServer; esto baja la regeneración de chakra
	Poisoned = {
		DisplayName = "Poisoned",
		Category = "DamageOverTime",
		DefaultDuration = 3.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			ChakraRegenMultiplier = 0.3,
		},
	},

	-- Mientras se carga un lanzable (mantener G): más lento
	ThrowCharging = {
		DisplayName = "Charging Throw",
		Category = "Self",
		DefaultDuration = 8.0,
		TickInterval = nil,
		MaxStacks = 1,
		Stacking = "Refresh",
		Flags = {},
		Modifiers = {
			MoveSpeedMultiplier = 0.7,
		},
	},

}

return table.freeze(Definitions)
