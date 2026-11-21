-- The plugin's one database, data/chinesehelper.sqlite (built by
-- tools/build_db.py), through KOReader's bundled SQLite binding
-- (lua-ljsqlite3). Opened on first use and kept open for the rest of the
-- KOReader session, shared by every book (main.lua).
--
--   entries(simp, trad, pinyin, syllables, defs, defs_simp)   CC-CEDICT, one row
--                         per entry; indexes on simp and trad (the popup's lookup)
--   chars(ch, rank, reading)                       the resolver's tables
--   words(word, syllables, freq, rare)             (see ch_readings.lua);
--   word_marks(word, syllables)                    chars, word_marks, rules and
--   rules(ch, side, neighbour, reading, n)         uncertain are read into
--   uncertain(ch, confidence, first, second)       memory once, words are
--   special(word, pinyin, marks, freq, note)       looked up on demand
--   special_guard(ordinary, word, offset)
--   fallback(simp, trad, pinyin, syllables, defs, source)   other dictionaries,
--                         for words CC-CEDICT lacks (indexes on simp and trad);
--                         the same table in the user's optional files, which
--                         from 2.5.0 on add a `covered` column: 1 for a row
--                         whose headword CC-CEDICT has (MOE's file only),
--                         never a fallback entry
--   idioms(simp, trad, short, view, short_simp, view_simp)   in the user's 成語典
--                         and Xinhua files only: an idiom's Chinese short line and
--                         Origin & Usage view
--   Text columns (#48, 2.13.0): defs, short and view hold each dictionary's
--   text as its source writes it; defs_simp, short_simp and view_simp the
--   same in simplified characters, NULL when that is no different. Files
--   built before 2.13.0 have only the one text (DB:hasColumn).
--   components(ch, body)                           a character's parts, for the popup
--   component_notes(ch, text)                      (ch_components.lua); missing from
--                         databases built before 1.7.0
--   meta(key, value)
--
-- The SQL here must stay identical to tools/build_db.py's, which checks the
-- query plans (tests/test_db.lua compares them).

local Readings = require("ch_readings")

local DB = {}
DB.__index = DB

-- nil, err when the file or the binding is missing. SQ3: the binding (tests
-- pass a stand-in).
function DB.open(path, SQ3)
    local f = io.open(path, "rb")
    if not f then return nil, "missing " .. path end
    f:close()
    if not SQ3 then
        local ok, mod = pcall(require, "lua-ljsqlite3/init")
        if not ok then return nil, "SQLite binding not available: " .. tostring(mod) end
        SQ3 = mod
    end
    local ok, conn = pcall(SQ3.open, path, "ro")
    if not ok or not conn then return nil, "cannot open " .. path .. ": " .. tostring(conn) end
    return setmetatable({ conn = conn, stmts = {} }, DB)
end

function DB:close()
    for _, stmt in pairs(self.stmts) do pcall(stmt.close, stmt) end
    self.stmts = {}
    if self.conn then pcall(self.conn.close, self.conn) end
    self.conn = nil
end

local function marks(n)
    return string.rep("?,", n - 1) .. "?"
end

-- Statements are prepared once per SQL text and kept, and the text depends on
-- the number of words. So that the cache does not grow with every distinct
-- count, lists are padded with "" (which no row has) to a power of two up to
-- 1,024, then to a multiple of 1,024.
function DB.padded(n)
    if n > 1024 then return math.ceil(n / 1024) * 1024 end
    local m = 1
    while m < n do m = m * 2 end
    return m
end

-- `list` padded to DB.padded(#list), repeated `times` times (simp IN, trad IN).
local function padded_args(list, times)
    local n, m = #list, DB.padded(#list)
    local args = {}
    for t = 0, times - 1 do
        for k = 1, m do args[t * m + k] = k <= n and list[k] or "" end
    end
    return args, m
end

-- CC-CEDICT rows for n candidate words (simplified or traditional form).
-- (The plugin's own database always has defs_simp: it ships with the code.)
-- The xref_* columns (#61): a cross-reference-only entry's target word.
function DB.entriesSql(n)
    return "SELECT simp, trad, pinyin, syllables, defs, defs_simp, xref_simp, xref_trad, xref_pinyin, "
        .. "xref_defs, xref_defs_simp FROM entries WHERE simp IN (" .. marks(n)
        .. ") OR trad IN (" .. marks(n) .. ") ORDER BY rowid"
end

-- Fallback rows for n candidate words (simplified or traditional form).
-- uncovered: leave out covered rows (a table with the `covered` column);
-- simp: also read defs_simp (a table that has it).
-- Kept identical to tools/fallback_sources.py's fallback_sql.
function DB.fallbackSql(n, uncovered, simp)
    local cols = "simp, trad, pinyin, syllables, defs, source" .. (simp and ", defs_simp" or "")
    if uncovered then
        return "SELECT " .. cols .. " FROM fallback WHERE (simp IN (" .. marks(n)
            .. ") OR trad IN (" .. marks(n) .. ")) AND covered = 0 ORDER BY rowid"
    end
    return "SELECT " .. cols .. " FROM fallback WHERE simp IN (" .. marks(n)
        .. ") OR trad IN (" .. marks(n) .. ") ORDER BY rowid"
end

-- Every fallback row for n words, covered ones included, with the `covered`
-- column (a table that has it): MOE's one query per tap when it is shown
-- Always. Kept identical to tools/fallback_sources.py's fallback_all_sql.
function DB.fallbackAllSql(n, simp)
    local cols = "simp, trad, pinyin, syllables, defs, source, covered" .. (simp and ", defs_simp" or "")
    return "SELECT " .. cols .. " FROM fallback WHERE simp IN (" .. marks(n)
        .. ") OR trad IN (" .. marks(n) .. ") ORDER BY rowid"
end

-- The resolver's word readings for n words.
function DB.wordsSql(n)
    return "SELECT word, syllables, freq FROM words WHERE word IN (" .. marks(n) .. ")"
end

-- Run a prepared statement (cached by its SQL) with `args`, calling fn(row)
-- for every row.
function DB:each(sql, args, fn)
    if not self.conn then return end
    local stmt = self.stmts[sql]
    if not stmt then
        stmt = self.conn:prepare(sql)
        self.stmts[sql] = stmt
    end
    stmt:reset()
    if args and #args > 0 then stmt:bind((table.unpack or unpack)(args)) end
    local row = stmt:step()
    while row do
        fn(row)
        row = stmt:step()
    end
    if args and #args > 0 then stmt:clearbind() end
end

-- Rows { {simp=, trad=, pinyin=, syllables=, defs=, defs_simp=, xref=}, ... }
-- for every CC-CEDICT entry whose simplified or traditional form is one of
-- `words`, in CC-CEDICT order (defs_simp nil when the same as defs). xref,
-- for an entry whose only senses are cross-references (#61): the word they
-- lead to, {simp=, trad=, pinyin=, defs=, defs_simp=}; nil otherwise.
function DB:lookup(words)
    if #words == 0 then return {} end
    local args, n = padded_args(words, 2)
    local rows = {}
    self:each(DB.entriesSql(n), args, function(row)
        local xref
        if row[10] ~= nil then
            xref = { simp = row[7], trad = row[8], pinyin = row[9], defs = row[10], defs_simp = row[11] }
        end
        rows[#rows + 1] = { simp = row[1], trad = row[2], pinyin = row[3], syllables = row[4], defs = row[5],
                            defs_simp = row[6], xref = xref }
    end)
    return rows
end

-- The simplified form that keys character `ch` read `reading` (reading
-- marks, ch_marks.lua), from CC-CEDICT's single-character rows: a
-- traditional character takes the simplified form of its row in that
-- reading, so 乾 qián stays 乾 but 乾 gān is 干, 著 zhù stays 著 but 著 zhe is
-- 着. A character with no row as a traditional form (most simplified ones)
-- is its own key.
DB.SIMPLIFY_SQL = "SELECT simp, syllables FROM entries WHERE trad = ? AND length(simp) = 1"
function DB:simplifiedOf(ch, reading)
    local rows = {}
    self:each(DB.SIMPLIFY_SQL, { ch }, function(row) rows[#rows + 1] = { row[1], row[2] } end)
    if #rows == 0 then return ch end
    local match
    for _, r in ipairs(rows) do
        if r[2] == reading or r[2]:lower() == reading then
            if r[1] == ch then return ch end
            match = match or r[1]
        end
    end
    if match then return match end
    for _, r in ipairs(rows) do if r[1] == ch then return ch end end
    return rows[1][1]
end

-- `s` and every traditional form CC-CEDICT gives it as a single character
-- (这: 这, 這): the page forms that can key to `s`.
DB.TRADITIONAL_SQL = "SELECT DISTINCT trad FROM entries WHERE simp = ? AND length(trad) = 1"
function DB:formsOf(s)
    local out, seen = { s }, { [s] = true }
    self:each(DB.TRADITIONAL_SQL, { s }, function(row)
        if not seen[row[1]] then seen[row[1]] = true; out[#out + 1] = row[1] end
    end)
    return out
end

-- Whether table `tbl` has column `col`, checked once per database and
-- table (false when the table is missing).
function DB:hasColumn(tbl, col)
    self.columns = self.columns or {}
    local cols = self.columns[tbl]
    if not cols then
        cols = {}
        pcall(self.each, self, "PRAGMA table_info(" .. tbl .. ")", nil, function(row)
            cols[row[2]] = true
        end)
        self.columns[tbl] = cols
    end
    return cols[col] == true
end

-- Whether the fallback table has the `covered` column (files built before
-- 2.5.0, and the release database, have none).
function DB:hasCovered()
    return self:hasColumn("fallback", "covered")
end

-- Rows { {simp=, trad=, pinyin=, syllables=, defs=, source=}, ... } from the
-- fallback table for `words`, in table order, never a covered row. A
-- database without the table (built before fallback sources existed) gives
-- none.
function DB:fallback(words)
    if #words == 0 then return {} end
    local args, n = padded_args(words, 2)
    local rows = {}
    local simp = self:hasColumn("fallback", "defs_simp")
    local ok, err = pcall(self.each, self, DB.fallbackSql(n, self:hasCovered(), simp), args, function(row)
        rows[#rows + 1] = { simp = row[1], trad = row[2], pinyin = row[3], syllables = row[4], defs = row[5],
                            source = row[6], defs_simp = row[7] }
    end)
    if not ok then return {}, err end
    return rows
end

-- Rows as DB:fallback gives them, covered ones included, each with
-- covered = true or false. Only for a table with the `covered` column
-- (DB:hasCovered); {} otherwise.
function DB:fallbackAll(words)
    if #words == 0 or not self:hasCovered() then return {} end
    local args, n = padded_args(words, 2)
    local rows = {}
    local simp = self:hasColumn("fallback", "defs_simp")
    local ok, err = pcall(self.each, self, DB.fallbackAllSql(n, simp), args, function(row)
        rows[#rows + 1] = { simp = row[1], trad = row[2], pinyin = row[3], syllables = row[4], defs = row[5],
                            source = row[6], covered = tonumber(row[7]) == 1, defs_simp = row[8] }
    end)
    if not ok then return {}, err end
    return rows
end

-- An idiom's short line and Origin & Usage view for n candidate words, from the
-- user's 成語典 or Xinhua file (tools/chengyu.py). Kept identical to
-- tools/chengyu.py's idioms_sql. simp: also read short_simp and view_simp.
function DB.idiomsSql(n, simp)
    local cols = "simp, trad, short, view" .. (simp and ", short_simp, view_simp" or "")
    return "SELECT " .. cols .. " FROM idioms WHERE simp IN (" .. marks(n)
        .. ") OR trad IN (" .. marks(n) .. ") ORDER BY rowid"
end

-- Rows { {simp=, trad=, short=, view=, short_simp=, view_simp=}, ... } for
-- `words`; none from a database without the table (every database but those
-- two files).
function DB:idioms(words)
    if #words == 0 then return {} end
    local args, n = padded_args(words, 2)
    local rows = {}
    local simp = self:hasColumn("idioms", "short_simp")
    local ok, err = pcall(self.each, self, DB.idiomsSql(n, simp), args, function(row)
        rows[#rows + 1] = { simp = row[1], trad = row[2], short = row[3], view = row[4],
                            short_simp = row[5], view_simp = row[6] }
    end)
    if not ok then return {}, err end
    return rows
end

-- Components rows and origin notes for one or two characters. Kept identical
-- to tools/build_db.py's COMPONENTS_SQL and NOTES_SQL.
DB.COMPONENTS_SQL = "SELECT ch, body FROM components WHERE ch IN (?, ?)"
DB.NOTES_SQL = "SELECT ch, text FROM component_notes WHERE ch IN (?, ?) ORDER BY rowid"

-- { [ch] = body } for the characters of `list` (one or two; more are
-- looked up two at a time). A database without the table gives none.
function DB:components(list)
    local out = {}
    for k = 1, #list, 2 do
        pcall(self.each, self, DB.COMPONENTS_SQL, { list[k], list[k + 1] or "" }, function(row)
            out[row[1]] = row[2]
        end)
    end
    return out
end

-- { [ch] = text } of the origin notes for the characters of `list`.
function DB:notes(list)
    local out = {}
    for k = 1, #list, 2 do
        pcall(self.each, self, DB.NOTES_SQL, { list[k], list[k + 1] or "" }, function(row)
            out[row[1]] = row[2]
        end)
    end
    return out
end

-- The Classical dictionary (#53, #55). Kept identical to
-- tools/build_classical.py's CLASSICAL_SQL and VARIANT_SQL.
DB.CLASSICAL_SQL = "SELECT trad, simp, senses FROM classical WHERE trad = ? OR simp = ? ORDER BY trad"
DB.CLASSICAL_VARIANT_SQL = "SELECT trad FROM classical_variant WHERE ch = ?"

-- Whether this database has the Classical dictionary.
function DB:hasClassical()
    if self.has_classical == nil then self.has_classical = self:hasColumn("classical", "senses") end
    return self.has_classical
end

-- The Classical entries for one character: { {trad=, simp=, senses=}, ... }
-- (senses: "reading<TAB>gloss<TAB>sources" lines), keyed by its traditional
-- or simplified form; a variant with no entry of its own (説) gets its
-- target's (說). Empty when there is none, or no table.
function DB:classical(ch)
    local out = {}
    local function collect(want)
        pcall(self.each, self, DB.CLASSICAL_SQL, { want, want }, function(row)
            if want == ch or row[1] == want then out[#out + 1] = { trad = row[1], simp = row[2], senses = row[3] } end
        end)
    end
    collect(ch)
    if #out == 0 then
        local target
        pcall(self.each, self, DB.CLASSICAL_VARIANT_SQL, { ch }, function(row) target = row[1] end)
        if target then collect(target) end
    end
    return out
end

-- { [word] = { "syllables", freq } } for the words of `list` in the words table.
function DB:words(list)
    local out = {}
    if #list == 0 then return out end
    local args, n = padded_args(list, 1)
    self:each(DB.wordsSql(n), args, function(row)
        out[row[1]] = { row[2], tonumber(row[3]) or 0 }
    end)
    return out
end

-- The resolver's tables: chars, rules, uncertain and the words containing a
-- rare character in memory (everything a page's annotations need), the
-- other words looked up here on demand.
function DB:readings()
    local db = self
    local data = Readings.new{ word_lookup = function(list) return db:words(list) end }
    self:each("SELECT ch, rank, reading FROM chars", nil, function(row)
        data:addChar(row[1], tonumber(row[2]), row[3])
    end)
    self:each("SELECT word, syllables, freq FROM words WHERE rare = 1", nil, function(row)
        data:addWord(row[1], row[2], tonumber(row[3]))
    end)
    -- Missing from databases built before 1.6.0: nothing to mark then.
    pcall(self.each, self, "SELECT word, syllables FROM word_marks", nil, function(row)
        data:addWordMark(row[1], row[2])
    end)
    self:each("SELECT ch, side, neighbour, reading, n FROM rules", nil, function(row)
        data:addRule(row[1], row[2], row[3], row[4], tonumber(row[5]))
    end)
    self:each("SELECT ch, confidence, first, second FROM uncertain", nil, function(row)
        data:addUncertain(row[1], tonumber(row[2]), row[3], row[4])
    end)
    return data
end

-- The special words (unusual readings of common characters).
function DB:special()
    local special = Readings.newSpecial()
    self:each("SELECT word, pinyin, marks, freq, note FROM special", nil, function(row)
        Readings.addSpecial(special, row[1], row[2], row[3], tonumber(row[4]), row[5])
    end)
    self:each("SELECT ordinary, word, offset FROM special_guard", nil, function(row)
        Readings.addGuard(special, row[1], row[2], tonumber(row[3]))
    end)
    return special
end

-- { key = value } from the meta table (source versions, licence, counts).
function DB:meta()
    local out = {}
    self:each("SELECT key, value FROM meta", nil, function(row) out[row[1]] = row[2] end)
    return out
end

return DB
