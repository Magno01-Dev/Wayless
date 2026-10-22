--!strict
-- WAYLESS Weather System v1.0 - TESTING / CANDIDATE
-- Shared, deterministic configuration. Never edit canonical gameplay systems here.
local Config = {}

Config.ZoneFolderName = "WAYLESS_WeatherZones"
Config.SharedFolderName = "WAYLESS_Weather"
Config.StateFolderName = "RegionStates"
Config.ZonePollSeconds = 0.25 -- Client position checks; independent from weather generation
Config.ZoneSwitchDelaySeconds = 0.8 -- Hysteresis against rapid border oscillation
Config.ServerScanSeconds = 2 -- Discovers regions without scanning the entire Workspace
Config.DurationMinSeconds = 360 -- 6 minutes
Config.DurationMaxSeconds = 720 -- 12 minutes
Config.TransitionSeconds = 10
Config.VisualEffectsEnabled = true
Config.DebugLog = false

-- Temperate: percentages totaling 100. The presets only affect probability, not gameplay.
-- Keys can be referenced by a WeatherZone part's Climate Attribute/StringValue.
Config.ClimateWeights = {
	temperate = { CLEAR = 40, CLOUDY = 25, LIGHT_RAIN = 18, HEAVY_RAIN = 10, FOG = 7 },
	coastal = { CLEAR = 32, CLOUDY = 24, LIGHT_RAIN = 25, HEAVY_RAIN = 15, FOG = 4 },
	mountain = { CLEAR = 26, CLOUDY = 27, LIGHT_RAIN = 12, HEAVY_RAIN = 9, FOG = 26 },
	arid = { CLEAR = 65, CLOUDY = 21, LIGHT_RAIN = 8, HEAVY_RAIN = 2, FOG = 4 },
}
Config.DefaultClimate = "temperate"

Config.WeatherTypes = { "CLEAR", "CLOUDY", "LIGHT_RAIN", "HEAVY_RAIN", "FOG" }
Config.RainIntensity = { CLEAR = 0, CLOUDY = 0, LIGHT_RAIN = 0.40, HEAVY_RAIN = 0.90, FOG = 0 }

-- Atmospheric numbers are targets, not global Roblox defaults.
-- "baseline" means respect the existing map lighting values.
Config.Visual = {
	CLEAR = { cover = "baseline", cloudDensity = "baseline", cloudColor = "baseline", exposureOffset = 0, atmosphereDensityOffset = 0, hazeOffset = 0 },
	CLOUDY = { cover = 0.60, cloudDensity = 0.62, cloudColor = Color3.fromRGB(207, 213, 220), exposureOffset = -0.12, atmosphereDensityOffset = 0.02, hazeOffset = 0.3 },
	LIGHT_RAIN = { cover = 0.73, cloudDensity = 0.78, cloudColor = Color3.fromRGB(145, 156, 168), exposureOffset = -0.22, atmosphereDensityOffset = 0.04, hazeOffset = 0.45 },
	HEAVY_RAIN = { cover = 0.88, cloudDensity = 0.92, cloudColor = Color3.fromRGB(96, 112, 130), exposureOffset = -0.43, atmosphereDensityOffset = 0.075, hazeOffset = 0.9 },
	FOG = { cover = 0.70, cloudDensity = 0.74, cloudColor = Color3.fromRGB(192, 204, 209), exposureOffset = -0.09, atmosphereDensityOffset = 0.20, hazeOffset = 2.0 },
}

-- Camera raindrops: not included in this v1 candidate (original Rain2 had allocation issues).
-- Third-party Rain source adapted for raycasts/limited sampling.
Config.Rain = {
	Volume = 0.32,
	QualityIntensityMultiplier = 0.85,
	TransitionSeconds = 6,
}

-- A part's custom Attribute is preferred; a matching StringValue/IntValue works too.
function Config.ReadZoneProperty(part: BasePart, propertyName: string): any
	local attribute = part:GetAttribute(propertyName)
	if attribute ~= nil then
		return attribute
	end
	local child = part:FindFirstChild(propertyName)
	if child and (child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue")) then
		return child.Value
	end
	return nil
end

function Config.GetRegionId(part: BasePart): string
	local value = Config.ReadZoneProperty(part, "RegionId")
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return part.Name
end

function Config.GetClimate(part: BasePart): string
	local value = Config.ReadZoneProperty(part, "Climate")
	if typeof(value) == "string" and Config.ClimateWeights[value] then
		return value
	end
	return Config.DefaultClimate
end

function Config.GetPriority(part: BasePart): number
	local value = Config.ReadZoneProperty(part, "Priority")
	return if typeof(value) == "number" then value else 0
end

return Config
