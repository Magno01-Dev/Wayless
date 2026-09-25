--!strict
-- StarterPlayer > StarterPlayerScripts > JutsuVFXController
--
-- WAYLESS Jutsu VFX Controller v9
--
-- PRESERVA:
--
-- - Fireball
-- - Hosenka
-- - FlameBreath
-- - GenericStaticCast
-- - StaticCastAnchor
-- - FlameBreath sigue al personaje cada frame
-- - FlameBreath LockedToPart
--
-- NUEVO:
--
-- SPRINT LOCK PARA JUTSUS
--
-- Mientras Character.JutsuRunLocked == true:
--
-- - NO puede sprintar.
-- - SI puede caminar.
-- - WalkSpeed queda limitado a JutsuRunLockWalkSpeed.
-- - Default = 16.
-- - Si el sprint intenta poner WalkSpeed 24/30/etc,
--   este controller lo devuelve a velocidad de caminar.
--
-- El servidor sigue siendo quien decide CUANDO existe el lock.
-- Este LocalScript se encarga de que el sprint local no pueda
-- visualmente/funcionalmente saltarse ese lock.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

local Debris =
	game:GetService("Debris")

local Players =
	game:GetService("Players")

---------------------------------------------------------------------
-- PLAYER
---------------------------------------------------------------------

local localPlayer =
	Players.LocalPlayer

---------------------------------------------------------------------
-- REMOTE
---------------------------------------------------------------------

local jutsuSystem =
	ReplicatedStorage:
	WaitForChild(
		"JutsuSystem"
	)

local remotes =
	jutsuSystem:
	WaitForChild(
		"Remotes"
	)

local vfxRemote =
	remotes:
	WaitForChild(
		"JutsuVFX"
	) :: RemoteEvent

---------------------------------------------------------------------
-- VFX ROOT
---------------------------------------------------------------------

local vfxFolder =
	ReplicatedStorage:
	WaitForChild(
		"VFX"
	)

local jutsuVFXFolder =
	vfxFolder:
	WaitForChild(
		"Jutsus"
	)

---------------------------------------------------------------------
-- CLIENT VFX FOLDER
---------------------------------------------------------------------

local clientVFXFolder =
	workspace:
	FindFirstChild(
		"ClientJutsuVFX"
	)

if not clientVFXFolder then

	clientVFXFolder =
		Instance.new(
			"Folder"
		)

	clientVFXFolder.Name =
		"ClientJutsuVFX"

	clientVFXFolder.Parent =
		workspace
end

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local MOUTH_DOWN_OFFSET_SCALE =
	0.13

local MOUTH_FORWARD_OFFSET =
	0.05

local FLAME_BREATH_VISUAL_DURATION =
	1.0

---------------------------------------------------------------------
-- SPRINT LOCK CONFIG
---------------------------------------------------------------------

local DEFAULT_JUTSU_WALK_SPEED =
	16

---------------------------------------------------------------------
-- TYPES
---------------------------------------------------------------------

type ProjectileState = {
	Model: Model,
	Root: BasePart,

	JutsuId: string,

	StartPosition: Vector3,
	Direction: Vector3,

	Speed: number,

	SpawnedAt: number,
	VisualStartedAt: number,

	Lifetime: number,

	StartVisualAtOrigin: boolean,

	Connection: RBXScriptConnection?,
}

type FlameBreathState = {
	Model: Model,
	Root: BasePart,

	Caster: Model,

	FallbackDirection: Vector3,

	StartedAt: number,

	Stopped: boolean,
	StopRequested: boolean,

	Connection: RBXScriptConnection?,
}

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local projectiles:
	{[string]: ProjectileState} =
	{}

local flameBreaths:
	{[string]: FlameBreathState} =
	{}

---------------------------------------------------------------------
-- SAFE LOOK AT
---------------------------------------------------------------------

local function safeLookAt(
	position: Vector3,
	direction: Vector3
): CFrame

	local unitDirection =
		if direction.Magnitude > 0.001
		then
		direction.Unit
		else
		Vector3.new(
			0,
			0,
			-1
		)

	local upVector =
		if math.abs(
			unitDirection:
			Dot(
				Vector3.yAxis
			)
		) > 0.98
		then
		Vector3.xAxis
		else
		Vector3.yAxis

	return CFrame.lookAt(
		position,
		position + unitDirection,
		upVector
	)
end

---------------------------------------------------------------------
-- MOUTH POSITION
---------------------------------------------------------------------

local function getMouthPosition(
	head: BasePart
): Vector3

	local mouthAttachment =
		head:
		FindFirstChild(
			"MouthAttachment"
		)

	if mouthAttachment
		and mouthAttachment:IsA(
			"Attachment"
		) then

		return mouthAttachment.WorldPosition
	end

	local faceFront =
		head:
		FindFirstChild(
			"FaceFrontAttachment"
		)

	if faceFront
		and faceFront:IsA(
			"Attachment"
		) then

		return faceFront.WorldPosition

		- head.CFrame.UpVector
			* (
				head.Size.Y
				* MOUTH_DOWN_OFFSET_SCALE
			)

			+ head.CFrame.LookVector
			* MOUTH_FORWARD_OFFSET
	end

	local faceCenter =
		head:
		FindFirstChild(
			"FaceCenterAttachment"
		)

	if faceCenter
		and faceCenter:IsA(
			"Attachment"
		) then

		return faceCenter.WorldPosition

		- head.CFrame.UpVector
			* (
				head.Size.Y
				* MOUTH_DOWN_OFFSET_SCALE
			)

			+ head.CFrame.LookVector
			* MOUTH_FORWARD_OFFSET
	end

	return head.CFrame:
		PointToWorldSpace(
			Vector3.new(
				0,

				-head.Size.Y
				* MOUTH_DOWN_OFFSET_SCALE,

				-head.Size.Z
				* 0.50
			)
		)
