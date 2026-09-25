--!strict
-- CombatTagService v1
-- PLACE AS ModuleScript:
-- ServerScriptService > CombatTagService
--
-- Central server authority for PvP combat tags.
--
-- Rules:
-- - Tags last 90 seconds.
-- - Each attacker/source has an independent timer on the victim.
-- - Repeated valid damage from the same source refreshes ONLY that source's timer.
-- - Hitting someone tags the VICTIM, not the attacker.
-- - Other systems can call Tag(victim, source) for non-damage interactions
--   such as Carry.
-- - "mb all" is implemented by CombatTagServer and calls ClearTagsPlacedBy().
-- - Player/Character attributes:
--     CombatTagged: boolean
--     CombatTagMaxExpiresAt: number
--
-- Client detail snapshots are sent only to the tagged player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local CombatTagService = {}

local DEFAULT_TAG_DURATION = 90
local CLEANUP_INTERVAL = 0.25

type TagEntry = {
	sourceUserId: number,
	sourceName: string,
	sourceDisplayName: string,
	expiresAt: number,
}

local tagsByVictim: {[Player]: {[number]: TagEntry}} = {}

local started = false
local cleanupAccumulator = 0


-- ============================================================
-- REMOTES
-- ============================================================

local remotes =
	ReplicatedStorage:FindFirstChild(
		"CombatTagRemotes"
	) :: Folder?

if not remotes then
	local created = Instance.new("Folder")
	created.Name = "CombatTagRemotes"
	created.Parent = ReplicatedStorage
	remotes = created
end

local updateRemote =
	remotes:FindFirstChild(
		"CombatTagUpdate"
	) :: RemoteEvent?

if not updateRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagUpdate"
	created.Parent = remotes
	updateRemote = created
end

local requestSnapshotRemote =
	remotes:FindFirstChild(
		"CombatTagRequestSnapshot"
	) :: RemoteEvent?

if not requestSnapshotRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagRequestSnapshot"
	created.Parent = remotes
	requestSnapshotRemote = created
end

local resetAttemptRemote =
	remotes:FindFirstChild(
		"CombatTagResetAttempt"
	) :: RemoteEvent?

if not resetAttemptRemote then
	local created = Instance.new("RemoteEvent")
	created.Name = "CombatTagResetAttempt"
	created.Parent = remotes
	resetAttemptRemote = created
end


-- ============================================================
-- SERVER-ONLY EVENTS FOR FUTURE LIVES / PERMADEATH
-- ============================================================

local internalFolder =
	ServerStorage:FindFirstChild(
		"CombatTagInternal"
	) :: Folder?

if not internalFolder then
	local created = Instance.new("Folder")
	created.Name = "CombatTagInternal"
	created.Parent = ServerStorage
	internalFolder = created
end

local combatLogDetected =
	internalFolder:FindFirstChild(
		"CombatLogDetected"
	) :: BindableEvent?

if not combatLogDetected then
	local created = Instance.new("BindableEvent")
	created.Name = "CombatLogDetected"
	created.Parent = internalFolder
	combatLogDetected = created
end

local combatRespawnAttempt =
	internalFolder:FindFirstChild(
		"CombatRespawnAttempt"
	) :: BindableEvent?

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


local function setCharacterAttributes(
	character: Model?,
	active: boolean,
	maxExpiresAt: number
)
	if not character then
		return
	end

	character:SetAttribute("CombatTagged", active)
	character:SetAttribute("CombatTagMaxExpiresAt", maxExpiresAt)
end


local function buildSnapshot(
	victim: Player
): {any}

	local victimTags =
		tagsByVictim[victim]

	if not victimTags then
		return {}
	end

	local currentTime = now()
	local snapshot = {}

	for _, entry in pairs(victimTags) do
		if entry.expiresAt > currentTime then
			table.insert(snapshot, {
				sourceUserId = entry.sourceUserId,
				sourceName = entry.sourceName,
				sourceDisplayName = entry.sourceDisplayName,
				expiresAt = entry.expiresAt,
			})
		end
	end

	table.sort(snapshot, function(a, b)
		if a.expiresAt == b.expiresAt then
			return string.lower(a.sourceName)
				< string.lower(b.sourceName)
		end

		return a.expiresAt > b.expiresAt
	end)

	return snapshot
end


local function publishVictimState(
	victim: Player
)
	if not victim.Parent then
		return
	end

	local snapshot =
		buildSnapshot(victim)

	local active =
		#snapshot > 0

	local maxExpiresAt = 0

	for _, entry in ipairs(snapshot) do
		maxExpiresAt =
			math.max(
				maxExpiresAt,
				entry.expiresAt
			)
	end

	victim:SetAttribute(
		"CombatTagged",
		active
	)

	victim:SetAttribute(
		"CombatTagMaxExpiresAt",
		maxExpiresAt
	)

	setCharacterAttributes(
		victim.Character,
		active,
		maxExpiresAt
	)

	updateRemote:FireClient(
		victim,
		snapshot
	)
end


