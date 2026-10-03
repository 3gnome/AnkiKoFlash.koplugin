-- Highlight Inbox — batch highlights as Vocabulary or Memorization cards.

local Menu         = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local UIManager    = require("ui/uimanager")
local ConfirmBox   = require("ui/widget/confirmbox")
local _            = require("gettext")

local CardFields      = require("card_fields")
local CardStorage     = require("card_storage")
local CardDefaults    = require("card_defaults")
local SendFlow        = require("send_flow")
local DictionaryLookup
do
    local ok, mod = pcall(require, "dictionary_lookup")
    if ok then DictionaryLookup = mod end
end
local EtymologyLookup
do
    local ok, mod = pcall(require, "etymology_lookup")
    if ok then EtymologyLookup = mod end
end
local PoetryMemorize  = require("poetry_memorize")
local PluginConstants = require("plugin_constants")
local ReadingLocation = require("reading_location")
local get_selection_in_context = require("selection_context")
local HighlightBooks = require("highlight_books")
local PluginPeers = require("plugin_peers")
local BatchGeneration = require("batch_generation")
local PositionUtils = require("position_utils")
local HighlightInbox  = {}
local Nav             = require("nav")
local SelectableMenu  = require("selectable_menu")

local MODE_VOCAB = "vocabulary"
local MODE_MEM   = "memorization"

local MODE_ORDER = { MODE_VOCAB, MODE_MEM }

local function mode_label(config, mode)
    if mode == MODE_VOCAB then
        return CardDefaults.vocabulary_hub_label(config)
    elseif mode == MODE_MEM then
        return PluginConstants.MEMORIZATION_CARD_LABEL
    end
    return mode
end

local function normalize(s)
    return (s or ""):lower():match("^%s*(.-)%s*$")
end

local function clean(s, max_len)
    if not s then return "" end
    s = s:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if max_len and #s > max_len then s = s:sub(1, max_len) end
    return s
end

local function capitalize_first(s)
    return (s:gsub("^%l", string.upper))
end

local function mode_button_label(config, mode)
    return _("Mode: ") .. mode_label(config, mode) .. " " .. _("(Tap to change)")
end

