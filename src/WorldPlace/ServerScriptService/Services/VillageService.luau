--!strict
-- ServerScriptService > Services > VillageService
--
-- WAYLESS common village/affiliation gateway v1.
--
-- OriginVillageId = historical village chosen at Character Creation.
-- AffiliationVillageId = current institutional affiliation.
-- IsRogue = current rogue state.
--
-- Future missions, trainers, exams, guards, bounty, spawns and Threat Rank
-- should query this service instead of duplicating Player attribute checks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CharacterOriginService = require(
	ServerScriptService
		:WaitForChild("Services")
		:WaitForChild("CharacterOriginService")
)

local VillageDefinitions = require(
	ReplicatedStorage
		:WaitForChild("CharacterOriginSystem")
		:WaitForChild("Shared")
		:WaitForChild("VillageDefinitions")
)

local VillageService = {}

function VillageService.IsValidVillage(villageId: any): boolean
	return VillageDefinitions.IsValid(villageId)
end

function VillageService.GetOriginVillage(player: Player): string?
	local data = CharacterOriginService.GetData(player)
	return data and data.OriginVillageId or nil
end

function VillageService.GetAffiliationVillage(player: Player): string?
	local data = CharacterOriginService.GetData(player)
	return data and data.AffiliationVillageId or nil
end

-- Compatibility name: Village means current affiliation.
function VillageService.GetVillage(player: Player): string?
	return VillageService.GetAffiliationVillage(player)
end

function VillageService.IsRogue(player: Player): boolean
	local data = CharacterOriginService.GetData(player)
	return data ~= nil and data.IsRogue == true
end

function VillageService.HasOrigin(player: Player, villageId: string): boolean
	return VillageService.GetOriginVillage(player) == villageId
end

function VillageService.IsAffiliatedWith(player: Player, villageId: string): boolean
	return VillageService.GetAffiliationVillage(player) == villageId
		and not VillageService.IsRogue(player)
end

function VillageService.HasAnyAffiliation(player: Player): boolean
	return VillageService.GetAffiliationVillage(player) ~= nil
		and not VillageService.IsRogue(player)
end

function VillageService.ChooseOriginVillage(
	player: Player,
	villageId: string
): (boolean, string)
	return CharacterOriginService.ChooseVillage(player, villageId)
end

-- Future server-only gameplay hooks.
-- Nothing in this version automatically makes a player Rogue.
function VillageService.SetAffiliation(
	player: Player,
	villageId: string?
): (boolean, string)
	return CharacterOriginService.SetVillageAffiliation(player, villageId)
end

function VillageService.SetRogue(
	player: Player,
	isRogue: boolean
): (boolean, string)
	return CharacterOriginService.SetRogueStatus(player, isRogue)
end

print(
	"[VillageService] READY v1"
		.. " | OriginVillage=ON"
		.. " | CurrentAffiliation=ON"
		.. " | RogueHook=READY"
)

return VillageService
