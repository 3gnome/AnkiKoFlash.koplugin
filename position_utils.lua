-- Structural highlight-position comparison and deterministic keys.

local PositionUtils = {}

local function wrap(tag, payload)
    payload = payload or ""
    return tag .. tostring(#payload) .. ":" .. payload
end

local function serialize(value, stack)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then return wrap("d", string.format("%.17g", value)) end
    if kind == "string" then return wrap("s", value) end
    if kind ~= "table" then return wrap(kind:sub(1, 1), tostring(value)) end

    stack = stack or {}
    if stack[value] then return "c" end
    stack[value] = true

    local entries = {}
    for key, child in pairs(value) do
        local key_serialized = serialize(key, stack)
        local child_serialized = serialize(child, stack)
        entries[#entries + 1] = wrap("k", key_serialized)
            .. wrap("v", child_serialized)
    end
    table.sort(entries)
    stack[value] = nil
    return wrap("t", table.concat(entries))
end

function PositionUtils.key(position)
    return serialize(position)
end

function PositionUtils.equal(left, right)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    return serialize(left) == serialize(right)
end

function PositionUtils.pair_key(pos0, pos1)
    return wrap("0", serialize(pos0)) .. wrap("1", serialize(pos1))
end

return PositionUtils
