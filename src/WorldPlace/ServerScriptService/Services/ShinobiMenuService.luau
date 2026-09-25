--!strict
-- ServerScriptService > Services > ShinobiMenuService
--
-- WAYLESS Shinobi Menu server gateway v2 - Technique Loadout.
--
-- The client never decides whether a technique may be unlocked.
-- This service returns a sanitized catalog and routes Unlock through:
--
--   TechniqueRegistry
--   -> CharacterRequirementService
--   -> TechniqueLearningService
--
-- Current active pages:
--   Character (client reads replicated attributes)
--   Techniques (server-authoritative unlock)
--   Loadout (10-slot server-authoritative technique loadout)
--
-- Reserved shell pages:
--   Ninja Bag
--   Equipment

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

local Services =
	ServerScriptService:
	WaitForChild(
		"Services"
	)

local TechniqueRegistry =
	require(
		Services:
		WaitForChild(
			"TechniqueRegistry"
		)
	)

local TechniqueLearningService =
	require(
		Services:
		WaitForChild(
			"TechniqueLearningService"
		)
	)

local TechniqueLoadoutService =
	require(
		Services:
		WaitForChild(
			"TechniqueLoadoutService"
		)
	)

local CharacterOriginService =
	require(
		Services:
		WaitForChild(
			"CharacterOriginService"
		)
	)

local VillageService =
	require(
		Services:
		WaitForChild(
			"VillageService"
		)
	)

local ShinobiMenuService = {}

local UNLOCK_REQUEST_COOLDOWN =
	0.20

local LOADOUT_REQUEST_COOLDOWN =
	0.10

local lastUnlockAt: {[Player]: number} =
	{}

local lastLoadoutAt: {[Player]: number} =
	{}

local function listContains(
	list: any,
	value: string
): boolean
	if typeof(list) ~= "table" then
		return false
	end

	for _, candidate in ipairs(
		list
		) do
		if candidate == value then
			return true
		end
	end

	return false
end

local function hasLearned(
	knownSet: {[string]: boolean},
	techniqueId: string
): boolean
	return knownSet[
	techniqueId
	] == true
end

local function getKnownSet(
	player: Player
): {[string]: boolean}
	local result: {[string]: boolean} =
		{}

	for _, techniqueId in ipairs(
		TechniqueLearningService
			.GetKnownTechniqueIds(
				player
			)
		) do
		result[techniqueId] =
			true
	end

	return result
end

local function requirementItem(
	key: string,
	label: string,
	met: boolean,
	required: any?,
	current: any?
): {[string]: any}
	return {
		Key = key,
		Label = label,
		Met = met,
		Required = required,
		Current = current,
	}
end

