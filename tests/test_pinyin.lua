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

-- Joined pinyin (the fallback dictionaries' only spelling) split into one
-- syllable per character, or nil when that cannot be done in exactly one way.
local function split(p, n)
    local s = Pinyin.splitJoined(p, n)
    return s and table.concat(s, " ") or "nil"
end
eq(split("lěishì", 2), "lěi shì")
eq(split("lěi shì", 2), "lěi shì", "spaced (MOE)")
eq(split("Jiāochénrú", 3), "jiāo chén rú", "lowercased")
eq(split("Xī'ān", 2), "xī ān", "apostrophe")
eq(split("xiān", 2), "nil", "a/e/o start a syllable only after an apostrophe")
eq(split("fāngǎn", 2), "fān gǎn")
eq(split("yīdiǎnr", 3), "yī diǎn r", "erhua as the last syllable")
eq(split("dàn", 2), "nil", "no interjection n")
eq(split("lěishì", 3), "nil", "wrong count")
eq(split("ji¹ zi³", 2), "nil", "Cantonese")
eq(split("sang⁴ qian² tian¹", 3), "nil", "dialect romanisation")
eq(split("lǐǎ", 1), "nil", "two tone marks in one syllable")
