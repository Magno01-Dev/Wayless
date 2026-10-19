-- StarterPlayer > StarterPlayerScripts > KenjutsuClient  (LocalScript)
--
-- Dibuja los efectos de kenjutsu que anuncia el servidor (TechniqueKit > Kenjutsu):
--   Iai             corte horizontal rápido (dorado y más grande si fue contraataque)
--   Tsuki           estocada recta
--   KesagiriWindup  el arma brilla antes del corte pesado (aviso)
--   Kesagiri        corte diagonal grande
--   ChakraFlow      el arma brilla con el color del elemento mientras dure
--   ChakraFlowEnd   se apaga
-- El daño, el bloqueo y los VFX de impacto normales los hace CombatServer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local remote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("KenjutsuFX")

local FOLDER_NAME = "KenjutsuFX"

local ELEMENT_COLORS: {[string]: Color3} = {
	Fire = Color3.fromRGB(255, 120, 40),
	Wind = Color3.fromRGB(170, 240, 190),
	Lightning = Color3.fromRGB(150, 200, 255),
	Earth = Color3.fromRGB(170, 120, 70),
	Water = Color3.fromRGB(70, 150, 255),
}

local function getFolder(): Folder
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function newPart(size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
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

local function bladeOf(character: Model?): Instance?
	local visuals = character and character:FindFirstChild("WAYLESS_EquipmentVisuals")
	local weapon = visuals and visuals:FindFirstChild("WeaponVisual")
	return weapon and weapon:FindFirstChild("BladeAssembly")
end

--[[
	Media luna de corte: segmentos finos en arco alrededor de `center`, en el plano definido
	por `forward` y `up`, de `fromAngle` a `toAngle` (grados, 0 = forward).
]]
local function slashArc(center: Vector3, forward: Vector3, up: Vector3, radius: number,
	fromAngle: number, toAngle: number, color: Color3, thickness: number, duration: number)
	local right = forward:Cross(up).Unit
	local segments = 14
	local previous: Vector3? = nil
	for i = 0, segments do
		local alpha = i / segments
		local angle = math.rad(fromAngle + (toAngle - fromAngle) * alpha)
		local point = center + (forward * math.cos(angle) + right * math.sin(angle)) * radius
		if previous then
			local length = (point - previous).Magnitude
			-- Más grueso en el centro del arco, fino en las puntas
			local width = thickness * math.sin(alpha * math.pi) + 0.03
			local part = newPart(Vector3.new(width, width * 0.4, length + 0.05), color)
			part.CFrame = CFrame.lookAt((point + previous) / 2, point, up)
			part.Transparency = 0.05
			part.Parent = getFolder()
			local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = Vector3.new(0.02, 0.02, length * 1.2),
			})
			tween:Play()
			tween.Completed:Once(function()
				part:Destroy()
			end)
		end
		previous = point
	end
end

-- Iai ----------------------------------------------------------------------------------------

local function iai(data: {[string]: any})
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local forward: Vector3 = data.Direction or root.CFrame.LookVector
	local counter = data.Counter == true
	local color = if counter then Color3.fromRGB(255, 215, 120) else Color3.fromRGB(235, 245, 255)
	local radius = (data.Range or 11) * 0.75
	slashArc(root.Position + Vector3.yAxis * 0.4, forward, Vector3.yAxis, radius, -35, 35,
		color, if counter then 0.5 else 0.3, if counter then 0.35 else 0.22)
	if counter then
		-- Destello del contraataque
		local flash = newPart(Vector3.one * 1, color)
		flash.Shape = Enum.PartType.Ball
		flash.CFrame = CFrame.new(root.Position + forward * 3)
		flash.Parent = getFolder()
		local tween = TweenService:Create(flash, TweenInfo.new(0.25), { Size = Vector3.one * 7, Transparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			flash:Destroy()
		end)
	end
end

-- Tsuki --------------------------------------------------------------------------------------

local function tsuki(data: {[string]: any})
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local forward: Vector3 = data.Direction or root.CFrame.LookVector
	local range = data.Range or 12
	local start = root.Position + Vector3.yAxis * 0.4 + forward * 1.5
	local line = newPart(Vector3.new(0.25, 0.25, 1), Color3.fromRGB(235, 245, 255))
	line.CFrame = CFrame.lookAt(start + forward * 0.5, start + forward)
	line.Parent = getFolder()
	local tween = TweenService:Create(line, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 0.05, range),
		CFrame = CFrame.lookAt(start + forward * (range / 2), start + forward * range),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		line:Destroy()
	end)
	-- Anillo en la punta
	local ring = newPart(Vector3.new(0.1, 1, 1), Color3.fromRGB(235, 245, 255))
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.lookAt(start + forward * range * 0.6, start + forward * range) * CFrame.Angles(0, math.pi / 2, 0)
	ring.Transparency = 0.3
	ring.Parent = getFolder()
	local ringTween = TweenService:Create(ring, TweenInfo.new(0.22), { Size = Vector3.new(0.05, 4, 4), Transparency = 1 })
	ringTween:Play()
	ringTween.Completed:Once(function()
		ring:Destroy()
	end)
