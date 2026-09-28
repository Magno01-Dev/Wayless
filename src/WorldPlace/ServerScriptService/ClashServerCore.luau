--!strict
-- ClashServerCore v2.6 - WaterLungeMotionFallback
-- ElDiabloLocoStudios
--
-- INSTALL:
-- ServerScriptService > ClashServerCore [ModuleScript]
--
-- IMPORTANT:
-- This ModuleScript remains isolated from CombatServer; v2.6 only consumes
-- the server-published Lunge attributes from CombatServer v24.7.
--
-- It observes the stable Lunge contract already published by CombatServer:
--   ServerLungeActive
--   ServerLungeClashActive
--
-- When two eligible Lunges meet:
--   1) both characters are locked with the existing IsStunned contract,
--   2) their normal Lunge clients cancel themselves,
--   3) CombatServer v24.7 clears its own Lunge state normally,
--   4) this independent controller starts the Clash cinematic.
--
-- Animation:
-- 110715673180255

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")


print(
	"[ClashServerCore] BOOT v2.6 | ScriptRunning=YES"
)


-- =========================
-- REMOTE
-- =========================

local combatRemotes =
	ReplicatedStorage:
	FindFirstChild(
		"CombatRemotes"
	)

if not combatRemotes then

	combatRemotes =
		Instance.new(
			"Folder"
		)

	combatRemotes.Name =
		"CombatRemotes"

	combatRemotes.Parent =
		ReplicatedStorage
end


local clashEvent =
	combatRemotes:
	FindFirstChild(
		"ClashEvent"
	)

if not clashEvent then

	clashEvent =
		Instance.new(
			"RemoteEvent"
		)

	clashEvent.Name =
		"ClashEvent"

	clashEvent.Parent =
		combatRemotes
end

local remote =
	clashEvent :: RemoteEvent


remote:SetAttribute(
	"ClashServerVersion",
	"2.5"
)

-- Keep protocol 2.5 for the current ClashController handshake while exposing
-- the implementation revision separately.
remote:SetAttribute(
	"ClashServerCoreRevision",
	"2.6"
)


print(
	"[ClashServerCore] REMOTE READY v2.6 | "
		.. remote:GetFullName()
)


-- =========================
-- CONFIG
-- =========================

local CLASH_ANIMATION_ID =
	"rbxassetid://110715673180255"


-- Detection only happens while BOTH players are inside the authored
-- ServerLungeClashActive window.
local MAX_CLASH_ROOT_DISTANCE =
	16.0

local MIN_CLASH_ROOT_DISTANCE =
	1.25

local MAX_VERTICAL_DIFFERENCE =
	5.0

-- Lunge is a fast crossing attack. At ClashStart the two roots may
-- already have passed one another, so current LookVector is NOT a valid
-- test of whether they attacked head-on.
local MIN_LUNGE_MOTION_SPEED =
	8.0

-- Dot <= -0.10 means the two horizontal travel vectors are moving more
-- than ~95 degrees apart. Head-on Lunges are normally near -1.
local MAX_OPPOSING_MOTION_DOT =
	-0.10


-- PRE-IMPACT CLASH:
-- CombatServer can process the first player's DamageStart at the same moment
-- it publishes ClashStart. That 7-damage hit can cancel the opponent before
-- the opponent's ClashStart packet arrives.
--
-- Therefore a real Clash must be recognized slightly BEFORE DamageStart,
-- while BOTH server-accepted Lunges are active and their trajectories are
-- closing into each other.
local PREIMPACT_MAX_DISTANCE =
	18.0

local PREIMPACT_MAX_VERTICAL_DIFFERENCE =
	5.0

local PREIMPACT_MIN_HORIZONTAL_SPEED =
	8.0

-- Water Walk's surface constraint can momentarily flatten or distort the
-- replicated HRP velocity while the Lunge is still valid. CombatServer v24.7
-- publishes the accepted horizontal Lunge direction for this fallback.
local WATER_LUNGE_ASSUMED_SPEED =
	24.0

local PREIMPACT_MIN_TOWARD_DOT =
	0.12

local PREIMPACT_MIN_CLOSING_SPEED =
	12.0

-- Two Lunges started this far apart in time may still physically meet.
-- The spatial/motion tests below must ALSO pass.
local PREIMPACT_MAX_START_DESYNC =
	0.45

-- Do not use an ancient ServerLungeActive if another system failed to clear it.
local PREIMPACT_MAX_LUNGE_AGE =
	1.20


-- Conservative pre-animation spacing.
-- The final exact contact distance is calculated from BOTH clients'
-- actual animated kicking-leg extents at ClashImpact.
local INITIAL_ROOT_DISTANCE =
	8.0

local CONTACT_TARGET_GAP =
	0.06

local MIN_CONTACT_DISTANCE =
	5.0

local MAX_CONTACT_DISTANCE =
	11.5

local MAX_REPORTED_FOOT_EXTENT =
	6.5

local MIN_REPORTED_FOOT_EXTENT =
	0.35

local SINGLE_EXTENT_FALLBACK_DELAY =
	0.055


-- If animated foot extent cannot be resolved, still show the impact VFX
-- shortly after the authored ClashImpact marker using the current midpoint.
local CLASH_IMPACT_VFX_FALLBACK_DELAY =
	0.085


