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
function VFX.Create(position,direction)
    local root=part("WindBlade_Crescent",frame(position,direction))
    local curves={}
    -- Broad translucent cutting body, bright edge, two trailing pressure arcs.
    for j=1,4 do
        curves[j]=chain(root,23,({0.82,0.15,0.3,0.17})[j],({0.58,0.13,0.55,0.7})[j])
    end
    local ribbons={}
    for j=1,7 do ribbons[j]=chain(root,9, j%2==0 and 0.15 or 0.085,0.5) end
    for j=1,5 do
        local x=(j-3)*1.1
        local center=Vector3.new(x,x*0.16,0.25+x*x*0.15)
        local a=Instance.new("Attachment"); local b=Instance.new("Attachment")
        a.Position=center+Vector3.xAxis*0.22; b.Position=center-Vector3.xAxis*0.22
        a.Parent=root; b.Parent=root
        local trail=Instance.new("Trail")
        trail.Attachment0=a; trail.Attachment1=b; trail.FaceCamera=true
        trail.Lifetime=0.12; trail.MinLength=0.05
        trail.Color=ColorSequence.new(WHITE,MINT); trail.LightEmission=0.4
        trail.Transparency=NumberSequence.new(0.55,1)
        trail.WidthScale=NumberSequence.new(1,0); trail.Parent=root
    end
    local mist=Instance.new("ParticleEmitter")
    mist.Texture="rbxasset://textures/particles/smoke_main.dds"
    mist.Color=ColorSequence.new(WHITE); mist.LightInfluence=0; mist.LightEmission=0.2
    mist.Rate=24; mist.Lifetime=NumberRange.new(0.12,0.23)
    mist.Speed=NumberRange.new(2,5); mist.EmissionDirection=Enum.NormalId.Back
    mist.SpreadAngle=Vector2.new(15,15); mist.Rotation=NumberRange.new(0,360)
    mist.Size=NumberSequence.new(1.3,2.8); mist.Transparency=NumberSequence.new(0.93,1)
    mist.Parent=root
    local born=os.clock()
    local function animate()
        local t=os.clock()-born
        for j,c in curves do
            for i,a in c.nodes do
                local f=(i-1)/(#c.nodes-1)
                local theta=(f-0.5)*math.pi*0.96
                local x=math.sin(theta)*(j<=2 and 3.25 or 3.05)
                local z=(1-math.cos(theta))*2.1+(j<=2 and 0 or (j-2)*0.55)
                a.Position=Vector3.new(x,x*0.16+math.sin(t*14+f*5)*0.035,z)
            end
        end
        for j,c in ribbons do
            local x=(j-4)*0.82
            for i,a in c.nodes do
                local f=(i-1)/(#c.nodes-1)
                a.Position=Vector3.new(x+math.sin(f*4+t*14+j)*0.17*f,
                    x*0.16+math.sin(f*5-t*12+j)*0.18*f,
                    0.2+x*x*0.13+f*(2.5+(j%3)*0.55))
            end
        end
    end
    animate(); root.Parent=workspace
    local connection=RunService.Heartbeat:Connect(animate)
    root.Destroying:Once(function() connection:Disconnect() end)
    return root
end

function VFX.Impact(position,normal,radius)
    local root=part("WindBlade_CutImpact",frame(position+normal*0.08,normal))
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
                a.Position=Vector3.new(math.cos(theta)*r,math.sin(theta)*r*0.4,(j-1)*radius*0.3)
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
