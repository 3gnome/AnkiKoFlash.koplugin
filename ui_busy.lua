-- Keep KOReader responsive during long network and dictionary work (Trapper coroutine).

local InfoMessage = require("ui/widget/infomessage")
local Trapper     = require("ui/trapper")
local UIManager   = require("ui/uimanager")
local _           = require("gettext")

local UiBusy = {}

function UiBusy.is_wrapped()
    return Trapper:isWrapped()
end

function UiBusy.pulse(message)
    if Trapper:isWrapped() then
        Trapper:info(message, true, true)
    end
end

-- Run fn() without freezing the UI; dismiss progress when done.
function UiBusy.run(message, fn)
    Trapper:wrap(function()
        Trapper:info(message, false, true)
        local ok, err = xpcall(fn, debug.traceback)
        Trapper:clear()
        if not ok then
            local msg = tostring(err)
            local line = msg:match(":%d+:%s*(.-)\n") or msg:match("(.-\n)") or msg
            UIManager:show(InfoMessage:new {
                text    = _("Operation failed: ") .. line,
                timeout = 8,
            })
            return false
        end
        return true
    end)
end

return UiBusy