-- Gives IsStunned enough time to cancel the old Lunge track/drive before
-- the Clash animation begins.
local SYNC_LEAD_TIME =
	0.18


-- Long enough to cover:
-- ~80 animation frames + hitstop + network tolerance.
local CLASH_LOCK_DURATION =
	2.65

local CLASH_HARD_TIMEOUT =
	3.25


-- If one client reaches ClashEnd a few milliseconds before the other,
-- wait briefly before accepting one-sided completion.
local SINGLE_END_FALLBACK_DELAY =
	0.16


local DEBUG =
	false


-- =========================
-- STATE
-- =========================

local nextClashId =
	0

local activeClashes: {
	[number]: any
} = {}

local playerActiveClash: {
	[Player]: number
} = {}


local watchedCharacters: {
	[Model]: boolean
} = {}


-- Server-local timestamp for the authoritative ServerLungeActive rising edge.
-- This does not modify CombatServer; it only observes its existing attribute.
local lungeActiveSince: {
	[Model]: number
} = {}


-- =========================
-- GENERIC HELPERS
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


local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?, BasePart?)

	local character =
		player.Character

	if not character then
		return nil, nil, nil
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

		return nil, nil, nil
	end


	return character,
		humanoid,
		root
end


local function isDownedLocked(
	character: Model
): boolean

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


local function zeroRoot(
	root: BasePart
)

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero
end


local function setHorizontalFacing(
	root: BasePart,
	position: Vector3,
	forward: Vector3
)

	local horizontalForward =
		horizontalUnit(
			forward,
			root.CFrame.LookVector
		)


	root.CFrame =
		CFrame.lookAt(
			position,
			position
			+ horizontalForward,
			Vector3.yAxis
		)
end


-- =========================
-- NO-COLLISION DURING CLASH
-- =========================

local CORE_BODY_PART_NAMES = {
	"HumanoidRootPart",
	"Head",
	"Torso",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
}


local function collectCoreParts(
	character: Model
): {BasePart}

	local result = {}


	for _,
		name in ipairs(
			CORE_BODY_PART_NAMES
		) do

		local part =
			character:
			FindFirstChild(
				name
			)

		if part
			and part:IsA(
				"BasePart"
			) then

			table.insert(
				result,
				part
			)
		end
	end


	return result
end


local function createNoCollision(
	clash: any,
	characterA: Model,
	characterB: Model
)

	clash.noCollision =
		{}


	local partsA =
		collectCoreParts(
			characterA
		)

	local partsB =
		collectCoreParts(
			characterB
		)


	for _,
		partA in ipairs(
			partsA
		) do

		for _,
			partB in ipairs(
				partsB
			) do

			local constraint =
				Instance.new(
					"NoCollisionConstraint"
				)

			constraint.Name =
				"ClashNoCollision_v2"

			constraint.Part0 =
				partA

			constraint.Part1 =
				partB

			constraint.Parent =
				partB


			table.insert(
				clash.noCollision,
				constraint
			)
		end
	end
end


local function destroyNoCollision(
	clash: any
)

	for _,
		constraint in ipairs(
			clash.noCollision
				or {}
		) do

		if constraint.Parent then

			constraint:
				Destroy()
		end
	end


	clash.noCollision =
		{}
end


-- =========================
-- CLASH LOCK OWNERSHIP
-- =========================

local function lockCharacter(
	clash: any,
	player: Player,
	opponent: Player
)

	local character =
		player.Character

	if not character then
		return
	end


	character:SetAttribute(
		"ClashServerActive",
		true
	)

	character:SetAttribute(
		"ClashId",
		clash.id
	)

	character:SetAttribute(
		"ClashOpponentUserId",
		opponent.UserId
	)

	character:SetAttribute(
		"ClashStunOwnerId",
		clash.id
	)


	-- This is deliberately the SAME contract that the stable Lunge client
	-- already understands. LungeAttackController v5.3 sees IsStunned and
	-- calls its own normal Cancel path.
	character:SetAttribute(
		"IsStunned",
		true
	)

	character:SetAttribute(
		"StunEndsAt",
		clash.lockEndsAt
	)
end


local function maintainCharacterLock(
	clash: any,
	player: Player
)

	local character =
		player.Character

	if not character then
		return
	end


	local now =
		time()

	local currentEnd =
		character:GetAttribute(
			"StunEndsAt"
		)


	-- Preserve any OTHER combat stun that may be applied by a third party.
	-- Clash keeps itself locked until its own end, but remembers the external
	-- expiry so it does not clear a legitimate longer/overlapping stun.
	if typeof(currentEnd) ==
		"number"
		and math.abs(
			currentEnd
			- clash.lockEndsAt
		) > 0.035
			and currentEnd >
		now then

		local previous =
			clash.externalStunEnds[
		player
		]

		if not previous
			or currentEnd >
			previous then

			clash.externalStunEnds[
			player
			] =
				currentEnd
		end
	end


	local externalEnd =
		clash.externalStunEnds[
	player
	]

	local desiredEnd =
		clash.lockEndsAt

	if externalEnd
		and externalEnd >
		desiredEnd then

		desiredEnd =
			externalEnd
	end


	if character:GetAttribute(
		"IsStunned"
		) ~= true then

		character:SetAttribute(
			"IsStunned",
			true
		)
	end


	local publishedEnd =
		character:GetAttribute(
			"StunEndsAt"
		)

	if typeof(publishedEnd) ~=
		"number"
		or math.abs(
			publishedEnd
			- desiredEnd
		) > 0.035 then

		character:SetAttribute(
			"StunEndsAt",
			desiredEnd
		)
	end
