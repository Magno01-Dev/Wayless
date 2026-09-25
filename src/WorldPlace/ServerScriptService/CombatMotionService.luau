--!strict
-- CombatMotionService v1.1 - Stable Constraint Air Hold
-- ServerScriptService > CombatMotionService [ModuleScript]
--
-- Server-side motion adapter for combat entities without a player client.
-- v1.1 replaces per-frame HumanoidRootPart.CFrame writes with AlignPosition /
-- AlignOrientation so NPC suspension has one stable physics owner.

local RunService = game:GetService("RunService")

local CombatMotionService = {}

export type ServerTransitionHandle = {
	Stop: (self: ServerTransitionHandle, reason: string?) -> (),
	IsActive: (self: ServerTransitionHandle) -> boolean,
}

type TransitionState = {
	active: boolean,
	connection: RBXScriptConnection?,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	startCFrame: CFrame,
	targetCFrame: CFrame,
	transitionStartsAt: number,
	transitionDuration: number,
	holdDuration: number,
	savedAutoRotate: boolean,
	attachment: Attachment?,
	alignPosition: AlignPosition?,
	alignOrientation: AlignOrientation?,
}

local activeByCharacter: {[Model]: TransitionState} = {}

local function zeroRoot(root: BasePart)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function destroyConstraints(state: TransitionState)
	if state.alignPosition and state.alignPosition.Parent then
		state.alignPosition:Destroy()
	end
	if state.alignOrientation and state.alignOrientation.Parent then
		state.alignOrientation:Destroy()
	end
	if state.attachment and state.attachment.Parent then
		state.attachment:Destroy()
	end
	state.alignPosition = nil
	state.alignOrientation = nil
	state.attachment = nil
end

local function restoreState(state: TransitionState)
	if state.connection then
		state.connection:Disconnect()
		state.connection = nil
	end

	destroyConstraints(state)

	if state.character.Parent and state.humanoid.Parent then
		state.humanoid.AutoRotate = state.savedAutoRotate
	end

	if state.root.Parent then
		zeroRoot(state.root)
		pcall(function()
			state.root:SetNetworkOwner(nil)
		end)
	end

	if state.humanoid.Parent and state.humanoid.Health > 0 then
		if state.humanoid.FloorMaterial == Enum.Material.Air then
			state.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		else
			state.humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end

	if activeByCharacter[state.character] == state then
		activeByCharacter[state.character] = nil
	end
end

function CombatMotionService.StopServerTransition(
	character: Model,
	_reason: string?
)
	local state = activeByCharacter[character]
	if not state then
		return
	end
	state.active = false
	restoreState(state)
end

function CombatMotionService.BeginServerTransition(
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	transitionStartsAt: number,
	transitionDuration: number,
	holdDuration: number,
	startCFrame: CFrame,
	targetCFrame: CFrame
): ServerTransitionHandle
	CombatMotionService.StopServerTransition(character, "Replaced")

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatAirHoldAttachment"
	attachment.Parent = root

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "CombatAirHoldPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.ApplyAtCenterOfMass = true
	alignPosition.RigidityEnabled = false
	alignPosition.MaxForce = 250000
	alignPosition.MaxVelocity = 120
	alignPosition.Responsiveness = 42
	alignPosition.Position = startCFrame.Position
	alignPosition.Parent = root

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "CombatAirHoldOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxTorque = 250000
	alignOrientation.MaxAngularVelocity = 80
	alignOrientation.Responsiveness = 45
	alignOrientation.CFrame = targetCFrame.Rotation
	alignOrientation.Parent = root

	local state: TransitionState = {
		active = true,
		connection = nil,
		character = character,
		humanoid = humanoid,
		root = root,
		startCFrame = startCFrame,
		targetCFrame = targetCFrame,
		transitionStartsAt = transitionStartsAt,
		transitionDuration = math.max(0.01, transitionDuration),
		holdDuration = math.max(0, holdDuration),
		savedAutoRotate = humanoid.AutoRotate,
		attachment = attachment,
		alignPosition = alignPosition,
		alignOrientation = alignOrientation,
	}

	activeByCharacter[character] = state
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	zeroRoot(root)

	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	state.connection = RunService.Heartbeat:Connect(function()
		if not state.active then
			return
		end

		if not character.Parent
			or not humanoid.Parent
			or not root.Parent
			or humanoid.Health <= 0
			or not alignPosition.Parent
			or not alignOrientation.Parent then

			state.active = false
			restoreState(state)
			return
		end

		local serverNow = workspace:GetServerTimeNow()

		if serverNow < transitionStartsAt then
			alignPosition.Position = startCFrame.Position
			alignOrientation.CFrame = targetCFrame.Rotation
			return
		end

		local elapsed = serverNow - transitionStartsAt

		if elapsed < state.transitionDuration then
			local alpha = math.clamp(elapsed / state.transitionDuration, 0, 1)
			local eased = 1 - math.pow(1 - alpha, 3)
			alignPosition.Position = startCFrame.Position:Lerp(targetCFrame.Position, eased)
			alignOrientation.CFrame = targetCFrame.Rotation
		elseif elapsed < state.transitionDuration + state.holdDuration then
			alignPosition.Position = targetCFrame.Position
			alignOrientation.CFrame = targetCFrame.Rotation
		else
			state.active = false
			restoreState(state)
		end
	end)

	local handle = {} :: any

	function handle:Stop(_reason: string?)
		if state.active then
			state.active = false
			restoreState(state)
		end
	end

	function handle:IsActive(): boolean
		return state.active
	end

	return handle :: ServerTransitionHandle
end

print(
	"[CombatMotionService] READY v1.1 StableAirHold"
		.. " | ServerNPCTransitions=ON"
		.. " | AlignPosition=ON"
		.. " | AlignOrientation=ON"
		.. " | HumanoidPhysicsHold=ON"
		.. " | PerFrameCFrame=OFF"
)

return CombatMotionService
