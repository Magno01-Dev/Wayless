--!strict
-- SusanooClient (StarterPlayer > StarterPlayerScripts)
-- Muestra el Susanoo imperfecto de cada jugador y maneja el combo del brazo del jugador local.
--
-- Qué se ve (atributos del personaje que publica el servidor):
--   SusanooActive                       → costillas + brazo (modo Susanoo, Z mantenida)
--   MangekyoActive + BlockStartedAt      → solo las costillas mientras bloquea (bloqueo 360°); con
--                                          escudo también el brazo, en guardia (modo Guard)
--   MangekyoColor                        → color propio (ReplicatedStorage > Shared > MangekyoCatalog)
--   SusanooRemote "Yasaka"               → Yasaka no Magatama: si no hay Susanoo sale solo el brazo
--                                          (modo Arm) el tiempo de la animación; el arma se esconde
--                                          mientras la mano sostiene los magatama
--   MangekyoWeapon                       → arma del brazo: las piezas de la carpeta Weapons del rig
--                                          llevan el atributo SusanooWeapon y solo queda la que toca
-- El modelo es una copia local del rig (SusanooConfig.Sides[Side].Model) soldada al
-- HumanoidRootPart; las animaciones se reproducen con el Animator de su RenderHumanoid (el Humanoid
-- inerte da el contorno claro de la Highlight; un AnimationController al lado no animaría).
-- Aura: Beams y partículas del modelo. Atributos de los efectos:
--   SusanooArm   → solo con el modo Susanoo (no con el bloqueo de costillas)
--   SusanooBack  → se apagan en tu propio Susanoo (la cámara está detrás y taparían la vista)
--
-- Combo: con el modo Susanoo, Mouse1 lo maneja este script (AttackController lo ignora). Cada arma
-- tiene el suyo (SusanooConfig.Weapons). El golpe se anima al instante en local y se pide a
-- SusanooServer, que valida, lo muestra a los demás y resuelve el impacto con CombatInternal >
-- ExternalMeleeHit. El contraataque del escudo lo decide el servidor ("Counter").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local player = Players.LocalPlayer

local susanooFolder = ReplicatedStorage:WaitForChild("Susanoo")
local Config = require(susanooFolder:WaitForChild("SusanooConfig") :: ModuleScript) :: any
local side = (Config.Sides and Config.Sides[Config.Side]) or Config
local template = susanooFolder:WaitForChild(side.Model or "Imperfect") :: Model
local sequences = susanooFolder:WaitForChild(side.AnimationFolder or "Animations")
local animationIds = side.AnimationIds or Config.AnimationIds
local remote = susanooFolder:WaitForChild("SusanooRemote") :: RemoteEvent
local MangekyoCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MangekyoCatalog")) :: any

local RIBS_FADE = 0.12
-- Diagnóstico: true escribe en la consola por qué sale o no cada golpe del Susanoo
local DEBUG = false
local function debugLog(...)
	if DEBUG then
		print("[SusanooClient]", ...)
	end
end
local ARM_PART_NAMES = { UpperArm = true, Forearm = true, Hand = true }

local visualsFolder = Instance.new("Folder")
visualsFolder.Name = "SusanooVisuals"
visualsFolder.Parent = workspace

type Mode = "Ribs" | "Guard" | "Full" | "Arm"

type Visual = {
	Character: Model,
	Model: Model,
	IsLocal: boolean,
	Weapon: string,
	Mode: Mode?,
	Parts: { BasePart },
	ArmParts: { [BasePart]: boolean },
	BaseTransparency: { [BasePart]: number },
	Emitters: { ParticleEmitter },
	BaseRate: { [ParticleEmitter]: number },
	Beams: { Beam },
	BeamBase: { [Beam]: NumberSequence },
	ArmFx: { [Instance]: boolean },
	BackFx: { [Instance]: boolean },
	ArmFade: NumberValue,
	BodyFade: NumberValue,
	Highlight: Highlight?,
	Light: PointLight?,
	Animator: Animator?,
	Tracks: { [string]: AnimationTrack },
	Removing: boolean,
	HoldUntil: number?, -- modo Arm temporal (Yasaka no Magatama) aunque no toque Susanoo
	WeaponHiddenUntil: number?,
}

