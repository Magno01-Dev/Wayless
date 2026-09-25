--!strict
-- ThrowableController v3.7 - Status Combat Gate + Combat Counter Priority + Fast Defensive Throw
-- StarterPlayer > StarterCharacterScripts > ThrowableController
--
-- One throwable input:
--
-- TAP G
-- -> Combat Mode ON: throw currently selected projectile
-- -> Combat Mode OFF: send defensive-only request; server accepts it only if
--    a real incoming projectile can be intercepted
--
-- HOLD G
-- -> open Ninja Bag radial
-- -> move mouse toward a slot
-- -> release G to save selection
-- -> releasing from radial does NOT throw
--
-- R is intentionally untouched because Combat Mode already owns it.
--
-- UI is intentionally code-built/prototype quality, but follows the current
-- DiabloStudios HUD direction:
-- dark translucent surfaces, restrained gold lines, muted red accents,
-- compact typography, no cartoon styling.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local player =
	Players.LocalPlayer


local character =
	script.Parent

local humanoid =
	character:
	WaitForChild(
		"Humanoid"
	) :: Humanoid

local rootPart =
	character:
	WaitForChild(
		"HumanoidRootPart"
	) :: BasePart


local ProjectileConfigs =
	require(
		ReplicatedStorage:
		WaitForChild(
			"ProjectileConfigs"
		)
	)


local combatAimModule =
	ReplicatedStorage:
	FindFirstChild(
		"CombatAim"
	)


local CombatAim: any =
	nil


if combatAimModule then

	CombatAim =
		require(
			combatAimModule
		)
end


local remotes =
	ReplicatedStorage:
	WaitForChild(
		"ProjectileRemotes"
	)


local projectileRequest =
	remotes:
	WaitForChild(
		"ProjectileRequest"
	) :: RemoteEvent


local projectileDefenseRequest =
	remotes:
	WaitForChild(
		"ProjectileDefenseRequest"
	) :: RemoteEvent


local projectileDefensePrepare =
	remotes:
	WaitForChild(
		"ProjectileDefensePrepare"
	) :: RemoteFunction


local projectileThrowAccepted =
	remotes:
	WaitForChild(
		"ProjectileThrowAccepted"
	) :: RemoteEvent


local projectileCombatState =
	remotes:
	WaitForChild(
		"ProjectileCombatState"
	) :: RemoteEvent

-- =========================
-- NINJA BAG INPUT / SLOT CONTRACT
-- =========================

local NINJA_BAG_KEY =
	Enum.KeyCode.G

local NINJA_BAG_HOLD_TIME =
	0.22

local NINJA_BAG_DEADZONE =
	42

local NINJA_BAG_SLOT_COUNT =
	4


-- The RADIAL owns directions.
-- The LOADOUT owns projectile identity.
--
-- No direction is permanently tied to Kunai/Shuriken/Senbon/Fuma.
local SLOT_DEFINITIONS = {
	[1] = {
		Direction = "Up",
		Index = "01",
	},

	[2] = {
		Direction = "Right",
		Index = "02",
	},

	[3] = {
		Direction = "Down",
		Index = "03",
	},

	[4] = {
		Direction = "Left",
		Index = "04",
	},
}


local function slotProjectileAttribute(
	slotIndex: number
): string

	return "NinjaBagSlot"
		.. tostring(
			slotIndex
		)
		.. "Projectile"
end


local function amountAttribute(
	projectileType: string
): string

	return "NinjaBagAmount_"
		.. projectileType
end


local function maxAmountAttribute(
	projectileType: string
): string

	return "NinjaBagMax_"
		.. projectileType
end


local function getSlotProjectile(
	slotIndex: number
): string?

	local value =
		player:GetAttribute(
			slotProjectileAttribute(
				slotIndex
			)
		)


	if typeof(value) ~= "string"
		or value == "" then

		return nil
	end


	if not ProjectileConfigs[
		value
		] then

		return nil
	end


	return value
end


local function getProjectileAmount(
	projectileType: string?
): number

	if not projectileType then
		return 0
	end


	local value =
		player:GetAttribute(
			amountAttribute(
				projectileType
			)
		)


	if typeof(value) ~= "number" then
		return 0
	end


	return math.max(
		0,
		math.floor(
			value
		)
	)
end


local function getProjectileMaxAmount(
	projectileType: string?
): number

	if not projectileType then
		return 0
	end


	local value =
		player:GetAttribute(
			maxAmountAttribute(
				projectileType
			)
		)


	if typeof(value) ~= "number" then
		return 0
	end


	return math.max(
		0,
		math.floor(
			value
		)
	)
end


local function getProjectilePresentation(
	projectileType: string?
): (string, string)

	if not projectileType then

		return "VACÍO",
			"SIN EQUIPAR"
	end


	local config =
		ProjectileConfigs[
	projectileType
	]


	if not config then

		return string.upper(
			projectileType
		),
			"NO CONFIG"
	end


	local bag =
		config.NinjaBag


	if typeof(bag) == "table" then

		local displayName =
			if typeof(
				bag.DisplayName
			) == "string"
			then bag.DisplayName
			else string.upper(
				projectileType
			)


		local subtitle =
			if typeof(
				bag.Subtitle
			) == "string"
			then bag.Subtitle
			else "LANZABLE"


		return displayName,
			subtitle
	end


	return string.upper(
		projectileType
	),
		"LANZABLE"
end


-- Give the server-created NinjaBagService attributes a short initialization
-- window before constructing the radial.
local ninjaBagReadyDeadline =
	time() + 5

while player:GetAttribute(
	"NinjaBagReady"
	) ~= true
		and time() <
		ninjaBagReadyDeadline do

	task.wait(
		0.05
	)
end


if player:GetAttribute(
	"NinjaBagReady"
	) ~= true then

	warn(
		"[ThrowableController] NinjaBagReady was not received within 5s."
	)
end

-- =========================
-- CLIENT SETTINGS
-- =========================

local MAX_TARGET_DISTANCE =
	1000

local LOCAL_REQUEST_DEBOUNCE =
	0.08

local DEBUG_THROWABLE =
	true

-- =========================
-- THROW ANIMATION
-- =========================

local THROW_NORMAL_ANIMATION_ID =
	"rbxassetid://85810196265540"

local THROW_SPRINT_ANIMATION_ID =
	"rbxassetid://121774304926898"

local NORMAL_THROW_ANIMATION_SPEED =
	1.25

local DEFENSIVE_THROW_ANIMATION_SPEED =
	3.0

local THROW_ANIMATION_SOURCE_FPS =
	60

local THROW_ANIMATION_TOTAL_FRAMES =
	54

local THROW_RELEASE_FRAME =
	40


local function getReleaseTimeForSpeed(
	playbackSpeed: number
): number

	return (
		THROW_RELEASE_FRAME
			/ THROW_ANIMATION_SOURCE_FPS
	) / playbackSpeed
end


local function getAnimationTimeForSpeed(
	playbackSpeed: number
): number

	return (
		THROW_ANIMATION_TOTAL_FRAMES
			/ THROW_ANIMATION_SOURCE_FPS
	) / playbackSpeed
end

local THROW_ANIMATION_FADE_IN =
	0.06

local THROW_ANIMATION_FADE_OUT =
	0.08

local THROW_VARIANT_CROSSFADE =
	0.07

-- =========================
-- LOCAL STATE
-- =========================

local lastLocalRequest =
	-math.huge

local throwGeneration =
	0

local pendingThrow = nil

local normalThrowAnimation =
	Instance.new(
		"Animation"
	)

normalThrowAnimation.Name =
	"GenericThrowableThrowNormal"

normalThrowAnimation.AnimationId =
	THROW_NORMAL_ANIMATION_ID


local sprintThrowAnimation =
	Instance.new(
		"Animation"
	)

