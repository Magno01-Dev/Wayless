--!strict
-- WAYLESS Weather System v1.0 - TESTING / CANDIDATE
-- Client owns ONLY presentation. State authority and zone geometry come from the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("WAYLESS_Weather")
local Config = require(shared:WaitForChild("WeatherConfig"))
local descriptors = shared:WaitForChild("ZoneDescriptors")
local states = shared:WaitForChild(Config.StateFolderName)
local RainRenderer = require(script:WaitForChild("RainRenderer"))

local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Name = "WAYLESS_LocalWeatherClouds"
	clouds.Cover = 0.2
	clouds.Density = 0.35
	clouds.Parent = Workspace.Terrain
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "WAYLESS_LocalWeatherAtmosphere"
	atmosphere.Density = 0.12
	atmosphere.Haze = 0
	atmosphere.Parent = Lighting
end

local baseline = {
	exposure = Lighting.ExposureCompensation,
	cover = clouds.Cover,
	cloudDensity = clouds.Density,
	cloudColor = clouds.Color,
	atmosphereDensity = atmosphere.Density,
	haze = atmosphere.Haze,
}
local tweens: {Tween} = {}

local function playTween(object: Instance, goals: {[string]: any}, duration: number)
	local tween = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goals)
	table.insert(tweens, tween)
	tween:Play()
end

local function applyWeather(weatherType: string, intensity: number)
	if not Config.VisualEffectsEnabled then
		return
	end
	local profile = Config.Visual[weatherType] or Config.Visual.CLEAR
	for _, tween in ipairs(tweens) do
		tween:Cancel()
		tween:Destroy()
	end
	table.clear(tweens)
	local duration = Config.TransitionSeconds
	playTween(clouds, {
		Cover = if typeof(profile.cover) == "number" then profile.cover else baseline.cover,
		Density = if typeof(profile.cloudDensity) == "number" then profile.cloudDensity else baseline.cloudDensity,
		Color = if typeof(profile.cloudColor) == "Color3" then profile.cloudColor else baseline.cloudColor,
	}, duration)
	playTween(Lighting, { ExposureCompensation = math.clamp(baseline.exposure + profile.exposureOffset, -3, 3) }, duration)
	playTween(atmosphere, {
		Density = math.clamp(baseline.atmosphereDensity + profile.atmosphereDensityOffset, 0, 0.85),
		Haze = math.clamp(baseline.haze + profile.hazeOffset, 0, 10),
	}, duration)
	RainRenderer:SetIntensity(math.clamp(intensity, 0, 1), math.min(duration, Config.Rain.TransitionSeconds))
end

-- Region lookup uses server-published oriented volumes, not streamed Workspace parts.
-- A zone may be rotated; matching volumes with the same RegionId form a larger region.
local function getRegionAt(worldPosition: Vector3): string?
	local bestId: string? = nil
	local bestPriority = -math.huge
	local bestVolume = math.huge
	for _, descriptor in ipairs(descriptors:GetChildren()) do
		local regionId = descriptor:GetAttribute("RegionId")
		local priority = descriptor:GetAttribute("Priority")
		local cf = descriptor:FindFirstChild("VolumeCFrame")
		local sz = descriptor:FindFirstChild("VolumeSize")
		if typeof(regionId) == "string" and cf and sz and cf:IsA("CFrameValue") and sz:IsA("Vector3Value") then
			local p = cf.Value:PointToObjectSpace(worldPosition)
			local half = sz.Value * 0.5
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				local rank = if typeof(priority) == "number" then priority else 0
				local volume = sz.Value.X * sz.Value.Y * sz.Value.Z
				if rank > bestPriority or (rank == bestPriority and volume < bestVolume) then
					bestPriority = rank
					bestVolume = volume
					bestId = regionId
				end
			end
		end
	end
	return bestId
end

local currentRegion: string? = nil
local pendingRegion: string? = nil
local pendingSince = 0
local currentSignature: string? = nil

local function update()
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local found = if root and root:IsA("BasePart") then getRegionAt(root.Position) else nil
	if found ~= currentRegion then
		if found ~= pendingRegion then
			pendingRegion = found
			pendingSince = os.clock()
		elseif os.clock() - pendingSince >= Config.ZoneSwitchDelaySeconds then
			currentRegion = found
			currentSignature = nil
		end
	else
		pendingRegion = currentRegion
		pendingSince = os.clock()
	end

	local state = if currentRegion then states:FindFirstChild(currentRegion) else nil
	local weatherType = if state then state:GetAttribute("Type") else nil
	if typeof(weatherType) ~= "string" or not Config.Visual[weatherType] then
		weatherType = "CLEAR"
	end
	local intensity = if state then state:GetAttribute("Intensity") else nil
	if typeof(intensity) ~= "number" then
		intensity = 0
	end
	local signature = tostring(currentRegion) .. ":" .. weatherType .. ":" .. tostring(intensity)
	if signature ~= currentSignature then
		currentSignature = signature
		applyWeather(weatherType, intensity)
		if Config.DebugLog then
			print("[WAYLESS Weather] region=", currentRegion or "NONE", "type=", weatherType, "intensity=", intensity)
		end
	end
end

RainRenderer:Initialize(Config.Rain)
while script.Parent do
	update()
	task.wait(Config.ZonePollSeconds)
end
RainRenderer:SetIntensity(0, 0)
