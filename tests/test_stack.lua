-- Popups opened from popups (ch_tap.lua): a character tapped in a popup's
-- text opens its popup on top, underlined below while it is shown; its
-- Close (no Back button) or the Back key returns to the one below; a tap
-- outside or Translate closes them all; at most Tap.MAX_DEPTH at once. The nested popup's context line
-- is the popup text's sentence, not the book's; only the first popup has a Translate button. Built
-- against stub KOReader modules and the real database, with a fake Popup.
local H = require("sq3_shim")
local eq = H.eq
local Glyphs = require("ch_glyphs")

local function stub(name, value) package.loaded[name] = value end
local Extendable = {}
function Extendable:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
Extendable.new = Extendable.extend

local shown, closed, infos = {}, {}, {}
stub("gettext", function(s) return s end)
stub("logger", { err = function() end, warn = function() end, info = function() end, dbg = function() end })
stub("ffi/util", { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end })
stub("ui/uimanager", {
    nextTick = function(_, f) f() end, setDirty = function() end,
    show = function(_, w) shown[#shown + 1] = w end,
    close = function(_, w, refresh, region)
        closed[#closed + 1] = { w = w, refresh = refresh, region = region }
        if w.on_close then local f = w.on_close; w.on_close = nil; f() end
    end,
})
stub("ui/event", { new = function(_, ...) return { ... } end })
stub("ui/time", { monotonic = function() return 0 end, to_ms = function() return 0 end })
stub("ui/widget/container/widgetcontainer", Extendable)
stub("ui/widget/infomessage", { new = function(_, args) infos[#infos + 1] = args; return args end })
stub("ui/widget/widget", Extendable)
stub("ffi/blitbuffer", { COLOR_BLACK = 0 })
stub("ui/font", {})
stub("ui/rendertext", {})
stub("ui/size", { span = { horizontal_small = 2 } })
stub("device", { screen = { scaleBySize = function(_, v) return v end, getWidth = function() return 1680 end,
                            getHeight = function() return 1264 end, getDPI = function() return 300 end },
                 isTouchDevice = function() return true end })
stub("lua-ljsqlite3/init", H.SQ3)
stub("datastorage", { getDataDir = function() return TEST_KOREADER_DIR end, getSettingsDir = function() return TEST_KOREADER_DIR .. "/settings" end })
stub("libs/libkoreader-lfs", { attributes = function() return nil end })
stub("ui/network/manager", { isWifiOn = function() return true end, isConnected = function() return true end,
                             runWhenConnected = function(_, f) f() end })
local settings = {}
G_reader_settings = {
    readSetting = function(_, k) return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
    flush = function() end,
}

-- The fake popup: the arguments Tap gives it, the underline set on it, and
-- closing as Popup:onClose does (UIManager:close, then on_close).
local Popup = { BOLD_START = "", BOLD_END = "" }
function Popup:new(args)
    args.marks = {}
    args.setMark = function(p, hit) p.marked = hit; p.marks[#p.marks + 1] = hit or false end
    args.onClose = function(p, region, tall)
        require("ui/uimanager"):close(p, tall and "flashpartial" or "partial", region)
    end
    return args
end
stub("ch_popup", Popup)

local Plugin = dofile(PLUGIN_DIR .. "/main.lua")
local plugin = Plugin:new{ path = PLUGIN_DIR }
plugin:init()
plugin.ui = { highlight = { onTranslateText = function() end } }
local tap = plugin.tap
tap.textHeight = function() return 64 end

local Text = require("ch_text")
local Model = require("ch_popup_model")

-- The popup for a tap on the page (as Tap:showPopup, without the page).
local function root(left, char, right, sentence)
    local cands, words = Text.candidates(Text.chars(left), char, Text.chars(right))
    local rows = plugin:db():lookup(words)
    for _, r in ipairs(tap:fallbackRows(words, rows)) do rows[#rows + 1] = r end
    local m = Model.matches{ cands = cands, rows = rows, order = plugin.settings:fallbackOrder() }
    return tap:present{ db = plugin:db(), char = char, cands = cands, rows = rows, matches = m, annotated = false,
                        mark = 7, sentence = sentence }
end

-- A tap on the n-th `char` of `text` in popup p's body (as Popup:charAt).
local function hitIn(text, char, n)
    local chars = Glyphs.chars(text)
    n = n or 1
    for k, c in ipairs(chars) do
        if c == char then
            n = n - 1
            if n == 0 then
                return { box = 1, index = k, char = c, chars = chars, rect = { x = 100, y = 200, w = 50, h = 65 } }
            end
        end
    end
    error("no " .. char)
end

local function buttons(p)
    local out = {}
    for _, r in ipairs(p.buttons) do for _, b in ipairs(r) do out[#out + 1] = b end end
    return out
end
local function button(p, text)
    for _, b in ipairs(buttons(p)) do if b.text == text then return b end end
end
local function texts(p)
    local out = {}
    for _, b in ipairs(buttons(p)) do out[#out + 1] = b.text end
    return table.concat(out, ",")
end
-- The bottom row's button texts ("Close").
local function lastRow(p)
    local out = {}
    for _, b in ipairs(p.buttons[#p.buttons]) do out[#out + 1] = b.text end
    return table.concat(out, ",")
end

local unmarked = {}
tap.unmark = function(_, id) unmarked[#unmarked + 1] = id end

-- The first popup: no Back, on the stack.
local p1 = root("首", "鼠", "两端")
eq(#tap:stack(), 1, "one popup")
assert(not button(p1, "Back"), texts(p1))
eq(lastRow(p1), "Close", "Close alone on the bottom row")

-- A character of its text: its own popup on top, the character underlined
-- in the first, looked up with the words around it in that text.
local DEF = "首鼠：鼠性多疑，出洞时一进一退，不能自决；两端：拿不定主意。"
local hit = hitIn(DEF, "疑")
p1.on_char_tap(p1, hit)
eq(#tap:stack(), 2, "two popups")
local p2 = tap:stack()[2]
eq(p2.title, "疑", "the tapped character's popup")
eq(p1.marked, hit, "underlined in the popup below")
assert(texts(p2):find("多疑", 1, true), "a word around it in the popup text: " .. texts(p2))
assert(not button(p2, "Back"), "no Back button: " .. texts(p2))
eq(lastRow(p2), "Close", "Close alone on the bottom row")
eq(p2.anchor, hit.rect, "placed away from the tapped character")
-- Its context line: the popup text's sentence (cut at ；), the character marked.
eq(table.concat(p2.context.chars, ""), "首鼠：鼠性多疑，出洞时一进一退，不能自决；", "context: the popup sentence")
eq(p2.context.chars[p2.context.index], "疑", "the tapped character marked")

-- The Back key: the second goes, the first is shown with no underline.
p2.on_back()
eq(#tap:stack(), 1, "back to one")
eq(p1.marked, nil, "underline gone")
eq(closed[#closed].w, p2, "the second closed")
eq(#unmarked, 0, "the page underline stays")
-- Its Close does the same.
p1.on_char_tap(p1, hitIn(DEF, "端"))
button(tap:stack()[2], "Close").callback()
eq(#tap:stack(), 1); eq(p1.marked, nil); eq(#unmarked, 0)

-- The 秃 of the 史记 citation in an idiom's Origin & Usage view: the nested
-- popup's context is the citation, not the book's sentence; it has no
-- Translate button, only Close.
local VIEW = "典源　《史记．卷一〇七．魏其武安侯列传》\n武安已罢朝，出止车门，召韩御史大夫载，怒曰：「与长孺共一老秃翁，何为首鼠两端？」"
tap:showChuchu("首鼠两端", "xinhua", VIEW, p1)
eq(#tap:stack(), 2, "the Origin & Usage view on the stack")
local view = tap:stack()[2]
eq(view.full, true)
view.on_char_tap(view, hitIn(VIEW, "秃"))
eq(#tap:stack(), 3, "a popup on the view")
local p3 = tap:stack()[3]
eq(p3.title, "秃")
local CITE = "「与长孺共一老秃翁，何为首鼠两端？」"
eq(table.concat(p3.context.chars, ""), CITE, "context line: the citation")
eq(p3.context.chars[p3.context.index], "秃")
eq(button(p3, "Translate"), nil, "no Translate in a nested popup: " .. texts(p3))
eq(lastRow(p3), "Close", "Close at the bottom")
eq(texts(view), "Close", "the Origin & Usage view: only Close")
-- A tap outside closes them all.
local before = #closed
p1.on_outside()
eq(#tap:stack(), 0, "a tap outside closes them all")
eq(#closed - before, 3, "each closed once")
eq(closed[#closed].w, p1, "the first closed last, with the refresh")
eq(unmarked[#unmarked], 7, "the page underline goes")

-- Plain definition prose: the definition's sentence.
p1 = root("首", "鼠", "两端")
p1.on_char_tap(p1, hitIn("形容犹豫不决的样子。语出《史记》。", "豫"))
eq(table.concat(tap:stack()[2].context.chars, ""), "形容犹豫不决的样子。", "a definition sentence")

-- The depth cap: five at most; a sixth tap says so and opens nothing.
for k = 3, 5 do
    local top = tap:stack()[#tap:stack()]
    top.on_char_tap(top, hitIn(DEF, "疑"))
    eq(#tap:stack(), k)
end
local top = tap:stack()[5]
local n_infos = #infos
top.on_char_tap(top, hitIn(DEF, "疑"))
eq(#tap:stack(), 5, "capped at 5")
eq(#infos, n_infos + 1, "a message instead")
assert(infos[#infos].text:find("5", 1, true))
eq(top.marked, nil, "nothing underlined")
-- A Origin & Usage view counts too.
tap:showChuchu("首鼠两端", "xinhua", VIEW, top)
eq(#tap:stack(), 5, "no view past the cap")

-- A tap outside closes them all, top first, one refresh at the end.
before = #closed
local first = tap:stack()[1]
first.on_outside()
eq(#tap:stack(), 0, "all closed")
eq(#closed - before, 5)
for k = before + 1, #closed - 1 do eq(closed[k].refresh, nil, "no refresh before the last") end
eq(closed[#closed].refresh ~= nil, true, "one refresh, with the first")
eq(closed[#closed].w, first, "the first last")

-- Close, one popup at a time: with three open (page -> nested -> Origin & Usage view),
-- the view's Close leaves two, the nested one's leaves the first (its
-- underline cleared), and the first's closes it and the page underline.
p1 = root("首", "鼠", "两端")
p1.on_char_tap(p1, hitIn(DEF, "疑"))
p2 = tap:stack()[2]
p2.on_char_tap(p2, hitIn(DEF, "端"))
eq(#tap:stack(), 3)
p3 = tap:stack()[3]
before = #closed
button(p3, "Close").callback()
eq(#tap:stack(), 2, "Close closes only the top")
eq(closed[#closed].w, p3); eq(#closed - before, 1)
eq(tap:stack()[2], p2, "the one below still shown")
eq(p2.marked, nil, "its underline cleared")
eq(p1.marked ~= nil, true, "the first keeps its underline")
tap:showChuchu("首鼠两端", "xinhua", VIEW, p2)
view = tap:stack()[3]
button(view, "Close").callback()
eq(#tap:stack(), 2, "the Origin & Usage view's Close returns to the popup below")
button(p2, "Close").callback()
eq(#tap:stack(), 1); eq(p1.marked, nil)
local n_unmarked = #unmarked
button(p1, "Close").callback()
eq(#tap:stack(), 0, "the last Close closes the first")
eq(#unmarked, n_unmarked + 1, "and the page underline")
eq(unmarked[#unmarked], 7)
-- The first popup's Back key closes it.
p1 = root("首", "鼠", "两端")
p1.on_back()
eq(#tap:stack(), 0, "Back key on the first popup closes it")

-- A word button in a nested popup: that popup goes (the one below stays,
-- still underlined) and KOReader's dictionary opens with the popup text as
-- context; its close takes the underline away.
local looked
tap.lookupInKOReader = function(_, text, box, opts) looked = { text = text, box = box, opts = opts } end
p1 = root("首", "鼠", "两端")
hit = hitIn(DEF, "疑")
p1.on_char_tap(p1, hit)
button(tap:stack()[2], "多疑").callback()
eq(#tap:stack(), 1, "the nested popup went")
eq(p1.marked, hit, "still underlined below")
eq(looked.text, "多疑")
eq(table.concat(looked.opts.context.chars, ""), "首鼠：鼠性多疑，出洞时一进一退，不能自决；")
looked.opts.on_close()
eq(p1.marked, nil, "the dictionary's close takes the underline")
p1.on_outside()

-- A popup from the page with a Translate row (Wi-Fi on) and enough words to
-- wrap: entries in rows, Translate, then Close alone on the bottom row.
p1 = root("首", "鼠", "两端", function(close) return { { text = "Translate", callback = close } } end)
assert(#p1.buttons >= 3, "entries, Translate, Close: " .. texts(p1))
eq(p1.buttons[#p1.buttons - 1][1].text, "Translate", "Translate above Close")
eq(lastRow(p1), "Close", "Close alone at the bottom")
for k = 1, #p1.buttons - 2 do
    for _, b in ipairs(p1.buttons[k]) do assert(b.text ~= "Close" and b.text ~= "Back", texts(p1)) end
end
-- A popup opened from its text has no Translate row, only Close below its words.
p1.on_char_tap(p1, hitIn(DEF, "疑"))
local nested = tap:stack()[2]
eq(button(nested, "Translate"), nil, "no Translate in a nested popup: " .. texts(nested))
eq(lastRow(nested), "Close")
p1.on_outside()

-- The book's font goes to every popup (the setting on, a crengine book), and
-- to none with the setting off or for another kind of document.
package.loaded["document/credocument"] = { engineInit = function()
    return { getFontFaceFilenameAndFaceIndex = function(name) return "/fonts/" .. name .. ".ttf", 0 end }
end }
plugin.ui.document = { provider = "crengine", getFontFace = function() return "Kai" end }
p1 = root("首", "鼠", "两端")
eq(p1.book_font.path, "/fonts/Kai.ttf", "the book's font")
p1.on_char_tap(p1, hitIn(DEF, "疑"))
eq(tap:stack()[2].book_font.path, "/fonts/Kai.ttf", "nested popups too")
tap:showChuchu("首鼠两端", "xinhua", VIEW, tap:stack()[2])
eq(tap:stack()[3].book_font.path, "/fonts/Kai.ttf", "and the Origin & Usage view")
p1.on_outside()
plugin.settings:set("match_book_font", false)
p1 = root("首", "鼠", "两端")
eq(p1.book_font, nil, "setting off: the UI font")
p1.on_outside()
plugin.settings:set("match_book_font", true)
plugin.ui.document.provider = "mupdf"
p1 = root("首", "鼠", "两端")
eq(p1.book_font, nil, "a PDF: the UI font")
p1.on_outside()

-- The tapped character's frequency rank (#17): on its own entry only, in the
-- first popup and in nested ones; the setting off removes it.
local function ranks(p)
    local out = {}
    for k, b in ipairs(p.blocks) do if b.rank then out[#out + 1] = k .. "=" .. b.rank end end
    return table.concat(out, ",")
end
assert(plugin.settings:charRankEnabled(), "on by default")
p1 = root("", "涓", "")
eq(ranks(p1), "1=字频 4,270", "涓")
p1.on_outside()
-- Inside a chengyu: only the character's own entry, not 九牛一毛 or other words.
p1 = root("九牛一", "毛", "")
eq(ranks(p1), "1=字频 809", "毛 in 九牛一毛")
assert(#p1.blocks > 1, "the chengyu and its words are listed too")
p1.on_outside()
p1 = root("", "㶉", "")
eq(ranks(p1), "1=字频 7,000+", "past 7,000")
p1.on_outside()
-- A nested popup gets its own character's rank.
p1 = root("首", "鼠", "两端")
p1.on_char_tap(p1, hitIn(DEF, "疑"))
local nested_rank = ranks(tap:stack()[2])
assert(nested_rank:match("^1=字频 [%d,]+$"), "nested: " .. nested_rank)
p1.on_outside()
plugin.settings:set("char_rank", false)
p1 = root("", "涓", "")
eq(ranks(p1), "", "setting off: no rank")
p1.on_outside()
plugin.settings:set("char_rank", true)
