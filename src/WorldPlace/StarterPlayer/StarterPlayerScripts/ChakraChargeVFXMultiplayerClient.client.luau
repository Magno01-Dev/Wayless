--!strict
-- ChakraChargeVFXMultiplayerClient v1.1 - Remote VFX + 3D Charge Sound
-- ElDiabloLocoStudios / Roblox
--
-- LOCATION:
-- StarterPlayer > StarterPlayerScripts > ChakraChargeVFXMultiplayerClient
--
-- PURPOSE:
-- Renders Chakra Charge body VFX + 3D looping charge sound for OTHER PLAYERS.
--
-- The owning player keeps using ChakraChargeController for their own VFX.
-- The server replicates:
--
--   Character.ChakraChargeVisualActive
--
-- Every client watches that attribute on remote characters.
--
-- ASSETS:
-- ReplicatedStorage
-- └── ChakraRemotes
--     └── ChakraChargeVFXAssets
--         ├── Head
--         ├── Torso
--         ├── LeftArm
--         ├── RightArm
--         ├── LeftLeg
--         └── RightLeg


local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)


local localPlayer =
	Players.LocalPlayer


local chakraRemotes =
	ReplicatedStorage:
	WaitForChild(
		"ChakraRemotes"
	)


local vfxAssets =
	chakraRemotes:
	WaitForChild(
		"ChakraChargeVFXAssets"
	) :: Folder


-- ============================================================
-- REMOTE CHARGE SOUND
-- ============================================================

local CHARGE_SOUND_ID =
	"rbxassetid://111262226714062"

local CHARGE_SOUND_VOLUME =
	1

local CHARGE_SOUND_MIN_DISTANCE =
	8

local CHARGE_SOUND_MAX_DISTANCE =
	70


type RemoteCharacterVFX = {
	character: Model,
	objects: {Instance},
	sound: Sound?,
	active: boolean,
	attributeConnection: RBXScriptConnection?,
	deathConnection: RBXScriptConnection?,
}


local activeCharacters:
	{[Model]: RemoteCharacterVFX} =
	{}


local characterAddedConnections:
	{[Player]: RBXScriptConnection} =
	{}


local function findBodyPart(
	character: Model,
	name: string
): BasePart?

	local candidate =
		character:
		FindFirstChild(
			name
		)


	if candidate
		and candidate:IsA(
			"BasePart"
		) then

		return candidate
	end


	return nil
end


local function getTargetBodyPart(
	character: Model,
	vfxName: string
): BasePart?

	if vfxName == "Head" then
		return findBodyPart(
			character,
			"Head"
		)
	end


	if vfxName == "Torso" then

		return findBodyPart(
			character,
			"UpperTorso"
		)
			or findBodyPart(
				character,
				"Torso"
			)
	end


	if vfxName == "LeftArm" then

		return findBodyPart(
			character,
			"LeftUpperArm"
		)
			or findBodyPart(
				character,
				"Left Arm"
			)
	end


	if vfxName == "RightArm" then

		return findBodyPart(
			character,
			"RightUpperArm"
		)
			or findBodyPart(
				character,
				"Right Arm"
			)
	end


	if vfxName == "LeftLeg" then

		return findBodyPart(
			character,
			"LeftUpperLeg"
		)
			or findBodyPart(
				character,
				"Left Leg"
			)
	end


	if vfxName == "RightLeg" then

		return findBodyPart(
			character,
			"RightUpperLeg"
		)
			or findBodyPart(
				character,
				"Right Leg"
			)
	end


	return nil
end


local function setVFXObjectEnabled(
	object: Instance,
	enabled: boolean
)

	if object:IsA(
		"ParticleEmitter"
		) then

		object.Enabled =
			enabled

	elseif object:IsA(
		"Trail"
		) then

		object.Enabled =
			enabled

	elseif object:IsA(
		"Beam"
		) then

		object.Enabled =
			enabled

	elseif object:IsA(
		"PointLight"
		) then

		object.Enabled =
			enabled
	end
