-- StarterPlayer > StarterPlayerScripts > ClanClient  (LocalScript)
--
-- Dibuja las mecánicas de clan (TechniqueKit > Clan, etapa 1):
--   Ojos           Sharingan: la textura del ojo la cambia CharacterFaceController (variante
--                  "Sharingan" de AppearanceCatalog, atributo CharacterEyeVariantId). Aquí van
--                  el brillo rojo, la estela al moverse rápido y, si ese estilo de ojo todavía
--                  no tiene textura de Sharingan, dos puntos rojos.
--                  Byakugan: puntos blancos con brillo.
--   Sharingan      ModeStart: destello y tomoe girando en TU pantalla + sonido; los demás ven el
--                  destello en tus ojos. Mientras lo tienes: tinte, viñeta roja e indicador
--                  (solo el tomoe).
--                  Lectura: el servidor te manda "SharinganRead" cuando alguien que tienes
--                  delante prepara un jutsu (icono del jutsu, nombre, barra de sellos y
--                  trayectoria tan larga como su alcance).
--                  Los clones ilusorios que tengas a la vista se marcan como falsos.
--                  Tomoe (atributo SharinganTomoe): el tomoe dibujado tiene 1, 2 o 3 comas.
--                  SharinganWindup: Genjutsu: Sharingan, solo sonido y brillo de ojos (sin nada
--                  en pantalla). GenjutsuReflected: texto breve "REFLECTED" sobre quien lo
--                  lanzó; el paralizado ve el tomoe girando. SubstitutionRead (2+ tomoe / Byakugan):
--                  remanentes de quien se sustituyó mientras va invisible. Copied / CopyCleared:
--                  nombre del jutsu copiado y el tiempo que queda, encima del indicador.
--   Byakugan       (si TÚ lo tienes activo) ves a todos a ≤ 45 studs a través de paredes y los
--                  clones ilusorios marcados como FALSO (humo, Henge y minas: en sus scripts)
--   Marcas         sobre quien las tenga: sellos Uzumaki (封 ×N) y tenketsu Hyūga (●○○○○)
--   Kagemane       la sombra que corre por el suelo, la captura y el hilo de sombra
--   SealBurst      sello Uzumaki detonado · TenketsuSealed: tenketsu sellados
--   Clash          indicador de clash (Sharingan, en este cliente con Throwables > ClientShots):
--                  icono de peligro con flecha alrededor del centro
--                  de la pantalla que señala de dónde viene el proyectil (también de espaldas);
--                  icono de clash cuando pulsar G haría clash (gris si no puedes)
--   ClanAwakened   despertar de una etapa: para ti, velo rojo y el tomoe nuevo girando; los
--                  demás ven el tomoe cerrarse sobre tu cara
--   Icon           avisos al jugador SIN texto: el icono (ReplicatedStorage > Shared > ClanAssets)
--                  salta encima del indicador del dōjutsu
--   Notice         avisos con texto (otros clanes, de momento)
--
-- El tomoe usa la imagen de ClanAssets.SharinganIris (1, 2 o 3 tomoe); sin imagen, makeEmblem lo dibuja con Frames.
-- Iconos y sonidos definitivos: se rellenan en ClanAssets (sin tocar este script).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("ClanFX")
local AppearanceCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AppearanceCatalog"))
local ClanAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClanAssets"))

local FOLDER_NAME = "ClanFX"
local BYAKUGAN_RANGE = 45
local SHARINGAN_CLONE_RANGE_BY_TOMOE = { 90, 110, 130 } -- clones falsos: igual que la lectura (Clan.Tuning)
local SHARINGAN_VIEW_DOT = math.cos(math.rad(70)) -- campo visual (140°) según hacia dónde mira tu cuerpo
local TRAIL_SPEED = 26 -- studs/s: a partir de aquí los ojos del Sharingan dejan estela
local TRAJECTORY_DEFAULT = 60 -- trayectoria de un jutsu que no declara alcance
local TRAJECTORY_MAX = 150

local SHARINGAN_SOUND_VOLUME = 0.8
-- En tu propia pantalla el sonido suena en tu cabeza, casi sin distancia: más bajo
local SHARINGAN_SELF_VOLUME = 0.3
local SHARINGAN_SELF_AWAKEN_VOLUME = 0.4

-- Emblema grande al activar: transparencia mientras se ve y tiempos de entrada / salida
local ACTIVATION_EMBLEM_TRANSPARENCY = 0.6
local ACTIVATION_IN, ACTIVATION_HOLD, ACTIVATION_OUT = 0.15, 0.3, 0.5
-- Mientras dura el despertar no se dibuja la activación normal (llegan casi a la vez)
local awakeningUntil = 0

local SHARINGAN_RED = Color3.fromRGB(220, 20, 30)
local SHARINGAN_DARK = Color3.fromRGB(28, 2, 5)
local BYAKUGAN_WHITE = Color3.fromRGB(225, 230, 255)
local UZUMAKI_ORANGE = Color3.fromRGB(255, 140, 60)
local TENKETSU_BLUE = Color3.fromRGB(150, 200, 255)

-- string.upper no pasa a mayúscula las vocales con macrón (ō → Ō)
local MACRONS = { ["ā"] = "Ā", ["ē"] = "Ē", ["ī"] = "Ī", ["ō"] = "Ō", ["ū"] = "Ū" }

local function upper(text: string): string
	local result = string.upper(text)
	for lower, capital in MACRONS do
		result = string.gsub(result, lower, capital)
	end
	return result
end

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

-- Tomoe del Sharingan de ese personaje (atributo SharinganTomoe; 1 si no lo tiene)
local function tomoeOf(character: Model?): number
	local tomoe = character and character:GetAttribute("SharinganTomoe")
	return if typeof(tomoe) == "number" then math.clamp(math.floor(tomoe), 1, 3) else 1
end

-- Imagen del iris para una clave: número = tomoe (1–3) · texto = iris del Mangekyō ("Itachi"…)
local function irisImageFor(key: any): string?
	if typeof(key) == "string" then
		return (ClanAssets.MangekyoIris and ClanAssets.MangekyoIris[key])
			or (ClanAssets.SharinganIris and ClanAssets.SharinganIris[3])
	end
	return ClanAssets.SharinganIris and ClanAssets.SharinganIris[math.clamp(tonumber(key) or 1, 1, 3)]
end

-- Clave del iris que lleva un personaje ahora: su Mangekyō si lo tiene activo, si no sus tomoe
local function emblemKey(character: Model?): any
	if character and character:GetAttribute("MangekyoActive") == true then
		local iris = character:GetAttribute("MangekyoIris")
		return if typeof(iris) == "string" then iris else "Itachi"
	end
	return tomoeOf(character)
end

-- Iconos (ClanAssets): la imagen si la hay; si no, el placeholder (círculo oscuro con el kanji)
local function makeBadge(icon: any, size: UDim2): Frame
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.Size = size
	badge.BackgroundTransparency = 1
	badge.BorderSizePixel = 0
	if typeof(icon.Image) == "string" and icon.Image ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = icon.Image
		image.Parent = badge
		return badge
	end
	badge.BackgroundColor3 = SHARINGAN_DARK
	badge.BackgroundTransparency = 0.1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = icon.Color
	stroke.Thickness = 2
	stroke.Parent = badge
	local glyph = Instance.new("TextLabel")
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.7, 0.7)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.GothamBold
	glyph.TextScaled = true
	glyph.Text = icon.Glyph
	glyph.TextColor3 = icon.Color
	glyph.Parent = badge
	return badge
end

local function playSound(character: Model, soundId: string, volume: number, maxDistance: number?)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = maxDistance or 70
	sound.Parent = head
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

-- Avisos ---------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ClanOverlay"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 64
gui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Los BillboardGui van directos en PlayerGui (dentro de un ScreenGui no es seguro que se dibujen)
local billboardParent = localPlayer:WaitForChild("PlayerGui")

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
notice.ZIndex = 10 -- por encima de los destellos y de la pantalla del paralizado
notice.Parent = gui

local function showNotice(text: string)
	notice.Text = text
	notice.TextTransparency = 0
	TweenService:Create(notice, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1), {
		TextTransparency = 1,
	}):Play()
end

-- Tomoe procedural ------------------------------------------------------------------------------

local function circle(parent: Instance, scale: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

-- Iris rojo, anillo, pupila y `tomoe` comas negras alrededor. Devuelve un CanvasGroup (se puede
-- girar, escalar y desvanecer de una vez).
-- Con imagen devuelve un ImageLabel (se desvanece con ImageTransparency); sin imagen, el dibujo
-- procedural en un CanvasGroup (GroupTransparency). No meter la imagen en un CanvasGroup: si Roblox
-- no puede dibujarlo como grupo, ignora GroupTransparency y la imagen sale sólida y se corta de golpe.
local function makeEmblem(size: UDim2, tomoe: any): GuiObject
	local irisImage = irisImageFor(tomoe)
	if typeof(irisImage) == "string" and irisImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "SharinganEmblem"
		image.BackgroundTransparency = 1
		image.Image = irisImage
		image.ScaleType = Enum.ScaleType.Fit
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = size
		return image
	end

	local group = Instance.new("CanvasGroup")
	group.Name = "SharinganEmblem"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = size

	local iris = circle(group, 0.94, SHARINGAN_RED)
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.new(0, 0, 0)
	rim.Thickness = 2
	rim.Parent = iris

	local ring = circle(iris, 0.6, SHARINGAN_RED)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(70, 0, 0)
	ringStroke.Thickness = 1
	ringStroke.Parent = ring

	circle(iris, 0.2, Color3.new(0, 0, 0)) -- pupila

	local tomoeCount = if typeof(tomoe) == "number" then math.clamp(tomoe, 1, 3) else 3
	for index = 1, tomoeCount do
		local arm = Instance.new("Frame")
		arm.Name = "Tomoe"
		arm.BackgroundTransparency = 1
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.Position = UDim2.fromScale(0.5, 0.5)
		arm.Size = UDim2.fromScale(1, 1)
		arm.Rotation = (index - 1) * (360 / tomoeCount)
		arm.Parent = iris
		local ball = circle(arm, 0.17, Color3.new(0, 0, 0))
		ball.Position = UDim2.fromScale(0.5, 0.2)
		local tail = circle(arm, 0.08, Color3.new(0, 0, 0))
		tail.Position = UDim2.fromScale(0.6, 0.14)
	end
	return group
end

-- Propiedad de transparencia del emblema (ImageLabel o CanvasGroup) y meta de tween con ella
local function fadeKey(emblem: GuiObject): string
	return if emblem:IsA("CanvasGroup") then "GroupTransparency" else "ImageTransparency"
end

local function fadeGoal(emblem: GuiObject, value: number, goal: {[string]: any}?): {[string]: any}
	local result = goal or {}
	result[fadeKey(emblem)] = value
	return result
end

-- Precarga del iris y los sonidos del Sharingan para que la primera activación no salga vacía
task.spawn(function()
	local preload = {}
	local images = table.clone(ClanAssets.SharinganIris or {})
	table.insert(images, ClanAssets.EyeGlow or "")
	table.insert(images, ClanAssets.SharinganVignette or "")
	for _, id in images do
		if id ~= "" then
			local image = Instance.new("ImageLabel")
			image.Image = id
			table.insert(preload, image)
		end
	end
	for _, id in ClanAssets.Sounds do
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(preload, sound)
		end
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(preload)
	end)
	for _, instance in preload do
		instance:Destroy()
	end
end)

