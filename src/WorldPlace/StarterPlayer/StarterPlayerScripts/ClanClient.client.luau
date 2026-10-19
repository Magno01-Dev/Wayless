-- StarterPlayer > StarterPlayerScripts > ClanClient  (LocalScript)
--
-- Dibuja las mecánicas de clan (TechniqueKit > Clan, etapa 1):
--   Ojos           Sharingan (rojo) y Byakugan (blanco) se ven en la cara de quien los activa
--   Sharingan      (si TÚ lo tienes activo) sobre la cabeza de los demás ves qué jutsu preparan
--   Byakugan       (si TÚ lo tienes activo) ves a todos a ≤ 45 studs a través de paredes y los
--                  clones ilusorios marcados como FALSO (humo, Henge y minas: en sus scripts)
--   Marcas         sobre quien las tenga: sellos Uzumaki (封 ×N) y tenketsu Hyūga (●○○○○)
--   Kagemane       la sombra que corre por el suelo, la captura y el hilo de sombra
--   SealBurst      sello Uzumaki detonado · TenketsuSealed: tenketsu sellados
--   Notice         avisos al jugador

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("ClanFX")

local FOLDER_NAME = "ClanFX"
local BYAKUGAN_RANGE = 45
local SHARINGAN_RANGE = 100

local SHARINGAN_RED = Color3.fromRGB(220, 20, 30)
local BYAKUGAN_WHITE = Color3.fromRGB(225, 230, 255)
local UZUMAKI_ORANGE = Color3.fromRGB(255, 140, 60)
local TENKETSU_BLUE = Color3.fromRGB(150, 200, 255)

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
	part.Material = material or Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function localHas(attribute: string): boolean
	local character = localPlayer.Character
	return character ~= nil and character:GetAttribute(attribute) == true
end

-- Avisos ---------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ClanOverlay"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 64
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local notice = Instance.new("TextLabel")
notice.AnchorPoint = Vector2.new(0.5, 0)
notice.Position = UDim2.new(0.5, 0, 0.5, 70)
notice.Size = UDim2.fromOffset(360, 24)
notice.BackgroundTransparency = 1
notice.Font = Enum.Font.GothamBold
notice.TextSize = 15
notice.TextStrokeTransparency = 0.4
notice.TextColor3 = Color3.fromRGB(255, 200, 150)
notice.TextTransparency = 1
notice.Parent = gui

local function showNotice(text: string)
	notice.Text = text
	notice.TextTransparency = 0
	TweenService:Create(notice, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1), {
		TextTransparency = 1,
	}):Play()
end

-- Viñeta clara del Byakugan
local byakuganTint = Instance.new("ColorCorrectionEffect")
byakuganTint.Name = "ByakuganTint"
byakuganTint.Enabled = false
byakuganTint.Saturation = -0.35
byakuganTint.TintColor = Color3.fromRGB(230, 235, 255)
byakuganTint.Parent = Lighting

-- Ojos -----------------------------------------------------------------------------------------

local eyes: {[Model]: {Kind: string, Parts: {Instance}}} = {}

local function removeEyes(character: Model)
	local entry = eyes[character]
	if entry then
		eyes[character] = nil
		for _, part in entry.Parts do
			part:Destroy()
		end
	end
end

local function addEyes(character: Model, kind: string)
	removeEyes(character)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local color = if kind == "Sharingan" then SHARINGAN_RED else BYAKUGAN_WHITE
	local parts = {}
	for _, side in { -1, 1 } do
		local eye = newPart(Vector3.new(0.16, 0.1, 0.05), color)
		eye.Anchored = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(side * 0.2, 0.15, -head.Size.Z / 2 - 0.01)
		eye.Parent = getFolder()
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = eye
		weld.Part1 = head
		weld.Parent = eye
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 3
		light.Brightness = 1.5
		light.Parent = eye
		table.insert(parts, eye)
	end
	eyes[character] = { Kind = kind, Parts = parts }
end

-- Marcas sobre la cabeza ------------------------------------------------------------------------

local markGuis: {[Model]: {Gui: BillboardGui, Uzumaki: TextLabel, Tenketsu: TextLabel}} = {}

