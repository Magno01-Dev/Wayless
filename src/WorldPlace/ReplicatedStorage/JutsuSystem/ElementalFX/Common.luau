--!nonstrict
-- ReplicatedStorage > JutsuSystem > ElementalFX > Common   (ModuleScript, solo cliente)
--
-- Utilidades compartidas por los VFX de Agua, Viento y Rayo.
--
-- PERSONALIZACIÓN SIN TOCAR CÓDIGO
-- Creen esta carpeta (opcional):
--
--   ReplicatedStorage > VFX > Jutsus > Custom > <NombreDelJutsu>     (Folder, ej. "WaterBullet")
--       Atributos de texto para cambiar texturas de partículas:
--           Droplet = "rbxassetid://…"     Mist = "rbxassetid://…"
--           Spark   = "rbxassetid://…"     Dust = "rbxassetid://…"
--       Piezas opcionales (Model, MeshPart, Part o Attachment con efectos adentro):
--           Body    se pega al proyectil / efecto principal y lo sigue
--           Cast    aparece donde se lanza
--           Impact  aparece donde choca
--       Dentro de esas piezas:
--           ParticleEmitter con atributo EmitCount (número) → ráfaga única
--           ParticleEmitter sin EmitCount → emite mientras dure la pieza
--           Beams, Trails, luces, meshes → se muestran tal cual
--       Atributo opcional de la pieza: Duration (segundos, por defecto 1).
--       Atributo opcional de la carpeta: HideDefault = true → oculta el efecto
--           por código y deja solo sus piezas (para reemplazarlo por completo).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Common = {}

---------------------------------------------------------------------
-- AJUSTES GLOBALES
---------------------------------------------------------------------

-- 0 = animación fluida. 12 = estilo anime (los VFX avanzan a 12 cuadros por segundo).
Common.AnimeFps = 0

-- Contorno estilo anime (Highlight): blanco en el agua, marrón oscuro en la tierra
Common.WaterOutline = true
Common.EarthOutline = true

Common.Palettes = {
	Water = {
		Deep = Color3.fromRGB(14, 74, 178),
		Body = Color3.fromRGB(38, 140, 228),
		Light = Color3.fromRGB(120, 205, 250),
		Foam = Color3.fromRGB(236, 250, 255),
		Outline = Color3.fromRGB(205, 242, 255),
	},
	Wind = {
		White = Color3.fromRGB(242, 255, 252),
		Mint = Color3.fromRGB(165, 228, 214),
		Teal = Color3.fromRGB(92, 190, 176),
		Dust = Color3.fromRGB(176, 166, 146),
		Gash = Color3.fromRGB(52, 48, 44),
	},
	Lightning = {
		Core = Color3.fromRGB(240, 251, 255),
		Cyan = Color3.fromRGB(80, 200, 255),
		Blue = Color3.fromRGB(65, 110, 255),
		Violet = Color3.fromRGB(150, 135, 255),
		Scorch = Color3.fromRGB(28, 28, 36),
	},
	Earth = {
		Rock = Color3.fromRGB(111, 94, 74),
		Dark = Color3.fromRGB(78, 64, 50),
		Light = Color3.fromRGB(150, 128, 100),
		Dust = Color3.fromRGB(143, 123, 98),
		Crack = Color3.fromRGB(38, 32, 26),
		Outline = Color3.fromRGB(42, 33, 25),
	},
}

local DEFAULT_TEXTURES = {
	Droplet = "rbxasset://textures/particles/sparkles_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Mist = "rbxasset://textures/particles/smoke_main.dds",
	Dust = "rbxasset://textures/particles/smoke_main.dds",
}

Common.Folder = Workspace:FindFirstChild("ClientElementalFX") or Instance.new("Folder")
Common.Folder.Name = "ClientElementalFX"
Common.Folder.Parent = Workspace

---------------------------------------------------------------------
-- PERSONALIZACIÓN
---------------------------------------------------------------------

local function customFolder(kind)
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local jutsus = vfx and vfx:FindFirstChild("Jutsus")
	local custom = jutsus and jutsus:FindFirstChild("Custom")
	return custom and custom:FindFirstChild(kind)
end

-- Textura de partículas: la de la carpeta Custom si existe, si no la de Roblox
function Common.texture(kind, name)
	local folder = customFolder(kind)
	local value = folder and folder:GetAttribute(name)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return DEFAULT_TEXTURES[name] or DEFAULT_TEXTURES.Mist
end

