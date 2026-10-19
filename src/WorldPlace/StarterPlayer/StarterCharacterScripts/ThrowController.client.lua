--[[
	ThrowController · LocalScript en StarterPlayer.StarterCharacterScripts

	G (tap)      lanza el arma seleccionada (solo en CombatMode)
	G (mantener) carga el segundo comportamiento del arma; al máximo queda lista hasta soltar
	G con un proyectil enemigo por impactar → contraataque guiado (también fuera de CombatMode)
	G con el kunai explosivo seleccionado y sellos tuyos clavados → los detona

	El proyectil aparece en la mano en el marcador "Release" de la animación, sin esperar al servidor.
	En el aire: la caída se frena un momento (una vez por salto). Nunca durante un tree jump.
	La selección de arma (menú radial) está en NinjaBagRadial.
]]

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("Throwables")
local Config = require(folder:WaitForChild("Config"))
local Definitions = require(folder:WaitForChild("Definitions"))
local Targets = require(folder:WaitForChild("Targets"))
local ClientShots = require(folder:WaitForChild("ClientShots"))
local Visuals = require(folder:WaitForChild("Visuals"))
local Effects = require(folder:WaitForChild("Effects"))

local combatAimModule = ReplicatedStorage:FindFirstChild("CombatAim")
local CombatAim = if combatAimModule then require(combatAimModule) else nil

local remotes = folder:WaitForChild("Remotes")
local throwEvent = remotes:WaitForChild("Throw")
local counterEvent = remotes:WaitForChild("Counter")
local chargeEvent = remotes:WaitForChild("Charge")
local resultEvent = remotes:WaitForChild("Result")
local worldEvent = remotes:WaitForChild("World")
local detonateEvent = remotes:WaitForChild("Detonate")
local redirectEvent = remotes:WaitForChild("Redirect")

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local DEFAULT_RELEASE_TIME = Config.ReleaseFrame / Config.AnimationFps
local DEFAULT_HOLD_TIME = Config.HoldPoseFrame / Config.AnimationFps
local RECOVERY_TIME = 0.35 -- tras el Release, cuánto dura todavía la acción

local BLOCKING_ATTRIBUTES = {
	"CombatSuppressed", "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting", "IsCarrying",
	"IsStunned", "Status_AttackBlocked", "Status_Stunned", "IsBlocking", "IsAttacking", "IsDashing",
	"TreeJumpActive", "IsTreeJumping",
}

local function debugLog(...)
	if Config.Debug then
		print("[ThrowController]", ...)
	end
end

-- Animaciones -------------------------------------------------------------------

local animator = humanoid:WaitForChild("Animator", 5)
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

-- Lee los tiempos de los marcadores Release / Hold de la animación (si los tiene)
local function readMarkers(info)
	local ok, sequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(info.Id)
	end)
	if not ok or not sequence then
		warn("[ThrowController] No pude leer los marcadores de " .. info.Id .. "; uso los frames de respaldo")
		return
	end
	local foundRelease, foundHold = false, false
	for _, keyframe in sequence:GetKeyframes() do
		for _, marker in keyframe:GetMarkers() do
			if marker.Name == Config.ReleaseMarker then
				info.Release, foundRelease = keyframe.Time, true
			elseif marker.Name == Config.HoldMarker then
				info.Hold, foundHold = keyframe.Time, true
			end
		end
	end
	if not foundRelease then
		warn("[ThrowController] " .. info.Id .. " no tiene marcador '" .. Config.ReleaseMarker .. "'")
	end
	if not foundHold then
		info.Hold = math.min(info.Hold, info.Release * 0.75)
	end
	debugLog(info.Id, "Release", info.Release, "Hold", info.Hold)
end

-- Devuelve { Track, Id, Release, Hold } o nil
local function loadAnimation(id)
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn("[ThrowController] No se pudo cargar la animación " .. id)
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	local info = { Track = track, Id = id, Release = DEFAULT_RELEASE_TIME, Hold = DEFAULT_HOLD_TIME }
	task.spawn(readMarkers, info)
	return info
end

local animations = {
	Normal = loadAnimation(Config.Animations.Normal),
	Sprint = loadAnimation(Config.Animations.Sprint),
	AirThrow = loadAnimation(Config.AirAnimations.Throw),
	AirHeavy = loadAnimation(Config.AirAnimations.Heavy),
}

