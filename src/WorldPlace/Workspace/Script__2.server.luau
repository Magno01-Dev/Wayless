--[[
	TreeJumpZones · plugin de Studio (paso 1 del rework de Tree Jump)

	Instalación:
		1. Crea un Script en ServerStorage y pega este código.
		2. Clic derecho sobre el Script → "Save as Local Plugin...".
		3. En la pestaña Plugins aparece la barra "Tree Jump".
		   (El Script de ServerStorage se puede borrar; no corre en el juego.)

	Botones:
		Generar zonas → en los árboles seleccionados, o en todos si no hay selección
		Validar       → revisa árboles y zonas y reporta en Output
		Ver zonas     → muestra/oculta las zonas (solo en el editor, no se guarda)
		Arreglar      → el follaje sin colisión deja de bloquear raycasts,
		                y los árboles pasan a ModelStreamingMode Atomic si hay streaming

	Contrato de árbol:
		- Un árbol es un Model que contiene ramas.
		- Rama: BasePart cuyo nombre empieza con "Branch", o con tag "TreeBranch",
		  o con atributo IsBranch = true.
		- Las zonas son Parts con tag "JumpZone" dentro de la carpeta "JumpZones" del árbol.
		  Eje X = largo de la rama, cara superior = donde se pisa.
		- Atributos de zona: Enabled, AllowStop, Priority, Surface, Generated, Locked.
		- Surface se hereda del atributo "Surface" del árbol (por bioma), o "Wood".
		- Una zona con Locked = true no se borra al regenerar, y su rama no se vuelve a generar.

	Cómo se genera una zona:
		1. Raycasts hacia abajo en grilla sobre la rama → puntos del lomo.
		2. Eje principal de la rama en planta, cortado en estaciones cada StationStep.
		3. Una estación es pisable si el ancho ≥ MinWidth y el cuerpo del personaje
		   cabe ahí sin chocar con el tronco u otras ramas.
		4. Tramos seguidos, sin pendientes > MaxSlope y de largo ≥ MinRunLength,
		   se simplifican (Douglas-Peucker) en uno o más segmentos rectos → zonas.
		Todo se mide en studs sobre el árbol ya escalado, así que sirve para cualquier tamaño.
]]

if not plugin then
	return
end

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local CONFIG = {
	-- Dónde buscar árboles cuando no hay selección
	TreeRoots = { "Arboles" },
	TreeTag = "Tree",

	-- Identificación
	BranchTag = "TreeBranch",
	BranchNamePattern = "^Branch",
	ZoneTag = "JumpZone",
	ZoneFolderName = "JumpZones",

	-- Muestreo
	GridStep = 0.2, -- separación de los raycasts (studs)
	MaxRaysPerBranch = 40000, -- si la rama es enorme, la grilla se agranda
	StationStep = 0.5, -- largo de cada estación a lo largo de la rama

	-- Reglas de pisable (studs y grados)
	MinWidth = 0.8,
	MinRunLength = 2.5,
	MinSegmentLength = 1.5,
	MaxSlope = 25,
	MaxDeviation = 0.3, -- cuánto puede curvarse la rama antes de partir la zona
	EndTrim = 0.4, -- margen en las puntas para que los pies no queden en el aire

	-- Cuerpo del personaje (esferas sobre el lomo)
	BodyProbeRadius = 1,
	BodyProbeHeights = { 1.5, 3.5 },
	HeadroomCheck = 5,

	-- Zona
	ZoneThickness = 0.2,
	ZoneCanCollide = false, -- true = la zona también sirve de piso invisible
	DefaultSurface = "Wood",
}

local LOG = "[TreeJump] "

-- Identificación -----------------------------------------------------------

local function isZone(instance)
	return instance:IsA("BasePart") and instance:HasTag(CONFIG.ZoneTag)
end

local function isBranch(instance)
	if not instance:IsA("BasePart") or isZone(instance) then
		return false
	end
	return instance:HasTag(CONFIG.BranchTag)
		or instance:GetAttribute("IsBranch") == true
		or string.match(instance.Name, CONFIG.BranchNamePattern) ~= nil
end

local function getTree(part)
	return part:FindFirstAncestorOfClass("Model")
end

local function getBranches(tree)
	local branches = {}
	for _, descendant in tree:GetDescendants() do
		if isBranch(descendant) and getTree(descendant) == tree then
			table.insert(branches, descendant)
		end
	end
	return branches
