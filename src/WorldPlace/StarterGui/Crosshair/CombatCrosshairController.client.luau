--!strict
-- CombatCrosshairController v5 - Surface Screen-Space Shoulder Camera + Mouse Lock Aim
--
-- REQUISITO:
-- Este LocalScript vive dentro del ScreenGui que contiene:
--
--   ScreenGui
--   +-- Reticle (ImageLabel)
--   +-- CombatCrosshairController (LocalScript)
--
-- IMPORTANTE:
-- Este script YA NO controla CombatMode y YA NO escucha la tecla R.
--
-- CombatController es la �nica autoridad que:
-- - recibe R
-- - entra/sale de Combat Mode
-- - escribe los atributos CombatMode / CombatSuppressed
--
-- Este script solamente OBSERVA esos atributos y se encarga de:
-- - mostrar/ocultar la crosshair
-- - aplicar/quitar el offset de camara de combate
-- - mantener la MISMA composicion shoulder-camera en suelo, paredes y techos
--
-- En suelo usamos Humanoid.CameraOffset como antes.
-- En SurfaceWalking no-water, el mismo offset se aplica en SCREEN SPACE despues
-- de SurfaceCamera_Post. Asi "derecha" y "arriba" siguen significando derecha
-- y arriba de la pantalla aunque el personaje este rotado 90/180 grados.
--
-- No modifica CombatMode ni la logica de aim.

local Players =
	game:GetService("Players")

local GuiService =
	game:GetService("GuiService")

local RunService =
	game:GetService("RunService")

local UserInputService =
	game:GetService("UserInputService")

local TweenService =
	game:GetService("TweenService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")


-- =========================
-- CONFIG
-- =========================

local CROSSHAIR_IMAGE =
	"rbxassetid://122005572232501"

local CROSSHAIR_SIZE =
	12

-- Ya no usamos un Y manual.
-- La crosshair se dibuja exactamente sobre la posici�n real del mouse.
local FADE_TIME =
	0.25


-- Offset de c�mara mientras el combate est� realmente ACTIVO.
--
-- CombatMode = true + CombatSuppressed = false
--
-- CombatSuppressed se usa, por ejemplo, mientras el personaje nada.
local CAMERA_OFFSET_RIGHT =
	3

local CAMERA_OFFSET_UP =
	2

local CAMERA_OFFSET_BACK =
	0

local COMBAT_CAMERA_OFFSET =
	Vector3.new(
		CAMERA_OFFSET_RIGHT,
		CAMERA_OFFSET_UP,
		CAMERA_OFFSET_BACK
	)


-- Tiempo aproximado para transferir el shoulder offset entre:
-- Humanoid local-space <-> camera screen-space.
--
-- No cambia la magnitud total del offset; solo cambia QUIEN lo aplica.
local SURFACE_OFFSET_BLEND_TIME =
	0.18


-- Debemos ejecutar:
-- 1) antes de SurfaceCamera_Pre para retirar nuestro offset manual anterior
-- 2) despues de SurfaceCamera_Post para aplicar el nuevo offset en screen-space
local CAMERA_OFFSET_PRE_BIND =
	"CombatCrosshair_SurfaceOffset_Pre"

local CAMERA_OFFSET_POST_BIND =
	"CombatCrosshair_SurfaceOffset_Post"


-- =========================
-- PLAYER / GUI
-- =========================

local player =
	Players.LocalPlayer

if not player then

	error(
		"CombatCrosshairController debe ejecutarse como LocalScript."
	)

end


local screenGui =
	script.Parent :: ScreenGui

local reticle =
	screenGui:WaitForChild(
		"Reticle"
	) :: ImageLabel


local CombatAim =
	require(
		ReplicatedStorage:WaitForChild(
			"CombatAim"
		)
	)


-- El ScreenGui puede sobrevivir al respawn.
screenGui.ResetOnSpawn =
	false


-- =========================
-- RETICLE SETUP
-- =========================