-- Animación fija de respaldo (sin track) para no romper la lógica si falta alguna
local FALLBACK_ANIMATION = { Track = nil, Id = "", Release = DEFAULT_RELEASE_TIME, Hold = DEFAULT_HOLD_TIME }

-- Ninja Bag -----------------------------------------------------------------------

local function getSelectedSlot()
	local value = player:GetAttribute("NinjaBagSelectedSlot")
	if typeof(value) == "number" and value >= 1 and value <= Config.SlotCount then
		return math.floor(value)
	end
	return 1
end

local function getSlotWeapon(slot)
	local value = player:GetAttribute("NinjaBagSlot" .. slot .. "Projectile")
	if typeof(value) == "string" and typeof(Definitions[value]) == "table" then
		return value
	end
	return nil
end

local function getAmount(weapon)
	local value = player:GetAttribute("NinjaBagAmount_" .. weapon)
	return if typeof(value) == "number" then math.max(0, math.floor(value)) else 0
end

local function cooldownRemaining(weapon)
	local endsAt = character:GetAttribute("CoreCooldown_" .. weapon .. "_EndsAt")
	return if typeof(endsAt) == "number" then endsAt - Workspace:GetServerTimeNow() else 0
end

-- Estado del personaje ---------------------------------------------------------------

local function isBlocked()
	if humanoid.Health <= 0 or not rootPart.Parent then
		return true
	end
	for _, name in BLOCKING_ATTRIBUTES do
		if character:GetAttribute(name) == true then
			return true
		end
	end
	return player:GetAttribute("NinjaBagLoadoutOpen") == true or player:GetAttribute("NinjaBagRadialOpen") == true
end

local function rightHandBusy()
	for _, name in Config.RightHandBusyAttributes do
		if character:GetAttribute(name) == true then
			return true
		end
	end
	return character:FindFirstChildOfClass("Tool") ~= nil
end

local function getOrigin(weapon)
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
	return rootPart.Position
end

local function getAimRay()
	if CombatAim and CombatAim.GetAimRay then
		local ok, ray = pcall(CombatAim.GetAimRay)
		if ok and ray then
			return ray
		end
	end
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

local function setThrowFlags(weapon)
	local active = weapon ~= nil
	character:SetAttribute("IsThrowingProjectile", active)
	for id, definition in Definitions do
		if typeof(definition) == "table" and not definition.Technique then
			character:SetAttribute("IsThrowing" .. id, active and id == weapon)
		end
	end
	-- Compatibilidad: AttackController bloquea el M1 con este atributo
	character:SetAttribute("IsThrowingKunai", active)
end

setThrowFlags(nil)

-- UI de carga (rombos bajo el retículo y anillo de enfoque del senbon) --------------------

local COLOR_GOLD = Color3.fromRGB(190, 151, 76)
local COLOR_GOLD_DIM = Color3.fromRGB(116, 92, 50)
local COLOR_PANEL = Color3.fromRGB(14, 14, 16)

local chargeGui = Instance.new("ScreenGui")
chargeGui.Name = "ThrowChargeUI"
chargeGui.IgnoreGuiInset = true
chargeGui.ResetOnSpawn = true
chargeGui.DisplayOrder = 70
chargeGui.Enabled = false
chargeGui.Parent = player:WaitForChild("PlayerGui")

local pipRow = Instance.new("Frame")
pipRow.AnchorPoint = Vector2.new(0.5, 0)
pipRow.Position = UDim2.new(0.5, 0, 0.5, 30)
pipRow.Size = UDim2.fromOffset(120, 14)
pipRow.BackgroundTransparency = 1
pipRow.Parent = chargeGui

local pipLayout = Instance.new("UIListLayout")
pipLayout.FillDirection = Enum.FillDirection.Horizontal
pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pipLayout.Padding = UDim.new(0, 8)
pipLayout.Parent = pipRow

local focusRing = Instance.new("Frame")
focusRing.AnchorPoint = Vector2.new(0.5, 0.5)
focusRing.Position = UDim2.fromScale(0.5, 0.5)
focusRing.Size = UDim2.fromOffset(84, 84)
focusRing.BackgroundTransparency = 1
focusRing.Visible = false
focusRing.Parent = chargeGui
Instance.new("UICorner", focusRing).CornerRadius = UDim.new(1, 0)
local focusStroke = Instance.new("UIStroke")
focusStroke.Color = COLOR_GOLD
focusStroke.Thickness = 1.5
focusStroke.Transparency = 0.3
focusStroke.Parent = focusRing

