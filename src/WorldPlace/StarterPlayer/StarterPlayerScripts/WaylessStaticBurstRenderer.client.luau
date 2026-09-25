--!nonstrict
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local remote = game:GetService("ReplicatedStorage"):WaitForChild("WaylessStaticBurstVFX")
local WHITE = Color3.fromRGB(222,247,255)
local CYAN = Color3.fromRGB(67,191,255)
local BLUE = Color3.fromRGB(65,103,255)
local active = {}
local function ball(name, position, color, parent)
    local p = Instance.new("Part")
    p.Name = name; p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon
    p.Size = Vector3.one * 0.1; p.Position = position; p.Color = color
    p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
    p.CastShadow = false; p.Transparency = 1; p.Parent = parent
    return p
end
local function direction(rng)
    local y = rng:NextNumber(-1,1)
    local angle = rng:NextNumber(0,math.pi*2)
    local xz = math.sqrt(1-y*y)
    return Vector3.new(xz*math.cos(angle),y,xz*math.sin(angle))
end
local function scramble(s)
    for _,arc in s.arcs do
        local n = direction(s.rng)
        local reference = math.abs(n.Y)>0.9 and Vector3.xAxis or Vector3.yAxis
        local u = n:Cross(reference).Unit
        local v = n:Cross(u).Unit
        local rotation = s.rng:NextNumber(0,math.pi*2)
        local tangent = u*math.cos(rotation)+v*math.sin(rotation)
        local span = s.rng:NextNumber(0.24,0.5)
        arc.visible = s.rng:NextNumber()>0.18
        for i=1,5 do
            local along = ((i-1)/4-0.5)*span
            local zigzag = (i==1 or i==5) and 0 or s.rng:NextNumber(-0.065,0.065)
            arc.points[i] = (n+tangent*along+v*zigzag).Unit*s.rng:NextNumber(0.95,1.025)
        end
    end
end
local function animate(s,age)
    local grow = 1-(1-math.clamp(age/0.16,0,1))^3
    local radius = s.radius*(0.12+0.88*grow)
    local fade = math.clamp((age-0.18)/0.34,0,1)
    local pulse = 0.5+0.5*math.sin(age*83)
    -- Solid spherical silhouette; only short, disconnected static scratches.
    s.root.Size = Vector3.one*radius*2
    s.root.Transparency = 0.86+0.14*fade
    s.inner.Size = Vector3.one*radius*1.74
    s.inner.Transparency = 0.88+0.12*fade
    s.core.Size = Vector3.one*radius*(0.48+0.05*pulse)
    s.core.Transparency = 0.58+0.42*math.clamp(age/0.36,0,1)
    s.light.Brightness = (1.2+0.35*pulse)*(1-fade)
    local tick = math.floor(age*24)
    if tick~=s.tick then s.tick=tick; scramble(s) end
    for _,arc in s.arcs do
        for i,a in arc.nodes do a.Position=arc.points[i]*radius end
        for _,beam in arc.beams do
            beam.Enabled = arc.visible and fade<1
            beam.Width0 = beam:GetAttribute("BaseWidth")*(1-fade)*(0.8+0.2*pulse)
            beam.Width1 = beam.Width0
        end
    end
end
remote.OnClientEvent:Connect(function(position,radius)
    if typeof(position)~="Vector3" or typeof(radius)~="number" or radius~=radius or radius==math.huge or radius<=0 then return end
    local s = {radius=radius,born=os.clock(),rng=Random.new(),arcs={},tick=-1}
    s.root = ball("StaticBurst_Orb",position,BLUE,nil)
    s.inner = ball("IonGlow",position,CYAN,s.root)
    s.core = ball("ElectricCore",position,WHITE,s.root)
    for j=1,9 do
        local arc = {nodes={},beams={},points={}}
        for i=1,5 do
            local a=Instance.new("Attachment"); a.Parent=s.root; arc.nodes[i]=a
        end
        for i=1,4 do
            for layer=1,2 do
                local b=Instance.new("Beam")
                b.Attachment0=arc.nodes[i]; b.Attachment1=arc.nodes[i+1]
                b.FaceCamera=true; b.Segments=1; b.LightEmission=1; b.LightInfluence=0
                b.Color=ColorSequence.new(layer==1 and CYAN or WHITE)
                b.Transparency=NumberSequence.new(layer==1 and 0.82 or 0.12)
                b:SetAttribute("BaseWidth",layer==1 and 0.3 or 0.075)
                b.Parent=s.root; table.insert(arc.beams,b)
            end
        end
        table.insert(s.arcs,arc)
    end
    s.light=Instance.new("PointLight")
    s.light.Color=CYAN; s.light.Range=math.min(radius*1.6,18)
    s.light.Shadows=false; s.light.Parent=s.root
    animate(s,0)
    s.root.Parent=workspace
    Debris:AddItem(s.root,0.8)
    table.insert(active,s)
end)
RunService.RenderStepped:Connect(function()
    local now=os.clock()
    for i=#active,1,-1 do
        local s=active[i]
        local age=now-s.born
        if age>0.54 or not s.root.Parent then
            s.root:Destroy(); table.remove(active,i)
        else
            animate(s,age)
        end
    end
end)
