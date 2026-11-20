--[[--
Reading marks (#26): a character in one reading marked **known** (its pinyin
never drawn) or **remind** (always drawn), in every book. Pure Lua: the file
store and the simplified-form lookups are passed in, so this is tested
offline (tests/test_marks.lua); main.lua gives the KOReader ones.

A mark is per character *and* reading, keyed by the character's simplified
form, so 這 and 这 share one. The reading is toned pinyin as the plugin draws
it (neutral tone unmarked: 了 le and 了 liǎo are separate marks).

The file (main.lua: settings/chinesehelper_marks.lua) holds
    { version = 1, marks = { ["行"] = { ["háng"] = "known" }, ... } }
It is read once and written only after a real change, so a missing or
unreadable file is never replaced at startup. An unreadable one (or one
from a newer format) is set aside before the first write, never overwritten.

  store.read()        -> data (table or nil), existed (the file was there)
  store.write(data)   -> true, or nil and an error
  store.setAside()    -> renames an unreadable file out of the way
  simplify(ch, reading) -> the simplified form to key ch in this reading
  variants(s)         -> the forms (s and its traditional forms) that can key to s
]]

local Marks = {}
Marks.__index = Marks

Marks.VERSION = 1
Marks.KNOWN = "known"
Marks.REMIND = "remind"
local CHECK = "\226\156\147"   -- ✓
Marks.CHECK = CHECK

function Marks.new(opts)
    local self = setmetatable({
        store = opts.store,
        simplify = opts.simplify or function(ch) return ch end,
        variants = opts.variants or function(s) return { s } end,
        marks = {},          -- key char -> { [reading] = state }
        forms = nil,         -- page form -> true: may key to a marked character
        remind_forms = nil,  -- page form -> true: may key to a character with a remind mark
        key_cache = {},
        loaded = false,
        unreadable = false,  -- the file exists but could not be used: set aside on the first write
        writes = 0,
    }, Marks)
    return self
end

local function valid(data)
    if type(data) ~= "table" or data.version ~= Marks.VERSION or type(data.marks) ~= "table" then return false end
    return true
end

-- Read the file once. Bad entries inside an otherwise good file are skipped.
function Marks:load()
    if self.loaded then return self end
    self.loaded = true
    local ok, data, existed = true, nil, false
    if self.store then ok, data, existed = pcall(self.store.read) end
    if not ok then data, existed = nil, true end
    if valid(data) then
        for ch, readings in pairs(data.marks) do
            if type(ch) == "string" and type(readings) == "table" then
                for reading, state in pairs(readings) do
                    if type(reading) == "string" and (state == Marks.KNOWN or state == Marks.REMIND) then
                        self.marks[ch] = self.marks[ch] or {}
                        self.marks[ch][reading] = state
                    end
                end
            end
        end
    elseif existed then
        -- There but unusable: not our format (a newer version, garbage), or
        -- {} from LuaSettings for a file it could not parse (with no usable
        -- .old). Set aside on the first write, never overwritten.
        self.unreadable = true
    end
    self:reindex()
    return self
end

-- The page forms that can key to a marked character.
function Marks:reindex()
    local forms, remind = {}, {}
    for s, readings in pairs(self.marks) do
        local has_remind = false
        for _, state in pairs(readings) do if state == Marks.REMIND then has_remind = true end end
        local ok, list = pcall(self.variants, s)
        if not ok or type(list) ~= "table" then list = { s } end
        local seen_self = false
        for _, f in ipairs(list) do
            forms[f] = true
            if has_remind then remind[f] = true end
            if f == s then seen_self = true end
        end
        if not seen_self then
            forms[s] = true
            if has_remind then remind[s] = true end
        end
    end
    self.forms, self.remind_forms = forms, remind
end

function Marks:key(ch, reading)
    local k = ch .. "\t" .. reading
    local s = self.key_cache[k]
    if s == nil then
        local ok, r = pcall(self.simplify, ch, reading)
        s = (ok and type(r) == "string" and r ~= "") and r or ch
        self.key_cache[k] = s
    end
    return s
end

-- Could `ch` (as it is on the page) have a mark? A table lookup: the check
-- run for every character the resolver annotates.
function Marks:mayHave(ch)
    self:load()
    return self.forms[ch] == true
end

-- Could `ch` have a remind mark in some reading?
function Marks:mayRemind(ch)
    self:load()
    return self.remind_forms[ch] == true
end

function Marks:get(ch, reading)
    self:load()
    if not reading or not self.forms[ch] then return nil end
    local readings = self.marks[self:key(ch, reading)]
    return readings and readings[reading] or nil
