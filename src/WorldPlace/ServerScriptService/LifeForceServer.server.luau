--!strict
-- ServerScriptService > LifeForceServer
--
-- WAYLESS · Fuerza vital (Life Force) v1
--
-- Cada vida empieza con 100. Una muerte REAL (ejecución / grip) resta fuerza vital según quién te
-- mató; al llegar a 0 vas al Afterlife (AfterlifeTransferService.HandleFinalDeath), donde un NPC
-- te deja borrar el personaje o revivir (tokens / Robux). Revivir devuelve el 100 %. Nunca es un
-- borrado inmediato.
--
-- Pérdida por muerte (Tuning):
--   PvP contra alguien de tu nivel o más débil ........ 20 %  (5 vidas)
--   PvP contra alguien bastante más fuerte ............ 10 %  (+15 niveles o 1 rango más)
--   PvP contra alguien muy superior ................... 5 %   (+30 niveles o 2 rangos más)
--   NPC, jefes y PvE en general ....................... 5 %
--   Desconectarse en combate .......................... 20 %  (CombatLogPenaltyServer)
-- Ganancia: ejecutar a alguien de tu nivel o más fuerte devuelve +3 % (PvP justo, no abuso).
-- Protected Final Death: si te mata alguien muy superior (tier 2), esa muerte no te deja en 0 sino
-- en ProtectedFloor (1 %), salvo que empezaras tú la pelea (CombatTagService.GetTagStartedAt) o
-- seas Rogue.
-- No hay regeneración pasiva: otras formas de recuperarla (misiones, NPC, objetos) usarán
-- ServerStorage > LifeForceInternal > Adjust(jugador, delta, motivo).
--
-- Protección de novato (mientras nivel < NoviceMaxLevel y rango ≤ Genin, y no la hayas perdido):
--   · pierdes la mitad de fuerza vital
--   · una vez cada NoviceSaveCooldown, si te van a ejecutar te salvas: poof y apareces junto al
--     spawn lejos del atacante, sin perder nada (DownedServer pregunta a TryNoviceSave)
--   · la pierdes para siempre en esta vida si TÚ ejecutas a alguien (elegiste el PvP)
--   · ejecutar a un novato no da recompensas (ni PvP justo ni maestría de clan)
--   · atributo del jugador NoviceProtected (icono sobre la cabeza: NoviceProtectionClient)
--
-- Fuente de la muerte: DownedServer dispara ServerStorage > CombatInternal > FinalDeath
-- (víctima, asesino, causa) en el golpe final. El asesino es un Player o, para PvE, otra cosa.
-- El valor vive en AccountProfileService (CurrentLife.LifeForce) y se publica en el atributo del
-- jugador "LifeForce" (0–100) para el HUD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local AccountProfileService = require(Services:WaitForChild("AccountProfileService"))
local CharacterLifeContextService = require(Services:WaitForChild("CharacterLifeContextService"))

local Tuning = {
	MaxLifeForce = 100,
	PvPLossByTier = { [0] = 20, [1] = 10, [2] = 5 }, -- tier = cuánto más fuerte era quien te mató
	PvELoss = 5,
	CombatLogLoss = 20,
	FairPvPReward = 3,
	-- Diferencias para los tiers (nivel = atributo CharacterLevel, rango = NinjaRankOrder)
	StrongerLevelGap = 15,
	FarSuperiorLevelGap = 30,
	StrongerRankGap = 1,
	FarSuperiorRankGap = 2,
	-- PvP justo: la víctima no era más débil que tú (como mucho estos niveles por debajo)
	FairLevelMargin = 5,
	-- Tras llegar a 0, segundos antes de ir al Afterlife (que se vea la ejecución)
	DepletedDelay = 3,
	-- En Studio, llegar a 0 solo se registra (no marca la muerte final ni teletransporta)
	FinalDeathInStudio = false,
	-- Protección de novato
	NoviceMaxLevel = 25, -- protegido mientras el nivel sea menor
	NoviceMaxRankOrder = 2, -- y el rango sea como mucho Genin (1 Estudiante, 2 Genin, 3 Chūnin, 4 Jōnin)
	NoviceLossMultiplier = 0.5,
	NoviceSaveCooldown = 2 * 60 * 60, -- s reales entre salvamentos
	NoviceSaveMinDistance = 120, -- studs mínimos entre el atacante y donde reaparece
	-- Protected Final Death: matarte alguien muy superior (tier 2) no te puede dejar en 0 por sí
	-- solo; te quedas en ProtectedFloor. No protege si empezaste tú la pelea o eres Rogue (con bounty,
	-- guerra o PvP de objetivo tampoco, cuando existan)
	ProtectedFinalDeathTier = 2,
	ProtectedFloor = 1,
}

