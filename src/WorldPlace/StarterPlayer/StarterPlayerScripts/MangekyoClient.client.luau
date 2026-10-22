-- StarterPlayer > StarterPlayerScripts > MangekyoClient  (LocalScript)
--
-- Efectos de las técnicas del Mangekyō (Jutsus > Amaterasu, Tsukuyomi, EntonSpear, GokaMekkyaku,
-- YasakaMagatama). ClanClient dibuja el
-- Sharingan, el Mangekyō y el aviso de los ojos ("SharinganWindup"); aquí va lo propio de cada
-- técnica:
--   Amaterasu   AmaterasuWindup: humo negro sobre la víctima y un círculo negro que la sigue y se
--               cierra en la ventana final (el momento del dash para esquivarlo)
--               etiqueta "AmaterasuBurning" (jugadores, NPCs y el tronco): llamas negras con borde rojo
--               oscuro por todo el cuerpo
--               AmaterasuPuddle: charco de fuego negro en el suelo
--   EntonSpear  EntonSpearForm: la lanza crece en la mano (o en la del Susanoo) y se queda ahí,
--               en pose de jabalina, hasta lanzarla; EntonSpearCancel la quita si se cortó
--               EntonSpear: la lanza en vuelo (cada cliente la mueve con Start, Direction, Speed)
--               EntonSpearEnd: se clava (World), arde en el cuerpo (Target), se rompe en la
--               guardia (Blocked) o se apaga al final del vuelo (Expire)
--   Gōka Mekkyaku  GokaInhale: fuego y luz en la boca mientras toma aire (GokaCancel lo apaga)
--               GokaBreathStart: chorro de fuego de la boca (o del pecho del Susanoo), luz y tinte
--               naranja y temblor si estás cerca; GokaCells: cada llama del mar de fuego avanza,
--               crece y se queda ardiendo; GokaBreathEnd: se corta el chorro y el mar se apaga en Linger s
--   Yasaka no Magatama  YasakaForm: chispas que se juntan en la palma del Susanoo, las tres tomoe
--               aparecen entre llamas de chakra, se cierran girando y se juntan con un destello;
--               YasakaThrow: sale girando con estela gruesa y espirales y va en arco hacia el
--               objetivo (YasakaPos corrige, YasakaLost deja de perseguir); YasakaImpact: en un
--               cuerpo, humo oscuro con las tomoe girando alrededor, sello de tres tomoe gigante y
--               explosión de chakra (en la pared, sin el giro; en la guardia se rompe); YasakaCancel:
--               se deshace en la mano. Todo con el color del Susanoo de quien lo lanza.
--               Malla: ReplicatedStorage > Shared > ClanModels > Magatama (atributos HeadToBody,
--               RingRadius, HoleRadius); texturas de VFX Studio (tabla TEX).
--   Kagutsuchi: Black Wall  BlackWallForm: línea quemada en el suelo (Telegraph) y el muro brota del
--               centro a los extremos: fuego negro continuo (tres capas de una cortina de llamas que
--               sube y una corona de lenguas que parpadean), partículas negras de detalle y un humo
--               tenue hasta SmokeHeight; se apaga de los extremos al centro. Solo negro. BlackWallRepel: estallido al devolver a quien lo cruza;
--               BlackWallWindup: llamas negras en quien lo lanza (Susanoo, sin sellos).
--   Tsukuyomi   GenjutsuFX "Start" (Kind "Tsukuyomi"), solo la víctima: el Mangekyō llena la
--               pantalla y la deja dentro del genjutsu (cielo rojo, luna negra, mundo sin color);
--               al soltarse la vista vuelve poco a poco
--               TsukuyomiBind (lo ven todos): Mangekyō en el suelo, aura roja y negra y la
--               pose congelada mientras siga dentro (atributo InGenjutsu)
-- Texturas: ReplicatedStorage > Shared > ClanAssets (FireFlipbook, TsukuyomiMoon, MangekyoIris).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes")
local clanRemote = remotes:WaitForChild("ClanFX")
local ClanAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClanAssets"))
local MangekyoCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MangekyoCatalog"))
local SusanooConfig = require(ReplicatedStorage:WaitForChild("Susanoo"):WaitForChild("SusanooConfig"))

local BLACK = Color3.fromRGB(8, 6, 8)
local EMBER = Color3.fromRGB(125, 12, 14)
local TSUKUYOMI_RED = Color3.fromRGB(150, 0, 6)

local BODY_PARTS = { "Torso", "UpperTorso", "LowerTorso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local folder = Instance.new("Folder")
folder.Name = "MangekyoFX"
folder.Parent = Workspace

local function key(time: number, value: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(time, value)
end

local function rootOf(character: Instance?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function irisFor(kind: any): string
	local iris = ClanAssets.MangekyoIris
	return (iris and typeof(kind) == "string" and iris[kind]) or (iris and iris.Itachi) or ""
end

-- Amaterasu ---------------------------------------------------------------------------------

-- Llama negra: el fuego de los jutsus (flipbook 4×4 a 30 fps, como el Fireball) teñido de negro,
-- con alfa normal (sin luz) para que se vea negra sobre cualquier fondo
local function flameEmitter(parent: Instance, rate: number, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AmaterasuFlame"
	emitter.Texture = ClanAssets.FireFlipbook or ClanAssets.FlameWisp or "rbxasset://textures/particles/fire_main.dds"
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	emitter.FlipbookFramerate = NumberRange.new(30)
	emitter.Color = ColorSequence.new(BLACK)
	emitter.LightEmission = 0
	emitter.LightInfluence = 0
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.5, 0.55) -- lo que dura la animación (16 cuadros a 30 fps)
	emitter.Speed = NumberRange.new(0.5, 1.6)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0, 7, 0)
	emitter.Drag = 1.5
	emitter.Size = NumberSequence.new({ key(0, size * 0.7), key(0.35, size), key(1, size * 0.6) })
	emitter.Rotation = NumberRange.new(-360, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.Transparency = NumberSequence.new({ key(0, 0), key(0.7, 0.55), key(0.86, 0.85), key(1, 1) })
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.ZOffset = 0.4
	emitter.LockedToPart = false
	emitter.Parent = parent
	return emitter
end

-- Borde rojo oscuro por debajo de la llama negra (el brillo justo para que se lea en la oscuridad)
local function emberEmitter(parent: Instance, rate: number, size: number): ParticleEmitter
	local emitter = flameEmitter(parent, rate, size)
	emitter.Name = "AmaterasuEmber"
	emitter.Color = ColorSequence.new(EMBER, BLACK)
	emitter.LightEmission = 0.3
	emitter.ZOffset = 0.3
	return emitter
end

local burns: {[Instance]: {ParticleEmitter}} = {}

local function startBurn(character: Instance)
	if burns[character] then
		return
	end
	local list = {}
	if character:IsA("Model") then
		for _, name in BODY_PARTS do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				local torso = name == "Torso" or name == "UpperTorso"
				table.insert(list, flameEmitter(part, if torso then 30 else 14, if torso then 2.2 else 1.4))
				table.insert(list, emberEmitter(part, if torso then 10 else 5, if torso then 1.8 else 1.1))
			end
		end
	end
	-- Sin cuerpo (el tronco de una sustitución): llamas en sus piezas, según su tamaño
	if #list == 0 then
		local parts = {}
		if character:IsA("BasePart") then
			table.insert(parts, character)
		end
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and #parts < 4 then
				table.insert(parts, part)
			end
		end
		for _, part in parts do
			local size = math.clamp(part.Size.Magnitude * 0.45, 1, 2.6)
			table.insert(list, flameEmitter(part, 26, size))
			table.insert(list, emberEmitter(part, 8, size * 0.8))
		end
	end
	burns[character] = list
end

local function stopBurn(character: Instance)
	local list = burns[character]
	if not list then
		return
	end
	burns[character] = nil
	for _, emitter in list do
		emitter.Enabled = false
	end
	task.delay(1, function()
		for _, emitter in list do
			emitter:Destroy()
		end
	end)
end

CollectionService:GetInstanceAddedSignal("AmaterasuBurning"):Connect(startBurn)
CollectionService:GetInstanceRemovedSignal("AmaterasuBurning"):Connect(stopBurn)
for _, character in CollectionService:GetTagged("AmaterasuBurning") do
	startBurn(character)
end

-- Aviso: humo negro que sale de la víctima y un círculo negro bajo sus pies que la sigue; en la
-- ventana final (DodgeWindow) el círculo se cierra y se oscurece: es el momento del dash
local WINDUP_RING_SIZE = 8
local WINDUP_RING_CLOSED = 4.5
local WINDUP_RING_DROP = 2.95

local function amaterasuWindup(data: {[string]: any})
	local root = rootOf(data.Target)
	if not root then
		return
	end
	local duration = if typeof(data.Duration) == "number" then data.Duration else 0.6
	local window = if typeof(data.DodgeWindow) == "number" then data.DodgeWindow else 0.2
	local smoke = flameEmitter(root, 22, 1.6)
	smoke.Name = "AmaterasuWindup"
	smoke.Speed = NumberRange.new(1, 2.5)
	smoke.Transparency = NumberSequence.new({ key(0, 1), key(0.2, 0.45), key(1, 1) })

	local ring = Instance.new("Part")
	ring.Name = "AmaterasuMark"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 1
	ring.Size = Vector3.new(WINDUP_RING_SIZE, 0.05, WINDUP_RING_SIZE)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, WINDUP_RING_DROP, 0))
	ring.Parent = folder
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = ClanAssets.TsukuyomiMoon or ""
	decal.Color3 = Color3.new(0, 0, 0)
	decal.Transparency = 1
	decal.Parent = ring
	TweenService:Create(decal, TweenInfo.new(0.15), { Transparency = 0.55 }):Play()

	local started = os.clock()
	local closing = false
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= duration or not root.Parent then
			connection:Disconnect()
			TweenService:Create(decal, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			task.delay(0.25, function()
				ring:Destroy()
			end)
			return
		end
		if not closing and elapsed >= duration - window then
			closing = true
			TweenService:Create(ring, TweenInfo.new(window, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(WINDUP_RING_CLOSED, 0.05, WINDUP_RING_CLOSED),
			}):Play()
			TweenService:Create(decal, TweenInfo.new(window * 0.5), { Transparency = 0.05 }):Play()
		end
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, WINDUP_RING_DROP, 0)) * CFrame.Angles(0, elapsed * 3, 0)
	end)

	task.delay(duration, function()
		smoke.Enabled = false
		task.delay(1, function()
			smoke:Destroy()
		end)
	end)
end

-- Charco de fuego negro en el suelo
local function amaterasuPuddle(data: {[string]: any})
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	local radius = if typeof(data.Radius) == "number" then data.Radius else 3.5
	local duration = if typeof(data.Duration) == "number" then data.Duration else 6
	local base = Instance.new("Part")
	base.Name = "AmaterasuPuddle"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false
	base.Transparency = 1
	base.Size = Vector3.new(radius * 2, 0.3, radius * 2)
	base.CFrame = CFrame.new(data.Position + Vector3.new(0, 0.15, 0))
	base.Parent = folder
	local flames = flameEmitter(base, 14 * radius, 1.8)
	flames.EmissionDirection = Enum.NormalId.Top
	local embers = emberEmitter(base, 4 * radius, 1.4)
	embers.EmissionDirection = Enum.NormalId.Top
	-- Mancha oscura en el suelo
	local scorch = Instance.new("Decal")
	scorch.Face = Enum.NormalId.Top
	scorch.Texture = ClanAssets.TsukuyomiMoon or ""
	scorch.Color3 = Color3.new(0, 0, 0)
	scorch.Transparency = 0.35
	scorch.Parent = base
	task.delay(math.max(0, duration - 0.6), function()
		flames.Enabled = false
		embers.Enabled = false
		TweenService:Create(scorch, TweenInfo.new(1), { Transparency = 1 }):Play()
		task.delay(1.1, function()
			base:Destroy()
		end)
	end)
end

-- Enton: Black Spear ------------------------------------------------------------------------
-- La malla está en ReplicatedStorage > Shared > ClanModels > EntonSpear (atributos GripToBody,
-- TipZ, TailZ: de la empuñadura al centro de la malla, a la punta y a la cola, a escala 1). Sin
-- malla se usa un asta de respaldo.

local SPEAR_LENGTH = 7 -- asta de respaldo
local SPEAR_SHELL = Color3.fromRGB(150, 14, 16)

type SpearVisual = {
	Model: Model,
	Body: BasePart, -- malla negra (o asta de respaldo)
	Shell: BasePart?, -- borde de energía roja alrededor (ForceField)
	Aura: BasePart, -- emisores a lo largo de la lanza
	Emitters: {ParticleEmitter},
	Trail: Trail,
	BaseSize: Vector3,
	ShellSize: Vector3,
	GripToBody: CFrame,
	TipZ: number,
	TailZ: number,
	Scale: number,
}

type Spear = {
	Visual: SpearVisual,
	Connection: RBXScriptConnection,
	Direction: Vector3,
	Scale: number,
}

local spears: {[string]: Spear} = {}

local function playSound(soundId: any, position: Vector3, volume: number)
	if typeof(soundId) ~= "string" or soundId == "" then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Parent = Workspace.Terrain
	holder.WorldPosition = position
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 160
	sound.Parent = holder
	sound:Play()
	task.delay(5, function()
		holder:Destroy()
	end)
