--!strict
-- ProjectileInteractionService v4 - Priority Deflection + Incoming Threat Query
-- ServerScriptService > ProjectileInteractionService [ModuleScript]
--
-- Generic server-authoritative projectile-vs-projectile layer.
--
-- Priority-deflection model:
--
-- When one projectile clearly overpowers another:
-- - the weaker projectile is strongly DEFLECTED, not destroyed
-- - the winner keeps most of its trajectory
-- - the winner pays Stability
-- - when the winner's Stability reaches 0, it becomes "spent" by being strongly
--   deflected away instead of disappearing
--
-- This preserves the existing Power / Weight / BreakPowerRatio / Stability
-- hierarchy while keeping projectile clashes visually readable.
--
-- No projectile-pair hardcoding exists here.

local CollectionService = game:GetService("CollectionService")

local ProjectileInteractionService = {}

export type ProjectileConfig = {
	ProjectileType: string,
	OwnerUserId: number,

	-- Required for server-authoritative collision-course prediction.
	Speed: number?,

	ClashPower: number,
	Weight: number,
	ClashRadius: number?,

	CanClash: boolean?,
	CanBreak: boolean?,

	MutualDeflectAngleDegrees: number?,
	WinnerDeflectAngleDegrees: number?,
	BreakPowerRatio: number?,

	ClashStability: number?,
	StabilityDamage: number?,
}

export type ProjectileCallbacks = {
	GetDirection: () -> Vector3,
	SetDirection: (newDirection: Vector3, reason: string) -> (),
	Destroy: (reason: string, impactPosition: Vector3) -> (),
}

type RuntimeProjectile = {
	runtimeId: number,
	model: Model,
	config: ProjectileConfig,
	callbacks: ProjectileCallbacks,

	previousPosition: Vector3,
	position: Vector3,

	remainingStability: number,

	active: boolean,
}

export type ClashResult = {
	handled: boolean,
	selfDestroyed: boolean,
	outcome: string,
	otherModel: Model?,
	impactPosition: Vector3,
}

export type IncomingThreat = {
	Model: Model,
	ProjectileType: string,
	OwnerUserId: number,

	Position: Vector3,
	Direction: Vector3,
	Speed: number,

	TimeToImpact: number,
	ClosestDistance: number,
	ClosestPoint: Vector3,
}

local DEFAULT_CLASH_RADIUS = 0.75
local DEFAULT_MUTUAL_DEFLECT_ANGLE = 34
local DEFAULT_WINNER_DEFLECT_ANGLE = 9
local DEFAULT_BREAK_POWER_RATIO = 1.30
local DEFAULT_CLASH_STABILITY = 1
local DEFAULT_STABILITY_DAMAGE = 1

-- Strong visual redirect for a projectile that loses a dominant clash.
local DOMINATED_DEFLECT_MIN_ANGLE = 42
local DOMINATED_DEFLECT_MAX_ANGLE = 78

-- When a winner spends its last Stability point it should stop controlling the
-- lane, but it should remain visible as a physically deflected projectile.
local SPENT_WINNER_DEFLECT_MIN_ANGLE = 48
local SPENT_WINNER_DEFLECT_MAX_ANGLE = 68

local PAIR_LOCK_TIME = 0.18
local EPSILON = 1e-6

local registry: {[Model]: RuntimeProjectile} = {}
local nextRuntimeId = 0
local pairLocks: {[string]: number} = {}


local function safeUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3

	if vector.Magnitude > EPSILON then
		return vector.Unit
	end

	if fallback.Magnitude > EPSILON then
		return fallback.Unit
	end

	return Vector3.new(0, 0, -1)
end


local function rotateVector(
	direction: Vector3,
	axis: Vector3,
	degrees: number
): Vector3

	local unitDirection =
		safeUnit(
			direction,
			Vector3.new(0, 0, -1)
		)

	local unitAxis =
		safeUnit(
			axis,
			Vector3.yAxis
		)

	local rotation =
		CFrame.fromAxisAngle(
			unitAxis,
			math.rad(
				degrees
			)
		)

	return safeUnit(
		rotation:
			VectorToWorldSpace(
				unitDirection
			),
		unitDirection
	)
