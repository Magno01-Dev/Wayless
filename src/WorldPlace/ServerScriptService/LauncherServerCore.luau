--!strict
-- LauncherServerCore v3.7 DB - Reliable Uplift Hit Timing
-- ServerScriptService > LauncherServerCore [ModuleScript]
--
-- Uses shared DamageService plus the CombatEntity/CombatMotion foundation.
-- Player and NPC humanoid targets now share the same Launcher hit/air contract.

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

local ServerScriptService =
	game:GetService("ServerScriptService")

local Debris =
	game:GetService("Debris")

local TweenService =
	game:GetService("TweenService")


local DamageService =
	require(
		script.Parent:
		WaitForChild(
			"DamageService"
		)
	)

local StatusCombatModifierService =
	require(
		script.Parent:
		WaitForChild("Services"):
		WaitForChild(
			"StatusCombatModifierService"
		)
	)

local CombatEntityService =
	require(
		script.Parent:
		WaitForChild(
			"CombatEntityService"
		)
	)

local CombatMotionService =
	require(
		script.Parent:
		WaitForChild(
			"CombatMotionService"
		)
	)


local combatRemotes =
	ReplicatedStorage:
	WaitForChild(
		"CombatRemotes"
	)

local launcherEvent =
	combatRemotes:
	WaitForChild(
		"LauncherEvent"
	) :: RemoteEvent

local combatImpactVFXInstance =
	combatRemotes:
	FindFirstChild(
		"CombatImpactVFX"
	)

if not combatImpactVFXInstance then
	combatImpactVFXInstance =
		Instance.new(
			"RemoteEvent"
		)

	combatImpactVFXInstance.Name =
		"CombatImpactVFX"

	combatImpactVFXInstance.Parent =
		combatRemotes
end

local combatImpactVFX =
	combatImpactVFXInstance :: RemoteEvent


-- Server-only bridge used by CombatServer after an authoritative aerial M1_5.
-- No new Script is required; this BindableEvent belongs to LauncherServerCore.
local existingAirComboControl =
	ServerScriptService:
	FindFirstChild(
		"LauncherAirComboControl"
	)

if existingAirComboControl
	and not existingAirComboControl:IsA(
		"BindableEvent"
	) then
	existingAirComboControl:Destroy()
	existingAirComboControl = nil
end

local launcherAirComboControl =
	existingAirComboControl
	or Instance.new(
		"BindableEvent"
	)

launcherAirComboControl.Name =
	"LauncherAirComboControl"
launcherAirComboControl.Parent =
	ServerScriptService


-- ============================================================
-- CONFIG
-- ============================================================

local LAUNCHER_DAMAGE =
	4

local LAUNCHER_ARMOR_PROFILE = {
	Penetration = 0,
	DurabilityDamage = 1.00,
}

-- Launcher balance: visible/client cooldown is 4.0s. Server enforcement stays
-- slightly shorter so latency cannot create a false reject at the edge.
local LAUNCHER_COOLDOWN =
	4.00

local SERVER_COOLDOWN =
	3.90

-- Authored Hit on the restored Uplift lands ~0.25s after local Start at
-- PlaybackSpeed 1.4. RemoteEvent scheduling showed legitimate server-side
-- Start->Hit intervals as low as ~0.18-0.20s, so 0.22 produced false misses.
-- This remains only a sanity/anti-impossible-packet bound; the server still
-- owns target selection, LOS, cooldown, sequence and damage.
local MIN_HIT_AFTER_START =
	0.10

local MAX_HIT_AFTER_START =
	0.85

local MAX_CLIENT_TIMESTAMP_REWIND =
	0.20


local HITBOX_SIZE =
	Vector3.new(
		8.5,
		7.0,
		10.0
	)

local HITBOX_FORWARD_OFFSET =
	5.5

local HITBOX_VERTICAL_OFFSET =
	0.35


-- Air transition QA values.
local AIR_RISE_HEIGHT =
	20.0

-- Give the upward kick a readable away-from-attacker component too.
local AIR_VICTIM_FORWARD_DISTANCE =
	8.0

local AIR_PAIR_DISTANCE =
	4.5

local AIR_ATTACKER_LOWER_OFFSET =
	0.75

local AIR_TRANSITION_DURATION =
	0.48

local AIR_HOLD_DURATION =
	3.75

-- Victim can reach the apex before the attacker finishes the new HIT-only
-- animation tail. This is only a safety/pre-hold allowance. The REAL combo
-- timer starts when the attacker reports AirFollowArrived.
local AIR_PRE_HOLD_MAX_DURATION =
	3.00

-- Air M2 slam QA values. The finisher launches the victim hard enough to
-- create a readable diagonal-down trajectory, drops the attacker immediately,
-- and resolves the first real collidable surface impact (ground or wall).
-- Ground and wall share the same damage/stun duration by design.
local AIR_M2_HORIZONTAL_SPEED =
	110.0

local AIR_M2_DOWNWARD_SPEED =
	75.0

local AIR_M2_ATTACKER_DROP_SPEED =
	42.0

local AIR_M2_IMPACT_DAMAGE =
	8.0

local AIR_M2_IMPACT_TIMEOUT =
	2.00

local AIR_M2_IMPACT_MIN_DELAY =
	0.08

-- Keep forward prediction tight. The old 4.5-stud probe could "hit" the floor
-- several studs before the victim physically reached it, anchoring them mid-air.
local AIR_M2_FORWARD_PROBE_MAX_DISTANCE =
	1.15

local AIR_M2_FORWARD_PROBE_PADDING =
	0.18

local AIR_M2_GROUND_CONTACT_PROBE_DISTANCE =
	3.75

-- HRP center is several studs above the feet on R6. These proximity probes
-- detect the character volume touching a surface rather than waiting for the
-- HRP center itself to cross the surface.
local AIR_M2_GROUND_PROXIMITY_DISTANCE =
	3.55

local AIR_M2_WALL_PROXIMITY_DISTANCE =
	3.75

-- Detect walls even if physics has already stopped/reversed the victim.
local AIR_M2_EARLY_WALL_PROBE_DISTANCE =
	4.25

local AIR_M2_TIMEOUT_GROUND_RECOVERY_DISTANCE =
	8.0

local AIR_M2_TIMEOUT_WALL_RECOVERY_DISTANCE =
	4.5

local AIR_M2_GROUND_ROOT_OFFSET =
	2.35

local AIR_M2_RELEASE_REINFORCE_FRAMES =
	3

local AIR_M2_GROUND_NORMAL_Y_MIN =
	0.45

local AIR_M2_IMPACT_STUN_DURATION =
	1.00

-- Visual-only procedural impact geometry. Keep the scar readable for a while,
-- then fade it instead of deleting the whole model in one frame.
local AIR_M2_IMPACT_VISUAL_HOLD_DURATION =
	10.0

local AIR_M2_IMPACT_VISUAL_FADE_DURATION =
	2.75

local AIR_M2_GROUND_SCAR_DIAMETER =
	18.0

local AIR_M2_WALL_SCAR_DIAMETER =
	AIR_M2_GROUND_SCAR_DIAMETER

-- Authored victim animations.
--
-- Uplift launch:
-- 27 frames ~= 0.45s at 60 FPS.
-- Physical transition remains 0.48s, so the animation fits without changing
-- the approved movement timing.
local AIR_UPLIFT_VICTIM_LAUNCH_ANIMATION_ID =
	"113069702431140"

-- Air M2 route.
local AIR_M2_VICTIM_AIR_TRAVEL_ANIMATION_ID =
	"131120495295267"

local AIR_M2_VICTIM_GROUND_IMPACT_ANIMATION_ID =
	"90447032048524"

local AIR_M2_VICTIM_GROUND_STUN_ANIMATION_ID =
	"98446797314691"

-- Still pending authored wall animations.
local AIR_M2_VICTIM_WALL_IMPACT_ANIMATION_ID =
	""

local AIR_M2_VICTIM_WALL_PINNED_ANIMATION_ID =
	""

-- GroundImpact was authored around the ~12 frame / ~0.20s target.
local AIR_M2_IMPACT_TO_STUN_ANIMATION_DELAY =
	0.20

local AIR_SYNC_LEAD =
	0.08

local AIR_HARD_TIMEOUT =
	AIR_SYNC_LEAD
	+ AIR_TRANSITION_DURATION
	+ AIR_PRE_HOLD_MAX_DURATION
	+ AIR_HOLD_DURATION
	+ 0.75


local DEBUG =
	false


-- Authored Launcher/Uplift SFX.
local LAUNCHER_HIT_SOUND_ID =
	"rbxassetid://119801699610817"

local LAUNCHER_MISS_SOUND_ID =
	"rbxassetid://135708425496510"

local AIR_M2_KICK_IMPACT_SOUND_ID =
	"rbxassetid://135806242267027"

local AIR_M2_GROUND_IMPACT_SOUND_IDS = {
	"rbxassetid://91558081996789",
	"rbxassetid://131549424855755",
	"rbxassetid://74149238738530",
}

local LAUNCHER_HIT_SOUND_VOLUME =
	0.40

local LAUNCHER_MISS_SOUND_VOLUME =
	0.40

local AIR_M2_KICK_IMPACT_SOUND_VOLUME =
	1.50

local AIR_M2_GROUND_IMPACT_SOUND_VOLUME =
	1.00

local SOUND_ROLLOFF_MAX_DISTANCE =
	65

local lastAirM2GroundImpactSoundIndex =
	0


-- ============================================================
-- STATE
-- ============================================================

local launcherStates: {
	[Player]: any
} = {}

local cooldownUntil: {
	[Player]: number
} = {}

local airCombos: {
	[number]: any
} = {}

local nextAirComboId =
	0


-- ============================================================
-- HELPERS
-- ============================================================

local function getAliveCharacter(
	player: Player
): (Model?, Humanoid?, BasePart?)

	local character =
		player.Character

	if not character then
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
		or not root:IsA(
			"BasePart"
		) then

		return nil, nil, nil
	end


	return character,
		humanoid,
		root
end


local function downedLocked(
	character: Model
): boolean

	return character:GetAttribute(
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
		) == true
end


local function canBeLauncherTarget(
	character: Model,
	humanoid: Humanoid
): boolean

	if humanoid.Health <= 0 then
		return false
	end

	if downedLocked(
		character
		) then
		return false
	end

	if character:GetAttribute(
		"AirComboServerActive"
		) == true then
		return false
	end

	return true
end


local function horizontalUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	local flat =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if flat.Magnitude >
		0.001 then

		return flat.Unit
	end


	local fallbackFlat =
		Vector3.new(
			fallback.X,
			0,
			fallback.Z
		)

	if fallbackFlat.Magnitude >
		0.001 then

		return fallbackFlat.Unit
	end


	return Vector3.new(
		0,
		0,
		-1
	)
end


local function zeroRoot(
	root: BasePart
)

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero
end


