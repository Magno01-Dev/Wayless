-- StarterPlayer > StarterPlayerScripts > GenjutsuClient  (LocalScript)
--
-- Dibuja los efectos de genjutsu que anuncia el servidor (TechniqueKit > Genjutsu):
--   Start / End   (solo el afectado) visión distorsionada de Narakumi; al romperse, destello
--   Fail          (solo el que lanzó) aviso de por qué falló
--   Success       (solo el que lanzó) aviso de que entró
--   Kai           (todos) pulso alrededor de quien usó Kai
--   Hidden        (todos) Kori Shinchū: el que lo usa se ve semitransparente a sí mismo
--   Clones        (todos) clones ilusorios que corren y se deshacen en humo al tocarlos

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("GenjutsuFX")

local FOLDER_NAME = "GenjutsuIllusions"
local DEFAULT_RUN_ANIMATION = "rbxassetid://180426354" -- correr R6 por defecto de Roblox

local function getFolder(): Folder
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function newPart(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Pantalla ------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "GenjutsuOverlay"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 65
gui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Viñeta: 4 bordes oscuros con degradado
local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.Visible = false
vignette.Parent = gui

local function edge(rotation: number, size: UDim2, position: UDim2, anchor: Vector2)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(25, 0, 10)
	frame.BorderSizePixel = 0
	frame.Parent = vignette
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
end
edge(90, UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
edge(-90, UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1))
edge(0, UDim2.fromScale(0.25, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
edge(180, UDim2.fromScale(0.25, 1), UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5))

local releaseFlash = Instance.new("TextLabel")
releaseFlash.AnchorPoint = Vector2.new(0.5, 0.5)
releaseFlash.Position = UDim2.fromScale(0.5, 0.45)
releaseFlash.Size = UDim2.fromOffset(200, 200)
releaseFlash.BackgroundTransparency = 1
releaseFlash.Font = Enum.Font.GothamBold
releaseFlash.TextScaled = true
releaseFlash.TextColor3 = Color3.fromRGB(255, 255, 255)
releaseFlash.TextStrokeTransparency = 0.3
releaseFlash.TextTransparency = 1
releaseFlash.Text = "解"
releaseFlash.Parent = gui

local notice = Instance.new("TextLabel")
notice.AnchorPoint = Vector2.new(0.5, 0)
notice.Position = UDim2.new(0.5, 0, 0.5, 46)
notice.Size = UDim2.fromOffset(320, 24)
notice.BackgroundTransparency = 1
notice.Font = Enum.Font.GothamBold
notice.TextSize = 15
notice.TextStrokeTransparency = 0.4
notice.TextTransparency = 1
notice.Parent = gui

local function showNotice(text: string, color: Color3)
	notice.Text = text
	notice.TextColor3 = color
	notice.TextTransparency = 0
	TweenService:Create(notice, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9), {
		TextTransparency = 1,
	}):Play()
end

-- Narakumi: visión de miedo -------------------------------------------------------------------

local fear = nil -- { Id, EndsAt, Color, Blur }

local function stopFear(reason: string?)
	if not fear then
		return
	end
	local current = fear
	fear = nil
	vignette.Visible = false
	TweenService:Create(current.Color, TweenInfo.new(0.3), {
		Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1), Brightness = 0,
	}):Play()
	TweenService:Create(current.Blur, TweenInfo.new(0.3), { Size = 0 }):Play()
	task.delay(0.35, function()
		current.Color:Destroy()
		current.Blur:Destroy()
	end)
	if reason == "Kai" or reason == "Damage" then
		-- Se rompe la ilusión
		releaseFlash.TextTransparency = 0
		releaseFlash.Size = UDim2.fromOffset(120, 120)
		TweenService:Create(releaseFlash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			Size = UDim2.fromOffset(260, 260),
		}):Play()
	end
end

local function startFear(id: number, duration: number)
	stopFear(nil)
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "GenjutsuFear"
	color.Parent = Lighting
	local blur = Instance.new("BlurEffect")
	blur.Name = "GenjutsuFearBlur"
	blur.Size = 0
	blur.Parent = Lighting
	TweenService:Create(color, TweenInfo.new(0.35), {
		Saturation = -0.75,
		Contrast = 0.3,
		Brightness = -0.06,
		TintColor = Color3.fromRGB(255, 175, 190),
	}):Play()
	TweenService:Create(blur, TweenInfo.new(0.35), { Size = 7 }):Play()
	vignette.Visible = true
	fear = { Id = id, EndsAt = os.clock() + duration, Color = color, Blur = blur, StartedAt = os.clock() }
end

-- Balanceo de cámara mientras dura el miedo (después de la cámara normal)
RunService:BindToRenderStep("GenjutsuFearSway", Enum.RenderPriority.Camera.Value + 2, function()
	if not fear then
		return
	end
	if os.clock() >= fear.EndsAt + 0.5 then
		stopFear(nil) -- respaldo por si no llegó el End
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local t = os.clock() - fear.StartedAt
	local ramp = math.clamp(t / 0.4, 0, 1)
	camera.CFrame = camera.CFrame * CFrame.Angles(
		math.rad(math.sin(t * 2.3) * 1.6 * ramp),
		math.rad(math.sin(t * 1.7) * 2.2 * ramp),
		math.rad(math.sin(t * 1.1) * 4 * ramp)
	)
	-- La tinta late
	fear.Color.TintColor = Color3.fromRGB(255, 165 + math.sin(t * 6) * 20, 180 + math.sin(t * 6) * 15)
end)

localPlayer.CharacterAdded:Connect(function()
	stopFear(nil)
end)

-- Kai: pulso ---------------------------------------------------------------------------------

