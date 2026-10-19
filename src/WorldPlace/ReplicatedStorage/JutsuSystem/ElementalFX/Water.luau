--!nonstrict
-- ReplicatedStorage > JutsuSystem > ElementalFX > Water   (ModuleScript, solo cliente)
--
-- VFX de Suiton estilo anime: capa exterior translúcida + núcleo oscuro + contorno blanco.
--   WaterBullet   carga en la boca, bala gelatinosa con cola y espirales, impacto con corona
--   WaterWave     ola que avanza pegada al suelo y rompe al final
--   WaterWhip     chorro continuo que sale de la boca y sigue al personaje
--   WaterPrison   orbe de agua y burbuja que encierra al objetivo

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Common = require(script.Parent:WaitForChild("Common"))

local C = Common.Palettes.Water
local GLASS = Enum.Material.Glass
local MIST_COLORS = ColorSequence.new(C.Light, C.Foam)

local Water = {}

local movedParts, movedCFrames = {}, {}

local function bulkMove(pieces, cf)
	table.clear(movedParts)
	table.clear(movedCFrames)
	for _, piece in pieces do
		table.insert(movedParts, piece.Part)
		table.insert(movedCFrames, cf * piece.Offset)
	end
	Workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Salpicadura genérica (impactos de WaterBullet / WaterPrison)
local function splash(kind, position, normal, scale)
	local model = Common.newModel(kind .. "_Splash")
	Common.outline(model, C.Outline)
	local u = Common.planeBasis(normal)

	local splat, splatMesh = Common.ellipsoid(model, Vector3.one, C.Body, 0.2, GLASS)
	Common.animate(0.45, function(t)
		local a = Common.easeOut(t / 0.45)
		splatMesh.Scale = Vector3.new(3 + 7 * a, math.max(2.8 * (1 - a), 0.15), 3 + 7 * a) * scale
		splat.CFrame = CFrame.fromMatrix(position + normal * (0.6 * (1 - a) * scale), u, normal)
		splat.Transparency = 0.2 + 0.8 * a ^ 2
	end)

	Common.crown(model, C, position, normal, 10, 1.3 * scale, 4.5 * scale, 0.6, 0.55 * scale)
	Common.ripple(model, position, normal, 2 * scale, 16 * scale, 0.6, C.Light, 0.25)
	Common.ripple(model, position, normal, 1.5 * scale, 9 * scale, 0.45, C.Body, 0.3)

	local puddle = Common.disc(model, C.Deep, 0.45)
	local puddleCF = Common.discCFrame(position + normal * 0.03, normal)
	Common.animate(1.8, function(t)
		local size = (5 + 3 * Common.easeOut(t / 0.3)) * scale
		puddle.Size = Vector3.new(0.08, size, size)
		puddle.CFrame = puddleCF
		puddle.Transparency = 0.45 + 0.55 * math.clamp((t - 0.8) / 1.0, 0, 1)
	end)

	local holder = Common.emitterHolder(model, position, normal, Vector3.new(1.5, 0.2, 1.5) * scale)
	Common.droplets(kind, holder, C, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(60, 60),
		Speed = NumberRange.new(15, 35),
		Lifetime = NumberRange.new(0.5, 0.9),
		Acceleration = Vector3.new(0, -80, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
	}):Emit(math.floor(70 * scale))
	Common.droplets(kind, holder, C, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(85, 85),
		Speed = NumberRange.new(10, 20),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
	}):Emit(math.floor(25 * scale))
	Common.mist(kind, holder, MIST_COLORS, { Speed = NumberRange.new(4, 9) }):Emit(12)

	Common.shake(position, 1.2 * scale, 70)
	Common.spawnCustom(kind, "Impact", Common.upCFrame(position, normal))
	Debris:AddItem(model, 2.5)
end

