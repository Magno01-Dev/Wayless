--!strict
-- EquipmentVisualService v4 - Attachment-Authored Sheath + Hand Mounting
-- ServerScriptService > EquipmentVisualService [ModuleScript]
--
-- Current scope:
-- - Reads Character.EquippedWeaponId.
-- - Clones authored weapon assets from:
--   ReplicatedStorage > EquipmentAssets > Weapons > <AssetName>
-- - Keeps Sheath mounted to the body.
-- - Moves the SAME Blade assembly between holstered/drawn states.
-- - Supports R6 and R15.
-- - Uses authored GripAttachment / HolsterAttachment.
--
-- IMPORTANT:
-- Katana asset baseline:
-- Katana
--   Blade
--     ... MeshParts ...
--     Cube.003
--       GripAttachment
--   Sheath
--     Cube.005
--       HolsterAttachment
--
-- Optional:
-- Add SheathedGripAttachment somewhere inside Sheath if you want the
-- actual Blade/hilt visibly aligned inside the sheath while holstered.
-- Until then, Blade is hidden while holstered and becomes visible on draw.

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local WeaponCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"WeaponCatalog"
		)
	)

local EquipmentVisualService = {}

local VISUAL_FOLDER_NAME =
	"WAYLESS_EquipmentVisuals"

local WEAPON_VISUAL_NAME =
	"WeaponVisual"

local VALID_STATES = {
	Holstered = true,
	Drawn = true,
	None = true,
}

local function getVisualFolder(
	character: Model
): Folder

	local existing =
		character:
		FindFirstChild(
			VISUAL_FOLDER_NAME
		)

	if existing
		and existing:IsA(
			"Folder"
		) then

		return existing
	end

	if existing then
		existing:
			Destroy()
	end

	local folder =
		Instance.new(
			"Folder"
		)

	folder.Name =
		VISUAL_FOLDER_NAME

	folder.Parent =
		character

	return folder
end

local function getCurrentWeaponVisual(
	character: Model
): Model?

	local folder =
		getVisualFolder(
			character
		)

	local visual =
		folder:
		FindFirstChild(
			WEAPON_VISUAL_NAME
		)

	if visual
		and visual:IsA(
			"Model"
		) then

		return visual
	end

	return nil
end

local function destroyWeaponVisual(
	character: Model
)

	local folder =
		getVisualFolder(
			character
		)

	local visual =
		folder:
		FindFirstChild(
			WEAPON_VISUAL_NAME
		)

	if visual then
		visual:
			Destroy()
	end
end

local function findAttachmentDeep(
	instance: Instance,
	name: string
): Attachment?

	local found =
		instance:
		FindFirstChild(
			name,
			true
		)

	if found
		and found:IsA(
			"Attachment"
		) then

		return found
	end

	return nil
end

local function findBasePartDeep(
	instance: Instance,
	name: string
): BasePart?

	local found =
		instance:
		FindFirstChild(
			name,
			true
		)

	if found
		and found:IsA(
			"BasePart"
		) then

		return found
	end

	return nil
end

local function collectBaseParts(
	instance: Instance
): {BasePart}

	local result = {}

	if instance:IsA(
		"BasePart"
		) then
		table.insert(
			result,
			instance
		)
	end

	for _,
		descendant in ipairs(
			instance:GetDescendants()
		) do

		if descendant:IsA(
			"BasePart"
			) then

			table.insert(
				result,
				descendant
			)
		end
	end

	return result
end

local function configurePart(
	part: BasePart
)

	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
end

local function prepareAssembly(
	container: Instance,
	root: BasePart
)

	local parts =
		collectBaseParts(
			container
		)

	for _,
		part in ipairs(
			parts
		) do

		configurePart(
			part
		)
	end

	for _,
		part in ipairs(
			parts
		) do

		if part ~= root then

			local weld =
				Instance.new(
					"WeldConstraint"
				)

			weld.Name =
				"WAYLESS_InternalWeld"

			weld.Part0 =
				root

			weld.Part1 =
				part

			weld.Parent =
				root
		end
	end
