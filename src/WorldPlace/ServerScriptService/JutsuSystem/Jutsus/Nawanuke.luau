-- ServerScriptService > JutsuSystem > Jutsus > Nawanuke
--
-- Ninjutsu · Nawanuke no Jutsu (rango D, primera capa). Escape de ataduras.
-- Instantáneo, sin sellos. Te libera de ataduras, raíces y lentitudes (kunai clavado, hilo
-- ninja, Sōfūsha, abrojos, agujas y parálisis del senbon, lentitud genérica) y das un salto
-- hacia atrás. Se puede usar con el ataque bloqueado (Config.Escape), pero no aturdido.
-- No quita genjutsu (para eso está Kai) ni veneno. Gasta chakra.

local ServerScriptService = game:GetService("ServerScriptService")

local Ninjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Ninjutsu")
)

local StatusEffectService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("StatusEffectService"))

-- Estados de los que libera
local ESCAPABLE = {
	"KunaiPin",
	"WireBind",
	"WireSlow",
	"CaltropSlow",
	"SenbonNeedle",
	"SenbonParalysis",
	"Slow",
}

local Nawanuke = {}

Nawanuke.Id = "Nawanuke"
Nawanuke.TechniqueCategory = "Ninjutsu"
Nawanuke.MinimumLevel = 1
Nawanuke.SortOrder = 1010

Nawanuke.Config = {
	DisplayName = "Nawanuke no Jutsu",
	TechniqueCategory = "Ninjutsu",
	MinimumLevel = 1,
	SortOrder = 1010,

	Escape = true, -- JutsuServer: se puede usar con el ataque bloqueado

	ChakraCost = 10,
	Cooldown = 14.0,
	CastTime = 0.1,

	HopBack = 30,
	HopUp = 18,
	HopTime = 0.15,
}

Nawanuke.MarkerCastTimeout = 2.0
Nawanuke.ProjectileFallbackDelay = 0.5
Nawanuke.MinProjectileDelay = 0

return Ninjutsu.build(Nawanuke, function(context)
	local config = context.Config
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart

	local freed = 0
	for _, statusId in ESCAPABLE do
		if StatusEffectService.Has(character, statusId) then
			StatusEffectService.Remove(character, statusId, "Nawanuke")
			freed += 1
		end
	end

	-- Salto hacia atrás (un LinearVelocity sí mueve a un jugador)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local hop = Instance.new("LinearVelocity")
	hop.Attachment0 = attachment
	hop.RelativeTo = Enum.ActuatorRelativeTo.World
	hop.MaxForce = 1e6
	hop.VectorVelocity = -look * config.HopBack + Vector3.yAxis * config.HopUp
	hop.Parent = root
	task.delay(config.HopTime, function()
		hop:Destroy()
		attachment:Destroy()
	end)

	Ninjutsu.fxAll("Nawanuke", { Character = character, Freed = freed })
end)
