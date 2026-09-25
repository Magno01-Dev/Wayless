--!strict
-- ClashController v2.2 - ServerHandshake
-- ElDiabloLocoStudios
--
-- INSTALL:
-- StarterPlayer > StarterPlayerScripts > ClashController [LocalScript]
--
-- Paired with:
-- ServerScriptService > ClashServerController v2.3
--
-- DOES NOT own normal combat or Lunge.
--
-- Current approved Clash:
-- Animation: 110715673180255
-- Hitstop: 0.075 sec
-- Knockback travel: 24 studs per player
-- Arc apex: 5.4 studs
-- Slide: 8 studs per player
--
-- Required animation markers:
-- ClashImpact
-- ClashResolve
-- LandImpact
-- SlideStart
-- SlideEnd
-- ClashEnd

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

local Debris =
	game:GetService("Debris")

local ContentProvider =
	game:GetService("ContentProvider")


local localPlayer =
	Players.LocalPlayer


-- =========================
-- REMOTE
-- =========================

local combatRemotes =
	ReplicatedStorage:
	WaitForChild(
		"CombatRemotes"
	)

local clashEvent =
	combatRemotes:
	WaitForChild(
		"ClashEvent"
	) :: RemoteEvent


-- =========================
-- SERVER HANDSHAKE
-- =========================

local function readServerHandshake()

	local bootstrapOnline =
		clashEvent:GetAttribute(
			"ClashServerBootstrapOnline"
		)

	local serverVersion =
		clashEvent:GetAttribute(
			"ClashServerVersion"
		)

	local coreLoaded =
		clashEvent:GetAttribute(
			"ClashServerCoreLoaded"
		)

	local coreError =
		clashEvent:GetAttribute(
			"ClashServerCoreError"
		)


	print(
		"[ClashClient v2.2] SERVER HANDSHAKE",
		"BootstrapOnline=",
		bootstrapOnline,
		"Version=",
		serverVersion,
		"CoreLoaded=",
		coreLoaded
	)


	if bootstrapOnline ~= true
		or serverVersion ~= "2.5" then

		warn(
			"[ClashClient v2.2] SERVER HANDSHAKE MISSING | "
				.. "ClashEvent exists, but ClashServerBootstrap v2.5 "
				.. "is NOT confirmed running."
		)

	elseif coreLoaded ~= true then

		warn(
			"[ClashClient v2.2] SERVER CORE NOT LOADED | Error=",
			coreError
		)
	end
end


readServerHandshake()


clashEvent:
	GetAttributeChangedSignal(
		"ClashServerCoreLoaded"
	):
	Connect(
		readServerHandshake
	)


-- =========================
-- CONFIG
-- =========================

local CLASH_ANIMATION_ID =
	"rbxassetid://110715673180255"

local HITSTOP_DURATION =
	0.075


-- ClashImpact is authored at/very near the start.
local IMPACT_FALLBACK_DELAY =
	0.050


-- Approved movement from solo QA.
local ARC_ANIMATION_DURATION =
	40 / 60

local ARC_HORIZONTAL_DISTANCE =
	24.0

local ARC_APEX_HEIGHT =
	5.4

local ARC_HORIZONTAL_EASE_POWER =
	1.35


local SLIDE_ANIMATION_DURATION =
	20 / 60

local SLIDE_DISTANCE =
	8.0


-- Dust
local SLIDE_DUST_INTERVAL =
	0.055

local MAX_VFX_DISTANCE =
	150


-- ReplicatedStorage > VFX > Clash > ImpactLunge
local CLASH_IMPACT_VFX_LIFETIME =
	3.0


-- Sound played exactly when the clash animation begins.
local CLASH_START_SOUND_ID =
	"rbxassetid://96478382958151"

local CLASH_START_SOUND_VOLUME =
	1.0

local CLASH_START_SOUND_ROLLOFF_MIN =
	10

local CLASH_START_SOUND_ROLLOFF_MAX =
	120

local CLASH_START_SOUND_LIFETIME =
	8.0


-- Camera shake fired in the EXACT same scheduled callback as the clash sound.
local CLASH_CAMERA_SHAKE_DURATION =
	0.38

-- Movimiento base del temblor.
local CLASH_CAMERA_SHAKE_POSITION =
	0.46

-- Rotacion maxima del temblor base.
local CLASH_CAMERA_SHAKE_ROTATION_DEGREES =
	3.6

-- Frecuencia del ruido.
local CLASH_CAMERA_SHAKE_FREQUENCY =
	38

-- Golpe inicial: hace que el primer frame del clash se sienta mucho mas fuerte.
local CLASH_CAMERA_SHAKE_IMPACT_KICK =
	0.72

local CLASH_CAMERA_SHAKE_IMPACT_PITCH_DEGREES =
	4.2

local CLASH_CAMERA_SHAKE_IMPACT_ROLL_DEGREES =
	2.0

local CLASH_CAMERA_SHAKE_FULL_DISTANCE =
	35

local CLASH_CAMERA_SHAKE_MAX_DISTANCE =
	120


-- Preload one template locally so the first clash has less audio delay.
local clashStartSoundTemplate =
	Instance.new(
		"Sound"
	)

clashStartSoundTemplate.Name =
	"ClashStartSoundTemplate"

clashStartSoundTemplate.SoundId =
	CLASH_START_SOUND_ID

clashStartSoundTemplate.Volume =
	CLASH_START_SOUND_VOLUME

clashStartSoundTemplate.RollOffMode =
	Enum.RollOffMode.InverseTapered

