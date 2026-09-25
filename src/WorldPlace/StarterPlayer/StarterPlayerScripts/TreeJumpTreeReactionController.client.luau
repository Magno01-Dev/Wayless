--!strict
-- TreeJumpTreeReactionController v1.3
-- Foliage-Origin Leaves + Safe Foliage Sway
-- ElDiabloLocoStudios / Roblox
--
-- REPLACE ONLY:
-- StarterPlayer > StarterPlayerScripts > TreeJumpTreeReactionController
--
-- ADDITIVE ONLY.
-- Does NOT modify TreeJumpController / TreeJumpServer / TargetIndicator /
-- FOV / DOF / trajectory / speed / arc / WindTrail / TreeJumpPolish.
--
-- v1.3:
-- - Landing on the branch remains the trigger.
-- - Leaves now originate from ACTUAL foliage parts of the SAME tree.
-- - Closest foliage to the impacted branch is prioritized.
-- - If no safe foliage is detected, NO leaves spawn from the branch.
-- - Safe non-collidable foliage sway remains.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

local TweenService =
	game:GetService("TweenService")

local Debris =
	game:GetService("Debris")


local localPlayer =
	Players.LocalPlayer


local TREE_FOLDER =
	workspace:
	WaitForChild(
		"Arboles"
	)


local replicateEvent =
	ReplicatedStorage:
	WaitForChild(
		"TreeJumpReplicate"
	) :: RemoteEvent


-- ============================================================
-- CONFIG
-- ============================================================

local DEBUG =
	true

local MAX_RENDER_DISTANCE =
	230


-- Arrival
local TREE_JUMP_SPEED_MIRROR =
	160

local MIN_TRAVEL_TIME =
	0.20

local MAX_TRAVEL_TIME =
	1.60

local ARRIVAL_RADIUS =
	7.0

local ARRIVAL_EXTRA_TIMEOUT =
	0.70


-- Actual branch-under-feet detection
local BRANCH_RAY_START_UP =
	1.0

local BRANCH_RAY_DISTANCE =
	11.0


-- ============================================================
-- FOLIAGE LEAVES
-- ============================================================

local LEAF_COUNT_MIN =
	10

local LEAF_COUNT_MAX =
	15

local LEAF_WIDTH_MIN =
	0.18

local LEAF_WIDTH_MAX =
	0.28

local LEAF_LENGTH_MIN =
	0.45

local LEAF_LENGTH_MAX =
	0.72

local LEAF_THICKNESS =
	0.04

local LEAF_LIFETIME_MIN =
	1.55

local LEAF_LIFETIME_MAX =
	2.20


-- We only use foliage reasonably close to the branch landing.
local FOLIAGE_SEARCH_RADIUS =
	46

-- Among all detected foliage pieces, prioritize this many nearest pieces
-- as actual leaf emission sources.
local MAX_LEAF_SOURCE_PARTS =
	7

local LEAF_SOURCE_INSET =
	0.10


-- Leaf motion: a small disturbance FROM the foliage, then gentle fall.
local LEAF_INITIAL_UP_MIN =
	0.6

local LEAF_INITIAL_UP_MAX =
	2.0

local LEAF_SIDE_SPEED_MIN =
	1.0

local LEAF_SIDE_SPEED_MAX =
	3.2

local LEAF_CUSTOM_GRAVITY_MIN =
	4.0

local LEAF_CUSTOM_GRAVITY_MAX =
	6.5

local LEAF_SWAY_AMPLITUDE_MIN =
	0.16

local LEAF_SWAY_AMPLITUDE_MAX =
	0.38

local LEAF_SWAY_FREQUENCY_MIN =
	4.5

local LEAF_SWAY_FREQUENCY_MAX =
	7.5


-- ============================================================
-- SAFE FOLIAGE SWAY
-- ============================================================

local MAX_SWAY_PARTS =
	14

local SWAY_TRANSLATION_MIN =
	0.04

local SWAY_TRANSLATION_MAX =
	0.10

local SWAY_ANGLE_MIN_DEG =
	0.75

local SWAY_ANGLE_MAX_DEG =
	1.65

local SWAY_OUT_TIME =
	0.06

local SWAY_COUNTER_TIME =
	0.09

local SWAY_RETURN_TIME =
	0.16

local SAME_TREE_REACTION_COOLDOWN =
	0.12


-- ============================================================
-- CONSTANTS / STATE
-- ============================================================

