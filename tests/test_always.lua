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

-- The default (#24): MOE Fallback for characters, so 涓 (CC-CEDICT has it)
-- gets no MOE block.
set("components", true)
local p = popup("", "涓", "涓细流")
eq(plugin.settings:moeMode("chars"), "fallback")
eq(block(p, function(b) return b.source == "moe" end), nil, "default: no MOE block for 涓")
assert(shape(p):find("^cedict:涓  juān | components:"), shape(p))

-- Always for characters, chosen in the menu. 涓: CC-CEDICT's entry (with the
-- rank), then MOE's, then the components, then the words.
set("moe_chars", "always")
p = popup("", "涓", "涓细流")
local s = shape(p)
assert(s:find("^cedict:涓  juān | moe%*:涓  juān | components:"), s)
eq(p.blocks[1].rank ~= nil, true, "字频 on CC-CEDICT's entry")
eq(p.blocks[2].rank, nil, "never on MOE's")
eq(p.blocks[2].collapse, true); eq(p.blocks[2].lines[1], "細小的流水。", "MOE's own text (#48)")
eq(p.collapse_lines, 2, "collapse setting passed to the popup")
-- 和: two MOE readings as one block; hàn, which CC-CEDICT lacks, marked.
p = popup("", "和", "平")
local moe = block(p, function(b) return b.always end)
-- The test file has hàn first: CC-CEDICT's readings come first all the same.
eq(moe.head, "和  hé"); eq(moe.lines[2], "hàn · " .. Model.NOT_CEDICT .. ": [連] 連詞。")
eq(p.blocks[2], moe, "right after the character's own entry")
-- Dictionary text: Simplified (#48) leaves MOE's text as MOE writes it (#86).
set("dict_text", "simplified")
p = popup("", "和", "平")
eq(block(p, function(b) return b.always end).lines[2], "hàn · " .. Model.NOT_CEDICT .. ": [連] 連詞。")
set("dict_text", nil)
-- Words stay Fallback by default: 颶風 (CC-CEDICT has it) gets no MOE block.
p = popup("颶", "風", "")
eq(block(p, function(b) return b.source == "moe" end), nil, "words: Fallback")
-- Words Always: MOE's 颶風 shown under CC-CEDICT's, collapsed.
set("moe_words", "always")
p = popup("颶", "風", "")
local w = block(p, function(b) return b.source == "moe" end)
eq(w and w.always, true); eq(w.lines[1], "熱帶氣旋。／風暴。")
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
local cases = { { "", "涓", "涓细流" }, { "", "和", "平" }, { "颶", "風", "" }, { "尚书", "省", "" }, { "", "丁", "匠" } }
for k, c in ipairs(cases) do always_shapes[k] = without(popup(c[1], c[2], c[3])) end
set("moe_chars", "fallback")
for k, c in ipairs(cases) do
    local q = popup(c[1], c[2], c[3])
    eq(block(q, function(b) return b.always end), nil, "Fallback: no Always block for " .. c[2])
    eq(without(q), always_shapes[k], "Fallback: the rest unchanged for " .. c[2])
end
-- A MOE file users built before 2.28.0, left in KOReader's data folder: not
-- read (MOE is bundled), and Status says it can be deleted.
local old_path = TEST_KOREADER_DIR .. "/data/chinesehelper/chinesehelper-moe.sqlite"
local fh = assert(io.open(old_path, "wb")); fh:write("old"); fh:close()
set("moe_chars", "always")
for k, c in ipairs(cases) do
    eq(without(popup(c[1], c[2], c[3])), always_shapes[k], "an old file changes nothing for " .. c[2])
end
local status = table.concat(plugin:fallbackStatus(), "\n")
assert(status:find(old_path .. " is no longer used", 1, true), status)
assert(status:find("MOE 重編國語辭典: on (2026-09-29, 10 entries, as published)", 1, true), status)
assert(status:find("中華民國教育部（Ministry of Education, R.O.C.）。《重編國語辭典修訂本》（版本編號：2026-09-29）", 1, true), status)
assert(status:find("CC BY-ND 3.0 TW (https://creativecommons.org/licenses/by-nd/3.0/tw/)", 1, true), status)
os.remove(old_path)
assert(not table.concat(plugin:fallbackStatus(), "\n"):find("no longer used", 1, true))

-- MOE off: nothing from it at all, whatever its modes.
set("fallback_moe", false)
eq(plugin.settings:moeMode("chars"), "off")
p = popup("", "涓", "涓细流")
eq(block(p, function(b) return b.source == "moe" end), nil)
set("fallback_moe", nil)

-- One query to MOE's file per tap with characters Always.
local mdb = plugin:sourceDb("moe")
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
    for _, r in ipairs(plugin:readings().fallback({ "丁匠", "尚书省", "和", "涓", "颶風", "问题不大" })) do
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

-- Defaults again: one MOE query per tap at most, still.
queries = 0
mdb.fallbackAll, mdb.fallback = function(self, l) queries = queries + 1; return real_all(self, l) end,
    function(self, l) queries = queries + 1; return real_fb(self, l) end
popup("", "涓", "涓细流")
assert(queries <= 1, "MOE queries with the defaults: " .. queries)
mdb.fallbackAll, mdb.fallback = real_all, real_fb

-- Idioms: the short line and Origin & Usage stay as they were.
p = popup("", "一", "毛不拔")
local idiom = block(p, function(b) return b.note ~= nil end)
assert(idiom, "an idiom's short line: " .. shape(p))
print("MOE Always: ok")

-- Words first (#71): the words' blocks, then the character's group (its
-- CC-CEDICT entry with the rank, its MOE Always entry, the components), then
-- the Chinese-text dictionaries' blocks. Off: as before.
do
    local function groups(p)
        local char, words, chinese = {}, {}, {}
        for k, b in ipairs(p.blocks) do
            local tag = b.components and "components" or ((b.source or "?") .. (b.always and "*" or ""))
            tag = tag .. ":" .. (b.head or "") .. (b.rank and "+rank" or "") .. (b.spoken and "+spoken" or "")
            if Model.LARGE_SOURCES[b.source] and not b.always then chinese[#chinese + 1] = tag
            elseif b.components or (b.head and b.head:find("^" .. p.char_tapped .. " ")) then char[#char + 1] = tag
            else words[#words + 1] = tag end
        end
        return char, words, chinese
    end
    local function tagged(p)
        local out = {}
        for _, b in ipairs(p.blocks) do
            local tag = b.components and "components" or ((b.source or "?") .. (b.always and "*" or ""))
            out[#out + 1] = tag .. ":" .. (b.head or "") .. (b.rank and "+rank" or "") .. (b.spoken and "+spoken" or "")
        end
        return table.concat(out, " | ")
    end
    local function both(left, char, right, spoken)
        local function one()
            local found = tap:lookup(plugin:db(), char, Text.chars(left), Text.chars(right), resolve)
            local p = tap:present{ db = plugin:db(), char = char, cands = found.cands, rows = found.rows,
                                   matches = found.matches, annotated = false, spoken = spoken }
            p.char_tapped = char
            return p
        end
        set("words_first", false)
        local off = one()
        set("words_first", nil)   -- the default: on
        assert(plugin.settings:wordsFirst(), "on by default")
        local on = one()
        return off, on
    end
    local function check(left, char, right, spoken, what)
        local off, on = both(left, char, right, spoken)
        local c, w, z = groups(off)
        local want = {}
        for _, t in ipairs(w) do want[#want + 1] = t end
        for _, t in ipairs(c) do want[#want + 1] = t end
        for _, t in ipairs(z) do want[#want + 1] = t end
        eq(tagged(on, char), table.concat(want, " | "), what)
        return off, on
    end
    for _, mode in ipairs({ "fallback", "always" }) do
        set("moe_chars", mode); set("moe_words", mode)
        for _, comp in ipairs({ true, false }) do
            set("components", comp)
            local off, on = check("", "涓", "涓细流", nil, "涓 " .. mode .. tostring(comp))
            assert(tagged(off, "涓"):find("^cedict:涓  juān%+rank"), "off: as before " .. tagged(off, "涓"))
            assert(not tagged(on, "涓"):find("^cedict:涓 "), "on: a word first " .. tagged(on, "涓"))
            local _, n = tagged(on, "涓"):gsub("rank", "")
            eq(n, 1, "one rank, on 涓's own entry: " .. tagged(on, "涓"))
            if mode == "always" then
                assert(tagged(on, "涓"):find("cedict:涓  juān%+rank | moe%*:涓  juān"), tagged(on, "涓"))
            end
            if comp then assert(tagged(on, "涓"):find(" | components:$"), "components last: " .. tagged(on, "涓")) end
            check("", "和", "平", nil, "和 " .. mode)
            -- No words around it: nothing changes.
            local alone_off, alone_on = both("", "涓", "")
            eq(tagged(alone_on, "涓"), tagged(alone_off, "涓"), "涓 alone " .. mode)
        end
    end
    set("moe_chars", nil); set("moe_words", nil); set("components", true)
    -- The spoken note (#37) stays on the character's own entry, with the rank.
    local off, on = check("", "不", "是", "bú", "不是")
    assert(tagged(on, "不"):find("cedict:不  bù%+rank%+spoken"), tagged(on, "不"))
    assert(not tagged(on, "不"):find("^cedict:不 "), tagged(on, "不"))
    set("words_first", nil)
end
print("words first: ok")
