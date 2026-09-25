--!strict
-- ServerScriptService > JutsuSystem > Jutsus > FlameWave
--
-- WAYLESS FlameWave v3
--
-- HITBOX ADAPTATIVA AL VFX
--
-- ReplicatedStorage
-- └── VFX
--     └── Jutsus
--         └── Fire
--             └── FlameWave
--                 ├── Root
--                 │   ├── Fire1
--                 │   ├── Fire2
--                 │   ├── SmokeDark1
--                 │   └── Specks1
--                 │
--                 └── Hitbox [OPCIONAL PERO RECOMENDADO]
--
-- SISTEMA:
--
-- 1. Si existe un BasePart llamado "Hitbox" dentro del VFX:
--      usa EXACTAMENTE su Size.
--
-- 2. Si no existe:
--      usa el BoundingBox del Model FlameWave.
--
-- 3. Si el BoundingBox es demasiado pequeño:
--      usa los valores fallback de Config.Wave.
--
-- Esto permite que el gameplay se adapte al tamaño REAL AUTORADO
-- del VFX sin tener que cambiar Width/Height manualmente en cada jutsu.
--
-- El Hitbox del VFX puede ser:
--
-- - Transparency = 1
-- - CanCollide = false
-- - CanQuery = false
-- - CanTouch = false
--
-- Su Size representa el volumen real que debe hacer daño.
--
-- DAMAGE:
-- - Server authoritative.
-- - DamageService.
-- - Multi-target.
-- - Cada target recibe daño una sola vez por FlameWave.
--
-- VFX:
-- - Usa GenericStaticCast del JutsuVFXController.
-- - No usa placeholders.

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local HttpService =
	game:GetService("HttpService")

---------------------------------------------------------------------
-- REMOTE
---------------------------------------------------------------------

local jutsuVFXRemote =
	ReplicatedStorage:
	WaitForChild(
		"JutsuSystem"
	):
	WaitForChild(
		"Remotes"
	):
	WaitForChild(
		"JutsuVFX"
	) :: RemoteEvent

---------------------------------------------------------------------
-- VFX TEMPLATE
---------------------------------------------------------------------

local vfxRoot =
	ReplicatedStorage:
	WaitForChild(
		"VFX"
	)

local jutsusVFX =
	vfxRoot:
	WaitForChild(
		"Jutsus"
	)

local fireVFX =
	jutsusVFX:
	WaitForChild(
		"Fire"
	)

local flameWaveVFXInstance =
	fireVFX:
	WaitForChild(
		"FlameWave"
	)

local flameWaveVFX =
	flameWaveVFXInstance :: Model

---------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------

local FlameWave = {}

FlameWave.Id =
	"FlameWave"

FlameWave.NatureId =
	"Fire"

FlameWave.TechniqueCategory =
	"ElementalNinjutsu"

FlameWave.MinimumLevel =
	1

FlameWave.SortOrder =
	40

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

FlameWave.Config = {
	DisplayName =
		"Flame Wave",

	NatureId =
		"Fire",

	TechniqueCategory =
		"ElementalNinjutsu",

	MinimumLevel =
		1,

	SortOrder =
		40,

	-----------------------------------------------------------------
	-- COST / COOLDOWN
	-----------------------------------------------------------------

	ChakraCost =
		20,

	Cooldown =
		7.0,

	CastTime =
		1.0,

	-----------------------------------------------------------------
	-- DAMAGE
	-----------------------------------------------------------------

	Damage =
		14,

	-----------------------------------------------------------------
	-- WAVE
	-----------------------------------------------------------------

	Wave = {
		Distance =
			30,

		-----------------------------------------------------------------
		-- FALLBACK ONLY.
		--
		-- Normally Width and Height now come from the authored VFX.
		-----------------------------------------------------------------

		Width =
			8,

		Height =
			5,

		StepDistance =
			3.25,

		StepInterval =
			0.08,

		GroundProbeHeight =
			6,

		GroundProbeDepth =
			14,

		LaunchForwardOffset =
			2.0,

		-----------------------------------------------------------------
		-- HITBOX ADAPTIVE SYSTEM
		-----------------------------------------------------------------

		Hitbox = {
			UseVFXBounds =
				true,

			-----------------------------------------------------------------
			-- If FlameWave contains a BasePart named "Hitbox",
			-- its Size wins over everything else.
			-----------------------------------------------------------------

			HitboxPartName =
				"Hitbox",

			-----------------------------------------------------------------
			-- Optional fine tuning.
			--
			-- 1 = exact authored size.
			-----------------------------------------------------------------

			WidthScale =
				1.0,

			HeightScale =
				1.0,

			DepthScale =
				1.0,

			-----------------------------------------------------------------
			-- Slight overlap between consecutive wave sections.
			-----------------------------------------------------------------

			StepOverlap =
				1.0,

			-----------------------------------------------------------------
			-- Ignore tiny Root/model bounds such as 1x1x1 control parts.
			-- In that case fallback Width/Height are used.
			-----------------------------------------------------------------

			MinimumUsefulWidth =
				2.0,

			MinimumUsefulHeight =
				2.0,

			MinimumUsefulDepth =
				1.0,
		},
	},

	-----------------------------------------------------------------
	-- VFX
	-----------------------------------------------------------------

	VFX = {
		Nature =
			"Fire",

		Model =
			"FlameWave",

		Anchor =
			"Root",

		Duration =
			0.32,

		Scale =
			1.0,

		HeightOffset =
			0.05,
	},
}

