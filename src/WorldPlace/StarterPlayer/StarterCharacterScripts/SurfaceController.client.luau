-- SurfaceController v3.4.3 - Chakra Suppression Integration + Air Dash Water Landing Handoff
-- Base: v2.6 DetachFacingFix
-- Changes only:
-- - reliable landing capture when FloorMaterial briefly becomes Water
-- - prevents attaching to solid walls while actually underwater/swimming
-- - clean WaterJumping handoff so Water Jump -> Air Dash is not interrupted
-- - slightly more forgiving near-surface underwater capture
-- - remembers a genuine approach to water FROM ABOVE
-- - recovers fast falls / shore jumps that tunnel through the water surface
-- - NEW: PostSimulation foot-sweep catches the exact frame the feet cross water
-- - NEW: near-surface swimming reacquires Water Walk more reliably
-- - NEW: Air Dash powered impulse remains blocked from Water Walk capture
-- - NEW: descending AirDashCarry can hand off cleanly into Water Walk
-- - NEW: Water/Surface locomotion mirrors SprintController directional Run (Forward/Left/Right)
-- - NEW: Surface Run now follows authoritative IsSprinting instead of raw Shift input
-- - NEW: Combat backward movement stays Walk visually, matching ground behavior
-- All existing wall/ceiling/camera/combat/surface behavior is preserved.

--
-- Chakra en los pies:
--   C + C rapido = ON
--   C + C rapido = OFF
--
-- Mientras ChakraFeetActive esta ON:
-- - El movimiento normal en suelo sigue siendo el de Roblox.
-- - Si avanzas con W contra una superficie, esa superficie puede convertirse
--   en el nuevo "suelo".
-- - El personaje puede recorrer paredes, techos, troncos, ramas y superficies
--   inclinadas.
-- - Si alcanza fisicamente la superficie del agua, puede caminar sobre ella.
--   Activar Chakra Feet bajo el agua NO lo sube automaticamente.
-- - Las mismas animaciones Idle / Walk / Run se reutilizan.
-- - La camara se transforma junto con el nuevo suelo.
--
-- Este controlador NO reemplaza TreeJumpController.
-- Se aparta automaticamente mientras Tree Jump toma control.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local chakraRemotes =
	ReplicatedStorage:
	WaitForChild("ChakraRemotes")

local chakraFeetStateEvent =
	chakraRemotes:
	WaitForChild("ChakraFeetState") :: RemoteEvent

local ChakraConfig =
	require(
		ReplicatedStorage:
		WaitForChild("ChakraConfig")
	)

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local animate = character:WaitForChild("Animate")
local rootPart = character:WaitForChild("HumanoidRootPart")


-- =========================
-- INPUT SETTINGS
-- =========================

local CHAKRA_FEET_KEY = Enum.KeyCode.C
local DOUBLE_C_WINDOW = 0.30

-- C is shared with Chakra Charge.
-- Only a SHORT press counts toward the Chakra Feet double-tap.
local CHAKRA_FEET_TAP_MAX_DURATION =
	ChakraConfig.Charge.ChakraFeetTapMaxDuration
	or 0.18

local cPressStartedAt =
	-math.huge

local lastReportedChakraFeetMode =
	"Off"

local function reportChakraFeetMode(
	mode: string
)
	if lastReportedChakraFeetMode ==
		mode then

		return
	end

	lastReportedChakraFeetMode =
		mode

	chakraFeetStateEvent:
		FireServer(mode)
end


-- =========================
-- SURFACE SETTINGS
-- =========================

-- Distancia para detectar una pared delante del personaje.
local ATTACH_PROBE_DISTANCE = 5.0

-- Radio de los Spherecast. Da mas estabilidad que un solo rayo fino.
local SURFACE_CAST_RADIUS = 0.45

-- Distancia extra para seguir detectando la superficie bajo los pies.
local SURFACE_CHECK_EXTRA_DISTANCE = 1.75

-- Separacion extra entre los pies y la superficie.
-- Evita que el cuerpo quede parcialmente enterrado en paredes/techos.
local SURFACE_CONTACT_PADDING = 0.15

-- Correccion continua de distancia respecto a la superficie.
-- En vez de empujar siempre al personaje hacia dentro, mantenemos
-- una distancia objetivo estable entre el HRP y su nuevo suelo.
local SURFACE_DISTANCE_RESPONSE = 16
local MAX_SURFACE_CORRECTION_SPEED = 16
local SURFACE_STICK_BIAS = 0.35
local SURFACE_DISTANCE_DEADZONE = 0.04

-- Tiempo que permitimos perder momentaneamente la superficie
-- antes de soltar al personaje.
local LOST_SURFACE_GRACE = 0.10

-- Que tan rapido sigue una normal curva (por ejemplo un tronco redondo).
local NORMAL_FOLLOW_SPEED = 14

-- =========================
-- SOLID SURFACE FILTERING
-- =========================

-- Angulo minimo que una superficie que mira HACIA ARRIBA debe tener
-- respecto al suelo horizontal para convertirse en SurfaceWalking.
--
-- 0°  = piso plano
-- 30° = escalera/rampa comun              -> NO se pega
-- 45° = pendiente fuerte                  -> NO se pega con valor 55
-- 55° = empieza Chakra Feet SurfaceWalking
-- 90° = pared                              -> SI
--
-- Superficies invertidas (overhangs/techos) siguen siendo validas.
local MIN_SURFACE_ANGLE_FROM_GROUND = 55

-- Convertimos el angulo a un limite de Normal.Y.
-- Para 55° el valor es aproximadamente 0.574.
local WORLD_GROUND_DOT =
	math.cos(
		math.rad(
			MIN_SURFACE_ANGLE_FROM_GROUND
		)
	)

-- Evita que Chakra Feet intente convertir detalles pequenos en "suelo":
-- escalones individuales, barandales, postes, molduras, etc.
--
-- Se mide la cara REAL que golpeamos, no el nombre ni el tamaño total
-- en una sola direccion. Una pared fina pero grande sigue siendo valida.
local MIN_SURFACE_FACE_DIMENSION = 1.25

-- =========================
-- LOW LEDGE / CURB FILTER
-- =========================
--
-- Una cara puede ser perfectamente vertical (90 grados) y aun asi ser
-- demasiado baja para que tenga sentido convertirla en "nuevo suelo".
--
-- Ejemplos que queremos ignorar:
-- - bordes de plataformas
-- - banquetas/curbs
-- - pequeños desniveles
-- - bases elevadas
--
-- Un muro real de casa/edificio normalmente supera ampliamente este valor.
local MIN_INITIAL_WALL_VERTICAL_SPAN = 4.5

-- Solo aplicamos el filtro anterior a superficies realmente "tipo muro".
-- abs(Normal.Y) <= 0.35 equivale aproximadamente a una cara dentro de
-- ~20 grados de ser completamente vertical.
local WALLISH_NORMAL_MAX_ABS_Y = 0.35

-- Mientras YA estamos adheridos, podemos ignorar pequenos adornos
-- delante de la pared para seguir detectando la superficie principal.
local SURFACE_DETAIL_SKIP_LIMIT = 6

-- Deteccion de esquinas.
local CONCAVE_PROBE_DISTANCE = 4.25
local CONVEX_FORWARD_EXTRA = 0.75
local CONVEX_INSET_EXTRA = 0.75
local CONVEX_CAST_EXTRA = 4.0

-- Evita reengancharse instantaneamente despues de un Wall Jump.
local SURFACE_JUMP_REATTACH_DELAY = 0.25


-- =========================
-- WATER WALK SETTINGS
-- =========================

-- Distancia adicional bajo los pies para detectar agua al caer desde arriba.
local WATER_CAPTURE_EXTRA_DISTANCE = 2.25

-- Si estamos nadando, buscamos la superficie dentro de este rango vertical.
-- Esto NO nos eleva hacia ella; solo nos permite detectarla cuando nos acercamos.
local WATER_SURFACE_SEARCH_HEIGHT = 16

-- Que tan cerca debe estar el HRP de su posicion correcta sobre el agua
-- para engancharse viniendo desde debajo.
local WATER_UNDERWATER_CAPTURE_DISTANCE = 3.25

-- Maximo de piezas normales que podemos ignorar al buscar Terrain Water.
-- Sirve, por ejemplo, para poder detectar agua bajo un puente.
local WATER_RAY_MAX_SKIPS = 8

-- High-speed water-entry recovery.
-- This distance NEVER attaches early. It only remembers that the player is
-- genuinely falling toward a water surface from above.
local WATER_FALL_APPROACH_BASE_LOOKAHEAD = 10
local WATER_FALL_APPROACH_VELOCITY_MULTIPLIER = 2.75

-- If physics crosses the surface between frames and reports Swimming,
-- Chakra Feet can recover to the same surface for a very short window.
local WATER_FALL_ENTRY_GRACE = 0.48
local WATER_FALL_ENTRY_MAX_RECOVERY_DISTANCE = 8.5
local WATER_FALL_ENTRY_SURFACE_Y_TOLERANCE = 1.5
local WATER_FALL_ENTRY_MIN_DOWNWARD_SPEED = 2

-- Swept contact settings.
-- We track the point where the R6 feet should touch the water surface and raycast
-- from last frame's foot point to this frame's foot point AFTER physics.
-- This removes dependence on the character happening to be close enough on one
-- particular PreSimulation frame.
local WATER_SWEEP_MIN_DISTANCE = 0.04
local WATER_SWEEP_SURFACE_SEARCH_HEIGHT = 24
local WATER_SWEEP_SURFACE_SEARCH_DEPTH = 48
local WATER_SWEEP_ABOVE_TOLERANCE = 0.40


