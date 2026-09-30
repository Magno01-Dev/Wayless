--!strict
-- ServerScriptService > Services > SquadService
-- WAYLESS Squad Service v1 candidate.
-- Server-authoritative, current-server-only squads for Astra SquadUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local SquadConfig = require(shared:WaitForChild("SquadConfig"))

local SquadService = {}
local started = false

export type MemberRecord = {
	Player: Player,
	UserId: number,
	IdentityKey: string,
	JoinOrder: number,
}

export type SquadRecord = {
	Id: string,
	LeaderUserId: number,
	Members: {[number]: MemberRecord},
	NextJoinOrder: number,
}

export type InvitationRecord = {
	Id: string,
	SquadId: string,
	SenderUserId: number,
	TargetUserId: number,
	ExpiresAt: number,
	Status: string,
}

type MemberConnections = {
	General: {RBXScriptConnection},
	Character: {RBXScriptConnection},
}

local squadsById: {[string]: SquadRecord} = {}
local squadIdByUserId: {[number]: string} = {}
local invitationsById: {[string]: InvitationRecord} = {}
local memberConnections: {[number]: MemberConnections} = {}
local lastInviteRequestAt: {[number]: number} = {}
local publishQueued: {[string]: boolean} = {}

local inviteRemote: RemoteEvent
local respondRemote: RemoteEvent
local removeRemote: RemoteEvent
local leaveRemote: RemoteEvent
local requestStateRemote: RemoteEvent
local snapshotRemote: RemoteEvent
local invitationRemote: RemoteEvent
local invitationResultRemote: RemoteEvent
local noticeRemote: RemoteEvent

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then
			return existing
		end
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getPlayer(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function getSquadForUserId(userId: number): SquadRecord?
	local squadId = squadIdByUserId[userId]
	if not squadId then
		return nil
	end
	return squadsById[squadId]
end

local function countMembers(squad: SquadRecord): number
	local count = 0
	for _ in pairs(squad.Members) do
		count += 1
	end
	return count
end

local function getCharacterName(player: Player): string
	local value = player:GetAttribute("ShinobiDisplayName")
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return player.DisplayName
end

local function getHealth(player: Player): (number, number)
	local character = player.Character
	if not character then
		return 0, 0
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return 0, 0
	end
	return math.max(0, humanoid.Health), math.max(0, humanoid.MaxHealth)
end

local function sendNotice(player: Player?, text: string)
	if player and player.Parent == Players then
		noticeRemote:FireClient(player, text)
	end
end

local function sendEmptySnapshot(player: Player)
	if player.Parent == Players then
		snapshotRemote:FireClient(player, nil, nil, {})
	end
end

local function buildMembersSnapshot(squad: SquadRecord): {{[string]: any}}
	local ordered: {MemberRecord} = {}
	for _, member in pairs(squad.Members) do
		table.insert(ordered, member)
	end
	table.sort(ordered, function(a, b)
		return a.JoinOrder < b.JoinOrder
	end)

	local result = {}
	for _, member in ipairs(ordered) do
		local health, maxHealth = getHealth(member.Player)
		table.insert(result, {
			UserId = member.UserId,
			characterName = getCharacterName(member.Player),
			username = member.Player.Name,
			identityKey = member.IdentityKey,
			health = health,
			maxHealth = maxHealth,
		})
	end
	return result
end

local function publishSnapshot(squad: SquadRecord)
	if squadsById[squad.Id] ~= squad then
		return
	end
	local payload = buildMembersSnapshot(squad)
	for _, member in pairs(squad.Members) do
		if member.Player.Parent == Players then
			snapshotRemote:FireClient(member.Player, squad.Id, squad.LeaderUserId, payload)
		end
	end
end

local function schedulePublish(squad: SquadRecord)
	if publishQueued[squad.Id] then
		return
	end
	publishQueued[squad.Id] = true
	task.delay(SquadConfig.SnapshotHealthThrottleSeconds, function()
		publishQueued[squad.Id] = nil
		if squadsById[squad.Id] == squad then
			publishSnapshot(squad)
		end
	end)
end

local function disconnectList(list: {RBXScriptConnection})
	for _, connection in ipairs(list) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(list)
end

local function disconnectMember(userId: number)
	local bundle = memberConnections[userId]
	if not bundle then
		return
	end
	disconnectList(bundle.General)
	disconnectList(bundle.Character)
	memberConnections[userId] = nil
end

local function bindCharacter(player: Player, squad: SquadRecord, bundle: MemberConnections, character: Model)
	disconnectList(bundle.Character)

	local function bindHumanoid(humanoid: Humanoid)
		table.insert(bundle.Character, humanoid.HealthChanged:Connect(function()
			if getSquadForUserId(player.UserId) == squad then
				schedulePublish(squad)
			end
		end))
		table.insert(bundle.Character, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			if getSquadForUserId(player.UserId) == squad then
				schedulePublish(squad)
			end
		end))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		bindHumanoid(humanoid)
	else
		table.insert(bundle.Character, character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") and getSquadForUserId(player.UserId) == squad then
				bindHumanoid(child)
				schedulePublish(squad)
			end
		end))
	end

	table.insert(bundle.Character, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and getSquadForUserId(player.UserId) == squad then
			schedulePublish(squad)
		end
	end))

	schedulePublish(squad)