local function buildRequirementItems(
	player: Player,
	requirements: any,
	knownSet: {[string]: boolean}
): {{[string]: any}}
	local items = {}

	if typeof(requirements) ~=
		"table" then

		return items
	end

	if typeof(
		requirements.MinimumLevel
		) == "number" then

		local currentLevel =
			player:GetAttribute(
				"CharacterLevel"
			)

		local met =
			typeof(currentLevel) == "number"
			and currentLevel
			>= requirements.MinimumLevel

		table.insert(
			items,
			requirementItem(
				"MinimumLevel",
				"Level "
					.. tostring(
						requirements.MinimumLevel
					),
				met,
				requirements.MinimumLevel,
				currentLevel
			)
		)
	end

	if typeof(
		requirements.UnlockedNatureId
		) == "string" then

		local natureId =
			requirements.UnlockedNatureId

		table.insert(
			items,
			requirementItem(
				"UnlockedNatureId",
				natureId
					.. " Nature",
				CharacterOriginService
					.CanUseNature(
						player,
						natureId
					),
				natureId,
				nil
			)
		)
	end

	if typeof(
		requirements.UnlockedNatureIds
		) == "table" then

		for _, natureId in ipairs(
			requirements.UnlockedNatureIds
			) do
			table.insert(
				items,
				requirementItem(
					"UnlockedNatureIds",
					tostring(natureId)
						.. " Nature",
					CharacterOriginService
						.CanUseNature(
							player,
							tostring(
								natureId
							)
						),
					natureId,
					nil
				)
			)
		end
	end

	if typeof(
		requirements.AnyUnlockedNatureIds
		) == "table" then

		local met =
			false

		for _, natureId in ipairs(
			requirements.AnyUnlockedNatureIds
			) do
			if CharacterOriginService
				.CanUseNature(
					player,
					tostring(
						natureId
					)
				) then

				met =
					true

				break
			end
		end

		table.insert(
			items,
			requirementItem(
				"AnyUnlockedNatureIds",
				"Any Nature: "
					.. table.concat(
						requirements.AnyUnlockedNatureIds,
						" / "
					),
				met,
				table.clone(
					requirements.AnyUnlockedNatureIds
				),
				nil
			)
		)
	end

	if typeof(
		requirements.ClanId
		) == "string" then

		local clanId =
			CharacterOriginService
			.GetClan(
				player
			)

		table.insert(
			items,
			requirementItem(
				"ClanId",
				requirements.ClanId
					.. " Clan",
				clanId
					== requirements.ClanId,
				requirements.ClanId,
				clanId
			)
		)
	end

	if typeof(
		requirements.ClanIds
		) == "table" then

		local clanId =
			CharacterOriginService
			.GetClan(
				player
			)

		table.insert(
			items,
			requirementItem(
				"ClanIds",
				"Clan: "
					.. table.concat(
						requirements.ClanIds,
						" / "
					),
				typeof(clanId)
					== "string"
					and listContains(
						requirements.ClanIds,
						clanId
					),
				table.clone(
					requirements.ClanIds
				),
				clanId
			)
		)
	end

	if requirements
		.RequiresNaturalKGPotential
		~= nil then

		local qualified =
			CharacterOriginService
			.HasNaturalKGPotential(
				player
			)

		table.insert(
			items,
			requirementItem(
				"RequiresNaturalKGPotential",
				requirements
					.RequiresNaturalKGPotential
					and "Natural KG Potential"
					or "No Natural KG Potential",
				qualified
					== requirements
					.RequiresNaturalKGPotential,
				requirements
					.RequiresNaturalKGPotential,
				qualified
			)
		)
	end

	if typeof(
		requirements.NaturalKGId
		) == "string" then

		local kgId =
			CharacterOriginService
			.GetNaturalKGId(
				player
			)

		local available =
			CharacterOriginService
			.HasNaturalKGAvailable(
				player
			)

		table.insert(
			items,
			requirementItem(
				"NaturalKGId",
				requirements.NaturalKGId,
				available
					and kgId
					== requirements.NaturalKGId,
				requirements.NaturalKGId,
				kgId
			)
		)
	end

	if typeof(
		requirements.RequiredTechniqueId
		) == "string" then

		local requiredId =
			requirements.RequiredTechniqueId

		table.insert(
			items,
			requirementItem(
				"RequiredTechniqueId",
				"Technique: "
					.. requiredId,
				hasLearned(
					knownSet,
					requiredId
				),
				requiredId,
				nil
			)
		)
	end

	if typeof(
		requirements.RequiredTechniqueIds
		) == "table" then

		for _, requiredId in ipairs(
			requirements.RequiredTechniqueIds
			) do
			table.insert(
				items,
				requirementItem(
					"RequiredTechniqueIds",
					"Technique: "
						.. tostring(
							requiredId
						),
					hasLearned(
						knownSet,
						tostring(
							requiredId
						)
					),
					requiredId,
					nil
				)
			)
		end
	end

	local affiliation =
		requirements
		.AffiliationVillageId
		or requirements.VillageId

	if typeof(affiliation) ==
		"string" then

		table.insert(
			items,
			requirementItem(
				"AffiliationVillageId",
				"Affiliation: "
					.. affiliation,
				VillageService
					.IsAffiliatedWith(
						player,
						affiliation
					),
				affiliation,
				VillageService
					.GetAffiliationVillage(
						player
					)
			)
		)
	end

	if typeof(
		requirements.OriginVillageId
		) == "string" then

		local origin =
			VillageService
			.GetOriginVillage(
				player
			)

		table.insert(
			items,
			requirementItem(
				"OriginVillageId",
				"Origin: "
					.. requirements
					.OriginVillageId,
				origin
					== requirements
					.OriginVillageId,
				requirements
					.OriginVillageId,
				origin
			)
		)
	end

	if requirements.Rogue ~= nil then
		local rogue =
			VillageService
			.IsRogue(
				player
			)

		table.insert(
			items,
			requirementItem(
				"Rogue",
				requirements.Rogue
					and "Rogue"
					or "Not Rogue",
				rogue
					== requirements.Rogue,
				requirements.Rogue,
				rogue
			)
		)
	end

	return items
