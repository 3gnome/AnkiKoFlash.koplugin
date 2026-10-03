-- Update highlight colors for saved / sent cards.

local PluginConstants = require("plugin_constants")
local PositionUtils = require("position_utils")

local HighlightStatus = {}

local function find_annotation(ui, pos0, pos1)
    if not ui or not ui.annotation or not ui.annotation.annotations then
        return nil
    end
    for idx, ann in ipairs(ui.annotation.annotations) do
        if PositionUtils.equal(ann.pos0, pos0)
            and (not pos1 or PositionUtils.equal(ann.pos1, pos1)) then
            return ann, idx
        end
    end
    return nil
end

function HighlightStatus.set_color(ui, pos0, pos1, color)
    local ann = find_annotation(ui, pos0, pos1)
    if ann and color and color ~= "" then
        ann.color = color
    end
end

function HighlightStatus.mark_saved(ui, pos0, pos1)
    HighlightStatus.set_color(ui, pos0, pos1, PluginConstants.HIGHLIGHT_COLOR_SAVED)
end

function HighlightStatus.mark_sent(ui, pos0, pos1)
    HighlightStatus.set_color(ui, pos0, pos1, PluginConstants.HIGHLIGHT_COLOR_SENT)
end

function HighlightStatus.remove_highlight(ui, pos0, pos1)
    local ann, idx = find_annotation(ui, pos0, pos1)
    if not idx then return false end
    if ui and ui.highlight and ui.highlight.deleteHighlight then
        ui.highlight:deleteHighlight(idx)
        return true
    end
    return false
end

return HighlightStatus
