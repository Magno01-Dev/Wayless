--!strict
-- StarterPlayer > StarterPlayerScripts > JutsuController
--
-- Animated Cast Transport + Technique Loadout Input + Bulk Katon + Suiton + Futon + Raiton + Doton
--
-- Technique Slots:
--   1 2 3 4 5 6 7 8 9 0
--
-- Each key resolves TechniqueLoadoutSlot_<N> dynamically.
-- No technique IDs are hardcoded to gameplay hotkeys.
--
-- Compatible con:
--
-- JutsuAnimatedRequest
-- JutsuAnimatedMarker
-- JutsuAnimatedSFX
-- ProjectileSkillshotPolicy

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local UserInputService =
	game:GetService("UserInputService")

local ContextActionService =
	game:GetService("ContextActionService")

local ContentProvider =
	game:GetService("ContentProvider")

local player =
	Players.LocalPlayer

---------------------------------------------------------------------
-- JUTSU SYSTEM
---------------------------------------------------------------------

local jutsuSystem =
	ReplicatedStorage:
	WaitForChild(
		"JutsuSystem"
	)

local shared =
	jutsuSystem:
	WaitForChild(
		"Shared"
	)

local definitions =
	require(
		shared:
		WaitForChild(
			"JutsuDefinitions"
		)
	)

local ProjectileSkillshotPolicy =
	require(
		shared:
		WaitForChild(
			"ProjectileSkillshotPolicy"
		)
	)

local remotes =
	jutsuSystem:
	WaitForChild(
		"Remotes"
	)

local animatedRequest =
	remotes:
	WaitForChild(
		"JutsuAnimatedRequest"
	) :: RemoteFunction

local animatedMarker =
	remotes:
	WaitForChild(
		"JutsuAnimatedMarker"
	) :: RemoteEvent

local animatedSFX =
	remotes:
	WaitForChild(
		"JutsuAnimatedSFX"
	) :: RemoteEvent

---------------------------------------------------------------------
-- SHARED ANIMATIONS
---------------------------------------------------------------------

local HAND_SIGN_ANIMATIONS = {
	Low =
		"rbxassetid://109122450412662",

	Medium =
		"rbxassetid://112260201062309",

	High =
		"rbxassetid://80789406734721",
}

---------------------------------------------------------------------
-- HAND SIGN TIMING (compartido por todos los jutsus)
---------------------------------------------------------------------

-- Velocidad de reproducción de cada sello (antes 0.55 en cada jutsu).
local HAND_SIGN_SPEED =
	0.9

-- Tiempo mínimo entre un sello y el siguiente (antes 0.38).
local HAND_SIGN_MIN_CADENCE =
	0.22

-- El siguiente sello empieza este tiempo antes de que termine el actual
-- (antes se esperaba el final completo + 0.20 s extra).
local HAND_SIGN_OVERLAP =
	0.08

-- Los sellos empiezan al presionar la tecla, sin esperar la respuesta
-- del servidor. Si el servidor rechaza el cast, se cortan.
local OPTIMISTIC_HAND_SIGNS =
	true

-- Máximo que se espera la respuesta del servidor antes de soltar el jutsu.
local CAST_TOKEN_TIMEOUT =
	3

local RELEASE_MARKERS = {
	ReleaseStart =
		"ReleaseStart",

	ProjectileSpawn =
		"ProjectileSpawn",

	RecoveryStart =
		"RecoveryStart",

	CastEnd =
		"CastEnd",
}

---------------------------------------------------------------------
-- SHURIKENJUTSU: animación de lanzar
--
-- Usan la animación de lanzar de los lanzables (Throwables.Config.Animations.Normal).
-- Su marcador "Release" es el momento en que salen los proyectiles; ReleaseStart,
-- RecoveryStart y CastEnd se envían solos (respaldos de playRelease).
---------------------------------------------------------------------

local THROW_RELEASE_ANIMATION =
	"rbxassetid://85810196265540"

local THROW_RELEASE_MARKERS = {
	ProjectileSpawn =
		"Release",
}

local function shurikenjutsuAnimation(
	handSigns: {string}
): any
	return {
		HandSigns =
			handSigns,

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			THROW_RELEASE_ANIMATION,

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.25,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			THROW_RELEASE_MARKERS,
	}
end

---------------------------------------------------------------------
-- GENJUTSU: solo sellos de mano
--
-- Sin animación de salida: al terminar los sellos se envían los marcadores
-- de inmediato (fallbackRelease) y el genjutsu sale en ProjectileSpawn.
---------------------------------------------------------------------

local function genjutsuAnimation(
	handSigns: {string}
): any
	return {
		HandSigns =
			handSigns,

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			nil,

		ReleaseMarkers =
			RELEASE_MARKERS,
	}
end

---------------------------------------------------------------------
-- TAIJUTSU: sin sellos, animaciones del combate cuerpo a cuerpo
--
-- La técnica sale en el marcador indicado de cada animación
-- (los M1 tienen "Hit"; el ataque corriendo tiene "Launch").
-- Sin animación (nil): sale enseguida (fallbackRelease).
---------------------------------------------------------------------

local LUNGE_ANIMATION_ID =
	"rbxassetid://122884818050264"

local M1_1_ANIMATION_ID =
	"rbxassetid://104431855936125"

local M1_3_ANIMATION_ID =
	"rbxassetid://123837934591896"

local M1_4_ANIMATION_ID =
	"rbxassetid://134382076834484"

local M1_5_ANIMATION_ID =
	"rbxassetid://85536933283172"

local function taijutsuAnimation(
	animationId: string?,
	markerName: string?,
	playbackSpeed: number?
): any
	return {
		HandSigns =
			{},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		ReleaseAnimation =
			animationId,

		ReleasePriority =
			Enum.AnimationPriority.Action2,

		ReleasePlaybackSpeed =
			playbackSpeed or 1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			if markerName
			then { ProjectileSpawn = markerName }
			else RELEASE_MARKERS,
	}
end

