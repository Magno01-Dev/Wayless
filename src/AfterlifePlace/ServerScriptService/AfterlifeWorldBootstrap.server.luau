--!strict
-- ServerScriptService > AfterlifeWorldBootstrap (dedicated Afterlife Place)
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local room = Workspace:WaitForChild("WAYLESS_Afterlife", 30)
if not room or not room:IsA("Model") then
	warn("[Afterlife] Import WAYLESS_Afterlife.rbxmx into Workspace")
	return
end
local floor = room:FindFirstChild("Floor")
local anchor = room:FindFirstChild("HagoromoAnchor")
local arrival = room:FindFirstChild("ArrivalMarker")
if not floor or not floor:IsA("BasePart") or not anchor or not anchor:IsA("BasePart") or not arrival or not arrival:IsA("BasePart") then
	warn("[Afterlife] Missing Floor, HagoromoAnchor or ArrivalMarker")
	return
end
room.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
-- Remove only the old known QA scene. The imported final model is authoritative.
local old = Workspace:FindFirstChild("AfterlifeScene")
if old and old:FindFirstChild("ReflectiveWater") and old:FindFirstChild("AfterlifeGuide") then old:Destroy() end
Lighting.Brightness=0
Lighting.ClockTime=0
Lighting.Ambient=Color3.fromRGB(34,38,27)
Lighting.OutdoorAmbient=Color3.fromRGB(26,30,21)
Lighting.EnvironmentDiffuseScale=0
Lighting.EnvironmentSpecularScale=0
Lighting.ExposureCompensation=0
Lighting.ColorShift_Top=Color3.new()
Lighting.ColorShift_Bottom=Color3.new()
Lighting.FogColor=Color3.fromRGB(9,12,6)
Lighting.FogStart=18
Lighting.FogEnd=85
-- Lift the surface from absolute black so local light can reveal it.
floor.Color=Color3.fromRGB(29,33,20)
floor.Material=Enum.Material.SmoothPlastic
floor.Reflectance=0
floor.Transparency=0
local lightAnchor=room:FindFirstChild("LightAnchor")
if lightAnchor and lightAnchor:IsA("BasePart") then
	local light=lightAnchor:FindFirstChildOfClass("PointLight")
	if light then
		light.Color=Color3.fromRGB(213,224,176)
		light.Brightness=1.8
		light.Range=30
		light.Shadows=false
	end
end
-- Park atmospheres without destroying them; they override distance fog.
local parked=Instance.new("Folder")
parked.Name="OriginalLighting"
parked.Parent=script
for _,effect in ipairs(Lighting:GetChildren()) do
	if effect:IsA("Atmosphere") or effect:IsA("PostEffect") then effect.Parent=parked end
end
local attachment=anchor:FindFirstChild("DialogueAttachment")
if not attachment or not attachment:IsA("Attachment") then
	attachment=Instance.new("Attachment")
	attachment.Name="DialogueAttachment"
	attachment.Parent=anchor
end
local att=attachment :: Attachment
att.Position=Vector3.new(0,3,0)
local oldPrompt=att:FindFirstChild("AfterlifePrompt")
if oldPrompt then oldPrompt:Destroy() end
local prompt=Instance.new("ProximityPrompt")
prompt.Name="AfterlifePrompt"
prompt.ActionText="Hablar"
prompt.ObjectText="Hagoromo"
prompt.KeyboardKeyCode=Enum.KeyCode.E
prompt.MaxActivationDistance=12
prompt.RequiresLineOfSight=false
prompt.HoldDuration=0
prompt.Parent=att
local spawn=room:FindFirstChild("AfterlifeSpawn")
if not spawn or not spawn:IsA("SpawnLocation") then
	spawn=Instance.new("SpawnLocation")
	spawn.Name="AfterlifeSpawn"
	spawn.Parent=room
end
local destination=spawn :: SpawnLocation
destination.Anchored=true
destination.Transparency=1
destination.CanCollide=false
destination.Neutral=true
destination.Enabled=true
destination.Duration=0
destination.Size=Vector3.new(4,1,4)
destination.Position=Vector3.new(arrival.Position.X,floor.Position.Y+floor.Size.Y/2+.5,arrival.Position.Z)
local function placeCharacter(character: Model)
	local root=character:WaitForChild("HumanoidRootPart",10)
	if not root or not root:IsA("BasePart") then return end
	local position=destination.Position+Vector3.new(0,3,0)
	character:PivotTo(CFrame.lookAt(position,Vector3.new(anchor.Position.X,position.Y,anchor.Position.Z)))
	root.AssemblyLinearVelocity=Vector3.zero
end
local function bind(player: Player)
	player.RespawnLocation=destination
	player.CharacterAdded:Connect(placeCharacter)
	if player.Character then task.spawn(placeCharacter,player.Character) end
end
Players.PlayerAdded:Connect(bind)
for _,player in ipairs(Players:GetPlayers()) do bind(player) end
print("[AfterlifeWorldBootstrap] Imported room ready | E interaction | Dedicated lighting")