end


local function getDeflectionAxis(
	directionA: Vector3,
	directionB: Vector3
): Vector3

	local axis =
		directionA:
		Cross(
			directionB
		)

	if axis.Magnitude > 0.05 then
		return axis.Unit
	end


	axis =
		directionA:
		Cross(
			Vector3.yAxis
		)


	if axis.Magnitude <= 0.05 then

		axis =
			directionA:
			Cross(
				Vector3.xAxis
			)
	end


	return safeUnit(
		axis,
		Vector3.zAxis
	)
end


local function makePairKey(
	a: RuntimeProjectile,
	b: RuntimeProjectile
): string

	if a.runtimeId <
		b.runtimeId then

		return tostring(
			a.runtimeId
		)
			.. ":"
			.. tostring(
				b.runtimeId
			)
	end


	return tostring(
		b.runtimeId
	)
		.. ":"
		.. tostring(
			a.runtimeId
		)
end


local function isPairLocked(
	a: RuntimeProjectile,
	b: RuntimeProjectile,
	now: number
): boolean

	local key =
		makePairKey(
			a,
			b
		)

	local untilTime =
		pairLocks[
	key
	]


	if not untilTime then
		return false
	end


	if now >= untilTime then

		pairLocks[
		key
		] =
			nil

		return false
	end


	return true
end


local function lockPair(
	a: RuntimeProjectile,
	b: RuntimeProjectile,
	now: number
)

	pairLocks[
	makePairKey(
		a,
		b
	)
	] =
		now
		+ PAIR_LOCK_TIME
end


local function getClosestPointsOnSegments(
	p1: Vector3,
	q1: Vector3,
	p2: Vector3,
	q2: Vector3
): (Vector3, Vector3, number)

	local d1 =
		q1 - p1

	local d2 =
		q2 - p2

	local r =
		p1 - p2

	local a =
		d1:Dot(
			d1
		)

	local e =
		d2:Dot(
			d2
		)

	local s =
		0

	local t =
		0


	if a <= EPSILON
		and e <= EPSILON then

		return p1,
			p2,
			(
				p1 - p2
			).Magnitude
	end


	if a <= EPSILON then

		s =
			0

		t =
			math.clamp(
				d2:
				Dot(
					r
				)
				/ e,
				0,
				1
			)

	else

		local c =
			d1:
			Dot(
				r
			)


		if e <= EPSILON then

			t =
				0

			s =
				math.clamp(
					-c / a,
					0,
					1
				)

		else

			local b =
				d1:
				Dot(
					d2
				)

			local f =
				d2:
				Dot(
					r
				)

			local denominator =
				a * e
			- b * b


			if math.abs(
				denominator
				) > EPSILON then

				s =
					math.clamp(
						(
							b * f
							- c * e
						)
						/ denominator,
						0,
						1
					)

			else

				s =
					0
			end


			t =
				(
					b * s
					+ f
				)
				/ e


			if t < 0 then

				t =
					0

				s =
					math.clamp(
						-c / a,
						0,
						1
					)

			elseif t > 1 then

				t =
					1

				s =
					math.clamp(
						(
							b - c
						)
						/ a,
						0,
						1
					)
			end
		end
	end


	local pointA =
		p1
		+ d1 * s

	local pointB =
		p2
		+ d2 * t


	return pointA,
		pointB,
		(
			pointA - pointB
		).Magnitude
end


local function getEffectivePower(
	runtime: RuntimeProjectile
): number

	return math.max(
		0.01,
		runtime.config.ClashPower
	)
		* math.max(
			0.01,
			runtime.config.Weight
		)
end


local function updateStabilityAttribute(
	runtime: RuntimeProjectile
)

	if runtime.model.Parent then

		runtime.model:SetAttribute(
			"ProjectileClashStabilityRemaining",
			runtime.remainingStability
		)
	end
end


