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
-- centred. The first line (when on) is the text around the character on the
-- page, the character bold and underlined, at the popup's text size
-- (ch_snippet.lua picks what fits). Text size: a percentage of the book's
-- text size (the menu's "Popup text size").

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
local Snippet = require("ch_snippet")
local Widget = require("ui/widget/widget")

local Popup = InputContainer:extend{
    title = nil,       -- the character
    blocks = nil,      -- the entries (ch_popup_model.lua Model.blocks), and the
                       -- components block (ch_components.lua Components.block)
    labels = nil,      -- source -> label text (Model.SOURCE_LABELS)
    label_mode = "fallback", -- which entries carry a label: "all", "fallback", "none"
    context = nil,     -- page text around the tap (ch_tap.lua Tap:context), or nil
    on_close = nil,    -- called when the popup closes, however it closes
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

    self:build()
    local y = Model.place(self.frame:getSize().h, screen_h, self.margin, self.anchor)
    local size = self.frame:getSize()
    self.frame_x = math.floor((screen_w - size.w) / 2)
    self.frame_y = y
    -- Tall popups cover most of the page: close them with a flashing refresh
    -- so no ghost of them is left on e-ink.
    self.tall = size.h > screen_h / 2
end

function Popup:build()
    local screen_h = Screen:getHeight()
    local padding = Size.padding.large
    local inner_w = self.width - 2 * Size.border.window

    local parts = { align = "left" }
    local header_h = 0
    local line = self.context and Popup.contextLine(self.context, nil, self.face, inner_w - 2 * padding)
    if line then
        local header = FrameContainer:new{
            padding = padding, padding_top = Size.padding.default, padding_bottom = Size.padding.default,
            bordersize = 0, margin = 0,
            line,
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
    self.has_context = line ~= nil
end

-- Text with a line under it (the marked character or word of the context
-- line): the line sits just under the baseline, in the descender space.
local Underlined = Widget:extend{ text_widget = nil, thick = 2, offset = 0 }

function Underlined:getSize()
    local size = self.text_widget:getSize()
    local bottom = self.text_widget:getBaseline() + self.offset + self.thick
    return Geom:new{ w = size.w, h = math.max(size.h, bottom) }
end

function Underlined:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self:getSize().w, h = self:getSize().h }
    self.text_widget:paintTo(bb, x, y)
    bb:paintRect(x, y + self.text_widget:getBaseline() + self.offset, self.text_widget:getSize().w, self.thick,
        Blitbuffer.COLOR_BLACK)
end

function Underlined:free() self.text_widget:free() end

--[[--
The context line as a widget, at most `width` pixels wide, or nil: the text
before, the marked character or word (bold, underlined), the text after.
  context  { chars=, index= } (ch_tap.lua Tap:context)
  word     { text=, start= } to mark a word instead (Snippet.select), or nil
  face     the font face (the popup's text face: same size as the entries)
]]
function Popup.contextLine(context, word, face, width)
    local function measure(s, bold)
        if s == "" then return 0 end
        local w = TextWidget:new{ text = s, face = face, bold = bold }
        local px = w:getSize().w
        w:free()
        return px
    end
    local sel = Snippet.select{ chars = context.chars, index = context.index, word = word,
                                measure = measure, width = width }
    if not sel or sel.mark == "" then return nil end
    local group = HorizontalGroup:new{ align = "top" }
    local used = 0
    local function add(widget)
        group[#group + 1] = widget
        used = used + widget:getSize().w
    end
    if sel.before ~= "" then add(TextWidget:new{ text = sel.before, face = face, max_width = width }) end
    local size = face.size
    add(Underlined:new{
        text_widget = TextWidget:new{ text = sel.mark, face = face, bold = true, max_width = math.max(1, width - used) },
        thick = math.max(2, math.floor(size / 10 + 0.5)),
        offset = math.max(2, math.floor(size * 0.12 + 0.5)),
    })
    if sel.after ~= "" and width - used > 0 then
        add(TextWidget:new{ text = sel.after, face = face, max_width = width - used })
    end
    return group
end

--[[--
Put the context line under the title of KOReader's dictionary popup `dql`
(a DictQuickLookup just built, for a lookup from one of our popups' word
buttons), with `word` marked. The popup keeps its height, and so the place
KOReader chose for it (clear of the looked-up word when it could): the
definition, which scrolls, gives up whole lines for the line. Skipped when
that would leave it fewer than MIN_DICT_LINES.
]]
Popup.MIN_DICT_LINES = 3

function Popup.addContextToDict(dql, context, word)
    local frame = dql.dict_frame
    local group = frame and frame[1]
    local line_h = dql.definition_line_height
    if not group or not dql.content_width or not dql.content_face or not line_h or line_h <= 0
            or not dql.definition_height or not dql.definition_widget or not dql._instantiateScrollWidget then
        return
    end
    local line = Popup.contextLine(context, word, dql.content_face, dql.content_width)
    if not line then return end
    local pad_top = Size.padding.default
    local row_h = line:getSize().h + pad_top
    local cut = math.ceil(row_h / line_h) * line_h
    if dql.definition_height - cut < Popup.MIN_DICT_LINES * line_h then
        line:free()
        return
    end
    -- The definition, rebuilt shorter (DictQuickLookup:update reuses it, so
    -- the other dictionaries' results keep the height).
    local container
    for _, child in ipairs(group) do
        if child[1] == dql.definition_widget then container = child end
    end
    if not container or not container.dimen then
        line:free()
        return
    end
    if dql.text_widget and dql.text_widget.free then dql.text_widget:free() end
    dql.definition_height = dql.definition_height - cut
    dql:_instantiateScrollWidget()
    dql.definition_widget[1] = dql.text_widget
    container.dimen.h = dql.definition_widget:getSize().h
    table.insert(group, 2, FrameContainer:new{
        padding = 0, padding_left = Size.padding.large, padding_right = Size.padding.large,
        padding_top = pad_top, bordersize = 0, margin = 0,
        line,
    })
    -- What is left of the lines given up goes under the definition.
    for k, child in ipairs(group) do
        if child == container then
            table.insert(group, k + 1, VerticalSpan:new{ width = cut - row_h })
            break
        end
    end
    group:resetLayout()
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

function Popup:onCloseWidget()
    if self.on_close then
        local f = self.on_close
        self.on_close = nil
        f()
    end
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
