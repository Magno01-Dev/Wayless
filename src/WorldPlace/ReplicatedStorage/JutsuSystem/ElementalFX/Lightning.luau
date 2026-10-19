--!nonstrict
-- ReplicatedStorage > JutsuSystem > ElementalFX > Lightning   (ModuleScript, solo cliente)
--
-- VFX de Raiton estilo anime: rayos en zigzag (núcleo blanco + resplandor) que cambian de
-- forma varias veces por segundo, destellos, chispas y luz.
--   LightningBolt     rayo instantáneo con ramas
--   LightningStream   corriente continua desde la boca/mano (pulsos del servidor)
--   StaticBurst       cúpula eléctrica alrededor del personaje
--   LightningSenbon   agujas eléctricas en ráfaga

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Common = require(script.Parent:WaitForChild("Common"))

local C = Common.Palettes.Lightning
local CRACKLE_RATE = 24 -- veces por segundo que los rayos cambian de forma

local Lightning = {}

local function sparkColors()
	return ColorSequence.new(C.Core, C.Cyan)
end

local function light(parent, range, brightness)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = C.Cyan
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = parent
	return pointLight
end

local function flashOrb(position, size, duration)
	local orb = Common.ball(nil, C.Core, 0, Enum.Material.Neon)
	Common.animate(duration, function(t)
		local a = t / duration
		orb.Size = Vector3.one * ((size * Common.easeOut(t / (duration * 0.4))) * (1 - a) + 0.05)
		orb.CFrame = CFrame.new(position)
		orb.Transparency = a
	end)
	Debris:AddItem(orb, duration + 0.05)
end

local function scorch(position, normal, size)
	local mark = Common.disc(nil, C.Scorch, 0.25)
	mark.Size = Vector3.new(0.05, size, size)
	mark.CFrame = Common.discCFrame(position + normal * 0.03, normal)
	Common.animate(2, function(t)
		mark.Transparency = 0.25 + 0.75 * math.clamp((t - 0.8) / 1.2, 0, 1)
	end)
	Debris:AddItem(mark, 2.1)
end

-- Chispas + mini rayos al chocar
local function sparkImpact(kind, position, normal, size, rng)
	local anchor = Common.host(kind .. "_Impact", CFrame.new(position), Vector3.one * 0.6)
	local pointLight = light(anchor, 14 * size, 6)
	local bolts = {}
	for _ = 1, math.floor(5 * size + 1) do
		table.insert(bolts, { Bolt = Common.newBolt(anchor, 5, 0.06 * size, 0.3 * size, C), Direction = (Common.randomUnit(rng) + normal * 0.8).Unit })
	end
	local lastTick = -1
	Common.animate(0.3, function(t)
		local a = t / 0.3
		local tick = math.floor(t * CRACKLE_RATE)
		if tick ~= lastTick then
			lastTick = tick
			pointLight.Brightness = 6 * (1 - a) * rng:NextNumber(0.5, 1)
			for _, entry in bolts do
				Common.jag(entry.Bolt, Vector3.zero, entry.Direction * rng:NextNumber(1.5, 3.5) * size, 0.35 * size, rng)
				Common.setBoltScale(entry.Bolt, (1 - a) * (if rng:NextNumber() > 0.2 then 1 else 0))
			end
		end
	end)
	local holder = Common.emitterHolder(nil, position, normal)
	Common.sparks(kind, holder, sparkColors(), {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(70, 70),
		Speed = NumberRange.new(15, 35),
	}):Emit(math.floor(30 * size))
	flashOrb(position, 2.5 * size, 0.15)
	Common.spawnCustom(kind, "Impact", Common.upCFrame(position, normal))
	Debris:AddItem(anchor, 0.35)
	Debris:AddItem(holder, 0.8)
end

---------------------------------------------------------------------
-- LIGHTNING BOLT
---------------------------------------------------------------------

