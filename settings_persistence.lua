-- Shared checked persistence for settings writes.

local CardStorage = require("card_storage")
local PrivacyLog  = require("privacy_log")
local _           = require("gettext")

local SettingsPersistence = {}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

SettingsPersistence.copy = copy

function SettingsPersistence.save(settings, operation)
    local ok, reason = CardStorage.save_anki_settings(settings)
    if ok then return true end
    PrivacyLog.warn("settings_storage_failed", {
        operation = operation or "settings",
        reason = PrivacyLog.reason_code(reason),
    })
    return false, reason, _(
        "Could not save settings to device storage. Check available space and write access, then retry.")
end

-- Persist a mutated candidate without exposing it to callers until the write
-- succeeds. The original settings table is never changed by this helper.
function SettingsPersistence.transaction(settings, mutate, operation)
    local candidate = copy(settings or {})
    local called, mutation_error = pcall(mutate, candidate)
    if not called then
        return false, nil, mutation_error
    end
    local ok, reason, message = SettingsPersistence.save(candidate, operation)
    if not ok then return false, nil, reason, message end
    return true, candidate
end

-- Preserve table identity for consumers that already hold a settings
-- reference, but only after transaction() has durably saved the candidate.
function SettingsPersistence.commit(target, candidate)
    if type(target) ~= "table" or type(candidate) ~= "table" then
        return candidate
    end
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(candidate) do target[key] = value end
    return target
end

return SettingsPersistence
