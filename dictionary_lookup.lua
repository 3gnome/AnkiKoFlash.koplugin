-- Look up a word using KOReader's installed StarDict dictionaries (offline).

local Menu     = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _        = require("gettext")

local Nav = require("nav")

local DictionaryLookup = {}

local MAX_DEFINITION = 4000
local PREVIEW_LEN    = 72

-- Decode a numeric Unicode codepoint to a UTF-8 byte sequence (Lua 5.1 has no
-- native utf8 support, so the bytes are built by hand).
local function utf8_from_codepoint(cp)
    cp = tonumber(cp)
    if not cp or cp < 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
        return ""
    end
    if cp < 0x20 then return " " end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    else
        return string.char(0xF0 + math.floor(cp / 0x40000),
                           0x80 + math.floor(cp / 0x1000) % 0x40,
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
end

-- Named HTML entities (name -> codepoint) that appear in dictionary bodies.
local NAMED_ENTITY_CP = {
    amp = 0x26, lt = 0x3C, gt = 0x3E, quot = 0x22, apos = 0x27,
    mdash = 0x2014, ndash = 0x2013, hellip = 0x2026,
    lsquo = 0x2018, rsquo = 0x2019, ldquo = 0x201C, rdquo = 0x201D,
    bull = 0x2022, middot = 0x00B7, deg = 0x00B0,
    eacute = 0x00E9, egrave = 0x00E8, ecirc = 0x00EA, euml = 0x00EB,
    aacute = 0x00E1, agrave = 0x00E0, acirc = 0x00E2, auml = 0x00E4, aring = 0x00E5,
    iacute = 0x00ED, igrave = 0x00EC, icirc = 0x00EE, iuml = 0x00EF,
    oacute = 0x00F3, ograve = 0x00F2, ocirc = 0x00F4, ouml = 0x00F6,
    uacute = 0x00FA, ugrave = 0x00F9, ucirc = 0x00FB, uuml = 0x00FC,
    ntilde = 0x00F1, ccedil = 0x00E7, szlig = 0x00DF,
    Eacute = 0x00C9, Egrave = 0x00C8, Ecirc = 0x00CA, Euml = 0x00CB,
    Aacute = 0x00C1, Agrave = 0x00C0, Acirc = 0x00C2, Auml = 0x00C4, Aring = 0x00C5,
    Iacute = 0x00CD, Igrave = 0x00CC, Icirc = 0x00CE, Iuml = 0x00CF,
    Oacute = 0x00D3, Ograve = 0x00D2, Ocirc = 0x00D4, Ouml = 0x00D6,
    Uacute = 0x00DA, Ugrave = 0x00D9, Ucirc = 0x00DB, Uuml = 0x00DC,
    Ntilde = 0x00D1, Ccedil = 0x00C7,
}

local function decode_entities(text)
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&(%a+);", function(name)
        local cp = NAMED_ENTITY_CP[name] or NAMED_ENTITY_CP[name:lower()]
        if not cp then return "&" .. name .. ";" end
        return utf8_from_codepoint(cp)
    end)
    text = text:gsub("&#[xX](%x+);", function(h)
        return utf8_from_codepoint(tonumber(h, 16))
    end)
    text = text:gsub("&#(%d+);", function(n)
        return utf8_from_codepoint(tonumber(n))
    end)
    return text
end

local function truncate_utf8(s, max)
    if #s <= max then return s end
    local cut = max
    -- Back up to a lead byte so we never split a multi-byte character.
    while cut > 0 do
        local b = s:byte(cut)
        if b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    if cut == 0 then cut = max end
    return s:sub(1, cut) .. "..."
end