end

local function fadeEmitters(list: {ParticleEmitter}, after: number)
	for _, emitter in list do
		emitter.Enabled = false
	end
	task.delay(after, function()
		for _, emitter in list do
			emitter:Destroy()
		end
	end)
end

local function plainPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	return part
end

local function spearTemplate(): MeshPart?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local models = shared and shared:FindFirstChild("ClanModels")
	local mesh = models and models:FindFirstChild("EntonSpear")
	return if mesh and mesh:IsA("MeshPart") then mesh else nil
end

local function scaled(cframe: CFrame, s: number): CFrame
	return CFrame.new(cframe.Position * s) * cframe.Rotation
end

-- Lanza: malla negra con un borde de energía roja, llamas negras a lo largo y una estela
local function buildSpearVisual(scale: number): SpearVisual
	local model = Instance.new("Model")
	model.Name = "EntonSpear"
	local template = spearTemplate()
	local body: BasePart
	local shell: BasePart? = nil
	local gripToBody, tipZ, tailZ
	if template then
		local mesh = template:Clone()
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.Material = Enum.Material.SmoothPlastic
		mesh.Color = BLACK
		mesh.Transparency = 0
		body = mesh
		local glow = mesh:Clone()
		glow.Name = "Shell"
		glow.Material = Enum.Material.ForceField
		glow.Color = SPEAR_SHELL
		shell = glow
		local attribute = template:GetAttribute("GripToBody")
		gripToBody = if typeof(attribute) == "CFrame" then attribute else CFrame.identity
		tipZ = template:GetAttribute("TipZ") or -3.9
		tailZ = template:GetAttribute("TailZ") or 3
	else
		local shaft = plainPart("Body", Vector3.new(0.3, 0.3, SPEAR_LENGTH))
		shaft.Material = Enum.Material.SmoothPlastic
		shaft.Color = BLACK
		body = shaft
		gripToBody = CFrame.new(0, 0, -0.5)
		tipZ = -SPEAR_LENGTH / 2 - 0.5
		tailZ = SPEAR_LENGTH / 2 - 0.5
	end
	body.Parent = model
	if shell then
		shell.Parent = model
	end
	local length = (tailZ - tipZ) * scale
	local aura = plainPart("Aura", Vector3.new(0.45 * scale, 0.45 * scale, length))
	aura.Transparency = 1
	aura.Parent = model
	local flames = flameEmitter(aura, 110 * scale, 1.0 * scale)
	flames.Lifetime = NumberRange.new(0.35, 0.55)
	local wisps = flameEmitter(aura, 30 * scale, 1.6 * scale)
	wisps.Name = "AmaterasuWisp"
	wisps.Speed = NumberRange.new(0.5, 2)
	local embers = emberEmitter(aura, 30 * scale, 0.7 * scale)
	local tail0 = Instance.new("Attachment")
	tail0.Position = Vector3.new(0, 0.4 * scale, length / 2)
	tail0.Parent = aura
	local tail1 = Instance.new("Attachment")
	tail1.Position = Vector3.new(0, -0.4 * scale, length / 2)
	tail1.Parent = aura
	local trail = Instance.new("Trail")
	trail.Attachment0 = tail0
	trail.Attachment1 = tail1
	trail.Color = ColorSequence.new(BLACK)
	trail.Transparency = NumberSequence.new({ key(0, 0.15), key(0.6, 0.6), key(1, 1) })
	trail.Lifetime = 0.3
	trail.LightEmission = 0
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = aura
	model.PrimaryPart = body
	return {
		Model = model,
		Body = body,
		Shell = shell,
		Aura = aura,
		Emitters = { flames, wisps, embers },
		Trail = trail,
		BaseSize = body.Size,
		ShellSize = body.Size * 1.08,
		GripToBody = gripToBody,
		TipZ = tipZ,
		TailZ = tailZ,
		Scale = scale,
	}
end

-- grip: empuñadura con -Z hacia la punta; grow: 0..1 mientras se forma
local function placeSpear(visual: SpearVisual, grip: CFrame, grow: number)
	local s = visual.Scale * grow
	visual.Body.Size = visual.BaseSize * s
	visual.Body.CFrame = grip * scaled(visual.GripToBody, s)
	local shell = visual.Shell
	if shell then
		shell.Size = visual.ShellSize * s
		shell.CFrame = visual.Body.CFrame
	end
	-- las llamas cubren lo que ya mide la lanza
	visual.Aura.Size = Vector3.new(0.45, 0.45, visual.TailZ - visual.TipZ) * s
	visual.Aura.CFrame = grip * CFrame.new(0, 0, (visual.TipZ + visual.TailZ) / 2 * s)
end

local function hideSpear(visual: SpearVisual)
	visual.Trail.Enabled = false
	visual.Body.Transparency = 1
	if visual.Shell then
		visual.Shell.Transparency = 1
	end
	fadeEmitters(visual.Emitters, 1)
	task.delay(1, function()
		visual.Model:Destroy()
	end)
end

-- Dónde sostiene la lanza: la mano del Susanoo o el final del brazo derecho
local function holdingPart(character: Instance, susanoo: boolean): (BasePart?, CFrame)
	if susanoo then
		local visuals = Workspace:FindFirstChild("SusanooVisuals")
		local model = visuals and visuals:FindFirstChild("Susanoo_" .. character.Name)
		local hand = model and model:FindFirstChild("Hand")
		if hand and hand:IsA("BasePart") then
			return hand, CFrame.new(0, -0.5, 0)
		end
	end
	local hand = character:FindFirstChild("RightHand")
	if hand and hand:IsA("BasePart") then
		return hand, CFrame.identity
	end
	local arm = character:FindFirstChild("Right Arm")
	if arm and arm:IsA("BasePart") then
		return arm, CFrame.new(0, -1, 0)
	end
	return nil, CFrame.identity
end

type Held = { Visual: SpearVisual, Gather: BasePart, Connection: RBXScriptConnection }
local held: {[Instance]: Held} = {}

local function dropHeld(character: Instance)
	local entry = held[character]
	if not entry then
		return
	end
	held[character] = nil
	entry.Connection:Disconnect()
	hideSpear(entry.Visual)
	for _, emitter in entry.Gather:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = false
		end
	end
	task.delay(0.6, function()
		entry.Gather:Destroy()
	end)
end

-- Las llamas negras convergen en la mano y la lanza crece poco a poco (FormTime); al estar
-- lista da un destello y se queda sostenida (punta hacia donde mira) hasta que sale
local function spearForm(data: {[string]: any})
	local character = data.Character
	if typeof(character) ~= "Instance" then
		return
	end
	dropHeld(character)
	local susanoo = data.Susanoo == true
	local holder, offset = holdingPart(character, susanoo)
	local root = rootOf(character)
	if not holder or not root then
		return
	end
	local scale = if susanoo then 2.2 else 1
	local formTime = if typeof(data.FormTime) == "number" then data.FormTime else 0.45
	local visual = buildSpearVisual(scale)
	visual.Model.Parent = folder

	-- Llamas que vienen de alrededor hacia la mano
	local gather = plainPart("EntonGather", Vector3.one * 3.4 * scale)
	gather.Transparency = 1
	gather.Parent = folder
	local inward = flameEmitter(gather, 80 * scale, 0.9 * scale)
	inward.Shape = Enum.ParticleEmitterShape.Sphere
	inward.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	inward.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	inward.Speed = NumberRange.new(5.5 * scale, 7 * scale)
	inward.Acceleration = Vector3.zero
	inward.Drag = 0
	inward.Lifetime = NumberRange.new(0.24, 0.3)
	local inwardEmbers = emberEmitter(gather, 24 * scale, 0.45 * scale)
	inwardEmbers.Shape = Enum.ParticleEmitterShape.Sphere
	inwardEmbers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	inwardEmbers.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	inwardEmbers.Speed = NumberRange.new(6 * scale, 8 * scale)
	inwardEmbers.Acceleration = Vector3.zero
	inwardEmbers.Lifetime = NumberRange.new(0.22, 0.28)
	inwardEmbers.LightEmission = 0.6

	local started = os.clock()
	local ready = false
	local connection = RunService.RenderStepped:Connect(function()
		if not holder.Parent or not root.Parent then
			dropHeld(character)
			return
		end
		local grown = math.clamp((os.clock() - started) / formTime, 0, 1)
		local eased = 1 - (1 - grown) ^ 2.2
		local grip = (holder.CFrame * offset).Position
		local look = root.CFrame.LookVector
		local direction = (Vector3.new(look.X, 0, look.Z).Unit + Vector3.yAxis * 0.12).Unit
		placeSpear(visual, CFrame.lookAt(grip, grip + direction), 0.12 + 0.88 * eased)
		visual.Body.Transparency = 0.7 * (1 - eased)
		if visual.Shell then
			visual.Shell.Transparency = 1 - eased
		end
		gather.CFrame = CFrame.new(grip)
		inward.Rate = 80 * scale * (1 - grown)
		inwardEmbers.Rate = 24 * scale * (1 - grown)
		if grown >= 1 and not ready then
			ready = true
			-- Lista: destello de llamas y brasas
			for _, emitter in visual.Emitters do
				emitter:Emit(14)
			end
		end
	end)
	local entry = { Visual = visual, Gather = gather, Connection = connection }
	held[character] = entry
	task.delay(if typeof(data.Duration) == "number" then data.Duration else 2.5, function()
		if held[character] == entry then
			dropHeld(character)
		end
	end)
end

local endSpear: (string, Vector3?, string?) -> ()

local function gripForTip(visual: SpearVisual, tip: Vector3, direction: Vector3, roll: number): CFrame
	local grip = tip + direction * (visual.TipZ * visual.Scale)
	return CFrame.lookAt(grip, grip + direction) * CFrame.Angles(0, 0, roll)
end

local function spearFlight(data: {[string]: any})
	if typeof(data.Id) ~= "string" or typeof(data.Start) ~= "Vector3" or typeof(data.Direction) ~= "Vector3" then
		return
	end
	-- La lanza ya salió: fuera la de la mano
	local character = data.Character
	if typeof(character) == "Instance" then
		dropHeld(character)
	end
	local scale = if typeof(data.Scale) == "number" then data.Scale else 1
	local speed = if typeof(data.Speed) == "number" then data.Speed else 200
	local range = if typeof(data.Range) == "number" then data.Range else 130
	local direction = data.Direction.Unit
	local visual = buildSpearVisual(scale)
	visual.Trail.Enabled = true
	local start = data.Start
	local started = os.clock()
	placeSpear(visual, gripForTip(visual, start, direction, 0), 1)
	visual.Model.Parent = folder
	spears[data.Id] = {
		Visual = visual,
		Connection = RunService.RenderStepped:Connect(function()
			local elapsed = os.clock() - started
			local tip = start + direction * math.min(elapsed * speed, range)
			placeSpear(visual, gripForTip(visual, tip, direction, elapsed * 9), 1)
		end),
		Direction = direction,
		Scale = scale,
	}
	playSound(ClanAssets.Sounds and ClanAssets.Sounds.EntonSpearThrow, start, 0.9)
	-- Respaldo por si no llega el final
	task.delay(range / speed + 1.5, function()
		endSpear(data.Id, nil, "Expire")
	end)
end

-- Impacto: llamas negras que estallan, brasas y una onda negra (o chispas si se bloqueó)
local function spearBurst(position: Vector3, kind: string, scale: number, direction: Vector3)
	local holder = plainPart("EntonSpearBurst", Vector3.one * scale)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = folder
	local flames = flameEmitter(holder, 0, 1.8 * scale)
	flames.Speed = NumberRange.new(6 * scale, 14 * scale)
	flames.SpreadAngle = Vector2.new(180, 180)
	flames.Drag = 4
	local embers = emberEmitter(holder, 0, 0.6 * scale)
	embers.Speed = NumberRange.new(14 * scale, 30 * scale)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.LightEmission = 0.7
	if kind == "Blocked" then
		flames:Emit(10)
		embers:Emit(36)
	else
		flames:Emit(38)
		embers:Emit(24)
		local up = if math.abs(direction.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
		local ring = plainPart("EntonSpearWave", Vector3.new(0.2, 1, 1) * scale)
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.SmoothPlastic
		ring.Color = BLACK
		ring.Transparency = 0.25
		ring.CFrame = CFrame.fromMatrix(position, direction, (up - direction * up:Dot(direction)).Unit)
		ring.Parent = folder
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(ring, info, { Size = Vector3.new(0.2, 9, 9) * scale, Transparency = 1 }):Play()
		task.delay(0.4, function()
			ring:Destroy()
		end)
	end
	task.delay(1.6, function()
		holder:Destroy()
	end)
end

function endSpear(id: string, position: Vector3?, kind: string?)
	local spear = spears[id]
	local scale = if spear then spear.Scale else 1
	local direction = if spear then spear.Direction else Vector3.new(0, 0, -1)
	if spear then
		spears[id] = nil
		spear.Connection:Disconnect()
		local visual = spear.Visual
		if kind == "World" and position then
			-- Se clava: la punta dentro de la superficie y arde un rato
			visual.Trail.Enabled = false
			placeSpear(visual, gripForTip(visual, position + direction * 0.5 * scale, direction, 0), 1)
			task.delay(2.2, function()
				fadeEmitters(visual.Emitters, 1)
				TweenService:Create(visual.Body, TweenInfo.new(0.5), { Transparency = 1 }):Play()
				if visual.Shell then
					TweenService:Create(visual.Shell, TweenInfo.new(0.5), { Transparency = 1 }):Play()
				end
				task.delay(1, function()
					visual.Model:Destroy()
				end)
			end)
		else
			hideSpear(visual)
		end
	end
	if position and kind ~= nil and kind ~= "Expire" and kind ~= "Consumed" then
		spearBurst(position, kind, scale, direction)
		playSound(ClanAssets.Sounds and ClanAssets.Sounds.EntonSpearImpact, position, 1.1)
	end
end

-- Katon: Gōka Mekkyaku ---------------------------------------------------------------------

local FIRE_HOT = Color3.fromRGB(255, 214, 120)
local FIRE_MID = Color3.fromRGB(255, 120, 30)
local FIRE_DEEP = Color3.fromRGB(190, 40, 12)

-- Fuego normal: la misma textura de los jutsus, en naranja y con luz
local function fireEmitter(parent: Instance, rate: number, size: number): ParticleEmitter
	local emitter = flameEmitter(parent, rate, size)
	emitter.Name = "GokaFire"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, FIRE_HOT),
		ColorSequenceKeypoint.new(0.45, FIRE_MID),
		ColorSequenceKeypoint.new(1, FIRE_DEEP),
	})
	emitter.LightEmission = 0.85
	emitter.LightInfluence = 0
	return emitter
