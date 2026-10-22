--!strict
-- SusanooConfig (ReplicatedStorage > Susanoo > SusanooConfig)
-- Ajustes compartidos del Susanoo imperfecto: animaciones, aspecto y el combo de cada arma. Lo leen SusanooClient (StarterPlayerScripts) y SusanooServer (ServerScriptService).
--
-- Dos versiones del rig: brazo izquierdo (ImperfectLeft) y derecho (ImperfectRight, reflejo exacto).
-- Side elige cuál usa el juego. Cada lado tiene su modelo y sus animaciones (las del derecho son las
-- del izquierdo reflejadas); ArmSign dice hacia qué lado del HumanoidRootPart queda el brazo.
-- Animaciones: se editan sobre el rig de cada lado; el Animation Editor las guarda en
-- ServerStorage > RBX_ANIMSAVES > ImperfectLeft / ImperfectRight y el juego usa la copia de
-- ReplicatedStorage > Susanoo > AnimationsLeft / AnimationsRight. Mientras un id esté vacío, en
-- Studio se reproduce la KeyframeSequence; en el juego publicado hace falta el id
-- (Animation Editor > Publish to Roblox y pegar aquí "rbxassetid://...").

local SusanooConfig = {}

SusanooConfig.Side = "Right"
SusanooConfig.Sides = {
	Left = {
		Model = "ImperfectLeft",
		AnimationFolder = "AnimationsLeft",
		AnimationIds = {
			Idle = "rbxassetid://84259171649617",
			Swing1 = "rbxassetid://133235158475614",
			Swing2 = "rbxassetid://92099768315698",
			Hammer = "rbxassetid://74300588160098",
			SwordCut1 = "",
			SwordCut2 = "",
			SwordCut3 = "",
			SwordThrust = "",
			ShieldBash1 = "",
			ShieldBash2 = "",
			ShieldSlam = "",
			ShieldGuard = "",
			Throw = "",
			YasakaThrow = "",
			YasakaBarrage = "",
		},
		ArmSign = -1,
	},
	Right = {
		Model = "ImperfectRight",
		AnimationFolder = "AnimationsRight",
		AnimationIds = {
			Idle = "rbxassetid://119810036594975",
			Swing1 = "rbxassetid://135898274413987",
			Swing2 = "rbxassetid://127483460831636",
			Hammer = "rbxassetid://122452389305960",
			SwordCut1 = "",
			SwordCut2 = "",
			SwordCut3 = "",
			SwordThrust = "",
			ShieldBash1 = "",
			ShieldBash2 = "",
			ShieldSlam = "",
			ShieldGuard = "",
			Throw = "",
			YasakaThrow = "",
			YasakaBarrage = "",
		},
		ArmSign = 1,
	},
}

-- KeyframeSequence de ReplicatedStorage > Susanoo > Animations para cada animación
SusanooConfig.AnimationSequences = {
	Idle = "SusanooIdle",
	Swing1 = "SusanooSwing1",
	Swing2 = "SusanooSwing2",
	Hammer = "SusanooHammer",
	SwordCut1 = "SusanooSwordCut1",
	SwordCut2 = "SusanooSwordCut2",
	SwordCut3 = "SusanooSwordCut3",
	SwordThrust = "SusanooSwordThrust",
	ShieldBash1 = "SusanooShieldBash1",
	ShieldBash2 = "SusanooShieldBash2",
	ShieldSlam = "SusanooShieldSlam",
	ShieldGuard = "SusanooShieldGuard",
	-- Gesto de lanzar del brazo (Enton: Black Spear con el Susanoo): forma la lanza arriba y la
	-- suelta en el marcador "Hit" (0.75 s)
	Throw = "SusanooThrow",
	-- Yasaka no Magatama: brazo parcial que forma y lanza uno ("Hit" a 0.9 s) y, con el Susanoo
	-- activo, tres seguidos ("Hit" a 0.6 / 0.9 / 1.2 s)
	YasakaThrow = "SusanooYasakaThrow",
	YasakaBarrage = "SusanooYasakaBarrage",
}

-- Antiguo (un color por tipo de Mangekyō): ya no se usa. El color propio de cada jugador está en
-- ReplicatedStorage > Shared > MangekyoCatalog.Colors
SusanooConfig.Colors = {
	Itachi = Color3.fromRGB(235, 50, 35),
	Obito = Color3.fromRGB(70, 200, 255),
	Sasuke = Color3.fromRGB(150, 70, 230),
	Madara = Color3.fromRGB(70, 110, 255),
	Shisui = Color3.fromRGB(70, 215, 110),
}
SusanooConfig.DefaultType = "Itachi"

SusanooConfig.FadeIn = 0.35
SusanooConfig.FadeOut = 0.3
SusanooConfig.HighlightFill = 0.88
SusanooConfig.HighlightOutline = 0.12
-- Transparencia extra para tu propio Susanoo, para que no tape la vista
SusanooConfig.LocalExtraTransparency = 0.15
SusanooConfig.LocalHighlightFill = 0.95
SusanooConfig.LocalHighlightOutline = 0.12
SusanooConfig.LocalParticleRate = 0.5
SusanooConfig.LocalAuraOpacity = 0.6

