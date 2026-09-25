--!strict
-- ServerScriptService > Services > FrontendService
--
-- WAYLESS Frontend / Main Menu server v1.1 stable Character Creation.
--
-- Server-authoritative slot actions:
-- Alive -> secure World handoff
-- DeadAwaitingDecision -> secure Afterlife handoff
-- Empty/Creating -> Character Creation foundation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperiencePlaceConfig =
	require(Shared:WaitForChild("ExperiencePlaceConfig"))

local Services = ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterHandoffService =
	require(Services:WaitForChild("CharacterHandoffService"))

local FrontendServerBrowserService =
	require(Services:WaitForChild("FrontendServerBrowserService"))

local FrontendService = {}

local cachedCharacterCreationService: any? = nil

local function getCharacterCreationService(): (any?, string?)
	if cachedCharacterCreationService then
		return cachedCharacterCreationService, nil
	end

	local module =
		Services:FindFirstChild("CharacterCreationService")

	if not module or not module:IsA("ModuleScript") then
		return nil, "CharacterCreationServiceMissing"
	end

	local ok, result =
		pcall(require, module)

	if not ok then
		warn(
			"[FrontendService] CharacterCreationService require failed",
			result
		)

		return nil, tostring(result)
	end

	cachedCharacterCreationService = result
	return cachedCharacterCreationService, nil
end

local started = false

type PlayerSession = {
	Ready: boolean,
	FocusSlotId: string?,
	ArrivalReason: string?,
}

local sessions: {[Player]: PlayerSession} = {}

local function waitForAccount(player: Player): boolean
	AccountProfileService.Start()

	local deadline = time() + 30
	while player.Parent and time() < deadline do
		if AccountProfileService.IsReady(player) then
			return true
		end
		task.wait(0.05)
	end

	return AccountProfileService.IsReady(player)
end

local function getTeleportData(player: Player): any
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)

	if not ok or typeof(joinData) ~= "table" then
		return nil
	end

	return joinData.TeleportData
end

local function processArrival(player: Player): PlayerSession
	local session: PlayerSession = {
		Ready = false,
		FocusSlotId = nil,
		ArrivalReason = nil,
	}
	sessions[player] = session

	if not waitForAccount(player) then
		return session
	end

	local teleportData = getTeleportData(player)

	if typeof(teleportData) == "table"
		and typeof(teleportData.HandoffToken) == "string"
		and teleportData.HandoffToken ~= "" then

		local ok, reason, handoff =
			CharacterHandoffService.Consume(
				player,
				teleportData.HandoffToken,
				"Frontend"
			)

		if ok and typeof(handoff) == "table" then
			local slotId =
				typeof(handoff.SlotId) == "string"
				and handoff.SlotId
				or nil

			if slotId
				and AccountProfileService.GetSlot(player, slotId) then

				session.FocusSlotId = slotId
				session.ArrivalReason =
					typeof(handoff.Extra) == "table"
					and tostring(handoff.Extra.Reason or "")
					or nil
			end
		else
			warn(
				"[FrontendService] ARRIVAL HANDOFF REJECTED",
				player.Name,
				reason
			)
		end
	end

	session.Ready = true

	player:SetAttribute("FrontendReady", true)
	player:SetAttribute("FrontendFocusSlotId", session.FocusSlotId)
	player:SetAttribute("FrontendArrivalReason", session.ArrivalReason)

	return session
end

