-- ServerScriptService > JutsuSystem > Jutsus > Shunshin
--
-- Ninjutsu · Shunshin no Jutsu (rango C, primera capa). Cuerpo parpadeante.
-- Te teletransportas hasta 18 studs hacia el retículo (subiendo como máximo 8), con humo y
-- hojas donde estabas y donde apareces. No atraviesa paredes: te deja justo antes.
-- 1 sello. Gasta chakra.

local ServerScriptService = game:GetService("ServerScriptService")

local Ninjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Ninjutsu")
)

local Shunshin = {}

Shunshin.Id = "Shunshin"
Shunshin.TechniqueCategory = "Ninjutsu"
Shunshin.MinimumLevel = 1
Shunshin.SortOrder = 1000

Shunshin.Config = {
	DisplayName = "Shunshin no Jutsu",
	TechniqueCategory = "Ninjutsu",
	MinimumLevel = 1,
	SortOrder = 1000,

	ChakraCost = 15,
	Cooldown = 6.0,
	CastTime = 0.3,

	Distance = 18,
	MaxRise = 8,
	WallMargin = 2.5,
}

Shunshin.MarkerCastTimeout = 3.0
Shunshin.ProjectileFallbackDelay = 1.0
Shunshin.MinProjectileDelay = 0

return Ninjutsu.build(Shunshin, function(context, direction)
	local config = context.Config
	local character: Model = context.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart

	-- Dirección: hacia el retículo, sin subir más de MaxRise
	local travel = direction.Unit * config.Distance
	if travel.Y > config.MaxRise then
		travel = Vector3.new(travel.X, config.MaxRise, travel.Z)
	end
	if Vector3.new(travel.X, 0, travel.Z).Magnitude < 1 then
		local look = root.CFrame.LookVector
		travel = Vector3.new(look.X, 0, look.Z).Unit * config.Distance
	end

	-- Paredes: se queda antes del obstáculo
	local from = root.Position
	local hit = Ninjutsu.castWorld(from, travel, { character })
	if hit then
		local reach = math.max((hit.Position - from).Magnitude - config.WallMargin, 0)
		travel = travel.Unit * reach
	end
	if travel.Magnitude < 2 then
		return
	end
	local destination = from + travel

	-- Apoyarse en el suelo si está cerca (no aparecer flotando por un pequeño desnivel)
	local ground = Ninjutsu.castWorld(destination + Vector3.yAxis * 2, Vector3.yAxis * -8, { character })
	if ground then
		local hipHeight = root.Position.Y - (Ninjutsu.castWorld(from, Vector3.yAxis * -8, { character }) or { Position = from - Vector3.yAxis * 3 }).Position.Y
		destination = Vector3.new(destination.X, ground.Position.Y + math.clamp(hipHeight, 2.5, 4), destination.Z)
	end

	local flatLook = Vector3.new(travel.X, 0, travel.Z)
	local facing = if flatLook.Magnitude > 0.1 then flatLook.Unit else root.CFrame.LookVector
	character:PivotTo(CFrame.lookAt(destination, destination + facing))
	root.AssemblyLinearVelocity = Vector3.zero

	Ninjutsu.fxAll("Shunshin", { Character = character, From = from, To = destination })
end)
