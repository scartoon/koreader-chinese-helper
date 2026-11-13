-- Han detection, context trimming, candidate generation, button rows (ch_text.lua).
local Text = require("ch_text")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function chars(s) return Text.chars(s) end
local function join(list, key, sep)
    local out = {}
    for _, x in ipairs(list) do out[#out + 1] = key and x[key] or x end
    return table.concat(out, sep or ",")
end

------------------------------------------------------------------------
-- Han detection
------------------------------------------------------------------------
for _, c in ipairs({ "中", "国", "饕", "㐀", "䶿", "𠀀", "𪜀", "𰀀", "豈", "丽" }) do
    assert(Text.isHan(c), "should be Han: " .. c)
end
-- 丽 above is U+4E3D; the compatibility supplement U+2F800 is "丽" too:
assert(Text.isHan("\240\175\160\128"), "U+2F800 compatibility supplement")
assert(Text.isHan("〇"), "〇 (U+3007) is read as a character")
for _, c in ipairs({ "，", "。", "“", "a", "Z", "1", "１", " ", "\n", "ー", "あ", "한", "", "中国" }) do
    assert(not Text.isHan(c), "should not be Han: [" .. c .. "]")
end
assert(not Text.isHan("\228\184"), "truncated UTF-8")
assert(not Text.isHan(nil))

------------------------------------------------------------------------
-- Context trimming
------------------------------------------------------------------------
eq(table.concat(Text.hanSuffix("他说：这个历史", 7)), "这个历史", "suffix stops at punctuation")
eq(table.concat(Text.hanSuffix("一二三四五六七八九", 7)), "三四五六七八九", "suffix capped at 7")
eq(table.concat(Text.hanSuffix("第一章\n这个", 7)), "这个", "suffix stops at paragraph break")
eq(table.concat(Text.hanSuffix("in 2008年", 7)), "年", "suffix stops at digits")
eq(table.concat(Text.hanPrefix("靠谱，真的", 7)), "靠谱", "prefix stops at punctuation")
eq(table.concat(Text.hanPrefix("一二三四五六七八九", 7)), "一二三四五六七", "prefix capped at 7")
eq(table.concat(Text.hanPrefix(" 中国", 7)), "", "prefix stops at a leading space")
eq(#Text.hanPrefix("", 7), 0)

------------------------------------------------------------------------
-- Candidates
------------------------------------------------------------------------
-- 历 tapped in 这个[历]史挺靠谱
local cands, texts = Text.candidates(chars("这个"), "历", chars("史挺靠谱"))
-- Every substring containing position 3, length <= 8: starts 1..3, ends 3..7.
eq(#cands, 3 * 5, "candidate count")
eq(#texts, #cands)
local by_text = {}
for _, c in ipairs(cands) do by_text[c.text] = c end
assert(by_text["历"] and by_text["历"].start == 0 and by_text["历"].len == 1)
assert(by_text["历史"] and by_text["历史"].start == 0 and by_text["历史"].len == 2)
assert(by_text["个历"] and by_text["个历"].start == -1)
assert(by_text["这个历史挺靠谱"] and by_text["这个历史挺靠谱"].len == 7)
assert(not by_text["这个"], "must contain the tapped character")
assert(not by_text["靠谱"], "must contain the tapped character")

-- Full context: 7 + 1 + 7 characters, words up to 8.
local left, right = chars("一二三四五六七"), chars("九十百千万亿兆")
cands = Text.candidates(left, "八", right)
local count, maxlen = 0, 0
for len = 1, 8 do count = count + len end   -- a window of length len has len positions containing t
eq(#cands, count, "7+1+7 candidate count")
for _, c in ipairs(cands) do
    if c.len > maxlen then maxlen = c.len end
    assert(c.start <= 0 and c.start + c.len - 1 >= 0, "contains tapped char: " .. c.text)
end
eq(maxlen, 8, "longest candidate")

-- No context: only the character itself.
cands = Text.candidates({}, "中", {})
eq(#cands, 1); eq(cands[1].text, "中")

-- Repeated strings appear once, with the earliest start: 天[天]天
cands = Text.candidates(chars("天"), "天", chars("天"))
local seen = {}
for _, c in ipairs(cands) do
    assert(not seen[c.text], "duplicate " .. c.text)
    seen[c.text] = c
end
eq(seen["天天"].start, -1, "earliest start kept")
eq(#cands, 3, "天, 天天, 天天天")

------------------------------------------------------------------------
-- Button rows
------------------------------------------------------------------------
local items = {}
for k = 1, 9 do items[k] = k end
local r = Text.rows(items, 4)
eq(#r, 3); eq(#r[1], 4); eq(#r[3], 1); eq(r[3][1], 9)
eq(#Text.rows({}, 4), 0)

