--!nonstrict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("WaylessLightningStreamVFX")
local WHITE = Color3.fromRGB(229,251,255)
local CYAN = Color3.fromRGB(67,191,255)
local BLUE = Color3.fromRGB(54,104,255)
local VIOLET = Color3.fromRGB(139,122,255)
local active = {}
local count = 14
local function anchor(root)
    local a = Instance.new("Attachment")
    a.Parent = root
    return a
end
local function line(state, a, b, width, color, alpha, taper)
    local beam = Instance.new("Beam")
    beam.Attachment0 = a; beam.Attachment1 = b
    beam.FaceCamera = true; beam.Segments = 1
    beam.Width0 = width; beam.Width1 = width * (taper or 1)
    beam.Color = ColorSequence.new(color)
    beam.Transparency = NumberSequence.new(alpha)
    beam.LightEmission = 1; beam.LightInfluence = 0; beam.Brightness = 1.6
    beam.Parent = state.root
    table.insert(state.beams,{beam=beam,width=width,taper=taper or 1})
end
local function chain(state, width, color, alpha, halo)
    local points = {}
    for i=1,count+1 do points[i]=anchor(state.root) end
    for i=1,count do
        if halo then line(state,points[i],points[i+1],width*3.7,BLUE,0.82) end
        line(state,points[i],points[i+1],width,color,alpha)
    end
    return points
end
local function sparks(a)
    local e = Instance.new("ParticleEmitter")
    e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    e.Color = ColorSequence.new(WHITE,CYAN)
    e.LightEmission = 1; e.LightInfluence = 0
    e.Lifetime = NumberRange.new(0.1,0.25)
    e.Speed = NumberRange.new(4,11); e.Drag = 5
    e.SpreadAngle = Vector2.new(180,180)
    e.Size = NumberSequence.new(0.18,0)
    e.Transparency = NumberSequence.new(0.1,1)
    e.Rate = 0; e.Parent = a
    return e
end
local function create(id, now)
    local root = Instance.new("Part")
    root.Name = "LightningStream_LocalVFX"
    root.Size = Vector3.one*0.1; root.Transparency=1
    root.Anchored=true; root.CanCollide=false; root.CanQuery=false; root.CanTouch=false; root.CastShadow=false
    local s={root=root,beams={},pulses={},born=now,seed=Random.new():NextNumber(0,100),id=id}
    s.core=chain(s,0.19,WHITE,0.03,true)
    s.rail1=chain(s,0.075,CYAN,0.17)
    s.rail2=chain(s,0.055,VIOLET,0.34)
    s.forks={}
    for i=4,12,4 do
        local b,c=anchor(root),anchor(root)
        line(s,s.core[i],b,0.07,CYAN,0.2)
        line(s,b,c,0.05,WHITE,0.2,0)
        table.insert(s.forks,{index=i,b=b,c=c})
    end
    s.crown={}
    for i=1,9 do s.crown[i]=anchor(root) end
    for i=1,8 do line(s,s.crown[i],s.crown[i+1],0.075,CYAN,0.25) end
    s.endRays={}
    for i=1,5 do
        local b,c=anchor(root),anchor(root)
        line(s,s.core[count+1],b,0.09,WHITE,0.15)
        line(s,b,c,0.055,BLUE,0.25,0)
        table.insert(s.endRays,{b=b,c=c})
    end
    s.riders={}
    for i=1,3 do
        local a,b=anchor(root),anchor(root)
        line(s,a,b,0.5,CYAN,0.4,0.2)
        table.insert(s.riders,{a=a,b=b})
    end
    s.startSparks=sparks(s.core[1]); s.endSparks=sparks(s.core[count+1])
    s.light=Instance.new("PointLight")
    s.light.Color=CYAN; s.light.Range=8; s.light.Brightness=1.4; s.light.Shadows=false
    s.light.Parent=s.core[1]
    root.Parent=workspace
    return s
