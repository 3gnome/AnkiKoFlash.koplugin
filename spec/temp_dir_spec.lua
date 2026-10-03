#!/usr/bin/env luajit
-- Run: luajit spec/temp_dir_spec.lua (from plugin root)

local function normalized(path)
    return path:gsub("\\", "/"):gsub("/+$", "")
end

local function run_tests(assert_eq, assert_true)
    local TempDir = require("temp_dir")
    local TestSupport = require("test_support")

    local owner = TempDir.new("ankikoflash temp test")
    local success_path
    local first, second = owner:with_temp_dir(function(path)
        success_path = path
        assert_true(TempDir.path_exists(path), "owned temp exists during callback")
        assert_true(
            normalized(path):sub(1, #normalized(owner.root) + 1)
                == normalized(owner.root) .. "/",
            "owned temp is under OS temp root"
        )
        return "kept", 42
    end)
    assert_eq(first, "kept", "success callback first return preserved")
    assert_eq(second, 42, "success callback second return preserved")
    assert_true(not TempDir.path_exists(success_path), "success callback temp cleaned")

    local failure_path
    local ok, err = pcall(function()
        owner:with_temp_dir(function(path)
            failure_path = path
            error("intentional temp callback failure")
        end)
    end)
    assert_true(not ok, "failure callback is rethrown")
    assert_true(tostring(err):match("intentional temp callback failure") ~= nil,
        "failure callback keeps original error")
    assert_true(not TempDir.path_exists(failure_path), "failure callback temp cleaned")

    local first_owner = TempDir.new("ankikoflash ownership")
    local second_owner = TempDir.new("ankikoflash ownership")
    local owned_path = first_owner:create()
    local removed, remove_error = second_owner:cleanup(owned_path)
    assert_true(not removed, "different helper cannot clean unowned temp")
    assert_true(tostring(remove_error):match("unowned") ~= nil,
        "unowned cleanup explains refusal")
    assert_true(TempDir.path_exists(owned_path), "unowned cleanup leaves temp intact")
    assert_true(first_owner:cleanup(owned_path), "owning helper cleans temp")
    assert_true(not TempDir.path_exists(owned_path), "owned cleanup removes temp")

    local module_name = "ankikoflash_cleanup_regression"
    local original_module = { original = true }
    package.loaded[module_name] = original_module
    ok = pcall(function()
        TestSupport.with_package_loaded(
            { module_name }, { [module_name] = { mocked = true } }, function()
                assert_true(package.loaded[module_name].mocked,
                    "module mock is installed during callback")
                error("intentional module callback failure")
            end)
    end)
    assert_true(not ok, "module helper rethrows callback failure")
    assert_true(package.loaded[module_name] == original_module,
        "module helper restores package.loaded after failure")
    package.loaded[module_name] = nil
end

if arg and arg[0] and arg[0]:match("temp_dir_spec%.lua$") then
    local root = arg[0]:match("(.*)[/\\]") or "."
    package.path = package.path .. ";" .. root .. "/?.lua;" .. root .. "/../?.lua"
    local passed, failed = 0, 0
    local function assert_true(c, msg)
        if not c then failed = failed + 1; print("FAIL:", msg); return end
        passed = passed + 1
    end
    local function assert_eq(a, e, msg)
        if a ~= e then failed = failed + 1; print("FAIL:", msg, "expected", e, "got", a); return end
        passed = passed + 1
    end
    run_tests(assert_eq, assert_true)
    print(string.format("Results: %d passed, %d failed", passed, failed))
    os.exit(failed > 0 and 1 or 0)
end

return run_tests