end

local function setAssemblyVisible(
	container: Instance,
	visible: boolean
)

	for _,
		part in ipairs(
			collectBaseParts(
				container
			)
		) do

		-- Preserve authored transparency when visible.
		-- Save it exactly once.
		local saved =
			part:GetAttribute(
				"WAYLESS_AuthoredTransparency"
			)

		if typeof(saved) ~= "number" then

			saved =
				part.Transparency

			part:SetAttribute(
				"WAYLESS_AuthoredTransparency",
				saved
			)
		end

		part.Transparency =
			if visible
			then saved
			else 1
	end
end

local function destroyMountWelds(
	root: BasePart
)

	for _,
		child in ipairs(
			root:GetChildren()
		) do

		if child:IsA(
			"WeldConstraint"
			)
				and child.Name ==
				"WAYLESS_MountWeld" then

			child:
				Destroy()
		end
	end
end

local function alignRootAttachmentToTarget(
	root: BasePart,
	rootAttachment: Attachment,
	targetPart: BasePart,
	targetAttachment: Attachment
)

	destroyMountWelds(
		root
	)

	-- RootCF * RootAttachmentCF = TargetPartCF * TargetAttachmentCF
	root.CFrame =
		targetPart.CFrame
		* targetAttachment.CFrame
		* rootAttachment.CFrame:
		Inverse()

	local weld =
		Instance.new(
			"WeldConstraint"
		)

	weld.Name =
		"WAYLESS_MountWeld"

	weld.Part0 =
		targetPart

	weld.Part1 =
		root

	weld.Parent =
		root
end

-- Align an authored grip to a world-space target frame, then weld the
-- assembly root to a carrier part.
local function alignRootAttachmentToWorldCFrame(
	root: BasePart,
	rootAttachment: Attachment,
	carrierPart: BasePart,
	targetWorldCFrame: CFrame
)

	destroyMountWelds(
		root
	)

	root.CFrame =
		targetWorldCFrame
		* rootAttachment.CFrame:
		Inverse()

	local weld =
		Instance.new(
			"WeldConstraint"
		)

	weld.Name =
		"WAYLESS_MountWeld"

	weld.Part0 =
		carrierPart

	weld.Part1 =
		root

	weld.Parent =
		root
end

local function createOrUpdateCharacterAttachment(
	part: BasePart,
	name: string,
	cframe: CFrame
): Attachment

	local existing =
		part:
		FindFirstChild(
			name
		)

	local attachment: Attachment

	if existing
		and existing:IsA(
			"Attachment"
		) then

		attachment =
			existing
	else
		if existing then
			existing:
				Destroy()
		end

		attachment =
			Instance.new(
				"Attachment"
			)

		attachment.Name =
			name

		attachment.Parent =
			part
	end

	attachment.CFrame =
		cframe

	return attachment
end

local function resolveRigPart(
	character: Model,
	r6Name: string,
	r15Name: string
): BasePart?

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local isR15 =
		humanoid
		and humanoid.RigType ==
		Enum.HumanoidRigType.R15

	local preferredName =
		if isR15
		then r15Name
		else r6Name

	local preferred =
		character:
		FindFirstChild(
			preferredName
		)

	if preferred
		and preferred:IsA(
			"BasePart"
		) then

		return preferred
	end

	local fallbackName =
		if isR15
		then r6Name
		else r15Name

	local fallback =
		character:
		FindFirstChild(
			fallbackName
		)

	if fallback
		and fallback:IsA(
			"BasePart"
		) then

		return fallback
	end

	return nil
end

local function getWeaponTemplate(
	assetName: string
): Instance?

	local equipmentAssets =
		ReplicatedStorage:
		FindFirstChild(
			"EquipmentAssets"
		)

	if not equipmentAssets then
		return nil
	end

	local weapons =
		equipmentAssets:
		FindFirstChild(
			"Weapons"
		)

	if not weapons then
		return nil
	end

	return weapons:
		FindFirstChild(
			assetName
		)
