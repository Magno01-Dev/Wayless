-- TreeJumpController - Stable + LeftAlt + No Swimming
--
-- El jugador apunta libremente a un �rbol.
-- De ese �rbol elegimos la rama v�lida m�s
-- cercana al cursor.
--
-- NO existen rutas predefinidas.
--
-- La rama actual se excluye comparando
-- la INSTANCIA exacta, no su nombre.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WindTrail = require(ReplicatedStorage:WaitForChild("WindTrail"))


-- =========================
-- PLAYER / CHARACTER
-- =========================

local player =
	Players.LocalPlayer


local character =
	script.Parent


local humanoid =
	character:WaitForChild("Humanoid")


local rootPart =
	character:WaitForChild(
		"HumanoidRootPart"
	)


-- =========================
-- REFERENCES
-- =========================

local TREE_FOLDER =
	workspace:WaitForChild("Arboles")


local requestEvent =
	ReplicatedStorage:WaitForChild(
		"TreeJumpRequest"
	)


local approvedEvent =
	ReplicatedStorage:WaitForChild(
		"TreeJumpApproved"
	)


local replicateEvent =
	ReplicatedStorage:WaitForChild(
		"TreeJumpReplicate"
	)


-- =========================
-- INPUT
-- =========================

local TREE_JUMP_KEY =
	Enum.KeyCode.LeftAlt


local TREE_JUMP_COOLDOWN =
	0.15


-- =========================
-- TREE JUMP FOV (isolated)
-- =========================
-- Aumenta ligeramente el FOV SOLO durante Tree Jump para
-- dar sensaci�n de velocidad. No toca el FOV base del juego
-- ni los dem�s sistemas (sprint, dash, combate, etc.).
-- Se guarda el FOV previo y se restaura al terminar, as�
-- convive con cualquier otro sistema de FOV activo.

local TweenService =
	game:GetService("TweenService")


local TREE_JUMP_FOV_BONUS =
	25  -- grados extra durante Tree Jump (rango 5-8)


local TREE_JUMP_FOV_TIME =
	0.2  -- segundos de transici�n suave


local treeJumpFovTween =
	nil


local treeJumpFovWasActive =
	false  -- evita apilar/duplicar el efecto


local treeJumpPreviousFov =
	nil  -- FOV exacto existente justo antes de Tree Jump


local function startTreeJumpFov()

	if treeJumpFovWasActive then
		return  -- ya est� activo; no apilar
	end

	local camera =
		workspace.CurrentCamera

	if not camera then
		return
	end

	treeJumpPreviousFov =
		camera.FieldOfView

	treeJumpFovWasActive =
		true

	if treeJumpFovTween then
		treeJumpFovTween:Cancel()
	end

	treeJumpFovTween =
		TweenService:Create(
			camera,
			TweenInfo.new(
				TREE_JUMP_FOV_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				FieldOfView =
				treeJumpPreviousFov +
				TREE_JUMP_FOV_BONUS
			}
		)

	treeJumpFovTween:Play()

end


local function stopTreeJumpFov()

	if not treeJumpFovWasActive then
		return
	end

	local camera =
		workspace.CurrentCamera

	treeJumpFovWasActive =
		false

	if camera then

		if treeJumpFovTween then
			treeJumpFovTween:Cancel()
		end

		local restoreFov =
			treeJumpPreviousFov or camera.FieldOfView

		treeJumpFovTween =
			TweenService:Create(
				camera,
				TweenInfo.new(
					TREE_JUMP_FOV_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					FieldOfView = restoreFov
				}
			)

		treeJumpFovTween:Play()

	end

	treeJumpPreviousFov =
		nil

end


-- TREE JUMP DEPTH OF FIELD (isolated)
-- =========================
-- Efecto de profundidad de campo (DepthOfFieldEffect en Lighting)
-- EXCLUSIVO de Tree Jump. Mantiene una zona nitida central (radio
-- modificable via TREE_JUMP_DOF_IN_FOCUS_RADIUS) y desenfoca los
-- alrededores para simular la sensacion de aceleracion hacia adelante.
-- Se sincroniza con el FOV y no toca otros sistemas de post-procesado.
-- NOTA: Roblox no tiene blur radial con centro en post-procesado; este
-- enfoque usa DOF (n�tido por distancia de camara, no radial perfecto).
local Lighting =
	game:GetService("Lighting")


local TREE_JUMP_DOF_FOCUS_DISTANCE =
	15  -- distancia de la banda nitida (studs)


local TREE_JUMP_DOF_IN_FOCUS_RADIUS =
	25  -- radio de la zona nitida central (MODIFICABLE: "radio en el centro")


local TREE_JUMP_DOF_INTENSITY =
	0.2  -- intensidad de desenfoque cerca/lejos (aprox 0-1)


local TREE_JUMP_DOF_RISE_TIME =
	0.1  -- subida rapida al inicio del Tree Jump


local TREE_JUMP_DOF_FALL_TIME =
	0.25  -- bajada suave al terminar


local treeJumpDofEffect =
	nil


local treeJumpDofTween =
	nil


local treeJumpDofWasActive =
	false  -- evita apilar/duplicar el efecto


local function getTreeJumpDofEffect()

	if treeJumpDofEffect and treeJumpDofEffect.Parent then
		return treeJumpDofEffect
	end

	local effect =
		Instance.new("DepthOfFieldEffect")

	effect.Name =
		"TreeJumpDepthOfField"

	effect.FocusDistance =
		TREE_JUMP_DOF_FOCUS_DISTANCE

	effect.InFocusRadius =
		TREE_JUMP_DOF_IN_FOCUS_RADIUS

	effect.NearIntensity =
		0

	effect.FarIntensity =
		0

	effect.Enabled =
		true

	effect.Parent =
		Lighting

	treeJumpDofEffect =
		effect

	return effect

end


local function startTreeJumpDof()

	if treeJumpDofWasActive then
		return  -- ya esta activo; no apilar
	end

	local effect =
		getTreeJumpDofEffect()

	treeJumpDofWasActive =
		true

	if treeJumpDofTween then
		treeJumpDofTween:Cancel()
	end

	-- InFocusRadius (radio central) queda fijo; se anima la intensidad.
	treeJumpDofTween =
		TweenService:Create(
			effect,
			TweenInfo.new(
				TREE_JUMP_DOF_RISE_TIME,
				Enum.EasingStyle.Exponential,
				Enum.EasingDirection.Out
			),
			{
				NearIntensity = TREE_JUMP_DOF_INTENSITY,
				FarIntensity = TREE_JUMP_DOF_INTENSITY,
			}
		)

	treeJumpDofTween:Play()

