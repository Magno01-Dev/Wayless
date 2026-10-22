--[[
	Throwables.Effects · ModuleScript en ReplicatedStorage.Throwables (solo cliente)

	Dibuja los efectos que el servidor anuncia cuando cae un lanzable de efecto:
		Explosion    estallido (sello explosivo, mina)
		StickyTag    kunai con sello clavado en el mundo o en alguien, hasta que explota
		Mine         sello-mina pegado a una superficie (oculto para los demás si es la versión cargada)
		Caltrops     abrojos esparcidos en el suelo
		Smoke        nube de humo (oscurece al que está dentro, oculta su placa y anula la asistencia de apuntado)
		Flash        bomba de luz (ciega a quien la estaba mirando)
		Anchor       hilo ninja clavado: el dueño es jalado hacia el ancla
		Bind         hilo ninja atado a alguien
		SealMark     sello de supresión pegado en el pecho de alguien
		SealZone     círculo sellado en el suelo
		Mark         (solo el que marcó) silueta del marcado a través de paredes + distancia
		Marked       (solo el marcado) aviso "te han marcado"
		Poison       nube de veneno (no tapa la vista; tinte verde si estás dentro)

	La lógica de daño y estados la decide el servidor. Aquí solo hay imagen, sonido y,
	para el jugador local, el gancho (el cliente mueve su propio personaje) y la ceguera.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Config = require(script.Parent:WaitForChild("Config"))
local Definitions = require(script.Parent:WaitForChild("Definitions"))
local Targets = require(script.Parent:WaitForChild("Targets"))
local Visuals = require(script.Parent:WaitForChild("Visuals"))

local Effects = {}

local localPlayer = Players.LocalPlayer

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function getFolder()
	local folder = Workspace:FindFirstChild(Config.EffectsFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.EffectsFolderName
		folder.Parent = Workspace
	end
	return folder
end

local function playSound(name, position, parent)
	local audio = Config.Sounds[name]
	if not audio or not audio.Id or audio.Id == "" then
		return nil
	end
	return Visuals.playSound(audio, position, parent)
end

local function newPart(name, size, color, material, shape)
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
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function tweenThenDestroy(instance, duration, goal, style)
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	tween.Completed:Once(function()
		instance:Destroy()
	end)
	return tween
end

-- Orientación con el eje Y sobre la normal de la superficie
local function surfaceFrame(position, normal)
	local up = if normal and normal.Magnitude > 1e-3 then normal.Unit else Vector3.yAxis
	local reference = if math.abs(up.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	local right = reference:Cross(up).Unit
	return CFrame.fromMatrix(position, right, up)
end

local function groundBelow(position, ignore)
	local hit = Targets.castWorld(position + Vector3.yAxis * 3, Vector3.yAxis * -8, ignore)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

local function characterRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

-- Byakugan (clan Hyūga) activo en el jugador local: ve a través del humo y de las minas ocultas
local function localByakugan()
	local character = localPlayer.Character
	return character ~= nil and character:GetAttribute("ByakuganActive") == true
end

-- Temblor de cámara ---------------------------------------------------------------------

local shakePower, shakeUntil, shakeLength = 0, 0, 0.0001

local function shake(position, power, duration)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	if distance > Config.ExplosionShakeRadius then
		return
	end
	local scaled = power * (1 - distance / Config.ExplosionShakeRadius)
	if scaled > shakePower * math.max(shakeUntil - os.clock(), 0) / shakeLength then
		shakePower, shakeUntil, shakeLength = scaled, os.clock() + duration, duration
	end
end

RunService:BindToRenderStep("ThrowablesShake", Enum.RenderPriority.Camera.Value + 1, function()
	local remaining = shakeUntil - os.clock()
	if remaining <= 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local strength = shakePower * (remaining / shakeLength)
	camera.CFrame = camera.CFrame * CFrame.Angles(
		math.rad((math.random() - 0.5) * strength),
		math.rad((math.random() - 0.5) * strength),
		math.rad((math.random() - 0.5) * strength * 0.5)
	)
end)

-- Explosión -------------------------------------------------------------------------------

local function emitBurst(position, props, count)
	local holder = newPart("BurstHolder", Vector3.one * 0.2, Color3.new(), nil)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = getFolder()
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	for key, value in props do
		emitter[key] = value
	end
	emitter.Parent = attachment
	emitter:Emit(count)
	task.delay(4, function()
		holder:Destroy()
	end)
end

local function explosion(data)
	local position, radius = data.Position, data.Radius or 9
	local folder = getFolder()

	-- Bola de fuego
	local core = newPart("ExplosionCore", Vector3.one * radius * 0.35, Color3.fromRGB(255, 200, 110), Enum.Material.Neon, Enum.PartType.Ball)
	core.CFrame = CFrame.new(position)
	core.Parent = folder
	tweenThenDestroy(core, 0.32, { Size = Vector3.one * radius * 1.5, Transparency = 1, Color = Color3.fromRGB(255, 110, 40) })

	-- Onda en el suelo
	local groundPosition, groundNormal = groundBelow(position)
	if groundPosition and (groundPosition - position).Magnitude < radius then
		local ring = newPart("Shockwave", Vector3.new(0.2, radius * 0.6, radius * 0.6), Color3.fromRGB(255, 235, 200), Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.CFrame = surfaceFrame(groundPosition + groundNormal * 0.1, groundNormal) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Transparency = 0.3
		ring.Parent = folder
		tweenThenDestroy(ring, 0.4, { Size = Vector3.new(0.05, radius * 2.6, radius * 2.6), Transparency = 1 })
	end

	-- Luz
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = radius * 3
	light.Brightness = 8
	local lightHolder = newPart("ExplosionLight", Vector3.one * 0.2, Color3.new(), nil)
	lightHolder.Transparency = 1
	lightHolder.CFrame = CFrame.new(position)
	lightHolder.Parent = folder
	light.Parent = lightHolder
	TweenService:Create(light, TweenInfo.new(0.45), { Brightness = 0 }):Play()
	task.delay(0.5, function()
		lightHolder:Destroy()
	end)

	-- Humo y chispas
	emitBurst(position, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Lifetime = NumberRange.new(0.9, 1.6),
		Speed = NumberRange.new(radius * 0.8, radius * 1.6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Rotation = NumberRange.new(-180, 180),
		RotSpeed = NumberRange.new(-60, 60),
		LightInfluence = 0.5,
		Color = ColorSequence.new(Color3.fromRGB(90, 80, 75), Color3.fromRGB(45, 42, 40)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, radius * 0.25),
			NumberSequenceKeypoint.new(1, radius * 0.6),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, 26)
	emitBurst(position, {
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(radius * 3, radius * 5),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 140)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, 30)

	playSound("Explosion", position)
	shake(position, 6, 0.4)
end

-- Sellos clavados (kunai explosivo cargado) ---------------------------------------------

local tags = {} -- [id] = { Model, Correction, AttachTo, Offset, FuseAt, Light, Hiss, OwnerUserId }

local function removeTag(id)
	local tag = tags[id]
	if not tag then
		return
	end
	tags[id] = nil
	if tag.Model then
		tag.Model:Destroy()
	end
	if tag.Hiss then
		tag.Hiss:Destroy()
	end
end

local function stickyTag(data)
	removeTag(data.Id)
	local definition = Definitions[data.Weapon] or Definitions.ExplosiveKunai
	local model, correction = Visuals.cloneModel(definition)
	if not model then
		return
	end
	model.Parent = getFolder()
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 90, 50)
	light.Range = 6
	light.Brightness = 0
	light.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)

	local tag = {
		Model = model,
		Correction = correction,
		AttachTo = data.AttachTo,
		Offset = data.Offset,
		Frame = CFrame.lookAt(data.Position, data.Position + data.Direction),
		FuseAt = data.FuseAt,
		ArmedAt = serverNow(),
		Light = light,
		OwnerUserId = data.OwnerUserId,
	}
	tags[data.Id] = tag
	tag.Hiss = playSound("Fuse", data.Position, light.Parent)
end

local function updateTags()
	local now = serverNow()
	for id, tag in tags do
		local frame = tag.Frame
		if tag.AttachTo then
			local root = characterRoot(tag.AttachTo)
			if not root or not tag.AttachTo.Parent then
				removeTag(id)
				continue
			end
			frame = root.CFrame * tag.Offset
		end
		tag.Model:PivotTo(frame * tag.Correction)
		-- Parpadea cada vez más rápido cerca de la explosión automática
		local left = math.max(tag.FuseAt - now, 0)
		local rate = if left < 1.5 then 14 else 4
		tag.Light.Brightness = 1.5 + math.sin(now * rate) * 1.5
	end
end

function Effects.hasOwnTags()
	for _, tag in tags do
		if tag.OwnerUserId == localPlayer.UserId then
			return true
		end
	end
	return false
end

-- Minas ----------------------------------------------------------------------------------

local mines = {} -- [id] = { Model, Paper, Hidden, OwnerUserId, Position, ArmAt, Triggered }

local function removeMine(id)
	local mine = mines[id]
	if not mine then
		return
	end
	mines[id] = nil
	mine.Model:Destroy()
	if mine.Hiss then
		mine.Hiss:Destroy()
	end
end

local function setMineTransparency(mine, value)
	if mine.Transparency == value then
		return
	end
	mine.Transparency = value
	for _, descendant in mine.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = value
		elseif descendant:IsA("TextLabel") then
			descendant.TextTransparency = value
		end
	end
end

local function mine(data)
	removeMine(data.Id)
	local model = Visuals.buildTag()
	local paper = model.PrimaryPart
	model:PivotTo(surfaceFrame(data.Position + data.Normal * 0.03, data.Normal))
	model.Parent = getFolder()
	local entry = {
		Model = model,
		Paper = paper,
		Hidden = data.Hidden == true,
		OwnerUserId = data.OwnerUserId,
		Position = data.Position,
		ArmAt = data.ArmAt,
		Triggered = false,
		Transparency = 0,
	}
	mines[data.Id] = entry
	playSound("Caltrops", data.Position)
end

local function mineTrigger(data)
	local entry = mines[data.Id]
	if not entry then
		return
	end
	entry.Triggered = true
	setMineTransparency(entry, 0)
	entry.Paper.Material = Enum.Material.Neon
	entry.Paper.Color = Color3.fromRGB(255, 150, 70)
	entry.Hiss = playSound("Fuse", entry.Position, entry.Paper)
	TweenService:Create(entry.Paper, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Color = Color3.fromRGB(255, 240, 200),
	}):Play()
end

local function updateMines()
	local character = localPlayer.Character
	local root = characterRoot(character)
	for _, entry in mines do
		if entry.Triggered then
			continue
		end
		local value = 0
		if entry.Hidden and localByakugan() then
			value = 0.25
		elseif entry.Hidden and entry.OwnerUserId ~= localPlayer.UserId then
			-- Oculta: casi invisible salvo muy de cerca
			local close = root and (root.Position - entry.Position).Magnitude <= 7
			value = if close then 0.55 else 0.93
		elseif entry.Hidden then
			value = 0.45 -- el dueño la ve semitransparente para saber que está oculta
		end
		setMineTransparency(entry, value)
	end
end

-- Abrojos -------------------------------------------------------------------------------

local fields = {} -- [id] = { Model, EndsAt }

local function caltrops(data)
	local model = Instance.new("Model")
	model.Name = "Makibishi"
	local random = Random.new(data.Seed or 1)
	local metal = Color3.fromRGB(58, 58, 62)
	local frame = surfaceFrame(data.Position, data.Normal)
	for _ = 1, data.Count or 16 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(random:NextNumber()) * data.Radius * 0.9
		local guess = frame:PointToWorldSpace(Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
		local ground, normal = groundBelow(guess, { model })
		if not ground then
			continue
		end
		-- Abrojo: tres púas cruzadas
		local base = surfaceFrame(ground + normal * 0.12, normal) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		for spike = 1, 3 do
			local part = newPart("Spike", Vector3.new(0.07, 0.07, 0.45), metal, Enum.Material.Metal)
			part.CFrame = base * CFrame.Angles(math.rad(35), math.rad(spike * 120), 0)
			part.Parent = model
		end
	end
	model.Parent = getFolder()
	fields[data.Id] = { Model = model, EndsAt = serverNow() + data.Duration }
	playSound("Caltrops", data.Position)
end

local function updateFields()
	local now = serverNow()
	for id, field in fields do
		local left = field.EndsAt - now
		if left <= 0 then
			field.Model:Destroy()
			fields[id] = nil
		elseif left < 1 and not field.Fading then
			field.Fading = true
			for _, part in field.Model:GetChildren() do
				TweenService:Create(part, TweenInfo.new(left), { Transparency = 1 }):Play()
			end
		end
	end
end

-- Humo -----------------------------------------------------------------------------------

local smokes = {} -- [id] = { Position, Radius, EndsAt, Holder, Emitter }

local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "ThrowablesOverlay"
overlayGui.IgnoreGuiInset = true
overlayGui.ResetOnSpawn = false
overlayGui.DisplayOrder = 60
overlayGui.Parent = localPlayer:WaitForChild("PlayerGui")

local smokeFrame = Instance.new("Frame")
smokeFrame.Size = UDim2.fromScale(1, 1)
smokeFrame.BackgroundColor3 = Color3.fromRGB(120, 120, 122)
smokeFrame.BackgroundTransparency = 1
smokeFrame.BorderSizePixel = 0
smokeFrame.Parent = overlayGui

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 250)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 2
flashFrame.Parent = overlayGui

local function smoke(data)
	local radius = data.Radius
	local holder = newPart("SmokeVolume", Vector3.one * radius * 0.6, Color3.new(), nil, Enum.PartType.Ball)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(data.Position + Vector3.yAxis * radius * 0.35)
	holder.Parent = getFolder()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.Rate = radius * 4
	emitter.Lifetime = NumberRange.new(2.5, 3.5)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.Drag = 1
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-15, 15)
	emitter.LightInfluence = 0.7
	emitter.Color = ColorSequence.new(Color3.fromRGB(175, 175, 178), Color3.fromRGB(140, 140, 145))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.45),
		NumberSequenceKeypoint.new(1, radius * 0.75),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.08),
		NumberSequenceKeypoint.new(0.8, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	emitter:Emit(math.floor(radius * 3))

	-- La nube se expande rápido desde el punto de impacto
	TweenService:Create(holder, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 1.5,
	}):Play()

	smokes[data.Id] = {
		Position = data.Position + Vector3.yAxis * radius * 0.35,
		Radius = radius,
		EndsAt = serverNow() + data.Duration,
		Holder = holder,
		Emitter = emitter,
	}
	playSound("SmokePop", data.Position)
