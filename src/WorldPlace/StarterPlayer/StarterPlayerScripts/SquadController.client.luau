--!strict
-- StarterPlayer > StarterPlayerScripts > SquadController [LocalScript]
-- WAYLESS SquadUI v1 candidate — client adapter for server-authoritative SquadService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shared = ReplicatedStorage:WaitForChild("Shared")
local SquadConfig = require(shared:WaitForChild("SquadConfig"))
local SquadView = require(shared:WaitForChild("SquadView"))

local remotesFolder = ReplicatedStorage:WaitForChild(SquadConfig.RemotesFolderName)
local names = SquadConfig.RemoteNames

local inviteRemote = remotesFolder:WaitForChild(names.Invite) :: RemoteEvent
local respondRemote = remotesFolder:WaitForChild(names.Respond) :: RemoteEvent
local removeRemote = remotesFolder:WaitForChild(names.Remove) :: RemoteEvent
local leaveRemote = remotesFolder:WaitForChild(names.Leave) :: RemoteEvent
local requestStateRemote = remotesFolder:WaitForChild(names.RequestState) :: RemoteEvent
local snapshotRemote = remotesFolder:WaitForChild(names.SquadSnapshot) :: RemoteEvent
local invitationRemote = remotesFolder:WaitForChild(names.Invitation) :: RemoteEvent
local invitationResultRemote = remotesFolder:WaitForChild(names.InvitationResult) :: RemoteEvent
local noticeRemote = remotesFolder:WaitForChild(names.SquadNotice) :: RemoteEvent

local view = SquadView.new(SquadConfig, playerGui)

-- Honor Roblox reduced-motion preference when the client exposes it.
-- SquadView reads animation timings from its per-instance config, so reduced
-- motion swaps only those timings/offsets to zero without changing layout.
local reducedMotionConnection: RBXScriptConnection? = nil
local normalViewConfig = view.Config
local reducedAnimation = table.clone(SquadConfig.Animation)
for _, key in ipairs({
	"PanelEnter",
	"PanelExit",
	"PanelEnterOffsetY",
	"PanelExitOffsetY",
	"HUDRowEnter",
	"HUDRowRemove",
	"HUDRowReflow",
	"HealthTween",
	"NoticeEnter",
	"NoticeExit",
}) do
	reducedAnimation[key] = 0
end
local reducedViewConfig = {}
for key, value in pairs(SquadConfig) do
	reducedViewConfig[key] = value
end
reducedViewConfig.Animation = reducedAnimation

local function setReducedMotion(enabled: boolean)
	view.Config = if enabled then reducedViewConfig else normalViewConfig
end

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
				setReducedMotion(value)
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

local destroyed = false
local connections: {RBXScriptConnection} = {}
local menuOpen = false
local activeTab = "invite"
local squadId: string? = nil
local leaderUserId: number? = nil
local members: {SquadView.MemberData} = {}
local memberIds: {[number]: boolean} = {}
local playersByUserId: {[number]: Player} = {}

local currentInvitation: {
	Id: string,
	SenderUserId: number,
	ExpiresAt: number,
}? = nil

local function track(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, connection)
	return connection
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getCharacterName(target: Player): string
	local value = target:GetAttribute("ShinobiDisplayName")
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return target.DisplayName
end

local function rebuildPlayersMap()
	table.clear(playersByUserId)
	for _, target in ipairs(Players:GetPlayers()) do
		playersByUserId[target.UserId] = target
	end
end

local function rebuildMemberIds()
	table.clear(memberIds)
	for _, member in ipairs(members) do
		memberIds[member.UserId] = true
	end
end

local function normalizeSearch(text: string): string
	local query = string.lower(text)
	query = string.gsub(query, "^%s+", "")
	query = string.gsub(query, "%s+$", "")
	query = string.gsub(query, "^@", "")
	return query
end

local function includesInsensitive(haystack: string, needle: string): boolean
	if needle == "" then
		return true
	end
	return string.find(string.lower(haystack), needle, 1, true) ~= nil
end

local function memberEntries(): {SquadView.SearchEntry}
	local result: {SquadView.SearchEntry} = {}
	for _, member in ipairs(members) do
		table.insert(result, {
			UserId = member.UserId,
			characterName = member.characterName,
			username = member.username,
			isLeader = member.UserId == leaderUserId,
			isSelf = member.UserId == player.UserId,
		})
	end
	return result
