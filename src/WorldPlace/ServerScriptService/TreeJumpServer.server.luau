--!strict
-- TreeJumpServer v3.3 - PvP Stamina + Mission Interaction Aware
-- REPLACE:
-- ServerScriptService > TreeJumpServer
--
-- Stable behavior preserved:
-- - Workspace.Arboles branch validation
-- - 250-stud normal target range
-- - dynamic duration / arc
-- - 3-use normal chain counter
-- - Downed / Carry restrictions
-- - server landing watchdog/correction
--
-- NEW:
-- While CombatTagged == true, approved Tree Jumps have a
-- 4-second server-authoritative cooldown between them.
--
-- We deliberately limit FREQUENCY instead of changing the current
-- 250-stud range so the existing TreeJumpController and its visual
-- target indicator remain synchronized with the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StaminaConfig =
	require(
		ReplicatedStorage:
		WaitForChild("StaminaConfig")
	)

local StaminaService =
	require(
		ServerScriptService:
		WaitForChild("StaminaService")
	)

local TREE_FOLDER =
	workspace:WaitForChild("Arboles")

local requestEvent =
	ReplicatedStorage:WaitForChild("TreeJumpRequest") :: RemoteEvent

local approvedEvent =
	ReplicatedStorage:WaitForChild("TreeJumpApproved") :: RemoteEvent

local replicateEvent =
	ReplicatedStorage:WaitForChild("TreeJumpReplicate") :: RemoteEvent


-- =========================
-- CONFIG
-- =========================

local MIN_DISTANCE = 4
local MAX_DISTANCE = 250
local DISTANCE_OFFSET = 3

local TREE_JUMP_SPEED = 160
local MIN_JUMP_DURATION = 0.20
local MAX_JUMP_DURATION = 1.60

local ARC_HEIGHT_PER_STUD = 0.06
local MIN_ARC_HEIGHT = 3
local MAX_ARC_HEIGHT = 12

local LANDING_TOLERANCE = 3
local CURRENT_BRANCH_RAY_DISTANCE = 6

local MAX_USES = 3
local COUNTER_TIMEOUT = 1.6

local CORRECTION_THRESHOLD = 12
local SERVER_FINISH_BUFFER = 0.40

local COMBAT_TAG_TREE_JUMP_COOLDOWN = 4.0

local DEBUG = false

local BRANCH_NAMES = {
	Branch_EA = true,
	Branch_NE = true,
	Branch_SW = true,
	Branch_WE = true,
}


type PlayerState = {
	uses: number,
	lastUseTime: number,
	busy: boolean,
	lastCombatTagJumpTime: number,
}

local playerState: {[Player]: PlayerState} = {}


local function dbg(message: string)
	if DEBUG then
		print("[TreeJump-Server] " .. message)
	end
end


local function isDownedSystemLocked(
	character: Model
): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsCarrying") == true
end


local function clearTreeJumpState(
	player: Player,
	character: Model?
)
	local state = playerState[player]

	if state then
		state.busy = false
	end

	if character and character.Parent then
		character:SetAttribute(
			"TreeJumpProtected",
			false
		)

		character:SetAttribute(
			"TreeJumpActive",
			false
		)

		character:SetAttribute(
			"IsTreeJumping",
			false
		)
	end
end


-- =========================
-- TREE HELPERS
-- =========================

local function isInsideArboles(
	instance: Instance?
): boolean
	local current = instance

	while current and current ~= workspace do
		if current == TREE_FOLDER then
			return true
		end

		current = current.Parent
	end

	return false
end


local function findTreeModelFor(
	instance: Instance?
): Instance?
	if not instance then
		return nil
	end

	local current = instance

	while current and current ~= workspace do
		if current.Parent == TREE_FOLDER then
			return current
		end

		current = current.Parent
	end

	return nil
end


local function isValidBranch(
	instance: Instance?
): boolean
	return instance ~= nil
		and instance:IsA("BasePart")
		and BRANCH_NAMES[instance.Name] == true
		and isInsideArboles(instance)
