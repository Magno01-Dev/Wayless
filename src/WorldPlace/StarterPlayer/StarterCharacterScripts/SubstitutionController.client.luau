--!strict
-- SubstitutionController v1.4 - Launcher Air Counterplay + Server Confirmed Blue
-- StarterPlayer > StarterCharacterScripts > SubstitutionController
--
-- X = arm Substitution / Kawarimi dodge window.
--
-- The server is authoritative:
-- pressing X does NOT teleport immediately.
-- A valid incoming attack must reach the shared server damage gateway during
-- the short active window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player =
	Players.LocalPlayer

local character =
	script.Parent :: Model

local humanoid =
	character:
	WaitForChild(
		"Humanoid"
	) :: Humanoid

local remotes =
	ReplicatedStorage:
	WaitForChild(
		"SubstitutionRemotes",
		10
	)

if not remotes then
	error(
		"[Substitution-Client] SubstitutionRemotes did not appear after 10s. "
			.. "SubstitutionServer is missing or failed to start."
	)
end

local requestRemote =
	remotes:
	WaitForChild(
		"SubstitutionRequest",
		5
	) :: RemoteEvent?

local stateRemote =
	remotes:
	WaitForChild(
		"SubstitutionState",
		5
	) :: RemoteEvent?

if not requestRemote
	or not stateRemote then

	error(
		"[Substitution-Client] Required substitution remotes are missing."
	)
end

-- =========================
-- CONFIG
-- =========================

-- R is Combat Mode, F is Block, Q is Dash, C is Surface/ChakraFeet,
-- V/B are Downed interactions, G is Kunai.
local SUBSTITUTION_KEY =
	Enum.KeyCode.X

local DEBUG =
	true

-- =========================
-- LOCAL-ONLY TEST INDICATOR
-- =========================
--
-- This effect is created by the local player's LocalScript inside Lighting.
-- It is NOT replicated and does not modify the character, so opponents receive
-- zero visual warning that Substitution has been armed.
--
-- Color reference matches the current Chakra Feet blue family.
local INDICATOR_NAME =
	"LocalSubstitutionWindowIndicator"

local CHAKRA_BLUE =
	Color3.fromRGB(
		95,
		180,
		255
	)

local INDICATOR_TINT =
	Color3.fromRGB(
		155,
		210,
		255
	)

local INDICATOR_BRIGHTNESS =
	0.04

local INDICATOR_CONTRAST =
	0.08

local INDICATOR_SATURATION =
	-0.04

local INDICATOR_FADE_IN =
	0.07

local INDICATOR_FADE_OUT =
	0.10

local indicatorEffect: ColorCorrectionEffect? =
	nil

local indicatorTween: Tween? =
	nil

local function destroyOldLocalIndicator()
	local existing =
		Lighting:FindFirstChild(
			INDICATOR_NAME
		)

	if existing
		and existing:IsA(
			"ColorCorrectionEffect"
		) then

		existing:Destroy()
	end
end

local function ensureIndicator():
	ColorCorrectionEffect

	if indicatorEffect
		and indicatorEffect.Parent then

		return indicatorEffect
	end

	destroyOldLocalIndicator()

	local effect =
		Instance.new(
			"ColorCorrectionEffect"
		)

	effect.Name =
		INDICATOR_NAME

	-- Neutral starting values. We tween into the chakra-blue state only while
	-- the SERVER attribute says the dodge window is active.
	effect.TintColor =
		Color3.new(
			1,
			1,
			1
		)

	effect.Brightness =
		0

	effect.Contrast =
		0

	effect.Saturation =
		0

	effect.Enabled =
		true

	effect.Parent =
		Lighting

	indicatorEffect =
		effect

	return effect
end

local function cancelIndicatorTween()
	if indicatorTween then
		indicatorTween:Cancel()
		indicatorTween = nil
	end
end

local function setIndicatorActive(
	active: boolean
)
	local effect =
		ensureIndicator()

	cancelIndicatorTween()

	if active then
		indicatorTween =
			TweenService:Create(
				effect,
				TweenInfo.new(
					INDICATOR_FADE_IN,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					TintColor =
					INDICATOR_TINT,

					Brightness =
					INDICATOR_BRIGHTNESS,

					Contrast =
					INDICATOR_CONTRAST,

					Saturation =
					INDICATOR_SATURATION,
				}
			)

		indicatorTween:Play()
	else
		indicatorTween =
			TweenService:Create(
				effect,
				TweenInfo.new(
					INDICATOR_FADE_OUT,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					TintColor =
					Color3.new(
						1,
						1,
						1
					),

					Brightness = 0,
					Contrast = 0,
					Saturation = 0,
				}
			)

		indicatorTween:Play()
	end
