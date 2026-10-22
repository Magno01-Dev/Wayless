--!strict
-- WAYLESS Clan Back Emblem v1 / shared by FrontendPlace and WorldPlace.
-- Cosmetic only. Single R6 Torso-mounted back decal. No profile writes.
local ClanBackEmblem = {}

local EMBLEMS: {[string]: {Normal: number, White: number?}} = {
    Uchiha  = {Normal = 88378610115045},
    Hyuga   = {Normal = 115351605032285},
    Nara    = {Normal = 83964381736190,  White = 91477586091255},
    Akimichi= {Normal = 109703424399060, White = 95724777326699},
    Aburame = {Normal = 73249868409053,  White = 123444311578954},
    Inuzuka = {Normal = 138312642811209, White = 86696623149878},
    Hozuki  = {Normal = 88489711913384,  White = 133128139064238},
    Uzumaki = {Normal = 83887466494363},
}

-- The back fabric darkness is classified by *TopId*, not by avatar skin or asset ID.
local DARK_TOP_IDS: {[string]: boolean} = {
    H01_TOP=true, H03_TOP=true, H04_TOP=true, H06_TOP=true, H11_TOP=true, H15_TOP=true,
    M01_TOP=true, M05_TOP=true, M06_TOP=true, M07_TOP=true, M08_TOP=true, M09_TOP=true,
}

local PLATE_NAME = "WAYLESS_ClanBackEmblem"
local DECAL_NAME = "ClanSymbol"

local function isWardrobeTop(topId: any): boolean
    if typeof(topId) ~= "string" then return false end
    -- H/M 01 through 15; all others (legacy, ANBU, U01) are unmapped.
    local side, rawNumber = string.match(topId, "^([HM])(%d%d)_TOP$")
    local n = tonumber(rawNumber)
    return (side == "H" or side == "M") and n ~= nil and n >= 1 and n <= 15
end

function ClanBackEmblem.Resolve(clanId: any, topId: any): string?
    if typeof(clanId) ~= "string" or not isWardrobeTop(topId) then return nil end
    local clan = EMBLEMS[clanId]
    if not clan then return nil end
    local chosen = if DARK_TOP_IDS[topId] and clan.White then clan.White else clan.Normal
    return "rbxassetid://" .. tostring(chosen)
end

function ClanBackEmblem.Remove(model: Model)
    local plate = model:FindFirstChild(PLATE_NAME)
    if plate then plate:Destroy() end
end

function ClanBackEmblem.Apply(model: Model, clanId: any, topId: any): boolean
    local texture = ClanBackEmblem.Resolve(clanId, topId)
    local torso = model:FindFirstChild("Torso")
    if not texture or not torso or not torso:IsA("BasePart") then
        ClanBackEmblem.Remove(model)
        return false
    end

    local plate = model:FindFirstChild(PLATE_NAME)
    if plate and not plate:IsA("Part") then
        -- Never modify a nonmatching live object with the same name.
        warn("[ClanBackEmblem] Unexpected plate type:", plate.ClassName)
        return false
    end
    if not plate then
        plate = Instance.new("Part")
        plate.Name = PLATE_NAME
        plate.Size = Vector3.new(0.8, 0.8, 0.001)
        plate.Transparency = 1
        plate.Material = Enum.Material.SmoothPlastic
        plate.CastShadow = false
        plate.CanCollide = false
        plate.CanTouch = false
        plate.CanQuery = false
        plate.Massless = true
        plate.Anchored = false
        -- R6 back is local +Z, upper back below shoulder line.
        -- The 0.018-stud lift keeps the decal above classic Shirt without z-fighting.
        plate.CFrame = torso.CFrame * CFrame.new(0, 0.26, torso.Size.Z/2 + 0.018)
        plate.Parent = model
        local weld = Instance.new("WeldConstraint")
        weld.Name = "TorsoWeld"
        weld.Part0 = torso
        weld.Part1 = plate
        weld.Parent = plate
        local decal = Instance.new("Decal")
        decal.Name = DECAL_NAME
        decal.Face = Enum.NormalId.Back  -- +Z face, NOT front-facing -Z.
        decal.Transparency = 0
        decal.Parent = plate
    end
    -- Reusing a plate after a Torso replacement is unusual but must stay correct.
    local weld = plate:FindFirstChild("TorsoWeld")
    if not weld or not weld:IsA("WeldConstraint") then
        warn("[ClanBackEmblem] Missing/unexpected TorsoWeld; leave existing plate untouched")
        return false
    end
    if weld.Part0 ~= torso then
        weld.Part0 = torso
        plate.CFrame = torso.CFrame * CFrame.new(0, 0.26, torso.Size.Z/2 + 0.018)
    end
    local decal = plate:FindFirstChild(DECAL_NAME)
    if not decal or not decal:IsA("Decal") then
        warn("[ClanBackEmblem] Missing/unexpected decal; no changes applied")
        return false
    end
    if decal.Texture ~= texture then decal.Texture = texture end
    return true
end

return ClanBackEmblem