end

local function getState(
	character: Model
): string

	local state =
		character:GetAttribute(
			"WeaponState"
		)

	if typeof(state) ~= "string"
		or not VALID_STATES[
		state
		] then

		return "Holstered"
	end

	return state
end

local function mountSheath(
	character: Model,
	visual: Model,
	definition: any
): boolean

	local visualConfig =
		definition.Visual

	local sheath =
		visual:
		FindFirstChild(
			"SheathAssembly"
		)

	if not sheath then
		return false
	end

	local holsterAttachment =
		findAttachmentDeep(
			sheath,
			visualConfig.HolsterAttachmentName
		)

	if not holsterAttachment then

		warn(
			"[EquipmentVisualService] "
				.. definition.Id
				.. " missing "
				.. visualConfig.HolsterAttachmentName
				.. " inside Sheath"
		)

		return false
	end

	local sheathRoot =
		holsterAttachment.Parent

	if not sheathRoot
		or not sheathRoot:IsA(
			"BasePart"
		) then

		return false
	end

	local torso =
		resolveRigPart(
			character,
			visualConfig.R6HolsterPart,
			visualConfig.R15HolsterPart
		)

	if not torso then

		warn(
			"[EquipmentVisualService] no torso mount part for "
				.. character.Name
		)

		return false
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local isR15 =
		humanoid
		and humanoid.RigType ==
		Enum.HumanoidRigType.R15

	local mountCFrame =
		if isR15
		then visualConfig.R15HolsterAttachmentCFrame
		else visualConfig.R6HolsterAttachmentCFrame

	local characterAttachment =
		createOrUpdateCharacterAttachment(
			torso,
			visualConfig.CharacterHolsterAttachmentName,
			mountCFrame
		)

	alignRootAttachmentToTarget(
		sheathRoot,
		holsterAttachment,
		torso,
		characterAttachment
	)

	setAssemblyVisible(
		sheath,
		true
	)

	return true
end

local function mountBladeDrawn(
	character: Model,
	visual: Model,
	definition: any
): boolean

	local visualConfig =
		definition.Visual

	local blade =
		visual:
		FindFirstChild(
			"BladeAssembly"
		)

	if not blade then
		return false
	end

	local gripAttachment =
		findAttachmentDeep(
			blade,
			visualConfig.GripAttachmentName
		)

	if not gripAttachment then

		warn(
			"[EquipmentVisualService] "
				.. definition.Id
				.. " missing "
				.. visualConfig.GripAttachmentName
				.. " inside Blade"
		)

		return false
	end

	local bladeRoot =
		gripAttachment.Parent

	if not bladeRoot
		or not bladeRoot:IsA(
			"BasePart"
		) then

		return false
	end

	local hand =
		resolveRigPart(
			character,
			visualConfig.R6HandPart,
			visualConfig.R15HandPart
		)

	if not hand then

		warn(
			"[EquipmentVisualService] no hand mount part for "
				.. character.Name
		)

		return false
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local isR15 =
		humanoid
		and humanoid.RigType ==
		Enum.HumanoidRigType.R15

	local mountCFrame =
		if isR15
		then visualConfig.R15HandAttachmentCFrame
		else visualConfig.R6HandAttachmentCFrame

	local characterAttachment =
		createOrUpdateCharacterAttachment(
			hand,
			visualConfig.CharacterHandAttachmentName,
			mountCFrame
		)

	setAssemblyVisible(
		blade,
		true
	)

	alignRootAttachmentToTarget(
		bladeRoot,
		gripAttachment,
		hand,
		characterAttachment
	)

	return true
end

