-- Spoken tones of 一 and 不 (#37, ch_sandhi.lua): the rules through
-- Resolve.annotate against the real database, the setting, the marks and the
-- popup's note.
local Resolve = require("ch_resolve")
local Sandhi = require("ch_sandhi")
local Settings = require("ch_settings")
local Marks = require("ch_marks")
local Model = require("ch_popup_model")
local H = require("sq3_shim")
local eq = H.eq

local data = H.readings()

-- Engine-like items: one per Han character; anything else breaks the
-- "joined" chain (punctuation, Latin, digits, spaces).
local function items_of(text)
    local items, joined = {}, false
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if Resolve.single_char(ch) and not ch:match("^\227\128") and not ch:match("^\239\188") then
            items[#items + 1] = { text = ch, joined = joined }
            joined = true
        else
            joined = false
        end
    end
    return items
end

-- The readings drawn above every 一 and 不 in `text` (learner mode), in order.
local function spoken(text, opts)
    opts = opts or {}
    local items = items_of(text)
    local out = {}
    local on = opts.spoken
    if on == nil then on = true end
    for _, a in ipairs(Resolve.annotate(data, items, opts.threshold or 0, "best", nil, opts.marks, on)) do
        local ch = items[a.index].text
        if ch == "一" or ch == "不" then out[#out + 1] = a.reading end
    end
    return table.concat(out, " ")
end

local function check(text, expected)
    eq(spoken(text), expected, text)
end

-- Tone helper.
eq(Sandhi.tone("shì"), 4); eq(Sandhi.tone("tiān"), 1); eq(Sandhi.tone("ge"), nil)
eq(Sandhi.tone("chéng/shèng"), 2); eq(Sandhi.tone("lǜ"), 4); eq(Sandhi.tone(nil), nil)

-- 不: bú before a fourth tone, bù otherwise.
check("不是", "bú"); check("不过", "bú"); check("不要", "bú"); check("不客气", "bú")
check("不好", "bù"); check("不来", "bù"); check("不知道", "bù")
-- Neutral bu: A-不-A, verb + complement; a dictionary bu stays.
check("是不是", "bu"); check("好不好", "bu"); check("去不去", "bu")
check("看不见", "bu"); check("来不及", "bu"); check("吃不了", "bu"); check("说不出话", "bu")
check("对不起", "bu")
-- ... but not 不了解, nor a word that takes in the character before 不.
check("我不了解", "bù"); check("好不容易", "bù")
check("一动不动", "yí bú")

-- 一: yí before a fourth tone, yì before the others; a neutral next syllable
-- counts by its character's tone (个 ge -> gè).
check("一个", "yí"); check("一样", "yí"); check("一定", "yí"); check("一下", "yí")
check("一天", "yì"); check("一年", "yì"); check("一起", "yì"); check("一点", "yì")
-- Numbers and ordinals stay yī.
check("第一", "yī"); check("初一", "yī"); check("十一", "yī"); check("二十一", "yī")
check("一九九八年", "yī"); check("一月", "yī"); check("一号", "yī"); check("一等奖", "yī")
check("统一了", "yī"); check("唯一的", "yī"); check("万一他来", "yī"); check("之一是", "yī")
check("一一对应", "yī yī")
-- Before 百, 千, 万 a quantity; between two units too.
check("一百", "yì"); check("一千", "yì"); check("一万", "yí")
check("一万一千", "yí yì"); check("三百一十", "yī")
-- Reduplicated verbs: neutral yi; but 一X一X changes as usual.
check("看一看", "yi"); check("想一想", "yi")
check("一步一步", "yí yí")
-- Prefix words that end in 一 still change (刚一进门, 另一个).
check("刚一进门", "yí"); check("另一个", "yí"); check("不一定", "bù yí")

-- Alone, before punctuation, at a line end, before a non-Han character.
check("一", "yī"); check("不", "bù")
check("一。", "yī"); check("不，", "bù"); check("说不", "bù")
check("一Kg", "yī"); check("不OK", "bù"); check("一 个", "yī")

-- The setting off: dictionary tones.
eq(spoken("一个不是", { spoken = false }), "yī bù")

-- Settings: three values x learner mode on/off.
local function store(values)
    local s = { values = values or {} }
    function s:readSetting(k) return self.values[k] end
    function s:saveSetting(k, v) self.values[k] = v end
    return s
end
local s = Settings.new(store())
eq(s:spokenTonesMode(), "learner", "default: in learner mode")
for _, case in ipairs({
    { "learner", 0, true }, { "learner", 3500, false },
    { "always", 0, true }, { "always", 3500, true },
    { "never", 0, false }, { "never", 3500, false },
    { "odd", 0, true }, { "odd", 3500, false },
}) do
    s = Settings.new(store{ chinesehelper_spoken_tones = case[1], chinesehelper_threshold = case[2] })
    eq(s:spokenTones(), case[3], case[1] .. " at " .. case[2])
end
eq(Sandhi.enabled("learner", 0), true); eq(Sandhi.enabled("learner", 500), false)
eq(Sandhi.enabled("always", 3500), true); eq(Sandhi.enabled("never", 0), false)

-- Marks stay keyed on the dictionary reading: known bù hides bú and bu.
local function marks(list)
    local st = { read = function() return {}, false end, write = function() return true end, setAside = function() end }
    local m = Marks.new{ store = st }
    for _, e in ipairs(list) do m:set(e[1], e[2], e[3]) end
    return m
end
local known_bu = marks{ { "不", "bù", "known" } }
eq(spoken("不是看不见不好", { marks = known_bu }), "bu", "known bù: bú and bù hidden, the dictionary's bu stays")
-- Remind-me 不 at 3,500 with Always: the spoken form is drawn.
local remind_bu = marks{ { "不", "bù", "remind" } }
eq(spoken("不是不好", { threshold = 3500, marks = remind_bu }), "bú bù")
eq(spoken("不是不好", { threshold = 3500, marks = remind_bu, spoken = false }), "bù bù")
-- A known neighbour does not change the rule: 个 known, 一个 still yí.
local known_ge = marks{ { "个", "gè", "known" } }
eq(spoken("一个", { marks = known_ge }), "yí")

-- annotate's `dict`: the dictionary reading behind a spoken one.
do
    local items = items_of("不是")
    local a = Resolve.annotate(data, items, 0, "best", nil, nil, true)[1]
    eq(a.reading, "bú"); eq(a.dict, "bù"); eq(a.sandhi, "bu-4")
    a = Resolve.annotate(data, items_of("不好"), 0, "best", nil, nil, true)[1]
    eq(a.reading, "bù"); eq(a.dict, nil)
end

-- The popup's note, on the character's own block next to the rank.
do
    local blocks = { { lines = {} }, { lines = {} } }
    local matches = { { len = 1 }, { len = 2 } }
    Model.markRank(blocks, matches, "字频 5")
    eq(Model.markSpoken(blocks, matches, "bú"), true)
    eq(Model.labelText(blocks[1], false), "字频 5 · spoken here: bú")
    eq(Model.labelText(blocks[2], false), nil)
    blocks = { { lines = {} } }
    eq(Model.markSpoken(blocks, matches, nil), false)
    eq(blocks[1].spoken, nil)
    eq(Model.markSpoken({ {} }, { { len = 2 } }, "bú"), false, "only on the character's own entry")
end

-- From the corpus judging: 不不 stays bù bù; 我不见它 and 不打不成交 are plain
-- negations (bú before 见); 数一数二 keeps yī.
check("不不", "bù bù"); check("我不见它", "bú"); check("不打不成交", "bù bù")
check("数一数二", "yī")

-- Second round: X一X only for verbs; AB不AB; directional and common
-- complements.
check("明年一年做到", "yì"); check("四个人一人对付", "yì"); check("在旁边一边整理", "yì")
check("愿意不愿意", "bu"); check("拿不过来", "bu"); check("想不起来", "bu")
check("扩不动", "bu"); check("做不到", "bu"); check("轮不到", "bu")
check("他不动", "bú"); check("也不到", "bú")
