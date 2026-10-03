#!/usr/bin/env luajit

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[deep_copy(key)] = deep_copy(child)
    end
    return copy
end

local function run_tests(assert_eq, assert_true)
    local json = require("json")
    local PositionUtils = require("position_utils")

    assert_true(PositionUtils.equal("/body/DocFragment[1]", "/body/DocFragment[1]"),
        "string positions compare by value")
    assert_true(not PositionUtils.equal("/body/DocFragment[1]", "/body/DocFragment[2]"),
        "different string positions remain distinct")

    local pdf_position = {
        page = 42,
        x = 120.5,
        y = 388.25,
        zoom = 1.25,
        rect = { x0 = 120.5, y0 = 388.25, x1 = 240, y1 = 410 },
    }
    local copied = deep_copy(pdf_position)
    local round_tripped = json.decode(json.encode(pdf_position))

    assert_true(PositionUtils.equal(pdf_position, copied),
        "deep-copied PDF positions compare structurally")
    assert_true(PositionUtils.equal(pdf_position, round_tripped),
        "JSON-roundtrip PDF positions compare structurally")
    assert_eq(PositionUtils.key(pdf_position), PositionUtils.key(copied),
        "deep-copied PDF positions have stable keys")
    assert_eq(PositionUtils.key(pdf_position), PositionUtils.key(round_tripped),
        "JSON-roundtrip PDF positions have stable keys")

    local HighlightStatus = require("highlight_status")
    local annotation = {
        pos0 = pdf_position,
        pos1 = { page = 42, x = 240, y = 410 },
        color = "orange",
    }
    local deleted_index
    local ui = {
        annotation = { annotations = { annotation } },
        highlight = {
            deleteHighlight = function(_, index) deleted_index = index end,
        },
    }
    HighlightStatus.mark_sent(
        ui, round_tripped, json.decode(json.encode(annotation.pos1)))
    assert_eq(annotation.color, "green",
        "highlight status matches JSON-roundtrip PDF positions")
    assert_true(HighlightStatus.remove_highlight(
        ui, deep_copy(pdf_position), deep_copy(annotation.pos1)),
        "highlight removal matches deep-copied PDF positions")
    assert_eq(deleted_index, 1,
        "structural highlight removal targets the matching annotation")

    copied.rect.x1 = 241
    assert_true(not PositionUtils.equal(pdf_position, copied),
        "changed nested PDF fields do not compare equal")
end

return run_tests
