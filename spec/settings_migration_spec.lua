local function run_tests(assert_eq, assert_true)
    local saved_card_fields = package.loaded["card_fields"]
    local saved_storage = package.loaded["card_storage"]
    local saved_gettext = package.loaded["gettext"]
    local saved_profiles = package.loaded["note_type_profiles"]

    package.loaded["card_fields"] = nil
    package.loaded["note_type_profiles"] = nil
    package.loaded["card_storage"] = {
        load_anki_settings = function() return nil end,
    }
    package.loaded["gettext"] = function(text) return text end

    local CardFields = require("card_fields")
    local settings = {
        vocabulary_model = "Vocabulary Card",
    }
    local migrated, notice, changed =
        CardFields.migrate_anki_settings(settings)
    assert_eq(migrated.max_memorization_steps, 80,
        "missing threshold migrates to default")
    assert_true(changed, "default migration is persisted")
    assert_true(notice == nil, "additive default needs no warning")

    local existing = {
        vocabulary_model = "Vocabulary Card",
        max_memorization_steps = 120,
    }
    local kept, _notice, changed_existing =
        CardFields.migrate_anki_settings(existing)
    assert_eq(kept.max_memorization_steps, 120,
        "custom threshold is preserved")
    assert_true(not changed_existing,
        "fully populated valid settings need no migration")

    local invalid = {
        vocabulary_model = "Vocabulary Card",
        max_memorization_steps = 0,
    }
    CardFields.migrate_anki_settings(invalid)
    assert_eq(invalid.max_memorization_steps, 80,
        "invalid threshold resets safely")

    local legacy = {
        model = "Wiki Card",
        vocabulary_model = "",
        send_on_save = true,
        memorize_auto_send = false,
        deck = "Legacy Deck",
        max_memorization_steps = "12.9",
    }
    local migrated_legacy, legacy_notice, legacy_changed =
        CardFields.migrate_anki_settings(legacy)
    assert_true(legacy_changed, "legacy fixture reports every mutation")
    assert_true(legacy_notice ~= nil, "legacy shared deck reports a notice")
    assert_true(migrated_legacy.model == nil,
        "retired wiki mirror key is scrubbed")
    assert_eq(migrated_legacy.vocabulary_model, "Vocabulary Card",
        "empty vocabulary model is reset to default")
    assert_eq(migrated_legacy.auto_send_vocabulary, true,
        "legacy send-on-save assigns vocabulary auto-send")
    assert_eq(migrated_legacy.auto_send_memorization, true,
        "legacy send-on-save assigns memorization auto-send")
    assert_true(migrated_legacy.send_on_save == nil,
        "legacy send-on-save removal is applied")
    assert_true(migrated_legacy.memorize_auto_send == nil,
        "false legacy memorization toggle removal is applied")
    assert_true(migrated_legacy.wiki_deck == nil,
        "retired wiki deck key is scrubbed")
    assert_eq(migrated_legacy.vocabulary_deck, "Legacy Deck",
        "legacy shared deck assigns vocabulary deck")
    assert_eq(migrated_legacy.max_memorization_steps, 12,
        "numeric string threshold is normalized")

    local _, _, second_changed =
        CardFields.migrate_anki_settings(migrated_legacy)
    assert_true(not second_changed,
        "fully migrated fixture reports no phantom changes")

    local broken_nested = {
        vocabulary_model = "Memorization",
        memorize_model = "Vocabulary Card",
        max_memorization_steps = 80,
    }
    local _, _, nested_changed =
        CardFields.migrate_anki_settings(broken_nested)
    assert_true(nested_changed, "invalid model assignments are marked changed")
    assert_eq(broken_nested.vocabulary_model, "Vocabulary Card",
        "invalid vocabulary model is reset to default")
    assert_eq(broken_nested.memorize_model, "Memorization",
        "invalid memorization model is reset to default")
    assert_eq(broken_nested.memorize.model, "Memorization",
        "nested memorization model assignment is persisted")

    -- AI provider / API-key scrub wipes every stored key.
    local ai_settings = {
        vocabulary_model = "Vocabulary Card",
        max_memorization_steps = 80,
        text_provider = "openai",
        openai_api_key = "sk-secret",
        gemini_api_key = "gemini-secret",
        dashscope_api_key = "dash-secret",
        openrouter_api_key = "or-secret",
        custom_prompts = { suffix = "x" },
        prompt_suffix = "x",
    }
    local ai_migrated = CardFields.migrate_anki_settings(ai_settings)
    assert_true(ai_migrated.text_provider == nil, "provider key is scrubbed")
    assert_true(ai_migrated.openai_api_key == nil, "openai key is scrubbed")
    assert_true(ai_migrated.gemini_api_key == nil, "gemini key is scrubbed")
    assert_true(ai_migrated.dashscope_api_key == nil, "dashscope key is scrubbed")
    assert_true(ai_migrated.openrouter_api_key == nil, "openrouter key is scrubbed")
    assert_true(ai_migrated.custom_prompts == nil, "custom prompts are scrubbed")
    assert_true(ai_migrated.prompt_suffix == nil, "prompt suffix is scrubbed")

    package.loaded["card_fields"] = saved_card_fields
    package.loaded["card_storage"] = saved_storage
    package.loaded["gettext"] = saved_gettext
    package.loaded["note_type_profiles"] = saved_profiles
end

return run_tests
