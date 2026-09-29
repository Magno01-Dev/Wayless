--!strict
-- ServerScriptService > SquadBootstrap
-- Starts the server-authoritative WAYLESS Squad service.

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")
local SquadService = require(Services:WaitForChild("SquadService"))

SquadService.Start()
