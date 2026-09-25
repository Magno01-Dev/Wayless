--!strict
-- WindTrail v3 - AutoSpeed / Multiplayer / Smooth Fade (R6)
--
-- White wind trails on hands/feet.
--
-- Goals:
-- 1) Ground Dash / Air Dash / Tree Jump -> ON automatically.
-- 2) Normal jump / normal fall -> does NOT activate just because Y velocity is high.
-- 3) Smooth fade + shortening when speed drops instead of a hard cut.
-- 4) Every client creates the trails for ALL replicated player characters,
--    so other players can see them too.
-- 5) No RenderStepped work. VFX monitoring runs on Heartbeat at 30 Hz so it
--    does not compete with CombatController / camera render updates.
--
-- Compatibility API preserved:
--   WindTrail.start(character)
--   WindTrail.stop(character)
--
-- Existing DashController / TreeJumpController do not need changes.

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")


-- =========================
-- SPEED SETTINGS
-- =========================

-- Current values:
-- Sprint = 40
-- Ground Dash = 75
-- Air Dash = 105
-- Tree Jump ~= 160
local ACTIVATE_SPEED =
	70

local DEACTIVATE_SPEED =
	55


-- =========================
-- UPDATE / FADE
-- =========================

-- VFX logic does not need to run at render frequency.
local UPDATE_HZ =
	30

local UPDATE_INTERVAL =
	1 / UPDATE_HZ

-- How fast the visual strength reaches 1 / 0.
local FADE_IN_TIME =
	0.06

local FADE_OUT_TIME =
	0.24


-- =========================
-- VISUAL SETTINGS
-- =========================

local ARM_LIFETIME =
	0.10

local ARM_WIDTH =
	0.11

local LEG_LIFETIME =
	0.14

local LEG_WIDTH =
	0.14

local MIN_TRAIL_LENGTH =
	0.04

local LIGHT_EMISSION =
	0.65


local WIND_COLOR =
	ColorSequence.new({
		ColorSequenceKeypoint.new(
			0,
			Color3.fromRGB(
				255,
				255,
				255
			)
		),

		ColorSequenceKeypoint.new(
			1,
			Color3.fromRGB(
				225,
				240,
				255
			)
		),
	})


-- Transparency at FULL visual strength.
local BASE_TRANSPARENCY_POINTS = {
	{ 0.00, 0.48 },
	{ 0.18, 0.25 },
	{ 0.65, 0.55 },
	{ 1.00, 1.00 },
}


-- =========================
-- R6 LIMBS
-- =========================

export type LimbConfig = {
	name: string,
	y: number,
	width: number,
	lifetime: number,
}


local LIMBS: { LimbConfig } = {
	{
		name = "Left Arm",
		y = -0.88,
		width = ARM_WIDTH,
		lifetime = ARM_LIFETIME,
	},

	{
		name = "Right Arm",
		y = -0.88,
		width = ARM_WIDTH,
		lifetime = ARM_LIFETIME,
	},

	{
		name = "Left Leg",
		y = -0.92,
		width = LEG_WIDTH,
		lifetime = LEG_LIFETIME,
	},

	{
		name = "Right Leg",
		y = -0.92,
		width = LEG_WIDTH,
		lifetime = LEG_LIFETIME,
	},
}


-- =========================
-- STATE
-- =========================

export type TrailData = {
	trail: Trail,
	baseLifetime: number,
}


export type CharacterEffect = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	trails: { TrailData },
	attachments: { Attachment },
	visualStrength: number,
	visible: boolean,
}


local effects: { [Model]: CharacterEffect } =
	{}


-- =========================
-- HELPERS
-- =========================

local function moveTowards(
	current: number,
	target: number,
	maxDelta: number
): number

	if current < target then

		return math.min(
			current + maxDelta,
			target
		)

	end


	return math.max(
		current - maxDelta,
		target
	)

end


local function getHorizontalSpeed(
	velocity: Vector3
): number

	return Vector3.new(
		velocity.X,
		0,
		velocity.Z
	).Magnitude

end


local function isKnownSpecialHighSpeedMovement(
	character: Model
): boolean

	-- Ground/Air Dash.
	if character:GetAttribute(
		"IsDashing"
		) == true then

		return true

	end


	-- Actual local Tree Jump motion.
	if character:GetAttribute(
		"TreeJumpActive"
		) == true then

		return true

	end


	-- Generic future hook.
	-- If later you add a vertical launch/teleport-like movement that should
	-- use wind trails, set HighSpeedVFX = true for that movement.
	if character:GetAttribute(
		"HighSpeedVFX"
		) == true then

		return true

	end


	return false

end


