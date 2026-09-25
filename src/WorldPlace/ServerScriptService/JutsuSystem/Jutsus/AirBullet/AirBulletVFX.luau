--!nonstrict
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local VFX={}
local WHITE=Color3.fromRGB(233,255,250)
local MINT=Color3.fromRGB(163,220,208)
local function frame(position,direction)
    local up=math.abs(direction.Unit.Y)>0.98 and Vector3.xAxis or Vector3.yAxis
    return CFrame.lookAt(position,position+direction,up)
end
local function part(name,cf)
    local p=Instance.new("Part")
    p.Name=name; p.CFrame=cf; p.Size=Vector3.one*0.1
    p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
    p.CastShadow=false; p.Transparency=1
    return p
end
local function chain(root,count,width,alpha)
    local c={nodes={},beams={},width=width}
    for i=1,count do
        local a=Instance.new("Attachment"); a.Parent=root; c.nodes[i]=a
    end
    for i=1,count-1 do
        local b=Instance.new("Beam")
        b.Attachment0=c.nodes[i]; b.Attachment1=c.nodes[i+1]
        b.FaceCamera=true; b.Segments=1; b.Color=ColorSequence.new(WHITE,MINT)
        b.LightEmission=0.5; b.LightInfluence=0; b.Transparency=NumberSequence.new(alpha)
        b.Width0=width*math.sin((i-1)/(count-1)*math.pi)
        b.Width1=width*math.sin(i/(count-1)*math.pi)
        b.Parent=root; c.beams[i]=b
    end
    return c
end
function VFX.Create(position,direction,radius)
    local root=part("AirBullet_CompressedWind",frame(position,direction))
    root.Shape=Enum.PartType.Ball; root.Material=Enum.Material.Neon
    root.Color=WHITE; root.Size=Vector3.new(radius*1.5,radius*1.5,radius*2.3)
    root.Transparency=0.87
    local curves={}
    for j=1,5 do curves[j]=chain(root,15,radius*(j<=3 and 0.2 or 0.1),j<=3 and 0.25 or 0.5) end
    for j=1,3 do
        local a=Instance.new("Attachment"); local b=Instance.new("Attachment")
        local theta=j*math.pi*2/3
        local center=Vector3.new(math.cos(theta)*radius*0.55,math.sin(theta)*radius*0.55,radius*0.4)
        a.Position=center+Vector3.yAxis*radius*0.15; b.Position=center-Vector3.yAxis*radius*0.15
        a.Parent=root; b.Parent=root
        local trail=Instance.new("Trail")
        trail.Attachment0=a; trail.Attachment1=b; trail.FaceCamera=true
        trail.Lifetime=0.11; trail.MinLength=0.05
        trail.Color=ColorSequence.new(WHITE,MINT); trail.LightEmission=0.35
        trail.Transparency=NumberSequence.new(0.4,1)
        trail.WidthScale=NumberSequence.new(1,0); trail.Parent=root
    end
    local mist=Instance.new("ParticleEmitter")
    mist.Texture="rbxasset://textures/particles/smoke_main.dds"
    mist.Color=ColorSequence.new(WHITE); mist.LightInfluence=0; mist.LightEmission=0.15
    mist.Rate=35; mist.Lifetime=NumberRange.new(0.12,0.22)
    mist.Speed=NumberRange.new(1,3); mist.EmissionDirection=Enum.NormalId.Back
    mist.SpreadAngle=Vector2.new(20,20); mist.Rotation=NumberRange.new(0,360)
    mist.RotSpeed=NumberRange.new(-90,90); mist.Size=NumberSequence.new(radius, radius*2.5)
    mist.Transparency=NumberSequence.new(0.91,1); mist.Parent=root
    local born=os.clock()
    local function animate()
        local t=os.clock()-born
        for j,c in curves do
            for i,a in c.nodes do
                local f=(i-1)/(#c.nodes-1)
                local theta=j*math.pi*2/5+f*math.pi*2.15-t*(j%2==0 and 15 or -12)
                local r=radius*(0.35+math.sin(f*math.pi)*0.7)
                -- Narrow leading tip, curled wind flowing into a trailing tail.
                a.Position=Vector3.new(math.cos(theta)*r,math.sin(theta)*r,radius*(-1+f*3.7))
            end
        end
    end
    animate(); root.Parent=workspace
    local connection=RunService.Heartbeat:Connect(animate)
    root.Destroying:Once(function() connection:Disconnect() end)
    return root
end
function VFX.Impact(position,normal,radius)
    local root=part("AirBullet_WindImpact",frame(position+normal*0.08,normal))
    local curves={}
    for j=1,3 do curves[j]=chain(root,19,radius*(j==1 and 0.35 or 0.18),0.4) end
    local spokes={}
    for j=1,8 do spokes[j]=chain(root,4,radius*0.15,0.4) end
    local born=os.clock()
    local function animate()
        local t=math.clamp((os.clock()-born)/0.27,0,1)
        local r=radius*(0.5+3*(1-(1-t)^3))
        for j,c in curves do
            for i,a in c.nodes do
                local f=(i-1)/(#c.nodes-1)
                local theta=f*math.pi*1.65+j*2.1+t*2
                a.Position=Vector3.new(math.cos(theta)*r,math.sin(theta)*r,(j-1)*radius*0.3)
            end
            for i,b in c.beams do
                b.Width0=c.width*math.sin((i-1)/#c.beams*math.pi)*(1-t)
                b.Width1=c.width*math.sin(i/#c.beams*math.pi)*(1-t)
            end
        end
        for j,c in spokes do
            local theta=j*math.pi/4
            for i,a in c.nodes do
                local f=0.4+(i-1)*0.23
                a.Position=Vector3.new(math.cos(theta)*r*f,math.sin(theta)*r*f,radius*math.sin(f*math.pi)*0.4)
            end
            for _,b in c.beams do b.Width0=c.width*(1-t); b.Width1=0 end
        end
    end
    animate(); root.Parent=workspace
    local connection=RunService.Heartbeat:Connect(animate)
    root.Destroying:Once(function() connection:Disconnect() end)
    Debris:AddItem(root,0.3)
end
return VFX
