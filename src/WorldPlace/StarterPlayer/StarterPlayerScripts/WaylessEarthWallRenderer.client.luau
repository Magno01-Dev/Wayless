--!nonstrict
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local active={}
local pending={}
local function rock(parent,size,cf,color)
    local p=Instance.new("Part")
    p.Name="EarthWall_Rock"; p.Size=size; p.CFrame=cf
    p.Material=Enum.Material.Slate; p.Color=color
    p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
    p.CastShadow=true; p.Parent=parent
    return p
end
local function dust(s,collapse)
    for i=1,7 do
        local anchor=rock(s.folder,Vector3.one*0.1,s.base*CFrame.new((i-4)*s.size.X/7,0.15,0),Color3.new())
        anchor.Transparency=1
        local p=Instance.new("ParticleEmitter")
        p.Texture="rbxasset://textures/particles/smoke_main.dds"
        p.Color=ColorSequence.new(Color3.fromRGB(143,123,98),Color3.fromRGB(100,91,77))
        p.Rate=0; p.Lifetime=NumberRange.new(0.45,0.95)
        p.Speed=NumberRange.new(collapse and 3 or 8,collapse and 7 or 15)
        p.EmissionDirection=Enum.NormalId.Top; p.SpreadAngle=Vector2.new(75,75)
        p.Drag=6; p.Acceleration=Vector3.new(0,1.5,0)
        p.Rotation=NumberRange.new(0,360); p.RotSpeed=NumberRange.new(-65,65)
        p.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.1),NumberSequenceKeypoint.new(0.5,3.8),NumberSequenceKeypoint.new(1,5.5)})
        p.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.65),NumberSequenceKeypoint.new(0.3,0.76),NumberSequenceKeypoint.new(1,1)})
        p.Parent=anchor; p:Emit(collapse and 5 or 9)
        Debris:AddItem(anchor,1.2)
    end
end
local function create(wall)
    local rng=Random.new()
    local folder=Instance.new("Folder"); folder.Name="EarthWall_LocalDetail"; folder.Parent=workspace
    local s={wall=wall,folder=folder,size=wall.Size,base=wall.CFrame*CFrame.new(0,-wall.Size.Y/2,0),born=os.clock(),slabs={},chips={}}
    local function color()
        local v=rng:NextNumber(0.8,1.22)
        return Color3.fromRGB(111*v,94*v,74*v)
    end
    -- Solid visual core rises with the detailed stones. The original server
    -- part remains invisible locally but continues providing collision.
    s.core=rock(folder,Vector3.new(s.size.X,0.02,s.size.Z),s.base,wall.Color)
    s.core.Name="EarthWall_RisingCore"
    s.core.Material=wall.Material
    -- Interlocking strata on both faces; the original solid wall stays intact.
    for side=-1,1,2 do
        for row=1,3 do
            for col=1,7 do
                local w=s.size.X/7
                local h=s.size.Y/3
                local depth=rng:NextNumber(0.22,0.5)
                local size=Vector3.new(w*rng:NextNumber(0.88,0.98),h*rng:NextNumber(0.9,0.98),depth)
                local x=(col-4)*w
                local y=(row-0.5)*h
                local cf=s.base*CFrame.new(x,y,side*(s.size.Z/2+depth*0.4))*CFrame.Angles(0,0,rng:NextNumber(-0.025,0.025))
                local p=rock(folder,size,cf,color())
                table.insert(s.slabs,{part=p,target=cf,size=size,delay=math.abs(col-4)*0.018+(row-1)*0.025})
            end
        end
    end
    for i=1,9 do
        local x=(i-5)*s.size.X/9
        local size=Vector3.new(s.size.X/10,rng:NextNumber(0.35,0.95),s.size.Z*0.9)
        local cf=s.base*CFrame.new(x,s.size.Y+size.Y*0.15,0)*CFrame.Angles(0,rng:NextNumber(-0.12,0.12),rng:NextNumber(-0.2,0.2))
        table.insert(s.slabs,{part=rock(folder,size,cf,color()),target=cf,size=size,delay=0.07+math.abs(i-5)*0.015})
    end
    for i=1,20 do
        local theta=i*math.pi*2/20
        local localPos=Vector3.new(math.cos(theta)*(s.size.X*0.54),0.15,math.sin(theta)*(s.size.Z*0.5+1.3))
        local size=Vector3.new(rng:NextNumber(0.4,1),rng:NextNumber(0.3,0.65),rng:NextNumber(0.5,1.1))
        local cf=s.base*CFrame.new(localPos)*CFrame.Angles(rng:NextNumber(-0.4,0.4),theta,rng:NextNumber(-0.3,0.3))
        table.insert(s.slabs,{part=rock(folder,size,cf,color()),target=cf,size=size,delay=0})
    end
    for i=1,22 do
        local origin=s.base:PointToWorldSpace(Vector3.new(rng:NextNumber(-s.size.X/2,s.size.X/2),0.2,rng:NextNumber(-s.size.Z,s.size.Z)))
        local size=Vector3.one*rng:NextNumber(0.14,0.45)
        local p=rock(folder,size,CFrame.new(origin),color())
        table.insert(s.chips,{part=p,origin=origin,velocity=s.base:VectorToWorldSpace(Vector3.new(rng:NextNumber(-6,6),rng:NextNumber(10,19),rng:NextNumber(-9,9))),spin=Vector3.new(rng:NextNumber(-8,8),rng:NextNumber(-8,8),rng:NextNumber(-8,8))})
    end
    dust(s,false)
    active[wall]=s
    Debris:AddItem(folder,16)
