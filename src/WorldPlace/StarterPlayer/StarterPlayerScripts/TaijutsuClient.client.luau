-- StarterPlayer > StarterPlayerScripts > TaijutsuClient  (LocalScript)
--
-- Dibuja los efectos de taijutsu que anuncia el servidor (TechniqueKit > Taijutsu):
--   DynamicEntry  estela y líneas de viento durante la patada voladora
--   Senpu         torbellino alrededor del que gira
--   Reppu         polvo en arco a ras de suelo
--   Stance        aura de la postura de contraataque (+ animación de guardia del dueño)
--   Counter       humo donde estaba y donde aparece
--   StanceWhiff   (solo el dueño) aviso de que quedó expuesto
--   Impact        onda de golpe fuerte
-- El daño, el bloqueo y los VFX de impacto normales los hace CombatServer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("TaijutsuFX")

-- Animación de guardia (BlockController) para la postura
local STANCE_ANIMATION_ID = "rbxassetid://102348484921328"

local FOLDER_NAME = "TaijutsuFX"

local function getFolder(): Folder
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function newPart(size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Neon
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

local function tweenThenDestroy(instance: Instance, duration: number, goal: {[string]: any})
	local tween = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	tween.Completed:Once(function()
		instance:Destroy()
	end)
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function groundBelow(position: Vector3, ignore: {Instance}): (Vector3?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = table.clone(ignore)
	table.insert(exclude, getFolder())
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(position + Vector3.yAxis * 2, Vector3.yAxis * -10, params)
	if result then
		return result.Position, result.Normal
	end
	return nil, nil
end

local function dust(position: Vector3, count: number, size: number, speed: number)
	local holder = newPart(Vector3.one * 0.2, Color3.new(), nil)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Drag = 4
	emitter.LightInfluence = 0.6
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 175, 150))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.5),
		NumberSequenceKeypoint.new(1, size),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

local function smokePuff(position: Vector3)
	local holder = newPart(Vector3.one * 0.2, Color3.new(), nil)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = getFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.LightInfluence = 0.3
	emitter.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3.5),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	emitter:Emit(16)
	task.delay(1, function()
		holder:Destroy()
	end)
end

-- Dynamic Entry ------------------------------------------------------------------------------

local function dynamicEntry(data: {[string]: any})
	local character = data.Character
	local root = rootOf(character)
	if not root then
		return
	end
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1.2, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -1.2, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.25
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = root

	local ground = groundBelow(root.Position, { character })
	if ground then
		dust(ground, 10, 2.5, 10)
	end
	task.delay((data.Duration or 0.3) + 0.3, function()
		trail.Enabled = false
		task.delay(0.3, function()
			trail:Destroy()
			top:Destroy()
			bottom:Destroy()
		end)
	end)
end

-- Konoha Senpū -------------------------------------------------------------------------------