end

local function smokeEmitter(parent: Instance, rate: number, size: number): ParticleEmitter
	local emitter = flameEmitter(parent, rate, size)
	emitter.Name = "GokaSmoke"
	emitter.Color = ColorSequence.new(Color3.fromRGB(45, 38, 36))
	emitter.Transparency = NumberSequence.new({ key(0, 1), key(0.25, 0.55), key(1, 1) })
	emitter.Lifetime = NumberRange.new(0.9, 1.3)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.ZOffset = -0.5
	return emitter
end

local inhaling: {[Instance]: {Instance}} = {}

local function gokaStopInhale(character: Instance)
	local list = inhaling[character]
	if not list then
		return
	end
	inhaling[character] = nil
	for _, item in list do
		if item:IsA("ParticleEmitter") then
			item.Enabled = false
		elseif item:IsA("PointLight") then
			TweenService:Create(item, TweenInfo.new(0.2), { Brightness = 0 }):Play()
		end
	end
	task.delay(1, function()
		for _, item in list do
			item:Destroy()
		end
	end)
end

local function gokaInhale(data: {[string]: any})
	local character = data.Character
	if typeof(character) ~= "Instance" then
		return
	end
	gokaStopInhale(character)
	local holder: BasePart? = nil
	local size = 1
	if data.Susanoo == true then
		local visuals = Workspace:FindFirstChild("SusanooVisuals")
		local model = visuals and visuals:FindFirstChild("Susanoo_" .. character.Name)
		local ribs = model and model:FindFirstChild("Ribcage")
		if ribs and ribs:IsA("BasePart") then
			holder, size = ribs, 2.5
		end
	end
	if not holder then
		local head = character:FindFirstChild("Head")
		holder = if head and head:IsA("BasePart") then head else nil
	end
	if not holder then
		return
	end
	local fire = fireEmitter(holder, 30 * size, 0.9 * size)
	fire.LockedToPart = true
	fire.Speed = NumberRange.new(0.2, 0.8)
	local light = Instance.new("PointLight")
	light.Color = FIRE_MID
	light.Range = 10 * size
	light.Brightness = 0
	light.Parent = holder
	local duration = if typeof(data.Duration) == "number" then data.Duration else 0.4
	TweenService:Create(light, TweenInfo.new(duration), { Brightness = 3 }):Play()
	local list = { fire, light }
	inhaling[character] = list
	task.delay(duration + 0.6, function()
		if inhaling[character] == list then
			gokaStopInhale(character)
		end
	end)
end

type Breath = {
	Character: Instance,
	Stream: BasePart,
	Emitters: {ParticleEmitter},
	Light: PointLight,
	Connection: RBXScriptConnection,
	Cells: {BasePart},
	Tint: ColorCorrectionEffect?,
}
local breaths: {[string]: Breath} = {}

-- Temblor corto de cámara (solo si estás cerca)
local function shakeCamera(duration: number, strength: number)
	local name = "GokaShake"
	local started = os.clock()
	pcall(function()
		RunService:UnbindFromRenderStep(name)
	end)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local elapsed = os.clock() - started
		local camera = Workspace.CurrentCamera
		if elapsed >= duration or not camera then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local fade = 1 - elapsed / duration
		local s = strength * fade
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * s), math.rad((math.random() - 0.5) * s), 0)
	end)
end

local function mouthOf(character: Instance, susanoo: boolean): (BasePart?, CFrame, number)
	if susanoo then
		local visuals = Workspace:FindFirstChild("SusanooVisuals")
		local model = visuals and visuals:FindFirstChild("Susanoo_" .. character.Name)
		local ribs = model and model:FindFirstChild("Ribcage")
		if ribs and ribs:IsA("BasePart") then
			return ribs, CFrame.new(0, 1.2, -1.5), 2.2
		end
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head, CFrame.new(0, -0.15, -0.6), 1
	end
	return nil, CFrame.identity, 1
end

local function gokaBreathStart(data: {[string]: any})
	local character = data.Character
	if typeof(data.Id) ~= "string" or typeof(character) ~= "Instance" then
		return
	end
	gokaStopInhale(character)
	local susanoo = data.Susanoo == true
	local holder, offset, scale = mouthOf(character, susanoo)
	local root = rootOf(character)
	if not holder or not root then
		return
	end
	-- El chorro: sale de la boca hacia delante y crece mientras vuela
	local stream = plainPart("GokaStream", Vector3.new(1, 1, 1) * scale)
	stream.Transparency = 1
	stream.Parent = folder
	local jet = fireEmitter(stream, 260, 1)
	jet.EmissionDirection = Enum.NormalId.Front
	jet.Speed = NumberRange.new(34, 44)
	jet.SpreadAngle = Vector2.new(14, 14)
	jet.Acceleration = Vector3.new(0, 3, 0)
	jet.Drag = 1.2
	jet.Lifetime = NumberRange.new(0.55, 0.75)
	jet.Size = NumberSequence.new({ key(0, 1.4 * scale), key(0.35, 5 * scale), key(1, 11 * scale) })
	jet.Transparency = NumberSequence.new({ key(0, 0.1), key(0.7, 0.35), key(1, 1) })
	jet.LightEmission = 1
	local glow = fireEmitter(stream, 90, 1)
	glow.Name = "GokaJetCore"
	glow.EmissionDirection = Enum.NormalId.Front
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), FIRE_HOT)
	glow.Speed = NumberRange.new(28, 36)
	glow.SpreadAngle = Vector2.new(8, 8)
	glow.Lifetime = NumberRange.new(0.3, 0.45)
	glow.Size = NumberSequence.new({ key(0, 1 * scale), key(1, 6 * scale) })
	glow.LightEmission = 1
	local light = Instance.new("PointLight")
	light.Color = FIRE_MID
	light.Range = 45
	light.Brightness = 0
	light.Parent = stream
	TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 6 }):Play()
	playSound(ClanAssets.Sounds and ClanAssets.Sounds.GokaMekkyaku, (holder.CFrame * offset).Position, 1.4)

	-- Cerca: el mundo se tiñe de naranja y tiembla
	local tint: ColorCorrectionEffect? = nil
	local me = localPlayer.Character
	local myRoot = me and rootOf(me)
	local near = myRoot and (myRoot.Position - root.Position).Magnitude or math.huge
	if near < 110 then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "GokaTint"
		effect.Parent = Lighting
		local strength = math.clamp(1 - near / 110, 0.25, 1)
		TweenService:Create(effect, TweenInfo.new(0.4), {
			TintColor = Color3.fromRGB(255, 225, 190):Lerp(Color3.new(1, 1, 1), 1 - strength),
			Brightness = 0.06 * strength,
			Contrast = 0.1 * strength,
		}):Play()
		tint = effect
	end
	if near < 45 then
		shakeCamera(if typeof(data.Duration) == "number" then data.Duration else 2, 0.6)
	end

	local connection = RunService.RenderStepped:Connect(function()
		if not holder.Parent or not root.Parent then
			return
		end
		local mouth = (holder.CFrame * offset).Position
		local look = root.CFrame.LookVector
		local direction = (Vector3.new(look.X, 0, look.Z).Unit + Vector3.yAxis * -0.12).Unit
		stream.CFrame = CFrame.lookAt(mouth, mouth + direction)
	end)
	breaths[data.Id] = {
		Character = character,
		Stream = stream,
		Emitters = { jet, glow },
		Light = light,
		Connection = connection,
		Cells = {},
		Tint = tint,
	}
	-- Respaldo por si no llega el final
	task.delay((if typeof(data.Duration) == "number" then data.Duration else 2) + 6, function()
		local breath = breaths[data.Id]
		if breath then
			breaths[data.Id] = nil
			breath.Connection:Disconnect()
			breath.Stream:Destroy()
			for _, cell in breath.Cells do
				cell:Destroy()
			end
			if breath.Tint then
				breath.Tint:Destroy()
			end
		end
	end)
end

-- Cada llama del mar de fuego: avanza, crece y se queda ardiendo donde para
local function gokaCells(data: {[string]: any})
	local breath = if typeof(data.Id) == "string" then breaths[data.Id] else nil
	if not breath or typeof(data.Cells) ~= "table" then
		return
	end
	local speed = if typeof(data.Speed) == "number" then data.Speed else 38
	local startRadius = if typeof(data.StartRadius) == "number" then data.StartRadius else 3
	local endRadius = if typeof(data.EndRadius) == "number" then data.EndRadius else 9
	local reach = if typeof(data.Reach) == "number" then data.Reach else 60
	for index, cell in data.Cells do
		if typeof(cell) ~= "table" or typeof(cell.Origin) ~= "Vector3" or typeof(cell.Direction) ~= "Vector3" then
			continue
		end
		local distance = if typeof(cell.Distance) == "number" then cell.Distance else reach
		local blob = plainPart("GokaCell", Vector3.new(startRadius * 2, 3, startRadius * 2))
		blob.Transparency = 1
		blob.CFrame = CFrame.new(cell.Origin + Vector3.yAxis * 2)
		blob.Parent = folder
		local fire = fireEmitter(blob, 26, 1)
		fire.Lifetime = NumberRange.new(0.6, 0.9)
		fire.Speed = NumberRange.new(2, 6)
		fire.Acceleration = Vector3.new(0, 12, 0)
		fire.SpreadAngle = Vector2.new(35, 35)
		fire.LightEmission = 1
		local core = fireEmitter(blob, 10, 1)
		core.Name = "GokaCellCore"
		core.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), FIRE_MID)
		core.LightEmission = 1
		core.Lifetime = NumberRange.new(0.4, 0.6)
		local smoke: ParticleEmitter? = if index == 1 then smokeEmitter(blob, 4, 10) else nil
		if smoke then
			smoke.Lifetime = NumberRange.new(1.6, 2.4)
			smoke.Speed = NumberRange.new(6, 10)
			smoke.EmissionDirection = Enum.NormalId.Top
		end
		table.insert(breath.Cells, blob)
		local born = os.clock()
		local arrived = false
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			if not blob.Parent then
				connection:Disconnect()
				return
			end
			local travelled = math.min((os.clock() - born) * speed, distance)
			local radius = startRadius + (endRadius - startRadius) * math.clamp(travelled / reach, 0, 1)
			blob.Size = Vector3.new(radius * 1.6, 3, radius * 1.6)
			blob.CFrame = CFrame.new(cell.Origin + cell.Direction * travelled + Vector3.yAxis * 2)
			-- llamas del tamaño de la llama del mar (enormes al final)
			fire.Size = NumberSequence.new({ key(0, radius * 0.9), key(0.4, radius * 1.5), key(1, radius * 0.8) })
			core.Size = NumberSequence.new({ key(0, radius * 0.7), key(1, radius * 1.1) })
			if travelled >= distance and not arrived then
				arrived = true
				connection:Disconnect()
				-- Ya parada: arde en el suelo, más baja
				fire.Speed = NumberRange.new(1, 4)
				fire.Rate = 18
				core.Rate = 6
			end
		end)
	end
end

