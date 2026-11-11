-- The sentence around a tapped character, for the popup's Translate button.
--
-- Works on the document text, not on the lines drawn on screen: it walks
-- crengine's DOM with getPrevVisibleChar/getNextVisibleChar (which cross line
-- wraps, inline tags and page boundaries) and reads the text in between with
-- getTextFromXPointers, where a real paragraph or block break comes back as
-- "\n" (crengine's getRangeText block delimiter). A line wrap is never a break.
--
--   forward:  up to and including the next sentence end (。！？, and . ! ? in
--             Latin text) with any closing quotes or brackets right after it,
--             or to the end of the paragraph if there is none;
--   backward: to just after the previous sentence end (and its closers), or
--             to the start of the paragraph, whichever comes first.
--
-- Longer than MAX characters: kept to a MAX-character window around the
-- tapped character (see Sentence.cap). The result carries the start and end
-- XPointers, so it can stand in for a real selection.
--
-- No KOReader requires: the document is passed in, so this is tested offline
-- with a fake document (tests/test_sentence.lua).

local Text = require("ch_text")

local Sentence = {}

Sentence.MAX = 200   -- characters, the tapped one included
Sentence.CHUNK = 48  -- characters walked between two text reads

local function set(list)
    local s = {}
    for _, c in ipairs(list) do s[c] = true end
    return s
end

-- Sentence ends: always, or (Latin) only when followed by a space, a closer,
-- another end mark, a non-ASCII character or the end of the paragraph, so
-- "3.14" or "e.g" do not end a sentence.
Sentence.ENDS = set{ "。", "！", "？", "｡", "︒", "﹒", "﹗", "﹖", "．" }
Sentence.ASCII_ENDS = set{ ".", "!", "?" }
-- Closing quotes and brackets that belong to the sentence they follow.
Sentence.CLOSERS = set{ "”", "’", "」", "』", "）", "》", "〉", "】", "〕", "〗", "〙", "〛",
                        "］", "｝", "﹂", "﹄", "»", "›", "\"", "'", ")", "]", "}" }
-- Clause marks: where an over-long sentence is preferably cut.
Sentence.CLAUSES = set{ "，", "；", "：", ",", ";", ":", "﹐", "﹔", "﹕" }

local function isSpace(c)
    return c == " " or c == "\t" or c == "\r" or c == "\n" or c == "　" or c == "\194\160"
end
Sentence.isSpace = isSpace

-- Is c (followed by `next`, nil when unknown) a sentence end? Returns
-- true, false, or nil when it depends on a character not read yet.
function Sentence.isEnd(c, next)
    if Sentence.ENDS[c] then return true end
    if not Sentence.ASCII_ENDS[c] then return false end
    if next == nil then return nil end
    return isSpace(next) or Sentence.CLOSERS[next] or Sentence.ENDS[next] or Sentence.ASCII_ENDS[next]
        or #next > 1
end

local function isTail(c)
    return Sentence.CLOSERS[c] or Sentence.ENDS[c] or Sentence.ASCII_ENDS[c]
end

--[[--
How many of `chars` (the characters after the tapped one, in reading order)
belong to its sentence. Returns n, final: final is false when the answer
depends on text not read yet (an end mark is the last character read, so
closers may follow). `at_end`: nothing follows `chars` (end of the document,
or the walk's limit).
]]
function Sentence.forwardCut(chars, at_end)
    local i = 1
    while i <= #chars do
        local c = chars[i]
        if c == "\n" then return i - 1, true end
        local e = Sentence.isEnd(c, chars[i + 1])
        if e == nil then return at_end and i or i - 1, at_end end
        if e then
            local j = i
            while chars[j + 1] and isTail(chars[j + 1]) do j = j + 1 end
            if j == #chars and not at_end then return j, false end
            return j, true
        end
        i = i + 1
    end
    return #chars, at_end
end

--[[--
How many of `chars` (the characters before the tapped one, in reading order)
belong to its sentence: those after the last paragraph break or sentence end
(with its closers). Returns n, final: final is false when no boundary was
found and more text may precede. `at_start`: nothing precedes `chars`.
`char`: the tapped character (what follows the last of `chars`).
]]
function Sentence.backwardCut(chars, at_start, char)
    local boundary
    local i = 1
    while i <= #chars do
        local c = chars[i]
        if c == "\n" then
            boundary = i
        elseif Sentence.isEnd(c, chars[i + 1] or char) then
            local j = i
            while chars[j + 1] and isTail(chars[j + 1]) do j = j + 1 end
            boundary = j
            i = j
        end
        i = i + 1
    end
    if boundary then return #chars - boundary, true end
    return #chars, at_start
end

local function trimLeft(chars)
    local k = 1
    while chars[k] and isSpace(chars[k]) do k = k + 1 end
    local out = {}
    for i = k, #chars do out[#out + 1] = chars[i] end
    return out
end

local function trimRight(chars)
    local k = #chars
    while k > 0 and isSpace(chars[k]) do k = k - 1 end
    local out = {}
    for i = 1, k do out[i] = chars[i] end
    return out
end
Sentence.trimLeft, Sentence.trimRight = trimLeft, trimRight

--[[--
Keep a sentence of `left` + the tapped character + `right` (character arrays)
to at most `max` characters. The window is centred on the tapped character,
shifted when one side is shorter than half; then each cut end moves inward
to the nearest clause mark (，；：,;:) in the outer quarter of its side, if
there is one, so the text does not stop mid-phrase. Returns left, right,
capped (true when anything was cut).
]]
function Sentence.cap(left, right, max)
    max = max or Sentence.MAX
    if #left + 1 + #right <= max then return left, right, false end
    local budget = max - 1
    local lb = math.floor(budget / 2)
    local rb = budget - lb
    if #left < lb then
        rb, lb = rb + lb - #left, #left
    elseif #right < rb then
        lb, rb = lb + rb - #right, #right
    end
    local l, r = {}, {}
    local from = #left - lb + 1
    if lb < #left then
        -- the outermost clause mark in the first quarter: start just after it
        for k = from, from + math.floor(lb / 4) - 1 do
            if Sentence.CLAUSES[left[k]] then from = k + 1; break end
        end
    end
    for k = from, #left do l[#l + 1] = left[k] end
    local to = rb
    if rb < #right then
        -- the outermost clause mark in the last quarter: end with it
        for k = rb, rb - math.floor(rb / 4) + 1, -1 do
            if Sentence.CLAUSES[right[k]] then to = k; break end
        end
    end
    for k = 1, to do r[k] = right[k] end
    return trimLeft(l), trimRight(r), true
end

-- Document side ------------------------------------------------------------

local function call(object, method, ...)
    if not object or not object[method] then return nil end
    local ok, a = pcall(object[method], object, ...)
    if not ok then return nil end
    return a
end

-- One side's walk: xps[0] is the start, xps[k] k visible characters away.
-- text(k) is the text between the tapped character and xps[k], without the
-- tapped character, read once and kept.
local function side(document, hit, forward)
    local s = { xps = { [0] = forward and hit.pos1 or hit.pos0 }, texts = { [0] = "" }, n = 0, done = false }
    local step = forward and "getNextVisibleChar" or "getPrevVisibleChar"
    function s.extend(count)
        for _ = 1, count do
            local cur = s.xps[s.n]
            local nxt = call(document, step, cur)
            if not nxt or nxt == cur then s.done = true; return end
            s.n = s.n + 1
            s.xps[s.n] = nxt
        end
    end
    function s.text(k)
        if s.texts[k] then return s.texts[k] end
        local t
        if forward then
            t = call(document, "getTextFromXPointers", hit.pos0, s.xps[k])
            if t and t:sub(1, #hit.char) == hit.char then t = t:sub(#hit.char + 1) else t = nil end
        else
            t = call(document, "getTextFromXPointers", s.xps[k], hit.pos1)
            if t and #t >= #hit.char and t:sub(-#hit.char) == hit.char then t = t:sub(1, #t - #hit.char) else t = nil end
        end
        s.texts[k] = t or false
        return s.texts[k]
    end
    -- The first k whose text is at least `bytes` long and matches `want` at
    -- the tapped character's side; texts grow with k, so a binary search.
    function s.find(want)
        if #want == 0 then return 0 end
        local lo, hi = 1, s.n
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            local t = s.text(mid)
            if t and #t >= #want then hi = mid else lo = mid + 1 end
        end
        local t = s.text(lo)
        if not t or #t < #want then return nil end
        if forward then
            if t:sub(1, #want) ~= want then return nil end
        elseif t:sub(-#want) ~= want then
            return nil
        end
        return lo
    end
    return s
end

-- Read one side until the cut is final (or the walk's limit is reached).
-- Returns the side's characters to keep (reading order) and the side.
local function readSide(document, hit, forward, limit)
    local s = side(document, hit, forward)
    while true do
        s.extend(Sentence.CHUNK)
        local t = s.text(s.n)
        if not t then return nil end
        local chars = Text.chars(t)
        local last = s.done or #chars >= limit
        if forward then
            local n, final = Sentence.forwardCut(chars, last)
            if final or last then
                local out = {}
                for k = 1, n do out[k] = chars[k] end
                return out, s
            end
        else
            local n, final = Sentence.backwardCut(chars, last, hit.char)
            if final or last then
                local out = {}
                for k = #chars - n + 1, #chars do out[#out + 1] = chars[k] end
                return out, s
            end
        end
    end
end

--[[--
The sentence around hit ({ char=, pos0=, pos1= }, as from ch_context.lua).
Returns { text=, pos0=, pos1=, capped= }, or nil when the document cannot
be read. pos0/pos1 are nil when the text could not be matched back to
positions (then only the text can be sent).
]]
function Sentence.find(document, hit, max)
    max = max or Sentence.MAX
    if not document or not hit or not hit.pos0 or not hit.pos1 or not hit.char then return nil end
    local limit = max + 8
    local left, back = readSide(document, hit, false, limit)
    local right, fwd = readSide(document, hit, true, limit)
    if not left or not right then return nil end
    local capped
    left, right, capped = Sentence.cap(trimLeft(left), trimRight(right), max)
    local ltext, rtext = table.concat(left), table.concat(right)
    local result = { text = ltext .. hit.char .. rtext, capped = capped }
    local i, j = back.find(ltext), fwd.find(rtext)
    if i and j then
        result.pos0, result.pos1 = back.xps[i], fwd.xps[j]
    end
    return result
end

return Sentence