sprintThrowAnimation.Name =
	"GenericThrowableThrowSprint"

sprintThrowAnimation.AnimationId =
	THROW_SPRINT_ANIMATION_ID


local animator =
	humanoid:
	FindFirstChildOfClass(
		"Animator"
	)

if not animator then

	animator =
		Instance.new(
			"Animator"
		)

	animator.Parent =
		humanoid
end


local function loadThrowTrack(
	animation: Animation,
	label: string
): AnimationTrack?

	local ok,
		track =
		pcall(
			function()

				return animator:
				LoadAnimation(
					animation
				)
			end
		)


	if not ok
		or not track then

		warn(
			"[ThrowableController] Failed to load "
				.. label
				.. " throwable animation:",
			animation.AnimationId
		)

		return nil
	end


	track.Priority =
		Enum.AnimationPriority.Action

	track.Looped =
		false


	return track
end


local normalThrowAnimationTrack =
	loadThrowTrack(
		normalThrowAnimation,
		"normal"
	)


local sprintThrowAnimationTrack =
	loadThrowTrack(
		sprintThrowAnimation,
		"sprint"
	)


local activeThrowAnimationTrack: AnimationTrack? =
	nil


local function stopThrowAnimationTracks(
	fadeTime: number
)

	if normalThrowAnimationTrack
		and normalThrowAnimationTrack.IsPlaying then

		normalThrowAnimationTrack:
			Stop(
				fadeTime
			)
	end


	if sprintThrowAnimationTrack
		and sprintThrowAnimationTrack.IsPlaying then

		sprintThrowAnimationTrack:
			Stop(
				fadeTime
			)
	end


	activeThrowAnimationTrack =
		nil
end


local function getThrowTrackForCurrentMovement(): (AnimationTrack?, string)

	if character:GetAttribute(
		"IsSprinting"
		) == true then

		return sprintThrowAnimationTrack,
			"Sprint"
	end


	return normalThrowAnimationTrack,
		"Normal"
end


local selectedSlot =
	if typeof(
		player:GetAttribute(
			"NinjaBagSelectedSlot"
		)
	) == "number"
	and player:GetAttribute(
		"NinjaBagSelectedSlot"
	) >= 1
	and player:GetAttribute(
		"NinjaBagSelectedSlot"
	) <= NINJA_BAG_SLOT_COUNT
	then math.floor(
		player:GetAttribute(
			"NinjaBagSelectedSlot"
		)
	)
	else 1


player:SetAttribute(
	"NinjaBagSelectedSlot",
	selectedSlot
)


local ninjaBagKeyDown =
	false

local ninjaBagPressedAt =
	0.0

local ninjaBagPressGeneration =
	0

local radialOpen =
	false

local hoveredSlot: number? =
	nil

local previousMouseBehavior =
	UserInputService.MouseBehavior

local previousMouseIconEnabled =
	UserInputService.MouseIconEnabled


local ninjaBagGui: ScreenGui? =
	nil

local radialRoot: Frame? =
	nil

local radialScale: UIScale? =
	nil

local radialDim: Frame? =
	nil

local centerSelectedLabel: TextLabel? =
	nil

local selectedIndicator: Frame? =
	nil

local selectedIndicatorCategory: TextLabel? =
	nil

local selectedIndicatorName: TextLabel? =
	nil

local selectedIndicatorAmount: TextLabel? =
	nil

local slotFrames: {[number]: Frame} =
	{}

local slotStrokes: {[number]: UIStroke} =
	{}

local slotAccentBars: {[number]: Frame} =
	{}

local slotIndexLabels: {[number]: TextLabel} =
	{}

local slotNameLabels: {[number]: TextLabel} =
	{}

local slotSubtitleLabels: {[number]: TextLabel} =
	{}

local slotAmountLabels: {[number]: TextLabel} =
	{}


character:SetAttribute(
	"IsThrowingProjectile",
	false
)


for projectileType in pairs(
	ProjectileConfigs
	) do

	character:SetAttribute(
		"IsThrowing"
			.. projectileType,
		false
	)
end


-- COMPATIBILITY:
-- Current AttackController blocks M1 using IsThrowingKunai.
-- While the combat controller is still on that older contract, all throwable
-- actions mirror into IsThrowingKunai too.
character:SetAttribute(
	"IsThrowingKunai",
	false
)

-- =========================
-- HELPERS
-- =========================

local function reject(
	reason: string
): boolean

	if DEBUG_THROWABLE then

		print(
			"[ThrowableController] REJECT:",
			reason
		)
	end


	return false
end


local function syncCombatMode()

	projectileCombatState:
		FireServer(
			character:GetAttribute(
				"CombatMode"
			) == true
		)
end


local function getCooldownRemaining(
	projectileType: string
): number

	local endsAt =
		character:GetAttribute(
			"CoreCooldown_"
			.. projectileType
			.. "_EndsAt"
		)


	if typeof(endsAt) ~=
		"number" then

		return 0
	end


	return math.max(
		0,
		endsAt
		- workspace:
			GetServerTimeNow()
	)
end


local function isTreeJumpActive(): boolean

	return character:GetAttribute(
		"TreeJumpActive"
	) == true
		or character:GetAttribute(
			"IsTreeJumping"
		) == true
end


local function isStatusCombatBlocked(): boolean
	return character:GetAttribute(
		"Status_AttackBlocked"
	) == true

		or character:GetAttribute(
			"Status_Stunned"
		) == true
end


