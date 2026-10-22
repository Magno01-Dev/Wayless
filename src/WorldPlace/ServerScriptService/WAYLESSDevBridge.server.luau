--!strict
-- ServerScriptService > WAYLESSDevBridge
--
-- Small centralized bridge used by the unified WAYLESS developer menu.
--
-- Existing specialized server remotes stay authoritative for their own
-- systems. This bridge only handles common developer access/bypass state.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local ServerScriptService =
	game:GetService("ServerScriptService")

local DeveloperAccessService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("DeveloperAccessService")
)

DeveloperAccessService.Start()
local TechniqueLoadoutService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("TechniqueLoadoutService"))
local TechniqueRegistry = require(ServerScriptService:WaitForChild("Services"):WaitForChild("TechniqueRegistry"))
local NinjaBagService = require(ServerScriptService:WaitForChild("NinjaBagService"))
local InventoryCatalog = require(ReplicatedStorage:WaitForChild("InventoryCatalog"))
local MangekyoCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MangekyoCatalog"))
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WAYLESS_Weather"):WaitForChild("WeatherConfig"))
local originalClockTime = Lighting.ClockTime

local function clanDev(action: string, player: Player, value: any?): (boolean, string, any?)
	local internal = ServerStorage:FindFirstChild("JutsuInternal")
	local dev = internal and internal:FindFirstChild("ClanDev")
	if not dev or not dev:IsA("BindableFunction") then return false, "ClanDevNotReady", nil end
	local ok, result = pcall(function() return dev:Invoke(action, player, value) end)
	if not ok then return false, tostring(result), nil end
	if typeof(result) ~= "table" or result.Loaded ~= true then return false, "ClanProgressNotLoaded", result end
	return true, "ClanUpdatedPersistent", result
end

local remotes =
	ReplicatedStorage:
	FindFirstChild("Remotes")

if not remotes then
	remotes =
		Instance.new("Folder")

	remotes.Name =
		"Remotes"

	remotes.Parent =
		ReplicatedStorage
end

local existing =
	remotes:FindFirstChild(
		"WAYLESSDevRequest"
	)

if existing
	and not existing:IsA(
		"RemoteFunction"
	) then

	existing:Destroy()
	existing = nil
end

local request =
	existing :: RemoteFunction?

if not request then
	request =
		Instance.new(
			"RemoteFunction"
		)

	request.Name =
		"WAYLESSDevRequest"

	request.Parent =
		remotes
end

local function snapshot(
	player: Player
)
	return {
		IsDeveloper =
			DeveloperAccessService.IsDeveloper(
				player
			),

		ContentBypass =
			DeveloperAccessService.HasContentBypass(
				player
			),

		TechniqueLearnedCount =
			player:GetAttribute(
				"TechniqueLearnedCount"
			) or 0,

		TechniqueLearningReady =
			player:GetAttribute(
				"TechniqueLearningReady"
			) == true,
		InfiniteChakra = player:GetAttribute("DevInfiniteChakra") == true,
		ClanStage = player:GetAttribute("ClanAwakenStage"),
		WeatherRegionCount = (function()
			local regions = ReplicatedStorage:FindFirstChild("WAYLESS_Weather")
			regions = regions and regions:FindFirstChild(WeatherConfig.StateFolderName)
			return if regions then #regions:GetChildren() else 0
		end)(),
	}
end

