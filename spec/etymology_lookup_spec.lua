-- Unit tests for etymology_lookup.lua (offline StarDict etymology, no AI).

local function run_tests(assert_eq, assert_true)
    -- etymology_lookup requires "gettext"; it never actually calls _().
    package.loaded["gettext"] = function(s) return s end
    package.loaded["etymology_lookup"] = nil

    local EtymologyLookup = require("etymology_lookup")

    local function ui_with(results)
        return {
            dictionary = {
                disable_fuzzy_search = true,
                startSdcv = function(self, word, dict_names, fuzzy)
                    assert_eq(fuzzy, false, "fuzzy search disabled for lookups")
                    return results
                end,
            },
        }
    end

    -- 1. Preferred dictionary returns its (already etymology-only) text.
    do
        local ui = ui_with({
            { word = "serendipity", dict = "Etymology (Wiktionary)",
              definition = "<p>From Serendip + -ity.</p>" },
        })
        local got = EtymologyLookup.lookup(ui, "serendipity", "Etymology (Wiktionary)")
        assert_eq(got, "From Serendip + -ity.",
            "preferred etymology dictionary text is stripped and returned")
    end

    -- 2. No preferred dictionary -> extract the Etymology heading from HTML.
    do
        local ui = ui_with({
            { word = "orange",
              definition = "<h2>Etymology</h2><p>From Latin, borrowed.</p>"
                  .. "<h2>Noun</h2><p>A fruit.</p>" },
        })
        local got = EtymologyLookup.lookup(ui, "orange", nil)
        assert_eq(got, "From Latin, borrowed.",
            "falls back to extracting the Etymology heading")
    end

    -- 3. Empty preferred dictionary string also falls through to extraction.
    do
        local ui = ui_with({
            { word = "algebra",
              definition = "<h3>Etymology</h3><p>Borrowed from Arabic.</p>"
                  .. "<h3>Noun</h3><p>Math.</p>" },
        })
        local got = EtymologyLookup.lookup(ui, "algebra", "")
        assert_eq(got, "Borrowed from Arabic.",
            "empty preferred dictionary falls back to extraction")
    end

    -- 4. skip no_result entries and use the first real definition.
    do
        local ui = ui_with({
            { no_result = true, definition = "ignored" },
            { word = "inchoate",
              definition = "<h2>Etymology</h2><p>Borrowed from Latin.</p>" },
        })
        local got = EtymologyLookup.lookup(ui, "inchoate", nil)
        assert_eq(got, "Borrowed from Latin.",
            "no_result entries are skipped")
    end

    -- 5. No results at all -> nil.
    do
        local ui = ui_with({})
        assert_eq(EtymologyLookup.lookup(ui, "nope", "Etymology (Wiktionary)"), nil,
            "empty results -> nil")
    end

    -- 6. Lookup cancelled -> nil.
    do
        local ui = ui_with({ lookup_cancelled = true })
        assert_eq(EtymologyLookup.lookup(ui, "word", nil), nil,
            "cancelled lookup -> nil")
    end

    -- 7. Definition without an Etymology heading -> nil.
    do
        local ui = ui_with({
            { word = "apple", definition = "<h2>Noun</h2><p>A fruit.</p>" },
        })
        assert_eq(EtymologyLookup.lookup(ui, "apple", nil), nil,
            "no Etymology heading -> nil")
    end

    -- 8. Empty/whitespace word -> nil without calling sdcv.
    do
        local called = false
        local ui = {
            dictionary = {
                disable_fuzzy_search = true,
                startSdcv = function() called = true; return {} end,
            },
        }
        assert_eq(EtymologyLookup.lookup(ui, "   "), nil, "blank word -> nil")
        assert_true(not called, "blank word short-circuits before sdcv")
    end

    -- 9. Missing dictionary API -> nil (no crash).
    assert_eq(EtymologyLookup.lookup({}, "word", nil), nil,
        "missing dictionary API -> nil")

    -- 10. Etymology heading in a later dictionary result is found.
    do
        local ui = ui_with({
            { word = "word", definition = "<h2>Noun</h2><p>A plain definition.</p>" },
            { word = "word", definition = "<h2>Etymology</h2><p>From Late Latin.</p>" },
        })
        local got = EtymologyLookup.lookup(ui, "word", nil)
        assert_eq(got, "From Late Latin.",
            "etymology heading found in a later dictionary result")
    end

    -- 11. Configured dictionary present but no entry -> nil + not_found, and no
    --     fallback to another dictionary's Etymology heading.
    do
        local all = {
            { word = "apple", dict = "Etymology (Wiktionary)", definition = "" },
            { word = "apple", dict = "English (General)",
              definition = "<h2>Etymology</h2><p>From Old English.</p>" },
        }
        local ui = {
            dictionary = {
                disable_fuzzy_search = true,
                startSdcv = function(self, word, dict_names, fuzzy)
                    assert_eq(fuzzy, false, "fuzzy search disabled")
                    if not dict_names then return all end
                    local wanted = {}
                    for _i, n in ipairs(dict_names) do wanted[n] = true end
                    local out = {}
                    for _i, r in ipairs(all) do
                        if wanted[r.dict] then out[#out + 1] = r end
                    end
                    return out
                end,
            },
        }
        local got, status = EtymologyLookup.lookup(ui, "apple", "Etymology (Wiktionary)")
        assert_eq(got, nil, "configured dictionary without entry -> nil")
        assert_eq(status, "not_found", "configured dictionary without entry -> not_found")
    end

    -- 12. Successful preferred lookup also reports status "found".
    do
        local ui = ui_with({
            { word = "serendipity", dict = "Etymology (Wiktionary)",
              definition = "<p>From Serendip + -ity.</p>" },
        })
        local got, status = EtymologyLookup.lookup(ui, "serendipity", "Etymology (Wiktionary)")
        assert_eq(got, "From Serendip + -ity.",
            "preferred etymology dictionary text is stripped and returned")
        assert_eq(status, "found", "preferred etymology dictionary reports found")
    end

    -- 13. Named and numeric HTML entities are decoded.
    do
        local ui = ui_with({
            { word = "resume",
              definition = "<p>From French r&eacute;sum&eacute; &mdash; "
                  .. "see &#x201C;r&#233;sumer&#x201D;.</p>" },
        })
        local got = EtymologyLookup.lookup(ui, "resume", "Etymology (Wiktionary)")
        assert_true(got ~= nil, "entity lookup returns text")
        assert_true(got:find("\195\169", 1, true) ~= nil,
            "eacute named entity decoded")
        assert_true(got:find("\226\128\148", 1, true) ~= nil,
            "mdash named entity decoded")
        assert_true(got:find("\226\128\156", 1, true) ~= nil,
            "numeric hex entity decoded to a curly quote")
    end

    package.loaded["etymology_lookup"] = nil
    package.loaded["gettext"] = nil
end

return run_tests