---------------------------------------------------------------------
-- MARKERS
---------------------------------------------------------------------

FlameWave.AllowedCastMarkers = {
	ReleaseStart =
		true,

	ProjectileSpawn =
		true,

	RecoveryStart =
		true,

	CastEnd =
		true,
}

FlameWave.MarkerCastTimeout =
	8.0

FlameWave.ProjectileFallbackDelay =
	6.0

FlameWave.MinProjectileDelay =
	0.80

---------------------------------------------------------------------
-- REQUEST / AIM
---------------------------------------------------------------------

local function isFiniteNumber(
	value: number
): boolean

	return value == value
		and value ~= math.huge
		and value ~= -math.huge
end

---------------------------------------------------------------------
-- SANITIZE DIRECTION
---------------------------------------------------------------------

local function sanitizeDirection(
	character: Model,
	payload: any
): (boolean, string, Vector3?)

	if typeof(payload) ~=
		"table" then

		return false,
			"InvalidPayload",
			nil
	end

	local rawDirection =
		payload.Direction

	if typeof(rawDirection) ~=
		"Vector3"

		or not isFiniteNumber(
			rawDirection.X
		)

			or not isFiniteNumber(
				rawDirection.Y
			)

			or not isFiniteNumber(
				rawDirection.Z
			)

			or rawDirection.Magnitude <
			0.001 then

		return false,
			"InvalidDirection",
			nil
	end

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA(
			"BasePart"
		) then

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

	if horizontalDirection.Magnitude >
		0.001

			and horizontalLook.Magnitude >
		0.001

			and horizontalLook.Unit:
			Dot(
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

---------------------------------------------------------------------
-- PUBLIC SANITIZE
---------------------------------------------------------------------

function FlameWave.SanitizeRequest(
	character: Model,
	payload: any
): (boolean, string, any?)

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
			Direction =
			direction,
		}
end

---------------------------------------------------------------------
-- REFRESH RELEASE AIM
---------------------------------------------------------------------

local function refreshReleaseAim(
	context: any,
	markerPayload: any?
)

	if typeof(markerPayload) ~=
		"table" then

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
-- GET ALIVE ROOT
---------------------------------------------------------------------

local function getAliveRoot(
	context: any
): BasePart?

	local player: Player =
		context.Player

	local character: Model =
		context.Character

	if not player.Parent
		or player.Character ~=
		character
		or not character.Parent then

		return nil
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <=
		0 then

		return nil
	end

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if root
		and root:IsA(
			"BasePart"
		) then

		return root
	end

	return nil
end

---------------------------------------------------------------------
-- DAMAGEABLE ENTITY
---------------------------------------------------------------------

local function resolveDamageableEntity(
	context: any,
	instance: Instance?
): any?

	if not instance
		or not instance:IsA(
			"BasePart"
		) then

		return nil
	end

	local CombatEntityService =
		context.CombatEntityService

	local entity =
		CombatEntityService
		.ResolveFromInstance(
			instance
		)

	if not entity
		or not entity.Character

		or entity.Character ==
		context.Character

		or entity.CanReceiveDamage ~=
		true

		or not CombatEntityService
		.IsAlive(
			entity
		)

			or entity.Character:
			GetAttribute(
				"CombatImmune"
			) == true

			or entity.Character:
			GetAttribute(
				"IsMissionNPC"
			) == true then

		return nil
	end

	return entity
