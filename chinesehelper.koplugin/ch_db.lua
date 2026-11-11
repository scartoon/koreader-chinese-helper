-- The plugin's one database, data/chinesehelper.sqlite (built by
-- tools/build_db.py), through KOReader's bundled SQLite binding
-- (lua-ljsqlite3). Opened on first use and kept open while the book is.
--
--   entries(simp, trad, pinyin, syllables, defs)   CC-CEDICT, one row per entry;
--                         indexes on simp and trad (the popup's lookup)
--   chars(ch, rank, reading)                       the resolver's tables
--   words(word, syllables, freq, rare)             (see ch_readings.lua);
--   rules(ch, side, neighbour, reading, n)         chars, rules and uncertain are
--   uncertain(ch, confidence, first, second)       read into memory once, words
--   special(word, pinyin, marks, freq, note)       are looked up on demand
--   special_guard(ordinary, word, offset)
--   fallback(simp, trad, pinyin, syllables, defs, source)   other dictionaries,
--                         for words CC-CEDICT lacks (indexes on simp and trad);
--                         the same table in the user's optional MOE file
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

-- CC-CEDICT rows for n candidate words (simplified or traditional form).
function DB.entriesSql(n)
    return "SELECT simp, trad, pinyin, syllables, defs FROM entries WHERE simp IN (" .. marks(n)
        .. ") OR trad IN (" .. marks(n) .. ") ORDER BY rowid"
end

-- Fallback rows for n candidate words (simplified or traditional form).
-- Kept identical to tools/fallback_sources.py's fallback_sql.
function DB.fallbackSql(n)
    return "SELECT simp, trad, pinyin, syllables, defs, source FROM fallback WHERE simp IN (" .. marks(n)
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

-- Rows { {simp=, trad=, pinyin=, syllables=, defs=}, ... } for every CC-CEDICT
-- entry whose simplified or traditional form is one of `words`, in
-- CC-CEDICT order.
function DB:lookup(words)
    local n = #words
    if n == 0 then return {} end
    local args = {}
    for k = 1, n do args[k], args[n + k] = words[k], words[k] end
    local rows = {}
    self:each(DB.entriesSql(n), args, function(row)
        rows[#rows + 1] = { simp = row[1], trad = row[2], pinyin = row[3], syllables = row[4], defs = row[5] }
    end)
    return rows
end

-- Rows { {simp=, trad=, pinyin=, syllables=, defs=, source=}, ... } from the
-- fallback table for `words`, in table order. A database without the table
-- (built before fallback sources existed) gives none.
function DB:fallback(words)
    local n = #words
    if n == 0 then return {} end
    local args = {}
    for k = 1, n do args[k], args[n + k] = words[k], words[k] end
    local rows = {}
    local ok, err = pcall(self.each, self, DB.fallbackSql(n), args, function(row)
        rows[#rows + 1] = { simp = row[1], trad = row[2], pinyin = row[3], syllables = row[4], defs = row[5],
                            source = row[6] }
    end)
    if not ok then return {}, err end
    return rows
end

-- { [word] = { "syllables", freq } } for the words of `list` in the words table.
function DB:words(list)
    local out = {}
    if #list == 0 then return out end
    self:each(DB.wordsSql(#list), list, function(row)
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
