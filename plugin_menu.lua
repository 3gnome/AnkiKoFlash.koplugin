-- AnkiKoFlash hub menu — single highlight-menu entry for all plugin actions.

local Menu       = require("ui/widget/menu")
local UIManager  = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _          = require("gettext")

local CardManager     = require("card_manager")
local HighlightInbox  = require("highlight_inbox")
local CardStorage     = require("card_storage")
local CardDefaults    = require("card_defaults")
local PluginConstants = require("plugin_constants")
local Nav             = require("nav")

local PluginMenu = {}

local function show_readme(readme_id, opts)
    local ok, ReadmeViewer = pcall(require, "readme_viewer")
    if ok and ReadmeViewer and ReadmeViewer.show_or_notify then
        ReadmeViewer.show_or_notify(readme_id, opts)
    elseif ok and ReadmeViewer and ReadmeViewer.show then
        ReadmeViewer.show(readme_id, opts)
    else
        UIManager:show(InfoMessage:new {
            text    = _("README viewer unavailable"),
            timeout = 5,
        })
    end
end

local function merge_settings_into_config(config, new_cfg, previous_settings)
    if not config or not new_cfg then return end
    config.anki = config.anki or {}
    -- Settings callbacks provide the complete newly persisted table. Remove
    -- keys from the prior persisted table first so successful nil deletions
    -- (which pairs() cannot report) clear runtime state, while static config
    -- keys that were never persisted remain intact.
    for key, _value in pairs(previous_settings or {}) do
        config.anki[key] = nil
    end
    -- sync_server predates this replacement merge and must also be clearable
    -- when no prior-settings snapshot was available.
    config.anki.sync_server = nil
    for k, v in pairs(new_cfg) do
        config.anki[k] = v
    end
end

PluginMenu.merge_settings_into_config = merge_settings_into_config