local function createNoCollision(
	state: any,
	characterA: Model,
	characterB: Model
)
	state.noCollision = {}

	local partsA: {BasePart} = {}
	local partsB: {BasePart} = {}

	for _, descendant in ipairs(characterA:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(partsA, descendant)
		end
	end

	for _, descendant in ipairs(characterB:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(partsB, descendant)
		end
	end

	for _, partA in ipairs(partsA) do
		for _, partB in ipairs(partsB) do
			local constraint = Instance.new("NoCollisionConstraint")
			constraint.Name = "LauncherAirNoCollision"
			constraint.Part0 = partA
			constraint.Part1 = partB
			constraint.Parent = partB
			table.insert(state.noCollision, constraint)
		end
	end
end


local function destroyNoCollision(
	state: any
)
	for _, constraint in ipairs(state.noCollision or {}) do
		if constraint.Parent then
			constraint:Destroy()
		end
	end

	state.noCollision = {}
end


local function setLauncherAirTarget(
	attackerCharacter: Model,
	victimCharacter: Model
)
	local existing =
		attackerCharacter:
		FindFirstChild(
			"LauncherAirTarget"
		)

	local targetRef: ObjectValue

	if existing
		and existing:IsA(
			"ObjectValue"
		) then

		targetRef = existing
	else
		if existing then
			existing:Destroy()
		end

		targetRef =
			Instance.new(
				"ObjectValue"
			)

		targetRef.Name =
			"LauncherAirTarget"

		targetRef.Parent =
			attackerCharacter
	end

	targetRef.Value =
		victimCharacter

	attackerCharacter:SetAttribute(
		"AirM1Allowed",
		true
	)
end


local function clearLauncherAirTarget(
	character: Model
)
	character:SetAttribute(
		"AirM1Allowed",
		false
	)

	local targetRef =
		character:
		FindFirstChild(
			"LauncherAirTarget"
		)

	if targetRef
		and targetRef:IsA(
			"ObjectValue"
		) then

		targetRef.Value =
			nil

		targetRef:Destroy()
	end
end


local function setAirLock(
	state: any,
	character: Model,
	role: string
)
	character:SetAttribute("AirComboServerActive", true)
	character:SetAttribute("AirComboId", state.id)
	character:SetAttribute("AirComboRole", role)
	character:SetAttribute("LauncherAirLockOwner", state.id)
	character:SetAttribute("LauncherAirComboAttacker", role == "Attacker")
	character:SetAttribute("LauncherAirComboVictim", role == "Victim")

	-- The attacker must stay actionable in the authored aerial-combo window.
	-- Only the victim is crowd-controlled. This is what allows the existing
	-- M1 pipeline to run in air without creating a parallel aerial M1 system.
	if role == "Victim" then
		state.previousStuns = state.previousStuns or {}
		state.previousStuns[character] = {
			isStunned = character:GetAttribute("IsStunned") == true,
			stunEndsAt = character:GetAttribute("StunEndsAt"),
		}

		character:SetAttribute("IsStunned", true)

		local currentEnd = character:GetAttribute("StunEndsAt")
		local lockEnd = state.serverLockEndsAt
		if typeof(currentEnd) == "number" then
			lockEnd = math.max(lockEnd, currentEnd)
		end
		character:SetAttribute("StunEndsAt", lockEnd)
	end
end


local function releaseAirLock(
	state: any,
	character: Model?
)
	if not character or not character.Parent then
		return
	end

	local role = character:GetAttribute("AirComboRole")

	if role == "Attacker" then
		clearLauncherAirTarget(
			character
		)
	else
		character:SetAttribute(
			"AirM1Allowed",
			false
		)
	end

	character:SetAttribute("AirComboServerActive", false)
	character:SetAttribute("AirComboId", nil)
	character:SetAttribute("AirComboRole", nil)
	character:SetAttribute("LauncherAirComboAttacker", false)
	character:SetAttribute("LauncherAirComboVictim", false)

	local owns = character:GetAttribute("LauncherAirLockOwner") == state.id
	character:SetAttribute("LauncherAirLockOwner", nil)

	if not owns or role ~= "Victim" then
		return
	end

	local now = time()
	local currentEnd = character:GetAttribute("StunEndsAt")

	-- A newer/longer combat stun owns the victim now; never clear it here.
	if typeof(currentEnd) == "number"
		and currentEnd > state.serverLockEndsAt + 0.05 then
		return
	end

	local previous = state.previousStuns and state.previousStuns[character] or nil
	if previous
		and previous.isStunned == true
		and typeof(previous.stunEndsAt) == "number"
		and previous.stunEndsAt > now then

		character:SetAttribute("IsStunned", true)
		character:SetAttribute("StunEndsAt", previous.stunEndsAt)
	else
		character:SetAttribute("IsStunned", false)
		character:SetAttribute("StunEndsAt", nil)
	end
end


local function playLauncher3DSound(
	parentPart: BasePart,
	soundName: string,
	soundId: string,
	volume: number
)
	if soundId == "" then
		return
	end

	local sound =
		Instance.new("Sound")

	sound.Name =
		soundName

	sound.SoundId =
		soundId

	sound.Volume =
		volume

	sound.PlaybackSpeed =
		1.0

	sound.RollOffMode =
		Enum.RollOffMode.Inverse

	sound.RollOffMaxDistance =
		SOUND_ROLLOFF_MAX_DISTANCE

	sound.Parent =
		parentPart

	sound:
		Play()

	Debris:
		AddItem(
			sound,
			4
		)
end


local function playLauncherHitSound(
	targetRoot: BasePart
)
	playLauncher3DSound(
		targetRoot,
		"LauncherUpliftHitSound",
		LAUNCHER_HIT_SOUND_ID,
		LAUNCHER_HIT_SOUND_VOLUME
	)
end


local function playLauncherMissSound(
	attackerRoot: BasePart
)
	playLauncher3DSound(
		attackerRoot,
		"LauncherUpliftMissSound",
		LAUNCHER_MISS_SOUND_ID,
		LAUNCHER_MISS_SOUND_VOLUME
	)
end


local function playAirM2KickImpactSound(
	targetRoot: BasePart
)
	playLauncher3DSound(
		targetRoot,
		"LauncherAirM2KickImpactSound",
		AIR_M2_KICK_IMPACT_SOUND_ID,
		AIR_M2_KICK_IMPACT_SOUND_VOLUME
	)
end


local function chooseAirM2GroundImpactSoundId(): string
	local count =
		#AIR_M2_GROUND_IMPACT_SOUND_IDS

	if count <= 0 then
		return ""
	end

	if count == 1 then
		lastAirM2GroundImpactSoundIndex =
			1

		return AIR_M2_GROUND_IMPACT_SOUND_IDS[1]
	end

	local index =
		math.random(
			1,
			count
		)

	if index ==
		lastAirM2GroundImpactSoundIndex then

		index =
			index % count
			+ 1
	end

	lastAirM2GroundImpactSoundIndex =
		index

	return AIR_M2_GROUND_IMPACT_SOUND_IDS[index]
end


local function playAirM2GroundImpactSound(
	targetRoot: BasePart
)
	local soundId =
		chooseAirM2GroundImpactSoundId()

	if soundId == "" then
		return
	end

	playLauncher3DSound(
		targetRoot,
		"LauncherAirM2GroundImpactSound",
		soundId,
		AIR_M2_GROUND_IMPACT_SOUND_VOLUME
	)
end


local function emitLauncherImpactVFX(
	attacker: Player,
	defender: Player?,
	attackerRoot: BasePart,
	targetRoot: BasePart
)
	local delta = targetRoot.Position - attackerRoot.Position
	local impactDirection = if delta.Magnitude > 0.001 then delta.Unit else attackerRoot.CFrame.LookVector
	local impactPosition = targetRoot.Position - impactDirection * 0.92 + Vector3.new(0, 0.48, 0)

	combatImpactVFX:FireAllClients(
		"Hit",
		impactPosition,
		impactDirection,
		0,
		attacker.UserId,
		defender and defender.UserId or 0
	)
end


-- ============================================================
-- HITBOX
-- ============================================================

type Candidate = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	entity: any,
}


local function collectCandidates(
	attackerCharacter: Model,
	attackerRoot: BasePart
): {Candidate}
	local boxCFrame = attackerRoot.CFrame * CFrame.new(0, HITBOX_VERTICAL_OFFSET, -HITBOX_FORWARD_OFFSET)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {attackerCharacter}

	local parts = workspace:GetPartBoundsInBox(boxCFrame, HITBOX_SIZE, params)
	local seen: {[Model]: boolean} = {}
	local candidates: {Candidate} = {}

	for _, part in ipairs(parts) do
		local entity = CombatEntityService.ResolveFromInstance(part)
		if not entity then
			continue
		end

		local target = entity.Character
		if target == attackerCharacter or seen[target] then
			continue
		end

		seen[target] = true

		if not CombatEntityService.CanReceiveLauncher(entity) then
			continue
		end

		table.insert(candidates, {
			character = entity.Character,
			humanoid = entity.Humanoid,
			root = entity.Root,
			player = entity.Player,
			entity = entity,
		})
	end

	table.sort(candidates, function(a: Candidate, b: Candidate)
		return (a.root.Position - attackerRoot.Position).Magnitude < (b.root.Position - attackerRoot.Position).Magnitude
	end)

	return candidates
end


local function hasLineOfSight(
	attackerCharacter: Model,
	targetCharacter: Model,
	attackerRoot: BasePart,
	targetRoot: BasePart
): boolean

	local direction =
		targetRoot.Position
	- attackerRoot.Position


	if direction.Magnitude <
		0.1 then

		return true
	end


	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		attackerCharacter,
	}


	local result =
		workspace:
		Raycast(
			attackerRoot.Position,
			direction,
			params
		)


	if not result then
		return true
	end


	return result.Instance:
		IsDescendantOf(
			targetCharacter
		)
end


local function normalizeOptionalAnimationId(
	rawId: string
): string?
	if rawId == "" then
		return nil
	end

	if string.find(rawId, "rbxassetid://", 1, true) == 1 then
		return rawId
	end

	return "rbxassetid://" .. rawId
end


local function playOptionalVictimAnimation(
	humanoid: Humanoid,
	rawId: string,
	name: string,
	looped: boolean
): AnimationTrack?
	local animationId =
		normalizeOptionalAnimationId(rawId)

	if not animationId then
		return nil
	end

	local animator =
		humanoid:FindFirstChildOfClass("Animator")

	if not animator then
		return nil
	end

	local animation =
		Instance.new("Animation")

	animation.Name = name
	animation.AnimationId = animationId

	local animationTrack =
		animator:LoadAnimation(animation)

	animation:Destroy()

	animationTrack.Priority =
		Enum.AnimationPriority.Action4

	animationTrack.Looped =
		looped

	animationTrack:Play(0.04)

	return animationTrack
