--!strict
-- ServerScriptService > JutsuSystem > Jutsus > WaterWave
--
-- WaterWave v10: self-contained Suiton VFX, shared WaterBullet palette.
-- Optional mesh: ReplicatedStorage/VFX/Jutsus/Water/WaterWaveAssets/WaveBodyMesh
-- FoamTexture attribute on Water reuses water_bullet_assets/water_foam.png.
-- One damage event per target; forward-only wave; no homing.

local Debris =
	game:GetService("Debris")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

---------------------------------------------------------------------
-- GENERAL UTILITIES
---------------------------------------------------------------------

local function isFiniteNumber(
	value: number
): boolean

	return value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function safeLookAt(
	position: Vector3,
	direction: Vector3
): CFrame

	local unit =
		if direction.Magnitude > 0.001
		then direction.Unit
		else Vector3.new(0, 0, -1)

	local up =
		if math.abs(
			unit:Dot(Vector3.yAxis)
		) > 0.98
		then Vector3.xAxis
		else Vector3.yAxis

	return CFrame.lookAt(
		position,
		position + unit,
		up
	)
end

---------------------------------------------------------------------
-- AIM
---------------------------------------------------------------------

local function sanitizeDirection(
	character: Model,
	payload: any
): (boolean, string, Vector3?)

	if typeof(payload) ~= "table" then
		return false, "InvalidPayload", nil
	end

	local rawDirection =
		payload.Direction

	if typeof(rawDirection) ~= "Vector3"
		or not isFiniteNumber(rawDirection.X)
		or not isFiniteNumber(rawDirection.Y)
		or not isFiniteNumber(rawDirection.Z)
		or rawDirection.Magnitude < 0.001 then

		return false, "InvalidDirection", nil
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA("BasePart") then

		return false, "NoRoot", nil
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

		return false, "AimBehindCharacter", nil
	end

	return true, "OK", direction
end

local function refreshReleaseAim(
	context: any,
	markerPayload: any?
)

	if typeof(markerPayload) ~= "table" then
		return
	end

	local ok, _reason, direction =
		sanitizeDirection(
			context.Character,
			markerPayload
		)

	if ok and direction then

		context.RequestData.Direction =
			direction
	end
end

---------------------------------------------------------------------
-- CHARACTER
---------------------------------------------------------------------

local function getAliveHeadRoot(
	context: any
): (BasePart?, BasePart?)

	local character: Model =
		context.Character

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return nil, nil
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

		return nil, nil
	end

	return head, root
end

---------------------------------------------------------------------
-- COMBAT ENTITY
---------------------------------------------------------------------

local function resolveDamageableEntity(
	context: any,
	instance: Instance?
): any?

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
		or entity.Character == context.Character
		or not entity.CanReceiveDamage
		or not context.CombatEntityService
		.IsAlive(entity)
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

-- VFX: el servidor solo avisa (inicio y hasta dónde llegó); cada cliente dibuja la ola
-- siguiendo el suelo (ReplicatedStorage > JutsuSystem > ElementalFX > Water).
local ElementalFX = require(
	ReplicatedStorage
		:WaitForChild("JutsuSystem")
		:WaitForChild("Shared")
		:WaitForChild("ElementalFX")
)


---------------------------------------------------------------------
-- GROUND FOLLOWING
---------------------------------------------------------------------

local function getGroundPosition(
	context: any,
	position: Vector3,
	fallbackY: number
): Vector3

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		context.Character,
	}

	params.IgnoreWater =
		false

	local rayOrigin =
		Vector3.new(
			position.X,
			fallbackY + 10,
			position.Z
		)

	local result =
		workspace:Raycast(
			rayOrigin,
			Vector3.new(
				0,
				-24,
				0
			),
			params
		)

	if result then

		return result.Position
	end

	return Vector3.new(
		position.X,
		fallbackY - 3,
		position.Z
	)
end

---------------------------------------------------------------------
-- WORLD BLOCKING
---------------------------------------------------------------------

