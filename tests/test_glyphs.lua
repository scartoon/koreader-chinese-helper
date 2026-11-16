-- Tap to character in the popup's text (ch_glyphs.lua): line wraps, mixed
-- Chinese and Latin text, boxes of two text sizes, scrolling, near misses,
-- and the underline. The boxes are laid out here the way TextBoxWidget lays
-- them out: wide characters one size wide, others half, wrapped at `width`.
local Glyphs = require("ch_glyphs")
local Snippet = require("ch_snippet")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- A box for `text` at (x, y): size px characters, lines 1.3 size high.
local function box(text, x, y, size, width, clip)
    local chars = Glyphs.chars(text)
    local line_h = math.floor(size * 1.3)
    local lines, line, pen = {}, nil, 0
    local function newline()
        line = { top = #lines * line_h, glyphs = {} }
        lines[#lines + 1] = line
        pen = 0
    end
    newline()
    for i, c in ipairs(chars) do
        if c == "\n" then
            newline()
        else
            local w = Snippet.isWide(c) and size or math.floor(size / 2)
            if pen + w > width then newline() end
            line.glyphs[#line.glyphs + 1] = { i = i, x0 = pen, x1 = pen + w }
            pen = pen + w
        end
    end
    return { x = x, y = y, line_h = line_h, baseline = size, lines = lines, chars = chars, clip = clip }
end

-- The character tapped at (px, py), or nil.
local function tap(boxes, px, py)
    local k, i = Glyphs.find(boxes, px, py)
    if not k then return nil end
    return boxes[k].chars[i], k, i
end

-- Line wraps: 10 characters of 40 px per 400 px line.
local B = box("一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑", 100, 200, 40, 400)
eq(#B.lines, 3, "wrapped into three lines")
eq(tap({ B }, 100 + 5, 200 + 10), "一", "first character")
eq(tap({ B }, 100 + 9 * 40 + 20, 200 + 10), "十", "last of line 1")
eq(tap({ B }, 100 + 20, 200 + 52 + 10), "甲", "first of line 2 (after the wrap)")
eq(tap({ B }, 100 + 60, 200 + 2 * 52 + 5), "丑", "line 3")
-- Near misses: within half a character's width of one, the nearest.
eq(tap({ B }, 100 - 15, 200 + 10), "一", "15 px left of the box")
eq(tap({ B }, 100 - 25, 200 + 10), nil, "25 px left: too far")
eq(tap({ B }, 100 + 2 * 40 + 15, 200 + 2 * 52 + 10), "丑", "after the last character of line 3")
eq(tap({ B }, 100 + 2 * 40 + 15, 200 + 2 * 52 + 2), "丑", "same, near the line above: this line first")
eq(tap({ B }, 100 + 2 * 40 + 30, 200 + 2 * 52 + 10), "丙", "out of reach on this line: 丙 just above")
eq(tap({ B }, 100 + 2 * 40 + 30, 200 + 2 * 52 + 30), nil, "well after it")
eq(tap({ B }, 100 + 20, 200 - 15), "一", "just above the box")
eq(tap({ B }, 100 + 20, 200 + 3 * 52 + 15), "子", "just below the last line")
-- Between lines: the closer one (each line's band includes its spacing).
eq(tap({ B }, 100 + 20, 200 + 50), "一", "bottom of line 1's band")
eq(tap({ B }, 100 + 20, 200 + 54), "甲", "top of line 2's band")
-- Between two characters: the nearer.
eq(tap({ B }, 100 + 39, 200 + 10), "一", "right edge of 一")
eq(tap({ B }, 100 + 40, 200 + 10), "二", "left edge of 二")

-- Mixed Chinese and Latin: a tap on a letter takes nothing, even next to a
-- character; a tap on punctuation or a space next to one takes it.
local M = box("dǎ: 敲击。hit, 打", 0, 0, 40, 1000)
-- d 0-20, ǎ 20-40, : 40-60, space 60-80, 敲 80-120, 击 120-160, 。 160-200,
-- h 200-220 i 220-240 t 240-260 , 260-280, space 280-300, 打 300-340
eq(tap({ M }, 10, 10), nil, "on d")
eq(tap({ M }, 30, 10), nil, "on ǎ (tone mark)")
eq(tap({ M }, 70, 10), "敲", "on the space before 敲")
eq(tap({ M }, 100, 10), "敲", "on 敲")
eq(tap({ M }, 170, 10), "击", "on 。, next to 击")
eq(tap({ M }, 190, 10), nil, "on 。, too far from 击")
eq(tap({ M }, 205, 10), nil, "on h, right after 。")
eq(tap({ M }, 290, 10), "打", "on the space before 打")

-- Two boxes, two text sizes (an English gloss, then MOE's text 1.3x), with
-- a gap between them: the nearer box's character.
local small = box("Lit: 首鼠", 20, 100, 30, 900)        -- 首 at x 95-125, 鼠 125-155 (screen)
local big = box("首鼠两端", 20, 100 + 39 + 20, 39, 900)  -- top at y 159
local boxes = { small, big }
eq(tap(boxes, 20 + 90, 100 + 15), "首", "small box")
eq(tap(boxes, 20 + 45, 159 + 20), "鼠", "big box")
eq(tap(boxes, 20 + 45, 159 - 8), "鼠", "gap, nearer the big box")
eq(tap(boxes, 20 + 110, 100 + 39 + 5), "鼠", "gap, nearer the small box")
local _, k, i = tap(boxes, 20 + 100, 159 + 20)
eq(k, 2, "box index")
eq(i, 3, "character index (两)")

-- Scrolling: a box scrolled up by 100 px inside a 300 px window from y 50.
-- Its first two lines are above the window; taps there take nothing, and
-- below the window too.
local clip = { x = 0, y = 50, w = 500, h = 300 }
local S = box("一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉天地玄黄", 0, 50 - 100, 40, 400, clip)
eq(tap({ S }, 20, 50 - 100 + 10), nil, "line 1, scrolled out")
-- Line 3's band starts at y 54 (2 * 52 - 100 + 50); the last 4 px of line
-- 2's band are still in the window.
eq(tap({ S }, 20, 52), "甲", "line 2's visible bottom")
eq(tap({ S }, 20, 56), "子", "line 3")
eq(tap({ S }, 20, 50 + 10), "子", "line 3")
eq(tap({ S }, 20, 54 + 52 + 10), "天", "line 4")
eq(tap({ S }, 20, 49), nil, "just above the window")
-- Without the clip, the same tap would take line 2's character.
S.clip = nil
eq(tap({ S }, 20, 50 + 2), "甲", "unclipped: line 2's band reaches y 54")
S.clip = clip

-- Text with bold markers: they take no index.
local P = box("\239\191\177\239\191\178首鼠\239\191\179 x", 0, 0, 40, 400)
eq(#P.chars, 4, "markers left out")
eq(tap({ P }, 50, 10), "鼠", "after a bold run")

-- The underline: under the character, below the baseline, cut to the clip.
local u = Glyphs.underline(B, 11, 4, 5)   -- 甲, line 2
eq(u.x, 100, "underline x")
eq(u.w, 40, "underline w")
eq(u.y, 200 + 52 + 40 + 5, "underline y")
eq(u.h, 4, "underline h")
eq(Glyphs.underline(S, 1, 4, 5), nil, "a scrolled-out character has none")
local cut = Glyphs.underline(S, 21, 4, 5)  -- 子 on line 3, baseline at 54 + 40
eq(cut.y, 54 + 40 + 5, "visible underline")

-- Glyphs.cut (#11): the collapsed block's last line, cut to leave room for
-- the marker; each character 10 px wide here.
do
    local chars = Glyphs.chars("一二三四五\n六七八九十")
    local measure = function(s) return #Glyphs.chars(s) * 10 end
    eq(Glyphs.cut(chars, 7, 11, 100, measure), 11, "fits: nothing cut")
    eq(Glyphs.cut(chars, 7, 11, 35, measure), 9, "three characters fit")
    eq(Glyphs.cut(chars, 7, 11, 5, measure), 6, "none fit: an empty line")
    eq(Glyphs.cut(chars, 1, 6, 100, measure), 5, "a trailing newline dropped")
end