-- Revienta en el aire (llegó al alcance máximo)
local function airBurst(kind, position, direction, radius)
	local model = Common.newModel(kind .. "_AirBurst")
	Common.outline(model, C.Outline)
	local shell, shellMesh = Common.ellipsoid(model, Vector3.one, C.Body, 0.25, GLASS)
	Common.animate(0.22, function(t)
		local a = Common.easeOut(t / 0.22)
		shellMesh.Scale = Vector3.one * radius * (2 + 2.5 * a)
		shell.CFrame = Common.lookAlong(position, direction)
		shell.Transparency = 0.25 + 0.75 * a
	end)
	local holder = Common.host("Burst", CFrame.new(position), Vector3.one * 2, model)
	Common.droplets(kind, holder, C, {
		Speed = NumberRange.new(10, 22),
		Lifetime = NumberRange.new(0.5, 1),
		Acceleration = Vector3.new(0, -70, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
	}):Emit(60)
	Common.mist(kind, holder, MIST_COLORS):Emit(8)
	Debris:AddItem(model, 2)
end

---------------------------------------------------------------------
-- WATER BULLET
---------------------------------------------------------------------

local charges = {} -- [caster] = estado de la carga en la boca

local function stopCharge(caster)
	local charge = charges[caster]
	if not charge then
		return
	end
	charges[caster] = nil
	charge.Connection:Disconnect()
	charge.Gather.Enabled = false
	Debris:AddItem(charge.Model, 0.4)
	Common.animate(0.12, function(t)
		charge.Orb.Transparency = 0.25 + 0.75 * (t / 0.12)
	end)
end

local function startCharge(kind, data)
	local caster = data.Caster
	if typeof(caster) ~= "Instance" or not caster:IsA("Model") then
		return
	end
	stopCharge(caster)
	local head = caster:FindFirstChild("Head")
	if not head then
		return
	end

	local radius = if typeof(data.Radius) == "number" then data.Radius else 1.6
	local model = Common.newModel(kind .. "_Charge")
	Common.outline(model, C.Outline)
	local orb, orbMesh = Common.ellipsoid(model, Vector3.one * 0.1, C.Body, 0.25, GLASS)
	-- Gotas que llegan desde una esfera alrededor y convergen al centro
	local gatherer = Common.host("Gather", CFrame.new(head.Position), Vector3.one * 7, model)
	local gather = Common.droplets(kind, gatherer, C, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(12, 16),
		Lifetime = NumberRange.new(0.22, 0.28),
		Acceleration = Vector3.zero,
		Rate = 70,
	})

	local start = os.clock()
	local charge = { Model = model, Orb = orb, Gather = gather }
	charge.Connection = RunService.RenderStepped:Connect(function()
		if not head.Parent then
			stopCharge(caster)
			return
		end
		local t = Common.stylizedTime(os.clock() - start)
		local mouth = Common.mouthPosition(head) + head.CFrame.LookVector * 1.2
		local grow = Common.easeOut(t / 0.9)
		local wobble = 1 + 0.12 * math.sin(t * 40)
		orbMesh.Scale = Vector3.new(wobble, 1 / wobble, 1) * (radius * 1.2 * grow + 0.1)
		orb.CFrame = CFrame.new(mouth) * head.CFrame.Rotation
		gatherer.CFrame = CFrame.new(mouth)
		if t > 4 then
			stopCharge(caster)
		end
	end)
	charges[caster] = charge
end

local function buildBullet(kind, radius)
	local r = radius
	local model = Common.newModel(kind)
	Common.outline(model, C.Outline)
	local bullet = { Model = model, Pieces = {}, Radius = r }

	local function add(scale, offset, color, transparency, material)
		local part, mesh = Common.ellipsoid(model, scale, color, transparency, material)
		table.insert(bullet.Pieces, { Part = part, Mesh = mesh, Offset = offset, Scale = scale })
		return part
	end

	bullet.Shell = add(Vector3.new(2, 2, 2.4) * r, CFrame.new(), C.Body, 0.25, GLASS)
	add(Vector3.new(1.3, 1.3, 1.5) * r, CFrame.new(0, 0, 0.1 * r), C.Deep, 0.05)
	-- Brillo de espuma en el frente y destello
	add(Vector3.new(1.0, 0.35, 0.5) * r, CFrame.new(0, 0.48 * r, -0.62 * r) * CFrame.Angles(math.rad(-30), 0, 0), C.Foam, 0.05)
	local glint = Common.ball(model, C.Foam, 0, Enum.Material.Neon)
	glint.Size = Vector3.one * 0.35 * r
	table.insert(bullet.Pieces, { Part = glint, Offset = CFrame.new(0.38 * r, 0.5 * r, -0.45 * r) })
	-- Cola de agua y punta de espuma
	add(Vector3.new(1.4, 1.4, 4.2) * r, CFrame.new(0, 0, 1.9 * r), C.Body, 0.35, GLASS)
	add(Vector3.new(0.5, 0.5, 2.2) * r, CFrame.new(0, 0, 3.6 * r), C.Foam, 0.3)

	-- Espirales de espuma alrededor de la bala
	bullet.Spirals = {}
	for k = 1, 2 do
		local a0 = Instance.new("Attachment")
		a0.Parent = bullet.Shell
		local a1 = Instance.new("Attachment")
		a1.Parent = bullet.Shell
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.22
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.LightEmission = 0.3
		trail.Color = ColorSequence.new(C.Foam, C.Light)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Enabled = false
		trail.Parent = bullet.Shell
		table.insert(bullet.Spirals, { A0 = a0, A1 = a1, Trail = trail, Phase = k * math.pi })
	end

	bullet.Drops = Common.droplets(kind, bullet.Shell, C, {
		EmissionDirection = Enum.NormalId.Back,
		SpreadAngle = Vector2.new(35, 35),
		Speed = NumberRange.new(4, 10),
		Rate = 70,
		Enabled = false,
	})
	bullet.Mist = Common.mist(kind, bullet.Shell, MIST_COLORS, {
		EmissionDirection = Enum.NormalId.Back,
		Rate = 14,
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) }),
		Enabled = false,
	})
	return bullet