end


local function stopOptionalTrack(
	animationTrack: AnimationTrack?
)
	if not animationTrack then
		return
	end

	-- Launcher victim reactions are Action4 and can hold a floor pose strongly.
	-- For authoritative release paths we do NOT want residual blend weight.
	if animationTrack.IsPlaying then
		animationTrack:
			Stop(0)
	end

	animationTrack:
		Destroy()
end


local function stopAllLauncherVictimTracks(
	humanoid: Humanoid
)
	local animator =
		humanoid:
		FindFirstChildOfClass(
			"Animator"
		)

	if not animator then
		return
	end

	for _, track in ipairs(
		animator:GetPlayingAnimationTracks()
		) do

		local name =
			track.Name

		if string.find(
			name,
			"LauncherM2",
			1,
			true
			) == 1
				or string.find(
					name,
					"LauncherUpliftVictimLaunch",
					1,
					true
				) == 1 then

			track:
				Stop(0)

			track:
				Destroy()
		end
	end
end


local function surfaceBasis(
	normal: Vector3
): (Vector3, Vector3)
	local unitNormal =
		normal.Unit

	local tangent =
		unitNormal:Cross(Vector3.yAxis)

	if tangent.Magnitude < 0.05 then
		tangent =
			unitNormal:Cross(Vector3.xAxis)
	end

	tangent =
		tangent.Unit

	local bitangent =
		unitNormal:Cross(tangent).Unit

	return tangent, bitangent
end


local function getImpactSurfaceColor(
	result: RaycastResult
): Color3
	if result.Instance:IsA("BasePart") then
		return result.Instance.Color
	end

	return workspace.Terrain:
		GetMaterialColor(result.Material)
end


local function getImpactVisualSurface(
	impactKind: string,
	result: RaycastResult
): (Enum.Material, Color3)
	local surfaceMaterial =
		result.Material

	local surfaceColor =
		getImpactSurfaceColor(result)

	-- A wall scar represents pieces of the wall itself.
	if impactKind == "Wall" then
		return surfaceMaterial,
			surfaceColor
	end

	-- Ground impacts expose what is UNDER the visible top layer. Grass/snow
	-- therefore become earthy rather than producing bright green/white rocks.
	local looksVegetated =
		surfaceMaterial == Enum.Material.Grass
		or (
			surfaceColor.G > surfaceColor.R * 1.18
			and surfaceColor.G > surfaceColor.B * 1.10
		)

	if looksVegetated
		or surfaceMaterial == Enum.Material.Snow then

		return Enum.Material.Ground,
			workspace.Terrain:
			GetMaterialColor(
				Enum.Material.Ground
			)
	end

	if surfaceMaterial == Enum.Material.Sand then
		return Enum.Material.Sand,
			surfaceColor:
			Lerp(
				Color3.new(0, 0, 0),
				0.10
			)
	end

	return surfaceMaterial,
		surfaceColor:
		Lerp(
			Color3.new(0, 0, 0),
			0.06
		)
end


local function scheduleImpactVisualFade(
	folder: Folder
)
	-- Hard cleanup is only a safety net. Normal presentation fades first.
	Debris:AddItem(
		folder,
		AIR_M2_IMPACT_VISUAL_HOLD_DURATION
			+ AIR_M2_IMPACT_VISUAL_FADE_DURATION
			+ 1.0
	)

	task.delay(
		AIR_M2_IMPACT_VISUAL_HOLD_DURATION,
		function()
			if not folder.Parent then
				return
			end

			local tweenInfo =
				TweenInfo.new(
					AIR_M2_IMPACT_VISUAL_FADE_DURATION,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)

			for _, descendant in ipairs(
				folder:GetDescendants()
				) do
				if descendant:IsA("BasePart") then
					TweenService:
						Create(
							descendant,
							tweenInfo,
							{Transparency = 1}
						):Play()
				end
			end

			task.delay(
				AIR_M2_IMPACT_VISUAL_FADE_DURATION + 0.10,
				function()
					if folder.Parent then
						folder:Destroy()
					end
				end
			)
		end
	)
end


local function spawnAirM2ImpactVisual(
	state: any,
	impactKind: string,
	result: RaycastResult
)
	local normal =
		result.Normal.Unit

	local tangent,
		bitangent =
		surfaceBasis(normal)

	local visualMaterial,
		surfaceColor =
		getImpactVisualSurface(
			impactKind,
			result
		)

	local folder =
		Instance.new("Folder")

	folder.Name =
		"LauncherM2ImpactVisual"

	folder.Parent =
		workspace

	local random =
		Random.new(
			state.id * 7919
		)

	local function configureVisualPart(
		part: BasePart
	)
		part.Anchored =
			true

		part.CanCollide =
			false

		part.CanQuery =
			false

		part.CanTouch =
			false

		part.CastShadow =
			true

		part.Material =
			visualMaterial

		part.Color =
			surfaceColor

		part.Parent =
			folder
	end

	if impactKind == "Ground"
		or impactKind == "Wall" then

		-- Same impact force, same crater geometry. The construction is based on
		-- the hit normal, so it rotates cleanly onto vertical walls.
		-- Large anime-style crater. The R6 body should fit clearly inside the
		-- fractured basin, while the raised rim extends well beyond the body.
		-- All geometry is visual-only: no collision and no Terrain mutation.
		local diameter =
			AIR_M2_GROUND_SCAR_DIAMETER

		local rimRadius =
			diameter * 0.37

		local outerCount =
			20

		-- Continuous raised rim. Segment width intentionally overlaps the
		-- circumference so the rocks read as one lifted ring, not separate stones.
		for index = 1, outerCount do
			local baseAngle =
				(index - 1)
				/ outerCount
				* math.pi
				* 2

			local angle =
				baseAngle
				+ random:
				NextNumber(
					-0.045,
					0.045
				)

			local radial =
				(
					tangent
					* math.cos(angle)
					+ bitangent
					* math.sin(angle)
				).Unit

			local around =
				normal:
				Cross(radial).Unit

			local width =
				random:
				NextNumber(
					2.55,
					3.45
				)

			local height =
				random:
				NextNumber(
					1.25,
					2.35
				)

			local depth =
				random:
				NextNumber(
					3.25,
					4.85
				)

			local rock =
				Instance.new(
					"WedgePart"
				)

			rock.Name =
				"CraterRimRock"

			rock.Size =
				Vector3.new(
					width,
					height,
					depth
				)

			configureVisualPart(
				rock
			)

			rock.Color =
				surfaceColor:
				Lerp(
					Color3.new(0, 0, 0),
					random:
					NextNumber(
						0.02,
						0.13
					)
				)

			local radialDistance =
				rimRadius
				+ random:
				NextNumber(
					-0.30,
					0.30
				)

			local position =
				result.Position
				+ radial
				* radialDistance
				+ normal
				* (
					height
					* 0.58
				)

			rock.CFrame =
				CFrame.fromMatrix(
					position,
					around,
					normal,
					radial
				)
				* CFrame.Angles(
					random:
					NextNumber(
						-0.42,
						-0.16
					),
					random:
					NextNumber(
						-0.08,
						0.08
					),
					random:
					NextNumber(
						-0.10,
						0.10
					)
				)
		end

		-- Broken inner shelf: large slabs lean from the basin toward the raised rim.
		-- This fills the empty gap that made the previous version look like
		-- "a few rocks in a circle" instead of displaced ground.
		local shelfCount =
			14

		for index = 1, shelfCount do
			local baseAngle =
				(index - 1)
				/ shelfCount
				* math.pi
				* 2

			local angle =
				baseAngle
				+ random:
				NextNumber(
					-0.08,
					0.08
				)

			local radial =
				(
					tangent
					* math.cos(angle)
					+ bitangent
					* math.sin(angle)
				).Unit

			local around =
				normal:
				Cross(radial).Unit

			local slab =
				Instance.new(
					"WedgePart"
				)

			slab.Name =
				"CraterInnerShelf"

			slab.Size =
				Vector3.new(
					random:
					NextNumber(
						2.40,
						3.65
					),
					random:
					NextNumber(
						0.45,
						1.05
					),
					random:
					NextNumber(
						3.20,
						4.80
					)
				)

			configureVisualPart(
				slab
			)

			slab.Color =
				surfaceColor:
				Lerp(
					Color3.new(0, 0, 0),
					random:
					NextNumber(
						0.10,
						0.22
					)
				)

			local shelfRadius =
				rimRadius * random:
				NextNumber(
					0.49,
					0.68
				)

			slab.CFrame =
				CFrame.fromMatrix(
					result.Position
					+ radial
					* shelfRadius
					+ normal
					* random:
					NextNumber(
						0.08,
						0.28
					),
					around,
					normal,
					radial
				)
				* CFrame.Angles(
					random:
					NextNumber(
						-0.30,
						-0.10
					),
					random:
					NextNumber(
						-0.08,
						0.08
					),
					random:
					NextNumber(
						-0.08,
						0.08
					)
				)
		end

		-- Fractured basin floor. Large overlapping plates visually read as a
		-- broken/depressed center while remaining purely cosmetic.
		local centerCount =
			12

		for index = 1, centerCount do
			local angle =
				random:
				NextNumber(
					0,
					math.pi * 2
				)

			local distance =
				random:
				NextNumber(
					0.15,
					rimRadius * 0.48
				)

			local radial =
				(
					tangent
					* math.cos(angle)
					+ bitangent
					* math.sin(angle)
				).Unit

			local around =
				normal:
				Cross(radial).Unit

			local slab =
				Instance.new(
					"Part"
				)

			slab.Name =
				"CraterBasinPlate"

			slab.Size =
				Vector3.new(
					random:
					NextNumber(
						2.10,
						4.20
					),
					random:
					NextNumber(
						0.10,
						0.24
					),
					random:
					NextNumber(
						2.25,
						4.65
					)
				)

			configureVisualPart(
				slab
			)

			slab.Color =
				surfaceColor:
				Lerp(
					Color3.new(0, 0, 0),
					random:
					NextNumber(
						0.18,
						0.34
					)
				)

			slab.CFrame =
				CFrame.fromMatrix(
					result.Position
					+ radial
					* distance
					+ normal
					* 0.055,
					around,
					normal,
					radial
				)
				* CFrame.Angles(
					random:
					NextNumber(
						-0.05,
						0.05
					),
					random:
					NextNumber(
						-0.25,
						0.25
					),
					random:
					NextNumber(
						-0.05,
						0.05
					)
				)
		end

		-- A handful of larger displaced chunks outside the rim sell the force
		-- without turning the crater into a uniform perfect circle.
		local debrisCount =
			8

		for index = 1, debrisCount do
			local angle =
				random:
				NextNumber(
					0,
					math.pi * 2
				)

			local radial =
				(
					tangent
					* math.cos(angle)
					+ bitangent
					* math.sin(angle)
				).Unit

			local size =
				random:
				NextNumber(
					0.55,
					1.20
				)

			local debrisRock =
				Instance.new(
					"Part"
				)

			debrisRock.Name =
				"CraterDebrisRock"

			debrisRock.Size =
				Vector3.new(
					size
					* random:
					NextNumber(
						0.85,
						1.45
					),
					size
					* random:
					NextNumber(
						0.55,
						1.10
					),
					size
					* random:
					NextNumber(
						0.85,
						1.55
					)
				)

			configureVisualPart(
				debrisRock
			)

			debrisRock.CFrame =
				CFrame.new(
					result.Position
					+ radial
					* random:
					NextNumber(
						rimRadius * 1.18,
						rimRadius * 1.55
					)
					+ normal
					* random:
					NextNumber(
						0.18,
						0.55
					)
				)
				* CFrame.Angles(
					random:
					NextNumber(
						-0.45,
						0.45
					),
					random:
					NextNumber(
						0,
						math.pi * 2
					),
					random:
					NextNumber(
						-0.45,
						0.45
					)
				)
		end
	else
		-- Wall impact remains a compact visual scar, but uses physical shards
		-- instead of the old flat plastic disc.
		local radius =
			AIR_M2_WALL_SCAR_DIAMETER
			* 0.30

		local shardCount =
			16

		for index = 1, shardCount do
			local angle =
				(index - 1)
				/ shardCount
				* math.pi
				* 2
				+ random:
				NextNumber(
					-0.16,
					0.16
				)

			local radial =
				(
					tangent
					* math.cos(
						angle
					)
					+ bitangent
					* math.sin(
						angle
					)
				).Unit

			local shard =
				Instance.new(
					"WedgePart"
				)

			shard.Name =
				"WallImpactShard"

			shard.Size =
				Vector3.new(
					random:
					NextNumber(
						1.10,
						2.05
					),
					random:
					NextNumber(
						0.38,
						0.82
					),
					random:
					NextNumber(
						2.10,
						3.55
					)
				)

			configureVisualPart(
				shard
			)

			shard.Color =
				surfaceColor:
				Lerp(
					Color3.new(
						0,
						0,
						0
					),
					0.08
				)

			local position =
				result.Position
				+ radial
				* random:
				NextNumber(
					radius * 0.60,
					radius * 0.96
				)
				+ normal
				* 0.18

			local around =
				normal:
				Cross(
					radial
				).Unit

			shard.CFrame =
				CFrame.fromMatrix(
					position,
					around,
					radial,
					normal
				)
				* CFrame.Angles(
					random:
					NextNumber(
						-0.12,
						0.12
					),
					random:
					NextNumber(
						-0.12,
						0.12
					),
					random:
					NextNumber(
						-0.12,
						0.12
					)
				)
		end

		-- Dense broken center so the wall hit reads as a crater/scar instead of
		-- a few floating shards around an empty point.
		for index = 1, 9 do
			local angle =
				random:NextNumber(0, math.pi * 2)

			local radial =
				(
					tangent * math.cos(angle)
					+ bitangent * math.sin(angle)
				).Unit

			local plate =
				Instance.new("Part")

			plate.Name =
				"WallImpactCenterPlate"

			plate.Size =
				Vector3.new(
					random:NextNumber(1.7, 3.4),
					random:NextNumber(1.4, 3.0),
					random:NextNumber(0.18, 0.42)
				)

			configureVisualPart(plate)

			plate.Color =
				surfaceColor:
				Lerp(
					Color3.new(0, 0, 0),
					random:NextNumber(0.10, 0.24)
				)

			local position =
				result.Position
				+ radial * random:NextNumber(0.0, radius * 0.52)
				+ normal * 0.11

			plate.CFrame =
				CFrame.fromMatrix(
					position,
					tangent,
					bitangent,
					normal
				)
				* CFrame.Angles(
					0,
					0,
					random:NextNumber(-0.55, 0.55)
				)
		end
	end

	if DEBUG then
		print(
			"[LauncherServerCore] AIR M2 VISUAL SPAWN",
			state.id,
			impactKind,
			"parts",
			#folder:GetChildren()
		)
	end

	scheduleImpactVisualFade(folder)
