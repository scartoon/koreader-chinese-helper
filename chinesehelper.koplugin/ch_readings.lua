-- The reading tables the resolver works from (pure Lua, no KOReader
-- dependencies). From pinyin_data.lua in koreader-interlinear-pinyin.
--
--   chars      char -> { rank, default reading }. rank: frequency rank in
--              modern written Chinese, 0 = not in the frequency list (very
--              rare). Every character with a known reading is here; only
--              those ranked above 1,000 (or 0) can be annotated.
--   words      word -> syllables, frequency (per billion words). 2-4
--              character words containing a polyphonic character, with
--              several dictionary readings, or giving a rare character a
--              neutral tone that is not its default (鼓捣 gǔ dao).
--   word_marks word -> the reading the tap popup marks, where it is not the
--              one in words: where CC-CEDICT lists a word both with and
--              without a neutral tone, words give a rare character the toned
--              one (大爷 dà yé, for the pinyin drawn), another dictionary
--              reading of the word (dà yé "idler"); the popup must mark dà ye
--              "uncle". A few dozen at most.
--   rules      context rules: the reading of a character when the character
--              immediately to its left (L) or right (R) is a given one.
--   uncertain  characters whose default reading is unreliable when neither a
--              word nor a rule decides: confidence, the two likeliest readings.
--
-- The plugin fills chars, rules and uncertain from the SQLite database when
-- the first page is drawn (they are needed for every character on a page),
-- with every word that contains a rare character (one that can be
-- annotated): those are all the words a page's annotations can need, so a
-- page turn never queries the database, as fast as the TSV tables of
-- interlinear-pinyin 0.5.0. Other words (common characters only, for the
-- popup) are looked up in the database on demand, in batches, and cached
-- (ch_db.lua). Tests and tools fill everything from the build's TSV files
-- (Readings.fromTsv). Either way the resolver sees the same object.

local Readings = {}
Readings.__index = Readings

Readings.MAX_WORD_LEN = 4
Readings.RARE_RANK = 1000      -- characters ranked above this (or unranked) can be annotated
Readings.CACHE_LIMIT = 20000   -- cached word lookups kept before the cache is reset

-- opts.word_lookup: function(list of words) -> { [word] = { "syllables", freq } }
-- for words not held in memory (nil: words come only from addWord). With a
-- lookup, the words in memory are taken to be every word that contains a
-- rare character: such a word that is not there does not exist.
function Readings.new(opts)
    opts = opts or {}
    return setmetatable({
        chars = {}, rules = {}, uncertain = {}, words = {}, word_freq = {}, word_marks = {},
        lookup = opts.word_lookup, cache = {}, cached = 0,
        max_word_len = Readings.MAX_WORD_LEN,
    }, Readings)
end

-- Does `word` contain a rare character (one that can be annotated)?
function Readings:hasRare(word)
    for ch in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local entry = self.chars[ch]
        if not entry or entry[1] == 0 or entry[1] > Readings.RARE_RANK then return true end
    end
    return false
end

