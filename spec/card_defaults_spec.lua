local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = {
        "card_defaults", "card_fields", "note_type_profiles", "plugin_constants",
    }
    return TestSupport.with_package_loaded(names, {}, function()

    local merged
    package.loaded["card_fields"] = {
        merged_anki_settings = function(config)
            if type(config) ~= "table" then return {} end
            local out = {}
            if type(config.anki) == "table" then
                for k, v in pairs(config.anki) do out[k] = v end
            end
            return out
        end,
    }
    package.loaded["note_type_profiles"] = {}
    package.loaded["plugin_constants"] = {}
    package.loaded["card_defaults"] = nil

    local CardDefaults = require("card_defaults")

    local config = function(anki)
        return { anki = anki or {} }
    end

    assert_true(not CardDefaults.save_only_vocabulary(config({})),
        "save-only is off when unset")
    assert_true(not CardDefaults.save_only_vocabulary(config({ save_only_vocabulary = false })),
        "save-only is off when explicitly false")
    assert_true(CardDefaults.save_only_vocabulary(config({ save_only_vocabulary = true })),
        "save-only is on when set")

    assert_true(not CardDefaults.vocab_auto_flow(config({})),
        "auto flow is off when no toggles are set")
    assert_true(CardDefaults.vocab_auto_flow(config({ auto_send_vocabulary = true })),
        "auto flow is on for auto-send")
    assert_true(CardDefaults.vocab_auto_flow(config({ save_only_vocabulary = true })),
        "auto flow is on for save-only")
    assert_true(CardDefaults.vocab_auto_flow(config({
        auto_send_vocabulary = false, save_only_vocabulary = true })),
        "save-only alone enables the auto flow")
    assert_true(CardDefaults.vocab_auto_flow(config({
        auto_send_vocabulary = true, save_only_vocabulary = true })),
        "both toggles still enable the auto flow")

    end)
end

return run_tests
