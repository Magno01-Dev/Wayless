--!strict
-- StarterPlayer > StarterPlayerScripts > JutsuController
--
-- Animated Cast Transport + Technique Loadout Input + Bulk Katon + Suiton + Futon + Raiton + Doton
--
-- Technique Slots:
--   1 2 3 4 5 6 7 8 9 0
--
-- Each key resolves TechniqueLoadoutSlot_<N> dynamically.
-- No technique IDs are hardcoded to gameplay hotkeys.
--
-- Compatible con:
--
-- JutsuAnimatedRequest
-- JutsuAnimatedMarker
-- JutsuAnimatedSFX
-- ProjectileSkillshotPolicy

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local UserInputService =
	game:GetService("UserInputService")

local ContextActionService =
	game:GetService("ContextActionService")

local player =
	Players.LocalPlayer

---------------------------------------------------------------------
-- JUTSU SYSTEM
---------------------------------------------------------------------

local jutsuSystem =
	ReplicatedStorage:
	WaitForChild(
		"JutsuSystem"
	)

local shared =
	jutsuSystem:
	WaitForChild(
		"Shared"
	)

local definitions =
	require(
		shared:
		WaitForChild(
			"JutsuDefinitions"
		)
	)

local ProjectileSkillshotPolicy =
	require(
		shared:
		WaitForChild(
			"ProjectileSkillshotPolicy"
		)
	)

local remotes =
	jutsuSystem:
	WaitForChild(
		"Remotes"
	)

local animatedRequest =
	remotes:
	WaitForChild(
		"JutsuAnimatedRequest"
	) :: RemoteFunction

local animatedMarker =
	remotes:
	WaitForChild(
		"JutsuAnimatedMarker"
	) :: RemoteEvent

local animatedSFX =
	remotes:
	WaitForChild(
		"JutsuAnimatedSFX"
	) :: RemoteEvent

---------------------------------------------------------------------
-- SHARED ANIMATIONS
---------------------------------------------------------------------

local HAND_SIGN_ANIMATIONS = {
	Low =
		"rbxassetid://109122450412662",

	Medium =
		"rbxassetid://112260201062309",

	High =
		"rbxassetid://80789406734721",
}

local RELEASE_MARKERS = {
	ReleaseStart =
		"ReleaseStart",

	ProjectileSpawn =
		"ProjectileSpawn",

	RecoveryStart =
		"RecoveryStart",

	CastEnd =
		"CastEnd",
}

---------------------------------------------------------------------
-- ANIMATION DEFINITIONS
---------------------------------------------------------------------

local animationDefinitions = {

	-----------------------------------------------------------------
	-- FIREBALL
	-----------------------------------------------------------------

	Fireball = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- HOSENKA
	--
	-- Temporalmente usa las mismas animaciones que Fireball.
	-----------------------------------------------------------------

	Hosenka = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- FLAME BREATH
	-- Bulk gameplay pass: temporary Fireball animation set.
	-----------------------------------------------------------------

	FlameBreath = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- FLAME WAVE
	-- Bulk gameplay pass: temporary Fireball animation set.
	-----------------------------------------------------------------

	FlameWave = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- WATER BULLET
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterBullet = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WATER WAVE
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterWave = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WATER WHIP
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterWhip = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WATER PRISON
	-- Bulk gameplay pass: temporary shared release animation set.
	-----------------------------------------------------------------

	WaterPrison = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- AIR BULLET
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	AirBullet = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WIND BLADE
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	WindBlade = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- GALE PALM
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	GalePalm = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- WIND SWEEP
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	WindSweep = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- LIGHTNING BOLT
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	LightningBolt = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- LIGHTNING STREAM
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	LightningStream = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- STATIC BURST
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	StaticBurst = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- LIGHTNING SENBON
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	LightningSenbon = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
	-----------------------------------------------------------------
	-- STONE SHOT
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	StoneShot = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- EARTH WALL
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	EarthWall = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- EARTH SPIKES
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	EarthSpikes = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},

	-----------------------------------------------------------------
	-- EARTH TREMOR
	-- Bulk gameplay pass: temporary Fireball release animation.
	-----------------------------------------------------------------

	EarthTremor = {
		HandSigns = {
			"Medium",
			"High",
			"Low",
		},

		HandSignAnimations =
			HAND_SIGN_ANIMATIONS,

		HandSignPriority =
			Enum.AnimationPriority.Action,

		HandSignPlaybackSpeed =
			0.55,

		HandSignFadeTime =
			0.04,

		HandSignFallbackDuration =
			0.30,

		HandSignMinCadence =
			0.38,

		ReleaseAnimation =
			"rbxassetid://72456181450753",

		ReleasePriority =
			Enum.AnimationPriority.Action,

		ReleasePlaybackSpeed =
			1.0,

		ReleaseFadeTime =
			0.04,

		ReleaseMarkers =
			RELEASE_MARKERS,
	},
}

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local animationGeneration =
	0