local function gokaBreathEnd(data: {[string]: any})
	local id = data.Id
	local breath = if typeof(id) == "string" then breaths[id] else nil
	if not breath then
		return
	end
	breaths[id] = nil
	breath.Connection:Disconnect()
	for _, emitter in breath.Emitters do
		emitter.Enabled = false
	end
	TweenService:Create(breath.Light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	task.delay(1, function()
		breath.Stream:Destroy()
	end)
	local linger = if typeof(data.Linger) == "number" then data.Linger else 3
	task.delay(linger, function()
		for _, cell in breath.Cells do
			for _, emitter in cell:GetChildren() do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = false
				end
			end
			task.delay(2.5, function()
				cell:Destroy()
			end)
		end
		local tint = breath.Tint
		if tint then
			TweenService:Create(tint, TweenInfo.new(1), { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0 }):Play()
			task.delay(1.1, function()
				tint:Destroy()
			end)
		end
	end)
end

-- Yasaka no Magatama ------------------------------------------------------------------------

-- Texturas de VFX Studio (elegidas viéndolas una a una)
local TEX = {
	CoreGlow = "rbxassetid://11425477167", -- Flare: brillo redondo con destello
	StarFlare = "rbxassetid://14197583306", -- Flare: estrella de cuatro puntas
	Rays = "rbxassetid://12386392796", -- Flare: rayos radiales
	ChakraFlame = "rbxassetid://250186345", -- Energy: llamas de aura
	SpinBlur = "rbxassetid://10365549270", -- Swirl: anillo con estela de giro
	Spark = "rbxassetid://5889875399", -- Spec: chispa alargada
	ShockRing = "rbxassetid://9573351641", -- Impact: anillo de picos
	GlowRing = "rbxassetid://7136539160", -- Impact: anillo de luz
	ThinRing = "rbxassetid://12403112662", -- Impact: anillo fino
	BurstRing = "rbxassetid://12402852980", -- Impact: estallido radial
	StarBurst = "rbxassetid://12402888086", -- Impact: estallido en estrella
	Smoke = "rbxassetid://2671910894", -- Smoke: nube
	SmokePuff = "rbxassetid://883906867", -- Smoke: bocanada
	TrailTaper = "rbxassetid://12402902689", -- Beam: cuña (en una estela: ancha en la cabeza, punta en la cola)
	TrailCore = "rbxassetid://74970414136395", -- Beam: línea con brillo
}

local HOT = Color3.fromRGB(255, 246, 222) -- blanco cálido: núcleo, borde y chispas
local SMOKE_DARK = Color3.fromRGB(26, 18, 22)

type Palette = { Skeleton: Color3, Glow: Color3, Core: Color3 }

type Shuriken = {
	Model: Model,
	Center: BasePart, -- invisible: emisores, estelas y luz
	Gather: BasePart, -- invisible y grande: de su superficie salen las chispas que se juntan al formarse
	Tomoe: { BasePart },
	Shells: { BasePart },
	Eyes: { BasePart },
	HeadTrails: { Trail }, -- finas, desde cada cabeza: con el giro dibujan una espiral
	Wake: { Trail }, -- la estela gruesa del centro
	Flames: ParticleEmitter, -- llamas de chakra alrededor
	Glow: ParticleEmitter,
	Blur: ParticleEmitter, -- el disco borroso del giro (solo en vuelo)
	GatherFx: ParticleEmitter,
	Sparks: ParticleEmitter,
	Light: PointLight,
	Scale: number,
	Palette: Palette,
}

local function paletteOf(character: Instance?): Palette
	local name = if typeof(character) == "Instance" then character:GetAttribute("MangekyoColor") else nil
	return (typeof(name) == "string" and MangekyoCatalog.Colors[name]) or MangekyoCatalog.Colors[MangekyoCatalog.DefaultColor]
end

local function magatamaTemplate(): MeshPart?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local models = shared and shared:FindFirstChild("ClanModels")
	local mesh = models and models:FindFirstChild("Magatama")
	return if mesh and mesh:IsA("MeshPart") then mesh else nil
end

-- Blanco cálido → brillo → color del Susanoo
local function hotSequence(palette: Palette): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOT),
		ColorSequenceKeypoint.new(0.35, palette.Glow),
		ColorSequenceKeypoint.new(1, palette.Skeleton),
	})
end

local function emitter(parent: Instance, texture: string, color: Color3, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Estela de cara a la cámara, de ancho 2 × halfWidth
local function wakeTrail(parent: BasePart, halfWidth: number, props: { [string]: any }): Trail
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, halfWidth, 0)
	a0.Parent = parent
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -halfWidth, 0)
	a1.Parent = parent
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.TextureLength = 1
	trail.Enabled = false
	for k, v in props do
		(trail :: any)[k] = v
	end
	trail.Parent = parent
	return trail
end

-- Punto suelto para efectos de un instante (se borra solo)
local function fxPoint(position: Vector3, life: number): BasePart
	local holder = plainPart("YasakaFx", Vector3.one * 0.2)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = folder
	task.delay(life, function()
		holder:Destroy()
	end)
	return holder
end

local function flashLight(parent: Instance, color: Color3, range: number, brightness: number, duration: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = parent
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
end

local function shakeNear(position: Vector3, radius: number, duration: number, strength: number)
	local me = localPlayer.Character
	local myRoot = me and rootOf(me)
	if myRoot and (myRoot.Position - position).Magnitude < radius then
		shakeCamera(duration, strength)
	end
end

-- Shuriken de tres tomoe en el plano XY de su centro (girando en +Z, la cabeza va delante)
local function buildShuriken(scale: number, palette: Palette): Shuriken
	local model = Instance.new("Model")
	model.Name = "YasakaShuriken"
	local center = plainPart("Center", Vector3.one * 0.2)
	center.Transparency = 1
	center.Parent = model
	model.PrimaryPart = center
	local gather = plainPart("Gather", Vector3.one * 5 * scale)
	gather.Transparency = 1
	gather.Parent = model
	local template = magatamaTemplate()
	local headRadius = 0.5 * scale
	local holeRadius = (if template then template:GetAttribute("HoleRadius") or 0.15 else 0.15) * scale
	local tomoe, shells, eyes, headTrails = {}, {}, {}, {}
	for k = 1, 3 do
		local body: BasePart
		if template then
			local mesh = template:Clone()
			mesh.Size = template.Size * scale
			body = mesh
		else
			local ball = plainPart("Tomoe", Vector3.one * headRadius * 2)
			ball.Shape = Enum.PartType.Ball
			body = ball
		end
		body.Name = "Tomoe" .. k
		body.Anchored = true
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.CastShadow = false
		body.Material = Enum.Material.Neon
		body.Color = palette.Skeleton
		body.Transparency = 0
		body.Parent = model
		local shell = body:Clone()
		shell.Name = "Shell" .. k
		shell.Material = Enum.Material.ForceField
		shell.Color = palette.Glow
		shell.Size = body.Size * 1.14
		shell.Transparency = 0
		shell.Parent = model
		local eye = plainPart("Eye" .. k, Vector3.one * holeRadius * 2.1)
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = HOT
		eye.Parent = model
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0, -headRadius * 0.6)
		a0.Parent = eye
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 0, headRadius * 0.6)
		a1.Parent = eye
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(HOT, palette.Glow)
		trail.Transparency = NumberSequence.new({ key(0, 0), key(0.6, 0.5), key(1, 1) })
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Lifetime = 0.2
		trail.FaceCamera = true
		trail.WidthScale = NumberSequence.new({ key(0, 1), key(1, 0.1) })
		trail.Enabled = false
		trail.Parent = eye
		table.insert(tomoe, body)
		table.insert(shells, shell)
		table.insert(eyes, eye)
		table.insert(headTrails, trail)
	end
	local hot = hotSequence(palette)
	local wake = {
		-- Cuña blanca que se vuelve del color del Susanoo
		wakeTrail(center, 1.05 * scale, {
			Name = "Wake",
			Texture = TEX.TrailTaper,
			Color = hot,
			Transparency = NumberSequence.new({ key(0, 0), key(0.5, 0.35), key(1, 1) }),
			WidthScale = NumberSequence.new({ key(0, 1), key(1, 0.6) }),
			Lifetime = 0.34,
			Brightness = 2.2,
		}),
		-- Halo de fuera, del color del Susanoo
		wakeTrail(center, 1.7 * scale, {
			Name = "WakeGlow",
			Texture = TEX.TrailTaper,
			Color = ColorSequence.new(palette.Glow, palette.Skeleton),
			Transparency = NumberSequence.new({ key(0, 0.45), key(1, 1) }),
			Lifetime = 0.22,
		}),
		-- Hilo de luz que dura más
		wakeTrail(center, 0.45 * scale, {
			Name = "WakeCore",
			Texture = TEX.TrailCore,
			Color = ColorSequence.new(HOT),
			Transparency = NumberSequence.new({ key(0, 0), key(0.7, 0.5), key(1, 1) }),
			Lifetime = 0.5,
			Brightness = 3,
		}),
	}
	local flames = emitter(center, TEX.ChakraFlame, HOT, {
		Name = "ChakraFlames",
		Color = hot,
		Size = NumberSequence.new({ key(0, 2.6 * scale), key(1, 3.4 * scale) }),
		Transparency = NumberSequence.new({ key(0, 0.3), key(0.6, 0.55), key(1, 1) }),
		Lifetime = NumberRange.new(0.16, 0.24),
		Rate = 30,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		LockedToPart = true,
		ZOffset = -1,
	})
	local glow = emitter(center, TEX.CoreGlow, palette.Glow, {
		Name = "CoreGlow",
		Size = NumberSequence.new(3.8 * scale),
		Transparency = NumberSequence.new({ key(0, 0.35), key(1, 0.8) }),
		Lifetime = NumberRange.new(0.1),
		Rate = 30,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		LockedToPart = true,
		ZOffset = -1.2,
	})
	local blur = emitter(center, TEX.SpinBlur, HOT, {
		Name = "SpinBlur",
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new(3.4 * scale),
		Transparency = NumberSequence.new({ key(0, 0.55), key(1, 1) }),
		Lifetime = NumberRange.new(0.12),
		Rate = 24,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-1080),
		LockedToPart = true,
		ZOffset = 0.3,
		Enabled = false,
	})
	local gatherFx = emitter(gather, TEX.Spark, HOT, {
		Name = "Gather",
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 0.15 * scale), key(0.6, 0.45 * scale), key(1, 0) }),
		Transparency = NumberSequence.new({ key(0, 0.6), key(0.3, 0), key(1, 0.2) }),
		Lifetime = NumberRange.new(0.2, 0.24),
		Speed = NumberRange.new(10 * scale, 11 * scale),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		LockedToPart = true,
	})
	local sparks = emitter(center, TEX.Spark, HOT, {
		Name = "Sparks",
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 0.35 * scale), key(1, 0) }),
		Lifetime = NumberRange.new(0.18, 0.32),
		Speed = NumberRange.new(6, 16),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
	local light = Instance.new("PointLight")
	light.Color = palette.Glow
	light.Range = 12 * scale
	light.Brightness = 3
	light.Parent = center
	-- Borde blanco alrededor de las tomoe (como en el juego)
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = palette.Skeleton
	highlight.FillTransparency = 1
	highlight.OutlineColor = HOT
	highlight.OutlineTransparency = 0
	highlight.Adornee = model
	highlight.Parent = model
	return {
		Model = model,
		Center = center,
		Gather = gather,
		Tomoe = tomoe,
		Shells = shells,
		Eyes = eyes,
		HeadTrails = headTrails,
		Wake = wake,
		Flames = flames,
		Glow = glow,
		Blur = blur,
		GatherFx = gatherFx,
		Sparks = sparks,
		Light = light,
		Scale = scale,
		Palette = palette,
	}
end

-- Coloca las tomoe: frame = centro (plano XY), radius = a qué distancia del centro van las
-- cabezas, grow = tamaño (0..1+), spin = giro en Z
local function placeShuriken(s: Shuriken, frame: CFrame, radius: number, grow: number, spin: number)
	local template = magatamaTemplate()
	local headToBody = if template then template:GetAttribute("HeadToBody") else nil
	s.Center.CFrame = frame
	s.Gather.CFrame = frame
	for k = 1, 3 do
		local head = frame * CFrame.Angles(0, 0, spin + (k - 1) * math.pi * 2 / 3) * CFrame.new(0, radius, 0)
		local body = s.Tomoe[k]
		local g = math.max(grow, 0.01)
		local cframe = if typeof(headToBody) == "CFrame"
			then head * CFrame.new(headToBody.Position * s.Scale * g) * headToBody.Rotation
			else head
		if template then
			body.Size = template.Size * s.Scale * g
		else
			body.Size = Vector3.one * s.Scale * g
		end
		body.CFrame = cframe
		s.Shells[k].Size = body.Size * 1.14
		s.Shells[k].CFrame = cframe
		s.Eyes[k].Size = Vector3.one * 0.15 * 2.1 * s.Scale * g
		s.Eyes[k].CFrame = head
	end
end

local function setFlying(s: Shuriken, flying: boolean)
	for _, trail in s.HeadTrails do
		trail.Enabled = flying
	end
	for _, trail in s.Wake do
		trail.Enabled = flying
	end
	s.Blur.Enabled = flying
	s.Sparks.Rate = if flying then 40 else 0
end

-- Apaga todo lo que emite (lo ya emitido se acaba solo)
local function quiet(s: Shuriken)
	setFlying(s, false)
	s.Flames.Enabled = false
	s.Glow.Enabled = false
	s.GatherFx.Enabled = false
end

local function fadeShuriken(s: Shuriken, duration: number, burst: boolean)
	quiet(s)
	if burst then
		s.Sparks:Emit(14)
		s.Flames:Emit(3)
	end
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for k = 1, 3 do
		TweenService:Create(s.Tomoe[k], info, { Transparency = 1, Size = s.Tomoe[k].Size * 0.3 }):Play()
		TweenService:Create(s.Shells[k], info, { Transparency = 1 }):Play()
		TweenService:Create(s.Eyes[k], info, { Transparency = 1 }):Play()
	end
	TweenService:Create(s.Light, info, { Brightness = 0 }):Play()
	task.delay(duration + 0.5, function()
		s.Model:Destroy()
	end)
end

