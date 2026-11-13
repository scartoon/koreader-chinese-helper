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
Model.MARK_UNSURE = "one of these"   -- the uncertainty pair: no word or rule decided

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
                          seen = seen, order = #kept + 1, proper = pinyin:match("^%u") ~= nil,
                          source = row.source or "cedict" }
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

-- Move marked entries to the front: in the resolver's order when several
-- readings were chosen ("lěi/léi": lěi first; e.rank, set while marking),
-- otherwise keeping their order. The unmarked keep their order.
local function markedFirst(entries)
    local marked, out = {}, {}
    for k, e in ipairs(entries) do if e.marked then marked[#marked + 1] = { e, e.rank or 0, k } end end
    table.sort(marked, function(a, b)
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[3] < b[3]
    end)
    for _, m in ipairs(marked) do
        m[1].rank = nil
        out[#out + 1] = m[1]
    end
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
--      (西 in 东西 dōngxi: 西's own entry xī; 捣 drawn dao in 鼓捣: dǎo).
--      Where several tones have those letters (糊 hù, hú, hū for 含糊 hu),
--      only `prefer` (the character's default reading) when it is one of them.
-- `value` is what marked is set to. Returns whether anything was marked.
local function markMatching(entries, chosen, value, prefer)
    local want = Pinyin.lower(chosen)
    local neutral = want == Pinyin.stripTones(want)
    local function sameLetters(e) return neutral and Pinyin.stripTones(Pinyin.lower(e.syllables)) == want end
    local narrowed = false
    if neutral and prefer and prefer ~= "" then
        prefer = Pinyin.lower(prefer)
        for _, e in ipairs(entries) do
            if sameLetters(e) and Pinyin.lower(e.syllables) == prefer then narrowed = true end
        end
    end
    local tests = {
        function(e) return Pinyin.lower(e.syllables) == want end,
        function(e) return Pinyin.matches(e.syllables, want) end,
        function(e) return sameLetters(e) and (not narrowed or Pinyin.lower(e.syllables) == prefer) end,
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

------------------------------------------------------------------------
-- Fallback dictionaries (Wiktionary and Wikipedia titles in the plugin
-- database; CBDB, MOE and Moegirlpedia in the user's optional files):
-- consulted only for candidate words CC-CEDICT has no row for, one source
-- per word.
------------------------------------------------------------------------

-- After CC-CEDICT, in this order (the default; Settings:fallbackOrder() can
-- change it, passed to Model.matches as args.order).
Model.SOURCE_ORDER = { "wikt", "cbdb", "moe", "wp", "moegirl" }
-- Sources whose readings are generated (pypinyin), not the source's own:
-- the popup says so.
Model.GENERATED_READING = { wp = true, moegirl = true }
Model.GENERATED_NOTE = "generated pinyin"

-- The candidate words (texts) no CC-CEDICT row covers, in their order.
function Model.uncovered(texts, rows)
    local covered = {}
    for _, row in ipairs(rows or {}) do
        covered[row.simp or ""], covered[row.trad or ""] = true, true
    end
    local out = {}
    for _, t in ipairs(texts) do
        if not covered[t] then out[#out + 1] = t end
    end
    return out
end

-- From one source's rows for `remaining` (a list of words), the rows to use
-- and the words still without an entry: a word one source has is not looked
-- up in the next.
function Model.takeFallback(remaining, rows)
    local wanted, taken = {}, {}
    for _, t in ipairs(remaining) do wanted[t] = true end
    local kept = {}
    for _, row in ipairs(rows or {}) do
        local hit = false
        for _, form in ipairs({ row.simp, row.trad }) do
            if form and wanted[form] then
                taken[form] = true
                hit = true
            end
        end
        if hit then kept[#kept + 1] = row end
    end
    local left = {}
    for _, t in ipairs(remaining) do
        if not taken[t] then left[#left + 1] = t end
    end
    return kept, left
end

--[[--
The popup's matches.

  args.cands        Text.candidates' first result
  args.rows         rows for the candidates ({simp, trad, pinyin, syllables, defs,
                    source}): CC-CEDICT's (source nil or "cedict") and the
                    fallback dictionaries' ("wikt", "wp", "cbdb", "moe",
                    "moegirl"). For each word, CC-CEDICT's rows win;
                    otherwise the first source in args.order (default
                    Model.SOURCE_ORDER) that has the word gives its rows.
  args.order        the fallback dictionaries' priority, or nil
  args.chosen       the resolver's reading of the tapped character ("dào", or a
                    pair "chéng/shèng"), or nil
  args.default      the tapped character's default reading, or nil: which of
                    several same-letter tones a neutral `chosen` stands for
  args.annotated    true when that reading is drawn above the character
  args.unsure       true when `chosen` is the uncertainty pair (no word or rule
                    decided; Resolve.forPopup): its readings are marked
                    Model.MARK_UNSURE, not "likely here"
  args.decided      the word that decided it, or nil:
                    { word=, start= (relative to the tapped character), len=,
                      syllables= (the resolver's reading of the word), note= }
  args.wordReading  function(word) -> the resolver's reading of a word ("dōng xi")
                    or nil

Returns { {word=, start=, len=, entries={...}, decided=bool, note=, mark=}, ... }
(mark: Model.MARK_UNSURE on the tapped character's own match when its
readings are the uncertainty pair; nil otherwise).
Each entry: { pinyin=, syllables=, senses={...}, proper=bool, marked=bool,
missing=bool (a chosen reading CC-CEDICT does not list), source= ("cedict",
"wikt", "wp", "cbdb", "moe", "moegirl") }. Reading markers (and the "decides" tag's test for a choice
of readings) only ever apply to CC-CEDICT entries: a fallback entry shows its
source's own reading, unmarked.
]]
function Model.matches(args)
    -- form -> source -> rows
    local by_form = {}
    for _, row in ipairs(args.rows or {}) do
        local source = row.source or "cedict"
        for _, form in ipairs({ row.simp, row.trad }) do
            if form then
                local sources = by_form[form]
                if not sources then
                    sources = {}
                    by_form[form] = sources
                end
                local list = sources[source]
                if not list then
                    list = {}
                    sources[source] = list
                end
                if list[#list] ~= row then list[#list + 1] = row end
            end
        end
    end
    local function rowsFor(form)
        local sources = by_form[form]
        if not sources then return nil end
        if sources.cedict then return sources.cedict end
        for _, s in ipairs(args.order or Model.SOURCE_ORDER) do
            if sources[s] then return sources[s] end
        end
        return nil
    end
    local decided = args.decided
    local anchor, words, have_decided = nil, {}, false
    for _, c in ipairs(args.cands or {}) do
        local list = rowsFor(c.text)
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

    -- A word whose entries are CC-CEDICT's (the resolver's own reading lines
    -- count as CC-CEDICT's side), not a fallback dictionary's.
    local function fromCedict(m)
        for _, e in ipairs(m.entries) do
            if e.source == "cedict" then return true end
        end
        return false
    end
    -- A reading CC-CEDICT gives the tapped character only with a tone: a
    -- word's neutral tone (猬 wèi, drawn wei in 刺猬). Then even a character
    -- with one reading has its entry marked and the word that decided it
    -- tagged, so the popup says why the pinyin drawn differs from the entry.
    local toneless = false
    if anchor and args.chosen and not args.chosen:find("/", 1, true) then
        local want = Pinyin.lower(args.chosen)
        if want ~= "" and want == Pinyin.stripTones(want) then
            toneless = true
            for _, e in ipairs(anchor.entries) do
                if Pinyin.lower(e.syllables) == want then toneless = false end
            end
        end
    end
    -- The tapped character: mark the resolver's reading(s).
    if anchor and fromCedict(anchor) and args.chosen and args.chosen ~= "" then
        local entries = anchor.entries
        local several = distinctReadings(entries) > 1 or toneless
        local rank = 0
        for reading in args.chosen:gmatch("[^/]+") do
            rank = rank + 1
            if not markMatching(entries, reading, several or nil, args.default) then
                -- A reading CC-CEDICT does not list for the character itself
                -- (it may come from a pypinyin phrase): shown, with no senses.
                entries[#entries + 1] = { pinyin = reading, syllables = reading, senses = {},
                                          missing = true, marked = true, source = "cedict" }
            end
            for _, e in ipairs(entries) do
                if e.marked and not e.rank then e.rank = rank end
            end
        end
        anchor.entries = markedFirst(entries)
        -- Nothing decided between the pair: neither reading is "likely".
        if args.unsure and not args.annotated then anchor.mark = Model.MARK_UNSURE end
    end
    -- Each word: mark the resolver's reading when there is a choice.
    for _, m in ipairs(words) do
        if fromCedict(m) and (distinctReadings(m.entries) > 1 or (toneless and m.decided)) then
            local chosen = (m.decided and decided.syllables)
                or (args.wordReading and args.wordReading(m.word))
            if chosen and markMatching(m.entries, chosen, true) then
                m.entries = markedFirst(m.entries)
            end
        end
    end
    -- "Decides X's reading" only means something when X has a choice of
    -- readings (人 in 行人 has one); the word itself stays listed.
    local choice = anchor and fromCedict(anchor) and (distinctReadings(anchor.entries) > 1 or toneless)
    if not choice then
        for _, m in ipairs(words) do m.decided = nil end
    end
    if anchor then table.insert(words, 1, anchor) end
    return words
end

-- Short names of the dictionaries, shown as the entries' source labels.
-- (Moegirlpedia is "Moegirl", not "Moe", which would read as MOE.)
Model.SOURCE_LABELS = { cedict = "CEDICT", wikt = "Wikt", wp = "WP", cbdb = "CBDB", moe = "MOE",
                        moegirl = "Moegirl" }

--[[--
The popup's content as blocks, one per match:
  { head = "**宛**  yuān · shown above" (the word, its first reading, markers),
    source = "cedict" / "wikt" / "wp" / "cbdb" / "moe" / "moegirl" (whose entry it is),
    lines = { "winding; as if", "wǎn: ...", ... } (senses, further readings) }
b0/b1 are the bold markers (TextBoxWidget's PTF markers in KOReader).
The tapped character's marked readings are "shown above" when `annotated`,
"one of these" when Model.matches set m.mark (the uncertainty pair), and
"likely here" otherwise. A reading a source does not give itself
(Model.GENERATED_READING) is followed by "· generated pinyin".
]]
function Model.blocks(matches, char, annotated, b0, b1)
    b0, b1 = b0 or "", b1 or ""
    local default_mark = annotated and Model.MARK_SHOWN or Model.MARK_LIKELY
    local blocks = {}
    for _, m in ipairs(matches) do
        local block = { lines = {} }
        local mark = " · " .. (m.mark or default_mark)
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
            if Model.GENERATED_READING[e.source or ""] and e.pinyin ~= "" then
                marked = marked .. " · " .. Model.GENERATED_NOTE
            end
            if k == 1 then
                local tag = m.decided and (" · decides " .. char .. "'s reading") or ""
                block.head = b0 .. m.word .. b1 .. "  " .. e.pinyin .. marked .. tag
                block.source = e.source or "cedict"
                block.lines[#block.lines + 1] = senses
            else
                block.lines[#block.lines + 1] = e.pinyin .. marked .. ": " .. senses
            end
        end
        blocks[#blocks + 1] = block
    end
    return blocks
end

--[[--
The popup text, without source labels. One block per match, separated by a
blank line:

  **宛**  yuān · shown above
  winding; as if
  wǎn: ...

  **大宛**  Dàyuān · decides 宛's reading
  Dayuan, ancient state of Central Asia
]]
function Model.render(matches, char, annotated, b0, b1)
    local out = {}
    for _, block in ipairs(Model.blocks(matches, char, annotated, b0, b1)) do
        out[#out + 1] = block.head .. "\n" .. table.concat(block.lines, "\n")
    end
    return table.concat(out, "\n\n")
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
