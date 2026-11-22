-- What the popup shows (ch_popup_model.lua): ordering and row cleaning,
-- reading markers, the deciding word, the header, and placement.
local Text = require("ch_text")
local Model = require("ch_popup_model")
local H = require("sq3_shim")
local eq = H.eq

local function chars(s) return Text.chars(s) end
local function join(list, key, sep)
    local out = {}
    for _, x in ipairs(list) do out[#out + 1] = key and x[key] or x end
    return table.concat(out, sep or ",")
end
local function row(simp, trad, pinyin, defs, syllables)
    return { simp = simp, trad = trad, pinyin = pinyin, defs = defs, syllables = syllables }
end
local function matches(left, char, right, rows, extra)
    local args = extra or {}
    args.cands = Text.candidates(chars(left), char, chars(right))
    args.rows = rows
    return Model.matches(args)
end

------------------------------------------------------------------------
-- Ordering
------------------------------------------------------------------------
-- Tapped 历 in 这个[历]史挺靠谱. Rows in CC-CEDICT order.
local m = matches("这个", "历", "史挺靠谱", {
    row("历", "歷", "lì", "to experience/to undergo"),
    row("历", "曆", "lì", "calendar"),
    row("历史", "歷史", "lìshǐ", "history/CL: 门 mén", "lì shǐ"),
    row("个", "個", "gè", "individual"),  -- never returned (no 历): ignored
    row("史", "史", "Shǐ", "surname Shi"),
})
eq(join(m, "word"), "历,历史", "anchor first, then words")
eq(#m[1].entries, 1, "歷 and 曆 rows with the same reading merged")
eq(join(m[1].entries[1].senses), "to experience,to undergo,calendar")
eq(m[2].entries[1].pinyin, "lìshǐ")

-- Longest first. Tapped 国 at the end of 中华人民共和国.
m = matches("中华人民共和", "国", "", {
    row("国", "國", "guó", "country"),
    row("和国", "和國", "x", "fake 2-char ending in 国"),
    row("共和国", "共和國", "gònghéguó", "republic"),
    row("中华人民共和国", "中華人民共和國", "Zhōnghuá Rénmín Gònghéguó", "People's Republic of China"),
    row("民共和国", "民共和國", "x", "fake 4"),
})
eq(join(m, "word"), "国,中华人民共和国,民共和国,共和国,和国", "longest first")

-- Ties on length: earlier start first. Tapped 学 in 大学生.
m = matches("大", "学", "生", {
    row("学生", "學生", "xuésheng", "student"),
    row("大学", "大學", "dàxué", "university"),
    row("大学生", "大學生", "dàxuéshēng", "university student"),
    row("学", "學", "xué", "to learn"),
})
eq(join(m, "word"), "学,大学生,大学,学生", "ties broken by earlier start")

-- No entry for the tapped character itself: words only.
m = matches("", "𪜀", "𪜀", { row("𪜀𪜀", "𪜀𪜀", "x", "fake") })
eq(join(m, "word"), "𪜀𪜀")
eq(#matches("", "𪜀", "𪜀", {}), 0, "nothing found")

-- Traditional text matches through the traditional form, shown as written.
m = matches("", "歷", "史", { row("历史", "歷史", "lìshǐ", "history"), row("历", "歷", "lì", "to experience") })
eq(join(m, "word"), "歷,歷史", "traditional match")

-- Self-referring variant senses dropped; proper-noun readings last.
m = matches("", "着", "", {
    row("着", "着", "zhāo", "variant of 着 zhāo"),
    row("着", "着", "zhe", "variant of 着 zhe"),
    row("着", "著", "zhe", "aspect particle"),
    row("着", "著", "zháo", "to touch/to feel"),
})
eq(join(m[1].entries, "pinyin"), "zhe,zháo", "self-variant rows dropped")
m = matches("", "乐", "", { row("乐", "樂", "Lè", "surname Le"), row("乐", "樂", "lè", "happy"),
                             row("乐", "樂", "yuè", "music") })
eq(join(m[1].entries, "pinyin"), "lè,yuè,Lè", "proper-noun readings last")
eq(#matches("", "着", "", { row("着", "着", "zhāo", "old variant of 着 zhāo") }), 0, "no senses left: dropped")

------------------------------------------------------------------------
-- Reading markers
------------------------------------------------------------------------
local yue = {
    row("乐", "樂", "lè", "happy/cheerful"),
    row("乐", "樂", "yuè", "music"),
    row("乐", "樂", "Lè", "surname Le"),
}
-- The resolver's reading is marked and moved first.
m = matches("", "乐", "", yue, { chosen = "yuè" })
eq(join(m[1].entries, "pinyin"), "yuè,lè,Lè", "chosen first")
assert(m[1].entries[1].marked and not m[1].entries[2].marked)
eq(Model.render(m, "乐", false, "<b>", "</b>"),
   "<b>乐</b>  yuè · likely here\nmusic\nlè: happy; cheerful\nLè: surname Le")
eq(Model.render(m, "乐", true), "乐  yuè\nmusic\nlè: happy; cheerful\nLè: surname Le")
-- An uncertain pair marks both.
m = matches("", "乐", "", yue, { chosen = "yuè/lè" })
assert(m[1].entries[1].marked and m[1].entries[2].marked and not m[1].entries[3].marked, "both of a pair marked")
-- One reading only: nothing to point at, no marker.
m = matches("", "靠", "", { row("靠", "靠", "kào", "to lean") }, { chosen = "kào" })
eq(Model.render(m, "靠", true), "靠  kào\nto lean")
-- A neutral tone in CC-CEDICT stands for the toned reading: 瘩 "da" is dā.
m = matches("", "瘩", "", { row("瘩", "瘩", "da", "see 疙瘩"), row("瘩", "瘩", "tǎ", "sore") }, { chosen = "dā" })
eq(join(m[1].entries, "pinyin"), "da,tǎ"); assert(m[1].entries[1].marked)
-- A word's neutral tone drawn as it is (刺猬 cì wei): the one entry with the
-- same letters is marked even though it is the only reading, and the word
-- that decided it is tagged and marked.
m = matches("刺", "猬", "", { row("猬", "蝟", "wèi", "hedgehog"),
                             row("刺猬", "刺蝟", "cìwei", "hedgehog", "cì wei") },
            { chosen = "wei", annotated = true,
              decided = { word = "刺猬", start = -1, len = 2, syllables = "cì wei" } })
eq(Model.render(m, "猬", true), "猬  wèi\nhedgehog\n\n"
   .. "刺猬  cìwei · likely here · decides 猬's reading\nhedgehog")
-- Several tones with those letters: only the default stands for it.
local hu = { row("糊", "糊", "hù", "paste"), row("糊", "糊", "hú", "muddled"), row("糊", "糊", "hū", "to plaster") }
m = matches("", "糊", "", hu, { chosen = "hu", default = "hú" })
eq(join(m[1].entries, "pinyin"), "hú,hù,hū"); assert(m[1].entries[1].marked and not m[1].entries[2].marked)
m = matches("", "糊", "", hu, { chosen = "hu" })
assert(m[1].entries[1].marked and m[1].entries[2].marked and m[1].entries[3].marked, "no default: all three")
-- A chosen reading CC-CEDICT does not list for the character: shown, empty.
m = matches("", "乐", "", yue, { chosen = "yào" })
eq(m[1].entries[1].pinyin, "yào"); assert(m[1].entries[1].missing and m[1].entries[1].marked)
assert(Model.render(m, "乐", true):find("yào\nno separate CC-CEDICT entry for this reading", 1, true))

-- Words: the resolver's reading of the word is marked when there is a choice.
local dongxi = {
    row("东", "東", "dōng", "east"),
    row("东西", "東西", "dōngxī", "east and west", "dōng xī"),
    row("东西", "東西", "dōngxi", "thing/stuff", "dōng xi"),
}
m = matches("", "东", "西", dongxi, { chosen = "dōng", wordReading = function(w) return w == "东西" and "dōng xi" or nil end })
eq(join(m[2].entries, "pinyin"), "dōngxi,dōngxī", "the word's chosen reading first")
assert(m[2].entries[1].marked and not m[2].entries[2].marked)
eq(Model.render(m, "东", false), "东  dōng\neast\n\n东西  dōngxi · likely here\nthing; stuff\ndōngxī: east and west")
-- Without a word reading, CC-CEDICT's order, nothing marked.
m = matches("", "东", "西", dongxi, { chosen = "dōng" })
eq(join(m[2].entries, "pinyin"), "dōngxī,dōngxi"); assert(not m[2].entries[1].marked)

------------------------------------------------------------------------
-- The deciding word
------------------------------------------------------------------------
-- In CC-CEDICT: tagged.
m = matches("大", "宛", "如", {
    row("宛", "宛", "wǎn", "winding"), row("宛", "宛", "yuān", "see 大宛"),
    row("大宛", "大宛", "Dàyuān", "Dayuan, ancient state", "Dà yuān"),
    row("宛如", "宛如", "wǎnrú", "just like", "wǎn rú"),
}, { chosen = "yuān", annotated = true, decided = { word = "大宛", start = -1, len = 2, syllables = "dà yuān" } })
eq(join(m, "word"), "宛,大宛,宛如")
assert(m[2].decided and not m[3].decided)
local text = Model.render(m, "宛", true)
assert(text:find("宛  yuān\nsee 大宛\nwǎn: winding", 1, true), text)
assert(text:find("大宛  Dàyuān · decides 宛's reading\nDayuan, ancient state", 1, true), text)
-- Not in CC-CEDICT (a special word with a note): listed anyway, with the note.
m = matches("", "冒", "顿", { row("冒", "冒", "mào", "to emit") },
    { chosen = "mò", annotated = true, decided = { word = "冒顿", start = 0, len = 2, syllables = "mò dú",
                                                   note = "Modu, Xiongnu ruler" } })
eq(join(m, "word"), "冒,冒顿")
text = Model.render(m, "冒", true)
assert(text:find("冒  mò\nno separate CC-CEDICT entry for this reading\nmào: to emit", 1, true), text)
assert(text:find("冒顿  mò dú · decides 冒's reading\nModu, Xiongnu ruler", 1, true), text)
-- A pypinyin-only word (no definition from any source, no note): not listed (#20),
-- the tapped character's own block still there.
m = matches("", "甲", "乙", { row("甲", "甲", "jiǎ", "first") },
    { chosen = "jiǎ", decided = { word = "甲乙", start = 0, len = 2, syllables = "jiǎ yǐ" } })
eq(join(m, "word"), "甲")
text = Model.render(m, "甲", false)
assert(text:find("^甲  jiǎ") and not text:find("甲乙", 1, true), text)
-- Same with no other word for the character: nothing listed at all, so the tap
-- goes to KOReader's dictionaries (ch_tap.lua), never an empty popup.
m = matches("", "甲", "乙", {}, { chosen = "jiǎ", decided = { word = "甲乙", start = 0, len = 2, syllables = "jiǎ yǐ" } })
eq(#m, 0)
-- A noted word with no senses still shows (冒顿 above); so does a pypinyin word
-- that only MOE's Always rows have.
m = matches("", "甲", "乙", { row("甲", "甲", "jiǎ", "first") },
    { chosen = "jiǎ", decided = { word = "甲乙", start = 0, len = 2, syllables = "jiǎ yǐ" },
      always = { { simp = "甲乙", trad = "甲乙", pinyin = "jiǎ yǐ", defs = "天干的第一位和第二位", source = "moe" } } })
eq(join(m, "word"), "甲,甲乙")

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------
local SH, MG = 1000, 10
local top_box = { x = 100, y = 100, w = 40, h = 60 }      -- character in the top half
local bottom_box = { x = 100, y = 800, w = 40, h = 60 }   -- in the bottom half
local y, covers = Model.place(300, SH, MG, top_box)
eq(y, SH - MG - 300, "short popup, character at the top: bottom half"); assert(not covers)
y, covers = Model.place(300, SH, MG, bottom_box)
eq(y, MG, "short popup, character at the bottom: top half"); assert(not covers)
y, covers = Model.place(700, SH, MG, top_box)
eq(y, 150, "tall popup: centred"); assert(covers, "a tall popup covers the character")
y, covers = Model.place(990, SH, MG, bottom_box)
eq(y, MG, "taller than the room: from the top margin"); assert(covers)
-- A character straddling the middle: a half-screen popup can still cover it.
y, covers = Model.place(480, SH, MG, { x = 0, y = 470, w = 40, h = 60 })
eq(y, MG); assert(covers)

-- The deciding word is tagged only when the character has a choice of readings.
m = matches("行", "人", "", { row("人", "人", "rén", "person"), row("行人", "行人", "xíngrén", "pedestrian", "xíng rén") },
    { chosen = "rén", decided = { word = "行人", start = -1, len = 2, syllables = "xíng rén" } })
eq(join(m, "word"), "人,行人"); assert(not m[2].decided)
assert(not Model.render(m, "人", false):find("decides", 1, true))

------------------------------------------------------------------------
-- Fallback dictionaries
------------------------------------------------------------------------
local function frow(simp, trad, pinyin, defs, source) return { simp = simp, trad = trad, pinyin = pinyin, defs = defs, source = source } end

-- Only the words CC-CEDICT does not cover go to the fallback lookup.
eq(table.concat(Model.uncovered({ "尚", "尚书", "尚书省", "书省" }, { row("尚", "尚", "shàng", "still"),
    row("尚书", "尚書", "shàngshū", "high official") }), ","), "尚书省,书省")
eq(#Model.uncovered({ "歷" }, { row("历", "歷", "lì", "x") }), 0, "traditional form covered")
-- One source per word: what Wiktionary has is not looked up in MOE.
local kept, left = Model.takeFallback({ "尚书省", "书省", "韃子" },
    { frow("尚书省", "尚書省", "Shàngshūshěng", "Department of State Affairs", "wikt"),
      frow("鞑子", "韃子", "dázi", "Tartar", "wikt") })
eq(#kept, 2); eq(table.concat(left, ","), "书省")
kept, left = Model.takeFallback({ "书省" }, { frow("别的", "別的", "x", "x", "moe") })
eq(#kept, 0, "rows for other words ignored"); eq(table.concat(left, ","), "书省")

-- CC-CEDICT always wins: a fallback row for a word CC-CEDICT has is ignored.
m = matches("", "东", "西", {
    row("东", "東", "dōng", "east"),
    frow("东", "東", "dōng", "WIKT east", "wikt"),
    row("东西", "東西", "dōngxī", "east and west", "dōng xī"),
    frow("东西", "東西", "dōngxi", "WIKT thing", "wikt"),
})
eq(#m[1].entries, 1); eq(m[1].entries[1].source, "cedict")
eq(join(m[2].entries, "source"), "cedict", "CC-CEDICT's 东西 only")
-- Fallback rows fill words CC-CEDICT lacks; Wiktionary before MOE, one source per word.
m = matches("", "尚", "书省", {
    row("尚", "尚", "shàng", "still"),
    row("尚书", "尚書", "shàngshū", "high official"),
    frow("尚书省", "尚書省", "shàng shū shěng", "官署名", "moe"),
    frow("尚书省", "尚書省", "Shàngshūshěng", "the Department of State Affairs", "wikt"),
})
eq(join(m, "word"), "尚,尚书省,尚书", "longest first, as always")
eq(join(m[2].entries, "source"), "wikt", "Wiktionary before MOE")
eq(m[2].entries[1].senses[1], "the Department of State Affairs")
-- MOE when Wiktionary does not have the word (or is switched off).
m = matches("", "尚", "书省", { row("尚", "尚", "shàng", "still"),
    frow("尚书省", "尚書省", "shàng shū shěng", "官署名", "moe") })
eq(m[2].entries[1].source, "moe"); eq(m[2].entries[1].pinyin, "shàng shū shěng", "MOE's own (Taiwan) reading")

-- No reading markers on fallback entries, even with several readings and a
-- resolver reading for the word; CC-CEDICT's markers are unchanged.
m = matches("", "鞑", "子", { row("鞑", "韃", "dá", "Tartar"), row("鞑", "韃", "tà", "whip"),
    frow("鞑子", "韃子", "dázi", "Tartar (derogatory)", "wikt"), frow("鞑子", "韃子", "dázǐ", "other", "wikt") },
    { chosen = "dá", annotated = true, wordReading = function() return "dá zǐ" end })
assert(m[1].entries[1].marked, "CC-CEDICT anchor still marked")
for _, e in ipairs(m[2].entries) do assert(not e.marked, "fallback entry unmarked") end
eq(join(m[2].entries, "pinyin"), "dázi,dázǐ", "the source's order, nothing moved")
-- A fallback-only anchor (CC-CEDICT lacks the character): listed, unmarked.
m = matches("", "𪜀", "", { frow("𪜀", "𪜀", "x", "a rare character", "wikt") }, { chosen = "x" })
eq(#m, 1); assert(not m[1].entries[1].marked and not m[1].entries[1].missing)
-- A dialect word with no Standard reading has no pinyin (#15): the word and
-- its qualified gloss, no stray gap or separator.
m = matches("", "挟", "菜", { row("挟", "挾", "xié", "to clasp"), row("挟", "挾", "jiā", "to hold"),
    frow("挟菜", "挾菜", "", "(dialectal) to get food using chopsticks", "wikt"),
    frow("挟菜", "挾菜", "jiācài", "other sense", "wikt") }, { chosen = "xié" })
text = Model.render(m, "挟", true)
assert(text:find("\n\n挟菜\n%(dialectal%) to get food using chopsticks\njiācài: other sense$"), text)
m = matches("", "挟", "菜", { row("挟", "挾", "xié", "to clasp"),
    frow("挟菜", "挾菜", "jiācài", "a sense", "wikt"),
    frow("挟菜", "挾菜", "", "(dialectal) to get food using chopsticks", "wikt") }, { chosen = "xié" })
text = Model.render(m, "挟", true)
assert(text:find("\n\n挟菜  jiācài\na sense\n%(dialectal%) to get food using chopsticks$"), text)

-- The deciding word CC-CEDICT lacks: the fallback definition, tag kept.
local decided = { word = "尚书省", start = 0, len = 3, syllables = "shàng shū shěng" }
m = matches("", "尚", "书省", { row("尚", "尚", "shàng", "still"), row("尚", "尚", "cháng", "other"),
    frow("尚书省", "尚書省", "Shàngshūshěng", "the Department of State Affairs", "wikt") },
    { chosen = "shàng", decided = decided })
local text = Model.render(m, "尚", false)
assert(text:find("尚书省  Shàngshūshěng · decides 尚's reading\nthe Department of State Affairs", 1, true), text)
assert(not text:find("no definition in CC-CEDICT", 1, true), text)
-- Without a fallback entry: the deciding word is not listed (#20); the
-- tapped character keeps its marked reading.
m = matches("", "尚", "书省", { row("尚", "尚", "shàng", "still"), row("尚", "尚", "cháng", "other") },
    { chosen = "shàng", decided = decided })
eq(join(m, "word"), "尚")
text = Model.render(m, "尚", false)
assert(text:find("^尚  shàng · likely here\nstill"), text)
assert(not text:find("尚书省", 1, true) and not text:find("no definition", 1, true), text)
-- Blocks carry each entry's source (for the labels); the text is the same as render's.
m = matches("", "尚", "书省", { row("尚", "尚", "shàng", "still"),
    frow("尚书省", "尚書省", "shàng shū shěng", "官署名", "moe") })
local blocks = Model.blocks(m, "尚", false)
eq(blocks[1].source, "cedict"); eq(blocks[2].source, "moe")
eq(blocks[2].head, "尚书省  shàng shū shěng"); eq(blocks[2].lines[1], "官署名")
eq(Model.render(m, "尚", false), blocks[1].head .. "\n" .. table.concat(blocks[1].lines, "\n") .. "\n\n"
    .. blocks[2].head .. "\n" .. table.concat(blocks[2].lines, "\n"))
eq(Model.SOURCE_LABELS.cedict, "CEDICT"); eq(Model.SOURCE_LABELS.wikt, "Wikt"); eq(Model.SOURCE_LABELS.moe, "國語辭典")
eq(Model.SOURCE_LABELS.wp, "WP"); eq(Model.SOURCE_LABELS.cbdb, "CBDB"); eq(Model.SOURCE_LABELS.moegirl, "Moegirl")
eq(table.concat(Model.SOURCE_ORDER, ","), "wikt,cbdb,moe,idioms,xinhua,wp,moegirl", "the default priority")
eq(Model.SOURCE_LABELS.idioms, "成语典"); eq(Model.SOURCE_LABELS.xinhua, "新华")

-- Idioms: the first source in the order for each field, the other filling
-- a field it lacks; attached to matches of two or more characters; a short
-- line under an entry that is not Chinese already; Origin & Usage buttons.
local picked = Model.pickIdioms({
    { simp = "一毛不拔", trad = "一毛不拔", short = "新华的", view = "新华 view", source = "xinhua" },
    { simp = "一毛不拔", trad = "一毛不拔", short = "成语典的", view = "成语典 view", source = "idioms" },
    { simp = "玉石俱碎", trad = "玉石俱碎", short = "", view = "成语典 view", source = "idioms" },
    { simp = "玉石俱碎", trad = "玉石俱碎", short = "犹玉石俱焚。", view = "", source = "xinhua" },
})
eq(picked["一毛不拔"].short, "成语典的"); eq(picked["一毛不拔"].source, "idioms")
eq(picked["玉石俱碎"].short, "犹玉石俱焚。"); eq(picked["玉石俱碎"].short_source, "xinhua")
eq(picked["玉石俱碎"].source, "idioms")
eq(Model.pickIdioms({ { simp = "一毛不拔", trad = "一毛不拔", short = "新华的", view = "", source = "xinhua" },
                      { simp = "一毛不拔", trad = "一毛不拔", short = "成语典的", view = "", source = "idioms" } },
                    { "xinhua", "idioms" })["一毛不拔"].short, "新华的", "the order is the setting's")
local im = matches("一", "毛", "不拔", { row("毛", "毛", "máo", "hair"),
    row("一毛不拔", "一毛不拔", "yīmáobùbá", "(fig.) extremely stingy") })
Model.attachIdioms(im, { ["一毛不拔"] = picked["一毛不拔"], ["毛"] = picked["一毛不拔"] })
eq(im[1].idiom, nil, "a single character is never an idiom")
local iblocks = Model.blocks(im, "毛", false)
eq(iblocks[2].note.source, "idioms"); eq(iblocks[2].note.text, "成语典的"); eq(iblocks[1].note, nil)
eq(Model.render(im, "毛", false), "毛  máo\nhair\n\n一毛不拔  yīmáobùbá\n(fig.) extremely stingy\n成语典的")
local cb = Model.chuchu(im)
eq(#cb, 1); eq(cb[1].text, "成语 Origin & Usage"); eq(cb[1].word, "一毛不拔"); eq(cb[1].view, "成语典 view")
im[1].idiom = { view = "x", source = "xinhua" }; im[1].len = 2; im[1].word = "毛毛"
cb = Model.chuchu(im)
eq(cb[1].text, "毛毛 - Origin & Usage"); eq(cb[2].text, "一毛不拔 - Origin & Usage", "several: named")
local cm = matches("一", "毛", "不拔", { frow("一毛不拔", "一毛不拔", "yī máo bù bá", "形容吝啬。", "moe") })
Model.attachIdioms(cm, { ["一毛不拔"] = picked["一毛不拔"] })
eq(Model.blocks(cm, "毛", false)[1].note, nil, "MOE's entry is Chinese already")

-- The newer sources. Default order: CBDB before MOE, Wikipedia after MOE,
-- Moegirlpedia last; CC-CEDICT before all of them.
local five = {
    row("典", "典", "diǎn", "canon"),
    frow("典史", "典史", "diǎn shǐ", "官名", "moe"),
    frow("典史", "典史", "dian shi", "Clerk (Ming office title)", "cbdb"),
    frow("典史", "典史", "diǎn shǐ", "网络用语", "moegirl"),
}
m = matches("", "典", "史", five)
eq(m[2].entries[1].source, "cbdb", "CBDB before MOE and Moegirlpedia")
eq(m[2].entries[1].pinyin, "dian shi", "CBDB's own toneless reading")
-- args.order (Settings:fallbackOrder()) changes it.
m = matches("", "典", "史", five, { order = { "moegirl", "moe", "cbdb" } })
eq(m[2].entries[1].source, "moegirl")
m = matches("", "典", "史", { row("典", "典", "diǎn", "canon"), frow("典史", "典史", "diǎn shǐ", "x", "moegirl"),
    frow("典史", "典史", "Diǎnshǐ", "Clerk", "wp") })
eq(m[2].entries[1].source, "wp", "Wikipedia before Moegirlpedia")
-- CC-CEDICT wins over every one of them.
m = matches("", "典", "", { row("典", "典", "diǎn", "canon"), frow("典", "典", "x", "y", "cbdb"),
    frow("典", "典", "x", "y", "wp"), frow("典", "典", "x", "y", "moegirl") })
eq(join(m[1].entries, "source"), "cedict")
-- Generated readings (Wikipedia titles, Moegirlpedia) say so; CBDB's and
-- MOE's own readings do not.
m = matches("", "红", "夷大炮", { row("红", "紅", "hóng", "red"),
    frow("红夷大炮", "紅夷大炮", "hóng yí dà pào", "Hongyipao", "wp") })
blocks = Model.blocks(m, "红", false)
eq(blocks[2].source, "wp"); eq(blocks[2].head, "红夷大炮  hóng yí dà pào · generated pinyin")
m = matches("", "问", "题不大", { row("问", "問", "wèn", "ask"),
    frow("问题不大", "問題不大", "wèn tí bù dà", "问题不大是一句网络流行语。", "moegirl") })
eq(Model.blocks(m, "问", false)[2].head, "问题不大  wèn tí bù dà · generated pinyin")
m = matches("", "典", "史", { row("典", "典", "diǎn", "canon"), frow("典史", "典史", "dian shi", "Clerk", "cbdb") })
eq(Model.blocks(m, "典", false)[2].head, "典史  dian shi")
-- Only fallback rows: the popup has something to show (it no longer goes
-- straight to KOReader's dictionary).
m = matches("", "尚", "书省", { frow("尚书省", "尚書省", "Shàngshūshěng", "x", "wikt") })
eq(join(m, "word"), "尚书省")

-- Marked readings follow the resolver's order ("lěi/léi": lěi first),
-- not CC-CEDICT's (léi first).
local lei = { row("累", "纍", "léi", "rope; to bind"), row("累", "累", "lěi", "to accumulate"),
              row("累", "累", "lèi", "tired") }
m = matches("", "累", "", lei, { chosen = "lěi/léi" })
eq(join(m[1].entries, "pinyin"), "lěi,léi,lèi", "resolver's order")
eq(m[1].entries[1].rank, nil, "the sort key is not left behind")
m = matches("", "累", "", lei, { chosen = "léi/lěi" })
eq(join(m[1].entries, "pinyin"), "léi,lěi,lèi")
-- The uncertainty pair (nothing decided, nothing drawn): no marker.
m = matches("", "累", "", lei, { chosen = "lěi/léi", unsure = true })
eq(Model.render(m, "累", false), "累  lěi\nto accumulate\nléi: rope; to bind\n"
    .. "lèi: tired")
-- Drawn as a pair, it is what the page shows: no label.
m = matches("", "累", "", lei, { chosen = "lěi/léi", unsure = true, annotated = true })
eq(Model.render(m, "累", true), "累  lěi\nto accumulate\nléi: rope; to bind\n"
    .. "lèi: tired")
-- A single resolved reading stays "likely here".
m = matches("", "累", "", lei, { chosen = "lěi" })
eq(Model.render(m, "累", false), "累  lěi · likely here\nto accumulate\nléi: rope; to bind\nlèi: tired")
-- ...when a word, special word, fallback word or rule decided it (#16).
for _, source in ipairs({ "word", "special", "fallback", "rule" }) do
    m = matches("", "累", "", lei, { chosen = "lěi", source = source })
    eq(Model.render(m, "累", false), "累  lěi · likely here\nto accumulate\nléi: rope; to bind\nlèi: tired", source)
end
-- The default reading (nothing decided): first, no label.
for _, source in ipairs({ "default", "pair" }) do
    m = matches("", "累", "", lei, { chosen = "lěi", source = source })
    eq(Model.render(m, "累", false), "累  lěi\nto accumulate\nléi: rope; to bind\nlèi: tired", source)
end
-- "One of these" is the tapped character's marker only: a word's marked
-- reading is still "likely here".
m = matches("", "东", "西", { row("东", "東", "dōng", "east"), row("东西", "東西", "dōngxi", "thing", "dōng xi"),
    row("东西", "東西", "dōngxī", "east and west", "dōng xī") },
    { chosen = "dōng/dòng", unsure = true, wordReading = function() return "dōng xi" end })
assert(Model.render(m, "东", false):find("东西  dōngxi · likely here", 1, true))

-- The Chinese dictionaries' entries (MOE, 成語典, Xinhua, Moegirlpedia) go
-- last, after the components block, in their own order; the rest keep theirs.
local blocks = Model.chineseLast({ { source = "cedict", head = "a" }, { source = "moe", head = "b" },
    { source = "mmah", components = true, head = "c" }, { source = "xinhua", head = "d" },
    { source = "moegirl", head = "e" }, { source = "idioms", head = "f" }, { source = "wikt", head = "g" } })
eq(join(blocks, "head", ""), "acgbdef", "Chinese dictionaries last")
eq(join(Model.chineseLast({ { source = "cedict", head = "a" } }), "head", ""), "a", "none")
assert(Model.LARGE_SOURCES.moe and Model.LARGE_SOURCES.idioms and Model.LARGE_SOURCES.xinhua)
assert(Model.LARGE_SOURCES.moegirl)

-- Words first (#71): the character's group (the first n blocks) below the
-- rest, in its own order; the rank goes with its block.
local function wf(n)
    local bl = { { head = "c", rank = "字频 9" }, { head = "m", always = true }, { head = "k", components = true },
                 { head = "w1" }, { head = "W1", always = true }, { head = "w2" } }
    return Model.wordsFirst(bl, n)
end
eq(join(wf(3), "head", ","), "w1,W1,w2,c,m,k", "the group below the words")
eq(wf(3)[4].rank, "字频 9", "the rank on the character's block")
eq(join(wf(1), "head", ","), "m,k,w1,W1,w2,c", "a group of one")
eq(join(wf(0), "head", ","), "c,m,k,w1,W1,w2", "no group: unchanged")
eq(join(wf(6), "head", ","), "c,m,k,w1,W1,w2", "no words: unchanged")
eq(#Model.wordsFirst({}, 0), 0)
assert(not Model.LARGE_SOURCES.cedict and not Model.LARGE_SOURCES.wikt and not Model.LARGE_SOURCES.wp
       and not Model.LARGE_SOURCES.cbdb)

-- Tappable: the Chinese dictionaries' own text only.
local note = { source = "idioms", text = "形容人非常吝啬。" }
for _, src in ipairs({ "moe", "idioms", "xinhua", "moegirl" }) do
    assert(Model.tappable({ source = src, lines = { "x" } }, "lines"), src .. " text")
    assert(not Model.tappable({ source = src, head = "x" }, "head"), src .. " headline")
end
for _, src in ipairs({ "cedict", "wikt", "wp", "cbdb" }) do
    assert(not Model.tappable({ source = src, lines = { "x" } }, "lines"), src .. " gloss")
end
assert(Model.tappable({ source = "cedict", lines = { "x" }, note = note }, "note"), "an idiom's short line")
assert(not Model.tappable({ source = "cedict", head = "x" }, "head"), "a CC-CEDICT headline")
assert(not Model.tappable({ source = "mmah", components = true, lines = { "x" } }, "lines"), "components")
assert(not Model.tappable({ source = "wikt", components = true, lines = { "x" } }, "lines"), "Wiktionary components")
assert(Model.tappable({ source = "xinhua", lines = { "x" }, large = true }, "lines"), "a Origin & Usage view")

-- The frequency rank's text (#17) and the grey lines above a block: the rank
-- line first, then the source label on its own row (#59).
eq(Model.rankText(1), "字频 1")
eq(Model.rankText(4270), "字频 4,270")
eq(Model.rankText(7000), "字频 7,000")
eq(Model.rankText(7001), "字频 7,000+")
eq(Model.rankText(0), "字频 unranked")
eq(Model.rankText(nil), "字频 unranked")
local function ll(...) return table.concat(Model.labelLines(...), " / ") end
eq(ll({ source = "cedict" }, false, Model.SOURCE_LABELS), "", "no label, no rank: no line")
eq(ll({ source = "cedict", rank = "字频 4,270" }, false, Model.SOURCE_LABELS), "字频 4,270")
eq(ll({ source = "cedict", rank = "字频 4,270" }, true, Model.SOURCE_LABELS), "字频 4,270 / CEDICT",
   "rank first, the label on a row of its own")
eq(ll({ source = "classical", rank = "字频 16" }, true, Model.SOURCE_LABELS), "字频 16 / 文言")
eq(ll({ source = "cedict", spoken = "spoken here: yì" }, true, Model.SOURCE_LABELS), "spoken here: yì / CEDICT",
   "a spoken mark without a rank")
eq(ll({ source = "wikt" }, true, Model.SOURCE_LABELS), "Wikt")
-- Only the character's own block gets it.
local bl = { {}, {} }
assert(Model.markRank(bl, { { len = 1 }, { len = 4 } }, "字频 9"))
eq(bl[1].rank, "字频 9"); eq(bl[2].rank, nil)
bl = { {} }
assert(not Model.markRank(bl, { { len = 2 } }, "字频 9"), "no entry of its own")
eq(bl[1].rank, nil)

------------------------------------------------------------------------
-- Button separators in night mode (#43)
------------------------------------------------------------------------
-- Day mode keeps KOReader's grey; night mode draws them darker, so that
-- after the inversion they are as light on black as day's are on white.
eq(Model.separatorShade(false), 0xAA)
eq(Model.separatorShade(nil), 0xAA)
eq(Model.separatorShade(true), 0x55)
eq(Model.separatorShade(true), 0xFF - Model.separatorShade(false))
-- Secondary text (#57): grey by day, the normal text colour in night mode.
eq(Model.secondaryGrey(false), true, "day: grey")
eq(Model.secondaryGrey(nil), true, "no night flag: grey")
eq(Model.secondaryGrey(true), false, "night: normal colour")

------------------------------------------------------------------------
-- Traditional forms beside the headword (#47)
------------------------------------------------------------------------
local FA = { row("发", "發", "fā", "to send out"), row("发", "髮", "fà", "hair") }
local function tradOf(left, char, right, rows, k, extra)
    local bl = Model.blocks(matches(left, char, right, rows, extra), char, false, nil, nil, true)
    return bl[k or 1] and bl[k or 1].trad
end
eq(tradOf("", "观", "", { row("观", "觀", "guān", "to look at") }), "觀")
local tb = Model.blocks(matches("", "观", "", { row("观", "觀", "guān", "to look at") }), "观", false, "<", ">", true)[1]
eq(tb.head, "<观> • 觀  guān", "same size, after a bullet (#73)")
eq(tb.word, "观"); eq(tb.rest, "  guān")
eq(Model.render(matches("", "观", "", { row("观", "觀", "guān", "to look at") }), "观", false, nil, nil, true),
   "观 • 觀  guān\nto look at")
-- #73's cases: a word shows its one form; the same form (人, 大人) adds nothing.
local XX = { row("学", "學", "xué", "to learn"), row("学习", "學習", "xuéxí", "to study") }
eq(Model.blocks(matches("", "学", "习", XX), "学", false, "**", "**", true)[2].head, "**学习** • 學習  xuéxí")
eq(Model.blocks(matches("", "学", "习", XX), "学", false, "**", "**", true)[1].head, "**学** • 學  xué")
eq(Model.blocks(matches("", "学", "习", XX), "学", false, "**", "**")[2].head, "**学习**  xuéxí", "off: simplified only")
local DR = { row("大", "大", "dà", "big"), row("大人", "大人", "dàrén", "adult") }
for _, b in ipairs(Model.blocks(matches("", "大", "人", DR), "大", false, "**", "**", true)) do
    eq(b.head:find("•", 1, true), nil, "the same form: no bullet"); eq(b.trad, nil)
end
eq(Model.blocks(matches("", "大", "人", DR), "大", false, "**", "**", true)[2].head, "**大人**  dàrén")
local TF = { FA[1], FA[2], row("头发", "頭髮", "tóufa", "hair (on the head)"),
             row("发现", "發現", "fāxiàn", "to find") }
eq(tradOf("头", "发", "", TF, 2), "頭髮", "the whole word")
eq(tradOf("", "发", "现", TF, 2), "發現")
eq(tradOf("头", "发", "", TF, 1), "髮/發", "the character: the word's form first")
eq(tradOf("", "发", "现", TF, 1), "發/髮")
eq(tradOf("", "发", "", FA, 1), "發/髮", "alone: the head line's reading first")
eq(tradOf("", "发", "", FA, 1, { chosen = "fà" }), "髮/發", "the chosen reading's first")
eq(tradOf("", "人", "民", { row("人", "人", "rén", "person"), row("人民", "人民", "rénmín", "the people") }, 1), nil)
eq(tradOf("", "人", "民", { row("人", "人", "rén", "person"), row("人民", "人民", "rénmín", "the people") }, 2), nil,
   "the same: nothing")
eq(tradOf("中", "国", "", { row("国", "國", "guó", "country"), row("中国", "中國", "Zhōngguó", "China") }, 2), "中國")
-- A character that is one of its own traditional forms: not listed (#73).
eq(tradOf("", "干", "", { row("干", "乾", "gān", "dry"), row("干", "幹", "gàn", "to do"),
                          row("干", "干", "gān", "shield"), row("干", "榦", "gàn", "trunk") }, 1), "乾/幹/榦",
   "the head reading gān's forms first, 干 itself left out")
eq(tradOf("", "干", "", { row("干", "干", "gān", "shield") }, 1), nil, "its own only form: nothing")
-- A traditional text: the smaller form is the word as tapped, after its
-- simplified form (#50; nothing was added before 2.14.0).
eq(tradOf("頭", "髮", "", { row("发", "髮", "fà", "hair"), row("头发", "頭髮", "tóufa", "hair") }, 1), "髮")
eq(tradOf("頭", "髮", "", { row("发", "髮", "fà", "hair"), row("头发", "頭髮", "tóufa", "hair") }, 2), "頭髮")
eq(tradOf("", "觀", "", { row("观", "觀", "guān", "to look at") }), "觀")
-- Fallback rows: an empty or copied trad gives nothing; a longer wording is not a form.
eq(tradOf("", "辅", "助", { frow("辅助", "", "fǔ zhù", "to assist", "wikt") }, 1), nil)
eq(tradOf("", "辅", "助", { frow("辅助", "辅助", "fǔ zhù", "to assist", "wikt") }, 1), nil)
eq(tradOf("", "辅", "助", { frow("辅助", "輔助", "fǔ zhù", "to assist", "wikt") }, 1), "輔助")
eq(tradOf("", "哎", "妈", { frow("哎妈", "哎呀媽呀", "āi mā", "oh my", "wikt") }, 1), nil)
-- An Always block: the same rule.
local am = matches("头", "发", "", TF, { always = { frow("头发", "頭髮", "tóu fǎ", "人的头上所生的毛。", "moe") } })
local ab = Model.blocks(am, "发", false, nil, nil, true)
eq(ab[3].always, true); eq(ab[3].trad, "頭髮")
-- The setting off: no traditional forms anywhere.
for _, b in ipairs(Model.blocks(am, "发", false)) do eq(b.trad, nil, "off") end
eq(Model.render(matches("", "观", "", { row("观", "觀", "guān", "to look at") }), "观", false),
   "观  guān\nto look at")

------------------------------------------------------------------------
-- A neutral reading with several same-letter tones (#51): the word's
-- traditional form of the character picks the entry.
------------------------------------------------------------------------
local NT = { row("发", "發", "fā", "to send out", "fā"), row("发", "髮", "fà", "hair", "fà"),
             row("头发", "頭髮", "tóufa", "hair (on the head)", "tóu fa"),
             row("发现", "發現", "fāxiàn", "to find", "fā xiàn") }
local function markedOf(left, char, right, rows, extra)
    local out = {}
    for _, e in ipairs(matches(left, char, right, rows, extra)[1].entries) do
        if e.marked then out[#out + 1] = e.pinyin end
    end
    return table.concat(out, ",")
end
eq(markedOf("头", "发", "", NT, { chosen = "fa", default = "fā" }), "fà", "头发: 髮 → fà")
eq(matches("头", "发", "", NT, { chosen = "fa", default = "fā" })[1].entries[1].pinyin, "fà", "listed first")
eq(markedOf("", "发", "", NT, { chosen = "fa", default = "fā" }), "fā", "no word: the default")
eq(markedOf("", "发", "现", NT, { chosen = "fā", default = "fā" }), "fā")
-- The pick on both entries (same traditional form): the default decides.
local HU = { row("糊", "糊", "hū", "to paste", "hū"), row("糊", "糊", "hú", "muddled", "hú"),
             row("糊", "糊", "hù", "paste", "hù"), row("含糊", "含糊", "hánhu", "vague", "hán hu") }
eq(markedOf("含", "糊", "", HU, { chosen = "hu", default = "hú" }), "hú")
-- A toned reading never reaches the tie-break.
eq(markedOf("头", "发", "", NT, { chosen = "fā", default = "fā" }), "fā")

------------------------------------------------------------------------
-- Traditional taps: the simplified form in bold, the tapped form smaller (#50)
------------------------------------------------------------------------
local function headOf(left, char, right, rows, k, extra, b0, b1)
    local bl = Model.blocks(matches(left, char, right, rows, extra), char, false, b0, b1, true)
    local b = bl[k or 1]
    if not b then return nil end
    return b.trad and (b.word .. " " .. b.trad) or nil, b
end
local TT = { row("头", "頭", "tóu", "head"), row("头", "頭", "tou", "suffix for nouns"),
             row("发", "發", "fā", "to send out"), row("发", "髮", "fà", "hair"),
             row("头发", "頭髮", "tóufa", "hair (on the head)"), row("发现", "發現", "fāxiàn", "to find") }
eq(headOf("", "頭", "髮花白", TT, 1), "头 頭", "頭 in 頭髮")
eq(headOf("", "頭", "髮花白", TT, 2), "头发 頭髮", "the word block")
eq(headOf("頭", "髮", "花白", TT, 1), "发 髮")
eq(headOf("", "發", "現", TT, 1), "发 發")
eq(headOf("", "發", "現", TT, 2), "发现 發現")
local _, hb = headOf("", "頭", "髮花白", TT, 2, nil, "<", ">")
eq(hb.head, "<头发> • 頭髮  tóufa", "the head line leads with the simplified form (#73)")
eq(hb.word, "头发"); eq(hb.trad, "頭髮"); eq(hb.rest, "  tóufa")
eq(Model.render(matches("", "頭", "髮", TT), "頭", false, nil, nil, true),
   "头 • 頭  tóu\nhead\ntou: suffix for nouns\n\n头发 • 頭髮  tóufa\nhair (on the head)")
-- The setting off (#73): a traditional tap's head lines are simplified only.
eq(Model.render(matches("", "頭", "髮", TT), "頭", false),
   "头  tóu\nhead\ntou: suffix for nouns\n\n头发  tóufa\nhair (on the head)")
-- 乾: 干 in 乾淨, itself in 乾隆 (a row keyed by 乾 as simplified).
local QIAN = { row("乾", "乾", "qián", "one of the Eight Trigrams"), row("干", "乾", "gān", "dry"),
               row("干净", "乾淨", "gānjìng", "clean"), row("乾隆", "乾隆", "Qiánlóng", "the Qianlong era") }
eq(headOf("", "乾", "淨", QIAN, 1), "干 乾", "乾 in 乾淨")
eq(headOf("", "乾", "淨", QIAN, 2), "干净 乾淨")
eq(headOf("", "乾", "隆", QIAN, 1), nil, "乾 in 乾隆: nothing added")
eq(headOf("", "乾", "隆", QIAN, 2), nil)
eq(headOf("", "乾", "", QIAN, 1, { chosen = "gān" }), "干 乾", "alone: the head line's reading's")
eq(headOf("", "乾", "", QIAN, 1, { chosen = "qián" }), nil)
-- 著 in 著名: 著 zhù is its own simplified form.
local ZHU = { row("著", "著", "zhù", "to make known"), row("着", "著", "zhe", "aspect particle"),
              row("着", "著", "zhuó", "to wear"), row("著", "著", "zhuó", "used in 執著"),
              row("著名", "著名", "zhùmíng", "famous") }
eq(headOf("", "著", "名", ZHU, 1, { chosen = "zhù" }), nil, "著 in 著名")
eq(headOf("", "著", "名", ZHU, 2), nil)
eq(headOf("", "人", "民", { row("人", "人", "rén", "person"), row("人民", "人民", "rénmín", "the people") }, 2), nil)
eq(headOf("", "東", "西", { row("东", "東", "dōng", "east"), row("东西", "東西", "dōngxi", "thing") }, 2),
   "东西 東西")
-- Fallback rows: an empty or different-length simp adds nothing.
eq(headOf("", "輔", "助", { frow("", "輔助", "fǔ zhù", "to assist", "wikt") }, 1), nil)
eq(headOf("", "哎", "呀媽呀", { frow("哎妈", "哎呀媽呀", "āi mā", "oh my", "wikt") }, 1), nil)
eq(headOf("", "輔", "助", { frow("辅助", "輔助", "fǔ zhù", "to assist", "wikt") }, 1), "辅助 輔助")
-- An MOE Always block matched by its traditional form: the same rule.
local tam = matches("", "頭", "髮", TT, { always = { frow("头发", "頭髮", "tóu fǎ", "人的頭上所生的毛。", "moe") } })
local tab = Model.blocks(tam, "頭", false, nil, nil, true)
eq(tab[3].always, true); eq(tab[3].word, "头发"); eq(tab[3].trad, "頭髮")
-- The setting off: simplified headwords only (#73), no traditional form.
for _, b in ipairs(Model.blocks(tam, "頭", false, "<", ">")) do
    eq(b.trad, nil, "off"); eq(b.word, nil, "off")
end
eq(Model.blocks(tam, "頭", false, "<", ">")[2].head, "<头发>  tóufa")
eq(Model.render(tam, "頭", false), "头  tóu\nhead\ntou: suffix for nouns\n\n头发  tóufa\nhair (on the head)"
   .. "\n\n头发  tóu fǎ · not in CC-CEDICT\n人的頭上所生的毛。")
-- Simplified taps unchanged.
eq(headOf("头", "发", "", TT, 1), "发 髮/發")
eq(headOf("头", "发", "", TT, 2), "头发 頭髮")
eq(Model.simpPick(Text.candidates({}, "乾", chars("淨")), QIAN), "干")
eq(Model.simpPick(Text.candidates({}, "乾", chars("隆")), QIAN), "乾")

-- #48: a self-referring variant sense as CC-CEDICT writes it ("variant of
-- 個|个 gè" on 个) is dropped like the simplified one; another form's stays.
local kept = Model.cleanRows("个", {
    { simp = "个", trad = "个", pinyin = "gè", syllables = "gè", defs = "variant of 個|个 gè" },
    { simp = "个", trad = "個", pinyin = "gè", syllables = "gè", defs = "individual/variant of 箇|个 gè" },
})
eq(#kept, 1); eq(table.concat(kept[1].senses, ";"), "individual")
kept = Model.cleanRows("够", { { simp = "够", trad = "夠", pinyin = "gòu", syllables = "gòu",
                                 defs = "variant of 夠|够 gòu/enough" } })
eq(table.concat(kept[1].senses, ";"), "enough")
kept = Model.cleanRows("彀", { { simp = "彀", trad = "彀", pinyin = "gòu", syllables = "gòu",
                                 defs = "variant of 夠|够 gòu" } })
eq(table.concat(kept[1].senses, ";"), "variant of 夠|够 gòu")
-- Dictionary text (#48): the original text, or the simplified copy where
-- there is one; the copies go either way.
local function textRows()
    return { { defs = "variant of 夠|够 gòu", defs_simp = "variant of 够 gòu" }, { defs = "enough" },
             { short = "吝嗇", short_simp = "吝啬", view = "釋義", view_simp = "释义" } }
end
local orig, simp = Model.chooseText(textRows(), false), Model.chooseText(textRows(), true)
eq(orig[1].defs, "variant of 夠|够 gòu"); eq(orig[1].defs_simp, nil); eq(orig[3].short, "吝嗇")
eq(simp[1].defs, "variant of 够 gòu"); eq(simp[2].defs, "enough"); eq(simp[3].short, "吝啬"); eq(simp[3].view, "释义")
eq(simp[3].short_simp, nil)

-- #61: a cross-reference-only entry's target, under the entry's own line;
-- the same text choice; the tapped form's script; none when the row is
-- dropped as a variant of the word itself.
local function xrefRows()
    return { { simp = "贤惠", trad = "賢惠", pinyin = "xiánhuì", syllables = "xián huì",
               defs = "variant of 賢慧|贤慧 xiánhuì",
               xref = { simp = "贤慧", trad = "賢慧", pinyin = "xiánhuì", defs = "wise and kind/see also 賢人|贤人 xiánrén",
                        defs_simp = "wise and kind/see also 贤人 xiánrén" } } }
end
local xo = Model.cleanRows("贤惠", Model.chooseText(xrefRows(), false))
eq(#xo[1].xrefs, 1); eq(xo[1].xrefs[1].word, "贤慧")
eq(table.concat(Model.xrefLines(xo[1]), "|"), "贤慧: wise and kind; see also 賢人|贤人 xiánrén")
local xs = Model.cleanRows("贤惠", Model.chooseText(xrefRows(), true))
eq(table.concat(Model.xrefLines(xs[1]), "|"), "贤慧: wise and kind; see also 贤人 xiánrén")
eq(xrefRows()[1].xref.defs_simp ~= nil, true)
local xt = Model.cleanRows("賢惠", Model.chooseText(xrefRows(), false))
eq(Model.xrefLines(xt[1])[1], "賢慧: wise and kind; see also 賢人|贤人 xiánrén", "tapped in traditional")
local lishi = Model.cleanRows("利是", { { simp = "利是", trad = "利是", pinyin = "lìshì", syllables = "lì shì",
    defs = "variant of 利事 lìshì", xref = { simp = "红包", trad = "紅包", pinyin = "hóngbāo", defs = "red packet" } } })
eq(Model.xrefLines(lishi[1])[1], "红包 hóngbāo: red packet", "a chain: the pinyin too")
local jun = Model.cleanRows("俊", { { simp = "俊", trad = "㑺", pinyin = "jùn", syllables = "jùn",
    defs = "old variant of 俊 jùn", xref = { simp = "俊", trad = "俊", pinyin = "jùn", defs = "handsome" } },
    { simp = "俊", trad = "俊", pinyin = "jùn", syllables = "jùn", defs = "handsome" } })
eq(#jun, 1); eq(jun[1].xrefs, nil, "a variant of the word itself: no target")
eq(#Model.xrefLines({ senses = { "x" } }), 0)
local xm = { { word = "贤惠", start = 0, len = 2, entries = xo } }
eq(table.concat(Model.blocks(xm, "贤", true)[1].lines, "\n"), "variant of 賢慧|贤慧 xiánhuì\n贤慧: wise and kind; see also 賢人|贤人 xiánrén")

-- #62: cross-reference spans in CC-CEDICT lines, and the tapped one first.
local function spanList(lines)
    local out = {}
    for _, sp in ipairs(Model.xrefSpans(lines)) do
        local cs = chars(table.concat(lines, "\n"))
        out[#out + 1] = table.concat(cs, "", sp.from, sp.to) .. "=" .. sp.word .. "/" .. (sp.alt or "") .. "/" .. sp.pinyin
    end
    return table.concat(out, " ; ")
end
eq(spanList({ "variant of 賢慧|贤慧 xiánhuì" }), "賢慧|贤慧 xiánhuì=贤慧/賢慧/xiánhuì")
eq(spanList({ "variant of 贤慧 xiánhuì" }), "贤慧 xiánhuì=贤慧//xiánhuì")
eq(spanList({ "see 河北省 Héběi Shěng" }), "河北省 Héběi=河北省//Héběi Shěng")
eq(spanList({ "CL: 個|个 gè, 隻|只 zhī" }), "個|个 gè=个/個/gè ; 隻|只 zhī=只/隻/zhī")
eq(spanList({ "(bound form) kind (as in 惠顧|惠顾 huìgù)" }), "惠顧|惠顾 huìgù=惠顾/惠顧/huìgù")
eq(spanList({ "Hebei Province, capital 石家莊市|石家庄市 Shíjiāzhuāng Shì (short name 冀 Jì)" }),
   "石家莊市|石家庄市 Shíjiāzhuāng=石家庄市/石家莊市/Shíjiāzhuāng Shì ; 冀 Jì=冀//Jì")
eq(spanList({ "variant of 賢慧|贤慧 xiánhuì", "贤慧: wise and kind" }),
   "賢慧|贤慧 xiánhuì=贤慧/賢慧/xiánhuì ; 贤慧=贤慧//", "a lead-in line")
eq(spanList({ "branch of Xianbei 鮮卑|鲜卑", "Huì: surname Hui" }), "", "no pinyin, no lead-in: none")
eq(spanList({ "a 人: b" }), "", "a colon not at the line's start")
eq(spanList({ "see 吕梁市 Lǚliáng Shì" }), "吕梁市 Lǚliáng=吕梁市//Lǚliáng Shì", "ü after the #63 fix")
local sp = Model.xrefSpans({ "variant of 賢慧|贤慧 xiánhuì" })[1]
eq(Model.spanOffset(sp, 12), 1); eq(Model.spanOffset(sp, 13), 2); eq(Model.spanOffset(sp, 15), 1)
eq(Model.spanOffset(sp, 16), 2); eq(Model.spanOffset(sp, 19), 1, "on the pinyin")
local function mm()
    return { { word = "合", len = 1, entries = { { pinyin = "hé" }, { pinyin = "gě" } } },
             { word = "合格", len = 2, entries = { { pinyin = "hégé" } } } }
end
local sf = Model.spanFirst(mm(), { word = "合", pinyin = "gě" })
eq(sf[1].word, "合"); eq(sf[1].entries[1].pinyin, "gě")
sf = Model.spanFirst(mm(), { word = "合格", alt = "閤格", pinyin = "hégé" })
eq(sf[1].word, "合格"); eq(sf[2].word, "合")
sf = Model.spanFirst({ { word = "河", entries = {} }, { word = "河北省", entries = { { pinyin = "x" }, { pinyin = "Héběi Shěng" } } } },
    { word = "河北省", pinyin = "Héběi Shěng" })
eq(sf[1].word, "河北省"); eq(sf[1].entries[1].pinyin, "Héběi Shěng")
sf = Model.spanFirst(mm(), { word = "茄萣", pinyin = "Qiédìng" })
eq(sf[1].word, "合", "not there: unchanged")

------------------------------------------------------------------------
-- Citation tones for ties the traditional form can't break (#52)
------------------------------------------------------------------------
local function cands(...)
    local out = {}
    for _, c in ipairs({ ... }) do out[#out + 1] = { text = c[1], start = c[2], len = select(2, c[1]:gsub("[^\128-\191]", "")) } end
    return out
end
eq(Model.citationPick(cands({ "处", 0 }, { "好处", -1 }), "处"), "chù", "好处")
eq(Model.citationPick(cands({ "處", 0 }, { "好處", -1 }), "處"), "chù", "好處")
eq(Model.citationPick(cands({ "应", 0 }, { "答应", -1 }, { "满口答应", -3 }), "应"), "yìng", "满口答应")
eq(Model.citationPick(cands({ "处", 0 }, { "处理", 0 }), "处"), nil, "处理: not listed")
eq(Model.citationPick(cands({ "好", 0 }, { "好处", 0 }), "好"), nil, "only the listed character")

------------------------------------------------------------------------
-- The Classical dictionary's blocks (#53)
------------------------------------------------------------------------
local fa = {
    { trad = "發", simp = "发", senses = "fā\tto shoot (an arrow)\tCN\nfā\tto open; to uncover\tCN,Wikt" },
    { trad = "髮", simp = "发", senses = "\thair of the head\tCN" },
}
local cb = Model.classicalBlocks(fa, "发", "髮", "**", "**", true)
eq(#cb, 1, "the word's form only (头发 → 髮)")
eq(cb[1].head, "**发** • 髮"); eq(cb[1].word, "发"); eq(cb[1].trad, "髮"); eq(cb[1].source, "classical")
assert(cb[1].classical and not cb[1].collapse, "never collapsed (#56)")
eq(table.concat(cb[1].lines, " | "), "hair of the head")
cb = Model.classicalBlocks(fa, "发", nil, "**", "**", true)
eq(#cb, 2, "no word decides: each form")
eq(table.concat(cb[1].lines, " | "), "1. fā: to shoot (an arrow) | 2. fā: to open; to uncover", "numbered when several (#67)")
cb = Model.classicalBlocks(fa, "發", nil, "**", "**", true)
eq(#cb, 1, "tapped in traditional: its own entry"); eq(cb[1].head, "**发** • 發")
cb = Model.classicalBlocks(fa, "髮", nil, "**", "**", false)
eq(cb[1].head, "**发**", "Show traditional in headwords off: the word alone"); eq(cb[1].trad, nil)
local zhi = Model.classicalBlocks({ { trad = "之", simp = "之", senses = "\thim; her; it\tCN,Wikt" } }, "之", nil, "", "", true)
eq(zhi[1].head, "之"); eq(zhi[1].trad, nil, "the same form: nothing beside it")
eq(#Model.classicalBlocks({}, "的", nil), 0, "no entry: nothing")
eq(#Model.classicalBlocks({ { trad = "x", simp = "x", senses = "" } }, "x", nil), 0, "no senses: nothing")
eq(Model.SOURCE_LABELS.classical, "文言")

-- #67: the Classical entries of the words around the tapped character.
local wrows = {
    { trad = "所以", simp = "所以", senses = "\tthat by which\tCN,Wikt\n\tthe reason why\tWikt" },
    { trad = "賤人", simp = "贱人", senses = "\ta lowly person\tCN,Wikt" },
}
local wm = { { word = "贱人", len = 2 }, { word = "人", len = 1 }, { word = "所以", len = 2 }, { word = "賤人", len = 2 } }
local wb = Model.classicalWordBlocks(wrows, wm, "**", "**", true)
eq(#wb, 2, "one block per word with an entry, each once")
eq(wb[1].head, "**贱人** • 賤人", "in the order of the matches"); eq(wb[1].source, "classical")
eq(table.concat(wb[1].lines, " | "), "a lowly person", "one sense: no number")
eq(table.concat(wb[2].lines, " | "), "1. that by which | 2. the reason why")
eq(#Model.classicalWordBlocks({}, wm), 0, "no entries: nothing")
