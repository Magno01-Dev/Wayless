--!strict
-- WAYLESS Weather System v1.0 - TESTING / CANDIDATE
-- Authoritative per-region state; never modifies Lighting or player-owned rain objects.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

-- Model imported to Workspace is a staging artifact. Do not boot before installation.
while script:IsDescendantOf(Workspace) do
	task.wait(0.25)
end

local shared = ReplicatedStorage:WaitForChild("WAYLESS_Weather")
local Config = require(shared:WaitForChild("WeatherConfig"))
local rng = Random.new()

local zoneFolder = Workspace:FindFirstChild(Config.ZoneFolderName)
if not zoneFolder then
	zoneFolder = Instance.new("Folder")
	zoneFolder.Name = Config.ZoneFolderName
	zoneFolder.Parent = Workspace
	warn("[Weather] No zones installed yet; add BaseParts to Workspace." .. Config.ZoneFolderName)
end

-- Geometry descriptors live in ReplicatedStorage to remain available with StreamingEnabled.
-- Workspace parts are editable Studio authoring volumes, but clients never rely on their streaming.
local descriptors = shared:FindFirstChild("ZoneDescriptors")
if not descriptors then
	descriptors = Instance.new("Folder")
	descriptors.Name = "ZoneDescriptors"
	descriptors.Parent = shared
end

local states = shared:FindFirstChild(Config.StateFolderName)
if not states then
	states = Instance.new("Folder")
	states.Name = Config.StateFolderName
	states.Parent = shared
end

-- Each region owns an independent clock, generated server-side.
type Region = {
	folder: Folder,
	climate: string,
	lastType: string?,
	expiresAt: number,
	lastForce: string?,
}
local regions: {[string]: Region} = {}

local function chooseWeather(climate: string, avoid: string?): string
	local weights = Config.ClimateWeights[climate] or Config.ClimateWeights[Config.DefaultClimate]
	local total = 0
	for _, weatherType in ipairs(Config.WeatherTypes) do
		if weatherType ~= avoid then
			total += math.max(0, weights[weatherType] or 0)
		end
	end
	if total <= 0 then
		return "CLEAR"
	end
	local pick = rng:NextNumber(0, total)
	local accumulator = 0
	for _, weatherType in ipairs(Config.WeatherTypes) do
		if weatherType ~= avoid then
			accumulator += math.max(0, weights[weatherType] or 0)
			if pick <= accumulator then
				return weatherType
			end
		end
	end
	return "CLEAR"
end

local function publish(region: Region, weatherType: string, expiresAt: number)
	-- Individual attribute updates are eventually consistent; Type is written last.
	region.folder:SetAttribute("Intensity", Config.RainIntensity[weatherType] or 0)
	region.folder:SetAttribute("ExpiresAt", expiresAt)
	region.folder:SetAttribute("Climate", region.climate)
	region.folder:SetAttribute("Type", weatherType)
	region.lastType = weatherType
	region.expiresAt = expiresAt
end

local function scanZones(): {[string]: string}
	local climates: {[string]: string} = {}
	local liveZoneIds: {[string]: boolean} = {}
	for _, descendant in ipairs(zoneFolder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local id = Config.GetRegionId(descendant)
			if id ~= "" then
				-- An ID can span multiple boxes. Its climate comes from its first box.
				if not climates[id] then
					climates[id] = Config.GetClimate(descendant)
				end
				local zoneId = descendant:GetAttribute("WeatherZoneUUID")
				if typeof(zoneId) ~= "string" or zoneId == "" or liveZoneIds[zoneId] then
					zoneId = HttpService:GenerateGUID(false)
					descendant:SetAttribute("WeatherZoneUUID", zoneId)
				end
				liveZoneIds[zoneId] = true
				local descriptor = descriptors:FindFirstChild(zoneId)
				if not descriptor then
					descriptor = Instance.new("Folder")
					descriptor.Name = zoneId
					local cf = Instance.new("CFrameValue")
					cf.Name = "VolumeCFrame"
					cf.Parent = descriptor
					local size = Instance.new("Vector3Value")
					size.Name = "VolumeSize"
					size.Parent = descriptor
					descriptor.Parent = descriptors
				end
				descriptor:SetAttribute("RegionId", id)
				descriptor:SetAttribute("Priority", Config.GetPriority(descendant))
				local cf = descriptor:FindFirstChild("VolumeCFrame")
				local size = descriptor:FindFirstChild("VolumeSize")
				if cf and cf:IsA("CFrameValue") and cf.Value ~= descendant.CFrame then
					cf.Value = descendant.CFrame
				end
				if size and size:IsA("Vector3Value") and size.Value ~= descendant.Size then
					size.Value = descendant.Size
				end
			end
		end
	end
	for _, child in ipairs(descriptors:GetChildren()) do
		if not liveZoneIds[child.Name] then
			child:Destroy()
		end
	end
	return climates
end

local function refreshRegions()
	local climates = scanZones()
	for id, climate in pairs(climates) do
		local region = regions[id]
		if not region then
			local folder = Instance.new("Folder")
			folder.Name = id
			folder.Parent = states
			region = { folder = folder, climate = climate, lastType = nil, expiresAt = 0, lastForce = nil }
			regions[id] = region
		else
			region.climate = climate
		end
	end
	for id, region in pairs(regions) do
		if not climates[id] then
			region.folder:Destroy()
			regions[id] = nil
		end
	end
end

refreshRegions()

while true do
	refreshRegions()
	local now = Workspace:GetServerTimeNow()
	for _, region in pairs(regions) do
		-- SERVER-ONLY test hook. In Studio Server Command Bar:
		-- game.ReplicatedStorage.WAYLESS_Weather.RegionStates.REGION_ID:SetAttribute("ForceWeather", "HEAVY_RAIN")
		-- Clear with SetAttribute("ForceWeather", nil). Never expose a client RemoteEvent for this.
		local rawForce = region.folder:GetAttribute("ForceWeather")
		local force = if typeof(rawForce) == "string" and table.find(Config.WeatherTypes, rawForce) then rawForce else nil
		if force ~= region.lastForce then
			region.lastForce = force
			region.expiresAt = 0 -- Process force change / return to random immediately.
		end
		if now >= region.expiresAt then
			local nextType = force or chooseWeather(region.climate, region.lastType)
			local duration = rng:NextInteger(Config.DurationMinSeconds, Config.DurationMaxSeconds)
			publish(region, nextType, now + duration)
		end
	end
	task.wait(Config.ServerScanSeconds)
end
