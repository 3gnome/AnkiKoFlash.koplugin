local function run_tests(assert_eq, assert_true)
    local names = {
        "send_flow", "ui/widget/confirmbox", "ui/widget/notification",
        "ui/uimanager", "gettext", "anki_sync", "card_defaults",
        "card_storage", "deck_picker", "card_fields", "note_type_profiles",
        "settings_persistence", "ui_busy", "card_reconcile",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local state = { ok = true }
    local shown = {}
    package.loaded["ui/widget/confirmbox"] = { new = function(_, value) return value end }
    package.loaded["ui/widget/notification"] = { new = function(_, value) return value end }
    package.loaded["ui/uimanager"] = {
        show = function(_, widget) shown[#shown + 1] = widget end,
    }
    package.loaded["gettext"] = function(text) return text end
    package.loaded["anki_sync"] = {}
    package.loaded["card_defaults"] = {}
    package.loaded["card_storage"] = {}
    package.loaded["deck_picker"] = {}
    package.loaded["card_fields"] = {
        default_vocabulary_model = function() return "Vocabulary Card" end,
    }
    package.loaded["note_type_profiles"] = {
        normalize_model_name = function(value) return value end,
    }
    package.loaded["settings_persistence"] = {
        save = function()
            return state.ok, state.reason
        end,
    }
    package.loaded["ui_busy"] = {}
    package.loaded["card_reconcile"] = {}
    package.loaded["send_flow"] = nil

    local SendFlow = require("send_flow")
    local cfg = {
        last_send_deck = "Old",
        last_send_model = "OldModel",
        recent_decks = { "Old", "Other" },
    }
    local ok = SendFlow.remember_send(cfg, "New", "NewModel", {
        touch_recent = true,
    })
    assert_true(ok, "recent send settings report successful persistence")
    assert_eq(cfg.last_send_deck, "New", "last deck updates after success")
    assert_eq(cfg.last_send_model, "NewModel", "last model updates after success")
    assert_eq(cfg.recent_decks[1], "New", "new recent deck is first")
    assert_eq(cfg.recent_decks[2], "Old", "existing recent order is preserved")

    state.ok = false
    state.reason = "write_failed"
    local previous_recent = cfg.recent_decks
    ok, state.reason = SendFlow.remember_send(cfg, "Failed", "FailedModel", {
        touch_recent = true,
    })
    assert_true(not ok, "recent send settings return write failure")
    assert_eq(state.reason, "write_failed", "write reason is additive")
    assert_eq(cfg.last_send_deck, "New",
        "failed write rolls back in-memory last deck")
    assert_eq(cfg.last_send_model, "NewModel",
        "failed write rolls back in-memory last model")
    assert_true(cfg.recent_decks == previous_recent,
        "failed write restores prior recent list")

    state.ok = true
    state.send_result = { true, "", "sent", "Deck", "Model" }
    package.loaded["anki_sync"].send_card = function()
        return unpack(state.send_result)
    end
    package.loaded["card_storage"].find_pending_duplicate = function()
        return nil
    end
    package.loaded["ui_busy"].run = function(_, callback)
        callback()
    end
    package.loaded["card_reconcile"].finish = function(_item, _config, _ui, opts)
        state.reconcile_calls = (state.reconcile_calls or 0) + 1
        state.reconcile_status = opts.status
        return true, "deleted", {
            code = "recent_sent_persistence_failed",
            warning = true,
            warning_message = "Recently sent history could not be saved.",
        }
    end
    local done_ok, done_error, done_info
    SendFlow.execute_send(cfg, { phrase = "Accepted" }, "Deck", "Model", nil,
        function(send_ok, send_error, info)
            done_ok, done_error, done_info = send_ok, send_error, info
        end, {
            skip_duplicate_check = true,
        })
    assert_true(done_ok,
        "history-only reconciliation warning does not invite duplicate resend")
    assert_true(done_error == nil,
        "history-only warning is not returned as a send error")
    assert_eq(done_info.reconcile_warning.code,
        "recent_sent_persistence_failed",
        "send caller receives non-fatal reconciliation metadata")
    assert_true(#shown > 0
        and shown[#shown].text:find(
            "Recently sent history could not be saved", 1, true) ~= nil,
        "send caller displays accurate history warning")

    state.send_result = {
        true, "", "duplicate", "Resolved::Deck", "ResolvedModel",
    }
    done_ok, done_error, done_info = nil, nil, nil
    SendFlow.execute_send(cfg, { phrase = "Duplicate" }, "Deck", "Model", nil,
        function(send_ok, send_error, info)
            done_ok, done_error, done_info = send_ok, send_error, info
        end, {
            skip_duplicate_check = true,
            background = true,
        })
    assert_true(done_ok, "verified duplicate succeeds in manual send path")
    assert_true(done_error == nil,
        "verified duplicate does not invite a blind manual retry")
    assert_eq(state.reconcile_status, "already_in_anki",
        "manual duplicate recovery records already-in-Anki status")
    assert_eq(done_info.send_status, "duplicate",
        "manual callback receives duplicate recovery status")
    assert_eq(cfg.last_send_deck, "Resolved::Deck",
        "manual recovery remembers resolved target deck")

    state.send_result = {
        true, "", "verified", "Resolved::Deck", "ResolvedModel",
    }
    SendFlow.execute_send(cfg, { phrase = "Timed out" }, "Deck", "Model", nil,
        function(send_ok, send_error, info)
            done_ok, done_error, done_info = send_ok, send_error, info
        end, {
            skip_duplicate_check = true,
            background = true,
        })
    assert_true(done_ok, "exactly verified ambiguous manual send succeeds")
    assert_eq(state.reconcile_status, "verified",
        "manual timeout recovery records verified status")
    assert_eq(done_info.send_status, "verified",
        "manual callback receives timeout recovery status")

    local reconcile_calls = state.reconcile_calls
    state.send_result = {
        nil, "Send outcome is uncertain; card remains pending", "failed",
        "Resolved::Deck", "ResolvedModel",
    }
    SendFlow.execute_send(cfg, { phrase = "Pending" }, "Deck", "Model", nil,
        function(send_ok, send_error, info)
            done_ok, done_error, done_info = send_ok, send_error, info
        end, {
            skip_duplicate_check = true,
            background = true,
        })
    assert_true(done_ok == nil, "unverified ambiguous manual send fails")
    assert_true(done_error:find("remains pending", 1, true) ~= nil,
        "manual failure clearly reports retained pending state")
    assert_true(done_info.pending, "manual callback marks retained pending card")
    assert_eq(state.reconcile_calls, reconcile_calls,
        "unverified manual send never deletes or reconciles the queue")

    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

return run_tests