local visuals: { [Model]: Visual } = {}

-- Animaciones -----------------------------------------------------------------------------------

local temporaryIds: { [string]: string } = {}

local function animationIdFor(name: string): string?
	local id = animationIds[name]
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	-- Sin id publicado: en Studio se registra la KeyframeSequence (solo funciona en Studio)
	if not RunService:IsStudio() then
		return nil
	end
	if temporaryIds[name] then
		return temporaryIds[name]
	end
	local sequence = sequences:FindFirstChild(Config.AnimationSequences[name] or "")
	if not sequence or not sequence:IsA("KeyframeSequence") then
		return nil
	end
	local ok, result = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	if ok and typeof(result) == "string" then
		temporaryIds[name] = result
		return result
	end
	warn("[SusanooClient] could not register animation", name, result)
	return nil
end

local function loadTrack(visual: Visual, name: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local existing = visual.Tracks[name]
	if existing then
		return existing
	end
	local animator = visual.Animator
	local id = animationIdFor(name)
	if not animator or not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		debugLog("could not load", name, id, track)
		return nil
	end
	debugLog("loaded", name, id, "length", track.Length)
	track.Priority = priority
	track.Looped = looped
	visual.Tracks[name] = track
	return track
end

-- Modelo ----------------------------------------------------------------------------------------

local function isArmPart(part: BasePart, model: Model): boolean
	if ARM_PART_NAMES[part.Name] or part:GetAttribute("SusanooWeapon") ~= nil then
		return true
	end
	if string.match(part.Name, "^%a+%d$") and part.Parent == model and part.Name ~= "Ribcage" then
		return true -- falanges: Index1, Thumb2...
	end
	local folder = model:FindFirstChild("LeftArmVisual") or model:FindFirstChild("RightArmVisual")
	return folder ~= nil and part:IsDescendantOf(folder)
end

-- Color propio del Mangekyō de este personaje (MangekyoCatalog.Colors)
local function paletteOf(character: Model): any
	local name = character:GetAttribute("MangekyoColor")
	return (typeof(name) == "string" and MangekyoCatalog.Colors[name])
		or MangekyoCatalog.Colors[MangekyoCatalog.DefaultColor]
end

local function weaponOf(character: Model): string
	local name = character:GetAttribute("MangekyoWeapon")
	return if typeof(name) == "string" and MangekyoCatalog.Weapons[name] then name else MangekyoCatalog.DefaultWeapon
end

local function comboOf(character: Model): { any }
	return Config.weapon(weaponOf(character)).Combo
end

local function applyColor(visual: Visual)
	local palette = paletteOf(visual.Character)
	local color = palette.Skeleton
	-- llamas: punta más clara que el esqueleto
	local auraColor = ColorSequence.new(palette.Glow, palette.Core)
	for _, part in visual.Parts do
		part.Color = color
	end
	for _, emitter in visual.Emitters do
		emitter.Color = auraColor
	end
	for _, beam in visual.Beams do
		beam.Color = auraColor
	end
	if visual.Highlight then
		visual.Highlight.FillColor = color
		visual.Highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.55)
	end
	if visual.Light then
		visual.Light.Color = color
	end
end

-- Transparencia de un Beam según la opacidad (0 = invisible, 1 = la del modelo)
local function scaled(base: NumberSequence, opacity: number): NumberSequence
	local points = {}
	for _, k in base.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(k.Time, 1 - (1 - k.Value) * opacity))
	end
	return NumberSequence.new(points)
end

