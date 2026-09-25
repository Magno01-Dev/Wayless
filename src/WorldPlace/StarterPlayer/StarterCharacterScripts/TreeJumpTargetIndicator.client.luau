--!strict
-- TreeJumpTargetIndicator v4 - PNG + Fast Fade + Smooth Spin/Pulse
--
-- StarterPlayer > StarterCharacterScripts > TreeJumpTargetIndicator
--
-- IMPORTANT:
-- This script is VISUAL ONLY.
-- It does not modify TreeJumpController, camera, character CFrame,
-- Humanoid state, AutoRotate, movement, animations, sounds, FOV, DOF,
-- Tree Jump physics, or server state.
--
-- It mirrors the target rules from the current TreeJumpController:
--   1) tree under cursor
--   2) direct branch under cursor has priority
--   3) otherwise closest valid branch to cursor
--   4) otherwise closest valid branch in 3D
--   5) current standing branch excluded
--   6) range + camera visibility + clear travel path required
--
-- Performance:
-- - branch lists are cached per tree
-- - visibility raycasts are only done in score order until a winner is found
-- - scans at 12 Hz instead of RenderStepped/Heartbeat every frame
-- - fades only use TweenService when visibility changes

local Players =
	game:GetService("Players")

local UserInputService =
	game:GetService("UserInputService")

local TweenService =
	game:GetService("TweenService")

local RunService =
	game:GetService("RunService")


-- =========================
-- CHARACTER
-- =========================

local player =
	Players.LocalPlayer

local character =
	script.Parent

local humanoid =
	character:WaitForChild(
		"Humanoid"
	)

local rootPart =
	character:WaitForChild(
		"HumanoidRootPart"
	)

local playerGui =
	player:WaitForChild(
		"PlayerGui"
	)


-- =========================
-- TREE REFERENCES
-- =========================

local TREE_FOLDER =
	workspace:WaitForChild(
		"Arboles"
	)


-- =========================
-- SAME TARGET VALUES AS TREE JUMP
-- =========================

local TREE_JUMP_KEY =
	Enum.KeyCode.LeftAlt

local TREE_JUMP_COOLDOWN =
	0.15

local MAX_DISTANCE =
	250

local MIN_DISTANCE =
	4

local SAME_BRANCH_THRESHOLD =
	5

local CURSOR_SCREEN_TOLERANCE =
	300

local EXTERNAL_BLOCK_TOLERANCE =
	5

local TREE_JUMP_DISTANCE_OFFSET =
	3

local CURRENT_BRANCH_RAY_DISTANCE =
	6


local BRANCH_NAMES = {
	Branch_EA = true,
	Branch_NE = true,
	Branch_SW = true,
	Branch_WE = true,
}


-- =========================
-- INDICATOR VISUALS
-- =========================

local SCAN_HZ =
	12

local SCAN_INTERVAL =
	1 / SCAN_HZ

local INDICATOR_SIZE =
	52

-- IMPORTANT:
-- Upload TreeJumpIndicator_white.png to Roblox and paste its image asset id
-- below, for example:
-- "rbxassetid://1234567890"
local INDICATOR_IMAGE =
	"rbxassetid://114427377405514"

local INDICATOR_IMAGE_TRANSPARENCY =
	0.20

-- Very quick acquire fade so the marker feels responsive when the cursor
-- enters a valid tree/branch.
local FADE_IN_TIME =
	0.045

local FADE_OUT_TIME =
	0.10

local SURFACE_OFFSET =
	0.16

local ROTATION_SPEED =
	125

-- Subtle breathing pulse while the target remains valid.
local PULSE_SPEED =
	2.25

local PULSE_AMOUNT =
	0.055

-- Small acquire "pop" before settling into the pulse.
local ACQUIRE_START_SCALE =
	0.88

local ACQUIRE_POP_TIME =
	0.07


-- =========================
-- GUI
-- =========================

local billboard =
	Instance.new(
		"BillboardGui"
	)

billboard.Name =
	"TreeJumpTargetIndicator"

