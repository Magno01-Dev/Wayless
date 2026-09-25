--!strict
-- ChakraChargeController v5.3 - Chakra Suppression Integration + Multiplayer Charge VFX
-- Chakra Charge + Body VFX + Rotation Lock + Sound + Max Chakra Camera Shake
-- ElDiabloLocoStudios / Roblox
--
-- LOCATION:
-- StarterPlayer > StarterPlayerScripts > ChakraChargeController
--
-- INPUT:
-- Double C = Chakra Feet
-- Hold C   = Chakra Charge
--
-- VFX:
-- ReplicatedStorage
-- +-- ChakraRemotes
--     +-- ChakraChargeVFXAssets
--         +-- Head
--         +-- Torso
--         +-- LeftArm
--         +-- RightArm
--         +-- LeftLeg
--         +-- RightLeg
--
-- SOUND:
-- 111262226714062
--
-- IMPORTANT:
-- Chakra reaching maximum does NOT stop the animation.
--
-- Animation/VFX/Sound stop ONLY when C is released.
--
-- When Chakra reaches maximum:
-- -> Camera shake triggers once.


-- =========================================================
-- SERVICES
-- =========================================================

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local UserInputService =
	game:GetService("UserInputService")

local ContextActionService =
	game:GetService("ContextActionService")

local RunService =
	game:GetService("RunService")

local SoundService =
	game:GetService("SoundService")


-- =========================================================
-- PLAYER
-- =========================================================

local player =
	Players.LocalPlayer


-- =========================================================
-- CAMERA
-- =========================================================

local camera =
	workspace.CurrentCamera


workspace:GetPropertyChangedSignal(
	"CurrentCamera"
):Connect(
	function()

		camera =
			workspace.CurrentCamera

	end
)


-- =========================================================
-- CONFIG
-- =========================================================

local ChakraConfig =
	require(
		ReplicatedStorage:
		WaitForChild("ChakraConfig")
	)


-- =========================================================
-- REMOTES
-- =========================================================

local chakraRemotes =
	ReplicatedStorage:
	WaitForChild("ChakraRemotes")


local chargeRequest:
	RemoteFunction? =
	nil


local possibleRemoteNames = {
	"ChakraChargeRequest",
	"ChakraChargeVFX",
}


for _, remoteName in ipairs(
	possibleRemoteNames
	) do

	local candidate =
		chakraRemotes:
		FindFirstChild(
			remoteName
		)


	if candidate
		and candidate:IsA(
			"RemoteFunction"
		) then

		chargeRequest =
			candidate

		print(
			"[ChakraChargeController] Charge Remote = "
				.. candidate:GetFullName()
		)

		break

	end

end


if not chargeRequest then

	error(
		"[ChakraChargeController] "
			.. "No Charge RemoteFunction found."
	)

end


local chargeVisualStateEvent =
	chakraRemotes:
	WaitForChild(
		"ChakraChargeVisualState"
	) :: RemoteEvent


local function setReplicatedChargeVisual(
	active: boolean
)

	chargeVisualStateEvent:
		FireServer(
			active
		)

end


-- =========================================================
-- INPUT
-- =========================================================

local CHARGE_KEY =
	Enum.KeyCode[
ChakraConfig.Charge.KeyCodeName
]
	or Enum.KeyCode.C


local HOLD_THRESHOLD =
	ChakraConfig.Charge.HoldThreshold
	or 0.28


-- =========================================================
-- RETRY
-- =========================================================

local START_RETRY_INTERVAL =
	0.10


-- =========================================================
-- ANIMATION
-- =========================================================

local CHARGE_ANIMATION_ID =
	"rbxassetid://92669274206041"


local CHARGE_START_MARKER =
	"ChargeStart"


local CHARGE_ANIMATION_SPEED =
	1.0


local LOOP_CHARGE_SECTION_FROM_MARKER =
	true


local CHARGE_LOOP_END_EPSILON =
	0.035


local CHARGE_LOOP_RESTART_OFFSET =
	0.015


-- =========================================================
-- SOUND
-- =========================================================

local CHARGE_SOUND_ID =
	"rbxassetid://111262226714062"


local CHARGE_SOUND_VOLUME =
	1


local CHARGE_SOUND_LOOPED =
	true


-- 3D attenuation for the owning player's local sound.
-- Other players receive the same spatial sound from
-- ChakraChargeVFXMultiplayerClient.
local CHARGE_SOUND_MIN_DISTANCE =
	8

local CHARGE_SOUND_MAX_DISTANCE =
	70


local chargeSound:
	Sound? =
	nil


-- =========================================================
-- CAMERA SHAKE CONFIG
-- =========================================================

local MAX_CHAKRA_SHAKE_DURATION =
	0.65


local MAX_CHAKRA_SHAKE_POSITION =
	0.16


local MAX_CHAKRA_SHAKE_ROTATION =
	math.rad(3.5)


local MAX_CHAKRA_SHAKE_FREQUENCY =
	28


local cameraShakeActive =
	false


local cameraShakeStartTime =
	0


