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
  ch_sentence.lua      the sentence around the tapped character
  ch_translate.lua     the popup's Translate button (KOAssistant or KOReader)
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

ChineseHelper.VERSION = "1.5.0"
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
-- or the first character tapped. Wiktionary's words, while that dictionary
-- is switched on, are (re)attached on every call, so switching it off takes
-- effect at once. They only pick one of an uncertain character's two likely
-- readings (ch_resolve.lua); MOE's words are not used for readings: its
-- Taiwan readings broke more than they fixed (tools/eval_readings.py).
ChineseHelper.READING_SOURCES = { wikt = true }

function ChineseHelper:readings()
    local data = self:loadReadings()
    if data then
        local names = {}
        for _i, src in ipairs(self:fallbackSources()) do
            if ChineseHelper.READING_SOURCES[src.source] then names[#names + 1] = src.source end
        end
        data:setFallback(#names > 0 and function(list)
            return self:fallbackLookup(list, ChineseHelper.READING_SOURCES)
        end or nil, table.concat(names, ","))
    end
    return data
end

function ChineseHelper:loadReadings()
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

------------------------------------------------------------------------
-- Fallback dictionaries
------------------------------------------------------------------------

ChineseHelper.SOURCE_NAMES = { wikt = "Wiktionary", wp = "Wikipedia titles", cbdb = "CBDB office titles",
                                moe = "MOE 重編國語辭典", moegirl = "Moegirlpedia slang" }
-- In the plugin database (the release): their rows are in its fallback table.
ChineseHelper.BUNDLED_SOURCES = { wikt = true, wp = true }
-- Files the user builds and installs (licences that forbid distributing
-- them): tools/build_moe.py, build_cbdb.py, build_moegirl.py.
ChineseHelper.LOCAL_FILES = { moe = "chinesehelper-moe.sqlite", cbdb = "chinesehelper-cbdb.sqlite",
                              moegirl = "chinesehelper-moegirl.sqlite" }

-- Where the user's own files go: KOReader's data folder, which plugin
-- updates leave alone (Android: /sdcard/koreader/data/chinesehelper/).
function ChineseHelper:localPath(source)
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage or not ChineseHelper.LOCAL_FILES[source] then return nil end
    return DataStorage:getDataDir() .. "/data/chinesehelper/" .. ChineseHelper.LOCAL_FILES[source]
end

-- A user file's database, opened on first use, or nil when not installed.
function ChineseHelper:localDb(source)
    session.local_dbs = session.local_dbs or {}
    local cached = session.local_dbs[source]
    if cached ~= nil then return cached or nil end
    local path = self:localPath(source)
    local db = path and require("ch_db").open(path)
    session.local_dbs[source] = db or false
    return db or nil
end

-- A database's meta table (cached for the session), or {}.
local function metaOf(db)
    if not db then return {} end
    session.metas = session.metas or {}
    local meta = session.metas[db]
    if not meta then
        local ok, m = pcall(db.meta, db)
        meta = ok and m or {}
        session.metas[db] = meta
    end
    return meta
end

-- Is `source` in a database's meta fallback_sources ("wikt,wp")?
local function listed(db, source)
    for name in (metaOf(db).fallback_sources or ""):gmatch("[^,%s]+") do
        if name == source then return true end
    end
    return false
end

-- The database holding a fallback dictionary, or nil when it is not there
-- (not in this plugin database, or the user's file not installed).
function ChineseHelper:sourceDb(source)
    if ChineseHelper.BUNDLED_SOURCES[source] then
        local db = self:db()
        return db and listed(db, source) and db or nil
    end
    return self:localDb(source)
end

-- The fallback dictionaries to consult, in priority order
-- (Settings:fallbackOrder()): { {source="wikt", db=}, {source="cbdb", db=},
-- ... }, each only when switched on and present.
function ChineseHelper:fallbackSources()
    local out = {}
    local settings = self.settings
    for _i, source in ipairs(settings:fallbackOrder()) do
        if settings:fallbackEnabled(source) then
            local db = self:sourceDb(source)
            if db then out[#out + 1] = { source = source, db = db } end
        end
    end
    return out
end

-- Rows { {simp=, trad=, pinyin=, syllables=, defs=, source=}, ... } from the
-- fallback dictionaries for `words` (none of them CC-CEDICT's): each source in
-- priority order, and a word one source has is not taken from the next. One
-- query per database: Wiktionary and the Wikipedia titles share the plugin's,
-- which is asked once for every word and its rows then shared out by source.
-- only: { [source] = true } to use only those.
function ChineseHelper:fallbackLookup(words, only)
    local Model = require("ch_popup_model")
    local remaining, out, fetched = words, {}, {}
    for _i, src in ipairs(self:fallbackSources()) do
        if #remaining == 0 then break end
        if not only or only[src.source] then
            local rows = fetched[src.db]
            if not rows then
                rows = src.db:fallback(words)
                fetched[src.db] = rows
            end
            local got = {}
            for _j, row in ipairs(rows) do
                if (row.source or src.source) == src.source then
                    row.source = src.source
                    got[#got + 1] = row
                end
            end
            local kept
            kept, remaining = Model.takeFallback(remaining, got)
            for _j, row in ipairs(kept) do out[#out + 1] = row end
        end
    end
    return out
end

-- One Status line per fallback dictionary, in priority order: version,
-- size, on or off.
function ChineseHelper:fallbackStatus()
    local lines = {}
    local state = function(source) return self.settings:fallbackEnabled(source) and _("on") or _("off") end
    local describe = {
        wikt = function(m) return T(_("Wiktionary: %1 (dump %2, %3 entries)"), state("wikt"),
            m.wikt_dump or "?", m.wikt_rows or "?") end,
        wp = function(m) return T(_("Wikipedia titles: %1 (dump %2, %3 entries)"), state("wp"),
            m.wp_dump or "?", m.wp_rows or "?") end,
        cbdb = function(m) return T(_("CBDB office titles: %1 (CBDB %2, %3 entries)"), state("cbdb"),
            (m.cbdb_date or "?"):sub(1, 10), m.cbdb_rows or "?") end,
        moe = function(m) return T(_("MOE 重編國語辭典: %1 (moedict-data %2, %3 entries)"), state("moe"),
            (m.moe_commit_date or "?"):sub(1, 10), m.moe_rows or "?") end,
        moegirl = function(m) return T(_("Moegirlpedia slang: %1 (snapshot %2, %3 entries)"), state("moegirl"),
            (m.moegirl_snapshot or "?"):sub(1, 10), m.moegirl_rows or "?") end,
    }
    for _i, source in ipairs(self.settings:fallbackOrder()) do
        local db = self:sourceDb(source)
        if db then
            lines[#lines + 1] = describe[source](metaOf(db))
        elseif ChineseHelper.BUNDLED_SOURCES[source] then
            lines[#lines + 1] = T(_("%1: not in this database"), ChineseHelper.SOURCE_NAMES[source])
        else
            lines[#lines + 1] = T(_("%1: not installed"), ChineseHelper.SOURCE_NAMES[source])
        end
    end
    return lines
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
            },
            {
                text = _("Fallback dictionaries"),
                help_text = _("For words CC-CEDICT does not have, the popup can show entries from other dictionaries, in the order listed here. CC-CEDICT always comes first: a word it has never gets an entry from another dictionary, and each word gets the entry of the first dictionary that has it. Wiktionary and the Wikipedia titles are part of the plugin; CBDB, MOE and Moegirlpedia are files you build and install yourself (see the README)."),
                sub_item_table = plugin:fallbackItems(apply, {
                    {
                        text_func = function()
                            local names = { all = _("all entries"), fallback = _("other dictionaries only"),
                                            none = _("none") }
                            return T(_("Source labels: %1"), names[settings:labelMode()])
                        end,
                        help_text = _("A small grey line above an entry naming its dictionary: CEDICT, Wikt (Wiktionary), CBDB, MOE, WP (Wikipedia titles) or Moegirl (Moegirlpedia)."),
                        sub_item_table = {
                            { text = _("All entries"), radio = true, keep_menu_open = true,
                              checked_func = function() return settings:labelMode() == "all" end,
                              callback = function() settings:set("labels", "all") end },
                            { text = _("Other dictionaries only (not CC-CEDICT)"), radio = true, keep_menu_open = true,
                              checked_func = function() return settings:labelMode() == "fallback" end,
                              callback = function() settings:set("labels", "fallback") end },
                            { text = _("None"), radio = true, keep_menu_open = true,
                              checked_func = function() return settings:labelMode() == "none" end,
                              callback = function() settings:set("labels", "none") end },
                        },
                        separator = true,
                    },
                }),
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

-- The Fallback dictionaries menu: `items` (the source labels setting), then
-- one on/off item per dictionary in priority order. The user's own files
-- show whether they are installed and cannot be switched on without one.
function ChineseHelper:fallbackItems(apply, items)
    local plugin, settings = self, self.settings
    for _i, source in ipairs(settings:fallbackOrder()) do
        local name = ChineseHelper.SOURCE_NAMES[source]
        local bundled = ChineseHelper.BUNDLED_SOURCES[source]
        items[#items + 1] = {
            text_func = function()
                if plugin:sourceDb(source) then
                    return bundled and name or T(_("%1 (your own file)"), name)
                end
                return bundled and T(_("%1 (not in this database)"), name) or T(_("%1 (not installed)"), name)
            end,
            enabled_func = function() return plugin:sourceDb(source) ~= nil end,
            checked_func = function() return settings:fallbackEnabled(source) and plugin:sourceDb(source) ~= nil end,
            callback = function(touchmenu)
                settings:set("fallback_" .. source, not settings:fallbackEnabled(source))
                apply(touchmenu)   -- Wiktionary's words can decide the pinyin drawn
            end,
        }
    end
    return items
end

-- "0 mm (off)", "2.5 mm", "5 mm", "7.5 mm", "10 mm".
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
        for _i, line in ipairs(self:fallbackStatus()) do lines[#lines + 1] = line end
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
