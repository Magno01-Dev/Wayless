--!strict
-- WAYLESS FaceHD gameplay wiring v2.0 CANDIDATE, WorldPlace.
-- Reuses canonical DamageService.AfterHit and JutsuInternal.CastStarted.
-- Never creates remotes, changes damage calculations, or writes DataStores.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local FaceExpressions = require(ServerScriptService:WaitForChild("Services"):WaitForChild("FaceExpressionService"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local connections: {[Player]: {RBXScriptConnection}} = {}

DamageService.AddHook({
    AfterHit = function(context: any, _result: string)
        local target = context.TargetCharacter
        if typeof(target) == "Instance" and target:IsA("Model") then
            FaceExpressions.Set(target, "dolor", 0.7)
        end
        -- Only a confirmed body hit: no success expression for misses or substitutions.
        local attacker = context.Attacker
        if attacker and attacker:IsA("Player") and attacker.Character then
            FaceExpressions.Set(attacker.Character, "esfuerzo", 0.35)
        end
    end,
})

local function bindPlayer(player: Player)
    local function bindCharacter(character: Model)
        local list = connections[player]
        if list then
            for _, c in ipairs(list) do c:Disconnect() end
        end
        list = {}
        connections[player] = list
        local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
        if humanoid and humanoid:IsA("Humanoid") then
            local lastHealth = humanoid.Health
            -- Fallback for current systems that may damage a player outside
            -- DamageService. Only decreases cause pain; healing never does.
            table.insert(list, humanoid.HealthChanged:Connect(function(health)
                if health < lastHealth and health > 0 then FaceExpressions.Set(character, "dolor", 0.7) end
                lastHealth = health
            end))
            table.insert(list, humanoid.Died:Connect(function()
                FaceExpressions.Clear(character)
            end))
        end
    end
    player.CharacterAdded:Connect(bindCharacter)
    if player.Character then task.spawn(bindCharacter, player.Character) end
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
    for _, c in ipairs(connections[player] or {}) do c:Disconnect() end
    connections[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end

-- JutsuServer publishes this BindableEvent only AFTER a cast is accepted.
-- It is also consumed by Clan (Sharingan Read); do not replace it.
task.spawn(function()
    local internal = ServerStorage:WaitForChild("JutsuInternal", 60)
    local event = internal and internal:WaitForChild("CastStarted", 60)
    if not event or not event:IsA("BindableEvent") then
        warn("[FaceHD] JutsuInternal.CastStarted unavailable; jutsu expressions disabled")
        return
    end
    event.Event:Connect(function(player: Player, character: Model, _techniqueId: string, _info: any)
        if player and player.Character == character then
            FaceExpressions.Set(character, "esfuerzo", 0.72)
        end
    end)
end)