local BRANCH_NAMES = {
	Branch_EA = true,
	Branch_NE = true,
	Branch_SW = true,
	Branch_WE = true,
}


local FOLIAGE_NAME_HINTS = {
	"leaf",
	"leaves",
	"foliage",
	"canopy",
	"crown",
	"bush",
	"copa",
	"hoja",
	"hojas",
}


local rng =
	Random.new()


local lastTreeReactionAt: {[Instance]: number} =
	{}


type ActiveSway = {
	baseCFrame: CFrame,
	token: number,
	tween: Tween?,
}


local activeSways: {[BasePart]: ActiveSway} =
	{}


local function dbg(
	message: string
)

	if DEBUG then

		print(
			"[TreeReaction v1.3] "
				.. message
		)
	end
end


-- ============================================================
-- BASIC HELPERS
-- ============================================================

local function isInsideTrees(
	instance: Instance?
): boolean

	local current =
		instance


	while current
		and current ~= workspace do

		if current ==
			TREE_FOLDER then

			return true
		end


		current =
			current.Parent
	end


	return false
end


local function findTreeModelFor(
	instance: Instance?
): Instance?

	if not instance then
		return nil
	end


	local current: Instance? =
		instance


	while current
		and current ~= workspace do

		if current.Parent ==
			TREE_FOLDER then

			return current
		end


		current =
			current.Parent
	end


	return nil
end


local function getLocalReferencePosition(): Vector3?

	local character =
		localPlayer.Character


	if character then

		local root =
			character:
			FindFirstChild(
				"HumanoidRootPart"
			)


		if root
			and root:IsA(
				"BasePart"
			) then

			return root.Position
		end
	end


	local camera =
		workspace.CurrentCamera


	if camera then

		return camera.CFrame.Position
	end


	return nil
end


local function shouldRenderAt(
	position: Vector3
): boolean

	local reference =
		getLocalReferencePosition()


	if not reference then
		return true
	end


	return (
		reference - position
	).Magnitude <=
		MAX_RENDER_DISTANCE
end


-- ============================================================
-- RELIABLE BRANCH DETECTION
-- ============================================================

local function getActualBranchBelowCharacter(
	character: Model,
	root: BasePart
): (
	BasePart?,
	Vector3?,
	Vector3?
	)

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{character}

	params.IgnoreWater =
		false


	local result =
		workspace:
		Raycast(
			root.Position
			+ Vector3.new(
				0,
				BRANCH_RAY_START_UP,
				0
			),
			Vector3.new(
				0,
				-BRANCH_RAY_DISTANCE,
				0
			),
			params
		)


	if not result
		or not result.Instance
		or not result.Instance:IsA(
			"BasePart"
		) then

		return nil,
			nil,
			nil
	end


	local part =
		result.Instance


	if BRANCH_NAMES[
		part.Name
		] ~= true
			or not isInsideTrees(
				part
			) then

		return nil,
			nil,
			nil
	end


	return part,
		result.Position,
		result.Normal
end


-- ============================================================
-- FOLIAGE DETECTION
-- ============================================================

local function nameLooksLikeFoliage(
	name: string
): boolean

	local lower =
		string.lower(
			name
		)


	for _, hint in ipairs(
		FOLIAGE_NAME_HINTS
		) do

		if string.find(
			lower,
			hint,
			1,
			true
			) then

			return true
		end
	end


	return false
end


local function colorLooksLikeFoliage(
	color: Color3
): boolean

	return color.G >
	color.R * 0.84
		and color.G >
	color.B * 0.98
		and color.G >
	0.13
end


local function isFoliageVisualPart(
	part: BasePart
): boolean

	if not part.Anchored then
		return false
	end


	-- Critical safety:
	-- never visually move / use collidable tree geometry as "foliage".
	if part.CanCollide then
		return false
	end


	if BRANCH_NAMES[
		part.Name
		] == true then

		return false
	end


	return nameLooksLikeFoliage(
		part.Name
	)
		or part.Material ==
		Enum.Material.LeafyGrass
		or colorLooksLikeFoliage(
			part.Color
		)
end


