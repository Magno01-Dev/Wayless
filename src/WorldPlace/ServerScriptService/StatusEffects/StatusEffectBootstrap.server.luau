--!strict
-- DiabloStudios
-- ServerScriptService > StatusEffects > StatusEffectBootstrap

local RunService = game:GetService("RunService")

print("[StatusEffectBootstrap] BOOT v1.1")
local ServerScriptService = game:GetService("ServerScriptService")

local services = ServerScriptService:WaitForChild("Services")
local StatusEffectService =
	require(services:WaitForChild("StatusEffectService"))

-- Studio-only temporary DOT damage adapter.
--
-- It is intentionally NON-LETHAL so it cannot bypass the project's Downed /
-- execution pipeline while we're still integrating status damage with the
-- centralized combat damage authority.
--
-- In production, Poison/Bleed/Burn will do no health damage until we replace
-- this with the real combat damage adapter.
if RunService:IsStudio() then
	StatusEffectService.SetDamageHandler(function(
		targetCharacter: Model,
		amount: number,
		context: {[string]: any}
	)
		local humanoid =
			targetCharacter:FindFirstChildOfClass("Humanoid")

		if not humanoid or humanoid.Health <= 1 then
			return
		end

		local before = humanoid.Health
		humanoid.Health =
			math.max(1, humanoid.Health - amount)

		print(
			"[StatusEffectDevDamage]",
			context.EffectId,
			targetCharacter.Name,
			string.format("%.2f -> %.2f", before, humanoid.Health),
			"| stacks=",
			context.Stacks
		)
	end)
end

StatusEffectService.Start()

print(
	"[StatusEffectBootstrap] READY v1.1",
	"| StudioDOT=NONLETHAL_TEST_ONLY",
	"| ProductionDOT=AWAITING_COMBAT_DAMAGE_ADAPTER"
)
