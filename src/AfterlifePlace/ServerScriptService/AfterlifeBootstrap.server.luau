--!strict
-- ServerScriptService > AfterlifeBootstrap

local ServerScriptService =
	game:GetService("ServerScriptService")

local AfterlifeService =
	require(
		ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("AfterlifeService")
	)

AfterlifeService.Start()

print(
	"[AfterlifeBootstrap] READY v1"
)
