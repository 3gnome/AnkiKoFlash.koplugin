-- Local card storage for AnkiKoFlash.

local DataStorage = require("datastorage")
local json        = require("json")
local logger      = require("logger")
local AtomicJson  = require("atomic_json")
local PluginConstants = require("plugin_constants")
local PositionUtils = require("position_utils")
local _           = require("gettext")

local function data_path(name)
    return DataStorage:getDataDir() .. "/" .. name
end

local CARDS_FILE       = data_path(PluginConstants.CARDS_FILE)
local SETTINGS_FILE    = data_path(PluginConstants.SETTINGS_FILE)
local RECENT_SENT_FILE = data_path(PluginConstants.RECENT_SENT_FILE)

-- One-time migration of legacy AnkiKOAi storage filenames to AnkiKoFlash.
local LEGACY_FILES = {
    { from = "ankikooai_cards.json",       to = PluginConstants.CARDS_FILE },
    { from = "ankikooai_settings.json",    to = PluginConstants.SETTINGS_FILE },
    { from = "ankikooai_recent_sent.json", to = PluginConstants.RECENT_SENT_FILE },
}

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local RECENT_SENT_MAX = 50
local purge_done = false

local CardStorage = {}

-- Migrate any legacy AnkiKOAi storage files to the current AnkiKoFlash names.
-- Returns the number of files migrated. A legacy file is only renamed when the
-- current name is absent, so an existing AnkiKoFlash file is never overwritten.
function CardStorage.migrate_legacy_files()
    local migrated = 0
    for _, pair in ipairs(LEGACY_FILES) do
        local legacy = data_path(pair.from)
        local current = data_path(pair.to)
        if not file_exists(current) and file_exists(legacy) then
            local renamed, rename_err = os.rename(legacy, current)
            if renamed then
                migrated = migrated + 1
            else
                logger.warn(PluginConstants.ID,
                    "storage migration failed for", pair.from,
                    ":", tostring(rename_err))
            end
        end
    end
    return migrated
end

local function normalize(phrase)
    return (phrase or ""):lower():match("^%s*(.-)%s*$")
end

local function normalize_memorization_text(text)
    return normalize(text):gsub("%s+", " ")
end

-- Naive English stemmer: strip common inflectional suffixes.
local function stem(word)
    local w = normalize(word)
    -- Order matters — try longest suffixes first.
    w = w:gsub("ies$", "y")       -- "stories" → "story"
    w = w:gsub("ying$", "y")      -- "studying" → "study" (approximate)
    w = w:gsub("ving$", "ve")     -- "having" → "have"
    w = w:gsub("ting$", "t")      -- "sitting" → "sit" (approximate)
    w = w:gsub("ning$", "n")      -- "running" → "run"
    w = w:gsub("ging$", "g")      -- "nagging" → "nag"
    w = w:gsub("ding$", "d")      -- "adding" → "add"
    w = w:gsub("bing$", "b")      -- "rubbing" → "rub"
    w = w:gsub("ping$", "p")      -- "tapping" → "tap"
    w = w:gsub("ming$", "m")      -- "swimming" → "swim"
    w = w:gsub("zing$", "z")      -- "buzzing" → "buz" (close enough)
    w = w:gsub("sing$", "s")      -- "missing" → "mis" (approximate)
    w = w:gsub("ing$", "")        -- "taxing" → "tax"
    w = w:gsub("ied$", "y")       -- "studied" → "study"
    w = w:gsub("ved$", "ve")      -- "moved" → "move"
    w = w:gsub("ced$", "ce")      -- "danced" → "dance"
    w = w:gsub("sed$", "se")      -- "closed" → "close"
    w = w:gsub("ted$", "t")       -- "dotted" → "dot"
    w = w:gsub("ned$", "n")       -- "planned" → "plan"
    w = w:gsub("ged$", "g")       -- "nagged" → "nag"
    w = w:gsub("ded$", "d")       -- "added" → "add"
    w = w:gsub("bed$", "b")       -- "rubbed" → "rub"
    w = w:gsub("ped$", "p")       -- "tapped" → "tap"
    w = w:gsub("med$", "m")       -- "trimmed" → "trim"
    w = w:gsub("ed$", "")         -- "walked" → "walk"
    w = w:gsub("es$", "")         -- "cogs" won't match but "boxes" → "box"
    w = w:gsub("s$", "")          -- "cogs" → "cog"
    w = w:gsub("ly$", "")         -- "quickly" → "quick"
    w = w:gsub("er$", "")         -- "bigger" → "bigg" (approximate)
    w = w:gsub("est$", "")        -- "biggest" → "bigg"
    return w
