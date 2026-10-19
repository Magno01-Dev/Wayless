-- ServerScriptService > JutsuSystem > TechniqueKit > Genjutsu  (ModuleScript)
--
-- Base común de los genjutsu. Va FUERA de la carpeta Jutsus (no es un jutsu).
--
-- Regla de campo visual (decidido en PROGRESION_TECNICAS):
--   El genjutsu solo entra si el OBJETIVO te tiene en su campo visual:
--   el ángulo entre hacia dónde mira y la dirección hacia ti es ≤ 70° (cono de 140°)
--   y no hay paredes en medio. Si te da la espalda, falla (el chakra ya se gastó).
--
-- Salidas de un genjutsu (siempre hay alguna):
--   Genjutsu Kai, recibir daño (BreakDamage o más de un golpe) o que se acabe el tiempo.
--
-- Efectos visuales: remote ReplicatedStorage > JutsuSystem > Remotes > GenjutsuFX,
-- los dibuja StarterPlayerScripts > GenjutsuClient.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))

local throwables = ReplicatedStorage:WaitForChild("Throwables")
local Targets = require(throwables:WaitForChild("Targets"))

local Genjutsu = {}

Genjutsu.FieldOfView = 70 -- medio ángulo del cono de visión del objetivo (140° en total)
Genjutsu.BreakDamage = 5 -- un golpe de esto o más rompe el genjutsu
Genjutsu.StatusCategory = "Genjutsu" -- Kai quita todos los estados de esta categoría

-- Remote -------------------------------------------------------------------------------------

local REMOTE_NAME = "GenjutsuFX"
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	local jutsuSystem = ReplicatedStorage:WaitForChild("JutsuSystem")
	local remotes = jutsuSystem:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = jutsuSystem
	end
	local found = remotes:FindFirstChild(REMOTE_NAME)
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = REMOTE_NAME
		found.Parent = remotes
	end
	remote = found :: RemoteEvent
	return remote :: RemoteEvent
end

task.spawn(getRemote) -- existe desde que arranca el servidor

function Genjutsu.fxTo(player: Player?, action: string, data: {[string]: any})
	if player and player.Parent then
		getRemote():FireClient(player, action, data)
	end
end

function Genjutsu.fxAll(action: string, data: {[string]: any})
	getRemote():FireAllClients(action, data)
end

-- Visión ------------------------------------------------------------------------------------

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function eyeOf(character: Model): Vector3?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = rootOf(character)
	return if root then root.Position + Vector3.yAxis * 1.5 else nil
end

local function lineOfSight(from: Vector3, to: Vector3, ignore: {Instance}): boolean
	return Targets.castWorld(from, to - from, ignore) == nil
end

--[[
	¿El viewer te ve? Ángulo horizontal entre hacia dónde mira su cuerpo y la dirección hacia
	subjectPosition, más línea de visión. (El servidor no recibe la rotación de la cabeza de un
	jugador, solo la del cuerpo; en CombatMode el cuerpo mira hacia la cámara.)
]]
function Genjutsu.canSee(viewer: Model, subject: Model): (boolean, string)
	local root = rootOf(viewer)
	local eye = eyeOf(viewer)
	local subjectEye = eyeOf(subject)
	if not root or not eye or not subjectEye then
		return false, "NoBody"
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local toSubject = Vector3.new(subjectEye.X - eye.X, 0, subjectEye.Z - eye.Z)
	if look.Magnitude > 1e-3 and toSubject.Magnitude > 1e-3 then
		local angle = math.deg(math.acos(math.clamp(look.Unit:Dot(toSubject.Unit), -1, 1)))
		if angle > Genjutsu.FieldOfView then
			return false, "NotInView"
		end
	end
	if not lineOfSight(eye, subjectEye, { viewer, subject }) then
		return false, "Blocked"
	end
	return true, "OK"
end

--[[
	Objetivo: el más cercano a la línea de apuntado (cabeza → retículo) dentro de range y de
	un cono de maxAngle grados, con línea de visión desde el lanzador.
]]
function Genjutsu.findTarget(context: any, direction: Vector3, range: number, maxAngle: number): any?
	local character: Model = context.Character
	local eye = eyeOf(character)
	if not eye then
		return nil
	end
	local best, bestAngle = nil, maxAngle
	for _, candidate in Targets.list(character) do
		if candidate.Character:GetAttribute("IsMissionNPC") == true
			or candidate.Character:GetAttribute("CombatImmune") == true then
			continue
		end
		local candidateEye = eyeOf(candidate.Character) or candidate.Root.Position
		local offset = candidateEye - eye
		local distance = offset.Magnitude
		if distance > range or distance < 0.5 then
			continue
		end
		local angle = math.deg(math.acos(math.clamp(direction.Unit:Dot(offset.Unit), -1, 1)))
		if angle <= bestAngle and lineOfSight(eye, candidateEye, { character, candidate.Character }) then
			best, bestAngle = candidate, angle
		end
	end
	return best
end

-- Estado de genjutsu ------------------------------------------------------------------------

type ActiveGenjutsu = {
	Id: number,
	Kind: string,
	StatusId: string,
	HealthConnection: RBXScriptConnection?,
	Player: Player?,
}

local active: {[Model]: ActiveGenjutsu} = {}
local sequence = 0

function Genjutsu.isAffected(character: Model): boolean
	return active[character] ~= nil
