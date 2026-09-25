--!strict
-- CombatEntityService v1.0
-- ServerScriptService > CombatEntityService [ModuleScript]
--
-- Canonical target abstraction for player characters, humanoid NPCs and
-- monster/boss NPCs. Combat systems should resolve a Model once and then use
-- capabilities instead of branching on Player ~= nil.

local Players = game:GetService("Players")

local CombatEntityService = {}

export type CombatEntityKind = "Player" | "HumanoidNPC" | "MonsterNPC"

export type CombatEntity = {
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	Kind: CombatEntityKind,
	Profile: string,
	IsPlayer: boolean,
	CanReceiveDamage: boolean,
	CanStun: boolean,
	CanKnockback: boolean,
	CanLaunch: boolean,
	CanRagdoll: boolean,
}

local function readBooleanAttribute(
	character: Model,
	name: string,
	fallback: boolean
): boolean
	local value = character:GetAttribute(name)
	if typeof(value) == "boolean" then
		return value
	end
	return fallback
end

local function inferKind(character: Model, player: Player?): CombatEntityKind
	if player then
		return "Player"
	end

	local explicit = character:GetAttribute("CombatEntityType")
	if explicit == "MonsterNPC" or explicit == "Monster" or explicit == "Bijuu" then
		return "MonsterNPC"
	end

	return "HumanoidNPC"
end

local function defaultsForKind(kind: CombatEntityKind)
	if kind == "MonsterNPC" then
		return {
			CanReceiveDamage = true,
			CanStun = true,
			CanKnockback = false,
			CanLaunch = false,
			CanRagdoll = false,
		}
	end

	return {
		CanReceiveDamage = true,
		CanStun = true,
		CanKnockback = true,
		CanLaunch = true,
		CanRagdoll = true,
	}
end

function CombatEntityService.Resolve(character: Model): CombatEntity?
	if not character:IsA("Model") then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	local root: BasePart? = nil
	local explicitRootName = character:GetAttribute("CombatRootPartName")

	if typeof(explicitRootName) == "string" and explicitRootName ~= "" then
		local explicitRoot = character:FindFirstChild(explicitRootName, true)
		if explicitRoot and explicitRoot:IsA("BasePart") then
			root = explicitRoot
		end
	end

	if not root then
		local humanoidRoot = character:FindFirstChild("HumanoidRootPart", true)
		if humanoidRoot and humanoidRoot:IsA("BasePart") then
			root = humanoidRoot
		end
	end

	if not root and character.PrimaryPart then
		root = character.PrimaryPart
	end

	if not humanoid or not root then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	local kind = inferKind(character, player)
	local defaults = defaultsForKind(kind)

	local profileValue = character:GetAttribute("CombatProfile")
	local profile = if typeof(profileValue) == "string" and profileValue ~= ""
		then profileValue
		else kind

	return {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Player = player,
		Kind = kind,
		Profile = profile,
		IsPlayer = player ~= nil,
		CanReceiveDamage = readBooleanAttribute(character, "CanReceiveDamage", defaults.CanReceiveDamage),
		CanStun = readBooleanAttribute(character, "CanStun", defaults.CanStun),
		CanKnockback = readBooleanAttribute(character, "CanKnockback", defaults.CanKnockback),
		CanLaunch = readBooleanAttribute(character, "CanLaunch", defaults.CanLaunch),
		CanRagdoll = readBooleanAttribute(character, "CanRagdoll", defaults.CanRagdoll),
	}
end

function CombatEntityService.ResolveFromInstance(instance: Instance?): CombatEntity?
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") then
			local entity = CombatEntityService.Resolve(current)
			if entity then
				return entity
			end
		end
		current = current.Parent
	end
	return nil
end

function CombatEntityService.IsAlive(entity: CombatEntity): boolean
	return entity.Character.Parent ~= nil
		and entity.Humanoid:IsDescendantOf(entity.Character)
		and entity.Root:IsDescendantOf(entity.Character)
		and entity.Humanoid.Health > 0
end

function CombatEntityService.IsActionLocked(entity: CombatEntity): boolean
	local character = entity.Character
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsCarrying") == true
end

function CombatEntityService.CanReceiveLauncher(entity: CombatEntity): boolean
	if not CombatEntityService.IsAlive(entity) then
		return false
	end
	if not entity.CanReceiveDamage then
		return false
	end
	if entity.Character:GetAttribute("CombatImmune") == true
		or entity.Character:GetAttribute("IsMissionNPC") == true then
		return false
	end
	if CombatEntityService.IsActionLocked(entity) then
		return false
	end
	if entity.Character:GetAttribute("AirComboServerActive") == true then
		return false
	end
	return true
end

print(
	"[CombatEntityService] READY v1.0"
		.. " | Player=ON"
		.. " | HumanoidNPC=ON"
		.. " | MonsterNPC=ON"
		.. " | CapabilityAttributes=ON"
)

return CombatEntityService
