--[[
	Throwables.Paths · ModuleScript en ReplicatedStorage.Throwables

	Trayectorias deterministas: con los mismos datos de entrada, cliente y servidor
	calculan exactamente el mismo camino. Por eso no se replica ningún modelo.

	Un disparo ("shot") es una lista de segmentos que se recorren en orden:
		Bezier     curva cuadrática P0 → P2 con punto de control P1 (con easing)
		Linear     recta con velocidad constante
		Ballistic  recta con gravedad (proyectiles desviados)

	La curva termina en el punto de destino decidido al soltar (ayuda de apuntado).
	No hay guiado en vuelo: si el objetivo se mueve después, el disparo puede fallar.
]]

local Config = require(script.Parent:WaitForChild("Config"))

local Paths = {}

local function bezier(p0, p1, p2, u)
	local a = 1 - u
	return p0 * (a * a) + p1 * (2 * a * u) + p2 * (u * u)
end

local function bezierDerivative(p0, p1, p2, u)
	return (p1 - p0) * (2 * (1 - u)) + (p2 - p1) * (2 * u)
end

local function approximateLength(p0, p1, p2)
	return ((p1 - p0).Magnitude + (p2 - p1).Magnitude + (p2 - p0).Magnitude) / 2
end

function Paths.segmentAt(segment, t)
	if segment.Type == "Bezier" then
		local s = math.clamp(t / segment.Duration, 0, 1)
		local a = segment.Ease
		local u = s + a * s * (1 - s)
		local du = 1 + a * (1 - 2 * s)
		local position = bezier(segment.P0, segment.P1, segment.P2, u)
		local velocity = bezierDerivative(segment.P0, segment.P1, segment.P2, u) * du / segment.Duration
		return position, velocity
	elseif segment.Type == "Ballistic" then
		local gravity = Vector3.new(0, -segment.Gravity, 0)
		return segment.P0 + segment.Velocity * t + gravity * (0.5 * t * t), segment.Velocity + gravity * t
	end
	return segment.P0 + segment.Velocity * t, segment.Velocity
end

local function makeBezier(p0, p1, p2, speed, ease)
	return {
		Type = "Bezier", P0 = p0, P1 = p1, P2 = p2,
		Duration = math.max(approximateLength(p0, p1, p2) / speed, 0.05),
		Ease = math.clamp(ease or 0, -0.9, 0.9),
	}
end

local function makeTail(segment, distance, fallbackSpeed)
	local position, velocity = Paths.segmentAt(segment, segment.Duration)
	if velocity.Magnitude < 1 then
		local direction = segment.P2 - segment.P1
		velocity = (if direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, 0, -1)) * fallbackSpeed
	end
	return { Type = "Linear", P0 = position, Velocity = velocity, Duration = math.max(distance, 1) / velocity.Magnitude }
end

function Paths.frame(origin, target)
	local delta = target - origin
	local length = delta.Magnitude
	local direction = if length > 1e-3 then delta / length else Vector3.new(0, 0, -1)
	local right = direction:Cross(Vector3.yAxis)
	right = if right.Magnitude < 1e-3 then Vector3.xAxis else right.Unit
	local up = right:Cross(direction).Unit
	return direction, right, up, length
end

local function curveTo(p0, p2, lateral, lift, speed, ease, right, up)
	local length = (p2 - p0).Magnitude
	local p1 = (p0 + p2) / 2 + right * (lateral * length) + up * (lift * length)
	return makeBezier(p0, p1, p2, speed, ease)
end

local function finalize(shot)
	local total = 0
	for _, segment in shot.Segments do
		total += segment.Duration
	end
	shot.Total = total
	return shot
end