-- true si el equipo pidió ocultar el efecto por código de este jutsu
function Common.hideDefault(kind)
	local folder = customFolder(kind)
	return folder ~= nil and folder:GetAttribute("HideDefault") == true
end

local function pinInstance(instance, cf)
	if instance:IsA("Model") then
		for _, part in instance:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		instance:PivotTo(cf)
	elseif instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CFrame = cf
	end
end

local function startEmitters(instance)
	for _, item in instance:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			local count = item:GetAttribute("EmitCount")
			if typeof(count) == "number" then
				item.Enabled = false
				item:Emit(count)
			else
				item.Enabled = true
			end
		end
	end
end

local function stopEmitters(instance)
	for _, item in instance:GetDescendants() do
		if item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then
			item.Enabled = false
		end
	end
end

-- Pieza puntual (Cast / Impact): aparece, emite y se limpia sola
function Common.spawnCustom(kind, slot, cf)
	local folder = customFolder(kind)
	local template = folder and folder:FindFirstChild(slot)
	if not template then
		return nil
	end
	local clone = template:Clone()
	local duration = template:GetAttribute("Duration")
	duration = if typeof(duration) == "number" then duration else 1
	if clone:IsA("Attachment") then
		local anchor = Common.host(slot, cf)
		clone.Parent = anchor
		startEmitters(anchor)
		task.delay(duration, function()
			stopEmitters(anchor)
		end)
		Debris:AddItem(anchor, duration + 3)
		return anchor
	end
	pinInstance(clone, cf)
	clone.Parent = Common.Folder
	startEmitters(clone)
	task.delay(duration, function()
		if clone.Parent then
			stopEmitters(clone)
		end
	end)
	Debris:AddItem(clone, duration + 3)
	return clone
end

-- Pieza que sigue al efecto (Body). Devuelve un objeto con :Move(cf) y :Stop()
function Common.attachCustom(kind, slot, cf)
	local folder = customFolder(kind)
	local template = folder and folder:FindFirstChild(slot)
	if not template then
		return nil
	end
	local clone = template:Clone()
	local holder = clone
	if clone:IsA("Attachment") then
		holder = Common.host(slot, cf)
		clone.Parent = holder
	else
		pinInstance(clone, cf)
		clone.Parent = Common.Folder
	end
	startEmitters(holder)
	local piece = {}
	function piece:Move(newCf)
		if holder:IsA("Model") then
			holder:PivotTo(newCf)
		elseif holder:IsA("BasePart") then
			holder.CFrame = newCf
		end
	end
	function piece:Stop()
		stopEmitters(holder)
		Debris:AddItem(holder, 2)
	end
	return piece
end

---------------------------------------------------------------------
-- MATEMÁTICA
---------------------------------------------------------------------

function Common.easeOut(x)
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

