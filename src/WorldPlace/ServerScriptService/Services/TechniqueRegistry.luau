--!strict
-- ServerScriptService > Services > TechniqueRegistry
--
-- WAYLESS global technique registry v1.5 ElementStyleJutsuMenuNames.
--
-- JUTSU AUTO-INTEGRATION CONTRACT
--
-- Any ModuleScript placed directly inside:
--     ServerScriptService > JutsuSystem > Jutsus
--
-- is automatically loaded and registered by JutsuServer through this module.
--
-- Elemental jutsus need only declare:
--
--     Jutsu.NatureId = "Fire"
--
-- That single metadata field AUTOMATICALLY becomes:
--
--     CastRequirements.UnlockedNatureId = "Fire"
--     LearnRequirements.UnlockedNatureId = "Fire"
--
-- Unlock progression metadata may be declared as:
--
--     Jutsu.MinimumLevel = 5
--
-- or in JutsuDefinitions:
--
--     MinimumLevel = 5
--
-- If MinimumLevel has not been authored yet, the temporary compatibility
-- fallback is Level 1 and a warning is printed. This keeps current content
-- testable without inventing balance thresholds.
--
-- No per-jutsu edit to JutsuServer.
-- No separate JutsuAccessConfig.
-- No duplicated nature check.
--
-- Non-elemental techniques simply omit NatureId.
--
-- Explicit future requirements may additionally be declared as:
--
--     Jutsu.CastRequirements = {
--         VillageId = "Mist",
--     }
--
-- or:
--
--     Jutsu.Requirements = {
--         Cast = {...},
--         Learn = {...},
--     }
--
-- All requirement evaluation goes through CharacterRequirementService.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local ServerScriptService =
	game:GetService("ServerScriptService")

local services =
	ServerScriptService:
	WaitForChild("Services")

local CharacterRequirementService = require(
	services:
		WaitForChild("CharacterRequirementService")
)

local TechniqueLearningService = require(
	services:
		WaitForChild("TechniqueLearningService")
)

local originSystem =
	ReplicatedStorage:
	WaitForChild("CharacterOriginSystem")

local NatureDefinitions = require(
	originSystem:
		WaitForChild("Shared"):
		WaitForChild("NatureDefinitions")
)

local TechniqueRegistry = {}

type RegistryEntry = {
	Id: string,
	Kind: string,
	Category: string,
	NatureId: string?,
	DisplayName: string,
	MinimumLevel: number,
	DisplayInMenu: boolean,
	SortOrder: number,

	Module: any,
	Config: any,
	Source: ModuleScript,

	CastRequirements: {[string]: any},
	LearnRequirements: {[string]: any},
}

local entries: {[string]: RegistryEntry} = {}

---------------------------------------------------------------------
-- ELEMENT STYLE DISPLAY NAMES
--
-- Menu-only presentation. Technique Ids, configs, requirements and
-- gameplay logic remain untouched.
--
-- TechniqueHotbarController already removes the "... Style:" prefix,
-- so the 10-slot HUD remains compact.
---------------------------------------------------------------------

local STYLE_PREFIX_BY_NATURE: {[string]: string} = {
	Fire = "Fire Style",
	Water = "Water Style",
	Wind = "Wind Style",
	Lightning = "Lightning Style",
	Earth = "Earth Style",
}

local function formatElementStyleDisplayName(
	natureId: string?,
	displayName: string
): string

	if not natureId then
		return displayName
	end

	local prefix =
		STYLE_PREFIX_BY_NATURE[
	natureId
	]

	-- Only the five basic elemental natures receive this menu convention.
	if not prefix then
		return displayName
	end

	-- Remove an already-authored elemental Style prefix before rebuilding
	-- the final menu name. This prevents duplicated prefixes.
	local baseName =
		string.gsub(
			displayName,
			"^%s*[^:]-[Ss]tyle:%s*",
			""
		)

	-- Every basic elemental technique uses the visible suffix "Jutsu".
	-- Preserve names that already end with Jutsu.
	if not string.match(
		baseName,
		"[Jj][Uu][Tt][Ss][Uu]%s*$"
		) then
		baseName =
			baseName
			.. " Jutsu"
	end

	return prefix
		.. ": "
		.. baseName
end
local jutsuModules: {[string]: any} = {}

local function shallowMerge(
	target: {[string]: any},
	source: any
)
	if typeof(source) ~= "table" then
		return
	end

	for key, value in pairs(source) do
		target[key] = value
	end
end

local function deriveNatureId(
	module: any,
	config: any
): string?
	local natureId =
		module.NatureId

	if natureId == nil
		and typeof(config) == "table" then

		natureId =
			config.NatureId
	end

	-- Temporary compatibility aliases. New content should use NatureId.
	if natureId == nil then
		natureId =
			module.ElementId
			or module.Element
	end

	if natureId == nil
		and typeof(config) == "table" then

		natureId =
			config.ElementId
			or config.Element
	end

	if natureId == nil then
		return nil
	end

	if typeof(natureId) ~= "string"
		or not NatureDefinitions.IsValid(
			natureId
		) then

		return nil
	end

	return natureId
