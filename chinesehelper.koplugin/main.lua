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
  ch_snippet.lua       the popup's context line: page text, what fits on one line
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

ChineseHelper.VERSION = "2.7.0"
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
-- A page turn also takes the tapped character's underline away (the page
-- is redrawn in full, so no refresh of its own).
function ChineseHelper:onPageUpdate()
    self.annotator:setMark(nil, true)
    self.annotator:refreshPage()
end
function ChineseHelper:onPosUpdate()
    self.annotator:setMark(nil, true)
    self.annotator:refreshPage()
end

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
                                moe = "MOE 重編國語辭典", idioms = "MOE 成語典", xinhua = "Xinhua idioms",
                                moegirl = "Moegirlpedia slang" }
ChineseHelper.MOE_MODE_NAMES = { off = _("off"), fallback = _("fallback"), always = _("always") }
-- In the plugin database (the release): their rows are in its fallback table.
ChineseHelper.BUNDLED_SOURCES = { wikt = true, wp = true }
-- Files the user builds and installs (licences that forbid distributing
-- them): tools/build_moe.py, build_cbdb.py, build_idioms.py, build_xinhua.py,
-- build_moegirl.py.
ChineseHelper.LOCAL_FILES = { moe = "chinesehelper-moe.sqlite", cbdb = "chinesehelper-cbdb.sqlite",
                              idioms = "chinesehelper-idioms.sqlite", xinhua = "chinesehelper-xinhua.sqlite",
                              moegirl = "chinesehelper-moegirl.sqlite" }
-- Fallback dictionaries whose files also hold idioms' short lines and Origin & Usage
-- views (an idioms table) for words CC-CEDICT has.
ChineseHelper.IDIOM_SOURCES = { idioms = true, xinhua = true }

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

-- The number of characters in a word.
local function length(word)
    return select(2, word:gsub("[^\128-\191]", ""))
end

-- Does the installed MOE file have covered rows (built with 2.5.0's
-- tools/build_moe.py)? Without them, Always behaves as Fallback.
function ChineseHelper:moeHasCovered()
    local db = self:localDb("moe")
    return db ~= nil and metaOf(db).moe_covered == "1" and db:hasCovered()
end

