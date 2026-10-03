-- Dictionary picker — list installed KOReader StarDict dictionaries in a Menu.
-- Unlike deck_picker.lua, the names come from KOReader's ReaderDictionary module
-- (ui.dictionary.enabled_dict_names) instead of AnkiConnect, so no network is
-- involved. Callers fall back to free-text entry when the list is unavailable.

local InputDialog  = require("ui/widget/inputdialog")
local Menu         = require("ui/widget/menu")
local UIManager    = require("ui/uimanager")
local _            = require("gettext")

local Nav = require("nav")

local DictionaryPicker = {}

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

-- Installed/enabled StarDict names, or nil when unavailable.
function DictionaryPicker.installed_names(ui)
    local dict = ui and ui.dictionary
    if not dict then return nil end
    local names = dict.enabled_dict_names or dict.preferred_dictionaries
    if type(names) ~= "table" or #names == 0 then return nil end
    return sorted_unique(names)
end

-- Show a menu of installed dictionaries. Returns nil when no dictionary list is
-- available (callers should fall back to free-text entry); otherwise shows the
-- menu and returns true. ``current`` is the currently configured name ("" = auto).
function DictionaryPicker.show(ui, current, on_select, opts)
    opts = opts or {}
    current = current or ""
    local names = DictionaryPicker.installed_names(ui)
    if not names or #names == 0 then
        return nil
    end

    local parent_fn = opts.parent_fn
    local menu_instance
    local suppress_dismiss = false
    local dismissed = false

    local function dismiss()
        if dismissed then return end
        dismissed = true
        Nav.after_close(function()
            if menu_instance then UIManager:close(menu_instance) end
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

    local function pick(name)
        close_menu_quiet()
        if on_select then on_select(name) end
    end

    local function open_menu()
        local item_table = {}
        table.insert(item_table, {
            text     = current == "" and (_("(auto)") .. "  ✓") or _("(auto)"),
            bold     = true,
            callback = function() pick("") end,
        })
        for _i, name in ipairs(names) do
            local label = name
            if name == current then label = "✓ " .. label end
            table.insert(item_table, {
                text     = label,
                callback = function() pick(name) end,
            })
        end

        table.insert(item_table, {
            text = _("Enter manually…"),
            callback = function()
                close_menu_quiet()
                local edit_dlg
                edit_dlg = InputDialog:new {
                    title      = opts.title or _("Dictionary name"),
                    input      = current,
                    input_hint = opts.hint or "",
                    buttons    = {{
                        { text = _("Cancel"), callback = function()
                            UIManager:close(edit_dlg)
                            open_menu()
                        end },
                        { text = _("OK"), is_enter_default = true, callback = function()
                            local new_name = edit_dlg:getInputText() or ""
                            UIManager:close(edit_dlg)
                            if new_name ~= "" then pick(new_name) end
                        end },
                    }},
                }
                UIManager:show(edit_dlg)
                edit_dlg:onShowKeyboard()
            end,
        })

        table.insert(item_table, {
            text     = _("← Back"),
            bold     = true,
            callback = function()
                close_menu_quiet()
                dismiss()
            end,
        })

        menu_instance = Nav.wrap_menu(Menu:new(Nav.apply_compact_menu {
            title      = opts.title or _("Choose dictionary"),
            item_table = item_table,
        }), function()
            if suppress_dismiss then return end
            dismiss()
        end)
        Nav.show(menu_instance)
    end

    open_menu()
    return true
end

return DictionaryPicker