end

---------------------------------------------------------------------
-- HORIZONTAL DIRECTION
---------------------------------------------------------------------

local function getHorizontalDirection(
	root: BasePart,
	requestDirection: any
): Vector3

	local raw =
		if typeof(
			requestDirection
		) == "Vector3"

		then
		requestDirection

		else
		root.CFrame.LookVector

	local horizontal =
		Vector3.new(
			raw.X,
			0,
			raw.Z
		)

	if horizontal.Magnitude <
		0.001 then

		horizontal =
			Vector3.new(
				root.CFrame.LookVector.X,
				0,
				root.CFrame.LookVector.Z
			)
	end

	if horizontal.Magnitude <
		0.001 then

		return Vector3.new(
			0,
			0,
			-1
		)
	end

	return horizontal.Unit
end

---------------------------------------------------------------------
-- VFX HITBOX SIZE
--
-- Returns local dimensions:
--
-- X = width
-- Y = height
-- Z = forward depth
---------------------------------------------------------------------

local function getVFXHitboxSize(
	context: any
): Vector3

	local config =
		context.Config

	local waveConfig =
		config.Wave
		or FlameWave.Config.Wave

	local hitboxConfig =
		waveConfig.Hitbox
		or FlameWave.Config.Wave.Hitbox

	local fallbackWidth =
		if typeof(
			waveConfig.Width
		) == "number"

		then
		math.max(
			2,
			waveConfig.Width
		)

		else
		8

	local fallbackHeight =
		if typeof(
			waveConfig.Height
		) == "number"

		then
		math.max(
			2,
			waveConfig.Height
		)

		else
		5

	local fallbackDepth =
		if typeof(
			waveConfig.StepDistance
		) == "number"

		then
		math.max(
			1,
			waveConfig.StepDistance
		)

		else
		3.25

	-----------------------------------------------------------------
	-- VFX SCALE
	-----------------------------------------------------------------

	local vfxConfig =
		config.VFX
		or FlameWave.Config.VFX

	local vfxScale =
		if typeof(
			vfxConfig.Scale
		) == "number"

		then
		math.clamp(
			vfxConfig.Scale,
			0.05,
			5
		)

		else
		1

	-----------------------------------------------------------------
	-- HITBOX SCALE
	-----------------------------------------------------------------

	local widthScale =
		if typeof(
			hitboxConfig.WidthScale
		) == "number"

		then
		math.max(
			0.05,
			hitboxConfig.WidthScale
		)

		else
		1

	local heightScale =
		if typeof(
			hitboxConfig.HeightScale
		) == "number"

		then
		math.max(
			0.05,
			hitboxConfig.HeightScale
		)

		else
		1

	local depthScale =
		if typeof(
			hitboxConfig.DepthScale
		) == "number"

		then
		math.max(
			0.05,
			hitboxConfig.DepthScale
		)

		else
		1

	-----------------------------------------------------------------
	-- MINIMUM USEFUL DIMENSIONS
	-----------------------------------------------------------------

	local minimumWidth =
		if typeof(
			hitboxConfig.MinimumUsefulWidth
		) == "number"

		then
		math.max(
			0,
			hitboxConfig.MinimumUsefulWidth
		)

		else
		2

	local minimumHeight =
		if typeof(
			hitboxConfig.MinimumUsefulHeight
		) == "number"

		then
		math.max(
			0,
			hitboxConfig.MinimumUsefulHeight
		)

		else
		2

	local minimumDepth =
		if typeof(
			hitboxConfig.MinimumUsefulDepth
		) == "number"

		then
		math.max(
			0,
			hitboxConfig.MinimumUsefulDepth
		)

		else
		1

	-----------------------------------------------------------------
	-- VFX BOUNDS DISABLED
	-----------------------------------------------------------------

	if hitboxConfig.UseVFXBounds ==
		false then

		return Vector3.new(
			fallbackWidth,
			fallbackHeight,
			fallbackDepth
		)
	end

	-----------------------------------------------------------------
	-- EXACT AUTHORED HITBOX PART
	--
	-- Recommended:
	--
	-- FlameWave
	-- ├── Root
	-- └── Hitbox
	--
	-- The Hitbox Part can be completely invisible.
	-----------------------------------------------------------------

	local hitboxPartName =
		if typeof(
			hitboxConfig.HitboxPartName
		) == "string"

		then
		hitboxConfig.HitboxPartName

		else
		"Hitbox"

	local hitboxPart =
		flameWaveVFX:
		FindFirstChild(
			hitboxPartName,
			true
		)

	if hitboxPart
		and hitboxPart:IsA(
			"BasePart"
		) then

		local authored =
			hitboxPart.Size
			* vfxScale

		return Vector3.new(
			math.max(
				0.1,
				authored.X
					* widthScale
			),

			math.max(
				0.1,
				authored.Y
					* heightScale
			),

			math.max(
				0.1,
				authored.Z
					* depthScale
			)
		)
	end

	-----------------------------------------------------------------
	-- MODEL BOUNDING BOX FALLBACK
	--
	-- Works automatically when the VFX uses actual BaseParts/MeshParts
	-- representing its visible size.
	--
	-- ParticleEmitters themselves do not contribute to Roblox model
	-- bounding boxes, which is why an authored Hitbox Part is preferred.
	-----------------------------------------------------------------

	local extents =
		flameWaveVFX:
		GetExtentsSize()
		* vfxScale

	local width =
		extents.X

	local height =
		extents.Y

	local depth =
		extents.Z

	-----------------------------------------------------------------
	-- TINY CONTROL ROOT PROTECTION
	--
	-- If the Model is basically only a tiny Root carrying particles,
	-- keep the gameplay fallback instead of shrinking the hitbox.
	-----------------------------------------------------------------

	if width <
		minimumWidth then

		width =
			fallbackWidth
	end

	if height <
		minimumHeight then

		height =
			fallbackHeight
	end

	if depth <
		minimumDepth then

		depth =
			fallbackDepth
	end

	return Vector3.new(
		width
			* widthScale,

		height
			* heightScale,

		depth
			* depthScale
	)