local function mountBladeHolstered(
	visual: Model,
	definition: any
): boolean

	local visualConfig =
		definition.Visual

	local blade =
		visual:
		FindFirstChild(
			"BladeAssembly"
		)

	local sheath =
		visual:
		FindFirstChild(
			"SheathAssembly"
		)

	if not blade
		or not sheath then

		return false
	end

	local gripAttachment =
		findAttachmentDeep(
			blade,
			visualConfig.GripAttachmentName
		)

	if not gripAttachment then
		return false
	end

	local bladeRoot =
		gripAttachment.Parent

	if not bladeRoot
		or not bladeRoot:IsA(
			"BasePart"
		) then

		return false
	end

	local sheathedGrip =
		findAttachmentDeep(
			sheath,
			visualConfig.SheathedGripAttachmentName
		)

	if sheathedGrip then

		local sheathRoot =
			sheathedGrip.Parent

		if sheathRoot
			and sheathRoot:IsA(
				"BasePart"
			) then

			setAssemblyVisible(
				blade,
				true
			)

			-- Asset-authored calibration:
			-- SheathedGripAttachment controls BOTH insertion position and
			-- rotation. GripAttachment on the blade is aligned directly to it.
			--
			-- This means no weapon-specific CFrame guessing is required in
			-- service code. If the katana is crooked in the sheath, rotate or
			-- move SheathedGripAttachment in Studio.
			alignRootAttachmentToTarget(
				bladeRoot,
				gripAttachment,
				sheathRoot,
				sheathedGrip
			)

			return true
		end
	end

	-- Safe baseline when the asset has no authored sheathed blade mount.
	-- Keep the same Blade instance alive, but hidden and welded to the
	-- sheath root so it never falls through the map.
	local holsterAttachment =
		findAttachmentDeep(
			sheath,
			visualConfig.HolsterAttachmentName
		)

	if not holsterAttachment then
		return false
	end

	local sheathRoot =
		holsterAttachment.Parent

	if not sheathRoot
		or not sheathRoot:IsA(
			"BasePart"
		) then

		return false
	end

	setAssemblyVisible(
		blade,
		false
	)

	destroyMountWelds(
		bladeRoot
	)

	bladeRoot.CFrame =
		sheathRoot.CFrame

	local weld =
		Instance.new(
			"WeldConstraint"
		)

	weld.Name =
		"WAYLESS_MountWeld"

	weld.Part0 =
		sheathRoot

	weld.Part1 =
		bladeRoot

	weld.Parent =
		bladeRoot

	return true
end

local function buildWeaponVisual(
	character: Model,
	weaponId: string
): Model?

	local definition =
		WeaponCatalog.Get(
			weaponId
		)

	if not definition then

		warn(
			"[EquipmentVisualService] unknown weapon id: "
				.. weaponId
		)

		return nil
	end

	local visualConfig =
		definition.Visual

	local template =
		getWeaponTemplate(
			visualConfig.AssetName
		)

	if not template then

		warn(
			"[EquipmentVisualService] missing asset: ReplicatedStorage.EquipmentAssets.Weapons."
				.. visualConfig.AssetName
		)

		return nil
	end

	local sourceBlade =
		template:
		FindFirstChild(
			visualConfig.BladeContainerName
		)

	local sourceSheath =
		template:
		FindFirstChild(
			visualConfig.SheathContainerName
		)

	if not sourceBlade then

		warn(
			"[EquipmentVisualService] "
				.. visualConfig.AssetName
				.. " missing top-level Blade"
		)

		return nil
	end

	if not sourceSheath then

		warn(
			"[EquipmentVisualService] "
				.. visualConfig.AssetName
				.. " missing top-level Sheath"
		)

		return nil
	end

	local visual =
		Instance.new(
			"Model"
		)

	visual.Name =
		WEAPON_VISUAL_NAME

	visual:SetAttribute(
		"WeaponId",
		weaponId
	)

	local blade =
		sourceBlade:
		Clone()

	blade.Name =
		"BladeAssembly"

	blade.Parent =
		visual

	local sheath =
		sourceSheath:
		Clone()

	sheath.Name =
		"SheathAssembly"

	sheath.Parent =
		visual

	local gripAttachment =
		findAttachmentDeep(
			blade,
			visualConfig.GripAttachmentName
		)

	local holsterAttachment =
		findAttachmentDeep(
			sheath,
			visualConfig.HolsterAttachmentName
		)

	if not gripAttachment
		or not gripAttachment.Parent
		or not gripAttachment.Parent:IsA(
			"BasePart"
		) then

		warn(
			"[EquipmentVisualService] invalid GripAttachment for "
				.. weaponId
		)

		visual:
			Destroy()

		return nil
	end

	if not holsterAttachment
		or not holsterAttachment.Parent
		or not holsterAttachment.Parent:IsA(
			"BasePart"
		) then

		warn(
			"[EquipmentVisualService] invalid HolsterAttachment for "
				.. weaponId
		)

		visual:
			Destroy()

		return nil
	end

	prepareAssembly(
		blade,
		gripAttachment.Parent
	)

	prepareAssembly(
		sheath,
		holsterAttachment.Parent
	)

	visual.Parent =
		getVisualFolder(
			character
		)

	return visual
