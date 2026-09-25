--!strict
-- CombatController v6.7 - Inventory Mouse Handoff + External Enter Request
--
-- StarterPlayer > StarterCharacterScripts > CombatController
--
-- v6.6 preserves v6.5 behavior and adds ONE local integration contract:
--
-- Character > CombatModeRequest [BindableEvent]
--
-- Supported:
-- CombatModeRequest:Fire("Enter", source)
--
-- This lets trusted local controllers (currently ThrowableController after a
-- server-confirmed defensive projectile counter) ask CombatController to enter
-- combat WITHOUT duplicating CombatController's internal state or mouse/facing
-- logic.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")


-- =========================
-- COMBAT SETTINGS
-- =========================

local COMBAT_KEY = Enum.KeyCode.R
local COMBAT_RENDER_BIND_NAME = "CombatFacing"

local COMBAT_FACING_RESPONSIVENESS = 100

local COMBAT_FACING_TARGET_SMOOTH_SPEED = 20


-- =========================
-- VARIABLES
-- =========================

local combatMode = false
local combatSuppressed = false

local smoothedCombatFacingYaw = nil


-- =========================
-- CHARACTER ATTRIBUTES
-- =========================

character:SetAttribute(
	"CombatMode",
	false
)

character:SetAttribute(
	"CombatSuppressed",
	false
)


-- =========================
-- EXTERNAL COMBAT MODE REQUEST
-- =========================
--
-- BindableEvent = LOCAL client-to-client-controller contract.
-- It does not expose a server RemoteEvent and does not let the server directly
-- mutate CombatController's private `combatMode` variable.

local existingCombatModeRequest =
	character:
	FindFirstChild(
		"CombatModeRequest"
	)

local combatModeRequest: BindableEvent

if existingCombatModeRequest
	and existingCombatModeRequest:IsA(
		"BindableEvent"
	) then

	combatModeRequest =
		existingCombatModeRequest

else

	if existingCombatModeRequest then

		existingCombatModeRequest:
			Destroy()
	end


	combatModeRequest =
		Instance.new(
			"BindableEvent"
		)


	combatModeRequest.Name =
		"CombatModeRequest"


	combatModeRequest.Parent =
		character
end


-- =========================
-- COMBAT FACING
-- =========================

local combatFacingAttachment =
	Instance.new("Attachment")

combatFacingAttachment.Name =
	"CombatFacingAttachment"

combatFacingAttachment.Parent =
	rootPart


local combatFacingAlign =
	Instance.new("AlignOrientation")

combatFacingAlign.Name =
	"CombatFacingAlign"

combatFacingAlign.Mode =
	Enum.OrientationAlignmentMode.OneAttachment

combatFacingAlign.Attachment0 =
	combatFacingAttachment

combatFacingAlign.RigidityEnabled =
	false

combatFacingAlign.Responsiveness =
	COMBAT_FACING_RESPONSIVENESS

combatFacingAlign.MaxTorque =
	math.huge

combatFacingAlign.MaxAngularVelocity =
	math.huge

combatFacingAlign.ReactionTorqueEnabled =
	false

combatFacingAlign.Enabled =
	false

combatFacingAlign.Parent =
	rootPart


local function resetCombatFacingSmoothing()

	smoothedCombatFacingYaw =
		nil
end


local function setCombatFacingEnabled(
	enabled
)

	if not enabled then

		resetCombatFacingSmoothing()
	end


	combatFacingAlign.Enabled =
		enabled
end


local function directionToYaw(
	facingDirection
)

	return math.atan2(
		facingDirection.X,
		-facingDirection.Z
	)
end


local function yawToDirection(
	yaw
)

	return Vector3.new(
		math.sin(
			yaw
		),
		0,
		-math.cos(
			yaw
		)
	)
end


local function shortestAngleDelta(
	fromAngle,
	toAngle
)

	return math.atan2(
		math.sin(
			toAngle - fromAngle
		),
		math.cos(
			toAngle - fromAngle
		)
	)
end


local function applyCombatFacingDirection(
	facingDirection
)

	if not facingDirection
		or facingDirection.Magnitude <
		0.01 then

		return
	end


	combatFacingAlign.CFrame =
		CFrame.lookAt(
			Vector3.zero,
			facingDirection.Unit,
			Vector3.yAxis
		)
end


local function setCombatFacingDirectionImmediate(
	facingDirection
)

	if not facingDirection
		or facingDirection.Magnitude <
		0.01 then

		return
	end


	smoothedCombatFacingYaw =
		directionToYaw(
			facingDirection.Unit
		)


	applyCombatFacingDirection(
		facingDirection
	)
