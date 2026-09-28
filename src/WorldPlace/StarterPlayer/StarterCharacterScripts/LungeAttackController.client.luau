--!strict
-- LungeAttackController v5.6 - Status Combat Gate + Explicit Water Walk Server Handshake
-- ElDiabloLocoStudios / Roblox
--
-- INSTALL:
-- StarterPlayer > StarterCharacterScripts > LungeAttackController [LocalScript]
--
-- PURPOSE
-- =======
-- Marker-driven Running Attack:
--
-- Mouse1 while eligible Sprint
-- -> play animation 122884818050264 FULL LENGTH
-- -> Launch: starts the physical forward dash
-- -> DamageStart: opens moving server-authoritative damage volume
-- -> DamageEnd: closes damage volume and releases powered dash
-- -> ClashStart / ClashEnd: expose clash eligibility
-- -> animation Stopped: cleanup
--
-- NO:
-- - landing detection
-- - FloorMaterial landing logic
-- - ground ray landing logic
-- - horizontal velocity loop
-- - steering loop
-- - M1MovementSpeedCap
-- - IsAttacking ownership
-- - Humanoid Move/Running restoration
-- - client-owned hit detection
-- - normalized marker fallbacks
--
-- The controller only owns the authored Lunge impulse/forward mover.
-- Outside that attack window, normal Sprint / Humanoid / gravity remain in
-- control.

local UserInputService =
	game:GetService("UserInputService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")


local GroundingService =
	require(
		ReplicatedStorage:
		WaitForChild(
			"GroundingService"
		)
	)


local character =
	script.Parent :: Model

local humanoid =
	character:
	WaitForChild(
		"Humanoid"
	) :: Humanoid

local animator =
	humanoid:
	WaitForChild(
		"Animator"
	) :: Animator

local rootPart =
	character:
	WaitForChild(
		"HumanoidRootPart"
	) :: BasePart


local combatRemotes =
	ReplicatedStorage:
	WaitForChild(
		"CombatRemotes"
	)

local lungeRequest =
	combatRemotes:
	WaitForChild(
		"LungeRequest"
	) :: RemoteEvent


-- =========================
-- CONFIG
-- =========================

local LUNGE_ANIMATION_ID =
	"rbxassetid://122884818050264"

local LUNGE_ANIMATION_SPEED =
	1.0

local LUNGE_FADE_IN =
	0.03

local LUNGE_FADE_OUT =
	0.05

-- PvP cooldown:
-- Starts when the Lunge is accepted.
local LUNGE_LOCAL_COOLDOWN =
	3.00

local LUNGE_MIN_HORIZONTAL_SPEED =
	24

local LUNGE_MIN_FORWARD_DOT =
	0.22

-- LOW side-flip arc.
-- Height from v3.1 was visually approved.
local LUNGE_LAUNCH_Y =
	24

-- PHYSICS DRIVE
--
-- v3.x repeatedly overwrote HumanoidRootPart.AssemblyLinearVelocity every
-- PreSimulation. On R6 this can trigger the Humanoid's physics-trip behavior
-- during fast acrobatic motion.
--
-- v4.0 uses a LinearVelocity constraint ONLY on the horizontal X/Z plane.
-- Gravity / Jump / Landing retain complete ownership of Y.
--
-- Powered dash lifetime is marker-driven in v5.0:
-- Launch starts it. DamageEnd OR the PvP movement cap releases propulsion.
-- The offensive DamageStart/DamageEnd window remains marker-driven independently.
-- PvP tuning:
-- Approved ground Dash = 75 studs/s.
-- Lunge must remain slower so a correctly timed Dash can disengage.
local LUNGE_DRIVE_START_SPEED =
	58

local LUNGE_DRIVE_END_SPEED =
	36

-- Independent caps for the special propulsion.
-- The offensive DamageStart/DamageEnd window remains marker-driven.
local LUNGE_MAX_POWERED_TIME =
	0.24

local LUNGE_MAX_POWERED_DISTANCE =
	12

-- Finite force prevents the mover from behaving like an infinite-force shove
-- if the character meets geometry.
local LUNGE_DRIVE_FORCE_PER_MASS =
	5500

local LUNGE_DRIVE_ATTACHMENT_NAME =
	"LungeDriveAttachment_v4"

local LUNGE_DRIVE_CONSTRAINT_NAME =
	"LungeLinearVelocity_v4"

local LUNGE_BINDABLE_NAME =
	"LungeTryStart"

local DEBUG_LUNGE =
	false


