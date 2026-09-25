-- Strictly based on Astra's Combat HUD v20 animation notes.
local RunService = game:GetService("RunService")

local Controller = {}
Controller.__index = Controller

local function number(v, fallback)
	return if type(v) == "number" and v == v and math.abs(v) < math.huge then v else fallback
end

function Controller.new(bars, orb, renderStates, options)
	options = options or {}
	local self = setmetatable({
		bars = bars,
		orb = orb,
		renderStates = renderStates,
		states = {},
		values = {},
		now = options.now or function()
			return workspace:GetServerTimeNow()
		end,
		reducedMotion = options.reducedMotion == true,
		sequence = 0,
		clock = 0,
		lastStateRender = 0,
	}, Controller)

	if orb and orb.Flame then
		orb.Flame.ImageRectSize = Vector2.new(256, 256)
		self.flameSize = orb.Flame.Size
	end

	self.hoverConnections = {}
	self.fireHover = 0
	self.orbHover = false
	if orb and orb.HitArea then
		table.insert(self.hoverConnections, orb.HitArea.MouseEnter:Connect(function()
			self.orbHover = true
		end))
		table.insert(self.hoverConnections, orb.HitArea.MouseLeave:Connect(function()
			self.orbHover = false
		end))
	end
	if orb and orb.Flame then
		orb.Flame.ImageTransparency = 1
	end

	self.connection = RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
	return self
end

function Controller:SetResource(id, current, maximum)
	local view = assert(self.bars[id], "Unknown resource")
	maximum = math.max(0, number(maximum, 0))
	current = math.clamp(number(current, 0), 0, maximum)
	local ratio = if maximum > 0 then current / maximum else 0
	local v = self.values[id]
	if not v then
		v = { value = ratio, trail = ratio, target = ratio, current = current, maximum = maximum }
		self.values[id] = v
	end
	if ratio < v.target then
		v.delay = self.now() + 0.35
	end
	v.target = ratio
	v.current = current
	v.maximum = maximum
end

function Controller:SetAura(id, active)
	local v = self.values[id]
	if v then
		if v.aura and active ~= true then
			v.auraEnded = self.now()
		end
		v.aura = active == true
	end
end

function Controller:SetLifeForce(percent)
	self.lifeForce = math.clamp(number(percent, 0), 0, 100) / 100
	if self.orb and self.orb.Percent then
		self.orb.Percent.Text = string.format("%d%%", math.floor(self.lifeForce * 100 + .5))
	end
end

function Controller:UpsertState(state)
	assert(type(state.id) == "string", "State needs stable instance id")
	assert(state.kind == "benefit" or state.kind == "negative", "Invalid state kind")
	local previous = self.states[state.id]
	self.sequence += 1
	self.states[state.id] = {
		id = state.id,
		kind = state.kind,
		name = state.name or state.id,
		description = state.description or "",
		icon = state.icon or "",
		stacks = math.max(1, math.floor(number(state.stacks, 1))),
		endsAt = if type(state.endsAt) == "number" then number(state.endsAt, nil) else nil,
		priority = number(state.priority, 0),
		sequence = if previous then previous.sequence else self.sequence,
	}
	self.lastStateRender = 0
end

function Controller:RemoveState(id)
	self.states[id] = nil
	self.lastStateRender = 0
end

function Controller:Update(dt)
	dt = math.min(number(dt, 0), .1)
	self.clock += dt
	local now = self.now()

	for id, v in pairs(self.values) do
		local view = self.bars[id]
		local ease = if self.reducedMotion then 1 else 1 - math.exp(-dt * 14)
		v.value += (v.target - v.value) * ease
		if v.trail < v.value then
			v.trail = v.value
		end
		if now >= (v.delay or 0) then
			v.trail += (v.value - v.trail) * (if self.reducedMotion then 1 else 1 - math.exp(-dt * 5))
		end
		if id == "health" then
			view.Clip.AnchorPoint = Vector2.new(1, view.Clip.AnchorPoint.Y)
			view.Clip.Position = UDim2.new(1, 0, view.Clip.Position.Y.Scale, view.Clip.Position.Y.Offset)
			if view.TrailClip then
				view.TrailClip.AnchorPoint = Vector2.new(1, view.TrailClip.AnchorPoint.Y)
				view.TrailClip.Position = UDim2.new(1, 0, view.TrailClip.Position.Y.Scale, view.TrailClip.Position.Y.Offset)
			end
		end
		view.Clip.Size = UDim2.new(v.value, 0, view.Clip.Size.Y.Scale, view.Clip.Size.Y.Offset)
		if view.TrailClip then
			view.TrailClip.Size = UDim2.new(v.trail, 0, view.TrailClip.Size.Y.Scale, view.TrailClip.Size.Y.Offset)
		end
		if view.Label then
			view.Label.Text = string.format("%d / %d", math.floor(v.current + .5), math.floor(v.maximum + .5))
		end
		local glow = if v.aura then 1 else (if v.auraEnded then math.clamp(1 - (now - v.auraEnded) / .65, 0, 1) else 0)
		if view.Aura then
			view.Aura.ImageTransparency = 1 - glow * (.4 + (if self.reducedMotion then 0 else .16 * math.sin(self.clock * 6.6)))
		end
		if view.OuterAura then
			view.OuterAura.ImageTransparency = 1 - glow * (.58 + (if self.reducedMotion then 0 else .12 * math.sin(self.clock * 5.5)))
		end
		if view.TrailImage then
			local shades = {
				health = Color3.fromRGB(101, 27, 34),
				chakra = Color3.fromRGB(23, 62, 100),
				armor = Color3.fromRGB(68, 73, 78),
				stamina = Color3.fromRGB(112, 80, 31),
			}
			view.TrailImage.ImageColor3 = shades[id] or Color3.new(1, 1, 1)
		end
	end

	if self.orb then
		local p = self.lifeForce or 0
		if self.orb.Energy then
			self.orb.Energy.ImageTransparency = 1 - p
		end
		if self.orb.EnergyClip then
			self.orb.EnergyClip.Size = UDim2.fromScale(1, 1)
		end
		local f = self.orb.Flame
		if f then
			local index = if self.reducedMotion then 0 else math.floor(self.clock * 11.11) % 8
			f.ImageRectOffset = Vector2.new(index % 4 * 256, math.floor(index / 4) * 256)
			self.fireHover = math.clamp(self.fireHover + (if self.orbHover then dt / .18 else -dt / .25), 0, 1)
			f.Visible = p > 0 and self.fireHover > 0
			f.ImageTransparency = 1 - p * self.fireHover
			local centers = {
				Vector2.new(129, 140), Vector2.new(129, 140), Vector2.new(127, 140), Vector2.new(127, 140),
				Vector2.new(129, 139), Vector2.new(129, 139), Vector2.new(127, 139), Vector2.new(127, 139),
			}
			f.AnchorPoint = centers[index + 1] / 256
		end
	end

	if self.renderStates and now - self.lastStateRender >= .1 then
		self.lastStateRender = now
		local list = {}
		for id, s in pairs(self.states) do
			if s.endsAt and s.endsAt <= now then
				self.states[id] = nil
			else
				local copy = table.clone(s)
				copy.remaining = if s.endsAt then math.max(0, s.endsAt - now) else nil
				table.insert(list, copy)
			end
		end
		table.sort(list, function(a, b)
			return a.sequence > b.sequence
		end)
		self.renderStates(list)
	end
end

function Controller:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end
	for _, connection in ipairs(self.hoverConnections) do
		connection:Disconnect()
	end
	table.clear(self.states)
end

return Controller