clashStartSoundTemplate.RollOffMinDistance =
	CLASH_START_SOUND_ROLLOFF_MIN

clashStartSoundTemplate.RollOffMaxDistance =
	CLASH_START_SOUND_ROLLOFF_MAX

clashStartSoundTemplate.Looped =
	false

clashStartSoundTemplate.Parent =
	script


task.spawn(
	function()

		pcall(
			function()

				ContentProvider:
					PreloadAsync({
						clashStartSoundTemplate,
					})
			end
		)
	end
)


-- Per-emitter burst counts. These are intentionally local visual tuning
-- values; changing them does not affect clash gameplay or replication.
local CLASH_IMPACT_EMIT_COUNTS: {
	[string]: number
} = {
	Break2 = 8,
	Break3 = 8,
	Break4 = 8,
	Wind1 = 1,
	Wind2 = 1,
}


local DEBUG =
	true


-- =========================
-- LOCAL PARTICIPANT STATE
-- =========================

local activeClash: any =
	nil

local hitstopToken =
	0


-- =========================
-- GLOBAL VFX STATE
-- =========================

local slideVFX: {
	[number]: any
} = {}


-- =========================
-- CAMERA SHAKE STATE
-- =========================

local activeCameraShakes: {
	[number]: any
} = {}

local CAMERA_SHAKE_BIND_NAME =
	"ClashCameraShake_"
	.. tostring(
		localPlayer.UserId
	)


-- =========================
-- HELPERS
-- =========================

local function horizontalUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	local horizontal =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if horizontal.Magnitude >
		0.001 then

		return horizontal.Unit
	end


	local fallbackHorizontal =
		Vector3.new(
			fallback.X,
			0,
			fallback.Z
		)

	if fallbackHorizontal.Magnitude >
		0.001 then

		return fallbackHorizontal.Unit
	end


	return Vector3.new(
		0,
		0,
		-1
	)
end


local function getPlayerCharacterParts(
	player: Player
): (Model?, Humanoid?, BasePart?, Animator?)

	local character =
		player.Character

	if not character then

		return nil,
			nil,
			nil,
			nil
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

		return nil,
			nil,
			nil,
			nil
	end


	local animator =
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


	return character,
		humanoid,
		root,
		animator
end


local function playerFromUserId(
	userId: number
): Player?

	return Players:
		GetPlayerByUserId(
			userId
		)
end


local function loadClashTrack(
	animator: Animator
): AnimationTrack

	local animation =
		Instance.new(
			"Animation"
		)

	animation.Name =
		"ClashReaction"

	animation.AnimationId =
		CLASH_ANIMATION_ID


	local track =
		animator:
		LoadAnimation(
			animation
		)


	animation:
		Destroy()


	track.Priority =
		Enum.AnimationPriority.Action4

	track.Looped =
		false


	return track
end


local function zeroLocalMotion(
	state: any
)

	local root =
		state.root

	local humanoid =
		state.humanoid


	if root
		and root.Parent then

		root.AssemblyLinearVelocity =
			Vector3.zero

		root.AssemblyAngularVelocity =
			Vector3.zero
	end


	if humanoid
		and humanoid.Parent then

		humanoid:
			Move(
				Vector3.zero,
				false
			)
	end
end


local function faceTowardAxis(
	root: BasePart,
	position: Vector3,
	toward: Vector3
)

	local horizontalToward =
		horizontalUnit(
			toward,
			root.CFrame.LookVector
		)


	root.CFrame =
		CFrame.lookAt(
			position,
			position
			+ horizontalToward,
			Vector3.yAxis
		)
end


-- =========================
-- FOOT EXTENT REPORT
-- =========================

local function projectedHalfExtent(
	part: BasePart,
	direction: Vector3
): number

	local unitDirection =
		horizontalUnit(
			direction,
			Vector3.new(
				1,
				0,
				0
			)
		)


	local cf =
		part.CFrame

	local size =
		part.Size


	return math.abs(
		unitDirection:Dot(
			cf.RightVector
		)
	) * size.X * 0.5

		+ math.abs(
			unitDirection:Dot(
				cf.UpVector
			)
		) * size.Y * 0.5

		+ math.abs(
			unitDirection:Dot(
				cf.LookVector
			)
		) * size.Z * 0.5
end


local function findForwardKickLeg(
	character: Model,
	root: BasePart,
	towardDirection: Vector3
): BasePart?

	local toward =
		horizontalUnit(
			towardDirection,
			root.CFrame.LookVector
		)


	local candidates = {
		character:
			FindFirstChild(
				"Right Leg"
			),

		character:
			FindFirstChild(
				"Left Leg"
			),
	}


	local bestPart: BasePart? =
		nil

	local bestForward =
		-math.huge


	for _,
		candidate in ipairs(
			candidates
		) do

		if candidate
			and candidate:IsA(
				"BasePart"
			) then

			local relative =
				candidate.Position
			- root.Position

			local amount =
				relative:Dot(
					toward
				)


			if amount >
				bestForward then

				bestForward =
					amount

				bestPart =
					candidate
			end
		end
	end


	return bestPart
end


local function computeOwnKickExtent(
	state: any
): (number?, string?)

	local leg =
		findForwardKickLeg(
			state.character,
			state.root,
			state.toward
		)


	if not leg then

		return nil,
			nil
	end


	local centerOffset =
		(
			leg.Position
			- state.root.Position
		):
		Dot(
			state.toward
		)


	local frontExtent =
		centerOffset
		+ projectedHalfExtent(
			leg,
			state.toward
		)


	return math.max(
		0,
		frontExtent
	),
		leg.Name
