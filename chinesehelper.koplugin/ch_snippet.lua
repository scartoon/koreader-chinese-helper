-- The popup's context line: the text around the tapped character, as much
-- of it as fits on one line, with the character (or the word a word button
-- looked up) marked.
--
--   Snippet.select   pure: page characters, tapped index (and word span), a
--                    width-measuring function -> the line's three parts
--   Snippet.pageText the visible page's characters and the tapped one's index,
--                    through CreDocument (the document is passed in)
--
-- No KOReader requires: tested offline (tests/test_snippet.lua).

local Sentence = require("ch_sentence")
local Text = require("ch_text")

local Snippet = {}

-- A paragraph (block) break in the character list. Never produced by
-- Text.chars, which splits into single characters, so a lone "\n" in the
-- list is a hard line break inside a paragraph (whitespace).
Snippet.BREAK = "\n\n"
Snippet.ELLIPSIS = "…"
Snippet.TAIL_WALK = 1500   -- characters walked to find the end of the last page

local isSpace = Sentence.isSpace

local function isTail(c)
    return Sentence.CLOSERS[c] or Sentence.ENDS[c] or Sentence.ASCII_ENDS[c]
end

-- Full-width text: between two of these, whitespace collapses to nothing.
-- CJK scripts and punctuation, full-width forms, and the curly quotes,
-- dashes and ellipsis Chinese text sets full-width.
function Snippet.isWide(c)
    local cp = Text.codepoint(c)
    if not cp then return false end
    return (cp >= 0x1100 and cp <= 0x115F) or (cp >= 0x2E80 and cp <= 0xA4CF)
        or (cp >= 0xAC00 and cp <= 0xD7A3) or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0xFE30 and cp <= 0xFE4F) or (cp >= 0xFF00 and cp <= 0xFF60)
        or (cp >= 0xFFE0 and cp <= 0xFFE6) or (cp >= 0x20000 and cp <= 0x3FFFD)
        or cp == 0x2014 or cp == 0x2026 or (cp >= 0x2018 and cp <= 0x201D)
end