end

---------------------------------------------------------------------
-- NUMBER SEQUENCE SCALE
---------------------------------------------------------------------

local function scaleNumberSequence(
	sequence: NumberSequence,
	scale: number
): NumberSequence

	local keypoints:
		{NumberSequenceKeypoint} =
		{}

	for _, point in ipairs(
		sequence.Keypoints
		) do

		table.insert(
			keypoints,

			NumberSequenceKeypoint.new(
				point.Time,
				point.Value * scale,
				point.Envelope * scale
			)
		)
	end

	return NumberSequence.new(
		keypoints
	)
end

---------------------------------------------------------------------
-- GET JUTSU TEMPLATE
---------------------------------------------------------------------

local function getJutsuTemplate(
	modelName: string,
	natureName: string?
): Model?

	if natureName
		and natureName ~= "" then

		local natureFolder =
			jutsuVFXFolder:
			FindFirstChild(
				natureName
			)

		if natureFolder then

			local template =
				natureFolder:
				FindFirstChild(
					modelName
				)

			if template then

				if template:IsA(
					"Model"
					) then

					return template
				end

				warn(
					"[JutsuVFXController]",
					template:GetFullName(),
					"must be a Model"
				)

				return nil
			end
		end
	end

	local direct =
		jutsuVFXFolder:
		FindFirstChild(
			modelName
		)

	if direct
		and direct:IsA(
			"Model"
		) then

		return direct
	end

	local recursive =
		jutsuVFXFolder:
		FindFirstChild(
			modelName,
			true
		)

	if recursive
		and recursive:IsA(
			"Model"
		) then

		return recursive
	end

	warn(
		"[JutsuVFXController] VFX NOT FOUND",
		"| Model:",
		modelName,
		"| Nature:",
		natureName or "nil"
	)

	return nil
end

---------------------------------------------------------------------
-- GET IMPACT TEMPLATE
---------------------------------------------------------------------

local function getImpactTemplate(
	vfxName: string,
	natureName: string?,
	modelName: string?
): Instance?

	local direct =
		vfxFolder:
		FindFirstChild(
			vfxName
		)

	if direct then
		return direct
	end

	if natureName then

		local natureFolder =
			jutsuVFXFolder:
			FindFirstChild(
				natureName
			)

		if natureFolder then

			if modelName then

				local jutsuModel =
					natureFolder:
					FindFirstChild(
						modelName
					)

				if jutsuModel then

					local inside =
						jutsuModel:
						FindFirstChild(
							vfxName
						)

					if inside then
						return inside
					end
				end
			end

			local shared =
				natureFolder:
				FindFirstChild(
					vfxName
				)

			if shared then
				return shared
			end

			local recursive =
				natureFolder:
				FindFirstChild(
					vfxName,
					true
				)

			if recursive then
				return recursive
			end
		end
	end

	local jutsuDirect =
		jutsuVFXFolder:
		FindFirstChild(
			vfxName
		)

	if jutsuDirect then
		return jutsuDirect
	end

	return jutsuVFXFolder:
		FindFirstChild(
			vfxName,
			true
		)
end

---------------------------------------------------------------------
-- SCALE PROJECTILE
---------------------------------------------------------------------

local function scaleProjectileVFX(
	model: Model,
	scale: number
)

	scale =
		math.clamp(
			scale,
			0.05,
			5
		)

	if math.abs(
		scale - 1
		) < 0.001 then

		return
	end

	pcall(
		function()

			model:
				ScaleTo(
					scale
				)
		end
	)
end

---------------------------------------------------------------------
-- ENABLE PROJECTILE
---------------------------------------------------------------------

local function enableProjectileVisuals(
	model: Model
)

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			descendant.Enabled =
				true

			if descendant.Rate <= 0 then

				local authoredCount =
					descendant:
					GetAttribute(
						"EmitCount"
					)

				local emitCount =
					if typeof(
						authoredCount
					) == "number"

					then
					math.max(
						1,
						math.floor(
							authoredCount
						)
					)

					else
					8

				descendant:
					Emit(
						emitCount
					)
			end

		elseif descendant:IsA(
			"Trail"
			) then

			descendant.Enabled =
				true

		elseif descendant:IsA(
			"Beam"
			) then

			descendant.Enabled =
				true

		elseif descendant:IsA(
			"PointLight"
			)
				or descendant:IsA(
					"SpotLight"
				)
				or descendant:IsA(
					"SurfaceLight"
				) then

			descendant.Enabled =
				true
		end
	end
end

---------------------------------------------------------------------
-- DISABLE VISUALS
---------------------------------------------------------------------

local function disableProjectileVisuals(
	model: Model
)

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			descendant.Enabled =
				false

		elseif descendant:IsA(
			"Trail"
			) then

			descendant.Enabled =
				false

		elseif descendant:IsA(
			"Beam"
			) then

			descendant.Enabled =
				false

		elseif descendant:IsA(
			"PointLight"
			)
				or descendant:IsA(
					"SpotLight"
				)
				or descendant:IsA(
					"SurfaceLight"
				) then

			descendant.Enabled =
				false
		end
	end
end

---------------------------------------------------------------------
-- LINGER
---------------------------------------------------------------------

