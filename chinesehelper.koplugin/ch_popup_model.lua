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

Model.MARK_LIKELY = "likely here"    -- the resolver's reading, nothing drawn
Model.MARK_UNSURE = ""               -- the uncertainty pair or the default: nothing decided, so no marker
-- What may make a reading "likely here" (Resolve.forPopup's source).
Model.EVIDENCE = { word = true, special = true, fallback = true, rule = true }
-- A reading drawn on the page gets no marker either: the reader can see it.

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
-- database; CBDB, MOE, the 成語典, Xinhua idioms and Moegirlpedia in the
-- user's optional files):
-- consulted only for candidate words CC-CEDICT has no row for, one source
-- per word.
------------------------------------------------------------------------

-- After CC-CEDICT, in this order (the default; Settings:fallbackOrder() can
-- change it, passed to Model.matches as args.order).
Model.SOURCE_ORDER = { "wikt", "cbdb", "moe", "idioms", "xinhua", "wp", "moegirl" }
-- Sources whose readings are generated (pypinyin), not the source's own:
-- the popup says so.
Model.GENERATED_READING = { wp = true, moegirl = true }
Model.GENERATED_NOTE = "generated pinyin"
-- After an Always entry's reading that CC-CEDICT does not list for that word.
Model.NOT_CEDICT = "not in CC-CEDICT"

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
  args.always       MOE's rows for the words it shows Always (main.lua
                    fallbackLookup's second value), or nil: a match whose
                    entries are not MOE's own gets them as m.always (entries
                    as cleanRows gives them; a reading CC-CEDICT does not
                    list for that word has notcedict = true). Never read
                    by the reading markers.
  args.chosen       the resolver's reading of the tapped character ("dào", or a
                    pair "chéng/shèng"), or nil
  args.default      the tapped character's default reading, or nil: which of
                    several same-letter tones a neutral `chosen` stands for
  args.annotated    true when that reading is drawn above the character
  args.unsure       true when `chosen` is the uncertainty pair (no word or rule
                    decided; Resolve.forPopup): its readings are marked
                    Model.MARK_UNSURE, not "likely here"
  args.source       what decided `chosen` (Resolve.forPopup's `source`): unless
                    it is a word, special word, fallback word or context rule
                    (Model.EVIDENCE), the reading is just the character's
                    default and gets no label either (#16). nil: not known
                    (treated as evidence)
  args.decided      the word that decided it, or nil:
                    { word=, start= (relative to the tapped character), len=,
                      syllables= (the resolver's reading of the word), note= }
  args.wordReading  function(word) -> the resolver's reading of a word ("dōng xi")
                    or nil

Returns { {word=, start=, len=, entries={...}, always=, decided=bool, note=, mark=}, ... }
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
        if sources.cedict then return sources.cedict, "cedict" end
        for _, s in ipairs(args.order or Model.SOURCE_ORDER) do
            if sources[s] then return sources[s], s end
        end
        return nil
    end
    local always_by_form = {}
    for _, row in ipairs(args.always or {}) do
        for _, form in ipairs({ row.simp, row.trad }) do
            if form then
                local list = always_by_form[form] or {}
                always_by_form[form] = list
                if list[#list] ~= row then list[#list + 1] = row end
            end
        end
    end
    -- MOE's Always entries for a word whose own entries (from `source`) are
    -- not MOE's; MOE readings CC-CEDICT lacks for it marked notcedict.
    local function alwaysFor(text, source, entries)
        local list = always_by_form[text]
        if not list or source == list[1].source then return nil end
        local out = Model.cleanRows(text, list)
        if #out == 0 then return nil end
        if source == "cedict" then
            local known = {}
            for _, e in ipairs(entries) do known[Pinyin.lower(e.syllables or e.pinyin or "")] = true end
            for _, e in ipairs(out) do
                local reading = (e.syllables ~= nil and e.syllables ~= "") and e.syllables or e.pinyin
                if reading ~= "" and not known[Pinyin.lower(reading)] then e.notcedict = true end
            end
        end
        return out
    end
    local decided = args.decided
    local anchor, words, have_decided = nil, {}, false
    for _, c in ipairs(args.cands or {}) do
        local list, list_source = rowsFor(c.text)
        local entries = list and Model.cleanRows(c.text, list) or {}
        local m = { word = c.text, start = c.start, len = c.len, entries = entries }
        if #entries > 0 then
            m.always = alwaysFor(c.text, list_source, entries)
        elseif always_by_form[c.text] then
            -- Only MOE's covered rows have it (a form CC-CEDICT lacks, 台風
            -- for its 颱風): MOE's entry is the word's own.
            entries = Model.cleanRows(c.text, always_by_form[c.text])
            m.entries = entries
        end
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
        -- Nothing decided between the pair, or nothing decided at all (the
        -- default reading): no reading is called "likely".
        local evidence = args.source == nil or Model.EVIDENCE[args.source]
        if (args.unsure or not evidence) and not args.annotated then anchor.mark = Model.MARK_UNSURE end
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
    -- An Always block's readings in the order of the word's own entries (so
    -- the reading marked likely comes first), then those it does not list,
    -- in the file's order (the build sorts MOE's rows, so that order is not
    -- MOE's own).
    for _, m in ipairs(words) do
        if m.always then
            local at = {}
            for k, e in ipairs(m.entries) do
                local key = Pinyin.lower(e.syllables or e.pinyin or "")
                if not at[key] then at[key] = k end
            end
            local keyed = {}
            for k, e in ipairs(m.always) do
                local reading = (e.syllables ~= nil and e.syllables ~= "") and e.syllables or e.pinyin or ""
                keyed[k] = { e, at[Pinyin.lower(reading)] or (#m.entries + 1), e.proper and 1 or 0, k }
            end
            table.sort(keyed, function(a, b)
                if a[3] ~= b[3] then return a[3] < b[3] end
                if a[2] ~= b[2] then return a[2] < b[2] end
                return a[4] < b[4]
            end)
            for k, item in ipairs(keyed) do m.always[k] = item[1] end
        end
    end
    return words
end

-- Short names of the dictionaries, shown as the entries' source labels.
-- (Moegirlpedia is "Moegirl", not "Moe", which would read as MOE.)
-- mmah and ids label the components block (ch_components.lua).
Model.SOURCE_LABELS = { cedict = "CEDICT", wikt = "Wikt", wp = "WP", cbdb = "CBDB", moe = "MOE",
                        idioms = "成语典", xinhua = "新华",
                        moegirl = "Moegirl", mmah = "MMAH", ids = "IDS" }

------------------------------------------------------------------------
-- Idioms (the user's 成語典 and Xinhua files, tools/chengyu.py): a short
-- line of Chinese explanation under an English entry, and the Origin & Usage view.
------------------------------------------------------------------------

-- Entries whose text is already Chinese: no short line added under them.
Model.CHINESE_SOURCES = { moe = true, idioms = true, xinhua = true, moegirl = true }
-- The Chinese-language fallback dictionaries: their entries go last, their
-- text is drawn larger (the "Chinese text size" setting), and it is the only
-- popup text whose characters can be tapped (Model.tappable).
Model.LARGE_SOURCES = { moe = true, idioms = true, xinhua = true, moegirl = true }

--[[--
Can the characters of this part of a block be tapped (each opening its own
popup)? Only the Chinese dictionaries' own text: a block's senses (`part`
"lines") when the block is theirs or is a Origin & Usage view (`large`), and an
idiom's short line ("note"). Never a headline ("head"), the components
block, or any other dictionary's gloss.
]]
function Model.tappable(block, part)
    if block.components then return false end
    if part == "lines" then return block.large == true or Model.LARGE_SOURCES[block.source] == true end
    if part == "note" then return block.note ~= nil and Model.LARGE_SOURCES[block.note.source] == true end
    return false
end
-- An idiom's view button and title: "成语 Origin & Usage" (one button), or
-- "一毛不拔 - Origin & Usage" (several, each naming its idiom).
Model.ORIGIN = "Origin & Usage"
Model.ORIGIN_ONE = "成语"

--[[--
{ [form] = {source=, short=, view=} } from idiom rows ({simp, trad, short,
view, source}), the first source in `order` (Model.SOURCE_ORDER by default)
for each form; a source's empty field is filled from the next one that has
it (an idiom whose 成語典 entry has no short line still gets Xinhua's).
]]
function Model.pickIdioms(rows, order)
    local rank = {}
    for k, s in ipairs(order or Model.SOURCE_ORDER) do rank[s] = k end
    local sorted = {}
    for k, row in ipairs(rows or {}) do sorted[#sorted + 1] = { row, rank[row.source] or 99, k } end
    table.sort(sorted, function(a, b)
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[3] < b[3]
    end)
    local out = {}
    for _, item in ipairs(sorted) do
        local row = item[1]
        for _, form in ipairs({ row.simp, row.trad }) do
            if form then
                local info = out[form]
                if not info then
                    info = {}
                    out[form] = info
                end
                if (info.short or "") == "" and (row.short or "") ~= "" then
                    info.short, info.short_source = row.short, row.source
                end
                if (info.view or "") == "" and (row.view or "") ~= "" then
                    info.view, info.source = row.view, row.source
                end
            end
        end
    end
    return out
end

-- Attach the idiom information to the matches of two or more characters
-- (m.idiom = {short=, short_source=, view=, source=}).
function Model.attachIdioms(matches, idioms)
    for _, m in ipairs(matches) do
        if m.len and m.len > 1 and idioms[m.word] then m.idiom = idioms[m.word] end
    end
    return matches
end

-- The Origin & Usage buttons: { {word=, source=, view=, text=}, ... }, one
-- per match with a view, labelled "成语 Origin & Usage" (or "一毛不拔 - Origin &
-- Usage" when there are several).
function Model.chuchu(matches)
    local out = {}
    for _, m in ipairs(matches) do
        if m.idiom and (m.idiom.view or "") ~= "" then
            out[#out + 1] = { word = m.word, source = m.idiom.source, view = m.idiom.view }
        end
    end
    for _, b in ipairs(out) do b.text = #out > 1 and (b.word .. " - " .. Model.ORIGIN) or (Model.ORIGIN_ONE .. " " .. Model.ORIGIN) end
    return out
end

--[[--
The popup's content as blocks, one per match:
  { head = "**宛**  yuān · likely here" (the word, its first reading, markers),
    source = "cedict" / "wikt" / "wp" / "cbdb" / "moe" / "moegirl" (whose entry it is),
    lines = { "winding; as if", "wǎn: ...", ... } (senses, further readings),
    note = { source = "idioms" / "xinhua", text = "比喻…" } or nil: an idiom's
      Chinese short line, under an entry whose text is not Chinese already }
b0/b1 are the bold markers (TextBoxWidget's PTF markers in KOReader).
The tapped character's marked readings are unmarked when `annotated` (the
reading is drawn on the page, so it comes first with no label) or when
Model.matches set m.mark (the uncertainty pair, or a default reading nothing
decided: listed with no label), and "likely here" otherwise. A reading a source does not give itself
(Model.GENERATED_READING) is followed by "· generated pinyin".
]]
function Model.blocks(matches, char, annotated, b0, b1)
    b0, b1 = b0 or "", b1 or ""
    local default_mark = annotated and "" or Model.MARK_LIKELY
    local blocks = {}
    local function build(m)
        local block = { lines = {} }
        local label = m.mark or default_mark
        local mark = label ~= "" and (" · " .. label) or ""
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
            if e.notcedict then marked = marked .. " · " .. Model.NOT_CEDICT end
            if k == 1 then
                local tag = m.decided and (" · decides " .. char .. "'s reading") or ""
                -- A word with no pinyin (a dialect word without a Standard
                -- reading) shows the word alone.
                block.head = b0 .. m.word .. b1 .. (e.pinyin ~= "" and ("  " .. e.pinyin) or "") .. marked .. tag
                block.source = e.source or "cedict"
                block.lines[#block.lines + 1] = senses
                local idiom = m.idiom
                if idiom and (idiom.short or "") ~= "" and not Model.CHINESE_SOURCES[block.source] then
                    block.note = { source = idiom.short_source, text = idiom.short }
                end
            else
                block.lines[#block.lines + 1] = e.pinyin ~= "" and (e.pinyin .. marked .. ": " .. senses) or senses
            end
        end
        return block
    end
    for _, m in ipairs(matches) do
        blocks[#blocks + 1] = build(m)
        if m.always then
            -- MOE's Always entries: their own block, right after the match's,
            -- collapsed in the popup (ch_popup.lua), never marked.
            local block = build{ word = m.word, len = m.len, entries = m.always }
            block.always, block.collapse = true, true
            blocks[#blocks + 1] = block
        end
    end
    return blocks
end

-- The Chinese-language dictionaries' entries (MOE, the 成語典, Xinhua,
-- Moegirlpedia: Model.LARGE_SOURCES, drawn larger) go last, after everything else (the
-- components block included), in the order they came: `blocks` is
-- reordered in place.
-- The tapped character's frequency rank, as the popup shows it (#17): its
-- rank among characters in modern written Chinese (wordfreq; tools/
-- build_data.py). Exact up to Model.RANK_EXACT; past it the data is too thin
-- for an exact rank (rank 7,000 is about 66 per billion). nil or 0: not in
-- the frequency list.
Model.RANK_EXACT = 7000
Model.RANK_PREFIX = "字频 "

local function thousands(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

function Model.rankText(rank)
    rank = tonumber(rank)
    if not rank or rank <= 0 then return Model.RANK_PREFIX .. "unranked" end
    if rank > Model.RANK_EXACT then return Model.RANK_PREFIX .. thousands(Model.RANK_EXACT) .. "+" end
    return Model.RANK_PREFIX .. thousands(rank)
end

-- The small grey line above a block: its source label (when `labelled`) and
-- the rank (block.rank, the tapped character's own entry only), on one line
-- ("CEDICT · 字频 4,270"); nil when there is neither.
function Model.labelText(block, labelled, labels)
    local parts = {}
    if labelled then parts[#parts + 1] = (labels or {})[block.source] or block.source end
    if block.rank then parts[#parts + 1] = block.rank end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end

-- Put `rank_text` on the tapped character's own block: blocks[1] when the
-- first match is the character itself (Model.matches lists it first), before
-- any reordering. Returns true when it was placed.
function Model.markRank(blocks, matches, rank_text)
    local first = matches and matches[1]
    if rank_text and first and first.len == 1 and blocks[1] then
        blocks[1].rank = rank_text
        return true
    end
    return false
end

function Model.chineseLast(blocks)
    local rest, chinese = {}, {}
    for _, b in ipairs(blocks) do
        -- An Always block stays right after its word's own entry.
        if Model.LARGE_SOURCES[b.source] and not b.always then chinese[#chinese + 1] = b else rest[#rest + 1] = b end
    end
    for k, b in ipairs(rest) do blocks[k] = b end
    for k, b in ipairs(chinese) do blocks[#rest + k] = b end
    return blocks
end

--[[--
The popup text, without source labels. One block per match, separated by a
blank line:

  **宛**  yuān
  winding; as if
  wǎn: ...

  **大宛**  Dàyuān · decides 宛's reading
  Dayuan, ancient state of Central Asia
]]
function Model.render(matches, char, annotated, b0, b1)
    local out = {}
    for _, block in ipairs(Model.blocks(matches, char, annotated, b0, b1)) do
        out[#out + 1] = block.head .. "\n" .. table.concat(block.lines, "\n")
            .. (block.note and ("\n" .. block.note.text) or "")
    end
    return table.concat(out, "\n\n")
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
