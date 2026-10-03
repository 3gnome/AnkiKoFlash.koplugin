#!/usr/bin/env luajit

local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    return TestSupport.with_package_loaded(
        { "json", "atomic_json" }, {}, function()
    local activity = 0
    package.loaded["json"] = {
        encode = function()
            error("encode rejected")
        end,
    }
    package.loaded["atomic_json"] = nil
    local AtomicJson = require("atomic_json")

    local ok, reason = AtomicJson.write("cards.json", {}, {
        open = function() activity = activity + 1 end,
        rename = function() activity = activity + 1 end,
        remove = function() activity = activity + 1 end,
        token = "encode",
    })
    assert_true(not ok, "encode failure is reported")
    assert_eq(reason.code, "encode_failed", "encode failure has structured reason")
    assert_eq(activity, 0, "encode completes before filesystem mutation")

    package.loaded["atomic_json"] = nil
    package.loaded["json"] = {
        encode = function() return "{\"state\":\"new\"}" end,
        decode = function(content)
            if content == "{\"state\":\"new\"}" then
                return { state = "new" }
            elseif content == "{\"state\":\"original\"}" then
                return { state = "original" }
            elseif content == "[{\"state\":\"original\"}]" then
                return { { state = "original" } }
            end
            error("malformed json")
        end,
    }
    AtomicJson = require("atomic_json")

    local removed_temp
    ok, reason = AtomicJson.write("cards.json", {}, {
        open = function()
            return {
                write = function() return true end,
                close = function() return nil, "disk full" end,
            }
        end,
        rename = function() error("rename must not run after close failure") end,
        remove = function(path) removed_temp = path; return true end,
        token = "close",
    })
    assert_true(not ok, "close failure is reported")
    assert_eq(reason.code, "temp_write_failed", "close failure has structured reason")
    assert_eq(removed_temp, "cards.json.tmp.close",
        "owned temp is removed after close failure")

    local function fallback_io(fail_install, fail_restore, fail_cleanup)
        local files = { ["cards.json"] = "{\"state\":\"original\"}" }
        local pending_path, pending_content
        local backup_path = AtomicJson.backup_path("cards.json")
        local ops
        ops = {
            fail_install = fail_install,
            fail_restore = fail_restore,
            fail_cleanup = fail_cleanup,
            open = function(path)
                pending_path = path
                return {
                    write = function(_, content)
                        pending_content = content
                        return true
                    end,
                    close = function()
                        files[pending_path] = pending_content
                        return true
                    end,
                }
            end,
            rename = function(from, to)
                if files[from] == nil then return nil, "missing source" end
                if to == "cards.json" and files[to] ~= nil then
                    return nil, "destination exists"
                end
                if ops.fail_install and from:find("%.tmp%.", 1, false)
                    and to == "cards.json" then
                    return nil, "install failed"
                end
                if ops.fail_restore and from == backup_path
                    and to == "cards.json" then
                    return nil, "restore failed"
                end
                files[to] = files[from]
                files[from] = nil
                return true
            end,
            remove = function(path)
                if ops.fail_cleanup and path == backup_path then
                    return nil, "cleanup failed"
                end
                files[path] = nil
                return true
            end,
            probe = function(path)
                return files[path] ~= nil and "present" or "absent"
            end,
            validate = function(path)
                local content = files[path]
                return content == "{\"state\":\"new\"}"
                    or content == "{\"state\":\"original\"}"
                    or content == "[{\"state\":\"original\"}]"
            end,
        }
        return files, ops
    end

    local files, ops = fallback_io(false)
    ops.token = "success"
    ok, reason = AtomicJson.write("cards.json", {}, ops)
    assert_true(ok, "Windows fallback installs completed temp")
    assert_eq(files["cards.json"], "{\"state\":\"new\"}",
        "fallback replaces destination")
    assert_true(files["cards.json.tmp.success"] == nil,
        "successful fallback leaves no temp")
    assert_true(files[AtomicJson.backup_path("cards.json")] == nil,
        "successful fallback leaves no backup")

    files, ops = fallback_io(true)
    ops.token = "restore"
    ok, reason = AtomicJson.write("cards.json", {}, ops)
    assert_true(not ok, "failed fallback replacement is reported")
    assert_eq(reason.code, "replace_failed",
        "failed fallback replacement has structured reason")
    assert_true(reason.restored, "failed fallback confirms original restoration")
    assert_eq(files["cards.json"], "{\"state\":\"original\"}",
        "failed fallback restores original destination")
    assert_true(files["cards.json.tmp.restore"] == nil,
        "failed fallback cleans owned temp")
    assert_true(files[AtomicJson.backup_path("cards.json")] == nil,
        "restored fallback cleans owned backup")

    files, ops = fallback_io(true, true, false)
    ops.token = "interrupted"
    ok, reason = AtomicJson.write("cards.json", {}, ops)
    assert_true(not ok, "interrupted fallback reports restore failure")
    assert_eq(reason.code, "restore_failed",
        "interrupted fallback exposes recoverable reason")
    assert_true(files["cards.json"] == nil,
        "interrupted fallback may leave canonical absent")
    assert_eq(files[AtomicJson.backup_path("cards.json")],
        "{\"state\":\"original\"}",
        "interrupted fallback retains stable owned backup")
    ops.fail_install = false
    ops.fail_restore = false
    ok, reason = AtomicJson.recover("cards.json", ops)
    assert_true(ok, "next reader restores interrupted fallback")
    assert_eq(reason.code, "backup_recovered",
        "reader reports canonical recovery")
    assert_eq(files["cards.json"], "{\"state\":\"original\"}",
        "reader restores canonical from stable backup")
    assert_true(files[AtomicJson.backup_path("cards.json")] == nil,
        "recovery consumes stable backup")

    files, ops = fallback_io(false, false, true)
    ops.token = "cleanup"
    ok, reason = AtomicJson.write("cards.json", {}, ops)
    assert_true(ok, "post-commit backup cleanup failure remains success")
    assert_eq(reason.code, "backup_cleanup_failed",
        "post-commit cleanup returns warning metadata")
    assert_true(reason.committed, "cleanup warning explicitly reports commit")
    assert_eq(files["cards.json"], "{\"state\":\"new\"}",
        "cleanup warning keeps committed canonical data")
    assert_eq(files[AtomicJson.backup_path("cards.json")],
        "{\"state\":\"original\"}",
        "cleanup warning retains recoverable owned backup")
    ops.fail_cleanup = false
    ok = AtomicJson.recover("cards.json", ops)
    assert_true(ok, "later read cleans stale committed backup")
    assert_eq(files["cards.json"], "{\"state\":\"new\"}",
        "canonical data wins over stale backup")
    assert_true(files[AtomicJson.backup_path("cards.json")] == nil,
        "later read removes stale owned backup")

    files, ops = fallback_io(false)
    local stable_backup = AtomicJson.backup_path("cards.json")
    files["cards.json"] = "{\"state\":"
    files[stable_backup] = "{\"state\":\"original\"}"
    ok, reason = AtomicJson.recover("cards.json", ops)
    assert_true(ok, "torn canonical recovers from valid stable backup")
    assert_eq(reason.code, "backup_recovered",
        "torn-canonical recovery is reported")
    assert_eq(files["cards.json"], "{\"state\":\"original\"}",
        "valid backup replaces malformed canonical")
    assert_true(files[stable_backup] == nil,
        "successful restore moves valid backup to canonical")

    files, ops = fallback_io(false)
    stable_backup = AtomicJson.backup_path("cards.json")
    files["cards.json"] = "{\"state\":"
    files[stable_backup] = "[broken"
    ok, reason = AtomicJson.recover("cards.json", ops)
    assert_true(not ok, "two invalid crash-window copies fail recovery")
    assert_eq(reason.code, "recovery_no_valid_json",
        "two invalid copies return structured recovery failure")
    assert_eq(files["cards.json"], "{\"state\":",
        "failed recovery retains malformed canonical for diagnosis")
    assert_eq(files[stable_backup], "[broken",
        "failed recovery never destroys invalid stable backup")

    local generic_files = {
        ["generic.json"] = "{\"state\":\"new\"}",
        [AtomicJson.backup_path("generic.json")] =
            "[{\"state\":\"original\"}]",
    }
    local generic_ops = {
        open = function(path)
            local content = generic_files[path]
            if not content then return nil, "missing", 2 end
            return {
                read = function() return content end,
                close = function() return true end,
            }
        end,
        probe = function(path)
            return generic_files[path] and "present" or "absent"
        end,
        remove = function(path)
            generic_files[path] = nil
            return true
        end,
        rename = function(from, to)
            if not generic_files[from] then return nil, "missing" end
            generic_files[to] = generic_files[from]
            generic_files[from] = nil
            return true
        end,
    }
    ok = AtomicJson.recover("generic.json", generic_ops)
    assert_true(ok, "valid object canonical passes generic JSON validation")
    assert_true(generic_files[AtomicJson.backup_path("generic.json")] == nil,
        "valid object canonical permits stale backup cleanup")

    generic_files["generic.json"] = "{torn"
    generic_files[AtomicJson.backup_path("generic.json")] =
        "[{\"state\":\"original\"}]"
    ok, reason = AtomicJson.recover("generic.json", generic_ops)
    assert_true(ok, "valid array backup passes generic JSON validation")
    assert_eq(reason.code, "backup_recovered",
        "valid array backup restores malformed object canonical")
    assert_eq(generic_files["generic.json"], "[{\"state\":\"original\"}]",
        "generic recovery installs valid array JSON")

    end)
end

return run_tests
