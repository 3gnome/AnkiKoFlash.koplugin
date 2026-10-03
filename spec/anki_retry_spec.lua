local function run_tests(assert_eq, assert_true)
    local saved = {}
    local names = {
        "socket.http", "socket", "ltn12", "json", "gettext",
        "card_fields", "card_defaults", "note_type_profiles",
        "anki_sync", "privacy_log", "logger", "plugin_constants",
    }
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local last_payload
    local deck_calls, add_calls, multi_calls = 0, 0, 0
    local sleeps = {}

    package.loaded["socket"] = {
        sleep = function(delay) sleeps[#sleeps + 1] = delay end,
    }
    package.loaded["ltn12"] = {
        source = { string = function(value) return value end },
        sink = {
            table = function(target)
                return function(chunk)
                    if chunk then target[#target + 1] = chunk end
                    return 1
                end
            end,
        },
    }
    package.loaded["json"] = {
        encode = function(value)
            last_payload = value
            return value.action
        end,
        decode = function()
            local action = last_payload.action
            if action == "deckNames" then
                return { result = { "Default" }, error = nil }
            elseif action == "multi" then
                local result = {}
                for i = 1, #(last_payload.params.actions or {}) do result[i] = i end
                return { result = result, error = nil }
            end
            return { result = true, error = nil }
        end,
    }
    package.loaded["socket.http"] = {
        request = function(request)
            local action = request.source
            if action == "deckNames" then
                deck_calls = deck_calls + 1
                if deck_calls < 3 then return nil, "timeout" end
                request.sink("ok")
                return 1, 200
            elseif action == "addNote" then
                add_calls = add_calls + 1
                return nil, "timeout"
            elseif action == "multi" then
                multi_calls = multi_calls + 1
                request.sink("ok")
                return 1, 200
            end
            request.sink("ok")
            return 1, 200
        end,
    }
    package.loaded["gettext"] = function(text) return text end
    package.loaded["card_fields"] = {}
    package.loaded["card_defaults"] = {}
    package.loaded["note_type_profiles"] = {}
    package.loaded["privacy_log"] = {
        reason_code = function() return "timeout" end,
        warn = function() end,
    }
    package.loaded["anki_sync"] = nil

    local Retry = require("anki_retry")
    assert_true(Retry.is_idempotent_read("version"), "version is a read")
    assert_true(Retry.is_idempotent_read("notesInfo"), "notesInfo is a read")
    assert_true(not Retry.is_idempotent_read("addNote"), "addNote is never retryable")
    assert_true(not Retry.is_idempotent_read("addNotes"), "addNotes is never retryable")
    assert_true(not Retry.is_idempotent_read("multi"), "multi is never retryable")
    assert_true(not Retry.is_idempotent_read("deleteNotes"), "delete is never retryable")
    assert_true(not Retry.is_idempotent_read("createDeck"), "create is never retryable")
    assert_true(Retry.is_transient_error("HTTP error: 408"),
        "request timeout status is retryable")
    assert_true(Retry.is_transient_error("HTTP error: 429"),
        "rate limit status is retryable")
    assert_true(Retry.is_transient_error("HTTP error: 503"),
        "selected server status is retryable")
    assert_true(not Retry.is_transient_error("HTTP error: 400"),
        "bad request is never retryable")
    assert_true(not Retry.is_transient_error("HTTP error: 401"),
        "authentication failure is never retryable")
    assert_true(not Retry.is_transient_error("HTTP error: 404"),
        "missing endpoint is never retryable")
    assert_true(not Retry.should_retry(
        "deckNames", "HTTP error: 400", 1, 3),
        "idempotent reads still reject permanent HTTP failures")

    local AnkiSync = require("anki_sync")
    local decks = AnkiSync.get_deck_names("http://anki")
    assert_eq(decks[1], "Default", "read succeeds after retry")
    assert_eq(deck_calls, 3, "read attempts are capped")
    assert_eq(#sleeps, 2, "bounded backoff runs between read attempts")

    local ok = AnkiSync.add_note("http://anki", {})
    assert_true(ok == nil, "ambiguous addNote fails")
    assert_eq(add_calls, 1, "addNote timeout is not retried")

    local notes = {}
    for i = 1, 121 do notes[i] = { fields = { Title = tostring(i) } } end
    local sent, failed = AnkiSync.add_notes_batch("http://anki", notes)
    assert_eq(sent, 121, "all chunked notes counted")
    assert_eq(failed, 0, "chunked notes have no failures")
    assert_eq(multi_calls, 3, "121 notes use 50/50/21 multi batches")

    package.loaded["anki_sync"] = nil
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

return run_tests
