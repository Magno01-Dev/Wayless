--!nonstrict
-- WAYLESS HairAppearance v0.1 CANDIDATE
-- Shared, pure cosmetic rules for FrontendPlace and WorldPlace.
-- Does not modify or scale the R6 body.
local HairAppearance = {}

HairAppearance.MaxHairIds = 4
HairAppearance.Bounds = {
    X = 1.85,          -- local head X: maximum left/right extension
    MaxY = 1.85,       -- above head center
    MinY = -2.60,      -- long hair toward shoulders
    Z = 1.95,          -- front/back extension
    MaxParts = 36,
}

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

-- Bounds use the *loaded* and attached hair in an actual R6 model.
-- AABB of each BasePart is transformed into head-local coordinates.
-- For legacy SpecialMesh, include its Scale/Offset conservatively because
-- BasePart.Size alone may be much smaller than the rendered mesh.
function HairAppearance.ValidateAvatarHair(avatar, expectedCount)
    local head = avatar and avatar:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        return false, "HairHeadMissing"
    end
    local count, partCount = 0, 0
    local bound = HairAppearance.Bounds
    for _, child in ipairs(avatar:GetChildren()) do
        if child:IsA("Accessory") then
            count += 1
            local accessoryParts = 0
            for _, object in ipairs(child:GetDescendants()) do
                if object:IsA("BasePart") then
                    accessoryParts += 1
                    partCount += 1
                    if partCount > bound.MaxParts then
                        return false, "HairTooComplex"
                    end
                    local size = object.Size
                    local transform = object.CFrame
                    local special = object:FindFirstChildOfClass("SpecialMesh")
                    if special then
                        size = Vector3.new(
                            math.max(size.X, math.abs(special.Scale.X)),
                            math.max(size.Y, math.abs(special.Scale.Y)),
                            math.max(size.Z, math.abs(special.Scale.Z))
                        )
                        transform = transform * CFrame.new(special.Offset)
                    end
                    local half = size * 0.5
                    for _, ix in ipairs({-1, 1}) do
                        for _, iy in ipairs({-1, 1}) do
                            for _, iz in ipairs({-1, 1}) do
                                local point = head.CFrame:PointToObjectSpace(
                                    transform:PointToWorldSpace(Vector3.new(ix*half.X,iy*half.Y,iz*half.Z))
                                )
                                if math.abs(point.X) > bound.X
                                    or point.Y > bound.MaxY
                                    or point.Y < bound.MinY
                                    or math.abs(point.Z) > bound.Z then
                                    return false, "HairTooLarge"
                                end
                            end
                        end
                    end
                end
            end
            if accessoryParts == 0 then return false, "HairGeometryMissing" end
        end
    end
    if expectedCount ~= nil and count ~= expectedCount then
        return false, "HairAssetUnavailable"
    end
    return true, "HairSizeReady"
end

return HairAppearance