local cameraShakeSeed =
	math.random(
		1,
		1000000
	)


local maxChakraShakeTriggered =
	false


-- =========================================================
-- CHAKRA VALUE NAMES
-- =========================================================

local CHAKRA_VALUE_NAMES = {

	"Chakra",

	"CurrentChakra",

	"ChakraValue",

	"ChakraAmount",

	"CurrentChakraAmount",

}


local MAX_CHAKRA_VALUE_NAMES = {

	"MaxChakra",

	"ChakraMax",

	"MaxChakraValue",

	"MaxChakraAmount",

	"MaximumChakra",

}


-- =========================================================
-- INPUT LOCK
-- =========================================================

local LOCK_ACTION =
	"DiabloChakraChargeInputLock"


local blockedInputs = {

	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,

	Enum.KeyCode.Space,

	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift,

	Enum.KeyCode.Q,
	Enum.KeyCode.E,
	Enum.KeyCode.F,
	Enum.KeyCode.G,
	Enum.KeyCode.X,
	Enum.KeyCode.R,
	Enum.KeyCode.V,
	Enum.KeyCode.B,
	Enum.KeyCode.N,

	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.MouseButton2,

}


local TRANSIENT_RETRY_REASONS: {
	[string]: boolean
} = {

	MovingTooFast = true,

	MustBeGroundedOrChakraFeet = true,

	StateUnavailable = true,

	CharacterMismatch = true,

	CharacterUnavailable = true,

}


-- =========================================================
-- VFX
-- =========================================================

local VFX_FOLDER_NAME =
	"ChakraChargeVFXAssets"


local activeVFXObjects:
	{Instance} =
	{}


-- =========================================================
-- CHARACTER
-- =========================================================

local character:
	Model? =
	nil


local humanoid:
	Humanoid? =
	nil


local animator:
	Animator? =
	nil


local chargeTrack:
	AnimationTrack? =
	nil


-- =========================================================
-- CONNECTIONS
-- =========================================================

local chargeMarkerConnection:
	RBXScriptConnection? =
	nil


local chargeAttributeConnection:
	RBXScriptConnection? =
	nil


local statusGateConnections:
	{RBXScriptConnection} =
	{}


-- =========================================================
-- CHARGE STATE
-- =========================================================

local charging =
	false


local chargeAnimationActive =
	false


local chargeAnimationSequence =
	0


local chargeMarkerReachedSequence =
	-1


local chargeLoopStartTime:
	number? =
	nil


local chargeKeyDown =
	false


local holdMatured =
	false


local holdSequence =
	0


local startRequestInFlight =
	false


local stopRequestInFlight =
	false


local startRetryScheduled =
	false


-- =========================================================
-- ROTATION LOCK
-- =========================================================

local rotationLocked =
	false


local previousAutoRotate =
	true


local lockedRootPart:
	BasePart? =
	nil


local rotationAttachment:
	Attachment? =
	nil


local rotationAlign:
	AlignOrientation? =
	nil


-- =========================================================
-- INPUT LOCK
-- =========================================================

local function sinkAction():
	Enum.ContextActionResult

	return Enum.ContextActionResult.Sink

end


local function applyInputLock(
	active: boolean
)

	if active then

		ContextActionService:
			BindActionAtPriority(
				LOCK_ACTION,
				sinkAction,
				false,
				Enum.ContextActionPriority.High.Value
				+ 100,
				table.unpack(
					blockedInputs
				)
			)

	else

		ContextActionService:
			UnbindAction(
				LOCK_ACTION
			)

	end

end


local function refreshInputLock()

	applyInputLock(
		charging
			or chargeAnimationActive
	)

end


-- =========================================================
-- CAMERA SHAKE
-- =========================================================

local function triggerMaxChakraShake()

	cameraShakeActive =
		true

	cameraShakeStartTime =
		time()

	cameraShakeSeed +=
		1

	print(
		"[ChakraChargeController] "
			.. "MAX CHAKRA CAMERA SHAKE"
	)

end


local function updateCameraShake()

	if not cameraShakeActive then

		return

	end


	if not camera then

		cameraShakeActive =
			false

		return

	end


	local elapsed =
		time()
	- cameraShakeStartTime


	if elapsed >=
		MAX_CHAKRA_SHAKE_DURATION then

		cameraShakeActive =
			false

		return

	end


	local progress =
		elapsed /
		MAX_CHAKRA_SHAKE_DURATION


	-- Fade out the shake smoothly.
	local fade =
		1
	- progress


	-- Multiple sine waves create an irregular energy-like shake.
	local t =
		elapsed
		* MAX_CHAKRA_SHAKE_FREQUENCY


	local noiseX =
		math.sin(
			t
			+ cameraShakeSeed
		)


	local noiseY =
		math.sin(
			t * 1.37
			+ cameraShakeSeed * 0.7
		)


	local noiseZ =
		math.cos(
			t * 0.83
			+ cameraShakeSeed * 1.3
		)


	local rotationX =
		math.sin(
			t * 1.17
			+ cameraShakeSeed
		)


	local rotationY =
		math.cos(
			t * 1.43
			+ cameraShakeSeed
		)


	local rotationZ =
		math.sin(
			t * 0.91
			+ cameraShakeSeed * 0.5
		)


	local positionOffset =
		Vector3.new(
			noiseX,
			noiseY,
			noiseZ
		)
		*
		(
			MAX_CHAKRA_SHAKE_POSITION
			* fade
		)


	local rotationOffset =
		CFrame.Angles(
			rotationX
			* MAX_CHAKRA_SHAKE_ROTATION
			* fade,

			rotationY
			* MAX_CHAKRA_SHAKE_ROTATION
			* fade,

			rotationZ
			* MAX_CHAKRA_SHAKE_ROTATION
			* fade
		)


	camera.CFrame =
		camera.CFrame
		* CFrame.new(
			positionOffset
		)
		* rotationOffset

