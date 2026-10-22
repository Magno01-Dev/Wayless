--!strict
-- ServerScriptService > CharacterIdentityBootstrap

local ServerScriptService =
	game:GetService("ServerScriptService")

local CharacterIdentityService =
	require(
		ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("CharacterIdentityService")
	)

CharacterIdentityService.Start()

print(
	"[CharacterIdentityBootstrap] READY v1"
)
