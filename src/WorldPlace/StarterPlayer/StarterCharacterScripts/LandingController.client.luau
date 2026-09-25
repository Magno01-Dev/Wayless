local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")


-- =========================
-- LANDING SETTINGS
-- =========================

local REMOVE_LANDING_BOUNCE = true


-- =========================
-- REMOVE BOUNCE
-- =========================

local function removeLandingBounce()
	if not REMOVE_LANDING_BOUNCE then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity

	-- Conservamos X y Z.
	-- Solo eliminamos la velocidad vertical.
	rootPart.AssemblyLinearVelocity = Vector3.new(
		velocity.X,
		0,
		velocity.Z
	)

	-- Comprobamos nuevamente después de la simulación
	-- física para evitar un pequeño rebote residual.
	task.spawn(function()

		RunService.PostSimulation:Wait()

		if humanoid.FloorMaterial ~= Enum.Material.Air then

			local newVelocity = rootPart.AssemblyLinearVelocity

			if newVelocity.Y > 0 then
				rootPart.AssemblyLinearVelocity = Vector3.new(
					newVelocity.X,
					0,
					newVelocity.Z
				)
			end
		end

	end)
end


-- =========================
-- HUMANOID STATES
-- =========================

humanoid.StateChanged:Connect(function(oldState, newState)

	if oldState == Enum.HumanoidStateType.Freefall
		and newState == Enum.HumanoidStateType.Landed then

		removeLandingBounce()
	end

end)