local function strip_html(html, keep_newlines)
    if not html or html == "" then return "" end
    local text = html
    if keep_newlines then
        text = text:gsub("<%s*[bB][rR]%s*/?>", "\n")
        -- Closing block-level tags become line breaks so paragraphs, list items
        -- and headings separate instead of running together.
        text = text:gsub("</%s*[pP]%s*>", "\n")
        text = text:gsub("</%s*[dD][iI][vV]%s*>", "\n")
        text = text:gsub("</%s*[lL][iI]%s*>", "\n")
        text = text:gsub("</%s*[tT][rR]%s*>", "\n")
        text = text:gsub("</%s*[hH][1-6]%s*>", "\n")
        text = text:gsub("</%s*[dD][dDtT]%s*>", "\n")
    else
        text = text:gsub("<%s*[bB][rR]%s*/?>", " ")
    end
    -- Replace any remaining tag with a space (never an empty string) so inline
    -- elements like <b>Adverb</b>In… don't glue into "AdverbIn".
    text = text:gsub("<[^>]+>", " ")
    text = decode_entities(text)
    if keep_newlines then
        text = text:gsub("[ \t]+", " ")
        text = text:gsub("\n[ \t]+", "\n")
        text = text:gsub("[ \t]+\n", "\n")
        text = text:gsub("\n\n\n+", "\n\n")
        text = text:match("^%s*(.-)%s*$") or ""
    else
        text = text:gsub("[ \t\r\n]+", " "):match("^%s*(.-)%s*$") or ""
    end
    text = truncate_utf8(text, MAX_DEFINITION)
    return text
end

local function preview_text(definition)
    local s = (definition or ""):gsub("\n", " "):match("^%s*(.-)%s*$") or ""
    return truncate_utf8(s, PREVIEW_LEN)
end

local function reader_settings()
    if rawget(_G, "G_reader_settings") and G_reader_settings then
        return G_reader_settings
    end
    local ok, ls = pcall(require, "luasettings")
    if ok and ls and ls.open then
        local ok2, settings = pcall(function() return ls:open("reader.lua") end)
        if ok2 then return settings end
    end
    return nil
end

local function fuzzy_search_enabled(dict_module)
    if dict_module.disable_fuzzy_search ~= nil then
        return not dict_module.disable_fuzzy_search
    end
    if dict_module.disable_fuzzy_search_fm ~= nil then
        return not dict_module.disable_fuzzy_search_fm
    end
    local settings = reader_settings()
    if settings and settings.nilOrFalse then
        return settings:nilOrFalse("disable_fuzzy_search")
    end
    return false
end

local function same_word(a, b)
    a = (a or ""):lower()
    b = (b or ""):lower()
    return a == b
end

local function normalize_entry(raw, fallback_word)
    if not raw or raw.no_result then return nil end
    local definition = strip_html(raw.definition or "", true)
    if definition == "" then return nil end
    return {
        word       = (raw.word and raw.word ~= "") and raw.word or fallback_word,
        definition = definition,
        dict       = raw.dict or "",
        preview    = preview_text(definition),
    }
end

local function run_lookup(ui, word, opts)
    opts = opts or {}
    word = (word or ""):match("^%s*(.-)%s*$") or ""
    if word == "" then
        return nil, _("No word to look up")
    end
    if not ui or not ui.dictionary or not ui.dictionary.startSdcv then
        return nil, _("Dictionary not available in KOReader")
    end

    local dict = ui.dictionary
    local dict_names = dict.enabled_dict_names or dict.preferred_dictionaries
    local fuzzy = fuzzy_search_enabled(dict)
    local results = dict:startSdcv(word, dict_names, fuzzy)

    if not results or #results == 0 then
        return nil, _("No dictionary results")
    end
    if results.lookup_cancelled then
        return nil, _("Dictionary lookup interrupted")
    end

    local entries = {}
    local seen = {}
    for _i, raw in ipairs(results) do
        local entry = normalize_entry(raw, word)
        if entry then
            local key = (entry.dict or "") .. "|" .. (entry.word or "")
                .. "|" .. entry.definition
            if not seen[key] then
                seen[key] = true
                table.insert(entries, entry)
            end
        end
    end

    -- Exclude a single dictionary (e.g. the etymology dictionary) from the
    -- definition results, but never let the exclusion empty the result set.
    local exclude = opts.exclude_dictionary
    if exclude and exclude ~= "" then
        local kept = {}
        for _i, entry in ipairs(entries) do
            if (entry.dict or "") ~= exclude then
                table.insert(kept, entry)
            end
        end
        if #kept > 0 then entries = kept end
    end

    if #entries == 0 then
        return nil, _("No dictionary entry found for this word")
    end
    return entries
end

function DictionaryLookup.lookup_all(ui, word, opts)
    return run_lookup(ui, word, opts)
end

function DictionaryLookup.lookup(ui, word, opts)
    local entries, err = run_lookup(ui, word, opts)
    if not entries then return nil, err end
    return entries[1]
end

