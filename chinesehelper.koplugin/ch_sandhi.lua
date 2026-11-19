-- Spoken tones of 一 and 不 (#37): yí gè, yì tiān, bú shì, kàn bu jiàn,
-- drawn instead of the dictionary tones yī and bù when the setting is on.
-- Pure Lua (no KOReader dependencies), tested offline.
--
-- Display only: Resolve.annotate applies it after the reading is resolved
-- (and after the reading marks, which stay keyed on the dictionary reading),
-- so the popup's entries and the marks see yī and bù as before.
--
-- The rules look at the next syllable's underlying tone: its resolved
-- reading, or, when that is neutral, its character's toned default (个
-- drawn ge counts as gè, so 一个 is yí ge).
--
--   不  bú before a fourth tone (不是, 不要). Neutral bu in A-不-A (是不是)
--       and between a verb and its complement (看不见, 说不出): the
--       complement is one of Sandhi.COMPLEMENTS and the verb + 得 +
--       complement is a dictionary word. 不不 ("no, no") stays bù bù.
--   一  yí before a fourth tone (一个, 一定), yì before the other tones (一天,
--       一年, 一起). Neutral yi in a reduplicated verb (看一看). It stays yī
--       as a number or ordinal: before punctuation or anything not Han;
--       after 第 or 初; next to another digit (十一, 一九九八, 一一); in
--       dates (一月, 一号) and a few ordinal words (一等奖, 一审); at the end
--       of a dictionary word (统一, 唯一, 之一). Before 百, 千, 万 and 亿 it
--       is a quantity and changes as usual (一百 yìbǎi, 一万 yíwàn), also
--       after one of them (一万一千 yíwàn yìqiān).
--
-- A reading the dictionary already gives as neutral (对不起 duì bu qǐ, 比一比
-- bǐ yi bǐ) or with the spoken tone (赔不是 péi bú shi) is left as it is.

local Sandhi = {}

Sandhi.YI, Sandhi.BU = "一", "不"
Sandhi.SPOKEN = { [Sandhi.YI] = true, [Sandhi.BU] = true }

-- The setting's values.
Sandhi.LEARNER, Sandhi.ALWAYS, Sandhi.NEVER = "learner", "always", "never"

local function set(s)
    local t = {}
    for c in s:gmatch("[\192-\247][\128-\191]*") do t[c] = true end
    return t
end

-- Digits that make 一 part of a number read digit by digit or a compound
-- numeral (十一, 二〇一一, 一九九八).
Sandhi.DIGITS = set("〇零一二三四五六七八九十")
-- Units after which 一 is a quantity again when another unit follows.
Sandhi.UNITS = set("百千万亿萬億")
Sandhi.ORDINAL_PREV = set("第初")
-- Dates: 一月, 一号, 一號.
Sandhi.DATE_NEXT = set("月号號")
-- Words where 一 is "first" (CC-CEDICT gives yī; spoken yī).
Sandhi.ORDINAL_WORDS = {
    ["一等"] = true, ["一级"] = true, ["一級"] = true, ["一审"] = true, ["一審"] = true,
    ["一品"] = true, ["一甲"] = true, ["一秘"] = true, ["一年级"] = true, ["一年級"] = true,
}
-- Words that end in 一, read yī (统一了, 唯一的, 之一是). From CC-CEDICT's
-- words ending in 一, less the ones after which 一 still changes (刚一进门
-- gāng yí jìn mén, 另一个, 头一次, 大一点, 不一定) and the ones other
-- rules cover (十一, 初一, 第一). The words table cannot tell: it leaves out
-- words read as their characters' defaults (统一).
Sandhi.FINAL_WORDS = {}
for w in ("统一 統一 唯一 惟一 万一 萬一 之一 其一 专一 專一 单一 單一 划一 劃一 合一 均一 逐一 "
        .. "星期一 礼拜一 禮拜一 周一 週一 如一 混一 齐一 齊一 独一 獨一 归一 歸一 同一"):gmatch("%S+") do
    Sandhi.FINAL_WORDS[w] = true
end
-- X一X is a reduplicated verb (看一看, 清一清) unless X is one of these nouns
-- and measure words, where 一 is a number (明年一年, 四个人一人, 秦国一国,
-- 人家一家, 旁边一边) or an enumeration (一是…二是).
Sandhi.NOT_REDUP = set("定路年天日月时時人国國家边邊是个個次回步口句层層片条條张張位种種样樣件代辈輩世生身面方处處头頭点點"
    .. "下声聲手眼刀脚腳枪槍拳顿頓场場阵陣遍份")
