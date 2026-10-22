-- ReplicatedStorage > Shared > ClanAssets  (ModuleScript)
--
-- Iconos y sonidos de las mecánicas de clan, todos en un sitio (los usa
-- StarterPlayerScripts > ClanClient).
--
-- Iconos: pictogramas provisionales (PNG 128×128 con fondo transparente, ya con su círculo y
-- borde). Para cambiar uno basta con poner otro rbxassetid en el tercer argumento (Image).
-- Si Image está vacío se dibuja el respaldo: un círculo oscuro con el kanji de Glyph en Color.
-- Sonidos: rbxassetid; vacío = sin sonido.

export type Icon = { Image: string, Glyph: string, Color: Color3 }

local ClanAssets = {}

local function icon(glyph: string, color: Color3, image: string?): Icon
	return { Image = image or "", Glyph = glyph, Color = color }
end

local RED = Color3.fromRGB(220, 20, 30)

ClanAssets.Icons = {
	-- Avisos para ti (aparecen encima del indicador del dōjutsu)
	SharinganRequired = icon("眼", RED, "rbxassetid://96251060088024"), -- la técnica necesita el Sharingan activo
	NotAwakened = icon("閉", Color3.fromRGB(150, 150, 150), "rbxassetid://119554490710435"), -- todavía no despertaste esa etapa
	NothingCopied = icon("写", Color3.fromRGB(150, 150, 150), "rbxassetid://128734401425755"), -- la Copia no tiene nada guardado
	NoChakra = icon("空", Color3.fromRGB(120, 170, 255), "rbxassetid://98651490585219"), -- sin chakra para mantener el dōjutsu
	GenjutsuResisted = icon("幻", Color3.fromRGB(200, 140, 255), "rbxassetid://76944028885111"), -- el Sharingan acortó un genjutsu

	-- Sobre el objetivo (se ven en el mundo)
	SealsBroken = icon("破", RED, "rbxassetid://105038037145628"), -- sellos rotos
	GenjutsuReflected = icon("返", RED, "rbxassetid://129999158691008"), -- Genjutsu Kaeshi
	SharinganBind = icon("縛", RED, "rbxassetid://103384146199488"), -- paralizado por Genjutsu: Sharingan

	-- Copia
	Copy = icon("写", RED, "rbxassetid://101816905243631"),

	-- Clash de proyectiles (indicador del Sharingan)
	Danger = icon("危", Color3.fromRGB(255, 170, 40), "rbxassetid://127748612160841"), -- viene un proyectil
	ClashWindow = icon("弾", Color3.fromRGB(255, 255, 255), "rbxassetid://136030211091739"), -- ahora puedes hacer clash
	ClashUnavailable = icon("弾", Color3.fromRGB(120, 120, 120), "rbxassetid://98680242124674"), -- podrías, pero sin arma o en cooldown
	ClashArrow = icon("▲", Color3.fromRGB(255, 170, 40), "rbxassetid://139119636368441"), -- señala de dónde viene (con Image: una flecha que apunte hacia ARRIBA)
}

-- Icono de un jutsu: su elemento (NatureId) o, si no tiene, su categoría
ClanAssets.Natures = {
	Fire = icon("火", Color3.fromRGB(255, 120, 40), "rbxassetid://118808303354744"),
	Water = icon("水", Color3.fromRGB(70, 150, 255), "rbxassetid://97083725634009"),
	Wind = icon("風", Color3.fromRGB(150, 230, 170), "rbxassetid://111117070952007"),
	Lightning = icon("雷", Color3.fromRGB(255, 230, 90), "rbxassetid://133240489521842"),
	Earth = icon("土", Color3.fromRGB(190, 140, 90), "rbxassetid://133895038307675"),
}

ClanAssets.Categories = {
	Ninjutsu = icon("忍", Color3.fromRGB(225, 225, 225), "rbxassetid://104812887867085"),
	ElementalNinjutsu = icon("忍", Color3.fromRGB(225, 225, 225), "rbxassetid://104812887867085"),
	Genjutsu = icon("幻", Color3.fromRGB(200, 140, 255), "rbxassetid://125507466444751"),
	Taijutsu = icon("体", Color3.fromRGB(255, 170, 120), "rbxassetid://94787817996505"),
	Kenjutsu = icon("剣", Color3.fromRGB(200, 210, 230), "rbxassetid://133765303482866"),
	Shurikenjutsu = icon("手", Color3.fromRGB(200, 210, 230), "rbxassetid://84374211989182"),
	Clan = icon("血", RED, "rbxassetid://107897153863017"),
}

