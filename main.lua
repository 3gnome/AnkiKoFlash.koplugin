-- AnkiKoFlash — KOReader plugin.
-- Highlight text → dictionary flashcard → sync to Anki via AnkiConnect.

local Device         = require("device")
local logger         = require("logger")
local InfoMessage    = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr     = require("ui/network/manager")
local Notification   = require("ui/widget/notification")
local UIManager      = require("ui/uimanager")
local util           = require("util")
local _              = require("gettext")

local get_selection_in_context = require("selection_context")

local CardViewer       = require("card_viewer")
local CardStorage      = require("card_storage")
local AnkiSync         = require("anki_sync")
local CardManager      = require("card_manager")
local CardSync         = require("card_sync")
local CardFields       = require("card_fields")
local CardDefaults     = require("card_defaults")
local NoteTypePicker   = require("note_type_picker")
local NoteTypeProfiles = require("note_type_profiles")
local SendFlow         = require("send_flow")
local UiBusy           = require("ui_busy")
local PluginConstants  = require("plugin_constants")
local PrivacyLog       = require("privacy_log")
local ReadingLocation  = require("reading_location")
local HighlightStatus  = require("highlight_status")
local PoetryMemorize   = require("poetry_memorize")
local PluginMenu       = require("plugin_menu")
local HighlightInbox   = require("highlight_inbox")
local HighlightMenuReopen = require("highlight_menu_reopen")
local PositionUtils    = require("position_utils")

local DictionaryLookup
do
    local ok, mod = pcall(require, "dictionary_lookup")
    if ok then
        DictionaryLookup = mod
    else
        logger.warn(PluginConstants.ID, "dictionary_lookup failed to load:", mod)
    end
end

local EtymologyLookup
do
    local ok, mod = pcall(require, "etymology_lookup")
    if ok then
        EtymologyLookup = mod
    else
        logger.warn(PluginConstants.ID, "etymology_lookup failed to load:", mod)
    end
end

local MAX_HL    = 2000
local MAX_TITLE = 100
local PENDING_MIGRATION_NOTICE = nil

-- Load configuration from configuration.lua; saved anki settings (from the
-- settings UI) are merged on top at startup and at send time.
local CONFIGURATION = nil
do
    local ok, conf = pcall(require, "configuration")
    if ok then CONFIGURATION = conf end
    pcall(CardStorage.migrate_legacy_files)
    local saved_anki = CardStorage.load_anki_settings()
    if saved_anki then
        local _, migrate_msg, migrate_changed =
            CardFields.migrate_anki_settings(saved_anki)
        if migrate_changed then
            local saved_ok, save_reason =
                CardStorage.save_anki_settings(saved_anki)
            PrivacyLog.warn("settings_migration_outcome", {
                outcome = saved_ok and "applied" or "failed",
                reason = saved_ok and "none"
                    or PrivacyLog.reason_code(save_reason),
            })
        end
        if migrate_msg then
            PENDING_MIGRATION_NOTICE = migrate_msg
        end
        CONFIGURATION = CONFIGURATION or {}
        CONFIGURATION.anki = saved_anki
    end
    CONFIGURATION = CONFIGURATION or {}
    local called, migrated, migrate_reason =
        pcall(CardStorage.ensure_queue_migrated)
    if not called or not migrated then
        PrivacyLog.warn("queue_migration_outcome", {
            outcome = "failed",
            reason = called and PrivacyLog.reason_code(migrate_reason)
                or "exception",
        })
    end
    if CONFIGURATION and CONFIGURATION.anki then
        CardFields.migrate_anki_settings(CONFIGURATION.anki)
    end
end

local AnkiKoFlash = InputContainer:new {
    name        = PluginConstants.ID,
    is_doc_only = true,
}

local function is_current_highlight(hl, ui)
    return HighlightMenuReopen.is_current(hl, ui)
end

local function ui_for_highlight(hl, fallback)
    if type(hl) == "table" and type(hl.ui) == "table" then
        return hl.ui
    end
    return fallback
end

-- Strip control chars, normalise whitespace, and truncate.
local function clean_str(s, max_len)
    if not s then return "" end
    s = s:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if max_len and #s > max_len then s = s:sub(1, max_len) end
    return s
end

local function capitalize_first(s)
    if not s or s == "" then return s end
    -- Only capitalize when the headword is otherwise all-lowercase, so
    -- iPhone / eBay / iOS keep their casing.
    if s:sub(2):match("%u") then return s end
    return (s:gsub("^%l", string.upper))
end

