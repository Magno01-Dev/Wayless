--!strict
-- ServerScriptService > Services > CharacterLifeContextService
--
-- WAYLESS Character Life Context v1.1 - teardown safe
--
-- Canonical runtime identity:
--   Account -> Slot -> CurrentLife
--
-- SlotId is permanent container identity.
-- CharacterId/LifeId identify the current incarnation occupying that slot.
--
-- Gameplay services must use LifeId for life-scoped persistence.
-- Permanent genetics remain slot-scoped through AccountProfileService.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterSlotContextService =
	require(Services:WaitForChild("CharacterSlotContextService"))

local CharacterLifeContextService = {}

local WAIT_TIMEOUT = 30
local started = false

type LifeState = {
	Resolving: boolean,
	Ready: boolean,
	SlotId: string?,
	LifeId: string?,
	CharacterId: string?,
	LifeNumber: number,
	LifeState: string?,
	LegacyChildDataMigrationEligible: boolean,
}

local states: {[Player]: LifeState} = {}

local function getState(player: Player): LifeState
	local state = states[player]
	if state then
		return state
	end

	state = {
		Resolving = false,
		Ready = false,
		SlotId = nil,
		LifeId = nil,
		CharacterId = nil,
		LifeNumber = 0,
		LifeState = nil,
		LegacyChildDataMigrationEligible = false,
	}

	states[player] = state
	return state
end

local function waitForAccount(player: Player): boolean
	AccountProfileService.Start()

	local deadline = time() + WAIT_TIMEOUT
	while player.Parent and time() < deadline do
		if AccountProfileService.IsReady(player) then
			return true
		end
		task.wait(0.05)
	end

	return AccountProfileService.IsReady(player)
end

local function publish(player: Player, state: LifeState)
	player:SetAttribute(
		"CharacterLifeContextReady",
		state.Ready
	)

	player:SetAttribute(
		"CharacterLifeSlotId",
		state.SlotId
	)

	player:SetAttribute(
		"CharacterLifeId",
		state.LifeId
	)

	player:SetAttribute(
		"CharacterId",
		state.CharacterId
	)

	player:SetAttribute(
		"CharacterLifeNumber",
		state.LifeNumber
	)

	player:SetAttribute(
		"CharacterLifeState",
		state.LifeState
	)

	player:SetAttribute(
		"CharacterLifeLegacyMigrationEligible",
		state.LegacyChildDataMigrationEligible
	)
end

local function resolve(player: Player): LifeState
	local state = getState(player)

	if state.Ready then
		return state
	end

	if state.Resolving then
		while player.Parent and not state.Ready do
			task.wait()
		end
		return state
	end

	state.Resolving = true
	publish(player, state)

	if not waitForAccount(player) then
		state.Resolving = false
		error(
			("[CharacterLifeContextService] AccountProfile unavailable for %s")
				:format(player.Name)
		)
	end

	local slotReady, slotId =
		CharacterSlotContextService.WaitUntilReady(
			player,
			WAIT_TIMEOUT
		)

	if not slotReady or not slotId then
		state.Resolving = false
		error(
			("[CharacterLifeContextService] Slot context unavailable for %s")
				:format(player.Name)
		)
	end

	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot then
		state.Resolving = false
		error(
			("[CharacterLifeContextService] Active slot missing | Player=%s Slot=%s")
				:format(
					player.Name,
					slotId
				)
		)
	end

	local life = slot.CurrentLife

	if typeof(life) ~= "table"
		and slotId == "1"
		and slot.State == "LegacyImportPending" then

		-- Bootstrap bridge for accounts that have not completed the old
		-- Slot 1 -> AccountProfile import yet. AccountProfileService uses this
		-- exact deterministic LifeId when ImportLegacySlot1 commits, so Origin
		-- can load first without creating a circular dependency.
		local legacyLifeId =
			"legacy_"
			.. tostring(player.UserId)
			.. "_slot_1_life_1"

		life = {
			LifeId = legacyLifeId,
			CharacterId = legacyLifeId,
			LifeNumber = 1,
			State = "Alive",
			LegacyChildDataMigrationEligible = true,
		}

		print(
			"[CharacterLifeContextService] LEGACY SLOT 1 BRIDGE",
			player.Name,
			"Life=" .. legacyLifeId
		)
	end

	if typeof(life) ~= "table" then
		state.Resolving = false
		error(
			("[CharacterLifeContextService] Active slot has no life | Player=%s Slot=%s")
				:format(
					player.Name,
					slotId
				)
		)
	end

	local lifeId = life.LifeId
	if typeof(lifeId) ~= "string" or lifeId == "" then
		state.Resolving = false
		error(
			("[CharacterLifeContextService] Invalid LifeId | Player=%s Slot=%s")
				:format(
					player.Name,
					slotId
				)
		)
	end

	local characterId = life.CharacterId
	if typeof(characterId) ~= "string" or characterId == "" then
		-- Backward compatibility if AccountProfile migration has not been
		-- persisted yet.
		characterId = lifeId
	end

	state.SlotId = slotId
	state.LifeId = lifeId
	state.CharacterId = characterId
	state.LifeNumber =
		typeof(life.LifeNumber) == "number"
		and math.max(1, math.floor(life.LifeNumber))
		or 1
	state.LifeState =
		typeof(life.State) == "string"
		and life.State
		or tostring(slot.State)
	state.LegacyChildDataMigrationEligible =
		life.LegacyChildDataMigrationEligible == true

	state.Ready = true
	state.Resolving = false

	publish(player, state)

	print(
		"[CharacterLifeContextService] RESOLVED",
		player.Name,
		"Slot=" .. slotId,
		"Life=" .. lifeId,
		"Character=" .. characterId,
		"LifeNumber=" .. tostring(state.LifeNumber),
		"LegacyMigration="
			.. tostring(
				state.LegacyChildDataMigrationEligible
			)
	)

	return state