local function getVisualLinger(
	model: Model
): number

	local maximum =
		0

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			maximum =
				math.max(
					maximum,
					descendant.Lifetime.Max
				)

		elseif descendant:IsA(
			"Trail"
			) then

			maximum =
				math.max(
					maximum,
					descendant.Lifetime
				)
		end
	end

	return maximum
end

---------------------------------------------------------------------
-- PREPARE MODEL
---------------------------------------------------------------------

local function prepareGenericModel(
	model: Model
): BasePart?

	local root =
		model:
		FindFirstChild(
			"Root"
		)

	if not root then

		root =
			model:
			FindFirstChild(
				"Root",
				true
			)
	end

	if not root
		or not root:IsA(
			"BasePart"
		) then

		warn(
			"[JutsuVFXController]",
			model:GetFullName(),
			"requires Root BasePart"
		)

		return nil
	end

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"BasePart"
			) then

			descendant.Anchored =
				true

			descendant.CanCollide =
				false

			descendant.CanTouch =
				false

			descendant.CanQuery =
				false

			descendant.CastShadow =
				false
		end
	end

	model.PrimaryPart =
		root

	return root
end

---------------------------------------------------------------------
-- PREPARE PROJECTILE
---------------------------------------------------------------------

local function prepareProjectile(
	model: Model
): BasePart?

	local root =
		prepareGenericModel(
			model
		)

	if not root then
		return nil
	end

	enableProjectileVisuals(
		model
	)

	return root
end

---------------------------------------------------------------------
-- PROJECTILE POSITION
---------------------------------------------------------------------

local function setProjectilePosition(
	state: ProjectileState,
	position: Vector3
)

	state.Model:
		PivotTo(
			safeLookAt(
				position,
				state.Direction
			)
		)
end

---------------------------------------------------------------------
-- STOP PROJECTILE
---------------------------------------------------------------------

local function stopProjectile(
	projectileId: string,
	finalPosition: Vector3?
)

	local state =
		projectiles[
	projectileId
	]

	if not state then
		return
	end

	projectiles[
	projectileId
	] =
		nil

	if state.Connection then

		state.Connection:
			Disconnect()

		state.Connection =
			nil
	end

	if not state.Model.Parent then
		return
	end

	if finalPosition then

		setProjectilePosition(
			state,
			finalPosition
		)
	end

	disableProjectileVisuals(
		state.Model
	)

	local linger =
		getVisualLinger(
			state.Model
		)

	Debris:AddItem(
		state.Model,

		math.max(
			0.05,
			linger + 0.15
		)
	)
end

---------------------------------------------------------------------
-- IMPACT BURST COUNT
---------------------------------------------------------------------

local function getImpactBurstCount(
	emitter: ParticleEmitter
): number

	local emitCount =
		emitter:
		GetAttribute(
			"EmitCount"
		)

	if typeof(emitCount) ==
		"number" then

		return math.max(
			1,
			math.floor(
				emitCount
			)
		)
	end

	local burstCount =
		emitter:
		GetAttribute(
			"BurstCount"
		)

	if typeof(burstCount) ==
		"number" then

		return math.max(
			1,
			math.floor(
				burstCount
			)
		)
	end

	local lowerName =
		string.lower(
			emitter.Name
		)

	if string.find(
		lowerName,
		"smoke",
		1,
		true
		) then

		return 12
	end

	if string.find(
		lowerName,
		"speck",
		1,
		true
		) then

		return 18
	end

	if string.find(
		lowerName,
		"fire",
		1,
		true
		) then

		return 16
	end

	return 12
end

---------------------------------------------------------------------
-- IMPACT VFX
---------------------------------------------------------------------

