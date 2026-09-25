--!strict
-- ServerScriptService > JutsuSystem > JutsuServer
--
-- v11 Slot-Authoritative Technique Transport + Loadout Gate
--
-- IMPORTANT:
-- KMZ's existing JutsuRequest/JutsuResult/JutsuVFX remotes are preserved.
-- Animated casts use isolated transport:
--
--   JutsuAnimatedRequest : RemoteFunction
--   JutsuAnimatedMarker  : RemoteEvent
--
-- This avoids depending on the legacy request/result event pair while KMZ
-- continues working on the jutsu framework.
--
-- Server remains authoritative for:
-- validation, chakra, cooldown, projectile, damage and statuses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local ChakraService = require(
	ServerScriptService:WaitForChild("ChakraService")
)

local DamageService = require(
	ServerScriptService:WaitForChild("DamageService")
)

local CombatEntityService = require(
	ServerScriptService:WaitForChild("CombatEntityService")
)

local StatusEffectService = require(
	ServerScriptService
		:WaitForChild("Services")
		:WaitForChild("StatusEffectService")
)

local TechniqueRegistry = require(
	ServerScriptService
		:WaitForChild("Services")
		:WaitForChild("TechniqueRegistry")
)

local DeveloperAccessService = require(
	ServerScriptService
		:WaitForChild("Services")
		:WaitForChild("DeveloperAccessService")
)

local TechniqueLoadoutService = require(
	ServerScriptService
		:WaitForChild("Services")
		:WaitForChild("TechniqueLoadoutService")
)

DeveloperAccessService.Start()
TechniqueLoadoutService.Start()

local jutsuSystem =
	ReplicatedStorage:WaitForChild("JutsuSystem")

local definitions = require(
	jutsuSystem
		:WaitForChild("Shared")
		:WaitForChild("JutsuDefinitions")
)

---------------------------------------------------------------------
-- REMOTES
---------------------------------------------------------------------

local remotes =
	jutsuSystem:FindFirstChild("Remotes")

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = jutsuSystem
end

local function getOrCreateRemoteEvent(
	name: string
): RemoteEvent

	local existing =
		remotes:FindFirstChild(name)

	if existing
		and existing:IsA("RemoteEvent") then

		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote =
		Instance.new("RemoteEvent")

	remote.Name = name
	remote.Parent = remotes

	return remote
end

local function getOrCreateRemoteFunction(
	name: string
): RemoteFunction

	local existing =
		remotes:FindFirstChild(name)

	if existing
		and existing:IsA("RemoteFunction") then

		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote =
		Instance.new("RemoteFunction")

	remote.Name = name
	remote.Parent = remotes

	return remote
end

-- Preserve/create KMZ remotes.
local legacyRequestRemote =
	getOrCreateRemoteEvent("JutsuRequest")

local legacyResultRemote =
	getOrCreateRemoteEvent("JutsuResult")

local vfxRemote =
	getOrCreateRemoteEvent("JutsuVFX")

-- Isolated animated-cast transport.
local animatedRequest =
	getOrCreateRemoteFunction(
		"JutsuAnimatedRequest"
	)

local animatedMarker =
	getOrCreateRemoteEvent(
		"JutsuAnimatedMarker"
	)

-- Universal presentation SFX for every animated jutsu.
-- This is deliberately separate from gameplay markers.
local animatedSFX =
	getOrCreateRemoteEvent(
		"JutsuAnimatedSFX"
	)

animatedRequest:SetAttribute(
	"ServerTransportVersion",
	"v8-slot-authoritative"
)

animatedMarker:SetAttribute(
	"ServerTransportVersion",
	"v8-slot-authoritative"
)

animatedSFX:SetAttribute(
	"ServerTransportVersion",
	"v8-slot-authoritative"
)

---------------------------------------------------------------------
-- LOAD JUTSU MODULES
---------------------------------------------------------------------

local modulesFolder =
	script.Parent:WaitForChild("Jutsus")

-- TechniqueRegistry now owns automatic registration/loading.
-- Every ModuleScript in Jutsus is registered once here.
local jutsus: {[string]: any} =
	TechniqueRegistry.LoadJutsuFolder(
		modulesFolder,
		definitions
	)

