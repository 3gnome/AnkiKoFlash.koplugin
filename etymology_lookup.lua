-- Look up a word's etymology using an offline StarDict dictionary.
--
-- Primary path: restrict the lookup to the configured etymology dictionary and
-- use its (already etymology-only) text.  Fallback: run a general lookup and
-- extract the ``Etymology`` heading from the first definition that has one.

local _ = require("gettext")

local EtymologyLookup = {}

local MAX_ETYMOLOGY = 4000

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
    while cut > 0 do
        local b = s:byte(cut)
        if b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    if cut == 0 then cut = max end
    return s:sub(1, cut) .. "..."
end

local function strip_html(html)
    if not html or html == "" then return "" end
    local text = html
    text = text:gsub("<%s*[bB][rR]%s*/?>", "\n")
    text = text:gsub("</%s*[pP]%s*>", "\n")
    text = text:gsub("</%s*[dD][iI][vV]%s*>", "\n")
    text = text:gsub("</%s*[lL][iI]%s*>", "\n")
    text = text:gsub("</%s*[hH][1-6]%s*>", "\n")
    text = text:gsub("<[^>]+>", " ")
    text = decode_entities(text)
    text = text:gsub("[ \t\r\n]+", " "):match("^%s*(.-)%s*$") or ""
    return truncate_utf8(text, MAX_ETYMOLOGY)
end

-- Extract the text of an ``Etymology`` heading section from a general
-- dictionary definition (HTML). Returns nil when no etymology heading exists.
local function extract_etymology_from_html(html)
    if not html or html == "" then return nil end
    local pos = 1
    local capture_start
    while true do
        local hs, he, level, text = html:find(
            "<%s*[hH]([1-6])[^>]*>(.-)</%s*[hH]%1>", pos)
        if not hs then break end
        local plain = strip_html(text):gsub("%s+", " ")
        if plain:match("^[Ee]tymology") then
            capture_start = he + 1
            break
        end
        pos = he + 1
    end
    if not capture_start then return nil end

    -- Capture until the next heading at any level (a following Etymology 2 /
    -- next POS section) or the end of the definition.
    local next_heading = html:find("<%s*[hH][1-6][^>]*>", capture_start)
    local body = next_heading and html:sub(capture_start, next_heading - 1)
        or html:sub(capture_start)
    local text = strip_html(body)
    if text == "" then return nil end
    return text
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

-- Return every non-empty raw definition (HTML) from a lookup, in order.
local function all_definitions(ui, word, dict_names)
    if not ui or not ui.dictionary or not ui.dictionary.startSdcv then
        return {}
    end
    local dict = ui.dictionary
    local fuzzy = fuzzy_search_enabled(dict)
    local ok, results = pcall(dict.startSdcv, dict, word, dict_names, fuzzy)
    if not ok then return {} end
    if not results or #results == 0 or results.lookup_cancelled then
        return {}
    end
    local out = {}
    for _i, raw in ipairs(results) do
        if raw and not raw.no_result and raw.definition
           and raw.definition ~= "" then
            out[#out + 1] = raw.definition
        end
    end
    return out
end

-- Look up etymology for ``word``. ``preferred_dictionary`` is the configured
-- etymology dictionary name (may be nil). Returns (plain_text_or_nil, status),
-- where status is "found" or "not_found".
function EtymologyLookup.lookup(ui, word, preferred_dictionary)
    word = (word or ""):match("^%s*(.-)%s*$") or ""
    if word == "" then return nil, "not_found" end

    local configured = preferred_dictionary and preferred_dictionary ~= ""

    -- Primary: the dedicated etymology dictionary is already etymology-only.
    if configured then
        for _, definition in ipairs(all_definitions(ui, word, { preferred_dictionary })) do
            local text = strip_html(definition)
            if text ~= "" then return text, "found" end
        end
        -- A dictionary is explicitly configured but has no entry for this word:
        -- do not fall back to another dictionary's Etymology heading.
        return nil, "not_found"
    end

    -- Fallback (no configured dictionary): extract the Etymology heading from
    -- any installed dictionary, checking every result (not just the first) for
    -- a usable heading.
    for _, definition in ipairs(all_definitions(ui, word, nil)) do
        local extracted = extract_etymology_from_html(definition)
        if extracted then return extracted, "found" end
    end
    return nil, "not_found"
end

return EtymologyLookup
