-- ModuleScript beside AfterlifeController in StarterPlayerScripts.
local Effects = {}
local started = false
function Effects.Start()
	if started then return end
	started=true
	-- Started by AfterlifeController; lighting is owned by WorldBootstrap.
	-- No uploaded images required. Only activates inside the imported room.
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")

	local TweenService = game:GetService("TweenService")
	local player = Players.LocalPlayer
	local room = workspace:WaitForChild("WAYLESS_Afterlife")
	local floor = room:WaitForChild("Floor")
	local anchor = room:WaitForChild("HagoromoAnchor")
	local effects = Instance.new("Folder")
	effects.Name = "AfterlifeLocalEffects"
	effects.Parent = workspace
	-- Local soft fill: follows this player, revealing only nearby ground and clothing.
	local fillPart=Instance.new("Part")
	fillPart.Name="PlayerSoftFill"
	fillPart.Size=Vector3.one
	fillPart.Anchored=true
	fillPart.Transparency=1
	fillPart.CanCollide=false
	fillPart.CanTouch=false
	fillPart.CanQuery=false
	fillPart.Parent=effects
	local fill=Instance.new("PointLight")
	fill.Name="PersonalPenumbra"
	fill.Color=Color3.fromRGB(203,216,164)
	fill.Brightness=1.35
	fill.Range=17
	fill.Shadows=false
	fill.Enabled=false
	fill.Parent=fillPart
	local active = false
	local rings, steps, pulse = {}, {}, 0
	local function inside(position)
		local p = floor.CFrame:PointToObjectSpace(position)
		return math.abs(p.X)<124 and math.abs(p.Z)<124 and p.Y>0 and p.Y<65
	end
	local function enter() active=true; fill.Enabled=true end
	local function leave()
		active=false
		fill.Enabled=false
		table.clear(steps)
		for _,p in ipairs(rings) do p:Destroy() end
		table.clear(rings); pulse=0
	end
	local function ripple(position, diameter, duration, alpha)
		if #rings>=40 then return end
		local p=Instance.new("Part")
		p.Name="WaterRing"; p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
		p.Transparency=1; p.Size=Vector3.new(.5,.01,.5)
		p.CFrame=CFrame.new(position); p.Parent=effects
		local gui=Instance.new("SurfaceGui")
		gui.Face=Enum.NormalId.Top; gui.CanvasSize=Vector2.new(256,256)
		gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.LightInfluence=0; gui.AlwaysOnTop=false; gui.MaxDistance=120; gui.Parent=p
		local circle=Instance.new("Frame")
		circle.Size=UDim2.fromScale(.9,.9); circle.Position=UDim2.fromScale(.05,.05)
		circle.BackgroundTransparency=1; circle.BorderSizePixel=0; circle.Parent=gui
		local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(.5,0); corner.Parent=circle
		local stroke=Instance.new("UIStroke")
		stroke.Color=Color3.fromRGB(183,196,132); stroke.Thickness=2
		stroke.Transparency=alpha; stroke.Parent=circle
		table.insert(rings,p)
		local t=TweenService:Create(p,TweenInfo.new(duration,Enum.EasingStyle.Linear),{Size=Vector3.new(diameter,.01,diameter)})
		TweenService:Create(stroke,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Transparency=1}):Play()
		t.Completed:Once(function()
			local i=table.find(rings,p); if i then table.remove(rings,i) end
			p:Destroy()
		end)
		t:Play()
	end
	local cast=RaycastParams.new(); cast.FilterType=Enum.RaycastFilterType.Include; cast.FilterDescendantsInstances={floor}
	local tickTime=0
	RunService.Heartbeat:Connect(function(dt)
		tickTime+=dt; if tickTime<.05 then return end
		local elapsed=math.min(tickTime,.15); tickTime=0
		local char=player.Character
		local root=char and char:FindFirstChild("HumanoidRootPart")
		local wanted=root and inside(root.Position) or false
		if wanted and not active then enter() elseif not wanted and active then leave() end
		if not active then return end
		local camera=workspace.CurrentCamera
		local toCamera=camera and (camera.CFrame.Position-root.Position) or Vector3.new(0,0,1)
		local horizontal=Vector3.new(toCamera.X,0,toCamera.Z)
		if horizontal.Magnitude>.01 then horizontal=horizontal.Unit else horizontal=Vector3.new(0,0,1) end
		fillPart.Position=root.Position+Vector3.new(0,2.5,0)+horizontal*3
		pulse-=elapsed
		if pulse<=0 then
			pulse=1.5
			ripple(Vector3.new(anchor.Position.X,floor.Position.Y+floor.Size.Y/2+.025,anchor.Position.Z),22,5,.25)
		end
		-- Alternating distance-based footsteps: supports R6 without editing animations.
		for _,other in ipairs(Players:GetPlayers()) do
			local c=other.Character; local r=c and c:FindFirstChild("HumanoidRootPart")
			local h=c and c:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health>0 and inside(r.Position) and (r.Position-root.Position).Magnitude<65 then
				local state=steps[other] or {pos=r.Position,distance=0,side=1}; steps[other]=state
				local delta=r.Position-state.pos; state.pos=r.Position
				local distance=Vector3.new(delta.X,0,delta.Z).Magnitude
				if h.FloorMaterial~=Enum.Material.Air and distance<5 then
					state.distance+=distance
					if state.distance>=2.8 then
						state.distance=0; state.side=-state.side
						local from=r.Position+r.CFrame.RightVector*(state.side*.48)
						local hit=workspace:Raycast(from,Vector3.new(0,-7,0),cast)
						if hit then
							local near=math.clamp(1-(hit.Position-anchor.Position).Magnitude/55,0,1)
							ripple(hit.Position+Vector3.new(0,.025,0),4.8,2.1,.48-near*.12)
						end
					end
				else state.distance=0 end
			else steps[other]=nil end
		end
	end)
	script.Destroying:Connect(function() if active then leave() end; effects:Destroy() end)

end
return Effects