local function canThrow(
	projectileType: string
): boolean

	if humanoid.Health <= 0
		or not rootPart.Parent then

		return reject(
			"dead/no root"
		)
	end


	if character:GetAttribute(
		"CombatSuppressed"
		) == true then

		return reject(
			"CombatSuppressed"
		)
	end


	if character:GetAttribute(
		"DownedActionLocked"
		) == true
			or character:GetAttribute(
				"IsDowned"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true
			or character:GetAttribute(
				"IsExecuting"
			) == true
			or character:GetAttribute(
				"IsCarrying"
			) == true then

		return reject(
			"Downed system lock"
		)
	end


	if character:GetAttribute(
		"IsStunned"
		) == true
			or isStatusCombatBlocked() then

		return reject(
			"Stunned/StatusAttackBlocked"
		)
	end


	if character:GetAttribute(
		"IsBlocking"
		) == true then

		return reject(
			"IsBlocking"
		)
	end


	if character:GetAttribute(
		"IsAttacking"
		) == true then

		return reject(
			"IsAttacking"
		)
	end


	if character:GetAttribute(
		"IsDashing"
		) == true then

		return reject(
			"IsDashing"
		)
	end


	if character:GetAttribute(
		"IsThrowingProjectile"
		) == true then

		return reject(
			"already throwing"
		)
	end


	if isTreeJumpActive() then

		return reject(
			"TreeJump"
		)
	end


	if getCooldownRemaining(
		projectileType
		) > 0 then

		return reject(
			"server cooldown"
		)
	end


	if time() - lastLocalRequest <
		LOCAL_REQUEST_DEBOUNCE then

		return reject(
			"local request debounce"
		)
	end


	return true
end

-- =========================
-- THROW ORIGIN / AIM
-- =========================

local function getThrowOriginPosition(
	projectileType: string
): Vector3

	local explicit =
		character:
		FindFirstChild(
			projectileType
			.. "ThrowOrigin",
			true
		)


	if explicit
		and explicit:IsA(
			"Attachment"
		) then

		return explicit.WorldPosition
	end


	-- Generic throwable origin intentionally uses LEFT ARM.
	-- The RIGHT ARM remains free for future Kenjutsu weapon ownership.
	local leftArm =
		character:
		FindFirstChild(
			"Left Arm"
		)


	if leftArm
		and leftArm:IsA(
			"BasePart"
		) then

		return leftArm.Position
		- leftArm.CFrame.UpVector
			* (
				leftArm.Size.Y
				* 0.28
			)
			+ leftArm.CFrame.LookVector
			* 0.12
	end


	return rootPart.Position
end


local function getAimData(
	projectileType: string
): (Vector3?, Vector3?, Vector3?)

	local camera =
		workspace.CurrentCamera


	if not camera then

		return nil,
			nil,
			nil
	end


	local throwOrigin =
		getThrowOriginPosition(
			projectileType
		)


	local params =
		RaycastParams.new()


	params.FilterType =
		Enum.RaycastFilterType.Exclude


	params.FilterDescendantsInstances =
		{
			character,
		}


	params.IgnoreWater =
		false


	if CombatAim
		and CombatAim.GetDirectionFromOrigin then

		local ok,
			direction,
			targetPoint =
			pcall(
				function()

					return CombatAim.GetDirectionFromOrigin(
						throwOrigin,
						MAX_TARGET_DISTANCE,
						params
					)
				end
			)


		if ok
			and typeof(direction) ==
			"Vector3"
			and typeof(targetPoint) ==
			"Vector3" then

			return targetPoint,
				direction,
				throwOrigin
		end
	end


	local mouseLocation =
		UserInputService:
		GetMouseLocation()


	local ray =
		camera:
		ScreenPointToRay(
			mouseLocation.X,
			mouseLocation.Y,
			0
		)


	local hit =
		workspace:
		Raycast(
			ray.Origin,
			ray.Direction
			* MAX_TARGET_DISTANCE,
			params
		)


	local target =
		if hit
		then hit.Position
		else ray.Origin
		+ ray.Direction
		* MAX_TARGET_DISTANCE


	local delta =
		target
	- throwOrigin


	if delta.Magnitude <= 0.001 then

		return nil,
			nil,
			nil
	end


	return target,
		delta.Unit,
		throwOrigin
end

-- =========================
-- THROW STATE
-- =========================

local function setThrowFlags(
	projectileType: string?,
	active: boolean
)

	character:SetAttribute(
		"IsThrowingProjectile",
		active
	)


	for knownType in pairs(
		ProjectileConfigs
		) do

		character:SetAttribute(
			"IsThrowing"
				.. knownType,
			active
				and knownType ==
				projectileType
		)
	end


	-- Legacy AttackController compatibility.
	character:SetAttribute(
		"IsThrowingKunai",
		active
	)
end


local function getThrowStateDuration(
	projectileType: string,
	playbackSpeed: number
): number

	local config =
		ProjectileConfigs[
	projectileType
	]

	local releaseTime =
		getReleaseTimeForSpeed(
			playbackSpeed
		)

	local animationDuration =
		getAnimationTimeForSpeed(
			playbackSpeed
		)
		+ THROW_ANIMATION_FADE_OUT
		+ 0.04


	if not config then
		return animationDuration
	end


	local pattern =
		config.Pattern


	if pattern.Mode ==
		"Sequential" then

		local volleyDuration =
			releaseTime
			+ (
				pattern.Count
				- 1
			)
			* pattern.Interval
			+ 0.12

		return math.max(
			animationDuration,
			volleyDuration
		)
	end


	return animationDuration
end


local function beginThrowState(
	projectileType: string,
	playbackSpeed: number
)

	throwGeneration +=
		1


	local generation =
		throwGeneration


	setThrowFlags(
		projectileType,
		true
	)


	task.delay(
		getThrowStateDuration(
			projectileType,
			playbackSpeed
		),
		function()

			if generation ~=
				throwGeneration then

				return
			end


			if character.Parent then

				setThrowFlags(
					nil,
					false
				)
			end
		end
	)
end


local function cancelThrowState()

	throwGeneration +=
		1

	pendingThrow =
		nil


	stopThrowAnimationTracks(
		THROW_ANIMATION_FADE_OUT
	)


	setThrowFlags(
		nil,
		false
	)
end

-- =========================
-- LOCAL LAUNCH AUDIO
-- =========================

local function getLaunchParent(): BasePart

	local leftArm =
		character:
		FindFirstChild(
			"Left Arm"
		)


	if leftArm
		and leftArm:IsA(
			"BasePart"
		) then

		return leftArm
	end


	return rootPart
end


local function playLaunchAudio(
	projectileType: string
)

	local config =
		ProjectileConfigs[
	projectileType
	]


	if not config then
		return
	end


	local audio =
		config.Audio.Launch


	local sound =
		Instance.new(
			"Sound"
		)


	sound.Name =
		projectileType
		.. "LocalLaunch"


	sound.SoundId =
		audio.SoundId


	sound.Volume =
		audio.Volume


	sound.PlaybackSpeed =
		audio.PlaybackSpeed


	sound.TimePosition =
		math.max(
			0,
			audio.StartTimePosition
			or 0
		)


	sound.Parent =
		getLaunchParent()


	local function playNow()

		if sound.Parent then

			sound:
				Play()
		end
	end


	if (
		audio.StartDelay
			or 0
		) > 0 then

		task.delay(
			audio.StartDelay,
			playNow
		)

	else

		playNow()
	end


	Debris:AddItem(
		sound,
		audio.Lifetime
			or 4
	)
end


local function requestCombatModeFromDefensiveCounter()

	-- CombatController is the sole owner of:
	-- - its internal combatMode variable
	-- - CombatMode / CombatSuppressed attributes
	-- - mouse lock
	-- - AutoRotate
	-- - CombatFacingAlign
	--
	-- Therefore ThrowableController does NOT write CombatMode directly.

	task.defer(
		function()

			if not character.Parent then
				return
			end


			local request =
				character:
				FindFirstChild(
					"CombatModeRequest"
				)


			if not request then

				request =
					character:
					WaitForChild(
						"CombatModeRequest",
						1.0
					)
			end


			if request
				and request:IsA(
					"BindableEvent"
				) then

				request:
					Fire(
						"Enter",
						"ProjectileCounter"
					)


				if DEBUG_THROWABLE then

					print(
						"[ThrowableController] AUTO COMBAT REQUEST -> ProjectileCounter"
					)
				end

			else

				warn(
					"[ThrowableController] CombatModeRequest not found; defensive counter succeeded but CombatController could not be asked to enter combat."
				)
			end
		end
	)
end


projectileThrowAccepted.OnClientEvent:
	Connect(
		function(
			projectileType: any,
			launchMode: any,
			_incomingProjectileType: any,
			autoEnterCombat: any,
			acceptedSlot: any,
			remainingAmmo: any
		)

			if typeof(projectileType) ~=
				"string" then

				return
			end


			if DEBUG_THROWABLE then

				print(
					"[ThrowableController] ACCEPTED",
					projectileType,
					launchMode,
					"slot=",
					acceptedSlot,
					"ammo=",
					remainingAmmo
				)
			end


			if launchMode ==
				"DefensiveIntercept"
				and autoEnterCombat == true
				and character:GetAttribute(
					"CombatMode"
				) ~= true then

				requestCombatModeFromDefensiveCounter()
			end


			playLaunchAudio(
				projectileType
			)
		end
	)

-- =========================
-- THROW
-- =========================

local function firePendingThrowAtRelease(
	generation: number,
	source: string
)

	local pending =
		pendingThrow


	if not pending
		or pending.Generation ~=
		generation
		or pending.Released then

		return
	end


	pending.Released =
		true


	if not character.Parent
		or humanoid.Health <= 0
		or not rootPart.Parent then

		cancelThrowState()

		return
	end


	local currentProjectileType =
		getSlotProjectile(
			pending.SlotIndex
		)


	if currentProjectileType ~=
		pending.ProjectileType then

		if DEBUG_THROWABLE then

			print(
				"[ThrowableController] RELEASE CANCEL:",
				"slot changed during windup"
			)
		end

		cancelThrowState()

		return
	end


	if getProjectileAmount(
		pending.ProjectileType
		) <= 0 then

		cancelThrowState()

		return
	end


	-- Defensive counter has priority in both CombatMode states.
	if pending.DefensiveCounter == true then

		local defensiveReleaseOrigin =
			getThrowOriginPosition(
				pending.ProjectileType
			)


		projectileDefenseRequest:
			FireServer(
				pending.SlotIndex,
				defensiveReleaseOrigin
			)


		if DEBUG_THROWABLE then

			print(
				"[ThrowableController] RELEASE DEFENSE REQUEST",
				"source=",
				source,
				"slot=",
				pending.SlotIndex,
				pending.ProjectileType,
				"combatAtStart=",
				pending.CombatActiveAtStart
			)
		end


		return
	end


	if pending.CombatActiveAtStart then

		local targetPosition,
			aimDirection,
			throwOrigin =
			getAimData(
				pending.ProjectileType
			)


		if not targetPosition
			or not aimDirection
			or not throwOrigin then

			cancelThrowState()

			return
		end


		syncCombatMode()


		projectileRequest:
			FireServer(
				pending.SlotIndex,
				targetPosition,
				aimDirection,
				throwOrigin
			)


		if DEBUG_THROWABLE then

			print(
				"[ThrowableController] RELEASE FIRE",
				"source=",
				source,
				"slot=",
				pending.SlotIndex,
				pending.ProjectileType,
				"frame=",
				THROW_RELEASE_FRAME,
				"time=",
				string.format(
					"%.3f",
					pending.ReleaseTime
				)
			)
		end


		return
	end


	-- Off-combat non-counter throws are never valid.
	cancelThrowState()
end


local function canBeginDefensiveThrow(
	slotIndex: number
): (boolean, string)

	-- Keep the server's CombatMode mirror fresh before asking for a
	-- defensive opportunity. This RemoteFunction is read-only: it does not
	-- consume ammo, start cooldowns, enter Combat Mode or launch anything.
	syncCombatMode()


	local ok,
		allowed,
		reason,
		incomingProjectileType,
		timeToImpact =
		pcall(
			function()

				return projectileDefensePrepare:
				InvokeServer(
					slotIndex
				)
			end
		)


	if not ok then

		warn(
			"[ThrowableController] Defensive preflight failed:",
			allowed
		)

		return false,
			"defensive preflight network error"
	end


	if allowed ~= true then

		if DEBUG_THROWABLE then

			print(
				"[ThrowableController] DEFENSE PREFLIGHT REJECT",
				reason
					or "no valid incoming threat"
			)
		end

		return false,
			tostring(
				reason
				or "no valid incoming threat"
			)
	end


	if DEBUG_THROWABLE then

		print(
			"[ThrowableController] DEFENSE PREFLIGHT OK",
			"incoming=",
			incomingProjectileType,
			"TTI=",
			if typeof(
				timeToImpact
			) == "number"
				then string.format(
					"%.3f",
					timeToImpact
				)
				else "?"
		)
	end


	return true,
		"OK"
end


local function beginAnimatedThrow(
	slotIndex: number
)

	if player:GetAttribute(
		"NinjaBagLoadoutOpen"
		) == true then

		reject(
			"Loadout UI open"
		)

		return
	end


	local projectileType =
		getSlotProjectile(
			slotIndex
		)


	if not projectileType then

		reject(
			"Slot "
				.. tostring(
					slotIndex
				)
				.. " empty"
		)

		return
	end


	if getProjectileAmount(
		projectileType
		) <= 0 then

		reject(
			projectileType
				.. " exhausted"
		)

		return
	end


	if not ProjectileConfigs[
		projectileType
		] then

		return
	end


	if not canThrow(
		projectileType
		) then

		return
	end


	local combatActive =
		character:GetAttribute(
			"CombatMode"
		) == true


	-- Probe the same server-authoritative counter window in BOTH modes.
	--
	-- Combat ON:
	--   valid window -> fast DefensiveIntercept
	--   no window    -> normal offensive throw
	--
	-- Combat OFF:
	--   valid window -> fast DefensiveIntercept
	--   no window    -> no animation/action
	local defensiveAllowed =
		canBeginDefensiveThrow(
			slotIndex
		)


	if not combatActive
		and not defensiveAllowed then

		return
	end


	-- A preflight round trip happened, so re-check local action state.
	if not canThrow(
		projectileType
		) then

		return
	end


	lastLocalRequest =
		time()


	local defensiveCounter =
		defensiveAllowed == true


	local playbackSpeed =
		if defensiveCounter
		then DEFENSIVE_THROW_ANIMATION_SPEED
		else NORMAL_THROW_ANIMATION_SPEED


	local releaseTime =
		getReleaseTimeForSpeed(
			playbackSpeed
		)


	local selectedThrowTrack,
		throwVariant =
		getThrowTrackForCurrentMovement()


	beginThrowState(
		projectileType,
		playbackSpeed
	)


	local generation =
		throwGeneration


	pendingThrow = {
		Generation =
			generation,

		SlotIndex =
			slotIndex,

		ProjectileType =
			projectileType,

		CombatActiveAtStart =
			combatActive,

		AnimationVariant =
			throwVariant,

		PlaybackSpeed =
			playbackSpeed,

		ReleaseTime =
			releaseTime,

		DefensiveFastThrow =
			defensiveCounter,

		DefensiveCounter =
			defensiveCounter,

		Released =
			false,
	}


	stopThrowAnimationTracks(
		0
	)


	if selectedThrowTrack then

		activeThrowAnimationTrack =
			selectedThrowTrack

		selectedThrowTrack.TimePosition =
			0


		selectedThrowTrack:
			Play(
				THROW_ANIMATION_FADE_IN,
				1,
				playbackSpeed
			)

	else

		warn(
			"[ThrowableController] "
				.. throwVariant
				.. " throw animation unavailable; using frame-40 fallback."
		)
	end


	task.delay(
		releaseTime
			+ 0.02,
		function()

			firePendingThrowAtRelease(
				generation,
				"Frame40Fallback"
			)
		end
	)


	if DEBUG_THROWABLE then

		print(
			"[ThrowableController] THROW WINDUP",
			projectileType,
			"slot=",
			slotIndex,
			"combat=",
			combatActive,
			"counter=",
			defensiveCounter,
			"variant=",
			throwVariant,
			"speed=",
			playbackSpeed,
			"release=",
			string.format(
				"%.3f",
				releaseTime
			),
			"animation=",
			if throwVariant == "Sprint"
				then 121774304926898
				else 85810196265540
		)
	end
end


local function connectReleaseMarker(
	track: AnimationTrack?,
	markerName: string,
	variant: string
)

	if not track then
		return
	end


	track:
		GetMarkerReachedSignal(
			markerName
		):
		Connect(
			function()

				if activeThrowAnimationTrack ~=
					track then

					return
				end


				local pending =
				pendingThrow


				if not pending
					or pending.AnimationVariant ~=
					variant then

					return
				end


				firePendingThrowAtRelease(
					pending.Generation,
					"Marker:"
					.. variant
					.. ":"
					.. markerName
				)
			end
		)
end


for _,
	markerName in ipairs(
		{
			"release",
			"Release",
		}
	) do

	connectReleaseMarker(
		normalThrowAnimationTrack,
		markerName,
		"Normal"
	)

	connectReleaseMarker(
		sprintThrowAnimationTrack,
		markerName,
		"Sprint"
	)
end


local function switchThrowAnimationForSprintState()

	local pending =
		pendingThrow


	local currentTrack =
		activeThrowAnimationTrack


	if not pending
		or not currentTrack
		or not currentTrack.IsPlaying then

		return
	end


	local desiredTrack,
		desiredVariant =
		getThrowTrackForCurrentMovement()


	if not desiredTrack
		or desiredTrack ==
		currentTrack
		or pending.AnimationVariant ==
		desiredVariant then

		return
	end


	local currentTime =
		currentTrack.TimePosition


	-- Start the destination track on the SAME point of the source timeline.
	-- Play() first so TimePosition is writable on a live AnimationTrack.
	local playbackSpeed =
		pending.PlaybackSpeed
		or NORMAL_THROW_ANIMATION_SPEED


	desiredTrack:
		Play(
			THROW_VARIANT_CROSSFADE,
			1,
			playbackSpeed
		)


	if desiredTrack.Length > 0 then

		desiredTrack.TimePosition =
			math.clamp(
				currentTime,
				0,
				math.max(
					0,
					desiredTrack.Length
					- 0.001
				)
			)

	else

		desiredTrack.TimePosition =
			math.max(
				0,
				currentTime
			)
	end


	-- Make the destination authoritative BEFORE fading the previous track.
	-- Marker callbacks from the previous track are ignored immediately.
	activeThrowAnimationTrack =
		desiredTrack

	pending.AnimationVariant =
		desiredVariant


	currentTrack:
		Stop(
			THROW_VARIANT_CROSSFADE
		)


	if DEBUG_THROWABLE then

		print(
			"[ThrowableController] THROW VARIANT CROSSFADE",
			"to=",
			desiredVariant,
			"time=",
			string.format(
				"%.3f",
				currentTime
			)
		)
	end
end

-- =========================
-- NINJA BAG PROTOTYPE UI
-- =========================

local COLOR_PANEL =
	Color3.fromRGB(
		14,
		14,
		16
	)

local COLOR_PANEL_SOFT =
	Color3.fromRGB(
		22,
		22,
		25
	)

local COLOR_GOLD =
	Color3.fromRGB(
		190,
		151,
		76
	)

local COLOR_GOLD_DIM =
	Color3.fromRGB(
		116,
		92,
		50
	)

local COLOR_RED =
	Color3.fromRGB(
		148,
		47,
		42
	)

local COLOR_TEXT =
	Color3.fromRGB(
		232,
		228,
		216
	)

local COLOR_TEXT_DIM =
	Color3.fromRGB(
		145,
		141,
		132
	)

local COLOR_LOCKED =
	Color3.fromRGB(
		72,
		72,
		76
	)


local SLOT_POSITIONS = {
	[1] =
		UDim2.fromScale(
			0.50,
			0.13
		),

	[2] =
		UDim2.fromScale(
			0.87,
			0.50
		),

	[3] =
		UDim2.fromScale(
			0.50,
			0.87
		),

	[4] =
		UDim2.fromScale(
			0.13,
			0.50
		),
}


local function addCorner(
	parent: Instance,
	radius: UDim
)

	local corner =
		Instance.new(
			"UICorner"
		)

	corner.CornerRadius =
		radius

	corner.Parent =
		parent
end


local function addStroke(
	parent: Instance,
	color: Color3,
	transparency: number,
	thickness: number
): UIStroke

	local stroke =
		Instance.new(
			"UIStroke"
		)

	stroke.ApplyStrokeMode =
		Enum.ApplyStrokeMode.Border

	stroke.Color =
		color

	stroke.Transparency =
		transparency

	stroke.Thickness =
		thickness

	stroke.Parent =
		parent


	return stroke
end


local function createTextLabel(
	parent: Instance,
	name: string,
	textValue: string,
	position: UDim2,
	size: UDim2,
	font: Enum.Font,
	textSize: number,
	color: Color3,
	xAlignment: Enum.TextXAlignment
): TextLabel

	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		name

	label.BackgroundTransparency =
		1

	label.Position =
		position

	label.Size =
		size

	label.Font =
		font

	label.Text =
		textValue

	label.TextSize =
		textSize

	label.TextColor3 =
		color

	label.TextTransparency =
		0

	label.TextXAlignment =
		xAlignment

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	label.TextTruncate =
		Enum.TextTruncate.AtEnd

	label.Parent =
		parent


	return label
end


local function updateSelectedIndicator()

	if not selectedIndicator
		or not selectedIndicatorName
		or not selectedIndicatorAmount then

		return
	end


	local projectileType =
		getSlotProjectile(
			selectedSlot
		)


	local displayName,
		_subtitle =
		getProjectilePresentation(
			projectileType
		)


	local amount =
		getProjectileAmount(
			projectileType
		)


	if selectedIndicatorCategory then

		selectedIndicatorCategory.Text =
			"SLOT "
			.. string.format(
				"%02d",
				selectedSlot
			)
			.. "  •  LANZABLE"
	end


	selectedIndicatorName.Text =
		displayName


	selectedIndicatorAmount.Text =
		if projectileType
		then string.format(
			"×%02d",
			amount
		)
		else "--"


	selectedIndicatorAmount.TextColor3 =
		if projectileType
		and amount <= 0
		then COLOR_RED
		else COLOR_GOLD


	-- Keep the normal HUD quiet outside Combat Mode.
	selectedIndicator.Visible =
		character:GetAttribute(
			"CombatMode"
		) == true
end


local function updateSlotVisuals(
	highlighted: number?
)

	for slotIndex = 1,
		NINJA_BAG_SLOT_COUNT do

		local frame =
			slotFrames[
		slotIndex
		]


		if not frame then
			continue
		end


		local projectileType =
			getSlotProjectile(
				slotIndex
			)


		local displayName,
			subtitle =
			getProjectilePresentation(
				projectileType
			)


		local amount =
			getProjectileAmount(
				projectileType
			)


		local isEmpty =
			projectileType == nil


		local isDepleted =
			not isEmpty
			and amount <= 0


		local stroke =
			slotStrokes[
		slotIndex
		]


		local accent =
			slotAccentBars[
		slotIndex
		]


		local isHighlighted =
			slotIndex ==
			highlighted


		local isCurrent =
			slotIndex ==
			selectedSlot


		local indexLabel =
			slotIndexLabels[
		slotIndex
		]


		local nameLabel =
			slotNameLabels[
		slotIndex
		]


		local subtitleLabel =
			slotSubtitleLabels[
		slotIndex
		]


		local amountLabel =
			slotAmountLabels[
		slotIndex
		]


		if indexLabel then

			indexLabel.Text =
				"SLOT "
				.. string.format(
					"%02d",
					slotIndex
				)
		end


		if nameLabel then

			nameLabel.Text =
				displayName


			nameLabel.TextColor3 =
				if isEmpty
				or isDepleted
				then COLOR_TEXT_DIM
				else COLOR_TEXT
		end


		if subtitleLabel then

			subtitleLabel.Text =
				if isDepleted
				then "AGOTADO"
				else subtitle


			subtitleLabel.TextColor3 =
				if isDepleted
				then COLOR_RED
				else COLOR_TEXT_DIM
		end


		if amountLabel then

			amountLabel.Text =
				if isEmpty
				then "--"
				else string.format(
					"×%02d",
					amount
				)


			amountLabel.TextColor3 =
				if isDepleted
				then COLOR_RED
				elseif isEmpty
				then COLOR_TEXT_DIM
				else COLOR_GOLD
		end


		if isHighlighted then

			frame.BackgroundColor3 =
				COLOR_PANEL_SOFT

			frame.BackgroundTransparency =
				0.08


			stroke.Color =
				if isDepleted
				or isEmpty
				then COLOR_RED
				else COLOR_GOLD


			stroke.Transparency =
				0


			stroke.Thickness =
				2.2


			accent.BackgroundColor3 =
				COLOR_RED


			accent.BackgroundTransparency =
				0


		elseif isCurrent then

			frame.BackgroundColor3 =
				COLOR_PANEL_SOFT

			frame.BackgroundTransparency =
				0.16


			stroke.Color =
				if isDepleted
				or isEmpty
				then COLOR_RED
				else COLOR_GOLD


			stroke.Transparency =
				0.22


			stroke.Thickness =
				1.4


			accent.BackgroundColor3 =
				if isDepleted
				or isEmpty
				then COLOR_RED
				else COLOR_GOLD


			accent.BackgroundTransparency =
				0.18


		else

			frame.BackgroundColor3 =
				COLOR_PANEL

			frame.BackgroundTransparency =
				0.28


			stroke.Color =
				if isDepleted
				or isEmpty
				then COLOR_LOCKED
				else COLOR_GOLD_DIM


			stroke.Transparency =
				0.52


			stroke.Thickness =
				1


			accent.BackgroundColor3 =
				if isDepleted
				or isEmpty
				then COLOR_RED
				else COLOR_GOLD_DIM


			accent.BackgroundTransparency =
				0.58
		end
	end


	if centerSelectedLabel then

		local centerSlot =
			highlighted
			or selectedSlot


		local projectileType =
			getSlotProjectile(
				centerSlot
			)


		local displayName =
			select(
				1,
				getProjectilePresentation(
					projectileType
				)
			)


		local amount =
			getProjectileAmount(
				projectileType
			)


		centerSelectedLabel.Text =
			if projectileType
			then displayName
			.. " "
			.. string.format(
				"×%02d",
				amount
			)
			else "SLOT VACÍO"


		centerSelectedLabel.TextColor3 =
			if projectileType
			and amount > 0
			then COLOR_TEXT
			else COLOR_RED
	end
end


local function createSlot(
	parent: Frame,
	slotIndex: number
)

	local definition =
		SLOT_DEFINITIONS[
	slotIndex
	]


	local projectileType =
		getSlotProjectile(
			slotIndex
		)


	local displayName,
		subtitle =
		getProjectilePresentation(
			projectileType
		)


	local amount =
		getProjectileAmount(
			projectileType
		)


	local frame =
		Instance.new(
			"Frame"
		)


	frame.Name =
		"Slot_"
		.. tostring(
			slotIndex
		)


	frame.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)


	frame.Position =
		SLOT_POSITIONS[
	slotIndex
	]


	frame.Size =
		UDim2.fromOffset(
			142,
			64
		)


	frame.BackgroundColor3 =
		COLOR_PANEL


	frame.BackgroundTransparency =
		0.28


	frame.BorderSizePixel =
		0


	frame.Parent =
		parent


	addCorner(
		frame,
		UDim.new(
			0,
			5
		)
	)


	local stroke =
		addStroke(
			frame,
			COLOR_GOLD_DIM,
			0.52,
			1
		)


	local accent =
		Instance.new(
			"Frame"
		)


	accent.Name =
		"Accent"


	accent.Size =
		UDim2.new(
			0,
			3,
			1,
			0
		)


	accent.BackgroundColor3 =
		COLOR_GOLD_DIM


	accent.BackgroundTransparency =
		0.58


	accent.BorderSizePixel =
		0


	accent.Parent =
		frame


	addCorner(
		accent,
		UDim.new(
			0,
			4
		)
	)


	slotIndexLabels[
	slotIndex
	] =
		createTextLabel(
			frame,
			"Index",
			"SLOT "
			.. definition.Index,
			UDim2.fromOffset(
				12,
				4
			),
			UDim2.fromOffset(
				64,
				14
			),
			Enum.Font.GothamMedium,
			9,
			COLOR_GOLD,
			Enum.TextXAlignment.Left
		)


	slotNameLabels[
	slotIndex
	] =
		createTextLabel(
			frame,
			"Name",
			displayName,
			UDim2.fromOffset(
				12,
				18
			),
			UDim2.new(
				1,
				-62,
				0,
				22
			),
			Enum.Font.GothamBold,
			13,
			COLOR_TEXT,
			Enum.TextXAlignment.Left
		)


	slotAmountLabels[
	slotIndex
	] =
		createTextLabel(
			frame,
			"Amount",
			if projectileType
			then string.format(
				"×%02d",
				amount
			)
			else "--",
			UDim2.new(
				1,
				-50,
				0,
				18
			),
			UDim2.fromOffset(
				38,
				22
			),
			Enum.Font.GothamBold,
			12,
			COLOR_GOLD,
			Enum.TextXAlignment.Right
		)


	slotSubtitleLabels[
	slotIndex
	] =
		createTextLabel(
			frame,
			"Subtitle",
			subtitle,
			UDim2.fromOffset(
				12,
				42
			),
			UDim2.new(
				1,
				-20,
				0,
				15
			),
			Enum.Font.GothamMedium,
			8,
			COLOR_TEXT_DIM,
			Enum.TextXAlignment.Left
		)


	slotFrames[
	slotIndex
	] =
		frame


	slotStrokes[
	slotIndex
	] =
		stroke


	slotAccentBars[
	slotIndex
	] =
		accent