end


local function spawnAirM2GroundVisualFallback(
	state: any,
	result: RaycastResult
)
	local normal =
		result.Normal.Unit

	local tangent,
		bitangent =
		surfaceBasis(normal)

	local visualMaterial,
		surfaceColor =
		getImpactVisualSurface(
			"Ground",
			result
		)

	local folder =
		Instance.new("Folder")

	folder.Name =
		"LauncherM2ImpactVisualFallback"

	folder.Parent =
		workspace

	local radius =
		AIR_M2_GROUND_SCAR_DIAMETER
		* 0.37

	for index = 1, 18 do
		local angle =
			(index - 1)
			/ 18
			* math.pi
			* 2

		local radial =
			(
				tangent * math.cos(angle)
				+ bitangent * math.sin(angle)
			).Unit

		local rock =
			Instance.new("Part")

		rock.Name =
			"FallbackCraterRim"

		rock.Anchored =
			true

		rock.CanCollide =
			false

		rock.CanQuery =
			false

		rock.CanTouch =
			false

		rock.Material =
			visualMaterial

		rock.Color =
			surfaceColor:
			Lerp(
				Color3.new(0, 0, 0),
				0.08
			)

		rock.Size =
			Vector3.new(
				2.9,
				1.5,
				4.0
			)

		local position =
			result.Position
			+ radial * radius
			+ normal * 0.85

		rock.CFrame =
			CFrame.lookAt(
				position,
				position + radial,
				normal
			)

		rock.Parent =
			folder
	end

	scheduleImpactVisualFade(folder)

	if DEBUG then
		warn(
			"[LauncherServerCore] AIR M2 crater fallback visual",
			state.id
		)
	end
end


-- DB:
-- The old forced-upright recovery helper was removed.
-- Full authored victim rotation is no longer corrected merely to protect
-- against the former CCL/GlobalNoTrip FallingDown behavior.

local function applyAirM2ImpactStun(
	state: any,
	impactKind: string,
	result: RaycastResult,
	victimCharacter: Model,
	victimHumanoid: Humanoid,
	victimRoot: BasePart
)
	local stunOwner =
		state.id

	local stunEndsAt =
		time() + AIR_M2_IMPACT_STUN_DURATION

	local existingStunEndsAt =
		victimCharacter:GetAttribute("StunEndsAt")

	local effectiveStunEndsAt =
		stunEndsAt

	if typeof(existingStunEndsAt) == "number" then
		effectiveStunEndsAt =
			math.max(
				effectiveStunEndsAt,
				existingStunEndsAt
			)
	end

	victimCharacter:SetAttribute(
		"LauncherImpactStunned",
		true
	)

	victimCharacter:SetAttribute(
		"LauncherImpactType",
		impactKind
	)

	victimCharacter:SetAttribute(
		"LauncherImpactStunOwner",
		stunOwner
	)

	victimCharacter:SetAttribute(
		"IsStunned",
		true
	)

	victimCharacter:SetAttribute(
		"StunEndsAt",
		effectiveStunEndsAt
	)

	local previousAnchored =
		victimRoot.Anchored

	local previousAutoRotate =
		victimHumanoid.AutoRotate

	victimHumanoid.AutoRotate =
		false

	zeroRoot(victimRoot)

	if impactKind == "Wall" then
		local wallNormal =
			result.Normal.Unit

		local pinPosition =
			result.Position
			+ wallNormal * 1.35

		local upVector =
			Vector3.yAxis

		if math.abs(
			wallNormal:Dot(upVector)
			) > 0.95 then

			upVector =
				Vector3.zAxis
		end

		-- Face OUT from the wall so the victim's back is against it.
		victimRoot.CFrame =
			CFrame.lookAt(
				pinPosition,
				pinPosition + wallNormal,
				upVector
			)
	else
		-- Ground impacts are resolved from a short predictive ray. Snap the
		-- HRP to the actual contact point before anchoring so the stun can
		-- never leave the victim visibly floating above the crater.
		local groundNormal =
			result.Normal.Unit

		local groundPosition =
			result.Position
			+ groundNormal * AIR_M2_GROUND_ROOT_OFFSET

		victimRoot.CFrame =
			CFrame.new(groundPosition)
			* victimRoot.CFrame.Rotation
	end

	victimRoot.Anchored =
		true

	local impactAnimationId =
		if impactKind == "Ground"
		then AIR_M2_VICTIM_GROUND_IMPACT_ANIMATION_ID
		else AIR_M2_VICTIM_WALL_IMPACT_ANIMATION_ID

	local stunAnimationId =
		if impactKind == "Ground"
		then AIR_M2_VICTIM_GROUND_STUN_ANIMATION_ID
		else AIR_M2_VICTIM_WALL_PINNED_ANIMATION_ID

	local impactTrack =
		playOptionalVictimAnimation(
			victimHumanoid,
			impactAnimationId,
			"LauncherM2"
			.. impactKind
			.. "Impact",
			false
		)

	local stunTrack: AnimationTrack? =
		nil

	local released =
		false

	local downedConnection: RBXScriptConnection? =
		nil

	local deathConnection: RBXScriptConnection? =
		nil

	local function releaseImpactStun(
		reason: string
	)
		if released then
			return
		end

		released =
			true

		if downedConnection then
			downedConnection:Disconnect()
			downedConnection = nil
		end

		if deathConnection then
			deathConnection:Disconnect()
			deathConnection = nil
		end

		stopOptionalTrack(impactTrack)
		stopOptionalTrack(stunTrack)

		-- Defensive cleanup: if an authored track ended/restarted between timers,
		-- remove every Launcher-owned victim Action4 track before physics release.
		stopAllLauncherVictimTracks(
			victimHumanoid
		)

		if not victimCharacter.Parent
			or not victimRoot.Parent then

			return
		end

		if victimCharacter:GetAttribute(
			"LauncherImpactStunOwner"
			) ~= stunOwner then

			return
		end

		victimCharacter:SetAttribute(
			"LauncherImpactStunned",
			false
		)

		victimCharacter:SetAttribute(
			"LauncherImpactType",
			nil
		)

		victimCharacter:SetAttribute(
			"LauncherImpactStunOwner",
			nil
		)

		-- DB: preserve the authored orientation. We only clear residual physical
		-- velocity before releasing the real Slam stun.
		zeroRoot(
			victimRoot
		)

		if victimRoot.Anchored then
			victimRoot.Anchored =
				previousAnchored
		end

		if not victimHumanoid.Parent
			or victimHumanoid.Health <= 0 then

			return
		end

		victimHumanoid.AutoRotate =
			previousAutoRotate

		local downedNow =
			victimCharacter:GetAttribute(
				"IsDowned"
			) == true
			or victimCharacter:GetAttribute(
				"DownedActionLocked"
			) == true

		if not downedNow then
			local currentStunEndsAt =
				victimCharacter:GetAttribute(
					"StunEndsAt"
				)

			if typeof(currentStunEndsAt) ~= "number"
				or currentStunEndsAt <=
				stunEndsAt + 0.05 then

				victimCharacter:SetAttribute(
					"IsStunned",
					false
				)

				victimCharacter:SetAttribute(
					"StunEndsAt",
					nil
				)
			end

			-- DB: no forced Humanoid Running/Freefall repair here.
			-- With CCL/GlobalNoTrip removed, Roblox resumes its normal state machine.

		end

		if DEBUG then
			print(
				"[LauncherServerCore] AIR M2 IMPACT RELEASE",
				state.id,
				victimCharacter.Name,
				impactKind,
				reason
			)
		end
	end

	downedConnection =
		victimCharacter:
		GetAttributeChangedSignal(
			"IsDowned"
		):
		Connect(
			function()
				if victimCharacter:GetAttribute(
					"IsDowned"
					) == true then

					releaseImpactStun(
						"Downed"
					)
				end
			end
		)

	deathConnection =
		victimHumanoid.Died:
		Connect(
			function()
				releaseImpactStun(
					"Death"
				)
			end
		)

	task.delay(
		AIR_M2_IMPACT_TO_STUN_ANIMATION_DELAY,
		function()
			if released
				or not victimCharacter.Parent
				or not victimHumanoid.Parent
				or victimHumanoid.Health <= 0
				or victimCharacter:GetAttribute(
					"LauncherImpactStunOwner"
				) ~= stunOwner then

				return
			end

			stopOptionalTrack(impactTrack)

			stunTrack =
				playOptionalVictimAnimation(
					victimHumanoid,
					stunAnimationId,
					"LauncherM2"
					.. impactKind
					.. "Stun",
					impactKind == "Wall"
				)
		end
	)

	task.delay(
		AIR_M2_IMPACT_STUN_DURATION,
		function()
			releaseImpactStun(
				"Timer"
			)
		end
	)
