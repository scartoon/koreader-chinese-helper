-- Pinyin string helpers (pure Lua): case folding, tone stripping, and whether
-- a dictionary reading is the one the resolver chose. From pinyin_defs.lua in
-- koreader-interlinear-pinyin.
--
-- Readings come in two spellings:
--   syllables  "dōng xi"   space-separated, as the resolver and the words
--                          table have them (and CC-CEDICT's `syllables` column)
--   joined     "dōngxi"    CC-CEDICT's display form (apostrophes, names)
-- Comparisons are always made on syllables.

local Pinyin = {}

local function split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return out
end
Pinyin.split = split

-- Lowercase pinyin, including capital vowels with tone marks.
local UPPER = {
    ["Ā"] = "ā", ["Á"] = "á", ["Ǎ"] = "ǎ", ["À"] = "à", ["Ē"] = "ē", ["É"] = "é", ["Ě"] = "ě", ["È"] = "è",
    ["Ī"] = "ī", ["Í"] = "í", ["Ǐ"] = "ǐ", ["Ì"] = "ì", ["Ō"] = "ō", ["Ó"] = "ó", ["Ǒ"] = "ǒ", ["Ò"] = "ò",
    ["Ū"] = "ū", ["Ú"] = "ú", ["Ǔ"] = "ǔ", ["Ù"] = "ù", ["Ǖ"] = "ǖ", ["Ǘ"] = "ǘ", ["Ǚ"] = "ǚ", ["Ǜ"] = "ǜ",
    ["Ü"] = "ü",
}
-- (string.lower depends on the C locale: in some UTF-8 locales it changes
-- bytes >= 0x80 and breaks multi-byte characters, so only A-Z are mapped.)
function Pinyin.lower(s)
    s = s:gsub("[\195-\199][\128-\191]", UPPER)
    s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
    return s
end

-- Tone marks removed (after lower()); ü keeps its dots: "lǜ" -> "lü".
local PLAIN = {
    ["ā"] = "a", ["á"] = "a", ["ǎ"] = "a", ["à"] = "a", ["ē"] = "e", ["é"] = "e", ["ě"] = "e", ["è"] = "e",
    ["ī"] = "i", ["í"] = "i", ["ǐ"] = "i", ["ì"] = "i", ["ō"] = "o", ["ó"] = "o", ["ǒ"] = "o", ["ò"] = "o",
    ["ū"] = "u", ["ú"] = "u", ["ǔ"] = "u", ["ù"] = "u", ["ǖ"] = "ü", ["ǘ"] = "ü", ["ǚ"] = "ü", ["ǜ"] = "ü",
}
function Pinyin.stripTones(s)
    return (s:gsub("[\195-\199][\128-\191]", PLAIN))
end

-- Does a dictionary syllable stand for the chosen reading? Equal, or the
-- dictionary's neutral tone of it: words give 鼓捣 as "gǔ dao" where 捣 is
-- shown as dǎo. Erhua "r" stands for no reading. Both lowercase.
function Pinyin.syllableMatches(syllable, chosen)
    if syllable == chosen then return true end
    return syllable ~= "r" and syllable == Pinyin.stripTones(syllable)
        and syllable == Pinyin.stripTones(chosen)
end

-- The same for whole readings in syllable form ("gǔ dao" for "gǔ dǎo"),
-- case-insensitively.
function Pinyin.matches(syllables, chosen)
    syllables, chosen = Pinyin.lower(syllables), Pinyin.lower(chosen)
    if syllables == chosen then return true end
    local a, b = split(syllables, " "), split(chosen, " ")
    if #a ~= #b then return false end
    for k = 1, #a do
        if not Pinyin.syllableMatches(a[k], b[k]) then return false end
    end
    return true
end

-- Is a single-character reading one of the chosen ones (`chosen` may be a
-- pair "chéng/shèng")?
function Pinyin.matchesAny(syllable, chosen)
    syllable = Pinyin.lower(syllable)
    for reading in Pinyin.lower(chosen or ""):gmatch("[^/]+") do
        if Pinyin.syllableMatches(syllable, reading) then return true end
    end
    return false
end

return Pinyin