-- Existing shared JutsuDefinitions remains authoritative.
-- New bulk jutsu modules may provide Module.Config instead.
local function resolveJutsuConfig(
	jutsuId: string,
	jutsu: any?
): any?
	local entry =
		TechniqueRegistry.Get(
			jutsuId
		)

	if entry
		and typeof(entry.Config) == "table" then

		return entry.Config
	end

	if typeof(definitions) == "table"
		and typeof(definitions[jutsuId]) == "table" then

		return definitions[jutsuId]
	end

	if typeof(jutsu) == "table"
		and typeof(jutsu.Config) == "table" then

		return jutsu.Config
	end

	return nil
end

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local cooldowns:
	{[Player]: {[string]: number}} =
	{}

local requestThrottle:
	{[Player]: number} =
	{}

local castingUntil:
	{[Player]: number} =
	{}

local activeCasts:
	{[Player]: any} =
	{}

local REQUEST_MIN_INTERVAL =
	0.08

local function now(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------
-- TECHNIQUE LOADOUT GATE
--
-- Normal players may cast only techniques equipped in one of their
-- 10 CharacterSlotContext technique slots.
--
-- Authorized Dev Content Bypass preserves the existing testing contract:
-- developers may still test registered techniques without populating the
-- loadout. Chakra, cooldown, state and all other server checks still apply.
---------------------------------------------------------------------

local function checkTechniqueLoadoutAccess(
	player: Player,
	techniqueId: string
): (boolean, string, any?)

	if DeveloperAccessService.HasContentBypass(
		player
		) then

		return true,
			"DeveloperBypass",
			{
				DeveloperBypass = true,
			}
	end

	if not TechniqueLoadoutService.IsReady(
		player
		) then

		return false,
			"TechniqueLoadoutNotReady",
			{
				TechniqueId = techniqueId,
			}
	end

	local slotIndex =
		TechniqueLoadoutService.FindSlot(
			player,
			techniqueId
		)

	if not slotIndex then
		return false,
			"TechniqueNotEquipped",
			{
				TechniqueId = techniqueId,
			}
	end

	return true,
		"TechniqueEquipped",
		{
			TechniqueId = techniqueId,
			SlotIndex = slotIndex,
		}
end


---------------------------------------------------------------------
-- SLOT-AUTHORITATIVE ANIMATED REQUEST RESOLUTION
--
-- Normal gameplay sends only SlotIndex. The server resolves the technique
-- from TechniqueLoadoutService. Direct TechniqueId requests are retained
-- only as a compatibility/testing path; normal players cannot use that path.
---------------------------------------------------------------------

local function resolveAnimatedRequestTechnique(
	player: Player,
	requestTarget: any
): (boolean, string?, number?, string, any?)

	local slotIndex: number? = nil

	if typeof(requestTarget) == "number" then
		slotIndex = requestTarget

	elseif typeof(requestTarget) == "table" then
		local candidate =
			requestTarget.SlotIndex

		if typeof(candidate) == "number" then
			slotIndex = candidate
		end
	end

	if slotIndex ~= nil then
		if slotIndex % 1 ~= 0
			or slotIndex < 1
			or slotIndex > TechniqueLoadoutService.GetSlotCount() then

			return false,
				nil,
				nil,
				"InvalidTechniqueSlot",
				{
					SlotIndex = slotIndex,
				}
		end

		if not TechniqueLoadoutService.IsReady(
			player
			) then

			return false,
				nil,
				slotIndex,
				"TechniqueLoadoutNotReady",
				{
					SlotIndex = slotIndex,
				}
		end

		local techniqueId =
			TechniqueLoadoutService.GetSlot(
				player,
				slotIndex
			)

		if not techniqueId then
			return false,
				nil,
				slotIndex,
				"TechniqueSlotEmpty",
				{
					SlotIndex = slotIndex,
				}
		end

		return true,
			techniqueId,
			slotIndex,
			"TechniqueSlotResolved",
			{
				SlotIndex = slotIndex,
				TechniqueId = techniqueId,
			}
	end

	if typeof(requestTarget) == "string" then
		if DeveloperAccessService.HasContentBypass(
			player
			) then

			return true,
				requestTarget,
				nil,
				"DeveloperDirectTechniqueId",
				{
					TechniqueId = requestTarget,
					DeveloperBypass = true,
				}
		end

		return false,
			nil,
			nil,
			"DirectTechniqueIdDisabled",
			{
				TechniqueId = requestTarget,
			}
	end

	return false,
		nil,
		nil,
		"InvalidTechniqueRequest",
		nil
end

---------------------------------------------------------------------
-- CHARACTER / GATES
---------------------------------------------------------------------

local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?, BasePart?)

	local character =
		player.Character

	if not character
		or not character.Parent then

		return nil, nil, nil
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart") then

		return nil, nil, nil
	end

	return character,
		humanoid,
		root