local function collectFoliageParts(
	tree: Instance,
	contactPosition: Vector3
): {BasePart}

	local candidates: {{
		part: BasePart,
		distance: number,
	}} =
		{}


	for _, descendant in ipairs(
		tree:GetDescendants()
		) do

		if descendant:IsA(
			"BasePart"
			)
				and isFoliageVisualPart(
					descendant
				) then

			local distance =
				(
					descendant.Position
					- contactPosition
				).Magnitude


			if distance <=
				FOLIAGE_SEARCH_RADIUS then

				table.insert(
					candidates,
					{
						part =
							descendant,
						distance =
							distance,
					}
				)
			end
		end
	end


	table.sort(
		candidates,
		function(
			a,
			b
		)

			return a.distance <
				b.distance
		end
	)


	local result: {BasePart} =
		{}


	for index = 1,
		math.min(
			#candidates,
			MAX_SWAY_PARTS
		) do

		table.insert(
			result,
			candidates[index].part
		)
	end


	return result
end


local function getLeafSourceParts(
	foliageParts: {BasePart}
): {BasePart}

	local result: {BasePart} =
		{}


	for index = 1,
		math.min(
			#foliageParts,
			MAX_LEAF_SOURCE_PARTS
		) do

		table.insert(
			result,
			foliageParts[index]
		)
	end


	return result
end


-- ============================================================
-- RANDOM POINT INSIDE FOLIAGE
-- ============================================================

local function randomPointInsidePart(
	part: BasePart
): Vector3

	local half =
		part.Size
		* 0.5


	local localPoint =
		Vector3.new(
			rng:NextNumber(
				-half.X
				+ LEAF_SOURCE_INSET,
				half.X
				- LEAF_SOURCE_INSET
			),
			rng:NextNumber(
				-half.Y
				+ LEAF_SOURCE_INSET,
				half.Y
				- LEAF_SOURCE_INSET
			),
			rng:NextNumber(
				-half.Z
				+ LEAF_SOURCE_INSET,
				half.Z
				- LEAF_SOURCE_INSET
			)
		)


	return part.CFrame:
		PointToWorldSpace(
			localPoint
		)
end


local function chooseLeafBaseColor(
	sourcePart: BasePart
): Color3

	return sourcePart.Color:
		Lerp(
			Color3.new(
				1,
				1,
				1
			),
			0.05
		)
end


-- ============================================================
-- DETERMINISTIC LEAF RENDERING
-- ============================================================

local function makeLeafPart(
	position: Vector3,
	baseColor: Color3
): WedgePart

	local leaf =
		Instance.new(
			"WedgePart"
		)


	leaf.Name =
		"TreeJumpLeaf_v1_3"


	leaf.Size =
		Vector3.new(
			rng:NextNumber(
				LEAF_WIDTH_MIN,
				LEAF_WIDTH_MAX
			),
			LEAF_THICKNESS,
			rng:NextNumber(
				LEAF_LENGTH_MIN,
				LEAF_LENGTH_MAX
			)
		)


	local variation =
		rng:NextNumber(
			-0.08,
			0.10
		)


	if variation >=
		0 then

		leaf.Color =
			baseColor:
			Lerp(
				Color3.new(
					1,
					1,
					1
				),
				variation
			)

	else

		leaf.Color =
			baseColor:
			Lerp(
				Color3.new(
					0,
					0,
					0
				),
				-variation
			)
	end


	leaf.Material =
		Enum.Material.SmoothPlastic

	leaf.Transparency =
		0

	leaf.CastShadow =
		false

	leaf.Anchored =
		true

	leaf.CanCollide =
		false

	leaf.CanTouch =
		false

	leaf.CanQuery =
		false

	leaf.CFrame =
		CFrame.new(
			position
		)


	leaf.Parent =
		workspace


	return leaf
end


