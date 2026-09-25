--!nonstrict
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("WaylessWindSweepVFX")
local active={}
local WHITE=Color3.fromRGB(230,255,248)
local MINT=Color3.fromRGB(158,222,204)
local function curve(root,count,width,alpha)
    local c={nodes={},beams={},width=width}
    for i=1,count do
        local a=Instance.new("Attachment"); a.Parent=root; c.nodes[i]=a
    end
    for i=1,count-1 do
        local b=Instance.new("Beam")
        b.Attachment0=c.nodes[i]; b.Attachment1=c.nodes[i+1]
        b.FaceCamera=true; b.Segments=1; b.LightEmission=0.45; b.LightInfluence=0
        b.Color=ColorSequence.new(WHITE,MINT); b.Transparency=NumberSequence.new(alpha)
        b.Parent=root; c.beams[i]=b
    end
    return c
end
local function style(c,fade)
    for i,b in c.beams do
        b.Width0=c.width*math.sin((i-1)/#c.beams*math.pi)*fade
        b.Width1=c.width*math.sin(i/#c.beams*math.pi)*fade
        b.Enabled=fade>0.001
    end
end
local function point(theta,radius,y)
    return Vector3.new(math.sin(theta)*radius,y,-math.cos(theta)*radius)
end
local function animate(s,age)
    for j,c in s.arcs do
        local t=math.clamp((age-(j-1)*0.018)/0.4,0,1)
        local r=s.range*(0.16+0.84*(1-(1-t)^3))*(1-(j-1)*0.055)
        local reveal=math.clamp(t/0.32,0,1)
        local fade=math.sin(t*math.pi)^0.65
        for i,a in c.nodes do
            local f=(i-1)/(#c.nodes-1)
            local theta=-s.angle+2*s.angle*f*reveal
            local y=(j-3)*0.26+math.sin(f*math.pi)*0.18
            a.Position=point(theta,r,y)
        end
        style(c,fade)
    end
    for j,c in s.wisps do
        local t=math.clamp((age-c.delay)/0.35,0,1)
        local r=s.range*(0.15+0.8*t)
        for i,a in c.nodes do
            local f=(i-1)/(#c.nodes-1)
            local theta=math.clamp(c.angle+(f-0.5)*0.34+(t-0.5)*0.23,-s.angle,s.angle)
            a.Position=point(theta,r*(0.82+0.18*f),c.height+math.sin(f*math.pi+t*5)*0.35)
        end
        style(c,math.sin(t*math.pi))
    end
end
remote.OnClientEvent:Connect(function(origin,direction,range,halfAngle)
    if typeof(origin)~="Vector3" or typeof(direction)~="Vector3" or typeof(range)~="number" then return end
    if range~=range or range<=0 or range==math.huge or direction.Magnitude<0.001 then return end
    local root=Instance.new("Part")
    root.Name="WindSweep_LocalVFX"; root.Size=Vector3.one*0.1; root.Transparency=1
    root.Anchored=true; root.CanCollide=false; root.CanTouch=false; root.CanQuery=false; root.CastShadow=false
    root.CFrame=CFrame.lookAt(origin,origin+direction)
    local s={root=root,range=range,angle=math.rad(math.clamp(halfAngle or 70,20,89)),born=os.clock(),arcs={},wisps={}}
    for j=1,6 do s.arcs[j]=curve(root,27,j==2 and 0.8 or 0.25,j==2 and 0.56 or 0.28) end
    local rng=Random.new()
    for j=1,16 do
        local c=curve(root,8,j%3==0 and 0.28 or 0.13,0.45)
        c.angle=(-1+2*(j-1)/15)*s.angle*0.9
        c.height=rng:NextNumber(-1.1,0.7); c.delay=rng:NextNumber(0,0.13)
        s.wisps[j]=c
    end
    -- Local mist travels outward through the same frontal sector.
    local emitters={}
    for j=1,7 do
        local theta=(-1+2*(j-1)/6)*s.angle*0.86
        local a=Instance.new("Attachment")
        a.CFrame=CFrame.lookAt(point(theta,1,-0.5),point(theta,2,-0.5))
        a.Parent=root
        local mist=Instance.new("ParticleEmitter")
        mist.Texture="rbxasset://textures/particles/smoke_main.dds"
        mist.Color=ColorSequence.new(WHITE,MINT); mist.LightInfluence=0; mist.LightEmission=0.15
        mist.Rate=0; mist.Lifetime=NumberRange.new(0.2,0.36)
        mist.Speed=NumberRange.new(range*1.7,range*2.4); mist.Drag=3
        mist.EmissionDirection=Enum.NormalId.Front; mist.SpreadAngle=Vector2.new(12,12)
        mist.Rotation=NumberRange.new(0,360); mist.RotSpeed=NumberRange.new(-100,100)
        mist.Size=NumberSequence.new(1.1,3.8)
        mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.15,0.89),NumberSequenceKeypoint.new(1,1)})
        mist.Parent=a; table.insert(emitters,mist)
    end
    animate(s,0); root.Parent=workspace
    for _,mist in emitters do mist:Emit(5) end
    Debris:AddItem(root,0.8); table.insert(active,s)
end)
RunService.RenderStepped:Connect(function()
    for i=#active,1,-1 do
        local s=active[i]; local age=os.clock()-s.born
        if age>0.55 or not s.root.Parent then s.root:Destroy(); table.remove(active,i)
        else animate(s,age) end
    end
end)
