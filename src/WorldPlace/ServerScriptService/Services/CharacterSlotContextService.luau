--!strict
-- ServerScriptService > Services > CharacterSlotContextService
--
-- WAYLESS Character Slot Context v5 - Secure World handoff.
--
-- AUTHORITATIVE SESSION CONTRACT
--   * One gameplay server session has exactly one immutable active slot.
--   * Production source: one-time MemoryStore handoff from Frontend/Afterlife.
--   * Studio QA source: AccountProfile.QA.StudioNextSlotId.
--   * Direct joins without either source safely fall back to Slot 1.
--   * Requested slots are validated against AccountProfileService BEFORE
--     CharacterSlotContextReady is published.
--   * Empty/dead slots cannot enter the gameplay World.
--
-- IMPORTANT
--   Do NOT hot-switch slots after gameplay persistence has loaded.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local DeveloperAccessService =
	require(Services:WaitForChild("DeveloperAccessService"))

local CharacterHandoffService =
	require(Services:WaitForChild("CharacterHandoffService"))

local CharacterSlotContextService = {}

local DEFAULT_SLOT_ID = "1"
local WAIT_TIMEOUT = 30
local MODE_REAL = "RealSlotSelection"

local started = false

local states: {[Player]: {
	Resolving: boolean,
	Ready: boolean,
	SlotId: string?,
	Source: string?,
}} = {}

local function normalizeSlotId(value: any): string?
	if value == nil then
		return nil
	end

	local slotId = tostring(value)
	local numeric = tonumber(slotId)

	if slotId == ""
		or numeric == nil
		or numeric < 1
		or numeric ~= math.floor(numeric) then

		return nil
	end

	return tostring(math.floor(numeric))
end

local function getState(player: Player)
	local state = states[player]
	if state then
		return state
	end

	state = {
		Resolving = false,
		Ready = false,
		SlotId = nil,
		Source = nil,
	}
	states[player] = state
	return state
end

local function waitForAccountProfile(player: Player): boolean
	AccountProfileService.Start()

	local deadline = time() + WAIT_TIMEOUT
	while player.Parent and time() < deadline do
		if AccountProfileService.IsReady(player) then
			return true
		end
		task.wait(0.05)
	end

	return player.Parent ~= nil
		and AccountProfileService.IsReady(player)
end

local function slotCanEnterWorld(
	player: Player,
	slotId: string
): (boolean, string)
	local slot = AccountProfileService.GetSlot(player, slotId)
	if not slot then
		return false, "SlotNotUnlocked"
	end

	-- Legacy Slot 1 is allowed while its one-time import finishes.
	if slotId == "1"
		and slot.State == "LegacyImportPending" then

		return true, "LegacySlot1Pending"
	end

	if slot.State ~= "Alive" then
		return false, "SlotNotAlive"
	end

	if typeof(slot.CurrentLife) ~= "table" then
		return false, "SlotHasNoCurrentLife"
	end

	return true, "SlotPlayable"
end

local function readSecureWorldHandoff(
	player: Player
): (string?, string?, string?)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)

	if not ok or typeof(joinData) ~= "table" then
		return nil, nil, nil
	end

	local teleportData = joinData.TeleportData
	if typeof(teleportData) ~= "table" then
		return nil, nil, nil
	end

	local token = teleportData.HandoffToken

	if typeof(token) ~= "string"
		or token == "" then

		return nil, nil, nil
	end

	local consumeOk,
		reason,
		handoff =
		CharacterHandoffService.Consume(
			player,
			token,
			"World"
		)

	if not consumeOk
		or typeof(handoff) ~= "table" then

		return nil,
			nil,
			"InvalidWorldHandoff:" .. tostring(reason)
	end

	local slotId =
		normalizeSlotId(
			handoff.SlotId
		)

	local lifeId =
		typeof(handoff.LifeId) == "string"
		and handoff.LifeId
		or nil

	if not slotId
		or not lifeId
		or lifeId == "" then

		return nil,
			nil,
			"IncompleteWorldHandoff"
	end

	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot
		or slot.State ~= "Alive"
		or typeof(slot.CurrentLife) ~= "table"
		or tostring(slot.CurrentLife.LifeId or "") ~= lifeId then

		return nil,
			nil,
			"WorldHandoffLifeMismatch"
	end

	return slotId,
		lifeId,
		nil
end

