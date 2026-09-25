--!strict
-- ChakraHUDController v2 - MainHUD PNG Clip
-- StarterPlayer > StarterPlayerScripts > ChakraHUDController
--
-- Replaces the temporary Chakra HUD controller.
--
-- Uses character attributes published by ChakraService:
-- Chakra
-- MaxChakra
-- ChakraCharging
--
-- The fill PNG is revealed through FillClip. It is never squashed.

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

local chakraConnection: RBXScriptConnection? =
	nil

local maxChakraConnection: RBXScriptConnection? =
	nil

local chargingConnection: RBXScriptConnection? =
	nil


local fillClip: GuiObject? =
	nil

local fill: GuiObject? =
	nil

local valueLabel: TextLabel? =
	nil

local chargeStatus: TextLabel? =
	nil

local currentTween: Tween? =
	nil


local displayedChakra =
	Instance.new(
		"NumberValue"
	)

displayedChakra.Name =
	"DisplayedChakra"

displayedChakra.Value =
	100

displayedChakra.Parent =
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


	local chakraBar =
		mainHUD:
		FindFirstChild(
			"ChakraBar"
		)

	if not chakraBar
		or not chakraBar:IsA(
			"GuiObject"
		) then

		return false
	end


	chakraBar.Visible =
		true


	local barArea =
		chakraBar:
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
			"ChakraValue"
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


	local nextStatus =
		chakraBar:
		FindFirstChild(
			"ChargeStatus"
		)

	if nextStatus
		and nextStatus:IsA(
			"TextLabel"
		) then

		chargeStatus =
			nextStatus
	else

		chargeStatus =
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


local function getMaxChakra(): number

	if not character then
		return 100
	end


	local value =
		character:
		GetAttribute(
			"MaxChakra"
		)


	if typeof(value) ==
		"number"
		and value > 0 then

		return value
	end


	return 100
end


local function refreshChargingStatus()

	if not chargeStatus then
		return
	end


	local charging =
		character ~= nil
		and character.Parent ~= nil
		and character:
		GetAttribute(
			"ChakraCharging"
		) == true


	chargeStatus.Visible =
		charging

	chargeStatus.Text =
		charging
		and "CHARGING"
		or ""
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


	local maxChakra =
		getMaxChakra()


	local value =
		math.clamp(
			displayedChakra.Value,
			0,
			maxChakra
		)


	applyClip(
		value
			/ maxChakra
	)


	if valueLabel then

		local actual =
			character:
			GetAttribute(
				"Chakra"
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
					maxChakra
					+ 0.5
				)
			)
	end


	refreshChargingStatus()
end


local function updateFromAttributes(
	immediate: boolean?
)

	if not character
		or not character.Parent then

		return
	end


	local chakra =
		character:
		GetAttribute(
			"Chakra"
		)


	local maxChakra =
		getMaxChakra()


	if typeof(chakra) ~=
		"number" then

		return
	end


	chakra =
		math.clamp(
			chakra,
			0,
			maxChakra
		)


	stopTween()


	if immediate then

		displayedChakra.Value =
			chakra

		refreshVisual()

		return
	end


	currentTween =
		TweenService:
		Create(
			displayedChakra,
			TweenInfo.new(
				TWEEN_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value =
				chakra
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
		chakraConnection
	)

	disconnect(
		maxChakraConnection
	)

	disconnect(
		chargingConnection
	)


	character =
		newCharacter


	chakraConnection =
		newCharacter:
		GetAttributeChangedSignal(
			"Chakra"
		):
		Connect(
			function()

				updateFromAttributes(
					false
				)
			end
		)


	maxChakraConnection =
		newCharacter:
		GetAttributeChangedSignal(
			"MaxChakra"
		):
		Connect(
			function()

				updateFromAttributes(
					true
				)
			end
		)


	chargingConnection =
		newCharacter:
		GetAttributeChangedSignal(
			"ChakraCharging"
		):
		Connect(
			refreshChargingStatus
		)


	resolveHUD()

	updateFromAttributes(
		true
	)

	refreshChargingStatus()
end


displayedChakra.Changed:
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
				"ChakraBar"
				or descendant.Name ==
				"FillClip"
				or descendant.Name ==
				"ChakraValue" then

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
	"[ChakraHUD] READY v2"
		.. " | MainHUDPNG=ON"
		.. " | ClipNoStretch=ON"
		.. " | LabelPendingCompatible=ON"
)
