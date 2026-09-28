--!strict
-- AerialKickController v1.6 - Pure Vertical Drop + CoreCooldown Contract
-- StarterPlayer > StarterCharacterScripts > AerialKickController
--
-- Animation: 78929223932185
--
-- Required authored markers:
-- AerialStart
-- Commit
-- DamageStart
-- Hit
-- DamageEnd
-- RecoveryStart
-- AerialEnd
--
-- Input is NOT owned here.
-- AttackController remains the single Mouse1 owner and invokes
-- character.AerialKickTryStart when appropriate.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Debris =
	game:GetService("Debris")

local TweenService =
	game:GetService("TweenService")

local RunService =
	game:GetService("RunService")

local player =
	Players.LocalPlayer

local character =
	script.Parent

local humanoid =
	character:
	WaitForChild("Humanoid") :: Humanoid

local animator =
	humanoid:
	WaitForChild("Animator") :: Animator

local root =
	character:
	WaitForChild("HumanoidRootPart") :: BasePart

local combatRemotes =
	ReplicatedStorage:
	WaitForChild("CombatRemotes")

local aerialKickEvent =
	combatRemotes:
	WaitForChild("AerialKickEvent") :: RemoteEvent


-- =========================
-- TUNING
-- =========================

local ANIMATION_ID =
	"rbxassetid://73275060027676"

local ANIMATION_SPEED =
	1.0

local ANIMATION_FADE_IN =
	0.04

local ANIMATION_FADE_OUT =
	0.06

local LOCAL_COOLDOWN =
	2.75

local END_FAILSAFE_PADDING =
	0.22


-- =========================
-- ATTACKER AIR PRESENTATION
-- =========================
--
-- Axe Kick animation length: 38 authored frames (~0.633s at 60 FPS).
--
-- Before DamageStart the flip remains nearly suspended so startup reads cleanly.
local AERIAL_PRE_DAMAGE_HOVER_SPEED =
	0.35

-- At DamageStart we STOP controlling vertical velocity and return the character
-- to Roblox gravity. We only ensure the kick is already moving downward so it
-- cannot continue rising from jump momentum.
local AERIAL_DIVE_MIN_START_SPEED =
	-10.0

-- No artificial fall speed or acceleration after DamageStart.
-- Workspace gravity owns the fall from that point onward.

-- Floor protection exists only near the actual floor. This is deliberately
-- small so 95%+ of the descent feels like completely normal falling physics.
local AERIAL_LOCAL_FLOOR_HOLD_DISTANCE =
	3.85

local AERIAL_GROUND_PROBE_DISTANCE =
	8.0

local AERIAL_FLOOR_HOLD_SPEED =
	0.10

local AERIAL_VERTICAL_FORCE_MULTIPLIER =
	4.5

-- Server contact monitor ends first at 0.90s. Client waits slightly longer only
-- as a visual failsafe in case a response packet is lost/delayed.
local AERIAL_CONTACT_HOLD_FAILSAFE =
	1.15


local DEBUG =
	false


-- =========================
-- STATE
-- =========================

local active =
	false

local committed =
	false

local sequence =
	0

local cooldownEndsAt =
	-math.huge

local track: AnimationTrack? =
	nil

local hoverAttachment: Attachment? =
	nil

local verticalHold: LinearVelocity? =
	nil

local floorGuardConnection: RBXScriptConnection? =
	nil

local horizontalLockConnection: RBXScriptConnection? =
	nil

local hitFrozen =
	false

local localFloorHeld =
	false

local groundApproachReported =
	false


character:SetAttribute(
	"AerialKickActive",
	false
)

character:SetAttribute(
	"AerialKickCommitted",
	false
)


-- =========================
-- ANIMATION
-- =========================

local animation =
	Instance.new("Animation")

animation.Name =
	"AerialSpinKick"

animation.AnimationId =
	ANIMATION_ID


local function createTrack(): AnimationTrack
	local newTrack =
		animator:
		LoadAnimation(
			animation
		)

	newTrack.Priority =
		Enum.AnimationPriority.Action

	newTrack.Looped =
		false

	return newTrack
end


-- =========================
-- HELPERS
-- =========================

