-- The sentence around a character tapped in a popup's own text
-- (ch_sentence.lua Sentence.inText): a nested popup's Translate text and
-- context line.
local Sentence = require("ch_sentence")
local Text = require("ch_text")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- The sentence when `char` (its n-th occurrence, default the first) is tapped in `text`.
local function at(text, char, n)
    local chars = Text.chars(text)
    n = n or 1
    for k, c in ipairs(chars) do
        if c == char then
            n = n - 1
            if n == 0 then
                local s = Sentence.inText(chars, k)
                return s and s.text
            end
        end
    end
    error("no " .. char .. " in " .. text)
end

-- An idiom's 出处 view, laid out like the 成語典's (the quotation is from
-- the 史记; the rest is written for this test).
local VIEW = table.concat({
    "释义",
    "形容犹豫不决的样子。语出《史记．卷一〇七．魏其武安侯列传》。",
    "",
    "典源　《史记．卷一〇七．魏其武安侯列传》",
    "武安已罢朝，出止车门，召韩御史大夫载，怒曰：「与长孺共一老秃翁，何为首鼠两端？」",
    "",
    "书证",
    "01.《史记．卷一〇七．魏其武安侯列传》：「武安已罢朝，出止车门，召韩御史大夫载，怒曰：『与长孺共一老秃翁，何为首鼠两端？』」",
}, "\n")

-- The citation, whole, brackets included: not the narrative around it.
eq(at(VIEW, "秃"), "「与长孺共一老秃翁，何为首鼠两端？」", "秃 in the 典源 citation")
eq(at(VIEW, "长"), "「与长孺共一老秃翁，何为首鼠两端？」", "长 in the same citation")
-- Outside the quote: the narrative sentence, with the quote kept whole.
eq(at(VIEW, "罢"), "武安已罢朝，出止车门，召韩御史大夫载，怒曰：「与长孺共一老秃翁，何为首鼠两端？」",
   "罢 before the quote")
-- Nested quotes in 书证: the outer citation, whole.
eq(at(VIEW, "秃", 2),
   "「武安已罢朝，出止车门，召韩御史大夫载，怒曰：『与长孺共一老秃翁，何为首鼠两端？』」",
   "秃 in the 书证 citation")
-- Plain definition prose: its own sentence, not the next one.
eq(at(VIEW, "犹"), "形容犹豫不决的样子。", "犹 in the definition")
-- ． inside a title does not end a sentence.
eq(at(VIEW, "语"), "语出《史记．卷一〇七．魏其武安侯列传》。", "语 after the definition")
-- A line with no end mark: the line.
eq(at(VIEW, "典"), "典源　《史记．卷一〇七．魏其武安侯列传》", "典源 heading line")

-- A MOE sense: the number goes, a quoted word is not a citation.
local SENSE = "1. 敲击、捶击、殴打。如：「打棒球」、「打铁趁热」。\n　唐．杜甫〈十二月一日〉诗三首之二：「打鼓发船何郡郎，新亭举目风景切。」"
eq(at(SENSE, "击"), "敲击、捶击、殴打。", "a sense's definition")
eq(at(SENSE, "棒"), "如：「打棒球」、「打铁趁热」。", "a quoted example word")
eq(at(SENSE, "鼓"), "「打鼓发船何郡郎，新亭举目风景切。」", "a quoted line of verse")
eq(at(SENSE, "杜"), "唐．杜甫〈十二月一日〉诗三首之二：「打鼓发船何郡郎，新亭举目风景切。」",
   "the quotation's source: the whole line, indent dropped")

-- ；！？ end sentences; a closing quote after an end mark belongs to it.
eq(at("他说：「好。」我们走吧！你来吗？", "们"), "我们走吧！", "after 。」")
eq(at("他说：「好。」我们走吧！你来吗？", "他"), "他说：「好。」", "speech ending in 。」")
eq(at("甲乙；丙丁。", "丙"), "丙丁。", "；")
-- An unclosed quote does not swallow the rest.
eq(at("他说：「好吗。我们走", "们"), "我们走", "unclosed quote")
-- A citation longer than QUOTE_MAX: the sentence inside it.
local long = "曰：「" .. string.rep("天", 70) .. "。" .. string.rep("地", 60) .. "人。」"
eq(at(long, "人"), string.rep("地", 60) .. "人。", "inside a long citation")
-- A line break is not a character.
eq(Sentence.inText(Text.chars("甲\n乙"), 2), nil, "line break")

-- Latin letters inside MOE's text do not cut the sentence.
eq(at("量词。计算物品的单位。为英文dozen的音译。十二个为一打。", "译"), "为英文dozen的音译。", "Latin inside")