end


local function resolveAirM2SurfaceImpact(
	state: any,
	impactKind: string,
	result: RaycastResult,
	victimCharacter: Model,
	victimHumanoid: Humanoid,
	victimRoot: BasePart,
	travelTrack: AnimationTrack?
)
	stopOptionalTrack(travelTrack)

	local victimPlayer =
		Players:GetPlayerFromCharacter(
			victimCharacter
		)

	local resolution =
		DamageService.Apply({
			TargetCharacter = victimCharacter,
			TargetHumanoid = victimHumanoid,
			TargetPlayer = victimPlayer,
			Attacker = state.attacker,
			Damage = AIR_M2_IMPACT_DAMAGE,
			SourceType = "Launcher",
			SourceId = "Launcher_AirM2_Impact",
		})

	local bodyStillActive =
		resolution.Result == "Damaged"
		or resolution.Result == "DamagedNPC"

	if impactKind == "Ground" then
		playAirM2GroundImpactSound(
			victimRoot
		)
	end

	local gameplayImpactKind =
		if impactKind == "Water"
		then "Ground"
		else impactKind

	if bodyStillActive
		and victimHumanoid.Health > 0 then

		applyAirM2ImpactStun(
			state,
			gameplayImpactKind,
			result,
			victimCharacter,
			victimHumanoid,
			victimRoot
		)
	end

	local visualOk =
		true

	local visualError: any =
		nil

	if impactKind == "Ground"
		or impactKind == "Wall" then

		launcherEvent:FireAllClients(
			"LauncherM2GroundDust",
			result.Position,
			result.Normal,
			state.id,
			state.attacker.UserId,
			victimPlayer and victimPlayer.UserId or 0,
			getImpactSurfaceColor(result)
		)
	end

	if impactKind == "Water" then
		-- No crater on water. This action is the authored-splash integration hook.
		launcherEvent:FireAllClients(
			"LauncherM2WaterImpact",
			result.Position,
			result.Normal,
			0,
			state.attacker.UserId,
			victimPlayer and victimPlayer.UserId or 0
		)

		if DEBUG then
			print(
				"[LauncherServerCore] AIR M2 WATER IMPACT",
				state.id,
				"SplashHook=LauncherM2WaterImpact"
			)
		end
	else
		visualOk, visualError = pcall(
			function()
				spawnAirM2ImpactVisual(
					state,
					impactKind,
					result
				)
			end
		)
	end

	if not visualOk then
		warn(
			"[LauncherServerCore] AIR M2 impact visual failed",
			state.id,
			impactKind,
			visualError
		)

		if impactKind == "Ground" then
			local fallbackOk,
				fallbackError =
				pcall(
					function()
						spawnAirM2GroundVisualFallback(
							state,
							result
						)
					end
				)

			if not fallbackOk then
				warn(
					"[LauncherServerCore] AIR M2 crater fallback failed",
					state.id,
					fallbackError
				)
			end
		end
	end

	if DEBUG then
		print(
			"[LauncherServerCore] AIR M2 "
				.. string.upper(impactKind)
				.. " IMPACT",
			state.id,
			victimCharacter.Name,
			"damage",
			AIR_M2_IMPACT_DAMAGE,
			"stun",
			bodyStillActive
				and AIR_M2_IMPACT_STUN_DURATION
				or 0,
			"result",
			resolution.Result
		)
	end
end


local function scheduleAirM2SurfaceImpact(
	state: any,
	victimCharacter: Model,
	victimHumanoid: Humanoid,
	victimRoot: BasePart
)
	local startedAt =
		time()

	local resolved =
		false

	local previousPosition =
		victimRoot.Position

	local raycastParams =
		RaycastParams.new()

	raycastParams.FilterType =
		Enum.RaycastFilterType.Exclude

	local ignoredInstances: {Instance} = {
		victimCharacter,
	}

	if state.attackerCharacter then
		table.insert(
			ignoredInstances,
			state.attackerCharacter
		)
	end

	raycastParams.FilterDescendantsInstances =
		ignoredInstances

	raycastParams.RespectCanCollide =
		true

	local travelTrack =
		playOptionalVictimAnimation(
			victimHumanoid,
			AIR_M2_VICTIM_AIR_TRAVEL_ANIMATION_ID,
			"LauncherM2AirTravel",
			true
		)

	local connection: RBXScriptConnection?

	local function filterCharacterHit(
		result: RaycastResult?
	): RaycastResult?
		if not result then
			return nil
		end

		local struckEntity =
			CombatEntityService.ResolveFromInstance(
				result.Instance
			)

		if struckEntity then
			table.insert(
				ignoredInstances,
				struckEntity.Character
			)

			raycastParams.FilterDescendantsInstances =
				ignoredInstances

			return nil
		end

		return result
	end

	local function probeWallAlongDirection(
		origin: Vector3,
		direction: Vector3,
		distance: number
	): RaycastResult?

		local flatDirection =
			Vector3.new(
				direction.X,
				0,
				direction.Z
			)

		if flatDirection.Magnitude < 0.001 then
			return nil
		end

		flatDirection =
			flatDirection.Unit

		local right =
			Vector3.new(
				-flatDirection.Z,
				0,
				flatDirection.X
			)

		local offsets = {
			Vector3.zero,
			Vector3.new(0, 1.35, 0),
			Vector3.new(0, -1.15, 0),
			right * 1.05,
			-right * 1.05,
		}

		local bestResult: RaycastResult? =
			nil

		for _, offset in ipairs(offsets) do
			local result =
				filterCharacterHit(
					workspace:Raycast(
						origin + offset,
						flatDirection * distance,
						raycastParams
					)
				)

			if result
				and result.Normal.Y < AIR_M2_GROUND_NORMAL_Y_MIN then

				if not bestResult
					or result.Distance < bestResult.Distance then

					bestResult =
						result
				end
			end
		end

		return bestResult
	end

	local function resolveResult(
		result: RaycastResult,
		elapsed: number,
		source: string
	)
		if resolved then
			return
		end

		resolved = true

		if connection then
			connection:Disconnect()
		end

		local impactKind =
			if result.Material == Enum.Material.Water
			then "Water"
			elseif result.Normal.Y >= AIR_M2_GROUND_NORMAL_Y_MIN
			then "Ground"
			else "Wall"

		if DEBUG then
			print(
				"[LauncherServerCore] AIR M2 CONTACT",
				state.id,
				impactKind,
				"source",
				source,
				"elapsed",
				string.format("%.3f", elapsed),
				"root",
				victimRoot.Position,
				"surface",
				result.Position
			)
		end

		resolveAirM2SurfaceImpact(
			state,
			impactKind,
			result,
			victimCharacter,
			victimHumanoid,
			victimRoot,
			travelTrack
		)
	end

	connection =
		RunService.Heartbeat:
		Connect(
			function(
				deltaTime: number
			)
				if resolved then
					return
				end

				if not victimCharacter.Parent
					or not victimRoot.Parent
					or victimHumanoid.Health <= 0 then

					resolved = true
					stopOptionalTrack(travelTrack)

					if connection then
						connection:Disconnect()
					end

					return
				end

				local elapsed =
				time() - startedAt

				local currentPosition =
				victimRoot.Position

				local velocity =
				victimRoot.AssemblyLinearVelocity

				local launchDirection =
				state.m2LaunchDirection

				if typeof(launchDirection) == "Vector3" then
					local earlyWall =
					probeWallAlongDirection(
						currentPosition,
						launchDirection,
						AIR_M2_EARLY_WALL_PROBE_DISTANCE
					)

					if earlyWall then
						resolveResult(
							earlyWall,
							elapsed,
							"EarlyWallLaunchDirection"
						)
						return
					end
				end

				if elapsed < AIR_M2_IMPACT_MIN_DELAY then
					previousPosition = currentPosition
					return
				end

				local hitResult: RaycastResult? =
				nil

				local hitSource =
				"None"

				-- 1) Swept center ray catches true tunneling through thin geometry.
				local displacement =
				currentPosition - previousPosition

				if displacement.Magnitude > 0.05 then
					hitResult =
					filterCharacterHit(
						workspace:Raycast(
							previousPosition,
							displacement,
							raycastParams
						)
					)

					if hitResult then
						hitSource = "Swept"
					end
				end

				-- 2) Dedicated wall-volume probe. Physics stops the R6 body BEFORE the
				-- HRP center reaches a wall, so a center-only ray intermittently misses it.
				if not hitResult then
					local wallResult: RaycastResult? =
					nil

					if typeof(launchDirection) == "Vector3" then
						wallResult =
						probeWallAlongDirection(
							currentPosition,
							launchDirection,
							AIR_M2_WALL_PROXIMITY_DISTANCE
						)
					end

					if not wallResult then
						local flatVelocity =
						Vector3.new(
							velocity.X,
							0,
							velocity.Z
						)

						if flatVelocity.Magnitude > 1 then
							wallResult =
							probeWallAlongDirection(
								currentPosition,
								flatVelocity,
								AIR_M2_WALL_PROXIMITY_DISTANCE
							)
						end
					end

					if wallResult then
						hitResult =
						wallResult

						hitSource =
						"WallProximityRobust"
					end
				end

				-- 3) Dedicated ground-volume probe. It does NOT depend on FloorMaterial,
				-- which is exactly what was making some legitimate impacts disappear.
				if not hitResult
					and velocity.Y <= 8 then

					local groundOrigin =
					currentPosition + Vector3.new(0, 0.25, 0)

					local groundResult =
					filterCharacterHit(
						workspace:Raycast(
							groundOrigin,
							Vector3.new(
								0,
								-AIR_M2_GROUND_PROXIMITY_DISTANCE,
								0
							),
							raycastParams
						)
					)

					if groundResult
						and groundResult.Normal.Y >= AIR_M2_GROUND_NORMAL_Y_MIN then

						hitResult = groundResult
						hitSource = "GroundProximity"
					end
				end

				-- 4) Small prediction only; never the old multi-stud pre-hit ray.
				if not hitResult
					and velocity.Magnitude > 4 then

					local frameTravel =
					velocity.Magnitude * deltaTime

					local probeDistance =
					math.min(
						AIR_M2_FORWARD_PROBE_MAX_DISTANCE,
						frameTravel + AIR_M2_FORWARD_PROBE_PADDING
					)

					if probeDistance > 0.08 then
						hitResult =
						filterCharacterHit(
							workspace:Raycast(
								currentPosition,
								velocity.Unit * probeDistance,
								raycastParams
							)
						)

						if hitResult then
							hitSource = "Forward"
						end
					end
				end

				previousPosition = currentPosition

				if hitResult then
					resolveResult(
						hitResult,
						elapsed,
						hitSource
					)
					return
				end

				if elapsed <= AIR_M2_IMPACT_TIMEOUT then
					return
				end

				-- Final recovery probe: by two seconds a downward M2 should have hit
				-- something. Recover a nearby real surface instead of silently losing
				-- the crater/damage event because Humanoid contact replication was late.
				local recoveryResult: RaycastResult? =
				nil

				local flatVelocity =
				Vector3.new(
					velocity.X,
					0,
					velocity.Z
				)

				local recoveryDirection =
				if typeof(launchDirection) == "Vector3"
				then launchDirection
				else flatVelocity

				if recoveryDirection.Magnitude > 0.001 then
					local wallRecovery =
					probeWallAlongDirection(
						currentPosition,
						recoveryDirection,
						AIR_M2_TIMEOUT_WALL_RECOVERY_DISTANCE
					)

					if wallRecovery then
						recoveryResult =
						wallRecovery
					end
				end

				if not recoveryResult then
					local groundRecovery =
					filterCharacterHit(
						workspace:Raycast(
							currentPosition + Vector3.new(0, 1.0, 0),
							Vector3.new(
								0,
								-AIR_M2_TIMEOUT_GROUND_RECOVERY_DISTANCE,
								0
							),
							raycastParams
						)
					)

					if groundRecovery
						and groundRecovery.Normal.Y >= AIR_M2_GROUND_NORMAL_Y_MIN then

						recoveryResult = groundRecovery
					end
				end

				if recoveryResult then
					resolveResult(
						recoveryResult,
						elapsed,
						"TimeoutRecovery"
					)
				else
					resolved = true
					stopOptionalTrack(travelTrack)

					if connection then
						connection:Disconnect()
					end

					if DEBUG then
						warn(
							"[LauncherServerCore] AIR M2 CONTACT TIMEOUT no surface",
							state.id,
							victimCharacter.Name,
							victimRoot.Position
						)
					end
				end
			end
		)
