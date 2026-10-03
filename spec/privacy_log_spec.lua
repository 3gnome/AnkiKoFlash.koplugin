local function run_tests(assert_eq, assert_true)
    local names = { "privacy_log", "logger", "plugin_constants" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local output = {}
    package.loaded["logger"] = {
        warn = function(...)
            for i = 1, select("#", ...) do
                output[#output + 1] = tostring(select(i, ...))
            end
        end,
    }
    package.loaded["plugin_constants"] = { ID = "ankikoflash" }
    package.loaded["privacy_log"] = nil

    local PrivacyLog = require("privacy_log")
    PrivacyLog.warn("storage failure", {
        api_key = "TOP-SECRET-KEY",
        highlight = "PRIVATE HIGHLIGHT",
        url = "https://user:pass@example.test/path?key=SECRET",
        reason = "write_failed",
        failed = 2,
    })
    local line = table.concat(output, " ")
    assert_true(not line:find("TOP-SECRET-KEY", 1, true),
        "API keys are redacted")
    assert_true(not line:find("PRIVATE HIGHLIGHT", 1, true),
        "highlight text is redacted")
    assert_true(not line:find("user:pass", 1, true),
        "credential-bearing URLs are redacted")
    assert_true(not line:find("?key=", 1, true),
        "query keys are redacted")
    assert_true(line:find("reason=write_failed", 1, true) ~= nil,
        "safe reason code remains useful")
    assert_true(line:find("failed=2", 1, true) ~= nil,
        "safe count remains useful")

    assert_eq(PrivacyLog.reason_code(
        "HTTP 503: https://provider.test?key=SECRET"), "http_503",
        "reason classification does not expose provider response")
    assert_eq(PrivacyLog.reason_code({ code = "write_failed" }), "write_failed",
        "structured storage code remains concise")

    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

return run_tests