end


local function stopTreeJumpDof()

	if not treeJumpDofWasActive then
		return
	end

	local effect =
		treeJumpDofEffect

	treeJumpDofWasActive =
		false

	if not effect or not effect.Parent then
		return
	end

	if treeJumpDofTween then
		treeJumpDofTween:Cancel()
	end

	treeJumpDofTween =
		TweenService:Create(
			effect,
			TweenInfo.new(
				TREE_JUMP_DOF_FALL_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				NearIntensity = 0,
				FarIntensity = 0,
			}
		)

	treeJumpDofTween:Play()

end
-- (VFX de viento ahora vive en ReplicatedStorage.WindTrail, compartido
-- con DashController. Ver WindTrail.start / WindTrail.stop abajo.)
-- con DashController. Ver WindTrail.start / WindTrail.stop abajo.)




local function spawnWindStreak(gui: BillboardGui, moveDir: Vector3, root: BasePart)

	local dir =
		moveDir.Magnitude > 0.01 and moveDir.Unit or root.CFrame.LookVector

	local camera =
		workspace.CurrentCamera

	if not camera then
		return
	end

	-- Punto base: alrededor de los lados y atras del personaje.
	local side =
		math.random() < 0.5 and -1 or 1

	local lateral =
		side * (1.2 + math.random() * 3.8)

	-- Sesgo hacia atras (contra la direccion de movimiento).
	local back =
		-WIND_STREAK_BACK_BIAS * (0.4 + math.random() * 0.9)

	local right =
		root.CFrame.RightVector

	local fwd =
		root.CFrame.LookVector

	local worldPos =
		root.Position
		+ right * lateral
		+ fwd * back
		+ Vector3.new(0, -1.2 + math.random() * 3.2, 0)

	-- Proyecta mundo -> pantalla y lo ancla al BillboardGui (siempre
	-- enfrentando la camara), asi la estela queda alrededor del personaje.
	local rootScreen =
		camera:WorldToScreenPoint(root.Position)

	local streakScreen =
		camera:WorldToScreenPoint(worldPos)

	local cx =
		streakScreen.X - rootScreen.X

	local cy =
		streakScreen.Y - rootScreen.Y

	-- Direccion de retroceso en pantalla (contra el movimiento).
	local behindScreen =
		camera:WorldToScreenPoint(root.Position - dir)

	local backX =
		behindScreen.X - rootScreen.X

	local backY =
		behindScreen.Y - rootScreen.Y

	local backLen =
		math.sqrt(backX * backX + backY * backY)

	if backLen < 0.001 then
		backX = 0
		backY = -1
		backLen = 1
	end

	backX = backX / backLen
	backY = backY / backLen

	local length =
		WIND_STREAK_LENGTH[1] +
		math.random() * (WIND_STREAK_LENGTH[2] - WIND_STREAK_LENGTH[1])

	local thickness =
		WIND_STREAK_THICKNESS[1] +
		math.random() * (WIND_STREAK_THICKNESS[2] - WIND_STREAK_THICKNESS[1])

	local line =
		Instance.new("ImageLabel")

	line.Name =
		"WindStreak"

	line.BackgroundColor3 =
		WIND_STREAK_COLOR

	line.BackgroundTransparency =
		1 - WIND_STREAK_ALPHA

	line.BorderSizePixel =
		0

	line.Size =
		UDim2.fromOffset(math.max(2, length * 28), thickness)

	line.Position =
		UDim2.new(0.5, cx, 0.5, cy)

	-- Rotacion: levemente angulada respecto al movimiento.
	line.Rotation =
		(8 + math.random() * 22) * (math.random() < 0.5 and -1 or 1)

	line.AnchorPoint =
		Vector2.new(0.5, 0.5)

	line.ZIndex =
		2

	line.Parent =
		gui

	-- Deriva hacia atras (contra el movimiento) durante su vida.
	local driftDir =
		-dir

	local life =
		WIND_STREAK_LIFETIME[1] +
		math.random() * (WIND_STREAK_LIFETIME[2] - WIND_STREAK_LIFETIME[1])

	local tweenInfo =
		TweenInfo.new(
			life,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		)

	local fade =
		TweenService:Create(
			line,
			TweenInfo.new(WIND_STREAK_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 - WIND_STREAK_ALPHA }
		)

	fade:Play()

	local driftPx =
		40 + math.random() * 50

	local drift =
		TweenService:Create(
			line,
			tweenInfo,
			{
				Position = UDim2.new(
					0.5,
					cx + backX * driftPx,
					0.5,
					cy + backY * driftPx
				),
				BackgroundTransparency = 1,
			}
		)

	drift:Play()

	drift.Completed:Once(function()
		line:Destroy()
	end)

end


local function startTreeJumpWind()

	if not ENABLE_TREE_JUMP_WIND then
		return
	end

	if windHeartbeatConn then
		return
	end

	if not rootPart.Parent then
		return
	end

	windGui =
		createWindBillboard(rootPart)

	windHeartbeatConn =
		RunService.Heartbeat:Connect(function()

			if not windGui or not windGui.Parent then
				return
			end

			local moveDir =
			rootPart.AssemblyLinearVelocity

			for _ = 1, math.random(WIND_STREAKS_PER_TICK[1], WIND_STREAKS_PER_TICK[2]) do
				spawnWindStreak(windGui, moveDir, rootPart)
			end

		end)

end


local function stopTreeJumpWind()

	if windHeartbeatConn then
		windHeartbeatConn:Disconnect()
		windHeartbeatConn = nil
	end

	-- Las estelas vivas se desvanecen solas (no se borran de golpe).
	if windGui then
		local gui = windGui
		windGui = nil
		task.delay(0.6, function()
			if gui and gui.Parent then
				gui:Destroy()
			end
		end)
	end

end


-- =========================
-- TARGET SETTINGS
-- =========================

local MAX_DISTANCE = 250
local MIN_DISTANCE = 4


-- No permitir saltar a la rama en la que ya
-- estamos parados (o muy cerca). Debe coincidir
-- con el guard del servidor (distancia < 5).
local SAME_BRANCH_THRESHOLD =
	5


local CURSOR_SCREEN_TOLERANCE =
	300


local EXTERNAL_BLOCK_TOLERANCE =
	5


local TREE_JUMP_DISTANCE_OFFSET =
	3