end

local function searchEntries(): {SquadView.SearchEntry}
	local query = normalizeSearch(view.SearchBox.Text)
	local result: {SquadView.SearchEntry} = {}

	for _, target in ipairs(Players:GetPlayers()) do
		if target ~= player and not memberIds[target.UserId] then
			local characterName = getCharacterName(target)
			if includesInsensitive(characterName, query)
				or includesInsensitive(target.Name, query) then
				table.insert(result, {
					UserId = target.UserId,
					characterName = characterName,
					username = target.Name,
				})
			end
		end
	end

	table.sort(result, function(a, b)
		local aName = string.lower(a.characterName)
		local bName = string.lower(b.characterName)
		if aName == bName then
			return string.lower(a.username) < string.lower(b.username)
		end
		return aName < bName
	end)

	return result
end

local renderMenu: () -> ()

local function canInvite(): boolean
	if #members >= SquadConfig.MaxMembers then
		return false
	end
	if squadId == nil then
		return true
	end
	return leaderUserId == player.UserId
end

renderMenu = function()
	if destroyed then
		return
	end

	view:SetActiveTab(activeTab)
	view:SetLeaveVisible(squadId ~= nil)

	if activeTab == "members" then
		local entries = memberEntries()
		view:RenderResults(entries, "members", {
			Remove = if leaderUserId == player.UserId
				then function(targetUserId: number)
					removeRemote:FireServer(targetUserId)
				end
				else nil,
		}, player.UserId, leaderUserId)

		if squadId == nil then
			view:SetHint("Invite someone to create your squad.")
		elseif leaderUserId == player.UserId then
			view:SetHint("You can remove members from your squad.")
		else
			view:SetHint("Only the leader can remove members.")
		end
	else
		local allowed = canInvite()
		view:RenderResults(searchEntries(), "invite", {
			Invite = if allowed
				then function(targetUserId: number)
					inviteRemote:FireServer(targetUserId)
				end
				else nil,
		}, player.UserId, leaderUserId)

		if #members >= SquadConfig.MaxMembers then
			view:SetHint("Squad is full.")
		elseif squadId ~= nil and leaderUserId ~= player.UserId then
			view:SetHint("Only the leader can invite players.")
		else
			view:SetHint("Select a player to invite.")
		end
	end
end

local function setMenuOpen(open: boolean)
	menuOpen = open
	view:SetMenuOpen(open)
	if open then
		renderMenu()
	end
end

local function toggleMenu()
	setMenuOpen(not menuOpen)
end

local function setActiveTab(tab: string)
	if tab ~= "invite" and tab ~= "members" then
		return
	end
	activeTab = tab
	renderMenu()
end

local function clearInvitation()
	currentInvitation = nil
	view:SetInvitationVisible(false)
end

local function validateMember(raw: any): SquadView.MemberData?
	if typeof(raw) ~= "table" then
		return nil
	end
	if typeof(raw.UserId) ~= "number" or raw.UserId <= 0 or raw.UserId % 1 ~= 0 then
		return nil
	end
	if typeof(raw.characterName) ~= "string" or typeof(raw.username) ~= "string" or typeof(raw.identityKey) ~= "string" then
		return nil
	end
	local health = if typeof(raw.health) == "number" then raw.health else 0
	local maxHealth = if typeof(raw.maxHealth) == "number" then raw.maxHealth else 0
	return {
		UserId = raw.UserId,
		characterName = raw.characterName,
		username = raw.username,
		identityKey = raw.identityKey,
		health = math.max(0, health),
		maxHealth = math.max(0, maxHealth),
	}
end

track(view.SocialButton.Activated:Connect(toggleMenu))
track(view.HUDHeading.Activated:Connect(function()
	activeTab = "members"
	setMenuOpen(true)
end))
track(view.CloseButton.Activated:Connect(function()
	setMenuOpen(false)
end))
track(view.InviteTab.Activated:Connect(function()
	setActiveTab("invite")
end))
track(view.MembersTab.Activated:Connect(function()
	setActiveTab("members")
end))
track(view.LeaveButton.Activated:Connect(function()
	leaveRemote:FireServer()
end))
track(view.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if activeTab == "invite" then
		renderMenu()
	end
end))
track(view.AcceptButton.Activated:Connect(function()
	local invitation = currentInvitation
	if not invitation then
		return
	end
	respondRemote:FireServer(invitation.Id, true)
end))
track(view.DeclineButton.Activated:Connect(function()
	local invitation = currentInvitation
	if not invitation then
		return
	end
	respondRemote:FireServer(invitation.Id, false)
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and menuOpen then
		setMenuOpen(false)
	end
end))