end

local function makeTechniqueView(
	player: Player,
	entry: any,
	knownSet: {[string]: boolean}
): {[string]: any}
	local learned =
		hasLearned(
			knownSet,
			entry.Id
		)

	local allowed,
		reason,
		details =
		TechniqueRegistry
		.CheckLearnAccess(
			player,
			entry.Id
		)

	local status: string

	if learned then
		status =
			"UNLOCKED"

	elseif allowed then
		status =
			"AVAILABLE"

	else
		status =
			"LOCKED"
	end

	return {
		Id =
			entry.Id,

		DisplayName =
			entry.DisplayName,

		Category =
			entry.Category,

		NatureId =
			entry.NatureId,

		MinimumLevel =
			entry.MinimumLevel
			or 1,

		SortOrder =
			entry.SortOrder
			or 0,

		Status =
			status,

		Learned =
			learned,

		CanUnlock =
			not learned
			and allowed,

		LockReason =
			allowed
			and nil
			or reason,

		LockDetails =
			allowed
			and nil
			or details,

		Requirements =
			buildRequirementItems(
				player,
				entry.LearnRequirements,
				knownSet
			),
	}
end

function ShinobiMenuService.GetTechniqueSnapshot(
	player: Player
): {[string]: any}
	if not TechniqueLearningService
		.IsReady(
			player
		) then

		return {
			Ok = false,
			Reason =
				"TechniqueLearningNotReady",
			Techniques = {},
		}
	end

	local knownSet =
		getKnownSet(
			player
		)

	local techniques = {}

	for _, entry in pairs(
		TechniqueRegistry.GetAll()
		) do
		if entry.DisplayInMenu
			~= false then

			table.insert(
				techniques,
				makeTechniqueView(
					player,
					entry,
					knownSet
				)
			)
		end
	end

	table.sort(
		techniques,
		function(
			a: any,
			b: any
		): boolean
			if a.SortOrder
				~= b.SortOrder then

				return a.SortOrder
					< b.SortOrder
			end

			if a.MinimumLevel
				~= b.MinimumLevel then

				return a.MinimumLevel
					< b.MinimumLevel
			end

			if a.Category
				~= b.Category then

				return tostring(
					a.Category
				) < tostring(
					b.Category
				)
			end

			return tostring(
				a.DisplayName
			) < tostring(
				b.DisplayName
			)
		end
	)

	return {
		Ok = true,
		Reason = "OK",
		Techniques = techniques,
		LearnedCount =
			#TechniqueLearningService
			.GetKnownTechniqueIds(
				player
			),
		RegisteredCount =
			#techniques,
	}
end

