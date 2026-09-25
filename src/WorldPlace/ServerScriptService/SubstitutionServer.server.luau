--!strict
-- SubstitutionServer v2.6 - Launcher Air Counterplay + Core Cooldown Contract
-- ServerScriptService > SubstitutionServer [Script]
--
-- Server-authoritative Naruto-style substitution / replacement.
--
-- Core rule:
-- The player presses the substitution key to arm a very short dodge window.
-- If combat damage reaches the shared DownedInternal.ApplyDamage gateway
-- during that window, the hit is consumed, a log is left at the old position,
-- the existing ExecutionPoofFX smoke/SFX is played, and the player is moved
-- to a random safe nearby position.
--
-- This module never edits Humanoid locomotion states.
-- It does not own Sprint / Dash / Jump / SurfaceWalking.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SubstitutionService = {}

-- =========================
-- TUNING
-- =========================

-- TEMP TEST VALUE: enlarged so two players can reliably validate the mechanic.
-- Final balance value will be reduced after functional testing.
local DODGE_WINDOW = 1.00

-- Initial balance value. Exposed here for later tuning.
local COOLDOWN = 6.0

-- Random horizontal displacement.
local TELEPORT_MIN_RADIUS = 10
local TELEPORT_MAX_RADIUS = 18

-- Stratified sampling: every substitution covers the full 360-degree ring
-- instead of relying on 20 completely random directions. The starting angle
-- is still random, so the final teleport remains unpredictable.
local DESTINATION_ATTEMPTS = 48

-- Ground search around candidate positions.
--
-- v2.3 only searched 10 studs upward. On tall/wide staircases, candidate
-- steps farther uphill could be above the ray origin and therefore invisible.
local GROUND_RAY_UP = 36
local GROUND_RAY_DOWN = 72
local MAX_GROUNDED_SOURCE_DISTANCE = 5.0

-- A direct torso-height line can hit staircase risers even when an R6-sized
-- route above the steps is perfectly usable. We retry at a modest clearance
-- height. Tall walls/trees still block the elevated check.
local STAIR_PATH_CLEARANCE = 2.75

-- Endpoint occupancy volume.
--
-- v2.4 used 3.5 x 5.2 x 3.5 centered directly on the HRP. On staircases this
-- frequently overlapped the next riser/tread even though a normal R6 could
-- stand there.
--
-- This box represents the collision-critical center of an R6 rather than the
-- full visual arm span. It is also lifted slightly so the floor/tread directly
-- below the feet is not misclassified as an obstruction.
local DESTINATION_BOX_SIZE = Vector3.new(2.25, 4.40, 2.25)
local DESTINATION_BOX_Y_OFFSET = 0.45

-- Final free-space fallback used only if no grounded/normal-air destination
-- survives. It allows Kawarimi to escape complex staircase geometry without
-- requiring a floor at the destination.
local FAILSAFE_ATTEMPTS = 48
local FAILSAFE_MIN_RADIUS = 6
local FAILSAFE_MAX_RADIUS = 15
local FAILSAFE_MIN_HEIGHT = 5
local FAILSAFE_MAX_HEIGHT = 12

-- Visual replacement remains briefly after the dodge.
local LOG_LIFETIME = 3.5
local LOG_FADE_TIME = 0.50

-- Physical replacement tuning.
local LOG_INITIAL_DOWNWARD_SPEED = 1.5
local LOG_INITIAL_TUMBLE_SPEED = 1.75

-- If the incoming attack was a kunai, the live projectile should be very
-- close to the old body position at the exact substitution frame.
local KUNAI_CAPTURE_RADIUS = 7.0
local KUNAI_VISUAL_EMBED_DEPTH = 0.30

-- =========================
-- REMOTES
-- =========================

local remotes =
	ReplicatedStorage:FindFirstChild("SubstitutionRemotes")

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "SubstitutionRemotes"
	remotes.Parent = ReplicatedStorage
end

local requestRemote =
	remotes:FindFirstChild("SubstitutionRequest") :: RemoteEvent?

if not requestRemote then
	requestRemote = Instance.new("RemoteEvent")
	requestRemote.Name = "SubstitutionRequest"
	requestRemote.Parent = remotes
end

local stateRemote =
	remotes:FindFirstChild("SubstitutionState") :: RemoteEvent?

if not stateRemote then
	stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = "SubstitutionState"
	stateRemote.Parent = remotes
end

-- =========================
-- STATE
-- =========================

type PlayerState = {
	windowUntil: number,
	cooldownUntil: number,
	generation: number,
	character: Model?,
}

local states: {[Player]: PlayerState} = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getState(player: Player): PlayerState
	local state = states[player]

	if state then
		return state
	end

	state = {
		windowUntil = 0,
		cooldownUntil = 0,
		generation = 0,
		character = nil,
	}

	states[player] = state
	return state
end

-- =========================
-- CHARACTER HELPERS
-- =========================

