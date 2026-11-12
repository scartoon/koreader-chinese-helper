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

------------------------------------------------------------------------
-- Splitting joined pinyin ("lěishì", the fallback dictionaries' only
-- spelling) into one syllable per character.
------------------------------------------------------------------------

-- Every Mandarin syllable without tones (from pypinyin's character table),
-- less the interjections m, n, ng, hm and hng: as syllables of their own
-- they would split dàn into dà n.
local SYLLABLES = {}
for s in ([[a ai an ang ao ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bong bu
ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua
chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo da dai dan dang dao de dei den deng
di dia dian diao die din ding diu dong dou du duan dui dun duo e ei en eng er fa fan fang fei fen feng
fiao fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo ha hai
han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo ji jia jian jiang jiao jie jin
jing jiong jiu ju juan jue jun ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui
kun kuo la lai lan lang lao le lei len leng li lia lian liang liao lie lin ling liu lo long lou lu
luan lun luo lü lüe ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu na nai
nan nang nao ne nei nen neng ni nia nian niang niao nie nin ning niu nong nou nu nuan nun nuo nü nüe
o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu qi qia qian qiang qiao qie
qin qing qiong qiu qu quan que qun ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo sa sai
san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan
shuang shui shun shuo si song sou su suan sui sun suo ta tai tan tang tao te tei teng ti tian tiao tie
ting tong tou tu tuan tui tun tuo wa wai wan wang wei wen weng wo wong wu xi xia xian xiang xiao xie
xin xing xiong xiu xu xuan xue xun ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun za zai
zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua
zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo]]):gmatch("%S+") do
    SYLLABLES[s] = true
end

local function utf8_chars(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

-- Syllables starting with a, e or o need an apostrophe when they do not start
-- the word (xī'ān): without one, the letters belong to the syllable before.
local function vowelInitial(ch)
    return Pinyin.stripTones(ch):match("^[aeo]$") ~= nil
end

--[[--
The syllables of a joined reading ("lěishì" -> { "lěi", "shì" }), lowercase,
when it splits into exactly n Mandarin syllables in exactly one way; nil
otherwise (Cantonese "ji¹ zi³", stray characters, more than one split). Spaces,
apostrophes and hyphens separate syllables; erhua "r" counts only as the last
syllable (一点儿 yīdiǎnr). A syllable carries at most one tone mark.
]]
function Pinyin.splitJoined(pinyin, n)
    if not pinyin or pinyin == "" or not n or n < 1 then return nil end
    -- Characters, with true marking the start of a separated segment.
    local chars, starts = {}, {}
    local new_segment = true
    for _, ch in ipairs(utf8_chars(Pinyin.lower(pinyin))) do
        if ch == " " or ch == "'" or ch == "-" or ch == "’" or ch == "·" then
            new_segment = true
        else
            chars[#chars + 1] = ch
            starts[#chars] = new_segment
            new_segment = false
        end
    end
    if #chars == 0 then return nil end
    local found, count = nil, 0
    local path = {}
    local function walk(p)
        if count > 1 then return end
        if p > #chars then
            if #path == n then
                count = count + 1
                found = {}
                for k, syl in ipairs(path) do found[k] = syl end
            end
            return
        end
        if #path >= n then return end
        if not starts[p] and vowelInitial(chars[p]) then return end
        local parts, marks = {}, 0
        for q = p, math.min(#chars, p + 5) do
            if q > p and starts[q] then break end
            local ch = chars[q]
            local plain = Pinyin.stripTones(ch)
            if plain ~= ch then marks = marks + 1 end
            if not plain:match("^[a-z]$") and plain ~= "ü" then break end
            parts[#parts + 1] = ch
            if marks > 1 then break end
            local syl = table.concat(parts)
            local base = Pinyin.stripTones(syl)
            local ok = SYLLABLES[base]
                or (base == "r" and #path > 0 and #path == n - 1 and q == #chars)
            if ok then
                path[#path + 1] = syl
                walk(q + 1)
                path[#path] = nil
            end
        end
    end
    walk(1)
    if count ~= 1 then return nil end
    return found
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
