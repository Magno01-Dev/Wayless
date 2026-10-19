--[[
	Throwables.Visuals · ModuleScript en ReplicatedStorage.Throwables (solo cliente)
	Modelos de proyectil, estelas, sonidos, impactos, choques y proyectiles en la mano al cargar.
	Los modelos se buscan en ReplicatedStorage por el nombre de Definitions[x].Asset.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))

local Visuals = {}

local templateCache = {}
local warnedMissing = {}

local function getFolder()
	local folder = Workspace:FindFirstChild(Config.VfxFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.VfxFolderName
		folder.Parent = Workspace
	end
	return folder
end

local function findTemplate(definition)
	local cached = templateCache[definition.Id]
	if cached and cached.Parent then
		return cached
	end
	local name = definition.Asset
	local found = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name, true)
	if not found then
		local wanted = string.lower(name)
		for _, descendant in ReplicatedStorage:GetDescendants() do
			if string.lower(descendant.Name) == wanted and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
				found = descendant
				break
			end
		end
	end
	if not found and not warnedMissing[name] then
		warnedMissing[name] = true
		warn("[Throwables] No encontré el modelo '" .. name .. "' en ReplicatedStorage")
	end
	templateCache[definition.Id] = found
	return found
end

-- Rotación que alinea el modelo con la dirección de vuelo
local function computeCorrection(visual, size)
	if visual.Mode == "Point" then
		local correction = visual.Offset
		if not correction then
			if size.X >= size.Y and size.X >= size.Z then
				correction = CFrame.Angles(0, math.pi / 2, 0)
			elseif size.Y >= size.X and size.Y >= size.Z then
				correction = CFrame.Angles(-math.pi / 2, 0, 0)
			else
				correction = CFrame.identity
			end
		end
		if visual.Flip then
			correction = CFrame.Angles(0, math.pi, 0) * correction
		end
		return correction
	end
	-- Flat: el eje más delgado queda vertical respecto al vuelo (gira como disco)
	if size.X <= size.Y and size.X <= size.Z then
		return CFrame.Angles(0, 0, math.pi / 2)
	elseif size.Z <= size.X and size.Z <= size.Y then
		return CFrame.Angles(-math.pi / 2, 0, 0)
	end
	return CFrame.identity
end

-- Modelos hechos por código (sellos, bombas, bolsa de abrojos) ---------------------------

local PAPER = Color3.fromRGB(238, 224, 188)
local INK = Color3.fromRGB(150, 28, 24)

