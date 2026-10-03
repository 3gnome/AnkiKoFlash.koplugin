#!/usr/bin/env luajit

local function fixture(annotations)
    local ui = {
        annotation = { annotations = annotations or {} },
    }
    local hl = { ui = ui }
    ui.highlight = hl
    return hl, ui
end

local function run_tests(assert_eq, assert_true)
    local json = require("json")
    local Reopen = require("highlight_menu_reopen")

    local first = { text = "first", pos0 = "a", pos1 = "b" }
    local second = { text = "second", pos0 = "c", pos1 = "d" }
    local hl = fixture({ first, second })

    local index, annotation = Reopen.resolve_annotation(hl, 2, nil)
    assert_eq(index, 2, "valid annotation index is preserved")
    assert_true(annotation == second, "valid index returns its annotation")

    index = Reopen.resolve_annotation(hl, nil, first)
    assert_eq(index, 1, "missing index resolves by annotation identity")

    index = Reopen.resolve_annotation(hl, nil, { pos0 = "c", pos1 = "d" })
    assert_eq(index, 2, "missing index resolves by selection positions")

    local pdf_annotation = {
        text = "pdf",
        pos0 = { page = 4, x = 20, y = 30 },
        pos1 = { page = 4, x = 80, y = 30 },
    }
    local pdf_hl = fixture({ pdf_annotation })
    local pdf_selection = json.decode(json.encode(pdf_annotation))
    index = Reopen.resolve_annotation(pdf_hl, nil, pdf_selection)
    assert_eq(index, 1,
        "JSON-roundtrip PDF selection resolves by structural positions")

    local shifted_first = { text = "inserted", pos0 = "x", pos1 = "y" }
    local shifted_hl = fixture({ shifted_first, first, second })
    index, annotation = Reopen.resolve_annotation(shifted_hl, 2, second)
    assert_eq(index, 3,
        "stale supplied index is rejected when captured selection shifted")
    assert_true(annotation == second,
        "shifted index search preserves captured annotation identity")
    index = Reopen.resolve_annotation(
        shifted_hl, 1, { pos0 = "c", pos1 = "d" })
    assert_eq(index, 3,
        "stale supplied index is rejected using captured positions")

    hl.selected_text = { pos0 = "a", pos1 = "b" }
    index = Reopen.resolve_annotation(hl, nil, nil)
    assert_eq(index, 1, "missing copied selection uses live selection positions")

    local action = Reopen.decide({ ui = {} }, nil, nil)
    assert_eq(action, "fallback", "missing annotation UI selects safe fallback")

    local scheduled
    local shown_index
    function hl:onShowHighlightMenu(resolved_index)
        shown_index = resolved_index
    end
    Reopen.reopen(hl, 2, nil, {
        schedule = function(callback) scheduled = callback end,
    })
    scheduled()
    assert_eq(shown_index, 2, "valid reopen shows highlight menu")
    assert_true(shown_index ~= nil, "reopen never passes a nil index")

    local fresh_hl = fixture({})
    local fresh_selection = { text = "fresh selection" }
    local fallback_count = 0
    function fresh_hl:onShowHighlightMenu()
        error("nil-index highlight menu must not be called")
    end
    Reopen.reopen(fresh_hl, nil, fresh_selection, {
        open_fallback = function() fallback_count = fallback_count + 1 end,
    })
    assert_eq(fallback_count, 1, "unresolved fresh selection opens fallback")
    assert_true(fresh_hl.selected_text == fresh_selection,
        "unresolved selection is restored before fallback")

    local stale_hl, stale_ui = fixture({ first })
    local stale_callback
    local stale_shown, stale_fallback = 0, 0
    function stale_hl:onShowHighlightMenu()
        stale_shown = stale_shown + 1
    end
    Reopen.reopen(stale_hl, 1, nil, {
        schedule = function(callback) stale_callback = callback end,
        open_fallback = function() stale_fallback = stale_fallback + 1 end,
    })
    stale_ui.highlight = {}
    stale_callback()
    assert_eq(stale_shown, 0, "stale delayed callback does not reopen menu")
    assert_eq(stale_fallback, 0, "stale delayed callback does not open fallback")
end

return run_tests
