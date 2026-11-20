-- Settings and their defaults (ch_settings.lua).
local Settings = require("ch_settings")
local eq = require("sq3_shim").eq

local function store(values)
    local s = { values = values or {}, flushed = 0 }
    function s:readSetting(k) return self.values[k] end
    function s:saveSetting(k, v) self.values[k] = v end
    function s:flush() self.flushed = self.flushed + 1 end
    return s
end

-- Defaults: pinyin off, popup on.
local s = Settings.new(store())
eq(s:pinyinEnabled(), false); eq(s:popupEnabled(), true)
eq(s:threshold(), 3500); eq(s:sizePercent(), 40); eq(s:uncertainMode(), "both")
eq(s:specialEnabled(), true); eq(s:specialStyle(), "bold"); eq(s:popupTextPercent(), 60)

-- Values set under this plugin's keys are read back; set() writes to disk.
local st = store{
    chinesehelper_pinyin_enabled = true, chinesehelper_threshold = 2500, chinesehelper_size_pct = 50,
    chinesehelper_uncertain = "best", chinesehelper_special = false,
    chinesehelper_special_style = "underline", chinesehelper_popup_enabled = false,
}
s = Settings.new(st)
eq(s:pinyinEnabled(), true); eq(s:threshold(), 2500); eq(s:sizePercent(), 50)
eq(s:uncertainMode(), "best"); eq(s:specialEnabled(), false); eq(s:specialStyle(), "underline")
eq(s:popupEnabled(), false)
s:set("threshold", 5000)
eq(s:threshold(), 5000); assert(st.flushed > 0, "written to disk")

-- Traditional forms on the head lines (#47): on by default.
eq(Settings.new(store()):tradHeadsEnabled(), true)
eq(Settings.new(store{ chinesehelper_trad_heads = false }):tradHeadsEnabled(), false)
-- Classical mode (#53): off by default.
eq(Settings.new(store()):classicalEnabled(), false)
eq(Settings.new(store{ chinesehelper_classical_mode = true }):classicalEnabled(), true)

-- Thresholds: All (0), 500 and 1,000 as well as the old steps; anything else
-- is the default.
for _, t in ipairs({ 0, 500, 1000, 1500, 2500, 3500, 5000, 7000 }) do
    eq(Settings.new(store{ chinesehelper_threshold = t }):threshold(), t)
end
eq(Settings.new(store{ chinesehelper_threshold = 1200 }):threshold(), 3500)
eq(Settings.new(store{ chinesehelper_threshold = -1 }):threshold(), 3500)

-- Out-of-range values come back valid.
s = Settings.new(store{ chinesehelper_uncertain = "nonsense", chinesehelper_size_pct = 500,
                        chinesehelper_special_style = "x", chinesehelper_popup_text_pct = 1 })
eq(s:uncertainMode(), "both"); eq(s:sizePercent(), 80); eq(s:specialStyle(), "bold"); eq(s:popupTextPercent(), 60)
-- Popup text size: exactly the menu's choices; an old 70 falls back to the default.
for _, pct in ipairs({ 40, 60, 80, 100, 120 }) do
    eq(Settings.new(store{ chinesehelper_popup_text_pct = pct }):popupTextPercent(), pct)
end
eq(Settings.new(store{ chinesehelper_popup_text_pct = 70 }):popupTextPercent(), 60)
-- Chinese text size: default 130%, the menu's choices, anything else the default.
eq(Settings.new(store()):chineseTextPercent(), 130)
for _, pct in ipairs({ 100, 115, 130, 150, 175 }) do
    eq(Settings.new(store{ chinesehelper_chinese_text_pct = pct }):chineseTextPercent(), pct)
end
eq(Settings.new(store{ chinesehelper_chinese_text_pct = 120 }):chineseTextPercent(), 130)
-- Edge width: every choice saved by 1.1.0 or later is kept as it is, 7.5 mm
-- included; no setting is the default 5 mm; anything else falls back to it.
eq(Settings.new(store()):edgeMm(), 5)
for _, mm in ipairs({ 0, 2.5, 5, 7.5, 10 }) do
    eq(Settings.new(store{ chinesehelper_edge_mm = mm }):edgeMm(), mm)
end
eq(Settings.new(store{ chinesehelper_edge_mm = 7 }):edgeMm(), 5)
s:set("threshold", 1500); eq(s:threshold(), 1500)
s:set("threshold", 1234); eq(s:threshold(), 3500, "not one of THRESHOLDS: the default")
s:set("threshold", "2500"); eq(s:threshold(), 2500)
s:set("threshold", 1500)
-- Source labels: default "fallback"; anything else unknown falls back to it.
eq(Settings.new(store()):labelMode(), "fallback")
eq(Settings.new(store{ chinesehelper_labels = "all" }):labelMode(), "all")
eq(Settings.new(store{ chinesehelper_labels = "x" }):labelMode(), "fallback")
eq(Settings.new(store()):fallbackEnabled("wikt"), true); eq(Settings.new(store()):fallbackEnabled("moe"), true)
for _, src in ipairs({ "wp", "cbdb", "moegirl", "idioms", "xinhua" }) do eq(Settings.new(store()):fallbackEnabled(src), true) end
-- The fallback priority: the default, a setting naming some (the rest
-- follow in the default order), unknown names, repeats and junk ignored.
eq(table.concat(Settings.new(store()):fallbackOrder(), ","), "wikt,cbdb,moe,idioms,xinhua,wp,moegirl")
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = "moegirl,wikt" }):fallbackOrder(), ","),
   "moegirl,wikt,cbdb,moe,idioms,xinhua,wp")
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = " wp , x,wp" }):fallbackOrder(), ","),
   "wp,wikt,cbdb,moe,idioms,xinhua,moegirl")
