--!strict
-- ServerScriptService > Services > CharacterIdentityService
--
-- WAYLESS Character Identity v3.11 - wearable loader synchronization + canonical glove Y=-0.80.
--
-- Applies/publishes:
-- - Shinobi given name + clan surname
-- - Village identity
-- - skin tone
-- - Roblox catalog hair selected during creation
-- - starter face/outfit catalog entries when real assets are configured
-- - derived base eye style attribute for future clan/doujutsu visuals
--
-- Physical build/height scaling remains profile-only for now to avoid changing
-- gameplay hitboxes and animation assumptions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

local originSystem =
	ReplicatedStorage:WaitForChild("CharacterOriginSystem")

local originShared =
	originSystem:WaitForChild("Shared")

local ClanDefinitions =
	require(originShared:WaitForChild("ClanDefinitions"))

local CharacterIdentityService = {}

local started = false
local connections: {[Player]: {RBXScriptConnection}} = {}
local faceGuardConnections: {[Player]: {RBXScriptConnection}} = {}
local faceApplying: {[Player]: boolean} = {}
local faceReapplyQueued: {[Player]: boolean} = {}

local LEGACY_SKIN_COLORS = {
	Porcelain = Color3.fromRGB(250, 224, 204),
	Light = Color3.fromRGB(239, 203, 177),
	Warm = Color3.fromRGB(207, 158, 119),
	Tan = Color3.fromRGB(169, 116, 80),
	Brown = Color3.fromRGB(119, 75, 54),
	Deep = Color3.fromRGB(69, 43, 36),
}

local cachedAppearanceCatalog: any? = nil

local function getAppearanceCatalog(): any?
	if cachedAppearanceCatalog then
		return cachedAppearanceCatalog
	end

	local shared =
		ReplicatedStorage:
		FindFirstChild("Shared")

	local module =
		shared
		and shared:
		FindFirstChild(
			"AppearanceCatalog"
		)

	if not module
		or not module:IsA("ModuleScript") then

		return nil
	end

	local ok, result =
		pcall(require, module)

	if not ok then
		warn(
			"[CharacterIdentityService] AppearanceCatalog require failed",
			result
		)
		return nil
	end

	cachedAppearanceCatalog = result
	return cachedAppearanceCatalog
end

local function validateAppearanceCatalog(): boolean
	local catalog =
		getAppearanceCatalog()

	if not catalog then
		warn(
			"[CharacterIdentityService] APPEARANCE CATALOG MISSING"
		)
		return false
	end

	local version =
		tonumber(catalog.Version) or 0

	local modularReady =
		version >= 6
		and typeof(catalog.GetMouthStyle) == "function"
		and typeof(catalog.GetBrowStyle) == "function"
		and typeof(catalog.GetNoseStyle) == "function"
		and typeof(catalog.GetEyeStyle) == "function"
		and typeof(catalog.GetEyeImage) == "function"

	if not modularReady then
		warn(
			"[CharacterIdentityService] APPEARANCE CATALOG TOO OLD",
			"Version=" .. tostring(version),
			"ExpectedVersion>=6"
		)
		return false
	end

	return true
end

local function clanDisplayName(
	clanId: string
): string
	if typeof(ClanDefinitions.Get) == "function" then
		local ok, definition =
			pcall(
				ClanDefinitions.Get,
				clanId
			)

		if ok
			and typeof(definition) == "table" then

			return tostring(
				definition.DisplayName
					or definition.Name
					or clanId
			)
		end
	end

	return clanId
end

local function currentSummary(
	player: Player
): (string?, string?, {[string]: any}?)
	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	local slot =
		AccountProfileService.GetSlot(
			player,
			identity.SlotId
		)

	if not slot
		or typeof(slot.CurrentLife) ~= "table"
		or tostring(
			slot.CurrentLife.LifeId
		) ~= tostring(
			identity.LifeId
		) then

		return identity.SlotId,
			identity.LifeId,
			nil
	end

	local summary =
		typeof(slot.CurrentLife.Summary) == "table"
		and slot.CurrentLife.Summary
		or nil

	return identity.SlotId,
		identity.LifeId,
		summary
end

local function getSkinColor(
	skinToneId: any
): Color3?
	if typeof(skinToneId) ~= "string" then
		return nil
	end

	local catalog =
		getAppearanceCatalog()

	if catalog
		and typeof(catalog.GetSkinTone) == "function" then

		local entry =
			catalog.GetSkinTone(
				skinToneId
			)

		if typeof(entry) == "table"
			and typeof(entry.Color) == "Color3" then

			return entry.Color
		end
	end

	return LEGACY_SKIN_COLORS[
	skinToneId
	]
end

local function hairIdsToString(
	raw: any
): string?
	if typeof(raw) ~= "table" then
		return nil
	end

	local values = {}

	for _, rawId in ipairs(raw) do
		local assetId =
			math.floor(
				tonumber(rawId) or 0
			)

		if assetId > 0 then
			table.insert(
				values,
				tostring(assetId)
			)
		end
	end

	return table.concat(
		values,
		","
	)
end

local FACE_DECAL_NAMES = {
	face = true,
	Face = true,
}

local function removeDefaultRobloxFace(
	head: BasePart
)
	for _, child in ipairs(
		head:GetChildren()
		) do
		if child:IsA("Decal")
			and FACE_DECAL_NAMES[child.Name] then

			child:Destroy()

		elseif child:IsA("SurfaceGui")
			and child.Name == "WAYLESSFaceGui" then

			-- Cleanup only from the obsolete SurfaceGui implementation.
			child:Destroy()
		end
	end
