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

local Components = require("ch_components")
local Context = require("ch_context")
local Edge = require("ch_edge")
local Model = require("ch_popup_model")
local Page = require("ch_page")
local Resolve = require("ch_resolve")
local Snippet = require("ch_snippet")
local Text = require("ch_text")

local Tap = {}
Tap.__index = Tap

Tap.ZONE_ID = "chinesehelper_tap"
Tap.BUTTONS_PER_ROW = 4

-- TextBoxWidget's bold markers (ch_popup.lua loads KOReader's widgets, so
-- only when a popup is shown).
local function bold()
    local Popup = require("ch_popup")
    return Popup.BOLD_START, Popup.BOLD_END
end

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
        self:unmark()   -- no popup: no underline either
        return false
    end
    return result
end

--[[--
The resolver's view of the tapped character, computed on the page items the
annotation layer uses (so the popup cannot disagree with the pinyin drawn):
chosen reading (or nil), the deciding word (Model.matches' `decided`),
whether this occurrence has pinyin drawn above it, and whether the reading
is only the uncertainty pair (Resolve.forPopup's `unsure`).
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
    local reading, decided, unsure = Resolve.forPopup(data, items, i, settings:uncertainMode(), special,
        drawn and drawn.text)
    return reading, decided, drawn ~= nil, unsure
end

-- Rows from the fallback dictionaries for the candidate words CC-CEDICT has
-- no row for: each source in priority order, one source per word.
function Tap:fallbackRows(texts, rows)
    return self.plugin:fallbackLookup(Model.uncovered(texts, rows))
end

--[[--
Look `text` up in KOReader's dictionaries.
  opts.context   the page text around the tap (Tap:context), shown at the top
                 of the dictionary popup with opts.word marked (Snippet.select)
  opts.on_close  called when that dictionary popup closes
]]
function Tap:lookupInKOReader(text, box, opts)
    local dictionary = self:ui().dictionary
    if not dictionary then return end
    opts = opts or {}
    local boxes = box and { box } or nil
    Tap.installDictHook()
    -- The hook recognises the popup of this lookup by its boxes table, which
    -- ReaderDictionary hands on unchanged: lookups from inside a dictionary
    -- popup (or anywhere else) never get the line.
    Tap.pending_dict = (opts.context and boxes) and { boxes = boxes, context = opts.context, word = opts.word } or nil
    dictionary:onLookupWord(text, false, boxes, nil, nil, opts.on_close)
end

-- Wrap DictQuickLookup:init once, so the popup of a lookup made from our
-- popup (Tap.pending_dict) gets the context line under its title.
function Tap.installDictHook()
    local ok, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
    if not ok or not DictQuickLookup or DictQuickLookup._chinesehelper_init then return end
    local init = DictQuickLookup.init
    DictQuickLookup._chinesehelper_init = init
    DictQuickLookup.init = function(dql, ...)
        init(dql, ...)
        local pending = Tap.pending_dict
        if pending and dql.word_boxes ~= nil and dql.word_boxes == pending.boxes then
            Tap.pending_dict = nil
            local ok2, err = pcall(require("ch_popup").addContextToDict, dql, pending.context, pending.word)
            if not ok2 then logger.warn("chinesehelper: context line in dictionary failed:", tostring(err)) end
        end
    end
end

-- The page text around the tap for the context line: { chars=, index= }, or
-- nil (setting off, or the page cannot be read).
function Tap:context(hit)
    if not self.plugin.settings:contextEnabled() then return nil end
    local t0 = time.monotonic()
    local ok, chars, index = pcall(function()
        local document = self:ui().document
        local view = self:ui().view
        local bounds = Snippet.pageBounds(document, view ~= nil and view.view_mode == "scroll")
        return Snippet.pageText(document, hit, bounds)
    end)
    if not ok then
        logger.warn("chinesehelper: context failed:", tostring(chars))
        return nil
    end
    logger.dbg(string.format("chinesehelper: context %s in %.1f ms", chars and (#chars .. " chars") or "none",
        time.to_ms(time.monotonic() - t0)))
    return chars and { chars = chars, index = index } or nil
end

-- The underline under the tapped character on the page. Each mark has an
-- id, so a late close (of a popup already replaced) leaves a newer one alone.
function Tap:mark(hit)
    if not self.plugin.settings:underlineEnabled() or not hit.box then
        self:unmark()
        return nil
    end
    self.mark_id = (self.mark_id or 0) + 1
    self.plugin.annotator:setMark(hit.box)
    return self.mark_id
end

function Tap:unmark(id)
    if id and id ~= self.mark_id then return end
    self.plugin.annotator:setMark(nil)
end

-- The sentence button's row (ch_translate.lua), or nil while Wi-Fi is not
-- connected. The sentence is only looked for when the button is pressed.
function Tap:sentenceRow(hit, close)
    local t0 = time.monotonic()
    local ok, row, mode = pcall(function()
        local Sentence = require("ch_sentence")
        local Translate = require("ch_translate")
        local document = self:ui().document
        return Translate.row{
            ui = self:ui(),
            network = require("ui/network/manager"),
            close = close,
            logger = logger,
            sentence = function()
                local t0 = time.monotonic()
                local ok2, s = pcall(Sentence.find, document, hit)
                if not ok2 then logger.warn("chinesehelper: sentence failed:", tostring(s)) end
                s = ok2 and s or { text = hit.char }
                logger.dbg(string.format("chinesehelper: sentence of %d bytes%s%s in %.1f ms", #s.text,
                    s.pos0 and "" or " (no positions)", s.capped and " (capped)" or "",
                    time.to_ms(time.monotonic() - t0)))
                return s
            end,
        }
    end)
    if not ok then
        logger.warn("chinesehelper: sentence button failed:", tostring(row))
        return nil
    end
    logger.dbg(string.format("chinesehelper: sentence button %s in %.2f ms", tostring(mode or "hidden"),
        time.to_ms(time.monotonic() - t0)))
    return row
end

function Tap:showPopup(hit)
    local t0 = time.monotonic()
    local db = self:openDb()
    if not db then return end
    local document = self:ui().document
    local left, right = Context.around(document, hit)
    local cands, texts = Text.candidates(left, hit.char, right)
    local rows = db:lookup(texts)
    for _, row in ipairs(self:fallbackRows(texts, rows)) do rows[#rows + 1] = row end
    local chosen, decided, annotated, unsure = self:resolve(hit, left, right)
    local data = self.plugin:readings()
    if data then data:prefetch(texts) end
    local matches = Model.matches{
        cands = cands, rows = rows, chosen = chosen, annotated = annotated, decided = decided,
        unsure = unsure, order = self.plugin.settings:fallbackOrder(),
        default = data and select(2, data:char(hit.char)) or nil,
        wordReading = data and function(word) return Resolve.wordReading(data, word) end,
    }
    self:present{
        db = db, char = hit.char, box = hit.box, cands = cands, rows = rows, matches = matches,
        annotated = annotated, context = self:context(hit), mark = self:mark(hit),
        sentence = function(close) return self:sentenceRow(hit, close) end,
    }
    logger.dbg(string.format("chinesehelper: %s [%s|%s] reading %s, %d matches in %.1f ms",
        hit.char, table.concat(left, ""), table.concat(right, ""), tostring(chosen), #matches,
        time.to_ms(time.monotonic() - t0)))
end

function Tap:openDb()
    local db, err = self.plugin:db()
    if not db then
        UIManager:show(InfoMessage:new{
            text = T(_("Chinese helper: dictionary not available (%1)."), tostring(err)), timeout = 4 })
    end
    return db
end

-- The components to show for `char` (ch_components.lua), or nil.
function Tap:components(db, char, cands, rows)
    if not self.plugin.settings:componentsEnabled() then return nil end
    local ok, c, via, changes = pcall(Components.resolve, char,
        function(list) return db:components(list) end, cands, rows)
    if not ok then
        logger.warn("chinesehelper: components failed:", tostring(c))
        return nil
    end
    if not c then return nil end
    return { c = c, via = via, changes = changes }
end

-- The idiom information for the matches of two or more characters
-- (main.lua idiomLookup), attached to them (Model.attachIdioms).
function Tap:attachIdioms(matches)
    local words = {}
    for _, m in ipairs(matches) do
        if m.len and m.len > 1 then words[#words + 1] = m.word end
    end
    if #words == 0 or not self.plugin.idiomLookup then return end
    local ok, idioms = pcall(self.plugin.idiomLookup, self.plugin, words)
    if not ok then
        logger.warn("chinesehelper: idioms failed:", tostring(idioms))
        return
    end
    Model.attachIdioms(matches, idioms)
end

Tap.CHUCHU_SOURCES = { idioms = "教育部《成语典》", xinhua = "新华成语" }

function Tap:showChuchu(word, source, text)
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{
        title = T("%1 · %2 · %3", word, Model.CHUCHU, Tap.CHUCHU_SOURCES[source] or source),
        text = text,
    })
end

--[[--
Show the popup.
  args.db, args.char, args.box      the database, the character, its screen box (or nil)
  args.cands, args.rows             Text.candidates and the rows looked up for them
  args.matches                      Model.matches
  args.annotated                    pinyin drawn above this occurrence
  args.context                      the page text around the tap (Tap:context), or nil
  args.mark                         the page underline's id (Tap:mark), or nil
  args.sentence                     function(close) -> the sentence button's row (or nil)
]]
function Tap:present(args)
    local comp = self:components(args.db, args.char, args.cands, args.rows)
    -- KOReader's dictionary popup, opened from this tap: keeps the underline
    -- on the tapped character until it closes.
    local function lookup(text, word)
        self:lookupInKOReader(text, args.box, {
            context = args.context, word = word,
            on_close = args.mark and function() self:unmark(args.mark) end,
        })
    end
    if #args.matches == 0 and not comp then
        -- No dictionary (CC-CEDICT or a fallback dictionary) has the
        -- character or any word around it: straight to KOReader's dictionaries.
        lookup(args.char)
        return
    end
    local Popup = require("ch_popup")
    local b0, b1 = bold()
    local popup
    local keep_mark = false
    local close = function() popup:onClose() end
    self:attachIdioms(args.matches)
    local blocks = Model.blocks(args.matches, args.char, args.annotated, b0, b1)
    local words = {}
    for _, m in ipairs(args.matches) do
        local word = m.word
        words[#words + 1] = {
            text = word,
            callback = function()
                keep_mark = true
                popup:onClose()
                lookup(word, { text = word, start = m.start })
            end,
        }
    end
    for _, c in ipairs(Model.chuchu(args.matches)) do
        words[#words + 1] = { text = c.text, callback = function() self:showChuchu(c.word, c.source, c.view) end }
    end
    -- Buttons: the character, the words around it, 出处, Close. The
    -- components block has none of its own.
    words[#words + 1] = { text = _("Close"), callback = close }
    local button_rows = Text.rows(words, Tap.BUTTONS_PER_ROW)
    local block = comp and Components.block(comp.c, b0, b1, comp.via, comp.changes)
    if block then
        -- Below the character's own entry (when it has one).
        local first = args.matches[1]
        table.insert(blocks, (first and first.len == 1) and 2 or 1, block)
    end
    local sentence_row = args.sentence and args.sentence(close)
    if sentence_row then button_rows[#button_rows + 1] = sentence_row end
    local font_size = self:textHeight()
    popup = Popup:new{
        title = args.char,
        blocks = blocks,
        labels = Model.SOURCE_LABELS, label_mode = self.plugin.settings:labelMode(),
        context = args.context,
        -- However it closes (tap outside, Close, Back, Translate): the
        -- underline goes, unless a word button opened a dictionary popup.
        on_close = function()
            if not keep_mark and args.mark then self:unmark(args.mark) end
        end,
        buttons = button_rows,
        anchor = args.box,
        text_px = font_size and math.floor(font_size * self.plugin.settings:popupTextPercent() / 100 + 0.5),
    }
    UIManager:show(popup)
end

return Tap