end


local function getCurrentStandingBranch(
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart
): BasePart?
	if humanoid.FloorMaterial ==
		Enum.Material.Air then

		return nil
	end

	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character
	}

	local hit =
		workspace:Raycast(
			rootPart.Position,
			Vector3.new(
				0,
				-CURRENT_BRANCH_RAY_DISTANCE,
				0
			),
			params
		)

	if not hit
		or not hit.Instance
		or not hit.Instance:IsA("BasePart") then

		return nil
	end

	local part = hit.Instance

	if not BRANCH_NAMES[part.Name]
		or not isInsideArboles(part) then

		return nil
	end

	return part
end


local function hasClearDashPath(
	rootPart: BasePart,
	targetPosition: Vector3,
	targetBranch: BasePart,
	character: Model
): boolean
	local delta =
		targetPosition
	- rootPart.Position

	if delta.Magnitude < 0.1 then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character
	}

	local hit =
		workspace:Raycast(
			rootPart.Position,
			delta,
			params
		)

	if not hit then
		return true
	end

	if (
		hit.Position
		- targetPosition
		).Magnitude <= LANDING_TOLERANCE then

		return true
	end

	if hit.Instance == targetBranch
		or hit.Instance:IsDescendantOf(
			targetBranch
		) then

		return true
	end

	return false
end


-- =========================
-- COUNTER
-- =========================

local function resetCounter(
	player: Player
)
	local state = playerState[player]

	if not state then
		return
	end

	state.uses = 0

	local character = player.Character

	if character then
		character:SetAttribute(
			"TreeJumpUses",
			0
		)
	end
end


local function scheduleCounterReset(
	player: Player
)
	local state = playerState[player]

	if not state then
		return
	end

	local expectedLastUse =
		state.lastUseTime

	task.delay(
		COUNTER_TIMEOUT,
		function()
			local current =
				playerState[player]

			if not current
				or current.lastUseTime ~=
				expectedLastUse
				or current.busy then

				return
			end

			resetCounter(player)
		end
	)
end


-- =========================
-- CHARACTER / PLAYER SETUP
-- =========================

local function setupCharacter(
	player: Player,
	character: Model
)
	local humanoid =
		character:
		WaitForChild("Humanoid") :: Humanoid

	character:SetAttribute(
		"TreeJumpUses",
		0
	)

	character:SetAttribute(
		"TreeJumpActive",
		false
	)

	character:SetAttribute(
		"TreeJumpProtected",
		false
	)

	character:SetAttribute(
		"IsTreeJumping",
		false
	)

	character:SetAttribute(
		"CoreCooldown_TreeJump_Label",
		"Tree Jump"
	)

	character:SetAttribute(
		"CoreCooldown_TreeJump_StartsAt",
		0
	)

	character:SetAttribute(
		"CoreCooldown_TreeJump_EndsAt",
		0
	)

	humanoid.StateChanged:Connect(
		function(_, newState)
			if newState ==
				Enum.HumanoidStateType.Landed then

				resetCounter(player)
			end
		end
	)

	local function handleDownedState()
		if isDownedSystemLocked(
			character
			) then

			clearTreeJumpState(
				player,
				character
			)

			resetCounter(player)

			dbg(
				"Tree Jump cancelado por Downed/Carry"
			)
		end
	end

	character:
		GetAttributeChangedSignal(
			"DownedActionLocked"
		):
		Connect(
			handleDownedState
		)

	character:
		GetAttributeChangedSignal(
			"IsCarrying"
		):
		Connect(
			handleDownedState
		)

	character:
		GetAttributeChangedSignal(
			"MissionInteractionActive"
		):
		Connect(
			function()

				if character:GetAttribute(
					"MissionInteractionActive"
					) == true then

					clearTreeJumpState(
						player,
						character
					)

					resetCounter(
						player
					)

					dbg(
						"Tree Jump cancelado por MissionInteractionActive"
					)
				end
			end
		)
