--!strict
-- DownedServer v31.5 - DB CCL Cleanup + Carry Pickup Ground Clearance
-- ServerScriptService > DownedServer
--
-- Existing remotes:
-- ReplicatedStorage > DownedRemotes
--   ExecuteRequest
--   CarryRequest
--   DownedState
--   DownedAnimationSync (created automatically if missing)
--
-- Server-only damage gateway:
-- ServerStorage > DownedInternal > ApplyDamage
--
-- v22 notes:
-- - Basic Execute now uses 270-frame / 4.5 s animations.
-- - Executor animation: 91747169766286. Victim animation: 96138604942161.
-- - Authored lethal impact is frame 203; poof/hide is frame 245; unlock is frame 270.
-- - Any incoming damage attempt on the Executor before lethal impact cancels the Execute.
-- - NEW v23: every cancelled Execute restarts the victim's full Downed timer.
-- - NEW v24: valid PvP damage tags only the victim; repeated hits refresh that source's 90 s tag.
-- - NEW v24: successful Carry mutually tags Carrier and Victim.
-- - NEW v24: true death clears victim-side Combat Tags before respawn.
-- - Direct Humanoid health loss also cancels the Execute as a fallback for damage paths that bypass ApplyDamage.
-- - While being executed, the Downed victim is non-interceptable: CanCollide/CanTouch/CanQuery are disabled and IsBeingExecuted=true.
-- - If cancelled, victim collision/query state is restored and Downed Idle resumes.
--
-- v21 notes:
-- - Keeps Executor + Victim grounded together during the authored Execute, preserving their exact Moon Animator relation.
-- - finalKill no longer lifts only the Victim while an Execute pair is active.
-- - Fresh respawns explicitly re-enable ordinary locomotion Humanoid states and recover grounded characters to Running.
--
-- v20 notes:
-- - Execute poof VFX/SFX is rendered locally via a persistent StarterPlayerScripts client for reliable visibility.
-- - True-death respawn delay is 8 seconds (configurable below).
-- - Walk/Fall respawn repair is handled by a separate persistent client guard; Carry/Downed/Execute behavior is otherwise unchanged.
--
-- v19 notes:
-- - ExecuteExecutor and ExecuteVictim are authored at 60 FPS for 115 frames (1.9167 s).
-- - Historical v19 ExecuteVictim used asset 105206176890382 (replaced in v22).
-- - At frame 90 (1.50 s), the executed body plays Naruto-style poof SFX 90296139665102, emits smoke, and becomes physically invisible/non-collidable.
-- - The old character remains in Workspace internally until normal Roblox respawn, avoiding unnecessary respawn-flow changes.
-- - Removes the visible corpse/final-pose dependency: the Executor continues through frame 115 while the Victim is already gone.
--
-- v18 notes:
-- - Marks a character as ExecutionFinalized before lethal health is committed so no death/HealthChanged race can re-enter Downed.
-- - Clears IsDowned at the execution impact while keeping IsExecuting locked, preventing any late Downing sequence from restarting.
--
-- v17 notes:
-- - Snaps the Executor to the exact Victim-relative Moon Animator pose before Basic Execute starts.
-- - Anchors the Executor during the authored Execute so the stomp cannot drift off target.
-- - Adds a monotonically increasing Downed cycleId. Recovery timers, fallback callbacks, and client RecoveryFinished messages are accepted only for the current cycle.
-- - Prevents stale recovery work from an earlier Downed from instantly reviving a later Downed.
--
-- v16 notes:
-- - Integrates the Basic unarmed Execute animations.
-- - Final death is synchronized to the executor marker "ExecuteHit" (frame 48 / 0.80 s).
-- - Server validates the marker inside a narrow timing window and has a fallback hit time.
-- - Carry / Downed / Airborne Drop behavior from v15 is unchanged.
--
-- v15 notes:
-- - Fixes intermittent mid-air anchoring after Drop.
-- - Ground raycasts ignore every player character, so the Carrier/other players cannot be mistaken for floor.
-- - Ground raycasts respect CanCollide, ignoring non-collidable visual/query parts.
-- - Airborne Drop starts with a guaranteed downward velocity and has a server watchdog that prevents hovering.
-- - After real ground contact, Downed Idle ground-fit and the recovery timer resume normally.
--
-- v14 notes:
-- - Dropped Downed players are released into gravity instead of being anchored in mid-air.
-- - While airborne, Carry/Execute targeting is blocked until the victim lands.
-- - Landing is detected server-side with a downward raycast and the real R6 body bottom.
--
-- v12 notes:
-- - CarryCarrierRun switches client-side while sprinting.
-- - Keeps the confirmed-stable Downed/Recovery behavior from v8-v11.
--
-- Stable v8 features:
-- - Keeps Health EXACTLY at DOWNED_HEALTH while Downed (blocks regen/healing/damage).
-- - Grounds the real R6 Downed Idle pose dynamically instead of using a fixed Y offset.
-- - Stores the exact Idle Y correction and reverses it during Recovery.
-- - Disables FallingDown + Ragdoll during Downed/Recovery and restores them afterward.
-- - Keeps Carry / Execute / pre-lethal behavior from v7.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatTagService =
	require(
		ServerScriptService:
		WaitForChild("CombatTagService")
	)

local substitutionInternal =
	ServerStorage:
	WaitForChild(
		"SubstitutionInternal",
		10
	)

if not substitutionInternal then
	error(
		"[Downed-Server] SubstitutionInternal did not appear after 10s. "
			.. "SubstitutionServer v2 is missing or failed to start."
	)
end

local trySubstitution =
	substitutionInternal:
	WaitForChild(
		"TrySubstitution",
		5
	) :: BindableFunction?

if not trySubstitution then
	error(
		"[Downed-Server] SubstitutionInternal.TrySubstitution is missing."
	)
end

local remotes = ReplicatedStorage:WaitForChild("DownedRemotes")
local executeRequest = remotes:WaitForChild("ExecuteRequest") :: RemoteEvent
local carryRequest = remotes:WaitForChild("CarryRequest") :: RemoteEvent
local downedStateEvent = remotes:WaitForChild("DownedState") :: RemoteEvent

local animationSync = remotes:FindFirstChild("DownedAnimationSync") :: RemoteEvent?

if not animationSync then
	animationSync = Instance.new("RemoteEvent")
	animationSync.Name = "DownedAnimationSync"
	animationSync.Parent = remotes
end

local executionPoofFX = remotes:FindFirstChild("ExecutionPoofFX") :: RemoteEvent?

if not executionPoofFX then
	executionPoofFX = Instance.new("RemoteEvent")
	executionPoofFX.Name = "ExecutionPoofFX"
	executionPoofFX.Parent = remotes
end

-- =========================
-- SERVER-ONLY DAMAGE GATEWAY
-- =========================

local internalFolder = ServerStorage:FindFirstChild("DownedInternal")

if not internalFolder then
	internalFolder = Instance.new("Folder")
	internalFolder.Name = "DownedInternal"
	internalFolder.Parent = ServerStorage
end

local oldApplyDamage = internalFolder:FindFirstChild("ApplyDamage")

if oldApplyDamage then
	oldApplyDamage:Destroy()
end

local applyDamageFunction = Instance.new("BindableFunction")
applyDamageFunction.Name = "ApplyDamage"
applyDamageFunction.Parent = internalFolder

-- =========================
-- CONFIG
-- =========================

local DOWNED_TIME = 20
local RECOVERY_HEALTH = 30
local DOWNED_HEALTH = 1

-- Maximum amount the server is allowed to move the anchored HRP vertically
-- when fitting the actual animated Downed Idle pose to the ground.
local MAX_IDLE_GROUND_CORRECTION = 4

-- If the client never reports the end of Recovery, server releases the player.
local RECOVERY_FINISH_FALLBACK = 4.0

local EXECUTION_RANGE = 8

-- Roblox can occasionally leave a grounded R6 Humanoid reporting Freefall
-- for a short time after locomotion/root-motion transitions.
-- Carry/Execute should care about PHYSICAL airborne state, not a stale enum.
local INTERACTION_GROUND_RAY_DISTANCE = 4.5
local INTERACTION_MAX_GROUNDED_VERTICAL_SPEED = 7
local CARRY_RANGE = 8

-- Basic Execute timing (animations authored at 60 FPS).
-- Both animations are exactly 270 frames = 4.50 s.
-- The original 115-frame motion was shifted later by 155 frames:
-- old frame 48 -> new frame 203 (lethal impact)
-- old frame 90 -> new frame 245 (poof/hide)
-- old frame 115 -> new frame 270 (Executor unlock)
local EXECUTION_DURATION = 270 / 60 -- 4.50 s
local EXECUTION_HIT_TIME = 203 / 60 -- 3.3833 s
local EXECUTION_POOF_TIME = 245 / 60 -- 4.0833 s

local EXECUTION_POOF_SOUND_ID = "rbxassetid://90296139665102"
local EXECUTION_POOF_VOLUME = 1.0
local EXECUTION_POOF_PARTICLE_COUNT = 24

-- Delay for real Roblox deaths. Downed recovery does not use this because it is not a real death.
local EXECUTION_RESPAWN_DELAY = 8.0
Players.RespawnTime = EXECUTION_RESPAWN_DELAY

-- Client marker is presentation-driven, so the server only accepts it near the
-- authored frame 203 impact. A server fallback prevents the Execute from hanging
-- if the marker is missing or was not moved in Moon Animator.
local EXECUTION_MARKER_EARLIEST = 191 / 60 -- 3.1833 s
local EXECUTION_MARKER_LATEST = 215 / 60 -- 3.5833 s
local EXECUTION_HIT_FALLBACK = EXECUTION_HIT_TIME + 0.12

-- Airborne Drop:
-- Dropped Downed players are released from Carry and allowed to fall naturally.
local DROP_FORWARD_NUDGE = 0.75
local DROP_MAX_HORIZONTAL_SPEED = 22
local DROP_INITIAL_FALL_SPEED = 7
local AIRBORNE_MIN_FALL_SPEED = 5
local AIRBORNE_STUCK_GRACE = 0.12
local AIRBORNE_GROUND_RAY_LENGTH = 160
local AIRBORNE_LANDING_TOLERANCE = 0.35
local AIRBORNE_LANDING_MAX_UPWARD_SPEED = 1.5

