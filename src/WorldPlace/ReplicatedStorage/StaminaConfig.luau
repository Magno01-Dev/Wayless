-- StaminaConfig v1.2 - PvP Tree Jump + Double Jump + Dash
--
-- Open-world Tree Jump remains free.
-- CombatTagged Tree Jump consumes a medium-high amount of Stamina.

return {
	MaxStamina = 100,

	Regen = {
		OpenWorld = {
			PerSecond = 20,
			DelayAfterSpend = 0.75,
		},

		CombatTagged = {
			PerSecond = 10,
			DelayAfterSpend = 2.50,
		},

		UpdateInterval = 0.05,
	},

	Dash = {
		OpenWorld = {
			GroundCost = 30,
			AirCost = 30,
			Cooldown = 0.60,
		},

		Restricted = {
			GroundCost = 30,
			AirCost = 30,
			Cooldown = 2.00,
		},

		RestrictedByCombatMode = true,
		RestrictedByCombatTag = true,
	},

	Actions = {
		DoubleJump = {
			Cost = 10,
		},

		TreeJump = {
			OpenWorldCost = 0,
			CombatTaggedCost = 40,
		},
	},
}