-- Reuse the definition already shown in KOReader's DictQuickLookup popup.
-- Returns nil when preferred_dictionary is set but not among popup results
-- (caller should run a fresh StarDict lookup with the same settings).
function DictionaryLookup.lookup_from_popup(popup, opts)
    opts = opts or {}
    if not popup then return nil end

    local word = popup.displayword or popup.lookupword or popup.word
    word = (word or ""):match("^%s*(.-)%s*$") or ""
    if word == "" then return nil end

    local preferred = opts.preferred_dictionary
    local results = popup.results
    if type(results) ~= "table" or #results == 0 then
        if popup.definition and popup.definition ~= "" then
            local def = strip_html(tostring(popup.definition), true)
            if def ~= "" then
                return {
                    word       = word,
                    definition = def,
                    dict       = popup.dictionary or "",
                    preview    = preview_text(def),
                }
            end
        end
        return nil
    end

    local function entry_at(index)
        return normalize_entry(results[index], word)
    end

    if preferred and preferred ~= "" then
        for i = 1, #results do
            if results[i].dict == preferred then
                return entry_at(i)
            end
        end
        return nil
    end

    local idx = tonumber(popup.dict_index) or 1
    if idx < 1 or idx > #results then idx = 1 end
    return entry_at(idx)
end

function DictionaryLookup.show_picker(entries, lookup_word, on_select, opts)
    opts = opts or {}
    lookup_word = lookup_word or ""
    local menu_ref = {}
    local guard = { busy = false }
    local items = {}

    local function finish_cancel()
        if guard.busy then return end
        if opts.on_cancel then
            opts.on_cancel()
        elseif opts.parent_fn then
            opts.parent_fn()
        end
    end

    if opts.parent_fn then
        Nav.prepend_back(items, nil, menu_ref, _("← Back"))
    end

    table.insert(items, {
        text           = _("Tap a dictionary entry to use its definition:"),
        select_enabled = false,
    })

    for _i, entry in ipairs(entries or {}) do
        local dict_label = (entry.dict and entry.dict ~= "") and entry.dict or _("Dictionary")
        local title = dict_label
        if entry.word and not same_word(entry.word, lookup_word) then
            title = title .. " · " .. entry.word
        end

        local function choose()
            guard.busy = true
            if menu_ref[1] then UIManager:close(menu_ref[1]) end
            menu_ref[1] = nil
            guard.busy = false
            if on_select then on_select(entry) end
        end

        table.insert(items, {
            text     = title,
            bold     = true,
            callback = choose,
        })
        if entry.preview and entry.preview ~= "" then
            table.insert(items, {
                text     = entry.preview,
                dim      = true,
                callback = choose,
            })
        end
    end

    menu_ref[1] = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
        title      = _("Choose definition"),
        item_table = items,
    }), finish_cancel)
    Nav.show(menu_ref[1])
end

-- Look up word; if multiple dictionary hits, let the user pick one.
-- opts.preferred_dictionary — prefer entries from this StarDict name
-- opts.auto_pick — when true, use preferred/first entry without showing the menu
-- opts.exclude_dictionary — never offer this StarDict (e.g. etymology dictionary)
function DictionaryLookup.pick(ui, word, on_select, opts)
    opts = opts or {}
    local preferred = opts.preferred_dictionary
    local exclude = opts.exclude_dictionary
    -- Never exclude the definition dictionary we are explicitly preferring.
    if exclude and exclude ~= "" and exclude == preferred then
        exclude = nil
    end
    local entries, err = run_lookup(ui, word, { exclude_dictionary = exclude })
    if not entries then
        return nil, err
    end

    if preferred and preferred ~= "" then
        local filtered = {}
        for _i, entry in ipairs(entries) do
            if entry.dict == preferred then
                table.insert(filtered, entry)
            end
        end
        if #filtered > 0 then
            entries = filtered
        end
    end

    if #entries == 1 and not opts.always_pick and not opts.auto_pick then
        if on_select then on_select(entries[1]) end
        return entries[1]
    end

    if opts.auto_pick and #entries > 0 then
        local no_preferred = not preferred or preferred == ""
        if not (no_preferred and #entries > 1) then
            if on_select then on_select(entries[1]) end
            return entries[1]
        end
    end

    DictionaryLookup.show_picker(entries, word, on_select, opts)
    return true
end

return DictionaryLookup
