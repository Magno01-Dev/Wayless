--!strict
-- WAYLESS Weather System v1.0 - third-party Rain module adapter.
-- The legacy module is client-only, sourced from the user-supplied free Toolbox asset.
local Rain = require(script:WaitForChild("RainLegacy"))
local Renderer = {}
local active = false
local initialized = false
local baseVolume = 0.32
local token = 0

function Renderer:Initialize(options)
	if initialized then return end
	initialized = true
	Rain:SetColor(Color3.fromRGB(219, 233, 246))
	Rain:SetDirection(Vector3.new(0, -1, 0))
	Rain:SetCollisionMode(Rain.CollisionMode.Function, function(part)
		-- Ignore invisible, non-collidable props; honor roofs and terrain.
		return part == workspace.Terrain or (part.CanCollide and part.Transparency < 0.93)
	end)
	Rain:SetLightInfluence(0.85)
	Rain:SetIntensityRatio(0)
	baseVolume = options.Volume or 0.32
	Rain:SetVolume(0)
end

function Renderer:SetIntensity(intensity: number, duration: number)
	token += 1
	local thisToken = token
	local target = math.clamp(intensity, 0, 1)
	local fade = math.max(0, duration)
	local tweenInfo = if fade > 0 then TweenInfo.new(fade, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) else nil
	if target > 0 and not active then
		active = true
		Rain:SetIntensityRatio(0)
		Rain:Enable()
	end
	if active then
		Rain:SetIntensityRatio(target, tweenInfo)
		Rain:SetVolume(baseVolume * target, tweenInfo)
		if target == 0 then
			-- Disable only when fade completes; cancel stale disable after rapid border crossings.
			task.delay(fade + 0.05, function()
				if thisToken == token and active then
					active = false
					Rain:Disable()
				end
			end)
		end
	end
end

return Renderer