function Common.smoothstep(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function Common.stylizedTime(t)
	if Common.AnimeFps > 0 then
		return math.floor(t * Common.AnimeFps) / Common.AnimeFps
	end
	return t
end

function Common.planeBasis(n)
	local reference = if math.abs(n.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local u = n:Cross(reference).Unit
	local v = n:Cross(u).Unit
	return u, v
end

function Common.lookAlong(position, direction)
	if direction.Magnitude < 1e-4 then
		return CFrame.new(position)
	end
	direction = direction.Unit
	local up = if math.abs(direction.Y) > 0.97 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, up)
end

-- Disco perpendicular a `normal` (el eje de un Cylinder es X)
function Common.discCFrame(position, normal)
	local u = Common.planeBasis(normal)
	return CFrame.fromMatrix(position, normal, u)
end

-- CFrame cuyo "arriba" (Y) es `normal`
function Common.upCFrame(position, normal)
	local u = Common.planeBasis(normal)
	return CFrame.fromMatrix(position, u, normal)
end

function Common.randomUnit(rng)
	local y = rng:NextNumber(-1, 1)
	local angle = rng:NextNumber(0, math.pi * 2)
	local xz = math.sqrt(1 - y * y)
	return Vector3.new(xz * math.cos(angle), y, xz * math.sin(angle))
end

---------------------------------------------------------------------
-- PARTES
---------------------------------------------------------------------

function Common.newPart(className, props, parent)
	local part = Instance.new(className)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		part[key] = value
	end
	part.Parent = parent or Common.Folder
	return part
end

function Common.host(name, cf, size, parent)
	return Common.newPart("Part", { Name = name, CFrame = cf, Size = size or Vector3.one * 0.2, Transparency = 1 }, parent)
end

function Common.ball(parent, color, transparency, material)
	return Common.newPart("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one,
		Color = color,
		Transparency = transparency,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

-- Esfera estirada: el tamaño se controla con mesh.Scale
function Common.ellipsoid(parent, scale, color, transparency, material)
	local part = Common.newPart("Part", {
		Size = Vector3.one,
		Color = color,
		Transparency = transparency,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = scale
	mesh.Parent = part
	return part, mesh
end

function Common.disc(parent, color, transparency, material)
	return Common.newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1, 1),
		Color = color,
		Transparency = transparency,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

function Common.newModel(name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = Common.Folder
	return model
end

-- Contorno estilo anime para todo un modelo (1 Highlight por efecto).
-- enabled: por defecto Common.WaterOutline
function Common.outline(model, color, enabled)
	if enabled == nil then
		enabled = Common.WaterOutline
	end
	if not enabled then
		return nil
	end
	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillTransparency = 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	return highlight
end

-- Parte invisible orientada con `normal` hacia arriba, para emitir partículas
function Common.emitterHolder(parent, position, normal, size)
	return Common.newPart("Part", {
		Size = size or Vector3.new(1, 0.2, 1),
		Transparency = 1,
		CFrame = Common.upCFrame(position, normal),
	}, parent)
end

---------------------------------------------------------------------
-- PARTÍCULAS
---------------------------------------------------------------------

local function emitter(parent, defaults, props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Rotation = NumberRange.new(0, 360)
	for key, value in defaults do
		e[key] = value
	end
	for key, value in props or {} do
		e[key] = value
	end
	e.Parent = parent
	return e
end

function Common.droplets(kind, parent, palette, props)
	return emitter(parent, {
		Texture = Common.texture(kind, "Droplet"),
		Color = ColorSequence.new(palette.Foam, palette.Light),
		LightEmission = 0.25,
		LightInfluence = 0.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.05, 1),
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(3, 9),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -50, 0),
	}, props)
end

function Common.mist(kind, parent, colors, props)
	return emitter(parent, {
		Texture = Common.texture(kind, "Mist"),
		Color = colors,
		LightEmission = 0.1,
		LightInfluence = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.5),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		RotSpeed = NumberRange.new(-40, 40),
	}, props)
end

function Common.sparks(kind, parent, colors, props)
	return emitter(parent, {
		Texture = Common.texture(kind, "Spark"),
		Color = colors,
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 1),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(15, 35),
		Drag = 5,
		SpreadAngle = Vector2.new(180, 180),
	}, props)
end

function Common.dust(kind, parent, color, props)
	return emitter(parent, {
		Texture = Common.texture(kind, "Dust"),
		Color = ColorSequence.new(color),
		LightEmission = 0,
		LightInfluence = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1.0),
		Speed = NumberRange.new(5, 12),
		Drag = 3,
		SpreadAngle = Vector2.new(80, 80),
		RotSpeed = NumberRange.new(-60, 60),
	}, props)
end

---------------------------------------------------------------------
-- ANIMACIÓN
---------------------------------------------------------------------

-- Llama a step(t) cada frame durante `duration` segundos (t respeta el modo anime)
function Common.animate(duration, step)
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= duration then
			connection:Disconnect()
			local ok, err = pcall(step, duration)
			if not ok then
				warn("[ElementalFX]", err)
			end
			return
		end
		local ok, err = pcall(step, Common.stylizedTime(t))
		if not ok then
			connection:Disconnect()
			warn("[ElementalFX]", err)
		end
	end)
	return connection
end

local shakeUntil, shakePower, shakeLength = 0, 0, 0.3
RunService:BindToRenderStep("ElementalFXShake", Enum.RenderPriority.Camera.Value + 1, function()
	local remaining = shakeUntil - os.clock()
	if remaining <= 0 then
		return
	end
	local k = shakePower * remaining / shakeLength
	local camera = Workspace.CurrentCamera
	camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * k), math.rad((math.random() - 0.5) * k), 0)
end)

-- Temblor de cámara según la distancia al efecto
function Common.shake(position, power, radius, duration)
	radius = radius or 80
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	if distance > radius then
		return
	end
	local strength = power * (1 - distance / radius)
	if os.clock() < shakeUntil and strength < shakePower then
		return
	end
	shakePower = strength
	shakeLength = duration or 0.3
	shakeUntil = os.clock() + shakeLength
end

---------------------------------------------------------------------
-- FORMAS DE AGUA
---------------------------------------------------------------------

