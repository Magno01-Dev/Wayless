--!nonstrict
-- ReplicatedStorage > JutsuSystem > ElementalFX > Wind   (ModuleScript, solo cliente)
--
-- VFX de Fūton estilo anime: líneas blancas/menta nítidas (Beams), anillos de presión y polvo.
--   AirBullet   bala de aire comprimido que deja anillos de choque detrás
--   WindBlade   media luna cortante; atraviesa enemigos y deja marca de corte
--   GalePalm    ráfaga de palma en cono con anillos y líneas de viento
--   WindSweep   barrido horizontal amplio alrededor del personaje

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Common = require(script.Parent:WaitForChild("Common"))

local C = Common.Palettes.Wind

local Wind = {}

local function sparkColors()
	return ColorSequence.new(C.White, C.Mint)
end

-- Anillo de presión que se abre (en el plano perpendicular a `direction`)
local function pressureRing(position, direction, fromRadius, toRadius, duration, width, delay)
	local anchor = Common.host("PressureRing", Common.lookAlong(position, direction))
	local ring = Common.beamLine(anchor, 25, C.White, C.Mint, 0.15, 0.8, width)
	local function run()
		Common.animate(duration, function(t)
			local a = Common.easeOut(t / duration)
			Common.placeCircle(ring, Vector3.zAxis, fromRadius + (toRadius - fromRadius) * a)
			Common.setUniformWidth(ring, width * (1 - a))
			Common.setTransparency(ring, 0.15 + 0.85 * a)
		end)
	end
	if delay and delay > 0 then
		task.delay(delay, run)
	else
		run()
	end
	Debris:AddItem(anchor, duration + (delay or 0) + 0.1)
end

-- Polvo levantado en el suelo
local function groundDust(kind, position, normal, size, count)
	local holder = Common.emitterHolder(nil, position, normal, Vector3.new(size, 0.2, size))
	Common.dust(kind, holder, C.Dust, {
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(6, 14),
	}):Emit(count)
	Debris:AddItem(holder, 1.5)
end

-- Corte en X, rayos y anillo sobre una superficie (impactos de WindBlade y AirBullet)
local function cutFlash(kind, position, normal, size, withGash, along)
	local anchor = Common.host(kind .. "_Cut", Common.lookAlong(position + normal * 0.1, -normal), Vector3.new(1.5, 0.2, 1.5))
	local cuts = { Common.beamLine(anchor, 3, C.White, C.Mint, 0, 1, 0.6), Common.beamLine(anchor, 3, C.White, C.Mint, 0, 1, 0.6) }
	Common.animate(0.32, function(t)
		local reach = Common.easeOut(t / 0.05) * 4.2 * size
		local thin = 1 - math.clamp((t - 0.05) / 0.27, 0, 1)
		for k, cut in cuts do
			local slope = if k == 1 then 0.35 else -0.35
			local tip = Vector3.new(reach, reach * slope, 0)
			cut.Nodes[1].Position = -tip
			cut.Nodes[2].Position = Vector3.zero
			cut.Nodes[3].Position = tip
			cut.Beams[1].Width0, cut.Beams[1].Width1 = 0, 0.6 * size * thin
			cut.Beams[2].Width0, cut.Beams[2].Width1 = 0.6 * size * thin, 0
		end
	end)

	local spokes = {}
	for k = 1, 10 do
		table.insert(spokes, { Line = Common.beamLine(anchor, 2, C.White, C.Mint, 0.1, 0.9, 0.22), Angle = k / 10 * math.pi * 2 + math.random() * 0.3 })
	end
	local ring = Common.beamLine(anchor, 25, C.White, C.Mint, 0.2, 0.8, 0.3)
	Common.animate(0.3, function(t)
		local a = Common.easeOut(t / 0.3)
		for _, spoke in spokes do
			local direction = Vector3.new(math.cos(spoke.Angle), math.sin(spoke.Angle), 0)
			spoke.Line.Nodes[1].Position = direction * (1 + 4 * a) * size
			spoke.Line.Nodes[2].Position = direction * (2.5 + 6 * a) * size
			Common.setUniformWidth(spoke.Line, 0.22 * size * (1 - a), 0)
		end
		Common.placeCircle(ring, Vector3.zAxis, (1 + 6 * a) * size)
		Common.setUniformWidth(ring, 0.3 * size * (1 - a))
		Common.setTransparency(ring, 0.2 + 0.8 * a)
	end)

	local holder = Common.emitterHolder(nil, position, normal, Vector3.new(1.5, 0.2, 1.5))
	Common.sparks(kind, holder, sparkColors(), {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(70, 70),
		Speed = NumberRange.new(15, 30),
		Drag = 4,
		Lifetime = NumberRange.new(0.2, 0.4),
	}):Emit(math.floor(30 * size))
	Common.dust(kind, holder, C.Dust, { EmissionDirection = Enum.NormalId.Top }):Emit(math.floor(14 * size))

	-- Marca de corte en la superficie, alineada con el ancho del corte
	if withGash then
		local u = Common.planeBasis(normal)
		local axis = if along then along - normal * along:Dot(normal) else u
		axis = if axis.Magnitude > 1e-3 then axis.Unit else u
		local gash = Common.newPart("Part", {
			Name = "WindGash",
			Color = C.Gash,
			Size = Vector3.new(6 * size, 0.06, 0.28),
			CFrame = CFrame.fromMatrix(position + normal * 0.03, axis, normal),
		})
		Common.animate(1.6, function(t)
			gash.Transparency = 0.15 + 0.85 * math.clamp((t - 0.6) / 1.0, 0, 1)
		end)
		Debris:AddItem(gash, 1.7)
	end

	Common.shake(position, 0.9 * size, 70, 0.2)
	Common.spawnCustom(kind, "Impact", Common.upCFrame(position, normal))
	Debris:AddItem(anchor, 0.4)
	Debris:AddItem(holder, 1.2)