end


-- =========================
-- CLASH IMPACT VFX
-- =========================

local warnedMissingImpactVFX =
	false


local function getImpactVFXTemplate(): Instance?

	local vfxFolder =
		ReplicatedStorage:
		FindFirstChild(
			"VFX"
		)

	local clashFolder =
		vfxFolder
		and vfxFolder:
		FindFirstChild(
			"Clash"
		)

	local template =
		clashFolder
		and clashFolder:
		FindFirstChild(
			"ImpactLunge"
		)


	if not template
		and not warnedMissingImpactVFX then

		warnedMissingImpactVFX =
			true

		warn(
			"[ClashClient v2.2] Missing VFX template: "
				.. "ReplicatedStorage.VFX.Clash.ImpactLunge"
		)
	end


	return template
end


local function prepareImpactClone(
	clone: Instance,
	impactCFrame: CFrame
)

	if clone:IsA(
		"BasePart"
		) then

		clone.Anchored =
			true

		clone.CanCollide =
			false

		clone.CanTouch =
			false

		clone.CanQuery =
			false

		clone.CastShadow =
			false

		clone.Transparency =
			1

		clone.CFrame =
			impactCFrame

	elseif clone:IsA(
		"Model"
		) then

		for _,
			descendant in ipairs(
				clone:GetDescendants()
			) do

			if descendant:IsA(
				"BasePart"
				) then

				descendant.Anchored =
					true

				descendant.CanCollide =
					false

				descendant.CanTouch =
					false

				descendant.CanQuery =
					false

				descendant.CastShadow =
					false
			end
		end


		clone:
			PivotTo(
				impactCFrame
			)
	end
end