local pips = {}

local function buildPips(count)
	for _, pip in pips do
		pip:Destroy()
	end
	table.clear(pips)
	for _ = 1, count do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(9, 9)
		pip.Rotation = 45
		pip.BackgroundColor3 = COLOR_PANEL
		pip.BackgroundTransparency = 0.3
		pip.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLOR_GOLD_DIM
		stroke.Thickness = 1
		stroke.Parent = pip
		pip.Parent = pipRow
		table.insert(pips, pip)
	end
end

local function setPipLevel(level)
	for i, pip in pips do
		local filled = i <= level
		pip.BackgroundColor3 = if filled then COLOR_GOLD else COLOR_PANEL
		pip.BackgroundTransparency = if filled then 0 else 0.3
		if filled and pip:GetAttribute("Filled") ~= true then
			pip.Size = UDim2.fromOffset(14, 14)
			TweenService:Create(pip, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(9, 9) }):Play()
		end
		pip:SetAttribute("Filled", filled)
	end
end

-- Acción en curso -------------------------------------------------------------------------

local action = nil
local sideByWeapon = {}

local function isAirborne()
	return humanoid.FloorMaterial == Enum.Material.Air
end

local function stopTracks(fade)
	for _, info in animations do
		if info.Track and info.Track.IsPlaying then
			info.Track:Stop(fade)
		end
	end
end

-- Animación según el arma y si está en el aire (con respaldo si falta alguna)
local function pickAnimation(definition, airborne)
	if airborne then
		local heavy = definition.AirAnimation and animations["Air" .. definition.AirAnimation]
		if heavy then
			return heavy
		end
		if animations.AirThrow then
			return animations.AirThrow
		end
	end
	if character:GetAttribute("IsSprinting") == true and animations.Sprint then
		return animations.Sprint
	end
	return animations.Normal or FALLBACK_ANIMATION
end

-- Frenado en el aire ----------------------------------------------------------------------
-- Una vez por salto: empujón hacia arriba, retroceso y gravedad reducida mientras se lanza.

local airUsed = false
local hangState = nil

local hangAttachment = Instance.new("Attachment")
hangAttachment.Name = "AirThrowAttachment"
hangAttachment.Parent = rootPart

local hangForce = Instance.new("VectorForce")
hangForce.Name = "AirThrowForce"
hangForce.Attachment0 = hangAttachment
hangForce.RelativeTo = Enum.ActuatorRelativeTo.World
hangForce.ApplyAtCenterOfMass = true
hangForce.Force = Vector3.zero
hangForce.Enabled = false
hangForce.Parent = rootPart

local function stopHang()
	hangState = nil
	hangForce.Enabled = false
	hangForce.Force = Vector3.zero
end

local function startHang()
	local air = Config.AirThrow
	if not air.Enabled or airUsed or not isAirborne() then
		return
	end
	airUsed = true
	local velocity = rootPart.AssemblyLinearVelocity
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.zero
	rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X * air.HorizontalKeep, air.Pop, velocity.Z * air.HorizontalKeep)
		- flatLook * air.Recoil
	hangState = { StartedAt = os.clock(), FiredAt = nil }
	hangForce.Enabled = true
end

local function updateHang()
	if not isAirborne() then
		airUsed = false
		if hangState then
			stopHang()
		end
		return
	end
	if not hangState then
		return
	end
	local air = Config.AirThrow
	local now = os.clock()
	local scale
	if action and not action.Fired then
		-- Preparando o cargando: casi sin gravedad (cargando mucho, cae lento)
		local overCharged = action.Charging and action.KeyDown and now - hangState.StartedAt > air.MaxChargeHang
		scale = if overCharged then air.ChargeGravityScale else air.GravityScale
	else
		-- Ya lanzó (o se canceló): un momento más y vuelve la gravedad
		hangState.FiredAt = hangState.FiredAt or now
		local after = now - hangState.FiredAt - air.HangTime
		if after <= 0 then
			scale = air.GravityScale
		else
			local alpha = math.clamp(after / air.RecoverTime, 0, 1)
			if alpha >= 1 then
				stopHang()
				return
			end
			scale = air.GravityScale + (1 - air.GravityScale) * alpha
		end
	end
	hangForce.Force = Vector3.new(0, rootPart.AssemblyMass * Workspace.Gravity * (1 - scale), 0)
