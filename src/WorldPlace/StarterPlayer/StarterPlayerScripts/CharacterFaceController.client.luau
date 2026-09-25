--!strict
-- StarterPlayer > StarterPlayerScripts > CharacterFaceController
--
-- WAYLESS Character Face Controller v2.1
-- Canonical R6 head + direct modular face decals.
--
-- IMPORTANT:
-- Character Creation already proved that direct Decals render the modular
-- Eyes/Brows/Mouth assets correctly on a clean R6 head.
--
-- World characters can arrive with an avatar/custom head SpecialMesh carrying
-- rbxasset://textures/face.png or another MeshId/TextureId. This controller
-- first normalizes that SpecialMesh back to the classic R6 Head configuration,
-- then uses the exact same direct-Decal strategy as Character Creation.
--
-- Visual-only client system. Server remains authoritative for saved IDs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared =
	ReplicatedStorage:
	WaitForChild("Shared")

local AppearanceCatalog =
	require(
		shared:
		WaitForChild(
			"AppearanceCatalog"
		)
	)

local FACE_ATTRIBUTE_NAMES = {
	"CharacterAppearanceMouthStyleId",
	"CharacterAppearanceBrowStyleId",
	"CharacterAppearanceNoseStyleId",
	"CharacterBaseEyeStyleId",
	"CharacterEyeStyleId",
	"CharacterEyeVariantId",
}

local WAYLESS_FACE_NAMES = {
	WAYLESS_Eyes = true,
	WAYLESS_Brows = true,
	WAYLESS_Nose = true,
	WAYLESS_Mouth = true,
}

local playerConnections: {[Player]: {RBXScriptConnection}} = {}
local characterConnections: {[Player]: {RBXScriptConnection}} = {}
local renderQueued: {[Player]: boolean} = {}
local rendering: {[Player]: boolean} = {}

local function disconnectAll(
	connections: {RBXScriptConnection}?
)
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
end

local function valueOrFallback(
	value: any,
	fallback: any
): string?
	if typeof(value) == "string"
		and value ~= "" then

		return value
	end

	if typeof(fallback) == "string"
		and fallback ~= "" then

		return fallback
	end

	return nil
end

local function getSelection(
	player: Player
): (
	string?,
	string?,
	string?,
	string?,
	string
	)
	local defaults =
		typeof(AppearanceCatalog.Defaults) == "table"
		and AppearanceCatalog.Defaults
		or {}

	local mouthStyleId =
		valueOrFallback(
			player:GetAttribute(
				"CharacterAppearanceMouthStyleId"
			),
			defaults.MouthStyleId
		)

	local browStyleId =
		valueOrFallback(
			player:GetAttribute(
				"CharacterAppearanceBrowStyleId"
			),
			defaults.BrowStyleId
		)

	local noseStyleId =
		valueOrFallback(
			player:GetAttribute(
				"CharacterAppearanceNoseStyleId"
			),
			defaults.NoseStyleId
		)

	local eyeStyleId =
		valueOrFallback(
			player:GetAttribute(
				"CharacterBaseEyeStyleId"
			)
			or player:GetAttribute(
				"CharacterEyeStyleId"
			),
			defaults.EyeStyleId
		)

	local eyeVariantId =
		valueOrFallback(
			player:GetAttribute(
				"CharacterEyeVariantId"
			),
			AppearanceCatalog.DefaultEyeVariantId
			or "Base"
		)
		or "Base"

	return mouthStyleId,
		browStyleId,
		noseStyleId,
		eyeStyleId,
		eyeVariantId
end

local function getOrCreateClassicHeadMesh(
	head: BasePart
): SpecialMesh?
	if not head:IsA("Part") then
		warn(
			"[CharacterFaceController] R6 HEAD IS NOT A PART",
			head.ClassName
		)

		return nil
	end

	local mesh =
		head:
		FindFirstChildOfClass(
			"SpecialMesh"
		)

	if not mesh then
		mesh =
			Instance.new("SpecialMesh")

		mesh.Name = "Mesh"
		mesh.Parent = head
	end

	-- Canonical classic R6 head.
	--
	-- We intentionally do NOT put WAYLESS facial art in TextureId.
	-- The face is rendered by transparent Decals, exactly like the proven
	-- Character Creation preview.
	mesh.MeshId = ""
	mesh.TextureId = ""
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Offset = Vector3.zero
	mesh.VertexColor = Vector3.one

	return mesh
