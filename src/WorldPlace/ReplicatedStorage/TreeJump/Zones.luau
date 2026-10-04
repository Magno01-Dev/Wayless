--[[
	TreeJump.Zones · ModuleScript en ReplicatedStorage.TreeJump
	Registro de zonas, geometría, trayectoria y selección de objetivos.
	Lo usan el cliente (apuntar y volar) y el servidor (validar), así ambos calculan igual.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))

local Zones = {}

-- Registro (funciona con StreamingEnabled: las zonas entran y salen solas)
local registry = {}

local function track(instance)
	if instance:IsA("BasePart") then
		registry[instance] = true
	end
end

local function untrack(instance)
	registry[instance] = nil
end

CollectionService:GetInstanceAddedSignal(Config.ZoneTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(Config.ZoneTag):Connect(untrack)
for _, instance in CollectionService:GetTagged(Config.ZoneTag) do
	track(instance)
end

function Zones.isUsable(zone)
	return registry[zone] == true
		and zone:IsDescendantOf(Workspace)
		and zone:GetAttribute("Enabled") ~= false
		and zone.Size.X >= Config.MinZoneLength
		and zone.Size.Z >= Config.MinZoneWidth
end

-- Geometría -----------------------------------------------------------------

-- Extremos de la línea superior de la zona (donde se pisa)
function Zones.segment(zone)
	local cf, size = zone.CFrame, zone.Size
	local halfLength, top = size.X / 2, size.Y / 2
	return cf:PointToWorldSpace(Vector3.new(-halfLength, top, 0)), cf:PointToWorldSpace(Vector3.new(halfLength, top, 0))
end

function Zones.sourceBranch(zone)
	local source = zone:FindFirstChild("SourceBranch")
	return if source and source:IsA("ObjectValue") then source.Value else nil
end

function Zones.surface(zone)
	return zone:GetAttribute("Surface") or "Wood"
end

function Zones.closestPointOnSegment(point, a, b)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return a
	end
	return a + ab * math.clamp((point - a):Dot(ab) / lengthSq, 0, 1)
end

-- Punto del segmento más cercano a un rayo (donde apunta el jugador)
function Zones.closestPointToRay(a, b, origin, direction)
	local u = b - a
	local w = a - origin
	local uu, uv, vv = u:Dot(u), u:Dot(direction), direction:Dot(direction)
	local uw, vw = u:Dot(w), direction:Dot(w)
	local denominator = uu * vv - uv * uv
	local s = if denominator < 1e-6 then 0 else (uv * vw - vv * uw) / denominator
	return a + u * math.clamp(s, 0, 1)
end

-- Altura del HumanoidRootPart sobre el punto donde están los pies
function Zones.standOffset(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return root.Size.Y / 2 + 2
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

-- Zona sobre la que están parados los pies, si hay una
function Zones.zoneUnder(feet)
	local best, bestDistance = nil, math.huge
	for zone in registry do
		if (zone.Position - feet).Magnitude <= zone.Size.X / 2 + 3 and Zones.isUsable(zone) then
			local a, b = Zones.segment(zone)
			local point = Zones.closestPointOnSegment(feet, a, b)
			local vertical = math.abs(feet.Y - point.Y)
			local horizontal = Vector3.new(feet.X - point.X, 0, feet.Z - point.Z).Magnitude
			if vertical <= 1.5 and horizontal <= zone.Size.Z / 2 + 0.75 and vertical + horizontal < bestDistance then
				best, bestDistance = zone, vertical + horizontal
			end
		end
	end
	return best
end

-- Trayectoria ---------------------------------------------------------------

function Zones.trajectory(startPosition, endPosition, chainIndex)
	local delta = endPosition - startPosition
	local distance = delta.Magnitude
	local speedup = math.min((chainIndex or 0) * Config.ChainSpeedup, Config.MaxChainSpeedup)
	local duration = math.clamp(Config.DurationPerSqrtStud * math.sqrt(distance), Config.MinDuration, Config.MaxDuration)
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	return {
		Start = startPosition,
		End = endPosition,
		Duration = duration * (1 - speedup),
		Arc = math.clamp(horizontal * Config.ArcPerStud, Config.MinArc, Config.MaxArc),
	}
end

-- s = fracción del tiempo (0 a 1). Devuelve posición y velocidad.
-- El tiempo se deforma: sale rápido, flota cerca del punto alto y cae rápido.
function Zones.evaluate(trajectory, s)
	local k = Config.TimingWarp
	local twoPi = 2 * math.pi
	local u = s + k * math.sin(twoPi * s) / twoPi
	local du = 1 + k * math.cos(twoPi * s)
	local delta = trajectory.End - trajectory.Start
	local arc = trajectory.Arc
	local position = trajectory.Start + delta * u + Vector3.yAxis * (arc * 4 * u * (1 - u))
	local tangent = delta + Vector3.yAxis * (arc * 4 * (1 - 2 * u))
	return position, tangent * du / trajectory.Duration
end

-- Rayos y colisiones ---------------------------------------------------------

local function isCharacterPart(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Lanza un rayo o esfera ignorando partes sin colisión (hojas, triggers) y personajes
local function castSolid(origin, direction, params, radius)
	for _ = 1, 4 do
		local hit = if radius
			then Workspace:Spherecast(origin, radius, direction, params)
			else Workspace:Raycast(origin, direction, params)
		if not hit then
			return nil
		end
		if hit.Instance.CanCollide and not isCharacterPart(hit.Instance) then
			return hit
		end
		params:AddToFilter(hit.Instance)
	end
	return nil
end

local function excludeParams(ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

function Zones.isPathClear(trajectory, ignore)
	local params = excludeParams(ignore)
	local previous = trajectory.Start
	for i = 1, Config.PathSamples do
		local position = Zones.evaluate(trajectory, i / Config.PathSamples)
		local step = position - previous
		if step.Magnitude > 0.01 and castSolid(previous, step, params, Config.PathRadius) then
			return false
		end
		previous = position
	end
	return true
end

local function isVisible(cameraPosition, point, branch, ignore)
	local target = point + Vector3.yAxis * 0.5
	local hit = castSolid(cameraPosition, target - cameraPosition, excludeParams(ignore))
	return hit == nil or (hit.Position - target).Magnitude <= 2 or hit.Instance == branch
end

--[[
	Mejor objetivo según donde apunta el jugador.
	context = {
		Origin          posición actual (o futura) del HumanoidRootPart
		AimOrigin       origen del rayo de apuntado
		AimDirection    dirección del rayo (unitaria)
		CameraPosition  para el chequeo de visibilidad
		Cone            ángulo máximo de apuntado
		Exclude         { [zona] = true } zonas que no cuentan
		FlightDirection dirección horizontal del vuelo actual, o nil
		Preferred       zona marcada actualmente (histéresis), o nil
		StandOffset     Zones.standOffset del personaje
		Ignore          instancias ignoradas por los rayos (el personaje)
		ChainIndex      para calcular la duración
	}
	Devuelve { Zone, Point, RootTarget, Trajectory } o nil.
]]
function Zones.findBest(context)
	local cosCone = math.cos(math.rad(context.Cone))
	local candidates = {}

	for zone in registry do
		if context.Exclude[zone] or not Zones.isUsable(zone) then
			continue
		end
		if (zone.Position - context.Origin).Magnitude - zone.Size.X / 2 > Config.MaxDistance then
			continue
		end

		local a, b = Zones.segment(zone)
		local point = Zones.closestPointToRay(a, b, context.AimOrigin, context.AimDirection)
		local toPoint = point - context.AimOrigin
		if toPoint.Magnitude < 1e-3 then
			continue
		end
		local aimDot = toPoint.Unit:Dot(context.AimDirection)
		if aimDot < cosCone then
			continue
		end

		local rootTarget = point + Vector3.yAxis * context.StandOffset
		local delta = rootTarget - context.Origin
		local distance = delta.Magnitude
		if distance < Config.MinDistance or distance > Config.MaxDistance then
			continue
		end
		if delta.Y > Config.MaxRise or -delta.Y > Config.MaxDrop then
			continue
		end

		local angle = math.deg(math.acos(math.clamp(aimDot, -1, 1)))
		local score = angle / context.Cone + (distance / Config.MaxDistance) * 0.35
		if delta.Y > 0 then
			score += (delta.Y / Config.MaxRise) * 0.2
		end
		score -= (zone:GetAttribute("Priority") or 0) * 0.1
		if context.FlightDirection then
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude > 1e-3 then
				local dot = flat.Unit:Dot(context.FlightDirection)
				score += if dot < 0 then 1 else -dot * 0.15
			end
		end
		if zone == context.Preferred then
			score -= 0.15
		end

		table.insert(candidates, { Zone = zone, Point = point, RootTarget = rootTarget, Score = score })
	end

	table.sort(candidates, function(x, y)
		return x.Score < y.Score
	end)

	for i = 1, math.min(#candidates, Config.MaxVisibilityChecks) do
		local candidate = candidates[i]
		local branch = Zones.sourceBranch(candidate.Zone)
		local ignore = table.clone(context.Ignore)
		if branch then
			table.insert(ignore, branch)
		end
		if isVisible(context.CameraPosition, candidate.Point, branch, context.Ignore) then
			local trajectory = Zones.trajectory(context.Origin, candidate.RootTarget, context.ChainIndex)
			if Zones.isPathClear(trajectory, ignore) then
				candidate.Trajectory = trajectory
				return candidate
			end
		end
	end
	return nil
end

return Zones
