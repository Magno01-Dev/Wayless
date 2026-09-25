--!strict
-- StarterPlayer > StarterCharacterScripts > UpliftAnimationReproTest
--
-- Reproduce-only diagnostic for the old Uplift animation.
-- IMPORTANT:
-- - Does NOT change Humanoid states.
-- - Does NOT change WalkSpeed / JumpPower.
-- - Does NOT anchor HumanoidRootPart.
-- - Does NOT write AssemblyLinearVelocity.
-- - Does NOT clamp RootJoint rotation.
-- - Does NOT use PlatformStand.
-- - It only loads and plays the animation exactly as authored.
--
-- Press P to play:
--   rbxassetid://120638779148705
--
-- Press O to stop the test animation manually.

local Players =
	game:GetService("Players")

local UserInputService =
	game:GetService("UserInputService")

local player =
	Players.LocalPlayer

local character =
	script.Parent

local humanoid =
	character:
	WaitForChild(
		"Humanoid"
	) :: Humanoid

local animator =
	humanoid:
	FindFirstChildOfClass(
		"Animator"
	)

if not animator then
	animator =
		Instance.new("Animator")

	animator.Parent =
		humanoid
end

local ANIMATION_ID =
	"rbxassetid://120638779148705"

local animation =
	Instance.new("Animation")

animation.Name =
	"UpliftAnimationRepro"

animation.AnimationId =
	ANIMATION_ID

local track =
	animator:
	LoadAnimation(
		animation
	)

track.Priority =
	Enum.AnimationPriority.Action4

track.Looped =
	false

local playing =
	false

local function stateName(): string
	return humanoid:
		GetState().Name
end

local function printSnapshot(
	label: string
)
	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	local velocity =
		if root
		and root:IsA("BasePart")
		then root.AssemblyLinearVelocity
		else Vector3.zero

	print(
		"[UpliftRepro]",
		label,
		"| State=",
		stateName(),
		"| Floor=",
		humanoid.FloorMaterial.Name,
		"| PlatformStand=",
		humanoid.PlatformStand,
		"| AutoRotate=",
		humanoid.AutoRotate,
		"| Vel=",
		string.format(
			"%.2f, %.2f, %.2f",
			velocity.X,
			velocity.Y,
			velocity.Z
		)
	)
end

local function stopTrack()
	if track.IsPlaying then
		track:
			Stop(
				0.05
			)
	end

	playing =
		false

	printSnapshot(
		"MANUAL STOP"
	)
end

local function playTrack()
	if track.IsPlaying then
		track:
			Stop(
				0
			)
	end

	printSnapshot(
		"BEFORE PLAY"
	)

	playing =
		true

	track:
		Play(
			0.05,
			1,
			1
		)

	print(
		"[UpliftRepro] PLAY",
		ANIMATION_ID,
		"| Length=",
		track.Length
	)
end

track.Stopped:
	Connect(
		function()
			if not playing then
				return
			end

			playing =
			false

			printSnapshot(
				"TRACK STOPPED"
			)
		end
	)

humanoid.StateChanged:
	Connect(
		function(
			oldState,
			newState
		)
			if not playing then
				return
			end

			print(
				"[UpliftRepro] STATE",
				oldState.Name,
				"->",
				newState.Name
			)
		end
	)

UserInputService.InputBegan:
	Connect(
		function(
			input: InputObject,
			gameProcessed: boolean
		)
			if gameProcessed then
				return
			end

			if input.KeyCode ==
				Enum.KeyCode.P then

				playTrack()

			elseif input.KeyCode ==
				Enum.KeyCode.O then

				stopTrack()
			end
		end
	)

script.Destroying:
	Connect(
		function()
			if track.IsPlaying then
				track:
				Stop(
					0
				)
			end

			animation:
			Destroy()
		end
	)

print(
	"[UpliftRepro] READY",
	"| P=Play",
	"| O=Stop",
	"| Animation=",
	ANIMATION_ID,
	"| PhysicsWrites=NONE",
	"| StateWrites=NONE"
)
