-- LPCG-style poetry memorization: overlapping line context → recite next line.
-- See https://ankilpcg.readthedocs.io/en/stable/theory.html

local ConfirmBox   = require("ui/widget/confirmbox")
local InfoMessage  = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local TextViewer   = require("ui/widget/textviewer")
local UIManager    = require("ui/uimanager")
local _            = require("gettext")

local AnkiSync         = require("anki_sync")
local CardFields       = require("card_fields")
local CardStorage      = require("card_storage")
local NoteTypeProfiles = require("note_type_profiles")
local ReadingLocation  = require("reading_location")
local MemorizationPolicy = require("memorization_policy")
local MemorizationResult = require("memorization_result")
local PrivacyLog         = require("privacy_log")
local PluginConstants    = require("plugin_constants")
local util             = require("util")

local CardDefaults     = require("card_defaults")

local PoetryMemorize = {}

PoetryMemorize.CONTEXT_LINE_OPTIONS = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20 }

local function count_newlines(s)
    local n = 0
    for _ in (s or ""):gmatch("\n") do n = n + 1 end
    return n
end

-- Convert selection HTML to plain text while keeping verse/paragraph line breaks.
local function strip_html_lines(html)
    if not html or html == "" then return "" end
    local text = html
    text = text:gsub("<%s*[bB][rR]%s*/?>", "\n")
    text = text:gsub("</%s*[pP]%s*>", "\n")
    text = text:gsub("</%s*[dD][iI][vV]%s*>", "\n")
    text = text:gsub("</%s*[lL][iI]%s*>", "\n")
    text = text:gsub("</%s*[hH][1-6]%s*>", "\n")
    text = text:gsub("<[^>]+>", " ")
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&quot;", '"')
    text = text:gsub("[ \t]+", " ")
    text = text:gsub("\n[ \t]+", "\n")
    text = text:gsub("[ \t]+\n", "\n")
    text = text:gsub("\n\n\n+", "\n\n")
    return text:match("^%s*(.-)%s*$") or ""
end

-- Preserve newlines for memorization (unlike clean_str in main.lua).
function PoetryMemorize.prepare_text(text, max_len)
    if not text or text == "" then return "" end
    text = util.cleanupSelectedText(text)
    if max_len and #text > max_len then text = text:sub(1, max_len) end
    return text
end

-- Best-effort text for memorization: EPUB/HTML keeps verse lines; never collapse \n.
function PoetryMemorize.extract_selection_text(ui, opts, max_len)
    opts = opts or {}
    local plain = opts.text or ""

    local from_html = ""
    if ui and ui.document then
        local doc = ui.document
        local pos0 = opts.pos0 or (opts.selected_text and opts.selected_text.pos0)
        local pos1 = opts.pos1 or (opts.selected_text and opts.selected_text.pos1)
        if pos0 and pos1 and doc.getHTMLFromXPointers then
            local ok, html = pcall(function()
                return doc:getHTMLFromXPointers(pos0, pos1, 0, true)
            end)
            if ok and type(html) == "string" and html ~= "" then
                from_html = strip_html_lines(html)
            end
        end
    end

    local prepared_html = (from_html ~= "") and PoetryMemorize.prepare_text(from_html, max_len) or ""
    local prepared_plain = PoetryMemorize.prepare_text(plain, max_len)

    if count_newlines(prepared_html) > count_newlines(prepared_plain) then
        return prepared_html
    elseif count_newlines(prepared_plain) > 0 then
        return prepared_plain
    elseif prepared_html ~= "" and #prepared_html >= math.max(1, #prepared_plain) then
        return prepared_html
    end
    return prepared_plain
end

PoetryMemorize.INTRO_TEXT = _([[
Creates overlapping step cards in Anki so you recite each new line or chunk aloud.

• Poetry: one step per line (long lines split by word count)
• Prose: split by sentences, then ~7-word chunks
• Each step shows prior lines as cue; you recite the next part
• Optional one full-passage recitation card per selection
• Deck: Memorize::Book title::page (created automatically)
• Anki note type must be named "Memorization"

Set up templates and deck options in the plugin docs (anki-memorization.md).]])

