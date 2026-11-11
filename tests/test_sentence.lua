-- The sentence around a tapped character (ch_sentence.lua), against the fake
-- CreDocument (tests/fake_credoc.lua): text, and positions that read back as
-- the same text.
local Text = require("ch_text")
local Sentence = require("ch_sentence")
local Fake = require("fake_credoc")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- The n-th occurrence (default 1) of `char` in paragraph p, as a hit.
local function hitOf(doc, paras, p, char, nth)
    local seen = 0
    for i, c in ipairs(Text.chars(paras[p])) do
        if c == char then
            seen = seen + 1
            if seen == (nth or 1) then return doc:hit(p, i) end
        end
    end
    error("no " .. char .. " in paragraph " .. p)
end

local function sentence(paras, p, char, opts)
    opts = opts or {}
    local doc = Fake.fakeDoc(paras, opts.per_line or 20)
    doc.lines_per_page = opts.lines_per_page
    local s = Sentence.find(doc, hitOf(doc, paras, p, char, opts.nth), opts.max)
    assert(s, "no sentence")
    assert(s.pos0 and s.pos1, "no positions for " .. s.text)
    eq(doc:getTextFromXPointers(s.pos0, s.pos1):gsub("^%s+", ""):gsub("%s+$", ""), s.text,
        "positions read back as the text")
    return s, doc
end

local function text(...) return (sentence(...)).text end

-- 1. Ends in 。 followed by ”: the closer belongs to the sentence.
local P = { "他说：“今天下雨了。”我们回家吧。" }
eq(text(P, 1, "雨"), "他说：“今天下雨了。”", "。 then ”")
eq(text(P, 1, "回"), "我们回家吧。", "starts after 。”")

-- 2. A sentence starting at the paragraph start (no end mark in the
-- previous paragraph's last characters counts).
P = { "上一段没有句号", "第二段开头的句子在这里。后面还有一句。" }
eq(text(P, 2, "句"), "第二段开头的句子在这里。", "paragraph start")
eq(text(P, 2, "第"), "第二段开头的句子在这里。", "tapped first character")
eq(text(P, 2, "里"), "第二段开头的句子在这里。", "tapped last character before 。")

-- 3. Backward stops at the previous 。.
P = { "第一句话。第二句话很长。第三句。" }
eq(text(P, 1, "很"), "第二句话很长。", "back to the previous 。")
eq(text(P, 1, "第", { nth = 2 }), "第二句话很长。", "first character after 。")

-- 4. ？ (and a run of end marks and closers).
P = { "你今天去哪里了？我去了公园。", "“真的吗？！”她问。" }
eq(text(P, 1, "哪"), "你今天去哪里了？", "？")
eq(text(P, 1, "公"), "我去了公园。", "after ？")
eq(text(P, 2, "真"), "“真的吗？！”", "？！” taken whole")
eq(text(P, 2, "她"), "她问。", "after ？！”")

-- 5. Mixed Chinese and English with a period.
P = { "他说 Hello world. 然后就走了。圆周率是3.14左右。他说 OK." }
eq(text(P, 1, "他"), "他说 Hello world.", "Latin period before a space")
eq(text(P, 1, "然"), "然后就走了。", "after '. ', leading space trimmed")
eq(text(P, 1, "周"), "圆周率是3.14左右。", "3.14 does not end a sentence")
eq(text(P, 1, "他", { nth = 2 }), "他说 OK.", "Latin period at the paragraph end")

-- 6. A paragraph with no end mark: the paragraph is the sentence.
P = { "前一段。", "没有句号的段落", "下一段。" }
eq(text(P, 2, "号"), "没有句号的段落", "no end mark")

-- 7. A sentence that continues onto the next page (5 characters a line,
-- 2 lines a page): the walk follows the document, not the page.
P = { "上一句。这是一个很长的句子它会一直延续到下一页才结束。下一句。" }
local s, doc = sentence(P, 1, "这", { per_line = 5, lines_per_page = 2 })
eq(s.text, "这是一个很长的句子它会一直延续到下一页才结束。", "across pages")
assert(doc:getPageFromXPointer(s.pos1) > doc:getPageFromXPointer(s.pos0) + 1, "spans pages")
s = sentence(P, 1, "束", { per_line = 5, lines_per_page = 2 })
eq(s.text, "这是一个很长的句子它会一直延续到下一页才结束。", "back across pages")

-- Leading and trailing whitespace trimmed.
P = { "  前面有空格的句子  " }
eq(text(P, 1, "空"), "前面有空格的句子", "trimmed")

-- 8. The 200-character cap.
local han = {}
local pool = Text.chars("一二三四五六七八九十")
for i = 1, 400 do han[i] = pool[(i - 1) % #pool + 1] end
local long = table.concat(han) .. "。"
-- Tapped in the middle: 99 characters before, 100 after.
s = sentence({ long }, 1, "一", { nth = 21 })      -- the 201st character
eq(#Text.chars(s.text), 200, "capped at 200")
assert(s.capped, "capped flag")
eq(s.text, table.concat(han, "", 102, 301), "centred on the tapped character")
-- Tapped near the start: the rest of the budget goes after it.
s = sentence({ long }, 1, "一", { nth = 2 })       -- the 11th character
eq(s.text, table.concat(han, "", 1, 200), "window shifted to the right")
-- Short sentences are not capped.
s = sentence({ "短句。" }, 1, "短")
assert(not s.capped, "not capped")
-- With clause marks: each cut end moves to a ， in its outer quarter.
-- 20 clauses of 20 characters (19 of one character, then ，), all different.
local stems = Text.chars("甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉")
local parts = {}
for i = 1, 20 do parts[i] = string.rep(stems[i], 19) .. "，" end
local clauses = table.concat(parts) .. "完。"
s = sentence({ clauses }, 1, "子")                  -- the 201st character
local chars = Text.chars(s.text)
assert(#chars <= 200 and #chars >= 150, "near the cap: " .. #chars)
eq(chars[#chars], "，", "ends with a clause mark")
local before = clauses:sub(1, clauses:find(s.text, 1, true) - 1)
assert(#before > 0, "cut at the start")
eq(Text.chars(before)[#Text.chars(before)], "，", "starts just after a clause mark")

-- Pure cuts.
eq(select(2, Sentence.forwardCut(Text.chars("了。"), false)), false, "end mark last: need more")
eq(Sentence.forwardCut(Text.chars("了。x"), false), 2, "end mark then more")
eq(select(2, Sentence.forwardCut(Text.chars("world."), false)), false, "Latin period last: need more")
eq(Sentence.backwardCut(Text.chars("。”他"), false, "说"), 1, "after 。”")
eq(select(2, Sentence.backwardCut(Text.chars("没有"), false, "说")), false, "no boundary: need more")