end

local function muzzle(kind, position, direction)
	local model = Common.newModel(kind .. "_Muzzle")
	Common.outline(model, C.Outline)
	Common.ripple(model, position + direction * 0.6, direction, 1.5, 7, 0.3, C.Light, 0.2)
	Common.ripple(model, position + direction * 1.8, direction, 1, 4.5, 0.25, C.Foam, 0.3)
	local holder = Common.emitterHolder(model, position, direction)
	Common.droplets(kind, holder, C, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(30, 30),
		Speed = NumberRange.new(20, 35),
		Acceleration = Vector3.new(0, -60, 0),
	}):Emit(30)
	Common.spawnCustom(kind, "Cast", Common.lookAlong(position, direction))
	Debris:AddItem(model, 1.5)
end

Water.WaterBullet = {
	Charge = function(data)
		startCharge("WaterBullet", data)
	end,
	ChargeStop = function(data)
		if typeof(data.Caster) == "Instance" then
			stopCharge(data.Caster)
		end
	end,
	Projectile = {
		Create = function(data)
			if typeof(data.Caster) == "Instance" then
				stopCharge(data.Caster)
			end
			muzzle("WaterBullet", data.Origin, data.Direction)
			local state = {
				Kind = "WaterBullet",
				Radius = data.Radius or 1.6,
				Custom = Common.attachCustom("WaterBullet", "Body", Common.lookAlong(data.Origin, data.Direction)),
			}
			if not Common.hideDefault("WaterBullet") then
				state.Bullet = buildBullet("WaterBullet", state.Radius)
			end
			return state
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
			-- Tiembla como gelatina
			local wobble = Vector3.new(1 + 0.08 * math.sin(t * 26), 1 - 0.07 * math.sin(t * 26 + 1.2), 1 + 0.06 * math.sin(t * 19))
			for _, piece in bullet.Pieces do
				if piece.Mesh then
					piece.Mesh.Scale = piece.Scale * wobble
				end
			end
			bulkMove(bullet.Pieces, cf)
			for _, spiral in bullet.Spirals do
				local angle = t * 18 + spiral.Phase
				local radial = Vector3.new(math.cos(angle), math.sin(angle), 0) * bullet.Radius * 0.95
				spiral.A0.Position = radial + Vector3.new(0, 0, 0.3 * bullet.Radius)
				spiral.A1.Position = radial * 0.8 + Vector3.new(0, 0, 0.3 * bullet.Radius)
			end
			if not state.Started then
				state.Started = true
				for _, spiral in bullet.Spirals do
					spiral.Trail.Enabled = true
				end
				bullet.Drops.Enabled = true
				bullet.Mist.Enabled = true
			end
		end,
		End = function(state, position, normal, hit)
			if state.Bullet then
				state.Bullet.Model:Destroy()
			end
			if state.Custom then
				state.Custom:Stop()
			end
			if hit and typeof(normal) == "Vector3" then
				splash("WaterBullet", position, normal, 1)
			else
				airBurst("WaterBullet", position, Vector3.zAxis, state.Radius)
			end
		end,
	},
}

---------------------------------------------------------------------
-- WATER WAVE
---------------------------------------------------------------------

local waves = {}