billboard.Size =
	UDim2.fromOffset(
		INDICATOR_SIZE,
		INDICATOR_SIZE
	)

billboard.AlwaysOnTop =
	true

billboard.MaxDistance =
	MAX_DISTANCE + 25

billboard.Enabled =
	false

billboard.Parent =
	playerGui


local ring =
	Instance.new(
		"ImageLabel"
	)

ring.Name =
	"Ring"

ring.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

ring.Position =
	UDim2.fromScale(
		0.5,
		0.5
	)

ring.Size =
	UDim2.fromScale(
		1,
		1
	)

ring.BackgroundTransparency =
	1

ring.BorderSizePixel =
	0

ring.Image =
	INDICATOR_IMAGE

ring.ImageColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

ring.ImageTransparency =
	1

ring.ScaleType =
	Enum.ScaleType.Fit

ring.Parent =
	billboard


local ringScale =
	Instance.new(
		"UIScale"
	)

ringScale.Name =
	"PulseScale"

ringScale.Scale =
	1

ringScale.Parent =
	ring


-- =========================
-- STATE
-- =========================

local mouse =
	player:GetMouse()

local currentBranch: BasePart? =
	nil

local currentTween: Tween? =
	nil

local spinConnection: RBXScriptConnection? =
	nil

local pulseTime =
	0

local currentPopTween: Tween? =
	nil

local visualGeneration =
	0

local indicatorLastUse =
	-math.huge

-- v4.1: explicit fade state fixes same-branch reacquire.
local targetFadeOutActive =
	false


-- Cache static branch collections instead of GetDescendants() every scan.
local branchCache: { [Instance]: { BasePart } } =
	setmetatable(
		{},
		{
			__mode = "k",
		}
	)


-- Shared raycast params.
local excludeCharacterParams =
	RaycastParams.new()

excludeCharacterParams.FilterType =
	Enum.RaycastFilterType.Exclude

excludeCharacterParams.FilterDescendantsInstances = {
	character,
}


-- =========================
-- TREE HELPERS
-- =========================