local function playImpactVFX(
	vfxName: string,
	position: Vector3,
	direction: Vector3,
	scale: number,
	natureName: string?,
	modelName: string?
)

	local template =
		getImpactTemplate(
			vfxName,
			natureName,
			modelName
		)

	if not template then

		warn(
			"[JutsuVFXController] Missing impact VFX:",
			vfxName
		)

		return
	end

	local holder =
		Instance.new(
			"Part"
		)

	holder.Name =
		vfxName
		.. "_Impact"

	holder.Size =
		Vector3.new(
			0.1,
			0.1,
			0.1
		)

	holder.Transparency =
		1

	holder.Anchored =
		true

	holder.CanCollide =
		false

	holder.CanTouch =
		false

	holder.CanQuery =
		false

	holder.CastShadow =
		false

	holder.CFrame =
		safeLookAt(
			position,
			direction
		)

	holder.Parent =
		clientVFXFolder

	local attachment =
		Instance.new(
			"Attachment"
		)

	attachment.Name =
		"Main"

	attachment.Parent =
		holder

	local emitterCount =
		0

	local longestLifetime =
		0

	scale =
		math.clamp(
			scale,
			0.05,
			5
		)

	for _, descendant in ipairs(
		template:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			emitterCount +=
				1

			local emitter =
				descendant:
				Clone()

			emitter.Enabled =
				false

			emitter.Size =
				scaleNumberSequence(
					emitter.Size,
					scale
				)

			emitter.Speed =
				NumberRange.new(
					emitter.Speed.Min
					* scale,

					emitter.Speed.Max
					* scale
				)

			emitter.Parent =
				attachment

			longestLifetime =
				math.max(
					longestLifetime,
					emitter.Lifetime.Max
				)

			emitter:
				Emit(
					getImpactBurstCount(
						emitter
					)
				)
		end
	end

	if emitterCount == 0 then

		holder:
			Destroy()

		warn(
			"[JutsuVFXController]",
			template:GetFullName(),
			"contains no ParticleEmitters"
		)

		return
	end

	Debris:AddItem(
		holder,

		math.max(
			2,
			longestLifetime + 1
		)
	)
end

---------------------------------------------------------------------
-- PLAY PROJECTILE
---------------------------------------------------------------------

local function playProjectile(
	data: any
)

	if typeof(
		data.JutsuId
		) ~= "string"

			or typeof(
				data.ProjectileId
			) ~= "string"

			or typeof(
				data.StartPosition
			) ~= "Vector3"

			or typeof(
				data.Direction
			) ~= "Vector3"

			or typeof(
				data.Speed
			) ~= "number"

			or typeof(
				data.Lifetime
			) ~= "number"

			or typeof(
				data.SpawnedAt
			) ~= "number" then

		return
	end

	if data.Direction.Magnitude <
		0.001 then

		return
	end

	local modelName =
		data.JutsuId

	if typeof(
		data.VFXModel
		) == "string" then

		modelName =
			data.VFXModel
	end

	local natureName:
		string? =
		nil

	if typeof(
		data.VFXNature
		) == "string" then

		natureName =
			data.VFXNature
	end

	local template =
		getJutsuTemplate(
			modelName,
			natureName
		)

	if not template then
		return
	end

	if projectiles[
		data.ProjectileId
		] then

		stopProjectile(
			data.ProjectileId,
			nil
		)
	end

	local model =
		template:
		Clone()

	model.Name =
		data.JutsuId
		.. "_"
		.. tostring(
			data.ShotIndex
			or ""
		)
		.. "_"
		.. data.ProjectileId

	if typeof(
		data.VFXScale
		) == "number" then

		scaleProjectileVFX(
			model,
			data.VFXScale
		)
	end

	local root =
		prepareProjectile(
			model
		)

	if not root then

		model:
			Destroy()

		return
	end

	model.Parent =
		clientVFXFolder

	local startVisualAtOrigin =
		data.StartVisualAtOrigin ==
		true

	local visualStartedAt =
		workspace:
		GetServerTimeNow()

	local state:
		ProjectileState =
		{
			Model =
			model,

			Root =
			root,

			JutsuId =
			data.JutsuId,

			StartPosition =
			data.StartPosition,

			Direction =
			data.Direction.Unit,

			Speed =
			data.Speed,

			SpawnedAt =
			data.SpawnedAt,

			VisualStartedAt =
			visualStartedAt,

			Lifetime =
			data.Lifetime,

			StartVisualAtOrigin =
			startVisualAtOrigin,

			Connection =
			nil,
		}

	projectiles[
	data.ProjectileId
	] =
		state

	if state.StartVisualAtOrigin then

		setProjectilePosition(
			state,
			state.StartPosition
		)

	else

		local elapsed =
			math.max(
				0,

				workspace:
				GetServerTimeNow()
				- state.SpawnedAt
			)

		elapsed =
			math.min(
				elapsed,
				0.15
			)

		local position =
			state.StartPosition

			+ state.Direction
			* state.Speed
			* elapsed

		setProjectilePosition(
			state,
			position
		)
	end

	state.Connection =
		RunService.RenderStepped:
		Connect(
			function()

				if not model.Parent then

					stopProjectile(
						data.ProjectileId,
						nil
					)

					return
				end

				local elapsed:
				number

				if state.StartVisualAtOrigin then

					elapsed =
					math.max(
						0,

						workspace:
						GetServerTimeNow()
						- state.VisualStartedAt
					)

				else

					elapsed =
					math.max(
						0,

						workspace:
						GetServerTimeNow()
						- state.SpawnedAt
					)
				end

				if elapsed >
					state.Lifetime
					+ 0.5 then

					stopProjectile(
						data.ProjectileId,
						nil
					)

					return
				end

				local position =
				state.StartPosition

				+ state.Direction
				* state.Speed
				* elapsed

				setProjectilePosition(
					state,
					position
				)
			end
		)
end

---------------------------------------------------------------------
-- IMPACT
---------------------------------------------------------------------

local function playImpact(
	data: any
)

	if typeof(
		data.ProjectileId
		) ~= "string" then

		return
	end

	local position:
		Vector3? =
		nil

	if typeof(
		data.Position
		) == "Vector3" then

		position =
			data.Position
	end

	stopProjectile(
		data.ProjectileId,
		position
	)

	if not position then
		return
	end

	if typeof(
		data.ImpactVFX
		) ~= "string" then

		return
	end

	local direction =
		Vector3.new(
			0,
			0,
			-1
		)

	if typeof(
		data.Direction
		) == "Vector3"

			and data.Direction.Magnitude >
		0.001 then

		direction =
			data.Direction.Unit
	end

	local scale =
		1

	if typeof(
		data.ImpactVFXScale
		) == "number" then

		scale =
			data.ImpactVFXScale
	end

	local natureName:
		string? =
		nil

	if typeof(
		data.VFXNature
		) == "string" then

		natureName =
			data.VFXNature
	end

	local modelName:
		string? =
		nil

	if typeof(
		data.VFXModel
		) == "string" then

		modelName =
			data.VFXModel

	elseif typeof(
		data.JutsuId
		) == "string" then

		modelName =
			data.JutsuId
	end

	playImpactVFX(
		data.ImpactVFX,
		position,
		direction,
		scale,
		natureName,
		modelName
	)
end

---------------------------------------------------------------------
-- EXPIRE
---------------------------------------------------------------------

local function playExpire(
	data: any
)

	if typeof(
		data.ProjectileId
		) ~= "string" then

		return
	end

	local position:
		Vector3? =
		nil

	if typeof(
		data.Position
		) == "Vector3" then

		position =
			data.Position
	end

	stopProjectile(
		data.ProjectileId,
		position
	)
end

---------------------------------------------------------------------
-- FLAME BREATH PARTICLES
---------------------------------------------------------------------

local function enableFlameBreathVisuals(
	model: Model
)

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			-----------------------------------------------------------------
			-- PARTICLES ROTATE WITH CHARACTER
			-----------------------------------------------------------------

			descendant.LockedToPart =
				true

			if descendant.Rate > 0 then

				descendant.Enabled =
					true

			else

				descendant.Enabled =
					false

				local authoredCount =
					descendant:
					GetAttribute(
						"EmitCount"
					)

				local emitCount =
					if typeof(
						authoredCount
					) == "number"

					then
					math.max(
						1,
						math.floor(
							authoredCount
						)
					)

					else
					8

				descendant:
					Emit(
						emitCount
					)
			end

		elseif descendant:IsA(
			"Trail"
			) then

			descendant.Enabled =
				true

		elseif descendant:IsA(
			"Beam"
			) then

			descendant.Enabled =
				true

		elseif descendant:IsA(
			"PointLight"
			)
				or descendant:IsA(
					"SpotLight"
				)
				or descendant:IsA(
					"SurfaceLight"
				) then

			descendant.Enabled =
				true
		end
	end
end

---------------------------------------------------------------------
-- FLAME BREATH BURSTS
---------------------------------------------------------------------

local function emitFlameBreathBurstOnly(
	model: Model
)

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			)

				and descendant.Rate <=
				0 then

			local authoredCount =
				descendant:
				GetAttribute(
					"EmitCount"
				)

			local emitCount =
				if typeof(
					authoredCount
				) == "number"

				then
				math.max(
					1,
					math.floor(
						authoredCount
					)
				)

				else
				6

			descendant:
				Emit(
					emitCount
				)
		end
	end
