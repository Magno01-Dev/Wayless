--!strict
-- WeaponPoseController v3 - R6 Two-Handed Visual QA Stance
-- StarterPlayer > StarterPlayerScripts > WeaponPoseController [LocalScript]
--
-- IMPORTANT:
-- This controller is VISUAL ONLY.
-- It does not listen to Mouse1 and does not send WeaponAttackRequest.
--
-- Why:
-- WAYLESS already has AttackController + CombatServer handling M1.
-- The previous weapon controller was also listening to Mouse1, which caused
-- both weapon damage and unarmed M1 damage to fire from the same click.
--
-- v3 scope:
-- - Keep the temporary R6 two-handed stance for visual/balance testing.
-- - Put the RIGHT hand in front of the torso using a world-space arm solver.
-- - Make LEFT hand follow OffhandGripAttachment only when that attachment
--   is actually in front of the torso and within a sane reach.
-- - Fall back to a safe front-hand target instead of sending arms behind.
--
-- Final authored weapon animations can replace this later.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local RunService =
	game:GetService(
		"RunService"
	)

local player =
	Players.LocalPlayer

local WeaponCatalog =
	require(
		ReplicatedStorage:
		WaitForChild(
			"WeaponCatalog"
		)
	)

local simulationConnection: RBXScriptConnection? =
	nil

local currentRight =
	CFrame.identity

local currentLeft =
	CFrame.identity

---------------------------------------------------------------------
-- TUNING
---------------------------------------------------------------------

-- R6 torso-local targets.
-- Roblox forward is local -Z.
local RIGHT_HAND_TARGET =
	Vector3.new(
		0.28,
		-0.08,
		-1.18
	)

local LEFT_HAND_FALLBACK_TARGET =
	Vector3.new(
		-0.08,
		-0.12,
		-1.10
	)

local MAX_OFFHAND_DISTANCE_FROM_TORSO =
	2.8

local MIN_FRONT_Z =
	-0.10

local POSE_BLEND_SPEED =
	22

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function findMotor(
	torso: BasePart,
	name: string
): Motor6D?

	local motor =
		torso:
		FindFirstChild(
			name
		)

	if motor
		and motor:IsA(
			"Motor6D"
		) then

		return motor
	end

	return nil
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

local function getWeaponVisual(
	character: Model
): Model?

	local folder =
		character:
		FindFirstChild(
			"WAYLESS_EquipmentVisuals"
		)

	if not folder then
		return nil
	end

	local visual =
		folder:
		FindFirstChild(
			"WeaponVisual"
		)

	if visual
		and visual:IsA(
			"Model"
		) then

		return visual
	end

	return nil
end

local function getDefinition(
	character: Model
): any?

	local weaponId =
		character:GetAttribute(
			"EquippedWeaponId"
		)

	if typeof(weaponId) ~= "string"
		or weaponId == "" then

		return nil
	end

	return WeaponCatalog.Get(
		weaponId
	)
end

local function expBlendAlpha(
	speed: number,
	dt: number
): number

	return 1
	- math.exp(
		-speed * dt
	)
end

local function canPose(
	character: Model
): boolean

	if player.Character
		~= character
		or not character.Parent then

		return false
	end

	if character:GetAttribute(
		"WeaponState"
		) ~= "Drawn" then

		return false
	end

	if character:GetAttribute(
		"CombatMode"
		) ~= true then

		return false
	end

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

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	return humanoid ~= nil
		and humanoid.Health > 0
end

---------------------------------------------------------------------
-- R6 WORLD-SPACE ARM SOLVER
---------------------------------------------------------------------

local function solveArmTransformToHandTarget(
	torso: BasePart,
	shoulder: Motor6D,
	arm: BasePart,
	targetWorldPosition: Vector3
): CFrame

	local shoulderWorldCFrame =
		torso.CFrame
		* shoulder.C0

	local shoulderWorldPosition =
		shoulderWorldCFrame.Position

	local displacement =
		targetWorldPosition
	- shoulderWorldPosition

	if displacement.Magnitude
		< 0.05 then

		return CFrame.identity
	end

	local handDirection =
		displacement.Unit

	-- R6 arm extends from shoulder toward local -Y.
	-- So desired local +Y points back toward the shoulder.
	local desiredUp =
		-handDirection

	local referenceRight =
		torso.CFrame.RightVector

	local desiredRight =
		referenceRight
	- desiredUp
		* referenceRight:Dot(
			desiredUp
		)

	if desiredRight.Magnitude
		< 0.05 then

		desiredRight =
			torso.CFrame.LookVector:
			Cross(
				desiredUp
			)
	end

	if desiredRight.Magnitude
		< 0.05 then

		desiredRight =
			Vector3.xAxis
	end

	desiredRight =
		desiredRight.Unit

	local desiredBack =
		desiredRight:
		Cross(
			desiredUp
		)

	if desiredBack.Magnitude
		< 0.05 then

		desiredBack =
			torso.CFrame.LookVector
	end

	desiredBack =
		desiredBack.Unit

	desiredRight =
		desiredUp:
		Cross(
			desiredBack
		).Unit

	local armLength =
		arm.Size.Y

	local desiredArmCenter =
		shoulderWorldPosition
		+ handDirection
		* (
			armLength
			* 0.5
		)

	local desiredArmCFrame =
		CFrame.fromMatrix(
			desiredArmCenter,
			desiredRight,
			desiredUp,
			desiredBack
		)

	-- Motor6D:
	-- Part0.CFrame * C0 * Transform = Part1.CFrame * C1
	return shoulder.C0:
		Inverse()
		* torso.CFrame:
		Inverse()
		* desiredArmCFrame
		* shoulder.C1
