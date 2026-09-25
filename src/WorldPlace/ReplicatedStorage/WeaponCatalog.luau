--!strict
-- WeaponCatalog v5 - Stable Root Holster + Medium Katana Baseline
-- ReplicatedStorage > WeaponCatalog [ModuleScript]
--
-- This catalog owns weapon-specific visual metadata and combat tuning.
-- InventoryCatalog only owns inventory/equipment metadata.
--
-- First baseline:
-- KatanaQA = Medium weapon / balance reference 1.00x.

local WeaponCatalog = {}

local WEAPONS = {

	KatanaQA = {
		Id = "KatanaQA",
		DisplayName = "Katana",
		Class = "Medium",

		Visual = {
			AssetName = "Katana",

			BladeContainerName = "Blade",
			SheathContainerName = "Sheath",

			GripAttachmentName = "GripAttachment",
			OffhandGripAttachmentName = "OffhandGripAttachment",
			HolsterAttachmentName = "HolsterAttachment",

			-- Used to keep the SAME blade visibly inserted in the sheath.
			-- If present, the blade will remain visibly inserted while holstered.
			-- If absent, v1 hides the Blade assembly while holstered.
			SheathedGripAttachmentName = "SheathedGripAttachment",

			CharacterHandAttachmentName = "RightWeaponAttachment",
			CharacterHolsterAttachmentName = "WeaponHolsterAttachment",

			R6HandPart = "Right Arm",
			R15HandPart = "RightHand",

			-- Stable carrier: HumanoidRootPart does not inherit the large
			-- authored torso lean used by sprint/run animations.
			R6HolsterPart = "HumanoidRootPart",
			R15HolsterPart = "HumanoidRootPart",

			-- First-pass mount positions. These are intentionally centralized
			-- so we can calibrate the katana without touching service code.
			-- The GripAttachment is now the authored source of truth.
			-- Only rotate the hand mount so Cube.003's long local X axis
			-- follows the arm/handle direction. The previous extra Y rotation
			-- twisted the blade in the hand.
			R6HandAttachmentCFrame =
				CFrame.new(
					0,
					-0.95,
					0
				)
				* CFrame.Angles(
					0,
					0,
					math.rad(-90)
				)
				-- Keep the sword axis, but roll the blade face 90 degrees
				-- so the katana is not presented edge-on in the hand.
				* CFrame.Angles(
					math.rad(90),
					0,
					0
				),

			R15HandAttachmentCFrame =
				CFrame.new(
					0,
					-0.15,
					0
				)
				* CFrame.Angles(
					0,
					0,
					math.rad(-90)
				),

			-- Katana is worn low on the LEFT HIP instead of diagonally
			-- across the character's back. Cube.005's long local X axis
			-- is turned into the character's front/back axis.
			R6HolsterAttachmentCFrame =
				CFrame.new(
					-1.18,
					-1.02,
					0.34
				)
				* CFrame.Angles(
					0,
					math.rad(90),
					math.rad(-4)
				),

			R15HolsterAttachmentCFrame =
				CFrame.new(
					-0.98,
					-0.78,
					0.36
				)
				* CFrame.Angles(
					0,
					math.rad(90),
					math.rad(-4)
				),
		},

		Pose = {
			GripStyle = "TwoHanded",

			-- Temporary QA stance. This is NOT the final animation set.
			-- WeaponPoseController applies it only while WeaponState=Drawn.
			R6RightShoulderTransform =
				CFrame.Angles(
					math.rad(62),
					math.rad(-8),
					math.rad(-28)
				),

			R6PoseBlendSpeed = 22,

			-- Left arm procedurally aims at OffhandGripAttachment.
			R6OffhandTracking = true,

			-- Temporary procedural M1 arc. Final authored animations can
			-- replace this later without changing combat timings.
			QASwingYawDegrees = 42,
			QASwingReturnBias = 0.18,
		},

		Combat = {
			-- Medium = canonical 1.00 balance reference.
			Damage = 8,
			ComboCount = 4,

			SwingInterval = 0.40,
			SwingSpeedScale = 1.00,
			RangeScale = 1.00,

			Startup = 0.12,
			ActiveTime = 0.12,
			Recovery = 0.16,

			Hitstun = 0.24,
			GuardDamage = 8,

			MovementMultiplier = 0.86,

			-- Server-authoritative Medium weapon hitbox.
			HitboxSize = Vector3.new(
				4.6,
				4.8,
				6.0
			),

			HitboxForwardOffset = 3.15,
			MaxTargetsPerSwing = 3,
			ComboResetTime = 0.85,
		},
	},
}

local function copyTable(source: any): any
	local result = {}

	for key, value in pairs(source) do
		if typeof(value) == "table" then
			result[key] = copyTable(value)
		else
			result[key] = value
		end
	end

	return result
end

function WeaponCatalog.Get(
	weaponId: string
): any?

	local definition =
		WEAPONS[
	weaponId
	]

	if not definition then
		return nil
	end

	return copyTable(
		definition
	)
end

function WeaponCatalog.GetAll(): {any}
	local result = {}

	for _,
		definition in pairs(
			WEAPONS
		) do

		table.insert(
			result,
			copyTable(
				definition
			)
		)
	end

	table.sort(
		result,
		function(a: any, b: any)
			return tostring(a.Id)
				< tostring(b.Id)
		end
	)

	return result
end

print(
	"[WeaponCatalog] READY v5"
		.. " | KatanaQA=Medium"
)

return WeaponCatalog