end


local function releaseCharacterLock(
	clash: any,
	player: Player
)

	local character =
		player.Character

	if not character then
		return
	end


	character:SetAttribute(
		"ClashServerActive",
		false
	)

	character:SetAttribute(
		"ClashId",
		nil
	)

	character:SetAttribute(
		"ClashOpponentUserId",
		nil
	)


	local owns =
		character:GetAttribute(
			"ClashStunOwnerId"
		) == clash.id


	character:SetAttribute(
		"ClashStunOwnerId",
		nil
	)


	if not owns then
		return
	end


	local now =
		time()

	local externalEnd =
		clash.externalStunEnds[
	player
	]


	-- Re-check the currently published value once more in case another stun
	-- landed immediately before ClashEnd.
	local currentEnd =
		character:GetAttribute(
			"StunEndsAt"
		)

	if typeof(currentEnd) ==
		"number"
		and currentEnd >
		now
			and math.abs(
				currentEnd
				- clash.lockEndsAt
			) > 0.035 then

		if not externalEnd
			or currentEnd >
			externalEnd then

			externalEnd =
				currentEnd
		end
	end


	if externalEnd
		and externalEnd >
		now then

		character:SetAttribute(
			"IsStunned",
			true
		)

		character:SetAttribute(
			"StunEndsAt",
			externalEnd
		)

		return
	end


	character:SetAttribute(
		"IsStunned",
		false
	)

	character:SetAttribute(
		"StunEndsAt",
		nil
	)
end


-- =========================
-- ALIGNMENT
-- =========================

local function alignAtDistance(
	clash: any,
	distance: number
): (CFrame?, CFrame?)

	local characterA,
		_humanoidA,
		rootA =
		getAliveCharacter(
			clash.playerA
		)

	local characterB,
		_humanoidB,
		rootB =
		getAliveCharacter(
			clash.playerB
		)


	if not characterA
		or not rootA
		or not characterB
		or not rootB then

		return nil, nil
	end


	local axis =
		clash.axis


	local currentCenter =
		(
			rootA.Position
			+ rootB.Position
		)
		* 0.5


	local halfDistance =
		distance
		* 0.5


	-- Keep each participant's current vertical root position. Clash detection
	-- already rejects excessive Y differences.
	local positionA =
		Vector3.new(
			currentCenter.X
			- axis.X
			* halfDistance,
			rootA.Position.Y,
			currentCenter.Z
			- axis.Z
			* halfDistance
		)

	local positionB =
		Vector3.new(
			currentCenter.X
			+ axis.X
			* halfDistance,
			rootB.Position.Y,
			currentCenter.Z
			+ axis.Z
			* halfDistance
		)


	local cframeA =
		CFrame.lookAt(
			positionA,
			positionA
			+ axis,
			Vector3.yAxis
		)

	local cframeB =
		CFrame.lookAt(
			positionB,
			positionB
			- axis,
			Vector3.yAxis
		)


	rootA.CFrame =
		cframeA

	rootB.CFrame =
		cframeB


	zeroRoot(
		rootA
	)

	zeroRoot(
		rootB
	)


	return cframeA,
		cframeB
end


local function applyFootContactAlignment(
	clash: any,
	allowSingleFallback: boolean
): boolean

	if clash.finished
		or clash.contactAligned then

		return false
	end


	local extentA =
		clash.footExtents[
	clash.playerA
	]

	local extentB =
		clash.footExtents[
	clash.playerB
	]


	if not extentA
		and not extentB then

		return false
	end


	if not extentA
		or not extentB then

		if not allowSingleFallback then
			return false
		end


		-- Same R6 animation is used by both players, so one valid report is a
		-- safe fallback if the other packet is a few frames late/lost.
		local available =
			extentA
			or extentB

		extentA =
			extentA
			or available

		extentB =
			extentB
			or available
	end


	if not extentA
		or not extentB then

		return false
	end


	local desiredDistance =
		math.clamp(
			extentA
			+ extentB
			+ CONTACT_TARGET_GAP,
			MIN_CONTACT_DISTANCE,
			MAX_CONTACT_DISTANCE
		)


	local cframeA,
		cframeB =
		alignAtDistance(
			clash,
			desiredDistance
		)


	if not cframeA
		or not cframeB then

		return false
	end


	clash.contactAligned =
		true

	clash.contactDistance =
		desiredDistance


	-- Apply the same exact correction immediately on every client so the
	-- foot-to-foot freeze is visually identical even before replication
	-- catches up.
	remote:
		FireAllClients(
			"ContactAligned",
			clash.id,
			cframeA,
			cframeB,
			desiredDistance
		)


	-- The ClashImpact VFX is fired only AFTER the exact foot-contact
	-- correction has been calculated. This gives every participant and
	-- spectator the same authoritative impact position.
	if not clash.clashImpactVFXSent then

		clash.clashImpactVFXSent =
			true


		local impactPosition =
			(
				cframeA.Position
				+ cframeB.Position
			)
			* 0.5


		local impactCFrame =
			CFrame.lookAt(
				impactPosition,
				impactPosition
				+ clash.axis,
				Vector3.yAxis
			)


		remote:
			FireAllClients(
				"VFX",
				"ClashImpact",
				clash.id,
				clash.playerA.UserId,
				clash.playerB.UserId,
				impactCFrame
			)
	end


	if DEBUG then

		print(
			"[ClashServerCore v2.5] FOOT CONTACT",
			clash.id,
			clash.playerA.Name,
			"<->",
			clash.playerB.Name,
			"extentA",
			string.format(
				"%.3f",
				extentA
			),
			"extentB",
			string.format(
				"%.3f",
				extentB
			),
			"distance",
			string.format(
				"%.3f",
				desiredDistance
			)
		)
	end


	return true