-- =========================
-- ANIMATION
-- =========================

local animation =
	Instance.new(
		"Animation"
	)

animation.Name =
	"LungeAttack"

animation.AnimationId =
	LUNGE_ANIMATION_ID


local track =
	animator:
	LoadAnimation(
		animation
	)

track.Priority =
	Enum.AnimationPriority.Action

track.Looped =
	false


-- =========================
-- STATE
-- =========================

local active =
	false

local sequence =
	0

local lockedUntil =
	-math.huge

local launchUsed =
	false

local damageStartUsed =
	false

local damageEndUsed =
	false

local clashStartUsed =
	false

local clashEndUsed =
	false

local finishing =
	false

local driveGeneration =
	0

local activeDriveAttachment: Attachment? =
	nil

local activeLinearVelocity: LinearVelocity? =
	nil


character:SetAttribute(
	"IsLungeAttacking",
	false
)

character:SetAttribute(
	"LungePhase",
	"None"
)

character:SetAttribute(
	"LungeClashActive",
	false
)

character:SetAttribute(
	"LungeDamageActive",
	false
)

character:SetAttribute(
	"LungeCanStartNow",
	false
)

character:SetAttribute(
	"LungeBlockedReason",
	"Initializing"
)

character:SetAttribute(
	"LungeCooldownEndsAt",
	nil
)

-- Generic cooldown HUD contract consumed by CooldownPopupController v3.
-- Keep LungeCooldownEndsAt above for internal gameplay compatibility.
character:SetAttribute(
	"CoreCooldown_Lunge_Label",
	"Lunge"
)

character:SetAttribute(
	"CoreCooldown_Lunge_StartsAt",
	nil
)

character:SetAttribute(
	"CoreCooldown_Lunge_EndsAt",
	nil
)


-- =========================
-- HELPERS
-- =========================

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


local function horizontalSpeed(): number

	local velocity =
		rootPart.AssemblyLinearVelocity

	return Vector3.new(
		velocity.X,
		0,
		velocity.Z
	).Magnitude
end


local function forwardMovementDot(): number

	local move =
		humanoid.MoveDirection

	local look =
		rootPart.CFrame.LookVector

	local flatMove =
		Vector3.new(
			move.X,
			0,
			move.Z
		)

	local flatLook =
		Vector3.new(
			look.X,
			0,
			look.Z
		)

	if flatMove.Magnitude <= 0.05
		or flatLook.Magnitude <= 0.05 then

		return -1
	end

	return flatMove.Unit:
		Dot(
			flatLook.Unit
		)
end


local function isWaterWalkGrounded(): boolean

	return character:GetAttribute(
		"WaterWalking"
	) == true
		and humanoid:GetState()
		~= Enum.HumanoidStateType.Swimming
end


local function isSharedGrounded(): boolean

	-- Chakra-feet water walking is virtual ground for Lunge. It intentionally
	-- does not make wall/ceiling SurfaceWalking eligible.
	if isWaterWalkGrounded() then
		return true
	end

	return GroundingService.IsSolidGrounded(
		character,
		humanoid,
		rootPart
	)
end


local function isStatusCombatBlocked(): boolean
	return character:GetAttribute(
		"Status_AttackBlocked"
	) == true

		or character:GetAttribute(
			"Status_Stunned"
		) == true
end


