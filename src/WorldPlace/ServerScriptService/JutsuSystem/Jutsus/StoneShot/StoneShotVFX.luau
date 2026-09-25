--!nonstrict
local Debris=game:GetService("Debris")
local RunService=game:GetService("RunService")
local VFX={}
local rng=Random.new()
local previous=setmetatable({}, {__mode="k"})
local lastGlobal=0
local function stone(parent,size,cf,color,wedge)
    local p=Instance.new(wedge and "WedgePart" or "Part")
    p.Name="StoneFacet"; p.Size=size; p.CFrame=cf; p.Color=color
    p.Material=Enum.Material.Slate; p.Anchored=true
    p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=true
    p.Parent=parent; return p
end
local function moveVisual(root,target)
    local previousCF=root.CFrame
    local delta=target*previousCF:Inverse()
    root.CFrame=target
    for _,child in root:GetChildren() do
        if child:IsA("BasePart") then child.CFrame=delta*child.CFrame end
    end
end
local function dust(parent,rate,size)
    local p=Instance.new("ParticleEmitter")
    p.Texture="rbxasset://textures/particles/smoke_main.dds"
    p.Color=ColorSequence.new(Color3.fromRGB(144,126,104),Color3.fromRGB(92,85,74))
    p.Rate=rate; p.Lifetime=NumberRange.new(0.2,0.45)
    p.Speed=NumberRange.new(1,4); p.SpreadAngle=Vector2.new(180,180)
    p.Drag=4; p.Rotation=NumberRange.new(0,360); p.RotSpeed=NumberRange.new(-70,70)
    p.Size=NumberSequence.new(size,size*2.4)
    p.Transparency=NumberSequence.new(0.78,1); p.Parent=parent; return p
end
function VFX.Create(position,radius,owner)
    local last=owner and previous[owner] or lastGlobal
    local variant=last==0 and rng:NextInteger(1,3) or ((last-1+rng:NextInteger(1,2))%3+1)
    if owner then previous[owner]=variant else lastGlobal=variant end
    local root=stone(nil,Vector3.one*(radius*2),CFrame.new(position),Color3.fromRGB(105,87,67),false)
    root.Name="StoneShot_Rock"; root.Transparency=0
    root:SetAttribute("StoneVariant",variant)
    local palette={Color3.fromRGB(105,87,67),Color3.fromRGB(112,108,97),Color3.fromRGB(123,93,67)}
    local color=palette[variant]
    root.Color=color
    local mesh=Instance.new("SpecialMesh")
    mesh.Name="StoneShape"
    mesh.Parent=root
    if variant==1 then
        mesh.MeshType=Enum.MeshType.Head
        mesh.Scale=Vector3.new(1.15,0.95,1.08)
    elseif variant==2 then
        mesh.MeshType=Enum.MeshType.Brick
        mesh.Scale=Vector3.new(0.82,0.72,1.5)
        root.CFrame*=CFrame.Angles(0.15,0.35,0.45)
    else
        mesh.MeshType=Enum.MeshType.Wedge
        mesh.Scale=Vector3.new(1.25,0.9,1.15)
        root.CFrame*=CFrame.Angles(-0.3,0.2,-0.25)
    end
    local smoke=dust(root,32,radius*0.65)
    for j=1,2 do
        local a=Instance.new("Attachment"); local b=Instance.new("Attachment")
        a.Position=Vector3.new(-radius*0.22,(j==1 and 1 or -1)*radius*0.4,0)
        b.Position=a.Position+Vector3.xAxis*radius*0.44
        a.Parent=root; b.Parent=root
        local trail=Instance.new("Trail")
        trail.Attachment0=a; trail.Attachment1=b; trail.FaceCamera=true
        trail.Lifetime=0.16; trail.MinLength=0.05; trail.Color=ColorSequence.new(color)
        trail.Transparency=NumberSequence.new(0.65,1); trail.WidthScale=NumberSequence.new(1,0)
        trail.Parent=root
    end
    root.Parent=workspace; smoke:Emit(8)
    root:SetAttribute("StoneShotVisual",true)
    return root
end
function VFX.Move(root,target)
    if root and root.Parent then moveVisual(root,target) end
end
function VFX.Impact(position,normal,radius)
    local folder=Instance.new("Folder"); folder.Name="StoneShot_Impact"; folder.Parent=workspace
    local center=stone(folder,Vector3.one*0.1,CFrame.new(position+normal*0.15),Color3.new(),false)
    center.Transparency=1
    local smoke=dust(center,0,radius*1.1)
    smoke.Speed=NumberRange.new(5,13); smoke.Lifetime=NumberRange.new(0.35,0.7); smoke:Emit(28)
    local chunks={}
    local up=math.abs(normal.Y)>0.98 and Vector3.xAxis or Vector3.yAxis
    local cf=CFrame.lookAt(position,position+normal,up)
    for j=1,18 do
        local size=rng:NextNumber(0.13,0.36)*radius
        local p=stone(folder,Vector3.new(size,size*rng:NextNumber(0.6,1.4),size),cf,Color3.fromRGB(110,94,75)*rng:NextNumber(0.8,1.15),j%3==0)
        local angle=j*math.pi*2/18
        local velocity=cf:VectorToWorldSpace(Vector3.new(math.cos(angle)*rng:NextNumber(5,14),math.sin(angle)*rng:NextNumber(5,14),-rng:NextNumber(5,12)))
        table.insert(chunks,{part=p,velocity=velocity,spin=Vector3.new(rng:NextNumber(-9,9),rng:NextNumber(-9,9),rng:NextNumber(-9,9))})
    end
    local born=os.clock()
    local connection
    connection=RunService.Heartbeat:Connect(function()
        local t=os.clock()-born
        if t>0.65 or not folder.Parent then connection:Disconnect(); return end
        for _,c in chunks do
            c.part.CFrame=CFrame.new(position+normal*0.15+c.velocity*t+Vector3.new(0,-26*t*t,0))*CFrame.Angles(c.spin.X*t,c.spin.Y*t,c.spin.Z*t)
            c.part.Transparency=math.clamp((t-0.3)/0.35,0,1)
        end
    end)
    folder.Destroying:Once(function() connection:Disconnect() end)
    Debris:AddItem(folder,0.9)
end
return VFX