local function unregisterRuntime(
	runtime: RuntimeProjectile
)

	if not runtime.active then
		return
	end


	runtime.active =
		false


	if registry[
		runtime.model
		] == runtime then

		registry[
		runtime.model
		] =
			nil
	end


	if runtime.model.Parent then

		runtime.model:SetAttribute(
			"ProjectileInteractionActive",
			false
		)
	end


	if CollectionService:
		HasTag(
			runtime.model,
			"CombatProjectile"
		) then

		CollectionService:
			RemoveTag(
				runtime.model,
				"CombatProjectile"
			)
	end
end


function ProjectileInteractionService.Register(
	model: Model,
	config: ProjectileConfig,
	callbacks: ProjectileCallbacks,
	initialPosition: Vector3
)

	ProjectileInteractionService.Unregister(
		model
	)


	nextRuntimeId +=
		1


	local stability =
		math.max(
			0.01,
			config.ClashStability
			or DEFAULT_CLASH_STABILITY
		)


	local runtime: RuntimeProjectile = {
		runtimeId =
			nextRuntimeId,

		model =
			model,

		config =
			config,

		callbacks =
			callbacks,

		previousPosition =
			initialPosition,

		position =
			initialPosition,

		remainingStability =
			stability,

		active =
			true,
	}


	registry[
	model
	] =
		runtime


	model:SetAttribute(
		"ProjectileInteractionActive",
		true
	)

	model:SetAttribute(
		"ProjectileClashSpent",
		false
	)

	model:SetAttribute(
		"ProjectileWasDominated",
		false
	)

	model:SetAttribute(
		"ProjectileType",
		config.ProjectileType
	)

	model:SetAttribute(
		"ProjectileOwnerUserId",
		config.OwnerUserId
	)

	model:SetAttribute(
		"ProjectileSpeed",
		config.Speed
			or 0
	)

	model:SetAttribute(
		"ProjectileClashPower",
		config.ClashPower
	)

	model:SetAttribute(
		"ProjectileWeight",
		config.Weight
	)

	model:SetAttribute(
		"ProjectileClashRadius",
		config.ClashRadius
			or DEFAULT_CLASH_RADIUS
	)

	model:SetAttribute(
		"ProjectileCanClash",
		config.CanClash
			~= false
	)

	model:SetAttribute(
		"ProjectileCanBreak",
		config.CanBreak
			~= false
	)

	model:SetAttribute(
		"ProjectileClashStabilityMax",
		stability
	)

	updateStabilityAttribute(
		runtime
	)


	if not CollectionService:
		HasTag(
			model,
			"CombatProjectile"
		) then

		CollectionService:
			AddTag(
				model,
				"CombatProjectile"
			)
	end


	model.AncestryChanged:
		Connect(
			function(
				_child: Instance,
				parent: Instance?
			)

				if parent == nil then

					ProjectileInteractionService.Unregister(
						model
					)
				end
			end
		)
end


function ProjectileInteractionService.Unregister(
	model: Model
)

	local runtime =
		registry[
	model
	]


	if not runtime then
		return
	end


	unregisterRuntime(
		runtime
	)
end


function ProjectileInteractionService.UpdatePosition(
	model: Model,
	position: Vector3
)

	local runtime =
		registry[
	model
	]


	if not runtime
		or not runtime.active then

		return
	end


	runtime.previousPosition =
		runtime.position


	runtime.position =
		position
end


function ProjectileInteractionService.IsRegistered(
	model: Model
): boolean

	local runtime =
		registry[
	model
	]


	return runtime ~= nil
		and runtime.active
end


function ProjectileInteractionService.BuildRaycastExclusions(
	baseExclusions: {Instance}
): {Instance}

	local exclusions: {Instance} =
		table.clone(
			baseExclusions
		)


	for model,
		runtime in pairs(
			registry
		) do

		if runtime.active
			and model.Parent then

			table.insert(
				exclusions,
				model
			)
		end
	end


	return exclusions
end


-- ============================================================
-- INCOMING THREAT QUERY
-- ============================================================
--
-- This function only identifies genuine collision-course projectiles.
-- ProjectileServer separately decides whether the currently selected
-- throwable can physically reach an interception point in time.

