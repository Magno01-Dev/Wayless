--!strict
-- CombatImpactVFXController v2.1 - Reduced Punch HitVFX Scale
-- StarterPlayer > StarterPlayerScripts > CombatImpactVFXController [LocalScript]
--
-- M1 hit visuals use ReplicatedStorage > VFX > HitVFX templates.
-- M1_1: Punch-01
-- M1_2: Punch-02
-- M1_3: Punch-03
-- M1_4: Punch-04 if present, otherwise Punch-03 fallback.
-- M1_5: Shoot-01.
-- Block: Shield-01.
-- GuardBreak: Shield-Break-01.
-- Produced templates fully replace the old procedural visuals for these events.
-- Runtime scaling is supported; you do NOT need to resize the source assets manually.
--
-- Server-confirmed event types:
-- Hit
-- HeavyHit
-- Block
-- GuardBreak
--
-- Design:
-- atmospheric / clean / anime
-- no outline
-- short-lived readable impact shapes
-- subtle camera impulse
--
-- Camera impulse is disabled while SurfaceWalking so it cannot fight the
-- wall/ceiling camera controller.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local TweenService =
	game:GetService("TweenService")

local Debris =
	game:GetService("Debris")

local RunService =
	game:GetService("RunService")


local player =
	Players.LocalPlayer


-- =========================
-- PRODUCED HIT VFX TEMPLATES
-- =========================

local vfxFolder =
	ReplicatedStorage:
	WaitForChild(
		"VFX"
	)

local hitVFXFolder =
	vfxFolder:
	WaitForChild(
		"HitVFX"
	)

local punch01Template =
	hitVFXFolder:
	WaitForChild(
		"Punch-01"
	)

local punch02Template =
	hitVFXFolder:
	WaitForChild(
		"Punch-02"
	)

local punch03Template =
	hitVFXFolder:
	WaitForChild(
		"Punch-03"
	)

-- Optional authored VFX for the fourth normal hit.
-- Your current folder only contains Punch-01/02/03, so M1_4 falls back
-- to Punch-03 until you add a Punch-04 template.
local punch04Template =
	hitVFXFolder:
	FindFirstChild(
		"Punch-04"
	)
	or punch03Template

local shootTemplate =
	hitVFXFolder:
	WaitForChild(
		"Shoot-01"
	)

local shieldTemplate =
	hitVFXFolder:
	WaitForChild(
		"Shield-01"
	)

local shieldBreakTemplate =
	hitVFXFolder:
	WaitForChild(
		"Shield-Break-01"
	)

local m1Templates: { [number]: Instance } = {
	[1] = punch01Template,
	[2] = punch02Template,
	[3] = punch03Template,
	[4] = punch04Template,
	[5] = shootTemplate,
}

if HIT_VFX_RUNTIME_DEBUG then
	print(
		"[CombatImpactVFX] ASSET PATH OK:",
		hitVFXFolder:GetFullName()
	)

	for comboIndex = 1, 5 do
		local template = m1Templates[comboIndex]

		print(
			"[CombatImpactVFX] M1 TEMPLATE",
			comboIndex,
			template and template:GetFullName() or "MISSING"
		)
	end
end

-- Easy tuning if the authored templates face a different axis.
-- Keep identity first. If the pack is rotated, change only this CFrame.
local M1_TEMPLATE_ROTATION_OFFSET =
	CFrame.new()

-- How long continuously-enabled emitters / beams / trails stay active.
-- One-shot disabled ParticleEmitters are burst with :Emit() immediately.
local M1_TEMPLATE_ACTIVE_TIME =
	0.12

local M1_TEMPLATE_MIN_CLEANUP =
	1.25

-- Runtime visual scale. These values scale the authored geometry plus the
-- visual size/width of ParticleEmitters, Beams and Trails.
-- Keep the source assets untouched in ReplicatedStorage and tune here.
local PUNCH_TEMPLATE_SCALE =
	1.00

local SHOOT_TEMPLATE_SCALE =
	1.20

local SHIELD_TEMPLATE_SCALE =
	1.65

local SHIELD_BREAK_TEMPLATE_SCALE =
	1.85

-- Particle motion can be scaled as well so a larger burst occupies more space.
-- 1.00 preserves the authored particle travel speed.
local PARTICLE_MOTION_SCALE =
	1.35

-- Prints the real class/contents of each template the first time it is used.
-- Leave ON while diagnosing invisible assets, then set false.
local PRODUCED_TEMPLATE_DEBUG =
	true

-- Keep these ON until the HitVFX pipeline is confirmed.
local HIT_VFX_RUNTIME_DEBUG =
	true

-- One Heartbeat delay after parenting makes burst emission reliable for
-- freshly-cloned Attachment/ParticleEmitter packs.
local WAIT_ONE_HEARTBEAT_BEFORE_EMIT =
	true

-- Runtime-only visibility normalization for authored particle packs.
-- The original assets in ReplicatedStorage are NEVER modified.
local NORMALIZE_HIT_PARTICLE_VISIBILITY =
	true

local HIT_PARTICLE_MIN_BRIGHTNESS =
	2.0

local HIT_PARTICLE_MIN_LIGHT_EMISSION =
	0.80

local HIT_PARTICLE_MIN_ZOFFSET =
	1.0