local function emitClashImpactVFX(
	impactCFrame: CFrame
)

	local camera =
		workspace.CurrentCamera

	if camera
		and (
			camera.CFrame.Position
			- impactCFrame.Position
		).Magnitude >
		MAX_VFX_DISTANCE then

		return
	end


	local template =
		getImpactVFXTemplate()

	if not template then
		return
	end


	local clone =
		template:
		Clone()

	clone.Name =
		"ClashImpactVFX_Client"


	prepareImpactClone(
		clone,
		impactCFrame
	)


	clone.Parent =
		workspace


	for _,
		descendant in ipairs(
			clone:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			descendant.Enabled =
				false


			local configuredCount =
				CLASH_IMPACT_EMIT_COUNTS[
			descendant.Name
			]

			local attributeCount =
				descendant:GetAttribute(
					"EmitCount"
				)

			local emitCount =
				typeof(attributeCount) ==
				"number"
				and math.max(
					1,
					math.floor(
						attributeCount
					)
				)
				or configuredCount
				or 1


			descendant:
				Emit(
					emitCount
				)
		end
	end


	Debris:
		AddItem(
			clone,
			CLASH_IMPACT_VFX_LIFETIME
		)


	if DEBUG then

		print(
			"[ClashClient v2.2] VFX ClashImpact",
			impactCFrame.Position
		)
	end
end


-- =========================
-- DUST VFX
-- =========================

local function materialColor(
	result: RaycastResult
): Color3

	if result.Instance
		and result.Instance:IsA(
			"BasePart"
		) then

		return result.Instance.Color
	end


	local ok,
		color =
		pcall(
			function()

				return workspace.Terrain:
				GetMaterialColor(
					result.Material
				)
			end
		)


	if ok
		and typeof(color) ==
		"Color3" then

		return color
	end


	return Color3.fromRGB(
		150,
		143,
		132
	)
end


local function shouldRenderVFX(
	position: Vector3
): boolean

	local camera =
		workspace.CurrentCamera

	if not camera then
		return true
	end


	return (
		camera.CFrame.Position
		- position
	).Magnitude <=
		MAX_VFX_DISTANCE
end


-- =========================
-- CLASH START SOUND
-- =========================

local function getCharacterRootForUserId(
	userId: number
): BasePart?

	local player =
		playerFromUserId(
			userId
		)

	local character =
		player
		and player.Character

	local root =
		character
		and character:
		FindFirstChild(
			"HumanoidRootPart"
		)


	if root
		and root:IsA(
			"BasePart"
		) then

		return root
	end


	return nil
end


local function getClashWorldPosition(
	userIdA: number,
	userIdB: number
): Vector3?

	local rootA =
		getCharacterRootForUserId(
			userIdA
		)

	local rootB =
		getCharacterRootForUserId(
			userIdB
		)


	if rootA
		and rootB then

		return (
			rootA.Position
				+ rootB.Position
		)
			* 0.5
	end


	if rootA then

		return rootA.Position
	end


	if rootB then

		return rootB.Position
	end


	return nil
end


local function getCameraShakeIntensity(
	worldPosition: Vector3
): number

	local camera =
		workspace.CurrentCamera

	if not camera then

		return 0
	end


	local distance =
		(
			camera.CFrame.Position
			- worldPosition
		).Magnitude


	if distance <=
		CLASH_CAMERA_SHAKE_FULL_DISTANCE then

		return 1
	end


	if distance >=
		CLASH_CAMERA_SHAKE_MAX_DISTANCE then

		return 0
	end


	local alpha =
		(
			distance
			- CLASH_CAMERA_SHAKE_FULL_DISTANCE
		)
		/ (
			CLASH_CAMERA_SHAKE_MAX_DISTANCE
			- CLASH_CAMERA_SHAKE_FULL_DISTANCE
		)


	return 1
	- math.clamp(
		alpha,
		0,
		1
	)
end


local function playClashCameraShake(
	clashId: number,
	userIdA: number,
	userIdB: number
)

	local worldPosition =
		getClashWorldPosition(
			userIdA,
			userIdB
		)


	if not worldPosition then

		return
	end


	local intensity =
		getCameraShakeIntensity(
			worldPosition
		)


	if intensity <=
		0 then

		return
	end


	activeCameraShakes[
	clashId
	] = {
		startedAt = time(),
		duration = CLASH_CAMERA_SHAKE_DURATION,
		intensity = intensity,
		seed =
			clashId * 0.137
			+ localPlayer.UserId * 0.001,
	}


	if DEBUG then

		print(
			"[ClashClient v2.2] CAMERA SHAKE",
			clashId,
			"intensity",
			string.format(
				"%.2f",
				intensity
			)
		)
	end
end


RunService:
	BindToRenderStep(
		CAMERA_SHAKE_BIND_NAME,
		Enum.RenderPriority.Camera.Value
		+ 1,
		function()

			local camera =
			workspace.CurrentCamera

			if not camera then

				return
			end


			local now =
			time()

			local totalPosition =
			Vector3.zero

			local totalRotation =
			Vector3.zero

			local hasShake =
			false


			for clashId,
				shake in pairs(
					activeCameraShakes
				) do

				local elapsed =
				now
				- shake.startedAt

				local alpha =
				elapsed
				/ shake.duration


				if alpha >=
					1 then

					activeCameraShakes[
					clashId
					] =
					nil

					continue
				end


				hasShake =
				true


				local envelope =
				math.pow(
					1
					- math.clamp(
						alpha,
						0,
						1
					),
					2
				)


				local sample =
				elapsed
				* CLASH_CAMERA_SHAKE_FREQUENCY


				local positionNoise =
				Vector3.new(
					math.noise(
						shake.seed,
						sample,
						0
					),

					math.noise(
						shake.seed,
						sample,
						17
					),

					math.noise(
						shake.seed,
						sample,
						31
					)
				)


				local rotationNoise =
				Vector3.new(
					math.noise(
						shake.seed
						+ 43,
						sample,
						5
					),

					math.noise(
						shake.seed
						+ 59,
						sample,
						11
					),

					math.noise(
						shake.seed
						+ 71,
						sample,
						23
					)
				)


				local shakeStrength =
				shake.intensity
				* envelope


				-- Ruido principal. Multiplicamos por 2 porque math.noise suele
				-- entregar valores visualmente suaves en este rango.
				totalPosition +=
				positionNoise
				* 2
				* CLASH_CAMERA_SHAKE_POSITION
				* shakeStrength


				totalRotation +=
				rotationNoise
				* 2
				* CLASH_CAMERA_SHAKE_ROTATION_DEGREES
				* shakeStrength


				-- Impact kick: una sacudida seca en el PRIMER frame y luego
				-- una caida muy rapida. CFrame.new se aplica en espacio local
				-- de la camara, por eso +Z empuja la camara hacia atras.
				local impactKick =
				math.exp(
					-alpha * 16
				)
				* shake.intensity


				local kickDirection =
				if math.noise(
					shake.seed + 101,
					0,
					0
				) >= 0
				then 1
				else -1


				totalPosition +=
				Vector3.new(
					0,
					0,
					CLASH_CAMERA_SHAKE_IMPACT_KICK
					* impactKick
				)


				totalRotation +=
				Vector3.new(
					-CLASH_CAMERA_SHAKE_IMPACT_PITCH_DEGREES
					* impactKick,
					0,
					CLASH_CAMERA_SHAKE_IMPACT_ROLL_DEGREES
					* impactKick
					* kickDirection
				)
			end


			if not hasShake then

				return
			end


			camera.CFrame =
			camera.CFrame
			* CFrame.new(
				totalPosition
			)
			* CFrame.Angles(
				math.rad(
					totalRotation.X
				),
				math.rad(
					totalRotation.Y
				),
				math.rad(
					totalRotation.Z
				)
			)
		end
	)


local function playClashStartSound(
	clashId: number,
	userIdA: number,
	userIdB: number
)

	local position =
		getClashWorldPosition(
			userIdA,
			userIdB
		)


	if not position then

		return
	end


	if not shouldRenderVFX(
		position
		) then

		return
	end


	local anchor =
		Instance.new(
			"Part"
		)

	anchor.Name =
		"ClashStartSoundAnchor"

	anchor.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)

	anchor.Anchored =
		true

	anchor.CanCollide =
		false

	anchor.CanTouch =
		false

	anchor.CanQuery =
		false

	anchor.CastShadow =
		false

	anchor.Transparency =
		1

	anchor.CFrame =
		CFrame.new(
			position
		)

	anchor.Parent =
		workspace


	local sound =
		clashStartSoundTemplate:
		Clone()

	sound.Name =
		"ClashStartSound"

	sound.Parent =
		anchor


	sound.Ended:
		Connect(
			function()

				if anchor.Parent then

					anchor:
					Destroy()
				end
			end
		)


	sound:
		Play()


	Debris:
		AddItem(
			anchor,
			CLASH_START_SOUND_LIFETIME
		)


	if DEBUG then

		print(
			"[ClashClient v2.2] START SOUND",
			clashId,
			CLASH_START_SOUND_ID,
			position
		)
	end
