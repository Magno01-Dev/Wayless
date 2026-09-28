--!strict
-- LauncherController v4.1 DB - Original Uplift + No Legacy Backflip Jump
-- StarterPlayer > StarterCharacterScripts > LauncherController
--
-- Animation:
-- 135785314988292  -- original pre-DB Uplift animation restored
--
-- Authored Launcher markers used by this controller:
-- LauncherStart   REQUIRED
-- Commit          REQUIRED
-- Hit             REQUIRED
-- WhiffEnd        REQUIRED for clean miss branching
-- FlickerReady    REQUIRED for Body Flicker preparation/freeze
-- BodyFlicker     REQUIRED for the actual marker-driven follow
-- RecoveryStart   OPTIONAL
-- LauncherEnd     OPTIONAL
--
-- Phase 4.1 intentionally implements ONLY:
-- Ctrl+M1 -> Launcher -> server hit confirm -> automatic air follow
-- -> timed suspended QA window -> release/fall.
--
-- Air M1 reuses the existing grounded M1 pipeline while the attacker is held in the Launcher aerial window.
-- Air M2 ends the aerial window by throwing the paired victim diagonally downward.
-- Launcher victims remain action-locked except for explicit Block/Kawarimi counterplay.

local Players =
	game:GetService("Players")

local UserInputService =
	game:GetService("UserInputService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

local Debris =
	game:GetService("Debris")


local player =
	Players.LocalPlayer

local character =
	script.Parent

local humanoid =
	character:
	WaitForChild("Humanoid") :: Humanoid

local root =
	character:
	WaitForChild("HumanoidRootPart") :: BasePart

local animator =
	humanoid:
	WaitForChild("Animator") :: Animator


-- ============================================================
-- REMOTE
-- ============================================================

local combatRemotes =
	ReplicatedStorage:
	WaitForChild("CombatRemotes")

local launcherEvent =
	combatRemotes:
	WaitForChild("LauncherEvent") :: RemoteEvent

-- ============================================================
-- CONFIG
-- ============================================================

local ANIMATION_ID =
	"rbxassetid://135785314988292"

-- Dedicated Air M2 attacker animation.
-- Authored markers:
--   Impact  -> contact frame / brief anime hit-stop.
--   Release -> VFX hook + authoritative victim launch.
local AIR_M2_ATTACKER_ANIMATION_ID =
	"113654141031298"

local AIR_M2_ATTACKER_IMPACT_MARKER =
	"Impact"

local AIR_M2_ATTACKER_RELEASE_MARKER =
	"Release"

local AIR_M2_ATTACKER_PLAYBACK_SPEED =
	1.00

local AIR_M2_HITSTOP_DURATION =
	0.10

local LAUNCHER_WHIFF_END_MARKER =
	"WhiffEnd"

local LAUNCHER_FLICKER_READY_MARKER =
	"FlickerReady"

local LAUNCHER_BODY_FLICKER_MARKER =
	"BodyFlicker"

-- The authored marker decides WHEN the follow begins.
-- This value only controls how fast the visual Body Flicker crosses the gap.
local AIR_ATTACKER_BODY_FLICKER_DURATION =
	0.075

-- Let the authored preparation pose read clearly before the follow starts.
local FLICKER_READY_FREEZE_DURATION =
	0.20

-- Anime Body Flicker presentation.
local BODY_FLICKER_VFX_NAME =
	"body flicker"

local BODY_FLICKER_DEPART_SOUND_ID =
	"127579210330639"

-- Reserved for the future appearance sound.
-- Paste only the numeric Roblox asset ID here when ready.
local BODY_FLICKER_APPEAR_SOUND_ID =
	""

local BODY_FLICKER_BLINK_INTERVAL =
	0.035

local BODY_FLICKER_VFX_ACTIVE_TIME =
	0.14

local BODY_FLICKER_VFX_LIFETIME =
	2.0

local BODY_FLICKER_VISUAL_FAILSAFE =
	3.5

-- Release the M2 attacker into a definite fall instead of zero Y velocity.
local AIR_M2_ATTACKER_FALL_RELEASE_SPEED =
	8.0

-- If the branch marker is reached before the server result arrives, pause
-- briefly instead of accidentally entering the HIT-only tail on a miss.
local LAUNCHER_HIT_RESOLVE_GRACE =
	0.30

-- ReplicatedStorage/VFX/Slam authored visuals.
-- Impact marker: Shoot-01 + Wind-01.
-- Release marker: Release.
local SLAM_VFX_FOLDER_NAME =
	"SlamVFX"

local SLAM_VFX_LIFETIME =
	4.0

-- Authored continuous emitters used to be cut at 0.18s, which made some
-- templates look much weaker than they do when previewed in Studio.
local SLAM_ACTIVE_EMITTER_TIME =
	0.10

local SLAM_DEFAULT_BURST_COUNT =
	6

local SLAM_VFX_TUNING = {
	["Shoot-01"] = {
		Scale = 1.10,
		EmitMultiplier = 0.75,
		TransparencyFloor = 0.70,
		MaxParticleLifetime = 0.50,
		MinBrightness = 2.25,
		MinLightEmission = 0.72,
		MaxLightInfluence = 0.22,
	},
	["Wind-01"] = {
		Scale = 1.15,
		EmitMultiplier = 0.70,
		TransparencyFloor = 0.70,
		MaxParticleLifetime = 0.45,
		MinBrightness = 1.75,
		MinLightEmission = 0.60,
		MaxLightInfluence = 0.28,
	},
	["Release"] = {
		Scale = 1.10,
		EmitMultiplier = 0.80,
		TransparencyFloor = 0.70,
		MaxParticleLifetime = 0.35,
		MinBrightness = 2.10,
		MinLightEmission = 0.68,
		MaxLightInfluence = 0.24,
	},
}

local SLAM_IMPACT_SHAKE_DURATION =
	0.16

local SLAM_IMPACT_SHAKE_MAX_DISTANCE =
	58.0

local SLAM_IMPACT_SHAKE_TRANSLATION =
	0.23

local SLAM_IMPACT_SHAKE_ROTATION_DEG =
	1.15

local SLAM_GROUND_DUST_CORE_COUNT =
	42

local SLAM_GROUND_DUST_OUTER_COUNT =
	54

local SLAM_GROUND_DUST_LIFETIME =
	2.35

-- If Roblox ever misses authored markers on a replayed AnimationTrack,
-- this wall-clock failsafe prevents the committed M2 from hanging until
-- the aerial hold times out. Authored Release remains the normal path.
local AIR_M2_RELEASE_FAILSAFE_DELAY =
	0.85

-- Attacker-only M2 landing polish. After the authored M2 animation ends the
-- attacker is released into a natural fall. A short local landing guard then
-- pre-brakes only the final fraction of the descent and kills any solver bounce,
-- so the Humanoid returns to grounded locomotion instead of lingering in Fall.
local AIR_M2_ATTACKER_LANDING_ROOT_OFFSET =
	3.00

local AIR_M2_ATTACKER_LANDING_PROBE_DISTANCE =
	5.25

local AIR_M2_ATTACKER_LANDING_NORMAL_Y_MIN =
	0.45

local AIR_M2_ATTACKER_LANDING_PREBRAKE_SPEED =
	12.0

local AIR_M2_ATTACKER_LANDING_CONTACT_TOLERANCE =
	0.16

local AIR_M2_ATTACKER_LANDING_BOUNCE_DAMP_TIME =
	0.16

local AIR_M2_ATTACKER_LANDING_GUARD_TIMEOUT =
	2.25

-- Playback speed for the Launcher animation.
-- 1.00 = authored speed, 1.15 = 15% faster, 1.25 = 25% faster.
-- Animation markers scale automatically with this value.
local ANIMATION_PLAYBACK_SPEED =
	1.40

local LAUNCHER_BINDABLE_NAME =
	"LauncherTryStart"

-- Initial balance value. Launcher is a stronger commitment/setup tool than Lunge.
local CLIENT_COOLDOWN =
	4.00

-- Small movement commitment at the authored Commit marker.
-- This is deliberately modest; server hitbox remains authoritative.
local COMMIT_FORWARD_IMPULSE =
	5.5

-- ============================================================
-- DB: LEGACY PHYSICAL BACKFLIP JUMP REMOVED
-- ============================================================
-- The previous Launcher animation needed a client-side vertical impulse plus
-- counter-gravity to visually clear the ground. The restored original Uplift
-- animation (135785314988292) does not use that movement assist.
--
-- No vertical impulse / anti-gravity is applied by Launcher startup.
-- The authored animation plays from the character's natural grounded position.
-- The modest forward Commit impulse remains gameplay movement, not the old jump.

local COMMIT_FALLBACK_DELAY =
	0.20

local ANIMATION_FADE_IN =
	0.035

local ANIMATION_FADE_OUT =
	0.06

local DEBUG =
	false


-- ============================================================
-- SLAM VFX / CAMERA FEEDBACK
-- ============================================================

-- Resolve on demand instead of caching at LocalScript boot.
-- ReplicatedStorage descendants can arrive after this controller starts.
local function hasRequiredSlamTemplates(
	instance: Instance
): boolean
	return instance:FindFirstChild("Release") ~= nil
		and instance:FindFirstChild("Shoot-01") ~= nil
		and instance:FindFirstChild("Wind-01") ~= nil
end

local function resolveSlamFolder(): Instance?
	local vfxRoot =
		ReplicatedStorage:
		FindFirstChild("VFX")

	if not vfxRoot then
		return nil
	end

	-- Current authored folder name from Studio.
	local preferredNames = {
		"SlamVFX",
		"Slam",
	}

	for _, preferredName in ipairs(preferredNames) do
		local exact =
			vfxRoot:
			FindFirstChild(preferredName)

		if exact then
			return exact
		end
	end

	-- Case-insensitive support for harmless naming variations.
	for _, child in ipairs(vfxRoot:GetChildren()) do
		local lowerName =
			string.lower(child.Name)

		if lowerName == "slamvfx"
			or lowerName == "slam" then
			return child
		end
	end

	-- Final content-based fallback:
	-- find whichever folder actually contains the three authored templates.
	for _, child in ipairs(vfxRoot:GetChildren()) do
		if hasRequiredSlamTemplates(child) then
			if DEBUG then
				print(
					"[LauncherClient] SLAM FOLDER RESOLVED BY CONTENT",
					child:GetFullName()
				)
			end

			return child
		end
	end

	return nil
end

task.defer(
	function()
		for _ = 1, 20 do
			local folder =
				resolveSlamFolder()

			if folder then
				if DEBUG then
					local names = {}

					for _, child in ipairs(folder:GetChildren()) do
						table.insert(names, child.Name)
					end

					print(
						"[LauncherClient] SLAM FOLDER READY",
						folder:GetFullName(),
						"templates",
						table.concat(names, ", ")
					)
				end
				return
			end

			task.wait(0.25)
		end

		if DEBUG then
			warn(
				"[LauncherClient] SLAM VFX FOLDER NOT FOUND after 5s"
			)
		end
	end
)

local function unitOrFallback(
	value: Vector3,
	fallback: Vector3
): Vector3
	if value.Magnitude > 0.001 then
		return value.Unit
	end

	if fallback.Magnitude > 0.001 then
		return fallback.Unit
	end

	return Vector3.zAxis
end

local function effectCFrame(
	position: Vector3,
	direction: Vector3
): CFrame
	local forward =
		unitOrFallback(
			direction,
			Vector3.zAxis
		)

	local up = Vector3.yAxis
	if math.abs(forward:Dot(up)) > 0.96 then
		up = Vector3.xAxis
	end

	return CFrame.lookAt(
		position,
		position + forward,
		up
	)
end

local function scaleNumberSequence(
	sequence: NumberSequence,
	factor: number
): NumberSequence
	local keypoints = {}

	for _, keypoint in ipairs(sequence.Keypoints) do
		table.insert(
			keypoints,
			NumberSequenceKeypoint.new(
				keypoint.Time,
				keypoint.Value * factor,
				keypoint.Envelope * factor
			)
		)
	end

	return NumberSequence.new(keypoints)
end

local function floorNumberSequence(
	sequence: NumberSequence,
	floorValue: number
): NumberSequence
	local keypoints = {}

	for _, keypoint in ipairs(sequence.Keypoints) do
		local value =
			math.max(
				keypoint.Value,
				floorValue
			)

		table.insert(
			keypoints,
			NumberSequenceKeypoint.new(
				keypoint.Time,
				value,
				math.min(
					keypoint.Envelope,
					math.max(0, 1 - value)
				)
			)
		)
	end

	return NumberSequence.new(keypoints)
end

local function prepareVisualObject(
	descendant: Instance,
	tuning: any
)
	if descendant:IsA("BasePart") then
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		descendant.Massless = true

		-- Authored VFX BaseParts are only spatial containers/preview holders.
		-- Keep the emitters/attachments, but never render the support geometry.
		descendant.Transparency = 1
		descendant.CastShadow = false
	elseif descendant:IsA("ParticleEmitter") then
		local emitMultiplier =
			typeof(tuning) == "table"
			and typeof(tuning.EmitMultiplier) == "number"
			and tuning.EmitMultiplier
			or 1.0

		local sizeScale =
			typeof(tuning) == "table"
			and typeof(tuning.Scale) == "number"
			and tuning.Scale
			or 1.0

		descendant.Size =
			scaleNumberSequence(
				descendant.Size,
				sizeScale
			)

		if typeof(tuning) == "table"
			and typeof(tuning.TransparencyFloor) == "number" then

			descendant.Transparency =
				floorNumberSequence(
					descendant.Transparency,
					tuning.TransparencyFloor
				)
		end

		if typeof(tuning) == "table"
			and typeof(tuning.MaxParticleLifetime) == "number" then

			local cap =
				tuning.MaxParticleLifetime

			descendant.Lifetime =
				NumberRange.new(
					math.min(
						descendant.Lifetime.Min,
						cap
					),
					math.min(
						descendant.Lifetime.Max,
						cap
					)
				)
		end

		if typeof(tuning) == "table" then
			if typeof(tuning.MinBrightness) == "number" then
				descendant.Brightness =
					math.max(
						descendant.Brightness,
						tuning.MinBrightness
					)
			end

			if typeof(tuning.MinLightEmission) == "number" then
				descendant.LightEmission =
					math.max(
						descendant.LightEmission,
						tuning.MinLightEmission
					)
			end

			if typeof(tuning.MaxLightInfluence) == "number" then
				descendant.LightInfluence =
					math.min(
						descendant.LightInfluence,
						tuning.MaxLightInfluence
					)
			end
		end

		-- Keep particles from visually disappearing behind the victim body.
		descendant.ZOffset =
			math.max(
				descendant.ZOffset,
				1.15
			)

		local authoredEmitCount =
			descendant:GetAttribute("EmitCount")

		local baseEmitCount =
			if typeof(authoredEmitCount) == "number"
			and authoredEmitCount > 0
			then authoredEmitCount
			else SLAM_DEFAULT_BURST_COUNT

		local finalEmitCount =
			math.clamp(
				math.floor(
					baseEmitCount
					* emitMultiplier
					+ 0.5
				),
				3,
				10
			)

		-- Guaranteed authored burst even when the template was stored disabled.
		descendant:Emit(finalEmitCount)

		-- If it was designed as a continuous emitter, let it run briefly too.
		if descendant.Rate > 0 then
			descendant.Rate =
				math.clamp(
					descendant.Rate
					* emitMultiplier,
					1,
					20
				)

			descendant.Enabled = true

			task.delay(
				SLAM_ACTIVE_EMITTER_TIME,
				function()
					if descendant.Parent then
						descendant.Enabled = false
					end
				end
			)
		end
	elseif descendant:IsA("Beam") then
		local scale =
			typeof(tuning) == "table"
			and typeof(tuning.Scale) == "number"
			and tuning.Scale
			or 1.0

		descendant.Width0 *= scale
		descendant.Width1 *= scale

		if typeof(tuning) == "table"
			and typeof(tuning.TransparencyFloor) == "number" then

			descendant.Transparency =
				floorNumberSequence(
					descendant.Transparency,
					tuning.TransparencyFloor
				)
		end

		descendant.Enabled = true

		task.delay(
			SLAM_ACTIVE_EMITTER_TIME,
			function()
				if descendant.Parent then
					descendant.Enabled = false
				end
			end
		)
	elseif descendant:IsA("Trail") then
		local scale =
			typeof(tuning) == "table"
			and typeof(tuning.Scale) == "number"
			and tuning.Scale
			or 1.0

		descendant.WidthScale =
			scaleNumberSequence(
				descendant.WidthScale,
				scale
			)

		if typeof(tuning) == "table"
			and typeof(tuning.TransparencyFloor) == "number" then

			descendant.Transparency =
				floorNumberSequence(
					descendant.Transparency,
					tuning.TransparencyFloor
				)
		end

		descendant.Enabled = true

		task.delay(
			SLAM_ACTIVE_EMITTER_TIME,
			function()
				if descendant.Parent then
					descendant.Enabled = false
				end
			end
		)
	end
end

local function prepareVisualClone(
	instance: Instance,
	tuning: any
)
	prepareVisualObject(instance, tuning)

	for _, descendant in ipairs(instance:GetDescendants()) do
		prepareVisualObject(descendant, tuning)
	end
end


local function findAuthoredVFXRoot(
	instance: Instance
): BasePart?
	local preferredNames = {
		"Main",
		"Root",
		"Center",
		"Effect",
		"VFX",
		"Part",
	}

	for _, name in ipairs(preferredNames) do
		local candidate =
			instance:FindFirstChild(name, true)

		if candidate
			and candidate:IsA("BasePart") then
			return candidate
		end
	end

	if instance:IsA("BasePart") then
		return instance
	end

	return instance:
		FindFirstChildWhichIsA(
			"BasePart",
			true
		)
end

local function moveCloneByReferencePart(
	instance: Instance,
	targetCFrame: CFrame
): (boolean, BasePart?)
	local referencePart =
		findAuthoredVFXRoot(instance)

	if not referencePart then
		return false, nil
	end

	local delta =
		targetCFrame
		* referencePart.CFrame:Inverse()

	if instance:IsA("BasePart") then
		instance.CFrame =
			targetCFrame

		return true, instance
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame =
				delta
				* descendant.CFrame
		end
	end

	return true, referencePart
end

-- ============================================================
-- BODY FLICKER PRESENTATION
-- ============================================================

local function resolveBodyFlickerTemplate(): Instance?
	local vfxRoot =
		ReplicatedStorage:
		FindFirstChild("VFX")

	if not vfxRoot then
		return nil
	end

	local wanted =
		string.lower(
			BODY_FLICKER_VFX_NAME
		)

	for _, child in ipairs(vfxRoot:GetChildren()) do
		local normalized =
			string.lower(child.Name):
			gsub("[%s_%-]", "")

		local wantedNormalized =
			wanted:
			gsub("[%s_%-]", "")

		if normalized == wantedNormalized then
			return child
		end
	end

	return nil
end


local function activateBodyFlickerVisualObject(
	object: Instance
)
	if object:IsA("BasePart") then
		object.Anchored = true
		object.CanCollide = false
		object.CanQuery = false
		object.CanTouch = false
		object.Massless = true
		object.Transparency = 1
		object.CastShadow = false

	elseif object:IsA("ParticleEmitter") then
		local authoredEmitCount =
			object:GetAttribute("EmitCount")

		local emitCount =
			if typeof(authoredEmitCount) == "number"
			and authoredEmitCount > 0
			then math.clamp(
				math.floor(authoredEmitCount + 0.5),
				1,
				24
			)
			else math.clamp(
				math.floor(
					math.max(
						object.Rate * BODY_FLICKER_VFX_ACTIVE_TIME,
						5
					)
					+ 0.5
				),
				4,
				16
			)

		object:Emit(emitCount)

		if object.Rate > 0 then
			object.Enabled = true

			task.delay(
				BODY_FLICKER_VFX_ACTIVE_TIME,
				function()
					if object.Parent then
						object.Enabled = false
					end
				end
			)
		end

	elseif object:IsA("Beam")
		or object:IsA("Trail") then

		object.Enabled = true

		task.delay(
			BODY_FLICKER_VFX_ACTIVE_TIME,
			function()
				if object.Parent then
					object.Enabled = false
				end
			end
		)
	end
end


local function spawnBodyFlickerVFX(
	targetCharacter: Model
)
	local targetRoot =
		targetCharacter:
		FindFirstChild("HumanoidRootPart")

	if not targetRoot
		or not targetRoot:IsA("BasePart") then
		return
	end

	local template =
		resolveBodyFlickerTemplate()

	if not template then
		if DEBUG then
			warn(
				"[LauncherClient] missing ReplicatedStorage/VFX/body flicker"
			)
		end
		return
	end

	local clone =
		template:Clone()

	clone.Name =
		"LauncherBodyFlickerVFX"

	local targetCFrame =
		targetRoot.CFrame

	if clone:IsA("Attachment") then
		local anchorPart =
			Instance.new("Part")

		anchorPart.Name =
			"LauncherBodyFlickerVFXAnchor"
		anchorPart.Size =
			Vector3.new(0.2, 0.2, 0.2)
		anchorPart.Transparency = 1
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.CFrame =
			targetCFrame
		anchorPart.Parent =
			workspace

		clone.Parent =
			anchorPart
		clone.CFrame =
			CFrame.identity

		activateBodyFlickerVisualObject(anchorPart)
		activateBodyFlickerVisualObject(clone)

		for _, descendant in ipairs(anchorPart:GetDescendants()) do
			activateBodyFlickerVisualObject(descendant)
		end

		Debris:AddItem(
			anchorPart,
			BODY_FLICKER_VFX_LIFETIME
		)
		return
	end

	local placed =
		moveCloneByReferencePart(
			clone,
			targetCFrame
		)

	if not placed
		and clone:IsA("Model") then
		pcall(
			function()
				clone:PivotTo(
					targetCFrame
				)
			end
		)
	end

	clone.Parent =
		workspace

	activateBodyFlickerVisualObject(clone)

	for _, descendant in ipairs(clone:GetDescendants()) do
		activateBodyFlickerVisualObject(descendant)
	end

	Debris:AddItem(
		clone,
		BODY_FLICKER_VFX_LIFETIME
	)
end


local function playBodyFlickerSound(
	targetCharacter: Model,
	soundAssetId: string
)
	if soundAssetId == "" then
		return
	end

	local targetRoot =
		targetCharacter:
		FindFirstChild("HumanoidRootPart")

	if not targetRoot
		or not targetRoot:IsA("BasePart") then
		return
	end

	local sound =
		Instance.new("Sound")

	sound.Name =
		"LauncherBodyFlickerSound"
	sound.SoundId =
		"rbxassetid://" .. soundAssetId
	sound.Volume =
		0.70
	sound.RollOffMode =
		Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance =
		8
	sound.RollOffMaxDistance =
		80
	sound.Parent =
		targetRoot

	sound:Play()

	Debris:AddItem(
		sound,
		4.0
	)
end


type BodyFlickerVisualState = {
	character: Model,
	token: number,
	mode: string,
	originalLocalTransparency: {[BasePart]: number},
}

local bodyFlickerVisualStates:
	{[number]: BodyFlickerVisualState} =
	{}


local function getBodyFlickerTargetCharacter(
	userId: number
): Model?
	local targetPlayer =
		Players:
		GetPlayerByUserId(userId)

	if not targetPlayer then
		return nil
	end

	return targetPlayer.Character
end


local function getOrCreateBodyFlickerState(
	userId: number,
	targetCharacter: Model
): BodyFlickerVisualState
	local existing =
		bodyFlickerVisualStates[userId]

	if existing
		and existing.character == targetCharacter then
		return existing
	end

	if existing then
		for part, original in pairs(
			existing.originalLocalTransparency
			) do
			if part.Parent then
				part.LocalTransparencyModifier =
					original
			end
		end
	end

	local state: BodyFlickerVisualState = {
		character = targetCharacter,
		token = 0,
		mode = "Visible",
		originalLocalTransparency = {},
	}

	bodyFlickerVisualStates[userId] =
		state

	return state
end


local function setBodyFlickerInvisible(
	state: BodyFlickerVisualState,
	invisible: boolean
)
	for _, descendant in ipairs(
		state.character:GetDescendants()
		) do

		if descendant:IsA("BasePart") then
			if state.originalLocalTransparency[descendant] == nil then
				state.originalLocalTransparency[descendant] =
					descendant.LocalTransparencyModifier
			end

			descendant.LocalTransparencyModifier =
				if invisible
				then 1
				else state.originalLocalTransparency[descendant]
		end
	end
end


local function restoreBodyFlickerVisibility(
	userId: number
)
	local state =
		bodyFlickerVisualStates[userId]

	if not state then
		return
	end

	state.token += 1
	state.mode =
		"Visible"

	setBodyFlickerInvisible(
		state,
		false
	)
end


local function startBodyFlickerBlink(
	userId: number,
	targetCharacter: Model
)
	local state =
		getOrCreateBodyFlickerState(
			userId,
			targetCharacter
		)

	state.token += 1
	state.mode =
		"Blink"

	local token =
		state.token

	setBodyFlickerInvisible(
		state,
		false
	)

	task.spawn(
		function()
			local invisible =
				false

			while state.token == token
				and state.mode == "Blink"
				and state.character.Parent do

				invisible =
					not invisible

				setBodyFlickerInvisible(
					state,
					invisible
				)

				task.wait(
					BODY_FLICKER_BLINK_INTERVAL
				)
			end
		end
	)

	task.delay(
		BODY_FLICKER_VISUAL_FAILSAFE,
		function()
			local current =
				bodyFlickerVisualStates[userId]

			if current == state
				and current.token == token
				and current.mode ~= "Visible" then

				restoreBodyFlickerVisibility(
					userId
				)
			end
		end
	)
end


local function forceBodyFlickerInvisible(
	userId: number,
	targetCharacter: Model
)
	local state =
		getOrCreateBodyFlickerState(
			userId,
			targetCharacter
		)

	state.token += 1
	state.mode =
		"Invisible"

	setBodyFlickerInvisible(
		state,
		true
	)
end


local function handleBodyFlickerPresentation(
	stage: string,
	attackerUserId: number
)
	local targetCharacter =
		getBodyFlickerTargetCharacter(
			attackerUserId
		)

	if not targetCharacter then
		return
	end

	if stage == "Ready" then
		spawnBodyFlickerVFX(
			targetCharacter
		)

		startBodyFlickerBlink(
			attackerUserId,
			targetCharacter
		)

	elseif stage == "Disappear" then
		forceBodyFlickerInvisible(
			attackerUserId,
			targetCharacter
		)

		playBodyFlickerSound(
			targetCharacter,
			BODY_FLICKER_DEPART_SOUND_ID
		)

	elseif stage == "Arrive" then
		restoreBodyFlickerVisibility(
			attackerUserId
		)

		spawnBodyFlickerVFX(
			targetCharacter
		)

		playBodyFlickerSound(
			targetCharacter,
			BODY_FLICKER_APPEAR_SOUND_ID
		)

	elseif stage == "Cancel" then
		restoreBodyFlickerVisibility(
			attackerUserId
		)
	end
end


local function spawnSlamTemplate(
	templateName: string,
	position: Vector3,
	direction: Vector3
)
	local tuning =
		SLAM_VFX_TUNING[templateName]

	local slamFolder =
		resolveSlamFolder()

	if not slamFolder then
		if DEBUG then
			warn(
				"[LauncherClient] Slam folder not replicated yet; retrying",
				templateName
			)
		end

		-- Presentation-only retry. Never block the Launcher controller/input.
		task.delay(
			0.12,
			function()
				local retryFolder =
					resolveSlamFolder()

				if retryFolder then
					spawnSlamTemplate(
						templateName,
						position,
						direction
					)
				elseif DEBUG then
					warn(
						"[LauncherClient] Slam folder still unavailable after retry",
						templateName
					)
				end
			end
		)

		return
	end

	local template =
		slamFolder:FindFirstChild(templateName)

	if not template then
		if DEBUG then
			local childNames = {}

			for _, child in ipairs(slamFolder:GetChildren()) do
				table.insert(childNames, child.Name)
			end

			warn(
				"[LauncherClient] missing Slam VFX",
				templateName,
				"folder",
				slamFolder:GetFullName(),
				"children",
				table.concat(childNames, ", ")
			)
		end
		return
	end

	local emitterCount = 0
	local beamCount = 0
	local trailCount = 0

	if template:IsA("ParticleEmitter") then
		emitterCount += 1
	elseif template:IsA("Beam") then
		beamCount += 1
	elseif template:IsA("Trail") then
		trailCount += 1
	end

	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			emitterCount += 1
		elseif descendant:IsA("Beam") then
			beamCount += 1
		elseif descendant:IsA("Trail") then
			trailCount += 1
		end
	end

	if DEBUG then
		print(
			"[LauncherClient] SLAM TEMPLATE",
			templateName,
			"path",
			template:GetFullName(),
			"class",
			template.ClassName,
			"emitters",
			emitterCount,
			"beams",
			beamCount,
			"trails",
			trailCount
		)
	end

	local clone = template:Clone()
	clone.Name = "LauncherSlam_" .. templateName

	local cf = effectCFrame(position, direction)

	-- Do not scale the Model/BasePart geometry here.
	-- ParticleEmitter/Beam/Trail sizing is handled once in prepareVisualObject.
	-- This preserves the authored attachment layout and avoids double-scaling.
	-- Place using an actual authored BasePart rather than Model.WorldPivot.
	-- Imported VFX often have a pivot far away from their visible emitters.
	local placed,
		referencePart =
		moveCloneByReferencePart(
			clone,
			cf
		)

	if clone:IsA("Attachment") then
		local anchor = Instance.new("Part")
		anchor.Name = "LauncherSlamVFXAnchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CFrame = cf
		anchor.Parent = workspace
		clone.Parent = anchor
		clone.CFrame = CFrame.identity
		prepareVisualClone(anchor, tuning)

		if DEBUG then
			print(
				"[LauncherClient] SLAM SPAWNED",
				templateName,
				"AttachmentRoot",
				"at",
				position
			)
		end

		Debris:AddItem(anchor, SLAM_VFX_LIFETIME)
		return
	end

	if not placed
		and clone:IsA("Model") then
		-- Last-resort fallback for unusual authored models with no BasePart.
		pcall(
			function()
				clone:PivotTo(cf)
			end
		)
	end

	clone.Parent = workspace

	prepareVisualClone(clone, tuning)

	if DEBUG then
		local actualPosition =
			referencePart
			and referencePart.Position
			or position

		print(
			"[LauncherClient] SLAM SPAWNED",
			templateName,
			"requested",
			position,
			"actual",
			actualPosition,
			"distanceError",
			(actualPosition - position).Magnitude
		)
	end

	Debris:AddItem(clone, SLAM_VFX_LIFETIME)
end

local shakeSerial = 0

local function playSlamImpactShake(
	impactPosition: Vector3,
	attackerUserId: number
)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local distance =
		(camera.CFrame.Position - impactPosition).Magnitude

	local localIsAttacker =
		attackerUserId == player.UserId

	if not localIsAttacker
		and distance > SLAM_IMPACT_SHAKE_MAX_DISTANCE then
		return
	end

	local distanceScale =
		if localIsAttacker
		then 1.0
		else math.clamp(
			1.0 - distance / SLAM_IMPACT_SHAKE_MAX_DISTANCE,
			0,
			1
		)

	if distanceScale <= 0 then
		return
	end

	shakeSerial += 1
	local mySerial = shakeSerial
	local startedAt = time()
	local rotationScale = math.rad(SLAM_IMPACT_SHAKE_ROTATION_DEG)

	task.spawn(
		function()
			while mySerial == shakeSerial do
				local elapsed = time() - startedAt
				if elapsed >= SLAM_IMPACT_SHAKE_DURATION then
					break
				end

				RunService.RenderStepped:Wait()

				local currentCamera = workspace.CurrentCamera
				if not currentCamera then
					break
				end

				local fade =
					1 - elapsed / SLAM_IMPACT_SHAKE_DURATION

				local amplitude =
					distanceScale * fade

				local x = (math.random() * 2 - 1)
					* SLAM_IMPACT_SHAKE_TRANSLATION
					* amplitude
				local y = (math.random() * 2 - 1)
					* SLAM_IMPACT_SHAKE_TRANSLATION
					* 0.65
					* amplitude
				local rx = (math.random() * 2 - 1)
					* rotationScale
					* amplitude
				local rz = (math.random() * 2 - 1)
					* rotationScale
					* amplitude

				currentCamera.CFrame =
					currentCamera.CFrame
					* CFrame.new(x, y, 0)
					* CFrame.Angles(rx, 0, rz)
			end
		end
	)
end

local function surfaceAlignedCFrame(
	position: Vector3,
	normal: Vector3
): CFrame
	local up = unitOrFallback(normal, Vector3.yAxis)
	local reference =
		if math.abs(up:Dot(Vector3.yAxis)) < 0.92
		then Vector3.yAxis
		else Vector3.xAxis
	local right = reference:Cross(up).Unit
	local back = right:Cross(up).Unit
	return CFrame.fromMatrix(position, right, up, back)
end

local function createGroundDustEmitter(
	parent: Attachment,
	name: string,
	dustColor: Color3,
	lifetime: NumberRange,
	speed: NumberRange,
	drag: number,
	spread: number,
	startSize: number,
	midSize: number,
	endSize: number,
	count: number,
	lightInfluence: number
)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = lifetime
	emitter.Speed = speed
	emitter.Drag = drag
	emitter.Acceleration = Vector3.new(0, 3.0, 0)
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.LightInfluence = lightInfluence
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, startSize),
		NumberSequenceKeypoint.new(0.28, midSize),
		NumberSequenceKeypoint.new(1, endSize),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.58, 0.40),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(dustColor)
	emitter.Parent = parent
	emitter:Emit(count)
