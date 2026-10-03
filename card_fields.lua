-- Normalize card field storage: flat legacy keys + dynamic anki_fields table.

local NoteTypeProfiles = require("note_type_profiles")
local CardStorage      = require("card_storage")
local _                = require("gettext")

local CardFields = {}

local function merged_anki_settings(config)
    local cfg = {}
    if config and type(config.anki) == "table" then
        for k, v in pairs(config.anki) do cfg[k] = v end
    end
    local saved = CardStorage.load_anki_settings()
    if saved then
        for k, v in pairs(saved) do cfg[k] = v end
    end
    return cfg
end

function CardFields.default_vocabulary_model(config)
    local ac = merged_anki_settings(config)
    local name = ac.vocabulary_model or NoteTypeProfiles.VOCABULARY_CARD_MODEL
    if NoteTypeProfiles.is_vocabulary_compatible(name) then
        return name
    end
    return NoteTypeProfiles.VOCABULARY_CARD_MODEL
end

function CardFields.default_memorization_model(config)
    local ac = merged_anki_settings(config)
    local name = ac.memorize_model
    if (not name or name == "") and ac.memorize and type(ac.memorize) == "table" then
        name = ac.memorize.model
    end
    name = name or NoteTypeProfiles.MEMORIZATION_MODEL
    if NoteTypeProfiles.is_memorization_compatible(name) then
        return name
    end
    return NoteTypeProfiles.MEMORIZATION_MODEL
end

-- Scrub retired AI / Wiki Card settings, any stored API keys, and migrate
-- legacy vocabulary/memorization settings. Mutates settings in place.
-- Returns optional user-facing notice (newline-separated).
function CardFields.migrate_anki_settings(settings)
    if type(settings) ~= "table" then return settings, nil end

    local notices = {}
    local migration_changed = false
    local function set_value(key, value)
        if settings[key] ~= value then
            settings[key] = value
            migration_changed = true
        end
    end
    local function clear_value(key)
        if settings[key] ~= nil then
            settings[key] = nil
            migration_changed = true
        end
    end
    local function ensure_memorize_table()
        if type(settings.memorize) ~= "table" then
            set_value("memorize", {})
        end
        return settings.memorize
    end
    local function set_memorize_model(value)
        local memorize = ensure_memorize_table()
        if memorize.model ~= value then
            memorize.model = value
            migration_changed = true
        end
    end

    -- Retired Wiki Card keys and every AI provider / API-key / prompt key.
    local scrub_keys = {
        "wiki_note_type", "wiki_model", "wiki_deck", "wiki_card_hub_label",
        "wiki_hub_label", "auto_send_wiki", "wiki_enabled", "model",
        "text_provider", "openai_api_key", "gemini_api_key", "dashscope_api_key",
        "openrouter_api_key", "openrouter_model", "anthropic_api_key",
        "google_api_key", "custom_prompts", "prompt_suffix", "default_prompt",
        "prompts", "llm_model", "llm_provider",
    }
    for _, key in ipairs(scrub_keys) do
        clear_value(key)
    end

    -- send_on_save (removed) → per-type auto-send toggles
    if settings.send_on_save == true then
        if settings.auto_send_vocabulary ~= true then
            set_value("auto_send_vocabulary", true)
        end
        if settings.auto_send_memorization ~= true then
            set_value("auto_send_memorization", true)
        end
        clear_value("send_on_save")
        table.insert(notices, _(
            "“Send after generate” is now per card type under Card defaults."))
    end

    -- Legacy memorization auto-send key
    if settings.memorize_auto_send == true and settings.auto_send_memorization ~= true then
        set_value("auto_send_memorization", true)
    end
    clear_value("memorize_auto_send")

    -- Legacy skip-hub → unified toggle when unset
    if settings.auto_send_skip_hub_submenu == nil
       and settings.memorize_skip_hub_submenu == true then
        set_value("auto_send_skip_hub_submenu", true)
    end

    -- Legacy shared deck → per-type defaults
    local legacy_deck = (settings.deck and settings.deck ~= "") and settings.deck or nil
    if legacy_deck then
        if not settings.vocabulary_deck or settings.vocabulary_deck == "" then
            set_value("vocabulary_deck", legacy_deck)
        end
    end

    local vocab = settings.vocabulary_model or NoteTypeProfiles.VOCABULARY_CARD_MODEL
    if not NoteTypeProfiles.is_vocabulary_compatible(vocab) then
        set_value("vocabulary_model", NoteTypeProfiles.VOCABULARY_CARD_MODEL)
        table.insert(notices, _("Invalid vocabulary note type; using Vocabulary Card."))
    end

    local mem = settings.memorize_model
    if (not mem or mem == "") and settings.memorize and type(settings.memorize) == "table" then
        mem = settings.memorize.model
    end
    if mem and mem ~= "" and not NoteTypeProfiles.is_memorization_compatible(mem) then
        set_value("memorize_model", NoteTypeProfiles.MEMORIZATION_MODEL)
        set_memorize_model(NoteTypeProfiles.MEMORIZATION_MODEL)
        table.insert(notices, _("Invalid memorization note type; using Memorization."))
    end

    if settings.max_memorization_steps == nil then
        set_value("max_memorization_steps", 80)
    else
        local max_steps = tonumber(settings.max_memorization_steps)
        if not max_steps or max_steps < 1 then
            set_value("max_memorization_steps", 80)
        else
            local normalized = math.floor(max_steps)
            if settings.max_memorization_steps ~= normalized then
                set_value("max_memorization_steps", normalized)
            end
        end
    end

    if #notices == 0 then return settings, nil, migration_changed end
    return settings, table.concat(notices, "\n"), migration_changed