end


-- ============================================================
-- AIR COMBO TRANSITION - PLAYER + NPC
-- ============================================================

local function endAirCombo(
	airComboId: number,
	reason: string,
	victimReleaseVelocity: Vector3?,
	attackerReleaseVelocity: Vector3?
)
	local state = airCombos[airComboId]
	if not state or state.finished then
		return
	end

	state.finished = true
	destroyNoCollision(state)

	if state.npcTransition then
		state.npcTransition:Stop(reason)
		state.npcTransition = nil
	end

	stopOptionalTrack(
		state.victimLaunchTrack
	)
	state.victimLaunchTrack =
		nil

	local attackerCharacter, _attackerHumanoid, attackerRoot = getAliveCharacter(state.attacker)
	if attackerRoot then
		if typeof(attackerReleaseVelocity) == "Vector3" then
			attackerRoot.AssemblyLinearVelocity = attackerReleaseVelocity
			attackerRoot.AssemblyAngularVelocity = Vector3.zero
		else
			zeroRoot(attackerRoot)
		end
	end
	releaseAirLock(state, attackerCharacter or state.attackerCharacter)

	-- Always restore visibility on every client if the aerial sequence ends
	-- through M2, timeout, substitution, death or any other cancellation path.
	launcherEvent:FireAllClients(
		"LauncherBodyFlickerFX",
		"Cancel",
		state.id,
		state.attacker.UserId
	)

	if state.attacker.Parent then
		launcherEvent:FireClient(
			state.attacker,
			"AirEnd",
			state.id,
			reason,
			attackerReleaseVelocity
		)
	end

	local victimEntity = state.victimEntity
	local victimCharacter = victimEntity and victimEntity.Character or nil
	local victimRoot = victimEntity and victimEntity.Root or nil

	if victimRoot and victimRoot.Parent then
		if typeof(victimReleaseVelocity) == "Vector3" then
			victimRoot.AssemblyLinearVelocity =
				victimReleaseVelocity

			victimRoot.AssemblyAngularVelocity =
				Vector3.zero
		else
			zeroRoot(victimRoot)
		end
	end
	releaseAirLock(state, victimCharacter)

	local victimPlayer = victimEntity and victimEntity.Player or nil
	if victimPlayer and victimPlayer.Parent then
		launcherEvent:FireClient(
			victimPlayer,
			"AirEnd",
			state.id,
			reason,
			victimReleaseVelocity
		)
	end

	airCombos[airComboId] = nil

	if DEBUG then
		print("[LauncherServerCore] AIR END", airComboId, reason)
	end
end


launcherAirComboControl.Event:
	Connect(
		function(
			action: string,
			subjectPlayer: Player?,
			airComboId: number?
		)
			if not subjectPlayer
				or typeof(airComboId) ~= "number" then

				return
			end

			local state =
			airCombos[airComboId]

			if not state
				or state.finished then

				return
			end

			if action == "M1_5Confirmed" then
				if state.attacker ~=
					subjectPlayer then

					return
				end

				if DEBUG then
					print(
						"[LauncherServerCore] AIR FINISH REQUEST",
						airComboId,
						subjectPlayer.Name,
						"reason M1_5Confirmed"
					)
				end

				endAirCombo(
					airComboId,
					"M1_5Complete",
					nil,
					nil
				)

			elseif action == "VictimSubstituted" then
				local victimPlayer =
				state.victimEntity
				and state.victimEntity.Player
				or nil

				if victimPlayer ~=
					subjectPlayer then

					return
				end

				if DEBUG then
					print(
						"[LauncherServerCore] AIR BREAK",
						airComboId,
						subjectPlayer.Name,
						"reason Substitution"
					)
				end

				endAirCombo(
					airComboId,
					"Substitution",
					nil
				)
			end
		end
	)

local function beginAirCombo(
	attacker: Player,
	victimEntity: any,
	attackerCharacter: Model,
	attackerRoot: BasePart
)
	local victimCharacter = victimEntity.Character :: Model
	local victimHumanoid = victimEntity.Humanoid :: Humanoid
	local victimRoot = victimEntity.Root :: BasePart
	local victimPlayer = victimEntity.Player :: Player?

	nextAirComboId += 1
	local airComboId = nextAirComboId

	local direction = horizontalUnit(victimRoot.Position - attackerRoot.Position, attackerRoot.CFrame.LookVector)
	local midpointY = math.max(attackerRoot.Position.Y, victimRoot.Position.Y)
	local victimTargetPosition =
		Vector3.new(
			victimRoot.Position.X,
			midpointY + AIR_RISE_HEIGHT,
			victimRoot.Position.Z
		)
		+ direction * AIR_VICTIM_FORWARD_DISTANCE

	local attackerTargetPosition =
		victimTargetPosition
	- direction * AIR_PAIR_DISTANCE
		+ Vector3.new(
			0,
			-AIR_ATTACKER_LOWER_OFFSET,
			0
		)
	local victimTarget = CFrame.lookAt(victimTargetPosition, attackerTargetPosition, Vector3.yAxis)
	local attackerTarget = CFrame.lookAt(attackerTargetPosition, victimTargetPosition, Vector3.yAxis)

	local serverNow = workspace:GetServerTimeNow()
	local transitionStartsAt = serverNow + AIR_SYNC_LEAD

	local state = {
		id = airComboId,
		attacker = attacker,
		attackerCharacter = attackerCharacter,
		victimEntity = victimEntity,
		transitionStartsAt = transitionStartsAt,
		serverLockEndsAt = time() + AIR_HARD_TIMEOUT,
		finished = false,
		noCollision = {},
		npcTransition = nil,
		victimLaunchTrack = nil,
		previousStuns = {},
		m2Consumed = false,
		m2Preparing = false,
		m2ImpactVFXSent = false,
		m2ReleaseExpiresAt = nil,
		holdReadyAt = nil,
		holdExpiresAt = nil,
		bodyFlickerReadyFXSent = false,
		bodyFlickerDisappearFXSent = false,
		bodyFlickerArriveFXSent = false,
	}

	airCombos[airComboId] = state
	createNoCollision(state, attackerCharacter, victimCharacter)
	setAirLock(state, attackerCharacter, "Attacker")
	setAirLock(state, victimCharacter, "Victim")

	-- Server-authoritative pairing for aerial M1.
	-- CombatServer reads this ObjectValue instead of depending on the
	-- attacker's replicated HRP having already converged to the air hold.
	setLauncherAirTarget(
		attackerCharacter,
		victimCharacter
	)

	victimCharacter:SetAttribute(
		"AirM1Allowed",
		false
	)

	zeroRoot(attackerRoot)
	zeroRoot(victimRoot)

	-- Victim reaction is visual-only and starts on the exact same server clock
	-- as the approved 0.48s Uplift transition. No movement speed is changed.
	local victimLaunchDelay =
		math.max(
			0,
			transitionStartsAt
			- workspace:GetServerTimeNow()
		)

	task.delay(
		victimLaunchDelay,
		function()
			local current =
				airCombos[
			airComboId
			]

			if not current
				or current.finished
				or not victimHumanoid.Parent
				or victimHumanoid.Health <= 0 then

				return
			end

			stopOptionalTrack(
				current.victimLaunchTrack
			)

			current.victimLaunchTrack =
				playOptionalVictimAnimation(
					victimHumanoid,
					AIR_UPLIFT_VICTIM_LAUNCH_ANIMATION_ID,
					"LauncherUpliftVictimLaunch",
					false
				)

			if DEBUG then
				print(
					"[LauncherServerCore] UPLIFT VICTIM ANIM",
					airComboId,
					victimCharacter.Name,
					AIR_UPLIFT_VICTIM_LAUNCH_ANIMATION_ID,
					"transition",
					AIR_TRANSITION_DURATION
				)
			end
		end
	)

	launcherEvent:FireClient(
		attacker,
		"AirBegin",
		airComboId,
		"Attacker",
		transitionStartsAt,
		AIR_TRANSITION_DURATION,
		AIR_HOLD_DURATION,
		attackerRoot.CFrame,
		attackerTarget
	)

	if victimPlayer then
		launcherEvent:FireClient(
			victimPlayer,
			"AirBegin",
			airComboId,
			"Victim",
			transitionStartsAt,
			AIR_TRANSITION_DURATION,
			AIR_PRE_HOLD_MAX_DURATION
				+ AIR_HOLD_DURATION,
			victimRoot.CFrame,
			victimTarget
		)
	else
		state.npcTransition = CombatMotionService.BeginServerTransition(
			victimCharacter,
			victimHumanoid,
			victimRoot,
			transitionStartsAt,
			AIR_TRANSITION_DURATION,
			AIR_PRE_HOLD_MAX_DURATION
				+ AIR_HOLD_DURATION,
			victimRoot.CFrame,
			victimTarget
		)
	end

	-- If the attacker never reaches BodyFlicker/arrival, release the pair.
	task.delay(
		AIR_SYNC_LEAD
			+ AIR_TRANSITION_DURATION
			+ AIR_PRE_HOLD_MAX_DURATION,
		function()

			local current =
				airCombos[airComboId]

			if current
				and not current.finished
				and typeof(current.holdReadyAt) ~= "number" then

				endAirCombo(
					airComboId,
					"FollowTimeout",
					nil
				)
			end
		end
	)

	task.delay(AIR_HARD_TIMEOUT, function()
		if airCombos[airComboId] then
			endAirCombo(airComboId, "HardTimeout", nil)
		end
	end)

	if DEBUG then
		print(
			"[LauncherServerCore] AIR BEGIN",
			airComboId,
			attacker.Name,
			"->",
			victimCharacter.Name,
			"entityType",
			victimEntity.Kind,
			"motionOwner",
			victimPlayer and "Client" or "Server",
			"height",
			AIR_RISE_HEIGHT,
			"pairDistance",
			AIR_PAIR_DISTANCE,
			"hold",
			AIR_HOLD_DURATION
		)
	end
