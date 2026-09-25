--!strict
-- ReplicatedStorage > CharacterOriginSystem > Shared > ElementalReactionDefinitions
-- WAYLESS canonical 10 basic-element interactions.
-- These are reactions, NOT Kekkei Genkai.

local Definitions = {}

Definitions.Order = {
	"FanTheFlames",
	"Overheat",
	"ScorchedGround",
	"SteamBurst",
	"ChargedCurrent",
	"DustCloud",
	"PressurizedFlow",
	"Fracture",
	"Conductive",
	"Mud",
}

Definitions.ById = {
	FanTheFlames = {
		Id = "FanTheFlames",
		DisplayName = "Fan the Flames",
		Natures = {"Fire", "Wind"},
		Intent = "Expand or potentiate fire area/range.",
		Behavior = "TechniqueHook",
	},

	Overheat = {
		Id = "Overheat",
		DisplayName = "Overheat",
		Natures = {"Fire", "Lightning"},
		Intent = "Burst / explosion / knockback.",
		Behavior = "TechniqueHook",
	},

	ScorchedGround = {
		Id = "ScorchedGround",
		DisplayName = "Scorched Ground",
		Natures = {"Fire", "Earth"},
		Intent = "Area denial / Doton structure pressure.",
		Behavior = "TechniqueHook",
	},

	SteamBurst = {
		Id = "SteamBurst",
		DisplayName = "Steam Burst",
		Natures = {"Fire", "Water"},
		Intent = "Dense steam / vision denial.",
		Behavior = "TechniqueHook",
	},

	ChargedCurrent = {
		Id = "ChargedCurrent",
		DisplayName = "Charged Current",
		Natures = {"Wind", "Lightning"},
		Intent = "Extended electricity / arcs / pressure.",
		Behavior = "TechniqueHook",
	},

	DustCloud = {
		Id = "DustCloud",
		DisplayName = "Dust Cloud",
		Natures = {"Wind", "Earth"},
		Intent = "Concealment / disruption.",
		Behavior = "TechniqueHook",
	},

	PressurizedFlow = {
		Id = "PressurizedFlow",
		DisplayName = "Pressurized Flow",
		Natures = {"Wind", "Water"},
		Intent = "Faster / sharper water.",
		Behavior = "TechniqueHook",
	},

	Fracture = {
		Id = "Fracture",
		DisplayName = "Fracture",
		Natures = {"Lightning", "Earth"},
		Intent = "Crack / break terrestrial defenses.",
		Behavior = "TechniqueHook",
	},

	Conductive = {
		Id = "Conductive",
		DisplayName = "Conductive",
		Natures = {"Lightning", "Water"},
		Intent = "Chain shock / controlled micro-stagger.",
		Behavior = "ConductiveMicroStagger",
	},

	Mud = {
		Id = "Mud",
		DisplayName = "Mud",
		Natures = {"Earth", "Water"},
		Intent = "Movement / dash control.",
		Behavior = "TechniqueHook",
	},
}

local function pairKey(
	a: string,
	b: string
): string
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end

Definitions.ByPair = {}

for _, id in ipairs(Definitions.Order) do
	local def = Definitions.ById[id]
	Definitions.ByPair[
	pairKey(
		def.Natures[1],
		def.Natures[2]
	)
	] = def
end

function Definitions.GetByNatures(
	a: string,
	b: string
): any?
	if a == b then
		return nil
	end
	return Definitions.ByPair[
	pairKey(a, b)
	]
end

return table.freeze(Definitions)