local function isLauncherOwnedAirContext(): boolean
	return character:GetAttribute(
		"LauncherAirComboAttacker"
	) == true
		or character:GetAttribute(
			"AirComboServerActive"
		) == true
		or character:GetAttribute(
			"AirComboActive"
		) == true
		or character:GetAttribute(
			"AirComboTransitionActive"
		) == true
end


local function isAirborne(): boolean
	local state =
		humanoid:GetState()

	return state ==
		Enum.HumanoidStateType.Jumping
		or state ==
		Enum.HumanoidStateType.Freefall
end


local function isDownedLocked(): boolean
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


local function isStatusBlocked(): boolean
	return character:GetAttribute(
		"IsStunned"
	) == true
		or character:GetAttribute(
			"Status_AttackBlocked"
		) == true
		or character:GetAttribute(
			"Status_Stunned"
		) == true
end


local function setCooldownAttributes(
	startsAt: number,
	endsAt: number
)
	character:SetAttribute(
		"CoreCooldown_AerialKick_Label",
		"Aerial Axe Kick"
	)

	character:SetAttribute(
		"CoreCooldown_AerialKick_StartsAt",
		startsAt
	)

	character:SetAttribute(
		"CoreCooldown_AerialKick_EndsAt",
		endsAt
	)
end


local function canStart(): (boolean, string)
	if active then
		return false, "Active"
	end

	if not isAirborne() then
		return false, "Grounded"
	end

	if isLauncherOwnedAirContext() then
		return false, "LauncherAir"
	end

	if character:GetAttribute(
		"CombatMode"
		) ~= true then

		return false, "CombatModeOff"
	end

	if humanoid.Health <= 0
		or humanoid.PlatformStand then

		return false, "DeadOrPlatform"
	end

	if character:GetAttribute(
		"CombatSuppressed"
		) == true
			or isStatusBlocked()
			or isDownedLocked() then

		return false, "Locked"
	end

	if character:GetAttribute(
		"IsBlocking"
		) == true
			or character:GetAttribute(
				"IsDashing"
			) == true
			or character:GetAttribute(
				"AirDashCarryActive"
			) == true
			or character:GetAttribute(
				"IsThrowingKunai"
			) == true
			or character:GetAttribute(
				"TreeJumpActive"
			) == true
			or character:GetAttribute(
				"IsTreeJumping"
			) == true
			or character:GetAttribute(
				"SurfaceWalking"
			) == true
			or character:GetAttribute(
				"SurfaceJumping"
			) == true then

		return false, "ActionConflict"
	end

	if character:GetAttribute(
		"IsAttacking"
		) == true then

		return false, "OtherAttack"
	end

	if workspace:GetServerTimeNow() <
		cooldownEndsAt then

		return false, "Cooldown"
	end

	return true, "OK"
end


local function destroyVerticalHold()
	if verticalHold then
		verticalHold:
			Destroy()

		verticalHold =
			nil
	end

	if hoverAttachment then
		hoverAttachment:
			Destroy()

		hoverAttachment =
			nil
	end
end


local function stopFloorGuard()
	if floorGuardConnection then
		floorGuardConnection:
			Disconnect()

		floorGuardConnection =
			nil
	end
end


local function stopHorizontalLock()
	if horizontalLockConnection then
		horizontalLockConnection:
			Disconnect()

		horizontalLockConnection =
			nil
	end
end


local function startHorizontalLock()
	stopHorizontalLock()

	-- Remove inherited sprint/jump/dash horizontal momentum immediately.
	local velocity =
		root.AssemblyLinearVelocity

	root.AssemblyLinearVelocity =
		Vector3.new(
			0,
			velocity.Y,
			0
		)

	-- Keep the attack perfectly vertical. Y is intentionally untouched so
	-- startup hover, natural gravity and near-floor hold remain independent.
	horizontalLockConnection =
		RunService.Heartbeat:
		Connect(
			function()
				if not active
					or not root.Parent then

					return
				end

				local currentVelocity =
				root.AssemblyLinearVelocity

				if math.abs(currentVelocity.X) > 0.001
					or math.abs(currentVelocity.Z) > 0.001 then

					root.AssemblyLinearVelocity =
					Vector3.new(
						0,
						currentVelocity.Y,
						0
					)
				end
			end
		)

	if DEBUG then
		print(
			"[AerialKickClient] HORIZONTAL LOCK XZ=0"
		)
	end
