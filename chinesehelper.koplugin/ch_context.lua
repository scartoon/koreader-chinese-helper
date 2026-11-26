-- From a tap to the tapped Chinese character and the Han characters around it,
-- through CreDocument (reflowable documents only). Context.tapTarget decides
-- what a tap does (the geometry is in ch_area.lua). Uses the same engine calls
-- as ReaderHighlight: getTextFromPositions for the text under a point,
-- getPrevVisibleChar/getNextVisibleChar to move by character (they cross line
-- breaks and inline tags), getTextFromXPointers for the text in between.
--
-- No KOReader requires here:
-- the document is passed in, so this is tested offline with a fake document
-- (tests/test_context.lua).

local Text = require("ch_text")
local Layout = require("ch_layout")
local Area = require("ch_area")

local Context = {}

local function call(object, method, ...)
    if not object or not object[method] then return nil end
    local ok, a, b = pcall(object[method], object, ...)
    if not ok then return nil end
    return a, b
end

-- Vertical band the glyphs occupy inside a line box (crengine's segment boxes
-- are line-height tall): the same estimate the annotation layer draws against.
Context.glyphBand = Layout.textBand

-- True when (x, y) is on the glyph of the character whose segment box is `box`.
function Context.onGlyph(box, text_height, x, y)
    if not box or not box.w or box.w <= 0 then return false end
    local top, bottom = Context.glyphBand(box, text_height)
    return x >= box.x and x < box.x + box.w and y >= top and y < bottom
end

--[[--
The Han character under screen point pos, or nil.

Returns { char=, pos0=, pos1=, box= } only when the text under the point is
exactly one Han character and the point is on its glyph: crengine snaps a
point in a margin, between lines or after a paragraph to the nearest text, so
the box test is what lets those taps through.
]]
function Context.charAt(document, pos, text_height)
    local range = call(document, "getTextFromPositions", pos, pos, true)
    if not range or not range.pos0 or not range.pos1 then return nil end
    local char = range.text
    if not Text.isHan(char) then return nil end
    local boxes = range.sboxes
    if not boxes or #boxes == 0 then
        boxes = call(document, "getScreenBoxesFromPositions", range.pos0, range.pos1, true)
    end
    for _, box in ipairs(boxes or {}) do
        if Context.onGlyph(box, text_height, pos.x, pos.y) then
            return { char = char, pos0 = range.pos0, pos1 = range.pos1, box = box }
        end
    end
    return nil
end

Context.WINDOW_MAX = 400   -- characters walked at most each way (Context.window)

-- One character from xpointer a to b: { text=, pos0=, pos1=, box= }; box is
-- nil off screen and at a paragraph's end (empty text).
local function cell(document, a, b, screen_h)
    local text = call(document, "getTextFromXPointers", a, b) or ""
    local boxes = call(document, "getScreenBoxesFromPositions", a, b, true)
    local box = boxes and boxes[1]
    if box and (not box.w or box.w <= 0 or not box.h or box.h <= 0
            or (screen_h and (box.y >= screen_h or box.y + box.h <= 0))) then
        box = nil
    end
    return { text = text, pos0 = a, pos1 = b, box = box }
end

-- A paragraph's end, between two paragraphs' characters: no text and no box.
local function isBreak(c) return c.box == nil and (c.text == "" or c.text == "\n") end

