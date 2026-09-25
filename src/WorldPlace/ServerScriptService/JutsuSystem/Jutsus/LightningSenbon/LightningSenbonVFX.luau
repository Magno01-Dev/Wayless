--!nonstrict
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local VFX = {}
local BLUE = Color3.fromRGB(62, 143, 255)
local WHITE = Color3.fromRGB(225, 250, 255)
local function frame(position, direction)
    local up = math.abs(direction.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
    return CFrame.lookAt(position, position + direction, up)
end
local function rootPart(name, cf)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = Vector3.one * 0.1
    p.CFrame = cf
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Transparency = 1
    return p
end
local function attachment(root, position)
    local a = Instance.new("Attachment")
    a.Position = position
    a.Parent = root
    return a
end
local function beam(root, a, b, width0, width1, color, alpha)
    local e = Instance.new("Beam")
    e.Attachment0 = a
    e.Attachment1 = b
    e.Width0 = width0
    e.Width1 = width1
    e.FaceCamera = true
    e.Segments = 1
    e.Color = ColorSequence.new(color)
    e.Transparency = NumberSequence.new(alpha)
    e.LightEmission = 1
    e.LightInfluence = 0
    e.Brightness = 2
    e.Parent = root
    return e
end
function VFX.Create(position: Vector3, direction: Vector3): BasePart
    local p = rootPart("LightningSenbon_Visual", frame(position, direction))
    -- The sharp tip is exactly at the authoritative projectile position.
    local tip = attachment(p, Vector3.zero)
    local shoulder = attachment(p, Vector3.new(0, 0, 0.6))
    local tail = attachment(p, Vector3.new(0, 0, 2.7))
    beam(p, tail, tip, 0.36, 0, BLUE, 0.68)
    beam(p, tail, shoulder, 0.035, 0.13, WHITE, 0.02)
    beam(p, shoulder, tip, 0.13, 0, WHITE, 0)
    local random = Random.new()
    for side = -1, 1, 2 do
        local last = tail
        for i = 1, 4 do
            local a = i == 4 and tip or attachment(p, Vector3.new(side * random:NextNumber(0.1,0.28), random:NextNumber(-0.16,0.16), 2.7 * (1-i/4)))
            beam(p, last, a, 0.045, 0.025, BLUE, 0.2)
            last = a
        end
    end
    for i = 0, 1 do
        local offset = i == 0 and Vector3.new(0.12,0,0) or Vector3.new(0,0.12,0)
        local trail = Instance.new("Trail")
        trail.Name = "ElectricWake"
        trail.Attachment0 = attachment(p, Vector3.new(0,0,1.8)+offset)
        trail.Attachment1 = attachment(p, Vector3.new(0,0,1.8)-offset)
        trail.Lifetime = 0.075
        trail.MinLength = 0.03
        trail.FaceCamera = true
        trail.Color = ColorSequence.new(WHITE, BLUE)
        trail.Transparency = NumberSequence.new(0.22,1)
        trail.WidthScale = NumberSequence.new(1,0)
        trail.LightEmission = 1
        trail.LightInfluence = 0
        trail.Parent = p
    end
    p.Parent = workspace
    return p
end
function VFX.Release(p: BasePart)
    if not p.Parent or p:GetAttribute("Released") then return end
    p:SetAttribute("Released", true)
    for _, e in p:GetDescendants() do
        if e:IsA("Beam") or e:IsA("Trail") then e.Enabled = false end
    end
    Debris:AddItem(p, 0.2)
end
function VFX.Impact(position: Vector3, normal: Vector3)
    local p = rootPart("LightningSenbon_Hit", frame(position + normal * 0.06, normal))
    local center = attachment(p, Vector3.zero)
    local random = Random.new()
    local rays = {}
    for i = 1, 5 do
        local angle = i * math.pi * 2 / 5 + random:NextNumber(-0.2,0.2)
        local radial = Vector3.new(math.cos(angle), math.sin(angle), 0)
        local length = random:NextNumber(0.8,1.5)
        local mid = attachment(p, radial * length * 0.5 + Vector3.new(0,0,-0.3))
        local tip = attachment(p, radial * length + Vector3.new(0,0,-0.1))
        table.insert(rays, beam(p, center, mid, 0.09,0.06,WHITE,0.03))
        table.insert(rays, beam(p, mid, tip, 0.06,0,BLUE,0.15))
    end
    local sparks = Instance.new("ParticleEmitter")
    sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparks.Color = ColorSequence.new(WHITE,BLUE)
    sparks.LightEmission = 1
    sparks.LightInfluence = 0
    sparks.EmissionDirection = Enum.NormalId.Front
    sparks.SpreadAngle = Vector2.new(75,75)
    sparks.Speed = NumberRange.new(5,12)
    sparks.Drag = 5
    sparks.Lifetime = NumberRange.new(0.12,0.25)
    sparks.Size = NumberSequence.new(0.16,0)
    sparks.Transparency = NumberSequence.new(0,1)
    sparks.Rate = 75
    sparks.Parent = center
    p.Parent = workspace
    Debris:AddItem(p,0.55)
    task.delay(0.1,function()
        if not p.Parent then return end
        sparks.Enabled = false
        for _, e in rays do
            TweenService:Create(e,TweenInfo.new(0.13),{Width0=0,Width1=0,Brightness=0}):Play()
        end
    end)
end
return VFX