ClanAssets.Fallback = icon("術", Color3.fromRGB(225, 225, 225), "rbxassetid://104812887867085")

-- Icono para la placa de lectura y la Copia. IconId (si el jutsu lo tiene) gana a todo.
function ClanAssets.forTechnique(natureId: any, category: any, iconId: any): Icon
	local base = (typeof(natureId) == "string" and ClanAssets.Natures[natureId])
		or (typeof(category) == "string" and ClanAssets.Categories[category])
		or ClanAssets.Fallback
	if typeof(iconId) == "string" and iconId ~= "" then
		return { Image = iconId, Glyph = base.Glyph, Color = base.Color }
	end
	return base
end

-- Iris del Sharingan por tomoe (PNG con fondo transparente). Se usa en el emblema de pantalla,
-- el despertar, el indicador y el emblema sobre la cabeza. Vacío = dibujo procedural.
ClanAssets.SharinganIris = {
	[1] = "rbxassetid://108724693723834",
	[2] = "rbxassetid://125272460451137",
	[3] = "rbxassetid://89472697838530",
}

-- Iris del Mangekyō por tipo. Si falta uno se usa el de 3 tomoe.
ClanAssets.MangekyoIris = {
	Itachi = "rbxassetid://90751863549946", -- definitivo
}

-- Brillo de los ojos con dōjutsu activo: PNG blanco con degradado radial suave (se tiñe por código)
ClanAssets.EyeGlow = "rbxassetid://75647912383663"

-- Viñeta del Sharingan: PNG blanco, transparente en el centro y opaco en las esquinas (se tiñe por código)
ClanAssets.SharinganVignette = "rbxassetid://76275599778927"

-- Tsukuyomi: luna negra con halo rojo (PNG con transparencia) en el cielo rojo de la víctima
ClanAssets.TsukuyomiMoon = "rbxassetid://122135908502287"
-- Llamas de Amaterasu: la textura del fuego de los jutsus (flipbook 4×4, se tiñe de negro por código)
ClanAssets.FireFlipbook = "rbxassetid://11395089850"
-- Lengua de fuego suelta (sin animación), de respaldo
ClanAssets.FlameWisp = "rbxassetid://105846817437370"

ClanAssets.Sounds = {
	SharinganActivate = "rbxassetid://100301303292547", -- activar el Sharingan
	SharinganAwaken = "rbxassetid://100301303292547", -- despertar una etapa (1, 2, 3 tomoe); mismo sonido hasta tener uno propio
	SharinganGenjutsu = "rbxassetid://100301303292547", -- aviso de Genjutsu: Sharingan (oírlo es la pista para apartar la mirada)
	Denied = "", -- técnica rechazada (sin Sharingan, nada copiado)
	ClashDanger = "", -- viene un proyectil (indicador de clash)
	ClashWindow = "", -- se abre la ventana de clash
	AmaterasuIgnite = "", -- Amaterasu prende (pendiente)
	TsukuyomiEnter = "", -- entrar en el Tsukuyomi (pendiente)
	EntonSpearThrow = "rbxassetid://113831670560719", -- Enton: Black Spear sale (provisional: el del Fireball)
	EntonSpearImpact = "rbxassetid://130565967505452", -- Enton: Black Spear impacta (provisional: el del Fireball)
	GokaMekkyaku = "rbxassetid://130565967505452", -- sale el muro de fuego (provisional: el del Fireball)
	YasakaForm = "", -- se forman los magatama en la mano del Susanoo (pendiente)
	YasakaThrow = "", -- sale el shuriken girando (pendiente)
	YasakaImpact = "", -- explosión de chakra al impactar (pendiente)
	BlackWall = "", -- brota el muro de llamas negras (pendiente)
}

return ClanAssets
