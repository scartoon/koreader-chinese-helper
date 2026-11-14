-- The text area and the nearest Han character to a tap (pure Lua, no
-- KOReader dependencies, tested offline in tests/test_area.lua).
--
-- A tap inside the text opens the popup for the nearest Han character, so a
-- tap between lines, between characters, in a paragraph's indent or on
-- punctuation never turns the page. Only clear whitespace goes to KOReader.
--
-- The text area is the union of the line rectangles: each runs from the
-- line's first character's left edge to its last character's right edge,
-- plus `pad` on both sides, and covers the full line box vertically. A
-- paragraph's first line also covers its indent (it reaches left to where
-- the neighbouring lines start, if that is at most INDENT_EMS away). The
-- vertical gap between two consecutive lines counts too while it is less
-- than a line high (paragraph spacing), across the width of either line.
--
-- Input: the characters around the tap in reading order (ch_context.lua's
-- Context.window), each { text=, box={x,y,w,h}, brk=true when a paragraph
-- break comes before it }. Lines are runs of consecutive characters with the
-- same box top.

local Text = require("ch_text")
local Layout = require("ch_layout")

local Area = {}

Area.PAD_MM = 1.5        -- beyond a line's first and last character
Area.REACH_EMS = 3       -- how far (in character widths) a Latin tap looks for a Han character
Area.INDENT_EMS = 4      -- the widest indent a paragraph's first line is widened over

-- Distance from (x, y) to the rectangle x0..x1, y0..y1 (0 inside).
local function dist(x, y, x0, y0, x1, y1)
    local dx = (x < x0 and x0 - x) or (x > x1 and x - x1) or 0
    local dy = (y < y0 and y0 - y) or (y > y1 and y - y1) or 0
    return math.sqrt(dx * dx + dy * dy)
end

-- The glyph box of a character: its box horizontally, the glyph band
-- (Layout.textBand) vertically.
function Area.glyph(box, text_height)
    local top, bottom = Layout.textBand(box, text_height)
    return box.x, top, box.x + box.w, bottom
end

function Area.glyphDistance(box, text_height, x, y)
    local x0, y0, x1, y1 = Area.glyph(box, text_height)
    return dist(x, y, x0, y0, x1, y1)
end

--[[--
The lines of `chars`: { first=, last= (indexes into chars), x0=, x1=, y0=,
y1=, han= (number of Han characters), para= (true when the line starts a
paragraph) }, in reading order. Characters without a box are left out.
]]
function Area.lines(chars)
    local lines, cur = {}, nil
    for k, c in ipairs(chars) do
        local b = c.box
        if b and b.w and b.h and b.h > 0 then
            if not cur or b.y ~= cur.y0 then
                cur = { first = k, last = k, x0 = b.x, x1 = b.x + b.w, y0 = b.y, y1 = b.y + b.h, han = 0,
                        para = c.brk == true }
                lines[#lines + 1] = cur
            end
            cur.last = k
            if b.x < cur.x0 then cur.x0 = b.x end
            if b.x + b.w > cur.x1 then cur.x1 = b.x + b.w end
            if b.y + b.h > cur.y1 then cur.y1 = b.y + b.h end
            if Text.isHan(c.text) then cur.han = cur.han + 1 end
        end
    end
    return lines
end

-- Are lines a and b (a before b) vertically next to each other: b starts at
-- or below a's bottom, less than a line high further down?
local function adjacent(a, b)
    if not a or not b then return false end
    local gap = b.y0 - a.y1
    local h = math.min(a.y1 - a.y0, b.y1 - b.y0)
    return gap >= 0 and gap < h
end

-- Left edge of a line in the text area: a paragraph's first line reaches
-- left over its indent to where a neighbouring line starts.
local function left(lines, i, em)
    local line = lines[i]
    local x0 = line.x0
    if not line.para then return x0 end
    for _, j in ipairs({ i - 1, i + 1 }) do
        local nb = lines[j]
        local next_to = (j < i and adjacent(nb, line)) or (j > i and adjacent(line, nb))
        if next_to and nb.x0 < x0 and line.x0 - nb.x0 <= Area.INDENT_EMS * em then x0 = nb.x0 end
    end
    return x0
end

local function inSpan(lines, i, x, pad, em)
    local line = lines[i]
    return x >= left(lines, i, em) - pad and x < line.x1 + pad
end

-- The nearest Han character on the given lines: index, distance.
local function nearest(chars, lines, which, text_height, x, y)
    local best, best_d
    for _, i in ipairs(which) do
        local line = lines[i]
        if line then
            for k = line.first, line.last do
                local c = chars[k]
                if c.box and Text.isHan(c.text) then
                    local d = Area.glyphDistance(c.box, text_height, x, y)
                    if not best_d or d < best_d then best, best_d = k, d end
                end
            end
        end
    end
    return best, best_d
end

--[[--
What a tap at (x, y) does.

  chars  the characters around the tap (see the top of this file)
  m      { text_height=, pad= (px), em= (a character's width, px; default
           text_height) }

Returns { outcome = "popup" | "swallow" | "pass", index= (into chars, for a
popup), dist= (px from that character's glyph box), why= (a short reason,
for the log) }:
  popup    the nearest Han character, on the tapped line, or for a tap in
           the gap between two lines on either of them; a tap on a line
           whose nearest Han character is more than REACH_EMS away (Latin
           text) looks on the lines above and below too;
  swallow  inside a line that has Han characters, but none within reach:
           nothing happens (no popup, no page turn);
  pass     outside the text area, or on a line with no Han characters (or
           in a gap nearer to such a line than to the other): KOReader's.
]]
function Area.decide(chars, x, y, m)
    local th = m.text_height
    local pad = m.pad or 0
    local em = m.em or th or 0
    local reach = Area.REACH_EMS * em
    local lines = Area.lines(chars)
    -- A line whose box holds the tap point (its own span, not just its height).
    for i, line in ipairs(lines) do
        if y >= line.y0 and y < line.y1 and inSpan(lines, i, x, pad, em) then
            if line.han == 0 then return { outcome = "pass", why = "line without Han" } end
            local k, d = nearest(chars, lines, { i }, th, x, y)
            if d <= reach then return { outcome = "popup", index = k, dist = d, why = "line" } end
            local around = {}
            if adjacent(lines[i - 1], line) then around[#around + 1] = i - 1 end
            if adjacent(line, lines[i + 1]) then around[#around + 1] = i + 1 end
            local k2, d2 = nearest(chars, lines, around, th, x, y)
            if k2 and d2 <= reach then return { outcome = "popup", index = k2, dist = d2, why = "next line" } end
            return { outcome = "swallow", why = "no Han within reach" }
        end
    end
    -- The gap between two consecutive lines.
    for i = 1, #lines - 1 do
        local a, b = lines[i], lines[i + 1]
        if y >= a.y1 and y < b.y0 and adjacent(a, b)
                and (inSpan(lines, i, x, pad, em) or inSpan(lines, i + 1, x, pad, em)) then
            -- The nearer line (the upper one at the midpoint) decides whether
            -- this is text: a gap beside a line with no Han is KOReader's.
            local near = (y - a.y1 <= b.y0 - y) and a or b
            if near.han == 0 then return { outcome = "pass", why = "gap beside a line without Han" } end
            local k, d = nearest(chars, lines, { i, i + 1 }, th, x, y)
            if d <= reach + (b.y0 - a.y1) then return { outcome = "popup", index = k, dist = d, why = "gap" } end
            return { outcome = "swallow", why = "no Han within reach" }
        end
    end
    return { outcome = "pass", why = "outside the text" }
end

return Area
