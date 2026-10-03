-- Rename-purity regression spec: the plugin must be AnkiKoFlash everywhere
-- user-visible, with the pre-rename AnkiKOAi identity (and the retired AI /
-- Wiki feature modules) fully gone. The only tolerated old-name literals are
-- the intentional storage-file migration in card_storage.lua.

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function load_module_file(path)
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    return chunk()
end

local function list_root_lua_files(root)
    local is_windows = package.config:sub(1, 1) == "\\"
    local files = {}
    local handle
    if is_windows then
        handle = io.popen('dir /b "' .. root .. '\\*.lua"')
    else
        handle = io.popen('ls -1 ' .. root .. '/*.lua 2>/dev/null')
    end
    if not handle then return files end
    for line in handle:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            files[#files + 1] = line
        end
    end
    handle:close()
    return files
end

local function run_tests(assert_eq, assert_true)
    local script_dir = arg[0] and arg[0]:match("(.*)[/\\]") or "."
    local plugin_root = script_dir .. "/.."

    -- 1. Plugin metadata identity.
    local meta, meta_err = load_module_file(plugin_root .. "/_meta.lua")
    assert_true(meta ~= nil, "_meta.lua loads: " .. tostring(meta_err))
    if meta then
        assert_eq(meta.name, "ankikoflash", "plugin id is ankikoflash")
        assert_eq(meta.fullname, "AnkiKoFlash", "plugin display name is AnkiKoFlash")
        assert_true(not meta.description:lower():find(" ai ", 1, true)
            and not meta.description:lower():match("^ai ")
            and not meta.description:lower():find(" ai$"),
            "description no longer advertises AI")
    end

    -- 2. Plugin constants identity.
    local pc, pc_err = load_module_file(plugin_root .. "/plugin_constants.lua")
    assert_true(pc ~= nil, "plugin_constants.lua loads: " .. tostring(pc_err))
    if pc then
        assert_eq(pc.ID, "ankikoflash", "PluginConstants.ID is ankikoflash")
        assert_eq(pc.NAME, "AnkiKoFlash", "PluginConstants.NAME is AnkiKoFlash")
        assert_eq(pc.CARDS_FILE, "ankikoflash_cards.json",
            "cards storage file uses the current name")
        assert_eq(pc.SETTINGS_FILE, "ankikoflash_settings.json",
            "settings storage file uses the current name")
        assert_eq(pc.RECENT_SENT_FILE, "ankikoflash_recent_sent.json",
            "recent-sent storage file uses the current name")
        assert_eq(pc.HIGHLIGHT_DIALOG_ID_HUB, "99_ankikoflash",
            "highlight-dialog hub id uses the current name")
    end

    -- 3. Retired AI / Wiki modules must not exist.
    local retired = {
        "card_generator.lua",
        "llm_response_validator.lua",
        "prompt_builder.lua",
        "wiki_sources.lua",
    }
    for _, name in ipairs(retired) do
        assert_true(read_file(plugin_root .. "/" .. name) == nil,
            "retired module removed: " .. name)
    end

    -- 4. No old-name strings in any root Lua file, except the one migration
    -- module that must keep the legacy filenames.
    local allowlist = { ["card_storage.lua"] = true }
    local old_patterns = { "ankikoai", "ankikooai" }
    for _, path in ipairs(list_root_lua_files(plugin_root)) do
        local base = path:match("([^/\\]+)$")
        if not base or not allowlist[base] then
            local content = read_file(path)
            if content then
                local lowered = content:lower()
                for _, pat in ipairs(old_patterns) do
                    assert_true(not lowered:find(pat, 1, true),
                        "old name absent from " .. base .. ": " .. pat)
                end
            end
        end
    end

    -- 5. configuration.lua.sample carries no provider / API-key / prompt keys.
    local sample = read_file(plugin_root .. "/configuration.lua.sample")
    assert_true(sample ~= nil, "configuration.lua.sample exists")
    if sample then
        for _, key in ipairs({
            "text_provider", "openai_api_key", "gemini_api_key",
            "dashscope_api_key", "openrouter_api_key", "anthropic_api_key",
            "google_api_key", "custom_prompts", "prompt_suffix",
            "default_prompt", "llm_model", "llm_provider",
        }) do
            assert_true(not sample:find(key, 1, true),
                "configuration.lua.sample scrubs AI key: " .. key)
        end
    end
end

if arg and arg[0] and arg[0]:match("rename_purity_spec%.lua$") then
    local passed, failed = 0, 0
    local function assert_true(c, msg)
        if not c then failed = failed + 1; print("FAIL:", msg); return end
        passed = passed + 1
    end
    local function assert_eq(a, b, msg)
        if a ~= b then
            failed = failed + 1
            print("FAIL:", msg, "expected", b, "got", a)
            return
        end
        passed = passed + 1
    end
    local root = arg[0]:match("(.*)[/\\]") or "."
    package.path = package.path .. ";" .. root .. "/?.lua;" .. root .. "/../?.lua"
    run_tests(assert_eq, assert_true)
    print(string.format("Results: %d passed, %d failed", passed, failed))
    os.exit(failed > 0 and 1 or 0)
end

return run_tests