local function buildWave(width, height)
	local model = Common.newModel("WaterWave")
	Common.outline(model, C.Outline)
	local pieces = {}
	local function add(scale, offset, color, transparency, material, bob)
		local part, mesh = Common.ellipsoid(model, scale, color, transparency, material)
		table.insert(pieces, { Part = part, Mesh = mesh, Offset = offset, Scale = scale, Bob = bob })
		return part
	end

	-- Cuerpo de la ola y núcleo oscuro
	add(Vector3.new(width, height * 0.75, 5), CFrame.new(0, height * 0.36, 0.6), C.Body, 0.25, GLASS)
	add(Vector3.new(width * 0.9, height * 0.5, 3.4), CFrame.new(0, height * 0.3, 0.8), C.Deep, 0.05)
	-- Cresta que se curva hacia adelante
	local crestCount = math.max(3, math.floor(width / 3.5))
	for i = 1, crestCount do
		local x = ((i - 0.5) / crestCount - 0.5) * width * 0.92
		add(Vector3.new(width / crestCount * 1.35, height * 0.36, 3.2), CFrame.new(x, height * 0.78, -1.3) * CFrame.Angles(math.rad(-28), 0, 0), C.Light, 0.2, GLASS, i)
		add(Vector3.new(width / crestCount * 1.15, 0.7, 1.7), CFrame.new(x, height * 0.95, -2.5) * CFrame.Angles(math.rad(-40), 0, 0), C.Foam, 0.05, nil, i + 0.5)
	end
	-- Capa de agua que queda detrás
	add(Vector3.new(width * 0.95, 0.7, 10), CFrame.new(0, 0.3, 6), C.Body, 0.35, GLASS)
	add(Vector3.new(width * 0.7, 0.35, 7), CFrame.new(0, 0.55, 5), C.Foam, 0.35)

	-- Espuma y rocío en la cresta
	local crestHolder = Common.host("Crest", CFrame.new(), Vector3.new(width, 0.2, 1.5), model)
	table.insert(pieces, { Part = crestHolder, Offset = CFrame.new(0, height * 0.95, -2.2) })
	local spray = Common.droplets("WaterWave", crestHolder, C, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(40, 40),
		Speed = NumberRange.new(6, 14),
		Lifetime = NumberRange.new(0.4, 0.8),
		Rate = 120,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
	})
	local fog = Common.mist("WaterWave", crestHolder, MIST_COLORS, { Rate = 14, Speed = NumberRange.new(2, 5) })
	return { Model = model, Pieces = pieces, Spray = spray, Fog = fog }
end

local function crashWave(wave, cf, width, height)
	local visual = wave.Visual
	if visual then
		visual.Spray.Enabled = false
		visual.Fog.Enabled = false
		-- La ola cae hacia adelante y se aplana
		Common.animate(0.45, function(t)
			local a = Common.easeOut(t / 0.45)
			local fallCF = cf * CFrame.new(0, 0, -3 * a)
			for _, piece in visual.Pieces do
				if piece.Mesh then
					piece.Mesh.Scale = piece.Scale * Vector3.new(1, math.max(1 - a * 0.85, 0.1), 1 + a * 0.3)
				end
				if piece.Mesh then
					piece.Part.Transparency = math.max(piece.Part.Transparency, a)
				end
			end
			bulkMove(visual.Pieces, fallCF * CFrame.new(0, -height * 0.3 * a, 0))
		end)
		Debris:AddItem(visual.Model, 0.5)
	end
	if wave.Custom then
		wave.Custom:Stop()
	end

	-- Salpicadura a lo ancho
	local model = Common.newModel("WaterWave_Crash")
	Common.outline(model, C.Outline)
	local position = cf.Position
	local holder = Common.newPart("Part", { Size = Vector3.new(width, 0.3, 2), Transparency = 1, CFrame = cf * CFrame.new(0, 0.5, -2) }, model)
	Common.droplets("WaterWave", holder, C, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(45, 45),
		Speed = NumberRange.new(14, 30),
		Lifetime = NumberRange.new(0.5, 1),
		Acceleration = Vector3.new(0, -70, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
	}):Emit(math.floor(width * 6))
	Common.mist("WaterWave", holder, MIST_COLORS, {
		Speed = NumberRange.new(4, 10),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) }),
	}):Emit(18)
	Common.ripple(model, position + cf.LookVector * -2, Vector3.yAxis, 4, width * 1.4, 0.7, C.Light, 0.3)
	local puddle = Common.disc(model, C.Deep, 0.45)
	local puddleCF = Common.discCFrame(position + Vector3.new(0, 0.03, 0) - cf.LookVector * 2, Vector3.yAxis)
	Common.animate(2, function(t)
		local size = width * (0.6 + 0.3 * Common.easeOut(t / 0.4))
		puddle.Size = Vector3.new(0.08, size, size)
		puddle.CFrame = puddleCF
		puddle.Transparency = 0.45 + 0.55 * math.clamp((t - 0.9) / 1.1, 0, 1)
	end)
	Common.shake(position, 1.5, 80)
	Common.spawnCustom("WaterWave", "Impact", cf)
	Debris:AddItem(model, 2.2)
end