end

local function upsertFaceDecal(
	head: BasePart,
	name: string,
	image: any,
	zIndex: number
): Decal?
	if typeof(image) ~= "string"
		or image == "" then

		local old =
			head:FindFirstChild(name)

		if old
			and old:IsA("Decal") then

			old:Destroy()
		end

		return nil
	end

	local existing =
		head:FindFirstChild(name)

	local decal: Decal

	if existing
		and existing:IsA("Decal") then

		decal = existing
	else
		if existing then
			existing:Destroy()
		end

		decal =
			Instance.new("Decal")

		decal.Name = name
		decal.Face = Enum.NormalId.Front
		decal.Parent = head
	end

	decal.Face = Enum.NormalId.Front
	decal.Texture = image

	pcall(function()
		decal.ZIndex = zIndex
	end)

	return decal
end

local function applyFaceLayersRaw(
	player: Player,
	character: Model,
	appearance: {[string]: any}
)
	local catalog =
		getAppearanceCatalog()

	if not catalog
		or not validateAppearanceCatalog() then

		return
	end

	local defaults =
		typeof(catalog.Defaults) == "table"
		and catalog.Defaults
		or {}

	local mouthStyleId =
		typeof(appearance.MouthStyleId) == "string"
		and appearance.MouthStyleId
		or defaults.MouthStyleId

	local browStyleId =
		typeof(appearance.BrowStyleId) == "string"
		and appearance.BrowStyleId
		or defaults.BrowStyleId

	local eyeStyleId =
		typeof(appearance.EyeStyleId) == "string"
		and appearance.EyeStyleId
		or defaults.EyeStyleId

	local mouthEntry =
		typeof(catalog.GetMouthStyle) == "function"
		and typeof(mouthStyleId) == "string"
		and catalog.GetMouthStyle(
			mouthStyleId
		)
		or nil

	local browEntry =
		typeof(catalog.GetBrowStyle) == "function"
		and typeof(browStyleId) == "string"
		and catalog.GetBrowStyle(
			browStyleId
		)
		or nil

	local eyeEntry =
		typeof(catalog.GetEyeStyle) == "function"
		and typeof(eyeStyleId) == "string"
		and catalog.GetEyeStyle(
			eyeStyleId
		)
		or nil

	local head =
		character:
		FindFirstChild("Head")

	if not head
		or not head:IsA("BasePart") then

		return
	end

	removeDefaultRobloxFace(head)

	local eyeVariantId =
		player:GetAttribute(
			"CharacterEyeVariantId"
		)

	if typeof(eyeVariantId) ~= "string"
		or eyeVariantId == "" then

		eyeVariantId = "Base"
	end

	local eyeImage =
		typeof(catalog.GetEyeImage) == "function"
		and typeof(eyeStyleId) == "string"
		and catalog.GetEyeImage(
			eyeStyleId,
			eyeVariantId
		)
		or (
			typeof(eyeEntry) == "table"
			and eyeEntry.Image
			or nil
		)

	upsertFaceDecal(
		head,
		"WAYLESS_Eyes",
		eyeImage,
		10
	)

	upsertFaceDecal(
		head,
		"WAYLESS_Brows",
		typeof(browEntry) == "table"
			and browEntry.Image
			or nil,
		20
	)

	upsertFaceDecal(
		head,
		"WAYLESS_Mouth",
		typeof(mouthEntry) == "table"
			and mouthEntry.Image
			or nil,
		30
	)
end


local function applyFaceLayers(
	player: Player,
	character: Model,
	appearance: {[string]: any}
)
	if faceApplying[player] then
		return
	end

	faceApplying[player] = true

	local ok, err =
		pcall(
			applyFaceLayersRaw,
			player,
			character,
			appearance
		)

	faceApplying[player] = nil

	if not ok then
		warn(
			"[CharacterIdentityService] FACE APPLY FAILED",
			player.Name,
			err
		)
		return
	end

	local head =
		character:
		FindFirstChild("Head")

	if head
		and head:IsA("BasePart") then

		local eyes =
			head:FindFirstChild("WAYLESS_Eyes")

		local brows =
			head:FindFirstChild("WAYLESS_Brows")

		local mouth =
			head:FindFirstChild("WAYLESS_Mouth")

		local defaultFace =
			head:FindFirstChild("face")
			or head:FindFirstChild("Face")

		print(
			"[CharacterIdentityService] FACE APPLIED",
			player.Name,
			"Mouth="
				.. tostring(
					player:GetAttribute(
						"CharacterAppearanceMouthStyleId"
					)
				),
			"Brows="
				.. tostring(
					player:GetAttribute(
						"CharacterAppearanceBrowStyleId"
					)
				),
			"Eyes="
				.. tostring(
					player:GetAttribute(
						"CharacterBaseEyeStyleId"
					)
				),
			"EyesDecal="
				.. tostring(
					eyes ~= nil
				),
			"BrowsDecal="
				.. tostring(
					brows ~= nil
				),
			"MouthDecal="
				.. tostring(
					mouth ~= nil
				),
			"DefaultFace="
				.. tostring(
					defaultFace ~= nil
				)
		)
	end
end