local HIT_PARTICLE_MIN_VISIBLE_SIZE =
	1.35

local HIT_PARTICLE_MAX_AUTO_SIZE_MULTIPLIER =
	8.0

local HIT_PARTICLE_MIN_BURST =
	18


-- =========================
-- SETTINGS
-- =========================

local MAX_VFX_DISTANCE =
	135

local MAX_SHAKE_DISTANCE =
	48

local CAMERA_SHAKE_ENABLED =
	true

-- Normal hits and regular blocks intentionally use NO camera shake.
local NORMAL_SHAKE_ROTATION =
	0

-- Only finishers / breaks keep a tiny impulse for impact weight.
local HEAVY_SHAKE_ROTATION =
	math.rad(0.10)

local GUARD_BREAK_SHAKE_ROTATION =
	math.rad(0.055)

local SHAKE_DURATION =
	0.045


-- =========================
-- COLORS
-- =========================

local HIT_CORE =
	Color3.fromRGB(
		245,
		242,
		232
	)

local HIT_SPARK =
	Color3.fromRGB(
		220,
		225,
		228
	)

local HEAVY_CORE =
	Color3.fromRGB(
		255,
		236,
		212
	)

local HEAVY_ACCENT =
	Color3.fromRGB(
		194,
		47,
		34
	)

local BLOCK_CORE =
	Color3.fromRGB(
		224,
		235,
		238
	)

local BLOCK_ACCENT =
	Color3.fromRGB(
		123,
		147,
		158
	)

local BREAK_CORE =
	Color3.fromRGB(
		255,
		226,
		160
	)

local BREAK_ACCENT =
	Color3.fromRGB(
		196,
		65,
		38
	)

local SMOKE_COLOR =
	Color3.fromRGB(
		178,
		182,
		188
	)

local SMOKE_ACCENT =
	Color3.fromRGB(
		208,
		212,
		218
	)


-- =========================
-- HELPERS
-- =========================

local function safeUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	if vector.Magnitude >
		0.001 then

		return vector.Unit
	end

	return fallback
end


local function getCameraDistance(
	position: Vector3
): number

	local camera =
		workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	return (
		camera.CFrame.Position
		- position
	).Magnitude
end


local function createEffectPart(
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	transparency: number
): Part

	local part =
		Instance.new("Part")

	part.Name =
		name

	part.Anchored =
		true

	part.CanCollide =
		false

	part.CanTouch =
		false

	part.CanQuery =
		false

	part.CastShadow =
		false

	part.Material =
		Enum.Material.Neon

	part.Color =
		color

	part.Transparency =
		transparency

	part.Size =
		size

	part.CFrame =
		CFrame.new(
			position
		)

	part.Parent =
		workspace


	Debris:AddItem(
		part,
		0.65
	)


	return part
end


local function makeFlash(
	position: Vector3,
	color: Color3,
	startSize: number,
	endSize: number,
	duration: number,
	startTransparency: number?
)

	local flash =
		createEffectPart(
			"CombatImpactFlash",
			position,
			Vector3.new(
				startSize,
				startSize,
				startSize
			),
			color,
			startTransparency
			or 0.12
		)

	flash.Shape =
		Enum.PartType.Ball


	TweenService:
		Create(
			flash,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Size =
				Vector3.new(
					endSize,
					endSize,
					endSize
				),

				Transparency =
				1
			}
		):
		Play()
end


local function makeStreak(
	position: Vector3,
	direction: Vector3,
	color: Color3,
	length: number,
	width: number,
	travel: number,
	duration: number,
	startTransparency: number
)

	local unitDirection =
		safeUnit(
			direction,
			Vector3.yAxis
		)


	local startPosition =
		position
		+ unitDirection
		* (
			length * 0.35
		)


	local streak =
		createEffectPart(
			"CombatImpactStreak",
			startPosition,
			Vector3.new(
				width,
				width,
				length
			),
			color,
			startTransparency
		)


	streak.CFrame =
		CFrame.lookAt(
			startPosition,
			startPosition
			+ unitDirection
		)


	local endPosition =
		startPosition
		+ unitDirection
		* travel


	TweenService:
		Create(
			streak,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				CFrame =
				CFrame.lookAt(
					endPosition,
					endPosition
					+ unitDirection
				),

				Size =
				Vector3.new(
					width * 0.25,
					width * 0.25,
					length * 0.55
				),

				Transparency =
				1
			}
		):
		Play()
end


