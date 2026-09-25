-- Strictly based on Astra's Combat HUD v20 slot rules.
local RunService = game:GetService("RunService")

local Visuals = {}
Visuals.__index = Visuals

local valid = {
	lightning = true,
	fire = true,
	water = true,
	earth = true,
	wind = true,
	genjutsu = true,
	healing = true,
	taijutsu = true,
	shuriken = true,
	kenjutsu = true,
}

local function normalize(value)
	if type(value) ~= "string" then
		return nil
	end
	local key = string.lower(value)
	if key == "lighting" then
		key = "lightning"
	end
	return valid[key] and key or nil
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Visuals.ResolveFrame(item)
	if item == nil then
		return "empty"
	end
	if item.kind ~= "ability" then
		return "default"
	end
	return normalize(item.frameType) or normalize(item.element) or normalize(item.jutsuType) or "default"
end

function Visuals.new(assets, now)
	local self = setmetatable({
		assets = assets,
		slots = {},
		connections = {},
		now = now or function()
			return workspace:GetServerTimeNow()
		end,
	}, Visuals)
	self.step = RunService.RenderStepped:Connect(function()
		self:Update()
	end)
	return self
end

function Visuals:RegisterSlot(key, view)
	assert(view.FrameImage and view.ItemImage and view.Shade and view.Timer and view.KeyLabel, "Missing slot visual layer")
	self.slots[key] = { view = view }
	view.Shade.BackgroundColor3 = Color3.new(0, 0, 0)
	view.Shade.BorderSizePixel = 0
	view.Shade.Visible = false
	view.Timer.Visible = false
	self:SetSlot(key, nil)
end

function Visuals:SetSlot(key, item)
	local slot = assert(self.slots[key], "Register slot first")
	slot.item = item
	local frame = Visuals.ResolveFrame(item)
	local uri = self.assets[frame] or self.assets.default
	assert(type(uri) == "string" and uri ~= "", "Upload and map the slot frame assets first")
	local view = slot.view
	view.FrameImage.Image = uri
	view.FrameImage.ScaleType = Enum.ScaleType.Stretch
	view.ItemImage.ScaleType = Enum.ScaleType.Fit
	view.ItemImage.Image = if item and type(item.icon) == "string" then item.icon else ""
	view.ItemImage.Visible = item ~= nil and view.ItemImage.Image ~= ""
	slot.endsAt, slot.duration = nil, nil
	view.Shade.Visible, view.Timer.Visible = false, false
end

function Visuals:SetCooldown(key, endsAt, duration)
	local slot = assert(self.slots[key], "Register slot first")
	if slot.item == nil or not finite(endsAt) or not finite(duration) or duration <= 0 then
		slot.endsAt, slot.duration = nil, nil
		slot.view.Shade.Visible, slot.view.Timer.Visible = false, false
		return
	end
	slot.endsAt, slot.duration = endsAt, duration
	self:Update()
end

function Visuals:Update()
	local now = self.now()
	for _, slot in pairs(self.slots) do
		local remaining = if slot.endsAt then math.max(0, slot.endsAt - now) else 0
		local active = remaining > 0 and slot.item ~= nil
		slot.view.Shade.Visible = active
		slot.view.Timer.Visible = active
		if active then
			local ratio = math.clamp(remaining / slot.duration, 0, 1)
			slot.view.Shade.BackgroundTransparency = 1 - 0.78 * ratio
			slot.view.Timer.Text = tostring(math.ceil(remaining)) .. "s"
		else
			slot.endsAt, slot.duration = nil, nil
		end
	end
end

function Visuals:BindLifeForce(hitArea, percentageLabel)
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	self.percentageLabel = percentageLabel
	percentageLabel.Visible = false
	table.insert(self.connections, hitArea.MouseEnter:Connect(function()
		percentageLabel.Visible = true
	end))
	table.insert(self.connections, hitArea.MouseLeave:Connect(function()
		percentageLabel.Visible = false
	end))
end

function Visuals:SetLifeForce(value)
	local percent = if finite(value) then math.clamp(value, 0, 100) else 0
	if self.percentageLabel then
		self.percentageLabel.Text = string.format("%d%%", math.floor(percent + 0.5))
	end
end

function Visuals:Destroy()
	if self.step then
		self.step:Disconnect()
	end
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.slots)
end

return Visuals
