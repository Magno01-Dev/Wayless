--[[
	ThrowableRenderer · LocalScript en StarterPlayer.StarterPlayerScripts
	Dibuja todos los proyectiles (propios y de otros), los efectos al caer (Effects)
	y aplica los eventos del servidor.
	Vive fuera del personaje para seguir funcionando al morir o reaparecer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("Throwables")
local Definitions = require(folder:WaitForChild("Definitions"))
local ClientShots = require(folder:WaitForChild("ClientShots"))
local Visuals = require(folder:WaitForChild("Visuals"))
local Effects = require(folder:WaitForChild("Effects"))

local remotes = folder:WaitForChild("Remotes")
local spawnEvent = remotes:WaitForChild("Spawn")
local worldEvent = remotes:WaitForChild("World")
local resultEvent = remotes:WaitForChild("Result")
local effectEvent = remotes:WaitForChild("Effect")

local localPlayer = Players.LocalPlayer

RunService.RenderStepped:Connect(function(dt)
	ClientShots.step(dt)
	Visuals.updateCharges(Workspace:GetServerTimeNow(), dt)
	Effects.step(dt)
end)

-- Efectos de los lanzables de efecto (explosiones, humo, minas…)
effectEvent.OnClientEvent:Connect(function(kind, data)
	if typeof(data) == "table" and typeof(data.ShotId) == "string" then
		ClientShots.onStop(data.ShotId) -- el proyectil que lo causó desaparece
	end
	Effects.handle(kind, data)
end)

-- Lanzamientos de otros jugadores (los propios los agrega ThrowController al instante).
-- Los de técnicas (shurikenjutsu) los crea el servidor: se dibujan también los propios.
spawnEvent.OnClientEvent:Connect(function(packet)
	if typeof(packet) ~= "table" then
		return
	end
	local own = packet.OwnerUserId == localPlayer.UserId
	if packet.ServerSpawned then
		ClientShots.addThrow(packet, own)
	elseif not own then
		ClientShots.addThrow(packet, false)
	end
end)

-- Respuesta a los lanzamientos propios
resultEvent.OnClientEvent:Connect(function(throwId, approved, _reason, startTime)
	local key = ClientShots.throwKey(localPlayer.UserId, throwId)
	if not approved then
		ClientShots.removeThrow(key)
	elseif typeof(startTime) == "number" then
		ClientShots.retime(key, startTime)
	end
end)

worldEvent.OnClientEvent:Connect(function(kind, ...)
	if kind == "Hit" then
		local id, position, result, pierce = ...
		ClientShots.onHit(id, position, result, pierce)
	elseif kind == "Deflect" then
		local id, serverTime, position, velocity, harmless = ...
		ClientShots.onDeflect(id, serverTime, position, velocity, harmless)
	elseif kind == "Stop" then
		local id = ...
		ClientShots.onStop(id)
	elseif kind == "Clash" then
		local position = ...
		Visuals.clash(position)
	elseif kind == "ChargeBegin" then
		local player, weapon, oneHand, startedAt = ...
		local definition = Definitions[weapon]
		if player ~= localPlayer and player.Character and typeof(definition) == "table" then
			Visuals.startCharge(player.Character, definition, { StartedAt = startedAt, OneHand = oneHand })
		end
	elseif kind == "ChargeEnd" then
		local player = ...
		if player ~= localPlayer and player.Character then
			Visuals.stopCharge(player.Character)
		end
	end
end)