end


local function initPlayer(
	player: Player
)
	if not playerState[player] then
		playerState[player] = {
			uses = 0,
			lastUseTime = 0,
			busy = false,
			lastCombatTagJumpTime =
				-math.huge,
		}
	end

	if player.Character then
		setupCharacter(
			player,
			player.Character
		)
	end

	player.CharacterAdded:Connect(
		function(character: Model)
			local state =
				playerState[player]

			if state then
				state.uses = 0
				state.lastUseTime = 0
				state.busy = false
				state.lastCombatTagJumpTime =
					-math.huge
			end

			setupCharacter(
				player,
				character
			)
		end
	)
end


for _, player in ipairs(
	Players:GetPlayers()
	) do
	initPlayer(player)
end

Players.PlayerAdded:Connect(
	initPlayer
)

Players.PlayerRemoving:Connect(
	function(player: Player)
		playerState[player] = nil
	end
)



-- =========================
-- WATER / SWIMMING GUARD
-- =========================
-- Server-authoritative Tree Jump water validation.
--
-- Rules:
-- - Humanoid Swimming -> blocked
-- - WaterJumping -> blocked
-- - stable WaterWalking -> allowed
-- - otherwise, Terrain water occupancy around HRP -> blocked
--
-- The voxel read only occurs when a Tree Jump request reaches the server.

local TREE_JUMP_WATER_VOXEL_RESOLUTION =
	4

local TREE_JUMP_WATER_OCCUPANCY_THRESHOLD =
	0.10

local TREE_JUMP_WATER_SAMPLE_HALF_SIZE =
	Vector3.new(
		1.5,
		1.8,
		1.5
	)


local function isRootInsideTerrainWater(
	rootPart: BasePart
): boolean

	local terrain =
		workspace.Terrain


	local region =
		Region3.new(
			rootPart.Position
			- TREE_JUMP_WATER_SAMPLE_HALF_SIZE,
			rootPart.Position
			+ TREE_JUMP_WATER_SAMPLE_HALF_SIZE
		):
		ExpandToGrid(
			TREE_JUMP_WATER_VOXEL_RESOLUTION
		)


	local materials,
		occupancies =
		terrain:
		ReadVoxels(
			region,
			TREE_JUMP_WATER_VOXEL_RESOLUTION
		)


	for x = 1,
		#materials do

		for y = 1,
			#materials[x] do

			for z = 1,
				#materials[x][y] do

				if materials[x][y][z] ==
					Enum.Material.Water
					and occupancies[x][y][z] >=
					TREE_JUMP_WATER_OCCUPANCY_THRESHOLD then

					return true
				end
			end
		end
	end


	return false
end


local function isTreeJumpWaterBlocked(
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart
): boolean

	-- Never let an explicit Swimming state through.
	if humanoid:GetState() ==
		Enum.HumanoidStateType.Swimming then

		return true
	end


	if character:GetAttribute(
		"WaterJumping"
		) == true then

		return true
	end


	-- Chakra Feet WaterWalking is the intentional exception.
	if character:GetAttribute(
		"WaterWalking"
		) == true then

		return false
	end


	if humanoid.FloorMaterial ==
		Enum.Material.Water then

		return true
	end


	return isRootInsideTerrainWater(
		rootPart
	)
end


-- =========================
-- REQUEST
-- =========================

