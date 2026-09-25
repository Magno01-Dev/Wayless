--!strict
-- ServerScriptService > Services > CharacterCreationService
--
-- WAYLESS Character Creation stable v1.9 - optional gloves + wearable appearance.
--
-- Frontend-only. Loaded lazily by FrontendService only when CONFIRM is pressed.
--
-- Opening the creator never invokes this module and never writes DataStore.
-- This service validates the submitted creation payload and commits a new life.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local Services = ServerScriptService:WaitForChild("Services")
local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterCreationService = {}

local NAME_MIN = 2
local NAME_MAX = 18
local MAX_HAIR_ASSETS = 4

local VALID_VILLAGES = {
	Leaf = true,
	Sand = true,
	Mist = true,
	Cloud = true,
	Stone = true,
}

local hairAssetValidationCache: {[number]: boolean} = {}
local cachedAppearanceCatalog: any? = nil

local function getAppearanceCatalog(): (any?, string?)
	if cachedAppearanceCatalog then
		return cachedAppearanceCatalog, nil
	end

	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("AppearanceCatalog")

	if not module or not module:IsA("ModuleScript") then
		return nil, "AppearanceCatalogMissing"
	end

	local ok, result = pcall(require, module)
	if not ok then
		return nil, "AppearanceCatalogRequireFailed"
	end

	cachedAppearanceCatalog = result
	return cachedAppearanceCatalog, nil
end

local function trim(value: string): string
	return string.gsub(
		string.gsub(value, "^%s+", ""),
		"%s+$",
		""
	)
end

local function normalizeName(raw: any): string?
	if typeof(raw) ~= "string" then
		return nil
	end

	local value = trim(
		string.gsub(raw, "%s+", " ")
	)

	if #value < NAME_MIN or #value > NAME_MAX then
		return nil
	end

	if string.find(value, "[%c]") then
		return nil
	end

	return value
end

local function filterName(
	player: Player,
	raw: any
): (boolean, string, string?)
	local normalized = normalizeName(raw)
	if not normalized then
		return false, "InvalidName", nil
	end

	local ok, filterResult = pcall(function()
		return TextService:FilterStringAsync(
			normalized,
			player.UserId,
			Enum.TextFilterContext.PublicChat
		)
	end)

	if not ok or not filterResult then
		return false, "NameFilterFailed", nil
	end

	local textOk, filtered = pcall(function()
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)

	if not textOk or typeof(filtered) ~= "string" then
		return false, "NameFilterFailed", nil
	end

	filtered = trim(filtered)

	if filtered == ""
		or string.gsub(filtered, "[#%s]", "") == "" then

		return false, "NameRejectedByFilter", nil
	end

	return true, "NameAccepted", filtered
end

local function normalizeAssetId(raw: any): number?
	local value = tonumber(raw)

	if not value then
		return nil
	end

	value = math.floor(value)

	if value <= 0 then
		return nil
	end

	return value
end

local function validateHairAsset(assetId: number): (boolean, string)
	local cached = hairAssetValidationCache[assetId]
	if cached ~= nil then
		return cached,
			cached and "HairAssetValid" or "InvalidHairAsset"
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(
			assetId,
			Enum.InfoType.Asset
		)
	end)

	if not ok or typeof(info) ~= "table" then
		hairAssetValidationCache[assetId] = false
		return false, "HairAssetLookupFailed"
	end

	local assetTypeId = tonumber(info.AssetTypeId)
	local isHair =
		assetTypeId
		== Enum.AvatarAssetType.HairAccessory.Value

	hairAssetValidationCache[assetId] = isHair

	return isHair,
		isHair and "HairAssetValid" or "InvalidHairAsset"
end

local function validateHairAssetIds(raw: any): (boolean, string, {number}?)
	if raw == nil then
		return true, "HairReady", {}
	end

	if typeof(raw) ~= "table" then
		return false, "InvalidHairAssetList", nil
	end

	local normalized: {number} = {}
	local seen: {[number]: boolean} = {}

	for _, rawId in ipairs(raw) do
		local assetId = normalizeAssetId(rawId)
		if not assetId then
			return false, "InvalidHairAssetId", nil
		end

		if not seen[assetId] then
			seen[assetId] = true
			table.insert(normalized, assetId)
		end
	end

	if #normalized > MAX_HAIR_ASSETS then
		return false, "TooManyHairAssets", nil
	end

	for _, assetId in ipairs(normalized) do
		local valid, reason =
			validateHairAsset(assetId)

		if not valid then
			return false, reason, nil
		end
	end

	return true, "HairReady", normalized
end