local function plainPart(name, size, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Kanji en ambas caras de un sello (por defecto 爆, "explosión")
local function inkTag(part, kanji, ink)
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.CanvasSize = Vector2.new(60, 110)
		surface.LightInfluence = 1
		surface.Parent = part
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = kanji or "爆"
		text.TextScaled = true
		text.TextColor3 = ink or INK
		text.Font = Enum.Font.GothamBold
		text.Parent = surface
	end
end

-- Sello de papel. kanji / ink opcionales (sello de supresión 封, rastreador 追…)
function Visuals.buildTag(kanji, ink)
	local model = Instance.new("Model")
	model.Name = "PaperTag"
	local paper = plainPart("Paper", Vector3.new(0.55, 0.04, 1), PAPER, Enum.Material.Fabric)
	paper.Parent = model
	inkTag(paper, kanji, ink)
	model.PrimaryPart = paper
	return model
end

local function buildProcedural(definition)
	local visual = definition.Visual
	local kind = visual.Procedural
	if kind == "Tag" then
		return Visuals.buildTag(visual.Kanji, visual.Ink)
	end
	local model = Instance.new("Model")
	model.Name = definition.Id
	if kind == "Ball" then
		local ball = plainPart("Ball", Vector3.one * 0.7, visual.Color or Color3.fromRGB(80, 80, 80), Enum.Material.Fabric, Enum.PartType.Ball)
		ball.Parent = model
		-- Cilindro: X es el largo del eje; girado para que el eje quede vertical (faja horizontal)
		local band = plainPart("Band", Vector3.new(0.16, 0.72, 0.72), PAPER, Enum.Material.Fabric, Enum.PartType.Cylinder)
		band.CFrame = CFrame.Angles(0, 0, math.pi / 2)
		band.Parent = model
		model.PrimaryPart = ball
	else -- Pouch (abrojos)
		local pouch = plainPart("Pouch", Vector3.new(0.75, 0.65, 0.75), Color3.fromRGB(110, 86, 60), Enum.Material.Fabric, Enum.PartType.Ball)
		pouch.Parent = model
		local knot = plainPart("Knot", Vector3.new(0.25, 0.25, 0.25), Color3.fromRGB(80, 60, 42), Enum.Material.Fabric)
		knot.CFrame = CFrame.new(0, 0.38, 0)
		knot.Parent = model
		model.PrimaryPart = pouch
	end
	return model
end

-- Sello de papel envuelto alrededor del centro de un kunai
local function addTagWrap(model)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local axes = { boxSize.X, boxSize.Y, boxSize.Z }
	local longest = 1
	for i = 2, 3 do
		if axes[i] > axes[longest] then
			longest = i
		end
	end
	local size, stripeSize = {}, {}
	for i = 1, 3 do
		size[i] = if i == longest then 0.45 else axes[i] * 1.2 + 0.08
		stripeSize[i] = if i == longest then 0.08 else size[i] + 0.01
	end
	local wrap = plainPart("TagWrap", Vector3.new(size[1], size[2], size[3]), PAPER, Enum.Material.Fabric)
	wrap.CFrame = boxCFrame
	wrap.Parent = model
	local stripe = plainPart("TagInk", Vector3.new(stripeSize[1], stripeSize[2], stripeSize[3]), INK)
	stripe.CFrame = boxCFrame
	stripe.Parent = model
end

local function cloneModel(definition)
	if definition.Visual.Procedural then
		local model = buildProcedural(definition)
		local boxCFrame, boxSize = model:GetBoundingBox()
		model.WorldPivot = boxCFrame
		return model, computeCorrection(definition.Visual, boxSize)
	end
	local template = findTemplate(definition)
	if not template then
		return nil
	end
	local clone = template:Clone()
	local model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		clone.Parent = model
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	local visual = definition.Visual
	if visual.TargetDiameter then
		local _, size = model:GetBoundingBox()
		local largest = math.max(size.X, size.Y, size.Z)
		if largest > 1e-3 then
			pcall(function()
				model:ScaleTo(model:GetScale() * visual.TargetDiameter / largest)
			end)
		end
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	model.WorldPivot = boxCFrame
	if visual.Decoration == "TagWrap" then
		addTagWrap(model)
	end
	return model, computeCorrection(visual, boxSize)
end

-- Para Effects: el mismo modelo del proyectil (kunai con sello clavado, etc.)
Visuals.cloneModel = cloneModel

function Visuals.getFolder()
	return getFolder()
end

-- Punto de la mano izquierda (de donde sale el hilo)
function Visuals.handAttachment(character, name)
	local hand = character and (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm"))
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name or "ThrowableWireHand"
	attachment.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	attachment.Parent = hand
	return attachment
end

-- Hilo ninja: un Beam fino entre dos attachments
function Visuals.wireBeam(attachment0, attachment1, parent)
	local beam = Instance.new("Beam")
	beam.Name = "NinjaWire"
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Width0 = 0.05
	beam.Width1 = 0.05
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightInfluence = 0.3
	beam.LightEmission = 0.2
	beam.Color = ColorSequence.new(Color3.fromRGB(205, 210, 220))
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = parent
	return beam
end

local function flightFrame(position, velocity)
	if velocity.Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	local direction = velocity.Unit
	local up = if math.abs(direction.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, up)
end

-- Sonidos ----------------------------------------------------------------------

function Visuals.playSound(audio, position, parent)
	if not audio or not audio.Id then
		return nil
	end
	local holder = parent
	if not holder then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = Workspace.Terrain
		holder = attachment
		task.delay(4, function()
			attachment:Destroy()
		end)
	end
	local sound = Instance.new("Sound")
	sound.SoundId = audio.Id
	sound.Volume = audio.Volume or 1
	sound.PlaybackSpeed = audio.Speed or 1
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = 110
	sound.Looped = audio.Looped == true
	sound.Parent = holder
	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
	return sound
end

-- Proyectiles ------------------------------------------------------------------

function Visuals.createProjectile(definition, levelDef, ownerCharacter)
	local model, correction = cloneModel(definition)
	local folder = getFolder()

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.one * 0.1
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Parent = folder

	local trailSettings = levelDef.Trail or definition.Visual.Trail
	local trail = nil
	if trailSettings then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, trailSettings.Width / 2, 0)
		a0.Parent = core
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -trailSettings.Width / 2, 0)
		a1.Parent = core
		trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.Lifetime = trailSettings.Lifetime
		trail.MinLength = 0.05
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Color = ColorSequence.new(trailSettings.Color)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Enabled = false
		trail.Parent = core
	end

	if levelDef.Glow then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 200, 255)
		light.Brightness = 3
		light.Range = 8
		light.Parent = core
	end

	local travel = nil
	if definition.Audio.Travel then
		local audio = table.clone(definition.Audio.Travel)
		audio.Looped = true
		travel = Visuals.playSound(audio, nil, core)
	end

	if model then
		model.Parent = folder
	end

	-- Hilo ninja: de la mano del lanzador al proyectil mientras vuela
	local wireHand = nil
	if definition.Visual.Wire and ownerCharacter then
		wireHand = Visuals.handAttachment(ownerCharacter)
		if wireHand then
			local tip = Instance.new("Attachment")
			tip.Name = "WireTip"
			tip.Parent = core
			Visuals.wireBeam(wireHand, tip, core)
		end
	end

	return {
		Model = model,
		Correction = correction,
		Mode = definition.Visual.Mode,
		Spin = definition.Visual.Spin or 0,
		Core = core,
		Trail = trail,
		Travel = travel,
		WireHand = wireHand,
		Angle = 0,
		Placed = false,
	}
