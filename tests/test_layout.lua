-- Vertical placement of the pinyin and the line-height needed for it.
local Layout = require("ch_layout")

local function near(a, b) return math.abs(a - b) < 0.01 end

-- Measured on a Boox Go 7: 64 px text, line box 105 px (line-height 1.94 at
-- 85% line spacing). Pinyin ascent 20, descent 6, gap 2.
local box = { x = 0, y = 32, w = 64, h = 105 }
local top = Layout.textBand(box, 64)
assert(near(top, 52.5), "text top " .. top)
local baseline = Layout.pinyinBaseline(box, 64, 20, 6, 2)
assert(near(baseline, 44.5), "baseline " .. baseline)
-- Pinyin top (24.5) is below the line above's characters (32 - 20.5 = 11.5)
-- and its bottom (50.5) clears this line's characters (52.5).
assert(baseline - 20 > box.y - (top - box.y))
assert(baseline + 6 <= top - 2 + 0.01)

-- Cramped line: no room, so the pinyin is pushed down onto its own character
-- instead of up onto the line above.
local tight = { x = 0, y = 32, w = 64, h = 70 }
local b2 = Layout.pinyinBaseline(tight, 64, 20, 6, 2)
assert(near(b2, 32 - 3 + 2 + 20), "tight baseline " .. b2)

-- Headings: a line box clearly taller than a line of book text (here twice
-- the size) gets its text size from the box, so the pinyin clears its larger
-- characters; an ordinary line keeps the book's text size exactly.
local ratio = 105 / 64
assert(Layout.lineTextHeight(box, 64, ratio) == 64, "ordinary line unchanged")
assert(Layout.lineTextHeight({ x = 0, y = 32, w = 64, h = 110 }, 64, ratio) == 64, "slightly taller: unchanged")
local heading = { x = 0, y = 32, w = 128, h = 210 }
assert(near(Layout.lineTextHeight(heading, 64, ratio), 128), "heading text size")
assert(Layout.lineTextHeight(heading, 64, nil) == 64, "no ratio: as before")

-- The tapped character's underline: just below the glyph band, scaled to the
-- text size, as wide as the character.
local u = Layout.underlineRect(box, 64)
eq_u = function(a, b, m) assert(a == b, m .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
eq_u(u.x, 0, "underline x"); eq_u(u.w, 64, "underline w")
eq_u(u.h, 4, "underline thickness at 64 px")
eq_u(u.y, math.floor(32 + 105 - 20.5 + 3), "underline just below the glyphs")
assert(u.y + u.h < box.y + box.h + 20.5, "inside the gap above the next line's glyphs")
u = Layout.underlineRect({ x = 5, y = 0, w = 20, h = 24 }, 20)
eq_u(u.h, 2, "never thinner than 2 px"); eq_u(u.y, 22 + 1, "gap at least 1 px")

print("layout: ok")
