--!nonstrict
-- ServerScriptService > JutsuSystem > Jutsus > WaterPrison
--
-- WAYLESS Water Prison v6
--
-- CAMBIOS:
-- - Prison.Duration = 1.90 segundos.
-- - La prision flota 3.5 studs.
-- - La subida ahora es LENTA y SMOOTH.
-- - FloatRiseTime controla cuanto tarda en subir.
-- - FloatResponsiveness evita el tiron brusco.
-- - FloatMaxVelocity limita la velocidad vertical.
--
-- Todo el VFX se genera por codigo.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

---------------------------------------------------------------------
-- VFX
---------------------------------------------------------------------

local WaterPrisonVFX = {}

local WATER = ColorSequence.new(
	Color3.fromRGB(52, 163, 225),
	Color3.fromRGB(192, 247, 255)
)

local PRISON_WATER = ColorSequence.new({
	ColorSequenceKeypoint.new(
		0,
		Color3.fromRGB(47, 153, 221)
	),

	ColorSequenceKeypoint.new(
		0.5,
		Color3.fromRGB(181, 242, 255)
	),

	ColorSequenceKeypoint.new(
		1,
		Color3.fromRGB(71, 186, 232)
	),
})

local SMOKE =
	"rbxasset://textures/particles/smoke_main.dds"

local activePrisons =
	setmetatable({}, {
		__mode = "k",
	})

---------------------------------------------------------------------
-- BASIC VFX HELPERS
---------------------------------------------------------------------

local function createBasePart(
	name,
	position
)

	local part =
		Instance.new("Part")

	part.Name =
		name

	part.Anchored =
		true

	part.CanCollide =
		false

	part.CanQuery =
		false

	part.CanTouch =
		false

	part.CastShadow =
		false

	part.Transparency =
		1

	part.Size =
		Vector3.one * 0.2

	part.Position =
		position

	return part
end

local function createAttachment(
	parent,
	name,
	position
)

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		name

	attachment.Position =
		position

	attachment.Parent =
		parent

	return attachment
end