end

local function hideChargeUi()
	chargeGui.Enabled = false
	focusRing.Visible = false
end

local function endCharge(notifyServer)
	if action and action.Charging then
		if notifyServer then
			chargeEvent:FireServer("Cancel")
		end
		Visuals.stopCharge(character)
		action.Charging = false
	end
	hideChargeUi()
end

local function cancelAction(reason)
	if not action then
		return
	end
	debugLog("cancelado:", reason)
	endCharge(true)
	stopTracks(0.08)
	if hangState and not hangState.FiredAt then
		hangState.FiredAt = os.clock() - Config.AirThrow.HangTime -- recupera la gravedad ya
	end
	action = nil
	setThrowFlags(nil)
end

local function startAction(kind, slot, definition, speed, extra)
	local airborne = isAirborne()
	local animation = pickAnimation(definition, airborne)
	local track = animation.Track
	stopTracks(0)
	if track then
		track:Play(0.06, 1, speed)
	end
	action = {
		Kind = kind,
		Slot = slot,
		Definition = definition,
		Anim = animation,
		Track = track,
		Speed = speed,
		AnimTime = 0,
		Frozen = false,
		PressTime = os.clock(),
		KeyDown = true,
		Charging = false,
		ChargeStart = 0,
		Level = 0,
		MaxLevel = 0,
		Fired = false,
	}
	if extra then
		for key, value in extra do
			action[key] = value
		end
	end
	setThrowFlags(definition.Id)
	-- El contraataque es rápido y no frena la caída
	if kind == "Throw" and airborne then
		startHang()
	end
end

local function maxLevelForAmmo(definition, oneHand)
	local ammo = getAmount(definition.Id)
	local level = 0
	while definition.Levels[level + 1] and ClientShots.shotCount(definition, level + 1, oneHand) <= ammo do
		level += 1
	end
	return level
end

local function beginCharge()
	action.Charging = true
	action.ChargeStart = os.clock()
	action.MaxLevel = maxLevelForAmmo(action.Definition, rightHandBusy())
	chargeEvent:FireServer("Begin", action.Slot)
	Visuals.startCharge(character, action.Definition, {
		StartedAt = Workspace:GetServerTimeNow(),
		OneHand = rightHandBusy(),
		MaxLevel = action.MaxLevel,
	})
	buildPips(action.MaxLevel)
	setPipLevel(0)
	chargeGui.Enabled = true
	focusRing.Visible = false
	debugLog("carga", action.Definition.Id, "máx", action.MaxLevel)
end

local function updateCharge()
	local definition = action.Definition
	local elapsed = os.clock() - action.ChargeStart
	local level = 0
	while definition.Levels[level + 1] and level < action.MaxLevel and elapsed >= definition.Levels[level + 1].HoldTime do
		level += 1
	end
	if level ~= action.Level then
		action.Level = level
		setPipLevel(level)
	end

	-- Enfoque del senbon: el anillo se cierra hacia el retículo
	local focusLevel = definition.Levels[1]
	if focusLevel and focusLevel.Focus and action.MaxLevel >= 1 then
		focusRing.Visible = true
		local alpha = math.clamp(elapsed / focusLevel.HoldTime, 0, 1)
		local size = 84 - (84 - 24) * alpha
		focusRing.Size = UDim2.fromOffset(size, size)
		focusStroke.Transparency = 0.5 - 0.4 * alpha
	end
end

