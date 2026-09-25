--!strict
-- NinjaBagLoadoutServer v1 - Server Authoritative Slot Reassignment
-- ServerScriptService > NinjaBagLoadoutServer [Script]
--
-- Temporary QA loadout editor backend.
--
-- Client requests:
-- EquipRequest(slotIndex, projectileType)
--
-- projectileType:
-- string -> equip projectile
-- ""     -> clear slot
--
-- The server validates the slot and projectile, then calls NinjaBagService.
-- ProjectileServer remains the authority when the equipped slot is actually
-- used in combat.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)


local ProjectileConfigs =
	require(
		ReplicatedStorage:
		WaitForChild(
			"ProjectileConfigs"
		)
	)


local NinjaBagService =
	require(
		script.Parent:
		WaitForChild(
			"NinjaBagService"
		)
	)


local REMOTE_FOLDER_NAME =
	"NinjaBagRemotes"

local EQUIP_REQUEST_NAME =
	"EquipRequest"

local EQUIP_RESULT_NAME =
	"EquipResult"


local SLOT_COUNT =
	4

local REQUEST_DEBOUNCE =
	0.10


local lastRequestAt: {[Player]: number} =
	{}


local remotes =
	ReplicatedStorage:
	FindFirstChild(
		REMOTE_FOLDER_NAME
	)

if not remotes then

	remotes =
		Instance.new(
			"Folder"
		)

	remotes.Name =
		REMOTE_FOLDER_NAME

	remotes.Parent =
		ReplicatedStorage
end


local equipRequestInstance =
	remotes:
	FindFirstChild(
		EQUIP_REQUEST_NAME
	)

if not equipRequestInstance then

	equipRequestInstance =
		Instance.new(
			"RemoteEvent"
		)

	equipRequestInstance.Name =
		EQUIP_REQUEST_NAME

	equipRequestInstance.Parent =
		remotes
end


local equipResultInstance =
	remotes:
	FindFirstChild(
		EQUIP_RESULT_NAME
	)

if not equipResultInstance then

	equipResultInstance =
		Instance.new(
			"RemoteEvent"
		)

	equipResultInstance.Name =
		EQUIP_RESULT_NAME

	equipResultInstance.Parent =
		remotes
end


local equipRequest =
	equipRequestInstance :: RemoteEvent

local equipResult =
	equipResultInstance :: RemoteEvent


local function sendResult(
	player: Player,
	success: boolean,
	slotIndex: number?,
	projectileType: string?,
	reason: string
)

	equipResult:
		FireClient(
			player,
			success,
			slotIndex,
			projectileType,
			reason
		)
end


local function isValidSlot(
	slotIndex: any
): boolean

	return typeof(slotIndex) == "number"
		and slotIndex % 1 == 0
		and slotIndex >= 1
		and slotIndex <= SLOT_COUNT
end


local function isProjectileEquippable(
	player: Player,
	projectileType: string
): (boolean, string)

	local config =
		ProjectileConfigs[
	projectileType
	]


	if typeof(config) ~= "table" then

		return false,
			"invalid projectile"
	end


	if typeof(
		config.NinjaBag
		) ~= "table" then

		return false,
			"not a Ninja Bag throwable"
	end


	-- Future progression / ownership contract.
	--
	-- Missing attribute = available during current QA.
	-- Explicit false = locked.
	--
	-- A future inventory/unlock system can publish:
	-- NinjaBagUnlocked_SmokeBomb = true/false
	local unlocked =
		player:GetAttribute(
			"NinjaBagUnlocked_"
			.. projectileType
		)


	if unlocked == false then

		return false,
			"projectile locked"
	end


	return true,
		"OK"
end


local function getCharacterBlockReason(
	player: Player
): string?

	local character =
		player.Character


	if not character then

		return "no character"
	end


	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)


	if not humanoid
		or humanoid.Health <= 0 then

		return "character unavailable"
	end


	-- CombatTag is server-owned and prevents changing your prepared loadout
	-- during an active PvP engagement, even if the client toggles Combat Mode.
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

		return "character action locked"
	end


	return nil
end


equipRequest.OnServerEvent:
	Connect(
		function(
			player: Player,
			slotValue: any,
			projectileValue: any
		)

			local now =
			time()


			local previous =
			lastRequestAt[
			player
			]
			or -math.huge


			if now - previous <
				REQUEST_DEBOUNCE then

				return
			end


			lastRequestAt[
			player
			] =
			now


			if not isValidSlot(
				slotValue
				) then

				sendResult(
					player,
					false,
					nil,
					nil,
					"invalid slot"
				)


				return
			end


			local slotIndex =
			math.floor(
				slotValue
			)


			local blockReason =
			getCharacterBlockReason(
				player
			)


			if blockReason then

				sendResult(
					player,
					false,
					slotIndex,
					nil,
					blockReason
				)


				return
			end


			local projectileType: string? =
			nil


			if projectileValue ~= nil
				and projectileValue ~= "" then

				if typeof(
					projectileValue
					) ~= "string" then

					sendResult(
						player,
						false,
						slotIndex,
						nil,
						"invalid projectile"
					)


					return
				end


				local equippable,
				reason =
				isProjectileEquippable(
					player,
					projectileValue
				)


				if not equippable then

					sendResult(
						player,
						false,
						slotIndex,
						projectileValue,
						reason
					)


					return
				end


				projectileType =
				projectileValue
			end


			-- Duplicates are intentionally legal at the architecture level.
			-- Both slots consume the same projectile inventory amount.
			--
			-- The final loadout UX may choose to prevent duplicates later.
			local success,
			reason =
			NinjaBagService.SetSlot(
				player,
				slotIndex,
				projectileType
			)


			if not success then

				sendResult(
					player,
					false,
					slotIndex,
					projectileType,
					reason
				)


				return
			end


			sendResult(
				player,
				true,
				slotIndex,
				projectileType,
				"OK"
			)


			print(
				"[NinjaBagLoadoutServer] EQUIP",
				player.Name,
				"Slot",
				slotIndex,
				"->",
				projectileType
				or "EMPTY"
			)
		end
	)


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			lastRequestAt[
			player
			] =
			nil
		end
	)


print(
	"[NinjaBagLoadoutServer] READY v1"
		.. " | Slots=4"
		.. " | CombatTaggedLock=ON"
		.. " | DuplicateSlots=Allowed"
)