end


local function scheduleClashStartEffects(
	clashId: number,
	userIdA: number,
	userIdB: number,
	startAt: number
)

	local delaySeconds =
		math.max(
			0,
			startAt
			- workspace:
			GetServerTimeNow()
		)


	task.delay(
		delaySeconds,
		function()

			-- Sound and camera shake are intentionally fired from the SAME
			-- callback so both begin on the clash start frame.
			playClashStartSound(
				clashId,
				userIdA,
				userIdB
			)


			playClashCameraShake(
				clashId,
				userIdA,
				userIdB
			)
		end
	)
end


local function emitDust(
	character: Model,
	landing: boolean
)

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA(
			"BasePart"
		)
			or not shouldRenderVFX(
				root.Position
			) then

		return
	end


	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}


	local result =
		workspace:
		Raycast(
			root.Position
			+ Vector3.new(
				0,
				1.0,
				0
			),
			Vector3.new(
				0,
				-8,
				0
			),
			params
		)


	if not result
		or result.Material ==
		Enum.Material.Water then

		return
	end


	local dustColor =
		materialColor(
			result
		)


	-- During the deterministic CFrame slide AssemblyLinearVelocity is often
	-- intentionally zero. Character LookVector points back toward the rival,
	-- which is exactly the trailing direction of the slide.
	local trailDirection =
		horizontalUnit(
			root.CFrame.LookVector,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local anchor =
		Instance.new(
			"Part"
		)

	anchor.Name =
		landing
		and "ClashLandDust"
		or "ClashSlideDust"

	anchor.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)

	anchor.Transparency =
		1

	anchor.Anchored =
		true

	anchor.CanCollide =
		false

	anchor.CanTouch =
		false

	anchor.CanQuery =
		false

	anchor.CastShadow =
		false


	anchor.CFrame =
		CFrame.new(
			result.Position
			+ result.Normal
			* 0.12
			+ trailDirection
			* (
				landing
				and 0.15
				or 0.40
			)
		)

	anchor.Parent =
		workspace


	local attachment =
		Instance.new(
			"Attachment"
		)

	attachment.Parent =
		anchor


	local emitter =
		Instance.new(
			"ParticleEmitter"
		)

	emitter.Texture =
		"rbxasset://textures/particles/smoke_main.dds"

	emitter.Enabled =
		false

	emitter.Rate =
		0

	emitter.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	emitter.Rotation =
		NumberRange.new(
			-180,
			180
		)

	emitter.RotSpeed =
		NumberRange.new(
			-70,
			70
		)

	emitter.Drag =
		3.0

	emitter.LightInfluence =
		0.22


	emitter.Color =
		ColorSequence.new(
			dustColor:Lerp(
				Color3.fromRGB(
					230,
					226,
					216
				),
				0.25
			),
			dustColor
		)


	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.14
			),

			NumberSequenceKeypoint.new(
				0.55,
				0.52
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})


	if landing then

		emitter.Lifetime =
			NumberRange.new(
				0.45,
				0.72
			)

		emitter.Speed =
			NumberRange.new(
				3.5,
				7.0
			)

		emitter.Size =
			NumberSequence.new({
				NumberSequenceKeypoint.new(
					0,
					0.55
				),

				NumberSequenceKeypoint.new(
					0.5,
					1.65
				),

				NumberSequenceKeypoint.new(
					1,
					2.30
				),
			})

		emitter.Acceleration =
			trailDirection
			* 5
			+ result.Normal
			* 3.5

	else

		emitter.Lifetime =
			NumberRange.new(
				0.28,
				0.48
			)

		emitter.Speed =
			NumberRange.new(
				1.8,
				4.0
			)

		emitter.Size =
			NumberSequence.new({
				NumberSequenceKeypoint.new(
					0,
					0.32
				),

				NumberSequenceKeypoint.new(
					0.55,
					0.85
				),

				NumberSequenceKeypoint.new(
					1,
					1.25
				),
			})

		emitter.Acceleration =
			trailDirection
			* 6
			+ result.Normal
			* 1.7
	end


	emitter.Parent =
		attachment


	emitter:
		Emit(
			landing
			and 20
			or 7
		)


	Debris:
		AddItem(
			anchor,
			1.5
		)
end


local function emitForUserIds(
	userIdA: number,
	userIdB: number,
	landing: boolean
)

	for _,
		userId in ipairs({
			userIdA,
			userIdB,
		}) do

		local player =
			playerFromUserId(
				userId
			)

		local character =
			player
			and player.Character


		if character then

			emitDust(
				character,
				landing
			)
		end
	end
end


-- =========================
-- LOCAL CLASH CLEANUP
-- =========================

local function finishLocalClash(
	reason: string
)

	local state =
		activeClash

	if not state then
		return
	end


	activeClash =
		nil

	hitstopToken +=
		1


	state.arcActive =
		false

	state.slideActive =
		false


	if state.track
		and state.track.IsPlaying then

		state.track:
			Stop(
				0.055
			)
	end


	if state.root
		and state.root.Parent then

		state.root.AssemblyLinearVelocity =
			Vector3.zero

		state.root.AssemblyAngularVelocity =
			Vector3.zero
	end


	if state.humanoid
		and state.humanoid.Parent then

		state.humanoid.AutoRotate =
			state.savedAutoRotate
	end


	if state.character
		and state.character.Parent then

		state.character:SetAttribute(
			"IsClashing",
			false
		)

		state.character:SetAttribute(
			"ClashPhase",
			"None"
		)
	end


	if DEBUG then

		print(
			"[ClashClient v2.2] END",
			state.id,
			reason
		)
	end