end

local function spawnGroundImpactDust(
	position: Vector3,
	normal: Vector3,
	dustColor: Color3?
)
	local anchor = Instance.new("Part")
	anchor.Name = "LauncherM2GroundDust"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = surfaceAlignedCFrame(
		position + unitOrFallback(normal, Vector3.yAxis) * 0.16,
		normal
	)
	anchor.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local color =
		dustColor
		or Color3.fromRGB(126, 105, 80)

	-- Dense core around the actual slam point.
	createGroundDustEmitter(
		attachment,
		"ImpactDustCore",
		color,
		NumberRange.new(0.75, 1.25),
		NumberRange.new(7.5, 13.5),
		3.2,
		68,
		1.6,
		4.6,
		6.6,
		SLAM_GROUND_DUST_CORE_COUNT,
		0.56
	)

	-- Wider, slower outer cloud so the dust expands past the character/crater
	-- instead of remaining as a tight ring around the victim.
	createGroundDustEmitter(
		attachment,
		"ImpactDustOuter",
		color,
		NumberRange.new(1.10, 1.85),
		NumberRange.new(13.0, 23.0),
		2.0,
		78,
		1.4,
		5.8,
		9.2,
		SLAM_GROUND_DUST_OUTER_COUNT,
		0.64
	)

	Debris:AddItem(anchor, SLAM_GROUND_DUST_LIFETIME)