local function getEffectiveSpeed(
	data: CharacterEffect
): number

	local velocity =
		data.root.AssemblyLinearVelocity


	local fullSpeed =
		velocity.Magnitude


	if isKnownSpecialHighSpeedMovement(
		data.character
		) then

		-- Dash / Tree Jump can be fully 3D.
		return fullSpeed

	end


	local state =
		data.humanoid:GetState()


	if state ==
		Enum.HumanoidStateType.Jumping
		or state ==
		Enum.HumanoidStateType.Freefall then

		-- Ignore natural vertical Jump/Fall velocity.
		--
		-- This fixes normal jumps activating the VFX because JumpPower /
		-- extra fall acceleration can push total 3D speed over 70.
		--
		-- High horizontal movement while airborne can still activate it.
		return getHorizontalSpeed(
			velocity
		)

	end


	return fullSpeed

end


local function buildTransparency(
	strength: number
): NumberSequence

	local keypoints: { NumberSequenceKeypoint } =
		{}


	for _, point in ipairs(
		BASE_TRANSPARENCY_POINTS
		) do

		local timePoint =
			point[1]

		local baseTransparency =
			point[2]


		-- Convert transparency -> opacity, scale opacity by visual strength,
		-- then convert back to transparency.
		local baseOpacity =
			1 - baseTransparency


		local opacity =
			baseOpacity
			* strength


		table.insert(
			keypoints,
			NumberSequenceKeypoint.new(
				timePoint,
				1 - opacity
			)
		)

	end


	return NumberSequence.new(
		keypoints
	)

end


local function buildWidthScale(
	strength: number
): NumberSequence

	return NumberSequence.new({
		NumberSequenceKeypoint.new(
			0.00,
			1.00 * strength
		),

		NumberSequenceKeypoint.new(
			0.55,
			0.62 * strength
		),

		NumberSequenceKeypoint.new(
			1.00,
			0
		),
	})

end


local function destroyNamedOldObjects(
	limb: BasePart
)

	for _, child in ipairs(
		limb:GetChildren()
		) do

		if child.Name ==
			"WindTrail_Att0"
			or child.Name ==
			"WindTrail_Att1"
			or child.Name ==
			"WindTrail" then

			child:Destroy()

		end

	end

end


local function createTrailForLimb(
	limb: BasePart,
	config: LimbConfig
): (
	TrailData,
	Attachment,
	Attachment
	)

	destroyNamedOldObjects(
		limb
	)


	local halfWidth =
		config.width * 0.5


	local attachment0 =
		Instance.new(
			"Attachment"
		)

	attachment0.Name =
		"WindTrail_Att0"

	attachment0.Position =
		Vector3.new(
			-halfWidth,
			config.y,
			0
		)

	attachment0.Parent =
		limb


	local attachment1 =
		Instance.new(
			"Attachment"
		)

	attachment1.Name =
		"WindTrail_Att1"

	attachment1.Position =
		Vector3.new(
			halfWidth,
			config.y,
			0
		)

	attachment1.Parent =
		limb


	local trail =
		Instance.new(
			"Trail"
		)

	trail.Name =
		"WindTrail"

	trail.Attachment0 =
		attachment0

	trail.Attachment1 =
		attachment1

	trail.Enabled =
		false

	trail.FaceCamera =
		true

	trail.Lifetime =
		config.lifetime

	trail.MinLength =
		MIN_TRAIL_LENGTH

	trail.LightEmission =
		LIGHT_EMISSION

	trail.LightInfluence =
		0

	trail.Color =
		WIND_COLOR

	trail.Transparency =
		buildTransparency(
			0
		)

	trail.WidthScale =
		buildWidthScale(
			0
		)

	trail.Parent =
		limb


	return {
		trail = trail,
		baseLifetime = config.lifetime,
	},
		attachment0,
		attachment1

end


local function applyVisualStrength(
	data: CharacterEffect,
	strength: number
)

	strength =
		math.clamp(
			strength,
			0,
			1
		)


	local shouldRender =
		strength >
	0.015


	if data.visible ~=
		shouldRender then

		data.visible =
			shouldRender


		for _, trailData in ipairs(
			data.trails
			) do

			trailData.trail.Enabled =
				shouldRender

		end

	end


	if not shouldRender then

		return

	end


	local transparency =
		buildTransparency(
			strength
		)


	local widthScale =
		buildWidthScale(
			strength
		)


	for _, trailData in ipairs(
		data.trails
		) do

		local trail =
			trailData.trail


		if trail.Parent then

			-- As strength falls, the history also gets shorter.
			trail.Lifetime =
				trailData.baseLifetime
				* (
					0.35
					+ 0.65
					* strength
				)


			trail.Transparency =
				transparency


			trail.WidthScale =
				widthScale

		end

	end

end


local function cleanup(
	character: Model
)

	local data =
		effects[
	character
	]


	if not data then

		return

	end


	for _, trailData in ipairs(
		data.trails
		) do

		local trail =
			trailData.trail


		if trail.Parent then

			trail:Destroy()

		end

	end


	for _, attachment in ipairs(
		data.attachments
		) do

		if attachment.Parent then

			attachment:Destroy()

		end

	end


	effects[
	character
	] =
		nil

end