end


-- =========================================================
-- FIND VALUE
-- =========================================================

local function getNumberValue(
	container: Instance,
	names: {string}
): number?

	-- =====================================================
	-- ATTRIBUTES
	-- =====================================================

	for _, name in ipairs(
		names
		) do

		local attribute =
			container:
			GetAttribute(
				name
			)


		if typeof(attribute) ==
			"number" then

			return attribute

		end

	end


	-- =====================================================
	-- DIRECT VALUE OBJECTS
	-- =====================================================

	for _, name in ipairs(
		names
		) do

		local object =
			container:
			FindFirstChild(
				name
			)


		if object
			and object:IsA(
				"NumberValue"
			) then

			return object.Value

		end


		if object
			and object:IsA(
				"IntValue"
			) then

			return object.Value

		end

	end


	-- =====================================================
	-- RECURSIVE VALUE OBJECT FALLBACK
	-- =====================================================

	for _, descendant in ipairs(
		container:GetDescendants()
		) do

		if not table.find(
			names,
			descendant.Name
			) then

			continue

		end


		if descendant:IsA(
			"NumberValue"
			) then

			return descendant.Value

		end


		if descendant:IsA(
			"IntValue"
			) then

			return descendant.Value

		end

	end


	return nil

end


-- =========================================================
-- CHECK MAX CHAKRA
-- =========================================================

local function checkMaxChakra()

	if not character
		or not character.Parent then

		return

	end


	if maxChakraShakeTriggered then

		return

	end


	local currentChakra =
		getNumberValue(
			character,
			CHAKRA_VALUE_NAMES
		)


	local maxChakra =
		getNumberValue(
			character,
			MAX_CHAKRA_VALUE_NAMES
		)


	if not currentChakra
		or not maxChakra then

		return

	end


	if maxChakra <= 0 then

		return

	end


	if currentChakra >=
		maxChakra then

		maxChakraShakeTriggered =
			true


		triggerMaxChakraShake()

	end

end


-- =========================================================
-- RESET MAX SHAKE
-- =========================================================

local function resetMaxChakraShake()

	maxChakraShakeTriggered =
		false


	cameraShakeActive =
		false

end


-- =========================================================
-- ROTATION LOCK
-- =========================================================

local function startRotationLock()

	if rotationLocked then

		return

	end


	if not character
		or not character.Parent
		or not humanoid
		or not humanoid.Parent then

		return

	end


	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)


	if not root
		or not root:IsA(
			"BasePart"
		) then

		return

	end


	previousAutoRotate =
		humanoid.AutoRotate


	humanoid.AutoRotate =
		false


	-- =====================================================
	-- ATTACHMENT
	-- =====================================================

	local attachment =
		Instance.new(
			"Attachment"
		)


	attachment.Name =
		"ChakraRotationLockAttachment"


	attachment.Parent =
		root


	-- =====================================================
	-- ALIGN ORIENTATION
	-- =====================================================

	local align =
		Instance.new(
			"AlignOrientation"
		)


	align.Name =
		"ChakraRotationLock"


	align.Mode =
		Enum.OrientationAlignmentMode.OneAttachment


	align.Attachment0 =
		attachment


	-- Capture the current rotation.
	align.CFrame =
		root.CFrame.Rotation


	align.RigidityEnabled =
		true


	align.Responsiveness =
		200


	align.MaxTorque =
		math.huge


	align.MaxAngularVelocity =
		math.huge


	align.Parent =
		root


	-- =====================================================
	-- SAVE
	-- =====================================================

	lockedRootPart =
		root


	rotationAttachment =
		attachment


	rotationAlign =
		align


	rotationLocked =
		true


	root.AssemblyAngularVelocity =
		Vector3.zero

end


-- =========================================================
-- STOP ROTATION LOCK
-- =========================================================

local function stopRotationLock()

	if not rotationLocked then

		return

	end


	if rotationAlign then

		rotationAlign:
			Destroy()

	end


	if rotationAttachment then

		rotationAttachment:
			Destroy()

	end


	rotationAlign =
		nil


	rotationAttachment =
		nil


	if lockedRootPart
		and lockedRootPart.Parent then

		lockedRootPart.AssemblyAngularVelocity =
			Vector3.zero

	end


	if humanoid
		and humanoid.Parent then

		humanoid.AutoRotate =
			previousAutoRotate

	end


	lockedRootPart =
		nil


	rotationLocked =
		false