-- A saved order from before 1.9.0 (no idiom sources): they follow in the default order.
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = "wikt,cbdb,moe,wp,moegirl" }):fallbackOrder(),
   ","), "wikt,cbdb,moe,wp,moegirl,idioms,xinhua")
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = 5 }):fallbackOrder(), ","),
   "wikt,cbdb,moe,idioms,xinhua,wp,moegirl")
-- No settings store at all (tests, odd starts): defaults, no errors.
s = Settings.new(nil); eq(s:threshold(), 3500); s:set("threshold", 1); eq(s:threshold(), 3500)

-- "Try to match the book's font": on by default, toggled from the menu.
s = Settings.new(store())
eq(s:matchBookFont(), true, "match the book's font: on by default")
s:set("match_book_font", false)
eq(s:matchBookFont(), false)

-- MOE's modes (#11): Fallback for characters (#24: Always in 2.5.0-2.5.2) and
-- for words; MOE off overrides both; odd values fall back to the defaults.
s = Settings.new(store())
eq(s:moeMode("chars"), "fallback"); eq(s:moeMode("words"), "fallback"); eq(s:collapseLines(), 2)
-- Migration from 2.4.0: fallback_moe = false stays off, true gets the defaults,
-- and an existing fallback_order is the order.
st = store{ chinesehelper_fallback_moe = false, chinesehelper_fallback_order = "moe,wikt" }
s = Settings.new(st)
eq(s:moeMode("chars"), "off"); eq(s:moeMode("words"), "off")
eq(table.concat(s:fallbackOrder(), ","), "moe,wikt,cbdb,idioms,xinhua,wp,moegirl")
st = store{ chinesehelper_fallback_moe = true }
s = Settings.new(st)
eq(s:moeMode("chars"), "fallback"); eq(s:moeMode("words"), "fallback")
-- A mode chosen in the menu (stored) is kept: "always" stays Always.
st.values.chinesehelper_moe_chars = "always"; eq(s:moeMode("chars"), "always")
st.values.chinesehelper_moe_chars = "bogus"; eq(s:moeMode("chars"), "fallback")
st.values.chinesehelper_moe_chars = "fallback"; st.values.chinesehelper_moe_words = "bogus"
eq(s:moeMode("chars"), "fallback"); eq(s:moeMode("words"), "fallback")
st.values.chinesehelper_moe_words = "off"; eq(s:moeMode("words"), "off")
for _, n in ipairs({ 1, 3, 0 }) do st.values.chinesehelper_collapse_lines = n; eq(s:collapseLines(), n) end
st.values.chinesehelper_collapse_lines = 7; eq(s:collapseLines(), 2)
s:setFallbackOrder({ "wp", "moe" })
eq(st.values.chinesehelper_fallback_order, "wp,moe")
eq(table.concat(s:fallbackOrder(), ","), "wp,moe,wikt,cbdb,idioms,xinhua,moegirl")
