-- Full-screen card viewer with front/back experience.
--
-- Vocabulary Card front: highlighted term only.
-- Vocabulary Card back: definition + etymology + context + source.

local BD               = require("ui/bidi")
local Blitbuffer       = require("ffi/blitbuffer")
local ButtonDialog     = require("ui/widget/buttondialog")
local ButtonTable      = require("ui/widget/buttontable")
local CenterContainer  = require("ui/widget/container/centercontainer")
local Device           = require("device")
local Screen           = Device.screen
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local GestureRange     = require("ui/gesturerange")
local InfoMessage      = require("ui/widget/infomessage")
local InputContainer   = require("ui/widget/container/inputcontainer")
local InputDialog      = require("ui/widget/inputdialog")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification     = require("ui/widget/notification")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size             = require("ui/size")
local TitleBar         = require("ui/widget/titlebar")
local UIManager        = require("ui/uimanager")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local _                = require("gettext")

local CardFields       = require("card_fields")
local PluginConstants  = require("plugin_constants")
local SendFlow         = require("send_flow")

local PTF_HEADER     = "\xEF\xBF\xB1"  -- U+FFF1  required prefix to activate PTF parsing
local PTF_BOLD_START = "\xEF\xBF\xB2"  -- U+FFF2
local PTF_BOLD_END   = "\xEF\xBF\xB3"  -- U+FFF3

local function ptf_bold(s)
    return PTF_BOLD_START .. s .. PTF_BOLD_END
end

-- Colors for special fields (tuned for e-ink visibility).
local COLOR_BLUE   = Blitbuffer.ColorRGB32(0x00, 0x3A, 0x75, 0xFF)  -- phrase (back): dark navy blue

local COLOR_GRAY = Blitbuffer.ColorRGB32(0x55, 0x55, 0x55, 0xFF)

-- ── Widget ────────────────────────────────────────────────────────────────────

-- Snapshot props so the viewer can reopen after deck picker / send dialogs.
local function snapshot_viewer_props(viewer)
    return {
        card                  = viewer.card,
        show_back             = viewer.show_back,
        on_show_answer        = viewer.on_show_answer,
        on_show_front         = viewer.on_show_front,
        on_save               = viewer.on_save,
        on_send               = viewer.on_send,
        on_quick_send         = viewer.on_quick_send,
        can_quick_send        = viewer.can_quick_send,
        on_update             = viewer.on_update,
        on_navigate_to_source = viewer.on_navigate_to_source,
        on_change_definition  = viewer.on_change_definition,
        on_highlight_dialog   = viewer.on_highlight_dialog,
        read_only             = viewer.read_only,
    }
end

local CardViewer  -- forward declare for run_anki_send

local function run_anki_send(viewer, send_fn)
    if not send_fn then return end
    local props = snapshot_viewer_props(viewer)
    UIManager:close(viewer)
    UIManager:scheduleIn(0.05, function()
        send_fn(function(ok, err)
            if ok then
                UIManager:show(Notification:new { text = _("Sent to Anki!") })
                return
            end
            UIManager:show(CardViewer:new(props))
            if err and not SendFlow.is_cancelled(err) then
                UIManager:show(InfoMessage:new {
                    text    = _("Anki error: ") .. (err or "unknown"),
                    timeout = 5,
                })
            end
        end)
    end)
end

CardViewer = InputContainer:extend {
    name           = "ankikoflash_card_viewer",
    modal          = true,
    card           = nil,   -- card table: { phrase, definition, etymology, context, source, … }
    show_back      = false, -- false = front (question), true = back (answer)
    on_show_answer = nil,   -- function() — called when user flips to back
    on_show_front  = nil,   -- function() — called when user flips to front
    on_save        = nil,   -- function() -> true | nil, err
    on_send        = nil,   -- function(done) — done(ok, err) after deck picker + send
    on_quick_send  = nil,   -- function(done) — resend with last deck + note type
    can_quick_send = false,
    on_update      = nil,   -- function(card) — called after a field edit (to persist)
    on_navigate_to_source = nil, -- function() — jump to highlight position in book
    on_change_definition = nil, -- function() — pick another dictionary entry (Vocabulary Card)
    on_highlight_dialog = nil, -- function() — open KOReader's native highlight dialog (color, style, delete…)
    read_only      = false,

    text_padding   = Size.padding.large,
    text_margin    = Size.margin.small,
    button_padding = Size.padding.default,
}