end

---------------------------------------------------------------------
-- AIR BULLET
---------------------------------------------------------------------

local function buildAirBullet(radius)
	local anchor = Common.host("AirBullet", CFrame.new(), Vector3.one * radius * 1.5)
	local bullet = { Anchor = anchor, Radius = radius, Rings = {} }
	-- Distorsión: esfera de vidrio casi invisible + capa ForceField (se ve como aire girando)
	bullet.Glass = Common.ball(nil, C.White, 0.82, Enum.Material.Glass)
	bullet.Glass.Size = Vector3.one * radius * 2
	bullet.Swirl = Common.ball(nil, C.Mint, 0.35, Enum.Material.ForceField)
	bullet.Swirl.Size = Vector3.one * radius * 2.3
	-- Anillos que giran alrededor (espiral de aire)
	for k = 1, 3 do
		table.insert(bullet.Rings, { Line = Common.beamLine(anchor, 21, C.White, C.Mint, 0.2, 0.7, 0.14), Phase = k * 2.1 })
	end
	-- Estelas de velocidad
	for k = 1, 3 do
		local angle = k / 3 * math.pi * 2
		local offset = Vector3.new(math.cos(angle), math.sin(angle), 0) * radius * 0.8
		local a0 = Instance.new("Attachment")
		a0.Position = offset * 1.05
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = offset * 0.85
		a1.Parent = anchor
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.14
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.LightEmission = 0.7
		trail.Color = sparkColors()
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = anchor
		bullet.Trails = bullet.Trails or {}
		table.insert(bullet.Trails, trail)
	end
	return bullet
end

