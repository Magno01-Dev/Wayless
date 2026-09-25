--!strict
-- ReplicatedStorage > CharacterOriginSystem > Shared > ClanDefinitions
--
-- WAYLESS approved clan roster v1.
--
-- IMPORTANT:
-- This file only defines clan identity/archetype metadata.
-- No combat stats, buffs, abilities, Hiden, Dōjutsu or KG are granted here.
--
-- Clan is genetic and independent from village affiliation.
-- All eight clans currently use equal generation weight because no rarity
-- distribution has been approved yet.

local ClanDefinitions = {}

ClanDefinitions.Order = {
	"Uchiha",
	"Hyuga",
	"Nara",
	"Akimichi",
	"Aburame",
	"Inuzuka",
	"Hozuki",
	"Uzumaki",
}

ClanDefinitions.ById = {
	Uchiha = {
		Id = "Uchiha",
		DisplayName = "Uchiha",
		Archetype = "ReactiveDuelist",
		Summary = "Duelista reactivo, lectura, predicción, Sharingan y counterplay.",
		GameplayReady = false,
	},

	Hyuga = {
		Id = "Hyuga",
		DisplayName = "Hyūga",
		Archetype = "PrecisionSuppressor",
		Summary = "Precisión, Byakugan, Gentle Fist y supresión de chakra.",
		GameplayReady = false,
	},

	Nara = {
		Id = "Nara",
		DisplayName = "Nara",
		Archetype = "TacticalController",
		Summary = "Control, setups, sombras y castigo táctico.",
		GameplayReady = false,
	},

	Akimichi = {
		Id = "Akimichi",
		DisplayName = "Akimichi",
		Archetype = "BruiserTank",
		Summary = "Bruiser/tank, expansión corporal, knockback y Calorie Reserve.",
		GameplayReady = false,
	},

	Aburame = {
		Id = "Aburame",
		DisplayName = "Aburame",
		Archetype = "ZonerTracker",
		Summary = "Zoning, tracking, drenaje de chakra y Colony.",
		GameplayReady = false,
	},

	Inuzuka = {
		Id = "Inuzuka",
		DisplayName = "Inuzuka",
		Archetype = "RushdownTracker",
		Summary = "Rushdown, tracking, Ninken y presión coordinada.",
		GameplayReady = false,
	},

	Hozuki = {
		Id = "Hozuki",
		DisplayName = "Hōzuki",
		Archetype = "EvasiveRepositioner",
		Summary = "Evasión, Hydrification, reposicionamiento y Hydration.",
		GameplayReady = false,
	},

	Uzumaki = {
		Id = "Uzumaki",
		DisplayName = "Uzumaki",
		Archetype = "SealingSustain",
		Summary = "Sealing, sustain, anti-ability, Seal Marks y Strong Life Force.",
		GameplayReady = false,
	},
}

function ClanDefinitions.IsValid(
	clanId: any
): boolean
	return typeof(clanId) == "string"
		and ClanDefinitions.ById[clanId] ~= nil
end

function ClanDefinitions.Get(
	clanId: string
): any?
	return ClanDefinitions.ById[clanId]
end

function ClanDefinitions.GetDisplayName(
	clanId: string?
): string
	if clanId == nil then
		return "None"
	end

	local definition =
		ClanDefinitions.ById[clanId]

	return definition
		and definition.DisplayName
		or clanId
end

return table.freeze(ClanDefinitions)
