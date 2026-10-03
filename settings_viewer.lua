-- Settings UI for AnkiKoFlash.
-- Settings are saved to ankikoflash_settings.json in the KOReader data dir.

local ButtonDialog   = require("ui/widget/buttondialog")
local ConfirmBox     = require("ui/widget/confirmbox")
local InfoMessage    = require("ui/widget/infomessage")
local InputDialog    = require("ui/widget/inputdialog")
local Menu           = require("ui/widget/menu")
local Notification   = require("ui/widget/notification")
local UIManager      = require("ui/uimanager")
local _              = require("gettext")

local AnkiSync       = require("anki_sync")
local CardFields     = require("card_fields")
local CardStorage    = require("card_storage")
local CardSync       = require("card_sync")
local CardDefaults   = require("card_defaults")
local DeckPicker         = require("deck_picker")
local DictionaryPicker   = require("dictionary_picker")
local Nav                = require("nav")
local NoteTypeProfiles   = require("note_type_profiles")
local NoteTypePicker     = require("note_type_picker")
local PluginConstants    = require("plugin_constants")
local PoetryMemorize     = require("poetry_memorize")
local PrivacyLog         = require("privacy_log")
local SettingsPersistence = require("settings_persistence")
local UiBusy              = require("ui_busy")

local SettingsViewer = {}