local function getEligibility(): (boolean, string)

	if active then
		return false, "AlreadyActive"
	end

	if UserInputService:
		GetFocusedTextBox() then

		return false, "TextBoxFocused"
	end

	if humanoid.Health <= 0 then
		return false, "Dead"
	end

	if humanoid.PlatformStand then
		return false, "PlatformStand"
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
		"TreeJumpActive"
		) == true
			or character:GetAttribute(
				"IsTreeJumping"
			) == true then

		return false, "TreeJump"
	end

	local waterWalkGrounded =
		isWaterWalkGrounded()

	-- SurfaceWalking normally means wall/ceiling traversal and must block
	-- Lunge. Water Walk also publishes SurfaceWalking in the current surface
	-- system, so it is the one explicit exception.
	if character:GetAttribute(
		"SurfaceWalking"
		) == true
			and not waterWalkGrounded then

		return false, "SurfaceWalking"
	end

	if humanoid:GetState()
		== Enum.HumanoidStateType.Swimming then

		return false, "Swimming"
	end

	if isDownedLocked() then
		return false, "DownedSystemLock"
	end

	-- A normal M1 already in progress still owns combat.
	if character:GetAttribute(
		"IsAttacking"
		) == true then

		return false, "M1Attacking"
	end

	if character:GetAttribute(
		"M1ComboCooldownActive"
		) == true then

		return false, "M1FullComboCooldown"
	end

	local comboIndex =
		character:GetAttribute(
			"M1ComboIndex"
		)

	if comboIndex ~= 1 then

		return false,
			"M1ComboIndex="
			.. tostring(
				comboIndex
			)
	end

	if time() <
		lockedUntil then

		return false,
			"LungeCooldown="
			.. string.format(
				"%.2f",
				lockedUntil
				- time()
			)
	end

	if character:GetAttribute(
		"IsSprinting"
		) ~= true then

		return false, "NotSprinting"
	end

	if not isSharedGrounded() then

		return false, "NotSharedGrounded"
	end

	local speed =
		horizontalSpeed()

	if speed <
		LUNGE_MIN_HORIZONTAL_SPEED then

		return false,
			"Speed="
			.. string.format(
				"%.1f",
				speed
			)
	end

	local forwardDot =
		forwardMovementDot()

	if forwardDot <
		LUNGE_MIN_FORWARD_DOT then

		return false,
			"ForwardDot="
			.. string.format(
				"%.2f",
				forwardDot
			)
	end

	return true, "Ready"
end




-- =========================
-- CLEANUP
-- =========================

local function destroyActiveDrive()

	if activeLinearVelocity then

		activeLinearVelocity:
			Destroy()

		activeLinearVelocity =
			nil
	end


	if activeDriveAttachment then

		activeDriveAttachment:
			Destroy()

		activeDriveAttachment =
			nil
	end
end


local function clearLocalState()

	active =
		false

	driveGeneration +=
		1

	destroyActiveDrive()

	launchUsed =
		false

	damageStartUsed =
		false

	damageEndUsed =
		false

	clashStartUsed =
		false

	clashEndUsed =
		false

	character:SetAttribute(
		"IsLungeAttacking",
		false
	)

	character:SetAttribute(
		"LungePhase",
		"None"
	)

	character:SetAttribute(
		"LungeClashActive",
		false
	)

	character:SetAttribute(
		"LungeDamageActive",
		false
	)

	if character:GetAttribute(
		"ActiveAttackType"
		) == "Lunge" then

		character:SetAttribute(
			"ActiveAttackType",
			"None"
		)
	end
end


local function finish(
	cancelled: boolean
)

	if not active
		or finishing then

		return
	end

	finishing =
		true

	local currentSequence =
		sequence

	if cancelled
		and track.IsPlaying then

		track:
			Stop(
				LUNGE_FADE_OUT
			)
	end

	lungeRequest:
		FireServer(
			cancelled
			and "Cancel"
			or "End",
			currentSequence
		)

	clearLocalState()


	finishing =
		false

	if DEBUG_LUNGE then

		print(
			"[LungeSimple] Finish",
			currentSequence,
			cancelled
				and "CANCEL"
				or "END"
		)
	end
end


-- =========================
-- DASH-STYLE FORWARD DRIVE
-- =========================

