-- ServerScriptService > JutsuSystem > TechniqueKit > Taijutsu  (ModuleScript)
--
-- Base común de las técnicas de taijutsu. Va FUERA de la carpeta Jutsus (no es un jutsu).
--
-- - Gastan STAMINA (Config.StaminaCost; JutsuServer v12 + coste por stamina). El sello de
--   supresión no las bloquea porque no usan chakra.
-- - Los golpes pasan por CombatServer (ServerStorage > CombatInternal > ExternalMeleeHit):
--   mismo bloqueo frontal, guardia, sustitución, Downed, contador de combo y VFX de impacto
--   que los M1.
-- - Efectos visuales: remote ReplicatedStorage > JutsuSystem > Remotes > TaijutsuFX
--   (StarterPlayerScripts > TaijutsuClient).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local throwables = ReplicatedStorage:WaitForChild("Throwables")
local Targets = require(throwables:WaitForChild("Targets"))

local Taijutsu = {}

-- Remote -------------------------------------------------------------------------------------

local REMOTE_NAME = "TaijutsuFX"
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

task.spawn(getRemote)

function Taijutsu.fxAll(action: string, data: {[string]: any})
	getRemote():FireAllClients(action, data)
end

function Taijutsu.fxTo(player: Player?, action: string, data: {[string]: any})
	if player and player.Parent then
		getRemote():FireClient(player, action, data)
	end
end

-- APIs de otros sistemas ---------------------------------------------------------------------

local function internalFunction(folderName: string, name: string): BindableFunction?
	local folder = ServerStorage:WaitForChild(folderName, 10)
	local found = folder and folder:WaitForChild(name, 10)
	if found and found:IsA("BindableFunction") then
		return found
	end
	warn("[Taijutsu] Falta ServerStorage > " .. folderName .. " > " .. name)
	return nil
end

local meleeHit: BindableFunction? = nil
local applyStun: BindableFunction? = nil
local interruptCast: BindableFunction? = nil

--[[
	Golpe de taijutsu con las reglas del combate cuerpo a cuerpo.
	spec: ver CombatServer (ExternalMeleeHit). Devuelve el resultado ("Blocked", "Damaged"…).
]]
function Taijutsu.hit(attacker: Player, targetCharacter: Model, spec: {[string]: any}): string
	meleeHit = meleeHit or internalFunction("CombatInternal", "ExternalMeleeHit")
	if not meleeHit then
		return "Invalid"
	end
	local ok, result = pcall(function()
		return (meleeHit :: BindableFunction):Invoke(attacker, targetCharacter, spec)
	end)
	if not ok then
		warn("[Taijutsu] ExternalMeleeHit falló: " .. tostring(result))
		return "Invalid"
	end
	return result
end

function Taijutsu.stun(character: Model, duration: number, playReaction: boolean?)
	applyStun = applyStun or internalFunction("CombatInternal", "ApplyStun")
	if applyStun then
		pcall(function()
			(applyStun :: BindableFunction):Invoke(character, duration, playReaction == true)
		end)
	end
end

-- Corta los sellos de mano de un jugador (si su jutsu todavía no salió)
function Taijutsu.interrupt(player: Player?): boolean
	if not player then
		return false
	end
	interruptCast = interruptCast or internalFunction("JutsuInternal", "InterruptCast")
	if not interruptCast then
		return false
	end
	local ok, result = pcall(function()
		return (interruptCast :: BindableFunction):Invoke(player)
	end)
	return ok and result == true
end

-- Geometría ----------------------------------------------------------------------------------