-- Ambiente de los dōjutsu ------------------------------------------------------------------------

-- Viñeta clara del Byakugan
local byakuganTint = Instance.new("ColorCorrectionEffect")
byakuganTint.Name = "ByakuganTint"
byakuganTint.Enabled = false
byakuganTint.Saturation = -0.35
byakuganTint.TintColor = Color3.fromRGB(230, 235, 255)
byakuganTint.Parent = Lighting

-- Sharingan: percepción agudizada, no daño. Más contraste y un pelín más de color (quitar
-- saturación y teñir de rojo es lo que hace parecer "poca vida")
local sharinganTint = Instance.new("ColorCorrectionEffect")
sharinganTint.Name = "SharinganTint"
sharinganTint.Enabled = false
sharinganTint.Contrast = 0.1
sharinganTint.Saturation = 0.06
sharinganTint.TintColor = Color3.fromRGB(255, 247, 244)
sharinganTint.Parent = Lighting

-- Viñeta: oscura y suave, sobre todo en las esquinas (ClanAssets.SharinganVignette). Va en su
-- propio ScreenGui por debajo del HUD para no oscurecerlo; aparece y se va con un fundido.
local VIGNETTE_COLOR = Color3.fromRGB(24, 3, 7)
local VIGNETTE_TRANSPARENCY = 0.3
local VIGNETTE_FADE = 0.4

local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "ClanVignette"
vignetteGui.IgnoreGuiInset = true
vignetteGui.ResetOnSpawn = false
vignetteGui.DisplayOrder = -10
vignetteGui.Parent = localPlayer:WaitForChild("PlayerGui")

local vignette = Instance.new("ImageLabel")
vignette.Name = "SharinganVignette"
vignette.BackgroundTransparency = 1
vignette.Size = UDim2.fromScale(1, 1)
vignette.Image = ClanAssets.SharinganVignette or ""
vignette.ImageColor3 = VIGNETTE_COLOR
vignette.ImageTransparency = 1
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.Parent = vignetteGui

-- Fatiga ocular (Eye Strain) del Mangekyō (atributo del jugador MangekyoEyeStrain, 0–100): con un dōjutsu activo la
-- vista se desenfoca y los bordes se oscurecen por tramos. Baja fuera de combate (servidor).
local BLINDNESS_TIERS = {
	{ At = 100, Blur = 14, Shade = 0.3 },
	{ At = 75, Blur = 10, Shade = 0.45 },
	{ At = 50, Blur = 6, Shade = 0.65 },
	{ At = 25, Blur = 3, Shade = 0.85 },
}

local eyeStrainBlur = Instance.new("BlurEffect")
eyeStrainBlur.Name = "MangekyoEyeStrainBlur"
eyeStrainBlur.Size = 0
eyeStrainBlur.Parent = Lighting

local eyeStrainShade = Instance.new("ImageLabel")
eyeStrainShade.Name = "MangekyoEyeStrainShade"
eyeStrainShade.BackgroundTransparency = 1
eyeStrainShade.Size = UDim2.fromScale(1, 1)
eyeStrainShade.Image = ClanAssets.SharinganVignette or ""
eyeStrainShade.ImageColor3 = Color3.new(0, 0, 0)
eyeStrainShade.ImageTransparency = 1
eyeStrainShade.ScaleType = Enum.ScaleType.Stretch
eyeStrainShade.ZIndex = 2
eyeStrainShade.Parent = vignetteGui

local eyeStrainTier = 0
local function setEyeStrainView(value: number)
	local tier, blur, shade = 0, 0, 1
	for index, entry in BLINDNESS_TIERS do
		if value >= entry.At then
			tier, blur, shade = #BLINDNESS_TIERS - index + 1, entry.Blur, entry.Shade
			break
		end
	end
	if tier == eyeStrainTier then
		return
	end
	eyeStrainTier = tier
	TweenService:Create(eyeStrainBlur, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Size = blur }):Play()
	TweenService:Create(eyeStrainShade, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { ImageTransparency = shade }):Play()
end

local vignetteOn = false
local function setVignette(on: boolean)
	if on == vignetteOn then
		return
	end
	vignetteOn = on
	TweenService:Create(vignette, TweenInfo.new(VIGNETTE_FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = if on then VIGNETTE_TRANSPARENCY else 1,
	}):Play()
end

-- Avisos para ti: el icono salta encima del indicador del dōjutsu y se desvanece
-- Dónde salta el icono de aviso; se reasigna más abajo para ponerlo encima del indicador del HUD
local popAnchor: () -> UDim2 = function()
	return UDim2.new(0.5, 0, 1, -286)
end

-- Aviso corto en texto encima del indicador del HUD: sube un poco y se desvanece
local function popText(text: string, denied: boolean?)
	local label = Instance.new("TextLabel")
	label.Name = "ClanNotice"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = popAnchor()
	label.Size = UDim2.fromOffset(260, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(255, 228, 228)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.ZIndex = 9
	label.Parent = gui
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = label.Position + UDim2.fromOffset(0, -10),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.75), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.15, function()
		label:Destroy()
	end)
	local character = localPlayer.Character
	if denied and character then
		playSound(character, ClanAssets.Sounds.Denied, 0.6)
	end
end

-- Avisos del servidor ("Icon"): solo los que merecen texto. GenjutsuResisted y el resto, sin aviso.
local function personalNotice(data: {[string]: any})
	local name = data.Icon
	if name == "SharinganRequired" then
		popText("Sharingan required", true)
	elseif name == "NotAwakened" then
		popText(if typeof(data.Tomoe) == "number" then string.format("Requires %d tomoe", data.Tomoe) else "Sharingan not awakened", true)
	elseif name == "NothingCopied" then
		popText("Nothing copied", true)
	elseif name == "NoMangekyo" then
		popText("Mangekyō not awakened", true)
	elseif name == "MangekyoRequired" then
		popText(if typeof(data.Ability) == "string" then "Your Mangekyō lacks " .. data.Ability else "Mangekyō Sharingan required", true)
	elseif name == "EyeStrainLocked" then
		popText("Eye strain too high to use the Mangekyō", true)
	end
end

-- Indicador mientras lo tienes activo: solo el tomoe girando (las comas dicen la etapa)
local indicator = Instance.new("Frame")
indicator.Name = "SharinganIndicator"
indicator.AnchorPoint = Vector2.new(0.5, 1)
indicator.Position = UDim2.new(0.5, 0, 1, -205) -- encima del HUD central
indicator.Size = UDim2.fromOffset(40, 40)
indicator.BackgroundTransparency = 1
-- El marco SIEMPRE está visible (es transparente): un GuiObject oculto no recalcula su
-- AbsolutePosition, y el iris que baja necesita la posición real. Se oculta solo el iris.
indicator.Visible = true
indicator.Parent = gui

local indicatorEmblem: GuiObject? = nil
local indicatorTomoe = 0
-- El indicador va dentro del HUD de combate (WAYLESSCombatHUD_v20 > Root), encima de la orbe
-- de fuerza vital, y escala con el UIScale del HUD. Medidas en unidades del lienzo del HUD.
local HUD_NAME = "WAYLESSCombatHUD_v20"
local INDICATOR_HUD_SIZE = 44
local INDICATOR_HUD_GAP = 4
-- El iris ocupa esta fracción del indicador
local INDICATOR_EMBLEM_FILL = 0.9
-- Mientras el emblema grande baja a ocupar su sitio, el indicador no se dibuja (es el mismo)
local indicatorHiddenUntil = 0
local indicatorShown = false

-- El tomoe del indicador se rehace si cambian los tomoe
local function refreshIndicator(tomoe: any)
	if tomoe == indicatorTomoe then
		return
	end
	indicatorTomoe = tomoe
	local rotation = if indicatorEmblem then indicatorEmblem.Rotation else 0
	if indicatorEmblem then
		indicatorEmblem:Destroy()
	end
	-- Con imagen: ImageLabel directo. Un CanvasGroup tan pequeño rasteriza el PNG grande sin
	-- mipmaps y el borde y las colas de los tomoe salen como picos al girar.
	local irisImage = irisImageFor(tomoe)
	local emblem: GuiObject
	if typeof(irisImage) == "string" and irisImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "SharinganEmblem"
		image.BackgroundTransparency = 1
		image.Image = irisImage
		image.ScaleType = Enum.ScaleType.Fit
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Size = UDim2.fromScale(INDICATOR_EMBLEM_FILL, INDICATOR_EMBLEM_FILL)
		emblem = image
	else
		emblem = makeEmblem(UDim2.fromScale(INDICATOR_EMBLEM_FILL, INDICATOR_EMBLEM_FILL), tomoe)
	end
	emblem.Position = UDim2.fromScale(0.5, 0.5)
	emblem.Rotation = rotation
	emblem.Visible = indicatorShown
	emblem.Parent = indicator
	indicatorEmblem = emblem
end
refreshIndicator(1)

-- Cuándo se vio el indicador por última vez (el apagado lo cierra aunque el escaneo ya lo ocultara)
local indicatorLastShown = 0

