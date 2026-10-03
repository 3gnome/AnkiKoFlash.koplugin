-- Remove orphan AnkiKoFlash vocab/mem highlights left after background send.

local PluginConstants = require("plugin_constants")
local PositionUtils = require("position_utils")

local HighlightCleanup = {}

HighlightCleanup.MAX_AGE_SEC = 7 * 24 * 3600

local function normalize_phrase(text)
    if type(text) ~= "string" then return "" end
    return text:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function HighlightCleanup.should_remove_annotation(ann, entry, now, document_path)
    if not ann or not entry then
        return false
    end
    if not document_path or document_path == ""
        or not entry.document_path or entry.document_path ~= document_path then
        return false
    end
    now = now or os.time()
    local kind = entry.card_kind or ""
    if kind ~= "vocabulary" and kind ~= "memorization" then
        return false
    end
    if ann.color ~= PluginConstants.HIGHLIGHT_COLOR_SAVED then
        return false
    end
    if not entry.highlight_pos0
        or not PositionUtils.equal(ann.pos0, entry.highlight_pos0) then
        return false
    end
    if entry.highlight_pos1
        and not PositionUtils.equal(ann.pos1, entry.highlight_pos1) then
        return false
    end
    local stored_text = kind == "memorization"
        and entry.memorization_text or entry.phrase
    if normalize_phrase(stored_text) == ""
        or normalize_phrase(ann.text) ~= normalize_phrase(stored_text) then
        return false
    end
    local sent_at = entry.sent_at or 0
    if sent_at <= 0 or (now - sent_at) > HighlightCleanup.MAX_AGE_SEC then
        return false
    end
    return true
end

function HighlightCleanup.find_removable_positions(
    annotations, recent_entries, now, document_path)
    local out = {}
    local seen = {}
    annotations = annotations or {}
    recent_entries = recent_entries or {}
    if not document_path or document_path == "" then return out end
    for _, entry in ipairs(recent_entries) do
        local key = entry.highlight_pos0
            and PositionUtils.pair_key(entry.highlight_pos0, entry.highlight_pos1)
        if key and not seen[key] then
            for _, ann in ipairs(annotations) do
                if HighlightCleanup.should_remove_annotation(
                    ann, entry, now, document_path) then
                    out[#out + 1] = {
                        pos0 = ann.pos0,
                        pos1 = ann.pos1,
                    }
                    seen[key] = true
                    break
                end
            end
        end
    end
    return out
end

function HighlightCleanup.run(ui)
    if not ui or not ui.highlight or not ui.annotation then
        return 0
    end
    local CardStorage = require("card_storage")
    local HighlightStatus = require("highlight_status")
    local document_path = ui.document and ui.document.file
    if not document_path or document_path == "" then return 0 end
    local annotations = ui.annotation.annotations or {}
    local positions = HighlightCleanup.find_removable_positions(
        annotations, CardStorage.load_recent_sent(), nil, document_path)
    local removed = 0
    for _, pos in ipairs(positions) do
        if HighlightStatus.remove_highlight(ui, pos.pos0, pos.pos1) then
            removed = removed + 1
        end
    end
    return removed
end

return HighlightCleanup
