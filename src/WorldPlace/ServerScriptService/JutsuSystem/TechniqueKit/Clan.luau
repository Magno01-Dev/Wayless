-- ServerScriptService > JutsuSystem > TechniqueKit > Clan  (ModuleScript)
--
-- Base común de las mecánicas de clan (PLANEACION_CLANES.md, etapa 1).
--
--   Clan.build(module, clanId, execute)   técnica de clan (requiere ClanId para aprender y usar)
--   Clan.buildMode(module, clanId, opts)  modo que se activa / desactiva con la misma tecla
--                                         (Sharingan, Byakugan): gasta chakra por segundo y
--                                         con él activo no regeneras chakra. Apagarlo responde
--                                         siempre: JutsuServer llama a module.TryToggleOff antes
--                                         del loadout, los bloqueos de estado y el cooldown
--   Clan.addMark / getMarks / clearMarks  marcas en el objetivo (sellos Uzumaki, tenketsu Hyūga)
--   Clan.resolveAwaken(player)            tecla Z (JutsuServer): la técnica de modo de tu clan
--                                         (Sharingan, Byakugan). Los modos NO van en slots
--   Clan.getStage / addMastery            despertar por etapas y maestría (abajo)
--
-- Despertar y maestría (por vida: CharacterDataService.ClanProgress; un wipe lo borra):
--   Etapa publicada en el jugador como ClanAwakenStage y la maestría como ClanMastery.
--   Maestría (Tuning.Mastery): tiempo en combate con el modo activo, mantenerlo activo en
--   combate, leer jutsus de otros jugadores, ver una sustitución, acertar Genjutsu: Sharingan, Kaeshi,
--   derribar (Downed) y hacer grip/execute a otros jugadores. Solo contra jugadores, con límite
--   por víctima y por lanzador.
--   Uchiha: 1 tomoe despierta en peligro (nivel 5 y vida ≤ 30 % en combate) y enciende el
--   Sharingan solo; 2 y 3 tomoe despiertan con nivel (20 / 45) y maestría (300 / 1200). Con el
--   Sharingan activo, los sellos van un 10 / 20 / 30 % más rápido (SealSpeedMultiplier).
--
-- Indicador de clash (Uchiha, Sharingan activo): lo dibuja ClanClient con la lógica del
-- contraataque de la G (Throwables > ClientShots). Aquí, la maestría por cada clash válido.
--   Pruebas (solo servidor): ServerStorage > JutsuInternal > ClanDev:Invoke(acción, jugador, valor)
--     "SetStage" (0–3, con su momento de despertar) · "AddMastery" · "Get" -> { Stage, Mastery }
--     "SetMangekyo" (nil = al azar · { Attack, Control, Color, Iris, Weapon } · "Itachi") · "SetEyeStrain"
--
-- Pasivas (se registran al cargar este módulo, que lo cargan los jutsus de clan al arrancar):
--   Uchiha   afinidad Katon: sus jutsus de fuego hacen +10 % · con el Sharingan activo los
--            genjutsu que le lanzan duran un 25 % menos · lectura del Sharingan (abajo) ·
--            tomoe = etapa despertada (ver "Despertar y maestría") · con 2+ tomoe, ver la sustitución:
--            si alguien que tienes delante se sustituye, ves remanentes suyos mientras va
--            invisible (ClanClient; SubstitutionServer avisa por CombatInternal > Substituted) ·
--            con 3 tomoe, Genjutsu Kaeshi: si BLOQUEAS justo a tiempo (bloqueo perfecto, ventana
--            KaeshiPerfectWindow) un genjutsu de alguien que ves, le rebota; recarga KaeshiCooldown
--            (Genjutsu.addInterceptor; CombatServer publica BlockStartedAt) · con 3 tomoe, la última técnica
--            que leas (ninjutsu, genjutsu, taijutsu, kenjutsu o shurikenjutsu; nunca clan ni KG) queda
--            copiada 12 s (Clan.getCopied; la lanza Jutsus > SharinganCopy, ×0.8 si no es de tu naturaleza)
--   Uzumaki  fuerza vital: el Downed dura ×0.7 (DownedServer v31.6) · sus golpes cuerpo a
--            cuerpo dejan marcas de sello (máx. 3, 8 s)
--   Hyūga    Jūken: sus M1 y taijutsu SIN ARMA hacen −10 % y cierran tenketsu (máx. 5, 8 s):
--            menos regeneración de chakra; con 5, 2 s sin chakra
--   Nara     trampas mejores (ThrowableServer v3.3): minas y abrojos duran el doble y las
--            minas siempre son ocultas
--
-- Lectura del Sharingan: JutsuServer avisa de cada cast aceptado por
-- ServerStorage > JutsuInternal > CastStarted. Aquí se manda "SharinganRead" SOLO a los Uchiha
-- con el Sharingan activo que tienen al lanzador en su campo visual (Genjutsu.canSee: 140°,
-- sin paredes) y a ≤ Tuning.SharinganReadRangeByTomoe studs. Nada de esto va en atributos.
--
-- Avisos al jugador: "Icon" { Icon = nombre } (ClanClient decide si es texto corto o nada) y
-- los efectos sobre otros (GenjutsuReflected, SubstitutionRead…).
--
-- Efectos visuales: remote ReplicatedStorage > JutsuSystem > Remotes > ClanFX
-- (StarterPlayerScripts > ClanClient). Las marcas y los modos también se publican como
-- atributos del personaje, que ClanClient dibuja. Los ojos del modo se cambian con el
-- atributo del jugador CharacterEyeVariantId (lo pinta CharacterFaceController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Genjutsu = require(script.Parent:WaitForChild("Genjutsu"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local ChakraService = require(ServerScriptService:WaitForChild("ChakraService"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))
local MangekyoCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MangekyoCatalog"))
local ClanAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClanAssets"))

local Clan = {}

Clan.Tuning = {
	UchihaKatonMultiplier = 1.1,
	SharinganGenjutsuMultiplier = 0.75, -- con el Sharingan activo los genjutsu te duran un 25 % menos
	-- Despertar por etapas: 1 tomoe con nivel 5 en peligro; 2 y 3 con nivel y maestría acumulada
	SharinganStageLevels = { 5, 20, 45 },
	SharinganStageMastery = { 0, 300, 1200 },
	SharinganAwakenHealthFraction = 0.3,
	SealSpeedByTomoe = { 1.1, 1.2, 1.3 }, -- sellos más rápidos con el Sharingan activo
	SharinganDrainByTomoe = { 1.5, 1.25, 1.0 },
	SharinganReadRangeByTomoe = { 90, 110, 130 }, -- lectura y clones falsos
	GenjutsuSharinganRangeByTomoe = { 55, 55, 65 },
	SubstitutionReadMinTomoe = 2, -- ver dónde reaparece quien se sustituye delante de ti
	ByakuganSubstitutionRange = 45, -- el Byakugan ve los remanentes a su alrededor (360°)
	KaeshiMinTomoe = 3,
	KaeshiPerfectWindow = 0.35, -- s: bloquear como mucho este tiempo antes de que entre el genjutsu
	KaeshiCooldown = 25,
	-- Mangekyō Sharingan (etapa 4; Eterno = etapa 5)
	MangekyoMinLevel = 60,
	MangekyoMinMastery = 2500,
	MangekyoMinExecutions = 10, -- ejecuciones (grips) hechas con el Sharingan activo
	MangekyoWitnessRange = 40, -- studs: el compañero muere delante de ti
	MangekyoDrainPerSecond = 2,
	SusanooDrainPerSecond = 3,
	-- Ceguera (0–100): sube con las habilidades del Mangekyō y el Susanoo, baja fuera de combate
	EyeStrainMax = 100,
	EyeStrainSusanooPerSecond = 0.5,
	EyeStrainDecayPerSecond = 0.5, -- fuera de combate
	EyeStrainReadPenaltyAt = 50, -- desde aquí, menos alcance de lectura
	EyeStrainReadRangeMultiplier = 0.75,
	EyeStrainCooldownPenaltyAt = 75, -- desde aquí, las habilidades del Mangekyō recargan más lento
	EyeStrainCooldownMultiplier = 1.25,
	CopyMinTomoe = 3,
	CopyDuration = 12,
	CopyCostMultiplier = 1.3,
	-- Se copia ninjutsu (elemental o no), genjutsu, taijutsu, kenjutsu y shurikenjutsu: nunca clan ni KG
	CopyCategories = {
		Ninjutsu = true,
		ElementalNinjutsu = true,
		Genjutsu = true,
		Taijutsu = true,
		Kenjutsu = true,
		Shurikenjutsu = true,
	},
	-- Copia de una técnica de una naturaleza que no tienes: funciona, con menos potencia
	CopyOffNaturePotency = 0.8,
	CopyPotencyWindow = 6, -- s tras lanzarla en los que su daño va reducido (proyectiles en vuelo)
	UzumakiDownedMultiplier = 0.7,
	UzumakiMaxMarks = 3,
	UzumakiMarkDuration = 8,
	JukenDamageMultiplier = 0.9,
	JukenMaxMarks = 5,
	JukenMarkDuration = 8,
	JukenSealDuration = 2,

	-- Maestría del clan: cuánto da cada cosa
	Mastery = {
		CombatPerSecond = 0.2, -- en combate con el modo activo
		SustainedActivation = 5, -- mantener el modo ≥ SustainedSeconds en combate
		SustainedSeconds = 5,
		SustainedCooldown = 60, -- como mucho una vez por minuto
		Read = 1, -- leer un jutsu de otro jugador
		ReadCapPerCaster = 10, -- lecturas que cuentan del mismo jugador por ventana
		ReadWindow = 300,
		SubstitutionRead = 3, -- ver la sustitución de otro jugador
		GenjutsuLanded = 5,
		Kaeshi = 10,
		Down = 15, -- derribar (Downed) a otro jugador
		Execute = 30, -- grip / execute
		Clash = 4, -- clash defensivo con el Sharingan activo
		ClashCooldown = 15, -- contra el mismo lanzador
		VictimCooldown = 300, -- la misma víctima cuenta una vez por ventana (derribo y execute)
	},
}

-- Remote -------------------------------------------------------------------------------------

local REMOTE_NAME = "ClanFX"
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	local jutsuSystem = ReplicatedStorage:WaitForChild("JutsuSystem")
	local remotes = jutsuSystem:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = jutsuSystem
	end
	local found = remotes:FindFirstChild(REMOTE_NAME)
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = REMOTE_NAME
		found.Parent = remotes
	end
	remote = found :: RemoteEvent
	return remote :: RemoteEvent
end

task.spawn(getRemote)

function Clan.fxAll(action: string, data: {[string]: any})
	getRemote():FireAllClients(action, data)
end

function Clan.fxTo(player: Player?, action: string, data: {[string]: any})
	if player and player.Parent then
		getRemote():FireClient(player, action, data)
	end
end

function Clan.getClan(player: Player?): string?
	local clanId = player and player:GetAttribute("ClanId")
	return if typeof(clanId) == "string" then clanId else nil
end

local function clanOfCharacter(character: Model?): string?
	return Clan.getClan(character and Players:GetPlayerFromCharacter(character))
end

Clan.findTarget = Genjutsu.findTarget

local function applyStatus(character: Model, statusId: string, options: {[string]: any}?)
	if not StatusEffectService.GetDefinition(statusId) then
		warn("[Clan] Falta el estado '" .. statusId .. "' en StatusEffectDefinitions")
		return
	end
	StatusEffectService.Apply(character, statusId, options)
end
Clan.applyStatus = applyStatus

-- Servicios que se piden tarde: requerirlos al cargar haría un require circular con
-- TechniqueRegistry, que es quien carga los jutsus de clan (y con ellos este módulo).
local lateServices: {[string]: any} = {}

local function lateService(name: string): any?
	local cached = lateServices[name]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return require(ServerScriptService:WaitForChild("Services"):WaitForChild(name))
	end)
	if ok then
		lateServices[name] = result
		return result
	end
	return nil
end

-- ¿Está en combate? (le pegaron o pegó a alguien hace poco: CombatTagService)
local combatTagService: any = nil

local function inCombat(player: Player): boolean
	if combatTagService == nil then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("CombatTagService"))
		end)
		combatTagService = if ok then result else false
	end
	if not combatTagService then
		return false
	end
	local ok, tagged = pcall(function()
		return combatTagService.IsTagged(player) or combatTagService.GetOutgoingCount(player) > 0
	end)
	return ok and tagged == true