local function setIndicatorShown(shown: boolean)
	if indicatorShown then
		indicatorLastShown = os.clock()
	end
	indicatorShown = shown
	if indicatorEmblem then
		indicatorEmblem.Visible = shown
	end
end

-- El emblema grande (activación o despertar) baja, se encoge y se convierte en el indicador:
-- un solo Sharingan en pantalla que pasa de una posición a la otra
-- Al llegar, el emblema que baja SE CONVIERTE en el del indicador (mismo objeto, mismo giro):
-- no hay cambio de imagen ni salto.
local function landOnIndicator(emblem: GuiObject, tomoe: number, duration: number)
	refreshIndicator(tomoe)
	indicatorHiddenUntil = os.clock() + duration + 0.1
	setIndicatorShown(false)
	TweenService:Create(emblem, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), fadeGoal(emblem, 0)):Play()
	-- Posición y tamaño por fotograma persiguiendo el indicador real (si el HUD cambia de escala
	-- a mitad del viaje, llega igual). Ojo: ClanOverlay y el HUD no tienen el mismo origen de
	-- AbsolutePosition (difieren en la barra superior), así que todo se calcula en absoluto y se
	-- pasa a coordenadas de ClanOverlay restando gui.AbsolutePosition.
	local startCenter = emblem.AbsolutePosition + emblem.AbsoluteSize / 2
	local startSize = emblem.AbsoluteSize.X
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	local elapsed = 0
	local done = false
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not emblem.Parent then
			connection:Disconnect()
			return
		end
		elapsed += dt
		local alpha = math.min(elapsed / duration, 1)
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		local target = indicator.AbsolutePosition + indicator.AbsoluteSize / 2
		local targetSize = indicator.AbsoluteSize.X * INDICATOR_EMBLEM_FILL
		local center = startCenter:Lerp(target, eased)
		local size = startSize + (targetSize - startSize) * eased
		local origin = gui.AbsolutePosition
		emblem.Position = UDim2.fromOffset(center.X - origin.X, center.Y - origin.Y)
		emblem.Size = UDim2.fromOffset(size, size)
		if alpha >= 1 and not done then
			done = true
			connection:Disconnect()
			emblem[fadeKey(emblem)] = 0
			local rotation = emblem.Rotation % 360
			if indicatorEmblem and indicatorEmblem ~= emblem then
				indicatorEmblem:Destroy()
			end
			emblem.Name = "SharinganEmblem"
			emblem.Position = UDim2.fromScale(0.5, 0.5)
			emblem.Size = UDim2.fromScale(INDICATOR_EMBLEM_FILL, INDICATOR_EMBLEM_FILL)
			emblem.ZIndex = indicator.ZIndex + 1
			emblem.Rotation = rotation
			emblem.Parent = indicator
			indicatorEmblem = emblem
			indicatorTomoe = tomoe
			indicatorHiddenUntil = 0
			setIndicatorShown(localHas("SharinganActive"))
		end
	end)
end


-- Jutsu copiado (Copia del Sharingan): icono de la Copia + icono del jutsu y el tiempo que le queda
local copyChip = Instance.new("Frame")
copyChip.Name = "SharinganCopy"
copyChip.AnchorPoint = Vector2.new(0.5, 1)
copyChip.Position = UDim2.new(0.5, 0, 1, -250)
copyChip.Size = UDim2.fromOffset(170, 22)
copyChip.BackgroundTransparency = 1
copyChip.Visible = false
copyChip.Parent = gui

-- Nombre del jutsu copiado (texto: los jutsus no tienen icono) y debajo el tiempo que le queda
local copyLabel = Instance.new("TextLabel")
copyLabel.Name = "Name"
copyLabel.BackgroundTransparency = 1
copyLabel.Size = UDim2.new(1, 0, 1, -5)
copyLabel.Font = Enum.Font.GothamBold
copyLabel.TextSize = 14
copyLabel.TextColor3 = Color3.fromRGB(255, 228, 228)
copyLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
copyLabel.TextStrokeTransparency = 0.35
copyLabel.TextTruncate = Enum.TextTruncate.AtEnd
copyLabel.Text = ""
copyLabel.Parent = copyChip

local copyBar = Instance.new("Frame")
copyBar.BackgroundColor3 = SHARINGAN_RED
copyBar.BorderSizePixel = 0
copyBar.Position = UDim2.new(0, 0, 1, -3)
copyBar.Size = UDim2.new(1, 0, 0, 3)
copyBar.Parent = copyChip

local copyUntil = 0
local copyDuration = 12

local function showCopied(data: {[string]: any})
	copyLabel.Text = "COPY · " .. upper(tostring(data.Name or "?"))
	local nature = typeof(data.NatureId) == "string" and ClanAssets.Natures[data.NatureId]
	copyBar.BackgroundColor3 = if nature then nature.Color else SHARINGAN_RED
	copyDuration = if typeof(data.Duration) == "number" and data.Duration > 0 then data.Duration else 12
	copyUntil = os.clock() + copyDuration
end

local function clearCopied()
	copyUntil = 0
end

-- Anclaje al HUD: el indicador y la Copia van dentro de su Root, encima de la orbe. Si el HUD
-- todavía no existe (o se rehace) se quedan en la posición de respaldo de ClanOverlay.
local function placeFallback()
	indicator.AnchorPoint = Vector2.new(0.5, 1)
	indicator.Position = UDim2.new(0.5, 0, 1, -205)
	indicator.Size = UDim2.fromOffset(40, 40)
	indicator.Parent = gui
	copyChip.Position = UDim2.new(0.5, 0, 1, -250)
	copyChip.Parent = gui
end

local function placeOnHud(hud: Instance): boolean
	local root = hud:WaitForChild("Root", 10)
	local orb = root and root:WaitForChild("LifeForceFrame", 10)
	if not root or not orb or not orb:IsA("GuiObject") or not root:IsA("GuiObject") then
		return false
	end
	local centerX = orb.Position.X.Offset + orb.Size.X.Offset * (0.5 - orb.AnchorPoint.X)
	local top = orb.Position.Y.Offset - orb.Size.Y.Offset * orb.AnchorPoint.Y
	indicator.AnchorPoint = Vector2.new(0.5, 1)
	indicator.Size = UDim2.fromOffset(INDICATOR_HUD_SIZE, INDICATOR_HUD_SIZE)
	indicator.Position = UDim2.fromOffset(centerX, top - INDICATOR_HUD_GAP)
	indicator.ZIndex = 40
	indicator.Parent = root
	copyChip.Position = UDim2.fromOffset(centerX, top - INDICATOR_HUD_GAP - INDICATOR_HUD_SIZE - 4)
	copyChip.ZIndex = 40
	copyChip.Parent = root
	root.Destroying:Once(function()
		pcall(placeFallback)
	end)
	return true
end

-- Encima del indicador (y de la Copia), esté donde esté el HUD
popAnchor = function()
	-- Absoluto del indicador → coordenadas de ClanOverlay (origen distinto al del HUD)
	local origin = gui.AbsolutePosition
	local above = indicator.AbsolutePosition.Y - copyChip.AbsoluteSize.Y - 10
	return UDim2.fromOffset(indicator.AbsolutePosition.X + indicator.AbsoluteSize.X / 2 - origin.X, above - origin.Y)
end

placeFallback()
task.spawn(function()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild(HUD_NAME)
	if hud then
		placeOnHud(hud)
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == HUD_NAME then
			placeOnHud(child)
		end
	end)
end)

RunService.RenderStepped:Connect(function(dt)
	if indicatorShown and indicatorEmblem then
		indicatorEmblem.Rotation = (indicatorEmblem.Rotation + dt * 45) % 360
	end
	local left = copyUntil - os.clock()
	copyChip.Visible = indicatorShown and left > 0
	if copyChip.Visible then
		copyBar.Size = UDim2.new(math.clamp(left / copyDuration, 0, 1), 0, 0, 3)
	end
end)

-- Activación en tu pantalla: destello rojo y tomoe que gira, crece y se desvanece
local function screenActivation(tomoe: number)
	if os.clock() < awakeningUntil then
		return
	end
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = SHARINGAN_RED
	flash.BackgroundTransparency = 0.75
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 5
	flash.Parent = gui
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()

	-- Entrada: aparece pequeño y crece con un leve rebote, semitransparente para no tapar la vista
	flash.Name = "SharinganActivationFX"
	local emblem = makeEmblem(UDim2.fromOffset(90, 90), tomoe)
	emblem.Name = "SharinganActivationFX"
	emblem.Position = UDim2.fromScale(0.5, 0.45)
	emblem.ZIndex = 6
	emblem[fadeKey(emblem)] = 1
	emblem.Parent = gui
	local total = ACTIVATION_IN + ACTIVATION_HOLD + ACTIVATION_OUT
	TweenService:Create(emblem, TweenInfo.new(ACTIVATION_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), fadeGoal(emblem, ACTIVATION_EMBLEM_TRANSPARENCY, {
		Size = UDim2.fromOffset(150, 150),
	})):Play()
	-- Gira todo el rato, frenando al final
	TweenService:Create(emblem, TweenInfo.new(total, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Rotation = 420,
	}):Play()
	-- Salida: baja, se encoge y se queda como el indicador del HUD
	indicatorHiddenUntil = os.clock() + total + 0.1
	setIndicatorShown(false)
	task.delay(ACTIVATION_IN + ACTIVATION_HOLD, function()
		if emblem.Parent then
			landOnIndicator(emblem, tomoe, ACTIVATION_OUT)
		end
	end)

	task.delay(total + 0.05, function()
		flash:Destroy()
	end)
end

-- Al apagarlo: el reverso de la activación. El iris del HUD gira rápido, se cierra y se apaga;
-- la viñeta se va con su fundido (setVignette) y hay un parpadeo oscuro muy suave.
local DEACTIVATION_TIME = 0.35

local function screenDeactivation()
	if indicatorEmblem and (indicatorShown or os.clock() - indicatorLastShown < 0.3) then
		local closing = indicatorEmblem:Clone()
		closing.Name = "SharinganClosing"
		closing.Visible = true
		closing.Parent = indicator
		TweenService:Create(closing, TweenInfo.new(DEACTIVATION_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), fadeGoal(closing, 1, {
			Size = UDim2.fromScale(0, 0),
			Rotation = closing.Rotation + 300,
		})):Play()
		task.delay(DEACTIVATION_TIME + 0.05, function()
			closing:Destroy()
		end)
		setIndicatorShown(false)
	end

	local blink = Instance.new("Frame")
	blink.BackgroundColor3 = Color3.new(0, 0, 0)
	blink.BackgroundTransparency = 0.85
	blink.BorderSizePixel = 0
	blink.Size = UDim2.fromScale(1, 1)
	blink.ZIndex = 5
	blink.Parent = gui
	local tween = TweenService:Create(blink, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		blink:Destroy()
	end)
