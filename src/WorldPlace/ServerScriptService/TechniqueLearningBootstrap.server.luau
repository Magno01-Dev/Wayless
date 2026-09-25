--!strict
-- ServerScriptService > TechniqueLearningBootstrap
--
-- Starts the learned-technique persistence and centralized developer bypass.

local ServerScriptService =
	game:GetService("ServerScriptService")

local TechniqueLearningService = require(
	ServerScriptService:
		WaitForChild("Services"):
		WaitForChild("TechniqueLearningService")
)

TechniqueLearningService.Start()

print(
	"[TechniqueLearningBootstrap] READY v1"
)
