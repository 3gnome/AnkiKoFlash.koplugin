#!/usr/bin/env luajit

local function run_tests(assert_eq, assert_true)
    local TestSupport = require("test_support")
    local names = {
        "highlight_inbox",
        "ui/network/manager",
        "ui/widget/menu",
        "ui/widget/notification",
        "ui/uimanager",
        "ui/widget/confirmbox",
        "gettext",
        "card_generator",
        "card_fields",
        "card_storage",
        "card_defaults",
        "send_flow",
        "dictionary_lookup",
        "poetry_memorize",
        "plugin_constants",
        "reading_location",
        "selection_context",
        "highlight_books",
        "plugin_peers",
        "batch_generation",
        "nav",
        "selectable_menu",
    }
    return TestSupport.with_package_loaded(names, {}, function()
        for _, name in ipairs(names) do
            package.loaded[name] = {}
        end
        package.loaded["gettext"] = function(text) return text end
        package.loaded["selection_context"] = function() return "" end

        local extraction_calls = 0
        local deleted_phrase, deleted_document, deleted_pos0, deleted_pos1
        package.loaded["card_storage"] = {
            delete_by_phrase_in_document = function(
                phrase, document_path, pos0, pos1)
                deleted_phrase = phrase
                deleted_document = document_path
                deleted_pos0 = pos0
                deleted_pos1 = pos1
                return true
            end,
        }
        package.loaded["poetry_memorize"] = {
            prepare_text = function(text, max_len)
                if max_len and #text > max_len then return text:sub(1, max_len) end
                return text
            end,
            extract_selection_text = function(ui, opts)
                extraction_calls = extraction_calls + 1
                return ui.document:getHTMLFromXPointers(opts.pos0, opts.pos1)
            end,
        }
        package.loaded["highlight_inbox"] = nil
        local HighlightInbox = require("highlight_inbox")

        local matching_pos0 = "/body/DocFragment[4]"
        local matching_pos1 = "/body/DocFragment[5]"
        local ui = {
            document = {
                file = "/books/current.epub",
                getHTMLFromXPointers = function(_, pos0, pos1)
                    assert_eq(pos0, matching_pos0,
                        "current extraction receives matching pos0")
                    assert_eq(pos1, matching_pos1,
                        "current extraction receives matching pos1")
                    return "text from current open document"
                end,
            },
        }
        local foreign_highlight = {
            text = "stored text from other book",
            ann = { pos0 = matching_pos0, pos1 = matching_pos1 },
        }

        local text = HighlightInbox.passage_text(ui, foreign_highlight, {
            path = "/books/other.epub",
            is_current = true,
        }, 2000)
        assert_eq(text, "stored text from other book",
            "cross-book matching xpointers use stored annotation text")
        assert_eq(extraction_calls, 0,
            "mismatched document identity never invokes current document extraction")

        text = HighlightInbox.passage_text(ui, foreign_highlight, {
            path = "/books/current.epub",
            is_current = false,
        }, 2000)
        assert_eq(text, "text from current open document",
            "exact selected/open document identity allows extraction")
        assert_eq(extraction_calls, 1,
            "exact document identity invokes extraction once")
        assert_true(text ~= foreign_highlight.text,
            "current-document extraction remains available when identities match")

        assert_true(HighlightInbox.delete_pending_for_highlight(
            "shared phrase", "/books/current.epub",
            matching_pos0, matching_pos1),
            "inbox pending-card deletion delegates successfully")
        assert_eq(deleted_phrase, "shared phrase",
            "inbox deletion keeps exact selected phrase")
        assert_eq(deleted_document, "/books/current.epub",
            "inbox deletion always supplies selected document identity")
        assert_eq(deleted_pos0, matching_pos0,
            "inbox deletion supplies selected structural pos0")
        assert_eq(deleted_pos1, matching_pos1,
            "inbox deletion supplies selected structural pos1")

        local carded = HighlightInbox.already_carded_from_cards({
            {
                phrase = "Repeated phrase",
                document_path = "/books/current.epub",
                highlight_pos0 = "/pos/a",
                highlight_pos1 = "/pos/b",
            },
            {
                phrase = "Legacy phrase",
                document_path = "/books/current.epub",
            },
        })
        assert_true(HighlightInbox.is_already_carded(
            carded,
            { text = "Repeated phrase", ann = { pos0 = "/pos/a", pos1 = "/pos/b" } },
            { path = "/books/current.epub" }),
            "same document and same position is already carded")
        assert_true(not HighlightInbox.is_already_carded(
            carded,
            { text = "Repeated phrase", ann = { pos0 = "/pos/c", pos1 = "/pos/d" } },
            { path = "/books/current.epub" }),
            "same phrase at another position is not already carded")
        assert_true(not HighlightInbox.is_already_carded(
            carded,
            { text = "Repeated phrase", ann = { pos0 = "/pos/a", pos1 = "/pos/b" } },
            { path = "/books/other.epub" }),
            "same phrase and position in another document is not already carded")
        assert_true(HighlightInbox.is_already_carded(
            carded,
            { text = "Legacy phrase", ann = { pos0 = "/pos/legacy", pos1 = "/pos/end" } },
            { path = "/books/current.epub" }),
            "legacy same-document phrase fallback remains available")
        assert_true(not HighlightInbox.is_already_carded(
            carded,
            { text = "Legacy phrase", ann = { pos0 = "/pos/legacy", pos1 = "/pos/end" } },
            { path = "/books/other.epub" }),
            "legacy phrase fallback is document-scoped")
    end)
end

return run_tests
