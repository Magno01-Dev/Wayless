--!strict
-- DashVFXController v1.5 - Real Poof Particle Trail
-- StarterPlayer > StarterPlayerScripts > DashVFXController [LocalScript]
--
-- ADDITIVE VFX ONLY.
--
-- Existing systems intentionally left untouched:
-- - DashController v3.9 handles movement, Stamina, cooldown, FOV, animations,
--   and the existing Dash SFX.
-- - WindTrail v3 already handles the white hand/foot speed trails.
--
-- This controller adds:
-- 1) a short directional pressure ring when a Dash begins;
-- 2) subtle dust/scrape from solid ground;
-- 3) no dust for Air Dash or Water Walking;
-- 4) no camera shake.
--
-- Multiplayer:
-- - Local character: IsDashing attribute is the primary trigger.
-- - Other characters: replicated Dash animation playback is used as the
--   cosmetic trigger.
-- - A short per-character dedupe window prevents double bursts.

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local TweenService =
	game:GetService("TweenService")

local Debris =
	game:GetService("Debris")


local localPlayer =
	Players.LocalPlayer


local DASH_ANIMATION_IDS: {[string]: boolean} = {
	["101651539767821"] = true,
	["107834944480329"] = true,
	["133451550328369"] = true,
	["119152397409036"] = true,
}


local MAX_RENDER_DISTANCE = 130
local TRIGGER_DEDUPE_TIME = 0.10
local DASH_DIRECTION_MIN_SPEED = 45
local DASH_DIRECTION_SAMPLE_FRAMES = 3


local RING_ENABLED = true
local RING_SEGMENTS = 12
local RING_START_RADIUS = 0.72
local RING_END_RADIUS = 1.90
local RING_THICKNESS = 0.075
local RING_START_TRANSPARENCY = 0.48
local RING_DURATION = 0.23
local RING_BACK_OFFSET = 0.56
local RING_COLOR =
	Color3.fromRGB(
		225,
		236,
		242
	)


local DUST_ENABLED = true

-- v1.5:
-- Uses the SAME native smoke texture / ParticleEmitter language as the
-- Execution poof, but at a much smaller scale and emitted repeatedly during
-- the beginning of the Dash.
local DUST_TRAIL_BURST_COUNT = 5
local DUST_TRAIL_INTERVAL = 0.045

local DUST_OUTER_PARTICLE_COUNT = 7
local DUST_CORE_PARTICLE_COUNT = 4

local DUST_MIN_UP_DOT = 0.55

local DUST_TEXTURE =
	"rbxasset://textures/particles/smoke_main.dds"


type CharacterBinding = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	animator: Animator,
	connections: {RBXScriptConnection},
	lastTriggerAt: number,
}

local bindings: {[Model]: CharacterBinding} = {}
local playerConnections: {[Player]: RBXScriptConnection} = {}


local function safeUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	if vector.Magnitude > 0.001 then
		return vector.Unit
	end

	if fallback.Magnitude > 0.001 then
		return fallback.Unit
	end

	return Vector3.new(0, 0, -1)
end


local function getCameraDistance(
	position: Vector3
): number

	local camera =
		workspace.CurrentCamera

	if not camera then
		return math.huge
	end

	return (
		camera.CFrame.Position
		- position
	).Magnitude
end


local function getAnimationNumericId(
	animationId: string
): string?

	return string.match(
		animationId,
		"(%d+)$"
	)
end


local function getPlaneBasis(
	normal: Vector3
): (Vector3, Vector3, Vector3)

	local resolvedNormal =
		safeUnit(
			normal,
			Vector3.yAxis
		)

	local reference =
		if math.abs(
			resolvedNormal:Dot(
				Vector3.yAxis
			)
		) < 0.94
		then Vector3.yAxis
		else Vector3.xAxis

	local axisA =
		safeUnit(
			reference:Cross(
				resolvedNormal
			),
			Vector3.xAxis
		)

	local axisB =
		safeUnit(
			resolvedNormal:Cross(
				axisA
			),
			Vector3.zAxis
		)

	return resolvedNormal,
		axisA,
		axisB
end


local function createVFXPart(
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number
): Part

	local part =
		Instance.new("Part")

	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Parent = workspace

	return part
end