end

local function syncWindowIndicator()
	setIndicatorActive(
		character:GetAttribute(
			"SubstitutionWindowActive"
		) == true
	)
end

-- =========================
-- LOCAL PRECHECK
-- =========================

local function isLauncherAirVictim(): boolean
	return character:GetAttribute(
		"AirComboServerActive"
	) == true
		and character:GetAttribute(
			"AirComboRole"
		) == "Victim"
		and character:GetAttribute(
			"LauncherAirComboVictim"
		) == true
end


local function isBusy(): boolean
	return character:GetAttribute("DownedActionLocked") == true
		or character:GetAttribute("IsDowned") == true
		or character:GetAttribute("IsCarried") == true
		or character:GetAttribute("IsCarrying") == true
		or character:GetAttribute("IsExecuting") == true
		or character:GetAttribute("IsBeingExecuted") == true
		or character:GetAttribute("IsRecovering") == true
		or (
			character:GetAttribute("IsStunned") == true
			and not isLauncherAirVictim()
		)
		or character:GetAttribute("IsAttacking") == true
		or character:GetAttribute("IsDashing") == true
		or character:GetAttribute("IsBlocking") == true
		or character:GetAttribute("TreeJumpActive") == true
		or character:GetAttribute("IsTreeJumping") == true
		or character:GetAttribute("SurfaceJumping") == true
end

local function cooldownRemaining(): number
	local cooldownEndsAt =
		character:GetAttribute(
			"SubstitutionCooldownEndsAt"
		)

	if typeof(cooldownEndsAt)
		~= "number" then
		return 0
	end

	return math.max(
		0,
		cooldownEndsAt
		- workspace:
			GetServerTimeNow()
	)
end

local function canRequest(): boolean
	if humanoid.Health <= 0
		or isBusy() then
		return false
	end

	if character:GetAttribute(
		"SubstitutionWindowActive"
		) == true then
		return false
	end

	return cooldownRemaining() <= 0
end

-- =========================
-- SERVER WINDOW VISUAL
-- =========================

character:GetAttributeChangedSignal(
	"SubstitutionWindowActive"
):Connect(
	syncWindowIndicator
)

-- Initial state in case replication beats this LocalScript startup.
task.defer(
	syncWindowIndicator
)

-- =========================
-- INPUT
-- =========================

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)

			if gameProcessed
				or UserInputService:
				GetFocusedTextBox() then
				return
			end

			if input.UserInputType ~=
				Enum.UserInputType.Keyboard then
				return
			end

			if input.KeyCode ~=
				SUBSTITUTION_KEY then
				return
			end

			print(
				"[Substitution-Client] X pressed"
			)

			if not canRequest() then
				print(
					"[Substitution-Client] local precheck blocked X",
					"busy=",
					isBusy(),
					"cooldownRemaining=",
					cooldownRemaining()
				)

				return
			end

			print(
				"[Substitution-Client] sending Arm request"
			)

			requestRemote:
			FireServer(
				"Arm",
				character
			)
		end
	)

-- =========================
-- SERVER FEEDBACK
-- =========================

stateRemote.OnClientEvent:
	Connect(
		function(
			action: string,
			arg1: any,
			arg2: any
		)

			if not DEBUG then
				return
			end

			if action == "Armed" then
				print(
					"[Substitution-Client] ARM ACCEPTED BY SERVER - blue indicator ON"
				)

				-- Direct server confirmation drives the testing visual immediately.
				-- The replicated attribute remains the authoritative backup and
				-- will turn it off when the server window closes/triggers.
				setIndicatorActive(
					true
				)

			elseif action == "Rejected" then
				print(
					"[Substitution-Client] rejected:",
					tostring(arg1),
					"cooldown:",
					tostring(arg2)
				)

			elseif action == "Triggered" then
				local subject =
				arg1

				if subject == player then
					print(
						"[Substitution-Client] TRIGGERED"
					)
				end
			end
		end
	)

script.Destroying:Connect(
	function()
		cancelIndicatorTween()

		if indicatorEffect
			and indicatorEffect.Parent then

			indicatorEffect:Destroy()
			indicatorEffect = nil
		end
	end
)

print(
	"[Substitution-Client] READY v1.4 key=X launcherAirCounterplay=ON serverConfirmedBlue=ON"
)
