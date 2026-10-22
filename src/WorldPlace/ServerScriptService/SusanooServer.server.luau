--!strict
-- SusanooServer (ServerScriptService)
-- Combo del brazo del Susanoo imperfecto: mientras el personaje tiene SusanooActive, el M1 es el
-- combo de su arma (SusanooConfig.Weapons[MangekyoWeapon]: puño, espada o escudo). El cliente
-- (SusanooClient) anima al instante y pide el golpe; aquí se valida el orden y el ritmo, se avisa
-- a los demás clientes para que lo vean y, en el momento del impacto, se resuelve con
-- CombatInternal > ExternalMeleeHit (bloqueo, guardia, sustitución, Downed, combo y VFX de impacto
-- como cualquier golpe cuerpo a cuerpo). El M1 normal queda bloqueado en CombatServer y
-- AttackController mientras dura el modo.
-- Escudo: si su dueño bloquea con el Mangekyō un golpe cuerpo a cuerpo sin que le rompan la
-- guardia (CombatInternal > MeleeBlocked), devuelve un golpe que aturde y aparta al atacante
-- (Weapons.Shield.Counter, con recarga).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local susanooFolder = ReplicatedStorage:WaitForChild("Susanoo")
local Config = require(susanooFolder:WaitForChild("SusanooConfig") :: ModuleScript) :: any

local REMOTE_NAME = "SusanooRemote"
local TIMING_TOLERANCE = 0.08 -- margen para la latencia entre pulsaciones

local remote = susanooFolder:FindFirstChild(REMOTE_NAME) :: RemoteEvent?
if not remote then
	local created = Instance.new("RemoteEvent")
	created.Name = REMOTE_NAME
	created.Parent = susanooFolder
	remote = created
end
local susanooRemote = remote :: RemoteEvent

local combatInternal = ServerStorage:WaitForChild("CombatInternal")
local externalMeleeHit = combatInternal:WaitForChild("ExternalMeleeHit") :: BindableFunction
local meleeBlocked = combatInternal:WaitForChild("MeleeBlocked") :: BindableEvent

local SOURCE_IDS = {
	Fist = "SusanooArm",
	Sword = "SusanooSword",
	Shield = "SusanooShield",
}

type ComboState = {
	Weapon: string,
	Index: number,
	At: number,
	LockedUntil: number,
}

local comboStates: { [Player]: ComboState } = {}
local counterReadyAt: { [Player]: number } = {}

local BLOCKING_ATTRIBUTES = {
	"IsStunned",
	"JutsuCasting",
	"DownedActionLocked",
	"IsDowned",
	"IsCarried",
	"IsExecuting",
	"IsCarrying",
}

local function weaponNameOf(character: Model): string
	local name = character:GetAttribute("MangekyoWeapon")
	return if typeof(name) == "string" and Config.Weapons[name] then name else Config.DefaultWeapon
end

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function canAttack(character: Model): boolean
	if not isAlive(character) or character:GetAttribute("SusanooActive") ~= true then
		return false
	end
	for _, attribute in BLOCKING_ATTRIBUTES do
		if character:GetAttribute(attribute) == true then
			return false
		end
	end
	return true
end

local function characterOf(part: BasePart): Model?
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return model
end

-- Caja de golpe del paso (o la del arma), reflejada hacia el lado del brazo
local function hitboxOf(weapon: any, step: any): (CFrame, Vector3)
	local box = step.Hitbox or weapon.Hitbox
	local side = Config.Sides[Config.Side]
	local offset = box.Offset :: Vector3
	return CFrame.new(offset.X * (side.ArmSign or 1), offset.Y, offset.Z), box.Size
end

local function invokeHit(player: Player, target: Model, spec: any)
	task.spawn(function()
		local ok, result = pcall(function()
			return externalMeleeHit:Invoke(player, target, spec)
		end)
		if not ok then
			warn("[SusanooServer] ExternalMeleeHit failed:", result)
		end
	end)
end

