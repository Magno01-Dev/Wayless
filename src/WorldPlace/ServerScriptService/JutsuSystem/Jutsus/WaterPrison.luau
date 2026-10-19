--!nonstrict
-- ServerScriptService > JutsuSystem > Jutsus > WaterPrison
--
-- WAYLESS Water Prison v7
--
-- - Prison.Duration = 1.90 segundos.
-- - La prisión flota 3.5 studs (subida lenta y suave: FloatRiseTime,
--   FloatResponsiveness, FloatMaxVelocity).
--
-- VFX: el servidor solo avisa (proyectil, impacto, burbuja y liberación);
-- cada cliente los dibuja (ReplicatedStorage > JutsuSystem > ElementalFX > Water).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ElementalFX = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("JutsuSystem")
		:WaitForChild("Shared")
		:WaitForChild("ElementalFX")
)

---------------------------------------------------------------------
-- VFX (avisos)
---------------------------------------------------------------------

local WaterPrisonVFX = {}

-- Burbuja alrededor del objetivo. Si la prisión termina antes (otra prisión,
-- el objetivo cae o deja de existir), el AlignPosition se destruye y se avisa.
function WaterPrisonVFX.CreatePrison(targetRoot, duration, constraint)
	ElementalFX.Fire("WaterPrison", "PrisonStart", {
		Target = targetRoot,
		Duration = duration,
	})

	if constraint then
		local connection
		connection = constraint.Destroying:Connect(function()
			connection:Disconnect()
			ElementalFX.Fire("WaterPrison", "PrisonEnd", {
				Target = targetRoot,
			})
		end)
	end
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

	local fxId =
		ElementalFX.Projectile(
			WaterPrison.Id,
			context.Character,
			position,
			direction,
			speed,
			maxDistance,
			radius
		)

	local ignored = {
		context.Character,
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

	local function finish(hitPosition, hitNormal)

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

		ElementalFX.ProjectileEnd(fxId, hitPosition, hitNormal)
	end

	local function impactAndFinish(
		impactPosition,
		impactNormal
	)

		finish(
			impactPosition,
			impactNormal
		)
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