end

-- Ojos -----------------------------------------------------------------------------------------

type EyeEntry = { Kind: string, Instances: {Instance}, Light: PointLight?, Trails: {Trail}, Glows: {BillboardGui} }

-- Brillo visible de cada ojo (textura suave ClanAssets.EyeGlow, sin depender de la luz del mapa).
-- Tamaño en studs: se encoge con la distancia como la cabeza.
local EYE_GLOW_SIZE = 0.5
-- Estela de los ojos al moverse rápido: grosor (la mitad, en studs) y largo (s que dura)
local EYE_TRAIL_HALF_WIDTH = 0.08
local EYE_TRAIL_LIFETIME = 0.19
local EYE_GLOW_FLASH_SIZE = 1.5
local EYE_GLOW_TRANSPARENCY = 0.25
-- Luz sobre la cara: muy suave, si no tiñe toda la cabeza de rojo
local EYE_LIGHT_BRIGHTNESS, EYE_LIGHT_RANGE = 0.5, 2
local eyes: {[Model]: EyeEntry} = {}

local EYE_OFFSET_X = 0.2
local EYE_OFFSET_Y = 0.15

local function removeEyes(character: Model)
	local entry = eyes[character]
	if entry then
		eyes[character] = nil
		for _, instance in entry.Instances do
			instance:Destroy()
		end
	end
end

-- ¿El estilo de ojo de este jugador tiene textura para esta variante? (si no, van puntos)
local function hasEyeVariant(player: Player?, variantId: string): boolean
	if not player then
		return false
	end
	local styleId = player:GetAttribute("CharacterBaseEyeStyleId") or player:GetAttribute("CharacterEyeStyleId")
	if typeof(styleId) ~= "string" or styleId == "" then
		styleId = AppearanceCatalog.Defaults and AppearanceCatalog.Defaults.EyeStyleId
	end
	if typeof(styleId) ~= "string" then
		return false
	end
	local variant = AppearanceCatalog.GetEyeImage(styleId, variantId)
	return variant ~= nil and variant ~= AppearanceCatalog.GetEyeImage(styleId, "Base")
end

local function addEyes(character: Model, kind: string)
	removeEyes(character)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local sharingan = kind == "Sharingan"
	local color = if sharingan then SHARINGAN_RED else BYAKUGAN_WHITE
	local front = -head.Size.Z / 2
	local entry: EyeEntry = { Kind = kind, Instances = {}, Light = nil, Trails = {}, Glows = {} }

	-- Brillo en la cara
	local glow = Instance.new("Attachment")
	glow.Name = "DojutsuGlow"
	glow.Position = Vector3.new(0, EYE_OFFSET_Y, front - 0.2)
	glow.Parent = head
	table.insert(entry.Instances, glow)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = EYE_LIGHT_RANGE
	light.Brightness = EYE_LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = glow
	entry.Light = light

	-- Brillo en cada ojo: textura de degradado suave teñida, siempre a plena intensidad. No es
	-- AlwaysOnTop: la cabeza lo tapa si te ven de espaldas.
	for _, side in { -1, 1 } do
		local anchor = Instance.new("Attachment")
		anchor.Name = "DojutsuEyeGlow"
		anchor.Position = Vector3.new(side * EYE_OFFSET_X, EYE_OFFSET_Y, front - 0.06)
		anchor.Parent = head
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "DojutsuEyeGlow"
		billboard.Adornee = anchor
		billboard.Size = UDim2.fromScale(EYE_GLOW_SIZE, EYE_GLOW_SIZE)
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 90
		billboard.Parent = billboardParent
		local halo = Instance.new("ImageLabel")
		halo.BackgroundTransparency = 1
		halo.Size = UDim2.fromScale(1, 1)
		halo.Image = ClanAssets.EyeGlow or ""
		halo.ImageColor3 = color
		halo.ImageTransparency = EYE_GLOW_TRANSPARENCY
		halo.Parent = billboard
		table.insert(entry.Instances, anchor)
		table.insert(entry.Instances, billboard)
		table.insert(entry.Glows, billboard)
	end

	local textured = sharingan and hasEyeVariant(Players:GetPlayerFromCharacter(character), "Sharingan")
	for _, side in { -1, 1 } do
		if not textured then
			local eye = newPart(Vector3.new(0.13, 0.13, 0.13), color)
			eye.Name = "DojutsuEye"
			eye.Shape = Enum.PartType.Ball
			eye.Anchored = false
			eye.Massless = true
			eye.CFrame = head.CFrame * CFrame.new(side * EYE_OFFSET_X, EYE_OFFSET_Y, front - 0.02)
			eye.Parent = getFolder()
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = eye
			weld.Part1 = head
			weld.Parent = eye
			table.insert(entry.Instances, eye)
		end
		-- Estela roja de los ojos (Sharingan): se enciende al moverse rápido
		if sharingan then
			local top = Instance.new("Attachment")
			top.Name = "SharinganTrailTop"
			top.Position = Vector3.new(side * EYE_OFFSET_X, EYE_OFFSET_Y + EYE_TRAIL_HALF_WIDTH, front)
			top.Parent = head
			local bottom = Instance.new("Attachment")
			bottom.Name = "SharinganTrailBottom"
			bottom.Position = Vector3.new(side * EYE_OFFSET_X, EYE_OFFSET_Y - EYE_TRAIL_HALF_WIDTH, front)
			bottom.Parent = head
			local trail = Instance.new("Trail")
			trail.Name = "SharinganTrail"
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Color = ColorSequence.new(SHARINGAN_RED)
			trail.LightEmission = 1
			trail.LightInfluence = 0
			trail.Lifetime = EYE_TRAIL_LIFETIME
			trail.MinLength = 0.05
			trail.FaceCamera = true
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.Enabled = false
			trail.Parent = head
			table.insert(entry.Instances, top)
			table.insert(entry.Instances, bottom)
			table.insert(entry.Instances, trail)
			table.insert(entry.Trails, trail)
		end
	end
	eyes[character] = entry
end

local function ensureEyes(character: Model, kind: string)
	local current = eyes[character]
	if not current or current.Kind ~= kind then
		addEyes(character, kind)
	end
end

-- Destello de los ojos al activarse (lo ven todos)
local function eyeFlash(character: Model)
	local entry = eyes[character]
	local light = entry and entry.Light
	if not light then
		return
	end
	light.Brightness = 2.5
	light.Range = 4
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = EYE_LIGHT_BRIGHTNESS,
		Range = EYE_LIGHT_RANGE,
	}):Play()
	-- Los brillos de los ojos se abren a plena intensidad y vuelven (es lo que ven los demás al
	-- activarlo, así que tiene que leerse bien)
	for _, billboard in entry.Glows do
		billboard.Size = UDim2.fromScale(EYE_GLOW_FLASH_SIZE, EYE_GLOW_FLASH_SIZE)
		TweenService:Create(billboard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(EYE_GLOW_SIZE, EYE_GLOW_SIZE),
		}):Play()
		local halo = billboard:FindFirstChildOfClass("ImageLabel")
		if halo then
			halo.ImageTransparency = 0
			TweenService:Create(halo, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = EYE_GLOW_TRANSPARENCY,
			}):Play()
		end
	end
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
	billboard.Parent = billboardParent

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

type Read = {
	Billboard: BillboardGui,
	Plate: CanvasGroup,
	Holder: Part?,
	Connection: RBXScriptConnection?,
	Ended: boolean,
}
local reads: {[Model]: Read} = {}

local function endRead(caster: Model)
	local read = reads[caster]
	if not read or read.Ended then
		return
	end
	read.Ended = true
	reads[caster] = nil
	if read.Connection then
		read.Connection:Disconnect()
	end
	if read.Holder then
		read.Holder:Destroy()
	end
	TweenService:Create(read.Plate, TweenInfo.new(0.2), { GroupTransparency = 1 }):Play()
	task.delay(0.25, function()
		read.Billboard:Destroy()
	end)
end

