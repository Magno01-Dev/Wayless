--!strict
-- ServerScriptService > WorldServerRegistryBootstrap

local ServerScriptService = game:GetService("ServerScriptService")

local service =
	require(
		ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("WorldServerRegistryService")
	)

service.Start()