end

local function reason_code(reason)
    return type(reason) == "table" and reason.code or tostring(reason or "unknown")
end

local function read_json_table(path)
    local recovered, recovery_reason = AtomicJson.recover(path)
    if not recovered then
        return nil, "read_failed", recovery_reason
    end
    local f, open_error, open_code = io.open(path, "r")
    if not f then
        local message = tostring(open_error or ""):lower()
        if open_code == 2 or message:find("no such file", 1, true)
            or message:find("cannot find the file", 1, true) then
            return {}, "absent"
        end
        return nil, "read_failed", open_error
    end
    local read_ok, content = pcall(f.read, f, "*all")
    local close_ok, closed = pcall(f.close, f)
    if not read_ok or content == nil or not close_ok or not closed then
        return nil, "read_failed", not read_ok and content or closed
    end
    if content == "" then return {}, "empty" end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then return data, "ok" end
    return nil, "malformed", ok and "root_not_table" or data
end

local function save_recent_raw(entries)
    return AtomicJson.write(RECENT_SENT_FILE, entries)
end

local function load_recent_raw()
    return read_json_table(RECENT_SENT_FILE)
end

function CardStorage.record_recent_sent(entry)
    entry = entry or {}
    local entries, load_status = load_recent_raw()
    if not entries then
        logger.warn(PluginConstants.ID,
            "record_recent_sent: recent history load failed:", load_status)
        return false, "load_failed", load_status
    end
    table.insert(entries, 1, {
        phrase     = entry.phrase or "",
        book_title = entry.book_title or "",
        card_kind  = entry.card_kind or "",
        deck       = entry.deck or "",
        model      = entry.model or "",
        status     = entry.status or "sent",
        sent_at    = entry.sent_at or os.time(),
        highlight_pos0 = entry.highlight_pos0,
        highlight_pos1 = entry.highlight_pos1,
        document_path = entry.document_path,
        memorization_text = entry.memorization_text or "",
    })
    while #entries > RECENT_SENT_MAX do
        table.remove(entries)
    end
    local ok, reason = save_recent_raw(entries)
    if not ok then
        logger.warn(PluginConstants.ID,
            "record_recent_sent: write failed:", reason_code(reason))
        return false, "write_failed", reason
    end
    return true
end

function CardStorage.load_recent_sent()
    local entries, status, detail = load_recent_raw()
    return entries or {}, status, detail
end

function CardStorage.clear_recent_sent()
    return save_recent_raw({})
end

local function load_raw()
    return read_json_table(CARDS_FILE)
end

local function save_raw(entries)
    local ok, reason = AtomicJson.write(CARDS_FILE, entries)
    if not ok then
        logger.warn(PluginConstants.ID,
            "save_raw: atomic write failed:", reason_code(reason))
    end
    return ok, reason
end

function CardStorage.purge_sent_cards()
    local ok_load, entries, load_status = pcall(load_raw)
    if not ok_load or type(entries) ~= "table" then
        logger.warn(PluginConstants.ID, "purge_sent_cards: load failed:",
            ok_load and load_status or "exception")
        return false, "load_failed", ok_load and load_status or entries
    end
    local kept = {}
    for _i, e in ipairs(entries) do
        if type(e) == "table" and not e.sent_to_anki then
            table.insert(kept, e)
        end
    end
    if #kept ~= #entries then
        local saved, reason = save_raw(kept)
        if not saved then
            logger.warn(PluginConstants.ID,
                "purge_sent_cards: save failed:", reason_code(reason))
            return false, "write_failed", reason
        end
    end
    purge_done = true
    return true