local function createParticles(
	parent,
	name,
	radius,
	impact
)

	local emitter =
		Instance.new("ParticleEmitter")

	emitter.Name =
		name

	emitter.Texture =
		SMOKE

	emitter.Color =
		WATER

	emitter.LightEmission =
		0.25

	emitter.LightInfluence =
		0

	emitter.Lifetime =
		NumberRange.new(
			0.18,
			impact and 0.65 or 0.35
		)

	emitter.Speed =
		NumberRange.new(
			impact and 10 or 1,
			impact and 25 or 4
		)

	emitter.SpreadAngle =
		impact
		and Vector2.new(75, 75)
		or Vector2.new(18, 18)

	emitter.EmissionDirection =
		Enum.NormalId.Back

	emitter.Acceleration =
		Vector3.new(
			0,
			impact and -38 or -8,
			0
		)

	emitter.Drag =
		1

	emitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				radius * 0.12
			),

			NumberSequenceKeypoint.new(
				0.2,
				radius * 0.24
			),

			NumberSequenceKeypoint.new(
				1,
				0
			),
		})

	emitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.15
			),

			NumberSequenceKeypoint.new(
				0.6,
				0.4
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	emitter.Rate =
		impact and 0 or 45

	emitter.Enabled =
		not impact

	emitter.Parent =
		parent

	return emitter
end

local function safeLookAt(
	position,
	direction
)

	local unitDirection =
		if direction.Magnitude > 0.001
		then direction.Unit
		else Vector3.new(0, 0, -1)

	local up =
		if math.abs(
			unitDirection:Dot(Vector3.yAxis)
		) > 0.98
		then Vector3.xAxis
		else Vector3.yAxis

	return CFrame.lookAt(
		position,
		position + unitDirection,
		up
	)
end

---------------------------------------------------------------------
-- PROJECTILE VFX
---------------------------------------------------------------------

function WaterPrisonVFX.CreateProjectile(
	position,
	radius,
	direction
)

	local projectile =
		createBasePart(
			"WaterPrison_Projectile",
			position
		)

	projectile.Size =
		Vector3.new(
			radius * 1.55,
			radius * 1.55,
			radius * 2.15
		)

	projectile.Material =
		Enum.Material.SmoothPlastic

	projectile.Color =
		Color3.fromRGB(
			29,
			143,
			208
		)

	projectile.Transparency =
		0.32

	local mesh =
		Instance.new("SpecialMesh")

	mesh.MeshType =
		Enum.MeshType.Sphere

	mesh.Parent =
		projectile

	projectile.CFrame =
		safeLookAt(
			position,
			direction
		)

	for i = 0, 3 do

		local angle =
			i * math.pi / 2

		local offset =
			Vector3.new(
				math.cos(angle),
				math.sin(angle),
				0
			) * radius * 0.64

		local startAttachment =
			createAttachment(
				projectile,
				"CurrentStart" .. tostring(i),
				offset
				+ Vector3.new(
					0,
					0,
					-radius * 0.55
				)
			)

		local endAttachment =
			createAttachment(
				projectile,
				"CurrentEnd" .. tostring(i),
				-offset * 0.25
				+ Vector3.new(
					0,
					0,
					radius * 2.4
				)
			)

		startAttachment.Axis =
			Vector3.new(
				-math.sin(angle),
				math.cos(angle),
				0
			)

		endAttachment.Axis =
			startAttachment.Axis

		local beam =
			Instance.new("Beam")

		beam.Name =
			"Flow" .. tostring(i)

		beam.Attachment0 =
			startAttachment

		beam.Attachment1 =
			endAttachment

		beam.CurveSize0 =
			radius * 1.3

		beam.CurveSize1 =
			-radius * 0.7

		beam.Width0 =
			radius * 0.55

		beam.Width1 =
			radius * 0.08

		beam.FaceCamera =
			true

		beam.Segments =
			12

		beam.Texture =
			SMOKE

		beam.TextureLength =
			radius * 1.5

		beam.TextureSpeed =
			3

		beam.Color =
			WATER

		beam.LightEmission =
			0.35

		beam.Transparency =
			NumberSequence.new(
				0.08,
				0.85
			)

		beam.Parent =
			projectile
	end

	for i = 0, 1 do

		local offset =
			if i == 0
			then Vector3.new(
				radius * 0.6,
				0,
				0
			)
			else Vector3.new(
				0,
				radius * 0.6,
				0
			)

		local trail =
			Instance.new("Trail")

		trail.Name =
			"WaterWake" .. tostring(i)

		trail.Attachment0 =
			createAttachment(
				projectile,
				"WakeA" .. tostring(i),
				offset
			)

		trail.Attachment1 =
			createAttachment(
				projectile,
				"WakeB" .. tostring(i),
				-offset
			)

		trail.Lifetime =
			0.12

		trail.MinLength =
			0.05

		trail.FaceCamera =
			true

		trail.Color =
			WATER

		trail.LightEmission =
			0.2

		trail.Transparency =
			NumberSequence.new(
				0.4,
				1
			)

		trail.WidthScale =
			NumberSequence.new(
				1,
				0
			)

		trail.Parent =
			projectile
	end

	local tail =
		createAttachment(
			projectile,
			"Tail",
			Vector3.new(
				0,
				0,
				radius
			)
		)

	createParticles(
		tail,
		"Droplets",
		radius,
		false
	)

	projectile.Parent =
		workspace

	return projectile
end

---------------------------------------------------------------------
-- RELEASE PROJECTILE
---------------------------------------------------------------------

function WaterPrisonVFX.ReleaseProjectile(
	projectile
)

	if not projectile
		or not projectile.Parent then

		return
	end

	projectile.Transparency =
		1

	for _, object in ipairs(
		projectile:GetDescendants()
		) do

		if object:IsA("ParticleEmitter")
			or object:IsA("Beam")
			or object:IsA("Trail") then

			object.Enabled =
				false
		end
	end

	Debris:AddItem(
		projectile,
		0.8
	)
end

---------------------------------------------------------------------
-- IMPACT
---------------------------------------------------------------------

function WaterPrisonVFX.Impact(
	position,
	normal,
	radius
)

	local splash =
		createBasePart(
			"WaterPrison_Splash",
			position + normal * 0.08
		)

	local up =
		if math.abs(normal.Y) > 0.98
		then Vector3.xAxis
		else Vector3.yAxis

	splash.CFrame =
		CFrame.lookAt(
			splash.Position,
			splash.Position - normal,
			up
		)

	local drops =
		createParticles(
			splash,
			"SplashDrops",
			radius,
			true
		)

	local foam =
		createParticles(
			splash,
			"Whitewater",
			radius,
			true
		)

	foam.Color =
		ColorSequence.new(
			Color3.fromRGB(
				216,
				249,
				255
			)
		)

	foam.Speed =
		NumberRange.new(
			3,
			10
		)

	foam.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				radius * 0.3
			),

			NumberSequenceKeypoint.new(
				0.3,
				radius * 1.2
			),

			NumberSequenceKeypoint.new(
				1,
				radius * 1.7
			),
		})

	foam.Transparency =
		NumberSequence.new(
			0.5,
			1
		)

	splash.Parent =
		workspace

	task.delay(
		0.06,
		function()

			if splash.Parent then

				drops:Emit(32)
				foam:Emit(10)
			end
		end
	)

	Debris:AddItem(
		splash,
		1.2
	)