function ProjectileInteractionService.GetIncomingThreats(
	targetOwnerUserId: number,
	targetPosition: Vector3,
	targetRadius: number,
	maxTimeToImpact: number
): {IncomingThreat}

	local threats: {IncomingThreat} =
		{}


	local safeRadius =
		math.max(
			0,
			targetRadius
		)


	local safeMaxTime =
		math.max(
			0,
			maxTimeToImpact
		)


	for model,
		runtime in pairs(
			registry
		) do

		if not runtime.active
			or not model.Parent then

			continue
		end


		if runtime.config.OwnerUserId ==
			targetOwnerUserId then

			continue
		end


		local speed =
			runtime.config.Speed
			or 0


		if speed <= EPSILON then
			continue
		end


		local direction =
			safeUnit(
				runtime.callbacks.GetDirection(),
				Vector3.new(
					0,
					0,
					-1
				)
			)


		local toTarget =
			targetPosition
		- runtime.position


		local forwardDistance =
			toTarget:
			Dot(
				direction
			)


		-- Already past the target plane or moving away.
		if forwardDistance <= 0 then
			continue
		end


		local timeToImpact =
			forwardDistance
			/ speed


		if timeToImpact >
			safeMaxTime then

			continue
		end


		local closestPoint =
			runtime.position
			+ direction
			* forwardDistance


		local closestDistance =
			(
				targetPosition
				- closestPoint
			).Magnitude


		if closestDistance >
			safeRadius then

			continue
		end


		table.insert(
			threats,
			{
				Model =
					model,

				ProjectileType =
					runtime.config.ProjectileType,

				OwnerUserId =
					runtime.config.OwnerUserId,

				Position =
					runtime.position,

				Direction =
					direction,

				Speed =
					speed,

				TimeToImpact =
					timeToImpact,

				ClosestDistance =
					closestDistance,

				ClosestPoint =
					closestPoint,
			}
		)
	end


	table.sort(
		threats,
		function(
			a: IncomingThreat,
			b: IncomingThreat
		)

			if math.abs(
				a.TimeToImpact
				- b.TimeToImpact
				) > 0.0001 then

				return a.TimeToImpact <
					b.TimeToImpact
			end


			return a.ClosestDistance <
				b.ClosestDistance
		end
	)


	return threats
end


local function mutualDeflect(
	selfRuntime: RuntimeProjectile,
	otherRuntime: RuntimeProjectile,
	directionA: Vector3,
	directionB: Vector3,
	axis: Vector3,
	sign: number,
	impactPosition: Vector3
): ClashResult

	local angleA =
		selfRuntime.config.MutualDeflectAngleDegrees
		or DEFAULT_MUTUAL_DEFLECT_ANGLE


	local angleB =
		otherRuntime.config.MutualDeflectAngleDegrees
		or DEFAULT_MUTUAL_DEFLECT_ANGLE


	selfRuntime.callbacks.SetDirection(
		rotateVector(
			directionA,
			axis,
			angleA * sign
		),
		"MutualDeflect"
	)


	otherRuntime.callbacks.SetDirection(
		rotateVector(
			directionB,
			axis,
			-angleB * sign
		),
		"MutualDeflect"
	)


	return {
		handled =
			true,

		selfDestroyed =
			false,

		outcome =
			"MutualDeflect",

		otherModel =
			otherRuntime.model,

		impactPosition =
			impactPosition,
	}
end