end

function CardStorage.ensure_queue_migrated()
    if not purge_done then
        return CardStorage.purge_sent_cards()
    end
    return true
end

-- Identity test used for de-duplication / upsert. Memorization passages are
-- keyed on their full text (the phrase is a title-derived label shared by many
-- passages from the same book/page); all other cards key on the phrase.
function CardStorage.same_card(a, b, match_book)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local a_mem = a.card_kind == "memorization"
    local b_mem = b.card_kind == "memorization"
    if a_mem or b_mem then
        if not (a_mem and b_mem) then return false end
        local at = normalize_memorization_text(a.memorization_text)
        if at == "" or at ~= normalize_memorization_text(b.memorization_text) then
            return false
        end
    elseif normalize(a.phrase) ~= normalize(b.phrase) then
        return false
    end
    return not match_book
        or normalize(a.book_title or "") == normalize(b.book_title or "")
end

function CardStorage.identity_key(card, include_book)
    card = card or {}
    local book = include_book and ("__" .. normalize(card.book_title or "")) or ""
    if card.card_kind == "memorization" then
        return "memorization__"
            .. normalize_memorization_text(card.memorization_text) .. book
    end
    -- Preserve the historical cloud key for vocabulary and legacy rows.
    return normalize(card.phrase) .. book
end

-- Upsert by card identity (used for auto-save after generation).
function CardStorage.save_or_update(card)
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    for i, e in ipairs(entries) do
        if CardStorage.same_card(e, card, true) then
            local merged = CardStorage.serialize_entry(card)
            merged.date = e.date or merged.date
            entries[i] = merged
            local saved, reason = save_raw(entries)
            if not saved then return false, "write_failed", reason end
            return true, "updated"
        end
    end
    table.insert(entries, CardStorage.serialize_entry(card))
    local saved, reason = save_raw(entries)
    if not saved then return false, "write_failed", reason end
    return true, "saved"
end

function CardStorage.serialize_entry(card)
    return {
        phrase      = card.phrase      or "",
        ipa         = card.ipa         or "",
        definition  = card.definition  or "",
        synonyms    = card.synonyms    or "",
        text        = card.text        or "",
        context     = card.context     or "",
        links       = card.links       or (card.anki_fields and card.anki_fields.Links) or "",
        source      = card.source      or "",
        book_title  = card.book_title  or "",
        book_author = card.book_author or "",
        highlight_pos0 = card.highlight_pos0,
        highlight_pos1 = card.highlight_pos1,
        document_path = card.document_path,
        _context       = card._context       or "",
        etymology      = card.etymology      or "",
        target_deck    = card.target_deck    or "",
        target_model   = card.target_model   or "",
        model          = card.model          or "",
        card_kind      = card.card_kind      or "",
        dictionary_only = card.dictionary_only == true,
        dictionary_name = card.dictionary_name or "",
        memorization_text = card.memorization_text or "",
        memorization_deck = card.memorization_deck or "",
        anki_fields    = card.anki_fields,
        date           = os.date("%Y-%m-%d"),
        updated_at     = os.time(),
    }
end

-- Pending queue duplicate for this phrase in the same book?
-- exclude_card: skip the row being sent (same identity) so Send anyway? only
-- appears when another pending entry exists.
function CardStorage.find_pending_duplicate(phrase, book_title, exclude_card)
    local candidate = exclude_card or {
        phrase = phrase or "",
        book_title = book_title or "",
    }
    local match_book = normalize(book_title or "") ~= ""
    local skipped_excluded = false
    for _, e in ipairs(CardStorage.load_cards()) do
        if not e.sent_to_anki
            and CardStorage.same_card(e, candidate, match_book) then
            if exclude_card and not skipped_excluded
                and CardStorage.same_card(e, exclude_card, true) then
                skipped_excluded = true
            else
                return e
            end
        end
    end
    return nil