end

---------------------------------------------------------------------
-- PRISON RINGS
---------------------------------------------------------------------

local function ringFrame(
	position,
	tangent,
	radial
)

	return CFrame.fromMatrix(
		position,
		tangent.Unit,
		radial.Unit,
		tangent.Unit:Cross(
			radial.Unit
		)
	)
end

local function createRing(
	part,
	radius,
	tilt,
	name,
	width,
	speed
)

	local transform =
		CFrame.Angles(
			tilt.X,
			tilt.Y,
			tilt.Z
		)

	local k =
		4
		* math.tan(
			math.pi / 8
		)
		/ 3

	for q = 0, 3 do

		local a =
			q * math.pi / 2

		local b =
			(q + 1) * math.pi / 2

		local function point(
			theta,
			suffix
		)

			local radial =
				Vector3.new(
					math.cos(theta),
					0,
					math.sin(theta)
				)

			local tangent =
				Vector3.new(
					-math.sin(theta),
					0,
					math.cos(theta)
				)

			local attachment =
				Instance.new("Attachment")

			attachment.Name =
				name
				.. suffix
				.. tostring(q)

			attachment.CFrame =
				transform
				* ringFrame(
					radial * radius,
					tangent,
					radial
				)

			attachment.Parent =
				part

			return attachment
		end

		local beam =
			Instance.new("Beam")

		beam.Name =
			name .. tostring(q)

		beam.Attachment0 =
			point(
				a,
				"Start"
			)

		beam.Attachment1 =
			point(
				b,
				"End"
			)

		beam.CurveSize0 =
			k * radius

		beam.CurveSize1 =
			k * radius

		beam.Segments =
			12

		beam.Width0 =
			width

		beam.Width1 =
			width

		beam.FaceCamera =
			true

		beam.Color =
			PRISON_WATER

		beam.Texture =
			SMOKE

		beam.TextureLength =
			3.4

		beam.TextureSpeed =
			speed

		beam.LightEmission =
			0.2

		beam.LightInfluence =
			0

		beam.Transparency =
			NumberSequence.new(
				0.28
			)

		beam.Parent =
			part
	end
end

---------------------------------------------------------------------
-- RELEASE PRISON
---------------------------------------------------------------------