end

function CardFields.merged_anki_settings(config)
    return merged_anki_settings(config)
end

-- Citation string from open book metadata (preferred for Source field).
function CardFields.format_book_source(title, author)
    title  = (title  or ""):match("^%s*(.-)%s*$") or ""
    author = (author or ""):match("^%s*(.-)%s*$") or ""
    if title ~= "" and author ~= "" then
        return title .. " — " .. author
    elseif title ~= "" then
        return title
    elseif author ~= "" then
        return author
    end
    return ""
end

function CardFields.set_source(card, source)
    if not card or not source or source == "" then return end
    card.source = source
    card.anki_fields = card.anki_fields or {}
    card.anki_fields.Source = source
end

-- Source = book citation when reading; optional fallback (e.g. dictionary URL).
function CardFields.apply_reading_source(card, title, author, fallback, location)
    if not card then return end
    local book = CardFields.format_book_source(title, author)
    if location and location ~= "" then
        if book ~= "" then
            book = book .. " (" .. location .. ")"
        else
            book = location
        end
    end
    if book ~= "" then
        CardFields.set_source(card, book)
        return
    end
    if type(fallback) == "string" and fallback ~= "" then
        CardFields.set_source(card, fallback)
    end
end

-- Sync legacy flat keys from anki_fields.
function CardFields.sync_flat_from_anki(card)
    if not card or type(card.anki_fields) ~= "table" then return end
    local f = card.anki_fields
    card.phrase     = f.Phrase     or f.phrase     or card.phrase     or ""
    card.definition = f.Definition or f.definition or card.definition or ""
    card.context    = f.Context    or f.context    or card.context   or ""
    card.source     = f.Source     or f.source     or card.source     or ""
end

-- Build anki_fields from legacy flat card.
function CardFields.sync_anki_from_flat(card)
    if not card then return end
    card.anki_fields = card.anki_fields or {}
    local f = card.anki_fields
    if card.phrase     and card.phrase     ~= "" then f.Phrase     = card.phrase     end
    if card.definition and card.definition ~= "" then f.Definition = card.definition end
    if card.context    and card.context    ~= "" then f.Context    = card.context    end
    if card.source     and card.source     ~= "" then f.Source     = card.source     end
end

function CardFields.normalize(card, config)
    if type(card) ~= "table" then return card end
    card.model = NoteTypeProfiles.normalize_model_name(
        card.model or card.target_model or CardFields.default_vocabulary_model(config))

    if type(card.anki_fields) == "table" and next(card.anki_fields) then
        CardFields.sync_flat_from_anki(card)
    else
        CardFields.sync_anki_from_flat(card)
    end

    if card.phrase == "" then
        card.phrase = card.anki_fields.Phrase or card.anki_fields.Front
                      or card.anki_fields.front or ""
    end
    return card
end

-- Map an Anki field name to a piece of dictionary data by common conventions.
-- Returns (value, role) or nil if the field name isn't recognized.
local function dictionary_value_for_field(fname, data)
    local n = (fname or ""):lower():gsub("%s+", "")
    if n == "phrase" or n == "word" or n == "term" or n == "vocabulary"
       or n == "vocab" or n == "headword" or n == "expression"
       or n == "front" or n == "question" or n == "prompt" then
        return data.phrase, "term"
    end
    if n == "definition" or n == "meaning" or n == "def" or n == "gloss"
       or n == "explanation" or n == "back" or n == "answer" or n == "response"
       or n == "notes" or n == "note" or n == "extra" then
        return data.definition, "definition"
    end
    if n == "context" or n == "example" or n == "examples" or n == "sentence"
       or n == "passage" or n == "usage" or n == "quote" or n == "excerpt" then
        return data.context, "context"
    end
    if n == "etymology" or n == "origin" or n == "root" or n == "derivation" then
        return data.etymology, "etymology"
    end
    if n == "source" or n == "reference" or n == "book" or n == "citation" then
        return data.source, "source"
    end
    return nil
