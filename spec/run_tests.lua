#!/usr/bin/env luajit
-- Run: luajit spec/run_tests.lua (from plugin root or spec/)

local script_dir = arg[0]:match("(.*)[/\\]") or "."
local plugin_root = script_dir .. "/.."
package.path = table.concat({
    script_dir .. "/?.lua",
    plugin_root .. "/?.lua",
    package.path,
}, ";")

local passed, failed = 0, 0
local current_spec = ""

local function assert_true(condition, message)
    if not condition then
        failed = failed + 1
        print("FAIL [" .. current_spec .. "]:", message)
        return
    end
    passed = passed + 1
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        failed = failed + 1
        print("FAIL [" .. current_spec .. "]:", message,
            "expected", expected, "got", actual)
        return
    end
    passed = passed + 1
end

local specs = {
    "highlight_cleanup_spec",
    "highlight_books_spec",
    "highlight_inbox_spec",
    "highlight_menu_reopen_spec",
    "position_utils_spec",
    "atomic_json_spec",
    "card_storage_spec",
    "card_sync_spec",
    "card_reconcile_spec",
    "anki_retry_spec",
    "anki_sync_safety_spec",
    "memorization_safety_spec",
    "settings_migration_spec",
    "settings_persistence_spec",
    "send_flow_settings_spec",
    "privacy_log_spec",
    "etymology_lookup_spec",
    "dictionary_lookup_spec",
    "card_fields_dictionary_spec",
    "card_defaults_spec",
    "note_type_picker_spec",
    "plugin_menu_spec",
    "plugin_peers_spec",
    "temp_dir_spec",
    "rename_purity_spec",
}

for _, name in ipairs(specs) do
    current_spec = name
    local failed_before = failed
    local loaded, runner = pcall(require, name)
    if not loaded then
        failed = failed + 1
        print("ERROR [" .. name .. "]:", runner)
    elseif type(runner) ~= "function" then
        failed = failed + 1
        print("ERROR [" .. name .. "]: spec must return a test function")
    else
        local ran, run_error = xpcall(function()
            runner(assert_eq, assert_true)
        end, debug.traceback)
        if not ran then
            failed = failed + 1
            print("ERROR [" .. name .. "]:", run_error)
        end
    end
    if failed == failed_before then
        print("PASS:", name)
    end
end

print(string.format("Results: %d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