function WaterPrisonVFX.ReleasePrison(
	bubble
)

	if not bubble
		or not bubble.Parent
		or bubble:GetAttribute("Released") then

		return
	end

	bubble:SetAttribute(
		"Released",
		true
	)

	local state =
		activePrisons[bubble]

	if state then

		activePrisons[bubble] =
			nil

		for _, connection in ipairs(
			state.connections
			) do

			connection:Disconnect()
		end

		state.grow:Cancel()
	end

	local weld =
		bubble:FindFirstChild(
			"TargetWeld"
		)

	if weld then
		weld:Destroy()
	end

	bubble.Anchored =
		true

	for _, object in ipairs(
		bubble:GetDescendants()
		) do

		if object:IsA("Beam")
			or object:IsA("ParticleEmitter") then

			object.Enabled =
				false
		end
	end

	WaterPrisonVFX.Impact(
		bubble.Position,
		Vector3.yAxis,
		3.1
	)

	TweenService:Create(
		bubble,
		TweenInfo.new(
			0.2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		),
		{
			Transparency = 1,
			Size = Vector3.one * 7.8,
		}
	):Play()

	Debris:AddItem(
		bubble,
		0.8
	)
end

---------------------------------------------------------------------
-- CREATE PRISON
---------------------------------------------------------------------

function WaterPrisonVFX.CreatePrison(
	targetRoot,
	duration,
	constraint
)

	local bubble =
		Instance.new("Part")

	bubble.Name =
		"WaterPrison_Visual"

	bubble.Shape =
		Enum.PartType.Ball

	bubble.Size =
		Vector3.one * 0.6

	bubble.CFrame =
		targetRoot.CFrame

	bubble.Anchored =
		false

	bubble.Massless =
		true

	bubble.CanCollide =
		false

	bubble.CanTouch =
		false

	bubble.CanQuery =
		false

	bubble.CastShadow =
		false

	bubble.Material =
		Enum.Material.SmoothPlastic

	bubble.Color =
		Color3.fromRGB(
			31,
			142,
			200
		)

	bubble.Transparency =
		0.66

	createRing(
		bubble,
		3.53,
		Vector3.new(
			0.3,
			0,
			0.15
		),
		"EquatorialFlow",
		0.58,
		2.7
	)

	createRing(
		bubble,
		3.48,
		Vector3.new(
			1.15,
			0.35,
			0.7
		),
		"CrossFlow",
		0.42,
		-2.2
	)

	createRing(
		bubble,
		3.5,
		Vector3.new(
			-0.6,
			0.5,
			1.2
		),
		"PolarFlow",
		0.3,
		3.1
	)

	local foam =
		Instance.new("ParticleEmitter")

	foam.Name =
		"SuspendedBubbles"

	foam.Texture =
		SMOKE

	foam.Rate =
		25

	foam.Lifetime =
		NumberRange.new(
			0.3,
			0.6
		)

	foam.Speed =
		NumberRange.new(
			0.4,
			1.2
		)

	foam.Acceleration =
		Vector3.new(
			0,
			3,
			0
		)

	foam.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	foam.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.04
			),

			NumberSequenceKeypoint.new(
				0.3,
				0.18
			),

			NumberSequenceKeypoint.new(
				1,
				0
			),
		})

	foam.Transparency =
		NumberSequence.new(
			0.2,
			1
		)

	foam.Color =
		ColorSequence.new(
			Color3.fromRGB(
				195,
				241,
				255
			)
		)

	foam.LightEmission =
		0.3

	foam.LightInfluence =
		0

	foam.Parent =
		bubble

	local weld =
		Instance.new("WeldConstraint")

	weld.Name =
		"TargetWeld"

	weld.Part0 =
		targetRoot

	weld.Part1 =
		bubble

	weld.Parent =
		bubble

	local grow =
		TweenService:Create(
			bubble,
			TweenInfo.new(
				0.14,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Size = Vector3.one * 7,
			}
		)

	local state = {
		connections = {},
		grow = grow,
	}

	activePrisons[bubble] =
		state

	bubble.Parent =
		workspace

	if constraint then

		table.insert(
			state.connections,

			constraint.Destroying:Connect(
				function()

					WaterPrisonVFX.ReleasePrison(
						bubble
					)
				end
			)
		)
	end

	table.insert(
		state.connections,

		targetRoot.AncestryChanged:Connect(
			function()

				if not targetRoot:IsDescendantOf(
					workspace
					) then

					WaterPrisonVFX.ReleasePrison(
						bubble
					)
				end
			end
		)
	)

	table.insert(
		state.connections,

		bubble.Destroying:Connect(
			function()

				if activePrisons[bubble] then

					activePrisons[bubble] =
						nil

					for _, connection in ipairs(
						state.connections
						) do

						connection:Disconnect()
					end
				end
			end
		)
	)

	grow:Play()

	Debris:AddItem(
		bubble,
		duration + 2
	)

	return bubble