end

launcherEvent.OnClientEvent:
	Connect(
		function(
			action: any,
			stage: any,
			_airComboId: any,
			attackerUserId: any
		)
			if action ~= "LauncherBodyFlickerFX" then
				return
			end

			if typeof(stage) ~= "string"
				or typeof(attackerUserId) ~= "number" then
				return
			end

			handleBodyFlickerPresentation(
				stage,
				attackerUserId
			)
		end
	)


launcherEvent.OnClientEvent:
	Connect(
		function(
			action: any,
			position: any,
			direction: any,
			_airComboId: any,
			attackerUserId: any,
			_defenderUserId: any,
			extra: any
		)
			if typeof(position) ~= "Vector3"
				or typeof(direction) ~= "Vector3" then
				return
			end

			if action == "LauncherM2Impact" then
				spawnSlamTemplate("Shoot-01", position, direction)
				spawnSlamTemplate("Wind-01", position, direction)
				playSlamImpactShake(
					position,
					typeof(attackerUserId) == "number"
					and attackerUserId
					or 0
				)
			elseif action == "LauncherM2Release" then
				spawnSlamTemplate("Release", position, direction)
			elseif action == "LauncherM2GroundDust" then
				spawnGroundImpactDust(
					position,
					direction,
					typeof(extra) == "Color3"
					and extra
					or nil
				)
			end
		end
	)