end


-- =========================
-- FINISH
-- =========================

local function finishClash(
	clashId: number,
	reason: string
)

	local clash =
		activeClashes[
	clashId
	]

	if not clash
		or clash.finished then

		return
	end


	clash.finished =
		true


	destroyNoCollision(
		clash
	)


	for _,
		player in ipairs({
			clash.playerA,
			clash.playerB,
		}) do

		local _character,
			_humanoid,
			root =
			getAliveCharacter(
				player
			)

		if root then

			zeroRoot(
				root
			)
		end


		releaseCharacterLock(
			clash,
			player
		)


		if playerActiveClash[
			player
			] == clashId then

			playerActiveClash[
			player
			] =
				nil
		end
	end


	remote:
		FireAllClients(
			"VFX",
			"SlideEnd",
			clash.id,
			clash.playerA.UserId,
			clash.playerB.UserId
		)


	remote:
		FireAllClients(
			"End",
			clash.id,
			reason
		)


	activeClashes[
	clashId
	] =
		nil


	if DEBUG then

		print(
			"[ClashServerCore v2.5] END",
			clashId,
			reason
		)
	end
end


-- =========================
-- MULTIPLAYER QA DIAGNOSTICS
-- =========================

local lastEligibilityDiagnostic: {
	[Player]: number
} = {}


local function maybePrintEligibilityDiagnostic(
	player: Player
)

	if not DEBUG then
		return
	end


	local character =
		player.Character

	if not character then
		return
	end


	-- v2.3 diagnoses the full server-accepted Lunge because Clash may now be
	-- resolved BEFORE the authored ClashStart marker reaches the server.
	if character:GetAttribute(
		"ServerLungeActive"
		) ~= true then

		return
	end


	local now =
		time()

	local last =
		lastEligibilityDiagnostic[
	player
	]
		or -math.huge


	if now - last <
		0.20 then

		return
	end


	lastEligibilityDiagnostic[
	player
	] =
		now


	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)


	print(
		"[ClashServerCore v2.6] ELIGIBILITY",
		player.Name,
		"ServerLungeActive=",
		character:GetAttribute(
			"ServerLungeActive"
		),
		"ServerLungeClashActive=",
		character:GetAttribute(
			"ServerLungeClashActive"
		),
		"IsStunned=",
		character:GetAttribute(
			"IsStunned"
		),
		"DownedLocked=",
		isDownedLocked(
			character
		),
		"Position=",
		root
			and root:IsA(
				"BasePart"
			)
			and tostring(
				root.Position
			)
			or "NO_ROOT"
	)
end


local function getPublishedLungeDirection(
	character: Model
): Vector3?

	local published =
		character:GetAttribute(
			"ServerLungeDirection"
		)

	if typeof(published) ~=
		"Vector3" then

		return nil
	end

	local horizontal =
		Vector3.new(
			published.X,
			0,
			published.Z
		)

	if horizontal.Magnitude <=
		0.05 then

		return nil
	end

	return horizontal.Unit
end


local function getClashMotion(
	character: Model,
	root: BasePart
): (Vector3, number, string)

	local velocity =
		root.AssemblyLinearVelocity

	local horizontal =
		Vector3.new(
			velocity.X,
			0,
			velocity.Z
		)

	local actualSpeed =
		horizontal.Magnitude

	local publishedDirection =
		getPublishedLungeDirection(
			character
		)

	local waterLunge =
		character:GetAttribute(
			"ServerLungeWaterWalk"
		) == true

	if waterLunge
		and publishedDirection then

		local directionMismatch =
			actualSpeed > 0.05
			and horizontal.Unit:
			Dot(
				publishedDirection
			) < 0.20

		if actualSpeed <
			PREIMPACT_MIN_HORIZONTAL_SPEED
			or directionMismatch then

			local fallbackSpeed =
				math.max(
					actualSpeed,
					WATER_LUNGE_ASSUMED_SPEED
				)

			return publishedDirection
				* fallbackSpeed,
				fallbackSpeed,
				"WaterPublished"
		end
	end

	return horizontal,
		actualSpeed,
		"AssemblyVelocity"
end


-- =========================
-- PAIR VALIDATION
-- =========================