local function getMutationBlockReason(
	player: Player
): string?
	local character =
		player.Character

	if not character then
		return "NoCharacter"
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return "CharacterUnavailable"
	end

	if character:GetAttribute(
		"CombatTagged"
		) == true then

		return "CombatTagged"
	end

	if character:GetAttribute(
		"DownedActionLocked"
		) == true
			or character:GetAttribute(
				"IsDowned"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true
			or character:GetAttribute(
				"IsCarrying"
			) == true
			or character:GetAttribute(
				"IsExecuting"
			) == true then

		return "CharacterActionLocked"
	end

	return nil
end


local function makeLoadoutSlotView(
	slotIndex: number,
	techniqueId: string
): {[string]: any}
	if techniqueId == "" then
		return {
			SlotIndex = slotIndex,
			TechniqueId = nil,
			DisplayName = nil,
			Category = nil,
			NatureId = nil,
		}
	end

	local entry =
		TechniqueRegistry.Get(
			techniqueId
		)

	return {
		SlotIndex = slotIndex,
		TechniqueId = techniqueId,
		DisplayName = entry
			and entry.DisplayName
			or techniqueId,
		Category = entry
			and entry.Category
			or nil,
		NatureId = entry
			and entry.NatureId
			or nil,
	}
end

function ShinobiMenuService.GetLoadoutSnapshot(
	player: Player
): {[string]: any}
	if not TechniqueLoadoutService
		.IsReady(
			player
		) then

		return {
			Ok = false,
			Reason =
				"TechniqueLoadoutNotReady",
			SlotCount =
				TechniqueLoadoutService
				.GetSlotCount(),
			Slots = {},
		}
	end

	local rawSlots =
		TechniqueLoadoutService.GetSlots(
			player
		)

	local slots = {}

	for slotIndex = 1,
		TechniqueLoadoutService
		.GetSlotCount() do

		table.insert(
			slots,
			makeLoadoutSlotView(
				slotIndex,
				rawSlots[slotIndex]
					or ""
			)
		)
	end

	return {
		Ok = true,
		Reason = "OK",
		SlotCount =
			TechniqueLoadoutService
			.GetSlotCount(),
		Slots = slots,
	}
end

function ShinobiMenuService.SetLoadoutSlot(
	player: Player,
	slotIndex: any,
	techniqueId: any
): {[string]: any}
	local mutationBlock =
		getMutationBlockReason(
			player
		)

	if mutationBlock then
		return {
			Ok = false,
			Reason = mutationBlock,
		}
	end

	local now =
		os.clock()

	local last =
		lastLoadoutAt[player]
		or -math.huge

	if now - last
		< LOADOUT_REQUEST_COOLDOWN then

		return {
			Ok = false,
			Reason =
				"RequestThrottled",
		}
	end

	lastLoadoutAt[player] =
		now

	local ok,
		reason =
		TechniqueLoadoutService.SetSlot(
			player,
			slotIndex,
			techniqueId
		)

	return {
		Ok = ok,
		Reason = reason,
		Snapshot =
			ShinobiMenuService
			.GetLoadoutSnapshot(
				player
			),
	}
end

function ShinobiMenuService.UnlockTechnique(
	player: Player,
	techniqueId: any
): {[string]: any}
	if typeof(techniqueId)
		~= "string"
		or techniqueId == ""
		or #techniqueId > 80 then

		return {
			Ok = false,
			Reason =
				"InvalidTechniqueId",
		}
	end

	local mutationBlock =
		getMutationBlockReason(
			player
		)

	if mutationBlock then
		return {
			Ok = false,
			Reason =
				mutationBlock,
		}
	end

	local now =
		os.clock()

	local last =
		lastUnlockAt[player]
		or -math.huge

	if now - last
		< UNLOCK_REQUEST_COOLDOWN then

		return {
			Ok = false,
			Reason =
				"RequestThrottled",
		}
	end

	lastUnlockAt[player] =
		now

	if not TechniqueLearningService
		.IsReady(
			player
		) then

		return {
			Ok = false,
			Reason =
				"TechniqueLearningNotReady",
		}
	end

	local entry =
		TechniqueRegistry.Get(
			techniqueId
		)

	if not entry
		or entry.DisplayInMenu
		== false then

		return {
			Ok = false,
			Reason =
				"UnknownTechnique",
		}
	end

	-- Check the actual stored learned list rather than effective dev-bypass
	-- knowledge so developers can still QA the real Unlock button.
	local knownSet =
		getKnownSet(
			player
		)

	if knownSet[techniqueId] then
		return {
			Ok = true,
			Reason =
				"AlreadyLearned",
			Snapshot =
				ShinobiMenuService
				.GetTechniqueSnapshot(
					player
				),
		}
	end

	local ok,
		reason,
		details =
		TechniqueRegistry.Learn(
			player,
			techniqueId,
			{
				Type =
				"MenuUnlock",

				Id =
				"ShinobiMenu",
			}
		)

	if not ok then
		return {
			Ok = false,
			Reason =
				reason
				or "UnlockDenied",
			Details =
				details,
			Snapshot =
				ShinobiMenuService
				.GetTechniqueSnapshot(
					player
				),
		}
	end

	local saveOk =
		TechniqueLearningService.Save(
			player
		)

	return {
		Ok = true,
		Reason =
			saveOk
			and "Unlocked"
			or "UnlockedSavePending",
		TechniqueId =
			techniqueId,
		Snapshot =
			ShinobiMenuService
			.GetTechniqueSnapshot(
				player
			),
	}
end

function ShinobiMenuService.ForgetPlayer(
	player: Player
)
	lastUnlockAt[player] =
		nil

	lastLoadoutAt[player] =
		nil
end

print(
	"[ShinobiMenuService] READY v2"
		.. " | Techniques=SERVER_AUTHORITATIVE"
		.. " | Unlock=TechniqueRegistry"
		.. " | Trainers=NOT_REQUIRED"
		.. " | LoadoutSlots=10"
		.. " | CombatMutationLock=ON"
)

return ShinobiMenuService
