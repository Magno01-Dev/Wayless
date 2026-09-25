--!strict
-- DownedController v43.2 - DB CCL Workaround Cleanup ONLY
-- StarterPlayer > StarterCharacterScripts > DownedController
--
-- Paired with DownedServer v31.3. Basic Execute is authored at 270 frames / 4.5 s; server validates frame 203 hit and poofs at frame 245.
-- Server owns the real state.
-- Integration attribute:
-- character:GetAttribute("DownedActionLocked")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local animator = humanoid:WaitForChild("Animator") :: Animator
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart


humanoid:SetStateEnabled(
	Enum.HumanoidStateType.Dead,
	false
)

-- ============================================================
-- DB: CCL WORKAROUND CLEANUP
-- ============================================================
-- Character Controller Library / AbilityManagerActor was the real source
-- of the abnormal animation-triggered FallingDown lock.
--
-- No global anti-trip policy remains here.
-- Downed still owns the states it actually needs while the player is Downed.

local remotes = ReplicatedStorage:WaitForChild("DownedRemotes")
local executeRequest = remotes:WaitForChild("ExecuteRequest") :: RemoteEvent
local carryRequest = remotes:WaitForChild("CarryRequest") :: RemoteEvent
local downedState = remotes:WaitForChild("DownedState") :: RemoteEvent
local animationSync = remotes:WaitForChild("DownedAnimationSync") :: RemoteEvent

local EXECUTE_KEY = Enum.KeyCode.B
local CARRY_KEY = Enum.KeyCode.V

-- Client-side preflight only. Server remains authoritative.
local CARRY_LOCAL_PREFLIGHT_RADIUS = 8

-- =========================
-- DOWNED ANIMATIONS
-- =========================

local DOWNING_ID = "rbxassetid://134525769140622"
local DOWNED_IDLE_ID = "rbxassetid://116059469572649"
local RECOVERY_ID = "rbxassetid://103894505538002"

-- R6 Carry animations.
local CARRY_VICTIM_ID = "rbxassetid://122326908728582"

-- One-shot pickup transition. The victim is attached exactly at CarryAttach.
local CARRY_PICKUP_ID = "rbxassetid://93710921081891"

local CARRY_CARRIER_ID = "rbxassetid://133865543713846"
local CARRY_CARRIER_RUN_ID = "rbxassetid://115409975941282"

-- Independent tuning values.
local DOWNING_ANIMATION_SPEED = 1.00
local DOWNED_IDLE_ANIMATION_SPEED = 1.00
local RECOVERY_ANIMATION_SPEED = 1.00
local CARRY_VICTIM_ANIMATION_SPEED = 1.00
local CARRY_PICKUP_ANIMATION_SPEED = 1.00
local CARRY_CARRIER_ANIMATION_SPEED = 1.00
local CARRY_CARRIER_RUN_ANIMATION_SPEED = 1.00

-- Basic unarmed Execute animations (R6).
local EXECUTE_ID = "rbxassetid://91747169766286"
local EXECUTED_ID = "rbxassetid://96138604942161"

-- Authored at 60 FPS. Both Execute animations are exactly 270 frames / 4.5 s.
-- The lethal impact is expected at frame 203 and the poof/hide at frame 245.
-- If the marker is missing, the server owns a validated frame-203 fallback.
local EXECUTE_ANIMATION_SPEED = 1.00
local EXECUTED_ANIMATION_SPEED = 1.00

local function loadTrack(
	id: string,
	name: string,
	looped: boolean,
	priority: Enum.AnimationPriority
): AnimationTrack
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id

	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped

	animation:Destroy()
	return track
end

local downingTrack: AnimationTrack? = nil
local downedIdleTrack: AnimationTrack? = nil
local recoveryTrack: AnimationTrack? = nil
local carryVictimTrack: AnimationTrack? = nil
local carryPickupTrack: AnimationTrack? = nil
local carryCarrierTrack: AnimationTrack? = nil
local carryCarrierRunTrack: AnimationTrack? = nil
local executeTrack: AnimationTrack? = nil
local executedTrack: AnimationTrack? = nil

pcall(function()
	downingTrack = loadTrack(
		DOWNING_ID,
		"Downing",
		false,
		Enum.AnimationPriority.Action4
	)
end)

pcall(function()
	downedIdleTrack = loadTrack(
		DOWNED_IDLE_ID,
		"DownedIdle",
		true,
		Enum.AnimationPriority.Action3
	)
end)

pcall(function()
	recoveryTrack = loadTrack(
		RECOVERY_ID,
		"Recovery",
		false,
		Enum.AnimationPriority.Action4
	)
end)

pcall(function()
	carryVictimTrack = loadTrack(
		CARRY_VICTIM_ID,
		"CarryVictim",
		true,
		Enum.AnimationPriority.Action4
	)
end)

pcall(function()
	carryPickupTrack = loadTrack(
		CARRY_PICKUP_ID,
		"CarryPickup",
		false,
		Enum.AnimationPriority.Action4
	)
end)

pcall(function()
	carryCarrierTrack = loadTrack(
		CARRY_CARRIER_ID,
		"CarryCarrier",
		true,
		Enum.AnimationPriority.Action3
	)
end)