local function publicSnapshot(player: Player): {[string]: any}?
	local raw = AccountProfileService.GetSnapshot(player)
	if not raw then
		return nil
	end

	local result = {
		Currencies = raw.Currencies,
		Entitlements = raw.Entitlements,
		Slots = {},
	}

	for slotId, slot in pairs(raw.Slots or {}) do
		local life = slot.CurrentLife
		local origin = slot.PermanentOrigin

		result.Slots[slotId] = {
			SlotId = slotId,
			UnlockSource = slot.UnlockSource,
			State = slot.State,
			LifeCounter = slot.LifeCounter,
			PermanentOrigin =
				typeof(origin) == "table"
				and {
					ClanId = origin.ClanId,
					Nature1Id = origin.Nature1Id,
					Nature2Id = origin.Nature2Id,
					Nature3Id = origin.Nature3Id,
				}
				or nil,
			CurrentLife =
				typeof(life) == "table"
				and {
					LifeId = life.LifeId,
					CharacterId = life.CharacterId,
					LifeNumber = life.LifeNumber,
					State = life.State,
					RevivalCount = life.RevivalCount,
					Summary = life.Summary,
				}
				or nil,
		}
	end

	return result
end

local function response(
	player: Player,
	ok: boolean,
	reason: string,
	extra: {[string]: any}?
): {[string]: any}
	local session = sessions[player]

	local value = {
		Ok = ok,
		Reason = reason,
		Ready = session ~= nil and session.Ready == true,
		FocusSlotId = session and session.FocusSlotId or nil,
		ArrivalReason = session and session.ArrivalReason or nil,
		Snapshot = publicSnapshot(player),
	}

	if typeof(extra) == "table" then
		for key, child in pairs(extra) do
			value[key] = child
		end
	end

	return value
end

local function validateSlot(
	player: Player,
	slotId: any
): (string?, {[string]: any}?)
	if slotId == nil then
		return nil, nil
	end

	local normalized = tostring(slotId)
	local slot = AccountProfileService.GetSlot(player, normalized)

	if not slot then
		return nil, nil
	end

	return normalized, slot
end