end


local function setVFXTreeEnabled(
	root: Instance,
	enabled: boolean
)

	setVFXObjectEnabled(
		root,
		enabled
	)


	for _,
		descendant in ipairs(
			root:GetDescendants()
		) do

		setVFXObjectEnabled(
			descendant,
			enabled
		)
	end
end


local function destroyRemoteSound(
	data: RemoteCharacterVFX
)
	local sound =
		data.sound

	data.sound =
		nil

	if not sound then
		return
	end

	pcall(
		function()
			sound:Stop()
		end
	)

	if sound.Parent then
		sound:Destroy()
	end
end


local function startRemoteSound(
	data: RemoteCharacterVFX
)
	if data.sound then
		return
	end

	local character =
		data.character

	if not character.Parent then
		return
	end

	local root =
		findBodyPart(
			character,
			"HumanoidRootPart"
		)

	if not root then
		return
	end

	local sound =
		Instance.new(
			"Sound"
		)

	sound.Name =
		"ChakraChargeSound"

	sound.SoundId =
		CHARGE_SOUND_ID

	sound.Volume =
		CHARGE_SOUND_VOLUME

	sound.Looped =
		true

	sound.RollOffMode =
		Enum.RollOffMode.Inverse

	sound.RollOffMinDistance =
		CHARGE_SOUND_MIN_DISTANCE

	sound.RollOffMaxDistance =
		CHARGE_SOUND_MAX_DISTANCE

	sound.Parent =
		root

	data.sound =
		sound

	sound:Play()
end


local function destroyObjectsImmediately(
	data: RemoteCharacterVFX
)

	local objects =
		data.objects


	data.objects =
		{}

	data.active =
		false

	destroyRemoteSound(
		data
	)


	for _,
		object in ipairs(
			objects
		) do

		if object.Parent then

			object:
				Destroy()
		end
	end
end


local function stopRemoteVFX(
	data: RemoteCharacterVFX
)

	if not data.active
		and #data.objects == 0
		and data.sound == nil then

		return
	end


	data.active =
		false

	destroyRemoteSound(
		data
	)


	local objects =
		data.objects


	data.objects =
		{}


	for _,
		object in ipairs(
			objects
		) do

		if object.Parent then

			setVFXTreeEnabled(
				object,
				false
			)
		end
	end


	-- Allow existing particles to finish naturally.
	task.delay(
		0.70,
		function()

			for _,
				object in ipairs(
					objects
				) do

				if object.Parent then

					object:
						Destroy()
				end
			end
		end
	)
end


local function startRemoteVFX(
	data: RemoteCharacterVFX
)

	if data.active
		or #data.objects > 0
		or data.sound ~= nil then

		return
	end


	local character =
		data.character


	if not character.Parent then
		return
	end


	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)


	if not humanoid
		or humanoid.Health <= 0 then

		return
	end

	-- Mark the presentation active before creating descendants so repeated
	-- attribute callbacks cannot duplicate either the VFX or the sound.
	data.active =
		true

	-- Charge audio is server-owned by ChakraService.
	-- This client only renders the replicated VFX.

	local createdObjects:
		{Instance} =
		{}


	for _,
		bodyFolder in ipairs(
			vfxAssets:GetChildren()
		) do

		if not bodyFolder:IsA(
			"Folder"
			) then

			continue
		end


		local targetPart =
			getTargetBodyPart(
				character,
				bodyFolder.Name
			)


		if not targetPart then

			warn(
				"[ChakraChargeVFXMultiplayerClient] "
					.. "Missing body part "
					.. bodyFolder.Name
					.. " on "
					.. character.Name
			)

			continue
		end


		for _,
			sourceObject in ipairs(
				bodyFolder:GetChildren()
			) do

			local clone =
				sourceObject:
				Clone()


			clone.Parent =
				targetPart


			setVFXTreeEnabled(
				clone,
				true
			)


			table.insert(
				createdObjects,
				clone
			)
		end
	end


	data.objects =
		createdObjects
