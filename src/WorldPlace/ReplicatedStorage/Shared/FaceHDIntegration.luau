--!strict
-- WAYLESS Face HD integration candidate v1.0
-- Shared by FrontendPlace and WorldPlace. This does NOT modify saved profiles.
local FaceHDAssets = require(script.Parent:WaitForChild("FaceHDAssets"))
local Integration = {}

local function validImage(value: any): string?
    if typeof(value) == "number" and value > 0 then
        return "rbxassetid://" .. tostring(math.floor(value))
    end
    if typeof(value) == "string" and value:match("^rbxassetid://[1-9]%d*$") then
        return value
    end
    return nil
end

function Integration.Image(path: string): string?
    return validImage(FaceHDAssets[path])
end

function Integration.IsFamily(family: any): boolean
    if typeof(family) ~= "string" then return false end
    local side, number = string.match(family, "^([MF])(%d+)$")
    local n = tonumber(number)
    return (side == "M" or side == "F") and n ~= nil and n >= 1 and n <= 10
end

function Integration.FamilyFromStyle(style: any): string?
    if typeof(style) ~= "string" then return nil end
    local family = string.match(style, "^HD_(.+)$")
    if Integration.IsFamily(family) then return family end
    return nil
end

function Integration.Style(family: string): string
    return "HD_" .. family
end

function Integration.Path(family: string, layer: string, state: string?, variant: string?): string
    if layer == "ojos" then
        return "assets/" .. family .. "/ojos/" .. (state or "neutral") .. "/" .. (variant or "normal") .. ".png"
    end
    return "assets/" .. family .. "/" .. layer .. "/" .. (state or "neutral") .. ".png"
end

function Integration.BaseImages(families: {[string]: string}): {[string]: string}?
    local images = {}
    for _, layer in ipairs({"cejas", "ojos", "nariz", "boca"}) do
        local family = families[layer]
        if not Integration.IsFamily(family) then return nil end
        local path = Integration.Path(family, layer, "neutral", "normal")
        local image = Integration.Image(path)
        if not image then return nil end
        images[layer] = image
    end
    return images
end

function Integration.IsNeutralReady(family: string): boolean
    if not Integration.IsFamily(family) then return false end
    return Integration.BaseImages({cejas = family, ojos = family, nariz = family, boca = family}) ~= nil
end

-- Retains every historic option and stable ID; new options only appear once
-- all four neutral PNGs of a family have valid asset IDs.
function Integration.RegisterCatalog(catalog: any)
    if catalog._WaylessFaceHDRegistered then return end
    catalog._WaylessFaceHDRegistered = true
    local insertionIndex = 1
    for _, side in ipairs({"M", "F"}) do
        for n = 1, 10 do
            local family = side .. tostring(n)
            if Integration.IsNeutralReady(family) then
                local id = Integration.Style(family)
                local display = "FACE HD " .. family
                table.insert(catalog.BrowStyles, insertionIndex, {Id = id, DisplayName = display, Image = Integration.Image(Integration.Path(family, "cejas", "neutral")), Enabled = true})
                table.insert(catalog.NoseStyles, insertionIndex, {Id = id, DisplayName = display, Image = Integration.Image(Integration.Path(family, "nariz", "neutral")), Enabled = true})
                table.insert(catalog.MouthStyles, insertionIndex, {Id = id, DisplayName = display, Image = Integration.Image(Integration.Path(family, "boca", "neutral")), Enabled = true})
                table.insert(catalog.EyeStyles, insertionIndex, {Id = id, DisplayName = display, Image = Integration.Image(Integration.Path(family, "ojos", "neutral", "normal")), Variants = {
                    Sharingan = Integration.Image(Integration.Path(family, "ojos", "neutral", "sharingan_3")),
                }, Enabled = true})
                insertionIndex += 1
            end
        end
    end
end

return Integration