end


-- =========================================================
-- MAINTAIN ROTATION
-- =========================================================

local function maintainRotationLock()

	if not rotationLocked then

		return

	end


	if not lockedRootPart
		or not lockedRootPart.Parent then

		return

	end


	lockedRootPart.AssemblyAngularVelocity =
		Vector3.zero

end


-- =========================================================
-- FIND BODY PART
-- =========================================================

local function findBodyPart(
	targetCharacter: Model,
	name: string
): BasePart?

	local part =
		targetCharacter:
		FindFirstChild(
			name
		)


	if part
		and part:IsA(
			"BasePart"
		) then

		return part

	end


	return nil

end


-- =========================================================
-- TARGET BODY PART
-- =========================================================

local function getTargetBodyPart(
	targetCharacter: Model,
	vfxName: string
): BasePart?

	if vfxName ==
		"Head" then

		return findBodyPart(
			targetCharacter,
			"Head"
		)

	end


	if vfxName ==
		"Torso" then

		local upperTorso =
			findBodyPart(
				targetCharacter,
				"UpperTorso"
			)


		if upperTorso then

			return upperTorso

		end


		return findBodyPart(
			targetCharacter,
			"Torso"
		)

	end


	if vfxName ==
		"LeftArm" then

		local r15Arm =
			findBodyPart(
				targetCharacter,
				"LeftUpperArm"
			)


		if r15Arm then

			return r15Arm

		end


		return findBodyPart(
			targetCharacter,
			"Left Arm"
		)

	end


	if vfxName ==
		"RightArm" then

		local r15Arm =
			findBodyPart(
				targetCharacter,
				"RightUpperArm"
			)


		if r15Arm then

			return r15Arm

		end


		return findBodyPart(
			targetCharacter,
			"Right Arm"
		)

	end


	if vfxName ==
		"LeftLeg" then

		local r15Leg =
			findBodyPart(
				targetCharacter,
				"LeftUpperLeg"
			)


		if r15Leg then

			return r15Leg

		end


		return findBodyPart(
			targetCharacter,
			"Left Leg"
		)

	end


	if vfxName ==
		"RightLeg" then

		local r15Leg =
			findBodyPart(
				targetCharacter,
				"RightUpperLeg"
			)


		if r15Leg then

			return r15Leg

		end


		return findBodyPart(
			targetCharacter,
			"Right Leg"
		)

	end


	return nil

end


-- =========================================================
-- FIND VFX FOLDER
-- =========================================================

local function findVFXFolder():
	Folder?

	local folder =
		chakraRemotes:
		FindFirstChild(
			VFX_FOLDER_NAME
		)


	if folder
		and folder:IsA(
			"Folder"
		) then

		return folder

	end


	for _, descendant in ipairs(
		chakraRemotes:GetDescendants()
		) do

		if descendant.Name ==
			VFX_FOLDER_NAME
			and descendant:IsA(
				"Folder"
			) then

			return descendant

		end

	end


	return nil

end


-- =========================================================
-- ENABLE VFX
-- =========================================================

local function enableVFXObject(
	object: Instance
)

	if object:IsA(
		"ParticleEmitter"
		) then

		object.Enabled =
			true

	end


	if object:IsA(
		"Trail"
		) then

		object.Enabled =
			true

	end


	if object:IsA(
		"Beam"
		) then

		object.Enabled =
			true

	end


	if object:IsA(
		"PointLight"
		) then

		object.Enabled =
			true

	end

end


local function enableVFXTree(
	root: Instance
)

	enableVFXObject(
		root
	)


	for _, descendant in ipairs(
		root:GetDescendants()
		) do

		enableVFXObject(
			descendant
		)

	end

end


-- =========================================================
-- START BODY VFX
-- =========================================================

local function startChakraVFX()

	if #activeVFXObjects > 0 then

		return

	end


	if not character
		or not character.Parent then

		return

	end


	local sourceFolder =
		findVFXFolder()


	if not sourceFolder then

		warn(
			"[ChakraChargeController] "
				.. "VFX folder not found: "
				.. VFX_FOLDER_NAME
		)

		return

	end


	print(
		"[ChakraChargeController] "
			.. "VFX folder found: "
			.. sourceFolder:GetFullName()
	)


	-- =====================================================
	-- BODY PART FOLDERS
	-- =====================================================

	for _, bodyFolder in ipairs(
		sourceFolder:GetChildren()
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
				"[ChakraChargeController] "
					.. "Body part not found: "
					.. bodyFolder.Name
			)

			continue

		end


		print(
			"[ChakraChargeController] "
				.. bodyFolder.Name
				.. " -> "
				.. targetPart.Name
		)


		for _, sourceObject in ipairs(
			bodyFolder:GetChildren()
			) do

			local clone =
				sourceObject:
				Clone()


			clone.Parent =
				targetPart


			table.insert(
				activeVFXObjects,
				clone
			)


			enableVFXTree(
				clone
			)

		end

	end


	print(
		"[ChakraChargeController] "
			.. "TOTAL VFX OBJECTS: "
			.. tostring(
				#activeVFXObjects
			)
	)

