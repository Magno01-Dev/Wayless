local NPC = script.Parent

local Humanoid = NPC:WaitForChild("Humanoid")
local RootPart = NPC:WaitForChild("HumanoidRootPart")

-- NPC completamente inmóvil
RootPart.Anchored = true

Humanoid.WalkSpeed = 0
Humanoid.JumpPower = 0
Humanoid.JumpHeight = 0
Humanoid.AutoRotate = false

-- Evitar que otras partes interfieran con físicas
for _, object in ipairs(NPC:GetDescendants()) do
	if object:IsA("BasePart") then
		object.AssemblyLinearVelocity = Vector3.zero
		object.AssemblyAngularVelocity = Vector3.zero

		if object ~= RootPart then
			object.CanCollide = false
		end
	end
end

-- IMPORTANTE:
-- NO reproducimos ninguna animación desde el servidor.