local function isValidCharacterHint(
	player: Player,
	characterHint: any
): boolean

	if typeof(characterHint) ~= "Instance"
		or not characterHint:IsA("Model")
		or not characterHint.Parent then

		return false
	end

	-- The client may explicitly send its current script.Parent because some
	-- custom-character lifecycles can temporarily leave Player.Character nil.
	--
	-- RemoteEvent Instance arguments can only reference server-known Instances.
	-- Requiring the model to match the player's unique Roblox name prevents
	-- selecting another player's Character.
	if characterHint.Name ~= player.Name then
		return false
	end

	if not characterHint:IsDescendantOf(workspace) then
		return false
	end

	return true
end


local function getCharacterPieces(
	player: Player,
	characterHint: any?
): (Model?, Humanoid?, BasePart?, string)

	local state =
		getState(player)

	local character =
		player.Character

	if not character
		or not character.Parent then

		if isValidCharacterHint(
			player,
			characterHint
			) then

			character =
				characterHint

		elseif state.character
			and state.character.Parent
			and state.character.Name == player.Name
			and state.character:IsDescendantOf(workspace) then

			character =
				state.character
		end
	end

	if not character then
		return nil,
			nil,
			nil,
			"CharacterNil"
	end

	if not character.Parent then
		return nil,
			nil,
			nil,
			"CharacterUnparented"
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid then
		return character,
			nil,
			nil,
			"HumanoidMissing"
	end

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not root then
		return character,
			humanoid,
			nil,
			"RootMissing"
	end

	if not root:IsA("BasePart") then
		return character,
			humanoid,
			nil,
			"RootWrongClass"
	end

	-- Successful resolution becomes the service's authoritative current model
	-- for this life. Damage-triggered substitution can then use it even if
	-- Player.Character itself is temporarily nil.
	state.character =
		character

	return character,
		humanoid,
		root,
		"OK"
end

local function isLauncherAirVictim(character: Model): boolean
	return character:GetAttribute(
		"AirComboServerActive"
	) == true
		and character:GetAttribute(
			"AirComboRole"
		) == "Victim"
		and character:GetAttribute(
			"LauncherAirComboVictim"
		) == true
end


local function isBusy(character: Model): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsCarrying") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsBeingExecuted") == true
		or character:GetAttribute("IsRecovering") == true
		or (
			character:GetAttribute("IsStunned") == true
			and not isLauncherAirVictim(character)
		)
		or character:GetAttribute("IsAttacking") == true
		or character:GetAttribute("IsDashing") == true
		or character:GetAttribute("IsBlocking") == true
		or character:GetAttribute("TreeJumpActive") == true
		or character:GetAttribute("IsTreeJumping") == true
		or character:GetAttribute("SurfaceJumping") == true
end

local function canArm(
	player: Player,
	characterHint: any?
): (boolean, string)

	local character,
		humanoid,
		root,
		characterReason =
		getCharacterPieces(
			player,
			characterHint
		)

	if not character
		or not humanoid
		or not root then

		return false,
			characterReason
	end

	if humanoid.Health <= 0 then
		return false,
			"HumanoidDead"
	end

	if isBusy(character) then
		return false, "Busy"
	end

	local humanoidState = humanoid:GetState()

	if humanoidState == Enum.HumanoidStateType.Dead
		or humanoidState == Enum.HumanoidStateType.Seated
		or humanoidState == Enum.HumanoidStateType.Swimming then
		return false, "InvalidHumanoidState"
	end

	local state = getState(player)

	if now() < state.cooldownUntil then
		return false, "Cooldown"
	end

	return true, "OK"
end

-- =========================
-- RAYCAST / SPACE HELPERS
-- =========================

local function allCharacterModels(): {Instance}
	local exclusions: {Instance} = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local character = otherPlayer.Character

		if character then
			table.insert(exclusions, character)
		end
	end

	return exclusions
end

local function makeWorldRayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = allCharacterModels()
	params.IgnoreWater = false
	params.RespectCanCollide = true
	return params
end

local function calculateRootGroundOffset(
	character: Model,
	humanoid: Humanoid,
	root: BasePart
): number

	local maxFootDistance = 0

	for _, legName in ipairs({
		"Left Leg",
		"Right Leg",
		}) do
		local leg =
			character:FindFirstChild(legName)

		if leg and leg:IsA("BasePart") then
			local localPosition =
				root.CFrame:
				PointToObjectSpace(
					leg.Position
				)

			local footDistance =
				-localPosition.Y
				+ (leg.Size.Y / 2)

			maxFootDistance =
				math.max(
					maxFootDistance,
					footDistance
				)
		end
	end

	local fallback =
		humanoid.HipHeight
		+ (root.Size.Y / 2)
		+ 1.5

	return math.max(
		maxFootDistance,
		fallback,
		2.75
	) + 0.08
end