local function trajectoryParams(caster: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: {Instance} = { getFolder(), caster }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

local function startRead(data: {[string]: any})
	local caster = data.Caster
	if typeof(caster) ~= "Instance" or not caster:IsA("Model") or not localHas("SharinganActive") then
		return
	end
	local head = caster:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	endRead(caster)

	local startedAt = if typeof(data.StartedAt) == "number" then data.StartedAt else serverNow()
	local castTime = if typeof(data.CastTime) == "number" then data.CastTime else 0.5
	local releaseAt = startedAt + castTime

	-- Placa sobre la cabeza: nombre del jutsu y barra de sellos, con el color de su elemento
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SharinganRead"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(160, 36)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	billboard.MaxDistance = 120
	billboard.Parent = billboardParent

	local plate = Instance.new("CanvasGroup")
	plate.Name = "Plate"
	plate.BackgroundTransparency = 1
	plate.Size = UDim2.fromScale(1, 1)
	plate.GroupTransparency = 1
	plate.Parent = billboard

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Size = UDim2.new(1, -4, 1, -4)
	back.BackgroundColor3 = SHARINGAN_DARK
	back.BackgroundTransparency = 0.12
	back.BorderSizePixel = 0
	back.Parent = plate
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = SHARINGAN_RED
	stroke.Thickness = 1.5
	stroke.Parent = back

	-- Sin icono (los jutsus no tienen): el color del elemento tiñe el borde y la barra
	local nature = typeof(data.NatureId) == "string" and ClanAssets.Natures[data.NatureId]
	local accent = if nature then nature.Color else SHARINGAN_RED
	stroke.Color = accent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(10, 4)
	nameLabel.Size = UDim2.new(1, -20, 0, 16)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextColor3 = Color3.fromRGB(255, 228, 228)
	nameLabel.Text = upper(tostring(data.Name or "?"))
	nameLabel.Parent = back

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(70, 0, 6)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.new(0, 10, 1, -10)
	bar.Size = UDim2.new(1, -20, 0, 4)
	bar.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.clamp((serverNow() - startedAt) / math.max(castTime, 0.05), 0, 1), 1)
	fill.Parent = bar

	TweenService:Create(plate, TweenInfo.new(0.12), { GroupTransparency = 0 }):Play()
	local remaining = math.max(0.05, releaseAt - serverNow())
	local fillTween = TweenService:Create(fill, TweenInfo.new(remaining, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 1),
	})
	fillTween:Play()
	fillTween.Completed:Once(function()
		-- Sale ya: la barra destella
		fill.BackgroundColor3 = Color3.new(1, 1, 1)
		TweenService:Create(fill, TweenInfo.new(0.25), { BackgroundColor3 = accent }):Play()
	end)

	local read: Read = { Billboard = billboard, Plate = plate, Holder = nil, Connection = nil, Ended = false }
	reads[caster] = read

	-- Trayectoria: hacia dónde apuntó al empezar los sellos, tan larga como el alcance del jutsu
	-- (se corta en la primera pared)
	local direction = data.Direction
	local length = math.clamp(if typeof(data.Range) == "number" then data.Range else TRAJECTORY_DEFAULT, 10, TRAJECTORY_MAX)
	local a0: Attachment? = nil
	local a1: Attachment? = nil
	local params: RaycastParams? = nil
	if typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
		direction = direction.Unit
		local holder = newPart(Vector3.one * 0.2, SHARINGAN_RED)
		holder.Name = "SharinganTrajectory"
		holder.Transparency = 1
		holder.Parent = getFolder()
		a0 = Instance.new("Attachment")
		a0.Parent = holder
		a1 = Instance.new("Attachment")
		a1.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 30, 40))
		-- Poca emisión: con 1 se lava a blanco sobre suelos claros
		beam.LightEmission = 0.3
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.75, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Width0 = 1.2
		beam.Width1 = 0.35
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = holder
		read.Holder = holder
		params = trajectoryParams(caster)
	end

	read.Connection = RunService.RenderStepped:Connect(function()
		local now = serverNow()
		-- Se acaba cuando sale el jutsu (o se cancela), o si apagas el Sharingan
		if not caster.Parent or not localHas("SharinganActive")
			or caster:GetAttribute("JutsuCasting") ~= true
			or caster:GetAttribute("JutsuCastToken") ~= data.Token
			or now > releaseAt + 0.35 then
			endRead(caster)
			return
		end
		local root = rootOf(caster)
		if root and read.Holder and a0 and a1 and params then
			local origin = root.Position + Vector3.yAxis * 0.6 + direction * 1.5
			local reach = length
			-- Si viene hacia ti, la línea acaba en ti; y nunca pasa pegada a la cámara (de cerca
			-- taparía media pantalla)
			local localRoot = rootOf(localPlayer.Character)
			if localRoot then
				local along = (localRoot.Position - origin):Dot(direction)
				if along > 0 and along < reach
					and (origin + direction * along - localRoot.Position).Magnitude < 6 then
					reach = along
				end
			end
			local camera = Workspace.CurrentCamera
			if camera then
				local along = (camera.CFrame.Position - origin):Dot(direction)
				if along > 0 and along < reach
					and (origin + direction * along - camera.CFrame.Position).Magnitude < 5 then
					reach = math.max(1, along - 5)
				end
			end
			local hit = Workspace:Raycast(origin, direction * reach, params)
			read.Holder.CFrame = CFrame.new(origin)
			a0.WorldPosition = origin
			a1.WorldPosition = if hit then hit.Position else origin + direction * reach
		end
	end)
end

-- Visión de dōjutsu (Highlights) ---------------------------------------------------------------

local seen: {[Model]: Highlight} = {}

-- throughWalls: Byakugan (se ve a través de todo) · sin él: Sharingan (solo lo que está a la vista)
local function setSeen(character: Model, visible: boolean, fake: boolean?, throughWalls: boolean?)
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
		existing.Name = "DojutsuSight"
		existing.FillTransparency = 0.75
		existing.OutlineTransparency = 0
		existing.Adornee = character
		existing.Parent = getFolder()
		seen[character] = existing
	end
	existing.DepthMode = if throughWalls ~= false
		then Enum.HighlightDepthMode.AlwaysOnTop
		else Enum.HighlightDepthMode.Occluded
	local color = if fake then Color3.fromRGB(255, 80, 80) else BYAKUGAN_WHITE
	existing.FillColor = color
	existing.OutlineColor = color
end

-- ¿Está a la vista? Igual que la lectura del servidor (Genjutsu.canSee): campo visual de 140°
-- según hacia dónde mira tu cuerpo, a distancia (según tus tomoe) y sin paredes
local function inSharinganView(model: Model, position: Vector3, localRoot: BasePart?): boolean
	local localCharacter = localPlayer.Character
	local head = localCharacter and localCharacter:FindFirstChild("Head")
	if not localRoot or not head or not head:IsA("BasePart") then
		return false
	end
	local offset = position - head.Position
	local range = SHARINGAN_CLONE_RANGE_BY_TOMOE[tomoeOf(localCharacter)] or 90
	if offset.Magnitude < 0.1 or offset.Magnitude > range then
		return false
	end
	local look = Vector3.new(localRoot.CFrame.LookVector.X, 0, localRoot.CFrame.LookVector.Z)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if look.Magnitude > 1e-3 and flat.Magnitude > 1e-3 and look.Unit:Dot(flat.Unit) < SHARINGAN_VIEW_DOT then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: {Instance} = { getFolder(), model }
	if localCharacter then
		table.insert(exclude, localCharacter)
	end
	params.FilterDescendantsInstances = exclude
	return Workspace:Raycast(head.Position, offset, params) == nil
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
	sharinganTint.Enabled = sharingan
	setVignette(sharingan)
	local eyeStrain = localPlayer:GetAttribute("MangekyoEyeStrain")
	setEyeStrainView(if sharingan and typeof(eyeStrain) == "number" then eyeStrain else 0)
	setIndicatorShown(sharingan and os.clock() >= indicatorHiddenUntil)
	if sharingan then
		refreshIndicator(emblemKey(localCharacter))
	end

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
		if kind then
			ensureEyes(character, kind)
		elseif eyes[character] then
			removeEyes(character)
		end

		-- Estela de los ojos del Sharingan al moverse rápido
		local entry = eyes[character]
		if entry and #entry.Trails > 0 then
			local root = rootOf(character)
			local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
			local fast = Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= TRAIL_SPEED
			for _, trail in entry.Trails do
				trail.Enabled = fast
			end
		end

		updateMarks(character, now)

		if character ~= localCharacter then
			local root = rootOf(character)
			local distance = if root and localRoot then (root.Position - localRoot.Position).Magnitude else math.huge
			setSeen(character, byakugan and distance <= BYAKUGAN_RANGE)
		end
	end

	-- Clones ilusorios (GenjutsuClient): el Byakugan los marca como falsos a través de todo;
	-- el Sharingan, los que tienes a la vista
	local illusions = Workspace:FindFirstChild("GenjutsuIllusions")
	if illusions then
		for _, clone in illusions:GetChildren() do
			if clone:IsA("Model") then
				alive[clone] = true
				local root = rootOf(clone)
				local close = root ~= nil and localRoot ~= nil
					and (root.Position - localRoot.Position).Magnitude <= BYAKUGAN_RANGE
				local inView = sharingan and root ~= nil and inSharinganView(clone, root.Position, localRoot)
				setSeen(clone, (byakugan and close) or inView, true, byakugan and close)
			end
		end
	end

	-- Sin Sharingan no hay lecturas
	if not sharingan then
		for caster in reads do
			endRead(caster)
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
	for character, markEntry in markGuis do
		if not alive[character] then
			markEntry.Gui:Destroy()
			markGuis[character] = nil
		end
	end
end)

-- Modos: activación y fin ---------------------------------------------------------------------

local MODE_KINDS = {
	SharinganActive = "Sharingan",
	ByakuganActive = "Byakugan",
}

local function modeStart(data: {[string]: any})
	local character = data.Character
	local kind = MODE_KINDS[data.Attribute or ""]
	if typeof(character) ~= "Instance" or not character:IsA("Model") or not kind then
		return
	end
	ensureEyes(character, kind)
	eyeFlash(character)
	if kind == "Sharingan" then
		local own = character == localPlayer.Character
		playSound(character, ClanAssets.Sounds.SharinganActivate, if own then SHARINGAN_SELF_VOLUME else SHARINGAN_SOUND_VOLUME)
		-- Los demás solo ven tus ojos (destello, brillo y estela) y oyen el sonido: nada que
		-- tape la cara en combate
		if own and character:GetAttribute("MangekyoActive") ~= true then
			screenActivation(tomoeOf(character))
		end
	end
end

-- Despertar de una etapa en TU pantalla:
--   1. la pantalla se oscurece y se desenfoca; aparece el iris de la etapa anterior girando
--   2. destello y onda: el iris se transforma en el nuevo (se ve formarse el tomoe nuevo)
--   3. el iris nuevo se queda girando un momento y viaja hasta el indicador de abajo
local AWAKEN_INTRO, AWAKEN_FORM, AWAKEN_HOLD, AWAKEN_EXIT = 0.45, 0.3, 0.6, 0.5
local AWAKEN_SIZE = 160
local AWAKEN_CENTER = UDim2.fromScale(0.5, 0.42)

-- Círculo de pantalla que se abre y se desvanece (destello u onda)
local function screenBurst(fromSize: number, toSize: number, duration: number, color: Color3, filled: boolean)
	local burst = Instance.new("Frame")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = AWAKEN_CENTER
	burst.Size = UDim2.fromOffset(fromSize, fromSize)
	burst.BackgroundColor3 = color
	burst.BackgroundTransparency = if filled then 0.25 else 1
	burst.BorderSizePixel = 0
	burst.ZIndex = 7
	burst.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = burst
	local goal: {[string]: any} = { Size = UDim2.fromOffset(toSize, toSize) }
	if filled then
		goal.BackgroundTransparency = 1
	else
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 5
		stroke.Parent = burst
		TweenService:Create(stroke, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Thickness = 1,
		}):Play()
	end
	TweenService:Create(burst, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), goal):Play()
	task.delay(duration + 0.05, function()
		burst:Destroy()
	end)