-- Two-syllable directional complements after V不 (拿不过来, 想不起来).
Sandhi.DIRECTIONAL = {}
for w in ("过来 過來 过去 過去 起来 起來 出来 出來 出去 下来 下來 下去 上来 上來 上去 回来 回來 回去 "
        .. "进来 進來 进去 進去 开来 開來"):gmatch("%S+") do
    Sandhi.DIRECTIONAL[w] = true
end
-- Not verbs: no directional complement after them (他不过来 is bú).
Sandhi.NOT_VERBS = set("我你他她它您们們谁誰这這那此其之也都就还還又才并並却卻再很更最已曾总總便倒竟绝絕决決"
    .. "毫永从從根本全俱皆亦尚仍而且但可若如是着著了的得地么麼呢吧啊人年天时時日月岁歲个個些点點"
    .. "能会會要该該应應敢肯岂豈")
-- Resultative and directional complements after V不 (看不见, 来不及).
Sandhi.COMPLEMENTS = set("见見到了起动動住完及过過下上出来來去开開懂清着著透惯慣成掉走够夠赢贏得")

local TONE_MARKS = {
    ["ā"] = 1, ["á"] = 2, ["ǎ"] = 3, ["à"] = 4, ["ē"] = 1, ["é"] = 2, ["ě"] = 3, ["è"] = 4,
    ["ī"] = 1, ["í"] = 2, ["ǐ"] = 3, ["ì"] = 4, ["ō"] = 1, ["ó"] = 2, ["ǒ"] = 3, ["ò"] = 4,
    ["ū"] = 1, ["ú"] = 2, ["ǔ"] = 3, ["ù"] = 4, ["ǖ"] = 1, ["ǘ"] = 2, ["ǚ"] = 3, ["ǜ"] = 4,
}

-- Tone of a pinyin syllable (1-4), or nil when it has no tone mark (neutral).
-- Of a pair ("chéng/shèng"), the first reading's.
function Sandhi.tone(syllable)
    if not syllable then return nil end
    syllable = syllable:match("^[^/]*")
    for c in syllable:gmatch("[\192-\247][\128-\191]*") do
        local t = TONE_MARKS[c]
        if t then return t end
    end
    return nil
end

-- Is the setting on at this threshold? (0 = All characters, learner mode.)
function Sandhi.enabled(mode, threshold)
    if mode == Sandhi.ALWAYS then return true end
    if mode == Sandhi.NEVER then return false end
    return threshold == 0
end

local function han(data, item)
    return item ~= nil and data:char(item.text) ~= nil
end

-- items[j] when it is a Han character directly joined to items[j-1].
local function joined_next(data, items, j)
    local item = items[j]
    if item and item.joined and han(data, item) then return item end
    return nil
end

local function joined_prev(data, items, i)
    if not items[i].joined then return nil end
    local item = items[i - 1]
    if han(data, item) then return item end
    return nil
end

-- The next syllable's underlying tone.
local function next_tone(data, item, reading)
    local t = Sandhi.tone(reading)
    if t then return t end
    local _, default = data:char(item.text)
    return Sandhi.tone(default)
end

local function yi(data, items, i, match, next_reading)
    local nxt = joined_next(data, items, i + 1)
    if not nxt then return nil end
    local prev = joined_prev(data, items, i)
    local p, n = prev and prev.text, nxt.text
    -- Between two units (一万一千 yíwàn yìqiān) a quantity: the tone rules.
    if not (p and Sandhi.UNITS[p] and Sandhi.UNITS[n]) then
        if p and Sandhi.ORDINAL_PREV[p] then return nil end
        if Sandhi.DIGITS[n] or (p and Sandhi.DIGITS[p]) then return nil end
        if p and Sandhi.UNITS[p] then return nil end
        if p and Sandhi.FINAL_WORDS[p .. Sandhi.YI] then return nil end
        local pp = p and items[i - 1].joined and items[i - 2]
        if pp and Sandhi.FINAL_WORDS[pp.text .. p .. Sandhi.YI] then return nil end
    end
    if Sandhi.DATE_NEXT[n] then return nil end
    local after = items[i + 2]
    if Sandhi.ORDINAL_WORDS[Sandhi.YI .. n] then return nil end
    if after and after.joined and Sandhi.ORDINAL_WORDS[Sandhi.YI .. n .. after.text] then return nil end
    -- 看一看, but not the 一X一X of 一步一步 (yí bù yí bù) nor 数一数二.
    if p and p == n and not Sandhi.NOT_REDUP[p] then
        local before = items[i - 1].joined and items[i - 2]
        local beyond = joined_next(data, items, i + 2)
        if beyond and Sandhi.DIGITS[beyond.text] then return nil end   -- 数一数二: a numeral
        if not (before and before.text == Sandhi.YI) then return "yi", "yi-redup" end
    end
    local t = next_tone(data, nxt, next_reading(i + 1))
    if t == 4 then return "yí", "yi-4" end
    if t then return "yì", "yi-123" end
    return nil
