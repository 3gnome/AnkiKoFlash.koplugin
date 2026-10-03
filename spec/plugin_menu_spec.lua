#!/usr/bin/env luajit

local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = {
        "plugin_menu",
        "ui/widget/menu",
        "ui/uimanager",
        "ui/widget/infomessage",
        "gettext",
        "card_manager",
        "highlight_inbox",
        "card_storage",
        "card_defaults",
        "plugin_constants",
        "nav",
    }
    return TestSupport.with_package_loaded(names, {}, function()
        package.loaded["ui/widget/menu"] = {}
        package.loaded["ui/uimanager"] = {}
        package.loaded["ui/widget/infomessage"] = {}
        package.loaded["gettext"] = function(text) return text end
        package.loaded["card_manager"] = {}
        package.loaded["highlight_inbox"] = {}
        package.loaded["card_storage"] = {}
        package.loaded["card_defaults"] = {}
        package.loaded["plugin_constants"] = {}
        package.loaded["nav"] = {}

        local PluginMenu = require("plugin_menu")
        local old_server = { name = "Old" }
        local config = {
            static_top = "keep top",
            anki = {
                sync_server = old_server,
                stale_runtime = "remove",
                static_only = "keep nested",
                url = "http://old",
            },
        }
        local previous_settings = {
            sync_server = old_server,
            stale_runtime = "remove",
            url = "http://old",
        }
        local new_settings = {
            url = "http://new",
        }

        PluginMenu.merge_settings_into_config(
            config, new_settings, previous_settings)
        assert_true(config.anki.sync_server == nil,
            "successful sync-server deletion clears nested runtime state")
        assert_true(config.anki.stale_runtime == nil,
            "removed persisted keys are cleared from runtime config")
        assert_eq(config.anki.url, "http://new",
            "replacement settings install new nested values")
        assert_eq(config.anki.static_only, "keep nested",
            "replacement preserves unrelated static nested config")
        assert_eq(config.static_top, "keep top",
            "replacement preserves unrelated static top-level config")

        PluginMenu.merge_settings_into_config(
            config, { url = "http://newer" }, {
                url = "http://new",
            })
        assert_eq(config.anki.url, "http://newer",
            "replacement settings update the nested url")

        config.anki.sync_server = old_server
        PluginMenu.merge_settings_into_config(config, {}, {})
        assert_true(config.anki.sync_server == nil,
            "sync-server deletion clears even without prior-key snapshot")
        assert_eq(config.anki.static_only, "keep nested",
            "sync-server fallback does not remove static nested fields")

        -- ── Rename purity: labels derive from PluginConstants.NAME ─────────
        local script_dir = arg[0] and arg[0]:match("(.*)[/\\]") or "."
        local plugin_root = script_dir .. "/.."

        local function read_file(path)
            local f = io.open(path, "rb")
            if not f then return nil end
            local content = f:read("*all")
            f:close()
            return content
        end

        local real_constants_chunk =
            loadfile(plugin_root .. "/plugin_constants.lua")
        assert_true(real_constants_chunk ~= nil, "real plugin_constants loads")
        if real_constants_chunk then
            local RealConstants = real_constants_chunk()
            assert_eq(RealConstants.NAME, "AnkiKoFlash",
                "menu title source is the current name")
            assert_eq(RealConstants.MEMORIZATION_CARD_LABEL, "Memorization Card",
                "memorization label carries no retired Wiki branding")
            assert_true(not tostring(RealConstants.MEMORIZATION_CARD_LABEL)
                    :lower():find("wiki", 1, true)
                and not tostring(RealConstants.VOCABULARY_CARD_LABEL)
                    :lower():find("wiki", 1, true),
                "card labels carry no retired Wiki branding")
        end

        local menu_src = read_file(plugin_root .. "/plugin_menu.lua")
        assert_true(menu_src ~= nil, "plugin_menu.lua source is readable")
        if menu_src then
            assert_true(menu_src:find("title%s*=%s*PluginConstants%.NAME"),
                "hub menu title derives from PluginConstants.NAME")
            assert_true(not menu_src:lower():find("wiki", 1, true)
                and not menu_src:find(" AI ", 1, true),
                "hub menu shows no retired Wiki/AI labels")
        end

        local settings_src = read_file(plugin_root .. "/settings_viewer.lua")
        assert_true(settings_src ~= nil, "settings_viewer.lua source is readable")
        if settings_src then
            assert_true(not settings_src:lower():find("wiki", 1, true)
                and not settings_src:find(" AI ", 1, true),
                "settings UI shows no retired Wiki/AI labels")
        end
    end)
end

return run_tests
