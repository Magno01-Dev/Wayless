--!nonstrict
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local VFX = {}
local BLUE = Color3.fromRGB(73, 139, 255)
local WHITE = Color3.fromRGB(218, 248, 255)

function VFX.Play(origin: Vector3, endPosition: Vector3)
    local delta = endPosition - origin
    local distance = delta.Magnitude
    if distance < 0.05 then return end
    local random = Random.new()
    local direction = delta.Unit
    local up = math.abs(direction.Y) > 0.97 and Vector3.xAxis or Vector3.yAxis
    local right = direction:Cross(up).Unit
    up = right:Cross(direction).Unit
    local root = Instance.new("Part")
    root.Name = "LightningBolt_VFX"
    root.Size = Vector3.one * 0.1
    root.CFrame = CFrame.new(origin)
    root.Anchored = true
    root.CanCollide = false
    root.CanTouch = false
    root.CanQuery = false
    root.CastShadow = false
    root.Transparency = 1
    local beams = {}
    local function attachment(position)
        local a = Instance.new("Attachment")
        a.Position = position
        a.Parent = root
        return a
    end
    local function strand(a, b, width, color, alpha)
        local beam = Instance.new("Beam")
        beam.Attachment0 = a
        beam.Attachment1 = b
        beam.FaceCamera = true
        beam.Segments = 1
        beam.Width0 = width
        beam.Width1 = width
        beam.Color = ColorSequence.new(color)
        beam.Transparency = NumberSequence.new(alpha)
        beam.LightEmission = 1
        beam.LightInfluence = 0
        beam.Brightness = 2
        beam.Parent = root
        table.insert(beams, beam)
        return beam
    end
    local count = math.clamp(math.ceil(distance / 3), 3, 24)
    local amplitude = math.min(1.05, distance * 0.045)
    local nodes = {}
    for i = 0, count do
        nodes[i + 1] = attachment(delta * (i / count))
    end
    local function jitter()
        for i = 2, #nodes - 1 do
            local t = (i - 1) / count
            local envelope = math.sin(t * math.pi) * amplitude
            nodes[i].Position = delta * t + right * random:NextNumber(-envelope, envelope) + up * random:NextNumber(-envelope, envelope)
        end
    end
    jitter()
    for i = 1, #nodes - 1 do
        strand(nodes[i], nodes[i + 1], 0.52, BLUE, 0.68)
        strand(nodes[i], nodes[i + 1], 0.13, WHITE, 0.02)
    end
    -- Forks share the main bolt attachment, so their roots stay connected.
    for i = 3, #nodes - 2, 4 do
        local a = nodes[i]
        local side = i % 2 == 0 and -1 or 1
        local length = math.min(random:NextNumber(2, 4.5), distance * 0.18)
        local forkDirection = (direction * 0.6 + right * side + up * random:NextNumber(-0.8, 0.8)).Unit
        local b = attachment(a.Position + forkDirection * length * 0.5 + up * 0.5)
        local c = attachment(a.Position + forkDirection * length)
        strand(a, b, 0.09, WHITE, 0.12)
        local tip = strand(b, c, 0.07, BLUE, 0.2)
        tip.Width1 = 0.01
    end
    local function flare(position, size)
        local a = attachment(position)
        local light = Instance.new("PointLight")
        light.Color = BLUE
        light.Brightness = 2.5
        light.Range = 9
        light.Shadows = false
        light.Parent = a
        TweenService:Create(light, TweenInfo.new(0.25), {Brightness = 0}):Play()
        local sparks = Instance.new("ParticleEmitter")
        sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        sparks.Color = ColorSequence.new(WHITE, BLUE)
        sparks.LightEmission = 1
        sparks.LightInfluence = 0
        sparks.Rate = 0
        sparks.Lifetime = NumberRange.new(0.12, 0.28)
        sparks.Speed = NumberRange.new(5, 14)
        sparks.Drag = 4
        sparks.SpreadAngle = Vector2.new(180, 180)
        sparks.Size = NumberSequence.new(size, 0)
        sparks.Transparency = NumberSequence.new(0.1, 1)
        sparks.Parent = a
        -- Brief finite emission survives initial server-to-client replication.
        sparks.Rate = 110
        task.delay(0.12, function()
            if sparks.Parent then sparks.Enabled = false end
        end)
        for i = 1, 5 do
            local theta = i * math.pi * 2 / 5
            local radial = right * math.cos(theta) + up * math.sin(theta)
            local mid = attachment(position + radial * size * 1.7 + direction * random:NextNumber(-0.4, 0.4))
            local tip = attachment(position + radial * size * 2.7)
            strand(a, mid, 0.075, WHITE, 0.05)
            local beam = strand(mid, tip, 0.06, BLUE, 0.15)
            beam.Width1 = 0
        end
    end
    root.Parent = workspace
    -- Both flares mark the discharge endpoints; no extra hit or damage is inferred.
    flare(Vector3.zero, 0.55)
    flare(delta, 0.85)
    Debris:AddItem(root, 0.65)
    task.delay(0.065, function()
        if root.Parent then jitter() end
    end)
    task.delay(0.13, function()
        if not root.Parent then return end
        jitter()
        for _, beam in beams do
            TweenService:Create(beam, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Width0 = 0, Width1 = 0, Brightness = 0}):Play()
        end
    end)
end
return VFX
