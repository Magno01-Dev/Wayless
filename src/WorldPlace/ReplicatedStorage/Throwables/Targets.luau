--[[
	Throwables.Targets · ModuleScript en ReplicatedStorage.Throwables
	Objetivos (jugadores y dummies con tag), ayuda de apuntado, colisión con el cuerpo
	y rayos contra el mundo. Compartido por cliente y servidor.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))

local Targets = {}

-- Personajes atacables vivos, sin el excluido (el propio lanzador)
function Targets.list(exclude)
	local result, seen = {}, {}
	local function consider(model)
		if not model or seen[model] or model == exclude then
			return
		end
		seen[model] = true
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and model:GetAttribute("IsDowned") ~= true then
			table.insert(result, { Character = model, Humanoid = humanoid, Root = root })
		end
	end
	for _, player in Players:GetPlayers() do
		consider(player.Character)
	end
	for _, tagged in CollectionService:GetTagged(Config.TargetTag) do
		consider(if tagged:IsA("Model") then tagged else tagged:FindFirstAncestorOfClass("Model"))
	end
	return result
end

function Targets.characterFromPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Eje vertical del cuerpo (para el impacto)
function Targets.bodySegment(rootPosition)
	return rootPosition + Vector3.yAxis * Config.BodyBottom, rootPosition + Vector3.yAxis * Config.BodyTop
end

-- Distancia mínima entre dos segmentos
function Targets.segmentDistance(p1, q1, p2, q2)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, t = 0, 0
	if a <= 1e-6 and e <= 1e-6 then
		return (p1 - p2).Magnitude, p1
	end
	if a <= 1e-6 then
		t = math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= 1e-6 then
			s = math.clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denominator = a * e - b * b
			s = if math.abs(denominator) > 1e-6 then math.clamp((b * f - c * e) / denominator, 0, 1) else 0
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	local pointA = p1 + d1 * s
	local pointB = p2 + d2 * t
	return (pointA - pointB).Magnitude, pointA
end

-- Rayo/esfera contra el mundo sólido: ignora personajes, partes sin colisión y carpetas de efectos
local ignoredFolders = {}
local function getIgnoredFolders()
	table.clear(ignoredFolders)
	for _, name in Config.IgnoreFolders do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignoredFolders, folder)
		end
	end
	return ignoredFolders
end

-- Barreras de llamas negras (Jutsus > BlackWall): están en su propio grupo de colisión para que
-- ni el movimiento ni los rayos normales las vean; solo las miran a propósito los proyectiles y las
-- líneas de visión (castWorld ya las incluye)
local BARRIER_GROUP = "FlameBarrier"

function Targets.castBarrier(origin, direction, radius)
	local folder = Workspace:FindFirstChild("MangekyoBarriers")
	if not folder or #folder:GetChildren() == 0 or direction.Magnitude < 1e-4 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ok, hit = pcall(function()
		params.CollisionGroup = BARRIER_GROUP
		return if radius then Workspace:Spherecast(origin, radius, direction, params) else Workspace:Raycast(origin, direction, params)
	end)
	return if ok then hit else nil
end

function Targets.isBarrier(instance)
	return typeof(instance) == "Instance" and instance:GetAttribute("FlameBarrier") == true
end

-- Servidor: un proyectil entró en las llamas negras de una barrera y se consume (lo dibuja
-- MangekyoClient, ClanFX "BlackWallConsume")
function Targets.consumeAtBarrier(position, direction)
	if not game:GetService("RunService"):IsServer() then
		return
	end
	local jutsuSystem = game:GetService("ReplicatedStorage"):FindFirstChild("JutsuSystem")
	local remotes = jutsuSystem and jutsuSystem:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("ClanFX")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients("BlackWallConsume", { Position = position, Direction = direction })
	end
end

-- Servidor: si el resultado es una barrera, el proyectil se consume y devuelve true: el jutsu
-- termina ahí sin impacto, explosión ni daño
function Targets.consumedBy(result, position, direction)
	if not result or not Targets.isBarrier(result.Instance) then
		return false
	end
	Targets.consumeAtBarrier(position or result.Position, direction)
	return true
end

-- El más cercano entre un resultado normal y una barrera en el mismo tramo
function Targets.withBarrier(result, origin, direction, radius)
	local barrier = Targets.castBarrier(origin, direction, radius)
	if barrier and (not result or barrier.Distance < result.Distance) then
		return barrier
	end
	return result
end