end
local function pose(s,now,strength)
    local delta=s.finish-s.origin
    local length=delta.Magnitude
    if length<0.05 then return end
    local direction=delta.Unit
    local up=math.abs(direction.Y)>0.98 and Vector3.xAxis or Vector3.yAxis
    s.root.CFrame=CFrame.lookAt(s.origin,s.finish,up)
    local age=now-s.born
    local phase=age*19+s.seed
    local crackle=math.floor(age*26)
    local amplitude=math.min(0.6,length*0.04)
    for i=1,count+1 do
        local t=(i-1)/count
        local envelope=math.sin(t*math.pi)
        local x=math.noise(i*1.73,crackle,s.seed)*amplitude*envelope
        local y=math.noise(i*2.31,s.seed,crackle)*amplitude*envelope
        local core=Vector3.new(x,y,-length*t)
        s.core[i].Position=core
        local orbit=t*math.pi*5-phase
        local radius=amplitude*1.3*envelope
        s.rail1[i].Position=core+Vector3.new(math.cos(orbit)*radius,math.sin(orbit)*radius,0)
        s.rail2[i].Position=core+Vector3.new(math.cos(orbit+math.pi)*radius,math.sin(orbit+math.pi)*radius,0)
    end
    for i,f in s.forks do
        local start=s.core[f.index].Position
        local a=phase*0.4+i*2.1
        local reach=math.min(1.35,length*0.08)
        local radial=Vector3.new(math.cos(a),math.sin(a),0)*reach
        f.b.Position=start+radial*0.6+Vector3.new(0.15,0,-0.65)
        f.c.Position=start+radial+Vector3.new(0,0,-1.4)
    end
    local kick=math.max(0,1-(now-s.lastTick)/0.14)
    local radius=(0.42+0.32*kick)*math.min(1,length/3)
    for i,a in s.crown do
        local theta=(i-1)*math.pi*2/8+phase*0.3
        a.Position=Vector3.new(math.cos(theta)*radius,math.sin(theta)*radius,-0.15)
    end
    for i,f in s.endRays do
        local theta=i*math.pi*2/5-phase*0.5
        local reach=(0.55+0.65*kick)*math.min(1,length/3)
        local radial=Vector3.new(math.cos(theta),math.sin(theta),0)*reach
        local endpoint=Vector3.new(0,0,-length)
        f.b.Position=endpoint+radial*0.55+Vector3.new(0,0,0.2)
        f.c.Position=endpoint+radial+Vector3.new(0,0,0.5)
    end
    for i,r in s.riders do
        local t=((age*2.6)+(i-1)/3)%1
        local z=-length*t
        r.a.Position=Vector3.new(0,0,z)
        r.b.Position=Vector3.new(0,0,math.min(0,z+math.min(1.5,length*0.15)))
    end
    local pulse=(0.88+0.12*math.sin(age*43))*(1+kick*0.24)*strength
    for _, item in s.beams do
        item.beam.Width0=item.width*pulse
        item.beam.Width1=item.width*item.taper*pulse
    end
    s.light.Brightness=(0.8+kick*0.9)*strength
end
remote.OnClientEvent:Connect(function(id,character,origin,finish,hold)
    if typeof(id)~="number" or typeof(character)~="Instance" or typeof(origin)~="Vector3" or typeof(finish)~="Vector3" then return end
    if (finish-origin).Magnitude<0.05 then return end
    local now=os.clock()
    local s=active[id]
    if not s then s=create(id,now); active[id]=s end
    s.character=character; s.origin=origin; s.finish=finish
    s.lastTick=now; s.expires=now+math.clamp(hold,0.08,0.4)
    pose(s,now,1)
    s.startSparks:Emit(3); s.endSparks:Emit(5)
end)
RunService.RenderStepped:Connect(function()
    local now=os.clock()
    for id,s in active do
        local elapsed=now-s.expires
        if not s.character:IsDescendantOf(workspace) or elapsed>0.3 then
            s.root:Destroy(); active[id]=nil
        else
            local strength=math.clamp(1-math.max(0,elapsed)/0.11,0,1)
            pose(s,now,strength)
        end
    end
end)