local function markGuiFor(character: Model): any?
	local existing = markGuis[character]
	if existing and existing.Gui.Parent then
		return existing
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ClanMarks"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	billboard.MaxDistance = 80
	billboard.Parent = gui

	local function label(y: number, color: Color3): TextLabel
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.new(0, 0, 0, y)
		text.Size = UDim2.new(1, 0, 0, 18)
		text.Font = Enum.Font.GothamBold
		text.TextSize = 16
		text.TextColor3 = color
		text.TextStrokeTransparency = 0.3
		text.Text = ""
		text.Parent = billboard
		return text
	end

	local entry = { Gui = billboard, Uzumaki = label(0, UZUMAKI_ORANGE), Tenketsu = label(20, TENKETSU_BLUE) }
	markGuis[character] = entry
	return entry
end

local function updateMarks(character: Model, now: number)
	local uzumaki = character:GetAttribute("UzumakiMarks")
	local uzumakiUntil = character:GetAttribute("UzumakiMarksUntil")
	local tenketsu = character:GetAttribute("TenketsuMarks")
	local tenketsuUntil = character:GetAttribute("TenketsuMarksUntil")
	local hasUzumaki = typeof(uzumaki) == "number" and typeof(uzumakiUntil) == "number" and uzumakiUntil > now
	local hasTenketsu = typeof(tenketsu) == "number" and typeof(tenketsuUntil) == "number" and tenketsuUntil > now

	if not hasUzumaki and not hasTenketsu then
		local existing = markGuis[character]
		if existing then
			existing.Gui:Destroy()
			markGuis[character] = nil
		end
		return
	end
	local entry = markGuiFor(character)
	if not entry then
		return
	end
	entry.Uzumaki.Text = if hasUzumaki then "封 ×" .. tostring(uzumaki) else ""
	entry.Tenketsu.Text = if hasTenketsu
		then string.rep("●", tenketsu) .. string.rep("○", math.max(0, 5 - tenketsu))
		else ""
end

-- Sharingan: lectura de jutsus -------------------------------------------------------------------

local readGuis: {[Model]: BillboardGui} = {}

local function updateRead(character: Model, active: boolean)
	local casting = character:GetAttribute("JutsuCasting") == true
	local name = character:GetAttribute("JutsuCastingName")
	local existing = readGuis[character]
	if not active or not casting or typeof(name) ~= "string" then
		if existing then
			existing:Destroy()
			readGuis[character] = nil
		end
		return
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	if not existing then
		existing = Instance.new("BillboardGui")
		existing.Name = "SharinganRead"
		existing.Adornee = head
		existing.AlwaysOnTop = true
		existing.Size = UDim2.fromOffset(220, 26)
		existing.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
		existing.Parent = gui
		local frame = Instance.new("TextLabel")
		frame.Name = "Label"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
		frame.BackgroundTransparency = 0.25
		frame.Font = Enum.Font.GothamBold
		frame.TextSize = 13
		frame.TextColor3 = Color3.fromRGB(255, 120, 120)
		frame.Parent = existing
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 5)
		local stroke = Instance.new("UIStroke")
		stroke.Color = SHARINGAN_RED
		stroke.Thickness = 1.5
		stroke.Parent = frame
		readGuis[character] = existing
	end
	(existing:FindFirstChild("Label") :: TextLabel).Text = "◉  " .. string.upper(name)
end

-- Byakugan: visión a través de paredes ---------------------------------------------------------

local seen: {[Model]: Highlight} = {}

local function setSeen(character: Model, visible: boolean, fake: boolean?)
	local existing = seen[character]
	if not visible then
		if existing then
			existing:Destroy()
			seen[character] = nil
		end
		return
	end
	if not existing then
		existing = Instance.new("Highlight")
		existing.Name = "ByakuganSight"
		existing.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		existing.FillTransparency = 0.75
		existing.OutlineTransparency = 0
		existing.Adornee = character
		existing.Parent = getFolder()
		seen[character] = existing
	end
	local color = if fake then Color3.fromRGB(255, 80, 80) else BYAKUGAN_WHITE
	existing.FillColor = color
	existing.OutlineColor = color
end

-- Escaneo -------------------------------------------------------------------------------------

local scanAccumulator = 0

