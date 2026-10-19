-- ServerScriptService > JutsuSystem > Jutsus > Kagemane
--
-- Clan Nara · Kagemane no Jutsu (etapa 1 · Despertar). Posesión de sombra.
-- Tu sombra sale por el suelo hacia el retículo (45 studs/s, hasta 28 studs). Si toca a
-- alguien que tenga los pies en el suelo, queda atrapado 1.5 s:
--   - no puede moverse por su cuenta ni atacar (estado ShadowBound);
--   - IMITA TU MOVIMIENTO: si caminas, él camina lo mismo (llévalo a tus minas o abrojos);
--   - tú tampoco puedes atacar mientras lo sostienes (ShadowHolding);
--   - si estaba haciendo sellos de mano, su jutsu falla.
-- La sombra no cruza huecos ni agua, se corta contra paredes y no atrapa a quien está
-- saltando. Se suelta si te golpean (3 o más de daño) o si se alejan demasiado.
-- 1 sello.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)

local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))
local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))

local Kagemane = {}

Kagemane.Id = "Kagemane"
Kagemane.TechniqueCategory = "Clan"
Kagemane.MinimumLevel = 1
Kagemane.SortOrder = 1130

Kagemane.Config = {
	DisplayName = "Kagemane no Jutsu",
	TechniqueCategory = "Clan",
	MinimumLevel = 1,
	SortOrder = 1130,

	ChakraCost = 18,
	Cooldown = 14.0,
	CastTime = 0.4,

	Speed = 45,
	Range = 28,
	CatchRadius = 2.8,
	HoldTime = 1.5,
	GroundedHeight = 3.8, -- distancia máx. del HumanoidRootPart al suelo para "tener los pies en el suelo"
	BreakDamage = 3,
	MaxLeash = 40,
}

Kagemane.MarkerCastTimeout = 4.0
Kagemane.ProjectileFallbackDelay = 1.5
Kagemane.MinProjectileDelay = 0

local function groundAt(position: Vector3, ignore: {Instance}): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false
	params.FilterDescendantsInstances = ignore
	-- Targets.castWorld ignora personajes y partes sin colisión; aquí además queremos ver el agua
	local water = workspace:Raycast(position + Vector3.yAxis * 3, Vector3.yAxis * -8, params)
	if water and water.Material == Enum.Material.Water then
		return nil
	end
	return Targets.castWorld(position + Vector3.yAxis * 3, Vector3.yAxis * -8, ignore)
end

local function isGrounded(character: Model, height: number): boolean
	local root = character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and Targets.castWorld(root.Position, Vector3.yAxis * -height, { character }) ~= nil
end

local interruptCast: BindableFunction? = nil
local function interrupt(player: Player?)
	if not player then
		return
	end
	if not interruptCast then
		local folder = ServerStorage:FindFirstChild("JutsuInternal")
		local found = folder and folder:FindFirstChild("InterruptCast")
		interruptCast = if found and found:IsA("BindableFunction") then found else nil
	end
	if interruptCast then
		pcall(function()
			(interruptCast :: BindableFunction):Invoke(player)
		end)
	end
end

local sequence = 0