-- Exact R6 placement measured in Moon Animator:
-- carrierTorso.CFrame:ToObjectSpace(victimRoot.CFrame)
-- Do not replace this with guessed XYZ/Euler offsets.
local CARRY_TORSO_RELATIVE_CFRAME = CFrame.new(
	1.771755, 1.504292, 0.192993,
	0.999900, -0.000713, -0.014135,
	0.000000, 0.998732, -0.050343,
	0.014153, 0.050338, 0.998632
)

-- Exact R6 Basic Execute placement measured in Moon Animator:
-- victimRoot.CFrame:ToObjectSpace(executorRoot.CFrame)
-- The Victim stays in the stable Downed pose; the Executor snaps to this
-- transform before both Execute animations start.
local EXECUTOR_RELATIVE_TO_VICTIM_CFRAME = CFrame.new(
	1.037281, 0.017088, -1.977417,
	-0.997856, -0.065453, 0.000000,
	-0.065453, 0.997856, 0.000000,
	0.000000, 0.000000, -1.000000
)

local FLOOR_CLEARANCE = 0.08

-- Execute pair ground fitting. Both anchored roots receive the SAME vertical
-- correction so their exact Moon Animator relationship is never changed.
local EXECUTION_GROUND_FIT_MAX_STEP = 0.30
local EXECUTION_GROUND_RAY_UP = 8
local EXECUTION_GROUND_RAY_DOWN = 28

-- =========================
-- TYPES
-- =========================

type CarryPartState = {
	canCollide: boolean,
	massless: boolean,
}

type DownedInfo = {
	state: string, -- Normal | Downed | Executed
	cycleId: number,

	downedAt: number,
	recoveryDeadline: number,
	recoveryTask: thread?,

	carriedBy: Player?,
	carrying: Player?,
	airborne: boolean,

	originalWalkSpeed: number,
	originalUseJumpPower: boolean,
	originalJumpPower: number,
	originalJumpHeight: number,
	originalAutoRotate: boolean,
	originalPlatformStand: boolean,
	originalBreakJointsOnDeath: boolean,
	originalFallingDownEnabled: boolean,
	originalRagdollEnabled: boolean,

	carryPhysics: {[BasePart]: CarryPartState}?,

	idleOffsetApplied: boolean,
	idleRootYOffset: number,
	recovering: boolean,
	recoveryTween: Tween?,
}

type ExecutionSnapshot = {
	walkSpeed: number,
	rootAnchored: boolean,
	useJumpPower: boolean,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	platformStand: boolean,
}

type ExecutionVictimPartState = {
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean,
}

-- =========================
-- STATE
-- =========================

local downedInfo: {[Player]: DownedInfo} = {}
local executing: {[Player]: boolean} = {}
local allowFinalDeath: {[Player]: boolean} = {}
local interceptingHealth: {[Player]: boolean} = {}

-- Active Basic Execute synchronization. Keyed by executor.
local executionTarget: {[Player]: Player} = {}
local executionStartedAt: {[Player]: number} = {}
local executionMarkerReceived: {[Player]: boolean} = {}
local executionCancelRequested: {[Player]: boolean} = {}
local executionVictimPhysics: {[Player]: {[BasePart]: ExecutionVictimPartState}} = {}

local recoverPlayer: (Player) -> ()
local startRecovery: (Player) -> ()
local detachCarry: (Player, Vector3?) -> ()

local function makeDefaultInfo(): DownedInfo
	return {
		state = "Normal",
		cycleId = 0,

		downedAt = 0,
		recoveryDeadline = 0,
		recoveryTask = nil,

		carriedBy = nil,
		carrying = nil,
		airborne = false,

		originalWalkSpeed = 16,
		originalUseJumpPower = true,
		originalJumpPower = 50,
		originalJumpHeight = 7.2,
		originalAutoRotate = true,
		originalPlatformStand = false,
		originalBreakJointsOnDeath = true,
		originalFallingDownEnabled = true,
		originalRagdollEnabled = true,

		carryPhysics = nil,

		idleOffsetApplied = false,
		idleRootYOffset = 0,
		recovering = false,
		recoveryTween = nil,
	}
end

local function getInfo(player: Player): DownedInfo
	local info = downedInfo[player]

	if not info then
		info = makeDefaultInfo()
		downedInfo[player] = info
	end

	return info
end

-- =========================
-- ATTRIBUTES
-- =========================

local function updateActionLocked(character: Model)
	local locked =
		character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true

	character:SetAttribute("DownedActionLocked", locked)
end

local function setDownedAttributes(
	character: Model,
	downed: boolean,
	carried: boolean
)
	character:SetAttribute("IsDowned", downed)
	character:SetAttribute("Downed", downed)
	character:SetAttribute("IsCarried", carried)

	if not downed then
		character:SetAttribute("IsDownedAirborne", false)
	end

	updateActionLocked(character)
end

local function setExecuting(character: Model, value: boolean)
	character:SetAttribute("IsExecuting", value)
	updateActionLocked(character)
end

local function initializeCharacterAttributes(character: Model)
	character:SetAttribute("IsDowned", false)
	character:SetAttribute("Downed", false)
	character:SetAttribute("IsCarried", false)
	character:SetAttribute("IsCarrying", false)
	character:SetAttribute("IsExecuting", false)
	character:SetAttribute("IsBeingExecuted", false)
	character:SetAttribute("ExecutionFinalized", false)
	character:SetAttribute("ExecutedPoofed", false)
	character:SetAttribute("IsRecovering", false)
	character:SetAttribute("IsDownedAirborne", false)
	character:SetAttribute("DownedActionLocked", false)
end

-- =========================
-- CHARACTER HELPERS
-- =========================

local function getCharacterPieces(
	player: Player
): (Model?, Humanoid?, BasePart?)
	local character = player.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not root then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function zeroRootVelocity(root: BasePart?)
	if not root then
		return
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Ground detection must never treat another player as terrain. This was the
-- source of the intermittent v14 hover: during a jump/double-jump the ray
-- could hit the Carrier underneath, immediately call Landed, and anchor the
-- Downed player in mid-air.
local function makeGroundRaycastParams(
	ignoreCharacter: Model?
): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false
	params.RespectCanCollide = true

	local exclusions: {Instance} = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local otherCharacter = otherPlayer.Character

		if otherCharacter then
			table.insert(exclusions, otherCharacter)
		end
	end

	if ignoreCharacter
		and not table.find(exclusions, ignoreCharacter) then
		table.insert(exclusions, ignoreCharacter)
	end

	params.FilterDescendantsInstances = exclusions
	return params
end


local function isPhysicallyGroundedForInteraction(
	character: Model,
	humanoid: Humanoid,
	root: BasePart
): boolean

	-- FloorMaterial is the cheapest/strongest grounded signal when Roblox
	-- has already updated it correctly.
	if humanoid.FloorMaterial
		~= Enum.Material.Air then

		return true
	end

	-- A genuinely airborne player should still be blocked.
	-- This also prevents a downward ray near the ground from allowing
	-- interaction during most of an actual jump/fall.
	if math.abs(
		root.AssemblyLinearVelocity.Y
		) > INTERACTION_MAX_GROUNDED_VERTICAL_SPEED then

		return false
	end

	local params =
		makeGroundRaycastParams(
			character
		)

	local result =
		workspace:Raycast(
			root.Position,
			Vector3.new(
				0,
				-INTERACTION_GROUND_RAY_DISTANCE,
				0
			),
			params
		)

	return result ~= nil
end


local function makeRootWorldUpright(root: BasePart?)
	if not root then
		return
	end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)

	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end

	root.CFrame = CFrame.lookAt(
		root.Position,
		root.Position + flat,
		Vector3.yAxis
	)
end

local function liftCharacterOutOfGround(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not root then
		return
	end

	local boundsCF, boundsSize = character:GetBoundingBox()
	local bottom = boundsCF.Position.Y - boundsSize.Y * 0.5

	local params = makeGroundRaycastParams(character)

	local result = workspace:Raycast(
		root.Position + Vector3.new(0, 8, 0),
		Vector3.new(0, -24, 0),
		params
	)

	if not result then
		return
	end

	local requiredBottom = result.Position.Y + FLOOR_CLEARANCE

	if bottom >= requiredBottom then
		return
	end

	local lift = requiredBottom - bottom

	character:PivotTo(
		character:GetPivot() + Vector3.new(0, lift, 0)
	)
end

local function disableDownedPhysicsStates(
	humanoid: Humanoid
)
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.FallingDown,
		false
	)

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Ragdoll,
		false
	)

	local state = humanoid:GetState()

	if state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Ragdoll then

		humanoid:ChangeState(
			Enum.HumanoidStateType.Physics
		)
	end
end


local function saveHumanoidState(
	humanoid: Humanoid,
	info: DownedInfo
)
	info.originalWalkSpeed = humanoid.WalkSpeed
	info.originalUseJumpPower = humanoid.UseJumpPower
	info.originalJumpPower = humanoid.JumpPower
	info.originalJumpHeight = humanoid.JumpHeight
	info.originalAutoRotate = humanoid.AutoRotate
	info.originalPlatformStand = humanoid.PlatformStand
	info.originalBreakJointsOnDeath = humanoid.BreakJointsOnDeath

	info.originalFallingDownEnabled =
		humanoid:GetStateEnabled(
			Enum.HumanoidStateType.FallingDown
		)

	info.originalRagdollEnabled =
		humanoid:GetStateEnabled(
			Enum.HumanoidStateType.Ragdoll
		)
end


local function putHumanoidIntoDownedState(
	character: Model,
	humanoid: Humanoid,
	root: BasePart?
)
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Dead,
		false
	)

	disableDownedPhysicsStates(humanoid)

	humanoid.BreakJointsOnDeath = false
	humanoid.Sit = false
	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = false

	if root then
		zeroRootVelocity(root)
		makeRootWorldUpright(root)
		liftCharacterOutOfGround(character)
		root.Anchored = true
	end

	if humanoid.Health <= 0 then
		humanoid.Health = 1
	end

	updateActionLocked(character)
end

