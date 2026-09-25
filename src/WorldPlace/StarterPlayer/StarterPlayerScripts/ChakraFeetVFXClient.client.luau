--!strict
-- ChakraFeetVFXClient v5 - Multiplayer
--
-- StarterPlayer > StarterPlayerScripts > ChakraFeetVFXClient
--
-- IMPORTANT:
-- Put this in StarterPlayerScripts, NOT StarterCharacterScripts.
--
-- Every client creates the Chakra Feet aura locally for EVERY player
-- whose replicated character attribute says:
--
--   ChakraFeetActive = true
--
-- This guarantees Player A can see Player B's aura and vice versa.
--
-- Visual look preserved from v4:
-- - dual layer aura
-- - brighter inner core
-- - subtle blue PointLight pulse
-- - locked to feet
-- - no running trail

local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")


-- =========================
-- VISUAL SETTINGS
-- =========================

local AURA_TEXTURE =
	"rbxasset://textures/particles/smoke_main.dds"

local CHAKRA_BLUE =
	Color3.fromRGB(
		95,
		180,
		255
	)

local CHAKRA_MID =
	Color3.fromRGB(
		145,
		210,
		255
	)

local CHAKRA_LIGHT =
	Color3.fromRGB(
		235,
		248,
		255
	)

local FOOT_Y =
	-0.74

local SIDE_OFFSET =
	0.43

local FRONT_BACK_OFFSET =
	0.43

local DIAGONAL_OFFSET =
	0.31

local INNER_SIDE_OFFSET =
	0.24

local INNER_FRONT_BACK_OFFSET =
	0.24

local INNER_DIAGONAL_OFFSET =
	0.17

local OUTER_RATE =
	14

local OUTER_LIFETIME =
	NumberRange.new(
		0.34,
		0.50
	)

local OUTER_SIZE =
	NumberSequence.new({
		NumberSequenceKeypoint.new(
			0.00,
			0.44
		),

		NumberSequenceKeypoint.new(
			0.30,
			0.63
		),

		NumberSequenceKeypoint.new(
			0.72,
			0.56
		),

		NumberSequenceKeypoint.new(
			1.00,
			0.25
		),
	})

local OUTER_TRANSPARENCY =
	NumberSequence.new({
		NumberSequenceKeypoint.new(
			0.00,
			0.24
		),

		NumberSequenceKeypoint.new(
			0.20,
			0.16
		),

		NumberSequenceKeypoint.new(
			0.68,
			0.34
		),

		NumberSequenceKeypoint.new(
			1.00,
			1.00
		),
	})

local INNER_RATE =
	11

local INNER_LIFETIME =
	NumberRange.new(
		0.20,
		0.30
	)

local INNER_SIZE =
	NumberSequence.new({
		NumberSequenceKeypoint.new(
			0.00,
			0.22
		),

		NumberSequenceKeypoint.new(
			0.30,
			0.34
		),

		NumberSequenceKeypoint.new(
			0.72,
			0.30
		),

		NumberSequenceKeypoint.new(
			1.00,
			0.14
		),
	})

local INNER_TRANSPARENCY =
	NumberSequence.new({
		NumberSequenceKeypoint.new(
			0.00,
			0.08
		),

		NumberSequenceKeypoint.new(
			0.18,
			0.03
		),

		NumberSequenceKeypoint.new(
			0.55,
			0.20
		),

		NumberSequenceKeypoint.new(
			1.00,
			1.00
		),
	})

local BASE_LIGHT_BRIGHTNESS =
	1.15

local PULSE_AMPLITUDE =
	0.28

local LIGHT_RANGE =
	5.2

local PULSE_SPEED =
	4.25

local PULSE_UPDATE_HZ =
	20

local PULSE_UPDATE_INTERVAL =
	1 / PULSE_UPDATE_HZ


-- =========================
-- TYPES / STATE
-- =========================