local function startForwardDrive(
	direction: Vector3,
	launchTrackTime: number
)

	driveGeneration +=
		1

	local generation =
		driveGeneration


	destroyActiveDrive()


	local attachment =
		Instance.new(
			"Attachment"
		)

	attachment.Name =
		LUNGE_DRIVE_ATTACHMENT_NAME

	attachment.Parent =
		rootPart


	local linearVelocity =
		Instance.new(
			"LinearVelocity"
		)

	linearVelocity.Name =
		LUNGE_DRIVE_CONSTRAINT_NAME

	linearVelocity.Attachment0 =
		attachment

	linearVelocity.RelativeTo =
		Enum.ActuatorRelativeTo.World

	linearVelocity.VelocityConstraintMode =
		Enum.VelocityConstraintMode.Plane

	linearVelocity.PrimaryTangentAxis =
		Vector3.new(
			1,
			0,
			0
		)

	linearVelocity.SecondaryTangentAxis =
		Vector3.new(
			0,
			0,
			1
		)

	linearVelocity.ForceLimitsEnabled =
		true

	linearVelocity.ForceLimitMode =
		Enum.ForceLimitMode.Magnitude

	linearVelocity.MaxForce =
		math.max(
			12000,
			rootPart.AssemblyMass
			* LUNGE_DRIVE_FORCE_PER_MASS
		)

	linearVelocity.PlaneVelocity =
		Vector2.new(
			direction.X
			* LUNGE_DRIVE_START_SPEED,
			direction.Z
			* LUNGE_DRIVE_START_SPEED
		)

	linearVelocity.Parent =
		rootPart


	local poweredStartedAt =
		os.clock()

	local poweredStartPosition =
		rootPart.Position


	activeDriveAttachment =
		attachment

	activeLinearVelocity =
		linearVelocity


	task.spawn(
		function()

			while active
				and generation ==
				driveGeneration
				and track.IsPlaying
				and activeLinearVelocity ==
				linearVelocity do


				local trackLength =
					track.Length

				if trackLength <=
					0.05 then

					RunService.PreSimulation:
						Wait()

					continue
				end


				if damageEndUsed then
					break
				end


				local poweredElapsed =
					os.clock()
				- poweredStartedAt

				local deltaFromStart =
					rootPart.Position
				- poweredStartPosition

				local poweredHorizontalDistance =
					Vector3.new(
						deltaFromStart.X,
						0,
						deltaFromStart.Z
					).Magnitude


				if poweredElapsed >=
					LUNGE_MAX_POWERED_TIME
					or poweredHorizontalDistance >=
					LUNGE_MAX_POWERED_DISTANCE then

					if DEBUG_LUNGE then
						print(
							"[LungeSimple] Drive PvP cap",
							"time",
							string.format(
								"%.3f",
								poweredElapsed
							),
							"distance",
							string.format(
								"%.1f",
								poweredHorizontalDistance
							)
						)
					end

					break
				end


				local denominator =
					math.max(
						0.01,
						trackLength
						- launchTrackTime
					)

				local alpha =
					math.clamp(
						(
							track.TimePosition
							- launchTrackTime
						)
						/ denominator,
						0,
						1
					)

				local eased =
					alpha
					* alpha
					* (
						3
						- 2
						* alpha
					)

				local speed =
					LUNGE_DRIVE_START_SPEED
					+ (
						LUNGE_DRIVE_END_SPEED
						- LUNGE_DRIVE_START_SPEED
					)
					* eased


				linearVelocity.PlaneVelocity =
					Vector2.new(
						direction.X
						* speed,
						direction.Z
						* speed
					)


				RunService.PreSimulation:
					Wait()
			end


			if activeLinearVelocity ==
				linearVelocity then

				linearVelocity:
					Destroy()

				activeLinearVelocity =
					nil
			end


			if activeDriveAttachment ==
				attachment then

				attachment:
					Destroy()

				activeDriveAttachment =
					nil
			end


			if DEBUG_LUNGE
				and generation ==
				driveGeneration then

				local velocity =
					rootPart.AssemblyLinearVelocity

				print(
					"[LungeSimple] LinearVelocity released",
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					),
					"reason",
					damageEndUsed
						and "DamageEnd"
						or "TrackEnd/Cleanup",
					"xz",
					string.format(
						"%.1f",
						Vector3.new(
							velocity.X,
							0,
							velocity.Z
						).Magnitude
					)
				)
			end
		end
	)
end

-- =========================
-- START
-- =========================