-- Estado de la protección de novato (caché de AccountProfileService)
local noviceLost: {[Player]: boolean} = {}
local noviceSaveAt: {[Player]: number} = {}

local function slotIdOf(player: Player): string?
	local ok, identity = pcall(CharacterLifeContextService.GetIdentity, player)
	if ok and typeof(identity) == "table" and typeof(identity.SlotId) == "string" and identity.SlotId ~= "" then
		return identity.SlotId
	end
	for _, name in { "CharacterLifeSlotId", "CharacterLifecycleActiveSlotId" } do
		local value = player:GetAttribute(name)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

local function publish(player: Player, value: number?)
	if typeof(value) == "number" then
		player:SetAttribute("LifeForce", value)
	end
end

-- AccountProfileService rechaza mutaciones simultáneas ("AccountProfileBusy"): reintenta un poco
local function adjust(player: Player, delta: number, reason: string, saveNow: boolean): (boolean, string, number?)
	local slotId = slotIdOf(player)
	if not slotId then
		return false, "NoSlot", nil
	end
	local ok, why, value = false, "?", nil
	for _ = 1, 10 do
		ok, why, value = AccountProfileService.AdjustLifeForce(player, slotId, delta, reason, saveNow)
		if ok or why ~= "AccountProfileBusy" then
			break
		end
		task.wait(0.2)
	end
	if ok then
		publish(player, value)
	end
	return ok, why, value
end

-- Fuerza de un jugador para comparar: nivel y orden de rango ninja
local function strengthOf(player: Player): (number, number)
	local level = player:GetAttribute("CharacterLevel")
	local rank = player:GetAttribute("NinjaRankOrder")
	return if typeof(level) == "number" then level else 1, if typeof(rank) == "number" then rank else 0
end

-- 0 = parecido o más débil · 1 = bastante más fuerte · 2 = muy superior (el asesino respecto a ti)
local function strengthTier(killer: Player, victim: Player): number
	local killerLevel, killerRank = strengthOf(killer)
	local victimLevel, victimRank = strengthOf(victim)
	local levelGap = killerLevel - victimLevel
	local rankGap = killerRank - victimRank
	if levelGap >= Tuning.FarSuperiorLevelGap or rankGap >= Tuning.FarSuperiorRankGap then
		return 2
	elseif levelGap >= Tuning.StrongerLevelGap or rankGap >= Tuning.StrongerRankGap then
		return 1
	end
	return 0
end

local function isFairKill(killer: Player, victim: Player): boolean
	local killerLevel, killerRank = strengthOf(killer)
	local victimLevel, victimRank = strengthOf(victim)
	return killerLevel - victimLevel <= Tuning.FairLevelMargin and killerRank <= victimRank
end

local function isNovice(player: Player): boolean
	if noviceLost[player] then
		return false
	end
	local level, rank = strengthOf(player)
	return level < Tuning.NoviceMaxLevel and rank <= Tuning.NoviceMaxRankOrder
end

local function refreshNovice(player: Player)
	player:SetAttribute("NoviceProtected", isNovice(player))
end