-- =========================
-- ORIENTATION SETTINGS
-- =========================

local ALIGN_RESPONSIVENESS = 45

-- Menor = transicion de camara mas suave al pasar suelo -> pared -> techo.
-- Usamos smoothing exponencial para que se sienta igual a distintos FPS.
local CAMERA_TRANSFORM_SPEED = 4.5

-- Water Walk is world-up, so it does not need the same contact bias used to
-- keep a character glued to walls. A dedicated vertical correction prevents
-- the tiny sink/correct cycle that can make the camera feel like it is
-- stepping or bobbing.
local WATER_HEIGHT_RESPONSE = 22
local WATER_MAX_HEIGHT_CORRECTION_SPEED = 10
local WATER_HEIGHT_DEADZONE = 0.025

-- Water has no changing surface normal; a more responsive facing correction
-- removes the delayed feeling when turning while walking over it.
local WATER_ALIGN_RESPONSIVENESS = 90


-- =========================
-- ANIMATION IDS
-- =========================

local IDLE_ANIMATION_ID = "rbxassetid://129182759601754"
local WALK_ANIMATION_ID = "rbxassetid://75479783841702"
local RUN_ANIMATION_ID = "rbxassetid://116142758807536"
local LEFT_RUN_ANIMATION_ID = "rbxassetid://96610792244949"
local RIGHT_RUN_ANIMATION_ID = "rbxassetid://121603680342672"

local IDLE_ANIMATION_SPEED = 1.0
local WALK_ANIMATION_SPEED = 1.8

-- Keep Surface/Water Run playback identical to SprintController v1.15.
local RUN_ANIMATION_SPEED = 1.4

-- Same directional threshold used by SprintController v1.15.
local COMBAT_DIRECTIONAL_RUN_LATERAL_THRESHOLD = 0.35


-- =========================
-- ATTRIBUTES
-- =========================

character:SetAttribute("ChakraFeetActive", false)
character:SetAttribute("SurfaceWalking", false)
character:SetAttribute("SurfaceMoving", false)
character:SetAttribute("SurfaceNormal", Vector3.yAxis)
character:SetAttribute("SurfaceMoveDirection", Vector3.zero)
character:SetAttribute("SurfaceDashFacingDirection", Vector3.zero)
character:SetAttribute("SurfaceJumping", false)
character:SetAttribute("WaterWalking", false)


-- =========================
-- STATE
-- =========================

local chakraFeetActive = false
local surfaceWalking = false
local waterWalking = false

local currentNormal = Vector3.yAxis

-- Direccion estable usada para transportar el sistema de coordenadas
-- de una superficie a otra.
local surfaceBasisForward = Vector3.new(0, 0, -1)

-- Direccion real hacia donde mira el personaje.
local facingForward = Vector3.new(0, 0, -1)

-- Direccion horizontal virtual que tenia el jugador antes de adherirse.
-- La camara de Roblox sigue operando en ese espacio virtual y luego
-- nosotros la transformamos al espacio de la superficie.
local virtualHeading = Vector3.new(0, 0, -1)

local lastCPressTime = -math.huge
local lostSurfaceTime = 0
local lastSurfaceJumpTime = -math.huge

-- Proof that the current Swimming entry came from ABOVE the water.
-- This prevents the recovery system from pulling a normal underwater swimmer up.
local lastWaterFallApproachTime = -math.huge
local lastWaterFallApproachSurfaceY = nil

-- Previous post-physics foot-contact sample used for swept water collision.
local previousWaterFootProbePosition = nil

local previousAutoRotate = nil

local surfaceAttachment = nil
local alignOrientation = nil
local gravityCancelForce = nil

local currentCameraTransform = CFrame.new()
local targetCameraTransform = CFrame.new()


-- =========================
-- ANIMATION TRACKS
-- =========================

local function createTrack(name, animationId, priority, looped)
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId

	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped

	return track
end

local surfaceIdleTrack = createTrack(
	"SurfaceIdleAnimation",
	IDLE_ANIMATION_ID,
	Enum.AnimationPriority.Idle,
	true
)

local surfaceWalkTrack = createTrack(
	"SurfaceWalkAnimation",
	WALK_ANIMATION_ID,
	Enum.AnimationPriority.Movement,
	true
)

local surfaceRunTrack = createTrack(
	"SurfaceRunAnimation",
	RUN_ANIMATION_ID,
	Enum.AnimationPriority.Movement,
	true
)

local surfaceLeftRunTrack = createTrack(
	"SurfaceLeftRunAnimation",
	LEFT_RUN_ANIMATION_ID,
	Enum.AnimationPriority.Movement,
	true
)

local surfaceRightRunTrack = createTrack(
	"SurfaceRightRunAnimation",
	RIGHT_RUN_ANIMATION_ID,
	Enum.AnimationPriority.Movement,
	true
)

local activeSurfaceRunTrack = nil


-- =========================
-- DEFAULT SWIM ANIMATIONS
-- =========================

-- Water Walk must not disable HumanoidStateType.Swimming.
-- The previous version did that too aggressively and could prevent
-- Terrain Water from transitioning correctly.
--
-- We only identify the default Swim tracks so that, once Water Walk
-- captures the character, a one-frame swim animation cannot remain visible.

local swimAnimationIds = {}

local function collectAnimationIds(container)
	if not container then
		return
	end

	if container:IsA("Animation")
		and container.AnimationId ~= "" then

		swimAnimationIds[
		container.AnimationId
		] = true
	end

	for _, descendant in ipairs(
		container:GetDescendants()
		) do
		if descendant:IsA("Animation")
			and descendant.AnimationId ~= "" then

			swimAnimationIds[
			descendant.AnimationId
			] = true
		end
	end
end

collectAnimationIds(
	animate:FindFirstChild("swim")
)

collectAnimationIds(
	animate:FindFirstChild("swimidle")
)

local function stopSwimAnimations(fadeTime)
	fadeTime = fadeTime or 0

	for _, track in ipairs(
		animator:GetPlayingAnimationTracks()
		) do
		local animation =
			track.Animation

		local animationId =
			animation
			and animation.AnimationId
			or ""

		local trackName =
			string.lower(
				track.Name or ""
			)

		local animationName =
			animation
			and string.lower(
				animation.Name or ""
			)
			or ""

		local isSwim =
			swimAnimationIds[
		animationId
		] == true
			or string.find(
				trackName,
				"swim",
				1,
				true
			) ~= nil
			or string.find(
				animationName,
				"swim",
				1,
				true
			) ~= nil

		if isSwim then
			track:Stop(
				fadeTime
			)
		end
	end
end


-- =========================
-- RAYCAST PARAMS
-- =========================

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Exclude
surfaceParams.FilterDescendantsInstances = { character }
surfaceParams.IgnoreWater = true
surfaceParams.RespectCanCollide = true

-- Raycasts dedicados a Terrain Water.
-- IgnoreWater = false hace que Enum.Material.Water participe en el raycast.
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.FilterDescendantsInstances = { character }
waterParams.IgnoreWater = false
waterParams.RespectCanCollide = false


-- =========================
-- VECTOR HELPERS
-- =========================

local function projectOnPlane(vector, normal)
	return vector - normal * vector:Dot(normal)
end

local function safeUnit(vector, fallback)
	if vector.Magnitude > 0.001 then
		return vector.Unit
	end

	return fallback
end

local function calculateSurfaceOffset()
	-- En R6 el HRP esta aproximadamente en el centro del torso.
	-- Calculamos la distancia REAL desde el HRP hasta la parte inferior
	-- de las piernas usando el espacio local del propio RootPart.

	local maxFootDistance = 0

	for _, legName in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = character:FindFirstChild(legName)

		if leg and leg:IsA("BasePart") then
			local localPosition =
				rootPart.CFrame:PointToObjectSpace(leg.Position)

			local footDistance =
				-localPosition.Y + (leg.Size.Y / 2)

			maxFootDistance =
				math.max(maxFootDistance, footDistance)
		end
	end

	local fallbackOffset =
		humanoid.HipHeight
		+ (rootPart.Size.Y / 2)
		+ 1.5

	return math.max(
		maxFootDistance,
		fallbackOffset,
		2.75
	) + SURFACE_CONTACT_PADDING
end

local SURFACE_OFFSET = calculateSurfaceOffset()

local function getSurfaceOffset()
	return SURFACE_OFFSET
end

local function getWorldHorizontal(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)

	if flat.Magnitude > 0.001 then
		return flat.Unit
	end

	return nil
end

local function isOtherCharacterPart(instance)
	if not instance then
		return false
	end

	local current = instance

	while current and current ~= workspace do
		if current:IsA("Model")
			and current ~= character
			and current:FindFirstChildOfClass("Humanoid") then

			return true
		end

		current = current.Parent
	end

	return false
end


-- =========================
-- SOLID SURFACE VALIDATION
-- =========================

local function isUpwardSurfaceTooFlat(normal)
	-- Solo clasificamos como "suelo normal" las caras que miran hacia arriba.
	--
	-- Una pared tiene Normal.Y ~= 0.
	-- Un techo tiene Normal.Y ~= -1 y por lo tanto sigue siendo valido.
	return normal:Dot(
		Vector3.yAxis
	) >= WORLD_GROUND_DOT
end