end

-- Fuerza de ocultación de un punto: 0 = fuera, 1 = en el centro
local function smokeDepth(position)
	if localByakugan() then
		return 0 -- el Byakugan ve a través del humo
	end
	local now = serverNow()
	local best = 0
	for _, cloud in smokes do
		if now > cloud.EndsAt - 0.8 then
			continue -- disipándose: ya no oculta
		end
		local distance = (position - cloud.Position).Magnitude
		local depth = 1 - distance / (cloud.Radius * 0.9)
		if depth > best then
			best = depth
		end
	end
	return math.clamp(best, 0, 1)
end

Targets.isConcealed = function(position)
	return smokeDepth(position) > 0
end

local concealed = {} -- [character] = true (atributo local, lo lee PlayerNameplateController)

local function updateSmokes()
	local now = serverNow()
	for id, cloud in smokes do
		if now >= cloud.EndsAt then
			cloud.Emitter.Enabled = false
			task.delay(3.6, function()
				cloud.Holder:Destroy()
			end)
			smokes[id] = nil
		end
	end

	-- Pantalla gris si la cámara está dentro
	local camera = Workspace.CurrentCamera
	local depth = if camera then smokeDepth(camera.CFrame.Position) else 0
	smokeFrame.BackgroundTransparency = 1 - (1 - Config.SmokeInsideDarkness) * math.clamp(depth * 1.6, 0, 1)

	-- Placas de nombre de quien está dentro del humo
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = characterRoot(character)
		if player == localPlayer or not root then
			continue
		end
		local inside = smokeDepth(root.Position) > 0
		if inside ~= (concealed[character] == true) then
			concealed[character] = if inside then true else nil
			character:SetAttribute("ThrowablesConcealed", inside)
		end
	end
	for character in concealed do
		if not character.Parent then
			concealed[character] = nil
		end
	end
