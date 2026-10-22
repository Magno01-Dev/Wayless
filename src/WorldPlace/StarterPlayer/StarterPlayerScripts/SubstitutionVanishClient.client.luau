--!strict
-- StarterPlayer > StarterPlayerScripts > SubstitutionVanishClient
--
-- Invisibilidad tras la sustitución (SubstitutionServer pone el atributo SubstitutionHidden
-- en el personaje). En TU pantalla:
--   · los demás que estén invisibles desaparecen del todo: cuerpo, accesorios, partículas,
--     estelas, luces y los BillboardGui que lleven encima (nombres, barras, brillos…)
--   · tú te ves semitransparente para saber dónde estás
-- Los clanes con dōjutsu (Sharingan 2+ tomoe, Byakugan) ven remanentes: los dibuja ClanClient.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local SELF_TRANSPARENCY = 0.6

type Hidden = {
	Disabled: {[Instance]: boolean},
	Added: RBXScriptConnection?,
}

local hidden: {[Model]: Hidden} = {}

local function isLocal(character: Model): boolean
	return character == localPlayer.Character
end

local function hideInstance(entry: Hidden, instance: Instance)
	if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") then
		(instance :: any).LocalTransparencyModifier = 1
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
		or instance:IsA("Light") or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles") then
		if (instance :: any).Enabled == true then
			entry.Disabled[instance] = true;
			(instance :: any).Enabled = false
		end
	elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") or instance:IsA("Highlight") then
		if (instance :: any).Enabled == true then
			entry.Disabled[instance] = true;
			(instance :: any).Enabled = false
		end
	end
end

-- BillboardGui en PlayerGui con Adornee dentro del personaje (nombres, brillos de ojos…)
local function hideAdornedGuis(entry: Hidden, character: Model)
	for _, gui in playerGui:GetDescendants() do
		if gui:IsA("BillboardGui") and gui.Enabled and gui.Adornee and gui.Adornee:IsDescendantOf(character) then
			entry.Disabled[gui] = true
			gui.Enabled = false
		end
	end
end

local function hide(character: Model)
	if hidden[character] or isLocal(character) then
		return
	end
	local entry: Hidden = { Disabled = {}, Added = nil }
	hidden[character] = entry
	for _, descendant in character:GetDescendants() do
		hideInstance(entry, descendant)
	end
	hideAdornedGuis(entry, character)
	-- Lo que aparezca mientras está oculto (estelas, efectos) también se oculta
	entry.Added = character.DescendantAdded:Connect(function(descendant)
		hideInstance(entry, descendant)
	end)
end

local function show(character: Model)
	local entry = hidden[character]
	if not entry then
		return
	end
	hidden[character] = nil
	if entry.Added then
		entry.Added:Disconnect()
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			(descendant :: any).LocalTransparencyModifier = 0
		end
	end
	for instance in entry.Disabled do
		if instance.Parent then
			(instance :: any).Enabled = true
		end
	end
end

local function sync(character: Model)
	if character:GetAttribute("SubstitutionHidden") == true then
		hide(character)
	else
		show(character)
	end
end

local function watch(character: Model)
	character:GetAttributeChangedSignal("SubstitutionHidden"):Connect(function()
		sync(character)
	end)
	sync(character)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
	player.CharacterRemoving:Connect(function(character)
		hidden[character] = nil
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end

-- Tú mismo: semitransparente cada fotograma, después de la cámara (que también toca la
-- transparencia local de tu personaje al acercarla)
local selfWasHidden = false
RunService:BindToRenderStep("SubstitutionVanishSelf", Enum.RenderPriority.Camera.Value + 1, function()
	local character = localPlayer.Character
	local isHidden = character ~= nil and character:GetAttribute("SubstitutionHidden") == true
	if not character or (not isHidden and not selfWasHidden) then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			if isHidden then
				(descendant :: any).LocalTransparencyModifier = math.max((descendant :: any).LocalTransparencyModifier, SELF_TRANSPARENCY)
			elseif descendant.Name ~= "HumanoidRootPart" then
				(descendant :: any).LocalTransparencyModifier = 0
			end
		end
	end
	selfWasHidden = isHidden
end)
