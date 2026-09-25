--!strict
-- ServerScriptService > ElementalCombatBootstrap

local ServerScriptService =
	game:GetService("ServerScriptService")

local ElementalCombatService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("ElementalCombatService")
)

ElementalCombatService.Start()

print(
	"[ElementalCombatBootstrap] READY v1"
)