---------------------------------------------------------------------
-- ENTON: BLACK SPEAR
--
-- 4 sellos más pausados que los normales (técnica avanzada: se oyen y se ven uno a
-- uno); al terminarlos la lanza se forma en la mano (marcador "Form" =
-- ReleaseStart) y sale en "Hit" (ProjectileSpawn, con la mira de ese momento).
-- Con el Susanoo activo, sin sellos (la forma el Susanoo) y más lenta. Sin id
-- publicado, en Studio se usa la KeyframeSequence
-- ReplicatedStorage > Shared > ClanAnimations > EntonSpearThrow.
---------------------------------------------------------------------

local ENTON_SPEAR_THROW_ANIMATION = "" -- rbxassetid de EntonSpearThrow publicada

local function entonSpearAnimation(): any
	local base = genjutsuAnimation({ "High", "Low", "Medium", "High" })
	base.HandSignPlaybackSpeed = 0.7
	base.HandSignMinCadence = 0.3 -- ≈ 0.23 s por sello con el Mangekyō
	base.ReleaseAnimation = if ENTON_SPEAR_THROW_ANIMATION ~= "" then ENTON_SPEAR_THROW_ANIMATION else nil
	base.ReleaseSequence = "EntonSpearThrow"
	base.ReleasePriority = Enum.AnimationPriority.Action2
	base.ReleasePlaybackSpeed = 1
	base.ReleaseFadeTime = 0.08
	base.ReleaseMarkers = { ReleaseStart = "Form", ProjectileSpawn = "Hit" }
	local susanoo = table.clone(base)
	susanoo.HandSigns = {}
	susanoo.ReleasePlaybackSpeed = 0.8 -- "Hit" a 0.75 s, a la vez que el brazo del Susanoo
	base.Variant = function(character: Model): any?
		return if character:GetAttribute("SusanooActive") == true then susanoo else nil
	end
	return base
end

---------------------------------------------------------------------
-- KATON: GŌKA MEKKYAKU
--
-- 4 sellos como Enton: Black Spear y, sin animación de salida, los
-- marcadores se mandan al acabarlos: el servidor hace la pausa de tomar
-- aire antes de soltar el muro. Con el Susanoo activo, sin sellos.
---------------------------------------------------------------------

local function gokaMekkyakuAnimation(): any
	local base = genjutsuAnimation({ "High", "Low", "Medium", "High" })
	base.HandSignPlaybackSpeed = 0.7
	base.HandSignMinCadence = 0.3
	local susanoo = table.clone(base)
	susanoo.HandSigns = {}
	base.Variant = function(character: Model): any?
		return if character:GetAttribute("SusanooActive") == true then susanoo else nil
	end
	return base
end

---------------------------------------------------------------------
-- KAGUTSUCHI: BLACK WALL
--
-- 3 sellos pausados (moldear llamas negras) y, sin animación de salida, los
-- marcadores se mandan al acabarlos: el servidor marca la línea de brasas y
-- el muro brota. Con el Susanoo activo, sin sellos (el servidor hace el windup).
---------------------------------------------------------------------

local function blackWallAnimation(): any
	local base = genjutsuAnimation({ "Low", "Medium", "High" })
	base.HandSignPlaybackSpeed = 0.7
	base.HandSignMinCadence = 0.3
	local susanoo = table.clone(base)
	susanoo.HandSigns = {}
	base.Variant = function(character: Model): any?
		return if character:GetAttribute("SusanooActive") == true then susanoo else nil
	end
	return base
end

---------------------------------------------------------------------
-- YASAKA NO MAGATAMA
--
-- Sin sellos (es el Susanoo). El R6 carga chakra con la mano atrás
-- (marcador "Form" = ReleaseStart: sale el brazo del Susanoo y se forman los
-- magatama) y empuja con la palma al soltar ("Hit" = ProjectileSpawn, a 1.45 s).
-- Con el Susanoo activo va 1.5× más rápido: suelta a 0.97 s, a la vez que su
-- brazo (YasakaBarrage). Sin id publicado, en Studio se usa la KeyframeSequence
-- ReplicatedStorage > Shared > ClanAnimations > YasakaCast.
---------------------------------------------------------------------

local YASAKA_CAST_ANIMATION = "" -- rbxassetid de YasakaCast publicada

local function yasakaMagatamaAnimation(): any
	local base = taijutsuAnimation(nil, nil)
	base.ReleaseAnimation = if YASAKA_CAST_ANIMATION ~= "" then YASAKA_CAST_ANIMATION else nil
	base.ReleaseSequence = "YasakaCast"
	base.ReleasePriority = Enum.AnimationPriority.Action2
	base.ReleasePlaybackSpeed = 1
	base.ReleaseFadeTime = 0.1
	base.ReleaseMarkers = { ReleaseStart = "Form", ProjectileSpawn = "Hit" }
	local susanoo = table.clone(base)
	susanoo.ReleasePlaybackSpeed = 1.5
	base.Variant = function(character: Model): any?
		return if character:GetAttribute("SusanooActive") == true then susanoo else nil
	end
	return base
end

---------------------------------------------------------------------
-- ANIMATION DEFINITIONS
---------------------------------------------------------------------