local function currentAppearance(
	player: Player
): {[string]: any}?
	local _, _, summary =
		currentSummary(
			player
		)

	if typeof(summary) ~= "table"
		or typeof(summary.Appearance) ~= "table" then

		return nil
	end

	return summary.Appearance
end

local function reapplyCurrentFace(
	player: Player,
	character: Model
)
	if player.Character ~= character then
		return
	end

	local appearance =
		currentAppearance(
			player
		)

	if not appearance then
		warn(
			"[CharacterIdentityService] FACE REAPPLY SKIPPED - NO APPEARANCE",
			player.Name
		)
		return
	end

end

local function queueFaceReapply(
	player: Player,
	character: Model
)
	if player.Character ~= character
		or faceApplying[player]
		or faceReapplyQueued[player] then

		return
	end

	faceReapplyQueued[player] = true

	task.defer(function()
		faceReapplyQueued[player] = nil

		if player.Character ~= character then
			return
		end

		reapplyCurrentFace(
			player,
			character
		)
	end)
end

local function disconnectFaceGuard(
	player: Player
)
	local guards =
		faceGuardConnections[player]

	if guards then
		for _, connection in ipairs(guards) do
			connection:Disconnect()
		end
	end

	faceGuardConnections[player] = nil
	faceReapplyQueued[player] = nil
end

local function isCurrentHeadDescendant(
	character: Model,
	instance: Instance
): boolean
	local head =
		character:
		FindFirstChild("Head")

	if not head then
		return false
	end

	return instance == head
		or instance:IsDescendantOf(head)
end

local function bindFaceGuard(
	player: Player,
	character: Model
)

	local guards: {RBXScriptConnection} = {}
	faceGuardConnections[player] = guards

	-- Character-level guard survives a full Head replacement and blocks any
	-- default Roblox face added after WAYLESS initialization.
	table.insert(
		guards,
		character.DescendantAdded:
			Connect(function(instance)
				if player.Character ~= character
					or faceApplying[player] then

					return
				end

				if instance:IsA("BasePart")
					and instance.Name == "Head" then

					print(
						"[CharacterIdentityService] HEAD ADDED/REPLACED",
						player.Name
					)

					queueFaceReapply(
						player,
						character
					)

					return
				end

				if instance:IsA("Decal")
					and isCurrentHeadDescendant(
						character,
						instance
					)
					and (
						instance.Name == "face"
						or instance.Name == "Face"
					) then

					print(
						"[CharacterIdentityService] DEFAULT FACE BLOCKED",
						player.Name,
						instance.Texture
					)

					instance:Destroy()

					queueFaceReapply(
						player,
						character
					)
				end
			end)
	)

	table.insert(
		guards,
		character.ChildAdded:
			Connect(function(child)
				if player.Character ~= character
					or faceApplying[player] then

					return
				end

				if child:IsA("BasePart")
					and child.Name == "Head" then

					queueFaceReapply(
						player,
						character
					)
				end
			end)
	)

	queueFaceReapply(
		player,
		character
	)
end

local R6_VISIBLE_PARTS = {
	"Head",
	"Torso",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
}

local function applyR6Skin(
	character: Model,
	color: Color3
)
	for _, partName in ipairs(
		R6_VISIBLE_PARTS
		) do
		local part =
			character:
			FindFirstChild(
				partName
			)

		if part
			and part:IsA("BasePart") then

			part.Color = color
		end
	end

	local bodyColors =
		character:
		FindFirstChildOfClass(
			"BodyColors"
		)

	if not bodyColors then
		bodyColors =
			Instance.new(
				"BodyColors"
			)

		bodyColors.Parent =
			character
	end

	bodyColors.HeadColor3 = color
	bodyColors.LeftArmColor3 = color
	bodyColors.RightArmColor3 = color
	bodyColors.LeftLegColor3 = color
	bodyColors.RightLegColor3 = color
	bodyColors.TorsoColor3 = color
end

local function removeAvatarBodyAndCosmetics(
	character: Model
)
	-- Enforce the exact same classic blocky R6 body for every shinobi.
	for _, child in ipairs(
		character:GetChildren()
		) do
		if child:IsA("CharacterMesh")
			or child:IsA("Accessory")
			or child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic") then

			child:Destroy()
		end
	end
end

local function resolveStarterTopId(
	catalog: any,
	raw: any
): string?
	local candidate =
		typeof(raw) == "string"
		and raw
		or nil

	if candidate
		and typeof(catalog.IsValidStarterTop) == "function"
		and catalog.IsValidStarterTop(candidate) then

		return candidate
	end

	local fallback =
		catalog.Defaults
		and catalog.Defaults.StarterTopId
		or nil

	return typeof(fallback) == "string"
		and fallback
		or nil
end

local function resolveStarterBottomId(
	catalog: any,
	raw: any
): string?
	local candidate =
		typeof(raw) == "string"
		and raw
		or nil

	if candidate
		and typeof(catalog.IsValidStarterBottom) == "function"
		and catalog.IsValidStarterBottom(candidate) then

		return candidate
	end

	local fallback =
		catalog.Defaults
		and catalog.Defaults.StarterBottomId
		or nil

	return typeof(fallback) == "string"
		and fallback
		or nil
end

local function resolveShoesStyleId(
	catalog: any,
	raw: any
): string?
	local candidate =
		typeof(raw) == "string"
		and raw
		or (
			catalog.Defaults
			and catalog.Defaults.ShoesStyleId
			or nil
		)

	if candidate
		and typeof(catalog.IsValidShoesStyle) == "function"
		and catalog.IsValidShoesStyle(candidate) then

		return candidate
	end

	return catalog.Defaults
		and catalog.Defaults.ShoesStyleId
		or nil
