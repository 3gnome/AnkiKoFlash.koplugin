-- Structured logging that deliberately excludes user content and credentials.

local logger = require("logger")
local PluginConstants = require("plugin_constants")

local PrivacyLog = {}

local REDACTED_KEYS = {
    api_key = true, body = true, card = true, content = true,
    endpoint = true, highlight = true, phrase = true, prompt = true,
    request = true, response = true, text = true, url = true,
}

local function normalized_key(key)
    return tostring(key or ""):lower():gsub("[^%w_]", "_")
end

local function contains_sensitive_key(key)
    key = normalized_key(key)
    if REDACTED_KEYS[key] then return true end
    return key:find("api_key", 1, true) ~= nil
        or key:find("token", 1, true) ~= nil
        or key:find("secret", 1, true) ~= nil
        or key:find("password", 1, true) ~= nil
end

local function safe_value(key, value)
    if contains_sensitive_key(key) then return "[redacted]" end
    local kind = type(value)
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind ~= "string" then return "[redacted]" end
    if value:find("://", 1, true) or value:find("?", 1, true)
       or value:lower():find("authorization", 1, true)
       or value:lower():find("bearer ", 1, true)
       or value:lower():find("api_key", 1, true)
       or value:lower():find("apikey", 1, true) then
        return "[redacted]"
    end
    value = value:gsub("[%c%s]+", "_"):gsub("[^%w%._%-]", "_")
    if #value > 64 then value = value:sub(1, 64) end
    return value ~= "" and value or "empty"
end

function PrivacyLog.reason_code(reason)
    if type(reason) == "table" then reason = reason.code end
    local text = tostring(reason or "unknown"):lower()
    local http = text:match("http[^%d]*(%d%d%d)")
    if http then return "http_" .. http end
    if text:find("timeout", 1, true) then return "timeout" end
    if text:find("connection", 1, true) or text:find("unreachable", 1, true)
       or text:find("refused", 1, true) or text:find("closed", 1, true) then
        return "connection"
    end
    if text:find("rename", 1, true) then return "rename_failed" end
    if text:find("write", 1, true) then return "write_failed" end
    if text:find("read", 1, true) then return "read_failed" end
    return "other"
end

function PrivacyLog.warn(event, fields)
    local parts = { "event=" .. safe_value("event", event) }
    local keys = {}
    for key in pairs(fields or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = normalized_key(key) .. "=" .. safe_value(key, fields[key])
    end
    logger.warn(PluginConstants.ID, table.concat(parts, " "))
end

return PrivacyLog
