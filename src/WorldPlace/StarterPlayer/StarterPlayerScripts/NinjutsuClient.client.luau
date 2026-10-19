-- StarterPlayer > StarterPlayerScripts > NinjutsuClient  (LocalScript)
--
-- Dibuja los efectos del ninjutsu general que anuncia el servidor (TechniqueKit > Ninjutsu):
--   Shunshin              humo y hojas donde estabas y donde apareces
--   Nawanuke              cuerdas rotas que caen y humo
--   HengeStart / HengeEnd disfraz: esconde al transformado y muestra una copia del objetivo
--                         (o un tronco) que lo sigue. El transformado pide romperlo al atacar,
--                         lanzar o bloquear.
--   ShosenStart / End     brillo verde en quien recibe la curación y lazo desde las manos

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("NinjutsuFX")

local FOLDER_NAME = "NinjutsuFX"
local DEFAULT_RUN_ANIMATION = "rbxassetid://180426354"

local function getFolder(): Folder
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function newPart(size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function smokePuff(position: Vector3, count: number?)
	local holder = newPart(Vector3.one * 0.2, Color3.new())
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.LightInfluence = 0.3
	emitter.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(1, 4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	emitter:Emit(count or 18)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

-- Hojas que salen girando
local function leafBurst(position: Vector3, count: number)
	for _ = 1, count do
		local leaf = newPart(Vector3.new(0.35, 0.04, 0.55), Color3.fromRGB(80 + math.random(0, 40), 150 + math.random(0, 50), 60), Enum.Material.Grass)
		leaf.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		leaf.Parent = getFolder()
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit * (2 + math.random() * 3)
		local tween = TweenService:Create(leaf, TweenInfo.new(0.7 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + offset - Vector3.yAxis * 1.5) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			leaf:Destroy()
		end)
	end
end

-- Shunshin -----------------------------------------------------------------------------------

local function shunshin(data: {[string]: any})
	if typeof(data.From) == "Vector3" then
		smokePuff(data.From, 14)
		leafBurst(data.From, 10)
	end
	if typeof(data.To) == "Vector3" then
		smokePuff(data.To, 10)
		leafBurst(data.To, 6)
	end
end

-- Nawanuke -----------------------------------------------------------------------------------

local function nawanuke(data: {[string]: any})
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local origin = root.Position
	smokePuff(origin, 10)
	for i = 1, 5 do
		local rope = newPart(Vector3.new(0.12, 0.12, 1.2), Color3.fromRGB(150, 120, 80), Enum.Material.Fabric)
		rope.CFrame = CFrame.new(origin + Vector3.new(math.random() - 0.5, i * 0.35 - 1, math.random() - 0.5))
			* CFrame.Angles(math.random() * 3, math.random() * 3, 0)
		rope.Parent = getFolder()
		local tween = TweenService:Create(rope, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = rope.CFrame - Vector3.yAxis * 3,
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			rope:Destroy()
		end)
	end
end

-- Henge --------------------------------------------------------------------------------------

type Disguise = {
	Id: number,
	Model: Model,
	Kind: string,
	Track: AnimationTrack?,
	Connections: {RBXScriptConnection},
}

local disguises: {[Model]: Disguise} = {}

local function runAnimationId(character: Model): string
	local animate = character:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	local animation = run and run:FindFirstChildOfClass("Animation")
	if animation and animation.AnimationId ~= "" then
		return animation.AnimationId
	end
	return DEFAULT_RUN_ANIMATION
end

local function cloneAppearance(target: Model): Model?
	local archivable = target.Archivable
	target.Archivable = true
	local ok, clone = pcall(function()
		return target:Clone()
	end)
	target.Archivable = archivable
	if not ok or not clone then
		return nil
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript")
			or descendant:IsA("Constraint") or descendant:IsA("BodyMover") or descendant:IsA("ForceField")
			or descendant:IsA("Sound") or descendant:IsA("Highlight") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		elseif descendant:IsA("BillboardGui") then
			-- La placa copiada apunta a la cabeza real: se reapunta a la del disfraz
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") then
				descendant.Adornee = parent
				descendant.Enabled = true
			end
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart")
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		clone:Destroy()
		return nil
	end
	root.Anchored = true
	root.Transparency = 1
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	return clone
end

local function buildLog(): Model
	local model = Instance.new("Model")
	model.Name = "HengeLog"
	local log = newPart(Vector3.new(3.4, 1.7, 1.7), Color3.fromRGB(115, 80, 50), Enum.Material.Wood)
	log.Shape = Enum.PartType.Cylinder
	log.Parent = model
	local top = newPart(Vector3.new(0.05, 1.5, 1.5), Color3.fromRGB(190, 150, 100), Enum.Material.Wood)
	top.Shape = Enum.PartType.Cylinder
	top.CFrame = CFrame.new(1.71, 0, 0)
	top.Parent = model
	model.PrimaryPart = log
	return model
end

local function setHidden(character: Model, hidden: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function endDisguise(character: Model)
	local disguise = disguises[character]
	if not disguise then
		return
	end
	disguises[character] = nil
	for _, connection in disguise.Connections do
		connection:Disconnect()
	end
	local root = rootOf(character)
	if root then
		smokePuff(root.Position, 16)
	end
	disguise.Model:Destroy()
	if character.Parent then
		setHidden(character, false)
	end
end

local BREAK_ATTRIBUTES = { "IsAttacking", "IsThrowingProjectile", "IsBlocking" }

local function hengeStart(data: {[string]: any})
	local character = data.Character
	local root = rootOf(character)
	if not character or not root then
		return
	end
	endDisguise(character)

	local model: Model?
	local kind = "Log"
	if data.Target and data.Target.Parent then
		model = cloneAppearance(data.Target)
		kind = "Copy"
	end
	if not model then
		model = buildLog()
		kind = "Log"
	end
	model.Parent = getFolder()
	smokePuff(root.Position, 18)

	local disguise: Disguise = { Id = data.Id, Model = model, Kind = kind, Track = nil, Connections = {} }
	disguises[character] = disguise

	if kind == "Copy" then
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = runAnimationId(data.Target)
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			disguise.Track = track
		end
	end

	-- Seguir al transformado y mantenerlo escondido
	-- (con el Byakugan del clan Hyūga se ve el cuerpo real y el disfraz semitransparente)
	local revealedLast: boolean? = nil
	table.insert(disguise.Connections, RunService.RenderStepped:Connect(function()
		if not character.Parent or not root.Parent then
			endDisguise(character)
			return
		end
		local viewer = localPlayer.Character
		local revealed = viewer ~= nil and viewer ~= character and viewer:GetAttribute("ByakuganActive") == true
		setHidden(character, not revealed)
		if revealed ~= revealedLast then
			revealedLast = revealed
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") or descendant:IsA("Decal") then
					descendant.LocalTransparencyModifier = if revealed then 0.7 else 0
				end
			end
		end
		if kind == "Copy" then
			model:PivotTo(root.CFrame)
			local velocity = root.AssemblyLinearVelocity
			local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2
			local track = disguise.Track
			if track then
				if moving and not track.IsPlaying then
					track:Play(0.15)
				elseif not moving and track.IsPlaying then
					track:Stop(0.2)
				end
			end
		else
			-- Tronco de pie, apoyado en el suelo
			model:PivotTo(CFrame.new(root.Position - Vector3.yAxis * 1.3) * CFrame.Angles(0, 0, math.pi / 2))
		end
	end))

	-- El transformado rompe el disfraz al atacar, lanzar o bloquear
	if character == localPlayer.Character then
		for _, name in BREAK_ATTRIBUTES do
			table.insert(disguise.Connections, character:GetAttributeChangedSignal(name):Connect(function()
				if character:GetAttribute(name) == true then
					remote:FireServer("HengeBreak")
				end
			end))
		end
	end
end

-- Shōsen -------------------------------------------------------------------------------------

local heals: {[number]: {Instance}} = {}

local function shosenStart(data: {[string]: any})
	local caster, target = data.Caster, data.Target
	local targetTorso = target and (target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso"))
	if not targetTorso then
		return
	end
	local created = {}
	local glowColor = Color3.fromRGB(120, 255, 150)

	local light = Instance.new("PointLight")
	light.Color = glowColor
	light.Range = 8
	light.Brightness = 2
	light.Parent = targetTorso
	table.insert(created, light)

	local attachment = Instance.new("Attachment")
	attachment.Parent = targetTorso
	table.insert(created, attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 20
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(glowColor)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = attachment

	-- Lazo verde desde la mano del que cura (si cura a otro)
	if caster and caster ~= target then
		local hand = caster:FindFirstChild("RightHand") or caster:FindFirstChild("Right Arm")
		if hand and hand:IsA("BasePart") then
			local handAttachment = Instance.new("Attachment")
			handAttachment.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
			handAttachment.Parent = hand
			table.insert(created, handAttachment)
			local beam = Instance.new("Beam")
			beam.Attachment0 = handAttachment
			beam.Attachment1 = attachment
			beam.Width0 = 0.3
			beam.Width1 = 0.6
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(glowColor)
			beam.Transparency = NumberSequence.new(0.4)
			beam.Parent = handAttachment
		end
	end

	heals[data.Id] = created
	task.delay((data.Duration or 3) + 0.5, function()
		local entry = heals[data.Id]
		if entry == created then
			heals[data.Id] = nil
			for _, instance in created do
				instance:Destroy()
			end
		end
	end)
end

local function shosenEnd(data: {[string]: any})
	local created = heals[data.Id]
	if not created then
		return
	end
	heals[data.Id] = nil
	for _, instance in created do
		instance:Destroy()
	end
end

-- Entrada ------------------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if action == "Shunshin" then
			shunshin(data)
		elseif action == "Nawanuke" then
			nawanuke(data)
		elseif action == "HengeStart" then
			hengeStart(data)
		elseif action == "HengeEnd" and data.Character then
			local disguise = disguises[data.Character]
			if disguise and disguise.Id == data.Id then
				endDisguise(data.Character)
			end
		elseif action == "ShosenStart" then
			shosenStart(data)
		elseif action == "ShosenEnd" then
			shosenEnd(data)
		end
	end)
	if not ok then
		warn("[NinjutsuClient] " .. tostring(action) .. ": " .. tostring(err))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		endDisguise(player.Character)
	end
end)
