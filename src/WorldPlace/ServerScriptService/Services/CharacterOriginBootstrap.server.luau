--!strict
-- ServerScriptService > CharacterOriginBootstrap
-- v1.3 Clan + KG Potential / CentralDevAccess / TeamTest compatible

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services =
	ServerScriptService:
	WaitForChild("Services")

local DeveloperAccessService =
	require(
		Services:
		WaitForChild(
			"DeveloperAccessService"
		)
	)

DeveloperAccessService.Start()

local originSystem = ReplicatedStorage:FindFirstChild("CharacterOriginSystem")
if not originSystem then
	originSystem = Instance.new("Folder")
	originSystem.Name = "CharacterOriginSystem"
	originSystem.Parent = ReplicatedStorage
end

local remotes = originSystem:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = originSystem
end

local function getRemoteFunction(name: string): RemoteFunction
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local request = getRemoteFunction("CharacterOriginRequest")
local devRequest = getRemoteFunction("CharacterOriginDevRequest")

local CharacterOriginService = require(
	ServerScriptService:WaitForChild("Services"):WaitForChild("CharacterOriginService")
)

local function loadPlayer(player: Player)
	task.spawn(function()
		CharacterOriginService.LoadPlayer(player)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	loadPlayer(player)
end
Players.PlayerAdded:Connect(loadPlayer)
Players.PlayerRemoving:Connect(function(player)
	CharacterOriginService.UnloadPlayer(player)
end)

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	if typeof(action) ~= "string" then
		return { Ok = false, Reason = "InvalidAction" }
	end

	if action == "ChooseVillage" then
		local villageId = typeof(payload) == "table" and payload.VillageId or nil
		local ok, reason = CharacterOriginService.ChooseVillage(player, villageId)
		return { Ok = ok, Reason = reason }
	elseif action == "ChoosePrimaryNature" then
		local natureId = typeof(payload) == "table" and payload.NatureId or nil
		local ok, reason = CharacterOriginService.ChoosePrimaryNature(player, natureId)
		return { Ok = ok, Reason = reason }
	end

	return { Ok = false, Reason = "UnknownAction" }
end

devRequest.OnServerInvoke = function(player: Player, action: any, payload: any)
	if not DeveloperAccessService.IsDeveloper(
		player
		) then
		return {
			Ok = false,
			Reason = "NotDeveloper",
		}
	end

	if typeof(action) ~= "string" then
		return { Ok = false, Reason = "InvalidAction" }
	end

	local ok = false
	local reason = "UnknownAction"

	if action == "SetVillage" then
		local villageId = typeof(payload) == "table" and payload.VillageId or nil
		ok, reason = CharacterOriginService.DevSetVillage(player, villageId)
	elseif action == "SetAffiliation" then
		local villageId = typeof(payload) == "table" and payload.VillageId or nil
		ok, reason = CharacterOriginService.SetVillageAffiliation(player, villageId)
	elseif action == "SetRogue" then
		local isRogue = typeof(payload) == "table" and payload.IsRogue or false
		ok, reason = CharacterOriginService.SetRogueStatus(player, isRogue)
	elseif action == "SetPrimaryNature" then
		local natureId = typeof(payload) == "table" and payload.NatureId or nil
		ok, reason = CharacterOriginService.DevSetPrimaryNature(player, natureId)
	elseif action == "UnlockNature" then
		local natureId = typeof(payload) == "table" and payload.NatureId or nil
		ok, reason = CharacterOriginService.UnlockNature(player, natureId)
	elseif action == "SetClan" then
		local clanId =
			typeof(payload) == "table"
			and payload.ClanId
			or nil

		ok, reason =
			CharacterOriginService.DevSetClan(
				player,
				clanId
			)

	elseif action == "RandomizeClan" then
		ok, reason =
			CharacterOriginService.DevRandomizeClan(
				player
			)

	elseif action == "RegenerateGenetics" then
		ok, reason = CharacterOriginService.DevRegenerateGenetics(player)

	elseif action == "RerollKGPotential" then
		ok, reason = CharacterOriginService.RerollNaturalKGPotentialForNewLife(player)

	elseif action == "ForceKGPotential" then
		local qualified =
			typeof(payload) == "table"
			and payload.Qualified == true

		ok, reason =
			CharacterOriginService.DevForceNaturalKGPotential(
				player,
				qualified
			)

	elseif action == "Save" then
		ok = CharacterOriginService.SavePlayer(player, "DevManual")
		reason = ok and "Saved" or "SaveFailed"
	end

	return { Ok = ok, Reason = reason }
end

print(
	"[CharacterOriginBootstrap] READY v1.3 ClanKGPotential"
		.. " | ProductionCreationRemote=ON"
		.. " | CentralDevRemote=ON"
		.. " | TeamTestCompatible=ON"
		.. " | ClanDevActions=ON"
		.. " | KGPotentialDevActions=ON"
)