-- Las tres tomoe salen despedidas girando (bloqueo, pared)
local function shatterShuriken(s: Shuriken, frame: CFrame)
	quiet(s)
	s.Sparks:Emit(18)
	local info = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for k = 1, 3 do
		local out = frame * CFrame.Angles(0, 0, (k - 1) * math.pi * 2 / 3)
		local away = out * CFrame.new(0, 4.5 * s.Scale / 1.4, 0) * CFrame.Angles(0, 0, math.rad(240))
		for _, part in { s.Tomoe[k], s.Shells[k], s.Eyes[k] } do
			local offset = out:ToObjectSpace(part.CFrame)
			TweenService:Create(part, info, {
				CFrame = away * offset,
				Size = part.Size * 0.25,
				Transparency = 1,
			}):Play()
		end
	end
	TweenService:Create(s.Light, info, { Brightness = 0 }):Play()
	task.delay(0.6, function()
		s.Model:Destroy()
	end)
end

-- Destello de contacto: estrella, chispas y luz
local function contactFlash(position: Vector3, k: number, palette: Palette, sparks: number)
	local holder = fxPoint(position, 1)
	emitter(holder, TEX.StarFlare, HOT, {
		Size = NumberSequence.new({ key(0, 5 * k), key(1, 9 * k) }),
		Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
		Lifetime = NumberRange.new(0.16),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-15, 15),
		ZOffset = 2,
	}):Emit(1)
	emitter(holder, TEX.Spark, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 0.7 * k), key(1, 0) }),
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(28 * k, 60 * k),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	}):Emit(sparks)
	flashLight(holder, palette.Glow, 22 * k, 7, 0.35)
end

-- Sello de tres tomoe gigante que destella de cara a la cámara de cada uno
local function tomoeSeal(position: Vector3, k: number, palette: Palette)
	local template = magatamaTemplate()
	local headToBody = if template then template:GetAttribute("HeadToBody") else nil
	local sealScale = 3.2 * k
	local ring = 1.0 * sealScale
	local model = Instance.new("Model")
	model.Name = "YasakaSeal"
	local baseSize = if template
		then Vector3.new(template.Size.X, template.Size.Y, template.Size.Z * 0.25) * sealScale
		else Vector3.one * sealScale
	local parts = {}
	for i = 1, 3 do
		local body: BasePart
		if template then
			body = template:Clone()
		else
			local ball = plainPart("SealTomoe", baseSize)
			ball.Shape = Enum.PartType.Ball
			body = ball
		end
		body.Anchored = true
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.CastShadow = false
		body.Material = Enum.Material.Neon
		body.Color = palette.Glow:Lerp(HOT, 0.45)
		body.Size = baseSize
		body.Transparency = 0.05
		body.Parent = model
		parts[i] = body
	end
	local holder = plainPart("SealRing", Vector3.one * 0.2)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = model
	model.Parent = folder
	emitter(holder, TEX.GlowRing, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 3.4 * sealScale), key(1, 4.4 * sealScale) }),
		Transparency = NumberSequence.new({ key(0, 0), key(0.4, 0.1), key(1, 1) }),
		Lifetime = NumberRange.new(0.32),
		Speed = NumberRange.new(0),
		LockedToPart = true,
		ZOffset = 0.5,
	}):Emit(1)
	local duration = 0.34
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		local camera = Workspace.CurrentCamera
		local frame = if camera then CFrame.lookAt(position, camera.CFrame.Position) else CFrame.new(position)
		local grow = 0.75 + 0.45 * (1 - (1 - t) ^ 3)
		local spin = t * math.rad(70)
		for i, body in parts do
			local head = frame * CFrame.Angles(0, 0, spin + (i - 1) * math.pi * 2 / 3) * CFrame.new(0, ring * grow, 0)
			body.CFrame = if typeof(headToBody) == "CFrame"
				then head * CFrame.new(headToBody.Position * sealScale * grow) * headToBody.Rotation
				else head
			body.Size = baseSize * grow
			body.Transparency = if t < 0.35 then 0.05 else 0.05 + 0.95 * ((t - 0.35) / 0.65) ^ 1.5
		end
		holder.CFrame = frame
		if t >= 1 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- Explosión de chakra: esfera de luz blanca, onda de choque, rayos, vetas del color del Susanoo,
-- chispas que caen y humo oscuro
local function chakraExplosion(position: Vector3, k: number, palette: Palette)
	local holder = fxPoint(position, 2)
	local core = plainPart("YasakaBlast", Vector3.one * 1.2 * k)
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = HOT
	core.CFrame = CFrame.new(position)
	core.Parent = folder
	TweenService:Create(core, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * 9 * k,
	}):Play()
	TweenService:Create(core, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()
	local shell = core:Clone()
	shell.Material = Enum.Material.ForceField
	shell.Color = palette.Skeleton
	shell.Size = Vector3.one * 2 * k
	shell.Parent = folder
	TweenService:Create(shell, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * 13 * k,
		Transparency = 1,
	}):Play()
	task.delay(0.5, function()
		core:Destroy()
		shell:Destroy()
	end)
	emitter(holder, TEX.ShockRing, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 4 * k), key(1, 20 * k) }),
		Transparency = NumberSequence.new({ key(0, 0), key(0.6, 0.4), key(1, 1) }),
		Lifetime = NumberRange.new(0.38),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		ZOffset = 1,
	}):Emit(1)
	emitter(holder, TEX.BurstRing, palette.Glow, {
		Size = NumberSequence.new({ key(0, 6 * k), key(1, 15 * k) }),
		Transparency = NumberSequence.new({ key(0, 0.1), key(1, 1) }),
		Lifetime = NumberRange.new(0.3),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		ZOffset = 0.8,
	}):Emit(1)
	emitter(holder, TEX.Rays, HOT, {
		Size = NumberSequence.new({ key(0, 10 * k), key(1, 18 * k) }),
		Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
		Lifetime = NumberRange.new(0.22),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		ZOffset = 1.5,
	}):Emit(1)
	emitter(holder, TEX.StarBurst, palette.Skeleton, {
		Size = NumberSequence.new({ key(0, 8 * k), key(1, 16 * k) }),
		Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
		Lifetime = NumberRange.new(0.3),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		ZOffset = 1.2,
	}):Emit(2)
	emitter(holder, TEX.Spark, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 1 * k), key(1, 0) }),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(45 * k, 90 * k),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Acceleration = Vector3.new(0, -30, 0),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	}):Emit(44)
	emitter(holder, TEX.SmokePuff, SMOKE_DARK, {
		LightEmission = 0,
		Size = NumberSequence.new({ key(0, 4 * k), key(1, 10 * k) }),
		Transparency = NumberSequence.new({ key(0, 0.35), key(1, 1) }),
		Lifetime = NumberRange.new(0.7, 1.0),
		Speed = NumberRange.new(8 * k, 14 * k),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		ZOffset = -1,
	}):Emit(9)
	flashLight(holder, palette.Glow, 40 * k, 12, 0.6)
	shakeNear(position, 45 * k, 0.4, 2.4)
end

-- Impacto en un cuerpo (como en el juego): humo oscuro que lo envuelve con las tres tomoe girando
-- a su alrededor y cerrándose, un sello de tres tomoe gigante y la explosión
local ORBIT_TIME = 0.22

local function hitSequence(s: Shuriken?, position: Vector3, target: Instance?, scale: number, palette: Palette)
	local k = scale / 1.4
	contactFlash(position, k, palette, 24)
	local holder = fxPoint(position, 1.5)
	emitter(holder, TEX.Smoke, SMOKE_DARK, {
		LightEmission = 0,
		Size = NumberSequence.new({ key(0, 3 * k), key(1, 6.5 * k) }),
		Transparency = NumberSequence.new({ key(0, 0.2), key(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.55),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		ZOffset = -0.5,
	}):Emit(10)
	local orbitSparks = emitter(holder, TEX.Spark, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 0.5 * k), key(1, 0) }),
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(10 * k, 22 * k),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rate = 70,
	})
	local shuriken = s
	if not shuriken then
		local built = buildShuriken(scale, palette)
		built.Model.Parent = folder
		shuriken = built
	end
	local orbiting = shuriken :: Shuriken
	quiet(orbiting)
	for _, trail in orbiting.HeadTrails do
		trail.Enabled = true
	end
	orbiting.Flames.Enabled = true
	local started = os.clock()
	local last = started
	local spin = 0
	local sealed = false
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - last
		last = now
		local t = now - started
		local root = rootOf(target)
		local center = if root then root.Position else position
		holder.CFrame = CFrame.new(center)
		local orbitT = math.clamp(t / ORBIT_TIME, 0, 1)
		spin += dt * 26
		-- Las tomoe giran casi en horizontal alrededor del cuerpo y se cierran sobre él
		local radius = 2.6 * k * (1 - 0.75 * orbitT ^ 2)
		local frame = CFrame.new(center) * CFrame.Angles(math.rad(72), 0, 0)
		placeShuriken(orbiting, frame, radius, 1 - 0.3 * orbitT, spin)
		if t >= ORBIT_TIME * 0.7 and not sealed then
			sealed = true
			tomoeSeal(center, k, palette)
		end
		if t >= ORBIT_TIME then
			connection:Disconnect()
			orbitSparks.Enabled = false
			chakraExplosion(center, k, palette)
			fadeShuriken(orbiting, 0.08, false)
		end
	end)
end

-- Al soltarlo: destello en la mano, un anillo de aire alrededor del lanzamiento y chispas hacia delante
local function releaseBurst(position: Vector3, direction: Vector3, scale: number, palette: Palette)
	local holder = fxPoint(position, 0.8)
	holder.CFrame = CFrame.lookAt(position, position + direction)
	emitter(holder, TEX.StarFlare, HOT, {
		Size = NumberSequence.new({ key(0, 3 * scale), key(1, 5 * scale) }),
		Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
		Lifetime = NumberRange.new(0.12),
		Speed = NumberRange.new(0),
		ZOffset = 2,
	}):Emit(1)
	-- Perpendicular al lanzamiento: la orientación la da su velocidad
	emitter(holder, TEX.ThinRing, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 1.5 * scale), key(1, 5.5 * scale) }),
		Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
		Lifetime = NumberRange.new(0.22),
		Speed = NumberRange.new(6),
		EmissionDirection = Enum.NormalId.Front,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Drag = 8,
	}):Emit(1)
	emitter(holder, TEX.Spark, HOT, {
		Color = ColorSequence.new(HOT, palette.Glow),
		Size = NumberSequence.new({ key(0, 0.5 * scale), key(1, 0) }),
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 5,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	}):Emit(14)
	flashLight(holder, palette.Glow, 14 * scale, 5, 0.25)
end

-- Dónde se forma: sobre la palma de la mano del Susanoo (o delante del pecho si aún no está)
local function formingFrame(character: Instance, scale: number): CFrame?
	local root = rootOf(character)
	if not root then
		return nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local visuals = Workspace:FindFirstChild("SusanooVisuals")
	local model = visuals and visuals:FindFirstChild("Susanoo_" .. character.Name)
	local hand = model and model:FindFirstChild("Hand")
	local position: Vector3
	if hand and hand:IsA("BasePart") then
		local side = SusanooConfig.Sides[SusanooConfig.Side]
		local palm = hand.CFrame:VectorToWorldSpace(Vector3.new(-(side.ArmSign or 1), 0, 0))
		position = hand.Position + palm * (1.4 * scale + 0.5) + Vector3.yAxis * 0.3
	else
		position = root.Position + look * 3 + Vector3.yAxis * 2
	end
	return CFrame.lookAt(position, position + look)
end

type Held = { Shuriken: Shuriken, Connection: RBXScriptConnection, Ready: boolean, Snap: (CFrame?) -> () }
local heldMagatama: { [Instance]: Held } = {}

local function dropMagatama(character: Instance, fade: boolean)
	local held = heldMagatama[character]
	if not held then
		return
	end
	heldMagatama[character] = nil
	held.Connection:Disconnect()
	if fade then
		fadeShuriken(held.Shuriken, 0.2, true)
	end
end

