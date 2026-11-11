-- Tap -> character and neighbours (ch_context.lua), against a fake CreDocument.
--
-- The fake document is tests/fake_credoc.lua.
local Text = require("ch_text")
local Context = require("ch_context")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local Fake = require("fake_credoc")
local fakeDoc = Fake.fakeDoc
local CW, LH, TH, X0 = Fake.CW, Fake.LH, Fake.TH, Fake.X0

local function tapAt(doc, line, col, dy)
    return { x = X0 + col * CW + CW / 2, y = line * LH + (dy or LH / 2) }
end

local function around(doc, pos)
    local hit = Context.charAt(doc, pos, TH)
    if not hit then return nil end
    local l, r = Context.around(doc, hit)
    return hit.char, table.concat(l), table.concat(r)
end

-- One paragraph across lines (5 per line): 他说，这个历 / 史挺靠谱的书 / ，Hello中文。
local doc = fakeDoc({ "他说，这个历史挺靠谱的书，Hello中文。", "第二段开头" }, 5)

-- 历 is line 1 col 0 (他说，这个 / 历史挺靠谱 / ...)
local c, l, r = around(doc, tapAt(doc, 1, 0))
eq(c, "历"); eq(l, "这个", "left across the line break, stops at ，"); eq(r, "史挺靠谱的书", "right stops at ，")

-- Character at the end of a line: right side continues on the next line.
c, l, r = around(doc, tapAt(doc, 0, 4))
eq(c, "个"); eq(l, "这"); eq(r, "历史挺靠谱的书", "7 to the right, across the line")

-- Context capped at 7 each way.
local long = fakeDoc({ "一二三四五六七八九十百千万亿兆京" }, 20)
c, l, r = around(long, tapAt(long, 0, 8))
eq(c, "九"); eq(l, "二三四五六七八"); eq(r, "十百千万亿兆京")

-- Paragraph break stops the walk: 第 starts paragraph 2, 。 ends paragraph 1.
-- Paragraph 1 has 21 characters: lines 0..4, so paragraph 2 is on line 5.
c, l, r = around(doc, tapAt(doc, 5, 0))
eq(c, "第"); eq(l, "", "nothing from the previous paragraph"); eq(r, "二段开头")
local para = fakeDoc({ "前文", "后文" }, 10)
c, l, r = around(para, tapAt(para, 0, 1))
eq(c, "文"); eq(l, "前"); eq(r, "", "paragraph break on the right")

-- Taps that must pass through:
-- punctuation (，is line 0 col 2)
assert(not Context.charAt(doc, tapAt(doc, 0, 2), TH), "punctuation")
-- Latin (H is line 2 col 3: 的书，He / llo中文 ...)
assert(not Context.charAt(doc, tapAt(doc, 2, 3), TH), "Latin")
-- left margin, next to a character
assert(not Context.charAt(doc, { x = 20, y = LH + 50 }, TH), "left margin")
-- right margin
assert(not Context.charAt(doc, { x = X0 + 5 * CW + 30, y = LH + 50 }, TH), "right margin")
-- blank space after the paragraph's last line (第二段开头 is 5 chars and fills its line,
-- so use the 2-char paragraph: blank after 文 on its line)
assert(not Context.charAt(para, { x = X0 + 2 * CW + 60, y = 50 }, TH), "after the paragraph")
-- between lines: in the leading above and below the glyphs
assert(not Context.charAt(doc, tapAt(doc, 1, 0, 5), TH), "leading above the glyph")
assert(not Context.charAt(doc, tapAt(doc, 1, 0, LH - 5), TH), "leading below the glyph")
-- below the last line of text
assert(not Context.charAt(doc, { x = X0 + 20, y = 30 * LH }, TH), "below all text")

-- Glyph edges: the glyph band of a 100 px line with 40 px text is y 30..70.
assert(Context.charAt(doc, tapAt(doc, 1, 0, 31), TH), "just inside the glyph top")
assert(not Context.charAt(doc, tapAt(doc, 1, 0, 29), TH), "just above the glyph top")
assert(Context.onGlyph({ x = 0, y = 0, w = 40, h = 40 }, 60, 20, 20), "text taller than box: whole box")
assert(not Context.onGlyph({ x = 0, y = 0, w = 0, h = 40 }, 40, 0, 20), "empty box")

-- Engine calls that fail are not taps on a character.
assert(not Context.charAt({ getTextFromPositions = function() error("boom") end }, { x = 1, y = 1 }, TH))
assert(not Context.charAt({}, { x = 1, y = 1 }, TH))

-- Regression (seen on device): a heading ending in a Han character followed by
-- a paragraph starting with one. Tapping the heading's last character must not
-- read the paragraph, and tapping the paragraph's first must not read the heading.
local hp = fakeDoc({ "高度人性化的俸禄制度", "唐代俸禄水平在中国" }, 20)
c, l, r = around(hp, tapAt(hp, 0, 9))
eq(c, "度"); eq(l, "人性化的俸禄制"); eq(r, "", "heading end: nothing from the next paragraph")
c, l, r = around(hp, tapAt(hp, 1, 0))
eq(c, "唐"); eq(l, "", "paragraph start: nothing from the heading"); eq(r, "代俸禄水平在中")
-- Middle of a paragraph is unaffected.
c, l, r = around(hp, tapAt(hp, 1, 3))
eq(c, "禄"); eq(l, "唐代俸"); eq(r, "水平在中国")
