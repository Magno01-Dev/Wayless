-- ServerScriptService > JutsuSystem > TechniqueKit > Clan  (ModuleScript)
--
-- Base común de las mecánicas de clan (PLANEACION_CLANES.md, etapa 1).
--
--   Clan.build(module, clanId, execute)   técnica de clan (requiere ClanId para aprender y usar)
--   Clan.buildMode(module, clanId, opts)  modo que se activa / desactiva con la misma tecla
--                                         (Sharingan, Byakugan): gasta chakra por segundo y
--                                         con él activo no regeneras chakra
--   Clan.addMark / getMarks / clearMarks  marcas en el objetivo (sellos Uzumaki, tenketsu Hyūga)
--
-- Pasivas (se registran al cargar este módulo, que lo cargan los jutsus de clan al arrancar):
--   Uzumaki  fuerza vital: el Downed dura ×0.7 (DownedServer v31.6) · sus golpes cuerpo a
--            cuerpo dejan marcas de sello (máx. 3, 8 s)
--   Hyūga    Jūken: sus M1 y taijutsu SIN ARMA hacen −10 % y cierran tenketsu (máx. 5, 8 s):
--            menos regeneración de chakra; con 5, 2 s sin chakra
--   Nara     trampas mejores (ThrowableServer v3.3): minas y abrojos duran el doble y las
--            minas siempre son ocultas
--
-- Efectos visuales: remote ReplicatedStorage > JutsuSystem > Remotes > ClanFX
-- (StarterPlayerScripts > ClanClient). Las marcas y los modos también se publican como
-- atributos del personaje, que ClanClient dibuja.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Genjutsu = require(script.Parent:WaitForChild("Genjutsu"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local ChakraService = require(ServerScriptService:WaitForChild("ChakraService"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))

local Clan = {}

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

type Mode = { Attribute: string, Status: string?, Token: number }
local modes: {[Model]: {[string]: Mode}} = {}
local modeSequence = 0

function Clan.isModeActive(character: Model, attribute: string): boolean
	return modes[character] ~= nil and modes[character][attribute] ~= nil
end

function Clan.stopMode(character: Model, attribute: string)
	local byAttribute = modes[character]
	local mode = byAttribute and byAttribute[attribute]
	if not mode then
		return
	end
	byAttribute[attribute] = nil
	if character.Parent then
		character:SetAttribute(attribute, nil)
		if mode.Status and StatusEffectService.Has(character, mode.Status) then
			StatusEffectService.Remove(character, mode.Status, "ModeEnd")
		end
	end
	Clan.fxAll("ModeEnd", { Character = character, Attribute = attribute })
end

--[[
	opts = {
		Attribute       atributo del personaje mientras está activo ("SharinganActive")
		DrainPerSecond  chakra por segundo
		Status          estado mientras está activo (p. ej. "DojutsuActive": sin regenerar chakra)
	}
]]
function Clan.startMode(player: Player, character: Model, opts: {[string]: any})
	local attribute = opts.Attribute
	Clan.stopMode(character, attribute)
	modeSequence += 1
	local mode: Mode = { Attribute = attribute, Status = opts.Status, Token = modeSequence }
	modes[character] = modes[character] or {}
	modes[character][attribute] = mode

	character:SetAttribute(attribute, true)
	if opts.Status then
		applyStatus(character, opts.Status, { Duration = 3600 })
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
				or character:GetAttribute("Status_ChakraSuppressed") == true then
				Clan.stopMode(character, attribute)
				return
			end
			local spent = ChakraService.TrySpend(player, opts.DrainPerSecond * interval, "Mode:" .. attribute)
			if not spent then
				Clan.stopMode(character, attribute)
				Clan.fxTo(player, "ModeNoChakra", { Attribute = attribute })
				return
			end
		end
	end)
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
	Clan.build(module, clanId, function(context)
		Clan.startMode(context.Player, context.Character, opts)
	end)

	local baseSanitize = module.SanitizeRequest
	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		if Clan.isModeActive(character, opts.Attribute) then
			Clan.stopMode(character, opts.Attribute)
			return false, "Toggled", nil
		end
		return baseSanitize(character, payload)
	end

	return module
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

Clan.Tuning = {
	UzumakiDownedMultiplier = 0.7,
	UzumakiMaxMarks = 3,
	UzumakiMarkDuration = 8,
	JukenDamageMultiplier = 0.9,
	JukenMaxMarks = 5,
	JukenMarkDuration = 8,
	JukenSealDuration = 2,
}

DamageService.AddHook({
	ModifyDamage = function(context: any): number?
		if isJuken(context) then
			return Clan.Tuning.JukenDamageMultiplier
		end
		return nil
	end,

	AfterHit = function(context: any, _result: string)
		local target: Model = context.TargetCharacter
		local clanId = Clan.getClan(context.Attacker)

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

-- Uzumaki: fuerza vital (DownedServer lee DownedTimeMultiplier)
local function refreshVitality(player: Player)
	player:SetAttribute(
		"DownedTimeMultiplier",
		if Clan.getClan(player) == "Uzumaki" then Clan.Tuning.UzumakiDownedMultiplier else nil
	)
end

local function bindPlayer(player: Player)
	refreshVitality(player)
	player:GetAttributeChangedSignal("ClanId"):Connect(function()
		refreshVitality(player)
	end)
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

-- Limpieza de modos al reaparecer o salir
Players.PlayerRemoving:Connect(function(player)
	local character = player.Character
	if character and modes[character] then
		modes[character] = nil
	end
end)

Clan.clanOfCharacter = clanOfCharacter

return Clan