end

-- Kesagiri -----------------------------------------------------------------------------------

local function glint(data: {[string]: any})
	local blade = bladeOf(data.Character)
	local part = blade and (if blade:IsA("BasePart") then blade else blade:FindFirstChildWhichIsA("BasePart", true))
	if not part then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Range = 8
	light.Brightness = 0
	light.Parent = part
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = Color3.fromRGB(255, 240, 200)
	sparkle.Parent = part
	TweenService:Create(light, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Brightness = 5 }):Play()
	task.delay(data.Duration or 0.6, function()
		light:Destroy()
		sparkle:Destroy()
	end)
end

local function kesagiri(data: {[string]: any})
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local forward: Vector3 = data.Direction or root.CFrame.LookVector
	-- Plano diagonal: inclinado 40° sobre el eje de avance
	local right = forward:Cross(Vector3.yAxis).Unit
	local up = CFrame.fromAxisAngle(forward, math.rad(40)):VectorToWorldSpace(right):Cross(forward).Unit
	slashArc(root.Position + Vector3.yAxis * 0.6, forward, up, (data.Range or 8) * 0.8, -60, 60,
		Color3.fromRGB(255, 235, 215), 0.7, 0.35)
end

-- Chakura Nagashi ------------------------------------------------------------------------------

local flows: {[Model]: {Highlight: Highlight, Lights: {Instance}, Until: number}} = {}

local function stopFlow(character: Model)
	local flow = flows[character]
	if not flow then
		return
	end
	flows[character] = nil
	flow.Highlight:Destroy()
	for _, instance in flow.Lights do
		instance:Destroy()
	end
end

local function chakraFlow(data: {[string]: any})
	local character = data.Character
	local blade = bladeOf(character)
	if not character or not blade then
		return
	end
	stopFlow(character)
	local color = ELEMENT_COLORS[data.Element] or Color3.fromRGB(150, 200, 255)

	local highlight = Instance.new("Highlight")
	highlight.Name = "ChakuraNagashiGlow"
	highlight.FillColor = color
	highlight.FillTransparency = 0.35
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = blade
	highlight.Parent = getFolder()

	local lights = {}
	local part = if blade:IsA("BasePart") then blade else blade:FindFirstChildWhichIsA("BasePart", true)
	if part then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 7
		light.Brightness = 2
		light.Parent = part
		table.insert(lights, light)

		local attachment = Instance.new("Attachment")
		attachment.Parent = part
		table.insert(lights, attachment)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 25
		emitter.Lifetime = NumberRange.new(0.25, 0.45)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Color = ColorSequence.new(color)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new(0.2)
		emitter.Parent = attachment
	end

	local entry = { Highlight = highlight, Lights = lights, Until = data.Until or 0 }
	flows[character] = entry
	local remaining = (data.Until or 0) - Workspace:GetServerTimeNow()
	task.delay(math.max(remaining, 0) + 0.2, function()
		if flows[character] == entry then
			stopFlow(character)
		end
	end)
end

-- Entrada ------------------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if action == "Iai" then
			iai(data)
		elseif action == "Tsuki" then
			tsuki(data)
		elseif action == "KesagiriWindup" then
			glint(data)
		elseif action == "Kesagiri" then
			kesagiri(data)
		elseif action == "ChakraFlow" then
			chakraFlow(data)
		elseif action == "ChakraFlowEnd" and data.Character then
			stopFlow(data.Character)
		end
	end)
	if not ok then
		warn("[KenjutsuClient] " .. tostring(action) .. ": " .. tostring(err))
	end
end)

-- Personajes que se van: limpiar brillos
Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		stopFlow(player.Character)
	end
end)