-- Sostener al atrapado: imita el desplazamiento del Nara
local function hold(context: any, target: any, id: number)
	local config = context.Config
	local caster: Model = context.Character
	local casterRoot = caster:FindFirstChild("HumanoidRootPart") :: BasePart
	local casterHumanoid = caster:FindFirstChildOfClass("Humanoid") :: Humanoid
	local targetRoot: BasePart = target.Root

	Clan.applyStatus(target.Character, "ShadowBound", { Duration = config.HoldTime, SourcePlayer = context.Player })
	Clan.applyStatus(caster, "ShadowHolding", { Duration = config.HoldTime })
	interrupt(Players:GetPlayerFromCharacter(target.Character))
	Clan.fxAll("ShadowCapture", { Character = caster, Target = target.Character, Id = id, Duration = config.HoldTime })

	-- AlignPosition creado por el servidor: sí mueve a un personaje controlado por su cliente
	local attachment = Instance.new("Attachment")
	attachment.Name = "KagemaneAttachment"
	attachment.Parent = targetRoot
	local align = Instance.new("AlignPosition")
	align.Name = "KagemaneAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = 1e6
	align.Responsiveness = 40
	align.ApplyAtCenterOfMass = true
	align.Position = targetRoot.Position
	align.Parent = targetRoot

	local casterStart = casterRoot.Position
	local targetStart = targetRoot.Position
	local lastHealth = casterHumanoid.Health
	local startedAt = os.clock()
	local connection: RBXScriptConnection? = nil

	local function release(reason: string)
		if connection then
			connection:Disconnect()
			connection = nil
		end
		align:Destroy()
		attachment:Destroy()
		for _, pair in { { target.Character, "ShadowBound" }, { caster, "ShadowHolding" } } do
			local character, statusId = pair[1], pair[2]
			if character.Parent and StatusEffectService.Has(character, statusId) then
				StatusEffectService.Remove(character, statusId, "Kagemane")
			end
		end
		Clan.fxAll("ShadowEnd", { Id = id, Reason = reason })
	end

	connection = RunService.Heartbeat:Connect(function()
		if os.clock() - startedAt >= config.HoldTime then
			release("Done")
			return
		end
		if not caster.Parent or not target.Character.Parent or casterHumanoid.Health <= 0
			or target.Humanoid.Health <= 0 or not targetRoot.Parent then
			release("Lost")
			return
		end
		if casterHumanoid.Health < lastHealth - config.BreakDamage + 0.01 then
			release("Hit")
			return
		end
		lastHealth = math.max(lastHealth, casterHumanoid.Health)
		if (casterRoot.Position - targetRoot.Position).Magnitude > config.MaxLeash then
			release("Leash")
			return
		end
		local moved = casterRoot.Position - casterStart
		align.Position = Vector3.new(targetStart.X + moved.X, targetRoot.Position.Y, targetStart.Z + moved.Z)
	end)
end

return Clan.build(Kagemane, "Nara", function(context, direction)
	local config = context.Config
	local caster: Model = context.Character
	local casterRoot = caster:FindFirstChild("HumanoidRootPart") :: BasePart
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(casterRoot.CFrame.LookVector.X, 0, casterRoot.CFrame.LookVector.Z).Unit

	local startGround = groundAt(casterRoot.Position, { caster })
	if not startGround then
		Clan.fxTo(context.Player, "Notice", { Text = "NO HAY SUELO PARA TU SOMBRA" })
		return
	end

	sequence += 1
	local id = sequence
	Clan.fxAll("ShadowStart", { Character = caster, Id = id, Direction = flat, Speed = config.Speed, Range = config.Range })

	local tip = startGround.Position
	local travelled = 0
	local connection: RBXScriptConnection? = nil

	connection = RunService.Heartbeat:Connect(function(dt)
		if not caster.Parent then
			connection:Disconnect()
			Clan.fxAll("ShadowEnd", { Id = id, Reason = "Lost" })
			return
		end
		local step = math.min(config.Speed * dt, config.Range - travelled)
		if step <= 0 then
			connection:Disconnect()
			Clan.fxAll("ShadowEnd", { Id = id, Reason = "Range" })
			return
		end
		-- Pared delante: la sombra se corta
		if Targets.castWorld(tip + Vector3.yAxis * 1, flat * (step + 0.5), { caster }) then
			connection:Disconnect()
			Clan.fxAll("ShadowEnd", { Id = id, Reason = "Blocked" })
			return
		end
		local nextGround = groundAt(tip + flat * step, { caster })
		if not nextGround then
			connection:Disconnect()
			Clan.fxAll("ShadowEnd", { Id = id, Reason = "NoGround" })
			return
		end
		tip = nextGround.Position
		travelled += step

		for _, candidate in Targets.list(caster) do
			local offset = candidate.Root.Position - tip
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= config.CatchRadius
				and math.abs(offset.Y) <= 5
				and isGrounded(candidate.Character, config.GroundedHeight)
				and candidate.Character:GetAttribute("IsMissionNPC") ~= true then
				connection:Disconnect()
				hold(context, candidate, id)
				return
			end
		end
	end)
end)
