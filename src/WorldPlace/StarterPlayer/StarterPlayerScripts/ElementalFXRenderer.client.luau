--!nonstrict
-- StarterPlayer > StarterPlayerScripts > ElementalFXRenderer   (LocalScript)
--
-- Dibuja los VFX de los jutsus de Agua, Viento, Rayo y Tierra.
-- El servidor solo avisa por el RemoteEvent JutsuSystem > Remotes > ElementalFX;
-- los efectos están en ReplicatedStorage > JutsuSystem > ElementalFX (Water, Wind, Lightning, Earth).
--
-- Proyectiles: el servidor manda origen, dirección, velocidad y su hora; este script
-- calcula la posición cada frame (no se replica nada por frame) y recupera
-- suavemente el atraso del ping.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local jutsuSystem = ReplicatedStorage:WaitForChild("JutsuSystem")
local ElementalFX = require(jutsuSystem:WaitForChild("Shared"):WaitForChild("ElementalFX"))
local effectsFolder = jutsuSystem:WaitForChild("ElementalFX")
local Common = require(effectsFolder:WaitForChild("Common"))

local CATCH_UP_TIME = 0.12 -- qué tan rápido el proyectil alcanza su posición real
local MAX_SPAWN_LEAD = 0.12 -- adelanto máximo al aparecer

-- Registro: effects[NombreDelJutsu] = { Accion = función, Projectile = {...} }
local effects = {}
for _, moduleName in { "Water", "Wind", "Lightning", "Earth" } do
	local module = effectsFolder:WaitForChild(moduleName, 10)
	if module then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" then
			for kind, definition in result do
				effects[kind] = definition
			end
		else
			warn("[ElementalFX] No se pudo cargar " .. moduleName .. ": " .. tostring(result))
		end
	end
end

local function call(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[ElementalFX]", result)
		return nil
	end
	return result
end

-- Proyectiles -------------------------------------------------------------------------

local projectiles = {}

local function startProjectile(kind, data)
	local definition = effects[kind] and effects[kind].Projectile
	if not definition
		or typeof(data.Id) ~= "number"
		or typeof(data.Origin) ~= "Vector3"
		or typeof(data.Direction) ~= "Vector3"
		or typeof(data.Speed) ~= "number"
		or typeof(data.MaxDistance) ~= "number" then
		return
	end
	local state = call(definition.Create, data)
	if not state then
		return
	end
	local lag = math.max(0, Workspace:GetServerTimeNow() - (data.T or Workspace:GetServerTimeNow()))
	local lead = math.min(lag, MAX_SPAWN_LEAD)
	projectiles[data.Id] = {
		Definition = definition,
		State = state,
		Data = data,
		Offset = lead - lag, -- atraso visual (≤ 0) que se recupera de a poco
		Born = os.clock(),
		Position = data.Origin,
	}
end

local function endProjectile(data, reachedLimit)
	local projectile = projectiles[data.Id]
	if not projectile then
		return
	end
	projectiles[data.Id] = nil
	local hit = typeof(data.Position) == "Vector3"
	local position = if hit then data.Position else projectile.Position
	call(projectile.Definition.End, projectile.State, position, data.Normal, hit and not reachedLimit)
end

RunService.RenderStepped:Connect(function(deltaTime)
	local serverNow = Workspace:GetServerTimeNow()
	for id, projectile in projectiles do
		local data = projectile.Data
		if projectile.Offset < 0 then
			projectile.Offset *= math.exp(-deltaTime / CATCH_UP_TIME)
			if projectile.Offset > -0.001 then
				projectile.Offset = 0
			end
		end
		local elapsed = math.max(0, serverNow - data.T + projectile.Offset)
		local styled = Common.stylizedTime(elapsed)
		local travelled = math.min(styled * data.Speed, data.MaxDistance)
		local position = data.Origin + data.Direction * travelled
		projectile.Position = position
		call(projectile.Definition.Update, projectile.State, position, data.Direction, os.clock() - projectile.Born)

		-- Seguridad: si el aviso de fin no llega, se termina solo
		if elapsed > data.MaxDistance / data.Speed + 0.75 then
			endProjectile({ Id = id }, true)
		end
	end
end)

-- Avisos del servidor --------------------------------------------------------------------

ElementalFX.GetRemote().OnClientEvent:Connect(function(kind, action, data)
	if typeof(kind) ~= "string" or typeof(action) ~= "string" or typeof(data) ~= "table" then
		return
	end
	if action == "Projectile" then
		startProjectile(kind, data)
	elseif action == "ProjectileHit" then
		local projectile = projectiles[data.Id]
		if projectile and projectile.Definition.Hit and typeof(data.Position) == "Vector3" then
			call(projectile.Definition.Hit, projectile.State, data.Position, data.Normal)
		end
	elseif action == "ProjectileEnd" then
		endProjectile(data, false)
	else
		local definition = effects[kind]
		local handler = definition and definition[action]
		if typeof(handler) == "function" then
			call(handler, data)
		end
	end
end)