local function startLunge()

	local eligible,
		reason =
		getEligibility()

	if not eligible then

		character:SetAttribute(
			"LungeBlockedReason",
			reason
		)

		return false
	end


	active =
		true

	sequence +=
		1

	launchUsed =
		false

	damageStartUsed =
		false

	damageEndUsed =
		false

	clashStartUsed =
		false

	clashEndUsed =
		false

	lockedUntil =
		time()
		+ LUNGE_LOCAL_COOLDOWN


	character:SetAttribute(
		"IsLungeAttacking",
		true
	)

	character:SetAttribute(
		"ActiveAttackType",
		"Lunge"
	)

	character:SetAttribute(
		"LungePhase",
		"Playing"
	)

	character:SetAttribute(
		"LungeClashActive",
		false
	)

	character:SetAttribute(
		"LungeDamageActive",
		false
	)

	character:SetAttribute(
		"LungeBlockedReason",
		"Active"
	)

	local cooldownStartedAt =
		workspace:
		GetServerTimeNow()

	local cooldownEndsAt =
		cooldownStartedAt
		+ LUNGE_LOCAL_COOLDOWN


	-- Internal gameplay cooldown contract.
	character:SetAttribute(
		"LungeCooldownEndsAt",
		cooldownEndsAt
	)

	-- Generic right-side cooldown HUD contract.
	character:SetAttribute(
		"CoreCooldown_Lunge_Label",
		"Lunge"
	)

	character:SetAttribute(
		"CoreCooldown_Lunge_StartsAt",
		cooldownStartedAt
	)

	character:SetAttribute(
		"CoreCooldown_Lunge_EndsAt",
		cooldownEndsAt
	)


	if track.IsPlaying then

		track:
			Stop(
				0
			)
	end


	local animationStartedAt =
		workspace:
		GetServerTimeNow()


	track:
		Play(
			LUNGE_FADE_IN
		)

	track:
		AdjustSpeed(
			LUNGE_ANIMATION_SPEED
		)


	local startedOnWaterWalk =
		isWaterWalkGrounded()

	lungeRequest:
		FireServer(
			"Start",
			sequence,
			animationStartedAt,
			startedOnWaterWalk
		)


	if DEBUG_LUNGE then

		print(
			"[LungeSimple] Start",
			sequence,
			"trackLength",
			string.format(
				"%.3f",
				track.Length
			),
			"speed",
			string.format(
				"%.1f",
				horizontalSpeed()
			),
			"waterWalk",
			startedOnWaterWalk
		)
	end


	-- Safety only. The normal completion path remains AnimationTrack.Stopped.
	local thisSequence =
		sequence

	local watchdogDelay =
		math.max(
			1.50,
			(
				track.Length > 0.05
				and track.Length
				/ math.max(
					0.05,
					LUNGE_ANIMATION_SPEED
				)
				or 1.0
			)
			+ 0.65
		)

	task.delay(
		watchdogDelay,
		function()

			if active
				and sequence ==
				thisSequence then

				warn(
					"[LungeSimple] watchdog cleanup"
				)

				finish(
					true
				)
			end
		end
	)


	return true
end


-- =========================
-- MARKERS
-- =========================

track:
	GetMarkerReachedSignal(
		"Launch"
	):
	Connect(
		function()

			if not active
				or launchUsed then

				return
			end

			launchUsed =
			true

			character:SetAttribute(
				"LungePhase",
				"Airborne"
			)


			local velocity =
			rootPart.AssemblyLinearVelocity

			local look =
			rootPart.CFrame.LookVector

			local direction =
			Vector3.new(
				look.X,
				0,
				look.Z
			)

			if direction.Magnitude <=
				0.05 then

				local horizontal =
				Vector3.new(
					velocity.X,
					0,
					velocity.Z
				)

				direction =
				if horizontal.Magnitude >
				0.05
				then horizontal.Unit
				else Vector3.new(
					0,
					0,
					-1
				)

			else

				direction =
				direction.Unit
			end


			local launchTrackTime =
			track.TimePosition

			-- ONE initial vertical impulse only.
			-- Existing X/Z is preserved; horizontal dash ownership is handled by
			-- the planar LinearVelocity constraint below.
			rootPart.AssemblyLinearVelocity =
			Vector3.new(
				velocity.X,
				math.max(
					velocity.Y,
					LUNGE_LAUNCH_Y
				),
				velocity.Z
			)


			startForwardDrive(
				direction,
				launchTrackTime
			)


			if DEBUG_LUNGE then

				print(
					"[LungeSimple] Launch",
					sequence,
					"Y",
					LUNGE_LAUNCH_Y,
					"LinearVelocity",
					LUNGE_DRIVE_START_SPEED,
					"->",
					LUNGE_DRIVE_END_SPEED,
					"release",
					"DamageEnd"
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"DamageStart"
	):
	Connect(
		function()

			if not active
				or damageStartUsed then

				return
			end

			damageStartUsed =
			true

			character:SetAttribute(
				"LungeDamageActive",
				true
			)

			character:SetAttribute(
				"LungePhase",
				"DamageActive"
			)

			local markerAt =
			workspace:
			GetServerTimeNow()

			lungeRequest:
			FireServer(
				"DamageStart",
				sequence,
				markerAt
			)

			if DEBUG_LUNGE then

				print(
					"[LungeSimple] DamageStart",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					)
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"DamageEnd"
	):
	Connect(
		function()

			if not active
				or damageEndUsed then

				return
			end

			damageEndUsed =
			true

			character:SetAttribute(
				"LungeDamageActive",
				false
			)

			character:SetAttribute(
				"LungePhase",
				"Recovery"
			)

			local markerAt =
			workspace:
			GetServerTimeNow()

			lungeRequest:
			FireServer(
				"DamageEnd",
				sequence,
				markerAt
			)

			-- DamageEnd is also the authored end of the powered forward-kick
			-- travel. The movement loop sees damageEndUsed and releases the
			-- LinearVelocity on the next PreSimulation turn.
			if DEBUG_LUNGE then

				print(
					"[LungeSimple] DamageEnd",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					)
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"ClashStart"
	):
	Connect(
		function()

			if not active
				or clashStartUsed then

				return
			end

			clashStartUsed =
			true

			character:SetAttribute(
				"LungeClashActive",
				true
			)

			lungeRequest:
			FireServer(
				"ClashStart",
				sequence,
				workspace:
				GetServerTimeNow()
			)

			if DEBUG_LUNGE then

				print(
					"[LungeSimple] ClashStart",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					)
				)
			end
		end
	)


