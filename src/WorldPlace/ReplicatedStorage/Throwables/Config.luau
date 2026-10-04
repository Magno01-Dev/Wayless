--[[
	Throwables.Config · ModuleScript en ReplicatedStorage.Throwables
	Ajustes generales del sistema de lanzables (cliente y servidor).
	Los valores de cada arma están en Definitions.
]]

return {
	Debug = false,

	-- Teclas ---------------------------------------------------------------------
	ThrowKey = Enum.KeyCode.G, -- tap = lanzar · mantener = cargar
	BagKey = Enum.KeyCode.T, -- mantener = menú radial de la Ninja Bag
	TapThreshold = 0.18, -- soltar antes de esto = tap
	SlotCount = 4,

	-- Animación (la misma del sistema anterior) -----------------------------------
	Animations = {
		Normal = "rbxassetid://85810196265540",
		Sprint = "rbxassetid://121774304926898",
	},
	-- Animaciones en el aire (vacío = usa las de suelo). Pegar aquí los IDs cuando existan.
	AirAnimations = {
		Throw = "", -- lanzamiento aéreo normal
		Heavy = "", -- opcional: lanzamiento aéreo del fuma (ver Definitions.Fuma.AirAnimation)
	},

	-- Marcadores (Animation Events) dentro de cada animación. Si una animación no los tiene,
	-- se usan los frames de respaldo de abajo.
	ReleaseMarker = "Release", -- momento en que sale el proyectil
	HoldMarker = "Hold", -- pose con la mano atrás donde se congela mientras cargas
	AnimationFps = 60,
	ReleaseFrame = 40, -- respaldo si no hay marcador Release
	HoldPoseFrame = 30, -- respaldo si no hay marcador Hold
	NormalSpeed = 1.25,
	CounterAnimationSpeed = 3.0,

	-- Lanzamiento en el aire: la caída se frena un momento (no se congela)
	AirThrow = {
		Enabled = true,
		Pop = 8, -- empujón hacia arriba al empezar (studs/s)
		Recoil = 3, -- retroceso hacia atrás (studs/s)
		HorizontalKeep = 0.3, -- cuánto de la velocidad horizontal se conserva
		GravityScale = 0.12, -- gravedad durante el frenado (0 = flotar, 1 = normal)
		HangTime = 0.35, -- duración del frenado en un tap
		MaxChargeHang = 0.7, -- tope si se carga en el aire; después se cae lento aunque sigas cargando
		ChargeGravityScale = 0.35, -- gravedad al cargar pasado el tope
		RecoverTime = 0.15, -- transición de vuelta a la gravedad normal
	},

	-- Mano derecha ocupada (kenjutsu) → el shuriken carga solo con la izquierda.
	-- El sistema de kenjutsu debe poner alguno de estos atributos en el Character.
	RightHandBusyAttributes = { "RightHandOccupied", "KenjutsuEquipped", "WeaponEquipped" },
	HandSpacing = 3, -- distancia entre manos para los lanzamientos a dos manos

	-- Carga ------------------------------------------------------------------------
	ChargeStatus = "ThrowCharging", -- estado que ralentiza mientras cargas (StatusEffectDefinitions)
	ChargeTolerance = 0.2, -- margen de latencia al validar el tiempo de carga
	MaxChargeTime = 8,

	-- Contraataque defensivo --------------------------------------------------------
	CounterEnabled = true,
	CounterThreatRadius = 3.65,
	CounterWindow = 0.8, -- cuánto hacia adelante se buscan amenazas
	CounterSafety = 0.03,
	CounterMaxLateness = 0.3,

	-- Objetivos y ayuda de apuntado ------------------------------------------------
	TargetTag = "ProjectileTarget", -- dummies / NPCs atacables
	AimHeightOffset = 0.35, -- apuntar un poco sobre el centro del torso
	MaxPredictionSpeed = 60,
	VerticalLeadFactor = 0.3,
	MaxLeadDistance = 12,
	BodyRadius = 1.0,
	BodyBottom = -2.6, -- relativo al HumanoidRootPart
	BodyTop = 2.0,

	-- Red / validación ----------------------------------------------------------------
	GlobalThrowLock = 0.16,
	MaxStartTimeLag = 0.35,
	OriginBaseTolerance = 2.5,
	OriginVelocityWindow = 0.15,
	OriginMaxTolerance = 9,
	TargetTolerance = 4,
	RewindExtra = 0.1, -- retraso de interpolación de los clientes
	MaxRewind = 0.35,
	HistoryLength = 1,

	-- Mundo -----------------------------------------------------------------------------
	StuckTime = 30,
	DeflectGravity = 70,
	VfxFolderName = "ThrowablesVFX",
	IgnoreFolders = { "ThrowablesVFX", "TreeJumpVFX", "VFX" },

	-- Choque
	ClashSoundId = "rbxassetid://91709243524873",
}
