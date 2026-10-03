-- AnkiConnect HTTP client.

local http  = require("socket.http")
local socket = require("socket")
local ltn12 = require("ltn12")
local json  = require("json")
local _      = require("gettext")

local CardFields       = require("card_fields")
local CardDefaults     = require("card_defaults")
local AnkiRetry        = require("anki_retry")
local MemorizationPolicy = require("memorization_policy")
local NoteTypeProfiles = require("note_type_profiles")
local PrivacyLog       = require("privacy_log")

local TIMEOUT = 5
-- Bounded foreground sync: an AnkiWeb sync normally finishes in a few seconds.
-- Cap the worst case so a stalled sync never blocks the UI for minutes.
local SYNC_TIMEOUT = 20
local MAX_SAFE_INTEGER = 9007199254740991
local AnkiSync = {}

local function normalized_exact(value)
    value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    return value:match("^%s*(.-)%s*$") or ""
end

local function valid_note_id(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value > 0
        and value <= MAX_SAFE_INTEGER
        and value % 1 == 0
end

-- Base deck before subdeck expansion (respects per-book mapping).
function AnkiSync.resolve_base_deck(config, card)
    config = config or {}
    local base = CardDefaults.deck_for_card({ anki = config }, card)
        or "English::Koreader"
    if card and card.book_title and card.book_title ~= ""
       and type(config.per_book_decks) == "table" then
        local mapped = config.per_book_decks[card.book_title]
        if mapped and mapped ~= "" then base = mapped end
    end
    return base
end

function AnkiSync.resolve_deck_name(config, card, base_deck)
    config = config or {}
    local base = (base_deck and base_deck ~= "") and base_deck
                 or AnkiSync.resolve_base_deck(config, card)

    if config.subdeck_by_book == false then return base end

    local title = card and card.book_title and card.book_title ~= "" and card.book_title
    if not title then return base end
    local safe = title:gsub(":", " -"):match("^%s*(.-)%s*$")
    if safe == "" then return base end
    local parent = base:match("^([^:]+)") or base
    return parent .. "::" .. safe
end

local function post(url, action, params, timeout_sec)
    local body     = json.encode({ action = action, version = 6, params = params or {} })
    local response = {}
    http.TIMEOUT = timeout_sec or TIMEOUT
    local ok, code = http.request {
        url     = url,
        method  = "POST",
        headers = {
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink   = ltn12.sink.table(response),
    }
    if not ok or tostring(code) ~= "200" then
        local reason = tostring(code)
        if reason == "timeout" then
            -- A timeout is ambiguous: Anki may have accepted the write. Keep
            -- "timeout" in the text so transient-error detection still matches.
            return nil, "Anki request timeout."
        end
        if reason:find("unreachable") or reason:find("refused")
            or reason:find("host not found") then
            return nil, "Cannot reach Anki. Check URL in Settings."
        end
        return nil, "HTTP error: " .. reason
    end
    local ok2, result = pcall(json.decode, table.concat(response))
    if not ok2 then return nil, "JSON decode error" end
    if type(result) ~= "table" then
        return nil, "Unexpected AnkiConnect response (not an object)"
    end
    return result
end

local function post_read(url, action, params)
    local result, err, attempts = AnkiRetry.run(action, function()
        return post(url, action, params)
    end, socket.sleep)
    if result == nil and attempts >= AnkiRetry.MAX_ATTEMPTS
       and AnkiRetry.is_transient_error(err) then
        PrivacyLog.warn("anki_retry_exhausted", {
            action = action,
            attempts = attempts,
            reason = PrivacyLog.reason_code(err),
        })
    end
    return result, err, attempts
end

function AnkiSync.test_connection(url)
    local result, err = post(url, "requestPermission", {})
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if result.result == nil then
        return nil, "Permission denied or unexpected response"
    end
    return true
end

function AnkiSync.get_deck_names(url)
    local result, err = post_read(url, "deckNames", {})
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "table" then return nil, "Unexpected deckNames response" end
    return result.result
end

function AnkiSync.get_model_names(url)
    local result, err = post_read(url, "modelNames", {})
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "table" then return nil, "Unexpected modelNames response" end
    return result.result
end

function AnkiSync.get_model_field_names(url, model_name)
    local result, err = post_read(url, "modelFieldNames", { modelName = model_name })
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "table" then return nil, "Unexpected modelFieldNames response" end
    return result.result
end

local function escape_deck_query(deck_name)
    return (deck_name or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function escape_query_term(text)
    return (text or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

function AnkiSync.is_duplicate_error(err)
    if not err or err == "" then return false end
    return err:lower():find("duplicate", 1, true) ~= nil
end

function AnkiSync.is_network_error(err)
    return AnkiRetry.is_transient_error(err)
end

-- True when the error means Anki was definitively not reached (connection
-- refused / host unreachable), as opposed to an ambiguous outcome (timeout,
-- mid-request close, or a retryable HTTP status) where the write may still
-- have been accepted and is worth verifying.
function AnkiSync.is_unreachable_error(err)
    if type(err) ~= "string" or err == "" then return false end
    return err:lower():find("cannot reach", 1, true) ~= nil
end

function AnkiSync.find_note_ids(url, query)
    local result, err = post_read(url, "findNotes", { query = query or "" })
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "table" then return nil, "Unexpected findNotes response" end
    return result.result
end

function AnkiSync.notes_info(url, ids)
    if not ids or #ids == 0 then return {} end
    local result, err = post_read(url, "notesInfo", { notes = ids })
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "table" then return nil, "Unexpected notesInfo response" end
    return result.result
end

function AnkiSync.cards_info(url, ids)
    if not ids or #ids == 0 then return {} end
    local result, err = post_read(url, "cardsInfo", { cards = ids })
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "table" then return nil, "Unexpected cardsInfo response" end
    return result.result
end

local function candidate_notes_with_decks(url, ids)
    local infos, info_err = AnkiSync.notes_info(url, ids)
    if not infos then return nil, nil, info_err end

    local card_ids = {}
    for _, info in ipairs(infos) do
        for _, card_id in ipairs(info.cards or {}) do
            card_ids[#card_ids + 1] = card_id
        end
    end

    local decks_by_note = {}
    for _, card_chunk in ipairs(MemorizationPolicy.chunk(
        card_ids, MemorizationPolicy.MULTI_BATCH_SIZE)) do
        local cards, cards_err = AnkiSync.cards_info(url, card_chunk)
        if not cards then return nil, nil, cards_err end
        for _, card in ipairs(cards) do
            local note_id = card.note
            if note_id ~= nil and type(card.deckName) == "string" then
                local note_decks = decks_by_note[tostring(note_id)] or {}
                note_decks[normalized_exact(card.deckName)] = true
                decks_by_note[tostring(note_id)] = note_decks
            end
        end
    end
    return infos, decks_by_note
end

local function info_matches_identity(info, decks_by_note, deck_name, model_name, fields)
    if normalized_exact(info and info.modelName) ~= normalized_exact(model_name) then
        return false
    end
    local note_decks = decks_by_note[tostring(info and info.noteId)]
    if not note_decks or not note_decks[normalized_exact(deck_name)] then
        return false
    end
    for name, expected in pairs(fields or {}) do
        local actual = info.fields and info.fields[name]
        if type(actual) == "table" then actual = actual.value end
        if normalized_exact(actual) ~= normalized_exact(expected) then
            return false
        end
    end
    return true
end

local function query_anchor(fields, phrase, preferred_name)
    if preferred_name and fields[preferred_name] ~= nil then
        return preferred_name, fields[preferred_name]
    end
    local phrase_norm = normalized_exact(phrase)
    local names = {}
    for name in pairs(fields) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        if phrase_norm ~= "" and normalized_exact(fields[name]) == phrase_norm then
            return name, fields[name]
        end
    end
    for _, name in ipairs(names) do
        if normalized_exact(fields[name]) ~= "" then return name, fields[name] end
    end
    return preferred_name or "Phrase", phrase
end

-- Read-only reconciliation: search narrows candidates, then notesInfo/cardsInfo
-- must prove the exact model, deck, and intended field values.
function AnkiSync.note_exists_in_deck(
    url, deck_name, model_name, phrase, field_name, expected_fields)
    field_name = field_name or "Phrase"
    local term = (phrase or ""):match("^%s*(.-)%s*$")
    if term == "" or not url or url == "" or not deck_name or deck_name == "" then
        return false
    end
    local fields = {}
    for name, value in pairs(expected_fields or {}) do fields[name] = value end
    if not next(fields) then fields[field_name] = term end
    local anchor_name, anchor_value = query_anchor(fields, term, field_name)
    local model_part = ""
    if model_name and model_name ~= "" then
        model_part = ' note:"' .. escape_query_term(model_name) .. '"'
    end
    local query = 'deck:"' .. escape_deck_query(deck_name) .. '"' .. model_part
        .. " " .. anchor_name .. ':"' .. escape_query_term(anchor_value) .. '"'
    local ids, err = AnkiSync.find_note_ids(url, query)
    if not ids then return false, err end
    if #ids == 0 then return false end
    local infos, decks_by_note, details_err =
        candidate_notes_with_decks(url, ids)
    if not infos then return false, details_err end
    for _, info in ipairs(infos) do
        if info_matches_identity(
            info, decks_by_note, deck_name, model_name, fields) then
            return true
        end
    end
    return false
end

function AnkiSync.find_note_ids_in_deck(url, deck_name)
    if not url or url == "" or not deck_name or deck_name == "" then
        return nil, "Deck name not set"
    end
    return AnkiSync.find_note_ids(
        url, 'deck:"' .. escape_deck_query(deck_name) .. '"')
end

function AnkiSync.count_notes_in_deck(url, deck_name)
    local ids, err = AnkiSync.find_note_ids_in_deck(url, deck_name)
    if not ids then return nil, err end
    return #ids
end

function AnkiSync.delete_notes_in_deck(url, deck_name)
    local ids, err = AnkiSync.find_note_ids_in_deck(url, deck_name)
    if not ids then return nil, err end
    if #ids == 0 then return true, 0 end
    local result, del_err = post(url, "deleteNotes", { notes = ids })
    if not result then return nil, del_err end
    if type(result.error) == "string" then return nil, result.error end
    return true, #ids
end

function AnkiSync.sync_after_send_enabled(config)
    config = config or {}
    return config.sync_after_send ~= false
end

function AnkiSync.sync_collection(url)
    if not url or url == "" then
        return nil, "Anki URL not configured"
    end
    local result, err = post(url, "sync", {}, SYNC_TIMEOUT)
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    return true
end

-- Returns a user-visible suffix (empty if disabled, skipped, or sync OK).
function AnkiSync.sync_status_suffix(config)
    if not AnkiSync.sync_after_send_enabled(config) then
        return ""
    end
    if not config or not config.url or config.url == "" then
        return ""
    end
    local ok, err = AnkiSync.sync_collection(config.url)
    if ok then
        return _("\nSynced to AnkiWeb.")
    end
    return _("\n(Sync to AnkiWeb failed: ") .. (err or "?") .. ")"
end

function AnkiSync.ensure_deck(url, deck_name)
    if not url or url == "" or not deck_name or deck_name == "" then
        return nil, "Deck name not set"
    end
    local result, err = post(url, "createDeck", { deck = deck_name })
    if not result then return nil, err end
    if type(result.error) == "string" then
        local lower = result.error:lower()
        if lower:find("exists") then return true end
        return nil, result.error
    end
    return true
end

function AnkiSync.add_note(url, note)
    if not url or url == "" then return nil, "Anki URL not configured" end
    local result, err = post(url, "addNote", { note = note })
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if not valid_note_id(result.result) then
        return nil, "Unexpected addNote response (missing valid note ID)"
    end
    return true, nil, result.result
end

-- Send many notes in bounded AnkiConnect multi requests. Multi/addNote writes
-- are deliberately never retried: a timeout may mean Anki accepted the write.
function AnkiSync.add_notes_batch(url, notes)
    if not url or url == "" then return nil, nil, "Anki URL not configured" end
    if not notes or #notes == 0 then return 0, 0, nil end
    if #notes == 1 then
        local ok, err = AnkiSync.add_note(url, notes[1])
        if ok then return 1, 0, nil end
        return 0, 1, err
    end

    local sent, failed = 0, 0
    local last_err = nil
    for _, chunk in ipairs(MemorizationPolicy.chunk(
        notes, MemorizationPolicy.MULTI_BATCH_SIZE)) do
        local actions = {}
        for i, note in ipairs(chunk) do
            actions[i] = { action = "addNote", params = { note = note } }
        end
        local result, err = post(url, "multi", { actions = actions })
        if not result then
            failed = failed + #chunk
            last_err = err
        elseif type(result.error) == "string" then
            failed = failed + #chunk
            last_err = result.error
        elseif type(result.result) ~= "table" then
            failed = failed + #chunk
            last_err = "Unexpected multi response"
        else
            for i = 1, #chunk do
                local item = result.result[i]
                local item_result = type(item) == "table" and item.result or item
                if valid_note_id(item_result) then
                    sent = sent + 1
                else
                    failed = failed + 1
                    local item_err = type(item) == "table" and item.error or nil
                    last_err = last_err or item_err or _("One or more notes failed")
                end
            end
        end
    end
    return sent, failed, last_err
end

local MEM_IDENTITY_FIELDS = {
    "Title", "Target", "FullText", "LineIndex", "FullRecite",
}

local function field_value(fields, name)
    local value = fields and fields[name]
    if type(value) == "table" then value = value.value end
    return normalized_exact(value)
end

function AnkiSync.memorization_note_identity(note_or_info)
    local fields = note_or_info and note_or_info.fields or {}
    local values = {}
    for _, name in ipairs(MEM_IDENTITY_FIELDS) do
        values[#values + 1] = field_value(fields, name)
    end
    return table.concat(values, "\30")
end

-- Exact field verification used before/after ambiguous memorization sends.
-- Returns identity -> count, or nil,error if the read could not be completed.
function AnkiSync.find_existing_memorization_notes(url, notes)
    if not notes or #notes == 0 then return {} end
    local first = notes[1]
    local title = field_value(first.fields, "Title")
    local query = 'deck:"' .. escape_deck_query(first.deckName or "") .. '"'
        .. ' note:"' .. escape_query_term(first.modelName or "") .. '"'
        .. ' Title:"' .. escape_query_term(title) .. '"'
    local ids, find_err = AnkiSync.find_note_ids(url, query)
    if not ids then return nil, find_err end

    local existing = {}
    for _, id_chunk in ipairs(MemorizationPolicy.chunk(
        ids, MemorizationPolicy.MULTI_BATCH_SIZE)) do
        local infos, decks_by_note, info_err =
            candidate_notes_with_decks(url, id_chunk)
        if not infos then return nil, info_err end
        for _, info in ipairs(infos) do
            local note_decks = decks_by_note[tostring(info.noteId)]
            if normalized_exact(info.modelName)
                    == normalized_exact(first.modelName)
                and note_decks
                and note_decks[normalized_exact(first.deckName)] then
                local identity = AnkiSync.memorization_note_identity(info)
                existing[identity] = (existing[identity] or 0) + 1
            end
        end
    end
    return existing
end

local function fields_for_card(config, card, model)
    local field_names = require("note_type_picker").fetch_field_names(config, model)
    if not field_names or #field_names == 0 then
        field_names = NoteTypeProfiles.VOCABULARY_CARD_FIELDS
    end

    if CardFields.is_dictionary_card(card, config) then
        return CardFields.dictionary_fields_for_send(card, field_names)
    end
    return CardFields.fields_for_send(card, field_names)
end

function AnkiSync.fields_for_verification(config, card, model)
    if type(card) ~= "table" then return nil, "Card not set" end
    config = config or {}
    CardFields.normalize(card, config)
    model = NoteTypeProfiles.normalize_model_name(
        (model and model ~= "") and model
        or card.model or CardFields.default_vocabulary_model({ anki = config }))
    return fields_for_card(config, card, model)
end

local function prepare_send_payload(config, card, opts)
    if not config or not config.url or config.url == "" then
        return nil, nil, nil, nil, "Anki URL not configured"
    end

    opts = opts or {}
    CardFields.normalize(card, config)

    local base_deck = (opts.deck and opts.deck ~= "") and opts.deck
        or CardDefaults.deck_for_card({ anki = config }, card)
        or "English::Koreader"
    local model = NoteTypeProfiles.normalize_model_name(
        (opts.model and opts.model ~= "") and opts.model
        or card.model or CardFields.default_vocabulary_model({ anki = config }))

    local deck_name = AnkiSync.resolve_deck_name(config, card, base_deck)
    local ensured, deck_err = AnkiSync.ensure_deck(config.url, deck_name)
    if not ensured then return nil, nil, nil, nil, deck_err end

    local fields = fields_for_card(config, card, model)

    local note = {
        deckName  = deck_name,
        modelName = model,
        fields    = fields,
        options   = {
            allowDuplicate = false,
            duplicateScope = "deck",
        },
        tags = (config.tags_enabled == false) and {} or (config.tags or { "KOReader" }),
    }

    return note, deck_name, model, fields, nil
end

-- Batch send helper: sent | duplicate | verified | failed
function AnkiSync.send_card_with_status(config, card, opts)
    local note, deck_name, model, fields, prep_err = prepare_send_payload(config, card, opts)
    if not note then
        return "failed", nil, nil, prep_err
    end

    local result, err = post(config.url, "addNote", { note = note })
    -- KOReader's LuaJSON decodes JSON `null` to a sentinel function, not Lua
    -- nil, so "no error" must be detected by absence of a string error, not
    -- by `result.error == nil`.
    if result and type(result.error) ~= "string" and valid_note_id(result.result) then
        return "sent", deck_name, model, nil
    end

    local err_msg
    if result and type(result.error) == "string" then
        err_msg = result.error
    elseif result then
        return "failed", deck_name, model,
            "Unexpected addNote response; card remains pending"
    else
        err_msg = err or "unknown"
    end

    if AnkiSync.is_duplicate_error(err_msg)
        or (AnkiSync.is_network_error(err_msg)
            and not AnkiSync.is_unreachable_error(err_msg)) then
        local phrase = card.phrase or ""
        local exists, verify_err = AnkiSync.note_exists_in_deck(
            config.url, deck_name, model, phrase, "Phrase", fields)
        if exists then
            local recovered = AnkiSync.is_duplicate_error(err_msg)
                and "duplicate" or "verified"
            return recovered, deck_name, model, err_msg
        end
        local prefix = AnkiSync.is_duplicate_error(err_msg)
            and "Anki reported a duplicate, but the exact note was not verified"
            or "Send outcome is uncertain and the exact note was not verified"
        if verify_err and verify_err ~= "" then
            prefix = prefix .. ": " .. verify_err
        end
        return "failed", deck_name, model, prefix .. "; card remains pending"
    end
    return "failed", deck_name, model, err_msg
end

function AnkiSync.send_card(config, card, opts)
    opts = opts or {}
    local status, deck_name, model, err =
        AnkiSync.send_card_with_status(config, card, opts)
    if status ~= "sent" and status ~= "duplicate" and status ~= "verified" then
        return nil, err, status, deck_name, model
    end
    local sync_suffix = ""
    if not opts.skip_sync and status ~= "duplicate" then
        sync_suffix = AnkiSync.sync_status_suffix(config)
    end
    return true, sync_suffix, status, deck_name, model
end

return AnkiSync