end

-- Returns the full list of saved cards.
function CardStorage.load_cards()
    local entries, status, detail = load_raw()
    return entries or {}, status, detail
end

function CardStorage.is_memorization(card)
    return card and card.card_kind == "memorization"
        and card.memorization_text and card.memorization_text ~= ""
end

function CardStorage.count_pending()
    local n = 0
    for _, e in ipairs(CardStorage.load_cards()) do
        if not e.sent_to_anki then n = n + 1 end
    end
    return n
end

function CardStorage.count_unsent()
    return CardStorage.count_pending()
end

-- Queue a memorization passage for sending when Anki is reachable.
function CardStorage.save_memorization_pending(text, meta, deck)
    meta = meta or {}
    text = text or ""
    if text == "" then return false, "empty" end
    local title = (meta.title and meta.title ~= "") and meta.title
        or text:match("^%s*(.-)%s*$") or _("Passage")
    if #title > 60 then title = title:sub(1, 60) .. "…" end
    local phrase = _("Memorization") .. ": " .. title
    local ok, reason = CardStorage.save_or_update({
        card_kind           = "memorization",
        phrase              = phrase,
        memorization_text   = text,
        memorization_deck   = deck or "",
        book_title          = meta.book_title or "",
        book_author         = meta.book_author or "",
        source              = meta.source or "",
        document_path       = meta.document_path,
        highlight_pos0      = meta.highlight_pos0,
        highlight_pos1      = meta.highlight_pos1,
        target_deck         = deck or "",
    })
    return ok, reason
end

-- Update editable fields of an already-saved card (matched by original phrase).
-- Does not touch book metadata or date.
function CardStorage.update_card(original_phrase, new_card)
    local key     = normalize(original_phrase)
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    for _, e in ipairs(entries) do
        if normalize(e.phrase) == key then
            e.phrase       = new_card.phrase       or ""
            e.ipa          = new_card.ipa          or ""
            e.definition   = new_card.definition   or ""
            e.synonyms     = new_card.synonyms     or ""
            e.text         = new_card.text         or ""
            e.source       = new_card.source       or ""
            e.model        = new_card.model        or e.model or ""
            e.anki_fields  = new_card.anki_fields   or e.anki_fields
            e.updated_at   = os.time()
            local saved, reason = save_raw(entries)
            if not saved then return false, "write_failed", reason end
            return true
        end
    end
    return false
end

-- Remove card by 1-based index.
function CardStorage.delete_card(idx)
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    if type(idx) ~= "number" or idx % 1 ~= 0
        or idx < 1 or idx > #entries then
        return false
    end
    table.remove(entries, idx)
    local saved, reason = save_raw(entries)
    if not saved then return false, "write_failed", reason end
    return true
end

function CardStorage.delete_at_index(idx)
    return CardStorage.delete_card(idx)
end

-- Remove one pending card matching identity (phrase/mem text + book).
function CardStorage.delete_matching_card(card)
    if not card then return false, "invalid_card" end
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    for i, e in ipairs(entries) do
        if CardStorage.same_card(e, card, true) then
            table.remove(entries, i)
            local saved, reason = save_raw(entries)
            if not saved then return false, "write_failed", reason end
            return true
        end
    end
    return false, "not_found"
end

-- Keep an Anki-accepted card out of pending/auto-send if deletion cannot be
-- persisted. The next startup purge will retry removal of this compatibility row.
function CardStorage.mark_matching_sent(card)
    if not card then return false, "invalid_card" end
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    for _, e in ipairs(entries) do
        if CardStorage.same_card(e, card, true) then
            e.sent_to_anki = true
            e.updated_at = os.time()
            local saved, reason = save_raw(entries)
            if not saved then return false, "write_failed", reason end
            purge_done = false
            return true
        end
    end
    return false, "not_found"
