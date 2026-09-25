--!strict
-- ReplicatedStorage > InventoryUISounds
-- WAYLESS Inventory UI sound palette v1
--
-- All sound IDs are intentionally 0 until the final SFX are chosen.
-- Fill only the Id fields; InventoryBandsHUD does not need to be edited again.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local InventoryUISounds = {}

InventoryUISounds.MasterVolume = 0.65
InventoryUISounds.Events = {
	Open = { Id = 0, Volume = 0.52, Speed = 1.00, Jitter = 0.015 },
	Close = { Id = 0, Volume = 0.46, Speed = 0.98, Jitter = 0.015 },
	TooltipOpen = { Id = 0, Volume = 0.24, Speed = 1.03, Jitter = 0.025 },
	ContextOpen = { Id = 0, Volume = 0.32, Speed = 1.00, Jitter = 0.020 },
	BagOpen = { Id = 0, Volume = 0.36, Speed = 1.00, Jitter = 0.020 },
	BagAssign = { Id = 0, Volume = 0.42, Speed = 1.00, Jitter = 0.015 },
	Equip = { Id = 0, Volume = 0.48, Speed = 1.00, Jitter = 0.015 },
	Unequip = { Id = 0, Volume = 0.42, Speed = 0.98, Jitter = 0.015 },
	Lock = { Id = 0, Volume = 0.40, Speed = 1.00, Jitter = 0.010 },
	Unlock = { Id = 0, Volume = 0.38, Speed = 1.03, Jitter = 0.010 },
	Drop = { Id = 0, Volume = 0.42, Speed = 0.98, Jitter = 0.020 },
	Consume = { Id = 0, Volume = 0.44, Speed = 1.00, Jitter = 0.020 },
	Denied = { Id = 0, Volume = 0.40, Speed = 0.94, Jitter = 0.010 },
	LevelUp = { Id = 0, Volume = 0.55, Speed = 1.00, Jitter = 0.000 },
}

local function soundId(id: any): string?
	if typeof(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(math.floor(id))
	end
	if typeof(id) == "string" and id ~= "" and id ~= "0" and id ~= "rbxassetid://0" then
		if string.find(id, "rbxassetid://", 1, true) == 1 then
			return id
		end
		local numeric = tonumber(id)
		if numeric and numeric > 0 then
			return "rbxassetid://" .. tostring(math.floor(numeric))
		end
	end
	return nil
end

function InventoryUISounds.Play(eventName: string): boolean
	local cfg = InventoryUISounds.Events[eventName]
	if not cfg then
		return false
	end

	local id = soundId(cfg.Id)
	if not id then
		return false
	end

	local sound = Instance.new("Sound")
	sound.Name = "WAYLESS_InventoryUI_" .. eventName
	sound.SoundId = id
	sound.Volume = math.clamp((cfg.Volume or 1) * InventoryUISounds.MasterVolume, 0, 10)
	local jitter = math.max(0, cfg.Jitter or 0)
	sound.PlaybackSpeed = math.max(0.05, (cfg.Speed or 1) + ((math.random() * 2 - 1) * jitter))
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.Parent = SoundService
	sound:Play()

	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	Debris:AddItem(sound, 8)
	return true
end

return InventoryUISounds