end

-- Bomba de luz ----------------------------------------------------------------------------

local blindUntil = 0
local blur = nil

Targets.isBlinded = function()
	return serverNow() < blindUntil
end

local function blind(duration)
	blindUntil = math.max(blindUntil, serverNow() + duration * 0.8)
	flashFrame.BackgroundTransparency = 0
	TweenService:Create(flashFrame, TweenInfo.new(duration * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, duration * 0.55), {
		BackgroundTransparency = 1,
	}):Play()
	if not blur or not blur.Parent then
		blur = Instance.new("BlurEffect")
		blur.Name = "ThrowablesFlashBlur"
		blur.Parent = Lighting
	end
	blur.Size = 28
	TweenService:Create(blur, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = 0 }):Play()
	playSound("FlashRing", Workspace.CurrentCamera.CFrame.Position)
end

local function flash(data)
	local position, radius = data.Position, data.Radius

	local ball = newPart("FlashCore", Vector3.one * 1.5, Color3.fromRGB(255, 255, 245), Enum.Material.Neon, Enum.PartType.Ball)
	ball.CFrame = CFrame.new(position)
	ball.Parent = getFolder()
	tweenThenDestroy(ball, 0.35, { Size = Vector3.one * 14, Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 20
	light.Color = Color3.fromRGB(255, 255, 240)
	light.Parent = ball
	playSound("FlashBang", position)

	if data.OwnerUserId == localPlayer.UserId then
		return -- quien la lanza sabe que viene
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = Workspace.CurrentCamera
	if not humanoid or humanoid.Health <= 0 or not camera then
		return
	end
	local eye = camera.CFrame.Position
	local toFlash = position - eye
	local distance = toFlash.Magnitude
	if distance > radius then
		return
	end
	if distance > 0.5 and Targets.castWorld(eye, toFlash * 0.98, { character }) then
		return -- hay una pared en medio
	end
	local cone = (data.ConeAngle or 70)
	local angle = if distance > 0.5 then math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(toFlash.Unit), -1, 1))) else 0
	if angle > cone then
		return -- estaba mirando hacia otro lado
	end
	local facing = 1 - 0.6 * (angle / cone) ^ 2
	local near = if distance <= radius * 0.4 then 1 else 1 - 0.5 * (distance - radius * 0.4) / (radius * 0.6)
	blind(data.Duration * facing * near)
