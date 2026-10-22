-- ServerScriptService > JutsuSystem > Jutsus > ChakuraNagashi
--
-- Kenjutsu · Chakura Nagashi (rango C, primera capa). Flujo de chakra en el arma.
-- 12 s imbuyendo el arma con tu elemento principal (PrimaryNatureId):
--   - tus golpes con arma (M1 y kenjutsu) hacen +35 % de daño;
--   - cada golpe que da en el cuerpo aplica el estado de tu elemento:
--       Fuego → Burning (quema) · Viento → Unsteady · Rayo → Charged
--       Tierra → Heavy · Agua → Wet
--     (los mismos estados que los jutsus, así que también disparan sus reacciones).
-- Lo aplica DamageService v1.3 leyendo ChakraFlowElement / ChakraFlowUntil.
-- Se pierde si enfundas el arma. Gasta CHAKRA (la supresión de chakra lo bloquea).

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Kenjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Kenjutsu")
)

local VALID_ELEMENTS = {
	Fire = true,
	Wind = true,
	Lightning = true,
	Earth = true,
	Water = true,
}

local ChakuraNagashi = {}

ChakuraNagashi.Id = "ChakuraNagashi"
ChakuraNagashi.TechniqueCategory = "Kenjutsu"
ChakuraNagashi.MinimumLevel = 1
ChakuraNagashi.SortOrder = 910

ChakuraNagashi.Config = {
	DisplayName = "Chakura Nagashi",
	TechniqueCategory = "Kenjutsu",
	MinimumLevel = 1,
	SortOrder = 910,

	ChakraCost = 25,
	Cooldown = 25.0,
	CastTime = 0.4,

	Duration = 12.0,
}

ChakuraNagashi.MarkerCastTimeout = 4.0
ChakuraNagashi.ProjectileFallbackDelay = 2.0
ChakuraNagashi.MinProjectileDelay = 0

local function elementOf(character: Model): string?
	local player = Players:GetPlayerFromCharacter(character)
	local element = player and player:GetAttribute("PrimaryNatureId")
	if typeof(element) == "string" and VALID_ELEMENTS[element] then
		return element
	end
	return nil
end

-- Sin elemento principal no empieza (no gasta chakra)
function ChakuraNagashi.Precheck(character: Model): (boolean, string)
	return elementOf(character) ~= nil, "NoPrimaryNature"
end

return Kenjutsu.build(ChakuraNagashi, function(context)
	local config = context.Config
	local character: Model = context.Character
	local element = elementOf(character)
	if not element then
		return
	end

	local untilTime = Workspace:GetServerTimeNow() + config.Duration
	character:SetAttribute("ChakraFlowElement", element)
	character:SetAttribute("ChakraFlowUntil", untilTime)
	Kenjutsu.fxAll("ChakraFlow", { Character = character, Element = element, Until = untilTime })

	-- Al terminar (o al enfundar) se apaga
	local connection: RBXScriptConnection? = nil
	local function clear()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if character.Parent and character:GetAttribute("ChakraFlowUntil") == untilTime then
			character:SetAttribute("ChakraFlowElement", nil)
			character:SetAttribute("ChakraFlowUntil", nil)
			Kenjutsu.fxAll("ChakraFlowEnd", { Character = character })
		end
	end
	connection = character:GetAttributeChangedSignal("WeaponState"):Connect(function()
		if character:GetAttribute("WeaponState") ~= "Drawn" then
			clear()
		end
	end)
	task.delay(config.Duration, clear)
end)