type FootLightData = {
	light: PointLight,
	baseBrightness: number,
	phaseOffset: number,
}

type CharacterVFX = {
	character: Model,
	humanoid: Humanoid,
	emitters: { ParticleEmitter },
	attachments: { Attachment },
	lights: { FootLightData },
	active: boolean,
	pulseClock: number,
	attributeConnection: RBXScriptConnection?,
	deathConnection: RBXScriptConnection?,
}

local characterVFX: { [Model]: CharacterVFX } =
	{}

local playerConnections: { [Player]: RBXScriptConnection } =
	{}


-- =========================
-- CREATION HELPERS
-- =========================

local function createAttachment(
	leg: BasePart,
	name: string,
	position: Vector3,
	storage: { Attachment }
): Attachment

	local attachment =
		Instance.new(
			"Attachment"
		)

	attachment.Name =
		name

	attachment.Position =
		position

	attachment.Parent =
		leg


	table.insert(
		storage,
		attachment
	)


	return attachment

end


local function configureEmitterShared(
	emitter: ParticleEmitter
)

	emitter.Texture =
		AURA_TEXTURE

	emitter.Enabled =
		false

	emitter.Speed =
		NumberRange.new(
			0,
			0
		)

	emitter.Acceleration =
		Vector3.zero

	emitter.Drag =
		0

	emitter.SpreadAngle =
		Vector2.new(
			0,
			0
		)

	-- Keeps the aura visually attached to the animated foot.
	emitter.LockedToPart =
		true

	emitter.LightInfluence =
		0

end


local function createOuterEmitter(
	attachment: Attachment,
	storage: { ParticleEmitter }
): ParticleEmitter

	local emitter =
		Instance.new(
			"ParticleEmitter"
		)

	emitter.Name =
		"ChakraFeet_OuterAura"

	configureEmitterShared(
		emitter
	)

	emitter.Rate =
		OUTER_RATE

	emitter.Lifetime =
		OUTER_LIFETIME

	emitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	emitter.RotSpeed =
		NumberRange.new(
			-26,
			26
		)

	emitter.LightEmission =
		0.92

	emitter.Color =
		ColorSequence.new({
			ColorSequenceKeypoint.new(
				0.00,
				CHAKRA_BLUE
			),

			ColorSequenceKeypoint.new(
				0.42,
				CHAKRA_MID
			),

			ColorSequenceKeypoint.new(
				0.78,
				CHAKRA_LIGHT
			),

			ColorSequenceKeypoint.new(
				1.00,
				CHAKRA_BLUE
			),
		})

	emitter.Size =
		OUTER_SIZE

	emitter.Transparency =
		OUTER_TRANSPARENCY

	emitter.Parent =
		attachment


	table.insert(
		storage,
		emitter
	)


	return emitter

end


local function createInnerEmitter(
	attachment: Attachment,
	storage: { ParticleEmitter }
): ParticleEmitter

	local emitter =
		Instance.new(
			"ParticleEmitter"
		)

	emitter.Name =
		"ChakraFeet_InnerAura"

	configureEmitterShared(
		emitter
	)

	emitter.Rate =
		INNER_RATE

	emitter.Lifetime =
		INNER_LIFETIME

	emitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	emitter.RotSpeed =
		NumberRange.new(
			-18,
			18
		)

	emitter.LightEmission =
		1

	emitter.Color =
		ColorSequence.new({
			ColorSequenceKeypoint.new(
				0.00,
				CHAKRA_MID
			),

			ColorSequenceKeypoint.new(
				0.35,
				CHAKRA_LIGHT
			),

			ColorSequenceKeypoint.new(
				0.75,
				CHAKRA_MID
			),

			ColorSequenceKeypoint.new(
				1.00,
				CHAKRA_BLUE
			),
		})

	emitter.Size =
		INNER_SIZE

	emitter.Transparency =
		INNER_TRANSPARENCY

	emitter.Parent =
		attachment


	table.insert(
		storage,
		emitter
	)


	return emitter