end


local function updateSmoothedCombatFacing(
	facingDirection,
	deltaTime
)

	if not facingDirection
		or facingDirection.Magnitude <
		0.01 then

		return
	end


	local targetYaw =
		directionToYaw(
			facingDirection.Unit
		)


	if smoothedCombatFacingYaw ==
		nil then

		smoothedCombatFacingYaw =
			targetYaw

	else

		local delta =
			shortestAngleDelta(
				smoothedCombatFacingYaw,
				targetYaw
			)


		local alpha =
			1 - math.exp(
				-COMBAT_FACING_TARGET_SMOOTH_SPEED
				* math.max(
					deltaTime,
					0
				)
			)


		smoothedCombatFacingYaw +=
			delta * alpha
	end


	applyCombatFacingDirection(
		yawToDirection(
			smoothedCombatFacingYaw
		)
	)
end


-- =========================
-- TREE JUMP
-- =========================

local function isTreeJumpActive()

	return character:GetAttribute(
		"TreeJumpActive"
	) == true
end


-- =========================
-- SWIMMING
-- =========================

local function isActuallySwimming()

	return humanoid:GetState() ==
		Enum.HumanoidStateType.Swimming
end


-- =========================
-- INVENTORY UI HANDOFF
-- =========================

local function isInventoryOpen(): boolean
	return player:GetAttribute("InventoryOpen") == true
		or player:GetAttribute("NinjaBagLoadoutOpen") == true
end


-- =========================
-- MOUSE
-- =========================

local function setCombatMouseLocked(
	locked
)

	-- CombatController is the actual owner of combat mouse lock.
	-- While InventoryOpen is true, it must surrender cursor ownership even if
	-- another combat handoff asks to lock again.
	if locked
		and not isInventoryOpen() then

		UserInputService.MouseBehavior =
			Enum.MouseBehavior.LockCenter


		UserInputService.MouseIconEnabled =
			false

	else

		UserInputService.MouseBehavior =
			Enum.MouseBehavior.Default


		UserInputService.MouseIconEnabled =
			true
	end
end


-- =========================
-- COMBAT SUPPRESSION
-- =========================

local function setCombatSuppressed(
	suppressed
)

	if combatSuppressed ==
		suppressed then

		return
	end


	combatSuppressed =
		suppressed


	character:SetAttribute(
		"CombatSuppressed",
		suppressed
	)


	if suppressed then

		setCombatFacingEnabled(
			false
		)


		if character:GetAttribute(
			"SurfaceWalking"
			) ~= true then

			humanoid.AutoRotate =
				true
		end


		setCombatMouseLocked(
			false
		)

	else

		if not combatMode then

			return
		end


		if character:GetAttribute(
			"SurfaceWalking"
			) ~= true then

			humanoid.AutoRotate =
				false


			setCombatFacingEnabled(
				true
			)

		else

			setCombatFacingEnabled(
				false
			)
		end


		setCombatMouseLocked(
			true
		)
	end
end


-- =========================
-- GET CAMERA DIRECTION
-- =========================

local function getCameraFacingDirection()

	local camera =
		workspace.CurrentCamera


	if not camera then

		return nil
	end


	local cameraDirection =
		camera.CFrame.LookVector


	local flatDirection =
		Vector3.new(
			cameraDirection.X,
			0,
			cameraDirection.Z
		)


	if flatDirection.Magnitude <
		0.01 then

		return nil
	end


	return flatDirection.Unit
end


-- =========================
-- UPDATE CHARACTER FACING
-- =========================

local function updateCombatFacing(
	deltaTime
)

	if not combatMode then

		return
	end


	if isInventoryOpen() then

		setCombatFacingEnabled(
			false
		)


		setCombatMouseLocked(
			false
		)


		return
	end


	if isActuallySwimming() then

		setCombatSuppressed(
			true
		)


		return

	elseif combatSuppressed then

		setCombatSuppressed(
			false
		)
	end


	if character:GetAttribute(
		"IsDashing"
		) == true then

		setCombatFacingEnabled(
			false
		)


		return
	end


	if isTreeJumpActive() then

		setCombatFacingEnabled(
			false
		)


		return
	end


	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		setCombatFacingEnabled(
			false
		)


		humanoid.AutoRotate =
			false


		setCombatMouseLocked(
			true
		)


		return
	end


	humanoid.AutoRotate =
		false


	setCombatFacingEnabled(
		true
	)


	local facingDirection =
		getCameraFacingDirection()


	if facingDirection then

		updateSmoothedCombatFacing(
			facingDirection,
			deltaTime
		)
	end


	setCombatMouseLocked(
		true
	)
