--[[
	TreeJumpController · LocalScript en StarterPlayer.StarterCharacterScripts

	Estados:
		Idle     en el suelo o en el aire (salto normal)
		Perched  parado sobre una zona (rama)
		Flying   volando hacia una rama
		Contact  pies tocando la rama un instante antes de encadenar

	Espacio:
		Suelo            → salto normal (pasa al sistema de Roblox / doble salto del juego)
		Aire             → cuenta toques; el toque EntryPressCount con objetivo marcado = tree jump
		Parado en rama   → tree jump al objetivo marcado; sin objetivo = salto normal
		Volando          → desde BufferWindowStart queda en cola: al tocar la rama sale el siguiente
		Sin tocar nada   → al llegar te quedas parado en la rama

	El salto empieza al instante; el servidor valida en paralelo y, si rechaza, el vuelo se corta.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("TreeJump")
local Config = require(folder:WaitForChild("Config"))
local Zones = require(folder:WaitForChild("Zones"))
local Effects = require(folder:WaitForChild("Effects"))
local Indicator = require(folder:WaitForChild("Indicator"))

local remotes = folder:WaitForChild("Remotes")
local requestEvent = remotes:WaitForChild("Request")
local resultEvent = remotes:WaitForChild("Result")
local replicateEvent = remotes:WaitForChild("Replicate")

-- Estela de viento existente del juego (opcional)
local windTrail = nil
local windModule = ReplicatedStorage:FindFirstChild("WindTrail")
if windModule then
	local ok, result = pcall(require, windModule)
	windTrail = if ok then result else nil
end

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")

local ACTION_NAME = "TreeJumpSpace"
local LOCK_ATTRIBUTES = { "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting", "IsCarrying" }

local function debugLog(...)
	if Config.Debug then
		print("[TreeJump]", ...)
	end
end

-- Indicadores -------------------------------------------------------------------

local mainIndicator = Indicator.new(playerGui, {
	Name = "TreeJumpTarget",
	Size = Config.IndicatorSize,
	Transparency = Config.IndicatorTransparency,
	Spin = true,
})
local nextIndicator = Indicator.new(playerGui, {
	Name = "TreeJumpNext",
	Size = Config.NextIndicatorSize,
	Transparency = Config.NextIndicatorTransparency,
	Spin = false,
})

-- Física del vuelo ----------------------------------------------------------------

local attachment = Instance.new("Attachment")
attachment.Name = "TreeJumpAttachment"
attachment.Parent = rootPart

local velocity = Instance.new("LinearVelocity")
velocity.Name = "TreeJumpVelocity"
velocity.Attachment0 = attachment
velocity.RelativeTo = Enum.ActuatorRelativeTo.World
velocity.MaxForce = math.huge
velocity.VectorVelocity = Vector3.zero
velocity.Enabled = false
velocity.Parent = rootPart

-- Animación (congela la pose final en saltos largos) -------------------------------

local animator = humanoid:WaitForChild("Animator", 5)
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end
local animation = Instance.new("Animation")
animation.AnimationId = Config.AnimationId
local track = animator:LoadAnimation(animation)
track.Priority = Enum.AnimationPriority.Action
track.Looped = false
local animationGeneration = 0

local function playAnimation(duration)
	animationGeneration += 1
	local generation = animationGeneration
	if track.IsPlaying then
		track:Stop(0)
	end
	track:Play(0.08)
	track:AdjustSpeed(1)

	task.spawn(function()
		local waited = 0
		while track.Length <= 0 and generation == animationGeneration and waited < 1 do
			waited += RunService.Heartbeat:Wait()
		end
		if generation ~= animationGeneration or track.Length <= 0 or duration <= track.Length then
			return
		end
		local freezeAt = math.max(track.Length - Config.FreezeBeforeEnd, 0)
		while generation == animationGeneration and track.IsPlaying and track.TimePosition < freezeAt do
			RunService.Heartbeat:Wait()
		end
		if generation == animationGeneration and track.IsPlaying then
			track.TimePosition = freezeAt
			track:AdjustSpeed(0)
		end
	end)
end

local function stopAnimation(fadeTime)
	animationGeneration += 1
	track:AdjustSpeed(1)
	if track.IsPlaying then
		track:Stop(fadeTime)
	end
end

-- Estado --------------------------------------------------------------------------

local state = "Idle"
local pressCount = 0
local currentZone, previousZone = nil, nil
local target, targetSince = nil, 0
local nextTarget = nil
local buffered = false
local chainIndex = 0
local lastLandTime = -math.huge
local jumpId = 0
local flight = nil -- { Id, Trajectory, Zone, Point, StartTime, StuckSince }
local contactTarget, contactUntil = nil, 0
local pendingEntry = nil -- { Since, Zone } entrada en combate (mantener Espacio)
local keyHeld = false
local lastPressTime = -math.huge
local savedAutoRotate = humanoid.AutoRotate
local scanTimer, floorTimer = 0, 0
local ignoreList = { character }
local connections = {}

-- Condiciones ---------------------------------------------------------------------

local function isLocked()
	for _, name in LOCK_ATTRIBUTES do
		if character:GetAttribute(name) == true then
			return true
		end
	end
	return false
end

local function inWater()
	if humanoid:GetState() == Enum.HumanoidStateType.Swimming or character:GetAttribute("WaterJumping") == true then
		return true
	end
	if character:GetAttribute("WaterWalking") == true then
		return false
	end
	return humanoid.FloorMaterial == Enum.Material.Water
end

local function inCombat()
	return player:GetAttribute(Config.CombatAttribute) == true or character:GetAttribute(Config.CombatAttribute) == true
end

local function onCombatCooldown()
	local endsAt = character:GetAttribute("CoreCooldown_TreeJump_EndsAt")
	return typeof(endsAt) == "number" and Workspace:GetServerTimeNow() < endsAt
end

local function canTreeJump()
	return humanoid.Health > 0
		and not isLocked()
		and not inWater()
		and character:GetAttribute("IsDashing") ~= true
		and character:GetAttribute("MissionInteractionActive") ~= true
		and character:GetAttribute("ChakraCharging") ~= true
		and not onCombatCooldown()
end

local function isAirborne()
	return humanoid.FloorMaterial == Enum.Material.Air
end

local function isFlying()
	return state == "Flying" or state == "Contact"
end

local function recentlyLanded()
	return currentZone ~= nil and os.clock() - lastLandTime <= Config.LandingGrace
end

local function flatDirection(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		local look = rootPart.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	return if flat.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else flat.Unit
end

local function feetPosition()
	return rootPart.Position - Vector3.yAxis * Zones.standOffset(humanoid, rootPart)
end

-- Un Espacio ahora, ¿haría tree jump?
local function wouldTreeJump()
	if state == "Perched" then
		return true
	end
	return state == "Idle" and isAirborne() and pressCount >= Config.EntryPressCount - 1
end

-- Objetivos -----------------------------------------------------------------------

local function findTarget(origin, cone, exclude, flightDirection, preferred, chain)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	return Zones.findBest({
		Origin = origin,
		AimOrigin = ray.Origin,
		AimDirection = ray.Direction.Unit,
		CameraPosition = camera.CFrame.Position,
		Cone = cone,
		Exclude = exclude,
		FlightDirection = flightDirection,
		Preferred = preferred,
		StandOffset = Zones.standOffset(humanoid, rootPart),
		Ignore = ignoreList,
		ChainIndex = chain,
	})
end

local function updateTargets()
	if not canTreeJump() then
		target, nextTarget = nil, nil
		mainIndicator:Hide()
		nextIndicator:Hide()
		return
	end

	if isFlying() then
		mainIndicator:Hide()
		if state == "Flying" and flight then
			local trajectory = flight.Trajectory
			local progress = (os.clock() - flight.StartTime) / trajectory.Duration
			if progress >= Config.BufferWindowStart then
				local exclude = { [flight.Zone] = true }
				if currentZone then
					exclude[currentZone] = true
				end
				nextTarget = findTarget(
					trajectory.End,
					Config.ChainCone,
					exclude,
					flatDirection(trajectory.End - trajectory.Start),
					nextTarget and nextTarget.Zone,
					chainIndex + 1
				)
			else
				nextTarget = nil
			end
		end
		local shown = if state == "Contact" then contactTarget else nextTarget
		if shown then
			nextIndicator:Show(shown.Zone, shown.Point)
		else
			nextIndicator:Hide()
		end
		return
	end

	nextIndicator:Hide()
	if not wouldTreeJump() then
		target = nil
		mainIndicator:Hide()
		return
	end

	local exclude = {}
	if currentZone and state == "Perched" then
		exclude[currentZone] = true
	end
	local cone = if state == "Perched" then Config.ChainCone else Config.EntryCone
	local found = findTarget(rootPart.Position, cone, exclude, nil, target and target.Zone, chainIndex)
	if found and (not target or target.Zone ~= found.Zone) then
		targetSince = os.clock()
	end
	target = found
	if target then
		mainIndicator:Show(target.Zone, target.Point)
	else
		mainIndicator:Hide()
	end
end

-- Entrada desde el aire: objetivo estable y moviéndose hacia él (o quieto)
local function entryAllowed(candidate)
	if os.clock() - targetSince < Config.ArmTime then
		return false
	end
	local move = humanoid.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	if flatMove.Magnitude > 0.1 then
		local toTarget = candidate.RootTarget - rootPart.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude > 1e-3 and flatMove.Unit:Dot(flat.Unit) < Config.EntryMinMoveDot then
			return false
		end
	end
	return true
end

-- Vuelo ---------------------------------------------------------------------------

local function releaseFlight()
	velocity.Enabled = false
	velocity.VectorVelocity = Vector3.zero
	humanoid.PlatformStand = false
	humanoid.AutoRotate = savedAutoRotate
	character:SetAttribute("TreeJumpActive", false)
	Effects.stopSpeed()
	if windTrail then
		pcall(windTrail.stop, character)
	end
	stopAnimation(0.1)

	-- Enderezar el cuerpo
	local position = rootPart.Position
	rootPart.CFrame = CFrame.lookAt(position, position + flatDirection(rootPart.CFrame.LookVector))
	rootPart.AssemblyAngularVelocity = Vector3.zero
	flight = nil
	contactTarget = nil
end

local function abort(reason)
	if not isFlying() then
		return
	end
	debugLog("vuelo cortado:", reason)
	releaseFlight()
	state = "Idle"
	buffered = false
	nextTarget = nil
	nextIndicator:Hide()
	chainIndex = 0
	-- El próximo Espacio en el aire puede volver a intentar
	pressCount = Config.EntryPressCount - 1
end

local function perch()
	releaseFlight()
	rootPart.AssemblyLinearVelocity = Vector3.zero
	state = "Perched"
	pressCount = 0
	buffered = false
	nextTarget = nil
	nextIndicator:Hide()
	Effects.cameraBump(Config.LandingBump)
end

local function launch(candidate, isChain)
	if not isFlying() then
		savedAutoRotate = humanoid.AutoRotate
	end
	local fromBranch = currentZone ~= nil and (state == "Perched" or state == "Contact")
	chainIndex = if isChain then chainIndex + 1 else 0

	local departure = feetPosition()
	local trajectory = Zones.trajectory(rootPart.Position, candidate.RootTarget, chainIndex)
	jumpId += 1
	flight = {
		Id = jumpId,
		Trajectory = trajectory,
		Zone = candidate.Zone,
		Point = candidate.Point,
		StartTime = os.clock(),
		StuckSince = nil,
	}
	state = "Flying"
	buffered = false
	target, nextTarget, pendingEntry, contactTarget = nil, nil, nil, nil
	mainIndicator:Hide()
	nextIndicator:Hide()

	requestEvent:FireServer(jumpId, candidate.Zone, candidate.Point, trajectory.Start, chainIndex)

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	velocity.Enabled = true
	character:SetAttribute("TreeJumpActive", true)

	if fromBranch then
		Effects.leafBurst(departure, Zones.surface(currentZone))
		Effects.bendBranch(currentZone, departure)
	end
	Effects.chakraFlash(departure)
	Effects.startSpeed()
	Effects.playSound(Config.JumpSoundId)
	if windTrail then
		pcall(windTrail.start, character)
	end
	playAnimation(trajectory.Duration)
	debugLog("salto", jumpId, "cadena", chainIndex, string.format("%.2fs", trajectory.Duration))
end

local function arrive()
	local trajectory = flight.Trajectory
	local zone, point = flight.Zone, flight.Point
	if (rootPart.Position - trajectory.End).Magnitude > Config.LandingSnapDistance then
		abort("lejos del aterrizaje")
		return
	end

	rootPart.CFrame = CFrame.lookAt(trajectory.End, trajectory.End + flatDirection(trajectory.End - trajectory.Start))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	previousZone = currentZone
	currentZone = zone
	lastLandTime = os.clock()

	Effects.leafBurst(point, Zones.surface(zone))
	Effects.chakraFlash(point)
	Effects.bendBranch(zone, point)
	Effects.playSound(Config.LandSoundId)

	local chained = nil
	if buffered and canTreeJump() then
		chained = nextTarget
		if not chained then
			local exclude = { [zone] = true }
			if previousZone then
				exclude[previousZone] = true
			end
			chained = findTarget(
				rootPart.Position,
				Config.ChainCone,
				exclude,
				flatDirection(trajectory.End - trajectory.Start),
				nil,
				chainIndex + 1
			)
		end
	end

	if chained then
		-- Touch-and-go: los pies tocan la rama un instante
		state = "Contact"
		flight = nil
		buffered = false
		contactTarget = chained
		contactUntil = os.clock() + Config.ContactTime
		velocity.VectorVelocity = Vector3.zero
		local position = rootPart.Position
		rootPart.CFrame = CFrame.lookAt(position, position + flatDirection(chained.RootTarget - position))
		nextIndicator:Show(chained.Zone, chained.Point)
	else
		perch()
	end
end

-- Entrada -------------------------------------------------------------------------

local function countPress()
	if isAirborne() then
		pressCount += 1
	else
		pressCount = 1
	end
end

local function onAction(_, inputState)
	if inputState == Enum.UserInputState.End then
		keyHeld = false
		pendingEntry = nil
		return Enum.ContextActionResult.Pass
	end
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	keyHeld = true
	lastPressTime = os.clock()

	if state == "Flying" then
		if flight and (os.clock() - flight.StartTime) / flight.Trajectory.Duration >= Config.BufferWindowStart then
			buffered = true
		end
		return Enum.ContextActionResult.Sink
	elseif state == "Contact" then
		return Enum.ContextActionResult.Sink
	end

	if not canTreeJump() then
		countPress()
		return Enum.ContextActionResult.Pass
	end

	if state == "Perched" or recentlyLanded() then
		updateTargets()
		if target then
			launch(target, recentlyLanded())
			return Enum.ContextActionResult.Sink
		end
		pressCount = 1
		return Enum.ContextActionResult.Pass
	end

	-- Idle
	if not isAirborne() then
		pressCount = 1
		return Enum.ContextActionResult.Pass
	end
	pressCount += 1
	if pressCount >= Config.EntryPressCount and target and entryAllowed(target) then
		if inCombat() then
			pendingEntry = { Since = os.clock(), Zone = target.Zone }
		else
			launch(target, false)
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindActionAtPriority(
	ACTION_NAME,
	onAction,
	false,
	Enum.ContextActionPriority.High.Value,
	table.unpack(Config.Keys)
)

-- Bucle principal -----------------------------------------------------------------

local function step(dt)
	if humanoid.Health <= 0 then
		return
	end
	local now = os.clock()

	if state == "Flying" and flight then
		local trajectory = flight.Trajectory
		local s = (now - flight.StartTime) / trajectory.Duration
		if s >= 1 then
			arrive()
		else
			local position, curveVelocity = Zones.evaluate(trajectory, s)
			local offset = position - rootPart.Position
			if offset.Magnitude > Config.StuckDistance then
				flight.StuckSince = flight.StuckSince or now
				if now - flight.StuckSince > Config.StuckTime then
					abort("chocó con algo")
					return
				end
			else
				flight.StuckSince = nil
			end
			velocity.VectorVelocity = curveVelocity + offset * Config.TrackingGain

			-- Cuerpo inclinado hacia adelante, se endereza al salir y al llegar
			local lean = Config.LeanAngle * math.clamp(math.min(s, 1 - s) / 0.15, 0, 1)
			local here = rootPart.Position
			rootPart.CFrame = CFrame.lookAt(here, here + flatDirection(trajectory.End - trajectory.Start))
				* CFrame.Angles(-math.rad(lean), 0, 0)
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	elseif state == "Contact" then
		velocity.VectorVelocity = Vector3.zero
		if now >= contactUntil then
			local chained = contactTarget
			if chained and canTreeJump() then
				launch(chained, true)
			else
				perch()
			end
		end
	else
		-- Suelo, rama o aire normal
		floorTimer += dt
		if floorTimer >= 0.1 then
			floorTimer = 0
			if now - lastLandTime < 0.3 and currentZone then
				state = "Perched"
			elseif not isAirborne() then
				-- Justo después de saltar el Humanoid todavía toca el suelo unos frames
				if now - lastPressTime > 0.25 then
					pressCount = 0
				end
				local zone = Zones.zoneUnder(feetPosition())
				if zone then
					if zone ~= currentZone then
						previousZone = currentZone
						currentZone = zone
					end
					state = "Perched"
				else
					state = "Idle"
					currentZone = nil
					chainIndex = 0
				end
			elseif state == "Perched" then
				state = "Idle"
			end
		end

		if pendingEntry then
			if not keyHeld or not target or target.Zone ~= pendingEntry.Zone then
				pendingEntry = nil
			elseif now - pendingEntry.Since >= Config.CombatHoldTime then
				pendingEntry = nil
				launch(target, false)
			end
		end
	end

	scanTimer += dt
	if scanTimer >= 1 / Config.ScanRate then
		scanTimer = 0
		updateTargets()
	end
end

table.insert(connections, RunService.Heartbeat:Connect(step))

-- Servidor ------------------------------------------------------------------------

table.insert(connections, resultEvent.OnClientEvent:Connect(function(id, approved, reason)
	if approved then
		return
	end
	debugLog("servidor rechazó", id, reason)
	if flight and flight.Id == id then
		abort("servidor: " .. tostring(reason))
	end
end))

-- Efectos de otros jugadores (su animación ya se replica sola)
table.insert(connections, replicateEvent.OnClientEvent:Connect(function(jumper, departure, landingPoint, duration, zone)
	if jumper == player then
		return
	end
	Effects.chakraFlash(departure)
	task.delay(duration, function()
		local surface = if zone and zone.Parent then Zones.surface(zone) else "Wood"
		Effects.leafBurst(landingPoint, surface)
		Effects.chakraFlash(landingPoint)
		if zone and zone.Parent then
			Effects.bendBranch(zone, landingPoint)
		end
	end)
end))

for _, name in LOCK_ATTRIBUTES do
	table.insert(connections, character:GetAttributeChangedSignal(name):Connect(function()
		if isLocked() then
			abort("bloqueado")
		end
	end))
end

-- Limpieza ------------------------------------------------------------------------

local cleanedUp = false
local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true
	abort("limpieza")
	ContextActionService:UnbindAction(ACTION_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	mainIndicator:Destroy()
	nextIndicator:Destroy()
end

humanoid.Died:Connect(cleanup)
character.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanup()
	end
end)