end


local function createNinjaBagUI()

	local playerGui =
		player:
		WaitForChild(
			"PlayerGui"
		)


	local oldGui =
		playerGui:
		FindFirstChild(
			"NinjaBagPrototypeUI"
		)


	if oldGui then

		oldGui:
			Destroy()
	end


	local gui =
		Instance.new(
			"ScreenGui"
		)


	gui.Name =
		"NinjaBagPrototypeUI"


	gui.ResetOnSpawn =
		true


	gui.IgnoreGuiInset =
		true


	gui.DisplayOrder =
		80


	gui.ZIndexBehavior =
		Enum.ZIndexBehavior.Sibling


	gui.Parent =
		playerGui


	ninjaBagGui =
		gui


	-- ---------------------------------------------------------
	-- Compact selected throwable HUD
	-- ---------------------------------------------------------

	local indicator =
		Instance.new(
			"Frame"
		)


	indicator.Name =
		"SelectedThrowable"


	indicator.AnchorPoint =
		Vector2.new(
			1,
			1
		)


	indicator.Position =
		UDim2.new(
			1,
			-30,
			1,
			-72
		)


	indicator.Size =
		UDim2.fromOffset(
			194,
			44
		)


	indicator.BackgroundColor3 =
		COLOR_PANEL


	indicator.BackgroundTransparency =
		0.18


	indicator.BorderSizePixel =
		0


	indicator.Parent =
		gui


	addCorner(
		indicator,
		UDim.new(
			0,
			5
		)
	)


	addStroke(
		indicator,
		COLOR_GOLD_DIM,
		0.38,
		1
	)


	local indicatorAccent =
		Instance.new(
			"Frame"
		)


	indicatorAccent.Name =
		"Accent"


	indicatorAccent.Size =
		UDim2.new(
			0,
			3,
			1,
			0
		)


	indicatorAccent.BackgroundColor3 =
		COLOR_RED


	indicatorAccent.BackgroundTransparency =
		0.06


	indicatorAccent.BorderSizePixel =
		0


	indicatorAccent.Parent =
		indicator


	addCorner(
		indicatorAccent,
		UDim.new(
			0,
			4
		)
	)


	selectedIndicatorCategory =
		createTextLabel(
			indicator,
			"Category",
			"SLOT 01  •  LANZABLE",
			UDim2.fromOffset(
				12,
				4
			),
			UDim2.fromOffset(
				118,
				14
			),
			Enum.Font.GothamMedium,
			9,
			COLOR_TEXT_DIM,
			Enum.TextXAlignment.Left
		)


	selectedIndicatorName =
		createTextLabel(
			indicator,
			"SelectedName",
			"KUNAI",
			UDim2.fromOffset(
				12,
				17
			),
			UDim2.new(
				1,
				-100,
				0,
				22
			),
			Enum.Font.GothamBold,
			14,
			COLOR_TEXT,
			Enum.TextXAlignment.Left
		)


	selectedIndicatorAmount =
		createTextLabel(
			indicator,
			"SelectedAmount",
			"×20",
			UDim2.new(
				1,
				-78,
				0,
				17
			),
			UDim2.fromOffset(
				38,
				22
			),
			Enum.Font.GothamBold,
			12,
			COLOR_GOLD,
			Enum.TextXAlignment.Right
		)


	local keyFrame =
		Instance.new(
			"Frame"
		)


	keyFrame.Name =
		"Key"


	keyFrame.AnchorPoint =
		Vector2.new(
			1,
			0.5
		)


	keyFrame.Position =
		UDim2.new(
			1,
			-8,
			0.5,
			0
		)


	keyFrame.Size =
		UDim2.fromOffset(
			29,
			28
		)


	keyFrame.BackgroundColor3 =
		COLOR_PANEL_SOFT


	keyFrame.BackgroundTransparency =
		0.04


	keyFrame.BorderSizePixel =
		0


	keyFrame.Parent =
		indicator


	addCorner(
		keyFrame,
		UDim.new(
			0,
			4
		)
	)


	addStroke(
		keyFrame,
		COLOR_GOLD,
		0.16,
		1
	)


	createTextLabel(
		keyFrame,
		"KeyText",
		"G",
		UDim2.fromScale(
			0,
			0
		),
		UDim2.fromScale(
			1,
			1
		),
		Enum.Font.GothamBold,
		14,
		COLOR_GOLD,
		Enum.TextXAlignment.Center
	)


	selectedIndicator =
		indicator


	-- ---------------------------------------------------------
	-- Radial overlay
	-- ---------------------------------------------------------

	local dim =
		Instance.new(
			"Frame"
		)


	dim.Name =
		"Dim"


	dim.Size =
		UDim2.fromScale(
			1,
			1
		)


	dim.BackgroundColor3 =
		Color3.new(
			0,
			0,
			0
		)


	dim.BackgroundTransparency =
		1


	dim.BorderSizePixel =
		0


	dim.Visible =
		false


	dim.Parent =
		gui


	radialDim =
		dim


	local root =
		Instance.new(
			"Frame"
		)


	root.Name =
		"RadialRoot"


	root.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)


	root.Position =
		UDim2.fromScale(
			0.5,
			0.5
		)


	root.Size =
		UDim2.fromOffset(
			392,
			392
		)


	root.BackgroundTransparency =
		1


	root.Visible =
		false


	root.Parent =
		dim


	radialRoot =
		root


	local scale =
		Instance.new(
			"UIScale"
		)


	scale.Scale =
		0.92


	scale.Parent =
		root


	radialScale =
		scale


	local ring =
		Instance.new(
			"Frame"
		)


	ring.Name =
		"Ring"


	ring.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)


	ring.Position =
		UDim2.fromScale(
			0.5,
			0.5
		)


	ring.Size =
		UDim2.fromOffset(
			258,
			258
		)


	ring.BackgroundColor3 =
		COLOR_PANEL


	ring.BackgroundTransparency =
		0.62


	ring.BorderSizePixel =
		0


	ring.Parent =
		root


	addCorner(
		ring,
		UDim.new(
			1,
			0
		)
	)


	addStroke(
		ring,
		COLOR_GOLD_DIM,
		0.72,
		1
	)


	local center =
		Instance.new(
			"Frame"
		)


	center.Name =
		"Center"


	center.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)


	center.Position =
		UDim2.fromScale(
			0.5,
			0.5
		)


	center.Size =
		UDim2.fromOffset(
			104,
			104
		)


	center.BackgroundColor3 =
		COLOR_PANEL


	center.BackgroundTransparency =
		0.08


	center.BorderSizePixel =
		0


	center.Parent =
		root


	addCorner(
		center,
		UDim.new(
			1,
			0
		)
	)


	addStroke(
		center,
		COLOR_GOLD,
		0.26,
		1.2
	)


	createTextLabel(
		center,
		"Title",
		"NINJA BAG",
		UDim2.fromOffset(
			7,
			19
		),
		UDim2.new(
			1,
			-14,
			0,
			20
		),
		Enum.Font.GothamBold,
		12,
		COLOR_GOLD,
		Enum.TextXAlignment.Center
	)


	centerSelectedLabel =
		createTextLabel(
			center,
			"Current",
			"KUNAI",
			UDim2.fromOffset(
				7,
				42
			),
			UDim2.new(
				1,
				-14,
				0,
				22
			),
			Enum.Font.GothamBold,
			13,
			COLOR_TEXT,
			Enum.TextXAlignment.Center
		)


	createTextLabel(
		center,
		"Hint",
		"SUELTA G",
		UDim2.fromOffset(
			7,
			69
		),
		UDim2.new(
			1,
			-14,
			0,
			14
		),
		Enum.Font.GothamMedium,
		8,
		COLOR_TEXT_DIM,
		Enum.TextXAlignment.Center
	)


	local centerAccent =
		Instance.new(
			"Frame"
		)


	centerAccent.Name =
		"Accent"


	centerAccent.AnchorPoint =
		Vector2.new(
			0.5,
			0
		)


	centerAccent.Position =
		UDim2.new(
			0.5,
			0,
			0,
			8
		)


	centerAccent.Size =
		UDim2.fromOffset(
			24,
			2
		)


	centerAccent.BackgroundColor3 =
		COLOR_RED


	centerAccent.BackgroundTransparency =
		0.05


	centerAccent.BorderSizePixel =
		0


	centerAccent.Parent =
		center


	for slotIndex = 1,
		NINJA_BAG_SLOT_COUNT do

		createSlot(
			root,
			slotIndex
		)
	end


	updateSelectedIndicator()


	updateSlotVisuals(
		selectedSlot
	)
