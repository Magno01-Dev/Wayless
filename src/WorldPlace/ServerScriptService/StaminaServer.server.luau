-- StaminaServer v1
--
-- Install as:
-- ServerScriptService > StaminaServer (Script)

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

local StaminaService =
	require(
		ServerScriptService:
		WaitForChild(
			"StaminaService"
		)
	)


StaminaService.Start()
