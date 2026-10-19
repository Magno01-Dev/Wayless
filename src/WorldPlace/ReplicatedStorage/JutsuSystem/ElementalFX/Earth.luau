--!nonstrict
-- ReplicatedStorage > JutsuSystem > ElementalFX > Earth   (ModuleScript, solo cliente)
--
-- VFX de Doton estilo anime: rocas facetadas (Slate) con contorno oscuro, grietas,
-- fragmentos que saltan con gravedad y nubes de polvo.
--   StoneShot     roca arrancada del suelo que vuela girando y revienta en pedazos
--   EarthSpikes   púas de roca que brotan en línea, una tras otra
--   EarthTremor   onda sísmica: grietas, rocas que se levantan en anillo y polvo
--   EarthWall     muro que sube por capas y se derrumba al terminar

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Common = require(script.Parent:WaitForChild("Common"))

local C = Common.Palettes.Earth
local SLATE = Enum.Material.Slate
local GRAVITY = 70

local Earth = {}

local function outline(model)
	return Common.outline(model, C.Outline, Common.EarthOutline)
end

local function rockColor(rng)
	local v = rng:NextNumber(0.82, 1.2)
	return Color3.new(math.min(C.Rock.R * v, 1), math.min(C.Rock.G * v, 1), math.min(C.Rock.B * v, 1))
end

local function rockPart(parent, size, cf, color, className)
	return Common.newPart(className or "Part", {
		Size = size,
		CFrame = cf,
		Color = color,
		Material = SLATE,
		CastShadow = true,
	}, parent)
end

-- Pedazos de roca que salen volando con gravedad y giro
local function debrisBurst(parent, position, normal, count, speed, size, rng, duration)
	duration = duration or 0.9
	local u, v = Common.planeBasis(normal)
	local chunks = {}
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local out = u * math.cos(angle) + v * math.sin(angle)
		local s = rng:NextNumber(size * 0.4, size)
		table.insert(chunks, {
			Part = rockPart(parent, Vector3.new(s, s * rng:NextNumber(0.6, 1.3), s), CFrame.new(position), rockColor(rng), if rng:NextNumber() > 0.6 then "WedgePart" else "Part"),
			Velocity = (out * rng:NextNumber(0.4, 1) + normal * rng:NextNumber(0.8, 1.6)).Unit * rng:NextNumber(speed * 0.5, speed),
			Spin = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10)),
		})
	end
	Common.animate(duration, function(t)
		for _, chunk in chunks do
			local p = position + chunk.Velocity * t + Vector3.new(0, -GRAVITY * 0.5 * t * t, 0)
			chunk.Part.CFrame = CFrame.new(p) * CFrame.Angles(chunk.Spin.X * t, chunk.Spin.Y * t, chunk.Spin.Z * t)
			chunk.Part.Transparency = math.clamp((t - duration * 0.6) / (duration * 0.4), 0, 1)
		end
	end)
end

-- Grietas que se abren en zigzag sobre la superficie
local function cracks(parent, position, normal, count, length, rng, lifetime)
	lifetime = lifetime or 1.8
	local u, v = Common.planeBasis(normal)
	local segments = {}
	for k = 1, count do
		local angle = k / count * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local point = position + normal * 0.04
		local heading = angle
		local reach = length * rng:NextNumber(0.6, 1)
		local pieces = 3
		for i = 1, pieces do
			heading += rng:NextNumber(-0.5, 0.5)
			local direction = u * math.cos(heading) + v * math.sin(heading)
			local segmentLength = reach / pieces
			local finish = point + direction * segmentLength
			local width = 0.35 * (1 - (i - 1) / pieces) + 0.08
			local part = Common.newPart("Part", { Color = C.Crack, Size = Vector3.new(width, 0.05, 0.05), Transparency = 0.1 }, parent)
			table.insert(segments, {
				Part = part,
				Start = point,
				Direction = direction,
				Length = segmentLength,
				Width = width,
				Delay = (i - 1) * 0.04,
			})
			point = finish
		end
	end
	Common.animate(lifetime, function(t)
		for _, segment in segments do
			local grow = Common.easeOut((t - segment.Delay) / 0.08)
			local len = math.max(segment.Length * grow, 0.05)
			local center = segment.Start + segment.Direction * (len * 0.5)
			segment.Part.Size = Vector3.new(segment.Width, 0.05, len)
			segment.Part.CFrame = CFrame.fromMatrix(center, segment.Direction:Cross(normal).Unit, normal)
			segment.Part.Transparency = if grow <= 0 then 1 else 0.1 + 0.9 * math.clamp((t - lifetime * 0.6) / (lifetime * 0.4), 0, 1)
		end
	end)