Water.WaterWave = {
	Start = function(data)
		if typeof(data.Id) ~= "number" or typeof(data.Origin) ~= "Vector3" or typeof(data.Direction) ~= "Vector3" then
			return
		end
		local width = data.Width or 17
		local height = data.Height or 7.5
		local wave = {
			Data = data,
			Width = width,
			Height = height,
			Start = os.clock(),
			Lag = math.max(0, Workspace:GetServerTimeNow() - data.T),
			Custom = Common.attachCustom("WaterWave", "Body", CFrame.new(data.Origin)),
			LastRipple = 0,
		}
		if not Common.hideDefault("WaterWave") then
			wave.Visual = buildWave(width, height)
		end
		Common.spawnCustom("WaterWave", "Cast", CFrame.new(data.Origin))
		local ignore = { data.Caster }
		local rippleModel = Common.newModel("WaterWave_Trail")
		Common.outline(rippleModel, C.Outline)
		Debris:AddItem(rippleModel, 12)

		waves[data.Id] = wave
		wave.Connection = RunService.RenderStepped:Connect(function()
			local elapsed = Common.stylizedTime(os.clock() - wave.Start + math.min(wave.Lag, 0.1))
			local limit = if wave.EndDistance then wave.EndDistance else data.Distance
			local travelled = math.min(elapsed * data.Speed, limit)
			local horizontal = data.Origin + data.Direction * ((data.StartDistance or 2.5) + travelled)
			local fallbackY = data.Origin.Y
			local hit = Common.castWorld(Vector3.new(horizontal.X, fallbackY + 10, horizontal.Z), Vector3.new(0, -24, 0), ignore)
			local ground = if hit then hit.Position else Vector3.new(horizontal.X, fallbackY - 3, horizontal.Z)
			local cf = CFrame.lookAt(ground, ground + data.Direction) * CFrame.new(0, data.HeightOffset or 0.15, 0)
			wave.CFrame = cf

			-- Sube desde el suelo al empezar
			local rise = Common.easeOut(elapsed / 0.18)
			if wave.Visual then
				for _, piece in wave.Visual.Pieces do
					if piece.Mesh then
						local bob = if piece.Bob then 1 + 0.08 * math.sin(elapsed * 9 + piece.Bob * 1.7) else 1
						piece.Mesh.Scale = piece.Scale * Vector3.new(1, math.max(rise * bob, 0.05), 1)
					end
				end
				bulkMove(wave.Visual.Pieces, cf * CFrame.new(0, -wave.Height * 0.4 * (1 - rise), 0))
			end
			if wave.Custom then
				wave.Custom:Move(cf)
			end

			-- Ondas en el suelo detrás de la ola
			if elapsed - wave.LastRipple > 0.12 then
				wave.LastRipple = elapsed
				Common.ripple(rippleModel, ground - data.Direction * 4, Vector3.yAxis, wave.Width * 0.4, wave.Width * 0.9, 0.6, C.Light, 0.5)
			end

			if travelled >= limit or elapsed > 6 then
				wave.Connection:Disconnect()
				waves[data.Id] = nil
				crashWave(wave, cf, wave.Width, wave.Height)
			end
		end)
	end,
	-- El servidor avisa cuánto avanzó realmente (choque con una pared, el lanzador murió…)
	End = function(data)
		local wave = waves[data.Id]
		if wave and typeof(data.Travelled) == "number" then
			wave.EndDistance = math.max(0, data.Travelled)
		end
	end,
}

---------------------------------------------------------------------
-- WATER WHIP (Water Beam)
---------------------------------------------------------------------

local beams = {}

-- Igual que el servidor: conserva la inclinación del lanzamiento y sigue el giro del personaje
local function followingDirection(root, releaseDirection)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.001 then
		return releaseDirection.Unit
	end
	look = look.Unit
	local pitchY = math.clamp(releaseDirection.Unit.Y, -0.95, 0.95)
	local direction = look * math.sqrt(math.max(0, 1 - pitchY * pitchY)) + Vector3.new(0, pitchY, 0)
	return if direction.Magnitude < 0.001 then look else direction.Unit
end

