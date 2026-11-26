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
local function cbdbRows(found)
    local out = {}
    for _, r in ipairs(found.rows) do if r.source == "cbdb" then out[#out + 1] = r.simp end end
    table.sort(out)
    return table.concat(out, ",")
end

-- Book titles: only for the whole run inside 《》.
local title = { before = "《", after = "》" }
eq(cbdbRows(lookup("", "隋", "书", title)), "隋书", "《隋书》")
eq(cbdbRows(lookup("", "隋", "书", nil)), "", "隋书 without 《》")
eq(cbdbRows(lookup("", "隋", "书", { before = "，", after = "》" })), "", "not opened by 《")
eq(cbdbRows(lookup("", "隋", "书", { before = "《", after = "·" })), "隋书", "《隋书·地理志》")
local book = lookup("", "隋", "书", title).rows
for _, r in ipairs(book) do
    if r.source == "cbdb" then eq(r.defs, "book title"); eq(r.pinyin, "Suí Shū") end
end

-- Office titles: shown where the word fits the segmentation, never when it
-- cuts through one of its words (考试 in 考试百户).
eq(cbdbRows(lookup("", "试", "百户", nil)), "试百户", "试百户 on its own")
eq(cbdbRows(lookup("考", "试", "百户", nil)), "", "试百户 cuts through 考试")

-- CBDB switched off: nothing of it, books included.
set("fallback_cbdb", false)
eq(cbdbRows(lookup("", "试", "百户", nil)), "", "off: no office titles")
eq(cbdbRows(lookup("", "隋", "书", title)), "", "off: no book titles")
set("fallback_cbdb", true)

print("CBDB: ok")
