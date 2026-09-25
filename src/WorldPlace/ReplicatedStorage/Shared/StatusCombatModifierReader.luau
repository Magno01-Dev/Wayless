--!strict
-- ReplicatedStorage > Shared > StatusCombatModifierReader
-- Shared reader for status-derived combat/movement multipliers.

local Reader = {}

local function readMultiplier(
	character: Model?,
	attributeName: string
): number
	if not character then
		return 1.0
	end

	local value = character:GetAttribute(attributeName)

	if typeof(value) ~= "number"
		or value ~= value
		or value <= 0 then

		return 1.0
	end

	return math.clamp(value, 0.10, 3.00)
end

function Reader.GetKnockbackReceivedMultiplier(
	character: Model?
): number
	return readMultiplier(
		character,
		"Status_KnockbackReceivedMultiplier"
	)
end

function Reader.GetGuardPressureTakenMultiplier(
	character: Model?
): number
	return readMultiplier(
		character,
		"Status_GuardPressureTakenMultiplier"
	)
end

function Reader.GetDashDistanceMultiplier(
	character: Model?
): number
	return readMultiplier(
		character,
		"Status_DashDistanceMultiplier"
	)
end

function Reader.GetJumpMultiplier(
	character: Model?
): number
	return readMultiplier(
		character,
		"Status_JumpMultiplier"
	)
end

function Reader.GetAirControlMultiplier(
	character: Model?
): number
	return readMultiplier(
		character,
		"Status_AirControlMultiplier"
	)
end

return table.freeze(Reader)
