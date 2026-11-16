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
stub("datastorage", { getDataDir = function() return TEST_KOREADER_DIR end })
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
-- "source:head" per block, "|" between ("moe*" for an Always block).
local function shape(p)
    local out = {}
    for _, b in ipairs(p.blocks) do
        local tag = b.components and "components" or ((b.source or "?") .. (b.always and "*" or ""))
        out[#out + 1] = tag .. ":" .. (b.head or "")
    end
    return table.concat(out, " | ")
end
local function block(p, pred)
    for _, b in ipairs(p.blocks) do if pred(b) then return b end end
end
local function set(k, v) settings["chinesehelper_" .. k] = v end

-- Defaults: MOE Always for characters. 涓: CC-CEDICT's entry (with the rank),
-- then MOE's, then the components, then the words.
set("components", true)
local p = popup("", "涓", "涓细流")
local s = shape(p)
assert(s:find("^cedict:涓  juān | moe%*:涓  juān | components:"), s)
eq(p.blocks[1].rank ~= nil, true, "字频 on CC-CEDICT's entry")
eq(p.blocks[2].rank, nil, "never on MOE's")
eq(p.blocks[2].collapse, true); eq(p.blocks[2].lines[1], "细小的流水。")
eq(p.collapse_lines, 2, "collapse setting passed to the popup")
-- 和: two MOE readings as one block; hàn, which CC-CEDICT lacks, marked.
p = popup("", "和", "平")
local moe = block(p, function(b) return b.always end)
-- (The test file has hàn first.)
eq(moe.head, "和  hàn · " .. Model.NOT_CEDICT); eq(moe.lines[2], "hé: 连带。; 平静。")
eq(p.blocks[2], moe, "right after the character's own entry")
-- Words stay Fallback by default: 台風 (only covered rows in MOE: CC-CEDICT
-- has 颱風) is not shown.
p = popup("台", "風", "")
eq(block(p, function(b) return b.head and b.head:find("台風") end), nil, "words: Fallback")
-- Words Always: MOE's 台風 shown, as the word's own entry (nothing above it to
-- collapse under).
set("moe_words", "always")
p = popup("台", "風", "")
local w = block(p, function(b) return b.head and b.head:find("台風") end)
eq(w and w.head, "台風  tái fēng"); eq(w.source, "moe"); eq(w.always, nil)
set("moe_words", nil)

-- Everything but the Always blocks is what MOE on Fallback gives, which is
-- 2.4.0's popup: same blocks with the Always ones taken out.
local function without(p_)
    local out = {}
    for _, b in ipairs(p_.blocks) do
        if not b.always then out[#out + 1] = (b.source or "c") .. "|" .. (b.head or "") .. "|" .. table.concat(b.lines or {}, "/") .. "|" .. tostring(b.rank) end
    end
    return table.concat(out, "\n")
end
local always_shapes = {}
local cases = { { "", "涓", "涓细流" }, { "", "和", "平" }, { "台", "風", "" }, { "尚书", "省", "" }, { "", "丁", "匠" } }
for k, c in ipairs(cases) do always_shapes[k] = without(popup(c[1], c[2], c[3])) end
set("moe_chars", "fallback")
for k, c in ipairs(cases) do
    local q = popup(c[1], c[2], c[3])
    eq(block(q, function(b) return b.always end), nil, "Fallback: no Always block for " .. c[2])
    eq(without(q), always_shapes[k], "Fallback: the rest unchanged for " .. c[2])
end
-- An old MOE file (no covered rows, no meta flag): Always behaves as Fallback.
set("moe_chars", nil)
local real_localDb = plugin.localDb
local old = DB.open(TEST_KOREADER_DIR .. "/moe-old.sqlite", H.SQ3)
plugin.localDb = function(self, source)
    if source == "moe" then return old end
    return real_localDb(self, source)
end
eq(plugin:moeHasCovered(), false)
for k, c in ipairs(cases) do
    local q = popup(c[1], c[2], c[3])
    eq(block(q, function(b) return b.always end), nil, "old file: no Always block for " .. c[2])
    eq(without(q), always_shapes[k], "old file: as Fallback for " .. c[2])
end
local status = table.concat(plugin:fallbackStatus(), "\n")
assert(status:find("rebuild", 1, true), "Status says to rebuild: " .. status)
plugin.localDb = real_localDb
old:close()
eq(plugin:moeHasCovered(), true)

-- MOE off: nothing from it at all, whatever its modes.
set("fallback_moe", false)
eq(plugin.settings:moeMode("chars"), "off")
p = popup("", "涓", "涓细流")
eq(block(p, function(b) return b.source == "moe" end), nil)
set("fallback_moe", nil)

-- Characters Off: no MOE fallback entry for a single character either, and
-- one query to MOE's file per tap with the defaults.
local mdb = plugin:localDb("moe")
local queries = 0
local real_all, real_fb = mdb.fallbackAll, mdb.fallback
mdb.fallbackAll = function(self, l) queries = queries + 1; return real_all(self, l) end
mdb.fallback = function(self, l) queries = queries + 1; return real_fb(self, l) end
popup("", "涓", "涓细流")
eq(queries, 1, "one MOE query per tap")
queries = 0
popup("", "和", "平")
eq(queries, 1, "one MOE query per tap")
mdb.fallbackAll, mdb.fallback = real_all, real_fb

-- The reading path: Wiktionary's fallback rows only, never a covered row,
-- whatever MOE's modes.
local function readingRows()
    local out = {}
    for _, r in ipairs(plugin:readings().fallback({ "丁匠", "尚书省", "和", "涓", "台風", "问题不大" })) do
        out[#out + 1] = r.simp .. ":" .. r.source .. ":" .. tostring(r.covered)
    end
    return table.concat(out, ",")
end
local base = readingRows()
eq(plugin:readings().fallback_key, "wikt")
for _, chars in ipairs({ "off", "fallback", "always" }) do
    for _, words in ipairs({ "off", "fallback", "always" }) do
        set("moe_chars", chars); set("moe_words", words)
        eq(readingRows(), base, "reading rows with MOE " .. chars .. "/" .. words)
        eq(plugin:readings().fallback_key, "wikt")
    end
end
assert(not base:find("moe", 1, true), base)
set("moe_chars", nil); set("moe_words", nil)

-- Idioms: the short line and Origin & Usage stay as they were.
p = popup("", "一", "毛不拔")
local idiom = block(p, function(b) return b.note ~= nil end)
assert(idiom, "an idiom's short line: " .. shape(p))
print("MOE Always: ok")
