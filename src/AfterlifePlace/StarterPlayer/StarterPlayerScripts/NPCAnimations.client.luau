local Workspace = game:GetService("Workspace")

--------------------------------------------------
-- CONFIGURACIÓN
--------------------------------------------------

local NPC_NAME = "Hagoromo_R6"

local ANIMATION_ID = "rbxassetid://116652630109159"

--------------------------------------------------
-- BUSCAR NPC
--------------------------------------------------

local NPC = Workspace:WaitForChild(NPC_NAME)

local Humanoid = NPC:WaitForChild("Humanoid")
local Animator = Humanoid:WaitForChild("Animator", 5)

if not Animator then
	Animator = Instance.new("Animator")
	Animator.Parent = Humanoid
end

--------------------------------------------------
-- QUITAR ANIMACIONES EXISTENTES EN ESTE CLIENTE
--------------------------------------------------

for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do
	track:Stop(0)
end

--------------------------------------------------
-- CARGAR ANIMACIÓN
--------------------------------------------------

local Animation = Instance.new("Animation")
Animation.Name = "PermanentNPCAnimation"
Animation.AnimationId = ANIMATION_ID

local Track = Animator:LoadAnimation(Animation)

Track.Looped = true
Track.Priority = Enum.AnimationPriority.Action4

--------------------------------------------------
-- REPRODUCIR
--------------------------------------------------

Track:Play(0, 1, 1)

--------------------------------------------------
-- SEGURIDAD
--------------------------------------------------

Track.Stopped:Connect(function()
	if NPC.Parent and Humanoid.Health > 0 then
		task.defer(function()
			if not Track.IsPlaying then
				Track:Play(0, 1, 1)
			end
		end)
	end
end)