local animationDefinitions = {

	-----------------------------------------------------------------
	-- FIREBALL
	-----------------------------------------------------------------

	Fireball = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- HOSENKA
	--
	-- Temporalmente usa las mismas animaciones que Fireball.
	-----------------------------------------------------------------

	Hosenka = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- FLAME BREATH
	-- Bulk gameplay pass: temporary Fireball animation set.
	-----------------------------------------------------------------

	FlameBreath = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- FLAME WAVE
	-- Bulk gameplay pass: temporary Fireball animation set.
	-----------------------------------------------------------------

	FlameWave = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- WATER BULLET
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterBullet = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WATER WAVE
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterWave = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WATER WHIP
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterWhip = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WATER PRISON
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterPrison = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- AIR BULLET
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	AirBullet = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WIND BLADE
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	WindBlade = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- GALE PALM
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	GalePalm = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WIND SWEEP
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	WindSweep = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- LIGHTNING BOLT
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	LightningBolt = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- LIGHTNING STREAM
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	LightningStream = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- STATIC BURST
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	StaticBurst = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- LIGHTNING SENBON
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	LightningSenbon = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- STONE SHOT
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	StoneShot = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- EARTH WALL
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	EarthWall = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- EARTH SPIKES
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	EarthSpikes = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- EARTH TREMOR
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	EarthTremor = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			HAND_SIGN_SPEED,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			HAND_SIGN_MIN_CADENCE,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- SHURIKENJUTSU (primera capa)
	-----------------------------------------------------------------

	KageShuriken =
		shurikenjutsuAnimation({ "High" }),

	SofushaSanNoTachi =
		shurikenjutsuAnimation({}),

	KunaiRain =
		shurikenjutsuAnimation({}),

	Soshujin =
		shurikenjutsuAnimation({}),

	-----------------------------------------------------------------
	-- GENJUTSU (primera capa)
	-----------------------------------------------------------------

	GenjutsuKai =
		genjutsuAnimation({ "Low" }),

	Narakumi =
		genjutsuAnimation({ "Medium", "High" }),

	KoriShinchu =
		genjutsuAnimation({ "Low", "High" }),

	IllusionClone =
		genjutsuAnimation({ "Medium", "Low" }),

	-----------------------------------------------------------------
	-- TAIJUTSU (primera capa)
	-----------------------------------------------------------------

	DynamicEntry =
		taijutsuAnimation(LUNGE_ANIMATION_ID, "Launch"),

	KonohaSenpu =
		taijutsuAnimation(M1_5_ANIMATION_ID, "Hit"),

	KonohaReppu =
		taijutsuAnimation(M1_4_ANIMATION_ID, "Hit"),

	CounterStance =
		taijutsuAnimation(nil, nil),

	-----------------------------------------------------------------
	-- KENJUTSU (primera capa) · animaciones de M1 (temporales)
	-----------------------------------------------------------------

	Iai =
		taijutsuAnimation(M1_1_ANIMATION_ID, "Hit", 1.35),

	ChakuraNagashi =
		genjutsuAnimation({ "Medium" }),

	Tsuki =
		taijutsuAnimation(M1_3_ANIMATION_ID, "Hit", 1.15),

	Kesagiri =
		taijutsuAnimation(M1_5_ANIMATION_ID, "Hit", 0.7),

	-----------------------------------------------------------------
	-- NINJUTSU GENERAL (primera capa)
	-----------------------------------------------------------------

	Shunshin =
		genjutsuAnimation({ "Low" }),

	-- Sin sellos: escapar tiene que ser instantáneo
	Nawanuke =
		taijutsuAnimation(nil, nil),

	Henge =
		genjutsuAnimation({ "Medium", "High" }),

	Shosen =
		genjutsuAnimation({ "Low", "Medium" }),

	-----------------------------------------------------------------
	-- CLANES (etapa 1)
	-----------------------------------------------------------------

	-- Dōjutsu: se activan / desactivan al instante
	Sharingan =
		taijutsuAnimation(nil, nil),

	Byakugan =
		taijutsuAnimation(nil, nil),

	-- Sin sellos: es la mirada (el aviso de 0,4 s lo hace el servidor)
	GenjutsuSharingan =
		taijutsuAnimation(nil, nil),

	-- Mangekyō de Itachi: con la mirada, sin sellos
	Amaterasu =
		taijutsuAnimation(nil, nil),

	Tsukuyomi =
		taijutsuAnimation(nil, nil),

	-- Enton: Black Spear: sellos (sin ellos con el Susanoo) y la lanza en la mano
	EntonSpear =
		entonSpearAnimation(),

	-- Katon: Gōka Mekkyaku: sellos (sin ellos con el Susanoo); toma aire en el servidor
	GokaMekkyaku =
		gokaMekkyakuAnimation(),

	-- Yasaka no Magatama: sin sellos; el R6 carga y empuja con la palma
	YasakaMagatama =
		yasakaMagatamaAnimation(),

	-- Kagutsuchi: Black Wall: 3 sellos (sin ellos con el Susanoo)
	BlackWall =
		blackWallAnimation(),

	-- El servidor responde con el jutsu copiado y se juega SU animación
	SharinganCopy =
		taijutsuAnimation(nil, nil),

	UzumakiFuin =
		genjutsuAnimation({ "High" }),

	Kagemane =
		genjutsuAnimation({ "Low" }),
}

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local animationGeneration =
	0

local requestBusy =
	false

---------------------------------------------------------------------
-- COMBAT MODE
---------------------------------------------------------------------

local function enterCombatMode(
	character: Model,
	source: string
)
	local request =
		character:
		FindFirstChild(
			"CombatModeRequest"
		)

	if request
		and request:IsA(
			"BindableEvent"
		) then

		request:Fire(
			"Enter",
			source
		)
	end
end

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local function getAimDirection(
	character: Model
): Vector3?

	local head =
		character:
		FindFirstChild(
			"Head"
		)

	if not head
		or not head:IsA(
			"BasePart"
		) then

		return nil
	end

	local camera =
		workspace.CurrentCamera

	if not camera then
		return nil
	end

	-----------------------------------------------------------------
	-- CENTER CROSSHAIR
	-----------------------------------------------------------------

	local viewport =
		camera.ViewportSize

	local cameraRay =
		camera:
		ViewportPointToRay(
			viewport.X * 0.5,
			viewport.Y * 0.5
		)

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}

	params.IgnoreWater =
		false

	local maxDistance =
		ProjectileSkillshotPolicy
		.CrosshairMaxDistance

	local displacement =
		cameraRay.Direction
		* maxDistance

	local result =
		workspace:Raycast(
			cameraRay.Origin,
			displacement,
			params
		)

	local targetPosition =
		if result
		then result.Position
		else cameraRay.Origin
		+ displacement

	local direction =
		targetPosition
	- head.Position

	if direction.Magnitude <
		0.001 then

		direction =
			camera.CFrame.LookVector
	end

	return direction.Unit