end

---------------------------------------------------------------------
-- FIND GROUND
---------------------------------------------------------------------

local function findGround(
	context: any,
	position: Vector3,
	probeHeight: number,
	probeDepth: number
): RaycastResult?

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater =
		false

	local ignored:
		{Instance} =
		{
			context.Character,
		}

	local origin =
		position

		+ Vector3.new(
			0,
			probeHeight,
			0
		)

	local displacement =
		Vector3.new(
			0,
			-(probeHeight + probeDepth),
			0
		)

	for _ = 1, 12 do

		params.FilterDescendantsInstances =
			ignored

		local result =
			workspace:
			Raycast(
				origin,
				displacement,
				params
			)

		if not result then
			return nil
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

		elseif not result.Instance.CanCollide

			or result.Instance:
			GetAttribute(
				"ProjectileIgnore"
			) == true then

			table.insert(
				ignored,
				result.Instance
			)

		else

			return result
		end
	end

	return nil
end

---------------------------------------------------------------------
-- PATH BLOCKED
---------------------------------------------------------------------

local function pathBlocked(
	context: any,
	fromPosition: Vector3,
	toPosition: Vector3
): boolean

	local displacement =
		toPosition
	- fromPosition

	if displacement.Magnitude <=
		0.05 then

		return false
	end

	local ignored:
		{Instance} =
		{
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
			workspace:
			Raycast(
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

		elseif not result.Instance.CanCollide

			or result.Instance:
			GetAttribute(
				"ProjectileIgnore"
			) == true then

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
-- SPAWN AUTHORED VFX
---------------------------------------------------------------------

local function spawnWaveVFX(
	context: any,
	waveId: string,
	stepIndex: number,
	position: Vector3,
	direction: Vector3
)

	local config =
		context.Config

	local vfxConfig =
		config.VFX
		or FlameWave.Config.VFX

	local nature =
		if typeof(
			vfxConfig.Nature
		) == "string"

		then
		vfxConfig.Nature

		else
		"Fire"

	local model =
		if typeof(
			vfxConfig.Model
		) == "string"

		then
		vfxConfig.Model

		else
		"FlameWave"

	local anchor =
		if typeof(
			vfxConfig.Anchor
		) == "string"

		then
		vfxConfig.Anchor

		else
		"Root"

	local duration =
		if typeof(
			vfxConfig.Duration
		) == "number"

		then
		math.clamp(
			vfxConfig.Duration,
			0.05,
			3
		)

		else
		0.32

	local scale =
		if typeof(
			vfxConfig.Scale
		) == "number"

		then
		math.clamp(
			vfxConfig.Scale,
			0.05,
			5
		)

		else
		1

	local heightOffset =
		if typeof(
			vfxConfig.HeightOffset
		) == "number"

		then
		vfxConfig.HeightOffset

		else
		0.05

	jutsuVFXRemote:
		FireAllClients(
			"Cast",
			{
				JutsuId =
				FlameWave.Id,

				VFXNature =
				nature,

				VFXModel =
				model,

				CastMode =
				"Static",

				VFXAnchor =
				anchor,

				EffectId =
				waveId
				.. "_"
				.. tostring(
					stepIndex
				),

				Position =
				position

				+ Vector3.new(
					0,
					heightOffset,
					0
				),

				Direction =
				direction,

				Duration =
				duration,

				VFXScale =
				scale,
			}
		)
end

---------------------------------------------------------------------
-- EXECUTE WAVE
---------------------------------------------------------------------

local function executeWave(
	context: any
)

	local root =
		getAliveRoot(
			context
		)

	if not root then
		return
	end

	local config =
		context.Config

	local waveConfig =
		config.Wave
		or FlameWave.Config.Wave

	-----------------------------------------------------------------
	-- DISTANCE
	-----------------------------------------------------------------

	local distance =
		if typeof(
			waveConfig.Distance
		) == "number"

		then
		math.max(
			6,
			waveConfig.Distance
		)

		else
		30

	-----------------------------------------------------------------
	-- STEP DISTANCE
	-----------------------------------------------------------------

	local stepDistance =
		if typeof(
			waveConfig.StepDistance
		) == "number"

		then
		math.clamp(
			waveConfig.StepDistance,
			1,
			8
		)

		else
		3.25

	-----------------------------------------------------------------
	-- STEP INTERVAL
	-----------------------------------------------------------------

	local stepInterval =
		if typeof(
			waveConfig.StepInterval
		) == "number"

		then
		math.clamp(
			waveConfig.StepInterval,
			0.03,
			0.35
		)

		else
		0.08

	-----------------------------------------------------------------
	-- GROUND
	-----------------------------------------------------------------

	local probeHeight =
		if typeof(
			waveConfig.GroundProbeHeight
		) == "number"

		then
		math.max(
			2,
			waveConfig.GroundProbeHeight
		)

		else
		6

	local probeDepth =
		if typeof(
			waveConfig.GroundProbeDepth
		) == "number"

		then
		math.max(
			4,
			waveConfig.GroundProbeDepth
		)

		else
		14

	-----------------------------------------------------------------
	-- OFFSET
	-----------------------------------------------------------------

	local launchForwardOffset =
		if typeof(
			waveConfig.LaunchForwardOffset
		) == "number"

		then
		math.max(
			0,
			waveConfig.LaunchForwardOffset
		)

		else
		2

	-----------------------------------------------------------------
	-- AUTHORED VFX HITBOX SIZE
	-----------------------------------------------------------------

	local authoredHitboxSize =
		getVFXHitboxSize(
			context
		)

	local hitboxConfig =
		waveConfig.Hitbox
		or FlameWave.Config.Wave.Hitbox

	local stepOverlap =
		if typeof(
			hitboxConfig.StepOverlap
		) == "number"

		then
		math.max(
			0,
			hitboxConfig.StepOverlap
		)

		else
		1

	-----------------------------------------------------------------
	-- FIXED DIRECTION
	-----------------------------------------------------------------

	local direction =
		getHorizontalDirection(
			root,
			context.RequestData.Direction
		)

	-----------------------------------------------------------------
	-- FIXED ORIGIN
	-----------------------------------------------------------------

	local launchOrigin =
		root.Position

	-----------------------------------------------------------------
	-- OVERLAP
	-----------------------------------------------------------------

	local overlapParams =
		OverlapParams.new()

	overlapParams.FilterType =
		Enum.RaycastFilterType.Exclude

	overlapParams.FilterDescendantsInstances = {
		context.Character,
	}

	-----------------------------------------------------------------
	-- ONE HIT PER CHARACTER
	-----------------------------------------------------------------

	local hitCharacters:
		{[Model]: boolean} =
		{}

	-----------------------------------------------------------------
	-- WAVE ID
	-----------------------------------------------------------------

	local waveId =
		HttpService:
		GenerateGUID(
			false
		)

	-----------------------------------------------------------------
	-- RUN
	-----------------------------------------------------------------

	task.spawn(
		function()

			local travelled =
				0.0

			local stepIndex =
				0

			local previousCenter =
				launchOrigin

				+ direction
				* launchForwardOffset

			while travelled <
				distance do

				---------------------------------------------------------
				-- CASTER VALID
				---------------------------------------------------------

				if not context.Player.Parent

					or context.Player.Character ~=
					context.Character

					or not context.Character.Parent then

					return
				end

				---------------------------------------------------------
				-- ADVANCE
				---------------------------------------------------------

				local advance =
					math.min(
						stepDistance,
						distance - travelled
					)

				travelled +=
					advance

				stepIndex +=
					1

				---------------------------------------------------------
				-- INTENDED POSITION
				---------------------------------------------------------

				local intended =
					launchOrigin

					+ direction
					* (
						launchForwardOffset
						+ travelled
					)

				---------------------------------------------------------
				-- GROUND
				---------------------------------------------------------

				local groundResult =
					findGround(
						context,
						intended,
						probeHeight,
						probeDepth
					)

				if not groundResult then
					break
				end

				---------------------------------------------------------
				-- HITBOX DIMENSIONS
				--
				-- WIDTH / HEIGHT:
				-- exact VFX authored dimensions.
				--
				-- DEPTH:
				-- never smaller than this travel step so gaps cannot
				-- appear between damage volumes.
				---------------------------------------------------------

				local hitboxWidth =
					authoredHitboxSize.X

				local hitboxHeight =
					authoredHitboxSize.Y

				local hitboxDepth =
					math.max(
						authoredHitboxSize.Z,

						advance
						+ stepOverlap
					)

				---------------------------------------------------------
				-- CENTER
				--
				-- VFX originates from ground level.
				-- Hitbox extends upward through its full visual height.
				---------------------------------------------------------

				local center =
					groundResult.Position

					+ Vector3.new(
						0,
						hitboxHeight * 0.5,
						0
					)

				---------------------------------------------------------
				-- WALL
				---------------------------------------------------------

				if pathBlocked(
					context,

					previousCenter

						+ Vector3.new(
							0,
							math.min(
								1.5,
								hitboxHeight * 0.5
							),
							0
						),

					groundResult.Position

						+ Vector3.new(
							0,
							math.min(
								1.5,
								hitboxHeight * 0.5
							),
							0
						)
					) then

					break
				end

				---------------------------------------------------------
				-- HITBOX CFRAME
				---------------------------------------------------------

				local hitboxCFrame =
					CFrame.lookAt(
						center,
						center + direction
					)

				---------------------------------------------------------
				-- HITBOX SIZE FROM VFX
				---------------------------------------------------------

				local hitboxSize =
					Vector3.new(
						hitboxWidth,
						hitboxHeight,
						hitboxDepth
					)

				---------------------------------------------------------
				-- DAMAGE
				---------------------------------------------------------

				for _, part in ipairs(
					workspace:
						GetPartBoundsInBox(
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

						and not hitCharacters[
						entity.Character
						] then

						hitCharacters[
						entity.Character
						] =
							true

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
								config.Damage,

							SourceType =
								"Jutsu",

							SourceId =
								FlameWave.Id,

							Armor =
								config.Armor,
						})
					end
				end

				---------------------------------------------------------
				-- VFX
				---------------------------------------------------------

				spawnWaveVFX(
					context,
					waveId,
					stepIndex,
					groundResult.Position,
					direction
				)

				---------------------------------------------------------
				-- NEXT
				---------------------------------------------------------

				previousCenter =
					groundResult.Position

				task.wait(
					stepInterval
				)
			end
		end
	)
end

---------------------------------------------------------------------
-- CAST START
---------------------------------------------------------------------

function FlameWave.OnCastStarted(
	_context: any
)
end

---------------------------------------------------------------------
-- MARKER
---------------------------------------------------------------------

function FlameWave.OnCastMarker(
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

---------------------------------------------------------------------
-- CAST END
---------------------------------------------------------------------

function FlameWave.OnCastEnded(
	_context: any,
	_reason: string
)
end

---------------------------------------------------------------------
-- LEGACY
---------------------------------------------------------------------

function FlameWave.Execute(
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

return FlameWave