end

local function getActionBlockReason(
	character: Model
): string?

	if character:GetAttribute(
		"IsDowned"
		) == true then

		return "IsDowned"

	elseif character:GetAttribute(
		"DownedActionLocked"
		) == true then

		return "DownedLocked"

	elseif character:GetAttribute(
		"IsCarried"
		) == true then

		return "IsCarried"

	elseif character:GetAttribute(
		"IsCarrying"
		) == true then

		return "IsCarrying"

	elseif character:GetAttribute(
		"IsRecovering"
		) == true then

		return "IsRecovering"

	elseif character:GetAttribute(
		"IsExecuting"
		) == true then

		return "IsExecuting"

	elseif character:GetAttribute(
		"CombatRagdolled"
		) == true then

		return "Ragdolled"

	elseif character:GetAttribute(
		"IsStunned"
		) == true then

		return "IsStunned"

	elseif character:GetAttribute(
		"Status_Stunned"
		) == true then

		return "StatusStunned"

	elseif character:GetAttribute(
		"Status_AttackBlocked"
		) == true then

		return "AttackBlocked"

	elseif character:GetAttribute(
		"CombatSuppressed"
		) == true then

		return "CombatSuppressed"

	elseif character:GetAttribute(
		"ChakraCharging"
		) == true then

		return "ChakraCharging"

	elseif character:GetAttribute(
		"AirComboServerActive"
		) == true then

		return "AirComboActive"
	end

	return nil
end

---------------------------------------------------------------------
-- COOLDOWN CONTRACT
---------------------------------------------------------------------

local function setCoreCooldown(
	character: Model,
	jutsuId: string,
	label: string,
	startsAt: number,
	endsAt: number
)
	local prefix =
		"CoreCooldown_"
		.. jutsuId

	character:SetAttribute(
		prefix .. "_Label",
		label
	)

	character:SetAttribute(
		prefix .. "_StartsAt",
		startsAt
	)

	character:SetAttribute(
		prefix .. "_EndsAt",
		endsAt
	)
end

---------------------------------------------------------------------
-- CAST ATTRIBUTES
---------------------------------------------------------------------

local function setCastAttributes(
	character: Model,
	jutsuId: string,
	token: string,
	endsAt: number
)
	character:SetAttribute(
		"JutsuCasting",
		true
	)

	character:SetAttribute(
		"JutsuCastingId",
		jutsuId
	)

	character:SetAttribute(
		"JutsuCastToken",
		token
	)

	character:SetAttribute(
		"JutsuCastEndsAt",
		endsAt
	)
end

local function clearCastAttributes(
	character: Model,
	jutsuId: string,
	token: string
)
	if not character.Parent then
		return
	end

	if character:GetAttribute(
		"JutsuCastingId"
		) ~= jutsuId then

		return
	end

	if character:GetAttribute(
		"JutsuCastToken"
		) ~= token then

		return
	end

	character:SetAttribute(
		"JutsuCasting",
		false
	)

	character:SetAttribute(
		"JutsuCastingId",
		nil
	)

	character:SetAttribute(
		"JutsuCastToken",
		nil
	)

	character:SetAttribute(
		"JutsuCastEndsAt",
		0
	)
end

---------------------------------------------------------------------
-- UNIVERSAL HAND-SIGN SFX
--
-- Reused by Fireball and every future animated jutsu.
---------------------------------------------------------------------

local HAND_SIGN_SOUND_ID =
	"rbxassetid://17735950643"

local HAND_SIGNS_END_SOUND_ID =
	"rbxassetid://147722098"

local HAND_SIGN_SOUND_VOLUME =
	1.0

local HAND_SIGNS_END_SOUND_VOLUME =
	1.0

local HAND_SIGN_ROLLOFF_MIN =
	7

local HAND_SIGN_ROLLOFF_MAX =
	55

