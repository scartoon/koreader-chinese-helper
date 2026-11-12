-- The resolver and the popup together, on the real database: the reading the
-- popup marks for a character, and for each word around it, is the
-- resolver's, and for every character the annotation layer draws it is
-- exactly the drawn pinyin.
local H = require("sq3_shim")
local Model = require("ch_popup_model")
local Resolve = require("ch_resolve")
local Text = require("ch_text")
local eq = H.eq

local db, data, special = H.db(), H.readings(), H.special()
-- The same tables with the Wiktionary fallback words attached, as the plugin
-- attaches them while that dictionary is switched on (its default).
local fdata = db:readings()
fdata:setFallback(function(list)
    local rows = db:fallback(list)
    for _, r in ipairs(rows) do r.source = r.source or "wikt" end
    return rows
end, "wikt")

-- The popup for the n-th occurrence (default 1) of `char` in `text`, as
-- ch_tap.lua builds it: the page items resolve the reading, the Han run of
-- up to 7 characters each side gives the candidate words. opts.data: the
-- tables to resolve with (fdata: with fallback words, whose rows are then
-- shown too, as ch_tap.lua adds them).
local function popup(text, char, opts)
    opts = opts or {}
    local data = opts.data or data
    local items = H.items(text)
    local i, seen = nil, 0
    for k, item in ipairs(items) do
        if item.text == char then
            seen = seen + 1
            if seen == (opts.nth or 1) then i = k break end
        end
    end
    assert(i, char .. " not in " .. text)
    local left, right = {}, {}
    local k = i
    while #left < 7 and items[k].joined and items[k - 1] do
        k = k - 1
        table.insert(left, 1, items[k].text)
    end
    k = i
    while #right < 7 and items[k + 1] and items[k + 1].joined do
        k = k + 1
        right[#right + 1] = items[k].text
    end
    local mode = opts.mode or "both"
    local drawn
    if opts.threshold then
        for _, a in ipairs(Resolve.annotate(data, items, opts.threshold, mode, special)) do
            if a.index == i then drawn = a.reading end
        end
    end
    local chosen, decided, unsure = Resolve.forPopup(data, items, i, mode, special, drawn)
    local cands, texts = Text.candidates(left, char, right)
    data:prefetch(texts)
    local rows = db:lookup(texts)
    if data.fallback then
        for _, r in ipairs(data.fallback(Model.uncovered(texts, rows))) do rows[#rows + 1] = r end
    end
    local matches = Model.matches{
        cands = cands, rows = rows, chosen = chosen, annotated = drawn ~= nil, decided = decided,
        unsure = unsure,
        wordReading = function(w) return Resolve.wordReading(data, w) end,
    }
    return { chosen = chosen, decided = decided, unsure = unsure, matches = matches, drawn = drawn,
             text = Model.render(matches, char, drawn ~= nil) }
end

-- The marked readings of match `word` ("" when nothing is marked).
local function marked(p, word)
    for _, m in ipairs(p.matches) do
        if m.word == word then
            local out = {}
            for _, e in ipairs(m.entries) do if e.marked then out[#out + 1] = e.pinyin end end
            return table.concat(out, ",")
        end
    end
    error(word .. " not in the popup:\n" .. p.text)
end
local function words(p)
    local out = {}
    for _, m in ipairs(p.matches) do out[#out + 1] = m.word end
    return table.concat(out, ",")
end

-- 的 in 的确: the word decides dí.
local p = popup("他的确很好。", "的")
eq(p.chosen, "dí"); eq(p.decided.word, "的确")
eq(marked(p, "的"), "dí", "的确's 的 marked dí")
eq(p.matches[1].entries[1].pinyin, "dí", "and listed first")
assert(p.text:find("的确  díquè · decides 的's reading", 1, true), p.text)
-- 的 alone: the particle, de (uncertain: with "both", the runner-up dì too).
p = popup("我的书。", "的")
eq(p.chosen, "de/dì")
eq(marked(p, "的"), "de,dì")
p = popup("我的书。", "的", { mode = "best" })
eq(p.chosen, "de"); eq(marked(p, "的"), "de")
-- "Don't annotate" draws nothing for an uncertain character; the popup still
-- marks both likely readings.
eq(popup("我的书。", "的", { mode = "skip" }).chosen, "de/dì")

-- 东西: the word's everyday reading dōngxi marked, dōngxī listed after it.
p = popup("去买东西。", "东")
eq(p.chosen, "dōng")
eq(marked(p, "东西"), "dōngxi")
assert(p.text:find("东西  dōngxi · likely here\nthing; stuff", 1, true), "no 'decides' tag: 东 has one reading\n" .. p.text)
eq(words(p), "东,买东西,东西")
assert(p.text:find("dōngxī: east and west", 1, true), p.text)
-- 西 in 东西 is neutral: its own entry xī stands for it (one reading: no marker).
p = popup("去买东西。", "西")
eq(p.chosen, "xi"); eq(p.matches[1].entries[1].pinyin, "xī"); assert(not p.matches[1].entries[1].missing)

-- Words with several CC-CEDICT readings: the common modern sense is marked.
-- pypinyin's phrase list decides where it has the word (便宜 pián yi, not
-- CC-CEDICT's first entry biàn yí; 明朝 the dynasty, a proper-name reading),
-- data/overrides.tsv where it does not or is wrong (教授, 妻子, 说法, 开通, 下水).
local function word_mark(text, char, word, want, msg)
    eq(marked(popup(text, char), word), want, msg or word)
end
word_mark("这个很便宜。", "便", "便宜", "piányi", "便宜 cheap, not biànyí (宜 ranks above 1,000)")
word_mark("明朝灭亡了。", "明", "明朝", "Míngcháo", "明朝: the dynasty (a proper-name reading)")
word_mark("他是大学教授。", "教", "教授", "jiàoshòu", "教授 professor")
word_mark("他去教会。", "教", "教会", "jiàohuì", "教会 church")
word_mark("他的妻子来了。", "妻", "妻子", "qīzi", "妻子 wife (妻 ranks above 1,000)")
word_mark("这种说法不对。", "说", "说法", "shuōfa", "说法 wording")
word_mark("地铁开通了。", "开", "开通", "kāitōng", "开通 to open")
word_mark("船下水了。", "下", "下水", "xiàshuǐ", "下水 to launch")
-- Hand-checked words still win over pypinyin.
word_mark("拧紧垫圈。", "垫", "垫圈", "diànquān", "垫圈 washer (pypinyin: juàn)")
word_mark("她伸出纤手。", "纤", "纤手", "xiānshǒu", "纤手 (pypinyin: qiàn)")
word_mark("咱家有钱。", "咱", "咱家", "zánjiā", "咱家 (pypinyin: zá)")
-- A rare character's neutral tone is drawn as its own tone (大爷: yé over
-- 爷), which is also CC-CEDICT's other reading of the word, dà yé "idler";
-- the popup still marks dà ye "uncle" (the word_marks table).
p = popup("那位大爷来了。", "大")
eq(marked(p, "大爷"), "dàye", "大爷 uncle, not dàyé")
assert(p.text:find("大爷  dàye · likely here", 1, true), p.text)
eq(Resolve.wordReading(data, "大爷"), "dà ye")
eq(table.concat(data:word("大爷"), " "), "dà yé", "drawn: 爷's own tone")
-- 裁缝: the neutral feng is drawn as the tone of the word's other reading
-- (cái féng), not 缝's default fèng.
eq(table.concat(data:word("裁缝"), " "), "cái féng")
word_mark("她是裁缝。", "裁", "裁缝", "cáifeng", "裁缝 tailor")

-- 行 in context.
p = popup("他在银行工作。", "行")
eq(p.chosen, "háng"); eq(p.decided.word, "银行"); eq(marked(p, "行"), "háng")
p = popup("路上的行人很多。", "行")
eq(p.chosen, "xíng"); eq(p.decided.word, "行人"); eq(marked(p, "行"), "xíng")
p = popup("这样也行。", "行")
eq(p.chosen, "xíng", "行 alone"); eq(p.decided, nil)
eq(p.matches[1].entries[1].pinyin, "xíng")

-- 一 and 不: dictionary tones, as the data has them (no tone changes).
p = popup("他一定来。", "一")
eq(p.chosen, "yī"); eq(marked(p, "一"), "")   -- one reading in CC-CEDICT: nothing to mark
p = popup("这不是书。", "不")
eq(p.chosen, "bù"); eq(marked(p, "不是"), "bùshì", "不是 is not, not bùshi (fault)")

-- Every word containing the character within the context, longest first.
p = popup("这个历史挺靠谱，", "历")
eq(words(p), "历,历史")
p = popup("这个历史挺靠谱，", "靠")
eq(words(p), "靠,靠谱")

-- An annotated character: the popup marks exactly the drawn pinyin.
p = popup("两军对峙。", "峙", { threshold = 2500 })
eq(p.drawn, "zhì"); eq(p.chosen, "zhì")
assert(p.text:find("峙  zhì · shown above", 1, true) or not p.text:find("·", 1, true), p.text)
-- 大宛 and 宛如 overlap; the more common word (宛如) wins, as drawn.
p = popup("很大宛如雷鸣", "宛", { threshold = 2500 })
eq(p.drawn, "wǎn"); eq(p.chosen, "wǎn"); eq(p.decided.word, "宛如")
assert(p.text:find("宛  wǎn\n", 1, true), "one reading in CC-CEDICT (with the surname): no marker\n" .. p.text)
assert(p.text:find("宛如  wǎnrú\n", 1, true), "no tag: CC-CEDICT gives 宛 one reading\n" .. p.text)
eq(words(p), "宛,大宛,宛如", "both words listed, the decided one tagged")
-- 大宛 alone: yuān.
p = popup("西域有大宛国。", "宛", { threshold = 2500 })
eq(p.drawn, "yuān"); eq(p.decided.word, "大宛")
-- CC-CEDICT's 宛 has no yuān (it is only in 大宛): shown first, marked, empty.
assert(p.text:find("宛  yuān · shown above\nno separate CC-CEDICT entry for this reading\nwǎn: winding", 1, true), p.text)

------------------------------------------------------------------------
-- Fallback dictionaries' words decide; honest markers otherwise
------------------------------------------------------------------------

-- 累 in 累世 (Wiktionary only: CC-CEDICT and pypinyin lack the word, no rule
-- covers 累 before 世). The word decides lěi, so lěi alone is marked
-- "likely here", léi is not marked, and 累世 is tagged as deciding.
p = popup("发展成门第望族累世公卿", "累", { data = fdata })
eq(p.chosen, "lěi"); eq(p.decided.word, "累世"); eq(p.decided.syllables, "lěi shì"); assert(not p.unsure)
eq(marked(p, "累"), "lěi", "lěi alone marked")
assert(p.text:find("累  lěi · likely here\n", 1, true), p.text)
assert(p.text:find("\nléi: ", 1, true), "léi listed, unmarked\n" .. p.text)
assert(p.text:find("累世  lěishì · decides 累's reading", 1, true), p.text)
eq(words(p), "累,累世")
-- Drawn (累 ranks 1,209): the annotation layer takes the same word.
p = popup("发展成门第望族累世公卿", "累", { data = fdata, threshold = 1000 })
eq(p.drawn, "lěi"); assert(p.text:find("累  lěi · shown above\n", 1, true), p.text)
local items = H.items("发展成门第望族累世公卿")
for _, a in ipairs(Resolve.annotate(fdata, items, 1000, "both", special)) do
    if items[a.index].text == "累" then eq(a.match.word, "累世"); eq(a.match.fallback, "wikt") end
end

-- Without the fallback words (as before this change): nothing decides, so
-- the pair is shown with "one of these", in the resolver's order (lěi
-- first, although CC-CEDICT lists léi first), and lèi stays unmarked.
p = popup("发展成门第望族累世公卿", "累")
eq(p.chosen, "lěi/léi"); assert(p.unsure); eq(p.decided, nil)
eq(marked(p, "累"), "lěi,léi")
assert(p.text:find("累  lěi · one of these\n", 1, true), p.text)
assert(p.text:find("\nléi · one of these: ", 1, true), p.text)
assert(not p.text:find("likely here", 1, true), p.text)
-- With them too, when no word covers the character (他累: no word, no rule).
p = popup("他累。", "累", { data = fdata })
eq(p.chosen, "lěi/léi"); assert(p.unsure)
assert(p.text:find("累  lěi · one of these\n", 1, true), p.text)
-- Drawn as a pair: "shown above", as before (that is what the page shows).
p = popup("他累。", "累", { data = fdata, threshold = 1000 })
eq(p.drawn, "lěi/léi"); assert(not p.unsure)
assert(p.text:find("累  lěi · shown above\n", 1, true), p.text)
assert(p.text:find("\nléi · shown above: ", 1, true), p.text)

-- A CC-CEDICT word beats a longer fallback word: in 串行端口, CC-CEDICT's
-- 串行 (chuànháng) decides 行, not Wiktionary's 串行端口 (chuànxíng
-- duānkǒu), although the fallback word is longer: CC-CEDICT is authoritative.
p = popup("接上串行端口。", "行", { data = fdata })
eq(p.chosen, "háng"); eq(p.decided.word, "串行")
eq(fdata:fallbackWord("串行端口").readings[2], "xíng", "the fallback word does give 行 another reading")
assert(p.text:find("串行  chuànháng · likely here · decides 行's reading", 1, true), p.text)
assert(not p.text:find("串行端口  [^\n]*decides"), p.text)

-- The property itself, over the regression sentences: wherever the
-- annotation layer draws pinyin, the popup's reading is the same, in every
-- mode, without being told what was drawn.
local f = assert(io.open(PLUGIN_DIR .. "/../tests/eval_cases.tsv", "r"))
local checked = 0
for line in f:lines() do
    local sentence = line:match("^([^\t#]+)\t")
    if sentence then
        local items = H.items(sentence)
        for _, d in ipairs({ data, fdata }) do
            for _, mode in ipairs({ "both", "best" }) do
                for _, threshold in ipairs({ 1500, 3500 }) do
                    for _, a in ipairs(Resolve.annotate(d, items, threshold, mode, special)) do
                        local chosen = Resolve.forPopup(d, items, a.index, mode, special, nil)
                        eq(chosen, a.reading, sentence .. " " .. items[a.index].text .. " (" .. mode .. ")")
                        checked = checked + 1
                    end
                end
            end
        end
    end
end
f:close()
assert(checked > 100, "only " .. checked .. " annotations checked")
