local Builder = require(script.Parent.CombatHUDBuilder_v20_ASTRA_STRICT)
local Visuals = require(script.Parent.CombatHUDVisuals_v20)
local Animations = require(script.Parent.HUDAnimationController_v20)

local CombatHUD = {}
CombatHUD.__index = CombatHUD

local SLOT_KEYS = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "G"}

local function buildSlotAssetMap(assetModule)
	return {
		default = assetModule.Slots.default,
		empty = assetModule.Slots.empty,
		fire = assetModule.Slots.fire,
		water = assetModule.Slots.water,
		earth = assetModule.Slots.earth,
		wind = assetModule.Slots.wind,
		lightning = assetModule.Slots.lightning,
		genjutsu = assetModule.Slots.genjutsu,
		healing = assetModule.Slots.healing,
		taijutsu = assetModule.Slots.taijutsu,
		shuriken = assetModule.Slots.shuriken,
		kenjutsu = assetModule.Slots.kenjutsu,
	}
end

function CombatHUD.new(playerGui, assetModule, options)
	assert(playerGui, "playerGui is required")
	assert(type(assetModule) == "table", "assetModule table is required")
	local built = Builder.Build(playerGui, assetModule, options)
	local self = setmetatable({
		ui = built,
		assets = assetModule,
	}, CombatHUD)

	self.visuals = Visuals.new(buildSlotAssetMap(assetModule), options and options.now)
	for _, key in ipairs(SLOT_KEYS) do
		self.visuals:RegisterSlot(key, built.Slots[key])
	end
	self.visuals:BindLifeForce(built.Orb.HitArea, built.Orb.Percent)

	self.anim = Animations.new(built.Bars, built.Orb, built.RenderStates, options)
	return self
end

function CombatHUD:SetSlot(key, item)
	self.visuals:SetSlot(key, item)
end

function CombatHUD:SetCooldown(key, endsAt, duration)
	self.visuals:SetCooldown(key, endsAt, duration)
end

function CombatHUD:SetResource(id, current, maximum)
	self.anim:SetResource(id, current, maximum)
end

function CombatHUD:SetAura(id, active)
	self.anim:SetAura(id, active)
end

function CombatHUD:SetLifeForce(percent)
	self.visuals:SetLifeForce(percent)
	self.anim:SetLifeForce(percent)
end

function CombatHUD:UpsertState(state)
	self.anim:UpsertState(state)
end

function CombatHUD:RemoveState(id)
	self.anim:RemoveState(id)
end

function CombatHUD:Destroy()
	if self.visuals then
		self.visuals:Destroy()
	end
	if self.anim then
		self.anim:Destroy()
	end
	if self.ui and self.ui.Destroy then
		self.ui.Destroy()
	end
end

return CombatHUD
