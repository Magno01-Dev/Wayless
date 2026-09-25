--!strict
-- ServerScriptService > Services > CharacterRequirementService
--
-- WAYLESS generic character requirement gateway v1.
--
-- IMPORTANT ARCHITECTURE RULE:
-- Systems should NOT duplicate origin checks such as:
--     if player:GetAttribute("NatureUnlocked_Fire") then ...
--
-- Instead, any server system that needs Character Origin information should
-- submit declarative requirements through this service.
--
-- This keeps:
-- - Jutsus
-- - trainers
-- - learning systems
-- - village content
-- - future clans / KG / disciplines
-- using one authorization path.
--
-- Current v1.3 supports:
-- - progression level
-- - innate/unlocked/primary nature
-- - village/origin/affiliation/Rogue
-- - clan
-- - Natural KG potential / available KG identity
-- - learned-technique dependencies
--
-- Requirements stay declarative so UI, learning and casting share one gate.

local ServerScriptService =
	game:GetService("ServerScriptService")

local services =
	ServerScriptService:
	WaitForChild("Services")

local DeveloperAccessService = require(
	services:
		WaitForChild("DeveloperAccessService")
)

local CharacterOriginService = require(
	services:
		WaitForChild("CharacterOriginService")
)

local VillageService = require(
	services:
		WaitForChild("VillageService")
)

local CharacterRequirementService = {}

type RequirementTable = {
	MinimumLevel: number?,
	MaximumLevel: number?,

	UnlockedNatureId: string?,
	UnlockedNatureIds: {string}?,
	AnyUnlockedNatureIds: {string}?,

	InnateNatureId: string?,
	InnateNatureIds: {string}?,
	AnyInnateNatureIds: {string}?,

	PrimaryNatureId: string?,
	PrimaryNatureIds: {string}?,

	ClanId: string?,
	ClanIds: {string}?,

	RequiresNaturalKGPotential: boolean?,
	NaturalKGId: string?,
	NaturalKGIds: {string}?,

	RequiredTechniqueId: string?,
	RequiredTechniqueIds: {string}?,

	-- Compatibility aliases for current affiliation.
	VillageId: string?,
	VillageIds: {string}?,

	AffiliationVillageId: string?,
	AffiliationVillageIds: {string}?,

	OriginVillageId: string?,
	OriginVillageIds: {string}?,

	Rogue: boolean?,
}

local ORIGIN_REQUIREMENT_KEYS = {
	UnlockedNatureId = true,
	UnlockedNatureIds = true,
	AnyUnlockedNatureIds = true,

	InnateNatureId = true,
	InnateNatureIds = true,
	AnyInnateNatureIds = true,

	PrimaryNatureId = true,
	PrimaryNatureIds = true,

	ClanId = true,
	ClanIds = true,

	RequiresNaturalKGPotential = true,
	NaturalKGId = true,
	NaturalKGIds = true,

	VillageId = true,
	VillageIds = true,

	AffiliationVillageId = true,
	AffiliationVillageIds = true,

	OriginVillageId = true,
	OriginVillageIds = true,

	Rogue = true,
}

local function hasOriginRequirements(
	requirements: any
): boolean
	if typeof(requirements) ~= "table" then
		return false
	end

	for key in pairs(
		ORIGIN_REQUIREMENT_KEYS
		) do
		if requirements[key] ~= nil then
			return true
		end
	end

	return false
end

local function contains(
	list: any,
	value: string
): boolean
	if typeof(list) ~= "table" then
		return false
	end

	for _, candidate in ipairs(list) do
		if candidate == value then
			return true
		end
	end

	return false
end

local function fail(
	reason: string,
	details: any?
): (boolean, string, any?)
	return false, reason, details
end

local function getCharacterLevel(
	player: Player
): number?
	local raw =
		player:GetAttribute(
			"CharacterLevel"
		)

	if typeof(raw) ~= "number" then
		return nil
	end

	return math.floor(raw)
end