end


local function getMousePositionInViewport(): Vector2

	local topLeftInset =
		select(
			1,
			GuiService:
			GetGuiInset()
		)


	return UserInputService:
		GetMouseLocation()
	- topLeftInset
end


local function getRadialHoveredSlot(): number?

	local camera =
		workspace.CurrentCamera


	if not camera then
		return nil
	end


	local mouse =
		getMousePositionInViewport()


	local center =
		camera.ViewportSize
		* 0.5


	local delta =
		mouse
	- center


	if delta.Magnitude <
		NINJA_BAG_DEADZONE then

		return nil
	end


	local angle =
		math.deg(
			math.atan2(
				delta.Y,
				delta.X
			)
		)


	if angle >= -45
		and angle < 45 then

		return 2
	end


	if angle >= 45
		and angle < 135 then

		return 3
	end


	if angle >= -135
		and angle < -45 then

		return 1
	end


	return 4
end


local function restoreMouseState()

	UserInputService.MouseBehavior =
		previousMouseBehavior


	UserInputService.MouseIconEnabled =
		previousMouseIconEnabled
end


local function openNinjaBag()

	if radialOpen then
		return
	end


	if not radialDim
		or not radialRoot
		or not radialScale then

		return
	end


	radialOpen =
		true


	hoveredSlot =
		selectedSlot


	previousMouseBehavior =
		UserInputService.MouseBehavior


	previousMouseIconEnabled =
		UserInputService.MouseIconEnabled


	UserInputService.MouseBehavior =
		Enum.MouseBehavior.Default


	UserInputService.MouseIconEnabled =
		true


	radialDim.Visible =
		true


	radialRoot.Visible =
		true


	radialDim.BackgroundTransparency =
		1


	radialScale.Scale =
		0.92


	updateSlotVisuals(
		selectedSlot
	)


	TweenService:
		Create(
			radialDim,
			TweenInfo.new(
				0.10,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				BackgroundTransparency =
				0.90,
			}
		):
		Play()


	TweenService:
		Create(
			radialScale,
			TweenInfo.new(
				0.11,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Scale =
				1,
			}
		):
		Play()
