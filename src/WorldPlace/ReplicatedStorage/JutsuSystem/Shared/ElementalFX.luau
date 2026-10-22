--!strict
-- ReplicatedStorage > JutsuSystem > Shared > ElementalFX
--
-- Estándar de VFX para los jutsus elementales:
--   el SERVIDOR solo decide y avisa (empieza, impacta, termina);
--   cada CLIENTE dibuja todo (ElementalFXRenderer + módulos en JutsuSystem > ElementalFX).
--
-- Así los efectos se ven fluidos, no cargan al servidor y no replican cientos
-- de partes por frame.
--
-- Uso en el servidor:
--   ElementalFX.Fire("StaticBurst", "Burst", { Position = p, Radius = 11 })
--   local id = ElementalFX.Projectile("AirBullet", character, origin, direction, speed, maxDistance, radius)
--   ElementalFX.ProjectileHit(id, position, normal)   -- golpe que no detiene (atraviesa)
--   ElementalFX.ProjectileEnd(id, position, normal)   -- impacto (o nil, nil = se acabó el alcance)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local REMOTE_NAME = "ElementalFX"

local ElementalFX = {}

local remote: RemoteEvent? = nil
local sequence = 0

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

-- Lo usa el cliente para escuchar
function ElementalFX.GetRemote(): RemoteEvent
	if RunService:IsServer() then
		return getRemote()
	end
	return ReplicatedStorage:WaitForChild("JutsuSystem"):WaitForChild("Remotes"):WaitForChild(REMOTE_NAME) :: RemoteEvent
end

function ElementalFX.NewId(): number
	sequence += 1
	return sequence
end

-- kind: nombre del jutsu ("WaterBullet"). action: qué pasó ("Burst", "Start"...).
function ElementalFX.Fire(kind: string, action: string, data: { [string]: any }?)
	local payload = data or {}
	payload.T = Workspace:GetServerTimeNow()
	getRemote():FireAllClients(kind, action, payload)
end

-- Proyectiles en línea recta: el cliente simula la posición con el tiempo del servidor
function ElementalFX.Projectile(
	kind: string,
	caster: Model?,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	maxDistance: number,
	radius: number,
	extra: { [string]: any }?
): number
	local id = ElementalFX.NewId()
	local data: { [string]: any } = extra or {}
	data.Id = id
	data.Caster = caster
	data.Origin = origin
	data.Direction = direction.Unit
	data.Speed = speed
	data.MaxDistance = maxDistance
	data.Radius = radius
	ElementalFX.Fire(kind, "Projectile", data)
	return id
end

function ElementalFX.ProjectileHit(id: number, position: Vector3, normal: Vector3?)
	getRemote():FireAllClients("_", "ProjectileHit", {
		Id = id,
		Position = position,
		Normal = normal,
		T = Workspace:GetServerTimeNow(),
	})
end

function ElementalFX.ProjectileEnd(id: number, position: Vector3?, normal: Vector3?)
	getRemote():FireAllClients("_", "ProjectileEnd", {
		Id = id,
		Position = position,
		Normal = normal,
		T = Workspace:GetServerTimeNow(),
	})
end

-- El RemoteEvent se crea al cargar (los jutsus requieren este módulo al iniciar el servidor),
-- así los clientes ya están escuchando antes del primer jutsu.
if RunService:IsServer() then
	task.spawn(getRemote)
end

return ElementalFX
