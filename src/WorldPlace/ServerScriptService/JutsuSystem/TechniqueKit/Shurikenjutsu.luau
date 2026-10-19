-- ServerScriptService > JutsuSystem > TechniqueKit > Shurikenjutsu  (ModuleScript)
--
-- Base común de los jutsus de shurikenjutsu. Va FUERA de la carpeta Jutsus para que
-- el TechniqueRegistry no lo cargue como jutsu.
--
-- Cada jutsu declara:
--     Module.Weapon = "Tech_..."            definición en ReplicatedStorage > Throwables > Definitions
--     Module.Ammo = { Shuriken = 1, ... }   lo que gasta de la Ninja Bag (inventario)
--     Module.GroundTarget = true            (opcional) el destino se baja al suelo
-- y llama a Shurikenjutsu.build(Module), que le agrega SanitizeRequest / OnCastMarker / Execute.
--
-- Flujo:
--   1. Al pedir el jutsu: se revisa dirección, bolsa equipada y munición (antes de gastar chakra).
--   2. En el marcador ProjectileSpawn: se gasta la munición y el sistema de lanzables dispara
--      (ServerStorage > ThrowablesInternal > SpawnTechnique). Curvas, choques, impactos y
--      dibujado son los mismos que los de los lanzables.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local throwables = ReplicatedStorage:WaitForChild("Throwables")
local Definitions = require(throwables:WaitForChild("Definitions"))
local Targets = require(throwables:WaitForChild("Targets"))

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local Shurikenjutsu = {}

local spawnTechnique: BindableFunction? = nil

local function getSpawnTechnique(): BindableFunction?
	if spawnTechnique and spawnTechnique.Parent then
		return spawnTechnique
	end
	local internal = ServerStorage:WaitForChild("ThrowablesInternal", 5)
	local found = internal and internal:WaitForChild("SpawnTechnique", 5)
	if found and found:IsA("BindableFunction") then
		spawnTechnique = found
		return found
	end
	warn("[Shurikenjutsu] No encontré ServerStorage > ThrowablesInternal > SpawnTechnique (¿falta ThrowableServer v3.2?)")
	return nil
end

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < 1e6 and math.abs(value.Y) < 1e6 and math.abs(value.Z) < 1e6
end

local function sanitizeDirection(character: Model, payload: any): (boolean, string, Vector3?)
	if typeof(payload) ~= "table" or not isFiniteVector(payload.Direction)
		or payload.Direction.Magnitude < 0.001 then
		return false, "InvalidDirection", nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "NoRoot", nil
	end
	local direction = payload.Direction.Unit
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flat.Magnitude > 0.001 and look.Magnitude > 0.001 and look.Unit:Dot(flat.Unit) < -0.25 then
		return false, "AimBehindCharacter", nil
	end
	return true, "OK", direction
end

local function hasNinjaBag(player: Player): boolean
	local bag = player:GetAttribute("EquippedNinjaBag")
	return typeof(bag) == "string" and bag ~= ""
end

function Shurikenjutsu.checkAmmo(player: Player, ammo: {[string]: number}): (boolean, string)
	if not hasNinjaBag(player) then
		return false, "NoNinjaBag"
	end
	for itemId, amount in ammo do
		if InventoryService.GetAmount(player, itemId) < amount then
			return false, "NotEnough" .. itemId
		end
	end
	return true, "OK"
end

function Shurikenjutsu.consumeAmmo(player: Player, ammo: {[string]: number}): boolean
	if not Shurikenjutsu.checkAmmo(player, ammo) then
		return false
	end
	for itemId, amount in ammo do
		local ok = InventoryService.Consume(player, itemId, amount)
		if not ok then
			return false
		end
	end
	return true
end

local function throwOrigin(character: Model): Vector3?
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	local head = character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else nil
end

function Shurikenjutsu.fire(module: any, context: any)
	if context.ShurikenjutsuFired then
		return
	end
	context.ShurikenjutsuFired = true

	local player: Player = context.Player
	local character: Model = context.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if not player.Parent or player.Character ~= character or not humanoid or humanoid.Health <= 0
		or not head or not head:IsA("BasePart") then
		return
	end

	local definition = Definitions[module.Weapon]
	local origin = throwOrigin(character)
	if typeof(definition) ~= "table" or not origin then
		warn("[Shurikenjutsu] Falta la definición " .. tostring(module.Weapon) .. " en Throwables.Definitions")
		return
	end

	-- La munición se gasta al soltar (si alguien la gastó mientras hacías los sellos, falla)
	if not Shurikenjutsu.consumeAmmo(player, module.Ammo) then
		return
	end

	local direction = context.RequestData.Direction
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then
		direction = head.CFrame.LookVector
	end
	-- Misma ayuda de apuntado que los lanzables, desde la línea cabeza → retículo
	local target = Targets.solveAim(definition, definition.Levels[0], origin, head.Position, direction.Unit, character)
	if module.GroundTarget then
		local ground = Targets.castWorld(target + Vector3.yAxis * 2, Vector3.yAxis * -80, { character })
		if ground then
			target = ground.Position
		end
	end

	local spawn = getSpawnTechnique()
	if spawn then
		spawn:Invoke(player, module.Weapon, origin, target)
	end
end

function Shurikenjutsu.build(module: any): any
	module.TechniqueCategory = module.TechniqueCategory or "Shurikenjutsu"

	module.AllowedCastMarkers = module.AllowedCastMarkers or {
		ReleaseStart = true,
		ProjectileSpawn = true,
		RecoveryStart = true,
		CastEnd = true,
	}

	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		local ok, reason, direction = sanitizeDirection(character, payload)
		if not ok then
			return false, reason, nil
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return false, "NoPlayer", nil
		end
		local hasAmmo, ammoReason = Shurikenjutsu.checkAmmo(player, module.Ammo)
		if not hasAmmo then
			return false, ammoReason, nil
		end
		return true, "OK", { Direction = direction }
	end

	function module.OnCastStarted(_context: any) end

	function module.OnCastMarker(context: any, semanticMarker: string, _source: string, markerPayload: any?)
		if semanticMarker ~= "ProjectileSpawn" then
			return
		end
		-- Dirección fresca al soltar (el jugador pudo girar durante los sellos)
		if typeof(markerPayload) == "table" then
			local ok, _, direction = sanitizeDirection(context.Character, markerPayload)
			if ok and direction then
				context.RequestData.Direction = direction
			end
		end
		Shurikenjutsu.fire(module, context)
	end

	function module.OnCastEnded(_context: any, _reason: string) end

	-- Camino antiguo (sin marcadores)
	function module.Execute(context: any)
		task.delay(context.Config.CastTime or 0.4, function()
			Shurikenjutsu.fire(module, context)
		end)
	end

	return module
end

return Shurikenjutsu