end

---------------------------------------------------------------------
-- WATER PRISON
---------------------------------------------------------------------

local WaterPrison = {}

WaterPrison.Id =
	"WaterPrison"

WaterPrison.NatureId =
	"Water"

WaterPrison.TechniqueCategory =
	"ElementalNinjutsu"

WaterPrison.MinimumLevel =
	1

WaterPrison.SortOrder =
	140

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

WaterPrison.Config = {
	DisplayName =
		"Water Prison",

	NatureId =
		"Water",

	TechniqueCategory =
		"ElementalNinjutsu",

	MinimumLevel =
		1,

	SortOrder =
		140,

	ChakraCost =
		24,

	Cooldown =
		9.0,

	CastTime =
		1.0,

	Damage =
		6,

	Projectile = {
		Speed =
			58,

		MaxDistance =
			46,

		Radius =
			2.0,

		SpawnForwardOffset =
			2.25,
	},

	Prison = {
		Duration =
			1.90,

		-----------------------------------------------------------------
		-- ALTURA FINAL
		-----------------------------------------------------------------

		FloatHeight =
			3.5,

		-----------------------------------------------------------------
		-- TIEMPO QUE TARDA EN SUBIR.
		--
		-- Mayor = subida mas lenta.
		-----------------------------------------------------------------

		FloatRiseTime =
			0.85,

		-----------------------------------------------------------------
		-- SUAVIDAD DEL ALIGNPOSITION.
		--
		-- Antes era 80 y hacia un tiron muy rapido.
		-----------------------------------------------------------------

		FloatResponsiveness =
			22,

		-----------------------------------------------------------------
		-- VELOCIDAD MAXIMA DURANTE LA SUBIDA.
		-----------------------------------------------------------------

		FloatMaxVelocity =
			6,

		MaxForce =
			1000000,

		MaxTorque =
			1000000,

		Responsiveness =
			80,
	},
}

---------------------------------------------------------------------
-- MARKERS
---------------------------------------------------------------------

WaterPrison.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

WaterPrison.MarkerCastTimeout =
	8.0

WaterPrison.ProjectileFallbackDelay =
	6.0

WaterPrison.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local function isFiniteNumber(
	value
)

	return value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function sanitizeDirection(
	character,
	payload
)

	if typeof(payload) ~= "table" then

		return false,
			"InvalidPayload",
			nil
	end

	local rawDirection =
		payload.Direction

	if typeof(rawDirection) ~= "Vector3"
		or not isFiniteNumber(rawDirection.X)
		or not isFiniteNumber(rawDirection.Y)
		or not isFiniteNumber(rawDirection.Z)
		or rawDirection.Magnitude < 0.001 then

		return false,
			"InvalidDirection",
			nil
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA("BasePart") then

		return false,
			"NoRoot",
			nil
	end

	local direction =
		rawDirection.Unit

	local horizontalDirection =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	local horizontalLook =
		Vector3.new(
			root.CFrame.LookVector.X,
			0,
			root.CFrame.LookVector.Z
		)

	if horizontalDirection.Magnitude > 0.001
		and horizontalLook.Magnitude > 0.001
		and horizontalLook.Unit:Dot(
			horizontalDirection.Unit
		) < -0.25 then

		return false,
			"AimBehindCharacter",
			nil
	end

	return true,
		"OK",
		direction
end

function WaterPrison.SanitizeRequest(
	character,
	payload
)

	local ok,
		reason,
		direction =
		sanitizeDirection(
			character,
			payload
		)

	if not ok
		or not direction then

		return false,
			reason,
			nil
	end

	return true,
		"OK",
		{
			Direction = direction,
		}
end

