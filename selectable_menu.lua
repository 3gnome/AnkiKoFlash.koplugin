-- Reusable checkbox lists: select all, delete selected/all (actions at bottom).

local ConfirmBox = require("ui/widget/confirmbox")
local UIManager  = require("ui/uimanager")
local _          = require("gettext")

local SelectableMenu = {}

function SelectableMenu.truncate(text, max_len)
    max_len = max_len or 40
    text = (text or ""):match("^%s*(.-)%s*$") or ""
    if #text > max_len then
        return text:sub(1, max_len - 1) .. "…"
    end
    return text
end

function SelectableMenu.count_selected(selected)
    local n = 0
    for _i, v in pairs(selected) do if v then n = n + 1 end end
    return n
end

-- Update checkbox / select-all / delete-selected labels without rebuilding the menu.
function SelectableMenu.sync_in_place(menu, state)
    if not menu or not menu.item_table or not state then return end
    local entries = state.entries or {}
    local selected = state.selected or {}
    local opts = state.opts or {}
    local sel_cnt = SelectableMenu.count_selected(selected)

    local entry_by_key = {}
    for i, entry in ipairs(entries) do
        entry_by_key[entry.key] = entry
    end

    for _i, item in ipairs(menu.item_table) do
        if item._anki_select_key then
            local entry = entry_by_key[item._anki_select_key]
            if entry then
                if opts.label_fn then
                    item.text = opts.label_fn(entry, selected, entry._idx)
                else
                    local check = selected[item._anki_select_key] and "☑ " or "☐ "
                    item.text = check .. (entry.label or "")
                end
            end
        elseif item._anki_select_all then
            item.text = sel_cnt > 0 and _("✗ Deselect All") or _("✓ Select All")
        elseif item._anki_delete_selected then
            local label = opts.delete_selected_label or _("Delete Selected")
            item.text = label .. " (" .. tostring(sel_cnt) .. ")"
            item.select_enabled = sel_cnt > 0
        elseif item._anki_send_selected then
            local label = opts.send_selected_label or _("Send Selected to Anki")
            item.text = label .. " (" .. tostring(sel_cnt) .. ")"
            item.select_enabled = sel_cnt > 0
        elseif item._anki_check_anki_selected then
            local label = opts.check_anki_selected_label or _("Check Selected against Anki")
            item.text = label .. " (" .. tostring(sel_cnt) .. ")"
            item.select_enabled = sel_cnt > 0
        elseif item._anki_remove_from_queue then
            local label = opts.remove_from_queue_label or _("Remove from queue")
            item.text = label .. " (" .. tostring(sel_cnt) .. ")"
            item.select_enabled = sel_cnt > 0
        elseif item._anki_action_count and opts.action_count_fn then
            local n = opts.action_count_fn()
            if opts.action_count_label_fn then
                item.text = opts.action_count_label_fn(n)
            else
                item.text = tostring(n)
            end
            item.select_enabled = n > 0
        end
    end

    pcall(function()
        menu:updateItems(menu.page or 1, false)
    end)
end

