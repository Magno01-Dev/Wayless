-- ServerScriptService > JutsuSystem > TechniqueKit > Kenjutsu  (ModuleScript)
--
-- Base común de las técnicas de kenjutsu. Se apoya en TechniqueKit > Taijutsu (mismos golpes
-- por CombatServer, misma construcción) y agrega:
--   - Requisito: tener un arma equipada (EquippedWeaponId). Si está enfundada, la técnica la
--     desenvaina sola.
--   - Daño escalado por el arma: daño de la técnica × (Combat.Damage del arma / 8). La katana
--     QA (Medium, daño 8) es la referencia 1.0.
--   - Los golpes son SourceType "Kenjutsu" (cuentan para la postura de contraataque y para
--     Chakura Nagashi).
--   - Efectos visuales: remote ReplicatedStorage > JutsuSystem > Remotes > KenjutsuFX
--     (StarterPlayerScripts > KenjutsuClient).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Taijutsu = require(script.Parent:WaitForChild("Taijutsu"))
local WeaponCatalog = require(ReplicatedStorage:WaitForChild("WeaponCatalog"))
local EquipmentVisualService = require(ServerScriptService:WaitForChild("EquipmentVisualService"))

local Kenjutsu = {}

Kenjutsu.BaselineWeaponDamage = 8 -- KatanaQA (Medium)

-- Remote -------------------------------------------------------------------------------------

local REMOTE_NAME = "KenjutsuFX"
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

function Kenjutsu.fxAll(action: string, data: {[string]: any})
	getRemote():FireAllClients(action, data)
end

-- Arma ---------------------------------------------------------------------------------------

function Kenjutsu.weapon(character: Model): any?
	local weaponId = character:GetAttribute("EquippedWeaponId")
	if typeof(weaponId) ~= "string" or weaponId == "" then
		return nil
	end
	return WeaponCatalog.Get(weaponId)
end

function Kenjutsu.damageScale(character: Model): number
	local definition = Kenjutsu.weapon(character)
	local damage = definition and definition.Combat and definition.Combat.Damage
	if typeof(damage) ~= "number" or damage <= 0 then
		return 1
	end
	return damage / Kenjutsu.BaselineWeaponDamage
end

-- Desenvaina si hace falta (Iai es literalmente un corte de desenvaine)
function Kenjutsu.draw(character: Model): boolean
	if character:GetAttribute("WeaponState") == "Drawn" then
		return false
	end
	local ok, success = pcall(EquipmentVisualService.SetWeaponState, character, "Drawn")
	return ok and success == true
end

-- Golpe ------------------------------------------------------------------------------------

--[[
	Igual que Taijutsu.hit, pero con SourceType "Kenjutsu" y el daño escalado por el arma.
	No modifica la tabla spec original.
]]
function Kenjutsu.hit(attacker: Player, targetCharacter: Model, spec: {[string]: any}): string
	local scaled = table.clone(spec)
	scaled.SourceType = "Kenjutsu"
	local character = attacker.Character
	if character and typeof(scaled.Damage) == "number" then
		scaled.Damage = scaled.Damage * Kenjutsu.damageScale(character)
	end
	return Taijutsu.hit(attacker, targetCharacter, scaled)
end

Kenjutsu.targetsAround = Taijutsu.targetsAround
Kenjutsu.flat = Taijutsu.flat
Kenjutsu.stun = Taijutsu.stun

-- Construcción ------------------------------------------------------------------------------

--[[
	Kenjutsu.build(module, execute)
	Como Taijutsu.build, más: sin arma equipada el jutsu ni empieza (no gasta nada), y al salir
	la técnica el arma se desenvaina.
]]
function Kenjutsu.build(module: any, execute: (any, Vector3) -> ()): any
	module.TechniqueCategory = module.TechniqueCategory or "Kenjutsu"

	Taijutsu.build(module, function(context, forward)
		Kenjutsu.draw(context.Character)
		execute(context, forward)
	end)

	local baseSanitize = module.SanitizeRequest
	function module.SanitizeRequest(character: Model, payload: any): (boolean, string, any?)
		if not Kenjutsu.weapon(character) then
			return false, "NoWeaponEquipped", nil
		end
		if module.Precheck then
			local ok, reason = module.Precheck(character)
			if not ok then
				return false, reason, nil
			end
		end
		return baseSanitize(character, payload)
	end

	return module
end

return Kenjutsu