local function truncate_preview(s, max_len)
    s = s or ""
    if #s > max_len then return s:sub(1, max_len) .. "…" end
    return s
end

function PoetryMemorize.build_send_summary(cfg, lines, deck, meta)
    cfg = cfg or {}
    meta = meta or {}
    local step_cards = #lines
    local total = step_cards + (cfg.include_full_recitation ~= false and 1 or 0)
    local preview = lines[1] or ""
    if #preview > 50 then preview = preview:sub(1, 50) .. "…" end

    local ctx_desc
    if cfg.context_cumulative then
        ctx_desc = _("all prior lines (cumulative)")
    else
        ctx_desc = tostring(cfg.context_lines or 3) .. _(" prior steps (rolling)")
    end

    local body = _("Will send to Anki:\n")
        .. _("• ") .. tostring(total) .. _(" cards (")
        .. tostring(step_cards) .. _(" step")
        .. (step_cards == 1 and "" or "s")
    if cfg.include_full_recitation ~= false then
        body = body .. _(" + 1 full recitation")
    end
    body = body .. ")\n"
        .. _("• Deck: ") .. deck .. "\n"
        .. _("• Note type: ") .. (cfg.model or NoteTypeProfiles.MEMORIZATION_MODEL) .. "\n"
        .. _("• Context: ") .. ctx_desc .. "\n"
        .. _("• Chunk size: ~") .. tostring(cfg.max_words_per_unit or 7) .. _(" words (prose)\n")
    if cfg.force_verse_lines then
        body = body .. _("• Split mode: verse lines\n")
    end
    if cfg.replace_duplicates then
        body = body .. _("• Replace existing cards in this deck\n")
    end
    if MemorizationPolicy.requires_confirmation(
        #lines, cfg.max_memorization_steps) then
        body = body .. _("• Large passage: all ") .. tostring(#lines)
            .. _(" steps will be sent (none will be truncated)\n")
    end
    if preview ~= "" then
        body = body .. _("• First chunk: \"") .. preview .. "\"\n"
    end
    if meta.location and meta.location ~= "" then
        body = body .. _("• Location: ") .. meta.location .. "\n"
    end

    if cfg.show_split_preview and #lines > 0 then
        body = body .. "\n" .. _("Steps:") .. "\n"
        local max_steps = math.min(#lines, 24)
        for i = 1, max_steps do
            body = body .. tostring(i) .. ". " .. truncate_preview(lines[i], 72) .. "\n"
        end
        if #lines > max_steps then
            body = body .. _("… and ") .. tostring(#lines - max_steps) .. _(" more\n")
        end
    end

    return body
end

function PoetryMemorize.maybe_show_intro(then_fn, on_cancel)
    local saved = CardStorage.load_anki_settings() or {}
    if saved.skip_memorize_intro then
        then_fn()
        return
    end

    local intro_dlg
    intro_dlg = TextViewer:new {
        title         = _("Memorization cards"),
        text          = PoetryMemorize.INTRO_TEXT,
        show_menu     = false,
        buttons_table = {
            {{ text = _("Continue"), callback = function()
                UIManager:close(intro_dlg)
                then_fn()
            end }},
            {{ text = _("View README"), callback = function()
                local ok, rv = pcall(require, "readme_viewer")
                if ok and rv and rv.show_or_notify then
                    rv.show_or_notify("memorization")
                end
            end }},
            {{ text = _("Don't show again"), callback = function()
                UIManager:close(intro_dlg)
                saved.skip_memorize_intro = true
                CardStorage.save_anki_settings(saved)
                then_fn()
            end }},
            {{ text = _("Cancel"), callback = function()
                UIManager:close(intro_dlg)
                if on_cancel then on_cancel() end
            end }},
        },
    }
    UIManager:show(intro_dlg)
end

local function safe_deck_part(s, max_len)
    s = (s or ""):gsub("::", " "):gsub(":", " -"):match("^%s*(.-)%s*$") or ""
    if max_len and #s > max_len then
        s = s:sub(1, max_len - 3) .. "..."
    end
    return s
end

function PoetryMemorize.config(base)
    local cfg = {
        parent_deck               = "Memorize",
        model                     = NoteTypeProfiles.MEMORIZATION_MODEL,
        context_lines             = 3,
        context_cumulative        = false,
        max_words_per_unit        = 7,
        max_memorization_steps    = MemorizationPolicy.DEFAULT_MAX_STEPS,
        auto_create_deck          = true,
        include_full_recitation   = true,
        force_verse_lines         = false,
        show_split_preview        = false,
        replace_duplicates        = false,
        merge_batch               = false,
        auto_send                 = false,
        auto_save_on_fail         = false,
        quick_highlight_button    = false,
        skip_hub_submenu          = false,
        tags                      = { "KOReader", "memorization" },
    }
    if base and type(base.memorize) == "table" then
        for k, v in pairs(base.memorize) do cfg[k] = v end
    end
    local anki = CardFields.merged_anki_settings(base)
    if anki.url and anki.url ~= "" then cfg.url = anki.url end
    if anki.memorize_parent_deck and anki.memorize_parent_deck ~= "" then
        cfg.parent_deck = anki.memorize_parent_deck
    end
    if anki.memorize_model and anki.memorize_model ~= "" then
        cfg.model = anki.memorize_model
    end
    if anki.memorize_context_lines then
        cfg.context_lines = tonumber(anki.memorize_context_lines) or cfg.context_lines
    end
    if anki.memorize_context_cumulative ~= nil then
        cfg.context_cumulative = anki.memorize_context_cumulative
    end
    if anki.memorize_max_words then
        cfg.max_words_per_unit = tonumber(anki.memorize_max_words) or cfg.max_words_per_unit
    end
    if anki.max_memorization_steps then
        cfg.max_memorization_steps = MemorizationPolicy.max_steps(
            anki.max_memorization_steps)
    end
    if anki.memorize_tags and type(anki.memorize_tags) == "table" then
        cfg.tags = anki.memorize_tags
    end
    if anki.memorize_include_full_recitation ~= nil then
        cfg.include_full_recitation = anki.memorize_include_full_recitation
    end
    if anki.memorize_force_verse_lines ~= nil then
        cfg.force_verse_lines = anki.memorize_force_verse_lines
    end
    if anki.memorize_show_split_preview ~= nil then
        cfg.show_split_preview = anki.memorize_show_split_preview
    end
    if anki.memorize_replace_duplicates ~= nil then
        cfg.replace_duplicates = anki.memorize_replace_duplicates
    end
    if anki.memorize_merge_batch ~= nil then
        cfg.merge_batch = anki.memorize_merge_batch
    end
    cfg.auto_send = CardDefaults.auto_send_memorization(base)
    if anki.memorize_auto_save_on_fail ~= nil then
        cfg.auto_save_on_fail = anki.memorize_auto_save_on_fail
    end
    if anki.memorize_quick_highlight_button ~= nil then
        cfg.quick_highlight_button = anki.memorize_quick_highlight_button
    end
    if anki.memorize_skip_hub_submenu ~= nil then
        cfg.skip_hub_submenu = anki.memorize_skip_hub_submenu
    end
    if anki.sync_after_send ~= nil then
        cfg.sync_after_send = anki.sync_after_send
    end
    return cfg
end

function PoetryMemorize.requires_step_confirmation(lines_or_count, cfg)
    local count = type(lines_or_count) == "table" and #lines_or_count
        or tonumber(lines_or_count) or 0
    cfg = cfg or {}
    return MemorizationPolicy.requires_confirmation(
        count, cfg.max_memorization_steps)
end

function PoetryMemorize.split_lines(text)
    local lines = {}
    if not text or text == "" then return lines end
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    return lines
end

local function count_words(s)
    local n = 0
    for _ in (s or ""):gmatch("%S+") do n = n + 1 end
    return n
end

local function split_word_chunks(text, max_words)
    max_words = math.max(4, tonumber(max_words) or 12)
    local words = {}
    for w in (text or ""):gmatch("%S+") do table.insert(words, w) end
    if #words == 0 then return {} end
    if #words <= max_words then return { table.concat(words, " ") } end

    local chunks = {}
    for i = 1, #words, max_words do
        local part = {}
        for j = i, math.min(i + max_words - 1, #words) do
            table.insert(part, words[j])
        end
        table.insert(chunks, table.concat(part, " "))
    end
    return chunks
end

local SENTENCE_ABBREV = {
    mr = true, mrs = true, ms = true, dr = true, st = true, sr = true, jr = true,
    prof = true, vs = true, etc = true, approx = true, fig = true, no = true,
}

-- A "." is a sentence boundary unless it sits between two digits (a decimal)
-- or closes a common abbreviation ("Mr.", "Dr.", "e.g."). Prevents "Mr. Smith"
-- and "3.14" from being split mid-sentence.
local function period_is_boundary(text, i)
    local prev = i > 1 and text:sub(i - 1, i - 1) or ""
    local nxt = i < #text and text:sub(i + 1, i + 1) or ""
    if prev:match("%d") and nxt:match("%d") then
        return false
    end
    local j = i - 1
    while j >= 1 and text:sub(j, j):match("%a") do j = j - 1 end
    if SENTENCE_ABBREV[text:sub(j + 1, i - 1):lower()] then
        return false
    end
    if i >= 3 and text:sub(i - 2, i - 1):match("^%.[a-z]$") then
        return false
    end
    return true
end

local function split_sentences(text)
    local out = {}
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return out end

    local len = #text
    local start = 1
    local i = 1
    while i <= len do
        local ch = text:sub(i, i)
        local boundary = ch == "!" or ch == "?" or ch == ";"
            or (ch == "." and period_is_boundary(text, i))
        if boundary then
            local j = i + 1
            if j <= len and text:sub(j, j):match("[\"']") then j = j + 1 end
            if j > len or text:sub(j, j):match("%s") then
                local seg = text:sub(start, j - 1):match("^%s*(.-)%s*$")
                if seg ~= "" then table.insert(out, seg) end
                start = j
                while start <= len and text:sub(start, start):match("%s") do
                    start = start + 1
                end
                i = start
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    if start <= len then
        local tail = text:sub(start):match("^%s*(.-)%s*$")
        if tail ~= "" then table.insert(out, tail) end
    end
    return out
end

local function expand_long_units(units, max_words)
    local out = {}
    for _i, unit in ipairs(units) do
        if count_words(unit) > max_words then
            for _i2, chunk in ipairs(split_word_chunks(unit, max_words)) do
                table.insert(out, chunk)
            end
        else
            table.insert(out, unit)
        end
    end
    return out
end

-- Poetry: one unit per line break. Prose: sentences, then word chunks if needed.
function PoetryMemorize.split_units(text, cfg)
    cfg = cfg or {}
    local max_words = cfg.max_words_per_unit or 12

    local lines = PoetryMemorize.split_lines(text)
    if cfg.force_verse_lines then
        if #lines == 0 then return {} end
        return expand_long_units(lines, max_words)
    end

    if #lines >= 2 then
        return expand_long_units(lines, max_words)
    end

    local block = lines[1] or text:match("^%s*(.-)%s*$") or ""
    if block == "" then return {} end

    local sentences = split_sentences(block)
    if #sentences == 0 then
        sentences = { block }
    end

    local units = expand_long_units(sentences, max_words)
    if #units <= 1 then
        units = split_word_chunks(block, max_words)
    end
    return units
end

function PoetryMemorize.derive_title(lines, meta)
    meta = meta or {}
    if meta.book_title and meta.book_title ~= "" then
        local label = safe_deck_part(meta.book_title, 36)
        local loc = meta.location
        if loc and loc ~= "" then
            return label .. " · " .. loc
        end
        return label .. " · " .. _("excerpt")
    end
    local first = (lines and lines[1]) or ""
    local words = {}
    for w in first:gmatch("%S+") do
        table.insert(words, w)
        if #words >= 6 then break end
    end
    local t = table.concat(words, " ")
    if count_words(first) > 6 then t = t .. "…" end
    return (t ~= "" and t) or _("Selection")
end

function PoetryMemorize.derive_piece_label(meta, lines)
    meta = meta or {}
    if meta.book_title and meta.book_title ~= "" then
        if meta.location and meta.location ~= "" then
            return safe_deck_part(meta.location, 40)
        end
        return _("excerpt")
    end
    return PoetryMemorize.derive_title(lines, meta)
end

function PoetryMemorize.resolve_deck(cfg, book_title, piece_label)
    local parts = { safe_deck_part(cfg.parent_deck or "Memorize", 40) }
    local book = safe_deck_part(book_title, 40)
    local piece = safe_deck_part(piece_label, 50)
    if book ~= "" then table.insert(parts, book) end
    if piece ~= "" and piece ~= book then table.insert(parts, piece) end
    return table.concat(parts, "::")
end

local function merge_tags(base_tags, extra)
    local out, seen = {}, {}
    for _i, tag in ipairs(base_tags or {}) do
        if tag ~= "" and not seen[tag] then
            seen[tag] = true
            table.insert(out, tag)
        end
    end
    for _i, tag in ipairs(extra or {}) do
        if tag ~= "" and not seen[tag] then
            seen[tag] = true
            table.insert(out, tag)
        end
    end
    return out
end

function PoetryMemorize.build_notes(lines, opts)
    opts = opts or {}
    local notes = {}
    local full_text = table.concat(lines, "\n")
    local ctx_n = math.max(0, tonumber(opts.context_lines) or 3)
    local cumulative = opts.context_cumulative == true
    local title = opts.title or PoetryMemorize.derive_title(lines)
    local source = opts.source or ""

    for i = 1, #lines do
        local ctx_lines = {}
        local ctx_start
        if cumulative then
            ctx_start = 1
        else
            ctx_start = math.max(1, i - ctx_n)
        end
        for j = ctx_start, i - 1 do
            table.insert(ctx_lines, lines[j])
        end
        table.insert(notes, {
            deckName  = opts.deck,
            modelName = opts.model,
            fields    = {
                Title     = title,
                Context   = table.concat(ctx_lines, "\n"),
                Target    = lines[i],
                FullText  = full_text,
                Source    = source,
                LineIndex = tostring(i),
                FullRecite = "",
            },
            options = {
                allowDuplicate = true,
                duplicateScope = "deck",
            },
            tags = merge_tags(opts.tags, { "memorization::step" }),
        })
    end

    if opts.include_full_recitation ~= false then
        table.insert(notes, {
            deckName  = opts.deck,
            modelName = opts.model,
            fields    = {
                Title      = title,
                Context    = "",
                Target     = "",
                FullText   = full_text,
                Source     = source,
                LineIndex  = "",
                FullRecite = "yes",
            },
            options = {
                allowDuplicate = true,
                duplicateScope = "deck",
            },
            tags = merge_tags(opts.tags, { "memorization::full" }),
        })
    end

    return notes
end

function PoetryMemorize.send_lines(lines, base_config, meta, done)
    meta = meta or {}
    local cfg = PoetryMemorize.config(base_config)
    if PoetryMemorize.requires_step_confirmation(lines, cfg)
        and not meta.threshold_confirmed then
        if done then
            done(nil, _("This passage has ") .. tostring(#lines)
                .. _(" steps and requires confirmation before sending all of them."),
                {
                    total = #lines
                        + (cfg.include_full_recitation ~= false and 1 or 0),
                    step_count = #lines,
                    max_steps = cfg.max_memorization_steps,
                    requires_confirmation = true,
                    all_sent = false,
                    partial = false,
                })
        end
        return
    end
    if PluginConstants.is_placeholder_anki_url(cfg.url) then
        if done then done(nil, _("Anki URL not set. Use AnkiKoFlash → Settings.")) end
        return
    end

    local title = meta.title or PoetryMemorize.derive_title(lines, meta)
    local source = meta.source or ""
    local piece_label = meta.piece_label or PoetryMemorize.derive_piece_label(meta, lines)
    local deck = meta.deck or PoetryMemorize.resolve_deck(cfg, meta.book_title, piece_label)

    if cfg.replace_duplicates then
        local ok_del, del_err = AnkiSync.delete_notes_in_deck(cfg.url, deck)
        if not ok_del then
            if done then done(nil, del_err or _("Could not replace existing cards")) end
            return
        end
    end

    local notes = PoetryMemorize.build_notes(lines, {
        title                   = title,
        source                  = source,
        deck                    = deck,
        model                   = cfg.model,
        context_lines           = cfg.context_lines,
        context_cumulative      = cfg.context_cumulative,
        include_full_recitation = cfg.include_full_recitation,
        tags                    = cfg.tags,
    })

    local total = #notes
    local info = MemorizationResult.from_counts(total, 0, 0, 0)
    info.deck = deck

    if cfg.auto_create_deck then
        local ok_deck, err_deck = AnkiSync.ensure_deck(cfg.url, deck)
        if not ok_deck then
            if done then done(nil, err_deck) end
            return
        end
    end

    local existing, existing_err =
        AnkiSync.find_existing_memorization_notes(cfg.url, notes)
    if not existing then
        if done then
            done(nil, _("Could not check existing memorization cards: ")
                .. (existing_err or _("Send failed")), info)
        end
        return
    end

    local pending = {}
    local remaining_existing = {}
    for identity, count in pairs(existing) do
        remaining_existing[identity] = count
    end
    for _, note in ipairs(notes) do
        local identity = AnkiSync.memorization_note_identity(note)
        local count = remaining_existing[identity] or 0
        if count > 0 then
            remaining_existing[identity] = count - 1
            info.already_present = info.already_present + 1
        else
            pending[#pending + 1] = note
        end
    end

    local batch_sent, _batch_failed, batch_err =
        AnkiSync.add_notes_batch(cfg.url, pending)
    info.sent = batch_sent or 0

    -- Re-read exact fields after every write attempt. This verifies ambiguous
    -- timeouts and makes a retained partial passage safe to retry.
    local final_existing, verify_err =
        AnkiSync.find_existing_memorization_notes(cfg.url, notes)
    local confirmed = info.already_present + info.sent
    if final_existing then
        confirmed = 0
        local available = {}
        for identity, count in pairs(final_existing) do available[identity] = count end
        for _, note in ipairs(notes) do
            local identity = AnkiSync.memorization_note_identity(note)
            local count = available[identity] or 0
            if count > 0 then
                available[identity] = count - 1
                confirmed = confirmed + 1
            end
        end
        info.verified = math.max(
            0, confirmed - info.already_present - info.sent)
    end
    local final_info = MemorizationResult.from_counts(
        total, info.sent, info.already_present, confirmed)
    final_info.deck = deck
    info = final_info

    if confirmed > 0 then
        local saved = CardStorage.load_anki_settings() or {}
        saved.last_memorize_deck = deck
        CardStorage.save_anki_settings(saved)
    end

    local msg
    if info.all_sent then
        if info.sent == total then
            msg = tostring(info.sent) .. _(" cards sent to ") .. deck
        elseif info.sent == 0 then
            msg = tostring(total) .. _(" cards already in Anki in ") .. deck
        else
            msg = tostring(info.sent) .. _(" cards sent, ")
                .. tostring(total - info.sent) .. _(" already in Anki — ") .. deck
        end
    else
        PrivacyLog.warn("memorization_partial_send", {
            confirmed = confirmed,
            failed = info.failed,
            total = total,
        })
        msg = _("Memorization send incomplete: ") .. tostring(confirmed)
            .. "/" .. tostring(total) .. _(" cards confirmed in Anki, ")
            .. tostring(info.failed) .. _(" failed. Passage kept pending.")
        local detail = batch_err or verify_err
        if detail and detail ~= "" then msg = msg .. " " .. detail end
    end
    if confirmed > info.already_present then
        msg = msg .. AnkiSync.sync_status_suffix(cfg)
    end
    if done then done(info.all_sent and true or nil, msg, info) end
end

function PoetryMemorize.send_highlight(base_config, text, ui, meta, done)
    meta = meta or {}
    local cfg = PoetryMemorize.config(base_config)
    local lines = PoetryMemorize.split_units(PoetryMemorize.prepare_text(text), cfg)
    if #lines == 0 then
        if done then done(nil, _("No text to memorize.")) end
        return
    end
    if PoetryMemorize.requires_step_confirmation(lines, cfg)
        and not meta.threshold_confirmed then
        if done then
            done(nil, _("This passage has ") .. tostring(#lines)
                .. _(" steps and requires confirmation before sending all of them."),
                {
                    total = #lines
                        + (cfg.include_full_recitation ~= false and 1 or 0),
                    step_count = #lines,
                    max_steps = cfg.max_memorization_steps,
                    requires_confirmation = true,
                    all_sent = false,
                    partial = false,
                })
        end
        return
    end

    if not meta.source then
        local book = CardFields.format_book_source(meta.book_title, meta.book_author)
        meta.source = ReadingLocation.append_to_source(book, ui)
    end
    meta.location = ReadingLocation.describe(ui)
    if not meta.title then
        meta.title = PoetryMemorize.derive_title(lines, meta)
    end
    meta.piece_label = meta.piece_label or PoetryMemorize.derive_piece_label(meta, lines)

    PoetryMemorize.send_lines(lines, base_config, meta, done)
end

local function save_pending_or_notify(text, ui, meta, deck, success_message)
    if not meta.source then
        local book = CardFields.format_book_source(meta.book_title, meta.book_author)
        meta.source = ReadingLocation.append_to_source(book, ui)
    end
    if CardStorage.save_memorization_pending(text, meta, deck) then
        UIManager:show(Notification:new {
            text    = success_message
                or _("Saved locally. Send from My Cards when Anki is available."),
            timeout = success_message and 8 or 5,
        })
        return true
    end
    UIManager:show(InfoMessage:new {
        text    = _("Could not save memorization passage."),
        timeout = 5,
    })
    return false
end

function PoetryMemorize.send_immediate(base_config, text, ui, meta, done)
    meta = meta or {}
    local cfg = PoetryMemorize.config(base_config)
    local prepared = PoetryMemorize.prepare_text(text)
    local lines = PoetryMemorize.split_units(prepared, cfg)
    if #lines == 0 then
        if done then done(nil, _("No text to memorize.")) end
        return
    end

    meta.location = meta.location or ReadingLocation.describe(ui)
    if not meta.title then
        meta.title = PoetryMemorize.derive_title(lines, meta)
    end
    meta.piece_label = meta.piece_label or PoetryMemorize.derive_piece_label(meta, lines)
    local deck = meta.deck
        or PoetryMemorize.resolve_deck(cfg, meta.book_title, meta.piece_label)

    local loading = Notification:new {
        text    = _("Sending memorization cards…"),
        timeout = 120,
    }
    UIManager:show(loading)
    UIManager:scheduleIn(0.05, function()
        PoetryMemorize.send_highlight(base_config, prepared, ui, meta,
            function(ok, err_or_msg, info)
            UIManager:close(loading)
            if ok then
                UIManager:show(Notification:new { text = err_or_msg, timeout = 5 })
                if done then done(true, err_or_msg, info) end
                return
            end
            if info and info.partial then
                MemorizationResult.persist_partial_before_callback(
                    info,
                    function()
                        return save_pending_or_notify(prepared, ui, meta, deck,
                            (err_or_msg or _("Memorization send incomplete."))
                            .. "\n\n" .. _(
                                "Passage kept pending. Retry from My Cards to send only the remaining cards."))
                    end,
                    function()
                        if done then done(false, err_or_msg, info) end
                    end)
                return
            end
            if cfg.auto_save_on_fail then
                save_pending_or_notify(prepared, ui, meta, deck)
                if done then done(false, err_or_msg, info) end
                return
            end
            UIManager:show(InfoMessage:new {
                text    = (err_or_msg or _("Send failed"))
                    .. "\n\n" .. _("Use Save for later to queue on this device."),
                timeout = 8,
            })
            if done then done(nil, err_or_msg, info) end
        end)
    end)
end

local function show_memorize_send_confirm(base_config, text, ui, meta, cfg, lines, deck)
    local body = PoetryMemorize.build_send_summary(cfg, lines, deck, meta)

    if not PluginConstants.is_placeholder_anki_url(cfg.url) and not cfg.replace_duplicates then
        local existing, err = AnkiSync.count_notes_in_deck(cfg.url, deck)
        if existing and existing > 0 then
            body = _("This book and page already have cards in Anki (")
                .. tostring(existing) .. _(" in this deck).\n\n")
                .. _("Exact matching steps are skipped; changed passages may add cards.\n")
                .. _("Enable Replace existing cards in Memorization settings to overwrite.\n\n")
                .. body
        elseif err then
            body = body .. "\n\n" .. _("(Could not check for duplicates: ") .. err .. ")"
        end
    end

    body = body .. "\n\n" .. _(
        "Save for later if Anki is unreachable. Send pending cards from My Cards or the hub menu.")

    local dlg
    dlg = TextViewer:new {
        title         = _("Send memorization cards"),
        text          = body,
        show_menu     = false,
        buttons_table = {
            {{ text = _("Send to Anki"), callback = function()
                UIManager:close(dlg)
                meta.threshold_confirmed = true
                local loading = Notification:new {
                    text    = _("Sending memorization cards…"),
                    timeout = 120,
                }
                UIManager:show(loading)
                UIManager:scheduleIn(0.05, function()
                    PoetryMemorize.send_highlight(base_config, text, ui, meta,
                        function(ok, err_or_msg, info)
                        UIManager:close(loading)
                        if ok then
                            UIManager:show(Notification:new { text = err_or_msg, timeout = 5 })
                        elseif info and info.partial then
                            MemorizationResult.persist_partial_before_callback(
                                info,
                                function()
                                    return save_pending_or_notify(text, ui, meta, deck,
                                        (err_or_msg or _("Memorization send incomplete."))
                                        .. "\n\n" .. _(
                                            "Passage kept pending. Retry from My Cards to send only the remaining cards."))
                                end,
                                meta.on_done)
                            return
                        else
                            UIManager:show(InfoMessage:new {
                                text    = (err_or_msg or _("Send failed"))
                                    .. "\n\n" .. _("Use Save for later to queue on this device."),
                                timeout = 8,
                            })
                        end
                        if meta.on_done then meta.on_done() end
                    end)
                end)
            end }},
            {{ text = _("Save for later"), callback = function()
                UIManager:close(dlg)
                save_pending_or_notify(text, ui, meta, deck)
                if meta.on_done then meta.on_done() end
            end }},
            {{ text = _("Cancel"), callback = function()
                UIManager:close(dlg)
                if meta.on_done then meta.on_done() end
            end }},
        },
    }
    UIManager:show(dlg)
end

function PoetryMemorize.confirm_and_send(base_config, text, ui, meta)
    meta = meta or {}
    local cfg = PoetryMemorize.config(base_config)
    local prepared = PoetryMemorize.prepare_text(text)
    local lines = PoetryMemorize.split_units(prepared, cfg)
    if #lines == 0 then
        UIManager:show(InfoMessage:new {
            text    = _("Select one or more lines to memorize."),
            timeout = 4,
        })
        if meta.on_done then meta.on_done() end
        return
    end

    meta.location = ReadingLocation.describe(ui)
    if not meta.title then
        meta.title = PoetryMemorize.derive_title(lines, meta)
    end
    meta.piece_label = meta.piece_label or PoetryMemorize.derive_piece_label(meta, lines)
    local deck = meta.deck
        or PoetryMemorize.resolve_deck(cfg, meta.book_title, meta.piece_label)
    local requires_confirmation =
        PoetryMemorize.requires_step_confirmation(lines, cfg)

    local function after_intro()
        if cfg.auto_send and not requires_confirmation then
            PoetryMemorize.send_immediate(base_config, prepared, ui, meta, function()
                if meta.on_done then meta.on_done() end
            end)
            return
        end
        show_memorize_send_confirm(base_config, prepared, ui, meta, cfg, lines, deck)
    end

    if cfg.auto_send then
        after_intro()
        return
    end

    PoetryMemorize.maybe_show_intro(after_intro, meta.on_done)
end

return PoetryMemorize