local function restoreHumanoidAfterDowned(
	character: Model,
	humanoid: Humanoid,
	root: BasePart?,
	info: DownedInfo
)
	humanoid.Sit = false

	if root then
		root.Anchored = false
	end

	humanoid.PlatformStand = false
	humanoid.AutoRotate = info.originalAutoRotate

	humanoid.WalkSpeed = info.originalWalkSpeed
	humanoid.UseJumpPower = info.originalUseJumpPower
	humanoid.JumpPower = info.originalJumpPower
	humanoid.JumpHeight = info.originalJumpHeight

	-- Ordinary future lethal damage must still be intercepted by Downed.
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Dead,
		false
	)

	-- Restore the Downed-scoped Humanoid state settings captured on entry.
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.FallingDown,
		info.originalFallingDownEnabled
	)

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Ragdoll,
		info.originalRagdollEnabled
	)

	zeroRootVelocity(root)
	makeRootWorldUpright(root)
	liftCharacterOutOfGround(character)

	-- Authored Recovery already handled presentation; return to locomotion.
	humanoid:ChangeState(
		Enum.HumanoidStateType.Running
	)
end

-- =========================
-- CARRY PHYSICS
-- =========================

local function saveAndDisableCarryPhysics(
	targetCharacter: Model,
	info: DownedInfo
)
	local saved: {[BasePart]: CarryPartState} = {}

	for _, instance in ipairs(targetCharacter:GetDescendants()) do
		if instance:IsA("BasePart") then
			saved[instance] = {
				canCollide = instance.CanCollide,
				massless = instance.Massless,
			}

			instance.CanCollide = false
			instance.Massless = true
		end
	end

	info.carryPhysics = saved
end

local function restoreCarryPhysics(info: DownedInfo)
	local saved = info.carryPhysics

	if not saved then
		return
	end

	for part, state in pairs(saved) do
		if part.Parent then
			part.CanCollide = state.canCollide
			part.Massless = state.massless
		end
	end

	info.carryPhysics = nil
end


local function removeCarryWeld(targetCharacter: Model?)
	if not targetCharacter then
		return
	end

	local weld = targetCharacter:FindFirstChild("CarryWeld")

	if weld then
		weld:Destroy()
	end

	-- Clean any residue if this rollback is run after the Codex
	-- separate-assembly version has existed in the place.
	local carrierAttachmentReference =
		targetCharacter:FindFirstChild("CarryCarrierAttachmentRef")

	if carrierAttachmentReference then
		if carrierAttachmentReference:IsA("ObjectValue") then
			local attachment = carrierAttachmentReference.Value

			if attachment then
				attachment:Destroy()
			end
		end

		carrierAttachmentReference:Destroy()
	end

	local targetRoot =
		targetCharacter:FindFirstChild("HumanoidRootPart")

	if targetRoot and targetRoot:IsA("BasePart") then
		for _, name in ipairs({
			"CarryAlignPosition",
			"CarryAlignOrientation",
			"CarryFollowerAttachment",
			}) do
			local residue = targetRoot:FindFirstChild(name)

			if residue then
				residue:Destroy()
			end
		end
	end
end

local function createCarryWeld(
	carrierTorso: BasePart,
	targetCharacter: Model,
	targetRoot: BasePart
)
	removeCarryWeld(targetCharacter)

	local desiredRootCFrame =
		carrierTorso.CFrame * CARRY_TORSO_RELATIVE_CFRAME

	-- Exact Moon Animator relation:
	-- Carrier Torso -> Victim HumanoidRootPart.
	targetRoot.CFrame = desiredRootCFrame
	zeroRootVelocity(targetRoot)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = carrierTorso
	weld.Part1 = targetRoot
	weld.Parent = targetCharacter
end

-- =========================
-- DOWNED IDLE GROUND FIT
-- =========================

local R6_VISIBLE_PARTS = {
	"Head",
	"Torso",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
}

local function getPartBottomY(part: BasePart): number
	local cf = part.CFrame
	local size = part.Size

	local halfWorldHeight =
		math.abs(cf.RightVector.Y) * size.X * 0.5
		+ math.abs(cf.UpVector.Y) * size.Y * 0.5
		+ math.abs(cf.LookVector.Y) * size.Z * 0.5

	return part.Position.Y - halfWorldHeight
end

local function getVisibleBodyBottomY(character: Model): number?
	local lowest = math.huge
	local found = false

	for _, partName in ipairs(R6_VISIBLE_PARTS) do
		local part = character:FindFirstChild(partName)

		if part and part:IsA("BasePart") then
			lowest = math.min(lowest, getPartBottomY(part))
			found = true
		end
	end

	if not found then
		return nil
	end

	return lowest
end


local function fitExecutionPairToGround(
	attackerCharacter: Model,
	attackerRoot: BasePart,
	targetCharacter: Model,
	targetRoot: BasePart
)
	local attackerBottom = getVisibleBodyBottomY(attackerCharacter)
	local targetBottom = getVisibleBodyBottomY(targetCharacter)

	if not attackerBottom or not targetBottom then
		return
	end

	local params = makeGroundRaycastParams(nil)
	local result = workspace:Raycast(
		targetRoot.Position + Vector3.new(0, EXECUTION_GROUND_RAY_UP, 0),
		Vector3.new(0, -EXECUTION_GROUND_RAY_DOWN, 0),
		params
	)

	if not result then
		return
	end

	local pairBottom = math.min(attackerBottom, targetBottom)
	local desiredBottom = result.Position.Y + FLOOR_CLEARANCE
	local yOffset = desiredBottom - pairBottom

	if math.abs(yOffset) < 0.005 then
		return
	end

	yOffset = math.clamp(
		yOffset,
		-EXECUTION_GROUND_FIT_MAX_STEP,
		EXECUTION_GROUND_FIT_MAX_STEP
	)

	local correction = Vector3.new(0, yOffset, 0)
	attackerRoot.CFrame = attackerRoot.CFrame + correction
	targetRoot.CFrame = targetRoot.CFrame + correction

	zeroRootVelocity(attackerRoot)
	zeroRootVelocity(targetRoot)
end

local function applyDownedIdleGroundCorrection(player: Player)
	local character, humanoid, root = getCharacterPieces(player)
	local info = downedInfo[player]

	if not character or not humanoid or not root or not info then
		return
	end

	if info.state ~= "Downed"
		or info.carriedBy
		or info.airborne
		or info.recovering
		or info.idleOffsetApplied then
		return
	end

	local bottomY = getVisibleBodyBottomY(character)

	if not bottomY then
		return
	end

	local params = makeGroundRaycastParams(character)

	local result = workspace:Raycast(
		root.Position + Vector3.new(0, 6, 0),
		Vector3.new(0, -24, 0),
		params
	)

	if not result then
		return
	end

	local desiredBottomY = result.Position.Y + FLOOR_CLEARANCE
	local yOffset = desiredBottomY - bottomY

	yOffset = math.clamp(
		yOffset,
		-MAX_IDLE_GROUND_CORRECTION,
		MAX_IDLE_GROUND_CORRECTION
	)

	root.Anchored = true
	zeroRootVelocity(root)
	root.CFrame = root.CFrame + Vector3.new(0, yOffset, 0)

	info.idleRootYOffset = yOffset
	info.idleOffsetApplied = true
end

local function clearRecoveryTween(info: DownedInfo)
	if info.recoveryTween then
		info.recoveryTween:Cancel()
		info.recoveryTween = nil
	end
end

-- =========================
-- RECOVERY TIMER
-- =========================

local function cancelRecovery(info: DownedInfo)
	if info.recoveryTask then
		task.cancel(info.recoveryTask)
		info.recoveryTask = nil
	end
end

local function scheduleRecovery(player: Player)
	local info = downedInfo[player]

	if not info
		or info.state ~= "Downed"
		or info.carriedBy
		or info.airborne then
		return
	end

	cancelRecovery(info)

	local scheduledCycleId = info.cycleId
	local remaining = math.max(0, info.recoveryDeadline - time())

	info.recoveryTask = task.delay(
		remaining,
		function()
			local current = downedInfo[player]

			if not player.Parent
				or not current
				or current.cycleId ~= scheduledCycleId
				or current.state ~= "Downed"
				or current.carriedBy
				or current.airborne then
				return
			end

			current.recoveryTask = nil
			startRecovery(player)
		end
	)
end

-- =========================
-- AIRBORNE DROP
-- =========================

local function setDownedAirborne(
	player: Player,
	value: boolean
)
	local info = downedInfo[player]
	local character = player.Character

	if info then
		info.airborne = value
	end

	if character then
		character:SetAttribute("IsDownedAirborne", value)
	end
end

local function finishAirborneDrop(player: Player)
	local info = downedInfo[player]
	local character, humanoid, root = getCharacterPieces(player)

	if not info
		or not character
		or not humanoid
		or not root
		or info.state ~= "Downed"
		or not info.airborne
		or info.carriedBy
		or info.recovering then
		return
	end

	-- Freeze only after the visible body has actually reached the floor.
	makeRootWorldUpright(root)
	liftCharacterOutOfGround(character)
	zeroRootVelocity(root)

	-- Return the character to automatic ownership before anchoring so that,
	-- after a later Recovery unanchors it, Roblox can give ownership back to
	-- the player normally.
	pcall(function()
		root:SetNetworkOwnershipAuto()
	end)

	root.Anchored = true

	info.idleOffsetApplied = false
	info.idleRootYOffset = 0
	setDownedAirborne(player, false)

	downedStateEvent:FireAllClients(
		player,
		"Landed"
	)

	-- The deadline keeps counting while falling. If it expired in the air,
	-- Recovery begins now that the player is safely back on the ground.
	scheduleRecovery(player)

	print("[Downed-Server] airborne drop landed", player.Name)
end

