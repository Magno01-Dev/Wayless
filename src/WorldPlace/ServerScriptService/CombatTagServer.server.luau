--!strict
-- CombatTagServer v1
-- PLACE AS Script:
-- ServerScriptService > CombatTagServer
--
-- Starts CombatTagService, mirrors state to fresh characters,
-- handles "mb all", and reports combat logging.
--
-- IMPORTANT:
-- Roblox cannot physically prevent a user from closing the client.
-- If a tagged player leaves, this script fires:
-- ServerStorage > CombatTagInternal > CombatLogDetected
--
-- Your future lives/permadeath system can listen to that BindableEvent
-- and remove a life.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatTagService =
	require(
		ServerScriptService:
		WaitForChild("CombatTagService")
	)

CombatTagService.Start()


local function normalizeCommand(
	message: string
): string

	local normalized =
		string.lower(message)

	normalized =
		string.gsub(
			normalized,
			"^%s+",
			""
		)

	normalized =
		string.gsub(
			normalized,
			"%s+$",
			""
		)

	normalized =
		string.gsub(
			normalized,
			"%s+",
			" "
		)

	return normalized
end


local function setupPlayer(
	player: Player
)
	if player:GetAttribute(
		"CombatTagged"
		) == nil then

		player:SetAttribute(
			"CombatTagged",
			false
		)
	end

	if player:GetAttribute(
		"CombatTagMaxExpiresAt"
		) == nil then

		player:SetAttribute(
			"CombatTagMaxExpiresAt",
			0
		)
	end

	player.CharacterAdded:Connect(
		function(character: Model)
			task.defer(function()
				if character.Parent then
					CombatTagService.SyncCharacter(
						player,
						character
					)

					CombatTagService.SendSnapshot(
						player
					)
				end
			end)
		end
	)

	if player.Character then
		CombatTagService.SyncCharacter(
			player,
			player.Character
		)
	end

	player.Chatted:Connect(
		function(message: string)
			local command =
				normalizeCommand(message)

			if command == "mb all"
				or command == "/mb all" then

				local removed =
					CombatTagService.ClearTagsPlacedBy(
						player
					)

				print(
					"[CombatTag] mb all:",
					player.Name,
					"removed",
					removed,
					"tag(s) placed by them"
				)
			end
		end
	)
end


for _, player in ipairs(
	Players:GetPlayers()
	) do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(
	setupPlayer
)

Players.PlayerRemoving:Connect(
	function(player: Player)
		-- Do this BEFORE deleting the victim-side state.
		-- Tags this player placed on OTHER players are intentionally
		-- NOT cleared by leaving. Only "mb all" clears those.
		CombatTagService.ReportCombatLog(
			player
		)

		CombatTagService.RemoveVictimState(
			player
		)
	end
)

print(
	"[CombatTagServer] ready. Duration=",
	CombatTagService.GetDefaultDuration(),
	"s | command=mb all"
)