function Paths.evaluate(shot, t)
	local override = shot.Override
	if override and t >= override.Time then
		local localTime = t - override.Time
		local segment = override.Segment
		local position, velocity = Paths.segmentAt(segment, math.min(localTime, segment.Duration))
		return position, velocity, localTime >= segment.Duration
	end

	local elapsed = t - shot.Delay
	if elapsed < 0 then
		return nil, nil, false
	end
	for _, segment in shot.Segments do
		if elapsed <= segment.Duration then
			local position, velocity = Paths.segmentAt(segment, elapsed)
			return position, velocity, false
		end
		elapsed -= segment.Duration
	end
	local last = shot.Segments[#shot.Segments]
	local position, velocity = Paths.segmentAt(last, last.Duration)
	return position, velocity, true
end

function Paths.endTime(shot)
	if shot.Override then
		return shot.Override.Time + shot.Override.Segment.Duration
	end
	return shot.Delay + shot.Total
end

function Paths.buildShots(definition, level, input)
	local levelDef = definition.Levels[level]
	local origin = input.Origin
	local side = if input.Side == -1 then -1 else 1
	local _, right, up, length = Paths.frame(origin, input.Target)

	local target = input.Target
	if length > definition.Range then
		target = origin + (target - origin).Unit * definition.Range
		length = definition.Range
	end

	local curve = levelDef.Curve
	local speed = levelDef.Speed
	local remaining = definition.Range - length + 20
	local shots = {}

	local function add(delay, segments, extra)
		local shot = { Index = #shots + 1, Delay = delay, Segments = segments }
		if extra then
			for key, value in extra do
				shot[key] = value
			end
		end
		table.insert(shots, finalize(shot))
	end

	if levelDef.Pattern == "Single" then
		local segment = curveTo(origin, target, curve.Lateral * side, curve.Lift, speed, curve.Ease, right, up)
		add(0, { segment, makeTail(segment, remaining, speed) })
	elseif levelDef.Pattern == "Fan" then
		local hands = if input.OneHand then { -1 } else { -1, 1 }
		local order = 0
		for i = 1, levelDef.Count do
			for _, hand in hands do
				local lane = if input.OneHand then (if i % 2 == 1 then -1 else 1) else hand
				local depth = if input.OneHand then math.ceil(i / 2) else i
				local handOrigin = if hand == 1 then origin + right * Config.HandSpacing else origin
				local lateral = lane * (curve.Lateral + curve.LateralStep * (depth - 1))
				local lift = curve.Lift * (if depth % 2 == 0 then -1 else 1)
				local spread = right * (lane * curve.TargetSpread * (depth - 1))
				local segment = curveTo(handOrigin, target + spread, lateral, lift, speed, curve.Ease, right, up)
				add(order * levelDef.Stagger, { segment, makeTail(segment, remaining, speed) })
				order += 1
			end
		end
	elseif levelDef.Pattern == "Burst" then
		for i = 1, levelDef.Count do
			local offset = up * (levelDef.Spacing * ((i - 1) - (levelDef.Count - 1) / 2))
			local segment = curveTo(origin + offset, target + offset, curve.Lateral * side, curve.Lift, speed, curve.Ease, right, up)
			add((i - 1) * levelDef.Stagger, { segment, makeTail(segment, remaining, speed) })
		end
	elseif levelDef.Pattern == "Boomerang" or levelDef.Pattern == "Kage" then
		local out = curveTo(origin, target, curve.Lateral * side, curve.Lift, speed, curve.Ease, right, up)
		local backControl = (target + origin) / 2 - right * (curve.Lateral * side * length) + up * (curve.Lift * length)
		local back = makeBezier(target, backControl, origin, speed, -curve.Ease)
		local _, backVelocity = Paths.segmentAt(back, back.Duration)
		local drop = {
			Type = "Ballistic", P0 = origin, Velocity = backVelocity * 0.5,
			Gravity = Config.DeflectGravity, Duration = 1.2,
		}
		add(0, { out, back, drop }, { ReturnAt = out.Duration + back.Duration })

		if levelDef.Pattern == "Kage" then
			local split = curve.Split
			local drop2 = up * -curve.KageDrop
			local p0 = out.P0 + drop2
			local q1 = out.P0:Lerp(out.P1, split) + drop2
			local splitPoint = bezier(out.P0, out.P1, out.P2, split) + drop2
			local first = makeBezier(p0, q1, splitPoint, speed, 0)
			local target2 = target + right * (-side * curve.KageOffset)
			local second = curveTo(splitPoint, target2, -side * curve.KageLateral, 0, speed * 1.15, 0.1, right, up)
			add(curve.KageDelay, { first, second, makeTail(second, remaining, speed) })
		end
	end

	return shots
end

function Paths.buildCounter(origin, intercept, flightTime)
	local velocity = (intercept - origin) / math.max(flightTime, 0.02)
	local shot = {
		Index = 1, Delay = 0,
		Segments = {
			{ Type = "Linear", P0 = origin, Velocity = velocity, Duration = flightTime },
			{ Type = "Linear", P0 = intercept, Velocity = velocity, Duration = 0.4 },
		},
	}
	return { finalize(shot) }
end

function Paths.makeDeflect(position, velocity, harmless)
	if harmless then
		return { Type = "Ballistic", P0 = position, Velocity = velocity, Gravity = Config.DeflectGravity, Duration = 2.5 }
	end
	return { Type = "Linear", P0 = position, Velocity = velocity, Duration = 1.5 }
end

return Paths