end


local function isDownedSystemLocked(): boolean

	return character:GetAttribute(
		"DownedActionLocked"
	) == true
		or character:GetAttribute(
			"IsDowned"
		) == true
		or character:GetAttribute(
			"IsCarried"
		) == true
		or character:GetAttribute(
			"IsExecuting"
		) == true
		or character:GetAttribute(
			"IsCarrying"
		) == true
end


-- =========================
-- INVENTORY / COMBAT PRESENTATION
-- =========================

local function refreshCombatPresentationForInventory()

	if isInventoryOpen() then

		setCombatFacingEnabled(
			false
		)


		setCombatMouseLocked(
			false
		)


		return
	end


	if not combatMode then

		setCombatMouseLocked(
			false
		)


		return
	end


	if combatSuppressed
		or isActuallySwimming() then

		setCombatMouseLocked(
			false
		)


		return
	end


	if character:GetAttribute(
		"SurfaceWalking"
		) ~= true
			and not isTreeJumpActive()
			and character:GetAttribute(
				"IsDashing"
			) ~= true then

		humanoid.AutoRotate =
			false


		local facingDirection =
			getCameraFacingDirection()


		if facingDirection then

			setCombatFacingDirectionImmediate(
				facingDirection
			)
		end


		setCombatFacingEnabled(
			true
		)

	else

		setCombatFacingEnabled(
			false
		)
	end


	setCombatMouseLocked(
		true
	)
end


-- =========================
-- ENTER COMBAT MODE
-- =========================

local function enterCombatMode()

	if isDownedSystemLocked() then
		return
	end


	if combatMode then

		return
	end


	if character:GetAttribute(
		"IsDashing"
		) == true
			or isTreeJumpActive() then

		return
	end


	combatMode =
		true


	character:SetAttribute(
		"CombatMode",
		true
	)


	if isActuallySwimming() then

		setCombatSuppressed(
			true
		)

	else

		combatSuppressed =
			false


		character:SetAttribute(
			"CombatSuppressed",
			false
		)


		if character:GetAttribute(
			"SurfaceWalking"
			) ~= true then

			humanoid.AutoRotate =
				false


			setCombatFacingEnabled(
				true
			)

		else

			setCombatFacingEnabled(
				false
			)
		end


		setCombatMouseLocked(
			true
		)
	end
end


-- =========================
-- RESTORE NORMAL FACING
-- =========================

local function restoreNormalFacing()

	setCombatFacingEnabled(
		false
	)


	if character:GetAttribute(
		"SurfaceWalking"
		) == true then

		return
	end


	if isTreeJumpActive()
		or character:GetAttribute(
			"IsDashing"
		) == true then

		return
	end


	humanoid.AutoRotate =
		true


	local moveDirection =
		humanoid.MoveDirection


	if moveDirection.Magnitude <
		0.05 then

		local velocity =
			rootPart.AssemblyLinearVelocity


		moveDirection =
			Vector3.new(
				velocity.X,
				0,
				velocity.Z
			)
	end


	if moveDirection.Magnitude >
		0.05 then

		local flatDirection =
			Vector3.new(
				moveDirection.X,
				0,
				moveDirection.Z
			)


		if flatDirection.Magnitude >
			0.05 then

			flatDirection =
				flatDirection.Unit


			rootPart.AssemblyAngularVelocity =
				Vector3.zero


			rootPart.CFrame =
				CFrame.lookAt(
					rootPart.Position,
					rootPart.Position
					+ flatDirection,
					Vector3.yAxis
				)
		end
	end


	task.defer(
		function()

			if not character.Parent then

				return
			end


			if character:GetAttribute(
				"CombatMode"
				) == true then

				return
			end


			if character:GetAttribute(
				"SurfaceWalking"
				) == true
					or isTreeJumpActive()
					or character:GetAttribute(
						"IsDashing"
					) == true then

				return
			end


			humanoid.AutoRotate =
				true
		end
	)
end


-- =========================
-- EXIT COMBAT MODE
-- =========================

local function exitCombatMode()

	if not combatMode then

		return
	end


	if not isDownedSystemLocked()
		and not isActuallySwimming()
		and (
			character:GetAttribute(
				"IsDashing"
			) == true
				or isTreeJumpActive()
		) then

		return
	end


	combatMode =
		false


	combatSuppressed =
		false


	character:SetAttribute(
		"CombatMode",
		false
	)


	character:SetAttribute(
		"CombatSuppressed",
		false
	)


	setCombatFacingEnabled(
		false
	)


	restoreNormalFacing()


	setCombatMouseLocked(
		false
	)