local function validateAppearance(
	raw: any
): (boolean, string, {[string]: any}?)
	if typeof(raw) ~= "table" then
		return false, "AppearanceMissing", nil
	end

	local catalog, catalogReason =
		getAppearanceCatalog()

	if not catalog then
		return false, catalogReason or "AppearanceCatalogMissing", nil
	end

	local resolvedSkinToneId =
		catalog.ResolveSkinToneId(
			raw.SkinToneId
		)

	if not resolvedSkinToneId then
		return false, "InvalidSkinTone", nil
	end

	local mouthStyleId =
		typeof(raw.MouthStyleId) == "string"
		and raw.MouthStyleId
		or catalog.Defaults.MouthStyleId

	local browStyleId =
		typeof(raw.BrowStyleId) == "string"
		and raw.BrowStyleId
		or catalog.Defaults.BrowStyleId

	local noseStyleId =
		typeof(raw.NoseStyleId) == "string"
		and raw.NoseStyleId
		or catalog.Defaults.NoseStyleId

	local eyeStyleId =
		typeof(raw.EyeStyleId) == "string"
		and raw.EyeStyleId
		or catalog.Defaults.EyeStyleId

	local shoesStyleId =
		typeof(raw.ShoesStyleId) == "string"
		and raw.ShoesStyleId
		or catalog.Defaults.ShoesStyleId

	local glovesStyleId =
		typeof(raw.GlovesStyleId) == "string"
		and raw.GlovesStyleId
		or catalog.Defaults.GlovesStyleId

	if not catalog.IsValidMouthStyle(mouthStyleId) then
		return false, "InvalidMouthStyle", nil
	end

	if not catalog.IsValidBrowStyle(browStyleId) then
		return false, "InvalidBrowStyle", nil
	end

	if not catalog.IsValidNoseStyle(noseStyleId) then
		return false, "InvalidNoseStyle", nil
	end

	if not catalog.IsValidEyeStyle(eyeStyleId) then
		return false, "InvalidEyeStyle", nil
	end

	if not catalog.IsValidShoesStyle(shoesStyleId) then
		return false, "InvalidShoesStyle", nil
	end

	if not catalog.IsValidGlovesStyle(glovesStyleId) then
		return false, "InvalidGlovesStyle", nil
	end

	local hairOk, hairReason, hairAssetIds =
		validateHairAssetIds(
			raw.HairAssetIds
		)

	if not hairOk or not hairAssetIds then
		return false, hairReason, nil
	end

	return true, "AppearanceReady", {
		Version = 8,
		RigType = "R6",
		SkinToneId = resolvedSkinToneId,
		HairAssetIds = hairAssetIds,
		MouthStyleId = mouthStyleId,
		BrowStyleId = browStyleId,
		NoseStyleId = noseStyleId,
		EyeStyleId = eyeStyleId,
		ShoesStyleId = shoesStyleId,
		GlovesStyleId = glovesStyleId,
	}
end

local function validateStarterOutfit(
	raw: any
): (boolean, string, {[string]: any}?)
	local catalog, catalogReason =
		getAppearanceCatalog()

	if not catalog then
		return false, catalogReason or "AppearanceCatalogMissing", nil
	end

	raw = typeof(raw) == "table" and raw or {}

	local topId =
		typeof(raw.TopId) == "string"
		and raw.TopId
		or catalog.Defaults.StarterTopId

	local bottomId =
		typeof(raw.BottomId) == "string"
		and raw.BottomId
		or catalog.Defaults.StarterBottomId

	if not catalog.IsValidStarterTop(topId) then
		return false, "InvalidStarterTop", nil
	end

	if not catalog.IsValidStarterBottom(bottomId) then
		return false, "InvalidStarterBottom", nil
	end

	return true, "StarterOutfitReady", {
		Version = 1,
		TopId = topId,
		BottomId = bottomId,
	}
end

function CharacterCreationService.Commit(
	player: Player,
	slotId: string,
	payload: any
): (boolean, string, string?)
	if typeof(payload) ~= "table" then
		return false, "InvalidCreationPayload", nil
	end

	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot then
		return false, "SlotNotUnlocked", nil
	end

	if slot.State ~= "Empty"
		and slot.State ~= "Creating" then

		return false, "SlotNotAvailableForCreation", nil
	end

	if typeof(slot.PermanentOrigin) ~= "table" then
		return false, "SlotOriginNotReady", nil
	end

	local nameOk, nameReason, filteredName =
		filterName(player, payload.GivenName)

	if not nameOk or not filteredName then
		return false, nameReason, nil
	end

	local villageId =
		typeof(payload.VillageId) == "string"
		and payload.VillageId
		or ""

	if villageId == ""
		or VALID_VILLAGES[villageId] ~= true then

		return false, "InvalidVillage", nil
	end

	local primaryNatureId =
		typeof(payload.PrimaryNatureId) == "string"
		and payload.PrimaryNatureId
		or ""

	local origin = slot.PermanentOrigin

	local validPrimary =
		primaryNatureId == origin.Nature1Id
		or primaryNatureId == origin.Nature2Id
		or primaryNatureId == origin.Nature3Id

	if not validPrimary then
		return false, "InvalidPrimaryNature", nil
	end

	local appearanceOk, appearanceReason, appearance =
		validateAppearance(payload.Appearance)

	if not appearanceOk or not appearance then
		return false, appearanceReason, nil
	end

	local outfitOk, outfitReason, starterOutfit =
		validateStarterOutfit(payload.StarterOutfit)

	if not outfitOk or not starterOutfit then
		return false, outfitReason, nil
	end

	-- Validate everything BEFORE the first persistent mutation.
	if slot.State == "Empty" then
		local beginOk, beginReason =
			AccountProfileService.BeginCharacterCreation(
				player,
				slotId
			)

		if not beginOk then
			return false, beginReason, nil
		end
	end

	local summary = {
		CreationVersion = 2,
		GivenName = filteredName,
		VillageId = villageId,
		PrimaryNatureId = primaryNatureId,
		Appearance = appearance,
		StarterOutfit = starterOutfit,
		CreatedAt = os.time(),
	}

	return AccountProfileService.CommitNewLifeMetadata(
		player,
		slotId,
		summary
	)
end

print(
	"[CharacterCreationService] READY stable v1.2"
		.. " | AppearanceV1=ON"
		.. " | HairValidation=ON"
)

return CharacterCreationService