pcall(function()
	carryCarrierRunTrack = loadTrack(
		CARRY_CARRIER_RUN_ID,
		"CarryCarrierRun",
		true,
		Enum.AnimationPriority.Action3
	)
end)

pcall(function()
	executeTrack = loadTrack(
		EXECUTE_ID,
		"Execute",
		false,
		Enum.AnimationPriority.Action4
	)
end)

pcall(function()
	executedTrack = loadTrack(
		EXECUTED_ID,
		"Executed",
		false,
		Enum.AnimationPriority.Action4
	)
end)

-- The marker should be authored into ExecuteExecutor at frame 203. This only
-- reports presentation timing; the server validates the active execution and timing.
if executeTrack then
	executeTrack:GetMarkerReachedSignal("ExecuteHit"):Connect(function()
		if character:GetAttribute("IsExecuting") == true
			and humanoid.Health > 0 then
			animationSync:FireServer("ExecuteHit")
		end
	end)
end

-- =========================
-- INDICATOR
-- =========================

local downedGui: BillboardGui? = nil

local function ensureIndicator()
	if downedGui and downedGui.Parent then
		return
	end

	local head = character:FindFirstChild("Head") :: BasePart?

	if not head then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "DownedIndicator"
	gui.Size = UDim2.fromOffset(100, 30)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "DOWNED"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 70, 70)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	gui.Parent = head
	downedGui = gui
end

local function removeIndicator()
	if downedGui then
		downedGui:Destroy()
		downedGui = nil
	end
end

local function stopTrack(track: AnimationTrack?)
	if track and track.IsPlaying then
		track:Stop(0.08)
	end
end

-- =========================
-- CARRY PICKUP
-- =========================

local CARRY_ATTACH_MARKER = "CarryAttach"

local carryPickupPending = false
local carryAttachRequested = false

-- Explicit ownership signal for other animation systems.
-- CustomAnimations must not interpret pickup-induced Freefall/Landed as a real
-- landing while Carry owns the full-body transition.
character:SetAttribute("CarryPickupActive", false)
local carryPickupGeneration = 0
local carryAttachConnection: RBXScriptConnection? = nil
local carryPickupCandidate: Model? = nil

-- The paired server holds the carrier root with temporary NON-ANCHORED Align constraints.
-- The real Carry remains the stable Torso-to-Victim CarryWeld.
local pickupRootHoldActive: boolean? = nil

local carriedOriginalEvaluateStateMachine: boolean? = nil

local function setCarriedHumanoidPhysicsDisabled(
	disabled: boolean
)
	if disabled then
		if carriedOriginalEvaluateStateMachine == nil then
			carriedOriginalEvaluateStateMachine =
				humanoid.EvaluateStateMachine
		end

		humanoid.EvaluateStateMachine = false
	else
		if carriedOriginalEvaluateStateMachine ~= nil then
			humanoid.EvaluateStateMachine =
				carriedOriginalEvaluateStateMachine

			carriedOriginalEvaluateStateMachine = nil
		end
	end
end

local PICKUP_ROOT_HOLD_ACK_TIMEOUT = 1.00
local pickupRootHoldAckGeneration = -1
local pickupRootHoldAckPhase = ""
local pickupRootHoldAckOk = false

animationSync.OnClientEvent:Connect(function(
	action: string,
	value: any
)
	if action ~= "CarryPickupConstraintHoldAck"
		or typeof(value) ~= "table" then
		return
	end

	local generation = tonumber(value.generation)
	local phase = tostring(value.phase or "")
	local ok = value.ok == true

	if not generation then
		return
	end

	pickupRootHoldAckGeneration = generation
	pickupRootHoldAckPhase = phase
	pickupRootHoldAckOk = ok

	print(
		"[Downed-Client v42] server pickup-root hold ACK",
		"| Phase=",
		phase,
		"| Generation=",
		generation,
		"| OK=",
		ok,
		"| Anchored=",
		rootPart.Anchored
	)
end)

local function resetPickupRootHoldAck()
	pickupRootHoldAckGeneration = -1
	pickupRootHoldAckPhase = ""
	pickupRootHoldAckOk = false
end

local function waitForPickupRootHoldAck(
	generation: number,
	phase: string
): boolean
	local deadline = time() + PICKUP_ROOT_HOLD_ACK_TIMEOUT

	while time() < deadline do
		if pickupRootHoldAckGeneration == generation
			and pickupRootHoldAckPhase == phase then

			return pickupRootHoldAckOk
		end

		RunService.Heartbeat:Wait()
	end

	return false
end


local function disconnectCarryAttachMarker()
	if carryAttachConnection then
		carryAttachConnection:Disconnect()
		carryAttachConnection = nil
	end
end


local function lockPickupRoot(): boolean
	if pickupRootHoldActive ~= nil then
		return true
	end

	-- Carry should never begin from a root already owned by another hard anchor.
	if rootPart.Anchored then
		warn(
			"[Downed-Client v42] pickup blocked: carrier HRP already Anchored"
		)
		return false
	end

	pickupRootHoldActive = true

	local generation = carryPickupGeneration

	resetPickupRootHoldAck()

	-- The server owns a temporary NON-ANCHORED constraint hold.
	-- The carrier remains Anchored=false for the complete authored pickup and
	-- the server destroys the temporary constraints only after pickup ends.
	animationSync:FireServer(
		"CarryPickupConstraintHoldStart",
		{
			generation = generation,
		}
	)

	local ok = waitForPickupRootHoldAck(
		generation,
		"Start"
	)

	if not ok then
		warn(
			"[Downed-Client v42] server pickup-root hold START failed/timeout",
			"| Generation=",
			generation,
			"| Anchored=",
			rootPart.Anchored
		)

		pickupRootHoldActive = nil
		return false
	end

	return true