-- Safely unwrap rhi.selected_text which may be a string, a table with a
-- .text field, or a nested structure depending on the KOReader backend.
local function extract_text(sel)
    if type(sel) == "string" then return sel end
    if type(sel) ~= "table"  then return "" end
    if type(sel.text) == "string" then return sel.text end
    -- Nested spans/lines: collect string leaves
    local parts = {}
    local function collect(t)
        for _i, v in ipairs(t) do
            if type(v) == "string" then
                parts[#parts + 1] = v
            elseif type(v) == "table" then
                if type(v.text) == "string" then parts[#parts + 1] = v.text end
                if v.spans    then collect(v.spans)    end
                if v.segments then collect(v.segments) end
                if v.lines    then collect(v.lines)    end
            end
        end
    end
    collect(sel)
    return table.concat(parts)
end

-- Read highlighted text from the live highlight module (KOReader stores it in
-- selected_text.text). Falls back to the annotation when editing an existing mark.
local function get_highlight_text(hl, index)
    local sel = hl and hl.selected_text
    local text = extract_text(sel or "")
    if text == "" and sel and sel.text then
        text = extract_text(sel.text)
    end
    local annotations = hl and hl.ui and hl.ui.annotation
        and hl.ui.annotation.annotations
    if text == "" and index and type(annotations) == "table" then
        local ann = annotations[index]
        if ann and ann.text then
            text = ann.text
        end
    end
    return util.cleanupSelectedText(text or "")
end

-- KOReader's WiFi gate can block forever in the desktop emulator (fake WiFi,
-- DNS checks that never satisfy isOnline). Run the task directly there.
local function schedule_online_task(fn)
    if Device.isEmulator or Device.isDesktop or not Device:hasWifiToggle() then
        UIManager:scheduleIn(0.05, fn)
        return
    end
    if NetworkMgr:isOnline() then
        UIManager:scheduleIn(0.05, fn)
    else
        NetworkMgr:runWhenOnline(function()
            UIManager:scheduleIn(0.05, fn)
        end)
    end
end

-- Close the highlight button dialog only (keep selection until a flow or dismiss).
local function dismiss_highlight_dialog(hl)
    if not hl then return end
    if hl.highlight_dialog then
        UIManager:close(hl.highlight_dialog)
        hl.highlight_dialog = nil
    end
end

-- Fully release text selection so the reader accepts new highlights.
local function release_highlight_for_reading(hl)
    if not hl then return end
    dismiss_highlight_dialog(hl)
    if hl.clear then
        hl:clear()
    end
    hl.selected_text = nil
    hl.hold_pos = nil
    if hl.select_mode then
        hl.select_mode = false
    end
end

-- Reopen the highlight action menu (Manage / My Cards / Generate), not the
-- edit-highlight dialog. showHighlightDialog() requires an existing annotation
-- index and crashes when index is nil (fresh text selection).
local function reopen_highlight_menu(hl, index, sel_copy, opts)
    opts = opts or {}
    opts.schedule = function(callback)
        UIManager:scheduleIn(0.05, callback)
    end
    opts.clone = util.tableDeepCopy
    HighlightMenuReopen.reopen(hl, index, sel_copy, opts)
end

-- Snapshot selection before closing the highlight dialog (onClose clears it).
local function capture_highlight_context(hl, index)
    local selected_text = type(hl) == "table" and hl.selected_text or nil
    return {
        index         = index,
        selected_text = selected_text and util.tableDeepCopy(selected_text) or nil,
        text          = get_highlight_text(hl, index),
    }
end

-- Build the effective Anki config by merging saved settings on top of
-- the config table loaded at startup.
local function get_anki_config()
    local cfg  = {}
    local base = CONFIGURATION and CONFIGURATION.anki
    if base then
        for k, v in pairs(base) do cfg[k] = v end
    end
    local fresh = CardStorage.load_anki_settings()
    if fresh then
        for k, v in pairs(fresh) do cfg[k] = v end
    end
    return cfg
end

local function apply_card_source(card, title, author, ui)
    local loc = ReadingLocation.describe(ui)
    CardFields.apply_reading_source(
        card, title, author, nil, loc)
    card.document_path = ui and ui.document and ui.document.file or nil
end

local function attach_send_callbacks(viewer, card, ui)
    local send_cb = SendFlow.viewer_callbacks(get_anki_config(), card, ui)
    viewer.can_quick_send = send_cb.can_quick_send
    viewer.on_send        = send_cb.on_send
    viewer.on_quick_send  = send_cb.on_quick_send
end

-- ── Vocabulary Card flow (KOReader dictionary only, no AI) ──────────────────

local function run_dictionary_vocabulary_flow(hl, ctx, ui, flow_opts)
    flow_opts = flow_opts or {}
    ctx = ctx or {}
    logger.info(PluginConstants.ID, "generate dictionary vocabulary card")
    local highlight_module = ui.highlight

    local title  = clean_str(ui.document:getProps().title, MAX_TITLE)
    local author = ui.document:getProps().authors
    if type(author) == "table" then
        author = table.concat(author, ", ")
    end
    author = clean_str(
        (author and author ~= "") and author or "Unknown Author",
        MAX_TITLE
    )

    local sel = ctx.selected_text
    local highlighted = ctx.text or get_highlight_text(highlight_module, ctx.index)
    local phrase      = capitalize_first(clean_str(highlighted, MAX_HL))
    if phrase == "" then
        UIManager:show(InfoMessage:new {
            text    = _("No text selected. Select words first, then choose Vocabulary Card."),
            timeout = 4,
        })
        return
    end
    local highlight_pos0 = sel and sel.pos0
    local highlight_pos1 = sel and sel.pos1
    local context     = clean_str(
        get_selection_in_context.paragraph(ui.document, highlighted),
        MAX_HL
    )

    local already_highlighted = false
    local anns = (ui.annotation and ui.annotation.annotations) or {}
    for _i, ann in ipairs(anns) do
        if ann.drawer
            and PositionUtils.equal(ann.pos0, highlight_pos0)
            and PositionUtils.equal(ann.pos1, highlight_pos1) then
            already_highlighted = true
            break
        end
    end
    -- Only persist a highlight when we actually have a selection (the
    -- highlight-dialog path always does; the single-word dictionary-popup
    -- path may not if KOReader cleared it first).
    if not already_highlighted and sel then
        if highlight_module.highlight then
            highlight_module.highlight.color = PluginConstants.HIGHLIGHT_COLOR_SAVED
        end
        highlight_module.selected_text = sel
        highlight_module:saveHighlight()
    end

    highlight_module:onClose()
    -- Selection is saved; release before lookup/send so page turns work again.
    release_highlight_for_reading(highlight_module)

    local anki_cfg = get_anki_config()
    local default_model = CardFields.default_vocabulary_model(CONFIGURATION)

    local function open_dictionary_card(chosen_model, lookup)
        local default_deck = CardDefaults.vocabulary_deck(CONFIGURATION)
        local card = {
            phrase            = capitalize_first(clean_str(lookup.word or phrase, MAX_HL)),
            definition        = lookup.definition or "",
            context           = context,
            text              = context,
            model             = chosen_model,
            target_model      = chosen_model,
            dictionary_only   = true,
            dictionary_name   = lookup.dict or "",
            card_kind         = "vocabulary",
            target_deck       = default_deck or "",
            book_title        = title,
            book_author       = author,
            highlight_pos0    = highlight_pos0,
            highlight_pos1    = highlight_pos1,
            anki_fields       = {
                Phrase     = capitalize_first(clean_str(lookup.word or phrase, MAX_HL)),
                Definition = lookup.definition or "",
                Context    = context,
            },
        }
        if EtymologyLookup then
            local ety_dict = CardDefaults.etymology_dictionary(CONFIGURATION)
            local ety, ety_status = EtymologyLookup.lookup(
                ui, lookup.word or phrase, ety_dict)
            if ety and ety ~= "" then
                card.etymology = ety
                card.anki_fields.Etymology = ety
            elseif ety_status == "not_found" and ety_dict and ety_dict ~= "" then
                UIManager:show(Notification:new {
                    text = _("No etymology entry in ") .. ety_dict
                        .. _(" for “") .. (lookup.word or phrase) .. "”",
                    timeout = 4,
                })
            end
        end
        apply_card_source(card, title, author, ui)
        CardFields.normalize(card, CONFIGURATION)
        local saved_ok = CardStorage.save_or_update(card)
        if not saved_ok then
            UIManager:show(InfoMessage:new {
                text    = _("Could not save card to device storage (disk full or read-only?)."),
                timeout = 6,
            })
        end
        HighlightStatus.mark_saved(ui, highlight_pos0, highlight_pos1)

        local viewer_ref = {}
        local lookup_word = phrase

        local function apply_lookup(c, lookup, show_back_flag)
            c.phrase = capitalize_first(clean_str(lookup.word or lookup_word, MAX_HL))
            c.definition = lookup.definition or ""
            c.dictionary_name = lookup.dict or ""
            c.anki_fields = c.anki_fields or {}
            c.anki_fields.Phrase = c.phrase
            c.anki_fields.Definition = c.definition
            CardFields.normalize(c, CONFIGURATION)
            CardStorage.save_or_update(c)
        end

        local function make_viewer(c, show_back_flag)
            local v
            v = CardViewer:new {
                card      = c,
                show_back = show_back_flag or false,

                on_show_answer = function()
                    local cur = viewer_ref[1] or v
                    UIManager:close(cur)
                    viewer_ref[1] = make_viewer(c, true)
                end,

                on_show_front = function()
                    local cur = viewer_ref[1] or v
                    UIManager:close(cur)
                    viewer_ref[1] = make_viewer(c, false)
                end,

                on_save = function()
                    CardStorage.save_or_update(c)
                    return true
                end,

                on_update = function(updated_card)
                    CardStorage.save_or_update(updated_card)
                end,

                on_change_definition = function()
                    if not DictionaryLookup then return end
                    if viewer_ref[1] then UIManager:close(viewer_ref[1]) end
                    local word = c.phrase or lookup_word
                    UiBusy.run(_("Dictionary lookup: ") .. word, function()
                        local ok, err = DictionaryLookup.pick(ui, word,
                            function(lookup)
                                apply_lookup(c, lookup, show_back_flag)
                                viewer_ref[1] = make_viewer(c, show_back_flag)
                            end, {
                                always_pick = true,
                                exclude_dictionary = CardDefaults.etymology_dictionary(CONFIGURATION),
                            })
                        if ok == nil then
                            UIManager:show(InfoMessage:new {
                                text    = _("Dictionary lookup failed: ") .. (err or "unknown"),
                                timeout = 5,
                            })
                            viewer_ref[1] = make_viewer(c, show_back_flag)
                        end
                    end)
                end,
            }
            attach_send_callbacks(v, c, ui)
            UIManager:show(v)
            return v
        end

        local function finish_vocab_send(card)
            local save_only = CardDefaults.save_only_vocabulary(CONFIGURATION)
            if CardDefaults.auto_send_vocabulary(CONFIGURATION) and not save_only then
                SendFlow.quick_send(anki_cfg, card, function(ok, _err)
                    if ok then
                        UIManager:show(Notification:new {
                            text    = _("Vocabulary card sent to Anki"),
                            timeout = 4,
                        })
                    else
                        viewer_ref[1] = make_viewer(card, false)
                    end
                end, {
                    ui = ui,
                    use_configured_deck = true,
                    -- AnkiWeb sync via AnkiConnect can block the reader for minutes.
                    skip_sync = Device:hasWifiToggle() and not Device.isEmulator,
                })
            else
                UIManager:show(Notification:new {
                    text    = save_only
                        and _("Saved locally (save-only mode).")
                        or _("Saved locally. Send from My Cards when Anki is available."),
                    timeout = 4,
                })
                viewer_ref[1] = make_viewer(card, false)
            end
        end

        finish_vocab_send(card)
    end

    local function begin_lookup(chosen_model)
        if not DictionaryLookup then
            UIManager:show(InfoMessage:new {
                text    = _("Dictionary lookup is unavailable. Restart KOReader after updating the plugin."),
                timeout = 5,
            })
            return
        end
        local pref_def = CardDefaults.vocabulary_dictionary(CONFIGURATION)
        local pick_opts = {
            preferred_dictionary = pref_def,
            exclude_dictionary = CardDefaults.etymology_dictionary(CONFIGURATION),
            -- Skip the per-card picker when a preferred definition dictionary
            -- is set (it already resolves to one definition source).
            auto_pick = CardDefaults.auto_send_vocabulary(CONFIGURATION)
                or CardDefaults.save_only_vocabulary(CONFIGURATION)
                or (pref_def and pref_def ~= ""),
            parent_fn = flow_opts.parent_fn,
        }
        UiBusy.run(_("Dictionary lookup: ") .. phrase, function()
            local ok, err = DictionaryLookup.pick(ui, phrase, function(lookup)
                open_dictionary_card(chosen_model, lookup)
            end, pick_opts)
            if ok == nil then
                UIManager:show(InfoMessage:new {
                    text    = _("Dictionary lookup failed: ") .. (err or "unknown"),
                    timeout = 5,
                })
                if flow_opts.parent_fn then flow_opts.parent_fn() end
            end
        end)
    end

    local function start_vocab_with_model(chosen_model)
        if flow_opts.prefill_lookup then
            open_dictionary_card(chosen_model, flow_opts.prefill_lookup)
        else
            begin_lookup(chosen_model)
        end
    end

    if CardDefaults.vocab_auto_flow(CONFIGURATION) then
        start_vocab_with_model(CardDefaults.vocabulary_model(CONFIGURATION))
    else
        NoteTypePicker.show(anki_cfg, function(chosen_model)
            start_vocab_with_model(chosen_model)
        end, {
            current_model = default_model,
            title         = _("Choose note type (Vocabulary Card)"),
            parent_fn     = flow_opts.parent_fn,
            profile_filter = "vocabulary",
            info_text     = _(
                "Vocabulary Card: uses KOReader dictionary only. "
                .. "Pick any note type — the word, definition, passage and source "
                .. "are mapped onto its fields by name (e.g. Front/Back also works). "
                .. "See docs/anki-vocabulary-card.md."),
            readme_id     = "vocabulary",
            fallback_models = {
                NoteTypeProfiles.VOCABULARY_CARD_MODEL,
                "Basic",
            },
        })
    end
end

local function run_memorization_flow(hl, ctx, ui, flow_opts)
    flow_opts = flow_opts or {}
    ctx = ctx or {}
    local highlight_module = ui.highlight
    local highlighted = ctx.text or get_highlight_text(highlight_module, ctx.index)
    local text = PoetryMemorize.extract_selection_text(ui, {
        text          = highlighted,
        selected_text = ctx.selected_text,
    }, MAX_HL)
    if text == "" then
        UIManager:show(InfoMessage:new {
            text    = _("Select text to memorize (sentence, stanza, or passage)."),
            timeout = 4,
        })
        return
    end

    local book_title = clean_str(ui.document:getProps().title, MAX_TITLE)
    local author = ui.document:getProps().authors
    if type(author) == "table" then
        author = table.concat(author, ", ")
    end
    author = clean_str(
        (author and author ~= "") and author or "Unknown Author",
        MAX_TITLE
    )

    PoetryMemorize.confirm_and_send(CONFIGURATION, text, ui, {
        book_title  = book_title,
        book_author = author,
        document_path = ui.document and ui.document.file or nil,
        highlight_pos0 = ctx.selected_text and ctx.selected_text.pos0,
        highlight_pos1 = ctx.selected_text and ctx.selected_text.pos1,
        on_done     = flow_opts.parent_fn,
    })
end

-- Launch the Vocabulary Card flow from KOReader's single-word dictionary
-- popup (DictQuickLookup). The long-pressed word is still held as the live
-- highlight selection (that's how the popup's own "Highlight" button works),
-- so we snapshot it before the popup tears itself down.
local function hub_menu_actions(hl, ctx, ui)
    return {
        on_vocabulary_card = function(reopen_hub_fn)
            run_dictionary_vocabulary_flow(hl, ctx, ui, {
                parent_fn = reopen_hub_fn,
            })
        end,
        on_memorization = function(reopen_hub_fn)
            release_highlight_for_reading(hl)
            run_memorization_flow(hl, ctx, ui, {
                parent_fn = reopen_hub_fn,
            })
        end,
        reopen_highlight_menu = function()
            reopen_highlight_menu(hl, ctx.index, ctx.selected_text, {
                on_unresolved = function()
                    release_highlight_for_reading(hl)
                end,
            })
        end,
        on_dismiss = function()
            release_highlight_for_reading(hl)
        end,
    }
end

local function open_hub_from_context(hl, ctx, ui)
    ui = ui_for_highlight(hl, ui)
    if type(ctx) ~= "table" or not is_current_highlight(hl, ui) then return end
    UIManager:scheduleIn(0.05, function()
        ui = ui_for_highlight(hl, ui)
        if not is_current_highlight(hl, ui) then return end
        PluginMenu.show(hl, ctx, ui, CONFIGURATION, hub_menu_actions(hl, ctx, ui))
    end)
end

local function open_highlight_inbox(hl, ctx, ui, inbox_opts)
    ui = ui_for_highlight(hl, ui)
    inbox_opts = inbox_opts or {}
    inbox_opts.title_prefix = inbox_opts.title_prefix or _("View All Highlights")
    if hl and ctx and not inbox_opts.on_back then
        inbox_opts.on_back = function()
            reopen_highlight_menu(hl, ctx.index, ctx.selected_text, {
                open_fallback = function()
                    open_hub_from_context(hl, ctx, ui)
                end,
                on_unresolved = function()
                    release_highlight_for_reading(hl)
                end,
            })
        end
        inbox_opts.back_label = inbox_opts.back_label or _("← Back to highlight menu")
    end
    HighlightInbox.show(ui, CONFIGURATION, inbox_opts)
end

local function dict_popup_context(hl, popup)
    local ctx = capture_highlight_context(hl, nil)
    if not ctx.text or ctx.text == "" then
        ctx.text = (popup and (popup.lookupword or popup.word)) or ""
    end
    return ctx
end

local function start_hub_from_dict_popup(ui, popup)
    local hl = (popup and popup.highlight) or ui.highlight
    ui = ui_for_highlight(hl, ui)
    local ctx = dict_popup_context(hl, popup)
    if popup and popup.onClose then
        popup:onClose(true)
    end
    open_hub_from_context(hl, ctx, ui)
end

local function start_vocab_from_dict_popup(ui, popup)
    local hl = (popup and popup.highlight) or ui.highlight
    ui = ui_for_highlight(hl, ui)
    local ctx = dict_popup_context(hl, popup)
    local prefill = nil
    if DictionaryLookup and DictionaryLookup.lookup_from_popup then
        prefill = DictionaryLookup.lookup_from_popup(popup, {
            preferred_dictionary = CardDefaults.vocabulary_dictionary(CONFIGURATION),
        })
    end
    -- Close the popup but keep the word selection (no_clear=true) so the card
    -- flow can promote it into a saved highlight.
    if popup and popup.onClose then
        popup:onClose(true)
    end
    UIManager:scheduleIn(0.05, function()
        if not is_current_highlight(hl, ui) then return end
        run_dictionary_vocabulary_flow(hl, ctx, ui, { prefill_lookup = prefill })
    end)
end

local function dict_popup_show(dict_popup)
    return not dict_popup.is_wiki
        and not dict_popup:isDocless()
        and dict_popup.highlight ~= nil
end

function AnkiKoFlash:init()
    if not self.ui or not self.ui.highlight then
        logger.warn(PluginConstants.ID, "highlight module not available — plugin not loaded")
        return
    end

    local HighlightCleanup = require("highlight_cleanup")
    UIManager:nextTick(function()
        HighlightCleanup.run(self.ui)
    end)

    -- ── AnkiKoFlash hub (single highlight-menu entry) ──────────────────────────
    local ok, err = pcall(function()
    self.ui.highlight:addToHighlightDialog(PluginConstants.HIGHLIGHT_DIALOG_ID_HUB, function(hl, index)
        return {
            text      = PluginConstants.NAME,
            font_bold = true,
            enabled   = true,
            callback = function()
                local ui = ui_for_highlight(hl, self.ui)
                if not is_current_highlight(hl, ui) then return end
                local ctx = capture_highlight_context(hl, index)
                dismiss_highlight_dialog(hl)
                open_hub_from_context(hl, ctx, ui)
            end,
        }
    end)

    self.ui.highlight:addToHighlightDialog(PluginConstants.HIGHLIGHT_DIALOG_ID_MEM, function(hl, index)
        return {
            text      = _("Memorize"),
            font_bold = true,
            enabled   = true,
            show_in_highlight_dialog_func = function()
                return CardDefaults.quick_highlight_button(CONFIGURATION)
            end,
            callback = function()
                local ui = ui_for_highlight(hl, self.ui)
                if not is_current_highlight(hl, ui) then return end
                local ctx = capture_highlight_context(hl, index)
                dismiss_highlight_dialog(hl)
                release_highlight_for_reading(hl)
                UIManager:scheduleIn(0.05, function()
                    if not is_current_highlight(hl, ui) then return end
                    run_memorization_flow(hl, ctx, ui, {})
                end)
            end,
        }
    end)

    self.ui.highlight:addToHighlightDialog(
        PluginConstants.HIGHLIGHT_DIALOG_ID_VIEW_ALL or "97_ankikoflash_view_all",
        function(hl, index)
        return {
            text    = _("View All Highlights"),
            font_bold = true,
            enabled = true,
            show_in_highlight_dialog_func = function()
                return true
            end,
            callback = function()
                local ui = ui_for_highlight(hl, self.ui)
                if not is_current_highlight(hl, ui) then return end
                local ctx = capture_highlight_context(hl, index)
                dismiss_highlight_dialog(hl)
                release_highlight_for_reading(hl)
                UIManager:scheduleIn(0.05, function()
                    if not is_current_highlight(hl, ui) then return end
                    open_highlight_inbox(hl, ctx, ui)
                end)
            end,
        }
    end)

    -- ── Vocabulary Card from the single-word dictionary popup ──────────────────
    -- Long-pressing a single word opens KOReader's dictionary popup
    -- (DictQuickLookup). Newer KOReader builds (master) expose
    -- ReaderDictionary:addToDictButtons; older/stable builds (e.g. v2026.03)
    -- instead broadcast a DictButtonsReady event handled by onDictButtonsReady
    -- below. We support both; they are mutually exclusive across versions.
    if self.ui.dictionary and self.ui.dictionary.addToDictButtons then
        self.ui.dictionary:addToDictButtons({
            id          = "ankikoflash_hub",
            text        = PluginConstants.NAME,
            font_bold   = true,
            conditional = true,
            show_func   = dict_popup_show,
            callback    = function(dict_popup)
                start_hub_from_dict_popup(self.ui, dict_popup)
            end,
        })
        self.ui.dictionary:addToDictButtons({
            id          = "ankikoflash_vocab",
            text        = _("Create Vocab Card"),
            font_bold   = true,
            conditional = true,
            show_func   = dict_popup_show,
            callback    = function(dict_popup)
                start_vocab_from_dict_popup(self.ui, dict_popup)
            end,
        })
    end

    -- ── Tap-to-Show Flashcard ─────────────────────────────────────────────────
    -- Short tap on a highlight with a saved card → show card viewer directly.
    -- No saved card → fall through to original highlight menu.
    local highlight_module = self.ui.highlight
    local orig_onTap = highlight_module.onTap

    highlight_module.onTap = function(hl_self, arg, ges)
        local function call_original()
            if type(orig_onTap) == "function" then
                return orig_onTap(hl_self, arg, ges)
            end
            return false
        end
        if not HighlightMenuReopen.is_current(hl_self, hl_self.ui) then
            return call_original()
        end
        -- Pass through if mid-hold or no gesture
        if hl_self.hold_pos or not ges then
            return call_original()
        end
        local visible = hl_self.view and hl_self.view.highlight
                        and hl_self.view.highlight.visible_boxes
        if type(visible) ~= "table" or #visible == 0
            or type(hl_self.view.screenToPageTransform) ~= "function" then
            return call_original()
        end
        local pos = hl_self.view:screenToPageTransform(ges.pos)
        if not pos or pos.x == nil or pos.y == nil then
            return call_original()
        end

        -- Find tapped highlight and check for a saved card
        for _i, box in ipairs(visible) do
            local r = box.rect
            if r and pos.x >= r.x and pos.y >= r.y
               and pos.x <= r.x + r.w and pos.y <= r.y + r.h then
                local annotations = hl_self.ui.annotation
                    and hl_self.ui.annotation.annotations
                local ann = type(annotations) == "table"
                    and annotations[box.index] or nil
                if ann then
                    local document_path = hl_self.ui.document
                        and hl_self.ui.document.file
                    local card
                    if type(document_path) == "string"
                        and document_path ~= "" then
                        card = CardStorage.find_for_highlight(
                            ann.text, document_path, ann.pos0, ann.pos1)
                    end
                    if card then
                        local hl_index = box.index
                        local viewer_ref = {}
                        local function make_viewer(show_back)
                            local v
                            v = CardViewer:new {
                                card      = card,
                                show_back = show_back,
                                read_only = false,
                                on_show_answer = function()
                                    local cur = viewer_ref[1] or v
                                    UIManager:close(cur)
                                    viewer_ref[1] = make_viewer(true)
                                end,
                                on_show_front = function()
                                    local cur = viewer_ref[1] or v
                                    UIManager:close(cur)
                                    viewer_ref[1] = make_viewer(false)
                                end,
                                on_save = function()
                                    CardStorage.save_or_update(card)
                                    return true
                                end,
                                on_update = function(updated_card)
                                    CardStorage.save_or_update(updated_card)
                                end,
                                on_highlight_dialog = function()
                                    if not HighlightMenuReopen.is_current(
                                            hl_self, hl_self.ui)
                                        or type(hl_self.showHighlightDialog) ~= "function" then
                                        return
                                    end
                                    local current_index =
                                        HighlightMenuReopen.resolve_annotation(
                                            hl_self, hl_index, ann)
                                    if current_index then
                                        hl_self:showHighlightDialog(current_index)
                                    end
                                end,
                            }
                            attach_send_callbacks(v, card, hl_self.ui)
                            UIManager:show(v)
                            return v
                        end
                        viewer_ref[1] = make_viewer(false)
                        return true
                    elseif ann.color == PluginConstants.HIGHLIGHT_COLOR_SENT then
                        UIManager:show(InfoMessage:new {
                            text    = _("Sent to Anki — see Recently sent"),
                            timeout = 3,
                        })
                        return true
                    end

                                    end
                break  -- only check first hit; fall through to original
            end
        end
        return call_original()
    end

    -- ── Auto-Send on WiFi ────────────────────────────────────────────────────
    -- Polls every 20 min when WiFi is on and auto_send_wifi is enabled,
    -- flushes all unsent cards to AnkiConnect silently in the background.
    local AUTO_SEND_INTERVAL = 20 * 60  -- seconds between checks (20 minutes)
    local AUTO_SEND_BACKOFF_MAX = 60 * 60 -- extra delay cap when Anki stays unreachable
    local auto_send_backoff = 0
    local function auto_send_tick()
        local wait = AUTO_SEND_INTERVAL + auto_send_backoff
        UIManager:scheduleIn(wait, auto_send_tick)
        local cfg = get_anki_config()
        if not cfg.auto_send_wifi then return end
        if not cfg.url or cfg.url == "" then return end
        if not NetworkMgr:isOnline() then return end
        if CardStorage.count_unsent() == 0 then
            auto_send_backoff = 0
            return
        end
        if CardManager.is_send_all_in_progress() then
            return
        end

        -- Silent background flush — never show Trapper/progress while reading.
        -- (UiBusy here caused random "Sending saved cards to Anki…" overlays on
        -- the Kindle when Anki was off but WiFi was on and cards were pending.)
        UIManager:scheduleIn(0, function()
            CardManager.send_all_unsent(CONFIGURATION, nil, {
                background = true,
                on_done = function(sent, failed, reconciled)
                    if (sent or 0) + (reconciled or 0) > 0 then
                        auto_send_backoff = 0
                    elseif (failed or 0) == 0 and CardStorage.count_unsent() > 0 then
                        -- Anki unreachable (precheck failed); back off, don't hammer.
                        auto_send_backoff = math.min(
                            AUTO_SEND_BACKOFF_MAX,
                            auto_send_backoff + AUTO_SEND_INTERVAL
                        )
                    end
                end,
            })
        end)
    end
    -- First check after one interval to let KOReader settle on startup.
    UIManager:scheduleIn(AUTO_SEND_INTERVAL, auto_send_tick)

    if PENDING_MIGRATION_NOTICE then
        local notice = PENDING_MIGRATION_NOTICE
        PENDING_MIGRATION_NOTICE = nil
        UIManager:scheduleIn(2, function()
            UIManager:show(Notification:new {
                text    = notice,
                timeout = 8,
            })
        end)
    end

    -- ── Auto-Sync on Startup ──────────────────────────────────────────────
    -- One-shot silent cloud sync 45s after startup.
    UIManager:scheduleIn(45, function()
        local cfg = get_anki_config()
        if cfg.sync_server and NetworkMgr:isOnline() then
            CardSync.run_sync(cfg.sync_server, true)
        end
    end)

    end)
    if not ok then
        local trace = debug.traceback(tostring(err), 2)
        logger.warn(PluginConstants.ID, "init failed:", trace)
        UIManager:show(InfoMessage:new {
            text    = _("AnkiKoFlash failed to load: ") .. tostring(err),
            timeout = 8,
        })
    end

    -- Dev-only OCR harness: no-op unless KOREADER_CAPTURE_DIR is set.
    local dev_ok, dev_capture = pcall(require, "dev-capture")
    if dev_ok and dev_capture and dev_capture.start then
        dev_capture.start()
    end

end

-- Add a "Create Vocab Card" button to the single-word dictionary popup.
-- KOReader (stable builds, e.g. v2026.03) broadcasts DictButtonsReady with the
-- popup instance and its button table (rows of button specs) for plugins to
-- modify in place. We append a new row; we must NOT return true, so other
-- plugins (e.g. vocabulary builder) can still add their own buttons.
function AnkiKoFlash:onDictButtonsReady(popup, buttons)
    if not popup or popup.is_wiki or popup.is_wiki_fullpage then return end
    if popup.highlight == nil then return end
    if type(buttons) ~= "table" then return end
    local has_hub, has_vocab = false, false
    for _i, row in ipairs(buttons) do
        if type(row) == "table" then
            for _j, btn in ipairs(row) do
                if btn.id == "ankikoflash_hub" then has_hub = true end
                if btn.id == "ankikoflash_vocab" then has_vocab = true end
            end
        end
    end
    if has_hub and has_vocab then return end
    local ui = self.ui
    table.insert(buttons, {
        {
            id        = "ankikoflash_hub",
            text      = PluginConstants.NAME,
            font_bold = true,
            callback  = function()
                start_hub_from_dict_popup(ui, popup)
            end,
        },
        {
            id        = "ankikoflash_vocab",
            text      = _("Create Vocab Card"),
            font_bold = true,
            callback  = function()
                start_vocab_from_dict_popup(ui, popup)
            end,
        },
    })
end

return AnkiKoFlash