end

-- Onda en el suelo alrededor de quien despierta (la ven todos)
local function awakeningRing(character: Model)
	local root = rootOf(character)
	if not root then
		return
	end
	local ring = newPart(Vector3.new(0.12, 3, 3), SHARINGAN_RED)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.45
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = getFolder()
	local tween = TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, 28, 28),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		ring:Destroy()
	end)
end

local function awakeningMoment(stage: any, previousKey: any?)
	-- Al despertar el primer tomoe el Sharingan se activa a la vez: quita su emblema para no duplicar
	for _, child in gui:GetChildren() do
		if child.Name == "SharinganActivationFX" then
			child:Destroy()
		end
	end
	local veil = Instance.new("Frame")
	veil.Name = "SharinganAwakening"
	veil.BackgroundColor3 = Color3.fromRGB(30, 0, 4)
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.Size = UDim2.fromScale(1, 1)
	veil.ZIndex = 5
	veil.Parent = gui
	TweenService:Create(veil, TweenInfo.new(0.25), { BackgroundTransparency = 0.4 }):Play()

	local blur = Instance.new("BlurEffect")
	blur.Name = "SharinganAwakeningBlur"
	blur.Size = 0
	blur.Parent = Lighting
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = 10 }):Play()

	local total = AWAKEN_INTRO + AWAKEN_FORM + AWAKEN_HOLD + AWAKEN_EXIT
	awakeningUntil = os.clock() + total
	-- El indicador no se ve hasta que el iris del despertar baje a ocupar su sitio
	indicatorHiddenUntil = os.clock() + total + 0.1
	setIndicatorShown(false)
	local function emblemFor(tomoe: any): GuiObject
		local emblem = makeEmblem(UDim2.fromOffset(AWAKEN_SIZE, AWAKEN_SIZE), tomoe)
		emblem.Position = AWAKEN_CENTER
		emblem.ZIndex = 6
		emblem[fadeKey(emblem)] = 1
		emblem.Parent = gui
		-- Gira todo el rato y frena al final
		TweenService:Create(emblem, TweenInfo.new(total, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Rotation = 720,
		}):Play()
		return emblem
	end

	-- 1. Entrada: el iris de antes (con 1 tomoe no hay iris anterior: entra el nuevo directamente)
	local previous = if previousKey ~= nil then emblemFor(previousKey)
		elseif typeof(stage) == "number" and stage > 1 then emblemFor(stage - 1)
		else nil
	local emblem = emblemFor(stage)
	local first = previous or emblem
	first.Size = UDim2.fromOffset(AWAKEN_SIZE * 0.6, AWAKEN_SIZE * 0.6)
	TweenService:Create(first, TweenInfo.new(AWAKEN_INTRO, Enum.EasingStyle.Back, Enum.EasingDirection.Out), fadeGoal(first, 0, {
		Size = UDim2.fromOffset(AWAKEN_SIZE, AWAKEN_SIZE),
	})):Play()

	-- 2. Se forma el tomoe nuevo: destello, onda y cambio de iris con un golpe de tamaño
	task.delay(AWAKEN_INTRO, function()
		if not emblem.Parent then
			return
		end
		screenBurst(AWAKEN_SIZE, AWAKEN_SIZE * 2.6, 0.45, Color3.fromRGB(255, 90, 90), true)
		screenBurst(AWAKEN_SIZE, AWAKEN_SIZE * 3.4, 0.6, SHARINGAN_RED, false)
		if previous then
			TweenService:Create(previous, TweenInfo.new(AWAKEN_FORM), fadeGoal(previous, 1)):Play()
		end
		emblem.Size = UDim2.fromOffset(AWAKEN_SIZE * 1.3, AWAKEN_SIZE * 1.3)
		TweenService:Create(emblem, TweenInfo.new(AWAKEN_FORM * 0.4), fadeGoal(emblem, 0)):Play()
		TweenService:Create(emblem, TweenInfo.new(AWAKEN_FORM + 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(AWAKEN_SIZE * 1.1, AWAKEN_SIZE * 1.1),
		}):Play()
	end)

	-- 3. Salida: el iris viaja al indicador de abajo y la pantalla vuelve
	task.delay(AWAKEN_INTRO + AWAKEN_FORM + AWAKEN_HOLD, function()
		TweenService:Create(veil, TweenInfo.new(AWAKEN_EXIT), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(blur, TweenInfo.new(AWAKEN_EXIT), { Size = 0 }):Play()
		if emblem.Parent then
			landOnIndicator(emblem, stage, AWAKEN_EXIT)
		end
	end)
	task.delay(total + 0.05, function()
		veil:Destroy()
		blur:Destroy()
		if previous then
			previous:Destroy()
		end
	end)
end

local function awakened(data: {[string]: any})
	local stage = if typeof(data.Stage) == "number" then math.clamp(math.floor(data.Stage), 1, 3) else 1
	local character = data.Character
	local isCharacter = typeof(character) == "Instance" and character:IsA("Model")
	if data.Player == localPlayer then
		awakeningMoment(stage)
	end
	if isCharacter then
		eyeFlash(character)
		awakeningRing(character)
		playSound(character, ClanAssets.Sounds.SharinganAwaken, if data.Player == localPlayer then SHARINGAN_SELF_AWAKEN_VOLUME else 1, 90)
	end
end

-- Mangekyō despertado: el mismo momento de despertar, del iris de 3 tomoe al Mangekyō
local function mangekyoAwakened(data: {[string]: any})
	local kind = if typeof(data.Type) == "string" then data.Type else "Itachi"
	local character = data.Character
	local isCharacter = typeof(character) == "Instance" and character:IsA("Model")
	if data.Player == localPlayer then
		awakeningMoment(kind, 3)
	end
	if isCharacter then
		eyeFlash(character)
		awakeningRing(character)
		playSound(character, ClanAssets.Sounds.SharinganAwaken, if data.Player == localPlayer then SHARINGAN_SELF_AWAKEN_VOLUME else 1, 120)
	end
end

-- Mangekyō encendido (doble Z): tu pantalla hace la activación con su iris; los demás ven tus ojos
local function mangekyoStart(data: {[string]: any})
	local character = data.Character
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	local own = character == localPlayer.Character
	eyeFlash(character)
	playSound(character, ClanAssets.Sounds.SharinganActivate, if own then SHARINGAN_SELF_VOLUME else SHARINGAN_SOUND_VOLUME)
	if own then
		screenActivation(if typeof(data.Type) == "string" then data.Type else emblemKey(character))
	end
end

local function modeEnd(data: {[string]: any})
	if data.Attribute == "SharinganActive" and data.Character == localPlayer.Character then
		screenDeactivation()
	end
end

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
		billboard.Parent = billboardParent
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

-- Indicador de clash (Sharingan) ---------------------------------------------------------------
-- Con el Sharingan activo ves venir los proyectiles enemigos (kunai, shuriken, senbon…) desde
-- cualquier dirección: icono de peligro con una flecha alrededor del centro de la pantalla que
-- señala de dónde vienen (también de espaldas). Cuando pulsar G haría el contraataque (la MISMA
-- comprobación que ThrowController: arma seleccionada, munición, cooldown, bloqueos, amenaza dentro
-- de Config.CounterWindow e intercepción posible) cambia al icono de clash; en gris si estás en la
-- ventana pero sin arma, sin munición, en cooldown o bloqueado. Más tomoe = lo ves venir antes.
-- No esquiva nada solo: solo te dice cuándo.

local throwablesFolder = ReplicatedStorage:WaitForChild("Throwables")
local ThrowConfig = require(throwablesFolder:WaitForChild("Config"))
local ThrowDefinitions = require(throwablesFolder:WaitForChild("Definitions"))
local ClientShots = require(throwablesFolder:WaitForChild("ClientShots"))

local CLASH_WARNING_BY_TOMOE = { 1.0, 1.3, 1.6 } -- segundos antes del impacto
local CLASH_WARNING_RADIUS = 4.5 -- el proyectil pasa a ≤ esto de ti
local CLASH_RING_SCALE = 0.2 -- radio del anillo = 20 % del alto de pantalla (fuera del cuerpo)
local CLASH_RING_MIN, CLASH_RING_MAX = 104, 190 -- px
local CLASH_UPDATE_INTERVAL = 1 / 30

-- Lo mismo que bloquea el contraataque en ThrowController
local CLASH_BLOCKING_ATTRIBUTES = {
	"CombatSuppressed", "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting", "IsCarrying",
	"IsStunned", "Status_AttackBlocked", "Status_Stunned", "IsBlocking", "IsAttacking", "IsDashing",
	"TreeJumpActive", "IsTreeJumping",
}

-- Tiempo hasta soltar el arma en el contraataque (frame Release / velocidad del contraataque)
local COUNTER_RELEASE_DELAY = (ThrowConfig.ReleaseFrame / ThrowConfig.AnimationFps) / ThrowConfig.CounterAnimationSpeed

local clashFrame = Instance.new("Frame")
clashFrame.Name = "ClashIndicator"
clashFrame.AnchorPoint = Vector2.new(0.5, 0.5)
clashFrame.Position = UDim2.fromScale(0.5, 0.5)
clashFrame.Size = UDim2.fromOffset(0, 0)
clashFrame.BackgroundTransparency = 1
clashFrame.Visible = false
clashFrame.ZIndex = 8
clashFrame.Parent = gui

local function clashBadge(iconName: string, size: number): CanvasGroup
	local group = Instance.new("CanvasGroup")
	group.Name = iconName
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Size = UDim2.fromOffset(size, size)
	group.BackgroundTransparency = 1
	group.Visible = false
	group.Parent = clashFrame
	makeBadge(ClanAssets.Icons[iconName], UDim2.fromScale(0.86, 0.86)).Parent = group
	local scale = Instance.new("UIScale")
	scale.Parent = group
	return group
end

-- Sin contraataque disponible (sin arma, munición o en cooldown): el mismo icono de la ventana,
-- en gris (no hace falta un icono propio)
local CLASH_ICON_BY_STATE = {
	Danger = "Danger",
	Ready = "ClashWindow",
	Unavailable = "ClashWindow",
}
local CLASH_UNAVAILABLE_TINT = Color3.fromRGB(110, 110, 110)

local clashBadges: {[string]: CanvasGroup} = {}
for state, iconName in CLASH_ICON_BY_STATE do
	clashBadges[state] = clashBadge(iconName, if state == "Ready" then 44 else 36)
end
clashBadges.Unavailable.Name = "ClashUnavailable"
for _, descendant in clashBadges.Unavailable:GetDescendants() do
	if descendant:IsA("ImageLabel") then
		descendant.ImageColor3 = CLASH_UNAVAILABLE_TINT
	elseif descendant:IsA("TextLabel") then
		descendant.TextColor3 = CLASH_UNAVAILABLE_TINT
	elseif descendant:IsA("UIStroke") then
		descendant.Color = CLASH_UNAVAILABLE_TINT
	end
end

-- Flecha que señala de dónde viene (imagen de ClanAssets o el glifo, sin círculo)
local clashArrow: GuiObject
do
	local arrowIcon = ClanAssets.Icons.ClashArrow
	if arrowIcon.Image ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = arrowIcon.Image
		image.ScaleType = Enum.ScaleType.Fit
		clashArrow = image
	else
		local glyph = Instance.new("TextLabel")
		glyph.Text = arrowIcon.Glyph
		glyph.TextScaled = true
		glyph.Font = Enum.Font.GothamBold
		glyph.TextColor3 = arrowIcon.Color
		glyph.TextStrokeColor3 = Color3.new(0, 0, 0)
		glyph.TextStrokeTransparency = 0
		clashArrow = glyph
	end
	clashArrow.Name = "ClashArrow"
	clashArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	clashArrow.Size = UDim2.fromOffset(24, 24)
	clashArrow.BackgroundTransparency = 1
	clashArrow.Parent = clashFrame
end

local function selectedWeapon(): string?
	local slot = localPlayer:GetAttribute("NinjaBagSelectedSlot")
	slot = if typeof(slot) == "number" and slot >= 1 and slot <= ThrowConfig.SlotCount then math.floor(slot) else 1
	local weapon = localPlayer:GetAttribute("NinjaBagSlot" .. slot .. "Projectile")
	return if typeof(weapon) == "string" and typeof(ThrowDefinitions[weapon]) == "table" then weapon else nil
end

-- Desde dónde sale el arma (igual que ThrowController)
local function throwOrigin(character: Model, weapon: string, root: BasePart): Vector3
	local explicit = character:FindFirstChild(weapon .. "ThrowOrigin", true)
	if explicit and explicit:IsA("Attachment") then
		return explicit.WorldPosition
	end
	local hand = character:FindFirstChild("LeftHand")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	local arm = character:FindFirstChild("Left Arm")
	if arm and arm:IsA("BasePart") then
		return arm.Position - arm.CFrame.UpVector * (arm.Size.Y * 0.28) + arm.CFrame.LookVector * 0.12
	end
	return root.Position
end

-- "None" · "Danger" (viene algo) · "Ready" (G haría el contraataque) · "Unavailable" (en la
-- ventana, pero sin arma, sin munición, en cooldown o bloqueado). Devuelve también la amenaza.
local function computeClash(character: Model, root: BasePart): (string, any?)
	local threat = ClientShots.findThreat(root.Position, CLASH_WARNING_BY_TOMOE[tomoeOf(character)] or 1, CLASH_WARNING_RADIUS)
	if not threat then
		return "None", nil
	end
	if not ThrowConfig.CounterEnabled or threat.TimeToImpact > ThrowConfig.CounterWindow then
		return "Danger", threat
	end
	local counterThreat = ClientShots.findThreat(root.Position, ThrowConfig.CounterWindow, ThrowConfig.CounterThreatRadius)
	if not counterThreat or counterThreat.TimeToImpact <= COUNTER_RELEASE_DELAY + 0.03 then
		return "Danger", threat
	end
	local weapon = selectedWeapon()
	local definition = if weapon then ThrowDefinitions[weapon] else nil
	local amount = if weapon then localPlayer:GetAttribute("NinjaBagAmount_" .. weapon) else nil
	local cooldownEnds = if weapon then character:GetAttribute("CoreCooldown_" .. weapon .. "_EndsAt") else nil
	local blocked = localPlayer:GetAttribute("NinjaBagLoadoutOpen") == true
		or localPlayer:GetAttribute("NinjaBagRadialOpen") == true
	for _, name in CLASH_BLOCKING_ATTRIBUTES do
		if character:GetAttribute(name) == true then
			blocked = true
			break
		end
	end
	if not weapon or not definition or definition.NoCounter or not definition.CounterSpeed
		or typeof(amount) ~= "number" or amount <= 0
		or (typeof(cooldownEnds) == "number" and cooldownEnds > serverNow())
		or blocked then
		return "Unavailable", counterThreat
	end
	local intercept = ClientShots.solveIntercept(
		counterThreat.Entry,
		throwOrigin(character, weapon, root),
		serverNow() + COUNTER_RELEASE_DELAY,
		definition.CounterSpeed,
		counterThreat.ImpactTime - ThrowConfig.CounterSafety
	)
	return if intercept then "Ready" else "Danger", counterThreat
end

local clashCurrent = "None"
local clashThreat: any = nil
local clashAccumulator = 0

local function setClash(state: string, threat: any?)
	local previous = clashCurrent
	clashCurrent = state
	clashThreat = threat
	clashFrame.Visible = state ~= "None"
	for name, badge in clashBadges do
		badge.Visible = name == state
	end
	if state == previous then
		return
	end
	-- La flecha toma el color del estado: peligro, ventana o sin contraataque
	local stateIcon = ClanAssets.Icons[CLASH_ICON_BY_STATE[state] or ""]
	if stateIcon then
		local arrowColor = if state == "Unavailable" then CLASH_UNAVAILABLE_TINT else stateIcon.Color
		if clashArrow:IsA("ImageLabel") then
			(clashArrow :: ImageLabel).ImageColor3 = arrowColor
		elseif clashArrow:IsA("TextLabel") then
			(clashArrow :: TextLabel).TextColor3 = arrowColor
		end
	end
	local character = localPlayer.Character
	if state == "Ready" then
		-- Se abre la ventana: el icono late
		local scale = clashBadges.Ready:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.4
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		if character then
			playSound(character, ClanAssets.Sounds.ClashWindow, 0.8)
		end
	elseif previous == "None" and character then
		playSound(character, ClanAssets.Sounds.ClashDanger, 0.6)
	end
end

-- Coloca el icono y la flecha en el anillo hacia donde está el proyectil respecto a la cámara
-- (arriba = delante, abajo = detrás)
local function placeClash(position: Vector3, root: BasePart)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local offset = position - root.Position
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if look.Magnitude < 1e-3 or right.Magnitude < 1e-3 then
		return
	end
	local angle = math.atan2(offset:Dot(right.Unit), offset:Dot(look.Unit))
	local x, y = math.sin(angle), -math.cos(angle)
	local radius = math.clamp(camera.ViewportSize.Y * CLASH_RING_SCALE, CLASH_RING_MIN, CLASH_RING_MAX)
	for _, badge in clashBadges do
		badge.Position = UDim2.fromOffset(x * radius, y * radius)
	end
	clashArrow.Position = UDim2.fromOffset(x * (radius + 30), y * (radius + 30))
	clashArrow.Rotation = math.deg(angle)
end

RunService.RenderStepped:Connect(function(dt)
	local character = localPlayer.Character
	local root = rootOf(character)
	if not character or not root or not localHas("SharinganActive") then
		if clashCurrent ~= "None" then
			setClash("None", nil)
		end
		return
	end
	clashAccumulator += dt
	if clashAccumulator >= CLASH_UPDATE_INTERVAL then
		clashAccumulator = 0
		local ok, state, threat = pcall(computeClash, character, root)
		if ok then
			setClash(state, threat)
		end
	end
	if clashCurrent ~= "None" and clashThreat then
		local ok, position = pcall(ClientShots.currentPosition, clashThreat.Entry)
		if ok and typeof(position) == "Vector3" then
			placeClash(position, root)
		end
	end
end)

-- Genjutsu: Sharingan y romper sellos ---------------------------------------------------------

-- Texto breve sobre un personaje (lo ven todos): sube un poco y se desvanece
local function worldText(character: Model?, text: string)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ClanWorldText"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(180, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 120
	billboard.Parent = billboardParent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(255, 225, 225)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.95, function()
		billboard:Destroy()
	end)