end

local function dropWire(handle)
	if handle.WireHand then
		handle.WireHand:Destroy()
		handle.WireHand = nil
	end
end

function Visuals.place(handle, position, velocity, dt)
	handle.Angle += handle.Spin * dt
	local frame = flightFrame(position, velocity)
	if handle.Model then
		local spin = if handle.Mode == "Flat" then CFrame.Angles(0, handle.Angle, 0) else CFrame.identity
		handle.Model:PivotTo(frame * spin * handle.Correction)
	end
	handle.Core.CFrame = frame
	if handle.Trail and not handle.Placed then
		handle.Trail.Enabled = true
	end
	handle.Placed = true
end

function Visuals.stick(handle, position, direction, depth)
	local embedded = position + direction * (depth or 0.2)
	local frame = flightFrame(embedded, direction)
	if handle.Model then
		local spin = if handle.Mode == "Flat" then CFrame.Angles(0, handle.Angle, 0) else CFrame.identity
		handle.Model:PivotTo(frame * spin * handle.Correction)
	end
	if handle.Trail then
		handle.Trail.Enabled = false
	end
	if handle.Travel then
		handle.Travel:Stop()
	end
	dropWire(handle)
	local model = handle.Model
	task.delay(Config.StuckTime, function()
		if model then
			model:Destroy()
		end
	end)
	task.delay(1, function()
		handle.Core:Destroy()
	end)
	handle.Model = nil
end

function Visuals.destroy(handle)
	if handle.Model then
		handle.Model:Destroy()
		handle.Model = nil
	end
	if handle.Trail then
		handle.Trail.Enabled = false
	end
	if handle.Travel then
		handle.Travel:Stop()
	end
	dropWire(handle)
	local core = handle.Core
	task.delay(0.4, function()
		core:Destroy()
	end)
end

-- Efectos ------------------------------------------------------------------------

local function flashPart(position, color, size, duration)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.one * size * 0.4
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = getFolder()
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		part:Destroy()
	end)
end

-- Estrella de líneas finas estilo anime
local function starBurst(position, color, count, length, duration)
	local camera = Workspace.CurrentCamera
	local facing = if camera then (camera.CFrame.Position - position).Unit else Vector3.zAxis
	local base = CFrame.lookAt(position, position + facing)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local line = Instance.new("Part")
		line.Material = Enum.Material.Neon
		line.Color = color
		line.Size = Vector3.new(0.08, 0.08, 0.1)
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.CanTouch = false
		line.CastShadow = false
		local direction = base:VectorToWorldSpace(Vector3.new(math.cos(angle), math.sin(angle), 0))
		line.CFrame = CFrame.lookAt(position, position + direction)
		line.Parent = getFolder()
		local finalLength = length * (0.7 + math.random() * 0.6)
		local tween = TweenService:Create(line, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.02, 0.02, finalLength),
			CFrame = CFrame.lookAt(position + direction * (finalLength / 2 + 0.3), position + direction * finalLength),
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			line:Destroy()
		end)
	end
end

function Visuals.impact(position)
	flashPart(position, Color3.fromRGB(255, 250, 235), 1.6, 0.12)
	starBurst(position, Color3.fromRGB(255, 245, 220), 6, 2.2, 0.16)
end