end


-- =========================
-- MOTION MARKER HELPERS
-- =========================

local function ensureLandingPosition(
	state: any
)

	if state.landPosition then
		return
	end


	state.landPosition =
		state.impactPosition
		+ state.away
		* ARC_HORIZONTAL_DISTANCE
end


local function snapToLanding(
	state: any
)

	ensureLandingPosition(
		state
	)


	if not state.landPosition then
		return
	end


	zeroLocalMotion(
		state
	)


	faceTowardAxis(
		state.root,
		state.landPosition,
		state.toward
	)
end


local function snapToFinal(
	state: any
)

	ensureLandingPosition(
		state
	)


	if not state.landPosition then
		return
	end


	local finalPosition =
		state.landPosition
		+ state.away
		* SLIDE_DISTANCE


	zeroLocalMotion(
		state
	)


	faceTowardAxis(
		state.root,
		finalPosition,
		state.toward
	)


	state.finalPosition =
		finalPosition
end


-- =========================
-- HITSTOP
-- =========================

local function performHitstop(
	state: any
)

	if activeClash ~=
		state
		or not state.track
		or not state.track.IsPlaying then

		return
	end


	hitstopToken +=
		1

	local token =
		hitstopToken


	state.track:
		AdjustSpeed(
			0
		)


	state.character:SetAttribute(
		"ClashPhase",
		"ImpactFreeze"
	)


	if DEBUG then

		print(
			"[ClashClient v2.2] HITSTOP",
			state.id,
			HITSTOP_DURATION
		)
	end


	task.delay(
		HITSTOP_DURATION,
		function()

			if activeClash ~=
				state
				or token ~=
				hitstopToken
				or not state.track
				or not state.track.IsPlaying then

				return
			end


			state.track:
				AdjustSpeed(
					1
				)


			state.character:SetAttribute(
				"ClashPhase",
				"Compression"
			)
		end
	)
end


-- =========================
-- MARKERS
-- =========================

local function sendMarker(
	state: any,
	name: string
)

	if state.markerSeen[
		name
		] then

		return
	end


	state.markerSeen[
	name
	] =
		true


	clashEvent:
		FireServer(
			"Marker",
			state.id,
			name
		)


	if DEBUG then

		print(
			"[ClashClient v2.2] MARKER",
			state.id,
			name,
			"trackTime",
			string.format(
				"%.3f",
				state.track.TimePosition
			)
		)
	end
end


local function handleImpact(
	state: any,
	fromFallback: boolean
)

	if activeClash ~=
		state
		or state.markerSeen.ClashImpact then

		return
	end


	sendMarker(
		state,
		"ClashImpact"
	)


	local extent,
		legName =
		computeOwnKickExtent(
			state
		)


	if extent then

		clashEvent:
			FireServer(
				"FootExtent",
				state.id,
				extent
			)
	end


	if DEBUG then

		print(
			"[ClashClient v2.2] FOOT REPORT",
			state.id,
			legName
				or "NONE",
			extent
				and string.format(
					"%.3f",
					extent
				)
				or "nil",
			fromFallback
				and "fallback"
				or "marker"
		)
	end


	performHitstop(
		state
	)
end


local function connectTrackMarkers(
	state: any
)

	local track =
		state.track


	track:
		GetMarkerReachedSignal(
			"ClashImpact"
		):
		Connect(
			function()

				handleImpact(
					state,
					false
				)
			end
		)


	track:
		GetMarkerReachedSignal(
			"ClashResolve"
		):
		Connect(
			function()

				if activeClash ~=
					state
					or state.markerSeen.ClashResolve then

					return
				end


				sendMarker(
					state,
					"ClashResolve"
				)


				state.character:SetAttribute(
					"ClashPhase",
					"Arc"
				)


				state.arcActive =
				true

				state.slideActive =
				false

				state.arcTrackStart =
				track.TimePosition


				-- ContactAligned is expected to have happened during hitstop.
				-- Use the ACTUAL root position at ClashResolve as the origin so
				-- the approved 24-stud travel starts from exact foot contact.
				state.impactPosition =
				state.root.Position

				state.landPosition =
				nil
			end
		)


	track:
		GetMarkerReachedSignal(
			"LandImpact"
		):
		Connect(
			function()

				if activeClash ~=
					state
					or state.markerSeen.LandImpact then

					return
				end


				sendMarker(
					state,
					"LandImpact"
				)


				state.arcActive =
				false


				state.character:SetAttribute(
					"ClashPhase",
					"Landing"
				)


				snapToLanding(
					state
				)
			end
		)


	track:
		GetMarkerReachedSignal(
			"SlideStart"
		):
		Connect(
			function()

				if activeClash ~=
					state
					or state.markerSeen.SlideStart then

					return
				end


				sendMarker(
					state,
					"SlideStart"
				)


				state.arcActive =
				false

				state.slideActive =
				true

				state.slideTrackStart =
				track.TimePosition


				state.character:SetAttribute(
					"ClashPhase",
					"Sliding"
				)


				-- LandImpact and SlideStart are authored on the same frame.
				-- This remains correct regardless of signal callback order.
				snapToLanding(
					state
				)
			end
		)


	track:
		GetMarkerReachedSignal(
			"SlideEnd"
		):
		Connect(
			function()

				if activeClash ~=
					state
					or state.markerSeen.SlideEnd then

					return
				end


				sendMarker(
					state,
					"SlideEnd"
				)


				state.arcActive =
				false

				state.slideActive =
				false


				snapToFinal(
					state
				)


				state.character:SetAttribute(
					"ClashPhase",
					"Recovery"
				)
			end
		)


	track:
		GetMarkerReachedSignal(
			"ClashEnd"
		):
		Connect(
			function()

				if activeClash ~=
					state
					or state.markerSeen.ClashEnd then

					return
				end


				sendMarker(
					state,
					"ClashEnd"
				)


				state.arcActive =
				false

				state.slideActive =
				false


				snapToFinal(
					state
				)


				state.character:SetAttribute(
					"ClashPhase",
					"Ending"
				)
			end
		)


	track.Ended:
		Connect(
			function()

				if activeClash ~=
					state then

					return
				end


				state.arcActive =
				false

				state.slideActive =
				false


				snapToFinal(
					state
				)


				clashEvent:
				FireServer(
					"ClientEnded",
					state.id
				)
			end
		)