end

function Marks:data()
    local out = {}
    for s, readings in pairs(self.marks) do
        for reading, state in pairs(readings) do
            out[s] = out[s] or {}
            out[s][reading] = state
        end
    end
    return { version = Marks.VERSION, marks = out }
end

function Marks:save()
    if not self.store then return true end
    if self.unreadable then
        pcall(self.store.setAside)
        self.unreadable = false
    end
    local ok, res, err = pcall(self.store.write, self:data())
    if not ok then return nil, res end
    if not res then return nil, err end
    self.writes = self.writes + 1
    return true
end

-- Mark `ch` in `reading` known, remind, or (state nil) clear it. Writes the
-- file only when something changed. Returns true when it changed.
function Marks:set(ch, reading, state)
    self:load()
    if state ~= nil and state ~= Marks.KNOWN and state ~= Marks.REMIND then error("bad mark state: " .. tostring(state)) end
    local s = self:key(ch, reading)
    local readings = self.marks[s]
    local old = readings and readings[reading] or nil
    if old == state then return false end
    if state then
        readings = readings or {}
        readings[reading] = state
        self.marks[s] = readings
    else
        readings[reading] = nil
        if next(readings) == nil then self.marks[s] = nil end
    end
    self:reindex()
    local ok, err = self:save()
    if not ok then
        -- Keep memory and file in step: undo.
        if old then
            self.marks[s] = self.marks[s] or {}
            self.marks[s][reading] = old
        elseif self.marks[s] then
            self.marks[s][reading] = nil
            if next(self.marks[s]) == nil then self.marks[s] = nil end
        end
        self:reindex()
        return nil, err
    end
    return true
end

function Marks:clear(ch, reading) return self:set(ch, reading, nil) end

-- Clear a mark as Marks:list gives it (by its stored key).
function Marks:clearEntry(entry)
    self:load()
    self.key_cache[entry.char .. "\t" .. entry.reading] = entry.char
    return self:set(entry.char, entry.reading, nil)
end

-- Number of known and remind marks.
function Marks:count()
    self:load()
    local known, remind = 0, 0
    for _, readings in pairs(self.marks) do
        for _, state in pairs(readings) do
            if state == Marks.KNOWN then known = known + 1 else remind = remind + 1 end
        end
    end
    return known, remind
end

-- Every mark: { {char=, reading=, state=}, ... }, by character then reading.
function Marks:list()
    self:load()
    local out = {}
    for s, readings in pairs(self.marks) do
        for reading, state in pairs(readings) do out[#out + 1] = { char = s, reading = reading, state = state } end
    end
    table.sort(out, function(a, b)
        if a.char ~= b.char then return a.char < b.char end
        return a.reading < b.reading
    end)
    return out
end

function Marks:clearAll()
    self:load()
    if next(self.marks) == nil then return false end
    local old = self.marks
    self.marks = {}
    self:reindex()
    local ok, err = self:save()
    if not ok then
        self.marks = old
        self:reindex()
        return nil, err
    end
    return true
end

-- What a mark does to a reading as the resolver gives it: "known" (not
-- drawn), "remind" (drawn whatever the rank) or nil. For the uncertainty
-- pair ("xíng/háng"): known only when every reading in it is, remind when
-- any is.
function Marks:effect(ch, reading)
    if not reading or not self:mayHave(ch) then return nil end
    if not reading:find("/", 1, true) then return self:get(ch, reading) end
    local all_known, any_remind = true, false
    for r in reading:gmatch("[^/]+") do
        local m = self:get(ch, r)
        if m ~= Marks.KNOWN then all_known = false end
        if m == Marks.REMIND then any_remind = true end
    end
    if all_known then return Marks.KNOWN end
    if any_remind then return Marks.REMIND end
    return nil
end

--[[--
The mark button for `ch` in `reading`: { text=, next= } where next is the
state a tap sets (nil: clear). `drawn_by_rule`: the reading is drawn under
the current settings without any mark (rare, or unusual in a special word).
]]
function Marks:button(ch, reading, drawn_by_rule)
    local state = self:get(ch, reading)
    if state == Marks.KNOWN then return { text = "Known " .. reading .. " " .. CHECK, next = nil, state = state } end
    if state == Marks.REMIND then return { text = "Reminding " .. reading .. " " .. CHECK, next = nil, state = state } end
    if drawn_by_rule then return { text = "I know " .. reading, next = Marks.KNOWN } end
    return { text = "Remind me: " .. reading, next = Marks.REMIND }
end

return Marks
