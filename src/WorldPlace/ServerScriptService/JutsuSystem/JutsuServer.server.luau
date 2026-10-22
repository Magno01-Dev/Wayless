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

local StaminaService = require(
	ServerScriptService:WaitForChild("StaminaService")
)

---------------------------------------------------------------------
-- COSTE: CHAKRA O STAMINA
--
-- Las técnicas físicas (taijutsu) declaran StaminaCost en vez de
-- ChakraCost: gastan stamina y el sello de supresión no las bloquea.
---------------------------------------------------------------------

local function usesStaminaOnly(
	config: any
): boolean
	return typeof(config) == "table"
		and typeof(config.StaminaCost) == "number"
		and config.StaminaCost > 0
		and not (
			typeof(config.ChakraCost) == "number"
			and config.ChakraCost > 0
		)
end

local function spendTechniqueCost(
	player: Player,
	config: any,
	jutsuId: string
): (boolean, string, number)
	if usesStaminaOnly(config) then
		return StaminaService.TrySpend(
			player,
			config.StaminaCost,
			"Jutsu:" .. jutsuId
		)
	end

	return ChakraService.TrySpend(
		player,
		config.ChakraCost,
		"Jutsu:" .. jutsuId
	)
end

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

---------------------------------------------------------------------
-- INTERRUPCIÓN (taijutsu)
--
-- ServerStorage > JutsuInternal > InterruptCast:Invoke(player) -> boolean
-- Si el jugador está haciendo sellos y su jutsu todavía no salió,
-- el jutsu falla (el coste ya gastado no se devuelve).
---------------------------------------------------------------------

do
	local ServerStorage =
		game:GetService("ServerStorage")

	local internal =
		ServerStorage:FindFirstChild("JutsuInternal")

	if not internal then
		internal = Instance.new("Folder")
		internal.Name = "JutsuInternal"
		internal.Parent = ServerStorage
	end

	local interrupt =
		(internal :: Folder):FindFirstChild("InterruptCast")

	if not interrupt then
		interrupt = Instance.new("BindableFunction")
		interrupt.Name = "InterruptCast"
		interrupt.Parent = internal
	end

	(interrupt :: BindableFunction).OnInvoke = function(
		player: Player
	): boolean
		local active =
			activeCasts[player]

		if not active
			or active.Markers.ProjectileSpawn == true then

			return false
		end

		active.Interrupted =
			true

		return true
	end
end

---------------------------------------------------------------------
-- OBSERVADORES DE CASTS (clanes)
--
-- ServerStorage > JutsuInternal > CastStarted (BindableEvent)
-- Fire(player, character, jutsuId, info) al aceptar un cast.
-- info = { Token, DisplayName, Category, CastTime, StartedAt, Direction?, Range?, NatureId?, IconId? }
-- Lo escucha TechniqueKit > Clan (lectura del Sharingan): el nombre del
-- jutsu ya NO se publica en atributos del personaje.
---------------------------------------------------------------------

local castStarted: BindableEvent = (function(): BindableEvent
	local internal =
		game:GetService("ServerStorage")
			:WaitForChild("JutsuInternal")

	local existing =
		internal:FindFirstChild("CastStarted")

	if existing
		and existing:IsA("BindableEvent") then

		return existing
	end

	local event =
		Instance.new("BindableEvent")

	event.Name = "CastStarted"
	event.Parent = internal

	return event
end)()

-- Alcance de un jutsu (para la trayectoria del Sharingan): el mayor Range / MaxDistance de su
-- configuración o de sus subtablas (Projectile, Bolt, Beam…)
local function techniqueRange(
	config: any,
	jutsu: any
): number?

	local best: number? =
		nil

	local function consider(
		source: any
	)
		if typeof(source) ~= "table" then
			return
		end

		for _, key in { "MaxDistance", "Range" } do
			local value =
				source[key]

			if typeof(value) == "number"
				and value > 0
				and (best == nil or value > (best :: number)) then

				best =
					value
			end
		end
	end

	consider(config)

	if typeof(config) == "table" then
		for _, value in config do
			consider(value)
		end
	end

	if best == nil then
		consider(jutsu)
	end

	return best
end

local REQUEST_MIN_INTERVAL =
	0.08

-- true = imprime cada solicitud, cast aceptado y marcador (solo para depurar)
local DEBUG_JUTSU =
	false

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

