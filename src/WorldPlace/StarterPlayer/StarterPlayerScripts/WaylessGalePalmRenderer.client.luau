--!nonstrict
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("WaylessGalePalmVFX")
local active={}
local WHITE=Color3.fromRGB(229,255,248)
local MINT=Color3.fromRGB(153,220,201)
local function curve(s,count,width,alpha,color)
    local c={nodes={},beams={},width=width,alpha=alpha}
    for i=1,count do
        local a=Instance.new("Attachment"); a.Parent=s.root; c.nodes[i]=a
    end
    for i=1,count-1 do
        local b=Instance.new("Beam")
        b.Attachment0=c.nodes[i]; b.Attachment1=c.nodes[i+1]
        b.FaceCamera=true; b.Segments=1; b.LightEmission=0.45; b.LightInfluence=0
        b.Color=ColorSequence.new(color)
        b.Transparency=NumberSequence.new(alpha)
        b.Parent=s.root; c.beams[i]=b
    end
    return c
end
local function style(c,opacity)
    for i,b in c.beams do
        local n=#c.beams
        b.Width0=c.width*math.sin((i-1)/n*math.pi)*opacity
        b.Width1=c.width*math.sin(i/n*math.pi)*opacity
        b.Enabled=opacity>0.001
    end
end
local function animate(s,age)
    -- Open crescents, staggered in depth: a brief palm shockwave, not a tunnel.
    for j,c in s.fronts do
        local t=math.clamp((age-(j-1)*0.035)/0.34,0,1)
        local distance=s.range*(1-(1-t)^2)
        local fade=math.sin(t*math.pi)^0.55
        local rx=0.65+distance*math.sin(s.angle)*0.86
        local ry=0.8+distance*0.24
        for i,a in c.nodes do
            local theta=-math.pi*0.78+(i-1)/(#c.nodes-1)*math.pi*1.56
            theta+=j%2==0 and math.pi or 0
            a.Position=Vector3.new(math.cos(theta)*rx,math.sin(theta)*ry,-distance)
        end
        style(c,fade)
    end
    for j,c in s.streams do
        local t=math.clamp((age-c.delay)/0.38,0,1)
        local fade=math.sin(t*math.pi)
        local head=s.range*math.min(1,t*1.3)
        for i,a in c.nodes do
            local f=(i-1)/(#c.nodes-1)
            local distance=math.max(0,head-(1-f)*s.range*0.46)
            local turn=c.angle+math.sin(f*math.pi+t*4)*0.045
            a.Position=Vector3.new(math.sin(turn)*distance,c.height*(0.2+distance*0.12)+math.sin(f*math.pi)*0.35,-math.cos(turn)*distance)
        end
        style(c,fade)
    end
    for j,c in s.swirls do
        local t=math.clamp((age-c.delay)/0.4,0,1)
        local center=s.range*(0.12+0.72*t)
        local radius=(0.5+center*0.18)*c.scale
        for i,a in c.nodes do
            local f=(i-1)/(#c.nodes-1)
            local theta=c.phase+f*math.pi*1.65-t*5
            a.Position=Vector3.new(
                math.sin(c.angle)*center+math.cos(theta)*radius,
                c.height+math.sin(theta)*radius*0.65,
                -math.cos(c.angle)*center+(f-0.5)*s.range*0.24)
        end
        style(c,math.sin(t*math.pi))
    end
    local flash=math.clamp(age/0.14,0,1)
    s.flash.Size=Vector3.new(1.6+flash*2.6,1.6+flash*2.6,0.3+flash*0.4)
    s.flash.Transparency=0.88+0.12*flash
end
remote.OnClientEvent:Connect(function(origin,direction,range,halfAngle)
    if typeof(origin)~="Vector3" or typeof(direction)~="Vector3" or typeof(range)~="number" then return end
    if range~=range or range<=0 or range==math.huge or direction.Magnitude<0.001 then return end
    local root=Instance.new("Part")
    root.Name="GalePalm_LocalVFX"; root.Size=Vector3.one*0.1; root.Transparency=1
    root.Anchored=true; root.CanCollide=false; root.CanTouch=false; root.CanQuery=false; root.CastShadow=false
    root.CFrame=CFrame.lookAt(origin,origin+direction)
    local s={root=root,range=range,angle=math.rad(math.clamp(halfAngle or 42,8,80)),born=os.clock(),fronts={},streams={},swirls={}}
    for j=1,5 do s.fronts[j]=curve(s,19,j==1 and 0.72 or 0.4,j==1 and 0.24 or 0.48,j==1 and WHITE or MINT) end
    local rng=Random.new()
    for j=1,20 do
        local c=curve(s,8,j%3==0 and 0.32 or 0.15,0.38,WHITE)
        c.angle=((j-1)/19*2-1)*s.angle*0.88
        c.height=rng:NextNumber(-1.5,1.5); c.delay=rng:NextNumber(0,0.1)
        s.streams[j]=c
    end
    for j=1,6 do
        local c=curve(s,15,j%2==0 and 0.38 or 0.2,0.5,WHITE)
        c.angle=rng:NextNumber(-0.55,0.55)*s.angle
        c.phase=rng:NextNumber(0,math.pi*2); c.scale=rng:NextNumber(0.7,1.2)
        c.height=rng:NextNumber(-0.7,0.7); c.delay=(j-1)*0.017
        s.swirls[j]=c
    end
    local mist=Instance.new("ParticleEmitter")
    mist.Name="WindVolume"; mist.Texture="rbxasset://textures/particles/smoke_main.dds"
    mist.Color=ColorSequence.new(WHITE,MINT); mist.LightEmission=0.2; mist.LightInfluence=0
    mist.Rate=0; mist.Lifetime=NumberRange.new(0.22,0.4)
    mist.EmissionDirection=Enum.NormalId.Front
    mist.Speed=NumberRange.new(range*1.5,range*2.2); mist.Drag=3
    mist.SpreadAngle=Vector2.new(math.min(halfAngle or 42,35),16)
    mist.Rotation=NumberRange.new(0,360); mist.RotSpeed=NumberRange.new(-110,110)
    mist.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.1),NumberSequenceKeypoint.new(0.5,3.4),NumberSequenceKeypoint.new(1,4.8)})
    mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.15,0.89),NumberSequenceKeypoint.new(0.6,0.94),NumberSequenceKeypoint.new(1,1)})
    mist.Parent=root
    local flash=root:Clone()
    flash:ClearAllChildren(); flash.Name="PalmPressure"; flash.Shape=Enum.PartType.Ball
    flash.Material=Enum.Material.Neon; flash.Color=WHITE; flash.Parent=root
    s.flash=flash
    animate(s,0); root.Parent=workspace; mist:Emit(22)
    Debris:AddItem(root,0.8); table.insert(active,s)
end)
RunService.RenderStepped:Connect(function()
    for i=#active,1,-1 do
        local s=active[i]; local age=os.clock()-s.born
        if age>0.58 or not s.root.Parent then s.root:Destroy(); table.remove(active,i)
        else animate(s,age) end
    end
end)