local function spendWinnerStability(
	winner: RuntimeProjectile,
	loser: RuntimeProjectile,
	axis: Vector3,
	sign: number
): boolean

	local stabilityDamage =
		math.max(
			0,
			loser.config.StabilityDamage
			or DEFAULT_STABILITY_DAMAGE
		)


	winner.remainingStability =
		math.max(
			0,
			winner.remainingStability
			- stabilityDamage
		)


	updateStabilityAttribute(
		winner
	)


	if winner.remainingStability >
		0 then

		return false
	end


	-- "Spent" no longer means deleted.
	--
	-- The projectile loses authority over the lane and is kicked visibly away.
	-- It remains a real projectile, so the clash reads as physical interaction
	-- instead of an object vanishing at the contact point.
	local currentDirection =
		safeUnit(
			winner.callbacks.GetDirection(),
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local baseAngle =
		winner.config.MutualDeflectAngleDegrees
		or DEFAULT_MUTUAL_DEFLECT_ANGLE


	local spentAngle =
		math.clamp(
			baseAngle * 1.45,
			SPENT_WINNER_DEFLECT_MIN_ANGLE,
			SPENT_WINNER_DEFLECT_MAX_ANGLE
		)


	winner.callbacks.SetDirection(
		rotateVector(
			currentDirection,
			axis,
			spentAngle * sign
		),
		"ClashStabilitySpentDeflect"
	)


	if winner.model.Parent then

		winner.model:SetAttribute(
			"ProjectileClashSpent",
			true
		)
	end


	return true
end


local function resolveClash(
	selfRuntime: RuntimeProjectile,
	otherRuntime: RuntimeProjectile,
	impactPosition: Vector3
): ClashResult

	local now =
		workspace:
		GetServerTimeNow()


	lockPair(
		selfRuntime,
		otherRuntime,
		now
	)


	local directionA =
		safeUnit(
			selfRuntime.callbacks.GetDirection(),
			Vector3.new(
				0,
				0,
				-1
			)
		)


	local directionB =
		safeUnit(
			otherRuntime.callbacks.GetDirection(),
			-directionA
		)


	local axis =
		getDeflectionAxis(
			directionA,
			directionB
		)


	local sign =
		if selfRuntime.runtimeId <
		otherRuntime.runtimeId
		then 1
		else -1


	local powerA =
		getEffectivePower(
			selfRuntime
		)


	local powerB =
		getEffectivePower(
			otherRuntime
		)


	local strongestPower =
		math.max(
			powerA,
			powerB
		)


	local weakestPower =
		math.max(
			0.01,
			math.min(
				powerA,
				powerB
			)
		)


	local ratio =
		strongestPower
		/ weakestPower


	local breakRatio =
		math.max(
			1.01,
			math.min(
				selfRuntime.config.BreakPowerRatio
				or DEFAULT_BREAK_POWER_RATIO,

				otherRuntime.config.BreakPowerRatio
				or DEFAULT_BREAK_POWER_RATIO
			)
		)


	if ratio < breakRatio then

		return mutualDeflect(
			selfRuntime,
			otherRuntime,
			directionA,
			directionB,
			axis,
			sign,
			impactPosition
		)
	end


	local selfIsStronger =
		powerA > powerB


	local stronger =
		if selfIsStronger
		then selfRuntime
		else otherRuntime


	local weaker =
		if selfIsStronger
		then otherRuntime
		else selfRuntime


	local strongerCanBreak =
		stronger.config.CanBreak
		~= false


	if not strongerCanBreak then

		return mutualDeflect(
			selfRuntime,
			otherRuntime,
			directionA,
			directionB,
			axis,
			sign,
			impactPosition
		)
	end


	local strongerDirection =
		if selfIsStronger
		then directionA
		else directionB


	local weakerDirection =
		if selfIsStronger
		then directionB
		else directionA


	local winnerAngle =
		stronger.config.WinnerDeflectAngleDegrees
		or DEFAULT_WINNER_DEFLECT_ANGLE


	local winnerSign =
		if stronger.runtimeId <
		weaker.runtimeId
		then 1
		else -1


	-- ------------------------------------------------------------
	-- DOMINANT WINNER
	-- ------------------------------------------------------------
	--
	-- Winner keeps almost all of its original lane. Heavy projectiles such as
	-- Fuma use a very small WinnerDeflectAngle, while lighter winners may move
	-- a little more.
	stronger.callbacks.SetDirection(
		rotateVector(
			strongerDirection,
			axis,
			winnerAngle
				* winnerSign
		),
		"WonClash"
	)


	-- ------------------------------------------------------------
	-- DOMINATED PROJECTILE
	-- ------------------------------------------------------------
	--
	-- Do NOT destroy it.
	--
	-- Redirect it strongly enough that the player can visually read:
	-- "that projectile was knocked aside."
	--
	-- The angle scales generically with both:
	-- - the weaker projectile's normal mutual-deflect personality
	-- - how far above the break threshold the winner actually is
	local weakerBaseAngle =
		weaker.config.MutualDeflectAngleDegrees
		or DEFAULT_MUTUAL_DEFLECT_ANGLE


	local dominanceBoost =
		math.clamp(
			(
				ratio
				- breakRatio
			) * 12,
			0,
			22
		)


	local dominatedAngle =
		math.clamp(
			weakerBaseAngle * 1.35
			+ dominanceBoost,
			DOMINATED_DEFLECT_MIN_ANGLE,
			DOMINATED_DEFLECT_MAX_ANGLE
		)


	weaker.callbacks.SetDirection(
		rotateVector(
			weakerDirection,
			axis,
			-dominatedAngle
				* winnerSign
		),
		"LostClashDeflect"
	)


	if weaker.model.Parent then

		weaker.model:SetAttribute(
			"ProjectileWasDominated",
			true
		)


		weaker.model:SetAttribute(
			"ProjectileLastDominatedDeflectAngle",
			dominatedAngle
		)
	end


	-- Winner still pays Stability exactly as before.
	--
	-- Difference:
	-- reaching Stability 0 now kicks the winner out of the lane rather than
	-- deleting it.
	local winnerSpent =
		spendWinnerStability(
			stronger,
			weaker,
			axis,
			winnerSign
		)


	local outcome: string


	if stronger == selfRuntime then

		outcome =
			if winnerSpent
			then "WonClashSpentDeflect"
			else "WonClashDeflect"

	else

		outcome =
			if winnerSpent
			then "LostClashWinnerSpentDeflect"
			else "LostClashDeflect"
	end


	return {
		handled =
			true,

		-- Priority clashes are now entirely physical deflections.
		selfDestroyed =
			false,

		outcome =
			outcome,

		otherModel =
			otherRuntime.model,

		impactPosition =
			impactPosition,
	}
end


function ProjectileInteractionService.CheckSegment(
	selfModel: Model,
	fromPosition: Vector3,
	toPosition: Vector3
): ClashResult?

	local selfRuntime =
		registry[
	selfModel
	]


	if not selfRuntime
		or not selfRuntime.active then

		return nil
	end


	if selfRuntime.config.CanClash ==
		false then

		return nil
	end


	local now =
		workspace:
		GetServerTimeNow()


	for otherModel,
		otherRuntime in pairs(
			registry
		) do

		if otherModel == selfModel
			or not otherRuntime.active
			or not otherModel.Parent
			or otherRuntime.config.CanClash ==
			false then

			continue
		end


		-- Same owner volleys never clash with themselves.
		if selfRuntime.config.OwnerUserId ==
			otherRuntime.config.OwnerUserId then

			continue
		end


		if isPairLocked(
			selfRuntime,
			otherRuntime,
			now
			) then

			continue
		end


		local pointA,
			pointB,
			distance =
			getClosestPointsOnSegments(
				fromPosition,
				toPosition,
				otherRuntime.previousPosition,
				otherRuntime.position
			)


		local selfRadius =
			selfRuntime.config.ClashRadius
			or DEFAULT_CLASH_RADIUS


		local otherRadius =
			otherRuntime.config.ClashRadius
			or DEFAULT_CLASH_RADIUS


		local contactDistance =
			selfRadius
			+ otherRadius


		if distance <= contactDistance then

			local impactPosition =
				(
					pointA
					+ pointB
				)
				* 0.5


			return resolveClash(
				selfRuntime,
				otherRuntime,
				impactPosition
			)
		end
	end


	return nil
end

print(
	"[ProjectileInteractionService] READY v4 PriorityDeflection"
		.. " | ClashStability=ON"
		.. " | IncomingThreats=ON"
		.. " | DominantDeflection=ON"
		.. " | NoClashDeletion=ON"
)


return ProjectileInteractionService
