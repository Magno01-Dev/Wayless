--!strict
-- ServerScriptService > Services > FrontendServerBrowserService
--
-- WAYLESS Frontend server browser v2.
-- Reads live public World registrations and exposes player-facing metadata.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperiencePlaceConfig =
	require(Shared:WaitForChild("ExperiencePlaceConfig"))

local FrontendServerBrowserService = {}

local MAP_NAME = "WAYLESS_WorldServers_v1"
local STALE_SECONDS = 60
local PAGE_SIZE = 50
local MAX_RESULTS = 50
local QUICKPLAY_PING_TOLERANCE_MS = 25

local map = MemoryStoreService:GetHashMap(MAP_NAME)

local NAME_LEFT = {
	"Amber", "Ashen", "Autumn", "Bamboo", "Black", "Blue", "Brave", "Bronze",
	"Cedar", "Clouded", "Crimson", "Dawn", "Deep", "Dusk", "Ember", "Falling",
	"Frost", "Golden", "Green", "Hidden", "Hollow", "Iron", "Ivory", "Jade",
	"Lone", "Moonlit", "Mossy", "Night", "Quiet", "Red", "River", "Rising",
	"Scarlet", "Shadow", "Silent", "Silver", "Snow", "Soft", "Stone", "Storm",
	"Summer", "Swift", "Thunder", "Twilight", "Verdant", "White", "Wild", "Winter",
}

local NAME_RIGHT = {
	"Badger", "Bamboo", "Bear", "Blossom", "Cedar", "Crane", "Crow", "Deer",
	"Falcon", "Fern", "Fox", "Frog", "Hawk", "Heron", "Hound", "Koi",
	"Lantern", "Leopard", "Lotus", "Mantis", "Maple", "Moth", "Oak", "Orchid",
	"Otter", "Owl", "Pine", "Raven", "Reed", "River", "Sparrow", "Stag",
	"Swallow", "Tiger", "Toad", "Turtle", "Viper", "Willow", "Wolf", "Wren",
	"Cypress", "Petal", "Lily", "Birch", "Cicada", "Finch", "Iris", "Juniper",
}

local function stableHash(text: string): number
	local value = 5381
	for index = 1, #text do
		value = (value * 33 + string.byte(text, index)) % 2147483647
	end
	return value
end