-- Carga: las tomoe aparecen de golpe en la palma entre llamas de chakra; mientras dura la carga
-- el chakra se junta cada vez más fuerte (chispas, llamas y luz) y las tomoe se cierran girando
-- cada vez más rápido hasta juntarse con un destello
local function formMagatama(character: Instance, scale: number, delay: number, formTime: number)
	dropMagatama(character, true)
	local palette = paletteOf(character)
	local shuriken = buildShuriken(scale, palette)
	local ring = 1.0 * scale -- un poco más que RingRadius (0.9): hueco entre cola y cabeza
	local started = os.clock() + delay
	local spin = 0
	local last = os.clock()
	local entry: Held
	local function snap(frame: CFrame?)
		if entry.Ready then
			return
		end
		entry.Ready = true
		shuriken.GatherFx.Rate = 0
		shuriken.Flames.Rate = 30
		shuriken.Light.Brightness = 3
		if not frame and not shuriken.Model.Parent then
			return -- aún no se veía: sin destello
		end
		local at = (frame or shuriken.Center.CFrame).Position
		local holder = fxPoint(at, 0.8)
		emitter(holder, TEX.StarFlare, HOT, {
			Size = NumberSequence.new({ key(0, 3.5 * scale), key(1, 6 * scale) }),
			Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
			Lifetime = NumberRange.new(0.14),
			Speed = NumberRange.new(0),
			ZOffset = 2,
		}):Emit(1)
		emitter(holder, TEX.GlowRing, HOT, {
			Color = ColorSequence.new(HOT, palette.Glow),
			Size = NumberSequence.new({ key(0, 2 * scale), key(1, 6 * scale) }),
			Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
			Lifetime = NumberRange.new(0.2),
			Speed = NumberRange.new(0),
			ZOffset = 1,
		}):Emit(1)
		flashLight(holder, palette.Glow, 14 * scale, 5, 0.25)
	end
	shuriken.Model.Parent = nil
	local connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - last
		last = now
		if not character.Parent then
			dropMagatama(character, false)
			shuriken.Model:Destroy()
			return
		end
		if now < started then
			return
		end
		local frame = formingFrame(character, scale)
		if not frame then
			return
		end
		if not shuriken.Model.Parent then
			shuriken.Model.Parent = folder
			shuriken.Flames:Emit(4)
			playSound(ClanAssets.Sounds and ClanAssets.Sounds.YasakaForm, frame.Position, 0.9)
		end
		local t = math.clamp((now - started) / formTime, 0, 1)
		-- tamaño: pop elástico al aparecer (corto aunque la carga sea larga)
		local popT = math.clamp((now - started) / 0.18, 0, 1)
		local grow = if popT < 1 then 1 + 1.7 * (popT - 1) ^ 3 + 0.7 * (popT - 1) ^ 2 else 1
		-- la carga sube: más chispas que se juntan, más llamas y más luz
		if not entry.Ready then
			shuriken.GatherFx.Rate = 50 + 90 * t
			shuriken.Flames.Rate = 12 + 36 * t
			shuriken.Light.Brightness = 1 + 3 * t
		end
		-- órbita: abiertas al principio, se cierran a lo largo de la carga girando cada vez más rápido
		local eased = t * t * (3 - 2 * t)
		local radius = ring * (2.1 - 1.1 * eased)
		spin += dt * (if entry.Ready then 14 else 3 + 23 * t * t)
		placeShuriken(shuriken, frame, radius, grow, spin)
		if t >= 1 then
			snap(frame)
		end
	end)
	entry = { Shuriken = shuriken, Connection = connection, Ready = false, Snap = snap }
	heldMagatama[character] = entry
	-- Respaldo: si no llega el lanzamiento
	task.delay(delay + formTime + 2, function()
		if heldMagatama[character] == entry then
			dropMagatama(character, true)
		end
	end)
end

type Flight = {
	Shuriken: Shuriken,
	Connection: RBXScriptConnection,
	Carrier: Vector3, -- el punto guía que persigue (como en el servidor)
	Position: Vector3, -- donde se ve: el guía más el arco
	Direction: Vector3, -- rumbo del guía
	Moving: Vector3, -- hacia dónde se mueve de verdad
	Target: Instance?,
	AimPoint: Vector3?,
	Curve: Vector3,
	Traveled: number,
	Total: number,
	Progress: number,
	Frame: CFrame,
}
local flights: { [string]: Flight } = {}

local function yasakaForm(data: { [string]: any })
	local character = data.Character
	if typeof(character) ~= "Instance" then
		return
	end
	formMagatama(character,
		if typeof(data.Scale) == "number" then data.Scale else 1.4,
		if typeof(data.Delay) == "number" then data.Delay else 0,
		if typeof(data.FormTime) == "number" then data.FormTime else 1.0)
end

local function turnToward(v: Vector3, goal: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(v:Dot(goal), -1, 1))
	if angle <= maxAngle or angle < 1e-4 then
		return goal
	end
	local axis = v:Cross(goal)
	if axis.Magnitude < 1e-4 then
		return v
	end
	return (CFrame.fromAxisAngle(axis.Unit, maxAngle) * v).Unit
end

-- Desvío del arco: perpendicular al rumbo, máximo a mitad de camino y cero al salir y al llegar
-- (la misma cuenta que el servidor)
local function curveOffset(direction: Vector3, curve: Vector3, progress: number): Vector3
	local lateral = curve - direction * curve:Dot(direction)
	if lateral.Magnitude < 1e-3 then
		return Vector3.zero
	end
	return lateral.Unit * curve.Magnitude * math.sin(math.pi * progress)
end

local function yasakaThrow(data: { [string]: any })
	if typeof(data.Id) ~= "string" or typeof(data.Start) ~= "Vector3" or typeof(data.Direction) ~= "Vector3" then
		return
	end
	local character = data.Character
	local scale = if typeof(data.Scale) == "number" then data.Scale else 1.4
	local speed = if typeof(data.Speed) == "number" then data.Speed else 110
	local turnRate = math.rad(if typeof(data.TurnRate) == "number" then data.TurnRate else 120)
	local lifetime = if typeof(data.Lifetime) == "number" then data.Lifetime else 1.6
	-- El que estaba en la mano sale (si aún no se había juntado, se junta ya)
	local shuriken: Shuriken
	local held = if typeof(character) == "Instance" then heldMagatama[character] else nil
	if held then
		heldMagatama[character] = nil
		held.Connection:Disconnect()
		held.Snap(nil)
		shuriken = held.Shuriken
	else
		shuriken = buildShuriken(scale, paletteOf(character))
	end
	shuriken.Model.Parent = folder
	shuriken.GatherFx.Rate = 0
	setFlying(shuriken, true)
	releaseBurst(data.Start, data.Direction.Unit, scale, shuriken.Palette)
	playSound(ClanAssets.Sounds and ClanAssets.Sounds.YasakaThrow, data.Start, 1)
	-- El siguiente se forma enseguida en la mano (Susanoo: tres seguidos)
	if typeof(character) == "Instance" and typeof(data.Remaining) == "number" and data.Remaining > 0 then
		formMagatama(character, scale, 0.02, 0.16)
	end

	local flight: Flight
	local started = os.clock()
	local last = started
	local spin = 0
	local radius = 1.0 * scale
	flight = {
		Shuriken = shuriken,
		Carrier = data.Start,
		Position = data.Start,
		Direction = data.Direction.Unit,
		Moving = data.Direction.Unit,
		Target = if typeof(data.Target) == "Instance" then data.Target else nil,
		AimPoint = if typeof(data.AimPoint) == "Vector3" then data.AimPoint else nil,
		Curve = if typeof(data.Curve) == "Vector3" then data.Curve else Vector3.zero,
		Traveled = 0,
		Total = if typeof(data.Total) == "number" then data.Total else speed * lifetime,
		Progress = 0,
		Frame = CFrame.new(data.Start),
		Connection = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			local dt = math.min(now - last, 0.1)
			last = now
			-- Mismo guiado y arco que el servidor (YasakaPos corrige la diferencia)
			local goal: Vector3? = nil
			local target = flight.Target
			if target then
				local root = rootOf(target)
				if root and target:GetAttribute("SubstitutionHidden") ~= true then
					goal = root.Position + Vector3.yAxis * 0.5
					local toGoal = (goal :: Vector3) - flight.Carrier
					if toGoal.Magnitude > 0.5 then
						flight.Direction = turnToward(flight.Direction, toGoal.Unit, turnRate * dt)
					end
				else
					flight.Target = nil
				end
			else
				goal = flight.AimPoint
			end
			local step = speed * dt
			flight.Carrier += flight.Direction * step
			flight.Traveled += step
			if goal then
				flight.Total = flight.Traveled + (goal - flight.Carrier).Magnitude
			end
			flight.Progress = math.max(flight.Progress, math.clamp(flight.Traveled / math.max(flight.Total, 1), 0, 1))
			local position = flight.Carrier + curveOffset(flight.Direction, flight.Curve, flight.Progress)
			local path = position - flight.Position
			if path.Magnitude > 1e-3 then
				flight.Moving = path.Unit
			end
			flight.Position = position
			spin += dt * 22
			-- De cara a donde va, un poco inclinado
			local frame = CFrame.lookAt(position, position + flight.Moving) * CFrame.Angles(math.rad(14), 0, 0)
			flight.Frame = frame
			placeShuriken(shuriken, frame, radius, 1, spin)
			if now - started > lifetime + 1 then
				flight.Connection:Disconnect()
				flights[data.Id] = nil
				fadeShuriken(shuriken, 0.2, false)
			end
		end),
	}
	flights[data.Id] = flight
end

local function yasakaPos(data: { [string]: any })
	local flight = if typeof(data.Id) == "string" then flights[data.Id] else nil
	if not flight or typeof(data.Carrier) ~= "Vector3" then
		return
	end
	-- Se acerca a lo del servidor sin saltos
	flight.Carrier = flight.Carrier:Lerp(data.Carrier, 0.6)
	if typeof(data.Direction) == "Vector3" then
		local blended = flight.Direction:Lerp(data.Direction, 0.6)
		if blended.Magnitude > 1e-3 then
			flight.Direction = blended.Unit
		end
	end
	if typeof(data.Traveled) == "number" then
		flight.Traveled += (data.Traveled - flight.Traveled) * 0.6
	end
	if typeof(data.Progress) == "number" then
		flight.Progress = math.max(flight.Progress, flight.Progress + (data.Progress - flight.Progress) * 0.6)
	end
end

local function yasakaLost(data: { [string]: any })
	local flight = if typeof(data.Id) == "string" then flights[data.Id] else nil
	if flight then
		flight.Target = nil
	end
end

local function yasakaImpact(data: { [string]: any })
	local id = data.Id
	local flight = if typeof(id) == "string" then flights[id] else nil
	local position = if typeof(data.Position) == "Vector3" then data.Position else nil
	local kind = if typeof(data.Kind) == "string" then data.Kind else "Hit"
	local scale = if typeof(data.Scale) == "number" then data.Scale else 1.4
	local target = if typeof(data.Target) == "Instance" then data.Target else nil
	local palette = if flight then flight.Shuriken.Palette else MangekyoCatalog.Colors[MangekyoCatalog.DefaultColor]
	local k = scale / 1.4
	local shuriken: Shuriken? = nil
	if flight then
		flights[id] = nil
		flight.Connection:Disconnect()
		shuriken = flight.Shuriken
	end
	if not position then
		if shuriken then
			fadeShuriken(shuriken, 0.2, true)
		end
		return
	end
	local frame = if flight then flight.Frame.Rotation + position else CFrame.new(position)
	if kind == "Hit" then
		hitSequence(shuriken, position, target, scale, palette)
		playSound(ClanAssets.Sounds and ClanAssets.Sounds.YasakaImpact, position, 1.2)
	elseif kind == "World" then
		contactFlash(position, k, palette, 18)
		if shuriken then
			shatterShuriken(shuriken, frame)
		end
		task.delay(0.04, tomoeSeal, position, k * 0.85, palette)
		task.delay(0.08, chakraExplosion, position, k * 0.85, palette)
		playSound(ClanAssets.Sounds and ClanAssets.Sounds.YasakaImpact, position, 1.2)
	elseif kind == "Blocked" then
		-- Se rompe en la guardia: chispas y las tomoe despedidas, sin explosión
		contactFlash(position, k, palette, 40)
		if shuriken then
			shatterShuriken(shuriken, frame)
		end
		local holder = fxPoint(position, 1)
		emitter(holder, TEX.GlowRing, HOT, {
			Color = ColorSequence.new(HOT, palette.Glow),
			Size = NumberSequence.new({ key(0, 3 * k), key(1, 8 * k) }),
			Transparency = NumberSequence.new({ key(0, 0), key(1, 1) }),
			Lifetime = NumberRange.new(0.22),
			Speed = NumberRange.new(0),
			ZOffset = 1,
		}):Emit(1)
		shakeNear(position, 30 * k, 0.2, 1.2)
		playSound(ClanAssets.Sounds and ClanAssets.Sounds.YasakaImpact, position, 0.9)
	elseif kind == "Consumed" then
		-- Entró en el muro de Kagutsuchi: se deshace sin explotar (BlackWallConsume pone las llamas)
		if shuriken then
			fadeShuriken(shuriken, 0.15, false)
		end
	elseif kind == "Substituted" then
		contactFlash(position, k, palette, 16)
		if shuriken then
			shatterShuriken(shuriken, frame)
		end
		task.delay(0.05, chakraExplosion, position, k * 0.6, palette)
		playSound(ClanAssets.Sounds and ClanAssets.Sounds.YasakaImpact, position, 0.9)
	else
		-- Expire: se deshace en el aire
		if shuriken then
			fadeShuriken(shuriken, 0.25, true)
		end
		local holder = fxPoint(position, 0.6)
		emitter(holder, TEX.StarFlare, HOT, {
			Size = NumberSequence.new({ key(0, 2.5 * k), key(1, 0) }),
			Transparency = NumberSequence.new({ key(0, 0.2), key(1, 1) }),
			Lifetime = NumberRange.new(0.18),
			Speed = NumberRange.new(0),
		}):Emit(1)
	end
end

-- Kagutsuchi: Black Wall --------------------------------------------------------------------

