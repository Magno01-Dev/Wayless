--!strict
-- ServerScriptService > WorldHandoffValidator
--
-- WAYLESS World handoff validator v2.
--
-- CharacterSlotContextService v5 consumes and validates secure World handoffs
-- BEFORE publishing the gameplay slot. This script performs the second-stage
-- LifeId check after CharacterLifeContext becomes ready.
--
-- Direct joins remain allowed for current developer QA.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local CharacterSlotContextService =
	require(Services:WaitForChild("CharacterSlotContextService"))

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

CharacterSlotContextService.Start()
CharacterLifeContextService.Start()

local function validate(player: Player)
	local secure =
		player:GetAttribute(
			"WorldHandoffValidated"
		) == true

	if not secure then
		player:SetAttribute(
			"WorldHandoffLifeValidated",
			false
		)
		return
	end

	local expectedLifeId =
		player:GetAttribute(
			"CharacterWorldExpectedLifeId"
		)

	if typeof(expectedLifeId) ~= "string"
		or expectedLifeId == "" then

		player:Kick(
			"Incomplete World character handoff."
		)
		return
	end

	local slotReady, slotId =
		CharacterSlotContextService.WaitUntilReady(
			player,
			30
		)

	local lifeReady, lifeId =
		CharacterLifeContextService.WaitUntilReady(
			player,
			30
		)

	if not slotReady
		or not lifeReady
		or lifeId ~= expectedLifeId then

		warn(
			"[WorldHandoffValidator] LIFE VALIDATION FAILED",
			player.Name,
			"Slot=" .. tostring(slotId),
			"ExpectedLife=" .. tostring(expectedLifeId),
			"ActualLife=" .. tostring(lifeId)
		)

		player:Kick(
			"Character life handoff mismatch."
		)
		return
	end

	player:SetAttribute(
		"WorldHandoffLifeValidated",
		true
	)

	print(
		"[WorldHandoffValidator] VALIDATED v2",
		player.Name,
		"Slot=" .. tostring(slotId),
		"Life=" .. tostring(lifeId)
	)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(validate, player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(validate, player)
end)

print(
	"[WorldHandoffValidator] READY v2"
		.. " | SecureSlotHandoff=ON"
		.. " | LifeValidation=ON"
)