local function playCharacterSound(
	character: Model,
	soundId: string,
	volume: number
)
	if not character.Parent then
		return
	end

	local parent =
		character:FindFirstChild("Head")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")

	if not parent
		or not parent:IsA("BasePart") then
		return
	end

	local sound =
		Instance.new("Sound")

	sound.SoundId =
		soundId

	sound.Volume =
		volume

	sound.RollOffMode =
		Enum.RollOffMode.InverseTapered

	sound.RollOffMinDistance =
		HAND_SIGN_ROLLOFF_MIN

	sound.RollOffMaxDistance =
		HAND_SIGN_ROLLOFF_MAX

	sound.Parent =
		parent

	sound:Play()

	Debris:AddItem(
		sound,
		5
	)
end

---------------------------------------------------------------------
-- ACTIVE CAST
---------------------------------------------------------------------

local function finishCast(
	player: Player,
	token: string,
	reason: string
)
	local active =
		activeCasts[player]

	if not active
		or active.Token ~= token then

		return
	end

	activeCasts[player] =
		nil

	castingUntil[player] =
		0

	clearCastAttributes(
		active.Character,
		active.JutsuId,
		token
	)

	if typeof(
		active.Jutsu.OnCastEnded
		) == "function" then

		local ok,
			err =
			pcall(
				function()

					active.Jutsu
					.OnCastEnded(
						active.Context,
						reason
					)
				end
			)

		if not ok then

			warn(
				"[JutsuServer v12] OnCastEnded failed",
				active.JutsuId,
				err
			)
		end
	end
end

local function isMarkerAllowed(
	jutsu: any,
	markerName: string
): boolean

	local allowed =
		jutsu.AllowedCastMarkers

	if typeof(allowed) ~=
		"table" then

		return false
	end

	return allowed[
	markerName
	] == true
end

local function dispatchMarker(
	player: Player,
	token: string,
	markerName: string,
	source: string,
	markerPayload: any?
)
	local active =
		activeCasts[player]

	if not active
		or active.Token ~= token then

		return
	end

	if not isMarkerAllowed(
		active.Jutsu,
		markerName
		) then

		warn(
			"[JutsuServer v12] Marker denied",
			active.JutsuId,
			markerName
		)

		return
	end

	if active.Markers[
		markerName
		] == true then

		return
	end

	-------------------------------------------------------------
	-- EARLIEST PROJECTILE TIME
	--
	-- Keeps the client marker from creating a projectile at t=0.
	-------------------------------------------------------------

	if markerName ==
		"ProjectileSpawn" then

		local minimum =
			if typeof(
				active.Jutsu
				.MinProjectileDelay
			) == "number"
			then math.max(
				0,
				active.Jutsu
				.MinProjectileDelay
			)
			else 0

		local elapsed =
			now()
		- active.StartedAt

		if elapsed < minimum then

			local remaining =
				minimum - elapsed

			task.delay(
				remaining,
				function()

					local current =
						activeCasts[
					player
					]

					if current
						and current.Token ==
						token
						and current.Markers
						.ProjectileSpawn
						~= true then

						dispatchMarker(
							player,
							token,
							"ProjectileSpawn",
							"ServerMinDelay",
							markerPayload
						)
					end
				end
			)

			return
		end
	end

	active.Markers[
	markerName
	] =
		true

	print(
		"[JutsuServer v12] MARKER",
		active.JutsuId,
		markerName,
		player.Name,
		source
	)

	if typeof(
		active.Jutsu.OnCastMarker
		) == "function" then

		local ok,
			err =
			pcall(
				function()

					active.Jutsu
					.OnCastMarker(
						active.Context,
						markerName,
						source,
						markerPayload
					)
				end
			)

		if not ok then

			warn(
				"[JutsuServer v12] OnCastMarker failed",
				active.JutsuId,
				markerName,
				err
			)
		end
	end

	if markerName ==
		"CastEnd" then

		finishCast(
			player,
			token,
			source
		)
	end
end

---------------------------------------------------------------------
-- ANIMATED REQUEST
---------------------------------------------------------------------

