--!strict
-- CombatTagService v2 - Player/NPC sources + Astra CombatTagHUD contract
-- PLACE AS ModuleScript:
-- ServerScriptService > CombatTagService
--
-- Server authority for combat tags.
--
-- Rules preserved:
-- - Tags last 90 seconds by default.
-- - Each source has an independent timer on the victim.
-- - Repeated valid damage from the same source refreshes ONLY that source timer.
-- - Hitting someone tags the VICTIM, not the attacker.
-- - Victims remain Players; sources may be Players or NPC Models.
-- - Incoming state is authoritative and sent only to the tagged player.
-- - Outgoing count is server-computed for the source player.
-- - Clear outgoing requests always clear source==requesting player only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local CombatTagService = {}

local DEFAULT_TAG_DURATION = 90
local CLEANUP_INTERVAL = 0.25
local NPC_SOURCE_ID_ATTRIBUTE = "CombatTagSourceId"

type SourceInstance = Player | Model

type TagEntry = {
	sourceId: string,
	sourceType: string,
	sourceUserId: number?,
	sourceName: string,
	sourceDisplayName: string,
	expiresAt: number,
}

local tagsByVictim: {[Player]: {[string]: TagEntry}} = {}

local started = false
local cleanupAccumulator = 0


-- ============================================================
-- REMOTES
-- ============================================================

local remotes = ReplicatedStorage:FindFirstChild("CombatTagRemotes") :: Folder?
if not remotes then
	local created = Instance.new("Folder")
	created.Name = "CombatTagRemotes"
	created.Parent = ReplicatedStorage
	remotes = created
end

local updateRemote = remotes:FindFirstChild("CombatTagUpdate") :: RemoteEvent?
if not updateRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagUpdate"
	created.Parent = remotes
	updateRemote = created
end

local requestSnapshotRemote = remotes:FindFirstChild("CombatTagRequestSnapshot") :: RemoteEvent?
if not requestSnapshotRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagRequestSnapshot"
	created.Parent = remotes
	requestSnapshotRemote = created
end

local resetAttemptRemote = remotes:FindFirstChild("CombatTagResetAttempt") :: RemoteEvent?
if not resetAttemptRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagResetAttempt"
	created.Parent = remotes
	resetAttemptRemote = created
end

local outgoingUpdateRemote = remotes:FindFirstChild("CombatTagOutgoingUpdate") :: RemoteEvent?
if not outgoingUpdateRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagOutgoingUpdate"
	created.Parent = remotes
	outgoingUpdateRemote = created
end

local clearOutgoingRequestRemote = remotes:FindFirstChild("CombatTagClearOutgoingRequest") :: RemoteEvent?
if not clearOutgoingRequestRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagClearOutgoingRequest"
	created.Parent = remotes
	clearOutgoingRequestRemote = created
end


-- ============================================================
-- SERVER-ONLY EVENTS FOR FUTURE LIVES / PERMADEATH
-- ============================================================

local internalFolder = ServerStorage:FindFirstChild("CombatTagInternal") :: Folder?
if not internalFolder then
	local created = Instance.new("Folder")
	created.Name = "CombatTagInternal"
	created.Parent = ServerStorage
	internalFolder = created
end

local combatLogDetected = internalFolder:FindFirstChild("CombatLogDetected") :: BindableEvent?
if not combatLogDetected then
	local created = Instance.new("BindableEvent")
	created.Name = "CombatLogDetected"
	created.Parent = internalFolder
	combatLogDetected = created
end

local combatRespawnAttempt = internalFolder:FindFirstChild("CombatRespawnAttempt") :: BindableEvent?
if not combatRespawnAttempt then
	local created = Instance.new("BindableEvent")
	created.Name = "CombatRespawnAttempt"
	created.Parent = internalFolder
	combatRespawnAttempt = created
end


-- ============================================================
-- HELPERS
-- ============================================================

local function now(): number
	return workspace:GetServerTimeNow()
end

local function playerSourceId(player: Player): string
	return "P:" .. tostring(player.UserId)
end

local function npcSourceId(model: Model): string
	local existing = model:GetAttribute(NPC_SOURCE_ID_ATTRIBUTE)
	if typeof(existing) == "string" and existing ~= "" then
		return "N:" .. existing
	end

	local generated = HttpService:GenerateGUID(false)
	model:SetAttribute(NPC_SOURCE_ID_ATTRIBUTE, generated)
	return "N:" .. generated
end

local function describeSource(source: SourceInstance): (string, string, number?, string, string)
	if source:IsA("Player") then
		return playerSourceId(source), "Player", source.UserId, source.Name, source.DisplayName
	end

	local displayAttribute = source:GetAttribute("CombatTagDisplayName")
	local displayName = source.Name
	if typeof(displayAttribute) == "string" and displayAttribute ~= "" then
		displayName = displayAttribute
	end

	return npcSourceId(source), "NPC", nil, source.Name, displayName