end

-- Hilo ninja ------------------------------------------------------------------------------

local function tether(character, targetAttachment, duration, anchorModel)
	local hand = Visuals.handAttachment(character, "ThrowableWireHand")
	if not hand then
		task.delay(duration, function()
			if anchorModel then
				anchorModel:Destroy()
			end
			if targetAttachment.Name == "WireAnchorPoint" then
				targetAttachment:Destroy()
			end
		end)
		return
	end
	local beam = Visuals.wireBeam(hand, targetAttachment, hand)
	task.delay(duration, function()
		local tween = TweenService:Create(beam, TweenInfo.new(0.2), { Width0 = 0, Width1 = 0 })
		tween:Play()
		tween.Completed:Wait()
		hand:Destroy()
		if targetAttachment.Parent and targetAttachment.Name == "WireAnchorPoint" then
			targetAttachment:Destroy()
		end
		if anchorModel then
			anchorModel:Destroy()
		end
	end)
end

local grapple = nil

local function stopGrapple(keepMomentum)
	if not grapple then
		return
	end
	local current = grapple
	grapple = nil
	current.Connection:Disconnect()
	current.Velocity:Destroy()
	current.Attachment:Destroy()
	local root = current.Root
	if keepMomentum and root.Parent then
		local settings = Config.WireGrapple
		root.AssemblyLinearVelocity = current.LastVelocity * settings.KeepMomentum + Vector3.yAxis * settings.ExitPop
	end
	if current.Character.Parent then
		current.Character:SetAttribute("IsGrappling", false)
	end
