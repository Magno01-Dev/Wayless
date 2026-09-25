--!strict
-- StarterCharacterScripts > HumanoidStateRootCauseProbe
-- DIAGNOSTIC ONLY. This script NEVER changes character state.

local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart

local suspiciousUntil = 0.0
local lastSample = 0.0

local function enabled(state: Enum.HumanoidStateType): boolean
	local ok, result = pcall(function()
		return humanoid:GetStateEnabled(state)
	end)
	return ok and result == true
end

local function tiltDegrees(): number
	local dot = math.clamp(root.CFrame.UpVector:Dot(Vector3.yAxis), -1, 1)
	return math.deg(math.acos(dot))
end

local function snapshot(tag: string)
	local v = root.AssemblyLinearVelocity
	local av = root.AssemblyAngularVelocity

	print(
		"[HumanoidProbe]",
		tag,
		"| t=", string.format("%.3f", workspace:GetServerTimeNow()),
		"| State=", humanoid:GetState().Name,
		"| Floor=", humanoid.FloorMaterial.Name,
		"| Tilt=", string.format("%.1f", tiltDegrees()),
		"| Vel=", string.format("%.1f,%.1f,%.1f", v.X, v.Y, v.Z),
		"| AngVel=", string.format("%.1f,%.1f,%.1f", av.X, av.Y, av.Z),
		"| PlatformStand=", humanoid.PlatformStand,
		"| Sit=", humanoid.Sit,
		"| AutoRotate=", humanoid.AutoRotate,
		"| Anchored=", root.Anchored,
		"| FD=", enabled(Enum.HumanoidStateType.FallingDown),
		"| RD=", enabled(Enum.HumanoidStateType.Ragdoll),
		"| GU=", enabled(Enum.HumanoidStateType.GettingUp),
		"| Combat=", character:GetAttribute("CombatMode"),
		"| Attack=", character:GetAttribute("IsAttacking"),
		"| Lunge=", character:GetAttribute("ServerLungeActive"),
		"| AirCombo=", character:GetAttribute("AirComboServerActive"),
		"| Surface=", character:GetAttribute("SurfaceWalking"),
		"| TreeJump=", character:GetAttribute("TreeJumpActive")
	)
end

snapshot("START")

humanoid.StateChanged:Connect(function(oldState, newState)
	snapshot("STATE " .. oldState.Name .. " -> " .. newState.Name)

	if newState == Enum.HumanoidStateType.FallingDown
		or newState == Enum.HumanoidStateType.Ragdoll
		or newState == Enum.HumanoidStateType.GettingUp
		or newState == Enum.HumanoidStateType.Physics then

		suspiciousUntil = os.clock() + 4.0
	end
end)

for _, propertyName in ipairs({
	"PlatformStand",
	"Sit",
	"AutoRotate",
	}) do
	humanoid:GetPropertyChangedSignal(propertyName):Connect(function()
		snapshot("PROP Humanoid." .. propertyName)
	end)
end

root:GetPropertyChangedSignal("Anchored"):Connect(function()
	snapshot("PROP HRP.Anchored")
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()

	if tiltDegrees() >= 35 then
		suspiciousUntil = math.max(suspiciousUntil, now + 1.0)
	end

	if now <= suspiciousUntil
		and now - lastSample >= 0.10 then

		lastSample = now
		snapshot("TRACE")
	end
end)

print("[HumanoidProbe] READY | read-only | no state writes")
