-- Deck picker — fetch Anki deck list via AnkiConnect and show a scrollable Menu.

local InputDialog  = require("ui/widget/inputdialog")
local Menu         = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local UIManager    = require("ui/uimanager")
local _            = require("gettext")

local AnkiSync     = require("anki_sync")
local CardDefaults = require("card_defaults")
local CardStorage  = require("card_storage")
local Nav         = require("nav")
local UiBusy      = require("ui_busy")

local DeckPicker = {}

local function sorted_unique(names)
    local seen, list = {}, {}
    for _i, name in ipairs(names or {}) do
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

local function favorite_set(config)
    local fav = {}
    if type(config.favorite_decks) == "table" then
        for _i, d in ipairs(config.favorite_decks) do fav[d] = true end
    end
    return fav
end

local function ordered_deck_list(config, names)
    local out, seen = {}, {}
    local fav = favorite_set(config)
    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(out, name)
        end
    end
    if type(config.recent_decks) == "table" then
        for _i, d in ipairs(config.recent_decks) do add(d) end
    end
    for _i, d in ipairs(names) do
        if fav[d] then add(d) end
    end
    for _i, d in ipairs(names) do add(d) end
    return out
end

function DeckPicker.fetch_deck_names(config, refresh)
    config = config or {}
    local url = config.url
    if not url or url == "" then
        return nil, _("AnkiConnect URL not set")
    end

    local names, err = AnkiSync.get_deck_names(url)
    if names then
        config.cached_deck_names = names
        config.cached_deck_names_at = os.time()
        CardStorage.save_anki_settings(config)
        return names, false
    end

    local cached = config.cached_deck_names
    if type(cached) == "table" and #cached > 0 then
        return cached, true
    end
    return nil, err or _("Could not fetch deck list")
end

function DeckPicker.show(config, card, on_select, opts)
    opts = opts or {}
    local current = opts.current_deck or AnkiSync.resolve_base_deck(config, card)
                       or config.deck or ""
    local parent_fn = opts.parent_fn

    local function deck_label(deck_name)
        local label = deck_name
        if deck_name == current then label = "✓ " .. label end
        if favorite_set(config)[deck_name] then label = "★ " .. label end
        if card then
            local resolved = AnkiSync.resolve_deck_name(config, card, deck_name)
            if resolved ~= deck_name then
                label = label .. "  → " .. resolved
            end
        end
        return label
    end

    local function open_menu(names, from_cache)
        local item_table = {}
        local menu_instance
        local suppress_dismiss = false
        local ordered = ordered_deck_list(config, names)
        local dismissed = false

        local function dismiss()
            if dismissed then return end
            dismissed = true
            Nav.after_close(function()
                if menu_instance then
                    UIManager:close(menu_instance)
                end
            end, function()
                if opts.on_cancel then
                    opts.on_cancel()
                elseif parent_fn then
                    parent_fn()
                end
            end)
        end

        local function close_menu_quiet()
            suppress_dismiss = true
            if menu_instance then UIManager:close(menu_instance) end
            suppress_dismiss = false
        end

        local function pick_deck(deck_name)
            close_menu_quiet()
            if on_select then on_select(deck_name) end
        end

        local subtitle_parts = {}
        if card then
            table.insert(subtitle_parts,
                _("Send to: ") .. AnkiSync.resolve_deck_name(config, card, current))
        end
        if from_cache then
            table.insert(subtitle_parts, _("Offline — cached deck list (may be stale)"))
        end

        for _i, name in ipairs(ordered) do
            local deck_name = name
            table.insert(item_table, {
                text = deck_label(deck_name),
                callback = function() pick_deck(deck_name) end,
            })
        end

        table.insert(item_table, {
            text = _("Enter manually…"),
            callback = function()
                close_menu_quiet()
                local edit_dlg
                edit_dlg = InputDialog:new {
                    title      = _("Deck name"),
                    input      = current,
                    input_hint = "English::Koreader",
                    buttons    = {{
                        { text = _("Cancel"), callback = function()
                            UIManager:close(edit_dlg)
                            open_menu(names, from_cache)
                        end },
                        { text = _("OK"), is_enter_default = true, callback = function()
                            local new_deck = edit_dlg:getInputText() or ""
                            UIManager:close(edit_dlg)
                            if new_deck ~= "" then pick_deck(new_deck) end
                        end },
                    }},
                }
                UIManager:show(edit_dlg)
                edit_dlg:onShowKeyboard()
            end,
        })

        if config.url and config.url ~= "" then
            table.insert(item_table, {
                text = _("Refresh deck list"),
                callback = function()
                    close_menu_quiet()
                    local fresh, err = DeckPicker.fetch_deck_names(config, true)
                    if fresh then
                        open_menu(sorted_unique(fresh), false)
                    else
                        UIManager:show(Notification:new {
                            text = err or _("Refresh failed"), timeout = 4,
                        })
                        open_menu(names, from_cache)
                    end
                end,
            })
        end

        table.insert(item_table, {
            text = _("Back"),
            callback = function()
                close_menu_quiet()
                dismiss()
            end,
        })

        menu_instance = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
            title    = opts.title or _("Choose Deck"),
            subtitle = #subtitle_parts > 0 and table.concat(subtitle_parts, " · ") or nil,
            item_table = item_table,
        }), function()
            if suppress_dismiss then return end
            dismiss()
        end)
        Nav.show(menu_instance)
    end

    local function show_with_names(names, err_or_cached)
        if names then
            open_menu(sorted_unique(names), err_or_cached == true)
            return
        end

        UIManager:show(Notification:new {
            text = (err_or_cached or _("Could not load decks"))
                   .. " — " .. _("using fallback list"),
            timeout = 4,
        })
        local fallback = CardDefaults.configured_deck_names(config)
        if config.deck and config.deck ~= "" then
            local seen = {}
            for _i, d in ipairs(fallback) do seen[d] = true end
            if not seen[config.deck] then table.insert(fallback, config.deck) end
        end
        if current ~= "" then
            local seen = {}
            for _i, d in ipairs(fallback) do seen[d] = true end
            if not seen[current] then table.insert(fallback, current) end
        end
        table.insert(fallback, "English::Koreader")
        open_menu(sorted_unique(fallback), true)
    end

    UiBusy.run(_("Loading Anki decks…"), function()
        local names, err_or_cached = DeckPicker.fetch_deck_names(config, opts.refresh)
        show_with_names(names, err_or_cached)
    end)
end

return DeckPicker