reticle.Image =
	CROSSHAIR_IMAGE

reticle.Size =
	UDim2.fromOffset(
		CROSSHAIR_SIZE,
		CROSSHAIR_SIZE
	)

reticle.AnchorPoint =
	Vector2.new(
		0.5,
		0.5
	)

reticle.BackgroundTransparency =
	1

reticle.Active =
	false

-- Debe arrancar realmente oculta.
reticle.ImageTransparency =
	1

reticle.ZIndex =
	10


-- El m�dulo de aim usa el CENTRO REAL renderizado de este Reticle.
-- No duplicamos CROSSHAIR_Y_SCALE en otros scripts.
CombatAim.SetReticle(
	reticle
)


-- =========================
-- TWEENS
-- =========================

local fadeTweenInfo =
	TweenInfo.new(
		FADE_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)


local activeReticleTween: Tween? =
	nil

-- =========================
-- CHARACTER STATE
-- =========================

local currentCharacter: Model? =
	nil

local currentHumanoid: Humanoid? =
	nil

-- Guardamos el CameraOffset que ya ten�a el Humanoid cuando nos conectamos.
-- As� no asumimos que siempre debe ser Vector3.zero y somos m�s compatibles
-- con futuros sistemas que quieran partir de un offset base.
local baseCameraOffset =
	Vector3.zero


-- 0..1 amount of the combat camera offset currently active.
local combatCameraBlend =
	0

local combatCameraBlendTarget =
	0

-- 0 = Humanoid.CameraOffset owns the combat offset.
-- 1 = screen-space post-camera translation owns it.
local surfaceSpaceBlend =
	0

local surfaceSpaceBlendTarget =
	0

-- World-space translation applied at the END of the previous frame.
-- We remove it at the BEGINNING of the next frame before SurfaceController
-- performs its own inverse/forward camera transforms.
local lastManualWorldOffset =
	Vector3.zero


local characterConnections: {RBXScriptConnection} =
	{}


-- =========================
-- HELPERS
-- =========================

local function disconnectCharacterConnections()

	for _, connection in ipairs(
		characterConnections
		) do

		connection:Disconnect()

	end


	table.clear(
		characterConnections
	)

end


local function isCombatVisualActive(): boolean

	local character =
		currentCharacter


	if not character then

		return false

	end


	return character:GetAttribute(
		"CombatMode"
	) == true
		and character:GetAttribute(
			"CombatSuppressed"
		) ~= true

end


local function isRotatedSurfaceCameraActive(): boolean

	local character =
		currentCharacter

	if not character then
		return false
	end

	-- Water Walk deliberately stays world-up in SurfaceController.
	return character:GetAttribute(
		"SurfaceWalking"
	) == true
		and character:GetAttribute(
			"WaterWalking"
		) ~= true

end


local function approach(
	current: number,
	target: number,
	maxDelta: number
): number

	if current < target then
		return math.min(
			target,
			current + maxDelta
		)
	end

	if current > target then
		return math.max(
			target,
			current - maxDelta
		)
	end

	return target

end


local function tweenReticle(
	active: boolean
)

	if activeReticleTween then

		activeReticleTween:Cancel()

	end


	activeReticleTween =
		TweenService:Create(
			reticle,
			fadeTweenInfo,
			{
				ImageTransparency =
				if active
				then 0
				else 1
			}
		)


	activeReticleTween:Play()

end


local function refreshCameraTargets()

	combatCameraBlendTarget =
		if isCombatVisualActive()
		then 1
		else 0

	surfaceSpaceBlendTarget =
		if isRotatedSurfaceCameraActive()
		then 1
		else 0

end


local lastVisualActive: boolean? =
	nil


local function refreshCombatVisuals(
	force: boolean?
)

	local active =
		isCombatVisualActive()


	if not force
		and lastVisualActive ==
		active then

		return

	end


	lastVisualActive =
		active


	tweenReticle(
		active
	)


	refreshCameraTargets()