end


-- =========================================================
-- STOP BODY VFX
-- =========================================================

local function stopChakraVFX()

	if #activeVFXObjects == 0 then

		return

	end


	local objects =
		activeVFXObjects


	activeVFXObjects =
		{}


	for _, object in ipairs(
		objects
		) do

		if not object
			or not object.Parent then

			continue

		end


		if object:IsA(
			"ParticleEmitter"
			) then

			object.Enabled =
				false

		end


		if object:IsA(
			"Trail"
			) then

			object.Enabled =
				false

		end


		if object:IsA(
			"Beam"
			) then

			object.Enabled =
				false

		end


		if object:IsA(
			"PointLight"
			) then

			object.Enabled =
				false

		end


		for _, descendant in ipairs(
			object:GetDescendants()
			) do

			if descendant:IsA(
				"ParticleEmitter"
				) then

				descendant.Enabled =
					false

			end


			if descendant:IsA(
				"Trail"
				) then

				descendant.Enabled =
					false

			end


			if descendant:IsA(
				"Beam"
				) then

				descendant.Enabled =
					false

			end


			if descendant:IsA(
				"PointLight"
				) then

				descendant.Enabled =
					false

			end

		end

	end


	task.delay(
		0.70,
		function()

			for _, object in ipairs(
				objects
				) do

				if object
					and object.Parent then

					object:
						Destroy()

				end

			end

		end
	)

end


-- =========================================================
-- FORCE VFX CLEANUP
-- =========================================================

local function destroyChakraVFXImmediately()

	local objects =
		activeVFXObjects


	activeVFXObjects =
		{}


	for _, object in ipairs(
		objects
		) do

		if object
			and object.Parent then

			object:
				Destroy()

		end

	end

end


-- =========================================================
-- CHARGE SOUND OWNERSHIP
-- =========================================================
-- Audio is created/played by ChakraService on the SERVER when
-- ChakraChargeVisualActive becomes true. This prevents duplicate local
-- sounds and makes the same 3D sound audible to nearby players.

local function startChargeSound()
	-- Server-owned. Intentionally empty.
end

local function stopChargeSound()
	-- Server-owned. Intentionally empty.
end

local function destroyChargeSoundImmediately()
	-- Server-owned. Intentionally empty.
end


-- =========================================================
-- STOP CHARGE ANIMATION
-- =========================================================
--
-- IMPORTANT:
-- This is ONLY called when C is released or character
-- is reset/destroyed.
--
-- Reaching maximum Chakra does NOT call this.
-- =========================================================

local function stopChargeAnimation(
	fadeTime: number?
)

	chargeAnimationActive =
		false


	chargeAnimationSequence =
		0


	chargeLoopStartTime =
		nil


	if chargeTrack
		and chargeTrack.IsPlaying then

		chargeTrack:
			Stop(
				fadeTime
				or 0.10
			)

	end


	stopRotationLock()

	stopChakraVFX()

	stopChargeSound()

	-- This is the authoritative visual STOP from the owning client.
	-- It is intentionally separate from ChakraCharging because the server
	-- can stop filling Chakra at MAX while the player is still holding C.
	setReplicatedChargeVisual(
		false
	)


	refreshInputLock()

end


-- =========================================================
-- SERVER STOP
-- =========================================================

local function requestStopGuaranteed()

	if stopRequestInFlight then

		return

	end


	if not chargeRequest then

		return

	end


	stopRequestInFlight =
		true


	task.spawn(
		function()

			pcall(
				function()

					chargeRequest:
						InvokeServer(
							"Stop"
						)

				end
			)


			stopRequestInFlight =
				false

		end
	)

end


-- =========================================================
-- RETRY
-- =========================================================

local attemptStart:
	(number) -> ()


local function isChakraChargeStatusBlocked(): boolean

	local currentCharacter =
		character


	if not currentCharacter
		or not currentCharacter.Parent then

		return false

	end


	return currentCharacter:GetAttribute(
		"Status_ChakraChargeBlocked"
	) == true
		or currentCharacter:GetAttribute(
			"Status_ChakraSuppressed"
		) == true

end


local function scheduleStartRetry(
	sequence: number
)

	if startRetryScheduled then

		return

	end


	startRetryScheduled =
		true


	task.delay(
		START_RETRY_INTERVAL,
		function()

			startRetryScheduled =
				false


			if not chargeKeyDown
				or not holdMatured
				or sequence ~=
				holdSequence
				or charging then

				return

			end


			attemptStart(
				sequence
			)

		end
	)

end


-- =========================================================
-- SERVER START
-- =========================================================

