--!strict
-- Health v1.0 - CombatTag Aware Health Regeneration
--
-- LOCATION:
-- StarterPlayer > StarterCharacterScripts > Health [Script]
--
-- IMPORTANT:
-- The script MUST be named exactly "Health".
-- Having your own Script named "Health" in StarterCharacterScripts replaces
-- Roblox's default character health-regeneration script, preventing both
-- regeneration systems from running at the same time.
--
-- BEHAVIOR:
-- Open world:
--   1% of MaxHealth regenerated per second.
--
-- CombatTagged:
--   70% slower than normal = 30% of the normal regeneration rate.
--
-- Damage delay:
--   Regeneration begins 5 seconds after the most recent health loss.
--
-- When CombatTagged changes back to false, regeneration automatically
-- returns to the normal rate.

local RunService =
	game:GetService("RunService")


local character =
	script.Parent


local humanoid =
	character:
	WaitForChild(
		"Humanoid"
	) :: Humanoid


-- =========================================================
-- TUNING
-- =========================================================

-- Roblox-style normal regeneration:
-- 0.01 = 1% of MaxHealth per second.
local NORMAL_REGEN_PERCENT_PER_SECOND =
	0.01

-- 70% slower means only 30% of the normal rate remains.
local COMBAT_REGEN_MULTIPLIER =
	0.30

-- Seconds without taking damage before regeneration can begin.
local REGEN_DELAY_AFTER_DAMAGE =
	5.0

-- Internal update interval.
local UPDATE_INTERVAL =
	0.10


-- =========================================================
-- STATE
-- =========================================================

local lastHealth =
	humanoid.Health

local lastDamageAt =
	-time()

local accumulator =
	0.0

local alive =
	humanoid.Health > 0


-- =========================================================
-- HELPERS
-- =========================================================

local function isCombatTagged(): boolean

	return character:GetAttribute(
		"CombatTagged"
	) == true
end


local function getRegenPerSecond(): number

	local normalRate =
		humanoid.MaxHealth
		* NORMAL_REGEN_PERCENT_PER_SECOND


	if isCombatTagged() then

		return normalRate
			* COMBAT_REGEN_MULTIPLIER
	end


	return normalRate
end


local function canRegenerate(): boolean

	if not alive then
		return false
	end


	if humanoid.Health <= 0 then
		return false
	end


	if humanoid.Health >=
		humanoid.MaxHealth then

		return false
	end


	local secondsSinceDamage =
		time()
	- lastDamageAt


	if secondsSinceDamage <
		REGEN_DELAY_AFTER_DAMAGE then

		return false
	end


	return true
end


-- =========================================================
-- DAMAGE TRACKING
-- =========================================================

humanoid.HealthChanged:
	Connect(
		function(
			newHealth: number
		)

			-- Only actual health LOSS resets the regeneration delay.
			-- Healing from this script or another system does not.
			if newHealth <
				lastHealth - 0.001 then

				lastDamageAt =
				time()
			end


			lastHealth =
			newHealth


			if newHealth <= 0 then

				alive =
				false
			end
		end
	)


humanoid.Died:
	Connect(
		function()

			alive =
			false
		end
	)


-- =========================================================
-- REGEN LOOP
-- =========================================================

local heartbeatConnection:
	RBXScriptConnection?


heartbeatConnection =
	RunService.Heartbeat:
	Connect(
		function(
			deltaTime: number
		)

			if not character.Parent
				or not humanoid.Parent then

				if heartbeatConnection then

					heartbeatConnection:
					Disconnect()

					heartbeatConnection =
					nil
				end

				return
			end


			accumulator +=
			deltaTime


			if accumulator <
				UPDATE_INTERVAL then

				return
			end


			local elapsed =
			accumulator

			accumulator =
			0


			if not canRegenerate() then
				return
			end


			local regenPerSecond =
			getRegenPerSecond()


			if regenPerSecond <= 0 then
				return
			end


			local amount =
			regenPerSecond
			* elapsed


			humanoid.Health =
			math.min(
				humanoid.MaxHealth,
				humanoid.Health
				+ amount
			)


			-- Keep the comparison baseline synchronized with our own healing.
			lastHealth =
			humanoid.Health
		end
	)


print(
	"[Health] READY v1.0"
		.. " | Normal="
		.. tostring(
			NORMAL_REGEN_PERCENT_PER_SECOND
			* 100
		)
		.. "% MaxHealth/s"
		.. " | CombatMultiplier="
		.. tostring(
			COMBAT_REGEN_MULTIPLIER
		)
		.. " (70% slower)"
		.. " | DamageDelay="
		.. tostring(
			REGEN_DELAY_AFTER_DAMAGE
		)
		.. "s"
)
