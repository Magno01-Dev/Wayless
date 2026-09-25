--!strict
-- WeaponStateController v1 - WAYLESS CombatMode -> Weapon Draw Bridge
-- StarterPlayer > StarterPlayerScripts > WeaponStateController [LocalScript]
--
-- This does NOT create a new weapon keybind.
-- It follows the existing local WAYLESS CombatMode state:
--
-- CombatMode ON  -> request Drawn
-- CombatMode OFF -> request Holstered
--
-- The server validates the equipped weapon and replicates the visual.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local player =
	Players.LocalPlayer

local equipmentRemotes =
	ReplicatedStorage:
	WaitForChild(
		"EquipmentRemotes"
	)

local weaponStateRequest =
	equipmentRemotes:
	WaitForChild(
		"WeaponStateRequest"
	) :: RemoteEvent

local connections:
	{RBXScriptConnection} =
	{}

local lastRequestedState =
	""

local function disconnectAll()

	for _,
		connection in ipairs(
			connections
		) do

		connection:
			Disconnect()
	end

	table.clear(
		connections
	)
end

local function hasWeapon(
	character: Model
): boolean

	local weaponId =
		character:GetAttribute(
			"EquippedWeaponId"
		)

	return typeof(weaponId) == "string"
		and weaponId ~= ""
end

local function desiredState(
	character: Model
): string?

	if not hasWeapon(
		character
		) then

		return nil
	end

	if character:GetAttribute(
		"CombatMode"
		) == true
			and character:GetAttribute(
				"CombatSuppressed"
			) ~= true
			and character:GetAttribute(
				"IsDowned"
			) ~= true
			and character:GetAttribute(
				"IsCarried"
			) ~= true then

		return "Drawn"
	end

	return "Holstered"
end

local function sync(
	character: Model,
	force: boolean?
)

	if player.Character
		~= character
		or not character.Parent then

		return
	end

	local state =
		desiredState(
			character
		)

	if not state then

		lastRequestedState =
			""

		return
	end

	if not force
		and lastRequestedState
		== state then

		return
	end

	lastRequestedState =
		state

	weaponStateRequest:
		FireServer(
			state
		)

	print(
		"[WeaponStateController]",
		"CombatMode=",
		character:GetAttribute(
			"CombatMode"
		),
		"requested",
		state
	)
end

local function bindCharacter(
	character: Model
)

	disconnectAll()

	lastRequestedState =
		""

	for _,
		attributeName in ipairs({
			"CombatMode",
			"CombatSuppressed",
			"IsDowned",
			"IsCarried",
			"EquippedWeaponId",
		}) do

		table.insert(
			connections,
			character:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(
					function()
						sync(
							character,
							false
						)
					end
				)
		)
	end

	task.defer(
		function()
			sync(
				character,
				true
			)
		end
	)

	-- EquipmentService can replicate EquippedWeaponId a moment after spawn.
	task.delay(
		0.35,
		function()

			if player.Character
				== character
				and character.Parent then

				sync(
					character,
					true
				)
			end
		end
	)
end

player.CharacterAdded:
	Connect(
		bindCharacter
	)

if player.Character then

	bindCharacter(
		player.Character
	)
end

print(
	"[WeaponStateController] READY v1"
		.. " | ExistingCombatMode=ON"
)