end

---------------------------------------------------------------------
-- STOP FLAME BREATH
---------------------------------------------------------------------

local function stopFlameBreathImmediately(
	effectId: string
)

	local state =
		flameBreaths[
	effectId
	]

	if not state then
		return
	end

	flameBreaths[
	effectId
	] =
		nil

	state.Stopped =
		true

	if state.Connection then

		state.Connection:
			Disconnect()

		state.Connection =
			nil
	end

	if not state.Model.Parent then
		return
	end

	disableProjectileVisuals(
		state.Model
	)

	local linger =
		getVisualLinger(
			state.Model
		)

	Debris:AddItem(
		state.Model,

		math.max(
			0.10,
			linger + 0.10
		)
	)
end

---------------------------------------------------------------------
-- REQUEST FLAME BREATH STOP
---------------------------------------------------------------------

local function requestFlameBreathStop(
	effectId: string
)

	local state =
		flameBreaths[
	effectId
	]

	if not state then
		return
	end

	state.StopRequested =
		true

	local elapsed =
		workspace:
		GetServerTimeNow()
	- state.StartedAt

	if elapsed >=
		FLAME_BREATH_VISUAL_DURATION then

		stopFlameBreathImmediately(
			effectId
		)

		return
	end

	local remaining =
		FLAME_BREATH_VISUAL_DURATION
	- elapsed

	task.delay(
		remaining,

		function()

			local current =
				flameBreaths[
			effectId
			]

			if current ~= state then
				return
			end

			stopFlameBreathImmediately(
				effectId
			)
		end
	)
end

---------------------------------------------------------------------
-- START FLAME BREATH
---------------------------------------------------------------------

local function playFlameBreathStart(
	data: any
)

	if typeof(
		data.EffectId
		) ~= "string"

			or typeof(
				data.Caster
			) ~= "Instance"

			or not data.Caster:IsA(
				"Model"
			)

			or typeof(
				data.Direction
			) ~= "Vector3"

			or data.Direction.Magnitude <
			0.001 then

		return
	end

	local effectId =
		data.EffectId

	local caster =
		data.Caster :: Model

	if flameBreaths[
		effectId
		] then

		stopFlameBreathImmediately(
			effectId
		)
	end

	local modelName =
		"FlameBreath"

	if typeof(
		data.VFXModel
		) == "string" then

		modelName =
			data.VFXModel
	end

	local natureName =
		"Fire"

	if typeof(
		data.VFXNature
		) == "string" then

		natureName =
			data.VFXNature
	end

	local template =
		getJutsuTemplate(
			modelName,
			natureName
		)

	if not template then
		return
	end

	local head =
		caster:
		FindFirstChild(
			"Head"
		)

	local humanoidRoot =
		caster:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not head
		or not head:IsA(
			"BasePart"
		)

			or not humanoidRoot
			or not humanoidRoot:IsA(
				"BasePart"
			) then

		return
	end

	local model =
		template:
		Clone()

	model.Name =
		"FlameBreath_"
		.. effectId

	local root =
		prepareGenericModel(
			model
		)

	if not root then

		model:
			Destroy()

		return
	end

	model.Parent =
		clientVFXFolder

	local direction =
		humanoidRoot.CFrame.LookVector

	if direction.Magnitude <
		0.001 then

		direction =
			data.Direction
	end

	direction =
		direction.Unit

	model:
		PivotTo(
			safeLookAt(
				getMouthPosition(
					head
				),
				direction
			)
		)

	enableFlameBreathVisuals(
		model
	)

	local state:
		FlameBreathState =
		{
			Model =
			model,

			Root =
			root,

			Caster =
			caster,

			FallbackDirection =
			direction,

			StartedAt =
			workspace:
			GetServerTimeNow(),

			Stopped =
			false,

			StopRequested =
			false,

			Connection =
			nil,
		}

	flameBreaths[
	effectId
	] =
		state

	task.delay(
		FLAME_BREATH_VISUAL_DURATION,

		function()

			local current =
				flameBreaths[
			effectId
			]

			if current ~= state then
				return
			end

			stopFlameBreathImmediately(
				effectId
			)
		end
	)
