--!strict
-- WeaponStateServer v2 - Client CombatMode Bridge + Server Validation
-- ServerScriptService > WeaponStateServer [Script]
--
-- IMPORTANT:
-- WAYLESS CombatMode is currently owned by LocalScripts through the
-- character's local CombatMode/CombatSuppressed state. A server Script
-- cannot reliably observe a client-only attribute change.
--
-- v2 therefore uses:
-- StarterPlayerScripts > WeaponStateController
--                  |
--                  v
-- ReplicatedStorage > EquipmentRemotes > WeaponStateRequest
--                  |
--                  v
-- WeaponStateServer -> EquipmentVisualService
--
-- The server remains authoritative over the actual replicated weapon
-- visual and validates that a real weapon is equipped.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local EquipmentVisualService =
	require(
		script.Parent:
		WaitForChild(
			"EquipmentVisualService"
		)
	)

---------------------------------------------------------------------
-- REMOTE
---------------------------------------------------------------------

local equipmentRemotes =
	ReplicatedStorage:
	FindFirstChild(
		"EquipmentRemotes"
	)

if not equipmentRemotes then

	equipmentRemotes =
		Instance.new(
			"Folder"
		)

	equipmentRemotes.Name =
		"EquipmentRemotes"

	equipmentRemotes.Parent =
		ReplicatedStorage
end

local existingRequest =
	equipmentRemotes:
	FindFirstChild(
		"WeaponStateRequest"
	)

local weaponStateRequest: RemoteEvent

if existingRequest
	and existingRequest:IsA(
		"RemoteEvent"
	) then

	weaponStateRequest =
		existingRequest
else

	if existingRequest then
		existingRequest:
			Destroy()
	end

	weaponStateRequest =
		Instance.new(
			"RemoteEvent"
		)

	weaponStateRequest.Name =
		"WeaponStateRequest"

	weaponStateRequest.Parent =
		equipmentRemotes
end

---------------------------------------------------------------------
-- VALIDATION
---------------------------------------------------------------------

local REQUEST_INTERVAL =
	0.06

local lastRequestAt:
	{[Player]: number} =
	{}

local characterConnections:
	{[Player]: {RBXScriptConnection}} =
	{}

local function disconnectPlayer(
	player: Player
)

	local connections =
		characterConnections[
	player
	]

	if connections then

		for _,
			connection in ipairs(
				connections
			) do

			connection:
				Disconnect()
		end
	end

	characterConnections[
	player
	] = nil

	lastRequestAt[
	player
	] = nil
end

local function getEquippedWeaponId(
	character: Model
): string?

	local weaponId =
		character:GetAttribute(
			"EquippedWeaponId"
		)

	if typeof(weaponId) ~= "string"
		or weaponId == "" then

		return nil
	end

	return weaponId
end

local function canDraw(
	character: Model
): boolean

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return false
	end

	-- These checks matter whenever the SERVER owns the restriction.
	-- We intentionally do not require server CombatMode=true because the
	-- existing WAYLESS CombatMode controller is client-side.
	if character:GetAttribute(
		"CombatSuppressed"
		) == true
			or character:GetAttribute(
				"IsDowned"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true then

		return false
	end

	return true
end

local function refreshHolstered(
	character: Model
)

	local weaponId =
		getEquippedWeaponId(
			character
		)

	if not weaponId then

		character:SetAttribute(
			"WeaponState",
			"None"
		)

		EquipmentVisualService.RefreshWeapon(
			character
		)

		return
	end

	character:SetAttribute(
		"WeaponState",
		"Holstered"
	)

	EquipmentVisualService.RefreshWeapon(
		character
	)

	EquipmentVisualService.SetWeaponState(
		character,
		"Holstered"
	)
end

---------------------------------------------------------------------
-- CHARACTER BINDING
---------------------------------------------------------------------

local function bindCharacter(
	player: Player,
	character: Model
)

	local previous =
		characterConnections[
	player
	]

	if previous then

		for _,
			connection in ipairs(
				previous
			) do

			connection:
				Disconnect()
		end
	end

	characterConnections[
	player
	] = {}

	local connections =
		characterConnections[
	player
	]

	if character:GetAttribute(
		"WeaponState"
		) == nil then

		character:SetAttribute(
			"WeaponState",
			"None"
		)
	end

	task.defer(
		function()

			if character.Parent then
				refreshHolstered(
					character
				)
			end
		end
	)

	table.insert(
		connections,
		character:
			GetAttributeChangedSignal(
				"EquippedWeaponId"
			):
			Connect(
				function()

					if character.Parent then
						refreshHolstered(
							character
						)
					end
				end
			)
	)

	-- If the server places the character in a hard restricted state,
	-- force the weapon back into the sheath.
	for _,
		attributeName in ipairs({
			"CombatSuppressed",
			"IsDowned",
			"IsCarried",
		}) do

		table.insert(
			connections,
			character:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(
					function()

						if not character.Parent then
							return
						end

						if not canDraw(
							character
							) then

							EquipmentVisualService.SetWeaponState(
								character,
								"Holstered"
							)
						end
					end
				)
		)
	end
end

local function bindPlayer(
	player: Player
)

	player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				bindCharacter(
					player,
					character
				)
			end
		)

	if player.Character then

		bindCharacter(
			player,
			player.Character
		)
	end
end

---------------------------------------------------------------------
-- CLIENT STATE REQUEST
---------------------------------------------------------------------

weaponStateRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			requestedState: any
		)

			if requestedState ~= "Drawn"
				and requestedState ~= "Holstered" then

				return
			end

			local now =
			time()

			local previous =
			lastRequestAt[
			player
			]
			or 0

			if now - previous
				< REQUEST_INTERVAL then

				return
			end

			lastRequestAt[
			player
			] = now

			local character =
			player.Character

			if not character
				or not character.Parent then

				return
			end

			if not getEquippedWeaponId(
				character
				) then

				return
			end

			if requestedState == "Drawn"
				and not canDraw(
					character
				) then

				requestedState =
				"Holstered"
			end

			local success,
			reason =
			EquipmentVisualService.SetWeaponState(
				character,
				requestedState
			)

			if not success then

				warn(
					"[WeaponStateServer v2]",
					player.Name,
					requestedState,
					reason
				)
			end
		end
	)

---------------------------------------------------------------------
-- PLAYER LIFECYCLE
---------------------------------------------------------------------

Players.PlayerAdded:
	Connect(
		bindPlayer
	)

for _,
	player in ipairs(
		Players:GetPlayers()
	) do

	bindPlayer(
		player
	)
end

Players.PlayerRemoving:
	Connect(
		disconnectPlayer
	)

print(
	"[WeaponStateServer] READY v2"
		.. " | ClientCombatModeBridge=ON"
		.. " | ServerVisualAuthority=ON"
)
