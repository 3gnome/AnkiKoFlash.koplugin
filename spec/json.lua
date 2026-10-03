-- Minimal JSON codec for standalone specs. KOReader supplies `json` at runtime.

local Json = { null = {} }

local function decode_error(pos, message)
    error("JSON decode error at " .. tostring(pos) .. ": " .. message)
end

function Json.decode(source)
    local pos, length = 1, #source

    local function skip_space()
        local _, last = source:find("^[ \t\r\n]*", pos)
        pos = (last or (pos - 1)) + 1
    end

    local parse_value

    local function parse_string()
        if source:sub(pos, pos) ~= '"' then decode_error(pos, "expected string") end
        pos = pos + 1
        local out = {}
        while pos <= length do
            local ch = source:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif ch == "\\" then
                local esc = source:sub(pos + 1, pos + 1)
                local values = {
                    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
                    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
                }
                if esc == "u" then
                    local hex = source:sub(pos + 2, pos + 5)
                    if not hex:match("^%x%x%x%x$") then
                        decode_error(pos, "invalid unicode escape")
                    end
                    local code = tonumber(hex, 16)
                    if code < 128 then
                        out[#out + 1] = string.char(code)
                    elseif code < 2048 then
                        out[#out + 1] = string.char(
                            192 + math.floor(code / 64), 128 + code % 64)
                    else
                        out[#out + 1] = string.char(
                            224 + math.floor(code / 4096),
                            128 + math.floor(code / 64) % 64,
                            128 + code % 64)
                    end
                    pos = pos + 6
                elseif values[esc] then
                    out[#out + 1] = values[esc]
                    pos = pos + 2
                else
                    decode_error(pos, "invalid escape")
                end
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        decode_error(pos, "unterminated string")
    end

    local function parse_array()
        pos = pos + 1
        local result = {}
        skip_space()
        if source:sub(pos, pos) == "]" then pos = pos + 1; return result end
        while true do
            result[#result + 1] = parse_value()
            skip_space()
            local ch = source:sub(pos, pos)
            if ch == "]" then pos = pos + 1; return result end
            if ch ~= "," then decode_error(pos, "expected comma") end
            pos = pos + 1
        end
    end

    local function parse_object()
        pos = pos + 1
        local result = {}
        skip_space()
        if source:sub(pos, pos) == "}" then pos = pos + 1; return result end
        while true do
            skip_space()
            local key = parse_string()
            skip_space()
            if source:sub(pos, pos) ~= ":" then
                decode_error(pos, "expected colon")
            end
            pos = pos + 1
            result[key] = parse_value()
            skip_space()
            local ch = source:sub(pos, pos)
            if ch == "}" then pos = pos + 1; return result end
            if ch ~= "," then decode_error(pos, "expected comma") end
            pos = pos + 1
        end
    end

    parse_value = function()
        skip_space()
        local ch = source:sub(pos, pos)
        if ch == '"' then return parse_string() end
        if ch == "{" then return parse_object() end
        if ch == "[" then return parse_array() end
        if source:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
        if source:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
        if source:sub(pos, pos + 3) == "null" then pos = pos + 4; return Json.null end
        local number = source:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if number and number ~= "" then
            pos = pos + #number
            return tonumber(number)
        end
        decode_error(pos, "unexpected token")
    end

    local result = parse_value()
    skip_space()
    if pos <= length then decode_error(pos, "trailing data") end
    return result
end

local function encode_string(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(ch)
        local escapes = {
            ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
            ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
        }
        return escapes[ch] or string.format("\\u%04x", ch:byte())
    end) .. '"'
end

function Json.encode(value)
    local kind = type(value)
    if value == Json.null then return "null" end
    if kind == "nil" then return "null" end
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind == "string" then return encode_string(value) end
    if kind ~= "table" then error("unsupported JSON type") end
    local count, max = 0, 0
    for key in pairs(value) do
        count = count + 1
        if type(key) == "number" and key > max then max = key end
    end
    local parts = {}
    if count == max then
        for i = 1, max do parts[#parts + 1] = Json.encode(value[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
        parts[#parts + 1] = encode_string(tostring(key)) .. ":" .. Json.encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

return Json
