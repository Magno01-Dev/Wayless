--[[
	ThrowableServer · Script en ServerScriptService

	El cliente lanza al instante y manda el lanzamiento; el servidor lo valida y simula la
	MISMA trayectoria (Throwables.Paths) para decidir impactos, choques y atrapadas.
	No se crea ni se mueve ningún modelo en el servidor: los clientes dibujan.

	v3: lanzables de efecto (sello explosivo, mina, hilo ninja, abrojos, humo, luz).
	v3.3: pasiva Nara (clan): sus minas y abrojos duran el doble y sus minas siempre son ocultas.
	Ver la sección "Efectos al caer".

	Integración:
		NinjaBagService      slots, munición (ConsumeSlot / GetAmount / SetAmount)
		DamageService        daño y armadura (los estados solo se aplican con impacto real al cuerpo)
		StatusEffectService  KunaiPin, SenbonNeedle, SenbonParalysis, ThrowCharging,
		                     WireBind, WireSlow, CaltropSlow (opcional)
		CoreCooldown_<Id>_*  atributos del HUD de cooldowns
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("Throwables")
local Config = require(folder:WaitForChild("Config"))
local Definitions = require(folder:WaitForChild("Definitions"))
local Paths = require(folder:WaitForChild("Paths"))
local Targets = require(folder:WaitForChild("Targets"))

local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local NinjaBagService = require(ServerScriptService:WaitForChild("NinjaBagService"))

local StatusEffectService = nil
do
	local services = ServerScriptService:WaitForChild("Services", 5)
	local module = services and services:FindFirstChild("StatusEffectService")
	if module then
		local ok, result = pcall(require, module)
		StatusEffectService = if ok then result else nil
	end
	if not StatusEffectService then
		warn("[Throwables] StatusEffectService no encontrado: los estados (KunaiPin, Senbon…) quedan desactivados")
	end
end

local function debugLog(message)
	if Config.Debug then
		print("[ThrowableServer] " .. message)
	end
end

-- Remotes -----------------------------------------------------------------------------

local remotes = folder:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = folder
end

local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

local throwEvent = getRemote("Throw") -- cliente → servidor
local counterEvent = getRemote("Counter") -- cliente → servidor
local chargeEvent = getRemote("Charge") -- cliente → servidor
local resultEvent = getRemote("Result") -- servidor → dueño
local spawnEvent = getRemote("Spawn") -- servidor → otros jugadores
local worldEvent = getRemote("World") -- servidor → todos (impactos, desvíos, choques, cargas)
local effectEvent = getRemote("Effect") -- servidor → todos (explosiones, humo, minas, abrojos, hilo…)
local detonateEvent = getRemote("Detonate") -- cliente → servidor (detonar sellos clavados)
local redirectEvent = getRemote("Redirect") -- cliente → servidor (kunai guiado: cambiar de rumbo)

-- API para el JutsuSystem (shurikenjutsu): ServerStorage > ThrowablesInternal > SpawnTechnique
local ServerStorage = game:GetService("ServerStorage")
local internalFolder = ServerStorage:FindFirstChild("ThrowablesInternal")
if not internalFolder then
	internalFolder = Instance.new("Folder")
	internalFolder.Name = "ThrowablesInternal"
	internalFolder.Parent = ServerStorage
end
local spawnTechniqueFunction = internalFolder:FindFirstChild("SpawnTechnique")
if not spawnTechniqueFunction then
	spawnTechniqueFunction = Instance.new("BindableFunction")
	spawnTechniqueFunction.Name = "SpawnTechnique"
	spawnTechniqueFunction.Parent = internalFolder
end

-- Estados (StatusEffectService) ---------------------------------------------------------

local warnedStatus = {}

local function applyStatus(character, id, options)
	if not StatusEffectService or not id then
		return
	end
	if not StatusEffectService.GetDefinition(id) then
		if not warnedStatus[id] then
			warnedStatus[id] = true
			warn("[Throwables] Falta la definición de estado '" .. id .. "' en StatusEffectDefinitions")
		end
		return
	end
	StatusEffectService.Apply(character, id, options)
end

local function removeStatus(character, id)
	if StatusEffectService and StatusEffectService.Has(character, id) then
		StatusEffectService.Remove(character, id, "Throwables")
	end
end

-- Jugadores ------------------------------------------------------------------------------

local states = {} -- [player] = { Cooldowns, GlobalLockUntil, Charge, LastThrowId }

local BLOCKING_ATTRIBUTES = {
	"CombatSuppressed", "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting", "IsCarrying",
	"IsStunned", "Status_AttackBlocked", "Status_Stunned", "IsBlocking", "IsAttacking", "IsDashing",
	"TreeJumpActive", "IsTreeJumping",
}

local function blockedReason(character)
	for _, name in BLOCKING_ATTRIBUTES do
		if character:GetAttribute(name) == true then
			return name
		end
	end
	return nil
end

local function getAlive(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil
end

local function rightHandBusy(character)
	for _, name in Config.RightHandBusyAttributes do
		if character:GetAttribute(name) == true then
			return true
		end
	end
	return character:FindFirstChildOfClass("Tool") ~= nil
end

local function oneWayLatency(player)
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and typeof(ping) == "number" then math.max(ping, 0) * 0.5 else 0
end

local function isVector(value)
	return typeof(value) == "Vector3"
		and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < 1e6 and math.abs(value.Y) < 1e6 and math.abs(value.Z) < 1e6
end

-- La mano del cliente puede ir por delante de la del servidor: tolerancia según velocidad y ping
local function originValid(player, character, root, weapon, origin)
	local explicit = character:FindFirstChild(weapon .. "ThrowOrigin", true)
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	local serverOrigin = if explicit and explicit:IsA("Attachment")
		then explicit.WorldPosition
		elseif hand then hand.Position
		else root.Position
	local velocity = root.AssemblyLinearVelocity
	local predicted = serverOrigin + velocity * math.clamp(oneWayLatency(player) + 1 / 60, 0, 0.18)
	local allowance = math.clamp(
		Config.OriginBaseTolerance + velocity.Magnitude * Config.OriginVelocityWindow,
		Config.OriginBaseTolerance,
		Config.OriginMaxTolerance
	)
	return (origin - predicted).Magnitude <= allowance + 1.5
end

local function publishCooldown(character, weapon, startsAt, endsAt)
	character:SetAttribute("CoreCooldown_" .. weapon .. "_Label", weapon)
	character:SetAttribute("CoreCooldown_" .. weapon .. "_StartsAt", startsAt)
	character:SetAttribute("CoreCooldown_" .. weapon .. "_EndsAt", endsAt)
end

local function fireOthers(remote, player, ...)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remote:FireClient(other, ...)
		end
	end
end

local function cancelCharge(player, notifyOwner)
	local state = states[player]
	if not state or not state.Charge then
		return
	end
	state.Charge = nil
	if player.Character then
		removeStatus(player.Character, Config.ChargeStatus)
	end
	fireOthers(worldEvent, player, "ChargeEnd", player)
	if notifyOwner then
		worldEvent:FireClient(player, "ChargeCancel")
	end
end

-- Historial de posiciones (compensación de latencia) ---------------------------------------

local history = setmetatable({}, { __mode = "k" }) -- [character] = { {T, P}, ... }

local function recordHistory(now, targets)
	for _, target in targets do
		local samples = history[target.Character]
		if not samples then
			samples = {}
			history[target.Character] = samples
		end
		table.insert(samples, { T = now, P = target.Root.Position })
		while #samples > 2 and now - samples[1].T > Config.HistoryLength do
			table.remove(samples, 1)
		end
	end
end

local function positionAt(target, time)
	local samples = history[target.Character]
	if not samples or #samples == 0 then
		return target.Root.Position
	end
	for i = #samples, 2, -1 do
		local newer, older = samples[i], samples[i - 1]
		if older.T <= time then
			local span = newer.T - older.T
			local alpha = if span > 1e-4 then math.clamp((time - older.T) / span, 0, 1) else 1
			return older.P:Lerp(newer.P, alpha)
		end
	end
	return samples[1].P
end

-- Proyectiles ------------------------------------------------------------------------------

local shots = {} -- [id] = proyectil
local sequence = 0

local function registerShot(player, character, definition, levelDef, path, startTime, id, origin, counter)
	sequence += 1
	local clash = definition.Clash
	shots[id] = {
		Id = id,
		ThrowKey = string.match(id, "^(.*):%d+$"), -- "<UserId>:<ThrowId>" (agrupa los disparos de un lanzamiento)
		Owner = player,
		OwnerCharacter = character,
		Definition = definition,
		LevelDef = levelDef,
		Path = path,
		StartTime = startTime,
		Origin = origin,
		Seq = sequence,
		Hits = {},
		Harmful = true,
		-- Los lanzables sin tabla Clash (humo, luz, abrojos, minas) no chocan con nada
		CanClash = clash ~= nil,
		Pierce = levelDef.Pierce == true,
		Clash = clash,
		Power = if clash then clash.Power * (levelDef.PowerMultiplier or 1) else 0,
		Weight = if clash then clash.Weight else 0,
		Radius = if clash then clash.Radius else 0,
		Stability = if clash then clash.Stability else 0,
		Impact = levelDef.Impact,
		ReturnAt = path.ReturnAt,
		Counter = counter,
		Previous = nil,
	}
end

local templateCache = {}
local function findTemplate(name)
	if templateCache[name] and templateCache[name].Parent then
		return templateCache[name]
	end
	local found = ReplicatedStorage:FindFirstChild(name, true)
	templateCache[name] = found
	return found
end

-- El sistema de sustitución busca Kunai_* cerca del cuerpo: se deja uno un instante
local function spawnSubstitutionProp(shot, position)
	local definition = shot.Definition
	if not definition.SubstitutionFolder then
		return
	end
	local template = findTemplate(definition.Asset)
	if not template then
		return
	end
	local holder = Workspace:FindFirstChild(definition.SubstitutionFolder)
	if not holder then
		holder = Instance.new("Model")
		holder.Name = definition.SubstitutionFolder
		holder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		holder.Parent = Workspace
	end
	local clone = template:Clone()
	local model = if clone:IsA("Model") then clone else Instance.new("Model")
	if model ~= clone then
		clone.Parent = model
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
	model.Name = definition.SubstitutionPrefix .. shot.Owner.Name
	model:PivotTo(CFrame.new(position))
	model.Parent = holder
	task.delay(0.35, function()
		model:Destroy()
	end)
end

local BODY_HIT = { Damaged = true, Downed = true, DamagedNPC = true }

local function applyOnHit(shot, character)
	for _, effect in shot.LevelDef.OnHit or {} do
		applyStatus(character, effect.Status, {
			Stacks = effect.Stacks,
			SourcePlayer = shot.Owner,
			SourceCharacter = shot.OwnerCharacter,
		})
		if effect.ParalyzeAt and StatusEffectService then
			local active = StatusEffectService.GetActive(character)[effect.Status]
			if active and active.Stacks >= effect.ParalyzeAt then
				StatusEffectService.Remove(character, effect.Status, "Paralyzed")
				applyStatus(character, effect.Paralysis, {
					SourcePlayer = shot.Owner,
					SourceCharacter = shot.OwnerCharacter,
				})
			end
		end
	end
end

local function applyHit(shot, target, point)
	local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
	local ok, resolution = pcall(DamageService.Apply, {
		TargetCharacter = target.Character,
		TargetHumanoid = target.Humanoid,
		TargetPlayer = targetPlayer,
		Attacker = shot.Owner,
		Damage = shot.LevelDef.Damage,
		SourceType = "Projectile",
		SourceId = shot.Definition.Id,
		Armor = shot.Definition.Armor,
	})
	if not ok then
		warn("[Throwables] DamageService.Apply falló: " .. tostring(resolution))
	end
	local result = if ok and resolution then resolution.Result else "Error"

	if BODY_HIT[result] then
		applyOnHit(shot, target.Character)
		if targetPlayer then
			cancelCharge(targetPlayer, true) -- un golpe corta la carga del objetivo
		end
	elseif result == "Substituted" then
		spawnSubstitutionProp(shot, point)
	end

	worldEvent:FireAllClients("Hit", shot.Id, point, result, shot.Pierce)
	debugLog(string.format("%s impactó a %s (%s)", shot.Id, target.Character.Name, result))
	return result
end

local function checkHit(shot, target, from, to, now)
	local radius = shot.Definition.HitRadius + Config.BodyRadius
	local rewind = math.clamp(oneWayLatency(shot.Owner) + Config.RewindExtra, 0, Config.MaxRewind)
	-- Favorece a quien lanza: vale la posición actual o la que veía su cliente
	for _, sample in { target.Root.Position, positionAt(target, now - rewind) } do
		local bottom, top = Targets.bodySegment(sample)
		local distance, point = Targets.segmentDistance(from, to, bottom, top)
		if distance <= radius then
			return point
		end
	end
	return nil
end

-- Fuma: si el dueño está donde vuelve, lo atrapa (devuelve munición y acorta el cooldown)
local function tryCatch(shot, now)
	local catch = shot.Definition.Catch
	local _, _, root = getAlive(shot.Owner)
	if not catch or not root or (root.Position - shot.Origin).Magnitude > catch.Radius then
		return
	end
	shots[shot.Id] = nil
	worldEvent:FireAllClients("Stop", shot.Id)

	local weapon = shot.Definition.Id
	if catch.Refund then
		local amount = NinjaBagService.GetAmount(shot.Owner, weapon)
		local maximum = NinjaBagService.GetMaxAmount(shot.Owner, weapon)
		local refunded = if maximum > 0 then math.min(amount + 1, maximum) else amount + 1
		NinjaBagService.SetAmount(shot.Owner, weapon, refunded)
	end
	local state = states[shot.Owner]
	local character = shot.Owner.Character
	if state and character and state.Cooldowns[weapon] and state.Cooldowns[weapon] > now then
		local endsAt = now + (state.Cooldowns[weapon] - now) * catch.CooldownMultiplier
		state.Cooldowns[weapon] = endsAt
		publishCooldown(character, weapon, now, endsAt)
	end
	debugLog(shot.Owner.Name .. " atrapó su fuma")
end

-- Efectos al caer (v3) -------------------------------------------------------------------------
--[[
	Lanzables con Levels[n].Impact. El servidor decide el efecto y lo anuncia por el remote
	Effect; los clientes lo dibujan (Throwables.Effects). Explosiones, minas, sellos clavados y
	abrojos se simulan aquí; el humo y la luz solo se anuncian (su efecto es visual, en cada cliente).
]]

local Debris = game:GetService("Debris")

local effectSequence = 0
local function newEffectId()
	effectSequence += 1
	return "fx" .. effectSequence
end

local stickyTags = {} -- [id] = sello clavado (kunai explosivo cargado)
local mines = {} -- [id] = sello-mina
local fields = {} -- [id] = abrojos

local detonateTag, detonateMine -- se definen más abajo (las explosiones se encadenan)

-- Para el gancho y la detonación basta con no estar fuera de combate (dashear o atacar no lo impide)
local INCAPACITATED = { "DownedActionLocked", "IsDowned", "IsCarried", "IsExecuting", "IsStunned", "Status_Stunned" }

local function incapacitated(character)
	for _, name in INCAPACITATED do
		if character:GetAttribute(name) == true then
			return true
		end
	end
	return false
end

-- Empujón: un LinearVelocity sí mueve a un jugador (su personaje lo controla su cliente)
local function knockback(root, velocity)
	local old = root:FindFirstChild("ThrowablesKnockback")
	if old then
		old:Destroy()
	end
	local attachment = root:FindFirstChild("ThrowablesKnockbackAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "ThrowablesKnockbackAttachment"
		attachment.Parent = root
	end
	local linear = Instance.new("LinearVelocity")
	linear.Name = "ThrowablesKnockback"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VectorVelocity = velocity
	linear.MaxForce = 1e6
	linear.Parent = root
	Debris:AddItem(linear, 0.15)
end

local function explode(owner, ownerCharacter, definition, position, shotId)
	local settings = definition.Explosion
	effectEvent:FireAllClients("Explosion", { ShotId = shotId, Position = position, Radius = settings.Radius })

	for _, target in Targets.list(nil) do
		if target.Character == ownerCharacter then
			continue -- quien lo puso no se hace daño
		end
		local bottom, top = Targets.bodySegment(target.Root.Position)
		local distance = Targets.segmentDistance(position, position, bottom, top)
		if distance > settings.Radius then
			continue
		end
		-- Las paredes cubren
		local center = target.Root.Position
		local toCenter = center - position
		local from = if toCenter.Magnitude > 0.6 then position + toCenter.Unit * 0.5 else position
		if toCenter.Magnitude > 0.6 and Targets.castWorld(from, center - from, { target.Character }) then
			continue
		end

		local falloff = 1 - (1 - settings.MinFalloff) * math.clamp(distance / settings.Radius, 0, 1)
		local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
		local ok, resolution = pcall(DamageService.Apply, {
			TargetCharacter = target.Character,
			TargetHumanoid = target.Humanoid,
			TargetPlayer = targetPlayer,
			Attacker = owner,
			Damage = settings.Damage * falloff,
			SourceType = "Explosion",
			SourceId = definition.Id,
			Armor = settings.Armor,
		})
		if not ok then
			warn("[Throwables] DamageService.Apply falló (explosión): " .. tostring(resolution))
			continue
		end
		if resolution and BODY_HIT[resolution.Result] then
			local flat = Vector3.new(toCenter.X, 0, toCenter.Z)
			local away = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
			knockback(target.Root, away * settings.Knockback * falloff + Vector3.yAxis * settings.Lift * falloff)
			if targetPlayer then
				cancelCharge(targetPlayer, true)
			end
		end
	end

	-- Reacción en cadena: sellos y minas dentro del radio también explotan
	for id, tag in stickyTags do
		if (tag.Position - position).Magnitude <= settings.Radius then
			task.delay(Config.ExplosionChainDelay, detonateTag, id)
		end
	end
	for id, mine in mines do
		if (mine.Position - position).Magnitude <= settings.Radius then
			task.delay(Config.ExplosionChainDelay, detonateMine, id)
		end
	end
	debugLog(string.format("explosión de %s en %s", definition.Id, tostring(position)))
end

-- Sellos clavados ---------------------------------------------------------------------------

local function ownedCount(registry, owner)
	local count, oldestId, oldestAt = 0, nil, math.huge
	for id, entry in registry do
		if entry.Owner == owner then
			count += 1
			if entry.CreatedAt < oldestAt then
				oldestId, oldestAt = id, entry.CreatedAt
			end
		end
	end
	return count, oldestId
end

detonateTag = function(id)
	local tag = stickyTags[id]
	if not tag then
		return
	end
	stickyTags[id] = nil
	effectEvent:FireAllClients("TagRemove", { Id = id })
	explode(tag.Owner, tag.OwnerCharacter, tag.Definition, tag.Position, nil)
end

local function removeTag(id)
	if stickyTags[id] then
		stickyTags[id] = nil
		effectEvent:FireAllClients("TagRemove", { Id = id })
	end
end

local function createStickyTag(shot, position, direction, attachTo)
	local definition = shot.Definition
	local settings = definition.Sticky
	local now = Workspace:GetServerTimeNow()
	local count, oldestId = ownedCount(stickyTags, shot.Owner)
	if count >= settings.MaxArmed and oldestId then
		removeTag(oldestId)
	end

	local id = newEffectId()
	local tag = {
		Id = id,
		Owner = shot.Owner,
		OwnerCharacter = shot.OwnerCharacter,
		Definition = definition,
		Position = position,
		CreatedAt = now,
		FuseAt = now + (if attachTo then settings.BodyFuse else settings.WorldFuse),
	}
	local offset = nil
	if attachTo then
		local root = attachTo:FindFirstChild("HumanoidRootPart")
		offset = root.CFrame:ToObjectSpace(CFrame.lookAt(position, position + direction))
		tag.AttachTo = attachTo
		tag.Root = root
		tag.Offset = offset
	end
	stickyTags[id] = tag
	effectEvent:FireAllClients("StickyTag", {
		ShotId = shot.Id,
		Id = id,
		Weapon = definition.Id,
		OwnerUserId = shot.Owner.UserId,
		Position = position,
		Direction = direction,
		AttachTo = attachTo,
		Offset = offset,
		FuseAt = tag.FuseAt,
	})
end

-- Minas ---------------------------------------------------------------------------------------

detonateMine = function(id)
	local mine = mines[id]
	if not mine then
		return
	end
	mines[id] = nil
	effectEvent:FireAllClients("MineRemove", { Id = id })
	explode(mine.Owner, mine.OwnerCharacter, mine.Definition, mine.Position + mine.Normal * 0.5, nil)
end

local function removeMine(id)
	if mines[id] then
		mines[id] = nil
		effectEvent:FireAllClients("MineRemove", { Id = id })
	end
end

-- Pasiva Nara (PLANEACION_CLANES): sus trampas duran el doble y sus minas siempre son ocultas
local function isNara(player)
	return player and player:GetAttribute("ClanId") == "Nara"
end

local function createMine(shot, position, normal)
	local definition = shot.Definition
	local settings = definition.Mine
	local impact = shot.Impact
	local now = Workspace:GetServerTimeNow()
	local nara = isNara(shot.Owner)
	local lifetime = settings.Lifetime * (if nara then 2 else 1)
	local hidden = impact.Hidden == true or nara
	local count, oldestId = ownedCount(mines, shot.Owner)
	if count >= settings.MaxArmed and oldestId then
		removeMine(oldestId)
	end
	local id = newEffectId()
	mines[id] = {
		Id = id,
		Owner = shot.Owner,
		OwnerCharacter = shot.OwnerCharacter,
		Definition = definition,
		Position = position,
		Normal = normal,
		CreatedAt = now,
		ArmAt = now + impact.ArmTime,
		ExpiresAt = now + lifetime,
		TriggeredAt = nil,
	}
	effectEvent:FireAllClients("Mine", {
		ShotId = shot.Id,
		Id = id,
		OwnerUserId = shot.Owner.UserId,
		Position = position,
		Normal = normal,
		Hidden = hidden,
		ArmAt = now + impact.ArmTime,
	})
end

-- Abrojos -------------------------------------------------------------------------------------

local function createCaltrops(shot, position, normal)
	-- Si cae en una pared, los abrojos caen al suelo de abajo
	if not normal or normal.Y < 0.6 then
		local start = position + (if normal then normal * 0.5 else Vector3.zero)
		local ground = Targets.castWorld(start, Vector3.yAxis * -30, { shot.OwnerCharacter })
		if not ground then
			return
		end
		position, normal = ground.Position, ground.Normal
	end
	local impact = shot.Impact
	local duration = impact.Duration * (if isNara(shot.Owner) then 2 else 1)
	local id = newEffectId()
	fields[id] = {
		Id = id,
		Owner = shot.Owner,
		OwnerCharacter = shot.OwnerCharacter,
		Definition = shot.Definition,
		Position = position,
		Normal = normal,
		Radius = impact.Radius,
		ExpiresAt = Workspace:GetServerTimeNow() + duration,
		LastHit = {},
	}
	effectEvent:FireAllClients("Caltrops", {
		ShotId = shot.Id,
		Id = id,
		Position = position,
		Normal = normal,
		Radius = impact.Radius,
		Duration = duration,
		Count = impact.Count,
		Seed = effectSequence,
	})
end

-- Hilo ninja ----------------------------------------------------------------------------------

local function anchorWire(shot, position, direction)
	local character, _, root = getAlive(shot.Owner)
	if not root or character ~= shot.OwnerCharacter or incapacitated(character) then
		return
	end
	local distance = (position - root.Position).Magnitude
	if distance > shot.Definition.Range + 15 then
		return
	end
	local impact = shot.Impact
	effectEvent:FireAllClients("Anchor", {
		ShotId = shot.Id,
		OwnerUserId = shot.Owner.UserId,
		Position = position,
		Direction = direction,
		PullSpeed = impact.PullSpeed,
		Duration = math.min(distance / impact.PullSpeed + 0.15, impact.MaxPullTime),
	})
end

local boundThisThrow = {} -- [throwKey] = { [personaje] = true } (OncePerThrow)

local function bindTarget(shot, target)
	local impact = shot.Impact
	if impact.OncePerThrow and shot.ThrowKey then
		local key = shot.ThrowKey
		local bound = boundThisThrow[key]
		if not bound then
			bound = {}
			boundThisThrow[key] = bound
			task.delay(5, function()
				boundThisThrow[key] = nil
			end)
		end
		if bound[target.Character] then
			return
		end
		bound[target.Character] = true
	end
	local options = { SourcePlayer = shot.Owner, SourceCharacter = shot.OwnerCharacter }
	applyStatus(target.Character, impact.RootStatus, options)
	applyStatus(target.Character, impact.SlowStatus, options)
	effectEvent:FireAllClients("Bind", {
		ShotId = shot.Id,
		OwnerUserId = shot.Owner.UserId,
		Target = target.Character,
		Duration = impact.TetherTime,
	})
end

-- Sello de supresión (v3.1) -----------------------------------------------------------------

local sealZones = {} -- [id] = zona sellada

local function suppressTarget(shot, target)
	local impact = shot.Impact
	applyStatus(target.Character, impact.Status, {
		Duration = impact.Duration,
		SourcePlayer = shot.Owner,
		SourceCharacter = shot.OwnerCharacter,
	})
	local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
	if targetPlayer then
		cancelCharge(targetPlayer, true) -- también corta la carga de un lanzable
	end
	effectEvent:FireAllClients("SealMark", {
		ShotId = shot.Id,
		Target = target.Character,
		Duration = impact.Duration,
	})
end

local function createSealZone(shot, position, normal)
	if not normal or normal.Y < 0.6 then
		local start = position + (if normal then normal * 0.5 else Vector3.zero)
		local ground = Targets.castWorld(start, Vector3.yAxis * -30, { shot.OwnerCharacter })
		if not ground then
			return
		end
		position, normal = ground.Position, ground.Normal
	end
	local impact = shot.Impact
	local id = newEffectId()
	sealZones[id] = {
		Id = id,
		Owner = shot.Owner,
		OwnerCharacter = shot.OwnerCharacter,
		Position = position,
		Normal = normal,
		Radius = impact.Radius,
		Status = impact.Status,
		ExpiresAt = Workspace:GetServerTimeNow() + impact.Duration,
	}
	effectEvent:FireAllClients("SealZone", {
		ShotId = shot.Id,
		Id = id,
		Position = position,
		Normal = normal,
		Radius = impact.Radius,
		Duration = impact.Duration,
	})
end

-- Sello rastreador (v3.1) -------------------------------------------------------------------

local marks = {} -- [id] = { Owner, Target (personaje), TargetPlayer, EndsAt }

local function endMark(id)
	local mark = marks[id]
	if not mark then
		return
	end
	marks[id] = nil
	if mark.Owner.Parent then
		effectEvent:FireClient(mark.Owner, "MarkEnd", { Id = id })
	end
	if mark.TargetPlayer and mark.TargetPlayer.Parent then
		effectEvent:FireClient(mark.TargetPlayer, "MarkedEnd", { Id = id })
	end
end

local function markTarget(shot, target)
	local now = Workspace:GetServerTimeNow()
	-- Volver a marcar al mismo objetivo solo renueva la marca
	for id, mark in marks do
		if mark.Owner == shot.Owner and mark.Target == target.Character then
			endMark(id)
		end
	end
	local count, oldestId = ownedCount(marks, shot.Owner)
	if count >= shot.Definition.Mark.MaxMarks and oldestId then
		endMark(oldestId)
	end

	local id = newEffectId()
	local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
	local endsAt = now + shot.Impact.Duration
	marks[id] = {
		Id = id,
		Owner = shot.Owner,
		Target = target.Character,
		TargetPlayer = targetPlayer,
		CreatedAt = now,
		EndsAt = endsAt,
	}
	-- Solo quien lanzó ve al marcado; el marcado solo sabe que lo marcaron
	effectEvent:FireClient(shot.Owner, "Mark", { Id = id, Target = target.Character, EndsAt = endsAt })
	if targetPlayer then
		effectEvent:FireClient(targetPlayer, "Marked", { Id = id, EndsAt = endsAt })
	end
end

-- Bomba de veneno (v3.1) --------------------------------------------------------------------

local poisonClouds = {} -- [id] = nube
local poisoned = {} -- [personaje] = { Owner, Definition, TickDamage, EndsAt, NextTick, Target }

local function createPoison(shot, position)
	local impact = shot.Impact
	local id = newEffectId()
	poisonClouds[id] = {
		Id = id,
		Owner = shot.Owner,
		OwnerCharacter = shot.OwnerCharacter,
		Definition = shot.Definition,
		Position = position,
		Radius = impact.Radius,
		TickDamage = impact.TickDamage,
		ExpiresAt = Workspace:GetServerTimeNow() + impact.Duration,
	}
	effectEvent:FireAllClients("Poison", {
		ShotId = shot.Id,
		Id = id,
		Position = position,
		Radius = impact.Radius,
		Duration = impact.Duration,
	})
end

--[[
	Activa el efecto de un proyectil.
	how = "World" | "Body" | "End" | "Clash" | "Fuse"
	target / result solo con "Body".
]]
local function triggerImpact(shot, position, normal, direction, how, target, result)
	local impact = shot.Impact
	local kind = impact.Kind
	local definition = shot.Definition
	direction = if direction and direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, 0, -1)
	normal = normal or -direction

	if kind == "Explode" then
		explode(shot.Owner, shot.OwnerCharacter, definition, position, shot.Id)
	elseif kind == "StickyTag" then
		if how == "World" then
			createStickyTag(shot, position, direction, nil)
		elseif how == "Body" and BODY_HIT[result] and target.Root.Parent then
			createStickyTag(shot, position, direction, target.Character)
		elseif how == "Body" then
			createStickyTag(shot, position, direction, nil) -- sustitución: el sello queda en el tronco/suelo
		else
			explode(shot.Owner, shot.OwnerCharacter, definition, position, shot.Id) -- choque en el aire
		end
	elseif kind == "Mine" then
		if how == "World" then
			createMine(shot, position, normal)
		elseif how == "Body" then
			explode(shot.Owner, shot.OwnerCharacter, definition, position, shot.Id)
		end
	elseif kind == "Anchor" then
		if how == "World" then
			anchorWire(shot, position, direction)
		end
	elseif kind == "Bind" then
		if how == "Body" and BODY_HIT[result] then
			bindTarget(shot, target)
		end
	elseif kind == "Caltrops" then
		createCaltrops(shot, position, if how == "World" then normal else nil)
	elseif kind == "Smoke" then
		effectEvent:FireAllClients("Smoke", {
			ShotId = shot.Id,
			Id = newEffectId(),
			Position = position,
			Radius = impact.Radius,
			Duration = impact.Duration,
		})
	elseif kind == "Suppress" then
		if how == "Body" and BODY_HIT[result] then
			suppressTarget(shot, target)
		end
	elseif kind == "SealZone" then
		createSealZone(shot, position, if how == "World" then normal else nil)
	elseif kind == "Mark" then
		if how == "Body" and BODY_HIT[result] then
			markTarget(shot, target)
		end
	elseif kind == "Poison" then
		createPoison(shot, position)
	elseif kind == "Flash" then
		effectEvent:FireAllClients("Flash", {
			ShotId = shot.Id,
			Position = position,
			Radius = impact.Radius,
			Duration = impact.Duration,
			OwnerUserId = shot.Owner.UserId,
			ConeAngle = definition.Flash and definition.Flash.ConeAngle or 70,
		})
	end
	debugLog(string.format("%s efecto %s (%s)", shot.Id, kind, how))
end

-- Simulación de sellos, minas y abrojos (cada frame del servidor)
local fieldAccumulator = 0

local function stepEffects(now, targets, dt)
	for id, tag in stickyTags do
		if tag.AttachTo then
			local humanoid = tag.AttachTo:FindFirstChildOfClass("Humanoid")
			if tag.Root.Parent and humanoid and humanoid.Health > 0 then
				tag.Position = (tag.Root.CFrame * tag.Offset).Position
			else
				detonateTag(id)
				continue
			end
		end
		if now >= tag.FuseAt then
			detonateTag(id)
		end
	end

	for id, mine in mines do
		if now >= mine.ExpiresAt then
			removeMine(id)
			continue
		end
		if mine.TriggeredAt or now < mine.ArmAt then
			continue
		end
		local trigger = mine.Definition.Mine.TriggerRadius
		local eye = mine.Position + mine.Normal * 0.4
		for _, target in targets do
			if target.Character == mine.OwnerCharacter then
				continue
			end
			local bottom, top = Targets.bodySegment(target.Root.Position)
			if Targets.segmentDistance(mine.Position, mine.Position, bottom, top) > trigger then
				continue
			end
			if Targets.castWorld(eye, target.Root.Position - eye, { target.Character }) then
				continue
			end
			mine.TriggeredAt = now
			effectEvent:FireAllClients("MineTrigger", { Id = id })
			task.delay(mine.Definition.Mine.FuseDelay, detonateMine, id)
			break
		end
	end

	-- Marcas: terminan con el tiempo o si el marcado muere / reaparece
	for id, mark in marks do
		local humanoid = mark.Target:FindFirstChildOfClass("Humanoid")
		if now >= mark.EndsAt or not mark.Target.Parent or not humanoid or humanoid.Health <= 0 then
			endMark(id)
		end
	end

	-- Veneno: daño cada TickInterval mientras dure (dentro de la nube y un rato después)
	for character, poison in poisoned do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if now >= poison.EndsAt or not character.Parent or not humanoid or humanoid.Health <= 0 then
			poisoned[character] = nil
			continue
		end
		if now < poison.NextTick then
			continue
		end
		poison.NextTick = now + poison.Definition.Poison.TickInterval
		pcall(DamageService.Apply, {
			TargetCharacter = character,
			TargetHumanoid = humanoid,
			TargetPlayer = Players:GetPlayerFromCharacter(character),
			Attacker = if poison.Owner.Parent then poison.Owner else nil,
			Damage = poison.TickDamage,
			SourceType = "Poison",
			SourceId = poison.Definition.Id,
			IgnoreArmor = true, -- la armadura no detiene el veneno
		})
	end

	fieldAccumulator += dt
	if fieldAccumulator < 0.1 then
		return
	end
	fieldAccumulator = 0

	-- Zonas selladas: quien está dentro no puede hacer jutsus ni cargar chakra
	for id, zone in sealZones do
		if now >= zone.ExpiresAt then
			sealZones[id] = nil
			continue
		end
		for _, target in targets do
			if target.Character == zone.OwnerCharacter then
				continue
			end
			local relative = target.Root.Position - zone.Position
			local height = relative:Dot(zone.Normal)
			local flat = (relative - zone.Normal * height).Magnitude
			if flat <= zone.Radius and height >= -2 and height <= 8 then
				-- Duración corta que se renueva: al salir de la zona se libera enseguida
				applyStatus(target.Character, zone.Status, { Duration = 0.4 })
			end
		end
	end

	-- Nubes de veneno: entrar o seguir dentro renueva el veneno
	for id, cloud in poisonClouds do
		if now >= cloud.ExpiresAt then
			poisonClouds[id] = nil
			continue
		end
		local settings = cloud.Definition.Poison
		for _, target in targets do
			if target.Character == cloud.OwnerCharacter then
				continue
			end
			local relative = target.Root.Position - cloud.Position
			-- La nube es más ancha que alta
			if Vector3.new(relative.X, relative.Y * 1.6, relative.Z).Magnitude > cloud.Radius then
				continue
			end
			local current = poisoned[target.Character]
			if current then
				current.EndsAt = now + settings.Linger
				current.TickDamage = math.max(current.TickDamage, cloud.TickDamage)
				current.Owner = cloud.Owner
			else
				poisoned[target.Character] = {
					Owner = cloud.Owner,
					Definition = cloud.Definition,
					TickDamage = cloud.TickDamage,
					EndsAt = now + settings.Linger,
					NextTick = now,
				}
			end
			applyStatus(target.Character, settings.Status, {
				Duration = settings.Linger,
				SourcePlayer = cloud.Owner,
				SourceCharacter = cloud.OwnerCharacter,
			})
		end
	end
	for id, field in fields do
		if now >= field.ExpiresAt then
			fields[id] = nil
			continue
		end
		local settings = field.Definition.Field
		for _, target in targets do
			if target.Character == field.OwnerCharacter then
				continue
			end
			local last = field.LastHit[target.Character]
			if last and now - last < settings.HitInterval then
				continue
			end
			-- Pisando: dentro del círculo y con los pies en el suelo (saltando no cuenta)
			local relative = target.Root.Position - field.Position
			local height = relative:Dot(field.Normal)
			local flat = (relative - field.Normal * height).Magnitude
			if flat > field.Radius or height < 0 or height > settings.Height then
				continue
			end
			field.LastHit[target.Character] = now
			local ok, resolution = pcall(DamageService.Apply, {
				TargetCharacter = target.Character,
				TargetHumanoid = target.Humanoid,
				TargetPlayer = Players:GetPlayerFromCharacter(target.Character),
				Attacker = field.Owner,
				Damage = settings.Damage,
				SourceType = "Trap",
				SourceId = field.Definition.Id,
			})
			if ok and resolution and BODY_HIT[resolution.Result] then
				applyStatus(target.Character, settings.SlowStatus, {
					SourcePlayer = field.Owner,
					SourceCharacter = field.OwnerCharacter,
				})
			end
		end
	end
end

local lastDetonate = {}
detonateEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastDetonate[player] and now - lastDetonate[player] < 0.25 then
		return
	end
	lastDetonate[player] = now
	local character = getAlive(player)
	if not character or incapacitated(character) then
		return
	end
	for id, tag in stickyTags do
		if tag.Owner == player then
			detonateTag(id)
		end
	end
end)

-- Shurikenjutsu (v3.2) ------------------------------------------------------------------------
--[[
	Los jutsus de shurikenjutsu lanzan sus proyectiles por aquí:
		SpawnTechnique:Invoke(player, weaponId, origin, target) → true / false
	weaponId es una definición con Technique = true (Tech_KageShuriken, …).
	El jutsu ya validó y gastó la munición y el chakra. Los ThrowId de estos lanzamientos son
	negativos para no chocar con los que numera cada cliente.
]]

local techniqueThrowId = 0

spawnTechniqueFunction.OnInvoke = function(player, weaponId, origin, target)
	local character = getAlive(player)
	local definition = Definitions[weaponId]
	if not character or typeof(definition) ~= "table" or not definition.Technique
		or not isVector(origin) or not isVector(target) then
		return false
	end
	local levelDef = definition.Levels[0]
	techniqueThrowId -= 1
	local throwId = techniqueThrowId
	local now = Workspace:GetServerTimeNow()
	local side = if math.random() < 0.5 then -1 else 1
	local seed = math.random(1, 1000000)

	local built = Paths.buildShots(definition, 0, {
		Origin = origin,
		Target = target,
		Side = side,
		OneHand = false,
		Seed = seed,
	})
	local key = tostring(player.UserId) .. ":" .. tostring(throwId)
	for _, path in built do
		registerShot(player, character, definition, levelDef, path, now, key .. ":" .. path.Index, origin, nil)
	end

	-- Todos los clientes lo dibujan, también el dueño (no lo predijo)
	spawnEvent:FireAllClients({
		OwnerUserId = player.UserId,
		ThrowId = throwId,
		Kind = "Throw",
		Weapon = weaponId,
		Level = 0,
		Origin = origin,
		Target = target,
		Side = side,
		OneHand = false,
		Seed = seed,
		StartTime = now,
		ServerSpawned = true,
	})

	if definition.Telegraph and levelDef.Rain then
		local ground = Targets.castWorld(target + Vector3.yAxis * 3, Vector3.yAxis * -40, { character })
		effectEvent:FireAllClients("Telegraph", {
			Position = if ground then ground.Position else target,
			Normal = if ground then ground.Normal else Vector3.yAxis,
			Radius = levelDef.Rain.Radius + 1,
			Duration = levelDef.Rain.FallDelay + levelDef.Rain.DropHeight / levelDef.Rain.FallSpeed,
		})
	end
	debugLog(string.format("%s técnica %s (%d proyectiles)", player.Name, weaponId, #built))
	return true
end

-- Kunai guiado: el dueño lo redirige una vez hacia un nuevo punto
redirectEvent.OnServerEvent:Connect(function(player, shotId, target)
	local shot = typeof(shotId) == "string" and shots[shotId] or nil
	if not shot or shot.Owner ~= player or shot.Redirected or not shot.Harmful or not isVector(target) then
		return
	end
	local redirect = shot.LevelDef.Redirect
	local _, _, root = getAlive(player)
	if not redirect or not root or (target - root.Position).Magnitude > redirect.MaxDistance then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local position = Paths.evaluate(shot.Path, now - shot.StartTime)
	if not position then
		return
	end
	local direction = target - position
	if direction.Magnitude < 1 then
		return
	end
	local velocity = direction.Unit * redirect.Speed
	shot.Redirected = true
	shot.Path.Override = { Time = now - shot.StartTime, Segment = Paths.makeDeflect(position, velocity, false) }
	shot.Previous = position
	shot.StepFrom, shot.StepTo = position, position
	shot.Velocity = velocity
	worldEvent:FireAllClients("Deflect", shot.Id, now, position, velocity, false)
	debugLog(player.Name .. " redirigió " .. shot.Id)
end)

-- Choques (reglas del ProjectileInteractionService anterior) ----------------------------------

local function rotate(direction, axis, degrees)
	return CFrame.fromAxisAngle(axis, math.rad(degrees)):VectorToWorldSpace(direction)
end

local function deflectionAxis(a, b)
	local axis = a:Cross(b)
	if axis.Magnitude > 0.05 then
		return axis.Unit
	end
	axis = a:Cross(Vector3.yAxis)
	if axis.Magnitude <= 0.05 then
		axis = a:Cross(Vector3.xAxis)
	end
	return axis.Unit
end

local function deflect(shot, direction, harmless, now, point)
	local speed = shot.Velocity.Magnitude
	local velocity = direction.Unit * (if harmless then speed * 0.55 else speed)
	shot.Path.Override = {
		Time = now - shot.StartTime,
		Segment = Paths.makeDeflect(point, velocity, harmless),
	}
	shot.Previous = point
	shot.StepFrom, shot.StepTo = point, point
	shot.Velocity = velocity
	shot.ReturnAt = nil
	if harmless then
		shot.Harmful = false
		shot.CanClash = false
	end
	worldEvent:FireAllClients("Deflect", shot.Id, now, point, velocity, harmless)
end

local function unitVelocity(shot)
	local velocity = shot.Velocity or Vector3.new(0, 0, -1)
	return if velocity.Magnitude > 1e-3 then velocity.Unit else Vector3.new(0, 0, -1)
end

local function resolveClash(a, b, point, now)
	if a.Counter then
		a.Counter.Done = true
	end
	if b.Counter then
		b.Counter.Done = true
	end

	local da, db = unitVelocity(a), unitVelocity(b)
	local axis = deflectionAxis(da, db)
	local sign = if a.Seq < b.Seq then 1 else -1
	local powerA, powerB = math.max(0.01, a.Power * a.Weight), math.max(0.01, b.Power * b.Weight)
	local ratio = math.max(powerA, powerB) / math.min(powerA, powerB)
	local breakRatio = math.max(1.01, math.min(a.Clash.BreakRatio, b.Clash.BreakRatio))
	local stronger = if powerA > powerB then a else b
	local weaker = if stronger == a then b else a

	if ratio < breakRatio or not stronger.Clash.CanBreak then
		-- Parejos: ambos salen desviados
		deflect(a, rotate(da, axis, a.Clash.MutualDeflect * sign), true, now, point)
		deflect(b, rotate(db, axis, -b.Clash.MutualDeflect * sign), true, now, point)
	else
		local winnerSign = if stronger.Seq < weaker.Seq then 1 else -1
		local strongDirection = if stronger == a then da else db
		local weakDirection = if stronger == a then db else da
		local dominated = math.clamp(
			weaker.Clash.MutualDeflect * 1.35 + math.clamp((ratio - breakRatio) * 12, 0, 22),
			42,
			78
		)
		deflect(weaker, rotate(weakDirection, axis, -dominated * winnerSign), true, now, point)

		stronger.Stability -= weaker.Clash.StabilityDamage
		if stronger.Stability <= 0 then
			local spent = math.clamp(stronger.Clash.MutualDeflect * 1.45, 48, 68)
			deflect(stronger, rotate(strongDirection, axis, spent * winnerSign), true, now, point)
		else
			deflect(stronger, rotate(strongDirection, axis, stronger.Clash.WinnerDeflect * winnerSign), false, now, point)
		end
	end

	worldEvent:FireAllClients("Clash", point)
	debugLog("choque " .. a.Id .. " vs " .. b.Id)

	-- Sello explosivo: si lo chocan en el aire, explota ahí
	for _, shot in { a, b } do
		if shot.Impact and shot.Impact.OnClash and shots[shot.Id] then
			shots[shot.Id] = nil
			triggerImpact(shot, point, nil, shot.Velocity, "Clash")
		end
	end
end

-- Simulación -----------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local now = Workspace:GetServerTimeNow()
	local targets = Targets.list(nil)
	recordHistory(now, targets)
	stepEffects(now, targets, dt)

	local active = {}
	for id, shot in shots do
		local t = now - shot.StartTime
		local position, velocity, finished = Paths.evaluate(shot.Path, t)
		if not position then
			continue
		end
		local previous = shot.Previous or shot.Path.Segments[1].P0
		shot.StepFrom, shot.StepTo = previous, position
		shot.Velocity = velocity
		local impact = if shot.Harmful then shot.Impact else nil

		-- Mecha: estalla en el aire a los N segundos de vuelo
		if impact and impact.Fuse and t - shot.Path.Delay >= impact.Fuse then
			shots[id] = nil
			triggerImpact(shot, position, nil, velocity, "Fuse")
			continue
		end

		local step = position - previous
		if step.Magnitude > 1e-3 then
			-- Mundo: termina (los clientes lo clavan por su cuenta) o activa su efecto
			local worldHit = Targets.castWorld(previous, step, { shot.OwnerCharacter })
			if worldHit then
				shots[id] = nil
				if Targets.consumedBy(worldHit, worldHit.Position, step.Unit) then
					-- Kagutsuchi: Black Wall: las llamas negras se lo comen (sin efecto ni daño)
				elseif impact and impact.OnWorld then
					triggerImpact(shot, worldHit.Position, worldHit.Normal, step, "World")
				end
				continue
			end

			if shot.Harmful then
				for _, target in targets do
					if target.Character == shot.OwnerCharacter or shot.Hits[target.Character] then
						continue
					end
					local point = checkHit(shot, target, previous, position, now)
					if point then
						shot.Hits[target.Character] = true
						-- Los lanzables de efecto puro (humo, luz…) no hacen daño directo
						local result = if shot.Definition.Utility then "Utility" else applyHit(shot, target, point)
						if impact and impact.OnBody then
							triggerImpact(shot, point, nil, step, "Body", target, result)
						end
						if not shot.Pierce then
							shots[id] = nil
							break
						end
					end
				end
				if not shots[id] then
					continue
				end
			end
		end

		if shot.ReturnAt and t >= shot.ReturnAt then
			shot.ReturnAt = nil
			tryCatch(shot, now)
			if not shots[id] then
				continue
			end
		end

		shot.Previous = position
		if finished then
			shots[id] = nil
			if impact and impact.OnEnd then
				triggerImpact(shot, position, nil, velocity, "End")
			end
			continue
		end
		table.insert(active, shot)
	end

	-- Choques entre proyectiles de dueños distintos
	for i = 1, #active do
		local a = active[i]
		if not a.CanClash or not shots[a.Id] then
			continue
		end
		for j = i + 1, #active do
			local b = active[j]
			if not b.CanClash or a.Owner == b.Owner or not shots[b.Id] then
				continue
			end
			local distance, point = Targets.segmentDistance(a.StepFrom, a.StepTo, b.StepFrom, b.StepTo)
			if distance <= a.Radius + b.Radius then
				resolveClash(a, b, point, now)
				break
			end
		end
	end

	-- Contraataques que llegan a su punto sin haber chocado todavía (latencia)
	for _, shot in shots do
		local counter = shot.Counter
		if counter and not counter.Done and now >= counter.Arrival then
			counter.Done = true
			local threat = shots[counter.ThreatId]
			if threat and threat.CanClash and shot.CanClash then
				local point = Paths.evaluate(threat.Path, counter.Arrival - threat.StartTime) or shot.StepTo
				shot.Velocity = shot.Velocity or (point - shot.Origin)
				threat.Velocity = threat.Velocity or Vector3.new(0, 0, -1)
				resolveClash(shot, threat, point, now)
			end
		end
	end
end)

-- Solicitudes ------------------------------------------------------------------------------

local function beginRequest(player, packet)
	local state = states[player]
	if not state or typeof(packet) ~= "table" or typeof(packet.ThrowId) ~= "number" then
		return nil
	end
	local function reject(reason)
		debugLog(player.Name .. " rechazado: " .. reason)
		resultEvent:FireClient(player, packet.ThrowId, false, reason)
		return nil
	end
	if packet.ThrowId <= state.LastThrowId then
		return reject("id repetido")
	end
	state.LastThrowId = packet.ThrowId

	if typeof(packet.Slot) ~= "number" or not isVector(packet.Origin) or typeof(packet.StartTime) ~= "number"
		or packet.StartTime ~= packet.StartTime then
		return reject("paquete inválido")
	end
	local character, _, root = getAlive(player)
	if not character then
		return reject("sin personaje")
	end
	local blocked = blockedReason(character)
	if blocked then
		return reject(blocked)
	end
	local canUse, weapon, reason = NinjaBagService.CanUseSlot(player, packet.Slot)
	if not canUse then
		return reject(tostring(reason))
	end
	local definition = Definitions[weapon]
	if typeof(definition) ~= "table" then
		return reject("sin definición para " .. tostring(weapon))
	end
	local now = Workspace:GetServerTimeNow()
	if now < state.GlobalLockUntil then
		return reject("bloqueo global")
	end
	if now < (state.Cooldowns[weapon] or 0) then
		return reject("cooldown")
	end
	if not originValid(player, character, root, weapon, packet.Origin) then
		return reject("origen")
	end
	return {
		State = state,
		Character = character,
		Root = root,
		Weapon = weapon,
		Definition = definition,
		Now = now,
		StartTime = math.clamp(packet.StartTime, now - Config.MaxStartTimeLag, now + 0.05),
		Reject = reject,
	}
end

local function consume(player, context, packet, count)
	if NinjaBagService.GetAmount(player, context.Weapon) < count then
		return false
	end
	local ok = NinjaBagService.ConsumeSlot(player, packet.Slot, count)
	if not ok then
		return false
	end
	local now, definition = context.Now, context.Definition
	context.State.Cooldowns[context.Weapon] = now + definition.Cooldown
	context.State.GlobalLockUntil = now + Config.GlobalThrowLock
	publishCooldown(context.Character, context.Weapon, now, now + definition.Cooldown)
	return true
end

throwEvent.OnServerEvent:Connect(function(player, packet)
	local context = beginRequest(player, packet)
	if not context then
		return
	end
	local definition, reject = context.Definition, context.Reject

	if typeof(packet.Level) ~= "number" or not isVector(packet.Target) or not isVector(packet.AimOrigin)
		or not isVector(packet.AimDirection) or packet.AimDirection.Magnitude < 0.5 then
		return reject("paquete inválido")
	end
	local level = math.floor(packet.Level)
	local levelDef = definition.Levels[level]
	if not levelDef then
		return reject("nivel inválido")
	end

	-- La carga debe haber durado lo suficiente
	if level > 0 then
		local charge = context.State.Charge
		if not charge or charge.Weapon ~= context.Weapon
			or context.Now - charge.StartedAt < levelDef.HoldTime - Config.ChargeTolerance then
			return reject("carga insuficiente")
		end
	end

	if levelDef.AtFeet then
		-- Al suelo bajo los pies: el destino tiene que estar pegado al personaje
		if (packet.Target - context.Root.Position).Magnitude > 14 then
			return reject("destino lejos de los pies")
		end
	else
		-- El destino debe estar cerca de la línea de apuntado (ayuda de apuntado + predicción)
		local aimDirection = packet.AimDirection.Unit
		local aimOrigin = if (packet.AimOrigin - context.Root.Position).Magnitude <= 80 then packet.AimOrigin else packet.Origin
		local toTarget = packet.Target - aimOrigin
		local along = toTarget:Dot(aimDirection)
		if along < 0 or (toTarget - aimDirection * along).Magnitude > Targets.maxAimOffset(definition, levelDef) then
			return reject("destino fuera de la línea de apuntado")
		end
	end

	local oneHand = packet.OneHand == true or rightHandBusy(context.Character)
	local side = if packet.Side == -1 then -1 else 1
	local built = Paths.buildShots(definition, level, {
		Origin = packet.Origin,
		Target = packet.Target,
		Side = side,
		OneHand = oneHand,
	})
	if not consume(player, context, packet, #built) then
		return reject("munición")
	end
	cancelCharge(player, false)

	local key = tostring(player.UserId) .. ":" .. tostring(packet.ThrowId)
	for _, path in built do
		registerShot(player, context.Character, definition, levelDef, path, context.StartTime, key .. ":" .. path.Index, packet.Origin, nil)
	end
	resultEvent:FireClient(player, packet.ThrowId, true, "OK", context.StartTime)
	fireOthers(spawnEvent, player, {
		OwnerUserId = player.UserId,
		ThrowId = packet.ThrowId,
		Kind = "Throw",
		Weapon = context.Weapon,
		Level = level,
		Origin = packet.Origin,
		Target = packet.Target,
		Side = side,
		OneHand = oneHand,
		StartTime = context.StartTime,
	})
	debugLog(string.format("%s lanzó %s nivel %d (%d proyectiles)", player.Name, context.Weapon, level, #built))
end)

counterEvent.OnServerEvent:Connect(function(player, packet)
	local context = beginRequest(player, packet)
	if not context then
		return
	end
	local definition, reject = context.Definition, context.Reject
	if definition.NoCounter or not definition.CounterSpeed then
		return reject("esta arma no contraataca")
	end
	if not isVector(packet.Intercept) or typeof(packet.Arrival) ~= "number" or typeof(packet.ThreatId) ~= "string" then
		return reject("paquete inválido")
	end

	local threat = shots[packet.ThreatId]
	if not threat or threat.Owner == player or not threat.Harmful or not threat.CanClash then
		return reject("sin amenaza")
	end
	local startTime, arrival = context.StartTime, packet.Arrival
	if arrival <= startTime or arrival < context.Now - Config.CounterMaxLateness then
		return reject("demasiado tarde")
	end
	local threatPoint = Paths.evaluate(threat.Path, arrival - threat.StartTime)
	if not threatPoint or (threatPoint - packet.Intercept).Magnitude > 4 then
		return reject("intercepción inválida")
	end
	local flightTime = arrival - startTime
	if (packet.Intercept - packet.Origin).Magnitude / flightTime > definition.CounterSpeed * 1.3 then
		return reject("demasiado rápido")
	end
	if not consume(player, context, packet, 1) then
		return reject("munición")
	end
	cancelCharge(player, false)

	local built = Paths.buildCounter(packet.Origin, packet.Intercept, flightTime)
	local key = tostring(player.UserId) .. ":" .. tostring(packet.ThrowId)
	registerShot(player, context.Character, definition, definition.Levels[0], built[1], startTime, key .. ":1", packet.Origin, {
		ThreatId = packet.ThreatId,
		Arrival = arrival,
		Done = false,
	})
	resultEvent:FireClient(player, packet.ThrowId, true, "Counter", startTime)
	fireOthers(spawnEvent, player, {
		OwnerUserId = player.UserId,
		ThrowId = packet.ThrowId,
		Kind = "Counter",
		Weapon = context.Weapon,
		Origin = packet.Origin,
		Intercept = packet.Intercept,
		Arrival = arrival,
		StartTime = startTime,
	})
	debugLog(player.Name .. " contraataca a " .. packet.ThreatId)

	-- Aviso a otros sistemas (maestría del Sharingan): ServerStorage > CombatInternal >
	-- DefensiveIntercept(jugador, UserId del dueño del proyectil, arma). Lo crea TechniqueKit > Clan.
	local combatInternal = game:GetService("ServerStorage"):FindFirstChild("CombatInternal")
	local intercepted = combatInternal and combatInternal:FindFirstChild("DefensiveIntercept")
	if intercepted and intercepted:IsA("BindableEvent")
		and typeof(threat.Owner) == "Instance" and threat.Owner:IsA("Player") then
		intercepted:Fire(player, threat.Owner.UserId, context.Weapon)
	end
end)

chargeEvent.OnServerEvent:Connect(function(player, kind, slot)
	local state = states[player]
	if not state then
		return
	end
	if kind == "Cancel" then
		cancelCharge(player, false)
		return
	end
	if kind ~= "Begin" or typeof(slot) ~= "number" then
		return
	end
	local character = getAlive(player)
	local canUse, weapon = NinjaBagService.CanUseSlot(player, slot)
	if not character or not canUse or typeof(Definitions[weapon]) ~= "table" or blockedReason(character) then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local charge = { Slot = slot, Weapon = weapon, StartedAt = now }
	state.Charge = charge
	applyStatus(character, Config.ChargeStatus, { Duration = Config.MaxChargeTime })
	fireOthers(worldEvent, player, "ChargeBegin", player, weapon, rightHandBusy(character), now)
	task.delay(Config.MaxChargeTime, function()
		if state.Charge == charge then
			cancelCharge(player, true)
		end
	end)
end)

-- Jugadores -------------------------------------------------------------------------------

local function onPlayerAdded(player)
	states[player] = { Cooldowns = {}, GlobalLockUntil = 0, Charge = nil, LastThrowId = 0 }
	player.CharacterAdded:Connect(function()
		local state = states[player]
		if state then
			state.Charge = nil
		end
	end)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
	lastDetonate[player] = nil
	for id, shot in shots do
		if shot.Owner == player then
			shots[id] = nil
		end
	end
	-- Sus sellos, minas y abrojos desaparecen con él
	for id, tag in stickyTags do
		if tag.Owner == player then
			removeTag(id)
		end
	end
	for id, mine in mines do
		if mine.Owner == player then
			removeMine(id)
		end
	end
	for id, field in fields do
		if field.Owner == player then
			fields[id] = nil
		end
	end
	for id, zone in sealZones do
		if zone.Owner == player then
			sealZones[id] = nil
		end
	end
	for id, cloud in poisonClouds do
		if cloud.Owner == player then
			poisonClouds[id] = nil
		end
	end
	for id, mark in marks do
		if mark.Owner == player or mark.TargetPlayer == player then
			endMark(id)
		end
	end
end)

print("[Throwables] Servidor listo")
