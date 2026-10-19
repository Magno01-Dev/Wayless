-- ServerScriptService > JutsuSystem > Jutsus > DynamicEntry
--
-- Taijutsu · Dynamic Entry (rango C, primera capa).
-- Patada voladora: recorres ~25 studs hacia el retículo. Al primer enemigo que tocas:
-- 12 de daño, lo tumbas lejos (ragdoll) y le cortas los sellos de mano si estaba haciendo
-- un jutsu. Si te bloquea, le quita mucha guardia (40) y lo empuja.
-- Se detiene contra paredes. Gasta stamina.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Taijutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Taijutsu")
)

local Targets = require(game:GetService("ReplicatedStorage"):WaitForChild("Throwables"):WaitForChild("Targets"))

local DynamicEntry = {}

DynamicEntry.Id = "DynamicEntry"
DynamicEntry.TechniqueCategory = "Taijutsu"
DynamicEntry.MinimumLevel = 1
DynamicEntry.SortOrder = 800

DynamicEntry.Config = {
	DisplayName = "Dynamic Entry",
	TechniqueCategory = "Taijutsu",
	MinimumLevel = 1,
	SortOrder = 800,

	StaminaCost = 30,
	Cooldown = 10.0,
	CastTime = 0.3,

	DashSpeed = 85,
	DashTime = 0.3, -- 85 × 0.3 ≈ 25 studs
	HitRadius = 4.5,

	Hit = {
		Damage = 12,
		SourceId = "DynamicEntry",
		GuardDamage = 40,
		BlockedKnockback = 24,
		Heavy = true,
		Ragdoll = { Horizontal = 55, Vertical = 14, Duration = 0.9 },
	},
}

DynamicEntry.MarkerCastTimeout = 4.0
DynamicEntry.ProjectileFallbackDelay = 2.0
DynamicEntry.MinProjectileDelay = 0.05

return Taijutsu.build(DynamicEntry, function(context, forward)
	local config = context.Config
	local player: Player = context.Player
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart

	-- Encara la dirección y sale disparado
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DynamicEntryAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DynamicEntryVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 1e6
	velocity.VectorVelocity = forward * config.DashSpeed + Vector3.yAxis * 4
	velocity.Parent = root

	character:SetAttribute("TaijutsuDashing", true)
	Taijutsu.fxAll("DynamicEntry", { Character = character, Duration = config.DashTime })

	local startedAt = os.clock()
	local previous = root.Position
	local connection: RBXScriptConnection? = nil

	local function finish()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		velocity:Destroy()
		attachment:Destroy()
		if character.Parent then
			character:SetAttribute("TaijutsuDashing", false)
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not character.Parent or not humanoid or humanoid.Health <= 0
			or os.clock() - startedAt >= config.DashTime
			or character:GetAttribute("IsStunned") == true then
			finish()
			return
		end

		local current = root.Position
		-- Pared delante: se detiene
		if Targets.castWorld(current, forward * 3, { character }) then
			finish()
			return
		end

		-- Primer enemigo en el recorrido (segmento previo → actual)
		for _, candidate in Targets.list(character) do
			local bottom, top = Targets.bodySegment(candidate.Root.Position)
			local distance = Targets.segmentDistance(previous, current + forward * 1.5, bottom, top)
			if distance <= config.HitRadius then
				finish()
				local result = Taijutsu.hit(player, candidate.Character, config.Hit)
				if result ~= "Blocked" and result ~= "GuardBreak" and result ~= "Substituted" and result ~= "Invalid" then
					Taijutsu.interrupt(Players:GetPlayerFromCharacter(candidate.Character))
				end
				Taijutsu.fxAll("Impact", { Position = candidate.Root.Position, Heavy = true })
				-- Pequeño rebote hacia atrás del que patea (un LinearVelocity sí mueve a un jugador)
				local bounceAttachment = Instance.new("Attachment")
				bounceAttachment.Parent = root
				local bounce = Instance.new("LinearVelocity")
				bounce.Attachment0 = bounceAttachment
				bounce.RelativeTo = Enum.ActuatorRelativeTo.World
				bounce.MaxForce = 1e6
				bounce.VectorVelocity = -forward * 14 + Vector3.yAxis * 16
				bounce.Parent = root
				task.delay(0.12, function()
					bounce:Destroy()
					bounceAttachment:Destroy()
				end)
				return
			end
		end
		previous = current
	end)
end)