local CURRENT_BRANCH_RAY_DISTANCE =
	6


-- =========================
-- DEBUG
-- =========================

local DEBUG_TREE_JUMP =
	false


-- =========================
-- SOUND EFFECTS
-- =========================

local ENABLE_TREE_JUMP_SOUND = false

local TREE_JUMP_SOUND_JUMP_ID = "97148318607493"  -- jump_whoosh_01
local TREE_JUMP_SOUND_LAND_ID = "126830394849063"  -- Stomp1 (aterrizaje)

local function playTreeJumpSound(soundId)
	if not ENABLE_TREE_JUMP_SOUND then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = 0.6
	-- 2D (no posicional): el sonido no se aten�a ni
	-- "queda atrasado" en saltos largos/altos.
	sound.Parent = player.PlayerGui
	sound:Play()

	sound.Ended:Once(function()
		sound:Destroy()
	end)
end


-- =========================
-- WOOD PARTICLES (VISUAL EFFECT)
-- =========================

local ENABLE_TREE_JUMP_WOOD_PARTICLES = false

local WOOD_CHIP_COUNT = 22
local WOOD_DUST_COUNT = 18
local PARTICLE_LIFETIME_MIN = 0.4
local PARTICLE_LIFETIME_MAX = 0.9

-- Map: character -> { chipEmitters, dustEmitters }
local particleEmittersByCharacter = {}

local function findFeet(character: Instance): { Instance }
	local feet = {}

	for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
		local foot = character:FindFirstChild(name, true)
		if foot and foot:IsA("BasePart") then
			table.insert(feet, foot)
		end
	end

	if #feet == 2 then
		return feet
	end

	-- R6 fallback
	feet = {}
	for _, name in ipairs({ "Left Leg", "Right Leg" }) do
		local part = character:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			table.insert(feet, part)
		end
	end

	if #feet > 0 then
		return feet
	end

	-- Ultimate fallback
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return { hrp }
	end

	return {}
end

local function createWoodParticleEmitters(character: Instance): { Instance }
	local woodChipProps = {
		Rate = 0,
		Enabled = false,
		EmissionDirection = Enum.NormalId.Back,
		SpreadAngle = Vector2.new(50, 35),
		Speed = NumberRange.new(12, 30),
		Lifetime = NumberRange.new(PARTICLE_LIFETIME_MIN, PARTICLE_LIFETIME_MAX),
		Acceleration = Vector3.new(0, -20, 0),
		Drag = 2,
		LightEmission = 0.15,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.4, 0.45),
			NumberSequenceKeypoint.new(1, 0.05),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-540, 540),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(160, 100, 50)),
	}

	local woodDustProps = {
		Rate = 0,
		Enabled = false,
		EmissionDirection = Enum.NormalId.Back,
		SpreadAngle = Vector2.new(70, 50),
		Speed = NumberRange.new(4, 16),
		Lifetime = NumberRange.new(PARTICLE_LIFETIME_MIN, PARTICLE_LIFETIME_MAX),
		Acceleration = Vector3.new(0, -8, 0),
		Drag = 1,
		LightEmission = 0.8,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 0.02),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(200, 160, 100)),
	}

	local feet = findFeet(character)
	local emitters = {}

	for _, foot in ipairs(feet) do
		local chipAttach = Instance.new("Attachment")
		chipAttach.Name = "TreeJumpChipAttach"
		chipAttach.Parent = foot

		local chipEmitter = Instance.new("ParticleEmitter")
		for prop, value in pairs(woodChipProps) do
			(chipEmitter :: any)[prop] = value
		end
		chipEmitter.Name = "TreeJumpChipEmitter"
		chipEmitter.Parent = chipAttach

		local dustAttach = Instance.new("Attachment")
		dustAttach.Name = "TreeJumpDustAttach"
		dustAttach.Parent = foot

		local dustEmitter = Instance.new("ParticleEmitter")
		for prop, value in pairs(woodDustProps) do
			(dustEmitter :: any)[prop] = value
		end
		dustEmitter.Name = "TreeJumpDustEmitter"
		dustEmitter.Parent = dustAttach

		table.insert(emitters, {
			chip = chipEmitter,
			dust = dustEmitter,
		})
	end

	return emitters
end

local function getOrCreateEmitters(character: Instance): { Instance }
	if not character or not character.Parent then
		return {}
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return {}
	end

	if particleEmittersByCharacter[character] ~= nil then
		return particleEmittersByCharacter[character]
	end

	local emitters = createWoodParticleEmitters(character)
	particleEmittersByCharacter[character] = emitters

	return emitters
end

local function playTreeJumpWoodParticles(character: Instance)
	if not ENABLE_TREE_JUMP_WOOD_PARTICLES then
		return
	end

	local emitters = getOrCreateEmitters(character)

	for _, pair in ipairs(emitters) do
		if pair.chip and pair.chip.Parent then
			(pair.chip :: ParticleEmitter):Emit(WOOD_CHIP_COUNT)
		end
		if pair.dust and pair.dust.Parent then
			(pair.dust :: ParticleEmitter):Emit(WOOD_DUST_COUNT)
		end
	end
end

local function cleanupParticleEmitters(character: Instance)
	local stored = particleEmittersByCharacter[character]
	if not stored then
		return
	end

	for _, pair in ipairs(stored) do
		if pair.chip then
			(pair.chip :: Instance):Destroy()
		end
		if pair.dust then
			(pair.dust :: Instance):Destroy()
		end
		local attach = pair.chip and pair.chip.Parent
		if attach and attach:IsA("Attachment") then
			attach:Destroy()
		end
	end

	particleEmittersByCharacter[character] = nil
end


-- =========================
-- VALID BRANCHES
-- =========================

local BRANCH_NAMES = {

	Branch_EA = true,
	Branch_NE = true,
	Branch_SW = true,
	Branch_WE = true,

}


-- Devuelve true SOLO para las cuatro ramas validas.
-- Nunca Trunk, Canopy, hojas ni otra pieza.
local function isValidBranch(instance)

	if not instance
		or not instance:IsA(
			"BasePart"
		) then

		return false

	end

	return BRANCH_NAMES[
	instance.Name
	] == true

end


-- =========================
-- ANIMATION
-- =========================

local ANIMATION_ID =
	"rbxassetid://101651539767821"


-- La animacion se reproduce a su velocidad normal.
-- Si el Tree Jump dura mas que la animacion, congelamos una pose
-- muy cercana al final y la mantenemos hasta aterrizar.
local TREE_JUMP_ANIMATION_SPEED =
	1.0


