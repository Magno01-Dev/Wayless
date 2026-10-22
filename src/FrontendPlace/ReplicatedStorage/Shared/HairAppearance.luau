--!nonstrict
-- WAYLESS HairAppearance v0.2 CANDIDATE — size restrictions disabled
-- Shared, pure cosmetic rules for FrontendPlace and WorldPlace.
-- Does not modify or scale the R6 body.
local HairAppearance = {}

HairAppearance.MaxHairIds = 4
-- IDs are deliberately stable, so hair selections persist when clan palette RGBs change.
-- Candidate palette: final hues still require owner visual QA.
HairAppearance.Palettes = {
    Uchiha = {
        {Id="01", Name="Jet Black", Color=Color3.fromRGB(18,18,23)},
        {Id="02", Name="Charcoal", Color=Color3.fromRGB(38,38,44)},
        {Id="03", Name="Black Plum", Color=Color3.fromRGB(51,43,56)},
    },
    Hyuga = {
        {Id="01", Name="Deep Black", Color=Color3.fromRGB(24,24,30)},
        {Id="02", Name="Ash Black", Color=Color3.fromRGB(46,43,49)},
        {Id="03", Name="Dark Brown", Color=Color3.fromRGB(75,56,51)},
    },
    Nara = {
        {Id="01", Name="Black", Color=Color3.fromRGB(25,24,25)},
        {Id="02", Name="Dark Brown", Color=Color3.fromRGB(58,41,32)},
        {Id="03", Name="Warm Brown", Color=Color3.fromRGB(87,62,44)},
    },
    Akimichi = {
        {Id="01", Name="Dark Chestnut", Color=Color3.fromRGB(69,42,37)},
        {Id="02", Name="Chestnut", Color=Color3.fromRGB(117,69,50)},
        {Id="03", Name="Warm Auburn", Color=Color3.fromRGB(140,76,49)},
    },
    Aburame = {
        {Id="01", Name="Jet Black", Color=Color3.fromRGB(22,23,26)},
        {Id="02", Name="Slate Black", Color=Color3.fromRGB(43,46,50)},
        {Id="03", Name="Ash Brown", Color=Color3.fromRGB(64,57,52)},
    },
    Inuzuka = {
        {Id="01", Name="Dark Brown", Color=Color3.fromRGB(62,43,37)},
        {Id="02", Name="Chestnut", Color=Color3.fromRGB(111,73,49)},
        {Id="03", Name="Black", Color=Color3.fromRGB(29,26,26)},
    },
    Hozuki = {
        {Id="01", Name="Ash White", Color=Color3.fromRGB(209,212,213)},
        {Id="02", Name="Silver Gray", Color=Color3.fromRGB(157,165,175)},
        {Id="03", Name="Pale Blue Gray", Color=Color3.fromRGB(182,196,204)},
    },
    Uzumaki = {
        {Id="01", Name="Crimson", Color=Color3.fromRGB(156,36,52)},
        {Id="02", Name="Copper Red", Color=Color3.fromRGB(197,76,54)},
        {Id="03", Name="Warm Blonde", Color=Color3.fromRGB(226,179,85)},
    },
}
HairAppearance.DefaultPalette = HairAppearance.Palettes.Nara

function HairAppearance.GetPalette(clanId)
    return HairAppearance.Palettes[clanId] or HairAppearance.DefaultPalette
end

function HairAppearance.ResolveColor(clanId, rawId)
    local palette = HairAppearance.GetPalette(clanId)
    local id = rawId
    if id == nil then id = "01" end -- legacy characters: stable default
    if typeof(id) ~= "string" then return nil, "InvalidHairColor" end
    for _, entry in ipairs(palette) do
        if entry.Id == id then return entry, "HairColorReady" end
    end
    return nil, "InvalidHairColor"
end

function HairAppearance.TintAccessory(accessory, color)
    if not accessory or not accessory:IsA("Accessory") or typeof(color) ~= "Color3" then
        return false
    end
    -- Remove color-map dependencies BEFORE tinting; tinting the original black
    -- texture would keep black hair black. Geometry and vertex normals remain.
    for _, descendant in ipairs(accessory:GetDescendants()) do
        if descendant:IsA("SurfaceAppearance") or descendant:IsA("Decal") or descendant:IsA("Texture") then
            descendant:Destroy()
        elseif descendant:IsA("SpecialMesh") then
            descendant.TextureId = ""
            descendant.VertexColor = Vector3.new(1, 1, 1)
        elseif descendant:IsA("BasePart") then
            if descendant:IsA("MeshPart") then
                descendant.TextureID = ""
            end
            descendant.Color = color
            descendant.Material = Enum.Material.SmoothPlastic
            descendant.Reflectance = 0
            descendant.CastShadow = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            -- Preserve original Transparency / DoubleSided to avoid changing geometry.
        end
    end
    return true
end

function HairAppearance.TintAvatarHair(avatar, color)
    if typeof(color) ~= "Color3" then return end
    for _, child in ipairs(avatar:GetChildren()) do
        if child:IsA("Accessory") then
            HairAppearance.TintAccessory(child, color)
        end
    end
end

return HairAppearance