end


local function createRing(
	leg: BasePart,
	prefix: string,
	sideOffset: number,
	frontBackOffset: number,
	diagonalOffset: number,
	attachments: { Attachment },
	emitters: { ParticleEmitter },
	createEmitter: (
		Attachment,
		{ ParticleEmitter }
	) -> ParticleEmitter
)

	local points = {
		{
			"Left",
			Vector3.new(
				-sideOffset,
				FOOT_Y,
				0
			),
		},

		{
			"Right",
			Vector3.new(
				sideOffset,
				FOOT_Y,
				0
			),
		},

		{
			"Front",
			Vector3.new(
				0,
				FOOT_Y,
				-frontBackOffset
			),
		},

		{
			"Back",
			Vector3.new(
				0,
				FOOT_Y,
				frontBackOffset
			),
		},

		{
			"FrontLeft",
			Vector3.new(
				-diagonalOffset,
				FOOT_Y,
				-diagonalOffset
			),
		},

		{
			"FrontRight",
			Vector3.new(
				diagonalOffset,
				FOOT_Y,
				-diagonalOffset
			),
		},

		{
			"BackLeft",
			Vector3.new(
				-diagonalOffset,
				FOOT_Y,
				diagonalOffset
			),
		},

		{
			"BackRight",
			Vector3.new(
				diagonalOffset,
				FOOT_Y,
				diagonalOffset
			),
		},
	}


	for _, point in ipairs(
		points
		) do

		local attachment =
			createAttachment(
				leg,
				prefix
				.. "_"
				.. point[1],
				point[2] :: Vector3,
				attachments
			)


		createEmitter(
			attachment,
			emitters
		)

	end

end


local function createFootLight(
	leg: BasePart,
	phaseOffset: number,
	storage: { FootLightData }
)

	local light =
		Instance.new(
			"PointLight"
		)

	light.Name =
		"ChakraFeet_Light"

	light.Enabled =
		false

	light.Color =
		CHAKRA_BLUE

	light.Brightness =
		BASE_LIGHT_BRIGHTNESS

	light.Range =
		LIGHT_RANGE

	light.Shadows =
		false

	light.Parent =
		leg


	table.insert(
		storage,
		{
			light = light,
			baseBrightness = BASE_LIGHT_BRIGHTNESS,
			phaseOffset = phaseOffset,
		}
	)

end


local function createFootAura(
	leg: BasePart,
	phaseOffset: number,
	attachments: { Attachment },
	emitters: { ParticleEmitter },
	lights: { FootLightData }
)

	createRing(
		leg,
		"ChakraFeetOuter",
		SIDE_OFFSET,
		FRONT_BACK_OFFSET,
		DIAGONAL_OFFSET,
		attachments,
		emitters,
		createOuterEmitter
	)

	createRing(
		leg,
		"ChakraFeetInner",
		INNER_SIDE_OFFSET,
		INNER_FRONT_BACK_OFFSET,
		INNER_DIAGONAL_OFFSET,
		attachments,
		emitters,
		createInnerEmitter
	)

	createFootLight(
		leg,
		phaseOffset,
		lights
	)

end


-- =========================
-- VFX STATE
-- =========================

local function setEnabled(
	data: CharacterVFX,
	enabled: boolean
)

	if data.active ==
		enabled then

		return

	end


	data.active =
		enabled


	for _, emitter in ipairs(
		data.emitters
		) do

		if emitter.Parent then

			if enabled
				and not emitter.Enabled then

				emitter:Emit(
					4
				)

			end


			emitter.Enabled =
				enabled

		end

	end


	for _, lightData in ipairs(
		data.lights
		) do

		if lightData.light.Parent then

			lightData.light.Enabled =
				enabled

			lightData.light.Brightness =
				lightData.baseBrightness

		end

	end

end


