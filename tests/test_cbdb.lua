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
-- Words first (#71) is on by default; these tests check the character-first
-- order (as before 2.23.0) unless they switch it on.
local settings = { chinesehelper_words_first = false }
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
    args.setHidden = function(p, hidden) p.hidden = hidden and true or false end
    args.onClose = function(p, region, tall)
        require("ui/uimanager"):close(p, tall and "flashpartial" or "partial", region)
    end
    return args
end
stub("ch_popup", Popup)

local Plugin = dofile(PLUGIN_DIR .. "/main.lua")
local plugin = Plugin:new{ path = PLUGIN_DIR, moe_path = TEST_MOE_PATH }
plugin:init()
plugin.ui = { highlight = { onTranslateText = function() end } }
local tap = plugin.tap
tap.textHeight = function() return 64 end
local Model = require("ch_popup_model")
local Text = require("ch_text")
local DB = require("ch_db")

-- The popup for `char` in left..char..right, through Tap:lookup (the real
-- fallback and Always path) and Tap:present (the fake popup keeps its args).
local resolve = function() return nil end
local function popup(left, char, right)
    local found = tap:lookup(plugin:db(), char, Text.chars(left), Text.chars(right), resolve)
    return tap:present{ db = plugin:db(), char = char, cands = found.cands, rows = found.rows,
                        matches = found.matches, annotated = false }, found
end

local function set(k, v) settings["chinesehelper_" .. k] = v end

-- The text helpers: the characters just outside the tapped run, and when
-- that run is exactly a book title.
eq(Text.edgeBefore("见《隋", Text.hanSuffix("见《隋")), "《")
eq(Text.edgeAfter("书》卷", Text.hanPrefix("书》卷")), "》")
eq(Text.edgeBefore("隋", Text.hanSuffix("隋")), nil, "the start of the text")
eq(Text.edgeBefore("《一二三四五六七", Text.hanSuffix("《一二三四五六七")), nil, "the run reached its maximum")
eq(Text.bookTitle({}, "隋", { "书" }, "《", "》"), "隋书")
eq(Text.bookTitle({ "新", "唐" }, "书", {}, "《", "·"), "新唐书", "the book before a chapter")
eq(Text.bookTitle({}, "唐", { "书" }, "新", "》"), nil, "part of a title")
eq(Text.bookTitle({}, "隋", { "书" }, "“", "”"), nil, "not in 《》")
eq(Text.bookTitle({}, "书", {}, "《", "》"), nil, "a single character")

local function lookup(left, char, right, edges)
    return tap:lookup(plugin:db(), char, Text.chars(left), Text.chars(right), resolve, edges)
end
-- CBDB's words in a lookup: its entries and its Always blocks (#88).
local function cbdbWords(found)
    local out, seen = {}, {}
    for _, m in ipairs(found.matches) do
        local own = m.entries[1] and m.entries[1].source == "cbdb"
        if (own or m.cbdb) and not seen[m.word] then out[#out + 1], seen[m.word] = m.word, true end
    end
    table.sort(out)
    return table.concat(out, ",")
end
-- "source:word" per block ("*" for an Always block), "|" between.
local function shape(left, char, right, edges)
    local found = lookup(left, char, right, edges)
    local p = tap:present{ db = plugin:db(), char = char, cands = found.cands, rows = found.rows,
                           matches = found.matches, annotated = false }
    local out = {}
    for _, b in ipairs(p.blocks) do
        local word = (b.head or ""):match("^(%S+)") or ""
        out[#out + 1] = (b.components and "components" or (b.source or "?")) .. (b.always and "*" or "") .. ":" .. word
    end
    return table.concat(out, " | ")
end

eq(plugin.settings:cbdbMode(), "always", "the default (#88)")
eq(table.concat(plugin.settings:fallbackOrder(), ","), "cbdb,wikt,moe,idioms,xinhua,wp,moegirl", "CBDB first")

-- Book titles: only for the whole run inside 《》.
local title = { before = "《", after = "》" }
eq(cbdbWords(lookup("", "隋", "书", title)), "隋书", "《隋书》")
eq(cbdbWords(lookup("", "隋", "书", nil)), "", "隋书 without 《》")
eq(cbdbWords(lookup("", "隋", "书", { before = "，", after = "》" })), "", "not opened by 《")
eq(cbdbWords(lookup("", "隋", "书", { before = "《", after = "·" })), "隋书", "《隋书·地理志》")
local s = shape("", "隋", "书", title)
assert(s:find("cedict:隋书 | cbdb*:隋书", 1, true), s)

-- Office titles: shown where the word fits the segmentation, never when it
-- cuts through one of its words (考试 in 考试百户).
eq(cbdbWords(lookup("", "试", "百户", nil)), "试百户", "试百户 on its own")
eq(cbdbWords(lookup("考", "试", "百户", nil)), "", "试百户 cuts through 考试")

-- People CC-CEDICT has (#88): CBDB's entry right after CC-CEDICT's.
s = shape("", "王", "安石")
assert(s:find("cedict:王安石 | cbdb*:王安石", 1, true), s)
local found = lookup("", "王", "安石")
for _, m in ipairs(found.matches) do
    if m.word == "王安石" then
        eq(m.entries[1].source, "cedict"); eq(m.cbdb[1].source, "cbdb")
        assert(m.cbdb[1].senses[1]:find("字 介甫", 1, true), m.cbdb[1].senses[1])
    end
end
-- Words first: the same pair, now above the character's entry.
set("words_first", true)
s = shape("", "王", "安石")
assert(s:find("^cedict:王安石 | cbdb%*:王安石"), s)
set("words_first", false)
-- With MOE Always for words: CBDB's block before MOE's (尚书省: Wiktionary's
-- entry first in an order that puts it before CBDB, then CBDB's, then MOE's).
set("moe_words", "always")
s = shape("", "尚", "书省")
assert(s:find("cbdb:尚书省 | moe*:尚书省", 1, true), "CBDB first in the default order: " .. s)
plugin.settings:setFallbackOrder({ "wikt", "cbdb", "moe" })
s = shape("", "尚", "书省")
assert(s:find("wikt:尚书省 | cbdb*:尚书省 | moe*:尚书省", 1, true), s)
plugin.settings:set("fallback_order", nil)
set("moe_words", nil)
-- Classical mode: the 文言 entry stays at the top.
set("classical_mode", true)
s = shape("", "王", "安石")
assert(s:find("^classical:") and s:find("cedict:王安石 | cbdb*:王安石", 1, true), s)
set("classical_mode", nil)

-- Fallback: only words CC-CEDICT lacks, so no 王安石 and no 隋书.
set("cbdb_mode", "fallback")
eq(cbdbWords(lookup("", "王", "安石")), "")
eq(cbdbWords(lookup("", "隋", "书", title)), "", "CC-CEDICT has 隋书")
eq(cbdbWords(lookup("", "试", "百户", nil)), "试百户")
-- Off, from its mode or its switch: nothing of it.
set("cbdb_mode", "off")
eq(cbdbWords(lookup("", "王", "安石")) .. cbdbWords(lookup("", "试", "百户", nil)), "", "mode off")
set("cbdb_mode", nil)
set("fallback_cbdb", false)
eq(cbdbWords(lookup("", "王", "安石")) .. cbdbWords(lookup("", "隋", "书", title)), "", "switched off")
set("fallback_cbdb", true)

print("CBDB: ok")
