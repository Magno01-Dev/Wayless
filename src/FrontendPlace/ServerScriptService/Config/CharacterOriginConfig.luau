--!strict
-- ServerScriptService > Config > CharacterOriginConfig

local Config = {}

Config.DataVersion = 1
Config.DataStoreName = "WAYLESS_CharacterOrigin_v1"

Config.SlotAttributeName = "CharacterSlotId"
Config.DefaultSlotId = "1"

Config.EnableStudioPersistence = false
Config.AutosaveSeconds = 60

Config.ThirdNatureChance = 0.03
Config.NaturalKGPotentialChance = 0.33

-- Deliberately empty until elemental KG combinations are actually defined.
Config.ElementalKGCombinations = {}

return Config