local function readDeveloperPreference(
	player: Player
): string?
	if not DeveloperAccessService.IsDeveloper(player) then
		return nil
	end

	local slotId =
		normalizeSlotId(
			AccountProfileService
			.GetStudioNextSlotId(player)
		)

	if slotId then
		print(
			"[CharacterSlotContextService] DEV PREFERENCE",
			player.Name,
			"Slot=" .. slotId,
			"Source=AccountProfile"
		)
	end

	return slotId
end

local function publish(
	player: Player,
	slotId: string,
	source: string
)
	local state = getState(player)

	state.Ready = true
	state.Resolving = false
	state.SlotId = slotId
	state.Source = source

	player:SetAttribute(
		"CharacterSlotId",
		slotId
	)
	player:SetAttribute(
		"CharacterActiveSlotId",
		slotId
	)
	player:SetAttribute(
		"CharacterSlotContextReady",
		true
	)
	player:SetAttribute(
		"CharacterSlotSelectionReady",
		true
	)
	player:SetAttribute(
		"CharacterSlotContextMode",
		MODE_REAL
	)
	player:SetAttribute(
		"CharacterRealSlotSelectionEnabled",
		true
	)
	player:SetAttribute(
		"CharacterSlotSelectionSource",
		source
	)
	player:SetAttribute(
		"CharacterSlotSessionLocked",
		true
	)
end

local function resolvePlayer(
	player: Player
): string
	local state = getState(player)

	if state.Ready and state.SlotId then
		return state.SlotId
	end

	if state.Resolving then
		while player.Parent and not state.Ready do
			task.wait()
		end
		return state.SlotId or DEFAULT_SLOT_ID
	end

	state.Resolving = true

	player:SetAttribute(
		"CharacterSlotContextReady",
		false
	)
	player:SetAttribute(
		"CharacterSlotSelectionReady",
		false
	)
	player:SetAttribute(
		"CharacterRealSlotSelectionEnabled",
		true
	)
	player:SetAttribute(
		"CharacterSlotContextMode",
		MODE_REAL
	)
	player:SetAttribute(
		"CharacterSlotSessionLocked",
		false
	)

	if not waitForAccountProfile(player) then
		warn(
			"[CharacterSlotContextService] Account profile timeout; fallback Slot 1",
			player.Name
		)

		publish(
			player,
			DEFAULT_SLOT_ID,
			"EmergencyFallback"
		)

		return DEFAULT_SLOT_ID
	end

	local requested,
		expectedLifeId,
		handoffError =
		readSecureWorldHandoff(
			player
		)

	local source =
		requested
		and "SecureHandoff"
		or nil

	if handoffError then
		state.Resolving = false

		warn(
			"[CharacterSlotContextService] WORLD HANDOFF REJECTED",
			player.Name,
			handoffError
		)

		player:Kick(
			"Invalid or expired character handoff."
		)

		error(handoffError)
	end

	if requested and expectedLifeId then
		player:SetAttribute(
			"CharacterWorldExpectedLifeId",
			expectedLifeId
		)

		player:SetAttribute(
			"WorldHandoffValidated",
			true
		)
	else
		player:SetAttribute(
			"WorldHandoffValidated",
			false
		)
	end

	if not requested then
		requested =
			readDeveloperPreference(player)

		if requested then
			source =
				"DeveloperAccountProfile"
		end
	end

	if not requested then
		requested = DEFAULT_SLOT_ID
		source = "DirectJoinFallback"
	end

	local playable,
		reason =
		slotCanEnterWorld(
			player,
			requested
		)

	if not playable then
		warn(
			"[CharacterSlotContextService] Requested slot rejected",
			player.Name,
			"Slot=" .. requested,
			"Reason=" .. reason,
			"-> Slot 1"
		)

		local fallbackPlayable =
			slotCanEnterWorld(
				player,
				DEFAULT_SLOT_ID
			)

		if not fallbackPlayable then
			state.Resolving = false

			error(
				"No playable fallback character slot for "
					.. player.Name
			)
		end

		requested = DEFAULT_SLOT_ID
		source = "ValidatedFallback"
	end

	publish(
		player,
		requested,
		source or "Unknown"
	)

	print(
		"[CharacterSlotContextService] SESSION RESOLVED",
		player.Name,
		"Slot=" .. requested,
		"Source=" .. tostring(source)
	)

	return requested
end

function CharacterSlotContextService.GetDefaultSlotId(): string
	return DEFAULT_SLOT_ID
end

function CharacterSlotContextService.IsRealSlotSelectionEnabled(): boolean
	return true
end

function CharacterSlotContextService.GetMode(): string
	return MODE_REAL
end