Wind.AirBullet = {
	Projectile = {
		Create = function(data)
			local radius = data.Radius or 1.15
			pressureRing(data.Origin, data.Direction, 0.6, 3.5, 0.22, 0.3)
			Common.spawnCustom("AirBullet", "Cast", Common.lookAlong(data.Origin, data.Direction))
			return {
				Radius = radius,
				Bullet = if Common.hideDefault("AirBullet") then nil else buildAirBullet(radius),
				Custom = Common.attachCustom("AirBullet", "Body", Common.lookAlong(data.Origin, data.Direction)),
				LastRing = 0,
			}
		end,
		Update = function(state, position, direction, t)
			local cf = Common.lookAlong(position, direction)
			if state.Custom then
				state.Custom:Move(cf)
			end
			local bullet = state.Bullet
			if not bullet then
				return
			end
			bullet.Anchor.CFrame = cf
			local pulse = 1 + 0.08 * math.sin(t * 30)
			bullet.Glass.CFrame = cf
			bullet.Swirl.CFrame = cf * CFrame.Angles(0, 0, t * 12)
			bullet.Swirl.Size = Vector3.one * state.Radius * 2.3 * pulse
			for _, ring in bullet.Rings do
				local axis = CFrame.Angles(0, 0, t * 9 + ring.Phase) * Vector3.new(0.35, 0, 1).Unit
				Common.placeCircle(ring.Line, axis, state.Radius * 1.2)
				Common.setUniformWidth(ring.Line, ring.Line.Width)
			end
			if not state.Started then
				state.Started = true
				for _, trail in bullet.Trails do
					trail.Enabled = true
				end
			end
			-- Anillos de choque que quedan atrás
			if t - state.LastRing > 0.07 then
				state.LastRing = t
				pressureRing(position, direction, state.Radius * 0.8, state.Radius * 2.6, 0.25, 0.18)
			end
		end,
		End = function(state, position, normal, hit)
			if state.Bullet then
				state.Bullet.Anchor:Destroy()
				state.Bullet.Glass:Destroy()
				state.Bullet.Swirl:Destroy()
			end
			if state.Custom then
				state.Custom:Stop()
			end
			if hit and typeof(normal) == "Vector3" then
				pressureRing(position + normal * 0.3, normal, 1, 7, 0.3, 0.4)
				pressureRing(position + normal * 0.3, normal, 0.5, 4.5, 0.25, 0.3, 0.05)
				cutFlash("AirBullet", position, normal, 0.6, false)
				groundDust("AirBullet", position, normal, 2, 12)
			else
				pressureRing(position, Vector3.yAxis, 0.5, 4, 0.25, 0.25)
			end
		end,
	},
}

---------------------------------------------------------------------
-- WIND BLADE
---------------------------------------------------------------------

local BLADE_HALF_WIDTH = 3.4
local BLADE_DEPTH = 2.2
local BLADE_TILT = CFrame.Angles(0, 0, math.rad(14))

local function crescentPoint(f, widthScale, depthOffset)
	local theta = (f - 0.5) * math.pi * 0.96
	local x = math.sin(theta) * BLADE_HALF_WIDTH * widthScale
	local z = (1 - math.cos(theta)) * BLADE_DEPTH * widthScale + depthOffset
	return Vector3.new(x, 0, z)
end

local function placeCrescent(line, widthScale, depthOffset, wobbleTime)
	local count = #line.Nodes
	for i, node in line.Nodes do
		local f = (i - 1) / (count - 1)
		local point = crescentPoint(f, widthScale, depthOffset)
		if wobbleTime then
			point += Vector3.new(0, math.sin(wobbleTime * 14 + f * 5) * 0.05, 0)
		end
		node.Position = point
	end
end

-- Tajo al lanzar: el arco se dibuja de un lado al otro y se desvanece
local function slashFlash(origin, direction)
	local anchor = Common.host("WindSlash", Common.lookAlong(origin, direction) * BLADE_TILT)
	local arc = Common.beamLine(anchor, 17, C.White, C.Mint, 0, 1, 0.35)
	local glow = Common.beamLine(anchor, 17, C.Mint, C.Teal, 0.5, 0.6, 1.4)
	Common.animate(0.24, function(t)
		local reveal = Common.easeOut(t / 0.08)
		local fade = math.clamp((t - 0.08) / 0.16, 0, 1)
		for _, line in { arc, glow } do
			local count = #line.Nodes
			for i, node in line.Nodes do
				node.Position = crescentPoint(math.min((i - 1) / (count - 1), reveal), 1.15, 0.6)
			end
			Common.setCrescentWidth(line, line.Width * (1 - fade))
		end
	end)
	pressureRing(origin + direction * 2.6, direction, 2, 6.5, 0.25, 0.28)
	pressureRing(origin + direction * 4.2, direction, 2.5, 7.5, 0.25, 0.28, 0.04)
	Debris:AddItem(anchor, 0.3)