end


local function destroyAerialMotion()
	stopHorizontalLock()

	hitFrozen =
		false

	localFloorHeld =
		false

	groundApproachReported =
		false

	stopFloorGuard()
	destroyVerticalHold()
end


local function findHumanoidModelFromPart(
	part: Instance
): Model?
	local current: Instance? =
		part

	while current
		and current ~= workspace do

		if current:IsA("Model")
			and current:
			FindFirstChildOfClass(
				"Humanoid"
			) then

			return current
		end

		current =
			current.Parent
	end

	return nil
end


local function getNonCharacterGroundDistance(): number?
	local exclusions: {Instance} = {
		character,
	}

	for _ = 1, 8 do
		local params =
			RaycastParams.new()

		params.FilterType =
			Enum.RaycastFilterType.Exclude

		params.FilterDescendantsInstances =
			exclusions

		params.IgnoreWater =
			false

		local result =
			workspace:Raycast(
				root.Position,
				Vector3.new(
					0,
					-AERIAL_GROUND_PROBE_DISTANCE,
					0
				),
				params
			)

		if not result then
			return nil
		end

		local humanoidModel =
			findHumanoidModelFromPart(
				result.Instance
			)

		if humanoidModel then
			table.insert(
				exclusions,
				humanoidModel
			)
		else
			return result.Distance
		end
	end

	return nil
end


local function ensureFloorHold()
	if verticalHold
		and hoverAttachment then

		verticalHold.LineVelocity =
			AERIAL_FLOOR_HOLD_SPEED

		return
	end

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"AerialKickFloorHoldAttachment"

	attachment.Parent =
		root

	hoverAttachment =
		attachment

	local assemblyMass =
		math.max(
			root.AssemblyMass,
			1
		)

	local hold =
		Instance.new("LinearVelocity")

	hold.Name =
		"AerialAxeKickFloorHold"

	hold.Attachment0 =
		attachment

	hold.RelativeTo =
		Enum.ActuatorRelativeTo.World

	hold.VelocityConstraintMode =
		Enum.VelocityConstraintMode.Line

	hold.LineDirection =
		Vector3.yAxis

	hold.LineVelocity =
		AERIAL_FLOOR_HOLD_SPEED

	hold.MaxForce =
		assemblyMass
		* workspace.Gravity
		* AERIAL_VERTICAL_FORCE_MULTIPLIER

	hold.Parent =
		root

	verticalHold =
		hold
end


local function beginAerialHover()
	destroyAerialMotion()

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"AerialKickMotionAttachment"

	attachment.Parent =
		root

	hoverAttachment =
		attachment

	local assemblyMass =
		math.max(
			root.AssemblyMass,
			1
		)

	local hold =
		Instance.new("LinearVelocity")

	hold.Name =
		"AerialAxeKickStartupHover"

	hold.Attachment0 =
		attachment

	hold.RelativeTo =
		Enum.ActuatorRelativeTo.World

	hold.VelocityConstraintMode =
		Enum.VelocityConstraintMode.Line

	hold.LineDirection =
		Vector3.yAxis

	hold.LineVelocity =
		AERIAL_PRE_DAMAGE_HOVER_SPEED

	hold.MaxForce =
		assemblyMass
		* workspace.Gravity
		* AERIAL_VERTICAL_FORCE_MULTIPLIER

	hold.Parent =
		root

	verticalHold =
		hold

	if DEBUG then
		print(
			"[AerialKickClient] AXE STARTUP HOVER",
			AERIAL_PRE_DAMAGE_HOVER_SPEED
		)
	end
end


local function reportGroundApproach()
	if groundApproachReported
		or not active
		or not hitFrozen then

		return
	end

	groundApproachReported =
		true

	aerialKickEvent:
		FireServer(
			"GroundApproach",
			sequence,
			workspace:GetServerTimeNow()
		)

	if DEBUG then
		print(
			"[AerialKickClient] GROUND APPROACH REPORT",
			sequence
		)
	end
end