end

local function resolveGlovesStyleId(
	catalog: any,
	raw: any
): string?
	local candidate =
		typeof(raw) == "string"
		and raw
		or (
			catalog.Defaults
			and catalog.Defaults.GlovesStyleId
			or nil
		)

	if candidate
		and typeof(catalog.IsValidGlovesStyle) == "function"
		and catalog.IsValidGlovesStyle(candidate) then

		return candidate
	end

	return catalog.Defaults
		and catalog.Defaults.GlovesStyleId
		or nil
end

local R6_WEARABLE_ATTACHMENTS = {
	{
		PartName = "Left Arm",
		AttachmentName = "WAYLESS_LeftGloveAttachment",
		Position = Vector3.new(0, -0.80, 0),
		Orientation = Vector3.new(90, 180, 0),
	},
	{
		PartName = "Right Arm",
		AttachmentName = "WAYLESS_RightGloveAttachment",
		Position = Vector3.new(0, -0.80, 0),
		Orientation = Vector3.new(90, 0, 0),
	},
	{
		PartName = "Left Leg",
		AttachmentName = "WAYLESS_LeftShoeAttachment",
		Position = Vector3.new(0, -1, 0),
		Orientation = Vector3.new(0, 180, 0),
	},
	{
		PartName = "Right Leg",
		AttachmentName = "WAYLESS_RightShoeAttachment",
		Position = Vector3.new(0, -1, 0),
		Orientation = Vector3.new(0, 180, 0),
	},
}

local function ensureR6WearableAttachments(
	character: Model
)
	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.RigType
		~= Enum.HumanoidRigType.R6 then

		return
	end

	for _, definition in ipairs(
		R6_WEARABLE_ATTACHMENTS
		) do
		local bodyPart =
			character:
			FindFirstChild(
				definition.PartName
			)

		if bodyPart
			and bodyPart:IsA("BasePart") then

			local attachment =
				bodyPart:
				FindFirstChild(
					definition.AttachmentName
				)

			if attachment
				and not attachment:IsA("Attachment") then

				attachment:Destroy()
				attachment = nil
			end

			if not attachment then
				attachment =
					Instance.new(
						"Attachment"
					)

				attachment.Name =
					definition.AttachmentName

				attachment.Parent =
					bodyPart
			end

			local typedAttachment =
				attachment :: Attachment

			typedAttachment.Position =
				definition.Position

			typedAttachment.Orientation =
				definition.Orientation
		end
	end
end

local function removeWaylessWearables(
	character: Model,
	categoryName: string
)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory")
			and child:GetAttribute(
				"WAYLESSWearableCategory"
			) == categoryName then

			child:Destroy()
		end
	end
end

local function getWearableTemplatesRoot(): Folder?
	local shared =
		ReplicatedStorage:
		FindFirstChild(
			"Shared"
		)

	local root =
		shared
		and shared:
		FindFirstChild(
			"CharacterWearableTemplates"
		)

	return root
		and root:IsA("Folder")
		and root
		or nil
end

local function ensureWearableTemplatesReady(): boolean
	local existing =
		getWearableTemplatesRoot()

	if existing
		and existing:GetAttribute("Ready") == true then

		return true
	end

	-- CharacterIdentityService can start before the standalone wearable
	-- bootstrap. Initialize the same service here as an idempotent fallback so
	-- character appearance can never race template loading in the World place.
	local module =
		Services:
		FindFirstChild(
			"CharacterWearableAssetService"
		)

	if not module
		or not module:IsA("ModuleScript") then

		warn(
			"[CharacterIdentityService] WEARABLE SERVICE MISSING"
		)

		return false
	end

	local requireOk, service =
		pcall(
			require,
			module
		)

	if not requireOk
		or typeof(service) ~= "table"
		or typeof(service.Initialize) ~= "function" then

		warn(
			"[CharacterIdentityService] WEARABLE SERVICE REQUIRE FAILED",
			service
		)

		return false
	end

	local initOk, initResult =
		pcall(
			service.Initialize
		)

	if not initOk then
		warn(
			"[CharacterIdentityService] WEARABLE SERVICE INIT FAILED",
			initResult
		)

		return false
	end

	local shared =
		ReplicatedStorage:
		FindFirstChild(
			"Shared"
		)

	local root =
		shared
		and shared:
		WaitForChild(
			"CharacterWearableTemplates",
			10
		)

	local ready =
		root ~= nil
		and root:IsA("Folder")
		and root:GetAttribute("Ready") == true

	if not ready then
		warn(
			"[CharacterIdentityService] WEARABLE TEMPLATES NOT READY",
			"InitializeResult=" .. tostring(initResult)
		)

		return false
	end

	print(
		"[CharacterIdentityService] WEARABLE TEMPLATES READY",
		"Loaded="
			.. tostring(
				root:GetAttribute("LoadedCount")
			),
		"Expected="
			.. tostring(
				root:GetAttribute("ExpectedCount")
			)
	)

	return true
end

local function getWearableStyleFolder(
	categoryName: string,
	styleId: string
): Folder?
	if not ensureWearableTemplatesReady() then
		return nil
	end

	local root =
		getWearableTemplatesRoot()

	if not root then
		return nil
	end

	local category =
		root:
		FindFirstChild(
			categoryName
		)

	local style =
		category
		and category:
		FindFirstChild(
			styleId
		)

	return style
		and style:IsA("Folder")
		and style
		or nil