end

local function clearForeignFaceVisuals(
	head: BasePart
)
	for _, child in ipairs(
		head:GetChildren()
		) do
		if child:IsA("Decal") then
			if not WAYLESS_FACE_NAMES[child.Name] then
				if child.Face == Enum.NormalId.Front
					or child.Name == "face"
					or child.Name == "Face" then

					child:Destroy()
				end
			end

		elseif child:IsA("Texture") then
			if child.Face == Enum.NormalId.Front then
				child:Destroy()
			end

		elseif child:IsA("SurfaceGui")
			and child.Name == "WAYLESSFaceGui" then

			child:Destroy()
		end
	end
end

local function upsertFaceDecal(
	head: BasePart,
	name: string,
	image: string?,
	zIndex: number
): Decal?
	if not image
		or image == "" then

		local existing =
			head:FindFirstChild(name)

		if existing then
			existing:Destroy()
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
		decal.Parent = head
	end

	decal.Face = Enum.NormalId.Front
	decal.Texture = image
	decal.Transparency = 0
	decal.Color3 = Color3.new(1, 1, 1)

	pcall(function()
		decal.ZIndex = zIndex
	end)

	return decal
end

local function renderFace(
	player: Player
)
	if rendering[player] then
		return
	end

	local character =
		player.Character

	if not character then
		return
	end

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

	local head =
		character:
		FindFirstChild("Head")

	if not head
		or not head:IsA("BasePart") then

		return
	end

	local mouthStyleId,
		browStyleId,
		noseStyleId,
		eyeStyleId,
		eyeVariantId =
		getSelection(
			player
		)

	if not mouthStyleId
		or not browStyleId
		or not noseStyleId
		or not eyeStyleId then

		return
	end

	local mouth =
		AppearanceCatalog.
		GetMouthStyle(
			mouthStyleId
		)

	local brows =
		AppearanceCatalog.
		GetBrowStyle(
			browStyleId
		)

	local nose =
		AppearanceCatalog.
		GetNoseStyle(
			noseStyleId
		)

	local eyes =
		AppearanceCatalog.
		GetEyeStyle(
			eyeStyleId
		)

	if not mouth
		or not brows
		or not nose
		or not eyes then

		warn(
			"[CharacterFaceController] FACE CATALOG ENTRY MISSING",
			player.Name,
			mouthStyleId,
			browStyleId,
			eyeStyleId
		)

		return
	end

	local eyeImage =
		AppearanceCatalog.
		GetEyeImage(
			eyeStyleId,
			eyeVariantId
		)

	local browImage =
		typeof(brows.Image) == "string"
		and brows.Image
		or nil

	local noseImage =
		typeof(nose.Image) == "string"
		and nose.Image
		or nil

	local mouthImage =
		typeof(mouth.Image) == "string"
		and mouth.Image
		or nil

	if not eyeImage
		or not browImage
		or not noseImage
		or not mouthImage then

		warn(
			"[CharacterFaceController] FACE IMAGE MISSING",
			player.Name
		)

		return
	end

	rendering[player] = true

	local ok, err =
		pcall(function()
			local mesh =
			getOrCreateClassicHeadMesh(
				head
			)

			if not mesh then
				error(
					"Classic R6 head mesh unavailable"
				)
			end

			clearForeignFaceVisuals(
				head
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
				browImage,
				20
			)

			upsertFaceDecal(
				head,
				"WAYLESS_Nose",
				noseImage,
				25
			)

			upsertFaceDecal(
				head,
				"WAYLESS_Mouth",
				mouthImage,
				30
			)

			local eyesDecal =
			head:
			FindFirstChild(
				"WAYLESS_Eyes"
			)

			local browsDecal =
			head:
			FindFirstChild(
				"WAYLESS_Brows"
			)

			local noseDecal =
			head:
			FindFirstChild(
				"WAYLESS_Nose"
			)

			local mouthDecal =
			head:
			FindFirstChild(
				"WAYLESS_Mouth"
			)

			print(
				"[CharacterFaceController] FACE RENDERED v2",
				player.Name,
				"MeshType="
				.. mesh.MeshType.Name,
				"MeshId="
				.. tostring(
					mesh.MeshId
				),
				"TextureId="
				.. tostring(
					mesh.TextureId
				),
				"Eyes="
				.. eyeStyleId,
				"Variant="
				.. eyeVariantId,
				"Brows="
				.. browStyleId,
				"Nose="
				.. noseStyleId,
				"Mouth="
				.. mouthStyleId,
				"EyesDecal="
				.. tostring(
					eyesDecal ~= nil
				),
				"BrowsDecal="
				.. tostring(
					browsDecal ~= nil
				),
				"NoseDecal="
				.. tostring(
					noseDecal ~= nil
				),
				"MouthDecal="
				.. tostring(
					mouthDecal ~= nil
				)
			)
		end)

	rendering[player] = nil

	if not ok then
		warn(
			"[CharacterFaceController] FACE RENDER FAILED",
			player.Name,
			err
		)
	end