local function buildBasis(
	impactDirection: Vector3
): (Vector3, Vector3, Vector3)

	local forward =
		safeUnit(
			impactDirection,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local referenceUp =
		Vector3.yAxis


	if math.abs(
		forward:
			Dot(
				referenceUp
			)
		) > 0.90 then

		referenceUp =
			Vector3.xAxis
	end


	local right =
		safeUnit(
			forward:
			Cross(
				referenceUp
			),
			Vector3.xAxis
		)


	local up =
		safeUnit(
			right:
			Cross(
				forward
			),
			Vector3.yAxis
		)


	return forward,
		right,
		up
end


local function emitRadialSparks(
	position: Vector3,
	impactDirection: Vector3,
	color: Color3,
	count: number,
	baseLength: number,
	baseTravel: number,
	duration: number
)

	local forward,
		right,
		up =
		buildBasis(
			impactDirection
		)


	for index = 1,
		count do

		local angle =
			(
				(index - 1)
				/ count
			)
			* math.pi
			* 2


		local radial =
			right
			* math.cos(
				angle
			)
			+ up
			* math.sin(
				angle
			)


		local outward =
			safeUnit(
				radial
				+ forward
				* (
					0.10
					+ (
						index
						% 3
					)
					* 0.08
				),
				radial
			)


		local lengthVariation =
			0.82
			+ (
				(index % 4)
				* 0.09
			)


		makeStreak(
			position,
			outward,
			color,
			baseLength
				* lengthVariation,
			0.055,
			baseTravel
				* lengthVariation,
			duration,
			0.08
		)
	end
end


local function emitCrossSlash(
	position: Vector3,
	impactDirection: Vector3,
	color: Color3,
	scale: number
)

	local _forward,
		right,
		up =
		buildBasis(
			impactDirection
		)


	local slashA =
		safeUnit(
			right
			+ up * 0.65,
			right
		)

	local slashB =
		safeUnit(
			-right
			+ up * 0.72,
			-right
		)


	makeStreak(
		position,
		slashA,
		color,
		1.75 * scale,
		0.10 * scale,
		0.55 * scale,
		0.13,
		0.03
	)


	makeStreak(
		position,
		slashB,
		color,
		1.65 * scale,
		0.09 * scale,
		0.50 * scale,
		0.13,
		0.06
	)
end


local function emitBlockPlate(
	position: Vector3,
	impactDirection: Vector3,
	color: Color3,
	scale: number
)

	local forward,
		right,
		up =
		buildBasis(
			impactDirection
		)


	for index = -1,
		1 do

		local lineDirection =
			safeUnit(
				up
				+ right
				* index
				* 0.48,
				up
			)


		makeStreak(
			position
			- forward * 0.12,
			lineDirection,
			color,
			1.15 * scale,
			0.10 * scale,
			0.18 * scale,
			0.11,
			0.15
		)
	end
end


local function emitGuardBreakFragments(
	position: Vector3,
	impactDirection: Vector3
)

	local forward,
		right,
		up =
		buildBasis(
			impactDirection
		)


	for index = 1,
		10 do

		local side =
			if index % 2 == 0
			then 1
			else -1


		local direction =
			safeUnit(
				forward * 0.28
				+ right
				* side
				* (
					0.35
					+ (index % 3)
					* 0.16
				)
				+ up
				* (
					-0.55
					+ (index % 5)
					* 0.28
				),
				up
			)


		makeStreak(
			position,
			direction,
			if index % 3 == 0
				then BREAK_ACCENT
				else BREAK_CORE,
			1.35
				+ (index % 3)
				* 0.18,
			0.075,
			1.00
				+ (index % 4)
				* 0.18,
			0.18,
			0.04
		)
	end
end


-- =========================
-- CAMERA-FACING IMPACT BURST
-- =========================
--
-- The 3D Neon geometry is intentionally short and thin.
-- v1.1 adds a very brief world-space Billboard burst so the contact is still
-- readable when the character body would otherwise cover the 3D pieces.
--
-- No image/texture asset is used: this is only Frames.

local function makeImpactGlyph(
	position: Vector3,
	primaryColor: Color3,
	accentColor: Color3,
	scale: number,
	rayCount: number,
	duration: number
)
	local anchor =
		Instance.new("Part")

	anchor.Name =
		"CombatImpactGlyphAnchor"

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

	anchor.Size =
		Vector3.new(
			0.05,
			0.05,
			0.05
		)

	anchor.CFrame =
		CFrame.new(
			position
		)

	anchor.Parent =
		workspace


	local billboard =
		Instance.new("BillboardGui")

	billboard.Name =
		"ImpactGlyph"

	billboard.Adornee =
		anchor

	billboard.AlwaysOnTop =
		true

	billboard.MaxDistance =
		115

	billboard.Size =
		UDim2.fromOffset(
			math.floor(
				92 * scale
			),
			math.floor(
				92 * scale
			)
		)

	billboard.Parent =
		anchor


	local centerRing =
		Instance.new("Frame")

	centerRing.Name =
		"CenterRing"

	centerRing.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)

	centerRing.Position =
		UDim2.fromScale(
			0.5,
			0.5
		)

	centerRing.Size =
		UDim2.fromOffset(
			math.floor(
				14 * scale
			),
			math.floor(
				14 * scale
			)
		)

	centerRing.BackgroundTransparency =
		1

	centerRing.BorderSizePixel =
		0

	centerRing.Rotation =
		45

	centerRing.ZIndex =
		4

	centerRing.Parent =
		billboard


	local ringCorner =
		Instance.new("UICorner")

	ringCorner.CornerRadius =
		UDim.new(
			1,
			0
		)

	ringCorner.Parent =
		centerRing


	local ringStroke =
		Instance.new("UIStroke")

	ringStroke.Color =
		primaryColor

	ringStroke.Thickness =
		math.max(
			1.2,
			2.2 * scale
		)

	ringStroke.Transparency =
		0.22

	ringStroke.Parent =
		centerRing


	for index = 1,
		rayCount do

		local angle =
			(index - 1)
			/ rayCount
			* 360


		local ray =
			Instance.new("Frame")

		ray.Name =
			"Ray_"
			.. tostring(
				index
			)

		ray.AnchorPoint =
			Vector2.new(
				0,
				0.5
			)

		ray.Position =
			UDim2.fromScale(
				0.5,
				0.5
			)

		ray.Size =
			UDim2.fromOffset(
				math.floor(
					22 * scale
				),
				math.max(
					1,
					math.floor(
						2.0 * scale
					)
				)
			)

		ray.BackgroundColor3 =
			if index % 3 == 0
			then accentColor
			else primaryColor

		ray.BackgroundTransparency =
			0.20

		ray.BorderSizePixel =
			0

		ray.Rotation =
			angle

		ray.ZIndex =
			3

		ray.Parent =
			billboard


		TweenService:
			Create(
				ray,
				TweenInfo.new(
					duration,
					Enum.EasingStyle.Quart,
					Enum.EasingDirection.Out
				),
				{
					Size =
					UDim2.fromOffset(
						math.floor(
							38 * scale
						),
						1
					),

					BackgroundTransparency =
					1
				}
			):
			Play()
	end


	TweenService:
		Create(
			centerRing,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Size =
				UDim2.fromOffset(
					math.floor(
						28 * scale
					),
					math.floor(
						28 * scale
					)
				),

				BackgroundTransparency =
				1
			}
		):
		Play()


	TweenService:
		Create(
			ringStroke,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Transparency =
				1,

				Thickness =
				math.max(
					0.6,
					1.4 * scale
				)
			}
		):
		Play()


	Debris:AddItem(
		anchor,
		duration + 0.08
	)
