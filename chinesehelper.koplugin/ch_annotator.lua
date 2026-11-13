-- Pinyin above rare characters: the paint layer, the line spacing that makes
-- room for it, and the per-page resolution. From koreader-interlinear-pinyin's
-- main.lua, which kept WordGloss's paint-layer approach, line-height injection
-- and style-sheet hook (WordGloss: https://github.com/GangYe293/wordgloss.koplugin,
-- GPL-3.0, by GangYe293).
--
-- It also keeps the current page's items (the engine's characters plus a few
-- of context), which the tap popup resolves against, so the popup's reading
-- is computed exactly as the drawn one.

local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")

local Overlay = require("ch_overlay")
local Page = require("ch_page")

local Annotator = {}
Annotator.__index = Annotator

local GAP = 2        -- pixels reserved above and below the pinyin (line spacing)
-- Pixels between the bottom of the pinyin's descenders and the estimated top
-- of the character. The estimate (textBand) sits a few pixels above the real
-- glyph top, so a small negative value still clears it and brings the pinyin
-- closer; -1 looked right on a Boox Go 7.
local DRAW_GAP = -1

-- plugin: the ChineseHelper instance (ui, settings, readings(), special()).
function Annotator.new(plugin)
    return setmetatable({ plugin = plugin }, Annotator)
end

function Annotator:ui() return self.plugin.ui end
function Annotator:settings() return self.plugin.settings end

function Annotator:attach()
    local ui = self:ui()
    if not self.overlay and ui and ui.view then
        self.overlay = Overlay:new{ glosses = {}, gap = DRAW_GAP }
        local ok, err = pcall(function() ui.view:registerViewModule("chinesehelper", self.overlay) end)
        if not ok then logger.warn("chinesehelper: registerViewModule failed:", tostring(err)) end
    end
    self:hookStyleSheet()
end

function Annotator:onReaderReady()
    self:attach()
    if not self:settings():pinyinEnabled() then return end
    UIManager:nextTick(function()
        self:refreshDocumentStyles()
        self:refreshPage()
    end)
end

-- Applying the style while settings are read means it is part of the initial
-- layout, with no extra re-render.
function Annotator:onReadSettings()
    if self:settings():pinyinEnabled() then
        self:hookStyleSheet()
        self:refreshDocumentStyles()
    end
end

function Annotator:onDocumentRerendered()
    if self.overlay then self.overlay.placed = nil end
    self.items, self.items_page = nil, nil
    UIManager:nextTick(function()
        -- KOReader handles SetLineSpace itself and does not pass the event on,
        -- so notice a line-spacing change here, after its re-layout. Re-apply
        -- the style only when it changed (refreshDocumentStyles checks).
        if self:settings():pinyinEnabled() then self:refreshDocumentStyles() end
        self:refreshPage()
    end)
end

function Annotator:close()
    if self.overlay then self.overlay:clear() end
    self.items, self.items_page = nil, nil
end

------------------------------------------------------------------------
-- Line spacing: room for the pinyin between lines
------------------------------------------------------------------------

-- KOReader's "line spacing" setting (percent). crengine multiplies every line
-- height by it, including ones set in CSS.
function Annotator:lineSpacingPercent()
    local ui = self:ui()
    local configurable = (ui and ui.font and ui.font.configurable)
        or (ui and ui.document and ui.document.configurable)
    local pct = configurable and tonumber(configurable.line_spacing)
    if not pct or pct <= 0 then return 100 end
    return pct
end

-- Line-height (in em, as written in CSS) that leaves room for the pinyin.
--
-- The pinyin is drawn in the whole gap between the characters of one line and
-- those of the line above: CSS splits the extra height (lh - 1) em into half
-- above and half below each line, so that gap is the full (lh - 1) em. It must
-- hold the pinyin itself (about 1.2x its font size counting tone marks and
-- descenders) plus GAP pixels on each side. crengine then scales the result by
-- the line-spacing percentage, so divide by it to get what we actually need.
function Annotator.lineHeightFor(font_size, size_pct, spacing_pct)
    font_size = math.max(1, tonumber(font_size) or 16)
    local pinyin_px = font_size * size_pct / 100
    local need = pinyin_px * 1.2 + 2 * GAP
    local lh = (1 + need / font_size) / ((spacing_pct or 100) / 100)
    return math.max(1.0, math.min(3.0, lh))
end

function Annotator:gapCss(document)
    local font_size = 16
    local ok, size = pcall(function() return document:getFontSize() end)
    if ok and tonumber(size) then font_size = tonumber(size) end
    local lh = Annotator.lineHeightFor(font_size, self:settings():sizePercent(), self:lineSpacingPercent())
    -- Headings too: a rare character in a title gets pinyin like any other.
    return string.format("p,li,dd,dt,blockquote,div,td,pre,h1,h2,h3,h4,h5,h6{line-height:%.2f !important;}", lh)
end

function Annotator:styleSignature()
    local settings = self:settings()
    return tostring(settings:pinyinEnabled()) .. "|" .. tostring(settings:sizePercent())
        .. "|" .. tostring(self:lineSpacingPercent())
end