local function getHitFaceDimensions(hit)
	if not hit
		or not hit.Instance then

		return nil, nil
	end

	local part =
		hit.Instance

	-- Terrain no tiene Size como un BasePart.
	-- Sus superficies se filtran por angulo, no por tamaño de pieza.
	if part == workspace.Terrain then
		return math.huge, math.huge
	end

	if not part:IsA("BasePart") then
		return nil, nil
	end

	-- Convertimos la normal golpeada al espacio local de la pieza.
	-- El eje dominante nos dice que cara aproximada estamos tocando.
	local localNormal =
		part.CFrame:
		VectorToObjectSpace(
			hit.Normal
		)

	local ax =
		math.abs(
			localNormal.X
		)

	local ay =
		math.abs(
			localNormal.Y
		)

	local az =
		math.abs(
			localNormal.Z
		)

	local size =
		part.Size

	if ax >= ay
		and ax >= az then

		-- Cara +/-X -> dimensiones Y/Z.
		return size.Y, size.Z

	elseif ay >= ax
		and ay >= az then

		-- Cara +/-Y -> dimensiones X/Z.
		return size.X, size.Z

	else
		-- Cara +/-Z -> dimensiones X/Y.
		return size.X, size.Y
	end
end

local function isSurfaceFaceLargeEnough(hit)
	local dimensionA,
		dimensionB =
		getHitFaceDimensions(
			hit
		)

	if not dimensionA
		or not dimensionB then

		return false
	end

	return dimensionA >=
		MIN_SURFACE_FACE_DIMENSION
		and dimensionB >=
		MIN_SURFACE_FACE_DIMENSION
end


-- =========================
-- WORLD VERTICAL SPAN
-- =========================

local function getWorldVerticalSpan(instance)
	if instance == workspace.Terrain then
		return math.huge
	end

	if not instance
		or not instance:IsA("BasePart") then

		return 0
	end

	local cf =
		instance.CFrame

	local size =
		instance.Size

	-- Altura del bounding box de la pieza proyectada sobre World Y.
	-- Funciona tambien con piezas rotadas.
	return math.abs(
		cf.RightVector.Y
	) * size.X
		+
		math.abs(
			cf.UpVector.Y
		) * size.Y
		+
		math.abs(
			cf.LookVector.Y
		) * size.Z
end


-- =========================
-- INITIAL WALL HEIGHT FILTER
-- =========================

local function isMeaningfulInitialWall(
	hit
)
	if not hit
		or not hit.Instance then

		return false
	end

	local normal =
		hit.Normal.Unit

	-- Rampas y otras superficies inclinadas se deciden mediante
	-- MIN_SURFACE_ANGLE_FROM_GROUND. Este filtro extra solo existe
	-- para caras casi verticales.
	if math.abs(
		normal.Y
		) > WALLISH_NORMAL_MAX_ABS_Y then

		return true
	end

	local verticalSpan =
		getWorldVerticalSpan(
			hit.Instance
		)

	return verticalSpan >=
		MIN_INITIAL_WALL_VERTICAL_SPAN
end

local function isValidSolidSurfaceHit(
	hit
)
	if not hit
		or not hit.Instance then

		return false
	end

	if isOtherCharacterPart(
		hit.Instance
		) then

		return false
	end

	if not isSurfaceFaceLargeEnough(
		hit
		) then

		return false
	end

	return true
end

local function spherecastIgnoringSmallDetails(
	origin,
	radius,
	direction
)
	if direction.Magnitude < 0.001 then
		return nil
	end

	local ignoreList = {
		character
	}

	for _ = 1,
		SURFACE_DETAIL_SKIP_LIMIT do

		surfaceParams.FilterDescendantsInstances =
			ignoreList

		local hit =
			workspace:Spherecast(
				origin,
				radius,
				direction,
				surfaceParams
			)

		if not hit then
			surfaceParams.FilterDescendantsInstances = {
				character
			}

			return nil
		end

		if isOtherCharacterPart(
			hit.Instance
			) then

			-- Personajes ajenos no se convierten en superficies.
			-- Si es BasePart podemos ignorarlo y seguir buscando pared.
			if hit.Instance:IsA(
				"BasePart"
				) then

				table.insert(
					ignoreList,
					hit.Instance
				)

				continue
			end

			break
		end

		if not isSurfaceFaceLargeEnough(
			hit
			) then

			-- Un detalle pequeño pegado a una pared no debe cambiar
			-- la normal ni hacer girar/ragdollear al personaje.
			if hit.Instance:IsA(
				"BasePart"
				) then

				table.insert(
					ignoreList,
					hit.Instance
				)

				continue
			end

			break
		end

		surfaceParams.FilterDescendantsInstances = {
			character
		}

		return hit
	end

	surfaceParams.FilterDescendantsInstances = {
		character
	}

	return nil
end


-- =========================
-- WATER HELPERS
-- =========================

local function isWaterHit(hit)
	return hit ~= nil
		and hit.Material == Enum.Material.Water
end

local function directWaterRaycast(origin, direction)
	if direction.Magnitude < 0.001 then
		return nil
	end

	waterParams.FilterDescendantsInstances = { character }

	local hit = workspace:Raycast(
		origin,
		direction,
		waterParams
	)

	if isWaterHit(hit) then
		return hit
	end

	return nil
end

local function raycastForWater(origin, direction)
	if direction.Magnitude < 0.001 then
		return nil
	end

	local ignoreList = { character }

	for _ = 1, WATER_RAY_MAX_SKIPS do
		waterParams.FilterDescendantsInstances = ignoreList

		local hit = workspace:Raycast(
			origin,
			direction,
			waterParams
		)

		if not hit then
			return nil
		end

		if isWaterHit(hit) then
			return hit
		end

		-- Terrain no puede excluirse parcialmente: si golpeamos Terrain
		-- que NO es agua, no intentamos atravesarlo buscando agua detras.
		if hit.Instance == workspace.Terrain then
			return nil
		end

		if hit.Instance then
			table.insert(ignoreList, hit.Instance)
		else
			return nil
		end
	end

	return nil
end

local function getWaterSurfaceBelow(extraDistance)
	local distance =
		getSurfaceOffset()
		+ WATER_CAPTURE_EXTRA_DISTANCE
		+ (extraDistance or 0)

	return directWaterRaycast(
		rootPart.Position,
		-Vector3.yAxis * distance
	)
end

local function rememberWaterApproachFromAbove(deltaTime)
	local velocityY =
		rootPart.AssemblyLinearVelocity.Y

	if velocityY >
		-WATER_FALL_ENTRY_MIN_DOWNWARD_SPEED then

		return nil
	end

	local dynamicLookahead =
		math.max(
			WATER_FALL_APPROACH_BASE_LOOKAHEAD,
			(-velocityY)
			* deltaTime
			* WATER_FALL_APPROACH_VELOCITY_MULTIPLIER
		)

	local approachHit =
		directWaterRaycast(
			rootPart.Position,
			-Vector3.yAxis
			* (
				getSurfaceOffset()
				+ dynamicLookahead
			)
		)

	if not approachHit then
		return nil
	end

	local desiredRootY =
		approachHit.Position.Y
		+ getSurfaceOffset()

	-- Only arm while we are still above the intended Water Walk height.
	if rootPart.Position.Y <
		desiredRootY - 0.25 then

		return nil
	end

	lastWaterFallApproachTime =
		time()

	lastWaterFallApproachSurfaceY =
		approachHit.Position.Y

	return approachHit
end


local function getWaterSurfaceAtWorldPoint(worldPoint)
	local origin =
		Vector3.new(
			worldPoint.X,
			worldPoint.Y + WATER_SWEEP_SURFACE_SEARCH_HEIGHT,
			worldPoint.Z
		)

	local direction =
		-Vector3.yAxis
		* WATER_SWEEP_SURFACE_SEARCH_DEPTH

	return raycastForWater(
		origin,
		direction
	)
end


local function getWaterFootProbePosition()
	-- Surface offset is the HRP-to-surface walking height. Subtracting it gives
	-- the point that should touch the water while Water Walking.
	return rootPart.Position
	- Vector3.yAxis * getSurfaceOffset()
end


local function findWaterSurfaceWhileSwimming()
	local origin =
		rootPart.Position
		+ Vector3.yAxis * WATER_SURFACE_SEARCH_HEIGHT

	local direction =
		-Vector3.yAxis
		* (WATER_SURFACE_SEARCH_HEIGHT * 2)

	return raycastForWater(origin, direction)
end


-- =========================
-- TREE JUMP CHECK
-- =========================

local function isTreeJumpActive()
	return character:GetAttribute("TreeJumpActive") == true
		or character:GetAttribute("IsTreeJumping") == true
end


-- =========================
-- AIR DASH -> WATER HANDOFF
-- =========================
--
-- DashController intentionally keeps IsDashing=true through the complete
-- ballistic Air Dash carry. SurfaceController must still block Water Walk
-- during the POWERED dash impulse, otherwise a dash aimed through/along the
-- water can be snapped prematurely to the surface.
--
-- Once AirDashCarryActive=true, the powered impulse is over. If the character
-- is now descending, Chakra Feet is allowed to capture the water exactly like
-- a normal fall. DashController will see WaterWalking=true and release its
-- carry ownership immediately.
local function isWaterCaptureBlockedByDash()
	if character:GetAttribute("IsDashing") ~= true then
		return false
	end

	local carryActive =
		character:GetAttribute(
			"AirDashCarryActive"
		) == true

	if not carryActive then
		return true
	end

	-- Do not pull an ascending Air Dash back down onto the water.
	-- At/after the apex, downward motion can hand off to Water Walk.
	return rootPart.AssemblyLinearVelocity.Y > 0
end


-- =========================
-- CAMERA TRANSFORM
-- =========================

