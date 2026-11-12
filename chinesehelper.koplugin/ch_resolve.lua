-- The reading resolver: which reading a character has in its context, and
-- which characters on a page get pinyin. Pure Lua, no KOReader dependencies.
--
-- It is the one place readings are decided: the annotation layer draws what
-- Resolve.annotate returns, and the tap popup marks what Resolve.reading
-- returns for the tapped character (and Resolve.wordReading for each word),
-- on the same page items with the same settings, so the two cannot disagree.
--
-- From pinyin_resolve.lua in koreader-interlinear-pinyin. Changes: the data
-- now covers every character (common ones too, for the popup), so annotate
-- checks rarity before resolving, which also keeps word lookups off the page
-- turn for common characters; word candidates are looked up in one batch.
--
-- Input is the page as a sequence of items, one per visible "word" the
-- rendering engine reports. The engine treats every CJK character as a
-- one-character word, so a run of Chinese text is one item per character.
--
--   items[i] = {
--       text   = "饕",        -- the item's text
--       joined = true,        -- directly follows items[i-1] (no punctuation,
--                             -- space or element boundary in between)
--       on_page = true,       -- false for context items before/after the page
--   }
--
-- Readings: each character has a default (its most frequent reading). When the
-- character sits inside a dictionary word of 2-4 characters, that word's
-- reading wins, longest word first. This is what turns 侥 into jiǎo in 侥幸
-- but yáo in 僬侥.

local Resolve = {}

-- Number of UTF-8 code points in s.
local function utf8_len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
Resolve.utf8_len = utf8_len

-- Is this item a single Han (or other 3-4 byte) character?
local function single_char(text)
    if not text then return false end
    -- One UTF-8 code point of 3 or 4 bytes.
    local len = #text
    if len ~= 3 and len ~= 4 then return false end
    local b = text:byte(1)
    if len == 3 then return b >= 0xE3 and b <= 0xEF end
    return b == 0xF0
end
Resolve.single_char = single_char

-- Is items[a..b] one contiguous run of characters?
local function contiguous(items, a, b)
    if a < 1 or b > #items then return false end
    for k = a, b do
        if not single_char(items[k].text) then return false end
        if k > a and not items[k].joined then return false end
    end
    return true
end