local function teleportWithHandoff(
	player: Player,
	targetKind: string,
	placeId: number,
	slotId: string,
	lifeId: string?,
	serverInstanceId: string?,
	reason: string
): (boolean, string)
	if placeId <= 0 then
		return false, targetKind .. "PlaceIdNotConfigured"
	end

	local handoffOk, handoffReason, token =
		CharacterHandoffService.Create(
			player,
			targetKind,
			slotId,
			lifeId,
			{
				Reason = reason,
				FromFrontend = true,
			}
		)

	if not handoffOk or not token then
		return false, handoffReason
	end

	local options = Instance.new("TeleportOptions")

	if typeof(serverInstanceId) == "string"
		and serverInstanceId ~= "" then

		options.ServerInstanceId = serverInstanceId
	end

	options:SetTeleportData({
		Flow = "FrontendTo" .. targetKind,
		HandoffToken = token,
		CharacterSlotId = slotId,
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(
			placeId,
			{ player },
			options
		)
	end)

	if not ok then
		CharacterHandoffService.Revoke(token)

		warn(
			"[FrontendService] TELEPORT FAILED",
			player.Name,
			targetKind,
			err
		)

		return false, targetKind .. "TeleportFailed"
	end

	player:SetAttribute("FrontendTeleporting", true)

	return true, targetKind .. "TeleportStarted"
end

local function handleRequest(
	player: Player,
	action: any,
	payload: any
): {[string]: any}
	if typeof(action) ~= "string" then
		return response(player, false, "InvalidAction", nil)
	end

	local session = sessions[player]
	if not session or not session.Ready then
		return response(player, false, "FrontendNotReady", nil)
	end

	if action == "GetState" then
		return response(player, true, "StateReady", nil)
	end

	if action == "GetServers" then
		local ok, reason, servers =
			FrontendServerBrowserService.ListServers()

		return response(
			player,
			ok,
			reason,
			{ Servers = servers }
		)
	end

	local slotId, slot =
		validateSlot(
			player,
			typeof(payload) == "table" and payload.SlotId or nil
		)

	if not slotId or not slot then
		return response(player, false, "SlotNotUnlocked", nil)
	end

	if action == "BeginCreation" then
		-- Compatibility only. The stable client opens the creator locally.
		-- Opening a UI must never mutate account data.
		return response(
			player,
			true,
			"CreatorOpensClientSide",
			nil
		)
	end

	if action == "CancelCreation" then
		if slot.State == "Empty" then
			return response(
				player,
				true,
				"CreatorClosed",
				nil
			)
		end

		local ok, reason =
			AccountProfileService.CancelCharacterCreation(
				player,
				slotId
			)

		return response(player, ok, reason, nil)
	end

	if action == "CommitCreation" then
		local creationService, creationError =
			getCharacterCreationService()

		if not creationService then
			return response(
				player,
				false,
				"CharacterCreationUnavailable",
				{
					CreationError = creationError,
				}
			)
		end

		local ok, reason, lifeId =
			creationService.Commit(
				player,
				slotId,
				payload
			)

		return response(
			player,
			ok,
			reason,
			{
				CreatedLifeId = lifeId,
			}
		)
	end

	if action == "ReturnAfterlife" then
		if slot.State ~= "DeadAwaitingDecision"
			or typeof(slot.CurrentLife) ~= "table" then

			return response(
				player,
				false,
				"LifeNotAwaitingDecision",
				nil
			)
		end

		local lifeId = slot.CurrentLife.LifeId
		if typeof(lifeId) ~= "string" or lifeId == "" then
			return response(player, false, "NoCurrentLife", nil)
		end

		local ok, reason =
			teleportWithHandoff(
				player,
				"Afterlife",
				tonumber(ExperiencePlaceConfig.AfterlifePlaceId) or 0,
				slotId,
				lifeId,
				nil,
				"FrontendDeadSlotReturn"
			)

		return response(player, ok, reason, nil)
	end

	if action == "PlaySlot" then
		if slot.State ~= "Alive"
			or typeof(slot.CurrentLife) ~= "table" then

			return response(
				player,
				false,
				"SlotNotPlayable",
				nil
			)
		end

		local lifeId = slot.CurrentLife.LifeId
		if typeof(lifeId) ~= "string" or lifeId == "" then
			return response(player, false, "NoCurrentLife", nil)
		end

		local serverInstanceId: string? = nil

		if typeof(payload) == "table"
			and typeof(payload.ServerInstanceId) == "string"
			and payload.ServerInstanceId ~= "" then

			local valid, reason, server =
				FrontendServerBrowserService.ValidateServer(
					payload.ServerInstanceId
				)

			if not valid or not server then
				return response(player, false, reason, nil)
			end

			serverInstanceId = server.JobId
		end

		local ok, reason =
			teleportWithHandoff(
				player,
				"World",
				tonumber(ExperiencePlaceConfig.WorldPlaceId) or 0,
				slotId,
				lifeId,
				serverInstanceId,
				serverInstanceId and "ServerBrowserJoin" or "QuickPlay"
			)

		return response(player, ok, reason, nil)
	end

	return response(player, false, "UnknownAction", nil)
end

local function ensureRemote(): RemoteFunction
	local system = ReplicatedStorage:FindFirstChild("FrontendSystem")

	if not system then
		system = Instance.new("Folder")
		system.Name = "FrontendSystem"
		system.Parent = ReplicatedStorage
	end

	local remotes = system:FindFirstChild("Remotes")

	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = system
	end

	local existing = remotes:FindFirstChild("FrontendRequest")

	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "FrontendRequest"
	remote.Parent = remotes

	return remote
end

function FrontendService.Start()
	if started then
		return
	end

	started = true
	AccountProfileService.Start()

	local remote = ensureRemote()

	remote.OnServerInvoke = function(player, action, payload)
		return handleRequest(player, action, payload)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(processArrival, player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(processArrival, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)

	print(
		"[FrontendService] READY v1.1 stable creation"
			.. " | SlotRouting=ON"
			.. " | CharacterCreation=STABLE_V1"
			.. " | ServerBrowser=ON"
	)
end

return FrontendService