local function beginAirborneDrop(
	player: Player,
	carrierRoot: BasePart?
)
	local info = downedInfo[player]
	local character, humanoid, root = getCharacterPieces(player)

	if not info
		or not character
		or not humanoid
		or not root
		or info.state ~= "Downed"
		or info.carriedBy
		or info.recovering then
		return
	end

	cancelRecovery(info)
	clearRecoveryTween(info)
	info.idleOffsetApplied = false
	info.idleRootYOffset = 0
	setDownedAirborne(player, true)

	root.Anchored = false
	makeRootWorldUpright(root)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	disableDownedPhysicsStates(humanoid)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Move only a small amount forward so restored body collisions do not
	-- immediately overlap the carrier. The current world height is preserved.
	if carrierRoot and DROP_FORWARD_NUDGE > 0 then
		local flatLook = Vector3.new(
			carrierRoot.CFrame.LookVector.X,
			0,
			carrierRoot.CFrame.LookVector.Z
		)

		if flatLook.Magnitude > 0.01 then
			root.CFrame = root.CFrame + flatLook.Unit * DROP_FORWARD_NUDGE
		end
	end

	-- Inherit a limited amount of carrier momentum. This feels natural when
	-- dropped during a jump without allowing Sprint to launch the victim.
	local inherited =
		if carrierRoot
		then carrierRoot.AssemblyLinearVelocity
		else Vector3.zero

	local horizontal = Vector3.new(inherited.X, 0, inherited.Z)

	if horizontal.Magnitude > DROP_MAX_HORIZONTAL_SPEED then
		horizontal = horizontal.Unit * DROP_MAX_HORIZONTAL_SPEED
	end

	-- Anti-hover / anti-exploit rule: a dropped Downed player starts falling
	-- immediately, even if the Carrier is still moving upward from Jump or
	-- Double Jump. Downward momentum is preserved if it is already faster.
	local vertical = math.min(
		inherited.Y,
		-DROP_INITIAL_FALL_SPEED
	)

	root.AssemblyLinearVelocity = Vector3.new(
		horizontal.X,
		vertical,
		horizontal.Z
	)
	root.AssemblyAngularVelocity = Vector3.zero

	-- Server ownership makes the fall authoritative and prevents a client from
	-- intentionally freezing a Downed character in mid-air.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local airborneStartedAt = time()

	task.spawn(function()
		while player.Parent do
			RunService.Heartbeat:Wait()

			local current = downedInfo[player]
			local currentCharacter, currentHumanoid, currentRoot =
				getCharacterPieces(player)

			if not current
				or not currentCharacter
				or not currentHumanoid
				or not currentRoot
				or current.state ~= "Downed"
				or not current.airborne
				or current.carriedBy
				or current.recovering then
				return
			end

			-- A Downed airborne assembly is never allowed to become anchored again
			-- before a real floor hit. This also protects against other movement
			-- systems accidentally re-anchoring the HRP for a frame.
			if currentRoot.Anchored then
				currentRoot.Anchored = false
			end

			pcall(function()
				currentRoot:SetNetworkOwner(nil)
			end)

			local params = makeGroundRaycastParams(currentCharacter)

			local result = workspace:Raycast(
				currentRoot.Position + Vector3.new(0, 4, 0),
				Vector3.new(0, -AIRBORNE_GROUND_RAY_LENGTH, 0),
				params
			)

			local landed = false

			if result then
				local bodyBottomY = getVisibleBodyBottomY(currentCharacter)

				if bodyBottomY then
					local distanceToGround = bodyBottomY - result.Position.Y
					local verticalSpeed = currentRoot.AssemblyLinearVelocity.Y

					if distanceToGround <= AIRBORNE_LANDING_TOLERANCE
						and verticalSpeed <= AIRBORNE_LANDING_MAX_UPWARD_SPEED then
						landed = true
					end
				end
			end

			if landed then
				finishAirborneDrop(player)
				return
			end

			-- Watchdog: gravity should already be accelerating the assembly. If a
			-- movement script/client zeroes the Y velocity, force a minimum fall
			-- speed instead of allowing the Downed player to hover.
			if time() - airborneStartedAt >= AIRBORNE_STUCK_GRACE then
				local velocity = currentRoot.AssemblyLinearVelocity

				if velocity.Y > -AIRBORNE_MIN_FALL_SPEED then
					currentRoot.AssemblyLinearVelocity = Vector3.new(
						velocity.X,
						-AIRBORNE_MIN_FALL_SPEED,
						velocity.Z
					)
				end
			end
		end
	end)
end

-- =========================
-- TARGETING / REQUEST VALIDATION
-- =========================

local function findNearestDownedInRange(
	requester: Player,
	range: number
): (Player?, Model?)
	local requesterCharacter, requesterHumanoid, requesterRoot =
		getCharacterPieces(requester)

	if not requesterCharacter
		or not requesterHumanoid
		or not requesterRoot
		or requesterHumanoid.Health <= 0 then
		return nil, nil
	end

	local bestPlayer: Player? = nil
	local bestCharacter: Model? = nil
	local bestDistance = math.huge

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == requester then
			continue
		end

		local targetInfo = downedInfo[targetPlayer]

		if not targetInfo
			or targetInfo.state ~= "Downed"
			or targetInfo.carriedBy
			or targetInfo.airborne
			or targetInfo.recovering then
			continue
		end

		local targetCharacter, targetHumanoid, targetRoot =
			getCharacterPieces(targetPlayer)

		if not targetCharacter
			or not targetHumanoid
			or not targetRoot
			or targetHumanoid.Health <= 0
			or targetCharacter:GetAttribute("IsBeingExecuted") == true then
			continue
		end

		local distance =
			(targetRoot.Position - requesterRoot.Position).Magnitude

		if distance <= range and distance < bestDistance then
			bestDistance = distance
			bestPlayer = targetPlayer
			bestCharacter = targetCharacter
		end
	end

	return bestPlayer, bestCharacter
end

local function canStartInteraction(player: Player): boolean
	local character, humanoid, root =
		getCharacterPieces(player)

	if not character
		or not humanoid
		or not root
		or humanoid.Health <= 0 then
		return false
	end

	local state =
		humanoid:GetState()

	-- Jumping is always a real action lock.
	if state ==
		Enum.HumanoidStateType.Jumping then

		return false
	end

	if state ==
		Enum.HumanoidStateType.Swimming then

		return false
	end

	-- Freefall alone is NOT sufficient evidence that the player is airborne.
	-- R6 can retain this state briefly while already standing on the ground.
	if state ==
		Enum.HumanoidStateType.Freefall
		and not isPhysicallyGroundedForInteraction(
			character,
			humanoid,
			root
		) then

		return false
	end

	local info = getInfo(player)

	if info.state ~= "Normal" then
		return false
	end

	if character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsStunned") == true
		or character:GetAttribute("IsDashing") == true
		or character:GetAttribute("IsAttacking") == true
		or character:GetAttribute("IsBlocking") == true
		or character:GetAttribute("IsSprinting") == true
		or character:GetAttribute("TreeJumpActive") == true
		or character:GetAttribute("IsTreeJumping") == true
		or character:GetAttribute("SurfaceJumping") == true then
		return false
	end

	return true
end

-- =========================
-- DOWNED / RECOVER
-- =========================

local function enterDowned(player: Player)
	local character, humanoid, root = getCharacterPieces(player)

	if not character or not humanoid then
		return
	end

	-- A character that has already committed an Execute death must never be
	-- intercepted back into Downed while its old body is waiting to despawn.
	if character:GetAttribute("ExecutionFinalized") == true then
		return
	end

	local info = getInfo(player)

	if info.state == "Downed" or info.state == "Executed" then
		if humanoid.Health <= 0
			and allowFinalDeath[player] ~= true then
			humanoid.Health = 1
		end

		return
	end

	if info.carrying then
		detachCarry(player)
	end

	saveHumanoidState(humanoid, info)

	-- Reserve the Downed HP before publishing the state.
	humanoid.Health = math.clamp(
		DOWNED_HEALTH,
		1,
		humanoid.MaxHealth
	)

	-- Every Downed entry gets a unique generation. Any delayed timer or client
	-- callback from an older Downed must carry the old id and is ignored.
	info.cycleId += 1

	info.state = "Downed"
	info.recovering = false
	info.airborne = false
	info.idleOffsetApplied = false
	info.idleRootYOffset = 0
	clearRecoveryTween(info)
	character:SetAttribute("IsRecovering", false)
	character:SetAttribute("IsDownedAirborne", false)

	info.downedAt = time()
	info.recoveryDeadline = info.downedAt + DOWNED_TIME
	info.carriedBy = nil

	setDownedAttributes(character, true, false)
	putHumanoidIntoDownedState(character, humanoid, root)

	downedStateEvent:FireAllClients(player, "Downed")

	print("[Downed-Server] enter", player.Name)

	scheduleRecovery(player)
end

startRecovery = function(player: Player)
	local character, humanoid, root = getCharacterPieces(player)

	if not character or not humanoid or not root then
		return
	end

	local info = getInfo(player)

	if info.state ~= "Downed"
		or info.carriedBy
		or info.airborne
		or info.recovering then
		return
	end

	cancelRecovery(info)
	info.recovering = true
	character:SetAttribute("IsRecovering", true)

	root.Anchored = true
	zeroRootVelocity(root)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	disableDownedPhysicsStates(humanoid)

	local recoveryCycleId = info.cycleId

	downedStateEvent:FireClient(
		player,
		player,
		"RecoveryStart",
		recoveryCycleId
	)

	task.delay(RECOVERY_FINISH_FALLBACK, function()
		local current = downedInfo[player]

		if current
			and current.cycleId == recoveryCycleId
			and current.state == "Downed"
			and current.recovering then
			warn(
				"[Downed-Server] Recovery fallback finish",
				player.Name,
				"cycle",
				recoveryCycleId
			)

			recoverPlayer(player)
		end
	end)
end

recoverPlayer = function(player: Player)
	local character, humanoid, root = getCharacterPieces(player)

	if not character or not humanoid then
		return
	end

	local info = getInfo(player)

	if info.state ~= "Downed"
		or info.carriedBy
		or info.airborne then
		return
	end

	cancelRecovery(info)
	clearRecoveryTween(info)
	restoreCarryPhysics(info)
	removeCarryWeld(character)

	info.recovering = false
	info.airborne = false
	info.idleOffsetApplied = false
	character:SetAttribute("IsRecovering", false)
	character:SetAttribute("IsDownedAirborne", false)

	info.state = "Normal"
	info.carriedBy = nil
	info.downedAt = 0
	info.recoveryDeadline = 0

	setDownedAttributes(character, false, false)

	-- Recovery always starts at the configured amount. The Downed health lock
	-- is already released because state is Normal before this assignment.
	humanoid.Health = math.clamp(
		RECOVERY_HEALTH,
		1,
		humanoid.MaxHealth
	)

	restoreHumanoidAfterDowned(
		character,
		humanoid,
		root,
		info
	)

	info.idleRootYOffset = 0

	downedStateEvent:FireAllClients(player, "Recovered")

	print(
		"[Downed-Server] recovered",
		player.Name,
		"hp",
		humanoid.Health
	)