local function resolveHit(player: Player, character: Model, weaponName: string, index: number)
	if player.Character ~= character or not canAttack(character) then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local weapon = Config.weapon(weaponName)
	local step = weapon.Combo[index]
	local offset, size = hitboxOf(weapon, step)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local parts = workspace:GetPartBoundsInBox(root.CFrame * offset, size, params)
	local spec = {
		Damage = step.Damage,
		SourceId = SOURCE_IDS[weaponName] or "SusanooArm",
		GuardDamage = step.GuardDamage,
		Hitstun = step.Hitstun,
		Knockback = step.Knockback,
		Ragdoll = step.Ragdoll,
		Heavy = step.Heavy,
		ComboNumber = math.min(index, 3),
	}
	local hit: { [Model]: boolean } = {}
	for _, part in parts do
		local target = characterOf(part)
		if target and target ~= character and not hit[target] then
			hit[target] = true
			invokeHit(player, target, spec)
		end
	end
end

susanooRemote.OnServerEvent:Connect(function(player: Player, action: any, requested: any)
	if action ~= "Attack" or typeof(requested) ~= "number" then
		return
	end
	local character = player.Character
	if not character or not canAttack(character) then
		return
	end
	local weaponName = weaponNameOf(character)
	local combo = Config.weapon(weaponName).Combo
	local index = math.floor(requested)
	local step = combo[index]
	if not step then
		return
	end

	-- Orden y ritmo: el combo empieza en 1 y avanza de uno en uno dentro de la ventana
	local now = os.clock()
	local state = comboStates[player]
	if state and state.Weapon == weaponName then
		if now < state.LockedUntil - TIMING_TOLERANCE then
			return
		end
		local expired = now - state.At > Config.ComboResetWindow + TIMING_TOLERANCE
		local expected = if expired or state.Index >= #combo then 1 else state.Index + 1
		if index ~= expected and index ~= 1 then
			return
		end
	elseif index ~= 1 then
		return
	end
	comboStates[player] = { Weapon = weaponName, Index = index, At = now, LockedUntil = now + step.NextAfter }

	for _, other in Players:GetPlayers() do
		if other ~= player then
			susanooRemote:FireClient(other, "Swing", character, index)
		end
	end

	task.delay(step.HitTime, resolveHit, player, character, weaponName, index)
end)

-- Contraataque del escudo ---------------------------------------------------------------------

meleeBlocked.Event:Connect(function(defenderPlayer: any, attackerPlayer: any)
	if typeof(defenderPlayer) ~= "Instance" or not defenderPlayer:IsA("Player")
		or typeof(attackerPlayer) ~= "Instance" or not attackerPlayer:IsA("Player")
		or defenderPlayer == attackerPlayer then
		return
	end
	local character = defenderPlayer.Character
	local attacker = attackerPlayer.Character
	if not character or not attacker or not isAlive(character) or not isAlive(attacker) then
		return
	end
	if character:GetAttribute("MangekyoActive") ~= true or weaponNameOf(character) ~= "Shield" then
		return
	end
	local counter = Config.Weapons.Shield.Counter
	local now = os.clock()
	if (counterReadyAt[defenderPlayer] or 0) > now then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
	if not root or not attackerRoot or not root:IsA("BasePart") or not attackerRoot:IsA("BasePart")
		or (attackerRoot.Position - root.Position).Magnitude > counter.Range then
		return
	end
	counterReadyAt[defenderPlayer] = now + counter.Cooldown
	susanooRemote:FireAllClients("Counter", character)
	-- fuera de la resolución del golpe bloqueado
	task.defer(invokeHit, defenderPlayer, attacker, {
		Damage = counter.Damage,
		SourceId = "SusanooShieldCounter",
		Unblockable = true,
		Hitstun = counter.Hitstun,
		Knockback = counter.Knockback,
		Heavy = true,
		ComboNumber = 3,
	})
end)

Players.PlayerRemoving:Connect(function(player: Player)
	comboStates[player] = nil
	counterReadyAt[player] = nil
end)