-- Congelamos unos milisegundos ANTES del final para evitar que Roblox
-- marque el track como terminado antes de poder pausarlo.
-- Ajuste visual:
-- Antes congelabamos 0.08 s antes del final.
-- Ahora congelamos 0.18 s antes para capturar una pose mas limpia
-- del impulso, antes de que la animacion empiece a "cerrarse".
local TREE_JUMP_FREEZE_BEFORE_END =
	0.50


local treeJumpTrack =
	nil


-- Invalida tareas viejas de freeze cuando comienza otro salto
-- o cuando limpiamos el actual.
local treeJumpAnimationGeneration =
	0


local function ensureAnimation()

	if treeJumpTrack then
		return
	end


	local animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)


	if not animator then


		animator =
			Instance.new(
				"Animator"
			)


		animator.Parent =
			humanoid

	end


	local animation =
		Instance.new(
			"Animation"
		)


	animation.AnimationId =
		ANIMATION_ID


	treeJumpTrack =
		animator:LoadAnimation(
			animation
		)


	treeJumpTrack.Priority =
		Enum.AnimationPriority.Action


	treeJumpTrack.Looped =
		false

end


local function stopTreeJumpAnimation(
	fadeTime
)

	treeJumpAnimationGeneration += 1


	if not treeJumpTrack then

		return

	end


	-- IMPORTANTE:
	-- Si el track estaba congelado con AdjustSpeed(0), devolvemos su
	-- velocidad antes de reutilizarlo en el siguiente Tree Jump.
	treeJumpTrack:AdjustSpeed(
		TREE_JUMP_ANIMATION_SPEED
	)


	if treeJumpTrack.IsPlaying then

		treeJumpTrack:Stop(
			fadeTime or 0.08
		)

	end

end


local function playTreeJumpAnimation(
	jumpDuration
)

	ensureAnimation()


	if not treeJumpTrack then

		return

	end


	treeJumpAnimationGeneration += 1

	local generation =
		treeJumpAnimationGeneration


	if treeJumpTrack.IsPlaying then

		treeJumpTrack:Stop(
			0
		)

	end


	treeJumpTrack:Play(
		0.08
	)


	treeJumpTrack:AdjustSpeed(
		TREE_JUMP_ANIMATION_SPEED
	)


	-- =========================
	-- FINAL POSE HOLD
	-- =========================
	--
	-- NO hacemos mas lenta toda la animacion.
	--
	-- Ejemplo:
	--
	-- animacion = 0.55 s
	-- Tree Jump = 1.20 s
	--
	-- 0.00 -> 0.47 s : animacion normal
	-- 0.47 -> 1.20 s : ultima pose mantenida
	-- aterriza           : Stop con blend
	--
	-- De esta manera el "impulso" de la animacion conserva su timing
	-- original aunque el salto tenga una duracion variable.

	task.spawn(
		function()

			-- AnimationTrack.Length puede ser 0 durante unos frames
			-- mientras Roblox termina de cargar el asset.
			local loadStart =
				time()


			while generation ==
				treeJumpAnimationGeneration
				and treeJumpTrack
				and treeJumpTrack.Length <=
				0
				and time() -
				loadStart <
				1 do

				RunService.Heartbeat:Wait()

			end


			if generation ~=
				treeJumpAnimationGeneration then

				return

			end


			if not treeJumpTrack
				or treeJumpTrack.Length <=
				0 then

				return

			end


			local animationPlaybackDuration =
				treeJumpTrack.Length /
				TREE_JUMP_ANIMATION_SPEED


			-- Si el salto termina antes que la animacion, no necesitamos
			-- congelar nada. cleanupTreeJumpState la cortara al aterrizar.
			if jumpDuration <=
				animationPlaybackDuration then

				return

			end


			local freezeAtPlaybackTime =
				math.max(
					animationPlaybackDuration
					- TREE_JUMP_FREEZE_BEFORE_END,
					0
				)


			local remainingWait =
				freezeAtPlaybackTime


			local waitStart =
				time()


			while generation ==
				treeJumpAnimationGeneration
				and time() -
				waitStart <
				remainingWait do

				RunService.Heartbeat:Wait()

			end


			if generation ~=
				treeJumpAnimationGeneration then

				return

			end


			if not treeJumpTrack
				or not treeJumpTrack.IsPlaying
				or character:GetAttribute(
					"TreeJumpActive"
				) ~= true then

				return

			end


			-- Colocamos el track explicitamente cerca del final y lo pausamos.
			-- AdjustSpeed(0) mantiene exactamente esa pose.
			treeJumpTrack.TimePosition =
				math.max(
					treeJumpTrack.Length
					- TREE_JUMP_FREEZE_BEFORE_END,
					0
				)


			treeJumpTrack:AdjustSpeed(
				0
			)

		end
	)

end


-- =========================
-- TREE HELPERS
-- =========================

local function isInsideArboles(instance)

	local current =
		instance


	while current
		and current ~= workspace do


		if current ==
			TREE_FOLDER then


			return true

		end


		current =
			current.Parent

	end


	return false

end


local function findTreeModelFor(instance)

	if not instance then
		return nil
	end


	local current =
		instance


	while current
		and current ~= workspace do


		if current.Parent ==
			TREE_FOLDER then


			return current

		end


		current =
			current.Parent

	end


	return nil

end


-- =========================
-- COLLECT BRANCHES
-- =========================

local function collectBranches(
	treeModel
)

	local branches = {}


	for _, descendant in ipairs(
		treeModel:GetDescendants()
		) do


		if descendant:IsA(
			"BasePart"
			)
				and BRANCH_NAMES[
			descendant.Name
			] then


			table.insert(
				branches,
				descendant
			)

		end

	end


	return branches

end


-- =========================
-- CURRENT BRANCH
-- =========================

