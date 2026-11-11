-- Build the plugin (main.lua) against stub KOReader modules: init with the
-- migration, the menu (every label evaluated, so errors that only show up
-- when KOReader builds the menu, such as a loop variable shadowing gettext's
-- `_`, are caught offline), data loading through the real database, and the
-- old-plugin check.
local H = require("sq3_shim")
local eq = H.eq

local function stub(name, value)
    package.loaded[name] = value
end

local Extendable = {}
function Extendable:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
Extendable.new = Extendable.extend

local shown = {}
stub("gettext", function(s) return s end)
stub("logger", { err = function() end, warn = function() end, info = function() end, dbg = function() end })
stub("ffi/util", { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end })
stub("ui/uimanager", { nextTick = function(_, f) f() end, setDirty = function() end,
                       show = function(_, w) shown[#shown + 1] = w end })
stub("ui/event", { new = function(_, ...) return { ... } end })
stub("ui/time", { monotonic = function() return 0 end, to_ms = function() return 0 end })
stub("ui/widget/container/widgetcontainer", Extendable)
stub("ui/widget/infomessage", Extendable)
stub("ui/widget/widget", Extendable)
stub("ffi/blitbuffer", { COLOR_BLACK = 0 })
stub("ui/font", {})
stub("ui/rendertext", {})
stub("ui/size", { span = { horizontal_small = 2 } })
local screen = { w = 1680, h = 1264, dpi = 300 }
stub("device", { screen = { scaleBySize = function(_, v) return v end, getWidth = function() return screen.w end,
                            getHeight = function() return screen.h end, getDPI = function() return screen.dpi end },
                 isTouchDevice = function() return true end })
stub("lua-ljsqlite3/init", H.SQ3)
local data_dir = TEST_KOREADER_DIR
stub("datastorage", { getDataDir = function() return data_dir end })
local dirs = {}
stub("libs/libkoreader-lfs", { attributes = function(path, what) return dirs[path] and "directory" or nil end })

-- This device's settings at the time of the merge.
local settings = {
    interlinearpinyin_enabled = true, interlinearpinyin_tap_definitions = true, interlinearpinyin_threshold = 2500,
}
G_reader_settings = {
    readSetting = function(_, k) return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
    flush = function() end,
}

-- The plugin finds its database at <path>/data/chinesehelper.sqlite.
local Plugin = dofile(PLUGIN_DIR .. "/main.lua")
local plugin = Plugin:new{ path = PLUGIN_DIR }
plugin:init()
eq(settings.chinesehelper_pinyin_enabled, true, "migrated: pinyin on")
eq(settings.chinesehelper_threshold, 2500, "migrated: threshold")
eq(plugin.settings:popupEnabled(), true, "popup on by default (chinesepopup_enabled was never set)")

local menu_items = {}
plugin:addToMainMenu(menu_items)
local entry = assert(menu_items.chinesehelper, "menu entry not registered")
eq(entry.sorting_hint, "tools")
eq(entry.sub_item_table[1].text, "Show pinyin above rare characters")
eq(entry.sub_item_table[2].text, "Tap characters for popup")

local count = 0
local function walk(items)
    for _i, item in ipairs(items) do
        local text = item.text or (item.text_func and item.text_func())
        assert(type(text) == "string" and text ~= "", "menu item without a label")
        if item.checked_func then item.checked_func() end
        count = count + 1
        if item.sub_item_table then walk(item.sub_item_table) end
    end
end
walk(entry.sub_item_table)
eq(count, 10 + 5 + 5 + 3 + 5 + 5 + 3 + 3, "menu size")

-- The two toggles are independent.
local pinyin_item, popup_item = entry.sub_item_table[1], entry.sub_item_table[2]
plugin.tap.update = function() end
popup_item.callback()
eq(plugin.settings:popupEnabled(), false); eq(plugin.settings:pinyinEnabled(), true)
pinyin_item.callback()
eq(plugin.settings:pinyinEnabled(), false); eq(plugin.settings:popupEnabled(), false)
popup_item.callback(); pinyin_item.callback()
assert(plugin.settings:popupEnabled() and plugin.settings:pinyinEnabled())

-- Threshold: saved, label follows.
entry.sub_item_table[3].sub_item_table[1].callback()
assert(entry.sub_item_table[3].text_func():find("1500"), "threshold label not updated")
-- Uncertain readings: default both, choices saved.
assert(entry.sub_item_table[5].text_func():find("show both"))
entry.sub_item_table[5].sub_item_table[2].callback()
eq(plugin.settings:uncertainMode(), "best")
-- Popup text size. A size saved by an earlier version that is no longer a
-- choice (70) shows and checks the default, 60%.
settings.chinesehelper_popup_text_pct = 70
assert(entry.sub_item_table[8].text_func():find("60%%"))
assert(entry.sub_item_table[8].sub_item_table[2].checked_func(), "60% checked")
for k, item in ipairs(entry.sub_item_table[8].sub_item_table) do
    if k ~= 2 then assert(not item.checked_func(), "only 60% checked") end
end
entry.sub_item_table[8].sub_item_table[4].callback()
eq(plugin.settings:popupTextPercent(), 100)
assert(entry.sub_item_table[8].text_func():find("100%%"))

-- Edge pass-through width: default 5 mm, five radio choices, label follows.
local edge_item = entry.sub_item_table[7]
eq(edge_item.text_func(), "Edge pass-through width: 5 mm")
local labels = {}
for _, item in ipairs(edge_item.sub_item_table) do
    labels[#labels + 1] = item.text
    assert(item.radio, "radio choices")
end
eq(table.concat(labels, "|"), "0 mm (off)|2.5 mm|5 mm|7.5 mm|10 mm")
assert(edge_item.sub_item_table[3].checked_func() and not edge_item.sub_item_table[1].checked_func())
edge_item.sub_item_table[2].callback()
eq(settings.chinesehelper_edge_mm, 2.5, "saved"); eq(edge_item.text_func(), "Edge pass-through width: 2.5 mm")

-- The tap handler: the edge band is checked first, before any hit testing,
-- and a change applies to the next tap.
local hits = 0
plugin.tap.hitAt = function() hits = hits + 1; return nil end
plugin.ui = { document = {}, highlight = {} }
local function tap(x, y) return plugin.tap:onTap({ pos = { x = x, y = y } }) end
for k, mm in ipairs({ 2.5, 5, 7.5, 10 }) do
    edge_item.sub_item_table[k + 1].callback()
    eq(settings.chinesehelper_edge_mm, mm, "saved")
    eq(edge_item.text_func(), "Edge pass-through width: " .. mm .. " mm")
    assert(edge_item.sub_item_table[k + 1].checked_func(), mm .. " mm checked")
    local band = ({ 30, 59, 89, 118 })[k]
    eq(plugin.tap:edgeBand(), band, mm .. " mm at 300 dpi")
    for _, p in ipairs({ { band - 1, 600 }, { 1680 - band, 600 }, { 840, band - 1 }, { 840, 1264 - band } }) do
        hits = 0
        eq(tap(p[1], p[2]), false, "edge tap passes through")
        eq(hits, 0, "no hit testing for an edge tap")
    end
    for _, p in ipairs({ { band, 600 }, { 1680 - band - 1, 600 }, { 840, band }, { 840, 1264 - band - 1 } }) do
        hits = 0
        tap(p[1], p[2])
        eq(hits, 1, "just outside the band: hit tested")
    end
end
-- Portrait: the right edge is at 1264.
screen.w, screen.h = 1264, 1680
hits = 0; tap(1264 - 130, 800); eq(hits, 1, "portrait, 10 mm band (118 px): 130 px from the right edge is outside")
hits = 0; tap(1264 - 100, 800); eq(hits, 0, "portrait: within 118 px of the right edge")
-- Portrait at 7.5 mm (89 px), all four edges.
edge_item.sub_item_table[4].callback()
for _, p in ipairs({ { 88, 800 }, { 1264 - 89, 800 }, { 600, 88 }, { 600, 1680 - 89 } }) do
    hits = 0; eq(tap(p[1], p[2]), false, "portrait, 7.5 mm: inside"); eq(hits, 0)
end
for _, p in ipairs({ { 89, 800 }, { 1264 - 90, 800 }, { 600, 89 }, { 600, 1680 - 90 } }) do
    hits = 0; tap(p[1], p[2]); eq(hits, 1, "portrait, 7.5 mm: just outside")
end
screen.w, screen.h = 1680, 1264
-- 0 mm: no band at all, even at the very edge.
edge_item.sub_item_table[1].callback()
eq(plugin.tap:edgeBand(), 0)
for _, p in ipairs({ { 0, 600 }, { 1679, 600 }, { 840, 0 }, { 840, 1263 } }) do
    hits = 0; tap(p[1], p[2]); eq(hits, 1, "0 mm: every tap is hit tested")
end
-- A screen that reports no DPI: 300.
screen.dpi = nil
edge_item.sub_item_table[3].callback()
eq(plugin.tap:edgeBand(), 59)
screen.dpi = 300
plugin.ui = nil

-- Data through the real database: loaded once, shared.
local data = assert(plugin:readings(), "readings")
assert(plugin:readings() == data, "loaded once")
assert(plugin:special(), "special words load when on")
local special_item = entry.sub_item_table[6]
special_item.callback()
assert(not plugin.settings:specialEnabled() and plugin:special() == nil, "nothing when off")
special_item.callback()

-- Old plugins: none present, then one next to this one.
eq(#plugin:oldPluginsPresent(), 0)
plugin:warnOldPlugins()
eq(#shown, 0, "no warning without old plugins")
local parent = PLUGIN_DIR:match("^(.*)/[^/]+$")
dirs[parent .. "/chinesepopup.koplugin"] = true
eq(table.concat(plugin:oldPluginsPresent(), ","), "chinesepopup")
plugin:warnOldPlugins()
eq(#shown, 1, "warning shown")
assert(shown[1].text:find("chinesepopup.koplugin", 1, true), shown[1].text)
plugin:warnOldPlugins()
eq(#shown, 1, "once per session")
-- Loaded (registered on the reader UI) counts too.
dirs = {}
plugin.ui = { interlinearpinyin = {} }
eq(table.concat(plugin:oldPluginsPresent(), ","), "interlinearpinyin")
plugin.ui = nil

-- Status lists what it knows without errors.
plugin:showStatus()
assert(shown[#shown].text:find("CC-CEDICT 2026", 1, true), shown[#shown].text)

-- Line-height: room for 1.2x the pinyin plus 2px either side in the gap
-- between lines, undoing KOReader's line-spacing scale.
local Annotator = require("ch_annotator")
local lh = Annotator.lineHeightFor(64, 40, 100)
assert(math.abs(lh - (1 + (64 * 0.4 * 1.2 + 4) / 64)) < 1e-9, "line height " .. lh)
assert(math.abs(Annotator.lineHeightFor(64, 40, 85) - lh / 0.85) < 1e-9, "line spacing not compensated")
eq(Annotator.lineHeightFor(64, 80, 50), 3.0, "line height capped")

-- Fallback dictionaries: Wiktionary from the plugin database, MOE from the
-- user's file in KOReader's data folder (here a test file), in that order.
local function names(list)
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = s.source end
    return table.concat(out, ",")
end
eq(names(plugin:fallbackSources()), "wikt,moe")
local fb_item = entry.sub_item_table[9]
eq(fb_item.text, "Fallback dictionaries")
-- Source labels: default "other dictionaries only".
local labels_item = fb_item.sub_item_table[1]
eq(labels_item.text_func(), "Source labels: other dictionaries only")
assert(labels_item.sub_item_table[2].checked_func())
labels_item.sub_item_table[1].callback(); eq(plugin.settings:labelMode(), "all")
labels_item.sub_item_table[3].callback(); eq(plugin.settings:labelMode(), "none")
eq(labels_item.text_func(), "Source labels: none")
labels_item.sub_item_table[2].callback()
-- Then the dictionaries, Wiktionary first.
table.remove(fb_item.sub_item_table, 1)
eq(fb_item.sub_item_table[2].text_func(), "MOE 重編國語辭典 (your own file)")
assert(fb_item.sub_item_table[1].checked_func() and fb_item.sub_item_table[2].checked_func())
local status = table.concat(plugin:fallbackStatus(), "\n")
assert(status:find("Wiktionary: on (dump 2026-10-01", 1, true), status)
assert(status:find("MOE 重編國語辭典: on (moedict-data 2026-07-11, 2 entries)", 1, true), status)

-- The tap's fallback lookup: CC-CEDICT's words never; Wiktionary first;
-- MOE for what Wiktionary lacks.
local Model = require("ch_popup_model")
local texts = { "尚", "尚书", "尚书省", "丁匠", "东西" }
local rows = plugin:db():lookup(texts)
local fb = plugin.tap:fallbackRows(texts, rows)
local got = {}
for _, r in ipairs(fb) do got[#got + 1] = r.simp .. ":" .. r.source end
table.sort(got)
eq(table.concat(got, ","), "丁匠:moe,尚书省:wikt")
-- Switch Wiktionary off: MOE gives 尚书省 too.
fb_item.sub_item_table[1].callback()
eq(names(plugin:fallbackSources()), "moe")
got = {}
for _, r in ipairs(plugin.tap:fallbackRows(texts, rows)) do got[#got + 1] = r.simp .. ":" .. r.source end
table.sort(got)
eq(table.concat(got, ","), "丁匠:moe,尚书省:moe")
assert(table.concat(plugin:fallbackStatus(), "\n"):find("Wiktionary: off", 1, true))
-- Both off: nothing beyond CC-CEDICT.
fb_item.sub_item_table[2].callback()
eq(#plugin:fallbackSources(), 0); eq(#plugin.tap:fallbackRows(texts, rows), 0)
fb_item.sub_item_table[1].callback(); fb_item.sub_item_table[2].callback()
eq(names(plugin:fallbackSources()), "wikt,moe")

-- No MOE file (a fresh session, with an empty data folder): Wiktionary only,
-- and the menu says so.
data_dir = "/nonexistent-koreader"
local Plugin2 = dofile(PLUGIN_DIR .. "/main.lua")
local plugin2 = Plugin2:new{ path = PLUGIN_DIR }
plugin2:init()
eq(names(plugin2:fallbackSources()), "wikt")
local items2 = {}
plugin2:addToMainMenu(items2)
local moe_item = items2.chinesehelper.sub_item_table[9].sub_item_table[3]
eq(moe_item.text_func(), "MOE 重編國語辭典 (not installed)")
assert(not moe_item.enabled_func() and not moe_item.checked_func())
assert(table.concat(plugin2:fallbackStatus(), "\n"):find("MOE 重編國語辭典: not installed", 1, true))

G_reader_settings = nil
