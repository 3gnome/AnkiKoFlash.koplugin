-- Note type picker — fetch Anki note types via AnkiConnect.

local InputDialog  = require("ui/widget/inputdialog")
local Menu         = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local UIManager    = require("ui/uimanager")
local _            = require("gettext")

local AnkiSync         = require("anki_sync")
local CardStorage      = require("card_storage")
local Nav              = require("nav")
local NoteTypeProfiles = require("note_type_profiles")
local UiBusy           = require("ui_busy")

local NoteTypePicker = {}

local function model_allowed(name, opts)
    opts = opts or {}
    local filter = opts.profile_filter
    if not filter or filter == "" then return true end
    if filter == "vocabulary" then
        return NoteTypeProfiles.is_vocabulary_compatible(name)
    elseif filter == "memorization" then
        return NoteTypeProfiles.is_memorization_compatible(name)
    end
    return true
end

local function filter_model_names(names, opts)
    local out = {}
    for _i, name in ipairs(names or {}) do
        if model_allowed(name, opts) then
            table.insert(out, name)
        end
    end
    return out
end

local function reject_invalid_model(model_name, opts)
    if model_allowed(model_name, opts) then return nil end
    local filter = opts and opts.profile_filter
    if filter == "vocabulary" then
        return _("That note type is not valid for dictionary vocabulary cards.")
    elseif filter == "memorization" then
        return _("That note type is not valid for memorization cards.")
    end
    return _("That note type is not allowed here.")
end

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

-- Apply the profile filter, then fall back to the raw (unfiltered) list so
-- the menu is never empty.
local function filtered_names(names, opts)
    local filtered = filter_model_names(sorted_unique(names), opts)
    if #filtered == 0 and opts.fallback_models then
        filtered = filter_model_names(opts.fallback_models, opts)
    end
    if #filtered == 0 then
        filtered = sorted_unique(names)
    end
    return filtered
end

-- True when a prior fetch cached a non-empty note-type list. Lets callers open
-- the picker instantly instead of blocking on AnkiConnect before showing a menu.
function NoteTypePicker.has_cached_models(config)
    local cached = config and config.cached_model_names
    return type(cached) == "table" and #cached > 0
end

function NoteTypePicker.fetch_model_names(config, refresh)
    config = config or {}
    local url = config.url
    if not url or url == "" then return nil, _("AnkiConnect URL not set") end

    local names, err = AnkiSync.get_model_names(url)
    if names then
        config.cached_model_names = names
        config.cached_model_names_at = os.time()
        CardStorage.save_anki_settings(config)
        return names, false
    end

    local cached = config.cached_model_names
    if type(cached) == "table" and #cached > 0 then
        return cached, true
    end
    return nil, err or _("Could not fetch note types")
end

function NoteTypePicker.fetch_field_names(config, model_name, refresh)
    config = config or {}
    model_name = NoteTypeProfiles.normalize_model_name(model_name)
    config.cached_model_fields = config.cached_model_fields or {}
    local url = config.url
    if not url or url == "" then
        return config.cached_model_fields[model_name]
    end
    local names, err = AnkiSync.get_model_field_names(url, model_name)
    if names then
        config.cached_model_fields[model_name] = names
        CardStorage.save_anki_settings(config)
        return names
    end
    return config.cached_model_fields[model_name]
end