attemptStart =
	function(
		sequence: number
	)

	if sequence ~=
		holdSequence
		or not chargeKeyDown
		or not holdMatured
		or charging
		or startRequestInFlight
		or not character
		or not character.Parent then

		return

	end


	if isChakraChargeStatusBlocked() then

		return

	end


	-- =====================================================
	-- SYSTEM READY
	-- =====================================================

	if character:GetAttribute(
		"ChakraSystemReady"
		) ~= true then

		scheduleStartRetry(
			sequence
		)

		return

	end


	if not chargeRequest then

		return

	end


	startRequestInFlight =
		true


	task.spawn(
		function()

			local ok,
			allowed,
			reason =
				pcall(
					function()

						return chargeRequest:
						InvokeServer(
							"Start"
						)

					end
				)


			startRequestInFlight =
				false


			-- =================================================
			-- C RELEASED DURING REQUEST
			-- =================================================

			if sequence ~=
				holdSequence
				or not chargeKeyDown
				or not holdMatured then

				if ok
					and allowed ==
					true then

					requestStopGuaranteed()

				end

				return

			end


			-- =================================================
			-- ACCEPTED
			-- =================================================

			if ok
				and allowed ==
				true then

				charging =
					true


				refreshInputLock()


				startRotationLock()


				startChargeSound()


				startChakraVFX()


				-- Tell the server that the charge visual is active so every
				-- other client can render this player's body VFX.
				setReplicatedChargeVisual(
					true
				)


				return

			end


			-- =================================================
			-- REJECTED
			-- =================================================

			local reasonString =
				if typeof(reason) ==
				"string"
				then reason
				else "RequestFailed"


			if character
				and character.Parent then

				character:SetAttribute(
					"ChakraChargeClientLastReject",
					reasonString
				)

			end


			if TRANSIENT_RETRY_REASONS[
				reasonString
				] == true then

				scheduleStartRetry(
					sequence
				)

			else

				-- Only stop the animation if the server
				-- permanently rejected the INITIAL start.
				stopChargeAnimation(
					0.10
				)

			end

		end
	)

end


-- =========================================================
-- SERVER ATTRIBUTE SYNC
-- =========================================================

local function syncChargingFromCharacter()

	local nextCharging =
		character ~= nil
		and character.Parent ~= nil
		and character:GetAttribute(
			"ChakraCharging"
		) == true


	local wasCharging =
		charging


	charging =
		nextCharging


	-- =====================================================
	-- SERVER STARTED CHARGE
	-- =====================================================

	if charging
		and not wasCharging then

		startRotationLock()

		refreshInputLock()


		-- Make sure effects exist.
		startChargeSound()

		startChakraVFX()

	end


	-- =====================================================
	-- IMPORTANT CHANGE
	-- =====================================================
	--
	-- We DO NOT call stopChargeAnimation() when
	-- ChakraCharging becomes false.
	--
	-- This allows the server to stop actually adding Chakra
	-- when the meter is full while the local charge animation,
	-- VFX and sound continue until C is released.
	--
	-- =====================================================


	if charging then

		startRotationLock()

		refreshInputLock()

	end


	-- =====================================================
	-- SAFETY
	-- =====================================================

	if charging
		and not chargeKeyDown then

		requestStopGuaranteed()

	end

end


-- =========================================================
-- BEGIN CHARGE ANIMATION
-- =========================================================

local function beginChargeAnimation(
	sequence: number
)

	if sequence ~=
		holdSequence
		or not chargeKeyDown
		or not holdMatured then

		return

	end


	if isChakraChargeStatusBlocked() then

		return

	end


	if not chargeTrack then

		warn(
			"[ChakraChargeController] "
				.. "Charge animation unavailable."
		)

		return

	end


	if chargeTrack.IsPlaying then

		chargeTrack:
			Stop(
				0.05
			)

	end


	-- =====================================================
	-- RESET MAX SHAKE FOR THIS CHARGE
	-- =====================================================

	resetMaxChakraShake()


	-- =====================================================
	-- STATE
	-- =====================================================

	chargeAnimationActive =
		true


	chargeAnimationSequence =
		sequence


	chargeMarkerReachedSequence =
		-1


	chargeLoopStartTime =
		nil


	refreshInputLock()


	-- =====================================================
	-- PLAY
	-- =====================================================

	chargeTrack.TimePosition =
		0


	chargeTrack:
		Play(
			0.08,
			1,
			CHARGE_ANIMATION_SPEED
		)


	chargeTrack:
		AdjustSpeed(
			CHARGE_ANIMATION_SPEED
		)

end


-- =========================================================
-- CHAKRA SUPPRESSION
-- =========================================================

local function handleChakraStatusGate()

	if not isChakraChargeStatusBlocked() then

		return

	end


	-- Invalidate the current hold so Suppression ending while C is still
	-- held cannot silently restart Chakra Charge.
	holdMatured =
		false


	holdSequence +=
		1


	startRetryScheduled =
		false


	if charging then

		requestStopGuaranteed()

	end


	charging =
		false


	stopChargeAnimation(
		0.10
	)


	resetMaxChakraShake()

	refreshInputLock()

end


-- =========================================================
-- BIND CHARACTER
-- =========================================================