-- Re-apply the style sheet when our settings change. The CSS itself is added
-- by hookStyleSheet, so KOReader's own re-layouts keep it too.
--
-- document:setStyleSheet alone only records the CSS; the book is laid out
-- again only on UpdatePos. ApplyStyleSheet is KOReader's own way to do both:
-- ReaderTypeset re-sets its CSS plus the style tweaks (through our hook) and
-- sends UpdatePos. Before the reader is ready (onReadSettings) UpdatePos is a
-- no-op and the first layout picks the style up.
function Annotator:refreshDocumentStyles()
    local ui = self:ui()
    local document = ui and ui.document
    if not document or not ui.typeset or not document.setStyleSheet then return false end
    local signature = self:styleSignature()
    if document._chinesehelper_signature == signature then return true end
    document._chinesehelper_signature = signature
    local ok, err = pcall(function() ui:handleEvent(Event:new("ApplyStyleSheet")) end)
    if not ok then
        logger.warn("chinesehelper: applying style sheet failed:", tostring(err))
        document._chinesehelper_signature = nil
        return false
    end
    return true
end

-- Wrap document:setStyleSheet so our line-height is appended every time the
-- engine applies styles. Runs in the middle of the engine's styling: only
-- plain Lua here, never calls back into the engine.
function Annotator:hookStyleSheet()
    local ui = self:ui()
    local document = ui and ui.document
    if not document or document._chinesehelper_hooked then return end
    local original = document.setStyleSheet
    if not original then return end
    document._chinesehelper_hooked = true
    local annotator = self
    document.setStyleSheet = function(doc, css, tweaks_css)
        local extra = tweaks_css or ""
        if annotator:settings():pinyinEnabled() then
            local ok, more = pcall(function() return annotator:gapCss(doc) end)
            if ok and more then extra = extra .. "\n" .. more end
        end
        return original(doc, css, extra)
    end
end

------------------------------------------------------------------------
-- Current page
------------------------------------------------------------------------

-- Where the reader is: the page number, whether the view is continuous
-- (scroll), and a key for the items on screen (the page in page view; the
-- top-of-screen position in continuous view, where scrolling stays on one
-- page number).
function Annotator:position(document)
    local view = self:ui().view
    local scroll = view ~= nil and view.view_mode == "scroll"
    local page = document:getCurrentPage()
    local key = scroll and ("scroll:" .. tostring(document:getXPointer())) or page
    return page, scroll, key
end

function Annotator:refreshPage()
    local ui = self:ui()
    local document = ui and ui.document
    if not document or not self.overlay then return end
    local settings = self:settings()
    if not settings:pinyinEnabled() then
        self.items, self.items_page = nil, nil
        if #self.overlay.glosses > 0 then
            self.overlay:clear()
            UIManager:setDirty(ui.view, "ui")
        end
        return
    end
    local data = self.plugin:readings()
    if not data then return end

    local t0 = time.monotonic()
    local ok, err = pcall(function()
        local font_size = document:getFontSize()
        local page, scroll, key = self:position(document)
        local glosses, stats, items = Page.build(document, page, data, settings:threshold(),
            settings:uncertainMode(), self.plugin:special(), scroll,
            scroll and require("device").screen:getHeight() or nil)
        self.items, self.items_page = items, key
        self.overlay.special_style = settings:specialStyle()
        self.overlay.font_size = math.max(8, math.floor(font_size * settings:sizePercent() / 100 + 0.5))
        -- Line box height per pixel of text, to tell headings (larger text) apart.
        self.overlay.line_ratio = Annotator.lineHeightFor(font_size, settings:sizePercent(),
            self:lineSpacingPercent()) * self:lineSpacingPercent() / 100
        self.overlay:setGlosses(glosses, font_size)
        stats.ms = time.to_ms(time.monotonic() - t0)
        self.last_stats = stats
        logger.dbg(string.format("chinesehelper: page %d: %d items, %d annotated in %.1f ms",
            page, stats.items, stats.annotated, stats.ms))
    end)
    if not ok then
        logger.warn("chinesehelper: refresh failed:", tostring(err))
        self.overlay:clear()
        self.items, self.items_page = nil, nil
    end
    UIManager:setDirty(ui.view, "ui")
end

function Annotator:apply(touchmenu)
    if self.overlay then self.overlay:clear() end
    self:refreshDocumentStyles()
    self:refreshPage()
    if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
end

------------------------------------------------------------------------
-- For the tap popup
------------------------------------------------------------------------

-- The drawn annotation under screen point (x, y), or nil (see ch_hit.lua).
function Annotator:hitTest(x, y)
    if not self:settings():pinyinEnabled() or not self.overlay then return nil end
    return self.overlay:hitTest(x, y)
end

-- The drawn annotation for page item `index`, or nil (a repeat left bare by
-- the once-per-page rule, or pinyin dropped from a crowded line, is not drawn).
function Annotator:drawnAt(index)
    if not self.overlay or not self:settings():pinyinEnabled() then return nil end
    local placed = self.overlay.placed
        or self.overlay:plan(self.overlay._max_x or require("device").screen:getWidth())
    for _, entry in ipairs(placed or {}) do
        if entry.item.gloss.index == index then return entry.item.gloss end
    end
    return nil
end

-- The current page's items: the ones the annotations were drawn from when
-- they are on, otherwise collected now (a few ms).
function Annotator:pageItems()
    local document = self:ui().document
    local page, scroll, key = self:position(document)
    if self.items and self.items_page == key then return self.items end
    local items = Page.collect(document, page, scroll)
    self.items, self.items_page = items, key
    return items
end

return Annotator