end

local function bu(data, items, i, match, next_reading)
    local nxt = joined_next(data, items, i + 1)
    if not nxt or nxt.text == Sandhi.BU then return nil end   -- 不不: "no, no"
    local prev = joined_prev(data, items, i)
    -- A word that takes in the character before 不 decided its tone (决不,
    -- 好不容易): no neutral bu there. The V不C word itself (吃不了 chī bù
    -- liǎo in CC-CEDICT) does not count.
    local lexical = match and match.len and match.len > 1 and match.start < i
        and not (match.start == i - 1 and match.len == 3)
    -- 不 starts a fixed phrase (不得了, 不着边际): no A-不-A there.
    local nxt2 = joined_next(data, items, i + 2)
    local nxt3 = nxt2 and joined_next(data, items, i + 3)
    local phrase = nxt2 and (data:word(Sandhi.BU .. nxt.text .. nxt2.text)
        or (nxt3 and data:word(Sandhi.BU .. nxt.text .. nxt2.text .. nxt3.text)))
    if prev and not lexical and not phrase then
        -- 错不错, but not 不错不错 (bú cuò bú cuò).
        local before = items[i - 1].joined and items[i - 2]
        if prev.text == nxt.text and not (before and before.text == Sandhi.BU) then return "bu", "bu-aba" end
        -- AB不AB: 愿意不愿意.
        local prev2 = items[i - 1].joined and items[i - 2]
        if prev2 and nxt2 and han(data, prev2) and prev2.text == nxt.text and prev.text == nxt2.text then
            return "bu", "bu-aba"
        end
        -- 得不到 dé bu dào (得 is on Sandhi.NOT_VERBS as the particle de).
        if prev.text == "得" and nxt.text == "到" then return "bu", "bu-comp" end
        if nxt2 and Sandhi.DIRECTIONAL[nxt.text .. nxt2.text] and not Sandhi.NOT_VERBS[prev.text] then
            return "bu", "bu-comp"
        end
        -- 吃不了, 受不了, but not 不了解.
        if nxt.text == "了" then
            local after = joined_next(data, items, i + 2)
            if not (after and data:word("了" .. after.text)) then return "bu", "bu-liao" end
        end
        -- The potential form V得C must be a word: 看得见, 来得及, 说得出
        -- (V + C alone lets in 我见, 打成, 年过: 我不见它, 不打不成交).
        if Sandhi.COMPLEMENTS[nxt.text] and data:word(prev.text .. "得" .. nxt.text) then
            return "bu", "bu-comp"
        end
        -- Anything else that may be a verb and its complement (拿不到, 进不去,
        -- but also 远不到, 不住颤抖): without word classes it can't be told
        -- from a plain negation, so the dictionary's bù is drawn.
        if Sandhi.COMPLEMENTS[nxt.text] and not Sandhi.NOT_VERBS[prev.text] then return nil end
    end
    if next_tone(data, nxt, next_reading(i + 1)) == 4 then return "bú", "bu-4" end
    return nil
end

--[[--
The spoken reading of items[i] (一 or 不), or nil when it is the dictionary
reading `reading` (the resolver's, for this position). Second value: the
rule that changed it ("yi-4", "yi-123", "yi-redup", "bu-4", "bu-aba",
"bu-liao", "bu-comp"), for measuring.
  match         the word that decided `reading` (Resolve.reading's third
                value: { word=, start=, len= }), or nil
  next_reading  function(j): the resolver's reading of items[j], or nil
]]
function Sandhi.spoken(data, items, i, reading, match, next_reading)
    local ch = items[i] and items[i].text
    if ch == Sandhi.YI and reading == "yī" then return yi(data, items, i, match, next_reading) end
    if ch == Sandhi.BU and reading == "bù" then return bu(data, items, i, match, next_reading) end
    return nil
end

return Sandhi