end

local function getZones(tree)
	local zones = {}
	for _, descendant in tree:GetDescendants() do
		if isZone(descendant) then
			table.insert(zones, descendant)
		end
	end
	return zones
end

-- Partes con colisión del árbol (tronco, ramas…). El follaje sin colisión no cuenta.
local function getSolids(tree)
	local solids = {}
	for _, descendant in tree:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CanCollide and not isZone(descendant) then
			table.insert(solids, descendant)
		end
	end
	return solids
end

-- Árboles de la selección, o de TreeRoots y el tag "Tree" si no hay selección
local function collectTrees()
	local roots = {}
	for _, item in Selection:Get() do
		if item:IsA("BasePart") then
			table.insert(roots, getTree(item) or item)
		else
			table.insert(roots, item)
		end
	end

	local usingSelection = #roots > 0
	if not usingSelection then
		for _, name in CONFIG.TreeRoots do
			local root = Workspace:FindFirstChild(name)
			if root then
				table.insert(roots, root)
			end
		end
		for _, tagged in CollectionService:GetTagged(CONFIG.TreeTag) do
			table.insert(roots, tagged)
		end
	end

	local trees, seen = {}, {}
	local function consider(instance)
		if isBranch(instance) then
			local tree = getTree(instance)
			if tree and not seen[tree] then
				seen[tree] = true
				table.insert(trees, tree)
			end
		end
	end
	for _, root in roots do
		consider(root)
		for _, descendant in root:GetDescendants() do
			consider(descendant)
		end
	end
	return trees, usingSelection
end

local function withUndo(name, callback)
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local ok, err = pcall(callback)
	if recording then
		local operation = if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		ChangeHistoryService:FinishRecording(recording, operation)
	end
	if not ok then
		warn(LOG .. "Error: " .. tostring(err))
	end
end

-- Geometría -----------------------------------------------------------------

local function worldBounds(part)
	local cf, half = part.CFrame, part.Size / 2
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = cf:PointToWorldSpace(half * Vector3.new(x, y, z))
				minX, minY, minZ = math.min(minX, corner.X), math.min(minY, corner.Y), math.min(minZ, corner.Z)
				maxX, maxY, maxZ = math.max(maxX, corner.X), math.max(maxY, corner.Y), math.max(maxZ, corner.Z)
			end
		end
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

-- Puntos del lomo de la rama, vistos desde arriba
local function sampleTop(branch)
	local minV, maxV = worldBounds(branch)
	local area = (maxV.X - minV.X) * (maxV.Z - minV.Z)
	local step = math.max(CONFIG.GridStep, math.sqrt(area / CONFIG.MaxRaysPerBranch))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { branch }

	local originY = maxV.Y + 1
	local ray = Vector3.new(0, -(maxV.Y - minV.Y + 2), 0)
	local hits = {}
	for x = minV.X, maxV.X, step do
		for z = minV.Z, maxV.Z, step do
			local result = Workspace:Raycast(Vector3.new(x, originY, z), ray, params)
			if result and result.Normal.Y > 0.05 then
				table.insert(hits, result.Position)
			end
		end
	end
	return hits, step
end

-- Eje principal en planta (PCA 2D sobre X/Z)
local function horizontalAxis(points)
	local cx, cz = 0, 0
	for _, point in points do
		cx += point.X
		cz += point.Z
	end
	cx /= #points
	cz /= #points

	local sxx, sxz, szz = 0, 0, 0
	for _, point in points do
		local dx, dz = point.X - cx, point.Z - cz
		sxx += dx * dx
		sxz += dx * dz
		szz += dz * dz
	end
	local angle = 0.5 * math.atan2(2 * sxz, sxx - szz)
	return Vector3.new(math.cos(angle), 0, math.sin(angle)), Vector3.new(cx, 0, cz)
end

local function distanceToSegment(point, a, b)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSq, 0, 1)
	return (point - (a + ab * t)).Magnitude
end

