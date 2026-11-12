--!strict
-- Preserves existing DataStore names and keys while bounding retry and save work.
return table.freeze({
    INVENTORY_STORE = "EmoteData_v1", SETTINGS_STORE = "PlayerSettings_v1", KEY_PREFIX = "Player_",
    RETRIES = 3, RETRY_DELAY = 1, SAVE_DEBOUNCE = 3, AUTOSAVE_INTERVAL = 60,
    LOAD_TIMEOUT = 15, SHUTDOWN_TIMEOUT = 25,
})
