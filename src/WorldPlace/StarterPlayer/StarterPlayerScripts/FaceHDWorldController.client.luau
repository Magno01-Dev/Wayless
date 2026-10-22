--!strict
-- WorldPlace candidate: render every player's neutral/expressive face on an
-- invisible R6 mesh overlay, not directly on the pixelated original Head.
-- Keeps CharacterFaceController and CharacterIdentityService installed.
-- They still choose and maintain neutral decals; this script mirrors them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Integration = require(Shared:WaitForChild("FaceHDIntegration"))
local Surface = require(Shared:WaitForChild("FaceHDSurface"))

local PRESETS = {
    neutral = {cejas = "neutral", ojos = "neutral", boca = "neutral"},
    activacion = {cejas = "esfuerzo", ojos = "alerta", boca = "neutral"},
    sorpresa = {cejas = "alerta", ojos = "alerta", boca = "alerta"},
    dolor = {cejas = "dolor", ojos = "dolor", boca = "dolor"},
    esfuerzo = {cejas = "esfuerzo", ojos = "esfuerzo", boca = "esfuerzo"},
}
local SOURCE = {cejas = "WAYLESS_Brows", ojos = "WAYLESS_Eyes", nariz = "WAYLESS_Nose", boca = "WAYLESS_Mouth"}
local STYLE_ATTR = {cejas = "CharacterAppearanceBrowStyleId", ojos = "CharacterBaseEyeStyleId", nariz = "CharacterAppearanceNoseStyleId", boca = "CharacterAppearanceMouthStyleId"}
local VARIANTS = {normal = true, iris_limpio = true, sharingan_1 = true, sharingan_2 = true, sharingan_3 = true, byakugan = true, mangekyo = true}
local states = {}
local watching = {}

local function resolveDojutsu(player: Player, character: Model): string
    local explicit = character:GetAttribute("FaceDojutsu")
    if typeof(explicit) == "string" and VARIANTS[explicit] then return explicit end
    -- Preserve existing WAYLESS eye-variant integration without changing
    -- CharacterIdentityService or saved CharacterBaseEyeStyleId.
    local legacy = player:GetAttribute("CharacterEyeVariantId")
    if legacy == "Sharingan" then return "sharingan_3" end
    if legacy == "Byakugan" then return "byakugan" end
    return "normal"
end