local function rebuildTargetCameraTransform()
	if not surfaceWalking
		or waterWalking then

		targetCameraTransform = CFrame.new()
		return
	end

	local actualForward =
		safeUnit(
			projectOnPlane(surfaceBasisForward, currentNormal),
			facingForward
		)

	local actualFrame =
		CFrame.lookAt(
			Vector3.zero,
			actualForward,
			currentNormal
		)

	local virtualForward =
		getWorldHorizontal(virtualHeading)
		or Vector3.new(0, 0, -1)

	local virtualFrame =
		CFrame.lookAt(
			Vector3.zero,
			virtualForward,
			Vector3.yAxis
		)

	targetCameraTransform =
		actualFrame * virtualFrame:Inverse()
end

local function transformCameraAroundPivot(cameraCFrame, transform, pivot)
	local relativePosition =
		cameraCFrame.Position - pivot

	local transformedPosition =
		pivot
		+ transform:VectorToWorldSpace(relativePosition)

	local transformedLook =
		transform:VectorToWorldSpace(
			cameraCFrame.LookVector
		)

	local transformedUp =
		transform:VectorToWorldSpace(
			cameraCFrame.UpVector
		)

	return CFrame.lookAt(
		transformedPosition,
		transformedPosition + transformedLook,
		transformedUp
	)
end

local CAMERA_PRE_BIND = "SurfaceCamera_Pre"
local CAMERA_POST_BIND = "SurfaceCamera_Post"

RunService:UnbindFromRenderStep(CAMERA_PRE_BIND)
RunService:UnbindFromRenderStep(CAMERA_POST_BIND)

RunService:BindToRenderStep(
	CAMERA_PRE_BIND,
	Enum.RenderPriority.Camera.Value - 1,
	function()
		local camera = workspace.CurrentCamera

		if not camera then
			return
		end

		if currentCameraTransform == CFrame.new() then
			return
		end

		camera.CFrame =
			transformCameraAroundPivot(
				camera.CFrame,
				currentCameraTransform:Inverse(),
				rootPart.Position
			)
	end
)

RunService:BindToRenderStep(
	CAMERA_POST_BIND,
	Enum.RenderPriority.Camera.Value + 1,
	function(deltaTime)
		local camera = workspace.CurrentCamera

		if not camera then
			return
		end

		rebuildTargetCameraTransform()

		if waterWalking then
			currentCameraTransform =
				CFrame.new()

			targetCameraTransform =
				CFrame.new()

			return
		end

		local alpha =
			1 - math.exp(
				-CAMERA_TRANSFORM_SPEED * deltaTime
			)

		currentCameraTransform =
			currentCameraTransform:Lerp(
				targetCameraTransform,
				alpha
			)

		if not surfaceWalking then
			local lookDelta =
				(
					currentCameraTransform.LookVector
					- CFrame.new().LookVector
				).Magnitude

			local upDelta =
				(
					currentCameraTransform.UpVector
					- CFrame.new().UpVector
				).Magnitude

			if lookDelta < 0.001
				and upDelta < 0.001 then

				currentCameraTransform =
					CFrame.new()
			end
		end

		if currentCameraTransform ~= CFrame.new() then
			camera.CFrame =
				transformCameraAroundPivot(
					camera.CFrame,
					currentCameraTransform,
					rootPart.Position
				)
		end
	end
)


-- =========================
-- SURFACE ANIMATIONS
-- =========================

local function stopSurfaceRunAnimations(fadeTime)
	fadeTime = fadeTime or 0.08

	for _, track in ipairs({
		surfaceRunTrack,
		surfaceLeftRunTrack,
		surfaceRightRunTrack,
		}) do
		if track.IsPlaying then
			track:Stop(fadeTime)
		end
	end

	activeSurfaceRunTrack = nil
end

local function stopSurfaceAnimations(fadeTime)
	fadeTime = fadeTime or 0.08

	if surfaceIdleTrack.IsPlaying then
		surfaceIdleTrack:Stop(fadeTime)
	end

	if surfaceWalkTrack.IsPlaying then
		surfaceWalkTrack:Stop(fadeTime)
	end

	stopSurfaceRunAnimations(fadeTime)
end

local function stopConflictingLocomotionAnimations()
	for _, track in ipairs(
		animator:GetPlayingAnimationTracks()
		) do
		local animation = track.Animation
		local animationId =
			animation and animation.AnimationId or ""

		if animationId == IDLE_ANIMATION_ID
			or animationId == WALK_ANIMATION_ID
			or animationId == RUN_ANIMATION_ID
			or animationId == LEFT_RUN_ANIMATION_ID
			or animationId == RIGHT_RUN_ANIMATION_ID
			or animationId == "rbxassetid://96074100792499"
			or animationId == "rbxassetid://92479075812419" then

			if track ~= surfaceIdleTrack
				and track ~= surfaceWalkTrack
				and track ~= surfaceRunTrack
				and track ~= surfaceLeftRunTrack
				and track ~= surfaceRightRunTrack then

				track:Stop(0.05)
			end
		end
	end
end

local function getDesiredSurfaceRunTrack()
	if character:GetAttribute("CombatMode") ~= true then
		return surfaceRunTrack
	end

	local moveDirection =
		character:GetAttribute("SurfaceMoveDirection")

	if typeof(moveDirection) ~= "Vector3"
		or moveDirection.Magnitude <= 0.05 then

		return surfaceRunTrack
	end

	local surfaceMove =
		projectOnPlane(
			moveDirection,
			currentNormal
		)

	local surfaceRight =
		projectOnPlane(
			rootPart.CFrame.RightVector,
			currentNormal
		)

	if surfaceMove.Magnitude <= 0.05
		or surfaceRight.Magnitude <= 0.05 then

		return surfaceRunTrack
	end

	local lateralDot =
		surfaceMove.Unit:Dot(
			surfaceRight.Unit
		)

	if lateralDot >=
		COMBAT_DIRECTIONAL_RUN_LATERAL_THRESHOLD then

		return surfaceRightRunTrack
	end

	if lateralDot <=
		-COMBAT_DIRECTIONAL_RUN_LATERAL_THRESHOLD then

		return surfaceLeftRunTrack
	end

	return surfaceRunTrack
end

local function startSurfaceRunAnimation()
	local desiredTrack =
		getDesiredSurfaceRunTrack()

	if activeSurfaceRunTrack ~= desiredTrack then
		if activeSurfaceRunTrack
			and activeSurfaceRunTrack.IsPlaying then

			activeSurfaceRunTrack:Stop(0.06)
		end

		activeSurfaceRunTrack = desiredTrack
	end

	for _, track in ipairs({
		surfaceRunTrack,
		surfaceLeftRunTrack,
		surfaceRightRunTrack,
		}) do
		if track ~= desiredTrack
			and track.IsPlaying then

			track:Stop(0.06)
		end
	end

	if not desiredTrack.IsPlaying then
		desiredTrack:Play(0.06)
	end

	desiredTrack:AdjustSpeed(
		RUN_ANIMATION_SPEED
	)
end

local function updateSurfaceAnimation(isMoving)
	if not surfaceWalking
		or character:GetAttribute("IsDashing")
		or isTreeJumpActive() then

		stopSurfaceAnimations(0.05)
		return
	end

	local sprintActive =
		character:GetAttribute("IsSprinting") == true

	if not isMoving then
		if surfaceWalkTrack.IsPlaying then
			surfaceWalkTrack:Stop(0.08)
		end

		stopSurfaceRunAnimations(0.08)

		if not surfaceIdleTrack.IsPlaying then
			surfaceIdleTrack:Play(0.10)
			surfaceIdleTrack:AdjustSpeed(
				IDLE_ANIMATION_SPEED
			)
		end

	elseif sprintActive then
		if surfaceIdleTrack.IsPlaying then
			surfaceIdleTrack:Stop(0.08)
		end

		if surfaceWalkTrack.IsPlaying then
			surfaceWalkTrack:Stop(0.08)
		end

		startSurfaceRunAnimation()

	else
		if surfaceIdleTrack.IsPlaying then
			surfaceIdleTrack:Stop(0.08)
		end

		stopSurfaceRunAnimations(0.08)

		if not surfaceWalkTrack.IsPlaying then
			surfaceWalkTrack:Play(0.08)
			surfaceWalkTrack:AdjustSpeed(
				WALK_ANIMATION_SPEED
			)
		end
	end
end


-- =========================
-- PHYSICS OBJECTS
-- =========================

local function createSurfacePhysics()
	if surfaceAttachment then
		return
	end

	surfaceAttachment =
		Instance.new("Attachment")

	surfaceAttachment.Name =
		"SurfaceMovementAttachment"

	surfaceAttachment.Parent =
		rootPart


	alignOrientation =
		Instance.new("AlignOrientation")

	alignOrientation.Name =
		"SurfaceAlignOrientation"

	alignOrientation.Mode =
		Enum.OrientationAlignmentMode.OneAttachment

	alignOrientation.Attachment0 =
		surfaceAttachment

	alignOrientation.MaxTorque =
		math.huge

	alignOrientation.Responsiveness =
		ALIGN_RESPONSIVENESS

	alignOrientation.RigidityEnabled =
		false

	alignOrientation.Parent =
		rootPart


	gravityCancelForce =
		Instance.new("VectorForce")

	gravityCancelForce.Name =
		"SurfaceGravityCancel"

	gravityCancelForce.Attachment0 =
		surfaceAttachment

	gravityCancelForce.RelativeTo =
		Enum.ActuatorRelativeTo.World

	gravityCancelForce.ApplyAtCenterOfMass =
		true

	gravityCancelForce.Parent =
		rootPart