end

---------------------------------------------------------------------
-- ANIMATOR
---------------------------------------------------------------------

local function getAnimator(
	character: Model
): Animator?

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return nil
	end

	local animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)

	if animator then
		return animator
	end

	local found =
		humanoid:
		WaitForChild(
			"Animator",
			2
		)

	if found
		and found:IsA(
			"Animator"
		) then

		return found
	end

	return nil
end

---------------------------------------------------------------------
-- LOAD ANIMATION
---------------------------------------------------------------------

local function loadTrack(
	animator: Animator,
	animationId: string,
	priority: Enum.AnimationPriority
): AnimationTrack?

	local animation =
		Instance.new(
			"Animation"
		)

	animation.AnimationId =
		animationId

	local ok,
		result =
		pcall(
			function()

				return animator:
				LoadAnimation(
					animation
				)
			end
		)

	animation:Destroy()

	if not ok
		or not result then

		warn(
			"[JutsuController] Animation load failed",
			animationId,
			result
		)

		return nil
	end

	local track =
		result :: AnimationTrack

	track.Priority =
		priority

	track.Looped =
		false

	return track
end

---------------------------------------------------------------------
-- TRACK CACHE
--
-- Cada animación se carga una sola vez por Animator y se reutiliza.
-- Antes se cargaba y se destruía en cada sello, y la primera vez
-- había que esperar a que bajara el asset (hasta 1 s por sello).
---------------------------------------------------------------------

local trackCache: {[Animator]: {[string]: AnimationTrack}} =
	setmetatable({}, { __mode = "k" }) :: any

local function getTrack(
	animator: Animator,
	animationId: string,
	priority: Enum.AnimationPriority
): AnimationTrack?

	local cache =
		trackCache[animator]

	if not cache then
		cache = {}
		trackCache[animator] = cache
	end

	local track =
		cache[animationId]

	if not track then
		track =
			loadTrack(
				animator,
				animationId,
				priority
			)

		if not track then
			return nil
		end

		cache[animationId] =
			track
	end

	track.Priority =
		priority

	return track
end

---------------------------------------------------------------------
-- PRELOAD
--
-- Descarga y carga todas las animaciones de sellos y de release al
-- aparecer el personaje, para que el primer jutsu no sea más lento.
---------------------------------------------------------------------

local function preloadAnimations()
	local character =
		player.Character

	if not character then
		return
	end

	local priorities: {[string]: Enum.AnimationPriority} =
		{}

	for _, config in pairs(
		animationDefinitions
		) do

		if typeof(config) ~= "table" then
			continue
		end

		for _, signName in ipairs(
			config.HandSigns or {}
			) do

			local id =
				config.HandSignAnimations
				and config.HandSignAnimations[signName]

			if typeof(id) == "string" then
				priorities[id] =
					config.HandSignPriority
					or Enum.AnimationPriority.Action
			end
		end

		if typeof(config.ReleaseAnimation) == "string" then
			priorities[config.ReleaseAnimation] =
				config.ReleasePriority
				or Enum.AnimationPriority.Action
		end
	end

	local animations: {Instance} =
		{}

	for id in pairs(priorities) do
		local animation =
			Instance.new("Animation")

		animation.AnimationId =
			id

		table.insert(
			animations,
			animation
		)
	end

	pcall(
		function()
			ContentProvider:PreloadAsync(
				animations
			)
		end
	)

	for _, animation in ipairs(animations) do
		animation:Destroy()
	end

	local animator =
		getAnimator(
			character
		)

	if not animator then
		return
	end

	for id, priority in pairs(priorities) do
		getTrack(
			animator,
			id,
			priority
		)
	end
end

---------------------------------------------------------------------
-- LOCAL CAST
--
-- Un cast local puede empezar antes de que el servidor responda.
-- Token = nil mientras no llega la respuesta.
---------------------------------------------------------------------

type LocalCast = {
	JutsuId: string,
	Token: string?,
	Rejected: boolean,
	PendingSignSFX: number,
}

local localCast: LocalCast? =
	nil

local function sendSignSFX(
	cast: LocalCast
)
	if cast.Token then
		animatedSFX:FireServer(
			cast.JutsuId,
			cast.Token,
			"HandSign"
		)
	else
		-- Se mandan en cuanto el servidor confirme el cast (uno por sello)
		cast.PendingSignSFX +=
			1
	end
end

local function waitForToken(
	cast: LocalCast,
	generation: number
): string?

	local deadline =
		os.clock()
		+ CAST_TOKEN_TIMEOUT

	while cast.Token == nil
		and not cast.Rejected
		and generation ==
		animationGeneration
		and os.clock() <
		deadline do

		task.wait()
	end

	if cast.Rejected
		or generation ~=
		animationGeneration then

		return nil
	end

	return cast.Token
end

---------------------------------------------------------------------
-- PLAY HAND SIGN
---------------------------------------------------------------------

local function playOneShot(
	animator: Animator,
	cast: LocalCast,
	animationId: string,
	priority: Enum.AnimationPriority,
	fadeTime: number,
	playbackSpeed: number,
	fallbackDuration: number,
	minCadence: number,
	generation: number
): boolean

	if generation ~=
		animationGeneration then

		return false
	end

	local track =
		getTrack(
			animator,
			animationId,
			priority
		)

	if not track then
		return false
	end

	local startedAt =
		os.clock()

	-----------------------------------------------------------------
	-- UNIVERSAL HAND SIGN SFX
	-----------------------------------------------------------------

	sendSignSFX(
		cast
	)

	track:Play(
		fadeTime,
		1,
		playbackSpeed
	)

	-----------------------------------------------------------------
	-- WAIT FOR LENGTH (con la precarga normalmente ya está disponible)
	-----------------------------------------------------------------

	local lengthDeadline =
		os.clock()
		+ 0.5

	while track.Length <= 0
		and os.clock() <
		lengthDeadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	local waitTime =
		fallbackDuration

	if track.Length > 0 then

		waitTime =
			track.Length
			/ math.max(
				playbackSpeed,
				0.01
			)
		- HAND_SIGN_OVERLAP
	end

	-----------------------------------------------------------------
	-- WAIT FOR SIGN (respetando la cadencia mínima)
	-----------------------------------------------------------------

	local deadline =
		startedAt
		+ math.max(
			minCadence,
			waitTime
		)

	while os.clock() <
		deadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	if track.IsPlaying then

		track:Stop(
			fadeTime
		)
	end

	return generation ==
		animationGeneration