local function characterIsClashEligible(
	player: Player
): (boolean, Model?, Humanoid?, BasePart?)

	if playerActiveClash[
		player
		] then

		return false, nil, nil, nil
	end


	local character,
		humanoid,
		root =
		getAliveCharacter(
			player
		)


	if not character
		or not humanoid
		or not root then

		return false, nil, nil, nil
	end


	-- v2.3 IMPORTANT:
	-- Candidate selection intentionally requires ONLY ServerLungeActive.
	--
	-- Waiting for BOTH ServerLungeClashActive flags is too late under real
	-- multiplayer latency: the first DamageStart can deal 7 damage and cancel
	-- the other player's Lunge before that second ClashStart reaches server.
	if character:GetAttribute(
		"ServerLungeActive"
		) ~= true then

		return false, nil, nil, nil
	end


	if character:GetAttribute(
		"CombatSuppressed"
		) == true
			or character:GetAttribute(
				"IsStunned"
			) == true
			or isDownedLocked(
				character
			) then

		return false, nil, nil, nil
	end


	-- Backfill a timestamp if this script began observing in the middle of an
	-- already accepted Lunge.
	if not lungeActiveSince[
		character
		] then

		lungeActiveSince[
		character
		] =
			workspace:
			GetServerTimeNow()
	end


	return true,
		character,
		humanoid,
		root
end


local function pairIsValid(
	playerA: Player,
	playerB: Player
): (boolean, Model?, BasePart?, Model?, BasePart?, Vector3?)

	if playerA ==
		playerB then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local eligibleA,
		characterA,
		_humanoidA,
		rootA =
		characterIsClashEligible(
			playerA
		)

	local eligibleB,
		characterB,
		_humanoidB,
		rootB =
		characterIsClashEligible(
			playerB
		)


	if not eligibleA
		or not characterA
		or not rootA
		or not eligibleB
		or not characterB
		or not rootB then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local delta =
		rootB.Position
	- rootA.Position


	local horizontalDelta =
		Vector3.new(
			delta.X,
			0,
			delta.Z
		)

	local distance =
		horizontalDelta.Magnitude


	if distance <
		MIN_CLASH_ROOT_DISTANCE then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	if distance >
		PREIMPACT_MAX_DISTANCE then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	if math.abs(
		delta.Y
		) > PREIMPACT_MAX_VERTICAL_DIFFERENCE then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local axis =
		horizontalDelta.Unit


	local motionA,
		speedA,
		motionSourceA =
		getClashMotion(
			characterA,
			rootA
		)

	local motionB,
		speedB,
		motionSourceB =
		getClashMotion(
			characterB,
			rootB
		)


	local clashWindowA =
		characterA:GetAttribute(
			"ServerLungeClashActive"
		) == true

	local clashWindowB =
		characterB:GetAttribute(
			"ServerLungeClashActive"
		) == true

	local bothMarkerWindows =
		clashWindowA
		and clashWindowB


	-- =========================================================
	-- PATH A: BOTH authored Clash windows already reached server
	-- =========================================================
	--
	-- Keep the v2.2 post-crossing behavior as a fallback.
	if bothMarkerWindows then

		if distance >
			MAX_CLASH_ROOT_DISTANCE then

			return false,
				nil,
				nil,
				nil,
				nil,
				nil
		end


		if math.abs(
			delta.Y
			) > MAX_VERTICAL_DIFFERENCE then

			return false,
				nil,
				nil,
				nil,
				nil,
				nil
		end


		local motionDot: number? =
			nil


		if speedA >=
			MIN_LUNGE_MOTION_SPEED
			and speedB >=
			MIN_LUNGE_MOTION_SPEED then

			motionDot =
				motionA.Unit:
				Dot(
					motionB.Unit
				)


			if motionDot >
				MAX_OPPOSING_MOTION_DOT then

				return false,
					nil,
					nil,
					nil,
					nil,
					nil
			end

		elseif distance >
			12.0 then

			return false,
				nil,
				nil,
				nil,
				nil,
				nil
		end


		if DEBUG then

			print(
				"[ClashServerCore v2.6] PAIR ACCEPT MARKER-WINDOW",
				playerA.Name,
				playerB.Name,
				"distance",
				string.format(
					"%.2f",
					distance
				),
				"speedA",
				string.format(
					"%.1f",
					speedA
				),
				"speedB",
				string.format(
					"%.1f",
					speedB
				),
				"motionDot",
				motionDot
					and string.format(
						"%.3f",
						motionDot
					)
					or "LOW_SPEED_FALLBACK",
				"sourceA",
				motionSourceA,
				"sourceB",
				motionSourceB
			)
		end


		return true,
			characterA,
			rootA,
			characterB,
			rootB,
			axis
	end


	-- =========================================================
	-- PATH B: PRE-IMPACT trajectory detection
	-- =========================================================
	--
	-- This is the important multiplayer race fix.
	--
	-- Both CombatServer Lunges are already accepted, but one or both authored
	-- ClashStart markers have not reached server yet. Detect their physical
	-- convergence BEFORE either DamageStart can consume the opponent.
	local now =
		workspace:
		GetServerTimeNow()

	local startA =
		lungeActiveSince[
	characterA
	]

	local startB =
		lungeActiveSince[
	characterB
	]


	if not startA
		or not startB then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local ageA =
		now
	- startA

	local ageB =
		now
	- startB


	if ageA >
		PREIMPACT_MAX_LUNGE_AGE
			or ageB >
		PREIMPACT_MAX_LUNGE_AGE then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local startDesync =
		math.abs(
			startA
			- startB
		)


	if startDesync >
		PREIMPACT_MAX_START_DESYNC then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	if speedA <
		PREIMPACT_MIN_HORIZONTAL_SPEED
		or speedB <
		PREIMPACT_MIN_HORIZONTAL_SPEED then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local directionA =
		motionA.Unit

	local directionB =
		motionB.Unit


	-- A must be travelling toward B, and B toward A.
	local towardDotA =
		directionA:
		Dot(
			axis
		)

	local towardDotB =
		directionB:
		Dot(
			-axis
		)


	if towardDotA <
		PREIMPACT_MIN_TOWARD_DOT
		or towardDotB <
		PREIMPACT_MIN_TOWARD_DOT then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	-- Positive means the distance between the two roots is shrinking.
	local closingSpeed =
		(
			motionA
			- motionB
		):
		Dot(
			axis
		)


	if closingSpeed <
		PREIMPACT_MIN_CLOSING_SPEED then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	local motionDot =
		directionA:
		Dot(
			directionB
		)


	if motionDot >
		MAX_OPPOSING_MOTION_DOT then

		return false,
			nil,
			nil,
			nil,
			nil,
			nil
	end


	if DEBUG then

		print(
			"[ClashServerCore v2.6] PAIR ACCEPT PREIMPACT",
			playerA.Name,
			playerB.Name,
			"distance",
			string.format(
				"%.2f",
				distance
			),
			"vertical",
			string.format(
				"%.2f",
				math.abs(
					delta.Y
				)
			),
			"speedA",
			string.format(
				"%.1f",
				speedA
			),
			"speedB",
			string.format(
				"%.1f",
				speedB
			),
			"closing",
			string.format(
				"%.1f",
				closingSpeed
			),
			"towardA",
			string.format(
				"%.2f",
				towardDotA
			),
			"towardB",
			string.format(
				"%.2f",
				towardDotB
			),
			"motionDot",
			string.format(
				"%.3f",
				motionDot
			),
			"startDesync",
			string.format(
				"%.3f",
				startDesync
			),
			"windows",
			tostring(
				clashWindowA
			)
				.. "/"
				.. tostring(
					clashWindowB
				),
			"sourceA",
			motionSourceA,
			"sourceB",
			motionSourceB
		)
	end


	return true,
		characterA,
		rootA,
		characterB,
		rootB,
		axis