local function isInsideArboles(
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

	local current =
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


local function getBranches(
	treeModel: Instance
): { BasePart }

	local cached =
		branchCache[
	treeModel
	]

	if cached then

		return cached

	end


	local result: { BasePart } =
		{}

	for _, descendant in ipairs(
		treeModel:GetDescendants()
		) do

		if descendant:IsA(
			"BasePart"
			)
				and BRANCH_NAMES[
			descendant.Name
			] then

			table.insert(
				result,
				descendant
			)

		end

	end


	branchCache[
	treeModel
	] =
		result

	return result

end


local function getCurrentStandingBranch(): BasePart?

	local castDirection: Vector3


	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		local surfaceNormal =
			character:GetAttribute(
				"SurfaceNormal"
			)

		if typeof(
			surfaceNormal
			) ~= "Vector3"
				or surfaceNormal.Magnitude <
				0.5 then

			return nil

		end

		castDirection =
			-surfaceNormal.Unit
			* CURRENT_BRANCH_RAY_DISTANCE

	else

		if humanoid.FloorMaterial ==
			Enum.Material.Air then

			return nil

		end

		castDirection =
			Vector3.new(
				0,
				-CURRENT_BRANCH_RAY_DISTANCE,
				0
			)

	end


	local hit =
		workspace:Raycast(
			rootPart.Position,
			castDirection,
			excludeCharacterParams
		)

	if not hit
		or not hit.Instance
		or not hit.Instance:IsA(
			"BasePart"
		) then

		return nil

	end


	local part =
		hit.Instance


	if not BRANCH_NAMES[
		part.Name
		] then

		return nil

	end


	if not isInsideArboles(
		part
		) then

		return nil

	end


	return part

end


local function findTreeUnderCursor(): Instance?

	local camera =
		workspace.CurrentCamera

	if not camera then

		return nil

	end


	local target =
		mouse.Target

	if target
		and target:IsA(
			"BasePart"
		)
			and isInsideArboles(
				target
			) then

		return findTreeModelFor(
			target
		)

	end


	local mouseLocation =
		UserInputService:
		GetMouseLocation()


	local ray =
		camera:
		ScreenPointToRay(
			mouseLocation.X,
			mouseLocation.Y
		)


	local hit =
		workspace:Raycast(
			ray.Origin,
			ray.Direction * 500,
			excludeCharacterParams
		)


	if hit
		and hit.Instance
		and hit.Instance:IsA(
			"BasePart"
		)
			and isInsideArboles(
				hit.Instance
			) then

		return findTreeModelFor(
			hit.Instance
		)

	end


	return nil

end


local function isBranchVisibleFromCamera(
	branch: BasePart,
	camera: Camera
): boolean

	local origin =
		camera.CFrame.Position

	local direction =
		branch.Position -
		origin

	local distance =
		direction.Magnitude


	if distance <
		0.1 then

		return true

	end


	local hit =
		workspace:Raycast(
			origin,
			direction.Unit * distance,
			excludeCharacterParams
		)


	if not hit then

		return true

	end


	return hit.Instance ==
		branch
		or hit.Instance:
		IsDescendantOf(
			branch
		)

end


local function isDistanceValid(
	branch: BasePart,
	standingBranch: BasePart?
): (boolean, number)

	if branch ==
		standingBranch then

		return false,
			math.huge

	end


	local distance =
		(
			branch.Position -
			rootPart.Position
		).Magnitude


	if distance <
		MIN_DISTANCE
		or distance >
		MAX_DISTANCE
			or distance <=
			SAME_BRANCH_THRESHOLD then

		return false,
			distance

	end


	return true,
		distance

end


-- =========================
-- OPTIMIZED EXACT TARGET PICK
-- =========================

type Candidate = {
	branch: BasePart,
	score: number,
	distance: number,
}


local function pickBestBranch(
	treeModel: Instance
): BasePart?

	local camera =
		workspace.CurrentCamera

	if not camera then

		return nil

	end


	local branches =
		getBranches(
			treeModel
		)

	if #branches ==
		0 then

		return nil

	end


	local standingBranch =
		getCurrentStandingBranch()


	-- Priority 1:
	-- exact branch directly under cursor.
	local directTarget =
		mouse.Target

	if directTarget
		and directTarget:IsA(
			"BasePart"
		)
			and BRANCH_NAMES[
		directTarget.Name
		]
			and findTreeModelFor(
				directTarget
			) ==
			treeModel then

		local valid =
			isDistanceValid(
				directTarget,
				standingBranch
			)

		if valid
			and isBranchVisibleFromCamera(
				directTarget,
				camera
			) then

			return directTarget

		end

	end


	local mousePosition =
		Vector2.new(
			mouse.X,
			mouse.Y
		)


	local screenCandidates: { Candidate } =
		{}

	local distanceCandidates: { Candidate } =
		{}


	for _, branch in ipairs(
		branches
		) do

		if branch.Parent then

			local valid,
				distance =
				isDistanceValid(
					branch,
					standingBranch
				)

			if valid then

				table.insert(
					distanceCandidates,
					{
						branch = branch,
						score = distance,
						distance = distance,
					}
				)


				local screenPosition,
					onScreen =
					camera:
					WorldToViewportPoint(
						branch.Position
					)


				if onScreen
					and screenPosition.Z >
					0 then

					local dx =
						screenPosition.X -
						mousePosition.X

					local dy =
						screenPosition.Y -
						mousePosition.Y

					local score =
						(dx * dx)
						+
						(dy * dy)


					table.insert(
						screenCandidates,
						{
							branch = branch,
							score = score,
							distance = distance,
						}
					)

				end

			end

		end

	end


	-- Sort first, raycast visibility second.
	-- This returns the same nearest VISIBLE candidate while avoiding
	-- one visibility raycast for every branch.
	table.sort(
		screenCandidates,
		function(
			a,
			b
		)

			return a.score <
				b.score

		end
	)


	local maxScreenScore =
		CURSOR_SCREEN_TOLERANCE
		* CURSOR_SCREEN_TOLERANCE


	for _, candidate in ipairs(
		screenCandidates
		) do

		if candidate.score >
			maxScreenScore then

			break

		end


		if isBranchVisibleFromCamera(
			candidate.branch,
			camera
			) then

			return candidate.branch

		end

	end


	-- Priority 3: nearest visible branch in world space.
	table.sort(
		distanceCandidates,
		function(
			a,
			b
		)

			return a.distance <
				b.distance

		end
	)


	for _, candidate in ipairs(
		distanceCandidates
		) do

		if isBranchVisibleFromCamera(
			candidate.branch,
			camera
			) then

			return candidate.branch

		end

	end


	return nil

end


-- =========================
-- SAME LANDING / PATH RULE
-- =========================

local function computeLandingPosition(
	branch: BasePart
): Vector3

	local rootPos =
		rootPart.Position

	local branchPos =
		branch.Position

	local branchTopY =
		branchPos.Y
		+
		(
			branch.Size.Y /
			2
		)

	local characterHeight =
		(
			rootPart.Size.Y /
			2
		)
		+
		humanoid.HipHeight
		+
		1.5


	local horizontal =
		Vector3.new(
			branchPos.X -
			rootPos.X,
			0,
			branchPos.Z -
			rootPos.Z
		)


	if horizontal.Magnitude >
		0.001 then

		horizontal =
			horizontal.Unit
			*
			TREE_JUMP_DISTANCE_OFFSET

	else

		horizontal =
			Vector3.zero

	end


	return Vector3.new(
		branchPos.X -
			horizontal.X,
		branchTopY +
			characterHeight,
		branchPos.Z -
			horizontal.Z
	)

end


local function hasClearDashPath(
	branch: BasePart
): boolean

	local targetPosition =
		computeLandingPosition(
			branch
		)

	local origin =
		rootPart.Position

	local direction =
		targetPosition -
		origin

	local distance =
		direction.Magnitude


	if distance <
		0.1 then

		return false

	end


	local hit =
		workspace:Raycast(
			origin,
			direction.Unit * distance,
			excludeCharacterParams
		)


	if not hit then

		return true

	end


	if (
		hit.Position -
			targetPosition
		).Magnitude <=
			EXTERNAL_BLOCK_TOLERANCE then

		return true

	end


	return hit.Instance ==
		branch
		or hit.Instance:
		IsDescendantOf(
			branch
		)

end


-- =========================
-- AVAILABILITY
-- =========================

local function canDisplayTarget(): boolean

	if humanoid.Health <=
		0 then

		return false

	end


	if UserInputService:
		GetFocusedTextBox() then

		return false

	end


	if character:GetAttribute(
		"IsDashing"
		) == true then

		return false

	end


	-- Mirror the current TreeJumpController availability exactly.
	if character:GetAttribute(
		"IsTreeJumping"
		) == true
			or character:GetAttribute(
				"TreeJumpActive"
			) == true then

		return false

	end


	if time() -
		indicatorLastUse <
		TREE_JUMP_COOLDOWN then

		return false

	end


	return true

end


local function findAvailableTarget(): BasePart?

	if not canDisplayTarget() then

		return nil

	end


	local treeModel =
		findTreeUnderCursor()

	if not treeModel then

		return nil

	end


	local branch =
		pickBestBranch(
			treeModel
		)

	if not branch then

		return nil

	end


	if not hasClearDashPath(
		branch
		) then

		return nil

	end


	return branch

end


-- =========================
-- VISUAL TRANSITIONS
-- =========================

local function cancelVisualTween()

	if currentTween then

		currentTween:Cancel()

		currentTween =
			nil

	end

	if currentPopTween then

		currentPopTween:Cancel()

		currentPopTween =
			nil

	end

end


local function stopSpin()

	if spinConnection then

		spinConnection:Disconnect()

		spinConnection =
			nil

	end

	pulseTime =
		0

	ringScale.Scale =
		1

end


local function startSpin()

	if spinConnection then

		return

	end

	pulseTime =
		0

	spinConnection =
		RunService.RenderStepped:Connect(
			function(dt)

				ring.Rotation +=
				ROTATION_SPEED * dt

				if ring.Rotation >=
					360 then

					ring.Rotation -=
					360

				end


				pulseTime +=
				dt * PULSE_SPEED * math.pi * 2

				local pulse =
				math.sin(
					pulseTime
				)

				ringScale.Scale =
				1
				+
				(
					pulse
					*
					PULSE_AMOUNT
				)

			end
		)

end


local function updateBillboardOffset(
	branch: BasePart
)

	local localTopPoint =
		Vector3.new(
			0,
			(
				branch.Size.Y /
				2
			)
			+
			SURFACE_OFFSET,
			0
		)


	local worldTopPoint =
		branch.CFrame:
		PointToWorldSpace(
			localTopPoint
		)


	billboard.StudsOffsetWorldSpace =
		worldTopPoint -
		branch.Position

end


local function showTarget(
	branch: BasePart
)

	visualGeneration +=
		1


	local changedTarget =
		currentBranch ~=
		branch

	local wasHidden =
		not billboard.Enabled

	local wasFadingOut =
		targetFadeOutActive

	targetFadeOutActive =
		false


	if changedTarget then

		currentBranch =
			branch

		billboard.Adornee =
			branch

		updateBillboardOffset(
			branch
		)

	end


	billboard.Enabled =
		true

	startSpin()


	-- Only replay the acquire fade/pop when the indicator first appears or
	-- switches to another valid branch. Keeping the same target should not
	-- restart the animation every 12 Hz scan.
	if wasHidden
		or changedTarget
		or wasFadingOut then

		cancelVisualTween()


		ring.ImageTransparency =
			1

		ringScale.Scale =
			ACQUIRE_START_SCALE


		currentTween =
			TweenService:Create(
				ring,
				TweenInfo.new(
					FADE_IN_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					ImageTransparency =
					INDICATOR_IMAGE_TRANSPARENCY,
				}
			)


		currentPopTween =
			TweenService:Create(
				ringScale,
				TweenInfo.new(
					ACQUIRE_POP_TIME,
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				),
				{
					Scale =
					1,
				}
			)


		currentTween:Play()
		currentPopTween:Play()

	end

end


local function hideTarget()

	if targetFadeOutActive then

		return

	end


	if not billboard.Enabled
		and not currentBranch then

		return

	end


	targetFadeOutActive =
		true


	visualGeneration +=
		1

	local generation =
		visualGeneration


	cancelVisualTween()


	stopSpin()


	currentTween =
		TweenService:Create(
			ring,
			TweenInfo.new(
				FADE_OUT_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				ImageTransparency =
				1,
			}
		)


	currentTween:Play()


	task.delay(
		FADE_OUT_TIME,
		function()

			if generation ~=
				visualGeneration then

				return

			end


			targetFadeOutActive =
				false

			billboard.Enabled =
				false

			billboard.Adornee =
				nil

			ring.Rotation =
				0

			ringScale.Scale =
				1

			currentBranch =
				nil

		end
	)

end


-- =========================
-- INPUT COOLDOWN MIRROR
-- =========================

UserInputService.InputBegan:Connect(
	function(
		input,
		gameProcessed
	)

		if gameProcessed then

			return

		end


		if input.KeyCode ==
			TREE_JUMP_KEY
			and currentBranch then

			indicatorLastUse =
				time()

		end

	end
)


-- =========================
-- LOW-FREQUENCY SCAN LOOP
-- =========================

task.spawn(
	function()

		while character.Parent
			and humanoid.Health >
			0 do

			local target =
				findAvailableTarget()


			if target then

				showTarget(
					target
				)

			else

				hideTarget()

			end


			task.wait(
				SCAN_INTERVAL
			)

		end


		hideTarget()

	end
)


humanoid.Died:Connect(
	function()

		stopSpin()
		hideTarget()

	end
)
