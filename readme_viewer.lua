-- Scrollable in-app README viewer (loads docs/*.md from the plugin folder).

local Blitbuffer       = require("ffi/blitbuffer")
local ButtonTable      = require("ui/widget/buttontable")
local Device           = require("device")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local GestureRange     = require("ui/gesturerange")
local InfoMessage      = require("ui/widget/infomessage")
local InputContainer   = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size             = require("ui/size")
local TitleBar         = require("ui/widget/titlebar")
local UIManager        = require("ui/uimanager")
local VerticalGroup    = require("ui/widget/verticalgroup")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local _                = require("gettext")

local Nav = require("nav")

local ReadmeViewer = {}

ReadmeViewer.DOCS = {
    vocabulary = {
        title = _("Vocabulary Card — Anki setup"),
        files = { "docs/in-app/vocabulary-card.md", "docs/anki-vocabulary-card.md" },
        desktop = {
            file  = "docs/desktop/vocabulary-card-anki-templates.txt",
            guide = "docs/anki-vocabulary-card.md",
        },
    },
    memorization = {
        title = _("Memorization — Anki setup"),
        files = { "docs/in-app/memorization.md", "docs/anki-memorization.md" },
        desktop = {
            file  = "docs/desktop/memorization-anki-templates.txt",
            guide = "docs/anki-memorization.md",
        },
    },
    getting_started = {
        title = _("Getting started"),
        files = { "docs/getting-started.md" },
        desktop = {
            guide = "docs/getting-started.md",
        },
    },
    plugin_config = {
        title = _("Plugin configuration"),
        files = { "docs/plugin-configuration.md" },
        desktop = {
            guide = "docs/plugin-configuration.md",
        },
    },
    settings = {
        title = _("Settings — help"),
        files = { "docs/in-app/settings-ui.md" },
        desktop = {
            guide = "docs/plugin-configuration.md",
        },
    },
}

ReadmeViewer.MODE_IDS = {
    vocabulary   = "vocabulary",
    memorization = "memorization",
}

local FALLBACK = {
    vocabulary = _([[
Vocabulary Card

Anki note type: Vocabulary Card
Fields: Phrase, Definition, Etymology, Context, Source

On your computer, open docs/desktop/vocabulary-card-anki-templates.txt in a text editor to copy templates and CSS into Anki.

Full guide: docs/anki-vocabulary-card.md]]),

    memorization = _([[
Memorization Card

Anki note type: Memorization

On your computer, open docs/desktop/memorization-anki-templates.txt in a text editor to copy Line/Full templates and CSS into Anki.

Full guide: docs/anki-memorization.md]]),

    getting_started = _([[
Getting started with AnkiKoFlash

1. Install this plugin (.koplugin folder)
2. Set up AnkiConnect on your PC
3. Create matching Anki note types (Vocabulary Card or Memorization)
4. Configure decks in AnkiKoFlash → Settings
5. View all highlights: highlight menu → View All Highlights

See docs/getting-started.md on your PC for the full guide.]]),

    plugin_config = _([[
Plugin configuration

Settings live in configuration.lua (PC) and on-device JSON after you save once.

Configure AnkiConnect URL, default decks, and per-book deck maps in AnkiKoFlash → Settings.

See docs/plugin-configuration.md on your PC for details.]]),
}

local PLUGIN_DIR = (function()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    return src:match("(.-)[/\\][^/\\]+$") or "."
end)()

local function join_path(dir, rel)
    local sep = dir:find("\\") and "\\" or "/"
    if dir:sub(-1) == sep then
        return dir .. rel:gsub("/", sep)
    end
    return dir .. sep .. rel:gsub("/", sep)
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    if not data or data == "" then return nil end
    if data:sub(1, 3) == "\239\187\191" then
        data = data:sub(4)
    end
    return data
end

local function read_first_doc(spec)
    local paths = spec.files or { spec.file }
    for _i, rel in ipairs(paths) do
        local raw = read_file(join_path(PLUGIN_DIR, rel))
        if raw then return raw end
    end
end

local function md_to_plain(md)
    if not md or md == "" then return "" end
    local text = md:gsub("\r\n", "\n")

    text = text:gsub("```[^\n]*\n(.-)```", function(block)
        local lines = 0
        for _line in block:gmatch("\n") do lines = lines + 1 end
        if lines > 12 or #block > 800 then
            return "\n[" .. _("Long template/CSS omitted — copy from docs/desktop/ on your PC") .. "]\n"
        end
        return "\n" .. block:gsub("^%s+", ""):gsub("%s+$", "") .. "\n"
    end)

    text = text:gsub("\n> ", "\n")
    text = text:gsub("%*%*(.-)%*%*", "%1")
    text = text:gsub("__([^_]+)__", "%1")
    text = text:gsub("%*(.-)%*", "%1")
    text = text:gsub("`([^`]+)`", "%1")
    text = text:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
    text = text:gsub("%[([^%]]+)%]%[[^%]]+%]", "%1")

    local out = {}
    local skipped_first_heading = false
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local hashes, title_text = line:match("^(#+)%s+(.*)$")
        if hashes then
            if not skipped_first_heading and #hashes == 1 then
                skipped_first_heading = true
            else
                table.insert(out, "")
                table.insert(out, (title_text or line):upper())
                table.insert(out, string.rep("-", math.min(40, #(title_text or line))))
            end
        elseif line:match("^|") and line:match("|%s*%-") then
            -- table separator row — skip
        elseif line:match("^|") then
            local cells = {}
            for cell in line:gmatch("|([^|]*)") do
                cell = cell:match("^%s*(.-)%s*$") or ""
                if cell ~= "" then table.insert(cells, cell) end
            end
            if #cells > 0 then
                table.insert(out, "  " .. table.concat(cells, " · "))
            end
        elseif line:match("^%- ") or line:match("^%* ") or line:match("^%d+%. ") then
            table.insert(out, "  • " .. (line:gsub("^[%*%-%d%.]+%s*", "")))
        else
            table.insert(out, line)
        end
    end

    text = table.concat(out, "\n")
    text = text:gsub("\n\n\n+", "\n\n")
    return text:match("^%s*(.-)%s*$") or text
end

local function reader_notice(spec)
    if not spec or not spec.desktop then return "" end
    local desk = spec.desktop
    if desk.file then
        return _([[
COPY-PASTE TEMPLATES ON YOUR COMPUTER

Copy front/back templates and CSS on your computer — not on this device.

Open the plugin folder in a text editor and use:

  ]]) .. desk.file .. _([[

Each section is labeled (front template, back template, styling). Select a block and paste it into Anki → Tools → Manage Note Types → Cards.

For deck options and field setup, see the full guide:
  ]]) .. (desk.guide or "") .. "\n\n" .. string.rep("-", 44) .. "\n\n"
    end
    if desk.guide then
        return _([[
FULL GUIDE ON YOUR COMPUTER

This on-device view may shorten long sections. For the complete guide — including tables, examples, and step-by-step setup — open in a text editor or Markdown viewer on your PC:

  ]]) .. desk.guide .. "\n\n" .. string.rep("-", 44) .. "\n\n"
    end
    return ""
end

function ReadmeViewer.load(readme_id)
    local spec = ReadmeViewer.DOCS[readme_id]
    if not spec then
        return _("README"), FALLBACK.vocabulary or _("No README available.")
    end

    local raw = read_first_doc(spec)
    if raw then
        local body = md_to_plain(raw)
        body = reader_notice(spec) .. body
        return spec.title, body
    end
    local fallback = FALLBACK[readme_id] or _("README file not found.")
    return spec.title, reader_notice(spec) .. fallback
end

function ReadmeViewer.show_or_notify(readme_id, opts)
    local ok, err = pcall(ReadmeViewer.show, readme_id, opts)
    if not ok then
        UIManager:show(InfoMessage:new {
            text    = _("Could not open README: ") .. tostring(err),
            timeout = 5,
        })
    end
end

local ReadmeDialog = InputContainer:extend {
    name  = "ankikoflash_readme_viewer",
    modal = true,
}

function ReadmeDialog:init()
    local Screen = Device.screen
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.region = Geom:new {
        x = 0, y = 0,
        w = screen_w,
        h = screen_h,
    }

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new { x = 0, y = 0, w = screen_w, h = screen_h }
        self.ges_events = {
            TapClose = { GestureRange:new { ges = "tap", range = range } },
            Swipe    = { GestureRange:new { ges = "swipe", range = range } },
        }
    end

    local pad = Size.padding.large
    local border = Size.border.window
    self.width, self.height = Nav.compact_menu_size()
    local title_w = self.width - 2 * border
    local inner_w = title_w - pad * 2

    local titlebar = TitleBar:new {
        width            = title_w,
        align            = "left",
        with_bottom_line = true,
        title            = self.readme_title or _("README"),
        close_callback   = function() self:onClose() end,
        show_parent      = self,
    }

    local title_h = titlebar:getHeight()
    local btn_table = ButtonTable:new {
        width       = inner_w,
        buttons     = {{
            {
                text     = _("Close"),
                callback = function() self:onClose() end,
            },
        }},
        zero_sep    = true,
        show_parent = self,
    }
    local btn_h = btn_table:getSize().h
    local scroll_h = self.height - title_h - btn_h - pad * 2 - border * 2
    scroll_h = math.max(scroll_h, Screen:scaleBySize(120))

    self.scroll_text_w = ScrollTextWidget:new {
        text        = self.readme_body or "",
        face        = Font:getFace("smallinfofont"),
        width       = inner_w,
        height      = scroll_h,
        alignment   = "left",
        dialog      = self,
        show_parent = self,
    }

    self.frame = FrameContainer:new {
        width      = self.width,
        radius     = Size.radius.window,
        padding    = 0,
        margin     = 0,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = border,
        VerticalGroup:new {
            titlebar,
            FrameContainer:new {
                padding    = pad,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                VerticalGroup:new {
                    self.scroll_text_w,
                    btn_table,
                },
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
        align = "center",
        dimen = self.region,
        self.movable,
    }
end

function ReadmeDialog:onShow()
    UIManager:setDirty(nil, "full")
    return true
end

function ReadmeDialog:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function ReadmeDialog:onTapClose(arg, ges_ev)
    if UIManager:getTopmostVisibleWidget() ~= self then
        return true
    end
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function ReadmeDialog:onSwipe(arg, ges)
    if self.scroll_text_w and ges.pos:intersectWith(self.scroll_text_w.dimen) then
        local BD = require("ui/bidi")
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.scroll_text_w:scrollText(1)
            return true
        elseif direction == "east" then
            self.scroll_text_w:scrollText(-1)
            return true
        end
    end
    return true
end

function ReadmeDialog:onClose()
    UIManager:close(self)
    UIManager:scheduleIn(0, function()
        UIManager:setDirty(nil, "full")
    end)
    if self.on_close_callback then
        self.on_close_callback()
    end
    return true
end

function ReadmeViewer.show(readme_id, opts)
    opts = opts or {}
    local title, body = ReadmeViewer.load(readme_id)
    local viewer = ReadmeDialog:new {
        readme_title      = title,
        readme_body       = body,
        on_close_callback = opts.on_close,
    }
    Nav.show(viewer)
    return viewer
end

function ReadmeViewer.show_text(title, body, opts)
    opts = opts or {}
    local viewer = ReadmeDialog:new {
        readme_title      = title or _("Preview"),
        readme_body       = body or "",
        on_close_callback = opts.on_close,
    }
    Nav.show(viewer)
    return viewer
end

function ReadmeViewer.show_text_or_notify(title, body, opts)
    local ok, err = pcall(ReadmeViewer.show_text, title, body, opts)
    if not ok then
        UIManager:show(InfoMessage:new {
            text    = _("Could not open preview: ") .. tostring(err),
            timeout = 5,
        })
    end
end

return ReadmeViewer