end

-- =========================
-- CARRY
-- =========================

local function attachCarry(carrier: Player, target: Player)
	local carrierCharacter, carrierHumanoid, carrierRoot =
		getCharacterPieces(carrier)

	local targetCharacter, targetHumanoid, targetRoot =
		getCharacterPieces(target)

	local carrierTorso =
		carrierCharacter
		and carrierCharacter:FindFirstChild("Torso") :: BasePart?

	if not carrierCharacter
		or not carrierHumanoid
		or not carrierRoot
		or not carrierTorso
		or not targetCharacter
		or not targetHumanoid
		or not targetRoot then
		return
	end

	local carrierInfo = getInfo(carrier)
	local targetInfo = getInfo(target)

	if carrierInfo.state ~= "Normal"
		or carrierInfo.carrying
		or targetInfo.state ~= "Downed"
		or targetInfo.carriedBy
		or targetInfo.airborne
		or targetInfo.recovering then
		return
	end

	if not canStartInteraction(carrier) then
		return
	end

	if (carrierRoot.Position - targetRoot.Position).Magnitude >
		CARRY_RANGE + 1 then
		return
	end

	cancelRecovery(targetInfo)
	clearRecoveryTween(targetInfo)
	targetInfo.recovering = false
	targetInfo.airborne = false
	targetInfo.idleOffsetApplied = false
	targetInfo.idleRootYOffset = 0
	targetCharacter:SetAttribute("IsRecovering", false)
	targetCharacter:SetAttribute("IsDownedAirborne", false)

	targetInfo.carriedBy = carrier
	carrierInfo.carrying = target

	targetCharacter:SetAttribute("IsCarried", true)
	updateActionLocked(targetCharacter)
	carrierCharacter:SetAttribute("IsCarrying", true)

	saveAndDisableCarryPhysics(targetCharacter, targetInfo)

	targetHumanoid.Sit = false
	targetRoot.Anchored = false
	targetHumanoid.PlatformStand = false
	targetHumanoid.AutoRotate = false
	targetHumanoid.WalkSpeed = 0
	disableDownedPhysicsStates(targetHumanoid)

	-- Stable v31 CarryWeld baseline:
	-- victim parts are non-collidable + massless and become part of the
	-- carrier's physical assembly through CarryWeld.

	if targetHumanoid.UseJumpPower then
		targetHumanoid.JumpPower = 0
	else
		targetHumanoid.JumpHeight = 0
	end

	createCarryWeld(
		carrierTorso,
		targetCharacter,
		targetRoot
	)

	-- Combat Tag:
	-- Carrying someone OR being carried puts both players in combat.
	CombatTagService.Tag(
		target,
		carrier
	)

	CombatTagService.Tag(
		carrier,
		target
	)

	downedStateEvent:FireAllClients(
		target,
		"Carried",
		carrier
	)

	downedStateEvent:FireAllClients(
		carrier,
		"Carrying",
		target
	)

	print(
		"[Downed-Server] carry",
		carrier.Name,
		"carrying",
		target.Name
	)
end

detachCarry = function(
	carrier: Player,
	dropPosition: Vector3?
)
	local carrierInfo = downedInfo[carrier]

	if not carrierInfo or not carrierInfo.carrying then
		return
	end

	local target = carrierInfo.carrying
	local targetInfo = downedInfo[target]

	local carrierCharacter = carrier.Character
	local targetCharacter = target.Character

	local carrierRoot =
		carrierCharacter
		and carrierCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	carrierInfo.carrying = nil

	if targetInfo then
		targetInfo.carriedBy = nil
	end

	if carrierCharacter then
		carrierCharacter:SetAttribute("IsCarrying", false)
	end

	if targetCharacter then
		removeCarryWeld(targetCharacter)

		local targetHumanoid =
			targetCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?

		local targetRoot =
			targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

		-- Publish Airborne BEFORE clearing IsCarried. The client therefore
		-- keeps the CarryVictim pose during the fall instead of starting the
		-- grounded Downed Idle while still in the air.
		if targetInfo and targetInfo.state == "Downed" then
			targetInfo.recovering = false
			targetInfo.idleOffsetApplied = false
			targetInfo.idleRootYOffset = 0
			setDownedAirborne(target, true)
			targetCharacter:SetAttribute("IsRecovering", false)
		end

		if targetInfo then
			restoreCarryPhysics(targetInfo)
		end

		targetCharacter:SetAttribute("IsCarried", false)
		updateActionLocked(targetCharacter)

		if targetHumanoid then
			targetHumanoid.Sit = false
			targetHumanoid.PlatformStand = false
			targetHumanoid.AutoRotate = false
			targetHumanoid.WalkSpeed = 0
			disableDownedPhysicsStates(targetHumanoid)

			if targetHumanoid.UseJumpPower then
				targetHumanoid.JumpPower = 0
			else
				targetHumanoid.JumpHeight = 0
			end
		end

		if targetRoot then
			-- An explicit dropPosition, if ever supplied by another system, only
			-- changes X/Z. We preserve the carried player's current world height.
			if dropPosition then
				targetRoot.CFrame = CFrame.new(
					Vector3.new(
						dropPosition.X,
						targetRoot.Position.Y,
						dropPosition.Z
					)
				)
			end

			targetRoot.Anchored = false
		end

		downedStateEvent:FireAllClients(
			target,
			"Dropped",
			carrier
		)

		if targetInfo and targetInfo.state == "Downed" then
			-- Releasing a carried Downed player still restarts the full Downed
			-- timer. It continues counting while the body is falling, but Recovery
			-- cannot actually begin until the body has landed.
			targetInfo.downedAt = time()
			targetInfo.recoveryDeadline =
				targetInfo.downedAt + DOWNED_TIME

			beginAirborneDrop(target, carrierRoot)
		end
	end

	print(
		"[Downed-Server] drop",
		carrier.Name,
		"dropped",
		target.Name
	)
end

-- =========================
-- EXECUTION
-- =========================

local function disableExecutionVictimHitbox(
	player: Player,
	character: Model
)
	-- Save exact per-part state so a cancelled Execute restores the Downed
	-- character exactly as it was before the cinematic began.
	local saved: {[BasePart]: ExecutionVictimPartState} = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			saved[descendant] = {
				canCollide = descendant.CanCollide,
				canTouch = descendant.CanTouch,
				canQuery = descendant.CanQuery,
			}

			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	executionVictimPhysics[player] = saved
	character:SetAttribute("IsBeingExecuted", true)
end

local function restoreExecutionVictimHitbox(
	player: Player,
	character: Model?
)
	local saved = executionVictimPhysics[player]
	executionVictimPhysics[player] = nil

	if saved then
		for part, state in pairs(saved) do
			if part.Parent then
				part.CanCollide = state.canCollide
				part.CanTouch = state.canTouch
				part.CanQuery = state.canQuery
			end
		end
	end

	if character and character.Parent then
		character:SetAttribute("IsBeingExecuted", false)
	end
end

local function requestExecutionCancel(player: Player)
	if executionTarget[player]
		and executing[player] == true then
		executionCancelRequested[player] = true
	end
end

local function snapshotExecution(
	humanoid: Humanoid,
	root: BasePart
): ExecutionSnapshot
	return {
		walkSpeed = humanoid.WalkSpeed,
		rootAnchored = root.Anchored,
		useJumpPower = humanoid.UseJumpPower,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
	}
end

local function lockExecutionHumanoid(
	humanoid: Humanoid,
	root: BasePart?
)
	humanoid.Sit = false
	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	humanoid.AutoRotate = false

	if root then
		root.Anchored = true
	end

	zeroRootVelocity(root)
end

local function restoreExecutionHumanoid(
	humanoid: Humanoid?,
	root: BasePart?,
	snapshot: ExecutionSnapshot?
)
	if not humanoid
		or not humanoid.Parent
		or not snapshot
		or humanoid.Health <= 0 then
		return
	end

	if root and root.Parent then
		root.Anchored = snapshot.rootAnchored
		zeroRootVelocity(root)
	end

	humanoid.PlatformStand = snapshot.platformStand
	humanoid.AutoRotate = snapshot.autoRotate
	humanoid.WalkSpeed = snapshot.walkSpeed
	humanoid.UseJumpPower = snapshot.useJumpPower
	humanoid.JumpPower = snapshot.jumpPower
	humanoid.JumpHeight = snapshot.jumpHeight
end

local function finalKill(
	player: Player,
	attacker: Player?
)
	local character, humanoid, root = getCharacterPieces(player)

	if not character or not humanoid or not root then
		return
	end

	local info = getInfo(player)

	cancelRecovery(info)
	clearRecoveryTween(info)
	info.recovering = false
	info.idleRootYOffset = 0
	character:SetAttribute("IsRecovering", false)
	restoreCarryPhysics(info)
	removeCarryWeld(character)

	-- Publish a permanent guard on this old character before Health reaches 0.
	-- This survives Humanoid.Died cleanup and prevents any late HealthChanged
	-- callback from creating a fresh Downed cycle and replaying Downing.
	character:SetAttribute("ExecutionFinalized", true)

	info.state = "Executed"
	info.airborne = false
	info.carriedBy = nil

	-- The victim is no longer logically Downed after the lethal impact.
	-- IsExecuting remains true, so controls stay locked through the authored Execute even after the visible body poofs.
	setDownedAttributes(character, false, false)

	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	if character:GetAttribute("IsExecuting") ~= true then
		liftCharacterOutOfGround(character)
	end

	root.Anchored = true
	zeroRootVelocity(root)

	allowFinalDeath[player] = true

	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Dead,
		true
	)

	downedStateEvent:FireAllClients(
		player,
		"Executed",
		attacker
	)

	humanoid.Health = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Dead)

	task.defer(function()
		if character.Parent and root.Parent then
			root.Anchored = true
			zeroRootVelocity(root)

			if character:GetAttribute("IsExecuting") ~= true then
				liftCharacterOutOfGround(character)
			end
		end
	end)