local function getCurrentStandingBranch()
	local castDirection

	-- Si estamos caminando sobre una superficie especial,
	-- "abajo" ya no es -Y. Es la direccion opuesta a
	-- SurfaceNormal.
	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		local surfaceNormal =
			character:GetAttribute(
				"SurfaceNormal"
			)

		if typeof(surfaceNormal) ~=
			"Vector3"
			or surfaceNormal.Magnitude <
			0.5 then

			return nil
		end

		castDirection =
			-surfaceNormal.Unit
			* CURRENT_BRANCH_RAY_DISTANCE

	else
		if humanoid.FloorMaterial ==
			Enum.Material.Air then

			return nil
		end

		castDirection =
			Vector3.new(
				0,
				-CURRENT_BRANCH_RAY_DISTANCE,
				0
			)
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character
	}

	local hit =
		workspace:Raycast(
			rootPart.Position,
			castDirection,
			params
		)

	if not hit
		or not hit.Instance then

		return nil
	end

	local part =
		hit.Instance

	if not part:IsA(
		"BasePart"
		) then

		return nil
	end

	if not BRANCH_NAMES[
		part.Name
		] then

		return nil
	end

	if not isInsideArboles(
		part
		) then

		return nil
	end

	-- Se devuelve la INSTANCIA exacta.
	-- El nombre no se utiliza para decidir
	-- si es "la misma rama".
	return part
end


-- =========================
-- TREE UNDER CURSOR
-- =========================

local function findTreeUnderCursor(
	mouse
)

	local camera =
		workspace.CurrentCamera


	if not camera then
		return nil
	end


	-- =========================
	-- MOUSE TARGET
	-- =========================

	local target =
		mouse.Target


	if target
		and target:IsA(
			"BasePart"
		)
			and isInsideArboles(
				target
			) then


		return findTreeModelFor(
			target
		)

	end


	-- =========================
	-- RAYCAST FALLBACK
	-- =========================

	local mouseLocation =
		UIS:GetMouseLocation()


	local ray =
		camera:ScreenPointToRay(

			mouseLocation.X,

			mouseLocation.Y

		)


	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	params.FilterDescendantsInstances = {
		character
	}


	local hit =
		workspace:Raycast(

			ray.Origin,

			ray.Direction *
			500,

			params

		)


	if hit
		and hit.Instance
		and hit.Instance:IsA(
			"BasePart"
		)
			and isInsideArboles(
				hit.Instance
			) then


		return findTreeModelFor(
			hit.Instance
		)

	end


	return nil

end


-- =========================
-- VISIBILITY (CAMERA)
-- =========================
-- La rama es visible solo si el Raycast desde
-- la camara hasta su posicion impacta PRIMERO
-- en la propia rama (o un descendiente suyo).
-- Si impacta antes en tronco, canopy, hojas,
-- otra rama o una pared, queda descartada.

local function isBranchVisibleFromCamera(
	branch,
	camera,
	localCharacter
)

	local origin =
		camera.CFrame.Position

	local direction =
		branch.Position -
		origin

	local distance =
		direction.Magnitude

	if distance <
		0.1 then

		return true

	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		localCharacter
	}

	local hit =
		workspace:Raycast(
			origin,
			direction.Unit * distance,
			params
		)

	if not hit then
		return true
	end

	if hit.Instance ==
		branch
		or hit.Instance:IsDescendantOf(
			branch
		) then

		return true

	end

	return false

end


-- =========================
-- PICK BEST BRANCH
-- =========================

local function pickBestBranch(
	treeModel,
	mouse
)

	local camera =
		workspace.CurrentCamera


	if not camera then
		return nil
	end


	local branches =
		collectBranches(
			treeModel
		)


	if #branches == 0 then
		return nil
	end


	local currentBranch =
		getCurrentStandingBranch()


	if DEBUG_TREE_JUMP
		and currentBranch then


		print(
			"[TreeJump-Client] rama actual ignorada:",
			currentBranch:GetFullName()
		)

	end


	-- =========================
	-- PRIORITY 1:
	-- DIRECT TARGET
	-- =========================

	local directTarget =
		mouse.Target


	if directTarget
		and directTarget:IsA(
			"BasePart"
		)
			and BRANCH_NAMES[
		directTarget.Name
		]

			-- INSTANCIA EXACTA.
			and directTarget ~=
			currentBranch

			-- Y DEBE SER VISIBLE DESDE LA CAMARA
			-- (no oculta tras el tronco o el canopy).
			and isBranchVisibleFromCamera(
				directTarget,
				camera,
				character
			) then


		if isInsideArboles(
			directTarget
			)
				and findTreeModelFor(
					directTarget
				) == treeModel then


			local distance =
				(
					directTarget.Position -
					rootPart.Position
				).Magnitude


			if distance >=
				MIN_DISTANCE
				and distance <=
				MAX_DISTANCE

				-- NO la rama en la que estamos.
				and distance >
				SAME_BRANCH_THRESHOLD then


				return directTarget

			end

		end

	end


	-- =========================
	-- PRIORITY 2:
	-- CLOSEST TO CURSOR
	-- =========================

	local mousePosition =
		Vector2.new(
			mouse.X,
			mouse.Y
		)


	local bestScreenBranch =
		nil


	local bestScreenScore =
		math.huge


	for _, branch in ipairs(
		branches
		) do


		if branch ~=
			currentBranch then


			local distance =
				(
					branch.Position -
					rootPart.Position
				).Magnitude


			if distance >=
				MIN_DISTANCE
				and distance <=
				MAX_DISTANCE

				-- NO la rama en la que estamos.
				and distance >
				SAME_BRANCH_THRESHOLD

					-- VISIBLE DESDE LA CAMARA.
					and isBranchVisibleFromCamera(
						branch,
						camera,
						character
					) then


				local screenPosition,
					onScreen =
					camera:
					WorldToViewportPoint(
						branch.Position
					)


				if onScreen
					and screenPosition.Z >
					0 then


					local dx =
						screenPosition.X -
						mousePosition.X


					local dy =
						screenPosition.Y -
						mousePosition.Y


					local score =
						(dx * dx)
						+
						(dy * dy)


					if score <
						bestScreenScore then


						bestScreenScore =
							score


						bestScreenBranch =
							branch

					end

				end

			end

		end

	end


	if bestScreenBranch
		and bestScreenScore <=
		(
			CURSOR_SCREEN_TOLERANCE
				*
				CURSOR_SCREEN_TOLERANCE
		) then


		return bestScreenBranch

	end


	-- =========================
	-- PRIORITY 3:
	-- 3D FALLBACK
	-- =========================

	local best3DBranch =
		nil


	local best3DDistance =
		math.huge


	for _, branch in ipairs(
		branches
		) do


		if branch ~=
			currentBranch then


			local distance =
				(
					branch.Position -
					rootPart.Position
				).Magnitude


			if distance >=
				MIN_DISTANCE
				and distance <=
				MAX_DISTANCE

				-- NO la rama en la que estamos.
				and distance >
				SAME_BRANCH_THRESHOLD

					and distance <
					best3DDistance

					-- VISIBLE DESDE LA CAMARA.
					and isBranchVisibleFromCamera(
						branch,
						camera,
						character
					) then


				best3DDistance =
					distance


				best3DBranch =
					branch

			end

		end

	end


	return best3DBranch

