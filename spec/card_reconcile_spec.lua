#!/usr/bin/env luajit

local function run_tests(assert_eq, assert_true)
    local names = {
        "card_reconcile", "card_storage", "card_fields", "highlight_status",
        "note_type_profiles", "plugin_constants", "logger", "gettext",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local state = {}
    local logs = {}
    package.loaded["gettext"] = function(text) return text end
    package.loaded["logger"] = {
        warn = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            logs[#logs + 1] = table.concat(parts, " ")
        end,
    }
    package.loaded["plugin_constants"] = { ID = "ankikoflash" }
    package.loaded["card_storage"] = {
        is_memorization = function(card)
            return card.card_kind == "memorization"
        end,
        record_recent_sent = function(entry)
            state.recent_entry = entry
            return state.recent_ok, state.recent_reason
        end,
        delete_matching_card = function()
            return state.delete_ok, state.delete_reason
        end,
        mark_matching_sent = function()
            return state.mark_ok, state.mark_reason
        end,
    }
    package.loaded["card_fields"] = {
        default_vocabulary_model = function() return "Basic" end,
        is_dictionary_card = function() return false end,
    }
    package.loaded["note_type_profiles"] = {
        normalize_model_name = function(model) return model end,
    }
    local highlight_marks, highlight_removals = 0, 0
    package.loaded["highlight_status"] = {
        mark_sent = function() highlight_marks = highlight_marks + 1 end,
        remove_highlight = function() highlight_removals = highlight_removals + 1 end,
    }
    package.loaded["card_reconcile"] = nil
    local CardReconcile = require("card_reconcile")

    local private_phrase = "PRIVATE HIGHLIGHT TEXT"
    local card = {
        phrase = private_phrase,
        book_title = "Private Book",
        document_path = "/books/private.epub",
        highlight_pos0 = "pos0",
        highlight_pos1 = "pos1",
    }
    state.recent_ok = true
    state.delete_ok = false
    state.delete_reason = "write_failed"
    state.mark_ok = true
    local matching_ui = { document = { file = "/books/private.epub" } }
    local ok, reason = CardReconcile.finish(
        { card = card }, {}, matching_ui, { status = "sent" })
    assert_true(ok, "delete failure falls back to durable sent marker")
    assert_eq(reason, "marked_sent", "fallback reports durable marker state")
    assert_eq(highlight_marks, 0,
        "durable sent marker never marks the highlight")
    assert_eq(highlight_removals, 1,
        "same-document vocabulary card removes its highlight")
    assert_eq(state.recent_entry.document_path, "/books/private.epub",
        "reconcile persists card source document identity")

    for _, message in ipairs(logs) do
        assert_true(not message:find(private_phrase, 1, true),
            "reconcile logs never include card phrase")
        assert_true(not message:find("Private Book", 1, true),
            "reconcile logs never include book title")
    end

    state.recent_ok = true
    state.delete_ok = false
    state.delete_reason = "write_failed"
    state.mark_ok = false
    state.mark_reason = "write_failed"
    ok, reason = CardReconcile.finish(
        { card = card }, {}, matching_ui, { status = "sent" })
    assert_true(not ok, "total queue persistence failure is reported")
    assert_eq(reason.code, "queue_persistence_failed",
        "total failure has structured reason")
    assert_eq(reason.delete_reason, "write_failed",
        "total failure includes deletion outcome")
    assert_eq(reason.marker_reason, "write_failed",
        "total failure includes marker outcome")
    assert_eq(highlight_removals, 1,
        "total persistence failure does not mutate highlight")

    state.recent_ok = false
    state.recent_reason = "write_failed"
    state.delete_ok = true
    state.delete_reason = nil
    state.mark_ok = false
    local warning
    ok, reason, warning = CardReconcile.finish(
        { card = card }, {}, matching_ui, { status = "sent" })
    assert_true(ok,
        "durable queue state remains successful when history persistence fails")
    assert_eq(reason, "deleted",
        "recent history failure reports durable queue state")
    assert_eq(warning.code, "recent_sent_persistence_failed",
        "recent history failure returns warning metadata")
    assert_true(warning.warning,
        "recent history metadata is explicitly non-fatal")
    assert_true(warning.warning_message:find(
        "Recently sent history could not be saved", 1, true) ~= nil,
        "recent history warning accurately names the failed persistence")
    assert_eq(highlight_removals, 2,
        "durably deleted queue still removes the highlight")

    state.recent_ok = true
    state.delete_ok = true
    local memorization_card = {
        card_kind = "memorization",
        phrase = "Memorization: display label",
        memorization_text = "Actual passage",
        book_title = "Private Book",
        document_path = "/books/private.epub",
        highlight_pos0 = "mem0",
        highlight_pos1 = "mem1",
    }
    ok = CardReconcile.finish(
        { card = memorization_card }, {}, matching_ui, { status = "sent" })
    assert_true(ok, "same-document memorization reconcile succeeds")
    assert_eq(highlight_removals, 3,
        "same-document memorization reconcile removes its highlight")
    assert_eq(state.recent_entry.memorization_text, "Actual passage",
        "memorization reconcile records actual passage text")

    ok = CardReconcile.finish(
        { card = memorization_card }, {},
        { document = { file = "/books/other.epub" } }, { status = "sent" })
    assert_true(ok, "cross-document memorization reconcile secures queue state")
    assert_eq(highlight_removals, 3,
        "cross-document memorization reconcile cannot remove open highlight")

    ok = CardReconcile.finish(
        { card = card }, {}, { document = { file = "/books/other.epub" } },
        { status = "sent" })
    assert_true(ok, "cross-document reconcile still secures queue state")
    assert_eq(highlight_removals, 3,
        "cross-document reconcile never mutates the open document")

    local legacy_card = {
        phrase = "Legacy",
        book_title = "Private Book",
        highlight_pos0 = "pos0",
        highlight_pos1 = "pos1",
    }
    ok = CardReconcile.finish(
        { card = legacy_card, document_path = "/books/private.epub" },
        {}, matching_ui, {
            status = "sent",
            document_path = "/books/private.epub",
        })
    assert_true(ok, "legacy reconcile still secures queue state")
    assert_eq(highlight_removals, 3,
        "legacy card cannot inherit document scope for UI mutation")
    assert_true(state.recent_entry.document_path == nil,
        "legacy card cannot inherit document scope in recent history")

    ok, reason = CardReconcile.finish(nil, {}, nil, {})
    assert_true(not ok, "missing reconcile card is rejected")
    assert_eq(reason.code, "invalid_card",
        "missing card has structured failure reason")

    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

return run_tests
