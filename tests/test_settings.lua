-- Settings and the migration from the two old plugins (ch_settings.lua).
local Settings = require("ch_settings")
local eq = require("sq3_shim").eq

local function store(values)
    local s = { values = values or {}, flushed = 0 }
    function s:readSetting(k) return self.values[k] end
    function s:saveSetting(k, v) self.values[k] = v end
    function s:flush() self.flushed = self.flushed + 1 end
    return s
end

-- Defaults: pinyin off (as interlinear-pinyin), popup on (as chinese-popup).
local s = Settings.new(store())
eq(s:pinyinEnabled(), false); eq(s:popupEnabled(), true)
eq(s:threshold(), 3500); eq(s:sizePercent(), 40); eq(s:uncertainMode(), "both")
eq(s:specialEnabled(), true); eq(s:specialStyle(), "bold"); eq(s:popupTextPercent(), 60)

-- This device's settings at the time of the merge, plus every other old key.
local st = store{
    interlinearpinyin_enabled = true, interlinearpinyin_tap_definitions = true,
    interlinearpinyin_threshold = 2500, interlinearpinyin_size_pct = 50,
    interlinearpinyin_uncertain = "best", interlinearpinyin_special = false,
    interlinearpinyin_special_style = "underline", chinesepopup_enabled = false,
}
s = Settings.new(st)
local copied = s:migrate()
eq(#copied, 7, "every old key with a successor copied")
eq(s:pinyinEnabled(), true); eq(s:threshold(), 2500); eq(s:sizePercent(), 50)
eq(s:uncertainMode(), "best"); eq(s:specialEnabled(), false); eq(s:specialStyle(), "underline")
eq(s:popupEnabled(), false, "chinesepopup_enabled")
eq(st.values.interlinearpinyin_threshold, 2500, "old keys left in place")
assert(st.values.chinesehelper_migrated, "marked as migrated")
assert(st.flushed > 0, "written to disk")
-- Only once: a later change to an old key is not copied again.
st.values.interlinearpinyin_threshold = 7000
eq(#s:migrate(), 0); eq(s:threshold(), 2500)

-- Never overwrites a value already set under the new key.
st = store{ interlinearpinyin_threshold = 2500, chinesehelper_threshold = 5000 }
s = Settings.new(st); s:migrate()
eq(s:threshold(), 5000)
-- Nothing to migrate: still marked, nothing copied.
st = store()
s = Settings.new(st); eq(#s:migrate(), 0); assert(st.values.chinesehelper_migrated)

-- Out-of-range values come back valid.
s = Settings.new(store{ chinesehelper_uncertain = "nonsense", chinesehelper_size_pct = 500,
                        chinesehelper_special_style = "x", chinesehelper_popup_text_pct = 1 })
eq(s:uncertainMode(), "both"); eq(s:sizePercent(), 80); eq(s:specialStyle(), "bold"); eq(s:popupTextPercent(), 60)
-- Popup text size: exactly the menu's choices; an old 70 falls back to the default.
for _, pct in ipairs({ 40, 60, 80, 100, 120 }) do
    eq(Settings.new(store{ chinesehelper_popup_text_pct = pct }):popupTextPercent(), pct)
end
eq(Settings.new(store{ chinesehelper_popup_text_pct = 70 }):popupTextPercent(), 60)
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
for _, src in ipairs({ "wp", "cbdb", "moegirl" }) do eq(Settings.new(store()):fallbackEnabled(src), true) end
-- The fallback priority: the default, a setting naming some (the rest
-- follow in the default order), unknown names, repeats and junk ignored.
eq(table.concat(Settings.new(store()):fallbackOrder(), ","), "wikt,cbdb,moe,wp,moegirl")
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = "moegirl,wikt" }):fallbackOrder(), ","),
   "moegirl,wikt,cbdb,moe,wp")
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = " wp , x,wp" }):fallbackOrder(), ","),
   "wp,wikt,cbdb,moe,moegirl")
eq(table.concat(Settings.new(store{ chinesehelper_fallback_order = 5 }):fallbackOrder(), ","),
   "wikt,cbdb,moe,wp,moegirl")
-- No settings store at all (tests, odd starts): defaults, no errors.
s = Settings.new(nil); eq(s:threshold(), 3500); s:set("threshold", 1); eq(#s:migrate(), 0)
