-- What a tap inside the text does (ch_area.lua), and the walk that feeds it
-- (Context.window, Context.tapTarget), against the fake CreDocument.
--
-- Fake geometry (tests/fake_credoc.lua): cells 40 px wide from x = 100, line
-- boxes 100 px tall, 40 px text, so a line's glyphs sit 30..70 px into its
-- box. Here: a 10 px pad, a 40 px character width, so Latin text reaches
-- 3 x 40 = 120 px for a Han character.
local Area = require("ch_area")
local Context = require("ch_context")
local Fake = require("fake_credoc")
local eq = require("sq3_shim").eq

local CW, LH, TH, X0 = Fake.CW, Fake.LH, Fake.TH, Fake.X0
local M = { text_height = TH, pad = 10, em = CW, screen_h = 2000 }

local function tap(doc, x, y)
    return Context.tapTarget(doc, { x = x, y = y }, M)
end
-- Popup for `char`?
local function popup(doc, x, y, char, msg)
    local r = tap(doc, x, y)
    eq(r.outcome, "popup", msg .. " (" .. tostring(r.why) .. ")")
    eq(r.hit.char, char, msg)
    return r
end
local function outcome(doc, x, y, want, msg)
    local r = tap(doc, x, y)
    eq(r.outcome, want, msg .. " (" .. tostring(r.why) .. ")")
    return r
end
-- Centre x of column col, top y of line `line` (with `gap` px per earlier paragraph).
local function cx(col) return X0 + col * CW + CW / 2 end

-- Ten cells a line, first lines indented two cells, 30 px between paragraphs:
--   line 0  y   0..100   ..他说，这个历史挺       (paragraph 1)
--   line 1  y 100..200   靠谱
--   line 2  y 230..330   ..的书Hello_            (paragraph 2, 30 px gap above)
--   line 3  y 330..430   world中文。
--   line 4  y 460..560   ..abc 123               (paragraph 3: no Han)
--   line 5  y 590..690   ..短                     (paragraph 4)
local doc = Fake.fakeDoc({ "他说，这个历史挺靠谱", "的书Hello world中文。", "abc 123", "短" }, 10,
    { indent = 2, gap = 30 })

-- On a glyph: the character, at once.
local r = popup(doc, cx(2), 50, "他", "on the glyph")
eq(r.dist, 0); eq(r.why, "on glyph")

-- Between lines: the half-line below line 0's glyphs is line 0's, above
-- line 1's glyphs is line 1's.
popup(doc, cx(3), 95, "说", "below the glyphs, in line 0's box")
popup(doc, cx(0), 105, "靠", "above the glyphs, in line 1's box")
r = popup(doc, cx(3), 85, "说", "the empty half-line below")
eq(r.dist, 15, "15 px below the glyph band (30..70)")

-- Punctuation: ， (column 4, x 260..300) goes to the nearer neighbour.
popup(doc, 265, 50, "说", "left part of ，")
popup(doc, 295, 50, "这", "right part of ，")
-- Either side of the boundary between 这 (300..340) and 个 (340..380).
popup(doc, 339, 50, "这", "just left of the boundary")
popup(doc, 341, 50, "个", "just right of the boundary")

-- The paragraph indent: line 0 starts at x 180, the line below at 100.
r = popup(doc, 130, 50, "他", "in the indent")
eq(r.dist, 50)
popup(doc, 95, 50, "他", "within the pad left of the indent")
outcome(doc, 85, 50, "pass", "left margin, beyond the pad")

-- A short last line's tail: 靠谱 ends at x 180.
popup(doc, 185, 150, "谱", "within the pad after the last character")
outcome(doc, 195, 150, "pass", "the rest of the short line")
outcome(doc, 400, 150, "pass", "far into the short line's tail")

-- Margins beside a full line (line 0 ends at 500).
outcome(doc, 505, 50, "popup", "right pad")
outcome(doc, 515, 50, "pass", "right margin")
outcome(doc, 20, 150, "pass", "left margin")

-- The 30 px paragraph gap between line 1 (to y 200) and line 2 (from 230):
-- never a page turn, while it is under a line high.
popup(doc, 300, 215, "书", "in the paragraph gap: nearest of both lines")
popup(doc, 120, 205, "靠", "in the gap, just below 靠")
-- ... but only across the lines' width: line 1 ends at 180 (+ pad), line 2 at 500.
outcome(doc, 515, 215, "pass", "right of both lines in the gap")

-- Latin in a mixed line: within reach (3 x 40 px) of a Han character, on
-- this line or the next, it snaps to it.
popup(doc, cx(4), 280, "书", "on H: 书 is next to it")
popup(doc, cx(7), 280, "文", "on the second l: 文 on the line below is nearer than 书")
popup(doc, cx(4), 380, "中", "on d: 中 is next to it")
r = popup(doc, cx(0), 380, "的", "on w: 中 is out of reach, 的 on the line above is not")
eq(r.why, "next line"); eq(r.dist, 100)