local function kaiPulse(character: Model?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local ring = newPart(Vector3.new(0.1, 2, 2), Color3.fromRGB(190, 220, 255), Enum.PartType.Cylinder)
	ring.CFrame = CFrame.new(root.Position - Vector3.yAxis * 2.6) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Transparency = 0.2
	ring.Parent = getFolder()
	local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 14, 14),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		ring:Destroy()
	end)
end

-- Kori Shinchū: el que lo usa se ve semitransparente (solo en su pantalla) -------------------

local hiddenUntil = 0

local function hidden(character: Model?, duration: number)
	if character ~= localPlayer.Character then
		return
	end
	hiddenUntil = os.clock() + duration
	showNotice("OCULTO EN LA ILUSIÓN", Color3.fromRGB(190, 220, 255))
end

RunService.RenderStepped:Connect(function()
	local character = localPlayer.Character
	if not character or hiddenUntil == 0 then
		return
	end
	local active = os.clock() < hiddenUntil
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.LocalTransparencyModifier = if active then math.max(part.LocalTransparencyModifier, 0.45) else 0
		end
	end
	if not active then
		hiddenUntil = 0
	end
end)

-- Clones ilusorios ---------------------------------------------------------------------------

local function poof(position: Vector3)
	local holder = newPart(Vector3.one * 0.2, Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.LightInfluence = 0.3
	emitter.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240), Color3.fromRGB(180, 180, 180))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(1, 4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	emitter:Emit(20)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

local function runAnimationId(character: Model): string
	local animate = character:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	local animation = run and run:FindFirstChildOfClass("Animation")
	if animation and animation.AnimationId ~= "" then
		return animation.AnimationId
	end
	return DEFAULT_RUN_ANIMATION
end

local function buildClone(character: Model): Model?
	local archivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not ok or not clone then
		return nil
	end

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript")
			or descendant:IsA("Constraint") or descendant:IsA("BodyMover") or descendant:IsA("ForceField")
			or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		elseif descendant:IsA("BillboardGui") then
			-- Las placas copiadas apuntan a la cabeza real: se reapuntan a la del clon
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") then
				descendant.Adornee = parent
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
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	clone.Name = character.Name
	clone.Parent = getFolder()
	return clone
end

local function groundHeight(position: Vector3, ignore: {Instance}): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = table.clone(ignore)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(position + Vector3.yAxis * 4, Vector3.yAxis * -12, params)
	return if result then result.Position.Y else nil
end

local function spawnClones(data: {[string]: any})
	local character = data.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local random = Random.new(data.Seed or 1)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local casterGround = groundHeight(root.Position, { getFolder() })
	local hipOffset = if casterGround then root.Position.Y - casterGround else 3
	local animationId = runAnimationId(character)
	local count = data.Count or 2

	for i = 1, count do
		local clone = buildClone(character)
		if not clone then
			continue
		end
		local cloneRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart
		local humanoid = clone:FindFirstChildOfClass("Humanoid") :: Humanoid
		local side = if i % 2 == 1 then 1 else -1
		local angle = math.rad(side * random:NextNumber(25, 45))
		local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(look)
		local position = root.Position + direction:Cross(Vector3.yAxis) * (-side * 1.5)
		cloneRoot.CFrame = CFrame.lookAt(position, position + direction)

		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local okTrack, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if okTrack and track then
			track.Looped = true
			track:Play(0.1)
		end
		poof(position)

		local endsAt = os.clock() + (data.Duration or 4)
		local speed = data.Speed or 20
		local connection: RBXScriptConnection? = nil
		local function finish()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if clone.Parent then
				poof(cloneRoot.Position)
				clone:Destroy()
			end
		end
		connection = RunService.Heartbeat:Connect(function(dt)
			if not clone.Parent or os.clock() >= endsAt then
				finish()
				return
			end
			-- Alguien lo toca (que no sea su dueño): se deshace
			for _, player in Players:GetPlayers() do
				local other = player.Character
				local otherRoot = other and other ~= character and other:FindFirstChild("HumanoidRootPart")
				if otherRoot and (otherRoot.Position - cloneRoot.Position).Magnitude < 3 then
					finish()
					return
				end
			end
			-- Pared delante: gira
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { getFolder(), character }
			local wall = Workspace:Raycast(position, direction * 2.5, params)
			if wall and wall.Instance.CanCollide then
				direction = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-side * 90)):VectorToWorldSpace(direction)
			end
			position += direction * speed * dt
			local ground = groundHeight(position, { getFolder() })
			if ground then
				position = Vector3.new(position.X, ground + hipOffset, position.Z)
			end
			cloneRoot.CFrame = CFrame.lookAt(position, position + direction)
		end)
	end
end

-- Entrada ------------------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	if action == "Start" then
		if data.Kind == "Narakumi" then
			startFear(data.Id, data.Duration or 3)
		end
	elseif action == "End" then
		if fear and fear.Id == data.Id then
			stopFear(data.Reason)
		end
	elseif action == "Fail" then
		local text = if data.Reason == "NotInView" then "GENJUTSU FALLÓ · NO TE ESTABA MIRANDO"
			elseif data.Reason == "Blocked" then "GENJUTSU FALLÓ · ALGO TAPA LA VISTA"
			else "GENJUTSU FALLÓ · SIN OBJETIVO"
		showNotice(text, Color3.fromRGB(255, 120, 110))
	elseif action == "Success" then
		showNotice("GENJUTSU", Color3.fromRGB(220, 170, 255))
	elseif action == "Kai" then
		kaiPulse(data.Character)
	elseif action == "Hidden" then
		hidden(data.Character, data.Duration or 4)
	elseif action == "Clones" then
		local ok, err = pcall(spawnClones, data)
		if not ok then
			warn("[GenjutsuClient] Clones: " .. tostring(err))
		end
	end
end)