local function animateLeaf(
	leaf: BasePart,
	startPosition: Vector3,
	arrivalDirection: Vector3,
	lifetime: number
)

	local horizontalArrival =
		Vector3.new(
			arrivalDirection.X,
			0,
			arrivalDirection.Z
		)


	if horizontalArrival.Magnitude >
		0.01 then

		horizontalArrival =
			horizontalArrival.Unit
	else

		horizontalArrival =
			Vector3.zero
	end


	local randomHorizontal =
		Vector3.new(
			rng:NextNumber(
				-1,
				1
			),
			0,
			rng:NextNumber(
				-1,
				1
			)
		)


	if randomHorizontal.Magnitude >
		0.01 then

		randomHorizontal =
			randomHorizontal.Unit
	else

		randomHorizontal =
			Vector3.xAxis
	end


	local initialVelocity =
		Vector3.new(
			0,
			rng:NextNumber(
				LEAF_INITIAL_UP_MIN,
				LEAF_INITIAL_UP_MAX
			),
			0
		)
		+ randomHorizontal
		* rng:NextNumber(
			LEAF_SIDE_SPEED_MIN,
			LEAF_SIDE_SPEED_MAX
		)
	- horizontalArrival
		* rng:NextNumber(
			0.2,
			1.0
		)


	local gravity =
		rng:NextNumber(
			LEAF_CUSTOM_GRAVITY_MIN,
			LEAF_CUSTOM_GRAVITY_MAX
		)


	local swayAxis =
		randomHorizontal


	local swayAmplitude =
		rng:NextNumber(
			LEAF_SWAY_AMPLITUDE_MIN,
			LEAF_SWAY_AMPLITUDE_MAX
		)


	local swayFrequency =
		rng:NextNumber(
			LEAF_SWAY_FREQUENCY_MIN,
			LEAF_SWAY_FREQUENCY_MAX
		)


	local swayPhase =
		rng:NextNumber(
			0,
			math.pi * 2
		)


	local rotX =
		rng:NextNumber(
			-4.0,
			4.0
		)

	local rotY =
		rng:NextNumber(
			-5.5,
			5.5
		)

	local rotZ =
		rng:NextNumber(
			-4.5,
			4.5
		)


	local initialRotation =
		Vector3.new(
			rng:NextNumber(
				0,
				math.pi * 2
			),
			rng:NextNumber(
				0,
				math.pi * 2
			),
			rng:NextNumber(
				0,
				math.pi * 2
			)
		)


	local startedAt =
		os.clock()


	local connection: RBXScriptConnection?

	connection =
		RunService.Heartbeat:
		Connect(
			function()

				if not leaf.Parent then

					if connection then

						connection:
						Disconnect()
					end

					return
				end


				local elapsed =
				os.clock()
				- startedAt


				if elapsed >=
					lifetime then

					if connection then

						connection:
						Disconnect()
					end


					leaf:
					Destroy()

					return
				end


				local normalized =
				elapsed
				/ lifetime


				local ballistic =
				startPosition
				+ initialVelocity
				* elapsed
				+ Vector3.new(
					0,
					-0.5
					* gravity
					* elapsed
					* elapsed,
					0
				)


				local sway =
				swayAxis
				* math.sin(
					elapsed
					* swayFrequency
					+ swayPhase
				)
				* swayAmplitude


				local position =
				ballistic
				+ sway


				if normalized >
					0.72 then

					leaf.Transparency =
					math.clamp(
						(
							normalized
							- 0.72
						)
						/ 0.28,
						0,
						1
					)
				end


				leaf.CFrame =
				CFrame.new(
					position
				)
				* CFrame.Angles(
					initialRotation.X
					+ rotX
					* elapsed,
					initialRotation.Y
					+ rotY
					* elapsed,
					initialRotation.Z
					+ rotZ
					* elapsed
				)
			end
		)


	Debris:AddItem(
		leaf,
		lifetime
			+ 0.25
	)
end


local function emitLeavesFromFoliage(
	foliageParts: {BasePart},
	arrivalDirection: Vector3
): number

	local sources =
		getLeafSourceParts(
			foliageParts
		)


	if #sources ==
		0 then

		return 0
	end


	local count =
		rng:NextInteger(
			LEAF_COUNT_MIN,
			LEAF_COUNT_MAX
		)


	for _ = 1,
		count do

		local source =
			sources[
		rng:NextInteger(
			1,
			#sources
		)
		]


		local startPosition =
			randomPointInsidePart(
				source
			)


		local leaf =
			makeLeafPart(
				startPosition,
				chooseLeafBaseColor(
					source
				)
			)


		animateLeaf(
			leaf,
			startPosition,
			arrivalDirection,
			rng:NextNumber(
				LEAF_LIFETIME_MIN,
				LEAF_LIFETIME_MAX
			)
		)
	end


	return count
end


-- ============================================================
-- SAFE FOLIAGE SWAY
-- ============================================================

local function tweenPart(
	part: BasePart,
	info: TweenInfo,
	target: CFrame,
	token: number
): Tween?

	local state =
		activeSways[
	part
	]


	if not state
		or state.token ~=
		token then

		return nil
	end


	local tween =
		TweenService:
		Create(
			part,
			info,
			{
				CFrame =
				target,
			}
		)


	state.tween =
		tween

	tween:
		Play()


	return tween
