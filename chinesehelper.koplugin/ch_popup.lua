-- The popup shown when a Chinese character (or the pinyin above it) is tapped.
--
-- Built from KOReader's own widgets (TitleBar, TextBoxWidget, ButtonTable) so it
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

local Glyphs = require("ch_glyphs")
local Model = require("ch_popup_model")
local Snippet = require("ch_snippet")
local Widget = require("ui/widget/widget")

local Popup = InputContainer:extend{
    title = nil,       -- the character
    blocks = nil,      -- the entries (ch_popup_model.lua Model.blocks), and the
                       -- components block (ch_components.lua Components.block)
    labels = nil,      -- source -> label text (Model.SOURCE_LABELS)
    label_mode = "all", -- which entries carry a label: "all" or "none"
    context = nil,     -- page text around the tap (ch_tap.lua Tap:context), or nil
    on_close = nil,    -- called when the popup closes, however it closes
    buttons = nil,     -- ButtonTable rows
    anchor = nil,      -- screen box of the tapped character {x, y, w, h}
    text_px = nil,     -- body text size in screen pixels (nil: KOReader's default)
    chinese_pct = 100, -- MOE's, the 成語典's and Xinhua's text: % of text_px
    book_font = nil,   -- {path=, index=} (ch_bookfont.lua): Chinese text in it, or nil
    full = false,      -- the whole screen's height (the Origin & Usage view), the body scrolling
    collapse_lines = 0, -- an Always block's senses (block.collapse) shown to this many
                       -- lines, then "…"; 0: never collapsed
    mark_buttons = nil, -- reading-mark buttons { {text=, callback=}, ... } (#26), at the
                       -- right end of the title bar, or nil (nested popups have none)
    -- Taps and keys (ch_tap.lua keeps the stack of popups):
    on_char_tap = nil, -- function(popup, hit): a Han character of the body tapped
                       -- (hit: Popup:charAt)
    on_outside = nil,  -- a tap outside the popup (nil: the popup closes)
    on_back = nil,     -- the Back key (nil: the popup closes)
}

-- Source labels: a small grey line just above an entry, left-aligned.
Popup.LABEL_MIN_PX = 18     -- never smaller than this, in screen pixels
Popup.LABEL_RATIO = 0.62    -- of the popup text size
-- The traditional form beside a headword (#47): the same typeface, this
-- much of the headword's size, in the text's own shade (#54).
Popup.TRAD_RATIO = 0.8

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
        self.key_events = { BackKey = { { Device.input.group.Back } } }
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
    self.trad_face = Font:getFace("x_smallinfofont", math.floor(face.orig_size * Popup.TRAD_RATIO + 0.5))
    -- Chinese text: the same font, larger (Font:getFace takes the size
    -- unscaled, so the ratio carries over).
    self.chinese_face = Font:getFace("x_smallinfofont",
        math.floor(face.orig_size * (self.chinese_pct or 100) / 100 + 0.5))
    -- The book's font for CJK glyphs (the UI font kept for the rest); the
    -- source labels keep the UI font.
    -- Bold counterparts for the context line's mark (nil: the face drawn
    -- bold, see contextLine); built from the unwrapped faces.
    self.bold_face, self.chinese_bold_face = nil, nil
    if self.book_font then
        local BookFont = require("ch_bookfont")
        self.bold_face = BookFont.bold(Font, self.face, self.book_font)
        self.chinese_bold_face = BookFont.bold(Font, self.chinese_face, self.book_font)
        self.face = BookFont.wrap(Font, self.face, self.book_font)
        self.title_face = BookFont.wrap(Font, self.title_face, self.book_font)
        self.chinese_face = BookFont.wrap(Font, self.chinese_face, self.book_font)
        self.trad_face = BookFont.wrap(Font, self.trad_face, self.book_font)
    end
    self:bookFontButtons()

    self:build()
    local y = self.full and self.margin or Model.place(self.frame:getSize().h, screen_h, self.margin, self.anchor)
    local size = self.frame:getSize()
    self.frame_x = math.floor((screen_w - size.w) / 2)
    self.frame_y = y
    -- Tall popups cover most of the page: close them with a flashing refresh
    -- so no ghost of them is left on e-ink.
    self.tall = size.h > screen_h / 2
end

-- Buttons whose text has Chinese in it (the character, the words, "成语
-- Origin & Usage"): Button's own font (bold Noto Sans) with the book font
-- first. Buttons with only Latin text (Close, Translate) are left alone.
Popup.BUTTON_FONT, Popup.BUTTON_FONT_SIZE = "cfont", 20   -- Button's defaults

function Popup:bookFontButtons()
    if not self.book_font or not self.buttons then return end
    local name
    for _, row in ipairs(self.buttons) do
        for _, b in ipairs(row) do
            if not b.font_face and type(b.text) == "string" and b.text:find("[\227-\233]") then
                name = name or require("ch_bookfont").buttonFont(Font, function(s) return Screen:scaleBySize(s) end,
                    self.book_font, Popup.BUTTON_FONT, b.font_size or Popup.BUTTON_FONT_SIZE)
                b.font_face = name
            end
        end
    end
end

function Popup:build()
    local screen_h = Screen:getHeight()
    local padding = Size.padding.large
    local inner_w = self.width - 2 * Size.border.window

    local parts = { align = "left" }
    local header_h = 0
    -- At the Chinese text size: the line is the page's text (#32).
    local line = self.context and Popup.contextLine(self.context, nil, self.chinese_face, inner_w - 2 * padding,
        self.chinese_bold_face)
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
    local head, mark_row = self:withMarkButtons(titlebar, inner_w)
    parts[#parts + 1] = head
    if mark_row then parts[#parts + 1] = mark_row end
    local button_table = ButtonTable:new{
        width = inner_w - 2 * Size.padding.default,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }
    Popup.shadeSeparators(button_table, Model.separatorShade(Screen.night_mode))

    -- Text area: as tall as the text, up to what the screen leaves.
    local text_w = inner_w - 2 * padding
    local max_h = screen_h - 2 * self.margin - header_h - head:getSize().h
        - (mark_row and mark_row:getSize().h or 0) - button_table:getSize().h
        - 2 * padding - 2 * Size.border.window
    max_h = math.max(max_h, self.face.size * 3)
    self.scroll = self:body(text_w, max_h, self.full)
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

-- The colour of the popup's small secondary text (source labels, 字频,
-- spoken here, [Tap to show more]): grey by day, the normal text colour in
-- night mode (#57; Model.secondaryGrey).
function Popup:secondaryColor()
    return Model.secondaryGrey(Screen.night_mode) and Blitbuffer.COLOR_GRAY_5 or Blitbuffer.COLOR_BLACK
end

--[[--
Draws a ButtonTable's grey separator lines (the row lines and the lines
between buttons in a row) in `shade` (Model.separatorShade). Black lines and
white (no_vertical_sep) ones are left alone.
]]
function Popup.shadeSeparators(button_table, shade)
    local default = Blitbuffer.COLOR_GRAY.a
    if shade == default then return end
    local color = Blitbuffer.Color8(shade)
    local function visit(w)
        if getmetatable(w) == LineWidget then
            if w.background and w.background.a == default then w.background = color end
        elseif type(w) == "table" and getmetatable(w) == HorizontalGroup then
            for _, child in ipairs(w) do visit(child) end
        end
    end
    for _, w in ipairs(button_table.container) do visit(w) end
end

-- The reading-mark buttons' text: a little smaller than the popup text.
Popup.MARK_TEXT_RATIO = 0.8

--[[--
The title bar with the reading-mark buttons (#26) laid over its right end,
right-aligned and vertically centred in it, or, when they don't fit beside
the title, the title bar alone and the buttons on a row of their own just
under it (returned second).
]]
function Popup:withMarkButtons(titlebar, inner_w)
    if not self.mark_buttons or #self.mark_buttons == 0 then return titlebar end
    local Button = require("ui/widget/button")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local size = self.text_px and unscaled(math.floor(self.text_px * Popup.MARK_TEXT_RATIO + 0.5)) or 18
    local group = HorizontalGroup:new{ align = "center" }
    for k, spec in ipairs(self.mark_buttons) do
        if k > 1 then group[#group + 1] = HorizontalSpan:new{ width = Size.padding.large } end
        group[#group + 1] = Button:new{
            text = spec.text,
            callback = spec.callback,
            bordersize = Size.border.thin,
            radius = Size.radius.button,
            padding_h = Size.padding.large,
            padding_v = Size.padding.small,
            margin = 0,
            text_font_size = size,
            text_font_bold = false,
            show_parent = self,
        }
    end
    self.mark_group = group
    local pad = Size.padding.large
    local title_w = TextWidget:new{ text = self.title or "", face = self.title_face }
    local tw = title_w:getSize().w
    title_w:free()
    local line_h = math.max(1, Size.line.thick or 1)
    local bar_h = titlebar:getHeight()
    local gw, gh = group:getSize().w, group:getSize().h
    if tw + 3 * pad + gw <= inner_w and gh <= bar_h - line_h then
        return OverlapGroup:new{
            dimen = Geom:new{ w = inner_w, h = bar_h },
            titlebar,
            RightContainer:new{
                dimen = Geom:new{ w = inner_w - pad, h = bar_h - line_h },
                group,
            },
        }
    end
    -- A row of its own, under the title bar's line.
    return titlebar, FrameContainer:new{
        padding = 0, padding_top = Size.padding.default, padding_bottom = Size.padding.default,
        bordersize = 0, margin = 0,
        RightContainer:new{ dimen = Geom:new{ w = inner_w - pad, h = gh }, group },
    }
end

-- New mark buttons (a mark changed): the popup is built again in place.
function Popup:setMarkButtons(list)
    self.mark_buttons = list
    self:rebuild()
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
  bold_face  the face for the marked part (drawn bold), or nil: `face`
]]
function Popup.contextLine(context, word, face, width, bold_face)
    bold_face = bold_face or face
    local function measure(s, bold)
        if s == "" then return 0 end
        local w = TextWidget:new{ text = s, face = bold and bold_face or face, bold = bold }
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
        text_widget = TextWidget:new{ text = sel.mark, face = bold_face, bold = true, max_width = math.max(1, width - used) },
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
that would leave it fewer than MIN_DICT_LINES. `chinese_pct` (the Chinese
text size setting, % of the dictionary's text; nil: 100) scales the line.
]]
Popup.MIN_DICT_LINES = 3

-- `face` at `pct`% of its size, the same font (nil or 100: `face` itself).
function Popup.scaledFace(face, pct)
    if not pct or pct == 100 or not face.orig_font or not face.orig_size then return face end
    return Font:getFace(face.orig_font, math.floor(face.orig_size * pct / 100 + 0.5)) or face
end

function Popup.addContextToDict(dql, context, word, chinese_pct)
    local frame = dql.dict_frame
    local group = frame and frame[1]
    local line_h = dql.definition_line_height
    if not group or not dql.content_width or not dql.content_face or not line_h or line_h <= 0
            or not dql.definition_height or not dql.definition_widget or not dql._instantiateScrollWidget then
        return
    end
    local line = Popup.contextLine(context, word, Popup.scaledFace(dql.content_face, chinese_pct), dql.content_width)
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

-- The marker after a collapsible block's text (an Always entry longer than
-- collapse_lines): small and grey, at the end of the last line shown. A tap
-- on it, or on the rest of that line after it, expands the block in place;
-- expanded, the same marker at the end of the text collapses it again.
Popup.SHOW_MORE = "[Tap to show more]"
Popup.SHOW_LESS = "[Tap to show less]"

-- A text box with the marker drawn after its line `line` (on a line of its
-- own below when it doesn't fit there). Remembers where the marker's tap
-- area was last painted (self.hot): from the marker to the right edge, the
-- height of that line.
local Marked = Widget:extend{ box = nil, marker = nil, width = nil, line = nil }

function Marked:init()
    local box, marker = self.box, self.marker
    local lh = box:getLineHeight()
    local list = box.vertical_string_list or {}
    local n = math.max(1, math.min(self.line or #list, #list))
    local used = list[n] and list[n].width or 0
    if list[n] and list[n].end_offset and list[n].end_offset < list[n].offset then used = 0 end
    self.gap = math.floor(marker:getSize().h / 2)
    local mw = marker:getSize().w
    local box_h = box:getSize().h
    self.extra = 0
    if used > 0 and used + self.gap + mw <= self.width then
        self.mx, self.line_top = used + self.gap, (n - 1) * lh
    else
        self.mx, self.line_top = 0, n * lh
        if self.line_top + lh > box_h then self.extra = self.line_top + lh - box_h end
    end
    local baseline = box.line_glyph_baseline or math.floor(lh * 0.8)
    self.my = self.line_top + baseline - marker:getBaseline()
    self.lh = lh
    self.size = Geom:new{ w = self.width, h = box_h + self.extra }
end

function Marked:getSize() return self.size end

function Marked:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size.w, h = self.size.h }
    self.box:paintTo(bb, x, y)
    self.marker:paintTo(bb, x + self.mx, y + self.my)
    local from = math.max(0, self.mx - self.gap)
    self.hot = Geom:new{ x = x + from, y = y + self.line_top, w = self.width - from, h = self.lh }
end

function Marked:free()
    self.box:free()
    self.marker:free()
end

-- A head line drawn in parts (#47): widgets side by side, their first
-- lines' baselines lined up. parts: { {widget=, baseline=, gap=}, ... }.
local HeadLine = Widget:extend{ parts = nil }

function HeadLine:init()
    local base = 0
    for _, p in ipairs(self.parts) do base = math.max(base, p.baseline) end
    local x, h = 0, 0
    for _, p in ipairs(self.parts) do
        p.x, p.y = x, base - p.baseline
        local size = p.widget:getSize()
        x = x + size.w + (p.gap or 0)
        h = math.max(h, p.y + size.h)
    end
    self.size = Geom:new{ w = x, h = h }
end

function HeadLine:getSize() return self.size end

function HeadLine:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size.w, h = self.size.h }
    for _, p in ipairs(self.parts) do p.widget:paintTo(bb, x + p.x, y + p.y) end
end

function HeadLine:free()
    for _, p in ipairs(self.parts) do p.widget:free() end
end

--[[--
A block's head line with its traditional form (block.trad, #47): the word
in bold, then the form smaller (Popup.TRAD_RATIO), in the text's own shade (#54),
then the rest (reading, markers), which wraps under itself when long. nil
when the word and the form leave too little room for the rest: the caller
draws the plain head line.
]]
function Popup:headLine(b, width)
    local word = TextWidget:new{ text = b.word, face = self.face, bold = true }
    local trad = TextWidget:new{ text = b.trad, face = self.trad_face }
    local space_w = TextWidget:new{ text = " ", face = self.face }
    local sw = space_w:getSize().w
    space_w:free()
    local parts = {
        { widget = word, baseline = word:getBaseline(), gap = sw },
        { widget = trad, baseline = trad:getBaseline() },
    }
    local used = word:getSize().w + sw + trad:getSize().w
    local rest = (b.rest or ""):gsub("^ +", "")
    if rest ~= "" then
        local lead = (#(b.rest or "") - #rest) * sw
        local room = width - used - lead
        if room < width * 0.3 then
            word:free()
            trad:free()
            return nil
        end
        parts[2].gap = lead
        local tbw = TextBoxWidget:new{ text = rest, face = self.face, width = room }
        parts[3] = { widget = tbw, baseline = tbw.line_glyph_baseline or math.floor(tbw:getLineHeight() * 0.8) }
    end
    return HeadLine:new{ parts = parts }
end

-- Should this block carry its source label?
function Popup:labelled(block)
    return not block.nolabel and self.label_mode ~= "none"
end

function Popup:labelPx()
    local px = self.text_px or Screen:scaleBySize(20)
    return math.max(Popup.LABEL_MIN_PX, math.floor(px * Popup.LABEL_RATIO + 0.5))
end

-- The entries, one block each: the source label (when shown) on a small grey
-- line of its own, left-aligned, then the headline (word, reading, markers)
-- and the senses, then an idiom's Chinese short line with its own label.
-- The senses and short lines of MOE, the 成語典 and Xinhua (Model.LARGE_SOURCES)
-- are in the larger Chinese face. The blocks stack vertically; only when they
-- are taller than the room left (or `full`) do they scroll
-- (ScrollableContainer, with a scroll bar). The text boxes whose characters
-- can be tapped (Model.tappable: the Chinese dictionaries' text only) are
-- kept in self.tap_boxes, for Popup:charAt.
function Popup:body(text_w, max_h, full)
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local label_face = Font:getFace("x_smallinfofont", unscaled(self:labelPx()))
    if self.book_font then
        label_face = require("ch_bookfont").wrap(Font, label_face, self.book_font)  -- 成语典, 新华
    end
    local block_gap = math.floor(self.face.size * 0.6)
    -- A components block (ch_components.lua) is indented by one em, below
    -- the character's own entry.
    local indent = self.face.size
    local function stack(full_width)
        self.tap_boxes = {}
        self.toggles = {}
        local group = VerticalGroup:new{ align = "left" }
        -- A text box; `tappable` ones (Model.tappable) are kept for charAt.
        local function box(text, face, width, tappable)
            local tbw = TextBoxWidget:new{ text = text, face = face, width = width }
            if tappable then
                self.tap_boxes[#self.tap_boxes + 1] = { widget = tbw, chars = Glyphs.chars(text) }
            end
            return tbw
        end
        for k, b in ipairs(self.blocks or {}) do
            if k > 1 then group[#group + 1] = VerticalSpan:new{ width = block_gap } end
            local width = b.components and full_width - indent or full_width
            local function add(widget)
                if b.components then
                    widget = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = indent }, widget }
                end
                group[#group + 1] = widget
            end
            -- The senses, built first: a collapsible block (an Always
            -- entry) longer than collapse_lines, counted as drawn, is cut to
            -- that many lines, the last one ending in "[Tap to show more]"
            -- unless expanded (then the text ends in "[Tap to show less]").
            local lines_box
            if #b.lines > 0 then
                local face = (b.large or Model.LARGE_SOURCES[b.source]) and self.chinese_face or self.face
                local text = TextBoxWidget.PTF_HEADER .. table.concat(b.lines, "\n")
                local tappable = Model.tappable(b, "lines")
                local n = self.collapse_lines or 0
                if b.collapse and n > 0 then
                    local probe = TextBoxWidget:new{ text = text, face = face, width = width }
                    local list = probe.vertical_string_list or {}
                    local line_h = probe:getLineHeight()
                    if #list > n then
                        local marker = TextWidget:new{
                            text = b.expanded and Popup.SHOW_LESS or Popup.SHOW_MORE, face = label_face,
                            fgcolor = self:secondaryColor(),
                        }
                        local tbw, line
                        if b.expanded then
                            probe:free()
                            tbw, line = box(text, face, width, tappable), nil
                        else
                            -- Cut the n-th line short enough to leave room for the marker.
                            local chars = Glyphs.chars(text)
                            local last = list[n]
                            local room = width - marker:getSize().w - math.floor(marker:getSize().h / 2)
                            local e = Glyphs.cut(chars, last.offset, math.min(last.end_offset or #chars, #chars), room,
                                function(str)
                                    local tw = TextWidget:new{ text = str, face = face }
                                    local w = tw:getSize().w
                                    tw:free()
                                    return w
                                end)
                            probe:free()
                            local cut = TextBoxWidget.PTF_HEADER .. table.concat(chars, "", 1, e)
                            tbw = TextBoxWidget:new{ text = cut, face = face, width = width,
                                height = n * line_h }
                            if tappable then
                                self.tap_boxes[#self.tap_boxes + 1] = { widget = tbw, chars = Glyphs.chars(cut) }
                            end
                            line = n
                        end
                        lines_box = Marked:new{ box = tbw, marker = marker, width = width, line = line }
                        self.toggles[#self.toggles + 1] = { widget = lines_box, block = b }
                    else
                        probe:free()
                    end
                end
                lines_box = lines_box or box(text, face, width, tappable)
            end
            -- On the tapped character's own entry, its frequency rank (and
            -- spoken mark); then the source label on a row of its own.
            for _, label in ipairs(Model.labelLines(b, self:labelled(b), self.labels)) do
                add(TextWidget:new{
                    text = label, face = label_face,
                    fgcolor = self:secondaryColor(), max_width = width,
                })
            end
            if b.head then
                local head = b.trad and b.word and self:headLine(b, width)
                add(head or box(TextBoxWidget.PTF_HEADER .. b.head, self.face, width, Model.tappable(b, "head")))
            end
            if lines_box then add(lines_box) end
            if b.note then
                if self:labelled(b.note) then
                    add(TextWidget:new{
                        text = (self.labels or {})[b.note.source] or b.note.source, face = label_face,
                        fgcolor = self:secondaryColor(), max_width = width,
                    })
                end
                local face = Model.LARGE_SOURCES[b.note.source] and self.chinese_face or self.face
                add(box(b.note.text, face, width, Model.tappable(b, "note")))
            end
        end
        return group
    end
    local group = stack(text_w)
    if group:getSize().h <= max_h and not full then
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

-- The visible part of the body: the scroll window, or nil (all visible).
function Popup:clip()
    local scroll = self.scrolls and self.scroll
    if not scroll or not scroll.dimen or not scroll.dimen.x then return nil end
    if scroll._is_scrollable and scroll.getCropRegion then return scroll:getCropRegion() end
    return Geom:new{ x = scroll.dimen.x, y = scroll.dimen.y, w = scroll.dimen.w, h = scroll.dimen.h }
end

-- The boxes as last painted (Glyphs.layout), in tap_boxes' order.
function Popup:layouts()
    local clip = self:clip()
    local out = {}
    for k, reg in ipairs(self.tap_boxes or {}) do
        out[k] = Glyphs.layout(reg.widget, reg.chars, clip)
            or { x = 0, y = 0, line_h = 1, lines = {}, chars = reg.chars, clip = clip }
    end
    return out
end

--[[--
The Han character of the body at screen position `pos`, or nil:
{ box=, index=, char=, chars= (the box's text), rect= (its screen box) }.
]]
function Popup:charAt(pos)
    local boxes = self:layouts()
    local k, i, rect = Glyphs.find(boxes, pos.x, pos.y)
    if not k then return nil end
    local chars = self.tap_boxes[k].chars
    return { box = k, index = i, char = chars[i], chars = chars, rect = rect }
end

-- Underline a character of the body (a hit from charAt) while a popup opened
-- from it is shown; nil takes the line away.
function Popup:setMark(hit)
    if self.marked == hit then return end
    self.marked = hit
    if self.frame.dimen then
        UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    end
end

function Popup:paintTo(bb, x, y)
    self.frame:paintTo(bb, x + self.frame_x, y + self.frame_y)
    local hit = self.marked
    if hit and self.tap_boxes and self.tap_boxes[hit.box] then
        local reg = self.tap_boxes[hit.box]
        local layout = Glyphs.layout(reg.widget, reg.chars, self:clip())
        local size = reg.widget.face and reg.widget.face.size or self.face.size
        local rect = layout and Glyphs.underline(layout, hit.index, math.max(2, math.floor(size / 10 + 0.5)),
            math.max(2, math.floor(size * 0.12 + 0.5)))
        if rect then bb:paintRect(rect.x, rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK) end
    end
end

-- The collapsible block whose marker's tap area is at `pos` ({widget=,
-- block=}), or nil; a marker scrolled out of view takes no tap.
function Popup:toggleAt(pos)
    local clip = self:clip()
    for _, t in ipairs(self.toggles or {}) do
        local d = t.widget.hot
        if d and d.x and pos.x >= d.x and pos.x < d.x + d.w and pos.y >= d.y and pos.y < d.y + d.h
                and (not clip or (pos.y >= clip.y and pos.y < clip.y + clip.h)) then
            return t
        end
    end
    return nil
end

-- Build the popup again (a block expanded or collapsed) and place it again;
-- what it covered before and covers now is repainted.
function Popup:rebuild()
    local old = self.frame.dimen and self.frame.dimen:copy()
    -- A scrolling body keeps its scroll position (within the new length).
    local offset = self.scrolls and self.scroll.getScrolledOffset and self.scroll:getScrolledOffset()
    self.frame:free()
    self:build()
    if offset and self.scrolls and self.scroll.setScrolledOffset and self.scroll.initState then
        self.scroll:initState()
        offset.y = math.min(offset.y, self.scroll._max_scroll_offset_y or offset.y)
        self.scroll:setScrolledOffset(offset)
    end
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local size = self.frame:getSize()
    self.frame_x = math.floor((screen_w - size.w) / 2)
    self.frame_y = self.full and self.margin or Model.place(size.h, screen_h, self.margin, self.anchor)
    self.tall = size.h > screen_h / 2
    local new = Geom:new{ x = self.frame_x, y = self.frame_y, w = size.w, h = size.h }
    local region = old and old:combine(new) or new
    UIManager:setDirty("all", function() return "ui", region end)
end

function Popup:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

-- Close this popup. region: what to refresh (default its own frame), for a
-- stack closed at once (ch_tap.lua); tall: refresh with a flash.
function Popup:onClose(region, tall)
    if tall == nil then tall = self.tall end
    UIManager:close(self, tall and "flashpartial" or "partial", region or self.frame.dimen)
    return true
end

function Popup:onBackKey()
    if self.on_back then self.on_back() else self:onClose() end
    return true
end

function Popup:onCloseWidget()
    if self.on_close then
        local f = self.on_close
        self.on_close = nil
        f()
    end
end

-- A tap outside the popup closes it (or the whole stack: on_outside), and
-- goes no further: it does not also turn the page. A tap in the body on a
-- Han character opens that character's popup (on_char_tap); other taps
-- inside that no button took are ignored.
function Popup:onTapClose(_, ges)
    if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
        if self.on_outside then self.on_outside() else self:onClose() end
        return true
    end
    local toggle = self:toggleAt(ges.pos)
    if toggle then
        toggle.block.expanded = not toggle.block.expanded
        self:rebuild()
        return true
    end
    if self.on_char_tap then
        local hit = self:charAt(ges.pos)
        if hit then self.on_char_tap(self, hit) end
    end
    return true
end

return Popup