local function getHorizontalFacing(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(
		look.X,
		0,
		look.Z
	)

	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end

	return flat.Unit
end

local function isSourcePhysicallyGrounded(
	root: BasePart
): boolean

	local result =
		workspace:Raycast(
			root.Position,
			Vector3.new(
				0,
				-MAX_GROUNDED_SOURCE_DISTANCE,
				0
			),
			makeWorldRayParams()
		)

	return result ~= nil
		and result.Material ~= Enum.Material.Water
end

local function rayPathIsClear(
	fromPosition: Vector3,
	toPosition: Vector3
): boolean

	local delta =
		toPosition - fromPosition

	if delta.Magnitude < 0.25 then
		return true
	end

	local result =
		workspace:Raycast(
			fromPosition,
			delta,
			makeWorldRayParams()
		)

	if not result then
		return true
	end

	-- A hit extremely close to the destination is generally the destination
	-- floor/edge rather than a barrier between both points.
	return (
		result.Position
		- toPosition
	).Magnitude <= 2.25
end


local function pathIsClear(
	fromPosition: Vector3,
	toPosition: Vector3
): boolean

	-- First try the old direct path.
	if rayPathIsClear(
		fromPosition,
		toPosition
		) then
		return true
	end

	-- Stair-aware retry:
	-- A staircase riser can intersect the direct torso line even though the
	-- character can safely exist on a higher/lower step. Shift BOTH ends up by
	-- the same modest clearance and retry along the same route.
	--
	-- This is intentionally not a huge "teleport over everything" height.
	-- Large walls and tree trunks still intersect this path.
	local clearance =
		Vector3.new(
			0,
			STAIR_PATH_CLEARANCE,
			0
		)

	return rayPathIsClear(
		fromPosition + clearance,
		toPosition + clearance
	)
end

local function destinationIsOpen(
	character: Model,
	targetCFrame: CFrame
): boolean

	local exclusions: {Instance} = {
		character,
	}

	local logsFolder =
		workspace:FindFirstChild(
			"SubstitutionLogs"
		)

	if logsFolder then
		table.insert(
			exclusions,
			logsFolder
		)
	end

	local params =
		OverlapParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		exclusions

	params.RespectCanCollide =
		true

	-- Lift the clearance box above the destination floor. A teleport endpoint
	-- only needs room for the collision-critical body volume; it should not be
	-- rejected because the box barely clips the stair tread under the feet.
	local clearanceCFrame =
		targetCFrame
		* CFrame.new(
			0,
			DESTINATION_BOX_Y_OFFSET,
			0
		)

	local parts =
		workspace:GetPartBoundsInBox(
			clearanceCFrame,
			DESTINATION_BOX_SIZE,
			params
		)

	for _, part in ipairs(parts) do
		if part:IsA("BasePart")
			and part.CanCollide then

			return false
		end
	end

	return true
end

local function makeTargetCFrame(
	position: Vector3,
	facing: Vector3
): CFrame

	return CFrame.lookAt(
		position,
		position + facing,
		Vector3.yAxis
	)
end

local function findGroundDestination(
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	origin: Vector3,
	facing: Vector3
): CFrame?

	local rootOffset =
		calculateRootGroundOffset(
			character,
			humanoid,
			root
		)

	local startAngle =
		math.random()
		* math.pi
		* 2

	for attempt = 1, DESTINATION_ATTEMPTS do
		-- Full-ring coverage + random starting rotation + small jitter.
		-- This prevents a wall from "winning" simply because all random samples
		-- happened to land on the blocked side.
		local angle =
			startAngle
			+ (
				(attempt - 1)
				/ DESTINATION_ATTEMPTS
			)
			* math.pi
			* 2
			+ (
				math.random()
				- 0.5
			)
			* math.rad(5)

		local radius =
			TELEPORT_MIN_RADIUS
			+ math.random()
			* (
				TELEPORT_MAX_RADIUS
				- TELEPORT_MIN_RADIUS
			)

		local direction =
			Vector3.new(
				math.cos(angle),
				0,
				math.sin(angle)
			)

		local flatCandidate =
			origin
			+ direction * radius

		local rayOrigin =
			flatCandidate
			+ Vector3.new(
				0,
				GROUND_RAY_UP,
				0
			)

		local result =
			workspace:Raycast(
				rayOrigin,
				Vector3.new(
					0,
					-(GROUND_RAY_UP + GROUND_RAY_DOWN),
					0
				),
				makeWorldRayParams()
			)

		if result
			and result.Material ~= Enum.Material.Water
			and result.Normal.Y >= 0.35 then

			local position =
				result.Position
				+ Vector3.new(
					0,
					rootOffset,
					0
				)

			local targetCFrame =
				makeTargetCFrame(
					position,
					facing
				)

			-- Kawarimi is a teleport, not a dash. Geometry BETWEEN origin and
			-- destination is irrelevant; only the endpoint must be safe.
			if destinationIsOpen(
				character,
				targetCFrame
				) then

				return targetCFrame
			end
		end
	end

	return nil
end

local function findAirDestination(
	character: Model,
	root: BasePart,
	origin: Vector3,
	facing: Vector3
): CFrame?

	local startAngle =
		math.random()
		* math.pi
		* 2

	for attempt = 1, DESTINATION_ATTEMPTS do
		-- Full-ring coverage + random starting rotation + small jitter.
		-- This prevents a wall from "winning" simply because all random samples
		-- happened to land on the blocked side.
		local angle =
			startAngle
			+ (
				(attempt - 1)
				/ DESTINATION_ATTEMPTS
			)
			* math.pi
			* 2
			+ (
				math.random()
				- 0.5
			)
			* math.rad(5)

		local radius =
			TELEPORT_MIN_RADIUS
			+ math.random()
			* (
				TELEPORT_MAX_RADIUS
				- TELEPORT_MIN_RADIUS
			)

		local direction =
			Vector3.new(
				math.cos(angle),
				0,
				math.sin(angle)
			)

		local verticalJitter =
			-2
			+ math.random() * 5

		local position =
			origin
			+ direction * radius
			+ Vector3.new(
				0,
				verticalJitter,
				0
			)

		local targetCFrame =
			makeTargetCFrame(
				position,
				facing
			)

		-- Teleport endpoint validation only. A wall between both positions is
		-- allowed because no physical traversal occurs.
		if destinationIsOpen(
			character,
			targetCFrame
			) then

			return targetCFrame
		end
	end

	return nil
end

local function findElevatedFailSafeDestination(
	character: Model,
	root: BasePart,
	origin: Vector3,
	facing: Vector3
): CFrame?

	local startAngle =
		math.random()
		* math.pi
		* 2

	for attempt = 1, FAILSAFE_ATTEMPTS do
		local angle =
			startAngle
			+ (
				(attempt - 1)
				/ FAILSAFE_ATTEMPTS
			)
			* math.pi
			* 2

		local radius =
			FAILSAFE_MIN_RADIUS
			+ math.random()
			* (
				FAILSAFE_MAX_RADIUS
				- FAILSAFE_MIN_RADIUS
			)

		local height =
			FAILSAFE_MIN_HEIGHT
			+ math.random()
			* (
				FAILSAFE_MAX_HEIGHT
				- FAILSAFE_MIN_HEIGHT
			)

		local direction =
			Vector3.new(
				math.cos(angle),
				0,
				math.sin(angle)
			)

		local position =
			origin
			+ direction * radius
			+ Vector3.new(
				0,
				height,
				0
			)

		local targetCFrame =
			makeTargetCFrame(
				position,
				facing
			)

		if destinationIsOpen(
			character,
			targetCFrame
			) then

			return targetCFrame
		end
	end

	-- Absolute final local vertical candidates. These are intentionally only
	-- used after every random endpoint failed.
	for _, height in ipairs({
		8,
		12,
		16,
		}) do
		local position =
			origin
			+ Vector3.new(
				0,
				height,
				0
			)

		local targetCFrame =
			makeTargetCFrame(
				position,
				facing
			)

		if destinationIsOpen(
			character,
			targetCFrame
			) then

			return targetCFrame
		end
	end

	return nil
end


local function findSafeDestination(
	character: Model,
	humanoid: Humanoid,
	root: BasePart
): CFrame?

	local origin =
		root.Position

	local facing =
		getHorizontalFacing(root)

	if isSourcePhysicallyGrounded(root) then
		local groundedDestination =
			findGroundDestination(
				character,
				humanoid,
				root,
				origin,
				facing
			)

		if groundedDestination then
			return groundedDestination
		end

		-- First fallback: roughly same-altitude open space.
		local airFallback =
			findAirDestination(
				character,
				root,
				origin,
				facing
			)

		if airFallback then
			print(
				"[Substitution-Server]",
				character.Name,
				"used SAME-ALTITUDE fallback destination"
			)

			return airFallback
		end

		-- Final fallback for staircases / dense geometry:
		-- escape upward into an open endpoint and let normal gravity/locomotion
		-- bring the player back to terrain.
		local elevatedFallback =
			findElevatedFailSafeDestination(
				character,
				root,
				origin,
				facing
			)

		if elevatedFallback then
			print(
				"[Substitution-Server]",
				character.Name,
				"used ELEVATED FAILSAFE destination"
			)

			return elevatedFallback
		end

		return nil
	end

	-- Air / Water:
	-- prefer roughly the same altitude.
	local airDestination =
		findAirDestination(
			character,
			root,
			origin,
			facing
		)

	if airDestination then
		return airDestination
	end

	-- Dense airborne geometry still gets the same final endpoint-only escape.
	return findElevatedFailSafeDestination(
		character,
		root,
		origin,
		facing
	)
end

-- =========================
-- LOG VISUAL
-- =========================

local function getPoofRemote(): RemoteEvent?
	local downedRemotes =
		ReplicatedStorage:
		FindFirstChild(
			"DownedRemotes"
		)

	if not downedRemotes then
		return nil
	end

	return downedRemotes:
		FindFirstChild(
			"ExecutionPoofFX"
		) :: RemoteEvent?
end

local substitutionLogFolder =
	workspace:FindFirstChild(
		"SubstitutionLogs"
	)

if not substitutionLogFolder then
	substitutionLogFolder =
		Instance.new("Folder")

	substitutionLogFolder.Name =
		"SubstitutionLogs"

	substitutionLogFolder.Parent =
		workspace
end


local function getPrimaryPhysicsPart(
	replacement: Instance
): BasePart?

	if replacement:IsA("BasePart") then
		return replacement
	end

	if replacement:IsA("Model") then
		if replacement.PrimaryPart then
			return replacement.PrimaryPart
		end

		for _, descendant in ipairs(
			replacement:GetDescendants()
			) do
			if descendant:IsA("BasePart") then
				replacement.PrimaryPart =
					descendant

				return descendant
			end
		end
	end

	return nil
end


local function getReplacementParts(
	replacement: Instance
): {BasePart}

	local parts: {BasePart} = {}

	if replacement:IsA("BasePart") then
		table.insert(
			parts,
			replacement
		)

		return parts
	end

	for _, descendant in ipairs(
		replacement:GetDescendants()
		) do
		if descendant:IsA("BasePart") then
			table.insert(
				parts,
				descendant
			)
		end
	end

	return parts
end


local function weldReplacementModel(
	replacement: Instance,
	primary: BasePart,
	parts: {BasePart}
)
	if not replacement:IsA("Model") then
		return
	end

	for _, part in ipairs(parts) do
		if part ~= primary then
			local weld =
				Instance.new(
					"WeldConstraint"
				)

			weld.Name =
				"SubstitutionPhysicsWeld"

			weld.Part0 =
				primary

			weld.Part1 =
				part

			weld.Parent =
				primary
		end
	end
end


local function enableReplacementPhysics(
	replacement: Instance
): BasePart?

	local parts =
		getReplacementParts(
			replacement
		)

	local primary =
		getPrimaryPhysicsPart(
			replacement
		)

	if not primary then
		return nil
	end

	weldReplacementModel(
		replacement,
		primary,
		parts
	)

	for _, part in ipairs(parts) do
		part.Anchored = false
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = true
		part.Massless = false

		-- Keep physics authoritative on the server so the replacement behaves
		-- the same for every client.
		pcall(
			function()
				part:SetNetworkOwner(
					nil
				)
			end
		)
	end

	primary.AssemblyLinearVelocity =
		Vector3.new(
			0,
			-LOG_INITIAL_DOWNWARD_SPEED,
			0
		)

	primary.AssemblyAngularVelocity =
		Vector3.new(
			math.random(
				-100,
				100
			) / 100,
			math.random(
				-100,
				100
			) / 100,
			math.random(
				-100,
				100
			) / 100
		).Unit
		* LOG_INITIAL_TUMBLE_SPEED

	return primary
end


local function createFallbackLog(
	oldCFrame: CFrame
): Model

	local model =
		Instance.new("Model")

	model.Name =
		"SubstitutionLog"

	local log =
		Instance.new("Part")

	log.Name =
		"Log"

	log.Shape =
		Enum.PartType.Cylinder

	-- Cylinder axis is local X. At 4.4 studs this roughly occupies the height
	-- of the R6 body before gravity tips it over.
	log.Size =
		Vector3.new(
			4.4,
			1.3,
			1.3
		)

	log.Material =
		Enum.Material.Wood

	log.Color =
		Color3.fromRGB(
			111,
			72,
			45
		)

	log.CastShadow =
		true

	-- Mildly heavy wood: enough friction to settle naturally, almost no bounce.
	log.CustomPhysicalProperties =
		PhysicalProperties.new(
			0.75,
			0.55,
			0.05,
			1,
			1
		)

	local oldPosition =
		oldCFrame.Position

	local horizontalLook =
		Vector3.new(
			oldCFrame.LookVector.X,
			0,
			oldCFrame.LookVector.Z
		)

	if horizontalLook.Magnitude <
		0.01 then

		horizontalLook =
			Vector3.new(
				0,
				0,
				-1
			)
	else
		horizontalLook =
			horizontalLook.Unit
	end

	local yawJitter =
		math.rad(
			math.random(
				-18,
				18
			)
		)

	-- Spawn where the body actually was rather than snapping immediately to
	-- the ground. Physics then handles the visible drop / tumble.
	local base =
		CFrame.lookAt(
			oldPosition,
			oldPosition
			+ horizontalLook,
			Vector3.yAxis
		)

	log.CFrame =
		base
		* CFrame.Angles(
			0,
			yawJitter,
			math.rad(90)
		)

	log.Parent =
		model

	model.PrimaryPart =
		log

	return model
end


local function getKunaiPrimaryPart(
	model: Model
): BasePart?

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	for _, descendant in ipairs(
		model:GetDescendants()
		) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end


local function findNearbyAttackerKunai(
	attacker: Player?,
	oldPosition: Vector3
): Model?

	if not attacker then
		return nil
	end

	local kunaiFolder =
		workspace:FindFirstChild(
			"Kunais"
		)

	if not kunaiFolder then
		return nil
	end

	local expectedName =
		"Kunai_"
		.. attacker.Name

	local bestModel: Model? =
		nil

	local bestDistance =
		KUNAI_CAPTURE_RADIUS

	for _, child in ipairs(
		kunaiFolder:GetChildren()
		) do
		if child:IsA("Model")
			and child.Name ==
			expectedName then

			local blade =
				getKunaiPrimaryPart(
					child
				)

			if blade then
				local distance =
					(
						blade.Position
						- oldPosition
					).Magnitude

				if distance <=
					bestDistance then

					bestDistance =
						distance

					bestModel =
						child
				end
			end
		end
	end

	return bestModel
end


local function weldKunaiVisualToLog(
	sourceKunai: Model,
	replacement: Instance,
	replacementPrimary: BasePart,
	attacker: Player
)
	local ok,
		cloneResult =
		pcall(
			function()
				return sourceKunai:
				Clone()
			end
		)

	if not ok
		or not cloneResult
		or not cloneResult:IsA(
			"Model"
		) then

		return
	end

	local kunaiClone =
		cloneResult

	kunaiClone.Name =
		"SubstitutionKunai_"
		.. attacker.Name

	local blade =
		getKunaiPrimaryPart(
			kunaiClone
		)

	if not blade then
		kunaiClone:Destroy()
		return
	end

	kunaiClone.PrimaryPart =
		blade

	-- Remove ongoing projectile-only effects from the stuck visual.
	for _, descendant in ipairs(
		kunaiClone:GetDescendants()
		) do
		if descendant:IsA("Trail") then
			descendant.Enabled =
				false

		elseif descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end

	-- Keep the exact projectile world pose, but nudge it slightly toward the
	-- log center so it visually reads as embedded rather than hovering.
	local sourcePivot =
		sourceKunai:GetPivot()

	local sourceBlade =
		getKunaiPrimaryPart(
			sourceKunai
		)

	if sourceBlade then
		local towardLog =
			replacementPrimary.Position
		- sourceBlade.Position

		if towardLog.Magnitude >
			0.01 then

			sourcePivot +=
				towardLog.Unit
				* KUNAI_VISUAL_EMBED_DEPTH
		end
	end

	kunaiClone.Parent =
		substitutionLogFolder

	kunaiClone:PivotTo(
		sourcePivot
	)

	local kunaiParts: {BasePart} =
		{}

	for _, descendant in ipairs(
		kunaiClone:GetDescendants()
		) do
		if descendant:IsA("BasePart") then
			table.insert(
				kunaiParts,
				descendant
			)
		end
	end

	-- The normal flying kunai is moved while anchored. For the stuck copy we
	-- convert the whole model into one welded, massless assembly attached to
	-- the physical replacement log.
	for _, part in ipairs(
		kunaiParts
		) do
		if part ~= blade then
			local internalWeld =
				Instance.new(
					"WeldConstraint"
				)

			internalWeld.Name =
				"SubstitutionKunaiInternalWeld"

			internalWeld.Part0 =
				blade

			internalWeld.Part1 =
				part

			internalWeld.Parent =
				blade
		end

		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
	end

	local logWeld =
		Instance.new(
			"WeldConstraint"
		)

	logWeld.Name =
		"SubstitutionKunaiLogWeld"

	logWeld.Part0 =
		replacementPrimary

	logWeld.Part1 =
		blade

	logWeld.Parent =
		blade

	kunaiClone:SetAttribute(
		"SubstitutionCaughtKunai",
		true
	)

	Debris:AddItem(
		kunaiClone,
		LOG_LIFETIME
			+ 0.15
	)
end


local function spawnReplacementLog(
	oldCFrame: CFrame,
	targetPlayer: Player,
	attacker: Player?
): Instance?

	local template =
		ServerStorage:
		FindFirstChild(
			"SubstitutionLogTemplate"
		)

	local replacement: Instance

	if template
		and (
			template:IsA("Model")
				or template:IsA("BasePart")
		) then

		replacement =
			template:Clone()

		replacement.Name =
			"SubstitutionLog"

		replacement.Parent =
			substitutionLogFolder

		if replacement:IsA("Model") then
			replacement:PivotTo(
				oldCFrame
			)
		else
			replacement.CFrame =
				oldCFrame
		end
	else
		replacement =
			createFallbackLog(
				oldCFrame
			)

		replacement.Parent =
			substitutionLogFolder
	end

	replacement:SetAttribute(
		"IsSubstitutionLog",
		true
	)

	replacement:SetAttribute(
		"SubstitutionOwnerUserId",
		targetPlayer.UserId
	)

	replacement:SetAttribute(
		"SubstitutionSpawnedAt",
		now()
	)

	local parts =
		getReplacementParts(
			replacement
		)

	local primary =
		enableReplacementPhysics(
			replacement
		)

	-- If the triggering attack appears to be a live kunai from this attacker,
	-- preserve a stuck visual copy on the physical log.
	--
	-- The current KunaiServer removes its own projectile shortly after a
	-- character hit, so we clone the nearby live projectile and weld the clone
	-- to the replacement. This keeps current Kunai combat logic untouched.
	if primary then
		local nearbyKunai =
			findNearbyAttackerKunai(
				attacker,
				oldCFrame.Position
			)

		if nearbyKunai
			and attacker then

			weldKunaiVisualToLog(
				nearbyKunai,
				replacement,
				primary,
				attacker
			)
		end
	end

	task.delay(
		math.max(
			0,
			LOG_LIFETIME
			- LOG_FADE_TIME
		),
		function()
			for _, part in ipairs(
				parts
				) do
				if part.Parent then
					TweenService:Create(
						part,
						TweenInfo.new(
							LOG_FADE_TIME,
							Enum.EasingStyle.Quad,
							Enum.EasingDirection.Out
						),
						{
							Transparency =
								1,
						}
					):Play()
				end
			end
		end
	)

	Debris:AddItem(
		replacement,
		LOG_LIFETIME
			+ 0.15
	)

	return replacement
end

-- =========================
-- ATTRIBUTE STATE
-- =========================

local function setWindowAttributes(
	character: Model,
	active: boolean,
	windowUntil: number,
	cooldownUntil: number
)
	character:SetAttribute(
		"SubstitutionWindowActive",
		active
	)

	character:SetAttribute(
		"SubstitutionWindowEndsAt",
		windowUntil
	)

	character:SetAttribute(
		"SubstitutionCooldownEndsAt",
		cooldownUntil
	)

	character:SetAttribute(
		"CoreCooldown_Substitution_Label",
		"Substitution"
	)

	if cooldownUntil > 0 then
		character:SetAttribute(
			"CoreCooldown_Substitution_StartsAt",
			cooldownUntil - COOLDOWN
		)

		character:SetAttribute(
			"CoreCooldown_Substitution_EndsAt",
			cooldownUntil
		)
	else
		character:SetAttribute(
			"CoreCooldown_Substitution_StartsAt",
			0
		)

		character:SetAttribute(
			"CoreCooldown_Substitution_EndsAt",
			0
		)
	end
end

function SubstitutionService.ResetCharacter(
	player: Player,
	character: Model
)
	local state =
		getState(player)

	state.windowUntil = 0
	state.generation += 1
	state.character = character

	-- A true respawn starts with the ability ready.
	-- This is a per-life combat ability, not a persistent account timer.
	state.cooldownUntil = 0

	setWindowAttributes(
		character,
		false,
		0,
		0
	)
end

function SubstitutionService.Arm(
	player: Player,
	characterHint: any?
): (boolean, string, number)

	local allowed, reason =
		canArm(
			player,
			characterHint
		)

	local state =
		getState(player)

	if not allowed then
		return false,
			reason,
			math.max(
				0,
				state.cooldownUntil
				- now()
			)
	end

	local character =
		getState(player).character

	if not character
		or not character.Parent then

		return false,
			"CharacterLostAfterValidation",
			0
	end

	local currentTime =
		now()

	state.generation += 1
	local generation =
		state.generation

	state.windowUntil =
		currentTime
		+ DODGE_WINDOW

	state.cooldownUntil =
		currentTime
		+ COOLDOWN

	setWindowAttributes(
		character,
		true,
		state.windowUntil,
		state.cooldownUntil
	)

	task.delay(
		DODGE_WINDOW + 0.03,
		function()
			local current =
				states[player]

			if not current
				or current.generation ~= generation then
				return
			end

			if now() >= current.windowUntil then
				current.windowUntil = 0

				local activeCharacter =
					player.Character

				if activeCharacter
					and activeCharacter.Parent then

					activeCharacter:
						SetAttribute(
							"SubstitutionWindowActive",
							false
						)

					activeCharacter:
						SetAttribute(
							"SubstitutionWindowEndsAt",
							0
						)
				end
			end
		end
	)

	return true,
		"Armed",
		COOLDOWN
end

function SubstitutionService.IsWindowActive(
	player: Player
): boolean

	local state =
		states[player]

	if not state then
		return false
	end

	return state.windowUntil > now()
end

function SubstitutionService.TrySubstitute(
	targetPlayer: Player,
	attacker: Player?
): (boolean, string)

	local state =
		states[targetPlayer]

	if not state
		or state.windowUntil <= now() then
		return false, "NoWindow"
	end

	local character,
		humanoid,
		root,
		characterReason =
		getCharacterPieces(
			targetPlayer,
			nil
		)

	if not character
		or not humanoid
		or not root then

		warn(
			"[Substitution-Server] TrySubstitute character resolution failed for",
			targetPlayer.Name,
			characterReason
		)

		return false,
			characterReason
	end

	if humanoid.Health <= 0 then
		return false,
			"HumanoidDead"
	end

	-- Revalidate at HIT time. An armed window cannot bypass Downed/Execute/
	-- stun/action locks that began after the key press.
	if isBusy(character) then
		state.windowUntil = 0

		setWindowAttributes(
			character,
			false,
			0,
			state.cooldownUntil
		)

		return false, "BecameBusy"
	end

	local destination =
		findSafeDestination(
			character,
			humanoid,
			root
		)

	if not destination then
		warn(
			"[Substitution-Server] NO SAFE DESTINATION after ground + air + elevated fail-safe for",
			targetPlayer.Name,
			"origin=",
			root.Position
		)

		-- Do not consume the active window if absolutely every endpoint failed.
		-- The warning above makes this condition directly visible in Output.
		return false,
			"NoSafeDestination"
	end

	-- Consume first so simultaneous multi-hit damage cannot trigger several
	-- teleports from the same window.
	state.generation += 1
	state.windowUntil = 0

	setWindowAttributes(
		character,
		false,
		0,
		state.cooldownUntil
	)

	local oldCFrame =
		root.CFrame

	spawnReplacementLog(
		oldCFrame,
		targetPlayer,
		attacker
	)

	-- Reuse the exact smoke + poof SFX already used by Execute.
	local poofRemote =
		getPoofRemote()

	if poofRemote then
		poofRemote:FireAllClients(
			oldCFrame
		)
	end

	-- Teleport the entire R6 assembly. Do not ChangeState or force Running.
	character:PivotTo(
		destination
	)

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero

	character:SetAttribute(
		"LastSubstitutionAt",
		now()
	)

	local airComboId =
		character:GetAttribute(
			"AirComboId"
		)

	if isLauncherAirVictim(character)
		and typeof(airComboId) == "number" then

		local airControl =
			ServerScriptService:
			FindFirstChild(
				"LauncherAirComboControl"
			)

		if airControl
			and airControl:IsA(
				"BindableEvent"
			) then

			airControl:Fire(
				"VictimSubstituted",
				targetPlayer,
				airComboId
			)
		end
	end

	stateRemote:FireAllClients(
		"Triggered",
		targetPlayer,
		attacker,
		oldCFrame,
		destination
	)

	print(
		"[Substitution-Server]",
		targetPlayer.Name,
		"substituted attack from",
		attacker
			and attacker.Name
			or "unknown"
	)

	return true, "Substituted"
end

function SubstitutionService.GetRequestRemote(): RemoteEvent
	return requestRemote
end

function SubstitutionService.GetStateRemote(): RemoteEvent
	return stateRemote
end

function SubstitutionService.RemovePlayer(
	player: Player
)
	states[player] = nil
end

function SubstitutionService.GetCooldownRemaining(
	player: Player
): number

	local state =
		getState(player)

	return math.max(
		0,
		state.cooldownUntil - now()
	)
end

-- =========================
-- SERVER-ONLY INTERNAL GATEWAY
-- =========================
--
-- DownedServer talks to Substitution through this BindableFunction.
-- It no longer requires this Script or depends on this Script's Instance name.

local internalFolder =
	ServerStorage:FindFirstChild(
		"SubstitutionInternal"
	)

if not internalFolder then
	internalFolder =
		Instance.new("Folder")

	internalFolder.Name =
		"SubstitutionInternal"

	internalFolder.Parent =
		ServerStorage
end

local trySubstitutionFunction =
	internalFolder:
	FindFirstChild(
		"TrySubstitution"
	) :: BindableFunction?

if not trySubstitutionFunction then
	trySubstitutionFunction =
		Instance.new(
			"BindableFunction"
		)

	trySubstitutionFunction.Name =
		"TrySubstitution"

	trySubstitutionFunction.Parent =
		internalFolder
end

trySubstitutionFunction.OnInvoke =
	function(
		targetPlayer: Player,
		attacker: Player?
	): boolean

	local substituted =
		SubstitutionService.TrySubstitute(
			targetPlayer,
			attacker
		)

	return substituted
end

-- =========================
-- INPUT + PLAYER LIFECYCLE
-- =========================

requestRemote.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: any,
			characterHint: any
		)

			if action ~= "Arm" then
				return
			end

			print(
				"[Substitution-Server] Arm request from",
				player.Name,
				"Player.Character=",
				player.Character
				and player.Character:GetFullName()
				or "nil",
				"hint=",
				if typeof(characterHint) == "Instance"
				then characterHint:GetFullName()
				else tostring(characterHint)
			)

			local success,
			reason,
			cooldown =
			SubstitutionService.Arm(
				player,
				characterHint
			)

			if success then
				local character =
				player.Character

				local windowEndsAt =
				if character
				then character:
				GetAttribute(
					"SubstitutionWindowEndsAt"
				)
				else 0

				local cooldownEndsAt =
				if character
				then character:
				GetAttribute(
					"SubstitutionCooldownEndsAt"
				)
				else 0

				print(
					"[Substitution-Server] Arm ACCEPTED",
					player.Name,
					"resolvedCharacter=",
					player.Character
					and player.Character:GetFullName()
					or "stored-character",
					"windowUntil=",
					windowEndsAt
				)

				stateRemote:
				FireClient(
					player,
					"Armed",
					windowEndsAt,
					cooldownEndsAt
				)
			else
				print(
					"[Substitution-Server] Arm REJECTED",
					player.Name,
					reason,
					"cooldownRemaining=",
					cooldown
				)

				stateRemote:
				FireClient(
					player,
					"Rejected",
					reason,
					cooldown
				)
			end
		end
	)

local function bindCharacter(
	player: Player,
	character: Model
)
	SubstitutionService.ResetCharacter(
		player,
		character
	)
end

local function bindPlayer(
	player: Player
)
	player.CharacterAdded:
		Connect(
			function(character)
				bindCharacter(
					player,
					character
				)
			end
		)

	if player.Character then
		task.defer(
			bindCharacter,
			player,
			player.Character
		)
	end
end

Players.PlayerAdded:
	Connect(bindPlayer)

Players.PlayerRemoving:
	Connect(
		function(player)
			SubstitutionService.RemovePlayer(
				player
			)
		end
	)

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.defer(
		bindPlayer,
		player
	)
end

print(
	"[Substitution-Server] READY v2.6 LauncherAirCounterplay=ON CoreCooldownContract=ON endpointOnlyTP=ON stairFailSafe=ON physicalLog=ON kunaiCatchVisual=ON window=1.00s cooldown=6.00s"
)