end


local function getAttackerArm(
	attackerUserId: number
): BasePart?
	if typeof(attackerUserId) ~= "number"
		or attackerUserId <= 0 then

		return nil
	end

	local attackerPlayer =
		Players:GetPlayerByUserId(
			attackerUserId
		)

	if not attackerPlayer then
		return nil
	end

	local character =
		attackerPlayer.Character

	if not character then
		return nil
	end

	return character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightHand")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("RightUpperArm")
end


local function emitArmSmokeTrail(
	attackerUserId: number,
	impactDirection: Vector3,
	heavy: boolean
)
	local arm =
		getAttackerArm(
			attackerUserId
		)

	if not arm then
		return
	end

	local basePosition =
		arm.Position
		+ arm.CFrame.UpVector * 0.05
		+ arm.CFrame.RightVector * 0.12

	local scale =
		if heavy then 1.0 else 0.82

	for index = 1, 2 do
		local anchor =
			Instance.new("Part")

		anchor.Name =
			"ArmSmokeAnchor"

		anchor.Anchored =
			true

		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.05, 0.05, 0.05)
		anchor.CFrame = CFrame.new(
			basePosition
				+ impactDirection * ((index - 1) * 0.18)
		)
		anchor.Parent = workspace

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ArmSmokeRing"
		billboard.Adornee = anchor
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 90
		billboard.Size = UDim2.fromOffset(
			math.floor((24 + index * 4) * scale),
			math.floor((24 + index * 4) * scale)
		)
		billboard.Parent = anchor

		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(0.55, 0.55)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ring

		local stroke = Instance.new("UIStroke")
		stroke.Color = if index == 1 then SMOKE_ACCENT else SMOKE_COLOR
		stroke.Thickness = if heavy then 2.1 else 1.7
		stroke.Transparency = 0.58 + index * 0.10
		stroke.Parent = ring

		TweenService:Create(
			ring,
			TweenInfo.new(
				0.18,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Size = UDim2.fromScale(
					0.95 + index * 0.12,
					0.95 + index * 0.12
				)
			}
		):Play()

		TweenService:Create(
			stroke,
			TweenInfo.new(
				0.18,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Transparency = 1,
				Thickness = 0.8
			}
		):Play()

		TweenService:Create(
			anchor,
			TweenInfo.new(
				0.18,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				CFrame = CFrame.new(
					anchor.Position
						+ impactDirection * (0.28 + index * 0.08)
				)
			}
		):Play()

		Debris:AddItem(anchor, 0.28)
	end
end


-- =========================
-- CAMERA IMPULSE
-- =========================

local activeShakeGeneration =
	0


local function playCameraImpulse(
	rotationMagnitude: number
)

	if not CAMERA_SHAKE_ENABLED then
		return
	end


	local character =
		player.Character


	if character
		and character:GetAttribute(
			"SurfaceWalking"
		) == true then

		return
	end


	local camera =
		workspace.CurrentCamera

	if not camera then
		return
	end


	activeShakeGeneration += 1

	local generation =
		activeShakeGeneration

	local startedAt =
		time()


	RunService:
		BindToRenderStep(
			"CombatImpactShake_"
			.. tostring(
				generation
			),
			Enum.RenderPriority.Camera.Value
			+ 5,
			function()

				local elapsed =
				time()
				- startedAt


				if elapsed >=
					SHAKE_DURATION then

					RunService:
					UnbindFromRenderStep(
						"CombatImpactShake_"
						.. tostring(
							generation
						)
					)

					return
				end


				local alpha =
				1
				- elapsed
				/ SHAKE_DURATION


				local phase =
				elapsed
				* 145


				local yaw =
				math.sin(
					phase
				)
				* rotationMagnitude
				* alpha


				local pitch =
				math.cos(
					phase * 1.31
				)
				* rotationMagnitude
				* 0.55
				* alpha


				local currentCamera =
				workspace.CurrentCamera


				if currentCamera then

					currentCamera.CFrame =
					currentCamera.CFrame
					* CFrame.Angles(
						pitch,
						yaw,
						0
					)
				end
			end
		)