-- ============================================================
-- ANIMATION
-- ============================================================

local animation =
	Instance.new("Animation")

animation.Name =
	"LauncherUplift"

animation.AnimationId =
	ANIMATION_ID


local track =
	animator:
	LoadAnimation(
		animation
	)

track.Priority =
	Enum.AnimationPriority.Action4

track.Looped =
	false


local airM2Animation: Animation? =
	nil

-- A fresh AnimationTrack is loaded for every M2 attempt.
-- Reusing one track proved unreliable in QA: the first playback delivered
-- Impact/Release correctly, while later Play() calls could start visually
-- without delivering the authored markers.
local airM2Track: AnimationTrack? =
	nil

local airM2TrackConnections:
	{RBXScriptConnection} =
	{}

if AIR_M2_ATTACKER_ANIMATION_ID ~= "" then
	airM2Animation =
		Instance.new(
			"Animation"
		)

	airM2Animation.Name =
		"LauncherAirM2Attacker"

	airM2Animation.AnimationId =
		if string.find(
			AIR_M2_ATTACKER_ANIMATION_ID,
			"rbxassetid://",
			1,
			true
		) == 1
		then AIR_M2_ATTACKER_ANIMATION_ID
		else "rbxassetid://"
		.. AIR_M2_ATTACKER_ANIMATION_ID
end


-- ============================================================
-- STATE
-- ============================================================

local active =
	false

local hitSent =
	false

local serverConfirmed =
	false

local serverResolved =
	false

local whiffGateReached =
	false

local whiffGatePaused =
	false

local pendingBodyFlickerSequence: number? =
	nil

local flickerReadyFreezeToken =
	0

local sequence =
	0

local cooldownEndsAt =
	-math.huge

local transitionState: any =
	nil

local airM2SentForId: number? =
	nil

local airM2PendingMarkerId: number? =
	nil

-- Server releases the victim at the authored Release marker, but the attacker
-- stays locally constrained in the aerial pose until the M2 animation ends.
local deferredAirM2EndId: number? =
	nil

local deferredAirM2EndVelocity: Vector3? =
	nil

local airM2HitstopToken =
	0

local airM2AttackerLandingGuardToken =
	0

local commitMovementApplied =
	false


character:SetAttribute(
	"IsLauncherAttacking",
	false
)

character:SetAttribute(
	"LauncherPhase",
	"None"
)

character:SetAttribute(
	"LauncherCooldownEndsAt",
	nil
)

character:SetAttribute(
	"AirComboTransitionActive",
	false
)

character:SetAttribute(
	"AirComboActive",
	false
)

character:SetAttribute(
	"AirComboRole",
	nil
)

character:SetAttribute(
	"LauncherAirComboAttacker",
	false
)

character:SetAttribute(
	"LauncherAirComboVictim",
	false
)

character:SetAttribute(
	"AirM1Allowed",
	false
)


-- ============================================================
-- HELPERS
-- ============================================================

local function ctrlHeld(): boolean

	return UserInputService:IsKeyDown(
		Enum.KeyCode.LeftControl
	)
		or UserInputService:IsKeyDown(
			Enum.KeyCode.RightControl
		)
end


local function downedLocked(): boolean

	return character:GetAttribute(
		"DownedActionLocked"
	) == true

		or character:GetAttribute(
			"IsDowned"
		) == true

		or character:GetAttribute(
			"IsCarried"
		) == true

		or character:GetAttribute(
			"IsExecuting"
		) == true

		or character:GetAttribute(
			"IsCarrying"
		) == true
end


local function horizontalForward(): Vector3?

	local look =
		root.CFrame.LookVector

	local flat =
		Vector3.new(
			look.X,
			0,
			look.Z
		)

	if flat.Magnitude <= 0.05 then
		return nil
	end

	return flat.Unit
end


local function sharedGrounded(): boolean

	if character:GetAttribute(
		"SharedGrounded"
		) == true then

		return true
	end

	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		return true
	end

	local state =
		humanoid:GetState()

	return state ~=
		Enum.HumanoidStateType.Jumping
		and state ~=
		Enum.HumanoidStateType.Freefall
		and state ~=
		Enum.HumanoidStateType.FallingDown
end


-- Legacy BackflipArc movement removed in DB v4.1.

local function applyCommitMovement(
	source: string
)

	if commitMovementApplied
		or not active then

		return
	end


	commitMovementApplied =
		true


	local direction =
		horizontalForward()


	if direction then

		root:
			ApplyImpulse(
				direction
				* root.AssemblyMass
				* COMMIT_FORWARD_IMPULSE
			)
	end


	if DEBUG then

		print(
			"[LauncherClient v1.6] CommitMovement",
			source,
			"trackTime",
			string.format(
				"%.3f",
				track.TimePosition
			)
		)
	end
end


local function setCooldown()

	local localNow =
		time()

	cooldownEndsAt =
		localNow
		+ CLIENT_COOLDOWN

	-- Local monotonic time gates input. HUD timestamps use synchronized server time.
	local serverNow =
		workspace:GetServerTimeNow()

	local visibleCooldownEndsAt =
		serverNow
		+ CLIENT_COOLDOWN

	character:SetAttribute(
		"LauncherCooldownEndsAt",
		visibleCooldownEndsAt
	)

	character:SetAttribute(
		"CoreCooldown_Launcher_Label",
		"Launcher"
	)

	character:SetAttribute(
		"CoreCooldown_Launcher_StartsAt",
		serverNow
	)

	character:SetAttribute(
		"CoreCooldown_Launcher_EndsAt",
		visibleCooldownEndsAt
	)
end


local function stopLauncherTrack()

	if track.IsPlaying then

		track:
			Stop(
				ANIMATION_FADE_OUT
			)
	end
end


local function finishLauncher(
	cancelled: boolean
)

	if not active then
		return
	end


	active =
		false

	hitSent =
		false


	character:SetAttribute(
		"IsLauncherAttacking",
		false
	)


	if not transitionState then

		character:SetAttribute(
			"LauncherPhase",
			cancelled
				and "Cancelled"
				or "None"
		)
	end




	if cancelled then

		stopLauncherTrack()
	end


	if DEBUG then

		print(
			"[LauncherClient v1.6] Finish",
			sequence,
			cancelled
				and "CANCEL"
				or "END",
			"confirmed",
			serverConfirmed
		)
	end
end


