-- The reading tables the resolver works from (pure Lua, no KOReader
-- dependencies). From pinyin_data.lua in koreader-interlinear-pinyin.
--
--   chars      char -> { rank, default reading }. rank: frequency rank in
--              modern written Chinese, 0 = not in the frequency list (very
--              rare). Every character with a known reading is here; only
--              those ranked above 1,000 (or 0) can be annotated.
--   words      word -> syllables, frequency (per billion words). 2-4
--              character words containing a polyphonic character, or with
--              several dictionary readings.
--   rules      context rules: the reading of a character when the character
--              immediately to its left (L) or right (R) is a given one.
--   uncertain  characters whose default reading is unreliable when neither a
--              word nor a rule decides: confidence, the two likeliest readings.
--
-- The plugin fills chars, rules and uncertain from the SQLite database when
-- the first page is drawn (they are needed for every character on a page)
-- and looks words up in the database on demand, in batches, caching the
-- answers (ch_db.lua). Tests and tools fill everything from the build's TSV
-- files (Readings.fromTsv). Either way the resolver sees the same object.

local Readings = {}
Readings.__index = Readings

Readings.MAX_WORD_LEN = 4
Readings.CACHE_LIMIT = 20000   -- cached word lookups kept before the cache is reset

-- opts.word_lookup: function(list of words) -> { [word] = { "syllables", freq } }
-- for words not held in memory (nil: words come only from addWord).
function Readings.new(opts)
    opts = opts or {}
    return setmetatable({
        chars = {}, rules = {}, uncertain = {}, words = {}, word_freq = {},
        lookup = opts.word_lookup, cache = {}, cached = 0,
        max_word_len = Readings.MAX_WORD_LEN,
    }, Readings)
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

function Readings:addWord(word, syllables, freq)
    self.words[word] = type(syllables) == "table" and syllables or Readings.syllables(syllables)
    local f = tonumber(freq)
    if f and f > 0 then self.word_freq[word] = f end
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
        if not self.words[w] and self.cache[w] == nil and not seen[w] then
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
    if syllables then return syllables, self.word_freq[word] or 0 end
    if not self.lookup then return nil end
    if self.cache[word] == nil then self:prefetch({ word }) end
    local hit = self.cache[word]
    if not hit then return nil end
    return hit[1], hit[2]
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

-- paths: { chars=, words=, rules=, uncertain= }; only chars is required.
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