local function refreshBeams(visual: Visual)
	local mul = if visual.IsLocal then Config.LocalAuraOpacity else 1
	for _, beam in visual.Beams do
		local fade = if visual.ArmFx[beam] then visual.ArmFade.Value else visual.BodyFade.Value
		beam.Enabled = fade > 0.01 and not (visual.IsLocal and visual.BackFx[beam])
		if beam.Enabled then
			beam.Transparency = scaled(visual.BeamBase[beam], fade * mul)
		end
	end
end

local function createVisual(character: Model): Visual?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local isLocal = character == player.Character
	local model = template:Clone()
	-- solo el arma de este Mangekyō (con puño no queda ninguna)
	local weapon = weaponOf(character)
	for _, item in model:GetDescendants() do
		local key = item:GetAttribute("SusanooWeapon")
		if key ~= nil and key ~= weapon then
			item:Destroy()
		end
	end
	local visual: Visual = {
		Character = character,
		Model = model,
		IsLocal = isLocal,
		Weapon = weapon,
		Mode = nil,
		Parts = {},
		ArmParts = {},
		BaseTransparency = {},
		Emitters = {},
		BaseRate = {},
		Beams = {},
		BeamBase = {},
		ArmFx = {},
		BackFx = {},
		ArmFade = Instance.new("NumberValue"),
		BodyFade = Instance.new("NumberValue"),
		Highlight = model:FindFirstChildOfClass("Highlight"),
		Light = nil,
		Animator = nil,
		Tracks = {},
		Removing = false,
	}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
			item.CastShadow = false
			if item.Transparency < 1 then
				table.insert(visual.Parts, item)
				visual.BaseTransparency[item] =
					math.min(item.Transparency + (if isLocal then Config.LocalExtraTransparency else 0), 0.98)
				visual.ArmParts[item] = isArmPart(item, model)
				item.Transparency = 1
			end
		elseif item:IsA("ParticleEmitter") then
			table.insert(visual.Emitters, item)
			visual.BaseRate[item] = item.Rate * (if isLocal then Config.LocalParticleRate else 1)
			local holder = item.Parent
			visual.ArmFx[item] = item:GetAttribute("SusanooArm") == true
				or (holder ~= nil and ARM_PART_NAMES[holder.Name] == true)
			visual.BackFx[item] = item:GetAttribute("SusanooBack") == true
			item.Enabled = false
		elseif item:IsA("Beam") then
			table.insert(visual.Beams, item)
			visual.BeamBase[item] = item.Transparency
			visual.ArmFx[item] = item:GetAttribute("SusanooArm") == true
			visual.BackFx[item] = item:GetAttribute("SusanooBack") == true
			item.Enabled = false
		elseif item:IsA("PointLight") then
			visual.Light = item
			item.Enabled = false
		elseif item:IsA("Animator") then
			visual.Animator = item
		end
	end
	visual.ArmFade.Changed:Connect(function()
		refreshBeams(visual)
	end)
	visual.BodyFade.Changed:Connect(function()
		refreshBeams(visual)
	end)
	if visual.Highlight then
		visual.Highlight.FillTransparency = 1
		visual.Highlight.OutlineTransparency = 1
		visual.Highlight.Adornee = model
	end
	applyColor(visual)

	local primary = model.PrimaryPart :: BasePart
	primary.CFrame = root.CFrame
	local weld = Instance.new("Weld")
	weld.Name = "SusanooAttach"
	weld.Part0 = root
	weld.Part1 = primary
	weld.Parent = primary
	model.Name = "Susanoo_" .. character.Name
	model.Parent = visualsFolder

	local idle = loadTrack(visual, "Idle", Enum.AnimationPriority.Idle, true)
	if idle then
		idle:Play(0)
	end
	return visual
end

