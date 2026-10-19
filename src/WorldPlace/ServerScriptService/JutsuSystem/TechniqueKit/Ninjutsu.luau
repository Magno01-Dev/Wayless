-- ServerScriptService > JutsuSystem > TechniqueKit > Ninjutsu  (ModuleScript)
--
-- Base común del ninjutsu general (sin elemento). Se apoya en TechniqueKit > Genjutsu para
-- construir el jutsu (dirección del retículo, Precheck, marcador ProjectileSpawn) y para
-- buscar objetivos. Efectos visuales: remote ReplicatedStorage > JutsuSystem > Remotes >
-- NinjutsuFX (StarterPlayerScripts > NinjutsuClient).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Genjutsu = require(script.Parent:WaitForChild("Genjutsu"))
local Targets = require(ReplicatedStorage:WaitForChild("Throwables"):WaitForChild("Targets"))

local Ninjutsu = {}

-- Remote -------------------------------------------------------------------------------------

local REMOTE_NAME = "NinjutsuFX"
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	local jutsuSystem = ReplicatedStorage:WaitForChild("JutsuSystem")
	local remotes = jutsuSystem:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = jutsuSystem
	end
	local found = remotes:FindFirstChild(REMOTE_NAME)
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = REMOTE_NAME
		found.Parent = remotes
	end
	remote = found :: RemoteEvent
	return remote :: RemoteEvent
end

task.spawn(getRemote)

function Ninjutsu.remote(): RemoteEvent
	return getRemote()
end

function Ninjutsu.fxAll(action: string, data: {[string]: any})
	getRemote():FireAllClients(action, data)
end

function Ninjutsu.fxTo(player: Player?, action: string, data: {[string]: any})
	if player and player.Parent then
		getRemote():FireClient(player, action, data)
	end
end

-- Reutilizado de Genjutsu / Targets ------------------------------------------------------------

Ninjutsu.findTarget = Genjutsu.findTarget
Ninjutsu.castWorld = Targets.castWorld

-- Construcción: igual que Genjutsu.build, con categoría "Ninjutsu"
function Ninjutsu.build(module: any, execute: (any, Vector3) -> ()): any
	module.TechniqueCategory = module.TechniqueCategory or "Ninjutsu"
	return Genjutsu.build(module, execute)
end

return Ninjutsu