end
Clan.inCombat = inCombat

-- Progreso de clan por vida ------------------------------------------------------------------

-- Uchiha: Stage 1–3 = tomoe, 4 = Mangekyō, 5 = Eterno. Mangekyo = el suyo propio
-- { Attack, Control, Color, Iris, Weapon } (ReplicatedStorage > Shared > MangekyoCatalog),
-- EyeStrain = fatiga ocular (Eye Strain) 0–100, Executions = ejecuciones hechas con el Sharingan activo.
type Progress = {
	ClanId: string,
	Stage: number,
	Mastery: number,
	Loaded: boolean,
	Mangekyo: {[string]: string}?,
	EyeStrain: number,
	Executions: number,
}
local progress: {[Player]: Progress} = {}

-- Se rellena más abajo (despertar por etapas)
local checkStageUp: ((Player) -> ())? = nil

local function publishProgress(player: Player, entry: Progress)
	player:SetAttribute("ClanAwakenStage", entry.Stage)
	player:SetAttribute("ClanMastery", math.floor(entry.Mastery))
	-- Mangekyō propio: cada parte en un atributo (requisitos de aprendizaje, menú, clientes)
	local mangekyo = if entry.Stage >= 4 then entry.Mangekyo else nil
	player:SetAttribute("MangekyoAttack", mangekyo and mangekyo.Attack)
	player:SetAttribute("MangekyoControl", mangekyo and mangekyo.Control)
	player:SetAttribute("MangekyoColor", mangekyo and mangekyo.Color)
	player:SetAttribute("MangekyoIris", mangekyo and mangekyo.Iris)
	player:SetAttribute("MangekyoWeapon", mangekyo and mangekyo.Weapon)
	player:SetAttribute("MangekyoKamui", if MangekyoCatalog.hasKamui(mangekyo :: any) then true else nil)
	player:SetAttribute("MangekyoType", nil) -- antiguo (un tipo por personaje)
	player:SetAttribute("MangekyoEyeStrain", if entry.EyeStrain > 0 then math.floor(entry.EyeStrain) else nil)
end

local function saveProgress(player: Player, entry: Progress)
	publishProgress(player, entry)
	local CharacterDataService = lateService("CharacterDataService")
	if not entry.Loaded or not CharacterDataService then
		return
	end
	pcall(CharacterDataService.SetClanProgress, player, entry.ClanId, {
		Stage = entry.Stage,
		Mastery = entry.Mastery,
		Mangekyo = entry.Mangekyo,
		EyeStrain = entry.EyeStrain,
		Executions = entry.Executions,
	})
end

-- Lee el progreso del clan actual del jugador en cuanto sus datos están cargados
local function loadProgress(player: Player)
	local clanId = Clan.getClan(player)
	if not clanId then
		progress[player] = nil
		player:SetAttribute("ClanAwakenStage", nil)
		player:SetAttribute("ClanMastery", nil)
		return
	end
	local entry: Progress = { ClanId = clanId, Stage = 0, Mastery = 0, Loaded = false, EyeStrain = 0, Executions = 0 }
	progress[player] = entry
	publishProgress(player, entry)
	task.spawn(function()
		local CharacterDataService = lateService("CharacterDataService")
		local deadline = os.clock() + 90
		while player.Parent and CharacterDataService and os.clock() < deadline do
			local ok, loaded = pcall(CharacterDataService.IsLoaded, player)
			if ok and loaded then
				break
			end
			task.wait(0.5)
		end
		if progress[player] ~= entry or not player.Parent or not CharacterDataService then
			return
		end
		local ok, stored = pcall(CharacterDataService.GetClanProgress, player, clanId)
		if not ok then
			warn("[Clan] No pude leer el progreso de clan de " .. player.Name .. ": " .. tostring(stored))
			return
		end
		if typeof(stored) == "table" then
			entry.Stage = if typeof(stored.Stage) == "number" then math.clamp(math.floor(stored.Stage), 0, 5) else 0
			entry.Mastery = if typeof(stored.Mastery) == "number" then math.max(0, stored.Mastery) else 0
			if typeof(stored.Mangekyo) == "table" then
				entry.Mangekyo = MangekyoCatalog.sanitize(stored.Mangekyo, ClanAssets.MangekyoIris) :: any
			elseif stored.MangekyoType == "Itachi" then
				-- Antiguo "tipo Itachi": sus dos habilidades, en rojo y con su iris
				entry.Mangekyo = { Attack = "Amaterasu", Control = "Tsukuyomi", Color = "Crimson", Iris = "Itachi", Weapon = "Fist" }
			elseif entry.Stage >= 4 then
				entry.Mangekyo = MangekyoCatalog.roll(ClanAssets.MangekyoIris) :: any
			end
			local storedStrain = if typeof(stored.EyeStrain) == "number" then stored.EyeStrain else stored.Blindness -- "Blindness" = nombre antiguo
		entry.EyeStrain = if typeof(storedStrain) == "number" then math.clamp(storedStrain, 0, 100) else 0
			entry.Executions = if typeof(stored.Executions) == "number" then math.max(0, math.floor(stored.Executions)) else 0
		end
		entry.Loaded = true
		publishProgress(player, entry)
		if checkStageUp then
			checkStageUp(player)
		end
	end)
end

function Clan.getStage(player: Player?): number
	local entry = player and progress[player]
	return if entry then entry.Stage else 0
end

function Clan.getMastery(player: Player?): number
	local entry = player and progress[player]
	return if entry then entry.Mastery else 0
end

