-- Build the plugin (main.lua) against stub KOReader modules: init, the menu
-- (every label evaluated, so errors that only show up when KOReader builds
-- the menu, such as a loop variable shadowing gettext's `_`, are caught
-- offline), and data loading through the real database.
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
stub("libs/libkoreader-lfs", { attributes = function() return nil end })
stub("datastorage", { getDataDir = function() return data_dir end, getSettingsDir = function() return data_dir .. "/settings" end })

-- Pinyin on at 2,500; the popup never set.
local settings = { chinesehelper_pinyin_enabled = true, chinesehelper_threshold = 2500 }
G_reader_settings = {
    readSetting = function(_, k) return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
    flush = function() end,
}

-- The plugin finds its database at <path>/data/chinesehelper.sqlite.
local Plugin = dofile(PLUGIN_DIR .. "/main.lua")
local plugin = Plugin:new{ path = PLUGIN_DIR }
plugin:init()
eq(plugin.settings:pinyinEnabled(), true)
eq(plugin.settings:threshold(), 2500)
eq(plugin.settings:popupEnabled(), true, "popup on by default")

local menu_items = {}
plugin:addToMainMenu(menu_items)
local entry = assert(menu_items.chinesehelper, "menu entry not registered")
eq(entry.sorting_hint, "tools")
eq(entry.sub_item_table[1].text, "Show pinyin")
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
eq(count, 19 + 8 + 2 + 5 + 3 + 3 + 5 + 5 + 5 + 8 + 3 + 14, "menu size")   -- frequency ranks: 2 choices; spoken tones: 3 choices; dictionaries: labels, order, collapse (4), 7 dictionaries, MOE's two modes (3 each)

