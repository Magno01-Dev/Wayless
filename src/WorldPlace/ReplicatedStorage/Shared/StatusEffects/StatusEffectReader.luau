--!strict
-- DiabloStudios
-- ReplicatedStorage > Shared > StatusEffects > StatusEffectReader
--
-- Lightweight read-only API for any client/server controller.

local Reader = {}

function Reader.IsStunned(character: Model): boolean
	return character:GetAttribute("Status_Stunned") == true
end

function Reader.IsMovementBlocked(character: Model): boolean
	return character:GetAttribute("Status_MovementBlocked") == true
end

function Reader.IsAttackBlocked(character: Model): boolean
	return character:GetAttribute("Status_AttackBlocked") == true
end

function Reader.IsChakraSuppressed(character: Model): boolean
	return character:GetAttribute("Status_ChakraSuppressed") == true
end

function Reader.IsChakraChargeBlocked(character: Model): boolean
	return character:GetAttribute("Status_ChakraChargeBlocked") == true
end

function Reader.GetMoveSpeedMultiplier(character: Model): number
	local value = character:GetAttribute("Status_MoveSpeedMultiplier")
	if typeof(value) == "number" then
		return value
	end
	return 1
end

function Reader.GetChakraRegenMultiplier(character: Model): number
	local value = character:GetAttribute("Status_ChakraRegenMultiplier")
	if typeof(value) == "number" then
		return value
	end
	return 1
end

function Reader.GetDamageTakenMultiplier(character: Model): number
	local value = character:GetAttribute("Status_DamageTakenMultiplier")
	if typeof(value) == "number" then
		return value
	end
	return 1
end

function Reader.GetDamageDealtMultiplier(character: Model): number
	local value = character:GetAttribute("Status_DamageDealtMultiplier")
	if typeof(value) == "number" then
		return value
	end
	return 1
end

function Reader.Has(character: Model, effectId: string): boolean
	local folder = character:FindFirstChild("StatusEffects")
	return folder ~= nil and folder:FindFirstChild(effectId) ~= nil
end

function Reader.GetEffect(character: Model, effectId: string): Folder?
	local folder = character:FindFirstChild("StatusEffects")
	if not folder then
		return nil
	end

	local effect = folder:FindFirstChild(effectId)
	if effect and effect:IsA("Folder") then
		return effect
	end

	return nil
end

return table.freeze(Reader)