RunService.RenderStepped:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator < 0.1 then
		return
	end
	scanAccumulator = 0

	local now = serverNow()
	local localCharacter = localPlayer.Character
	local localRoot = rootOf(localCharacter)
	local sharingan = localHas("SharinganActive")
	local byakugan = localHas("ByakuganActive")
	byakuganTint.Enabled = byakugan

	local alive: {[Model]: boolean} = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		alive[character] = true

		-- Ojos
		local kind = if character:GetAttribute("SharinganActive") == true then "Sharingan"
			elseif character:GetAttribute("ByakuganActive") == true then "Byakugan"
			else nil
		local current = eyes[character]
		if kind and (not current or current.Kind ~= kind) then
			addEyes(character, kind)
		elseif not kind and current then
			removeEyes(character)
		end

		updateMarks(character, now)

		if character ~= localCharacter then
			local root = rootOf(character)
			local distance = if root and localRoot then (root.Position - localRoot.Position).Magnitude else math.huge
			updateRead(character, sharingan and distance <= SHARINGAN_RANGE)
			setSeen(character, byakugan and distance <= BYAKUGAN_RANGE)
		end
	end

	-- Clones ilusorios (GenjutsuClient): el Byakugan los marca como falsos
	local illusions = Workspace:FindFirstChild("GenjutsuIllusions")
	if illusions then
		for _, clone in illusions:GetChildren() do
			if clone:IsA("Model") then
				alive[clone] = true
				local root = rootOf(clone)
				local close = root and localRoot and (root.Position - localRoot.Position).Magnitude <= BYAKUGAN_RANGE
				setSeen(clone, byakugan and close == true, true)
			end
		end
	end

	-- Limpieza de personajes que ya no existen
	for character in eyes do
		if not alive[character] or not character.Parent then
			removeEyes(character)
		end
	end
	for character, highlight in seen do
		if not alive[character] or not character.Parent then
			highlight:Destroy()
			seen[character] = nil
		end
	end
	for character, billboard in readGuis do
		if not alive[character] then
			billboard:Destroy()
			readGuis[character] = nil
		end
	end
	for character, entry in markGuis do
		if not alive[character] then
			entry.Gui:Destroy()
			markGuis[character] = nil
		end
	end
end)

-- Kagemane ------------------------------------------------------------------------------------

type Shadow = { Parts: {Part}, Connection: RBXScriptConnection?, Ended: boolean }
local shadows: {[number]: Shadow} = {}

local SHADOW_COLOR = Color3.fromRGB(10, 10, 14)

local function groundBelow(position: Vector3, ignore: {Instance}): RaycastResult?
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
	return Workspace:Raycast(position + Vector3.yAxis * 3, Vector3.yAxis * -8, params)
end

local function shadowSegment(shadow: Shadow, from: Vector3, to: Vector3, normal: Vector3, width: number)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return
	end
	local part = newPart(Vector3.new(width, 0.05, length + 0.1), SHADOW_COLOR, Enum.Material.SmoothPlastic)
	part.Transparency = 0.2
	part.CFrame = CFrame.lookAt((from + to) / 2 + normal * 0.06, to + normal * 0.06, normal)
	part.Parent = getFolder()
	table.insert(shadow.Parts, part)
end