end

local function bindMember(player: Player, squad: SquadRecord)
	disconnectMember(player.UserId)
	local bundle: MemberConnections = {
		General = {},
		Character = {},
	}
	memberConnections[player.UserId] = bundle

	table.insert(bundle.General, player.CharacterAdded:Connect(function(character)
		if getSquadForUserId(player.UserId) == squad then
			bindCharacter(player, squad, bundle, character)
		end
	end))

	table.insert(bundle.General, player:GetAttributeChangedSignal("ShinobiDisplayName"):Connect(function()
		if getSquadForUserId(player.UserId) == squad then
			schedulePublish(squad)
		end
	end))

	if player.Character then
		bindCharacter(player, squad, bundle, player.Character)
	else
		schedulePublish(squad)
	end
end

local function usedIdentities(squad: SquadRecord): {[string]: boolean}
	local used: {[string]: boolean} = {}
	for _, member in pairs(squad.Members) do
		used[member.IdentityKey] = true
	end
	return used
end

local function chooseIdentity(squad: SquadRecord): string?
	local used = usedIdentities(squad)
	for _, identity in ipairs(SquadConfig.Identities) do
		if not used[identity.Key] then
			return identity.Key
		end
	end
	return nil
end

local function addMember(squad: SquadRecord, player: Player): boolean
	if squad.Members[player.UserId] then
		return true
	end
	if squadIdByUserId[player.UserId] ~= nil then
		return false
	end
	if countMembers(squad) >= SquadConfig.MaxMembers then
		return false
	end

	local identityKey = chooseIdentity(squad)
	if not identityKey then
		return false
	end

	local joinOrder = squad.NextJoinOrder
	squad.NextJoinOrder += 1
	squad.Members[player.UserId] = {
		Player = player,
		UserId = player.UserId,
		IdentityKey = identityKey,
		JoinOrder = joinOrder,
	}
	squadIdByUserId[player.UserId] = squad.Id
	bindMember(player, squad)
	return true
end

local function createSquad(leader: Player): SquadRecord
	local squad: SquadRecord = {
		Id = HttpService:GenerateGUID(false),
		LeaderUserId = leader.UserId,
		Members = {},
		NextJoinOrder = 1,
	}
	squadsById[squad.Id] = squad
	if not addMember(squad, leader) then
		squadsById[squad.Id] = nil
		error("[SquadService] Failed to add leader to new squad")
	end
	return squad
end