-- Suma maestría al clan del jugador y comprueba si despierta la siguiente etapa
function Clan.addMastery(player: Player?, amount: number, _reason: string?)
	local entry = player and progress[player]
	if not player or not entry or not entry.Loaded or amount <= 0 then
		return
	end
	local before = math.floor(entry.Mastery)
	entry.Mastery += amount
	-- Se guarda al cruzar un entero (no en cada décima del tiempo en combate)
	if math.floor(entry.Mastery) ~= before then
		saveProgress(player, entry)
	end
	if checkStageUp then
		checkStageUp(player)
	end
end

-- Uchiha: tomoe = etapa de despertar (0 sin despertar · 1, 2, 3)
function Clan.sharinganTomoe(player: Player?): number
	if Clan.getClan(player) ~= "Uchiha" then
		return 0
	end
	-- El Mangekyō (etapas 4 y 5) conserva todo lo del Sharingan de 3 tomoe
	return math.min(Clan.getStage(player), 3)
end

-- Variante de ojos para esos tomoe: "Sharingan2" / "Sharingan3" si el estilo de ojo del jugador
-- tiene esa textura en AppearanceCatalog; si no, "Sharingan" (CharacterFaceController volvería
-- a los ojos normales con una variante que no existe)
local appearanceCatalog: any = nil

function Clan.sharinganEyeVariant(player: Player, tomoe: number): string
	if tomoe <= 1 then
		return "Sharingan"
	end
	if appearanceCatalog == nil then
		local ok, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AppearanceCatalog"))
		end)
		appearanceCatalog = if ok then result else false
	end
	local styleId = player:GetAttribute("CharacterBaseEyeStyleId") or player:GetAttribute("CharacterEyeStyleId")
	if not appearanceCatalog or typeof(styleId) ~= "string" then
		return "Sharingan"
	end
	local variantId = "Sharingan" .. tostring(tomoe)
	local ok, has = pcall(function()
		local image = appearanceCatalog.GetEyeImage(styleId, variantId)
		return image ~= nil and image ~= appearanceCatalog.GetEyeImage(styleId, "Base")
	end)
	return if ok and has then variantId else "Sharingan"
end

-- Marcas -------------------------------------------------------------------------------------

type MarkState = { Count: number, Until: number, By: Player? }
local marks: {[string]: {[Model]: MarkState}} = {}

local function publishMarks(kind: string, target: Model, state: MarkState?)
	if not target.Parent then
		return
	end
	target:SetAttribute(kind .. "Marks", if state then state.Count else nil)
	target:SetAttribute(kind .. "MarksUntil", if state then state.Until else nil)
end

function Clan.getMarks(kind: string, target: Model): number
	local state = marks[kind] and marks[kind][target]
	if not state or Workspace:GetServerTimeNow() > state.Until then
		return 0
	end
	return state.Count
end

function Clan.clearMarks(kind: string, target: Model)
	if marks[kind] then
		marks[kind][target] = nil
	end
	publishMarks(kind, target, nil)
end

function Clan.addMark(kind: string, target: Model, attacker: Player?, maxCount: number, duration: number): number
	marks[kind] = marks[kind] or {}
	local now = Workspace:GetServerTimeNow()
	local state = marks[kind][target]
	if not state or now > state.Until then
		state = { Count = 0, Until = 0, By = attacker }
		marks[kind][target] = state
	end
	state.Count = math.min(maxCount, state.Count + 1)
	state.Until = now + duration
	state.By = attacker
	publishMarks(kind, target, state)
	return state.Count
end

-- Las marcas vencidas se limpian solas
local markAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	markAccumulator += dt
	if markAccumulator < 0.5 then
		return
	end
	markAccumulator = 0
	local now = Workspace:GetServerTimeNow()
	for kind, byTarget in marks do
		for target, state in byTarget do
			if now > state.Until or not target.Parent then
				byTarget[target] = nil
				publishMarks(kind, target, nil)
			end
		end
	end
end)

-- Modos (Sharingan, Byakugan) ----------------------------------------------------------------

type Mode = {
	Attribute: string,
	Status: string?,
	EyeVariant: string?,
	Attributes: {[string]: any}?,
	Token: number,
	Player: Player,
	BaseOpts: {[string]: any},
	Opts: {[string]: any},
	CombatSeconds: number,
	SustainAwarded: boolean,
}
local modes: {[Model]: {[string]: Mode}} = {}
local modeSequence = 0

-- Opciones de cada modo por atributo (las registra buildMode; el primer despertar las usa)
local modeDefinitions: {[string]: {[string]: any}} = {}

-- Mantener el modo en combate da maestría como mucho una vez por SustainedCooldown
local sustainReadyAt: {[Player]: number} = {}

function Clan.isModeActive(character: Model, attribute: string): boolean
	return modes[character] ~= nil and modes[character][attribute] ~= nil
end

-- Mangekyō pedido (doble Z) mientras el Sharingan está encendido: lo lee Clan.mangekyoConfig
local wantMangekyo: {[Player]: boolean} = {}

function Clan.stopMode(character: Model, attribute: string)
	local byAttribute = modes[character]
	local mode = byAttribute and byAttribute[attribute]
	if not byAttribute or not mode then
		return
	end
	-- Apagar el Sharingan apaga también el Mangekyō y el Susanoo (que van encima)
	if attribute == "SharinganActive" then
		wantMangekyo[mode.Player] = nil
		if byAttribute.SusanooActive then
			Clan.stopMode(character, "SusanooActive")
		end
	end
	byAttribute[attribute] = nil
	if next(byAttribute) == nil then
		modes[character] = nil
	end
	if character.Parent then
		character:SetAttribute(attribute, nil)
		for name in mode.Attributes or {} do
			character:SetAttribute(name, nil)
		end
		if mode.Status and StatusEffectService.Has(character, mode.Status) then
			StatusEffectService.Remove(character, mode.Status, "ModeEnd")
		end
	end
	-- Los ojos vuelven a los de siempre (solo si nadie los cambió por otra cosa)
	if mode.EyeVariant and mode.Player:GetAttribute("CharacterEyeVariantId") == mode.EyeVariant then
		mode.Player:SetAttribute("CharacterEyeVariantId", "Base")
	end
	Clan.fxAll("ModeEnd", { Character = character, Attribute = attribute })
end

-- ¿Sigue la técnica equipada? Con el Content Bypass de desarrollador, siempre sí.
local function isEquipped(player: Player, techniqueId: string): boolean
	local DeveloperAccessService = lateService("DeveloperAccessService")
	local TechniqueLoadoutService = lateService("TechniqueLoadoutService")
	if not DeveloperAccessService or not TechniqueLoadoutService then
		return true
	end
	local ok, equipped = pcall(function()
		return DeveloperAccessService.HasContentBypass(player)
			or TechniqueLoadoutService.FindSlot(player, techniqueId) ~= nil
	end)
	return not ok or equipped == true
end

--[[
	opts = {
		Attribute       atributo del personaje mientras está activo ("SharinganActive")
		DrainPerSecond  chakra por segundo
		Status          estado mientras está activo (p. ej. "DojutsuActive": sin regenerar chakra)
		EyeVariant      variante de ojos de AppearanceCatalog mientras está activo ("Sharingan")
		Attributes      atributos extra del personaje mientras está activo ({ SharinganTomoe = 2 })
		Configure       function(player) -> tabla que sobrescribe las opciones anteriores al
		                activarlo (p. ej. drenaje y ojos según los tomoe)
		TechniqueId     si deja de estar equipada, el modo se apaga (lo pone buildMode)
	}
]]
local function resolveModeOpts(baseOpts: {[string]: any}, player: Player): {[string]: any}
	local opts = table.clone(baseOpts)
	if typeof(baseOpts.Configure) == "function" then
		local ok, overrides = pcall(baseOpts.Configure, player)
		if ok and typeof(overrides) == "table" then
			for key, value in overrides do
				opts[key] = value
			end
		end
	end
	return opts
end