local function tween(instance: Instance, duration: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function showMode(visual: Visual, mode: Mode, fade: number?)
	if visual.Mode == mode then
		return
	end
	visual.Mode = mode
	local duration = fade or (if mode == "Full" or mode == "Arm" then Config.FadeIn else RIBS_FADE)
	local weaponHidden = visual.WeaponHiddenUntil ~= nil and os.clock() < visual.WeaponHiddenUntil
	for _, part in visual.Parts do
		local isWeapon = part:GetAttribute("SusanooWeapon") ~= nil
		local shown = if mode == "Arm" then visual.ArmParts[part] and not isWeapon
			else mode ~= "Ribs" or not visual.ArmParts[part]
		if isWeapon and weaponHidden then
			shown = false
		end
		tween(part, duration, { Transparency = if shown then visual.BaseTransparency[part] else 1 })
	end
	for _, emitter in visual.Emitters do
		emitter.Rate = visual.BaseRate[emitter]
		emitter.Enabled = (if mode == "Arm" then visual.ArmFx[emitter] == true
				else mode ~= "Ribs" or not visual.ArmFx[emitter])
			and not (visual.IsLocal and visual.BackFx[emitter])
	end
	tween(visual.ArmFade, duration, { Value = if mode ~= "Ribs" then 1 else 0 })
	tween(visual.BodyFade, duration, { Value = if mode == "Arm" then 0 else 1 })
	if visual.Highlight then
		tween(visual.Highlight, duration, {
			FillTransparency = if visual.IsLocal then Config.LocalHighlightFill else Config.HighlightFill,
			OutlineTransparency = if visual.IsLocal then Config.LocalHighlightOutline else Config.HighlightOutline,
		})
	end
	if visual.Light then
		visual.Light.Enabled = true
	end
end

local function removeVisual(character: Model, instant: boolean?)
	local visual = visuals[character]
	if not visual then
		return
	end
	visuals[character] = nil
	visual.Removing = true
	if instant then
		visual.Model:Destroy()
		return
	end
	for _, part in visual.Parts do
		tween(part, Config.FadeOut, { Transparency = 1 })
	end
	for _, emitter in visual.Emitters do
		emitter.Enabled = false
	end
	tween(visual.ArmFade, Config.FadeOut, { Value = 0 })
	tween(visual.BodyFade, Config.FadeOut, { Value = 0 })
	if visual.Highlight then
		tween(visual.Highlight, Config.FadeOut, { FillTransparency = 1, OutlineTransparency = 1 })
	end
	if visual.Light then
		visual.Light.Enabled = false
	end
	task.delay(Config.FadeOut + 0.05, function()
		visual.Model:Destroy()
	end)
end

local function desiredMode(character: Model): Mode?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if character:GetAttribute("SusanooActive") == true then
		return "Full"
	end
	if character:GetAttribute("MangekyoActive") == true and character:GetAttribute("BlockStartedAt") ~= nil then
		return if Config.weapon(weaponOf(character)).Guard then "Guard" else "Ribs"
	end
	return nil
end

-- Escudo en guardia mientras bloquea con el Mangekyō (Weapons.Shield.Guard)
local function refreshGuard(visual: Visual)
	local character = visual.Character
	local guardName = Config.weapon(weaponOf(character)).Guard
	local guarding = guardName ~= nil
		and character:GetAttribute("MangekyoActive") == true
		and character:GetAttribute("BlockStartedAt") ~= nil
	local track = if guardName then visual.Tracks[guardName] else nil
	if guarding and not (track and track.IsPlaying) then
		track = loadTrack(visual, guardName, Enum.AnimationPriority.Action, true)
		if track then
			track:Play(0.1)
		end
	elseif not guarding and track and track.IsPlaying then
		track:Stop(0.15)
	end
end

local function refresh(character: Model)
	local mode = desiredMode(character)
	if not mode then
		-- Brazo parcial de Yasaka no Magatama: se queda hasta que acabe la animación
		local held = visuals[character]
		if held and not held.Removing and held.HoldUntil and os.clock() < held.HoldUntil then
			showMode(held, "Arm")
			return
		end
		removeVisual(character)
		return
	end
	local visual = visuals[character]
	if not visual then
		visual = createVisual(character)
		if not visual then
			return
		end
		visuals[character] = visual
	end
	showMode(visual, mode)
	refreshGuard(visual)
end

local function playSwing(character: Model, index: number)
	local visual = visuals[character]
	local step = comboOf(character)[index]
	if not visual or visual.Removing or not step then
		debugLog("swing", index, "skipped: visual", visual ~= nil, "removing", visual and visual.Removing)
		return
	end
	if visual.Mode ~= "Full" then
		showMode(visual, "Full")
	end
	for name, track in visual.Tracks do
		if name ~= "Idle" and track.IsPlaying then
			track:Stop(0.05)
		end
	end
	local track = loadTrack(visual, step.Animation, Enum.AnimationPriority.Action, false)
	if track then
		track:Play(0.05)
		debugLog("swing", index, step.Animation, "playing", track.IsPlaying, "length", track.Length)
	else
		debugLog("swing", index, "no track for", step.Animation)
	end
end

local function watchCharacter(character: Model)
	for _, attribute in { "SusanooActive", "MangekyoActive", "BlockStartedAt" } do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			refresh(character)
		end)
	end
	character:GetAttributeChangedSignal("MangekyoColor"):Connect(function()
		local visual = visuals[character]
		if visual then
			applyColor(visual)
		end
	end)
	-- otra arma: se rehace el modelo (si solo se borra el atributo al apagar el Mangekyō, no)
	character:GetAttributeChangedSignal("MangekyoWeapon"):Connect(function()
		local visual = visuals[character]
		if visual and character:GetAttribute("MangekyoWeapon") ~= nil and weaponOf(character) ~= visual.Weapon then
			removeVisual(character, true)
			refresh(character)
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			removeVisual(character)
		end)
	end
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			removeVisual(character, true)
		end
	end)
	refresh(character)