end


-- =========================
-- CHARACTER BINDING
-- =========================

local function bindCharacter(
	character: Model
)

	disconnectCharacterConnections()


	currentCharacter =
		character


	local humanoid =
		character:WaitForChild(
			"Humanoid"
		) :: Humanoid


	currentHumanoid =
		humanoid


	baseCameraOffset =
		humanoid.CameraOffset


	combatCameraBlend =
		0

	combatCameraBlendTarget =
		0

	surfaceSpaceBlend =
		0

	surfaceSpaceBlendTarget =
		0

	lastManualWorldOffset =
		Vector3.zero


	lastVisualActive =
		nil


	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal(
			"CombatMode"
		):Connect(
			function()

				refreshCombatVisuals(
					false
				)

			end
		)
	)


	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal(
			"CombatSuppressed"
		):Connect(
			function()

				refreshCombatVisuals(
					false
				)

			end
		)
	)


	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal(
			"SurfaceWalking"
		):Connect(
			function()

				refreshCameraTargets()

			end
		)
	)


	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal(
			"WaterWalking"
		):Connect(
			function()

				refreshCameraTargets()

			end
		)
	)


	table.insert(
		characterConnections,
		humanoid.Died:Connect(
			function()

				-- No modificamos CombatMode.
				-- Solo limpiamos la presentaci�n visual inmediatamente.
				lastVisualActive =
					false


				tweenReticle(
					false
				)


				combatCameraBlendTarget =
					0

				surfaceSpaceBlendTarget =
					0

			end
		)
	)


	-- No escribimos ning�n atributo.
	-- Leemos el estado que CombatController haya establecido.
	refreshCombatVisuals(
		true
	)

end


-- =========================
-- SURFACE-SAFE COMBAT CAMERA
-- =========================
--
-- SurfaceController currently runs:
--
-- Camera.Value - 1  -> SurfaceCamera_Pre
-- Camera.Value + 1  -> SurfaceCamera_Post
--
-- We deliberately bracket it:
--
-- Camera.Value - 2:
--   remove our previous manual screen-space translation
--   update Humanoid.CameraOffset for this frame
--
-- Camera.Value + 2:
--   SurfaceController has already rotated the final camera
--   add the combat shoulder offset using CAMERA Right/Up/Look vectors
--
-- This prevents accumulation and keeps the character/crosshair composition
-- screen-consistent on wall and ceiling surfaces.

RunService:UnbindFromRenderStep(
	CAMERA_OFFSET_PRE_BIND
)

RunService:UnbindFromRenderStep(
	CAMERA_OFFSET_POST_BIND
)


RunService:BindToRenderStep(
	CAMERA_OFFSET_PRE_BIND,
	Enum.RenderPriority.Camera.Value - 2,
	function(
		deltaTime: number
	)

		local camera =
			workspace.CurrentCamera


		-- Remove exactly what we manually added at the end of the prior frame.
		-- This is required before SurfaceCamera_Pre transforms the camera back
		-- into virtual upright space.
		if camera
			and lastManualWorldOffset.Magnitude > 0.00001 then

			camera.CFrame =
				camera.CFrame
			- lastManualWorldOffset

		end


		lastManualWorldOffset =
			Vector3.zero


		local humanoid =
			currentHumanoid


		if not humanoid
			or humanoid.Parent == nil then

			return

		end


		local combatStep =
			if FADE_TIME <= 0
			then 1
			else deltaTime / FADE_TIME


		combatCameraBlend =
			approach(
				combatCameraBlend,
				combatCameraBlendTarget,
				combatStep
			)


		local surfaceStep =
			if SURFACE_OFFSET_BLEND_TIME <= 0
			then 1
			else deltaTime / SURFACE_OFFSET_BLEND_TIME


		surfaceSpaceBlend =
			approach(
				surfaceSpaceBlend,
				surfaceSpaceBlendTarget,
				surfaceStep
			)


		-- Cross-fade ownership.
		--
		-- Ground:
		--   surfaceSpaceBlend = 0
		--   full combat offset lives in Humanoid.CameraOffset.
		--
		-- Wall / ceiling:
		--   surfaceSpaceBlend = 1
		--   Humanoid gets only base offset; manual camera pass owns combat offset.
		local humanoidCombatBlend =
			combatCameraBlend
			* (1 - surfaceSpaceBlend)


		humanoid.CameraOffset =
			baseCameraOffset
			+ COMBAT_CAMERA_OFFSET
			* humanoidCombatBlend

	end
)