function Clan.startMode(player: Player, character: Model, baseOpts: {[string]: any})
	local opts = resolveModeOpts(baseOpts, player)

	local attribute = opts.Attribute
	Clan.stopMode(character, attribute)
	modeSequence += 1
	local mode: Mode = {
		Attribute = attribute,
		Status = opts.Status,
		EyeVariant = opts.EyeVariant,
		Attributes = opts.Attributes,
		Token = modeSequence,
		Player = player,
		BaseOpts = baseOpts,
		Opts = opts,
		CombatSeconds = 0,
		SustainAwarded = false,
	}
	modes[character] = modes[character] or {}
	modes[character][attribute] = mode

	character:SetAttribute(attribute, true)
	for name, value in opts.Attributes or {} do
		character:SetAttribute(name, value)
	end
	if opts.Status then
		applyStatus(character, opts.Status, { Duration = 3600 })
	end
	if opts.EyeVariant then
		player:SetAttribute("CharacterEyeVariantId", opts.EyeVariant)
	end
	Clan.fxAll("ModeStart", { Character = character, Attribute = attribute })

	task.spawn(function()
		local interval = 0.5
		while true do
			task.wait(interval)
			local current = modes[character] and modes[character][attribute]
			if current ~= mode then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not character.Parent or player.Character ~= character or not humanoid or humanoid.Health <= 0
				or character:GetAttribute("IsDowned") == true
				or character:GetAttribute("Status_ChakraSuppressed") == true
				or (opts.TechniqueId and not isEquipped(player, opts.TechniqueId)) then
				Clan.stopMode(character, attribute)
				return
			end
			-- mode.Opts: puede cambiar con Clan.refreshMode (p. ej. al despertar otra etapa)
			local spent = ChakraService.TrySpend(player, (mode.Opts.DrainPerSecond or 1) * interval, "Mode:" .. attribute)
			if not spent then
				Clan.stopMode(character, attribute)
				Clan.fxTo(player, "ModeNoChakra", { Attribute = attribute })
				return
			end
			-- Modos que ciegan (Susanoo)
			if mode.Opts.EyeStrainPerSecond and Clan.addEyeStrain then
				Clan.addEyeStrain(player, mode.Opts.EyeStrainPerSecond * interval)
			end
			-- Maestría: tiempo en combate con el modo activo, y mantenerlo un rato en combate
			if inCombat(player) then
				mode.CombatSeconds += interval
				Clan.addMastery(player, Clan.Tuning.Mastery.CombatPerSecond * interval, "Combat")
				if not mode.SustainAwarded and mode.CombatSeconds >= Clan.Tuning.Mastery.SustainedSeconds then
					mode.SustainAwarded = true
					local now = Workspace:GetServerTimeNow()
					if (sustainReadyAt[player] or 0) <= now then
						sustainReadyAt[player] = now + Clan.Tuning.Mastery.SustainedCooldown
						Clan.addMastery(player, Clan.Tuning.Mastery.SustainedActivation, "Activation")
					end
				end
			end
		end
	end)
end

-- Vuelve a calcular un modo activo (Configure): atributos, ojos y gasto. Se usa al despertar
-- otra etapa con el Sharingan encendido.
function Clan.refreshMode(character: Model, attribute: string)
	local mode = modes[character] and modes[character][attribute]
	if not mode then
		return
	end
	local opts = resolveModeOpts(mode.BaseOpts, mode.Player)
	for name in mode.Attributes or {} do
		if not (opts.Attributes and opts.Attributes[name] ~= nil) then
			character:SetAttribute(name, nil)
		end
	end
	for name, value in opts.Attributes or {} do
		character:SetAttribute(name, value)
	end
	mode.Attributes = opts.Attributes
	mode.Opts = opts
	if opts.EyeVariant and opts.EyeVariant ~= mode.EyeVariant then
		mode.EyeVariant = opts.EyeVariant
		mode.Player:SetAttribute("CharacterEyeVariantId", opts.EyeVariant)
	end
end

-- Apaga todos los modos de un jugador salvo los de keepCharacter (al reaparecer o salir)
local function stopModesOf(player: Player, keepCharacter: Model?)
	for character, byAttribute in modes do
		if character ~= keepCharacter then
			for attribute, mode in byAttribute do
				if mode.Player == player then
					Clan.stopMode(character, attribute)
				end
			end
		end
	end
end

-- Construcción de técnicas ------------------------------------------------------------------

local function requireClan(module: any, clanId: string)
	module.Requirements = module.Requirements or {}
	module.Requirements.Cast = module.Requirements.Cast or {}
	module.Requirements.Learn = module.Requirements.Learn or {}
	module.Requirements.Cast.ClanId = clanId
	module.Requirements.Learn.ClanId = clanId
	module.ClanId = clanId
end

-- Técnica de clan: como un genjutsu (dirección del retículo, Precheck, marcador ProjectileSpawn)
function Clan.build(module: any, clanId: string, execute: (any, Vector3) -> ()): any
	module.TechniqueCategory = module.TechniqueCategory or "Clan"
	requireClan(module, clanId)
	return Genjutsu.build(module, execute)
end

--[[
	Modo que se activa y desactiva con la misma tecla. Al desactivarlo, el pedido se rechaza
	con "Toggled" (no gasta chakra ni cooldown).
	opts: ver Clan.startMode
]]
function Clan.buildMode(module: any, clanId: string, opts: {[string]: any}): any
	local modeOpts = table.clone(opts)
	modeDefinitions[opts.Attribute] = modeOpts

	Clan.build(module, clanId, function(context)
		Clan.startMode(context.Player, context.Character, modeOpts)
	end)
	module.IsClanMode = true
	-- Se usa con la tecla Z (Clan.resolveAwaken), no desde un slot: ni menú ni loadout
	module.NotEquippable = true
	module.DisplayInMenu = false
	-- Un dōjutsu no lleva sellos: JutsuServer no reproduce los sonidos de sellos
	module.NoHandSigns = true

	-- JutsuServer lo llama antes del loadout, los bloqueos y el cooldown
	function module.TryToggleOff(character: Model): boolean
		if Clan.isModeActive(character, opts.Attribute) then
			Clan.stopMode(character, opts.Attribute)
			return true
		end
		return false
	end

	-- Respaldo por si algún camino antiguo no llama a TryToggleOff
	local baseSanitize = module.SanitizeRequest
	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		if module.TryToggleOff(character) then
			return false, "Toggled", nil
		end
		return baseSanitize(character, payload)
	end

	return module
end

-- Modo a medida (Mangekyō, Susanoo): la misma tecla lo activa y lo apaga, pero encenderlo y
-- apagarlo lo deciden spec.Execute(context), spec.IsActive(character) y spec.TurnOff(character)
function Clan.buildCustomMode(module: any, clanId: string, spec: {[string]: any}): any
	Clan.build(module, clanId, function(context)
		spec.Execute(context)
	end)
	module.IsClanMode = true
	module.NotEquippable = true
	module.DisplayInMenu = false
	module.NoHandSigns = true

	function module.TryToggleOff(character: Model): boolean
		if spec.IsActive(character) then
			spec.TurnOff(character)
			return true
		end
		return false
	end

	local baseSanitize = module.SanitizeRequest
	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		if module.TryToggleOff(character) then
			return false, "Toggled", nil
		end
		return baseSanitize(character, payload)
	end

	return module
end

-- Susanoo (mantener Z): modo encima del Mangekyō. Gasta chakra y ciega mientras está activo.
modeDefinitions.SusanooActive = {
	Attribute = "SusanooActive",
	DrainPerSecond = Clan.Tuning.SusanooDrainPerSecond,
	EyeStrainPerSecond = Clan.Tuning.EyeStrainSusanooPerSecond,
}

function Clan.getModeDefinition(attribute: string): {[string]: any}?
	return modeDefinitions[attribute]
end

-- Despertar del clan (tecla Z) ----------------------------------------------------------------

-- Técnica de modo de cada clan (la lanza JutsuServer sin slot ni aprenderla)
Clan.AwakenTechniques = {
	Uchiha = "Sharingan",
	Hyuga = "Byakugan",
}

-- mode (JutsuController, tecla Z): "Sharingan" (toque) · "Mangekyo" (doble toque) · "Susanoo" (mantener)
function Clan.resolveAwaken(player: Player, mode: string?): (string?, string?)
	local clanId = Clan.getClan(player)
	local techniqueId = clanId and Clan.AwakenTechniques[clanId]
	if not clanId or not techniqueId then
		return nil, "NoAwaken"
	end
	-- Uchiha: hay que haber despertado el primer tomoe
	if clanId == "Uchiha" and Clan.getStage(player) < 1 then
		Clan.fxTo(player, "Icon", { Icon = "NotAwakened" })
		return nil, "NotAwakened"
	end
	if clanId == "Uchiha" and (mode == "Mangekyo" or mode == "Susanoo") then
		local character = player.Character
		local turningOff = character ~= nil and (
			(mode == "Mangekyo" and Clan.isMangekyoActive(character))
			or (mode == "Susanoo" and character:GetAttribute("SusanooActive") == true)
		)
		if not turningOff then
			if not Clan.hasMangekyo(player) then
				Clan.fxTo(player, "Icon", { Icon = "NoMangekyo" })
				return nil, "NoMangekyo"
			end
			if Clan.isEyeStrainLocked(player) then
				Clan.fxTo(player, "Icon", { Icon = "EyeStrainLocked" })
				return nil, "EyeStrainLocked"
			end
		end
		return if mode == "Mangekyo" then "Mangekyo" else "SusanooMode", nil
	end
	return techniqueId, nil
end

-- Pasivas ------------------------------------------------------------------------------------

local MELEE_SOURCES = {
	M1 = true,
	Lunge = true,
	AerialKick = true,
	Launcher = true,
	Taijutsu = true,
	Kenjutsu = true,
}

local UNARMED_SOURCES = {
	M1 = true,
	Taijutsu = true,
}

-- Daño de jutsus (los de fuego dan "Jutsu" y algunos proyectiles "Projectile", con su Id)
local KATON_SOURCES = {
	Jutsu = true,
	Projectile = true,
}