end

---------------------------------------------------------------------
-- SEND MARKER
---------------------------------------------------------------------

local function sendMarker(
	jutsuId: string,
	token: string,
	markerName: string,
	generation: number
)
	if generation ~=
		animationGeneration then

		return
	end

	local markerPayload: any? =
		nil

	-----------------------------------------------------------------
	-- REFRESH AIM AT THE ACTUAL RELEASE FRAME
	-----------------------------------------------------------------

	if markerName ==
		"ProjectileSpawn" then

		local character =
			player.Character

		if character
			and character.Parent then

			local freshDirection =
				getAimDirection(
					character
				)

			if freshDirection then

				markerPayload = {
					Direction =
						freshDirection,
				}
			end
		end
	end

	animatedMarker:FireServer(
		jutsuId,
		token,
		markerName,
		markerPayload
	)
end

---------------------------------------------------------------------
-- RELEASE FALLBACK
---------------------------------------------------------------------

local function fallbackRelease(
	jutsuId: string,
	token: string,
	generation: number
)
	sendMarker(
		jutsuId,
		token,
		"ReleaseStart",
		generation
	)

	task.wait(
		0.15
	)

	sendMarker(
		jutsuId,
		token,
		"ProjectileSpawn",
		generation
	)

	sendMarker(
		jutsuId,
		token,
		"RecoveryStart",
		generation
	)

	task.wait(
		0.10
	)

	sendMarker(
		jutsuId,
		token,
		"CastEnd",
		generation
	)
end

---------------------------------------------------------------------
-- RELEASE ANIMATION
---------------------------------------------------------------------

-- Animación de salida sin publicar: en Studio se registra su KeyframeSequence
-- (ReplicatedStorage > Shared > ClanAnimations > ReleaseSequence); publicada, basta el id
local registeredReleaseSequences: {[string]: string} =
	{}

local function releaseAnimationOf(
	config: any
): string?

	if typeof(config.ReleaseAnimation) == "string"
		and config.ReleaseAnimation ~= "" then

		return config.ReleaseAnimation
	end

	local sequenceName =
		config.ReleaseSequence

	if typeof(sequenceName) ~= "string"
		or not game:GetService("RunService"):IsStudio() then

		return nil
	end

	if registeredReleaseSequences[sequenceName] then
		return registeredReleaseSequences[sequenceName]
	end

	local shared =
		ReplicatedStorage:FindFirstChild("Shared")

	local folder =
		shared and shared:FindFirstChild("ClanAnimations")

	local sequence =
		folder and folder:FindFirstChild(sequenceName)

	if not sequence
		or not sequence:IsA("KeyframeSequence") then

		return nil
	end

	local registerOk, registered =
		pcall(function()
			return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(sequence)
		end)

	if registerOk
		and typeof(registered) == "string" then

		registeredReleaseSequences[sequenceName] =
			registered

		return registered
	end

	return nil
end

local function playRelease(
	animator: Animator,
	jutsuId: string,
	token: string,
	config: any,
	generation: number
)
	local animationId =
		releaseAnimationOf(
			config
		)

	if typeof(animationId) ~=
		"string" then

		fallbackRelease(
			jutsuId,
			token,
			generation
		)

		return
	end

	local track =
		getTrack(
			animator,
			animationId,
			config.ReleasePriority
			or Enum.AnimationPriority.Action
		)

	if not track then

		fallbackRelease(
			jutsuId,
			token,
			generation
		)

		return
	end

	local markerConnections:
		{RBXScriptConnection} =
		{}

	local sent:
		{[string]: boolean} =
		{}

	local function emit(
		semantic: string
	)
		if sent[
			semantic
			] == true then

			return
		end

		sent[
		semantic
		] =
			true

		sendMarker(
			jutsuId,
			token,
			semantic,
			generation
		)
	end

	for semantic,
		authoredName in pairs(
			config.ReleaseMarkers
		) do

		table.insert(
			markerConnections,

			track:
				GetMarkerReachedSignal(
					authoredName
				):
				Connect(
					function()

						emit(
							semantic
						)
					end
				)
		)
	end

	local stopped =
		false

	table.insert(
		markerConnections,

		track.Stopped:
			Connect(
				function()

					-- El track se reutiliza: ignora un Stopped atrasado de un cast anterior
					if not track.IsPlaying then
						stopped =
						true
					end
				end
			)
	)

	track:Play(
		config.ReleaseFadeTime
			or 0.04,
		1,
		config.ReleasePlaybackSpeed
			or 1
	)

	-----------------------------------------------------------------
	-- RELEASE START SAFETY FALLBACK
	-----------------------------------------------------------------

	task.delay(
		0.20,
		function()

			if generation ==
				animationGeneration
				and sent.ReleaseStart
				~= true then

				emit(
					"ReleaseStart"
				)
			end
		end
	)

	-----------------------------------------------------------------
	-- WAIT FOR ANIMATION
	-----------------------------------------------------------------

	local lengthDeadline =
		os.clock()
		+ 1

	while track.Length <= 0
		and os.clock() <
		lengthDeadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	local maxWait =
		if track.Length > 0
		then track.Length
		/ math.max(
			config.ReleasePlaybackSpeed
			or 1,
			0.01
		)
		+ 0.75
		else 2.5

	local deadline =
		os.clock()
		+ maxWait

	while not stopped
		and os.clock() <
		deadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	-----------------------------------------------------------------
	-- MARKER SAFETY FALLBACKS
	-----------------------------------------------------------------

	if generation ==
		animationGeneration then

		if sent.ReleaseStart ~=
			true then

			emit(
				"ReleaseStart"
			)
		end

		if sent.ProjectileSpawn ~=
			true then

			emit(
				"ProjectileSpawn"
			)
		end

		if sent.RecoveryStart ~=
			true then

			emit(
				"RecoveryStart"
			)
		end

		if sent.CastEnd ~=
			true then

			emit(
				"CastEnd"
			)
		end
	end

	for _, connection in ipairs(
		markerConnections
		) do

		connection:Disconnect()
	end

	if track.IsPlaying then

		track:Stop(
			config.ReleaseFadeTime
				or 0.04
		)
	end
