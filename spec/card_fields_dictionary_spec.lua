-- Unit tests for CardFields.dictionary_fields_for_send — the dictionary
-- (no-AI) field mapping, with a focus on how the looked-up etymology is routed
-- onto the chosen note type's fields by name.

local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = { "card_fields", "note_type_profiles", "card_storage", "gettext" }
    return TestSupport.with_package_loaded(names, {}, function()
        package.loaded["gettext"] = function(text) return text end
        package.loaded["card_storage"] = { load_anki_settings = function() return {} end }
        package.loaded["note_type_profiles"] = {
            VOCABULARY_CARD_MODEL = "Vocabulary Card",
            DEFAULT_MODEL = "Vocabulary Card",
            MEMORIZATION_MODEL = "Memorization",
            POETRY_MODEL = "Memorization",
            VOCABULARY_CARD_FIELDS = { "Phrase", "Definition", "Etymology", "Context", "Source" },
            normalize_model_name = function(name) return name or "Vocabulary Card" end,
            is_vocabulary_card = function(name) return name == "Vocabulary Card" end,
            is_memorization = function() return false end,
            is_basic = function() return false end,
            is_vocabulary_compatible = function() return true end,
            is_memorization_compatible = function() return false end,
            vocabulary_field_set = function() return true end,
        }
        package.loaded["card_fields"] = nil

        local CardFields = require("card_fields")

        -- 1. Full 5-field note type: every piece lands in its own field,
        --    including Etymology.
        local full = CardFields.dictionary_fields_for_send({
            phrase     = "serendipity",
            definition = "the faculty of making happy discoveries",
            etymology  = "coined by Horace Walpole in 1754",
            context    = "a passage from the book",
            source     = "Book — Author",
        }, { "Phrase", "Definition", "Etymology", "Context", "Source" })
        assert_eq(full.Phrase, "serendipity", "term maps to Phrase")
        assert_eq(full.Definition, "the faculty of making happy discoveries",
            "definition maps to Definition")
        assert_eq(full.Etymology, "coined by Horace Walpole in 1754",
            "etymology maps to Etymology")
        assert_eq(full.Context, "a passage from the book", "context maps to Context")
        assert_eq(full.Source, "Book — Author", "source maps to Source")

        -- 2. Etymology aliases: origin / root / derivation.
        local aliased = CardFields.dictionary_fields_for_send({
            phrase     = "algebra",
            definition = "a branch of mathematics",
            etymology  = "from Arabic al-jabr",
        }, { "Term", "Gloss", "Origin" })
        assert_eq(aliased.Term, "algebra", "term maps to Term alias")
        assert_eq(aliased.Gloss, "a branch of mathematics",
            "definition maps to Gloss alias")
        assert_eq(aliased.Origin, "from Arabic al-jabr",
            "etymology maps to Origin alias")

        -- 3. No Etymology field present: etymology is omitted (not merged into
        --    the definition), so the note type stays clean.
        local no_ety = CardFields.dictionary_fields_for_send({
            phrase     = "orange",
            definition = "a citrus fruit",
            etymology  = "from Old French",
            context    = "the peel",
        }, { "Phrase", "Definition", "Context", "Source" })
        assert_eq(no_ety.Definition, "a citrus fruit",
            "definition stays clean when no Etymology field exists")
        assert_true(no_ety.Etymology == nil,
            "Etymology field is absent when the note type has no etymology field")
        assert_true(not tostring(no_ety.Definition):find("Old French", 1, true),
            "etymology is not appended into Definition")

        -- 4. Etymology is only produced from the etymology data, never invented.
        local no_data = CardFields.dictionary_fields_for_send({
            phrase     = "blue",
            definition = "a color",
            etymology  = "",
        }, { "Phrase", "Definition", "Etymology" })
        assert_eq(no_data.Etymology, "", "empty etymology maps to empty Etymology field")

        -- 5. etymology_will_be_dropped signals when no field can hold it.
        local dropped = CardFields.etymology_will_be_dropped(
            { etymology = "from Old French" },
            { "Phrase", "Definition", "Context", "Source" })
        assert_true(dropped,
            "etymology is dropped for note types without an etymology field")

        local kept = CardFields.etymology_will_be_dropped(
            { etymology = "from Old French" },
            { "Phrase", "Definition", "Etymology", "Context" })
        assert_true(not kept,
            "etymology is kept when an Etymology field exists")

        local alias_kept = CardFields.etymology_will_be_dropped(
            { etymology = "from Arabic" },
            { "Term", "Gloss", "Origin" })
        assert_true(not alias_kept,
            "etymology alias field (Origin) keeps the etymology")

        local no_etymology_data = CardFields.etymology_will_be_dropped(
            { definition = "a color" },
            { "Phrase", "Definition" })
        assert_true(not no_etymology_data,
            "no etymology data is never flagged as dropped")
    end)
end

return run_tests