local function pruneVictim(
	victim: Player,
	publish: boolean
): boolean

	local victimTags =
		tagsByVictim[victim]

	if not victimTags then
		if publish then
			publishVictimState(victim)
		end

		return false
	end

	local currentTime = now()
	local changed = false

	for sourceUserId, entry in pairs(victimTags) do
		if entry.expiresAt <= currentTime then
			victimTags[sourceUserId] = nil
			changed = true
		end
	end

	if next(victimTags) == nil then
		tagsByVictim[victim] = nil
	end

	if publish and changed then
		publishVictimState(victim)
	end

	return changed
end


-- ============================================================
-- PUBLIC API
-- ============================================================

function CombatTagService.Tag(
	victim: Player,
	source: Player,
	duration: number?
): boolean

	if typeof(victim) ~= "Instance"
		or not victim:IsA("Player")
		or typeof(source) ~= "Instance"
		or not source:IsA("Player") then

		return false
	end

	if victim == source then
		return false
	end

	if not victim.Parent then
		return false
	end

	local tagDuration =
		duration or DEFAULT_TAG_DURATION

	if typeof(tagDuration) ~= "number"
		or tagDuration ~= tagDuration
		or tagDuration <= 0 then

		tagDuration =
			DEFAULT_TAG_DURATION
	end

	local victimTags =
		tagsByVictim[victim]

	if not victimTags then
		victimTags = {}
		tagsByVictim[victim] = victimTags
	end

	victimTags[source.UserId] = {
		sourceUserId = source.UserId,
		sourceName = source.Name,
		sourceDisplayName = source.DisplayName,
		expiresAt = now() + tagDuration,
	}

	publishVictimState(victim)

	return true
end


function CombatTagService.ClearTagsPlacedBy(
	source: Player
): number

	if typeof(source) ~= "Instance"
		or not source:IsA("Player") then

		return 0
	end

	local removed = 0
	local affectedVictims: {Player} = {}

	for victim, victimTags in pairs(tagsByVictim) do
		if victimTags[source.UserId] then
			victimTags[source.UserId] = nil
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

	return removed
end


function CombatTagService.ClearAll(
	victim: Player,
	_reason: string?
)
	if typeof(victim) ~= "Instance"
		or not victim:IsA("Player") then

		return
	end

	tagsByVictim[victim] = nil

	if victim.Parent then
		publishVictimState(victim)
	end
end


function CombatTagService.IsTagged(
	victim: Player
): boolean

	if typeof(victim) ~= "Instance"
		or not victim:IsA("Player") then

		return false
	end

	pruneVictim(victim, false)

	local victimTags =
		tagsByVictim[victim]

	return victimTags ~= nil
		and next(victimTags) ~= nil
end


function CombatTagService.GetSnapshot(
	victim: Player
): {any}

	if typeof(victim) ~= "Instance"
		or not victim:IsA("Player") then

		return {}
	end

	pruneVictim(victim, false)

	return buildSnapshot(victim)
end


function CombatTagService.SyncCharacter(
	player: Player,
	character: Model?
)
	if not character then
		return
	end

	pruneVictim(player, false)

	local snapshot =
		buildSnapshot(player)

	local active =
		#snapshot > 0

	local maxExpiresAt = 0

	for _, entry in ipairs(snapshot) do
		maxExpiresAt =
			math.max(
				maxExpiresAt,
				entry.expiresAt
			)
	end

	player:SetAttribute(
		"CombatTagged",
		active
	)

	player:SetAttribute(
		"CombatTagMaxExpiresAt",
		maxExpiresAt
	)

	setCharacterAttributes(
		character,
		active,
		maxExpiresAt
	)
end


function CombatTagService.SendSnapshot(
	player: Player
)
	pruneVictim(player, false)
	publishVictimState(player)
end


function CombatTagService.RemoveVictimState(
	player: Player
)
	tagsByVictim[player] = nil
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

	requestSnapshotRemote.OnServerEvent:Connect(
		function(player: Player)
			CombatTagService.SendSnapshot(player)
		end
	)

	resetAttemptRemote.OnServerEvent:Connect(
		function(player: Player)
			if CombatTagService.IsTagged(player) then
				combatRespawnAttempt:Fire(
					player,
					CombatTagService.GetSnapshot(player)
				)

				warn(
					"[CombatTag] blocked Reset attempt:",
					player.Name
				)
			end
		end
	)

	RunService.Heartbeat:Connect(
		function(deltaTime: number)
			cleanupAccumulator += deltaTime

			if cleanupAccumulator <
				CLEANUP_INTERVAL then

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
					tagsByVictim[victim] = nil
				end
			end
		end
	)
end


-- Exposed for CombatTagServer's PlayerRemoving hook.
function CombatTagService.ReportCombatLog(
	player: Player
)
	if not CombatTagService.IsTagged(player) then
		return false
	end

	combatLogDetected:Fire(
		player,
		CombatTagService.GetSnapshot(player)
	)

	warn(
		"[CombatTag] COMBAT LOG detected:",
		player.Name
	)

	return true
end


return CombatTagService