end

-- Aviso de Genjutsu: Sharingan: suena el Sharingan desde quien lo lanza y sus ojos brillan.
-- Sin nada en pantalla: oírlo (o verle los ojos) es la pista para apartar la mirada.
local function windup(data: {[string]: any})
	local character = data.Character
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	eyeFlash(character)
	playSound(character, ClanAssets.Sounds.SharinganGenjutsu, 1, 110)
end

-- Entró el genjutsu (lo ven todos): destello en los ojos de quien lo lanza y, sobre la víctima,
-- su Sharingan en el suelo, un aura roja tenue y la pose congelada mientras dure (InGenjutsu)
local BIND_SEAL_SIZE = 6 -- studs del Sharingan del suelo
local BIND_SEAL_DROP = 2.95 -- studs por debajo del HumanoidRootPart (los pies en R6)
local BIND_SEAL_TRANSPARENCY = 0.35
local BIND_AURA_FILL = 0.82
local BIND_AURA_OUTLINE = 0.5
local BIND_TIMEOUT = 4 -- respaldo por si no llega el fin

local function bindBurst(data: {[string]: any})
	if typeof(data.Character) == "Instance" and data.Character:IsA("Model") then
		eyeFlash(data.Character)
	end
	local target = data.Target
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	local root = rootOf(target)
	if not root then
		return
	end
	local tomoe = if typeof(data.Tomoe) == "number" then math.clamp(math.floor(data.Tomoe), 1, 3) else 3

	-- 1. El Sharingan de quien lo atrapó, en el suelo bajo sus pies, girando despacio
	local seal = newPart(Vector3.new(BIND_SEAL_SIZE, 0.05, BIND_SEAL_SIZE), Color3.new(0, 0, 0))
	seal.Name = "SharinganBindSeal"
	seal.Transparency = 1
	seal.CFrame = CFrame.new(root.Position - Vector3.new(0, BIND_SEAL_DROP, 0))
	seal.Parent = getFolder()
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = (ClanAssets.SharinganIris and ClanAssets.SharinganIris[tomoe]) or ""
	decal.Transparency = 1
	decal.Parent = seal
	TweenService:Create(decal, TweenInfo.new(0.2), { Transparency = BIND_SEAL_TRANSPARENCY }):Play()

	-- 2. Aura roja tenue sobre su cuerpo
	local aura = Instance.new("Highlight")
	aura.Name = "SharinganBindAura"
	aura.Adornee = target
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.FillColor = SHARINGAN_RED
	aura.OutlineColor = Color3.fromRGB(255, 70, 70)
	aura.FillTransparency = 1
	aura.OutlineTransparency = 1
	aura.Parent = target
	TweenService:Create(aura, TweenInfo.new(0.2), {
		FillTransparency = BIND_AURA_FILL,
		OutlineTransparency = BIND_AURA_OUTLINE,
	}):Play()

	-- 3. Pose congelada (solo en tu pantalla; hasta tener una animación propia de paralizado)
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
			and (elapsed < 0.25 or target:GetAttribute("InGenjutsu") == "GenjutsuSharingan")
		if held then
			angle += dt * 40
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

