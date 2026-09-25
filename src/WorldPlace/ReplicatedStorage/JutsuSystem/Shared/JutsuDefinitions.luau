--!strict
-- ReplicatedStorage > JutsuSystem > Shared > JutsuDefinitions

local Definitions = {

	-----------------------------------------------------------------
	-- FIREBALL
	-----------------------------------------------------------------

	Fireball = {
		Id = "Fireball",
		DisplayName = "Fire Style: Fireball Jutsu",

		InputKey = Enum.KeyCode.Z,

		ChakraCost = 25,
		Cooldown = 7.0,
		CastTime = 0.35,

		Aim = {
			MinPitchDegrees = -2,
		},

		Projectile = {
			Speed = 95,
			MaxDistance = 120,
			Radius = 2.5,
			VFXScale = 1.0,
		},

		Damage = 28,

		Armor = {
			Penetration = 0.10,
			DurabilityDamage = 1.0,
		},

		Burn = {
			Enabled = true,
			Duration = 4.0,
			Stacks = 1,
		},
	},

	-----------------------------------------------------------------
	-- HOSENKA
	-----------------------------------------------------------------

	Hosenka = {
		Id = "Hosenka",

		DisplayName =
			"Fire Style: Phoenix Sage Fire Technique",

		InputKey = Enum.KeyCode.V,

		ChakraCost = 22,
		Cooldown = 6.5,
		CastTime = 0.60,

		-- Reutiliza el modelo visual del Fireball.
		VFXModel = "Fireball",

		Aim = {
			MinPitchDegrees = -3,
		},

		Projectile = {
			Count = 5,

			-- Mucho más rápido que Fireball.
			Speed = 155,

			MaxDistance = 105,

			-- Hitbox física más pequeña.
			Radius = 0.85,

			-- Tamaño visual del modelo Fireball reutilizado.
			VFXScale = 0.48,

			-- Salen más rápido entre sí.
			ShotInterval = 0.055,

			Offsets = {
				{
					Yaw = 0,
					Pitch = 1,
				},

				{
					Yaw = -5,
					Pitch = -1,
				},

				{
					Yaw = 5,
					Pitch = -1,
				},

				{
					Yaw = -10,
					Pitch = 2,
				},

				{
					Yaw = 10,
					Pitch = 2,
				},
			},
		},

		Damage = 9,

		MaxHitsPerTarget = 3,

		Armor = {
			Penetration = 0.05,
			DurabilityDamage = 0.65,
		},

		Burn = {
			Enabled = true,
			Duration = 3.0,
			Stacks = 1,
			OncePerTarget = true,
		},
	},
}

return table.freeze(Definitions)