track(snapshotRemote.OnClientEvent:Connect(function(nextSquadId: any, nextLeaderUserId: any, rawMembers: any)
	if nextSquadId ~= nil and typeof(nextSquadId) ~= "string" then
		return
	end
	if nextLeaderUserId ~= nil and (typeof(nextLeaderUserId) ~= "number" or nextLeaderUserId % 1 ~= 0) then
		return
	end
	if typeof(rawMembers) ~= "table" then
		return
	end

	local nextMembers: {SquadView.MemberData} = {}
	for _, raw in ipairs(rawMembers) do
		local valid = validateMember(raw)
		if valid then
			table.insert(nextMembers, valid)
		end
	end

	squadId = nextSquadId
	leaderUserId = nextLeaderUserId
	members = nextMembers
	rebuildMemberIds()
	view:UpdateHUD(members, player.UserId)
	renderMenu()
end))

track(invitationRemote.OnClientEvent:Connect(function(invitationId: any, senderUserId: any, expiresAt: any)
	if typeof(invitationId) ~= "string"
		or typeof(senderUserId) ~= "number"
		or senderUserId <= 0
		or senderUserId % 1 ~= 0
		or typeof(expiresAt) ~= "number" then
		return
	end

	currentInvitation = {
		Id = invitationId,
		SenderUserId = senderUserId,
		ExpiresAt = expiresAt,
	}

	local sender = Players:GetPlayerByUserId(senderUserId)
	local senderName = if sender then getCharacterName(sender) else "Squad leader"
	view:SetInvitationContent(senderName, expiresAt - serverNow())
	view:SetInvitationVisible(true)
end))

track(invitationResultRemote.OnClientEvent:Connect(function(invitationId: any, status: any)
	if typeof(invitationId) ~= "string" or typeof(status) ~= "string" then
		return
	end
	local invitation = currentInvitation
	if invitation and invitation.Id == invitationId and status ~= "pending" then
		clearInvitation()
	end
end))

track(noticeRemote.OnClientEvent:Connect(function(text: any)
	if typeof(text) == "string" and text ~= "" then
		view:ShowNotice(text)
	end
end))

local function bindPlayerIdentity(target: Player)
	track(target:GetAttributeChangedSignal("ShinobiDisplayName"):Connect(function()
		if activeTab == "invite" and menuOpen then
			renderMenu()
		end
	end))
end

rebuildPlayersMap()
for _, target in ipairs(Players:GetPlayers()) do
	bindPlayerIdentity(target)
end

track(Players.PlayerAdded:Connect(function(target)
	playersByUserId[target.UserId] = target
	bindPlayerIdentity(target)
	if activeTab == "invite" and menuOpen then
		renderMenu()
	end
end))

track(Players.PlayerRemoving:Connect(function(target)
	playersByUserId[target.UserId] = nil
	if activeTab == "invite" and menuOpen then
		renderMenu()
	end
end))

track(RunService.RenderStepped:Connect(function()
	if destroyed then
		return
	end
	view:UpdateMarkers(members, player.UserId, playersByUserId)

	local invitation = currentInvitation
	if invitation then
		local remaining = invitation.ExpiresAt - serverNow()
		if remaining <= 0 then
			-- Expiration is authoritative on the server. The local panel may hide at
			-- zero, while InvitationResult/notice will carry the final server state.
			clearInvitation()
		else
			local sender = Players:GetPlayerByUserId(invitation.SenderUserId)
			local senderName = if sender then getCharacterName(sender) else "Squad leader"
			view:SetInvitationContent(senderName, remaining)
		end
	end
end))

track(script.Destroying:Connect(function()
	if destroyed then
		return
	end
	destroyed = true
	if reducedMotionConnection and reducedMotionConnection.Connected then
		reducedMotionConnection:Disconnect()
		reducedMotionConnection = nil
	end
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	view:Destroy()
end))

requestStateRemote:FireServer()
renderMenu()

print("[SquadController] READY v1 candidate | Astra SquadUI | ServerAuthority=true")