local function refreshReleaseAim(
	context,
	markerPayload
)

	if typeof(markerPayload) ~= "table" then
		return
	end

	local ok,
		_reason,
		direction =
		sanitizeDirection(
			context.Character,
			markerPayload
		)

	if ok
		and direction then

		context.RequestData.Direction =
			direction
	end
end

---------------------------------------------------------------------
-- CASTER
---------------------------------------------------------------------

local function getAliveHeadRoot(
	context
)

	local character =
		context.Character

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return nil,
			nil
	end

	local head =
		character:FindFirstChild(
			"Head"
		)

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not head
		or not head:IsA("BasePart")
		or not root
		or not root:IsA("BasePart") then

		return nil,
			nil
	end

	return head,
		root
end

---------------------------------------------------------------------
-- ENTITY
---------------------------------------------------------------------

local function resolveDamageableEntity(
	context,
	instance
)

	if not instance
		or not instance:IsA("BasePart") then

		return nil
	end

	local entity =
		context.CombatEntityService
		.ResolveFromInstance(
			instance
		)

	if not entity
		or not entity.Character
		or entity.Character == context.Character
		or not entity.CanReceiveDamage
		or not context.CombatEntityService.IsAlive(entity)
		or entity.Character:GetAttribute(
			"CombatImmune"
		) == true
			or entity.Character:GetAttribute(
				"IsMissionNPC"
			) == true then

		return nil
	end

	return entity
end

---------------------------------------------------------------------
-- CLEAR EXISTING PRISON
---------------------------------------------------------------------

local function clearExistingPrison(
	targetRoot
)

	local constraint =
		targetRoot:FindFirstChild(
			"WaterPrisonConstraint"
		)

	if constraint then
		constraint:Destroy()
	end

	local orientation =
		targetRoot:FindFirstChild(
			"WaterPrisonOrientation"
		)

	if orientation then
		orientation:Destroy()
	end

	local attachment =
		targetRoot:FindFirstChild(
			"WaterPrisonAttachment"
		)

	if attachment then
		attachment:Destroy()
	end
end

---------------------------------------------------------------------
-- APPLY PRISON
---------------------------------------------------------------------