end


local function getAirM2ContactVFXPosition(
	victimRoot: BasePart,
	direction: Vector3
): Vector3
	-- The previous implementation spawned Slam VFX at victimRoot.Position,
	-- which places most of the particles inside the victim body. Put the
	-- authored contact burst on the attacker-facing surface instead.
	local flatDirection =
		horizontalUnit(
			direction,
			victimRoot.CFrame.LookVector
		)

	local horizontalExtent =
		math.max(
			victimRoot.Size.X,
			victimRoot.Size.Z
		)

	local surfaceOffset =
		horizontalExtent * 0.5
		+ 0.70

	return victimRoot.Position
	- flatDirection * surfaceOffset
		+ Vector3.new(0, 0.55, 0)
end

local function broadcastAirM2ContactImpact(
	airState: any
)
	if airState.m2ImpactVFXSent == true then
		return
	end

	local attackerCharacter,
		_attackerHumanoid,
		attackerRoot =
		getAliveCharacter(
			airState.attacker
		)

	local victimEntity = airState.victimEntity
	local victimCharacter =
		victimEntity and victimEntity.Character
	local victimRoot =
		victimEntity and victimEntity.Root

	if not attackerCharacter
		or not attackerRoot
		or not victimCharacter
		or not victimRoot
		or not victimRoot.Parent then
		return
	end

	local direction =
		horizontalUnit(
			victimRoot.Position - attackerRoot.Position,
			attackerRoot.CFrame.LookVector
		)

	local victimPlayer =
		victimEntity.Player :: Player?

	airState.m2ImpactVFXSent = true

	-- Authored kick hit SFX at the exact M2 Impact-marker route.
	playAirM2KickImpactSound(
		victimRoot
	)

	local contactVFXPosition =
		getAirM2ContactVFXPosition(
			victimRoot,
			direction
		)

	launcherEvent:FireAllClients(
		"LauncherM2Impact",
		contactVFXPosition,
		direction,
		airState.id,
		airState.attacker.UserId,
		victimPlayer and victimPlayer.UserId or 0
	)

	if DEBUG then
		print(
			"[LauncherServerCore] AIR M2 CONTACT VFX",
			airState.id,
			"Shoot-01+Wind-01",
			"position",
			contactVFXPosition
		)
	end
end


local function reinforceAirM2Release(
	victimCharacter: Model,
	victimHumanoid: Humanoid,
	victimRoot: BasePart,
	releaseVelocity: Vector3
)
	task.spawn(
		function()
			for frame = 1, AIR_M2_RELEASE_REINFORCE_FRAMES do
				RunService.Heartbeat:Wait()

				if not victimCharacter.Parent
					or not victimRoot.Parent
					or victimHumanoid.Health <= 0
					or victimCharacter:GetAttribute(
						"LauncherImpactStunned"
					) == true then

					return
				end

				victimHumanoid:ChangeState(
					Enum.HumanoidStateType.Freefall
				)

				victimRoot.AssemblyLinearVelocity =
					releaseVelocity

				victimRoot.AssemblyAngularVelocity =
					Vector3.zero

				if DEBUG then
					print(
						"[LauncherServerCore] AIR M2 RELEASE REINFORCE",
						frame,
						victimCharacter.Name,
						victimRoot.AssemblyLinearVelocity
					)
				end
			end
		end
	)
end


local function publishLauncherCooldown(
	character: Model,
	startsAt: number
)
	local endsAt =
		startsAt
		+ LAUNCHER_COOLDOWN

	character:SetAttribute(
		"LauncherCooldownEndsAt",
		endsAt
	)

	character:SetAttribute(
		"CoreCooldown_Launcher_Label",
		"Launcher"
	)

	character:SetAttribute(
		"CoreCooldown_Launcher_StartsAt",
		startsAt
	)

	character:SetAttribute(
		"CoreCooldown_Launcher_EndsAt",
		endsAt
	)
end


-- ============================================================
-- REQUESTS
-- ============================================================

