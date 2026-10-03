-- Unit tests for dictionary_lookup.lua exclusion — the definition lookup must
-- never offer the configured etymology dictionary, but must keep returning
-- definitions from other dictionaries.

local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = {
        "dictionary_lookup",
        "ui/widget/menu",
        "ui/uimanager",
        "gettext",
        "nav",
    }
    return TestSupport.with_package_loaded(names, {}, function()
        package.loaded["ui/widget/menu"] = {}
        package.loaded["ui/uimanager"] = {}
        package.loaded["gettext"] = function(text) return text end
        package.loaded["nav"] = {
            prepend_back = function() end,
            wrap_menu = function(m) return m end,
            apply_compact_menu = function(t) return t end,
            show = function() end,
            after_close = function() end,
        }

        local DictionaryLookup = require("dictionary_lookup")

        local function ui_with(results)
            return {
                dictionary = {
                    disable_fuzzy_search = true,
                    startSdcv = function(self, word, dict_names, fuzzy)
                        return results
                    end,
                },
            }
        end

        -- 1. exclude_dictionary removes the etymology dictionary, keeping the
        --    definition dictionary.
        do
            local entries = DictionaryLookup.lookup_all(ui_with({
                { word = "run", dict = "English (General)",
                  definition = "<p>to move swiftly</p>" },
                { word = "run", dict = "Etymology (Wiktionary)",
                  definition = "<p>from Old English rinnan</p>" },
            }), "run", { exclude_dictionary = "Etymology (Wiktionary)" })
            assert_eq(#entries, 1, "etymology dictionary excluded from definitions")
            assert_eq(entries[1].dict, "English (General)",
                "definition dictionary retained after exclusion")
        end

        -- 2. Exclusion that would empty the set is ignored.
        do
            local entries = DictionaryLookup.lookup_all(ui_with({
                { word = "run", dict = "Etymology (Wiktionary)",
                  definition = "<p>from Old English rinnan</p>" },
            }), "run", { exclude_dictionary = "Etymology (Wiktionary)" })
            assert_eq(#entries, 1, "exclusion that empties results is ignored")
            assert_eq(entries[1].dict, "Etymology (Wiktionary)",
                "only available entry is retained")
        end

        -- 3. pick with preferred + exclude returns the preferred definition.
        do
            local picked
            DictionaryLookup.pick(ui_with({
                { word = "run", dict = "English (General)",
                  definition = "<p>to move swiftly</p>" },
                { word = "run", dict = "Etymology (Wiktionary)",
                  definition = "<p>from Old English rinnan</p>" },
            }), "run", function(e) picked = e end, {
                preferred_dictionary = "English (General)",
                exclude_dictionary = "Etymology (Wiktionary)",
                auto_pick = true,
            })
            assert_true(picked ~= nil, "pick returns an entry")
            assert_eq(picked.dict, "English (General)",
                "pick returns the preferred definition dictionary")
        end

        -- 4. exclude equal to preferred is ignored.
        do
            local picked
            DictionaryLookup.pick(ui_with({
                { word = "run", dict = "English (General)",
                  definition = "<p>to move swiftly</p>" },
                { word = "run", dict = "Etymology (Wiktionary)",
                  definition = "<p>from Old English rinnan</p>" },
            }), "run", function(e) picked = e end, {
                preferred_dictionary = "English (General)",
                exclude_dictionary = "English (General)",
                auto_pick = true,
            })
            assert_true(picked ~= nil, "pick returns an entry")
            assert_eq(picked.dict, "English (General)",
                "exclude equal to preferred is ignored")
        end

        -- 5. No preferred: the single non-excluded entry auto-picks.
        do
            local picked
            DictionaryLookup.pick(ui_with({
                { word = "run", dict = "English (General)",
                  definition = "<p>to move swiftly</p>" },
                { word = "run", dict = "Etymology (Wiktionary)",
                  definition = "<p>from Old English rinnan</p>" },
            }), "run", function(e) picked = e end, {
                exclude_dictionary = "Etymology (Wiktionary)",
            })
            assert_true(picked ~= nil, "single remaining entry is picked")
            assert_eq(picked.dict, "English (General)",
                "single non-excluded entry auto-picks without a menu")
        end
    end)
end

return run_tests
