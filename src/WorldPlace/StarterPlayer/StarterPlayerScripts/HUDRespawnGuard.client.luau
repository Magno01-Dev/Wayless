--!strict
-- HUDRespawnGuard v2 - Health + Chakra + Stamina
-- StarterPlayer > StarterPlayerScripts > HUDRespawnGuard
--
-- Replaces HUDRespawnGuard v1.
-- Keeps all three resource bars alive/visible after execution respawns.

local Players =
	game:GetService(
		"Players"
	)


local player =
	Players.LocalPlayer

local playerGui =
	player:
	WaitForChild(
		"PlayerGui"
	)


local RESOURCE_BARS = {
	"HealthBar",
	"ChakraBar",
	"StaminaBar",
}


local function restoreHUD()

	local mainHUD =
		playerGui:
		FindFirstChild(
			"MainHUD"
		)

	if not mainHUD then
		return
	end


	if mainHUD:IsA(
		"ScreenGui"
		) then

		mainHUD.ResetOnSpawn =
			false

		mainHUD.Enabled =
			true
	end


	for _,
		barName in ipairs(
			RESOURCE_BARS
		) do

		local bar =
			mainHUD:
			FindFirstChild(
				barName
			)


		if bar
			and bar:IsA(
				"GuiObject"
			) then

			bar.Visible =
				true


			local barArea =
				bar:
				FindFirstChild(
					"BarArea"
				)


			if barArea
				and barArea:IsA(
					"GuiObject"
				) then

				barArea.Visible =
					true
			end
		end
	end
end


player.CharacterAdded:
	Connect(
		function()

			task.defer(
				restoreHUD
			)

			task.delay(
				0.25,
				restoreHUD
			)
		end
	)


playerGui.ChildAdded:
	Connect(
		function(
			child: Instance
		)

			if child.Name ==
				"MainHUD" then

				task.defer(
					restoreHUD
				)
			end
		end
	)


restoreHUD()


print(
	"[HUDRespawnGuard] READY v2"
		.. " | Health/Chakra/Stamina=ON"
)