local function isStatusCombatBlocked(): boolean
	return character:GetAttribute(
		"Status_AttackBlocked"
	) == true

		or character:GetAttribute(
			"Status_Stunned"
		) == true
end


local function canStart(): (boolean, string)

	if not ctrlHeld() then
		return false, "NoCtrl"
	end

	if active
		or transitionState then

		return false, "AlreadyActive"
	end

	if time() <
		cooldownEndsAt then

		return false, "Cooldown"
	end

	if humanoid.Health <= 0 then
		return false, "Dead"
	end

	if character:GetAttribute(
		"CombatMode"
		) ~= true then

		return false, "CombatModeOff"
	end

	if character:GetAttribute(
		"CombatSuppressed"
		) == true then

		return false, "CombatSuppressed"
	end

	if character:GetAttribute(
		"IsStunned"
		) == true
			or isStatusCombatBlocked() then

		return false, "Stunned/StatusAttackBlocked"
	end

	if downedLocked() then
		return false, "DownedLocked"
	end

	if character:GetAttribute(
		"IsBlocking"
		) == true then

		return false, "Blocking"
	end

	if character:GetAttribute(
		"IsDashing"
		) == true
			or character:GetAttribute(
				"AirDashCarryActive"
			) == true then

		return false, "Dashing"
	end

	if character:GetAttribute(
		"IsLungeAttacking"
		) == true then

		return false, "LungeActive"
	end

	if character:GetAttribute(
		"IsClashing"
		) == true
			or character:GetAttribute(
				"ClashServerActive"
			) == true then

		return false, "Clashing"
	end

	if character:GetAttribute(
		"IsAttacking"
		) == true then

		return false, "M1Active"
	end

	if character:GetAttribute(
		"IsThrowingKunai"
		) == true then

		return false, "Throwing"
	end

	if character:GetAttribute(
		"TreeJumpActive"
		) == true
			or character:GetAttribute(
				"IsTreeJumping"
			) == true then

		return false, "TreeJump"
	end

	if not sharedGrounded() then
		return false, "NotGrounded"
	end

	return true, "Ready"
end


-- ============================================================
-- AIR TRANSITION LOCAL MOTION
-- ============================================================
--
-- v1.5 IMPORTANT:
-- The old QA implementation wrote HumanoidRootPart.CFrame every RenderStepped
-- while the Humanoid state machine was still trying to fall/get up. That made
-- two systems fight over the same assembly and produced visible trembling.
--
-- The aerial window now has ONE physical owner:
--   AlignPosition + AlignOrientation + Humanoid Physics state.
-- We only animate the constraint target during the rise; the root itself is
-- never teleported every frame.
--
-- The normal Animate locomotion layer is temporarily disabled so Roblox's
-- default fall pose does not cover the aerial hold. Action-priority M1 tracks
-- loaded by AttackController can still play normally.

local function stopLowPriorityLocomotionTracks()
	for _, playingTrack in ipairs(
		animator:GetPlayingAnimationTracks()
		) do
		if playingTrack ~= track
			and playingTrack.Priority.Value
			<= Enum.AnimationPriority.Movement.Value then

			playingTrack:Stop(0.05)
		end
	end
end


local function destroyTransitionConstraints(
	state: any
)
	if state.alignPosition
		and state.alignPosition.Parent then

		state.alignPosition:Destroy()
	end

	if state.alignOrientation
		and state.alignOrientation.Parent then

		state.alignOrientation:Destroy()
	end

	if state.attachment
		and state.attachment.Parent then

		state.attachment:Destroy()
	end

	state.alignPosition = nil
	state.alignOrientation = nil
	state.attachment = nil
end


local function stopTransition(
	reason: string,
	releaseVelocity: Vector3?
)

	local state =
		transitionState

	if not state then
		return
	end


	transitionState =
		nil

	airM2SentForId =
		nil

	airM2PendingMarkerId =
		nil

	deferredAirM2EndId =
		nil

	deferredAirM2EndVelocity =
		nil

	if airM2Track
		and airM2Track.IsPlaying
		and reason ~= "AirM2" then

		airM2Track:
			Stop(
				0.05
			)
	end


	character:SetAttribute(
		"AirComboTransitionActive",
		false
	)

	character:SetAttribute(
		"AirComboActive",
		false
	)

	character:SetAttribute(
		"AirComboRole",
		nil
	)

	character:SetAttribute(
		"LauncherAirComboAttacker",
		false
	)

	character:SetAttribute(
		"LauncherAirComboVictim",
		false
	)

	character:SetAttribute(
		"AirM1Allowed",
		false
	)

	character:SetAttribute(
		"LauncherPhase",
		"None"
	)


	destroyTransitionConstraints(
		state
	)


	root.AssemblyLinearVelocity =
		typeof(releaseVelocity) == "Vector3"
		and releaseVelocity
		or Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero


	humanoid.AutoRotate =
		state.savedAutoRotate


	if state.animateScript
		and state.animateScript.Parent
		and state.animateWasEnabled ~= nil then

		state.animateScript.Enabled =
			state.animateWasEnabled
	end


	if humanoid.Parent
		and humanoid.Health > 0 then

		if humanoid.FloorMaterial ==
			Enum.Material.Air then

			humanoid:ChangeState(
				Enum.HumanoidStateType.Freefall
			)
		else
			humanoid:ChangeState(
				Enum.HumanoidStateType.Running
			)
		end
	end


	if DEBUG then

		print(
			"[LauncherClient v1.6] Air transition END",
			reason
		)
	end
end


local function suppressAirborneIdleLocomotion()
	for _, playingTrack in ipairs(
		animator:GetPlayingAnimationTracks()
		) do

		local lowerName =
			string.lower(
				playingTrack.Name
			)

		if string.find(lowerName, "idle", 1, true)
			or string.find(lowerName, "walk", 1, true)
			or string.find(lowerName, "run", 1, true) then

			playingTrack:
				Stop(
					0.04
				)
		end
	end
end


local function keepAttackerInFreefallWhileAirborne()
	local currentState =
		humanoid:GetState()

	if currentState ~= Enum.HumanoidStateType.Freefall
		and currentState ~= Enum.HumanoidStateType.Jumping
		and currentState ~= Enum.HumanoidStateType.Swimming then

		humanoid:
			ChangeState(
				Enum.HumanoidStateType.Freefall
			)
	end

	suppressAirborneIdleLocomotion()
end


local function beginAirM2AttackerLandingGuard(
	airComboId: number
)
	airM2AttackerLandingGuardToken += 1
	local token =
		airM2AttackerLandingGuardToken

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}

	params.RespectCanCollide =
		true

	local startedAt =
		time()

	local settling =
		false

	local settleStartedAt =
		0.0

	local connection: RBXScriptConnection? =
		nil

	local function finishGuard()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	connection =
		RunService.PreSimulation:
		Connect(
			function(
				deltaTime: number
			)
				if token ~= airM2AttackerLandingGuardToken
					or not character.Parent
					or not root.Parent
					or not humanoid.Parent
					or humanoid.Health <= 0 then

					finishGuard()
					return
				end

				if time() - startedAt >
					AIR_M2_ATTACKER_LANDING_GUARD_TIMEOUT then

					finishGuard()
					return
				end

				local result =
				workspace:Raycast(
					root.Position,
					Vector3.new(
						0,
						-AIR_M2_ATTACKER_LANDING_PROBE_DISTANCE,
						0
					),
					params
				)

				local validGround =
				result ~= nil
				and result.Normal.Y >=
				AIR_M2_ATTACKER_LANDING_NORMAL_Y_MIN

				local velocity =
				root.AssemblyLinearVelocity

				if not settling then
					if not validGround then
						keepAttackerInFreefallWhileAirborne()
						return
					end

					if velocity.Y > 1.0 then
						keepAttackerInFreefallWhileAirborne()
						return
					end

					local distance =
					(result :: RaycastResult).Distance

					local predictedTravel =
					math.max(
						0,
						-velocity.Y
					)
					* deltaTime

					local preBrakeDistance =
					AIR_M2_ATTACKER_LANDING_ROOT_OFFSET
					+ predictedTravel
					+ 0.20

					if distance <= preBrakeDistance
						and velocity.Y <
						-AIR_M2_ATTACKER_LANDING_PREBRAKE_SPEED then

						root.AssemblyLinearVelocity =
						Vector3.new(
							velocity.X,
							-AIR_M2_ATTACKER_LANDING_PREBRAKE_SPEED,
							velocity.Z
						)

						velocity =
						root.AssemblyLinearVelocity
					end

					if distance >
						AIR_M2_ATTACKER_LANDING_ROOT_OFFSET
						+ AIR_M2_ATTACKER_LANDING_CONTACT_TOLERANCE then

						keepAttackerInFreefallWhileAirborne()
						return
					end

					settling = true
					settleStartedAt = time()

					-- Preserve horizontal control, remove only the landing impulse.
					root.AssemblyLinearVelocity =
					Vector3.new(
						velocity.X,
						0,
						velocity.Z
					)

					root.AssemblyAngularVelocity =
					Vector3.zero

					stopLowPriorityLocomotionTracks()

					humanoid:ChangeState(
						Enum.HumanoidStateType.Running
					)

					if DEBUG then
						print(
							"[LauncherClient] AIR M2 attacker landing settle",
							airComboId,
							"distance",
							string.format("%.2f", distance)
						)
					end
					return
				end

				local stillNearGround =
				validGround
				and (result :: RaycastResult).Distance <=
				AIR_M2_ATTACKER_LANDING_ROOT_OFFSET
				+ 0.35

				if stillNearGround then
					local settleVelocity =
					root.AssemblyLinearVelocity

					if settleVelocity.Y ~= 0 then
						root.AssemblyLinearVelocity =
						Vector3.new(
							settleVelocity.X,
							0,
							settleVelocity.Z
						)
					end

					local currentState =
					humanoid:GetState()

					if currentState == Enum.HumanoidStateType.Freefall
						or currentState == Enum.HumanoidStateType.FallingDown then

						humanoid:ChangeState(
							Enum.HumanoidStateType.Running
						)
					end
				end

				if time() - settleStartedAt >=
					AIR_M2_ATTACKER_LANDING_BOUNCE_DAMP_TIME then

					finishGuard()
				end
			end
		)
end