local requestBusy =
	false

---------------------------------------------------------------------
-- COMBAT MODE
---------------------------------------------------------------------

local function enterCombatMode(
	character: Model,
	source: string
)
	local request =
		character:
		FindFirstChild(
			"CombatModeRequest"
		)

	if request
		and request:IsA(
			"BindableEvent"
		) then

		request:Fire(
			"Enter",
			source
		)
	end
end

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local function getAimDirection(
	character: Model
): Vector3?

	local head =
		character:
		FindFirstChild(
			"Head"
		)

	if not head
		or not head:IsA(
			"BasePart"
		) then

		return nil
	end

	local camera =
		workspace.CurrentCamera

	if not camera then
		return nil
	end

	-----------------------------------------------------------------
	-- CENTER CROSSHAIR
	-----------------------------------------------------------------

	local viewport =
		camera.ViewportSize

	local cameraRay =
		camera:
		ViewportPointToRay(
			viewport.X * 0.5,
			viewport.Y * 0.5
		)

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		character,
	}

	params.IgnoreWater =
		false

	local maxDistance =
		ProjectileSkillshotPolicy
		.CrosshairMaxDistance

	local displacement =
		cameraRay.Direction
		* maxDistance

	local result =
		workspace:Raycast(
			cameraRay.Origin,
			displacement,
			params
		)

	local targetPosition =
		if result
		then result.Position
		else cameraRay.Origin
		+ displacement

	local direction =
		targetPosition
	- head.Position

	if direction.Magnitude <
		0.001 then

		direction =
			camera.CFrame.LookVector
	end

	return direction.Unit
end

---------------------------------------------------------------------
-- ANIMATOR
---------------------------------------------------------------------

local function getAnimator(
	character: Model
): Animator?

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return nil
	end

	local animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)

	if animator then
		return animator
	end

	local found =
		humanoid:
		WaitForChild(
			"Animator",
			2
		)

	if found
		and found:IsA(
			"Animator"
		) then

		return found
	end

	return nil
end

---------------------------------------------------------------------
-- LOAD ANIMATION
---------------------------------------------------------------------

local function loadTrack(
	animator: Animator,
	animationId: string,
	priority: Enum.AnimationPriority
): AnimationTrack?

	local animation =
		Instance.new(
			"Animation"
		)

	animation.AnimationId =
		animationId

	local ok,
		result =
		pcall(
			function()

				return animator:
				LoadAnimation(
					animation
				)
			end
		)

	animation:Destroy()

	if not ok
		or not result then

		warn(
			"[JutsuController] Animation load failed",
			animationId,
			result
		)

		return nil
	end

	local track =
		result :: AnimationTrack

	track.Priority =
		priority

	track.Looped =
		false

	return track
end

---------------------------------------------------------------------
-- PLAY HAND SIGN
---------------------------------------------------------------------

local function playOneShot(
	animator: Animator,
	jutsuId: string,
	animationId: string,
	priority: Enum.AnimationPriority,
	fadeTime: number,
	playbackSpeed: number,
	fallbackDuration: number,
	minCadence: number,
	generation: number,
	token: string
): boolean

	if generation ~=
		animationGeneration then

		return false
	end

	local track =
		loadTrack(
			animator,
			animationId,
			priority
		)

	if not track then
		return false
	end

	local startedAt =
		os.clock()

	-----------------------------------------------------------------
	-- UNIVERSAL HAND SIGN SFX
	-----------------------------------------------------------------

	animatedSFX:FireServer(
		jutsuId,
		token,
		"HandSign"
	)

	local stopped =
		false

	local connection =
		track.Stopped:
		Connect(
			function()

				stopped =
				true
			end
		)

	track:Play(
		fadeTime,
		1,
		playbackSpeed
	)

	-----------------------------------------------------------------
	-- WAIT FOR LENGTH
	-----------------------------------------------------------------

	local lengthDeadline =
		os.clock()
		+ 1

	while track.Length <= 0
		and os.clock() <
		lengthDeadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	local waitTime =
		fallbackDuration

	if track.Length > 0 then

		waitTime =
			track.Length
			/ math.max(
				playbackSpeed,
				0.01
			)
			+ 0.20
	end

	local deadline =
		os.clock()
		+ math.max(
			0.10,
			waitTime
		)

	while not stopped
		and os.clock() <
		deadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	-----------------------------------------------------------------
	-- MINIMUM CADENCE
	-----------------------------------------------------------------

	local cadenceDeadline =
		startedAt
		+ math.max(
			0,
			minCadence
		)

	while os.clock() <
		cadenceDeadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	connection:Disconnect()

	if track.IsPlaying then

		track:Stop(
			fadeTime
		)
	end

	track:Destroy()

	return generation ==
		animationGeneration