end

local function dustCloud(kind, position, normal, size, count, props)
	local holder = Common.emitterHolder(nil, position, normal, Vector3.new(size, 0.2, size))
	local defaults = {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(70, 70),
		Speed = NumberRange.new(6, 14),
		Lifetime = NumberRange.new(0.6, 1.2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(0.5, 4), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 1.5, 0),
	}
	for key, value in props or {} do
		defaults[key] = value
	end
	Common.dust(kind, holder, C.Dust, defaults):Emit(count)
	Debris:AddItem(holder, 2.5)
end

---------------------------------------------------------------------
-- STONE SHOT
---------------------------------------------------------------------

-- Roca facetada: núcleo + caras en ángulo (wedges y bloques) para que no se vea redonda
local function buildBoulder(radius, rng)
	local model = Common.newModel("StoneShot")
	outline(model)
	local pieces = {}
	local function add(part, offset)
		table.insert(pieces, { Part = part, Offset = offset })
	end
	add(rockPart(model, Vector3.one * radius * 1.6, CFrame.new(), rockColor(rng)), CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0))
	for _ = 1, 5 do
		local direction = Common.randomUnit(rng)
		local size = Vector3.new(radius * rng:NextNumber(0.8, 1.2), radius * rng:NextNumber(0.6, 1), radius * rng:NextNumber(0.8, 1.3))
		add(rockPart(model, size, CFrame.new(), rockColor(rng), if rng:NextNumber() > 0.5 then "WedgePart" else "Part"),
			CFrame.lookAt(direction * radius * 0.55, direction * 2) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)))
	end
	return { Model = model, Pieces = pieces }
end

local movedParts, movedCFrames = {}, {}

local function moveBoulder(boulder, cf)
	table.clear(movedParts)
	table.clear(movedCFrames)
	for _, piece in boulder.Pieces do
		table.insert(movedParts, piece.Part)
		table.insert(movedCFrames, cf * piece.Offset)
	end
	Workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function stoneImpact(position, normal, radius, rng)
	local model = Common.newModel("StoneShot_Impact")
	outline(model)
	debrisBurst(model, position + normal * 0.3, normal, 16, 26, radius * 0.6, rng)
	cracks(model, position, normal, 7, radius * 3.2, rng)
	dustCloud("StoneShot", position, normal, radius * 1.5, 18)
	local scar = Common.disc(model, C.Dark, 0.2)
	scar.Size = Vector3.new(0.05, radius * 2.6, radius * 2.6)
	scar.CFrame = Common.discCFrame(position + normal * 0.03, normal)
	Common.animate(1.8, function(t)
		scar.Transparency = 0.2 + 0.8 * math.clamp((t - 1) / 0.8, 0, 1)
	end)
	Common.shake(position, 1.4, 70, 0.25)
	Common.spawnCustom("StoneShot", "Impact", Common.upCFrame(position, normal))
	Debris:AddItem(model, 2)
end