local function startNaturalDive()
	if not active then
		return
	end

	-- Startup hover ends here. From now on gravity is real.
	destroyVerticalHold()

	local velocity =
		root.AssemblyLinearVelocity

	root.AssemblyLinearVelocity =
		Vector3.new(
			0,
			math.min(
				velocity.Y,
				AERIAL_DIVE_MIN_START_SPEED
			),
			0
		)

	if DEBUG then
		print(
			"[AerialKickClient] NATURAL DIVE START",
			"Y",
			string.format(
				"%.2f",
				root.AssemblyLinearVelocity.Y
			),
			"gravity",
			workspace.Gravity
		)
	end

	stopFloorGuard()

	floorGuardConnection =
		RunService.Heartbeat:
		Connect(
			function()
				if not active
					or not root.Parent then

					return
				end

				local groundDistance =
				getNonCharacterGroundDistance()

				if groundDistance
					and groundDistance <=
					AERIAL_LOCAL_FLOOR_HOLD_DISTANCE then

					if not localFloorHeld then
						localFloorHeld =
						true

						ensureFloorHold()

						if DEBUG then
							print(
								"[AerialKickClient] NEAR-FLOOR HOLD",
								string.format(
									"%.2f",
									groundDistance
								)
							)
						end
					end

					if hitFrozen then
						reportGroundApproach()
					end
				end
			end
		)
end


local function freezeAtHitPose(
	currentTrack: AnimationTrack,
	currentSequence: number
)
	if not active
		or sequence ~= currentSequence
		or hitFrozen then

		return
	end

	hitFrozen =
		true

	currentTrack:
		AdjustSpeed(
			0
		)

	if DEBUG then
		print(
			"[AerialKickClient] HIT POSE FROZEN",
			currentSequence
		)
	end

	aerialKickEvent:
		FireServer(
			"Hit",
			currentSequence,
			workspace:GetServerTimeNow()
		)

	if localFloorHeld then
		task.defer(
			reportGroundApproach
		)
	end

	task.delay(
		AERIAL_CONTACT_HOLD_FAILSAFE,
		function()
			if not active
				or sequence ~= currentSequence
				or not hitFrozen then

				return
			end

			if DEBUG then
				warn(
					"[AerialKickClient] CONTACT HOLD LOCAL FAILSAFE",
					currentSequence
				)
			end

			hitFrozen =
				false

			if currentTrack.IsPlaying then
				currentTrack:
					AdjustSpeed(
						ANIMATION_SPEED
					)
			end
		end
	)
end


local function releaseHitFreeze(
	reason: string
)
	if not active
		or not hitFrozen then

		return
	end

	hitFrozen =
		false

	local currentTrack =
		track

	if currentTrack
		and currentTrack.IsPlaying then

		currentTrack:
			AdjustSpeed(
				ANIMATION_SPEED
			)
	end

	if DEBUG then
		print(
			"[AerialKickClient] HIT POSE RELEASE",
			sequence,
			reason
		)
	end
end


local function releaseMotionForRecovery()
	-- RecoveryStart is the first frame where actual floor contact is legal.
	stopFloorGuard()
	destroyVerticalHold()

	hitFrozen =
		false

	localFloorHeld =
		false

	groundApproachReported =
		false

	if DEBUG then
		print(
			"[AerialKickClient] RECOVERY NATURAL PHYSICS",
			sequence,
			"Y",
			string.format(
				"%.2f",
				root.AssemblyLinearVelocity.Y
			)
		)
	end
end


local function finish(
	reason: string,
	sendEnd: boolean
)
	if not active then
		return
	end

	local finishedSequence =
		sequence

	active =
		false

	committed =
		false

	destroyAerialMotion()

	character:SetAttribute(
		"AerialKickActive",
		false
	)

	character:SetAttribute(
		"AerialKickCommitted",
		false
	)

	-- Only clear IsAttacking if this controller still owns it.
	if character:GetAttribute(
		"AttackPhase"
		) == "AerialKick" then

		character:SetAttribute(
			"IsAttacking",
			false
		)

		character:SetAttribute(
			"AttackPhase",
			"None"
		)
	end

	local currentTrack =
		track

	track =
		nil

	if currentTrack
		and currentTrack.IsPlaying then

		currentTrack:
			Stop(
				ANIMATION_FADE_OUT
			)
	end

	if sendEnd then
		aerialKickEvent:
			FireServer(
				"End",
				finishedSequence,
				workspace:GetServerTimeNow()
			)
	end

	if DEBUG then
		print(
			"[AerialKickClient] END",
			finishedSequence,
			reason
		)
	end