end

local GRAPPLE_CANCEL = {
	"IsDowned", "IsCarried", "IsExecuting", "IsStunned", "Status_Stunned", "Status_MovementBlocked",
	"TreeJumpActive", "IsTreeJumping",
}

local function startGrapple(anchor, speed, maxTime)
	stopGrapple(false)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = characterRoot(character)
	if not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "WireGrappleAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "WireGrappleVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 1e7
	velocity.VectorVelocity = (anchor - root.Position).Unit * speed
	velocity.Parent = root

	character:SetAttribute("IsGrappling", true)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local startedAt = os.clock()
	local lastCheck, lastPosition = startedAt, root.Position
	grapple = {
		Character = character,
		Root = root,
		Attachment = attachment,
		Velocity = velocity,
		LastVelocity = velocity.VectorVelocity,
	}
	grapple.Connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local toAnchor = anchor - root.Position
		if toAnchor.Magnitude <= Config.WireGrapple.ArriveDistance or now - startedAt >= maxTime
			or humanoid.Health <= 0 or not root.Parent then
			stopGrapple(true)
			return
		end
		for _, name in GRAPPLE_CANCEL do
			if character:GetAttribute(name) == true then
				stopGrapple(false)
				return
			end
		end
		-- Atascado contra algo: se suelta
		if now - lastCheck >= 0.15 then
			if now - startedAt > 0.2 and (root.Position - lastPosition).Magnitude < 0.6 then
				stopGrapple(false)
				return
			end
			lastCheck, lastPosition = now, root.Position
		end
		local pull = toAnchor.Unit * speed
		velocity.VectorVelocity = pull
		grapple.LastVelocity = pull
	end)
end