-- El cuerpo del muro es fuego continuo, sin huecos: en cada tramo, tres capas paralelas con la
-- cortina de llamas negras (flipbook de 24 cuadros a 30 fps BlackFlame_Curtain_00..23, cada uno en
-- mosaico: las lenguas se tuercen, crecen y ondulan) que además se desplaza hacia arriba a distinta
-- velocidad (el fuego fluye y tiene profundidad) y, encima, la corona de lenguas
-- (BlackFlame_Crown_00..23). Todos los tramos de una capa van en el mismo cuadro (el mosaico sigue
-- de un tramo al otro); las capas van desfasadas. En los dos extremos, llamas normales (partículas)
-- tapan el canto de las capas: de lado no se ven tres láminas. Los tintes dejan el muro tan negro
-- como las partículas (que no reciben luz). Los extremos bajan para que no acabe en un corte recto. Las
-- partículas (el fuego de los jutsus teñido de negro) solo son el detalle: lamen arriba, en la
-- base y sobre las caras. Solo negro: nada de rojo. Texturas hechas para Wayless
-- (black_flame_textures.py en la carpeta del proyecto).
local WALL_CURTAIN_FRAMES = {
	"rbxassetid://114628792047283", "rbxassetid://119156923782896", "rbxassetid://136652598205606",
	"rbxassetid://95686197776775", "rbxassetid://106184331160961", "rbxassetid://101734996967710",
	"rbxassetid://73670523729792", "rbxassetid://90776101369801", "rbxassetid://121830277662981",
	"rbxassetid://83016332613406", "rbxassetid://82060219716456", "rbxassetid://132700198028669",
	"rbxassetid://83297216318104", "rbxassetid://76834595829048", "rbxassetid://113474507028917",
	"rbxassetid://79858650451627", "rbxassetid://90705182112162", "rbxassetid://94362927097066",
	"rbxassetid://104043897079499", "rbxassetid://96472936727197", "rbxassetid://103119345845132",
	"rbxassetid://73315409980523", "rbxassetid://116734918330179", "rbxassetid://117663204305064",
}
local WALL_CROWN_FRAMES = {
	"rbxassetid://101221612180869", "rbxassetid://109172236909398", "rbxassetid://101201407556815",
	"rbxassetid://133671186824488", "rbxassetid://96705606057187", "rbxassetid://78012942916394",
	"rbxassetid://95410370730876", "rbxassetid://112365785726612", "rbxassetid://87362817811779",
	"rbxassetid://119478499287997", "rbxassetid://90233370779087", "rbxassetid://136439423216177",
	"rbxassetid://113431795079130", "rbxassetid://128699889240795", "rbxassetid://110169490693438",
	"rbxassetid://131121696127895", "rbxassetid://81145961683672", "rbxassetid://73155980312494",
	"rbxassetid://70645291856936", "rbxassetid://112876800354543", "rbxassetid://128540279803711",
	"rbxassetid://77657774999929", "rbxassetid://101704855695992", "rbxassetid://133320293766013",
}
local WALL_FPS = 30 -- como el resto de los VFX (el fuego de los jutsus va a 30)

-- Precarga: que el primer muro no parpadee mientras bajan los cuadros
task.spawn(function()
	local ids = table.clone(WALL_CURTAIN_FRAMES)
	for _, id in WALL_CROWN_FRAMES do
		table.insert(ids, id)
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(ids)
	end)
end)
local WALL_TILE_U = 14
local WALL_TILE_V = 28
-- Capas: desplazamiento hacia fuera (studs), tinte (más oscuro en medio), desfase del mosaico y
-- velocidad de subida (studs/s)
local WALL_LAYERS = {
	{ Offset = -1.1, Tint = 0.55, Shift = 0.37, Speed = 6 },
	{ Offset = 0, Tint = 0.35, Shift = 0.71, Speed = 8.5 },
	{ Offset = 1.1, Tint = 0.55, Shift = 0.05, Speed = 5 },
}
local WALL_SIDE_FLAMES = 0.55 -- partículas por stud² en los costados (tapan el canto de las capas)
local WALL_FACE_FLAMES = 0.09 -- partículas por stud² de cara y segundo (detalle, no cuerpo)

local function numberOr(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function wallFlames(parent: BasePart, size: number, zOffset: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "WallFlame"
	e.Texture = ClanAssets.FireFlipbook or ClanAssets.FlameWisp or "rbxasset://textures/particles/fire_main.dds"
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.FlipbookFramerate = NumberRange.new(30)
	e.Color = ColorSequence.new(BLACK)
	e.LightEmission = 0
	e.LightInfluence = 0
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 0.55) -- lo que dura la animación (16 cuadros a 30 fps)
	e.Speed = NumberRange.new(2, 5)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, 8, 0)
	e.Drag = 1
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Size = NumberSequence.new({ key(0, size * 0.65), key(0.35, size), key(1, size * 0.45) })
	e.Rotation = NumberRange.new(-15, 15)
	e.RotSpeed = NumberRange.new(-15, 15)
	e.Transparency = NumberSequence.new({ key(0, 0), key(0.7, 0.45), key(1, 1) })
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.ZOffset = zOffset
	e.Parent = parent
	return e
end

local function sheet(name: string, size: Vector3, parent: Instance): BasePart
	local part = plainPart(name, size)
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function wallTexture(part: BasePart, image: string, tileV: number, shiftU: number, tint: number): { Texture }
	local list = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local texture = Instance.new("Texture")
		texture.Texture = image
		texture.Face = face
		texture.StudsPerTileU = WALL_TILE_U
		texture.StudsPerTileV = tileV
		texture.OffsetStudsU = shiftU
		texture.Color3 = Color3.new(tint, tint, tint)
		texture.Transparency = 1
		texture.Parent = part
		table.insert(list, texture)
	end
	return list
end

type WallLayer = {
	Body: BasePart,
	Crown: BasePart,
	BodyTextures: { Texture },
	CrownTextures: { Texture },
	Local: CFrame, -- dónde va respecto a la base del tramo (capa paralela o plano cruzado)
	Width: number,
	Speed: number,
	Phase: number,
	FramePhase: number, -- desfase del flipbook (por capa)
	Frame: number, -- cuadro puesto ahora
}

type WallSegment = {
	Frame: CFrame,
	Height: number, -- su altura (los extremos más bajos)
	Spread: number, -- 0 en el centro, 1 en los extremos
	Layers: { WallLayer },
	Caps: { { Part: BasePart, X: number } }, -- llamas de los costados (solo en los extremos)
	Line: BasePart,
	Emitters: { ParticleEmitter },
	Rates: { number },
	Detail: BasePart,
	Tips: BasePart,
	Started: boolean,
	Ended: boolean,
}

