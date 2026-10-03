-- Safe highlight-menu reopening helpers.

local PositionUtils = require("position_utils")

local HighlightMenuReopen = {}

local function annotations_for(hl)
    if type(hl) ~= "table" then return nil end
    local ui = hl.ui
    if type(ui) ~= "table" or type(ui.annotation) ~= "table" then return nil end
    local annotations = ui.annotation.annotations
    if type(annotations) ~= "table" then return nil end
    return annotations
end

local function is_integer(value)
    return type(value) == "number" and value >= 1 and value % 1 == 0
end

function HighlightMenuReopen.is_current(hl, ui)
    return type(hl) == "table"
        and type(ui) == "table"
        and hl.ui == ui
        and ui.highlight == hl
end

function HighlightMenuReopen.resolve_annotation(hl, index, selection)
    local annotations = annotations_for(hl)
    if not annotations then return nil, nil end

    local function same_position(left, right)
        return type(left) == "table" and type(right) == "table"
            and left.pos0 ~= nil and left.pos1 ~= nil
            and PositionUtils.equal(left.pos0, right.pos0)
            and PositionUtils.equal(left.pos1, right.pos1)
    end

    if is_integer(index) and type(annotations[index]) == "table" then
        local indexed = annotations[index]
        if selection == nil or indexed == selection
            or same_position(indexed, selection) then
            return index, indexed
        end
    end

    local live_selection = hl.selected_text
    for i, annotation in ipairs(annotations) do
        if annotation == selection or annotation == live_selection then
            return i, annotation
        end
    end

    local function resolve_by_position(candidate)
        if type(candidate) == "table" then
            for i, annotation in ipairs(annotations) do
                if same_position(annotation, candidate) then
                    return i, annotation
                end
            end
        end
        return nil, nil
    end

    local position_index, annotation = resolve_by_position(selection)
    if position_index then return position_index, annotation end
    if live_selection ~= selection then
        position_index, annotation = resolve_by_position(live_selection)
        if position_index then return position_index, annotation end
    end

    return nil, nil
end

function HighlightMenuReopen.decide(hl, index, selection)
    local resolved_index, annotation =
        HighlightMenuReopen.resolve_annotation(hl, index, selection)
    if resolved_index then
        return "highlight_menu", resolved_index, annotation
    end
    return "fallback", nil, nil
end

function HighlightMenuReopen.reopen(hl, index, selection, opts)
    opts = opts or {}
    local ui = type(hl) == "table" and hl.ui or nil
    local schedule = opts.schedule or function(callback) callback() end

    schedule(function()
        if not HighlightMenuReopen.is_current(hl, ui) then return end

        local action, resolved_index, annotation =
            HighlightMenuReopen.decide(hl, index, selection)
        if selection ~= nil then
            hl.selected_text = selection
        elseif action == "highlight_menu" and hl.selected_text == nil then
            local clone = opts.clone or function(value) return value end
            hl.selected_text = clone(annotation)
        end

        if action == "highlight_menu"
            and type(hl.onShowHighlightMenu) == "function" then
            hl:onShowHighlightMenu(resolved_index)
            return
        end

        if type(opts.open_fallback) == "function" then
            opts.open_fallback()
        elseif type(opts.on_unresolved) == "function" then
            opts.on_unresolved()
        end
    end)
end

return HighlightMenuReopen