end


-- =========================
-- TOGGLE COMBAT MODE
-- =========================

local function toggleCombatMode()

	if combatMode then

		exitCombatMode()

	else

		enterCombatMode()
	end
end


-- =========================
-- EXTERNAL REQUEST HANDLER
-- =========================

combatModeRequest.Event:
	Connect(
		function(
			action,
			source
		)

			if action == "Enter"
				or action == true then

				local wasActive =
				combatMode


				enterCombatMode()


				if not wasActive
					and combatMode then

					print(
						"[CombatController] AUTO ENTER CombatMode source=",
						source
						or "Unknown"
					)
				end


				return
			end


			if action == "Exit"
				or action == false then

				exitCombatMode()
			end
		end
	)


local function handleDownedIntegrationState()

	if isDownedSystemLocked()
		and combatMode then

		exitCombatMode()
	end
end


for _, attributeName in ipairs(
	{
		"DownedActionLocked",
		"IsDowned",
		"IsCarried",
		"IsExecuting",
		"IsCarrying",
	}
	) do

	character:GetAttributeChangedSignal(
		attributeName
	):
		Connect(
			handleDownedIntegrationState
		)
end


-- =========================
-- INVENTORY MOUSE / FACING HANDOFF
-- =========================

local function handleInventoryOpenChanged()
	refreshCombatPresentationForInventory()
end


player:GetAttributeChangedSignal(
	"InventoryOpen"
):
	Connect(
		handleInventoryOpenChanged
	)


player:GetAttributeChangedSignal(
	"NinjaBagLoadoutOpen"
):
	Connect(
		handleInventoryOpenChanged
	)


-- =========================
-- INPUT
-- =========================

UserInputService.InputBegan:
	Connect(
		function(
			input,
			gameProcessed
		)

			if gameProcessed then

				return
			end


			if input.KeyCode ==
				COMBAT_KEY then

				if isInventoryOpen() then

					return
				end


				toggleCombatMode()
			end
		end
	)


-- =========================
-- TREE JUMP -> COMBAT HANDOFF
-- =========================

character:GetAttributeChangedSignal(
	"TreeJumpActive"
):
	Connect(
		function()

			if character:GetAttribute(
				"TreeJumpActive"
				) == true then

				setCombatFacingEnabled(
					false
				)


				return
			end


			if not combatMode
				or combatSuppressed
				or isActuallySwimming()
				or character:GetAttribute(
					"IsDashing"
				) == true
				or character:GetAttribute(
					"SurfaceWalking"
				) == true then

				return
			end


			humanoid.AutoRotate =
			false


			local facingDirection =
			getCameraFacingDirection()


			if facingDirection then

				setCombatFacingDirectionImmediate(
					facingDirection
				)
			end


			setCombatFacingEnabled(
				true
			)


			setCombatMouseLocked(
				true
			)
		end
	)


-- =========================
-- HUMANOID STATE
-- =========================

humanoid.StateChanged:
	Connect(
		function(
			_,
			newState
		)

			if not combatMode then

				return
			end


			if newState ==
				Enum.HumanoidStateType.Swimming then

				setCombatSuppressed(
					true
				)

			elseif combatSuppressed then

				setCombatSuppressed(
					false
				)
			end
		end
	)


-- =========================
-- COMBAT FACING UPDATE
-- =========================

RunService:
	UnbindFromRenderStep(
		COMBAT_RENDER_BIND_NAME
	)


RunService:
	BindToRenderStep(
		COMBAT_RENDER_BIND_NAME,
		Enum.RenderPriority.Character.Value,
		function(
			deltaTime
		)

			updateCombatFacing(
				deltaTime
			)
		end
	)


-- =========================
-- CLEANUP
-- =========================

script.Destroying:
	Connect(
		function()

			RunService:
			UnbindFromRenderStep(
				COMBAT_RENDER_BIND_NAME
			)


			setCombatFacingEnabled(
				false
			)


			setCombatMouseLocked(
				false
			)


			combatFacingAlign:
			Destroy()


			combatFacingAttachment:
			Destroy()
		end
	)


print(
	"[CombatController] READY v6.7"
		.. " | R toggle"
		.. " | CombatModeRequest=ON"
		.. " | InventoryMouseHandoff=ON"
)
