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
eq(Model.SOURCE_LABELS.cedict, "CEDICT"); eq(Model.SOURCE_LABELS.wikt, "Wikt"); eq(Model.SOURCE_LABELS.moe, "MOE")
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

-- The frequency rank's text (#17) and the grey line it shares with the label.
eq(Model.rankText(1), "字频 1")
eq(Model.rankText(4270), "字频 4,270")
eq(Model.rankText(7000), "字频 7,000")
eq(Model.rankText(7001), "字频 7,000+")
eq(Model.rankText(0), "字频 unranked")
eq(Model.rankText(nil), "字频 unranked")
eq(Model.labelText({ source = "cedict" }, false, Model.SOURCE_LABELS), nil, "no label, no rank: no line")
eq(Model.labelText({ source = "cedict", rank = "字频 4,270" }, false, Model.SOURCE_LABELS), "字频 4,270")
eq(Model.labelText({ source = "cedict", rank = "字频 4,270" }, true, Model.SOURCE_LABELS), "CEDICT · 字频 4,270",
   "label mode all: one line")
eq(Model.labelText({ source = "wikt" }, true, Model.SOURCE_LABELS), "Wikt")
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
eq(tb.head, "<观>  guān", "head unchanged")
eq(tb.word, "观"); eq(tb.rest, "  guān")
eq(Model.render(matches("", "观", "", { row("观", "觀", "guān", "to look at") }), "观", false, nil, nil, true),
   "观 觀  guān\nto look at")
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
-- A character that is one of its own traditional forms: listed with them.
eq(tradOf("", "干", "", { row("干", "乾", "gān", "dry"), row("干", "幹", "gàn", "to do"),
                          row("干", "干", "gān", "shield") }, 1), "乾/干/幹",
   "the head reading gān's forms first")
-- A traditional text: the word as tapped is the traditional form.
eq(tradOf("頭", "髮", "", { row("发", "髮", "fà", "hair"), row("头发", "頭髮", "tóufa", "hair") }, 1), nil)
eq(tradOf("頭", "髮", "", { row("发", "髮", "fà", "hair"), row("头发", "頭髮", "tóufa", "hair") }, 2), nil)
eq(tradOf("", "觀", "", { row("观", "觀", "guān", "to look at") }), nil)
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