local function cleanupCharacter(
	character: Model
)

	local data =
		characterVFX[
	character
	]


	if not data then

		return

	end


	if data.attributeConnection then

		data.attributeConnection:
			Disconnect()

	end


	if data.deathConnection then

		data.deathConnection:
			Disconnect()

	end


	for _, emitter in ipairs(
		data.emitters
		) do

		if emitter.Parent then

			emitter:Destroy()

		end

	end


	for _, attachment in ipairs(
		data.attachments
		) do

		if attachment.Parent then

			attachment:Destroy()

		end

	end


	for _, lightData in ipairs(
		data.lights
		) do

		if lightData.light.Parent then

			lightData.light:
				Destroy()

		end

	end


	characterVFX[
	character
	] =
		nil

end


local function setupCharacter(
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
					10
				)


			local leftLeg =
				character:
				WaitForChild(
					"Left Leg",
					10
				)


			local rightLeg =
				character:
				WaitForChild(
					"Right Leg",
					10
				)


			if not humanoid
				or not humanoid:IsA(
					"Humanoid"
				)
					or not leftLeg
					or not leftLeg:IsA(
						"BasePart"
					)
					or not rightLeg
					or not rightLeg:IsA(
						"BasePart"
					)
					or not character.Parent then

				return

			end


			local attachments: { Attachment } =
				{}

			local emitters: { ParticleEmitter } =
				{}

			local lights: { FootLightData } =
				{}


			createFootAura(
				leftLeg,
				0,
				attachments,
				emitters,
				lights
			)


			createFootAura(
				rightLeg,
				0.75,
				attachments,
				emitters,
				lights
			)


			local data: CharacterVFX = {
				character = character,
				humanoid = humanoid,
				emitters = emitters,
				attachments = attachments,
				lights = lights,
				active = false,
				pulseClock = 0,
				attributeConnection = nil,
				deathConnection = nil,
			}


			characterVFX[
			character
			] =
				data


			local function syncState()

				local current =
					characterVFX[
				character
				]


				if current ~= data then

					return

				end


				setEnabled(
					data,
					character:
						GetAttribute(
							"ChakraFeetActive"
						) == true
				)

			end


			data.attributeConnection =
				character:
				GetAttributeChangedSignal(
					"ChakraFeetActive"
				):
				Connect(
					syncState
				)


			data.deathConnection =
				humanoid.Died:
				Connect(
					function()

						setEnabled(
							data,
							false
						)

					end
				)


			syncState()

		end
	)

end


-- =========================
-- MULTIPLAYER BINDING
-- =========================

local function bindPlayer(
	player: Player
)

	if playerConnections[
		player
		] then

		return

	end


	if player.Character then

		setupCharacter(
			player.Character
		)

	end


	playerConnections[
	player
	] =
		player.CharacterAdded:
		Connect(
			setupCharacter
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

		connection:
			Disconnect()

	end


	playerConnections[
	player
	] =
		nil


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


-- =========================
-- LOCAL PULSE
-- =========================

local accumulated =
	0


RunService.Heartbeat:
	Connect(
		function(
			deltaTime
		)

			accumulated +=
			deltaTime


			if accumulated <
				PULSE_UPDATE_INTERVAL then

				return

			end


			local step =
			accumulated


			accumulated =
			0


			for character, data in pairs(
				characterVFX
				) do

				if not character.Parent
					or data.humanoid.Health <= 0 then

					cleanupCharacter(
						character
					)

					continue

				end


				if data.active then

					data.pulseClock +=
					step
					* PULSE_SPEED


					for _, lightData in ipairs(
						data.lights
						) do

						local light =
						lightData.light


						if light.Parent
							and light.Enabled then

							local pulse =
							(
								math.sin(
									data.pulseClock
									+
									lightData.phaseOffset
								)
								*
								0.5
							)
							+
							0.5


							light.Brightness =
							lightData.baseBrightness
							+
							(
								pulse
								*
								PULSE_AMPLITUDE
							)

						end

					end

				end

			end

		end
	)