function NoteTypePicker.show(config, on_select, opts)
    opts = opts or {}
    local current = NoteTypeProfiles.normalize_model_name(
        opts.current_model or config.vocabulary_model or config.model)
    local parent_fn = opts.parent_fn or opts.on_cancel

    local function open_menu(names, from_cache)
        local item_table = {}
        local menu_instance
        local suppress_dismiss = false
        local info_subtitle = opts.info_text or _(
            "Pick an Anki note type for dictionary vocabulary cards. "
            .. "Default name in Anki: Vocabulary Card.")
        if from_cache then
            info_subtitle = info_subtitle .. "\n" .. _("(Offline — cached note types, may be stale)")
        end

        local function dismiss()
            Nav.after_close(nil, function()
                if parent_fn then parent_fn() end
            end)
        end

        local function close_menu_quiet()
            suppress_dismiss = true
            if menu_instance then UIManager:close(menu_instance) end
            suppress_dismiss = false
        end

        local function pick_model(model_name)
            local reject = reject_invalid_model(model_name, opts)
            if reject then
                UIManager:show(Notification:new { text = reject, timeout = 5 })
                return
            end
            close_menu_quiet()
            if on_select then on_select(model_name) end
        end

        if opts.readme_id then
            table.insert(item_table, {
                text     = _("View README"),
                callback = function()
                    local ok, ReadmeViewer = pcall(require, "readme_viewer")
                    if ok and ReadmeViewer.show_or_notify then
                        ReadmeViewer.show_or_notify(opts.readme_id)
                    end
                end,
            })
        end

        for _i, name in ipairs(names) do
            if model_allowed(name, opts) then
                local model_name = name
                local label = model_name
                if model_name == current then label = "✓ " .. label end
                table.insert(item_table, {
                    text = label,
                    callback = function() pick_model(model_name) end,
                })
            end
        end

        table.insert(item_table, {
            text = _("Enter manually…"),
            callback = function()
                close_menu_quiet()
                local edit_dlg
                edit_dlg = InputDialog:new {
                    title      = _("Note type name"),
                    input      = current,
                    input_hint = NoteTypeProfiles.DEFAULT_MODEL,
                    buttons    = {{
                        { text = _("Cancel"), callback = function()
                            UIManager:close(edit_dlg)
                            open_menu(names, from_cache)
                        end },
                        { text = _("OK"), is_enter_default = true, callback = function()
                            local m = edit_dlg:getInputText() or ""
                            UIManager:close(edit_dlg)
                            if m ~= "" then pick_model(m) end
                        end },
                    }},
                }
                UIManager:show(edit_dlg)
                edit_dlg:onShowKeyboard()
            end,
        })

        if config.url and config.url ~= "" then
            table.insert(item_table, {
                text = _("Refresh note type list"),
                callback = function()
                    close_menu_quiet()
                    local fresh, err = NoteTypePicker.fetch_model_names(config, true)
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
            title      = opts.title or _("Choose note type"),
            subtitle   = info_subtitle,
            item_table = item_table,
        }), function()
            if suppress_dismiss then return end
            dismiss()
        end)
        Nav.show(menu_instance)
    end

    -- Cache-first: open the menu instantly from a previous fetch instead of
    -- blocking on AnkiConnect's modelNames round-trip (which could take seconds
    -- on a slow or unreachable Anki, making the menu feel frozen).
    if not opts.refresh and NoteTypePicker.has_cached_models(config) then
        open_menu(filtered_names(config.cached_model_names, opts), true)
        return
    end

    -- No cache yet (or an explicit refresh): fetch with a progress indicator
    -- (Trapper coroutine) so the reader stays responsive instead of freezing.
    UiBusy.run(_("Loading note types…"), function()
        local names, err_or_cached = NoteTypePicker.fetch_model_names(config, opts.refresh)
        if names then
            open_menu(filtered_names(names, opts), err_or_cached == true)
            return
        end
        UIManager:show(Notification:new {
            text = (err_or_cached or _("Could not load note types"))
                   .. " — " .. _("using built-in list"),
            timeout = 4,
        })
        local fallbacks = filter_model_names(opts.fallback_models or {
            NoteTypeProfiles.DEFAULT_MODEL,
            NoteTypeProfiles.VOCABULARY_CARD_MODEL,
            "Basic",
        }, opts)
        if #fallbacks == 0 then
            fallbacks = opts.fallback_models or {
                NoteTypeProfiles.DEFAULT_MODEL,
                "Basic",
            }
        end
        open_menu(fallbacks, true)
    end)
end

return NoteTypePicker
