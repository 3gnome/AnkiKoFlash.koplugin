local function run_tests(assert_eq, assert_true)
    local names = {
        "socket.http", "socket", "ltn12", "json", "gettext",
        "card_fields", "card_defaults", "note_type_profiles",
        "note_type_picker", "anki_sync", "privacy_log", "logger",
        "plugin_constants",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local last_payload
    local decoded_response
    local responses = {}
    local calls = {}
    local queries = {}

    local function enqueue(action, response)
        responses[action] = responses[action] or {}
        responses[action][#responses[action] + 1] = response
    end

    package.loaded["socket"] = { sleep = function() end }
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
            if value.action == "findNotes" then
                queries[#queries + 1] = value.params.query
            end
            return value.action
        end,
        decode = function() return decoded_response end,
    }
    package.loaded["socket.http"] = {
        request = function(request)
            local action = request.source
            calls[action] = (calls[action] or 0) + 1
            local queue = responses[action] or {}
            local response = table.remove(queue, 1)
            assert(response, "missing fake response for " .. tostring(action))
            if response.transport_error then
                return nil, response.transport_error
            end
            decoded_response = response.body
            request.sink("ok")
            return 1, 200
        end,
    }
    package.loaded["gettext"] = function(text) return text end
    package.loaded["card_defaults"] = {
        deck_for_card = function() return "Target" end,
    }
    package.loaded["card_fields"] = {
        normalize = function(card) return card end,
        default_vocabulary_model = function() return "Vocabulary Card" end,
        is_dictionary_card = function(card)
            return card and card.dictionary_only == true
        end,
        fields_for_send = function(card)
            return card.anki_fields or {}
        end,
        dictionary_fields_for_send = function(card)
            return card.anki_fields or {}
        end,
        sync_flat_from_anki = function() end,
    }
    package.loaded["note_type_profiles"] = {
        VOCABULARY_CARD_FIELDS = { "Phrase", "Definition", "Context" },
        normalize_model_name = function(value) return value end,
        is_vocabulary_card = function(value) return value == "Vocabulary Card" end,
    }
    package.loaded["note_type_picker"] = {
        fetch_field_names = function(_config, model)
            if model == "Basic" then return { "Front", "Back" } end
            if model == "Memorization" then
                return { "Title", "Target", "FullText", "LineIndex", "FullRecite" }
            end
            return { "Phrase", "Definition" }
        end,
    }
    package.loaded["privacy_log"] = {
        reason_code = function() return "test" end,
        warn = function() end,
    }
    package.loaded["anki_sync"] = nil

    local AnkiSync = require("anki_sync")
    local function ok_body(result)
        return { body = { result = result, error = nil } }
    end
    -- Mirror KOReader's LuaJSON: JSON `null` decodes to a sentinel function,
    -- not Lua nil. send_card_with_status must treat it as "no error".
    local JSON_NULL = function() return JSON_NULL end
    local function ok_body_null(result)
        return { body = { result = result, error = JSON_NULL } }
    end
    local function candidate(note_id, model, deck, fields)
        local info_fields = {}
        for name, value in pairs(fields) do
            info_fields[name] = { value = value }
        end
        enqueue("findNotes", ok_body({ note_id }))
        enqueue("notesInfo", ok_body({
            {
                noteId = note_id,
                modelName = model,
                fields = info_fields,
                cards = { note_id + 1000 },
            },
        }))
        enqueue("cardsInfo", ok_body({
            {
                cardId = note_id + 1000,
                note = note_id,
                deckName = deck,
            },
        }))
    end

    enqueue("addNote", ok_body(nil))
    local ok, err = AnkiSync.add_note("http://anki", {})
    assert_true(ok == nil, "nil addNote result is not success")
    assert_true(err:find("valid note ID", 1, true) ~= nil,
        "nil result reports malformed success response")

    enqueue("addNote", ok_body("123"))
    ok = AnkiSync.add_note("http://anki", {})
    assert_true(ok == nil, "string addNote result is not success")

    enqueue("addNote", ok_body(0))
    ok = AnkiSync.add_note("http://anki", {})
    assert_true(ok == nil, "zero addNote result is not success")

    enqueue("addNote", ok_body(12.5))
    ok = AnkiSync.add_note("http://anki", {})
    assert_true(ok == nil, "fractional addNote result is not success")

    enqueue("addNote", ok_body(math.huge))
    ok = AnkiSync.add_note("http://anki", {})
    assert_true(ok == nil, "non-finite addNote result is not success")

    enqueue("addNote", ok_body(123))
    ok, err = AnkiSync.add_note("http://anki", {})
    assert_true(ok, "positive integer addNote result succeeds")
    assert_true(err == nil, "valid note ID has no error")

    local card = {
        phrase = "alpha",
        model = "Vocabulary Card",
        anki_fields = { Phrase = "alpha", Definition = "meaning" },
    }
    local config = { url = "http://anki", subdeck_by_book = false }

    enqueue("createDeck", ok_body(1))
    enqueue("addNote", ok_body(124))
    local send_ok, send_err, send_status = AnkiSync.send_card(config, card, {
        deck = "Target",
        model = "Vocabulary Card",
        skip_sync = true,
    })
    assert_true(send_ok, "send_card accepts a valid numeric note ID")
    assert_eq(send_err, "", "valid send_card preserves empty sync suffix")
    assert_eq(send_status, "sent", "send_card exposes additive sent status")

    -- Regression: KOReader's LuaJSON decodes `"error": null` to a sentinel
    -- function, not nil. A successful addNote must still be reported "sent".
    enqueue("createDeck", ok_body(1))
    enqueue("addNote", ok_body_null(126))
    local null_send_ok, null_send_err, null_send_status =
        AnkiSync.send_card(config, card, {
            deck = "Target",
            model = "Vocabulary Card",
            skip_sync = true,
        })
    assert_true(null_send_ok, "send_card accepts addNote with JSON-null error field")
    assert_eq(null_send_status, "sent",
        "JSON-null error field is reported as sent, not failed")

    enqueue("createDeck", ok_body(1))
    enqueue("addNote", ok_body({ noteId = 125 }))
    send_ok, send_err = AnkiSync.send_card(config, card, {
        deck = "Target",
        model = "Vocabulary Card",
        skip_sync = true,
    })
    assert_true(send_ok == nil, "send_card rejects malformed table note ID")
    assert_true(send_err:find("remains pending", 1, true) ~= nil,
        "malformed send_card response retains pending state")

    enqueue("createDeck", ok_body(1))
    enqueue("addNote", { transport_error = "timeout" })
        candidate(10, "Vocabulary Card", "Target",
        { Phrase = "alpha", Definition = "meaning" })
    local status = AnkiSync.send_card_with_status(config, card, {
        deck = "Target",
        model = "Vocabulary Card",
    })
    assert_eq(status, "verified",
        "timeout accepted by Anki is recovered by exact verification")

    enqueue("createDeck", ok_body(1))
    enqueue("addNote", { transport_error = "connection closed" })
        candidate(11, "Vocabulary Card", "Target",
        { Phrase = "alpha broader", Definition = "meaning" })
    local rejected_status, _deck, _model, rejected_err =
        AnkiSync.send_card_with_status(config, card, {
            deck = "Target",
            model = "Vocabulary Card",
        })
    assert_eq(rejected_status, "failed",
        "timeout without exact note remains failed")
    assert_true(rejected_err:find("remains pending", 1, true) ~= nil,
        "ambiguous rejected send clearly remains pending")

    enqueue("createDeck", ok_body(1))
    enqueue("addNote", {
        body = { result = nil, error = "cannot create note because it is a duplicate" },
    })
        candidate(12, "Vocabulary Card", "Target",
        { Phrase = "alpha", Definition = "meaning" })
    status = AnkiSync.send_card_with_status(config, card, {
        deck = "Target",
        model = "Vocabulary Card",
    })
    assert_eq(status, "duplicate",
        "duplicate response recovers only after exact verification")

    local find_calls_before = calls.findNotes or 0
    enqueue("createDeck", ok_body(1))
    enqueue("addNote", ok_body(nil))
    status = AnkiSync.send_card_with_status(config, card, {
        deck = "Target",
        model = "Vocabulary Card",
    })
    assert_eq(status, "failed", "malformed send response is ambiguous failure")
    assert_eq(calls.findNotes or 0, find_calls_before,
        "malformed HTTP 200 response does not trigger queue reconciliation")

        candidate(20, "Vocabulary Card", "Target",
        { Phrase = "alpha expanded", Definition = "meaning" })
    local exists = AnkiSync.note_exists_in_deck(
        "http://anki", "Target", "Vocabulary Card", "alpha*", "Phrase",
        { Phrase = "alpha*", Definition = "meaning" })
    assert_true(not exists,
        "wildcard search hit is rejected when field value is not exact")

        candidate(21, "Vocabulary Card", "Target::Child",
        { Phrase = "alpha", Definition = "meaning" })
    exists = AnkiSync.note_exists_in_deck(
        "http://anki", "Target", "Vocabulary Card", "alpha", "Phrase",
        { Phrase = "alpha", Definition = "meaning" })
    assert_true(not exists, "broader deck search hit requires exact target deck")

    candidate(22, "Basic", "Custom",
        { Front = "Question?", Back = "Answer." })
    exists = AnkiSync.note_exists_in_deck(
        "http://anki", "Custom", "Basic", "Question?", "Phrase",
        { Front = "Question?", Back = "Answer." })
    assert_true(exists,
        "custom note type matches its exact intended fields and model")
    assert_true(queries[#queries]:find("Front:", 1, true) ~= nil,
        "custom verification anchors search on an actual intended field")

    candidate(23, "Memorization", "Poetry",
        {
            Title = "Poem",
            Target = "line",
            FullText = "whole poem",
            LineIndex = "1",
            FullRecite = "",
        })
    exists = AnkiSync.note_exists_in_deck(
        "http://anki", "Poetry", "Memorization", "Poem", "Title",
        {
            Title = "Poem",
            Target = "line",
            FullText = "whole poem",
            LineIndex = "1",
            FullRecite = "",
        })
    assert_true(exists, "memorization identity supports exact full field matching")

    assert_eq(calls.addNote, 13, "each addNote write is attempted exactly once")

    -- Non-object JSON body must not leak into callers that assume a table.
    enqueue("deckNames", { body = "not an object" })
    local deck_names, deck_names_err = AnkiSync.get_deck_names("http://anki")
    assert_true(deck_names == nil, "non-object response is rejected")
    assert_true(deck_names_err:find("not an object", 1, true) ~= nil,
        "non-object response reports a clear error")

    -- "Cannot reach Anki" is definitive: skip the verification round-trip.
    local reach_calls_before = calls.findNotes or 0
    enqueue("createDeck", ok_body(1))
    enqueue("addNote", { transport_error = "connection refused" })
    local unreachable_status = AnkiSync.send_card_with_status(config, card, {
        deck = "Target",
        model = "Vocabulary Card",
    })
    assert_eq(unreachable_status, "failed",
        "unreachable send fails cleanly")
    assert_eq(calls.findNotes or 0, reach_calls_before,
        "unreachable send skips the verification round-trip")

    package.loaded["anki_sync"] = nil
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

return run_tests
