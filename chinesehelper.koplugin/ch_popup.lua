-- The popup shown when a Chinese character (or the pinyin above it) is tapped.
--
-- From the popup both source plugins shared (koreader-interlinear-pinyin's
-- pinyin_popup.lua, copied as koreader-chinese-popup's cp_popup.lua). Built
-- from KOReader's own widgets (TitleBar, TextBoxWidget, ButtonTable) so it
-- looks native and uses KOReader's UI fonts, whose CJK fallback covers the
-- characters and whose Noto Sans has the tone marks. Bold uses
-- TextBoxWidget's PTF markers.
--
-- Size: the full screen width minus a small margin each side; as tall as its
-- content, up to the full screen height minus a small margin top and bottom,
-- scrolling only beyond that. Placement: a popup that fits in half the
-- screen goes in the half away from the tapped character, so the text stays
-- visible; a taller one (or one that would still cover the character) is
-- centred and starts with the phrase around the character, the character in
-- bold. Text size: a percentage of the book's text size (the menu's "Popup
-- text size").

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
local Screen = Device.screen

local Model = require("ch_popup_model")

local Popup = InputContainer:extend{
    title = nil,       -- the character
    blocks = nil,      -- the entries (ch_popup_model.lua Model.blocks), and the
                       -- components block (ch_components.lua Components.block)
    labels = nil,      -- source -> label text (Model.SOURCE_LABELS)
    label_mode = "fallback", -- which entries carry a label: "all", "fallback", "none"
    header = nil,      -- PTF phrase around the character (Model.header)
    buttons = nil,     -- ButtonTable rows
    anchor = nil,      -- screen box of the tapped character {x, y, w, h}
    text_px = nil,     -- body text size in screen pixels (nil: KOReader's default)
}

-- Source labels: a small grey line just above an entry, left-aligned.
Popup.LABEL_MIN_PX = 18     -- never smaller than this, in screen pixels
Popup.LABEL_RATIO = 0.62    -- of the popup text size

Popup.BOLD_START = TextBoxWidget.PTF_BOLD_START
Popup.BOLD_END = TextBoxWidget.PTF_BOLD_END

-- Font:getFace scales its size by the screen DPI; text_px is already in
-- screen pixels (from the book's font size), so undo that scaling.
local function unscaled(px)
    local scaled = Screen:scaleBySize(1000)
    if not scaled or scaled <= 0 then return px end
    return px * 1000 / scaled
end

function Popup:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h }
    self.margin = Size.margin.default + Size.padding.default
    self.width = screen_w - 2 * self.margin

    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end

    local face, title_face
    if self.text_px then
        face = Font:getFace("x_smallinfofont", unscaled(self.text_px))
        title_face = Font:getFace("x_smalltfont", unscaled(math.floor(self.text_px * 1.3 + 0.5)))
    else
        face = Font:getFace("x_smallinfofont")
        title_face = Font:getFace("x_smalltfont", 26)
    end
    self.face, self.title_face = face, title_face

    -- Build once without the context header; if the popup turns out tall (or
    -- still covers the character), build again with it.
    self:build(false)
    local y, covers = Model.place(self.frame:getSize().h, screen_h, self.margin, self.anchor)
    if covers and self.header then
        self:build(true)
        y = Model.place(self.frame:getSize().h, screen_h, self.margin, self.anchor)
    end
    local size = self.frame:getSize()
    self.frame_x = math.floor((screen_w - size.w) / 2)
    self.frame_y = y
    -- Tall popups cover most of the page: close them with a flashing refresh
    -- so no ghost of them is left on e-ink.
    self.tall = size.h > screen_h / 2
end

function Popup:build(with_header)
    local screen_h = Screen:getHeight()
    local padding = Size.padding.large
    local inner_w = self.width - 2 * Size.border.window

    local parts = { align = "left" }
    local header_h = 0
    if with_header then
        local header = FrameContainer:new{
            padding = padding, padding_top = Size.padding.default, padding_bottom = Size.padding.default,
            bordersize = 0, margin = 0,
            TextBoxWidget:new{
                text = TextBoxWidget.PTF_HEADER .. self.header,
                face = self.face, width = inner_w - 2 * padding,
            },
        }
        parts[#parts + 1] = header
        parts[#parts + 1] = LineWidget:new{ dimen = Geom:new{ w = inner_w, h = math.max(1, Size.line.thin) } }
        header_h = header:getSize().h + math.max(1, Size.line.thin)
    end
    local titlebar = TitleBar:new{
        width = inner_w,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        title_face = self.title_face,
        title_top_padding = Size.padding.default,
        bottom_v_padding = Size.padding.default,
        show_parent = self,
    }
    parts[#parts + 1] = titlebar
    local button_table = ButtonTable:new{
        width = inner_w - 2 * Size.padding.default,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }

    -- Text area: as tall as the text, up to what the screen leaves.
    local text_w = inner_w - 2 * padding
    local max_h = screen_h - 2 * self.margin - header_h - titlebar:getHeight() - button_table:getSize().h
        - 2 * padding - 2 * Size.border.window
    max_h = math.max(max_h, self.face.size * 3)
    self.scroll = self:body(text_w, max_h)
    parts[#parts + 1] = FrameContainer:new{ padding = padding, bordersize = 0, margin = 0, self.scroll }
    parts[#parts + 1] = CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = button_table:getSize().h },
        button_table,
    }
    self.button_table = button_table
    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new(parts),
    }
    self[1] = self.frame
    self.has_header = with_header
end

-- Should this block carry its source label?
function Popup:labelled(block)
    if self.label_mode == "none" then return false end
    if self.label_mode == "fallback" then return block.source ~= "cedict" end
    return true
end

function Popup:labelPx()
    local px = self.text_px or Screen:scaleBySize(20)
    return math.max(Popup.LABEL_MIN_PX, math.floor(px * Popup.LABEL_RATIO + 0.5))
end

-- The entries, one block each: the source label (when shown) on a small grey
-- line of its own, left-aligned, then the headline (word, reading, markers)
-- and the senses, then an idiom's Chinese short line with its own label. The blocks stack vertically; only when they are taller
-- than the room left do they scroll (ScrollableContainer, with a scroll bar).
function Popup:body(text_w, max_h)
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local label_face = Font:getFace("x_smallinfofont", unscaled(self:labelPx()))
    local block_gap = math.floor(self.face.size * 0.6)
    -- A components block (ch_components.lua) is indented by one em, below
    -- the character's own entry.
    local indent = self.face.size
    local function stack(full_width)
        local group = VerticalGroup:new{ align = "left" }
        for k, b in ipairs(self.blocks or {}) do
            if k > 1 then group[#group + 1] = VerticalSpan:new{ width = block_gap } end
            local width = b.components and full_width - indent or full_width
            local function add(widget)
                if b.components then
                    widget = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = indent }, widget }
                end
                group[#group + 1] = widget
            end
            if self:labelled(b) then
                add(TextWidget:new{
                    text = (self.labels or {})[b.source] or b.source, face = label_face,
                    fgcolor = Blitbuffer.COLOR_GRAY_5, max_width = width,
                })
            end
            if b.head then
                add(TextBoxWidget:new{ text = TextBoxWidget.PTF_HEADER .. b.head, face = self.face, width = width })
            end
            if #b.lines > 0 then
                add(TextBoxWidget:new{
                    text = TextBoxWidget.PTF_HEADER .. table.concat(b.lines, "\n"), face = self.face, width = width,
                })
            end
            if b.note then
                if self:labelled(b.note) then
                    add(TextWidget:new{
                        text = (self.labels or {})[b.note.source] or b.note.source, face = label_face,
                        fgcolor = Blitbuffer.COLOR_GRAY_5, max_width = width,
                    })
                end
                add(TextBoxWidget:new{ text = b.note.text, face = self.face, width = width })
            end
        end
        return group
    end
    local group = stack(text_w)
    if group:getSize().h <= max_h then
        self.scrolls = false
        return group
    end
    -- Too tall: narrower, to leave room for the scroll bar, and scrollable.
    group:free()
    -- (The container keeps 3 bar widths for its vertical bar; any wider and it
    -- adds a horizontal one.)
    group = stack(text_w - ScrollableContainer:getScrollbarWidth())
    self.scrolls = true
    return ScrollableContainer:new{ dimen = Geom:new{ w = text_w, h = max_h }, show_parent = self, group }
end

function Popup:paintTo(bb, x, y)
    self.frame:paintTo(bb, x + self.frame_x, y + self.frame_y)
end

function Popup:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

function Popup:onClose()
    UIManager:close(self, self.tall and "flashpartial" or "partial", self.frame.dimen)
    return true
end

-- A tap outside the popup closes it (and goes no further: it does not also
-- turn the page). Taps inside that no button took are ignored.
function Popup:onTapClose(_, ges)
    if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

return Popup
