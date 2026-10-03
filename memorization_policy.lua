-- Pure limits/chunking policy shared by memorization UI and send paths.

local MemorizationPolicy = {}

MemorizationPolicy.DEFAULT_MAX_STEPS = 80
MemorizationPolicy.MULTI_BATCH_SIZE = 50

function MemorizationPolicy.max_steps(value)
    local n = tonumber(value)
    if not n or n < 1 then return MemorizationPolicy.DEFAULT_MAX_STEPS end
    return math.floor(n)
end

function MemorizationPolicy.requires_confirmation(step_count, configured_max)
    return (tonumber(step_count) or 0) > MemorizationPolicy.max_steps(configured_max)
end

function MemorizationPolicy.chunk(items, size)
    items = items or {}
    size = math.max(1, math.floor(tonumber(size)
        or MemorizationPolicy.MULTI_BATCH_SIZE))
    local chunks = {}
    for first = 1, #items, size do
        local chunk = {}
        for i = first, math.min(first + size - 1, #items) do
            chunk[#chunk + 1] = items[i]
        end
        chunks[#chunks + 1] = chunk
    end
    return chunks
end

return MemorizationPolicy