end

local function findCharacterAttachment(
	character: Model,
	attachmentName: string
): Attachment?
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Attachment")
			and descendant.Name == attachmentName then

			local accessoryAncestor =
				descendant:
				FindFirstAncestorOfClass(
					"Accessory"
				)

			if not accessoryAncestor then
				return descendant
			end
		end
	end

	return nil
end

local function findWearableHandleAttachment(
	accessory: Accessory
): Attachment?
	local handle =
		accessory:
		FindFirstChild(
			"Handle"
		)

	if not handle
		or not handle:IsA("BasePart") then

		return nil
	end

	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment")
			and string.sub(
				child.Name,
				1,
				8
			) == "WAYLESS_" then

			return child
		end
	end

	return nil
end

local function weldWearableAccessory(
	character: Model,
	accessory: Accessory
): boolean
	local handle =
		accessory:
		FindFirstChild(
			"Handle"
		)

	if not handle
		or not handle:IsA("BasePart") then

		return false
	end

	local handleAttachment =
		findWearableHandleAttachment(
			accessory
		)

	if not handleAttachment then
		return false
	end

	local bodyAttachment =
		findCharacterAttachment(
			character,
			handleAttachment.Name
		)

	if not bodyAttachment
		or not bodyAttachment.Parent
		or not bodyAttachment.Parent:IsA("BasePart") then

		warn(
			"[WAYLESS Wearable] BODY ATTACHMENT MISSING",
			handleAttachment.Name
		)

		return false
	end

	local bodyPart =
		bodyAttachment.Parent :: BasePart

	local oldWeld =
		handle:
		FindFirstChild(
			"AccessoryWeld"
		)

	if oldWeld then
		oldWeld:Destroy()
	end

	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Massless = true

	accessory.Parent =
		character

	handle.CFrame =
		bodyAttachment.WorldCFrame
		* handleAttachment.CFrame:Inverse()

	local weld =
		Instance.new(
			"Weld"
		)

	weld.Name =
		"AccessoryWeld"

	weld.Part0 =
		bodyPart

	weld.Part1 =
		handle

	weld.C0 =
		bodyAttachment.CFrame

	weld.C1 =
		handleAttachment.CFrame

	weld.Parent =
		handle

	return true
end

local function applyWaylessWearable(
	character: Model,
	categoryName: string,
	styleId: string?
)
	removeWaylessWearables(
		character,
		categoryName
	)

	if not styleId then
		return
	end

	local catalog =
		getAppearanceCatalog()

	local style: any = nil

	if catalog then
		if categoryName == "Shoes"
			and typeof(catalog.GetShoesStyle) == "function" then

			style =
				catalog.GetShoesStyle(
					styleId
				)

		elseif categoryName == "Gloves"
			and typeof(catalog.GetGlovesStyle) == "function" then

			style =
				catalog.GetGlovesStyle(
					styleId
				)
		end
	end

	if typeof(style) == "table"
		and style.None == true then

		return
	end

	local template =
		getWearableStyleFolder(
			categoryName,
			styleId
		)

	if not template then
		warn(
			"[CharacterIdentityService] WEARABLE TEMPLATE MISSING",
			categoryName,
			styleId
		)

		return
	end

	ensureR6WearableAttachments(
		character
	)

	local attachedCount = 0

	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("Accessory") then
			local clone =
				child:Clone()

			clone:SetAttribute(
				"WAYLESSWearableCategory",
				categoryName
			)

			clone:SetAttribute(
				"WAYLESSWearableStyleId",
				styleId
			)

			if weldWearableAccessory(
				character,
				clone
				) then

				attachedCount += 1
			else
				clone:Destroy()

				warn(
					"[CharacterIdentityService] WEARABLE ATTACH FAILED",
					categoryName,
					styleId,
					child.Name
				)
			end
		end
	end

	print(
		"[CharacterIdentityService] WEARABLE APPLIED",
		categoryName,
		styleId,
		"Count=" .. tostring(attachedCount)
	)
end

local function starterOutfitTemplates(
	starterOutfit: {[string]: any}
): (string?, string?)
	local catalog =
		getAppearanceCatalog()

	if not catalog then
		return nil, nil
	end

	local shirtTemplate: string? = nil
	local pantsTemplate: string? = nil

	local topId =
		resolveStarterTopId(
			catalog,
			starterOutfit.TopId
		)

	if topId
		and typeof(catalog.GetStarterTop) == "function" then

		local top =
			catalog.GetStarterTop(
				topId
			)

		if typeof(top) == "table"
			and typeof(top.ShirtTemplate) == "string"
			and top.ShirtTemplate ~= "" then

			shirtTemplate =
				top.ShirtTemplate
		end
	end

	local bottomId =
		resolveStarterBottomId(
			catalog,
			starterOutfit.BottomId
		)

	if bottomId
		and typeof(catalog.GetStarterBottom) == "function" then

		local bottom =
			catalog.GetStarterBottom(
				bottomId
			)

		if typeof(bottom) == "table"
			and typeof(bottom.PantsTemplate) == "string"
			and bottom.PantsTemplate ~= "" then

			pantsTemplate =
				bottom.PantsTemplate
		end
	end

	return shirtTemplate,
		pantsTemplate
