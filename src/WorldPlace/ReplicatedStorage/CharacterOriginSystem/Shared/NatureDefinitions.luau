--!strict
-- ReplicatedStorage > CharacterOriginSystem > Shared > NatureDefinitions

local NatureDefinitions = {}

NatureDefinitions.AdvantageMultiplier = 1.15
NatureDefinitions.DisadvantageMultiplier = 0.85

NatureDefinitions.Order = {
	"Fire",
	"Wind",
	"Lightning",
	"Earth",
	"Water",
}

NatureDefinitions.ById = {
	Fire = {
		Id = "Fire",
		DisplayName = "Fire",
		JapaneseName = "Katon",
		StatusId = "Burning",
		StrongAgainst = "Wind",
		WeakAgainst = "Water",
	},
	Wind = {
		Id = "Wind",
		DisplayName = "Wind",
		JapaneseName = "Fūton",
		StatusId = "Unsteady",
		StrongAgainst = "Lightning",
		WeakAgainst = "Fire",
	},
	Lightning = {
		Id = "Lightning",
		DisplayName = "Lightning",
		JapaneseName = "Raiton",
		StatusId = "Charged",
		StrongAgainst = "Earth",
		WeakAgainst = "Wind",
	},
	Earth = {
		Id = "Earth",
		DisplayName = "Earth",
		JapaneseName = "Doton",
		StatusId = "Heavy",
		StrongAgainst = "Water",
		WeakAgainst = "Lightning",
	},
	Water = {
		Id = "Water",
		DisplayName = "Water",
		JapaneseName = "Suiton",
		StatusId = "Wet",
		StrongAgainst = "Fire",
		WeakAgainst = "Earth",
	},
}

function NatureDefinitions.IsValid(natureId: any): boolean
	return typeof(natureId) == "string" and NatureDefinitions.ById[natureId] ~= nil
end

function NatureDefinitions.Get(natureId: string): any?
	return NatureDefinitions.ById[natureId]
end

function NatureDefinitions.GetRelation(attackerNatureId: string, defenderNatureId: string): (string, number)
	if attackerNatureId == defenderNatureId then
		return "Neutral", 1
	end

	local attacker = NatureDefinitions.ById[attackerNatureId]
	if not attacker then
		return "Neutral", 1
	end

	if attacker.StrongAgainst == defenderNatureId then
		return "Advantage", NatureDefinitions.AdvantageMultiplier
	end

	if attacker.WeakAgainst == defenderNatureId then
		return "Disadvantage", NatureDefinitions.DisadvantageMultiplier
	end

	return "Neutral", 1
end

return NatureDefinitions