end


local function start(): boolean
	local eligible,
		reason =
		canStart()

	-- Only a real Jumping/Freefall click may ever be consumed here.
	-- Grounded Mouse1 must return FALSE so AttackController can continue to
	-- normal M1. Launcher air remains owned by Launcher.
	local trulyAirborne =
		isAirborne()

	local shouldConsume =
		trulyAirborne
		and not isLauncherOwnedAirContext()

	if not eligible then
		if DEBUG
			and shouldConsume
			and reason ~= "Cooldown" then

			print(
				"[AerialKickClient] blocked",
				reason,
				"state",
				humanoid:GetState().Name,
				"floor",
				humanoid.FloorMaterial.Name
			)
		end

		return shouldConsume
	end

	sequence +=
		1

	local currentSequence =
		sequence

	active =
		true

	committed =
		false

	local serverNow =
		workspace:GetServerTimeNow()

	cooldownEndsAt =
		serverNow
		+ LOCAL_COOLDOWN

	setCooldownAttributes(
		serverNow,
		cooldownEndsAt
	)

	character:SetAttribute(
		"AerialKickActive",
		true
	)

	character:SetAttribute(
		"AerialKickCommitted",
		false
	)

	character:SetAttribute(
		"IsAttacking",
		true
	)

	character:SetAttribute(
		"AttackPhase",
		"AerialKick"
	)

	local currentTrack =
		createTrack()

	track =
		currentTrack

	-- Pure vertical Axe Kick: remove all inherited X/Z movement immediately.
	startHorizontalLock()

	-- Hold Y until DamageStart, then return Y to natural gravity.
	beginAerialHover()

	-- Marker connections belong to THIS fresh track only.
	currentTrack:
		GetMarkerReachedSignal(
			"AerialStart"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				if DEBUG then
					print(
						"[AerialKickClient] AerialStart",
						currentSequence
					)
				end
			end
		)

	currentTrack:
		GetMarkerReachedSignal(
			"Commit"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				committed =
				true

				character:SetAttribute(
					"AerialKickCommitted",
					true
				)

				-- Axe Kick has no forward impulse. Commit only locks the
				-- authored attack state; vertical movement begins at DamageStart.
				if DEBUG then
					print(
						"[AerialKickClient] Commit",
						currentSequence
					)
				end
			end
		)

	currentTrack:
		GetMarkerReachedSignal(
			"DamageStart"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				startNaturalDive()

				aerialKickEvent:
				FireServer(
					"DamageStart",
					currentSequence,
					workspace:GetServerTimeNow()
				)

				if DEBUG then
					print(
						"[AerialKickClient] DamageStart",
						currentSequence
					)
				end
			end
		)

	currentTrack:
		GetMarkerReachedSignal(
			"Hit"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				freezeAtHitPose(
					currentTrack,
					currentSequence
				)

				if DEBUG then
					print(
						"[AerialKickClient] Hit marker -> CONTACT HOLD",
						currentSequence
					)
				end
			end
		)

	currentTrack:
		GetMarkerReachedSignal(
			"DamageEnd"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				aerialKickEvent:
				FireServer(
					"DamageEnd",
					currentSequence,
					workspace:GetServerTimeNow()
				)

				if DEBUG then
					print(
						"[AerialKickClient] DamageEnd",
						currentSequence
					)
				end
			end
		)

	currentTrack:
		GetMarkerReachedSignal(
			"RecoveryStart"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				character:SetAttribute(
					"AerialKickCommitted",
					false
				)

				releaseMotionForRecovery()

				if DEBUG then
					print(
						"[AerialKickClient] RecoveryStart",
						currentSequence
					)
				end
			end
		)

	currentTrack:
		GetMarkerReachedSignal(
			"AerialEnd"
		):
		Connect(
			function()
				if not active
					or sequence ~= currentSequence then

					return
				end

				finish(
					"AerialEnd",
					true
				)
			end
		)

	currentTrack.Stopped:
		Connect(
			function()
				if active
					and sequence == currentSequence then

					finish(
						"TrackStopped",
						true
					)
				end
			end
		)

	currentTrack:
		Play(
			ANIMATION_FADE_IN,
			1,
			ANIMATION_SPEED
		)

	aerialKickEvent:
		FireServer(
			"Start",
			currentSequence,
			workspace:GetServerTimeNow()
		)

	local expectedLength =
		math.max(
			currentTrack.Length,
			0.60
		)

	task.delay(
		expectedLength
			/ ANIMATION_SPEED
			+ AERIAL_CONTACT_HOLD_FAILSAFE
			+ END_FAILSAFE_PADDING,
		function()

			if active
				and sequence ==
				currentSequence then

				finish(
					"EndFailsafe",
					true
				)
			end
		end
	)

	if DEBUG then
		print(
			"[AerialKickClient] START",
			currentSequence,
			"anim",
			78929223932185,
			"state",
			humanoid:GetState().Name,
			"floor",
			humanoid.FloorMaterial.Name,
			"velocityY",
			string.format(
				"%.2f",
				root.AssemblyLinearVelocity.Y
			)
		)
	end

	return true