local function getMaterialColor(
	result: RaycastResult
): Color3

	local instance =
		result.Instance

	if instance
		and instance:IsA("BasePart") then

		return instance.Color:Lerp(
			Color3.fromRGB(
				150,
				145,
				136
			),
			0.56
		)
	end

	local material =
		result.Material

	if material == Enum.Material.Grass
		or material == Enum.Material.Ground
		or material == Enum.Material.LeafyGrass then

		return Color3.fromRGB(
			126,
			119,
			94
		)

	elseif material == Enum.Material.Sand then

		return Color3.fromRGB(
			180,
			162,
			125
		)

	elseif material == Enum.Material.Snow then

		return Color3.fromRGB(
			210,
			214,
			216
		)

	elseif material == Enum.Material.Wood
		or material == Enum.Material.WoodPlanks then

		return Color3.fromRGB(
			139,
			119,
			96
		)
	end

	return Color3.fromRGB(
		145,
		145,
		145
	)
end


local function makePressureRing(
	center: Vector3,
	planeNormal: Vector3
)

	if not RING_ENABLED then
		return
	end

	local normal,
		axisA,
		axisB =
		getPlaneBasis(
			planeNormal
		)

	for index = 1, RING_SEGMENTS do

		local angle =
			(index - 1)
			/ RING_SEGMENTS
			* math.pi
			* 2

		local radial =
			axisA
			* math.cos(angle)
			+ axisB
			* math.sin(angle)

		local tangent =
			safeUnit(
				normal:Cross(radial),
				axisA
			)

		local segmentArc =
			(
				2
				* math.pi
				* RING_START_RADIUS
			)
			/ RING_SEGMENTS
			* 0.72

		local startPosition =
			center
			+ radial
			* RING_START_RADIUS

		local segment =
			createVFXPart(
				"DashPressureRingSegment",
				RING_COLOR,
				Enum.Material.Neon,
				RING_START_TRANSPARENCY
			)

		segment.Size =
			Vector3.new(
				segmentArc,
				RING_THICKNESS,
				RING_THICKNESS
			)

		segment.CFrame =
			CFrame.fromMatrix(
				startPosition,
				tangent,
				normal,
				radial
			)

		local endSegmentArc =
			(
				2
				* math.pi
				* RING_END_RADIUS
			)
			/ RING_SEGMENTS
			* 0.72

		local endPosition =
			center
			+ radial
			* RING_END_RADIUS

		TweenService:
			Create(
				segment,
				TweenInfo.new(
					RING_DURATION,
					Enum.EasingStyle.Quart,
					Enum.EasingDirection.Out
				),
				{
					CFrame =
					CFrame.fromMatrix(
						endPosition,
						tangent,
						normal,
						radial
					),

					Size =
					Vector3.new(
						endSegmentArc,
						RING_THICKNESS * 0.55,
						RING_THICKNESS * 0.55
					),

					Transparency = 1
				}
			):
			Play()

		Debris:AddItem(
			segment,
			RING_DURATION + 0.08
		)
	end
end


local function getContact(
	character: Model,
	root: BasePart
): RaycastResult?

	local surfaceWalking =
		character:GetAttribute(
			"SurfaceWalking"
		) == true

	local castNormal =
		Vector3.yAxis

	if surfaceWalking then

		local surfaceNormal =
			character:GetAttribute(
				"SurfaceNormal"
			)

		if typeof(surfaceNormal) == "Vector3"
			and surfaceNormal.Magnitude > 0.5 then

			castNormal =
				surfaceNormal.Unit
		end
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances =
		{character}

	params.IgnoreWater =
		false

	return workspace:
		Raycast(
			root.Position
			+ castNormal * 0.35,
			-castNormal * 5.0,
			params
		)
end


