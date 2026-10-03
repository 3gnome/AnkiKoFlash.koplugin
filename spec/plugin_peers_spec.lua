local function run_tests(assert_eq, assert_true)
    package.loaded["plugin_peers"] = nil
    package.loaded["pluginloader"] = {
        isPluginLoaded = function(_, name)
            return name == "TagBankHighlightSync"
        end,
        getPluginInstance = function(_, name)
            if name == "TagBankHighlightSync" then
                return { syncAllBooksFromHistory = function() end }
            end
        end,
    }

    local PluginPeers = require("plugin_peers")

    assert_true(PluginPeers.is_tagbank_available(nil), "loader TagBankHighlightSync")
    assert_true(PluginPeers.get_tagbank_plugin(nil) ~= nil, "instance via loader")
    assert_true(PluginPeers.is_tagbank_available({ TagBankHighlightSync = {} }),
        "ui.TagBankHighlightSync fallback")
    assert_true(PluginPeers.is_tagbank_available({ tagbankhighlightsync = {} }),
        "ui.tagbankhighlightsync legacy fallback")

    package.loaded["pluginloader"] = nil
    assert_true(not PluginPeers.is_tagbank_available({}), "empty ui without loader")
end

if arg and arg[0] and arg[0]:match("plugin_peers_spec%.lua$") then
    local passed, failed = 0, 0
    local function assert_true(c, msg)
        if not c then failed = failed + 1; print("FAIL:", msg); return end
        passed = passed + 1
    end
    local root = arg[0]:match("(.*)[/\\]") or "."
    package.path = package.path .. ";" .. root .. "/?.lua;" .. root .. "/../?.lua"
    run_tests(function() end, assert_true)
    print(string.format("Results: %d passed, %d failed", passed, failed))
    os.exit(failed > 0 and 1 or 0)
end

return run_tests
