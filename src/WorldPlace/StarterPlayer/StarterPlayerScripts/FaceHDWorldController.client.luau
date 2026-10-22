--!strict
-- WAYLESS FaceHD World v2.0 CANDIDATE — 2026-10-21 ACTIVE baseline.
-- Visual-only client renderer. Keeps the existing FaceHDSurface / classic R6
-- normalization, original identity decals, ClanClient and MangekyoClient intact.
-- Uses only server-replicated clan mode flags for other players.
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
    ko = {cejas = "dolor", ojos = "parpadeo_cerrado", boca = "dolor"},
}
local SOURCE = {cejas = "WAYLESS_Brows", ojos = "WAYLESS_Eyes", nariz = "WAYLESS_Nose", boca = "WAYLESS_Mouth"}
local STYLE_ATTR = {cejas = "CharacterAppearanceBrowStyleId", ojos = "CharacterBaseEyeStyleId", nariz = "CharacterAppearanceNoseStyleId", boca = "CharacterAppearanceMouthStyleId"}
local VARIANTS = {normal = true, iris_limpio = true, sharingan_1 = true, sharingan_2 = true, sharingan_3 = true, byakugan = true, mangekyo = true}
local states: {[Player]: any} = {}
local watching: {[Player]: {RBXScriptConnection}} = {}

-- Canonical gameplay states always take precedence over the legacy variant
-- string. In particular "Sharingan" does NOT imply three tomoe.
local function resolveDojutsu(player: Player, character: Model): string
    if character:GetAttribute("ByakuganActive") == true then
        return "byakugan"
    end
    if character:GetAttribute("SharinganActive") == true then
        if character:GetAttribute("MangekyoActive") == true then
            return "mangekyo"
        end
        local tomoe = character:GetAttribute("SharinganTomoe")
        if typeof(tomoe) == "number" then
            return "sharingan_" .. tostring(math.clamp(math.floor(tomoe), 1, 3))
        end
        local legacy = player:GetAttribute("CharacterEyeVariantId")
        if legacy == "Sharingan2" then return "sharingan_2" end
        if legacy == "Sharingan3" then return "sharingan_3" end
        return "sharingan_1"
    end
    -- Compatibility with external face systems, without altering clan mode.
    local explicit = character:GetAttribute("FaceDojutsu")
    if typeof(explicit) == "string" and VARIANTS[explicit] then return explicit end
    local legacy = player:GetAttribute("CharacterEyeVariantId")
    if legacy == "Sharingan" then return "sharingan_1" end
    if legacy == "Sharingan2" then return "sharingan_2" end
    if legacy == "Sharingan3" then return "sharingan_3" end
    if legacy == "Byakugan" then return "byakugan" end
    if legacy == "Mangekyo" then return "mangekyo" end
    return "normal"
end

