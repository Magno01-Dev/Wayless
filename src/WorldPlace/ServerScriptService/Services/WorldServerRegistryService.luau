--!strict
-- ServerScriptService > Services > WorldServerRegistryService
--
-- WAYLESS public World server registry v2.
-- Publishes live public World server instances into MemoryStore for the Frontend.
-- Adds a stable player-facing server name and optional region metadata.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WorldServerRegistryService = {}

local MAP_NAME = "WAYLESS_WorldServers_v1" -- keep the existing map for migration compatibility
local HEARTBEAT_SECONDS = 15
local TTL_SECONDS = 45

local map = MemoryStoreService:GetHashMap(MAP_NAME)
local started = false
local startedAt = os.time()

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

local function stableDisplayName(jobId: string): string
	local hashA = stableHash(jobId)
	local hashB = stableHash(string.reverse(jobId) .. ":WAYLESS")
	local left = NAME_LEFT[(hashA % #NAME_LEFT) + 1]
	local right = NAME_RIGHT[(hashB % #NAME_RIGHT) + 1]
	return left .. " " .. right
end

local function readStringAttribute(instance: Instance, names: {string}): string?
	for _, name in ipairs(names) do
		local value = instance:GetAttribute(name)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

local function resolveRegion(): (string?, string)
	-- Roblox does not expose a simple in-experience datacenter-region property.
	-- If another allocator/resolver knows the real region, it can set either of
	-- these attributes and the registry will publish it. We intentionally do not
	-- substitute a player's country/locale because that would mislabel the server.
	local label =
		readStringAttribute(game, {"WAYLESS_ServerRegionLabel", "ServerRegionLabel"})
		or readStringAttribute(Workspace, {"WAYLESS_ServerRegionLabel", "ServerRegionLabel"})
	local code =
		readStringAttribute(game, {"WAYLESS_ServerRegionCode", "ServerRegionCode"})
		or readStringAttribute(Workspace, {"WAYLESS_ServerRegionCode", "ServerRegionCode"})

	if not label then
		return code, "Unknown"
	end

	return code, label
end

local function isPublicServer(): boolean
	return game.JobId ~= ""
		and game.PrivateServerId == ""
end

local function key(): string
	return "job_" .. game.JobId
end

local function payload(): {[string]: any}
	local regionCode, regionLabel = resolveRegion()
	local count = #Players:GetPlayers()
	local maxPlayers = math.max(1, Players.MaxPlayers)

	return {
		Version = 2,
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		DisplayName = stableDisplayName(game.JobId),
		Players = count,
		MaxPlayers = maxPlayers,
		Joinable = count < maxPlayers,
		RegionCode = regionCode,
		RegionLabel = regionLabel,
		StartedAt = startedAt,
		UpdatedAt = os.time(),
	}
end

local function publish()
	if not isPublicServer() then
		return
	end

	local ok, err = pcall(function()
		map:SetAsync(
			key(),
			payload(),
			TTL_SECONDS
		)
	end)

	if not ok then
		warn(
			"[WorldServerRegistryService] PUBLISH FAILED",
			err
		)
	end
end

function WorldServerRegistryService.PublishNow()
	publish()
end

function WorldServerRegistryService.Start()
	if started then
		return
	end

	started = true

	if not isPublicServer() then
		print(
			"[WorldServerRegistryService] READY v2"
				.. " | Registration=SKIPPED_NON_PUBLIC"
		)
		return
	end

	publish()

	Players.PlayerAdded:Connect(function()
		task.defer(publish)
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			task.wait()
			publish()
		end)
	end)

	-- If a future region resolver sets attributes after boot, republish immediately.
	for _, attributeName in ipairs({
		"WAYLESS_ServerRegionLabel",
		"ServerRegionLabel",
		"WAYLESS_ServerRegionCode",
		"ServerRegionCode",
		}) do
		game:GetAttributeChangedSignal(attributeName):Connect(function()
			task.defer(publish)
		end)
		Workspace:GetAttributeChangedSignal(attributeName):Connect(function()
			task.defer(publish)
		end)
	end

	task.spawn(function()
		while true do
			task.wait(HEARTBEAT_SECONDS)
			publish()
		end
	end)

	game:BindToClose(function()
		pcall(function()
			map:RemoveAsync(key())
		end)
	end)

	local _, regionLabel = resolveRegion()
	print(
		"[WorldServerRegistryService] READY v2"
			.. " | Map=" .. MAP_NAME
			.. " | Name=" .. stableDisplayName(game.JobId)
			.. " | Region=" .. regionLabel
			.. " | Heartbeat=" .. tostring(HEARTBEAT_SECONDS) .. "s"
	)
end

return WorldServerRegistryService