function Targets.castWorld(origin, direction, extraIgnore, radius)
	local barrier = Targets.castBarrier(origin, direction, radius)
	local function nearest(hit)
		if barrier and (not hit or barrier.Distance < hit.Distance) then
			return barrier
		end
		return hit
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = table.clone(getIgnoredFolders())
	if extraIgnore then
		for _, instance in extraIgnore do
			table.insert(ignore, instance)
		end
	end
	params.FilterDescendantsInstances = ignore
	for _ = 1, 6 do
		local hit = if radius
			then Workspace:Spherecast(origin, radius, direction, params)
			else Workspace:Raycast(origin, direction, params)
		if not hit then
			return nearest(nil)
		end
		local instance = hit.Instance
		if instance.CanCollide and not Targets.characterFromPart(instance) then
			return nearest(hit)
		end
		params:AddToFilter(if Targets.characterFromPart(instance) then Targets.characterFromPart(instance) else instance)
	end
	return nearest(nil)
end

--[[
	Ayuda de apuntado (solo al soltar).
	Busca el objetivo más cercano al rayo de apuntado dentro de un radio que crece con la
	distancia, y apunta a donde VA a estar (predicción parcial). Sin objetivo: el punto exacto
	del retículo. Devuelve targetPoint, targetCharacter.
]]
--[[
	Ocultación (solo cliente). Effects pone aquí sus funciones:
		Targets.isConcealed(position) → true si el punto está dentro de un humo
		Targets.isBlinded() → true si el jugador local está cegado por una bomba de luz
	Sin asistencia de apuntado si quien lanza está cegado o dentro del humo, ni hacia
	objetivos dentro del humo.
]]
Targets.isConcealed = nil
Targets.isBlinded = nil

local function assistSuppressed(origin)
	if Targets.isBlinded and Targets.isBlinded() then
		return true
	end
	return Targets.isConcealed ~= nil and Targets.isConcealed(origin)
end

function Targets.solveAim(definition, levelDef, origin, rayOrigin, rayDirection, ownCharacter)
	local assist = levelDef.Assist or definition.Assist
	local speed = levelDef.Speed
	local best, bestScore = nil, math.huge
	local candidates = if assistSuppressed(origin) then {} else Targets.list(ownCharacter)

	for _, candidate in candidates do
		local center = candidate.Root.Position + Vector3.yAxis * Config.AimHeightOffset
		if Targets.isConcealed and Targets.isConcealed(center) then
			continue
		end
		-- Genjutsu Kori Shinchū o invisible tras la sustitución: no se le puede fijar
		if candidate.Character:GetAttribute("GenjutsuHidden") == true
			or candidate.Character:GetAttribute("SubstitutionHidden") == true then
			continue
		end
		local toCenter = center - rayOrigin
		local along = toCenter:Dot(rayDirection)
		if along <= 0 then
			continue
		end
		local distance = (center - origin).Magnitude
		if distance > assist.Range then
			continue
		end
		local perpendicular = (toCenter - rayDirection * along).Magnitude
		local radius = math.clamp(distance * math.tan(math.rad(assist.Angle)), assist.MinRadius, assist.MaxRadius)
		if perpendicular > radius then
			continue
		end
		local blocked = Targets.castWorld(origin, center - origin, { ownCharacter })
		if blocked then
			continue
		end
		local score = perpendicular / radius + (distance / assist.Range) * 0.15
		if score < bestScore then
			best, bestScore = candidate, score
		end
	end

	if best then
		local center = best.Root.Position + Vector3.yAxis * Config.AimHeightOffset
		local velocity = best.Root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude > Config.MaxPredictionSpeed then
			flat = flat.Unit * Config.MaxPredictionSpeed
		end
		local travelTime = (center - origin).Magnitude / speed
		local lead = (flat + Vector3.yAxis * (velocity.Y * Config.VerticalLeadFactor)) * travelTime * assist.Lead
		if lead.Magnitude > Config.MaxLeadDistance then
			lead = lead.Unit * Config.MaxLeadDistance
		end
		return center + lead, best.Character
	end

	local range = definition.Range + 60
	local hit = Targets.castWorld(rayOrigin, rayDirection * range, { ownCharacter })
	return if hit then hit.Position else rayOrigin + rayDirection * range, nil
end

-- Máximo desvío permitido entre el punto de destino y la línea de apuntado (validación del servidor)
function Targets.maxAimOffset(definition, levelDef)
	local assist = levelDef.Assist or definition.Assist
	return assist.MaxRadius + Config.MaxLeadDistance + Config.TargetTolerance
end

return Targets
