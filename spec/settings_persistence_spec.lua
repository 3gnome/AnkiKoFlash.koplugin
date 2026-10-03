local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = {
        "settings_persistence", "card_storage", "privacy_log", "gettext",
    }
    return TestSupport.with_package_loaded(names, {}, function()

    local state = { ok = true }
    local warnings = {}
    local last_saved
    package.loaded["card_storage"] = {
        save_anki_settings = function(settings)
            last_saved = settings
            return state.ok, state.reason
        end,
    }
    package.loaded["privacy_log"] = {
        reason_code = function() return "write_failed" end,
        warn = function(event, fields)
            warnings[#warnings + 1] = { event = event, fields = fields }
        end,
    }
    package.loaded["gettext"] = function(text) return text end
    package.loaded["settings_persistence"] = nil

    local Persistence = require("settings_persistence")
    local ok, reason, message = Persistence.save({}, "settings_viewer")
    assert_true(ok, "successful settings write is reported")
    assert_true(reason == nil and message == nil,
        "successful settings write has no failure metadata")

    state.ok = false
    state.reason = { code = "write_failed", detail = "private path" }
    ok, reason, message = Persistence.save({}, "settings_viewer")
    assert_true(not ok, "failed settings write is returned")
    assert_eq(reason.code, "write_failed", "structured storage reason is preserved")
    assert_true(message:find("Could not save settings", 1, true) ~= nil,
        "failure has a user-safe retryable message")
    assert_eq(warnings[#warnings].event, "settings_storage_failed",
        "storage failure emits a structured warning")
    assert_eq(warnings[#warnings].fields.reason, "write_failed",
        "warning contains only a reason code")

    state.ok = true
    local original = {
        target_language = "English",
        auto_send_vocabulary = false,
        vocabulary_deck = "Old deck",
        per_book_decks = { alpha = "Old deck" },
    }
    local committed, candidate = Persistence.transaction(original, function(next_cfg)
        next_cfg.target_language = "German"
        next_cfg.auto_send_vocabulary = true
        next_cfg.vocabulary_deck = "New deck"
        next_cfg.per_book_decks.alpha = "New deck"
    end, "settings_viewer")
    assert_true(committed, "transaction saves a candidate")
    assert_true(candidate == last_saved,
        "successful transaction returns the persisted candidate")
    assert_eq(original.target_language, "English",
        "transaction does not mutate original text settings")
    assert_true(not original.auto_send_vocabulary,
        "transaction does not mutate original toggle settings")
    assert_eq(original.vocabulary_deck, "Old deck",
        "transaction does not mutate original picker settings")
    assert_eq(original.per_book_decks.alpha, "Old deck",
        "transaction deep-copies nested draft settings")
    Persistence.commit(original, candidate)
    assert_eq(original.target_language, "German",
        "commit publishes saved text settings")
    assert_true(original.auto_send_vocabulary,
        "commit publishes saved toggle settings")
    assert_eq(original.vocabulary_deck, "New deck",
        "commit publishes saved picker settings")
    assert_eq(original.per_book_decks.alpha, "New deck",
        "commit publishes saved nested draft settings")

    state.ok = false
    committed, candidate = Persistence.transaction(original, function(next_cfg)
        next_cfg.target_language = "Spanish"
        next_cfg.auto_send_vocabulary = false
        next_cfg.vocabulary_deck = "Unsaved deck"
    end, "settings_viewer")
    assert_true(not committed and candidate == nil,
        "failed transaction does not return an unsaved candidate")
    assert_eq(original.target_language, "German",
        "failed transaction rolls back text settings")
    assert_true(original.auto_send_vocabulary,
        "failed transaction rolls back toggle settings")
    assert_eq(original.vocabulary_deck, "New deck",
        "failed transaction rolls back picker settings")

    end)
end

return run_tests