end

local function watchPlayer(other: Player)
	if other.Character then
		task.spawn(watchCharacter, other.Character)
	end
	other.CharacterAdded:Connect(watchCharacter)
end

for _, other in Players:GetPlayers() do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Gesto de lanzar (Enton: Black Spear con el Susanoo activo)
local function playThrow(character: Model)
	local visual = visuals[character]
	if not visual or visual.Removing then
		return
	end
	local track = loadTrack(visual, "Throw", Enum.AnimationPriority.Action2, false)
	if track then
		track:Play(0.05)
	end
end

-- Yasaka no Magatama: el brazo forma y lanza los magatama (los dibuja MangekyoClient)
local function playYasaka(character: Model, data: { [string]: any })
	local duration = if typeof(data.Duration) == "number" then data.Duration else 2.5
	local visual = visuals[character]
	if not visual or visual.Removing then
		if data.Partial ~= true then
			return
		end
		local created = createVisual(character)
		if not created then
			return
		end
		visuals[character] = created
		visual = created
	end
	local current = visual :: Visual
	if data.Partial == true and not desiredMode(character) then
		current.HoldUntil = os.clock() + duration
		task.delay(duration + 0.05, function()
			if visuals[character] == current and current.HoldUntil and os.clock() >= current.HoldUntil then
				current.HoldUntil = nil
				refresh(character)
			end
		end)
	end
	-- El arma se esconde: la mano sostiene los magatama
	current.WeaponHiddenUntil = os.clock() + duration
	for _, part in current.Parts do
		if part:GetAttribute("SusanooWeapon") ~= nil then
			tween(part, 0.12, { Transparency = 1 })
		end
	end
	task.delay(duration, function()
		if visuals[character] == current and not current.Removing and current.Mode and current.Mode ~= "Arm" then
			for _, part in current.Parts do
				if part:GetAttribute("SusanooWeapon") ~= nil and (current.Mode ~= "Ribs") then
					tween(part, 0.25, { Transparency = current.BaseTransparency[part] })
				end
			end
		end
	end)
	if data.Partial == true and not desiredMode(character) then
		current.Mode = nil -- fuerza showMode aunque ya estuviera en Arm
		-- Fade: el brazo de Yasaka sale al ritmo de la carga (EmergeTime)
		showMode(current, "Arm", if typeof(data.Fade) == "number" then data.Fade else nil)
	end
	for name, track in current.Tracks do
		if name ~= "Idle" and track.IsPlaying then
			track:Stop(0.1)
		end
	end
	local name = if typeof(data.Animation) == "string" then data.Animation else "YasakaThrow"
	local track = loadTrack(current, name, Enum.AnimationPriority.Action2, false)
	if track then
		track.Priority = Enum.AnimationPriority.Action2
		track:Play(0.08)
	end