end


-- (isBranchVisibleFromCamera reubicada antes de pickBestBranch)


-- =========================
-- CLEAR DASH PATH
-- =========================
-- Raycast desde HumanoidRootPart hasta el punto
-- final seguro. Bloquea si algo (tronco, canopy,
-- hojas, otra rama o pared) se interpone antes
-- de llegar al destino. NO se ignoran partes del
-- mismo arbol: el tronco debe bloquear el salto.

local function hasClearDashPath(
	root,
	targetPosition,
	targetBranch,
	localCharacter
)

	local origin =
		root.Position

	local direction =
		targetPosition -
		origin

	local distance =
		direction.Magnitude

	if distance <
		0.1 then

		return false

	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		localCharacter
	}

	local hit =
		workspace:Raycast(
			origin,
			direction.Unit * distance,
			params
		)

	if not hit then
		return true
	end

	-- Llego al destino: ruta despejada.
	if (
		hit.Position -
			targetPosition
		).Magnitude <=
			EXTERNAL_BLOCK_TOLERANCE then

		return true

	end

	-- El impacto es la rama objetivo: permitido.
	if hit.Instance ==
		targetBranch
		or hit.Instance:IsDescendantOf(
			targetBranch
		) then

		return true

	end

	return false

end


-- =========================
-- LANDING POSITION
-- =========================
-- Punto final seguro: delante y ligeramente por
-- encima de la superficie de la rama objetivo.
-- Nunca dentro de Trunk, Canopy o la propia rama.

local function computeLandingPosition(branch)

	local rootPos =
		rootPart.Position

	local branchPos =
		branch.Position

	local branchTopY =
		branchPos.Y
		+
		(
			branch.Size.Y /
			2
		)

	local characterHeight =
		(
			rootPart.Size.Y /
			2
		)
		+
		humanoid.HipHeight
		+
		1.5

	local horizontal =
		Vector3.new(
			branchPos.X - rootPos.X,
			0,
			branchPos.Z - rootPos.Z
		)

	if horizontal.Magnitude >
		0.001 then

		horizontal =
			horizontal.Unit
			*
			TREE_JUMP_DISTANCE_OFFSET

	else

		horizontal =
			Vector3.zero

	end

	return Vector3.new(
		branchPos.X - horizontal.X,
		branchTopY + characterHeight,
		branchPos.Z - horizontal.Z
	)

end


-- =========================
-- OBSTACLE CHECK
-- =========================

local function isBlockedByExternalObject(
	treeModel,
	targetPosition
)

	local origin =
		rootPart.Position


	local delta =
		targetPosition -
		origin


	local distance =
		delta.Magnitude


	if distance <
		0.1 then


		return true

	end


	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	params.FilterDescendantsInstances = {
		character
	}


	local hit =
		workspace:Raycast(

			origin,

			delta,

			params

		)


	if not hit then

		return false

	end


	-- Cualquier pieza perteneciente al mismo
	-- �rbol objetivo NO bloquea.

	-- Reemplazado por hasClearDashPath (definido arriba).
	-- Este stub mantiene la firma pero ya no se usa:
	-- la validacion de ruta real la hace hasClearDashPath.

	return false

end


-- =========================
-- ACTIVE STATE
-- =========================

local lastLocalUse =
	0


local activeVelocity =
	nil


local activeAttachment =
	nil


local activeFacingDirection =
	nil


local previousAutoRotate =
	nil


local previousPlatformStand =
	nil


-- =========================
-- FACING
-- =========================

local function getFlatFacingToPosition(
	targetPosition
)

	local difference =
		targetPosition -
		rootPart.Position


	local direction =
		Vector3.new(

			difference.X,

			0,

			difference.Z

		)


	if direction.Magnitude <
		0.01 then


		local look =
			rootPart.CFrame.LookVector


		direction =
			Vector3.new(

				look.X,

				0,

				look.Z

			)

	end


	if direction.Magnitude <
		0.01 then


		return Vector3.new(
			0,
			0,
			-1
		)

	end


	return direction.Unit

end


local function lockTreeJumpFacing()

	if not rootPart.Parent then
		return
	end


	if not activeFacingDirection then
		return
	end


	humanoid.AutoRotate =
		false


	rootPart.AssemblyAngularVelocity =
		Vector3.zero


	rootPart.CFrame =
		CFrame.lookAt(

			rootPart.Position,

			rootPart.Position +
			activeFacingDirection,

			Vector3.yAxis

		)

end


-- =========================
-- CLEANUP
-- =========================

local function cleanupTreeJumpState(
	restorePosition
)

	-- La animacion puede estar congelada en su pose final.
	-- La soltamos exactamente al terminar/cancelar el Tree Jump.
	stopTreeJumpAnimation(
		0.08
	)


	stopTreeJumpFov()

	stopTreeJumpDof()

	WindTrail.stop(character)


	if activeVelocity then


		activeVelocity:Destroy()


		activeVelocity =
			nil

	end


	if activeAttachment then


		activeAttachment:Destroy()


		activeAttachment =
			nil

	end


	-- =========================
	-- FINAL POSITION
	-- =========================

	if restorePosition
		and rootPart.Parent then


		if activeFacingDirection then


			rootPart.CFrame =
				CFrame.lookAt(

					restorePosition,

					restorePosition +
					activeFacingDirection,

					Vector3.yAxis

				)


		else


			local rotation =
				rootPart.CFrame.Rotation


			rootPart.CFrame =
				CFrame.new(
					restorePosition
				)
				*
				rotation

		end

	end


	-- =========================
	-- STOP PHYSICS
	-- =========================

	if rootPart.Parent then


		rootPart.AssemblyLinearVelocity =
			Vector3.zero


		rootPart.AssemblyAngularVelocity =
			Vector3.zero

	end


	-- =========================
	-- RESTORE HUMANOID
	-- =========================

	if previousPlatformStand ~=
		nil then


		humanoid.PlatformStand =
			previousPlatformStand

	end


	if previousAutoRotate ~=
		nil then


		humanoid.AutoRotate =
			previousAutoRotate

	end


	-- =========================
	-- ATTRIBUTES
	-- =========================

	character:SetAttribute(
		"TreeJumpActive",
		false
	)


	character:SetAttribute(
		"TreeJumpProtected",
		false
	)


	-- =========================
	-- RESET
	-- =========================

	activeFacingDirection =
		nil


	previousAutoRotate =
		nil


	previousPlatformStand =
		nil