local function processAnimatedRequest(
	player: Player,
	requestTarget: any,
	payload: any
): any

	local resolved,
		jutsuId,
		slotIndex,
		resolveReason,
		resolveDetails =
		resolveAnimatedRequestTechnique(
			player,
			requestTarget
		)

	if not resolved
		or not jutsuId then

		return {
			Accepted = false,
			Reason = resolveReason,
			Loadout = resolveDetails,
		}
	end

	print(
		"[JutsuServer v12] REQUEST RECEIVED",
		player.Name,
		"Slot=" .. tostring(slotIndex or "DEV"),
		jutsuId
	)

	local currentTime =
		now()

	local previous =
		requestThrottle[
	player
	] or 0

	if currentTime - previous
		< REQUEST_MIN_INTERVAL then

		return {
			Accepted = false,
			Reason = "RequestThrottle",
		}
	end

	requestThrottle[
	player
	] =
		currentTime

	local jutsu =
		jutsus[jutsuId]

	local config =
		resolveJutsuConfig(
			jutsuId,
			jutsu
		)

	if not jutsu
		or not config then

		return {
			Accepted = false,
			Reason = "UnknownJutsu",
		}
	end

	-------------------------------------------------------------
	-- AUTOMATIC TECHNIQUE / CHARACTER ORIGIN ACCESS
	--
	-- Any NatureId declared by the jutsu is automatically
	-- converted by TechniqueRegistry into an unlocked-nature
	-- requirement. This happens BEFORE chakra/cooldown commit.
	-------------------------------------------------------------

	local accessAllowed,
		accessReason,
		accessDetails =
		TechniqueRegistry.CheckCastAccess(
			player,
			jutsuId
		)

	if not accessAllowed then
		return {
			Accepted = false,
			Reason =
				accessReason
				or "TechniqueAccessDenied",
			Access =
				accessDetails,
		}
	end

	-------------------------------------------------------------
	-- TECHNIQUE LOADOUT ACCESS
	-------------------------------------------------------------

	local loadoutAllowed,
		loadoutReason,
		loadoutDetails =
		checkTechniqueLoadoutAccess(
			player,
			jutsuId
		)

	if not loadoutAllowed then
		return {
			Accepted = false,
			Reason =
				loadoutReason
				or "TechniqueNotEquipped",
			Loadout =
				loadoutDetails,
		}
	end

	if typeof(
		jutsu.OnCastMarker
		) ~= "function" then

		return {
			Accepted = false,
			Reason =
				"JutsuNotMarkerDriven",
		}
	end

	local character,
		humanoid,
		root =
		getAliveCharacter(
			player
		)

	if not character
		or not humanoid
		or not root then

		return {
			Accepted = false,
			Reason =
				"CharacterUnavailable",
		}
	end

	local blockReason =
		getActionBlockReason(
			character
		)

	if blockReason then

		return {
			Accepted = false,
			Reason = blockReason,
		}
	end

	local currentCastEnds =
		castingUntil[
	player
	] or 0

	if currentCastEnds >
		currentTime then

		return {
			Accepted = false,
			Reason = "AlreadyCasting",
			EndsAt = currentCastEnds,
		}
	end

	local playerCooldowns =
		cooldowns[player]

	if not playerCooldowns then

		playerCooldowns =
			{}

		cooldowns[player] =
			playerCooldowns
	end

	local cooldownEndsAt =
		playerCooldowns[
	jutsuId
	] or 0

	if cooldownEndsAt >
		currentTime then

		return {
			Accepted = false,
			Reason = "Cooldown",
			EndsAt = cooldownEndsAt,
		}
	end

	-------------------------------------------------------------
	-- REQUEST SANITIZATION
	-------------------------------------------------------------

	local sanitizeOk,
		requestOk,
		requestReason,
		requestData =
		pcall(
			function()

				return jutsu
				.SanitizeRequest(
					character,
					payload
				)
			end
		)

	if not sanitizeOk then

		warn(
			"[JutsuServer v12] SanitizeRequest error",
			jutsuId,
			requestOk
		)

		return {
			Accepted = false,
			Reason =
				"SanitizeError",
		}
	end

	if requestOk ~= true then

		return {
			Accepted = false,
			Reason =
				requestReason
				or "InvalidRequest",
		}
	end

	-------------------------------------------------------------
	-- CHAKRA
	-------------------------------------------------------------

	local spent,
		spendReason,
		chakraRemaining =
		ChakraService.TrySpend(
			player,
			config.ChakraCost,
			"Jutsu:"
			.. jutsuId
		)

	if not spent then

		return {
			Accepted = false,
			Reason =
				spendReason
				or "ChakraRejected",
			Chakra =
				chakraRemaining,
		}
	end

	-------------------------------------------------------------
	-- COMMIT
	-------------------------------------------------------------

	local newCooldownEndsAt =
		currentTime
		+ config.Cooldown

	playerCooldowns[
	jutsuId
	] =
		newCooldownEndsAt

	local timeout =
		if typeof(
			jutsu.MarkerCastTimeout
		) == "number"
		then math.max(
			1,
			jutsu.MarkerCastTimeout
		)
		else 8

	local castEndsAt =
		currentTime
		+ timeout

	local token =
		HttpService:GenerateGUID(
			false
		)

	castingUntil[
	player
	] =
		castEndsAt

	setCoreCooldown(
		character,
		jutsuId,
		if typeof(
			config.DisplayName
		) == "string"
			then config.DisplayName
			else jutsuId,
		currentTime,
		newCooldownEndsAt
	)

	setCastAttributes(
		character,
		jutsuId,
		token,
		castEndsAt
	)

	local context = {
		Player =
			player,

		Character =
			character,

		Humanoid =
			humanoid,

		Root =
			root,

		Config =
			config,

		RequestData =
			requestData,

		VFXRemote =
			vfxRemote,

		DamageService =
			DamageService,

		CombatEntityService =
			CombatEntityService,

		StatusEffectService =
			StatusEffectService,

		CastToken =
			token,

		CastStartedAt =
			currentTime,
	}

	activeCasts[
	player
	] = {
		Token =
			token,

		JutsuId =
			jutsuId,

		Jutsu =
			jutsu,

		Character =
			character,

		Context =
			context,

		StartedAt =
			currentTime,

		Markers =
			{},

		HandSignSFXCount =
			0,

		HandSignsEndSFXPlayed =
			false,

		LastHandSignSFXAt =
			0,
	}

	if typeof(
		jutsu.OnCastStarted
		) == "function" then

		local startOk,
			startErr =
			pcall(
				function()

					jutsu
					.OnCastStarted(
						context
					)
				end
			)

		if not startOk then

			warn(
				"[JutsuServer v12] OnCastStarted failed",
				jutsuId,
				startErr
			)
		end
	end

	-------------------------------------------------------------
	-- SAFETY FALLBACK
	-------------------------------------------------------------

	local projectileFallback =
		jutsu.ProjectileFallbackDelay

	if typeof(
		projectileFallback
		) == "number"
			and projectileFallback > 0
			and isMarkerAllowed(
				jutsu,
				"ProjectileSpawn"
			) then

		task.delay(
			projectileFallback,
			function()

				local active =
					activeCasts[
				player
				]

				if active
					and active.Token ==
					token
					and active.Markers
					.ProjectileSpawn
					~= true then

					warn(
						"[JutsuServer v12] Projectile marker fallback",
						jutsuId,
						player.Name
					)

					dispatchMarker(
						player,
						token,
						"ProjectileSpawn",
						"ServerFallback"
					)
				end
			end
		)
	end

	task.delay(
		timeout,
		function()

			local active =
				activeCasts[
			player
			]

			if active
				and active.Token ==
				token then

				warn(
					"[JutsuServer v12] Cast timeout",
					jutsuId,
					player.Name
				)

				finishCast(
					player,
					token,
					"ServerTimeout"
				)
			end
		end
	)

	print(
		"[JutsuServer v12] ACCEPTED",
		player.Name,
		jutsuId,
		token
	)

	return {
		Accepted = true,
		JutsuId = jutsuId,
		SlotIndex = slotIndex,
		CastToken = token,
		CastEndsAt = castEndsAt,
		CooldownEndsAt =
			newCooldownEndsAt,
		ChakraRemaining =
			chakraRemaining,
	}
