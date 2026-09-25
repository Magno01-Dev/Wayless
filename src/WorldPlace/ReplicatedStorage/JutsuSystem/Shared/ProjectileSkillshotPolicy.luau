--!strict
-- ReplicatedStorage > JutsuSystem > Shared > ProjectileSkillshotPolicy
--
-- WAYLESS shared skillshot projectile policy v1.
--
-- Skillshots remain manual and non-homing, but are intentionally forgiving:
-- aim refreshes at release, target hit volume is larger than visual art, and
-- world collision uses only a tiny projectile core.

local Policy = {}

Policy.Version = 1

Policy.CrosshairMaxDistance = 1000

Policy.TargetRadiusBonus = 1.85
Policy.TargetRadiusMin = 5.25

Policy.WorldCollisionRadius = 0.18

Policy.MaxIgnoredWorldHits = 24
Policy.MaxSimulationStepDistance = 2.0
Policy.HitOrderEpsilon = 0.05

return table.freeze(Policy)