end


local function closeNinjaBag(
	commitSelection: boolean
)

	if not radialOpen then
		return
	end


	if commitSelection
		and hoveredSlot
		and hoveredSlot >= 1
		and hoveredSlot <=
		NINJA_BAG_SLOT_COUNT then

		selectedSlot =
			hoveredSlot


		player:SetAttribute(
			"NinjaBagSelectedSlot",
			selectedSlot
		)
	end


	radialOpen =
		false


	updateSelectedIndicator()


	updateSlotVisuals(
		selectedSlot
	)


	restoreMouseState()


	if radialDim
		and radialRoot
		and radialScale then

		local closingDim =
			radialDim


		local closingRoot =
			radialRoot


		local closingScale =
			radialScale


		TweenService:
			Create(
				closingDim,
				TweenInfo.new(
					0.08,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					BackgroundTransparency =
					1,
				}
			):
			Play()


		TweenService:
			Create(
				closingScale,
				TweenInfo.new(
					0.08,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					Scale =
					0.96,
				}
			):
			Play()


		task.delay(
			0.085,
			function()

				if not radialOpen
					and closingDim.Parent
					and closingRoot.Parent then

					closingRoot.Visible =
						false


					closingDim.Visible =
						false
				end
			end
		)
	end
end


local function canOpenNinjaBag(): boolean

	if player:GetAttribute(
		"NinjaBagLoadoutOpen"
		) == true then

		return false
	end


	if humanoid.Health <= 0
		or not rootPart.Parent then

		return false
	end


	if character:GetAttribute(
		"DownedActionLocked"
		) == true
			or character:GetAttribute(
				"IsDowned"
			) == true
			or character:GetAttribute(
				"IsCarried"
			) == true
			or character:GetAttribute(
				"IsExecuting"
			) == true then

		return false
	end


	return true