end


-- =========================
-- BEGIN
-- =========================

local function beginClash(
	playerA: Player,
	playerB: Player,
	characterA: Model,
	rootA: BasePart,
	characterB: Model,
	rootB: BasePart,
	axis: Vector3
)

	if playerActiveClash[
		playerA
		]
			or playerActiveClash[
		playerB
		] then

		return
	end


	nextClashId +=
		1


	local clashId =
		nextClashId


	local now =
		time()

	local serverNow =
		workspace:
		GetServerTimeNow()


	local clash = {
		id = clashId,

		playerA = playerA,
		playerB = playerB,

		axis = axis,

		createdAt = serverNow,
		startAt =
			serverNow
			+ SYNC_LEAD_TIME,

		lockEndsAt =
			now
			+ CLASH_LOCK_DURATION,

		footExtents = {},
		markers = {},
		endedPlayers = {},

		externalStunEnds = {},

		contactAligned = false,
		contactDistance = nil,

		noCollision = {},

		finished = false,
	}


	activeClashes[
	clashId
	] =
		clash

	playerActiveClash[
	playerA
	] =
		clashId

	playerActiveClash[
	playerB
	] =
		clashId


	createNoCollision(
		clash,
		characterA,
		characterB
	)


	-- IMPORTANT ORDER:
	-- lock first so LungeAttackController v5.3 immediately executes its
	-- existing Cancel path. We are not deleting/replacing any CombatServer
	-- state ourselves.
	lockCharacter(
		clash,
		playerA,
		playerB
	)

	lockCharacter(
		clash,
		playerB,
		playerA
	)


	alignAtDistance(
		clash,
		INITIAL_ROOT_DISTANCE
	)


	remote:
		FireAllClients(
			"Begin",
			clash.id,
			playerA.UserId,
			playerB.UserId,
			clash.startAt,
			CLASH_ANIMATION_ID,
			clash.axis
		)


	-- Re-assert the conservative initial spacing shortly before animation
	-- playback. This absorbs any final Lunge-drive packet that was already
	-- in flight when IsStunned was replicated.
	task.delay(
		math.max(
			0.04,
			SYNC_LEAD_TIME
			- 0.055
		),
		function()

			local current =
				activeClashes[
			clashId
			]

			if not current
				or current.finished
				or current.contactAligned then

				return
			end


			alignAtDistance(
				current,
				INITIAL_ROOT_DISTANCE
			)
		end
	)


	task.delay(
		CLASH_HARD_TIMEOUT,
		function()

			if activeClashes[
				clashId
				] then

				finishClash(
					clashId,
					"HardTimeout"
				)
			end
		end
	)


	if DEBUG then

		print(
			"[ClashServerCore v2.5] BEGIN",
			clash.id,
			playerA.Name,
			"<->",
			playerB.Name,
			"anim",
			"110715673180255",
			"initialDistance",
			INITIAL_ROOT_DISTANCE
		)
	end
end


-- =========================
-- SCAN
-- =========================

