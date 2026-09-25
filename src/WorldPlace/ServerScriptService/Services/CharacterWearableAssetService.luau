--!strict
-- ServerScriptService > Services > CharacterWearableAssetService
--
-- WAYLESS Character Wearable Asset Service v1.1
--
-- Loads 3D wearable assets server-side and exposes normalized Accessory
-- templates in ReplicatedStorage for both the Frontend preview and World.
--
-- Supported uploaded asset shape:
--   Model returned by AssetService:LoadAssetAsync()
--     └─ one or more Accessory descendants
--
-- Shoes can contain two Accessories (left/right).
-- Gloves can contain two Accessories (left/right).
--
-- If an uploaded asset is only a raw Model/MeshPart with no Accessory
-- descendants, the service logs a clear warning instead of guessing offsets.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterWearableAssetService = {}

local ROOT_NAME = "CharacterWearableTemplates"

local cachedReady = false

local function getShared(): Folder
	local existing = ReplicatedStorage:FindFirstChild("Shared")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Shared"
	folder.Parent = ReplicatedStorage
	return folder
end

local function clearOrCreateRoot(): Folder
	local shared = getShared()

	local old = shared:FindFirstChild(ROOT_NAME)
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root:SetAttribute("Ready", false)
	root.Parent = shared
	return root
end

local function collectAccessories(container: Instance): {Accessory}
	local result: {Accessory} = {}

	if container:IsA("Accessory") then
		table.insert(result, container)
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Accessory") then
			table.insert(result, descendant)
		end
	end

	return result
end

local function loadStyle(
	root: Folder,
	categoryName: string,
	styleId: string,
	assetId: number
): boolean
	local category =
		root:FindFirstChild(categoryName)

	if not category then
		category = Instance.new("Folder")
		category.Name = categoryName
		category.Parent = root
	end

	local styleFolder = Instance.new("Folder")
	styleFolder.Name = styleId
	styleFolder:SetAttribute("AssetId", assetId)
	styleFolder:SetAttribute("Loaded", false)
	styleFolder.Parent = category

	local ok, loaded =
		pcall(
			AssetService.LoadAssetAsync,
			AssetService,
			assetId
		)

	if not ok
		or typeof(loaded) ~= "Instance" then

		warn(
			"[CharacterWearableAssetService] LOAD FAILED",
			categoryName,
			styleId,
			assetId,
			loaded
		)

		return false
	end

	local accessories =
		collectAccessories(
			loaded
		)

	if #accessories == 0 then
		warn(
			"[CharacterWearableAssetService] NO ACCESSORY CONTENT",
			categoryName,
			styleId,
			assetId,
			"Upload/convert the 3D asset as Accessory content; raw Model offsets are not guessed."
		)

		loaded:Destroy()
		return false
	end

	local validCount = 0

	for index, accessory in ipairs(accessories) do
		local clone =
			accessory:Clone()

		clone.Name =
			string.format(
				"Accessory_%02d",
				index
			)

		clone:SetAttribute(
			"WAYLESSWearableCategory",
			categoryName
		)

		clone:SetAttribute(
			"WAYLESSWearableStyleId",
			styleId
		)

		local handle =
			clone:
			FindFirstChild(
				"Handle"
			)

		if not handle
			or not handle:IsA("BasePart") then

			warn(
				"[CharacterWearableAssetService] INVALID ACCESSORY HANDLE",
				categoryName,
				styleId,
				clone.Name
			)

			clone:Destroy()
			continue
		end

		handle.Anchored = false
		handle.CanCollide = false
		handle.CanTouch = false
		handle.Massless = true

		local waylessAttachment: Attachment? = nil

		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("Attachment")
				and string.sub(
					child.Name,
					1,
					8
				) == "WAYLESS_" then

				waylessAttachment =
					child

				break
			end
		end

		if not waylessAttachment then
			warn(
				"[CharacterWearableAssetService] MISSING WAYLESS ATTACHMENT",
				categoryName,
				styleId,
				clone.Name
			)

			clone:Destroy()
			continue
		end

		clone:SetAttribute(
			"WAYLESSAttachmentName",
			waylessAttachment.Name
		)

		clone.Parent =
			styleFolder

		validCount += 1
	end

	if validCount == 0 then
		warn(
			"[CharacterWearableAssetService] NO VALID ACCESSORIES",
			categoryName,
			styleId,
			assetId
		)

		loaded:Destroy()
		styleFolder:Destroy()
		return false
	end

	styleFolder:SetAttribute(
		"AccessoryCount",
		validCount
	)

	styleFolder:SetAttribute(
		"Loaded",
		true
	)

	print(
		"[CharacterWearableAssetService] LOADED",
		categoryName,
		styleId,
		"AssetId=" .. tostring(assetId),
		"Accessories=" .. tostring(validCount)
	)

	loaded:Destroy()
	return true
end

function CharacterWearableAssetService.Initialize(): boolean
	if cachedReady then
		return true
	end

	local catalogModule =
		getShared():
		FindFirstChild(
			"AppearanceCatalog"
		)

	if not catalogModule
		or not catalogModule:IsA("ModuleScript") then

		warn(
			"[CharacterWearableAssetService] AppearanceCatalog missing"
		)

		return false
	end

	local catalogOk, catalog =
		pcall(
			require,
			catalogModule
		)

	if not catalogOk
		or typeof(catalog) ~= "table" then

		warn(
			"[CharacterWearableAssetService] AppearanceCatalog require failed",
			catalog
		)

		return false
	end

	local root =
		clearOrCreateRoot()

	local loadedCount = 0
	local expectedCount = 0

	local categories = {
		{
			FolderName = "Shoes",
			Styles = catalog.ShoesStyles,
		},
		{
			FolderName = "Gloves",
			Styles = catalog.GlovesStyles,
		},
	}

	for _, category in ipairs(categories) do
		local styles =
			typeof(category.Styles) == "table"
			and category.Styles
			or {}

		for _, style in ipairs(styles) do
			if typeof(style) == "table"
				and style.Enabled ~= false
				and typeof(style.Id) == "string"
				and typeof(style.AssetId) == "number" then

				expectedCount += 1

				if loadStyle(
					root,
					category.FolderName,
					style.Id,
					style.AssetId
					) then

					loadedCount += 1
				end
			end
		end
	end

	root:SetAttribute(
		"LoadedCount",
		loadedCount
	)

	root:SetAttribute(
		"ExpectedCount",
		expectedCount
	)

	root:SetAttribute(
		"Ready",
		loadedCount == expectedCount
	)

	cachedReady =
		loadedCount == expectedCount

	print(
		"[CharacterWearableAssetService] READY v1.1",
		"Loaded="
			.. tostring(loadedCount)
			.. "/"
			.. tostring(expectedCount)
	)

	return cachedReady
end

return CharacterWearableAssetService
