#!/usr/bin/env luajit
-- Run: luajit spec/highlight_cleanup_spec.lua (from plugin root)

local function run_tests(assert_eq, assert_true)
local HighlightCleanup = require("highlight_cleanup")
local PluginConstants = require("plugin_constants")

local now = os.time()
local current_book = "/books/current.epub"

assert_true(not HighlightCleanup.should_remove_annotation(
    { text = "word", color = "green", pos0 = "a", pos1 = "b" },
    { card_kind = "vocabulary", phrase = "word", highlight_pos0 = "a", highlight_pos1 = "b", sent_at = now, document_path = current_book },
    now, current_book
), "green wiki-like never removed")

assert_true(HighlightCleanup.should_remove_annotation(
    { text = "inchoate", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "p0", pos1 = "p1" },
    { card_kind = "vocabulary", phrase = "inchoate", highlight_pos0 = "p0", highlight_pos1 = "p1", sent_at = now, document_path = current_book },
    now, current_book
), "orange vocab with matching positions removed")

assert_true(not HighlightCleanup.should_remove_annotation(
    { text = "inchoate", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "p0", pos1 = "p1" },
    { card_kind = "vocabulary", phrase = "inchoate", highlight_pos0 = "other", highlight_pos1 = "p1", sent_at = now, document_path = current_book },
    now, current_book
), "wrong position not removed")

assert_true(not HighlightCleanup.should_remove_annotation(
    { text = "other", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "p0", pos1 = "p1" },
    { card_kind = "vocabulary", phrase = "inchoate", highlight_pos0 = "p0", highlight_pos1 = "p1", sent_at = now, document_path = current_book },
    now, current_book
), "phrase mismatch not removed")

assert_true(not HighlightCleanup.should_remove_annotation(
    { text = "word", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "a", pos1 = "b" },
    { card_kind = "wiki", phrase = "word", highlight_pos0 = "a", highlight_pos1 = "b", sent_at = now, document_path = current_book },
    now, current_book
), "wiki recent entry never removed")

assert_true(not HighlightCleanup.should_remove_annotation(
    { text = "word", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "a", pos1 = "b" },
    { card_kind = "vocabulary", phrase = "word", highlight_pos0 = "a", highlight_pos1 = "b", sent_at = now },
    now, current_book
), "legacy recent entry without document identity is skipped")

assert_true(not HighlightCleanup.should_remove_annotation(
    { text = "word", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "a", pos1 = "b" },
    { card_kind = "vocabulary", phrase = "word", highlight_pos0 = "a", highlight_pos1 = "b", sent_at = now, document_path = "/books/other.epub" },
    now, current_book
), "cross-book recent entry cannot remove current-book highlight")

local memorization_entry = {
    card_kind = "memorization",
    phrase = "Memorization: generated display label",
    memorization_text = "Actual\nstored passage",
    highlight_pos0 = "m0",
    highlight_pos1 = "m1",
    sent_at = now,
    document_path = current_book,
}
assert_true(HighlightCleanup.should_remove_annotation(
    {
        text = "Actual stored passage",
        color = PluginConstants.HIGHLIGHT_COLOR_SAVED,
        pos0 = "m0",
        pos1 = "m1",
    },
    memorization_entry, now, current_book
), "same-document background cleanup matches memorization passage text")
assert_true(not HighlightCleanup.should_remove_annotation(
    {
        text = "Memorization: generated display label",
        color = PluginConstants.HIGHLIGHT_COLOR_SAVED,
        pos0 = "m0",
        pos1 = "m1",
    },
    memorization_entry, now, current_book
), "memorization cleanup never matches the generated display label")
assert_true(not HighlightCleanup.should_remove_annotation(
    {
        text = "Actual stored passage",
        color = PluginConstants.HIGHLIGHT_COLOR_SAVED,
        pos0 = "m0",
        pos1 = "m1",
    },
    memorization_entry, now, "/books/other.epub"
), "memorization cleanup is safe across documents")
assert_true(not HighlightCleanup.should_remove_annotation(
    {
        text = "Actual stored passage",
        color = PluginConstants.HIGHLIGHT_COLOR_SAVED,
        pos0 = "m0",
        pos1 = "m1",
    },
    {
        card_kind = "memorization",
        phrase = "Memorization: legacy",
        highlight_pos0 = "m0",
        highlight_pos1 = "m1",
        sent_at = now,
        document_path = current_book,
    }, now, current_book
), "legacy memorization history without passage text is skipped")

local positions = HighlightCleanup.find_removable_positions({
    { text = "alpha", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "x", pos1 = "y" },
    { text = "beta", color = PluginConstants.HIGHLIGHT_COLOR_SAVED, pos0 = "m", pos1 = "n" },
}, {
    {
        card_kind = "memorization",
        phrase = "Memorization: beta",
        memorization_text = "beta",
        highlight_pos0 = "m",
        highlight_pos1 = "n",
        sent_at = now,
        document_path = current_book,
    },
}, now, current_book)
assert_eq(#positions, 1, "same-book recent entry yields one removable position")
assert_eq(positions[1].pos0, "m", "correct pos0")

local pdf_pos0 = { page = 5, x = 10, y = 20 }
local pdf_pos1 = { page = 5, x = 90, y = 20 }
positions = HighlightCleanup.find_removable_positions({
    {
        text = "pdf word",
        color = PluginConstants.HIGHLIGHT_COLOR_SAVED,
        pos0 = { page = 5, x = 10, y = 20 },
        pos1 = { page = 5, x = 90, y = 20 },
    },
}, {
    {
        card_kind = "vocabulary",
        phrase = "pdf word",
        highlight_pos0 = pdf_pos0,
        highlight_pos1 = pdf_pos1,
        sent_at = now,
        document_path = current_book,
    },
    {
        card_kind = "vocabulary",
        phrase = "pdf word",
        highlight_pos0 = { page = 5, x = 10, y = 20 },
        highlight_pos1 = { page = 5, x = 90, y = 20 },
        sent_at = now,
        document_path = current_book,
    },
}, now, current_book)
assert_eq(#positions, 1,
    "structurally equal PDF positions deduplicate without table pointers")
end

if arg and arg[0] and arg[0]:match("highlight_cleanup_spec%.lua$") then
    local root = arg[0]:match("(.*)[/\\]") or "."
    package.path = package.path .. ";" .. root .. "/?.lua;" .. root .. "/../?.lua"
    local passed, failed = 0, 0
    local function assert_true(c, msg)
        if not c then failed = failed + 1; print("FAIL:", msg); return end
        passed = passed + 1
    end
    local function assert_eq(a, e, msg)
        if a ~= e then failed = failed + 1; print("FAIL:", msg, "expected", e, "got", a); return end
        passed = passed + 1
    end
    run_tests(assert_eq, assert_true)
    print(string.format("Results: %d passed, %d failed", passed, failed))
    os.exit(failed > 0 and 1 or 0)
end

return run_tests
