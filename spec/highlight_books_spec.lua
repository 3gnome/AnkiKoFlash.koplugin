#!/usr/bin/env luajit
-- Run: luajit spec/highlight_books_spec.lua (from plugin root)

local function run_tests(assert_eq, assert_true)

package.loaded["readhistory"] = {
    hist = {
        { file = "/books/alice.epub", text = "alice.epub", select_enabled = true },
        { file = "/books/empty.epub", text = "empty.epub", select_enabled = true },
    },
    reload = function() end,
}

local sidecars = {
    ["/books/alice.epub"] = {
        { drawer = "lighten", text = "quote one", chapter = "Ch1" },
        { drawer = "lighten", text = "quote two" },
    },
    ["/books/empty.epub"] = {},
    ["/books/current.epub"] = {
        { drawer = "lighten", text = "live only" },
    },
}

package.loaded["docsettings"] = {
    open = function(_, path)
        return {
            readSetting = function(self, key)
                if key == "annotations" then
                    return sidecars[path] or {}
                end
                if key == "doc_props" and path == "/books/alice.epub" then
                    return { title = "Alice", authors = { "Carroll" } }
                end
                return nil
            end,
        }
    end,
}

_G.lfs = {
    attributes = function(path, attr)
        if attr == "mode" and path and path:match("%.epub$") then
            return "file"
        end
        return nil
    end,
}

local HighlightBooks = require("highlight_books")

assert_eq(HighlightBooks.count_highlights(sidecars["/books/alice.epub"]), 2,
    "counts drawer highlights")
assert_true(not HighlightBooks.annotation_is_highlight({ text = "x" }),
    "text alone is not highlight")
assert_true(HighlightBooks.annotation_is_highlight(
    { drawer = "lighten", text = "x" }), "drawer+text is highlight")

local books = HighlightBooks.discover_books_with_highlights("/books/current.epub")
assert_eq(#books, 2, "alice + current in discovery (sidecar)")
local found_alice, found_current = false, false
for _, b in ipairs(books) do
    if b.path == "/books/alice.epub" then
        found_alice = true
        assert_eq(b.count, 2, "alice count")
        assert_eq(b.title, "Alice", "alice title from doc_props")
    end
    if b.path == "/books/current.epub" then
        found_current = true
        assert_true(b.is_current, "current flagged")
    end
end
assert_true(found_alice and found_current, "expected books discovered")

local live_ui = {
    document = { file = "/books/current.epub" },
    annotation = { annotations = {
        { drawer = "lighten", text = "from live" },
    } },
}

sidecars["/books/current.epub"] = {}
local books_live = HighlightBooks.discover_books_with_highlights("/books/current.epub", live_ui)
assert_eq(#books_live, 2, "current book counted from live ui when sidecar empty")
for _, b in ipairs(books_live) do
    if b.path == "/books/current.epub" then
        assert_eq(b.count, 1, "live-only current count")
    end
end

local live = HighlightBooks.load_highlights_for_book("/books/current.epub", live_ui)
assert_eq(#live, 1, "live book uses ui annotations")
assert_eq(live[1].ann_index, 1, "live book has ann_index")

local sidecar_only = HighlightBooks.load_highlights_for_book("/books/alice.epub", live_ui)
assert_eq(#sidecar_only, 2, "other book uses sidecar")
assert_eq(sidecar_only[1].ann_index, nil, "sidecar rows omit ann_index")

local meta = HighlightBooks.read_book_metadata("/books/alice.epub")
assert_eq(meta.title, "Alice", "metadata title")
assert_eq(meta.author, "Carroll", "metadata author")

end

if arg and arg[0] and arg[0]:match("highlight_books_spec%.lua$") then
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