end

---------------------------------------------------------------------
-- SEND MARKER
---------------------------------------------------------------------

local function sendMarker(
	jutsuId: string,
	token: string,
	markerName: string,
	generation: number
)
	if generation ~=
		animationGeneration then

		return
	end

	local markerPayload: any? =
		nil

	-----------------------------------------------------------------
	-- REFRESH AIM AT THE ACTUAL RELEASE FRAME
	-----------------------------------------------------------------

	if markerName ==
		"ProjectileSpawn" then

		local character =
			player.Character

		if character
			and character.Parent then

			local freshDirection =
				getAimDirection(
					character
				)

			if freshDirection then

				markerPayload = {
					Direction =
						freshDirection,
				}
			end
		end
	end

	animatedMarker:FireServer(
		jutsuId,
		token,
		markerName,
		markerPayload
	)
end

---------------------------------------------------------------------
-- RELEASE FALLBACK
---------------------------------------------------------------------

local function fallbackRelease(
	jutsuId: string,
	token: string,
	generation: number
)
	sendMarker(
		jutsuId,
		token,
		"ReleaseStart",
		generation
	)

	task.wait(
		0.15
	)

	sendMarker(
		jutsuId,
		token,
		"ProjectileSpawn",
		generation
	)

	sendMarker(
		jutsuId,
		token,
		"RecoveryStart",
		generation
	)

	task.wait(
		0.10
	)

	sendMarker(
		jutsuId,
		token,
		"CastEnd",
		generation
	)
end

---------------------------------------------------------------------
-- RELEASE ANIMATION
---------------------------------------------------------------------

local function playRelease(
	animator: Animator,
	jutsuId: string,
	token: string,
	config: any,
	generation: number
)
	local animationId =
		config.ReleaseAnimation

	if typeof(animationId) ~=
		"string" then

		fallbackRelease(
			jutsuId,
			token,
			generation
		)

		return
	end

	local track =
		loadTrack(
			animator,
			animationId,
			config.ReleasePriority
			or Enum.AnimationPriority.Action
		)

	if not track then

		fallbackRelease(
			jutsuId,
			token,
			generation
		)

		return
	end

	local markerConnections:
		{RBXScriptConnection} =
		{}

	local sent:
		{[string]: boolean} =
		{}

	local function emit(
		semantic: string
	)
		if sent[
			semantic
			] == true then

			return
		end

		sent[
		semantic
		] =
			true

		sendMarker(
			jutsuId,
			token,
			semantic,
			generation
		)
	end

	for semantic,
		authoredName in pairs(
			config.ReleaseMarkers
		) do

		table.insert(
			markerConnections,

			track:
				GetMarkerReachedSignal(
					authoredName
				):
				Connect(
					function()

						emit(
							semantic
						)
					end
				)
		)
	end

	local stopped =
		false

	table.insert(
		markerConnections,

		track.Stopped:
			Connect(
				function()

					stopped =
					true
				end
			)
	)

	track:Play(
		config.ReleaseFadeTime
			or 0.04,
		1,
		config.ReleasePlaybackSpeed
			or 1
	)

	-----------------------------------------------------------------
	-- RELEASE START SAFETY FALLBACK
	-----------------------------------------------------------------

	task.delay(
		0.20,
		function()

			if generation ==
				animationGeneration
				and sent.ReleaseStart
				~= true then

				emit(
					"ReleaseStart"
				)
			end
		end
	)

	-----------------------------------------------------------------
	-- WAIT FOR ANIMATION
	-----------------------------------------------------------------

	local lengthDeadline =
		os.clock()
		+ 1

	while track.Length <= 0
		and os.clock() <
		lengthDeadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	local maxWait =
		if track.Length > 0
		then track.Length
		/ math.max(
			config.ReleasePlaybackSpeed
			or 1,
			0.01
		)
		+ 0.75
		else 2.5

	local deadline =
		os.clock()
		+ maxWait

	while not stopped
		and os.clock() <
		deadline
		and generation ==
		animationGeneration do

		task.wait()
	end

	-----------------------------------------------------------------
	-- MARKER SAFETY FALLBACKS
	-----------------------------------------------------------------

	if generation ==
		animationGeneration then

		if sent.ReleaseStart ~=
			true then

			emit(
				"ReleaseStart"
			)
		end

		if sent.ProjectileSpawn ~=
			true then

			emit(
				"ProjectileSpawn"
			)
		end

		if sent.RecoveryStart ~=
			true then

			emit(
				"RecoveryStart"
			)
		end

		if sent.CastEnd ~=
			true then

			emit(
				"CastEnd"
			)
		end
	end

	for _, connection in ipairs(
		markerConnections
		) do

		connection:Disconnect()
	end

	if track.IsPlaying then

		track:Stop(
			config.ReleaseFadeTime
				or 0.04
		)
	end

	track:Destroy()
