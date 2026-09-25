--!strict
-- ProjectileConfigs v2.0 - Locked Intent + Aim Assist + Guidance/Commit
-- ReplicatedStorage > ProjectileConfigs [ModuleScript]
--
-- Design change (v2.0):
-- Normal lateral movement is still not a reliable projectile defense, but the
-- reliability now comes from AIM ASSIST + PREDICTION rather than from homing.
--
-- Offensive projectiles:
-- - lock a target ONCE, at release, and never re-acquire
-- - correct the release direction inside a tight intent cone (aim assist)
-- - lead the target using a smoothed, clamped velocity
-- - steer only lightly, with a turn-rate cap and an angular deadzone
-- - COMMIT (tracking off) once time-to-impact drops below CommitTime
-- - no pathfinding around world geometry, no U-turns
--
-- ALL LEGACY FIELDS ARE PRESERVED.
-- The v1.9 names (AcquireRange, AcquireConeDegrees, AcquireWindow,
-- TrackMaxFromOriginalDegrees, TurnRate*, TargetVelocityFactor,
-- MaxInterceptTime, ...) are still read by ProjectileServer v3.0 as fallbacks
-- and by ProjectileLaunchArcController. The NEW fields simply win when present.
--
-- Defensive projectile throws remain controlled by ProjectileServer's dedicated
-- DefensiveIntercept path and DO NOT use this offensive homing.
--
-- Projectile identity:
-- Kunai    = Guided Precision / Single x1
-- Shuriken = Converging Pressure / Sequential x3
-- Senbon   = Direct Precision / Parallel x3
-- Fuma     = Heavy Pursuit / Single x1 / Heavy Interceptor
--
-- IMPORTANT:
-- Damage is PER PROJECTILE, not per input action.