end

local function cancelYasaka(character: Model)
	local visual = visuals[character]
	if not visual then
		return
	end
	visual.HoldUntil = nil
	visual.WeaponHiddenUntil = nil
	for name, track in visual.Tracks do
		if string.sub(name, 1, 6) == "Yasaka" and track.IsPlaying then
			track:Stop(0.15)
		end
	end
	visual.Mode = nil
	refresh(character)
end

-- Contraataque del escudo: lo decide el servidor al bloquear un golpe
local function playCounter(character: Model)
	local visual = visuals[character]
	local counter = Config.weapon(weaponOf(character)).Counter
	if not visual or visual.Removing or not counter then
		return
	end
	local track = loadTrack(visual, counter.Animation, Enum.AnimationPriority.Action2, false)
	if track then
		track.Priority = Enum.AnimationPriority.Action2
		track:Play(0.05)
	end
end

remote.OnClientEvent:Connect(function(action: string, character: Model?, extra: any)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	if action == "Swing" and typeof(extra) == "number" then
		playSwing(character, extra)
	elseif action == "Counter" then
		playCounter(character)
	elseif action == "Throw" then
		playThrow(character)
	elseif action == "Yasaka" and typeof(extra) == "table" then
		playYasaka(character, extra)
	elseif action == "YasakaCancel" then
		cancelYasaka(character)
	end
end)

-- Combo local -----------------------------------------------------------------------------------

local comboIndex = 0
local comboWeapon: string? = nil
local lastSwingAt = -math.huge
local lockedUntil = 0

local BLOCKING_ATTRIBUTES = {
	"IsStunned",
	"IsBlocking",
	"IsDashing",
	"JutsuCasting",
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsExecuting",
	"IsCarrying",
}

local function canSwing(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if character:GetAttribute("CombatMode") ~= true or character:GetAttribute("CombatSuppressed") == true then
		return false
	end
	for _, attribute in BLOCKING_ATTRIBUTES do
		if character:GetAttribute(attribute) == true then
			return false
		end
	end
	return true
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute("SusanooActive") ~= true then
		return
	end
	if not canSwing(character) then
		local blocked = {}
		if character:GetAttribute("CombatMode") ~= true then
			table.insert(blocked, "CombatMode off (press R)")
		end
		for _, attribute in BLOCKING_ATTRIBUTES do
			if character:GetAttribute(attribute) == true then
				table.insert(blocked, attribute)
			end
		end
		debugLog("click blocked:", table.concat(blocked, ", "))
		return
	end
	local now = os.clock()
	if now < lockedUntil then
		debugLog("click ignored: still in the previous swing")
		return
	end
	local weapon = weaponOf(character)
	local combo = comboOf(character)
	local index = if weapon ~= comboWeapon or now - lastSwingAt > Config.ComboResetWindow or comboIndex >= #combo
		then 1
		else comboIndex + 1
	comboWeapon = weapon
	comboIndex = index
	lastSwingAt = now
	lockedUntil = now + combo[index].NextAfter
	playSwing(character, index)
	remote:FireServer("Attack", index)
end)
