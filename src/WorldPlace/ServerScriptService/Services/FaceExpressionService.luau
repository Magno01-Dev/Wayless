--!strict
-- WAYLESS Face Expression Service v2.0 CANDIDATE.
-- Server-authoritative, visual only; no damage, health or combat mechanics.
-- API Set(character, expression, duration?, priority?), Clear(character).
local FaceExpressionService = {}
local PRIORITY: {[string]: number} = {
    neutral = 0,
    activacion = 35,
    esfuerzo = 25,
    sorpresa = 40,
    dolor = 90,
    ko = 110,
}
local DEFAULT_DURATION: {[string]: number} = {
    neutral = 0,
    activacion = 0.55,
    esfuerzo = 0.65,
    sorpresa = 0.65,
    dolor = 0.72,
    ko = 0,
}
local states = setmetatable({}, {__mode = "k"})
local function now(): number
    return workspace:GetServerTimeNow()
end
local function aliveCharacter(character: any): boolean
    if typeof(character) ~= "Instance" or not character:IsA("Model") or not character.Parent then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

function FaceExpressionService.Set(character: Model, expression: string, duration: number?, priority: number?): boolean
    if not aliveCharacter(character) or not PRIORITY[expression] then return false end
    local t = now()
    local current = states[character]
    local nextPriority = priority or PRIORITY[expression]
    if current and current.untilTime > t and nextPriority < current.priority then return false end
    local seconds = if duration == nil then DEFAULT_DURATION[expression] else math.clamp(duration, 0, 10)
    local token = if current then current.token + 1 else 1
    local untilTime = if seconds == 0 then math.huge else t + seconds
    states[character] = {token = token, priority = nextPriority, untilTime = untilTime}
    character:SetAttribute("FaceExpression", expression)
    if seconds > 0 then
        task.delay(seconds, function()
            local pending = states[character]
            if pending and pending.token == token and now() >= pending.untilTime - 0.05 then
                states[character] = nil
                if character.Parent then character:SetAttribute("FaceExpression", nil) end
            end
        end)
    end
    return true
end
function FaceExpressionService.Clear(character: Model)
    states[character] = nil
    if character.Parent then character:SetAttribute("FaceExpression", nil) end
end
return FaceExpressionService
