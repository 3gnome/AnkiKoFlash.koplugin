local TestSupport = {}

local NIL = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

function TestSupport.with_package_loaded(names, replacements, callback)
    local saved = {}
    for _, name in ipairs(names or {}) do
        local value = package.loaded[name]
        saved[name] = value == nil and NIL or value
        package.loaded[name] = replacements and replacements[name] or nil
    end

    local results
    local ok, callback_error = xpcall(function()
        results = pack(callback())
    end, debug.traceback)

    for _, name in ipairs(names or {}) do
        if saved[name] == NIL then
            package.loaded[name] = nil
        else
            package.loaded[name] = saved[name]
        end
    end

    if not ok then error(callback_error, 0) end
    return unpack(results, 1, results.n)
end

return TestSupport