end

local function destroySurfacePhysics()
	if gravityCancelForce then
		gravityCancelForce:Destroy()
		gravityCancelForce = nil
	end

	if alignOrientation then
		alignOrientation:Destroy()
		alignOrientation = nil
	end

	if surfaceAttachment then
		surfaceAttachment:Destroy()
		surfaceAttachment = nil
	end
end


-- =========================
-- ORIENTATION
-- =========================

local function updateAlignOrientation()
	if not surfaceWalking
		or not alignOrientation then

		return
	end

	local forward =
		projectOnPlane(
			facingForward,
			currentNormal
		)

	if forward.Magnitude < 0.01 then
		forward =
			projectOnPlane(
				surfaceBasisForward,
				currentNormal
			)
	end

	forward =
		safeUnit(
			forward,
			surfaceBasisForward
		)

	facingForward =
		forward

	alignOrientation.Responsiveness =
		if waterWalking
		then WATER_ALIGN_RESPONSIVENESS
		else ALIGN_RESPONSIVENESS

	alignOrientation.CFrame =
		CFrame.lookAt(
			Vector3.zero,
			forward,
			currentNormal
		)

	rootPart.AssemblyAngularVelocity =
		Vector3.zero
end

local function getCameraForwardOnSurface()
	local camera = workspace.CurrentCamera

	if not camera then
		return surfaceBasisForward
	end

	local forward =
		projectOnPlane(
			camera.CFrame.LookVector,
			currentNormal
		)

	if forward.Magnitude < 0.05 then
		forward =
			projectOnPlane(
				surfaceBasisForward,
				currentNormal
			)
	end

	return safeUnit(
		forward,
		surfaceBasisForward
	)
end

local function isStatusMovementBlocked()
	return character:GetAttribute(
		"Status_MovementBlocked"
	) == true
		or character:GetAttribute(
			"Status_Stunned"
		) == true
end

local function getSurfaceInputDirection()
	-- Status Stun only suppresses tangential player input.
	-- It does NOT touch Water Walk height, camera, orientation,
	-- adhesion, raycasts, or any other Surface behavior.
	if isStatusMovementBlocked() then
		return Vector3.zero
	end

	local forward =
		getCameraForwardOnSurface()

	local right =
		forward:Cross(
			currentNormal
		)

	right =
		safeUnit(
			right,
			rootPart.CFrame.RightVector
		)

	local forwardInput = 0
	local rightInput = 0

	if UserInputService:IsKeyDown(
		Enum.KeyCode.W
		) then

		forwardInput += 1
	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.S
		) then

		forwardInput -= 1
	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.D
		) then

		rightInput += 1
	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.A
		) then

		rightInput -= 1
	end

	local direction =
		(forward * forwardInput)
		+ (right * rightInput)

	if direction.Magnitude > 0.01 then
		return direction.Unit
	end

	return Vector3.zero
end


-- =========================
-- VIRTUAL GROUND INPUT
-- =========================

local function getVirtualGroundInputDirection()

	local camera =
		workspace.CurrentCamera

	if not camera then

		return Vector3.zero

	end

	local virtualCameraCFrame =
		camera.CFrame

	if currentCameraTransform ~=
		CFrame.new() then

		virtualCameraCFrame =
			transformCameraAroundPivot(
				camera.CFrame,
				currentCameraTransform:Inverse(),
				rootPart.Position
			)

	end

	local forward =
		getWorldHorizontal(
			virtualCameraCFrame.LookVector
		)

	local right =
		getWorldHorizontal(
			virtualCameraCFrame.RightVector
		)

	if not forward
		or not right then

		return Vector3.zero

	end

	local forwardInput = 0
	local rightInput = 0

	if UserInputService:IsKeyDown(
		Enum.KeyCode.W
		) then

		forwardInput += 1

	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.S
		) then

		forwardInput -= 1

	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.D
		) then

		rightInput += 1

	end

	if UserInputService:IsKeyDown(
		Enum.KeyCode.A
		) then

		rightInput -= 1

	end

	local direction =
		(forward * forwardInput)
		+ (right * rightInput)

	if direction.Magnitude >
		0.05 then

		return direction.Unit

	end

	return Vector3.zero

end


-- =========================
-- UPRIGHT AFTER DETACH
-- =========================

local function makeCharacterWorldUpright(
	preferredForward
)

	if not rootPart.Parent then

		return

	end

	local combatMode =
		character:GetAttribute(
			"CombatMode"
		) == true
		and character:GetAttribute(
			"CombatSuppressed"
		) ~= true

	local forward = nil

	if combatMode then

		forward =
			getWorldHorizontal(
				facingForward
			)

		if not forward then

			local camera =
				workspace.CurrentCamera

			if camera then

				forward =
					getWorldHorizontal(
						camera.CFrame.LookVector
					)

			end

		end

	else

		if typeof(preferredForward) ==
			"Vector3"
			and preferredForward.Magnitude >
			0.05 then

			forward =
				getWorldHorizontal(
					preferredForward
				)

		end

		if not forward then

			local virtualInput =
				getVirtualGroundInputDirection()

			if virtualInput.Magnitude >
				0.05 then

				forward =
					virtualInput

			end

		end

		if not forward then

			forward =
				getWorldHorizontal(
					humanoid.MoveDirection
				)

		end

		if not forward then

			forward =
				getWorldHorizontal(
					rootPart.AssemblyLinearVelocity
				)

		end

		if not forward then

			forward =
				getWorldHorizontal(
					rootPart.CFrame.LookVector
				)

		end

	end

	forward =
		forward
		or Vector3.new(
			0,
			0,
			-1
		)

	rootPart.AssemblyAngularVelocity =
		Vector3.zero

	rootPart.CFrame =
		CFrame.lookAt(
			rootPart.Position,
			rootPart.Position
			+ forward,
			Vector3.yAxis
		)

end


-- =========================
-- RELEASE SURFACE
-- =========================

local function releaseSurface(handOffToOtherMovement)
	if not surfaceWalking then
		return
	end

	local detachForward =
		Vector3.zero

	if character:GetAttribute(
		"CombatMode"
		) ~= true
			or character:GetAttribute(
				"CombatSuppressed"
			) == true then

		detachForward =
			getVirtualGroundInputDirection()

		if detachForward.Magnitude <
			0.05 then

			local storedSurfaceMove =
				character:GetAttribute(
					"SurfaceMoveDirection"
				)

			if typeof(storedSurfaceMove) ==
				"Vector3" then

				detachForward =
					storedSurfaceMove

			end
		end
	end

	surfaceWalking = false
	waterWalking = false

	reportChakraFeetMode(
		"Off"
	)

	character:SetAttribute(
		"SurfaceWalking",
		false
	)

	character:SetAttribute(
		"WaterWalking",
		false
	)

	character:SetAttribute(
		"SurfaceMoving",
		false
	)

	character:SetAttribute(
		"SurfaceMoveDirection",
		Vector3.zero
	)

	stopSurfaceAnimations(0.06)
	destroySurfacePhysics()

	-- Surface no longer inherits the old GlobalNoTrip policy.
	-- These states are disabled only while Surface owns Physics.
	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.FallingDown,
		true
	)

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Ragdoll,
		true
	)

	humanoid:SetStateEnabled(
		Enum.HumanoidStateType.GettingUp,
		true
	)

	if not handOffToOtherMovement then
		makeCharacterWorldUpright(
			detachForward
		)

		local combatMode =
			character:GetAttribute(
				"CombatMode"
			) == true
			and character:GetAttribute(
				"CombatSuppressed"
			) ~= true

		humanoid.AutoRotate =
			not combatMode

		if humanoid.FloorMaterial ==
			Enum.Material.Air then

			humanoid:ChangeState(
				Enum.HumanoidStateType.Freefall
			)
		else
			humanoid:ChangeState(
				Enum.HumanoidStateType.Running
			)
		end

		if not combatMode then

			task.defer(
				function()

					if character.Parent
						and character:GetAttribute(
							"SurfaceWalking"
						) ~= true
							and character:GetAttribute(
								"CombatMode"
							) ~= true
							and character:GetAttribute(
								"IsTreeJumping"
							) ~= true
							and character:GetAttribute(
								"TreeJumpActive"
							) ~= true then

						humanoid.AutoRotate =
							true

					end

				end
			)

		end
	end

	previousAutoRotate = nil

	lostSurfaceTime = 0

	targetCameraTransform =
		CFrame.new()
end


-- =========================
-- SURFACE FRAME TRANSPORT
-- =========================

local function getTransportedForward(
	oldForward,
	oldUp,
	newUp,
	transitionKind
)
	local projected =
		projectOnPlane(
			oldForward,
			newUp
		)

	if projected.Magnitude > 0.05 then
		return projected.Unit
	end

	if transitionKind == "Concave"
		or transitionKind == "Attach" then

		projected =
			projectOnPlane(
				oldUp,
				newUp
			)

	elseif transitionKind == "Convex" then

		projected =
			projectOnPlane(
				-oldUp,
				newUp
			)
	end

	if projected.Magnitude <= 0.05 then
		projected =
			projectOnPlane(
				facingForward,
				newUp
			)
	end

	return safeUnit(
		projected,
		Vector3.new(0, 0, -1)
	)
end


-- =========================
-- ATTACH
-- =========================