-- Lanzamiento normal
local function fireThrow()
	local definition = action.Definition
	if getSlotWeapon(action.Slot) ~= definition.Id then
		cancelAction("cambió el slot")
		return
	end

	local oneHand = rightHandBusy()
	local ammo = getAmount(definition.Id)
	local level = if action.Charging then action.Level else 0
	while level > 0 and ClientShots.shotCount(definition, level, oneHand) > ammo do
		level -= 1
	end
	if not oneHand and ClientShots.shotCount(definition, level, false) > ammo then
		oneHand = true -- queda un solo shuriken: se lanza con una mano
	end
	if ClientShots.shotCount(definition, level, oneHand) > ammo then
		cancelAction("sin munición")
		return
	end

	local origin = getOrigin(definition.Id)
	local ray = getAimRay()
	local direction = ray.Direction.Unit
	local levelDef = definition.Levels[level]
	local target
	if levelDef.AtFeet then
		-- Al suelo bajo tus pies (bomba de humo cargada)
		local ground = Targets.castWorld(rootPart.Position, Vector3.yAxis * -12, { character })
		target = if ground then ground.Position else rootPart.Position - Vector3.yAxis * 3
	else
		target = Targets.solveAim(definition, levelDef, origin, ray.Origin, direction, character)
	end

	sideByWeapon[definition.Id] = -(sideByWeapon[definition.Id] or -1)

	local packet = {
		OwnerUserId = player.UserId,
		ThrowId = ClientShots.nextThrowId(),
		Kind = "Throw",
		Slot = action.Slot,
		Weapon = definition.Id,
		Level = level,
		Origin = origin,
		Target = target,
		AimOrigin = ray.Origin,
		AimDirection = direction,
		StartTime = Workspace:GetServerTimeNow(),
		Side = sideByWeapon[definition.Id],
		OneHand = oneHand,
	}
	ClientShots.addThrow(packet, true)
	throwEvent:FireServer(packet)

	if action.Charging then
		Visuals.stopCharge(character)
		action.Charging = false
	end
	hideChargeUi()
	debugLog("lanzado", definition.Id, "nivel", level)
end

-- Contraataque guiado
local function fireCounter()
	local definition = action.Definition
	local threat = action.Threat
	local origin = getOrigin(definition.Id)
	local releaseTime = Workspace:GetServerTimeNow()
	local intercept, arrival = ClientShots.solveIntercept(
		threat.Entry,
		origin,
		releaseTime,
		definition.CounterSpeed,
		threat.ImpactTime - Config.CounterSafety
	)
	if not intercept then
		cancelAction("intercepción imposible")
		return
	end
	local packet = {
		OwnerUserId = player.UserId,
		ThrowId = ClientShots.nextThrowId(),
		Kind = "Counter",
		Slot = action.Slot,
		Weapon = definition.Id,
		Origin = origin,
		Intercept = intercept,
		Arrival = arrival,
		StartTime = releaseTime,
		ThreatId = threat.Entry.Id,
	}
	ClientShots.addThrow(packet, true)
	counterEvent:FireServer(packet)
	debugLog("contraataque", definition.Id, "contra", threat.Entry.Id)
end

local function tryStart()
	if action or isBlocked() then
		return
	end
	local slot = getSelectedSlot()
	local weapon = getSlotWeapon(slot)

	-- Kunai explosivo con sellos clavados: G los detona en vez de lanzar
	if weapon and Definitions[weapon].Sticky and Effects.hasOwnTags() then
		detonateEvent:FireServer()
		debugLog("detonar sellos")
		return
	end

	if not weapon or getAmount(weapon) <= 0 or cooldownRemaining(weapon) > 0 then
		return
	end
	local definition = Definitions[weapon]

	-- Contraataque: tiene prioridad si algo está por impactar
	if Config.CounterEnabled and not definition.NoCounter then
		local releaseDelay = pickAnimation(definition, isAirborne()).Release / Config.CounterAnimationSpeed
		local threat = ClientShots.findThreat(rootPart.Position, Config.CounterWindow, Config.CounterThreatRadius)
		if threat and threat.TimeToImpact > releaseDelay + 0.03 then
			local now = Workspace:GetServerTimeNow()
			local intercept = ClientShots.solveIntercept(
				threat.Entry,
				getOrigin(weapon),
				now + releaseDelay,
				definition.CounterSpeed,
				threat.ImpactTime - Config.CounterSafety
			)
			if intercept then
				startAction("Counter", slot, definition, Config.CounterAnimationSpeed, { Threat = threat, KeyDown = false })
				return
			end
		end
	end

	-- Lanzamiento ofensivo: solo en CombatMode
	if character:GetAttribute("CombatMode") ~= true then
		return
	end
	startAction("Throw", slot, definition, Config.NormalSpeed)
end

-- Bucle ----------------------------------------------------------------------------