-- Onda: disco que se expande y se desvanece
function Common.ripple(parent, position, normal, fromSize, toSize, duration, color, transparency)
	local ring = Common.disc(parent, color, transparency)
	local cf = Common.discCFrame(position + normal * 0.05, normal)
	Common.animate(duration, function(t)
		local size = fromSize + (toSize - fromSize) * Common.easeOut(t / duration)
		ring.Size = Vector3.new(0.12, size, size)
		ring.CFrame = cf
		ring.Transparency = transparency + (1 - transparency) * (t / duration) ^ 1.5
	end)
	return ring
end

-- Corona: columnas finas que suben, se abren hacia afuera y caen
function Common.crown(parent, palette, position, normal, count, radius, height, duration, width)
	width = width or 0.9
	local u, v = Common.planeBasis(normal)
	local spikes = {}
	for k = 1, count do
		local angle = (k / count) * math.pi * 2 + math.random() * 0.35
		local part, mesh = Common.ellipsoid(parent, Vector3.one, if k % 2 == 0 then palette.Body else palette.Light, 0.15, Enum.Material.Glass)
		table.insert(spikes, {
			Part = part,
			Mesh = mesh,
			Out = u * math.cos(angle) + v * math.sin(angle),
			Height = height * (0.65 + math.random() * 0.5),
		})
	end
	Common.animate(duration, function(t)
		local rise = Common.easeOut(t / (duration * 0.25))
		local fall = math.clamp((t - duration * 0.25) / (duration * 0.75), 0, 1)
		for _, spike in spikes do
			local tilt = math.rad(18 + 48 * fall)
			local axis = (normal * math.cos(tilt) + spike.Out * math.sin(tilt)).Unit
			local h = spike.Height * rise * (1 - fall * 0.85)
			local base = position + spike.Out * (radius + radius * 1.6 * fall)
			local w = width * (1 + 0.6 * fall)
			spike.Mesh.Scale = Vector3.new(w, math.max(h, 0.05), w)
			local right = axis:Cross(spike.Out)
			right = if right.Magnitude > 1e-3 then right.Unit else (Common.planeBasis(axis))
			spike.Part.CFrame = CFrame.fromMatrix(base + axis * (h * 0.5), right, axis)
			spike.Part.Transparency = 0.15 + 0.85 * fall ^ 1.4
		end
	end)
end

---------------------------------------------------------------------
-- LÍNEAS (Beams)
---------------------------------------------------------------------

function Common.beamLine(parent, count, color0, color1, transparency, emission, width)
	local line = { Nodes = {}, Beams = {}, Width = width or 0.2, Transparency = transparency }
	for i = 1, count do
		local attachment = Instance.new("Attachment")
		attachment.Parent = parent
		line.Nodes[i] = attachment
	end
	for i = 1, count - 1 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = line.Nodes[i]
		beam.Attachment1 = line.Nodes[i + 1]
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Color = ColorSequence.new(color0, color1)
		beam.Transparency = NumberSequence.new(transparency)
		beam.LightEmission = emission
		beam.LightInfluence = 0
		beam.Width0 = 0
		beam.Width1 = 0
		beam.Parent = parent
		line.Beams[i] = beam
	end
	return line
end

-- Grosor de media luna: fino en las puntas, grueso en el centro
function Common.setCrescentWidth(line, width)
	local segments = #line.Beams
	for i, beam in line.Beams do
		beam.Width0 = width * math.sin((i - 1) / segments * math.pi)
		beam.Width1 = width * math.sin(i / segments * math.pi)
	end
end

-- Grosor que se afina hacia el final
function Common.setTaperWidth(line, width)
	local segments = #line.Beams
	for i, beam in line.Beams do
		beam.Width0 = width * (1 - (i - 1) / segments)
		beam.Width1 = width * (1 - i / segments)
	end
end

function Common.setUniformWidth(line, width0, width1)
	for _, beam in line.Beams do
		beam.Width0 = width0
		beam.Width1 = width1 or width0
	end
end

function Common.setTransparency(line, transparency)
	local sequence = NumberSequence.new(math.clamp(transparency, 0, 1))
	for _, beam in line.Beams do
		beam.Transparency = sequence
	end
end

-- Círculo cerrado en el plano perpendicular a `axis` (espacio local del ancla)
function Common.placeCircle(line, axis, radius, offset)
	local u, v = Common.planeBasis(axis)
	local count = #line.Nodes
	for i, node in line.Nodes do
		local angle = (i - 1) / (count - 1) * math.pi * 2
		node.Position = (offset or Vector3.zero) + (u * math.cos(angle) + v * math.sin(angle)) * radius
	end
end

---------------------------------------------------------------------
-- RAYOS
---------------------------------------------------------------------