local function beginTransition(
	airComboId: number,
	role: string,
	transitionStartsAt: number,
	transitionDuration: number,
	holdDuration: number,
	startCFrame: CFrame,
	targetCFrame: CFrame
)

	airM2AttackerLandingGuardToken += 1

	if transitionState then

		stopTransition(
			"Replaced",
			nil
		)
	end


	-- Victims do not own the attacker's Launcher animation.
	-- On the attacker, keep the authored track alive through:
	-- WhiffEnd -> FlickerReady -> BodyFlicker -> LauncherEnd.
	if role ~= "Attacker" then
		stopLauncherTrack()
	end


	local animateScript: BaseScript? = nil
	local animateCandidate =
		character:FindFirstChild("Animate")

	if animateCandidate
		and animateCandidate:IsA("BaseScript") then

		animateScript =
			animateCandidate
	end


	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"LauncherAirHoldAttachment"

	attachment.Parent =
		root


	local alignPosition =
		Instance.new("AlignPosition")

	alignPosition.Name =
		"LauncherAirHoldPosition"

	alignPosition.Mode =
		Enum.PositionAlignmentMode.OneAttachment

	alignPosition.Attachment0 =
		attachment

	alignPosition.ApplyAtCenterOfMass =
		true

	alignPosition.RigidityEnabled =
		false

	alignPosition.MaxForce =
		250000

	alignPosition.MaxVelocity =
		role == "Attacker"
		and 320
		or 120

	alignPosition.Responsiveness =
		role == "Attacker"
		and 85
		or 42

	alignPosition.Position =
		startCFrame.Position

	alignPosition.Parent =
		root


	local alignOrientation =
		Instance.new("AlignOrientation")

	alignOrientation.Name =
		"LauncherAirHoldOrientation"

	alignOrientation.Mode =
		Enum.OrientationAlignmentMode.OneAttachment

	alignOrientation.Attachment0 =
		attachment

	alignOrientation.RigidityEnabled =
		false

	alignOrientation.MaxTorque =
		250000

	alignOrientation.MaxAngularVelocity =
		80

	alignOrientation.Responsiveness =
		45

	alignOrientation.CFrame =
		targetCFrame.Rotation

	alignOrientation.Parent =
		root


	local state = {
		id = airComboId,
		role = role,

		transitionStartsAt =
			transitionStartsAt,

		transitionDuration =
			transitionDuration,

		holdDuration =
			holdDuration,

		startCFrame =
			startCFrame,

		targetCFrame =
			targetCFrame,

		savedAutoRotate =
			humanoid.AutoRotate,

		animateScript =
			animateScript,

		animateWasEnabled =
			animateScript
			and animateScript.Enabled
			or nil,

		attachment =
			attachment,

		alignPosition =
			alignPosition,

		alignOrientation =
			alignOrientation,

		phase =
			"Waiting",

		bodyFlickerTriggeredAt =
			nil,

		holdStartedAt =
			nil,

		holdEndsAt =
			nil,

		holdReported =
			false,
	}


	transitionState =
		state


	humanoid.AutoRotate =
		false

	humanoid:ChangeState(
		Enum.HumanoidStateType.Physics
	)


	if animateScript then
		animateScript.Enabled =
			false
	end

	stopLowPriorityLocomotionTracks()


	character:SetAttribute(
		"AirComboTransitionActive",
		true
	)

	character:SetAttribute(
		"AirComboActive",
		false
	)

	character:SetAttribute(
		"AirComboRole",
		role
	)

	character:SetAttribute(
		"LauncherAirComboAttacker",
		role == "Attacker"
	)

	character:SetAttribute(
		"LauncherAirComboVictim",
		role == "Victim"
	)

	-- Do not arm aerial M1 while the attacker is still below / preparing /
	-- Body Flickering. It becomes true only after the attacker reaches Hold.
	character:SetAttribute(
		"AirM1Allowed",
		false
	)

	character:SetAttribute(
		"LauncherPhase",
		"AirFollow"
	)


	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero


	if DEBUG then

		print(
			"[LauncherClient v1.6] Air transition BEGIN",
			airComboId,
			role,
			"rise",
			transitionDuration,
			"hold",
			holdDuration,
			"constraintHold",
			true,
			"airM1",
			role == "Attacker"
		)
	end
end


RunService.RenderStepped:
	Connect(
		function()

			local state =
			transitionState

			if not state then
				return
			end


			if not state.alignPosition
				or not state.alignPosition.Parent
				or not state.alignOrientation
				or not state.alignOrientation.Parent then

				stopTransition(
					"ConstraintMissing",
					nil
				)

				return
			end


			local serverNow =
			workspace:
			GetServerTimeNow()


			if serverNow <
				state.transitionStartsAt then

				state.alignPosition.Position =
				state.startCFrame.Position

				state.alignOrientation.CFrame =
				state.targetCFrame.Rotation

				return
			end


			local elapsed =
			serverNow
			- state.transitionStartsAt


			if state.role == "Attacker" then

				local flickerTriggeredAt =
				state.bodyFlickerTriggeredAt

				if typeof(flickerTriggeredAt) ~= "number" then

					-- Enemy is already rising. Keep the attacker in the authored
					-- preparation pose at the original launch point until the
					-- BodyFlicker marker tells us to follow.
					state.phase =
					"FlickerReadyWait"

					state.alignPosition.Position =
					state.startCFrame.Position

					state.alignOrientation.CFrame =
					state.targetCFrame.Rotation

					character:SetAttribute(
						"LauncherPhase",
						"FlickerReadyWait"
					)

				else

					local flickerElapsed =
					serverNow
					- flickerTriggeredAt

					if flickerElapsed <
						AIR_ATTACKER_BODY_FLICKER_DURATION then

						if state.phase ~= "BodyFlicker" then
							state.phase =
							"BodyFlicker"

							if DEBUG then
								print(
									"[LauncherClient] AIR FOLLOW BODY FLICKER",
									state.id,
									string.format(
										"%.3fs",
										AIR_ATTACKER_BODY_FLICKER_DURATION
									)
								)
							end
						end

						local alpha =
						math.clamp(
							flickerElapsed
							/ AIR_ATTACKER_BODY_FLICKER_DURATION,
							0,
							1
						)

						local eased =
						1
						- math.pow(
							1 - alpha,
							4
						)

						state.alignPosition.Position =
						state.startCFrame.Position:
						Lerp(
							state.targetCFrame.Position,
							eased
						)

						state.alignOrientation.CFrame =
						state.targetCFrame.Rotation

						character:SetAttribute(
							"LauncherPhase",
							"BodyFlickerFollow"
						)

					else

						if state.phase ~= "Hold" then
							state.phase =
							"Hold"

							state.holdStartedAt =
							serverNow

							state.holdEndsAt =
							serverNow
							+ state.holdDuration

							character:SetAttribute(
								"AirComboTransitionActive",
								false
							)

							character:SetAttribute(
								"AirComboActive",
								true
							)

							-- This is the first legal aerial-M1 frame:
							-- BodyFlicker has completed and attacker is at target.
							character:SetAttribute(
								"AirM1Allowed",
								true
							)

							character:SetAttribute(
								"LauncherPhase",
								"AirComboHold"
							)

							if state.holdReported ~= true then
								state.holdReported =
								true

								launcherEvent:
								FireServer(
									"AirFollowArrived",
									state.id,
									serverNow
								)
							end

							if DEBUG then
								print(
									"[LauncherClient] AIR HOLD START ON ARRIVAL",
									state.id,
									"duration",
									state.holdDuration,
									"AirM1Allowed",
									character:GetAttribute(
										"AirM1Allowed"
									)
								)
							end
						end

						state.alignPosition.Position =
						state.targetCFrame.Position

						state.alignOrientation.CFrame =
						state.targetCFrame.Rotation

						if typeof(state.holdEndsAt) == "number"
							and serverNow >= state.holdEndsAt then

							stopTransition(
								"LocalTimeout",
								nil
							)
						end
					end
				end

			else

				-- Victim still launches immediately using the existing smooth
				-- 0.48s rise. Its local hold is intentionally oversized; the
				-- server ends it using the real timer that starts on attacker arrival.
				if elapsed <
					state.transitionDuration then

					state.phase =
					"Rise"

					local alpha =
					math.clamp(
						elapsed
						/ state.transitionDuration,
						0,
						1
					)

					local eased =
					1
					- math.pow(
						1 - alpha,
						3
					)

					state.alignPosition.Position =
					state.startCFrame.Position:
					Lerp(
						state.targetCFrame.Position,
						eased
					)

					state.alignOrientation.CFrame =
					state.targetCFrame.Rotation

					character:SetAttribute(
						"LauncherPhase",
						"AirFollow"
					)

				elseif elapsed <
					state.transitionDuration
					+ state.holdDuration then

					if state.phase ~= "Hold" then
						state.phase =
						"Hold"

						character:SetAttribute(
							"AirComboTransitionActive",
							false
						)

						character:SetAttribute(
							"AirComboActive",
							true
						)

						character:SetAttribute(
							"AirM1Allowed",
							false
						)

						character:SetAttribute(
							"LauncherPhase",
							"AirComboHold"
						)

						if DEBUG then
							print(
								"[LauncherClient v1.6] AIR HOLD ACTIVE",
								state.id,
								state.role,
								"state",
								humanoid:GetState().Name,
								"AirM1Allowed",
								character:GetAttribute(
									"AirM1Allowed"
								)
							)
						end
					end

					state.alignPosition.Position =
					state.targetCFrame.Position

					state.alignOrientation.CFrame =
					state.targetCFrame.Rotation

				else

					stopTransition(
						"LocalTimeout",
						nil
					)
				end
			end
		end
	)


local function reportBodyFlickerPresentation(
	stage: string
)
	local state =
		transitionState

	if not state
		or state.role ~= "Attacker" then
		return
	end

	launcherEvent:
		FireServer(
			"BodyFlickerVisual",
			state.id,
			stage
		)
end


local function triggerMarkerDrivenBodyFlicker(
	source: string
)
	local state =
		transitionState

	if state
		and state.role == "Attacker"
		and state.bodyFlickerTriggeredAt == nil then

		reportBodyFlickerPresentation(
			"Disappear"
		)

		state.bodyFlickerTriggeredAt =
			workspace:
			GetServerTimeNow()

		pendingBodyFlickerSequence =
			nil

		if DEBUG then
			print(
				"[LauncherClient] BODY FLICKER TRIGGER",
				state.id,
				source
			)
		end

		return
	end

	-- Network can deliver AirBegin a frame after the authored marker.
	-- Queue it instead of losing the marker.
	pendingBodyFlickerSequence =
		sequence

	if DEBUG then
		print(
			"[LauncherClient] BODY FLICKER QUEUED",
			sequence,
			source
		)
	end
end


-- ============================================================
-- LAUNCHER ATTACK
-- ============================================================

local function startLauncher(): boolean

	local eligible,
		reason =
		canStart()


	if not eligible then

		if DEBUG
			and reason ~= "NoCtrl" then

			print(
				"[LauncherClient v1.6] blocked:",
				reason
			)
		end

		-- Ctrl is held: consume the click even if blocked.
		return ctrlHeld()
	end


	sequence +=
		1


	active =
		true

	hitSent =
		false

	serverConfirmed =
		false

	serverResolved =
		false

	whiffGateReached =
		false

	whiffGatePaused =
		false

	pendingBodyFlickerSequence =
		nil

	flickerReadyFreezeToken +=
		1

	commitMovementApplied =
		false


	character:SetAttribute(
		"IsLauncherAttacking",
		true
	)

	character:SetAttribute(
		"LauncherPhase",
		"Startup"
	)


	setCooldown()


	launcherEvent:
		FireServer(
			"Start",
			sequence,
			workspace:
			GetServerTimeNow()
		)


	track:
		Play(
			ANIMATION_FADE_IN,
			1,
			ANIMATION_PLAYBACK_SPEED
		)


	if DEBUG then

		print(
			"[LauncherClient v1.7] Start",
			sequence,
			"Animation=135785314988292"
		)
	end


	return true