local function applyPrison(
	context,
	entity,
	duration
)

	local targetCharacter =
		entity.Character

	if not targetCharacter
		or not targetCharacter.Parent then

		return
	end

	local targetRoot =
		targetCharacter:FindFirstChild(
			"HumanoidRootPart"
		)

	if not targetRoot
		or not targetRoot:IsA("BasePart") then

		return
	end

	clearExistingPrison(
		targetRoot
	)

	local prisonConfig =
		context.Config.Prison
		or WaterPrison.Config.Prison

	local maxForce =
		if typeof(prisonConfig.MaxForce) == "number"
		then prisonConfig.MaxForce
		else 1000000

	local maxTorque =
		if typeof(prisonConfig.MaxTorque) == "number"
		then prisonConfig.MaxTorque
		else 1000000

	local responsiveness =
		if typeof(prisonConfig.Responsiveness) == "number"
		then prisonConfig.Responsiveness
		else 80

	local floatHeight =
		if typeof(prisonConfig.FloatHeight) == "number"
		then math.clamp(
			prisonConfig.FloatHeight,
			0,
			12
		)
		else 3.5

	-----------------------------------------------------------------
	-- SMOOTH FLOAT CONFIG
	-----------------------------------------------------------------

	local floatRiseTime =
		if typeof(prisonConfig.FloatRiseTime) == "number"
		then math.clamp(
			prisonConfig.FloatRiseTime,
			0.15,
			duration
		)
		else 0.85

	local floatResponsiveness =
		if typeof(prisonConfig.FloatResponsiveness) == "number"
		then math.clamp(
			prisonConfig.FloatResponsiveness,
			1,
			200
		)
		else 22

	local floatMaxVelocity =
		if typeof(prisonConfig.FloatMaxVelocity) == "number"
		then math.max(
			0.5,
			prisonConfig.FloatMaxVelocity
		)
		else 6

	-----------------------------------------------------------------
	-- POSITIONS
	-----------------------------------------------------------------

	local originalPosition =
		targetRoot.Position

	local floatingPosition =
		originalPosition
		+ Vector3.new(
			0,
			floatHeight,
			0
		)

	-----------------------------------------------------------------
	-- ATTACHMENT
	-----------------------------------------------------------------

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"WaterPrisonAttachment"

	attachment.Parent =
		targetRoot

	-----------------------------------------------------------------
	-- POSITION LOCK
	--
	-- Starts exactly where target currently is.
	-- Then the target position itself is tweened upward.
	-----------------------------------------------------------------

	local alignPosition =
		Instance.new("AlignPosition")

	alignPosition.Name =
		"WaterPrisonConstraint"

	alignPosition.Mode =
		Enum.PositionAlignmentMode.OneAttachment

	alignPosition.Attachment0 =
		attachment

	alignPosition.Position =
		originalPosition

	alignPosition.ApplyAtCenterOfMass =
		true

	alignPosition.RigidityEnabled =
		false

	alignPosition.MaxForce =
		maxForce

	alignPosition.MaxVelocity =
		floatMaxVelocity

	alignPosition.Responsiveness =
		floatResponsiveness

	alignPosition.Parent =
		targetRoot

	-----------------------------------------------------------------
	-- ORIENTATION
	-----------------------------------------------------------------

	local alignOrientation =
		Instance.new("AlignOrientation")

	alignOrientation.Name =
		"WaterPrisonOrientation"

	alignOrientation.Mode =
		Enum.OrientationAlignmentMode.OneAttachment

	alignOrientation.Attachment0 =
		attachment

	alignOrientation.CFrame =
		targetRoot.CFrame.Rotation

	alignOrientation.RigidityEnabled =
		true

	alignOrientation.MaxTorque =
		maxTorque

	alignOrientation.Responsiveness =
		responsiveness

	alignOrientation.Parent =
		targetRoot

	-----------------------------------------------------------------
	-- CANCEL CURRENT MOMENTUM
	-----------------------------------------------------------------

	targetRoot.AssemblyLinearVelocity =
		Vector3.zero

	targetRoot.AssemblyAngularVelocity =
		Vector3.zero

	-----------------------------------------------------------------
	-- BUBBLE
	-----------------------------------------------------------------

	WaterPrisonVFX.CreatePrison(
		targetRoot,
		duration,
		alignPosition
	)

	-----------------------------------------------------------------
	-- SMOOTH ASCENT
	--
	-- We tween the destination itself instead of instantly setting
	-- AlignPosition.Position to the final height.
	--
	-- Sine InOut:
	-- - starts slowly
	-- - accelerates
	-- - slows again before reaching top
	-----------------------------------------------------------------

	local riseTween =
		TweenService:Create(
			alignPosition,

			TweenInfo.new(
				floatRiseTime,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),

			{
				Position =
				floatingPosition,
			}
		)

	riseTween:Play()

	-----------------------------------------------------------------
	-- RELEASE
	-----------------------------------------------------------------

	task.delay(
		duration,

		function()

			riseTween:Cancel()

			if alignPosition.Parent then
				alignPosition:Destroy()
			end

			if alignOrientation.Parent then
				alignOrientation:Destroy()
			end

			if attachment.Parent then
				attachment:Destroy()
			end
		end
	)
end

---------------------------------------------------------------------
-- PROJECTILE
---------------------------------------------------------------------