end


local function swayFoliagePart(
	part: BasePart,
	contactPosition: Vector3,
	arrivalDirection: Vector3
)

	local existing =
		activeSways[
	part
	]


	local baseCFrame =
		if existing
		then existing.baseCFrame
		else part.CFrame


	if existing
		and existing.tween then

		existing.tween:
			Cancel()
	end


	local token =
		(
			existing
			and existing.token
			or 0
		)
		+ 1


	activeSways[
	part
	] = {
		baseCFrame =
			baseCFrame,
		token =
			token,
		tween =
			nil,
	}


	local distance =
		(
			part.Position
			- contactPosition
		).Magnitude


	local falloff =
		1
	- math.clamp(
		distance
			/ FOLIAGE_SEARCH_RADIUS,
		0,
		1
	)


	local strength =
		0.35
		+ falloff
		* 0.65


	local horizontalArrival =
		Vector3.new(
			arrivalDirection.X,
			0,
			arrivalDirection.Z
		)


	if horizontalArrival.Magnitude <=
		0.01 then

		horizontalArrival =
			Vector3.xAxis
	else

		horizontalArrival =
			horizontalArrival.Unit
	end


	local sideways =
		Vector3.new(
			-horizontalArrival.Z,
			0,
			horizontalArrival.X
		)


	local directionSign =
		if rng:NextNumber() <
		0.5
		then -1
		else 1


	local translation =
		sideways
		* directionSign
		* rng:NextNumber(
			SWAY_TRANSLATION_MIN,
			SWAY_TRANSLATION_MAX
		)
		* strength


	local angle =
		math.rad(
			rng:NextNumber(
				SWAY_ANGLE_MIN_DEG,
				SWAY_ANGLE_MAX_DEG
			)
			* strength
			* directionSign
		)


	local impulse =
		(
			baseCFrame
			+ translation
		)
		* CFrame.Angles(
			angle * 0.65,
			0,
			-angle
		)


	local counter =
		(
			baseCFrame
			- translation
			* 0.35
		)
		* CFrame.Angles(
			-angle * 0.20,
			0,
			angle * 0.30
		)


	task.spawn(
		function()

			local first =
				tweenPart(
					part,
					TweenInfo.new(
						SWAY_OUT_TIME,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.Out
					),
					impulse,
					token
				)


			if not first then
				return
			end


			first.Completed:
				Wait()


			local state =
				activeSways[
			part
			]


			if not state
				or state.token ~=
				token then

				return
			end


			local second =
				tweenPart(
					part,
					TweenInfo.new(
						SWAY_COUNTER_TIME,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.InOut
					),
					counter,
					token
				)


			if not second then
				return
			end


			second.Completed:
				Wait()


			state =
				activeSways[
			part
			]


			if not state
				or state.token ~=
				token then

				return
			end


			local final =
				tweenPart(
					part,
					TweenInfo.new(
						SWAY_RETURN_TIME,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.Out
					),
					baseCFrame,
					token
				)


			if not final then
				return
			end


			final.Completed:
				Wait()


			state =
				activeSways[
			part
			]


			if state
				and state.token ==
				token then

				if part.Parent then

					part.CFrame =
						baseCFrame
				end


				activeSways[
				part
				] =
					nil
			end
		end
	)
end


local function swayFoliage(
	foliageParts: {BasePart},
	contactPosition: Vector3,
	arrivalDirection: Vector3
)

	for _, part in ipairs(
		foliageParts
		) do

		if part.Parent
			and part.Anchored
			and not part.CanCollide then

			swayFoliagePart(
				part,
				contactPosition,
				arrivalDirection
			)
		end
	end
end


-- ============================================================
-- ARRIVAL CONFIRMATION
-- ============================================================

