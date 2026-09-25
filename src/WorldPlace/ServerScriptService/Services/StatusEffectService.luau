--!strict
-- DiabloStudios
-- ServerScriptService > Services > StatusEffectService
--
-- Server-authoritative status-effect runtime.
--
-- IMPORTANT:
-- This service intentionally does NOT write Humanoid.WalkSpeed, JumpPower,
-- Chakra values, or combat state directly. It aggregates status state into
-- character attributes so the owning gameplay systems remain authoritative.
--
-- DOT damage uses an injected DamageHandler. The bootstrap installs a
-- non-lethal handler ONLY in Studio for testing. Production combat should
-- later connect this to the project's centralized damage/downed pipeline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local statusShared = shared:WaitForChild("StatusEffects")
local Definitions = require(statusShared:WaitForChild("StatusEffectDefinitions"))

export type ApplyOptions = {
	Duration: number?,
	Stacks: number?,
	SourceCharacter: Model?,
	SourcePlayer: Player?,
	Metadata: {[string]: any}?,
}

type EffectState = {
	Id: string,
	Definition: any,
	Character: Model,
	Stacks: number,
	ExpiresAt: number,
	NextTickAt: number?,
	SourceCharacter: Model?,
	SourcePlayer: Player?,
	Metadata: {[string]: any},
	Replica: Folder,
}

type DamageHandler = (
	targetCharacter: Model,
	amount: number,
	context: {[string]: any}
) -> ()

local Service = {}

local started = false
local damageHandler: DamageHandler? = nil
local activeByCharacter: {[Model]: {[string]: EffectState}} = {}

local appliedBindable = Instance.new("BindableEvent")
local removedBindable = Instance.new("BindableEvent")
local tickBindable = Instance.new("BindableEvent")

Service.Applied = appliedBindable.Event
Service.Removed = removedBindable.Event
Service.Ticked = tickBindable.Event

local DEFAULT_ATTRIBUTES = {
	Status_ActiveCount = 0,

	Status_Stunned = false,
	Status_MovementBlocked = false,
	Status_AttackBlocked = false,
	Status_ChakraSuppressed = false,
	Status_ChakraChargeBlocked = false,

	Status_MoveSpeedMultiplier = 1.0,
	Status_ChakraRegenMultiplier = 1.0,
	Status_DamageTakenMultiplier = 1.0,
	Status_DamageDealtMultiplier = 1.0,
}

local MULTIPLIER_ATTRIBUTES = {
	MoveSpeedMultiplier = "Status_MoveSpeedMultiplier",
	ChakraRegenMultiplier = "Status_ChakraRegenMultiplier",
	DamageTakenMultiplier = "Status_DamageTakenMultiplier",
	DamageDealtMultiplier = "Status_DamageDealtMultiplier",
}