end

local function buildBlade(cf)
	local anchor = Common.host("WindBlade", cf)
	local blade = { Anchor = anchor, Layers = {}, Echoes = {} }
	local function layer(count, color0, color1, transparency, emission, width, widthScale, depthOffset, isEcho)
		local line = Common.beamLine(anchor, count, color0, color1, transparency, emission, width)
		local entry = { Line = line, Width = width, WidthScale = widthScale, Depth = depthOffset }
		table.insert(blade.Layers, entry)
		if isEcho then
			table.insert(blade.Echoes, entry)
		end
		Common.setCrescentWidth(line, width)
		placeCrescent(line, widthScale, depthOffset, 0)
	end
	layer(23, C.Mint, C.White, 0.5, 0.6, 1.2, 1, 0) -- cuerpo translúcido
	layer(23, C.White, C.White, 0, 1, 0.2, 1, -0.15) -- filo brillante
	layer(23, C.White, C.Mint, 0.15, 1, 0.07, 0.98, 0.35) -- línea interior
	layer(19, C.Mint, C.Teal, 0.7, 0.5, 0.5, 0.92, 0.8, true) -- eco 1
	layer(15, C.Teal, C.Mint, 0.8, 0.4, 0.3, 0.8, 1.6, true) -- eco 2

	-- Líneas de velocidad
	blade.Trails = {}
	for k = 1, 7 do
		local point = crescentPoint(k / 8, 1, 0.1)
		local a0 = Instance.new("Attachment")
		a0.Position = point + Vector3.new(0, 0.05, 0)
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = point - Vector3.new(0, 0.05, 0)
		a1.Parent = anchor
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.16
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.LightEmission = 0.8
		trail.Color = sparkColors()
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = anchor
		table.insert(blade.Trails, trail)
	end

	-- Polvo que levanta al pasar cerca del suelo
	blade.DustHost = Common.host("WindBladeDust", CFrame.new(cf.Position), Vector3.new(3, 0.2, 3))
	blade.Dust = Common.dust("WindBlade", blade.DustHost, C.Dust, {
		Rate = 70,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(50, 50),
		Speed = NumberRange.new(4, 9),
		Lifetime = NumberRange.new(0.4, 0.8),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) }),
		Enabled = false,
	})
	return blade
end

local function dissipateBlade(blade)
	blade.Dust.Enabled = false
	Common.animate(0.15, function(t)
		local a = t / 0.15
		for _, layer in blade.Layers do
			Common.setCrescentWidth(layer.Line, layer.Width * (1 + a))
			Common.setTransparency(layer.Line, layer.Line.Transparency + (1 - layer.Line.Transparency) * a)
		end
	end)
	Debris:AddItem(blade.Anchor, 0.2)
	Debris:AddItem(blade.DustHost, 1)
end

