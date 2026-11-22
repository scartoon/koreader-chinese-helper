-- The reading resolver: which reading a character has in its context, and
-- which characters on a page get pinyin. Pure Lua, no KOReader dependencies.
--
-- It is the one place readings are decided: the annotation layer draws what
-- Resolve.annotate returns, and the tap popup marks what Resolve.reading
-- returns for the tapped character (and Resolve.wordReading for each word),
-- on the same page items with the same settings, so the two cannot disagree.
--
-- The data covers every character (common ones too, for the popup), so
-- annotate checks rarity before resolving, which also keeps word lookups off
-- the page turn for common characters; word candidates are looked up in one
-- batch.
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
-- Readings: each character has a default (its most frequent reading). Which
-- word a character belongs to comes from segmenting its run of text (#75):
-- the most probable split into dictionary words by word frequency, as jieba
-- does (Resolve.segment). When the word the path puts the character in has a
-- reading in the words table, that reading wins. This is what turns 侥 into
-- jiǎo in 侥幸 but yáo in 僬侥, and keeps 尽自 out of 尽尽自己 (自己 is the
-- path's word: it has no reading to give, but rules 尽自 out).

local Sandhi = require("ch_sandhi")

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

local function text_of(items, start, stop)
    local parts = {}
    for k = start, stop do parts[#parts + 1] = items[k].text end
    return table.concat(parts)
end

-- Add every word of 2-4 characters around items[i] to `list` (the fallback
-- dictionaries' candidates).
local function candidate_words(data, items, i, list)
    local max_len = math.min(data.max_word_len or 4, 4)
    for len = max_len, 2, -1 do
        for start = i - len + 1, i do
            if contiguous(items, start, start + len - 1) then list[#list + 1] = text_of(items, start, start + len - 1) end
        end
    end
    return list
end

------------------------------------------------------------------------
-- Segmentation (#75): which word each character of a run belongs to.
------------------------------------------------------------------------

-- Is this item one Han character (CJK ideographs, their extensions and
-- compatibility forms, and 〇)? Punctuation and other symbols end a run.
local function is_han(text)
    if not single_char(text) then return false end
    local b1, b2, b3, b4 = text:byte(1, 4)
    local cp
    if #text == 3 then
        cp = (b1 % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64)
    else
        cp = (b1 % 8) * 262144 + (b2 % 64) * 4096 + (b3 % 64) * 64 + (b4 % 64)
    end
    return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
        or (cp >= 0xF900 and cp <= 0xFAFF) or cp >= 0x20000 or cp == 0x3007
end
Resolve.is_han = is_han

-- First and last index of the run of joined Han items holding items[i], or
-- nil when items[i] is not a Han character.
local function run_bounds(items, i)
    if not items[i] or not is_han(items[i].text) then return nil end
    local a, b = i, i
    while a > 1 and items[a].joined and is_han(items[a - 1].text) do a = a - 1 end
    while items[b + 1] and items[b + 1].joined and is_han(items[b + 1].text) do b = b + 1 end
    return a, b
end

-- Word frequencies are per billion words (wordfreq's), so log(f / 1e9) is a
-- word's log probability. A character no dictionary lists as a word of its
-- own counts with the floor frequency, as a dictionary word wordfreq does
-- not know does.
Resolve.SEG_FLOOR = 1
local LOG_TOTAL = math.log(1e9)
local function log_p(freq) return math.log(freq) - LOG_TOTAL end

local function seg_max_len(data) return math.min(data.max_word_len or 4, 4) end

-- Every substring of items[a..b] the segmentation looks up, added to `list`.
local function run_words(data, items, a, b, list)
    local max_len = seg_max_len(data)
    for s = a, b do
        local text = ""
        for e = s, math.min(s + max_len - 1, b) do
            text = text .. items[e].text
            list[#list + 1] = text
        end
    end
    return list
end

--[[--
The most probable segmentation of the run items[a..b] (dynamic programming
over the sum of the words' log probabilities, words of 1-4 characters;
on a tie, the longer last word). Returns
  { a=, b=, at = { [k] = { start=, len= } for items[a + k - 1] } }
]]
function Resolve.segment(data, items, a, b)
    local max_len = seg_max_len(data)
    local n = b - a + 1
    local scores = {}   -- scores[s][len]: log probability of the word at s of that length, or nil
    for s = 1, n do
        local row, text = {}, ""
        for len = 1, math.min(max_len, n - s + 1) do
            text = text .. items[a + s + len - 2].text
            local f = data.segFreq and data:segFreq(text)
            if f then
                row[len] = log_p(math.max(f, Resolve.SEG_FLOOR))
            elseif len == 1 then
                row[len] = log_p(Resolve.SEG_FLOOR)
            end
        end
        scores[s] = row
    end
    local fwd, back = { [0] = 0 }, {}
    for k = 1, n do
        local best, best_len
        for len = math.min(max_len, k), 1, -1 do
            local w = scores[k - len + 1][len]
            if w then
                local score = fwd[k - len] + w
                if not best or score > best + 1e-9 then best, best_len = score, len end
            end
        end
        fwd[k], back[k] = best, best_len
    end
    local at, k = {}, n
    while k > 0 do
        local len = back[k]
        local word = { start = a + k - len, len = len }
        for j = k - len + 1, k do at[j] = word end
        k = k - len
    end
    return { a = a, b = b, at = at }
end

-- Segmented runs, per data object and items list: { [first index] = run }.
-- The popup and the annotations work on the same page items, so a run is
-- segmented once and both read the same path.
local seg_cache = setmetatable({}, { __mode = "k" })

local function runs_of(data, items)
    local by_items = seg_cache[data]
    if not by_items then
        by_items = setmetatable({}, { __mode = "k" })
        seg_cache[data] = by_items
    end
    local runs = by_items[items]
    if not runs then
        runs = {}
        by_items[items] = runs
    end
    return runs
end

-- Fetch the word frequencies of every run holding one of items[i] for i in
-- `list` that is not segmented yet, in one lookup.
function Resolve.prefetchRuns(data, items, list)
    if not data.prefetchSeg then return end
    local runs, words, seen = runs_of(data, items), {}, {}
    for _, i in ipairs(list) do
        local a, b = run_bounds(items, i)
        if a and not runs[a] and not seen[a] then
            seen[a] = true
            run_words(data, items, a, b, words)
        end
    end
    if #words > 0 then data:prefetchSeg(words) end
end

-- The segmented run holding items[i], or nil (not a Han character).
function Resolve.runAt(data, items, i)
    local a, b = run_bounds(items, i)
    if not a then return nil end
    local runs = runs_of(data, items)
    local run = runs[a]
    if not run then
        if data.prefetchSeg then data:prefetchSeg(run_words(data, items, a, b, {})) end
        run = Resolve.segment(data, items, a, b)
        runs[a] = run
    end
    return run
end

-- The path's word holding items[i]: { word=, start= (item index), len= },
-- or nil (not a Han character).
function Resolve.pathWord(data, items, i)
    local run = Resolve.runAt(data, items, i)
    if not run then return nil end
    local w = run.at[i - run.a + 1]
    if not w.word then w.word = text_of(items, w.start, w.start + w.len - 1) end
    return w
end

-- Is the word at items[start..stop] made of whole path words, splitting
-- none (a fallback dictionary's word: 累世 over the path's 累 + 世, never a
-- word that would cut 自己 in two)? Fallback words have no frequencies, and
-- with the floor one they would rarely beat two characters (累世 does not).
function Resolve.fits(data, items, start, stop)
    local run = Resolve.runAt(data, items, start)
    if not run or stop > run.b then return false end
    local first, last = run.at[start - run.a + 1], run.at[stop - run.a + 1]
    return first.start == start and last.start + last.len - 1 == stop
end

-- Reading of items[i] from the word the segmentation puts it in, or nil:
-- nil when that word is the character alone, or has no reading in the words
-- table (自己: it decides nothing, and no other word does either). Also
-- returns the word, the index of its first item and an empty list (where
-- the other words of the same length were returned before #75).
function Resolve.word_reading(data, items, i)
    local w = Resolve.pathWord(data, items, i)
    if not w or w.len < 2 then return nil end
    local syllables = data:word(w.word)
    if syllables and #syllables == w.len then
        return syllables[i - w.start + 1], w.word, w.start, {}
    end
    return nil
end

-- Reading of items[i] from the longest fallback-dictionary word around it
-- (Wiktionary's, the only source main.lua attaches for readings: words
-- CC-CEDICT lacks; see Readings:prefetchFallback),
-- or nil. Also returns the word, the index of its first item and its cache
-- entry ({ source=, syllables= }). Only words that give the character one
-- reading count. When two words of the longest such length give it
-- different readings, nothing is decided (fallback words have no
-- frequencies to choose by), and shorter words are not consulted. A word
-- counts only if it splits no word of the segmentation's path (Resolve.fits).
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
                if reading and not Resolve.fits(data, items, start, stop) then reading = nil end
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
-- then annotated however common it is. A fifth value says what decided the
-- reading: "special", "word", "rule", "fallback" (a fallback-dictionary word
-- chose within the uncertainty pair), "pair" (the pair, or its first reading
-- alone) or "default" (nothing around the character decided: its default).
--
-- sp: the special word covering items[i] when the caller has already looked
-- it up (false for none); nil to look it up here.
--
-- In order: a special word (when `special` is given); the word the
-- segmentation puts it in, when that word has a reading (CC-CEDICT and
-- pypinyin; Resolve.word_reading); a context rule for the character
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
                marked, "special"
        end
        return nil
    end
    if not rank then return nil end
    local reading, word, start, others = Resolve.word_reading(data, items, i)
    if reading then
        return reading, rank, { word = word, start = start, len = utf8_len(word), others = others }, nil, "word"
    end
    reading = rule_reading(data, items, i)
    if reading then return reading, rank, nil, nil, "rule" end
    local first, second
    if data.uncertainty then first, second = data:uncertainty(item.text) end
    if first and second and first ~= second then
        -- A fallback-dictionary word may choose between the two (累世: lěi).
        local fallback, fword, fstart, fentry = Resolve.fallback_reading(data, items, i)
        if fallback == first or fallback == second then
            return fallback, rank, { word = fword, start = fstart, len = utf8_len(fword), others = {},
                                     fallback = fentry.source, syllables = fentry.syllables }, nil, "fallback"
        end
        uncertain = uncertain or Resolve.UNCERTAIN_BOTH
        if uncertain == Resolve.UNCERTAIN_SKIP then return nil end
        if uncertain == Resolve.UNCERTAIN_BEST then return first, rank, nil, nil, "pair" end
        return first .. "/" .. second, rank, nil, nil, "pair"
    end
    return default, rank, nil, nil, "default"
end

--[[--
Annotations for the on-page items.

  threshold: characters ranked above this (or unranked) are annotated.
  uncertain: Resolve.UNCERTAIN_BOTH (default), _BEST or _SKIP; see Resolve.reading.
  special: loaded special words (Data.loadSpecial) or nil. A character whose
    reading in a special word is unusual is annotated whatever its rank,
    with special=true; a rare character inside a special word takes the
    special word's reading.

Every occurrence on the page is annotated, each in the reading resolved at
its own position (刨 páo in 刨根, then bào in 刨子).

  marks: the reader's reading marks (ch_marks.lua), or nil. Applied to the
    reading resolved at each position (Marks:effect): a known one is never
    annotated (special words included); a remind one is annotated whatever
    the character's rank, at every occurrence. For the uncertainty pair:
    left bare only when both readings are known, annotated if either is
    remind. Marks change the pinyin drawn only, never Resolve.reading.

  spoken: draw 一 and 不 with their spoken tones (ch_sandhi.lua): yí gè, bú
    shì. The marks still apply to the dictionary reading (a known bù hides
    bú too); `dict` is then that reading.

Returns { {index=i, reading="tāo", rank=4396, match=..., special=bool,
dict="bù" or nil}, ... } in page order; match is the word that decided the
reading (see Resolve.reading), or nil.
]]
function Resolve.annotate(data, items, threshold, uncertain, special, marks, spoken)
    -- Rarity first: only a rare character, one with an unusual reading in a
    -- special word, or one with a remind mark, is worth resolving. The word
    -- frequencies of their runs are then fetched in one lookup for the whole
    -- page, and the words the segmentation puts them in in one more.
    local wanted, around = {}, {}
    for i, item in ipairs(items) do
        if item.on_page ~= false and single_char(item.text) then
            local sp = special and Resolve.special_at(special, items, i) or false
            local rank = data:char(item.text)
            if (sp and sp.entry.marks[sp.pos]) or rank == 0 or (rank and rank > threshold)
                    or (marks and marks:mayRemind(item.text)) then
                wanted[#wanted + 1] = { i, sp }
                if not sp then around[#around + 1] = i end
                -- The next syllable decides a spoken tone.
                if spoken and Sandhi.SPOKEN[item.text] and items[i + 1] then around[#around + 1] = i + 1 end
            end
        end
    end
    Resolve.prefetchRuns(data, items, around)
    if data.prefetch then
        local words = {}
        for _, i in ipairs(around) do
            local w = Resolve.pathWord(data, items, i)
            if w and w.len > 1 then words[#words + 1] = w.word end
        end
        if #words > 0 then data:prefetch(words) end
    end
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
    local out = {}
    for _, w in ipairs(wanted) do
        local i = w[1]
        local item = items[i]
        local reading, rank, match, marked = Resolve.reading(data, items, i, uncertain, special, w[2])
        local mark = marks and reading and marks:effect(item.text, reading) or nil
        if mark == "known" then reading = nil end
        local remind = mark == "remind"
        if reading and (marked or remind or rank == 0 or (rank and rank > threshold)) then
            local dict, sandhi
            if spoken and Sandhi.SPOKEN[item.text] then
                local said, rule = Sandhi.spoken(data, items, i, reading, match, function(j)
                    return (Resolve.reading(data, items, j, Resolve.UNCERTAIN_BEST, special))
                end)
                if said then reading, dict, sandhi = said, reading, rule end
            end
            -- Rarity used to decide what to drop when a line is crowded:
            -- unranked characters count as rarest.
            -- Unusual readings are kept like the rarest characters.
            out[#out + 1] = { index = i, reading = reading,
                              rank = (marked or remind or rank == 0) and math.huge or rank,
                              tie = data.publicRank and data:publicRank(item.text) or nil,
                              match = match, special = marked or nil, remind = remind or nil,
                              dict = dict, sandhi = sandhi }
        end
    end
    return out
end

-- The resolver's reading of a whole word ("dōng xi" for 东西), from the words
-- table, or nil when the dictionaries give it only one reading (so there is
-- nothing to choose). The popup marks this reading among a word's entries:
-- where the words table gives a rare character the toned one of a word
-- CC-CEDICT lists both ways (大爷 dà yé, drawn), the reading meant (dà ye).
function Resolve.wordReading(data, word)
    local mark = data.wordMark and data:wordMark(word)
    if mark then return mark end
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
relative to items[i], len=, syllables=, note= } or nil), unsure: true
when chosen is the uncertainty pair (no word or rule decided, nothing drawn),
so the popup does not call either reading likely, and source: what decided
the reading (Resolve.reading's fifth value; nil when there is no reading),
then the character's rank and whether the reading is an unusual one from a
special word (Resolve.reading's second and fourth values), for the mark
buttons (#26), and the word the segmentation puts the character in when it
is longer than the character: { word=, start= relative to items[i], len= }
(#75: the popup lists it first), or nil.
]]
function Resolve.forPopup(data, items, i, uncertain, special, drawn)
    if uncertain == Resolve.UNCERTAIN_SKIP then uncertain = Resolve.UNCERTAIN_BOTH end
    local reading, rank, match, unusual, source = Resolve.reading(data, items, i, uncertain, special)
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
    local w = Resolve.pathWord(data, items, i)
    local path = w and w.len > 1 and { word = w.word, start = w.start - i, len = w.len } or nil
    return reading, decided, unsure, source, rank, unusual, path
end

return Resolve