end


-- =========================
-- PERFORM TREE JUMP
-- =========================

local function performLocalTreeJump(
	landingPos: Vector3,
	duration: number,
	arcHeight: number
)

	if not rootPart.Parent then
		return
	end


	if activeVelocity then
		return
	end


	if character:GetAttribute(
		"TreeJumpActive"
		) then


		return

	end


	-- Seguridad.
	duration =
		math.max(
			duration,
			0.001
		)


	arcHeight =
		math.max(
			arcHeight,
			0
		)


	-- =========================
	-- SAVE STATE
	-- =========================

	previousPlatformStand =
		humanoid.PlatformStand


	previousAutoRotate =
		humanoid.AutoRotate


	-- =========================
	-- TREE JUMP STATE
	-- =========================

	humanoid.PlatformStand =
		true


	humanoid.AutoRotate =
		false


	character:SetAttribute(
		"TreeJumpActive",
		true
	)


	character:SetAttribute(
		"TreeJumpProtected",
		true
	)


	startTreeJumpFov()

	startTreeJumpDof()

	WindTrail.start(character)


	-- =========================
	-- ORIENTATION
	-- =========================

	activeFacingDirection =
		getFlatFacingToPosition(
			landingPos
		)


	rootPart.AssemblyAngularVelocity =
		Vector3.zero


	lockTreeJumpFacing()


	-- =========================
	-- ATTACHMENT
	-- =========================

	local attachment =
		Instance.new(
			"Attachment"
		)


	attachment.Name =
		"TreeJumpVelocityAttachment"


	attachment.Parent =
		rootPart


	activeAttachment =
		attachment


	-- =========================
	-- LINEAR VELOCITY
	-- =========================

	local velocity =
		Instance.new(
			"LinearVelocity"
		)


	velocity.Name =
		"TreeJumpLinearVelocity"


	velocity.Attachment0 =
		attachment


	velocity.RelativeTo =
		Enum.ActuatorRelativeTo.World


	velocity.MaxForce =
		math.huge


	velocity.VectorVelocity =
		Vector3.zero


	velocity.Parent =
		rootPart


	activeVelocity =
		velocity


	-- =========================
	-- TRAJECTORY DATA
-- =========================

	local startPosition =
		rootPart.Position


	local travel =
		landingPos -
		startPosition


	-- Esta es la velocidad necesaria para
	-- alcanzar exactamente el destino en
	-- la duraci�n calculada por el servidor.

	local baseVelocity =
		travel /
		duration


	local startTime =
		time()


	-- =========================
	-- MOVEMENT LOOP
	-- =========================

	while time() -
		startTime <
		duration do


		if not rootPart.Parent
			or humanoid.Health <= 0 then


			break

		end


		local elapsed =
			time() -
			startTime


		local alpha =
			math.clamp(

				elapsed /
				duration,

				0,
				1

			)


		-- =========================
		-- REAL PARABOLIC ARC
		-- =========================
		--
		-- La altura adicional del salto es:
		--
		-- H * 4a(1-a)
		--
		-- donde:
		--
		-- a = alpha
		-- H = arcHeight
		--
		-- En la mitad:
		--
		-- alpha = 0.5
		-- altura extra = arcHeight
		--
		-- Como LinearVelocity necesita
		-- VELOCIDAD y no posici�n, usamos
		-- la derivada de esa par�bola:
		--
		-- (4H / duration) * (1 - 2a)
		--
		-- Resultado:
		--
		-- inicio  ?
		-- mitad   ?
		-- final   ?

		local arcVelocityY =
			(
				4 *
				arcHeight /
				duration
			)
			*
			(
				1 -
				2 *
				alpha
			)


		velocity.VectorVelocity =
			Vector3.new(

				baseVelocity.X,

				baseVelocity.Y +
				arcVelocityY,

				baseVelocity.Z

			)


		-- =========================
		-- ORIENTATION PROTECTION
		-- =========================

		lockTreeJumpFacing()


		RunService.Heartbeat:Wait()

	end


	-- =========================
	-- FINISH
	-- =========================

	cleanupTreeJumpState(
		landingPos
	)

	playTreeJumpSound(
		TREE_JUMP_SOUND_LAND_ID
	)

	if DEBUG_TREE_JUMP then


		print(
			"[TreeJump-Client] salto finalizado",
			"duracion:",
			string.format(
				"%.2f",
				duration
			),
			"arco:",
			string.format(
				"%.2f",
				arcHeight
			)
		)

	end

end