end


local function syncCharacterVFX(
	data: RemoteCharacterVFX
)

	local shouldBeActive =
		data.character:GetAttribute(
			"ChakraChargeVisualActive"
		) == true


	if shouldBeActive then

		startRemoteVFX(
			data
		)

	else

		stopRemoteVFX(
			data
		)
	end
end


local function unbindCharacter(
	character: Model
)

	local data =
		activeCharacters[
	character
	]


	if not data then
		return
	end


	if data.attributeConnection then

		data.attributeConnection:
			Disconnect()
	end


	if data.deathConnection then

		data.deathConnection:
			Disconnect()
	end


	destroyObjectsImmediately(
		data
	)


	activeCharacters[
	character
	] =
		nil
end


local function bindRemoteCharacter(
	owner: Player,
	character: Model
)

	if owner ==
		localPlayer then

		return
	end


	unbindCharacter(
		character
	)


	local data: RemoteCharacterVFX = {
		character = character,
		objects = {},
		sound = nil,
		active = false,
		attributeConnection = nil,
		deathConnection = nil,
	}


	activeCharacters[
	character
	] =
		data


	data.attributeConnection =
		character:
		GetAttributeChangedSignal(
			"ChakraChargeVisualActive"
		):
		Connect(
			function()

				if activeCharacters[
					character
					] ~= data then

					return
				end


				syncCharacterVFX(
					data
				)
			end
		)


	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)
		or character:
		WaitForChild(
			"Humanoid",
			5
		)


	if humanoid
		and humanoid:IsA(
			"Humanoid"
		) then

		data.deathConnection =
			humanoid.Died:
			Connect(
				function()

					if activeCharacters[
						character
						] == data then

						stopRemoteVFX(
							data
						)
					end
				end
			)
	end


	syncCharacterVFX(
		data
	)
end


local function bindPlayer(
	player: Player
)

	if player ==
		localPlayer then

		return
	end


	if characterAddedConnections[
		player
		] then

		characterAddedConnections[
		player
		]:
			Disconnect()
	end


	characterAddedConnections[
	player
	] =
		player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				bindRemoteCharacter(
					player,
					character
				)
			end
		)


	if player.Character then

		bindRemoteCharacter(
			player,
			player.Character
		)
	end
end


Players.PlayerAdded:
	Connect(
		bindPlayer
	)


Players.PlayerRemoving:
	Connect(
		function(
			leavingPlayer: Player
		)

			local connection =
			characterAddedConnections[
			leavingPlayer
			]


			if connection then

				connection:
				Disconnect()

				characterAddedConnections[
				leavingPlayer
				] =
				nil
			end


			for character,
				_ in pairs(
					activeCharacters
				) do

				if leavingPlayer.Character ==
					character then

					unbindCharacter(
						character
					)
				end
			end
		end
	)


for _,
	otherPlayer in ipairs(
		Players:GetPlayers()
	) do

	bindPlayer(
		otherPlayer
	)
end


script.Destroying:
	Connect(
		function()

			for _,
				connection in pairs(
					characterAddedConnections
				) do

				connection:
				Disconnect()
			end


			characterAddedConnections =
			{}


			local charactersToRemove =
			{}


			for character,
				_ in pairs(
					activeCharacters
				) do

				table.insert(
					charactersToRemove,
					character
				)
			end


			for _,
				character in ipairs(
					charactersToRemove
				) do

				unbindCharacter(
					character
				)
			end
		end
	)


print(
	"[ChakraChargeVFXMultiplayerClient] READY v1.1"
		.. " | RemotePlayersOnly=ON"
		.. " | RemoteChargeSound=111262226714062"
		.. " | Attribute=ChakraChargeVisualActive"
		.. " | Assets="
		.. vfxAssets:GetFullName()
)