local function buildStream()
	local anchor = Common.host("WaterWhip", CFrame.new())
	local stream = { Anchor = anchor, Layers = {}, Spirals = {} }
	stream.A = Instance.new("Attachment")
	stream.A.Parent = anchor
	stream.B = Instance.new("Attachment")
	stream.B.Parent = anchor

	-- Chorro: capa exterior translúcida, capa media y núcleo de espuma
	for _, layer in {
		{ W0 = 0.45, W1 = 3.4, Color = C.Body, Alpha = 0.45 },
		{ W0 = 0.32, W1 = 2.4, Color = C.Light, Alpha = 0.22 },
		{ W0 = 0.18, W1 = 0.9, Color = C.Foam, Alpha = 0.5 },
	} do
		local beam = Instance.new("Beam")
		beam.Attachment0 = stream.A
		beam.Attachment1 = stream.B
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Color = ColorSequence.new(layer.Color)
		beam.Transparency = NumberSequence.new(layer.Alpha)
		beam.LightEmission = 0.2
		beam.LightInfluence = 0
		beam.Parent = anchor
		table.insert(stream.Layers, { Beam = beam, W0 = layer.W0, W1 = layer.W1 })
	end
	-- Espirales de agua y espuma que giran alrededor del chorro
	for j = 1, 4 do
		local line = Common.beamLine(anchor, 24, if j % 2 == 0 then C.Foam else C.Light, C.Light, if j % 2 == 0 then 0.35 else 0.27, 0.2, if j % 2 == 0 then 0.19 else 0.34)
		table.insert(stream.Spirals, line)
	end

	stream.MouthHolder = Common.host("Mouth", CFrame.new(), Vector3.one * 0.6)
	stream.MouthSpray = Common.droplets("WaterWhip", stream.MouthHolder, C, {
		EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(25, 25),
		Speed = NumberRange.new(10, 18),
		Rate = 40,
	})
	stream.EndHolder = Common.host("End", CFrame.new(), Vector3.one * 1.5)
	stream.EndDrops = Common.droplets("WaterWhip", stream.EndHolder, C, {
		Speed = NumberRange.new(8, 17),
		Lifetime = NumberRange.new(0.25, 0.5),
		Acceleration = Vector3.new(0, -40, 0),
		Rate = 70,
	})
	stream.EndMist = Common.mist("WaterWhip", stream.EndHolder, MIST_COLORS, {
		Rate = 25,
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(3, 7),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
	})
	return stream
end

local function stopStream(id)
	local beam = beams[id]
	if not beam or beam.Stopping then
		return
	end
	beam.Stopping = true
	local stream = beam.Stream
	if stream then
		stream.MouthSpray.Enabled = false
		stream.EndDrops.Enabled = false
		stream.EndMist.Enabled = false
		Common.animate(0.16, function(t)
			local fade = 1 - t / 0.16
			for _, layer in stream.Layers do
				layer.Beam.Width0 = layer.W0 * fade
				layer.Beam.Width1 = layer.W1 * fade
			end
			for _, line in stream.Spirals do
				Common.setUniformWidth(line, line.Width * fade)
			end
		end)
		Debris:AddItem(stream.Anchor, 0.3)
		Debris:AddItem(stream.MouthHolder, 0.8)
		Debris:AddItem(stream.EndHolder, 0.8)
	end
	if beam.Custom then
		beam.Custom:Stop()
	end
	beam.Connection:Disconnect()
	beams[id] = nil
end