local function attackerCharacter(context: any): Model?
	local attacker = context.Attacker
	return attacker and attacker.Character
end

local function isJuken(context: any): boolean
	local character = attackerCharacter(context)
	return character ~= nil
		and Clan.getClan(context.Attacker) == "Hyuga"
		and UNARMED_SOURCES[context.SourceType or ""] == true
		and character:GetAttribute("WeaponState") ~= "Drawn"
end

-- Uchiha: ¿es un jutsu de fuego? (NatureId "Fire" en TechniqueRegistry)
local fireTechniques: {[string]: boolean} = {}

local function isFireTechnique(techniqueId: any): boolean
	if typeof(techniqueId) ~= "string" or techniqueId == "" then
		return false
	end
	local cached = fireTechniques[techniqueId]
	if cached ~= nil then
		return cached
	end
	local TechniqueRegistry = lateService("TechniqueRegistry")
	if not TechniqueRegistry then
		return false
	end
	local ok, entry = pcall(TechniqueRegistry.Get, techniqueId)
	if not ok then
		return false
	end
	local isFire = typeof(entry) == "table" and entry.NatureId == "Fire"
	fireTechniques[techniqueId] = isFire
	return isFire
end

local function isUchihaKaton(context: any): boolean
	return Clan.getClan(context.Attacker) == "Uchiha"
		and KATON_SOURCES[context.SourceType or ""] == true
		and isFireTechnique(context.SourceId)
end

-- Maestría contra otros jugadores (antifarmeo) ----------------------------------------------

-- La misma víctima cuenta una vez por VictimCooldown y por tipo (derribo, execute)
local victimRewardAt: {[Player]: {[string]: number}} = {}

local function rewardAgainst(attacker: Player?, victim: Player?, kind: string, amount: number, cooldown: number?)
	if not attacker or not victim or attacker == victim then
		return
	end
	-- Contra un novato protegido no se gana maestría (LifeForceServer: NoviceProtected)
	if victim:GetAttribute("NoviceProtected") == true then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local byKey = victimRewardAt[attacker] or {}
	victimRewardAt[attacker] = byKey
	local key = kind .. ":" .. tostring(victim.UserId)
	if (byKey[key] or 0) > now then
		return
	end
	byKey[key] = now + (cooldown or Clan.Tuning.Mastery.VictimCooldown)
	Clan.addMastery(attacker, amount, kind)
end

-- Leer jutsus de otro jugador: como mucho ReadCapPerCaster por ventana
local readCounts: {[Player]: {[number]: {Count: number, ResetAt: number}}} = {}

local function rewardRead(viewer: Player, caster: Player?)
	if not caster or caster == viewer or caster:GetAttribute("NoviceProtected") == true then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local byCaster = readCounts[viewer] or {}
	readCounts[viewer] = byCaster
	local entry = byCaster[caster.UserId]
	if not entry or now > entry.ResetAt then
		entry = { Count = 0, ResetAt = now + Clan.Tuning.Mastery.ReadWindow }
		byCaster[caster.UserId] = entry
	end
	if entry.Count >= Clan.Tuning.Mastery.ReadCapPerCaster then
		return
	end
	entry.Count += 1
	Clan.addMastery(viewer, Clan.Tuning.Mastery.Read, "Read")
end

DamageService.AddHook({
	ModifyDamage = function(context: any): number?
		local multiplier = 1
		if isJuken(context) then
			multiplier *= Clan.Tuning.JukenDamageMultiplier
		end
		if isUchihaKaton(context) then
			multiplier *= Clan.Tuning.UchihaKatonMultiplier
		end
		return if multiplier ~= 1 then multiplier else nil
	end,

	AfterHit = function(context: any, result: string)
		local target: Model = context.TargetCharacter
		local clanId = Clan.getClan(context.Attacker)

		-- Maestría: derribar a otro jugador (con o sin el modo activo)
		if result == "Downed" then
			rewardAgainst(context.Attacker, context.TargetPlayer or Players:GetPlayerFromCharacter(target), "Down", Clan.Tuning.Mastery.Down)
		end

		-- Uzumaki: marcas de sello
		if clanId == "Uzumaki" and MELEE_SOURCES[context.SourceType or ""] then
			Clan.addMark("Uzumaki", target, context.Attacker, Clan.Tuning.UzumakiMaxMarks, Clan.Tuning.UzumakiMarkDuration)
		end

		-- Hyūga: tenketsu
		if isJuken(context) then
			local count = Clan.addMark("Tenketsu", target, context.Attacker, Clan.Tuning.JukenMaxMarks, Clan.Tuning.JukenMarkDuration)
			applyStatus(target, "TenketsuClosed", { Duration = Clan.Tuning.JukenMarkDuration, SourcePlayer = context.Attacker })
			if count >= Clan.Tuning.JukenMaxMarks then
				Clan.clearMarks("Tenketsu", target)
				applyStatus(target, "TenketsuSealed", { Duration = Clan.Tuning.JukenSealDuration, SourcePlayer = context.Attacker })
				Clan.fxAll("TenketsuSealed", { Target = target })
			end
		end
	end,
})

-- Uchiha: con el Sharingan activo, los genjutsu que te lanzan duran la mitad
Genjutsu.addDurationModifier(function(target: any, _options: {[string]: any}): number?
	local character: Model = target.Character
	if not Clan.isModeActive(character, "SharinganActive") then
		return nil
	end
	Clan.fxTo(Players:GetPlayerFromCharacter(character), "Icon", { Icon = "GenjutsuResisted" })
	return Clan.Tuning.SharinganGenjutsuMultiplier
end)

-- Uchiha: Genjutsu Kaeshi (3 tomoe). Con el Sharingan activo, si bloqueas justo a tiempo (el
-- bloqueo empezó como mucho KaeshiPerfectWindow antes) un genjutsu de alguien que ves, le rebota.
-- No es pasivo: hace falta reflejo (el sonido del Sharingan avisa), y tiene recarga. El genjutsu
-- rebotado no vuelve a rebotar.
local kaeshiReadyAt: {[Player]: number} = {}
Players.PlayerRemoving:Connect(function(player)
	kaeshiReadyAt[player] = nil
end)

Genjutsu.addInterceptor(function(target: any, options: {[string]: any}): any?
	local character: Model = target.Character
	local defender = Players:GetPlayerFromCharacter(character)
	local attacker: Player? = options.Attacker
	local attackerCharacter = attacker and attacker.Character
	if not defender or not attackerCharacter or attackerCharacter == character
		or not Clan.isModeActive(character, "SharinganActive")
		or Clan.sharinganTomoe(defender) < Clan.Tuning.KaeshiMinTomoe then
		return nil
	end
	local now = Workspace:GetServerTimeNow()
	local blockedAt = character:GetAttribute("BlockStartedAt")
	if typeof(blockedAt) ~= "number" or now - blockedAt > Clan.Tuning.KaeshiPerfectWindow then
		return nil
	end
	if (kaeshiReadyAt[defender] or 0) > now then
		return nil
	end
	if not Genjutsu.canSee(character, attackerCharacter) then
		return nil
	end
	local humanoid = attackerCharacter:FindFirstChildOfClass("Humanoid")
	local root = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	kaeshiReadyAt[defender] = now + Clan.Tuning.KaeshiCooldown
	Clan.fxAll("GenjutsuReflected", { Character = character, Target = attackerCharacter })
	Clan.addMastery(defender, Clan.Tuning.Mastery.Kaeshi, "Kaeshi")
	return { Character = attackerCharacter, Humanoid = humanoid, Root = root }
end)

-- Uchiha: Copia (3 tomoe) ---------------------------------------------------------------------
-- copied[jugador] = el último jutsu que leyó y se puede copiar (lo rellena la lectura, abajo)

type Copied = { JutsuId: string, Name: string, Until: number }
local copied: {[Player]: Copied} = {}

function Clan.getCopied(player: Player): (string?, string?)
	local entry = copied[player]
	if not entry or Workspace:GetServerTimeNow() > entry.Until then
		copied[player] = nil
		return nil, nil
	end
	return entry.JutsuId, entry.Name
end

function Clan.consumeCopied(player: Player)
	if copied[player] then
		copied[player] = nil
		Clan.fxTo(player, "CopyCleared", {})
	end
end

local function rememberCopy(viewer: Player, jutsuId: string, info: {[string]: any})
	if Clan.sharinganTomoe(viewer) < Clan.Tuning.CopyMinTomoe
		or Clan.Tuning.CopyCategories[info.Category or ""] ~= true then
		return
	end
	local name = if typeof(info.DisplayName) == "string" then info.DisplayName else jutsuId
	copied[viewer] = { JutsuId = jutsuId, Name = name, Until = Workspace:GetServerTimeNow() + Clan.Tuning.CopyDuration }
	-- Solo se avisa a quien tiene la Copia equipada
	if isEquipped(viewer, "SharinganCopy") then
		Clan.fxTo(viewer, "Copied", {
			Name = name,
			Duration = Clan.Tuning.CopyDuration,
			Category = info.Category,
			NatureId = info.NatureId,
			IconId = info.IconId,
		})
	end
