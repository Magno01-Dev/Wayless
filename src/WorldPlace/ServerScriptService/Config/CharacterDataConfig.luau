--!strict
-- WAYLESS
-- CharacterDataConfig v1.0

local Config = {}

Config.DATASTORE_NAME = "WAYLESS_CharacterData_v1"
Config.KEY_PREFIX = "Player_"
Config.SCHEMA_VERSION = 1
Config.DEFAULT_SLOT_ID = "1"

Config.AUTOSAVE_SECONDS = 60
Config.SESSION_LOCK_LEASE_SECONDS = 180
Config.LOAD_RETRIES = 4
Config.SAVE_RETRIES = 4
Config.RETRY_DELAY_SECONDS = 2

-- OFF by default so ordinary Studio Play tests do not write persistent data.
Config.ENABLE_STUDIO_PERSISTENCE = false
Config.DEBUG = true

return Config