-- Combo de cada arma (MangekyoCatalog.Weapons; sustituye al M1 mientras el modo Susanoo está
-- activo). Mismo daño por segundo más o menos: cambia el estilo, no la fuerza.
--   Fist    3 golpes: barrido, revés y martillazo que tumba
--   Sword   más alcance y un golpe más, cada corte hace menos; cierra con una estocada larga
--   Shield  golpes lentos que castigan la guardia y cierran tumbando; al bloquear con el Mangekyō
--           sube el escudo (Guard) y contraataca al que te pegue cuerpo a cuerpo (Counter)
-- Cada golpe:
--   HitTime     segundos desde el inicio del golpe hasta el impacto (marcador "Hit" de la animación)
--   NextAfter   segundos hasta poder lanzar el siguiente golpe
--   Hitbox      opcional, si no la del arma. Size y Offset relativos al HumanoidRootPart; Offset.X
--               positivo = hacia el lado del brazo (Sides[Side].ArmSign lo refleja)
-- Con el brazo derecho las animaciones van reflejadas.
SusanooConfig.Weapons = {
	Fist = {
		Hitbox = { Size = Vector3.new(9, 7, 7), Offset = Vector3.new(1, 0, -4.5) },
		Combo = {
			{
				Animation = "Swing1",
				HitTime = 0.26,
				NextAfter = 0.42,
				Damage = 8,
				GuardDamage = 35,
				Hitstun = 0.5,
				Knockback = 14,
			},
			{
				Animation = "Swing2",
				HitTime = 0.28,
				NextAfter = 0.44,
				Damage = 8,
				GuardDamage = 35,
				Hitstun = 0.5,
				Knockback = 14,
			},
			{
				Animation = "Hammer",
				HitTime = 0.36,
				NextAfter = 1.0, -- cierre del combo
				Damage = 12,
				GuardDamage = 50,
				Heavy = true,
				Ragdoll = { Horizontal = 30, Vertical = 4, Duration = 0.75 },
			},
		},
	},
	Sword = {
		Hitbox = { Size = Vector3.new(12, 7, 11), Offset = Vector3.new(0.5, 0, -6.5) },
		Combo = {
			{
				Animation = "SwordCut1", -- tajo bajando de derecha a izquierda
				HitTime = 0.24,
				NextAfter = 0.38,
				Damage = 6,
				GuardDamage = 28,
				Hitstun = 0.45,
				Knockback = 8,
			},
			{
				Animation = "SwordCut2", -- revés subiendo
				HitTime = 0.24,
				NextAfter = 0.38,
				Damage = 6,
				GuardDamage = 28,
				Hitstun = 0.45,
				Knockback = 8,
			},
			{
				Animation = "SwordCut3", -- tajo vertical desde arriba
				HitTime = 0.28,
				NextAfter = 0.42,
				Damage = 6,
				GuardDamage = 28,
				Hitstun = 0.5,
				Knockback = 10,
				Hitbox = { Size = Vector3.new(8, 8, 12), Offset = Vector3.new(2.5, 0, -7) },
			},
			{
				Animation = "SwordThrust", -- estocada: largo alcance, empuja lejos
				HitTime = 0.38,
				NextAfter = 1.0, -- cierre del combo
				Damage = 11,
				GuardDamage = 45,
				Hitstun = 0.6,
				Knockback = 34,
				Heavy = true,
				Hitbox = { Size = Vector3.new(5, 6, 16), Offset = Vector3.new(1.5, 0.5, -10) },
			},
		},
	},
	Shield = {
		Hitbox = { Size = Vector3.new(9, 7, 6), Offset = Vector3.new(0.5, 0, -4) },
		Combo = {
			{
				Animation = "ShieldBash1", -- empujón de frente con el escudo
				HitTime = 0.28,
				NextAfter = 0.5,
				Damage = 9,
				GuardDamage = 45,
				Hitstun = 0.55,
				Knockback = 16,
			},
			{
				Animation = "ShieldBash2", -- revés con el canto del escudo
				HitTime = 0.28,
				NextAfter = 0.5,
				Damage = 9,
				GuardDamage = 45,
				Hitstun = 0.55,
				Knockback = 16,
			},
			{
				Animation = "ShieldSlam", -- golpe desde arriba que tumba
				HitTime = 0.4,
				NextAfter = 1.1, -- cierre del combo
				Damage = 13,
				GuardDamage = 70,
				Heavy = true,
				Ragdoll = { Horizontal = 34, Vertical = 10, Duration = 0.9 },
				Hitbox = { Size = Vector3.new(9, 8, 8), Offset = Vector3.new(1.5, -1, -5) },
			},
		},
		-- Animación en bucle mientras bloquea con el Mangekyō (el brazo aparece con el escudo)
		Guard = "ShieldGuard",
		-- Contraataque al bloquear un golpe cuerpo a cuerpo (sin que te rompan la guardia)
		Counter = {
			Animation = "ShieldBash1",
			Cooldown = 6,
			Range = 14, -- solo si el atacante está cerca
			Damage = 4,
			Hitstun = 0.9,
			Knockback = 30,
		},
	},
}
SusanooConfig.DefaultWeapon = "Fist"
SusanooConfig.ComboResetWindow = 1.2

-- Datos del arma (las que no tengan combo usan el puño)
function SusanooConfig.weapon(name: any): any
	local weapons = SusanooConfig.Weapons :: any
	return (typeof(name) == "string" and weapons[name]) or weapons[SusanooConfig.DefaultWeapon]
end

return SusanooConfig
