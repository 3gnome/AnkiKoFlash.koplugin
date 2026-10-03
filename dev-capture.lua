-- dev-capture.lua — dev-only OCR harness hook (no-op in production).
--
-- When KOREADER_CAPTURE_DIR is set in the environment, this module polls that
-- directory for a `_capture.now` sentinel file. On sight it removes the
-- sentinel, captures the current screen via Device.screen:shot() to shot.png,
-- then writes `shot.done` so the cursor-shift driver (on Windows) can OCR the
-- PNG. Without the env var nothing runs — safe to ship in the plugin.
--
-- Shared across plugins: only the first watcher to start is active (see the
-- _G guard), so loading two plugins that both embed this file is harmless.

local UIManager = require("ui/uimanager")
local Device    = require("device")

local DevCapture = {}

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function log(msg)
    local ok, logger = pcall(require, "logger")
    if ok and logger and logger.info then
        logger.info("dev-capture", msg)
    end
end

function DevCapture.start()
    local dir = os.getenv("KOREADER_CAPTURE_DIR")
    if not dir or dir == "" then
        return -- production: disabled
    end
    -- One watcher per reader process, even if both plugins embed this file.
    if rawget(_G, "__KO_OCR_CAPTURE_ACTIVE") then
        return
    end
    rawset(_G, "__KO_OCR_CAPTURE_ACTIVE", true)

    local sentinel  = dir .. "/_capture.now"
    local shot_path = dir .. "/shot.png"
    local done_path = dir .. "/shot.done"

    local function tick()
        UIManager:scheduleIn(0.5, tick)
        if not file_exists(sentinel) then
            return
        end
        os.remove(sentinel)
        local ok, err = pcall(function()
            Device.screen:shot(shot_path)
        end)
        local f = io.open(done_path, "w")
        if f then
            f:write(ok and "ok" or ("err:" .. tostring(err)))
            f:close()
        end
    end

    UIManager:scheduleIn(1, tick)
    log("OCR capture watcher enabled → " .. dir)
end

return DevCapture