local function bindCharacter(
	newCharacter: Model
)

	-- =====================================================
	-- DISCONNECT
	-- =====================================================

	if chargeAttributeConnection then

		chargeAttributeConnection:
			Disconnect()

		chargeAttributeConnection =
			nil

	end


	if chargeMarkerConnection then

		chargeMarkerConnection:
			Disconnect()

		chargeMarkerConnection =
			nil

	end


	for _, connection in ipairs(
		statusGateConnections
		) do

		connection:
			Disconnect()

	end


	table.clear(
		statusGateConnections
	)


	-- =====================================================
	-- CLEAN OLD
	-- =====================================================

	if chargeTrack
		and chargeTrack.IsPlaying then

		chargeTrack:
			Stop(
				0
			)

	end


	destroyChakraVFXImmediately()

	destroyChargeSoundImmediately()

	-- Clear any replicated charge VFX left on the previous character.
	setReplicatedChargeVisual(
		false
	)

	stopRotationLock()

	resetMaxChakraShake()


	-- =====================================================
	-- RESET
	-- =====================================================

	character =
		newCharacter


	humanoid =
		nil


	animator =
		nil


	chargeTrack =
		nil


	charging =
		false


	chargeAnimationActive =
		false


	chargeAnimationSequence =
		0


	chargeMarkerReachedSequence =
		-1


	chargeLoopStartTime =
		nil


	chargeKeyDown =
		false


	holdMatured =
		false


	holdSequence +=
		1


	startRequestInFlight =
		false


	stopRequestInFlight =
		false


	startRetryScheduled =
		false


	rotationLocked =
		false


	lockedRootPart =
		nil


	rotationAttachment =
		nil


	rotationAlign =
		nil


	applyInputLock(
		false
	)


	-- =====================================================
	-- HUMANOID
	-- =====================================================

	humanoid =
		newCharacter:
		WaitForChild(
			"Humanoid"
		) :: Humanoid


	-- =====================================================
	-- ANIMATOR
	-- =====================================================

	animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)


	if not animator then

		animator =
			Instance.new(
				"Animator"
			)


		animator.Parent =
			humanoid

	end


	-- =====================================================
	-- ANIMATION
	-- =====================================================

	local chargeAnimation =
		Instance.new(
			"Animation"
		)


	chargeAnimation.Name =
		"ChakraChargeAnimation"


	chargeAnimation.AnimationId =
		CHARGE_ANIMATION_ID


	chargeTrack =
		animator:
		LoadAnimation(
			chargeAnimation
		)


	chargeTrack.Priority =
		Enum.AnimationPriority.Action


	chargeTrack.Looped =
		false


	-- =====================================================
	-- MARKER
	-- =====================================================

	chargeMarkerConnection =
		chargeTrack:
		GetMarkerReachedSignal(
			CHARGE_START_MARKER
		):
		Connect(
			function()

				if not chargeAnimationActive
					or not chargeKeyDown
					or not holdMatured
					or chargeAnimationSequence ~=
					holdSequence then

					return

				end


				if chargeMarkerReachedSequence ==
					holdSequence then

					return

				end


				chargeMarkerReachedSequence =
				holdSequence


				chargeLoopStartTime =
				chargeTrack
				and chargeTrack.TimePosition
				or nil


				if character
					and character.Parent then

					character:SetAttribute(
						"ChakraChargeMarkerReachedAt",
						workspace:
						GetServerTimeNow()
					)

				end


				attemptStart(
					holdSequence
				)

			end
		)


	-- =====================================================
	-- CHARGING ATTRIBUTE
	-- =====================================================

	chargeAttributeConnection =
		newCharacter:
		GetAttributeChangedSignal(
			"ChakraCharging"
		):
		Connect(
			syncChargingFromCharacter
		)


	syncChargingFromCharacter()


	for _, attributeName in ipairs({
		"Status_ChakraChargeBlocked",
		"Status_ChakraSuppressed",
		}) do

		table.insert(
			statusGateConnections,
			newCharacter:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(
					handleChakraStatusGate
				)
		)

	end


	handleChakraStatusGate()


	-- =====================================================
	-- DEATH
	-- =====================================================

	humanoid.Died:
		Connect(
			function()

				destroyChakraVFXImmediately()

				destroyChargeSoundImmediately()

				setReplicatedChargeVisual(
					false
				)

				stopRotationLock()

				cameraShakeActive =
				false

			end
		)

end


-- =========================================================
-- CHARACTER ADDED
-- =========================================================

player.CharacterAdded:
	Connect(
		bindCharacter
	)


if player.Character then

	bindCharacter(
		player.Character
	)

end


-- =========================================================
-- INPUT BEGAN
-- =========================================================

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)

			if input.KeyCode ~=
				CHARGE_KEY then

				return

			end


			if gameProcessed
				or UserInputService:
				GetFocusedTextBox() then

				return

			end


			if chargeKeyDown then

				return

			end


			if isChakraChargeStatusBlocked() then

				return

			end


			chargeKeyDown =
			true


			holdMatured =
			false


			holdSequence +=
			1


			local sequence =
			holdSequence


			task.delay(
				HOLD_THRESHOLD,
				function()

					if not chargeKeyDown
						or sequence ~=
						holdSequence then

						return

					end


					holdMatured =
					true


					beginChargeAnimation(
						sequence
					)

				end
			)

		end
	)