end

local function applyStarterClassicClothing(
	character: Model,
	starterOutfit: {[string]: any}
)
	local shirtTemplate,
		pantsTemplate =
		starterOutfitTemplates(
			starterOutfit
		)

	if shirtTemplate then
		local shirt =
			Instance.new("Shirt")

		shirt.Name =
			"WAYLESSStarterTop"

		shirt.ShirtTemplate =
			shirtTemplate

		shirt.Parent =
			character
	end

	if pantsTemplate then
		local pants =
			Instance.new("Pants")

		pants.Name =
			"WAYLESSStarterBottom"

		pants.PantsTemplate =
			pantsTemplate

		pants.Parent =
			character
	end
end

local function applyAppearance(
	player: Player,
	character: Model,
	summary: {[string]: any}
)
	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid then
		return
	end

	if humanoid.RigType
		~= Enum.HumanoidRigType.R6 then

		warn(
			"[CharacterIdentityService] NON-R6 CHARACTER SKIPPED",
			player.Name,
			humanoid.RigType.Name
		)

		return
	end

	local appearance =
		typeof(summary.Appearance) == "table"
		and summary.Appearance
		or {}

	local starterOutfit =
		typeof(summary.StarterOutfit) == "table"
		and summary.StarterOutfit
		or {}

	-- Never call ApplyDescription/ApplyDescriptionReset on the actual WAYLESS
	-- R6 body. Those APIs can rebuild or remove R6 body parts when body asset
	-- IDs are zero. We keep the body fixed and layer cosmetics onto it.
	removeAvatarBodyAndCosmetics(
		character
	)

	local skinColor =
		getSkinColor(
			appearance.SkinToneId
		)

	if skinColor then
		applyR6Skin(
			character,
			skinColor
		)
	end

	local hairString =
		hairIdsToString(
			appearance.HairAssetIds
		)

	-- Legacy compatibility.
	if hairString == nil
		and typeof(appearance.HairStyleId) == "string"
		and appearance.HairStyleId ~= "RobloxAvatar" then

		local oldHairId =
			math.floor(
				tonumber(
					appearance.HairStyleId
				) or 0
			)

		if oldHairId > 0 then
			hairString =
				tostring(oldHairId)
		end
	end

	-- Create a disposable native R6 model only to let Roblox resolve catalog
	-- asset IDs into Accessory/Shirt/Pants instances. The source body's parts
	-- are never copied to the gameplay character.
	local sourceDescription =
		Instance.new(
			"HumanoidDescription"
		)

	if hairString ~= nil
		and hairString ~= "" then

		sourceDescription.HairAccessory =
			hairString
	end

	local sourceOk,
		sourceResult =
		pcall(function()
			return Players:
			CreateHumanoidModelFromDescriptionAsync(
				sourceDescription,
				Enum.HumanoidRigType.R6
			)
		end)

	sourceDescription:Destroy()

	if sourceOk
		and typeof(sourceResult) == "Instance"
		and sourceResult:IsA("Model") then

		local source =
			sourceResult :: Model


		for _, child in ipairs(
			source:GetChildren()
			) do
			if child:IsA("Accessory") then
				humanoid:
					AddAccessory(
						child:Clone()
					)
			end
		end

		source:Destroy()
	else
		warn(
			"[CharacterIdentityService] COSMETIC SOURCE LOAD FAILED",
			player.Name,
			sourceResult
		)
	end

	local catalog =
		getAppearanceCatalog()

	if catalog then
		local shoesStyleId =
			resolveShoesStyleId(
				catalog,
				appearance.ShoesStyleId
			)

		local glovesStyleId =
			resolveGlovesStyleId(
				catalog,
				appearance.GlovesStyleId
			)

		applyWaylessWearable(
			character,
			"Shoes",
			shoesStyleId
		)

		applyWaylessWearable(
			character,
			"Gloves",
			glovesStyleId
		)
	end

	applyStarterClassicClothing(
		character,
		starterOutfit
	)

end

local function applyCharacter(
	player: Player,
	character: Model
)
	local _, _, summary =
		currentSummary(
			player
		)

	if not summary then
		return
	end

	applyAppearance(
		player,
		character,
		summary
	)

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if humanoid then
		local displayName =
			player:GetAttribute(
				"ShinobiDisplayName"
			)

		if typeof(displayName) == "string"
			and displayName ~= "" then

			humanoid.DisplayName =
				displayName
		end
	end
end

local function defaultFaceStyleId(
	catalog: any,
	fieldName: string
): string?
	if catalog
		and typeof(catalog.Defaults) == "table" then

		local value =
			catalog.Defaults[fieldName]

		if typeof(value) == "string"
			and value ~= "" then

			return value
		end
	end

	return nil
end

local function resolveMouthStyleForCatalogV6(
	appearance: {[string]: any},
	catalog: any
): string?
	local fallback =
		defaultFaceStyleId(
			catalog,
			"MouthStyleId"
		)

	local raw =
		typeof(appearance.MouthStyleId) == "string"
		and appearance.MouthStyleId
		or fallback

	local version =
		tonumber(appearance.Version) or 0

	-- v4 used only the removed legacy mouth pack.
	if version <= 4 then
		return fallback
	end

	-- v5 had our Mouth_01..13 first, then removed legacy mouths at 14..35.
	if version == 5 then
		local index =
			typeof(raw) == "string"
			and tonumber(
				string.match(
					raw,
					"^Mouth_(%d+)$"
				)
			)
			or nil

		if not index
			or index < 1
			or index > 13 then

			return fallback
		end
	end

	if catalog
		and typeof(catalog.IsValidMouthStyle) == "function"
		and typeof(raw) == "string"
		and catalog.IsValidMouthStyle(raw) then

		return raw
	end

	return fallback