-- A line with no Han characters is KOReader's (paragraph 3: abc 123).
outcome(doc, cx(4), 510, "pass", "on a Latin and digit line")
outcome(doc, cx(4), 570, "pass", "in the gap, nearer that line than 短's")
popup(doc, cx(4), 585, "短", "in the gap, nearer 短's line")

-- Paragraph 4 (短 at x 180..220, y 590..690) and the blank space after it.
popup(doc, cx(2), 640, "短", "the last paragraph")
outcome(doc, cx(6), 640, "pass", "after its last character")
outcome(doc, cx(2), 720, "pass", "below the last line")
outcome(doc, cx(2), 1500, "pass", "far below the text")

-- A Latin run with no Han character within reach is swallowed: no popup, no
-- page turn. The line after it has no Han at all: KOReader's.
local latin = Fake.fakeDoc({ "中abcdefghijklmnopqrs" }, 10)
popup(latin, cx(3), 50, "中", "on c, 80 px from 中")
r = outcome(latin, cx(8), 50, "swallow", "on h, 300 px from 中")
assert(not r.hit)
outcome(latin, cx(5), 150, "pass", "on the line with no Han")

-- A gap of a line height or more is blank space: the page turns there.
local wide = Fake.fakeDoc({ "第一段", "第二段" }, 10, { gap = 120 })
outcome(wide, cx(1), 160, "pass", "120 px between paragraphs")
local narrow = Fake.fakeDoc({ "第一段", "第二段" }, 10, { gap = 90 })
popup(narrow, cx(1), 140, "一", "90 px between paragraphs: nearer line above")
popup(narrow, cx(1), 180, "二", "90 px between paragraphs: nearer line below")

-- The walk looks only at the lines around the tap, never the whole page:
-- 30 lines of 10, a tap in the middle reads the line, the one above and the
-- one below (and stops at the first character beyond them).
local long = {}
for _ = 1, 300 do long[#long + 1] = "字" end
local page = Fake.fakeDoc({ table.concat(long) }, 10)
r = popup(page, 300, 1590, "字", "between lines in a long paragraph")
assert(r.chars <= 40, "looked at " .. r.chars .. " characters")
eq(r.hit.box.y, 1500, "the line whose box holds the tap")

-- Paragraph breaks reach Area.lines as `brk` on the next paragraph's first
-- character.
local chars = Context.window(doc, "2/0", 0, 400, 2000)
local firsts = {}
for _, c in ipairs(chars) do if c.brk then firsts[#firsts + 1] = c.text end end
eq(table.concat(firsts, ","), "他,的", "paragraph starts")
-- Walking back from the middle of a paragraph also finds where it starts.
chars = Context.window(doc, "1/9", 0, 200, 2000)
eq(chars[1].text, "他"); eq(chars[1].brk, true)

-- On the device, crengine's step back from a paragraph's first character
-- lands on the previous paragraph's last character, with no empty
-- paragraph end in between: the start is still found.
local skips = Fake.fakeDoc({ "他说，这个历史挺靠谱", "的书Hello world中文。", "abc 123", "短" }, 10,
    { indent = 2, gap = 30, prev_skips_end = true })
chars = Context.window(skips, "2/0", 0, 400, 2000)
firsts = {}
for _, c in ipairs(chars) do if c.brk then firsts[#firsts + 1] = c.text end end
eq(table.concat(firsts, ","), "他,的", "paragraph starts, crengine's way")
popup(skips, 140, 280, "的", "the second paragraph's indent, tapped on its first line")
chars = Context.window(skips, "2/5", 0, 400, 2000)
eq(chars[1].text, "他"); assert(chars[1].brk)
for _, c in ipairs(chars) do
    if c.text == "的" then assert(c.brk, "的 starts paragraph 2, walking back from H") end
end

-- Area.decide directly: two lines that sit in two columns (the same line
-- top), a character with no box, and an empty input.
eq(Area.decide({}, 10, 10, M).outcome, "pass", "nothing to look at")
local boxless = { { text = "中" }, { text = "文", box = { x = 0, y = 0, w = 40, h = 100 } } }
r = Area.decide(boxless, 30, 50, M)
eq(r.outcome, "popup"); eq(r.index, 2, "the character with a box")
eq(#Area.lines(boxless), 1)

-- Engine failures are a pass, not an error.
eq(Context.tapTarget({}, { x = 1, y = 1 }, M).outcome, "pass")
eq(Context.tapTarget({ getTextFromPositions = function() error("boom") end }, { x = 1, y = 1 }, M).outcome, "pass")