function Visuals.clash(position)
	flashPart(position, Color3.fromRGB(255, 235, 170), 3, 0.18)
	starBurst(position, Color3.fromRGB(255, 225, 140), 10, 4, 0.22)
	Visuals.playSound({ Id = Config.ClashSoundId, Volume = 0.9 }, position)
end

-- Proyectiles en la mano mientras se carga ---------------------------------------

local charges = {} -- [character] = estado

local function getHand(character, left)
	if left then
		return character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	end
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function levelAt(definition, elapsed, maxLevel)
	local level = 0
	while definition.Levels[level + 1] and level < maxLevel and elapsed >= definition.Levels[level + 1].HoldTime do
		level += 1
	end
	return level
end

-- Cuántos modelos se ven en cada mano según el arma y la etapa
local function handCounts(definition, levelDef, oneHand)
	local id = definition.Id
	if levelDef.Pattern == "Fan" then
		return levelDef.Count, if oneHand then 0 else levelDef.Count
	elseif id == "Senbon" then
		return levelDef.Count, 0
	elseif levelDef.Pattern == "Kage" then
		return 2, 0
	end
	return 1, 0
end

--[[
	info = { StartedAt (tiempo del servidor), OneHand, MaxLevel }
]]
function Visuals.startCharge(character, definition, info)
	Visuals.stopCharge(character)
	charges[character] = {
		Definition = definition,
		StartedAt = info.StartedAt,
		OneHand = info.OneHand,
		MaxLevel = info.MaxLevel or 99,
		Level = -1,
		Left = {},
		Right = {},
		Light = nil,
		Angle = 0,
	}
end

function Visuals.stopCharge(character)
	local state = charges[character]
	if not state then
		return
	end
	charges[character] = nil
	for _, list in { state.Left, state.Right } do
		for _, entry in list do
			entry.Model:Destroy()
		end
	end
	if state.Light then
		state.Light:Destroy()
	end
end

function Visuals.chargeLevel(character)
	local state = charges[character]
	return if state then math.max(state.Level, 0) else 0
end

local function rebuildHand(state, list, count)
	for _, entry in list do
		entry.Model:Destroy()
	end
	table.clear(list)
	for _ = 1, count do
		local model, correction = cloneModel(state.Definition)
		if model then
			model.Parent = getFolder()
			table.insert(list, { Model = model, Correction = correction })
		end
	end
end

local function placeHand(state, hand, list, dt, mirror)
	if not hand then
		return
	end
	local grip = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.15, 0)
	local count = #list
	for i, entry in list do
		local fan = if count > 1 then ((i - 1) / (count - 1) - 0.5) * math.rad(50) * mirror else 0
		local frame = grip * CFrame.Angles(0, fan, 0)
		if state.Definition.Visual.Mode == "Flat" then
			frame = frame * CFrame.new(0, (i - 1) * 0.12, 0) * CFrame.Angles(0, state.Angle, 0)
		end
		entry.Model:PivotTo(frame * entry.Correction)
	end
end

-- Llamar cada frame (lo hace ThrowableRenderer)
function Visuals.updateCharges(serverNow, dt)
	for character, state in charges do
		if not character.Parent then
			Visuals.stopCharge(character)
			continue
		end
		local elapsed = serverNow - state.StartedAt
		local level = levelAt(state.Definition, elapsed, state.MaxLevel)
		local levelDef = state.Definition.Levels[level]
		if level ~= state.Level then
			state.Level = level
			local left, right = handCounts(state.Definition, levelDef, state.OneHand)
			rebuildHand(state, state.Left, left)
			rebuildHand(state, state.Right, right)
			if levelDef.Glow and not state.Light then
				local hand = getHand(character, true)
				if hand then
					state.Light = Instance.new("PointLight")
					state.Light.Color = Color3.fromRGB(150, 200, 255)
					state.Light.Range = 7
					state.Light.Parent = hand
				end
			end
		end
		-- El fuma gira cada vez más rápido
		local spinSpeed = (state.Definition.Visual.Spin or 0) * (0.3 + math.min(elapsed, 1.5))
		state.Angle += spinSpeed * dt
		if state.Light then
			state.Light.Brightness = 2 + math.sin(elapsed * 12) * 1
		end
		placeHand(state, getHand(character, true), state.Left, dt, 1)
		placeHand(state, getHand(character, false), state.Right, dt, -1)
	end
end

function Visuals.getLocalCharacter()
	local player = Players.LocalPlayer
	return player and player.Character
end

return Visuals