local function tryResolveAllPairs()

	local eligiblePlayers = {}


	for _,
		player in ipairs(
			Players:
				GetPlayers()
		) do

		maybePrintEligibilityDiagnostic(
			player
		)

		local eligible =
			characterIsClashEligible(
				player
			)

		if eligible then

			table.insert(
				eligiblePlayers,
				player
			)
		end
	end


	for indexA = 1,
		#eligiblePlayers - 1 do

		local playerA =
			eligiblePlayers[
		indexA
		]


		if playerActiveClash[
			playerA
			] then

			continue
		end


		for indexB =
			indexA + 1,
			#eligiblePlayers do

			local playerB =
				eligiblePlayers[
			indexB
			]


			if playerActiveClash[
				playerB
				] then

				continue
			end


			local valid,
				characterA,
				rootA,
				characterB,
				rootB,
				axis =
				pairIsValid(
					playerA,
					playerB
				)


			if valid
				and characterA
				and rootA
				and characterB
				and rootB
				and axis then

				beginClash(
					playerA,
					playerB,
					characterA,
					rootA,
					characterB,
					rootB,
					axis
				)

				break
			end
		end
	end
end


-- =========================
-- CLIENT REPORTS
-- =========================

local ALLOWED_MARKERS = {
	ClashImpact = true,
	ClashResolve = true,
	LandImpact = true,
	SlideStart = true,
	SlideEnd = true,
	ClashEnd = true,
}


local function playerBelongsToClash(
	clash: any,
	player: Player
): boolean

	return player ==
		clash.playerA
		or player ==
		clash.playerB
end


remote.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: string,
			clashId: number,
			arg1: any,
			_arg2: any
		)

			if typeof(clashId) ~=
				"number" then

				return
			end


			local clash =
			activeClashes[
			clashId
			]


			if not clash
				or clash.finished
				or not playerBelongsToClash(
					clash,
					player
				) then

				return
			end


			if action ==
				"FootExtent" then

				if typeof(arg1) ~=
					"number"
					or arg1 <
					MIN_REPORTED_FOOT_EXTENT
					or arg1 >
					MAX_REPORTED_FOOT_EXTENT then

					return
				end


				if clash.footExtents[
					player
					] then

					return
				end


				clash.footExtents[
				player
				] =
				arg1


				if applyFootContactAlignment(
					clash,
					false
					) then

					return
				end


				-- If the second client packet does not arrive promptly, use the
				-- one valid R6 extent symmetrically. Both players use the SAME
				-- approved animation.
				task.delay(
					SINGLE_EXTENT_FALLBACK_DELAY,
					function()

						local current =
						activeClashes[
						clashId
						]

						if current
							and not current.finished
							and not current.contactAligned then

							applyFootContactAlignment(
								current,
								true
							)
						end
					end
				)


				return
			end


			if action ==
				"Marker" then

				if typeof(arg1) ~=
					"string"
					or not ALLOWED_MARKERS[
					arg1
					] then

					return
				end


				local markerName =
				arg1


				local markerPlayers =
				clash.markers[
				markerName
				]

				if not markerPlayers then

					markerPlayers =
					{}

					clash.markers[
					markerName
					] =
					markerPlayers
				end


				if markerPlayers[
					player
					] then

					return
				end


				markerPlayers[
				player
				] =
				workspace:
				GetServerTimeNow()


				if DEBUG then

					print(
						"[ClashServerCore v2.5] MARKER",
						clash.id,
						markerName,
						player.Name
					)
				end


				if markerName ==
					"ClashImpact" then

					-- Normally applyFootContactAlignment sends the VFX first,
					-- using the exact corrected midpoint. This is only a safety
					-- fallback for a missing/invalid FootExtent report.
					task.delay(
						CLASH_IMPACT_VFX_FALLBACK_DELAY,
						function()

							local current =
							activeClashes[
							clashId
							]


							if not current
								or current.finished
								or current.clashImpactVFXSent then

								return
							end


							local _characterA,
							_humanoidA,
							rootA =
							getAliveCharacter(
								current.playerA
							)

							local _characterB,
							_humanoidB,
							rootB =
							getAliveCharacter(
								current.playerB
							)


							if not rootA
								or not rootB then

								return
							end


							current.clashImpactVFXSent =
							true


							local impactPosition =
							(
								rootA.Position
								+ rootB.Position
							)
							* 0.5


							local impactCFrame =
							CFrame.lookAt(
								impactPosition,
								impactPosition
								+ current.axis,
								Vector3.yAxis
							)


							remote:
							FireAllClients(
								"VFX",
								"ClashImpact",
								current.id,
								current.playerA.UserId,
								current.playerB.UserId,
								impactCFrame
							)
						end
					)


				elseif markerName ==
					"LandImpact" then

					if not clash.landVFXSent then

						clash.landVFXSent =
						true

						remote:
						FireAllClients(
							"VFX",
							"LandImpact",
							clash.id,
							clash.playerA.UserId,
							clash.playerB.UserId
						)
					end


				elseif markerName ==
					"SlideStart" then

					if not clash.slideVFXStarted then

						clash.slideVFXStarted =
						true

						remote:
						FireAllClients(
							"VFX",
							"SlideStart",
							clash.id,
							clash.playerA.UserId,
							clash.playerB.UserId
						)
					end


				elseif markerName ==
					"SlideEnd" then

					if not clash.slideVFXEnded then

						clash.slideVFXEnded =
						true

						remote:
						FireAllClients(
							"VFX",
							"SlideEnd",
							clash.id,
							clash.playerA.UserId,
							clash.playerB.UserId
						)
					end


				elseif markerName ==
					"ClashEnd" then

					clash.endedPlayers[
					player
					] =
					true


					if clash.endedPlayers[
						clash.playerA
						]
						and clash.endedPlayers[
						clash.playerB
						] then

						finishClash(
							clash.id,
							"BothClashEnd"
						)

						return
					end


					task.delay(
						SINGLE_END_FALLBACK_DELAY,
						function()

							local current =
							activeClashes[
							clashId
							]

							if current
								and not current.finished then

								finishClash(
									clashId,
									"SingleClashEndFallback"
								)
							end
						end
					)
				end


				return
			end


			if action ==
				"ClientEnded" then

				clash.endedPlayers[
				player
				] =
				true


				if clash.endedPlayers[
					clash.playerA
					]
					and clash.endedPlayers[
					clash.playerB
					] then

					finishClash(
						clash.id,
						"BothTracksEnded"
					)
				end
			end
		end
	)