local function pathBlocked(
	context: any,
	fromPosition: Vector3,
	toPosition: Vector3
): boolean

	local displacement =
		toPosition - fromPosition

	if displacement.Magnitude < 0.05 then

		return false
	end

	local ignored: {Instance} = {
		context.Character,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater =
		false

	for _ = 1, 12 do

		params.FilterDescendantsInstances =
			ignored

		local result =
			workspace:Raycast(
				fromPosition,
				displacement,
				params
			)

		if not result then

			return false
		end

		local entity =
			resolveDamageableEntity(
				context,
				result.Instance
			)

		if entity then

			table.insert(
				ignored,
				entity.Character
			)

		elseif result.Instance:GetAttribute(
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

			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- PUSH
---------------------------------------------------------------------

local function pushEntity(
	entity: any,
	direction: Vector3,
	pushSpeed: number,
	pushDuration: number,
	upwardSpeed: number
)

	if pushSpeed <= 0 then

		return
	end

	local targetRoot =
		entity.Character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not targetRoot
		or not targetRoot:IsA("BasePart") then

		return
	end

	local horizontal =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	if horizontal.Magnitude < 0.001 then

		return
	end

	horizontal =
		horizontal.Unit

	---------------------------------------------------------
	-- REMOVE OLD WATER WAVE FORCE
	---------------------------------------------------------

	local existingVelocity =
		targetRoot:FindFirstChild(
			"WaterWaveLinearVelocity"
		)

	if existingVelocity then

		existingVelocity:Destroy()
	end

	local existingAttachment =
		targetRoot:FindFirstChild(
			"WaterWaveKnockbackAttachment"
		)

	if existingAttachment then

		existingAttachment:Destroy()
	end

	---------------------------------------------------------
	-- ATTACHMENT
	---------------------------------------------------------

	local attachment =
		Instance.new("Attachment")

	attachment.Name =
		"WaterWaveKnockbackAttachment"

	attachment.Parent =
		targetRoot

	---------------------------------------------------------
	-- LINEAR VELOCITY
	---------------------------------------------------------

	local linearVelocity =
		Instance.new("LinearVelocity")

	linearVelocity.Name =
		"WaterWaveLinearVelocity"

	linearVelocity.Attachment0 =
		attachment

	linearVelocity.RelativeTo =
		Enum.ActuatorRelativeTo.World

	linearVelocity.VectorVelocity =
		horizontal * pushSpeed
		+ Vector3.new(
			0,
			upwardSpeed,
			0
		)

	linearVelocity.MaxForce =
		1000000

	linearVelocity.Parent =
		targetRoot

	---------------------------------------------------------
	-- CLEANUP
	---------------------------------------------------------

	task.delay(
		pushDuration,
		function()

			if linearVelocity.Parent then

				linearVelocity:Destroy()
			end

			if attachment.Parent then

				attachment:Destroy()
			end
		end
	)

	Debris:AddItem(
		linearVelocity,
		pushDuration + 0.35
	)

	Debris:AddItem(
		attachment,
		pushDuration + 0.35
	)
end

---------------------------------------------------------------------
-- JUTSU
---------------------------------------------------------------------

local WaterWave = {}

WaterWave.Id =
	"WaterWave"

WaterWave.NatureId =
	"Water"

WaterWave.TechniqueCategory =
	"ElementalNinjutsu"

WaterWave.MinimumLevel =
	1

WaterWave.SortOrder =
	120

WaterWave.Config = {

	DisplayName =
		"Water Wave",

	NatureId =
		"Water",

	TechniqueCategory =
		"ElementalNinjutsu",

	MinimumLevel =
		1,

	SortOrder =
		120,

	ChakraCost =
		18,

	Cooldown =
		6.0,

	CastTime =
		1.0,

	Damage =
		11,

	Wave = {

		-------------------------------------------------
		-- GAMEPLAY SIZE
		-------------------------------------------------

		Distance =
			42,

		Speed = 70,

		Width =
			17,

		Height =
			7.5,

		-------------------------------------------------
		-- MOVEMENT
		-------------------------------------------------

		StepDistance =
			2.5,

		StepInterval =
			1 / 30,

		-------------------------------------------------
		-- PUSH
		-------------------------------------------------

		PushSpeed =
			58,

		PushDuration =
			0.18,

		UpwardSpeed =
			4,

		-------------------------------------------------
		-- START POSITION
		-------------------------------------------------

		StartDistance =
			2.5,

		-------------------------------------------------
		-- VFX POSITION
		-------------------------------------------------

		-- Raise/lower the entire VFX relative to the ground.
		--
		-- If it's underground, try:
		-- 1
		-- 2
		-- 3
		VFXHeightOffset =
			0.15,

		-------------------------------------------------
		-- VFX ROTATION
		-------------------------------------------------

		-- If the effect faces backwards:
		-- 180
		--
		-- Sideways:
		-- 90
		-- or
		-- -90

		VFXYawDegrees =
			0,
	},
}

---------------------------------------------------------------------
-- CAST MARKERS
---------------------------------------------------------------------

WaterWave.AllowedCastMarkers = {

	ReleaseStart =
		true,

	ProjectileSpawn =
		true,

	RecoveryStart =
		true,

	CastEnd =
		true,
}

WaterWave.MarkerCastTimeout =
	8.0

WaterWave.ProjectileFallbackDelay =
	6.0

WaterWave.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- REQUEST
---------------------------------------------------------------------

function WaterWave.SanitizeRequest(
	character: Model,
	payload: any
): (boolean, string, any?)

	local ok, reason, direction =
		sanitizeDirection(
			character,
			payload
		)

	if not ok
		or not direction then

		return false, reason, nil
	end

	return true, "OK", {

		Direction =
			direction,
	}
end

---------------------------------------------------------------------
-- DIRECTION
---------------------------------------------------------------------

local function getHorizontalDirection(
	root: BasePart,
	requestDirection: any
): Vector3

	local raw =
		if typeof(
			requestDirection
		) == "Vector3"
		then requestDirection
		else root.CFrame.LookVector

	local horizontal =
		Vector3.new(
			raw.X,
			0,
			raw.Z
		)

	if horizontal.Magnitude < 0.001 then

		horizontal =
			Vector3.new(
				root.CFrame.LookVector.X,
				0,
				root.CFrame.LookVector.Z
			)
	end

	if horizontal.Magnitude < 0.001 then

		return Vector3.new(
			0,
			0,
			-1
		)
	end

	return horizontal.Unit
end

---------------------------------------------------------------------
-- EXECUTION
---------------------------------------------------------------------

local function executeWave(
	context: any
)

	local _head, root =
		getAliveHeadRoot(
			context
		)

	if not root then

		return
	end

	local waveConfig =
		context.Config.Wave
		or {}

	-----------------------------------------------------------------
	-- DISTANCE
	-----------------------------------------------------------------

	local distance =
		if typeof(
			waveConfig.Distance
		) == "number"
		then math.max(
			6,
			waveConfig.Distance
		)
		else 42

	-----------------------------------------------------------------
	-- WIDTH
	-----------------------------------------------------------------

	local width =
		if typeof(
			waveConfig.Width
		) == "number"
		then math.max(
			3,
			waveConfig.Width
		)
		else 17

	-----------------------------------------------------------------
	-- HEIGHT
	-----------------------------------------------------------------

	local height =
		if typeof(
			waveConfig.Height
		) == "number"
		then math.max(
			2,
			waveConfig.Height
		)
		else 7.5

	-----------------------------------------------------------------
	-- STEP DISTANCE
	-----------------------------------------------------------------

	local stepDistance =
		if typeof(
			waveConfig.StepDistance
		) == "number"
		then math.clamp(
			waveConfig.StepDistance,
			0.5,
			8
		)
		else 2.5

	-----------------------------------------------------------------
	-- STEP INTERVAL
	-----------------------------------------------------------------

	local stepInterval =
		if typeof(
			waveConfig.StepInterval
		) == "number"
		then math.clamp(
			waveConfig.StepInterval,
			0.02,
			0.3
		)
		else 1 / 30

	-----------------------------------------------------------------
	-- PUSH SPEED
	-----------------------------------------------------------------

	local speed = if typeof(waveConfig.Speed) == "number" and isFiniteNumber(waveConfig.Speed)
		then math.clamp(waveConfig.Speed, 10, 120) else stepDistance / stepInterval

	local pushSpeed =
		if typeof(
			waveConfig.PushSpeed
		) == "number"
		then math.max(
			0,
			waveConfig.PushSpeed
		)
		else 58

	-----------------------------------------------------------------
	-- PUSH DURATION
	-----------------------------------------------------------------

	local pushDuration =
		if typeof(
			waveConfig.PushDuration
		) == "number"
		then math.clamp(
			waveConfig.PushDuration,
			0.08,
			0.40
		)
		else 0.18

	-----------------------------------------------------------------
	-- UPWARD SPEED
	-----------------------------------------------------------------

	local upwardSpeed =
		if typeof(
			waveConfig.UpwardSpeed
		) == "number"
		then math.max(
			0,
			waveConfig.UpwardSpeed
		)
		else 4

	-----------------------------------------------------------------
	-- START DISTANCE
	-----------------------------------------------------------------

	local startDistance =
		if typeof(
			waveConfig.StartDistance
		) == "number"
		then math.max(
			0,
			waveConfig.StartDistance
		)
		else 2.5

	-----------------------------------------------------------------
	-- VFX HEIGHT
	-----------------------------------------------------------------

	local vfxHeightOffset =
		if typeof(
			waveConfig.VFXHeightOffset
		) == "number"
		then waveConfig.VFXHeightOffset
		else 0.15

	-----------------------------------------------------------------
	-- VFX YAW
	-----------------------------------------------------------------

	local vfxYawDegrees =
		if typeof(
			waveConfig.VFXYawDegrees
		) == "number"
		then waveConfig.VFXYawDegrees
		else 0

	-----------------------------------------------------------------
	-- CAST DIRECTION
	-----------------------------------------------------------------

	local direction =
		getHorizontalDirection(
			root,
			context.RequestData.Direction
		)

	local castOrigin =
		root.Position

	local fallbackGroundY =
		root.Position.Y

	-----------------------------------------------------------------
	-- INITIAL GROUND POSITION
	-----------------------------------------------------------------

	local initialHorizontal =
		castOrigin
		+ direction
		* startDistance

	local initialGround =
		getGroundPosition(
			context,
			initialHorizontal,
			fallbackGroundY
		)

	-----------------------------------------------------------------
	-- INITIAL VFX POSITION
	-----------------------------------------------------------------

	local initialVfxPosition =
		initialGround
		+ Vector3.new(
			0,
			vfxHeightOffset,
			0
		)

	-----------------------------------------------------------------
	-- SPAWN VFX
	-----------------------------------------------------------------

	-- Cada cliente simula la ola con estos datos (misma velocidad y mismo seguimiento del suelo)
	local fxId =
		ElementalFX.NewId()

	ElementalFX.Fire(WaterWave.Id, "Start", {
		Id = fxId,
		Caster = context.Character,
		Origin = castOrigin,
		Direction = direction,
		StartDistance = startDistance,
		Distance = distance,
		Speed = speed,
		Width = width,
		Height = height,
		HeightOffset = vfxHeightOffset,
		YawDegrees = vfxYawDegrees,
	})

	local _ = initialVfxPosition

	-----------------------------------------------------------------
	-- HIT TRACKING
	-----------------------------------------------------------------

	local hitCharacters:
		{[Model]: boolean} =
		{}

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		context.Character,
	}

	-----------------------------------------------------------------
	-- WAVE THREAD
	-----------------------------------------------------------------

	task.spawn(function()

		local travelled =
			0.0

		local previousCollisionCenter =
			initialGround
			+ Vector3.new(
				0,
				height * 0.5,
				0
			)

		while travelled < distance do
			local elapsed = task.wait(stepInterval)

			---------------------------------------------------------
			-- CASTER VALIDATION
			---------------------------------------------------------

			if not context.Player.Parent
				or context.Player.Character
				~= context.Character
				or not context.Character.Parent then

				break
			end

			local humanoid =
				context.Character:
				FindFirstChildOfClass(
					"Humanoid"
				)

			if not humanoid
				or humanoid.Health <= 0 then

				break
			end

			---------------------------------------------------------
			-- ADVANCE
			---------------------------------------------------------

			local advance =
				math.min(
					speed * math.min(elapsed, 0.15),
					distance - travelled
				)

			travelled +=
				advance

			---------------------------------------------------------
			-- HORIZONTAL POSITION
			---------------------------------------------------------

			local horizontalPosition =
				castOrigin
				+ direction
				* (
					startDistance
					+ travelled
				)

			---------------------------------------------------------
			-- FOLLOW GROUND
			---------------------------------------------------------

			local groundPosition =
				getGroundPosition(
					context,
					horizontalPosition,
					fallbackGroundY
				)

			---------------------------------------------------------
			-- HITBOX CENTER
			---------------------------------------------------------

			local collisionCenter =
				groundPosition
				+ Vector3.new(
					0,
					height * 0.5,
					0
				)

			---------------------------------------------------------
			-- BLOCKED BY WORLD
			---------------------------------------------------------

			if pathBlocked(
				context,
				previousCollisionCenter,
				collisionCenter
				) then

				break
			end

			---------------------------------------------------------
			-- MOVE VISUAL
			---------------------------------------------------------

			-- (el visual lo mueve cada cliente)

			---------------------------------------------------------
			-- HITBOX
			---------------------------------------------------------

			local hitboxCFrame =
				safeLookAt(
					(previousCollisionCenter + collisionCenter) * 0.5,
					direction
				)

			local hitboxSize =
				Vector3.new(
					width,
					height + math.abs(collisionCenter.Y - previousCollisionCenter.Y),
					advance + 4
				)

			---------------------------------------------------------
			-- FIND TARGETS
			---------------------------------------------------------

			for _, part in ipairs(
				workspace:GetPartBoundsInBox(
					hitboxCFrame,
					hitboxSize,
					overlapParams
				)
				) do

				local entity =
					resolveDamageableEntity(
						context,
						part
					)

				if entity
					and not pathBlocked(context, collisionCenter, part.Position)
					and not hitCharacters[
					entity.Character
					] then

					-------------------------------------------------
					-- ONE HIT PER CHARACTER
					-------------------------------------------------

					hitCharacters[
					entity.Character
					] = true

					-------------------------------------------------
					-- DAMAGE
					-------------------------------------------------

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
							WaterWave.Id,

						Armor =
							context.Config.Armor,
					})

					-------------------------------------------------
					-- PUSH
					-------------------------------------------------

					pushEntity(
						entity,
						direction,
						pushSpeed,
						pushDuration,
						upwardSpeed
					)
				end
			end

			previousCollisionCenter =
				collisionCenter

		end

		-----------------------------------------------------------------
		-- CLEANUP
		-----------------------------------------------------------------

		-- Hasta dónde llegó realmente (pared, lanzador muerto o distancia completa)
		ElementalFX.Fire(WaterWave.Id, "End", {
			Id = fxId,
			Travelled = travelled,
		})
	end)
end

---------------------------------------------------------------------
-- CAST CONTRACT
---------------------------------------------------------------------

function WaterWave.OnCastStarted(
	_context: any
)
end

function WaterWave.OnCastMarker(
	context: any,
	semanticMarker: string,
	_source: string,
	markerPayload: any?
)

	if semanticMarker ==
		"ProjectileSpawn" then

		refreshReleaseAim(
			context,
			markerPayload
		)

		executeWave(
			context
		)
	end
end

function WaterWave.OnCastEnded(
	_context: any,
	_reason: string
)
end

---------------------------------------------------------------------
-- LEGACY FALLBACK
---------------------------------------------------------------------

function WaterWave.Execute(
	context: any
)

	task.delay(
		context.Config.CastTime,
		function()

			executeWave(
				context
			)
		end
	)
end

---------------------------------------------------------------------
-- RETURN
---------------------------------------------------------------------

return WaterWave