end


local function createExecutionPoofFx(cframe: CFrame)
	-- FX lives outside the character so it can finish even if Roblox despawns the
	-- old character while the particles/sound are still fading.
	local fxPart = Instance.new("Part")
	fxPart.Name = "ExecutePoofFX"
	fxPart.Size = Vector3.new(0.2, 0.2, 0.2)
	fxPart.Transparency = 1
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanTouch = false
	fxPart.CanQuery = false
	fxPart.CastShadow = false
	fxPart.CFrame = cframe
	fxPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.Name = "ExecutePoof"
	sound.SoundId = EXECUTION_POOF_SOUND_ID
	sound.Volume = EXECUTION_POOF_VOLUME
	sound.RollOffMaxDistance = 70
	sound.Parent = fxPart

	local attachment = Instance.new("Attachment")
	attachment.Name = "ExecutePoofAttachment"
	attachment.Parent = fxPart

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ExecutePoofSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 0
	smoke.Lifetime = NumberRange.new(0.40, 0.70)
	smoke.Speed = NumberRange.new(5, 10)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rotation = NumberRange.new(-180, 180)
	smoke.RotSpeed = NumberRange.new(-90, 90)
	smoke.Drag = 3
	smoke.LightInfluence = 0.25
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 245, 245)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 175, 175)),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(0.35, 3.1),
		NumberSequenceKeypoint.new(1, 4.4),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.45, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = attachment

	sound:Play()
	smoke:Emit(EXECUTION_POOF_PARTICLE_COUNT)

	Debris:AddItem(fxPart, 2.5)
end

local function poofExecutedCharacter(character: Model)
	if not character.Parent
		or character:GetAttribute("ExecutedPoofed") == true then
		return
	end

	character:SetAttribute("ExecutedPoofed", true)

	local torso = character:FindFirstChild("Torso") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local fxCFrame = if torso then torso.CFrame
		elseif root then root.CFrame
		else character:GetPivot()

	-- Remove the body physically/visually, but do not destroy Character. Roblox
	-- can finish its normal death/respawn lifecycle without us forcing a respawn.
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		elseif descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = false
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end

	if root and root.Parent then
		root.Anchored = true
		zeroRootVelocity(root)
	end

	-- Ask every client to render the burst locally. This is reliable during the
	-- death/respawn lifecycle, unlike relying on a server :Emit() burst.
	if executionPoofFX then
		executionPoofFX:FireAllClients(fxCFrame)
	end
end

local function executionIsStillValid(
	attacker: Player,
	target: Player,
	attackerHumanoid: Humanoid,
	attackerRoot: BasePart,
	targetHumanoid: Humanoid,
	targetRoot: BasePart,
	targetInfo: DownedInfo
): boolean
	if executionCancelRequested[attacker] == true then
		return false
	end

	local attackerInfo = getInfo(attacker)

	if attackerInfo.state ~= "Normal" then
		return false
	end

	if attacker.Parent == nil
		or target.Parent == nil
		or attackerHumanoid.Parent == nil
		or attackerHumanoid.Health <= 0
		or targetHumanoid.Parent == nil
		or targetHumanoid.Health <= 0
		or targetInfo.state ~= "Downed"
		or targetInfo.carriedBy ~= nil
		or targetInfo.airborne
		or targetInfo.recovering then
		return false
	end

	return (attackerRoot.Position - targetRoot.Position).Magnitude
		<= EXECUTION_RANGE + 3
end

local function clearExecutionSync(attacker: Player)
	executionTarget[attacker] = nil
	executionStartedAt[attacker] = nil
	executionMarkerReceived[attacker] = nil
	executionCancelRequested[attacker] = nil
end

local function executePlayer(
	attacker: Player,
	target: Player
)
	if executing[attacker] or executing[target] then
		return
	end

	if not canStartInteraction(attacker) then
		return
	end

	local attackerCharacter, attackerHumanoid, attackerRoot =
		getCharacterPieces(attacker)

	local targetCharacter, targetHumanoid, targetRoot =
		getCharacterPieces(target)

	if not attackerCharacter
		or not attackerHumanoid
		or not attackerRoot
		or not targetCharacter
		or not targetHumanoid
		or not targetRoot then
		return
	end

	local attackerInfo = getInfo(attacker)
	local targetInfo = getInfo(target)

	if attackerInfo.state ~= "Normal"
		or attackerInfo.carrying
		or targetInfo.state ~= "Downed"
		or targetInfo.carriedBy
		or targetInfo.airborne
		or targetInfo.recovering then
		return
	end

	if (attackerRoot.Position - targetRoot.Position).Magnitude >
		EXECUTION_RANGE + 1 then
		return
	end

	executing[attacker] = true
	executing[target] = true
	executionCancelRequested[attacker] = false

	setExecuting(attackerCharacter, true)
	setExecuting(targetCharacter, true)
	disableExecutionVictimHitbox(target, targetCharacter)

	local attackerSnapshot = snapshotExecution(attackerHumanoid, attackerRoot)

	lockExecutionHumanoid(
		attackerHumanoid,
		attackerRoot
	)

	-- Keep the Downed victim exactly where the stable Downed system placed it.
	-- Snap the Executor to the authored Moon Animator relation, regardless of
	-- which side/direction the player approached from. Both roots are anchored
	-- for the cinematic so locomotion/physics cannot make the stomp miss.
	targetRoot.Anchored = true
	zeroRootVelocity(targetRoot)

	attackerRoot.CFrame =
		targetRoot.CFrame * EXECUTOR_RELATIVE_TO_VICTIM_CFRAME
	zeroRootVelocity(attackerRoot)

	cancelRecovery(targetInfo)

	local startedAt = time()
	executionTarget[attacker] = target
	executionStartedAt[attacker] = startedAt
	executionMarkerReceived[attacker] = false

	downedStateEvent:FireAllClients(
		attacker,
		"ExecuteStart",
		target
	)

	-- Animation transforms can move the visible R6 body relative to its anchored
	-- HumanoidRootPart. Ground BOTH characters together every frame so neither
	-- appears to float, while preserving the exact authored Executor/Victim offset.
	local executionGroundingActive = true

	task.spawn(function()
		RunService.Heartbeat:Wait()

		while executionGroundingActive
			and attackerCharacter.Parent
			and targetCharacter.Parent
			and attackerRoot.Parent
			and targetRoot.Parent
			and targetCharacter:GetAttribute("ExecutedPoofed") ~= true do

			fitExecutionPairToGround(
				attackerCharacter,
				attackerRoot,
				targetCharacter,
				targetRoot
			)

			RunService.Heartbeat:Wait()
		end
	end)

	print(
		"[Downed-Server] execute",
		attacker.Name,
		"->",
		target.Name
	)

	local hitCommitted = false
	local executionCancelled = false

	-- Wait for the authored frame-203 impact. Any damage attempt against the
	-- Executor before this point requests cancellation. The client marker may
	-- commit the lethal hit only inside the validated timing window; otherwise
	-- the server fallback commits shortly after frame 203.
	while true do
		local elapsed = time() - startedAt

		if not executionIsStillValid(
			attacker,
			target,
			attackerHumanoid,
			attackerRoot,
			targetHumanoid,
			targetRoot,
			targetInfo
			) then
			executionCancelled = true
			break
		end

		local markerReady =
			executionMarkerReceived[attacker] == true
			and elapsed >= EXECUTION_MARKER_EARLIEST
			and elapsed <= EXECUTION_MARKER_LATEST

		if markerReady or elapsed >= EXECUTION_HIT_FALLBACK then
			finalKill(target, attacker)
			hitCommitted = true
			break
		end

		RunService.Heartbeat:Wait()
	end

	if executionCancelled and not hitCommitted then
		executionGroundingActive = false
		restoreExecutionVictimHitbox(target, targetCharacter)

		if targetInfo.state == "Downed" then
			-- PvP rule v23:
			-- Every interrupted Execute gives the Downed victim a brand-new
			-- full DOWNED_TIME window. We intentionally DO NOT increment cycleId
			-- or call enterDowned(), so Downing does not replay and this remains
			-- the same physical Downed state; only the recovery clock resets.
			targetInfo.downedAt = time()
			targetInfo.recoveryDeadline =
				targetInfo.downedAt + DOWNED_TIME

			if not targetInfo.carriedBy
				and not targetInfo.airborne then
				scheduleRecovery(target)
			end
		end

		if attacker.Parent and target.Parent then
			downedStateEvent:FireAllClients(
				attacker,
				"ExecuteCancelled",
				target
			)
		end
	else
		-- With the 270-frame authoring, poof/hide is retimed to frame 245.
		-- The Executor then completes the final 25 frames before control returns
		-- at frame 270.
		local untilPoof = EXECUTION_POOF_TIME - (time() - startedAt)
		if untilPoof > 0 then
			task.wait(untilPoof)
		end

		if hitCommitted and targetCharacter.Parent then
			executionGroundingActive = false
			poofExecutedCharacter(targetCharacter)
			executionVictimPhysics[target] = nil
		end

		local untilFinish = EXECUTION_DURATION - (time() - startedAt)
		if untilFinish > 0 then
			task.wait(untilFinish)
		end
	end

	executionGroundingActive = false
	clearExecutionSync(attacker)
	executing[attacker] = nil
	executing[target] = nil

	if attackerCharacter.Parent then
		setExecuting(attackerCharacter, false)
	end

	if targetCharacter.Parent and targetHumanoid.Health > 0 then
		setExecuting(targetCharacter, false)
	end

	if getInfo(attacker).state == "Normal" then
		restoreExecutionHumanoid(
			attackerHumanoid,
			attackerRoot,
			attackerSnapshot
		)
	end

	if hitCommitted then
		print("[Downed-Server] executed", target.Name)
	else
		print(
			"[Downed-Server] execution interrupted",
			attacker.Name,
			"->",
			target.Name
		)
	end
end

-- =========================
-- REMOTES
-- =========================

executeRequest.OnServerEvent:Connect(function(player: Player)
	if executing[player] then
		return
	end

	local target = findNearestDownedInRange(
		player,
		EXECUTION_RANGE
	)

	if target then
		executePlayer(player, target)
	end
end)