-- Of `texts` (a tap's candidate words), those MOE is to show Always: the
-- single character when its Characters mode is Always, the longer words when
-- its Words mode is. None without a rebuilt MOE file.
function ChineseHelper:alwaysTexts(texts)
    local chars, words = self.settings:moeMode("chars"), self.settings:moeMode("words")
    if (chars ~= "always" and words ~= "always") or not self:moeHasCovered() then return {} end
    local out = {}
    for _i, t in ipairs(texts) do
        if (length(t) == 1 and chars == "always") or (length(t) > 1 and words == "always") then
            out[#out + 1] = t
        end
    end
    return out
end

-- Rows { {simp=, trad=, pinyin=, syllables=, defs=, source=}, ... } from the
-- fallback dictionaries for `words` (none of them CC-CEDICT's): each source in
-- priority order, and a word one source has is not taken from the next. One
-- query per database: Wiktionary and the Wikipedia titles share the plugin's,
-- which is asked once for every word and its rows then shared out by source.
-- only: { [source] = true } to use only those (the reading path: Wiktionary).
-- MOE gives a fallback entry only for the lengths its modes allow (Off for
-- characters: none for a single character).
-- always: texts MOE is to show Always (ChineseHelper:alwaysTexts), or nil.
-- Then MOE's file is asked once for those and `words` together, covered
-- rows included, and the second value is every MOE row for those texts.
function ChineseHelper:fallbackLookup(words, only, always)
    local Model = require("ch_popup_model")
    local remaining, out, fetched, always_rows = words, {}, {}, {}
    local settings = self.settings
    for _i, src in ipairs(self:fallbackSources()) do
        local want_always = always ~= nil and #always > 0 and src.source == "moe"
        if (#remaining > 0 or want_always) and (not only or only[src.source]) then
            local rows = fetched[src.db]
            if not rows and want_always then
                local list, seen = {}, {}
                for _j, list_ in ipairs({ words, always }) do
                    for _k, w in ipairs(list_) do
                        if not seen[w] then list[#list + 1], seen[w] = w, true end
                    end
                end
                local wanted = {}
                for _j, w in ipairs(always) do wanted[w] = true end
                rows = {}
                for _j, row in ipairs(src.db:fallbackAll(list)) do
                    if wanted[row.simp] or wanted[row.trad] then
                        row.source = src.source
                        always_rows[#always_rows + 1] = row
                    end
                    if not row.covered then rows[#rows + 1] = row end
                end
                fetched[src.db] = rows
            elseif not rows then
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
            -- MOE: only the lengths its modes allow; the rest stay for the
            -- next source.
            local ask, skipped = remaining, nil
            if src.source == "moe" then
                local chars_ok = settings:moeMode("chars") ~= "off"
                local words_ok = settings:moeMode("words") ~= "off"
                if not (chars_ok and words_ok) then
                    ask, skipped = {}, {}
                    for _j, w in ipairs(remaining) do
                        local single = length(w) == 1
                        if (single and chars_ok) or (not single and words_ok) then
                            ask[#ask + 1] = w
                        else
                            skipped[#skipped + 1] = w
                        end
                    end
                end
            end
            local kept
            kept, remaining = Model.takeFallback(ask, got)
            for _j, row in ipairs(kept) do out[#out + 1] = row end
            if skipped then
                local keep = {}
                for _j, w in ipairs(remaining) do keep[w] = true end
                for _j, w in ipairs(skipped) do keep[w] = true end
                remaining = {}
                for _j, w in ipairs(words) do if keep[w] then remaining[#remaining + 1] = w end end
            end
        end
    end
    return out, always_rows
end

-- { [form] = {short=, short_source=, view=, source=} } for the idioms among
-- `words`, from the 成語典 and Xinhua files that are switched on and
-- installed, in the fallback order (Model.pickIdioms).
function ChineseHelper:idiomLookup(words)
    local Model = require("ch_popup_model")
    local rows = {}
    if #words == 0 then return {} end
    for _i, src in ipairs(self:fallbackSources()) do
        if ChineseHelper.IDIOM_SOURCES[src.source] then
            for _j, row in ipairs(src.db:idioms(words)) do
                row.source = src.source
                rows[#rows + 1] = row
            end
        end
    end
    return Model.pickIdioms(rows, self.settings:fallbackOrder())
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
        -- Files built before 1.8.0 have no moe_text: their text is traditional.
        moe = function(m)
            local line = T(_("MOE 重編國語辭典: %1 (moedict-data %2, %3 entries, %4)"), state("moe"),
                (m.moe_commit_date or "?"):sub(1, 10), m.moe_rows or "?",
                m.moe_text == "simplified" and _("simplified text") or _("traditional text"))
            if not self.settings:fallbackEnabled("moe") then return line end
            local chars, words = self.settings:moeMode("chars"), self.settings:moeMode("words")
            line = line .. "\n  " .. T(_("characters: %1, words: %2"), ChineseHelper.MOE_MODE_NAMES[chars],
                ChineseHelper.MOE_MODE_NAMES[words])
            if self:moeHasCovered() then
                line = line .. "; " .. T(_("rebuilt for Always: %1 character rows, %2 word rows CC-CEDICT also has"),
                    m.moe_covered_char_rows or "?", m.moe_covered_word_rows or "?")
            elseif chars == "always" or words == "always" then
                line = line .. "\n  " .. _("Always works as Fallback with this file: rebuild it for Always (python3 tools/build_moe.py, see the README).")
            end
            return line
        end,
        idioms = function(m) return T(_("MOE 成語典: %1 (%2, %3 idioms, %4 not in CC-CEDICT, %5)"), state("idioms"),
            m.idioms_version or "?", m.idioms_rows or "?", m.idioms_fallback_rows or "?",
            m.idioms_text == "traditional" and _("traditional text") or _("simplified text")) end,
        xinhua = function(m) return T(_("Xinhua idioms: %1 (chinese-xinhua %2, %3 idioms, %4 not in CC-CEDICT)"),
            state("xinhua"), (m.xinhua_commit_date or "?"):sub(1, 10), m.xinhua_rows or "?",
            m.xinhua_fallback_rows or "?") end,
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
-- Reading marks (#26): known / remind me, for every book
------------------------------------------------------------------------

-- In KOReader's settings folder, never in the plugin's own: an update or
-- tools/deploy.sh replaces the plugin folder whole.
ChineseHelper.MARKS_FILE = "chinesehelper_marks.lua"

function ChineseHelper.marksPath()
    return require("datastorage"):getSettingsDir() .. "/" .. ChineseHelper.MARKS_FILE
end

--[[--
The marks file through KOReader's LuaSettings: read with LuaSettings:open
(which falls back to <file>.old when the file does not parse), written
atomically. LuaSettings:flush truncates and rewrites the file in place
(keeping a .old only when the file is over 60 s old), so a write cut short
could leave a broken file; here the new content goes to <file>.tmp, is
synced, and is renamed over the file.
]]
function ChineseHelper.marksStore(path)
    local LuaSettings = require("luasettings")
    local lfs = require("libs/libkoreader-lfs")
    local util = require("util")
    local dump = require("dump")
    return {
        path = path,
        read = function()
            local existed = lfs.attributes(path, "mode") == "file"
            return LuaSettings:open(path).data, existed
        end,
        write = function(data)
            LuaSettings:backup(path)   -- <file>.old, as LuaSettings:flush does
            local tmp = path .. ".tmp"
            local ok, err = util.writeToFile("-- " .. path .. "\nreturn " .. dump(data, nil, true) .. "\n", tmp, true)
            if not ok then return nil, err end
            local renamed, rerr = os.rename(tmp, path)
            if not renamed then return nil, rerr end
            pcall(function() require("ffi/util").fsyncDirectory(path) end)
            return true
        end,
        setAside = function()
            local to = path .. ".unreadable-" .. os.date("%Y%m%d-%H%M%S")
            os.rename(path, to)
            logger.warn("chinesehelper: the marks file could not be read; set aside as", to)
        end,
    }
end

-- The reader's reading marks, shared by every book for the session.
function ChineseHelper:marks()
    if session.marks then return session.marks end
    local Marks = require("ch_marks")
    local plugin = self
    session.marks = Marks.new{
        store = ChineseHelper.marksStore(ChineseHelper.marksPath()),
        simplify = function(ch, reading)
            local db = plugin:db()
            return db and db:simplifiedOf(ch, reading) or ch
        end,
        variants = function(s)
            local db = plugin:db()
            return db and db:formsOf(s) or { s }
        end,
    }
    return session.marks
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
                help_text = _("A single tap in the text shows the nearest Chinese character's CC-CEDICT entry and every dictionary word around it that contains it, with a button per word for KOReader's dictionary lookup. A tap between lines, between characters or on punctuation takes the nearest character; a tap on the pinyin above one takes that character. Taps outside the text (margins, blank space, the rest of a short line, lines with no Chinese) turn the page as usual; long-press is unchanged."),
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
            },
            plugin:marksItem(),
            {
                text_func = function()
                    return T(_("Edge pass-through width: %1"), plugin:edgeLabel(settings:edgeMm()))
                end,
                help_text = _("A tap this close to any edge of the screen always goes to KOReader (page turn, menus, corner actions), even on a Chinese character or its pinyin. 0 mm turns this off: then only taps outside the text go to KOReader."),
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
                text_func = function()
                    return T(_("Chinese text size: %1% of popup text"), settings:chineseTextPercent())
                end,
                help_text = _("Text from the Chinese dictionaries (MOE, the 成語典, Xinhua, Moegirlpedia: definitions, 出处, stories, examples) is drawn this much larger than the rest of the popup. Tap a character in it to look that character up. English glosses, headlines, components, source labels and buttons keep the popup text size."),
                sub_item_table = radio(Settings.CHINESE_SIZES, "chinese_text_pct", _("%1% of popup text size"), function() end,
                    function() return settings:chineseTextPercent() end),
            },
            {
                text = _("Show character components"),
                help_text = _("Below the tapped character's entry, one line per part: its form, reading, a short gloss, and whether it gives the meaning or the sound (same sound, same ending, or loose). A simplified character whose simplification hid a part shows its traditional form's parts. Sources: English Wiktionary, then Make Me a Hanzi, then yi-bai/ids (structure only)."),
                checked_func = function() return settings:componentsEnabled() end,
                callback = function() settings:set("components", not settings:componentsEnabled()) end,
            },
            {
                text = _("Show character frequency rank"),
                help_text = _("A small grey 字频 line on the tapped character's own entry: its rank among characters in modern written Chinese, from wordfreq (1 is the most common; the default pinyin threshold is 3,500). Past 7,000 it shows 7,000+, since the data is too thin there for an exact rank; unranked means the character is not in the list."),
                checked_func = function() return settings:charRankEnabled() end,
                callback = function() settings:set("char_rank", not settings:charRankEnabled()) end,
            },
            {
                text = _("Show the text around the character in the popup"),
                help_text = _("A line at the top of the popup with the text around the tapped character, as much of its sentence as fits on one line, the character in bold and underlined. It shows the text as it is on the page and never goes past the end of the sentence, the paragraph or the page. Popups opened from the word buttons mark the whole word."),
                checked_func = function() return settings:contextEnabled() end,
                callback = function() settings:set("popup_context", not settings:contextEnabled()) end,
            },
            {
                text = _("Underline the tapped character on the page"),
                help_text = _("While the popup is open, a line under the tapped character on the page, so you can see which character the tap hit and find your place again."),
                checked_func = function() return settings:underlineEnabled() end,
                callback = function() settings:set("page_underline", not settings:underlineEnabled()) end,
            },
            {
                text = _("Try to match the book's font"),
                help_text = _("Chinese text in the popup (the character, the line of text around it, entries, the Chinese dictionaries' text, components and the Origin & Usage view) is drawn in the font chosen in KOReader's font menu; English and pinyin keep the UI font. It follows the font menu, not fonts a book embeds or sets in its CSS. When the book's font cannot be used (a PDF, a font file that will not load), the popup uses the UI font."),
                checked_func = function() return settings:matchBookFont() end,
                callback = function() settings:set("match_book_font", not settings:matchBookFont()) end,
            },
            {
                text = _("Dictionaries"),
                help_text = _("CC-CEDICT always comes first. For a word it does not have, the popup shows the entry of the first other dictionary that has it, in the order set here (Order). MOE 重編國語辭典 can also be set to Always (its Characters and Words items): under CC-CEDICT's entry for a character (or word) it has too, collapsed to a few lines ending in [Tap to show more]. Wiktionary and the Wikipedia titles are part of the plugin; CBDB, MOE, the idiom files and Moegirlpedia are files you build and install yourself (see the README)."),
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

-- The Dictionaries menu: `items` (the source labels setting), then Order,
-- Collapse long entries, and one on/off item per dictionary in priority
-- order, MOE's followed by its Characters and Words modes. The user's own
-- files show whether they are installed and cannot be switched on without
-- one. Order rebuilds the per-dictionary items in the new order.
function ChineseHelper:fallbackItems(apply, items)
    local plugin, settings = self, self.settings
    local fixed
    local function fill()
        for k = #items, fixed + 1, -1 do items[k] = nil end
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
            if source == "moe" then
                for _j, kind in ipairs({ "chars", "words" }) do
                    items[#items + 1] = plugin:moeModeItem(kind)
                end
            end
        end
    end
    items[#items + 1] = {
        text = _("Order"),
        help_text = _("The order of the dictionaries after CC-CEDICT, which is always first: for a word CC-CEDICT lacks, the first one that has it gives its entry."),
        keep_menu_open = true,
        callback = function(touchmenu) plugin:showOrder(function()
            fill()
            if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
        end) end,
    }
    local collapse = {}
    for _i, n in ipairs(Settings.COLLAPSE_LINES) do
        collapse[#collapse + 1] = {
            text = ChineseHelper.collapseLabel(n), radio = true, keep_menu_open = true,
            checked_func = function() return settings:collapseLines() == n end,
            callback = function() settings:set("collapse_lines", n) end,
        }
    end
    items[#items + 1] = {
        text_func = function()
            return T(_("Collapse long entries: %1"), ChineseHelper.collapseLabel(settings:collapseLines()))
        end,
        help_text = _("An entry shown Always (MOE under CC-CEDICT's) is cut to this many lines, ending in a small grey [Tap to show more]: tap it to see the rest, and [Tap to show less] at the end to cut it again. CC-CEDICT's entries and an entry that is a word's only one are always shown in full."),
        sub_item_table = collapse,
        separator = true,
    }
    fixed = #items
    fill()
    return items
end

-- "1 line", "2 lines", "3 lines", "never".
function ChineseHelper.collapseLabel(n)
    if n == 0 then return _("never") end
    return n == 1 and _("1 line") or T(_("%1 lines"), n)
end

-- "Known & remind-me readings" (#26): the counts, the list (a tap clears
-- one mark), and Clear all (confirmed).
function ChineseHelper:marksItem()
    local plugin = self
    local function counts()
        local ok, marks = pcall(plugin.marks, plugin)
        if not ok then return 0, 0 end
        return marks:count()
    end
    return {
        text_func = function()
            local known, remind = counts()
            return T(_("Known & remind-me readings: %1 known, %2 remind"), known, remind)
        end,
        help_text = T(_("In a popup opened from the page, the button at the right of the title bar marks the tapped character in the reading it has there. I know: that reading never gets pinyin, at any threshold, in every book; its other readings are unchanged. Remind me: it always gets pinyin, at every occurrence, even when common. Tap the button again to clear the mark. The page changes at once. The marks are kept in %1, outside the plugin's folder, so updates and reinstalls keep them: back that file up to keep them, or copy it to another device."), ChineseHelper.marksPath()),
        keep_menu_open = true,
        separator = true,
        sub_item_table_func = function()
            return {
                {
                    text = _("Show marks (tap one to clear it)"),
                    enabled_func = function() local k, r = counts(); return k + r > 0 end,
                    callback = function(touchmenu) plugin:showMarks(touchmenu) end,
                },
                {
                    text = _("Clear all marks"),
                    enabled_func = function() local k, r = counts(); return k + r > 0 end,
                    keep_menu_open = true,
                    callback = function(touchmenu)
                        local ConfirmBox = require("ui/widget/confirmbox")
                        local known, remind = counts()
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Clear all marks (%1 known, %2 remind)?"), known, remind),
                            ok_text = _("Clear all"),
                            ok_callback = function()
                                plugin:marks():clearAll()
                                plugin.annotator:refreshPage()
                                if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
                            end,
                        })
                    end,
                },
            }
        end,
    }
end

-- The list of marks, one line per character and reading; a tap clears that
-- mark and shows the list again.
function ChineseHelper:showMarks(touchmenu)
    local KeyValuePage = require("ui/widget/keyvaluepage")
    local marks = self:marks()
    local plugin = self
    local page
    local kv = {}
    for _i, m in ipairs(marks:list()) do
        kv[#kv + 1] = {
            m.char .. "  " .. m.reading,
            m.state == "known" and _("known") or _("remind me"),
            callback = function()
                marks:clearEntry(m)
                plugin.annotator:refreshPage()
                if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
                UIManager:close(page)
                if #marks:list() > 0 then plugin:showMarks(touchmenu) end
            end,
        }
    end
    page = KeyValuePage:new{ title = _("Known & remind-me readings"), kv_pairs = kv }
    UIManager:show(page)
end

-- MOE's Characters ("chars") or Words mode item: Off / Fallback / Always.
function ChineseHelper:moeModeItem(kind)
    local plugin, settings = self, self.settings
    local key = kind == "words" and "moe_words" or "moe_chars"
    local labels = {
        off = _("Off"),
        fallback = _("Fallback: only when CC-CEDICT lacks it (default)"),
        always = _("Always: also under CC-CEDICT's entry"),
    }
    local sub = {}
    for _i, mode in ipairs(Settings.MOE_MODES) do
        sub[#sub + 1] = {
            text = labels[mode], radio = true, keep_menu_open = true,
            checked_func = function() return settings:moeMode(kind) == mode end,
            callback = function() settings:set(key, mode) end,
        }
    end
    return {
        text_func = function()
            local what = kind == "words" and _("MOE for words: %1") or _("MOE for single characters: %1")
            return "    " .. T(what, ChineseHelper.MOE_MODE_NAMES[settings:moeMode(kind)])
        end,
        help_text = _("Always: MOE's entry is shown under CC-CEDICT's too, collapsed (for a single character: between CC-CEDICT's entry and the components), with its classical senses and the readings CC-CEDICT does not list (marked \"not in CC-CEDICT\"). Fallback (the default): only when CC-CEDICT does not have it. Always needs a MOE file built with Chinese helper 2.5.0 or later; with an older one it works as Fallback (Status says so). MOE never decides the pinyin drawn."),
        enabled_func = function() return settings:fallbackEnabled("moe") and plugin:sourceDb("moe") ~= nil end,
        sub_item_table = sub,
    }
end

-- KOReader's SortWidget over the dictionaries after CC-CEDICT; on_done()
-- after the new order is saved.
function ChineseHelper:showOrder(on_done)
    local SortWidget = require("ui/widget/sortwidget")
    local item_table = {}
    for _i, source in ipairs(self.settings:fallbackOrder()) do
        item_table[#item_table + 1] = { text = ChineseHelper.SOURCE_NAMES[source], source = source }
    end
    UIManager:show(SortWidget:new{
        title = _("Dictionaries after CC-CEDICT"),
        item_table = item_table,
        callback = function()
            local order = {}
            for _i, item in ipairs(item_table) do order[#order + 1] = item.source end
            self.settings:setFallbackOrder(order)
            if on_done then on_done() end
        end,
    })
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
        if ok and meta.components then
            lines[#lines + 1] = T(_("Character components: %1 (%2 characters)"),
                self.settings:componentsEnabled() and _("on") or _("off"), meta.components)
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
    if self.tap.last_tap then
        lines[#lines + 1] = T(_("Last tap: %1"), self.tap.last_tap)
    end
    local old = self:oldPluginsPresent()
    if #old > 0 then
        lines[#lines + 1] = T(_("Old plugins still installed: %1"), table.concat(old, ", "))
    end
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

return ChineseHelper