local function update(dt)
	updateHang()
	if not action then
		return
	end
	if not action.Frozen then
		action.AnimTime += dt * action.Speed
	end
	local anim = action.Anim

	if action.Kind == "Throw" and not action.Fired then
		if action.KeyDown and not action.Charging
			and os.clock() - action.PressTime >= Config.TapThreshold
			and maxLevelForAmmo(action.Definition, rightHandBusy()) > 0 then
			beginCharge()
		end
		if action.Charging and action.KeyDown then
			-- Mano atrás: la pose se congela mientras se carga
			if action.AnimTime >= anim.Hold and not action.Frozen then
				action.Frozen = true
				action.AnimTime = anim.Hold
				if action.Track then
					action.Track.TimePosition = anim.Hold
					action.Track:AdjustSpeed(0)
				end
			end
			updateCharge()
			return
		end
	end

	-- Suelta: la animación sigue hasta el frame de salida
	if action.Frozen then
		action.Frozen = false
		if action.Track then
			action.Track:AdjustSpeed(action.Speed)
		end
	end

	if not action.Fired and action.AnimTime >= anim.Release then
		action.Fired = true
		if action.Kind == "Counter" then
			fireCounter()
		else
			fireThrow()
		end
	end

	if action and action.Fired and action.AnimTime >= anim.Release + RECOVERY_TIME then
		action = nil
		setThrowFlags(nil)
	end
end

local connections = {}
table.insert(connections, RunService.RenderStepped:Connect(update))

-- Entrada -----------------------------------------------------------------------------

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Config.ThrowKey or UserInputService:GetFocusedTextBox() then
		return
	end
	tryStart()
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.ThrowKey and action then
		action.KeyDown = false
	end
end))

-- Kunai guiado (shurikenjutsu): volver a presionar la tecla del jutsu mientras el kunai vuela
-- lo redirige hacia donde apuntas. El JutsuController también recibe la tecla, pero el jutsu
-- está en cooldown y no hace nada.
local TECHNIQUE_SLOT_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9, [Enum.KeyCode.Zero] = 10,
}

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	local slot = TECHNIQUE_SLOT_KEYS[input.KeyCode]
	if processed or not slot or UserInputService:GetFocusedTextBox() then
		return
	end
	if player:GetAttribute("TechniqueLoadoutSlot_" .. slot) ~= Config.RedirectTechnique then
		return
	end
	local entry = ClientShots.findRedirectable()
	local position = entry and ClientShots.currentPosition(entry)
	if not entry or not position or humanoid.Health <= 0 then
		return
	end
	local ray = getAimRay()
	local target = Targets.solveAim(entry.Definition, entry.LevelDef, position, ray.Origin, ray.Direction.Unit, character)
	entry.Redirected = true
	redirectEvent:FireServer(entry.Id, target)
	debugLog("redirigir", entry.Id)
end))

-- Servidor -----------------------------------------------------------------------------

table.insert(connections, resultEvent.OnClientEvent:Connect(function(_throwId, approved, reason)
	if approved and reason == "Counter" and character:GetAttribute("CombatMode") ~= true then
		-- Contraataque exitoso: pedir entrar en CombatMode (CombatController es el dueño)
		local request = character:FindFirstChild("CombatModeRequest")
		if request and request:IsA("BindableEvent") then
			request:Fire("Enter", "ProjectileCounter")
		end
	elseif not approved then
		debugLog("rechazado:", reason)
	end
end))

table.insert(connections, worldEvent.OnClientEvent:Connect(function(kind)
	if kind == "ChargeCancel" and action and not action.Fired then
		cancelAction("golpeado")
	end
end))

-- Cancelaciones ---------------------------------------------------------------------------

for _, name in BLOCKING_ATTRIBUTES do
	table.insert(connections, character:GetAttributeChangedSignal(name):Connect(function()
		if character:GetAttribute(name) == true and action and not action.Fired then
			cancelAction(name)
		end
	end))
end

table.insert(connections, character:GetAttributeChangedSignal("CombatMode"):Connect(function()
	if character:GetAttribute("CombatMode") ~= true and action and action.Kind == "Throw" and not action.Fired then
		cancelAction("salió de CombatMode")
	end
end))

local function cleanup()
	cancelAction("limpieza")
	stopHang()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)