carryRequest.OnServerEvent:Connect(function(player: Player)
	local info = getInfo(player)

	if info.carrying then
		detachCarry(player)
		return
	end

	if not canStartInteraction(player) then
		return
	end

	local target = findNearestDownedInRange(
		player,
		CARRY_RANGE
	)

	if target then
		attachCarry(player, target)
	end
end)

-- =========================
-- DOWNED ANIMATION SYNC
-- =========================


type PickupConstraintHold = {
	generation: number,
	root: BasePart,
	attachment: Attachment,
	position: AlignPosition,
	orientation: AlignOrientation,
}

local pickupConstraintHolds: {[Player]: PickupConstraintHold} = {}

-- CarryPickup plays with the carrier root held in world space so the authored
-- pickup can finish without moving the whole player. With full RootJoint
-- rotation restored, an R6 limb/torso can occasionally finish a few tenths of
-- a stud inside the floor. The Humanoid can still report Running and receive
-- MoveDirection, but the assembly is physically wedged until a jump lifts it.
--
-- This is NOT a CCL/state-machine workaround and does not touch the animation.
-- It runs only after the temporary pickup hold is released, and only lifts the
-- carrier by the exact penetration depth required to put the visible R6 body
-- above the real floor.
local function clearCarrierPickupGroundPenetration(
	player: Player,
	root: BasePart
)
	local character = player.Character

	if not character
		or not root.Parent
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true then

		return
	end

	local bottomY =
		getVisibleBodyBottomY(
			character
		)

	if not bottomY then
		return
	end

	local params =
		makeGroundRaycastParams(
			character
		)

	local result =
		workspace:Raycast(
			root.Position + Vector3.new(0, 6, 0),
			Vector3.new(0, -18, 0),
			params
		)

	if not result then
		return
	end

	local requiredBottomY =
		result.Position.Y + FLOOR_CLEARANCE

	local penetration =
		requiredBottomY - bottomY

	if penetration <= 0.005 then
		return
	end

	-- This is a clearance correction, not a launch. If something external has
	-- produced an absurd overlap, leave it visible for debugging rather than
	-- teleporting the carrier several studs.
	local correction =
		math.min(
			penetration,
			1.25
		)

	root.CFrame =
		root.CFrame
		+ Vector3.new(
			0,
			correction,
			0
		)

	zeroRootVelocity(
		root
	)

	print(
		"[Downed-Server v31.5] CarryPickup ground clearance",
		player.Name,
		"| Lift=",
		string.format("%.3f", correction),
		"| Penetration=",
		string.format("%.3f", penetration),
		"| Floor=",
		result.Material.Name
	)
end

local function sendPickupConstraintHoldAck(
	player: Player,
	phase: string,
	generation: number,
	ok: boolean
)
	animationSync:FireClient(
		player,
		"CarryPickupConstraintHoldAck",
		{
			phase = phase,
			generation = generation,
			ok = ok,
		}
	)
end

local function releaseServerPickupConstraintHold(
	player: Player,
	generation: number?,
	sendAck: boolean
): boolean
	local hold = pickupConstraintHolds[player]

	if not hold then
		if generation and sendAck then
			sendPickupConstraintHoldAck(
				player,
				"End",
				generation,
				true
			)
		end

		return true
	end

	if generation and hold.generation ~= generation then
		if sendAck then
			sendPickupConstraintHoldAck(
				player,
				"End",
				generation,
				false
			)
		end

		return false
	end

	pickupConstraintHolds[player] = nil

	if hold.position.Parent then
		hold.position:Destroy()
	end

	if hold.orientation.Parent then
		hold.orientation:Destroy()
	end

	if hold.attachment.Parent then
		hold.attachment:Destroy()
	end

	local root = hold.root

	-- Critical v31.3 invariant:
	-- pickup hold NEVER anchors the carrier HRP.
	if root.Parent and root.Anchored then
		warn(
			"[Downed-Server v31.5] unexpected anchored carrier during constraint release; forcing false",
			player.Name
		)
		root.Anchored = false
	end

	if root.Parent then
		clearCarrierPickupGroundPenetration(
			player,
			root
		)
	end

	print(
		"[Downed-Server v31.5] pickup constraint RELEASE",
		player.Name,
		"| Generation=",
		hold.generation,
		"| Anchored=",
		root.Parent and tostring(root.Anchored) or "destroyed"
	)

	if sendAck then
		sendPickupConstraintHoldAck(
			player,
			"End",
			hold.generation,
			true
		)
	end

	return true
end

local function beginServerPickupConstraintHold(
	player: Player,
	character: Model,
	root: BasePart,
	info: DownedInfo,
	generation: number
): boolean
	if info.state ~= "Normal"
		or info.carrying
		or executing[player] == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or root.Anchored then

		sendPickupConstraintHoldAck(
			player,
			"Start",
			generation,
			false
		)
		return false
	end

	releaseServerPickupConstraintHold(
		player,
		nil,
		false
	)

	zeroRootVelocity(root)

	local attachment = Instance.new("Attachment")
	attachment.Name = "CarryPickupHoldAttachment"
	attachment.CFrame = CFrame.identity
	attachment.Parent = root

	local position = Instance.new("AlignPosition")
	position.Name = "CarryPickupHoldPosition"
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.Position = root.Position
	position.ApplyAtCenterOfMass = true
	position.ReactionForceEnabled = false
	position.RigidityEnabled = true
	position.MaxForce = 1000000000
	position.MaxVelocity = 1000000
	position.Responsiveness = 200
	position.Parent = root

	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "CarryPickupHoldOrientation"
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.CFrame = root.CFrame.Rotation
	orientation.ReactionTorqueEnabled = false
	orientation.RigidityEnabled = true
	orientation.MaxTorque = 1000000000
	orientation.MaxAngularVelocity = 1000000
	orientation.Responsiveness = 200
	orientation.Parent = root

	local hold: PickupConstraintHold = {
		generation = generation,
		root = root,
		attachment = attachment,
		position = position,
		orientation = orientation,
	}

	pickupConstraintHolds[player] = hold

	-- Never anchor in this baseline.
	root.Anchored = false
	zeroRootVelocity(root)

	print(
		"[Downed-Server v31.5] pickup constraint HOLD",
		player.Name,
		"| Generation=",
		generation,
		"| Anchored=",
		root.Anchored,
		"| AssemblyRoot=",
		root.AssemblyRootPart
			and root.AssemblyRootPart:GetFullName()
			or "nil"
	)

	sendPickupConstraintHoldAck(
		player,
		"Start",
		generation,
		true
	)

	task.delay(3.25, function()
		local current = pickupConstraintHolds[player]

		if current
			and current.generation == generation then

			warn(
				"[Downed-Server v31.5] pickup constraint safety release",
				player.Name,
				"| Generation=",
				generation
			)

			releaseServerPickupConstraintHold(
				player,
				generation,
				true
			)
		end
	end)

	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	releaseServerPickupConstraintHold(
		player,
		nil,
		false
	)
end)

animationSync.OnServerEvent:Connect(function(
	player: Player,
	action: string,
	value: any
)
	local character, humanoid, root = getCharacterPieces(player)
	local info = downedInfo[player]

	if not character or not humanoid or not root or not info then
		return
	end

	if action == "CarryPickupConstraintHoldStart" then
		if typeof(value) ~= "table" then
			return
		end

		local generation = tonumber(value.generation)

		if not generation then
			return
		end

		beginServerPickupConstraintHold(
			player,
			character,
			root,
			info,
			generation
		)

		return
	end

	if action == "CarryPickupConstraintHoldEnd" then
		if typeof(value) ~= "table" then
			return
		end

		local generation = tonumber(value.generation)

		if not generation then
			return
		end

		releaseServerPickupConstraintHold(
			player,
			generation,
			true
		)

		return
	end

	if action == "ExecuteHit" then
		local target = executionTarget[player]
		local startedAt = executionStartedAt[player]

		if not target
			or not startedAt
			or executing[player] ~= true then
			return
		end

		local elapsed = time() - startedAt

		-- Never allow a client to move the lethal frame earlier than the authored
		-- animation. Late/spoofed markers are ignored and the server fallback wins.
		if elapsed >= EXECUTION_MARKER_EARLIEST
			and elapsed <= EXECUTION_MARKER_LATEST then
			executionMarkerReceived[player] = true
		end

		return
	end

	if action == "IdleStarted" then
		-- Let the replicated Animator apply the lying pose first, then measure
		-- the actual body against the floor instead of guessing an offset.
		local idleCycleId = info.cycleId

		task.delay(0.10, function()
			local current = downedInfo[player]

			if current
				and current.cycleId == idleCycleId
				and current.state == "Downed"
				and not current.recovering
				and not current.carriedBy then
				applyDownedIdleGroundCorrection(player)
			end
		end)

		return
	end

	if action == "RecoveryStarted" then
		if info.state ~= "Downed" or not info.recovering then
			return
		end

		if typeof(value) ~= "table" then
			return
		end

		local reportedCycleId = tonumber(value.cycleId)
		local duration = tonumber(value.duration) or 1

		if reportedCycleId ~= info.cycleId then
			return
		end

		duration = math.clamp(duration, 0.20, 3.50)

		clearRecoveryTween(info)
		disableDownedPhysicsStates(humanoid)

		if info.idleOffsetApplied
			and math.abs(info.idleRootYOffset) > 0.0001 then
			local target =
				root.CFrame
				+ Vector3.new(0, -info.idleRootYOffset, 0)

			info.recoveryTween = TweenService:Create(
				root,
				TweenInfo.new(
					duration,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut
				),
				{CFrame = target}
			)

			info.recoveryTween:Play()
		end

		return
	end

	if action == "RecoveryFinished" then
		local reportedCycleId = tonumber(value)

		if reportedCycleId == info.cycleId
			and info.state == "Downed"
			and info.recovering then
			recoverPlayer(player)
		end
	end
end)

-- =========================
-- PRE-LETHAL DAMAGE API
-- =========================

