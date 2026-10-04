--[[
	TreeJump.Effects · ModuleScript en ReplicatedStorage.TreeJump
	Efectos locales (solo cliente): hojas, destello de chakra, rama que se dobla,
	cámara (FOV, profundidad de campo, cabeceo al aterrizar) y sonidos.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))
local Zones = require(script.Parent:WaitForChild("Zones"))

local Effects = {}

local rng = Random.new()

local function getFolder()
	local folder = Workspace:FindFirstChild("TreeJumpVFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TreeJumpVFX"
		folder.Parent = Workspace
	end
	return folder
end

local function effectPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for key, value in props do
		part[key] = value
	end
	part.Parent = getFolder()
	return part
end

-- Hojas que salen volando y caen revoloteando
function Effects.leafBurst(position, surface, count)
	count = count or Config.LeafCount
	if count <= 0 then
		return
	end
	local colors = Config.LeafColors[surface] or Config.LeafColors.Wood
	local leaves = {}
	for _ = 1, count do
		local size = Vector3.new(0.45, 0.05, 0.25) * rng:NextNumber(0.8, 1.3)
		local part = effectPart({
			Material = Enum.Material.SmoothPlastic,
			Color = colors[rng:NextInteger(1, #colors)],
			Size = size,
			CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0),
		})
		table.insert(leaves, {
			Part = part,
			Size = size,
			Velocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(3, 8), rng:NextNumber(-6, 6)),
			Spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)),
			Phase = rng:NextNumber(0, 6.28),
			Life = rng:NextNumber(0.6, 1),
		})
	end

	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() - start
		local alive = false
		for _, leaf in leaves do
			if t < leaf.Life then
				alive = true
				leaf.Velocity = leaf.Velocity * (1 - math.min(dt * 2.5, 1)) + Vector3.new(0, -6 * dt, 0)
				local sway = Vector3.new(math.sin(t * 9 + leaf.Phase), 0, math.cos(t * 7 + leaf.Phase)) * 1.5 * dt
				local spin = leaf.Spin * dt
				leaf.Part.CFrame = (leaf.Part.CFrame + leaf.Velocity * dt + sway) * CFrame.Angles(spin.X, spin.Y, spin.Z)
				leaf.Part.Size = leaf.Size * math.max(math.clamp((leaf.Life - t) / 0.25, 0, 1), 0.05)
			elseif leaf.Part.Parent then
				leaf.Part:Destroy()
			end
		end
		if not alive then
			connection:Disconnect()
		end
	end)
end

-- Anillo de chakra bajo los pies
function Effects.chakraFlash(position)
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = Config.ChakraColor,
		Transparency = 0.2,
		Size = Vector3.new(0.1, 1.5, 1.5),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
	})
	local tween = TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 5, 5),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		ring:Destroy()
	end)
end

-- La rama se dobla un poco hacia abajo y rebota (solo en este cliente)
local bending = {}

function Effects.bendBranch(zone, point)
	if Config.BranchBend <= 0 or not zone or not zone.Parent then
		return
	end
	local branch = Zones.sourceBranch(zone)
	if not branch or not branch.Anchored or not branch:IsDescendantOf(Workspace) then
		return
	end

	local state = bending[branch]
	if state then
		state.Token += 1
	else
		state = { Original = branch.CFrame, Token = 1 }
		bending[branch] = state
	end
	local token = state.Token
	local original = state.Original

	-- La base es el extremo de la zona más cercano al centro del árbol
	local a, b = Zones.segment(zone)
	local tree = zone:FindFirstAncestorOfClass("Model")
	local pivot = if tree then tree:GetPivot().Position else a
	local function flatDistance(p)
		return Vector3.new(p.X - pivot.X, 0, p.Z - pivot.Z).Magnitude
	end
	local base, tip = a, b
	if flatDistance(b) < flatDistance(a) then
		base, tip = b, a
	end
	local along = tip - base
	local length = along.Magnitude
	if length < 0.1 then
		return
	end
	local direction = along.Unit
	local axis = Vector3.yAxis:Cross(direction)
	if axis.Magnitude < 1e-3 then
		return
	end
	axis = axis.Unit

	local reach = math.clamp((point - base):Dot(direction) / length, 0.3, 1)
	local amplitude = math.rad(Config.BranchBend) * reach
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if state.Token ~= token or not branch.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - start
		if t >= 0.8 then
			branch.CFrame = original
			bending[branch] = nil
			connection:Disconnect()
			return
		end
		local angle = amplitude * math.exp(-6 * t) * math.sin(t * 22)
		branch.CFrame = CFrame.new(base) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-base) * original
	end)
end

-- Cámara ----------------------------------------------------------------------

local bumpCount = 0

function Effects.cameraBump(strength)
	local camera = Workspace.CurrentCamera
	if not camera or strength <= 0 then
		return
	end
	bumpCount += 1
	local name = "TreeJumpBump" .. bumpCount
	local start = os.clock()
	local duration = 0.25
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local alpha = (os.clock() - start) / duration
		if alpha >= 1 then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local angle = strength * math.sin(alpha * math.pi) * (1 - alpha)
		camera.CFrame *= CFrame.Angles(-math.rad(angle), 0, 0)
	end)
end

local speedActive = false
local previousFov = nil
local fovTween, dofTween, dof = nil, nil, nil

local function tween(instance, time, goal)
	local created = TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	created:Play()
	return created
end

-- FOV y desenfoque mientras se vuela; guarda y restaura el FOV previo
function Effects.startSpeed()
	if speedActive then
		return
	end
	speedActive = true

	local camera = Workspace.CurrentCamera
	if camera and Config.FovBonus > 0 then
		previousFov = camera.FieldOfView
		if fovTween then
			fovTween:Cancel()
		end
		fovTween = tween(camera, Config.FovTime, { FieldOfView = previousFov + Config.FovBonus })
	end

	if Config.DepthOfField then
		if not dof or not dof.Parent then
			dof = Instance.new("DepthOfFieldEffect")
			dof.Name = "TreeJumpDepthOfField"
			dof.FocusDistance = Config.DofFocusDistance
			dof.InFocusRadius = Config.DofInFocusRadius
			dof.NearIntensity = 0
			dof.FarIntensity = 0
			dof.Parent = Lighting
		end
		if dofTween then
			dofTween:Cancel()
		end
		dofTween = tween(dof, 0.1, { NearIntensity = Config.DofIntensity, FarIntensity = Config.DofIntensity })
	end
end

function Effects.stopSpeed()
	if not speedActive then
		return
	end
	speedActive = false

	local camera = Workspace.CurrentCamera
	if camera and previousFov then
		if fovTween then
			fovTween:Cancel()
		end
		fovTween = tween(camera, Config.FovTime, { FieldOfView = previousFov })
	end
	previousFov = nil

	if dof and dof.Parent then
		if dofTween then
			dofTween:Cancel()
		end
		dofTween = tween(dof, 0.25, { NearIntensity = 0, FarIntensity = 0 })
	end
end

function Effects.playSound(soundId)
	if not Config.SoundsEnabled or not soundId then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = Config.SoundVolume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

return Effects