function PluginMenu.show(hl, ctx, ui, config, actions)
    actions = actions or {}
    ctx = ctx or {}
    local menu_ref = {}
    local guard = { dismissed = false }

    local function dismiss()
        if guard.dismissed then return end
        guard.dismissed = true
        if actions.on_dismiss then actions.on_dismiss() end
    end

    local function reopen_hub()
        guard.dismissed = false
        PluginMenu.show(hl, ctx, ui, config, actions)
    end

    local function close_hub()
        if menu_ref[1] then
            UIManager:close(menu_ref[1])
            menu_ref[1] = nil
        end
    end

    local function open_child(open_fn)
        Nav.after_close(close_hub, open_fn)
    end

    local book_title = ""
    if ui and ui.document then
        book_title = (ui.document:getProps().title or ""):match("^%s*(.-)%s*$") or ""
        if #book_title > 100 then book_title = book_title:sub(1, 100) end
    end

    local function section_label(text)
        return {
            text           = text,
            dim            = true,
            select_enabled = false,
        }
    end

    local CHECK_ON = "\xe2\x9c\x93 "

    local function toggle_label(on, label)
        if on then return CHECK_ON .. label .. ": ON" end
        return label .. ": OFF"
    end

    local function card_submenu(readme_id, action_label, on_action)
        return {
            {
                text     = action_label,
                bold     = true,
                callback = function()
                    open_child(on_action)
                end,
            },
            {
                text     = _("View README"),
                callback = function()
                    show_readme(readme_id)
                end,
            },
            {
                text     = _("← Back"),
                callback = function()
                    local menu = menu_ref[1]
                    if menu and menu.onClose then
                        menu:onClose()
                    end
                end,
            },
        }
    end

    local function add_card_hub_entry(items, label, readme_id, card_kind, on_action)
        if CardDefaults.should_flatten_hub(config, card_kind) then
            table.insert(items, {
                text     = _(label),
                bold     = true,
                callback = function()
                    open_child(on_action)
                end,
            })
        else
            table.insert(items, {
                text           = _(label),
                bold           = true,
                sub_item_table = card_submenu(readme_id, _("Create ") .. _(label), on_action),
            })
        end
    end

    local items = {
        {
            text     = _("← Back"),
            bold     = true,
            callback = function()
                if menu_ref[1] then menu_ref[1]:onCloseAllMenus() end
            end,
        },
        section_label(_("Mode")),
        {
            text     = toggle_label(
                CardDefaults.save_only_vocabulary(config),
                _("Save only (skip send to Anki)")),
            bold     = true,
            callback = function()
                config.anki = config.anki or {}
                config.anki.save_only_vocabulary =
                    not CardDefaults.save_only_vocabulary(config)
                CardStorage.save_anki_settings(config.anki)
                open_child(reopen_hub)
            end,
        },
        section_label(_("Create from highlight")),
    }

    add_card_hub_entry(items, CardDefaults.vocabulary_hub_label(config), "vocabulary", "vocabulary", function()
        if actions.on_vocabulary_card then
            actions.on_vocabulary_card(reopen_hub)
        end
    end)
    add_card_hub_entry(items, PluginConstants.MEMORIZATION_CARD_LABEL, "memorization", "memorization", function()
        if actions.on_memorization then
            actions.on_memorization(reopen_hub)
        end
    end)

    table.insert(items, section_label(_("Library & batch")))
    table.insert(items, {
        text     = _("View All Highlights"),
        bold     = true,
        callback = function()
            if not ui then
                UIManager:show(InfoMessage:new {
                    text    = _("Open a book to view highlights"),
                    timeout = 3,
                })
                return
            end
            open_child(function()
                HighlightInbox.show(ui, config, {
                    on_back      = reopen_hub,
                    back_label   = _("← Back to AnkiKoFlash"),
                    title_prefix = _("View All Highlights"),
                })
            end)
        end,
    })
    local unsent = CardStorage.count_unsent()
    if unsent > 0 then
        table.insert(items, {
            text     = _("Send pending to Anki") .. " (" .. tostring(unsent) .. ")",
            bold     = true,
            callback = function()
                CardManager.send_all_unsent(config, ui, {
                    on_done = function()
                        reopen_hub()
                    end,
                })
            end,
        })
    end
    table.insert(items, {
        text     = _("My Cards"),
        bold     = true,
        callback = function()
            open_child(function()
                CardManager.show(config, book_title, ui, {
                    on_back    = reopen_hub,
                    back_label = _("← Back to AnkiKoFlash"),
                })
            end)
        end,
    })
    table.insert(items, {
        text     = _("Highlights and Cards"),
        bold     = true,
        callback = function()
            open_child(function()
                CardManager.show_manage(config, {
                    on_back    = reopen_hub,
                    back_label = _("← Back to AnkiKoFlash"),
                    ui         = ui,
                })
            end)
        end,
    })
    table.insert(items, section_label(_("Configuration")))
    table.insert(items, {
        text     = _("Settings"),
        bold     = true,
        callback = function()
            open_child(function()
                local ok, SettingsViewer = pcall(require, "settings_viewer")
                if not ok or not SettingsViewer or not SettingsViewer.show then
                    UIManager:show(InfoMessage:new {
                        text    = _("Settings unavailable: ")
                            .. tostring(SettingsViewer or "load error"),
                        timeout = 8,
                    })
                    return
                end
                local previous_settings =
                    CardStorage.load_anki_settings() or {}
                SettingsViewer.show(config, function(new_cfg)
                    merge_settings_into_config(
                        config, new_cfg, previous_settings)
                    previous_settings = {}
                    for key, _value in pairs(new_cfg or {}) do
                        previous_settings[key] = true
                    end
                end, {
                    parent_fn = reopen_hub,
                    ui        = ui,
                })
            end)
        end,
    })

    menu_ref[1] = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
        title      = PluginConstants.NAME,
        item_table = items,
    }), dismiss)
    Nav.show(menu_ref[1])
end

return PluginMenu