end


-- =========================
-- BEGIN LOCAL PARTICIPANT
-- =========================

local function beginParticipantClash(
	clashId: number,
	userIdA: number,
	userIdB: number,
	startAt: number,
	animationId: string,
	axisFromServer: Vector3
)

	if localPlayer.UserId ~=
		userIdA
		and localPlayer.UserId ~=
		userIdB then

		return
	end


	finishLocalClash(
		"Replaced"
	)


	local character,
		humanoid,
		root,
		animator =
		getPlayerCharacterParts(
			localPlayer
		)


	if not character
		or not humanoid
		or not root
		or not animator then

		warn(
			"[ClashClient v2.2] Local character unavailable."
		)

		return
	end


	if animationId ~=
		CLASH_ANIMATION_ID then

		warn(
			"[ClashClient v2.2] Animation mismatch:",
			animationId,
			"expected",
			CLASH_ANIMATION_ID
		)
	end


	local isA =
		localPlayer.UserId ==
		userIdA


	local axis =
		horizontalUnit(
			axisFromServer,
			root.CFrame.LookVector
		)


	local toward =
		isA
		and axis
		or -axis


	local away =
		-toward


	local track =
		loadClashTrack(
			animator
		)


	local state = {
		id = clashId,

		userIdA = userIdA,
		userIdB = userIdB,

		isA = isA,

		axis = axis,
		toward = toward,
		away = away,

		character = character,
		humanoid = humanoid,
		root = root,
		animator = animator,
		track = track,

		savedAutoRotate =
			humanoid.AutoRotate,

		markerSeen = {
			ClashImpact = false,
			ClashResolve = false,
			LandImpact = false,
			SlideStart = false,
			SlideEnd = false,
			ClashEnd = false,
		},

		arcActive = false,
		slideActive = false,

		arcTrackStart = 0,
		slideTrackStart = 0,

		impactPosition = root.Position,
		landPosition = nil,
		finalPosition = nil,
	}


	activeClash =
		state


	humanoid.AutoRotate =
		false


	character:SetAttribute(
		"IsClashing",
		true
	)

	character:SetAttribute(
		"ClashPhase",
		"Pending"
	)


	connectTrackMarkers(
		state
	)


	local delaySeconds =
		math.max(
			0,
			startAt
			- workspace:
			GetServerTimeNow()
		)


	if DEBUG then

		print(
			"[ClashClient v2.2] BEGIN",
			clashId,
			isA
				and "A"
				or "B",
			"syncDelay",
			string.format(
				"%.3f",
				delaySeconds
			)
		)
	end


	task.delay(
		delaySeconds,
		function()

			if activeClash ~=
				state then

				return
			end


			zeroLocalMotion(
				state
			)


			state.character:SetAttribute(
				"ClashPhase",
				"Impact"
			)


			track:
				Play(
					0.025,
					1,
					1
				)


			local fallbackToken =
				hitstopToken


			task.delay(
				IMPACT_FALLBACK_DELAY,
				function()

					if activeClash ~=
						state
						or fallbackToken ~=
						hitstopToken
						or not track.IsPlaying
						or state.markerSeen.ClashImpact then

						return
					end


					if track.TimePosition <
						0.13 then

						if DEBUG then

							warn(
								"[ClashClient v2.2] ClashImpact frame-0 fallback"
							)
						end


						handleImpact(
							state,
							true
						)
					end
				end
			)
		end
	)
end


-- =========================
-- LOCAL MOTION LOOP
-- =========================