-- Ver la sustitución (Sharingan 2+ tomoe / Byakugan, solo tú): mientras el enemigo va invisible
-- tras sustituirse, deja remanentes translúcidos de su cuerpo cada poco: ves hacia dónde va, pero
-- no exactamente dónde está.
local AFTERIMAGE_INTERVAL = 0.11 -- s entre remanentes
local AFTERIMAGE_FADE = 0.5 -- s que tarda cada uno en desaparecer
local AFTERIMAGE_TRANSPARENCY = 0.62
local AFTERIMAGE_COLORS = {
	Sharingan = Color3.fromRGB(210, 20, 30),
	Byakugan = Color3.fromRGB(215, 225, 255),
}

local function spawnAfterimage(character: Model, color: Color3)
	local folder = getFolder()
	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") or part.Name == "HumanoidRootPart" or part.Transparency >= 0.95 then
			continue
		end
		local ok, ghost = pcall(function()
			return part:Clone()
		end)
		if not ok or not ghost then
			continue
		end
		for _, child in ghost:GetChildren() do
			if child:IsA("DataModelMesh") then
				if child:IsA("SpecialMesh") then
					child.TextureId = ""
				end
			else
				child:Destroy()
			end
		end
		if ghost:IsA("MeshPart") then
			ghost.TextureID = ""
		end
		ghost.Name = "SubstitutionAfterimage"
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.CastShadow = false
		ghost.Material = Enum.Material.Neon
		ghost.Color = color
		ghost.Transparency = AFTERIMAGE_TRANSPARENCY
		ghost.LocalTransparencyModifier = 0
		ghost.CFrame = part.CFrame
		ghost.Parent = folder
		local tween = TweenService:Create(ghost, TweenInfo.new(AFTERIMAGE_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			ghost:Destroy()
		end)
	end
end

local function substitutionRead(data: {[string]: any})
	local target = data.Character
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target.Parent then
		return
	end
	local duration = if typeof(data.Duration) == "number" then data.Duration else 0.65
	local color = AFTERIMAGE_COLORS[data.Kind or ""] or AFTERIMAGE_COLORS.Sharingan
	task.spawn(function()
		local endsAt = os.clock() + duration
		-- El primero sale ya, donde se sustituyó; luego mientras siga invisible
		repeat
			spawnAfterimage(target, color)
			task.wait(AFTERIMAGE_INTERVAL)
		until os.clock() >= endsAt or not target.Parent or target:GetAttribute("SubstitutionHidden") ~= true
	end)
end

-- Genjutsu Kaeshi: el genjutsu rebota a quien lo lanzó (lo ven todos)
local function reflected(data: {[string]: any})
	if typeof(data.Character) == "Instance" and data.Character:IsA("Model") then
		eyeFlash(data.Character)
	end
	worldText(data.Target, "REFLECTED")
end

-- Pantalla del atrapado por Genjutsu: Sharingan: todo se oscurece y solo ve el Sharingan de quien lo
-- atrapó (con sus tomoe) acercándose a la cámara. Al soltarse, el Sharingan se desvanece y la vista
-- vuelve poco a poco (oscuridad, color y enfoque) en una ventana corta.
local PARALYSIS_DARKNESS = 0.04 -- transparencia del negro mientras dura (0 = negro total)
local PARALYSIS_START_SIZE = 90 -- px del Sharingan al empezar
local PARALYSIS_END_SCALE = 0.9 -- al final ocupa esta fracción del lado corto de la pantalla
local PARALYSIS_EXIT = 0.7 -- s en recuperar la vista

type Paralysis = { Id: number, Frame: Frame, Emblem: GuiObject, Color: ColorCorrectionEffect, Blur: BlurEffect }
local paralysis: Paralysis? = nil

-- Capa propia por encima de todo el HUD (cooldowns, etiqueta de combate…): solo se ve el Sharingan
local paralysisGui = Instance.new("ScreenGui")
paralysisGui.Name = "ClanParalysis"
paralysisGui.IgnoreGuiInset = true
paralysisGui.ResetOnSpawn = false
paralysisGui.DisplayOrder = 500
paralysisGui.Parent = localPlayer:WaitForChild("PlayerGui")

local function stopParalysis(id: number?)
	local current = paralysis
	if not current or (id ~= nil and current.Id ~= id) then
		return
	end
	paralysis = nil
	-- El Sharingan se va primero; la oscuridad, el color y el enfoque vuelven detrás
	TweenService:Create(current.Emblem, TweenInfo.new(PARALYSIS_EXIT * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), fadeGoal(current.Emblem, 1)):Play()
	TweenService:Create(current.Frame, TweenInfo.new(PARALYSIS_EXIT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(current.Color, TweenInfo.new(PARALYSIS_EXIT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Saturation = 0,
		Brightness = 0,
	}):Play()
	TweenService:Create(current.Blur, TweenInfo.new(PARALYSIS_EXIT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = 0,
	}):Play()
	task.delay(PARALYSIS_EXIT + 0.05, function()
		current.Frame:Destroy()
		current.Emblem:Destroy()
		current.Color:Destroy()
		current.Blur:Destroy()
	end)
end

local function startParalysis(id: number, duration: number, tomoe: number)
	stopParalysis(nil)
	local frame = Instance.new("Frame")
	frame.Name = "SharinganParalysis"
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 20
	frame.Parent = paralysisGui
	TweenService:Create(frame, TweenInfo.new(0.12), { BackgroundTransparency = PARALYSIS_DARKNESS }):Play()

	-- El Sharingan del atacante, pequeño en el centro, se acerca a la cámara mientras gira despacio
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local endSize = math.min(viewport.X, viewport.Y) * PARALYSIS_END_SCALE
	local emblem = makeEmblem(UDim2.fromOffset(PARALYSIS_START_SIZE, PARALYSIS_START_SIZE), math.clamp(tomoe, 1, 3))
	emblem.Name = "SharinganParalysisEye"
	emblem.Position = UDim2.fromScale(0.5, 0.5)
	emblem.ZIndex = 21
	emblem[fadeKey(emblem)] = 1
	emblem.Parent = paralysisGui
	TweenService:Create(emblem, TweenInfo.new(0.2), fadeGoal(emblem, 0)):Play()
	TweenService:Create(emblem, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(endSize, endSize),
	}):Play()
	TweenService:Create(emblem, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Rotation = 120 }):Play()

	-- Debajo del negro el mundo queda sin color y desenfocado: al soltarse vuelve poco a poco
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "SharinganParalysis"
	color.Saturation = -1
	color.Brightness = -0.15
	color.Parent = Lighting
	local blur = Instance.new("BlurEffect")
	blur.Name = "SharinganParalysisBlur"
	blur.Size = 14
	blur.Parent = Lighting

	paralysis = { Id = id, Frame = frame, Emblem = emblem, Color = color, Blur = blur }
	-- Respaldo por si no llega el End
	task.delay(duration + 0.5, function()
		stopParalysis(id)
	end)
end

-- El genjutsu lo anuncia TechniqueKit > Genjutsu por GenjutsuFX (Start / End con Id)
task.spawn(function()
	local genjutsuRemote = ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild("GenjutsuFX")
	genjutsuRemote.OnClientEvent:Connect(function(action: string, data: any)
		if typeof(data) ~= "table" then
			return
		end
		if action == "Start" and data.Kind == "GenjutsuSharingan" then
			local visual = if typeof(data.Visual) == "table" then data.Visual else {}
			startParalysis(
				data.Id,
				if typeof(data.Duration) == "number" then data.Duration else 1.2,
				if typeof(visual.Tomoe) == "number" then visual.Tomoe else 3
			)
		elseif action == "End" then
			stopParalysis(data.Id)
		end
	end)
end)

localPlayer.CharacterAdded:Connect(function()
	stopParalysis(nil)
end)

-- Entrada ------------------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(action: string, data: any)
	if typeof(data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if action == "SharinganRead" then
			startRead(data)
		elseif action == "ModeStart" then
			modeStart(data)
		elseif action == "ModeEnd" then
			modeEnd(data)
		elseif action == "ClanAwakened" then
			awakened(data)
		elseif action == "MangekyoAwakened" then
			mangekyoAwakened(data)
		elseif action == "MangekyoStart" then
			mangekyoStart(data)
		elseif action == "MangekyoEnd" then
			-- El indicador vuelve solo al iris de tomoe (escaneo)
		elseif action == "SharinganWindup" then
			windup(data)
		elseif action == "SharinganBind" then
			bindBurst(data)
		elseif action == "SubstitutionRead" then
			substitutionRead(data)
		elseif action == "GenjutsuReflected" then
			reflected(data)
		elseif action == "Copied" then
			showCopied(data)
		elseif action == "CopyCleared" then
			clearCopied()
		elseif action == "ShadowStart" then
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
			-- Sin aviso: ya se ve el iris cerrándose y la barra de chakra vacía
		elseif action == "Icon" and typeof(data.Icon) == "string" then
			personalNotice(data)
		elseif action == "Notice" and typeof(data.Text) == "string" then
			showNotice(data.Text)
		end
	end)
	if not ok then
		warn("[ClanClient] " .. tostring(action) .. ": " .. tostring(err))
	end
end)