end

-- Build the Anki field payload for a dictionary (no-AI) card, mapping the
-- looked-up word/definition/etymology/passage/source onto whatever fields the
-- chosen note type actually has. Falls back so content is never silently dropped.
function CardFields.dictionary_fields_for_send(card, field_names)
    card = card or {}
    local af = card.anki_fields or {}
    local data = {
        phrase     = card.phrase     or af.Phrase     or "",
        definition = card.definition or af.Definition or "",
        etymology  = card.etymology  or af.Etymology  or "",
        context    = card.context    or card.text or af.Context or "",
        source     = card.source     or af.Source     or "",
    }

    field_names = field_names or {}
    if #field_names == 0 then
        return {
            Phrase     = data.phrase,
            Definition = data.definition,
            Etymology  = data.etymology,
            Context    = data.context,
            Source     = data.source,
        }
    end

    local out = {}
    local term_field, def_field, context_matched
    for _, fname in ipairs(field_names) do
        local v, role = dictionary_value_for_field(fname, data)
        out[fname] = v or ""
        if role == "term"       and not term_field then term_field = fname end
        if role == "definition" and not def_field  then def_field  = fname end
        if role == "context"    and v and v ~= ""  then context_matched = true end
    end

    -- Fallbacks for note types that don't use recognizable field names.
    if not term_field and data.phrase ~= "" then
        term_field = field_names[1]
        out[term_field] = data.phrase
    end
    if not def_field and data.definition ~= "" then
        for _, fname in ipairs(field_names) do
            if fname ~= term_field then def_field = fname break end
        end
        def_field = def_field or term_field or field_names[1]
        local existing = out[def_field] or ""
        out[def_field] = (existing ~= "" and (existing .. "\n\n") or "") .. data.definition
    end
    -- Keep the book passage even when the note type has no context field.
    if not context_matched and data.context ~= "" and def_field then
        out[def_field] = (out[def_field] ~= "" and (out[def_field] .. "\n\n") or "")
                         .. data.context
    end

    return out
end

-- True when the chosen note type has no field that can hold a non-empty
-- etymology, so ``dictionary_fields_for_send`` would silently drop it. Callers
-- use this to surface a notice instead of losing the looked-up etymology.
function CardFields.etymology_will_be_dropped(card, field_names)
    if not card or not card.etymology or card.etymology == "" then
        return false
    end
    local probe = { etymology = card.etymology }
    for _, fname in ipairs(field_names or {}) do
        local _, role = dictionary_value_for_field(fname, probe)
        if role == "etymology" then return false end
    end
    return true
end

function CardFields.fields_for_send(card, field_names)
    local out = {}
    local src = card.anki_fields or {}
    for _, fname in ipairs(field_names or {}) do
        out[fname] = src[fname] or ""
    end
    -- Legacy fallback
    if not next(out) then
        out = {
            Phrase     = card.phrase     or "",
            Definition = card.definition or "",
            Etymology  = card.etymology  or "",
            Context    = card.context    or "",
            Source     = card.source     or "",
        }
    end
    return out
end

function CardFields.editable_field_list(card)
    card = CardFields.normalize(card, {})
    local skip = { Source = true, source = true }
    local list = {}
    if type(card.anki_fields) == "table" then
        for fname, val in pairs(card.anki_fields) do
            if not skip[fname] then
                table.insert(list, { key = fname, label = fname, anki = true })
            end
        end
        table.sort(list, function(a, b) return a.label < b.label end)
    end
    if #list == 0 then
        return {
            { key = "phrase",     label = "Phrase" },
            { key = "definition", label = "Definition" },
            { key = "etymology",  label = "Etymology" },
            { key = "context",    label = "Context" },
        }
    end
    return list
end

function CardFields.use_rich_viewer(card, config)
    card = CardFields.normalize(card, config)
    if NoteTypeProfiles.is_vocabulary_card(card.model) then
        local names = {}
        for k in pairs(card.anki_fields or {}) do table.insert(names, k) end
        if #names == 0 then return true end
        return NoteTypeProfiles.vocabulary_field_set(names)
    end
    return false
end

function CardFields.is_dictionary_card(card, config)
    card = CardFields.normalize(card, config)
    return NoteTypeProfiles.is_vocabulary_card(card.model)
        or card.dictionary_only == true
end

return CardFields