end

---------------------------------------------------------------------
-- PLAY COMPLETE CAST
---------------------------------------------------------------------

local function playCastAnimations(
	cast: LocalCast,
	generation: number
)
	local jutsuId =
		cast.JutsuId

	local config =
		animationDefinitions[
	jutsuId
	]

	if typeof(config) ~=
		"table" then

		warn(
			"[JutsuController] Missing animation config:",
			jutsuId
		)

		return
	end

	local character =
		player.Character

	if not character
		or not character.Parent then

		return
	end

	-- Variante según el estado del personaje (p. ej. Enton: Black Spear con el Susanoo)
	if typeof(config.Variant) == "function" then
		local variantOk, variant =
			pcall(config.Variant, character)

		if variantOk
			and typeof(variant) == "table" then

			config =
				variant
		end
	end

	local animator =
		getAnimator(
			character
		)

	if not animator then

		local token =
			waitForToken(
				cast,
				generation
			)

		if token then
			fallbackRelease(
				jutsuId,
				token,
				generation
			)
		end

		return
	end

	-----------------------------------------------------------------
	-- HAND SIGNS
	-----------------------------------------------------------------

	-- Sellos más rápidos (atributo SealSpeedMultiplier del personaje, p. ej. el
	-- Sharingan según sus tomoe; el servidor deja salir el jutsu antes en proporción)
	local sealSpeedValue =
		character:GetAttribute(
			"SealSpeedMultiplier"
		)

	local sealSpeed =
		if typeof(sealSpeedValue) == "number"
			and sealSpeedValue >= 1
			and sealSpeedValue <= 3
		then sealSpeedValue
		else 1

	for _, signName in ipairs(
		config.HandSigns
		) do

		if generation ~=
			animationGeneration then

			return
		end

		local animationId =
			config.HandSignAnimations[
		signName
		]

		if typeof(animationId) ==
			"string" then

			local completed =
				playOneShot(
					animator,
					cast,
					animationId,
					config.HandSignPriority
					or Enum.AnimationPriority.Action,
					config.HandSignFadeTime
					or 0.04,
					(config.HandSignPlaybackSpeed
					or HAND_SIGN_SPEED)
					* sealSpeed,
					(config.HandSignFallbackDuration
					or 0.30)
					/ sealSpeed,
					(config.HandSignMinCadence
					or HAND_SIGN_MIN_CADENCE)
					/ sealSpeed,
					generation
				)

			if not completed then
				break
			end
		end
	end

	-----------------------------------------------------------------
	-- WAIT FOR SERVER (solo si respondió más lento que los sellos)
	-----------------------------------------------------------------

	local token =
		waitForToken(
			cast,
			generation
		)

	if not token then
		return
	end

	-----------------------------------------------------------------
	-- END HAND SIGNS SOUND
	-----------------------------------------------------------------

	animatedSFX:FireServer(
		jutsuId,
		token,
		"HandSignsEnd"
	)

	-----------------------------------------------------------------
	-- RELEASE
	-----------------------------------------------------------------

	playRelease(
		animator,
		jutsuId,
		token,
		config,
		generation
	)
end

local function runCast(
	cast: LocalCast,
	generation: number
)
	playCastAnimations(
		cast,
		generation
	)

	if localCast == cast then
		localCast =
			nil
	end
end

local function startLocalCast(
	jutsuId: string,
	token: string?
): LocalCast

	animationGeneration +=
		1

	local cast: LocalCast = {
		JutsuId =
			jutsuId,

		Token =
			token,

		Rejected =
			false,

		PendingSignSFX =
			0,
	}

	localCast =
		cast

	task.spawn(
		runCast,
		cast,
		animationGeneration
	)

	return cast
end

-- El servidor rechazó el cast: se cortan los sellos que ya empezaron
local function cancelLocalCast(
	cast: LocalCast?
)
	if not cast then
		return
	end

	cast.Rejected =
		true

	if localCast == cast then

		animationGeneration +=
			1

		localCast =
			nil
	end
end

-- Evita empezar sellos que el servidor seguro va a rechazar
local function canStartOptimistic(
	character: Model,
	jutsuId: string
): boolean

	local serverNow =
		workspace:GetServerTimeNow()

	if character:GetAttribute(
		"JutsuCasting"
		) == true then

		local castEndsAt =
			character:GetAttribute(
				"JutsuCastEndsAt"
			)

		if typeof(castEndsAt) ~= "number"
			or castEndsAt > serverNow then

			return false
		end
	end

	local cooldownEndsAt =
		character:GetAttribute(
			"CoreCooldown_"
			.. jutsuId
			.. "_EndsAt"
		)

	if typeof(cooldownEndsAt) == "number"
		and cooldownEndsAt > serverNow + 0.05 then

		return false
	end

	return true
end

---------------------------------------------------------------------
-- REQUEST
---------------------------------------------------------------------

