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
    local chosen, decided, unsure, source, _, _, path = Resolve.forPopup(data, items, i, mode, special, drawn)
    local cands, texts = Text.candidates(left, char, right)
    data:prefetch(texts)
    local rows = db:lookup(texts)
    if data.fallback then
        for _, r in ipairs(data.fallback(Model.uncovered(texts, rows))) do rows[#rows + 1] = r end
    end
    local matches = Model.matches{
        cands = cands, rows = rows, chosen = chosen, annotated = drawn ~= nil, decided = decided,
        unsure = unsure, source = source, default = select(2, data:char(char)), path = path,
        wordReading = function(w) return Resolve.wordReading(data, w) end,
    }
    return { chosen = chosen, decided = decided, path = path, unsure = unsure, source = source, matches = matches, drawn = drawn,
             text = Model.render(matches, char, drawn ~= nil),
             -- With "Show traditional in headwords" on (#47, #50, #73).
             ttext = Model.render(matches, char, drawn ~= nil, nil, nil, true) }
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
-- 的 alone: the particle, de, a hand-checked default (data/overrides.tsv,
-- #25), so never the pair de/dì.
p = popup("我的书。", "的")
eq(p.chosen, "de")
eq(marked(p, "的"), "de")
p = popup("我的书。", "的", { mode = "best" })
eq(p.chosen, "de"); eq(marked(p, "的"), "de")
-- "Don't annotate" draws nothing for an uncertain character; the popup still
-- marks both likely readings.
eq(popup("写得好。", "得", { mode = "skip" }).chosen, "de/děi")

-- 东西: the word's everyday reading dōngxi marked, dōngxī listed after it.
p = popup("去买东西。", "东")
eq(p.chosen, "dōng")
eq(marked(p, "东西"), "dōngxi")
assert(p.text:find("东西  dōngxi · likely here\nthing; stuff", 1, true), "no 'decides' tag: 东 has one reading\n" .. p.text)
eq(words(p), "东,东西,买东西", "东西, the word 东 is in here (#75), first")
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

-- A neutral tone drawn as it is (CC-CEDICT gives the word only that way): the
-- character's own entry with the same letters comes first, unmarked (the
-- reading is on the page), and the word is listed with the reading drawn.
p = popup("一只刺猬。", "猬", { threshold = 3500 })
eq(p.drawn, "wei"); eq(p.chosen, "wei")
eq(marked(p, "猬"), "wèi", "猬's entry wèi stands for the drawn wei")
assert(p.text:find("猬  wèi", 1, true), p.text)
assert(p.text:find("刺猬  cìwei · likely here · decides 猬's reading", 1, true), p.text)
eq(p.decided.word, "刺猬"); eq(p.decided.syllables, "cì wei")
-- 鼓捣: in the words table only for the neutral tone; drawn at 2,500 (捣 ranks
-- 2,655), and tapping 捣 shows the word.
p = popup("总能鼓捣回家点儿。", "捣", { threshold = 2500 })
eq(p.drawn, "dao"); eq(marked(p, "捣"), "dǎo")
assert(p.text:find("捣  dǎo", 1, true), p.text)
assert(p.text:find("鼓捣  gǔdao · likely here · decides 捣's reading", 1, true), p.text)
eq(p.decided.word, "鼓捣")
-- Not drawn at 3,500: the popup still marks the word's reading as likely.
p = popup("总能鼓捣回家点儿。", "捣", { threshold = 3500 })
eq(p.drawn, nil); eq(p.chosen, "dao"); eq(marked(p, "捣"), "dǎo")
assert(p.text:find("捣  dǎo · likely here", 1, true), p.text)
-- Several tones with the same letters (糊 hù, hú, hū): only the default, hú,
-- stands for the drawn hu of 含糊.
p = popup("他说得含糊。", "糊", { threshold = 1500 })
eq(p.drawn, "hu"); eq(marked(p, "糊"), "hú")
-- Listed both ways in CC-CEDICT: 缝 is drawn féng in 裁缝 (the word's other
-- reading's tone), the character's entry féng is marked, the word cáifeng.
p = popup("她是裁缝。", "缝", { threshold = 1500 })
eq(p.drawn, "féng"); eq(marked(p, "缝"), "féng"); eq(marked(p, "裁缝"), "cáifeng")
-- A rare character outside such a word keeps its own toned default.
-- (one reading, the one drawn: no marker, as before).
p = popup("他在捣乱。", "捣", { threshold = 2500 })
eq(p.drawn, "dǎo"); eq(marked(p, "捣"), "")
assert(p.text:find("捣  dǎo\n", 1, true) and not p.text:find("decides", 1, true), p.text)

-- Particles: the neutral reading CC-CEDICT lists as an entry of its own is
-- a candidate, and the default where it is the main use.
p = popup("你来啦。", "啦", { mode = "best" })
eq(p.chosen, "la"); eq(marked(p, "啦"), "la", "啦 the particle, not lā")
p = popup("你来啦。", "啦")
eq(p.chosen, "la", "both: the hand-checked particle alone (#25: no pair)")
eq(popup("好嘛。", "嘛").chosen, "ma")
eq(popup("快走呀。", "呀").chosen, "ya")
eq(popup("走吧。", "吧").chosen, "ba")
-- 得: de can win (default and first of the pair), děi stays in the pair,
-- and words still decide dé.
p = popup("他说得对。", "得")
eq(p.chosen, "de/děi"); eq(marked(p, "得"), "de,děi")
eq(popup("高兴得跳起来", "得", { mode = "best" }).chosen, "de")
eq(popup("你得去。", "得").chosen, "de/děi", "děi still offered")
p = popup("他得到了。", "得")
eq(p.chosen, "dé"); eq(p.decided.word, "得到")

-- 累官 is a word (lěi): the learned rule 累 + 官 -> lèi is excluded
-- (data/rules_exclude.tsv).
p = popup("他累官至尚书。", "累")
eq(p.chosen, "lěi"); eq(p.decided.word, "累官")
eq(data:rule("累", nil, "官"), nil, "no rule 累官")
eq(data:rule("攒", "为", nil), nil, "no rule 为攒")

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
assert(p.text:find("峙  zhì", 1, true) or not p.text:find("·", 1, true), p.text)
-- 大宛 and 宛如 overlap; the more common word (宛如) wins, as drawn.
p = popup("很大宛如雷鸣", "宛", { threshold = 2500 })
eq(p.drawn, "wǎn"); eq(p.chosen, "wǎn"); eq(p.decided.word, "宛如")
assert(p.text:find("宛  wǎn\n", 1, true), "one reading in CC-CEDICT (with the surname): no marker\n" .. p.text)
assert(p.text:find("宛如  wǎnrú\n", 1, true), "no tag: CC-CEDICT gives 宛 one reading\n" .. p.text)
eq(words(p), "宛,宛如,大宛", "both words listed, the decided one first (#75) and tagged")

-- The word a character belongs to comes from segmenting its run (#75):
-- 尽 + 自己的心思. 尽自 (jǐnzi, a word only because 尽 is polyphonic) used
-- to win as the leftmost two-character word, leaving 己 on its own. (The
-- book's 尽尽自己 is now the hand-checked word 尽尽 jìn jìn, #77.)
local jin = "能做的，只能是为她办一个盛大的葬礼，尽自己的心思。"
p = popup(jin, "自")
eq(p.path.word, "自己"); eq(p.path.start, 0)
eq(p.decided, nil, "自己 has no reading to give: it decides nothing")
eq(words(p):match("^自,自己,"), "自,自己,", "自己 first among the words: " .. words(p))
assert(words(p):find("尽自", 1, true), "尽自 still listed: " .. words(p))
assert(not p.text:find("尽自[^\n]*likely here"), p.text)
assert(not p.text:find("decides", 1, true), p.text)
assert(not p.text:find("likely here", 1, true), "自 has one reading; no word is likely here\n" .. p.text)
-- 尽: alone on the path, so 尽自 (jǐn) does not decide it. No
-- word or rule does, so it is the uncertainty pair, jìn first (jìn alone
-- in "best" mode), where it used to be jǐn, decided by 尽自.
p = popup(jin, "尽")
eq(p.chosen, "jìn/jǐn"); assert(p.unsure); eq(p.decided, nil); eq(p.path, nil)
eq(marked(p, "尽"), "jìn,jǐn", "jìn first")
assert(not p.text:find("尽自[^\n]*likely here"), p.text)
assert(not p.text:find("decides", 1, true), p.text)
p = popup(jin, "尽", { mode = "best" })
eq(p.chosen, "jìn"); eq(marked(p, "尽"), "jìn")
-- The page draws the same (尽 ranks below 1,000: learner threshold).
local items = H.items(jin)
local seen = 0
for _, a in ipairs(Resolve.annotate(data, items, 0, "best", special)) do
    if items[a.index].text == "尽" then
        seen = seen + 1
        eq(a.reading, "jìn", "尽 #" .. seen .. " drawn jìn")
        assert(not (a.match and a.match.word == "尽自"), "尽自 decides nothing")
    end
end
eq(seen, 1)
-- 大宛 alone: yuān.
p = popup("西域有大宛国。", "宛", { threshold = 2500 })
eq(p.drawn, "yuān"); eq(p.decided.word, "大宛")
-- CC-CEDICT's 宛 has no yuān (it is only in 大宛): shown first, unmarked, empty.
assert(p.text:find("宛  yuān\nno separate CC-CEDICT entry for this reading\nwǎn: winding", 1, true), p.text)

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
eq(p.drawn, "lěi"); assert(p.text:find("累  lěi\n", 1, true), p.text)
local items = H.items("发展成门第望族累世公卿")
for _, a in ipairs(Resolve.annotate(fdata, items, 1000, "both", special)) do
    if items[a.index].text == "累" then eq(a.match.word, "累世"); eq(a.match.fallback, "wikt") end
end

-- Without the fallback words (as before this change): nothing decides, so
-- the pair is shown unmarked, in the resolver's order (lěi
-- first, although CC-CEDICT lists léi first), and lèi stays unmarked.
p = popup("发展成门第望族累世公卿", "累")
eq(p.chosen, "lěi/léi"); assert(p.unsure); eq(p.decided, nil)
eq(marked(p, "累"), "lěi,léi")
assert(p.text:find("累  lěi\n", 1, true), p.text)
assert(p.text:find("\nléi: ", 1, true), p.text)
assert(not p.text:find(" · \n", 1, true), p.text)
assert(not p.text:find("likely here", 1, true), p.text)
-- With them too, when no word covers the character (他累: no word, no rule).
p = popup("他累。", "累", { data = fdata })
eq(p.chosen, "lěi/léi"); assert(p.unsure)
assert(p.text:find("累  lěi\n", 1, true), p.text)
-- Drawn as a pair: both readings first, in the drawn order, unmarked (the
-- page shows them; no "shown above" label).
p = popup("他累。", "累", { data = fdata, threshold = 1000 })
eq(p.drawn, "lěi/léi"); assert(not p.unsure)
assert(p.text:find("累  lěi\n", 1, true), p.text)
assert(p.text:find("\nléi: ", 1, true), p.text)
assert(not p.text:find("shown above", 1, true), p.text)
assert(not p.text:find(" · \n", 1, true) and not p.text:find(" \n", 1, true), p.text)

-- "likely here" only with evidence (#16). 传 in a book title cut by the line
-- (…传稿》): no word, no rule, so the default chuán is listed first with no
-- label, zhuàn after it.
p = popup("传稿》记载：", "传")
eq(p.source, "default"); eq(p.chosen, "chuán"); assert(not p.unsure)
assert(p.text:find("^传  chuán\n"), p.text)
assert(p.text:find("\nzhuàn: ", 1, true), p.text)
assert(not p.text:find("likely here", 1, true), p.text)
-- A context rule decides (还 after 他: hái): the label stays.
p = popup("他还。", "还")
eq(p.source, "rule"); eq(p.chosen, "hái")
assert(p.text:find("还  hái · likely here", 1, true), p.text)
-- Words keep theirs (刺猬, 鼓捣, 东西, 大爷 and 累世 above).
eq(popup("一只刺猬。", "猬").source, "word")
eq(popup("发展成门第望族累世公卿", "累", { data = fdata }).source, "fallback")

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

------------------------------------------------------------------------
-- Traditional taps (#50): the head line leads with the simplified form, the
-- tapped form after it ("头 • 頭" in the rendered text, #73).
------------------------------------------------------------------------
local function heads(p)
    local out = {}
    for block in (p.ttext .. "\n\n"):gmatch("(.-)\n\n") do
        local head = block:match("^[^\n]*")
        out[#out + 1] = head
    end
    return out
end
local function headOf(p, word)
    for _, h in ipairs(heads(p)) do
        if h:find(word, 1, true) == 1 then return h end
    end
    error(word .. " not a head line:\n" .. p.ttext)
end
p = popup("他頭髮花白。", "頭")
assert(headOf(p, "头 • 頭  tóu"), p.ttext)
assert(headOf(p, "头 • 頭  tóu"):find("likely here", 1, true), p.ttext)
assert(headOf(p, "头发 • 頭髮  tóufa"), p.ttext)
p = popup("他頭髮花白。", "髮")
assert(headOf(p, "发 • 髮  fà"), p.ttext)
assert(headOf(p, "头发 • 頭髮  tóufa"), p.ttext)
p = popup("我發現了。", "發")
assert(headOf(p, "发 • 發  fā"), p.ttext)
assert(headOf(p, "发现 • 發現"), p.ttext)
p = popup("很乾淨。", "乾")
assert(headOf(p, "干 • 乾  gān"), p.ttext)
assert(headOf(p, "干净 • 乾淨"), p.ttext)
p = popup("乾隆皇帝。", "乾")
eq(heads(p)[1]:sub(1, #"乾  qián"), "乾  qián", "乾 in 乾隆: nothing added")
assert(headOf(p, "乾隆  Qiánlóng"), p.ttext)
p = popup("他很著名。", "著")
eq(heads(p)[1]:sub(1, #"著  zhù"), "著  zhù", "著 in 著名: nothing added")
assert(headOf(p, "著名  zhùmíng"), p.ttext)
p = popup("買東西。", "東")
assert(headOf(p, "东 • 東  dōng"), p.ttext)
assert(headOf(p, "东西 • 東西  dōngxi"), p.ttext)
p = popup("人民。", "人")
assert(headOf(p, "人  rén"), p.ttext); assert(headOf(p, "人民  rénmín"), p.ttext)
-- The setting off: simplified headwords only (#73).
p = popup("他頭髮花白。", "頭")
assert(p.text:find("^头  tóu"), p.text); assert(p.text:find("\n\n头发  tóufa", 1, true), p.text)
-- Simplified taps unchanged (#47).
p = popup("他头发花白。", "头")
assert(headOf(p, "头 • 頭  tóu"), p.ttext); assert(headOf(p, "头发 • 頭髮  tóufa"), p.ttext)
p = popup("我发现了。", "发")
assert(headOf(p, "发 • 發/髮  fā"), p.ttext)

------------------------------------------------------------------------
-- A neutral reading on a character with several same-letter tones (#51):
-- the word's traditional form of it picks the entry (头发 → 髮 → fà), the
-- character's default only when that does not separate them.
------------------------------------------------------------------------
p = popup("头发花白。", "发")
eq(p.chosen, "fa")
eq(marked(p, "发"), "fà", "发 in 头发: hair, not to send out")
eq(p.matches[1].entries[1].pinyin, "fà", "and listed first")
assert(p.text:find("^发  fà · likely here\nhair"), p.text)
assert(p.text:find("头发  tóufa · likely here · decides 发's reading", 1, true), p.text)
p = popup("他剪头发了。", "发")
eq(marked(p, "发"), "fà", "剪头发")
p = popup("他发现了。", "发")
eq(p.chosen, "fā"); eq(marked(p, "发"), "fā", "发现 unchanged")
p = popup("翻了个跟斗。", "斗")
eq(marked(p, "斗"), "dǒu", "跟斗: 斗 dǒu (the scan's other change)")
-- Not separated by the traditional form: the default, as before.
p = popup("他说得含糊。", "糊")
eq(marked(p, "糊"), "hú", "含糊: 糊's default")
------------------------------------------------------------------------
-- #52: ties the traditional form can't break, settled by the hand list of
-- citation tones (Model.NEUTRAL_CITATIONS); popup marking only.
------------------------------------------------------------------------
local cites = {
    { "这是好处。", "处", "chù" }, { "没有坏处。", "处", "chù" }, { "这有害处。", "处", "chù" },
    { "他有难处。", "处", "chù" }, { "她答应了。", "应", "yìng" }, { "互相照应。", "应", "yìng" },
    { "他满口答应。", "应", "yìng" }, { "他是裁缝。", "缝", "féng" }, { "他思量着。", "量", "liáng" },
    { "掂量一下。", "量", "liáng" }, { "事情停当了。", "当", "dàng" }, { "大部分人。", "分", "fèn" },
    { "组织松散。", "散", "sǎn" }, { "他哭丧着脸。", "丧", "sāng" },
    { "這是好處。", "處", "chù" }, { "她答應了。", "應", "yìng" }, { "他是裁縫。", "縫", "féng" },
}
for _, t in ipairs(cites) do
    local q = popup(t[1], t[2])
    eq(marked(q, t[2]), t[3], t[1])
    eq(q.matches[1].entries[1].pinyin, t[3], t[1] .. " listed first")
    local d = popup(t[1], t[2], { threshold = 1 })
    eq(d.drawn, d.chosen, t[1] .. " drawn as resolved")
end
-- Left out of the list: the default, as before.
eq(marked(popup("他说得含糊。", "糊"), "糊"), "hú", "含糊 unchanged")
eq(marked(popup("说悄悄话。", "悄"), "悄"), "qiāo", "悄悄话: Taiwan's qiǎo left out")
eq(marked(popup("连累了他。", "累"), "累"), "lěi", "连累: Taiwan's lèi left out")
-- Outside the words, the character's default: 处理 chǔ, 回应 yìng (its own word).
eq(marked(popup("处理问题。", "处"), "处"), "chǔ", "处理")
-- Only the popup's marking: the page draws the same pinyin.
for _, t in ipairs({ { "头发花白。", "发" }, { "翻了个跟斗。", "斗" } }) do
    local q = popup(t[1], t[2], { threshold = 1 })
    eq(q.drawn, q.chosen, t[1] .. " drawn as resolved")
end
eq(popup("头发花白。", "发", { threshold = 1 }).drawn, "fa", "头发's 发 still drawn fa")

------------------------------------------------------------------------
-- The Classical dictionary (#53, #55), on the release database
------------------------------------------------------------------------
assert(db:hasClassical(), "the release database has the classical table")
local function classical(text, char)
    local p = popup(text, char)
    local items = H.items(text)
    local i
    for k, item in ipairs(items) do if item.text == char then i = k break end end
    local left, right = {}, {}
    for k = math.max(1, i - 7), i - 1 do left[#left + 1] = items[k].text end
    for k = i + 1, math.min(#items, i + 7) do right[#right + 1] = items[k].text end
    local cands, texts = Text.candidates(left, char, right)
    return Model.classicalBlocks(db:classical(char), char, Model.tradPick(cands, db:lookup(texts)), "**", "**", true), p
end
local cb = classical("學而時習之", "之")
eq(#cb, 1); eq(cb[1].head, "**之**"); eq(cb[1].source, "classical")
-- #67: every classical sense, numbered, commonest classical use first.
assert(#cb[1].lines >= 8, table.concat(cb[1].lines, " | "))
assert(cb[1].lines[1]:find("^1%. him") and not cb[1].lines[1]:find(":", 1, true),
       "之: the object pronoun first, no reading (one reading only): " .. cb[1].lines[1])
assert(cb[1].lines[2]:find("^2%. "), cb[1].lines[2])
cb = classical("不亦說乎", "說")
eq(#cb, 1); eq(cb[1].head, "**说** • 說", "tapped in traditional: the simplified form leads")
assert(table.concat(cb[1].lines, "|"):find("yuè: ", 1, true), "說 = 悅: " .. table.concat(cb[1].lines, " | "))
eq(classical("不亦说乎", "说")[1].head, "**说** • 說", "a simplified tap finds the traditional entry")
eq(#db:classical("説"), 1, "a variant (説) gets its target's entry (說)")
eq(db:classical("説")[1].trad, "說")
eq(#classical("好吗", "吗"), 0, "no entry: nothing added")
eq(classical("委讬", "讬")[1].head, "**讬** • 託", "no thin Unihan copy of a simplified form (#55): 讬 finds 託")