end


-- =========================
-- INPUT HANDOFF ENDPOINT
-- =========================

local oldEndpoint =
	character:
	FindFirstChild(
		"AerialKickTryStart"
	)

if oldEndpoint then
	oldEndpoint:
		Destroy()
end

local endpoint =
	Instance.new(
		"BindableFunction"
	)

endpoint.Name =
	"AerialKickTryStart"

endpoint.OnInvoke =
	function()
		return start()
	end

endpoint.Parent =
	character


-- =========================
-- SMALL WALL IMPACT VFX
-- =========================

local function getWallBasis(
	normal: Vector3
): (Vector3, Vector3)

	local helper =
		Vector3.yAxis

	if math.abs(
		normal:
			Dot(
				helper
			)
		) > 0.92 then

		helper =
			Vector3.xAxis
	end

	local right =
		normal:
		Cross(
			helper
		)

	if right.Magnitude < 0.001 then
		right =
			Vector3.xAxis
	else
		right =
			right.Unit
	end

	local up =
		right:
		Cross(
			normal
		).Unit

	return right,
		up
end


local function spawnWallImpact(
	position: Vector3,
	normal: Vector3,
	surfaceColor: Color3,
	surfaceMaterial: Enum.Material
)
	if normal.Magnitude < 0.001 then
		return
	end

	normal =
		normal.Unit

	local right,
		up =
		getWallBasis(
			normal
		)

	local radius =
		3.0

	for index = 1, 9 do
		local angle =
			(index - 1)
			/ 9
			* math.pi
			* 2

		local radial =
			right
			* math.cos(angle)
			+ up
			* math.sin(angle)

		local shard =
			Instance.new("Part")

		shard.Name =
			"AerialKickWallScar"

		shard.Anchored =
			true

		shard.CanCollide =
			false

		shard.CanTouch =
			false

		shard.CanQuery =
			false

		shard.CastShadow =
			false

		shard.Material =
			surfaceMaterial

		shard.Color =
			surfaceColor

		shard.Size =
			Vector3.new(
				0.22,
				0.55,
				1.25
			)

		local shardPosition =
			position
			+ normal * 0.045
			+ radial * radius

		local tangent =
			(
				-right
				* math.sin(angle)
				+ up
				* math.cos(angle)
			).Unit

		shard.CFrame =
			CFrame.fromMatrix(
				shardPosition,
				tangent,
				normal:
				Cross(
					tangent
				).Unit,
				normal
			)

		shard.Transparency =
			0.12

		shard.Parent =
			workspace

		TweenService:
			Create(
				shard,
				TweenInfo.new(
					0.85,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					Transparency = 1,
				}
			):
			Play()

		Debris:
			AddItem(
				shard,
				0.95
			)
	end

	local anchor =
		Instance.new("Part")

	anchor.Name =
		"AerialKickWallDust"

	anchor.Anchored =
		true

	anchor.CanCollide =
		false

	anchor.CanTouch =
		false

	anchor.CanQuery =
		false

	anchor.Transparency =
		1

	anchor.Size =
		Vector3.one

	anchor.CFrame =
		CFrame.lookAt(
			position
			+ normal * 0.08,
			position
			+ normal
		)

	anchor.Parent =
		workspace

	local emitter =
		Instance.new("ParticleEmitter")

	emitter.Texture =
		"rbxasset://textures/particles/smoke_main.dds"

	emitter.Color =
		ColorSequence.new(
			surfaceColor
		)

	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.28
			),
			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	emitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.45
			),
			NumberSequenceKeypoint.new(
				1,
				1.65
			),
		})

	emitter.Lifetime =
		NumberRange.new(
			0.28,
			0.48
		)

	emitter.Speed =
		NumberRange.new(
			4,
			8
		)

	emitter.Drag =
		3

	emitter.SpreadAngle =
		Vector2.new(
			38,
			38
		)

	emitter.EmissionDirection =
		Enum.NormalId.Front

	emitter.Rate =
		0

	emitter.Parent =
		anchor

	emitter:
		Emit(
			12
		)

	Debris:
		AddItem(
			anchor,
			0.75
		)