local function bind(player: Player, character: Model)
    local existing = states[player]
    if existing then existing.Stop() end
    local state: any = {Alive = true, Connections = {}, SourceConnections = {}, Revision = 0, Head = nil}
    states[player] = state
    local function stop()
        if not state.Alive then return end
        state.Alive = false
        state.Revision += 1
        for _, conn in ipairs(state.Connections) do conn:Disconnect() end
        for _, conn in ipairs(state.SourceConnections) do conn:Disconnect() end
        if state.Renderer then state.Renderer.Stop() end
        if states[player] == state then states[player] = nil end
    end
    state.Stop = stop
    local function draw(blink: string?)
        if not state.Alive or not state.Head or not state.Head.Parent then return end
        local head = state.Head
        local expression = character:GetAttribute("FaceExpression")
        local preset = PRESETS[expression] or PRESETS.neutral
        local dojutsu = resolveDojutsu(player, character)
        local images = {}
        for layer, oldName in pairs(SOURCE) do
            local decal = head:FindFirstChild(oldName)
            local fallback = decal and decal:IsA("Decal") and decal.Texture or nil
            local family = Integration.FamilyFromStyle(player:GetAttribute(STYLE_ATTR[layer]))
            local image = nil
            if family then
                if layer == "ojos" then
                    local eyeState = blink or preset.ojos
                    local variant = (eyeState == "dolor" or eyeState == "parpadeo_cerrado") and "comun" or dojutsu
                    image = Integration.Image(Integration.Path(family, "ojos", eyeState, variant))
                    if not image then image = Integration.Image(Integration.Path(family, "ojos", "neutral", dojutsu)) end
                    if not image then image = Integration.Image(Integration.Path(family, "ojos", "neutral", "normal")) end
                else
                    image = Integration.Image(Integration.Path(family, layer, (layer == "nariz") and "neutral" or preset[layer]))
                    if not image then image = Integration.Image(Integration.Path(family, layer, "neutral")) end
                end
            end
            images[layer] = image or fallback
        end
        if dojutsu == "byakugan" and character:GetAttribute("FaceByakuganActive") == true then
            images.venas = Integration.Image("assets/efectos/byakugan_venas.png")
        end
        if not state.Renderer or not state.Renderer.Alive then state.Renderer = Surface.Attach(character) end
        if state.Renderer then state.Renderer.Apply(images) end
    end
    state.Draw = draw
    local function refreshed()
        state.Revision += 1
        draw(nil)
    end
    for _, attr in ipairs({"FaceExpression", "FaceDojutsu", "FaceByakuganActive"}) do
        table.insert(state.Connections, character:GetAttributeChangedSignal(attr):Connect(refreshed))
    end
    for _, attr in pairs(STYLE_ATTR) do
        table.insert(state.Connections, player:GetAttributeChangedSignal(attr):Connect(refreshed))
    end
    for _, attr in ipairs({"CharacterEyeVariantId", "CharacterEyeStyleId"}) do
        table.insert(state.Connections, player:GetAttributeChangedSignal(attr):Connect(refreshed))
    end
    table.insert(state.Connections, character.Destroying:Connect(stop))
    local function bindHead(head: Instance)
        if not state.Alive or not head:IsA("Part") or state.Head == head then return end
        state.Revision += 1
        for _, connection in ipairs(state.SourceConnections) do connection:Disconnect() end
        state.SourceConnections = {}
        if state.Renderer then state.Renderer.Stop(); state.Renderer = nil end
        state.Head = head
        local function registerDecal(child: Instance)
            if child:IsA("Decal") and
                (child.Name == SOURCE.cejas or child.Name == SOURCE.ojos or child.Name == SOURCE.nariz or child.Name == SOURCE.boca) then
                table.insert(state.SourceConnections, child:GetPropertyChangedSignal("Texture"):Connect(function()
                    task.defer(refreshed)
                end))
                task.defer(refreshed)
            end
        end
        for _, child in ipairs(head:GetChildren()) do registerDecal(child) end
        table.insert(state.SourceConnections, head.ChildAdded:Connect(registerDecal))
        table.insert(state.SourceConnections, head.AncestryChanged:Connect(function()
            if not head:IsDescendantOf(workspace) and state.Head == head then
                state.Revision += 1
                state.Head = nil
                if state.Renderer then state.Renderer.Stop(); state.Renderer = nil end
            end
        end))
        task.defer(refreshed)
    end
    table.insert(state.Connections, character.ChildAdded:Connect(function(child)
        if child.Name == "Head" then bindHead(child) end
    end))
    task.spawn(function()
        local head = character:WaitForChild("Head", 10)
        if head then bindHead(head) end
    end)
    task.spawn(function()
        while state.Alive do
            task.wait(3 + math.random() * 2.5)
            if not state.Alive then break end
            local expression = character:GetAttribute("FaceExpression")
            local family = Integration.FamilyFromStyle(player:GetAttribute(STYLE_ATTR.ojos))
            if state.Head and (expression == nil or expression == "neutral") and family and
                Integration.Image(Integration.Path(family, "ojos", "parpadeo_medio", resolveDojutsu(player, character))) and
                Integration.Image(Integration.Path(family, "ojos", "parpadeo_cerrado", "comun")) then
                local version = state.Revision
                for _, frame in ipairs({{"parpadeo_medio", 0.05}, {"parpadeo_cerrado", 0.08}, {"parpadeo_medio", 0.05}}) do
                    if not state.Alive or version ~= state.Revision then break end
                    draw(frame[1]); task.wait(frame[2])
                end
                if state.Alive and version == state.Revision then draw(nil) end
            end
        end
    end)
end

local function watch(player: Player)
    if watching[player] then return end
    local links = {}
    watching[player] = links
    table.insert(links, player.CharacterAdded:Connect(function(character) bind(player, character) end))
    table.insert(links, player.CharacterRemoving:Connect(function()
        local s = states[player]
        if s then s.Stop() end
    end))
    if player.Character then bind(player, player.Character) end
end
local function unwatch(player: Player)
    local s = states[player]
    if s then s.Stop() end
    for _, c in ipairs(watching[player] or {}) do c:Disconnect() end
    watching[player] = nil
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(unwatch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
