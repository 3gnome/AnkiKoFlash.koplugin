-- Per card-type defaults and auto-send flags (saved in ankikoflash_settings.json).

local CardFields       = require("card_fields")
local NoteTypeProfiles = require("note_type_profiles")
local PluginConstants  = require("plugin_constants")

local CardDefaults = {}

function CardDefaults.merged(config)
    return CardFields.merged_anki_settings(config)
end

function CardDefaults.vocabulary_model(config)
    return CardFields.default_vocabulary_model(config)
end

function CardDefaults.memorization_model(config)
    return CardFields.default_memorization_model(config)
end

local function legacy_deck(ac)
    return (ac.deck and ac.deck ~= "") and ac.deck or nil
end

function CardDefaults.vocabulary_deck(config)
    local ac = CardDefaults.merged(config)
    if ac.vocabulary_deck and ac.vocabulary_deck ~= "" then return ac.vocabulary_deck end
    return legacy_deck(ac)
end

local function wrap_config(config)
    if config and config.anki then return config end
    return { anki = config }
end

-- Default deck for a saved/generated card (by note type).
function CardDefaults.deck_for_card(config, card)
    local wrapped = wrap_config(config)
    local model = card and card.model
    if model and model ~= "" then
        if NoteTypeProfiles.is_vocabulary_card(model) then
            return CardDefaults.vocabulary_deck(wrapped)
        elseif NoteTypeProfiles.is_memorization(model) then
            return CardDefaults.memorization_parent_deck(wrapped)
        end
    end
    return CardDefaults.vocabulary_deck(wrapped)
end

-- Distinct configured deck names (for picker fallbacks).
function CardDefaults.configured_deck_names(config)
    local wrapped = wrap_config(config)
    local names, seen = {}, {}
    for _i, fn in ipairs({
        CardDefaults.vocabulary_deck,
        CardDefaults.memorization_parent_deck,
    }) do
        local d = fn(wrapped)
        if d and d ~= "" and not seen[d] then
            seen[d] = true
            names[#names + 1] = d
        end
    end
    return names
end

function CardDefaults.memorization_parent_deck(config)
    local ac = CardDefaults.merged(config)
    if ac.memorize_parent_deck and ac.memorize_parent_deck ~= "" then
        return ac.memorize_parent_deck
    end
    if ac.memorize and type(ac.memorize) == "table" and ac.memorize.parent_deck then
        return ac.memorize.parent_deck
    end
    return "Memorize"
end

function CardDefaults.vocabulary_dictionary(config)
    local ac = CardDefaults.merged(config)
    local name = ac.vocabulary_preferred_dictionary
    if name and name ~= "" then return name end
    return nil
end

function CardDefaults.etymology_dictionary(config)
    local ac = CardDefaults.merged(config)
    local name = ac.etymology_preferred_dictionary
    if name and name ~= "" then return name end
    return nil
end

function CardDefaults.auto_send_vocabulary(config)
    local ac = CardDefaults.merged(config)
    return ac.auto_send_vocabulary == true
end

function CardDefaults.save_only_vocabulary(config)
    local ac = CardDefaults.merged(config)
    return ac.save_only_vocabulary == true
end

-- Hands-off auto flow: skip note-type + dictionary pickers without sending.
function CardDefaults.vocab_auto_flow(config)
    return CardDefaults.auto_send_vocabulary(config)
        or CardDefaults.save_only_vocabulary(config)
end

function CardDefaults.auto_send_memorization(config)
    local ac = CardDefaults.merged(config)
    return ac.auto_send_memorization == true
end

function CardDefaults.auto_send_skip_hub_submenu(config)
    local ac = CardDefaults.merged(config)
    return ac.auto_send_skip_hub_submenu == true
end

function CardDefaults.quick_highlight_button(config)
    local ac = CardDefaults.merged(config)
    return ac.memorize_quick_highlight_button == true
end

local function trimmed_hub_label(value, fallback)
    if value and type(value) == "string" then
        local t = value:match("^%s*(.-)%s*$") or ""
        if t ~= "" then return t end
    end
    return fallback
end

function CardDefaults.vocabulary_hub_label(config)
    local ac = CardDefaults.merged(config)
    return trimmed_hub_label(ac.vocabulary_card_hub_label, PluginConstants.VOCABULARY_CARD_LABEL)
end

-- Flatten hub submenu when auto-send is on for this card type (or legacy mem-only flag).
function CardDefaults.should_flatten_hub(config, card_kind)
    local ac = CardDefaults.merged(config)
    if ac.auto_send_skip_hub_submenu == true then
        if card_kind == "vocabulary" then
            return CardDefaults.auto_send_vocabulary(config)
        elseif card_kind == "memorization" then
            return CardDefaults.auto_send_memorization(config)
        end
    end
    if card_kind == "memorization" and ac.memorize_skip_hub_submenu == true then
        return true
    end
    return false
end

return CardDefaults