end

animatedRequest.OnServerInvoke =
	function(
		player: Player,
		requestTarget: any,
		payload: any
	): any

	local ok,
		response =
		pcall(
			processAnimatedRequest,
			player,
			requestTarget,
			payload
		)

	if not ok then

		warn(
			"[JutsuServer v12] REQUEST CRASH",
			player.Name,
			response
		)

		return {
			Accepted = false,
			Reason =
				"InternalServerError",
		}
	end

	return response
end

---------------------------------------------------------------------
-- MARKERS
---------------------------------------------------------------------

animatedMarker.OnServerEvent:
	Connect(
		function(
			player: Player,
			jutsuId: any,
			token: any,
			markerName: any,
			markerPayload: any?
		)

			if typeof(jutsuId) ~=
				"string"
				or typeof(token) ~=
				"string"
				or typeof(markerName) ~=
				"string" then

				return
			end

			local active =
			activeCasts[
			player
			]

			if not active then
				return
			end

			if active.JutsuId ~=
				jutsuId
				or active.Token ~=
				token then

				return
			end

			if markerPayload ~= nil
				and typeof(
					markerPayload
				) ~= "table" then

				markerPayload =
				nil
			end

			dispatchMarker(
				player,
				token,
				markerName,
				"ClientAnimation",
				markerPayload
			)
		end
	)