end


local function unlockPickupRoot()
	if pickupRootHoldActive == nil then
		return
	end

	local generation = carryPickupGeneration

	pickupRootHoldActive = nil
	resetPickupRootHoldAck()

	animationSync:FireServer(
		"CarryPickupConstraintHoldEnd",
		{
			generation = generation,
		}
	)

	local ok = waitForPickupRootHoldAck(
		generation,
		"End"
	)

	if not ok then
		warn(
			"[Downed-Client v42] server pickup-root hold END failed/timeout",
			"| Generation=",
			generation,
			"| Anchored=",
			rootPart.Anchored
		)
	end
end


local function startCarryReleaseTrace()
	local originPosition = rootPart.Position

	task.spawn(function()
		local startedAt = time()

		for _, targetDelay in ipairs({
			0.00,
			0.25,
			0.50,
			1.00,
			1.50,
			2.00,
			2.50,
			3.00,
			}) do
			local remaining = targetDelay - (time() - startedAt)

			if remaining > 0 then
				task.wait(remaining)
			end

			if not character.Parent
				or character:GetAttribute("IsCarrying") ~= true then
				return
			end

			local move = humanoid.MoveDirection
			local velocity = rootPart.AssemblyLinearVelocity
			local delta = rootPart.Position - originPosition
			local displacement = Vector3.new(delta.X, 0, delta.Z).Magnitude
			local assemblyRoot = rootPart.AssemblyRootPart
			local connectedCount = 0

			pcall(function()
				connectedCount = #rootPart:GetConnectedParts(true)
			end)

			local movementKeyDown =
				UserInputService:IsKeyDown(Enum.KeyCode.W)
				or UserInputService:IsKeyDown(Enum.KeyCode.A)
				or UserInputService:IsKeyDown(Enum.KeyCode.S)
				or UserInputService:IsKeyDown(Enum.KeyCode.D)

			print(string.format(
				"[CarryReleaseTrace] +%.2fs | Anchored=%s | State=%s | WalkSpeed=%.2f | MoveMag=%.3f | WASD=%s | VelXZ=%.3f | DispXZ=%.3f | AssemblyRoot=%s | Connected=%d | OldHoldPos=%s | OldHoldOri=%s",
				targetDelay,
				tostring(rootPart.Anchored),
				humanoid:GetState().Name,
				humanoid.WalkSpeed,
				move.Magnitude,
				tostring(movementKeyDown),
				Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
				displacement,
				assemblyRoot and assemblyRoot:GetFullName() or "nil",
				connectedCount,
				tostring(rootPart:FindFirstChild("CarryPickupHoldPosition") ~= nil),
				tostring(rootPart:FindFirstChild("CarryPickupHoldOrientation") ~= nil)
				))
		end
	end)
end
local function isValidLocalCarryCandidate(
	candidateCharacter: Model
): boolean
	if candidateCharacter == character
		or not candidateCharacter.Parent then

		return false
	end

	if candidateCharacter:GetAttribute("IsDowned") ~= true
		and candidateCharacter:GetAttribute("Downed") ~= true then

		return false
	end

	if candidateCharacter:GetAttribute("IsCarried") == true
		or candidateCharacter:GetAttribute("IsExecuting") == true
		or candidateCharacter:GetAttribute("IsDownedAirborne") == true
		or candidateCharacter:GetAttribute("IsRecovering") == true then

		return false
	end

	local candidateHumanoid =
		candidateCharacter:FindFirstChildOfClass(
			"Humanoid"
		)

	local candidateRoot =
		candidateCharacter:FindFirstChild(
			"HumanoidRootPart"
		)

	if not candidateHumanoid
		or candidateHumanoid.Health <= 0
		or not candidateRoot
		or not candidateRoot:IsA("BasePart") then

		return false
	end

	return (
		candidateRoot.Position
		- rootPart.Position
	).Magnitude <= CARRY_LOCAL_PREFLIGHT_RADIUS
end


local function findLocalCarryCandidate(): Model?
	local nearest: Model? = nil
	local nearestDistance = math.huge

	for _, otherPlayer in ipairs(
		Players:GetPlayers()
		) do
		if otherPlayer == player then
			continue
		end

		local otherCharacter =
			otherPlayer.Character

		if not otherCharacter
			or not isValidLocalCarryCandidate(
				otherCharacter
			) then

			continue
		end

		local otherRoot =
			otherCharacter:FindFirstChild(
				"HumanoidRootPart"
			) :: BasePart?

		if not otherRoot then
			continue
		end

		local distance =
			(
				otherRoot.Position
				- rootPart.Position
			).Magnitude

		if distance < nearestDistance then
			nearestDistance = distance
			nearest = otherCharacter
		end
	end

	return nearest
end