end

---------------------------------------------------------------------
-- UPDATE FLAME BREATH
---------------------------------------------------------------------

local function playFlameBreathUpdate(
	data: any
)

	if typeof(
		data.EffectId
		) ~= "string" then

		return
	end

	local state =
		flameBreaths[
	data.EffectId
	]

	if not state
		or state.Stopped then

		return
	end

	if typeof(
		data.Direction
		) == "Vector3"

			and data.Direction.Magnitude >
		0.001 then

		state.FallbackDirection =
			data.Direction.Unit
	end

	local elapsed =
		workspace:
		GetServerTimeNow()
	- state.StartedAt

	if elapsed >=
		FLAME_BREATH_VISUAL_DURATION then

		stopFlameBreathImmediately(
			data.EffectId
		)

		return
	end

	emitFlameBreathBurstOnly(
		state.Model
	)
end

---------------------------------------------------------------------
-- FLAME BREATH STOP EVENT
---------------------------------------------------------------------

local function playFlameBreathStop(
	data: any
)

	if typeof(
		data.EffectId
		) ~= "string" then

		return
	end

	requestFlameBreathStop(
		data.EffectId
	)
end

---------------------------------------------------------------------
-- UPDATE ACTIVE FLAME BREATHS
---------------------------------------------------------------------

local function updateFlameBreaths()

	local now =
		workspace:
		GetServerTimeNow()

	local toStop:
		{string} =
		{}

	for effectId, state in pairs(
		flameBreaths
		) do

		if state.Stopped then

			table.insert(
				toStop,
				effectId
			)

			continue
		end

		if now - state.StartedAt >=
			FLAME_BREATH_VISUAL_DURATION then

			table.insert(
				toStop,
				effectId
			)

			continue
		end

		local model =
			state.Model

		local caster =
			state.Caster

		if not model.Parent
			or not caster.Parent then

			table.insert(
				toStop,
				effectId
			)

			continue
		end

		local head =
			caster:
			FindFirstChild(
				"Head"
			)

		local humanoidRoot =
			caster:
			FindFirstChild(
				"HumanoidRootPart"
			)

		if not head
			or not head:IsA(
				"BasePart"
			)

				or not humanoidRoot
				or not humanoidRoot:IsA(
					"BasePart"
				) then

			table.insert(
				toStop,
				effectId
			)

			continue
		end

		local direction =
			humanoidRoot.CFrame.LookVector

		if direction.Magnitude <
			0.001 then

			direction =
				state.FallbackDirection
		end

		direction =
			direction.Unit

		local mouthPosition =
			getMouthPosition(
				head
			)

		model:
			PivotTo(
				safeLookAt(
					mouthPosition,
					direction
				)
			)
	end

	for _, effectId in ipairs(
		toStop
		) do

		stopFlameBreathImmediately(
			effectId
		)
	end
end

---------------------------------------------------------------------
-- JUTSU SPRINT LOCK
--
-- IMPORTANTE:
--
-- No detiene el movimiento.
-- Solo impide superar la velocidad de CAMINAR.
--
-- FlameBreath.luau debe publicar:
--
-- JutsuRunLocked = true
-- JutsuRunLockedUntil = serverTime
-- JutsuRunLockWalkSpeed = 16
---------------------------------------------------------------------

local function enforceJutsuSprintLock()

	local character =
		localPlayer.Character

	if not character then
		return
	end

	-----------------------------------------------------------------
	-- LOCK ACTIVE?
	-----------------------------------------------------------------

	if character:
		GetAttribute(
			"JutsuRunLocked"
		) ~= true then

		return
	end

	-----------------------------------------------------------------
	-- TIME CHECK
	-----------------------------------------------------------------

	local lockedUntil =
		character:
		GetAttribute(
			"JutsuRunLockedUntil"
		)

	if typeof(
		lockedUntil
		) == "number" then

		if workspace:
			GetServerTimeNow() >=
			lockedUntil then

			return
		end
	end

	-----------------------------------------------------------------
	-- HUMANOID
	-----------------------------------------------------------------

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return
	end

	-----------------------------------------------------------------
	-- WALK SPEED CAP
	-----------------------------------------------------------------

	local walkSpeedCap =
		character:
		GetAttribute(
			"JutsuRunLockWalkSpeed"
		)

	if typeof(
		walkSpeedCap
		) ~= "number" then

		walkSpeedCap =
			DEFAULT_JUTSU_WALK_SPEED
	end

	walkSpeedCap =
		math.max(
			0,
			walkSpeedCap
		)

	-----------------------------------------------------------------
	-- FORCE WALK SPEED
	--
	-- Only lowers it if something attempts to sprint.
	--
	-- If Slow/Stun/etc already put WalkSpeed below 16,
	-- this does NOT increase it.
	-----------------------------------------------------------------

	if humanoid.WalkSpeed >
		walkSpeedCap then

		humanoid.WalkSpeed =
			walkSpeedCap
	end

	-----------------------------------------------------------------
	-- COMMON SPRINT ATTRIBUTES
	--
	-- Only touch them when they already exist.
	-----------------------------------------------------------------

	if character:
		GetAttribute(
			"Sprinting"
		) ~= nil then

		character:
			SetAttribute(
				"Sprinting",
				false
			)
	end

	if character:
		GetAttribute(
			"IsSprinting"
		) ~= nil then

		character:
			SetAttribute(
				"IsSprinting",
				false
			)
	end

	if character:
		GetAttribute(
			"Running"
		) ~= nil then

		character:
			SetAttribute(
				"Running",
				false
			)
	end

	if character:
		GetAttribute(
			"IsRunning"
		) ~= nil then

		character:
			SetAttribute(
				"IsRunning",
				false
			)
	end

	if localPlayer:
		GetAttribute(
			"Sprinting"
		) ~= nil then

		localPlayer:
			SetAttribute(
				"Sprinting",
				false
			)
	end

	if localPlayer:
		GetAttribute(
			"IsSprinting"
		) ~= nil then

		localPlayer:
			SetAttribute(
				"IsSprinting",
				false
			)
	end

	if localPlayer:
		GetAttribute(
			"Running"
		) ~= nil then

		localPlayer:
			SetAttribute(
				"Running",
				false
			)
	end

	if localPlayer:
		GetAttribute(
			"IsRunning"
		) ~= nil then

		localPlayer:
			SetAttribute(
				"IsRunning",
				false
			)
	end