local function next_mode(mode)
    for i, m in ipairs(MODE_ORDER) do
        if m == mode then
            return MODE_ORDER[(i % #MODE_ORDER) + 1]
        end
    end
    return MODE_VOCAB
end

local function build_highlights(ui, book_ctx)
    if book_ctx and book_ctx.path then
        return HighlightBooks.load_highlights_for_book(book_ctx.path, ui)
    end
    return HighlightBooks.load_highlights_for_book(ui and ui.document and ui.document.file, ui)
end

local function selected_book_is_open_document(ui, book_ctx)
    return ui and ui.document
        and type(ui.document.file) == "string"
        and ui.document.file ~= ""
        and book_ctx
        and type(book_ctx.path) == "string"
        and book_ctx.path == ui.document.file
end

function HighlightInbox.passage_text(ui, highlight, book_ctx, max_len)
    highlight = highlight or {}
    max_len = max_len or 2000
    if not selected_book_is_open_document(ui, book_ctx) then
        return PoetryMemorize.prepare_text(highlight.text or "", max_len)
    end
    return PoetryMemorize.extract_selection_text(ui, {
        text = highlight.text or "",
        pos0 = highlight.ann and highlight.ann.pos0,
        pos1 = highlight.ann and highlight.ann.pos1,
    }, max_len)
end

function HighlightInbox.delete_pending_for_highlight(
    text, document_path, pos0, pos1)
    return CardStorage.delete_by_phrase_in_document(
        text, document_path, pos0, pos1)
end

function HighlightInbox.has_highlights(ui)
    if not ui or not ui.document then
        return false
    end
    local current = ui.document.file
    if current then
        local live = HighlightBooks.load_highlights_for_book(current, ui)
        if #live > 0 then
            return true
        end
    end
    local books = HighlightBooks.discover_books_with_highlights(current, ui)
    return #books > 0
end

function HighlightInbox.notify_empty()
    UIManager:show(Notification:new {
        text    = _("No highlights found in your reading history."),
        timeout = 3,
    })
end

local function document_path_for_highlight(highlight, book_ctx)
    return (book_ctx and book_ctx.path)
        or (highlight and highlight.document_path)
        or ""
end

local function document_phrase_key(document_path, phrase)
    if not document_path or document_path == "" then return nil end
    local normalized = normalize(phrase)
    if normalized == "" then return nil end
    return document_path .. "\31phrase\31" .. normalized
end

local function document_position_key(document_path, pos0, pos1)
    if not document_path or document_path == "" or pos0 == nil then
        return nil
    end
    return document_path .. "\31pos\31" .. PositionUtils.pair_key(pos0, pos1)
end

function HighlightInbox.already_carded_from_cards(cards)
    local already_carded = { positioned = {}, legacy = {} }
    for _i, card in ipairs(cards or {}) do
        local positioned_key = document_position_key(
            card.document_path, card.highlight_pos0, card.highlight_pos1)
        if positioned_key then
            already_carded.positioned[positioned_key] = true
        else
            local legacy_key = document_phrase_key(card.document_path, card.phrase)
            if legacy_key then already_carded.legacy[legacy_key] = true end
        end
    end
    return already_carded
end

function HighlightInbox.is_already_carded(already_carded, highlight, book_ctx)
    already_carded = already_carded or {}
    local document_path = document_path_for_highlight(highlight, book_ctx)
    local ann = highlight and highlight.ann
    local positioned_key = ann and document_position_key(
        document_path, ann.pos0, ann.pos1)
    if positioned_key and already_carded.positioned
        and already_carded.positioned[positioned_key] then
        return true
    end
    local legacy_key = document_phrase_key(
        document_path, highlight and highlight.text)
    return legacy_key ~= nil
        and already_carded.legacy
        and already_carded.legacy[legacy_key] == true
end

local function load_already_carded()
    return HighlightInbox.already_carded_from_cards(CardStorage.load_cards())
end

local function default_selected(highlights, already_carded, send_mode, book_ctx)
    local selected = {}
    for i, h in ipairs(highlights) do
        if send_mode == MODE_MEM then
            selected[i] = true
        else
            selected[i] = not HighlightInbox.is_already_carded(
                already_carded, h, book_ctx)
        end
    end
    return selected
end

-- Internal: build and show the selection menu with current state.
local function show_menu(ui, config, highlights, already_carded, selected, inbox_opts, send_mode, book_ctx)
    inbox_opts = inbox_opts or {}
    send_mode = send_mode or MODE_VOCAB
    book_ctx = book_ctx or HighlightBooks.make_book_ctx(nil, ui)
    if book_ctx then
        HighlightBooks.refresh_book_ctx_count(book_ctx, ui)
    end
    local menu_ref = {}
    local back_label = inbox_opts.back_label or _("← Back")
    local guard = { busy = false }
    local batch_state = BatchGeneration.new()
    local active_batch_token = nil

    local function cancel_active_batch()
        if active_batch_token then
            BatchGeneration.cancel(batch_state, active_batch_token)
            active_batch_token = nil
        end
    end

    local function go_back()
        if guard.busy then return end
        cancel_active_batch()
        if not inbox_opts.on_back then return end
        guard.busy = true
        Nav.after_close(function()
            if menu_ref[1] then UIManager:close(menu_ref[1]) end
        end, function()
            guard.busy = false
            inbox_opts.on_back()
        end)
    end

    local function soft_rebuild()
        UIManager:scheduleIn(0, function()
            if menu_ref[1] then UIManager:close(menu_ref[1]) end
            show_menu(ui, config, highlights, already_carded, selected, inbox_opts, send_mode, book_ctx)
        end)
    end

    local function hard_rebuild()
        UIManager:scheduleIn(0, function()
            if menu_ref[1] then UIManager:close(menu_ref[1]) end
            local fresh = build_highlights(ui, book_ctx)
            local carded = load_already_carded()
            if book_ctx then
                HighlightBooks.refresh_book_ctx_count(book_ctx, ui)
            end
            show_menu(ui, config, fresh, carded, default_selected(fresh, carded, send_mode, book_ctx),
                inbox_opts, send_mode, book_ctx)
        end)
    end

    local function show_switch_book_menu()
        local books = HighlightBooks.discover_books_with_highlights(
            ui and ui.document and ui.document.file, ui)
        if #books <= 1 then
            UIManager:show(Notification:new {
                text    = _("No other books with highlights."),
                timeout = 3,
            })
            return
        end
        local picker_ref = {}
        local items = {}
        for _, book in ipairs(books) do
            local pick = book
            items[#items + 1] = {
                text = pick.title .. " (" .. tostring(pick.count) .. ")",
                mandatory_func = function()
                    return book_ctx and pick.path == book_ctx.path and "✓" or ""
                end,
                callback = function()
                    if picker_ref[1] then UIManager:close(picker_ref[1]) end
                    if menu_ref[1] then UIManager:close(menu_ref[1]) end
                    local new_ctx = {
                        path = pick.path,
                        title = pick.title,
                        is_current = pick.is_current,
                        count = pick.count,
                    }
                    local fresh = build_highlights(ui, new_ctx)
                    local carded = load_already_carded()
                    show_menu(ui, config, fresh, carded,
                        default_selected(fresh, carded, send_mode, new_ctx),
                        inbox_opts, send_mode, new_ctx)
                end,
            }
        end
        Nav.prepend_back(items, nil, picker_ref, _("← Back"))
        picker_ref[1] = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
            title = _("Switch book"),
            item_table = items,
        }), function()
            if picker_ref[1] then UIManager:close(picker_ref[1]) end
        end)
        Nav.show(picker_ref[1])
    end

    local function book_title_author()
        if book_ctx and not book_ctx.is_current then
            local meta = HighlightBooks.read_book_metadata(book_ctx.path)
            return meta.title, meta.author
        end
        local book_props = (ui.document and ui.document:getProps()) or {}
        local title = clean(book_props.title or "", 100)
        local author = book_props.authors or ""
        if type(author) == "table" then author = table.concat(author, ", ") end
        author = clean((author ~= "" and author or "Unknown Author"), 100)
        if title == "" and book_ctx then
            title = clean(book_ctx.title or "", 100)
        end
        return title, author
    end

    local items   = {}

    if book_ctx then
        table.insert(items, {
            text = _("Switch book…") .. "  (" .. book_ctx.title .. ")",
            bold = true,
            callback = show_switch_book_menu,
        })
        if not book_ctx.is_current then
            table.insert(items, {
                text = _("Open this book to delete highlights."),
                dim = true,
                enabled = false,
                keep_menu_open = true,
            })
        end
        if PluginPeers.is_tagbank_available(ui) then
            table.insert(items, {
                text = _("Sync All Highlights"),
                bold = true,
                callback = function()
                    local tagbank = PluginPeers.get_tagbank_plugin(ui)
                    if tagbank and tagbank.syncAllBooksFromHistory then
                        tagbank:syncAllBooksFromHistory()
                    else
                        UIManager:show(Notification:new {
                            text    = _("Tag Bank Highlight Sync is not available."),
                            timeout = 3,
                        })
                    end
                end,
            })
        end
    end

    local function selected_for_generate()
        local to_do = {}
        for i, h in ipairs(highlights) do
            if selected[i] then
                if send_mode == MODE_MEM
                    or not HighlightInbox.is_already_carded(
                        already_carded, h, book_ctx) then
                    table.insert(to_do, h)
                end
            end
        end
        return to_do
    end

    local function generate_action_label(n)
        return (send_mode == MODE_MEM and _("Send Selected to Anki (") or _("Generate Selected ("))
            .. tostring(n) .. ")"
    end

    local generate_count = #selected_for_generate()

    table.insert(items, {
        text     = mode_button_label(config, send_mode),
        bold     = true,
        callback = function()
            send_mode = next_mode(send_mode)
            soft_rebuild()
        end,
    })

    table.insert(items, {
        text     = _("View README"),
        callback = function()
            local ReadmeViewer = require("readme_viewer")
            local readme_id = send_mode
            ReadmeViewer.show_or_notify(readme_id)
        end,
    })

    local function highlight_context(h)
        local raw = h.text or ""
        if book_ctx and book_ctx.is_current and ui and ui.document then
            return clean(get_selection_in_context(ui.document, raw, 10), 2000)
        end
        return clean(raw, 2000)
    end

    local function apply_highlight_meta(card, h, context)
        if h.ann then
            card.highlight_pos0 = h.ann.pos0
            card.highlight_pos1 = h.ann.pos1
        end
        card.document_path = book_ctx and book_ctx.path or nil
        card._context = context
    end

    local function run_dictionary_batch(to_do, title, author)
        local model  = CardFields.default_vocabulary_model(config)
        local total  = #to_do
        local done   = 0
        local sent   = 0
        local failed = 0
        local send_failed = 0
        local auto_send = CardDefaults.auto_send_vocabulary(config)
        local default_deck = CardDefaults.vocabulary_deck(config)
        local anki_cfg = CardFields.merged_anki_settings(config)
        local pref_dict = CardDefaults.vocabulary_dictionary(config)
        local ety_dict = CardDefaults.etymology_dictionary(config)
        local ety_missing = 0
        local prog_notif
        local token = BatchGeneration.begin(batch_state)
        active_batch_token = token
        local finished = false
        local generate_next

        local function is_active()
            return BatchGeneration.is_current(batch_state, token)
        end

        local function close_progress()
            local progress = prog_notif
            prog_notif = nil
            if progress then
                progress._anki_internal_close = true
                UIManager:close(progress)
            end
        end

        local function finish(cancelled)
            if finished then return end
            finished = true
            if active_batch_token == token then active_batch_token = nil end
            close_progress()
            local msg
            if auto_send then
                msg = tostring(sent) .. _(" card(s) sent to Anki")
                if send_failed > 0 then
                    msg = msg .. ", " .. tostring(send_failed)
                        .. _(" failed to send (saved locally)")
                end
                if done > send_failed then
                    msg = msg .. ", " .. tostring(done - send_failed)
                        .. _(" saved locally")
                end
            else
                msg = tostring(done) .. _(" card(s) saved")
            end
            if failed > 0 then
                msg = msg .. ", " .. tostring(failed) .. _(" failed")
            end
            if ety_missing > 0 then
                msg = msg .. ", " .. tostring(ety_missing) .. _(" had no etymology entry")
            end
            if cancelled then
                msg = msg .. ", " .. _("stopped after current item")
            end
            UIManager:show(Notification:new { text = msg, timeout = 5 })
        end

        local function show_progress(i)
            close_progress()
            prog_notif = Notification:new {
                text    = _("Generating ") .. tostring(i) .. "/" .. tostring(total) .. "…"
                    .. _("\nTap to stop after current item."),
                timeout = false,
                toast   = false,
            }
            local progress = prog_notif
            local original_on_close = progress.onCloseWidget
            function progress:onCloseWidget()
                if original_on_close then original_on_close(self) end
                if prog_notif == self then prog_notif = nil end
                if not self._anki_internal_close and not finished then
                    BatchGeneration.cancel(batch_state, token)
                    finish(true)
                end
            end
            UIManager:show(prog_notif)
        end

        local function continue_batch(i)
            if is_active() then generate_next(i) else finish(true) end
        end

        local function after_vocab_card(card, i)
            if not is_active() then finish(true); return end
            card.target_deck = default_deck or card.target_deck or ""
            CardStorage.save_or_update(card)
            if auto_send and default_deck then
                card.target_deck = default_deck
                SendFlow.quick_send(anki_cfg, card, function(ok)
                    if not is_active() then finish(true); return end
                    if ok then
                        sent = sent + 1
                    else
                        send_failed = send_failed + 1
                        done = done + 1
                    end
                    continue_batch(i + 1)
                end, {
                    ui = ui,
                    use_configured_deck = true,
                    background = true,
                })
            else
                done = done + 1
                continue_batch(i + 1)
            end
        end

        generate_next = function(i)
            if not is_active() then finish(true); return end
            if i > total then finish(); return end
            local h      = to_do[i]
            local phrase = capitalize_first(clean(h.text or "", 2000))
            local context = highlight_context(h)
            show_progress(i)
            UIManager:scheduleIn(0.05, function()
                if not is_active() then finish(true); return end
                if not DictionaryLookup then
                    failed = failed + 1
                    continue_batch(i + 1)
                    return
                end
                local entries, _err = DictionaryLookup.lookup_all(ui, phrase,
                    { exclude_dictionary = ety_dict })
                if not is_active() then finish(true); return end
                local entry = nil
                if entries then
                    if pref_dict and pref_dict ~= "" then
                        for _j, e in ipairs(entries) do
                            if e.dict == pref_dict then entry = e; break end
                        end
                    end
                    if not entry then entry = entries[1] end
                end
                if entry then
                    local card = {
                        phrase          = capitalize_first(clean(entry.word or phrase, 2000)),
                        definition      = entry.definition or "",
                        context         = context,
                        text            = context,
                        model           = model,
                        target_model    = model,
                        dictionary_only = true,
                        dictionary_name = entry.dict or "",
                        card_kind       = "vocabulary",
                        book_title      = title,
                        book_author     = author,
                    }
                    apply_highlight_meta(card, h, context)
                    CardFields.apply_reading_source(
                        card, title, author, nil, ReadingLocation.describe(ui))
                    if EtymologyLookup then
                        local ety, ety_status = EtymologyLookup.lookup(
                            ui, entry.word or phrase, ety_dict)
                        if ety and ety ~= "" then
                            card.etymology = ety
                            card.anki_fields = card.anki_fields or {}
                            card.anki_fields.Etymology = ety
                        elseif ety_status == "not_found" and ety_dict and ety_dict ~= "" then
                            ety_missing = ety_missing + 1
                        end
                    end
                    CardFields.normalize(card, config)
                    after_vocab_card(card, i)
                else
                    failed = failed + 1
                    continue_batch(i + 1)
                end
            end)
        end

        continue_batch(1)
    end

    local function run_memorization_batch(to_do, title, author, threshold_confirmed)
        local cfg = PoetryMemorize.config(config)
        local total = #to_do
        local done_passages, saved_local, failed = 0, 0, 0
        local partial_confirmed, partial_remaining = 0, 0
        local prog_notif
        local token = BatchGeneration.begin(batch_state)
        active_batch_token = token
        local finished = false

        local function is_active()
            return BatchGeneration.is_current(batch_state, token)
        end

        local function close_progress()
            local progress = prog_notif
            prog_notif = nil
            if progress then
                progress._anki_internal_close = true
                UIManager:close(progress)
            end
        end

        local function finish(cancelled)
            if finished then return end
            finished = true
            if active_batch_token == token then active_batch_token = nil end
            close_progress()
            local msg = tostring(done_passages) .. _(" passage(s) sent to Anki")
            if saved_local > 0 then
                msg = msg .. ", " .. tostring(saved_local) .. _(" kept pending")
            end
            if failed > 0 then
                msg = msg .. ", " .. tostring(failed) .. _(" failed")
            end
            if partial_confirmed > 0 or partial_remaining > 0 then
                msg = msg .. "; " .. tostring(partial_confirmed)
                    .. _(" card(s) confirmed, ") .. tostring(partial_remaining)
                    .. _(" remain pending")
            end
            if cancelled then
                msg = msg .. ", " .. _("stopped after current item")
            end
            UIManager:show(Notification:new { text = msg, timeout = 6 })
        end

        local function show_progress(label)
            close_progress()
            prog_notif = Notification:new {
                text    = label .. _("\nTap to stop after current item."),
                timeout = false,
                toast   = false,
            }
            local progress = prog_notif
            local original_on_close = progress.onCloseWidget
            function progress:onCloseWidget()
                if original_on_close then original_on_close(self) end
                if prog_notif == self then prog_notif = nil end
                if not self._anki_internal_close and not finished then
                    BatchGeneration.cancel(batch_state, token)
                    finish(true)
                end
            end
            UIManager:show(prog_notif)
        end

        local function passage_text(h)
            return HighlightInbox.passage_text(ui, h, book_ctx, 2000)
        end

        local function send_one_passage(text, meta, on_done)
            show_progress(_("Sending memorization cards…"))
            UIManager:scheduleIn(0.05, function()
                if not is_active() then finish(true); return end
                meta.threshold_confirmed = threshold_confirmed == true
                PoetryMemorize.send_highlight(config, text, ui, meta,
                    function(ok, _err, info)
                    if not is_active() then finish(true); return end
                    if ok then
                        done_passages = done_passages + 1
                        if on_done then on_done(true, info) end
                        return
                    end
                    if info and info.partial then
                        partial_confirmed = partial_confirmed
                            + math.max(0, (info.total or 0) - (info.failed or 0))
                        partial_remaining = partial_remaining + (info.failed or 0)
                    end
                    local piece_cfg = PoetryMemorize.config(config)
                    local lines = PoetryMemorize.split_units(
                        PoetryMemorize.prepare_text(text), piece_cfg)
                    meta.piece_label = meta.piece_label
                        or PoetryMemorize.derive_piece_label(meta, lines)
                    local deck = PoetryMemorize.resolve_deck(
                        piece_cfg, meta.book_title, meta.piece_label)
                    if CardStorage.save_memorization_pending(text, meta, deck) then
                        saved_local = saved_local + 1
                    else
                        failed = failed + 1
                    end
                    if on_done then on_done(false, info) end
                end)
            end)
        end

        if cfg.merge_batch and total > 1 then
            local parts = {}
            for _, h in ipairs(to_do) do
                local t = passage_text(h)
                if t ~= "" then table.insert(parts, t) end
            end
            local merged = table.concat(parts, "\n")
            if merged == "" then
                UIManager:show(Notification:new {
                    text    = _("No text to memorize."),
                    timeout = 4,
                })
                return
            end
            send_one_passage(merged, {
                book_title  = title,
                book_author = author,
                document_path = book_ctx and book_ctx.path or nil,
            }, function() finish(not is_active()) end)
            return
        end

        local function send_next(i)
            if not is_active() then finish(true); return end
            if i > total then finish(); return end
            local h = to_do[i]
            local text = passage_text(h)
            show_progress(_("Sending ") .. tostring(i) .. "/" .. tostring(total) .. "…")
            send_one_passage(text, {
                book_title  = title,
                book_author = author,
                document_path = book_ctx and book_ctx.path or nil,
                highlight_pos0 = h.ann and h.ann.pos0,
                highlight_pos1 = h.ann and h.ann.pos1,
            }, function()
                if is_active() then send_next(i + 1) else finish(true) end
            end)
        end

        send_next(1)
    end

    -- ▶ Generate / Send Selected ─────────────────────────────────────────────
    table.insert(items, {
        text               = generate_action_label(generate_count),
        bold               = true,
        _anki_action_count = true,
        select_enabled     = generate_count > 0,
        callback = function()
            local to_do = selected_for_generate()
            if #to_do == 0 then
                UIManager:show(Notification:new {
                    text    = _("Nothing selected."),
                    timeout = 3,
                })
                return
            end

            guard.busy = true
            if menu_ref[1] then UIManager:close(menu_ref[1]) end
            menu_ref[1] = nil
            guard.busy = false

            local title, author = book_title_author()

            if send_mode == MODE_VOCAB then
                run_dictionary_batch(to_do, title, author)
            else
                local cfg = PoetryMemorize.config(config)
                local planned_steps = 0
                local planned_parts = {}
                for _, h in ipairs(to_do) do
                    local part = HighlightInbox.passage_text(
                        ui, h, book_ctx, 2000)
                    if part ~= "" then planned_parts[#planned_parts + 1] = part end
                    if not cfg.merge_batch then
                        planned_steps = planned_steps + #PoetryMemorize.split_units(
                            PoetryMemorize.prepare_text(part), cfg)
                    end
                end
                if cfg.merge_batch then
                    planned_steps = #PoetryMemorize.split_units(
                        PoetryMemorize.prepare_text(
                            table.concat(planned_parts, "\n")), cfg)
                end
                local large_batch = PoetryMemorize.requires_step_confirmation(
                    planned_steps, cfg)
                local summary = _("Send ") .. tostring(#to_do)
                    .. _(" highlight(s) as memorization decks.\n\n")
                if cfg.merge_batch and #to_do > 1 then
                    summary = summary
                        .. _("Merge batch: ON — selections are combined into one passage.\n\n")
                else
                    summary = summary
                        .. _("Each selection becomes step cards (+ optional full card) in Memorize::Book::location.\n")
                end
                summary = summary
                    .. _("Note type: ") .. (cfg.model or "Memorization") .. "\n\n"
                    .. _("See docs/anki-memorization.md for Anki setup.")
                if large_batch then
                    summary = _("Large memorization batch: ")
                        .. tostring(planned_steps) .. _(" steps (limit: ")
                        .. tostring(cfg.max_memorization_steps)
                        .. _("). All steps will be sent; none will be truncated.\n\n")
                        .. summary
                end

                local function start_batch(threshold_confirmed)
                    run_memorization_batch(
                        to_do, title, author, threshold_confirmed)
                end

                if cfg.auto_send and not large_batch then
                    start_batch(false)
                elseif cfg.auto_send then
                    UIManager:show(ConfirmBox:new {
                        text = summary,
                        ok_text = _("Send all steps"),
                        ok_callback = function() start_batch(true) end,
                    })
                else
                    PoetryMemorize.maybe_show_intro(function()
                        UIManager:show(ConfirmBox:new {
                            text = summary,
                            ok_text = _("Send to Anki"),
                            ok_callback = function() start_batch(true) end,
                        })
                    end)
                end
            end
        end,
    })

    local entries = {}
    for i, h in ipairs(highlights) do
        local preview = clean(h.text or "", 2000)
        if #preview > 60 then preview = preview:sub(1, 60) .. "…" end
        local chapter = (h.chapter and h.chapter ~= "") and ("  [" .. h.chapter .. "]") or ""
        table.insert(entries, {
            key   = i,
            label = preview .. chapter,
            data  = h,
        })
    end

    local list_state = { entries = entries, selected = selected, opts = nil }
    local list_opts = {
        entries  = entries,
        selected = selected,
        rebuild  = function()
            UIManager:scheduleIn(0.05, function()
                if menu_ref[1] and list_state then
                    SelectableMenu.sync_in_place(menu_ref[1], list_state)
                end
            end)
        end,
        label_fn = function(entry, sel)
            local h = entry.data
            local is_carded = (send_mode ~= MODE_MEM)
                and HighlightInbox.is_already_carded(already_carded, h, book_ctx)
            local check = is_carded and "✓ " or (sel[entry.key] and "☑ " or "☐ ")
            return check .. entry.label
        end,
        on_delete_selected = (book_ctx and book_ctx.is_current) and function(picked)
            local indices = {}
            local storage_failed = 0
            for _i, entry in ipairs(picked) do
                local deleted, reason =
                    HighlightInbox.delete_pending_for_highlight(
                        entry.data.text, book_ctx.path,
                        entry.data.ann and entry.data.ann.pos0,
                        entry.data.ann and entry.data.ann.pos1)
                if (deleted or reason == "not_found")
                    and entry.data.ann_index then
                    table.insert(indices, entry.data.ann_index)
                elseif not deleted and reason ~= "not_found" then
                    storage_failed = storage_failed + 1
                end
            end
            table.sort(indices, function(a, b) return a > b end)
            if ui.highlight and ui.highlight.deleteHighlight then
                for _i, idx in ipairs(indices) do
                    ui.highlight:deleteHighlight(idx)
                end
            end
            if storage_failed > 0 then
                UIManager:show(Notification:new {
                    text = tostring(storage_failed) .. _(
                        " highlight(s) kept because saved-card deletion failed."),
                    timeout = 6,
                })
            end
        end or nil,
        after_delete = (book_ctx and book_ctx.is_current) and hard_rebuild or nil,
        delete_selected_label = _("Delete Selected Highlights"),
        delete_selected_confirm = _("Remove selected highlight(s) from this book?\n\n")
            .. _("Saved AnkiKoFlash cards for those phrases will also be deleted."),
        action_count_fn = function()
            return #selected_for_generate()
        end,
        action_count_label_fn = generate_action_label,
    }
    list_state.opts = list_opts
    SelectableMenu.append_list(items, list_opts)

    local total_label = tostring(#highlights) .. _(" highlight(s)")
    local title_prefix = inbox_opts.title_prefix or _("Highlights to Anki")
    local menu_title = title_prefix
    if book_ctx and book_ctx.title then
        menu_title = title_prefix .. " — " .. book_ctx.title
    end
    Nav.prepend_back(items, nil, menu_ref, back_label)
    local m = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
        title      = menu_title .. "  (" .. total_label .. ")",
        item_table = items,
    }), function()
        if guard.busy then return end
        go_back()
    end)
    menu_ref[1] = m
    Nav.show(m)
end

-- Public entry point. Call with self.ui and CONFIGURATION from main.lua.
function HighlightInbox.show(ui, config, inbox_opts)
    inbox_opts = inbox_opts or {}
    local book_ctx = HighlightBooks.make_book_ctx(inbox_opts.book_path, ui)
    if not book_ctx then
        HighlightInbox.notify_empty()
        return
    end
    local highlights = build_highlights(ui, book_ctx)
    local other_books = HighlightBooks.discover_books_with_highlights(book_ctx.path, ui)

    if #highlights == 0 and #other_books == 0 then
        HighlightInbox.notify_empty()
        return
    end

    local already_carded = load_already_carded()
    local selected = default_selected(highlights, already_carded, MODE_VOCAB, book_ctx)

    show_menu(ui, config, highlights, already_carded, selected, inbox_opts, MODE_VOCAB, book_ctx)
end

return HighlightInbox
