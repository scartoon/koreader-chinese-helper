-- Pinyin comparisons (ch_pinyin.lua).
local Pinyin = require("ch_pinyin")
local eq = require("sq3_shim").eq

eq(Pinyin.lower("Zhōng Guó"), "zhōng guó")
eq(Pinyin.lower("Ǎ Ü"), "ǎ ü")
eq(Pinyin.stripTones("lǜ zhuàng"), "lü zhuang")
-- A dictionary neutral tone stands for the toned reading with the same letters.
assert(Pinyin.syllableMatches("dao", "dǎo"))
assert(not Pinyin.syllableMatches("dǎo", "dao"), "a toned syllable is not the neutral one")
assert(not Pinyin.syllableMatches("r", "ér"), "erhua")
assert(Pinyin.matches("gǔ dao", "gǔ dǎo"))
assert(Pinyin.matches("Dà yuān", "dà yuān"), "case-insensitive")
assert(not Pinyin.matches("dōng xī", "dōng xi"), "dōngxī is not dōngxi")
assert(Pinyin.matches("dōng xi", "dōng xi"))
assert(not Pinyin.matches("dà", "dà yuān"), "different lengths")
assert(Pinyin.matchesAny("shèng", "chéng/shèng"))
assert(not Pinyin.matchesAny("chèng", "chéng/shèng"))
assert(Pinyin.matchesAny("Lè", "lè"))