end

---------------------------------------------------------------------
-- FINAL RENDER UPDATE
--
-- Corre al final del frame:
--
-- 1. FlameBreath sigue la rotacion actual.
-- 2. Sprint queda limitado a caminar.
---------------------------------------------------------------------

RunService:
	BindToRenderStep(
		"WAYLESS_JutsuVFX_FinalUpdate",

		Enum.RenderPriority.Last.Value,

		function()

			updateFlameBreaths()

			enforceJutsuSprintLock()
		end
	)

---------------------------------------------------------------------
-- GENERIC STATIC CAST
---------------------------------------------------------------------

local function getStaticCastEmitCount(
	emitter: ParticleEmitter
): number

	local emitCount =
		emitter:
		GetAttribute(
			"EmitCount"
		)

	if typeof(emitCount) == "number" then

		return math.max(
			1,
			math.floor(
				emitCount
			)
		)
	end

	local burstCount =
		emitter:
		GetAttribute(
			"BurstCount"
		)

	if typeof(burstCount) == "number" then

		return math.max(
			1,
			math.floor(
				burstCount
			)
		)
	end

	if emitter.Rate > 0 then

		return math.clamp(
			math.floor(
				emitter.Rate
					* 0.20
					+ 0.5
			),
			4,
			30
		)
	end

	return 8
end

---------------------------------------------------------------------
-- ENABLE STATIC CAST VISUALS
---------------------------------------------------------------------

local function enableStaticCastVisuals(
	model: Model
): (number, number, number)

	local emitterCount =
		0

	local burstCount =
		0

	local otherVisualCount =
		0

	for _, descendant in ipairs(
		model:GetDescendants()
		) do

		if descendant:IsA(
			"ParticleEmitter"
			) then

			emitterCount +=
				1

			if descendant.Rate > 0 then

				descendant.Enabled =
					true

			else

				descendant.Enabled =
					false
			end

			local shouldBurst =
				descendant.Rate <= 0

				or descendant:
				GetAttribute(
					"EmitCount"
				) ~= nil

				or descendant:
				GetAttribute(
					"BurstCount"
				) ~= nil

			if shouldBurst then

				burstCount +=
					1

				descendant:
					Emit(
						getStaticCastEmitCount(
							descendant
						)
					)
			end

		elseif descendant:IsA(
			"Trail"
			) then

			otherVisualCount +=
				1

			descendant.Enabled =
				true

		elseif descendant:IsA(
			"Beam"
			) then

			otherVisualCount +=
				1

			descendant.Enabled =
				true

		elseif descendant:IsA(
			"PointLight"
			)
				or descendant:IsA(
					"SpotLight"
				)
				or descendant:IsA(
					"SurfaceLight"
				) then

			otherVisualCount +=
				1

			descendant.Enabled =
				true
		end
	end

	return emitterCount,
		burstCount,
		otherVisualCount
end

---------------------------------------------------------------------
-- PIVOT MODEL BY ANCHOR
---------------------------------------------------------------------

local function pivotModelByAnchor(
	model: Model,
	anchor: BasePart,
	targetCFrame: CFrame
)

	local currentPivot =
		model:
		GetPivot()

	local anchorRelative =
		currentPivot:
		ToObjectSpace(
			anchor.CFrame
		)

	local desiredPivot =
		targetCFrame
		* anchorRelative:
		Inverse()

	model:
		PivotTo(
			desiredPivot
		)
end

---------------------------------------------------------------------
-- PLAY GENERIC STATIC CAST
---------------------------------------------------------------------