Earth.StoneShot = {
	Projectile = {
		Create = function(data)
			local rng = Random.new()
			local radius = data.Radius or 1.75
			-- Se arranca del suelo: grieta y polvo bajo el lanzador
			local ground = Common.groundBelow(data.Origin, { data.Caster }, 10)
			if ground then
				local model = Common.newModel("StoneShot_Cast")
				outline(model)
				cracks(model, ground.Position, ground.Normal, 4, 3, rng, 1.2)
				debrisBurst(model, ground.Position, ground.Normal, 6, 14, 0.5, rng, 0.6)
				dustCloud("StoneShot", ground.Position, ground.Normal, 2, 6)
				Debris:AddItem(model, 1.4)
			end
			Common.spawnCustom("StoneShot", "Cast", Common.lookAlong(data.Origin, data.Direction))

			local state = {
				Radius = radius,
				Rng = rng,
				Custom = Common.attachCustom("StoneShot", "Body", CFrame.new(data.Origin)),
			}
			if not Common.hideDefault("StoneShot") then
				state.Boulder = buildBoulder(radius, rng)
				state.TrailHolder = Common.host("StoneShotTrail", CFrame.new(data.Origin), Vector3.one * radius)
				state.Trail = Common.dust("StoneShot", state.TrailHolder, C.Dust, {
					Rate = 30,
					Speed = NumberRange.new(1, 3),
					Lifetime = NumberRange.new(0.3, 0.6),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.6), NumberSequenceKeypoint.new(1, radius * 1.6) }),
					SpreadAngle = Vector2.new(180, 180),
				})
				-- Piedritas que se desprenden
				state.Pebbles = Common.dust("StoneShot", state.TrailHolder, C.Dark, {
					Texture = Common.texture("StoneShot", "Spark"),
					Rate = 18,
					Speed = NumberRange.new(2, 5),
					Lifetime = NumberRange.new(0.4, 0.7),
					Acceleration = Vector3.new(0, -50, 0),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.1) }),
					Transparency = NumberSequence.new(0, 0.6),
				})
			end
			return state
		end,
		Update = function(state, position, direction, t)
			-- Gira mientras vuela
			local cf = CFrame.new(position) * CFrame.Angles(t * 5, t * 3, 0)
			if state.Custom then
				state.Custom:Move(cf)
			end
			if state.Boulder then
				moveBoulder(state.Boulder, cf)
				state.TrailHolder.CFrame = CFrame.new(position)
			end
		end,
		End = function(state, position, normal, hit)
			if state.Boulder then
				state.Boulder.Model:Destroy()
				state.Trail.Enabled = false
				state.Pebbles.Enabled = false
				Debris:AddItem(state.TrailHolder, 1)
			end
			if state.Custom then
				state.Custom:Stop()
			end
			if hit and typeof(normal) == "Vector3" then
				stoneImpact(position, normal, state.Radius, state.Rng)
			else
				-- Sin chocar: se desmorona en el aire
				local model = Common.newModel("StoneShot_Crumble")
				outline(model)
				debrisBurst(model, position, Vector3.yAxis, 10, 12, state.Radius * 0.5, state.Rng)
				dustCloud("StoneShot", position, Vector3.yAxis, state.Radius, 8)
				Debris:AddItem(model, 1.2)
			end
		end,
	},
}

---------------------------------------------------------------------
-- EARTH SPIKES
---------------------------------------------------------------------

-- Púa de roca: dos WedgeParts espalda con espalda forman un prisma con filo arriba;
-- dos prismas cruzados en X dan una punta afilada vista desde cualquier ángulo.
-- (La cara vertical de un WedgePart está en su +Z; la pendiente baja hacia -Z.)
local function spikeParts(parent, width, height, color)
	local parts = {}
	for _, yaw in { 0, math.pi / 2 } do
		for _, flip in { false, true } do
			local part = Common.newPart("WedgePart", {
				Size = Vector3.new(width * (if yaw == 0 then 0.55 else 0.4), height, width / 2),
				Color = color,
				Material = SLATE,
				CastShadow = true,
			}, parent)
			table.insert(parts, { Part = part, Yaw = yaw, Flip = flip })
		end
	end
	return parts
end

local function placeSpike(parts, baseCF, width, height)
	local depth = width / 2
	for _, entry in parts do
		local cf = baseCF * CFrame.Angles(0, entry.Yaw, 0)
		if entry.Flip then
			cf = cf * CFrame.new(0, height / 2, depth / 2) * CFrame.Angles(0, math.pi, 0)
		else
			cf = cf * CFrame.new(0, height / 2, -depth / 2)
		end
		entry.Part.CFrame = cf
	end
end