end

local function setCharacterAttributes(character: Model?, active: boolean, maxExpiresAt: number)
	if not character then
		return
	end

	character:SetAttribute("CombatTagged", active)
	character:SetAttribute("CombatTagMaxExpiresAt", maxExpiresAt)
end

local function buildSnapshot(victim: Player): {any}
	local victimTags = tagsByVictim[victim]
	if not victimTags then
		return {}
	end

	local currentTime = now()
	local snapshot = {}

	for _, entry in pairs(victimTags) do
		if entry.expiresAt > currentTime then
			table.insert(snapshot, {
				sourceId = entry.sourceId,
				sourceType = entry.sourceType,
				sourceUserId = entry.sourceUserId,
				sourceName = entry.sourceName,
				sourceDisplayName = entry.sourceDisplayName,
				expiresAt = entry.expiresAt,
			})
		end
	end

	table.sort(snapshot, function(a, b)
		if a.expiresAt == b.expiresAt then
			return string.lower(a.sourceDisplayName) < string.lower(b.sourceDisplayName)
		end
		return a.expiresAt > b.expiresAt
	end)

	return snapshot
end

local function countOutgoingForPlayer(source: Player): number
	local sourceId = playerSourceId(source)
	local currentTime = now()
	local count = 0

	for _, victimTags in pairs(tagsByVictim) do
		local entry = victimTags[sourceId]
		if entry and entry.expiresAt > currentTime then
			count += 1
		end
	end

	return count
end

local function publishOutgoingState(source: Player)
	if not source.Parent then
		return
	end

	outgoingUpdateRemote:FireClient(source, countOutgoingForPlayer(source))
end

local function publishOutgoingForUserId(userId: number)
	local source = Players:GetPlayerByUserId(userId)
	if source then
		publishOutgoingState(source)
	end
end

local function publishVictimState(victim: Player)
	if not victim.Parent then
		return
	end

	local snapshot = buildSnapshot(victim)
	local active = #snapshot > 0
	local maxExpiresAt = 0

	for _, entry in ipairs(snapshot) do
		maxExpiresAt = math.max(maxExpiresAt, entry.expiresAt)
	end

	victim:SetAttribute("CombatTagged", active)
	victim:SetAttribute("CombatTagMaxExpiresAt", maxExpiresAt)

	setCharacterAttributes(victim.Character, active, maxExpiresAt)
	updateRemote:FireClient(victim, snapshot)
end

local function pruneVictim(victim: Player, publish: boolean): boolean
	local victimTags = tagsByVictim[victim]
	if not victimTags then
		if publish then
			publishVictimState(victim)
		end
		return false
	end

	local currentTime = now()
	local changed = false
	local outgoingUsersToRefresh: {[number]: boolean} = {}

	for sourceId, entry in pairs(victimTags) do
		if entry.expiresAt <= currentTime then
			victimTags[sourceId] = nil
			changed = true
			if entry.sourceUserId then
				outgoingUsersToRefresh[entry.sourceUserId] = true
			end
		end
	end

	if next(victimTags) == nil then
		tagsByVictim[victim] = nil
	end

	if publish and changed then
		publishVictimState(victim)
	end

	for userId in pairs(outgoingUsersToRefresh) do
		publishOutgoingForUserId(userId)
	end

	return changed
end


-- ============================================================
-- PUBLIC API
-- ============================================================

function CombatTagService.Tag(victim: Player, source: SourceInstance, duration: number?): boolean
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return false
	end

	if typeof(source) ~= "Instance" or (not source:IsA("Player") and not source:IsA("Model")) then
		return false
	end

	if source:IsA("Player") and victim == source then
		return false
	end

	if not victim.Parent or not source.Parent then
		return false
	end

	local tagDuration = duration or DEFAULT_TAG_DURATION
	if typeof(tagDuration) ~= "number" or tagDuration ~= tagDuration or tagDuration <= 0 then
		tagDuration = DEFAULT_TAG_DURATION
	end

	local sourceId, sourceType, sourceUserId, sourceName, sourceDisplayName = describeSource(source)

	local victimTags = tagsByVictim[victim]
	if not victimTags then
		victimTags = {}
		tagsByVictim[victim] = victimTags
	end

	victimTags[sourceId] = {
		sourceId = sourceId,
		sourceType = sourceType,
		sourceUserId = sourceUserId,
		sourceName = sourceName,
		sourceDisplayName = sourceDisplayName,
		expiresAt = now() + tagDuration,
	}

	publishVictimState(victim)
	if source:IsA("Player") then
		publishOutgoingState(source)
	end

	return true
end

