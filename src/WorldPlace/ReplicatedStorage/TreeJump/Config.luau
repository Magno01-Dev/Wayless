--[[
	TreeJump.Config · ModuleScript en ReplicatedStorage.TreeJump
	Todos los valores ajustables, compartidos por cliente y servidor.
	Distancias en studs, ángulos en grados, tiempos en segundos.
]]

return {
	Debug = false,

	-- Zonas (las crea el plugin TreeJumpZones) ----------------------------------
	ZoneTag = "JumpZone",
	MinZoneWidth = 0.8, -- zonas más angostas se ignoran (árboles escalados hacia abajo)
	MinZoneLength = 1.5,

	-- Entrada -------------------------------------------------------------------
	Keys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
	-- Espacios desde el suelo hasta entrar: 1 salto, 2 doble salto, 3 tree jump.
	-- Si el juego no tiene doble salto, pon 2.
	EntryPressCount = 3,
	BufferWindowStart = 0.4, -- desde qué fracción del vuelo un Espacio queda en cola
	LandingGrace = 0.12, -- Espacio un poco tarde tras aterrizar = sigue encadenado
	ContactTime = 0.06, -- los pies tocan la rama este tiempo antes del siguiente salto

	-- Anti accidentes (solo al entrar; encadenar es más permisivo) ---------------
	EntryCone = 20, -- ángulo máximo entre donde apuntas y la rama, al entrar
	ChainCone = 35, -- lo mismo, parado en una rama o encadenando
	ArmTime = 0.12, -- el objetivo debe estar marcado este tiempo antes de aceptar la entrada
	EntryMinMoveDot = 0.3, -- si te mueves, debe ser hacia el árbol (1 = exacto, 0 = de lado)
	CombatHoldTime = 0.2, -- en combate hay que mantener Espacio para entrar
	CombatAttribute = "CombatTagged", -- se lee del Player o del Character

	-- Alcance -------------------------------------------------------------------
	MinDistance = 8,
	MaxDistance = 250,
	MaxRise = 40,
	MaxDrop = 90,

	-- Trayectoria ---------------------------------------------------------------
	DurationPerSqrtStud = 0.065, -- duración = k × √distancia (250 studs ≈ 1 s)
	MinDuration = 0.3,
	MaxDuration = 1.2,
	ArcPerStud = 0.12, -- altura del arco según la distancia horizontal
	MinArc = 2,
	MaxArc = 30,
	TimingWarp = 0.45, -- 0 = velocidad pareja; más alto = impulso fuerte y flotación arriba
	ChainSpeedup = 0.05, -- cada salto encadenado dura 5% menos…
	MaxChainSpeedup = 0.2, -- …hasta 20%
	PathSamples = 8,
	PathRadius = 0.75,
	TrackingGain = 12, -- qué tan fuerte corrige el desvío respecto a la curva
	LandingSnapDistance = 4, -- si al final estás más lejos que esto, no se ajusta: caes
	StuckDistance = 10, -- desvío que se considera "chocó con algo"
	StuckTime = 0.15,

	-- Escaneo de objetivos ------------------------------------------------------
	ScanRate = 15, -- veces por segundo
	MaxVisibilityChecks = 6,

	-- Sensación -----------------------------------------------------------------
	LeanAngle = 18, -- inclinación del cuerpo en el aire
	FovBonus = 12,
	FovTime = 0.2,
	DepthOfField = true,
	DofIntensity = 0.2,
	DofFocusDistance = 15,
	DofInFocusRadius = 25,
	LandingBump = 1.5, -- cabeceo de cámara al quedarse en una rama (grados)
	BranchBend = 1.5, -- cuánto se dobla la rama al pisarla (grados, 0 = apagado)
	LeafCount = 8,
	LeafColors = {
		Wood = { Color3.fromRGB(96, 170, 70), Color3.fromRGB(130, 195, 80), Color3.fromRGB(70, 140, 60) },
		Bamboo = { Color3.fromRGB(150, 200, 90), Color3.fromRGB(180, 215, 110) },
		Snow = { Color3.fromRGB(235, 240, 250), Color3.fromRGB(210, 225, 240) },
	},
	ChakraColor = Color3.fromRGB(110, 190, 255),

	-- Animación y sonido --------------------------------------------------------
	AnimationId = "rbxassetid://101651539767821",
	FreezeBeforeEnd = 0.5, -- en saltos largos se congela la pose este tiempo antes del final
	SoundsEnabled = false,
	SoundVolume = 0.6,
	JumpSoundId = "rbxassetid://97148318607493",
	LandSoundId = "rbxassetid://126830394849063",

	-- Indicador -----------------------------------------------------------------
	IndicatorImage = "rbxassetid://114427377405514",
	IndicatorSize = 52,
	IndicatorTransparency = 0.2,
	NextIndicatorSize = 34,
	NextIndicatorTransparency = 0.55,
	IndicatorFadeIn = 0.045,
	IndicatorFadeOut = 0.1,
	IndicatorSpinSpeed = 125,
	IndicatorPulseSpeed = 2.25,
	IndicatorPulseAmount = 0.055,
	IndicatorPopScale = 0.88,
	IndicatorPopTime = 0.07,

	-- Servidor ------------------------------------------------------------------
	CombatCooldown = 4, -- en combate, segundos entre tree jumps
	ChainGrace = 0.35, -- se acepta el siguiente salto un poco antes de que termine el actual (latencia)
	PositionTolerance = 14, -- diferencia máxima entre la posición del cliente y la del servidor
	ChainPositionTolerance = 6, -- al encadenar: distancia máxima al aterrizaje anterior
	LandingTolerance = 0.75, -- el punto de aterrizaje debe estar sobre la zona
	ServerFinishBuffer = 0.5,
	CorrectPosition = false, -- true = el servidor corrige a quien termine lejos del aterrizaje
	CorrectionThreshold = 12,
}