end

-- Uchiha: lectura del Sharingan ---------------------------------------------------------------

-- Técnicas sin trayectoria que dibujar (modos, sobre uno mismo, posturas)
local NO_TRAJECTORY = {
	Sharingan = true,
	Byakugan = true,
	GenjutsuKai = true,
	Henge = true,
	Shosen = true,
	Nawanuke = true,
	CounterStance = true,
	ChakuraNagashi = true,
	IllusionClone = true,
	KoriShinchu = true,
}

local function onCastStarted(caster: Player, character: Model, jutsuId: string, info: {[string]: any})
	local casterRoot = character:FindFirstChild("HumanoidRootPart")
	if not casterRoot or not casterRoot:IsA("BasePart") then
		return
	end
	local direction = if typeof(info.Direction) == "Vector3" and not NO_TRAJECTORY[jutsuId]
		then info.Direction
		else nil

	for _, viewer in Players:GetPlayers() do
		local viewerCharacter = viewer.Character
		if viewer == caster or not viewerCharacter
			or not Clan.isModeActive(viewerCharacter, "SharinganActive") then
			continue
		end
		local viewerRoot = viewerCharacter:FindFirstChild("HumanoidRootPart")
		local range = (Clan.Tuning.SharinganReadRangeByTomoe[Clan.sharinganTomoe(viewer)] or 60)
			* (if Clan.eyeStrainReadMultiplier then Clan.eyeStrainReadMultiplier(viewer) else 1)
		if not viewerRoot or not viewerRoot:IsA("BasePart")
			or (viewerRoot.Position - casterRoot.Position).Magnitude > range then
			continue
		end
		-- El Sharingan solo lee lo que tienes delante y sin paredes en medio
		if not Genjutsu.canSee(viewerCharacter, character) then
			continue
		end
		rememberCopy(viewer, jutsuId, info)
		rewardRead(viewer, caster)
		Clan.fxTo(viewer, "SharinganRead", {
			Caster = character,
			Token = info.Token,
			Name = info.DisplayName or jutsuId,
			Category = info.Category,
			StartedAt = info.StartedAt,
			CastTime = info.CastTime,
			Direction = direction,
			Range = info.Range,
			NatureId = info.NatureId,
			IconId = info.IconId,
		})
	end
end

task.spawn(function()
	local castStarted = ServerStorage:WaitForChild("JutsuInternal"):WaitForChild("CastStarted")
	if not castStarted:IsA("BindableEvent") then
		warn("[Clan] JutsuInternal > CastStarted no es un BindableEvent: sin lectura del Sharingan")
		return
	end
	castStarted.Event:Connect(function(caster: Player, character: Model, jutsuId: string, info: any)
		local ok, err = pcall(onCastStarted, caster, character, jutsuId, info)
		if not ok then
			warn("[Clan] Lectura del Sharingan: " .. tostring(err))
		end
	end)
end)

-- Maestría: grip / execute (DownedServer dispara CombatInternal > ExecutionCompleted)
task.spawn(function()
	local folder = ServerStorage:WaitForChild("CombatInternal", 10)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatInternal"
		folder.Parent = ServerStorage
	end
	local event = (folder :: Instance):FindFirstChild("ExecutionCompleted")
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = "ExecutionCompleted"
		event.Parent = folder
	end
	(event :: BindableEvent).Event:Connect(function(attacker: Player, victim: Player)
		rewardAgainst(attacker, victim, "Execute", Clan.Tuning.Mastery.Execute)
		-- Requisito del Mangekyō: ejecuciones con el Sharingan activo
		if Clan.onSharinganExecution then
			Clan.onSharinganExecution(attacker, victim)
		end
	end)
end)

-- Uchiha: clash con el indicador ----------------------------------------------------------
-- El indicador lo calcula ClanClient con la misma lógica que el contraataque de la G
-- (ReplicatedStorage > Throwables > ClientShots). Aquí solo se suma la maestría: ThrowableServer
-- avisa de cada contraataque válido por ServerStorage > CombatInternal > DefensiveIntercept.
task.spawn(function()
	local folder = ServerStorage:WaitForChild("CombatInternal", 10)
	if not folder then
		return
	end
	local event = folder:FindFirstChild("DefensiveIntercept")
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = "DefensiveIntercept"
		event.Parent = folder
	end
	(event :: BindableEvent).Event:Connect(function(player: Player, ownerUserId: number, _projectileType: string)
		local character = player.Character
		if character and Clan.isModeActive(character, "SharinganActive") then
			rewardAgainst(player, Players:GetPlayerByUserId(ownerUserId), "Clash",
				Clan.Tuning.Mastery.Clash, Clan.Tuning.Mastery.ClashCooldown)
		end
	end)
end)

-- Dōjutsu: ver la sustitución -----------------------------------------------------------------
-- Tras sustituirse, el jugador queda invisible un momento (SubstitutionServer). Con el Sharingan
-- activo y 2+ tomoe, si lo tenías delante (campo de visión y alcance de la lectura, sin paredes),
-- o con el Byakugan activo a ≤ ByakuganSubstitutionRange, ves remanentes suyos mientras se mueve
-- invisible: la dirección, no la posición exacta (ClanClient). SubstitutionServer avisa por
-- CombatInternal > Substituted (jugador, atacante, CFrame de antes).
local function sharinganSeesPoint(viewer: Model, point: Vector3, range: number): boolean
	local root = viewer:FindFirstChild("HumanoidRootPart")
	local head = viewer:FindFirstChild("Head")
	if not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then
		return false
	end
	local offset = point - head.Position
	if offset.Magnitude > range then
		return false
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if look.Magnitude > 1e-3 and flat.Magnitude > 1e-3 then
		local angle = math.deg(math.acos(math.clamp(look.Unit:Dot(flat.Unit), -1, 1)))
		if angle > Genjutsu.FieldOfView then
			return false
		end
	end
	return true
end

local function onSubstituted(targetPlayer: Player, oldCFrame: CFrame)
	local target = targetPlayer.Character
	if not target or typeof(oldCFrame) ~= "CFrame" then
		return
	end
	local origin = oldCFrame.Position + Vector3.yAxis * 1.5
	local hiddenUntil = target:GetAttribute("SubstitutionHiddenUntil")
	local duration = if typeof(hiddenUntil) == "number" then hiddenUntil - Workspace:GetServerTimeNow() else 0.65
	if duration <= 0 then
		return
	end
	for _, viewer in Players:GetPlayers() do
		local viewerCharacter = viewer.Character
		if viewer == targetPlayer or not viewerCharacter then
			continue
		end
		-- Byakugan: 360°, a corta distancia, a través de paredes (como ya ve a través del humo)
		if Clan.isModeActive(viewerCharacter, "ByakuganActive") then
			local viewerRoot = viewerCharacter:FindFirstChild("HumanoidRootPart")
			if viewerRoot and viewerRoot:IsA("BasePart")
				and (viewerRoot.Position - origin).Magnitude <= Clan.Tuning.ByakuganSubstitutionRange then
				Clan.fxTo(viewer, "SubstitutionRead", { Character = target, Duration = duration, Kind = "Byakugan" })
			end
			continue
		end
		if not Clan.isModeActive(viewerCharacter, "SharinganActive") then
			continue
		end
		local tomoe = Clan.sharinganTomoe(viewer)
		if tomoe < Clan.Tuning.SubstitutionReadMinTomoe then
			continue
		end
		local range = Clan.Tuning.SharinganReadRangeByTomoe[tomoe] or 60
		if not sharinganSeesPoint(viewerCharacter, origin, range) then
			continue
		end
		-- Sin paredes entre tus ojos y donde estaba
		local head = viewerCharacter:FindFirstChild("Head") :: BasePart
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { viewerCharacter, target }
		params.IgnoreWater = true
		local hit = Workspace:Raycast(head.Position, origin - head.Position, params)
		if hit and hit.Instance.CanCollide and hit.Instance.Transparency < 0.9 then
			continue
		end
		Clan.fxTo(viewer, "SubstitutionRead", { Character = target, Duration = duration, Kind = "Sharingan" })
		rewardAgainst(viewer, targetPlayer, "SubstitutionRead", Clan.Tuning.Mastery.SubstitutionRead)
	end
end

task.spawn(function()
	-- CombatServer lo crea al arrancar; esperar evita crear una segunda carpeta
	local folder = ServerStorage:WaitForChild("CombatInternal", 10)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatInternal"
		folder.Parent = ServerStorage
	end
	local event = (folder :: Folder):FindFirstChild("Substituted")
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = "Substituted"
		event.Parent = folder :: Folder
	end
	(event :: BindableEvent).Event:Connect(function(targetPlayer: Player, _attacker: Player?, oldCFrame: CFrame)
		local ok, err = pcall(onSubstituted, targetPlayer, oldCFrame)
		if not ok then
			warn("[Clan] Ver la sustitución: " .. tostring(err))
		end
	end)
end)

-- Uchiha: despertar por etapas ---------------------------------------------------------------

