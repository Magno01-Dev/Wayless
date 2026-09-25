--!strict
-- ServerScriptService > ShinobiMenuBootstrap
--
-- WAYLESS Shinobi Menu server bootstrap v2 - Technique Loadout.
--
-- Public player menu gateway.
-- This is NOT a developer remote.

local Players =
	game:GetService(
		"Players"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

local Services =
	ServerScriptService:
	WaitForChild(
		"Services"
	)

local TechniqueLearningService =
	require(
		Services:
		WaitForChild(
			"TechniqueLearningService"
		)
	)

local TechniqueLoadoutService =
	require(
		Services:
		WaitForChild(
			"TechniqueLoadoutService"
		)
	)

local ShinobiMenuService =
	require(
		Services:
		WaitForChild(
			"ShinobiMenuService"
		)
	)

TechniqueLearningService.Start()
TechniqueLoadoutService.Start()

local system =
	ReplicatedStorage:
	FindFirstChild(
		"ShinobiMenuSystem"
	)

if not system then
	system =
		Instance.new(
			"Folder"
		)

	system.Name =
		"ShinobiMenuSystem"

	system.Parent =
		ReplicatedStorage
end

local remotes =
	system:
	FindFirstChild(
		"Remotes"
	)

if not remotes then
	remotes =
		Instance.new(
			"Folder"
		)

	remotes.Name =
		"Remotes"

	remotes.Parent =
		system
end

local existing =
	remotes:
	FindFirstChild(
		"Request"
	)

local request: RemoteFunction

if existing
	and existing:IsA(
		"RemoteFunction"
	) then

	request =
		existing

else
	if existing then
		existing:Destroy()
	end

	request =
		Instance.new(
			"RemoteFunction"
		)

	request.Name =
		"Request"

	request.Parent =
		remotes
end

request.OnServerInvoke =
	function(
		player: Player,
		action: any,
		payload: any
	)
	if typeof(action)
		~= "string" then

		return {
			Ok = false,
			Reason =
				"InvalidAction",
		}
	end

	if action ==
		"GetTechniques" then

		return ShinobiMenuService
			.GetTechniqueSnapshot(
				player
			)
	end

	if action ==
		"UnlockTechnique" then

		local techniqueId =
			typeof(payload)
			== "table"
			and payload.TechniqueId
			or nil

		return ShinobiMenuService
			.UnlockTechnique(
				player,
				techniqueId
			)
	end

	if action ==
		"GetLoadout" then

		return ShinobiMenuService
			.GetLoadoutSnapshot(
				player
			)
	end

	if action ==
		"SetLoadoutSlot" then

		local slotIndex =
			typeof(payload)
			== "table"
			and payload.SlotIndex
			or nil

		local techniqueId =
			typeof(payload)
			== "table"
			and payload.TechniqueId
			or nil

		return ShinobiMenuService
			.SetLoadoutSlot(
				player,
				slotIndex,
				techniqueId
			)
	end

	return {
		Ok = false,
		Reason =
			"UnknownAction",
	}
end

Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)
			ShinobiMenuService
			.ForgetPlayer(
				player
			)
		end
	)

print(
	"[ShinobiMenuBootstrap] READY v2"
		.. " | Remote=ShinobiMenuSystem.Remotes.Request"
		.. " | PublicPlayerMenu=ON"
		.. " | TechniqueLoadout=10"
)