-- Reading of items[i] taken from the longest dictionary word around it, or
-- nil. Also returns the word, the index of its first item, and the other
-- words of the same length that also cover items[i] (for the tap popup's
-- "also possible"), as { {word=, start=}, ... }.
-- When several words of that length cover it (大宛 and 宛如 in 很大宛如), the
-- more frequent word wins; the leftmost one on a tie.
local function text_of(items, start, stop)
    local parts = {}
    for k = start, stop do parts[#parts + 1] = items[k].text end
    return table.concat(parts)
end

-- Add every word word_reading may look up for items[i] to `list`.
local function candidate_words(data, items, i, list)
    local max_len = math.min(data.max_word_len or 4, 4)
    for len = max_len, 2, -1 do
        for start = i - len + 1, i do
            if contiguous(items, start, start + len - 1) then list[#list + 1] = text_of(items, start, start + len - 1) end
        end
    end
    return list
end

function Resolve.word_reading(data, items, i)
    local max_len = math.min(data.max_word_len or 4, 4)
    if data.prefetch then
        -- Every candidate word in one lookup (a database query in the plugin;
        -- nothing when Resolve.annotate has fetched the page's already).
        local list = candidate_words(data, items, i, {})
        if #list > 0 then data:prefetch(list) end
    end
    for len = max_len, 2, -1 do
        local best, best_freq, best_word, best_start
        local others = {}
        for start = i - len + 1, i do
            local stop = start + len - 1
            if contiguous(items, start, stop) then
                local word = text_of(items, start, stop)
                local syllables, freq = data:word(word)
                freq = freq or 0
                if syllables and #syllables == len then
                    if not best or freq > best_freq then
                        if best then others[#others + 1] = { word = best_word, start = best_start } end
                        best, best_freq, best_word, best_start = syllables[i - start + 1], freq, word, start
                    else
                        others[#others + 1] = { word = word, start = start }
                    end
                end
            end
        end
        if best then return best, best_word, best_start, others end
    end
    return nil
end

-- Reading of items[i] from the longest fallback-dictionary word around it
-- (Wiktionary, MOE: words CC-CEDICT lacks; see Readings:prefetchFallback),
-- or nil. Also returns the word, the index of its first item and its cache
-- entry ({ source=, syllables= }). Only words that give the character one
-- reading count. When two words of the longest such length give it
-- different readings, nothing is decided (fallback words have no
-- frequencies to choose by), and shorter words are not consulted.
function Resolve.fallback_reading(data, items, i)
    if not data.fallbackWord or not data.fallback then return nil end
    data:prefetchFallback(candidate_words(data, items, i, {}))
    local max_len = math.min(data.max_word_len or 4, 4)
    for len = max_len, 2, -1 do
        local best, best_word, best_start, best_entry
        for start = i - len + 1, i do
            local stop = start + len - 1
            if contiguous(items, start, stop) then
                local word = text_of(items, start, stop)
                local entry = data:fallbackWord(word)
                local reading = entry and entry.readings[i - start + 1]
                if reading then
                    if not best then
                        best, best_word, best_start, best_entry = reading, word, start, entry
                    elseif reading ~= best then
                        return nil
                    end
                end
            end
        end
        if best then return best, best_word, best_start, best_entry end
    end
    return nil
end

------------------------------------------------------------------------
-- Unusual readings of common characters ("special words", data/special.tsv)
------------------------------------------------------------------------

-- Is the special word at items[s..e] blocked by an overlapping ordinary word
-- that is the likelier reading (订单 in 订单于3日发货 blocks 单于), or by a
-- longer word containing it with another reading (九华山 blocks 华山)? Which
-- word blocks which, and at what offset, is decided when the data is built
-- (tools/special_words.py); here it is only looked up.
local function blocked(special, items, entry, s, e)
    local guard = special.guard
    for a = s - 3, e do
        for b = math.max(a + 1, s), math.min(a + 3, e + 3) do
            -- items[a..b] crosses an edge (starts before s and ends inside, or
            -- starts inside and ends after e) or contains the whole word.
            local crosses = (a < s and b < e) or (a > s and b > e and a <= e)
            local contains = a <= s and b >= e and (a < s or b > e)
            if (crosses or contains) and contiguous(items, a, b) then
                local parts = {}
                for k = a, b do parts[#parts + 1] = items[k].text end
                if guard[table.concat(parts) .. "\t" .. entry.word .. "\t" .. (a - s)] then return true end
            end
        end
    end
    return false
end

-- The special word covering items[i], or nil: { entry=, start=, pos= } with
-- pos the index of items[i] in the word. When several cover it, the longest
-- wins, then the more frequent, then the leftmost.
function Resolve.special_at(special, items, i)
    if not special or not items[i] or not single_char(items[i].text) then return nil end
    local best
    for start = math.max(1, i - special.max_len + 1), i do
        local list = items[start] and special.by_first[items[start].text]
        if list then
            for _, entry in ipairs(list) do
                local n = #entry.chars
                local stop = start + n - 1
                if stop >= i and contiguous(items, start, stop) then
                    local same = true
                    for k = 2, n do
                        if items[start + k - 1].text ~= entry.chars[k] then
                            same = false
                            break
                        end
                    end
                    if same and not (best and (n < #best.entry.chars
                            or (n == #best.entry.chars and entry.freq <= best.entry.freq)))
                            and not blocked(special, items, entry, start, stop) then
                        best = { entry = entry, start = start, pos = i - start + 1 }
                    end
                end
            end
        end
    end
    return best
end

-- What to do when a character's reading is uncertain (see Resolve.reading).
Resolve.UNCERTAIN_BOTH = "both"   -- "chéng/shèng", most likely first
Resolve.UNCERTAIN_BEST = "best"   -- the most likely reading alone (may differ from the default)
Resolve.UNCERTAIN_SKIP = "skip"   -- no annotation

-- The reading a context rule gives items[i], or nil.
local function rule_reading(data, items, i)
    if not data.rule then return nil end
    local item = items[i]
    local left = item.joined and items[i - 1] and items[i - 1].text or nil
    local after = items[i + 1]
    local right = after and after.joined and after.text or nil
    return data:rule(item.text, left, right)
end

-- Would items[i] get the uncertainty pair from words and rules alone (no
-- special word considered)? Only then do fallback words count.
function Resolve.undecided(data, items, i)
    local first, second
    if data.uncertainty then first, second = data:uncertainty(items[i].text) end
    if not (first and second and first ~= second) then return false end
    return not Resolve.word_reading(data, items, i) and not rule_reading(data, items, i)
end

-- Reading for items[i] and the character's rank (0 = unranked), or nil when
-- there is none (no known reading, not a Han character, or uncertain with
-- mode "skip"). Works for any character; whether it is drawn is
-- Resolve.annotate's decision. A third value, when a dictionary word decided the
-- reading: { word=, start=, len=, others={ {word=, start=}, ... } } (with
-- special= the special.tsv entry for a special word). A fourth value is true
-- when the reading is an unusual one from a special word: the character is
-- then annotated however common it is.
--
-- sp: the special word covering items[i] when the caller has already looked
-- it up (false for none); nil to look it up here.
--
-- In order: a special word (when `special` is given); the longest dictionary
-- word around it (CC-CEDICT and pypinyin); a context rule for the character
-- right before or after it; its default reading. For a character whose
-- default is known to be unreliable (data:uncertainty), the longest
-- fallback-dictionary word around it picks one of the two most likely
-- readings (match.fallback = its source, match.syllables = its reading);
-- failing that, the two are shown together, the most likely alone, or
-- nothing, depending on `uncertain`. Fallback words decide nothing else:
-- measured on the CPP test split, letting them override defaults broke
-- seven readings for each one fixed (rare words matched across word
-- boundaries, dialect and classical readings).
function Resolve.reading(data, items, i, uncertain, special, sp)
    local item = items[i]
    if not item or not single_char(item.text) then return nil end
    local rank, default = data:char(item.text)
    if sp == nil then sp = special and Resolve.special_at(special, items, i) end
    if sp then
        local entry = sp.entry
        local marked = entry.marks[sp.pos]
        if marked or rank then
            return entry.syllables[sp.pos], rank,
                { word = entry.word, start = sp.start, len = #entry.chars, others = {}, special = entry },
                marked
        end
        return nil
    end
    if not rank then return nil end
    local reading, word, start, others = Resolve.word_reading(data, items, i)
    if reading then
        return reading, rank, { word = word, start = start, len = utf8_len(word), others = others }
    end
    reading = rule_reading(data, items, i)
    if reading then return reading, rank end
    local first, second
    if data.uncertainty then first, second = data:uncertainty(item.text) end
    if first and second and first ~= second then
        -- A fallback-dictionary word may choose between the two (累世: lěi).
        local fallback, fword, fstart, fentry = Resolve.fallback_reading(data, items, i)
        if fallback == first or fallback == second then
            return fallback, rank, { word = fword, start = fstart, len = utf8_len(fword), others = {},
                                     fallback = fentry.source, syllables = fentry.syllables }
        end
        uncertain = uncertain or Resolve.UNCERTAIN_BOTH
        if uncertain == Resolve.UNCERTAIN_SKIP then return nil end
        if uncertain == Resolve.UNCERTAIN_BEST then return first, rank end
        return first .. "/" .. second, rank
    end
    return default, rank
end

--[[--
Annotations for the on-page items.

  threshold: characters ranked above this (or unranked) are annotated.
  uncertain: Resolve.UNCERTAIN_BOTH (default), _BEST or _SKIP; see Resolve.reading.
  special: loaded special words (Data.loadSpecial) or nil. A character whose
    reading in a special word is unusual is annotated whatever its rank,
    with special=true; a rare character inside a special word takes the
    special word's reading.

Each character is annotated only the first time it appears on the page with a
given reading: later repeats are left bare, but a repeat with a different
reading (刨 páo in 刨根, then bào in 刨子) is annotated again.

Returns { {index=i, reading="tāo", rank=4396, match=..., special=bool}, ... }
in page order; match is the word that decided the reading (see
Resolve.reading), or nil.
]]
function Resolve.annotate(data, items, threshold, uncertain, special)
    -- Rarity first: only a rare character, or one with an unusual reading in
    -- a special word, is worth resolving. Their candidate words are then
    -- fetched in one lookup for the whole page.
    local wanted, words = {}, {}
    for i, item in ipairs(items) do
        if item.on_page ~= false and single_char(item.text) then
            local sp = special and Resolve.special_at(special, items, i) or false
            local rank = data:char(item.text)
            if (sp and sp.entry.marks[sp.pos]) or rank == 0 or (rank and rank > threshold) then
                wanted[#wanted + 1] = { i, sp }
                if data.prefetch then candidate_words(data, items, i, words) end
            end
        end
    end
    if #words > 0 then data:prefetch(words) end
    -- Then, in one more lookup, the fallback dictionaries' words around the
    -- characters that would otherwise get the uncertainty pair.
    if data.fallback then
        local fwords = {}
        for _, w in ipairs(wanted) do
            if not w[2] and Resolve.undecided(data, items, w[1]) then
                candidate_words(data, items, w[1], fwords)
            end
        end
        if #fwords > 0 then data:prefetchFallback(fwords) end
    end
    local out, seen = {}, {}
    for _, w in ipairs(wanted) do
        local i = w[1]
        local item = items[i]
        local reading, rank, match, marked = Resolve.reading(data, items, i, uncertain, special, w[2])
        if reading and (marked or rank == 0 or (rank and rank > threshold)) then
            local key = item.text .. "\t" .. reading
            if not seen[key] then
                seen[key] = true
                -- Rarity used to decide what to drop when a line is crowded:
                -- unranked characters count as rarest.
                -- Unusual readings are kept like the rarest characters.
                out[#out + 1] = { index = i, reading = reading,
                                  rank = (marked or rank == 0) and math.huge or rank,
                                  match = match, special = marked or nil }
            end
        end
    end
    return out
end

-- The resolver's reading of a whole word ("dōng xi" for 东西), from the words
-- table, or nil when the dictionaries give it only one reading (so there is
-- nothing to choose). The popup marks this reading among a word's entries.
function Resolve.wordReading(data, word)
    local syllables = data:word(word)
    return syllables and table.concat(syllables, " ") or nil
end

--[[--
What the tap popup needs for items[i]: the reading to mark and the word that
decided it. `drawn`, when the character has pinyin drawn above it, is that
pinyin, which then wins (it was computed by Resolve.annotate on the same
items, so they agree anyway; this makes it certain). The "don't annotate"
mode marks both likely readings: nothing is drawn, so there is nothing to
contradict.

Returns chosen ("dào", "chéng/shèng" or nil), decided ({ word=, start=
relative to items[i], len=, syllables=, note= } or nil), and unsure: true
when chosen is the uncertainty pair (no word or rule decided, nothing drawn),
so the popup does not call either reading likely.
]]
function Resolve.forPopup(data, items, i, uncertain, special, drawn)
    if uncertain == Resolve.UNCERTAIN_SKIP then uncertain = Resolve.UNCERTAIN_BOTH end
    local reading, _rank, match = Resolve.reading(data, items, i, uncertain, special)
    if drawn then reading = drawn end
    local decided
    if match and match.len and match.len > 1 then
        decided = {
            word = match.word, start = match.start - i, len = match.len,
            syllables = match.special and table.concat(match.special.syllables, " ")
                or match.syllables or Resolve.wordReading(data, match.word),
            note = match.special and match.special.note,
        }
    end
    local unsure = not drawn and reading ~= nil and reading:find("/", 1, true) ~= nil
    return reading, decided, unsure
end

return Resolve