-- Sube a esa etapa con su momento de despertar (ClanClient: "ClanAwakened")
local function awaken(player: Player, stage: number)
	local entry = progress[player]
	if not entry or not entry.Loaded then
		return
	end
	entry.Stage = math.clamp(stage, 0, #Clan.Tuning.SharinganStageLevels)
	saveProgress(player, entry)
	local character = player.Character
	if entry.ClanId == "Uchiha" and character and entry.Stage >= 1 then
		if Clan.isModeActive(character, "SharinganActive") then
			-- Ya activo: se ajusta al momento (más tomoe = menos gasto, sellos más rápidos…)
			Clan.refreshMode(character, "SharinganActive")
		elseif entry.Stage == 1 and modeDefinitions.SharinganActive then
			-- El primer despertar enciende el Sharingan solo (sin coste)
			Clan.startMode(player, character, modeDefinitions.SharinganActive)
		end
	end
	if entry.Stage >= 1 then
		Clan.fxAll("ClanAwakened", { Character = character, Player = player, ClanId = entry.ClanId, Stage = entry.Stage })
	end
end
Clan.awaken = awaken

-- 2 y 3 tomoe: nivel y maestría (el primero despierta en peligro, abajo)
checkStageUp = function(player: Player)
	local entry = progress[player]
	if not entry or not entry.Loaded or entry.ClanId ~= "Uchiha" or entry.Stage < 1 then
		return
	end
	local nextStage = entry.Stage + 1
	if nextStage > #Clan.Tuning.SharinganStageLevels then
		return
	end
	local level = player:GetAttribute("CharacterLevel")
	level = if typeof(level) == "number" then level else 1
	if level >= Clan.Tuning.SharinganStageLevels[nextStage]
		and entry.Mastery >= Clan.Tuning.SharinganStageMastery[nextStage] then
		awaken(player, nextStage)
	end
end

-- 1 tomoe: con nivel suficiente, en combate y con la vida baja, el Sharingan despierta
local function watchDanger(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.HealthChanged:Connect(function(health: number)
		local entry = progress[player]
		if not entry or not entry.Loaded or entry.ClanId ~= "Uchiha" or entry.Stage ~= 0
			or player.Character ~= character then
			return
		end
		local level = player:GetAttribute("CharacterLevel")
		if typeof(level) ~= "number" or level < Clan.Tuning.SharinganStageLevels[1] then
			return
		end
		if health > 0 and health <= humanoid.MaxHealth * Clan.Tuning.SharinganAwakenHealthFraction
			and inCombat(player) then
			awaken(player, 1)
		end
	end)
end

-- Uchiha: Mangekyō Sharingan --------------------------------------------------------------------
-- Etapa 4 = Mangekyō, 5 = Eterno. Requisitos: 3 tomoe, nivel MangekyoMinLevel, maestría
-- MangekyoMinMastery y MangekyoMinExecutions ejecuciones con el Sharingan activo. Despierta cuando
-- un compañero de squad con 3 tomoe (o más) muere de verdad (CombatInternal > FinalDeath) a
-- ≤ MangekyoWitnessRange delante de ti con el Sharingan activo; da igual quién lo ejecute. Una vez
-- por vida. El tipo sale al azar entre los que ya tienen habilidades (Implemented).
-- Tecla Z (JutsuController): toque = Sharingan · doble toque = Mangekyō · mantener = Susanoo.
-- El Mangekyō es el mismo modo SharinganActive con más gasto y el atributo MangekyoActive (todo lo
-- del Sharingan sigue funcionando); el Susanoo es otro modo (SusanooActive) encima del Mangekyō.
-- Fatiga ocular (Eye Strain): sube con las habilidades del Mangekyō (Clan.addEyeStrain) y el Susanoo; baja fuera de
-- combate; al máximo no puedes usar el Mangekyō hasta que baje. El Eterno no se ciega.

-- Cada Mangekyō es propio: dos habilidades (un ojo de ataque y uno de control), color e iris y
-- arma del Susanoo, sorteados por separado (ReplicatedStorage > Shared > MangekyoCatalog).
Clan.MangekyoCatalog = MangekyoCatalog

function Clan.hasMangekyo(player: Player?): boolean
	return Clan.getClan(player) == "Uchiha" and Clan.getStage(player) >= 4
end

function Clan.hasEternal(player: Player?): boolean
	return Clan.getClan(player) == "Uchiha" and Clan.getStage(player) >= 5
end

-- El Mangekyō del jugador (copia) o nil si no lo ha despertado
function Clan.getMangekyo(player: Player?): {[string]: string}?
	local entry = player and progress[player]
	return if entry and entry.Stage >= 4 and entry.Mangekyo then table.clone(entry.Mangekyo) else nil
end

-- ¿Tiene esta habilidad en alguno de sus ojos?
function Clan.hasMangekyoAbility(player: Player?, abilityId: string): boolean
	local mangekyo = Clan.getMangekyo(player)
	return mangekyo ~= nil and (mangekyo.Attack == abilityId or mangekyo.Control == abilityId)
end

function Clan.getEyeStrain(player: Player?): number
	local entry = player and progress[player]
	return if entry and not Clan.hasEternal(player) then entry.EyeStrain else 0
end

function Clan.isMangekyoActive(character: Model?): boolean
	return character ~= nil and character:GetAttribute("MangekyoActive") == true
end

function Clan.isEyeStrainLocked(player: Player?): boolean
	return not Clan.hasEternal(player) and Clan.getEyeStrain(player) >= Clan.Tuning.EyeStrainMax
end

-- Multiplicadores por ceguera: lectura del Sharingan y recarga de las habilidades del Mangekyō
function Clan.eyeStrainReadMultiplier(player: Player?): number
	return if Clan.getEyeStrain(player) >= Clan.Tuning.EyeStrainReadPenaltyAt
		then Clan.Tuning.EyeStrainReadRangeMultiplier
		else 1
end

function Clan.eyeStrainCooldownMultiplier(player: Player?): number
	return if Clan.getEyeStrain(player) >= Clan.Tuning.EyeStrainCooldownPenaltyAt
		then Clan.Tuning.EyeStrainCooldownMultiplier
		else 1
end

-- Lo que el modo SharinganActive añade cuando está en Mangekyō (lo llama Jutsus > Sharingan)
function Clan.mangekyoConfig(player: Player): {[string]: any}?
	if not wantMangekyo[player] or not Clan.hasMangekyo(player) or Clan.isEyeStrainLocked(player) then
		return nil
	end
	local mangekyo = Clan.getMangekyo(player)
	return {
		DrainPerSecond = Clan.Tuning.MangekyoDrainPerSecond,
		Attributes = {
			MangekyoActive = true,
			MangekyoAttack = mangekyo and mangekyo.Attack,
			MangekyoControl = mangekyo and mangekyo.Control,
			MangekyoColor = mangekyo and mangekyo.Color or MangekyoCatalog.DefaultColor,
			MangekyoIris = mangekyo and mangekyo.Iris or "Itachi",
			MangekyoWeapon = mangekyo and mangekyo.Weapon or MangekyoCatalog.DefaultWeapon,
			MangekyoEternal = if Clan.hasEternal(player) then true else nil,
		},
	}
end

-- Enciende o apaga el Mangekyō: con el Sharingan encendido se recalcula; si no, se enciende ya
-- en Mangekyō. Apagarlo también apaga el Susanoo.
function Clan.setMangekyoMode(player: Player, character: Model, on: boolean)
	local was = Clan.isMangekyoActive(character)
	wantMangekyo[player] = if on then true else nil
	if not on and modes[character] and modes[character].SusanooActive then
		Clan.stopMode(character, "SusanooActive")
	end
	if Clan.isModeActive(character, "SharinganActive") then
		Clan.refreshMode(character, "SharinganActive")
	elseif on and modeDefinitions.SharinganActive then
		Clan.startMode(player, character, modeDefinitions.SharinganActive)
	end
	local now = Clan.isMangekyoActive(character)
	if now and not was then
		local mangekyo = Clan.getMangekyo(player)
		-- Type = clave del iris (los clientes dibujan con ella)
		Clan.fxAll("MangekyoStart", { Character = character, Type = mangekyo and mangekyo.Iris })
	elseif was and not now then
		Clan.fxAll("MangekyoEnd", { Character = character })
	end
end

local eyeStrainSaveAt: {[Player]: number} = {}

local function setEyeStrain(player: Player, value: number)
	local entry = progress[player]
	if not entry or not entry.Loaded then
		return
	end
	local before = entry.EyeStrain
	entry.EyeStrain = math.clamp(value, 0, Clan.Tuning.EyeStrainMax)
	if math.floor(before) ~= math.floor(entry.EyeStrain) then
		publishProgress(player, entry)
		-- Se guarda como mucho cada 10 s (sube y baja de poco en poco)
		local now = os.clock()
		if (eyeStrainSaveAt[player] or 0) <= now or entry.EyeStrain <= 0 then
			eyeStrainSaveAt[player] = now + 10
			saveProgress(player, entry)
		end
	end
end

-- Suma ceguera (habilidades del Mangekyō, Susanoo). Al máximo, el Mangekyō se apaga y vuelve al
-- Sharingan normal hasta que baje.
function Clan.addEyeStrain(player: Player?, amount: number)
	if not player or amount <= 0 or not Clan.hasMangekyo(player) or Clan.hasEternal(player) then
		return
	end
	local entry = progress[player]
	if not entry then
		return
	end
	local wasLocked = Clan.isEyeStrainLocked(player)
	setEyeStrain(player, entry.EyeStrain + amount)
	if not wasLocked and Clan.isEyeStrainLocked(player) then
		local character = player.Character
		if character and Clan.isMangekyoActive(character) then
			Clan.setMangekyoMode(player, character, false)
		end
		Clan.fxTo(player, "Icon", { Icon = "EyeStrainLocked" })
	end
end

-- Fuera de combate la ceguera baja poco a poco
task.spawn(function()
	while true do
		task.wait(1)
		for player, entry in progress do
			if entry.Loaded and entry.EyeStrain > 0 and player.Parent and not inCombat(player) then
				setEyeStrain(player, entry.EyeStrain - Clan.Tuning.EyeStrainDecayPerSecond)
			end
		end
	end
end)

-- Ejecuciones con el Sharingan activo (requisito del Mangekyō). Contra novatos no cuentan.
function Clan.onSharinganExecution(attacker: Player?, victim: Player?)
	local entry = attacker and progress[attacker]
	local character = attacker and attacker.Character
	if not attacker or not entry or not entry.Loaded or entry.ClanId ~= "Uchiha"
		or not character or not Clan.isModeActive(character, "SharinganActive")
		or (victim and victim:GetAttribute("NoviceProtected") == true) then
		return
	end
	entry.Executions += 1
	saveProgress(attacker, entry)
end

local function mangekyoRequirementsMet(player: Player): boolean
	local entry = progress[player]
	if not entry or not entry.Loaded or entry.ClanId ~= "Uchiha" or entry.Stage ~= 3 then
		return false
	end
	local level = player:GetAttribute("CharacterLevel")
	return typeof(level) == "number" and level >= Clan.Tuning.MangekyoMinLevel
		and entry.Mastery >= Clan.Tuning.MangekyoMinMastery
		and entry.Executions >= Clan.Tuning.MangekyoMinExecutions
end

-- Despierta el Mangekyō (etapa 4): su Mangekyō propio sorteado (forced: partes fijadas a mano,
-- { Attack, Control, Color, Iris, Weapon }; lo que falte se sortea) y lo enciende con su momento de despertar
function Clan.awakenMangekyo(player: Player, forced: {[string]: any}?): boolean
	local entry = progress[player]
	if not entry or not entry.Loaded or entry.ClanId ~= "Uchiha" then
		return false
	end
	local mangekyo = MangekyoCatalog.sanitize(forced, ClanAssets.MangekyoIris)
	entry.Stage = math.max(entry.Stage, 4)
	entry.Mangekyo = mangekyo :: any
	entry.EyeStrain = 0
	saveProgress(player, entry)
	local character = player.Character
	-- Si ya lo tenía encendido, se recalcula con el nuevo (atributos, color, iris)
	if character and Clan.isMangekyoActive(character) and Clan.isModeActive(character, "SharinganActive") then
		Clan.refreshMode(character, "SharinganActive")
	end
	Clan.fxAll("MangekyoAwakened", { Character = character, Player = player, Type = mangekyo.Iris })
	if character then
		Clan.setMangekyoMode(player, character, true)
	end
	print("[Clan] MANGEKYŌ", player.Name, mangekyo.Attack, mangekyo.Control, mangekyo.Color, mangekyo.Iris, mangekyo.Weapon)
	return true
end

-- ¿Son del mismo squad? (SquadService.AreSquadmates)
local function areSquadmates(a: Player, b: Player): boolean
	local SquadService = lateService("SquadService")
	if not SquadService or typeof(SquadService.AreSquadmates) ~= "function" then
		return false
	end
	local ok, result = pcall(SquadService.AreSquadmates, a, b)
	return ok and result == true
end

-- El método: un compañero de squad con 3 tomoe muere de verdad delante de ti
local function onFinalDeathWitness(victim: Player, _killer: any)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return
	end
	local victimEntry = progress[victim]
	local victimCharacter = victim.Character
	local victimHead = victimCharacter and victimCharacter:FindFirstChild("Head")
	if not victimEntry or victimEntry.ClanId ~= "Uchiha" or victimEntry.Stage < 3
		or not victimHead or not victimHead:IsA("BasePart") then
		return
	end
	for _, witness in Players:GetPlayers() do
		local character = witness.Character
		if witness == victim or not character or not Clan.isModeActive(character, "SharinganActive")
			or not mangekyoRequirementsMet(witness) or not areSquadmates(witness, victim) then
			continue
		end
		if sharinganSeesPoint(character, victimHead.Position, Clan.Tuning.MangekyoWitnessRange) then
			Clan.awakenMangekyo(witness)
		end
	end
end

task.spawn(function()
	local folder = ServerStorage:WaitForChild("CombatInternal", 10)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatInternal"
		folder.Parent = ServerStorage
	end
	local event = (folder :: Instance):FindFirstChild("FinalDeath")
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = "FinalDeath"
		event.Parent = folder
	end
	(event :: BindableEvent).Event:Connect(function(victim: Player, killer: any)
		local ok, err = pcall(onFinalDeathWitness, victim, killer)
		if not ok then
			warn("[Clan] Mangekyō (testigo): " .. tostring(err))
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	wantMangekyo[player] = nil
	eyeStrainSaveAt[player] = nil
end)

-- Pruebas (solo servidor): ServerStorage > JutsuInternal > ClanDev
task.spawn(function()
	local internal = ServerStorage:WaitForChild("JutsuInternal")
	local dev = internal:FindFirstChild("ClanDev")
	if not dev then
		dev = Instance.new("BindableFunction")
		dev.Name = "ClanDev"
		dev.Parent = internal
	end
	(dev :: BindableFunction).OnInvoke = function(action: string, player: Player, value: any): any
		if action == "SetStage" and typeof(value) == "number" then
			awaken(player, value)
		elseif action == "AddMastery" and typeof(value) == "number" then
			Clan.addMastery(player, value, "Dev")
		elseif action == "SetMangekyo" then
			-- value = nil (todo al azar) · { Attack, Control, Color, Iris, Weapon } (lo que falte, al azar)
			-- · "Itachi" (Amaterasu + Tsukuyomi, como el antiguo)
			local forced = if typeof(value) == "table" then value
				elseif value == "Itachi" then { Attack = "Amaterasu", Control = "Tsukuyomi", Color = "Crimson", Iris = "Itachi" }
				else nil
			Clan.awakenMangekyo(player, forced)
		elseif action == "SetEyeStrain" and typeof(value) == "number" then
			setEyeStrain(player, value)
		elseif action == "SetExecutions" and typeof(value) == "number" then
			local entry = progress[player]
			if entry then
				entry.Executions = math.max(0, math.floor(value))
				saveProgress(player, entry)
			end
		end
		local entry = progress[player]
		return {
			ClanId = entry and entry.ClanId,
			Loaded = entry and entry.Loaded,
			Stage = Clan.getStage(player),
			Mastery = Clan.getMastery(player),
			Mangekyo = Clan.getMangekyo(player),
			EyeStrain = Clan.getEyeStrain(player),
			Executions = entry and entry.Executions,
		}
	end
end)

-- Uzumaki: fuerza vital (DownedServer lee DownedTimeMultiplier)
local function refreshVitality(player: Player)
	player:SetAttribute(
		"DownedTimeMultiplier",
		if Clan.getClan(player) == "Uzumaki" then Clan.Tuning.UzumakiDownedMultiplier else nil
	)
end

local function bindPlayer(player: Player)
	refreshVitality(player)
	loadProgress(player)
	player:GetAttributeChangedSignal("ClanId"):Connect(function()
		-- Otro clan: los modos del anterior (Sharingan, Byakugan…) se apagan
		stopModesOf(player, nil)
		refreshVitality(player)
		loadProgress(player)
	end)
	-- Subir de nivel puede despertar la siguiente etapa
	player:GetAttributeChangedSignal("CharacterLevel"):Connect(function()
		if checkStageUp then
			checkStageUp(player)
		end
	end)
	-- Al reaparecer, los modos del cuerpo anterior se apagan ya (y los ojos vuelven a Base)
	player.CharacterAdded:Connect(function(character)
		stopModesOf(player, character)
		task.spawn(watchDanger, player, character)
	end)
	if player.Character then
		task.spawn(watchDanger, player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

-- Limpieza de modos al salir
Players.PlayerRemoving:Connect(function(player)
	stopModesOf(player, nil)
	copied[player] = nil
	progress[player] = nil
	sustainReadyAt[player] = nil
	victimRewardAt[player] = nil
	readCounts[player] = nil
end)

Clan.clanOfCharacter = clanOfCharacter

return Clan
