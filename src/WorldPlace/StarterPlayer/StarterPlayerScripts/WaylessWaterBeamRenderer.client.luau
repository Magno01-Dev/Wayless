--!nonstrict
local RunService=game:GetService("RunService")
local active={}
local pending={}
local BLUE=Color3.fromRGB(26,119,203)
local AQUA=Color3.fromRGB(75,197,238)
local FOAM=Color3.fromRGB(213,247,255)
local function attachment(root)
    local a=Instance.new("Attachment"); a.Parent=root; return a
end
local function beam(root,a,b,w0,w1,color,alpha)
    local v=Instance.new("Beam")
    v.Attachment0=a; v.Attachment1=b; v.FaceCamera=true; v.Segments=1
    v.Width0=w0; v.Width1=w1; v.Color=ColorSequence.new(color)
    v.Transparency=NumberSequence.new(alpha); v.LightEmission=0.2; v.LightInfluence=0
    v.Parent=root
    return {object=v,w0=w0,w1=w1}
end
local function chain(s,count,width,color,alpha)
    local c={}
    for i=1,count do c[i]=attachment(s.localRoot) end
    for i=1,count-1 do
        table.insert(s.beams,beam(s.localRoot,c[i],c[i+1],width,width,color,alpha))
    end
    return c
end
local function emitter(parent,texture,rate,color,size,lifetime,speed,alpha)
    local p=Instance.new("ParticleEmitter")
    p.Texture=texture; p.Rate=rate; p.Color=ColorSequence.new(color)
    p.LightEmission=0.15; p.LightInfluence=0; p.Lifetime=lifetime; p.Speed=speed
    p.Size=NumberSequence.new(size,0); p.Transparency=NumberSequence.new(alpha,1)
    p.Rotation=NumberRange.new(0,360); p.RotSpeed=NumberRange.new(-90,90)
    p.EmissionDirection=Enum.NormalId.Back; p.SpreadAngle=Vector2.new(75,75)
    p.Parent=parent; return p
end
local function create(model,root,start,finish,control)
    local localRoot=Instance.new("Part")
    localRoot.Name="WaterBeam_ClientDetail"; localRoot.Size=Vector3.one*0.1
    localRoot.Anchored=true; localRoot.CanCollide=false; localRoot.CanQuery=false
    localRoot.CanTouch=false; localRoot.CastShadow=false; localRoot.Transparency=1
    localRoot.CFrame=root.CFrame; localRoot.Parent=model
    local s={model=model,root=root,start=start,finish=finish,control=control,localRoot=localRoot,
        beams={},spirals={},pulses={},emitters={},born=os.clock()}
    s.a=attachment(localRoot); s.b=attachment(localRoot)
    -- A translucent outer stream with two denser inner layers.
    table.insert(s.beams,beam(localRoot,s.a,s.b,0.38,3.4,BLUE,0.46))
    table.insert(s.beams,beam(localRoot,s.a,s.b,0.27,2.45,AQUA,0.24))
    table.insert(s.beams,beam(localRoot,s.a,s.b,0.16,0.85,FOAM,0.52))
    for j=1,4 do s.spirals[j]=chain(s,33,j%2==0 and 0.19 or 0.34,j%2==0 and FOAM or AQUA,j%2==0 and 0.35 or 0.27) end
    for j=1,6 do s.pulses[j]=chain(s,8,0.13,FOAM,0.23) end
    local smoke="rbxasset://textures/particles/smoke_main.dds"
    local sparkle="rbxasset://textures/particles/sparkles_main.dds"
    local mist=emitter(s.b,smoke,30,FOAM,2.8,NumberRange.new(0.18,0.35),NumberRange.new(3,7),0.9)
    mist.SpreadAngle=Vector2.new(180,180)
    local drops=emitter(s.b,sparkle,65,AQUA,0.21,NumberRange.new(0.2,0.42),NumberRange.new(8,17),0.15)
    drops.Acceleration=Vector3.new(0,-32,0); drops.Drag=2
    local spray=emitter(s.a,sparkle,18,FOAM,0.12,NumberRange.new(0.1,0.17),NumberRange.new(12,22),0.3)
    spray.EmissionDirection=Enum.NormalId.Front; spray.SpreadAngle=Vector2.new(12,12)
    s.emitters={mist,drops,spray}
    active[model]=s
end
local function watch(model)
    if model.Name=="WaterBeam_VFX" and not active[model] then pending[model]=os.clock() end
end
workspace.ChildAdded:Connect(watch)
for _,model in workspace:GetChildren() do watch(model) end
RunService.RenderStepped:Connect(function()
    local now=os.clock()
    for model,born in pending do
        if not model.Parent or now-born>4 then pending[model]=nil
        else
            local root=model:FindFirstChild("Root",true)
            local start=root and root:FindFirstChild("Start")
            local finish=root and root:FindFirstChild("End")
            local control=root and root:FindFirstChild("WaterBeamControl")
            if root and root:IsA("BasePart") and start and start:IsA("Attachment")
                and finish and finish:IsA("Attachment") and control and control:IsA("Beam") then
                create(model,root,start,finish,control); pending[model]=nil
            end
        end
    end
    for model,s in active do
        if not model.Parent or not s.root.Parent or not s.localRoot.Parent then
            s.localRoot:Destroy(); active[model]=nil
        else
            if s.control.Enabled then s.armed=true end
            if ((s.armed and not s.control.Enabled) or now-s.born>4) and not s.stopped then s.stopped=now end
            local fade=s.stopped and math.max(0,1-(now-s.stopped)/0.16) or 1
            local delta=s.finish.WorldPosition-s.start.WorldPosition
            local length=delta.Magnitude
            if length>0.01 then
                local unit=delta.Unit
                s.localRoot.CFrame=CFrame.lookAt(s.start.WorldPosition,s.finish.WorldPosition,
                    math.abs(unit.Y)>0.98 and Vector3.xAxis or Vector3.yAxis)
            end
            s.a.Position=Vector3.zero; s.b.Position=Vector3.new(0,0,-length)
            local t=now-s.born
            for j,c in s.spirals do
                for i,a in c do
                    local f=(i-1)/(#c-1)
                    local radius=(0.1+1.35*f)*math.min(1,length/5)
                    local theta=f*math.min(length*0.48,math.pi*9)-t*13+j*math.pi/2
                    radius*=1+math.sin(f*19-t*21+j)*0.07
                    a.Position=Vector3.new(math.cos(theta)*radius,math.sin(theta)*radius,-length*f)
                end
            end
            for j,c in s.pulses do
                local head=(t*1.9+j/6)%1
                for i,a in c do
                    local f=math.clamp(head-(1-(i-1)/(#c-1))*0.09,0,1)
                    local theta=j*2.4+f*9-t*3
                    local r=(0.1+f*1.2)*math.min(1,length/5)
                    a.Position=Vector3.new(math.cos(theta)*r,math.sin(theta)*r,-length*f)
                end
            end
            local pulse=0.96+0.04*math.sin(t*23)
            for _,v in s.beams do
                v.object.Enabled=s.armed==true and fade>0 and length>0.05
                v.object.Width0=v.w0*fade*pulse; v.object.Width1=v.w1*fade*pulse
            end
            for _,p in s.emitters do p.Enabled=s.armed==true and not s.stopped and length>0.5 end
            if s.stopped and now-s.stopped>0.6 then
                s.localRoot:Destroy(); active[model]=nil
            end
        end
    end
end)
