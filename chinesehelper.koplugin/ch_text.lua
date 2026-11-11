-- Text helpers: UTF-8, Han detection, the Han run around a tapped character,
-- and the candidate words containing it. From koreader-chinese-popup
-- (cp_text.lua). Pure Lua (no KOReader dependencies), tested offline.

local Text = {}

Text.MAX_CONTEXT = 7   -- characters taken on each side of the tapped one
Text.MAX_WORD = 8      -- longest candidate word, in characters

-- Code point of a single UTF-8 character, or nil when s is not exactly one
-- well-formed character.
function Text.codepoint(s)
    if type(s) ~= "string" or s == "" then return nil end
    local b1 = s:byte(1)
    local n, cp
    if b1 < 0x80 then n, cp = 1, b1
    elseif b1 >= 0xC2 and b1 <= 0xDF then n, cp = 2, b1 - 0xC0
    elseif b1 >= 0xE0 and b1 <= 0xEF then n, cp = 3, b1 - 0xE0
    elseif b1 >= 0xF0 and b1 <= 0xF4 then n, cp = 4, b1 - 0xF0
    else return nil end
    if #s ~= n then return nil end
    for k = 2, n do
        local b = s:byte(k)
        if b < 0x80 or b > 0xBF then return nil end
        cp = cp * 64 + (b - 0x80)
    end
    return cp
end

-- CJK Unified Ideographs, all extensions, and the compatibility ideographs.
function Text.isHanCodepoint(cp)
    if not cp then return false end
    return (cp >= 0x4E00 and cp <= 0x9FFF)      -- CJK Unified Ideographs
        or (cp >= 0x3400 and cp <= 0x4DBF)      -- Extension A
        or (cp >= 0x20000 and cp <= 0x2EE5F)    -- Extensions B, C, D, E, F, I
        or (cp >= 0x30000 and cp <= 0x323AF)    -- Extensions G, H
        or (cp >= 0xF900 and cp <= 0xFAFF)      -- Compatibility Ideographs
        or (cp >= 0x2F800 and cp <= 0x2FA1F)    -- Compatibility Ideographs Supplement
end

-- True when s is exactly one Han character.
function Text.isHan(s)
    return Text.isHanCodepoint(Text.codepoint(s))
end

-- The UTF-8 characters of s (malformed bytes come out as single bytes).
function Text.chars(s)
    local out = {}
    for ch in (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

-- The Han characters directly before the tapped one: the longest run of Han
-- characters at the end of `text`, at most `max` of them, in reading order.
-- Anything else (punctuation, Latin, digits, spaces, a paragraph break) ends it.
function Text.hanSuffix(text, max)
    max = max or Text.MAX_CONTEXT
    local chars, out = Text.chars(text), {}
    for k = #chars, 1, -1 do
        if #out >= max or not Text.isHan(chars[k]) then break end
        table.insert(out, 1, chars[k])
    end
    return out
end

-- The Han characters directly after the tapped one (see hanSuffix).
function Text.hanPrefix(text, max)
    max = max or Text.MAX_CONTEXT
    local chars, out = Text.chars(text), {}
    for k = 1, #chars do
        if #out >= max or not Text.isHan(chars[k]) then break end
        out[#out + 1] = chars[k]
    end
    return out
end

--[[--
Every substring of left .. char .. right that contains the tapped character,
1 to MAX_WORD characters long.

  left   Han characters before the tapped one, in reading order
  char   the tapped character
  right  Han characters after it

Returns { {text=, start=, len=}, ... } with start relative to the tapped
character (0 = starts with it, -2 = starts two characters before it), plus a
list of the distinct texts (for the query). Each text appears once in the
first list: the same string can occur at two positions (e.g. 天天 around a
tapped 天); the earliest start is kept.
]]
function Text.candidates(left, char, right, max_word)
    max_word = max_word or Text.MAX_WORD
    local seq = {}
    for _, c in ipairs(left or {}) do seq[#seq + 1] = c end
    seq[#seq + 1] = char
    local t = #seq
    for _, c in ipairs(right or {}) do seq[#seq + 1] = c end

    local out, texts, seen = {}, {}, {}
    for i = math.max(1, t - max_word + 1), t do
        for j = t, math.min(#seq, i + max_word - 1) do
            local text = table.concat(seq, "", i, j)
            if not seen[text] then
                seen[text] = true
                out[#out + 1] = { text = text, start = i - t, len = j - i + 1 }
                texts[#texts + 1] = text
            end
        end
    end
    return out, texts
end

-- Lay `items` out in rows of at most `per_row` (the popup's ButtonTable rows).
function Text.rows(items, per_row)
    per_row = per_row or 4
    local rows, row = {}, nil
    for _, item in ipairs(items) do
        if not row or #row >= per_row then
            row = {}
            rows[#rows + 1] = row
        end
        row[#row + 1] = item
    end
    return rows
end

return Text