Earth.EarthSpikes = {
	Spike = function(data)
		if typeof(data.Position) ~= "Vector3" then
			return
		end
		local rng = Random.new()
		local ground = data.Position
		local height = data.Height or 6
		local direction = if typeof(data.Direction) == "Vector3" then data.Direction else Vector3.zAxis
		Common.spawnCustom("EarthSpikes", "Impact", CFrame.lookAt(ground, ground + direction))
		if Common.hideDefault("EarthSpikes") then
			return
		end

		local model = Common.newModel("EarthSpikes")
		outline(model)
		-- Racimo: una púa grande y dos más chicas inclinadas
		local spikes = {}
		for k = 1, 3 do
			local scale = if k == 1 then 1 else rng:NextNumber(0.5, 0.7)
			local width = 2.4 * scale
			local h = height * scale
			local offset = if k == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-1.6, 1.6), 0, rng:NextNumber(-1.2, 1.2))
			local tilt = CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.25, 0.25))
			table.insert(spikes, {
				Parts = spikeParts(model, width, h, rockColor(rng)),
				Base = CFrame.new(ground + offset) * tilt,
				Width = width,
				Height = h,
				Delay = (k - 1) * 0.03,
			})
		end
		local hold, rise, sink = 0.42, 0.1, 0.25
		Common.animate(rise + hold + sink, function(t)
			for _, spike in spikes do
				local local_t = t - spike.Delay
				-- Sale disparada con un pequeño rebote, se queda y se hunde
				local up = if local_t < rise
					then Common.easeOut(local_t / rise) * 1.08
					elseif local_t < rise + 0.06 then 1.08 - 0.08 * ((local_t - rise) / 0.06)
					else 1
				local down = math.clamp((local_t - rise - hold) / sink, 0, 1)
				local visible = math.clamp(up, 0, 1.08) * (1 - down)
				local base = spike.Base * CFrame.new(0, -spike.Height * (1 - visible), 0)
				placeSpike(spike.Parts, base, spike.Width, spike.Height)
				for _, entry in spike.Parts do
					entry.Part.Transparency = if local_t < 0 then 1 else 0
				end
			end
		end)

		local up = Vector3.yAxis
		cracks(model, ground, up, 6, 3.5, rng, 1.3)
		debrisBurst(model, ground + up * 0.3, up, 10, 22, 0.55, rng, 0.8)
		dustCloud("EarthSpikes", ground, up, 3, 8)
		local ring = Common.disc(model, C.Dark, 0.3)
		ring.CFrame = Common.discCFrame(ground + up * 0.04, up)
		Common.animate(1.2, function(t)
			local size = 2 + 4 * Common.easeOut(t / 0.15)
			ring.Size = Vector3.new(0.05, size, size)
			ring.Transparency = 0.3 + 0.7 * math.clamp((t - 0.6) / 0.6, 0, 1)
		end)
		if (data.Index or 1) == 1 then
			Common.shake(ground, 1.1, 60, 0.2)
		end
		Debris:AddItem(model, 1.5)
	end,
}

---------------------------------------------------------------------
-- EARTH TREMOR
---------------------------------------------------------------------

