-- What the tap popup shows (pure Lua, no KOReader dependencies, tested
-- offline). Ordering and row cleaning come from koreader-chinese-popup
-- (cp_text.lua); the reading markers and the deciding word from
-- koreader-interlinear-pinyin's popup (pinyin_defs.lua).
--
--   * the tapped character's own entry first (the anchor), with every
--     reading; the resolver's reading for this occurrence marked and first;
--   * then every dictionary word around it that contains it, longest first,
--     ties broken by the earlier start; a word with several readings has the
--     resolver's reading of that word marked and first;
--   * the word that decided the character's reading tagged (when the
--     character has a choice of readings), and listed even when CC-CEDICT
--     lacks it (a pypinyin phrase, or a special word with a note such as 冒顿).

local Pinyin = require("ch_pinyin")

local Model = {}

Model.MARK_SHOWN = "shown above"     -- the reading drawn above the character
Model.MARK_LIKELY = "likely here"    -- the resolver's reading, nothing drawn

-- A sense that only says the entry is a variant of the very word being shown
-- ("variant of 着 zháo" on a 着 entry) tells the reader nothing.
local function selfVariant(sense, word)
    local target = sense:match("^[%a ]*variant of (%S+)")
    return target ~= nil and target == word
end

--[[--
Entries for one word from its CC-CEDICT rows: self-referring variant senses
dropped (and rows left with none), rows with the same pinyin merged (歷 and
曆 are both lì), ordinary readings before capitalised ones (surnames, place
names), CC-CEDICT's order otherwise.
Returns { {pinyin=, syllables=, senses={...}, proper=bool}, ... }.
]]
function Model.cleanRows(word, rows)
    local kept, by_pinyin = {}, {}
    for _, row in ipairs(rows) do
        local senses = {}
        for sense in (row.defs or ""):gmatch("[^/]+") do
            if not selfVariant(sense, word) then senses[#senses + 1] = sense end
        end
        if #senses > 0 then
            local pinyin = row.pinyin or ""
            local entry = by_pinyin[pinyin]
            if entry then
                for _, s in ipairs(senses) do
                    if not entry.seen[s] then
                        entry.seen[s] = true
                        entry.senses[#entry.senses + 1] = s
                    end
                end
            else
                local seen = {}
                for _, s in ipairs(senses) do seen[s] = true end
                entry = { pinyin = pinyin, syllables = row.syllables or pinyin, senses = senses,
                          seen = seen, order = #kept + 1, proper = pinyin:match("^%u") ~= nil }
                by_pinyin[pinyin] = entry
                kept[#kept + 1] = entry
            end
        end
    end
    table.sort(kept, function(a, b)
        if a.proper ~= b.proper then return not a.proper end
        return a.order < b.order
    end)
    for _, e in ipairs(kept) do e.seen, e.order = nil, nil end
    return kept
end

-- Number of distinct readings (case-insensitive: the surname Wǎn and wǎn are
-- one reading to choose).
local function distinctReadings(entries)
    local seen, n = {}, 0
    for _, e in ipairs(entries) do
        local key = Pinyin.lower(e.syllables or e.pinyin)
        if not seen[key] then
            seen[key] = true
            n = n + 1
        end
    end
    return n
end

-- Move marked entries to the front, keeping the order otherwise.
local function markedFirst(entries)
    local out = {}
    for _, e in ipairs(entries) do if e.marked then out[#out + 1] = e end end
    for _, e in ipairs(entries) do if not e.marked then out[#out + 1] = e end end
    return out
end

-- Mark the entries that stand for `chosen` (syllables, e.g. "dōng xi"), in
-- passes, stopping at the first that marks anything:
--   1. the same reading (case aside), ordinary entries before proper nouns
--      (a surname Lè is marked only when no ordinary lè exists);
--   2. a dictionary neutral tone standing for the chosen toned reading
--      (鼓捣 "gǔ dao" for gǔ dǎo), only when no entry has it exactly
--      (不是 bùshì "is not" must not also mark bùshi "fault");
--   3. a neutral chosen reading standing for the entry with the same letters
--      (西 in 东西 dōngxi: 西's own entry xī).
-- `value` is what marked is set to. Returns whether anything was marked.
local function markMatching(entries, chosen, value)
    local want = Pinyin.lower(chosen)
    local neutral = want == Pinyin.stripTones(want)
    local tests = {
        function(e) return Pinyin.lower(e.syllables) == want end,
        function(e) return Pinyin.matches(e.syllables, want) end,
        function(e) return neutral and Pinyin.stripTones(Pinyin.lower(e.syllables)) == want end,
    }
    for _, test in ipairs(tests) do
        for _, proper in ipairs({ false, true }) do
            local found = false
            for _, e in ipairs(entries) do
                if (e.proper or false) == proper and test(e) then
                    e.marked = value
                    found = true
                end
            end
            if found then return true end
        end
    end
    return false
end

--[[--
The popup's matches.

  args.cands        Text.candidates' first result
  args.rows         CC-CEDICT rows for the candidates ({simp, trad, pinyin, syllables, defs})
  args.chosen       the resolver's reading of the tapped character ("dào", or a
                    pair "chéng/shèng"), or nil
  args.annotated    true when that reading is drawn above the character
  args.decided      the word that decided it, or nil:
                    { word=, start= (relative to the tapped character), len=,
                      syllables= (the resolver's reading of the word), note= }
  args.wordReading  function(word) -> the resolver's reading of a word ("dōng xi")
                    or nil

Returns { {word=, start=, len=, entries={...}, decided=bool, note=}, ... }.
Each entry: { pinyin=, syllables=, senses={...}, proper=bool, marked=bool,
missing=bool (a chosen reading CC-CEDICT does not list) }.
]]
function Model.matches(args)
    local by_form = {}
    for _, row in ipairs(args.rows or {}) do
        for _, form in ipairs({ row.simp, row.trad }) do
            if form then
                local list = by_form[form]
                if not list then
                    list = {}
                    by_form[form] = list
                end
                if list[#list] ~= row then list[#list + 1] = row end
            end
        end
    end
    local decided = args.decided
    local anchor, words, have_decided = nil, {}, false
    for _, c in ipairs(args.cands or {}) do
        local list = by_form[c.text]
        local entries = list and Model.cleanRows(c.text, list) or {}
        local m = { word = c.text, start = c.start, len = c.len, entries = entries }
        local is_decided = decided ~= nil and c.text == decided.word and c.start == decided.start
        if is_decided then
            m.decided, m.note = true, decided.note
            have_decided = true
            if #entries == 0 then
                -- Known only to the resolver (pypinyin's phrases, special words).
                m.entries = { { pinyin = decided.syllables or "", syllables = decided.syllables or "",
                                senses = {}, missing = true } }
            end
        end
        if #m.entries > 0 then
            if c.len == 1 then anchor = m else words[#words + 1] = m end
        end
    end
    if decided and not have_decided and decided.word and decided.len and decided.len > 1 then
        -- The deciding word reaches past the popup's context (it should not:
        -- words are at most 4 characters, the context 7), listed anyway.
        words[#words + 1] = { word = decided.word, start = decided.start or 0, len = decided.len,
                              decided = true, note = decided.note,
                              entries = { { pinyin = decided.syllables or "", syllables = decided.syllables or "",
                                            senses = {}, missing = true } } }
    end
    table.sort(words, function(a, b)
        if a.len ~= b.len then return a.len > b.len end
        return a.start < b.start
    end)

    -- The tapped character: mark the resolver's reading(s).
    if anchor and args.chosen and args.chosen ~= "" then
        local entries = anchor.entries
        local several = distinctReadings(entries) > 1
        for reading in args.chosen:gmatch("[^/]+") do
            if not markMatching(entries, reading, several or nil) then
                -- A reading CC-CEDICT does not list for the character itself
                -- (it may come from a pypinyin phrase): shown, with no senses.
                entries[#entries + 1] = { pinyin = reading, syllables = reading, senses = {},
                                          missing = true, marked = true }
            end
        end
        anchor.entries = markedFirst(entries)
    end
    -- Each word: mark the resolver's reading when there is a choice.
    for _, m in ipairs(words) do
        if distinctReadings(m.entries) > 1 then
            local chosen = (m.decided and decided.syllables)
                or (args.wordReading and args.wordReading(m.word))
            if chosen and markMatching(m.entries, chosen, true) then
                m.entries = markedFirst(m.entries)
            end
        end
    end
    -- "Decides X's reading" only means something when X has a choice of
    -- readings (人 in 行人 has one); the word itself stays listed.
    local choice = anchor and distinctReadings(anchor.entries) > 1
    if not choice then
        for _, m in ipairs(words) do m.decided = nil end
    end
    if anchor then table.insert(words, 1, anchor) end
    return words
end

--[[--
The popup text. b0/b1 are the bold markers (TextBoxWidget's PTF markers in
KOReader). One block per match, separated by a blank line:

  **宛**  yuān · shown above
  winding; as if
  wǎn: ...

  **大宛**  Dàyuān · decides 宛's reading
  Dayuan, ancient state of Central Asia
]]
function Model.render(matches, char, annotated, b0, b1)
    b0, b1 = b0 or "", b1 or ""
    local mark = " · " .. (annotated and Model.MARK_SHOWN or Model.MARK_LIKELY)
    local blocks = {}
    for _, m in ipairs(matches) do
        local lines = {}
        for k, e in ipairs(m.entries) do
            local senses = table.concat(e.senses, "; ")
            if #e.senses == 0 then
                if m.note then
                    senses = m.note
                elseif m.len == 1 then
                    senses = "no separate CC-CEDICT entry for this reading"
                else
                    senses = "no definition in CC-CEDICT"
                end
            end
            local marked = e.marked and (m.len == 1 and mark or (" · " .. Model.MARK_LIKELY)) or ""
            if k == 1 then
                local tag = m.decided and (" · decides " .. char .. "'s reading") or ""
                lines[#lines + 1] = b0 .. m.word .. b1 .. "  " .. e.pinyin .. marked .. tag
                lines[#lines + 1] = senses
            else
                lines[#lines + 1] = e.pinyin .. marked .. ": " .. senses
            end
        end
        blocks[#blocks + 1] = table.concat(lines, "\n")
    end
    return table.concat(blocks, "\n\n")
end

-- The phrase around the tapped character with the character in bold: the
-- header shown when the popup covers the text.
function Model.header(left, char, right, b0, b1)
    return table.concat(left or {}) .. (b0 or "") .. char .. (b1 or "") .. table.concat(right or {})
end

--[[--
Where a popup of height h goes (pure arithmetic; ch_popup.lua uses it).

  screen_h, margin  screen height and the margin kept top and bottom
  box               the tapped character's screen box, or nil
Returns y, covers: the popup's top, and whether it covers the character's line.
A popup that fits in half the screen goes in the half away from the
character, against that half's outer edge; anything taller is centred.
]]
function Model.place(h, screen_h, margin, box)
    local half = screen_h / 2
    local y
    if box and h <= half - margin then
        local centre = box.y + box.h / 2
        if centre < half then
            y = screen_h - margin - h      -- character in the top half: bottom half
        else
            y = margin                     -- character in the bottom half: top half
        end
    else
        y = math.floor((screen_h - h) / 2)
    end
    y = math.max(margin, math.min(y, screen_h - margin - h))
    local covers = box ~= nil and y < box.y + box.h and y + h > box.y
    return y, covers
end

return Model