end

local function resolveBrowStyleForCatalogV6(
	appearance: {[string]: any},
	catalog: any
): string?
	local fallback =
		defaultFaceStyleId(
			catalog,
			"BrowStyleId"
		)

	local raw =
		typeof(appearance.BrowStyleId) == "string"
		and appearance.BrowStyleId
		or fallback

	local version =
		tonumber(appearance.Version) or 0

	-- v4 brows belonged to the removed legacy pack.
	if version <= 4 then
		return fallback
	end

	-- v5 stored our new brows as Brows_13..22 because legacy brows occupied
	-- 01..12. In v6 our brows are the only brows and are renumbered 01..10.
	if version == 5
		and typeof(raw) == "string" then

		local oldIndex =
			tonumber(
				string.match(
					raw,
					"^Brows_(%d+)$"
				)
			)

		if oldIndex
			and oldIndex >= 13
			and oldIndex <= 22 then

			raw =
				string.format(
					"Brows_%02d",
					oldIndex - 12
				)
		else
			-- v5 Brows_01..12 were legacy and are intentionally removed.
			return fallback
		end
	end

	if catalog
		and typeof(catalog.IsValidBrowStyle) == "function"
		and typeof(raw) == "string"
		and catalog.IsValidBrowStyle(raw) then

		return raw
	end

	return fallback
end

local function resolveNoseStyleForCatalogV6(
	appearance: {[string]: any},
	catalog: any
): string?
	local fallback =
		defaultFaceStyleId(
			catalog,
			"NoseStyleId"
		)

	local raw =
		typeof(appearance.NoseStyleId) == "string"
		and appearance.NoseStyleId
		or fallback

	if catalog
		and typeof(catalog.IsValidNoseStyle) == "function"
		and typeof(raw) == "string"
		and catalog.IsValidNoseStyle(raw) then

		return raw
	end

	return fallback
end

local function resolveEyeStyleForCatalogV6(
	appearance: {[string]: any},
	catalog: any
): string?
	local fallback =
		defaultFaceStyleId(
			catalog,
			"EyeStyleId"
		)

	local raw =
		typeof(appearance.EyeStyleId) == "string"
		and appearance.EyeStyleId
		or fallback

	if catalog
		and typeof(catalog.IsValidEyeStyle) == "function"
		and typeof(raw) == "string"
		and catalog.IsValidEyeStyle(raw) then

		return raw
	end

	return fallback
end