function CardViewer:init()
    if self.card then
        CardFields.normalize(self.card, {})
        self.use_rich = CardFields.use_rich_viewer(self.card, {})
    else
        self.use_rich = true
    end

    self.align  = "center"
    self.region = Geom:new {
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local outer_margin = Screen:scaleBySize(16)
    -- On a wide emulator window, don't cap width to the shorter axis.
    if Device.isDesktop or Device.isEmulator then
        self.width = math.min(screen_w - 2 * outer_margin, Screen:scaleBySize(640))
    else
        self.width = math.min(screen_w, screen_h) - Screen:scaleBySize(30)
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new { x=0, y=0, w=Screen:getWidth(), h=Screen:getHeight() }
        self.ges_events = {
            TapClose = { GestureRange:new { ges = "tap",   range = range } },
            Swipe    = { GestureRange:new { ges = "swipe", range = range } },
        }
    end

    local titlebar = TitleBar:new {
        width            = self.width,
        align            = "left",
        with_bottom_line = true,
        title            = PluginConstants.NAME,
        close_callback   = function() self:onClose() end,
        show_parent      = self,
    }

    -- ── Button row ────────────────────────────────────────────────────────────
    local buttons_row = {}

    if not self.show_back then
        -- Front: Show Answer + Close
        table.insert(buttons_row, {
            text     = _("▼ Show Answer"),
            callback = function()
                if self.on_show_answer then self.on_show_answer() end
            end,
        })
        if self.on_highlight_dialog then
            table.insert(buttons_row, {
                text     = _("Highlight"),
                callback = function()
                    self:onClose()
                    self.on_highlight_dialog()
                end,
            })
        end
        table.insert(buttons_row, {
            text     = _("Close"),
            callback = function() self:onClose() end,
        })
    else
        -- Back: full action buttons
        table.insert(buttons_row, {
            text     = _("▲ Show Front"),
            callback = function()
                if self.on_show_front then self.on_show_front() end
            end,
        })

        if not self.read_only then
            table.insert(buttons_row, {
                text     = _("Edit"),
                callback = function() self:showEditDialog() end,
            })
        end

        local CardStorage   = require("card_storage")
        local already_saved = self.card and CardStorage.is_saved(self.card.phrase or "")
        table.insert(buttons_row, {
            id      = "save",
            text    = already_saved and _("✓ Saved") or _("★ Save"),
            enabled = not already_saved,
            callback = function()
                if self.on_save then
                    local ok, err = self.on_save()
                    if ok then
                        UIManager:show(Notification:new { text = _("Saved!") })
                        local btn = self.button_table:getButtonById("save")
                        if btn then btn:disable(); btn:refresh() end
                    else
                        UIManager:show(InfoMessage:new { text = err or _("Could not save"), timeout = 5 })
                    end
                end
            end,
        })

        table.insert(buttons_row, {
            text     = _("→ Anki"),
            callback = function()
                run_anki_send(self, self.on_send)
            end,
        })

        if self.can_quick_send and self.on_quick_send then
            table.insert(buttons_row, {
                text     = _("↻ Send again"),
                callback = function()
                    run_anki_send(self, self.on_quick_send)
                end,
            })
        end

        if not self.read_only and self.on_change_definition then
            table.insert(buttons_row, {
                text     = _("Change def."),
                callback = function() self.on_change_definition() end,
            })
        end

        if self.on_navigate_to_source then
            table.insert(buttons_row, {
                text     = _("Go to"),
                callback = function() self.on_navigate_to_source() end,
            })
        end

        if self.on_highlight_dialog then
            table.insert(buttons_row, {
                text     = _("Highlight"),
                callback = function()
                    self:onClose()
                    self.on_highlight_dialog()
                end,
            })
        end

        table.insert(buttons_row, {
            text     = _("Close"),
            callback = function() self:onClose() end,
        })
    end

    local function split_button_rows(row)
        if #row <= 4 then return { row } end
        local mid = math.ceil(#row / 2)
        local row1, row2 = {}, {}
        for i, btn in ipairs(row) do
            if i <= mid then
                table.insert(row1, btn)
            else
                table.insert(row2, btn)
            end
        end
        return { row1, row2 }
    end

    self.button_table = ButtonTable:new {
        width       = self.width - 2 * self.button_padding,
        buttons     = split_button_rows(buttons_row),
        zero_sep    = true,
        show_parent = self,
    }

    -- ── Content area ──────────────────────────────────────────────────────────
    -- Keep the button bar on screen: content scrolls inside the remaining space.
    local chrome_h = titlebar:getHeight() + self.button_table:getSize().h + outer_margin
    local max_frame_h = screen_h - 2 * outer_margin
    local total_content_h = math.max(
        Screen:scaleBySize(100),
        math.min(Screen:scaleBySize(420), max_frame_h - chrome_h)
    )
    local inner_w = self.width - 2 * self.text_padding - 2 * self.text_margin

    local content_widget

    -- Build a ScrollTextWidget for one content section.
    -- justified=true enables full justification (implies left alignment).
    -- w overrides the default inner_w (used for multi-column layouts).
    local function make_text(text, face, height, color, align, justified, w)
        return ScrollTextWidget:new {
            text      = PTF_HEADER .. (text or ""),  -- header activates PTF bold parsing
            face      = face,
            fgcolor   = color,
            width     = w or inner_w,
            height    = math.max(1, height),
            dialog    = self,
            alignment = justified and "left" or (align or "center"),
            justified = justified or false,
        }
    end

    local function make_section_header(label)
        local header_face = Font:getFace("cfont", 18)
        local label_h = math.max(1, math.floor(Screen:scaleBySize(22)))
        return make_text(ptf_bold(label), header_face, label_h, nil, "left")
    end

    local gap = Size.padding.default
    -- Available height for all content widgets (inside the frame's padding/margin).
    local avail_h = total_content_h - 2 * self.text_padding - 2 * self.text_margin

    local big_gap = gap * 3

    if self.use_rich then
    if not self.show_back then
        local c          = self.card or {}
        local face       = Font:getFace("cfont", 22)
        local text_h     = avail_h - gap * 2
        local phrase_h   = math.max(1, math.floor(text_h * 0.4))

        local phrase_w = make_text(ptf_bold(c.phrase or ""), face, phrase_h, COLOR_BLUE, "center")
        self.scroll_text_w = phrase_w

        content_widget = VerticalGroup:new {
            phrase_w,
        }

    else
        local c             = self.card or {}
        local face          = Font:getFace("smallinfofont")
        local label_h       = math.max(1, math.floor(Screen:scaleBySize(22)))
        local ctx_text      = c.context or ""
        local etymology     = c.etymology or (c.anki_fields and c.anki_fields.Etymology) or ""

        local has_ety       = etymology ~= ""
        local has_ctx       = ctx_text ~= ""
        local section_count = (has_ety and 1 or 0) + (has_ctx and 1 or 0)
        local overhead      = gap * 10 + label_h * (3 + section_count)
        local text_h        = avail_h - overhead
        local phrase_h      = math.max(1, math.floor(text_h * 0.08))
        local def_h         = math.max(1, math.floor(text_h * 0.40))
        local ety_h         = has_ety and math.max(1, math.floor(text_h * 0.24)) or 0
        local ctx_h         = has_ctx and math.max(1, math.floor(text_h * 0.24)) or 0
        local src_h         = math.max(1, text_h - phrase_h - def_h - ety_h - ctx_h)

        local phrase_w      = make_text(ptf_bold(c.phrase or ""), face, phrase_h, COLOR_BLUE, "left")
        local def_w         = make_text(c.definition or "", face, def_h, nil, "left", true)
        local ety_w         = has_ety and make_text(etymology, face, ety_h, nil, "left", true) or nil
        local ctx_w         = make_text(ctx_text, face, ctx_h, nil, "left", true)
        self.scroll_text_w  = def_w

        local def_label = "DEFINITION"
        if c.dictionary_name and c.dictionary_name ~= "" then
            def_label = c.dictionary_name:upper()
        end

        content_widget = VerticalGroup:new {
            phrase_w,
            VerticalSpan:new { width = gap },
        }

        content_widget[#content_widget + 1] = make_section_header(def_label)
        content_widget[#content_widget + 1] = def_w

        if has_ety then
            content_widget[#content_widget + 1] = VerticalSpan:new { width = gap * 2 }
            content_widget[#content_widget + 1] = make_section_header("ETYMOLOGY")
            content_widget[#content_widget + 1] = ety_w
        end

        if has_ctx then
            content_widget[#content_widget + 1] = VerticalSpan:new { width = gap * 2 }
            content_widget[#content_widget + 1] = make_section_header("CONTEXT")
            content_widget[#content_widget + 1] = ctx_w
        end

        if c.source and c.source ~= "" then
            content_widget[#content_widget + 1] = VerticalSpan:new { width = gap * 2 }
            content_widget[#content_widget + 1] = make_section_header("SOURCE")
            content_widget[#content_widget + 1] = make_text(
                c.source, face, src_h, COLOR_GRAY, "left")
        end
    end

    else
        -- ── GENERIC field list (Basic and other note types) ─────────────────
        local c = self.card or {}
        local face = Font:getFace("smallinfofont")
        local fields = {}
        if type(c.anki_fields) == "table" then
            for fname, fval in pairs(c.anki_fields) do
                table.insert(fields, { name = fname, val = fval })
            end
            table.sort(fields, function(a, b) return a.name < b.name end)
        end
        if #fields == 0 then
            fields = {
                { name = "Phrase", val = c.phrase or "" },
                { name = "Definition", val = c.definition or "" },
            }
        end
        local rows = {}
        local row_h = math.max(1, math.floor(avail_h / math.max(#fields + 1, 2)))
        for _i, f in ipairs(fields) do
            if not self.show_back and f.name:lower() ~= "front"
               and f.name:lower() ~= "phrase" and f.name:lower() ~= "word" then
                -- front side: show primary field only
            else
                table.insert(rows, make_section_header(f.name:upper()))
                table.insert(rows, VerticalSpan:new { width = gap })
                table.insert(rows, make_text(f.val or "", face, row_h, nil, "left", true))
                table.insert(rows, VerticalSpan:new { width = gap * 2 })
            end
        end
        if not self.show_back then
            local primary = fields[1]
            for _i, f in ipairs(fields) do
                local n = f.name:lower()
                if n == "front" or n == "phrase" or n == "word" then primary = f; break end
            end
            rows = {
                make_text(ptf_bold(primary and primary.val or c.phrase or ""),
                          Font:getFace("cfont", 22),
                          math.max(1, math.floor(avail_h * 0.4)), COLOR_BLUE, "center"),
            }
            if #fields > 1 and fields[2] then
                rows[#rows + 1] = VerticalSpan:new { width = gap * 2 }
                rows[#rows + 1] = make_text(fields[2].val or "", face,
                    math.max(1, avail_h - math.floor(avail_h * 0.4)), nil, "left")
            end
        end
        content_widget = VerticalGroup:new(rows)
        self.scroll_text_w = rows[#rows]
    end

    self.textw = FrameContainer:new {
        padding    = self.text_padding,
        margin     = self.text_margin,
        bordersize = 0,
        content_widget,
    }

    self.frame = FrameContainer:new {
        radius     = Size.radius.window,
        padding    = 0,
        margin     = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new {
            titlebar,
            CenterContainer:new {
                dimen = Geom:new { w = self.width, h = self.textw:getSize().h },
                self.textw,
            },
            CenterContainer:new {
                dimen = Geom:new { w = self.width, h = self.button_table:getSize().h },
                self.button_table,
            },
        },
    }

    self.movable = MovableContainer:new {
        ignore_events = {
            "swipe", "hold", "hold_release", "hold_pan",
            "touch", "pan", "pan_release",
        },
        self.frame,
    }

    self[1] = WidgetContainer:new {
        align = self.align,
        dimen = self.region,
        self.movable,
    }
end

-- ── Edit flow (back only) ─────────────────────────────────────────────────────

function CardViewer:showEditDialog()
    local sel_dlg
    local field_buttons = {}
    local editable = CardFields.editable_field_list(self.card)
    for _i, f in ipairs(editable) do
        local fref = f
        table.insert(field_buttons, {{
            text     = _(fref.label),
            callback = function()
                UIManager:close(sel_dlg)
                self:editField(fref)
            end,
        }})
    end
    table.insert(field_buttons, {{
        text     = _("Cancel"),
        callback = function() UIManager:close(sel_dlg) end,
    }})
    sel_dlg = ButtonDialog:new {
        title   = _("Edit field"),
        buttons = field_buttons,
    }
    UIManager:show(sel_dlg)
end

function CardViewer:editField(field_def)
    local current
    if field_def.anki and self.card and self.card.anki_fields then
        current = self.card.anki_fields[field_def.key] or ""
    else
        current = self.card and self.card[field_def.key] or ""
    end
    local input_dlg
    input_dlg = InputDialog:new {
        title   = _("Edit: ") .. field_def.label,
        input   = current,
        buttons = {{
            {
                text     = _("Cancel"),
                callback = function() UIManager:close(input_dlg) end,
            },
            {
                text             = _("OK"),
                is_enter_default = true,
                callback         = function()
                    local new_val = input_dlg:getInputText() or ""
                    UIManager:close(input_dlg)
                    UIManager:scheduleIn(0, function()
                        local old_phrase = self.card.phrase
                        if field_def.anki then
                            self.card.anki_fields = self.card.anki_fields or {}
                            self.card.anki_fields[field_def.key] = new_val
                            CardFields.sync_flat_from_anki(self.card)
                        else
                            self.card[field_def.key] = new_val
                        end
                        local phrase_changed = (field_def.key == "phrase" or field_def.key == "Phrase")
                                               and new_val ~= old_phrase
                        if phrase_changed then
                            CardFields.apply_reading_source(
                                self.card,
                                self.card.book_title,
                                self.card.book_author)
                        end
                        if self.on_update then self.on_update(self.card) end
                        self:update()
                    end)
                end,
            },
        }},
    }
    UIManager:show(input_dlg)
    input_dlg:onShowKeyboard()
end

-- ── Update (close+recreate) ───────────────────────────────────────────────────

-- Closes this viewer and opens a fresh one with the (possibly updated) card.
-- Preserves show_back state unless new_show_back is explicitly passed.
function CardViewer:update(new_card, new_show_back)
    local card      = new_card or self.card
    local show_back = new_show_back ~= nil and new_show_back or self.show_back
    UIManager:close(self)
    local updated = CardViewer:new {
        card                  = card,
        show_back             = show_back,
        on_show_answer        = self.on_show_answer,
        on_show_front         = self.on_show_front,
        on_save               = self.on_save,
        on_send               = self.on_send,
        on_quick_send         = self.on_quick_send,
        can_quick_send        = self.can_quick_send,
        on_update             = self.on_update,
        on_navigate_to_source = self.on_navigate_to_source,
        on_change_definition  = self.on_change_definition,
        on_highlight_dialog   = self.on_highlight_dialog,
        read_only             = self.read_only,
    }
    UIManager:show(updated)
    return updated
end

-- ── Event handlers ────────────────────────────────────────────────────────────

function CardViewer:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
end

function CardViewer:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
    return true
end

function CardViewer:onTapClose(arg, ges_ev)
    if UIManager:getTopmostVisibleWidget() ~= self then
        return true
    end
    if self.frame and self.frame.dimen and ges_ev and ges_ev.pos
       and ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function CardViewer:onSwipe(arg, ges)
    if self.textw and self.textw.dimen and self.scroll_text_w
       and ges.pos:intersectWith(self.textw.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.scroll_text_w:scrollText(1)
            return true
        elseif direction == "east" then
            self.scroll_text_w:scrollText(-1)
            return true
        else
            UIManager:setDirty(nil, "full")
            return false
        end
    end
    return self.movable:onMovableSwipe(arg, ges)
end

function CardViewer:onClose()
    UIManager:close(self)
    UIManager:scheduleIn(0, function()
        UIManager:setDirty(nil, "full")
    end)
    return true
end

return CardViewer