local function makeDashSmokeEmitter(
	name: string,
	dustColor: Color3
): ParticleEmitter

	local emitter =
		Instance.new("ParticleEmitter")

	emitter.Name =
		name

	emitter.Texture =
		DUST_TEXTURE

	emitter.Rate =
		0

	emitter.Enabled =
		false

	emitter.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	emitter.Rotation =
		NumberRange.new(
			-180,
			180
		)

	emitter.RotSpeed =
		NumberRange.new(
			-65,
			65
		)

	emitter.Drag =
		3.2

	emitter.LightInfluence =
		0.22

	emitter.LightEmission =
		0.02

	emitter.Color =
		ColorSequence.new({
			ColorSequenceKeypoint.new(
				0,
				dustColor:Lerp(
					Color3.fromRGB(
						236,
						236,
						232
					),
					0.34
				)
			),

			ColorSequenceKeypoint.new(
				0.55,
				dustColor
			),

			ColorSequenceKeypoint.new(
				1,
				dustColor:Lerp(
					Color3.fromRGB(
						116,
						113,
						108
					),
					0.32
				)
			),
		})

	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.16
			),

			NumberSequenceKeypoint.new(
				0.30,
				0.27
			),

			NumberSequenceKeypoint.new(
				0.72,
				0.62
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	return emitter
end


local function makeDustBurst(
	contact: RaycastResult,
	dashDirection: Vector3,
	burstAlpha: number
)

	if not DUST_ENABLED then
		return
	end

	if contact.Material ==
		Enum.Material.Water then

		return
	end


	local normal =
		safeUnit(
			contact.Normal,
			Vector3.yAxis
		)


	if normal:Dot(
		Vector3.yAxis
		) < DUST_MIN_UP_DOT then

		return
	end


	local projectedDash =
		dashDirection
	- normal
		* dashDirection:Dot(
			normal
		)


	projectedDash =
		safeUnit(
			projectedDash,
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local backward =
		-projectedDash


	local dustColor =
		getMaterialColor(
			contact
		)


	-- Each burst is placed at the LIVE ground contact under the character.
	-- Because this is called repeatedly during the Dash, older poofs remain
	-- behind while new ones spawn farther along the displacement path.
	local anchor =
		Instance.new("Part")

	anchor.Name =
		"DashPoofDustAnchor"

	anchor.Size =
		Vector3.new(
			0.12,
			0.12,
			0.12
		)

	anchor.Transparency =
		1

	anchor.Anchored =
		true

	anchor.CanCollide =
		false

	anchor.CanTouch =
		false

	anchor.CanQuery =
		false

	anchor.CastShadow =
		false

	anchor.CFrame =
		CFrame.lookAt(
			contact.Position
			+ normal * 0.13
			+ backward
			* (
				0.12
				+ burstAlpha * 0.22
			),
			contact.Position
			+ normal * 0.13
			+ backward
			* (
				1.12
				+ burstAlpha * 0.22
			),
			normal
		)

	anchor.Parent =
		workspace


	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"DashDustAttachment"

	attachment.Parent =
		anchor


	-- OUTER:
	-- broader cloud silhouette, based directly on ExecutionPoofClient's outer
	-- emitter but heavily scaled down.
	local outer =
		makeDashSmokeEmitter(
			"DashDustOuter",
			dustColor
		)

	outer.Lifetime =
		NumberRange.new(
			0.38,
			0.62
		)

	outer.Speed =
		NumberRange.new(
			2.8,
			5.2
		)

	outer.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.42
			),

			NumberSequenceKeypoint.new(
				0.24,
				0.82
			),

			NumberSequenceKeypoint.new(
				0.68,
				1.28
			),

			NumberSequenceKeypoint.new(
				1,
				1.62
			),
		})

	outer.Acceleration =
		backward * 4.8
		+ normal * 2.2

	outer.Parent =
		attachment


	-- CORE:
	-- denser center so the cloud does not read as a few isolated circles.
	local core =
		makeDashSmokeEmitter(
			"DashDustCore",
			dustColor
		)

	core.Lifetime =
		NumberRange.new(
			0.28,
			0.48
		)

	core.Speed =
		NumberRange.new(
			1.5,
			3.3
		)

	core.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.34
			),

			NumberSequenceKeypoint.new(
				0.38,
				0.70
			),

			NumberSequenceKeypoint.new(
				1,
				1.12
			),
		})

	core.Acceleration =
		backward * 3.4
		+ normal * 1.6

	core.Parent =
		attachment


	outer:
		Emit(
			DUST_OUTER_PARTICLE_COUNT
		)

	core:
		Emit(
			DUST_CORE_PARTICLE_COUNT
		)


	Debris:AddItem(
		anchor,
		1.35
	)
end


local function sampleDashDirection(
	root: BasePart
): Vector3

	for _ = 1, DASH_DIRECTION_SAMPLE_FRAMES do

		local velocity =
			root.AssemblyLinearVelocity

		if velocity.Magnitude >=
			DASH_DIRECTION_MIN_SPEED then

			return velocity.Unit
		end

		RunService.Heartbeat:
			Wait()
	end

	return safeUnit(
		root.AssemblyLinearVelocity,
		root.CFrame.LookVector
	)
end