local function hasLearnedTechnique(
	player: Player,
	techniqueId: string
): boolean
	local folder =
		player:FindFirstChild(
			"LearnedTechniques"
		)

	if not folder
		or not folder:IsA(
			"Folder"
		) then

		return false
	end

	local marker =
		folder:FindFirstChild(
			techniqueId
		)

	return marker ~= nil
end

function CharacterRequirementService.Check(
	player: Player,
	requirements: RequirementTable?
): (boolean, string, any?)

	if typeof(requirements) ~= "table"
		or next(requirements) == nil then

		return true, "Allowed", nil
	end

	-----------------------------------------------------------------
	-- CENTRALIZED DEVELOPER CONTENT BYPASS
	--
	-- This bypasses declarative CONTENT requirements only.
	-- Combat/chakra/cooldown/state validation remains untouched.
	-----------------------------------------------------------------

	if DeveloperAccessService.HasContentBypass(
		player
		) then

		return true,
			"DeveloperBypass",
			{
				DeveloperBypass =
				true,
			}
	end

	-----------------------------------------------------------------
	-- PROGRESSION LEVEL
	-----------------------------------------------------------------

	if requirements.MinimumLevel ~= nil
		or requirements.MaximumLevel ~= nil then

		local level =
			getCharacterLevel(
				player
			)

		if level == nil then
			return fail(
				"ProgressionNotReady",
				nil
			)
		end

		if requirements.MinimumLevel ~= nil
			and level
			< requirements.MinimumLevel then

			return fail(
				"LevelTooLow",
				{
					CurrentLevel =
						level,

					RequiredLevel =
						requirements.MinimumLevel,
				}
			)
		end

		if requirements.MaximumLevel ~= nil
			and level
			> requirements.MaximumLevel then

			return fail(
				"LevelTooHigh",
				{
					CurrentLevel =
						level,

					MaximumLevel =
						requirements.MaximumLevel,
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- ORIGIN READINESS
	-----------------------------------------------------------------

	if hasOriginRequirements(requirements) then
		if player:GetAttribute(
			"CharacterOriginReady"
			) ~= true then

			return fail(
				"OriginNotReady",
				nil
			)
		end
	end

	-----------------------------------------------------------------
	-- UNLOCKED NATURE
	-----------------------------------------------------------------

	local unlockedNatureId =
		requirements.UnlockedNatureId

	if unlockedNatureId ~= nil then
		if not CharacterOriginService.CanUseNature(
			player,
			unlockedNatureId
			) then

			return fail(
				"MissingUnlockedNature",
				{
					RequiredNatureId =
						unlockedNatureId,
				}
			)
		end
	end

	local unlockedNatureIds =
		requirements.UnlockedNatureIds

	if unlockedNatureIds ~= nil then
		for _, natureId in ipairs(
			unlockedNatureIds
			) do
			if not CharacterOriginService.CanUseNature(
				player,
				natureId
				) then

				return fail(
					"MissingUnlockedNature",
					{
						RequiredNatureId =
							natureId,
					}
				)
			end
		end
	end

	local anyUnlocked =
		requirements.AnyUnlockedNatureIds

	if anyUnlocked ~= nil then
		local found = false

		for _, natureId in ipairs(
			anyUnlocked
			) do
			if CharacterOriginService.CanUseNature(
				player,
				natureId
				) then

				found = true
				break
			end
		end

		if not found then
			return fail(
				"MissingAnyUnlockedNature",
				{
					RequiredNatureIds =
						table.clone(anyUnlocked),
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- INNATE NATURE
	--
	-- Use this only when merely being born with a nature is enough.
	-- Jutsu CAST requirements should normally use UnlockedNatureId.
	-----------------------------------------------------------------

	local innateNatureId =
		requirements.InnateNatureId

	if innateNatureId ~= nil then
		if not CharacterOriginService.HasInnateNature(
			player,
			innateNatureId
			) then

			return fail(
				"MissingInnateNature",
				{
					RequiredNatureId =
						innateNatureId,
				}
			)
		end
	end

	local innateNatureIds =
		requirements.InnateNatureIds

	if innateNatureIds ~= nil then
		for _, natureId in ipairs(
			innateNatureIds
			) do
			if not CharacterOriginService.HasInnateNature(
				player,
				natureId
				) then

				return fail(
					"MissingInnateNature",
					{
						RequiredNatureId =
							natureId,
					}
				)
			end
		end
	end

	local anyInnate =
		requirements.AnyInnateNatureIds

	if anyInnate ~= nil then
		local found = false

		for _, natureId in ipairs(
			anyInnate
			) do
			if CharacterOriginService.HasInnateNature(
				player,
				natureId
				) then

				found = true
				break
			end
		end

		if not found then
			return fail(
				"MissingAnyInnateNature",
				{
					RequiredNatureIds =
						table.clone(anyInnate),
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- PRIMARY NATURE
	-----------------------------------------------------------------

	local data =
		CharacterOriginService.GetData(
			player
		)

	if requirements.PrimaryNatureId ~= nil then
		if not data
			or data.PrimaryNatureId
			~= requirements.PrimaryNatureId then

			return fail(
				"WrongPrimaryNature",
				{
					RequiredNatureId =
						requirements.PrimaryNatureId,
				}
			)
		end
	end

	if requirements.PrimaryNatureIds ~= nil then
		if not data
			or typeof(data.PrimaryNatureId)
			~= "string"
			or not contains(
				requirements.PrimaryNatureIds,
				data.PrimaryNatureId
			) then

			return fail(
				"WrongPrimaryNature",
				{
					RequiredNatureIds =
						table.clone(
							requirements.PrimaryNatureIds
						),
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- CLAN
	-----------------------------------------------------------------

	if requirements.ClanId ~= nil then
		local clanId =
			CharacterOriginService.GetClan(
				player
			)

		if clanId ~= requirements.ClanId then
			return fail(
				"WrongClan",
				{
					RequiredClanId =
						requirements.ClanId,

					ClanId =
						clanId,
				}
			)
		end
	end

	if requirements.ClanIds ~= nil then
		local clanId =
			CharacterOriginService.GetClan(
				player
			)

		if typeof(clanId) ~= "string"
			or not contains(
				requirements.ClanIds,
				clanId
			) then

			return fail(
				"WrongClan",
				{
					RequiredClanIds =
						table.clone(
							requirements.ClanIds
						),

					ClanId =
						clanId,
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- NATURAL KG
	-----------------------------------------------------------------

	if requirements.RequiresNaturalKGPotential ~= nil then
		local qualified =
			CharacterOriginService.HasNaturalKGPotential(
				player
			)

		if qualified
			~= requirements.RequiresNaturalKGPotential then

			return fail(
				"WrongNaturalKGPotential",
				{
					Required =
						requirements.RequiresNaturalKGPotential,

					Qualified =
						qualified,
				}
			)
		end
	end

	if requirements.NaturalKGId ~= nil then
		local kgId =
			CharacterOriginService.GetNaturalKGId(
				player
			)

		local available =
			CharacterOriginService.HasNaturalKGAvailable(
				player
			)

		if not available
			or kgId ~= requirements.NaturalKGId then

			return fail(
				"MissingNaturalKG",
				{
					RequiredNaturalKGId =
						requirements.NaturalKGId,

					NaturalKGId =
						kgId,

					Available =
						available,
				}
			)
		end
	end

	if requirements.NaturalKGIds ~= nil then
		local kgId =
			CharacterOriginService.GetNaturalKGId(
				player
			)

		local available =
			CharacterOriginService.HasNaturalKGAvailable(
				player
			)

		if not available
			or typeof(kgId) ~= "string"
			or not contains(
				requirements.NaturalKGIds,
				kgId
			) then

			return fail(
				"MissingNaturalKG",
				{
					RequiredNaturalKGIds =
						table.clone(
							requirements.NaturalKGIds
						),

					NaturalKGId =
						kgId,

					Available =
						available,
				}
			)
		end
	end

	-----------------------------------------------------------------
	-- LEARNED TECHNIQUE DEPENDENCIES
	--
	-- Uses the replicated LearnedTechniques folder to avoid a circular
	-- dependency between CharacterRequirementService and TechniqueRegistry.
	-----------------------------------------------------------------

	if requirements.RequiredTechniqueId ~= nil then
		if not hasLearnedTechnique(
			player,
			requirements.RequiredTechniqueId
			) then

			return fail(
				"MissingRequiredTechnique",
				{
					RequiredTechniqueId =
						requirements.RequiredTechniqueId,
				}
			)
		end
	end

	if requirements.RequiredTechniqueIds ~= nil then
		for _, requiredId in ipairs(
			requirements.RequiredTechniqueIds
			) do
			if not hasLearnedTechnique(
				player,
				requiredId
				) then

				return fail(
					"MissingRequiredTechnique",
					{
						RequiredTechniqueId =
							requiredId,

						RequiredTechniqueIds =
							table.clone(
								requirements.RequiredTechniqueIds
							),
					}
				)
			end
		end
	end

	-----------------------------------------------------------------
	-- VILLAGE / AFFILIATION
	--
	-- VillageId / VillageIds remain compatibility aliases for
	-- CURRENT affiliation. New systems should use explicit names.
	-----------------------------------------------------------------

	local requiredAffiliation =
		requirements.AffiliationVillageId
		or requirements.VillageId

	if requiredAffiliation ~= nil then
		if not VillageService.IsAffiliatedWith(
			player,
			requiredAffiliation
			) then

			return fail(
				"WrongVillageAffiliation",
				{
					RequiredVillageId =
						requiredAffiliation,

					CurrentVillageId =
						VillageService.GetAffiliationVillage(
							player
						),

					IsRogue =
						VillageService.IsRogue(
							player
						),
				}
			)
		end
	end

	local allowedAffiliations =
		requirements.AffiliationVillageIds
		or requirements.VillageIds

	if allowedAffiliations ~= nil then
		local current =
			VillageService.GetAffiliationVillage(
				player
			)

		if VillageService.IsRogue(player)
			or typeof(current) ~= "string"
			or not contains(
				allowedAffiliations,
				current
			) then

			return fail(
				"WrongVillageAffiliation",
				{
					RequiredVillageIds =
						table.clone(
							allowedAffiliations
						),

					CurrentVillageId =
						current,

					IsRogue =
						VillageService.IsRogue(
							player
						),
				}
			)
		end
	end

	if requirements.OriginVillageId ~= nil then
		if not VillageService.HasOrigin(
			player,
			requirements.OriginVillageId
			) then

			return fail(
				"WrongOriginVillage",
				{
					RequiredVillageId =
						requirements.OriginVillageId,

					OriginVillageId =
						VillageService.GetOriginVillage(
							player
						),
				}
			)
		end
	end

	if requirements.OriginVillageIds ~= nil then
		local originVillage =
			VillageService.GetOriginVillage(
				player
			)

		if typeof(originVillage) ~= "string"
			or not contains(
				requirements.OriginVillageIds,
				originVillage
			) then

			return fail(
				"WrongOriginVillage",
				{
					RequiredVillageIds =
						table.clone(
							requirements.OriginVillageIds
						),

					OriginVillageId =
						originVillage,
				}
			)
		end
	end

	if requirements.Rogue ~= nil then
		local isRogue =
			VillageService.IsRogue(
				player
			)

		if isRogue ~= requirements.Rogue then
			return fail(
				"WrongRogueStatus",
				{
					RequiredRogue =
						requirements.Rogue,

					IsRogue =
						isRogue,
				}
			)
		end
	end

	return true, "Allowed", nil
end

function CharacterRequirementService.RequireUnlockedNature(
	player: Player,
	natureId: string
): (boolean, string, any?)
	return CharacterRequirementService.Check(
		player,
		{
			UnlockedNatureId =
				natureId,
		}
	)
end

print(
	"[CharacterRequirementService] READY v1.3 ShinobiMenuRequirements"
		.. " | Level=ON"
		.. " | Nature=Innate+Unlocked+Primary"
		.. " | VillageOrigin+Affiliation+Rogue=ON"
		.. " | Clan=ON"
		.. " | NaturalKG=ON"
		.. " | TechniqueDependencies=ON"
		.. " | DeveloperContentBypass=ON"
)

return CharacterRequirementService