end


track:
	GetMarkerReachedSignal(
		"LauncherStart"
	):
	Connect(
		function()

			if not active then
				return
			end


			character:SetAttribute(
				"LauncherPhase",
				"Startup"
			)


			local launcherStartSequence =
			sequence


			-- The current exported asset did not emit Commit in the supplied log.
			-- Keep the marker supported, but guarantee the old forward commitment
			-- even if that marker is absent.
			task.delay(
				COMMIT_FALLBACK_DELAY,
				function()

					if active
						and sequence ==
						launcherStartSequence
						and not commitMovementApplied then

						applyCommitMovement(
							"Fallback"
						)
					end
				end
			)


			if DEBUG then

				print(
					"[LauncherClient v1.6] LauncherStart",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					),
					"state",
					humanoid:GetState().Name,
					"floor",
					humanoid.FloorMaterial.Name
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"Commit"
	):
	Connect(
		function()

			if not active then
				return
			end


			character:SetAttribute(
				"LauncherPhase",
				"Commit"
			)


			applyCommitMovement(
				"Marker"
			)


			if DEBUG then

				print(
					"[LauncherClient v1.6] Commit",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					),
					"state",
					humanoid:GetState().Name,
					"floor",
					humanoid.FloorMaterial.Name
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"Hit"
	):
	Connect(
		function()

			if not active
				or hitSent then

				return
			end


			hitSent =
			true


			character:SetAttribute(
				"LauncherPhase",
				"Hit"
			)


			launcherEvent:
			FireServer(
				"Hit",
				sequence,
				workspace:
				GetServerTimeNow()
			)


			if DEBUG then

				print(
					"[LauncherClient v1.6] Hit",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					),
					"state",
					humanoid:GetState().Name,
					"floor",
					humanoid.FloorMaterial.Name,
					"yVel",
					string.format(
						"%.2f",
						root.AssemblyLinearVelocity.Y
					)
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		LAUNCHER_WHIFF_END_MARKER
	):
	Connect(
		function()

			if not active then
				return
			end

			whiffGateReached =
			true

			if DEBUG then
				print(
					"[LauncherClient] WhiffEnd",
					sequence,
					"resolved",
					serverResolved,
					"confirmed",
					serverConfirmed
				)
			end

			if serverResolved then
				if serverConfirmed then
					return
				end

				track:
				Stop(
					ANIMATION_FADE_OUT
				)

				finishLauncher(
					false
				)

				return
			end

			-- Do not let a laggy MISS enter the HIT-only tail.
			whiffGatePaused =
			true

			track:
			AdjustSpeed(
				0
			)

			local gateSequence =
			sequence

			task.delay(
				LAUNCHER_HIT_RESOLVE_GRACE,
				function()

					if not active
						or sequence ~= gateSequence
						or not whiffGatePaused
						or serverResolved then

						return
					end

					serverResolved =
					true

					serverConfirmed =
					false

					whiffGatePaused =
					false

					if DEBUG then
						warn(
							"[LauncherClient] WhiffEnd resolve timeout -> MISS",
							gateSequence
						)
					end

					track:
					Stop(
						ANIMATION_FADE_OUT
					)

					finishLauncher(
						false
					)
				end
			)
		end
	)


track:
	GetMarkerReachedSignal(
		LAUNCHER_FLICKER_READY_MARKER
	):
	Connect(
		function()

			if not active
				or not serverConfirmed then

				return
			end

			character:SetAttribute(
				"LauncherPhase",
				"FlickerReady"
			)

			reportBodyFlickerPresentation(
				"Ready"
			)

			flickerReadyFreezeToken +=
			1

			local freezeToken =
			flickerReadyFreezeToken

			local freezeSequence =
			sequence

			track:
			AdjustSpeed(
				0
			)

			if DEBUG then
				print(
					"[LauncherClient] FlickerReady FREEZE",
					sequence,
					string.format(
						"%.2fs",
						FLICKER_READY_FREEZE_DURATION
					),
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					)
				)
			end

			task.delay(
				FLICKER_READY_FREEZE_DURATION,
				function()

					if not active
						or sequence ~= freezeSequence
						or flickerReadyFreezeToken ~= freezeToken
						or not serverConfirmed
						or not track.IsPlaying then

						return
					end

					track:
					AdjustSpeed(
						ANIMATION_PLAYBACK_SPEED
					)

					if DEBUG then
						print(
							"[LauncherClient] FlickerReady RELEASE",
							freezeSequence
						)
					end
				end
			)
		end
	)


track:
	GetMarkerReachedSignal(
		LAUNCHER_BODY_FLICKER_MARKER
	):
	Connect(
		function()

			if not active
				or not serverConfirmed then

				return
			end

			triggerMarkerDrivenBodyFlicker(
				"BodyFlickerMarker"
			)
		end
	)


track:
	GetMarkerReachedSignal(
		"RecoveryStart"
	):
	Connect(
		function()

			if not active then
				return
			end


			character:SetAttribute(
				"LauncherPhase",
				"Recovery"
			)


			if DEBUG then

				print(
					"[LauncherClient v1.6] RecoveryStart",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					),
					"state",
					humanoid:GetState().Name
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"LauncherEnd"
	):
	Connect(
		function()

			if not active then
				return
			end


			character:SetAttribute(
				"LauncherPhase",
				"LauncherEnd"
			)


			if DEBUG then

				print(
					"[LauncherClient v1.6] LauncherEnd",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					),
					"state",
					humanoid:GetState().Name
				)
			end


			finishLauncher(
				false
			)

		end
	)


track.Ended:
	Connect(
		function()

			-- LauncherEnd is optional in QA.
			-- If this export has only four markers, natural AnimationTrack.Ended
			-- is a fully supported clean completion path.
			if active then

				if DEBUG then

					print(
						"[LauncherClient v1.6] TrackEnded",
						sequence,
						"state",
						humanoid:GetState().Name
					)
				end


				finishLauncher(
					false
				)
			end
		end
	)


-- ============================================================
-- DB: OLD CCL/TRIP-STATE QA OBSERVER REMOVED
-- Character Controller Library / AbilityManagerActor is disabled at the
-- experience level, so the animation no longer needs trip-state diagnostics.
-- ============================================================

-- ============================================================
-- AIR M2 FINISHER
-- ============================================================

local function clearAirM2TrackConnections()
	for _, connection in ipairs(
		airM2TrackConnections
		) do
		connection:
			Disconnect()
	end

	table.clear(
		airM2TrackConnections
	)
end


local function dispatchAirM2Release(
	airComboId: number,
	source: string?
)
	local state = transitionState

	if not state
		or state.id ~= airComboId
		or state.role ~= "Attacker"
		or state.phase ~= "Hold"
		or character:GetAttribute("AirComboActive") ~= true then
		return
	end

	airM2PendingMarkerId = nil

	launcherEvent:FireServer(
		"AirM2",
		airComboId,
		workspace:GetServerTimeNow()
	)

	if DEBUG then
		print(
			"[LauncherClient] AIR M2 RELEASE",
			source or "Marker",
			airComboId
		)
	end
end


local function performAirM2ImpactHitstop(
	airComboId: number,
	track: AnimationTrack
)
	if airM2PendingMarkerId ~= airComboId
		or airM2Track ~= track
		or not track.IsPlaying then
		return
	end

	airM2HitstopToken += 1
	local token = airM2HitstopToken

	-- Marker-authored contact feedback is broadcast by the server so every
	-- nearby client sees the same Shoot/Wind VFX and camera impact timing.
	launcherEvent:FireServer(
		"AirM2Impact",
		airComboId,
		workspace:GetServerTimeNow()
	)

	track:AdjustSpeed(0)

	if DEBUG then
		print(
			"[LauncherClient] AIR M2 IMPACT hitstop",
			airComboId,
			string.format("%.3fs", AIR_M2_HITSTOP_DURATION)
		)
	end

	task.delay(
		AIR_M2_HITSTOP_DURATION,
		function()
			if token ~= airM2HitstopToken
				or airM2PendingMarkerId ~= airComboId
				or airM2Track ~= track
				or not track.IsPlaying then
				return
			end

			track:
				AdjustSpeed(
					AIR_M2_ATTACKER_PLAYBACK_SPEED
				)
		end
	)
end


local function createAirM2TrackForAttempt(
	airComboId: number
): AnimationTrack?
	if not airM2Animation then
		return nil
	end

	-- Never replay the same AnimationTrack instance. This is intentionally
	-- instance-per-attempt because QA showed marker delivery becoming stale
	-- after the first M2 playback.
	airM2HitstopToken += 1
	clearAirM2TrackConnections()

	if airM2Track
		and airM2Track.IsPlaying then

		airM2Track:
			AdjustSpeed(
				AIR_M2_ATTACKER_PLAYBACK_SPEED
			)

		airM2Track:
			Stop(
				0.025
			)
	end

	local track =
		animator:
		LoadAnimation(
			airM2Animation
		)

	track.Priority =
		Enum.AnimationPriority.Action4

	track.Looped =
		false

	airM2Track =
		track

	table.insert(
		airM2TrackConnections,
		track:
			GetMarkerReachedSignal(
				AIR_M2_ATTACKER_IMPACT_MARKER
			):
			Connect(
				function()
					if airM2Track == track
						and airM2PendingMarkerId ==
						airComboId then

						performAirM2ImpactHitstop(
							airComboId,
							track
						)
					end
				end
			)
	)

	table.insert(
		airM2TrackConnections,
		track:
			GetMarkerReachedSignal(
				AIR_M2_ATTACKER_RELEASE_MARKER
			):
			Connect(
				function()
					if airM2Track == track
						and airM2PendingMarkerId ==
						airComboId then

						dispatchAirM2Release(
							airComboId,
							"Marker"
						)
					end
				end
			)
	)

	table.insert(
		airM2TrackConnections,
		track.Ended:
			Connect(
				function()
					if airM2Track ~= track then
						return
					end

					if airM2PendingMarkerId ==
						airComboId then

						dispatchAirM2Release(
							airComboId,
							"EndedFallback"
						)
					end

					if deferredAirM2EndId ==
						airComboId
						and transitionState
						and transitionState.id ==
						airComboId
						and transitionState.role ==
						"Attacker" then

						if DEBUG then
							print(
								"[LauncherClient] AIR M2 attacker animation ended -> fall",
								airComboId
							)
						end

						local currentVelocity =
						root.AssemblyLinearVelocity

						local fallReleaseVelocity =
						Vector3.new(
							currentVelocity.X,
							-AIR_M2_ATTACKER_FALL_RELEASE_SPEED,
							currentVelocity.Z
						)

						stopTransition(
							"AirM2AnimationEnded",
							fallReleaseVelocity
						)

						beginAirM2AttackerLandingGuard(
							airComboId
						)
					end

					clearAirM2TrackConnections()
				end
			)
	)

	return track