local function setInvitationStatus(invitation: InvitationRecord, status: string)
	if invitation.Status ~= "pending" then
		return
	end
	invitation.Status = status
	local sender = getPlayer(invitation.SenderUserId)
	local target = getPlayer(invitation.TargetUserId)
	if sender then
		invitationResultRemote:FireClient(sender, invitation.Id, status)
	end
	if target then
		invitationResultRemote:FireClient(target, invitation.Id, status)
	end
end

local function cancelInvitationsForUser(userId: number)
	for _, invitation in pairs(invitationsById) do
		if invitation.Status == "pending"
			and (invitation.SenderUserId == userId or invitation.TargetUserId == userId) then
			setInvitationStatus(invitation, "cancelled")
		end
	end
end

local function cancelInvitationsForSquad(squadId: string)
	for _, invitation in pairs(invitationsById) do
		if invitation.Status == "pending" and invitation.SquadId == squadId then
			setInvitationStatus(invitation, "cancelled")
		end
	end
end

local function cancelInvalidInvitationsForSquad(squad: SquadRecord)
	local full = countMembers(squad) >= SquadConfig.MaxMembers
	for _, invitation in pairs(invitationsById) do
		if invitation.Status == "pending" and invitation.SquadId == squad.Id then
			local targetAlreadyGrouped = squadIdByUserId[invitation.TargetUserId] ~= nil
			local senderStillLeader = invitation.SenderUserId == squad.LeaderUserId
			if full or targetAlreadyGrouped or not senderStillLeader then
				setInvitationStatus(invitation, "cancelled")
			end
		end
	end
end

local function chooseSuccessor(squad: SquadRecord): number?
	local bestUserId: number? = nil
	local bestJoinOrder = math.huge
	for userId, member in pairs(squad.Members) do
		if member.JoinOrder < bestJoinOrder then
			bestJoinOrder = member.JoinOrder
			bestUserId = userId
		end
	end
	return bestUserId
end

local function disbandSquad(squad: SquadRecord)
	cancelInvitationsForSquad(squad.Id)
	for userId, member in pairs(squad.Members) do
		squadIdByUserId[userId] = nil
		disconnectMember(userId)
		sendEmptySnapshot(member.Player)
	end
	table.clear(squad.Members)
	squadsById[squad.Id] = nil
	publishQueued[squad.Id] = nil
end

local function removeMemberInternal(squad: SquadRecord, userId: number): Player?
	local member = squad.Members[userId]
	if not member then
		return nil
	end

	squad.Members[userId] = nil
	squadIdByUserId[userId] = nil
	disconnectMember(userId)
	cancelInvitationsForUser(userId)
	sendEmptySnapshot(member.Player)

	if countMembers(squad) == 0 then
		disbandSquad(squad)
		return member.Player
	end

	if squad.LeaderUserId == userId then
		local successor = chooseSuccessor(squad)
		if successor then
			squad.LeaderUserId = successor
		end
	end

	cancelInvalidInvitationsForSquad(squad)
	publishSnapshot(squad)
	return member.Player
end

local function validUserId(value: any): boolean
	return typeof(value) == "number" and value > 0 and value % 1 == 0
end