local function loseNoviceProtection(player: Player)
	if noviceLost[player] then
		return
	end
	noviceLost[player] = true
	refreshNovice(player)
	local slotId = slotIdOf(player)
	if slotId then
		task.spawn(AccountProfileService.SetNoviceState, player, slotId, true, nil)
	end
	print("[LifeForce] NOVICE PROTECTION LOST", player.Name, "(ejecutó a otro jugador)")
end

-- Lugar seguro para reaparecer: junto a un SpawnLocation lejos del atacante
local function safeDestination(attacker: Player?): CFrame?
	local attackerRoot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local attackerPosition = if attackerRoot and attackerRoot:IsA("BasePart") then attackerRoot.Position else nil
	local best: SpawnLocation? = nil
	local bestDistance = -1
	local candidates: {SpawnLocation} = {}
	for _, spawn in Workspace:GetDescendants() do
		if spawn:IsA("SpawnLocation") and spawn.Enabled then
			local distance = if attackerPosition then (spawn.Position - attackerPosition).Magnitude else math.huge
			if distance >= Tuning.NoviceSaveMinDistance then
				table.insert(candidates, spawn)
			end
			if distance > bestDistance then
				best, bestDistance = spawn, distance
			end
		end
	end
	local spawn = if #candidates > 0 then candidates[math.random(1, #candidates)] else best
	if not spawn then
		return nil
	end
	local offset = Vector3.new(
		(math.random() - 0.5) * spawn.Size.X * 0.6,
		spawn.Size.Y / 2 + 3,
		(math.random() - 0.5) * spawn.Size.Z * 0.6
	)
	return CFrame.new(spawn.Position + offset) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
end

-- DownedServer lo pregunta al EMPEZAR una ejecución: devuelve dónde reaparecer si el novato se
-- salva (y gasta el salvamento), o nil si la ejecución sigue normal
local function tryNoviceSave(victim: Player, attacker: Player?): CFrame?
	if not isNovice(victim) then
		return nil
	end
	local now = os.time()
	local last = noviceSaveAt[victim]
	if last and now - last < Tuning.NoviceSaveCooldown then
		return nil
	end
	local destination = safeDestination(attacker)
	if not destination then
		return nil
	end
	noviceSaveAt[victim] = now
	local slotId = slotIdOf(victim)
	if slotId then
		task.spawn(AccountProfileService.SetNoviceState, victim, slotId, nil, now)
	end
	print("[LifeForce] NOVICE SAVED", victim.Name, "de", attacker and attacker.Name or "?")
	return destination
end

local function sendToAfterlife(player: Player, reason: string)
	if RunService:IsStudio() and not Tuning.FinalDeathInStudio then
		warn("[LifeForce] STUDIO: " .. player.Name .. " llegó a 0 → iría al Afterlife (" .. reason .. ")."
			.. " Tuning.FinalDeathInStudio = true para probarlo de verdad.")
		return
	end
	local ok, AfterlifeTransferService = pcall(function()
		return require(Services:WaitForChild("AfterlifeTransferService"))
	end)
	if not ok then
		warn("[LifeForce] Sin AfterlifeTransferService: " .. tostring(AfterlifeTransferService))
		return
	end
	local sent, why = AfterlifeTransferService.HandleFinalDeath(player, reason)
	print("[LifeForce] AFTERLIFE", player.Name, reason, "->", sent, why)
end

local combatTags: any = nil
local function combatTagService(): any
	if combatTags == nil then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("CombatTagService"))
		end)
		combatTags = if ok then result else false
	end
	return combatTags or nil
end

-- ¿La víctima empezó la pelea? (le pegó al asesino antes de que él le pegara)
local function victimStartedFight(victim: Player, killer: Player): boolean
	local service = combatTagService()
	if not service or typeof(service.GetTagStartedAt) ~= "function" then
		return false
	end
	local victimHit = service.GetTagStartedAt(killer, victim) -- desde cuándo la víctima le pega
	local killerHit = service.GetTagStartedAt(victim, killer) -- desde cuándo el asesino le pega
	return typeof(victimHit) == "number" and (typeof(killerHit) ~= "number" or victimHit < killerHit)