track:
	GetMarkerReachedSignal(
		"ClashEnd"
	):
	Connect(
		function()

			if not active
				or clashEndUsed then

				return
			end

			clashEndUsed =
			true

			character:SetAttribute(
				"LungeClashActive",
				false
			)

			lungeRequest:
			FireServer(
				"ClashEnd",
				sequence,
				workspace:
				GetServerTimeNow()
			)

			if DEBUG_LUNGE then

				print(
					"[LungeSimple] ClashEnd",
					sequence,
					"trackTime",
					string.format(
						"%.3f",
						track.TimePosition
					)
				)
			end
		end
	)




track.Stopped:
	Connect(
		function()

			if active
				and not finishing then

				finish(
					false
				)
			end
		end
	)


-- =========================
-- ATTACKCONTROLLER HANDOFF
-- =========================

local existing =
	character:
	FindFirstChild(
		LUNGE_BINDABLE_NAME
	)

if existing then
	existing:Destroy()
end


local endpoint =
	Instance.new(
		"BindableFunction"
	)

endpoint.Name =
	LUNGE_BINDABLE_NAME

endpoint.Parent =
	character


endpoint.OnInvoke =
	function(): boolean

		-- While the full Lunge animation is playing, consume additional Mouse1
		-- without starting M1 and WITHOUT adding any movement lock.
		if active then
			return true
		end

		local eligible,
		reason =
		getEligibility()

		character:SetAttribute(
			"LungeCanStartNow",
			eligible
		)

		character:SetAttribute(
			"LungeBlockedReason",
			reason
		)

		if not eligible then

			if DEBUG_LUNGE then

				print(
					"[LungeSimple] blocked:",
					reason
				)
			end

			return false
		end

		return startLunge()
	end


-- =========================
-- REAL CANCELLATIONS ONLY
-- =========================

local function cancelIfNecessary()

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
			or isDownedLocked() then

		finish(
			true
		)
	end
end


for _,
	name in ipairs({
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
			name
		):
		Connect(
			cancelIfNecessary
		)
end


humanoid.Died:
	Connect(
		function()

			finish(
				true
			)
		end
	)


script.Destroying:
	Connect(
		function()

			if endpoint.Parent then
				endpoint:Destroy()
			end

			if active then
				finish(
					true
				)
			end

			if track.IsPlaying then
				track:Stop(0)
			end

			animation:Destroy()
		end
	)


print(
	"[LungeSimple] READY v5.6 StatusCombatGate WaterWalkServerHandshake Damage7Cooldown3s CooldownHUD BalancedVsDash MarkerWindowLunge"
		.. " | Animation=122884818050264"
		.. " | Markers=Launch/DamageStart/DamageEnd/ClashStart/ClashEnd"
		.. " | MovingDamageWindow=SERVER"
		.. " | SingleHitPerTarget=SERVER"
		.. " | ClashFoundation=ON"
		.. " | LaunchY="
		.. tostring(
			LUNGE_LAUNCH_Y
		)
		.. " | HorizontalMover=LinearVelocityPlane"
		.. " | Drive="
		.. tostring(
			LUNGE_DRIVE_START_SPEED
		)
		.. "->"
		.. tostring(
			LUNGE_DRIVE_END_SPEED
		)
		.. " | DriveRelease=DamageEnd/PvPCap"
		.. " | MaxPoweredTime="
		.. tostring(
			LUNGE_MAX_POWERED_TIME
		)
		.. " | MaxPoweredDistance="
		.. tostring(
			LUNGE_MAX_POWERED_DISTANCE
		)
		.. " | Cooldown="
		.. tostring(
			LUNGE_LOCAL_COOLDOWN
		)
		.. "s"
		.. " | GenericCooldownHUD=ON | WaterWalkGround=ON | WallCeilingSurface=BLOCKED"
)