function SettingsViewer.show(base_config, on_saved, viewer_opts)
    viewer_opts = viewer_opts or {}
    local settings_parent_fn = viewer_opts.parent_fn
    local viewer_ui = viewer_opts.ui
    local function show_save_failure(message)
        UIManager:show(InfoMessage:new {
            text = message or _(
                "Could not save settings. Check device storage and retry."),
            timeout = 7,
        })
    end
    -- Work on a merged copy: start with top-level config keys, then overlay
    -- the anki subtable, then saved on-device settings on top so they take
    -- priority.
    local cfg = {}
    if base_config then
        for k, v in pairs(base_config) do
            if k ~= "anki" then cfg[k] = v end
        end
        if type(base_config.anki) == "table" then
            for k, v in pairs(base_config.anki) do cfg[k] = v end
        end
    end
    local saved = CardStorage.load_anki_settings()
    if saved then
        for k, v in pairs(saved) do cfg[k] = v end
    end
    local migrated_candidate = SettingsPersistence.copy(cfg)
    local _migrated_cfg, migrate_msg, migrate_changed =
        CardFields.migrate_anki_settings(migrated_candidate)
    local migration_save_ok = true
    local migration_save_message
    if migrate_changed then
        migration_save_ok, _, migration_save_message =
            SettingsPersistence.save(migrated_candidate, "settings_migration")
        if migration_save_ok then cfg = migrated_candidate end
        PrivacyLog.warn("settings_migration_outcome", {
            outcome = migration_save_ok and "applied" or "failed",
        })
    end
    if migrate_msg then
        UIManager:scheduleIn(0.2, function()
            UIManager:show(Notification:new {
                text    = migration_save_ok and migrate_msg
                    or (_("Settings migration could not be saved. Please retry.")
                        .. "\n\n" .. (migration_save_message or "")),
                timeout = 8,
            })
        end)
    elseif migrate_changed and not migration_save_ok then
        UIManager:scheduleIn(0.2, function()
            show_save_failure(migration_save_message)
        end)
    end
    -- ── Shared helpers ───────────────────────────────────────────────────

    local function val(key)
        local v = cfg[key]
        if key == "tags" and type(v) == "table" then
            return table.concat(v, ", ")
        end
        if v == nil or v == "" then return "" end
        return tostring(v)
    end

    local function short(key, max)
        local v = val(key)
        max = max or 30
        if #v > max then return v:sub(1, max) .. ".." end
        return v ~= "" and v or "(not set)"
    end

    local function mask_key(k)
        if not k or k == "" or k:find("^YOUR_") then return "(not set)" end
        return "\xE2\x80\xA2\xE2\x80\xA2\xE2\x80\xA2\xE2\x80\xA2" .. k:sub(-1)
    end

    local function persist_update(mutator, operation)
        local changed = false
        local ok, candidate, reason, message = SettingsPersistence.transaction(
            cfg, function(next_cfg)
                mutator(next_cfg)
                local _, _, migrated = CardFields.migrate_anki_settings(next_cfg)
                changed = migrated == true
            end, operation or "settings_viewer")
        if not ok then
            show_save_failure(message)
            if changed then
                PrivacyLog.warn("settings_migration_outcome", {
                    outcome = "failed",
                })
            end
            return false, reason
        end
        cfg = candidate
        if changed then
            PrivacyLog.warn("settings_migration_outcome", {
                outcome = "applied",
            })
        end
        if on_saved then on_saved(cfg) end
        return true
    end

    local function current_book_title()
        local ui = viewer_opts.ui
        if ui and ui.document then
            local title = (ui.document:getProps().title or ""):match("^%s*(.-)%s*$") or ""
            if #title > 100 then title = title:sub(1, 100) end
            if title ~= "" then return title end
        end
        return ""
    end

    local map_book_to_deck

    -- Forward declarations for submenu functions.
    local show_main
    local show_sync
    local show_memorization, show_defaults
    local show_defaults_vocab, show_defaults_mem
    local show_where_cards_go, show_deck_picker_shortcuts, show_book_overrides
    local show_favorite_decks
    local show_anki_connection, show_tags

    local CHECK_ON = "\xe2\x9c\x93 "

    local function toggle_label(on, label)
        if on then return CHECK_ON .. label .. ": ON" end
        return label .. ": OFF"
    end

    local SETTINGS_HELP_SUBTITLE = _("Tap gray rows for help.")

    local function show_settings_help(text)
        UIManager:show(InfoMessage:new {
            text    = text,
            timeout = 8,
        })
    end

    local function info_menu_item(label, help_text)
        return {
            text     = label,
            dim      = true,
            callback = function() show_settings_help(help_text) end,
        }
    end

    local function open_settings_menu(title, item_table, on_close, subtitle)
        local menu_instance
        menu_instance = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
            title      = title,
            subtitle   = subtitle or SETTINGS_HELP_SUBTITLE,
            item_table = item_table,
        }), function()
            Nav.after_close(function()
                if menu_instance then UIManager:close(menu_instance) end
            end, on_close or function() end)
        end)
        Nav.show(menu_instance)
        return menu_instance
    end

    local function close_menu_then(menu_instance, fn)
        Nav.after_close(function()
            if menu_instance then UIManager:close(menu_instance) end
        end, fn)
    end

    local memorization_parent_fn = function() show_main() end

    -- Helper: show an InputDialog for editing a text field.
    local function edit_field(title, key, hint, parent_fn, transform)
        local edit_dlg
        edit_dlg = InputDialog:new {
            title      = _(title),
            input      = val(key),
            input_hint = hint,
            buttons    = {{
                {
                    text     = _("Cancel"),
                    callback = function()
                        UIManager:close(edit_dlg)
                        parent_fn()
                    end,
                },
                {
                    text             = _("Save"),
                    is_enter_default = true,
                    callback         = function()
                        local new_val = edit_dlg:getInputText() or ""
                        UIManager:close(edit_dlg)
                        persist_update(function(candidate)
                            if transform then
                                transform(new_val, candidate)
                            else
                                candidate[key] = new_val
                            end
                        end)
                        parent_fn()
                    end,
                },
            }},
        }
        UIManager:show(edit_dlg)
        edit_dlg:onShowKeyboard()
    end

    -- ── Deck routing (Vocabulary) ──────────────────────────────────────

    local function resolved_deck_for(card)
        local base = AnkiSync.resolve_base_deck(cfg, card)
        return AnkiSync.resolve_deck_name(cfg, card, base)
    end

    local function routing_preview_lines()
        local book = current_book_title()
        local vocab_card = {
            book_title = book,
            model      = CardDefaults.vocabulary_model({ anki = cfg }),
        }
        local lines = {}
        if book == "" then
            table.insert(lines, _("No book open — preview uses defaults only"))
        else
            table.insert(lines, _("Book: ") .. book)
        end
        table.insert(lines, _("Vocab → ") .. (resolved_deck_for(vocab_card) or ""))
        return lines
    end

    local function routing_help_book()
        local book = current_book_title()
        if book == "" then
            return _(
                "No book is open. Open a book to preview subdeck routing. Book overrides match each card's book_title field exactly."
            )
        end
        return _(
            "This title comes from the open book's metadata. Book overrides must match this string exactly. It is also used when Append book title to deck name is ON.\n\nCurrent title: "
        ) .. book
    end

    local function routing_help_for_card(card, defaults_label)
        local resolved = resolved_deck_for(card) or ""
        local subdeck_on = cfg.subdeck_by_book ~= false
        local step3 = subdeck_on
            and _("If Append book title is ON, adds ::Book Title to the parent deck segment.")
            or _("Append book title is OFF — no subdeck suffix is added.")
        return defaults_label .. _(" deck resolution:") .. "\n"
            .. _("1. Default deck (Card defaults → ") .. defaults_label .. ")\n"
            .. _("2. Book override for this title, if set\n")
            .. "3. " .. step3 .. "\n\n"
            .. _("Current result: ") .. resolved
    end

    map_book_to_deck = function(book, parent_fn)
        book = (book or ""):match("^%s*(.-)%s*$") or ""
        if book == "" then
            parent_fn()
            return
        end
        local existing = (cfg.per_book_decks and cfg.per_book_decks[book])
            or CardDefaults.vocabulary_deck({ anki = cfg })
            or ""
        local sample_card = { book_title = book }
        DeckPicker.show(cfg, sample_card, function(chosen)
            if persist_update(function(candidate)
                candidate.per_book_decks = candidate.per_book_decks or {}
                candidate.per_book_decks[book] = chosen
            end) then
                UIManager:show(Notification:new {
                    text    = book .. _(" → ") .. chosen,
                    timeout = 3,
                })
            end
            parent_fn()
        end, {
            title        = _("Deck for cards from this book"),
            current_deck = existing,
            parent_fn    = parent_fn,
        })
    end

    show_book_overrides = function()
        local parent_fn = show_where_cards_go
        local menu_instance

        local function reopen()
            show_book_overrides()
        end

        local item_table = {}
        local books = {}
        if type(cfg.per_book_decks) == "table" then
            for book, deck in pairs(cfg.per_book_decks) do
                if book and book ~= "" then
                    books[#books + 1] = { book = book, deck = deck or "" }
                end
            end
        end
        table.sort(books, function(a, b) return a.book < b.book end)

        local cur_book = current_book_title()
        if cur_book ~= "" then
            item_table[#item_table + 1] = {
                text = _("Add override for «") .. cur_book .. "»…",
                callback = function()
                    UIManager:close(menu_instance)
                    map_book_to_deck(cur_book, show_book_overrides)
                end,
            }
        end

        for _i, entry in ipairs(books) do
            local book = entry.book
            local deck = entry.deck
            item_table[#item_table + 1] = {
                text = book .. " → " .. (deck ~= "" and deck or _("(not set)")),
                callback = function()
                    UIManager:close(menu_instance)
                    local action_dlg
                    action_dlg = ButtonDialog:new {
                        title   = book,
                        buttons = {
                            {{ text = _("Change deck…"),
                               callback = function()
                                   UIManager:close(action_dlg)
                                   map_book_to_deck(book, show_book_overrides)
                               end }},
                            {{ text = _("Remove override"),
                               callback = function()
                                   UIManager:close(action_dlg)
                                   UIManager:show(ConfirmBox:new {
                                       text = _("Remove deck override for this book?"),
                                       ok_callback = function()
                                           persist_update(function(candidate)
                                               if candidate.per_book_decks then
                                                   candidate.per_book_decks[book] = nil
                                               end
                                           end)
                                           reopen()
                                       end,
                                       cancel_callback = function() reopen() end,
                                   })
                               end }},
                            {{ text = _("Back"),
                               callback = function()
                                   UIManager:close(action_dlg)
                                   reopen()
                               end }},
                        },
                    }
                    UIManager:show(action_dlg)
                end,
            }
        end

        if #books == 0 and cur_book == "" then
            item_table[#item_table + 1] = {
                text = _("No book overrides saved"),
                callback = function() reopen() end,
            }
        end

        item_table[#item_table + 1] = {
            text = _("Add by book title…"),
            callback = function()
                UIManager:close(menu_instance)
                edit_field("Book title", "_map_book_title", "Book title", show_book_overrides)
            end,
        }

        item_table[#item_table + 1] = {
            text = _("← Back"),
            callback = function()
                Nav.after_close(function()
                    if menu_instance then UIManager:close(menu_instance) end
                end, parent_fn)
            end,
        }

        menu_instance = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
            title    = _("Book overrides"),
            subtitle = _("Replaces Vocabulary default for matching book titles"),
            item_table = item_table,
        }), function()
            Nav.after_close(function()
                if menu_instance then UIManager:close(menu_instance) end
            end, parent_fn)
        end)
        Nav.show(menu_instance)
    end

    show_favorite_decks = function()
        local menu_instance
        cfg.favorite_decks = cfg.favorite_decks or {}
        local item_table = {}

        for _i, deck in ipairs(cfg.favorite_decks) do
            local deck_name = deck
            item_table[#item_table + 1] = {
                text = "★ " .. deck_name,
                callback = function()
                    UIManager:close(menu_instance)
                    UIManager:show(ConfirmBox:new {
                        text = _("Remove from favorites?") .. "\n" .. deck_name,
                        ok_callback = function()
                            persist_update(function(candidate)
                                candidate.favorite_decks =
                                    candidate.favorite_decks or {}
                                for i, v in ipairs(candidate.favorite_decks) do
                                    if v == deck_name then
                                        table.remove(candidate.favorite_decks, i)
                                        break
                                    end
                                end
                            end)
                            show_favorite_decks()
                        end,
                        cancel_callback = function() show_favorite_decks() end,
                    })
                end,
            }
        end

        if #cfg.favorite_decks == 0 then
            item_table[#item_table + 1] = {
                text = _("No favorite decks"),
                callback = function() show_favorite_decks() end,
            }
        end

        item_table[#item_table + 1] = {
            text = _("Add favorite deck…"),
            callback = function()
                UIManager:close(menu_instance)
                DeckPicker.show(cfg, nil, function(chosen)
                    local found = false
                    for _j, v in ipairs(cfg.favorite_decks) do
                        if v == chosen then found = true; break end
                    end
                    if not found then
                        persist_update(function(candidate)
                            candidate.favorite_decks = candidate.favorite_decks or {}
                            candidate.favorite_decks[
                                #candidate.favorite_decks + 1] = chosen
                        end)
                    end
                    show_favorite_decks()
                end, {
                    title     = _("Add favorite deck"),
                    parent_fn = show_favorite_decks,
                })
            end,
        }

        item_table[#item_table + 1] = {
            text = _("← Back"),
            callback = function()
                Nav.after_close(function()
                    if menu_instance then UIManager:close(menu_instance) end
                end, show_deck_picker_shortcuts)
            end,
        }

        menu_instance = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
            title    = _("Favorite decks"),
            subtitle = _("At top of deck picker; does not change automatic routing"),
            item_table = item_table,
        }), function()
            Nav.after_close(function()
                if menu_instance then UIManager:close(menu_instance) end
            end, show_deck_picker_shortcuts)
        end)
        Nav.show(menu_instance)
    end

    show_deck_picker_shortcuts = function()
        local menu_instance
        local fav_count = 0
        if type(cfg.favorite_decks) == "table" then
            fav_count = #cfg.favorite_decks
        end
        local recent_str = _("(none)")
        if type(cfg.recent_decks) == "table" and #cfg.recent_decks > 0 then
            recent_str = table.concat(cfg.recent_decks, ", ")
            if #recent_str > 55 then
                recent_str = recent_str:sub(1, 52) .. "…"
            end
        end

        local item_table = {
            info_menu_item(_("About deck picker shortcuts"), _(
                "Favorite decks and recent decks appear at the top when you manually choose a deck at send time.\n\nThey do not change automatic routing, one-tap send, or Where cards go settings."
            )),
            info_menu_item(_("Recent: ") .. recent_str, _(
                "The last 5 decks you picked manually appear first in the deck picker. They are saved automatically when you send from the card viewer and cannot be edited here."
            )),
            {
                text = _("Favorite decks…") .. " (" .. tostring(fav_count) .. ")",
                callback = function()
                    close_menu_then(menu_instance, show_favorite_decks)
                end,
            },
            {
                text = _("← Back"),
                callback = function() close_menu_then(menu_instance, show_defaults) end,
            },
        }

        menu_instance = open_settings_menu(_("Deck picker shortcuts"), item_table, show_defaults)
    end

    show_where_cards_go = function()
        local menu_instance
        local subdeck_on = cfg.subdeck_by_book ~= false
        local book = current_book_title()
        local vocab_card = {
            book_title = book,
            model      = CardDefaults.vocabulary_model({ anki = cfg }),
        }
        local preview = routing_preview_lines()

        local item_table = {
            info_menu_item(preview[1], routing_help_book()),
            info_menu_item(preview[2], routing_help_for_card(vocab_card, _("Vocabulary Card"))),
            info_menu_item(_("Vocabulary only"), _(
                "Memorization cards use Card defaults → Memorization Card. These routing rules do not apply to them."
            )),
            {
                text = toggle_label(subdeck_on, _("Append book title to deck name")),
                callback = function()
                    persist_update(function(candidate)
                        candidate.subdeck_by_book = not subdeck_on
                    end)
                    Nav.after_close(function()
                        if menu_instance then UIManager:close(menu_instance) end
                    end, show_where_cards_go)
                end,
            },
            {
                text = _("Book overrides…"),
                callback = function()
                    close_menu_then(menu_instance, show_book_overrides)
                end,
            },
            {
                text = _("← Back"),
                callback = function() close_menu_then(menu_instance, show_defaults) end,
            },
        }

        menu_instance = open_settings_menu(_("Where cards go"), item_table, show_defaults)
    end

    -- hook per-book deck save via transform on _map_book_title - use edit_field wrapper
    local orig_edit_field = edit_field
    edit_field = function(title, key, hint, parent_fn, transform)
        if key == "_map_book_title" then
            local edit_dlg
            edit_dlg = InputDialog:new {
                title = title, input = "", input_hint = hint,
                buttons = {{
                    { text = _("Cancel"), callback = function()
                        UIManager:close(edit_dlg); parent_fn()
                    end },
                    { text = _("Next"), callback = function()
                        local book = edit_dlg:getInputText() or ""
                        UIManager:close(edit_dlg)
                        if book == "" then parent_fn(); return end
                        map_book_to_deck(book, parent_fn)
                    end },
                }},
            }
            UIManager:show(edit_dlg)
            edit_dlg:onShowKeyboard()
            return
        end
        orig_edit_field(title, key, hint, parent_fn, transform)
    end

    -- ── Submenu: Memorization ────────────────────────────────────────────

    local MEMORIZATION_DEFAULTS = {
        memorize_context_lines             = 3,
        memorize_context_cumulative        = false,
        memorize_max_words                 = 7,
        max_memorization_steps             = 80,
        memorize_include_full_recitation   = true,
        memorize_force_verse_lines         = false,
        memorize_show_split_preview        = false,
        memorize_replace_duplicates        = false,
        memorize_merge_batch               = false,
        memorize_auto_save_on_fail         = false,
    }

    local memorization_draft = nil

    local function memorization_snapshot_from_cfg()
        return {
            memorize_context_lines = tonumber(cfg.memorize_context_lines)
                or MEMORIZATION_DEFAULTS.memorize_context_lines,
            memorize_context_cumulative = cfg.memorize_context_cumulative == true,
            memorize_max_words = tonumber(cfg.memorize_max_words)
                or MEMORIZATION_DEFAULTS.memorize_max_words,
            max_memorization_steps = tonumber(cfg.max_memorization_steps)
                or MEMORIZATION_DEFAULTS.max_memorization_steps,
            memorize_include_full_recitation = cfg.memorize_include_full_recitation ~= false,
            memorize_force_verse_lines = cfg.memorize_force_verse_lines == true,
            memorize_show_split_preview = cfg.memorize_show_split_preview == true,
            memorize_replace_duplicates = cfg.memorize_replace_duplicates == true,
            memorize_merge_batch = cfg.memorize_merge_batch == true,
            memorize_auto_save_on_fail = cfg.memorize_auto_save_on_fail == true,
        }
    end

    local function memorization_drafts_equal(a, b)
        if not a or not b then return false end
        return a.memorize_context_lines == b.memorize_context_lines
            and a.memorize_context_cumulative == b.memorize_context_cumulative
            and a.memorize_max_words == b.memorize_max_words
            and a.max_memorization_steps == b.max_memorization_steps
            and a.memorize_include_full_recitation == b.memorize_include_full_recitation
            and a.memorize_force_verse_lines == b.memorize_force_verse_lines
            and a.memorize_show_split_preview == b.memorize_show_split_preview
            and a.memorize_replace_duplicates == b.memorize_replace_duplicates
            and a.memorize_merge_batch == b.memorize_merge_batch
            and a.memorize_auto_save_on_fail == b.memorize_auto_save_on_fail
    end

    local function apply_memorization_draft(target, draft)
        target.memorize_context_lines = draft.memorize_context_lines
        target.memorize_context_cumulative = draft.memorize_context_cumulative
        target.memorize_max_words = draft.memorize_max_words
        target.max_memorization_steps = draft.max_memorization_steps
        target.memorize_include_full_recitation = draft.memorize_include_full_recitation
        target.memorize_force_verse_lines = draft.memorize_force_verse_lines
        target.memorize_show_split_preview = draft.memorize_show_split_preview
        target.memorize_replace_duplicates = draft.memorize_replace_duplicates
        target.memorize_merge_batch = draft.memorize_merge_batch
        target.memorize_auto_save_on_fail = draft.memorize_auto_save_on_fail
    end

    show_memorization = function()
        if not memorization_draft then
            memorization_draft = memorization_snapshot_from_cfg()
        end
        local draft = memorization_draft
        local saved_snapshot = memorization_snapshot_from_cfg()

        local ctx = draft.memorize_context_lines
        local maxw = draft.memorize_max_words
        local max_steps = draft.max_memorization_steps
        local full_on = draft.memorize_include_full_recitation
        local cum_on = draft.memorize_context_cumulative
        local verse_on = draft.memorize_force_verse_lines
        local preview_on = draft.memorize_show_split_preview
        local replace_on = draft.memorize_replace_duplicates
        local merge_on = draft.memorize_merge_batch
        local auto_save_on = draft.memorize_auto_save_on_fail

        local sub_dlg

        local function reopen_memorization()
            Nav.after_close(function() UIManager:close(sub_dlg) end, show_memorization)
        end

        local function discard_and_close()
            memorization_draft = nil
            UIManager:close(sub_dlg)
            memorization_parent_fn()
        end

        local function close_without_saving()
            if memorization_drafts_equal(draft, saved_snapshot) then
                discard_and_close()
                return
            end
            UIManager:show(ConfirmBox:new {
                text = _("Discard memorization changes?"),
                ok_text = _("Discard"),
                ok_callback = discard_and_close,
                cancel_text = _("Keep editing"),
            })
        end

        local function save_and_close()
            if not persist_update(function(candidate)
                apply_memorization_draft(candidate, draft)
            end) then return end
            memorization_draft = nil
            UIManager:close(sub_dlg)
            memorization_parent_fn()
        end

        local function cycle_number(key, cur, options)
            local idx = 1
            for i, n in ipairs(options) do
                if n == cur then idx = i; break end
            end
            draft[key] = options[(idx % #options) + 1]
            reopen_memorization()
        end

        local function toggle_bool(key)
            draft[key] = not draft[key]
            reopen_memorization()
        end

        sub_dlg = ButtonDialog:new {
            title   = _("Memorization options"),
            buttons = {
                {{ text = _("Context lines: ") .. tostring(ctx),
                   callback = function()
                       cycle_number("memorize_context_lines", ctx,
                           PoetryMemorize.CONTEXT_LINE_OPTIONS)
                   end }},
                {{ text = cum_on and _("Cumulative context: ON")
                                  or _("Cumulative context: OFF"),
                   callback = function()
                       toggle_bool("memorize_context_cumulative")
                   end }},
                {{ text = _("Max words per chunk: ") .. tostring(maxw),
                   callback = function()
                       cycle_number("memorize_max_words", maxw, { 4, 5, 6, 7, 8, 9, 10, 12 })
                   end }},
                {{ text = _("Confirm above steps: ") .. tostring(max_steps),
                   callback = function()
                       cycle_number("max_memorization_steps", max_steps,
                           { 40, 60, 80, 100, 120, 160, 200 })
                   end }},
                {{ text = full_on and _("Full recitation card: ON")
                                  or _("Full recitation card: OFF"),
                   callback = function()
                       toggle_bool("memorize_include_full_recitation")
                   end }},
                {{ text = verse_on and _("Force verse line split: ON")
                                   or _("Force verse line split: OFF"),
                   callback = function()
                       toggle_bool("memorize_force_verse_lines")
                   end }},
                {{ text = preview_on and _("Show step preview on send: ON")
                                    or _("Show step preview on send: OFF"),
                   callback = function()
                       toggle_bool("memorize_show_split_preview")
                   end }},
                {{ text = replace_on and _("Replace existing cards: ON")
                                    or _("Replace existing cards: OFF"),
                   callback = function()
                       toggle_bool("memorize_replace_duplicates")
                   end }},
                {{ text = merge_on and _("Merge batch highlights: ON")
                                  or _("Merge batch highlights: OFF"),
                   callback = function()
                       toggle_bool("memorize_merge_batch")
                   end }},
                {{ text = auto_save_on and _("Auto-save if send fails: ON")
                                     or _("Auto-save if send fails: OFF"),
                   callback = function()
                       toggle_bool("memorize_auto_save_on_fail")
                   end }},
                {{ text = _("Restore defaults"),
                   callback = function()
                       for k, v in pairs(MEMORIZATION_DEFAULTS) do
                           draft[k] = v
                       end
                       reopen_memorization()
                   end }},
                {{ text = _("Save"),
                   callback = save_and_close }},
                {{ text = _("Cancel"),
                   callback = close_without_saving }},
            },
        }

        function sub_dlg:onClose()
            if memorization_drafts_equal(draft, saved_snapshot) then
                discard_and_close()
                return true
            end
            UIManager:show(ConfirmBox:new {
                text = _("Discard memorization changes?"),
                ok_text = _("Discard"),
                ok_callback = discard_and_close,
                cancel_text = _("Keep editing"),
            })
            return true
        end

        UIManager:show(sub_dlg)
    end

    -- ── Submenu: Card defaults ───────────────────────────────────────────

    show_defaults_vocab = function()
        local sub_dlg
        local vocab_as = cfg.auto_send_vocabulary == true
        local pref_dict = (cfg.vocabulary_preferred_dictionary and cfg.vocabulary_preferred_dictionary ~= "")
            and cfg.vocabulary_preferred_dictionary or _("(auto)")
        local ety_dict = (cfg.etymology_preferred_dictionary and cfg.etymology_preferred_dictionary ~= "")
            and cfg.etymology_preferred_dictionary or _("(auto)")

        local function reopen()
            Nav.after_close(function() UIManager:close(sub_dlg) end, show_defaults_vocab)
        end

        -- Prefer a picker of installed StarDicts; fall back to free-text entry
        -- when KOReader's dictionary list is unavailable.
        local function pick_dictionary(key, current, title, hint)
            local shown = false
            if viewer_ui then
                shown = DictionaryPicker.show(viewer_ui, current, function(name)
                    persist_update(function(candidate)
                        candidate[key] = name
                    end)
                    show_defaults_vocab()
                end, {
                    title     = title,
                    hint      = hint,
                    parent_fn = show_defaults_vocab,
                })
            end
            if not shown then
                edit_field(title, key, hint, show_defaults_vocab)
            end
        end

        sub_dlg = ButtonDialog:new {
            title   = _("Vocabulary Card defaults"),
            buttons = {
                {{ text = _("Note type: ") .. short("vocabulary_model", 18),
                   callback = function()
                       UIManager:close(sub_dlg)
                       NoteTypePicker.show(cfg, function(chosen)
                           persist_update(function(candidate)
                               candidate.vocabulary_model = chosen
                           end)
                           show_defaults_vocab()
                       end, {
                           title         = _("Vocabulary Card note type"),
                           current_model = cfg.vocabulary_model or NoteTypeProfiles.VOCABULARY_CARD_MODEL,
                           parent_fn     = show_defaults_vocab,
                           profile_filter = "vocabulary",
                           readme_id     = "vocabulary",
                           fallback_models = {
                               NoteTypeProfiles.VOCABULARY_CARD_MODEL,
                               "Basic",
                           },
                       })
                   end }},
                {{ text = _("Default deck: ") .. short("vocabulary_deck", 18),
                   callback = function()
                       UIManager:close(sub_dlg)
                       DeckPicker.show(cfg, nil, function(chosen)
                           persist_update(function(candidate)
                               candidate.vocabulary_deck = chosen
                           end)
                           show_defaults_vocab()
                       end, {
                           title        = _("Vocabulary Card default deck"),
                           current_deck = CardDefaults.vocabulary_deck({ anki = cfg }),
                           parent_fn    = show_defaults_vocab,
                       })
                   end }},
                {{ text = _("Preferred dictionary: ") .. (type(pref_dict) == "string" and (
                       #pref_dict > 20 and pref_dict:sub(1, 20) .. ".." or pref_dict) or pref_dict),
                   callback = function()
                       UIManager:close(sub_dlg)
                       pick_dictionary("vocabulary_preferred_dictionary",
                           (cfg.vocabulary_preferred_dictionary or ""),
                           _("Preferred dictionary"),
                           _("StarDict name, or leave empty"))
                   end }},
                {{ text = _("Etymology dictionary: ") .. (type(ety_dict) == "string" and (
                       #ety_dict > 20 and ety_dict:sub(1, 20) .. ".." or ety_dict) or ety_dict),
                   callback = function()
                       UIManager:close(sub_dlg)
                       pick_dictionary("etymology_preferred_dictionary",
                           (cfg.etymology_preferred_dictionary or ""),
                           _("Etymology dictionary"),
                           _("StarDict name (e.g. Etymology (Wiktionary)), or leave empty"))
                   end }},
                {{ text = _("Hub menu label: ") .. (function()
                       local lbl = CardDefaults.vocabulary_hub_label({ anki = cfg })
                       if #lbl > 22 then return lbl:sub(1, 22) .. ".." end
                       return lbl
                   end)(),
                   callback = function()
                       UIManager:close(sub_dlg)
                       edit_field("Hub menu label", "vocabulary_card_hub_label",
                           PluginConstants.VOCABULARY_CARD_LABEL, show_defaults_vocab,
                           function(new_val, candidate)
                               local trimmed = (new_val or ""):match("^%s*(.-)%s*$") or ""
                               candidate.vocabulary_card_hub_label =
                                   trimmed ~= "" and trimmed or nil
                           end)
                   end }},
                {{ text = toggle_label(vocab_as, _("One-tap send (Vocabulary)")),
                   callback = function()
                       persist_update(function(candidate)
                           candidate.auto_send_vocabulary = not vocab_as
                       end)
                       reopen()
                   end }},
                {{ text = _("Back"),
                   callback = function() UIManager:close(sub_dlg); show_defaults() end }},
            },
        }
        UIManager:show(sub_dlg)
    end

    show_defaults_mem = function()
        local sub_dlg
        local mem_as = cfg.auto_send_memorization == true
        local quick_btn = cfg.memorize_quick_highlight_button == true
        local skip_hub = cfg.auto_send_skip_hub_submenu == true
            or cfg.memorize_skip_hub_submenu == true

        local function reopen()
            Nav.after_close(function() UIManager:close(sub_dlg) end, show_defaults_mem)
        end

        sub_dlg = ButtonDialog:new {
            title   = _("Memorization Card defaults"),
            buttons = {
                {{ text = _("Note type: ") .. short("memorize_model", 18),
                   callback = function()
                       UIManager:close(sub_dlg)
                       NoteTypePicker.show(cfg, function(chosen)
                           persist_update(function(candidate)
                               candidate.memorize_model = chosen
                           end)
                           show_defaults_mem()
                       end, {
                           title         = _("Memorization note type"),
                           current_model = cfg.memorize_model or NoteTypeProfiles.MEMORIZATION_MODEL,
                           parent_fn     = show_defaults_mem,
                           profile_filter = "memorization",
                           readme_id     = "memorization",
                           fallback_models = {
                               NoteTypeProfiles.MEMORIZATION_MODEL,
                           },
                       })
                   end }},
                {{ text = _("Parent deck: ") .. short("memorize_parent_deck", 18),
                   callback = function()
                       UIManager:close(sub_dlg)
                       DeckPicker.show(cfg, nil, function(chosen)
                           persist_update(function(candidate)
                               candidate.memorize_parent_deck = chosen
                           end)
                           show_defaults_mem()
                       end, {
                           title        = _("Memorization Card parent deck"),
                           current_deck = CardDefaults.memorization_parent_deck({ anki = cfg }),
                           parent_fn    = show_defaults_mem,
                       })
                   end }},
                {{ text = toggle_label(mem_as, _("One-tap send (Memorization)")),
                   callback = function()
                       persist_update(function(candidate)
                           candidate.auto_send_memorization = not mem_as
                       end)
                       reopen()
                   end }},
                {{ text = toggle_label(quick_btn, _("Quick highlight button")),
                   callback = function()
                       persist_update(function(candidate)
                           candidate.memorize_quick_highlight_button = not quick_btn
                       end)
                       reopen()
                   end }},
                {{ text = toggle_label(skip_hub, _("Skip hub submenu when auto-send")),
                   callback = function()
                       local new_val = not skip_hub
                       persist_update(function(candidate)
                           candidate.auto_send_skip_hub_submenu = new_val
                           candidate.memorize_skip_hub_submenu = new_val
                       end)
                       reopen()
                   end }},
                {{ text = _("Back"),
                   callback = function() UIManager:close(sub_dlg); show_defaults() end }},
            },
        }
        UIManager:show(sub_dlg)
    end

    show_defaults = function()
        local sub_dlg
        sub_dlg = ButtonDialog:new {
            title   = _("Card defaults"),
            buttons = {
                {{ text = _("Vocabulary Card…"),
                   callback = function()
                       UIManager:close(sub_dlg)
                       show_defaults_vocab()
                   end }},
                {{ text = _("Memorization Card…"),
                   callback = function()
                       UIManager:close(sub_dlg)
                       show_defaults_mem()
                   end }},
                {{ text = _("Where cards go…"),
                   callback = function()
                       UIManager:close(sub_dlg)
                       show_where_cards_go()
                   end }},
                {{ text = _("Deck picker shortcuts…"),
                   callback = function()
                       UIManager:close(sub_dlg)
                       show_deck_picker_shortcuts()
                   end }},
                {{ text = _("Back"),
                   callback = function() UIManager:close(sub_dlg); show_main() end }},
            },
        }
        UIManager:show(sub_dlg)
    end

    -- ── Submenu: Anki connection & Tags ──────────────────────────────────

    show_anki_connection = function()
        local sub_dlg
        local sync_after_on = cfg.sync_after_send ~= false

        sub_dlg = ButtonDialog:new {
            title   = _("Anki connection"),
            buttons = {
                {{ text = _("AnkiConnect URL: ") .. short("url", 28),
                   callback = function()
                       UIManager:close(sub_dlg)
                       edit_field("AnkiConnect URL", "url",
                           "http://192.168.1.100:8765", show_anki_connection)
                   end }},
                {{ text = toggle_label(sync_after_on, _("Sync to AnkiWeb after send")),
                   callback = function()
                       persist_update(function(candidate)
                           candidate.sync_after_send = not sync_after_on
                       end)
                       UIManager:close(sub_dlg)
                       show_anki_connection()
                   end }},
                {{ text = _("Test Connection"),
                   callback = function()
                       local url = cfg.url
                       if not url or url == "" then
                           UIManager:show(Notification:new {
                               text = _("Set the AnkiConnect URL first"), timeout = 3,
                           })
                           return
                       end
                       UiBusy.run(_("Testing connection…"), function()
                           local conn_ok, conn_err = AnkiSync.test_connection(url)
                           UIManager:show(Notification:new {
                               text = conn_ok and _("Connection OK")
                                         or (conn_err or _(
                                             "Cannot reach Anki. Check URL and that Anki is running.")),
                               timeout = conn_ok and 3 or 5,
                           })
                       end)
                   end }},
                {{ text = _("Back"),
                   callback = function() UIManager:close(sub_dlg); show_main() end }},
            },
        }
        UIManager:show(sub_dlg)
    end

    show_tags = function()
        local menu_instance
        local tags_on = cfg.tags_enabled ~= false
        local tag_list_str = short("tags")

        local item_table = {
            info_menu_item(_("About tags"), tags_on
                and _(
                    "Tags on new cards is ON. The tag list below is applied to every card sent via AnkiConnect.\n\nEdit as comma-separated names. Default is KOReader if the list is empty."
                )
                or _(
                    "Tags on new cards is OFF. No tags are sent to Anki, even if a tag list is configured.\n\nTurn ON to apply the tag list on send."
                )),
            {
                text = toggle_label(tags_on, _("Tags on new cards")),
                callback = function()
                    persist_update(function(candidate)
                        candidate.tags_enabled = not tags_on
                    end)
                    Nav.after_close(function()
                        if menu_instance then UIManager:close(menu_instance) end
                    end, show_tags)
                end,
            },
            {
                text = _("Tag list: ") .. tag_list_str,
                callback = function()
                    close_menu_then(menu_instance, function()
                        edit_field("Tags (comma-sep)", "tags", "KOReader",
                            show_tags, function(new_val, candidate)
                                local tag_list = {}
                                for t in new_val:gmatch("[^,]+") do
                                    local trimmed = t:match("^%s*(.-)%s*$")
                                    if trimmed ~= "" then
                                        tag_list[#tag_list + 1] = trimmed
                                    end
                                end
                                candidate.tags =
                                    #tag_list > 0 and tag_list or { "KOReader" }
                            end)
                    end)
                end,
            },
            {
                text = _("← Back"),
                callback = function() close_menu_then(menu_instance, show_main) end,
            },
        }

        menu_instance = open_settings_menu(_("Tags"), item_table, show_main)
    end

    -- ── Submenu: Sync ────────────────────────────────────────────────────
    show_sync = function()
        local sub_dlg
        local auto_label = cfg.auto_send_wifi
            and CHECK_ON .. _("Send pending when WiFi (every 20 min): ON")
            or  _("Send pending when WiFi (every 20 min): OFF")

        local sync_name
        if cfg.sync_server then
            sync_name = cfg.sync_server.name or cfg.sync_server.address or "Cloud"
        end

        sub_dlg = ButtonDialog:new {
            title   = _("Sync"),
            buttons = {
                {{ text = auto_label,
                   callback = function()
                       local next_value = not cfg.auto_send_wifi
                       persist_update(function(candidate)
                           candidate.auto_send_wifi = next_value
                       end)
                       UIManager:close(sub_dlg)
                       show_sync()
                   end }},
                {{ text = sync_name and (_("Cloud Sync: ") .. sync_name)
                                     or _("Cloud Sync: (not configured)"),
                   callback = function()
                       Nav.after_close(function() UIManager:close(sub_dlg) end, function()
                           CardSync.show_cloud_sync_dialog(cfg, function(new_cfg)
                               cfg = new_cfg
                               if on_saved then on_saved(cfg) end
                           end, { parent_fn = show_sync })
                       end)
                   end }},
                {{ text = _("Back"),
                   callback = function() UIManager:close(sub_dlg); show_main() end }},
            },
        }
        UIManager:show(sub_dlg)
    end

    -- ── Main settings screen ─────────────────────────────────────────────

    show_main = function()
        local menu_instance

        local function close_settings()
            Nav.after_close(function()
                if menu_instance then UIManager:close(menu_instance) end
            end, function()
                if settings_parent_fn then settings_parent_fn() end
            end)
        end

        local item_table = {
            info_menu_item(_("About Settings"), _(
                "Card defaults: note types, decks, one-tap send, and deck routing.\nAnki connection: AnkiConnect URL and sync after send.\nTags: tags applied when cards are sent.\nMemorization options: how text is split (not deck routing).\nSync: background send when WiFi is on and cloud backup.\n\nGray rows in any submenu — tap for help."
            )),
            {
                text = _("View settings guide"),
                dim  = true,
                callback = function()
                    close_menu_then(menu_instance, function()
                        local ok, ReadmeViewer = pcall(require, "readme_viewer")
                        if ok and ReadmeViewer.show_or_notify then
                            ReadmeViewer.show_or_notify("settings", {
                                on_close = show_main,
                            })
                        else
                            show_main()
                        end
                    end)
                end,
            },
            {
                text = _("Card defaults…"),
                callback = function()
                    close_menu_then(menu_instance, show_defaults)
                end,
            },
            {
                text = _("Anki connection…"),
                callback = function()
                    close_menu_then(menu_instance, show_anki_connection)
                end,
            },
            {
                text = _("Tags…"),
                callback = function()
                    close_menu_then(menu_instance, show_tags)
                end,
            },
            {
                text = _("Memorization options…"),
                callback = function()
                    memorization_parent_fn = show_main
                    close_menu_then(menu_instance, show_memorization)
                end,
            },
            {
                text = _("Sync…"),
                callback = function()
                    close_menu_then(menu_instance, show_sync)
                end,
            },
            {
                text = settings_parent_fn and _("← Back") or _("Close"),
                callback = close_settings,
            },
        }

        local on_close = settings_parent_fn and settings_parent_fn or function() end
        menu_instance = open_settings_menu(_("Settings"), item_table, on_close)
    end

    show_main()
end

return SettingsViewer