--[[--
Characters of `text` for Snippet.select. paragraphs: what marks a paragraph
break in `text`, "\n" (crengine's block delimiter, every "\n" is a break)
or "\n\n" (a blank line, as the tests write paragraphs; a single "\n" is
then a hard line break inside one).
]]
function Snippet.chars(text, paragraphs)
    local out = {}
    for _, c in ipairs(Text.chars(text)) do
        if c == "\n" and paragraphs == "\n" then
            out[#out + 1] = Snippet.BREAK   -- one per "\n": pageText matches them to crossings
        else
            out[#out + 1] = c
        end
    end
    if paragraphs == "\n\n" then
        local merged, k = {}, 1
        while k <= #out do
            if out[k] == "\n" and out[k + 1] == "\n" then
                while out[k] == "\n" do k = k + 1 end
                merged[#merged + 1] = Snippet.BREAK
            else
                merged[#merged + 1] = out[k]
                k = k + 1
            end
        end
        out = merged
    end
    return out
end

--[[--
The sentence around chars[from..to]: returns L, R, the first and last
index it covers. Stops at a paragraph break, after a sentence end (。！？,
and . ! ? in Latin text) with the closing quotes and brackets right after
it, and at the ends of `chars` (the visible page). Commas and semicolons
are not boundaries.
]]
function Snippet.bounds(chars, from, to)
    local L, R = 1, #chars
    for k = from - 1, 1, -1 do
        local c = chars[k]
        if c == Snippet.BREAK then L = k + 1; break end
        if Sentence.isEnd(c, chars[k + 1]) then
            L = k + 1
            -- Closers after the end belong to the sentence it ends.
            while L < from and isTail(chars[L]) do L = L + 1 end
            break
        end
    end
    for k = to + 1, #chars do
        local c = chars[k]
        if c == Snippet.BREAK then R = k - 1; break end
        local e = Sentence.isEnd(c, chars[k + 1])
        if e or (e == nil and k == #chars) then
            R = k
            while chars[R + 1] and chars[R + 1] ~= Snippet.BREAK and isTail(chars[R + 1]) do R = R + 1 end
            break
        end
    end
    return L, R
end

-- chars[L..R] as display tokens { {s=, idx=} }: each run of whitespace (hard
-- line breaks included) becomes nothing between two full-width characters
-- and at either end, and one space elsewhere.
local function tokens(chars, L, R)
    local out, i = {}, L
    while i <= R do
        local c = chars[i]
        if isSpace(c) then
            local j = i
            while j <= R and isSpace(chars[j]) do j = j + 1 end
            local prev, nxt = out[#out], j <= R and chars[j] or nil
            if prev and nxt and not (Snippet.isWide(prev.s) and Snippet.isWide(nxt)) then
                out[#out + 1] = { s = " ", idx = i, space = true }
            end
            i = j
        else
            out[#out + 1] = { s = c, idx = i }
            i = i + 1
        end
    end
    return out
end

local function concat(list, i, j)
    local parts = {}
    for k = i, j do parts[#parts + 1] = list[k].s end
    return table.concat(parts)
end

--[[--
Pick the context line.

  args.chars    the visible page's characters (Snippet.chars / pageText)
  args.index    the tapped character's index in chars
  args.word     optional { text=, start= }: a word looked up from the popup,
                starting `start` characters from the tapped one (0: at it,
                -2: two before it). Marked only when chars has exactly that
                word there; otherwise the tapped character is marked.
  args.measure  function(s, bold) -> width in pixels
  args.width    the line's width in pixels

Returns { before=, mark=, after=, cut_left=, cut_right= }: before and after
carry the "…" of a side cut for width (a side that stops at a boundary has
none). nil when index is not a character of chars.
]]
function Snippet.select(args)
    local chars, index = args.chars or {}, args.index
    if not index or not chars[index] or chars[index] == Snippet.BREAK then return nil end
    local from, to = index, index
    if args.word and args.word.text and args.word.start then
        local w = Text.chars(args.word.text)
        local a = index + args.word.start
        local ok = #w > 0 and a <= index and a + #w - 1 >= index and a >= 1
        if ok then
            for k = 1, #w do
                if chars[a + k - 1] ~= w[k] then ok = false; break end
            end
        end
        if ok then from, to = a, a + #w - 1 end
    end
    local L, R = Snippet.bounds(chars, from, to)
    local toks = tokens(chars, L, R)
    local left, right, mid = {}, {}, {}
    for _, t in ipairs(toks) do
        if t.idx < from then left[#left + 1] = t
        elseif t.idx > to then right[#right + 1] = t
        else mid[#mid + 1] = t end
    end
    local mark = concat(mid, 1, #mid)

    local cache = {}
    local function w(s)
        local v = cache[s]
        if not v then
            v = args.measure(s, false)
            cache[s] = v
        end
        return v
    end
    local width = args.width or math.huge
    local markw = args.measure(mark, true)
    local ell = w(Snippet.ELLIPSIS)

    -- Grow both sides from the mark, the narrower side first, one token at
    -- a time, while the line (with a "…" on each side not yet complete) fits.
    local li, ri = #left + 1, 0          -- left[li..#left] and right[1..ri] are in
    local lw, rw = 0, 0
    local function total(li_, ri_, lw_, rw_)
        return lw_ + markw + rw_ + (li_ > 1 and ell or 0) + (ri_ < #right and ell or 0)
    end
    while true do
        local can_l, can_r = li > 1, ri < #right
        if not can_l and not can_r then break end
        local order = (can_l and (not can_r or lw <= rw)) and { "l", "r" } or { "r", "l" }
        local grew = false
        for _, side in ipairs(order) do
            if side == "l" and li > 1 then
                local nlw = lw + w(left[li - 1].s)
                if total(li - 1, ri, nlw, rw) <= width then
                    li, lw, grew = li - 1, nlw, true
                    break
                end
            elseif side == "r" and ri < #right then
                local nrw = rw + w(right[ri + 1].s)
                if total(li, ri + 1, lw, nrw) <= width then
                    ri, rw, grew = ri + 1, nrw, true
                    break
                end
            end
        end
        if not grew then break end
    end

    local function build()
        local cut_l, cut_r = li > 1, ri < #right
        local a, b = li, ri
        -- No space between the "…" and the text.
        if cut_l and left[a] and left[a].space then a = a + 1 end
        if cut_r and right[b] and right[b].space then b = b - 1 end
        local before = (cut_l and Snippet.ELLIPSIS or "") .. concat(left, a, #left)
        local after = concat(right, 1, b) .. (cut_r and Snippet.ELLIPSIS or "")
        return { before = before, mark = mark, after = after, cut_left = cut_l, cut_right = cut_r }
    end
    -- The sum of single-token widths can differ from the whole string's by
    -- kerning: measure the result and give back a token from the wider side
    -- until it fits.
    local result = build()
    for _ = 1, #left + #right do
        local lwidth = result.before ~= "" and args.measure(result.before, false) or 0
        local rwidth = result.after ~= "" and args.measure(result.after, false) or 0
        if lwidth + markw + rwidth <= width or (li > #left and ri == 0) then break end
        if lwidth >= rwidth and li <= #left then li = li + 1 else ri = math.max(0, ri - 1) end
        result = build()
    end
    if result.before ~= "" or result.after ~= "" then
        local lwidth = result.before ~= "" and args.measure(result.before, false) or 0
        local rwidth = result.after ~= "" and args.measure(result.after, false) or 0
        if lwidth + markw + rwidth > width then
            -- Not even the "…" fit: the mark alone.
            result.before, result.after = "", ""
        end
    end
    return result
end

-- Document side ------------------------------------------------------------

local function call(object, method, ...)
    if not object or not object[method] then return nil end
    local ok, a = pcall(object[method], object, ...)
    if not ok then return nil end
    return a
end

--[[--
The visible page's characters and the tapped character's index in them:
chars, index (Snippet.chars of the page text, crengine's "\n" block
delimiters as paragraph breaks), or nil when the page cannot be read or
the tapped character cannot be found in it.

  hit     { char=, pos0=, pos1= } (ch_context.lua)
  bounds  { start=, stop= }: XPointers of the page's first character and of
          the first one after it (stop nil: the page runs to the end of the
          document); see Snippet.pageBounds.
]]
function Snippet.pageText(document, hit, bounds)
    if not hit or not hit.pos0 or not hit.pos1 or not bounds or not bounds.start then return nil end
    local stop = bounds.stop
    if not stop then
        -- To the end of the document: walk to its last character.
        stop = hit.pos1
        for _ = 1, Snippet.TAIL_WALK do
            local nxt = call(document, "getNextVisibleChar", stop)
            if not nxt or nxt == stop then break end
            stop = nxt
        end
    end
    local full = call(document, "getTextFromXPointers", bounds.start, stop)
    -- From the page start up to and including the tapped character: the
    -- range ends after text, so a paragraph break just before the tapped
    -- character is in it (crengine puts "\n" only between collected text).
    local head = call(document, "getTextFromXPointers", bounds.start, hit.pos1)
    if type(full) ~= "string" or type(head) ~= "string" then return nil end
    if #head < #hit.char or head:sub(-#hit.char) ~= hit.char then return nil end
    local chars = Snippet.chars(full, "\n")
    local index = #Snippet.chars(head, "\n")
    if chars[index] ~= hit.char or full:sub(1, #head) ~= head then
        -- The two reads disagree (should not happen): the nearest occurrence.
        local found
        for d = 0, 40 do
            if chars[index - d] == hit.char then found = index - d; break end
            if chars[index + d] == hit.char then found = index + d; break end
        end
        if not found then return nil end
        index = found
    end
    Snippet.markLineBreaks(document, hit, chars, index)
    return chars, index
end

-- The paragraph (block) a character's XPointer is in, as far as its path
-- tells: the path without the text node ("/body/p[4]/text()[2].5" ->
-- "/body/p[4]").
function Snippet.parentPath(xp)
    if type(xp) ~= "string" then return nil end
    return xp:match("^(.*)/text%(") or xp:match("^(.*)%.%d+$") or xp
end

Snippet.INLINE = {}
for name in ("a abbr b bdi bdo big cite code del dfn em font i img ins kbd label mark q rb rp rt rtc ruby "
        .. "s samp small span strike strong sub sup tt u var wbr"):gmatch("%S+") do
    Snippet.INLINE[name] = true
end

-- One step of the character walk, from XPointer a to b (a before b): "br"
-- when it crosses a <br/>, "block" when it crosses from one block into a
-- sibling one, nil otherwise (an inline tag, or nothing).
function Snippet.crossing(a, b, html)
    if type(html) == "string" and html:find("<br") then return "br" end
    local pa, pb = Snippet.parentPath(a), Snippet.parentPath(b)
    if not pa or not pb or pa == pb then return nil end
    -- Below their common ancestor, does either path go through a block?
    local ca, cb = {}, {}
    for c in pa:gmatch("[^/]+") do ca[#ca + 1] = c end
    for c in pb:gmatch("[^/]+") do cb[#cb + 1] = c end
    local n = 1
    while ca[n] and ca[n] == cb[n] do n = n + 1 end
    for _, list in ipairs({ ca, cb }) do
        for k = n, #list do
            if not Snippet.INLINE[list[k]:gsub("%[%d+%]$", "")] then return "block" end
        end
    end
    return nil
end

--[[--
crengine's text has "\n" both for a block break and for a <br/>; Snippet.chars
makes every one a BREAK. Turn the ones that are <br/> inside a paragraph
back into "\n" (whitespace for Snippet.select), for the breaks within
LINE_REACH characters of the tapped one (no line holds more): walk the
document from the tapped character outwards and match each "\n", in order, to
a step that crosses a <br/> or a block boundary. When the counts disagree,
those breaks stay paragraph breaks.
]]
Snippet.LINE_REACH = 80
function Snippet.markLineBreaks(document, hit, chars, index)
    for _, forward in ipairs({ false, true }) do
        local breaks, dir = {}, forward and 1 or -1
        local k = index + dir
        while chars[k] and math.abs(k - index) <= Snippet.LINE_REACH do
            if chars[k] == Snippet.BREAK then breaks[#breaks + 1] = k end
            k = k + dir
        end
        if #breaks > 0 then
            local kinds = {}
            local cur = forward and hit.pos1 or hit.pos0
            local step = forward and "getNextVisibleChar" or "getPrevVisibleChar"
            for _ = 1, Snippet.LINE_REACH + 2 * #breaks do
                if #kinds >= #breaks then break end
                local nxt = call(document, step, cur)
                if not nxt or nxt == cur then break end
                local a, b = cur, nxt
                if not forward then a, b = nxt, cur end
                local kind = Snippet.crossing(a, b, call(document, "getHTMLFromXPointers", a, b, 0, false))
                if kind then kinds[#kinds + 1] = kind end
                cur = nxt
            end
            if #kinds == #breaks then
                for n, pos in ipairs(breaks) do
                    if kinds[n] == "br" then chars[pos] = "\n" end
                end
            end
        end
    end
end

--[[--
The XPointers bounding the text on screen: { start=, stop= }, or nil.
Page view: the current page's start to the next page's (two pages side by
side: the page after both). Continuous view: the top of the screen to the
start of the page after next, as ch_page.lua reads it (a page is a screen
high, so that can run past the bottom of the screen).
]]
function Snippet.pageBounds(document, scroll)
    local page = call(document, "getCurrentPage")
    if not page then return nil end
    local start = scroll and call(document, "getXPointer") or call(document, "getPageXPointer", page)
    if not start then return nil end
    local count = call(document, "getVisiblePageCount")
    if type(count) ~= "number" or count < 1 then count = 1 end
    local stop = call(document, "getPageXPointer", page + (scroll and 2 or count))
    if stop == "" or stop == start then stop = nil end
    return { start = start, stop = stop }
end

return Snippet
