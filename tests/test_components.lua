-- Character components (ch_components.lua): the row format, the popup block,
-- the traditional form picked by the word, and the real database's rows for
-- the characters checked on the device.
local Components = require("ch_components")
local DB = require("ch_db")
local H = require("sq3_shim")
local Model = require("ch_popup_model")
local Text = require("ch_text")
local eq = H.eq

eq(DB.COMPONENTS_SQL, PY_COMPONENTS_SQL, "components SQL")
eq(DB.NOTES_SQL, PY_NOTES_SQL, "notes SQL")

-- Parsing.
local c = Components.parse("H\twikt\tpsc\td\t\t\t\nP\t氵\t水\ts\tshuǐ\twater (三点水)\t\t\nP\t青\t青\tp\tqīng\tgreen\tsame\ta")
eq(c.source, "wikt"); eq(c.type, "psc"); eq(c.disputed, true); eq(c.via, nil); eq(#c.changes, 0)
eq(c.choices, nil); eq(#c.parts, 2)
eq(c.parts[1].form, "氵"); eq(c.parts[1].lookup, "水"); eq(c.parts[1].role, "s"); eq(c.parts[1].abbr, false)
eq(c.parts[2].match, "same"); eq(c.parts[2].abbr, true)
c = Components.parse("H\twikt\tpsc\t\t觀\t雚>又,見>见\t\nP\t雚\t\tp\tguàn\tstork\tsame\t")
eq(c.via, "觀"); eq(#c.changes, 2); eq(c.changes[1][1], "雚"); eq(c.changes[1][2], "又")
eq(c.parts[1].lookup, nil, "no button")
c = Components.parse("H\t\t\t\t\t\t發=;髮=癶>x")
assert(not Components.hasContent(c), "choices only")
assert(c.choices["發"] and #c.choices["發"] == 0 and c.choices["髮"][1][2] == "x")
eq(Components.parse(""), nil); eq(Components.parse(nil), nil)

-- Role texts.
eq(Components.roleText({ role = "s" }), "→ meaning")
eq(Components.roleText({ role = "p", match = "same" }), "→ sound (same sound)")
eq(Components.roleText({ role = "p", match = "ending" }), "→ sound (same ending)")
eq(Components.roleText({ role = "p", match = "loose", abbr = true }), "→ sound, abbreviated (loose)")
eq(Components.roleText({ role = "p", match = "" }), "→ sound")
eq(Components.roleText({ role = "" }), "")

-- The block.
local block = Components.block(Components.parse(
    "H\twikt\tpsc\t\t觀\t雚>又\t\nP\t雚\t雚\tp\tguàn\t(archaic) stork; heron\tsame\t\nP\t見\t見\ts\tjiàn\tsee\t\t"),
    "<", ">")
eq(block.source, "wikt"); eq(block.components, true)
eq(table.concat(block.lines, "\n"),
   "traditional 觀:\n<雚> guàn  (archaic) stork; heron  → sound (same sound)\n<見> jiàn  see  → meaning\nsimplified: 雚 → 又")
block = Components.block(Components.parse("H\twikt\tpictogram\td\t\t\t"))
eq(table.concat(block.lines, "\n"), "pictogram (象形)", "disputed: no extra line")
eq(Components.block(Components.parse("H\t\t\t\t\t\t發=")), nil, "nothing of its own")

-- The traditional form from the word: 发 in 头发 is 髮, in 发现 發.
local choices = { ["發"] = {}, ["髮"] = {} }
local function cands(left, right)
    local l, r = Text.chars(left), Text.chars(right)
    return (Text.candidates(l, "发", r))
end
local rows = { { simp = "头发", trad = "頭髮" }, { simp = "发现", trad = "發現" }, { simp = "发", trad = "發" } }
eq(Components.pickTrad(cands("头", ""), rows, choices), "髮")
eq(Components.pickTrad(cands("", "现"), rows, choices), "發")
eq(Components.pickTrad(cands("", ""), rows, choices), nil, "the character alone does not say")
eq(Components.pickTrad(cands("头", ""), { { simp = "头发", trad = "頭髮", source = "wikt" } }, choices), nil,
   "only CC-CEDICT's words")
eq(Components.pickTrad(cands("头", ""), rows, nil), nil)

-- The real database.
local db = H.db()
local function lookup(list) return db:components(list) end
local function show(ch, left, right)
    local cs, texts = Text.candidates(Text.chars(left or ""), ch, Text.chars(right or ""))
    local r = db:lookup(texts)
    local comp, via, changes, notes = Components.resolve(ch, lookup, cs, r)
    local blk = comp and Components.block(comp, "", "", via, changes)
    return blk and table.concat(blk.lines, "\n") or nil, blk, notes
end
local function has(text, s, what) assert(text and text:find(s, 1, true), what .. ": " .. tostring(text)) end

local t, blk = show("髡")
has(t, "髟 biāo", "髡"); has(t, "→ meaning", "髡"); has(t, "兀 wù", "髡"); has(t, "→ sound (loose)", "髡")
t = show("清")
has(t, "氵 shuǐ  water (三点水)  → meaning", "清 radical form"); has(t, "青 qīng", "清"); has(t, "(same sound)", "清")
local notes
t, blk, notes = show("观")
eq(blk.source, "wikt")
has(t, "traditional 觀:", "观"); has(t, "雚 guàn", "观"); has(t, "見 jiàn  see  → meaning", "观")
has(t, "simplified: 雚 → 又", "观")
eq(table.concat(notes, ","), "观,觀", "origin notes of both forms")
assert(not t:find("又 yòu", 1, true), "MMAH's 又+见 is not used")
t = show("鸡")
has(t, "traditional 雞:", "鸡"); has(t, "奚 xī", "鸡"); has(t, "(same ending)", "鸡 jī / 奚 xī")
t = show("茴")
has(t, "艹 cǎo", "茴"); has(t, "回 huí", "茴"); has(t, "(same sound)", "茴")
t = show("廪")
has(t, "广", "廪"); has(t, "㐭 lǐn", "廪"); has(t, "禾", "廪")
-- 秋: Wiktionary's analysis has 𤒅 (outside the BMP: a box on the device), so
-- the next source's is shown; nothing shown anywhere has such a character.
t, blk = show("秋")
assert(not t:find("𤒅", 1, true), "秋: no box")
has(t, "禾 hé", "秋"); has(t, "火 huǒ", "秋")
t = show("铳")
has(t, "钅 jīn  metal (金字旁)  → meaning", "铳: 銃's analysis, 金 written 钅"); has(t, "充 chōng", "铳")
assert(not t:find("traditional", 1, true), "铳: the simplification hides nothing")
t, blk, notes = show("铳")
eq(table.concat(notes, ","), "铳,銃", "铳: 銃's origin note")
t = show("陈")
has(t, "阝 fù", "陈: left 阝 is 阜"); has(t, "左耳旁", "陈"); has(t, "东 dōng", "陈: 東 written 东")
t = show("郎")
has(t, "阝 yì", "郎: right 阝 is 邑"); has(t, "右耳旁", "郎"); has(t, "良 liáng", "郎")
has(t, "(same ending)", "郎 láng / 良 liáng")
t = show("发", "头", "")
has(t, "traditional 髮:", "发 in 头发"); has(t, "髟", "髮")
t = show("发", "", "现")
has(t, "traditional 發:", "发 in 发现")
eq(show("发"), nil, "发 alone: no form chosen, nothing of its own")
t, blk = show("钺")
has(t, "戉 yuè", "钺"); has(t, "(same sound)", "钺"); eq(blk.source, "wikt")
eq(show("卍"), nil, "no data")
t, blk = show("龘")
eq(blk.source, "ids"); has(t, "龍 lóng", "龘"); assert(not t:find("→", 1, true), "structure only: no roles")

-- Every row parses and renders, with no character outside the BMP (a
-- 4-byte UTF-8 sequence starts with a byte >= 0xF0), nor any origin note.
local n, shown = 0, 0
db:each("SELECT text FROM component_notes", nil, function(row)
    assert(not row[1]:find("[\240-\247]"), "note outside the BMP")
end)
db:each("SELECT ch, body FROM components", nil, function(row)
    n = n + 1
    assert(not row[2]:find("[\240-\247]"), "outside the BMP: " .. row[1])
    local pc = Components.parse(row[2])
    assert(pc, "parses: " .. row[1])
    if Components.block(pc, "", "") then shown = shown + 1 end
end)
assert(n > 13000 and shown > 13000, "rows " .. n .. ", shown " .. shown)

-- Labels for the blocks' sources.
eq(Model.SOURCE_LABELS.mmah, "MMAH"); eq(Model.SOURCE_LABELS.ids, "IDS"); eq(Model.SOURCE_LABELS.wikt, "Wikt")
print("components: ok")
