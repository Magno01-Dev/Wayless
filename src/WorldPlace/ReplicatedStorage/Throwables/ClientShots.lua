--[[
	Throwables.ClientShots · ModuleScript en ReplicatedStorage.Throwables (solo cliente)
	Registro de todos los proyectiles que este cliente está dibujando (propios y ajenos).
	Cada uno se simula localmente con Paths, usando el tiempo del servidor, así todos lo
	ven en el mismo lugar. El servidor solo manda eventos: impacto, desvío, fin.

	Identificador de cada proyectil: "<UserId>:<ThrowId>:<Index>"
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))
local Definitions = require(script.Parent:WaitForChild("Definitions"))
local Paths = require(script.Parent:WaitForChild("Paths"))
local Targets = require(script.Parent:WaitForChild("Targets"))
local Visuals = require(script.Parent:WaitForChild("Visuals"))

local ClientShots = {}

local entries = {} -- [id] = entrada
local throws = {} -- [throwKey] = { ids }

local localPlayer = Players.LocalPlayer

local function serverNow()
	return Workspace:GetServerTimeNow()
end

-- Ids de lanzamiento crecientes durante toda la sesión (sobreviven a reaparecer)
local lastThrowId = 0
function ClientShots.nextThrowId()
	lastThrowId += 1
	return lastThrowId
end

-- Cuántos proyectiles salen en un nivel (para la munición)
function ClientShots.shotCount(definition, level, oneHand)
	if not definition.Levels[level] then
		return math.huge
	end
	return #Paths.buildShots(definition, level, {
		Origin = Vector3.zero,
		Target = Vector3.new(0, 0, -20),
		Side = 1,
		OneHand = oneHand,
	})
end

function ClientShots.throwKey(ownerUserId, throwId)
	return tostring(ownerUserId) .. ":" .. tostring(throwId)
end

--[[
	packet = {
		OwnerUserId, ThrowId, Weapon, Kind ("Throw" | "Counter"), StartTime,
		Throw:   Level, Origin, Target, Side, OneHand
		Counter: Origin, Intercept, Arrival
	}
]]
function ClientShots.addThrow(packet, isLocal)
	local definition = Definitions[packet.Weapon]
	if typeof(definition) ~= "table" then
		return
	end

	local levelDef, built
	if packet.Kind == "Counter" then
		levelDef = definition.Levels[0]
		built = Paths.buildCounter(packet.Origin, packet.Intercept, packet.Arrival - packet.StartTime)
	else
		levelDef = definition.Levels[packet.Level]
		if not levelDef then
			return
		end
		built = Paths.buildShots(definition, packet.Level, packet)
	end

	local key = ClientShots.throwKey(packet.OwnerUserId, packet.ThrowId)
	local ids = {}
	throws[key] = ids

	Visuals.playSound(definition.Audio.Launch, packet.Origin)

	for _, shot in built do
		local id = key .. ":" .. shot.Index
		table.insert(ids, id)
		entries[id] = {
			Id = id,
			ThrowKey = key,
			OwnerUserId = packet.OwnerUserId,
			Local = isLocal == true,
			Definition = definition,
			LevelDef = levelDef,
			Shot = shot,
			StartTime = packet.StartTime,
			Handle = nil,
			PreviousPosition = nil,
			State = "Flying",
			Harmless = false,
			Hits = {},
			PredictedHit = false,
		}
	end
	return key
end

local function finish(entry)
	entry.State = "Done"
	if entry.Handle then
		Visuals.destroy(entry.Handle)
		entry.Handle = nil
	end
	entries[entry.Id] = nil
end

local function stick(entry, position, direction)
	entry.State = "Done"
	if entry.Handle then
		Visuals.stick(entry.Handle, position, direction, entry.Definition.EmbedDepth)
		entry.Handle = nil
	end
	Visuals.playSound(entry.Definition.Audio.Stick, position)
	entries[entry.Id] = nil
end

-- Proyectil con efecto al caer: queda quieto donde tocó, esperando el efecto del servidor
local function land(entry, position, direction)
	entry.State = "Landed"
	entry.PredictedAge = 0
	if entry.Handle then
		Visuals.place(entry.Handle, position - direction * 0.2, direction, 0)
		if entry.Handle.Trail then
			entry.Handle.Trail.Enabled = false
		end
	end
end

-- Lanzamiento rechazado por el servidor: desaparece sin efecto
function ClientShots.removeThrow(key)
	local ids = throws[key]
	if not ids then
		return
	end
	for _, id in ids do
		local entry = entries[id]
		if entry then
			finish(entry)
		end
	end
	throws[key] = nil
end

-- El servidor ajustó el tiempo de salida
function ClientShots.retime(key, startTime)
	local ids = throws[key]
	if not ids then
		return
	end
	for _, id in ids do
		local entry = entries[id]
		if entry then
			entry.StartTime = startTime
		end
	end
end

function ClientShots.get(id)
	return entries[id]
end

-- Kunai guiado propio que todavía vuela y no fue redirigido
function ClientShots.findRedirectable()
	local best = nil
	for _, entry in entries do
		if entry.Local and entry.State == "Flying" and not entry.Harmless and not entry.Redirected
			and entry.LevelDef.Redirect and (not best or entry.StartTime > best.StartTime) then
			best = entry
		end
	end
	return best
