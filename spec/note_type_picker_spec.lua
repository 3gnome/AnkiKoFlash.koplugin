-- Unit tests for NoteTypePicker's cache-first decision helper. The picker opens
-- instantly from a previous fetch (cached_model_names) instead of blocking on
-- AnkiConnect before showing a menu.

local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = {
        "ui/widget/inputdialog", "ui/widget/menu", "ui/widget/notification",
        "ui/uimanager", "gettext", "anki_sync", "card_storage", "nav",
        "note_type_profiles", "ui_busy", "note_type_picker",
    }
    return TestSupport.with_package_loaded(names, {}, function()
        package.loaded["ui/widget/inputdialog"] = {}
        package.loaded["ui/widget/menu"] = {}
        package.loaded["ui/widget/notification"] = {}
        package.loaded["ui/uimanager"] = {}
        package.loaded["gettext"] = function(text) return text end
        package.loaded["anki_sync"] = {}
        package.loaded["card_storage"] = {}
        package.loaded["nav"] = {}
        package.loaded["note_type_profiles"] = {}
        package.loaded["ui_busy"] = {}
        package.loaded["note_type_picker"] = nil

        local NoteTypePicker = require("note_type_picker")

        assert_true(NoteTypePicker.has_cached_models({
            cached_model_names = { "Vocabulary Card", "Basic" },
        }), "non-empty cached_model_names is a cache hit")
        assert_true(not NoteTypePicker.has_cached_models({ cached_model_names = {} }),
            "empty cached_model_names is not a cache hit")
        assert_true(not NoteTypePicker.has_cached_models({}),
            "missing cached_model_names is not a cache hit")
        assert_true(not NoteTypePicker.has_cached_models(nil),
            "nil config is not a cache hit")
    end)
end

return run_tests