local function endShadow(id: number)
	local shadow = shadows[id]
	if not shadow or shadow.Ended then
		return
	end
	shadow.Ended = true
	if shadow.Connection then
		shadow.Connection:Disconnect()
	end
	for _, part in shadow.Parts do
		local tween = TweenService:Create(part, TweenInfo.new(0.35), { Transparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			part:Destroy()
		end)
	end
	task.delay(0.4, function()
		if shadows[id] == shadow then
			shadows[id] = nil
		end
	end)
end

local function shadowStart(data: {[string]: any})
	local root = rootOf(data.Character)
	if not root then
		return
	end
	local direction: Vector3 = data.Direction
	local speed = data.Speed or 45
	local range = data.Range or 28
	local start = groundBelow(root.Position, { data.Character })
	if not start then
		return
	end
	local shadow: Shadow = { Parts = {}, Connection = nil, Ended = false }
	shadows[data.Id] = shadow
	local tip = start.Position
	local travelled = 0
	shadow.Connection = RunService.RenderStepped:Connect(function(dt)
		if shadow.Ended or travelled >= range then
			if shadow.Connection then
				shadow.Connection:Disconnect()
			end
			return
		end
		local step = math.min(speed * dt, range - travelled)
		local ground = groundBelow(tip + direction * step, { data.Character })
		if not ground then
			return
		end
		shadowSegment(shadow, tip, ground.Position, ground.Normal, 0.9)
		tip = ground.Position
		travelled += step
	end)
end

local function shadowCapture(data: {[string]: any})
	local shadow = shadows[data.Id]
	if shadow and shadow.Connection then
		shadow.Connection:Disconnect()
		shadow.Connection = nil
	end
	shadow = shadow or { Parts = {}, Connection = nil, Ended = false }
	shadows[data.Id] = shadow
	local targetRoot = rootOf(data.Target)
	local casterRoot = rootOf(data.Character)
	if not targetRoot or not casterRoot then
		return
	end
	-- Charco de sombra bajo el atrapado + hilo de sombra que lo une al Nara (se actualiza)
	local pool = newPart(Vector3.new(0.05, 5, 5), SHADOW_COLOR, Enum.Material.SmoothPlastic)
	pool.Shape = Enum.PartType.Cylinder
	pool.Transparency = 0.15
	pool.Parent = getFolder()
	table.insert(shadow.Parts, pool)
	local link = newPart(Vector3.new(0.7, 0.05, 1), SHADOW_COLOR, Enum.Material.SmoothPlastic)
	link.Transparency = 0.2
	link.Parent = getFolder()
	table.insert(shadow.Parts, link)

	shadow.Connection = RunService.RenderStepped:Connect(function()
		if shadow.Ended or not targetRoot.Parent or not casterRoot.Parent then
			return
		end
		local targetGround = groundBelow(targetRoot.Position, { data.Target })
		local casterGround = groundBelow(casterRoot.Position, { data.Character })
		if targetGround then
			pool.CFrame = CFrame.new(targetGround.Position + Vector3.yAxis * 0.06) * CFrame.Angles(0, 0, math.pi / 2)
		end
		if targetGround and casterGround then
			local a, b = casterGround.Position + Vector3.yAxis * 0.06, targetGround.Position + Vector3.yAxis * 0.06
			local length = (b - a).Magnitude
			link.Size = Vector3.new(0.7, 0.05, math.max(length, 0.1))
			link.CFrame = CFrame.lookAt((a + b) / 2, b)
		end
	end)
	task.delay((data.Duration or 1.5) + 0.2, function()
		endShadow(data.Id)
	end)
end

-- Sello Uzumaki / tenketsu ---------------------------------------------------------------------

local function ringBurst(character: Model?, color: Color3, text: string)
	local root = rootOf(character)
	if not root then
		return
	end
	local ring = newPart(Vector3.new(0.1, 3, 3), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Transparency = 0.2
	ring.Parent = getFolder()
	local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 12, 12),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		ring:Destroy()
	end)

	local head = character and character:FindFirstChild("Head")
	if head then
		local billboard = Instance.new("BillboardGui")
		billboard.Adornee = head
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(80, 80)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
		billboard.Parent = gui
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.2
		label.Parent = billboard
		TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(1.3, function()
			billboard:Destroy()
		end)
	end
end

-- Entrada ------------------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if action == "ShadowStart" then
			shadowStart(data)
		elseif action == "ShadowCapture" then
			shadowCapture(data)
		elseif action == "ShadowEnd" then
			endShadow(data.Id)
		elseif action == "SealBurst" then
			ringBurst(data.Target, UZUMAKI_ORANGE, "封")
		elseif action == "TenketsuSealed" then
			ringBurst(data.Target, TENKETSU_BLUE, "柔")
		elseif action == "ModeNoChakra" then
			showNotice("SIN CHAKRA PARA MANTENER EL DŌJUTSU")
		elseif action == "Notice" and typeof(data.Text) == "string" then
			showNotice(data.Text)
		end
	end)
	if not ok then
		warn("[ClanClient] " .. tostring(action) .. ": " .. tostring(err))
	end
end)