local ProjectileConfigs = {

	-- ============================================================
	-- KUNAI
	-- ============================================================

	Kunai = {
		Id = "Kunai",

		NinjaBag = {
			DisplayName = "KUNAI",
			Subtitle = "GUÍA ×1",

			-- Temporary QA quantities only.
			QAStartingAmount = 20,
			QAMaxAmount = 20,
		},

		AssetName = "Kunai",
		FolderName = "Kunais",
		ModelPrefix = "Kunai_",

		Speed = 130,
		Damage = 12,
		Range = 300,
		Lifetime = 4.0,
		Cooldown = 5.0,

		EmbedDepth = 0.20,
		StuckTime = 45.0,

		Pattern = {
			Mode = "Single",
			Count = 1,
			Interval = 0.0,
			Spacing = 0.0,
		},

		Guidance = {
			Mode = "Predictive",

			-- Broad enough that normal Combat Aim placement does not require
			-- pixel-perfect camera alignment, but still requires the enemy to
			-- be meaningfully in the attacker's forward combat space.
			AcquireRange = 270,
			AcquireConeDegrees = 82,
			AcquireWindow = 1.10,

			-- Never allow a full U-turn. Once a target has moved clearly behind
			-- the original throw lane, guidance is released.
			TrackMaxFromOriginalDegrees = 88,

			-- Old value was 10. Keeping guidance alive almost until contact is
			-- the main terminal-tracking change.
			CommitDistance = 2.75,

			-- Guided Precision:
			-- moderate far correction, strong middle correction, very strong
			-- terminal correction so ordinary strafing does not defeat Kunai.
			TurnRateFarDegreesPerSecond = 100,
			TurnRateMidDegreesPerSecond = 160,
			TurnRateNearDegreesPerSecond = 245,
			MidDistance = 48,

			-- Small ramp preserves a hand-thrown curve instead of snapping
			-- instantly toward the target on the first simulation frame.
			RampTime = 0.22,

			TargetVelocityFactor = 1.05,
			MaxInterceptTime = 1.10,
			MaxLeadDistance = 30,

			VerticalVelocityFactor = 0.60,
			VerticalAimWeight = 0.62,

			-- OLD behavior weakened guidance during evasive movement.
			-- Guided Pressure does the opposite.
			EvasiveLateralSpeed = 32,
			EvasiveTurnMultiplier = 1.25,

			-- ---------- v2.0: TARGET SELECTION ----------
			--
			-- AcquireConeDegrees (82) stays for legacy readers, but intent is
			-- now decided inside this much tighter cone, and a direct hit on
			-- the release line always wins over anything behind it.
			AimAssistConeDegrees = 15,
			AimAssistRange = 270,
			AimAssistMaxCorrectionDegrees = 15,
			AimAssistDirectRayPriority = true,

			-- ---------- v2.0: PREDICTION ----------
			PredictionStrength = 1.00,
			MaxPredictionTime = 0.80,
			MaxPredictionSpeed = 70,
			PredictionSmoothing = 0.40,
			AimPointHeightOffset = 0.35,

			-- ---------- v2.0: GUIDANCE -> COMMIT ----------
			CanTrack = true,
			GuidanceHz = 15,
			GuidanceDuration = 1.60,

			-- Speed 130 -> commit at ~26 studs. That is the Dash window:
			-- dashing earlier can still be partially tracked, dashing inside
			-- this window cannot be answered.
			CommitTime = 0.20,

			SteeringStrength = 1.00,
			MaxTurnRateDegreesPerSecond = 105,
			AngularDeadzoneDegrees = 0.6,
			MaxTrackingAngleDegrees = 30,

			-- ---------- v2.0: COUNTERS ----------
			BreakTrackingOnSubstitution = true,
			BreakTrackingOnDash = false,

			-- ---------- v2.0: HITBOX / TELEGRAPH ----------
			HitboxScale = 1.25,
			NearMissRadius = 3.25,
		},

		Clash = {
			Power = 50,

			-- 50 * 1.05 = 52.5 vs Shuriken 50 * 0.80 = 40.
			Weight = 1.05,

			Radius = 0.75,

			CanClash = true,
			CanBreak = true,

			MutualDeflectAngleDegrees = 34,

			-- Keeps a winning Kunai close enough to its lane to contest the
			-- next projectile in a sequential volley.
			WinnerDeflectAngleDegrees = 2,

			BreakPowerRatio = 1.30,

			Stability = 2,
			StabilityDamage = 1,
		},

		Armor = {
			Penetration = 0.12,
			DurabilityDamage = 1.00,
		},

		Visual = {
			Mode = "KunaiFixed",

			ScaleMode = "Preserve",

			PitchOffset = -math.pi / 2,
			YawOffset = 0,
			RollOffset = 0,

			Trail = {
				Enabled = true,
				Kind = "Kunai",
				Lifetime = 0.14,
				MinLength = 0.08,
				MinHalfWidth = 0.07,
				MaxHalfWidth = 0.16,
				LightEmission = 1.0,
				LightInfluence = 0.0,
				FaceCamera = true,
			},
		},

		Audio = {
			Launch = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 1.00,
				PlaybackSpeed = 1.00,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Lifetime = 4.0,
			},

			Travel = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 0.45,
				PlaybackSpeed = 1.00,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Looped = true,
				RollOffMinDistance = 7,
				RollOffMaxDistance = 80,
				EmitterSize = 3,
			},

			Hit = {
				SoundId = "rbxassetid://2782131222",
				Volume = 0.90,
				PlaybackSpeed = 1.00,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 5,
				RollOffMaxDistance = 100,
			},

			Stick = {
				SoundId = "rbxassetid://9116197517",
				Volume = 0.90,
				PlaybackSpeed = 1.00,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 5,
				RollOffMaxDistance = 100,
			},
		},
	},

	-- ============================================================
	-- SHURIKEN
	-- ============================================================

	Shuriken = {
		Id = "Shuriken",

		NinjaBag = {
			DisplayName = "SHURIKEN",
			Subtitle = "RÁFAGA ×3",

			QAStartingAmount = 20,
			QAMaxAmount = 20,
		},

		AssetName = "shuriken",
		FolderName = "Shurikens",
		ModelPrefix = "Shuriken_",

		Speed = 155,

		-- Three projectiles per action:
		-- 4 + 4 + 4 = 12 maximum raw damage.
		Damage = 4,

		Range = 260,
		Lifetime = 3.25,
		Cooldown = 4.0,

		EmbedDepth = 0.18,
		StuckTime = 45.0,

		Pattern = {
			-- v1.8 visual identity:
			-- three simultaneous lanes launch left / center / right and then
			-- Predictive guidance converges them toward the locked target.
			--
			-- This is intentionally a VISUAL convergence approximation that does
			-- not require changing ProjectileServer v2.6 / Counter code.
			Mode = "Parallel",
			Count = 3,
			Interval = 0.0,
			Spacing = 0.90,
		},

		Guidance = {
			-- Changed from LaunchAssist -> Predictive.
			-- Every member of the x3 volley now continues correcting after launch.
			Mode = "Predictive",

			AcquireRange = 260,
			AcquireConeDegrees = 82,
			AcquireWindow = 1.00,

			TrackMaxFromOriginalDegrees = 88,
			CommitDistance = 2.25,

			-- Converging Pressure:
			-- faster than Kunai, and the sequential members are meant to keep
			-- pressure on the same moving lane.
			TurnRateFarDegreesPerSecond = 105,
			TurnRateMidDegreesPerSecond = 170,
			TurnRateNearDegreesPerSecond = 265,
			MidDistance = 46,

			RampTime = 0.18,

			TargetVelocityFactor = 1.08,
			MaxInterceptTime = 1.00,
			MaxLeadDistance = 32,

			VerticalVelocityFactor = 0.62,
			VerticalAimWeight = 0.66,

			EvasiveLateralSpeed = 30,
			EvasiveTurnMultiplier = 1.30,

			-- ---------- v2.0 ----------
			-- Good assistance, light tracking, burst identity.
			AimAssistConeDegrees = 15,
			AimAssistRange = 260,
			AimAssistMaxCorrectionDegrees = 15,
			AimAssistDirectRayPriority = true,

			PredictionStrength = 1.00,
			MaxPredictionTime = 0.70,
			MaxPredictionSpeed = 70,
			PredictionSmoothing = 0.40,

			CanTrack = true,
			GuidanceHz = 15,
			GuidanceDuration = 1.35,
			CommitTime = 0.20,

			SteeringStrength = 0.90,
			MaxTurnRateDegreesPerSecond = 95,
			AngularDeadzoneDegrees = 0.7,
			MaxTrackingAngleDegrees = 26,

			BreakTrackingOnSubstitution = true,
			BreakTrackingOnDash = false,

			HitboxScale = 1.25,
			NearMissRadius = 3.00,
		},

		Clash = {
			Power = 50,
			Weight = 0.80,
			Radius = 0.75,

			CanClash = true,
			CanBreak = true,

			MutualDeflectAngleDegrees = 38,
			WinnerDeflectAngleDegrees = 6,
			BreakPowerRatio = 1.30,

			Stability = 1,
			StabilityDamage = 1,
		},

		Armor = {
			Penetration = 0.05,
			DurabilityDamage = 0.45,
		},

		Visual = {
			Mode = "FlatAutoSpin",

			ScaleMode = "TargetDiameter",
			TargetDiameter = 1.25,

			AutoDetectSpinAxis = true,
			FallbackSpinAxis = "Y",

			SpinSpeedRadiansPerSecond = math.rad(1260),

			PitchOffset = 0,
			YawOffset = 0,
			RollOffset = 0,

			Trail = {
				Enabled = true,
				Kind = "Micro",
				Lifetime = 0.17,
				MinLength = 0.07,
				Width = 0.09,
				LightEmission = 0.55,
				LightInfluence = 0.0,
				FaceCamera = true,
			},
		},

		Audio = {
			Launch = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 0.92,
				PlaybackSpeed = 1.08,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Lifetime = 4.0,
			},

			Travel = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 0.38,
				PlaybackSpeed = 1.08,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Looped = true,
				RollOffMinDistance = 7,
				RollOffMaxDistance = 85,
				EmitterSize = 3,
			},

			Hit = {
				SoundId = "rbxassetid://2782131222",
				Volume = 0.82,
				PlaybackSpeed = 1.08,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 5,
				RollOffMaxDistance = 100,
			},

			Stick = {
				SoundId = "rbxassetid://9116197517",
				Volume = 0.80,
				PlaybackSpeed = 1.08,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 5,
				RollOffMaxDistance = 100,
			},
		},
	},

	-- ============================================================
	-- SENBON
	-- ============================================================

	Senbon = {
		Id = "Senbon",

		NinjaBag = {
			DisplayName = "SENBON",
			Subtitle = "TRIPLE ×3",

			QAStartingAmount = 20,
			QAMaxAmount = 20,
		},

		AssetName = "senbon",
		FolderName = "Senbons",
		ModelPrefix = "Senbon_",

		Speed = 190,

		-- Three parallel needles:
		-- 3 + 3 + 3 = 9 maximum raw damage.
		Damage = 3,

		Range = 320,
		Lifetime = 3.0,
		Cooldown = 3.0,

		EmbedDepth = 0.12,
		StuckTime = 35.0,

		Pattern = {
			Mode = "Parallel",
			Count = 3,
			Interval = 0.0,

			-- Slightly wider than v1.6 so the three fast lanes are visible
			-- before they converge through guidance.
			Spacing = 0.62,
		},

		Guidance = {
			-- Changed from LaunchAssist -> Predictive.
			Mode = "Predictive",

			AcquireRange = 250,
			AcquireConeDegrees = 74,
			AcquireWindow = 0.90,

			-- More direct than Kunai/Shuriken: Senbon should read like precision
			-- needles, not broad missile arcs.
			TrackMaxFromOriginalDegrees = 78,
			CommitDistance = 1.75,

			TurnRateFarDegreesPerSecond = 90,
			TurnRateMidDegreesPerSecond = 150,
			TurnRateNearDegreesPerSecond = 225,
			MidDistance = 50,

			RampTime = 0.10,

			TargetVelocityFactor = 1.05,
			MaxInterceptTime = 0.90,
			MaxLeadDistance = 28,

			VerticalVelocityFactor = 0.58,
			VerticalAimWeight = 0.70,

			EvasiveLateralSpeed = 32,
			EvasiveTurnMultiplier = 1.20,

			-- ---------- v2.0 ----------
			-- Very fast, strong initial assistance, almost no homing.
			AimAssistConeDegrees = 14,
			AimAssistRange = 250,
			AimAssistMaxCorrectionDegrees = 14,
			AimAssistDirectRayPriority = true,

			PredictionStrength = 1.00,
			MaxPredictionTime = 0.65,
			MaxPredictionSpeed = 70,
			PredictionSmoothing = 0.45,

			CanTrack = true,
			GuidanceHz = 15,
			GuidanceDuration = 0.90,
			CommitTime = 0.22,

			SteeringStrength = 0.55,
			MaxTurnRateDegreesPerSecond = 55,
			AngularDeadzoneDegrees = 0.9,
			MaxTrackingAngleDegrees = 14,

			BreakTrackingOnSubstitution = true,
			BreakTrackingOnDash = false,

			HitboxScale = 1.25,
			NearMissRadius = 2.60,
		},

		Clash = {
			Power = 45,
			Weight = 0.45,
			Radius = 0.55,

			CanClash = true,
			CanBreak = false,

			MutualDeflectAngleDegrees = 42,
			WinnerDeflectAngleDegrees = 12,
			BreakPowerRatio = 1.30,

			Stability = 1,
			StabilityDamage = 1,
		},

		Armor = {
			Penetration = 0.25,
			DurabilityDamage = 0.15,
		},

		Visual = {
			Mode = "LongAxis",

			ScaleMode = "Preserve",

			AutoDetectLongAxis = true,
			FallbackLongAxis = "Z",

			PitchOffset = 0,
			YawOffset = 0,
			RollOffset = 0,

			Trail = {
				Enabled = true,
				Kind = "Micro",
				Lifetime = 0.16,
				MinLength = 0.05,
				Width = 0.075,
				LightEmission = 0.65,
				LightInfluence = 0.0,
				FaceCamera = true,
			},
		},

		Audio = {
			Launch = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 0.82,
				PlaybackSpeed = 1.15,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Lifetime = 4.0,
			},

			Travel = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 0.30,
				PlaybackSpeed = 1.15,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Looped = true,
				RollOffMinDistance = 5,
				RollOffMaxDistance = 75,
				EmitterSize = 2,
			},

			Hit = {
				SoundId = "rbxassetid://2782131222",
				Volume = 0.72,
				PlaybackSpeed = 1.15,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 4,
				RollOffMaxDistance = 90,
			},

			Stick = {
				SoundId = "rbxassetid://9116197517",
				Volume = 0.65,
				PlaybackSpeed = 1.15,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 4,
				RollOffMaxDistance = 90,
			},
		},
	},

	-- ============================================================
	-- FUMA SHURIKEN
	-- ============================================================

	Fuma = {
		Id = "Fuma",

		NinjaBag = {
			DisplayName = "FUMA",
			Subtitle = "PESADO ×1",

			QAStartingAmount = 20,
			QAMaxAmount = 20,
		},

		AssetName = "Fuma Shuriken",
		FolderName = "FumaShurikens",
		ModelPrefix = "FumaShuriken_",

		Speed = 108,
		Damage = 20,

		Range = 235,
		Lifetime = 4.25,
		Cooldown = 7.0,

		EmbedDepth = 0.32,
		StuckTime = 35.0,

		Pattern = {
			Mode = "Single",
			Count = 1,
			Interval = 0.0,
			Spacing = 0.0,
		},

		Guidance = {
			Mode = "Predictive",

			AcquireRange = 250,
			AcquireConeDegrees = 80,
			AcquireWindow = 1.00,

			-- Heavy Pursuit still refuses a true U-turn.
			TrackMaxFromOriginalDegrees = 86,

			-- The previous 16-stud ballistic terminal phase made simple lateral
			-- movement disproportionately effective. Keep guidance much longer.
			CommitDistance = 4.50,

			-- Lower than small projectiles so the Fuma visibly carries mass,
			-- but strong enough that running sideways is not a free answer.
			TurnRateFarDegreesPerSecond = 75,
			TurnRateMidDegreesPerSecond = 125,
			TurnRateNearDegreesPerSecond = 195,
			MidDistance = 55,

			-- Longer ramp creates the most visible curved launch of the set.
			RampTime = 0.28,

			TargetVelocityFactor = 1.00,
			MaxInterceptTime = 1.30,
			MaxLeadDistance = 34,

			VerticalVelocityFactor = 0.52,
			VerticalAimWeight = 0.55,

			EvasiveLateralSpeed = 28,
			EvasiveTurnMultiplier = 1.25,

			-- ---------- v2.0 ----------
			-- Heavy threat: stronger guidance, clearly limited turn rate,
			-- longest commit window so Clash stays the intended answer.
			AimAssistConeDegrees = 16,
			AimAssistRange = 250,
			AimAssistMaxCorrectionDegrees = 16,
			AimAssistDirectRayPriority = true,

			PredictionStrength = 1.00,
			MaxPredictionTime = 1.00,
			MaxPredictionSpeed = 70,
			PredictionSmoothing = 0.35,

			CanTrack = true,
			GuidanceHz = 15,
			GuidanceDuration = 2.20,

			-- Speed 108 -> commit at ~29 studs.
			CommitTime = 0.27,

			SteeringStrength = 1.00,
			MaxTurnRateDegreesPerSecond = 78,
			AngularDeadzoneDegrees = 0.5,
			MaxTrackingAngleDegrees = 34,

			BreakTrackingOnSubstitution = true,
			BreakTrackingOnDash = false,

			HitboxScale = 1.25,
			NearMissRadius = 4.00,
		},

		Clash = {
			Power = 82,
			Weight = 1.70,

			Radius = 2.65,

			CanClash = true,
			CanBreak = true,

			MutualDeflectAngleDegrees = 22,

			WinnerDeflectAngleDegrees = 0.75,

			BreakPowerRatio = 1.30,

			Stability = 4,
			StabilityDamage = 2,
		},

		Armor = {
			Penetration = 0.18,
			DurabilityDamage = 1.55,
		},

		Visual = {
			Mode = "FlatAutoSpin",

			ScaleMode = "Preserve",

			AutoDetectSpinAxis = true,
			FallbackSpinAxis = "Y",

			SpinSpeedRadiansPerSecond = math.rad(720),

			PitchOffset = 0,
			YawOffset = 0,
			RollOffset = 0,

			Trail = {
				Enabled = true,
				Kind = "Micro",
				Lifetime = 0.20,
				MinLength = 0.10,
				Width = 0.22,
				LightEmission = 0.45,
				LightInfluence = 0.0,
				FaceCamera = true,
			},
		},

		Audio = {
			Launch = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 1.10,
				PlaybackSpeed = 0.82,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Lifetime = 4.5,
			},

			Travel = {
				SoundId = "rbxassetid://138958784062039",
				Volume = 0.58,
				PlaybackSpeed = 0.82,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				Looped = true,
				RollOffMinDistance = 8,
				RollOffMaxDistance = 105,
				EmitterSize = 5,
			},

			Hit = {
				SoundId = "rbxassetid://2782131222",
				Volume = 1.05,
				PlaybackSpeed = 0.82,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 7,
				RollOffMaxDistance = 115,
			},

			Stick = {
				SoundId = "rbxassetid://9116197517",
				Volume = 1.00,
				PlaybackSpeed = 0.82,
				StartTimePosition = 0.00,
				StartDelay = 0.00,
				RollOffMinDistance = 7,
				RollOffMaxDistance = 115,
			},
		},
	},
}

return ProjectileConfigs