---------------------------------------------------------------------
-- DESPERTAR DEL CLAN (tecla Z)
--
-- requestTarget = { Awaken = true }: la técnica la decide el clan
-- (TechniqueKit > Clan.resolveAwaken: Sharingan, Byakugan…) y no
-- ocupa slot. No hace falta aprenderla ni equiparla: Clan valida el
-- clan y la etapa de despertar. El resto (bloqueos, cooldown, chakra,
-- marcadores) es igual que cualquier técnica.
---------------------------------------------------------------------

local function resolveAwakenTechnique(
	player: Player,
	mode: string?
): (string?, string?)

	local ok,
		clanKit =
		pcall(
			function()
				return require(
					script.Parent
						:WaitForChild("TechniqueKit")
						:WaitForChild("Clan")
				) :: any
			end
		)

	if not ok
		or typeof(clanKit) ~= "table"
		or typeof(clanKit.resolveAwaken) ~= "function" then

		return nil,
			"AwakenUnavailable"
	end

	return clanKit.resolveAwaken(
		player,
		mode
	)
end

---------------------------------------------------------------------
-- VELOCIDAD DE SELLOS
--
-- Atributo del personaje SealSpeedMultiplier (≥ 1; p. ej. el Sharingan
-- según sus tomoe). Solo cuenta en técnicas con sellos: el jutsu puede
-- salir antes (MinProjectileDelay / multiplicador) y la lectura del
-- Sharingan ve una barra más corta. JutsuController acelera los sellos.
---------------------------------------------------------------------

local SEAL_CATEGORIES: {[string]: boolean} = {
	Ninjutsu = true,
	ElementalNinjutsu = true,
	Genjutsu = true,
}

local function sealSpeedOf(
	character: Model,
	config: any,
	jutsu: any
): number

	local category =
		(typeof(config) == "table" and config.TechniqueCategory)
		or jutsu.TechniqueCategory

	if SEAL_CATEGORIES[category or ""] ~= true then
		return 1
	end

	local value =
		character:GetAttribute("SealSpeedMultiplier")

	return if typeof(value) == "number"
			and value >= 1
			and value <= 3
		then value
		else 1
end

local function resolveAnimatedRequestTechnique(
	player: Player,
	requestTarget: any
): (boolean, string?, number?, string, any?)

	local slotIndex: number? = nil

	-- Despertar del clan (tecla Z)
	if typeof(requestTarget) == "table"
		and requestTarget.Awaken == true then

		-- Mode: "Sharingan" (toque) · "Mangekyo" (doble toque) · "Susanoo" (mantener)
		local awakenMode =
			if typeof(requestTarget.Mode) == "string"
			then requestTarget.Mode
			else nil

		local awakenId,
			awakenReason =
			resolveAwakenTechnique(
				player,
				awakenMode
			)

		if not awakenId then
			return false,
				nil,
				nil,
				awakenReason or "NoAwaken",
				nil
		end

		return true,
			awakenId,
			nil,
			"ClanAwaken",
			{
				TechniqueId = awakenId,
			}
	end

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