local function isDownedSystemLocked(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsCarrying") == true
end


-- =========================
-- WATER / SWIMMING GUARD
-- =========================
-- Tree Jump is forbidden while actually swimming or physically submerged
-- in Terrain water. WaterWalking remains allowed because Chakra Feet owns
-- that state and the character is intentionally traveling on the surface.
--
-- We do NOT rely only on HumanoidStateType.Swimming. Around the water
-- surface Roblox can briefly transition through other humanoid states, so
-- we also inspect Terrain water voxels around the HumanoidRootPart.
--
-- This check only runs when Tree Jump is requested.

local TREE_JUMP_WATER_VOXEL_RESOLUTION =
	4

local TREE_JUMP_WATER_OCCUPANCY_THRESHOLD =
	0.10

local TREE_JUMP_WATER_SAMPLE_HALF_SIZE =
	Vector3.new(
		1.5,
		1.8,
		1.5
	)


local function isRootInsideTerrainWater(): boolean

	local terrain =
		workspace.Terrain


	local region =
		Region3.new(
			rootPart.Position
			- TREE_JUMP_WATER_SAMPLE_HALF_SIZE,
			rootPart.Position
			+ TREE_JUMP_WATER_SAMPLE_HALF_SIZE
		):
		ExpandToGrid(
			TREE_JUMP_WATER_VOXEL_RESOLUTION
		)


	local materials,
		occupancies =
		terrain:
		ReadVoxels(
			region,
			TREE_JUMP_WATER_VOXEL_RESOLUTION
		)


	for x = 1,
		#materials do

		for y = 1,
			#materials[x] do

			for z = 1,
				#materials[x][y] do

				if materials[x][y][z] ==
					Enum.Material.Water
					and occupancies[x][y][z] >=
					TREE_JUMP_WATER_OCCUPANCY_THRESHOLD then

					return true
				end
			end
		end
	end


	return false
end


local function isTreeJumpWaterBlocked(): boolean

	-- Actual Roblox swimming always wins, even if another attribute is stale.
	if humanoid:GetState() ==
		Enum.HumanoidStateType.Swimming then

		return true
	end


	if character:GetAttribute(
		"WaterJumping"
		) == true then

		return true
	end


	-- Stable Chakra Feet WaterWalking is intentionally allowed.
	if character:GetAttribute(
		"WaterWalking"
		) == true then

		return false
	end


	if humanoid.FloorMaterial ==
		Enum.Material.Water then

		return true
	end


	return isRootInsideTerrainWater()
end


-- =========================
-- TRY TREE JUMP
-- =========================

local function tryTreeJump()

	if isTreeJumpWaterBlocked() then

		if DEBUG_TREE_JUMP then

			print(
				"[TreeJump-Client] BLOCKED: Swimming/SubmergedWater"
			)
		end

		return
	end


	if isDownedSystemLocked() then
		return
	end

	if humanoid.Health <= 0 then
		return
	end


	if character:GetAttribute(
		"IsDashing"
		) then


		return

	end


	if character:GetAttribute(
		"IsTreeJumping"
		) then


		return

	end


	if character:GetAttribute(
		"TreeJumpActive"
		) then


		return

	end


	if activeVelocity then
		return
	end


	if time() -
		lastLocalUse <
		TREE_JUMP_COOLDOWN then


		return

	end


	local mouse =
		player:GetMouse()


	-- =========================
	-- TREE
	-- =========================

	local treeModel =
		findTreeUnderCursor(
			mouse
		)


	if not treeModel then


		if DEBUG_TREE_JUMP then


			print(
				"[TreeJump-Client] sin arbol bajo el cursor"
			)

		end


		return

	end


	-- =========================
	-- BRANCH
	-- =========================

	local branch =
		pickBestBranch(
			treeModel,
			mouse
		)


	if not branch then


		if DEBUG_TREE_JUMP then


			print(
				"[TreeJump-Client] sin rama valida"
			)

		end


		return

	end


	-- =========================
	-- RUTA LIBRE
	-- =========================

	if not hasClearDashPath(
		rootPart,
		computeLandingPosition(
			branch
		),
		branch,
		character
		) then


		if DEBUG_TREE_JUMP then


			print(
				"[TreeJump-Client] ruta bloqueada (tronco/canopy/otra rama/pared)"
			)

		end


		return

	end


	-- =========================
	-- SERVER REQUEST
	-- =========================

	lastLocalUse =
		time()


	requestEvent:FireServer(
		branch
	)


	if DEBUG_TREE_JUMP then


		print(
			"[TreeJump-Client] solicitud:",
			branch:GetFullName()
		)

	end

end


-- =========================
-- SERVER APPROVED
-- =========================

approvedEvent.OnClientEvent:Connect(
	function(
		landingPos,
		duration,
		arcHeight
	)

		if isDownedSystemLocked() then
			return
		end


		if DEBUG_TREE_JUMP then


			print(
				"[TreeJump-Client] APROBADO",
				"destino:",
				tostring(
					landingPos
				),
				"duracion:",
				string.format(
					"%.2f",
					duration
				),
				"arco:",
				string.format(
					"%.2f",
					arcHeight
				)
			)

		end


		-- La animaci�n empieza �nicamente
		-- cuando el servidor aprueba el salto.

		playTreeJumpSound(
			TREE_JUMP_SOUND_JUMP_ID
		)

		playTreeJumpAnimation(
			duration
		)


		performLocalTreeJump(
			landingPos,
			duration,
			arcHeight
		)

	end
)


-- =========================
-- OTHER PLAYERS
-- =========================

replicateEvent.OnClientEvent:Connect(
	function(
		jumpingPlayer,
		landingPos
	)


		-- Emitir particulas de madera en TODOS
		-- los clientes (due�o y espectadores).
		-- Las particulas salen de los pies del
		-- personaje que ejecuta el salto.

		local jumpingCharacter =
			jumpingPlayer
			and jumpingPlayer.Character


		if jumpingCharacter then

			playTreeJumpWoodParticles(
				jumpingCharacter
			)

		end


		if jumpingPlayer ==
			player then


			return

		end


		local otherCharacter =
			jumpingPlayer
			and jumpingPlayer.Character


		local otherHumanoid =
			otherCharacter
			and otherCharacter:
			FindFirstChildOfClass(
				"Humanoid"
			)


		if not otherHumanoid then
			return
		end


		local animator =
			otherHumanoid:
			FindFirstChildOfClass(
				"Animator"
			)


		if not animator then


			animator =
				Instance.new(
					"Animator"
				)


			animator.Parent =
				otherHumanoid

		end


		local animation =
			Instance.new(
				"Animation"
			)


		animation.AnimationId =
			ANIMATION_ID


		local track =
			animator:LoadAnimation(
				animation
			)


		track.Priority =
			Enum.AnimationPriority.Action


		track.Looped =
			false


		track:Play(
			0.08
		)


		task.delay(
			1,

			function()


				if track.IsPlaying then


					track:Stop(
						0.15
					)

				end


				animation:Destroy()

			end
		)

	end
)


-- =========================
-- SERVER CANCEL / FINISH
-- =========================

character:GetAttributeChangedSignal(
	"IsTreeJumping"
):Connect(
	function()


		if character:GetAttribute(
			"IsTreeJumping"
			) == false
				and activeVelocity then


			cleanupTreeJumpState()

		end

	end
)


local function handleDownedIntegrationState()
	if isDownedSystemLocked()
		and (
			activeVelocity
				or character:GetAttribute("TreeJumpActive") == true
		) then

		cleanupTreeJumpState()
	end
end

for _, attributeName in ipairs({
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsExecuting",
	"IsCarrying",
	}) do
	character:GetAttributeChangedSignal(attributeName):Connect(
		handleDownedIntegrationState
	)
end


-- =========================
-- DEATH
-- =========================

humanoid.Died:Connect(
	function()


		cleanupParticleEmitters(character)


		if activeVelocity
			or character:GetAttribute(
				"TreeJumpActive"
			) then


			cleanupTreeJumpState()

		end

	end
)


-- =========================
-- INPUT
-- =========================

UIS.InputBegan:Connect(
	function(
		input,
		gameProcessed
	)


		if gameProcessed then
			return
		end


		if input.KeyCode ~=
			TREE_JUMP_KEY then


			return
		end


		tryTreeJump()

	end
)