local function triggerDashVFX(
	data: CharacterBinding
)

	if not data.character.Parent
		or not data.root.Parent
		or data.humanoid.Health <= 0 then

		return
	end

	local now =
		time()

	if now - data.lastTriggerAt <
		TRIGGER_DEDUPE_TIME then

		return
	end

	data.lastTriggerAt =
		now

	task.spawn(
		function()

			if not data.character.Parent
				or not data.root.Parent then

				return
			end

			local dashDirection =
				sampleDashDirection(
					data.root
				)

			if getCameraDistance(
				data.root.Position
				) > MAX_RENDER_DISTANCE then

				return
			end

			makePressureRing(
				data.root.Position
				- dashDirection
					* RING_BACK_OFFSET,
				dashDirection
			)

			if data.character:GetAttribute(
				"WaterWalking"
				) == true then

				return
			end

			for burstIndex = 1, DUST_TRAIL_BURST_COUNT do

				if not data.character.Parent
					or not data.root.Parent then

					break
				end

				local liveDirection =
					safeUnit(
						data.root.AssemblyLinearVelocity,
						dashDirection
					)

				local contact =
					getContact(
						data.character,
						data.root
					)

				if contact then

					makeDustBurst(
						contact,
						liveDirection,
						(burstIndex - 1)
							/ math.max(
								1,
								DUST_TRAIL_BURST_COUNT - 1
							)
					)
				end

				if burstIndex < DUST_TRAIL_BURST_COUNT then
					task.wait(
						DUST_TRAIL_INTERVAL
					)
				end
			end
		end
	)
end


local function cleanupCharacter(
	character: Model
)

	local data =
		bindings[
	character
	]

	if not data then
		return
	end

	for _, connection in ipairs(
		data.connections
		) do

		connection:
			Disconnect()
	end

	bindings[character] = nil
end


local function bindCharacter(
	player: Player,
	character: Model
)

	cleanupCharacter(
		character
	)

	task.spawn(
		function()

			local humanoid =
				character:
				WaitForChild(
					"Humanoid",
					8
				)

			local root =
				character:
				WaitForChild(
					"HumanoidRootPart",
					8
				)

			if not humanoid
				or not humanoid:IsA("Humanoid")
				or not root
				or not root:IsA("BasePart")
				or not character.Parent then

				return
			end

			local animator =
				humanoid:
				FindFirstChildOfClass(
					"Animator"
				)
				or humanoid:
				WaitForChild(
					"Animator",
					5
				)

			if not animator
				or not animator:IsA("Animator") then

				return
			end

			local data: CharacterBinding = {
				character = character,
				humanoid = humanoid,
				root = root,
				animator = animator,
				connections = {},
				lastTriggerAt = -math.huge,
			}

			bindings[character] = data

			if player == localPlayer then

				table.insert(
					data.connections,
					character:
						GetAttributeChangedSignal(
							"IsDashing"
						):
						Connect(
							function()

								if character:
									GetAttribute(
										"IsDashing"
									) == true then

									triggerDashVFX(
										data
									)
								end
							end
						)
				)
			end

			table.insert(
				data.connections,
				animator.AnimationPlayed:
					Connect(
						function(
							track: AnimationTrack
						)

							local animation =
							track.Animation

							if not animation then
								return
							end

							local numericId =
							getAnimationNumericId(
								animation.AnimationId
							)

							if numericId
								and DASH_ANIMATION_IDS[numericId] then

								triggerDashVFX(
									data
								)
							end
						end
					)
			)

			table.insert(
				data.connections,
				humanoid.Died:
					Connect(
						function()

							cleanupCharacter(
								character
							)
						end
					)
			)

			table.insert(
				data.connections,
				character.AncestryChanged:
					Connect(
						function(
							_child,
							parent
						)

							if parent == nil then

								cleanupCharacter(
									character
								)
							end
						end
					)
			)
		end
	)
end


local function bindPlayer(
	player: Player
)

	if playerConnections[player] then
		return
	end

	if player.Character then

		bindCharacter(
			player,
			player.Character
		)
	end

	playerConnections[player] =
		player.CharacterAdded:
		Connect(
			function(
				character: Model
			)

				bindCharacter(
					player,
					character
				)
			end
		)
end


local function unbindPlayer(
	player: Player
)

	local connection =
		playerConnections[player]

	if connection then
		connection:
			Disconnect()
	end

	playerConnections[player] = nil

	if player.Character then

		cleanupCharacter(
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


Players.PlayerAdded:
	Connect(
		bindPlayer
	)


Players.PlayerRemoving:
	Connect(
		unbindPlayer
	)


print(
	"[DashVFXController] READY v1.5"
		.. " | ExistingWindTrail=UNCHANGED"
		.. " | ExistingDashSFX=UNCHANGED"
		.. " | PressureRing=THICKER_LONGER"
		.. " | GroundDust=REAL_POOF_PARTICLE_TRAIL"
		.. " | CameraShake=OFF"
)
