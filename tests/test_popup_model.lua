-- What the popup shows (ch_popup_model.lua): ordering and row cleaning (from
-- koreader-chinese-popup's tests), reading markers, the deciding word, the
-- header, and placement.
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
-- Ordering (unchanged from chinese-popup)
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
eq(Model.render(m, "乐", true), "乐  yuè · shown above\nmusic\nlè: happy; cheerful\nLè: surname Le")
-- An uncertain pair marks both.
m = matches("", "乐", "", yue, { chosen = "yuè/lè" })
assert(m[1].entries[1].marked and m[1].entries[2].marked and not m[1].entries[3].marked, "both of a pair marked")
-- One reading only: nothing to point at, no marker.
m = matches("", "靠", "", { row("靠", "靠", "kào", "to lean") }, { chosen = "kào" })
eq(Model.render(m, "靠", true), "靠  kào\nto lean")
-- A neutral tone in CC-CEDICT stands for the toned reading: 瘩 "da" is dā.
m = matches("", "瘩", "", { row("瘩", "瘩", "da", "see 疙瘩"), row("瘩", "瘩", "tǎ", "sore") }, { chosen = "dā" })
eq(join(m[1].entries, "pinyin"), "da,tǎ"); assert(m[1].entries[1].marked)
-- A chosen reading CC-CEDICT does not list for the character: shown, empty.
m = matches("", "乐", "", yue, { chosen = "yào" })
eq(m[1].entries[1].pinyin, "yào"); assert(m[1].entries[1].missing and m[1].entries[1].marked)
assert(Model.render(m, "乐", true):find("yào · shown above\nno separate CC-CEDICT entry for this reading", 1, true))

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
assert(text:find("宛  yuān · shown above\nsee 大宛\nwǎn: winding", 1, true), text)
assert(text:find("大宛  Dàyuān · decides 宛's reading\nDayuan, ancient state", 1, true), text)
-- Not in CC-CEDICT (a special word with a note): listed anyway, with the note.
m = matches("", "冒", "顿", { row("冒", "冒", "mào", "to emit") },
    { chosen = "mò", annotated = true, decided = { word = "冒顿", start = 0, len = 2, syllables = "mò dú",
                                                   note = "Modu, Xiongnu ruler" } })
eq(join(m, "word"), "冒,冒顿")
text = Model.render(m, "冒", true)
assert(text:find("冒  mò · shown above\nno separate CC-CEDICT entry for this reading\nmào: to emit", 1, true), text)
assert(text:find("冒顿  mò dú · decides 冒's reading\nModu, Xiongnu ruler", 1, true), text)
-- A pypinyin-only word: no definition.
m = matches("", "甲", "乙", {}, { chosen = "jiǎ", decided = { word = "甲乙", start = 0, len = 2, syllables = "jiǎ yǐ" } })
eq(join(m, "word"), "甲乙"); assert(Model.render(m, "甲", false):find("no definition in CC-CEDICT", 1, true))

------------------------------------------------------------------------
-- Header and placement
------------------------------------------------------------------------
eq(Model.header(chars("这个"), "历", chars("史挺靠谱"), "<b>", "</b>"), "这个<b>历</b>史挺靠谱")
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