local function onInvite(sender: Player, rawTargetUserId: any)
	if not validUserId(rawTargetUserId) then
		return
	end
	local targetUserId = rawTargetUserId :: number
	if targetUserId == sender.UserId then
		sendNotice(sender, "You cannot invite yourself.")
		return
	end

	local now = serverNow()
	local lastAt = lastInviteRequestAt[sender.UserId] or -math.huge
	if now - lastAt < SquadConfig.InviteRequestCooldownSeconds then
		return
	end
	lastInviteRequestAt[sender.UserId] = now

	local target = getPlayer(targetUserId)
	if not target then
		sendNotice(sender, "That player is no longer in this server.")
		return
	end
	if getSquadForUserId(targetUserId) then
		sendNotice(sender, "That player is already in a squad.")
		return
	end

	local squad = getSquadForUserId(sender.UserId)
	if squad then
		if squad.LeaderUserId ~= sender.UserId then
			sendNotice(sender, "Only the squad leader can invite players.")
			return
		end
		if countMembers(squad) >= SquadConfig.MaxMembers then
			sendNotice(sender, "Squad is full.")
			return
		end
	else
		-- Astra contract: first valid invitation while solo creates the squad.
		squad = createSquad(sender)
		publishSnapshot(squad)
	end

	for _, invitation in pairs(invitationsById) do
		if invitation.Status == "pending"
			and invitation.SquadId == squad.Id
			and invitation.TargetUserId == targetUserId then
			sendNotice(sender, "An invitation to that player is already pending.")
			return
		end
	end

	local invitation: InvitationRecord = {
		Id = HttpService:GenerateGUID(false),
		SquadId = squad.Id,
		SenderUserId = sender.UserId,
		TargetUserId = targetUserId,
		ExpiresAt = now + SquadConfig.InvitationExpirySeconds,
		Status = "pending",
	}
	invitationsById[invitation.Id] = invitation

	invitationRemote:FireClient(target, invitation.Id, sender.UserId, invitation.ExpiresAt)
	sendNotice(sender, "Invitation sent to " .. getCharacterName(target) .. ".")
	sendNotice(target, "Squad invitation received from " .. getCharacterName(sender) .. ".")
end

local function onRespond(target: Player, invitationId: any, accept: any)
	if typeof(invitationId) ~= "string" or #invitationId > 80 or typeof(accept) ~= "boolean" then
		return
	end

	local invitation = invitationsById[invitationId]
	if not invitation or invitation.Status ~= "pending" or invitation.TargetUserId ~= target.UserId then
		return
	end

	if invitation.ExpiresAt <= serverNow() then
		setInvitationStatus(invitation, "expired")
		sendNotice(target, "Invitation expired.")
		return
	end

	if not accept then
		setInvitationStatus(invitation, "declined")
		local sender = getPlayer(invitation.SenderUserId)
		sendNotice(target, "Invitation declined.")
		if sender then
			sendNotice(sender, getCharacterName(target) .. " declined your invitation.")
		end
		return
	end

	if getSquadForUserId(target.UserId) then
		setInvitationStatus(invitation, "cancelled")
		return
	end

	local squad = squadsById[invitation.SquadId]
	if not squad
		or squad.LeaderUserId ~= invitation.SenderUserId
		or not squad.Members[invitation.SenderUserId] then
		setInvitationStatus(invitation, "cancelled")
		sendNotice(target, "That squad invitation is no longer valid.")
		return
	end
	if countMembers(squad) >= SquadConfig.MaxMembers then
		setInvitationStatus(invitation, "cancelled")
		sendNotice(target, "That squad is already full.")
		return
	end
	if not addMember(squad, target) then
		setInvitationStatus(invitation, "cancelled")
		return
	end

	setInvitationStatus(invitation, "accepted")
	-- Membership invalidates any other pending incoming/outgoing invitations for
	-- the joining player. The accepted invitation is already final and is kept.
	cancelInvitationsForUser(target.UserId)
	cancelInvalidInvitationsForSquad(squad)
	publishSnapshot(squad)

	local sender = getPlayer(invitation.SenderUserId)
	sendNotice(target, "You joined the squad.")
	if sender then
		sendNotice(sender, getCharacterName(target) .. " joined your squad.")
	end
end

local function onRemove(requester: Player, rawTargetUserId: any)
	if not validUserId(rawTargetUserId) then
		return
	end
	local targetUserId = rawTargetUserId :: number
	if targetUserId == requester.UserId then
		return
	end

	local squad = getSquadForUserId(requester.UserId)
	if not squad or squad.LeaderUserId ~= requester.UserId then
		sendNotice(requester, "Only the squad leader can remove members.")
		return
	end
	local member = squad.Members[targetUserId]
	if not member then
		return
	end

	local removedName = getCharacterName(member.Player)
	local removed = removeMemberInternal(squad, targetUserId)
	if removed then
		sendNotice(removed, "You were removed from the squad.")
	end
	if squadsById[squad.Id] == squad then
		for _, remaining in pairs(squad.Members) do
			sendNotice(remaining.Player, removedName .. " was removed from the squad.")
		end
	end