-- Rayo: dos Beams por tramo sobre los mismos attachments (núcleo + resplandor)
function Common.newBolt(parent, count, coreWidth, glowWidth, palette, glowColor)
	local bolt = { Nodes = {}, Cores = {}, Glows = {}, CoreWidth = coreWidth, GlowWidth = glowWidth }
	for i = 1, count do
		local attachment = Instance.new("Attachment")
		attachment.Parent = parent
		bolt.Nodes[i] = attachment
	end
	for i = 1, count - 1 do
		for layer = 1, 2 do
			local beam = Instance.new("Beam")
			beam.Attachment0 = bolt.Nodes[i]
			beam.Attachment1 = bolt.Nodes[i + 1]
			beam.FaceCamera = true
			beam.Segments = 1
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Width0 = 0
			beam.Width1 = 0
			if layer == 1 then
				beam.Color = ColorSequence.new(palette.Core)
				table.insert(bolt.Cores, beam)
			else
				beam.Color = ColorSequence.new(glowColor or palette.Cyan, palette.Blue)
				beam.Transparency = NumberSequence.new(0.55)
				table.insert(bolt.Glows, beam)
			end
			beam.Parent = parent
		end
	end
	return bolt
end

function Common.setBoltScale(bolt, scale)
	local last = #bolt.Cores
	for i, beam in bolt.Cores do
		beam.Width0 = bolt.CoreWidth * scale
		beam.Width1 = if i == last then 0 else bolt.CoreWidth * scale
	end
	for i, beam in bolt.Glows do
		beam.Width0 = bolt.GlowWidth * scale
		beam.Width1 = if i == last then 0 else bolt.GlowWidth * scale
	end
end

-- Forma en zigzag entre dos puntos (espacio local del ancla)
function Common.jag(bolt, from, to, jitter, rng)
	local delta = to - from
	local u, v = Common.planeBasis(if delta.Magnitude > 1e-3 then delta.Unit else Vector3.yAxis)
	local count = #bolt.Nodes
	for i, node in bolt.Nodes do
		local f = (i - 1) / (count - 1)
		local envelope = math.sin(f * math.pi)
		local offset = (u * (rng:NextNumber() - 0.5) + v * (rng:NextNumber() - 0.5)) * 2 * jitter * envelope
		node.Position = from + delta * f + offset
	end
end

---------------------------------------------------------------------
-- SONIDO
---------------------------------------------------------------------

-- Sonido 3D en un punto (solo en este cliente)
function Common.playSound(soundId, position, volume, minDistance, maxDistance)
	if typeof(soundId) ~= "string" or soundId == "" then
		return
	end
	local holder = Common.host("Sound", CFrame.new(position))
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.RollOffMinDistance = minDistance or 10
	sound.RollOffMaxDistance = maxDistance or 90
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 6)
end

---------------------------------------------------------------------
-- PERSONAJE Y MUNDO
---------------------------------------------------------------------

local MOUTH_DOWN_OFFSET_SCALE = 0.13
local MOUTH_FORWARD_OFFSET = 0.05

-- Igual que en el servidor (FlameBreath / WaterWhip)
function Common.mouthPosition(head)
	local mouth = head:FindFirstChild("MouthAttachment")
	if mouth and mouth:IsA("Attachment") then
		return mouth.WorldPosition
	end
	for _, name in { "FaceFrontAttachment", "FaceCenterAttachment" } do
		local attachment = head:FindFirstChild(name)
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldPosition
				- head.CFrame.UpVector * (head.Size.Y * MOUTH_DOWN_OFFSET_SCALE)
				+ head.CFrame.LookVector * MOUTH_FORWARD_OFFSET
		end
	end
	return head.CFrame:PointToWorldSpace(Vector3.new(0, -head.Size.Y * MOUTH_DOWN_OFFSET_SCALE, -head.Size.Z * 0.5))
end

function Common.rayParams(ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { Common.Folder }
	for _, item in ignore or {} do
		table.insert(list, item)
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	return params
end

local function isCharacterPart(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Raycast que atraviesa personajes y partes sin colisión (como hacen los jutsus en el servidor)
function Common.castWorld(origin, direction, ignore)
	local params = Common.rayParams(ignore)
	for _ = 1, 8 do
		local hit = Workspace:Raycast(origin, direction, params)
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

function Common.groundBelow(position, ignore, distance)
	return Common.castWorld(position + Vector3.new(0, 3, 0), Vector3.new(0, -(distance or 12) - 3, 0), ignore)
end

return Common