local function senpu(data: {[string]: any})
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local radius = data.Radius or 8
	for i = 0, 1 do
		task.delay(i * 0.2, function()
			if not root.Parent then
				return
			end
			-- Anillo horizontal que se abre girando
			local ring = newPart(Vector3.new(0.15, 2, 2), Color3.fromRGB(230, 240, 255), Enum.Material.ForceField, Enum.PartType.Cylinder)
			ring.CFrame = CFrame.new(root.Position + Vector3.yAxis * (i == 0 and -0.5 or 0.6)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Transparency = 0.1
			ring.Parent = getFolder()
			tweenThenDestroy(ring, 0.3, {
				Size = Vector3.new(0.05, radius * 2, radius * 2),
				Transparency = 1,
				CFrame = ring.CFrame * CFrame.Angles(math.pi, 0, 0),
			})
		end)
	end
	local ground = groundBelow(root.Position, { data.Character })
	if ground then
		dust(ground, 14, 3, 14)
	end
end

-- Konoha Reppū -------------------------------------------------------------------------------

local function reppu(data: {[string]: any})
	local root = rootOf(data.Character)
	local direction: Vector3 = data.Direction or (root and root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	if not root then
		return
	end
	local range = data.Range or 9
	-- Polvo en abanico a ras de suelo
	for i = -3, 3 do
		local angle = math.rad(i * 20)
		local offset = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction) * (range * 0.6)
		local ground = groundBelow(root.Position + offset, { data.Character })
		if ground then
			task.delay((i + 3) * 0.02, function()
				dust(ground, 5, 2.2, 8)
			end)
		end
	end
	-- Media luna baja
	local arc = newPart(Vector3.new(0.1, 0.6, range * 1.6), Color3.fromRGB(240, 235, 220), Enum.Material.ForceField)
	local ground = groundBelow(root.Position, { data.Character })
	local base = if ground then ground + Vector3.yAxis * 0.4 else root.Position - Vector3.yAxis * 2.6
	arc.CFrame = CFrame.lookAt(base + direction * (range * 0.5), base + direction * range) * CFrame.Angles(0, math.pi / 2, 0)
	arc.Transparency = 0.3
	arc.Parent = getFolder()
	tweenThenDestroy(arc, 0.25, { Transparency = 1, Size = Vector3.new(0.05, 0.2, range * 2) })
end

-- Postura de contraataque --------------------------------------------------------------------

local function stance(data: {[string]: any})
	local character = data.Character
	local root = rootOf(character)
	if not root then
		return
	end
	local duration = data.Duration or 0.5
	local aura = newPart(Vector3.one * 6, Color3.fromRGB(150, 220, 160), Enum.Material.ForceField, Enum.PartType.Ball)
	aura.CFrame = root.CFrame
	aura.Transparency = 0.2
	aura.Parent = getFolder()
	local weld = Instance.new("WeldConstraint")
	aura.Anchored = false
	aura.Massless = true
	weld.Part0 = aura
	weld.Part1 = root
	weld.Parent = aura
	task.delay(duration, function()
		tweenThenDestroy(aura, 0.15, { Transparency = 1 })
	end)

	-- El dueño reproduce la guardia (las animaciones del propio personaje se replican solas)
	if character == localPlayer.Character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = STANCE_ANIMATION_ID
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.05)
				task.delay(duration, function()
					track:Stop(0.1)
				end)
			end
		end
	end
end

local notice = Instance.new("TextLabel")
notice.AnchorPoint = Vector2.new(0.5, 0)
notice.Position = UDim2.new(0.5, 0, 0.5, 46)
notice.Size = UDim2.fromOffset(320, 24)
notice.BackgroundTransparency = 1
notice.Font = Enum.Font.GothamBold
notice.TextSize = 15
notice.TextStrokeTransparency = 0.4
notice.TextTransparency = 1
notice.TextColor3 = Color3.fromRGB(255, 150, 120)
local noticeGui = Instance.new("ScreenGui")
noticeGui.Name = "TaijutsuNotice"
noticeGui.IgnoreGuiInset = true
noticeGui.ResetOnSpawn = false
noticeGui.Parent = localPlayer:WaitForChild("PlayerGui")
notice.Parent = noticeGui

local function showNotice(text: string)
	notice.Text = text
	notice.TextTransparency = 0
	TweenService:Create(notice, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), {
		TextTransparency = 1,
	}):Play()
end

-- Entrada ------------------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if action == "DynamicEntry" then
			dynamicEntry(data)
		elseif action == "Senpu" then
			senpu(data)
		elseif action == "Reppu" then
			reppu(data)
		elseif action == "Stance" then
			stance(data)
		elseif action == "Counter" then
			if typeof(data.From) == "Vector3" then
				smokePuff(data.From)
			end
			if typeof(data.To) == "Vector3" then
				smokePuff(data.To)
			end
		elseif action == "StanceWhiff" then
			showNotice("EXPUESTO")
		elseif action == "Impact" and typeof(data.Position) == "Vector3" then
			local ring = newPart(Vector3.new(0.1, 2, 2), Color3.fromRGB(255, 245, 225), Enum.Material.Neon, Enum.PartType.Cylinder)
			ring.CFrame = CFrame.new(data.Position) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Transparency = 0.2
			ring.Parent = getFolder()
			tweenThenDestroy(ring, 0.25, { Size = Vector3.new(0.05, 10, 10), Transparency = 1 })
		end
	end)
	if not ok then
		warn("[TaijutsuClient] " .. tostring(action) .. ": " .. tostring(err))
	end
end)
