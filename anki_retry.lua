-- Pure retry policy for AnkiConnect. Write actions are never retryable.

local AnkiRetry = {}

AnkiRetry.MAX_ATTEMPTS = 3
AnkiRetry.BACKOFF_SECONDS = { 0.05, 0.10 }

local IDEMPOTENT_READ_ACTIONS = {
    version = true,
    deckNames = true,
    modelNames = true,
    modelFieldNames = true,
    findNotes = true,
    notesInfo = true,
    cardsInfo = true,
    findCards = true,
    getTags = true,
}

local RETRYABLE_HTTP_STATUS = {
    [408] = true,
    [429] = true,
    [500] = true,
    [502] = true,
    [503] = true,
    [504] = true,
}

function AnkiRetry.is_idempotent_read(action)
    return IDEMPOTENT_READ_ACTIONS[action] == true
end

function AnkiRetry.is_transient_error(err)
    if type(err) ~= "string" or err == "" then return false end
    local lower = err:lower()
    local status = tonumber(lower:match("^http error:%s*(%d%d%d)")
        or lower:match("^http%s+(%d%d%d)"))
    if status then return RETRYABLE_HTTP_STATUS[status] == true end
    return lower:find("cannot reach", 1, true) ~= nil
        or lower:find("timeout", 1, true) ~= nil
        or lower == "http error: closed"
        or lower:find("connection refused", 1, true) ~= nil
        or lower:find("connection reset", 1, true) ~= nil
        or lower:find("connection closed", 1, true) ~= nil
        or lower:find("unreachable", 1, true) ~= nil
        or lower:find("host not found", 1, true) ~= nil
        or lower:find("broken pipe", 1, true) ~= nil
end

function AnkiRetry.should_retry(action, err, attempt, max_attempts)
    max_attempts = tonumber(max_attempts) or AnkiRetry.MAX_ATTEMPTS
    return AnkiRetry.is_idempotent_read(action)
        and AnkiRetry.is_transient_error(err)
        and (tonumber(attempt) or 1) < max_attempts
end

-- call_fn returns the same (result, err) pair as the underlying request.
-- sleep_fn is injected so the policy remains deterministic in tests.
function AnkiRetry.run(action, call_fn, sleep_fn, max_attempts)
    max_attempts = tonumber(max_attempts) or AnkiRetry.MAX_ATTEMPTS
    local result, err
    for attempt = 1, max_attempts do
        result, err = call_fn(attempt)
        if result ~= nil
            or not AnkiRetry.should_retry(action, err, attempt, max_attempts) then
            return result, err, attempt
        end
        if sleep_fn then
            sleep_fn(AnkiRetry.BACKOFF_SECONDS[attempt]
                or AnkiRetry.BACKOFF_SECONDS[#AnkiRetry.BACKOFF_SECONDS])
        end
    end
    return result, err, max_attempts
end

return AnkiRetry