local function cancelCarryPickup()
	carryPickupGeneration += 1
	carryPickupPending = false
	character:SetAttribute("CarryPickupActive", false)
	carryAttachRequested = false
	carryPickupCandidate = nil

	disconnectCarryAttachMarker()
	stopTrack(carryPickupTrack)
	stopTrack(carryCarrierTrack)
	stopTrack(carryCarrierRunTrack)
	unlockPickupRoot()
end


-- Forward declaration: pickup Ended hands control to the stable carry tracks.
local updateCarrierCarryAnimation: () -> ()
local prearmCarrierCarryAnimation: () -> ()


local function beginCarryPickup(
	candidate: Model
)
	if carryPickupPending
		or not isValidLocalCarryCandidate(
			candidate
		) then

		return
	end

	carryPickupPending = true
	character:SetAttribute("CarryPickupActive", true)
	carryAttachRequested = false
	carryPickupCandidate = candidate
	carryPickupGeneration += 1

	local generation =
		carryPickupGeneration

	if not lockPickupRoot() then
		carryPickupPending = false
		character:SetAttribute("CarryPickupActive", false)
		carryPickupCandidate = nil
		return
	end

	if not carryPickupTrack then
		-- Fail open: keep the original Carry behavior if the animation fails
		-- to load, but never leave the root anchored.
		carryPickupPending = false
		character:SetAttribute("CarryPickupActive", false)
		carryPickupCandidate = nil
		unlockPickupRoot()
		carryRequest:FireServer()
		return
	end

	stopTrack(carryCarrierTrack)
	stopTrack(carryCarrierRunTrack)

	disconnectCarryAttachMarker()

	carryAttachConnection =
		carryPickupTrack:
		GetMarkerReachedSignal(
			CARRY_ATTACH_MARKER
		):
		Connect(function()
			if generation
				~= carryPickupGeneration
				or not carryPickupPending
				or carryAttachRequested then

				return
			end

			local currentCandidate =
			carryPickupCandidate

			if not currentCandidate
				or not isValidLocalCarryCandidate(
					currentCandidate
				) then

				cancelCarryPickup()
				return
			end

			carryAttachRequested = true

			print(
				"[Downed-Client] CarryAttach marker"
			)

			-- v36:
			-- Keep the carrier HRP anchored through the ENTIRE pickup animation.
			--
			-- We already proved this prevents the authored crouch/lift pose from
			-- physically toppling the R6 assembly. GlobalNoTrip now independently
			-- prevents Roblox FallingDown/Ragdoll/GettingUp from stealing control
			-- when the root is released after the animation.
			--
			-- The victim can still be attached here at the authored marker.
			-- Victim carry parts are non-collidable + massless on the server.
			print(
				"[Downed-Client] CarryRequest while pickup root held",
				"| Anchored=",
				rootPart.Anchored,
				"| State=",
				humanoid:GetState().Name
			)


			carryRequest:FireServer()
		end)

	carryPickupTrack:Play(0.04)
	carryPickupTrack:AdjustSpeed(
		CARRY_PICKUP_ANIMATION_SPEED
	)

	-- Hard safety cleanup. This can never leave the pickup hold active forever.
	task.delay(3.0, function()
		if generation
			~= carryPickupGeneration
			or not carryPickupPending then

			return
		end

		warn(
			"[Downed-Client] pickup timeout; releasing root"
		)

		cancelCarryPickup()

		if character:GetAttribute(
			"IsCarrying"
			) == true then

			updateCarrierCarryAnimation()
		end
	end)

	task.spawn(function()
		carryPickupTrack.Ended:Wait()

		if generation
			~= carryPickupGeneration then

			return
		end

		disconnectCarryAttachMarker()

		-- Marker fallback only.
		if not carryAttachRequested then
			local currentCandidate =
				carryPickupCandidate

			if currentCandidate
				and isValidLocalCarryCandidate(
					currentCandidate
				) then

				warn(
					"[Downed-Client] CarryAttach missing; "
						.. "using Ended fallback"
				)

				carryAttachRequested = true

				-- Same v36 rule as the normal marker path: keep the carrier
				-- physically stable until the pickup track has fully ended.
				carryRequest:FireServer()
			end
		end

		carryPickupPending = false
		character:SetAttribute("CarryPickupActive", false)
		carryAttachRequested = false
		carryPickupCandidate = nil

		-- v38 HANDOFF:
		-- The server-confirmed Carry Idle/Run has already been playing at
		-- Action3 underneath CarryPickup's Action4 priority. Therefore when the
		-- pickup track ends there is no Roblox Idle/Walk frame between them.
		--
		-- Release the temporary root hold only after Action4 has fully ended; the
		-- already-settled Carry track becomes visible immediately.
		if character:GetAttribute("IsCarrying") == true then
			prearmCarrierCarryAnimation()
		end



		unlockPickupRoot()

		humanoid.PlatformStand = false
		humanoid.Sit = false

		startCarryReleaseTrace()

		print(
			"[Downed-Client] pickup ended -> PREARMED carry revealed",
			"| Anchored=",
			rootPart.Anchored,
			"| State=",
			humanoid:GetState().Name,
			"| IsCarrying=",
			character:GetAttribute("IsCarrying") == true,
			"| IdlePlaying=",
			carryCarrierTrack ~= nil
				and carryCarrierTrack.IsPlaying,
			"| RunPlaying=",
			carryCarrierRunTrack ~= nil
				and carryCarrierRunTrack.IsPlaying
		)
	end)