end

-- Delete multiple cards by 1-based indices (highest first).
function CardStorage.delete_indices(indices)
    if not indices or #indices == 0 then return true end
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    local sorted = {}
    local seen = {}
    for _, idx in ipairs(indices) do
        if type(idx) ~= "number" or idx % 1 ~= 0
            or idx < 1 or idx > #entries then
            return false, "invalid_index"
        end
        if not seen[idx] then
            seen[idx] = true
            table.insert(sorted, idx)
        end
    end
    table.sort(sorted, function(a, b) return a > b end)
    for _, idx in ipairs(sorted) do
        table.remove(entries, idx)
    end
    local saved, reason = save_raw(entries)
    if not saved then return false, "write_failed", reason end
    return true
end

-- Delete every card for which match_fn(card, index) is true.
function CardStorage.delete_where(match_fn)
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    local kept = {}
    local removed = 0
    for i, card in ipairs(entries) do
        if match_fn(card, i) then
            removed = removed + 1
        else
            table.insert(kept, card)
        end
    end
    if removed == 0 then return true, "not_found" end
    local saved, reason = save_raw(kept)
    if not saved then return false, "write_failed", reason end
    return true, removed
end

-- Empty the entire card list.
function CardStorage.clear_all()
    return save_raw({})
end

-- Remove saved card matching phrase (exact, then fuzzy). Returns true if removed.
function CardStorage.delete_by_phrase(phrase)
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    local key = normalize(phrase)
    local target_index
    for i, e in ipairs(entries) do
        if not e.sent_to_anki and normalize(e.phrase) == key then
            target_index = i
            break
        end
    end
    if not target_index then
        local fuzzy_key = stem(phrase)
        if fuzzy_key ~= "" then
            for i, e in ipairs(entries) do
                if not e.sent_to_anki and stem(e.phrase) == fuzzy_key then
                    target_index = i
                    break
                end
            end
        end
    end
    if not target_index then return false, "not_found" end
    table.remove(entries, target_index)
    local saved, reason = save_raw(entries)
    if not saved then return false, "write_failed", reason end
    return true
end

-- Remove one pending card only from an exact source document. When a highlight
-- position is supplied, position is authoritative and phrase fallback is
-- disabled so duplicate-text highlights cannot remove one another.
function CardStorage.delete_by_phrase_in_document(
    phrase, document_path, pos0, pos1)
    if type(document_path) ~= "string" or document_path == "" then
        return false, "invalid_document"
    end
    local entries, load_status = load_raw()
    if not entries then return false, "load_failed", load_status end
    local key = normalize(phrase)
    local target_index
    if pos0 then
        for i, e in ipairs(entries) do
            if not e.sent_to_anki and e.document_path == document_path
                and PositionUtils.equal(e.highlight_pos0, pos0)
                and (not pos1 or (e.highlight_pos1
                    and PositionUtils.equal(e.highlight_pos1, pos1))) then
                target_index = i
                break
            end
        end
        if not target_index then return false, "not_found" end
    end
    for i, e in ipairs(entries) do
        if not target_index and not e.sent_to_anki
            and e.document_path == document_path
            and normalize(e.phrase) == key then
            target_index = i
            break
        end
    end
    if not target_index then
        local fuzzy_key = stem(phrase)
        if fuzzy_key ~= "" then
            for i, e in ipairs(entries) do
                if not e.sent_to_anki and e.document_path == document_path
                    and stem(e.phrase) == fuzzy_key then
                    target_index = i
                    break
                end
            end
        end
    end
    if not target_index then return false, "not_found" end
    table.remove(entries, target_index)
    local saved, reason = save_raw(entries)
    if not saved then return false, "write_failed", reason end
    return true
end