-- =========================================================
-- INPUT ENDED
-- =========================================================

UserInputService.InputEnded:
	Connect(
		function(
			input: InputObject
		)

			if input.KeyCode ~=
				CHARGE_KEY then

				return

			end


			-- =================================================
			-- ONLY HERE DO WE END THE CHARGE ANIMATION
			-- =================================================

			chargeKeyDown =
			false


			holdMatured =
			false


			holdSequence +=
			1


			startRetryScheduled =
			false


			stopChargeAnimation(
				0.10
			)


			if charging then

				requestStopGuaranteed()

			end


			charging =
			false


			resetMaxChakraShake()


			refreshInputLock()

		end
	)


-- =========================================================
-- WINDOW FOCUS LOST
-- =========================================================

UserInputService.WindowFocusReleased:
	Connect(
		function()

			chargeKeyDown =
			false


			holdMatured =
			false


			holdSequence +=
			1


			startRetryScheduled =
			false


			stopChargeAnimation(
				0.10
			)


			if charging then

				requestStopGuaranteed()

			end


			charging =
			false


			resetMaxChakraShake()


			refreshInputLock()

		end
	)


-- =========================================================
-- RENDER STEPPED
-- =========================================================

RunService.RenderStepped:
	Connect(
		function()

			-- =================================================
			-- MAX CHAKRA CHECK
			-- =================================================
			--
			-- This is independent of ChakraCharging.
			-- Therefore the animation can continue even when
			-- the server stops filling the meter.
			--

			if chargeKeyDown
				and chargeAnimationActive then

				checkMaxChakra()

			end


			-- =================================================
			-- CAMERA SHAKE
			-- =================================================

			if cameraShakeActive then

				updateCameraShake()

			end


			-- =================================================
			-- ANIMATION LOOP
			-- =================================================

			if LOOP_CHARGE_SECTION_FROM_MARKER
				and chargeAnimationActive
				and chargeTrack
				and chargeTrack.IsPlaying
				and chargeLoopStartTime
				and chargeTrack.Length > 0 then


				local loopEnd =
				chargeTrack.Length
				- CHARGE_LOOP_END_EPSILON


				if chargeTrack.TimePosition >=
					loopEnd then


					local restartAt =
					math.min(

						chargeLoopStartTime
						+ CHARGE_LOOP_RESTART_OFFSET,

						math.max(

							0,

							chargeTrack.Length
							- (
								CHARGE_LOOP_END_EPSILON
								* 2
							)

						)

					)


					if restartAt <
						chargeTrack.Length then

						chargeTrack.TimePosition =
						restartAt

					end

				end

			end


			-- =================================================
			-- ROTATION LOCK
			-- =================================================

			if rotationLocked then

				maintainRotationLock()

			end


			-- =================================================
			-- MOVEMENT LOCK
			-- =================================================

			if not (
				charging
				or chargeAnimationActive
				)
				or not humanoid
				or not humanoid.Parent then

				return

			end


			humanoid:
			Move(
				Vector3.zero,
				false
			)

		end
	)


-- =========================================================
-- CLEANUP
-- =========================================================

script.Destroying:
	Connect(
		function()

			chargeKeyDown =
			false


			holdMatured =
			false


			holdSequence +=
			1


			if chargeMarkerConnection then

				chargeMarkerConnection:
				Disconnect()

			end


			if chargeAttributeConnection then

				chargeAttributeConnection:
				Disconnect()

			end


			for _, connection in ipairs(
				statusGateConnections
				) do

				connection:
				Disconnect()

			end


			table.clear(
				statusGateConnections
			)


			destroyChakraVFXImmediately()

			destroyChargeSoundImmediately()

			setReplicatedChargeVisual(
				false
			)

			stopRotationLock()


			cameraShakeActive =
			false


			if chargeTrack
				and chargeTrack.IsPlaying then

				chargeTrack:
				Stop(
					0
				)

			end


			applyInputLock(
				false
			)

		end
	)


-- =========================================================
-- READY
-- =========================================================

print(
	"[ChakraChargeController] READY v5.3 ChakraSuppressionIntegration"
		.. " | Key="
		.. CHARGE_KEY.Name
		.. " | Hold="
		.. tostring(
			HOLD_THRESHOLD
		)
		.. "s"
		.. " | BodyPartVFX=ON"
		.. " | MultiplayerChargeVFX=ON"
		.. " | RotationLock=AlignOrientation"
		.. " | AnimationStopsOnReleaseOrChakraSuppression=ON"
		.. " | MaxChakraShake=ON"
		.. " | Sound=111262226714062"
		.. " | Animation="
		.. CHARGE_ANIMATION_ID
		.. " | Marker="
		.. CHARGE_START_MARKER
)