function CharacterSlotContextService.EnsurePlayer(
	player: Player
): string
	return resolvePlayer(player)
end

function CharacterSlotContextService.WaitUntilReady(
	player: Player,
	timeoutSeconds: number?
): (boolean, string?)
	local state = getState(player)

	if state.Ready and state.SlotId then
		return true, state.SlotId
	end

	task.spawn(function()
		resolvePlayer(player)
	end)

	local timeout =
		typeof(timeoutSeconds) == "number"
		and math.max(0, timeoutSeconds)
		or WAIT_TIMEOUT

	local deadline = time() + timeout

	while player.Parent
		and time() < deadline do

		if state.Ready
			and state.SlotId then

			return true,
				state.SlotId
		end

		task.wait(0.03)
	end

	return false,
		state.SlotId
end

function CharacterSlotContextService.GetActiveSlotId(
	player: Player
): string
	return resolvePlayer(player)
end

function CharacterSlotContextService.GetSelectionSource(
	player: Player
): string?
	local state = getState(player)

	if not state.Ready then
		resolvePlayer(player)
	end

	return state.Source
end

-- Active gameplay sessions are immutable.
function CharacterSlotContextService.SetActiveSlotId(
	player: Player,
	requestedSlotId: any
): (boolean, string)
	local requested =
		normalizeSlotId(
			requestedSlotId
		)

	if not requested then
		return false,
			"InvalidSlotId"
	end

	local current =
		resolvePlayer(player)

	if current == requested then
		return true,
			"SlotAlreadyActive"
	end

	return false,
		"SessionSlotLocked"
end

function CharacterSlotContextService.SetStudioPreferredSlot(
	player: Player,
	requestedSlotId: any
): (boolean, string)
	if not DeveloperAccessService.IsDeveloper(player) then
		return false,
			"NotDeveloper"
	end

	if not waitForAccountProfile(player) then
		return false,
			"AccountProfileNotReady"
	end

	local slotId =
		normalizeSlotId(
			requestedSlotId
		)

	if not slotId then
		return false,
			"InvalidSlotId"
	end

	local playable,
		reason =
		slotCanEnterWorld(
			player,
			slotId
		)

	if not playable then
		return false,
			reason
	end

	local ok,
		saveReason =
		AccountProfileService
		.SetStudioNextSlotId(
			player,
			slotId
		)

	if not ok then
		return false,
			saveReason
	end

	player:SetAttribute(
		"CharacterStudioNextSlotId",
		slotId
	)

	print(
		"[CharacterSlotContextService] NEXT PLAY SAVED",
		player.Name,
		"Slot=" .. slotId,
		"Store=AccountProfile"
	)

	return true,
		"NextPlaySlotSaved"
end

function CharacterSlotContextService.GetStudioPreferredSlot(
	player: Player
): string?
	if not DeveloperAccessService.IsDeveloper(player) then
		return nil
	end

	if not waitForAccountProfile(player) then
		return nil
	end

	local slotId =
		normalizeSlotId(
			AccountProfileService
			.GetStudioNextSlotId(
				player
			)
		)

	player:SetAttribute(
		"CharacterStudioNextSlotId",
		slotId
	)

	return slotId
end

function CharacterSlotContextService.ClearStudioPreferredSlot(
	player: Player
): (boolean, string)
	if not DeveloperAccessService.IsDeveloper(player) then
		return false,
			"NotDeveloper"
	end

	if not waitForAccountProfile(player) then
		return false,
			"AccountProfileNotReady"
	end

	local ok,
		reason =
		AccountProfileService
		.ClearStudioNextSlotId(
			player
		)

	if not ok then
		return false,
			reason
	end

	player:SetAttribute(
		"CharacterStudioNextSlotId",
		nil
	)

	return true,
		"NextPlaySlotCleared"
end

function CharacterSlotContextService.Start()
	if started then
		return
	end

	started = true

	DeveloperAccessService.Start()
	AccountProfileService.Start()

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(function()
			resolvePlayer(player)
		end)
	end

	Players.PlayerAdded:
		Connect(function(
			player: Player
		)
		task.spawn(function()
			resolvePlayer(player)
		end)
	end)

	Players.PlayerRemoving:
		Connect(function(
			player: Player
		)
		states[player] = nil
	end)
end

print(
	"[CharacterSlotContextService] READY v5 SecureHandoff"
		.. " | Mode=RealSlotSelection"
		.. " | SessionLock=ON"
		.. " | TeleportData=ON"
		.. " | DevPreference=AccountProfile"
)

return CharacterSlotContextService
