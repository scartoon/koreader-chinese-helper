-- A fake CreDocument for the offline tests (test_context.lua, test_sentence.lua).
--
-- The fake lays a list of paragraphs out like crengine: each character is
-- 40 px wide in 100 px tall line boxes, `per_line` characters per line.
-- XPointers are "p/i" (paragraph p, character offset i). Paragraph breaks
-- come back from getTextFromXPointers as crengine returns them (see below).
local Text = require("ch_text")

local M = {}

M.CW, M.LH, M.TH, M.X0 = 40, 100, 40, 100
local CW, LH, X0 = M.CW, M.LH, M.X0

-- opts.indent: the first line of each paragraph starts this many cells in;
-- opts.gap: extra pixels between paragraphs (both 0 by default);
-- opts.prev_skips_end: see getPrevVisibleChar.
function M.fakeDoc(paras, per_line, opts)
    opts = opts or {}
    local indent, gap = opts.indent or 0, opts.gap or 0
    local doc = { cells = {} }    -- flat list of { p=, i=, ch=, box= }
    local line = 0
    for p, s in ipairs(paras) do
        local chars = Text.chars(s)
        for i, ch in ipairs(chars) do
            local col = (i - 1 + indent) % per_line
            if i > 1 and col == 0 then line = line + 1 end
            doc.cells[#doc.cells + 1] = { p = p, i = i - 1, ch = ch,
                box = { x = X0 + col * CW, y = line * LH + (p - 1) * gap, w = CW, h = LH } }
        end
        doc.cells[#doc.cells + 1] = { p = p, i = #chars, ch = nil }   -- end of paragraph
        line = line + 1
    end
    local index = {}
    for k, c in ipairs(doc.cells) do index[c.p .. "/" .. c.i] = k end
    local function xp(c) return c.p .. "/" .. c.i end

    -- crengine snaps a point to the nearest character on the nearest line
    -- (also in margins and blank space), which is why charAt tests the box.
    function doc:getTextFromPositions(pos)
        local best, bestd
        for k, c in ipairs(self.cells) do
            if c.ch then
                local cx, cy = c.box.x + c.box.w / 2, c.box.y + c.box.h / 2
                local d = math.abs(cy - pos.y) * 1000 + math.abs(cx - pos.x)
                if not bestd or d < bestd then best, bestd = k, d end
            end
        end
        local c = self.cells[best]
        return { text = c.ch, pos0 = xp(c), pos1 = c.p .. "/" .. (c.i + 1), sboxes = { c.box } }
    end
    -- From a paragraph's first character: the previous paragraph's end, or
    -- (opts.prev_skips_end, as crengine does on the device) its last character.
    function doc:getPrevVisibleChar(x)
        local k = index[x]
        if not k or k == 1 then return nil end
        local c = self.cells[k]
        if c.i == 0 and opts.prev_skips_end and k > 2 then return xp(self.cells[k - 2]) end
        return xp(self.cells[k - 1])
    end
    function doc:getNextVisibleChar(x)
        local k = index[x]
        if not k or k == #self.cells then return nil end
        return xp(self.cells[k + 1])
    end
    -- Like crengine's ldomXRange::getRangeText('\n'): the block delimiter goes
    -- between two pieces of collected text only, so a range that starts or
    -- ends exactly at a paragraph boundary has no "\n" at that end (seen on
    -- device: the old code read the next paragraph as context).
    function doc:getTextFromXPointers(a, b)
        local ka, kb = index[a], index[b]
        local out, pending = {}, false
        for k = ka, kb - 1 do
            local c = self.cells[k]
            if c.ch then
                if pending and #out > 0 then out[#out + 1] = "\n" end
                pending = false
                out[#out + 1] = c.ch
            else
                pending = true
            end
        end
        return table.concat(out)
    end
    -- Pages of `lines_per_page` lines (default 10), for tests that cross one.
    function doc:getPageFromXPointer(x)
        local k = index[x]
        local c = self.cells[k]
        if c and not c.box then c = self.cells[k - 1] end   -- end of paragraph: its last character
        local y = c and c.box and c.box.y or 0
        return math.floor(y / LH / (self.lines_per_page or 10)) + 1
    end
    -- One box per character (a paragraph's end has none), like crengine's
    -- line segments for a one-character range.
    function doc:getScreenBoxesFromPositions(a, b)
        local c = self.cells[index[a]]
        if not c or not c.ch then return {} end
        return { c.box }
    end
    -- The hit for the n-th character (1-based) of paragraph p.
    function doc:hit(p, n)
        local c = self.cells[index[p .. "/" .. (n - 1)]]
        return { char = c.ch, pos0 = p .. "/" .. (n - 1), pos1 = p .. "/" .. n, box = c.box }
    end
    return doc
end

return M
