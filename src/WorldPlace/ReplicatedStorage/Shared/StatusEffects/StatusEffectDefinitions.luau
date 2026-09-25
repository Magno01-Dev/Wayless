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
}

return table.freeze(Definitions)
