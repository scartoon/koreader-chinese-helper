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

-- Every word with a rare character is in memory, so annotating a page never
-- queries the database; common words still come from it.
local in_memory = 0
for _ in pairs(data.words) do in_memory = in_memory + 1 end
eq(tostring(in_memory), meta.rare_words, "words with a rare character loaded")
local queries = 0
local real = data.lookup
data.lookup = function(list) queries = queries + 1; return real(list) end
assert(data:word("饕不存在") == nil)
local Resolve = require("ch_resolve")
Resolve.annotate(data, H.items("两军对峙，饕餮之徒，侥幸逃脱，僬侥之国。"), 1500, "both", H.special())
eq(queries, 0, "no database query for a page's annotations")
data.cache, data.cached = {}, 0
data:word("东西")
eq(queries, 1, "a common word is looked up")
data.lookup = real

-- Fallback dictionaries: their own table, same SQL as the build, never a row
-- for a headword CC-CEDICT has.
for _, n in ipairs({ 1, 2, 36 }) do
    eq(DB.fallbackSql(n), PY_FALLBACK_SQL(n), "fallback SQL for " .. n)
end
local fb = db:fallback({ "尚书省" })
eq(#fb, 1, "尚书省 from Wiktionary"); eq(fb[1].source, "wikt"); eq(fb[1].trad, "尚書省")
assert(fb[1].defs:find("Department of State Affairs", 1, true), fb[1].defs)
eq(#db:lookup({ "尚书省" }), 0, "not in CC-CEDICT")
-- Simplified and traditional forms both find the entry (鞑子 is a soft redirect to 韃子).
eq(#db:fallback({ "鞑子" }), 1); eq(db:fallback({ "鞑子" })[1].trad, "韃子")
eq(#db:fallback({ "韃子" }), 1); eq(db:fallback({ "韃子" })[1].pinyin, "dázi")
eq(#db:fallback({ "躺平", "东西", "很多", "一百" }), 0,
   "CC-CEDICT's words (躺平 is in CC-CEDICT), everyday combinations, numerals: none")
eq(#db:fallback({}), 0)
local overlap
db:each("SELECT count(*) FROM fallback WHERE simp IN (SELECT simp FROM entries) OR simp IN (SELECT trad FROM entries)"
    .. " OR trad IN (SELECT simp FROM entries) OR trad IN (SELECT trad FROM entries)", nil,
    function(row) overlap = tonumber(row[1]) end)
eq(overlap, 0, "no fallback row for a CC-CEDICT headword")
local sources = {}
db:each("SELECT DISTINCT source FROM fallback", nil, function(row) sources[#sources + 1] = row[1] end)
eq(table.concat(sources, ","), "wikt", "only Wiktionary in the release database")
-- Version information for the Status screen and data/README.md.
local meta2 = db:meta()
eq(meta2.fallback_sources, "wikt"); assert(meta2.wikt_dump ~= "" and meta2.wikt_sha256 and meta2.resolver_sha256)
