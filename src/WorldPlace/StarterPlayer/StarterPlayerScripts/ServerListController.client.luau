--!strict
-- StarterPlayer > StarterPlayerScripts > ServerListController [LocalScript]
-- WAYLESS ServerList v1 candidate — live player roster + existing Squad integration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shared = ReplicatedStorage:WaitForChild("Shared")
local ServerListConfig = require(shared:WaitForChild("ServerListConfig"))
local ServerListView = require(shared:WaitForChild("ServerListView"))

local view = ServerListView.new(ServerListConfig, playerGui)

local destroyed = false
local connections: {RBXScriptConnection} = {}
local identityConnections: {[Player]: {RBXScriptConnection}} = {}
local villageLookup: {[string]: string} = {}

local squadId: string? = nil
local leaderUserId: number? = nil
local squadMemberIds: {[number]: boolean} = {}
local squadMemberCount = 0

local squadFolder = ReplicatedStorage:WaitForChild(ServerListConfig.Squad.RemotesFolderName)
local inviteRemote = squadFolder:WaitForChild(ServerListConfig.Squad.InviteRemoteName) :: RemoteEvent
local requestStateRemote = squadFolder:WaitForChild(ServerListConfig.Squad.RequestStateRemoteName) :: RemoteEvent
local snapshotRemote = squadFolder:WaitForChild(ServerListConfig.Squad.SnapshotRemoteName) :: RemoteEvent

for _, village in ipairs(ServerListConfig.Villages) do
	for _, alias in ipairs(village.Aliases) do
		villageLookup[string.lower(alias)] = village.Key
	end
end

local function track(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, connection)
	return connection
end

local function normalizeVillage(raw: any): string
	if typeof(raw) == "string" then
		local key = villageLookup[string.lower(raw)]
		if key then
			return key
		end
	end
	return "leaf"
end

local function characterName(target: Player): string
	local value = target:GetAttribute(ServerListConfig.Attributes.CharacterName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return target.DisplayName
end

local function rankName(target: Player): string
	local value = target:GetAttribute(ServerListConfig.Attributes.Rank)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return "Academy Student"
end

local function entryFor(target: Player): ServerListView.PlayerEntry
	return {
		UserId = target.UserId,
		CharacterName = characterName(target),
		Username = target.Name,
		VillageKey = normalizeVillage(target:GetAttribute(ServerListConfig.Attributes.VillageId)),
		Rank = rankName(target),
	}
end

local renderQueued = false
local function renderRoster()
	if destroyed then return end

	local entries: {ServerListView.PlayerEntry} = {}
	for _, target in ipairs(Players:GetPlayers()) do
		table.insert(entries, entryFor(target))
	end

	view:UpdateRoster(entries)
end

local function queueRender()
	if renderQueued or destroyed then return end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		renderRoster()
	end)
end

local function disconnectIdentity(target: Player)
	local list = identityConnections[target]
	if list then
		for _, connection in ipairs(list) do
			if connection.Connected then connection:Disconnect() end
		end
	end
	identityConnections[target] = nil
end

local function bindIdentity(target: Player)
	disconnectIdentity(target)

	local list = {}
	identityConnections[target] = list

	for _, attributeName in ipairs({
		ServerListConfig.Attributes.CharacterName,
		ServerListConfig.Attributes.VillageId,
		ServerListConfig.Attributes.Rank,
	}) do
		table.insert(list, target:GetAttributeChangedSignal(attributeName):Connect(queueRender))
	end
	table.insert(list, target:GetPropertyChangedSignal("DisplayName"):Connect(queueRender))
end

local function inviteReason(targetUserId: number): string
	if targetUserId == player.UserId then return "You" end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then return "Player left" end
	if squadMemberIds[targetUserId] then return "Already in your squad" end
	if squadMemberCount >= ServerListConfig.Squad.MaxMembers then return "Squad is full" end
	if squadId ~= nil and leaderUserId ~= player.UserId then return "Leader only" end
	return ""
end

view:SetInvitationAdapter(function(targetUserId: number)
	if inviteReason(targetUserId) ~= "" then return end
	inviteRemote:FireServer(targetUserId)
end, inviteReason)

track(view.ServerButton.Activated:Connect(function()
	view:SetOpen(not view.Open)
	if view.Open then
		requestStateRemote:FireServer()
		queueRender()
	end
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and view.Open then
		view:SetOpen(false)
	end
end))

track(snapshotRemote.OnClientEvent:Connect(function(nextSquadId: any, nextLeaderUserId: any, rawMembers: any)
	if nextSquadId ~= nil and typeof(nextSquadId) ~= "string" then return end
	if nextLeaderUserId ~= nil and typeof(nextLeaderUserId) ~= "number" then return end
	if typeof(rawMembers) ~= "table" then return end

	squadId = nextSquadId
	leaderUserId = nextLeaderUserId
	table.clear(squadMemberIds)
	squadMemberCount = 0

	for _, raw in ipairs(rawMembers) do
		if typeof(raw) == "table"
			and typeof(raw.UserId) == "number"
			and raw.UserId > 0
			and raw.UserId % 1 == 0 then

			squadMemberIds[raw.UserId] = true
			squadMemberCount += 1
		end
	end

	view:RefreshSelection()
end))

local reducedMotionConnection: RBXScriptConnection? = nil
do
	local okService, userGameSettings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)

	if okService and userGameSettings then
		local function syncReducedMotion()
			local okValue, value = pcall(function()
				return (userGameSettings :: any).ReducedMotion
			end)
			if okValue and typeof(value) == "boolean" then
				view:SetReducedMotion(value)
			end
		end

		syncReducedMotion()

		local okSignal, signal = pcall(function()
			return (userGameSettings :: any):GetPropertyChangedSignal("ReducedMotion")
		end)
		if okSignal and signal then
			reducedMotionConnection = signal:Connect(syncReducedMotion)
		end
	end
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

for _, target in ipairs(Players:GetPlayers()) do
	bindIdentity(target)
end

track(Players.PlayerAdded:Connect(function(target)
	bindIdentity(target)
	queueRender()
end))

track(Players.PlayerRemoving:Connect(function(target)
	disconnectIdentity(target)
	if view.SelectedUserId == target.UserId then
		view.SelectedUserId = nil
	end
	queueRender()
end))

track(script.Destroying:Connect(function()
	if destroyed then return end
	destroyed = true

	if reducedMotionConnection and reducedMotionConnection.Connected then
		reducedMotionConnection:Disconnect()
	end

	for target in pairs(identityConnections) do
		disconnectIdentity(target)
	end

	for _, connection in ipairs(connections) do
		if connection.Connected then connection:Disconnect() end
	end

	view:Destroy()
end))

requestStateRemote:FireServer()
renderRoster()

print("[ServerListController] READY v1 candidate | Astra ServerList | NativePlayerList=false")
