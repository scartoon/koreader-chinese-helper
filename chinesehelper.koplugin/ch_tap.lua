-- The one tap handler: a single tap on a Chinese character's glyph, or on the
-- pinyin drawn above one, opens the popup; every other tap is KOReader's.
--
-- One full-screen "tap" zone, like ReaderHighlight's readerhighlight_tap:
-- it overrides the page-turn, menu, footer and corner zones so it is asked
-- first, and returns false (the tap falls through to them, and the page
-- turns) unless the tap is on a Chinese character's glyph or drawn pinyin.
-- Links and highlights come earlier (registered before plugins) and are also
-- checked in the handler. A tap in the edge band ("Edge pass-through width")
-- is always KOReader's: that is checked first, before any hit testing. Nothing is registered for hold, swipe or any other
-- gesture, and nothing at all while "Tap characters for popup" is off or the
-- document is not reflowable (PDF, DjVu, CBZ: every tap is KOReader's).

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

local Context = require("ch_context")
local Edge = require("ch_edge")
local Model = require("ch_popup_model")
local Page = require("ch_page")
local Resolve = require("ch_resolve")
local Text = require("ch_text")

local Tap = {}
Tap.__index = Tap

Tap.ZONE_ID = "chinesehelper_tap"
Tap.BUTTONS_PER_ROW = 4

function Tap.new(plugin)
    return setmetatable({ plugin = plugin }, Tap)
end

function Tap:ui() return self.plugin.ui end

function Tap:zone()
    return {
        id = Tap.ZONE_ID,
        ges = "tap",
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        overrides = {
            "tap_top_left_corner",
            "tap_top_right_corner",
            "tap_left_bottom_corner",
            "tap_right_bottom_corner",
            "readerfooter_tap",
            "readerconfigmenu_ext_tap",
            "readerconfigmenu_tap",
            "readermenu_ext_tap",
            "readermenu_tap",
            "tap_forward",
            "tap_backward",
        },
        handler = function(ges) return self:onTap(ges) end,
    }
end

-- Register or unregister the zone to match the setting and the document.
function Tap:update()
    local ui = self:ui()
    if not ui or not ui.registerTouchZones or not Device:isTouchDevice() then return end
    local want = self.plugin.settings:popupEnabled() and self.plugin:isCompatibleDocument()
    if want and not self.registered then
        ui:registerTouchZones({ self:zone() })
        self.registered = true
    elseif not want and self.registered then
        ui:unRegisterTouchZones({ self:zone() })
        self.registered = false
    end
end

function Tap:tapIsOnLink(pos)
    local document = self:ui().document
    if not document or not document.getLinkFromPosition then return false end
    local ok, link = pcall(document.getLinkFromPosition, document, pos)
    return ok and link ~= nil and link ~= ""
end

-- Same test as ReaderHighlight:onTap.
function Tap:tapIsOnHighlight(pos)
    local view = self:ui().view
    local boxes = view and view.highlight and view.highlight.visible_boxes
    if not boxes or #boxes == 0 then return false end
    local page_pos = view:screenToPageTransform({ x = pos.x, y = pos.y })
    if not page_pos then return false end
    for _, box in ipairs(boxes) do
        local r = box.rect
        if r and r.x <= page_pos.x and r.y <= page_pos.y
                and r.x + r.w >= page_pos.x and r.y + r.h >= page_pos.y then
            return true
        end
    end
    return false
end

-- The edge band's width in pixels (0 when off), from the setting and the
-- DPI the screen reports. Read on every tap, so a change applies at once.
function Tap:edgeBand()
    local mm = self.plugin.settings:edgeMm()
    if mm <= 0 then return 0 end
    return Edge.px(mm, Device.screen:getDPI())
end

-- Is the tap within the edge band? Measured from the screen's edges in its
-- current orientation (getWidth/getHeight follow rotation, as do tap positions).
function Tap:inEdgeBand(pos)
    local band = self:edgeBand()
    if band <= 0 then return false end
    local screen = Device.screen
    return Edge.inBand(pos.x, pos.y, screen:getWidth(), screen:getHeight(), band)
end

function Tap:textHeight()
    local ok, size = pcall(function() return self:ui().document:getFontSize() end)
    return ok and tonumber(size) or nil
end

-- The character a tap is on: { char=, pos0=, pos1=, box= }, or nil. Drawn
-- pinyin counts as its character.
function Tap:hitAt(pos)
    local gloss = self.plugin.annotator:hitTest(pos.x, pos.y)
    if gloss and gloss.ws and gloss.we then
        return { char = gloss.char, pos0 = gloss.ws, pos1 = gloss.we, box = gloss.box }
    end
    return Context.charAt(self:ui().document, pos, self:textHeight())
end

function Tap:onTap(ges)
    if not self.plugin.settings:popupEnabled() or not ges or not ges.pos then return false end
    -- The edge band first: those taps are KOReader's, at no extra cost.
    if self:inEdgeBand(ges.pos) then return false end
    local highlight = self:ui().highlight
    -- A tap while selecting text, or in highlight select mode, is ReaderHighlight's.
    if highlight and (highlight.hold_pos or highlight.select_mode) then return false end
    local ok, result = pcall(function()
        local pos = { x = ges.pos.x, y = ges.pos.y }
        local hit = self:hitAt(pos)
        if not hit then return false end
        if self:tapIsOnLink(ges.pos) or self:tapIsOnHighlight(pos) then return false end
        self:showPopup(hit)
        return true
    end)
    if not ok then
        logger.warn("chinesehelper: tap failed:", tostring(result))
        return false
    end
    return result
end

--[[--
The resolver's view of the tapped character, computed on the page items the
annotation layer uses (so the popup cannot disagree with the pinyin drawn):
chosen reading (or nil), the deciding word (Model.matches' `decided`), and
whether this occurrence has pinyin drawn above it.
]]
function Tap:resolve(hit, left, right)
    local data = self.plugin:readings()
    if not data then return nil end
    local settings = self.plugin.settings
    local special = self.plugin:special()
    local document = self:ui().document
    local items, i
    local ok, page_items = pcall(function() return self.plugin.annotator:pageItems() end)
    if ok and page_items then
        items = page_items
        i = Page.find(document, items, hit.pos0)
    end
    if not i then
        -- Not found among the page's items: resolve on the Han run around it.
        items = {}
        for _, c in ipairs(left) do items[#items + 1] = { text = c, joined = #items > 0 } end
        items[#items + 1] = { text = hit.char, joined = #items > 0 }
        i = #items
        for _, c in ipairs(right) do items[#items + 1] = { text = c, joined = true } end
    end
    local drawn = items[i].ws and self.plugin.annotator:drawnAt(i)
    local reading, decided = Resolve.forPopup(data, items, i, settings:uncertainMode(), special,
        drawn and drawn.text)
    return reading, decided, drawn ~= nil
end

-- Rows from the fallback dictionaries for the candidate words CC-CEDICT has
-- no row for: each source in priority order, one source per word.
function Tap:fallbackRows(texts, rows)
    local remaining = Model.uncovered(texts, rows)
    local out = {}
    for _, src in ipairs(self.plugin:fallbackSources()) do
        if #remaining == 0 then break end
        local got = {}
        for _, row in ipairs(src.db:fallback(remaining)) do
            if (row.source or src.source) == src.source then
                row.source = src.source
                got[#got + 1] = row
            end
        end
        local kept
        kept, remaining = Model.takeFallback(remaining, got)
        for _, row in ipairs(kept) do out[#out + 1] = row end
    end
    return out
end

function Tap:lookupInKOReader(text, box)
    local dictionary = self:ui().dictionary
    if not dictionary then return end
    dictionary:onLookupWord(text, false, box and { box } or nil)
end

function Tap:showPopup(hit)
    local t0 = time.monotonic()
    local db, err = self.plugin:db()
    if not db then
        UIManager:show(InfoMessage:new{
            text = T(_("Chinese helper: dictionary not available (%1)."), tostring(err)), timeout = 4 })
        return
    end
    local document = self:ui().document
    local left, right = Context.around(document, hit)
    local cands, texts = Text.candidates(left, hit.char, right)
    local rows = db:lookup(texts)
    for _, row in ipairs(self:fallbackRows(texts, rows)) do rows[#rows + 1] = row end
    local chosen, decided, annotated = self:resolve(hit, left, right)
    local data = self.plugin:readings()
    if data then data:prefetch(texts) end
    local matches = Model.matches{
        cands = cands, rows = rows, chosen = chosen, annotated = annotated, decided = decided,
        wordReading = data and function(word) return Resolve.wordReading(data, word) end,
    }
    if #matches == 0 then
        -- Nothing in CC-CEDICT: straight to KOReader's dictionaries.
        self:lookupInKOReader(hit.char, hit.box)
        return
    end
    local Popup = require("ch_popup")
    local popup
    local buttons = {}
    for _, m in ipairs(matches) do
        local word = m.word
        buttons[#buttons + 1] = {
            text = word,
            callback = function()
                popup:onClose()
                self:lookupInKOReader(word, hit.box)
            end,
        }
    end
    buttons[#buttons + 1] = { text = _("Close"), callback = function() popup:onClose() end }
    local font_size = self:textHeight()
    popup = Popup:new{
        title = hit.char,
        text = Model.render(matches, hit.char, annotated, Popup.BOLD_START, Popup.BOLD_END),
        header = Model.header(left, hit.char, right, Popup.BOLD_START, Popup.BOLD_END),
        buttons = Text.rows(buttons, Tap.BUTTONS_PER_ROW),
        anchor = hit.box,
        text_px = font_size and math.floor(font_size * self.plugin.settings:popupTextPercent() / 100 + 0.5),
    }
    UIManager:show(popup)
    logger.dbg(string.format("chinesehelper: %s [%s|%s] reading %s, %d matches in %.1f ms",
        hit.char, table.concat(left, ""), table.concat(right, ""), tostring(chosen), #matches,
        time.to_ms(time.monotonic() - t0)))
end

return Tap