end

-- Protected Final Death: lo pierde quien empezó la pelea o es Rogue (bounty, guerra y PvP de
-- objetivo se añadirán aquí cuando existan)
local function isProtectedFromWipe(victim: Player, killer: Player): boolean
	if victim:GetAttribute("IsRogue") == true then
		return false
	end
	return not victimStartedFight(victim, killer)
end

local function onFinalDeath(victim: Player, killer: any, cause: string?)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return
	end
	local killerPlayer = if typeof(killer) == "Instance" and killer:IsA("Player") and killer ~= victim then killer else nil
	local victimNovice = isNovice(victim)
	local loss: number
	local kind: string
	local tier = 0
	if killerPlayer then
		tier = strengthTier(killerPlayer, victim)
		loss = Tuning.PvPLossByTier[tier] or Tuning.PvPLossByTier[0]
		kind = "PvP:tier" .. tier
	else
		loss = Tuning.PvELoss
		kind = "PvE"
	end
	if victimNovice then
		loss *= Tuning.NoviceLossMultiplier
		kind ..= ":novice"
	end
	-- Un novato que ejecuta a otro jugador pierde su protección
	if killerPlayer and isNovice(killerPlayer) then
		loseNoviceProtection(killerPlayer)
	end

	-- Protected Final Death: una diferencia abrumadora no te deja en 0 (como mucho en ProtectedFloor)
	if killerPlayer and tier >= Tuning.ProtectedFinalDeathTier and isProtectedFromWipe(victim, killerPlayer) then
		local current = victim:GetAttribute("LifeForce")
		if typeof(current) == "number" and current - loss < Tuning.ProtectedFloor then
			loss = math.max(0, current - Tuning.ProtectedFloor)
			kind ..= ":protected"
		end
	end

	local ok, why, value = adjust(victim, -loss, "Death:" .. kind, true)
	print(string.format("[LifeForce] DEATH %s -%s (%s, %s) -> %s %s", victim.Name, tostring(loss), kind, tostring(cause), tostring(value), why))

	-- Ejecutar a un novato no da recompensa
	if killerPlayer and not victimNovice and isFairKill(killerPlayer, victim) then
		local rewarded, rewardWhy, rewardValue = adjust(killerPlayer, Tuning.FairPvPReward, "FairPvP", false)
		if rewarded then
			print(string.format("[LifeForce] FAIR PVP %s +%d -> %s", killerPlayer.Name, Tuning.FairPvPReward, tostring(rewardValue)))
		elseif rewardWhy ~= "LifeNotAlive" then
			warn("[LifeForce] Recompensa PvP no aplicada a " .. killerPlayer.Name .. ": " .. rewardWhy)
		end
	end

	if ok and typeof(value) == "number" and value <= 0 then
		task.delay(Tuning.DepletedDelay, function()
			if victim.Parent then
				sendToAfterlife(victim, "LifeForceDepleted")
			end
		end)
	end
end

-- Al entrar: publica el valor. Una vida viva con 0 solo puede venir de revivir en el Afterlife
-- con una versión que no tocara la fuerza vital: se deja en el máximo.
local function loadPlayer(player: Player)
	local deadline = os.clock() + 60
	while player.Parent and os.clock() < deadline do
		if AccountProfileService.IsReady(player) and slotIdOf(player) then
			break
		end
		task.wait(0.5)
	end
	if not player.Parent then
		return
	end
	local slotId = slotIdOf(player)
	if not slotId then
		warn("[LifeForce] Sin slot para " .. player.Name)
		return
	end
	local value = AccountProfileService.GetLifeForce(player, slotId)
	if typeof(value) == "number" and value <= 0 then
		local ok, _, restored = adjust(player, Tuning.MaxLifeForce, "RevivedRecovery", true)
		if ok then
			value = restored
		end
	end
	publish(player, value)

	-- Protección de novato: estado guardado y se recalcula al subir de nivel o de rango
	local novice = AccountProfileService.GetNoviceState(player, slotId)
	noviceLost[player] = novice ~= nil and novice.Lost == true
	noviceSaveAt[player] = if novice and typeof(novice.SaveAt) == "number" then novice.SaveAt else nil
	refreshNovice(player)
	player:GetAttributeChangedSignal("CharacterLevel"):Connect(function()
		refreshNovice(player)
	end)
	player:GetAttributeChangedSignal("NinjaRankOrder"):Connect(function()
		refreshNovice(player)
	end)

	print("[LifeForce] LOADED", player.Name, "Slot=" .. slotId, "LifeForce=" .. tostring(value), "Novice=" .. tostring(isNovice(player)))
