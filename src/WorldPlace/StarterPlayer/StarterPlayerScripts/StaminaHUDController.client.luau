--!strict
-- StaminaHUDController v2 - MainHUD PNG Clip
-- StarterPlayer > StarterPlayerScripts > StaminaHUDController
--
-- Replaces v1 TemporaryFutureReady.
--
-- IMPORTANT:
-- The PNG itself is NEVER horizontally compressed.
-- FillClip is resized and the Fill image is inversely expanded exactly like
-- the established HealthController clipping method.

local Players =
	game:GetService(
		"Players"
	)

local TweenService =
	game:GetService(
		"TweenService"
	)


local player =
	Players.LocalPlayer

local playerGui =
	player:
	WaitForChild(
		"PlayerGui"
	)


local character: Model? =
	nil

local staminaConnection: RBXScriptConnection? =
	nil

local maxStaminaConnection: RBXScriptConnection? =
	nil


local fillClip: GuiObject? =
	nil

local fill: GuiObject? =
	nil

local valueLabel: TextLabel? =
	nil

local currentTween: Tween? =
	nil


local displayedStamina =
	Instance.new(
		"NumberValue"
	)

displayedStamina.Name =
	"DisplayedStamina"

displayedStamina.Value =
	100

displayedStamina.Parent =
	script


local TWEEN_TIME =
	0.08


local function disconnect(
	connection: RBXScriptConnection?
)

	if connection then
		connection:
			Disconnect()
	end
end


local function stopTween()

	if currentTween then

		currentTween:
			Cancel()

		currentTween =
			nil
	end
end


local function resolveHUD(): boolean

	local mainHUD =
		playerGui:
		FindFirstChild(
			"MainHUD"
		)

	if not mainHUD
		or not mainHUD:IsA(
			"ScreenGui"
		) then

		return false
	end


	mainHUD.ResetOnSpawn =
		false

	mainHUD.Enabled =
		true


	local staminaBar =
		mainHUD:
		FindFirstChild(
			"StaminaBar"
		)

	if not staminaBar
		or not staminaBar:IsA(
			"GuiObject"
		) then

		return false
	end


	staminaBar.Visible =
		true


	local barArea =
		staminaBar:
		FindFirstChild(
			"BarArea"
		)

	if not barArea
		or not barArea:IsA(
			"GuiObject"
		) then

		return false
	end


	local nextClip =
		barArea:
		FindFirstChild(
			"FillClip"
		)

	if not nextClip
		or not nextClip:IsA(
			"GuiObject"
		) then

		return false
	end


	local nextFill =
		nextClip:
		FindFirstChild(
			"Fill"
		)

	if not nextFill
		or not nextFill:IsA(
			"GuiObject"
		) then

		return false
	end


	fillClip =
		nextClip

	fill =
		nextFill

	fillClip.ClipsDescendants =
		true

	fillClip.BackgroundTransparency =
		1


	local nextValue =
		barArea:
		FindFirstChild(
			"StaminaValue"
		)

	if nextValue
		and nextValue:IsA(
			"TextLabel"
		) then

		valueLabel =
			nextValue
	else

		valueLabel =
			nil
	end


	return true
end


local function applyClip(
	ratio: number
)

	if not fillClip
		or not fill then

		return
	end


	ratio =
		math.clamp(
			ratio,
			0,
			1
		)


	fillClip.Size =
		UDim2.new(
			ratio,
			0,
			1,
			0
		)


	if ratio >
		0.0001 then

		fill.Size =
			UDim2.new(
				1 / ratio,
				0,
				1,
				0
			)

	else

		fill.Size =
			UDim2.fromScale(
				1,
				1
			)
	end


	fill.Position =
		UDim2.fromScale(
			0,
			0
		)
end


local function getMaxStamina(): number

	if not character then
		return 100
	end


	local value =
		character:
		GetAttribute(
			"MaxStamina"
		)


	if typeof(value) ==
		"number"
		and value > 0 then

		return value
	end


	return 100
end


local function refreshVisual()

	if not character
		or not character.Parent then

		return
	end


	if not fill
		or not fill.Parent then

		if not resolveHUD() then
			return
		end
	end


	local maxStamina =
		getMaxStamina()


	local value =
		math.clamp(
			displayedStamina.Value,
			0,
			maxStamina
		)


	applyClip(
		value
			/ maxStamina
	)


	if valueLabel then

		local actual =
			character:
			GetAttribute(
				"Stamina"
			)


		if typeof(actual) ~=
			"number" then

			actual =
				value
		end


		valueLabel.Text =
			string.format(
				"%d / %d",
				math.floor(
					math.max(
						0,
						actual
					) + 0.5
				),
				math.floor(
					maxStamina
					+ 0.5
				)
			)
	end
end


local function updateFromAttributes(
	immediate: boolean?
)

	if not character
		or not character.Parent then

		return
	end


	local stamina =
		character:
		GetAttribute(
			"Stamina"
		)


	local maxStamina =
		getMaxStamina()


	if typeof(stamina) ~=
		"number" then

		return
	end


	stamina =
		math.clamp(
			stamina,
			0,
			maxStamina
		)


	stopTween()


	if immediate then

		displayedStamina.Value =
			stamina

		refreshVisual()

		return
	end


	currentTween =
		TweenService:
		Create(
			displayedStamina,
			TweenInfo.new(
				TWEEN_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value =
				stamina
			}
		)


	currentTween:
		Play()


	refreshVisual()
end


local function bindCharacter(
	newCharacter: Model
)

	disconnect(
		staminaConnection
	)

	disconnect(
		maxStaminaConnection
	)


	character =
		newCharacter


	staminaConnection =
		newCharacter:
		GetAttributeChangedSignal(
			"Stamina"
		):
		Connect(
			function()

				updateFromAttributes(
					false
				)
			end
		)


	maxStaminaConnection =
		newCharacter:
		GetAttributeChangedSignal(
			"MaxStamina"
		):
		Connect(
			function()

				updateFromAttributes(
					true
				)
			end
		)


	resolveHUD()

	updateFromAttributes(
		true
	)
end


displayedStamina.Changed:
	Connect(
		refreshVisual
	)


player.CharacterAdded:
	Connect(
		function(
			newCharacter: Model
		)

			task.defer(
				function()

					bindCharacter(
						newCharacter
					)
				end
			)
		end
	)


playerGui.DescendantAdded:
	Connect(
		function(
			descendant: Instance
		)

			if descendant.Name ==
				"StaminaBar"
				or descendant.Name ==
				"FillClip"
				or descendant.Name ==
				"StaminaValue" then

				task.defer(
					function()

						resolveHUD()

						updateFromAttributes(
							true
						)
					end
				)
			end
		end
	)


if player.Character then

	task.defer(
		function()

			if player.Character then

				bindCharacter(
					player.Character
				)
			end
		end
	)
end


print(
	"[StaminaHUD] READY v2"
		.. " | MainHUDPNG=ON"
		.. " | ClipNoStretch=ON"
)