-- Split on the space character only: %S depends on the C locale, and in some
-- (e.g. macOS UTF-8) byte 0xA0 counts as a space, which would cut "à" (C3 A0)
-- in half.
function Readings.syllables(s)
    local out = {}
    for syl in (s or ""):gmatch("[^ ]+") do out[#out + 1] = syl end
    return out
end

function Readings:addChar(ch, rank, reading)
    self.chars[ch] = { tonumber(rank) or 0, reading }
end

-- syllables: a table, or the space-separated string (split on first use).
function Readings:addWord(word, syllables, freq)
    self.words[word] = syllables
    local f = tonumber(freq)
    if f and f > 0 then self.word_freq[word] = f end
end

function Readings:addWordMark(word, syllables)
    self.word_marks[word] = syllables
end

-- The reading the popup marks for a word ("dà ye"), when it is not the one
-- in words; nil otherwise.
function Readings:wordMark(word)
    return self.word_marks[word]
end

function Readings:addRule(ch, side, neighbour, reading, n)
    local rules = self.rules[ch]
    if not rules then
        rules = {}
        self.rules[ch] = rules
    end
    rules[side .. neighbour] = { reading, tonumber(n) or 0 }
end

function Readings:addUncertain(ch, confidence, first, second)
    self.uncertain[ch] = { tonumber(confidence), first, second }
end

-- rank (0 = unranked), default reading; or nil for a character with no known
-- reading.
function Readings:char(ch)
    local entry = self.chars[ch]
    if not entry then return nil end
    return entry[1], entry[2]
end

-- Reading from a context rule for ch with the given neighbours (either may be
-- nil), or nil. When both sides have a rule and they disagree, the one learned
-- from more examples wins.
function Readings:rule(ch, left, right)
    local rules = self.rules[ch]
    if not rules then return nil end
    local l = left and rules["L" .. left]
    local r = right and rules["R" .. right]
    if l and r and l[1] ~= r[1] then
        return (r[2] > l[2]) and r[1] or l[1]
    end
    return (l or r) and (l or r)[1] or nil
end

-- The two most likely readings of an uncertain character (most likely first)
-- and the confidence in its default, or nil when the default is reliable.
function Readings:uncertainty(ch)
    local entry = self.uncertain[ch]
    if not entry then return nil end
    return entry[2], entry[3], entry[1]
end

-- Look up every word in `list` not yet known, in one call to word_lookup.
function Readings:prefetch(list)
    if not self.lookup then return end
    local missing, seen = {}, {}
    for _, w in ipairs(list) do
        if not self.words[w] and self.cache[w] == nil and not seen[w] and not self:hasRare(w) then
            seen[w] = true
            missing[#missing + 1] = w
        end
    end
    if #missing == 0 then return end
    if self.cached + #missing > Readings.CACHE_LIMIT then
        self.cache, self.cached = {}, 0
    end
    local found = self.lookup(missing) or {}
    for _, w in ipairs(missing) do
        local row = found[w]
        self.cache[w] = row and { Readings.syllables(row[1]), tonumber(row[2]) or 0 } or false
        self.cached = self.cached + 1
    end
end

-- Syllable list for a multi-character word and its frequency (per billion
-- words, 0 when unknown), or nil.
function Readings:word(word)
    local syllables = self.words[word]
    if syllables then
        if type(syllables) == "string" then
            syllables = Readings.syllables(syllables)
            self.words[word] = syllables
        end
        return syllables, self.word_freq[word] or 0
    end
    if not self.lookup or self:hasRare(word) then return nil end
    if self.cache[word] == nil then self:prefetch({ word }) end
    local hit = self.cache[word]
    if not hit then return nil end
    return hit[1], hit[2]
end

------------------------------------------------------------------------
-- Fallback dictionaries' words: words CC-CEDICT lacks, which pick one of an
-- uncertain character's two likely readings when no word, rule or special
-- word decides it (Resolve.fallback_reading). The plugin attaches
-- Wiktionary's only (MOE's Taiwan readings proved less reliable).
--
-- setFallback(lookup, key): lookup(list of words) returns the rows
-- { {simp=, trad=, pinyin=, source=}, ... } of the sources used, one source
-- per word, in priority order (main.lua's fallbackLookup);
-- key names those sources, and the cache is emptied when it changes. nil
-- lookup: no fallback words.
--
-- Each word is cached as { readings = { [k] = "lěi" or false }, source=,
-- syllables= } (or false when no source has it): readings[k] is the reading
-- of the word's k-th character when every row of the word agrees on it and
-- has a tone; false when the rows disagree (a character with two readings in
-- the word), a row's pinyin does not split into one Mandarin syllable per
-- character, or it is toneless or erhua.
------------------------------------------------------------------------

function Readings:setFallback(lookup, key)
    key = lookup and (key or "") or nil
    if key ~= self.fallback_key then
        self.fallback_key = key
        self.fb_cache, self.fb_cached = {}, 0
    end
    self.fallback = lookup
end

local function utf8_count(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

-- The cache entry for `word` built from its rows (all from one source).
local function fallbackEntry(word, rows)
    local Pinyin = require("ch_pinyin")
    local n = utf8_count(word)
    local readings, syllables = {}, nil
    for _, row in ipairs(rows) do
        local syl = Pinyin.splitJoined(row.pinyin, n)
        if not syl then
            for k = 1, n do readings[k] = false end
            break
        end
        syllables = syllables or table.concat(syl, " ")
        for k = 1, n do
            local r = syl[k]
            if r == "r" or r == Pinyin.stripTones(r) then r = false end
            if readings[k] == nil then
                readings[k] = r
            elseif readings[k] ~= r then
                readings[k] = false
            end
        end
    end
    for k = 1, n do if readings[k] == nil then readings[k] = false end end
    return { readings = readings, source = rows[1] and rows[1].source, syllables = syllables }
end

-- Look up every word in `list` not yet known, in one call to the lookup.
-- Words of the words table are skipped: a word there decides before any
-- fallback word is consulted.
function Readings:prefetchFallback(list)
    if not self.fallback then return end
    local missing, seen = {}, {}
    for _, w in ipairs(list) do
        if self.fb_cache[w] == nil and not seen[w] and not self.words[w] and not self.cache[w] then
            seen[w] = true
            missing[#missing + 1] = w
        end
    end
    if #missing == 0 then return end
    if self.fb_cached + #missing > Readings.CACHE_LIMIT then
        self.fb_cache, self.fb_cached = {}, 0
    end
    -- form -> rows of the first source that has it
    local by_form = {}
    for _, row in ipairs(self.fallback(missing) or {}) do
        for _, form in ipairs({ row.simp, row.trad }) do
            if form and seen[form] then
                local rows = by_form[form]
                if not rows then
                    rows = { source = row.source }
                    by_form[form] = rows
                end
                if rows.source == row.source and rows[#rows] ~= row then rows[#rows + 1] = row end
            end
        end
    end
    for _, w in ipairs(missing) do
        local rows = by_form[w]
        self.fb_cache[w] = rows and fallbackEntry(w, rows) or false
        self.fb_cached = self.fb_cached + 1
    end
end

-- The cached fallback entry for a word (see above), or nil.
function Readings:fallbackWord(word)
    if not self.fallback then return nil end
    if self.fb_cache[word] == nil then self:prefetchFallback({ word }) end
    return self.fb_cache[word] or nil
end

------------------------------------------------------------------------
-- Unusual readings of common characters ("special words"), used only
-- while that setting is on.
--
--   special  word, pinyin, marks, frequency, note. marks: one digit per
--            character, 1 = annotate it (its reading here is not its default).
--   guard    ordinary word, special word, offset: the ordinary word, starting
--            `offset` characters after the special word's first character
--            (negative: before it), blocks the special word: 订单, 单于, -1
--            for 订单于3日发货.
--
-- { by_first = { [char] = { entry, ... } },
--   guard = { ["订单\t单于\t-1"] = true, ... },
--   max_len=, count=, guard_count= }
-- entry = { word=, chars={...}, syllables={...}, marks={bool...}, freq=, note= }
------------------------------------------------------------------------

local function utf8_chars(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

function Readings.newSpecial()
    return { by_first = {}, guard = {}, max_len = 1, count = 0, guard_count = 0 }
end

function Readings.addSpecial(special, word, pinyin, marks, freq, note)
    local chars = utf8_chars(word)
    local syllables = Readings.syllables(pinyin)
    if #syllables ~= #chars or #marks ~= #chars then return false end
    local flags = {}
    for k = 1, #marks do flags[k] = marks:sub(k, k) == "1" end
    local entry = { word = word, chars = chars, syllables = syllables, marks = flags,
                    freq = tonumber(freq) or 0, note = (note and note ~= "" and note or nil) }
    local list = special.by_first[chars[1]]
    if not list then
        list = {}
        special.by_first[chars[1]] = list
    end
    list[#list + 1] = entry
    if #chars > special.max_len then special.max_len = #chars end
    special.count = special.count + 1
    return true
end

-- One flat set of whole "ordinary<TAB>special<TAB>offset" keys: much smaller
-- than a table per word.
function Readings.addGuard(special, ordinary, word, offset)
    special.guard[ordinary .. "\t" .. word .. "\t" .. tostring(math.floor(tonumber(offset) or 0))] = true
    special.guard_count = special.guard_count + 1
end

------------------------------------------------------------------------
-- Loading from the build's TSV files (tests and tools; the plugin reads the
-- same tables from SQLite).
------------------------------------------------------------------------

local function read_lines(path, fn)
    local f = path and io.open(path, "r")
    if not f then return false end
    for line in f:lines() do fn(line) end
    f:close()
    return true
end

-- paths: { chars=, words=, word_marks=, rules=, uncertain= }; only chars is required.
function Readings.fromTsv(paths)
    local self = Readings.new()
    local ok = read_lines(paths.chars, function(line)
        local ch, rank, reading = line:match("^([^\t]+)\t(%d+)\t([^\t\r]+)")
        if ch then self:addChar(ch, rank, reading) end
    end)
    if not ok then return nil, "missing " .. tostring(paths.chars) end
    read_lines(paths.words, function(line)
        local word, readings, freq = line:match("^([^\t]+)\t([^\t\r]+)\t?(%d*)")
        if word then self:addWord(word, readings, freq) end
    end)
    read_lines(paths.word_marks, function(line)
        local word, syllables = line:match("^([^\t]+)\t([^\t\r]+)")
        if word then self:addWordMark(word, syllables) end
    end)
    read_lines(paths.rules, function(line)
        local ch, side, neighbour, reading, n = line:match("^([^\t]+)\t([LR])\t([^\t]+)\t([^\t\r]+)\t?(%d*)")
        if ch then self:addRule(ch, side, neighbour, reading, n) end
    end)
    read_lines(paths.uncertain, function(line)
        local ch, confidence, first, second = line:match("^([^\t]+)\t([%d.]+)\t([^\t]+)\t([^\t\r]+)")
        if ch then self:addUncertain(ch, confidence, first, second) end
    end)
    return self
end

-- paths: { special=, guard= }
function Readings.specialFromTsv(paths)
    local special = Readings.newSpecial()
    local ok = read_lines(paths.special, function(line)
        local word, pinyin, marks, freq, note = line:match("^([^\t]+)\t([^\t]+)\t([01]+)\t(%d*)\t?([^\r]*)")
        if word then Readings.addSpecial(special, word, pinyin, marks, freq, note) end
    end)
    if not ok then return nil, "missing " .. tostring(paths.special) end
    read_lines(paths.guard, function(line)
        local ordinary, word, offset = line:match("^([^\t#]+)\t([^\t]+)\t(%-?%d+)$")
        if ordinary then Readings.addGuard(special, ordinary, word, offset) end
    end)
    return special
end

return Readings