RunService.RenderStepped:
	Connect(
		function()

			local state =
			activeClash


			if state
				and state.root
				and state.root.Parent
				and state.track then

				zeroLocalMotion(
					state
				)


				if state.arcActive then

					local alpha =
					math.clamp(
						(
							state.track.TimePosition
							- state.arcTrackStart
						)
						/ ARC_ANIMATION_DURATION,
						0,
						1
					)


					local horizontalAlpha =
					1
					- math.pow(
						1 - alpha,
						ARC_HORIZONTAL_EASE_POWER
					)


					local horizontalDistance =
					ARC_HORIZONTAL_DISTANCE
					* horizontalAlpha


					local arcY =
					4
					* ARC_APEX_HEIGHT
					* alpha
					* (
						1
						- alpha
					)


					local position =
					state.impactPosition
					+ state.away
					* horizontalDistance
					+ Vector3.new(
						0,
						arcY,
						0
					)


					faceTowardAxis(
						state.root,
						position,
						state.toward
					)


				elseif state.slideActive then

					ensureLandingPosition(
						state
					)


					if state.landPosition then

						local alpha =
						math.clamp(
							(
								state.track.TimePosition
								- state.slideTrackStart
							)
							/ SLIDE_ANIMATION_DURATION,
							0,
							1
						)


						-- Approved slide: fast initial drag, progressively
						-- decelerating to zero exactly at frame 80.
						local eased =
						1
						- (
							1
							- alpha
						)
						* (
							1
							- alpha
						)


						local position =
						state.landPosition
						+ state.away
						* (
							SLIDE_DISTANCE
							* eased
						)


						faceTowardAxis(
							state.root,
							position,
							state.toward
						)
					end
				end
			end


			-- Global slide dust is rendered locally on every client.
			local now =
			time()


			for _,
				vfxState in pairs(
					slideVFX
				) do

				if now <
					vfxState.nextEmitAt then

					continue
				end


				vfxState.nextEmitAt =
				now
				+ SLIDE_DUST_INTERVAL


				emitForUserIds(
					vfxState.userIdA,
					vfxState.userIdB,
					false
				)
			end
		end
	)


-- =========================
-- SERVER EVENTS
-- =========================

clashEvent.OnClientEvent:
	Connect(
		function(
			action: string,
			arg1: any,
			arg2: any,
			arg3: any,
			arg4: any,
			arg5: any,
			arg6: any
		)

			if action ==
				"Begin" then

				scheduleClashStartEffects(
					arg1 :: number,
					arg2 :: number,
					arg3 :: number,
					arg4 :: number
				)


				beginParticipantClash(
					arg1 :: number,
					arg2 :: number,
					arg3 :: number,
					arg4 :: number,
					arg5 :: string,
					arg6 :: Vector3
				)

				return
			end


			if action ==
				"ContactAligned" then

				local clashId =
				arg1 :: number

				local cframeA =
				arg2 :: CFrame

				local cframeB =
				arg3 :: CFrame

				local distance =
				arg4 :: number


				-- Apply the same authoritative one-frame correction locally to
				-- BOTH rigs. This gives every participant/spectator the exact
				-- approved foot-to-foot freeze immediately.
				local state =
				activeClash


				if state
					and state.id ==
					clashId then

					if state.isA then

						state.root.CFrame =
						cframeA

					else

						state.root.CFrame =
						cframeB
					end


					zeroLocalMotion(
						state
					)
				end


				if state
					and state.id ==
					clashId then

					local opponentUserId =
					state.isA
					and state.userIdB
					or state.userIdA

					local opponent =
					playerFromUserId(
						opponentUserId
					)

					local opponentRoot =
					opponent
					and opponent.Character
					and opponent.Character:
					FindFirstChild(
						"HumanoidRootPart"
					)


					if opponentRoot
						and opponentRoot:IsA(
							"BasePart"
						) then

						opponentRoot.CFrame =
						state.isA
						and cframeB
						or cframeA
					end
				end


				if DEBUG then

					print(
						"[ClashClient v2.2] CONTACT ALIGNED",
						clashId,
						"distance",
						string.format(
							"%.3f",
							distance
						)
					)
				end


				return
			end


			if action ==
				"VFX" then

				local vfxType =
				arg1 :: string

				local clashId =
				arg2 :: number

				local userIdA =
				arg3 :: number

				local userIdB =
				arg4 :: number


				if vfxType ==
					"ClashImpact" then

					local impactCFrame =
					arg5


					if typeof(impactCFrame) ==
						"CFrame" then

						emitClashImpactVFX(
							impactCFrame
						)
					end


				elseif vfxType ==
					"LandImpact" then

					emitForUserIds(
						userIdA,
						userIdB,
						true
					)


				elseif vfxType ==
					"SlideStart" then

					slideVFX[
					clashId
					] = {
						userIdA = userIdA,
						userIdB = userIdB,
						nextEmitAt = 0,
					}


				elseif vfxType ==
					"SlideEnd" then

					slideVFX[
					clashId
					] =
					nil
				end


				return
			end


			if action ==
				"End" then

				local clashId =
				arg1 :: number

				local reason =
				tostring(
					arg2
				)


				slideVFX[
				clashId
				] =
				nil


				if activeClash
					and activeClash.id ==
					clashId then

					finishLocalClash(
						reason
					)
				end
			end
		end
	)


localPlayer.CharacterRemoving:
	Connect(
		function()

			finishLocalClash(
				"CharacterRemoving"
			)
		end
	)


script.Destroying:
	Connect(
		function()

			RunService:
			UnbindFromRenderStep(
				CAMERA_SHAKE_BIND_NAME
			)


			finishLocalClash(
				"ScriptDestroy"
			)
		end
	)


print(
	"[ClashClient] READY v2.2"
		.. " | Animation=110715673180255"
		.. " | SameAnimationBothPlayers=ON"
		.. " | FootExtentAutoAlign=SERVER"
		.. " | Hitstop=0.075"
		.. " | ArcDistance=24"
		.. " | ArcApex=5.4"
		.. " | SlideDistance=8"
		.. " | Land+SlideDust=ON"
		.. " | ClashStartSound=96478382958151"
		.. " | ClashCameraShake=ON"
		.. " | CombatServerReplacement=NO"
		.. " | MULTIPLAYER_CLIENT_REQUIRED=YES"
		.. " | ServerHandshakeRequired=v2.5"
)
