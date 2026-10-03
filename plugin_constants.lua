-- Plugin identity and storage file names.

local PluginConstants = {
    ID   = "ankikoflash",
    NAME = "AnkiKoFlash",

    VOCABULARY_CARD_LABEL = "Vocabulary Card",

    MEMORIZATION_CARD_LABEL = "Memorization Card",

    CARDS_FILE       = "ankikoflash_cards.json",
    SETTINGS_FILE    = "ankikoflash_settings.json",
    RECENT_SENT_FILE = "ankikoflash_recent_sent.json",

    HIGHLIGHT_COLOR_SAVED = "orange",
    HIGHLIGHT_COLOR_SENT  = "green",

    -- KOReader sorts highlight-dialog buttons by id string (99_… sorts after 01_…07_).
    HIGHLIGHT_DIALOG_ID_HUB      = "99_ankikoflash",
    HIGHLIGHT_DIALOG_ID_MEM      = "98_ankikoflash_mem",
    HIGHLIGHT_DIALOG_ID_VIEW_ALL = "97_ankikoflash_view_all",
}

--- True when a URL must not be treated as a live AnkiConnect endpoint:
--- unset, the documented ``192.168.x.x`` placeholder (any case), or the
--- device-local loopback (AnkiConnect lives on the PC, never localhost).
function PluginConstants.is_placeholder_anki_url(url)
    if not url or url == "" then return true end
    local lower = tostring(url):lower()
    if lower:find("192.168.x.x", 1, true) then return true end
    if lower:find("localhost", 1, true) then return true end
    if lower:find("127.0.0.1", 1, true) then return true end
    return false
end

return PluginConstants