local function attachToSurface(
	hit,
	transitionKind
)
	if not hit
		or not hit.Instance then

		return false
	end

	if not isValidSolidSurfaceHit(
		hit
		) then

		return false
	end

	local newNormal =
		hit.Normal.Unit

	if surfaceWalking
		and newNormal:Dot(
			Vector3.yAxis
		) >= WORLD_GROUND_DOT then

		local offset =
			getSurfaceOffset()

		local landingPosition =
			hit.Position
			+ newNormal * offset

		rootPart.CFrame =
			CFrame.new(
				landingPosition
			)
			* rootPart.CFrame.Rotation

		releaseSurface(false)

		return false
	end

	local oldUp =
		surfaceWalking
		and currentNormal
		or Vector3.yAxis

	local oldBasis =
		surfaceWalking
		and surfaceBasisForward
		or (
			getWorldHorizontal(
				rootPart.CFrame.LookVector
			)
			or Vector3.new(0, 0, -1)
		)

	local newBasis =
		getTransportedForward(
			oldBasis,
			oldUp,
			newNormal,
			transitionKind
		)

	if not surfaceWalking then
		previousAutoRotate =
			humanoid.AutoRotate

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.FallingDown,
			false
		)

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Ragdoll,
			false
		)

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.GettingUp,
			false
		)

		humanoid.AutoRotate =
			false

		humanoid:ChangeState(
			Enum.HumanoidStateType.Physics
		)

		stopSwimAnimations(0)

		createSurfacePhysics()

		surfaceWalking =
			true

		character:SetAttribute(
			"SurfaceWalking",
			true
		)

		local heading =
			getWorldHorizontal(
				rootPart.CFrame.LookVector
			)

		if not heading then
			local camera =
				workspace.CurrentCamera

			if camera then
				heading =
					getWorldHorizontal(
						camera.CFrame.LookVector
					)
			end
		end

		virtualHeading =
			heading
			or Vector3.new(0, 0, -1)

		stopConflictingLocomotionAnimations()
	end

	waterWalking = false

	character:SetAttribute(
		"WaterWalking",
		false
	)

	reportChakraFeetMode(
		"Solid"
	)

	currentNormal =
		newNormal

	surfaceBasisForward =
		newBasis

	facingForward =
		newBasis

	character:SetAttribute(
		"SurfaceNormal",
		currentNormal
	)

	lostSurfaceTime =
		0

	local offset =
		getSurfaceOffset()

	local targetPosition =
		hit.Position
		+ newNormal * offset

	rootPart.CFrame =
		CFrame.new(
			targetPosition
		)
		* rootPart.CFrame.Rotation

	updateAlignOrientation()
	rebuildTargetCameraTransform()

	return true
end


-- =========================
-- ATTACH TO WATER
-- =========================

local function attachToWater(hit)
	if not isWaterHit(hit) then
		return false
	end

	stopSwimAnimations(0)

	if isTreeJumpActive()
		or isWaterCaptureBlockedByDash()
		or character:GetAttribute("WaterJumping") == true then

		return false
	end

	if not surfaceWalking then
		previousAutoRotate =
			humanoid.AutoRotate

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.FallingDown,
			false
		)

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Ragdoll,
			false
		)

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.GettingUp,
			false
		)

		humanoid.AutoRotate = false

		humanoid:ChangeState(
			Enum.HumanoidStateType.Physics
		)

		stopSwimAnimations(0)

		createSurfacePhysics()

		surfaceWalking = true

		character:SetAttribute(
			"SurfaceWalking",
			true
		)

		local heading =
			getWorldHorizontal(
				rootPart.CFrame.LookVector
			)

		if not heading then
			local camera = workspace.CurrentCamera

			if camera then
				heading =
					getWorldHorizontal(
						camera.CFrame.LookVector
					)
			end
		end

		virtualHeading =
			heading
			or Vector3.new(0, 0, -1)

		stopConflictingLocomotionAnimations()
	end

	waterWalking = true
	currentNormal = Vector3.yAxis

	if character:GetAttribute("IsDashing") == true
		and character:GetAttribute("AirDashCarryActive") == true then

		print(
			"[SurfaceController] AirDashCarry -> WaterWalk handoff",
			"yVel",
			string.format(
				"%.2f",
				rootPart.AssemblyLinearVelocity.Y
			)
		)
	end

	lastWaterFallApproachTime =
		-math.huge

	lastWaterFallApproachSurfaceY =
		nil

	local flatForward =
		getWorldHorizontal(
			facingForward
		)
		or getWorldHorizontal(
			rootPart.CFrame.LookVector
		)
		or Vector3.new(0, 0, -1)

	surfaceBasisForward = flatForward
	facingForward = flatForward

	character:SetAttribute(
		"WaterWalking",
		true
	)

	reportChakraFeetMode(
		"Water"
	)

	character:SetAttribute(
		"SurfaceNormal",
		Vector3.yAxis
	)

	lostSurfaceTime = 0

	local targetPosition = Vector3.new(
		rootPart.Position.X,
		hit.Position.Y + getSurfaceOffset(),
		rootPart.Position.Z
	)

	local oldVelocity =
		rootPart.AssemblyLinearVelocity

	rootPart.CFrame =
		CFrame.new(targetPosition)
		* rootPart.CFrame.Rotation

	rootPart.AssemblyLinearVelocity =
		Vector3.new(
			oldVelocity.X,
			0,
			oldVelocity.Z
		)

	updateAlignOrientation()
	rebuildTargetCameraTransform()

	return true
end

local function tryAttachToWater(deltaTime)
	if not chakraFeetActive
		or surfaceWalking
		or isTreeJumpActive()
		or isWaterCaptureBlockedByDash()
		or character:GetAttribute("WaterJumping") == true then

		return false
	end

	if time() - lastSurfaceJumpTime <
		SURFACE_JUMP_REATTACH_DELAY then

		return false
	end

	local state = humanoid:GetState()

	local floorMaterial =
		humanoid.FloorMaterial

	if floorMaterial ~= Enum.Material.Air
		and floorMaterial ~= Enum.Material.Water
		and state ~= Enum.HumanoidStateType.Swimming then

		return false
	end

	if state ~= Enum.HumanoidStateType.Swimming then

		rememberWaterApproachFromAbove(
			deltaTime
		)
	end

	local velocityY =
		rootPart.AssemblyLinearVelocity.Y

	local predictiveExtra =
		math.max(0, -velocityY)
		* deltaTime

	local belowHit =
		getWaterSurfaceBelow(predictiveExtra)

	if belowHit
		and (
			state == Enum.HumanoidStateType.Swimming
				or velocityY <= 1.5
		) then

		return attachToWater(belowHit)
	end

	if state == Enum.HumanoidStateType.Swimming then
		local surfaceHit =
			findWaterSurfaceWhileSwimming()

		if surfaceHit then
			local desiredRootY =
				surfaceHit.Position.Y
				+ getSurfaceOffset()

			local distanceToWalkingHeight =
				math.abs(
					desiredRootY
					- rootPart.Position.Y
				)

			local normalUnderwaterCapture =
				distanceToWalkingHeight <=
				WATER_UNDERWATER_CAPTURE_DISTANCE

			local recentFallEntry =
				time() - lastWaterFallApproachTime <=
				WATER_FALL_ENTRY_GRACE

			local sameApproachedSurface =
				lastWaterFallApproachSurfaceY ~= nil
				and math.abs(
					surfaceHit.Position.Y
					- lastWaterFallApproachSurfaceY
				) <= WATER_FALL_ENTRY_SURFACE_Y_TOLERANCE

			local fallEntryRecovery =
				recentFallEntry
				and sameApproachedSurface
				and distanceToWalkingHeight <=
				WATER_FALL_ENTRY_MAX_RECOVERY_DISTANCE

			if normalUnderwaterCapture
				or fallEntryRecovery then

				return attachToWater(surfaceHit)
			end
		end
	end

	return false
end


-- =========================
-- INITIAL WALL ATTACH
-- =========================

local function tryAttachFromNormalMovement()
	if not chakraFeetActive
		or surfaceWalking
		or isTreeJumpActive()
		or isStatusMovementBlocked()
		or character:GetAttribute(
			"IsDashing"
		)
			or character:GetAttribute(
				"SurfaceJumping"
			) then

		return
	end

	local currentState =
		humanoid:GetState()

	if currentState ==
		Enum.HumanoidStateType.Swimming
		or humanoid.FloorMaterial ==
		Enum.Material.Water then

		return
	end

	if time() -
		lastSurfaceJumpTime <
		SURFACE_JUMP_REATTACH_DELAY then

		return
	end

	if not UserInputService:IsKeyDown(
		Enum.KeyCode.W
		) then

		return
	end

	local moveDirection =
		humanoid.MoveDirection

	if moveDirection.Magnitude < 0.05 then
		return
	end

	moveDirection =
		moveDirection.Unit

	local hit =
		workspace:Spherecast(
			rootPart.Position,
			SURFACE_CAST_RADIUS,
			moveDirection
			* ATTACH_PROBE_DISTANCE,
			surfaceParams
		)

	if not hit then
		return
	end

	if not isValidSolidSurfaceHit(
		hit
		) then
		return
	end

	if not isMeaningfulInitialWall(
		hit
		) then

		return
	end

	if moveDirection:Dot(
		-hit.Normal
		) < 0.20 then

		return
	end

	if isUpwardSurfaceTooFlat(
		hit.Normal
		) then

		return
	end

	attachToSurface(
		hit,
		"Attach"
	)
end


-- =========================
-- SURFACE PROBES
-- =========================

