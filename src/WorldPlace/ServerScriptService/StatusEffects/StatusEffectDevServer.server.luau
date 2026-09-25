--!strict
-- DiabloStudios
-- ServerScriptService > StatusEffects > StatusEffectDevServer
--
-- Studio-only self-test endpoint. It is inert outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[StatusEffectDevServer] BOOT v1.1")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if not RunService:IsStudio() then
	return
end

local services = ServerScriptService:WaitForChild("Services")
local StatusEffectService =
	require(services:WaitForChild("StatusEffectService"))

local remotes =
	ReplicatedStorage:FindFirstChild("StatusEffectRemotes")

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "StatusEffectRemotes"
	remotes.Parent = ReplicatedStorage
end

local devApply =
	remotes:FindFirstChild("DevApply")

if not devApply then
	devApply = Instance.new("RemoteEvent")
	devApply.Name = "DevApply"
	devApply.Parent = remotes
end

local ALLOWED = {
	Poison = true,
	Bleed = true,
	Burn = true,
	Slow = true,
	Stun = true,
	ChakraSuppression = true,
}

(devApply :: RemoteEvent).OnServerEvent:Connect(function(
	player,
	action: string,
	effectId: string?
)
	local character = player.Character
	if not character then
		return
	end

	if action == "Clear" then
		StatusEffectService.Clear(character)
		return
	end

	if action ~= "Apply"
		or typeof(effectId) ~= "string"
		or not ALLOWED[effectId] then
		return
	end

	local ok, result =
		StatusEffectService.Apply(
			character,
			effectId,
			{
				SourcePlayer = player,
				SourceCharacter = character,
			}
		)

	print(
		"[StatusEffectDevServer]",
		player.Name,
		action,
		effectId,
		ok,
		result
	)
end)

print(
	"[StatusEffectDevServer] READY v1.1",
	"| StudioOnly=ON",
	"| Target=SELF_ONLY"
)