(request :: RemoteFunction).OnServerInvoke =
	function(
		player: Player,
		action: string,
		value: any?
	)
	if not DeveloperAccessService.IsDeveloper(
		player
		) then

		return false,
			"NotDeveloper",
			nil
	end

	if action == "CanUse"
		or action == "GetStatus" then

		return true,
			"Authorized",
			snapshot(player)

	elseif action == "SetContentBypass" then
		local enabled =
			value == true

		local ok,
			reason =
			DeveloperAccessService
			.SetContentBypass(
				player,
				enabled
			)

		TechniqueLoadoutService.RefreshDevSlots(player)
		return ok, reason, snapshot(player)

	elseif action == "SetInfiniteChakra" then
		if typeof(value) ~= "boolean" then return false, "InvalidBoolean", nil end
		player:SetAttribute("DevInfiniteChakra", value)
		return true, (if value then "InfiniteChakraON" else "InfiniteChakraOFF"), snapshot(player)

	elseif action == "SetTime" then
		if value == "AUTO" then
			Lighting.ClockTime = originalClockTime
		elseif value == "DAY" then
			Lighting.ClockTime = 8
		elseif value == "AFTERNOON" then
			Lighting.ClockTime = 17
		elseif value == "NIGHT" then
			Lighting.ClockTime = 22
		else
			return false, "InvalidTime", nil
		end
		return true, "WorldClock=" .. tostring(value), Lighting.ClockTime

	elseif action == "SetWeather" then
		if typeof(value) ~= "string" then return false, "InvalidWeather", nil end
		if value ~= "AUTO" and not table.find(WeatherConfig.WeatherTypes, value) then return false, "InvalidWeather", nil end
		local parent = ReplicatedStorage:WaitForChild("WAYLESS_Weather")
		local regions = parent:FindFirstChild(WeatherConfig.StateFolderName)
		if not regions then return false, "WeatherRegionsNotReady", nil end
		local count = 0
		for _, region in ipairs(regions:GetChildren()) do
			if region:IsA("Folder") then
				region:SetAttribute("ForceWeather", (if value == "AUTO" then nil else value))
				count += 1
			end
		end
		return count > 0, "Weather=" .. value .. " Regions=" .. tostring(count), count

	elseif action == "ClanSetStage" or action == "ClanAwakenMangekyo" or action == "ClanSetMangekyoProperty" or action == "ClanResetEyeStrain" then
		if player:GetAttribute("ClanId") ~= "Uchiha" then return false, "RequiresUchiha", nil end
		if action == "ClanSetStage" then
			if typeof(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 3 then return false, "StageMustBe1To3", nil end
			return clanDev("SetStage", player, value)
		elseif action == "ClanAwakenMangekyo" then
			return clanDev("SetMangekyo", player, nil)
		elseif action == "ClanResetEyeStrain" then
			return clanDev("SetEyeStrain", player, 0)
		else
			if typeof(value) ~= "table" or typeof(value.Field) ~= "string" or typeof(value.Value) ~= "string" then return false, "InvalidProperty", nil end
			local field = value.Field
			local choice = value.Value
			local allowed = false
			if field == "Attack" then local v = MangekyoCatalog.Abilities.Attack[choice]; allowed = v ~= nil and v.Implemented ~= false end
			if field == "Control" then local v = MangekyoCatalog.Abilities.Control[choice]; allowed = v ~= nil and v.Implemented ~= false end
			if field == "Color" then allowed = MangekyoCatalog.Colors[choice] ~= nil end
			if field == "Weapon" then local v = MangekyoCatalog.Weapons[choice]; allowed = v ~= nil and v.Implemented ~= false end
			if not allowed then return false, "InvalidMangekyoChoice", nil end
			if (player:GetAttribute("ClanAwakenStage") or 0) < 4 then return false, "AwakenMangekyoFirst", nil end
			return clanDev("SetMangekyoProperty", player, value)
		end

	elseif action == "ListTechniques" then
		local list = {}
		for id, entry in pairs(TechniqueRegistry.GetAll()) do
			if not (entry.Module and entry.Module.NotEquippable == true) then
				table.insert(list, {Id=id, Label=tostring(entry.DisplayName or id), Category=tostring(entry.Category or "")})
			end
		end
		table.sort(list, function(a,b) return (a.Category .. a.Label .. a.Id) < (b.Category .. b.Label .. b.Id) end)
		return true, "Techniques=" .. tostring(#list), list

	elseif action == "SetDevTechniqueSlot" then
		if typeof(value) ~= "table" then return false, "InvalidPayload", nil end
		local ok, reason = TechniqueLoadoutService.SetDevSlot(player, value.Slot, value.Id)
		return ok, reason, nil

	elseif action == "ClearDevTechniqueSlots" then
		local ok, reason = TechniqueLoadoutService.ClearDevSlots(player)
		return ok, reason, nil

	elseif action == "SetNinjaBagSlot" then
		if typeof(value) ~= "table" or typeof(value.Slot) ~= "number" or value.Slot % 1 ~= 0 or value.Slot < 1 or value.Slot > 4 then return false, "InvalidBagSlot", nil end
		local name = value.ItemId
		if name == "" then name = nil end
		if name ~= nil then
			local info = typeof(name) == "string" and InventoryCatalog.GetItem(name)
			if not info or info.NinjaBagEquippable ~= true then return false, "InvalidThrowable", nil end
		end
		local char = player.Character
		local human = char and char:FindFirstChildOfClass("Humanoid")
		if not human or human.Health <= 0 then return false, "CharacterUnavailable", nil end
		for _, attr in ipairs({"CombatTagged","DownedActionLocked","IsDowned","IsCarried","IsCarrying","IsExecuting"}) do
			if char:GetAttribute(attr) == true then return false, "ActionLocked_" .. attr, nil end
		end
		if name and player:GetAttribute("NinjaBagUnlocked_" .. name) == false then return false, "ProjectileLocked", nil end
		local ok, reason = NinjaBagService.SetSlot(player, value.Slot, name)
		return ok, reason, nil
	end

	return false,
		"UnknownAction",
		nil
end

print(
	"[WAYLESSDevBridge] READY v1"
		.. " | UnifiedMenuAccess=ON"
		.. " | ContentBypassControl=ON"
)