end

-- Enlaces internos ---------------------------------------------------------------------------

local combatInternal = ServerStorage:WaitForChild("CombatInternal", 10)
if not combatInternal then
	combatInternal = Instance.new("Folder")
	combatInternal.Name = "CombatInternal"
	combatInternal.Parent = ServerStorage
end
local finalDeath = (combatInternal :: Instance):FindFirstChild("FinalDeath")
if not finalDeath then
	finalDeath = Instance.new("BindableEvent")
	finalDeath.Name = "FinalDeath"
	finalDeath.Parent = combatInternal
end
(finalDeath :: BindableEvent).Event:Connect(function(victim: Player, killer: any, cause: string?)
	local ok, err = pcall(onFinalDeath, victim, killer, cause)
	if not ok then
		warn("[LifeForce] FinalDeath: " .. tostring(err))
	end
end)

-- Para otros sistemas (misiones, NPC, objetos, administración): Adjust(jugador, delta, motivo)
local internal = ServerStorage:FindFirstChild("LifeForceInternal") or Instance.new("Folder")
internal.Name = "LifeForceInternal"
internal.Parent = ServerStorage
local adjustFunction = internal:FindFirstChild("Adjust") or Instance.new("BindableFunction")
adjustFunction.Name = "Adjust"
adjustFunction.Parent = internal
;(adjustFunction :: BindableFunction).OnInvoke = function(player: Player, delta: number, reason: string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(delta) ~= "number" then
		return false, "InvalidArguments", nil
	end
	local ok, why, value = adjust(player, delta, reason or "External", false)
	if ok and typeof(value) == "number" and value <= 0 then
		task.delay(Tuning.DepletedDelay, function()
			if player.Parent then
				sendToAfterlife(player, "LifeForceDepleted:" .. tostring(reason or "External"))
			end
		end)
	end
	return ok, why, value
end

-- Pérdida por desconectarse en combate (la aplica CombatLogPenaltyServer al salir)
local combatLogLoss = internal:FindFirstChild("CombatLogLoss") or Instance.new("NumberValue")
combatLogLoss.Name = "CombatLogLoss"
;(combatLogLoss :: NumberValue).Value = Tuning.CombatLogLoss
combatLogLoss.Parent = internal

-- DownedServer: ¿se salva este novato de la ejecución? -> CFrame donde reaparecer, o nil
local noviceSaveFunction = internal:FindFirstChild("TryNoviceSave") or Instance.new("BindableFunction")
noviceSaveFunction.Name = "TryNoviceSave"
noviceSaveFunction.Parent = internal
;(noviceSaveFunction :: BindableFunction).OnInvoke = function(victim: Player, attacker: Player?)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return nil
	end
	local ok, result = pcall(tryNoviceSave, victim, attacker)
	return if ok then result else nil
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayer, player)
end)
Players.PlayerRemoving:Connect(function(player)
	noviceLost[player] = nil
	noviceSaveAt[player] = nil
end)
for _, player in Players:GetPlayers() do
	task.spawn(loadPlayer, player)
end

print("[LifeForceServer] READY v1 | PvP=20/10/5 PvE=5 CombatLog=20 FairPvP=+3 | 0 -> Afterlife (no wipe)")