Wind.WindBlade = {
	Projectile = {
		Create = function(data)
			slashFlash(data.Origin, data.Direction)
			Common.spawnCustom("WindBlade", "Cast", Common.lookAlong(data.Origin, data.Direction))
			local cf = Common.lookAlong(data.Origin, data.Direction) * BLADE_TILT
			return {
				Blade = if Common.hideDefault("WindBlade") then nil else buildBlade(cf),
				Custom = Common.attachCustom("WindBlade", "Body", cf),
				Ignore = { data.Caster },
				Right = cf.RightVector,
			}
		end,
		Update = function(state, position, direction, t)
			local cf = Common.lookAlong(position, direction) * BLADE_TILT
			state.Right = cf.RightVector
			if state.Custom then
				state.Custom:Move(cf)
			end
			local blade = state.Blade
			if not blade then
				return
			end
			blade.Anchor.CFrame = cf
			for k, echo in blade.Echoes do
				placeCrescent(echo.Line, echo.WidthScale, echo.Depth, t + k)
				local flicker = 0.5 + 0.5 * math.sin(t * 40 + k * 2)
				Common.setCrescentWidth(echo.Line, echo.Width * (0.7 + 0.3 * flicker))
			end
			placeCrescent(blade.Layers[1].Line, 1, 0, t)
			if not state.Started then
				state.Started = true
				for _, trail in blade.Trails do
					trail.Enabled = true
				end
			end
			local ground = Common.castWorld(position, Vector3.new(0, -9, 0), state.Ignore)
			if ground then
				blade.DustHost.CFrame = CFrame.new(ground.Position)
				blade.Dust.Enabled = true
			else
				blade.Dust.Enabled = false
			end
		end,
		-- Atraviesa a un enemigo: corte pequeño sin detenerse
		Hit = function(state, position, normal)
			cutFlash("WindBlade", position, if typeof(normal) == "Vector3" then normal else -Vector3.zAxis, 0.5, false)
		end,
		End = function(state, position, normal, hit)
			if state.Custom then
				state.Custom:Stop()
			end
			if hit and typeof(normal) == "Vector3" then
				if state.Blade then
					state.Blade.Anchor:Destroy()
					state.Blade.DustHost:Destroy()
				end
				cutFlash("WindBlade", position, normal, 1, true, state.Right)
			elseif state.Blade then
				dissipateBlade(state.Blade)
			end
		end,
	},
}

---------------------------------------------------------------------
-- GALE PALM
---------------------------------------------------------------------

Wind.GalePalm = {
	Blast = function(data)
		if typeof(data.Origin) ~= "Vector3" or typeof(data.Direction) ~= "Vector3" then
			return
		end
		local origin, direction = data.Origin, data.Direction.Unit
		local range = data.Range or 15
		local halfAngle = math.rad(data.HalfAngle or 42)
		local spread = math.tan(halfAngle)
		Common.spawnCustom("GalePalm", "Cast", Common.lookAlong(origin, direction))
		if Common.hideDefault("GalePalm") then
			return
		end

		-- Golpe de presión en la palma
		local burst = Common.ball(nil, C.Mint, 0.3, Enum.Material.ForceField)
		Common.animate(0.2, function(t)
			local a = Common.easeOut(t / 0.2)
			burst.Size = Vector3.one * (1 + 5 * a)
			burst.CFrame = CFrame.new(origin + direction * 1.2)
			burst.Transparency = 0.3 + 0.7 * a
		end)
		Debris:AddItem(burst, 0.25)

		-- Anillos que viajan hacia adelante abriéndose con el cono
		for k = 0, 2 do
			local ringAnchor = Common.host("GaleRing", Common.lookAlong(origin, direction))
			local ring = Common.beamLine(ringAnchor, 29, C.White, C.Mint, 0.1, 0.9, 0.45)
			task.delay(k * 0.05, function()
				Common.animate(0.26, function(t)
					local a = Common.easeOut(t / 0.26)
					local distance = 1 + (range - 1) * a
					Common.placeCircle(ring, Vector3.zAxis, math.max(distance * spread, 1), Vector3.new(0, 0, -distance))
					Common.setUniformWidth(ring, 0.45 * (1 - a))
					Common.setTransparency(ring, 0.1 + 0.9 * a)
				end)
			end)
			Debris:AddItem(ringAnchor, 0.45)
		end

		-- Líneas de viento que salen dentro del cono
		local lineAnchor = Common.host("GaleLines", Common.lookAlong(origin, direction))
		local lines = {}
		local rng = Random.new()
		for _ = 1, 14 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radial = rng:NextNumber(0, spread)
			table.insert(lines, {
				Line = Common.beamLine(lineAnchor, 2, C.White, C.Mint, 0.1, 0.9, rng:NextNumber(0.1, 0.22)),
				Direction = Vector3.new(math.cos(angle) * radial, math.sin(angle) * radial, -1).Unit,
				Length = rng:NextNumber(3, 6),
				Delay = rng:NextNumber(0, 0.06),
			})
		end
		Common.animate(0.32, function(t)
			for _, entry in lines do
				local a = Common.easeOut(math.max(t - entry.Delay, 0) / 0.24)
				local head = (1 + (range - 1) * a)
				entry.Line.Nodes[1].Position = entry.Direction * math.max(head - entry.Length, 0.5)
				entry.Line.Nodes[2].Position = entry.Direction * head
				Common.setUniformWidth(entry.Line, entry.Line.Width * (1 - a), 0)
			end
		end)
		Debris:AddItem(lineAnchor, 0.4)

		-- Polvo en el suelo a lo largo del cono
		local ground = Common.groundBelow(origin + direction * range * 0.5, { data.Caster }, 10)
		if ground then
			groundDust("GalePalm", ground.Position, ground.Normal, range * 0.6, 22)
		end
		Common.shake(origin, 1.2, 60, 0.25)
	end,
}

