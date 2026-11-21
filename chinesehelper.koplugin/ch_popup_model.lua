-- What the tap popup shows (pure Lua, no KOReader dependencies, tested
-- offline): the order of the entries, row cleaning, the reading markers and
-- the deciding word.
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
-- ("variant of 着 zháo" on a 着 entry) tells the reader nothing. CC-CEDICT's
-- own text names both forms ("variant of 夠|够 gòu", #48): either counts.
-- (Plain spaces, not %S: under some C locales byte 0xA0, inside 夠, counts
-- as a space.)
local function chars(s)
    local out = {}
    for ch in (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

local function selfVariant(sense, word)
    local target = sense:match("^[%a ]*variant of ([^ ]+)")
    if target == nil then return false end
    if target == word then return true end
    for form in target:gmatch("[^|]+") do
        if form == word then return true end
    end
    return false
end

--[[--
The dictionary text to show (#48): rows from the databases (DB:lookup,
DB:fallback, DB:fallbackAll, DB:idioms) carry each source's own text in
defs, short and view, and the simplified text, where it differs, in
defs_simp, short_simp and view_simp. With `simplified`, those replace the
originals; either way the *_simp fields are dropped. Rows from files built
before 2.13.0 have no simplified copy and keep their one text. Changes the
rows in place and returns them.
]]
function Model.chooseText(rows, simplified)
    for _, row in ipairs(rows or {}) do
        if simplified then
            if row.defs_simp then row.defs = row.defs_simp end
            if row.short_simp then row.short = row.short_simp end
            if row.view_simp then row.view = row.view_simp end
        end
        row.defs_simp, row.short_simp, row.view_simp = nil, nil, nil
    end
    return rows
end

--[[--
Entries for one word from its CC-CEDICT rows: self-referring variant senses
dropped (and rows left with none), rows with the same pinyin merged (歷 and
曆 are both lì), ordinary readings before capitalised ones (surnames, place
names), CC-CEDICT's order otherwise.
Returns { {pinyin=, syllables=, senses={...}, proper=bool, trads={...}, simps={...},
selfsimp=bool}, ... }
(trads: the traditional forms of the rows whose simplified form is `word`;
simps: the simplified forms of the rows matched by `word` as their
traditional form, where they differ from it and have its length (#50);
selfsimp: some row has `word` as its simplified form).
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
                          source = row.source or "cedict", trads = {}, simps = {} }
                by_pinyin[pinyin] = entry
                kept[#kept + 1] = entry
            end
            -- The traditional form of a row keyed by the word as simplified
            -- (#47); a row matched by its traditional form (a traditional
            -- text) gives none.
            local trad = row.trad
            if row.simp == word and trad and trad ~= "" then
                local have = false
                for _, t in ipairs(entry.trads) do if t == trad then have = true end end
                if not have then entry.trads[#entry.trads + 1] = trad end
            end
            -- The simplified form of a row matched by its traditional form
            -- (#50): 头 for 頭. An empty simp or one of another length (a
            -- fallback row's other wording) gives none, nor one with a
            -- character past the BMP (噁's 𫫇), which e-reader fonts draw
            -- as a box.
            local simp = row.simp
            if simp == word then
                entry.selfsimp = true
            elseif row.trad == word and simp and simp ~= "" and #chars(simp) == #chars(word)
                    and not simp:find("[\240-\244]") then
                local have = false
                for _, t in ipairs(entry.simps) do if t == simp then have = true end end
                if not have then entry.simps[#entry.simps + 1] = simp end
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
--      Where several tones have those letters, the ones whose traditional
--      forms include `pick` (the word's traditional form of the character,
--      Model.tradPick: 发 in 头发 is 髮, so fà, not fā; #51) when that
--      separates them; otherwise only `prefer` (the word's citation tone
--      from Model.NEUTRAL_CITATIONS, #52, else the character's default
--      reading) when it is one of them (糊 hù, hú, hū for 含糊 hu: hú).
-- `value` is what marked is set to. Returns whether anything was marked.
local function markMatching(entries, chosen, value, prefer, pick)
    local want = Pinyin.lower(chosen)
    local neutral = want == Pinyin.stripTones(want)
    local function sameLetters(e) return neutral and Pinyin.stripTones(Pinyin.lower(e.syllables)) == want end
    local function picked(e)
        for _, t in ipairs(e.trads or {}) do if t == pick then return true end end
        return false
    end
    local by_pick = false
    if neutral and pick then
        local with, without = 0, 0
        for _, e in ipairs(entries) do
            if sameLetters(e) then
                if picked(e) then with = with + 1 else without = without + 1 end
            end
        end
        by_pick = with > 0 and without > 0
    end
    local narrowed = false
    if neutral and not by_pick and prefer and prefer ~= "" then
        prefer = Pinyin.lower(prefer)
        for _, e in ipairs(entries) do
            if sameLetters(e) and Pinyin.lower(e.syllables) == prefer then narrowed = true end
        end
    end
    local tests = {
        function(e) return Pinyin.lower(e.syllables) == want end,
        function(e) return Pinyin.matches(e.syllables, want) end,
        function(e)
            if not sameLetters(e) then return false end
            if by_pick then return picked(e) end
            return not narrowed or Pinyin.lower(e.syllables) == prefer
        end,
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
Neutral-tone ties the traditional form can't break (#52): words CC-CEDICT
gives a neutral syllable on a character with several same-letter tones, both
under one traditional form, so markMatching would fall back to the
character's default reading (处 chǔ in 好处). Here, the word's citation tone
of that character, where MOE and pypinyin's phrase data agree on it (难处's
neutral word nánchu "difficulty" is 处 chù; pypinyin's chǔ is the other
难处, nánchǔ "hard to get on with"). Left out: Taiwan readings (悄悄话 qiǎo,
连累 lèi) and 生分 (the sources disagree). Popup marking only: the pinyin
drawn on the page doesn't use this. word -> { char -> reading }, simplified
and traditional forms.
]]
Model.NEUTRAL_CITATIONS = {}
for _, row in ipairs({
    { "好处", "好處", "处", "處", "chù" }, { "坏处", "壞處", "处", "處", "chù" },
    { "害处", "害處", "处", "處", "chù" }, { "难处", "難處", "处", "處", "chù" },
    { "答应", "答應", "应", "應", "yìng" }, { "照应", "照應", "应", "應", "yìng" },
    { "满口答应", "滿口答應", "应", "應", "yìng" },
    { "裁缝", "裁縫", "缝", "縫", "féng" },
    { "思量", "思量", "量", "量", "liáng" }, { "掂量", "掂量", "量", "量", "liáng" },
    { "停当", "停當", "当", "當", "dàng" },
    { "大部分", "大部分", "分", "分", "fèn" },
    { "松散", "鬆散", "散", "散", "sǎn" },
    { "哭丧脸", "哭喪臉", "丧", "喪", "sāng" }, { "哭丧着脸", "哭喪著臉", "丧", "喪", "sāng" },
}) do
    Model.NEUTRAL_CITATIONS[row[1]] = { [row[3]] = row[5] }
    Model.NEUTRAL_CITATIONS[row[2]] = { [row[4]] = row[5] }
end

--[[--
The tapped character's citation reading from Model.NEUTRAL_CITATIONS (#52):
from the longest candidate word listed with that character. nil when none.
]]
function Model.citationPick(cands, char)
    local best, best_len
    for _, c in ipairs(cands or {}) do
        local cite = Model.NEUTRAL_CITATIONS[c.text]
        if cite and cite[char] and (not best_len or c.len > best_len) then
            best, best_len = cite[char], c.len
        end
    end
    return best
end

--[[--
For the tapped character with several traditional forms (发: 發 and 髮), the
one the word around it uses: from the longest candidate word with a
CC-CEDICT row keyed by that word as simplified, the character's place in
the row's traditional form (头发 → 髮, 发现 → 發). nil when no word says.
(Components.pickTrad's rule, without its components data.)
]]
function Model.tradPick(cands, rows)
    local by_simp = {}
    for _, row in ipairs(rows or {}) do
        if (row.source == nil or row.source == "cedict") and row.simp and not by_simp[row.simp] then
            by_simp[row.simp] = row
        end
    end
    local best, best_len
    for _, c in ipairs(cands or {}) do
        local row = by_simp[c.text]
        if c.len > 1 and row and (not best_len or c.len > best_len) then
            local t = chars(row.trad)[1 - c.start]
            if t then best, best_len = t, c.len end
        end
    end
    return best
end

--[[--
The reverse of Model.tradPick (#50): for a tapped traditional character, the
simplified form the word around it uses: from the longest candidate word
with a CC-CEDICT row keyed by that word as traditional, the character's
place in the row's simplified form (乾淨 → 干, 乾隆 → 乾, 頭髮 → 头). nil
when no word says.
]]
function Model.simpPick(cands, rows)
    local by_trad = {}
    for _, row in ipairs(rows or {}) do
        if (row.source == nil or row.source == "cedict") and row.trad and not by_trad[row.trad]
                and not (row.simp or ""):find("[\240-\244]") then
            by_trad[row.trad] = row
        end
    end
    local best, best_len
    for _, c in ipairs(cands or {}) do
        local row = by_trad[c.text]
        if c.len > 1 and row and (not best_len or c.len > best_len) then
            local s = chars(row.simp)[1 - c.start]
            if s then best, best_len = s, c.len end
        end
    end
    return best
end

--[[--
The simplified form of a word tapped in traditional characters (#50), or
nil when it is not one (the word is itself a simplified form, or no row
gives another). `m` and `entries` as for Model.tradText.
  * A word of two or more characters: the head line's entry's form.
  * A single character: one form, the one the word around it uses
    (m.simp_pick, even when the character's own rows lack it), else the
    head line's reading's, else the first. A row
    keyed by the character as simplified counts as its own form (乾 qián,
    著 zhù), so 乾 in 乾隆 and 著 in 著名 give nil.
]]
function Model.simpText(m, entries)
    local word = m.word
    if not entries or #entries == 0 then return nil end
    local function own(e)
        if e.selfsimp then return word end
        return (e.simps or {})[1]
    end
    local s
    if (m.len or #chars(word)) > 1 then
        s = own(entries[1])
    else
        if m.simp_pick then
            -- The word's spelling settles it, even where the character's
            -- own rows give another form (噁心 → 恶, the character's row 𫫇).
            s = m.simp_pick
        else
            s = own(entries[1])
            if not s then
                for _, e in ipairs(entries) do
                    s = own(e)
                    if s then break end
                end
            end
        end
    end
    if s == nil or s == word then return nil end
    return s
end

--[[--
The head line's two forms (#47, #50): the bold word and the smaller
form, or nil when nothing is added. A word tapped in simplified characters:
the word and its traditional form (Model.tradText). One tapped in
traditional characters: its simplified form (Model.simpText) and the word
as tapped.
]]
function Model.headForms(m, entries)
    local s = Model.simpText(m, entries)
    if s then return s, m.word end
    local t = Model.tradText(m, entries)
    if t then return m.word, t end
    return nil
end

--[[--
The traditional form shown after a block's headword (#47), or nil when it
is the same as the word. `m` is the match (word=, len=, trad_pick=), `entries`
the block's entries (cleanRows' trads; the first entry is the head line's).
  * A word of two or more characters: one form, the head line's row's, and
    only one of the same length as the word (a few Wiktionary rows give a
    longer wording or another word as their "traditional" form).
  * A single character: every form its rows give, "/"-joined, the one the
    word around it uses (m.trad_pick) first, then the head line's reading's,
    then the rest. When the character is itself one of several forms (干:
    乾/幹/干) it is listed with them; when it is the only form, nothing.
]]
function Model.tradText(m, entries)
    local word = m.word
    if not entries or #entries == 0 then return nil end
    if (m.len or #chars(word)) > 1 then
        local t = (entries[1].trads or {})[1]
        if t and t ~= word and #chars(t) == #chars(word) then return t end
        return nil
    end
    local list, seen = {}, {}
    local function add(t)
        if t and t ~= "" and not seen[t] and #chars(t) == 1 then
            seen[t] = true
            list[#list + 1] = t
        end
    end
    local all = {}
    for _, e in ipairs(entries) do
        for _, t in ipairs(e.trads or {}) do all[t] = true end
    end
    if m.trad_pick and all[m.trad_pick] then add(m.trad_pick) end
    for _, e in ipairs(entries) do
        for _, t in ipairs(e.trads or {}) do add(t) end
    end
    if #list == 0 or (#list == 1 and list[1] == word) then return nil end
    return table.concat(list, "/")
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
                    several same-letter tones a neutral `chosen` stands for, when the
                    word's traditional form of the character (Model.tradPick)
                    does not settle it (#51)
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
    local trad_pick = anchor and Model.tradPick(args.cands, args.rows)
    local cite = anchor and Model.citationPick(args.cands, anchor.word)
    if anchor and fromCedict(anchor) and args.chosen and args.chosen ~= "" then
        local entries = anchor.entries
        local several = distinctReadings(entries) > 1 or toneless
        local rank = 0
        for reading in args.chosen:gmatch("[^/]+") do
            rank = rank + 1
            if not markMatching(entries, reading, several or nil, cite or args.default, trad_pick) then
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
    -- A word with nothing to say (#20): no sense from any source, no note,
    -- no Always entries (a pypinyin phrase, or the deciding word when no
    -- dictionary has it) is not listed. Dropped only here, after the
    -- reading markers and the "decides" tag were worked out from the full
    -- list: the tapped character's own entry already shows the reading.
    local function empty(m)
        if m.note or m.always then return false end
        for _, e in ipairs(m.entries) do
            if #e.senses > 0 then return false end
        end
        return true
    end
    local kept = {}
    for _, m in ipairs(words) do
        if not empty(m) then kept[#kept + 1] = m end
    end
    words = kept
    if anchor then
        anchor.trad_pick = trad_pick
        anchor.simp_pick = Model.simpPick(args.cands, args.rows)
        table.insert(words, 1, anchor)
    end
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
-- (Moegirlpedia is "Moegirl", not "Moe". MOE's dictionary goes by its own
-- short name, in its own characters: 國語辭典.)
-- mmah and ids label the components block (ch_components.lua).
Model.SOURCE_LABELS = { cedict = "CEDICT", wikt = "Wikt", wp = "WP", cbdb = "CBDB", moe = "國語辭典",
                        idioms = "成语典", xinhua = "新华",
                        moegirl = "Moegirl", mmah = "MMAH", ids = "IDS", classical = "文言" }

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
With `trad` (the "Show traditional forms" setting, #47), a block whose
word's traditional form differs also has trad= (Model.tradText), word= and
rest= (the head line after the word), for the popup to draw the form beside
the word; head is the same either way. A word tapped in traditional
characters (#50) has word= its simplified form and trad= the word as
tapped (Model.headForms), and head leads with both: "**头发** 頭髮  tóufa".
The tapped character's marked readings are unmarked when `annotated` (the
reading is drawn on the page, so it comes first with no label) or when
Model.matches set m.mark (the uncertainty pair, or a default reading nothing
decided: listed with no label), and "likely here" otherwise. A reading a source does not give itself
(Model.GENERATED_READING) is followed by "· generated pinyin".
]]
function Model.blocks(matches, char, annotated, b0, b1, trad)
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
                -- Only the tapped character's own readings and noted words
                -- get here: Model.matches drops words with no senses at all.
                if m.note then
                    senses = m.note
                else
                    senses = "no separate CC-CEDICT entry for this reading"
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
                local rest = (e.pinyin ~= "" and ("  " .. e.pinyin) or "") .. marked .. tag
                block.head = b0 .. m.word .. b1 .. rest
                block.source = e.source or "cedict"
                if trad then
                    local word, form = Model.headForms(m, m.entries)
                    block.word, block.trad, block.rest = word or m.word, form, rest
                    -- Tapped in traditional characters (#50): the plain head
                    -- line (the popup's fallback when the drawn one has too
                    -- little room) leads with the simplified form too.
                    if word and word ~= m.word then
                        block.head = b0 .. word .. b1 .. " " .. form .. rest
                    end
                end
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
            local block = build{ word = m.word, len = m.len, entries = m.always, trad_pick = m.trad_pick,
                                 simp_pick = m.simp_pick }
            block.always, block.collapse = true, true
            blocks[#blocks + 1] = block
        end
    end
    return blocks
end

--[[--
The Classical dictionary's blocks for the tapped character (#53): `rows`
from DB:classical. A simplified character standing for several traditional
ones (发: 發, 髮) shows the one the word around it uses (`trad_pick`,
Model.tradPick), else each in turn. One block per entry, never collapsed
(#56: shown in full, first in the popup): head line the character (with its traditional form beside it
when `trad` and it differs), then one sense per line, "reading: gloss" when
the sense gives a reading. Empty when there is no entry: nothing is added.
]]
function Model.classicalBlocks(rows, char, trad_pick, b0, b1, trad)
    b0, b1 = b0 or "", b1 or ""
    local picked = {}
    for _, r in ipairs(rows or {}) do
        if r.trad == char then picked = { r } break end
    end
    if #picked == 0 then
        for _, r in ipairs(rows or {}) do
            if trad_pick and r.trad == trad_pick then picked = { r } break end
        end
    end
    if #picked == 0 then picked = rows or {} end
    local blocks = {}
    for _, r in ipairs(picked) do
        local block = { lines = {}, source = "classical", classical = true }
        for line in (r.senses or ""):gmatch("[^\n]+") do
            local reading, gloss = line:match("^([^\t]*)\t([^\t]*)")
            if gloss and gloss ~= "" then
                block.lines[#block.lines + 1] = (reading ~= "" and (reading .. ": ") or "") .. gloss
            end
        end
        if #block.lines > 0 then
            local word = (r.simp ~= "" and r.simp) or r.trad
            block.head = b0 .. word .. b1
            if trad then
                local form = r.trad ~= word and r.trad or nil
                block.word, block.trad, block.rest = word, form, ""
                if form then block.head = b0 .. word .. b1 .. " " .. form end
            end
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

-- With the reader's own ranks on (#42), `source` says where this rank comes
-- from: "books" (their file; `exact` its last exact rank) or "bundled" (a
-- character not in their books keeps its wordfreq rank). Only a bundled rank
-- is marked, since it is on a different scale: "字频 6,500 (bundled)"; the
-- reader's own rank is shown bare (#46).
Model.RANK_SOURCES = { bundled = "bundled" }

function Model.rankText(rank, source, exact)
    rank = tonumber(rank)
    local text
    if not rank or rank <= 0 then
        text = Model.RANK_PREFIX .. "unranked"
    else
        local limit = (source == "books" and tonumber(exact)) or Model.RANK_EXACT
        if rank > limit then
            text = Model.RANK_PREFIX .. thousands(limit) .. "+"
        else
            text = Model.RANK_PREFIX .. thousands(rank)
        end
    end
    local label = source and Model.RANK_SOURCES[source]
    if label then text = text .. " (" .. label .. ")" end
    return text
end

-- The small grey line above a block: its source label (when `labelled`) and
-- the rank (block.rank, the tapped character's own entry only), on one line
-- ("CEDICT · 字频 4,270"); nil when there is neither.
function Model.labelText(block, labelled, labels)
    local parts = {}
    if labelled then parts[#parts + 1] = (labels or {})[block.source] or block.source end
    if block.rank then parts[#parts + 1] = block.rank end
    if block.spoken then parts[#parts + 1] = block.spoken end
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

-- The spoken tone drawn above 一 or 不 (#37), on the character's own block
-- like the rank: its entries keep the dictionary's yī and bù, so the page
-- and the popup don't seem to disagree. Returns true when it was placed.
Model.SPOKEN_NOTE = "spoken here: %s"

function Model.markSpoken(blocks, matches, spoken)
    local first = matches and matches[1]
    if spoken and first and first.len == 1 and blocks[1] then
        blocks[1].spoken = string.format(Model.SPOKEN_NOTE, spoken)
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
function Model.render(matches, char, annotated, b0, b1, trad)
    local out = {}
    for _, block in ipairs(Model.blocks(matches, char, annotated, b0, b1, trad)) do
        local head = block.head
        if block.trad then head = (b0 or "") .. block.word .. (b1 or "") .. " " .. block.trad .. block.rest end
        out[#out + 1] = head .. "\n" .. table.concat(block.lines, "\n")
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

--[[--
The grey of the lines between the popup's bottom buttons (#43), as an 8-bit
shade. KOReader's ButtonTable draws them in COLOR_GRAY (0xAA). Night mode
inverts the screen, so they come out 0x55 on black, which the Boox's e-ink
hardly shows. In night mode they are drawn 0x55 instead, coming out 0xAA on
black: day mode's light grey line, mirrored.
]]
Model.SEPARATOR_DAY, Model.SEPARATOR_NIGHT = 0xAA, 0x55

function Model.separatorShade(night)
    return night and Model.SEPARATOR_NIGHT or Model.SEPARATOR_DAY
end

return Model