local function playGenericStaticCast(
	data: any
)

	if data.CastMode ~=
		"Static" then

		return
	end

	if typeof(
		data.JutsuId
		) ~= "string" then

		return
	end

	local targetCFrame:
		CFrame?

	if typeof(
		data.CFrame
		) == "CFrame" then

		targetCFrame =
			data.CFrame

	elseif typeof(
		data.Position
		) == "Vector3" then

		local direction =
			if typeof(
				data.Direction
			) == "Vector3"

			and data.Direction.Magnitude >
			0.001

			then
			data.Direction

			else
			Vector3.new(
				0,
				0,
				-1
			)

		targetCFrame =
			safeLookAt(
				data.Position,
				direction
			)

	else

		return
	end

	local modelName =
		data.JutsuId

	if typeof(
		data.VFXModel
		) == "string"

			and data.VFXModel ~= "" then

		modelName =
			data.VFXModel
	end

	local natureName:
		string? =
		nil

	if typeof(
		data.VFXNature
		) == "string"

			and data.VFXNature ~= "" then

		natureName =
			data.VFXNature
	end

	local template =
		getJutsuTemplate(
			modelName,
			natureName
		)

	if not template then
		return
	end

	local model =
		template:
		Clone()

	local effectSuffix =
		if typeof(
			data.EffectId
		) == "string"

		and data.EffectId ~= ""

		then
		data.EffectId

		else
		tostring(
			math.floor(
				workspace:
				GetServerTimeNow()
				* 1000
			)
		)

	model.Name =
		data.JutsuId
		.. "_Cast_"
		.. effectSuffix

	if typeof(
		data.VFXScale
		) == "number" then

		scaleProjectileVFX(
			model,
			data.VFXScale
		)
	end

	local root =
		prepareGenericModel(
			model
		)

	if not root then

		model:
			Destroy()

		return
	end

	model.Parent =
		clientVFXFolder

	local anchor =
		root

	if typeof(
		data.VFXAnchor
		) == "string"

			and data.VFXAnchor ~= "" then

		local candidate =
			model:
			FindFirstChild(
				data.VFXAnchor,
				true
			)

		if candidate
			and candidate:IsA(
				"BasePart"
			) then

			anchor =
				candidate

		else

			warn(
				"[JutsuVFXController] STATIC CAST anchor missing",
				"| Jutsu=",
				data.JutsuId,
				"| Anchor=",
				data.VFXAnchor
			)
		end
	end

	pivotModelByAnchor(
		model,
		anchor,
		targetCFrame :: CFrame
	)

	local emitterCount,
		burstEmitterCount,
		otherVisualCount =
		enableStaticCastVisuals(
			model
		)

	local duration =
		if typeof(
			data.Duration
		) == "number"

		then
		math.clamp(
			data.Duration,
			0.05,
			10.0
		)

		else
		1.0

	local linger =
		math.max(
			0.15,
			getVisualLinger(
				model
			)
		)

	print(
		"[JutsuVFXController] STATIC CAST",
		"| Jutsu=",
		data.JutsuId,
		"| Template=",
		template:GetFullName(),
		"| Anchor=",
		anchor:GetFullName(),
		"| Emitters=",
		emitterCount,
		"| BurstEmitters=",
		burstEmitterCount,
		"| OtherVisuals=",
		otherVisualCount,
		"| Duration=",
		duration
	)

	task.delay(
		duration,

		function()

			if not model.Parent then
				return
			end

			disableProjectileVisuals(
				model
			)

			Debris:AddItem(
				model,
				linger + 0.15
			)
		end
	)
end

---------------------------------------------------------------------
-- REMOTE
---------------------------------------------------------------------

-- Optional renderer, loaded only for WaterBullet messages.
-- Failure here must not prevent other jutsus from starting.
local waterBulletRenderer: any = nil
local waterBulletWarned = false
local function playWaterBullet(data: any)
	if data.JutsuId ~= "WaterBullet" then return end
	local ok, reason = pcall(function()
		if not waterBulletRenderer then
			-- This controller may run from StarterCharacterScripts. Resolve the
			-- installed renderer from PlayerScripts, independently of this script.
			local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
			local module = playerScripts and playerScripts:FindFirstChild("WaterBulletRenderer")
			if not module or not module:IsA("ModuleScript") then
				module = script.Parent:FindFirstChild("WaterBulletRenderer")
			end
			if not module or not module:IsA("ModuleScript") then
				error("WaterBulletRenderer must be a ModuleScript in StarterPlayer/StarterPlayerScripts; controller is at " .. script:GetFullName())
			end
			waterBulletRenderer = require(module)
		end
		waterBulletRenderer.Handle(data)
	end)
	if not ok and not waterBulletWarned then
		waterBulletWarned = true
		warn("[JutsuVFXController] WaterBullet VFX unavailable:", reason)
	end
end

vfxRemote.OnClientEvent:
	Connect(
		function(
			action: string,
			data: any
		)

			if typeof(data) ~=
				"table" then

				return
			end

			if action == "WaterBulletVFX" then
				playWaterBullet(data)
				return
			end

			if action ==
				"Projectile" then

				playProjectile(
					data
				)

			elseif action ==
				"Impact" then

				playImpact(
					data
				)

			elseif action ==
				"Expire" then

				playExpire(
					data
				)

			elseif action ==
				"Cast" then

				playGenericStaticCast(
					data
				)

			elseif action ==
				"FlameBreathStart" then

				playFlameBreathStart(
					data
				)

			elseif action ==
				"FlameBreathUpdate" then

				playFlameBreathUpdate(
					data
				)

			elseif action ==
				"FlameBreathStop" then

				playFlameBreathStop(
					data
				)
			end
		end
	)

print(
	"[JutsuVFXController] READY"
		.. " | Fireball=ON"
		.. " | Hosenka=ON"
		.. " | FlameBreath=ON"
		.. " | FlameBreathCharacterFollow=ON"
		.. " | FlameBreathLockedToPart=ON"
		.. " | JutsuSprintLock=ON"
		.. " | GenericStaticCast=ON"
		.. " | StaticCastAnchor=ON"
)