local FLAG_ATTRIBUTES = {
	Stunned = "Status_Stunned",
	MovementBlocked = "Status_MovementBlocked",
	AttackBlocked = "Status_AttackBlocked",
	ChakraSuppressed = "Status_ChakraSuppressed",
	ChakraChargeBlocked = "Status_ChakraChargeBlocked",
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getHumanoid(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return humanoid
end

local function initializeAttributes(character: Model)
	for name, value in pairs(DEFAULT_ATTRIBUTES) do
		if character:GetAttribute(name) == nil then
			character:SetAttribute(name, value)
		end
	end
end

local function ensureReplicaRoot(character: Model): Folder
	local existing = character:FindFirstChild("StatusEffects")
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "StatusEffects"
	folder.Parent = character
	return folder
end

local function createReplica(
	character: Model,
	effectId: string
): Folder
	local root = ensureReplicaRoot(character)

	local old = root:FindFirstChild(effectId)
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = effectId
	folder.Parent = root
	return folder
end

local function updateReplica(state: EffectState)
	local replica = state.Replica
	if not replica.Parent then
		return
	end

	replica:SetAttribute("Id", state.Id)
	replica:SetAttribute("DisplayName", state.Definition.DisplayName or state.Id)
	replica:SetAttribute("Category", state.Definition.Category or "Unknown")
	replica:SetAttribute("Stacks", state.Stacks)
	replica:SetAttribute("ExpiresAt", state.ExpiresAt)

	local sourceUserId = 0
	if state.SourcePlayer then
		sourceUserId = state.SourcePlayer.UserId
	end
	replica:SetAttribute("SourceUserId", sourceUserId)
end

local function getRegistry(character: Model): {[string]: EffectState}
	local registry = activeByCharacter[character]
	if registry then
		return registry
	end

	registry = {}
	activeByCharacter[character] = registry
	initializeAttributes(character)
	ensureReplicaRoot(character)

	return registry
end

local function recomputeAggregate(character: Model)
	initializeAttributes(character)

	local registry = activeByCharacter[character]

	local activeCount = 0

	local flags = {
		Stunned = false,
		MovementBlocked = false,
		AttackBlocked = false,
		ChakraSuppressed = false,
		ChakraChargeBlocked = false,
	}

	local multipliers = {
		MoveSpeedMultiplier = 1.0,
		ChakraRegenMultiplier = 1.0,
		DamageTakenMultiplier = 1.0,
		DamageDealtMultiplier = 1.0,
	}

	if registry then
		for _, state in pairs(registry) do
			activeCount += 1

			local definition = state.Definition
			local definitionFlags = definition.Flags or {}
			local definitionModifiers = definition.Modifiers or {}

			for flagName in pairs(flags) do
				if definitionFlags[flagName] == true then
					flags[flagName] = true
				end
			end

			for modifierName in pairs(multipliers) do
				local value = definitionModifiers[modifierName]
				if typeof(value) == "number" then
					multipliers[modifierName] *= value
				end
			end
		end
	end

	character:SetAttribute("Status_ActiveCount", activeCount)

	for flagName, attributeName in pairs(FLAG_ATTRIBUTES) do
		character:SetAttribute(attributeName, flags[flagName] == true)
	end

	for modifierName, attributeName in pairs(MULTIPLIER_ATTRIBUTES) do
		local value = multipliers[modifierName]
		value = math.clamp(value, 0.05, 5.0)
		character:SetAttribute(attributeName, value)
	end
end

local function removeInternal(
	character: Model,
	effectId: string,
	reason: string
): boolean
	local registry = activeByCharacter[character]
	if not registry then
		return false
	end

	local state = registry[effectId]
	if not state then
		return false
	end

	registry[effectId] = nil

	if state.Replica.Parent then
		state.Replica:Destroy()
	end

	recomputeAggregate(character)

	removedBindable:Fire(
		character,
		effectId,
		reason,
		state
	)

	if next(registry) == nil then
		activeByCharacter[character] = nil
	end

	return true
end

function Service.SetDamageHandler(handler: DamageHandler?)
	damageHandler = handler
end

function Service.GetDefinition(effectId: string): any?
	return Definitions[effectId]
end

function Service.Has(character: Model, effectId: string): boolean
	local registry = activeByCharacter[character]
	return registry ~= nil and registry[effectId] ~= nil
end

function Service.GetActive(character: Model): {[string]: any}
	local snapshot = {}
	local registry = activeByCharacter[character]

	if not registry then
		return snapshot
	end

	for effectId, state in pairs(registry) do
		snapshot[effectId] = {
			Id = state.Id,
			Stacks = state.Stacks,
			ExpiresAt = state.ExpiresAt,
			Remaining = math.max(0, state.ExpiresAt - now()),
			Category = state.Definition.Category,
			DisplayName = state.Definition.DisplayName,
		}
	end

	return snapshot
end

function Service.Apply(
	character: Model,
	effectId: string,
	options: ApplyOptions?
): (boolean, string)
	local definition = Definitions[effectId]
	if not definition then
		return false, "UnknownEffect"
	end

	if not character or not character:IsA("Model") or not character.Parent then
		return false, "InvalidCharacter"
	end

	local humanoid = getHumanoid(character)
	if not humanoid or humanoid.Health <= 0 then
		return false, "NoLivingHumanoid"
	end

	options = options or {}

	local duration = options.Duration or definition.DefaultDuration or 1.0
	duration = math.max(0.05, duration)

	local incomingStacks = options.Stacks or 1
	incomingStacks = math.max(1, math.floor(incomingStacks))

	local maxStacks = definition.MaxStacks or 1
	local stacking = definition.Stacking or "Refresh"

	local registry = getRegistry(character)
	local existing = registry[effectId]

	if existing then
		if stacking == "StackRefresh" then
			existing.Stacks = math.min(
				maxStacks,
				existing.Stacks + incomingStacks
			)
			existing.ExpiresAt = now() + duration

		elseif stacking == "Extend" then
			existing.ExpiresAt += duration

		elseif stacking == "Ignore" then
			return false, "AlreadyActive"

		else -- Refresh / fallback
			existing.Stacks = math.min(maxStacks, math.max(existing.Stacks, 1))
			existing.ExpiresAt = now() + duration
		end

		if options.SourceCharacter then
			existing.SourceCharacter = options.SourceCharacter
		end
		if options.SourcePlayer then
			existing.SourcePlayer = options.SourcePlayer
		end
		if options.Metadata then
			existing.Metadata = options.Metadata
		end

		if definition.TickInterval then
			existing.NextTickAt =
				math.min(
					existing.NextTickAt or math.huge,
					now() + definition.TickInterval
				)
		end

		updateReplica(existing)
		recomputeAggregate(character)

		appliedBindable:Fire(
			character,
			effectId,
			existing,
			true
		)

		return true, "Refreshed"
	end

	local replica = createReplica(character, effectId)

	local state: EffectState = {
		Id = effectId,
		Definition = definition,
		Character = character,
		Stacks = math.min(maxStacks, incomingStacks),
		ExpiresAt = now() + duration,
		NextTickAt = if definition.TickInterval
			then now() + definition.TickInterval
			else nil,
		SourceCharacter = options.SourceCharacter,
		SourcePlayer = options.SourcePlayer,
		Metadata = options.Metadata or {},
		Replica = replica,
	}

	registry[effectId] = state

	updateReplica(state)
	recomputeAggregate(character)

	appliedBindable:Fire(
		character,
		effectId,
		state,
		false
	)

	return true, "Applied"
end

function Service.Remove(
	character: Model,
	effectId: string,
	reason: string?
): boolean
	return removeInternal(
		character,
		effectId,
		reason or "Manual"
	)
end

function Service.Clear(
	character: Model,
	category: string?
): number
	local registry = activeByCharacter[character]
	if not registry then
		recomputeAggregate(character)
		return 0
	end

	local ids = {}

	for effectId, state in pairs(registry) do
		if category == nil
			or state.Definition.Category == category then
			table.insert(ids, effectId)
		end
	end

	local removed = 0
	for _, effectId in ipairs(ids) do
		if removeInternal(character, effectId, "Clear") then
			removed += 1
		end
	end

	return removed
end

local function tickEffect(state: EffectState)
	local definition = state.Definition
	local damage = definition.Damage

	if damage then
		local amountPerStack = damage.AmountPerStack or 0
		local amount = amountPerStack * state.Stacks

		if amount > 0 and damageHandler then
			damageHandler(
				state.Character,
				amount,
				{
					EffectId = state.Id,
					DamageType = damage.DamageType or state.Id,
					Stacks = state.Stacks,
					SourceCharacter = state.SourceCharacter,
					SourcePlayer = state.SourcePlayer,
					Metadata = state.Metadata,
				}
			)
		end
	end

	tickBindable:Fire(
		state.Character,
		state.Id,
		state
	)
end

local heartbeatAccumulator = 0

local function heartbeat(deltaTime: number)
	heartbeatAccumulator += deltaTime
	if heartbeatAccumulator < 0.10 then
		return
	end
	heartbeatAccumulator = 0

	local currentTime = now()

	local characterList = {}
	for character in pairs(activeByCharacter) do
		table.insert(characterList, character)
	end

	for _, character in ipairs(characterList) do
		local registry = activeByCharacter[character]
		if not registry then
			continue
		end

		local humanoid = getHumanoid(character)

		if not character.Parent
			or not humanoid
			or humanoid.Health <= 0 then

			Service.Clear(character)
			continue
		end

		local expired = {}

		for effectId, state in pairs(registry) do
			if currentTime >= state.ExpiresAt then
				table.insert(expired, effectId)
				continue
			end

			local tickInterval = state.Definition.TickInterval
			if tickInterval
				and state.NextTickAt
				and currentTime >= state.NextTickAt then

				tickEffect(state)
				state.NextTickAt = currentTime + tickInterval
			end
		end

		for _, effectId in ipairs(expired) do
			removeInternal(
				character,
				effectId,
				"Expired"
			)
		end
	end
end

function Service.Start()
	if started then
		return
	end

	started = true
	RunService.Heartbeat:Connect(heartbeat)

	print(
		"[StatusEffectService] READY v1",
		"| ServerAuthoritative=ON",
		"| ReplicatedState=Character/StatusEffects",
		"| AggregatedAttributes=ON",
		"| DirectMovementWrites=OFF",
		"| DamageHandler=EXTERNAL_ADAPTER"
	)
end

return Service