applyDamageFunction.OnInvoke = function(
	targetPlayer: Player,
	damage: number,
	attacker: Player?
): string
	if typeof(targetPlayer) ~= "Instance"
		or not targetPlayer:IsA("Player") then
		return "InvalidTarget"
	end

	if typeof(damage) ~= "number"
		or damage ~= damage
		or damage <= 0
		or damage == math.huge then
		return "InvalidDamage"
	end

	local character, humanoid, _ = getCharacterPieces(targetPlayer)

	if not character
		or not humanoid
		or humanoid.Health <= 0 then
		return "Dead"
	end

	-- PvP rule: ANY valid incoming damage attempt interrupts an Executor before
	-- lethal impact, regardless of attack type, as long as combat routes damage
	-- through this shared server gateway.
	if executionTarget[targetPlayer]
		and executing[targetPlayer] == true
		and character:GetAttribute("IsExecuting") == true
		and character:GetAttribute("ExecutionFinalized") ~= true then
		requestExecutionCancel(targetPlayer)
	end

	-- The Downed body currently inside an Execute is presentation-only and must
	-- not absorb M1s/projectiles/jutsus intended for the Executor. Physical
	-- query/touch/collision are also disabled for the duration of the Execute.
	if character:GetAttribute("IsBeingExecuted") == true then
		return "BeingExecuted"
	end

	if character:FindFirstChildOfClass("ForceField") then
		humanoid:TakeDamage(damage)
		return "ForceField"
	end

	-- Combat Tag:
	-- Landing a valid PvP hit tags ONLY the receiver.
	-- The attacker does not become tagged just for attacking.
	if attacker
		and typeof(attacker) == "Instance"
		and attacker:IsA("Player")
		and attacker ~= targetPlayer then

		CombatTagService.Tag(
			targetPlayer,
			attacker
		)
	end

	-- SUBSTITUTION / KAWARIMI:
	-- This lives in the shared damage gateway so M1, Kunai and every future
	-- jutsu/weapon that uses DownedInternal.ApplyDamage gets the same behavior.
	--
	-- Combat Tag is intentionally applied first: the attack connected with the
	-- defender's substitution window, so it still counts as PvP engagement.
	local substituted =
		trySubstitution:
		Invoke(
			targetPlayer,
			attacker
		)

	if substituted == true then
		return "Substituted"
	end

	local info = getInfo(targetPlayer)

	if info.state == "Downed"
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true then
		-- While Downed the value is fixed, not merely kept above a minimum.
		humanoid.Health = math.clamp(
			DOWNED_HEALTH,
			1,
			humanoid.MaxHealth
		)

		return "AlreadyDowned"
	end

	if info.state == "Executed"
		or allowFinalDeath[targetPlayer] == true then
		return "FinalDeath"
	end

	if damage >= humanoid.Health then
		enterDowned(targetPlayer)

		print(
			"[Downed-Server] pre-lethal intercept",
			targetPlayer.Name,
			"damage",
			damage,
			"attacker",
			attacker and attacker.Name or "nil"
		)

		return "Downed"
	end

	humanoid:TakeDamage(damage)
	return "Damaged"
end

-- =========================
-- HEALTH INTERCEPT / REGEN LOCK
-- =========================

local function initializeFreshDownedState(
	character: Model,
	humanoid: Humanoid,
	root: BasePart
)
	-- IMPORTANT:
	-- A newly spawned Character belongs to Roblox + the locomotion controllers.
	-- DownedServer must NOT normalize ordinary locomotion here.
	--
	-- Previous versions:
	--   * force-enabled Jumping / Freefall / Running / FallingDown / Ragdoll
	--   * zeroed HumanoidRootPart velocity
	--   * conditionally forced Running
	--
	-- That created an initialization race with SurfaceController, JumpController,
	-- DashController and Roblox's own Humanoid state machine. Depending on timing,
	-- a fresh life could remain in FallingDown or report FloorMaterial = Air while
	-- physically grounded.
	--
	-- A fresh Character does not inherit Anchored / PlatformStand / Sit / velocity
	-- from the dead Character, so none of that needs repairing here.
	--
	-- This function owns Downed-specific fresh-character state only.

	character:SetAttribute(
		"DownedActionLocked",
		false
	)

	character:SetAttribute(
		"IsDowned",
		false
	)

	character:SetAttribute(
		"IsCarried",
		false
	)

	character:SetAttribute(
		"IsCarrying",
		false
	)

	character:SetAttribute(
		"IsExecuting",
		false
	)

	character:SetAttribute(
		"IsBeingExecuted",
		false
	)

	character:SetAttribute(
		"IsRecovering",
		false
	)

	-- These are harmless default properties, but unlike Humanoid states they
	-- cannot fight the movement state machine. Only repair them if an external
	-- character template happened to spawn with a bad value.
	if root.Anchored then
		root.Anchored = false
	end

	if humanoid.PlatformStand then
		humanoid.PlatformStand = false
	end

	if humanoid.Sit then
		humanoid.Sit = false
	end

	humanoid.AutoRotate = true
end

local function hookCharacter(
	player: Player,
	character: Model
)
	CombatTagService.SyncCharacter(
		player,
		character
	)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	allowFinalDeath[player] = nil
	interceptingHealth[player] = nil

	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Dead,
		false
	)

	-- DB: no global trip-state policy at spawn.
	initializeFreshDownedState(character, humanoid, root)

	local healthConnection: RBXScriptConnection? = nil
	local lastObservedHealth = humanoid.Health

	healthConnection = humanoid.HealthChanged:Connect(
		function(newHealth: number)
			local previousHealth = lastObservedHealth
			lastObservedHealth = newHealth

			-- Fallback for legacy/direct Humanoid damage paths that bypass ApplyDamage.
			-- If the active Executor actually loses health before impact, cancel.
			if newHealth < previousHealth - 0.001
				and executionTarget[player]
				and executing[player] == true
				and character:GetAttribute("ExecutionFinalized") ~= true then
				requestExecutionCancel(player)
			end
			-- Execute death is terminal for this character instance. This character
			-- attribute survives even if Humanoid.Died clears the server tables.
			if character:GetAttribute("ExecutionFinalized") == true then
				return
			end

			if allowFinalDeath[player] == true then
				return
			end

			if interceptingHealth[player] then
				return
			end

			local info = getInfo(player)

			-- Downed HP is a hard lock. This prevents natural regeneration,
			-- external healing and normal extra damage from changing the value.
			if info.state == "Downed" then
				local lockedHealth = math.clamp(
					DOWNED_HEALTH,
					1,
					humanoid.MaxHealth
				)

				if math.abs(newHealth - lockedHealth) > 0.001 then
					interceptingHealth[player] = true
					humanoid.Health = lockedHealth
					interceptingHealth[player] = nil
				end

				return
			end

			if newHealth > 0 then
				return
			end

			interceptingHealth[player] = true

			if info.carrying then
				detachCarry(player)
			end

			warn(
				"[Downed-Server] external Health=0 fallback:",
				player.Name
			)

			humanoid.Health = math.clamp(
				DOWNED_HEALTH,
				1,
				humanoid.MaxHealth
			)

			enterDowned(player)
			interceptingHealth[player] = nil
		end
	)

	humanoid.Died:Connect(function()
		-- A real death/execution resolves this combat life-cycle.
		-- Do not carry victim-side tags onto the fresh character.
		CombatTagService.ClearAll(
			player,
			"Death"
		)

		local info = downedInfo[player]

		if info then
			if info.carrying then
				detachCarry(player)
			end

			if info.carriedBy then
				local carrier = info.carriedBy
				local carrierInfo = downedInfo[carrier]

				if carrierInfo
					and carrierInfo.carrying == player then
					carrierInfo.carrying = nil

					if carrier.Character then
						carrier.Character:SetAttribute(
							"IsCarrying",
							false
						)
					end
				end
			end

			cancelRecovery(info)
			clearRecoveryTween(info)
			restoreCarryPhysics(info)
		end

		removeCarryWeld(character)

		downedInfo[player] = nil
		executing[player] = nil
		executionVictimPhysics[player] = nil
		clearExecutionSync(player)
		allowFinalDeath[player] = nil
		interceptingHealth[player] = nil
	end)

	character.Destroying:Connect(function()
		if healthConnection then
			healthConnection:Disconnect()
		end
	end)

	zeroRootVelocity(root)
end

-- =========================
-- PLAYER LIFECYCLE
-- =========================

local function setupPlayer(player: Player)
	downedInfo[player] = makeDefaultInfo()

	player.CharacterAdded:Connect(function(character: Model)
		initializeCharacterAttributes(character)
		downedInfo[player] = makeDefaultInfo()
		hookCharacter(player, character)
	end)

	if player.Character then
		local character = player.Character
		initializeCharacterAttributes(character)
		downedInfo[player] = makeDefaultInfo()
		hookCharacter(player, character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local info = downedInfo[player]

	-- Remove any active stable CarryWeld before this player's character disappears.
	removeCarryWeld(player.Character)

	if info then
		if info.carrying then
			detachCarry(player)
		end

		if info.carriedBy then
			local carrier = info.carriedBy
			local carrierInfo = downedInfo[carrier]

			if carrierInfo and carrierInfo.carrying == player then
				carrierInfo.carrying = nil

				if carrier.Character then
					carrier.Character:SetAttribute(
						"IsCarrying",
						false
					)
				end
			end
		end

		cancelRecovery(info)
		clearRecoveryTween(info)
		restoreCarryPhysics(info)
	end

	downedInfo[player] = nil
	executing[player] = nil
	executionVictimPhysics[player] = nil
	clearExecutionSync(player)
	allowFinalDeath[player] = nil
	interceptingHealth[player] = nil
end)

print(
	"[Downed-Server] ready v31.5 DB_CCLCleanupOnly | GlobalNoTrip=REMOVED | CarryPickupGroundClearance=GEOMETRY_ONLY | StableCarry=ON | PickupRootHold=ALIGN_CONSTRAINT_NO_ANCHOR | VictimAssemblyVelocityWritesExpectedSuppressed=CLIENT_v42 | DOWNED_TIME="
		.. tostring(DOWNED_TIME)
		.. " RECOVERY_HEALTH="
		.. tostring(RECOVERY_HEALTH)
		.. " RESPAWN_DELAY="
		.. tostring(EXECUTION_RESPAWN_DELAY)
)
