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
stub("device", { screen = { scaleBySize = function(_, v) return v end, getWidth = function() return 1000 end },
                 isTouchDevice = function() return true end })
stub("lua-ljsqlite3/init", H.SQ3)
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
eq(count, 8 + 5 + 5 + 3 + 6, "menu size")

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
-- Popup text size.
entry.sub_item_table[7].sub_item_table[4].callback()
eq(plugin.settings:popupTextPercent(), 100)
assert(entry.sub_item_table[7].text_func():find("100%%"))

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

G_reader_settings = nil