local function requestTechniqueSlotCast(
	slotIndex: number
)
	if requestBusy
		or localCast then

		return
	end

	if player:GetAttribute(
		"TechniqueLoadoutReady"
		) ~= true then

		return
	end

	local expectedTechniqueId =
		player:GetAttribute(
			"TechniqueLoadoutSlot_"
			.. tostring(slotIndex)
		)

	if typeof(expectedTechniqueId) ~= "string"
		or expectedTechniqueId == "" then

		return
	end

	-- Local deployment preflight only.
	-- The technique ID is NOT sent to the server.
	-- Bulk jutsus may carry their authoritative gameplay config in Module.Config.
	if typeof(
		animationDefinitions[
		expectedTechniqueId
		]
		) ~= "table" then

		warn(
			"[JutsuController] Jutsu has no animation configuration:",
			expectedTechniqueId
		)

		return
	end

	local character =
		player.Character

	if not character
		or not character.Parent then

		return
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return
	end

	local direction =
		getAimDirection(
			character
		)

	if not direction then
		return
	end

	requestBusy = true

	-----------------------------------------------------------------
	-- OPTIMISTIC START
	--
	-- Los sellos empiezan ya, mientras el servidor valida.
	-----------------------------------------------------------------

	local cast: LocalCast? =
		nil

	if OPTIMISTIC_HAND_SIGNS
		and canStartOptimistic(
			character,
			expectedTechniqueId
		) then

		cast =
			startLocalCast(
				expectedTechniqueId,
				nil
			)
	end

	local invokeOk,
		response =
		pcall(
			function()

				return animatedRequest:
				InvokeServer(
					{
						SlotIndex = slotIndex,
					},
					{
						Direction = direction,
					}
				)
			end
		)

	requestBusy = false

	if not invokeOk then

		cancelLocalCast(
			cast
		)

		warn(
			"[JutsuController] InvokeServer failed for slot:",
			slotIndex,
			response
		)

		return
	end

	if typeof(response) ~= "table" then

		cancelLocalCast(
			cast
		)

		warn(
			"[JutsuController] Invalid response for slot:",
			slotIndex
		)

		return
	end

	if response.Accepted ~= true then

		cancelLocalCast(
			cast
		)

		-- Cooldown / ya lanzando / sin chakra son rechazos normales, no errores
		-- "Toggled": técnicas de modo (Sharingan, Byakugan) que se apagan al volver a pulsarlas
		if response.Reason ~= "Cooldown"
			and response.Reason ~= "AlreadyCasting"
			and response.Reason ~= "RequestThrottle"
			and response.Reason ~= "Toggled" then

			warn(
				"[JutsuController] REJECTED:",
				"Slot " .. tostring(slotIndex),
				response.Reason
			)
		end

		return
	end

	local jutsuId =
		response.JutsuId

	if typeof(jutsuId) ~= "string"
		or jutsuId == "" then

		cancelLocalCast(
			cast
		)

		warn(
			"[JutsuController] Accepted response missing JutsuId:",
			slotIndex
		)

		return
	end

	if typeof(
		animationDefinitions[
		jutsuId
		]
		) ~= "table" then

		cancelLocalCast(
			cast
		)

		warn(
			"[JutsuController] Server resolved jutsu missing local config:",
			slotIndex,
			jutsuId
		)

		return
	end

	if typeof(
		response.CastToken
		) ~= "string" then

		cancelLocalCast(
			cast
		)

		return
	end

	enterCombatMode(
		character,
		"Jutsu:" .. jutsuId
	)

	-----------------------------------------------------------------
	-- CONFIRM
	-----------------------------------------------------------------

	if cast
		and not cast.Rejected
		and localCast == cast
		and cast.JutsuId == jutsuId then

		cast.Token =
			response.CastToken

		if cast.PendingSignSFX > 0 then

			local pending =
				cast.PendingSignSFX

			cast.PendingSignSFX =
				0

			-- Los sellos que pasaron antes de la confirmación suenan seguidos, no a la vez
			for index = 1, pending do
				task.delay(
					(index - 1) * 0.1,
					function()
						animatedSFX:FireServer(
							jutsuId,
							response.CastToken,
							"HandSign"
						)
					end
				)
			end
		end

		return
	end

	-- Sin inicio optimista (o el slot cambió mientras tanto): empezar ahora
	cancelLocalCast(
		cast
	)

	startLocalCast(
		jutsuId,
		response.CastToken
	)
end

---------------------------------------------------------------------
-- DESPERTAR DEL CLAN (tecla Z)
--
-- El servidor decide la técnica según tu clan (Sharingan, Byakugan…):
-- no ocupa slot. Pulsar otra vez lo apaga. Se envía aunque estés haciendo
-- sellos de otro jutsu: así apagarlo siempre responde (encenderlo, el
-- servidor lo rechaza mientras lanzas otra cosa).
---------------------------------------------------------------------

local AWAKEN_KEY =
	Enum.KeyCode.Z

local function requestAwakenCast(mode: string?)
	if requestBusy then
		return
	end

	local character =
		player.Character

	if not character
		or not character.Parent then

		return
	end

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	local direction =
		getAimDirection(
			character
		)
		or (root and root:IsA("BasePart") and root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)

	requestBusy = true

	local invokeOk,
		response =
		pcall(
			function()
				return animatedRequest:InvokeServer(
					{
						Awaken = true,
						Mode = mode,
					},
					{
						Direction = direction,
					}
				)
			end
		)

	requestBusy = false

	-- Rechazos normales (apagado, cooldown, sin despertar…): los avisa ClanClient con iconos
	if not invokeOk
		or typeof(response) ~= "table"
		or response.Accepted ~= true then

		return
	end

	local jutsuId =
		response.JutsuId

	if typeof(jutsuId) ~= "string"
		or typeof(animationDefinitions[jutsuId]) ~= "table"
		or typeof(response.CastToken) ~= "string" then

		return
	end

	cancelLocalCast(
		localCast
	)

	startLocalCast(
		jutsuId,
		response.CastToken
	)
end

---------------------------------------------------------------------
-- TECHNIQUE LOADOUT INPUT
---------------------------------------------------------------------

local TECHNIQUE_SLOT_KEYS: {[number]: Enum.KeyCode} = {
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
	[5] = Enum.KeyCode.Five,
	[6] = Enum.KeyCode.Six,
	[7] = Enum.KeyCode.Seven,
	[8] = Enum.KeyCode.Eight,
	[9] = Enum.KeyCode.Nine,
	[10] = Enum.KeyCode.Zero,
}