---------------------------------------------------------------------
-- WIND SWEEP
---------------------------------------------------------------------

Wind.WindSweep = {
	Sweep = function(data)
		if typeof(data.Origin) ~= "Vector3" or typeof(data.Direction) ~= "Vector3" then
			return
		end
		local origin = data.Origin
		local flat = Vector3.new(data.Direction.X, 0, data.Direction.Z)
		local direction = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local range = data.Range or 13
		local halfAngle = math.rad(data.HalfAngle or 70)
		Common.spawnCustom("WindSweep", "Cast", Common.lookAlong(origin, direction))
		if Common.hideDefault("WindSweep") then
			return
		end

		-- Barrido: arcos horizontales que se dibujan de un lado al otro
		local anchor = Common.host("WindSweep", CFrame.lookAt(origin, origin + direction))
		local arcs = {
			{ Line = Common.beamLine(anchor, 25, C.White, C.Mint, 0, 1, 0.4), Radius = range * 0.85, Delay = 0 },
			{ Line = Common.beamLine(anchor, 25, C.Mint, C.Teal, 0.45, 0.6, 1.6), Radius = range * 0.8, Delay = 0 },
			{ Line = Common.beamLine(anchor, 21, C.White, C.Mint, 0.25, 0.9, 0.25), Radius = range * 0.55, Delay = 0.04 },
			{ Line = Common.beamLine(anchor, 17, C.Mint, C.White, 0.4, 0.8, 0.18), Radius = range * 0.32, Delay = 0.08 },
		}
		Common.animate(0.42, function(t)
			for k, arc in arcs do
				local local_t = math.max(t - arc.Delay, 0)
				local reveal = Common.easeOut(local_t / 0.16)
				local fade = math.clamp((local_t - 0.14) / 0.2, 0, 1)
				local count = #arc.Line.Nodes
				for i, node in arc.Line.Nodes do
					local f = math.min((i - 1) / (count - 1), reveal)
					local angle = -halfAngle + 2 * halfAngle * f
					node.Position = Vector3.new(math.sin(angle) * arc.Radius, 0.4 + k * 0.15, -math.cos(angle) * arc.Radius)
				end
				Common.setCrescentWidth(arc.Line, arc.Line.Width * (1 - fade))
			end
		end)
		Debris:AddItem(anchor, 0.5)

		pressureRing(origin, Vector3.yAxis, 2, range * 1.1, 0.35, 0.35)

		-- Polvo a lo largo del arco
		local ground = Common.groundBelow(origin, { data.Caster }, 8)
		if ground then
			for k = -2, 2 do
				local angle = halfAngle * k / 2
				local point = origin + (CFrame.lookAt(origin, origin + direction) * CFrame.Angles(0, -angle, 0)).LookVector * range * 0.7
				groundDust("WindSweep", Vector3.new(point.X, ground.Position.Y, point.Z), ground.Normal, 3, 6)
			end
		end
		Common.shake(origin, 0.9, 50, 0.2)
	end,
}

return Wind
