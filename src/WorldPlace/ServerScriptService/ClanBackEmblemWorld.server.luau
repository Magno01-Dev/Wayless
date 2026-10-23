--!strict
-- Server-side character badge, driven by existing ClanId and CharacterStarterTopId.
-- Can coexist with CharacterOriginService and CharacterIdentityService; modifies neither.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClanBackEmblem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClanBackEmblem"))
-- Read the existing wardrobe catalog only; NEVER edit it from the badge system.
local shared = ReplicatedStorage:WaitForChild("Shared")
local catalog = require(shared:WaitForChild("AppearanceCatalog"))

local function wornTopId(character: Model, selectedTopId: any): any
    local shirt = character:FindFirstChild("WAYLESSStarterTop")
    if not shirt or not shirt:IsA("Shirt") then return selectedTopId end
    local texture = shirt.ShirtTemplate
    if texture == "" then return nil end
    if typeof(catalog.GetStarterTop) ~= "function" then return selectedTopId end
    if typeof(selectedTopId) == "string" then
        local previous = catalog.GetStarterTop(selectedTopId)
        if previous and previous.ShirtTemplate == texture then return selectedTopId end
    end
    -- Existing service can swap a Shirt without changing the starter TopId.
    -- Derive from real *worn* classic shirt when the catalog knows that top.
    for _, side in ipairs({"H", "M"}) do
        for n = 1, 15 do
            local id = string.format("%s%02d_TOP", side, n)
            local entry = catalog.GetStarterTop(id)
            if entry and entry.ShirtTemplate == texture then return id end
        end
    end
    return nil -- Unrecognized shirt: do not display wrong clan emblem.
end

local playerConnections: {[Player]: {RBXScriptConnection}} = {}
local characterConnections: {[Player]: {RBXScriptConnection}} = {}

local function clearCharacterSignals(player: Player)
    for _, connection in ipairs(characterConnections[player] or {}) do connection:Disconnect() end
    characterConnections[player] = nil
end

local function onCharacter(player: Player, character: Model)
    clearCharacterSignals(player)
    local connections: {RBXScriptConnection} = {}
    characterConnections[player] = connections
    local shirtConnection: RBXScriptConnection? = nil

    local function refresh()
        if player.Character ~= character or not character.Parent then return end
        ClanBackEmblem.Apply(character,
            player:GetAttribute("ClanId"),
            wornTopId(character, player:GetAttribute("CharacterStarterTopId")))
    end
    local function watchShirt(child: Instance)
        if not child:IsA("Shirt") or child.Name ~= "WAYLESSStarterTop" then return end
        if shirtConnection then shirtConnection:Disconnect() end
        shirtConnection = child:GetPropertyChangedSignal("ShirtTemplate"):Connect(refresh)
        table.insert(connections, shirtConnection)
        task.defer(refresh)
    end
    for _, child in ipairs(character:GetChildren()) do watchShirt(child) end
    table.insert(connections, player:GetAttributeChangedSignal("ClanId"):Connect(refresh))
    table.insert(connections, player:GetAttributeChangedSignal("CharacterStarterTopId"):Connect(refresh))
    table.insert(connections, character.ChildAdded:Connect(function(child)
        if child.Name == "Torso" then task.defer(refresh) end
        watchShirt(child)
    end))
    table.insert(connections, character.Destroying:Connect(function()
        clearCharacterSignals(player)
    end))
    task.spawn(function()
        local torso = character:WaitForChild("Torso", 15)
        if torso and player.Character == character then refresh() end
    end)
end

local function onPlayer(player: Player)
    playerConnections[player] = {
        player.CharacterAdded:Connect(function(character) onCharacter(player, character) end),
        player.CharacterRemoving:Connect(function() clearCharacterSignals(player) end),
    }
    if player.Character then onCharacter(player, player.Character) end
end

Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
    clearCharacterSignals(player)
    for _, c in ipairs(playerConnections[player] or {}) do c:Disconnect() end
    playerConnections[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end
print("[WAYLESS ClanBackEmblem] WorldPlace visual service ready / TESTING v1")
