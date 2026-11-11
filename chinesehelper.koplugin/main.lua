--[[--
Chinese helper: pinyin above rare Chinese characters, and a tap on any
Chinese character for its definition and every dictionary word around it that
contains it. The book file is never modified.

Merges koreader-interlinear-pinyin (forked from WordGloss,
https://github.com/GangYe293/wordgloss.koplugin, GPL-3.0, by GangYe293) and
koreader-chinese-popup.

  ch_settings.lua      settings, defaults, migration from the old plugins
  ch_annotator.lua     pinyin layer: line spacing, page refresh (from WordGloss)
  ch_page.lua          walks the page through the engine
  ch_resolve.lua       the reading resolver (annotations and popup)
  ch_readings.lua      the resolver's tables
  ch_db.lua            data/chinesehelper.sqlite: CC-CEDICT and the tables
  ch_overlay.lua       draws the pinyin (from WordGloss)
  ch_layout.lua        keeps neighbouring pinyin apart (from WordGloss)
  ch_hit.lua           which drawn pinyin a tap is on
  ch_tap.lua           the one tap handler
  ch_context.lua       tap -> character and the Han characters around it
  ch_text.lua          UTF-8, Han detection, candidate words
  ch_pinyin.lua        pinyin comparisons
  ch_popup_model.lua   what the popup shows
  ch_popup.lua         the popup widget
]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

local Annotator = require("ch_annotator")
local Settings = require("ch_settings")
local Tap = require("ch_tap")

local ChineseHelper = WidgetContainer:extend{
    name = "chinesehelper",
    is_doc_only = true,
}

ChineseHelper.VERSION = "1.0.0"
ChineseHelper.OLD_PLUGINS = { "interlinearpinyin", "chinesepopup" }

-- Opened once per KOReader session and shared by every book: the database
-- handle, the resolver's tables and the special words.
local session = {}

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function ChineseHelper:init()
    self.settings = Settings.new(G_reader_settings)
    local copied = self.settings:migrate()
    if #copied > 0 then logger.info("chinesehelper: migrated settings:", table.concat(copied, ", ")) end
    self.annotator = Annotator.new(self)
    self.tap = Tap.new(self)
    -- Register the menu first: if anything later fails, the entry still shows.
    if self.ui and self.ui.menu then
        pcall(function() self.ui.menu:registerToMainMenu(self) end)
    end
end

-- Reflowable (CreDocument) documents only: they have xpointers and style
-- sheets. PDF, DjVu and CBZ get nothing: no pinyin, no tap zone.
function ChineseHelper:isCompatibleDocument()
    local ui = self.ui
    local document = ui and ui.document
    return document ~= nil and ui.rolling ~= nil and document.getTextFromXPointers ~= nil
        and document.setStyleSheet ~= nil
end

function ChineseHelper:onReaderReady()
    UIManager:nextTick(function() self:warnOldPlugins() end)
    if not self:isCompatibleDocument() then return end
    self.annotator:onReaderReady()
    self.tap:update()
end

function ChineseHelper:onReadSettings()
    if self:isCompatibleDocument() then self.annotator:onReadSettings() end
end

-- Compute right away (not on the next tick) so the pinyin is drawn in the same
-- screen refresh as the page turn, avoiding a second e-ink refresh.
function ChineseHelper:onPageUpdate() self.annotator:refreshPage() end
function ChineseHelper:onPosUpdate() self.annotator:refreshPage() end

function ChineseHelper:onDocumentRerendered() self.annotator:onDocumentRerendered() end
ChineseHelper.onDocumentPartiallyRerendered = ChineseHelper.onDocumentRerendered

function ChineseHelper:onCloseDocument()
    self.annotator:close()
end

------------------------------------------------------------------------
-- Data (shared for the session)
------------------------------------------------------------------------

function ChineseHelper:dbPath()
    return self.path .. "/data/chinesehelper.sqlite"
end

function ChineseHelper:db()
    if session.db then return session.db end
    if session.db_error then return nil, session.db_error end
    local DB = require("ch_db")
    local db, err = DB.open(self:dbPath())
    if not db then
        logger.warn("chinesehelper:", err)
        session.db_error = err
        return nil, err
    end
    session.db = db
    return db
end

-- The resolver's tables (chars, rules and uncertain read into memory; words
-- looked up in the database as needed). Loaded when the first page is drawn
-- or the first character tapped.
function ChineseHelper:readings()
    if session.readings then return session.readings end
    local db = self:db()
    if not db then return nil end
    local t0 = time.monotonic()
    local ok, data = pcall(db.readings, db)
    if not ok then
        logger.warn("chinesehelper: cannot load readings:", tostring(data))
        session.db_error = tostring(data)
        return nil
    end
    session.readings = data
    session.readings_ms = time.to_ms(time.monotonic() - t0)
    logger.info(string.format("chinesehelper: reading tables loaded in %.1f ms", session.readings_ms))
    return data
end

-- The special words, or nil while that setting is off (nothing is loaded then).
function ChineseHelper:special()
    if not self.settings:specialEnabled() then return nil end
    if session.special then return session.special end
    local db = self:db()
    if not db then return nil end
    -- The collector is paused while loading so the memory figure in Status
    -- is what the list takes, not that minus whatever was collected meanwhile.
    collectgarbage("stop")
    local t0, kb0 = time.monotonic(), collectgarbage("count")
    local ok, special = pcall(db.special, db)
    local kb = collectgarbage("count") - kb0
    collectgarbage("restart")
    if not ok then
        logger.warn("chinesehelper: no special readings:", tostring(special))
        return nil
    end
    special.load_ms = time.to_ms(time.monotonic() - t0)
    special.kb = kb
    session.special = special
    return special
end

------------------------------------------------------------------------
-- The old plugins
------------------------------------------------------------------------

-- Old plugins still installed next to this one, or loaded: { "interlinearpinyin", ... }.
function ChineseHelper:oldPluginsPresent()
    local found = {}
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local parent = self.path and self.path:match("^(.*)/[^/]+/?$")
    for _, name in ipairs(ChineseHelper.OLD_PLUGINS) do
        local installed = ok and parent and lfs.attributes(parent .. "/" .. name .. ".koplugin", "mode") == "directory"
        local loaded = self.ui and self.ui[name] ~= nil
        if installed or loaded then found[#found + 1] = name end
    end
    return found
end

-- Shown once per KOReader session: both live at once recreates the tap conflict.
function ChineseHelper:warnOldPlugins()
    if session.warned then return end
    local found = self:oldPluginsPresent()
    if #found == 0 then return end
    session.warned = true
    local folders = {}
    for _, name in ipairs(found) do folders[#folders + 1] = name .. ".koplugin" end
    logger.warn("chinesehelper: old plugins present:", table.concat(folders, ", "))
    UIManager:show(InfoMessage:new{
        text = T(_("Chinese helper replaces these plugins, which are still installed:\n\n%1\n\nPlease delete them from KOReader's plugins folder and restart KOReader. While they are installed, taps on Chinese characters can open the wrong popup."),
            table.concat(folders, "\n")),
    })
end

------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------

function ChineseHelper:addToMainMenu(menu_items)
    local plugin = self
    local settings = self.settings
    -- current: the validated value (the label shows the same), so a saved
    -- value that is no longer a choice still checks the one in use.
    local function radio(values, key, label, after, current)
        local items = {}
        for _i, value in ipairs(values) do
            items[#items + 1] = {
                text = T(label, value),
                checked_func = function() return (current and current() or settings:get(key)) == value end,
                radio = true,
                keep_menu_open = true,
                callback = function(touchmenu)
                    settings:set(key, value)
                    after(touchmenu)
                end,
            }
        end
        return items
    end
    local refresh = function() plugin.annotator:refreshPage() end
    local apply = function(touchmenu) plugin.annotator:apply(touchmenu) end

    local uncertain_items = {}
    local uncertain_labels = {
        { Settings.UNCERTAIN_BOTH, _("Show both readings (chéng/shèng)") },
        { Settings.UNCERTAIN_BEST, _("Show the most likely reading") },
        { Settings.UNCERTAIN_SKIP, _("Don't annotate") },
    }
    local uncertain_short = {
        [Settings.UNCERTAIN_BOTH] = _("show both"),
        [Settings.UNCERTAIN_BEST] = _("best guess"),
        [Settings.UNCERTAIN_SKIP] = _("don't annotate"),
    }
    for _i, entry in ipairs(uncertain_labels) do
        local mode, label = entry[1], entry[2]
        uncertain_items[#uncertain_items + 1] = {
            text = label,
            checked_func = function() return settings:uncertainMode() == mode end,
            radio = true,
            keep_menu_open = true,
            callback = function()
                settings:set("uncertain", mode)
                refresh()
            end,
        }
    end

    local edge_items = {}
    for _i, mm in ipairs(require("ch_edge").CHOICES) do
        edge_items[#edge_items + 1] = {
            text = plugin:edgeLabel(mm),
            checked_func = function() return settings:edgeMm() == mm end,
            radio = true,
            keep_menu_open = true,
            callback = function() settings:set("edge_mm", mm) end,
        }
    end

    menu_items.chinesehelper = {
        text = _("Chinese helper"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show pinyin above rare characters"),
                checked_func = function() return settings:pinyinEnabled() end,
                callback = function(touchmenu)
                    settings:set("pinyin_enabled", not settings:pinyinEnabled())
                    apply(touchmenu)
                end,
            },
            {
                text = _("Tap characters for popup"),
                help_text = _("A single tap on a Chinese character, or on the pinyin above one, shows its CC-CEDICT entry and every dictionary word around it that contains it, with a button per word for KOReader's dictionary lookup. Other taps turn the page as usual; long-press is unchanged."),
                checked_func = function() return settings:popupEnabled() end,
                callback = function()
                    settings:set("popup_enabled", not settings:popupEnabled())
                    plugin.tap:update()
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Which characters: outside the %1 most common"), settings:threshold())
                end,
                sub_item_table = radio(Settings.THRESHOLDS, "threshold", _("Outside the %1 most common"), refresh),
            },
            {
                text_func = function()
                    return T(_("Pinyin size: %1% of text"), settings:sizePercent())
                end,
                sub_item_table = radio(Settings.SIZES, "size_pct", _("%1% of text size"), apply),
            },
            {
                text_func = function()
                    return T(_("When the reading is uncertain: %1"), uncertain_short[settings:uncertainMode()])
                end,
                help_text = _("Some characters have more than one common reading and nothing nearby tells which one is meant. The plugin can show the two most likely readings (most likely first), only the most likely one, or nothing. The popup marks the same reading(s)."),
                sub_item_table = uncertain_items,
            },
            {
                text = _("Mark unusual readings of common characters (names, historical terms)"),
                help_text = _("Common characters are not annotated, but some take a rare reading in particular names and terms: 单于 chán yú, 冒顿 mò dú, 可汗 kè hán, 会稽 kuài jī. With this on, those characters get pinyin (in bold) when they appear in such a word."),
                checked_func = function() return settings:specialEnabled() end,
                callback = function()
                    settings:set("special", not settings:specialEnabled())
                    refresh()
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Edge pass-through width: %1"), plugin:edgeLabel(settings:edgeMm()))
                end,
                help_text = _("A tap this close to any edge of the screen always goes to KOReader (page turn, menus, corner actions), even on a Chinese character or its pinyin. 0 mm turns this off: then only taps that miss a character go to KOReader."),
                sub_item_table = edge_items,
            },
            {
                text_func = function()
                    return T(_("Popup text size: %1% of text"), settings:popupTextPercent())
                end,
                sub_item_table = radio(Settings.POPUP_SIZES, "popup_text_pct", _("%1% of text size"), function() end,
                    function() return settings:popupTextPercent() end),
                separator = true,
            },
            {
                text = _("Status"),
                keep_menu_open = true,
                callback = function() plugin:showStatus() end,
            },
        },
    }
end

-- "0 mm (off)", "2.5 mm", "5 mm", "10 mm".
function ChineseHelper:edgeLabel(mm)
    local text = (mm == math.floor(mm)) and string.format("%d mm", mm) or string.format("%.1f mm", mm)
    return mm == 0 and T(_("%1 (off)"), text) or text
end

function ChineseHelper:showStatus()
    local lines = { T(_("Chinese helper %1"), ChineseHelper.VERSION) }
    local db, err = self:db()
    if not db then
        lines[#lines + 1] = T(_("Data not loaded: %1"), tostring(err))
    else
        local ok, meta = pcall(db.meta, db)
        if ok then
            lines[#lines + 1] = T(_("CC-CEDICT %1 (%2 entries)"), (meta.cedict_date or "?"):sub(1, 10),
                meta.cedict_entries or "?")
        end
        if session.readings_ms then
            lines[#lines + 1] = T(_("Reading tables loaded in %1 ms"), string.format("%.0f", session.readings_ms))
        end
    end
    local stats = self.annotator.last_stats
    if stats and self.settings:pinyinEnabled() then
        lines[#lines + 1] = T(_("This page: %1 characters read, %2 annotated (%3 unusual readings) in %4 ms"),
            stats.items, stats.annotated, stats.special or 0, string.format("%.0f", stats.ms or 0))
    end
    local special = session.special
    if self.settings:specialEnabled() and special then
        lines[#lines + 1] = T(_("Unusual readings: %1 words, %2 overlap guards; loaded in %3 ms, %4 KB"),
            special.count, special.guard_count or 0, string.format("%.0f", special.load_ms or 0),
            string.format("%.0f", special.kb or 0))
    end
    local Device = require("device")
    local dpi = Device.screen and Device.screen.getDPI and Device.screen:getDPI()
    lines[#lines + 1] = T(_("Edge pass-through: %1 = %2 px (screen %3 dpi)"), self:edgeLabel(self.settings:edgeMm()),
        self.tap:edgeBand(), tostring(dpi))
    local old = self:oldPluginsPresent()
    if #old > 0 then
        lines[#lines + 1] = T(_("Old plugins still installed: %1"), table.concat(old, ", "))
    end
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

return ChineseHelper