local function fallbackDisplayName(jobId: string): string
	local hashA = stableHash(jobId)
	local hashB = stableHash(string.reverse(jobId) .. ":WAYLESS")
	return NAME_LEFT[(hashA % #NAME_LEFT) + 1]
		.. " "
		.. NAME_RIGHT[(hashB % #NAME_RIGHT) + 1]
end

local function shortSuffix(jobId: string): string
	local alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
	local value = stableHash(jobId .. ":suffix")
	local base = #alphabet
	local a = (value % base) + 1
	local b = (math.floor(value / base) % base) + 1
	return string.sub(alphabet, a, a) .. string.sub(alphabet, b, b)
end

local function worldPlaceId(): number
	return tonumber(ExperiencePlaceConfig.WorldPlaceId) or 0
end

local function cleanOptionalNumber(value: any): number?
	local numberValue = tonumber(value)
	if not numberValue or numberValue < 0 then
		return nil
	end
	return numberValue
end

local function sanitizeEntry(raw: any): {[string]: any}?
	if typeof(raw) ~= "table" then
		return nil
	end

	local jobId = raw.JobId
	if typeof(jobId) ~= "string" or jobId == "" then
		return nil
	end

	local placeId = tonumber(raw.PlaceId) or 0
	if placeId ~= worldPlaceId() then
		return nil
	end

	local updatedAt = tonumber(raw.UpdatedAt) or 0
	if os.time() - updatedAt > STALE_SECONDS then
		return nil
	end

	local players = math.max(0, math.floor(tonumber(raw.Players) or 0))
	local maxPlayers = math.max(1, math.floor(tonumber(raw.MaxPlayers) or 1))
	local displayName = raw.DisplayName
	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = fallbackDisplayName(jobId)
	end

	local regionLabel = raw.RegionLabel
	if typeof(regionLabel) ~= "string" or regionLabel == "" then
		regionLabel = "Unknown"
	end

	local regionCode = raw.RegionCode
	if typeof(regionCode) ~= "string" or regionCode == "" then
		regionCode = nil
	end

	local isFull = players >= maxPlayers
	local joinable = raw.Joinable ~= false and not isFull
	local estimatedPingMs = cleanOptionalNumber(raw.EstimatedPingMs)

	-- Return both the new UI schema and legacy names so old client builds remain compatible.
	return {
		serverId = jobId,
		displayName = displayName,
		playerCount = players,
		maxPlayers = maxPlayers,
		regionCode = regionCode,
		regionLabel = regionLabel,
		estimatedPingMs = estimatedPingMs,
		joinable = joinable,
		updatedAt = updatedAt,

		JobId = jobId,
		DisplayName = displayName,
		Players = players,
		MaxPlayers = maxPlayers,
		RegionCode = regionCode,
		RegionLabel = regionLabel,
		EstimatedPingMs = estimatedPingMs,
		Joinable = joinable,
		UpdatedAt = updatedAt,
		StartedAt = tonumber(raw.StartedAt) or updatedAt,
		IsFull = isFull,
	}
end

local function resolveDisplayNameCollisions(results: {any})
	local counts: {[string]: number} = {}
	for _, server in ipairs(results) do
		local name = tostring(server.DisplayName)
		counts[name] = (counts[name] or 0) + 1
	end

	for _, server in ipairs(results) do
		local name = tostring(server.DisplayName)
		if (counts[name] or 0) > 1 then
			local resolved = name .. " " .. shortSuffix(server.JobId)
			server.DisplayName = resolved
			server.displayName = resolved
		end
	end
end

function FrontendServerBrowserService.ListServers(): (boolean, string, {any})
	local results = {}

	local ok, err = pcall(function()
		local pages = map:ListItemsAsync(PAGE_SIZE)

		while true do
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local clean = sanitizeEntry(entry.value)

				if clean then
					table.insert(results, clean)

					if #results >= MAX_RESULTS then
						return
					end
				end
			end

			if pages.IsFinished then
				break
			end

			pages:AdvanceToNextPageAsync()
		end
	end)

	if not ok then
		warn("[FrontendServerBrowserService] LIST FAILED", err)
		return false, "ServerBrowserUnavailable", {}
	end

	resolveDisplayNameCollisions(results)

	table.sort(results, function(a, b)
		if a.Joinable ~= b.Joinable then
			return a.Joinable == true
		end

		if a.Players ~= b.Players then
			return a.Players > b.Players
		end

		return tostring(a.DisplayName) < tostring(b.DisplayName)
	end)

	return true, "ServersReady", results
end

function FrontendServerBrowserService.ValidateServer(
	jobId: string
): (boolean, string, {[string]: any}?)
	if typeof(jobId) ~= "string" or jobId == "" then
		return false, "InvalidServerId", nil
	end

	local raw: any = nil
	local ok, err = pcall(function()
		raw = map:GetAsync("job_" .. jobId)
	end)

	if not ok then
		warn("[FrontendServerBrowserService] VALIDATE FAILED", jobId, err)
		return false, "ServerBrowserUnavailable", nil
	end

	local clean = sanitizeEntry(raw)
	if not clean then
		return false, "ServerUnavailable", nil
	end

	if not clean.Joinable then
		return false, clean.IsFull and "ServerFull" or "ServerUnavailable", clean
	end

	return true, "ServerReady", clean
end

-- Future-ready quickplay policy. At present Roblox doesn't expose a direct,
-- per-target-server latency measurement to this frontend flow. If an authoritative
-- EstimatedPingMs source is added later, this method already implements the
-- desired 25 ms tolerance policy. Otherwise it returns nil so Roblox matchmaking
-- remains the honest fallback.
function FrontendServerBrowserService.ChooseQuickplay(servers: {any}?): {[string]: any}?
	local source = servers
	if typeof(source) ~= "table" then
		local ok, _, listed = FrontendServerBrowserService.ListServers()
		if not ok then
			return nil
		end
		source = listed
	end

	local eligible = {}
	local minPing: number? = nil

	for _, server in ipairs(source :: {any}) do
		if typeof(server) == "table" and server.Joinable == true then
			local ping = cleanOptionalNumber(server.EstimatedPingMs or server.estimatedPingMs)
			if ping then
				if not minPing or ping < minPing then
					minPing = ping
				end
			end
		end
	end

	if not minPing then
		return nil
	end

	for _, server in ipairs(source :: {any}) do
		if typeof(server) == "table" and server.Joinable == true then
			local ping = cleanOptionalNumber(server.EstimatedPingMs or server.estimatedPingMs)
			if ping and ping <= (minPing :: number) + QUICKPLAY_PING_TOLERANCE_MS then
				table.insert(eligible, server)
			end
		end
	end

	table.sort(eligible, function(a, b)
		local aPlayers = tonumber(a.Players or a.playerCount) or 0
		local bPlayers = tonumber(b.Players or b.playerCount) or 0
		if aPlayers ~= bPlayers then
			return aPlayers > bPlayers
		end
		local aPing = tonumber(a.EstimatedPingMs or a.estimatedPingMs) or math.huge
		local bPing = tonumber(b.EstimatedPingMs or b.estimatedPingMs) or math.huge
		if aPing ~= bPing then
			return aPing < bPing
		end
		return tostring(a.JobId or a.serverId) < tostring(b.JobId or b.serverId)
	end)

	return eligible[1]
end

print(
	"[FrontendServerBrowserService] READY v2"
		.. " | Map=" .. MAP_NAME
		.. " | StableNames=ON"
		.. " | RegionMetadata=OPTIONAL"
		.. " | QuickplayPingTolerance=" .. tostring(QUICKPLAY_PING_TOLERANCE_MS) .. "ms"
)

return FrontendServerBrowserService