end
local function watch(wall)
    if wall:IsA("BasePart") and wall.Name=="EarthWall" and not active[wall] then
        -- Hide the server's simple collision block immediately. Its collision and
        -- query behavior remain intact; only the local placeholder is invisible.
        wall.LocalTransparencyModifier=1
        pending[wall]=os.clock()
    end
end
workspace.ChildAdded:Connect(watch)
for _,wall in workspace:GetChildren() do watch(wall) end
RunService.RenderStepped:Connect(function()
    local now=os.clock()
    for wall,born in pending do
        if not wall.Parent or now-born>3 then pending[wall]=nil
        elseif wall:GetAttribute("JutsuId")=="EarthWall" and wall:GetAttribute("TemporaryJutsuObstacle")==true then
            create(wall); pending[wall]=nil
        end
    end
    for wall,s in active do
        local age=now-s.born
        if not wall.Parent and not s.stopped then s.stopped=now; dust(s,true) end
        local ending=s.stopped and math.clamp((now-s.stopped)/0.45,0,1) or 0
        local coreT=math.clamp(age/0.24,0,1)
        local coreGrow=1-(1-coreT)^3
        local visibleHeight=s.size.Y*coreGrow
        s.core.Size=Vector3.new(s.size.X,math.max(0.02,visibleHeight),s.size.Z)
        s.core.CFrame=s.base*CFrame.new(0,visibleHeight/2-ending*ending*s.size.Y,0)
        s.core.Transparency=ending
        for _,v in s.slabs do
            local t=math.clamp((age-v.delay)/0.24,0,1)
            local grow=1-(1-t)^3
            v.part.Size=Vector3.new(v.size.X,math.max(0.02,v.size.Y*grow),v.size.Z)
            v.part.CFrame=v.target+Vector3.new(0,-(1-grow)*v.size.Y/2-ending*ending*1.4,0)
            v.part.Transparency=math.max(1-grow,ending)
        end
        for _,v in s.chips do
            if age<0.65 then
                local pos=v.origin+v.velocity*age+Vector3.new(0,-32*age*age,0)
                v.part.CFrame=CFrame.new(pos)*CFrame.Angles(v.spin.X*age,v.spin.Y*age,v.spin.Z*age)
                v.part.Transparency=math.clamp((age-0.35)/0.3,0,1)
            else v.part.Transparency=1 end
        end
        if (s.stopped and now-s.stopped>1.15) or not s.folder.Parent then
            s.folder:Destroy(); active[wall]=nil
        end
    end
end)