Earth.EarthTremor = {
	Tremor = function(data)
		if typeof(data.Position) ~= "Vector3" then
			return
		end
		local rng = Random.new()
		local center = data.Position
		local radius = data.Radius or 12
		local normal = Vector3.yAxis
		Common.playSound(data.SoundId, center, data.SoundVolume, data.SoundMinDistance, data.SoundMaxDistance)
		Common.shake(center, 2.4, 60, 0.42)
		Common.spawnCustom("EarthTremor", "Cast", Common.upCFrame(center, normal))
		if Common.hideDefault("EarthTremor") then
			return
		end

		local model = Common.newModel("EarthTremor")
		outline(model)

		-- Grietas largas hasta el borde del área
		cracks(model, center, normal, 10, radius * 0.95, rng, 2)

		-- Rocas que se levantan en un anillo que se expande
		local rocks = {}
		for k = 1, 22 do
			local angle = k / 22 * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
			local distance = radius * rng:NextNumber(0.35, 1)
			local size = Vector3.new(rng:NextNumber(0.9, 2), rng:NextNumber(1.2, 2.6), rng:NextNumber(0.9, 2))
			local base = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
			table.insert(rocks, {
				Part = rockPart(model, size, CFrame.new(base), rockColor(rng), if rng:NextNumber() > 0.5 then "WedgePart" else "Part"),
				Base = base,
				Size = size,
				Tilt = CFrame.Angles(rng:NextNumber(-0.5, 0.5), angle, rng:NextNumber(-0.5, 0.5)),
				Delay = distance / radius * 0.18,
			})
		end
		Common.animate(1.1, function(t)
			for _, rock in rocks do
				local local_t = t - rock.Delay
				local up = Common.easeOut(local_t / 0.08)
				local down = math.clamp((local_t - 0.45) / 0.4, 0, 1)
				local lift = rock.Size.Y * (up * (1 - down)) - rock.Size.Y * 0.9
				rock.Part.CFrame = CFrame.new(rock.Base + Vector3.new(0, lift, 0)) * rock.Tilt
				rock.Part.Transparency = if local_t < 0 then 1 else 0
			end
		end)

		-- Onda de tierra y polvo que corre hacia afuera
		local wave = Common.disc(model, C.Dark, 0.35)
		wave.CFrame = Common.discCFrame(center + normal * 0.05, normal)
		Common.animate(0.6, function(t)
			local a = Common.easeOut(t / 0.6)
			local size = 2 * radius * a + 1
			wave.Size = Vector3.new(0.1, size, size)
			wave.Transparency = 0.35 + 0.65 * a
		end)
		for k = 1, 8 do
			local angle = k / 8 * math.pi * 2
			local point = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.7
			task.delay(0.08, function()
				dustCloud("EarthTremor", point, normal, 3, 6, { Speed = NumberRange.new(4, 9) })
			end)
		end
		debrisBurst(model, center + normal * 0.3, normal, 14, 28, 0.6, rng)
		Debris:AddItem(model, 2.2)
	end,
}

---------------------------------------------------------------------
-- EARTH WALL
---------------------------------------------------------------------

local walls = {}

local function collapseWall(state)
	if state.Stopped then
		return
	end
	state.Stopped = os.clock()
	local rng = state.Rng
	-- Polvo a lo largo de la base y pedazos que caen
	for i = 1, 6 do
		local point = (state.Base * CFrame.new((i - 3.5) * state.Size.X / 6, 0.2, 0)).Position
		dustCloud("EarthWall", point, Vector3.yAxis, 2.5, 4, { Speed = NumberRange.new(3, 7) })
	end
	debrisBurst(state.Model, (state.Base * CFrame.new(0, state.Size.Y * 0.5, 0)).Position, Vector3.yAxis, 14, 14, 0.9, rng, 1)
	if state.Custom then
		state.Custom:Stop()
	end
end

