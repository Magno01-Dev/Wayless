--[[
	TreeJump.Indicator · ModuleScript en ReplicatedStorage.TreeJump
	Marcador de objetivo (BillboardGui). Visual solamente: el controlador decide qué mostrar,
	así el marcador siempre es exactamente el destino del salto.

		local marker = Indicator.new(playerGui, { Name = "...", Size = 52, Transparency = 0.2, Spin = true })
		marker:Show(zone, worldPoint)
		marker:Hide()
		marker:Destroy()
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent:WaitForChild("Config"))

local Indicator = {}
Indicator.__index = Indicator

function Indicator.new(parent, options)
	local self = setmetatable({}, Indicator)
	self.Options = options
	self.Zone = nil
	self.FadingOut = false
	self.Generation = 0
	self.Tweens = {}

	local gui = Instance.new("BillboardGui")
	gui.Name = options.Name
	gui.Size = UDim2.fromOffset(options.Size, options.Size)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = Config.MaxDistance + 50
	gui.ResetOnSpawn = true
	gui.Enabled = false
	gui.Parent = parent

	local ring = Instance.new("ImageLabel")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Image = Config.IndicatorImage
	ring.ImageTransparency = 1
	ring.ScaleType = Enum.ScaleType.Fit
	ring.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = ring

	self.Gui = gui
	self.Ring = ring
	self.Scale = scale
	return self
end

function Indicator:_cancelTweens()
	for _, tween in self.Tweens do
		tween:Cancel()
	end
	table.clear(self.Tweens)
end

function Indicator:_play(instance, time, goal, style)
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	table.insert(self.Tweens, tween)
	tween:Play()
end

function Indicator:_startAnimation()
	if self.Animation then
		return
	end
	local pulseTime = 0
	self.Animation = RunService.RenderStepped:Connect(function(dt)
		if self.Options.Spin then
			self.Ring.Rotation = (self.Ring.Rotation + Config.IndicatorSpinSpeed * dt) % 360
		end
		pulseTime += dt * Config.IndicatorPulseSpeed * math.pi * 2
		if #self.Tweens == 0 or self.Tweens[#self.Tweens].PlaybackState ~= Enum.PlaybackState.Playing then
			self.Scale.Scale = 1 + math.sin(pulseTime) * Config.IndicatorPulseAmount
		end
	end)
end

function Indicator:_stopAnimation()
	if self.Animation then
		self.Animation:Disconnect()
		self.Animation = nil
	end
	self.Scale.Scale = 1
	self.Ring.Rotation = 0
end

function Indicator:Show(zone, point)
	local changed = self.Zone ~= zone
	local wasHidden = not self.Gui.Enabled or self.FadingOut
	self.Zone = zone
	self.Gui.Adornee = zone
	self.Gui.StudsOffsetWorldSpace = point - zone.Position + Vector3.yAxis * 0.2

	if wasHidden or changed then
		self.Generation += 1
		self.FadingOut = false
		self.Gui.Enabled = true
		self:_cancelTweens()
		self.Ring.ImageTransparency = 1
		self.Scale.Scale = Config.IndicatorPopScale
		self:_play(self.Ring, Config.IndicatorFadeIn, { ImageTransparency = self.Options.Transparency })
		self:_play(self.Scale, Config.IndicatorPopTime, { Scale = 1 }, Enum.EasingStyle.Back)
		self:_startAnimation()
	end
end

function Indicator:Hide()
	if not self.Gui.Enabled or self.FadingOut then
		return
	end
	self.FadingOut = true
	self.Generation += 1
	local generation = self.Generation
	self:_cancelTweens()
	self:_play(self.Ring, Config.IndicatorFadeOut, { ImageTransparency = 1 })
	task.delay(Config.IndicatorFadeOut, function()
		if generation ~= self.Generation then
			return
		end
		self.FadingOut = false
		self.Gui.Enabled = false
		self.Gui.Adornee = nil
		self.Zone = nil
		self:_stopAnimation()
	end)
end

function Indicator:Destroy()
	self.Generation += 1
	self:_cancelTweens()
	self:_stopAnimation()
	self.Gui:Destroy()
end

return Indicator
