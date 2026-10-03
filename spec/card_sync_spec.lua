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
    local owner = TempDir.new("ankikoflash card sync spec")
    return owner:with_temp_dir(function(data_dir)
    local names = {
        "card_sync", "card_storage", "atomic_json", "datastorage",
        "json", "logger", "gettext", "settings_persistence",
    }
    return TestSupport.with_package_loaded(names, {}, function()

    local snapshots = {}
    local next_id = 0
    package.loaded["datastorage"] = {
        getDataDir = function() return data_dir end,
    }
    package.loaded["json"] = {
        encode = function(value)
            next_id = next_id + 1
            local key = "[\"sync-snapshot-" .. tostring(next_id) .. "\"]"
            snapshots[key] = deep_copy(value)
            return key
        end,
        decode = function(key)
            return deep_copy(snapshots[key])
        end,
    }
    package.loaded["logger"] = { warn = function() end }
    package.loaded["gettext"] = function(text) return text end
    local settings_state = { ok = true, events = {} }
    package.loaded["settings_persistence"] = {
        save = function()
            return settings_state.ok, settings_state.reason,
                settings_state.message
        end,
        transaction = function(settings, mutate, operation)
            settings_state.events[#settings_state.events + 1] =
                "persist:" .. tostring(operation)
            local candidate = deep_copy(settings)
            mutate(candidate)
            if not settings_state.ok then
                return false, nil, settings_state.reason, settings_state.message
            end
            return true, candidate
        end,
        commit = function(target, candidate)
            for key in pairs(target) do target[key] = nil end
            for key, value in pairs(candidate) do target[key] = value end
            return target
        end,
    }
    package.loaded["atomic_json"] = nil
    package.loaded["card_storage"] = nil
    package.loaded["card_sync"] = nil

    local CardStorage = require("card_storage")
    local AtomicJson = require("atomic_json")
    local CardSync = require("card_sync")
    local local_path = data_dir .. "/local.json"
    local cached_path = data_dir .. "/cached.json"
    local income_path = data_dir .. "/income.json"

    local function write_snapshot(path, value)
        next_id = next_id + 1
        local key = "[\"input-snapshot-" .. tostring(next_id) .. "\"]"
        snapshots[key] = deep_copy(value)
        local f = assert(io.open(path, "wb"))
        assert(f:write(key))
        assert(f:close())
    end

    local function read_snapshot(path)
        local f = assert(io.open(path, "rb"))
        local key = assert(f:read("*all"))
        assert(f:close())
        return deep_copy(snapshots[key])
    end

    assert_eq(CardSync.card_key({
        phrase = " Term ",
        book_title = " Book ",
    }), "term__book", "legacy wiki key remains phrase and book")
    assert_eq(CardSync.card_key({
        card_kind = "vocabulary",
        phrase = " Term ",
        book_title = " Book ",
    }), "term__book", "vocabulary key keeps legacy behavior")
    assert_true(CardSync.card_key({
        card_kind = "memorization",
        phrase = "Memorization: same",
        memorization_text = "First passage",
        book_title = "Book",
    }) ~= CardSync.card_key({
        card_kind = "memorization",
        phrase = "Memorization: same",
        memorization_text = "Second passage",
        book_title = "Book",
    }), "memorization cloud key uses passage text")
    assert_true(CardStorage.same_card({
        card_kind = "memorization",
        memorization_text = "First\npassage",
        book_title = "Book",
    }, {
        card_kind = "memorization",
        memorization_text = " first passage ",
        book_title = "Book",
    }, true), "cloud key and storage share normalized mem identity")

    local old_server = { name = "Old" }
    local new_server = { name = "New" }
    local cfg = { sync_server = old_server }
    local saved_callbacks = 0
    local persisted = CardSync.persist_server(
        cfg, new_server, function() saved_callbacks = saved_callbacks + 1 end)
    assert_true(persisted, "server save reports durable success")
    assert_true(cfg.sync_server == new_server,
        "server save keeps new value after persistence")
    assert_eq(saved_callbacks, 1,
        "server save callback runs only after persistence")
    settings_state.ok = false
    settings_state.reason = "write_failed"
    settings_state.message = "save failed"
    persisted = CardSync.persist_server(
        cfg, nil, function() saved_callbacks = saved_callbacks + 1 end)
    assert_true(not persisted, "server removal reports persistence failure")
    assert_true(cfg.sync_server == new_server,
        "failed server removal rolls back in-memory value")
    assert_eq(saved_callbacks, 1,
        "failed server persistence suppresses success callback")
    settings_state.ok = true

    local baseline_path = data_dir .. "/ankikoflash_cards.json.sync"
    local baseline_removed, baseline_reason = CardSync.remove_sync_baseline()
    assert_true(baseline_removed,
        "absent cards sync baseline is benign")
    assert_true(baseline_reason == nil,
        "absent baseline has no failure reason")
    local baseline = assert(io.open(baseline_path, "wb"))
    assert(baseline:write("baseline"))
    assert(baseline:close())
    baseline_removed = CardSync.remove_sync_baseline()
    assert_true(baseline_removed,
        "existing cards sync baseline is directly removed")
    assert_true(io.open(baseline_path, "rb") == nil,
        "baseline removal is verified on the exact cards .sync path")

    local original_remove = os.remove
    local removed_path
    os.remove = function(path)
        removed_path = path
        return true
    end
    baseline = assert(io.open(baseline_path, "wb"))
    assert(baseline:write("baseline"))
    assert(baseline:close())
    baseline_removed, baseline_reason = CardSync.remove_sync_baseline()
    assert_true(not baseline_removed,
        "unverified no-op baseline removal cannot report success")
    assert_eq(baseline_reason, "baseline_still_exists",
        "baseline reset verifies that the file is actually absent")
    assert(original_remove(baseline_path))

    os.remove = function(path)
        removed_path = path
        return nil, "Permission denied", 13
    end
    baseline_removed, baseline_reason = CardSync.remove_sync_baseline()
    assert_true(not baseline_removed,
        "baseline removal errors cannot report success")
    assert_eq(baseline_reason, "baseline_remove_failed",
        "baseline removal reports its failure")

    local callbacks_before = saved_callbacks
    local persistence_before = #settings_state.events
    local changed, change_reason = CardSync.change_server(
        cfg, old_server, function() saved_callbacks = saved_callbacks + 1 end)
    assert_true(not changed,
        "baseline removal failure blocks server change success")
    assert_eq(change_reason.code, "baseline_reset_failed",
        "server change reports baseline reset failure")
    assert_true(cfg.sync_server == new_server,
        "failed baseline reset keeps the previous runtime server")
    assert_eq(saved_callbacks, callbacks_before,
        "failed baseline reset never invokes persistence callbacks")
    assert_eq(#settings_state.events, persistence_before,
        "failed baseline reset never attempts settings persistence")
    assert_eq(removed_path, baseline_path,
        "server change removes only the cards .sync baseline")

    local transition_events = {}
    os.remove = function(path)
        transition_events[#transition_events + 1] = "remove"
        return original_remove(path)
    end
    settings_state.events = transition_events
    baseline = assert(io.open(baseline_path, "wb"))
    assert(baseline:write("stale baseline"))
    assert(baseline:close())
    settings_state.ok = false
    settings_state.reason = "write_failed"
    settings_state.message = "save failed"
    callbacks_before = saved_callbacks
    changed, change_reason = CardSync.change_server(
        cfg, old_server, function() saved_callbacks = saved_callbacks + 1 end)
    assert_true(not changed,
        "server persistence failure is reported after baseline removal")
    assert_eq(change_reason.code, "server_persistence_failed",
        "post-reset persistence failure has a distinct reason")
    assert_true(change_reason.baseline_removed,
        "post-reset persistence failure reports the safe baseline state")
    assert_true(cfg.sync_server == new_server,
        "post-reset persistence failure keeps the old runtime server")
    assert_eq(saved_callbacks, callbacks_before,
        "failed server persistence suppresses its callback")
    assert_eq(transition_events[1], "remove",
        "server transition removes baseline before persistence")
    assert_eq(transition_events[2], "persist:cloud_sync_server",
        "server transition persists only after baseline reset")
    assert_true(io.open(baseline_path, "rb") == nil,
        "persistence failure leaves the safely removed baseline absent")

    settings_state.ok = true
    settings_state.reason = nil
    settings_state.message = nil
    transition_events = {}
    settings_state.events = transition_events
    local first_cfg = {}
    baseline = assert(io.open(baseline_path, "wb"))
    assert(baseline:write("stale first-server baseline"))
    assert(baseline:close())
    changed = CardSync.change_server(first_cfg, new_server)
    assert_true(changed, "nil-to-server transition succeeds")
    assert_true(first_cfg.sync_server == new_server,
        "nil-to-server transition installs the new runtime server")
    assert_eq(transition_events[1], "remove",
        "nil-to-server transition also clears stale baseline first")
    assert_eq(transition_events[2], "persist:cloud_sync_server",
        "nil-to-server transition persists after baseline removal")
    os.remove = original_remove
    settings_state.events = {}

    write_snapshot(local_path, {
        {
            card_kind = "memorization",
            phrase = "Memorization: same",
            memorization_text = "First passage",
            book_title = "Book",
            updated_at = 1,
        },
        {
            card_kind = "memorization",
            phrase = "Memorization: same",
            memorization_text = "Second passage",
            book_title = "Book",
            updated_at = 2,
        },
        {
            phrase = "Legacy wiki",
            book_title = "Book",
            updated_at = 1,
        },
    })
    write_snapshot(cached_path, {})
    write_snapshot(income_path, {
        {
            card_kind = "memorization",
            phrase = "Memorization: same",
            memorization_text = "Third passage",
            book_title = "Book",
            updated_at = 3,
        },
    })
    local merged, merge_reason = CardSync.merge_cards(
        local_path, cached_path, income_path)
    assert_true(merged, "memorization-aware cloud merge succeeds")
    local cards = read_snapshot(local_path)
    assert_eq(#cards, 4, "cloud merge preserves separate mem passages")
    assert_eq(cards[1].memorization_text, "First passage",
        "first local mem passage survives merge")
    assert_eq(cards[2].memorization_text, "Second passage",
        "second local mem passage survives merge")
    assert_eq(cards[4].memorization_text, "Third passage",
        "remote mem passage is added separately")

    local conflict_baseline = {
        phrase = "Three-way",
        book_title = "Book",
        definition = "baseline definition",
        links = "baseline links",
        text = "baseline text",
        anki_fields = { Front = "Three-way", Back = "baseline back" },
        updated_at = 100,
    }
    local local_unchanged = deep_copy(conflict_baseline)
    local_unchanged.updated_at = 999
    local remote_changed = deep_copy(conflict_baseline)
    remote_changed.anki_fields.Back = "remote nested edit"
    remote_changed.updated_at = 50
    write_snapshot(local_path, { local_unchanged })
    write_snapshot(cached_path, { conflict_baseline })
    write_snapshot(income_path, { remote_changed })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "remote edit versus skewed local clock merges")
    cards = read_snapshot(local_path)
    assert_eq(cards[1].anki_fields.Back, "remote nested edit",
        "content-edited remote wins over timestamp-only local change")
    assert_eq(cards[1].updated_at, 50,
        "clock skew cannot make unchanged local side win")

    local local_changed = deep_copy(conflict_baseline)
    local_changed.definition = "local edit"
    local_changed.updated_at = 1
    local remote_unchanged = deep_copy(conflict_baseline)
    remote_unchanged.updated_at = 1000
    write_snapshot(local_path, { local_changed })
    write_snapshot(cached_path, { conflict_baseline })
    write_snapshot(income_path, { remote_unchanged })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "local edit versus skewed remote clock merges")
    cards = read_snapshot(local_path)
    assert_eq(cards[1].definition, "local edit",
        "content-edited local wins over timestamp-only remote change")
    assert_eq(cards[1].updated_at, 1,
        "newer unchanged remote timestamp cannot erase local content")

    local local_equal = deep_copy(conflict_baseline)
    local_equal.definition = "local unique edit"
    local_equal.text = "z local conflict"
    local_equal.updated_at = 200
    local remote_equal = deep_copy(conflict_baseline)
    remote_equal.links = "remote unique edit"
    remote_equal.text = "a remote conflict"
    remote_equal.updated_at = 200
    write_snapshot(local_path, { local_equal })
    write_snapshot(cached_path, { conflict_baseline })
    write_snapshot(income_path, { remote_equal })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "equal-timestamp concurrent edits merge")
    cards = read_snapshot(local_path)
    assert_eq(cards[1].definition, "local unique edit",
        "equal-timestamp merge preserves local-only field edit")
    assert_eq(cards[1].links, "remote unique edit",
        "equal-timestamp merge preserves remote-only field edit")
    assert_eq(cards[1].text, "a remote conflict",
        "equal-timestamp same-field conflict resolves deterministically")

    write_snapshot(local_path, { remote_equal })
    write_snapshot(cached_path, { conflict_baseline })
    write_snapshot(income_path, { local_equal })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "reversed equal-timestamp merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(cards[1].definition, "local unique edit",
        "equal-timestamp result is independent of device direction")
    assert_eq(cards[1].links, "remote unique edit",
        "reversed merge keeps both unique field edits")
    assert_eq(cards[1].text, "a remote conflict",
        "reversed same-field conflict chooses the same value")

    local remote_newer = deep_copy(remote_equal)
    remote_newer.updated_at = 201
    write_snapshot(local_path, { local_equal })
    write_snapshot(cached_path, { conflict_baseline })
    write_snapshot(income_path, { remote_newer })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "different-timestamp concurrent edits merge")
    cards = read_snapshot(local_path)
    assert_eq(cards[1].links, "remote unique edit",
        "newer remote concurrent edit retains timestamp preference")
    assert_eq(cards[1].definition, "baseline definition",
        "timestamp preference still chooses the complete newer side")

    local baseline_card = {
        phrase = "Baseline",
        book_title = "Book",
        updated_at = 1,
    }
    local unrelated_remote = {
        phrase = "Unrelated remote",
        book_title = "Book",
        updated_at = 2,
    }
    write_snapshot(local_path, { baseline_card })
    write_snapshot(cached_path, { baseline_card })
    write_snapshot(income_path, { unrelated_remote })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "one-card merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "valid remote snapshot can delete an unchanged one-card baseline")
    assert_eq(cards[1].phrase, "Unrelated remote",
        "remote addition survives while its baseline deletion propagates")

    local ten_cached = {}
    for i = 1, 10 do
        ten_cached[i] = {
            phrase = "Card " .. tostring(i),
            book_title = "Book",
            text = "unchanged",
            updated_at = 1,
        }
    end
    write_snapshot(local_path, ten_cached)
    write_snapshot(cached_path, ten_cached)
    write_snapshot(income_path, { ten_cached[10] })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "large legitimate remote deletion merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "valid remote snapshot deleting nine of ten does not resurrect rows")
    assert_eq(cards[1].phrase, "Card 10",
        "the sole retained remote row survives the large deletion")

    write_snapshot(local_path, { ten_cached[10] })
    write_snapshot(cached_path, ten_cached)
    write_snapshot(income_path, ten_cached)
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "large legitimate local deletion merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "sending nine of ten locally does not resurrect cached rows")
    assert_eq(cards[1].phrase, "Card 10",
        "the sole unsent local row survives the large deletion")

    write_snapshot(local_path, { baseline_card })
    write_snapshot(cached_path, { baseline_card })
    write_snapshot(income_path, {})
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "valid empty remote snapshot merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 0,
        "valid JSON empty remote deletes last card from valid cached baseline")

    local locally_edited = deep_copy(baseline_card)
    locally_edited.text = "edited locally without timestamp change"
    write_snapshot(local_path, { locally_edited })
    write_snapshot(cached_path, { baseline_card })
    write_snapshot(income_path, {})
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "remote delete versus local edit merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "remote deletion preserves content changed relative to baseline")
    assert_eq(cards[1].text, locally_edited.text,
        "local content edit wins over concurrent remote deletion")

    write_snapshot(local_path, { baseline_card })
    write_snapshot(cached_path, { baseline_card })
    assert(os.remove(income_path))
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "absent remote snapshot merge is non-destructive")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "absent remote snapshot never deletes cached local card")

    assert(os.remove(cached_path))
    write_snapshot(local_path, { baseline_card })
    write_snapshot(income_path, {})
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "absent baseline merge is non-destructive")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "valid empty remote cannot delete without a decoded baseline")

    local empty_cached = assert(io.open(cached_path, "wb"))
    assert(empty_cached:close())
    write_snapshot(local_path, { baseline_card })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "zero-byte baseline merge is non-destructive")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "zero-byte baseline is not authoritative for deletion")

    local malformed_cached = assert(io.open(cached_path, "wb"))
    assert(malformed_cached:write("{malformed"))
    assert(malformed_cached:close())
    write_snapshot(local_path, { baseline_card })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(not merged, "malformed baseline aborts merge")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "malformed baseline never authorizes deletion")

    write_snapshot(cached_path, { baseline_card })
    write_snapshot(local_path, { baseline_card })
    local empty_remote = assert(io.open(income_path, "wb"))
    assert(empty_remote:close())
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "zero-byte remote snapshot merge is non-destructive")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "zero-byte remote snapshot never deletes cached local card")

    write_snapshot(local_path, { baseline_card })
    local malformed_remote = assert(io.open(income_path, "wb"))
    assert(malformed_remote:write("{malformed"))
    assert(malformed_remote:close())
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(not merged, "malformed remote snapshot aborts merge")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "malformed remote snapshot never deletes cached local card")

    assert(os.remove(local_path))
    write_snapshot(cached_path, { baseline_card })
    write_snapshot(income_path, { baseline_card })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "absent local queue merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "absent local queue cannot infer deletion of remote card")
    assert_eq(cards[1].phrase, "Baseline",
        "remote card survives absent local queue")

    local remotely_edited = deep_copy(baseline_card)
    remotely_edited.text = "edited remotely"
    remotely_edited.updated_at = 2
    write_snapshot(local_path, {})
    write_snapshot(cached_path, { baseline_card })
    write_snapshot(income_path, { remotely_edited })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "local delete versus remote edit merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "local deletion preserves remote card changed from baseline")
    assert_eq(cards[1].updated_at, 2,
        "remote timestamp edit wins over concurrent local deletion")

    write_snapshot(local_path, {})
    write_snapshot(income_path, { baseline_card })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "empty local queue merge succeeds")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 0,
        "valid JSON empty local queue deletes last card from valid cached baseline")

    local zero_byte_local = assert(io.open(local_path, "wb"))
    assert(zero_byte_local:close())
    write_snapshot(cached_path, { baseline_card })
    write_snapshot(income_path, { baseline_card })
    merged = CardSync.merge_cards(local_path, cached_path, income_path)
    assert_true(merged, "zero-byte local queue merge is non-destructive")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1,
        "zero-byte local queue never deletes cached remote card")

    write_snapshot(local_path, { { phrase = "Local", book_title = "Book" } })
    write_snapshot(cached_path, {})
    write_snapshot(income_path, { { phrase = "Remote", book_title = "Book" } })
    local original_write = AtomicJson.write
    AtomicJson.write = function(path)
        if path == local_path then
            return false, { code = "injected_write_failure" }
        end
        return original_write(path)
    end
    merged, merge_reason = CardSync.merge_cards(
        local_path, cached_path, income_path)
    assert_true(not merged, "merge reports atomic write failure")
    assert_eq(merge_reason.code, "injected_write_failure",
        "merge returns structured writer reason")
    cards = read_snapshot(local_path)
    assert_eq(#cards, 1, "failed merge write preserves local snapshot")
    assert_eq(cards[1].phrase, "Local",
        "failed merge does not claim or install merged data")
    AtomicJson.write = original_write

    end)
    end)
end

return run_tests