requestEvent.OnServerEvent:Connect(
	function(
		player: Player,
		branchRef: any
	)
		local state =
			playerState[player]

		if not state or state.busy then
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

		local rootPart =
			character:
			FindFirstChild(
				"HumanoidRootPart"
			) :: BasePart?

		if not humanoid
			or not rootPart
			or humanoid.Health <= 0
			or humanoid:GetState() ==
			Enum.HumanoidStateType.Dead then

			return
		end

		if isTreeJumpWaterBlocked(
			character,
			humanoid,
			rootPart
			) then

			dbg(
				"BLOCKED: Swimming/SubmergedWater"
			)

			return
		end


		if isDownedSystemLocked(
			character
			) then
			return
		end

		if character:GetAttribute(
			"ChakraCharging"
			) == true then

			dbg(
				"rechazado: ChakraCharging"
			)

			return
		end

		-- Tree Jump input is currently LeftAlt; MissionInteraction remains a server-authoritative lock.
		-- MissionClient consumes the input while near valid trash; this is the
		-- server-authoritative second layer.
		if character:GetAttribute(
			"MissionInteractionActive"
			) == true then

			dbg(
				"rechazado: MissionInteractionActive"
			)

			return
		end

		if character:GetAttribute(
			"IsDashing"
			) == true
				or character:GetAttribute(
					"TreeJumpActive"
				) == true then

			return
		end

		-- ====================================
		-- COMBAT TAG ESCAPE LIMIT
		-- ====================================

		if player:GetAttribute(
			"CombatTagged"
			) == true then

			local elapsed =
				workspace:GetServerTimeNow()
			- state.lastCombatTagJumpTime

			if elapsed <
				COMBAT_TAG_TREE_JUMP_COOLDOWN then

				dbg(
					"rechazado: CombatTag cooldown "
						..
						string.format(
							"%.2f",
							COMBAT_TAG_TREE_JUMP_COOLDOWN
							- elapsed
						)
						..
						"s"
				)

				return
			end
		end

		-- ====================================
		-- TARGET VALIDATION
		-- ====================================

		if typeof(branchRef) ~= "Instance"
			or not branchRef:IsA("BasePart")
			or not isValidBranch(branchRef) then

			return
		end

		local branch =
			branchRef :: BasePart

		local currentBranch =
			getCurrentStandingBranch(
				character,
				humanoid,
				rootPart
			)

		if currentBranch
			and currentBranch == branch then

			return
		end

		if not findTreeModelFor(
			branch
			) then

			return
		end

		local rootPos =
			rootPart.Position

		local distance =
			(
				branch.Position
				- rootPos
			).Magnitude

		if distance < MIN_DISTANCE
			or distance > MAX_DISTANCE then

			return
		end

		-- ====================================
		-- LANDING POSITION
		-- ====================================

		local characterHeight =
			(rootPart.Size.Y / 2)
			+ humanoid.HipHeight
			+ 1.5

		local branchPos =
			branch.Position

		local branchTopY =
			branchPos.Y
			+ branch.Size.Y / 2

		local horizontal =
			Vector3.new(
				branchPos.X - rootPos.X,
				0,
				branchPos.Z - rootPos.Z
			)

		if horizontal.Magnitude > 0.001 then
			horizontal =
				horizontal.Unit
				* DISTANCE_OFFSET
		else
			horizontal =
				Vector3.zero
		end

		local landingPos =
			Vector3.new(
				branchPos.X - horizontal.X,
				branchTopY + characterHeight,
				branchPos.Z - horizontal.Z
			)

		if not hasClearDashPath(
			rootPart,
			landingPos,
			branch,
			character
			) then

			return
		end

		-- ====================================
		-- NORMAL CHAIN LIMIT
		-- ====================================

		if time()
			- state.lastUseTime >
			COUNTER_TIMEOUT then

			state.uses = 0
		end

		if state.uses >= MAX_USES then
			return
		end

		-- ====================================
		-- DURATION / ARC
		-- ====================================

		local travel =
			landingPos
		- rootPos

		local travelDistance =
			travel.Magnitude

		local duration =
			math.clamp(
				travelDistance
				/ TREE_JUMP_SPEED,
				MIN_JUMP_DURATION,
				MAX_JUMP_DURATION
			)

		local horizontalDistance =
			Vector3.new(
				travel.X,
				0,
				travel.Z
			).Magnitude

		local arcHeight =
			math.clamp(
				horizontalDistance
				* ARC_HEIGHT_PER_STUD,
				MIN_ARC_HEIGHT,
				MAX_ARC_HEIGHT
			)

		-- ====================================
		-- STAMINA � PvP ONLY
		-- ====================================

		local combatTagged =
			player:GetAttribute(
				"CombatTagged"
			) == true
			or character:GetAttribute(
				"CombatTagged"
			) == true

		local treeJumpStaminaCost =
			if combatTagged
			then StaminaConfig.Actions.TreeJump.CombatTaggedCost
			else StaminaConfig.Actions.TreeJump.OpenWorldCost

		if treeJumpStaminaCost > 0 then
			local staminaAllowed,
			staminaReason =
				StaminaService.TrySpend(
					player,
					treeJumpStaminaCost,
					"TreeJump"
				)

			if not staminaAllowed then
				dbg(
					"rechazado: Tree Jump Stamina - "
						.. tostring(staminaReason)
				)

				return
			end
		end

		-- ====================================
		-- APPROVE
		-- ====================================

		state.busy = true
		state.uses += 1
		state.lastUseTime = time()

		if player:GetAttribute(
			"CombatTagged"
			) == true then

			local cooldownStartsAt =
				workspace:GetServerTimeNow()

			local cooldownEndsAt =
				cooldownStartsAt
				+ COMBAT_TAG_TREE_JUMP_COOLDOWN

			state.lastCombatTagJumpTime =
				cooldownStartsAt

			character:SetAttribute(
				"CoreCooldown_TreeJump_StartsAt",
				cooldownStartsAt
			)

			character:SetAttribute(
				"CoreCooldown_TreeJump_EndsAt",
				cooldownEndsAt
			)
		end

		character:SetAttribute(
			"TreeJumpUses",
			state.uses
		)

		character:SetAttribute(
			"IsTreeJumping",
			true
		)

		character:SetAttribute(
			"TreeJumpProtected",
			true
		)

		approvedEvent:FireClient(
			player,
			landingPos,
			duration,
			arcHeight
		)

		for _, targetPlayer in ipairs(
			Players:GetPlayers()
			) do
			replicateEvent:FireClient(
				targetPlayer,
				player,
				landingPos
			)
		end

		-- ====================================
		-- WATCHDOG / FINISH
		-- ====================================

		task.delay(
			duration
				+ SERVER_FINISH_BUFFER,
			function()
				local currentState =
					playerState[player]

				if not currentState then
					return
				end

				if character.Parent
					and rootPart.Parent then

					if isDownedSystemLocked(
						character
						) then

						clearTreeJumpState(
							player,
							character
						)

						resetCounter(player)
						return
					end

					if character:GetAttribute(
						"TreeJumpProtected"
						) == true then

						local deviation =
							(
								rootPart.Position
								- landingPos
							).Magnitude

						if deviation >
							CORRECTION_THRESHOLD then

							local rotation =
								rootPart.CFrame.Rotation

							rootPart.CFrame =
								CFrame.new(
									landingPos
								)
								* rotation

							rootPart.AssemblyLinearVelocity =
								Vector3.zero

							rootPart.AssemblyAngularVelocity =
								Vector3.zero
						end

						character:SetAttribute(
							"TreeJumpProtected",
							false
						)

						character:SetAttribute(
							"TreeJumpActive",
							false
						)
					end

					character:SetAttribute(
						"IsTreeJumping",
						false
					)
				end

				currentState.busy = false

				scheduleCounterReset(
					player
				)
			end
		)
	end
)

print(
	"[TreeJumpServer v3.3 PvPStamina] online"
		.. " | OpenWorldCost="
		.. tostring(
			StaminaConfig.Actions.TreeJump.OpenWorldCost
		)
		.. " | PvPCost="
		.. tostring(
			StaminaConfig.Actions.TreeJump.CombatTaggedCost
		)
		.. " | CombatTagCooldown="
		.. tostring(
			COMBAT_TAG_TREE_JUMP_COOLDOWN
		)
		.. "s"
)