local function waitForActualArrival(
	jumpingPlayer: Player,
	character: Model,
	landingPosition: Vector3,
	startPosition: Vector3
): BasePart?

	local travelDistance =
		(
			landingPosition
			- startPosition
		).Magnitude


	local expectedDuration =
		math.clamp(
			travelDistance
			/ TREE_JUMP_SPEED_MIRROR,
			MIN_TRAVEL_TIME,
			MAX_TRAVEL_TIME
		)


	local deadline =
		os.clock()
		+ expectedDuration
		+ ARRIVAL_EXTRA_TIMEOUT


	while os.clock() <
		deadline do

		if jumpingPlayer.Character ~=
			character
			or not character.Parent then

			return nil
		end


		local humanoid =
			character:
			FindFirstChildOfClass(
				"Humanoid"
			)


		local root =
			character:
			FindFirstChild(
				"HumanoidRootPart"
			)


		if not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA(
				"BasePart"
			) then

			return nil
		end


		if (
			root.Position
			- landingPosition
			).Magnitude <=
				ARRIVAL_RADIUS then

			return root
		end


		RunService.Heartbeat:
			Wait()
	end


	return nil
end


-- ============================================================
-- LANDING REACTION
-- ============================================================

local function reactToLanding(
	jumpingPlayer: Player,
	landingPosition: Vector3
)

	if not shouldRenderAt(
		landingPosition
		) then

		return
	end


	local character =
		jumpingPlayer.Character


	if not character then
		return
	end


	local initialRoot =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)


	if not initialRoot
		or not initialRoot:IsA(
			"BasePart"
		) then

		return
	end


	local startPosition =
		initialRoot.Position


	local arrivalDirection =
		landingPosition
	- startPosition


	if arrivalDirection.Magnitude >
		0.01 then

		arrivalDirection =
			arrivalDirection.Unit
	else

		arrivalDirection =
			Vector3.new(
				0,
				0,
				-1
			)
	end


	dbg(
		"REPLICATE received for "
			.. jumpingPlayer.Name
	)


	local arrivedRoot =
		waitForActualArrival(
			jumpingPlayer,
			character,
			landingPosition,
			startPosition
		)


	if not arrivedRoot then

		dbg(
			"FAIL: arrival was not confirmed."
		)

		return
	end


	local branch,
		contactPosition,
		_contactNormal =
		getActualBranchBelowCharacter(
			character,
			arrivedRoot
		)


	if not branch
		or not contactPosition then

		dbg(
			"FAIL: no valid Branch_* directly below HRP."
		)

		character:SetAttribute(
			"TreeReactionLastResult",
			"NoBranchBelow"
		)

		return
	end


	local tree =
		findTreeModelFor(
			branch
		)


	if not tree then

		dbg(
			"FAIL: branch has no tree model under Workspace.Arboles."
		)

		character:SetAttribute(
			"TreeReactionLastResult",
			"NoTreeModel"
		)

		return
	end


	local now =
		os.clock()


	if now
		- (
			lastTreeReactionAt[
			tree
			]
				or -math.huge
		) <
			SAME_TREE_REACTION_COOLDOWN then

		return
	end


	lastTreeReactionAt[
	tree
	] =
		now


	local foliageParts =
		collectFoliageParts(
			tree,
			contactPosition
		)


	local leafCount =
		emitLeavesFromFoliage(
			foliageParts,
			arrivalDirection
		)


	swayFoliage(
		foliageParts,
		contactPosition,
		arrivalDirection
	)


	if leafCount >
		0 then

		character:SetAttribute(
			"TreeReactionLastResult",
			"SuccessFoliageOrigin"
		)

	else

		character:SetAttribute(
			"TreeReactionLastResult",
			"NoSafeFoliage"
		)
	end


	character:SetAttribute(
		"TreeReactionLastLeafCount",
		leafCount
	)

	character:SetAttribute(
		"TreeReactionLastFoliageParts",
		#foliageParts
	)


	dbg(
		"RESULT | branch="
			.. branch.Name
			.. " | foliageParts="
			.. tostring(
				#foliageParts
			)
			.. " | foliageOriginLeaves="
			.. tostring(
				leafCount
			)
	)
end


-- ============================================================
-- EXISTING SERVER REPLICATION
-- ============================================================

replicateEvent.OnClientEvent:
	Connect(
		function(
			jumpingPlayer: Player,
			landingPosition: Vector3
		)

			if typeof(
				jumpingPlayer
				) ~= "Instance"
				or not jumpingPlayer:IsA(
					"Player"
				)
				or typeof(
					landingPosition
				) ~= "Vector3" then

				return
			end


			task.spawn(
				reactToLanding,
				jumpingPlayer,
				landingPosition
			)
		end
	)


print(
	"[TreeJumpTreeReaction] READY v1.3"
		.. " | LeavesOrigin=FOLIAGE"
		.. " | BranchOriginLeaves=OFF"
		.. " | SafeFoliageSway=ON"
)