end

---------------------------------------------------------------------
-- PLAY COMPLETE CAST
---------------------------------------------------------------------

local function playCastAnimations(
	jutsuId: string,
	token: string
)
	local config =
		animationDefinitions[
	jutsuId
	]

	if typeof(config) ~=
		"table" then

		warn(
			"[JutsuController] Missing animation config:",
			jutsuId
		)

		return
	end

	local character =
		player.Character

	if not character
		or not character.Parent then

		return
	end

	local animator =
		getAnimator(
			character
		)

	animationGeneration +=
		1

	local generation =
		animationGeneration

	if not animator then

		fallbackRelease(
			jutsuId,
			token,
			generation
		)

		return
	end

	-----------------------------------------------------------------
	-- HAND SIGNS
	-----------------------------------------------------------------

	for _, signName in ipairs(
		config.HandSigns
		) do

		if generation ~=
			animationGeneration then

			return
		end

		local animationId =
			config.HandSignAnimations[
		signName
		]

		if typeof(animationId) ==
			"string" then

			local completed =
				playOneShot(
					animator,
					jutsuId,
					animationId,
					config.HandSignPriority
					or Enum.AnimationPriority.Action,
					config.HandSignFadeTime
					or 0.04,
					config.HandSignPlaybackSpeed
					or 1,
					config.HandSignFallbackDuration
					or 0.30,
					config.HandSignMinCadence
					or 0.38,
					generation,
					token
				)

			if not completed then
				break
			end
		end
	end

	if generation ~=
		animationGeneration then

		return
	end

	-----------------------------------------------------------------
	-- END HAND SIGNS SOUND
	-----------------------------------------------------------------

	animatedSFX:FireServer(
		jutsuId,
		token,
		"HandSignsEnd"
	)

	-----------------------------------------------------------------
	-- RELEASE
	-----------------------------------------------------------------

	playRelease(
		animator,
		jutsuId,
		token,
		config,
		generation
	)
end

---------------------------------------------------------------------
-- REQUEST
---------------------------------------------------------------------

local function requestTechniqueSlotCast(
	slotIndex: number
)
	if requestBusy then
		return
	end

	if player:GetAttribute(
		"TechniqueLoadoutReady"
		) ~= true then

		return
	end

	local expectedTechniqueId =
		player:GetAttribute(
			"TechniqueLoadoutSlot_"
			.. tostring(slotIndex)
		)

	if typeof(expectedTechniqueId) ~= "string"
		or expectedTechniqueId == "" then

		return
	end

	-- Local deployment preflight only.
	-- The technique ID is NOT sent to the server.
	-- Bulk jutsus may carry their authoritative gameplay config in Module.Config.
	if typeof(
		animationDefinitions[
		expectedTechniqueId
		]
		) ~= "table" then

		warn(
			"[JutsuController] Jutsu has no animation configuration:",
			expectedTechniqueId
		)

		return
	end

	local character =
		player.Character

	if not character
		or not character.Parent then

		return
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return
	end

	local direction =
		getAimDirection(
			character
		)

	if not direction then
		return
	end

	requestBusy = true

	local invokeOk,
		response =
		pcall(
			function()

				return animatedRequest:
				InvokeServer(
					{
						SlotIndex = slotIndex,
					},
					{
						Direction = direction,
					}
				)
			end
		)

	requestBusy = false

	if not invokeOk then

		warn(
			"[JutsuController] InvokeServer failed for slot:",
			slotIndex,
			response
		)

		return
	end

	if typeof(response) ~= "table" then

		warn(
			"[JutsuController] Invalid response for slot:",
			slotIndex
		)

		return
	end

	if response.Accepted ~= true then

		warn(
			"[JutsuController] REJECTED:",
			"Slot " .. tostring(slotIndex),
			response.Reason
		)

		return
	end

	local jutsuId =
		response.JutsuId

	if typeof(jutsuId) ~= "string"
		or jutsuId == "" then

		warn(
			"[JutsuController] Accepted response missing JutsuId:",
			slotIndex
		)

		return
	end

	if typeof(
		animationDefinitions[
		jutsuId
		]
		) ~= "table" then

		warn(
			"[JutsuController] Server resolved jutsu missing local config:",
			slotIndex,
			jutsuId
		)

		return
	end

	if typeof(
		response.CastToken
		) ~= "string" then

		return
	end

	enterCombatMode(
		character,
		"Jutsu:" .. jutsuId
	)

	task.spawn(
		playCastAnimations,
		jutsuId,
		response.CastToken
	)