--[[
  Append selectable rows to items (KOReader Menu item_table).

  opts.entries     — { key, label, data?, hold_callback? }
  opts.selected    — map key → bool (updated in place)
  opts.rebuild     — function() refresh menu after toggle/delete
  opts.header_items — optional rows inserted after select-all
  opts.empty_text
  opts.on_open(entry, index) — hold (or tap when open_on_tap)
  opts.on_hold(entry, index) — overrides default hold behaviour
  opts.open_on_tap — tap opens instead of toggling
  opts.default_selected — bool, or opts.default_selected_fn(entry, i)
  opts.on_delete_selected(selected_entries)
  opts.on_send_selected(selected_entries)
  opts.on_check_anki_selected(selected_entries)
  opts.on_remove_from_queue_selected(selected_entries)
  Delete labels/confirms optional; delete rows only when callbacks set.
]]
function SelectableMenu.append_list(items, opts)
    opts = opts or {}
    local entries = opts.entries or {}
    local selected = opts.selected or {}
    local rebuild = opts.rebuild or function() end

    for i, entry in ipairs(entries) do
        if selected[entry.key] == nil then
            if opts.default_selected_fn then
                selected[entry.key] = opts.default_selected_fn(entry, i)
            else
                selected[entry.key] = opts.default_selected ~= false
            end
        end
    end

    local sel_cnt = SelectableMenu.count_selected(selected)
    local total = #entries

    if opts.leading_items then
        for _i, row in ipairs(opts.leading_items) do
            table.insert(items, row)
        end
    end

    if total > 0 and opts.show_select_all ~= false then
        table.insert(items, {
            text            = sel_cnt > 0 and _("✗ Deselect All") or _("✓ Select All"),
            _anki_select_all = true,
            callback = function()
                local current_cnt = SelectableMenu.count_selected(selected)
                local new_val = current_cnt == 0
                for _i, entry in ipairs(entries) do
                    selected[entry.key] = new_val
                end
                rebuild()
            end,
        })
    end

    if opts.header_items then
        for _i, row in ipairs(opts.header_items) do
            table.insert(items, row)
        end
    end

    if total == 0 then
        table.insert(items, {
            text           = opts.empty_text or _("(nothing here)"),
            select_enabled = false,
        })
    end

    for i, entry in ipairs(entries) do
        entry._idx = i
        local check = selected[entry.key] and "☑ " or "☐ "
        local key = entry.key
        local label = opts.label_fn
            and opts.label_fn(entry, selected, i)
            or (check .. (entry.label or ""))
        table.insert(items, {
            text            = label,
            _anki_select_key = key,
            callback = function()
                if opts.open_on_tap and opts.on_open then
                    opts.on_open(entry, i)
                else
                    selected[key] = not selected[key]
                    rebuild()
                end
            end,
            hold_callback = entry.hold_callback or function()
                if opts.on_hold then
                    opts.on_hold(entry, i)
                elseif opts.on_open then
                    opts.on_open(entry, i)
                end
            end,
        })
    end

    if opts.on_send_selected then
        table.insert(items, {
            text               = (opts.send_selected_label or _("Send Selected to Anki"))
                .. " (" .. tostring(sel_cnt) .. ")",
            select_enabled     = sel_cnt > 0,
            _anki_send_selected = true,
            callback = function()
                local current_cnt = SelectableMenu.count_selected(selected)
                if current_cnt == 0 then return end
                local picked = {}
                for _i, entry in ipairs(entries) do
                    if selected[entry.key] then
                        table.insert(picked, entry)
                    end
                end
                opts.on_send_selected(picked, selected)
            end,
        })
    end

    if opts.on_check_anki_selected then
        table.insert(items, {
            text                  = (opts.check_anki_selected_label or _("Check Selected against Anki"))
                .. " (" .. tostring(sel_cnt) .. ")",
            select_enabled        = sel_cnt > 0,
            _anki_check_anki_selected = true,
            callback = function()
                local current_cnt = SelectableMenu.count_selected(selected)
                if current_cnt == 0 then return end
                local picked = {}
                for _i, entry in ipairs(entries) do
                    if selected[entry.key] then
                        table.insert(picked, entry)
                    end
                end
                UIManager:show(ConfirmBox:new {
                    text = opts.check_anki_selected_confirm
                        or _("Check selected pending cards against Anki? Matches the exact intended note type, deck, and card fields. Does not create notes. Found cards are removed from the queue and logged to Recently sent."),
                    ok_text = _("Check Anki"),
                    ok_callback = function()
                        opts.on_check_anki_selected(picked, selected)
                    end,
                })
            end,
        })
    end

    if opts.on_remove_from_queue_selected then
        table.insert(items, {
            text                  = (opts.remove_from_queue_label or _("Remove from queue"))
                .. " (" .. tostring(sel_cnt) .. ")",
            select_enabled        = sel_cnt > 0,
            _anki_remove_from_queue = true,
            callback = function()
                local current_cnt = SelectableMenu.count_selected(selected)
                if current_cnt == 0 then return end
                local picked = {}
                for _i, entry in ipairs(entries) do
                    if selected[entry.key] then
                        table.insert(picked, entry)
                    end
                end
                UIManager:show(ConfirmBox:new {
                    text = opts.remove_from_queue_confirm
                        or _("Remove selected cards from the pending queue? This does not change Anki."),
                    ok_text = _("Remove"),
                    ok_callback = function()
                        opts.on_remove_from_queue_selected(picked, selected)
                        UIManager:scheduleIn(0.05, function()
                            if opts.after_remove_from_queue then
                                pcall(opts.after_remove_from_queue)
                            else
                                pcall(rebuild)
                            end
                        end)
                    end,
                })
            end,
        })
    end

    if opts.on_delete_selected then
        table.insert(items, {
            text               = (opts.delete_selected_label or _("Delete Selected"))
                .. " (" .. tostring(sel_cnt) .. ")",
            select_enabled     = sel_cnt > 0,
            _anki_delete_selected = true,
            callback = function()
                local current_cnt = SelectableMenu.count_selected(selected)
                if current_cnt == 0 then return end
                local picked = {}
                for _i, entry in ipairs(entries) do
                    if selected[entry.key] then
                        table.insert(picked, entry)
                    end
                end
                UIManager:show(ConfirmBox:new {
                    text = opts.delete_selected_confirm
                        or _("Delete selected item(s)?"),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        opts.on_delete_selected(picked, selected)
                        UIManager:scheduleIn(0.05, function()
                            if opts.after_delete then
                                pcall(opts.after_delete)
                            else
                                pcall(rebuild)
                            end
                        end)
                    end,
                })
            end,
        })
    end

    if total > 0 and opts.on_delete_all then
        local all_label = opts.delete_all_label or _("Delete All")
        if opts.delete_all_count ~= nil then
            all_label = all_label .. " (" .. tostring(opts.delete_all_count) .. ")"
        end
        table.insert(items, {
            text     = all_label,
            callback = function()
                UIManager:show(ConfirmBox:new {
                    text = opts.delete_all_confirm or _("Delete all items?"),
                    ok_text = opts.delete_all_ok or _("Delete All"),
                    ok_callback = function()
                        opts.on_delete_all(entries, selected)
                        UIManager:scheduleIn(0.05, function()
                            if opts.after_delete_all then
                                pcall(opts.after_delete_all)
                            else
                                pcall(rebuild)
                            end
                        end)
                    end,
                })
            end,
        })
    end

    return selected, sel_cnt, {
        entries  = entries,
        selected = selected,
        opts     = opts,
    }
end

return SelectableMenu
