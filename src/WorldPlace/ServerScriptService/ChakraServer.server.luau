-- ChakraServer v1

local ServerScriptService =
	game:GetService("ServerScriptService")

local ChakraService =
	require(
		ServerScriptService:
		WaitForChild("ChakraService")
	)

ChakraService.Start()