local TECHNIQUE_INPUT_PRIORITY =
	3000

local function techniqueSlotAttributeName(
	slotIndex: number
): string
	return "TechniqueLoadoutSlot_"
		.. tostring(
			slotIndex
		)
end

local function canUseTechniqueHotkeys(): boolean
	if UserInputService:
		GetFocusedTextBox() then

		return false
	end

	if player:GetAttribute(
		"InventoryOpen"
		) == true then

		return false
	end

	if player:GetAttribute(
		"NinjaBagLoadoutOpen"
		) == true then

		return false
	end

	return true
end

local function requestTechniqueSlot(
	slotIndex: number
)
	task.spawn(
		requestTechniqueSlotCast,
		slotIndex
	)
end

for slotIndex = 1, 10 do
	local boundSlotIndex =
		slotIndex

	local keyCode =
		TECHNIQUE_SLOT_KEYS[
	boundSlotIndex
	]

	local actionName =
		"WAYLESS_TechniqueSlot_"
		.. tostring(
			boundSlotIndex
		)

	ContextActionService:
		BindActionAtPriority(
			actionName,
			function(
				_actionName: string,
				inputState: Enum.UserInputState,
				_inputObject: InputObject
			): Enum.ContextActionResult

				if inputState ~=
					Enum.UserInputState.Begin then

					return Enum.ContextActionResult.Pass
				end

				if not canUseTechniqueHotkeys() then

					return Enum.ContextActionResult.Pass
				end

				requestTechniqueSlot(
					boundSlotIndex
				)

				-- Technique slot keys own 1-0 while gameplay input is active.
				-- This prevents Roblox Backpack hotkeys from also firing.
				return Enum.ContextActionResult.Sink
			end,
			false,
			TECHNIQUE_INPUT_PRIORITY,
			keyCode
		)
end

-- Z: toque = Sharingan · doble toque = Mangekyō · mantener = Susanoo. Sin Mangekyō despertado
-- (ClanAwakenStage < 4) el toque responde al soltar, sin esperar al doble toque.
local AWAKEN_DOUBLE_TAP_WINDOW = 0.25
local AWAKEN_HOLD_SECONDS = 0.55

local awakenPressToken = 0
local awakenHoldFired = false
local awakenPendingTap = false

local function hasMangekyo(): boolean
	local stage = player:GetAttribute("ClanAwakenStage")
	return typeof(stage) == "number" and stage >= 4
end

ContextActionService:
	BindActionAtPriority(
		"WAYLESS_ClanAwaken",
		function(
			_actionName: string,
			inputState: Enum.UserInputState,
			_inputObject: InputObject
		): Enum.ContextActionResult

			if inputState ==
				Enum.UserInputState.Begin then

				if not canUseTechniqueHotkeys() then

					return Enum.ContextActionResult.Pass
				end

				awakenPressToken += 1
				local token = awakenPressToken
				awakenHoldFired = false

				-- Mantener: Susanoo (solo con Mangekyō)
				if hasMangekyo() then
					task.delay(
						AWAKEN_HOLD_SECONDS,
						function()
							if awakenPressToken == token
								and not awakenHoldFired
								and UserInputService:IsKeyDown(AWAKEN_KEY) then

								awakenHoldFired = true
								awakenPendingTap = false
								task.spawn(requestAwakenCast, "Susanoo")
							end
						end
					)
				end

				return Enum.ContextActionResult.Sink
			end

			if inputState ~=
				Enum.UserInputState.End then

				return Enum.ContextActionResult.Pass
			end

			-- Al soltar: si ya saltó el Susanoo, nada más
			if awakenHoldFired then
				return Enum.ContextActionResult.Sink
			end

			if not hasMangekyo() then
				task.spawn(requestAwakenCast, "Sharingan")
				return Enum.ContextActionResult.Sink
			end

			-- Segundo toque dentro de la ventana: Mangekyō
			if awakenPendingTap then
				awakenPendingTap = false
				task.spawn(requestAwakenCast, "Mangekyo")
				return Enum.ContextActionResult.Sink
			end

			-- Primer toque: espera por si llega el segundo
			awakenPendingTap = true
			local token = awakenPressToken
			task.delay(
				AWAKEN_DOUBLE_TAP_WINDOW,
				function()
					if awakenPendingTap and awakenPressToken == token then
						awakenPendingTap = false
						task.spawn(requestAwakenCast, "Sharingan")
					end
				end
			)

			return Enum.ContextActionResult.Sink
		end,
		false,
		TECHNIQUE_INPUT_PRIORITY,
		AWAKEN_KEY
	)

---------------------------------------------------------------------
-- RESET
---------------------------------------------------------------------

player.CharacterAdded:
	Connect(
		function()

			animationGeneration +=
			1

			requestBusy =
			false

			localCast =
			nil

			task.spawn(
				preloadAnimations
			)
		end
	)

task.spawn(
	preloadAnimations
)

print(
	"[JutsuController] READY v16 BulkDoton"
		.. " | TechniqueSlots=1-0"
		.. " | ClientSends=SlotIndexOnly"
		.. " | ServerResolvesTechnique=ON"
		.. " | HardcodedJutsuKeys=OFF"
		.. " | BulkKaton=FlameBreath+FlameWave"
		.. " | BulkSuiton=WaterBullet+WaterWave+WaterWhip+WaterPrison"
		.. " | BulkFuton=AirBullet+WindBlade+GalePalm+WindSweep"
		.. " | BulkRaiton=LightningBolt+LightningStream+StaticBurst+LightningSenbon"
		.. " | BulkDoton=StoneShot+EarthWall+EarthSpikes+EarthTremor"
		.. " | SharedDefinitionPreflight=OPTIONAL"
		.. " | AnimatedTransport=ON"
		.. " | ReleaseAimRefresh=ON"
)