launcherEvent.OnServerEvent:
	Connect(
		function(
			player: Player,
			action: string,
			sequence: any,
			clientTimestamp: any
		)

			if typeof(sequence) ~=
				"number" then

				return
			end


			if action == "BodyFlickerVisual" then
				local airComboId =
				sequence

				local stage =
				clientTimestamp

				local airState =
				airCombos[airComboId]

				if not airState
					or airState.finished
					or airState.attacker ~= player
					or typeof(stage) ~= "string" then

					return
				end

				if stage == "Ready" then
					if airState.bodyFlickerReadyFXSent then
						return
					end

					airState.bodyFlickerReadyFXSent =
					true

				elseif stage == "Disappear" then
					if airState.bodyFlickerDisappearFXSent
						or not airState.bodyFlickerReadyFXSent then
						return
					end

					airState.bodyFlickerDisappearFXSent =
					true
				else
					return
				end

				launcherEvent:FireAllClients(
					"LauncherBodyFlickerFX",
					stage,
					airComboId,
					player.UserId
				)

				if DEBUG then
					print(
						"[LauncherServerCore] BODY FLICKER FX",
						airComboId,
						stage,
						player.Name
					)
				end

				return
			end


			if action == "AirFollowArrived" then
				local airComboId =
				sequence

				local airState =
				airCombos[airComboId]

				if not airState
					or airState.finished
					or airState.attacker ~= player
					or typeof(airState.holdReadyAt) == "number" then

					return
				end

				local now =
				workspace:
				GetServerTimeNow()

				airState.holdReadyAt =
				now

				airState.holdExpiresAt =
				now
				+ AIR_HOLD_DURATION

				if not airState.bodyFlickerArriveFXSent then
					airState.bodyFlickerArriveFXSent =
					true

					launcherEvent:FireAllClients(
						"LauncherBodyFlickerFX",
						"Arrive",
						airComboId,
						player.UserId
					)
				end

				local expectedExpiresAt =
				airState.holdExpiresAt

				task.delay(
					AIR_HOLD_DURATION,
					function()

						local current =
						airCombos[airComboId]

						if not current
							or current.finished
							or current.holdExpiresAt ~=
							expectedExpiresAt then

							return
						end

						if workspace:GetServerTimeNow()
							>= expectedExpiresAt then

							endAirCombo(
								airComboId,
								"WindowExpired",
								nil
							)
						end
					end
				)

				if DEBUG then
					print(
						"[LauncherServerCore] AIR HOLD TIMER START",
						airComboId,
						player.Name,
						"duration",
						AIR_HOLD_DURATION
					)
				end

				return
			end


			if action == "AirM2Windup" then
				local airComboId = sequence
				local airState = airCombos[airComboId]

				if not airState
					or airState.finished
					or airState.attacker ~= player
					or airState.m2Consumed == true
					or airState.m2Preparing == true then
					return
				end

				local now =
				workspace:GetServerTimeNow()

				local holdStartsAt =
				airState.holdReadyAt

				local holdEndsAt =
				airState.holdExpiresAt

				if typeof(holdStartsAt) ~= "number"
					or typeof(holdEndsAt) ~= "number"
					or now < holdStartsAt - 0.08
					or now > holdEndsAt + 0.10 then

					return
				end

				airState.m2Preparing = true
				airState.m2ReleaseExpiresAt = now + 2.0

				local attackerCharacter = airState.attackerCharacter
				if attackerCharacter and attackerCharacter.Parent then
					attackerCharacter:SetAttribute("AirM1Allowed", false)
				end

				if DEBUG then
					print(
						"[LauncherServerCore] AIR M2 WINDUP committed",
						airComboId,
						player.Name
					)
				end

				return
			end


			if action == "AirM2Impact" then
				local airComboId = sequence
				local airState = airCombos[airComboId]

				if not airState
					or airState.finished
					or airState.attacker ~= player
					or airState.m2Consumed == true
					or airState.m2Preparing ~= true
					or airState.m2ImpactVFXSent == true then
					return
				end

				broadcastAirM2ContactImpact(airState)
				return
			end


			if action == "AirM2" then
				local airComboId =
				sequence

				local airState =
				airCombos[
				airComboId
				]

				if not airState
					or airState.finished
					or airState.attacker ~= player
					or airState.m2Consumed == true then

					return
				end

				local now =
				workspace:
				GetServerTimeNow()

				local holdStartsAt =
				airState.holdReadyAt

				local holdEndsAt =
				airState.holdExpiresAt

				local committedReleaseValid =
				airState.m2Preparing == true
				and typeof(airState.m2ReleaseExpiresAt) == "number"
				and now <= airState.m2ReleaseExpiresAt

				if not committedReleaseValid
					and (
						typeof(holdStartsAt) ~= "number"
						or typeof(holdEndsAt) ~= "number"
						or now < holdStartsAt - 0.08
						or now > holdEndsAt + 0.10
					) then

					return
				end

				local attackerCharacter,
				_attackerHumanoid,
				attackerRoot =
				getAliveCharacter(
					player
				)

				local victimEntity =
				airState.victimEntity

				local victimCharacter =
				victimEntity
				and victimEntity.Character
				or nil

				local victimHumanoid =
				victimEntity
				and victimEntity.Humanoid
				or nil

				local victimRoot =
				victimEntity
				and victimEntity.Root
				or nil

				if not attackerCharacter
					or not attackerRoot
					or not victimCharacter
					or not victimCharacter.Parent
					or not victimHumanoid
					or victimHumanoid.Health <= 0
					or not victimRoot
					or not victimRoot.Parent then

					endAirCombo(
						airComboId,
						"AirM2InvalidPair",
						nil,
						nil
					)

					return
				end

				airState.m2Consumed =
				true

				airState.m2Preparing =
				false

				local direction =
				horizontalUnit(
					victimRoot.Position
					- attackerRoot.Position,
					attackerRoot.CFrame.LookVector
				)

				airState.m2LaunchDirection =
				direction

				local knockbackReceivedMultiplier =
				StatusCombatModifierService
				.GetKnockbackReceivedMultiplier(
					victimCharacter
				)

				local releaseVelocity =
				Vector3.new(
					direction.X
					* AIR_M2_HORIZONTAL_SPEED
					* knockbackReceivedMultiplier,
					-AIR_M2_DOWNWARD_SPEED,
					direction.Z
					* AIR_M2_HORIZONTAL_SPEED
					* knockbackReceivedMultiplier
				)

				if DEBUG then
					print(
						"[LauncherServerCore] AIR M2",
						airComboId,
						player.Name,
						"->",
						victimCharacter.Name,
						"velocity",
						releaseVelocity
					)
				end

				-- Victim launches at the authored Release marker, but the attacker
				-- remains held in the aerial pose until their M2 animation actually ends.
				-- The local LauncherController keeps its AlignPosition/Orientation alive
				-- after AirEnd(AirM2) and releases them on AnimationTrack.Ended.
				local attackerDropVelocity: Vector3? =
				nil

				-- If the authored Impact marker was ever lost, guarantee the contact
				-- visuals still occur before the release on every client.
				if airState.m2ImpactVFXSent ~= true then
					broadcastAirM2ContactImpact(airState)
				end

				-- Authored Release VFX is broadcast on the same authoritative frame
				-- that the victim launch velocity is committed.
				local releaseVFXPosition =
				getAirM2ContactVFXPosition(
					victimRoot,
					direction
				)

				launcherEvent:FireAllClients(
					"LauncherM2Release",
					releaseVFXPosition,
					direction,
					airComboId,
					player.UserId,
					victimEntity.Player and victimEntity.Player.UserId or 0
				)

				scheduleAirM2SurfaceImpact(
					airState,
					victimCharacter,
					victimHumanoid,
					victimRoot
				)

				endAirCombo(
					airComboId,
					"AirM2",
					releaseVelocity,
					attackerDropVelocity
				)

				reinforceAirM2Release(
					victimCharacter,
					victimHumanoid,
					victimRoot,
					releaseVelocity
				)

				return
			end


			if action ==
				"Start" then

				local character,
				humanoid,
				_root =
				getAliveCharacter(
					player
				)


				if not character
					or not humanoid then

					return
				end


				if character:GetAttribute(
					"AirComboServerActive"
					) == true
					or character:GetAttribute(
						"IsStunned"
					) == true
					or downedLocked(
						character
					) then

					return
				end


				local now =
				workspace:
				GetServerTimeNow()


				local serverCooldown =
				cooldownUntil[
				player
				]
				or -math.huge


				if now <
					serverCooldown then

					return
				end


				cooldownUntil[
				player
				] =
				now
				+ SERVER_COOLDOWN


				publishLauncherCooldown(
					character,
					now
				)


				launcherStates[
				player
				] = {
					sequence =
					sequence,

					startedAt =
					now,

					hitConsumed =
					false,
				}


				if DEBUG then

					print(
						"[LauncherServerCore] START",
						player.Name,
						sequence
					)
				end


				return
			end


			local state =
			launcherStates[
			player
			]


			if not state
				or state.sequence ~=
				sequence then

				return
			end


			if action ==
				"Cancel" then

				launcherStates[
				player
				] =
				nil

				return
			end


			if action ~=
				"Hit"
				or state.hitConsumed then

				return
			end


			state.hitConsumed =
			true


			local character,
			humanoid,
			root =
			getAliveCharacter(
				player
			)


			if not character
				or not humanoid
				or not root then

				launcherStates[
				player
				] =
				nil

				return
			end


			local now =
			workspace:
			GetServerTimeNow()

			local elapsed =
			now
			- state.startedAt


			if elapsed <
				MIN_HIT_AFTER_START
				or elapsed >
				MAX_HIT_AFTER_START then

				if DEBUG then

					print(
						"[LauncherServerCore] HIT REJECT timing",
						player.Name,
						string.format(
							"%.3f",
							elapsed
						)
					)
				end


				launcherEvent:
				FireClient(
					player,
					"HitMissed",
					sequence
				)


				launcherStates[
				player
				] =
				nil

				return
			end


			if typeof(clientTimestamp) ==
				"number" then

				local rewind =
				math.clamp(
					now
					- clientTimestamp,
					0,
					MAX_CLIENT_TIMESTAMP_REWIND
				)


				if DEBUG then

					print(
						"[LauncherServerCore] HIT marker rewind",
						player.Name,
						string.format(
							"%.3f",
							rewind
						)
					)
				end
			end


			local candidates =
			collectCandidates(
				character,
				root
			)


			local chosen: Candidate? =
			nil


			for _,
				candidate in ipairs(
					candidates
				) do

				if hasLineOfSight(
					character,
					candidate.character,
					root,
					candidate.root
					) then

					chosen =
					candidate

					break
				end
			end


			if not chosen then

				-- True Uplift whiff: no valid target was found.
				playLauncherMissSound(
					root
				)

				launcherEvent:
				FireClient(
					player,
					"HitMissed",
					sequence
				)


				launcherStates[
				player
				] =
				nil


				if DEBUG then

					print(
						"[LauncherServerCore] MISS",
						player.Name
					)
				end


				return
			end


			local resolution =
			DamageService.Apply({
				TargetCharacter =
				chosen.character,

				TargetHumanoid =
				chosen.humanoid,

				TargetPlayer =
				chosen.player,

				Attacker =
				player,

				Damage =
				LAUNCHER_DAMAGE,

				SourceType =
				"Launcher",

				SourceId =
				"Launcher_Uplift",

				Armor =
				LAUNCHER_ARMOR_PROFILE,
			})


			local result =
			resolution.Result


			if result ~= "Substituted" then
				playLauncherHitSound(chosen.root)
				emitLauncherImpactVFX(player, chosen.player, root, chosen.root)
			end


			if result ==
				"Substituted"
				or result ==
				"Downed"
				or result ==
				"AlreadyDowned"
				or result ==
				"BeingExecuted"
				or chosen.humanoid.Health <= 0 then

				launcherEvent:
				FireClient(
					player,
					"HitMissed",
					sequence
				)


				launcherStates[
				player
				] =
				nil


				if DEBUG then

					print(
						"[LauncherServerCore] NO AIR",
						player.Name,
						"result",
						result
					)
				end


				return
			end


			launcherEvent:
			FireClient(
				player,
				"HitConfirmed",
				sequence
			)

			launcherStates[player] = nil

			if not chosen.entity.CanLaunch then
				if DEBUG then
					print(
						"[LauncherServerCore] HIT NO LAUNCH",
						player.Name,
						"->",
						chosen.character.Name,
						"entityType",
						chosen.entity.Kind,
						"profile",
						chosen.entity.Profile
					)
				end
				return
			end

			beginAirCombo(
				player,
				chosen.entity,
				character,
				root
			)
		end
	)


Players.PlayerRemoving:
	Connect(
		function(
			player: Player
		)

			launcherStates[
			player
			] =
			nil

			cooldownUntil[
			player
			] =
			nil


			for airComboId,
				state in pairs(
					airCombos
				) do

				if state.attacker ==
					player
					or (
						state.victimEntity
						and state.victimEntity.Player == player
					) then

					endAirCombo(
						airComboId,
						"PlayerRemoving",
						nil
					)
				end
			end
		end
	)


print(
	"[LauncherServerCore] READY v3.7 ReliableUpliftHitTiming + DB CCLCleanup + StatusCombatModifiers SlamVFXMultiplayer + GroundDust + WaterHook + Cooldown4s"
		.. " | PlayerAir=ON"
		.. " | HumanoidNPCAir=ON"
		.. " | MonsterProfiles=ON"
		.. " | SharedHitFeedback=ON"
		.. " | Damage=4"
		.. " | Hitbox=8.5x7x10"
		.. " | RiseHeight=20 | VictimForward=8"
		.. " | PairDistance=4.5"
		.. " | Transition=0.48"
		.. " | HoldWindow=3.75_STARTS_ON_ATTACKER_ARRIVAL | PreHoldMax=3.00"
		.. " | AirM1=ON_SERVER_PAIRED_TARGET | M1_5EndsAir=ON"
		.. " | UpliftVictimAnim=113069702431140_27F | AirTravelAnim=131120495295267 | GroundImpactAnim=90447032048524 | GroundStunAnim=98446797314691 | GroundRelease=NO_LOOP+HARD_TRACK_CLEAN+NORMAL_STATE_MACHINE | AirM2=AUTHORED Impact+Release | AttackerFallsOnAnimationEnd=ON | ReplaySafeClient=EXPECTED | H=110 D=75 impactDamage=8 impactStun=1.00 ground+wall | GroundCrater=MEGA_CONTINUOUS_ROCK_RING | WallCrater=SAME_AS_GROUND | WallDust=SAME | WallProbe=EARLY_MULTI_RAY | BodyFlickerFX=MULTIPLAYER_READY_DISAPPEAR_ARRIVE | SlamVFXRoute=EXISTING_LAUNCHER_EVENT"
		.. " | Cooldown=4.00s CoreCooldownHUD=ON"
		.. " | HitTiming=0.10-0.85s_SERVER_SANITY"
)

return true
