-- ServerScriptService > JutsuSystem > Jutsus > UzumakiFuin
--
-- Clan Uzumaki · Fūin: sello de marcas (etapa 1 · Despertar).
-- Tus golpes cuerpo a cuerpo dejan marcas de sello en el rival (pasiva del clan, máx. 3,
-- duran 8 s). Con 3 marcas, apunta al rival (≤ 35 studs) y detónalas: 3 s sin poder hacer
-- jutsus ni cargar chakra, y si estaba haciendo sellos de mano, el jutsu falla.
-- Sin 3 marcas en el rival al que apuntas, la técnica ni empieza (no gasta chakra).
-- 1 sello.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Clan = require(
	ServerScriptService
		:WaitForChild("JutsuSystem")
		:WaitForChild("TechniqueKit")
		:WaitForChild("Clan")
)

local RANGE = 35
local AIM_ANGLE = 14
local REQUIRED_MARKS = 3

local UzumakiFuin = {}

UzumakiFuin.Id = "UzumakiFuin"
UzumakiFuin.TechniqueCategory = "Clan"
UzumakiFuin.MinimumLevel = 1
UzumakiFuin.SortOrder = 1120

UzumakiFuin.Config = {
	DisplayName = "Fūin: Seal Marks",
	TechniqueCategory = "Clan",
	MinimumLevel = 1,
	SortOrder = 1120,

	ChakraCost = 18,
	Cooldown = 12.0,
	CastTime = 0.4,

	SealDuration = 3.0,
}

UzumakiFuin.MarkerCastTimeout = 4.0
UzumakiFuin.ProjectileFallbackDelay = 1.5
UzumakiFuin.MinProjectileDelay = 0

local function markedTarget(character: Model, direction: Vector3): any?
	local target = Clan.findTarget({ Character = character }, direction, RANGE, AIM_ANGLE)
	if target and Clan.getMarks("Uzumaki", target.Character) >= REQUIRED_MARKS then
		return target
	end
	return nil
end

function UzumakiFuin.Precheck(character: Model, direction: Vector3): (boolean, string)
	return markedTarget(character, direction) ~= nil, "NotEnoughSealMarks"
end

local interruptCast: BindableFunction? = nil

return Clan.build(UzumakiFuin, "Uzumaki", function(context, direction)
	local config = context.Config
	local target = markedTarget(context.Character, direction)
	if not target then
		Clan.fxTo(context.Player, "Notice", { Text = "LAS MARCAS SE PERDIERON" })
		return
	end
	Clan.clearMarks("Uzumaki", target.Character)
	Clan.applyStatus(target.Character, "UzumakiSealed", {
		Duration = config.SealDuration,
		SourcePlayer = context.Player,
		SourceCharacter = context.Character,
	})

	-- Si estaba haciendo sellos de mano, su jutsu falla
	local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
	if targetPlayer then
		if not interruptCast then
			local folder = ServerStorage:FindFirstChild("JutsuInternal")
			local found = folder and folder:FindFirstChild("InterruptCast")
			interruptCast = if found and found:IsA("BindableFunction") then found else nil
		end
		if interruptCast then
			pcall(function()
				(interruptCast :: BindableFunction):Invoke(targetPlayer)
			end)
		end
	end

	Clan.fxAll("SealBurst", { Target = target.Character, Duration = config.SealDuration })
end)