RunService:BindToRenderStep(
	CAMERA_OFFSET_POST_BIND,
	Enum.RenderPriority.Camera.Value + 2,
	function()

		local camera =
			workspace.CurrentCamera


		if not camera then

			lastManualWorldOffset =
				Vector3.zero

			return

		end


		local manualBlend =
			combatCameraBlend
			* surfaceSpaceBlend


		if manualBlend <= 0.00001 then

			lastManualWorldOffset =
				Vector3.zero

			return

		end


		local cameraCFrame =
			camera.CFrame


		-- Positive X = right side of SCREEN.
		-- Positive Y = top of SCREEN.
		-- Positive Z = backward from screen/camera look direction,
		-- matching the semantic intent of CameraOffset.Z.
		local manualWorldOffset =
			(
				cameraCFrame.RightVector
				* CAMERA_OFFSET_RIGHT
				+ cameraCFrame.UpVector
				* CAMERA_OFFSET_UP
				- cameraCFrame.LookVector
				* CAMERA_OFFSET_BACK
			)
			* manualBlend


		camera.CFrame =
			cameraCFrame
			+ manualWorldOffset


		lastManualWorldOffset =
			manualWorldOffset

	end
)


-- =========================
-- RESPAWN
-- =========================

player.CharacterAdded:Connect(
	function(
		character
	)

		bindCharacter(
			character
		)

	end
)


if player.Character then

	bindCharacter(
		player.Character
	)

end


-- =========================
-- RETICLE POSITION
-- =========================
--
-- Esto solamente mueve UI.
-- No modifica CurrentCamera.CFrame, MouseBehavior ni CombatMode,
-- por lo que no compite con CombatController o SurfaceController.

RunService.RenderStepped:Connect(
	function()

		local mouseScreenPosition =
			UserInputService:GetMouseLocation()


		local guiPosition =
			mouseScreenPosition


		-- GetMouseLocation est� en coordenadas de pantalla.
		-- Si el ScreenGui respeta el inset, convertimos a su espacio local.
		if not screenGui.IgnoreGuiInset then

			local topLeftInset =
				GuiService:GetGuiInset()


			guiPosition =
				mouseScreenPosition
			- topLeftInset

		end


		reticle.Position =
			UDim2.fromOffset(
				guiPosition.X,
				guiPosition.Y
			)

	end
)


-- =========================
-- CLEANUP
-- =========================

script.Destroying:Connect(
	function()

		CombatAim.ClearReticle(
			reticle
		)


		disconnectCharacterConnections()


		if activeReticleTween then

			activeReticleTween:Cancel()

		end


		RunService:UnbindFromRenderStep(
			CAMERA_OFFSET_PRE_BIND
		)

		RunService:UnbindFromRenderStep(
			CAMERA_OFFSET_POST_BIND
		)


		local camera =
			workspace.CurrentCamera

		if camera
			and lastManualWorldOffset.Magnitude > 0.00001 then

			camera.CFrame =
				camera.CFrame
			- lastManualWorldOffset

		end

		lastManualWorldOffset =
			Vector3.zero


		local humanoid =
			currentHumanoid


		if humanoid
			and humanoid.Parent then

			humanoid.CameraOffset =
				baseCameraOffset

		end

	end
)
