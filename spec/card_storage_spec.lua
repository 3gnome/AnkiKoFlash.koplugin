#!/usr/bin/env luajit

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[deep_copy(key)] = deep_copy(child)
    end
    return copy
end

local function run_tests(assert_eq, assert_true)
    local TempDir = require("temp_dir")
    local TestSupport = require("test_support")
    local owner = TempDir.new("ankikoflash card storage spec")
    return owner:with_temp_dir(function(data_dir)
    local names = {
        "card_storage", "atomic_json", "datastorage", "json", "logger", "gettext",
        "card_fields", "note_type_profiles", "llm_response_validator",
    }
    return TestSupport.with_package_loaded(names, {}, function()

    local encoded = {}
    local next_id = 0
    local decode_calls = 0
    package.loaded["datastorage"] = {
        getDataDir = function() return data_dir end,
    }
    package.loaded["json"] = {
        encode = function(value)
            next_id = next_id + 1
            local key = "snapshot-" .. tostring(next_id)
            encoded[key] = deep_copy(value)
            return key
        end,
        decode = function(key)
            decode_calls = decode_calls + 1
            return deep_copy(encoded[key])
        end,
    }
    package.loaded["logger"] = { warn = function() end }
    package.loaded["gettext"] = function(text) return text end
    package.loaded["card_storage"] = nil
    package.loaded["atomic_json"] = nil
    package.loaded["card_fields"] = nil

    local CardStorage = require("card_storage")
    local AtomicJson = require("atomic_json")
    local cards_path = data_dir .. "/ankikoflash_cards.json"
    local settings_path = data_dir .. "/ankikoflash_settings.json"

    local function write_snapshot(key, value)
        encoded[key] = deep_copy(value)
        local f = assert(io.open(cards_path, "wb"))
        assert(f:write(key))
        assert(f:close())
    end

    local empty_cards, load_status = CardStorage.load_cards()
    assert_eq(#empty_cards, 0, "absent queue loads as empty for public API")
    assert_eq(load_status, "absent", "load distinguishes absent queue")
    local empty_file = assert(io.open(cards_path, "wb"))
    assert(empty_file:close())
    empty_cards, load_status = CardStorage.load_cards()
    assert_eq(#empty_cards, 0, "empty queue loads as empty for public API")
    assert_eq(load_status, "empty", "load distinguishes empty queue")
    assert(os.remove(cards_path))

    write_snapshot("interrupted-reader", {
        { phrase = "recovered" },
    })
    local recovery_backup = AtomicJson.backup_path(cards_path)
    assert(os.rename(cards_path, recovery_backup))
    local recovered_cards, recovered_status = CardStorage.load_cards()
    assert_eq(recovered_status, "ok",
        "storage reader restores missing canonical before decoding")
    assert_eq(recovered_cards[1].phrase, "recovered",
        "storage reader returns recovered canonical data")
    local recovered_file = io.open(cards_path, "rb")
    assert_true(recovered_file ~= nil,
        "storage reader recreates canonical file from owned backup")
    assert(recovered_file:close())
    assert_true(io.open(recovery_backup, "rb") == nil,
        "storage reader consumes recovered backup")
    assert(os.remove(cards_path))

    assert_true(CardStorage.save_or_update({ phrase = "alpha" }),
        "first test card saved")
    assert_true(CardStorage.save_or_update({ phrase = "beta" }),
        "second test card saved")
    assert_true(CardStorage.save_or_update({ phrase = "gamma" }),
        "third test card saved")

    for _, invalid in ipairs({ 0, -1, 1.5, 4, "1" }) do
        assert_true(not CardStorage.delete_card(invalid),
            "invalid delete index is rejected: " .. tostring(invalid))
    end
    assert_true(not CardStorage.delete_card(nil), "nil delete index is rejected")
    assert_eq(#CardStorage.load_cards(), 3,
        "invalid deletes leave card storage unchanged")

    assert_true(CardStorage.delete_at_index(2),
        "valid 1-based delete_at_index succeeds")
    local cards = CardStorage.load_cards()
    assert_eq(#cards, 2, "valid indexed delete removes one card")
    assert_eq(cards[2].phrase, "gamma", "valid indexed delete removes target")

    CardStorage.clear_all()
    CardStorage.save_or_update({ phrase = "alpha" })
    CardStorage.save_or_update({ phrase = "beta" })
    CardStorage.save_or_update({ phrase = "gamma" })
    local captured_beta = CardStorage.load_cards()[2]
    assert_true(CardStorage.delete_card(1), "earlier row deletion succeeds")
    assert_true(CardStorage.delete_matching_card(captured_beta),
        "identity deletion survives stale captured index")
    cards = CardStorage.load_cards()
    assert_eq(#cards, 1, "identity deletion removes one shifted card")
    assert_eq(cards[1].phrase, "gamma",
        "identity deletion removes captured card, not replacement index")

    CardStorage.clear_all()
    CardStorage.save_or_update({
        card_kind = "memorization",
        phrase = "Memorization: shared label",
        memorization_text = " First\n passage ",
        book_title = "Book A",
    })
    CardStorage.save_or_update({
        card_kind = "memorization",
        phrase = "Memorization: shared label",
        memorization_text = "Second passage",
        book_title = "Book A",
    })
    cards = CardStorage.load_cards()
    assert_eq(#cards, 2, "separate memorization passages remain separate")
    assert_true(CardStorage.same_card(cards[1], {
        card_kind = "memorization",
        memorization_text = "first passage",
        book_title = "Book A",
    }, true), "memorization identity normalizes passage whitespace")
    assert_true(not CardStorage.same_card(cards[1], {
        card_kind = "memorization",
        memorization_text = "first passage",
        book_title = "Book B",
    }, true), "memorization identity can include book")
    assert_true(CardStorage.same_card(
        { phrase = " Word ", book_title = "Book A" },
        { phrase = "word", book_title = "Book A" }, true),
        "legacy wiki/vocabulary identity remains phrase and book")

    CardStorage.clear_all()
    local pdf_pos0 = { page = 8, x = 12.5, y = 40 }
    local pdf_pos1 = { page = 8, x = 88.5, y = 40 }
    CardStorage.save_or_update({
        phrase = "PDF position",
        book_title = "PDF Book",
        document_path = "/books/pdf-book.pdf",
        highlight_pos0 = pdf_pos0,
        highlight_pos1 = pdf_pos1,
    })
    local roundtrip_pos0 =
        package.loaded["json"].decode(package.loaded["json"].encode(pdf_pos0))
    local roundtrip_pos1 =
        package.loaded["json"].decode(package.loaded["json"].encode(pdf_pos1))
    local positioned = CardStorage.find_by_position(
        roundtrip_pos0, roundtrip_pos1, "/books/pdf-book.pdf")
    assert_true(positioned ~= nil,
        "find_by_position matches JSON-roundtrip PDF positions")
    assert_eq(positioned.document_path, "/books/pdf-book.pdf",
        "card serialization preserves additive document path")
    assert_true(CardStorage.find_by_position(
        roundtrip_pos0, { page = 8, x = 99, y = 40 },
        "/books/pdf-book.pdf") == nil,
        "supplied pos1 mismatch never falls back to same-pos0 card")
    CardStorage.save_or_update({
        phrase = "Other PDF position",
        book_title = "Other PDF Book",
        document_path = "/books/other.pdf",
        highlight_pos0 = pdf_pos0,
        highlight_pos1 = pdf_pos1,
    })
    CardStorage.save_or_update({
        phrase = "Legacy unscoped position",
        book_title = "Legacy PDF Book",
        highlight_pos0 = pdf_pos0,
        highlight_pos1 = pdf_pos1,
    })
    positioned = CardStorage.find_by_position(
        roundtrip_pos0, roundtrip_pos1, "/books/other.pdf")
    assert_eq(positioned.phrase, "Other PDF position",
        "same structural positions resolve only inside the exact document")
    assert_true(CardStorage.find_by_position(
        roundtrip_pos0, roundtrip_pos1, "/books/missing.pdf") == nil,
        "position lookup cannot fall through to another document")
    assert_true(CardStorage.find_by_position(
        roundtrip_pos0, roundtrip_pos1, nil) == nil,
        "position lookup requires document identity")
    assert_eq(CardStorage.find_by_phrase_fuzzy(
        "Other PDF position", "/books/other.pdf").phrase,
        "Other PDF position",
        "tap phrase fallback resolves only within the exact document")
    assert_true(CardStorage.find_by_phrase_fuzzy(
        "Other PDF position", "/books/pdf-book.pdf") == nil,
        "tap phrase fallback cannot cross document identity")
    assert_true(CardStorage.find_by_phrase_fuzzy(
        "Legacy unscoped position", "/books/pdf-book.pdf") == nil,
        "tap phrase fallback skips legacy unscoped cards")
    assert_true(CardStorage.find_by_phrase_fuzzy(
        "Other PDF position", "") == nil,
        "tap phrase fallback rejects empty document identity")

    write_snapshot("same-document-tap-positions", {
        {
            phrase = "duplicate text",
            document_path = "/books/duplicates.epub",
            highlight_pos0 = "/body/DocFragment[1]",
            highlight_pos1 = "/body/DocFragment[2]",
            definition = "first position",
        },
        {
            phrase = "duplicate text",
            document_path = "/books/duplicates.epub",
            highlight_pos0 = "/body/DocFragment[3]",
            highlight_pos1 = "/body/DocFragment[4]",
            definition = "second position",
        },
    })
    local tapped = CardStorage.find_for_highlight(
        "duplicate text", "/books/duplicates.epub",
        "/body/DocFragment[3]", "/body/DocFragment[4]")
    assert_eq(tapped.definition, "second position",
        "tap lookup selects exact same-document duplicate position")
    assert_true(CardStorage.find_for_highlight(
        "duplicate text", "/books/duplicates.epub",
        "/body/DocFragment[5]", "/body/DocFragment[6]") == nil,
        "strict tap never phrase-falls back to a differently positioned duplicate")

    write_snapshot("legacy-tap-fallback", {
        {
            phrase = "duplicate text",
            document_path = "/books/duplicates.epub",
            highlight_pos0 = "/body/DocFragment[1]",
            highlight_pos1 = "/body/DocFragment[2]",
            definition = "positioned",
        },
        {
            phrase = "duplicate text",
            document_path = "/books/duplicates.epub",
            definition = "same-document legacy",
        },
        {
            phrase = "duplicate text",
            document_path = "/books/other-duplicates.epub",
            definition = "other-document legacy",
        },
    })
    tapped = CardStorage.find_for_highlight(
        "duplicate text", "/books/duplicates.epub",
        "/body/DocFragment[5]", "/body/DocFragment[6]")
    assert_eq(tapped.definition, "same-document legacy",
        "strict tap may fall back to a same-document legacy card")
    assert_true(CardStorage.find_for_highlight(
        "duplicate text", "/books/missing.epub",
        "/body/DocFragment[5]", "/body/DocFragment[6]") == nil,
        "legacy tap fallback remains exact-document scoped")

    CardStorage.save_or_update({
        phrase = "EPUB position",
        book_title = "EPUB Book",
        document_path = "/books/epub-book.epub",
        highlight_pos0 = "/body/DocFragment[4]",
        highlight_pos1 = "/body/DocFragment[5]",
    })
    assert_true(CardStorage.find_by_position(
        "/body/DocFragment[4]", "/body/DocFragment[5]",
        "/books/epub-book.epub") ~= nil,
        "document-scoped lookup preserves string positions")

    CardStorage.save_or_update({
        phrase = "Custom term",
        definition = "Custom definition",
        context = "Custom passage",
        model = "Basic",
        target_model = "Basic",
        target_deck = "Vocabulary::Final",
        card_kind = "vocabulary",
        dictionary_only = true,
        dictionary_name = "Test Dictionary",
        document_path = "/books/vocab.epub",
        anki_fields = {
            Front = "Custom term",
            Back = "Custom definition\n\nCustom passage",
            Extra = "Retained custom value",
        },
    })
    local vocabulary = CardStorage.find_by_phrase(
        "Custom term", "/books/vocab.epub")
    assert_true(vocabulary.dictionary_only,
        "vocabulary roundtrip retains dictionary classification")
    assert_eq(vocabulary.dictionary_name, "Test Dictionary",
        "vocabulary roundtrip retains dictionary name")
    assert_eq(vocabulary.target_deck, "Vocabulary::Final",
        "vocabulary roundtrip retains final target deck")
    assert_eq(vocabulary.anki_fields.Front, "Custom term",
        "vocabulary roundtrip retains custom Front")
    assert_eq(vocabulary.anki_fields.Back,
        "Custom definition\n\nCustom passage",
        "vocabulary roundtrip retains custom Back")
    assert_eq(vocabulary.anki_fields.Extra, "Retained custom value",
        "vocabulary roundtrip retains complete custom fields")
    local CardFields = require("card_fields")
    assert_true(CardFields.is_dictionary_card(vocabulary, {}),
        "reloaded Basic vocabulary still classifies as vocabulary")
    local basic_fields = CardFields.dictionary_fields_for_send(
        vocabulary, { "Front", "Back" })
    assert_eq(basic_fields.Front, "Custom term",
        "reloaded Basic vocabulary routes the term to Front")
    assert_eq(basic_fields.Back,
        "Custom definition\n\nCustom passage",
        "reloaded Basic vocabulary routes definition and passage to Back")

    assert_true(CardStorage.save_memorization_pending(
        "Actual stored passage", {
            title = "Retry passage",
            book_title = "Memory Book",
            document_path = "/books/memory.epub",
            highlight_pos0 = { page = 12, x = 10 },
            highlight_pos1 = { page = 12, x = 90 },
        }, "Memorize::Memory Book"), "memorization retry saves")
    local pending_memory
    for _, entry in ipairs(CardStorage.load_cards()) do
        if entry.card_kind == "memorization"
            and entry.memorization_text == "Actual stored passage" then
            pending_memory = entry
            break
        end
    end
    assert_true(pending_memory ~= nil,
        "memorization retry roundtrip retains passage")
    assert_eq(pending_memory.document_path, "/books/memory.epub",
        "memorization retry roundtrip retains document identity")
    assert_eq(pending_memory.highlight_pos0.page, 12,
        "memorization retry roundtrip retains structural pos0")
    assert_eq(pending_memory.highlight_pos1.x, 90,
        "memorization retry roundtrip retains structural pos1")

    assert_true(CardStorage.record_recent_sent({
        phrase = "PDF position",
        card_kind = "vocabulary",
        document_path = "/books/pdf-book.pdf",
        highlight_pos0 = pdf_pos0,
        highlight_pos1 = pdf_pos1,
    }), "recent sent entry with document path saves")
    local recent = CardStorage.load_recent_sent()
    assert_eq(recent[1].document_path, "/books/pdf-book.pdf",
        "recent sent history preserves source document path")
    assert_true(CardStorage.record_recent_sent({
        phrase = "Memorization: display label",
        memorization_text = "Actual stored passage",
        card_kind = "memorization",
        document_path = "/books/memory.epub",
        highlight_pos0 = "m0",
        highlight_pos1 = "m1",
    }), "memorization history saves actual passage")
    recent = CardStorage.load_recent_sent()
    assert_eq(recent[1].memorization_text, "Actual stored passage",
        "memorization history roundtrip retains actual passage text")

    write_snapshot("duplicate-mem", {
        {
            card_kind = "memorization",
            phrase = "Memorization: same",
            memorization_text = "Same passage",
            book_title = "Book A",
        },
        {
            card_kind = "memorization",
            phrase = "Memorization: same",
            memorization_text = " same\npassage ",
            book_title = "Book A",
        },
        {
            card_kind = "memorization",
            phrase = "Memorization: same",
            memorization_text = "Different passage",
            book_title = "Book A",
        },
    })
    cards = CardStorage.load_cards()
    local duplicate = CardStorage.find_pending_duplicate(
        cards[1].phrase, cards[1].book_title, cards[1])
    assert_true(duplicate ~= nil, "duplicate lookup finds second mem identity")
    assert_eq(duplicate.memorization_text, " same\npassage ",
        "duplicate lookup does not confuse same-label mem passages")
    assert_true(CardStorage.delete_matching_card(cards[3]),
        "identity deletion removes matching mem passage")
    cards = CardStorage.load_cards()
    assert_eq(#cards, 2, "mem identity deletion removes one row")
    assert_eq(cards[1].memorization_text, "Same passage",
        "mem identity deletion preserves other passage")

    write_snapshot("bulk-delete", {
        { phrase = "keep one", book_title = "A" },
        { phrase = "remove one", book_title = "B" },
        { phrase = "remove two", book_title = "B" },
    })
    local original_write = AtomicJson.write
    local write_calls = 0
    AtomicJson.write = function(path, value, opts)
        write_calls = write_calls + 1
        return original_write(path, value, opts)
    end
    local before_decode = decode_calls
    local deleted, deleted_count = CardStorage.delete_where(function(card)
        return card.book_title == "B"
    end)
    assert_true(deleted, "bulk predicate delete succeeds")
    assert_eq(deleted_count, 2, "bulk predicate reports removed count")
    assert_eq(decode_calls - before_decode, 1,
        "bulk predicate delete loads the queue once")
    assert_eq(write_calls, 1, "bulk predicate delete writes once")
    cards = CardStorage.load_cards()
    assert_eq(#cards, 1, "bulk predicate delete filters all matches")
    assert_eq(cards[1].phrase, "keep one", "bulk predicate preserves nonmatches")

    write_snapshot("phrase-delete", {
        { phrase = "walking", book_title = "A" },
        { phrase = "keep", book_title = "A" },
    })
    write_calls = 0
    before_decode = decode_calls
    deleted = CardStorage.delete_by_phrase("walked")
    assert_true(deleted, "fuzzy phrase delete succeeds")
    assert_eq(decode_calls - before_decode, 1,
        "phrase delete loads the queue once")
    assert_eq(write_calls, 1, "phrase delete writes once")
    cards = CardStorage.load_cards()
    assert_eq(#cards, 1, "phrase delete removes one fuzzy match")
    assert_eq(cards[1].phrase, "keep", "phrase delete preserves other rows")

    write_snapshot("document-phrase-delete", {
        {
            phrase = "shared phrase",
            book_title = "Book A",
            document_path = "/books/a.epub",
            highlight_pos0 = "/body/DocFragment[1]",
            highlight_pos1 = "/body/DocFragment[2]",
        },
        {
            phrase = "shared phrase",
            book_title = "Book A",
            document_path = "/books/a.epub",
            highlight_pos0 = "/body/DocFragment[3]",
            highlight_pos1 = "/body/DocFragment[4]",
        },
        {
            phrase = "shared phrase",
            book_title = "Book B",
            document_path = "/books/b.epub",
        },
        {
            phrase = "shared phrase",
            book_title = "Legacy Positioned Book",
            document_path = "/books/a.epub",
        },
        {
            phrase = "shared phrase",
            book_title = "Legacy Book",
        },
    })
    deleted = CardStorage.delete_by_phrase_in_document(
        "shared phrase", "/books/a.epub",
        "/body/DocFragment[3]", "/body/DocFragment[4]")
    assert_true(deleted, "positioned document-scoped deletion succeeds")
    cards = CardStorage.load_cards()
    assert_eq(#cards, 4, "positioned document deletion removes one row")
    assert_eq(cards[1].highlight_pos0, "/body/DocFragment[1]",
        "same-document duplicate text at another position survives deletion")
    assert_eq(cards[2].document_path, "/books/b.epub",
        "same phrase in another document survives deletion")
    assert_true(cards[3].highlight_pos0 == nil,
        "same-document legacy same-phrase row survives strict deletion")
    assert_true(cards[4].document_path == nil,
        "legacy unscoped same-phrase row survives deletion")
    local strict_reason
    deleted, strict_reason = CardStorage.delete_by_phrase_in_document(
        "shared phrase", "/books/a.epub",
        "/body/DocFragment[8]", "/body/DocFragment[9]")
    assert_true(not deleted,
        "missing strict position does not fall back to phrase deletion")
    assert_eq(strict_reason, "not_found",
        "missing strict deletion reports not found")
    assert_eq(#CardStorage.load_cards(), 4,
        "missing strict deletion preserves positioned and legacy duplicates")
    local scoped_reason
    deleted, scoped_reason = CardStorage.delete_by_phrase_in_document(
        "shared phrase", nil)
    assert_true(not deleted, "unscoped document deletion is rejected")
    assert_eq(scoped_reason, "invalid_document",
        "unscoped deletion reports safe document requirement")
    assert_eq(#CardStorage.load_cards(), 4,
        "invalid document cannot delete legacy or other-book rows")

    write_snapshot("bulk-write-failure", {
        { phrase = "remove", book_title = "B" },
        { phrase = "keep", book_title = "A" },
    })
    AtomicJson.write = function()
        return false, { code = "bulk_write_failure" }
    end
    local delete_reason, delete_detail
    deleted, delete_reason, delete_detail = CardStorage.delete_where(function(card)
        return card.book_title == "B"
    end)
    assert_true(not deleted, "bulk delete propagates write failure")
    assert_eq(delete_reason, "write_failed",
        "bulk delete returns stable write failure reason")
    assert_eq(delete_detail.code, "bulk_write_failure",
        "bulk delete preserves structured atomic detail")
    AtomicJson.write = original_write
    cards = CardStorage.load_cards()
    assert_eq(#cards, 2, "failed bulk delete preserves original queue")

    local legacy_rows = {
        {
            phrase = "Legacy wiki",
            book_title = "Old Book",
            definition = "Readable without migration",
            date = "2025-01-02",
        },
        {
            phrase = "Legacy vocabulary",
            book_title = "Old Book",
            ipa = "/old/",
        },
    }
    local fixture = assert(io.open("spec/fixtures/cards_v1.json", "rb"))
    local fixture_content = assert(fixture:read("*all"))
    assert(fixture:close())
    encoded[fixture_content] = deep_copy(legacy_rows)
    local legacy_file = assert(io.open(cards_path, "wb"))
    assert(legacy_file:write(fixture_content))
    assert(legacy_file:close())
    cards = CardStorage.load_cards()
    assert_eq(#cards, 2, "legacy rows remain readable")
    assert_eq(cards[1].definition, "Readable without migration",
        "legacy row fields are not rewritten")
    assert_true(cards[1].card_kind == nil,
        "reading legacy rows does not add schema fields")

    -- A malformed load and a failed purge save must both leave migration
    -- pending so the next ensure call retries.
    local malformed = assert(io.open(cards_path, "wb"))
    assert(malformed:write("not-a-snapshot"))
    assert(malformed:close())
    local purged, purge_reason = CardStorage.ensure_queue_migrated()
    assert_true(not purged, "malformed queue does not complete purge")
    assert_eq(purge_reason, "load_failed", "malformed purge reports load failure")

    write_snapshot("purge-rows", {
        { phrase = "pending" },
        { phrase = "accepted", sent_to_anki = true },
    })
    local fail_once = true
    AtomicJson.write = function(path, value, opts)
        if path == cards_path and fail_once then
            fail_once = false
            return false, { code = "injected_failure" }
        end
        return original_write(path, value, opts)
    end
    purged, purge_reason = CardStorage.ensure_queue_migrated()
    assert_true(not purged, "failed purge save does not complete migration")
    assert_eq(purge_reason, "write_failed", "failed purge reports write failure")
    assert_eq(#CardStorage.load_cards(), 2,
        "failed purge save preserves original queue")

    purged = CardStorage.ensure_queue_migrated()
    assert_true(purged, "purge retries after failed save")
    cards = CardStorage.load_cards()
    assert_eq(#cards, 1, "retry removes accepted compatibility row")
    assert_eq(cards[1].phrase, "pending", "retry preserves pending row")
    AtomicJson.write = original_write

    AtomicJson.write = function(path)
        if path == settings_path then
            return false, { code = "settings_write_failure" }
        end
        return false, { code = "unexpected_path" }
    end
    local settings_ok, settings_reason =
        CardStorage.save_anki_settings({ url = "http://127.0.0.1" })
    assert_true(not settings_ok, "settings propagate atomic write failure")
    assert_eq(settings_reason.code, "settings_write_failure",
        "settings return structured writer reason")
    AtomicJson.write = original_write

    -- ── Legacy filename migration (AnkiKOAi -> AnkiKoFlash) ──────────────────
    local function write_raw(path, content)
        local f = assert(io.open(path, "wb"))
        assert(f:write(content))
        assert(f:close())
    end
    local legacy_cards = data_dir .. "/ankikooai_cards.json"
    local legacy_settings = data_dir .. "/ankikooai_settings.json"
    local legacy_recent = data_dir .. "/ankikooai_recent_sent.json"

    os.remove(cards_path)
    os.remove(settings_path)
    os.remove(data_dir .. "/ankikoflash_recent_sent.json")

    write_raw(legacy_cards, "legacy-cards-content")
    write_raw(legacy_settings, "legacy-settings-content")
    write_raw(legacy_recent, "legacy-recent-content")

    assert_eq(CardStorage.migrate_legacy_files(), 3,
        "migration moves all three legacy files")
    assert_true(io.open(legacy_cards, "rb") == nil,
        "legacy cards file removed after migration")
    assert_true(io.open(legacy_settings, "rb") == nil,
        "legacy settings file removed after migration")
    assert_true(io.open(legacy_recent, "rb") == nil,
        "legacy recent file removed after migration")

    local moved_cards = io.open(cards_path, "rb")
    assert_true(moved_cards ~= nil,
        "migration creates the current cards file")
    assert_eq(assert(moved_cards:read("*all")), "legacy-cards-content",
        "migration preserves cards content verbatim")
    assert(moved_cards:close())

    local moved_settings = io.open(settings_path, "rb")
    assert_true(moved_settings ~= nil,
        "migration creates the current settings file")
    assert_eq(assert(moved_settings:read("*all")), "legacy-settings-content",
        "migration preserves settings content verbatim")
    assert(moved_settings:close())

    assert_eq(CardStorage.migrate_legacy_files(), 0,
        "migration is idempotent after a full move")

    write_raw(legacy_cards, "newer-legacy-cards")
    assert_eq(CardStorage.migrate_legacy_files(), 0,
        "migration never overwrites an existing current file")
    local kept = io.open(cards_path, "rb")
    assert_eq(assert(kept:read("*all")), "legacy-cards-content",
        "existing current file survives a later legacy file")
    assert(kept:close())
    assert_true(io.open(legacy_cards, "rb") ~= nil,
        "legacy file is preserved (renamed-only), not deleted, when current exists")
    assert(os.remove(legacy_cards))

    end)
    end)
end

return run_tests