---------------------------------------------------------------------
-- UNIVERSAL ANIMATED JUTSU SFX
---------------------------------------------------------------------

animatedSFX.OnServerEvent:
	Connect(
		function(
			player: Player,
			jutsuId: any,
			token: any,
			sfxType: any
		)

			if typeof(jutsuId) ~=
				"string"
				or typeof(token) ~=
				"string"
				or typeof(sfxType) ~=
				"string" then

				return
			end

			local active =
			activeCasts[
			player
			]

			if not active
				or active.JutsuId ~=
				jutsuId
				or active.Token ~=
				token then

				return
			end

			local character =
			active.Character

			if sfxType ==
				"HandSign" then

				-- Presentation-only anti-spam protection.
				if active.HandSignSFXCount >=
					20 then

					return
				end

				local current =
				now()

				if current -
					active.LastHandSignSFXAt <
					0.05 then

					return
				end

				active.LastHandSignSFXAt =
				current

				active.HandSignSFXCount +=
				1

				playCharacterSound(
					character,
					HAND_SIGN_SOUND_ID,
					HAND_SIGN_SOUND_VOLUME
				)

			elseif sfxType ==
				"HandSignsEnd" then

				if active.HandSignsEndSFXPlayed ==
					true then

					return
				end

				active.HandSignsEndSFXPlayed =
				true

				playCharacterSound(
					character,
					HAND_SIGNS_END_SOUND_ID,
					HAND_SIGNS_END_SOUND_VOLUME
				)
			end
		end
	)

---------------------------------------------------------------------
-- LEGACY KMZ REQUEST PATH
--
-- Kept functional for other/current KMZ jutsus.
---------------------------------------------------------------------

local function legacyReject(
	player: Player,
	jutsuId: string,
	reason: string,
	extra: any?
)
	legacyResultRemote:FireClient(
		player,
		"Rejected",
		{
			JutsuId = jutsuId,
			Reason = reason,
			Extra = extra,
		}
	)
end