end


-- =========================
-- PRODUCED TEMPLATE HELPERS
-- =========================

local function scaleNumberSequence(
	sequence: NumberSequence,
	scale: number
): NumberSequence

	local keypoints = {}

	for _, keypoint in ipairs(sequence.Keypoints) do
		table.insert(
			keypoints,
			NumberSequenceKeypoint.new(
				keypoint.Time,
				keypoint.Value * scale,
				keypoint.Envelope * scale
			)
		)
	end

	return NumberSequence.new(keypoints)
end


local function getProducedTemplateScale(
	templateName: string
): number

	if templateName == "Shoot-01" then
		return SHOOT_TEMPLATE_SCALE
	end

	if templateName == "Shield-01" then
		return SHIELD_TEMPLATE_SCALE
	end

	if templateName == "Shield-Break-01" then
		return SHIELD_BREAK_TEMPLATE_SCALE
	end

	return PUNCH_TEMPLATE_SCALE
end


local debuggedTemplates: { [string]: boolean } = {}

local function debugProducedTemplate(
	template: Instance,
	clone: Instance,
	scale: number
)

	if not PRODUCED_TEMPLATE_DEBUG
		or debuggedTemplates[template.Name] then
		return
	end

	debuggedTemplates[template.Name] = true

	local partCount = 0
	local attachmentCount = 0
	local emitterCount = 0
	local beamCount = 0
	local trailCount = 0

	local function countInstance(instance: Instance)
		if instance:IsA("BasePart") then
			partCount += 1
		elseif instance:IsA("Attachment") then
			attachmentCount += 1
		elseif instance:IsA("ParticleEmitter") then
			emitterCount += 1
		elseif instance:IsA("Beam") then
			beamCount += 1
		elseif instance:IsA("Trail") then
			trailCount += 1
		end
	end

	countInstance(clone)
	for _, descendant in ipairs(clone:GetDescendants()) do
		countInstance(descendant)
	end

	print(
		"[CombatImpactVFX] TEMPLATE",
		template.Name,
		"class",
		template.ClassName,
		"scale",
		scale,
		"parts",
		partCount,
		"attachments",
		attachmentCount,
		"emitters",
		emitterCount,
		"beams",
		beamCount,
		"trails",
		trailCount
	)

	if emitterCount == 0
		and beamCount == 0
		and trailCount == 0
		and partCount == 0 then

		warn(
			"[CombatImpactVFX] TEMPLATE HAS NO RENDERABLE CONTENT:",
			template:GetFullName()
		)
	end
end


