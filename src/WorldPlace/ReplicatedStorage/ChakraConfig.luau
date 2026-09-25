-- ChakraConfig v1.2 - Surface Charge + PvP Trickle Regen
--
-- Chakra is separate from Stamina.
-- C is shared safely: double-tap for Chakra Feet, hold for Chakra Charge.

return {
	MaxChakra = 100,

	Regen = {
		OpenWorld = {
			PerSecond = 4,
			DelayAfterSpend = 1.25,
		},

		CombatTagged = {
			-- Minimal PvP trickle. This is intentionally too low to replace
			-- manual Chakra Charge, but can matter in long situations where
			-- the player cannot safely charge.
			PerSecond = 1,
			DelayAfterSpend = 1.25,
		},

		UpdateInterval = 0.05,
	},

	ChakraFeet = {
		SolidDrainPerSecond = 6,
		WaterDrainPerSecond = 4,
	},

	Charge = {
		KeyCodeName = "C",

		-- Hold duration before Chakra Charge begins.
		-- Short C presses remain available to the Chakra Feet double-tap.
		HoldThreshold = 0.28,

		-- A C press longer than this is NOT counted as a Chakra Feet tap.
		ChakraFeetTapMaxDuration = 0.18,

		PerSecond = 18,

		-- While Chakra Feet is actually maintaining a surface, its normal
		-- drain pauses during Charge. The maintenance cost is instead
		-- subtracted from the normal charge rate:
		--
		-- Solid: 18 - 6 = 12/s
		-- Water: 18 - 4 = 14/s
		UseChakraFeetMaintenancePenalty = true,

		MaxStartHorizontalSpeed = 5,
		CancelHorizontalSpeed = 8,
	},
}