end


RunService.RenderStepped:
	Connect(
		function()

			if not radialOpen then
				return
			end


			-- Combat camera/crosshair systems can attempt to lock the cursor.
			-- While choosing a throwable, the Ninja Bag owns mouse mode.
			UserInputService.MouseBehavior =
			Enum.MouseBehavior.Default


			UserInputService.MouseIconEnabled =
			true


			local newHovered =
			getRadialHoveredSlot()


			if newHovered ~=
				hoveredSlot then

				hoveredSlot =
				newHovered


				updateSlotVisuals(
					hoveredSlot
					or selectedSlot
				)
			end
		end
	)

-- =========================
-- G TAP / HOLD INPUT
-- =========================

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)

			if gameProcessed then
				return
			end


			if UserInputService:
				GetFocusedTextBox() then

				return
			end


			if input.UserInputType ~=
				Enum.UserInputType.Keyboard
				or input.KeyCode ~=
				NINJA_BAG_KEY then

				return
			end


			if ninjaBagKeyDown then
				return
			end


			if not canOpenNinjaBag() then
				return
			end


			ninjaBagKeyDown =
			true


			ninjaBagPressedAt =
			time()


			ninjaBagPressGeneration +=
			1


			local generation =
			ninjaBagPressGeneration


			task.delay(
				NINJA_BAG_HOLD_TIME,
				function()

					if not ninjaBagKeyDown
						or generation ~=
						ninjaBagPressGeneration then

						return
					end


					openNinjaBag()
				end
			)
		end
	)


