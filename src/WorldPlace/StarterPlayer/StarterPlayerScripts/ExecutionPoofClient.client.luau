--!strict
-- ExecutionPoofClient v1
-- StarterPlayer > StarterPlayerScripts > ExecutionPoofClient
--
-- Persistent client-side VFX/SFX for executed-character disappearance.
-- It survives respawns, so the poof can still render while the victim's old
-- Character is dead/in the middle of being replaced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local remotes = ReplicatedStorage:WaitForChild("DownedRemotes")
local executionPoofFX = remotes:WaitForChild("ExecutionPoofFX") :: RemoteEvent

local POOF_SOUND_ID = "rbxassetid://90296139665102"
local POOF_VOLUME = 1.0
local OUTER_PARTICLE_COUNT = 36
local CORE_PARTICLE_COUNT = 24

local function makeSmokeEmitter(name: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-80, 80)
	emitter.Drag = 2.5
	emitter.LightInfluence = 0.15
	emitter.LightEmission = 0.05
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 250)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(225, 225, 225)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 170)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.03),
		NumberSequenceKeypoint.new(0.35, 0.18),
		NumberSequenceKeypoint.new(0.72, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	return emitter
end

local function createPoof(cframe: CFrame)
	local anchor = Instance.new("Part")
	anchor.Name = "ExecutionPoofClientFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.CFrame = cframe
	anchor.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Name = "PoofAttachment"
	attachment.Parent = anchor

	local outer = makeSmokeEmitter("ExecutionSmokeOuter")
	outer.Lifetime = NumberRange.new(0.55, 0.90)
	outer.Speed = NumberRange.new(5.5, 10.5)
	outer.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.22, 3.0),
		NumberSequenceKeypoint.new(0.65, 4.7),
		NumberSequenceKeypoint.new(1, 5.8),
	})
	outer.Parent = attachment

	local core = makeSmokeEmitter("ExecutionSmokeCore")
	core.Lifetime = NumberRange.new(0.35, 0.62)
	core.Speed = NumberRange.new(2.5, 6.0)
	core.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(0.40, 2.8),
		NumberSequenceKeypoint.new(1, 4.0),
	})
	core.Parent = attachment

	local sound = Instance.new("Sound")
	sound.Name = "ExecutionPoofSound"
	sound.SoundId = POOF_SOUND_ID
	sound.Volume = POOF_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 75
	sound.Parent = anchor

	sound:Play()
	outer:Emit(OUTER_PARTICLE_COUNT)
	core:Emit(CORE_PARTICLE_COUNT)

	Debris:AddItem(anchor, 3)
end

executionPoofFX.OnClientEvent:Connect(function(cframe: CFrame)
	if typeof(cframe) ~= "CFrame" then
		return
	end

	createPoof(cframe)
end)

print("[ExecutionPoofClient] ready")