end


aerialKickEvent.OnClientEvent:
	Connect(
		function(
			action: string,
			...: any
		)

			if action == "WallImpact" then
				local args = {...}

				local position =
				args[1]

				local normal =
				args[2]

				local surfaceColor =
				args[3]

				local surfaceMaterial =
				args[4]

				if typeof(position) == "Vector3"
					and typeof(normal) == "Vector3"
					and typeof(surfaceColor) == "Color3"
					and typeof(surfaceMaterial) == "EnumItem" then

					spawnWallImpact(
						position,
						normal,
						surfaceColor,
						surfaceMaterial
					)
				end

				return
			end

			if action == "HitConfirmed"
				or action == "Blocked"
				or action == "GuardBreak"
				or action == "Substituted"
				or action == "GroundRelease"
				or action == "ContactTimeout" then

				local args = {...}

				local resolvedSequence =
				args[1]

				if typeof(resolvedSequence) == "number"
					and active
					and sequence == resolvedSequence then

					releaseHitFreeze(
						action
					)
				end

				if DEBUG then
					print(
						"[AerialKickClient] CONTACT RESULT",
						action,
						resolvedSequence
					)
				end

				return
			end

			if action == "StartRejected" then
				local args = {...}

				local rejectedSequence =
				args[1]

				local reason =
				args[2]

				if typeof(rejectedSequence) == "number"
					and active
					and sequence == rejectedSequence then

					-- Server did not accept the attack; remove local ownership fast.
					-- Grounded input should normally never reach this anymore, but this
					-- keeps client/server state clean under replication edge cases.
					finish(
						"ServerRejected:"
						.. tostring(reason),
						false
					)
				end

				if DEBUG then
					print(
						"[AerialKickClient] SERVER REJECT",
						rejectedSequence,
						reason
					)
				end

				return
			end

			if DEBUG then
				print(
					"[AerialKickClient] SERVER",
					action,
					...
				)
			end
		end
	)


-- =========================
-- CANCEL / CLEANUP
-- =========================

for _, attributeName in ipairs({
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
			function()
				if active
					and character:GetAttribute(
						attributeName
					) == true then

					aerialKickEvent:
					FireServer(
						"Cancel",
						sequence,
						workspace:GetServerTimeNow()
					)

					finish(
						attributeName,
						false
					)
				end
			end
		)
end


humanoid.Died:
	Connect(
		function()
			if active then
				finish(
					"Died",
					false
				)
			end
		end
	)


script.Destroying:
	Connect(
		function()
			if active then
				finish(
					"Destroying",
					false
				)
			end

			if endpoint.Parent then
				endpoint:
				Destroy()
			end

			animation:
			Destroy()
		end
	)


print(
	"[AerialKickClient] READY v1.6"
		.. " | Animation=73275060027676"
		.. " | Markers=AerialStart/Commit/DamageStart/Hit/DamageEnd/RecoveryStart/AerialEnd"
		.. " | Input=Mouse1RealJumpingFreefallOnly"
		.. " | LauncherAirPriority=PRESERVED"
		.. " | LocalCooldown=2.75"
		.. " | NoRagdoll=ON | AxeKick=PURE_VERTICAL_GRAVITY_DIVE | HorizontalXZ=LOCKED_0 | DamageStart=GRAVITY+MIN_Y_-10 | HitFreezeMax=1.15_CLIENT/0.90_SERVER | CoreCooldown=AerialKick_2.75 | ForwardImpulse=OFF"
)