end

local function queueRender(
	player: Player
)
	if renderQueued[player] then
		return
	end

	renderQueued[player] = true

	task.defer(function()
		renderQueued[player] = nil

		renderFace(
			player
		)
	end)
end

local function bindCharacter(
	player: Player,
	character: Model
)
	disconnectAll(
		characterConnections[player]
	)

	local connections: {RBXScriptConnection} = {}
	characterConnections[player] = connections

	local head =
		character:
		WaitForChild(
			"Head",
			10
		)

	if not head
		or not head:IsA("BasePart") then

		return
	end

	-- First normalization/render.
	queueRender(player)

	-- Reassert after Roblox avatar appearance loading windows.
	task.delay(0.25, queueRender, player)
	task.delay(1, queueRender, player)
	task.delay(3, queueRender, player)

	table.insert(
		connections,
		head.ChildAdded:
			Connect(function(child)
				if rendering[player] then
					return
				end

				if child:IsA("Decal")
					or child:IsA("Texture")
					or child:IsA("SpecialMesh")
					or child:IsA("SurfaceGui") then

					queueRender(
						player
					)
				end
			end)
	)

	local mesh =
		head:
		FindFirstChildOfClass(
			"SpecialMesh"
		)

	if mesh then
		for _, propertyName in ipairs({
			"MeshType",
			"MeshId",
			"TextureId",
			}) do
			table.insert(
				connections,
				mesh:
					GetPropertyChangedSignal(
						propertyName
					):
					Connect(function()
						if not rendering[player] then
							queueRender(
								player
							)
						end
					end)
			)
		end
	end

	table.insert(
		connections,
		character.ChildAdded:
			Connect(function(child)
				if child.Name == "Head" then
					task.defer(
						bindCharacter,
						player,
						character
					)
				end
			end)
	)
end

local function watchPlayer(
	player: Player
)
	if playerConnections[player] then
		return
	end

	local connections: {RBXScriptConnection} = {}
	playerConnections[player] = connections

	table.insert(
		connections,
		player.CharacterAdded:
			Connect(function(character)
				task.defer(
					bindCharacter,
					player,
					character
				)
			end)
	)

	for _, attributeName in ipairs(
		FACE_ATTRIBUTE_NAMES
		) do
		table.insert(
			connections,
			player:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(function()
					queueRender(
						player
					)
				end)
		)
	end

	if player.Character then
		task.defer(
			bindCharacter,
			player,
			player.Character
		)
	end
end

local function unwatchPlayer(
	player: Player
)
	disconnectAll(
		playerConnections[player]
	)

	disconnectAll(
		characterConnections[player]
	)

	playerConnections[player] = nil
	characterConnections[player] = nil
	renderQueued[player] = nil
	rendering[player] = nil
end

Players.PlayerAdded:
	Connect(watchPlayer)

Players.PlayerRemoving:
	Connect(unwatchPlayer)

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.defer(
		watchPlayer,
		player
	)
end

print(
	"[CharacterFaceController] READY v2.1"
		.. " | ClassicR6Head=ON"
		.. " | DirectDecals=ON"
		.. " | CatalogVersion="
		.. tostring(
			AppearanceCatalog.Version
		)
)