local function bind(player: Player, character: Model)
    local old = states[player]
    if old then old.Stop() end
    local state: any = {Alive = true, Connections = {}, SourceConnections = {}, Revision = 0, Head = nil, Blink = nil, ActivationUntil = 0}
    states[player] = state
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local function stop()
        if not state.Alive then return end
        state.Alive = false
        state.Revision += 1
        for _, c in ipairs(state.Connections) do c:Disconnect() end
        for _, c in ipairs(state.SourceConnections) do c:Disconnect() end
        if state.Renderer then state.Renderer.Stop() end
        if states[player] == state then states[player] = nil end
    end
    state.Stop = stop

    local function expressionNow(): string
        if (humanoid and humanoid.Health <= 0) then return "ko" end
        if character:GetAttribute("IsDowned") == true then return "dolor" end
        if character:GetAttribute("Status_Stunned") == true or character:GetAttribute("IsStunned") == true then return "dolor" end
        local serverExpression = character:GetAttribute("FaceExpression")
        if typeof(serverExpression) == "string" and PRESETS[serverExpression] then
            return serverExpression
        end
        if workspace:GetServerTimeNow() < state.ActivationUntil then return "activacion" end
        local attackAt = character:GetAttribute("FaceAttackAt")
        if typeof(attackAt) == "number" and workspace:GetServerTimeNow() - attackAt < 0.38 and workspace:GetServerTimeNow() - attackAt > -0.3 then
            return "esfuerzo"
        end
        -- Local prediction for the attacking player only; not trusted by server.
        if player == Players.LocalPlayer and character:GetAttribute("IsAttacking") == true then
            return "esfuerzo"
        end
        return "neutral"
    end

    local function draw(blink: string?)
        if not state.Alive or not state.Head or not state.Head.Parent then return end
        local head = state.Head
        local expression = expressionNow()
        local preset = PRESETS[expression] or PRESETS.neutral
        local dojutsu = resolveDojutsu(player, character)
        local images: {[string]: string} = {}
        for layer, oldName in pairs(SOURCE) do
            local decal = head:FindFirstChild(oldName)
            local fallback = if decal and decal:IsA("Decal") then decal.Texture else nil
            local family = Integration.FamilyFromStyle(player:GetAttribute(STYLE_ATTR[layer]))
            local image: string? = nil
            if family then
                if layer == "ojos" then
                    -- The painful/closed eye textures intentionally have one
                    -- common art variant, regardless of the active dojutsu.
                    local eyeState = if expression == "neutral" then (blink or "neutral") else preset.ojos
                    local variant = if eyeState == "dolor" or eyeState == "parpadeo_cerrado" then "comun" else dojutsu
                    image = Integration.Image(Integration.Path(family, "ojos", eyeState, variant))
                    if not image and eyeState ~= "neutral" then
                        image = Integration.Image(Integration.Path(family, "ojos", "neutral", dojutsu))
                    end
                    if not image then image = Integration.Image(Integration.Path(family, "ojos", "neutral", "normal")) end
                else
                    image = Integration.Image(Integration.Path(family, layer, (layer == "nariz") and "neutral" or preset[layer]))
                    if not image then image = Integration.Image(Integration.Path(family, layer, "neutral")) end
                end
            end
            images[layer] = image or fallback or ""
        end
        if dojutsu == "byakugan" and character:GetAttribute("ByakuganActive") == true then
            images.venas = Integration.Image("assets/efectos/byakugan_venas.png") or ""
        end
        if not state.Renderer or not state.Renderer.Alive then state.Renderer = Surface.Attach(character) end
        if state.Renderer then state.Renderer.Apply(images) end
    end
    state.Draw = draw
    local function refreshed()
        state.Revision += 1
        draw(nil)
    end
    local function watchAttr(attr: string, onChange: (() -> ())?)
        table.insert(state.Connections, character:GetAttributeChangedSignal(attr):Connect(onChange or refreshed))
    end
    -- Canonical clan attributes, including refresh mid-mode when 1->2->3 tomoe.
    for _, attr in ipairs({"SharinganTomoe", "MangekyoActive", "FaceExpression", "FaceDojutsu", "Status_Stunned", "IsStunned", "IsDowned"}) do
        watchAttr(attr)
    end
    for _, attr in ipairs({"SharinganActive", "ByakuganActive"}) do
        watchAttr(attr, function()
            if character:GetAttribute(attr) == true then
                state.ActivationUntil = workspace:GetServerTimeNow() + 0.55
                refreshed()
                task.delay(0.56, function()
                    if state.Alive then refreshed() end
                end)
            else
                refreshed()
            end
        end)
    end
    -- A single accepted M1 is replicated as a timestamp. Refresh again when
    -- its brief visual window expires, including for remote players and misses.
    watchAttr("FaceAttackAt", function()
        refreshed()
        task.delay(0.41, function()
            if state.Alive then refreshed() end
        end)
    end)
    if player == Players.LocalPlayer then watchAttr("IsAttacking") end
    for _, attr in pairs(STYLE_ATTR) do
        table.insert(state.Connections, player:GetAttributeChangedSignal(attr):Connect(refreshed))
    end
    for _, attr in ipairs({"CharacterEyeVariantId", "CharacterEyeStyleId"}) do
        table.insert(state.Connections, player:GetAttributeChangedSignal(attr):Connect(refreshed))
    end
    table.insert(state.Connections, character.Destroying:Connect(stop))
    if humanoid then
        table.insert(state.Connections, humanoid.Died:Connect(refreshed))
    end
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
            if not state.Head or expressionNow() ~= "neutral" then continue end
            local family = Integration.FamilyFromStyle(player:GetAttribute(STYLE_ATTR.ojos))
            local dojutsu = resolveDojutsu(player, character)
            if family and
                Integration.Image(Integration.Path(family, "ojos", "parpadeo_medio", dojutsu)) and
                Integration.Image(Integration.Path(family, "ojos", "parpadeo_cerrado", "comun")) then
                local version = state.Revision
                for _, frame in ipairs({{"parpadeo_medio", 0.05}, {"parpadeo_cerrado", 0.08}, {"parpadeo_medio", 0.05}}) do
                    if not state.Alive or version ~= state.Revision or expressionNow() ~= "neutral" then break end
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
        local s = states[player]; if s then s.Stop() end
    end))
    if player.Character then bind(player, player.Character) end
end
local function unwatch(player: Player)
    local s = states[player]; if s then s.Stop() end
    for _, c in ipairs(watching[player] or {}) do c:Disconnect() end
    watching[player] = nil
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(unwatch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