-- Douglas-Peucker: índices de los puntos que se conservan
local function simplify(points, tolerance)
	local keep = { [1] = true, [#points] = true }
	local function recurse(first, last)
		local maxDistance, index = 0, nil
		for i = first + 1, last - 1 do
			local distance = distanceToSegment(points[i], points[first], points[last])
			if distance > maxDistance then
				maxDistance, index = distance, i
			end
		end
		if index and maxDistance > tolerance then
			keep[index] = true
			recurse(first, index)
			recurse(index, last)
		end
	end
	recurse(1, #points)

	local indices = {}
	for i = 1, #points do
		if keep[i] then
			table.insert(indices, i)
		end
	end
	return indices
end

-- Promedio con vecinos para quitar el ruido de la grilla
local function smoothRidge(run)
	local points = table.create(#run)
	for i = 1, #run do
		local sum, count = Vector3.zero, 0
		for j = math.max(1, i - 1), math.min(#run, i + 1) do
			sum += run[j].Ridge
			count += 1
		end
		points[i] = sum / count
	end
	return points
end

local function polylineLength(points)
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end
	return length
end

-- Análisis de una rama -------------------------------------------------------

local function isBodyClear(point, probe, overlapParams)
	for _, height in CONFIG.BodyProbeHeights do
		probe.CFrame = CFrame.new(point + Vector3.yAxis * height)
		if #Workspace:GetPartsInPart(probe, overlapParams) > 0 then
			return false
		end
	end
	return true
end

-- Devuelve una lista de segmentos { Start, End, Width } o una razón si no hay ninguno
local function analyzeBranch(branch, obstacles, probe)
	local hits, step = sampleTop(branch)
	if #hits < 3 then
		return {}, "no se detectó superficie (revisa CanQuery o CollisionFidelity)"
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = obstacles
	local checkBody = #obstacles > 0

	-- Estaciones a lo largo del eje
	local axis, center = horizontalAxis(hits)
	local lateral = Vector3.new(-axis.Z, 0, axis.X)
	local tValues = table.create(#hits)
	local tMin, tMax = math.huge, -math.huge
	for i, point in hits do
		local t = (point.X - center.X) * axis.X + (point.Z - center.Z) * axis.Z
		tValues[i] = t
		tMin = math.min(tMin, t)
		tMax = math.max(tMax, t)
	end

	local count = math.floor((tMax - tMin) / CONFIG.StationStep) + 1
	local stations = {}
	for i, point in hits do
		local k = math.floor((tValues[i] - tMin) / CONFIG.StationStep) + 1
		local s = (point.X - center.X) * lateral.X + (point.Z - center.Z) * lateral.Z
		local station = stations[k]
		if not station then
			stations[k] = { MinS = s, MaxS = s, Ridge = point }
		else
			station.MinS = math.min(station.MinS, s)
			station.MaxS = math.max(station.MaxS, s)
			if point.Y > station.Ridge.Y then
				station.Ridge = point
			end
		end
	end

	local maxWidth, anyValid = 0, false
	for k = 1, count do
		local station = stations[k]
		if station then
			station.Width = station.MaxS - station.MinS + step
			maxWidth = math.max(maxWidth, station.Width)
			station.Valid = station.Width >= CONFIG.MinWidth
				and (not checkBody or isBodyClear(station.Ridge, probe, overlapParams))
			anyValid = anyValid or station.Valid
		end
	end

	if maxWidth < CONFIG.MinWidth then
		return {}, string.format("muy delgada (ancho máx %.2f, mínimo %.2f studs)", maxWidth, CONFIG.MinWidth)
	end
	if not anyValid then
		return {}, "el cuerpo no cabe: choca con el tronco u otras ramas"
	end

	-- Tramos seguidos sin pendientes excesivas
	local runs, current = {}, nil
	local function closeRun()
		if current and #current >= 2 then
			table.insert(runs, current)
		end
		current = nil
	end
	for k = 1, count do
		local station = stations[k]
		if station and station.Valid then
			if current then
				local delta = station.Ridge - current[#current].Ridge
				local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
				local slope = math.deg(math.atan2(math.abs(delta.Y), math.max(horizontal, 1e-3)))
				if slope > CONFIG.MaxSlope then
					closeRun()
				end
			end
			current = current or {}
			table.insert(current, station)
		else
			closeRun()
		end
	end
	closeRun()

	-- Segmentos rectos por tramo
	local segments, longestRun = {}, 0
	for _, run in runs do
		local points = smoothRidge(run)
		local length = polylineLength(points)
		longestRun = math.max(longestRun, length)
		if length >= CONFIG.MinRunLength then
			local kept = simplify(points, CONFIG.MaxDeviation)
			for i = 1, #kept - 1 do
				local a, b = kept[i], kept[i + 1]
				local startPos, endPos = points[a], points[b]
				local delta = endPos - startPos
				local trimStart = if i == 1 then CONFIG.EndTrim else 0
				local trimEnd = if i == #kept - 1 then CONFIG.EndTrim else 0
				local trimmedLength = delta.Magnitude - trimStart - trimEnd
				if trimmedLength >= CONFIG.MinSegmentLength then
					local unit = delta.Unit
					local width = math.huge
					for j = a, b do
						width = math.min(width, run[j].Width)
					end
					table.insert(segments, {
						Start = startPos + unit * trimStart,
						End = endPos - unit * trimEnd,
						Width = width,
					})
				end
			end
		end
	end

	if #segments == 0 then
		return {}, string.format("tramo pisable muy corto o inclinado (máx %.1f studs)", longestRun)
	end
	return segments, nil
end

local function createZone(folder, tree, branch, segment)
	local direction = segment.End - segment.Start
	local vX = direction.Unit
	local vZ = vX:Cross(Vector3.yAxis)
	if vZ.Magnitude < 1e-3 then
		return nil
	end
	vZ = vZ.Unit
	local vY = vZ:Cross(vX).Unit
	local center = (segment.Start + segment.End) / 2 - vY * (CONFIG.ZoneThickness / 2)

	local zone = Instance.new("Part")
	zone.Name = "JumpZone"
	zone.Anchored = true
	zone.CastShadow = false
	zone.Transparency = 1
	zone.Material = Enum.Material.SmoothPlastic
	zone.Size = Vector3.new(direction.Magnitude, CONFIG.ZoneThickness, math.max(segment.Width, 0.2))
	zone.CFrame = CFrame.fromMatrix(center, vX, vY, vZ)
	zone.CanTouch = false
	if CONFIG.ZoneCanCollide then
		zone.CanCollide = true
	else
		zone.CanCollide = false
		zone.CanQuery = false
	end

	zone:SetAttribute("Enabled", true)
	zone:SetAttribute("AllowStop", true)
	zone:SetAttribute("Priority", 0)
	zone:SetAttribute("Surface", tree:GetAttribute("Surface") or CONFIG.DefaultSurface)
	zone:SetAttribute("Generated", true)
	zone:SetAttribute("Locked", false)

	local source = Instance.new("ObjectValue")
	source.Name = "SourceBranch"
	source.Value = branch
	source.Parent = zone

	zone:AddTag(CONFIG.ZoneTag)
	zone.Parent = folder
	return zone
end

local function describeBranch(tree, branch, index)
	return string.format("%s/%s #%d", tree.Name, branch.Name, index)
end

local function generateTree(tree, probe)
	-- Borra zonas generadas; recuerda las ramas con zonas bloqueadas
	local lockedBranches = {}
	for _, zone in getZones(tree) do
		if zone:GetAttribute("Locked") == true then
			local source = zone:FindFirstChild("SourceBranch")
			if source and source.Value then
				lockedBranches[source.Value] = true
			end
		elseif zone:GetAttribute("Generated") == true then
			zone:Destroy()
		end
	end

	local folder = tree:FindFirstChild(CONFIG.ZoneFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CONFIG.ZoneFolderName
		folder.Parent = tree
	end

	local solids = getSolids(tree)
	local branches = getBranches(tree)
	local created, problems = 0, {}

	for index, branch in branches do
		if lockedBranches[branch] then
			continue
		end

		local obstacles = {}
		for _, solid in solids do
			if solid ~= branch then
				table.insert(obstacles, solid)
			end
		end

		local restoreQuery = not branch.CanQuery
		if restoreQuery then
			branch.CanQuery = true
		end
		local ok, segments, reason = pcall(analyzeBranch, branch, obstacles, probe)
		if restoreQuery then
			branch.CanQuery = false
		end

		local label = describeBranch(tree, branch, index)
		if not ok then
			table.insert(problems, label .. ": error " .. tostring(segments))
		elseif #segments == 0 then
			table.insert(problems, label .. ": " .. reason)
		else
			for _, segment in segments do
				if createZone(folder, tree, branch, segment) then
					created += 1
				end
			end
		end
	end

	return created, #branches, problems
end

-- Acciones -----------------------------------------------------------------

local visualsFolder = nil

local function zoneColor(zone)
	if zone:GetAttribute("Enabled") == false then
		return Color3.fromRGB(235, 70, 70)
	end
	if zone:GetAttribute("AllowStop") == false then
		return Color3.fromRGB(245, 200, 60)
	end
	if zone:GetAttribute("Generated") ~= true or zone:GetAttribute("Locked") == true then
		return Color3.fromRGB(80, 190, 255)
	end
	return Color3.fromRGB(80, 230, 120)
end

local function clearVisuals()
	if visualsFolder then
		visualsFolder:Destroy()
		visualsFolder = nil
	end
end

local function showVisuals()
	clearVisuals()
	visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "TreeJumpZoneVisuals"
	visualsFolder.Parent = CoreGui

	local count = 0
	for _, zone in CollectionService:GetTagged(CONFIG.ZoneTag) do
		if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace) then
			local box = Instance.new("BoxHandleAdornment")
			box.Adornee = zone
			box.Size = Vector3.new(zone.Size.X, math.max(zone.Size.Y, 0.15), zone.Size.Z)
			box.Color3 = zoneColor(zone)
			box.Transparency = 0.35
			box.AlwaysOnTop = false
			box.ZIndex = 1
			box.Parent = visualsFolder
			count += 1
		end
	end
	print(LOG .. count .. " zona(s) visibles. Verde = normal, azul = manual/bloqueada, amarillo = solo de paso, rojo = desactivada.")
end

local function generate()
	if RunService:IsRunning() then
		warn(LOG .. "Detén la simulación antes de generar zonas.")
		return
	end
	local trees, usingSelection = collectTrees()
	if #trees == 0 then
		warn(LOG .. "No encontré árboles. Selecciona árboles o revisa CONFIG.TreeRoots.")
		return
	end
	print(LOG .. string.format("Generando zonas en %d árbol(es)%s...", #trees, if usingSelection then " seleccionados" else ""))

	withUndo("Tree Jump: generar zonas", function()
		local probe = Instance.new("Part")
		probe.Name = "TreeJumpProbe"
		probe.Shape = Enum.PartType.Ball
		probe.Size = Vector3.one * CONFIG.BodyProbeRadius * 2
		probe.Anchored = true
		probe.CanCollide = false
		probe.CanTouch = false
		probe.Transparency = 1
		probe.Archivable = false
		probe.Parent = Workspace

		local ok, err = pcall(function()
			local totalZones, totalBranches, totalProblems = 0, 0, 0
			for index, tree in trees do
				local created, branchCount, problems = generateTree(tree, probe)
				totalZones += created
				totalBranches += branchCount
				totalProblems += #problems
				for _, problem in problems do
					warn(LOG .. problem)
				end
				if index % 10 == 0 then
					task.wait()
				end
			end
			print(LOG .. string.format(
				"Listo: %d zona(s) en %d rama(s) de %d árbol(es). Ramas sin zona: %d.",
				totalZones,
				totalBranches,
				#trees,
				totalProblems
				))
		end)
		probe:Destroy()
		if not ok then
			error(err, 0)
		end
	end)

	if visualsFolder then
		showVisuals()
	end
end

local function validate()
	local trees = collectTrees()
	if #trees == 0 then
		warn(LOG .. "No encontré árboles para validar.")
		return
	end

	local issues = 0
	local function report(tree, message)
		issues += 1
		warn(LOG .. tree:GetFullName() .. ": " .. message)
	end

	for _, tree in trees do
		local branches = getBranches(tree)
		local zones = getZones(tree)
		local solids = getSolids(tree)

		if #zones == 0 then
			report(tree, "no tiene zonas (usa Generar zonas)")
		end

		for index, branch in branches do
			local label = branch.Name .. " #" .. index
			if branch:IsA("MeshPart") then
				local fidelity = branch.CollisionFidelity
				if fidelity == Enum.CollisionFidelity.Box or fidelity == Enum.CollisionFidelity.Hull then
					report(tree, label .. ": CollisionFidelity " .. fidelity.Name .. " es imprecisa; usa PreciseConvexDecomposition")
				end
			end
			if not branch.CanCollide and not CONFIG.ZoneCanCollide then
				report(tree, label .. ": no tiene colisión y las zonas tampoco; no hay dónde pararse")
			end
		end

		for _, zone in zones do
			local source = zone:FindFirstChild("SourceBranch")
			local branch = source and source.Value
			local top = zone.CFrame:PointToWorldSpace(Vector3.new(0, zone.Size.Y / 2, 0))

			if typeof(zone:GetAttribute("Enabled")) ~= "boolean" then
				report(tree, "zona sin atributo Enabled (booleano)")
			end
			if zone.Size.Z < CONFIG.MinWidth or zone.Size.X < CONFIG.MinSegmentLength then
				report(tree, string.format(
					"zona muy chica (%.1f × %.2f studs); ¿árbol escalado hacia abajo?",
					zone.Size.X,
					zone.Size.Z
					))
			end

			if zone:GetAttribute("Generated") == true and not (branch and branch:IsDescendantOf(tree)) then
				report(tree, "zona sin rama de origen (¿se borró la rama?); regenera")
			elseif branch and branch.CanQuery then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { branch }
				local hit = Workspace:Raycast(top + Vector3.yAxis, Vector3.new(0, -3, 0), params)
				if not hit or math.abs(hit.Position.Y - top.Y) > 0.5 then
					report(tree, "zona desalineada con su rama (¿se movió la rama?); regenera")
				end
			end

			local obstacles = {}
			for _, solid in solids do
				if solid ~= branch then
					table.insert(obstacles, solid)
				end
			end
			if #obstacles > 0 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = obstacles
				local hit = Workspace:Raycast(top + Vector3.yAxis * 0.2, Vector3.yAxis * CONFIG.HeadroomCheck, params)
				if hit then
					report(tree, string.format("zona con poco espacio arriba (%.1f studs hasta %s)", hit.Distance, hit.Instance.Name))
				end
			end
		end

		local blocking = 0
		for _, descendant in tree:GetDescendants() do
			if descendant:IsA("BasePart") and not descendant.CanCollide and not isZone(descendant)
				and not isBranch(descendant) and descendant.CanQuery then
				blocking += 1
			end
		end
		if blocking > 0 then
			report(tree, blocking .. " parte(s) sin colisión (follaje) bloquean raycasts; usa Arreglar")
		end

		if Workspace.StreamingEnabled and tree.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
			report(tree, "con StreamingEnabled conviene ModelStreamingMode = Atomic; usa Arreglar")
		end
	end

	if issues == 0 then
		print(LOG .. string.format("Validación OK: %d árbol(es) sin problemas.", #trees))
	else
		print(LOG .. string.format("Validación: %d aviso(s) en %d árbol(es). Revisa los mensajes de arriba.", issues, #trees))
	end
end

local function fix()
	local trees = collectTrees()
	if #trees == 0 then
		warn(LOG .. "No encontré árboles para arreglar.")
		return
	end
	withUndo("Tree Jump: arreglar", function()
		local foliage, atomic = 0, 0
		for _, tree in trees do
			for _, descendant in tree:GetDescendants() do
				if descendant:IsA("BasePart") and not descendant.CanCollide and not isZone(descendant)
					and not isBranch(descendant) and (descendant.CanQuery or descendant.CanTouch) then
					descendant.CanQuery = false
					descendant.CanTouch = false
					foliage += 1
				end
			end
			if Workspace.StreamingEnabled and tree.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
				tree.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				atomic += 1
			end
		end
		print(LOG .. string.format("Arreglado: %d parte(s) de follaje, %d árbol(es) a Atomic.", foliage, atomic))
	end)
end

-- Barra de herramientas ------------------------------------------------------

local toolbar = plugin:CreateToolbar("Tree Jump")

local generateButton = toolbar:CreateButton(
	"TreeJumpGenerate",
	"Genera zonas en los árboles seleccionados (o en todos si no hay selección)",
	"",
	"Generar zonas"
)
local validateButton = toolbar:CreateButton(
	"TreeJumpValidate",
	"Revisa árboles y zonas y reporta problemas en Output",
	"",
	"Validar"
)
local visualsButton = toolbar:CreateButton(
	"TreeJumpVisuals",
	"Muestra u oculta las zonas (solo en el editor)",
	"",
	"Ver zonas"
)
local fixButton = toolbar:CreateButton(
	"TreeJumpFix",
	"Follaje sin colisión deja de bloquear raycasts; árboles a streaming Atomic",
	"",
	"Arreglar"
)

for _, button in { generateButton, validateButton, visualsButton, fixButton } do
	button.ClickableWhenViewportHidden = true
end

generateButton.Click:Connect(generate)
validateButton.Click:Connect(validate)
fixButton.Click:Connect(fix)
visualsButton.Click:Connect(function()
	if visualsFolder then
		clearVisuals()
	else
		showVisuals()
	end
	visualsButton:SetActive(visualsFolder ~= nil)
end)

plugin.Unloading:Connect(clearVisuals)
