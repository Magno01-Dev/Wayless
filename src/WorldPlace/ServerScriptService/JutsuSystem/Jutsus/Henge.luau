-- ServerScriptService > JutsuSystem > Jutsus > Henge
--
-- Ninjutsu · Henge no Jutsu (rango D, primera capa). Transformación.
-- Apunta a alguien (≤ 60 studs) y tomas su apariencia y su placa de nombre; si no apuntas
-- a nadie, te conviertes en un tronco. Dura hasta 30 s y se rompe (con humo) si:
--   - recibes daño, usas otro jutsu (servidor),
--   - atacas, lanzas o bloqueas (lo detecta tu cliente y lo pide al servidor),
--   - vuelves a usar Henge.
-- El disfraz lo dibuja cada cliente (NinjutsuClient): esconde tu cuerpo y muestra una copia
-- del objetivo que te sigue. Tu placa se oculta con el atributo HengeActive (requiere el
-- cambio de PlayerNameplateController del LEEME). 2 sellos. Gasta chakra.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Ninjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Ninjutsu")
)

local RANGE = 60
local AIM_ANGLE = 12

local Henge = {}

Henge.Id = "Henge"
Henge.TechniqueCategory = "Ninjutsu"
Henge.MinimumLevel = 1
Henge.SortOrder = 1020

Henge.Config = {
	DisplayName = "Henge no Jutsu",
	TechniqueCategory = "Ninjutsu",
	MinimumLevel = 1,
	SortOrder = 1020,

	ChakraCost = 12,
	Cooldown = 15.0,
	CastTime = 0.5,

	MaxDuration = 30,
}

Henge.MarkerCastTimeout = 4.0
Henge.ProjectileFallbackDelay = 2.0
Henge.MinProjectileDelay = 0

type Active = {
	Token: number,
	Connections: {RBXScriptConnection},
}

local active: {[Model]: Active} = {}

local function endHenge(character: Model, reason: string)
	local entry = active[character]
	if not entry then
		return
	end
	active[character] = nil
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	if character.Parent then
		character:SetAttribute("HengeActive", nil)
	end
	Ninjutsu.fxAll("HengeEnd", { Character = character, Id = entry.Token, Reason = reason })
end

-- El cliente del transformado pide romperlo al atacar / lanzar / bloquear
Ninjutsu.remote().OnServerEvent:Connect(function(player: Player, action: any)
	if action ~= "HengeBreak" then
		return
	end
	local character = player.Character
	if character and active[character] then
		endHenge(character, "Action")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		endHenge(player.Character, "Left")
	end
end)

return Ninjutsu.build(Henge, function(context, direction)
	local config = context.Config
	local character: Model = context.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid

	-- Volver a usarlo deshace el anterior
	endHenge(character, "Recast")

	local target = Ninjutsu.findTarget(context, direction, RANGE, AIM_ANGLE)
	local token = (character:GetAttribute("HengeToken") or 0) + 1
	character:SetAttribute("HengeToken", token)
	character:SetAttribute("HengeActive", true)

	local entry: Active = { Token = token, Connections = {} }
	active[character] = entry

	-- Romper al recibir daño
	local lastHealth = humanoid.Health
	table.insert(entry.Connections, humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth - 0.01 then
			endHenge(character, "Damage")
		end
		lastHealth = health
	end))

	-- Romper al empezar OTRO jutsu (el cast de Henge todavía está terminando)
	local ownCastFinished = character:GetAttribute("JutsuCasting") ~= true
	table.insert(entry.Connections, character:GetAttributeChangedSignal("JutsuCasting"):Connect(function()
		if character:GetAttribute("JutsuCasting") ~= true then
			ownCastFinished = true
		elseif ownCastFinished then
			endHenge(character, "Jutsu")
		end
	end))

	table.insert(entry.Connections, humanoid.Died:Connect(function()
		endHenge(character, "Died")
	end))

	task.delay(config.MaxDuration, function()
		if active[character] == entry then
			endHenge(character, "Expired")
		end
	end)

	Ninjutsu.fxAll("HengeStart", {
		Character = character,
		Target = if target then target.Character else nil,
		Object = if target then nil else "Log",
		Id = token,
	})
end)
