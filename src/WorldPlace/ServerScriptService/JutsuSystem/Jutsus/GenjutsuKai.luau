-- ServerScriptService > JutsuSystem > Jutsus > GenjutsuKai
--
-- Genjutsu · Kai (rango E, primera capa).
-- Te libera de cualquier genjutsu. Si no estás bajo uno, libera al jugador que estés
-- tocando (≤ 6 studs, delante de ti) que sí lo esté.
-- 1 sello.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Genjutsu = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Genjutsu")
)

local ALLY_RANGE = 6

local GenjutsuKai = {}

GenjutsuKai.Id = "GenjutsuKai"
GenjutsuKai.TechniqueCategory = "Genjutsu"
GenjutsuKai.MinimumLevel = 1
GenjutsuKai.SortOrder = 700

GenjutsuKai.Config = {
	DisplayName = "Genjutsu Kai",
	TechniqueCategory = "Genjutsu",
	MinimumLevel = 1,
	SortOrder = 700,

	ChakraCost = 10,
	Cooldown = 6.0,
	CastTime = 0.3,
}

GenjutsuKai.MarkerCastTimeout = 4.0
GenjutsuKai.ProjectileFallbackDelay = 2.0
GenjutsuKai.MinProjectileDelay = 0

return Genjutsu.build(GenjutsuKai, function(context)
	local character: Model = context.Character
	Genjutsu.fxAll("Kai", { Character = character })

	if Genjutsu.release(character, "Kai") then
		return
	end

	-- Liberar a otro tocándolo
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
		if otherCharacter and otherCharacter ~= character and otherRoot
			and Genjutsu.isAffected(otherCharacter) then
			local offset = otherRoot.Position - root.Position
			if offset.Magnitude <= ALLY_RANGE and root.CFrame.LookVector:Dot(offset.Unit) > 0.2 then
				Genjutsu.release(otherCharacter, "Kai")
				return
			end
		end
	end
end)