end

local function onLeave(player: Player, disconnected: boolean)
	local squad = getSquadForUserId(player.UserId)
	if not squad then
		return
	end

	local wasLeader = squad.LeaderUserId == player.UserId
	local leavingName = getCharacterName(player)
	removeMemberInternal(squad, player.UserId)

	if not disconnected then
		sendNotice(player, "You left the squad.")
	end

	if squadsById[squad.Id] == squad then
		local message = leavingName .. " left the squad."
		if wasLeader then
			local successor = getPlayer(squad.LeaderUserId)
			if successor then
				message ..= " " .. getCharacterName(successor) .. " is now the leader."
			end
		end
		for _, remaining in pairs(squad.Members) do
			sendNotice(remaining.Player, message)
		end
	end
end

local function sendCurrentState(player: Player)
	local squad = getSquadForUserId(player.UserId)
	if squad then
		snapshotRemote:FireClient(player, squad.Id, squad.LeaderUserId, buildMembersSnapshot(squad))
	else
		sendEmptySnapshot(player)
	end

	local now = serverNow()
	for _, invitation in pairs(invitationsById) do
		if invitation.Status == "pending"
			and invitation.TargetUserId == player.UserId
			and invitation.ExpiresAt > now then
			invitationRemote:FireClient(player, invitation.Id, invitation.SenderUserId, invitation.ExpiresAt)
		end
	end
end

local function expireInvitations()
	local now = serverNow()
	for invitationId, invitation in pairs(invitationsById) do
		if invitation.Status == "pending" and invitation.ExpiresAt <= now then
			setInvitationStatus(invitation, "expired")
			sendNotice(getPlayer(invitation.SenderUserId), "Invitation expired.")
			sendNotice(getPlayer(invitation.TargetUserId), "Invitation expired.")
		elseif invitation.Status ~= "pending" and invitation.ExpiresAt + 60 <= now then
			invitationsById[invitationId] = nil
		end
	end
end

function SquadService.Start()
	if started then
		return
	end
	started = true

	local folderName = SquadConfig.RemotesFolderName
	local existing = ReplicatedStorage:FindFirstChild(folderName)
	local folder: Folder
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = ReplicatedStorage
	end

	local names = SquadConfig.RemoteNames
	inviteRemote = getOrCreateRemoteEvent(folder, names.Invite)
	respondRemote = getOrCreateRemoteEvent(folder, names.Respond)
	removeRemote = getOrCreateRemoteEvent(folder, names.Remove)
	leaveRemote = getOrCreateRemoteEvent(folder, names.Leave)
	requestStateRemote = getOrCreateRemoteEvent(folder, names.RequestState)
	snapshotRemote = getOrCreateRemoteEvent(folder, names.SquadSnapshot)
	invitationRemote = getOrCreateRemoteEvent(folder, names.Invitation)
	invitationResultRemote = getOrCreateRemoteEvent(folder, names.InvitationResult)
	noticeRemote = getOrCreateRemoteEvent(folder, names.SquadNotice)

	inviteRemote.OnServerEvent:Connect(onInvite)
	respondRemote.OnServerEvent:Connect(onRespond)
	removeRemote.OnServerEvent:Connect(onRemove)
	leaveRemote.OnServerEvent:Connect(function(player)
		onLeave(player, false)
	end)
	requestStateRemote.OnServerEvent:Connect(sendCurrentState)

	Players.PlayerRemoving:Connect(function(player)
		cancelInvitationsForUser(player.UserId)
		onLeave(player, true)
		lastInviteRequestAt[player.UserId] = nil
	end)

	task.spawn(function()
		while started do
			expireInvitations()
			task.wait(0.5)
		end
	end)

	print("[SquadService] READY v1 candidate | MaxMembers=4 | InvitationExpiry=30s | LeaderSuccession=LongestTenured")
end

return SquadService