end


-- =========================
-- LOCAL STATE
-- =========================

local executionDeathPending = false
local downedSequenceActive = false
local downingGeneration = 0
local recoveryPlaying = false
local activeRecoveryCycleId: number? = nil

-- Downed-only ownership.
-- SetStateEnabled does not replicate, so the client mirrors the server while
-- the actual Downed flow owns this character.
local downedPhysicsStatesSaved = false
local originalFallingDownEnabled = true
local originalRagdollEnabled = true

local function disableDownedPhysicsStates()
	if not downedPhysicsStatesSaved then
		originalFallingDownEnabled =
			humanoid:GetStateEnabled(
				Enum.HumanoidStateType.FallingDown
			)

		originalRagdollEnabled =
			humanoid:GetStateEnabled(
				Enum.HumanoidStateType.Ragdoll
			)

		downedPhysicsStatesSaved = true
	end

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

local function restoreDownedPhysicsStates()
	if not downedPhysicsStatesSaved then
		return
	end

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.FallingDown,
		originalFallingDownEnabled
	)

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Ragdoll,
		originalRagdollEnabled
	)

	downedPhysicsStatesSaved = false
end

local function isActionLocked(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
end

local function enforceLocalLockedPose()
	if not isActionLocked() then
		return
	end

	if character:GetAttribute("IsDowned") == true then
		disableDownedPhysicsStates()
	end

	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	humanoid.Sit = false

	if character:GetAttribute("IsDowned") == true then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = false

	elseif character:GetAttribute("IsCarried") == true then
		-- The carried character must not run its own Humanoid physics controller
		-- while the one-way constraints control its separate assembly.
		setCarriedHumanoidPhysicsDisabled(true)
		humanoid.PlatformStand = false
		humanoid.AutoRotate = false

	elseif character:GetAttribute("IsExecuting") == true then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = false
	end

	-- Separate-assembly Carry safety:
	-- When this client is the carried victim, do NOT write AssemblyLinearVelocity
	-- or AssemblyAngularVelocity. Carry locomotion belongs only to the carrier;
	-- the follower constraints and disabled victim state machine own the carried
	-- pose without any victim-side assembly velocity writer.
	--
	-- All other victim locks remain unchanged:
	-- WalkSpeed=0, Jump=0, Sit=false, PlatformStand=false, AutoRotate=false.
	if character:GetAttribute("IsCarried") == true then
		return
	end

	-- While a dropped Downed player is airborne, the server owns the fall and
	-- gravity must be allowed to change AssemblyLinearVelocity. We still kill
	-- spin so the R6 body does not tumble/ragdoll.
	if character:GetAttribute("IsDownedAirborne") == true then
		rootPart.AssemblyAngularVelocity = Vector3.zero
		return
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function playDownedIdle()
	if executionDeathPending
		or character:GetAttribute("IsDowned") ~= true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsDownedAirborne") == true then
		return
	end

	disableDownedPhysicsStates()
	stopTrack(downingTrack)

	if downedIdleTrack and not downedIdleTrack.IsPlaying then
		downedIdleTrack:Play(0.08)
		downedIdleTrack:AdjustSpeed(
			DOWNED_IDLE_ANIMATION_SPEED
		)

		-- Server waits a short moment, measures the real animated pose and fits
		-- it to the floor dynamically.
		animationSync:FireServer("IdleStarted")
	end
end

local function startDownedSequence()
	if downedSequenceActive
		or executionDeathPending
		or character:GetAttribute("ExecutionFinalized") == true then
		return
	end

	disableDownedPhysicsStates()
	downedSequenceActive = true
	recoveryPlaying = false
	downingGeneration += 1

	local generation = downingGeneration

	stopTrack(recoveryTrack)
	stopTrack(downedIdleTrack)
	stopTrack(executedTrack)

	if downingTrack then
		downingTrack:Play(0.04)
		downingTrack:AdjustSpeed(DOWNING_ANIMATION_SPEED)

		task.spawn(function()
			downingTrack.Stopped:Wait()

			if generation ~= downingGeneration
				or not downedSequenceActive
				or executionDeathPending
				or character:GetAttribute("IsDowned") ~= true then
				return
			end

			playDownedIdle()
		end)
	else
		playDownedIdle()
	end
end

local function playRecovery(cycleId: number)
	if recoveryPlaying
		or executionDeathPending
		or humanoid.Health <= 0 then
		return
	end

	disableDownedPhysicsStates()
	enforceLocalLockedPose()

	recoveryPlaying = true
	activeRecoveryCycleId = cycleId
	downingGeneration += 1
	downedSequenceActive = false

	stopTrack(downingTrack)
	stopTrack(downedIdleTrack)
	stopTrack(executedTrack)

	if recoveryTrack then
		recoveryTrack:Play(0.06)
		recoveryTrack:AdjustSpeed(RECOVERY_ANIMATION_SPEED)

		local length = recoveryTrack.Length
		local duration =
			if length > 0
			then length / math.max(RECOVERY_ANIMATION_SPEED, 0.01)
			else 1.0

		animationSync:FireServer("RecoveryStarted", {
			duration = duration,
			cycleId = cycleId,
		})

		task.spawn(function()
			recoveryTrack.Stopped:Wait()

			-- If another Downed/Recovery cycle superseded this animation, its
			-- Stopped signal must never finish the newer cycle.
			if activeRecoveryCycleId ~= cycleId then
				return
			end

			recoveryPlaying = false
			activeRecoveryCycleId = nil
			animationSync:FireServer("RecoveryFinished", cycleId)
		end)
	else
		recoveryPlaying = false
		activeRecoveryCycleId = nil
		animationSync:FireServer("RecoveryFinished", cycleId)
	end
end

local function playCarryVictim()
	if executionDeathPending then
		return
	end

	local carried = character:GetAttribute("IsCarried") == true
	local airborne = character:GetAttribute("IsDownedAirborne") == true

	if not carried and not airborne then
		return
	end

	stopTrack(downingTrack)
	stopTrack(downedIdleTrack)
	stopTrack(recoveryTrack)

	if carryVictimTrack and not carryVictimTrack.IsPlaying then
		carryVictimTrack:Play(0.08)
		carryVictimTrack:AdjustSpeed(CARRY_VICTIM_ANIMATION_SPEED)
	end
end

local function stopCarrierCarryTracks()
	stopTrack(carryCarrierTrack)
	stopTrack(carryCarrierRunTrack)
end


-- Start the final shoulder-carry animation WHILE CarryPickup (Action4) is
-- still playing. CarryPickup visually remains authoritative, but the Action3
-- Carry track reaches full weight underneath it. When pickup ends there is no
-- one-frame fall-through to Roblox Idle/Walk.
prearmCarrierCarryAnimation = function()
	if character:GetAttribute("IsCarrying") ~= true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true then

		stopCarrierCarryTracks()
		return
	end

	local sprinting =
		character:GetAttribute("IsSprinting") == true

	if sprinting then
		stopTrack(carryCarrierTrack)

		if carryCarrierRunTrack
			and not carryCarrierRunTrack.IsPlaying then

			carryCarrierRunTrack:Play(0)
			carryCarrierRunTrack:AdjustSpeed(
				CARRY_CARRIER_RUN_ANIMATION_SPEED
			)
		end
	else
		stopTrack(carryCarrierRunTrack)

		if carryCarrierTrack
			and not carryCarrierTrack.IsPlaying then

			carryCarrierTrack:Play(0)
			carryCarrierTrack:AdjustSpeed(
				CARRY_CARRIER_ANIMATION_SPEED
			)
		end
	end

	print(
		"[Downed-Client] carry pose PREARMED under pickup",
		"| Sprinting=",
		sprinting,
		"| IdlePlaying=",
		carryCarrierTrack ~= nil
			and carryCarrierTrack.IsPlaying,
		"| RunPlaying=",
		carryCarrierRunTrack ~= nil
			and carryCarrierRunTrack.IsPlaying
	)
end


updateCarrierCarryAnimation = function()
	if carryPickupPending then
		stopCarrierCarryTracks()
		return
	end

	if executionDeathPending
		or character:GetAttribute("IsCarrying") ~= true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true then

		stopCarrierCarryTracks()
		return
	end

	local sprinting =
		character:GetAttribute("IsSprinting") == true

	if sprinting then
		stopTrack(carryCarrierTrack)

		if carryCarrierRunTrack
			and not carryCarrierRunTrack.IsPlaying then

			carryCarrierRunTrack:Play(0.08)
			carryCarrierRunTrack:AdjustSpeed(
				CARRY_CARRIER_RUN_ANIMATION_SPEED
			)
		end
	else
		stopTrack(carryCarrierRunTrack)

		if carryCarrierTrack
			and not carryCarrierTrack.IsPlaying then

			carryCarrierTrack:Play(0.08)
			carryCarrierTrack:AdjustSpeed(
				CARRY_CARRIER_ANIMATION_SPEED
			)
		end
	end
end

local function onCarryingChanged()
	if character:GetAttribute("IsCarrying") == true then
		if carryPickupPending then
			prearmCarrierCarryAnimation()
			return
		end

		updateCarrierCarryAnimation()
	else
		-- If Carry was rejected/cancelled while pickup is still active,
		-- the animation may finish normally. Do not unanchor merely because
		-- the replicated attribute has not arrived yet.
		stopCarrierCarryTracks()
	end
end

local function onDownedChanged()
	local downed = character:GetAttribute("IsDowned") == true
	local carried = character:GetAttribute("IsCarried") == true

	if downed then
		cancelCarryPickup()

		if executionDeathPending
			or character:GetAttribute("ExecutionFinalized") == true then
			downingGeneration += 1
			downedSequenceActive = false
			stopTrack(downingTrack)
			stopTrack(downedIdleTrack)
			stopTrack(carryVictimTrack)
			removeIndicator()
			return
		end

		stopCarrierCarryTracks()
		disableDownedPhysicsStates()
		enforceLocalLockedPose()

		task.defer(function()
			if character.Parent
				and character:GetAttribute("IsDowned") == true then
				disableDownedPhysicsStates()
				humanoid.PlatformStand = false
				humanoid.AutoRotate = false
			end
		end)

		local airborne =
			character:GetAttribute("IsDownedAirborne") == true

		if carried or airborne then
			downingGeneration += 1
			downedSequenceActive = false
			stopTrack(downingTrack)
			stopTrack(downedIdleTrack)
			playCarryVictim()
		else
			stopTrack(carryVictimTrack)

			if not executionDeathPending
				and character:GetAttribute("IsRecovering") ~= true then
				startDownedSequence()
			end
		end

		if character:GetAttribute("IsRecovering") ~= true then
			ensureIndicator()
		end
	else
		removeIndicator()
		downedSequenceActive = false
		stopTrack(downingTrack)
		stopTrack(downedIdleTrack)
		stopTrack(carryVictimTrack)
	end
end

local function onCarriedChanged()
	local carried = character:GetAttribute("IsCarried") == true
	local airborne =
		character:GetAttribute("IsDownedAirborne") == true

	if carried then
		setCarriedHumanoidPhysicsDisabled(true)
		cancelCarryPickup()
		disableDownedPhysicsStates()
		enforceLocalLockedPose()

		-- Cancel any pending Downing -> Idle transition. Stopping Downing fires
		-- AnimationTrack.Stopped, so the generation guard prevents Idle from
		-- starting again while this character is attached to the carrier.
		downingGeneration += 1
		downedSequenceActive = false

		stopTrack(downingTrack)
		stopTrack(downedIdleTrack)
		stopTrack(recoveryTrack)
		playCarryVictim()
		ensureIndicator()
	else
		setCarriedHumanoidPhysicsDisabled(false)

		-- On an airborne Drop, keep the CarryVictim pose until the body reaches
		-- the floor. Starting DownedIdle here would immediately ask the server
		-- to ground-fit and could anchor the player in mid-air.
		if airborne then
			downingGeneration += 1
			downedSequenceActive = false
			stopTrack(downingTrack)
			stopTrack(downedIdleTrack)
			stopTrack(recoveryTrack)
			playCarryVictim()
			ensureIndicator()
			return
		end

		stopTrack(carryVictimTrack)

		if character:GetAttribute("IsDowned") == true
			and character:GetAttribute("IsRecovering") ~= true then
			disableDownedPhysicsStates()
			downedSequenceActive = true
			playDownedIdle()
			ensureIndicator()
		else
			removeIndicator()
		end
	end
end

local function onAirborneChanged()
	local airborne =
		character:GetAttribute("IsDownedAirborne") == true

	if airborne then
		disableDownedPhysicsStates()
		downingGeneration += 1
		downedSequenceActive = false
		stopTrack(downingTrack)
		stopTrack(downedIdleTrack)
		stopTrack(recoveryTrack)

		if character:GetAttribute("IsDowned") == true then
			playCarryVictim()
			ensureIndicator()
		end
		return
	end

	-- Landing: leave the airborne CarryVictim pose and return to the exact
	-- grounded Downed Idle flow. The server will receive IdleStarted and fit
	-- the actual animated R6 body to the floor.
	if character:GetAttribute("IsDowned") == true
		and character:GetAttribute("IsCarried") ~= true
		and character:GetAttribute("IsRecovering") ~= true
		and not executionDeathPending then

		stopTrack(carryVictimTrack)
		disableDownedPhysicsStates()
		downedSequenceActive = true
		playDownedIdle()
		ensureIndicator()
	end
end

local function onExecutingChanged()
	if character:GetAttribute("IsExecuting") == true then
		cancelCarryPickup()
		enforceLocalLockedPose()
	end
end

-- =========================
-- INPUT
-- =========================

local function canStartInteraction(): boolean
	if humanoid.Health <= 0 then
		return false
	end

	if character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true then
		return false
	end

	return true
end

UserInputService.InputBegan:Connect(function(
	input: InputObject,
	gameProcessed: boolean
)
	if gameProcessed then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == EXECUTE_KEY then
		if not canStartInteraction() then
			return
		end

		if character:GetAttribute("IsCarrying") == true then
			return
		end

		executeRequest:FireServer()
		return
	end

	if input.KeyCode == CARRY_KEY then
		if character:GetAttribute("IsCarrying") == true then
			cancelCarryPickup()
			carryRequest:FireServer()
			return
		end

		if carryPickupPending
			or not canStartInteraction() then

			return
		end

		local candidate =
			findLocalCarryCandidate()

		if not candidate then
			-- No real Downed target nearby: V does nothing.
			return
		end

		beginCarryPickup(candidate)
	end
end)

-- =========================
-- ATTRIBUTE REACTIONS
-- =========================

character:GetAttributeChangedSignal("IsDowned"):Connect(onDownedChanged)
character:GetAttributeChangedSignal("Downed"):Connect(onDownedChanged)
character:GetAttributeChangedSignal("IsCarried"):Connect(onCarriedChanged)
character:GetAttributeChangedSignal("IsCarrying"):Connect(onCarryingChanged)
character:GetAttributeChangedSignal("IsDownedAirborne"):Connect(onAirborneChanged)
character:GetAttributeChangedSignal("IsSprinting"):Connect(function()
	if character:GetAttribute("IsCarrying") == true then
		if carryPickupPending then
			prearmCarrierCarryAnimation()
		else
			updateCarrierCarryAnimation()
		end
	end
end)
character:GetAttributeChangedSignal("IsExecuting"):Connect(onExecutingChanged)

character:GetAttributeChangedSignal("IsRecovering"):Connect(function()
	if character:GetAttribute("IsRecovering") == true then
		cancelCarryPickup()
		disableDownedPhysicsStates()
		enforceLocalLockedPose()
		removeIndicator()
	end
end)

character:GetAttributeChangedSignal("DownedActionLocked"):Connect(function()
	if isActionLocked() then
		enforceLocalLockedPose()

		task.defer(function()
			if character.Parent and isActionLocked() then
				enforceLocalLockedPose()
			end
		end)
	end
end)

-- DB: global trip-state interceptor removed.

-- =========================
-- SERVER PRESENTATION EVENTS
-- =========================

downedState.OnClientEvent:Connect(function(
	subjectPlayer: Player,
	state: string,
	extra: any
)
	if state == "RecoveryStart" and subjectPlayer == player then
		local cycleId = tonumber(extra)

		if not cycleId then
			return
		end

		executionDeathPending = false
		disableDownedPhysicsStates()
		enforceLocalLockedPose()
		removeIndicator()
		stopTrack(carryVictimTrack)
		playRecovery(cycleId)
		return
	end

	if state == "ExecuteCancelled" then
		if subjectPlayer == player then
			stopTrack(executeTrack)
		elseif extra == player then
			executionDeathPending = false
			stopTrack(executedTrack)

			if character:GetAttribute("IsDowned") == true then
				disableDownedPhysicsStates()
				downedSequenceActive = true
				playDownedIdle()
			end
		end

		return
	end

	if state == "ExecuteStart" then
		if subjectPlayer == player then
			cancelCarryPickup()
			stopCarrierCarryTracks()

			if executeTrack then
				executeTrack:Play(0.06)
				executeTrack:AdjustSpeed(EXECUTE_ANIMATION_SPEED)
			end
		elseif extra == player then
			executionDeathPending = true
			stopTrack(carryVictimTrack)
			downingGeneration += 1
			downedSequenceActive = false

			stopTrack(downingTrack)
			stopTrack(downedIdleTrack)
			stopTrack(recoveryTrack)

			if executedTrack then
				executedTrack:Play(0.06)
				executedTrack:AdjustSpeed(EXECUTED_ANIMATION_SPEED)
			end
		end

		return
	end

	if subjectPlayer ~= player then
		return
	end

	if state == "Downed" then
		activeRecoveryCycleId = nil
		recoveryPlaying = false
		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Dead,
			false
		)
		disableDownedPhysicsStates()
		executionDeathPending = false
		onDownedChanged()

	elseif state == "Recovered" then
		setCarriedHumanoidPhysicsDisabled(false)
		activeRecoveryCycleId = nil
		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Dead,
			false
		)
		executionDeathPending = false
		recoveryPlaying = false
		downedSequenceActive = false
		removeIndicator()
		stopTrack(downingTrack)
		stopTrack(downedIdleTrack)
		stopTrack(carryVictimTrack)
		stopCarrierCarryTracks()
		restoreDownedPhysicsStates()
		humanoid.PlatformStand = false

	elseif state == "Carried" then
		onCarriedChanged()

	elseif state == "Dropped" then
		onCarriedChanged()

	elseif state == "Landed" then
		onAirborneChanged()

	elseif state == "Carrying" then
		onCarryingChanged()

	elseif state == "Executed" then
		setCarriedHumanoidPhysicsDisabled(false)
		activeRecoveryCycleId = nil
		executionDeathPending = true
		restoreDownedPhysicsStates()
		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Dead,
			true
		)
		downingGeneration += 1
		downedSequenceActive = false
		recoveryPlaying = false

		removeIndicator()
		stopTrack(downingTrack)
		stopTrack(downedIdleTrack)
		stopTrack(recoveryTrack)
		stopTrack(carryVictimTrack)
		stopCarrierCarryTracks()
	end