local function executePrisonProjectile(
	context
)

	local head,
		root =
		getAliveHeadRoot(
			context
		)

	if not head
		or not root then

		return
	end

	local projectileConfig =
		context.Config.Projectile
		or WaterPrison.Config.Projectile

	local prisonConfig =
		context.Config.Prison
		or WaterPrison.Config.Prison

	local speed =
		if typeof(projectileConfig.Speed) == "number"
		then math.max(
			10,
			projectileConfig.Speed
		)
		else 58

	local maxDistance =
		if typeof(projectileConfig.MaxDistance) == "number"
		then math.max(
			10,
			projectileConfig.MaxDistance
		)
		else 46

	local radius =
		if typeof(projectileConfig.Radius) == "number"
		then math.max(
			0.5,
			projectileConfig.Radius
		)
		else 2

	local spawnForwardOffset =
		if typeof(
			projectileConfig.SpawnForwardOffset
		) == "number"
		then math.max(
			0,
			projectileConfig.SpawnForwardOffset
		)
		else 2.25

	local duration =
		if typeof(prisonConfig.Duration) == "number"
		then math.clamp(
			prisonConfig.Duration,
			0.25,
			3.0
		)
		else 1.90

	local direction =
		context.RequestData.Direction

	if typeof(direction) ~= "Vector3"
		or direction.Magnitude < 0.001 then

		direction =
			root.CFrame.LookVector
	end

	direction =
		direction.Unit

	local position =
		head.Position
		+ direction
		* spawnForwardOffset

	local travelled =
		0

	local visual =
		WaterPrisonVFX.CreateProjectile(
			position,
			radius,
			direction
		)

	local ignored = {
		context.Character,
		visual,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater =
		false

	local alive =
		true

	local connection

	local function finish()

		if not alive then
			return
		end

		alive =
			false

		if connection then

			connection:Disconnect()

			connection =
				nil
		end

		if visual
			and visual.Parent then

			WaterPrisonVFX.ReleaseProjectile(
				visual
			)
		end
	end

	local function impactAndFinish(
		impactPosition,
		impactNormal
	)

		if not alive then
			return
		end

		WaterPrisonVFX.Impact(
			impactPosition,
			impactNormal,
			radius
		)

		finish()
	end

	connection =
		RunService.Heartbeat:Connect(
			function(dt)

				if not alive then
					return
				end

				if not context.Player.Parent
					or context.Player.Character ~= context.Character
					or not context.Character.Parent then

					finish()
					return
				end

				local remaining =
				maxDistance - travelled

				local step =
				math.min(
					speed * dt,
					remaining
				)

				if step <= 0 then

					finish()
					return
				end

				local displacement =
				direction * step

				for _ = 1, 10 do

					params.FilterDescendantsInstances =
					ignored

					local result =
					workspace:Spherecast(
						position,
						radius,
						displacement,
						params
					)

					if not result then
						break
					end

					local entity =
					resolveDamageableEntity(
						context,
						result.Instance
					)

					if entity then

						context.DamageService.Apply({
							TargetCharacter =
							entity.Character,

							TargetHumanoid =
							entity.Humanoid,

							TargetPlayer =
							entity.Player,

							Attacker =
							context.Player,

							Damage =
							context.Config.Damage,

							SourceType =
							"Jutsu",

							SourceId =
							WaterPrison.Id,

							Armor =
							context.Config.Armor,
						})

						applyPrison(
							context,
							entity,
							duration
						)

						impactAndFinish(
							result.Position,
							result.Normal
						)

						return
					end

					if result.Instance:GetAttribute(
						"ProjectileIgnore"
						) == true
						or (
							result.Instance:IsA("BasePart")
							and not result.Instance.CanCollide
						) then

						table.insert(
							ignored,
							result.Instance
						)

					else

						impactAndFinish(
							result.Position,
							result.Normal
						)

						return
					end
				end

				position +=
				displacement

				travelled +=
				step

				if visual
					and visual.Parent then

					visual.CFrame =
					safeLookAt(
						position,
						direction
					)
				end

				if travelled >= maxDistance then
					finish()
				end
			end
		)
end

---------------------------------------------------------------------
-- MARKER CONTRACT
---------------------------------------------------------------------

function WaterPrison.OnCastStarted(
	_context
)
end

function WaterPrison.OnCastMarker(
	context,
	semanticMarker,
	_source,
	markerPayload
)

	if semanticMarker ==
		"ProjectileSpawn" then

		refreshReleaseAim(
			context,
			markerPayload
		)

		executePrisonProjectile(
			context
		)
	end
end

function WaterPrison.OnCastEnded(
	_context,
	_reason
)
end

function WaterPrison.Execute(
	context
)

	task.delay(
		context.Config.CastTime,

		function()

			executePrisonProjectile(
				context
			)
		end
	)
end

return WaterPrison