end

-- Posición actual de un proyectil (tiempo del servidor)
function ClientShots.currentPosition(entry)
	return Paths.evaluate(entry.Shot, serverNow() - entry.StartTime)
end

function ClientShots.onHit(id, position, result, pierce)
	local entry = entries[id]
	if entry and not entry.PredictedHit then
		Visuals.impact(position)
	end
	if result ~= "Substituted" then
		local definition = if entry then entry.Definition else nil
		if definition then
			Visuals.playSound(definition.Audio.Hit, position)
		end
	end
	if entry then
		entry.PredictedHit = false
		if not pierce then
			finish(entry)
		end
	end
end

function ClientShots.onDeflect(id, serverTime, position, velocity, harmless)
	local entry = entries[id]
	if not entry then
		return
	end
	entry.Shot.Override = {
		Time = serverTime - entry.StartTime,
		Segment = Paths.makeDeflect(position, velocity, harmless),
	}
	entry.Harmless = harmless
	entry.PreviousPosition = position
	entry.State = "Flying"
end

function ClientShots.onStop(id)
	local entry = entries[id]
	if entry then
		finish(entry)
	end
end

-- Amenazas ---------------------------------------------------------------------

-- Proyectil enemigo que pasará cerca de `position` dentro de `window` segundos
function ClientShots.findThreat(position, window, radius)
	local now = serverNow()
	local best = nil
	for _, entry in entries do
		if entry.OwnerUserId == localPlayer.UserId or entry.Harmless or entry.State ~= "Flying"
			or entry.Definition.Utility then
			continue
		end
		local t0 = now - entry.StartTime
		local dt = 0
		while dt <= window do
			local point = Paths.evaluate(entry.Shot, t0 + dt)
			if point and (point - position).Magnitude <= radius then
				if not best or dt < best.TimeToImpact then
					best = { Entry = entry, TimeToImpact = dt, ImpactTime = now + dt }
				end
				break
			end
			dt += 0.02
		end
	end
	return best
end

-- Punto y momento (tiempo del servidor) en que un proyectil lanzado desde `origin`
-- en `releaseTime` alcanza a la amenaza
function ClientShots.solveIntercept(entry, origin, releaseTime, speed, deadline)
	local t = releaseTime + 0.03
	while t <= deadline do
		local point = Paths.evaluate(entry.Shot, t - entry.StartTime)
		if point and (point - origin).Magnitude / speed <= t - releaseTime then
			return point, t
		end
		t += 0.01
	end
	return nil, nil
end

-- Paso por frame ------------------------------------------------------------------

function ClientShots.step(dt)
	local now = serverNow()
	local localCharacter = localPlayer.Character
	local localTargets = nil

	for _, entry in entries do
		if entry.State ~= "Flying" then
			continue
		end
		local t = now - entry.StartTime
		local position, velocity, finished = Paths.evaluate(entry.Shot, t)
		if not position then
			continue -- todavía en la mano (disparo escalonado)
		end

		if not entry.Handle then
			local owner = Players:GetPlayerByUserId(entry.OwnerUserId)
			entry.Handle = Visuals.createProjectile(entry.Definition, entry.LevelDef, owner and owner.Character)
		end

		local previous = entry.PreviousPosition or entry.Shot.Segments[1].P0
		local step = position - previous
		if step.Magnitude > 1e-3 then
			-- Mundo: se clava donde choca. Si el nivel tiene efecto al caer, se queda quieto
			-- ahí hasta que el servidor mande el efecto (explosión, humo, mina…)
			local hit = Targets.castWorld(previous, step, nil)
			if hit then
				local impact = entry.LevelDef.Impact
				if impact and impact.OnWorld and not entry.Harmless then
					land(entry, hit.Position, step.Unit)
				else
					stick(entry, hit.Position, step.Unit)
				end
				continue
			end

			-- Impacto previsto (solo proyectiles propios): respuesta inmediata
			if entry.Local and not entry.Harmless and not entry.PredictedHit then
				localTargets = localTargets or Targets.list(localCharacter)
				for _, target in localTargets do
					if entry.Hits[target.Character] then
						continue
					end
					local bottom, top = Targets.bodySegment(target.Root.Position)
					local distance, point = Targets.segmentDistance(previous, position, bottom, top)
					if distance <= entry.Definition.HitRadius + Config.BodyRadius then
						entry.Hits[target.Character] = true
						if not entry.Definition.Utility then
							Visuals.impact(point)
						end
						if not entry.LevelDef.Pierce then
							entry.PredictedHit = true
							if entry.Handle then
								Visuals.destroy(entry.Handle)
								entry.Handle = nil
							end
							entry.State = "Predicted"
						end
						break
					end
				end
				if entry.State ~= "Flying" then
					continue
				end
			end
		end

		Visuals.place(entry.Handle, position, velocity, dt)
		entry.PreviousPosition = position

		if finished then
			finish(entry)
		end
	end

	-- Los impactos previstos y los proyectiles caídos esperan al servidor unos instantes
	for _, entry in entries do
		if entry.State == "Predicted" or entry.State == "Landed" then
			entry.PredictedAge = (entry.PredictedAge or 0) + dt
			if entry.PredictedAge > 2 then
				finish(entry)
			end
		end
	end
end

return ClientShots