UserInputService.InputEnded:
	Connect(
		function(
			input: InputObject,
			_gameProcessed: boolean
		)

			if input.UserInputType ~=
				Enum.UserInputType.Keyboard
				or input.KeyCode ~=
				NINJA_BAG_KEY then

				return
			end


			if not ninjaBagKeyDown then
				return
			end


			ninjaBagKeyDown =
			false


			ninjaBagPressGeneration +=
			1


			local heldFor =
			time()
			- ninjaBagPressedAt


			if radialOpen then

				closeNinjaBag(
					true
				)


				return
			end


			if heldFor <
				NINJA_BAG_HOLD_TIME then

				beginAnimatedThrow(
					selectedSlot
				)
			end
		end
	)


createNinjaBagUI()


local function refreshNinjaBagUI()

	updateSelectedIndicator()


	updateSlotVisuals(
		hoveredSlot
			or selectedSlot
	)
end


player:GetAttributeChangedSignal(
	"NinjaBagLoadoutOpen"
):
	Connect(
		function()

			if player:GetAttribute(
				"NinjaBagLoadoutOpen"
				) == true then

				ninjaBagKeyDown =
				false


				ninjaBagPressGeneration +=
				1


				closeNinjaBag(
					false
				)
			end
		end
	)


for slotIndex = 1,
	NINJA_BAG_SLOT_COUNT do

	player:GetAttributeChangedSignal(
		slotProjectileAttribute(
			slotIndex
		)
	):
		Connect(
			refreshNinjaBagUI
		)
end


for projectileType in pairs(
	ProjectileConfigs
	) do

	player:GetAttributeChangedSignal(
		amountAttribute(
			projectileType
		)
	):
		Connect(
			refreshNinjaBagUI
		)


	player:GetAttributeChangedSignal(
		maxAmountAttribute(
			projectileType
		)
	):
		Connect(
			refreshNinjaBagUI
		)
end

-- =========================
-- COMBAT MIRROR / CANCELLATION
-- =========================

character:GetAttributeChangedSignal(
	"IsSprinting"
):
	Connect(
		function()

			switchThrowAnimationForSprintState()
		end
	)


character:GetAttributeChangedSignal(
	"CombatMode"
):
	Connect(
		function()

			syncCombatMode()


			updateSelectedIndicator()


			if character:GetAttribute(
				"CombatMode"
				) ~= true then

				cancelThrowState()


				closeNinjaBag(
					false
				)
			end
		end
	)


character:GetAttributeChangedSignal(
	"CombatSuppressed"
):
	Connect(
		function()

			if character:GetAttribute(
				"CombatSuppressed"
				) == true then

				cancelThrowState()


				closeNinjaBag(
					false
				)
			end
		end
	)


character:GetAttributeChangedSignal(
	"IsDashing"
):
	Connect(
		function()

			if character:GetAttribute(
				"IsDashing"
				) == true then

				cancelThrowState()


				closeNinjaBag(
					false
				)
			end
		end
	)


for _, statusBlockAttribute in ipairs({
	"IsStunned",
	"Status_AttackBlocked",
	"Status_Stunned",
	}) do
	character:GetAttributeChangedSignal(
		statusBlockAttribute
	):
		Connect(
			function()

				if character:GetAttribute(
					statusBlockAttribute
					) == true then

					cancelThrowState()


					closeNinjaBag(
						false
					)
				end
			end
		)
end


humanoid.Died:
	Connect(
		function()

			cancelThrowState()


			closeNinjaBag(
				false
			)
		end
	)


script.Destroying:
	Connect(
		function()

			cancelThrowState()


			closeNinjaBag(
				false
			)


			normalThrowAnimation:
			Destroy()

			sprintThrowAnimation:
			Destroy()
		end
	)


task.defer(
	syncCombatMode
)


print(
	"[ThrowableController] READY v3.7 StatusCombatGate + CombatCounterPriority + FastDefensiveThrow"
		.. " | TAP G=Throw Selected"
		.. " | HOLD G=Radial"
		.. " | Default=Kunai"
		.. " | R untouched"
		.. " | OffCombat G=DefenseOnly"
		.. " | ThrowNormal=85810196265540"
		.. " | ThrowSprint=121774304926898"
		.. " | DynamicSprintBlend=ON"
		.. " | BlendTime=0.07"
		.. " | DefensivePreflight=ON"
		.. " | CombatCounterPriority=ON"
		.. " | NormalSpeed=1.25"
		.. " | DefensiveSpeed=3.0"
		.. " | NormalRelease=0.533"
		.. " | DefensiveRelease=0.222"
		.. " | Release=Frame40"
		.. " | ThrowHand=Left"
		.. " | CounterAutoCombat=ON"
)
