-- Which character of the popup's text a tap is on, and where to underline it.
--
--   Glyphs.find      pure: laid-out boxes and a tap point -> the Han
--                    character tapped (the nearest within half its width)
--   Glyphs.underline pure: a character's underline rectangle on screen
--   Glyphs.layout    a KOReader TextBoxWidget, as painted -> a box for those
--                    two (its lines and each character's x0/x1)
--
-- A box: { x=, y= (its top left on screen, scrolling included), line_h=,
-- baseline= (from a line's top), lines = { {top= (from the box's top),
-- glyphs = { {i=, x0=, x1=}, ... }}, ... }, chars = {...} (the box's text,
-- one character per index i), clip = {x=, y=, w=, h=} (the visible part:
-- a scrolling body's window) or nil }.
-- No KOReader requires: tested offline (tests/test_glyphs.lua).

local Text = require("ch_text")

local Glyphs = {}

Glyphs.REACH = 0.5   -- how far from a character a tap still takes it, in its width

-- TextBoxWidget's formatting markers, which it takes out of the text it shows.
Glyphs.PTF = { ["\239\191\177"] = true, ["\239\191\178"] = true, ["\239\191\179"] = true }  -- U+FFF1-FFF3

-- The characters a TextBoxWidget given `text` shows, one per index.
function Glyphs.chars(text)
    local out = {}
    for _, c in ipairs(Text.chars(text)) do
        if not Glyphs.PTF[c] then out[#out + 1] = c end
    end
    return out
end

local function inside(r, x, y)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Letters and digits (Latin, pinyin with tone marks, full-width forms): a
-- tap right on one is a tap on that text, never on a Han character nearby.
-- Punctuation and spaces are not: a tap on 。 next to a character takes it.
local function isWordChar(c)
    if not c or Text.isHan(c) then return false end
    if c:match("^[%w]$") then return true end
    local cp = Text.codepoint(c)
    if not cp then return false end
    return (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7) or (cp >= 0x1E00 and cp <= 0x1EFF)
        or (cp >= 0xFF10 and cp <= 0xFF19) or (cp >= 0xFF21 and cp <= 0xFF3A) or (cp >= 0xFF41 and cp <= 0xFF5A)
end

-- The screen rectangle of each glyph of a box, visible lines only:
-- calls f(glyph, x0, x1, y0, y1).
local function eachGlyph(box, f)
    local clip = box.clip
    for _, line in ipairs(box.lines) do
        local y0 = box.y + line.top
        local y1 = y0 + box.line_h
        if not clip or (y1 > clip.y and y0 < clip.y + clip.h) then
            for _, g in ipairs(line.glyphs) do
                if g.x1 > g.x0 then
                    if f(g, box.x + g.x0, box.x + g.x1, y0, y1) then return end
                end
            end
        end
    end
end

--[[--
The Han character tapped at (px, py) among `boxes`: box index, character
index, and its screen rectangle {x, y, w, h} (the line's full height); nil
when the tap is on no Han character. A tap on a character, or within
REACH of its width of one (beside it, above or below it, between lines),
takes the nearest: on the tapped line if one is in reach there, else on
the nearer line; a tap right on a letter or digit takes nothing; taps
outside a box's clip, or on lines scrolled out of it, take nothing in it.
]]
function Glyphs.find(boxes, px, py, reach)
    reach = reach or Glyphs.REACH
    local best_k, best_g, best_d, best_r
    for k, box in ipairs(boxes) do
        if not box.clip or inside(box.clip, px, py) then
            eachGlyph(box, function(g, x0, x1, y0, y1)
                local dx = math.max(0, x0 - px, px - x1 + 1)
                local dy = math.max(0, y0 - py, py - y1 + 1)
                local c = box.chars[g.i]
                if dx == 0 and dy == 0 and isWordChar(c) then
                    best_k, best_g, best_d = nil, nil, -1   -- right on a letter: nothing
                    return true
                end
                if Text.isHan(c) then
                    local limit = (x1 - x0) * reach
                    if dx <= limit and dy <= limit then
                        -- The tapped line first (dy 0), then the nearer line.
                        local d = dy * 100000 + dx
                        if not best_d or d < best_d then
                            best_k, best_g, best_d = k, g, d
                            best_r = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
                        end
                    end
                end
            end)
            if best_d == -1 then return nil end
        end
    end
    if not best_k then return nil end
    return best_k, best_g.i, best_r
end

--[[--
The underline under character `i` of `box`: {x, y, w, h} on screen, cut to
the box's clip, or nil (not on a visible line). thick, offset: the line's
thickness and its distance below the baseline.
]]
function Glyphs.underline(box, i, thick, offset)
    local rect
    eachGlyph(box, function(g, x0, x1, y0)
        if g.i == i then
            rect = { x = x0, y = y0 + (box.baseline or box.line_h) + offset, w = x1 - x0, h = thick }
            return true
        end
    end)
    if not rect or not box.clip then return rect end
    local c = box.clip
    local top, bottom = math.max(rect.y, c.y), math.min(rect.y + rect.h, c.y + c.h)
    if bottom <= top then return nil end
    rect.y, rect.h = top, bottom - top
    return rect
end

--[[--
A KOReader TextBoxWidget as last painted (its dimen gives the position) as
a box, or nil. chars: Glyphs.chars of the text it was given. clip: as above.
Reads the widget's line list: with xtext (KOReader's default) the shaped
glyphs' x0/x1 (a cluster of several characters shares its width out);
without, the characters' widths.
]]
function Glyphs.layout(tbw, chars, clip)
    local d = tbw.dimen
    local list = tbw.vertical_string_list
    if not d or not d.x or not list or not tbw.line_height_px then return nil end
    local first = (tbw.height == nil) and 1 or (tbw.virtual_line_num or 1)
    local last = math.min(#list, first + (tbw.lines_per_page or #list) - 1)
    local lines = {}
    for ln = first, last do
        local line = list[ln]
        local glyphs = {}
        if line.end_offset and line.end_offset >= line.offset then
            if tbw.use_xtext and tbw._xtext then
                tbw:_shapeLine(line)
                for _, g in ipairs(line.xglyphs or {}) do
                    if g.is_cluster_start then
                        local n = math.max(1, g.cluster_len or 1)
                        local w = (g.x1 - g.x0) / n
                        for m = 0, n - 1 do
                            glyphs[#glyphs + 1] = { i = g.text_index + m, x0 = g.x0 + m * w, x1 = g.x0 + (m + 1) * w }
                        end
                    end
                end
            elseif tbw.char_width and type(tbw.charlist) == "table" then
                local x = 0
                for idx = line.offset, line.end_offset do
                    local w = (tbw.char_width[tbw.charlist[idx]] or 0) + ((tbw.idx_pad or {})[idx] or 0)
                    glyphs[#glyphs + 1] = { i = idx, x0 = x, x1 = x + w }
                    x = x + w
                end
            end
        end
        lines[#lines + 1] = { top = (ln - first) * tbw.line_height_px, glyphs = glyphs }
    end
    return { x = d.x, y = d.y, line_h = tbw.line_height_px, baseline = tbw.line_glyph_baseline,
             lines = lines, chars = chars, clip = clip }
end

return Glyphs