-- Reading marks (#26): right after the special readings, the counts in its
-- label, the file named in its help; its sub-items list and clear.
local marks_item = entry.sub_item_table[9]
eq(marks_item.text_func(), "Known & remind-me readings: 0 known, 0 remind")
assert(marks_item.help_text:find("chinesehelper_marks.lua", 1, true), marks_item.help_text)
local marks_sub = marks_item.sub_item_table_func()
eq(#marks_sub, 2)
assert(not marks_sub[1].enabled_func() and not marks_sub[2].enabled_func(), "nothing to list or clear yet")

-- Character components: on by default, a toggle.
local comp_item = entry.sub_item_table[13]
eq(comp_item.text, "Show character components")
assert(plugin.settings:componentsEnabled() and comp_item.checked_func())
comp_item.callback()
assert(not plugin.settings:componentsEnabled() and not comp_item.checked_func())
comp_item.callback()
assert(plugin.settings:componentsEnabled())

-- The tapped character's frequency rank (#17): on by default, a toggle, right after components.
local rank_item = entry.sub_item_table[14]
eq(rank_item.text, "Show character frequency rank")
assert(plugin.settings:charRankEnabled() and rank_item.checked_func())
rank_item.callback()
assert(not plugin.settings:charRankEnabled() and not rank_item.checked_func())
rank_item.callback()
assert(plugin.settings:charRankEnabled())

-- The context line and the page underline: on by default, each its own toggle.
local ctx_item, ul_item = entry.sub_item_table[15], entry.sub_item_table[16]
eq(ctx_item.text, "Show the text around the character in the popup")
eq(ul_item.text, "Underline the tapped character on the page")
assert(plugin.settings:contextEnabled() and ctx_item.checked_func())
assert(plugin.settings:underlineEnabled() and ul_item.checked_func())
ctx_item.callback()
assert(not plugin.settings:contextEnabled() and plugin.settings:underlineEnabled())
ul_item.callback()
assert(not plugin.settings:underlineEnabled())
ctx_item.callback(); ul_item.callback()
assert(plugin.settings:contextEnabled() and plugin.settings:underlineEnabled())

-- "Try to match the book's font": on by default, a toggle, with help text.
local font_item = entry.sub_item_table[17]
eq(font_item.text, "Try to match the book's font")
assert(font_item.help_text:find("font menu", 1, true), font_item.help_text)
assert(plugin.settings:matchBookFont() and font_item.checked_func())
font_item.callback()
assert(not plugin.settings:matchBookFont() and not font_item.checked_func())
font_item.callback()
assert(plugin.settings:matchBookFont())

-- The two toggles are independent.
local pinyin_item, popup_item = entry.sub_item_table[1], entry.sub_item_table[2]
plugin.tap.update = function() end
popup_item.callback()
eq(plugin.settings:popupEnabled(), false); eq(plugin.settings:pinyinEnabled(), true)
pinyin_item.callback()
eq(plugin.settings:pinyinEnabled(), false); eq(plugin.settings:popupEnabled(), false)
popup_item.callback(); pinyin_item.callback()
assert(plugin.settings:popupEnabled() and plugin.settings:pinyinEnabled())

-- Threshold: saved, label follows. All first, then 500 ... 7000.
local thresholds = entry.sub_item_table[3].sub_item_table
eq(#thresholds, 8)
eq(thresholds[1].text, "All characters (learner mode)")
eq(thresholds[2].text, "Outside the 500 most common")
eq(thresholds[3].text, "Outside the 1000 most common")
eq(thresholds[8].text, "Outside the 7000 most common")
assert(entry.sub_item_table[3].help_text:find("learner mode", 1, true))
thresholds[1].callback()
eq(plugin.settings:threshold(), 0)
eq(entry.sub_item_table[3].text_func(), "Which characters: all")
assert(thresholds[1].checked_func() and not thresholds[4].checked_func())
thresholds[4].callback()
assert(entry.sub_item_table[3].text_func():find("1500"), "threshold label not updated")
-- Frequency ranks (#42): right after Which characters; bundled, From my
-- books disabled while there is no file, the file's path in the help.
local ranks_item = entry.sub_item_table[4]
eq(ranks_item.text_func(), "Frequency ranks: bundled")
assert(ranks_item.help_text_func():find("chinesehelper_ranks.tsv", 1, true))
assert(ranks_item.help_text_func():find("No file yet", 1, true))
eq(#ranks_item.sub_item_table, 2)
assert(ranks_item.sub_item_table[1].checked_func() and not ranks_item.sub_item_table[2].enabled_func())
ranks_item.sub_item_table[2].callback()
eq(plugin.settings:rankSource(), "books")
eq(ranks_item.text_func(), "Frequency ranks: bundled", "chosen but no file: still bundled")
assert(plugin:activeUserRanks() == nil)
ranks_item.sub_item_table[1].callback()
eq(plugin.settings:rankSource(), "bundled")
-- Uncertain readings: default both, choices saved.
assert(entry.sub_item_table[6].text_func():find("show both"))
entry.sub_item_table[6].sub_item_table[2].callback()
eq(plugin.settings:uncertainMode(), "best")
-- Popup text size. A size saved by an earlier version that is no longer a
-- choice (70) shows and checks the default, 60%.
settings.chinesehelper_popup_text_pct = 70
assert(entry.sub_item_table[11].text_func():find("60%%"))
assert(entry.sub_item_table[11].sub_item_table[2].checked_func(), "60% checked")
for k, item in ipairs(entry.sub_item_table[11].sub_item_table) do
    if k ~= 2 then assert(not item.checked_func(), "only 60% checked") end
end
entry.sub_item_table[11].sub_item_table[4].callback()
eq(plugin.settings:popupTextPercent(), 100)
assert(entry.sub_item_table[11].text_func():find("100%%"))
-- Chinese text size: right after it, default 130%, choices saved.
assert(entry.sub_item_table[12].text_func():find("Chinese text size: 130%%"))
assert(entry.sub_item_table[12].sub_item_table[3].checked_func(), "130% checked")
entry.sub_item_table[12].sub_item_table[4].callback()
eq(plugin.settings:chineseTextPercent(), 150)
assert(entry.sub_item_table[12].text_func():find("150%%"))

-- Edge pass-through width: default 5 mm, five radio choices, label follows.
local edge_item = entry.sub_item_table[10]
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
plugin.tap.target = function() hits = hits + 1; return { outcome = "pass" } end
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

-- Outside the band, the decision (ch_area.lua) decides: a popup and a
-- swallowed tap keep the page; a pass, a link or a highlight turn it.
local shown_hits = {}
local real_show = plugin.tap.showPopup
plugin.tap.showPopup = function(_, hit) shown_hits[#shown_hits + 1] = hit.char end
local decision
plugin.tap.target = function() return decision end
decision = { outcome = "popup", hit = { char = "中" }, dist = 12, why = "gap", chars = 30 }
eq(tap(600, 600), true, "popup: no page turn"); eq(shown_hits[1], "中")
assert(plugin.tap.last_tap:find("popup 中 at %?, 12 px from its glyph, gap, 30 chars"), plugin.tap.last_tap)
decision = { outcome = "swallow", why = "no Han within reach", chars = 20 }
eq(tap(600, 600), true, "swallow: no page turn"); eq(#shown_hits, 1, "and no popup")
decision = { outcome = "pass", why = "outside the text", chars = 10 }
eq(tap(600, 600), false, "pass: KOReader's")
decision = { outcome = "popup", hit = { char = "中" }, dist = 0, why = "on glyph", chars = 1 }
plugin.ui.document = { getLinkFromPosition = function() return "#note1" end }
eq(tap(600, 600), false, "on a link: KOReader's"); eq(#shown_hits, 1)
assert(plugin.tap.last_tap:find("pass, link or highlight", 1, true), plugin.tap.last_tap)
plugin.ui.document = {}
plugin.tap.target = function() error("boom") end
eq(tap(600, 600), false, "an error: KOReader's")
plugin.tap.showPopup = real_show
plugin.ui = nil

-- Data through the real database: loaded once, shared.
local data = assert(plugin:readings(), "readings")
assert(plugin:readings() == data, "loaded once")
assert(plugin:special(), "special words load when on")
local special_item = entry.sub_item_table[8]
special_item.callback()
assert(not plugin.settings:specialEnabled() and plugin:special() == nil, "nothing when off")
special_item.callback()

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

-- Fallback dictionaries: Wiktionary and Wikipedia titles from the plugin
-- database; CBDB, MOE and Moegirlpedia from the user's files in KOReader's
-- data folder (here test files, tests/run.py), in the default order.
local function names(list)
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = s.source end
    return table.concat(out, ",")
end
eq(names(plugin:fallbackSources()), "wikt,cbdb,moe,idioms,xinhua,wp,moegirl")
local fb_item = entry.sub_item_table[18]
eq(fb_item.text, "Dictionaries")
-- Source labels: default "other dictionaries only".
local labels_item = fb_item.sub_item_table[1]
eq(labels_item.text_func(), "Source labels: other dictionaries only")
assert(labels_item.sub_item_table[2].checked_func())
labels_item.sub_item_table[1].callback(); eq(plugin.settings:labelMode(), "all")
labels_item.sub_item_table[3].callback(); eq(plugin.settings:labelMode(), "none")
eq(labels_item.text_func(), "Source labels: none")
labels_item.sub_item_table[2].callback()
-- Then Order and Collapse long entries.
eq(fb_item.sub_item_table[2].text, "Order")
local collapse_item = fb_item.sub_item_table[3]
eq(collapse_item.text_func(), "Collapse long entries: 2 lines")
collapse_item.sub_item_table[4].callback(); eq(plugin.settings:collapseLines(), 0)
eq(collapse_item.text_func(), "Collapse long entries: never")
collapse_item.sub_item_table[1].callback(); eq(collapse_item.text_func(), "Collapse long entries: 1 line")
collapse_item.sub_item_table[2].callback()
-- Then the dictionaries, in priority order, each on; MOE's two modes after its switch.
local all_items = fb_item.sub_item_table
local moe_modes = {}
fb_item = { sub_item_table = {} }
for k = 4, #all_items do
    local it = all_items[k]
    if it.sub_item_table then moe_modes[#moe_modes + 1] = it else fb_item.sub_item_table[#fb_item.sub_item_table + 1] = it end
end
eq(#moe_modes, 2)
eq(all_items[7], moe_modes[1], "right after MOE's switch")
eq(moe_modes[1].text_func(), "    MOE for single characters: fallback")
assert(moe_modes[1].sub_item_table[2].checked_func(), "Fallback checked by default")
eq(moe_modes[1].sub_item_table[2].text, "Fallback: only when CC-CEDICT lacks it (default)")
moe_modes[1].sub_item_table[3].callback(); eq(plugin.settings:moeMode("chars"), "always")
eq(moe_modes[1].text_func(), "    MOE for single characters: always")
moe_modes[1].sub_item_table[2].callback(); eq(plugin.settings:moeMode("chars"), "fallback")
eq(moe_modes[2].text_func(), "    MOE for words: fallback")
moe_modes[2].sub_item_table[3].callback(); eq(plugin.settings:moeMode("words"), "always")
assert(moe_modes[2].sub_item_table[3].checked_func())
moe_modes[2].sub_item_table[2].callback()
assert(moe_modes[1].enabled_func())
local function texts(items)
    local out = {}
    for _, it in ipairs(items) do out[#out + 1] = it.text_func() end
    return table.concat(out, " | ")
end
eq(texts(fb_item.sub_item_table), "Wiktionary | CBDB office titles (your own file) | MOE 重編國語辭典 (your own file)"
    .. " | MOE 成語典 (your own file) | Xinhua idioms (your own file)"
    .. " | Wikipedia titles | Moegirlpedia slang (your own file)")
for _, it in ipairs(fb_item.sub_item_table) do assert(it.enabled_func() and it.checked_func()) end
local status = table.concat(plugin:fallbackStatus(), "\n")
assert(status:find("Wiktionary: on (dump 2026-10-01", 1, true), status)
assert(status:find("CBDB office titles: on (CBDB 2026-11-07, 3 entries)", 1, true), status)
assert(status:find("MOE 重編國語辭典: on (moedict-data 2026-07-11, 3 entries, simplified text)", 1, true), status)
assert(status:find("Wikipedia titles: on %(dump %d%d%d%d%-%d%d%-%d%d, %d+ entries%)"), status)
assert(status:find("Moegirlpedia slang: on (snapshot 2023-05-07, 3 entries)", 1, true), status)
assert(status:find("MOE 成語典: on (2020_20260929, 2 idioms, 1 not in CC-CEDICT, simplified text)", 1, true), status)
assert(status:find("Xinhua idioms: on (chinese-xinhua 2018-12-16, 4 idioms, 2 not in CC-CEDICT)", 1, true), status)
assert(status:find("^Wiktionary.*\nCBDB.*\nMOE 重.*\nMOE 成.*\nXinhua.*\nWikipedia.*\nMoegirlpedia"),
    "Status in priority order")

-- The resolver gets Wiktionary's words only (the others are for the popup).
eq(plugin:readings().fallback_key, "wikt")
local seen = {}
for _, r in ipairs(plugin:readings().fallback({ "丁匠", "尚书省", "典史", "红夷大炮", "问题不大" })) do
    seen[#seen + 1] = r.simp .. ":" .. r.source
end
eq(table.concat(seen, ","), "尚书省:wikt", "only Wiktionary asked for readings")

-- The tap's fallback lookup: CC-CEDICT's words never (东西, even though the
-- Moegirlpedia test file has a row for it); then one source per word, in
-- priority order.
local Model = require("ch_popup_model")
local texts_ = { "尚", "尚书", "尚书省", "丁匠", "典史", "试百户", "红夷大炮", "问题不大", "东西", "玉石俱碎", "精兵强将",
                 "一毛不拔" }
local rows = plugin:db():lookup(texts_)
local function lookup()
    local got = {}
    for _, r in ipairs(plugin.tap:fallbackRows(texts_, rows)) do got[#got + 1] = r.simp .. ":" .. r.source end
    table.sort(got)
    return table.concat(got, ",")
end
eq(lookup(), "丁匠:moe,典史:cbdb,尚书省:wikt,玉石俱碎:idioms,精兵强将:xinhua,红夷大炮:wp,试百户:cbdb,问题不大:moegirl")
-- Idioms: the short line and Origin & Usage view, CC-CEDICT's idioms too, the 成語典
-- first; a field it lacks comes from Xinhua.
local function idioms(words)
    local got = {}
    for form, info in pairs(plugin:idiomLookup(words)) do
        got[#got + 1] = form .. ":" .. tostring(info.short_source) .. "/" .. tostring(info.source)
    end
    table.sort(got)
    return table.concat(got, ",")
end
eq(idioms({ "一毛不拔", "玉石俱碎", "精兵强将", "首鼠两端", "东西" }),
   "一毛不拔:idioms/idioms,玉石俱碎:idioms/idioms,精兵強將:xinhua/xinhua,精兵强将:xinhua/xinhua,"
   .. "首鼠两端:xinhua/xinhua,首鼠兩端:xinhua/xinhua")
eq(plugin:idiomLookup({ "一毛不拔" })["一毛不拔"].short, "形容人非常吝啬。贬义。")
eq(idioms({}), "")
local function item(source)
    for _, it in ipairs(fb_item.sub_item_table) do
        if it.text_func():find(Plugin.SOURCE_NAMES[source], 1, true) then return it end
    end
end
-- Switch Wiktionary off: CBDB (before MOE) gives 尚书省.
item("wikt").callback()
eq(names(plugin:fallbackSources()), "cbdb,moe,idioms,xinhua,wp,moegirl")
eq(lookup(), "丁匠:moe,典史:cbdb,尚书省:cbdb,玉石俱碎:idioms,精兵强将:xinhua,红夷大炮:wp,试百户:cbdb,问题不大:moegirl")
assert(table.concat(plugin:fallbackStatus(), "\n"):find("Wiktionary: off", 1, true))
eq(plugin:readings().fallback, nil, "the resolver follows the switch: no Wiktionary, no fallback words")
-- CBDB off too: MOE's 典史 and 尚书省. Wikipedia off: Moegirlpedia's 红夷大炮.
item("cbdb").callback(); item("wp").callback()
eq(lookup(), "丁匠:moe,典史:moe,尚书省:moe,玉石俱碎:idioms,精兵强将:xinhua,红夷大炮:moegirl,问题不大:moegirl")
-- The 成語典 off: Xinhua gives 玉石俱碎 and every idiom's line and view.
item("idioms").callback()
eq(lookup(), "丁匠:moe,典史:moe,尚书省:moe,玉石俱碎:xinhua,精兵强将:xinhua,红夷大炮:moegirl,问题不大:moegirl")
eq(idioms({ "一毛不拔", "玉石俱碎" }), "一毛不拔:xinhua/xinhua,玉石俱碎:xinhua/nil", "Xinhua has no view for 玉石俱碎")
item("xinhua").callback()
eq(idioms({ "一毛不拔" }), "", "both off: no idiom lines")
eq(plugin:readings().fallback, nil, "CBDB, MOE, Moegirlpedia never decide readings")
-- All off: nothing beyond CC-CEDICT, for the resolver too.
item("moe").callback(); item("moegirl").callback()
eq(#plugin:fallbackSources(), 0); eq(lookup(), "")
eq(plugin:readings().fallback, nil)
for _, s in ipairs({ "wikt", "cbdb", "moe", "idioms", "xinhua", "wp", "moegirl" }) do item(s).callback() end
eq(names(plugin:fallbackSources()), "wikt,cbdb,moe,idioms,xinhua,wp,moegirl")

-- The order is a setting (not in the menu): named sources first, the rest
-- after in the default order.
plugin.settings:set("fallback_order", "moe, moegirl,bogus,moe")
eq(names(plugin:fallbackSources()), "moe,moegirl,wikt,cbdb,idioms,xinhua,wp")
eq(lookup(), "丁匠:moe,典史:moe,尚书省:moe,玉石俱碎:idioms,精兵强将:xinhua,红夷大炮:moegirl,试百户:cbdb,问题不大:moegirl")
assert(table.concat(plugin:fallbackStatus(), "\n"):find("^MOE.*\nMoegirlpedia.*\nWiktionary"), "Status follows")
local items3 = {}
plugin:addToMainMenu(items3)
eq(items3.chinesehelper.sub_item_table[18].sub_item_table[4].text_func(), "MOE 重編國語辭典 (your own file)",
   "the menu follows")
-- The popup gets the same order (Model.matches args.order).
eq(table.concat(plugin.settings:fallbackOrder(), ","), "moe,moegirl,wikt,cbdb,idioms,xinhua,wp")
plugin.settings:set("fallback_order", nil)
eq(names(plugin:fallbackSources()), "wikt,cbdb,moe,idioms,xinhua,wp,moegirl")
-- The Order item: KOReader's SortWidget over the seven; its order saved, and
-- the menu's dictionary items rebuilt in it.
local sort_args
package.loaded["ui/widget/sortwidget"] = { new = function(_, a) sort_args = a; return a end }
local items4 = {}
plugin:addToMainMenu(items4)
local dict_menu = items4.chinesehelper.sub_item_table[18].sub_item_table
local updated = 0
dict_menu[2].callback({ updateItems = function() updated = updated + 1 end })
eq(#sort_args.item_table, 7); eq(sort_args.item_table[1].text, "Wiktionary")
local moved = table.remove(sort_args.item_table, 6)   -- Wikipedia titles to the top
table.insert(sort_args.item_table, 1, moved)
sort_args.callback()
eq(plugin.settings:get("fallback_order"), "wp,wikt,cbdb,moe,idioms,xinhua,moegirl")
eq(updated, 1)
eq(dict_menu[4].text_func(), "Wikipedia titles"); eq(#dict_menu, 3 + 7 + 2, "rebuilt, not added to")
plugin.settings:set("fallback_order", nil)

-- The popup with idioms (ch_tap.lua present, with a stand-in for the popup
-- widget): CC-CEDICT's 一毛不拔 gets the 成語典's short line, labelled, and a
-- Origin & Usage button opening its view; 精兵强将 (Xinhua's fallback entry, Chinese
-- already) gets no line under it, and its own Origin & Usage button.
local popups = {}
stub("ch_popup", { BOLD_START = "", BOLD_END = "",
                   new = function(_, args) popups[#popups + 1] = args; args.onClose = function() end; return args end })
stub("ui/widget/textviewer", { new = function(_, args) return args end })
local Text = require("ch_text")
local function popupFor(left, char, right)
    local cands, words = Text.candidates(Text.chars(left), char, Text.chars(right))
    local prows = plugin:db():lookup(words)
    for _, r in ipairs(plugin.tap:fallbackRows(words, prows)) do prows[#prows + 1] = r end
    local m = Model.matches{ cands = cands, rows = prows, order = plugin.settings:fallbackOrder() }
    plugin.tap:present{ db = plugin:db(), char = char, cands = cands, rows = prows, matches = m, annotated = false }
    return popups[#popups]
end
local function buttonTexts(p)
    local out = {}
    for _, r in ipairs(p.buttons) do for _, b in ipairs(r) do out[#out + 1] = b.text end end
    return table.concat(out, ",")
end
local function blockOf(p, word)
    for _, b in ipairs(p.blocks) do if b.head and b.head:find(word, 1, true) == 1 then return b end end
end
local p = popupFor("一", "毛", "不拔")
local b = blockOf(p, "一毛不拔")
eq(b.source, "cedict"); eq(b.note.source, "idioms"); eq(b.note.text, "形容人非常吝啬。贬义。")
eq(p.labels.idioms, "成语典")
assert(buttonTexts(p):find("一毛不拔,成语 Origin & Usage,", 1, true), buttonTexts(p))
local before = #shown
for _, r in ipairs(p.buttons) do for _, btn in ipairs(r) do if btn.text == "成语 Origin & Usage" then btn.callback() end end end
eq(#shown, before + 1, "the Origin & Usage view is shown")
local view = shown[#shown]
eq(view.title, "一毛不拔 · Origin & Usage · 教育部《成语典》")
-- A full-height popup on the stack: the text in the larger Chinese size,
-- no label, only Close; a character tapped in it opens its own popup.
eq(view.full, true); eq(view.blocks[1].large, true); eq(view.blocks[1].nolabel, true)
assert(view.blocks[1].lines[1]:find("典源　《孟子．尽心上》", 1, true), view.blocks[1].lines[1])
eq(buttonTexts(view), "Close")
eq(view.chinese_pct, 150, "the Chinese text size set above")
assert(view.on_char_tap and view.on_back and view.on_outside)
p = popupFor("精", "兵", "强将")
b = blockOf(p, "精兵强将")
eq(b.source, "xinhua"); eq(b.note, nil, "a Chinese entry gets no short line under it")
assert(buttonTexts(p):find("成语 Origin & Usage", 1, true))
-- 首鼠两端: CC-CEDICT's entry, Xinhua's line and view.
p = popupFor("首", "鼠", "两端")
eq(blockOf(p, "首鼠两端").note.source, "xinhua")
assert(buttonTexts(p):find("首鼠两端,成语 Origin & Usage,", 1, true), buttonTexts(p))
-- Both idiom files off: no line, no button.
item("idioms").callback(); item("xinhua").callback()
p = popupFor("一", "毛", "不拔")
eq(blockOf(p, "一毛不拔").note, nil)
assert(not buttonTexts(p):find("Origin & Usage", 1, true), buttonTexts(p))
item("idioms").callback(); item("xinhua").callback()
package.loaded["ch_popup"], package.loaded["ui/widget/textviewer"] = nil, nil

-- No user files (a fresh session, with an empty data folder): the plugin's
-- own two, and the menu and Status say the rest are not installed.
data_dir = "/nonexistent-koreader"
local Plugin2 = dofile(PLUGIN_DIR .. "/main.lua")
local plugin2 = Plugin2:new{ path = PLUGIN_DIR }
plugin2:init()
eq(names(plugin2:fallbackSources()), "wikt,wp")
local items2 = {}
plugin2:addToMainMenu(items2)
local dict_items = {}
local moe_modes2 = {}
for k, it in ipairs(items2.chinesehelper.sub_item_table[18].sub_item_table) do
    if k > 3 then
        if it.sub_item_table then moe_modes2[#moe_modes2 + 1] = it else dict_items[#dict_items + 1] = it end
    end
end
for _, it in ipairs(moe_modes2) do assert(not it.enabled_func(), "MOE's modes greyed out without its file") end
eq(texts(dict_items), "Wiktionary | CBDB office titles (not installed) | MOE 重編國語辭典 (not installed)"
    .. " | MOE 成語典 (not installed) | Xinhua idioms (not installed)"
    .. " | Wikipedia titles | Moegirlpedia slang (not installed)")
for _, k in ipairs({ 2, 3, 4, 5, 7 }) do
    assert(not dict_items[k].enabled_func() and not dict_items[k].checked_func())
end
local status2 = table.concat(plugin2:fallbackStatus(), "\n")
for _, line in ipairs({ "CBDB office titles: not installed", "MOE 重編國語辭典: not installed",
                        "MOE 成語典: not installed", "Xinhua idioms: not installed",
                        "Moegirlpedia slang: not installed" }) do
    assert(status2:find(line, 1, true), status2)
end
-- The lookup still works: Wiktionary and Wikipedia only.
local fb2 = {}
for _, r in ipairs(plugin2:fallbackLookup(Model.uncovered(texts_, rows))) do fb2[#fb2 + 1] = r.simp .. ":" .. r.source end
table.sort(fb2)
eq(table.concat(fb2, ","), "尚书省:wikt,红夷大炮:wp")
eq(next(plugin2:idiomLookup({ "一毛不拔" })), nil, "no idiom files: no idiom lines")
-- One query for both: they share the plugin database.
local pdb = plugin2:db()
local real_fallback, queries = pdb.fallback, 0
pdb.fallback = function(self, list) queries = queries + 1; return real_fallback(self, list) end
plugin2:fallbackLookup(Model.uncovered(texts_, rows))
pdb.fallback = real_fallback
eq(queries, 1, "Wiktionary and Wikipedia titles in one statement")

-- Frequency ranks with a file (#42): From my books can be chosen, the help
-- gives the file's date and works, and the readings follow the setting.
do
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local ds = package.loaded["datastorage"]
    local real_settings_dir = ds.getSettingsDir
    ds.getSettingsDir = function() return dir end
    local path = dir .. "/chinesehelper_ranks.tsv"
    local f = assert(io.open(path, "w"))
    f:write("# date\t2026-11-19\n# works\t42\n# exact\t5700\n饕\t120\t40\t900\n")
    f:close()
    local lfs = package.loaded["libs/libkoreader-lfs"]
    local real_attributes = lfs.attributes
    lfs.attributes = function(p, what) if p == path then return 1 end return nil end
    local items5 = {}
    plugin:addToMainMenu(items5)
    local ranks_item = items5.chinesehelper.sub_item_table[4]
    assert(ranks_item.sub_item_table[2].enabled_func(), "file present: From my books enabled")
    local help = ranks_item.help_text_func()
    assert(help:find("42 works on 2026-11-19", 1, true), help)
    local pub = plugin:readings():publicRank("饕")
    eq((plugin:readings():char("饕")), pub, "bundled until chosen")
    ranks_item.sub_item_table[2].callback()
    eq(ranks_item.text_func(), "Frequency ranks: from my books")
    eq((plugin:readings():char("饕")), 120)
    eq(select(2, plugin:readings():rankInfo("饕")), "books")
    ranks_item.sub_item_table[1].callback()
    eq((plugin:readings():char("饕")), pub)
    lfs.attributes = real_attributes
    ds.getSettingsDir = real_settings_dir
    os.remove(path)
    os.remove(dir)
end

G_reader_settings = nil