function Taijutsu.flat(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else nil
end

-- Pies en el suelo: el suelo está a menos de `height` studs bajo el HumanoidRootPart
function Taijutsu.isGrounded(character: Model, height: number): boolean
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return Targets.castWorld(root.Position, Vector3.yAxis * -height, { character }) ~= nil
end

local function canBeHit(character: Model): boolean
	return character:GetAttribute("IsMissionNPC") ~= true
		and character:GetAttribute("CombatImmune") ~= true
end

--[[
	Objetivos alrededor del lanzador:
	  range       distancia horizontal máxima
	  arcDegrees  ancho del arco frente a `forward` (360 = alrededor)
	  maxHeight   diferencia de altura máxima
]]
function Taijutsu.targetsAround(character: Model, forward: Vector3, range: number, arcDegrees: number, maxHeight: number): {any}
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return {}
	end
	local found = {}
	local halfArc = math.cos(math.rad(math.min(arcDegrees, 360) / 2))
	for _, candidate in Targets.list(character) do
		if not canBeHit(candidate.Character) then
			continue
		end
		local offset = candidate.Root.Position - root.Position
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		if flatOffset.Magnitude > range or math.abs(offset.Y) > maxHeight then
			continue
		end
		if arcDegrees < 360 and flatOffset.Magnitude > 0.5 and forward:Dot(flatOffset.Unit) < halfArc then
			continue
		end
		-- Sin paredes en medio
		if Targets.castWorld(root.Position, offset, { character, candidate.Character }) then
			continue
		end
		table.insert(found, candidate)
	end
	return found
end

-- Postura de contraataque --------------------------------------------------------------------
--
-- La técnica pone CounterStanceUntil en el personaje. DamageService esquiva el primer golpe
-- cuerpo a cuerpo en esa ventana y dispara CombatInternal > CounterTriggered; aquí se
-- ejecuta la respuesta registrada con Taijutsu.onCounter.

local counterHandler: ((Model, Player, string) -> ())? = nil

function Taijutsu.onCounter(handler: (Model, Player, string) -> ())
	counterHandler = handler
end

task.spawn(function()
	local folder = ServerStorage:WaitForChild("CombatInternal", 30)
	local event = folder and folder:WaitForChild("CounterTriggered", 30)
	if not event or not event:IsA("BindableEvent") then
		warn("[Taijutsu] Falta ServerStorage > CombatInternal > CounterTriggered (¿DamageService v1.2?)")
		return
	end
	event.Event:Connect(function(defender: Model, attacker: Player, sourceType: string)
		if counterHandler then
			local ok, err = pcall(counterHandler, defender, attacker, sourceType)
			if not ok then
				warn("[Taijutsu] Contraataque: " .. tostring(err))
			end
		end
	end)
end)

-- Construcción de los módulos de jutsu -------------------------------------------------------

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and value.Magnitude > 0.001 and value.Magnitude < 1e6
end

--[[
	Taijutsu.build(module, execute)
	execute(context, forward) se llama en el marcador ProjectileSpawn de la animación.
	forward = dirección horizontal hacia el retículo (o hacia donde mira el personaje).
]]
function Taijutsu.build(module: any, execute: (any, Vector3) -> ()): any
	module.TechniqueCategory = module.TechniqueCategory or "Taijutsu"
	module.AllowedCastMarkers = module.AllowedCastMarkers or {
		ReleaseStart = true,
		ProjectileSpawn = true,
		RecoveryStart = true,
		CastEnd = true,
	}

	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		local root = character:FindFirstChild("HumanoidRootPart")
		local direction = if typeof(payload) == "table" and isFiniteVector(payload.Direction)
			then payload.Direction
			elseif root then root.CFrame.LookVector
			else Vector3.new(0, 0, -1)
		return true, "OK", { Direction = direction }
	end

	function module.OnCastStarted(_context: any) end

	function module.OnCastMarker(context: any, semanticMarker: string, _source: string, markerPayload: any?)
		if semanticMarker ~= "ProjectileSpawn" or context.TaijutsuDone then
			return
		end
		context.TaijutsuDone = true
		if typeof(markerPayload) == "table" and isFiniteVector(markerPayload.Direction) then
			context.RequestData.Direction = markerPayload.Direction
		end
		local character: Model = context.Character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not context.Player.Parent or context.Player.Character ~= character
			or not humanoid or humanoid.Health <= 0 or not root
			or character:GetAttribute("IsStunned") == true
			or character:GetAttribute("CombatRagdolled") == true then
			return -- golpeado durante la preparación: la técnica no sale
		end
		local forward = Taijutsu.flat(context.RequestData.Direction)
			or Taijutsu.flat(root.CFrame.LookVector)
			or Vector3.new(0, 0, -1)
		local ok, err = pcall(execute, context, forward)
		if not ok then
			warn("[Taijutsu] " .. tostring(module.Id) .. ": " .. tostring(err))
		end
	end

	function module.OnCastEnded(_context: any, _reason: string) end

	function module.Execute(context: any)
		task.delay(context.Config.CastTime or 0.3, function()
			module.OnCastMarker(context, "ProjectileSpawn", "Legacy", nil)
		end)
	end

	return module
end

return Taijutsu
