-- The bundled MOE dictionaries (#86, ch_moe.lua): the SQL matches
-- tools/build_moe.py's, the test file (tests/run.py make_test_moe) reads as
-- the plugin needs it, and the text helpers show MOE's text only selected
-- and laid out. Then, when the plugin's data/moe/ is there, the real file.
local H = require("sq3_shim")
local eq = H.eq
local Moe = require("ch_moe")

for _, n in ipairs({ 1, 2, 16 }) do
    for _, unc in ipairs({ false, true }) do
        eq(Moe.revisedSql(n, unc), PY_MOE_REVISED_SQL(n, unc), "revised SQL for " .. n)
        eq(Moe.idiomsSql(n, unc), PY_MOE_IDIOMS_SQL(n, unc), "idioms SQL for " .. n)
    end
end

-- Text helpers.
eq(Moe.boxed("見\243\186\159\145字"), "見□字", "a plane-15 private-use character")
eq(Moe.boxed("俗名&9A6C._104_0.gif;田藨"), "俗名□田藨", "an image code")
eq(Moe.hasBox("𤆬"), true, "outside the BMP"); eq(Moe.hasBox("一毛不拔"), false)
local senses = Moe.revisedSenses("[名]\r\n1.甲。\r\n2.乙/丙。\r\n[動]\r\n丁。\r\n")
eq(table.concat(senses, "|"), "[名] 1.甲。|2.乙／丙。|[動] 丁。")
eq(#Moe.revisedSenses(nil), 0)
eq(Moe.firstReading("yī máo bù bá （變） yì máo bù bá"), "yī máo bù bá")
eq(Moe.shorten("一二三。四五六。", 5), "一二三。"); eq(Moe.shorten("一二三", 5), "一二三")
eq(Moe.shorten("一二三四五六", 5), "一二三四五六", "no sentence end: whole")
eq(Moe.ownExplanation("猶「玉石俱焚」。見「玉石俱焚」條。"), "猶「玉石俱焚」。")
eq(Moe.ownExplanation("一根毫毛。\r\n△「愛財如命」"), "一根毫毛。")
eq(Moe.ownExplanation("比喻。01.《書》"), "比喻。")
eq(table.concat(Moe.sourceText("孟子曰：「\r\n*1*楊子\r\n取為我。」\r\n#子莫執中"), "|"), "孟子曰：「楊子取為我。」|子莫執中")
eq(Moe.sourceTitle("※《甲》\r\n※《乙》"), "《甲》；《乙》")
eq(table.concat(Moe.linesOf("甲＆乙\r\n　丙　"), "|"), "甲|乙|丙")
-- (Cases from the Python build's tests, before the 成語典 was bundled.)
eq(table.concat(Moe.sourceText("昔日*1*齷齪\r\n不足誇。\r\n＋\r\n唐詩*1*情深詞婉\r\n，故有久久莫知其意者。"), "|"),
   "昔日齷齪不足誇。|唐詩情深詞婉，故有久久莫知其意者。", "＋ between passages: a new paragraph")
eq(table.concat(Moe.sourceText("甲。\r\n＆\r\n乙。"), "|"), "甲。|乙。")
eq(table.concat(Moe.linesOf("比喻甲。褒義。＆比喻乙。褒義。"), "|"), "比喻甲。褒義。|比喻乙。褒義。")
eq(table.concat(Moe.linesOf("注一。\r\n＋\r\n注二。"), "|"), "注一。|注二。")
eq(Moe.oneLine("比喻甲。褒義。＆比喻乙。\r\n"), "比喻甲。褒義。比喻乙。")
eq(Moe.sourceTitle("＃《莊子．山木》*1*"), "《莊子．山木》")
eq(Moe.sourceTitle("※《醒世姻緣傳》第三四回\r\n※《水滸傳》第二四回"), "《醒世姻緣傳》第三四回；《水滸傳》第二四回")
eq(Moe.sourceTitle("◎1宋．王之道〈惜奴嬌〉詞"), "宋．王之道〈惜奴嬌〉詞")
eq(Moe.ownExplanation("一根毫毛也不願意拔取。※語本《孟子》。 \r\n△「愛財如命」"), "一根毫毛也不願意拔取。語本《孟子》。")
eq(Moe.shorten(string.rep("甲。", 60), 10), string.rep("甲。", 5))
-- A related entry takes its main entry's source text and story, headed with its name.
local main_rec = { ["成語"] = "玉石俱焚", ["典源文獻名稱"] = "《書經．胤征》", ["典源文獻內容"] = "火炎*1*崐岡\r\n，玉石俱焚。",
                   ["典源注解"] = "崐岡：崑崙山。", ["典故說明"] = "夏帝仲康時……", ["用法說明-語義說明"] = "比喻好壞同時受害。" }
local sub = Moe.idiomText({ ["成語"] = "玉石俱碎", ["漢語拼音"] = "yù shí jù suì",
    ["釋義"] = "猶「玉石俱焚」。見「玉石俱焚」條。01.陳琳〈檄〉：「玉石俱碎。」",
    ["典源文獻內容"] = "此處所列為「玉石俱焚」之典源，提供參考。", ["書證"] = "01.陳琳〈檄〉：「玉石俱碎。」（源）",
    ["主條成語／非主條成語"] = "非主條成語" }, main_rec, true)
eq(sub.short, "猶「玉石俱焚」。比喻好壞同時受害。")
assert(sub.view:find("^释义\n猶「玉石俱焚」。\n\n书证\n01.陳琳〈檄〉：「玉石俱碎。」\n\n"), sub.view)
assert(sub.view:find("典源（玉石俱焚）　《書經．胤征》\n火炎崐岡，玉石俱焚。", 1, true), sub.view)
assert(sub.view:find("典故说明（玉石俱焚）\n夏帝仲康時……", 1, true), sub.view)
assert(not sub.view:find("提供參考", 1, true))
eq(Moe.idiomText({ ["釋義"] = "火聲。見\243\186\159\145字。", ["主條成語／非主條成語"] = "非主條成語" }).view, "",
   "a line with a character MOE could not encode is left out")

-- The test file.
local rdb = assert(Moe.open(TEST_MOE_PATH, "revised", H.SQ3))
local idb = assert(Moe.open(TEST_MOE_PATH, "idioms", H.SQ3))
eq(rdb:hasCovered(), true); eq(idb:hasCovered(), false)
local function text(rows)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = table.concat({ r.simp, r.trad, r.pinyin, r.defs, r.source, tostring(r.covered) }, "|")
    end
    return table.concat(out, "\n")
end
eq(text(rdb:fallback({ "丁匠" })), "丁匠|丁匠|dīng jiàng|官府徵調的工匠。|moe|false", "MOE's own text, traditional")
eq(text(rdb:fallback({ "和", "涓", "颶風", "飓风" })), "", "words CC-CEDICT has: never a fallback entry")
eq(text(rdb:fallbackAll({ "和" })), "和|和|hé|[動] 1.連帶。/2.平靜。|moe|true\n和|和|hàn|[連] 連詞。|moe|true",
   "both readings, CC-CEDICT's or not, in MOE's order; the reading's stray space trimmed")
eq(text(rdb:fallbackAll({ "飓风" })), "飓风|颶風|jù fēng|熱帶氣旋。／風暴。|moe|true",
   "found by its simplified key; MOE's / drawn as ／ (a / separates senses)")
eq(#rdb:fallback({ "很大" }), 0, "an everyday combination has no key")
local hidden = {}
rdb:each("SELECT reason FROM revised_hidden ORDER BY id", nil, function(row) hidden[#hidden + 1] = row[1] end)
eq(table.concat(hidden, "|"), "degree adverb + word|not 1-8 Han characters")
eq(text(rdb:fallback({ "𤆬" })), "𤆬|𤆬|chuā|火聲。見□字。|moe|false", "MOE's private-use character drawn as □")
eq(rdb:idioms({ "一毛不拔" })[1], nil, "the 重編國語辭典 has no idioms")

local irows = idb:idioms({ "一毛不拔", "玉石俱碎", "东西" })
eq(#irows, 2)
eq(irows[1].simp, "一毛不拔"); eq(irows[1].short, "形容人非常吝嗇。貶義。")
eq(irows[1].view, "释义\n一根毫毛也不願意拔取。\n\n典源　《孟子．盡心上》\n孟子曰：「楊子取為我，拔一毛而利天下，不為也。」"
    .. "\n\n注解\n楊子：楊朱。\n\n用法\n形容人非常吝嗇。貶義。\n\n近义：愛財如命")
eq(irows[2].short, "猶「玉石俱焚」。比喻好壞同時受害。", "MOE's two sentences, as written")
assert(irows[2].view:find("书证\n01.《晉書》：「玉石俱碎。」", 1, true), irows[2].view)
eq(text(idb:fallback({ "一毛不拔", "玉石俱碎" })), "玉石俱碎|玉石俱碎|yù shí jù suì|猶「玉石俱焚」。比喻好壞同時受害。|idioms|nil",
   "a fallback entry only for the idiom CC-CEDICT lacks")
eq(#idb:fallbackAll({ "玉石俱碎" }), 0)
rdb:close(); idb:close()

-- No MOE table has a simplified column, and the key tables hold no MOE text.
local function columns(db, tbl)
    local out = {}
    db:each("PRAGMA table_info(" .. tbl .. ")", nil, function(row) out[#out + 1] = row[2] end)
    return table.concat(out, ",")
end
local function checkColumns(path)
    local db = assert(Moe.open(path, "revised", H.SQ3))
    for _, tbl in ipairs({ "revised", "idioms" }) do
        assert(not columns(db, tbl):find("simp", 1, true), tbl .. ": " .. columns(db, tbl))
    end
    eq(columns(db, "revised_keys"), "simp,trad,id,covered")
    eq(columns(db, "revised_hidden"), "id,reason")
    eq(columns(db, "idioms_keys"), "simp,trad,id,covered,main,equals")
    local tables = {}
    db:each("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name", nil, function(row)
        tables[#tables + 1] = row[1]
    end)
    eq(table.concat(tables, ","), "idioms,idioms_keys,meta,revised,revised_hidden,revised_keys")
    db:close()
end
checkColumns(TEST_MOE_PATH)

-- The real bundled file, when this checkout has it (it ships in the release zip).
local real = PLUGIN_DIR .. "/data/moe/moe.sqlite"
local f = io.open(real, "rb")
if f then
    f:close()
    checkColumns(real)
    local r = assert(Moe.open(real, "revised", H.SQ3))
    local i = assert(Moe.open(real, "idioms", H.SQ3))
    local m = r:meta()
    assert(m.revised_version:match("^%d%d%d%d%-%d%d%-%d%d$"), m.revised_version)
    assert(m.revised_attribution:find("重編國語辭典修訂本", 1, true) and m.idioms_attribution:find("成語典", 1, true))
    eq(m.license_uri, "https://creativecommons.org/licenses/by-nd/3.0/tw/")
    assert(tonumber(m.revised_records) > 160000 and tonumber(m.idioms_records) > 5000)
    local qiu = r:fallbackAll({ "秋" })
    eq(qiu[1].pinyin, "qiū"); assert(qiu[1].defs:find("[名] 1.一年四季中的第三季。", 1, true), qiu[1].defs)
    eq(qiu[1].covered, true)
    local yuan = r:fallback({ "秋月春风" })
    eq(#yuan, 1); eq(yuan[1].trad, "秋月春風"); assert(yuan[1].defs:find("比喻美好的時光", 1, true))
    local idiom = i:idioms({ "刻舟求剑" })[1]
    assert(idiom and idiom.trad == "刻舟求劍" and idiom.view:find("典源", 1, true), "刻舟求剑's view")
    r:close(); i:close()
    print("  (the bundled data/moe/moe.sqlite checked)")
else
    print("  (no " .. real .. ": skipped)")
end
print("MOE: ok")
