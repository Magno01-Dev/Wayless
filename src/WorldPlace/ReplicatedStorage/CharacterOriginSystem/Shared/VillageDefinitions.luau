--!strict
-- ReplicatedStorage > CharacterOriginSystem > Shared > VillageDefinitions

local VillageDefinitions = {}

VillageDefinitions.TargetPopulationShare = 0.20
VillageDefinitions.HealthyPopulationMin = 0.16
VillageDefinitions.HealthyPopulationMax = 0.24
VillageDefinitions.ExtremeSoftCapShare = 0.30

VillageDefinitions.Order = {
	"Leaf",
	"Sand",
	"Mist",
	"Cloud",
	"Stone",
}

VillageDefinitions.ById = {
	Leaf = { Id = "Leaf", DisplayName = "Leaf", Identity = "Balanced" },
	Sand = { Id = "Sand", DisplayName = "Sand", Identity = "Survival / Tactical" },
	Mist = { Id = "Mist", DisplayName = "Mist", Identity = "Assassination / Hunter-Nin" },
	Cloud = { Id = "Cloud", DisplayName = "Cloud", Identity = "Warrior / Verticality" },
	Stone = { Id = "Stone", DisplayName = "Stone", Identity = "Fortress / Military" },
}

function VillageDefinitions.IsValid(villageId: any): boolean
	return typeof(villageId) == "string" and VillageDefinitions.ById[villageId] ~= nil
end

function VillageDefinitions.Get(villageId: string): any?
	return VillageDefinitions.ById[villageId]
end

return VillageDefinitions