end

---------------------------------------------------------------------
-- TECHNIQUE LOADOUT INPUT
---------------------------------------------------------------------

local TECHNIQUE_SLOT_KEYS: {[number]: Enum.KeyCode} = {
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
	[5] = Enum.KeyCode.Five,
	[6] = Enum.KeyCode.Six,
	[7] = Enum.KeyCode.Seven,
	[8] = Enum.KeyCode.Eight,
	[9] = Enum.KeyCode.Nine,
	[10] = Enum.KeyCode.Zero,
}

local TECHNIQUE_INPUT_PRIORITY =
	3000

local function techniqueSlotAttributeName(
	slotIndex: number
): string
	return "TechniqueLoadoutSlot_"
		.. tostring(
			slotIndex
		)
end

local function canUseTechniqueHotkeys(): boolean
	if UserInputService:
		GetFocusedTextBox() then

		return false
	end

	if player:GetAttribute(
		"InventoryOpen"
		) == true then

		return false
	end

	if player:GetAttribute(
		"NinjaBagLoadoutOpen"
		) == true then

		return false
	end

	return true
end

local function requestTechniqueSlot(
	slotIndex: number
)
	task.spawn(
		requestTechniqueSlotCast,
		slotIndex
	)
end

for slotIndex = 1, 10 do
	local boundSlotIndex =
		slotIndex

	local keyCode =
		TECHNIQUE_SLOT_KEYS[
	boundSlotIndex
	]

	local actionName =
		"WAYLESS_TechniqueSlot_"
		.. tostring(
			boundSlotIndex
		)

	ContextActionService:
		BindActionAtPriority(
			actionName,
			function(
				_actionName: string,
				inputState: Enum.UserInputState,
				_inputObject: InputObject
			): Enum.ContextActionResult

				if inputState ~=
					Enum.UserInputState.Begin then

					return Enum.ContextActionResult.Pass
				end

				if not canUseTechniqueHotkeys() then

					return Enum.ContextActionResult.Pass
				end

				requestTechniqueSlot(
					boundSlotIndex
				)

				-- Technique slot keys own 1-0 while gameplay input is active.
				-- This prevents Roblox Backpack hotkeys from also firing.
				return Enum.ContextActionResult.Sink
			end,
			false,
			TECHNIQUE_INPUT_PRIORITY,
			keyCode
		)
end

---------------------------------------------------------------------
-- RESET
---------------------------------------------------------------------

player.CharacterAdded:
	Connect(
		function()

			animationGeneration +=
			1

			requestBusy =
			false
		end
	)

print(
	"[JutsuController] READY v16 BulkDoton"
		.. " | TechniqueSlots=1-0"
		.. " | ClientSends=SlotIndexOnly"
		.. " | ServerResolvesTechnique=ON"
		.. " | HardcodedJutsuKeys=OFF"
		.. " | BulkKaton=FlameBreath+FlameWave"
		.. " | BulkSuiton=WaterBullet+WaterWave+WaterWhip+WaterPrison"
		.. " | BulkFuton=AirBullet+WindBlade+GalePalm+WindSweep"
		.. " | BulkRaiton=LightningBolt+LightningStream+StaticBurst+LightningSenbon"
		.. " | BulkDoton=StoneShot+EarthWall+EarthSpikes+EarthTremor"
		.. " | SharedDefinitionPreflight=OPTIONAL"
		.. " | AnimatedTransport=ON"
		.. " | ReleaseAimRefresh=ON"
)
