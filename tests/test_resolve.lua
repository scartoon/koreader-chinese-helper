-- Offline tests for the character/word tables and reading logic.
-- Run with:  python3 tests/run.py   (needs `pip install lupa`)

-- (data: the plugin database, loaded as the plugin loads it)
local Resolve = require("ch_resolve")

local data = require("sq3_shim").readings()

-- Turn a string into engine-like items: one item per Han character;
-- punctuation and spaces are not items but break the "joined" chain,
-- as they do in the rendering engine. "|" marks the page start/end.
local function items_of(text)
    local items, joined, on_page = {}, false, true
    if text:find("|", 1, true) then on_page = false end
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if ch == "|" then
            on_page = not on_page
            -- a page boundary does not break a word
        elseif Resolve.single_char(ch) and not ch:match("^[\227][\128][\128-\191]$") and ch ~= "，" and ch ~= "。" and ch ~= "！" and ch ~= "？" and ch ~= "；" and ch ~= "：" then
            items[#items + 1] = { text = ch, joined = joined, on_page = on_page }
            joined = true
        else
            joined = false
        end
    end
    return items
end

local function readings(text, threshold)
    local items = items_of(text)
    local out = {}
    for _, a in ipairs(Resolve.annotate(data, items, threshold or 3500)) do
        out[#out + 1] = items[a.index].text .. "=" .. a.reading
    end
    return table.concat(out, " ")
end

-- Parsing must not depend on the locale: "à" ends in byte 0xA0, which some
-- C locales treat as a space.
do
    local syllables, freq = data:word("大宛")
    assert(syllables and #syllables == 2 and syllables[1] == "dà" and syllables[2] == "yuān",
        "大宛 parsed as " .. table.concat(syllables or {}, "|"))
    assert(freq and freq > 0, "大宛 has no frequency")
    syllables = data:word("刨子")
    assert(syllables and #syllables == 2 and syllables[1] == "bào", "刨子 parsed wrongly")
end

local failures, passed = 0, 0
local function expect(text, threshold, want)
    local got = readings(text, threshold)
    if got == want then
        passed = passed + 1
    else
        failures = failures + 1
        print(("FAIL  %s  (threshold %d)\n      want: %s\n      got:  %s"):format(text, threshold, want, got))
    end
end

-- Rare monophonic characters: default reading.
expect("饕餮之徒", 3500, "饕=tāo 餮=tiè")
expect("踟蹰不前", 3500, "踟=chí 蹰=chú")
expect("踟躕不前", 3500, "踟=chí 躕=chú")            -- traditional
expect("岁月蹉跎", 3500, "蹉=cuō 跎=tuó")

-- Polyphonic rare characters resolved by the word around them.
expect("他侥幸逃脱了", 3500, "侥=jiǎo")
expect("僬侥之国", 3500, "僬=jiāo 侥=yáo")
expect("莞尔一笑", 2500, "莞=wǎn")
expect("他住在东莞", 2500, "莞=guǎn")
expect("吐蕃王朝", 2500, "蕃=bō")
expect("刨根问底", 3500, "刨=páo")
expect("用刨子刨平", 3500, "刨=bào")                 -- second 刨, same reading: not repeated

-- Once per page: a repeated character is annotated only the first time,
-- unless it has a different reading the second time.
expect("饕餮之徒，饕餮之徒", 3500, "饕=tāo 餮=tiè")
expect("刨根问底，用刨子", 3500, "刨=páo 刨=bào")
expect("刨根问底，用刨子，刨根", 3500, "刨=páo 刨=bào")
-- Only on-page occurrences count: one in the context before the page does not
-- stop the first on-page one from being annotated.
expect("饕|饕餮|", 3500, "饕=tāo 餮=tiè")

-- Overlapping words of the same length: the more frequent one wins
-- (宛如 over 大宛), not the leftmost.
expect("声音很大宛如雷鸣", 2500, "宛=wǎn")
expect("张骞出使大宛", 2500, "骞=qiān 宛=yuān")

-- A neutral tone CC-CEDICT gives a word only that way is drawn as it is (刺猬
-- cì wei; pypinyin's cì wèi does not override it), in any position after the
-- first (大猩猩 dà xīng xing, 唠唠叨叨 láo lao dāo dāo): the standard spoken
-- form. 猩 twice on a page: two readings, so both are drawn.
expect("一只刺猬", 3500, "猬=wei")
expect("一只大猩猩", 2500, "猩=xīng 猩=xing")
expect("他唠唠叨叨", 3500, "唠=láo 唠=lao")
-- Words added only for their neutral tone (鼓捣: 捣 has the one reading dǎo,
-- so no word was kept for it before).
expect("总能鼓捣回家点儿", 2500, "捣=dao")
expect("总能鼓捣回家点儿", 3500, "")              -- 捣 ranks 2,655
expect("捣乱", 2500, "捣=dǎo")                     -- outside such a word: its own tone
expect("刺猬和猬", 3500, "猬=wei 猬=wèi")
-- CC-CEDICT lists both readings (大爷 dà yé / dà ye, 裁缝 cái féng / cái
-- feng): the toned one is drawn (the popup marks the neutral; word_marks).
expect("她是裁缝", 1500, "缝=féng")
assert(table.concat(data:word("鼓捣"), " ") == "gǔ dao", "鼓捣 in the words table")
assert(table.concat(data:word("唠唠叨叨"), " ") == "láo lao dāo dāo", "唠唠叨叨")

-- Words from pypinyin's phrase list that CC-CEDICT lacks or reads differently.
expect("澹台灭明", 3500, "澹=tán")

-- Hand-checked overrides (tools/overrides.tsv).
expect("食不下咽", 2500, "咽=yàn")
expect("温庭筠的词", 3500, "筠=yún")            -- default reading corrected
expect("筠连县", 3500, "筠=jūn")                 -- the place name keeps jūn
expect("以门荫为官", 2500, "荫=yìn")
expect("林荫大道", 2500, "荫=yīn")

-- Default readings corrected from the CPP train split (tools/overrides.tsv).
expect("李晟是唐朝名将", 3500, "晟=shèng")
expect("吃文蛤", 2500, "蛤=gé")
expect("一只癞蛤蟆", 2500, "癞=lài 蛤=há 蟆=ma")   -- the word keeps há; 蟆 neutral
expect("盐谷町", 2500, "町=tǐng")
expect("姓翟的人", 3500, "翟=zhái")
-- Word fixes from the train review.
expect("脯氨酸", 2500, "脯=fǔ 氨=ān")
expect("树枝分杈", 3500, "杈=chà")
-- Context rule learned from train (幢 after a numeral), and the pair shown
-- for 幢 when nothing decides.
expect("一幢房子", 2500, "幢=zhuàng")
expect("那幢", 2500, "幢=zhuàng")                -- hand-checked default, train agrees
-- Uncertain characters: both readings, most likely first.
expect("姓覃", 3500, "覃=qín/tán")
expect("叫鸣镝", 3500, "镝=dí")                 -- word (overrides.tsv); 镝 alone is a pair

-- Resolution order and the three "uncertain" modes, on made-up data.
do
    local fake = setmetatable({
        chars = { ["甲"] = { 3000, "a1" } },
        words = { ["丁甲"] = { "x", "w1" } }, word_freq = {},
        rules = { ["甲"] = { ["L乙"] = { "l2", 5 }, ["R丙"] = { "r3", 9 } } },
        uncertain = { ["甲"] = { 0.4, "b2", "a1" } },
        max_word_len = 2,
    }, getmetatable(data))
    local function items(text)
        local t = {}
        for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            t[#t + 1] = { text = ch, joined = #t > 0, on_page = true }
        end
        return t
    end
    local function at(text, mode)
        local list = items(text)
        for i, it in ipairs(list) do
            if it.text == "甲" then return (Resolve.reading(fake, list, i, mode)) end
        end
    end
    assert(at("甲", "both") == "b2/a1", "pair, most likely first")
    assert(at("甲", "best") == "b2", "best guess is the most likely reading")
    assert(at("甲", "skip") == nil, "skip leaves it bare")
    assert(at("甲") == "b2/a1", "default mode is both")
    assert(at("乙甲", "both") == "l2", "left rule beats uncertainty")
    assert(at("甲丙", "skip") == "r3", "right rule")
    assert(at("乙甲丙") == "r3", "rules disagree: more examples wins")
    assert(at("丁甲") == "w1", "a dictionary word beats a rule")
    local split = items("乙甲")
    split[2].joined = false   -- punctuation in between
    assert(Resolve.reading(fake, split, 2, "best") == "b2", "rules need a joined neighbour")
end

-- Punctuation breaks a word: 侥。幸 must not match 侥幸.
expect("僬侥。幸", 3500, "僬=jiāo 侥=yáo")

-- Common text: nothing at the default threshold.
expect("臣闻求木之长者，必固其根本", 3500, "")

-- Threshold: 莞 (rank ~2700) appears only when the threshold is below it.
expect("莞尔一笑", 3500, "")

-- Page boundary: context outside the page resolves the word but is not annotated.
expect("他侥|幸逃脱|", 3500, "")
expect("僬|侥之国|", 3500, "侥=yáo")

-- Fallback dictionaries' words (Resolve.fallback_reading), on small
-- hand-made tables: what decides, in which order, and what is skipped.
do
    local Readings = require("ch_readings")
    local fb = Readings.new()
    for ch, r in pairs({ ["累"] = "lěi", ["世"] = "shì", ["公"] = "gōng", ["卿"] = "qīng", ["积"] = "jī",
                         ["甲"] = "jiǎ", ["乙"] = "yǐ", ["丙"] = "bǐng", ["丁"] = "dīng" }) do
        fb:addChar(ch, 3000, r)
    end
    fb:addUncertain("累", 0.7, "lěi", "léi")
    fb:addWord("积累", "jī lěi", 100)
    fb:addChar("官", 500, "guān"); fb:addRule("累", "R", "官", "lèi", 9)
    local rows = {
        { simp = "累世", trad = "累世", pinyin = "lěishì", source = "wikt" },
        -- MOE's row for a word Wiktionary has is never used (one source per word).
        { simp = "累世", trad = "累世", pinyin = "lèi shì", source = "moe" },
        { simp = "甲累", trad = "甲累", pinyin = "jiǎléi", source = "wikt" },
        { simp = "甲累", trad = "甲累", pinyin = "jiǎlèi", source = "wikt" },  -- two readings of 累
        { simp = "累乙", trad = "累乙", pinyin = "léiyǐ", source = "wikt" },
        { simp = "丙累", trad = "丙累", pinyin = "bǐnglèi", source = "wikt" },
        { simp = "累丁", trad = "累丁", pinyin = "léidīng", source = "wikt" },
        { simp = "丙累丁", trad = "丙累丁", pinyin = "bǐng lei dīng", source = "wikt" },  -- toneless
        { simp = "积累世", trad = "積累世", pinyin = "jīlèishì", source = "wikt" },
        { simp = "累官", trad = "累官", pinyin = "léiguān", source = "wikt" },
        { simp = "公累", trad = "公累", pinyin = "gōnglèi", source = "wikt" },
        { simp = "世甲", trad = "世甲", pinyin = "shìjià", source = "wikt" },
    }
    local queries = 0
    fb:setFallback(function(list)
        queries = queries + 1
        local want, out = {}, {}
        for _, w in ipairs(list) do want[w] = true end
        for _, r in ipairs(rows) do if want[r.simp] then out[#out + 1] = r end end
        return out
    end, "wikt,moe")
    local function at(text, ch)
        local items = items_of(text)
        for i, item in ipairs(items) do
            if item.text == ch then
                local reading, _, match = Resolve.reading(fb, items, i)
                return reading .. (match and (" " .. match.word .. (match.fallback and ":" .. match.fallback or ""))
                    or "")
            end
        end
    end
    local function check(got, want, what)
        if got == want then passed = passed + 1 else
            failures = failures + 1
            print(("FAIL  %s: expected %s, got %s"):format(what, want, tostring(got)))
        end
    end
    check(at("累世公卿", "累"), "lěi 累世:wikt", "a fallback word decides")
    check(at("甲累", "累"), "lěi/léi", "a word giving the character two readings is skipped")
    check(at("甲累乙", "累"), "léi 累乙:wikt", "...and the next word used")
    check(at("丙累丁", "累"), "lěi/léi", "same length, different readings: nothing decided")
    check(at("积累世", "累"), "lěi 积累", "a CC-CEDICT word beats a longer fallback word")
    check(at("累官", "累"), "lèi", "a context rule beats a fallback word")
    check(at("公累", "累"), "lěi/léi", "a reading outside the uncertain pair is not taken")
    check(at("世甲", "甲"), "jiǎ", "a character with a reliable default: fallback words not used")
    fb:setFallback(nil)
    check(at("累世公卿", "累"), "lěi/léi", "fallback dictionaries off: the pair")
    -- Page annotation: the fallback words of a page come in one lookup, and
    -- only for characters no other word decides.
    fb:setFallback(fb.fallback or function(list)
        queries = queries + 1
        local want, out = {}, {}
        for _, w in ipairs(list) do want[w] = true end
        for _, r in ipairs(rows) do if want[r.simp] then out[#out + 1] = r end end
        return out
    end, "wikt")
    queries = 0
    local items = items_of("累世公卿，甲累乙，积累世，世甲")
    local got = {}
    for _, a in ipairs(Resolve.annotate(fb, items, 1000)) do got[#got + 1] = items[a.index].text .. "=" .. a.reading end
    check(table.concat(got, " "), "累=lěi 世=shì 公=gōng 卿=qīng 甲=jiǎ 累=léi 乙=yǐ 积=jī", "annotate")
    check(fb.fb_cache["世甲"], nil, "only the uncertain characters' words are looked up")
    check(queries, 1, "one fallback lookup for the page")
    for _, a in ipairs(Resolve.annotate(fb, items, 1000)) do end
    check(queries, 1, "cached: none for the same page again")
    -- Switching sources empties the cache.
    fb:setFallback(fb.fallback, "moe")
    check(fb.fb_cached, 0, "cache emptied when the sources change")
    -- A special word still wins (see test_special.lua for the real table).
    local special = Readings.newSpecial()
    Readings.addSpecial(special, "累世", "léi shì", "10", 1, "a test")
    local sitems = items_of("累世公卿")
    check((Resolve.reading(fb, sitems, 1, nil, special)), "léi", "a special word beats a fallback word")
end

print(("%d passed, %d failed"):format(passed, failures))
if failures > 0 then error("tests failed") end