end

function CharacterLifeContextService.Start()
	if started then
		return
	end

	started = true

	AccountProfileService.Start()
	CharacterSlotContextService.Start()

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(function()
			resolve(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			resolve(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	print(
		"[CharacterLifeContextService] READY v1.1"
			.. " | LifeScopedPersistence=ON"
			.. " | LegacySlotMigration=ON"
	)
end

function CharacterLifeContextService.IsReady(
	player: Player
): boolean
	local state = states[player]
	return state ~= nil
		and state.Ready
		and state.LifeId ~= nil
end

function CharacterLifeContextService.WaitUntilReady(
	player: Player,
	timeoutSeconds: number?
): (boolean, string?)
	local state = getState(player)

	if state.Ready and state.LifeId then
		return true, state.LifeId
	end

	task.spawn(function()
		resolve(player)
	end)

	local timeout =
		typeof(timeoutSeconds) == "number"
		and math.max(0, timeoutSeconds)
		or WAIT_TIMEOUT

	local deadline = time() + timeout
	while player.Parent and time() < deadline do
		if state.Ready and state.LifeId then
			return true, state.LifeId
		end
		task.wait(0.03)
	end

	return false, state.LifeId
end

function CharacterLifeContextService.GetSlotId(
	player: Player
): string
	return resolve(player).SlotId :: string
end

function CharacterLifeContextService.GetLifeId(
	player: Player
): string
	return resolve(player).LifeId :: string
end

function CharacterLifeContextService.GetCharacterId(
	player: Player
): string
	return resolve(player).CharacterId :: string
end

function CharacterLifeContextService.GetLifeNumber(
	player: Player
): number
	return resolve(player).LifeNumber
end

function CharacterLifeContextService.GetLifeState(
	player: Player
): string?
	return resolve(player).LifeState
end

function CharacterLifeContextService.IsLegacyChildDataMigrationEligible(
	player: Player
): boolean
	return resolve(player).LegacyChildDataMigrationEligible
end

function CharacterLifeContextService.GetIdentity(
	player: Player
): {[string]: any}
	local state = resolve(player)

	return {
		SlotId = state.SlotId,
		LifeId = state.LifeId,
		CharacterId = state.CharacterId,
		LifeNumber = state.LifeNumber,
		State = state.LifeState,
		LegacyChildDataMigrationEligible =
			state.LegacyChildDataMigrationEligible,
	}
end

function CharacterLifeContextService.AssertIdentity(
	player: Player,
	slotId: any,
	lifeId: any,
	serviceName: string
)
	local expectedSlot =
		player:GetAttribute(
			"CharacterLifeSlotId"
		)

	local expectedLife =
		player:GetAttribute(
			"CharacterLifeId"
		)

	if typeof(expectedSlot) ~= "string"
		or expectedSlot == ""
		or typeof(expectedLife) ~= "string"
		or expectedLife == "" then

		if player.Parent == Players then
			local state = resolve(player)
			expectedSlot = state.SlotId
			expectedLife = state.LifeId
		else
			-- Teardown-safe: do not attempt to rebuild Account/Slot context
			-- after PlayerRemoving. The caller's session identity is immutable.
			return
		end
	end

	if tostring(slotId) ~= tostring(expectedSlot)
		or tostring(lifeId) ~= tostring(expectedLife) then

		error(
			("[%s] REFUSED wrong life identity | Player=%s ExpectedSlot=%s ActualSlot=%s ExpectedLife=%s ActualLife=%s")
				:format(
					serviceName,
					player.Name,
					tostring(expectedSlot),
					tostring(slotId),
					tostring(expectedLife),
					tostring(lifeId)
				)
		)
	end
end

return CharacterLifeContextService
