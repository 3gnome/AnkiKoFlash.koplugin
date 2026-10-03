-- Pure generation tokens for serial scheduled UI batch chains.

local BatchGeneration = {}

function BatchGeneration.new()
    return { generation = 0 }
end

function BatchGeneration.begin(state)
    state.generation = (state.generation or 0) + 1
    return state.generation
end

function BatchGeneration.is_current(state, token)
    return state ~= nil and token ~= nil and state.generation == token
end

function BatchGeneration.cancel(state, token)
    if not state then return false end
    if token ~= nil and state.generation ~= token then return false end
    state.generation = (state.generation or 0) + 1
    return true
end

function BatchGeneration.if_current(state, token, callback, ...)
    if not BatchGeneration.is_current(state, token) then return false end
    callback(...)
    return true
end

return BatchGeneration