end)

if character:GetAttribute("IsDowned") == true then
	disableDownedPhysicsStates()
	onDownedChanged()
end

if character:GetAttribute("IsCarried") == true then
	onCarriedChanged()
end

if character:GetAttribute("IsCarrying") == true then
	updateCarrierCarryAnimation()
end

if character:GetAttribute("IsDownedAirborne") == true then
	onAirborneChanged()
end

print(
	"[Downed-Client] ready v43.2 DB_CCLCleanupOnly"
		.. " | CarryPickup=93710921081891"
		.. " | CarryAttachMarker=CarryAttach"
		.. " | PickupRootHeldUntilAnimationEnded=ON"
		.. " | CarryRequestWhileRootHeld=ON"
		.. " | CarryPosePrearmedUnderPickup=ON"
		.. " | PrearmHelperScope=FIXED"
		.. " | CarryPickupActiveSignal=ON"
		.. " | DefaultIdleGap=REMOVED"
		.. " | StableCarryWeldExpected=Server_v31"
		.. " | VictimAssemblyVelocityWrites=SUPPRESSED_WHILE_CARRIED"
		.. " | PickupRootHold=NONANCHORED_SERVER_CONSTRAINT"
		.. " | CarriedHumanoidEvaluateStateMachine=OFF_ABTEST"
		.. " | GlobalNoTrip=REMOVED_DB"
		.. " | CarryPickupRootClamp=REMOVED_DB"
)



-- ============================================================
-- DB: CarryPickup RootJoint rotation workaround removed.
-- Authored RootJoint rotation is no longer clamped.
-- ============================================================