end


local function tryAirM2Finisher(): boolean
	local state =
		transitionState

	if not state
		or state.role ~= "Attacker"
		or state.phase ~= "Hold"
		or character:GetAttribute(
			"AirComboActive"
		) ~= true
			or character:GetAttribute(
				"LauncherAirComboAttacker"
			) ~= true then

		return false
	end

	if airM2SentForId ==
		state.id then

		return true
	end

	airM2SentForId =
		state.id

	-- Commit immediately: M2 owns the rest of the aerial offense, while
	-- launch physics still wait for the authored Release marker.
	character:SetAttribute("AirM1Allowed", false)

	launcherEvent:FireServer(
		"AirM2Windup",
		state.id,
		workspace:GetServerTimeNow()
	)

	airM2PendingMarkerId =
		state.id

	local track =
		createAirM2TrackForAttempt(
			state.id
		)

	if not track then
		dispatchAirM2Release(
			state.id,
			"NoAnimationFallback"
		)

		return true
	end

	track:
		Play(
			0.035
		)

	-- Explicitly normalize every fresh playback.
	track:
		AdjustSpeed(
			AIR_M2_ATTACKER_PLAYBACK_SPEED
		)

	task.delay(
		AIR_M2_RELEASE_FAILSAFE_DELAY,
		function()
			if transitionState
				and transitionState.id ==
				state.id
				and airM2PendingMarkerId ==
				state.id
				and character:GetAttribute(
					"AirComboActive"
				) == true then

				if DEBUG then
					warn(
						"[LauncherClient] AIR M2 Release marker failsafe",
						state.id
					)
				end

				dispatchAirM2Release(
					state.id,
					"TimedFailsafe"
				)
			end
		end
	)

	if DEBUG then
		print(
			"[LauncherClient] AIR M2 animation",
			state.id,
			"freshTrack=YES",
			"Impact=hitstop",
			"Release=launch"
		)
	end

	return true
end


UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)

			if gameProcessed
				or UserInputService:
				GetFocusedTextBox() then

				return
			end

			if input.UserInputType ~=
				Enum.UserInputType.MouseButton2 then

				return
			end

			tryAirM2Finisher()
		end
	)


-- ============================================================
-- ATTACKCONTROLLER ENDPOINT
-- ============================================================

local existing =
	character:
	FindFirstChild(
		LAUNCHER_BINDABLE_NAME
	)

if existing then
	existing:
		Destroy()
end


local endpoint =
	Instance.new(
		"BindableFunction"
	)

endpoint.Name =
	LAUNCHER_BINDABLE_NAME

endpoint.Parent =
	character


endpoint.OnInvoke =
	function(): boolean

		-- Normal Mouse1: Launcher must be invisible to AttackController.
		if not ctrlHeld() then
			return false
		end


		if active
			or transitionState then

			return true
		end


		return startLauncher()
	end


-- ============================================================
-- SERVER EVENTS
-- ============================================================

launcherEvent.OnClientEvent:
	Connect(
		function(
			action: string,
			...: any
		)

			local args = {
				...
			}


			if action ==
				"HitConfirmed" then

				local confirmedSequence =
				args[1]


				if confirmedSequence ~=
					sequence then

					return
				end


				serverResolved =
				true

				serverConfirmed =
				true

				if whiffGatePaused then
					whiffGatePaused =
					false

					track:
					AdjustSpeed(
						ANIMATION_PLAYBACK_SPEED
					)
				end


				character:SetAttribute(
					"LauncherPhase",
					"Confirmed"
				)


				if DEBUG then

					print(
						"[LauncherClient v1.6] HIT CONFIRMED",
						sequence
					)
				end


			elseif action ==
				"HitMissed" then

				local missedSequence =
				args[1]


				if missedSequence ~=
					sequence then

					return
				end


				serverResolved =
				true

				serverConfirmed =
				false

				if whiffGatePaused
					or whiffGateReached then

					whiffGatePaused =
					false

					track:
					Stop(
						ANIMATION_FADE_OUT
					)

					finishLauncher(
						false
					)

					return
				end


				if DEBUG then

					print(
						"[LauncherClient v1.6] MISS",
						sequence,
						"| RecoveryPlayback=CONTINUE"
					)
				end


				-- MISS is allowed to continue only until WhiffEnd.
				-- FlickerReady / BodyFlicker are HIT-only.


			elseif action ==
				"AirBegin" then

				local airComboId =
				args[1] :: number

				local role =
				args[2] :: string

				local transitionStartsAt =
				args[3] :: number

				local transitionDuration =
				args[4] :: number

				local holdDuration =
				args[5] :: number

				local startCFrame =
				args[6] :: CFrame

				local targetCFrame =
				args[7] :: CFrame


				serverResolved =
				true

				serverConfirmed =
				true

				airM2SentForId =
				nil


				if role == "Attacker" then
					-- No legacy startup jump/force remains to clean up.
				else
					finishLauncher(
						false
					)
				end


				beginTransition(
					airComboId,
					role,
					transitionStartsAt,
					transitionDuration,
					holdDuration,
					startCFrame,
					targetCFrame
				)

				if role == "Attacker"
					and pendingBodyFlickerSequence ==
					sequence then

					triggerMarkerDrivenBodyFlicker(
						"QueuedBeforeAirBegin"
					)
				end


			elseif action ==
				"AirEnd" then

				local airComboId =
				args[1] :: number

				local reason =
				tostring(
					args[2]
				)

				local releaseVelocity =
				args[3]


				if transitionState
					and transitionState.id ==
					airComboId then

					if reason == "AirM2"
						and transitionState.role ==
						"Attacker"
						and airM2Track
						and airM2Track.IsPlaying then

						deferredAirM2EndId =
						airComboId

						deferredAirM2EndVelocity =
						nil

						if DEBUG then
							print(
								"[LauncherClient] AIR M2 attacker fall deferred until animation end",
								airComboId
							)
						end

						-- Safety only: natural AnimationTrack.Ended is the normal path.
						task.delay(
							2.75,
							function()
								if deferredAirM2EndId ==
									airComboId
									and transitionState
									and transitionState.id ==
									airComboId
									and transitionState.role ==
									"Attacker" then

									warn(
										"[LauncherClient] AIR M2 attacker end failsafe",
										airComboId
									)

									stopTransition(
										"AirM2AnimationEndFailsafe",
										Vector3.new(
											root.AssemblyLinearVelocity.X,
											-AIR_M2_ATTACKER_FALL_RELEASE_SPEED,
											root.AssemblyLinearVelocity.Z
										)
									)

									beginAirM2AttackerLandingGuard(
										airComboId
									)
								end
							end
						)
					else
						stopTransition(
							reason,
							typeof(releaseVelocity) == "Vector3"
							and releaseVelocity
							or nil
						)
					end
				end
			end
		end
	)


character:GetAttributeChangedSignal(
	"LastSubstitutionAt"
):Connect(
	function()

		if transitionState
			and transitionState.role == "Victim" then

			stopTransition(
				"Substitution",
				nil
			)
		end
	end
)


-- ============================================================
-- REAL CANCELLATIONS
-- ============================================================

local function cancelIfNecessary()

	-- Once server-confirmed air transition owns the player, its own lifecycle
	-- controls release. Do not cancel it merely because server applies the
	-- temporary IsStunned air lock.
	if transitionState then
		return
	end


	if not active then
		return
	end


	if humanoid.Health <= 0
		or character:GetAttribute(
			"CombatMode"
		) ~= true
			or character:GetAttribute(
				"CombatSuppressed"
			) == true
			or character:GetAttribute(
				"IsStunned"
			) == true
			or isStatusCombatBlocked()
			or downedLocked() then

		finishLauncher(
			true
		)


		launcherEvent:
			FireServer(
				"Cancel",
				sequence
			)
	end
end


for _,
	attributeName in ipairs({
		"CombatMode",
		"CombatSuppressed",
		"IsStunned",
		"Status_AttackBlocked",
		"Status_Stunned",
		"DownedActionLocked",
		"IsDowned",
		"IsCarried",
		"IsExecuting",
		"IsCarrying",
	}) do

	character:
		GetAttributeChangedSignal(
			attributeName
		):
		Connect(
			cancelIfNecessary
		)
end


humanoid.Died:
	Connect(
		function()

			if active then

				launcherEvent:
				FireServer(
					"Cancel",
					sequence
				)
			end


			finishLauncher(
				true
			)

			stopTransition(
				"Death",
				nil
			)
		end
	)


script.Destroying:
	Connect(
		function()

			if endpoint.Parent then
				endpoint:
				Destroy()
			end


			stopLauncherTrack()

			stopTransition(
				"ScriptDestroy",
				nil
			)


			animation:
			Destroy()

			if airM2Animation then
				airM2Animation:
				Destroy()
			end
		end
	)


print(
	"[LauncherClient] READY v4.1 DB OriginalUplift + NoLegacyBackflipJump"
		.. " | LegacyBackflipJump=OFF"
		.. " | CommitFallback=0.20s"
		.. " | Cooldown=4.00s"
		.. " | Input=Ctrl+Mouse1"
		.. " | Animation=135785314988292"
		.. " | PlaybackSpeed=" .. tostring(ANIMATION_PLAYBACK_SPEED)
		.. " | RequiredMarkers=LauncherStart/Commit/Hit/WhiffEnd/FlickerReady/BodyFlicker"
		.. " | OptionalMarkers=RecoveryStart/LauncherEnd"
		.. " | CommitImpulse=5.5"
		.. " | Cooldown=4.00"
		.. " | StableConstraintAirHold=ON"
		.. " | AirM1=ON_LAUNCHER_ONLY"
		.. " | DefaultFallPoseSuppressed=ON"
		.. " | AirM2=IMPACT_RELEASE_MARKER_DRIVEN | AttackerFallsOnAnimationEnd=ON | M2Hitstop=0.10 | M2Anim=113654141031298 | AirFollow=MARKER_DRIVEN_BODY_FLICKER+FLICKER_READY_0.20_FREEZE | AirM1Gate=ARRIVAL_ONLY | BodyFlickerFX=BLINK+VANISH+APPEAR | DepartSFX=127579210330639 | AppearSFX=PENDING | HoldTimer=START_ON_ARRIVAL | M2Fall=FREEFALL_SUSTAIN"
)