local function createEffect(
	character: Model
): CharacterEffect?

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)


	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)


	if not humanoid
		or not root
		or not root:IsA(
			"BasePart"
		) then

		return nil

	end


	local trails: { TrailData } =
		{}

	local attachments: { Attachment } =
		{}


	for _, config in ipairs(
		LIMBS
		) do

		local limb =
			character:FindFirstChild(
				config.name
			)


		if limb
			and limb:IsA(
				"BasePart"
			) then

			local trailData,
				attachment0,
				attachment1 =
				createTrailForLimb(
					limb,
					config
				)


			table.insert(
				trails,
				trailData
			)


			table.insert(
				attachments,
				attachment0
			)


			table.insert(
				attachments,
				attachment1
			)

		end

	end


	if #trails == 0 then

		return nil

	end


	local data: CharacterEffect = {
		character = character,
		humanoid = humanoid,
		root = root,
		trails = trails,
		attachments = attachments,
		visualStrength = 0,
		visible = false,
	}


	effects[
	character
	] =
		data


	return data

end


local function bind(
	character: Model
): CharacterEffect?

	local existing =
		effects[
	character
	]


	if existing
		and existing.character.Parent
		and existing.root.Parent then

		return existing

	end


	if existing then

		cleanup(
			character
		)

	end


	return createEffect(
		character
	)

end


local function bindCharacterWhenReady(
	character: Model
)

	task.spawn(
		function()

			character:WaitForChild(
				"Humanoid",
				8
			)


			character:WaitForChild(
				"HumanoidRootPart",
				8
			)


			-- R6 limbs replicate with the character. Yield one task so the
			-- limb instances have a chance to arrive on remote clients too.
			task.wait()


			if character.Parent then

				bind(
					character
				)

			end

		end
	)

end


-- =========================
-- SPEED MONITOR
-- =========================

local accumulatedTime =
	0


RunService.Heartbeat:Connect(
	function(
		deltaTime
	)

		accumulatedTime +=
			deltaTime


		if accumulatedTime <
			UPDATE_INTERVAL then

			return

		end


		local step =
			accumulatedTime


		accumulatedTime =
			0


		for character, data in pairs(
			effects
			) do

			if not character.Parent
				or not data.root.Parent
				or data.humanoid.Health <= 0 then

				cleanup(
					character
				)

				continue

			end


			local effectiveSpeed =
				getEffectiveSpeed(
					data
				)


			local targetStrength =
				0


			if data.visualStrength <=
				0.015 then

				-- From fully OFF, require the real activation threshold.
				if effectiveSpeed >=
					ACTIVATE_SPEED then

					targetStrength =
						1

				end

			else

				-- Once ON, gradually weaken as speed drops through 70 -> 55.
				targetStrength =
					math.clamp(
						(
							effectiveSpeed
							- DEACTIVATE_SPEED
						)
						/ (
							ACTIVATE_SPEED
							- DEACTIVATE_SPEED
						),
						0,
						1
					)

			end


			local fadeTime =
				if targetStrength >
				data.visualStrength
				then FADE_IN_TIME
				else FADE_OUT_TIME


			local maxDelta =
				if fadeTime >
				0
				then step / fadeTime
				else 1


			data.visualStrength =
				moveTowards(
					data.visualStrength,
					targetStrength,
					maxDelta
				)


			applyVisualStrength(
				data,
				data.visualStrength
			)

		end

	end
)


-- =========================
-- MULTIPLAYER AUTO-BIND
-- =========================
--
-- Every client builds local Trails for every replicated player character.
-- This avoids server-side cosmetic objects while making the effect visible
-- when looking at other players.

local playerConnections: { [Player]: RBXScriptConnection } =
	{}


local function bindPlayer(
	player: Player
)

	if playerConnections[
		player
		] then

		return

	end


	if player.Character then

		bindCharacterWhenReady(
			player.Character
		)

	end


	playerConnections[
	player
	] =
		player.CharacterAdded:Connect(
			function(
				character
			)

				bindCharacterWhenReady(
					character
				)

			end
		)

end


local function unbindPlayer(
	player: Player
)

	local connection =
		playerConnections[
	player
	]


	if connection then

		connection:Disconnect()

	end


	playerConnections[
	player
	] =
		nil


	if player.Character then

		cleanup(
			player.Character
		)

	end

end


for _, player in ipairs(
	Players:GetPlayers()
	) do

	bindPlayer(
		player
	)

end


Players.PlayerAdded:Connect(
	bindPlayer
)


Players.PlayerRemoving:Connect(
	unbindPlayer
)


-- =========================
-- COMPATIBILITY API
-- =========================

local function start(
	character: Model
)

	-- Keep current DashController / TreeJumpController requires/calls valid.
	-- Visibility is decided by actual velocity.
	bindCharacterWhenReady(
		character
	)

end


local function stop(
	_character: Model
)

	-- Intentionally no hard disable.
	-- Speed decay + FADE_OUT_TIME handle the visual exit smoothly.
end


return {
	start = start,
	stop = stop,
	bind = bind,
	cleanup = cleanup,
}