end

local function deriveMinimumLevel(
	module: any,
	config: any,
	techniqueId: string
): (number, boolean)
	local raw =
		module.MinimumLevel
		or module.UnlockLevel
		or (
			typeof(config) == "table"
			and (
				config.MinimumLevel
				or config.UnlockLevel
			)
			or nil
		)

	if raw == nil then
		warn(
			"[TechniqueRegistry] MISSING MinimumLevel",
			techniqueId,
			"Fallback=1"
		)

		return 1,
			true
	end

	if typeof(raw) ~= "number"
		or raw < 1
		or raw > 100 then

		warn(
			"[TechniqueRegistry] INVALID MinimumLevel",
			techniqueId,
			tostring(raw)
		)

		return 1,
			false
	end

	return math.floor(raw),
		true
end

local function buildRequirementTable(
	module: any,
	natureId: string?,
	minimumLevel: number,
	phase: string
): {[string]: any}
	local result: {[string]: any} = {}

	local grouped =
		module.Requirements

	if typeof(grouped) == "table" then
		shallowMerge(
			result,
			grouped[phase]
		)
	end

	if phase == "Cast" then
		shallowMerge(
			result,
			module.CastRequirements
		)

	elseif phase == "Learn" then
		shallowMerge(
			result,
			module.LearnRequirements
		)
	end

	-- Canonical elemental rule:
	-- having the nature genetically is NOT enough.
	-- It must be unlocked both to learn and to cast an elemental technique.
	if natureId ~= nil then
		result.UnlockedNatureId =
			natureId
	end

	-- Canonical progression rule:
	-- level controls when a technique becomes unlockable.
	if phase == "Learn"
		and result.MinimumLevel == nil then

		result.MinimumLevel =
			minimumLevel
	end

	return result
end

function TechniqueRegistry.RegisterJutsuModule(
	moduleScript: ModuleScript,
	definitions: any
): (boolean, any)

	local ok,
		module =
		pcall(
			require,
			moduleScript
		)

	if not ok then
		warn(
			"[TechniqueRegistry] REQUIRE FAILED",
			moduleScript:GetFullName(),
			module
		)

		return false, module
	end

	if typeof(module) ~= "table"
		or typeof(module.Id) ~= "string" then

		warn(
			"[TechniqueRegistry] INVALID JUTSU MODULE",
			moduleScript:GetFullName(),
			"Expected table with string Id"
		)

		return false, "InvalidJutsuModule"
	end

	local id =
		module.Id

	local sharedConfig =
		typeof(definitions) == "table"
		and definitions[id]
		or nil

	local moduleConfig =
		module.Config

	local config =
		if typeof(sharedConfig) == "table"
		then sharedConfig
		elseif typeof(moduleConfig) == "table"
		then moduleConfig
		else nil

	if typeof(config) ~= "table" then
		warn(
			"[TechniqueRegistry] MISSING JUTSU CONFIG",
			id,
			moduleScript:GetFullName(),
			"Expected JutsuDefinitions[id] or Module.Config"
		)

		return false, "MissingJutsuConfig"
	end

	if typeof(sharedConfig) ~= "table"
		and typeof(moduleConfig) == "table" then

		print(
			"[TechniqueRegistry] MODULE CONFIG FALLBACK",
			id
		)
	end

	if entries[id] ~= nil then
		warn(
			"[TechniqueRegistry] DUPLICATE TECHNIQUE ID",
			id,
			moduleScript:GetFullName()
		)

		return false, "DuplicateTechniqueId"
	end

	local rawNature =
		module.NatureId

	if rawNature == nil then
		rawNature =
			config.NatureId
	end

	local natureId =
		deriveNatureId(
			module,
			config
		)

	if rawNature ~= nil
		and natureId == nil then

		warn(
			"[TechniqueRegistry] INVALID NatureId",
			id,
			tostring(rawNature)
		)

		return false, "InvalidNatureId"
	end

	local minimumLevel,
		validMinimumLevel =
		deriveMinimumLevel(
			module,
			config,
			id
		)

	if not validMinimumLevel then
		return false,
			"InvalidMinimumLevel"
	end

	local category =
		module.TechniqueCategory
		or config.TechniqueCategory
		or (
			natureId
			and "ElementalNinjutsu"
			or "Ninjutsu"
		)

	local baseDisplayName =
		typeof(config.DisplayName)
		== "string"
		and config.DisplayName
		or id

	local displayName =
		formatElementStyleDisplayName(
			natureId,
			baseDisplayName
		)

	local displayInMenu =
		module.DisplayInMenu ~= false
		and config.DisplayInMenu ~= false

	local sortOrder =
		typeof(module.SortOrder) == "number"
		and module.SortOrder
		or (
			typeof(config.SortOrder) == "number"
			and config.SortOrder
			or 0
		)

	local castRequirements =
		buildRequirementTable(
			module,
			natureId,
			minimumLevel,
			"Cast"
		)

	local learnRequirements =
		buildRequirementTable(
			module,
			natureId,
			minimumLevel,
			"Learn"
		)

	local entry: RegistryEntry = {
		Id = id,
		Kind = "TECHNIQUE",
		Category = category,
		NatureId = natureId,
		DisplayName = displayName,
		MinimumLevel = minimumLevel,
		DisplayInMenu = displayInMenu,
		SortOrder = sortOrder,

		Module = module,
		Config = config,
		Source = moduleScript,

		CastRequirements =
			castRequirements,

		LearnRequirements =
			learnRequirements,
	}

	entries[id] =
		entry

	jutsuModules[id] =
		module

	print(
		"[TechniqueRegistry] REGISTERED",
		id,
		"Category=" .. category,
		"Nature="
			.. tostring(natureId),
		"AutoNatureGate="
			.. tostring(
				natureId ~= nil
			),
		"MinimumLevel="
			.. tostring(
				minimumLevel
			),
		"DisplayInMenu="
			.. tostring(
				displayInMenu
			)
	)

	return true, module
