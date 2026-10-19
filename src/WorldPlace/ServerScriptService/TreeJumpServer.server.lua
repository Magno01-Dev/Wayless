--[[
	TreeJumpServer · Script en ServerScriptService

	El cliente salta al instante y manda la solicitud; el servidor valida en paralelo
	con la misma geometría (TreeJump.Zones). Si rechaza, avisa y el cliente corta el vuelo.

	Validaciones conservadas del sistema anterior:
		agua (con la excepción de WaterWalking), downed/carry, misión, ChakraCharging,
		dash, stamina (StaminaConfig/StaminaService si existen) y cooldown en combate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("TreeJump")
local Config = require(folder:WaitForChild("Config"))
local Zones = require(folder:WaitForChild("Zones"))

-- Remotes ---------------------------------------------------------------------------

local remotes = folder:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = folder
end

local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

local requestEvent = getRemote("Request")
local resultEvent = getRemote("Result")
local replicateEvent = getRemote("Replicate")

-- Stamina (opcional) ----------------------------------------------------------------

local function optionalRequire(parent, name)
	local module = parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn("[TreeJump] No se pudo cargar " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

local StaminaConfig = optionalRequire(ReplicatedStorage, "StaminaConfig")
local StaminaService = optionalRequire(ServerScriptService, "StaminaService")

local function spendStamina(player, combat)
	local action = StaminaConfig and StaminaConfig.Actions and StaminaConfig.Actions.TreeJump
	if not (action and StaminaService) then
		return true
	end
	local cost = if combat then action.CombatTaggedCost else action.OpenWorldCost
	if not cost or cost <= 0 then
		return true
	end
	return StaminaService.TrySpend(player, cost, "TreeJump")
end

local function debugLog(message)
	if Config.Debug then
		print("[TreeJump-Server] " .. message)
	end
end

-- Guardias --------------------------------------------------------------------------

local LOCK_ATTRIBUTES = { "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting", "IsCarrying" }

local function isLocked(character)
	for _, name in LOCK_ATTRIBUTES do
		if character:GetAttribute(name) == true then
			return true
		end
	end
	return false
end

local WATER_VOXEL_RESOLUTION = 4
local WATER_OCCUPANCY_THRESHOLD = 0.1
local WATER_SAMPLE_HALF_SIZE = Vector3.new(1.5, 1.8, 1.5)

local function isRootInWater(root)
	local region = Region3.new(root.Position - WATER_SAMPLE_HALF_SIZE, root.Position + WATER_SAMPLE_HALF_SIZE)
		:ExpandToGrid(WATER_VOXEL_RESOLUTION)
	local materials, occupancies = Workspace.Terrain:ReadVoxels(region, WATER_VOXEL_RESOLUTION)
	for x = 1, #materials do
		for y = 1, #materials[x] do
			for z = 1, #materials[x][y] do
				if materials[x][y][z] == Enum.Material.Water and occupancies[x][y][z] >= WATER_OCCUPANCY_THRESHOLD then
					return true
				end
			end
		end
	end
	return false
end

local function inWater(character, humanoid, root)
	if humanoid:GetState() == Enum.HumanoidStateType.Swimming or character:GetAttribute("WaterJumping") == true then
		return true
	end
	if character:GetAttribute("WaterWalking") == true then
		return false
	end
	return humanoid.FloorMaterial == Enum.Material.Water or isRootInWater(root)
end

local function inCombat(player, character)
	return player:GetAttribute(Config.CombatAttribute) == true or character:GetAttribute(Config.CombatAttribute) == true
end

-- Estado por jugador ----------------------------------------------------------------

-- { Active = { Id, Landing, StartedAt, Duration } | nil, LastCombatJump }
local states = {}

local function clearAttributes(character)
	if character and character.Parent then
		character:SetAttribute("IsTreeJumping", false)
		character:SetAttribute("TreeJumpProtected", false)
		character:SetAttribute("TreeJumpActive", false)
		character:SetAttribute("TreeJumpUses", 0)
	end
end

local function cancelActive(player, character, reason)
	local state = states[player]
	if state and state.Active then
		resultEvent:FireClient(player, state.Active.Id, false, reason)
		state.Active = nil
	end
	clearAttributes(character)
	debugLog(player.Name .. " cancelado: " .. reason)
end

local function setupCharacter(player, character)
	local state = states[player]
	if state then
		state.Active = nil
		state.LastCombatJump = -math.huge
	end

	character:SetAttribute("CoreCooldown_TreeJump_Label", "Tree Jump")
	character:SetAttribute("CoreCooldown_TreeJump_StartsAt", 0)
	character:SetAttribute("CoreCooldown_TreeJump_EndsAt", 0)
	clearAttributes(character)

	local function onLockChanged()
		if isLocked(character) then
			cancelActive(player, character, "bloqueado")
		end
	end
	for _, name in LOCK_ATTRIBUTES do
		character:GetAttributeChangedSignal(name):Connect(onLockChanged)
	end
	character:GetAttributeChangedSignal("MissionInteractionActive"):Connect(function()
		if character:GetAttribute("MissionInteractionActive") == true then
			cancelActive(player, character, "misión")
		end
	end)
end

local function onPlayerAdded(player)
	states[player] = { Active = nil, LastCombatJump = -math.huge }
	if player.Character then
		setupCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

-- Solicitud -------------------------------------------------------------------------

requestEvent.OnServerEvent:Connect(function(player, id, zone, point, clientStart, chainIndex)
	local state = states[player]
	if not state then
		return
	end
	if typeof(id) ~= "number" or typeof(point) ~= "Vector3" or typeof(clientStart) ~= "Vector3"
		or typeof(chainIndex) ~= "number" or chainIndex ~= chainIndex then
		return
	end

	local function reject(reason)
		debugLog(player.Name .. " rechazado: " .. reason)
		resultEvent:FireClient(player, id, false, reason)
	end

	if not Zones.isUsable(zone) then
		return reject("zona inválida")
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then
		return reject("sin personaje")
	end
	if isLocked(character) then
		return reject("bloqueado")
	end
	if inWater(character, humanoid, root) then
		return reject("agua")
	end
	if character:GetAttribute("ChakraCharging") == true then
		return reject("cargando chakra")
	end
	if character:GetAttribute("MissionInteractionActive") == true then
		return reject("misión")
	end
	if character:GetAttribute("IsDashing") == true then
		return reject("dash")
	end

	-- Un salto a la vez (con margen para encadenar pese a la latencia)
	local now = os.clock()
	local active = state.Active
	if active and now < active.StartedAt + active.Duration - Config.ChainGrace then
		return reject("salto en curso")
	end

	-- El inicio debe coincidir con donde está el personaje, o con el aterrizaje anterior
	local nearRoot = (clientStart - root.Position).Magnitude <= Config.PositionTolerance
	local nearLanding = active ~= nil and (clientStart - active.Landing).Magnitude <= Config.ChainPositionTolerance
	if not (nearRoot or nearLanding) then
		return reject("posición de inicio")
	end

	-- El punto de aterrizaje debe estar sobre la zona
	local a, b = Zones.segment(zone)
	if (Zones.closestPointOnSegment(point, a, b) - point).Magnitude > Config.LandingTolerance then
		return reject("punto fuera de la zona")
	end

	local rootTarget = point + Vector3.yAxis * Zones.standOffset(humanoid, root)
	local delta = rootTarget - clientStart
	local distance = delta.Magnitude
	if distance < Config.MinDistance * 0.5 or distance > Config.MaxDistance + 5
		or delta.Y > Config.MaxRise + 2 or -delta.Y > Config.MaxDrop + 2 then
		return reject("fuera de alcance")
	end

	chainIndex = math.clamp(math.floor(chainIndex), 0, 50)
	local trajectory = Zones.trajectory(clientStart, rootTarget, chainIndex)
	local ignore = { character }
	local branch = Zones.sourceBranch(zone)
	if branch then
		table.insert(ignore, branch)
	end
	if not Zones.isPathClear(trajectory, ignore) then
		return reject("camino bloqueado")
	end

	local combat = inCombat(player, character)
	if combat and Workspace:GetServerTimeNow() - state.LastCombatJump < Config.CombatCooldown then
		return reject("cooldown de combate")
	end
	local staminaOk, staminaReason = spendStamina(player, combat)
	if not staminaOk then
		return reject("stamina: " .. tostring(staminaReason))
	end

	-- Aprobado ------------------------------------------------------------------
	local record = { Id = id, Landing = rootTarget, StartedAt = now, Duration = trajectory.Duration }
	state.Active = record

	if combat then
		local startsAt = Workspace:GetServerTimeNow()
		state.LastCombatJump = startsAt
		character:SetAttribute("CoreCooldown_TreeJump_StartsAt", startsAt)
		character:SetAttribute("CoreCooldown_TreeJump_EndsAt", startsAt + Config.CombatCooldown)
	end

	character:SetAttribute("IsTreeJumping", true)
	character:SetAttribute("TreeJumpProtected", true)
	character:SetAttribute("TreeJumpUses", chainIndex + 1)
	resultEvent:FireClient(player, id, true)

	local departure = clientStart - Vector3.yAxis * Zones.standOffset(humanoid, root)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			replicateEvent:FireClient(other, player, departure, point, trajectory.Duration, zone)
		end
	end

	task.delay(trajectory.Duration + Config.ServerFinishBuffer, function()
		-- Si ya empezó otro salto (encadenado), ese se encarga
		if states[player] ~= state or state.Active ~= record then
			return
		end
		state.Active = nil
		if Config.CorrectPosition and root.Parent and (root.Position - rootTarget).Magnitude > Config.CorrectionThreshold then
			root.CFrame = CFrame.new(rootTarget) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
		end
		clearAttributes(character)
	end)

	debugLog(string.format("%s salto %d aprobado (%.0f studs, %.2fs)", player.Name, id, distance, trajectory.Duration))
end)

print("[TreeJump] Servidor listo")