-- escape = técnica de escape (Config.Escape = true, p. ej. Nawanuke): se puede usar
-- con ataque bloqueado (kunai clavado, hilo, parálisis), pero no aturdido ni Downed.
local function getActionBlockReason(
	character: Model,
	staminaOnly: boolean?,
	escape: boolean?
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

	elseif escape ~= true
		and character:GetAttribute(
			"Status_AttackBlocked"
		) == true then

		return "AttackBlocked"

	elseif character:GetAttribute(
		"CombatSuppressed"
		) == true then

		return "CombatSuppressed"

		-- Sello de supresión (lanzables): sin jutsus mientras dure
		-- (el taijutsu no usa chakra: no se bloquea)
	elseif staminaOnly ~= true
		and character:GetAttribute(
			"Status_ChakraSuppressed"
		) == true then

		return "ChakraSuppressed"

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
	-- SELLO DE SUPRESIÓN
	--
	-- Si sellan al lanzador mientras hace los sellos de mano, el
	-- jutsu falla: se ignoran ReleaseStart / ProjectileSpawn.
	-- RecoveryStart y CastEnd pasan para que cada jutsu limpie
	-- (OnCastEnded). El chakra ya gastado no se devuelve.
	-------------------------------------------------------------

	-- Interrumpido por un golpe (InterruptCast, p. ej. Dynamic Entry): el jutsu no sale
	if active.Interrupted
		and markerName ~= "CastEnd"
		and markerName ~= "RecoveryStart" then

		return
	end

	if markerName ~= "CastEnd"
		and markerName ~= "RecoveryStart"
		and not usesStaminaOnly(active.Context and active.Context.Config) then
		local caster =
			player.Character

		if active.Suppressed
			or (caster
				and caster:GetAttribute(
					"Status_ChakraSuppressed"
				) == true) then

			if not active.Suppressed
				and DEBUG_JUTSU then
				print(
					"[JutsuServer v12] SUPPRESSED",
					active.JutsuId,
					player.Name
				)
			end

			active.Suppressed =
				true

			return
		end
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

		-- Sellos más rápidos (SealSpeedMultiplier al empezar el cast)
		if typeof(active.SealSpeed) == "number"
			and active.SealSpeed > 1 then

			minimum /=
				active.SealSpeed
		end

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

	if DEBUG_JUTSU then
		print(
			"[JutsuServer v12] MARKER",
			active.JutsuId,
			markerName,
			player.Name,
			source
		)
	end

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

	-- Despertar del clan: sin acceso de técnica aprendida ni loadout (lo valida Clan)
	local isAwaken =
		resolveReason == "ClanAwaken"

	if DEBUG_JUTSU then
		print(
			"[JutsuServer v12] REQUEST RECEIVED",
			player.Name,
			"Slot=" .. tostring(slotIndex or "DEV"),
			jutsuId
		)
	end

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
	-- MODOS DE CLAN (Sharingan, Byakugan)
	--
	-- Apagar un modo activo responde siempre: va antes del acceso,
	-- el loadout, los bloqueos de estado y el cooldown.
	-------------------------------------------------------------

	if typeof(
		jutsu.TryToggleOff
		) == "function" then

		local toggleCharacter =
			player.Character

		if toggleCharacter then
			local toggleOk,
				toggledOff =
				pcall(
					jutsu.TryToggleOff,
					toggleCharacter
				)

			if toggleOk
				and toggledOff == true then

				return {
					Accepted = false,
					Reason = "Toggled",
				}
			end
		end
	end

	-------------------------------------------------------------
	-- AUTOMATIC TECHNIQUE / CHARACTER ORIGIN ACCESS
	--
	-- Any NatureId declared by the jutsu is automatically
	-- converted by TechniqueRegistry into an unlocked-nature
	-- requirement. This happens BEFORE chakra/cooldown commit.
	-------------------------------------------------------------

	local accessAllowed: boolean,
		accessReason: any,
		accessDetails: any =
		true,
		nil,
		nil

	if not isAwaken then
		accessAllowed,
			accessReason,
			accessDetails =
			TechniqueRegistry.CheckCastAccess(
				player,
				jutsuId
			)
	end

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

	local loadoutAllowed: boolean,
		loadoutReason: any,
		loadoutDetails: any =
		true,
		nil,
		nil

	if not isAwaken then
		loadoutAllowed,
			loadoutReason,
			loadoutDetails =
			checkTechniqueLoadoutAccess(
				player,
				jutsuId
			)
	end

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

	-------------------------------------------------------------
	-- DELEGACIÓN (Copia del Sharingan)
	--
	-- module.ResolveDelegate(player, character)
	--     -> (jutsuId?, reason?, costMultiplier?)
	-- La técnica del slot lanza OTRO jutsu. El acceso y el loadout ya
	-- se comprobaron con la técnica del slot: el delegado no necesita
	-- estar aprendido, equipado ni tener su naturaleza. El cooldown es
	-- el de la técnica del slot; el coste, el del delegado × costMultiplier.
	-- Al confirmarse se llama module.OnDelegateCommitted(player, jutsuId).
	-------------------------------------------------------------

	local slotJutsuId =
		jutsuId

	local slotConfig =
		config

	local delegateSource: any =
		nil

	local costMultiplier =
		1

	if typeof(
		jutsu.ResolveDelegate
		) == "function" then

		local delegateOk,
			delegateId,
			delegateReason,
			delegateMultiplier =
			pcall(
				jutsu.ResolveDelegate,
				player,
				player.Character
			)

		local delegateJutsu =
			if delegateOk and typeof(delegateId) == "string"
			then jutsus[delegateId]
			else nil

		local delegateConfig =
			if delegateJutsu
			then resolveJutsuConfig(
				delegateId,
				delegateJutsu
			)
			else nil

		if not delegateJutsu
			or not delegateConfig then

			return {
				Accepted = false,
				Reason =
					if delegateOk and typeof(delegateReason) == "string"
					then delegateReason
					else "NoDelegate",
			}
		end

		delegateSource =
			jutsu

		jutsuId =
			delegateId

		jutsu =
			delegateJutsu

		config =
			delegateConfig

		if typeof(delegateMultiplier) == "number"
			and delegateMultiplier > 0 then

			costMultiplier =
				delegateMultiplier
		end
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
			character,
			usesStaminaOnly(config),
			typeof(config) == "table" and config.Escape == true
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
	slotJutsuId
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

	-- module.ChakraCostMultiplier(player) -> número: la técnica puede costar más según el
	-- estado (Enton: Black Spear con el Susanoo activo)
	if typeof(jutsu.ChakraCostMultiplier) == "function" then
		local chakraOk, chakraValue =
			pcall(jutsu.ChakraCostMultiplier, player)

		if chakraOk
			and typeof(chakraValue) == "number"
			and chakraValue > 0 then

			costMultiplier *= chakraValue
		end
	end

	-- Delegado (Copia): el coste del jutsu copiado × costMultiplier
	local costConfig: any =
		config

	if costMultiplier ~= 1
		and typeof(config) == "table" then

		costConfig =
			table.clone(config)

		if typeof(costConfig.ChakraCost) == "number" then
			costConfig.ChakraCost *= costMultiplier
		end

		if typeof(costConfig.StaminaCost) == "number" then
			costConfig.StaminaCost *= costMultiplier
		end
	end

	local spent,
		spendReason,
		chakraRemaining =
		spendTechniqueCost(
			player,
			costConfig,
			jutsuId
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

	-- module.CooldownMultiplier(player) -> número: la técnica del slot puede alargar su
	-- recarga (las del Mangekyō, con la ceguera alta)
	local cooldownModule =
		delegateSource or jutsu

	local cooldownMultiplier =
		1

	if typeof(cooldownModule.CooldownMultiplier) == "function" then
		local multiplierOk, multiplierValue =
			pcall(cooldownModule.CooldownMultiplier, player)

		if multiplierOk
			and typeof(multiplierValue) == "number"
			and multiplierValue > 0 then

			cooldownMultiplier =
				multiplierValue
		end
	end

	local newCooldownEndsAt =
		currentTime
		+ slotConfig.Cooldown * cooldownMultiplier

	playerCooldowns[
	slotJutsuId
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
		slotJutsuId,
		if typeof(
			slotConfig.DisplayName
		) == "string"
			then slotConfig.DisplayName
			else slotJutsuId,
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

		SealSpeed =
			sealSpeedOf(
				character,
				config,
				jutsu
			),
	}

	-- Observadores (lectura del Sharingan): qué se lanza, hacia dónde y cuándo sale
	castStarted:Fire(
		player,
		character,
		jutsuId,
		{
			Token =
				token,

			DisplayName =
				if typeof(config.DisplayName) == "string"
				then config.DisplayName
				else jutsuId,

			Category =
				config.TechniqueCategory
				or jutsu.TechniqueCategory,

			CastTime =
				(if typeof(config.CastTime) == "number"
				then config.CastTime
				else 0.5)
				/ sealSpeedOf(
					character,
					config,
					jutsu
				),

			StartedAt =
				currentTime,

			Direction =
				if typeof(requestData) == "table"
					and typeof(requestData.Direction) == "Vector3"
				then requestData.Direction
				else nil,

			Range =
				techniqueRange(
					config,
					jutsu
				),

			NatureId =
				config.NatureId
				or jutsu.NatureId,

			IconId =
				config.IconId
				or jutsu.IconId,
		}
	)

	-- Copia: se gasta lo copiado
	if delegateSource
		and typeof(delegateSource.OnDelegateCommitted) == "function" then

		local delegatedOk,
			delegatedErr =
			pcall(
				delegateSource.OnDelegateCommitted,
				player,
				jutsuId
			)

		if not delegatedOk then
			warn(
				"[JutsuServer v12] OnDelegateCommitted failed",
				slotJutsuId,
				delegatedErr
			)
		end
	end

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

	if DEBUG_JUTSU then
		print(
			"[JutsuServer v12] ACCEPTED",
			player.Name,
			jutsuId,
			token
		)
	end

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

			-- Técnicas sin sellos (dōjutsu): sin sonidos de sellos, usan solo el suyo
			if active.Jutsu
				and active.Jutsu.NoHandSigns == true then

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
				character,
				usesStaminaOnly(config),
				typeof(config) == "table" and config.Escape == true
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
			spendTechniqueCost(
				player,
				config,
				jutsuId
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