function CombatTagService.ClearTagsPlacedBy(source: Player): number
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return 0
	end

	local sourceId = playerSourceId(source)
	local removed = 0
	local affectedVictims: {Player} = {}

	for victim, victimTags in pairs(tagsByVictim) do
		if victimTags[sourceId] then
			victimTags[sourceId] = nil
			removed += 1
			table.insert(affectedVictims, victim)

			if next(victimTags) == nil then
				tagsByVictim[victim] = nil
			end
		end
	end

	for _, victim in ipairs(affectedVictims) do
		publishVictimState(victim)
	end

	publishOutgoingState(source)
	return removed
end

function CombatTagService.ClearAll(victim: Player, _reason: string?)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return
	end

	local victimTags = tagsByVictim[victim]
	local outgoingUsersToRefresh: {[number]: boolean} = {}
	if victimTags then
		for _, entry in pairs(victimTags) do
			if entry.sourceUserId then
				outgoingUsersToRefresh[entry.sourceUserId] = true
			end
		end
	end

	tagsByVictim[victim] = nil

	if victim.Parent then
		publishVictimState(victim)
	end

	for userId in pairs(outgoingUsersToRefresh) do
		publishOutgoingForUserId(userId)
	end
end

function CombatTagService.IsTagged(victim: Player): boolean
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return false
	end

	pruneVictim(victim, false)
	local victimTags = tagsByVictim[victim]
	return victimTags ~= nil and next(victimTags) ~= nil
end

function CombatTagService.GetSnapshot(victim: Player): {any}
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return {}
	end

	pruneVictim(victim, false)
	return buildSnapshot(victim)
end

function CombatTagService.GetOutgoingCount(source: Player): number
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return 0
	end
	return countOutgoingForPlayer(source)
end

function CombatTagService.SyncCharacter(player: Player, character: Model?)
	if not character then
		return
	end

	pruneVictim(player, false)
	local snapshot = buildSnapshot(player)
	local active = #snapshot > 0
	local maxExpiresAt = 0

	for _, entry in ipairs(snapshot) do
		maxExpiresAt = math.max(maxExpiresAt, entry.expiresAt)
	end

	player:SetAttribute("CombatTagged", active)
	player:SetAttribute("CombatTagMaxExpiresAt", maxExpiresAt)
	setCharacterAttributes(character, active, maxExpiresAt)
end

function CombatTagService.SendSnapshot(player: Player)
	pruneVictim(player, false)
	publishVictimState(player)
	publishOutgoingState(player)
end

function CombatTagService.RemoveVictimState(player: Player)
	local victimTags = tagsByVictim[player]
	local outgoingUsersToRefresh: {[number]: boolean} = {}

	if victimTags then
		for _, entry in pairs(victimTags) do
			if entry.sourceUserId then
				outgoingUsersToRefresh[entry.sourceUserId] = true
			end
		end
	end

	tagsByVictim[player] = nil

	for userId in pairs(outgoingUsersToRefresh) do
		publishOutgoingForUserId(userId)
	end
end

function CombatTagService.GetDefaultDuration(): number
	return DEFAULT_TAG_DURATION
end


-- ============================================================
-- START / EXPIRATION
-- ============================================================

function CombatTagService.Start()
	if started then
		return
	end
	started = true

	requestSnapshotRemote.OnServerEvent:Connect(function(player: Player)
		CombatTagService.SendSnapshot(player)
	end)

	clearOutgoingRequestRemote.OnServerEvent:Connect(function(player: Player)
		-- No source ID is accepted from the client. The requesting player is
		-- always the only source whose outgoing relationships may be cleared.
		CombatTagService.ClearTagsPlacedBy(player)
	end)

	resetAttemptRemote.OnServerEvent:Connect(function(player: Player)
		if CombatTagService.IsTagged(player) then
			combatRespawnAttempt:Fire(player, CombatTagService.GetSnapshot(player))
			warn("[CombatTag] blocked Reset attempt:", player.Name)
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime: number)
		cleanupAccumulator += deltaTime
		if cleanupAccumulator < CLEANUP_INTERVAL then
			return
		end
		cleanupAccumulator = 0

		local victims = {}
		for victim in pairs(tagsByVictim) do
			table.insert(victims, victim)
		end

		for _, victim in ipairs(victims) do
			if victim.Parent then
				pruneVictim(victim, true)
			else
				CombatTagService.RemoveVictimState(victim)
			end
		end
	end)
end

-- Exposed for CombatTagServer's PlayerRemoving hook.
function CombatTagService.ReportCombatLog(player: Player): boolean
	if not CombatTagService.IsTagged(player) then
		return false
	end

	combatLogDetected:Fire(player, CombatTagService.GetSnapshot(player))
	warn("[CombatTag] COMBAT LOG detected:", player.Name)
	return true
end

return CombatTagService
