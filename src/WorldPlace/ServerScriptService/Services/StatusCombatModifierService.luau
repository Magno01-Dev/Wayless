--!strict
-- ServerScriptService > Services > StatusCombatModifierService
-- Server compatibility gateway using the same shared reader as clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Reader = require(
	ReplicatedStorage:
		WaitForChild("Shared"):
		WaitForChild("StatusCombatModifierReader")
)

print(
	"[StatusCombatModifierService] READY v1.1 SharedReader"
		.. " | Knockback=ON"
		.. " | GuardPressure=ON"
		.. " | Dash=ON"
		.. " | Jump=ON"
		.. " | AirControl=ON"
)

return Reader