-- =========================
-- CHARACTER WATCH
-- =========================

local function watchCharacter(
	player: Player,
	character: Model
)

	if watchedCharacters[
		character
		] then

		return
	end


	watchedCharacters[
	character
	] =
		true


	character:SetAttribute(
		"ClashServerActive",
		false
	)

	character:SetAttribute(
		"ClashId",
		nil
	)

	character:SetAttribute(
		"ClashOpponentUserId",
		nil
	)

	character:SetAttribute(
		"ClashStunOwnerId",
		nil
	)


	local function refreshLungeActiveTimestamp()

		if character:GetAttribute(
			"ServerLungeActive"
			) == true then

			if not lungeActiveSince[
				character
				] then

				lungeActiveSince[
				character
				] =
					workspace:
					GetServerTimeNow()
			end

		else

			lungeActiveSince[
			character
			] =
				nil
		end
	end


	character:
		GetAttributeChangedSignal(
			"ServerLungeActive"
		):
		Connect(
			function()

				refreshLungeActiveTimestamp()

				if character:GetAttribute(
					"ServerLungeActive"
					) == true then

					task.defer(
						tryResolveAllPairs
					)
				end
			end
		)


	refreshLungeActiveTimestamp()


	character:
		GetAttributeChangedSignal(
			"ServerLungeClashActive"
		):
		Connect(
			function()

				if character:GetAttribute(
					"ServerLungeClashActive"
					) == true then

					task.defer(
						tryResolveAllPairs
					)
				end
			end
		)


	character.AncestryChanged:
		Connect(
			function(
				_child,
				parent
			)

				if parent then
					return
				end


				watchedCharacters[
				character
				] =
				nil

				lungeActiveSince[
				character
				] =
				nil


				local clashId =
				playerActiveClash[
				player
				]

				if clashId then

					finishClash(
						clashId,
						"CharacterRemoved"
					)
				end
			end
		)
end


local function watchPlayer(
	player: Player
)

	player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				watchCharacter(
					player,
					character
				)
			end
		)


	if player.Character then

		watchCharacter(
			player,
			player.Character
		)
	end
end


for _,
	player in ipairs(
		Players:
			GetPlayers()
	) do

	watchPlayer(
		player
	)
end


Players.PlayerAdded:
	Connect(
		watchPlayer
	)


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			local clashId =
			playerActiveClash[
			player
			]

			if clashId then

				finishClash(
					clashId,
					"PlayerRemoving"
				)
			end
		end
	)


-- =========================
-- HEARTBEAT
-- =========================

RunService.Heartbeat:
	Connect(
		function()

			-- Heartbeat is the critical v2.3 path:
			-- detect two server-accepted Lunges physically converging BEFORE
			-- DamageStart/ClashStart packet ordering can let one hit cancel the
			-- other. Attribute-change signals simply reduce detection latency.
			tryResolveAllPairs()


			for _,
				clash in pairs(
					activeClashes
				) do

				if clash.finished then
					continue
				end


				maintainCharacterLock(
					clash,
					clash.playerA
				)

				maintainCharacterLock(
					clash,
					clash.playerB
				)
			end
		end
	)


print(
	"[ClashServerCore] READY v2.6"
		.. " | IsolatedFromCombatServer=ON"
		.. " | Reads=ServerLungeActive+ServerLungeClashActive"
		.. " | Animation=110715673180255"
		.. " | FootContactReports=2Client"
		.. " | InitialDistance=8"
		.. " | ContactGap=0.06"
		.. " | ExistingLungeCancelContract=IsStunned"
		.. " | CombatModeServerGate=REMOVED"
		.. " | CurrentFacingGate=REMOVED"
		.. " | PREIMPACT_DETECTION=ON"
		.. " | CandidateGate=ServerLungeActive"
		.. " | PreImpactDistance=18"
		.. " | PreImpactStartDesync=0.45"
		.. " | PreventFirstDamageRace=ON"
		.. " | WaterLungeMotionFallback=ServerPublishedDirection"
		.. " | SyntaxBootstrapFix=ON"
)

return true