Lightning.LightningBolt = {
	Bolt = function(data)
		if typeof(data.Origin) ~= "Vector3" or typeof(data.End) ~= "Vector3" then
			return
		end
		local origin, finish = data.Origin, data.End
		local delta = finish - origin
		if delta.Magnitude < 0.1 then
			return
		end
		local direction = delta.Unit
		local rng = Random.new()
		Common.spawnCustom("LightningBolt", "Cast", Common.lookAlong(origin, direction))

		if not Common.hideDefault("LightningBolt") then
			local anchor = Common.host("LightningBolt", CFrame.new(origin), Vector3.one * 0.6)
			local pointLight = light(anchor, 18, 8)
			local count = math.clamp(math.floor(delta.Magnitude / 2.5), 8, 26)
			local main = Common.newBolt(anchor, count, 0.22, 1.0, C)
			local inner = Common.newBolt(anchor, count, 0.08, 0.4, C, C.Violet)
			local branches = {}
			for _ = 1, 4 do
				table.insert(branches, Common.newBolt(anchor, 6, 0.08, 0.4, C))
			end

			local lastTick = -1
			Common.animate(0.32, function(t)
				local a = t / 0.32
				local tick = math.floor(t * 20)
				if tick == lastTick then
					return
				end
				lastTick = tick
				local jitter = math.min(1.6, delta.Magnitude * 0.05)
				Common.jag(main, Vector3.zero, delta, jitter, rng)
				Common.jag(inner, Vector3.zero, delta, jitter * 0.6, rng)
				Common.setBoltScale(main, (1 - a) * rng:NextNumber(0.7, 1))
				Common.setBoltScale(inner, (1 - a))
				-- Ramas desde puntos del rayo principal
				for _, branch in branches do
					local node = main.Nodes[rng:NextInteger(2, #main.Nodes - 1)]
					local start = node.Position
					local out = (Common.randomUnit(rng) + direction * 0.6).Unit * rng:NextNumber(3, 6)
					Common.jag(branch, start, start + out, 0.6, rng)
					Common.setBoltScale(branch, (1 - a) * (if rng:NextNumber() > 0.3 then 1 else 0))
				end
				pointLight.Brightness = 8 * (1 - a) * rng:NextNumber(0.5, 1)
			end)
			Debris:AddItem(anchor, 0.4)
			flashOrb(origin, 2, 0.15)
		end

		-- Si termina en una superficie: chispas y quemadura
		local surface = Common.castWorld(finish - direction * 1.5, direction * 3, { data.Caster })
		local normal = if surface then surface.Normal else -direction
		sparkImpact("LightningBolt", finish, normal, 1, rng)
		if surface then
			scorch(surface.Position, surface.Normal, 3)
		end
		Common.shake(finish, 1.2, 70, 0.2)
	end,
}

---------------------------------------------------------------------
-- LIGHTNING STREAM
---------------------------------------------------------------------

local streams = {}

local function buildStream()
	local anchor = Common.host("LightningStream", CFrame.new(), Vector3.one * 0.6)
	local stream = {
		Anchor = anchor,
		Main = Common.newBolt(anchor, 16, 0.18, 0.8, C),
		Side = { Common.newBolt(anchor, 12, 0.06, 0.3, C, C.Violet), Common.newBolt(anchor, 12, 0.06, 0.3, C) },
		Light = light(anchor, 12, 4),
		Orb = Common.ball(nil, C.Cyan, 0.5, Enum.Material.Neon),
		EndHolder = Common.host("StreamEnd", CFrame.new(), Vector3.one * 0.8),
		LastTick = -1,
	}
	stream.EndSparks = Common.sparks("LightningStream", stream.EndHolder, sparkColors(), {
		Speed = NumberRange.new(8, 18),
		Lifetime = NumberRange.new(0.12, 0.25),
		Rate = 60,
	})
	return stream
end

local function stopStream(id)
	local entry = streams[id]
	if not entry then
		return
	end
	streams[id] = nil
	entry.Connection:Disconnect()
	local stream = entry.Stream
	if stream then
		stream.EndSparks.Enabled = false
		Common.animate(0.12, function(t)
			local fade = 1 - t / 0.12
			Common.setBoltScale(stream.Main, fade)
			for _, side in stream.Side do
				Common.setBoltScale(side, fade)
			end
			stream.Orb.Transparency = 1 - 0.5 * fade
		end)
		Debris:AddItem(stream.Anchor, 0.2)
		Debris:AddItem(stream.Orb, 0.2)
		Debris:AddItem(stream.EndHolder, 0.5)
	end
	if entry.Custom then
		entry.Custom:Stop()
	end
end

Lightning.LightningStream = {
	-- El servidor manda un pulso por cada tick de daño; mientras lleguen, la corriente sigue
	Pulse = function(data)
		if typeof(data.Id) ~= "number" or typeof(data.Origin) ~= "Vector3" or typeof(data.End) ~= "Vector3" then
			return
		end
		local entry = streams[data.Id]
		local caster = data.Caster
		local head = if typeof(caster) == "Instance" then caster:FindFirstChild("Head") else nil
		if not entry then
			entry = {
				Stream = if Common.hideDefault("LightningStream") then nil else buildStream(),
				Custom = Common.attachCustom("LightningStream", "Body", CFrame.new(data.Origin)),
				Rng = Random.new(),
				Start = os.clock(),
			}
			streams[data.Id] = entry
			Common.spawnCustom("LightningStream", "Cast", CFrame.new(data.Origin))
			entry.Connection = RunService.RenderStepped:Connect(function()
				local now = os.clock()
				if now > entry.Expires + 0.12 or (entry.Head and not entry.Head.Parent) then
					stopStream(data.Id)
					return
				end
				-- El origen sigue a la cabeza del lanzador entre pulsos
				local origin = if entry.Head then entry.Head.Position + entry.HeadOffset else entry.Origin
				local finish = entry.Finish
				if entry.Custom then
					entry.Custom:Move(Common.lookAlong(origin, finish - origin))
				end
				local stream = entry.Stream
				if not stream then
					return
				end
				stream.Orb.CFrame = CFrame.new(origin)
				stream.EndHolder.CFrame = CFrame.new(finish)
				local t = Common.stylizedTime(now - entry.Start)
				local tick = math.floor(t * 30)
				if tick == stream.LastTick then
					return
				end
				stream.LastTick = tick
				local rng = entry.Rng
				local kick = math.max(0, 1 - (now - entry.LastPulse) / 0.14)
				stream.Anchor.CFrame = CFrame.new(origin)
				local delta = finish - origin
				local jitter = math.min(0.9, delta.Magnitude * 0.04)
				Common.jag(stream.Main, Vector3.zero, delta, jitter, rng)
				Common.setBoltScale(stream.Main, (0.85 + 0.3 * kick) * rng:NextNumber(0.8, 1))
				for _, side in stream.Side do
					Common.jag(side, Vector3.zero, delta, jitter * 2.2, rng)
					Common.setBoltScale(side, if rng:NextNumber() > 0.25 then 1 else 0)
				end
				stream.Orb.Size = Vector3.one * (0.9 + 0.5 * kick) * rng:NextNumber(0.8, 1.15)
				stream.Light.Brightness = (2.5 + 2 * kick) * rng:NextNumber(0.7, 1)
			end)
		end
		entry.Origin = data.Origin
		entry.Finish = data.End
		entry.LastPulse = os.clock()
		entry.Expires = os.clock() + math.clamp(data.Hold or 0.15, 0.08, 0.4)
		if head then
			entry.Head = head
			entry.HeadOffset = data.Origin - head.Position
		end
		-- Chispas donde pega en cada pulso
		if entry.Stream then
			local direction = data.End - data.Origin
			if direction.Magnitude > 0.1 then
				Common.sparks("LightningStream", entry.Stream.EndHolder, sparkColors(), {
					Speed = NumberRange.new(15, 30),
				}):Emit(8)
			end
		end
	end,
}

---------------------------------------------------------------------
-- STATIC BURST
---------------------------------------------------------------------

Lightning.StaticBurst = {
	Burst = function(data)
		if typeof(data.Position) ~= "Vector3" then
			return
		end
		local center = data.Position
		local radius = data.Radius or 11
		local rng = Random.new()
		Common.spawnCustom("StaticBurst", "Cast", CFrame.new(center))
		if Common.hideDefault("StaticBurst") then
			return
		end

		local anchor = Common.host("StaticBurst", CFrame.new(center), Vector3.one * 0.6)
		-- Cúpula: el material ForceField ya viene animado y se ve eléctrico
		local dome = Common.ball(nil, C.Cyan, 0.1, Enum.Material.ForceField)
		local shell = Common.ball(nil, C.Blue, 0.85, Enum.Material.Neon)
		local flash = Common.ball(nil, C.Core, 0, Enum.Material.Neon)
		dome.CFrame, shell.CFrame, flash.CFrame = CFrame.new(center), CFrame.new(center), CFrame.new(center)
		local pointLight = light(anchor, 26, 10)

		local bolts = {}
		for _ = 1, 10 do
			local direction = Common.randomUnit(rng)
			if direction.Y < -0.3 then
				direction = Vector3.new(direction.X, -direction.Y * 0.5, direction.Z).Unit
			end
			table.insert(bolts, { Bolt = Common.newBolt(anchor, 8, 0.12, 0.6, C), Direction = direction, Reach = rng:NextNumber(0.6, 1) })
		end

		-- Rayos por el suelo, onda y quemadura
		local groundBolts, ring, groundAnchor = {}, nil, nil
		local ground = Common.groundBelow(center, { data.Caster }, 8)
		if ground then
			groundAnchor = Common.host("StaticGround", Common.upCFrame(ground.Position + ground.Normal * 0.15, ground.Normal))
			for k = 1, 8 do
				local angle = k / 8 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
				table.insert(groundBolts, { Bolt = Common.newBolt(groundAnchor, 7, 0.1, 0.45, C), Direction = Vector3.new(math.cos(angle), 0, math.sin(angle)) })
			end
			ring = Common.disc(nil, C.Cyan, 0.5, Enum.Material.Neon)
			ring.CFrame = Common.discCFrame(ground.Position + ground.Normal * 0.06, ground.Normal)
			local mark = Common.disc(nil, C.Scorch, 0.25)
			mark.CFrame = Common.discCFrame(ground.Position + ground.Normal * 0.03, ground.Normal)
			Common.animate(2.4, function(t)
				local size = 2 * radius * 0.7 * Common.easeOut(t / 0.15) + 0.1
				mark.Size = Vector3.new(0.05, size, size)
				mark.Transparency = 0.25 + 0.75 * math.clamp((t - 1) / 1.4, 0, 1)
			end)
			Debris:AddItem(mark, 2.5)
			Debris:AddItem(ring, 0.7)
			Debris:AddItem(groundAnchor, 0.7)
		end

		Common.sparks("StaticBurst", anchor, sparkColors(), { Speed = NumberRange.new(20, 45) }):Emit(70)
		Common.sparks("StaticBurst", anchor, sparkColors(), {
			Speed = NumberRange.new(8, 16),
			Lifetime = NumberRange.new(0.4, 0.8),
			Acceleration = Vector3.new(0, -30, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
		}):Emit(40)
		Common.shake(center, 2, 90, 0.35)

		local lastTick = -1
		Common.animate(0.6, function(t)
			local grow = Common.easeOut(t / 0.16)
			local fade = math.clamp((t - 0.16) / 0.44, 0, 1)
			local r = radius * grow
			dome.Size = Vector3.one * (2 * r + 0.1)
			dome.Transparency = 0.1 + 0.9 * fade
			shell.Size = Vector3.one * (2 * r * 0.97 + 0.1)
			shell.Transparency = 0.82 + 0.18 * fade
			local flashFade = math.clamp(t / 0.18, 0, 1)
			flash.Size = Vector3.one * ((0.5 + 5 * Common.easeOut(t / 0.08)) * (1 - flashFade) + 0.05)
			flash.Transparency = flashFade
			if ring then
				local size = 2 * r * 1.05 + 0.1
				ring.Size = Vector3.new(0.08, size, size)
				ring.Transparency = 0.5 + 0.5 * fade
			end
			local tick = math.floor(t * CRACKLE_RATE)
			if tick ~= lastTick then
				lastTick = tick
				pointLight.Brightness = 10 * (1 - fade) * rng:NextNumber(0.6, 1)
				for _, entry in bolts do
					Common.jag(entry.Bolt, Vector3.zero, entry.Direction * r * entry.Reach, 0.8 + r * 0.06, rng)
					Common.setBoltScale(entry.Bolt, (1 - fade) * rng:NextNumber(0.5, 1))
				end
				for _, entry in groundBolts do
					Common.jag(entry.Bolt, entry.Direction * r * 0.15, entry.Direction * r, 0.4 + r * 0.05, rng)
					Common.setBoltScale(entry.Bolt, (1 - fade) * rng:NextNumber(0.5, 1))
				end
			end
		end)
		Debris:AddItem(dome, 0.7)
		Debris:AddItem(shell, 0.7)
		Debris:AddItem(flash, 0.7)
		Debris:AddItem(anchor, 1)
	end,
}

---------------------------------------------------------------------
-- LIGHTNING SENBON
---------------------------------------------------------------------

-- Los cilindros de Roblox van a lo largo del eje X: se giran para que apunten hacia adelante
local ALONG_X = CFrame.Angles(0, math.rad(90), 0)

local function buildNeedle()
	local anchor = Common.host("LightningSenbon", CFrame.new(), Vector3.one * 0.3)
	local needle = {
		Anchor = anchor,
		Core = Common.newPart("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 0.12, 0.12), Color = C.Core, Material = Enum.Material.Neon }),
		Glow = Common.newPart("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.4, 0.4), Color = C.Cyan, Material = Enum.Material.Neon, Transparency = 0.6 }),
		Arcs = { Common.newBolt(anchor, 5, 0.04, 0.2, C), Common.newBolt(anchor, 5, 0.04, 0.2, C, C.Violet) },
		LastTick = -1,
	}
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.12, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.12, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.12
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = sparkColors()
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Enabled = false
	trail.Parent = anchor
	needle.Trail = trail
	return needle
end

Lightning.LightningSenbon = {
	Projectile = {
		Create = function(data)
			local rng = Random.new()
			-- Chispa pequeña donde sale cada aguja
			local holder = Common.host("SenbonCast", CFrame.new(data.Origin), Vector3.one * 0.4)
			Common.sparks("LightningSenbon", holder, sparkColors(), {
				Speed = NumberRange.new(6, 14),
				Lifetime = NumberRange.new(0.1, 0.2),
			}):Emit(6)
			Debris:AddItem(holder, 0.4)
			Common.spawnCustom("LightningSenbon", "Cast", Common.lookAlong(data.Origin, data.Direction))
			return {
				Needle = if Common.hideDefault("LightningSenbon") then nil else buildNeedle(),
				Custom = Common.attachCustom("LightningSenbon", "Body", Common.lookAlong(data.Origin, data.Direction)),
				Rng = rng,
				Direction = data.Direction,
			}
		end,
		Update = function(state, position, direction, t)
			local cf = Common.lookAlong(position, direction)
			if state.Custom then
				state.Custom:Move(cf)
			end
			local needle = state.Needle
			if not needle then
				return
			end
			needle.Anchor.CFrame = cf
			needle.Core.CFrame = cf * ALONG_X
			needle.Glow.CFrame = cf * ALONG_X
			local tick = math.floor(Common.stylizedTime(t) * 30)
			if tick ~= needle.LastTick then
				needle.LastTick = tick
				local rng = state.Rng
				for _, arc in needle.Arcs do
					local from = Vector3.new(0, 0, rng:NextNumber(-1.2, 0.2))
					local to = from + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), rng:NextNumber(0.6, 1.4))
					Common.jag(arc, from, to, 0.2, rng)
					Common.setBoltScale(arc, if rng:NextNumber() > 0.25 then 1 else 0)
				end
				needle.Glow.Transparency = rng:NextNumber(0.5, 0.7)
			end
			if not state.Started then
				state.Started = true
				needle.Trail.Enabled = true
			end
		end,
		End = function(state, position, normal, hit)
			if state.Needle then
				state.Needle.Anchor:Destroy()
				state.Needle.Core:Destroy()
				state.Needle.Glow:Destroy()
			end
			if state.Custom then
				state.Custom:Stop()
			end
			if hit and typeof(normal) == "Vector3" then
				sparkImpact("LightningSenbon", position, normal, 0.5, state.Rng)
			end
		end,
	},
}

return Lightning