local function blackWallForm(data: { [string]: any })
	local segments = data.Segments
	if typeof(segments) ~= "table" or #segments == 0 then
		return
	end
	local length = numberOr(data.SegmentLength, 4)
	local height = numberOr(data.Height, 22)
	local smokeHeight = numberOr(data.SmokeHeight, 50)
	local telegraph = numberOr(data.Telegraph, 0.6)
	local rise = numberOr(data.RiseTime, 0.35)
	local duration = numberOr(data.Duration, 6)
	local crownHeight = math.max(6, height * 0.36)
	local thickness = numberOr(data.Thickness, 3.5)
	local model = Instance.new("Model")
	model.Name = "BlackWall"
	model.Parent = folder
	local count = #segments
	local middle = (count + 1) / 2
	local width = length + 0.1
	local wallPhase = math.random() * WALL_TILE_V -- igual en todos los tramos: el mosaico sigue
	local list: { WallSegment } = {}
	local center = Vector3.zero
	for i, frame in segments do
		if typeof(frame) ~= "CFrame" then
			continue
		end
		center += frame.Position
		local spread = if count > 1 then math.abs(i - middle) / (middle - 1) else 0
		-- Los extremos bajan (el muro no acaba en un corte recto)
		local segmentHeight = height * (1 - 0.5 * math.clamp((spread - 0.6) / 0.4, 0, 1) ^ 1.5)
		local along = (i - 1) * length -- para que el mosaico siga de un tramo al siguiente
		local layers = {}
		for k, spec in WALL_LAYERS do
			local body = sheet("Body", Vector3.new(width, 0.1, 0.05), model)
			local crown = sheet("Crown", Vector3.new(width, crownHeight, 0.05), model)
			table.insert(layers, {
				Body = body,
				Crown = crown,
				BodyTextures = wallTexture(body, WALL_CURTAIN_FRAMES[1], WALL_TILE_V, along + spec.Shift * WALL_TILE_U, spec.Tint),
				CrownTextures = wallTexture(crown, WALL_CROWN_FRAMES[1], crownHeight, along + spec.Shift * WALL_TILE_U, spec.Tint),
				Local = CFrame.new(0, 0, spec.Offset),
				Width = width,
				Speed = spec.Speed,
				Phase = wallPhase + k * 7,
				FramePhase = k * 8,
				Frame = 1,
			})
		end
		-- Costados (solo en los extremos): llamas normales que tapan el canto de las capas
		local caps = {}
		local capEmitters = {}
		local capAt = {}
		if i == 1 then
			table.insert(capAt, -length / 2)
		end
		if i == count then
			table.insert(capAt, length / 2)
		end
		for _, x in capAt do
			local cap = sheet("SideFlames", Vector3.new(2.2, 0.1, thickness + 1.5), model)
			table.insert(capEmitters, wallFlames(cap, 3.6, 0.7))
			table.insert(caps, { Part = cap, X = x })
		end
		-- El aviso: línea quemada en el suelo con llamitas negras
		local line = plainPart("ScorchLine", Vector3.new(width, 0.12, 1))
		line.Color = Color3.fromRGB(14, 10, 12)
		line.Material = Enum.Material.SmoothPlastic
		line.Transparency = 0.15
		line.CFrame = frame * CFrame.new(0, 0.07, 0)
		line.Parent = model
		local lineFlames = wallFlames(line, 1.3, 0)
		lineFlames.Rate = 16
		-- Partículas de detalle: sobre las caras, en la base y lamiendo por arriba
		local detail = sheet("Detail", Vector3.new(width, segmentHeight * 0.8, 3), model)
		detail.CFrame = frame * CFrame.new(0, segmentHeight * 0.45, 0)
		local faceFlames = wallFlames(detail, 3, 0.6)
		local base = sheet("Base", Vector3.new(width, 2.5, 4), model)
		base.CFrame = frame * CFrame.new(0, 1.25, 0)
		local baseFlames = wallFlames(base, 4.2, 0.7)
		local tips = sheet("Tips", Vector3.new(width, 3, 2.5), model)
		local tipFlames = wallFlames(tips, 3.6, 0.6)
		tipFlames.Speed = NumberRange.new(5, 9)
		-- Un poco de humo negro, tenue, que marca la altura que no se puede saltar
		local haze = Instance.new("ParticleEmitter")
		haze.Name = "WallHaze"
		haze.Texture = "rbxassetid://2671910894" -- VFX Studio > Smoke
		haze.Color = ColorSequence.new(Color3.fromRGB(14, 11, 13))
		haze.LightEmission = 0
		haze.LightInfluence = 0
		haze.Rate = 0
		haze.Lifetime = NumberRange.new(1.8, 2.2)
		haze.Speed = NumberRange.new(math.max(6, (smokeHeight - segmentHeight) / 2))
		haze.EmissionDirection = Enum.NormalId.Top
		haze.SpreadAngle = Vector2.new(6, 6)
		haze.Shape = Enum.ParticleEmitterShape.Box
		haze.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		haze.Size = NumberSequence.new({ key(0, 3), key(1, 8) })
		haze.Transparency = NumberSequence.new({ key(0, 0.8), key(0.5, 0.86), key(1, 1) })
		haze.Rotation = NumberRange.new(0, 360)
		haze.RotSpeed = NumberRange.new(-20, 20)
		haze.ZOffset = -1
		haze.Parent = tips
		local emitters = { faceFlames, baseFlames, tipFlames, haze, lineFlames }
		local rates = { width * segmentHeight * WALL_FACE_FLAMES, width * 2.5, width * 2.2, width * 0.18, 0 }
		for _, emitter in capEmitters do
			table.insert(emitters, emitter)
			table.insert(rates, segmentHeight * (thickness + 1.5) * WALL_SIDE_FLAMES)
		end
		table.insert(list, {
			Frame = frame,
			Height = segmentHeight,
			Spread = spread,
			Layers = layers,
			Line = line,
			Caps = caps,
			Emitters = emitters,
			Rates = rates,
			Detail = detail,
			Tips = tips,
			Started = false,
			Ended = false,
		})
	end
	if #list == 0 then
		model:Destroy()
		return
	end
	center /= #list
	playSound(ClanAssets.Sounds and ClanAssets.Sounds.BlackWall, center, 1)

	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local t = now - started
		if not model.Parent then
			connection:Disconnect()
			return
		end
		for index, segment in list do
			-- Brota del centro hacia los extremos y se apaga de los extremos al centro
			local riseAt = telegraph + segment.Spread * 0.15
			local fadeAt = telegraph + duration + (1 - segment.Spread) * 0.5
			if t < riseAt then
				continue
			end
			if not segment.Started then
				segment.Started = true
				for k, emitter in segment.Emitters do
					emitter.Rate = segment.Rates[k]
				end
				segment.Emitters[2]:Emit(8)
				segment.Emitters[3]:Emit(6)
				TweenService:Create(segment.Line, TweenInfo.new(rise * 2), { Transparency = 1 }):Play()
			end
			local grow = math.clamp((t - riseAt) / rise, 0, 1)
			grow = 1 - (1 - grow) ^ 2
			local fade = math.clamp((t - fadeAt) / 0.45, 0, 1)
			if fade > 0 and not segment.Ended then
				segment.Ended = true
				for _, emitter in segment.Emitters do
					emitter.Enabled = false
				end
			end
			local h = segment.Height * grow * (1 - 0.6 * fade)
			local transparency = if h < 0.3 then 1 else fade
			for k, layer in segment.Layers do
				-- La cortina sube (el fuego fluye) y la corona parpadea
				local flicker = 1 + 0.14 * math.noise(index * 0.37, k * 3.1, now * 2.2)
				local crown = crownHeight * flicker * math.clamp(grow * 1.5, 0, 1)
				local base = segment.Frame * layer.Local
				layer.Body.Size = Vector3.new(layer.Width, math.max(h, 0.1), 0.05)
				layer.Body.CFrame = base * CFrame.new(0, h / 2, 0)
				layer.Crown.Size = Vector3.new(layer.Width, math.max(crown, 0.1), 0.05)
				layer.Crown.CFrame = base * CFrame.new(0, h + crown / 2 - 3, 0.02)
				local scroll = layer.Phase + now * layer.Speed
				-- Flipbook: las lenguas se mueven (todos los tramos de la capa en el mismo cuadro)
				local frame = (math.floor(now * WALL_FPS + layer.FramePhase) % #WALL_CURTAIN_FRAMES) + 1
				local swap = frame ~= layer.Frame
				layer.Frame = frame
				for _, texture in layer.BodyTextures do
					texture.OffsetStudsV = scroll
					texture.Transparency = transparency
					if swap then
						texture.Texture = WALL_CURTAIN_FRAMES[frame]
					end
				end
				for _, texture in layer.CrownTextures do
					texture.StudsPerTileV = math.max(crown, 0.1)
					texture.Transparency = transparency
					if swap then
						texture.Texture = WALL_CROWN_FRAMES[frame]
					end
				end
			end
			segment.Detail.Size = Vector3.new(width, math.max(h * 0.8, 0.1), 3)
			segment.Detail.CFrame = segment.Frame * CFrame.new(0, h * 0.45, 0)
			segment.Tips.CFrame = segment.Frame * CFrame.new(0, h + crownHeight * 0.4, 0)
			for _, cap in segment.Caps do
				cap.Part.Size = Vector3.new(2.2, math.max(h, 0.1), thickness + 1.5)
				cap.Part.CFrame = segment.Frame * CFrame.new(cap.X, h / 2, 0)
			end
		end
		if t > telegraph + duration + 2.5 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- Alguien cruzó el muro: estallido de llamas negras hacia su lado
local function blackWallRepel(data: { [string]: any })
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	local normal = if typeof(data.Normal) == "Vector3" and data.Normal.Magnitude > 0.01 then data.Normal.Unit else Vector3.yAxis
	local holder = fxPoint(data.Position, 1.2)
	holder.Size = Vector3.one * 2
	holder.CFrame = CFrame.lookAt(data.Position, data.Position + normal)
	local burst = wallFlames(holder, 3, 1)
	burst.EmissionDirection = Enum.NormalId.Front
	burst.Speed = NumberRange.new(10, 24)
	burst.SpreadAngle = Vector2.new(50, 50)
	burst.Acceleration = Vector3.new(0, 4, 0)
	burst.Drag = 3
	burst:Emit(24)
	shakeNear(data.Position, 8, 0.2, 1.6)
end

-- Un proyectil entró en el muro: las llamas negras se lo comen
local function blackWallConsume(data: { [string]: any })
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	local direction = if typeof(data.Direction) == "Vector3" and data.Direction.Magnitude > 0.01 then data.Direction.Unit else Vector3.zAxis
	local holder = fxPoint(data.Position + direction * 0.8, 1)
	holder.Size = Vector3.one * 1.5
	local burst = wallFlames(holder, 2.4, 1.2)
	burst.Speed = NumberRange.new(2, 6)
	burst.SpreadAngle = Vector2.new(40, 40)
	burst:Emit(10)
end

-- Con el Susanoo, sin sellos: se carga con llamas negras en quien lo lanza
local function blackWallWindup(data: { [string]: any })
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local duration = numberOr(data.Duration, 0.6)
	local flames = flameEmitter(root, 55, 2.6)
	task.delay(duration, function()
		flames.Enabled = false
		task.wait(0.7)
		flames:Destroy()
	end)
end

-- Tsukuyomi: los demás ------------------------------------------------------------------------

local BIND_SEAL_SIZE = 6
local BIND_SEAL_DROP = 2.95
local BIND_TIMEOUT = 4

local function tsukuyomiBind(data: {[string]: any})
	local target = data.Target
	local root = rootOf(target)
	if not root then
		return
	end
	-- El Mangekyō en el suelo, girando despacio
	local seal = Instance.new("Part")
	seal.Name = "TsukuyomiSeal"
	seal.Anchored = true
	seal.CanCollide = false
	seal.CanQuery = false
	seal.CanTouch = false
	seal.Transparency = 1
	seal.Size = Vector3.new(BIND_SEAL_SIZE, 0.05, BIND_SEAL_SIZE)
	seal.CFrame = CFrame.new(root.Position - Vector3.new(0, BIND_SEAL_DROP, 0))
	seal.Parent = folder
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = irisFor(data.Type)
	decal.Transparency = 1
	decal.Parent = seal
	TweenService:Create(decal, TweenInfo.new(0.2), { Transparency = 0.25 }):Play()

	-- Aura roja y negra
	local aura = Instance.new("Highlight")
	aura.Name = "TsukuyomiAura"
	aura.Adornee = target
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.FillColor = Color3.fromRGB(20, 0, 2)
	aura.OutlineColor = Color3.fromRGB(255, 30, 40)
	aura.FillTransparency = 1
	aura.OutlineTransparency = 1
	aura.Parent = target
	TweenService:Create(aura, TweenInfo.new(0.2), { FillTransparency = 0.55, OutlineTransparency = 0.2 }):Play()

	-- Pose congelada mientras siga dentro
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local frozen: {[AnimationTrack]: number} = {}
	local function freeze()
		if not animator then
			return
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			if frozen[track] == nil then
				frozen[track] = track.Speed
				track:AdjustSpeed(0)
			end
		end
	end
	freeze()
	local started = os.clock()
	local angle = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local elapsed = os.clock() - started
		local held = target.Parent ~= nil and root.Parent ~= nil and elapsed < BIND_TIMEOUT
			and (elapsed < 0.25 or target:GetAttribute("InGenjutsu") == "Tsukuyomi")
		if held then
			angle -= dt * 25
			seal.CFrame = CFrame.new(root.Position - Vector3.new(0, BIND_SEAL_DROP, 0)) * CFrame.Angles(0, math.rad(angle), 0)
			freeze()
			return
		end
		connection:Disconnect()
		for track, speed in frozen do
			pcall(function()
				track:AdjustSpeed(speed)
			end)
		end
		TweenService:Create(decal, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		TweenService:Create(aura, TweenInfo.new(0.3), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		task.delay(0.35, function()
			seal:Destroy()
			aura:Destroy()
		end)
	end)
end

-- Tsukuyomi: la víctima -----------------------------------------------------------------------

local TSUKUYOMI_EXIT = 0.7

local screen = Instance.new("ScreenGui")
screen.Name = "TsukuyomiScreen"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 499
screen.Parent = localPlayer:WaitForChild("PlayerGui")

type Inside = { Id: any, Sky: Frame, Moon: ImageLabel, Iris: ImageLabel, Color: ColorCorrectionEffect }
local inside: Inside? = nil

local function stopTsukuyomi(id: any?)
	local current = inside
	if not current or (id ~= nil and current.Id ~= id) then
		return
	end
	inside = nil
	local info = TweenInfo.new(TSUKUYOMI_EXIT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(current.Sky, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(current.Moon, info, { ImageTransparency = 1 }):Play()
	TweenService:Create(current.Iris, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()
	TweenService:Create(current.Color, info, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	task.delay(TSUKUYOMI_EXIT + 0.05, function()
		current.Sky:Destroy()
		current.Moon:Destroy()
		current.Iris:Destroy()
		current.Color:Destroy()
	end)
end

local function startTsukuyomi(id: any, duration: number, kind: any)
	stopTsukuyomi(nil)
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local shortSide = math.min(viewport.X, viewport.Y)

	-- 1. El Mangekyō de quien te atrapó se abalanza hasta llenar la pantalla
	local iris = Instance.new("ImageLabel")
	iris.Name = "TsukuyomiIris"
	iris.BackgroundTransparency = 1
	iris.AnchorPoint = Vector2.new(0.5, 0.5)
	iris.Position = UDim2.fromScale(0.5, 0.5)
	iris.Size = UDim2.fromOffset(110, 110)
	iris.Image = irisFor(kind)
	iris.ImageTransparency = 0
	iris.ZIndex = 30
	iris.Parent = screen
	local grow = math.max(viewport.X, viewport.Y) * 1.8
	TweenService:Create(iris, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(grow, grow),
		Rotation = 90,
	}):Play()
	TweenService:Create(iris, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.3), {
		ImageTransparency = 1,
	}):Play()

	-- 2. Dentro: cielo rojo (más intenso arriba) y la luna negra
	local sky = Instance.new("Frame")
	sky.Name = "TsukuyomiSky"
	sky.BackgroundColor3 = TSUKUYOMI_RED
	sky.BackgroundTransparency = 1
	sky.BorderSizePixel = 0
	sky.Size = UDim2.fromScale(1, 1)
	sky.ZIndex = 20
	sky.Parent = screen
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({ key(0, 0), key(0.55, 0.45), key(1, 0.7) })
	gradient.Parent = sky
	TweenService:Create(sky, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.25), {
		BackgroundTransparency = 0.15,
	}):Play()

	local moon = Instance.new("ImageLabel")
	moon.Name = "TsukuyomiMoon"
	moon.BackgroundTransparency = 1
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	moon.Position = UDim2.fromScale(0.5, 0.2)
	moon.Size = UDim2.fromOffset(shortSide * 0.34, shortSide * 0.34)
	moon.Image = ClanAssets.TsukuyomiMoon or ""
	moon.ImageTransparency = 1
	moon.ZIndex = 21
	moon.Parent = screen
	TweenService:Create(moon, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3), {
		ImageTransparency = 0,
	}):Play()

	-- 3. El mundo, sin color y teñido de rojo, con contraste duro
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "TsukuyomiColor"
	color.Parent = Lighting
	TweenService:Create(color, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.25), {
		Saturation = -1,
		Contrast = 0.4,
		Brightness = -0.08,
		TintColor = Color3.fromRGB(255, 120, 120),
	}):Play()

	inside = { Id = id, Sky = sky, Moon = moon, Iris = iris, Color = color }
	-- Respaldo por si no llega el End
	task.delay(duration + 0.6, function()
		stopTsukuyomi(id)
	end)
end

task.spawn(function()
	local genjutsuRemote = remotes:WaitForChild("GenjutsuFX")
	genjutsuRemote.OnClientEvent:Connect(function(action: string, data: any)
		if typeof(data) ~= "table" then
			return
		end
		if action == "Start" and data.Kind == "Tsukuyomi" then
			local visual = if typeof(data.Visual) == "table" then data.Visual else {}
			startTsukuyomi(data.Id, if typeof(data.Duration) == "number" then data.Duration else 2, visual.Type)
		elseif action == "End" then
			stopTsukuyomi(data.Id)
		end
	end)
end)

localPlayer.CharacterAdded:Connect(function()
	stopTsukuyomi(nil)
end)

-- Entrada ------------------------------------------------------------------------------------

clanRemote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if action == "AmaterasuWindup" then
			amaterasuWindup(data)
		elseif action == "AmaterasuPuddle" then
			amaterasuPuddle(data)
		elseif action == "TsukuyomiBind" then
			tsukuyomiBind(data)
		elseif action == "YasakaForm" then
			yasakaForm(data)
		elseif action == "YasakaThrow" then
			yasakaThrow(data)
		elseif action == "YasakaPos" then
			yasakaPos(data)
		elseif action == "YasakaLost" then
			yasakaLost(data)
		elseif action == "YasakaImpact" then
			yasakaImpact(data)
		elseif action == "YasakaCancel" and typeof(data.Character) == "Instance" then
			dropMagatama(data.Character, true)
		elseif action == "BlackWallForm" then
			blackWallForm(data)
		elseif action == "BlackWallRepel" then
			blackWallRepel(data)
		elseif action == "BlackWallConsume" then
			blackWallConsume(data)
		elseif action == "BlackWallWindup" then
			blackWallWindup(data)
		elseif action == "GokaInhale" then
			gokaInhale(data)
		elseif action == "GokaBreathStart" then
			gokaBreathStart(data)
		elseif action == "GokaCells" then
			gokaCells(data)
		elseif action == "GokaBreathEnd" then
			gokaBreathEnd(data)
		elseif action == "GokaCancel" and typeof(data.Character) == "Instance" then
			gokaStopInhale(data.Character)
		elseif action == "EntonSpearForm" then
			spearForm(data)
		elseif action == "EntonSpearCancel" and typeof(data.Character) == "Instance" then
			dropHeld(data.Character)
		elseif action == "EntonSpear" then
			spearFlight(data)
		elseif action == "EntonSpearEnd" and typeof(data.Id) == "string" then
			endSpear(data.Id, if typeof(data.Position) == "Vector3" then data.Position else nil,
				if typeof(data.Kind) == "string" then data.Kind else nil)
		end
	end)
	if not ok then
		warn("[MangekyoClient] " .. tostring(action) .. ": " .. tostring(err))
	end
end)