local function getCurrentSurfaceHit()
	local distance =
		getSurfaceOffset()
		+ SURFACE_CHECK_EXTRA_DISTANCE

	if waterWalking then
		return directWaterRaycast(
			rootPart.Position,
			-Vector3.yAxis * distance
		)
	end

	return spherecastIgnoringSmallDetails(
		rootPart.Position,
		SURFACE_CAST_RADIUS,
		-currentNormal * distance
	)
end


-- =========================
-- SURFACE DISTANCE CORRECTION
-- =========================

local function getSurfaceCorrectionVelocity(currentHit)
	if waterWalking then
		if not currentHit then
			return Vector3.zero
		end

		local desiredDistance =
			getSurfaceOffset()

		local actualDistance =
			(rootPart.Position - currentHit.Position):
			Dot(Vector3.yAxis)

		local error =
			desiredDistance
		- actualDistance

		if math.abs(error) <=
			WATER_HEIGHT_DEADZONE then

			return Vector3.zero
		end

		local correctionSpeed =
			math.clamp(
				error * WATER_HEIGHT_RESPONSE,
				-WATER_MAX_HEIGHT_CORRECTION_SPEED,
				WATER_MAX_HEIGHT_CORRECTION_SPEED
			)

		return Vector3.yAxis
			* correctionSpeed
	end

	if not currentHit then
		return -currentNormal * SURFACE_STICK_BIAS
	end

	local desiredDistance =
		getSurfaceOffset()

	local actualDistance =
		(rootPart.Position - currentHit.Position):Dot(currentNormal)

	local error =
		desiredDistance - actualDistance

	local correctionSpeed =
		math.clamp(
			error * SURFACE_DISTANCE_RESPONSE,
			-MAX_SURFACE_CORRECTION_SPEED,
			MAX_SURFACE_CORRECTION_SPEED
		)

	if math.abs(error) <=
		SURFACE_DISTANCE_DEADZONE then

		correctionSpeed =
			-SURFACE_STICK_BIAS
	end

	return currentNormal * correctionSpeed
end

local function findConcaveTransition(
	moveDirection
)
	if moveDirection.Magnitude < 0.05 then
		return nil
	end

	local hit =
		spherecastIgnoringSmallDetails(
			rootPart.Position,
			SURFACE_CAST_RADIUS,
			moveDirection
			* CONCAVE_PROBE_DISTANCE
		)

	if not hit then
		return nil
	end

	if not isValidSolidSurfaceHit(
		hit
		) then

		return nil
	end

	local normalDifference =
		currentNormal:Dot(
			hit.Normal
		)

	if normalDifference > 0.94 then
		return nil
	end

	if moveDirection:Dot(
		-hit.Normal
		) < 0.15 then

		return nil
	end

	return hit
end

local function findConvexTransition(
	moveDirection
)
	if moveDirection.Magnitude < 0.05 then
		return nil
	end

	local offset =
		getSurfaceOffset()

	local probeOrigin =
		rootPart.Position
		+ moveDirection
		* (
			offset
			+ CONVEX_FORWARD_EXTRA
		)
	- currentNormal
		* (
			offset
			+ CONVEX_INSET_EXTRA
		)

	local castDistance =
		(offset * 2)
		+ CONVEX_CAST_EXTRA

	local hit =
		spherecastIgnoringSmallDetails(
			probeOrigin,
			SURFACE_CAST_RADIUS,
			-moveDirection
			* castDistance
		)

	if not hit then
		return nil
	end

	if not isValidSolidSurfaceHit(
		hit
		) then

		return nil
	end

	if hit.Normal:Dot(
		moveDirection
		) < 0.20 then

		return nil
	end

	if currentNormal:Dot(
		hit.Normal
		) > 0.94 then

		return nil
	end

	return hit
end


-- =========================
-- CURVED SURFACE FOLLOW
-- =========================

local function followCurrentSurface(
	hit,
	deltaTime
)
	if not hit then
		return
	end

	if waterWalking then
		currentNormal = Vector3.yAxis

		character:SetAttribute(
			"SurfaceNormal",
			Vector3.yAxis
		)

		return
	end

	local newNormal =
		hit.Normal.Unit

	if isUpwardSurfaceTooFlat(
		newNormal
		) then

		return "Ground"
	end

	local dot =
		currentNormal:Dot(
			newNormal
		)

	if dot < 0.65 then
		return
	end

	if dot < 0.999 then
		local oldNormal =
			currentNormal

		local alpha =
			math.clamp(
				deltaTime
				* NORMAL_FOLLOW_SPEED,
				0,
				1
			)

		currentNormal =
			currentNormal:Lerp(
				newNormal,
				alpha
			).Unit

		surfaceBasisForward =
			getTransportedForward(
				surfaceBasisForward,
				oldNormal,
				currentNormal,
				"Curve"
			)

		facingForward =
			getTransportedForward(
				facingForward,
				oldNormal,
				currentNormal,
				"Curve"
			)

		character:SetAttribute(
			"SurfaceNormal",
			currentNormal
		)
	end

	return "Surface"
end