Water.WaterWhip = {
	Start = function(data)
		local caster = data.Caster
		if typeof(data.Id) ~= "number" or typeof(caster) ~= "Instance" or typeof(data.Direction) ~= "Vector3" then
			return
		end
		local head = caster:FindFirstChild("Head")
		local root = caster:FindFirstChild("HumanoidRootPart")
		if not head or not root then
			return
		end
		local range = data.Range or 72
		local activeTime = data.ActiveTime or 1.15
		local growTime = math.max(data.GrowTime or 0.1, 0.01)
		local padding = data.Padding or 0.15
		local lag = math.min(math.max(0, Workspace:GetServerTimeNow() - data.T), 0.3)

		local beam = {
			Stream = if Common.hideDefault("WaterWhip") then nil else buildStream(),
			Custom = Common.attachCustom("WaterWhip", "Body", CFrame.new(head.Position)),
			Start = os.clock() - lag,
			LastRipple = 0,
		}
		local stream = beam.Stream
		local rippleModel = Common.newModel("WaterWhip_Hits")
		Common.outline(rippleModel, C.Outline)
		Debris:AddItem(rippleModel, activeTime + 2)
		Common.spawnCustom("WaterWhip", "Cast", CFrame.new(Common.mouthPosition(head)))
		beams[data.Id] = beam

		beam.Connection = RunService.RenderStepped:Connect(function()
			if not head.Parent or not root.Parent then
				stopStream(data.Id)
				return
			end
			local real = os.clock() - beam.Start
			local t = Common.stylizedTime(real)
			if real >= activeTime then
				stopStream(data.Id)
				return
			end

			local origin = Common.mouthPosition(head)
			local direction = followingDirection(root, data.Direction)
			local hit = Common.castWorld(origin, direction * range, { caster })
			local reach = if hit then math.clamp(hit.Distance - padding, 0, range) else range
			local length = reach * math.clamp(t / growTime, 0, 1)
			local finish = origin + direction * length

			if beam.Custom then
				beam.Custom:Move(Common.lookAlong(origin, direction))
			end
			if stream then
				stream.Anchor.CFrame = Common.lookAlong(origin, direction)
				stream.A.Position = Vector3.zero
				stream.B.Position = Vector3.new(0, 0, -length)
				local pulse = 0.96 + 0.04 * math.sin(t * 23)
				for _, layer in stream.Layers do
					layer.Beam.Width0 = layer.W0 * pulse
					layer.Beam.Width1 = layer.W1 * pulse * math.min(1, length / 6)
				end
				for j, line in ipairs(stream.Spirals) do
					local count = #line.Nodes
					for i, node in line.Nodes do
						local f = (i - 1) / (count - 1)
						local radius = (0.1 + 1.35 * f) * math.min(1, length / 5) * (1 + math.sin(f * 19 - t * 21 + j) * 0.07)
						local theta = f * math.min(length * 0.48, math.pi * 9) - t * 13 + j * math.pi / 2
						node.Position = Vector3.new(math.cos(theta) * radius, math.sin(theta) * radius, -length * f)
					end
					Common.setUniformWidth(line, line.Width)
				end
				stream.MouthHolder.CFrame = Common.lookAlong(origin, direction)
				stream.EndHolder.CFrame = CFrame.new(finish)
				stream.EndDrops.Enabled = length > 1
				stream.EndMist.Enabled = length > 1
			end

			-- Salpicaduras donde el chorro choca con el mundo
			if hit and length >= reach - 0.5 and t - beam.LastRipple > 0.14 then
				beam.LastRipple = t
				Common.ripple(rippleModel, hit.Position, hit.Normal, 1.5, 7, 0.4, C.Light, 0.3)
			end
		end)
	end,
	End = function(data)
		stopStream(data.Id)
	end,
}

---------------------------------------------------------------------
-- WATER PRISON
---------------------------------------------------------------------

local function buildOrb(kind, radius)
	local model = Common.newModel(kind)
	Common.outline(model, C.Outline)
	local orb = { Model = model, Pieces = {}, Radius = radius }
	local function add(scale, offset, color, transparency, material)
		local part, mesh = Common.ellipsoid(model, scale, color, transparency, material)
		table.insert(orb.Pieces, { Part = part, Mesh = mesh, Offset = offset, Scale = scale })
		return part
	end
	orb.Shell = add(Vector3.one * radius * 2, CFrame.new(), C.Body, 0.3, GLASS)
	add(Vector3.one * radius * 1.2, CFrame.new(), C.Deep, 0.1)
	add(Vector3.new(0.9, 0.3, 0.5) * radius, CFrame.new(0, 0.5 * radius, -0.55 * radius) * CFrame.Angles(math.rad(-30), 0, 0), C.Foam, 0.05)
	-- Anillos de espuma que giran (sensación de remolino)
	orb.Anchor = Common.host("Rings", CFrame.new(), Vector3.one * 0.2, model)
	orb.Rings = {}
	for k = 1, 2 do
		table.insert(orb.Rings, { Line = Common.beamLine(orb.Anchor, 21, C.Foam, C.Light, 0.15, 0.3, 0.22), Tilt = k * 1.3 })
	end
	orb.Drops = Common.droplets(kind, orb.Shell, C, {
		EmissionDirection = Enum.NormalId.Back,
		SpreadAngle = Vector2.new(40, 40),
		Speed = NumberRange.new(3, 8),
		Rate = 50,
	})
	return orb
end

local function updateOrb(orb, cf, t)
	local wobble = Vector3.new(1 + 0.06 * math.sin(t * 20), 1 - 0.05 * math.sin(t * 20 + 1), 1 + 0.04 * math.sin(t * 15))
	for _, piece in orb.Pieces do
		piece.Mesh.Scale = piece.Scale * wobble
	end
	bulkMove(orb.Pieces, cf)
	orb.Anchor.CFrame = cf
	for _, ring in orb.Rings do
		local axis = CFrame.Angles(t * 3 + ring.Tilt, t * 4.5, ring.Tilt) * Vector3.yAxis
		Common.placeCircle(ring.Line, axis, orb.Radius * 1.08)
		Common.setUniformWidth(ring.Line, ring.Line.Width)
	end
end

local prisons = {}

