--!strict
-- ServerScriptService > CharacterLifecycleBootstrap
--
-- WAYLESS Character Lifecycle Bootstrap v2.
--
-- Initializes CharacterId/LifeId lifecycle state.
-- The old "SimulateNewLife" dev action is intentionally disabled so no
-- developer button can silently mutate a live character's genetics/data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services =
	ServerScriptService:WaitForChild("Services")

local DeveloperAccessService =
	require(Services:WaitForChild("DeveloperAccessService"))

local CharacterSlotContextService =
	require(Services:WaitForChild("CharacterSlotContextService"))

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

local CharacterLifecycleService =
	require(Services:WaitForChild("CharacterLifecycleService"))

DeveloperAccessService.Start()
CharacterSlotContextService.Start()
CharacterLifeContextService.Start()

local lifecycleSystem =
	ReplicatedStorage:
	FindFirstChild(
		"CharacterLifecycleSystem"
	)

if not lifecycleSystem then
	lifecycleSystem =
		Instance.new("Folder")

	lifecycleSystem.Name =
		"CharacterLifecycleSystem"

	lifecycleSystem.Parent =
		ReplicatedStorage
end

local remotes =
	lifecycleSystem:
	FindFirstChild("Remotes")

if not remotes then
	remotes =
		Instance.new("Folder")

	remotes.Name = "Remotes"
	remotes.Parent = lifecycleSystem
end

local existing =
	remotes:
	FindFirstChild(
		"CharacterLifecycleDevRequest"
	)

local devRequest: RemoteFunction

if existing
	and existing:IsA("RemoteFunction") then

	devRequest = existing

else
	if existing then
		existing:Destroy()
	end

	devRequest =
		Instance.new("RemoteFunction")

	devRequest.Name =
		"CharacterLifecycleDevRequest"

	devRequest.Parent =
		remotes
end

local function initializePlayer(
	player: Player
)
	CharacterSlotContextService.EnsurePlayer(
		player
	)

	local ok, err =
		pcall(function()
			CharacterLifecycleService.InitializePlayer(
				player
			)
		end)

	if not ok then
		warn(
			"[CharacterLifecycleBootstrap] INIT FAILED",
			player.Name,
			err
		)
	end
end

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.spawn(
		initializePlayer,
		player
	)
end

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(
		initializePlayer,
		player
	)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	CharacterLifecycleService.ForgetPlayer(
		player
	)
end)

devRequest.OnServerInvoke =
	function(
		player: Player,
		action: any,
		_payload: any
	)
	if not DeveloperAccessService.IsDeveloper(
		player
		) then

		return {
			Ok = false,
			Reason = "NotDeveloper",
		}
	end

	if typeof(action) ~= "string" then
		return {
			Ok = false,
			Reason = "InvalidAction",
		}
	end

	if action == "GetState" then
		local state =
			CharacterLifecycleService.GetState(
				player
			)

		state.Ok = true
		state.Reason = "OK"

		return state
	end

	if action == "SimulateNewLife" then
		local state =
			CharacterLifecycleService.GetState(
				player
			)

		state.Ok = false
		state.Reason =
			"DirectNewLifeDeprecatedUseCharacterCreation"

		return state
	end

	return {
		Ok = false,
		Reason = "UnknownAction",
	}
end

print(
	"[CharacterLifecycleBootstrap] READY v2"
		.. " | CharacterLifeContext=ON"
		.. " | OldNewLifeSimulation=DISABLED"
		.. " | WipeRemote=OFF"
		.. " | TeamTestCompatible=ON"
)