local function anchorAt(data)
	local owner = Players:GetPlayerByUserId(data.OwnerUserId)
	local character = owner and owner.Character
	if not character then
		return
	end
	-- Kunai clavado en el ancla
	local definition = Definitions.NinjaWire
	local model, correction = Visuals.cloneModel(definition)
	if model then
		model:PivotTo(CFrame.lookAt(data.Position, data.Position + data.Direction) * correction)
		model.Parent = getFolder()
	end
	local point = Instance.new("Attachment")
	point.Name = "WireAnchorPoint"
	point.WorldPosition = data.Position
	point.Parent = Workspace.Terrain
	tether(character, point, data.Duration + 0.1, model)
	playSound("WireZip", data.Position)

	if owner == localPlayer then
		startGrapple(data.Position, data.PullSpeed, data.Duration)
	end
end

local function bind(data)
	local owner = Players:GetPlayerByUserId(data.OwnerUserId)
	local character = owner and owner.Character
	local target = data.Target
	local targetPart = target and (target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso") or characterRoot(target))
	if not character or not targetPart then
		return
	end
	local point = Instance.new("Attachment")
	point.Name = "WireBindPoint"
	point.Parent = targetPart
	tether(character, point, data.Duration)
	task.delay(data.Duration + 0.3, function()
		point:Destroy()
	end)
	playSound("WireZip", targetPart.Position)
end

-- Sello de supresión (v3.1) ----------------------------------------------------------------

local SEAL_INK = Color3.fromRGB(60, 70, 190)
local SEAL_GLOW = Color3.fromRGB(120, 150, 255)

local sealMarks = {} -- [personaje] = { Model, Part, EndsAt }
local sealZones = {} -- [id] = { Model, Tags, EndsAt, Frame, Radius, Angle }

local function removeSealMark(character)
	local entry = sealMarks[character]
	if entry then
		sealMarks[character] = nil
		entry.Model:Destroy()
	end
end

local function sealMark(data)
	local target = data.Target
	local torso = target and (target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso"))
	if not torso then
		return
	end
	removeSealMark(target)
	local model = Visuals.buildTag("封", SEAL_INK)
	model.Parent = getFolder()
	local light = Instance.new("PointLight")
	light.Color = SEAL_GLOW
	light.Range = 6
	light.Brightness = 2
	light.Parent = model.PrimaryPart
	sealMarks[target] = { Model = model, Part = torso, EndsAt = serverNow() + data.Duration }
end

local function sealZone(data)
	local model = Instance.new("Model")
	model.Name = "SealZone"
	local frame = surfaceFrame(data.Position + data.Normal * 0.06, data.Normal)

	local disc = newPart("Disc", Vector3.new(0.05, data.Radius * 2, data.Radius * 2), SEAL_GLOW, Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.CFrame = frame * CFrame.Angles(0, 0, math.pi / 2)
	disc.Transparency = 0.82
	disc.Parent = model
	local ring = newPart("Ring", Vector3.new(0.07, data.Radius * 2 + 0.4, data.Radius * 2 + 0.4), SEAL_INK, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.CFrame = frame * CFrame.new(0, -0.01, 0) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Transparency = 0.45
	ring.Parent = model

	-- Sellos de pie alrededor del borde
	local tags = {}
	for i = 1, 6 do
		local tag = Visuals.buildTag("封", SEAL_INK)
		tag.Parent = model
		table.insert(tags, { Model = tag, Offset = (i - 1) / 6 * math.pi * 2 })
	end
	model.Parent = getFolder()

	-- Aparece desde el centro
	disc.Size = Vector3.new(0.05, 1, 1)
	TweenService:Create(disc, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = Vector3.new(0.05, data.Radius * 2, data.Radius * 2),
	}):Play()

	sealZones[data.Id] = {
		Model = model,
		Tags = tags,
		EndsAt = serverNow() + data.Duration,
		Frame = frame,
		Radius = data.Radius,
		Angle = 0,
	}
	playSound("Caltrops", data.Position)
end

local function updateSeals(dt)
	local now = serverNow()
	for character, entry in sealMarks do
		if now >= entry.EndsAt or not entry.Part.Parent then
			removeSealMark(character)
			continue
		end
		-- Pegado al pecho, de cara hacia afuera
		entry.Model:PivotTo(entry.Part.CFrame * CFrame.new(0, 0.1, -entry.Part.Size.Z / 2 - 0.03) * CFrame.Angles(math.pi / 2, 0, 0))
	end
	for id, zone in sealZones do
		local left = zone.EndsAt - now
		if left <= 0 then
			zone.Model:Destroy()
			sealZones[id] = nil
			continue
		end
		zone.Angle += dt * 0.6
		for _, tag in zone.Tags do
			local angle = zone.Angle + tag.Offset
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * zone.Radius
			-- De pie, mirando hacia el centro, flotando un poco
			local position = zone.Frame:PointToWorldSpace(offset + Vector3.new(0, 1.2 + math.sin(now * 2 + tag.Offset) * 0.15, 0))
			tag.Model:PivotTo(CFrame.lookAt(position, zone.Frame.Position + zone.Frame.UpVector * 1.2) * CFrame.Angles(math.pi / 2, 0, 0))
		end
		if left < 0.6 and not zone.Fading then
			zone.Fading = true
			for _, part in zone.Model:GetDescendants() do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(left), { Transparency = 1 }):Play()
				end
			end
		end
	end
end

-- Sello rastreador (v3.1) ------------------------------------------------------------------

local marks = {} -- [id] = { Highlight, Billboard, Label, Target, EndsAt } (solo el que marcó)
local markedOn = {} -- [id] = EndsAt (el jugador local está marcado)

local markedLabel = Instance.new("TextLabel")
markedLabel.AnchorPoint = Vector2.new(0.5, 0)
markedLabel.Position = UDim2.new(0.5, 0, 0, 64)
markedLabel.Size = UDim2.fromOffset(240, 26)
markedLabel.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
markedLabel.BackgroundTransparency = 0.25
markedLabel.BorderSizePixel = 0
markedLabel.Font = Enum.Font.GothamBold
markedLabel.TextSize = 13
markedLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
markedLabel.Visible = false
markedLabel.Parent = overlayGui
Instance.new("UICorner", markedLabel).CornerRadius = UDim.new(0, 5)

local function removeMark(id)
	local mark = marks[id]
	if mark then
		marks[id] = nil
		mark.Highlight:Destroy()
		mark.Billboard:Destroy()
	end
end

local function mark(data)
	local target = data.Target
	local head = target and target:FindFirstChild("Head")
	if not target or not head then
		return
	end
	removeMark(data.Id)
	local highlight = Instance.new("Highlight")
	highlight.Name = "ThrowablesTrackerMark"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 150, 60)
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = Color3.fromRGB(255, 190, 110)
	highlight.OutlineTransparency = 0
	highlight.Adornee = target
	highlight.Parent = getFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ThrowablesTrackerDistance"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(90, 22)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.Adornee = head
	billboard.Parent = overlayGui.Parent -- PlayerGui: con Adornee se dibuja sobre la cabeza
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(255, 190, 110)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	marks[data.Id] = { Highlight = highlight, Billboard = billboard, Label = label, Target = target, EndsAt = data.EndsAt }
	playSound("WireZip", head.Position)
end

local function updateMarks()
	local now = serverNow()
	local root = characterRoot(localPlayer.Character)
	for id, entry in marks do
		local targetRoot = characterRoot(entry.Target)
		if now >= entry.EndsAt or not targetRoot or not entry.Target.Parent then
			removeMark(id)
			continue
		end
		local distance = if root then math.floor((targetRoot.Position - root.Position).Magnitude) else 0
		entry.Label.Text = string.format("%d m · %ds", distance, math.ceil(entry.EndsAt - now))
	end

	local longest = 0
	for id, endsAt in markedOn do
		if now >= endsAt then
			markedOn[id] = nil
		else
			longest = math.max(longest, endsAt - now)
		end
	end
	markedLabel.Visible = longest > 0
	if longest > 0 then
		markedLabel.Text = string.format("追  TE HAN MARCADO · %ds", math.ceil(longest))
	end
end

-- Bomba de veneno (v3.1) -------------------------------------------------------------------

local poisons = {} -- [id] = { Position, Radius, EndsAt, Holder, Emitter }

local poisonFrame = Instance.new("Frame")
poisonFrame.Size = UDim2.fromScale(1, 1)
poisonFrame.BackgroundColor3 = Color3.fromRGB(110, 160, 60)
poisonFrame.BackgroundTransparency = 1
poisonFrame.BorderSizePixel = 0
poisonFrame.Parent = overlayGui

local function poison(data)
	local radius = data.Radius
	-- Bloque (no Ball, que obliga a tamaño uniforme): la emisión en esfera toma su forma achatada
	local holder = newPart("PoisonVolume", Vector3.new(radius * 1.6, radius * 0.6, radius * 1.6), Color3.new(), nil)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(data.Position + Vector3.yAxis * radius * 0.2)
	holder.Parent = getFolder()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rate = radius * 3
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Speed = NumberRange.new(0.3, 1.2)
	emitter.Drag = 1
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-20, 20)
	emitter.LightInfluence = 0.4
	emitter.LightEmission = 0.15
	emitter.Color = ColorSequence.new(Color3.fromRGB(130, 190, 70), Color3.fromRGB(110, 70, 140))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.3),
		NumberSequenceKeypoint.new(1, radius * 0.55),
	})
	-- Mucho más transparente que el humo: se ve a través
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(0.8, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	emitter:Emit(math.floor(radius * 2))

	poisons[data.Id] = {
		Position = data.Position,
		Radius = radius,
		EndsAt = serverNow() + data.Duration,
		Holder = holder,
		Emitter = emitter,
	}
	playSound("SmokePop", data.Position)
end

local function updatePoisons()
	local now = serverNow()
	local root = characterRoot(localPlayer.Character)
	local inside = false
	for id, cloud in poisons do
		if now >= cloud.EndsAt then
			cloud.Emitter.Enabled = false
			task.delay(3, function()
				cloud.Holder:Destroy()
			end)
			poisons[id] = nil
			continue
		end
		if root then
			local relative = root.Position - cloud.Position
			if Vector3.new(relative.X, relative.Y * 1.6, relative.Z).Magnitude <= cloud.Radius then
				inside = true
			end
		end
	end
	-- Tinte verde que late mientras estás dentro
	poisonFrame.BackgroundTransparency = if inside then 0.82 + math.sin(now * 4) * 0.05 else 1
end

-- Aviso en el suelo (lluvia de kunai) --------------------------------------------------------

local function telegraph(data)
	local frame = surfaceFrame(data.Position + data.Normal * 0.05, data.Normal) * CFrame.Angles(0, 0, math.pi / 2)
	local diameter = data.Radius * 2
	local disc = newPart("TelegraphDisc", Vector3.new(0.04, diameter, diameter), Color3.fromRGB(200, 40, 30), Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.CFrame = frame
	disc.Transparency = 0.85
	disc.Parent = getFolder()
	-- El anillo se cierra hasta el borde justo cuando caen los kunai
	local ring = newPart("TelegraphRing", Vector3.new(0.05, diameter * 1.8, diameter * 1.8), Color3.fromRGB(255, 90, 60), Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.CFrame = frame * CFrame.new(0.01, 0, 0)
	ring.Transparency = 0.6
	ring.Parent = getFolder()
	TweenService:Create(ring, TweenInfo.new(data.Duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.05, diameter, diameter),
		Transparency = 0.3,
	}):Play()
	task.delay(data.Duration + 0.15, function()
		tweenThenDestroy(disc, 0.25, { Transparency = 1 })
		tweenThenDestroy(ring, 0.25, { Transparency = 1 })
	end)
end

-- Entrada ----------------------------------------------------------------------------------

local handlers = {
	Explosion = explosion,
	StickyTag = stickyTag,
	TagRemove = function(data)
		removeTag(data.Id)
	end,
	Mine = mine,
	MineTrigger = mineTrigger,
	MineRemove = function(data)
		removeMine(data.Id)
	end,
	Caltrops = caltrops,
	Smoke = smoke,
	Flash = flash,
	Anchor = anchorAt,
	Bind = bind,
	SealMark = sealMark,
	SealZone = sealZone,
	Mark = mark,
	MarkEnd = function(data)
		removeMark(data.Id)
	end,
	Marked = function(data)
		markedOn[data.Id] = data.EndsAt
	end,
	MarkedEnd = function(data)
		markedOn[data.Id] = nil
	end,
	Poison = poison,
	Telegraph = telegraph,
}

function Effects.handle(kind, data)
	local handler = handlers[kind]
	if handler and typeof(data) == "table" then
		local ok, err = pcall(handler, data)
		if not ok then
			warn("[Throwables.Effects] " .. kind .. ": " .. tostring(err))
		end
	end
end

-- Llamar cada frame (lo hace ThrowableRenderer)
function Effects.step(dt)
	updateTags()
	updateMines()
	updateFields()
	updateSmokes()
	updateSeals(dt or 0)
	updateMarks()
	updatePoisons()
end

-- Al reaparecer, el gancho en curso se cancela
localPlayer.CharacterAdded:Connect(function()
	stopGrapple(false)
end)

return Effects