-- Find and return a saved card by phrase (case-insensitive, trimmed).
-- Returns the card table or nil.
function CardStorage.find_by_phrase(phrase, document_path)
    local key     = normalize(phrase)
    local entries = CardStorage.load_cards()
    for _, e in ipairs(entries) do
        if not e.sent_to_anki and normalize(e.phrase) == key
            and (document_path == nil
                or (type(document_path) == "string"
                    and document_path ~= ""
                    and e.document_path == document_path)) then
            return e
        end
    end
    return nil
end

-- Find a saved card by phrase with fuzzy stem matching.
-- Tries exact (normalized) match first, then falls back to stem comparison.
-- Returns the card table or nil.
function CardStorage.find_by_phrase_fuzzy(phrase, document_path)
    local exact = CardStorage.find_by_phrase(phrase, document_path)
    if exact then return exact end
    local key     = stem(phrase)
    if key == "" then return nil end
    local entries = CardStorage.load_cards()
    for _, e in ipairs(entries) do
        if not e.sent_to_anki and stem(e.phrase) == key
            and (document_path == nil
                or (type(document_path) == "string"
                    and document_path ~= ""
                    and e.document_path == document_path)) then
            return e
        end
    end
    return nil
end

-- Find a saved pending card by exact document identity and highlight position.
-- Returns the card table or nil.
function CardStorage.find_by_position(pos0, pos1, document_path)
    if not pos0 or type(document_path) ~= "string"
        or document_path == "" then
        return nil
    end
    local entries = CardStorage.load_cards()
    for _, e in ipairs(entries) do
        if not e.sent_to_anki
            and e.document_path == document_path
            and PositionUtils.equal(e.highlight_pos0, pos0) then
            if pos1 then
                if e.highlight_pos1
                    and PositionUtils.equal(e.highlight_pos1, pos1) then
                    return e
                end
            else
                return e
            end
        end
    end
    return nil
end

-- Resolve a tapped highlight. Exact document + structural position is
-- authoritative. Phrase matching is reserved for same-document legacy cards
-- that predate position metadata, so a duplicate positioned highlight cannot
-- capture a tap intended for another position.
function CardStorage.find_for_highlight(phrase, document_path, pos0, pos1)
    if type(document_path) ~= "string" or document_path == "" then
        return nil
    end
    if pos0 then
        local positioned = CardStorage.find_by_position(
            pos0, pos1, document_path)
        if positioned then return positioned end
    end

    local key = normalize(phrase)
    local entries = CardStorage.load_cards()
    for _, e in ipairs(entries) do
        if not e.sent_to_anki and e.document_path == document_path
            and e.highlight_pos0 == nil and e.highlight_pos1 == nil
            and normalize(e.phrase) == key then
            return e
        end
    end

    local fuzzy_key = stem(phrase)
    if fuzzy_key == "" then return nil end
    for _, e in ipairs(entries) do
        if not e.sent_to_anki and e.document_path == document_path
            and e.highlight_pos0 == nil and e.highlight_pos1 == nil
            and stem(e.phrase) == fuzzy_key then
            return e
        end
    end
    return nil
end

-- Returns true if phrase is already saved (case-insensitive, trimmed).
function CardStorage.is_saved(phrase)
    local key     = normalize(phrase)
    local entries = CardStorage.load_cards()
    for _, e in ipairs(entries) do
        if not e.sent_to_anki and normalize(e.phrase) == key then
            return true
        end
    end
    return false
end

-- Persist Anki connection settings (override configuration.lua at runtime).
function CardStorage.save_anki_settings(settings)
    local ok, reason = AtomicJson.write(SETTINGS_FILE, settings)
    if not ok then
        logger.warn(PluginConstants.ID,
            "save_anki_settings: atomic write failed:", reason_code(reason))
    end
    return ok, reason
end

-- Load saved Anki settings. Returns a table or nil if not yet set.
function CardStorage.load_anki_settings()
    local settings, status, detail = read_json_table(SETTINGS_FILE)
    if status == "absent" or status == "empty" then
        return nil, status
    end
    return settings, status, detail
end

return CardStorage