legacyRequestRemote.OnServerEvent:
	Connect(
		function(
			player: Player,
			jutsuId: any,
			payload: any
		)

			if typeof(jutsuId) ~=
				"string" then

				return
			end

			local currentTime =
			now()

			local jutsu =
			jutsus[
			jutsuId
			]

			local config =
			resolveJutsuConfig(
				jutsuId,
				jutsu
			)

			if not jutsu
				or not config then

				legacyReject(
					player,
					jutsuId,
					"UnknownJutsu"
				)

				return
			end

			-----------------------------------------------------
			-- AUTOMATIC TECHNIQUE / CHARACTER ORIGIN ACCESS
			-----------------------------------------------------

			local accessAllowed,
			accessReason,
			accessDetails =
			TechniqueRegistry.CheckCastAccess(
				player,
				jutsuId
			)

			if not accessAllowed then
				legacyReject(
					player,
					jutsuId,
					accessReason
					or "TechniqueAccessDenied",
					accessDetails
				)

				return
			end

			-----------------------------------------------------
			-- TECHNIQUE LOADOUT ACCESS
			-----------------------------------------------------

			local loadoutAllowed,
			loadoutReason,
			loadoutDetails =
			checkTechniqueLoadoutAccess(
				player,
				jutsuId
			)

			if not loadoutAllowed then
				legacyReject(
					player,
					jutsuId,
					loadoutReason
					or "TechniqueNotEquipped",
					loadoutDetails
				)

				return
			end

			-- Marker-driven Fireball uses v6 transport.
			if typeof(
				jutsu.OnCastMarker
				) == "function" then

				legacyReject(
					player,
					jutsuId,
					"UseAnimatedTransport"
				)

				return
			end

			local character,
			humanoid,
			root =
			getAliveCharacter(
				player
			)

			if not character
				or not humanoid
				or not root then

				legacyReject(
					player,
					jutsuId,
					"CharacterUnavailable"
				)

				return
			end

			local block =
			getActionBlockReason(
				character
			)

			if block then

				legacyReject(
					player,
					jutsuId,
					block
				)

				return
			end

			local playerCooldowns =
			cooldowns[player]

			if not playerCooldowns then

				playerCooldowns =
				{}

				cooldowns[player] =
				playerCooldowns
			end

			local cooldownEnd =
			playerCooldowns[
			jutsuId
			] or 0

			if cooldownEnd >
				currentTime then

				legacyReject(
					player,
					jutsuId,
					"Cooldown",
					{
						EndsAt =
						cooldownEnd,
					}
				)

				return
			end

			local sanitizeOk,
			requestOk,
			requestReason,
			requestData =
			pcall(
				function()

					return jutsu
					.SanitizeRequest(
						character,
						payload
					)
				end
			)

			if not sanitizeOk
				or requestOk ~= true then

				legacyReject(
					player,
					jutsuId,
					if sanitizeOk
					then requestReason
					else "SanitizeError"
				)

				return
			end

			local spent,
			spendReason,
			chakraRemaining =
			ChakraService.TrySpend(
				player,
				config.ChakraCost,
				"Jutsu:"
				.. jutsuId
			)

			if not spent then

				legacyReject(
					player,
					jutsuId,
					spendReason,
					{
						Chakra =
						chakraRemaining,
					}
				)

				return
			end

			local newCooldownEnd =
			currentTime
			+ config.Cooldown

			playerCooldowns[
			jutsuId
			] =
			newCooldownEnd

			local castEnd =
			currentTime
			+ config.CastTime

			castingUntil[
			player
			] =
			castEnd

			character:SetAttribute(
				"JutsuCasting",
				true
			)

			character:SetAttribute(
				"JutsuCastingId",
				jutsuId
			)

			character:SetAttribute(
				"JutsuCastEndsAt",
				castEnd
			)

			legacyResultRemote:FireClient(
				player,
				"Accepted",
				{
					JutsuId =
					jutsuId,

					CooldownEndsAt =
					newCooldownEnd,

					CastEndsAt =
					castEnd,

					ChakraRemaining =
					chakraRemaining,
				}
			)

			local executeOk,
			executeErr =
			pcall(
				function()

					jutsu.Execute({
						Player =
						player,

						Character =
						character,

						Humanoid =
						humanoid,

						Root =
						root,

						Config =
						config,

						RequestData =
						requestData,

						VFXRemote =
						vfxRemote,

						DamageService =
						DamageService,

						CombatEntityService =
						CombatEntityService,

						StatusEffectService =
						StatusEffectService,
					})
				end
			)

			if not executeOk then

				warn(
					"[JutsuServer v12] Legacy Execute failed",
					jutsuId,
					executeErr
				)
			end
		end
	)

---------------------------------------------------------------------
-- CLEANUP
---------------------------------------------------------------------

Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			cooldowns[player] =
			nil

			requestThrottle[player] =
			nil

			castingUntil[player] =
			nil

			activeCasts[player] =
			nil
		end
	)

print(
	"[JutsuServer] READY v12 BulkModuleConfigFallback"
		.. " | AnimatedRequest=RemoteFunction"
		.. " | AnimatedMarker=RemoteEvent+OptionalPayload"
		.. " | ReleaseAimRefresh=SUPPORTED"
		.. " | UniversalHandSignSFX=ON"
		.. " | TechniqueRegistry=ON"
		.. " | TechniqueLoadoutGate=ON"
		.. " | ClientSends=SlotIndexOnly"
		.. " | ServerResolvesTechnique=ON"
		.. " | DirectTechniqueIdNormalPlayers=OFF"
		.. " | DevLoadoutBypass=ON"
		.. " | AutoOriginAccess=ON"
		.. " | ModuleConfigFallback=ON"
		.. " | LegacyKMZRemotes=PRESERVED"
		.. " | loaded jutsus: "
		.. table.concat(
			(function()

				local names = {}

				for id in pairs(
					jutsus
					) do

					table.insert(
						names,
						id
					)
				end

				table.sort(
					names
				)

				return names
			end)(),
			", "
		)
)