end

function TechniqueRegistry.LoadJutsuFolder(
	folder: Instance,
	definitions: any
): {[string]: any}

	for _, child in ipairs(
		folder:GetChildren()
		) do
		if child:IsA("ModuleScript") then
			TechniqueRegistry.RegisterJutsuModule(
				child,
				definitions
			)
		end
	end

	return jutsuModules
end

function TechniqueRegistry.Get(
	techniqueId: string
): RegistryEntry?
	return entries[techniqueId]
end

function TechniqueRegistry.GetJutsuModule(
	jutsuId: string
): any?
	return jutsuModules[jutsuId]
end

function TechniqueRegistry.GetAll(): {[string]: RegistryEntry}
	return table.clone(entries)
end

function TechniqueRegistry.CheckCastAccess(
	player: Player,
	techniqueId: string
): (boolean, string, any?)

	local entry =
		entries[techniqueId]

	if not entry then
		return false,
			"UnknownTechnique",
			nil
	end

	-----------------------------------------------------------------
	-- AUTOMATIC LEARNED-TECHNIQUE GATE
	--
	-- Every registered technique passes this automatically.
	-- Dev content bypass treats every registered technique as learned.
	-----------------------------------------------------------------

	local known,
		knownReason,
		knownDetails =
		TechniqueLearningService.CheckUse(
			player,
			techniqueId
		)

	if not known then
		return false,
			knownReason
			or "TechniqueNotLearned",
			knownDetails
	end

	return CharacterRequirementService.Check(
		player,
		entry.CastRequirements
	)
end

function TechniqueRegistry.CheckLearnAccess(
	player: Player,
	techniqueId: string
): (boolean, string, any?)

	local entry =
		entries[techniqueId]

	if not entry then
		return false,
			"UnknownTechnique",
			nil
	end

	return CharacterRequirementService.Check(
		player,
		entry.LearnRequirements
	)
end

function TechniqueRegistry.Learn(
	player: Player,
	techniqueId: string,
	source: any?
): (boolean, string, any?)

	local allowed,
		reason,
		details =
		TechniqueRegistry.CheckLearnAccess(
			player,
			techniqueId
		)

	if not allowed then
		return false,
			reason,
			details
	end

	local ok,
		learnReason =
		TechniqueLearningService.Learn(
			player,
			techniqueId,
			source
		)

	return ok,
		learnReason,
		nil
end

function TechniqueRegistry.Forget(
	player: Player,
	techniqueId: string
): (boolean, string)
	return TechniqueLearningService.Forget(
		player,
		techniqueId
	)
end

function TechniqueRegistry.Knows(
	player: Player,
	techniqueId: string
): boolean
	if entries[techniqueId] == nil then
		return false
	end

	return TechniqueLearningService.Knows(
		player,
		techniqueId
	)
end

print(
	"[TechniqueRegistry] READY v1.5 ElementStyleJutsuMenuNames"
		.. " | AutoJutsuRegistration=ON"
		.. " | AutoNatureLearn+CastGate=ON"
		.. " | MinimumLevelLearnGate=ON"
		.. " | GenericRequirements=ON"
		.. " | LearnedTechniqueGate=ON"
		.. " | DeveloperBypass=ON"
		.. " | ModuleConfigFallback=ON"
		.. " | ElementStyleMenuNames=ON"
		.. " | ElementJutsuSuffix=ON"
)

return TechniqueRegistry