local function loadPlayer(
	player: Player
)
	AccountProfileService.Start()
	CharacterLifeContextService.Start()

	local ready =
		CharacterLifeContextService.WaitUntilReady(
			player,
			30
		)

	if not ready then
		warn(
			"[CharacterIdentityService] LIFE CONTEXT NOT READY",
			player.Name
		)
		return
	end

	local slotId,
		lifeId,
		summary =
		currentSummary(
			player
		)

	local slot =
		slotId
		and AccountProfileService.GetSlot(
			player,
			slotId
		)
		or nil

	local origin =
		slot
		and slot.PermanentOrigin
		or nil

	local clanId =
		typeof(origin) == "table"
		and tostring(
			origin.ClanId or ""
		)
		or ""

	local surname =
		clanId ~= ""
		and clanDisplayName(
			clanId
		)
		or ""

	local givenName =
		typeof(summary) == "table"
		and typeof(summary.GivenName) == "string"
		and summary.GivenName ~= ""
		and summary.GivenName
		or player.DisplayName

	local displayName =
		surname ~= ""
		and (
			givenName
			.. " "
			.. surname
		)
		or givenName

	player:SetAttribute(
		"CharacterIdentityReady",
		true
	)

	player:SetAttribute(
		"ShinobiGivenName",
		givenName
	)

	player:SetAttribute(
		"ShinobiClanSurname",
		surname ~= ""
			and surname
			or nil
	)

	player:SetAttribute(
		"ShinobiDisplayName",
		displayName
	)

	player:SetAttribute(
		"ShinobiVillageId",
		typeof(summary) == "table"
			and summary.VillageId
			or nil
	)

	player:SetAttribute(
		"CharacterCreationVersion",
		typeof(summary) == "table"
			and summary.CreationVersion
			or nil
	)

	local appearance =
		typeof(summary) == "table"
		and typeof(summary.Appearance) == "table"
		and summary.Appearance
		or {}

	local starterOutfit =
		typeof(summary) == "table"
		and typeof(summary.StarterOutfit) == "table"
		and summary.StarterOutfit
		or {}

	local catalog =
		getAppearanceCatalog()

	local catalogReady =
		validateAppearanceCatalog()

	print(
		"[CharacterIdentityService] APPEARANCE CATALOG",
		player.Name,
		"Version="
			.. tostring(
				catalog
				and catalog.Version
				or "nil"
			),
		"ModularFaces="
			.. tostring(
				catalogReady
			)
	)

	local skinToneId =
		typeof(appearance.SkinToneId) == "string"
		and appearance.SkinToneId
		or nil

	if catalog
		and skinToneId
		and typeof(catalog.ResolveSkinToneId) == "function" then

		skinToneId =
			catalog.ResolveSkinToneId(
				skinToneId
			) or skinToneId
	end

	player:SetAttribute(
		"CharacterAppearanceRigType",
		"R6"
	)

	player:SetAttribute(
		"CharacterAppearanceSkinToneId",
		skinToneId
	)


	local mouthStyleId =
		resolveMouthStyleForCatalogV6(
			appearance,
			catalog
		)

	local browStyleId =
		resolveBrowStyleForCatalogV6(
			appearance,
			catalog
		)

	local noseStyleId =
		resolveNoseStyleForCatalogV6(
			appearance,
			catalog
		)

	local eyeStyleId =
		resolveEyeStyleForCatalogV6(
			appearance,
			catalog
		)

	player:SetAttribute(
		"CharacterAppearanceMouthStyleId",
		mouthStyleId
	)

	player:SetAttribute(
		"CharacterAppearanceBrowStyleId",
		browStyleId
	)

	player:SetAttribute(
		"CharacterAppearanceNoseStyleId",
		noseStyleId
	)

	player:SetAttribute(
		"CharacterBaseEyeStyleId",
		eyeStyleId
	)

	player:SetAttribute(
		"CharacterEyeStyleId",
		eyeStyleId
	)

	player:SetAttribute(
		"CharacterEyeVariantId",
		"Base"
	)

	local hairString =
		hairIdsToString(
			appearance.HairAssetIds
		)

	player:SetAttribute(
		"CharacterAppearanceHairAssetIds",
		hairString
	)

	local resolvedShoesStyleId =
		catalog
		and resolveShoesStyleId(
			catalog,
			appearance.ShoesStyleId
		)
		or nil

	local resolvedGlovesStyleId =
		catalog
		and resolveGlovesStyleId(
			catalog,
			appearance.GlovesStyleId
		)
		or nil

	player:SetAttribute(
		"CharacterAppearanceShoesStyleId",
		resolvedShoesStyleId
	)

	player:SetAttribute(
		"CharacterAppearanceGlovesStyleId",
		resolvedGlovesStyleId
	)

	local resolvedStarterTopId =
		catalog
		and resolveStarterTopId(
			catalog,
			starterOutfit.TopId
		)
		or nil

	local resolvedStarterBottomId =
		catalog
		and resolveStarterBottomId(
			catalog,
			starterOutfit.BottomId
		)
		or nil

	player:SetAttribute(
		"CharacterStarterTopId",
		resolvedStarterTopId
	)

	player:SetAttribute(
		"CharacterStarterBottomId",
		resolvedStarterBottomId
	)


	connections[player] =
		connections[player]
		or {}

	-- Apply once as soon as a character exists. This gives fast feedback, but
	-- Roblox may still be loading the user's avatar appearance afterward.
	table.insert(
		connections[player],
		player.CharacterAdded:
			Connect(function(character)
				task.defer(
					applyCharacter,
					player,
					character
				)
			end)
	)

	-- AUTHORITATIVE PASS:
	-- Roblox can insert the user's Shirt/Pants/accessories after CharacterAdded.
	-- Re-apply WAYLESS appearance only after that avatar load finishes so the
	-- player's Roblox clothing can never win the race.
	table.insert(
		connections[player],
		player.CharacterAppearanceLoaded:
			Connect(function(character)
				if player.Character ~= character then
					return
				end

				task.defer(function()
					applyCharacter(
						player,
						character
					)


					print(
						"[CharacterIdentityService] POST-AVATAR APPEARANCE APPLIED",
						player.Name,
						"Top="
						.. tostring(
							player:GetAttribute(
								"CharacterStarterTopId"
							)
						),
						"Bottom="
						.. tostring(
							player:GetAttribute(
								"CharacterStarterBottomId"
							)
						)
					)
				end)
			end)
	)

	-- Connect events BEFORE touching the current character so we cannot miss
	-- CharacterAppearanceLoaded in the small startup window.
	if player.Character then
		local currentCharacter =
			player.Character

		task.defer(
			applyCharacter,
			player,
			currentCharacter
		)

	end

	print(
		"[CharacterIdentityService] LOADED",
		player.Name,
		"Slot=" .. tostring(slotId),
		"Life=" .. tostring(lifeId),
		"DisplayName=" .. displayName,
		"Village="
			.. tostring(
				player:GetAttribute(
					"ShinobiVillageId"
				)
			),
		"EyeStyle="
			.. tostring(eyeStyleId)
	)
end

local function unloadPlayer(
	player: Player
)
	disconnectFaceGuard(player)
	faceApplying[player] = nil

	local list =
		connections[player]

	if list then
		for _, connection in ipairs(list) do
			connection:Disconnect()
		end
	end

	connections[player] = nil
end

function CharacterIdentityService.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(
			loadPlayer,
			player
		)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(
			loadPlayer,
			player
		)
	end)

	Players.PlayerRemoving:Connect(
		unloadPlayer
	)

	print(
		"[CharacterIdentityService] READY v3.11"
			.. " | NativeR6Body=ON"
			.. " | Hair=ON"
			.. " | StarterOutfitCatalog=ON"
			.. " | PostAvatarReapply=ON"
			.. " | EyeStyleAttribute=ON"
			.. " | FaceVisualOwner=Client"
			.. " | CatalogVersionRequired=4"
	)
end

return CharacterIdentityService
