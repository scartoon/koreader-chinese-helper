-- The database module (ch_db.lua) against the real database, and its SQL
-- against the build's (tools/build_db.py checks those queries' plans).
local DB = require("ch_db")
local H = require("sq3_shim")
local eq = H.eq

for _, n in ipairs({ 1, 2, 36 }) do
    eq(DB.entriesSql(n), PY_ENTRIES_SQL(n), "entries SQL for " .. n)
end
for _, n in ipairs({ 1, 9 }) do
    eq(DB.wordsSql(n), PY_WORDS_SQL(n), "words SQL for " .. n)
end

local db = H.db()
local rows = db:lookup({ "东西", "東西" })
eq(#rows, 2, "东西 has two CC-CEDICT entries")
eq(rows[1].pinyin, "dōngxī"); eq(rows[1].syllables, "dōng xī"); eq(rows[2].pinyin, "dōngxi")
assert(rows[2].defs:find("thing", 1, true))
eq(#db:lookup({}), 0)
rows = db:lookup({ "歷史" })
eq(rows[1].simp, "历史", "traditional lookup")

local words = db:words({ "东西", "银行", "不存在的词" })
eq(words["东西"][1], "dōng xi"); eq(words["银行"][1], "yín háng")
assert(words["东西"][2] > 0, "frequency"); assert(words["不存在的词"] == nil)

local meta = db:meta()
assert(meta.cedict_entries and tonumber(meta.cedict_entries) > 100000, "meta")

local data = H.readings()
local rank, reading = data:char("的")
assert(rank and rank < 10, "common characters are in the tables now"); eq(reading, "dì")
rank, reading = data:char("饕")
assert(rank == 0 or rank > 1000); eq(reading, "tāo")
-- Words come from the database on demand, cached.
local syl = data:word("的确")
eq(table.concat(syl, " "), "dí què")
assert(data.cache["的确"], "cached")
assert(data:word("东东东") == nil and data.cache["东东东"] == false, "misses cached too")
eq(data:rule("行", nil, nil), nil)
local first, second = data:uncertainty("了")
eq(first, "le"); eq(second, "liǎo")