local function isDownedSystemLocked(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
end

local function isChakraSuppressed(): boolean
	return character:GetAttribute(
		"Status_ChakraSuppressed"
	) == true
end

-- =========================
-- CHAKRA FEET TOGGLE
-- =========================

local function setChakraFeetActive(active)
	chakraFeetActive =
		active

	character:SetAttribute(
		"ChakraFeetActive",
		active
	)

	if not active
		and surfaceWalking then

		releaseSurface(false)
	end
end

local function toggleChakraFeet()
	if isDownedSystemLocked() then
		return
	end

	if isChakraSuppressed() then
		if chakraFeetActive then
			setChakraFeetActive(false)
			reportChakraFeetMode("Off")
		end

		return
	end

	if character:GetAttribute(
		"ChakraCharging"
		) == true then

		return
	end

	if not chakraFeetActive then
		if character:GetAttribute(
			"ChakraSystemReady"
			) ~= true then

			return
		end

		local currentChakra =
			character:GetAttribute(
				"Chakra"
			)

		if typeof(currentChakra) ~= "number"
			or currentChakra <= 0 then

			return
		end
	end

	setChakraFeetActive(
		not chakraFeetActive
	)

	print(
		"[SurfaceController] Chakra Feet:",
		chakraFeetActive
			and "ON"
			or "OFF"
	)
end


local function handleDownedIntegrationState()
	if isDownedSystemLocked() then
		setChakraFeetActive(false)

		character:SetAttribute(
			"SurfaceJumping",
			false
		)

		character:SetAttribute(
			"WaterJumping",
			false
		)
	end
end

for _, attributeName in ipairs({
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsExecuting",
	}) do
	character:GetAttributeChangedSignal(attributeName):Connect(
		handleDownedIntegrationState
	)
end


local function handleChakraSuppressionState()
	if not isChakraSuppressed() then
		return
	end

	-- Suppression removes Chakra Feet itself, not only the current attachment.
	-- Existing releaseSurface() cleanup handles Surface/Water walking safely.
	setChakraFeetActive(false)
	reportChakraFeetMode("Off")

	lastCPressTime =
		-math.huge

	cPressStartedAt =
		-math.huge
end

character:
	GetAttributeChangedSignal(
		"Status_ChakraSuppressed"
	):
	Connect(handleChakraSuppressionState)

handleChakraSuppressionState()


-- =========================
-- CHAKRA RESOURCE HANDOFF
-- =========================

local function handleChakraResourceState()
	local currentChakra =
		character:GetAttribute(
			"Chakra"
		)

	local empty =
		typeof(currentChakra) == "number"
		and currentChakra <= 0

	local exhausted =
		character:GetAttribute(
			"ChakraExhausted"
		) == true

	if empty
		or exhausted then

		setChakraFeetActive(false)
		reportChakraFeetMode("Off")
	end
end

character:
	GetAttributeChangedSignal(
		"Chakra"
	):
	Connect(handleChakraResourceState)

character:
	GetAttributeChangedSignal(
		"ChakraExhausted"
	):
	Connect(handleChakraResourceState)

character:
	GetAttributeChangedSignal(
		"ChakraCharging"
	):
	Connect(handleChakraResourceState)


-- =========================
-- INPUT
-- =========================

UserInputService.InputBegan:Connect(
	function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode ~=
			CHAKRA_FEET_KEY then

			return
		end

		if isChakraSuppressed() then
			lastCPressTime =
				-math.huge

			cPressStartedAt =
				-math.huge

			return
		end

		cPressStartedAt =
			time()
	end
)


UserInputService.InputEnded:Connect(
	function(input)
		if input.KeyCode ~=
			CHAKRA_FEET_KEY then

			return
		end

		if isChakraSuppressed() then
			lastCPressTime =
				-math.huge

			cPressStartedAt =
				-math.huge

			return
		end

		local releasedAt =
			time()

		local pressDuration =
			releasedAt
		- cPressStartedAt

		cPressStartedAt =
			-math.huge

		if pressDuration < 0
			or pressDuration >
			CHAKRA_FEET_TAP_MAX_DURATION then

			lastCPressTime =
				-math.huge

			return
		end

		if releasedAt - lastCPressTime <=
			DOUBLE_C_WINDOW then

			lastCPressTime =
				-math.huge

			toggleChakraFeet()
		else
			lastCPressTime =
				releasedAt
		end
	end
)


-- =========================
-- ATTRIBUTE HANDOFFS
-- =========================

character:GetAttributeChangedSignal(
	"SurfaceJumping"
):Connect(
	function()
		if character:GetAttribute(
			"SurfaceJumping"
			) == true then

			lastSurfaceJumpTime =
				time()

			if surfaceWalking then

				local cleanWaterJumpHandoff =
					waterWalking
					and character:GetAttribute(
						"WaterJumping"
					) == true

				releaseSurface(
					cleanWaterJumpHandoff
				)
			end
		end
	end
)

local function handleTreeJumpState()
	if isTreeJumpActive() then
		if surfaceWalking then
			releaseSurface(true)
		end
	else
		if not surfaceWalking
			and not character:GetAttribute(
				"IsDashing"
			) then

			local combatMode =
				character:GetAttribute(
					"CombatMode"
				) == true

			humanoid.AutoRotate =
				not combatMode
		end
	end
end

character:GetAttributeChangedSignal(
	"TreeJumpActive"
):Connect(
	handleTreeJumpState
)

character:GetAttributeChangedSignal(
	"IsTreeJumping"
):Connect(
	handleTreeJumpState
)


-- =========================
-- COMBAT MODE HANDOFF
-- =========================

character:GetAttributeChangedSignal(
	"CombatMode"
):Connect(
	function()

		if character:GetAttribute(
			"CombatMode"
			) == true then

			return
		end

		if not surfaceWalking
			or character:GetAttribute(
				"IsDashing"
			) == true then

			return
		end

		local moveDirection =
			getSurfaceInputDirection()

		if moveDirection.Magnitude >
			0.05 then

			facingForward =
				moveDirection

			updateAlignOrientation()

		end

	end
)


-- =========================
-- MAIN PHYSICS LOOP
-- =========================

RunService.PreSimulation:Connect(
	function(deltaTime)
		if humanoid.Health <= 0 then
			return
		end

		if not chakraFeetActive then
			return
		end

		if isChakraSuppressed() then
			setChakraFeetActive(false)
			reportChakraFeetMode("Off")
			return
		end

		if isTreeJumpActive() then
			return
		end

		if not surfaceWalking then
			if tryAttachToWater(deltaTime) then
				return
			end

			tryAttachFromNormalMovement()
			return
		end

		if character:GetAttribute(
			"SurfaceJumping"
			) then

			releaseSurface(false)
			return
		end

		if humanoid:GetState() ~=
			Enum.HumanoidStateType.Physics then

			humanoid:ChangeState(
				Enum.HumanoidStateType.Physics
			)
		end

		humanoid.AutoRotate =
			false

		humanoid.Jump =
			false

		if gravityCancelForce then
			gravityCancelForce.Force =
				Vector3.yAxis
				* rootPart.AssemblyMass
				* workspace.Gravity
		end

		local moveDirection =
			getSurfaceInputDirection()

		local chakraCharging =
			character:GetAttribute(
				"ChakraCharging"
			) == true

		if chakraCharging then
			moveDirection =
				Vector3.zero
		end

		local isDashing =
			character:GetAttribute(
				"IsDashing"
			) == true
			and not isStatusMovementBlocked()

		if waterWalking
			and isDashing
			and rootPart.AssemblyLinearVelocity.Y > 1 then

			releaseSurface(false)

			humanoid:ChangeState(
				Enum.HumanoidStateType.Freefall
			)

			return
		end

		local transitionDirection =
			moveDirection

		if isDashing then
			local dashTangent =
				projectOnPlane(
					rootPart.AssemblyLinearVelocity,
					currentNormal
				)

			if dashTangent.Magnitude > 0.05 then
				transitionDirection =
					dashTangent.Unit
			end
		end

		if transitionDirection.Magnitude > 0.05 then
			local concaveHit =
				findConcaveTransition(
					transitionDirection
				)

			if concaveHit then
				attachToSurface(
					concaveHit,
					"Concave"
				)
			end
		end

		local currentHit =
			getCurrentSurfaceHit()

		if currentHit then
			lostSurfaceTime =
				0

			local followResult =
				followCurrentSurface(
					currentHit,
					deltaTime
				)

			if followResult ==
				"Ground" then

				attachToSurface(
					currentHit,
					"Curve"
				)

				return
			end
		else
			local convexHit = nil

			if transitionDirection.Magnitude >
				0.05 then

				convexHit =
					findConvexTransition(
						transitionDirection
					)
			end

			if convexHit then
				attachToSurface(
					convexHit,
					"Convex"
				)

				currentHit =
					convexHit

				lostSurfaceTime =
					0
			else
				lostSurfaceTime +=
					deltaTime

				if lostSurfaceTime >=
					LOST_SURFACE_GRACE then

					releaseSurface(false)
					return
				end
			end
		end

		moveDirection =
			getSurfaceInputDirection()

		if chakraCharging then
			moveDirection =
				Vector3.zero
		end

		local moving =
			moveDirection.Magnitude > 0.05

		character:SetAttribute(
			"SurfaceMoving",
			moving
		)

		character:SetAttribute(
			"SurfaceMoveDirection",
			moving
				and moveDirection
				or Vector3.zero
		)

		if isDashing then
			local dashFacing =
				character:GetAttribute(
					"SurfaceDashFacingDirection"
				)

			if typeof(dashFacing) ==
				"Vector3"
				and dashFacing.Magnitude >
				0.05 then

				local projectedDashFacing =
					projectOnPlane(
						dashFacing,
						currentNormal
					)

				if projectedDashFacing.Magnitude >
					0.05 then

					facingForward =
						projectedDashFacing.Unit
				end
			end

		elseif character:GetAttribute(
			"CombatMode"
			) == true
				and character:GetAttribute(
					"CombatSuppressed"
				) ~= true then

			local cameraForward =
				getCameraForwardOnSurface()

			if cameraForward.Magnitude >
				0.05 then

				facingForward =
					cameraForward
			end

		elseif moving then

			facingForward =
				moveDirection
		end

		updateAlignOrientation()
		rebuildTargetCameraTransform()

		local surfaceCorrectionVelocity =
			getSurfaceCorrectionVelocity(
				currentHit
			)

		if isDashing then
			local velocity =
				rootPart.AssemblyLinearVelocity

			local tangentVelocity =
				projectOnPlane(
					velocity,
					currentNormal
				)

			rootPart.AssemblyLinearVelocity =
				tangentVelocity
				+ surfaceCorrectionVelocity
		else
			local speed =
				humanoid.WalkSpeed

			local tangentVelocity =
				moving
				and (
					moveDirection
					* speed
				)
				or Vector3.zero

			rootPart.AssemblyLinearVelocity =
				tangentVelocity
				+ surfaceCorrectionVelocity
		end

		updateSurfaceAnimation(
			moving
		)
	end
)


-- =========================
-- POST-PHYSICS WATER FOOT SWEEP
-- =========================

RunService.PostSimulation:Connect(
	function()

		local currentProbe =
			getWaterFootProbePosition()

		local previousProbe =
			previousWaterFootProbePosition

		previousWaterFootProbePosition =
			currentProbe

		if not previousProbe then
			return
		end

		if humanoid.Health <= 0
			or not chakraFeetActive
			or surfaceWalking
			or isTreeJumpActive()
			or isWaterCaptureBlockedByDash()
			or character:GetAttribute(
				"WaterJumping"
			) == true then

			return
		end

		if time() - lastSurfaceJumpTime <
			SURFACE_JUMP_REATTACH_DELAY then

			return
		end

		local sweepVector =
			currentProbe - previousProbe

		if sweepVector.Magnitude <
			WATER_SWEEP_MIN_DISTANCE then

			return
		end

		local sweepHit =
			directWaterRaycast(
				previousProbe,
				sweepVector
			)

		if not sweepHit then
			return
		end

		local surfaceHit =
			getWaterSurfaceAtWorldPoint(
				sweepHit.Position
			)

		if not surfaceHit then
			return
		end

		local previousWasAboveSurface =
			previousProbe.Y >=
			surfaceHit.Position.Y
		- WATER_SWEEP_ABOVE_TOLERANCE

		if not previousWasAboveSurface then
			return
		end

		if attachToWater(
			surfaceHit
			) then

			previousWaterFootProbePosition =
				getWaterFootProbePosition()

		end

	end
)


-- =========================
-- DEATH / CLEANUP
-- =========================

humanoid.Died:Connect(
	function()
		stopSurfaceAnimations(0)
		destroySurfacePhysics()

		surfaceWalking =
			false

		waterWalking =
			false

		previousWaterFootProbePosition =
			nil

		character:SetAttribute(
			"SurfaceWalking",
			false
		)

		character:SetAttribute(
			"WaterWalking",
			false
		)
	end
)

script.Destroying:Connect(
	function()
		RunService:UnbindFromRenderStep(
			CAMERA_PRE_BIND
		)

		RunService:UnbindFromRenderStep(
			CAMERA_POST_BIND
		)

		stopSurfaceAnimations(0)
		destroySurfacePhysics()
	end
)


print(
	"[SurfaceController] READY v3.4.4 DB_CCLCleanupOnly + ChakraSuppression + StatusStunOnly + AirDashWaterLandingHandoff"
		.. " | ChakraResource=ON"
		.. " | ServerFeetReporting=ON"
		.. " | DoubleTapC=Feet"
		.. " | HoldC=Charge"
		.. " | ChargeKeepsFeet=ON"
		.. " | SmoothWater=ON"
		.. " | AirDashWaterLanding=ON"
		.. " | DirectionalRun=Forward/Left/Right"
		.. " | BackwardRun=OFF"
		.. " | SprintAuthority=IsSprinting"
		.. " | TripStatesRestore=NORMAL_AFTER_SURFACE"
		.. " | StatusStun=ZERO_TANGENT_ONLY"
		.. " | ChakraSuppression=FEET_FORCED_OFF"
)