end

local function getSafeLeftHandTarget(
	character: Model,
	torso: BasePart,
	definition: any
): Vector3

	local fallback =
		torso.CFrame:
		PointToWorldSpace(
			LEFT_HAND_FALLBACK_TARGET
		)

	local visual =
		getWeaponVisual(
			character
		)

	if not visual then
		return fallback
	end

	local visualConfig =
		definition.Visual
		or {}

	local offhandName =
		if typeof(
			visualConfig.OffhandGripAttachmentName
		) == "string"
		then visualConfig.OffhandGripAttachmentName
		else "OffhandGripAttachment"

	local offhand =
		findAttachmentDeep(
			visual,
			offhandName
		)

	if not offhand then
		return fallback
	end

	local localPosition =
		torso.CFrame:
		PointToObjectSpace(
			offhand.WorldPosition
		)

	-- Positive Z is behind the R6 torso. Never chase a bad attachment
	-- behind the character during this temporary QA stance.
	if localPosition.Z
		> MIN_FRONT_Z then

		return fallback
	end

	if (
		offhand.WorldPosition
		- torso.Position
		).Magnitude
			> MAX_OFFHAND_DISTANCE_FROM_TORSO then

		return fallback
	end

	return offhand.WorldPosition
end

---------------------------------------------------------------------
-- POSE
---------------------------------------------------------------------

local function runPose(
	character: Model,
	dt: number
)

	local torso =
		character:
		FindFirstChild(
			"Torso"
		)

	local rightArm =
		character:
		FindFirstChild(
			"Right Arm"
		)

	local leftArm =
		character:
		FindFirstChild(
			"Left Arm"
		)

	if not torso
		or not torso:IsA(
			"BasePart"
		)
			or not rightArm
			or not rightArm:IsA(
				"BasePart"
			)
			or not leftArm
			or not leftArm:IsA(
				"BasePart"
			) then

		return
	end

	local rightShoulder =
		findMotor(
			torso,
			"Right Shoulder"
		)

	local leftShoulder =
		findMotor(
			torso,
			"Left Shoulder"
		)

	if not rightShoulder
		or not leftShoulder then

		return
	end

	if not canPose(
		character
		) then

		currentRight =
			CFrame.identity

		currentLeft =
			CFrame.identity

		return
	end

	local definition =
		getDefinition(
			character
		)

	if not definition
		or typeof(
			definition.Pose
		) ~= "table"
			or definition.Pose.GripStyle
			~= "TwoHanded" then

		return
	end

	local blendSpeed =
		if typeof(
			definition.Pose.R6PoseBlendSpeed
		) == "number"
		then math.max(
			1,
			definition.Pose.R6PoseBlendSpeed
		)
		else POSE_BLEND_SPEED

	local alpha =
		expBlendAlpha(
			blendSpeed,
			dt
		)

	local rightTarget =
		torso.CFrame:
		PointToWorldSpace(
			RIGHT_HAND_TARGET
		)

	local rightTransform =
		solveArmTransformToHandTarget(
			torso,
			rightShoulder,
			rightArm,
			rightTarget
		)

	currentRight =
		currentRight:
		Lerp(
			rightTransform,
			alpha
		)

	rightShoulder.Transform =
		currentRight

	local leftTarget =
		getSafeLeftHandTarget(
			character,
			torso,
			definition
		)

	local leftTransform =
		solveArmTransformToHandTarget(
			torso,
			leftShoulder,
			leftArm,
			leftTarget
		)

	currentLeft =
		currentLeft:
		Lerp(
			leftTransform,
			alpha
		)

	leftShoulder.Transform =
		currentLeft
end

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local function bindCharacter(
	character: Model
)

	if simulationConnection then

		simulationConnection:
			Disconnect()

		simulationConnection =
			nil
	end

	currentRight =
		CFrame.identity

	currentLeft =
		CFrame.identity

	local humanoid =
		character:
		WaitForChild(
			"Humanoid"
		) :: Humanoid

	if humanoid.RigType
		~= Enum.HumanoidRigType.R6 then

		warn(
			"[WeaponPoseController] v3 procedural two-hand pose is R6 QA only"
		)

		return
	end

	simulationConnection =
		RunService.PreSimulation:
		Connect(
			function(
				dt: number
			)

				if player.Character
					== character
					and character.Parent then

					runPose(
						character,
						dt
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
	"[WeaponPoseController] READY v3"
		.. " | VisualOnly=ON"
		.. " | R6FrontTwoHandedQA=ON"
		.. " | DuplicateM1Input=OFF"
)