end

function EquipmentVisualService.RefreshWeapon(
	character: Model
)

	destroyWeaponVisual(
		character
	)

	local weaponId =
		character:GetAttribute(
			"EquippedWeaponId"
		)

	if typeof(weaponId) ~= "string"
		or weaponId == "" then

		character:SetAttribute(
			"WeaponState",
			"None"
		)

		return
	end

	local visual =
		buildWeaponVisual(
			character,
			weaponId
		)

	if not visual then
		return
	end

	local definition =
		WeaponCatalog.Get(
			weaponId
		)

	if not definition then
		return
	end

	mountSheath(
		character,
		visual,
		definition
	)

	local state =
		getState(
			character
		)

	if state == "Drawn" then

		mountBladeDrawn(
			character,
			visual,
			definition
		)
	else
		character:SetAttribute(
			"WeaponState",
			"Holstered"
		)

		mountBladeHolstered(
			visual,
			definition
		)
	end
end

function EquipmentVisualService.SetWeaponState(
	character: Model,
	state: string
): (boolean, string)

	if state ~= "Holstered"
		and state ~= "Drawn" then

		return false,
			"invalid weapon state"
	end

	local weaponId =
		character:GetAttribute(
			"EquippedWeaponId"
		)

	if typeof(weaponId) ~= "string"
		or weaponId == "" then

		character:SetAttribute(
			"WeaponState",
			"None"
		)

		return false,
			"no weapon equipped"
	end

	local definition =
		WeaponCatalog.Get(
			weaponId
		)

	if not definition then
		return false,
			"unknown weapon"
	end

	local visual =
		getCurrentWeaponVisual(
			character
		)

	if not visual
		or visual:GetAttribute(
			"WeaponId"
		) ~= weaponId then

		EquipmentVisualService.RefreshWeapon(
			character
		)

		visual =
			getCurrentWeaponVisual(
				character
			)

		if not visual then
			return false,
				"weapon visual unavailable"
		end
	end

	mountSheath(
		character,
		visual,
		definition
	)

	local mounted = false

	if state == "Drawn" then

		mounted =
			mountBladeDrawn(
				character,
				visual,
				definition
			)
	else
		mounted =
			mountBladeHolstered(
				visual,
				definition
			)
	end

	if not mounted then
		return false,
			"mount failed"
	end

	character:SetAttribute(
		"WeaponState",
		state
	)

	print(
		"[EquipmentVisualService v4]",
		character.Name,
		definition.Id,
		"->",
		state
	)

	return true,
		"OK"
end

print(
	"[EquipmentVisualService] READY v4"
		.. " | R6+R15=ON"
		.. " | SameBladeInstance=ON"
		.. " | SheathPersistent=ON"
)

return EquipmentVisualService