end

function Genjutsu.release(character: Model, reason: string)
	local entry = active[character]
	if not entry then
		return false
	end
	active[character] = nil
	if entry.HealthConnection then
		entry.HealthConnection:Disconnect()
	end
	StatusEffectService.Clear(character, Genjutsu.StatusCategory)
	character:SetAttribute("InGenjutsu", nil)
	Genjutsu.fxTo(entry.Player, "End", { Id = entry.Id, Kind = entry.Kind, Reason = reason })
	return true
end

--[[
	Aplica un genjutsu a target ({ Character, Humanoid, Root }).
	options = { Kind, StatusId, Duration, Damage?, Attacker, DamageService }
]]
function Genjutsu.apply(target: any, options: {[string]: any}): boolean
	local character: Model = target.Character
	local humanoid: Humanoid = target.Humanoid
	if not character.Parent or humanoid.Health <= 0 then
		return false
	end

	-- Uno nuevo reemplaza al anterior
	Genjutsu.release(character, "Replaced")

	local player = Players:GetPlayerFromCharacter(character)
	if options.Damage and options.Damage > 0 and options.DamageService then
		pcall(options.DamageService.Apply, {
			TargetCharacter = character,
			TargetHumanoid = humanoid,
			TargetPlayer = player,
			Attacker = options.Attacker,
			Damage = options.Damage,
			SourceType = "Genjutsu",
			SourceId = options.Kind,
			IgnoreArmor = true,
		})
	end

	local applied = StatusEffectService.Apply(character, options.StatusId, {
		Duration = options.Duration,
		SourcePlayer = options.Attacker,
		SourceCharacter = options.Attacker and options.Attacker.Character or nil,
	})
	if not applied then
		warn("[Genjutsu] No pude aplicar el estado " .. tostring(options.StatusId) .. " (¿falta en StatusEffectDefinitions?)")
	end

	sequence += 1
	local id = sequence
	local entry: ActiveGenjutsu = {
		Id = id,
		Kind = options.Kind,
		StatusId = options.StatusId,
		HealthConnection = nil,
		Player = player,
	}
	active[character] = entry
	character:SetAttribute("InGenjutsu", options.Kind)

	-- Recibir un golpe fuerte te saca del genjutsu
	local lastHealth = humanoid.Health
	entry.HealthConnection = humanoid.HealthChanged:Connect(function(health)
		if lastHealth - health >= Genjutsu.BreakDamage then
			Genjutsu.release(character, "Damage")
		end
		lastHealth = health
	end)

	task.delay(options.Duration, function()
		if active[character] == entry then
			Genjutsu.release(character, "Expired")
		end
	end)

	Genjutsu.fxTo(player, "Start", { Id = id, Kind = options.Kind, Duration = options.Duration })
	return true
end

-- Limpieza al morir / salir
Players.PlayerRemoving:Connect(function(player)
	local character = player.Character
	if character and active[character] then
		Genjutsu.release(character, "Left")
	end
end)

-- Construcción de los módulos de jutsu ----------------------------------------------------

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and value.Magnitude > 0.001 and value.Magnitude < 1e6
end

--[[
	Genjutsu.build(module, execute)
	execute(context, direction) se llama en el marcador ProjectileSpawn (fin de los sellos).
]]
function Genjutsu.build(module: any, execute: (any, Vector3) -> ()): any
	module.TechniqueCategory = module.TechniqueCategory or "Genjutsu"
	module.AllowedCastMarkers = module.AllowedCastMarkers or {
		ReleaseStart = true,
		ProjectileSpawn = true,
		RecoveryStart = true,
		CastEnd = true,
	}

	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		local direction = if typeof(payload) == "table" and isFiniteVector(payload.Direction)
			then payload.Direction.Unit
			else nil
		if not direction then
			local root = rootOf(character)
			direction = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
		end
		-- Sin nadie a quien apuntar no empieza (no gasta chakra). Que el objetivo
		-- no te vea sí se descubre al final y sí cuesta el chakra.
		if module.Precheck then
			local ok, reason = module.Precheck(character, direction)
			if not ok then
				return false, reason or "NoTarget", nil
			end
		end
		return true, "OK", { Direction = direction }
	end

	function module.OnCastStarted(_context: any) end

	function module.OnCastMarker(context: any, semanticMarker: string, _source: string, markerPayload: any?)
		if semanticMarker ~= "ProjectileSpawn" or context.GenjutsuDone then
			return
		end
		context.GenjutsuDone = true
		if typeof(markerPayload) == "table" and isFiniteVector(markerPayload.Direction) then
			context.RequestData.Direction = markerPayload.Direction.Unit
		end
		local humanoid = context.Character:FindFirstChildOfClass("Humanoid")
		if not context.Player.Parent or context.Player.Character ~= context.Character
			or not humanoid or humanoid.Health <= 0 then
			return
		end
		local ok, err = pcall(execute, context, context.RequestData.Direction)
		if not ok then
			warn("[Genjutsu] " .. tostring(module.Id) .. ": " .. tostring(err))
		end
	end

	function module.OnCastEnded(_context: any, _reason: string) end

	function module.Execute(context: any)
		task.delay(context.Config.CastTime or 0.4, function()
			module.OnCastMarker(context, "ProjectileSpawn", "Legacy", nil)
		end)
	end

	return module
end

return Genjutsu