--[[--
The characters on screen around the snapped character at xpointer pos0, in
reading order, for Area.decide: { text=, pos0=, pos1=, box=, brk= }, brk
marking the first character after a paragraph break.

Walks back from pos0 and forward from it one visible character at a time
(one text and one box lookup each: a few hundredths of a millisecond on a
Boox Go 7) and stops at the first character whose line lies wholly outside
y_lo..y_hi (so every line it keeps is complete), at a character off screen,
or after Context.WINDOW_MAX characters.
]]
function Context.window(document, pos0, y_lo, y_hi, screen_h)
    -- Backwards: (prev, cur) is the character before cur. A break met just
    -- after keeping a character means that character starts its paragraph;
    -- one met before keeping any means the snapped character does.
    local before, anchor_brk = {}, nil
    local cur = pos0
    for _ = 1, Context.WINDOW_MAX do
        local prev = call(document, "getPrevVisibleChar", cur)
        if not prev or prev == cur then
            -- The start of the text starts a paragraph too.
            if #before > 0 then before[#before].brk = true else anchor_brk = true end
            break
        end
        local c = cell(document, prev, cur, screen_h)
        if isBreak(c) then
            if #before > 0 then before[#before].brk = true else anchor_brk = true end
        else
            if not c.box or c.box.y + c.box.h <= y_lo then break end
            -- Walking back, crengine steps from a paragraph's first character
            -- straight to the last one of the paragraph before; forwards it
            -- stops at the paragraph's end in between. So where the line
            -- changes (and at the snapped character), a forward step that
            -- does not come back to cur means a paragraph starts at cur.
            local last = before[#before]
            if (not last or last.box.y ~= c.box.y)
                    and call(document, "getNextVisibleChar", prev) ~= cur then
                if last then last.brk = true else anchor_brk = true end
            end
            before[#before + 1] = c
        end
        cur = prev
    end
    local chars = {}
    for k = #before, 1, -1 do chars[#chars + 1] = before[k] end
    -- Forwards from pos0: the snapped character first.
    cur = pos0
    local pending = anchor_brk
    for _ = 1, Context.WINDOW_MAX do
        local nxt = call(document, "getNextVisibleChar", cur)
        if not nxt or nxt == cur then break end
        local c = cell(document, cur, nxt, screen_h)
        if isBreak(c) then
            pending = true
        else
            if not c.box or c.box.y >= y_hi then break end
            c.brk = pending or nil
            pending = nil
            chars[#chars + 1] = c
        end
        cur = nxt
    end
    return chars
end

--[[--
What a tap at screen point pos does (see ch_area.lua), through the engine.

  m  { text_height=, pad=, em=, screen_h= }

Returns Area.decide's result plus, for a popup, hit = { char=, pos0=, pos1=,
box= } (the character chosen, as Context.charAt returns it), and chars =
how many characters were looked at.

crengine snaps any point to the nearest text; that character is where the
walk starts (Context.window, over the lines within a line's height of the
tap and of the snapped character). A tap right on a Han character's glyph
takes it at once, without the walk.
]]
function Context.tapTarget(document, pos, m)
    local range = call(document, "getTextFromPositions", pos, pos, true)
    if not range or not range.pos0 or not range.pos1 then
        return { outcome = "pass", why = "no text", chars = 0 }
    end
    local boxes = range.sboxes
    if not boxes or #boxes == 0 then
        boxes = call(document, "getScreenBoxesFromPositions", range.pos0, range.pos1, true) or {}
    end
    if Text.isHan(range.text) then
        for _, box in ipairs(boxes) do
            if Context.onGlyph(box, m.text_height, pos.x, pos.y) then
                return { outcome = "popup", dist = 0, why = "on glyph", chars = 1,
                         hit = { char = range.text, pos0 = range.pos0, pos1 = range.pos1, box = box } }
            end
        end
    end
    local anchor = boxes[1]
    local lh = anchor and anchor.h or (m.text_height or 0) * 2
    local top = anchor and math.min(pos.y, anchor.y) or pos.y
    local bottom = anchor and math.max(pos.y, anchor.y + anchor.h) or pos.y
    local chars = Context.window(document, range.pos0, top - lh, bottom + lh, m.screen_h)
    local r = Area.decide(chars, pos.x, pos.y, m)
    r.chars = #chars
    local c = r.index and chars[r.index]
    if c then r.hit = { char = c.text, pos0 = c.pos0, pos1 = c.pos1, box = c.box } end
    return r
end

-- Move up to n visible characters from xp with `step`; the last position reached.
local function walk(document, xp, step, n)
    local cur = xp
    for _ = 1, n do
        local nxt = call(document, step, cur)
        if not nxt or nxt == cur then break end
        cur = nxt
    end
    return cur
end

-- Text.chars(text) without its last (or first) character, when that character
-- is `char`; nil otherwise (the range did not end/start where expected).
local function withoutLast(text, char)
    if not text or #text < #char or text:sub(-#char) ~= char then return nil end
    return text:sub(1, #text - #char)
end
local function withoutFirst(text, char)
    if not text or #text < #char or text:sub(1, #char) ~= char then return nil end
    return text:sub(#char + 1)
end

--[[--
Up to `max` Han characters before and after the tapped one.

Takes the text from `max` visible characters before the tapped character up
to and including it (and from it to `max` characters after it) in one call
each, then keeps only the Han run touching the tapped character: punctuation,
Latin, digits, spaces and paragraph breaks all end it. Line wraps do not.

The tapped character is included in each range on purpose: crengine's
getRangeText only puts its "\n" block delimiter between two pieces of
collected text, so a range that stops exactly at a paragraph boundary (the
tapped character first or last in its paragraph) would otherwise run the two
paragraphs together.
Returns left, right (arrays of characters, in reading order) and the run's
edges { before=, after= }: the characters that ended it on each side (《 and
》 around a book title), nil where it reached `max` characters or the range's
end.
]]
function Context.around(document, hit, max)
    max = max or Text.MAX_CONTEXT
    local left, right, before, after = {}, {}, nil, nil
    local from = walk(document, hit.pos0, "getPrevVisibleChar", max)
    if from ~= hit.pos0 then
        local text = withoutLast(call(document, "getTextFromXPointers", from, hit.pos1), hit.char)
        left = Text.hanSuffix(text or "", max)
        before = Text.edgeBefore(text or "", left, max)
    end
    -- pos1 is the end of the tapped character; one more step than max because
    -- the first step from pos1 may only reach the start of the next character.
    local to = walk(document, hit.pos1, "getNextVisibleChar", max + 1)
    if to ~= hit.pos1 then
        local text = withoutFirst(call(document, "getTextFromXPointers", hit.pos0, to), hit.char)
        right = Text.hanPrefix(text or "", max)
        after = Text.edgeAfter(text or "", right, max)
    end
    return left, right, { before = before, after = after }
end

return Context