Earth.EarthWall = {
	Raise = function(data)
		local wall = data.Wall
		local cf = if typeof(data.CFrame) == "CFrame" then data.CFrame elseif wall then wall.CFrame else nil
		local size = if typeof(data.Size) == "Vector3" then data.Size elseif wall then wall.Size else nil
		if not cf or not size then
			return
		end
		if Common.hideDefault("EarthWall") then
			Common.spawnCustom("EarthWall", "Cast", cf * CFrame.new(0, -size.Y / 2, 0))
			return
		end
		-- El bloque del servidor sigue dando la colisión, pero aquí se oculta
		if typeof(wall) == "Instance" and wall:IsA("BasePart") then
			wall.LocalTransparencyModifier = 1
		end

		local rng = Random.new()
		local model = Common.newModel("EarthWall")
		outline(model)
		local base = cf * CFrame.new(0, -size.Y / 2, 0)
		local state = {
			Model = model,
			Rng = rng,
			Base = base,
			Size = size,
			Born = os.clock(),
			Slabs = {},
			Custom = Common.attachCustom("EarthWall", "Body", cf),
		}
		Common.spawnCustom("EarthWall", "Cast", base)

		-- Núcleo que sube con las capas de roca
		state.Core = rockPart(model, Vector3.new(size.X, 0.05, size.Z), base, C.Rock)
		-- Losas en ambas caras, en 3 filas, y crestas en la parte de arriba
		for side = -1, 1, 2 do
			for row = 1, 3 do
				for col = 1, 7 do
					local w, h = size.X / 7, size.Y / 3
					local depth = rng:NextNumber(0.22, 0.5)
					local slabSize = Vector3.new(w * rng:NextNumber(0.88, 0.98), h * rng:NextNumber(0.9, 0.98), depth)
					local target = base * CFrame.new((col - 4) * w, (row - 0.5) * h, side * (size.Z / 2 + depth * 0.4)) * CFrame.Angles(0, 0, rng:NextNumber(-0.025, 0.025))
					table.insert(state.Slabs, { Part = rockPart(model, slabSize, target, rockColor(rng)), Target = target, Size = slabSize, Delay = math.abs(col - 4) * 0.018 + (row - 1) * 0.025 })
				end
			end
		end
		for i = 1, 9 do
			local crestSize = Vector3.new(size.X / 10, rng:NextNumber(0.35, 1.1), size.Z * 0.9)
			local target = base * CFrame.new((i - 5) * size.X / 9, size.Y + crestSize.Y * 0.15, 0) * CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), rng:NextNumber(-0.2, 0.2))
			table.insert(state.Slabs, { Part = rockPart(model, crestSize, target, rockColor(rng), if i % 3 == 0 then "WedgePart" else "Part"), Target = target, Size = crestSize, Delay = 0.07 + math.abs(i - 5) * 0.015 })
		end
		-- Piedras sueltas alrededor de la base
		for i = 1, 20 do
			local theta = i * math.pi * 2 / 20
			local stoneSize = Vector3.new(rng:NextNumber(0.4, 1), rng:NextNumber(0.3, 0.65), rng:NextNumber(0.5, 1.1))
			local target = base * CFrame.new(math.cos(theta) * size.X * 0.54, 0.15, math.sin(theta) * (size.Z * 0.5 + 1.3)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), theta, rng:NextNumber(-0.3, 0.3))
			table.insert(state.Slabs, { Part = rockPart(model, stoneSize, target, rockColor(rng)), Target = target, Size = stoneSize, Delay = 0 })
		end

		-- Al subir: grietas, polvo y piedras que saltan
		local groundPoint = base.Position
		cracks(model, groundPoint, Vector3.yAxis, 8, size.X * 0.6, rng, 2.5)
		for i = 1, 6 do
			local point = (base * CFrame.new((i - 3.5) * size.X / 6, 0.2, 0)).Position
			dustCloud("EarthWall", point, Vector3.yAxis, 2.5, 6)
		end
		debrisBurst(model, groundPoint + Vector3.new(0, 0.3, 0), Vector3.yAxis, 18, 20, 0.45, rng, 0.8)
		Common.shake(groundPoint, 1.3, 60, 0.3)

		local duration = data.Duration or 5
		local key = wall or state
		walls[key] = state
		state.Connection = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			local age = Common.stylizedTime(now - state.Born)
			-- Termina cuando el servidor quita el muro (o al acabar la duración)
			local gone = (typeof(wall) == "Instance" and not wall:IsDescendantOf(Workspace)) or (now - state.Born > duration + 0.5)
			if gone and not state.Stopped then
				collapseWall(state)
			end
			local ending = if state.Stopped then math.clamp((now - state.Stopped) / 0.45, 0, 1) else 0

			local coreGrow = Common.easeOut(age / 0.24)
			local visibleHeight = size.Y * coreGrow
			state.Core.Size = Vector3.new(size.X, math.max(0.05, visibleHeight), size.Z)
			state.Core.CFrame = base * CFrame.new(0, visibleHeight / 2 - ending * ending * size.Y, 0)
			state.Core.Transparency = ending
			for _, slab in state.Slabs do
				local grow = Common.easeOut((age - slab.Delay) / 0.24)
				slab.Part.Size = Vector3.new(slab.Size.X, math.max(0.05, slab.Size.Y * grow), slab.Size.Z)
				slab.Part.CFrame = slab.Target + Vector3.new(0, -(1 - grow) * slab.Size.Y / 2 - ending * ending * 1.4, 0)
				slab.Part.Transparency = math.max(1 - grow, ending)
			end
			if state.Custom then
				state.Custom:Move(cf)
			end

			if state.Stopped and now - state.Stopped > 1.15 then
				state.Connection:Disconnect()
				walls[key] = nil
				model:Destroy()
			end
		end)
	end,
}

return Earth