local function popPrison(target)
	local prison = prisons[target]
	if not prison then
		return
	end
	prisons[target] = nil
	prison.Connection:Disconnect()
	local position = prison.Position
	if prison.Orb then
		prison.Orb.Drops.Enabled = false
		prison.Bubbles.Enabled = false
		-- La burbuja se infla un poco y revienta
		Common.animate(0.15, function(t)
			local a = t / 0.15
			for _, piece in prison.Orb.Pieces do
				piece.Mesh.Scale = piece.Scale * (1 + 0.25 * a)
				piece.Part.Transparency = math.max(piece.Part.Transparency, a)
			end
			Common.setUniformWidth(prison.Orb.Rings[1].Line, 0)
			Common.setUniformWidth(prison.Orb.Rings[2].Line, 0)
		end)
		Debris:AddItem(prison.Orb.Model, 0.25)
	end
	if prison.Custom then
		prison.Custom:Stop()
	end
	local model = Common.newModel("WaterPrison_Pop")
	Common.outline(model, C.Outline)
	local holder = Common.host("Pop", CFrame.new(position), Vector3.one * 4, model)
	Common.droplets("WaterPrison", holder, C, {
		Speed = NumberRange.new(12, 26),
		Lifetime = NumberRange.new(0.5, 1),
		Acceleration = Vector3.new(0, -70, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
	}):Emit(90)
	Common.mist("WaterPrison", holder, MIST_COLORS):Emit(12)
	local ground = Common.groundBelow(position, { prison.Target.Parent }, 14)
	if ground then
		Common.ripple(model, ground.Position, ground.Normal, 3, 14, 0.6, C.Light, 0.3)
		Common.crown(model, C, ground.Position, ground.Normal, 10, 1.6, 4, 0.6, 0.6)
	end
	Debris:AddItem(model, 2)
end

Water.WaterPrison = {
	Projectile = {
		Create = function(data)
			muzzle("WaterPrison", data.Origin, data.Direction)
			local state = {
				Radius = data.Radius or 2,
				Custom = Common.attachCustom("WaterPrison", "Body", Common.lookAlong(data.Origin, data.Direction)),
			}
			if not Common.hideDefault("WaterPrison") then
				state.Orb = buildOrb("WaterPrison", state.Radius * 0.85)
			end
			return state
		end,
		Update = function(state, position, direction, t)
			local cf = Common.lookAlong(position, direction)
			if state.Custom then
				state.Custom:Move(cf)
			end
			if state.Orb then
				updateOrb(state.Orb, cf, t)
			end
		end,
		End = function(state, position, normal, hit)
			if state.Orb then
				state.Orb.Model:Destroy()
			end
			if state.Custom then
				state.Custom:Stop()
			end
			if hit and typeof(normal) == "Vector3" then
				splash("WaterPrison", position, normal, 1.15)
			else
				airBurst("WaterPrison", position, Vector3.zAxis, state.Radius)
			end
		end,
	},

	-- Burbuja alrededor del objetivo atrapado
	PrisonStart = function(data)
		local target = data.Target
		if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
			return
		end
		popPrison(target)
		local duration = data.Duration or 1.9
		local prison = {
			Target = target,
			Position = target.Position,
			Custom = Common.attachCustom("WaterPrison", "Prison", target.CFrame),
		}
		if not Common.hideDefault("WaterPrison") then
			prison.Orb = buildOrb("WaterPrison_Bubble", 3.5)
			prison.Bubbles = Common.droplets("WaterPrison", prison.Orb.Shell, C, {
				Speed = NumberRange.new(1, 3),
				Acceleration = Vector3.new(0, 6, 0),
				Lifetime = NumberRange.new(0.8, 1.4),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.4) }),
				Transparency = NumberSequence.new(0.3, 1),
				Rate = 18,
			})
			prison.Orb.Drops.Rate = 12
		end
		local start = os.clock()
		prisons[target] = prison
		prison.Connection = RunService.RenderStepped:Connect(function()
			local real = os.clock() - start
			if not target:IsDescendantOf(Workspace) or real >= duration then
				popPrison(target)
				return
			end
			local t = Common.stylizedTime(real)
			prison.Position = target.Position
			local cf = CFrame.new(target.Position)
			if prison.Custom then
				prison.Custom:Move(cf)
			end
			if prison.Orb then
				local grow = Common.easeOut(t / 0.14)
				updateOrb(prison.Orb, cf, t)
				if grow < 1 then
					for _, piece in prison.Orb.Pieces do
						piece.Mesh.Scale *= math.max(grow, 0.05)
					end
				end
			end
		end)
	end,
	PrisonEnd = function(data)
		if typeof(data.Target) == "Instance" then
			popPrison(data.Target)
		end
	end,
}

return Water