local function scaleProducedTemplateVisuals(
	root: Instance,
	scale: number
)

	-- Model geometry + Attachment offsets are handled by Model:ScaleTo when possible.
	if root:IsA("Model") then
		root:ScaleTo(root:GetScale() * scale)
	elseif root:IsA("BasePart") then
		root.Size *= scale
	end

	local function scaleVisual(instance: Instance)
		if instance:IsA("ParticleEmitter") then
			instance.Size = scaleNumberSequence(instance.Size, scale)

			if PARTICLE_MOTION_SCALE ~= 1 then
				instance.Speed = NumberRange.new(
					instance.Speed.Min * PARTICLE_MOTION_SCALE,
					instance.Speed.Max * PARTICLE_MOTION_SCALE
				)
			end

		elseif instance:IsA("Beam") then
			instance.Width0 *= scale
			instance.Width1 *= scale

		elseif instance:IsA("Trail") then
			instance.WidthScale = scaleNumberSequence(
				instance.WidthScale,
				scale
			)

		elseif instance:IsA("PointLight")
			or instance:IsA("SpotLight") then
			instance.Range *= scale
		end
	end

	scaleVisual(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		scaleVisual(descendant)
	end
end


local function getNumberSequenceMaxValue(
	sequence: NumberSequence
): number

	local maximum =
		0

	for _, keypoint in ipairs(
		sequence.Keypoints
		) do
		maximum =
			math.max(
				maximum,
				keypoint.Value
			)
	end

	return maximum
end


local function getNumberSequenceMinValue(
	sequence: NumberSequence
): number

	local minimum =
		math.huge

	for _, keypoint in ipairs(
		sequence.Keypoints
		) do
		minimum =
			math.min(
				minimum,
				keypoint.Value
			)
	end

	if minimum == math.huge then
		return 0
	end

	return minimum
end


local function normalizeProducedParticleVisibility(
	emitter: ParticleEmitter
)
	if not NORMALIZE_HIT_PARTICLE_VISIBILITY then
		return
	end

	emitter.Brightness =
		math.max(
			emitter.Brightness,
			HIT_PARTICLE_MIN_BRIGHTNESS
		)

	emitter.LightEmission =
		math.max(
			emitter.LightEmission,
			HIT_PARTICLE_MIN_LIGHT_EMISSION
		)

	emitter.ZOffset =
		math.max(
			emitter.ZOffset,
			HIT_PARTICLE_MIN_ZOFFSET
		)

	local currentMaxSize =
		getNumberSequenceMaxValue(
			emitter.Size
		)

	if currentMaxSize >
		0
			and currentMaxSize <
			HIT_PARTICLE_MIN_VISIBLE_SIZE then

		local requiredMultiplier =
			math.clamp(
				HIT_PARTICLE_MIN_VISIBLE_SIZE
				/ currentMaxSize,
				1,
				HIT_PARTICLE_MAX_AUTO_SIZE_MULTIPLIER
			)

		emitter.Size =
			scaleNumberSequence(
				emitter.Size,
				requiredMultiplier
			)
	end

	-- Transparency values close to 1 mean the authored effect is effectively
	-- invisible. Only replace the curve when the clone has no readable frame.
	local minimumTransparency =
		getNumberSequenceMinValue(
			emitter.Transparency
		)

	if minimumTransparency >=
		0.90 then

		emitter.Transparency =
			NumberSequence.new({
				NumberSequenceKeypoint.new(
					0,
					0.04
				),
				NumberSequenceKeypoint.new(
					0.55,
					0.12
				),
				NumberSequenceKeypoint.new(
					1,
					1
				),
			})
	end
end


local function getEmitterBurstCount(
	emitter: ParticleEmitter
): number

	local attributeNames = {
		"EmitCount",
		"BurstCount",
		"Count",
	}

	for _, attributeName in ipairs(attributeNames) do
		local value =
			emitter:GetAttribute(
				attributeName
			)

		if typeof(value) == "number"
			and value > 0 then

			return math.clamp(
				math.floor(value + 0.5),
				1,
				100
			)
		end
	end

	-- Fallback for authored emitters that do not expose a burst attribute.
	-- Scale from Rate so dense emitters stay dense without hardcoding one count.
	if emitter.Rate > 0 then
		return math.clamp(
			math.floor(
				emitter.Rate
					* M1_TEMPLATE_ACTIVE_TIME
					+ 0.5
			),
			1,
			40
		)
	end

	return 8
end


local function prepareTemplateRoot(
	clone: Instance,
	impactCFrame: CFrame
): Instance

	if clone:IsA("Model") then
		clone:PivotTo(
			impactCFrame
		)

		return clone
	end

	if clone:IsA("BasePart") then
		clone.CFrame =
			impactCFrame

		return clone
	end

	if clone:IsA("Attachment") then
		local anchorPart =
			Instance.new("Part")

		anchorPart.Name =
			"CombatHitVFXAnchor"
		anchorPart.Anchored =
			true
		anchorPart.CanCollide =
			false
		anchorPart.CanTouch =
			false
		anchorPart.CanQuery =
			false
		anchorPart.CastShadow =
			false
		anchorPart.Transparency =
			1
		anchorPart.Size =
			Vector3.new(0.1, 0.1, 0.1)
		anchorPart.CFrame =
			impactCFrame
		anchorPart.Parent =
			workspace

		clone.Parent =
			anchorPart

		return anchorPart
	end

	-- Folder / other container fallback: wrap it in a Model so PivotTo can
	-- move every BasePart descendant as one authored effect.
	local wrapper =
		Instance.new("Model")

	wrapper.Name =
		"CombatHitVFXWrapper"
	wrapper.Parent =
		workspace

	clone.Parent =
		wrapper

	wrapper:PivotTo(
		impactCFrame
	)

	return wrapper
end


local function sanitizeProducedTemplateGeometry(
	root: Instance
)
	local function sanitize(instance: Instance)
		if instance:IsA("BasePart") then
			-- Authored HitVFX parts are only containers/anchors for particles.
			-- They must never render as cubes/geometry in-game.
			instance.Anchored =
				true

			instance.CanCollide =
				false

			instance.CanTouch =
				false

			instance.CanQuery =
				false

			instance.CastShadow =
				false

			instance.Transparency =
				1
		end
	end

	sanitize(root)

	for _, descendant in ipairs(
		root:GetDescendants()
		) do
		sanitize(descendant)
	end
end


local function playProducedTemplateVFX(
	template: Instance,
	position: Vector3,
	direction: Vector3
)

	local facingDirection =
		safeUnit(
			direction,
			Vector3.new(0, 0, -1)
		)

	local impactCFrame =
		CFrame.lookAt(
			position,
			position + facingDirection,
			Vector3.yAxis
		)
		* M1_TEMPLATE_ROTATION_OFFSET

	local clone =
		template:Clone()

	clone.Name =
		"CombatHitVFX_"
		.. template.Name

	local templateScale =
		getProducedTemplateScale(
			template.Name
		)

	debugProducedTemplate(
		template,
		clone,
		templateScale
	)

	-- Model / BasePart must be parented before PivotTo for reliable bounds.
	if clone:IsA("Model")
		or clone:IsA("BasePart") then

		clone.Parent =
			workspace
	end

	local cleanupRoot =
		prepareTemplateRoot(
			clone,
			impactCFrame
		)

	-- IMPORTANT:
	-- Punch-01/02/03 are BaseParts that carry Attachments/ParticleEmitters.
	-- Hide the cloned container geometry itself, otherwise it appears as a cube
	-- at the hit position.
	sanitizeProducedTemplateGeometry(
		cleanupRoot
	)

	scaleProducedTemplateVisuals(
		cleanupRoot,
		templateScale
	)

	local maxLifetime =
		M1_TEMPLATE_MIN_CLEANUP

	if WAIT_ONE_HEARTBEAT_BEFORE_EMIT then
		RunService.Heartbeat:Wait()
	end

	local emittedParticleEmitters =
		0

	for _, descendant in ipairs(cleanupRoot:GetDescendants()) do
		if descendant:IsA("BasePart") then
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
			descendant.Transparency =
				1

		elseif descendant:IsA("ParticleEmitter") then
			emittedParticleEmitters += 1

			maxLifetime =
				math.max(
					maxLifetime,
					descendant.Lifetime.Max
					+ M1_TEMPLATE_ACTIVE_TIME
					+ 0.45
				)

			normalizeProducedParticleVisibility(
				descendant
			)

			local burstCount =
				math.max(
					getEmitterBurstCount(
						descendant
					),
					HIT_PARTICLE_MIN_BURST
				)

			-- Stop authored continuous emission and force a deterministic burst.
			-- This guarantees the VFX is tied to the confirmed hit event.
			descendant.Enabled =
				false

			descendant:Emit(
				burstCount
			)

			if HIT_VFX_RUNTIME_DEBUG then
				print(
					"[CombatImpactVFX] EMIT",
					template.Name,
					descendant:GetFullName(),
					"count",
					burstCount,
					"texture",
					descendant.Texture,
					"sizeMax",
					getNumberSequenceMaxValue(
						descendant.Size
					),
					"transparencyMin",
					getNumberSequenceMinValue(
						descendant.Transparency
					),
					"brightness",
					descendant.Brightness,
					"zOffset",
					descendant.ZOffset,
					"lifetime",
					descendant.Lifetime.Min,
					descendant.Lifetime.Max,
					"speed",
					descendant.Speed.Min,
					descendant.Speed.Max
				)

				if descendant.Texture == "" then
					warn(
						"[CombatImpactVFX] EMITTER HAS NO TEXTURE:",
						descendant:GetFullName()
					)
				end
			end

		elseif descendant:IsA("Beam") then
			descendant.Enabled =
				true

			task.delay(
				M1_TEMPLATE_ACTIVE_TIME,
				function()
					if descendant.Parent then
						descendant.Enabled =
							false
					end
				end
			)

		elseif descendant:IsA("Trail") then
			descendant.Enabled =
				true

			maxLifetime =
				math.max(
					maxLifetime,
					descendant.Lifetime
					+ M1_TEMPLATE_ACTIVE_TIME
					+ 0.45
				)

			task.delay(
				M1_TEMPLATE_ACTIVE_TIME,
				function()
					if descendant.Parent then
						descendant.Enabled =
							false
					end
				end
			)
		end
	end

	if HIT_VFX_RUNTIME_DEBUG then
		print(
			"[CombatImpactVFX] PLAYED",
			template.Name,
			"at",
			position,
			"emitters",
			emittedParticleEmitters
		)
	end

	if emittedParticleEmitters == 0 then
		warn(
			"[CombatImpactVFX] NO ParticleEmitter found in template:",
			template:GetFullName()
		)
	end

	Debris:AddItem(
		cleanupRoot,
		maxLifetime
	)
end


local function playM1HitTemplate(
	comboNumber: number,
	position: Vector3,
	direction: Vector3
)

	local chosenTemplate =
		m1Templates[
	comboNumber
	]

	if not chosenTemplate then
		warn(
			"[CombatImpactVFX] No M1 VFX template for combo",
			comboNumber
		)

		return
	end

	playProducedTemplateVFX(
		chosenTemplate,
		position,
		direction
	)
end


-- =========================
-- EFFECT TYPES
-- =========================

local function playNormalHit(
	position: Vector3,
	direction: Vector3,
	attackerUserId: number
)

	makeFlash(
		position,
		HIT_CORE,
		0.44,
		1.95,
		0.20,
		0.26
	)


	makeImpactGlyph(
		position,
		HIT_CORE,
		HIT_SPARK,
		1.00,
		6,
		0.17
	)


	emitCrossSlash(
		position,
		direction,
		HIT_CORE,
		1.18
	)


	emitRadialSparks(
		position,
		direction,
		HIT_SPARK,
		7,
		1.28,
		1.20,
		0.20
	)

	emitArmSmokeTrail(
		attackerUserId,
		direction,
		false
	)
end


local function playHeavyHit(
	position: Vector3,
	direction: Vector3,
	attackerUserId: number
)

	makeFlash(
		position,
		HEAVY_CORE,
		0.56,
		2.55,
		0.23,
		0.20
	)


	makeFlash(
		position,
		HEAVY_ACCENT,
		0.24,
		1.52,
		0.18,
		0.28
	)


	makeImpactGlyph(
		position,
		HEAVY_CORE,
		HEAVY_ACCENT,
		1.28,
		9,
		0.20
	)


	emitCrossSlash(
		position,
		direction,
		HEAVY_CORE,
		1.70
	)


	emitRadialSparks(
		position,
		direction,
		HEAVY_ACCENT,
		11,
		1.42,
		1.65,
		0.22
	)

	emitArmSmokeTrail(
		attackerUserId,
		direction,
		true
	)
end


local function playBlock(
	position: Vector3,
	direction: Vector3
)

	-- Full replacement: Shield-01 owns the Block visual.
	-- Do not layer the previous procedural flash/glyph/plate/sparks.
	playProducedTemplateVFX(
		shieldTemplate,
		position,
		direction
	)
end


local function playGuardBreak(
	position: Vector3,
	direction: Vector3
)

	-- Full replacement: Shield-Break-01 owns the GuardBreak visual.
	-- Do not layer the previous procedural flash/glyph/plate/fragments.
	playProducedTemplateVFX(
		shieldBreakTemplate,
		position,
		direction
	)
end


-- =========================
-- REMOTE
-- =========================

local combatRemotes =
	ReplicatedStorage:
	WaitForChild(
		"CombatRemotes"
	)


local combatImpactVFX =
	combatRemotes:
	WaitForChild(
		"CombatImpactVFX"
	)


combatImpactVFX.OnClientEvent:
	Connect(
		function(
			effectType,
			position,
			direction,
			comboNumber,
			attackerUserId,
			defenderUserId
		)

			if HIT_VFX_RUNTIME_DEBUG then
				print(
					"[CombatImpactVFX] REMOTE RECEIVED",
					effectType,
					"combo",
					comboNumber,
					"attacker",
					attackerUserId,
					"defender",
					defenderUserId,
					"position",
					position
				)
			end

			if typeof(effectType)
				~= "string"
				or typeof(position)
				~= "Vector3"
				or typeof(direction)
				~= "Vector3" then

				return
			end


			local cameraDistance =
			getCameraDistance(
				position
			)


			if cameraDistance >
				MAX_VFX_DISTANCE then

				if HIT_VFX_RUNTIME_DEBUG then
					warn(
						"[CombatImpactVFX] DISCARDED BY DISTANCE:",
						cameraDistance,
						">",
						MAX_VFX_DISTANCE
					)
				end

				return
			end


			local isM1Impact =
			typeof(comboNumber) == "number"
			and comboNumber >= 1
			and comboNumber <= 5
			and (
				effectType == "Hit"
				or effectType == "HeavyHit"
			)


			if isM1Impact then

				-- Full replacement for M1 visuals. Do NOT layer the previous
				-- procedural flash/glyph/slash/sparks/smoke on top.
				playM1HitTemplate(
					comboNumber,
					position,
					direction
				)

			elseif effectType == "HeavyHit" then

				-- Non-M1 heavy impacts keep their existing feedback until they
				-- receive their own produced template.
				playHeavyHit(
					position,
					direction,
					attackerUserId
				)

			elseif effectType == "Block" then

				-- Full replacement with ReplicatedStorage.VFX.HitVFX.Shield-01.
				playBlock(
					position,
					direction
				)

			elseif effectType == "GuardBreak" then

				-- Full replacement with ReplicatedStorage.VFX.HitVFX.Shield-Break-01.
				playGuardBreak(
					position,
					direction
				)

			else

				playNormalHit(
					position,
					direction,
					attackerUserId
				)
			end


			if cameraDistance <=
				MAX_SHAKE_DISTANCE then

				local localUserId =
				player.UserId


				local directlyInvolved =
				localUserId ==
				attackerUserId
				or localUserId ==
				defenderUserId


				if directlyInvolved then

					local shakeMagnitude =
					if effectType ==
					"HeavyHit"
					then HEAVY_SHAKE_ROTATION
					elseif effectType ==
					"GuardBreak"
					then GUARD_BREAK_SHAKE_ROTATION
					else NORMAL_SHAKE_ROTATION

					if shakeMagnitude > 0 then

						playCameraImpulse(
							shakeMagnitude
						)
					end
				end
			end
		end
	)


print(
	"[CombatImpactVFXController] READY v2.1 ReducedPunchScale_ProducedVFX"
		.. " | Path=ReplicatedStorage/VFX/HitVFX"
		.. " | M1Procedural=OFF"
		.. " | M1_1=Punch-01"
		.. " | M1_2=Punch-02"
		.. " | M1_3=Punch-03"
		.. " | M1_4=Punch-04_OR_Punch-03_FALLBACK"
		.. " | M1_5=Shoot-01"
		.. " | Block=Shield-01"
		.. " | GuardBreak=Shield-Break-01"
		.. " | BlockGuardBreakProcedural=OFF"
		.. " | PunchScale=" .. tostring(PUNCH_TEMPLATE_SCALE)
		.. " | ShootScale=" .. tostring(SHOOT_TEMPLATE_SCALE)
		.. " | ShieldScale=" .. tostring(SHIELD_TEMPLATE_SCALE)
		.. " | ShieldBreakScale=" .. tostring(SHIELD_BREAK_TEMPLATE_SCALE)
		.. " | TemplateDebug=" .. tostring(PRODUCED_TEMPLATE_DEBUG)
		.. " | VisibilityNormalize=" .. tostring(NORMALIZE_HIT_PARTICLE_VISIBILITY)
		.. " | NormalShake=OFF"
		.. " | GuardBreakMicroShake=ON"
		.. " | MultiplayerClientVFX=ON"
		.. " | SurfaceCameraSafe=ON"
)
