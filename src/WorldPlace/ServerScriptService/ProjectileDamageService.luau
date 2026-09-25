--!strict
-- ProjectileDamageService v2 - Shared DamageService Adapter
-- ServerScriptService > ProjectileDamageService [ModuleScript]
--
-- Keeps the current ProjectileServer API unchanged while moving all Armor
-- calculations into DamageService.

local DamageService = require(script.Parent:WaitForChild("DamageService"))

local ProjectileDamageService = {}

function ProjectileDamageService.Apply(
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	targetPlayer: Player?,
	sourcePlayer: Player,
	projectileConfig: any
): (any, number, number)
	local resolution = DamageService.Apply({
		TargetCharacter = targetCharacter,
		TargetHumanoid = targetHumanoid,
		TargetPlayer = targetPlayer,
		Attacker = sourcePlayer,
		Damage = math.max(0, projectileConfig.Damage or 0),
		SourceType = "Projectile",
		SourceId = projectileConfig.Id or "",
		Armor = projectileConfig.Armor,
	})

	return resolution.Result,
		resolution.FinalDamage,
		resolution.DurabilityDamage
end

print(
	"[ProjectileDamageService] READY v2"
		.. " | DamageServiceAdapter=ON"
)

return ProjectileDamageService
