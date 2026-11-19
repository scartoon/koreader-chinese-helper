-- The reader's own frequency ranks (#42): the file, the fallback to the
-- bundled rank, the data gates that must not move, the 字频 line and the
-- crowding tie-break.
local H = require("sq3_shim")
local eq = H.eq
local Ranks = require("ch_ranks")
local Resolve = require("ch_resolve")
local Readings = require("ch_readings")
local Layout = require("ch_layout")
local Model = require("ch_popup_model")
local Settings = require("ch_settings")

-- The file.
local parsed = Ranks.parse(table.concat({
    "# chinesehelper user ranks (tools/build_user_ranks.py)",
    "# date\t2026-11-19", "# works\t42", "# han\t41325818", "# ranked\t3", "# exact\t5700",
    "# char\trank\tworks\toccurrences",
    "的\t1\t42\t1681478", "饕\t20\t40\t900", "這\t2\t42\t5000", "",
}, "\n"))
eq(parsed.ranks["的"], 1)
eq(parsed.ranks["饕"], 20)
eq(parsed.ranks["這"], 2)
eq(parsed.info.works, 42)
eq(parsed.info.date, "2026-11-19")
eq(parsed.info.exact, 5700)
eq(parsed.info.rows, 3)
eq(Ranks.parse("# date\t2026-11-19\n"), nil, "no rows: no ranks")
eq(Ranks.parse(""), nil)
eq(Ranks.parse("的\t1\t1\t1\r\n").ranks["的"], 1, "CRLF")
eq(Ranks.load("/nonexistent/chinesehelper_ranks.tsv"), nil)

-- Settings: bundled unless From my books is chosen.
do
    local store = {}
    local s = Settings.new({ readSetting = function(_, k) return store[k] end,
                             saveSetting = function(_, k, v) store[k] = v end })
    eq(s:rankSource(), "bundled")
    s:set("rank_source", "books")
    eq(s:rankSource(), "books")
    s:set("rank_source", "nonsense")
    eq(s:rankSource(), "bundled")
end

local data = H.readings()
local pub_de, pub_tao, pub_bu = data:char("的"), data:char("饕"), data:char("不")
assert(pub_de == 1 and pub_tao > 3500 and pub_bu < 1000, "bundled ranks as expected")
local words_before = 0
for _ in pairs(data.words) do words_before = words_before + 1 end

local function items_of(text)
    local items = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        items[#items + 1] = { text = ch, joined = #items > 0, on_page = true }
    end
    return items
end
local function drawn(text, threshold)
    local items = items_of(text)
    local out = {}
    for _, a in ipairs(Resolve.annotate(data, items, threshold or 3500)) do out[#out + 1] = items[a.index].text end
    return table.concat(out)
end

-- Off: bundled ranks.
eq(drawn("饕餮的不"), "饕餮")
eq(select(2, data:rankInfo("饕")), nil, "no source while off")

-- On: 饕 common in my books, 的 rare in them (made up), 餮 absent: bundled.
data:setUserRanks({ ["饕"] = 120, ["的"] = 4000 }, 3000)
eq((data:char("饕")), 120)
eq((data:char("的")), 4000)
eq((data:char("餮")), (data:publicRank("餮")), "absent: bundled rank")
eq(data:publicRank("饕"), pub_tao, "bundled rank kept for the data gates")
eq(drawn("饕餮的不"), "餮的")
local r, src, exact = data:rankInfo("饕")
eq(r, 120); eq(src, "books"); eq(exact, 3000)
r, src, exact = data:rankInfo("餮")
eq(src, "bundled"); eq(exact, nil)

-- Data gates: what is held in memory, and what is looked up, are unchanged.
eq(data:hasRare("饕餮"), true, "饕餮 still a word with a rare character")
eq(data:hasRare("的确"), false, "的确 still all common")
local words_after = 0
for _ in pairs(data.words) do words_after = words_after + 1 end
eq(words_after, words_before, "no words loaded or dropped")
eq(Readings.RARE_RANK, 1000)
-- 的 now gets pinyin: its word comes from the lookup, as for any common character.
eq(drawn("的确", 3500), "的")

-- Off again: bundled.
data:setUserRanks(nil)
eq((data:char("饕")), pub_tao)
eq(drawn("饕餮的不"), "饕餮")

-- The 字频 line.
eq(Model.rankText(1200), "字频 1,200", "off: unchanged")
eq(Model.rankText(120, "books", 5700), "字频 120")
eq(Model.rankText(5700, "books", 5700), "字频 5,700")
eq(Model.rankText(5701, "books", 5700), "字频 5,700+", "past the file's exact ranks")
eq(Model.rankText(6500, "bundled", nil), "字频 6,500 (bundled)")
eq(Model.rankText(7001, "bundled", 5700), "字频 7,000+ (bundled)", "bundled keeps 7,000")
eq(Model.rankText(0, "bundled"), "字频 unranked (bundled)")
eq(Model.rankText(9000, "books", nil), "字频 7,000+", "no cut-off in the file: 7,000")

-- Crowding: equal ranks drop the more common bundled rank first.
do
    local function line(a, b)
        return { { box = { x = 0, w = 10 }, w = 60, rank = 4000, tie = a, name = "a" },
                 { box = { x = 10, w = 10 }, w = 60, rank = 4000, tie = b, name = "b" } }
    end
    local kept = Layout.placeLine(line(2000, 300), 100, 2)
    eq(#kept, 1); eq(kept[1].item.name, "a")
    kept = Layout.placeLine(line(300, 2000), 100, 2)
    eq(kept[1].item.name, "b")
    kept = Layout.placeLine(line(0, 2000), 100, 2)
    eq(kept[1].item.name, "a", "unranked counts as rarest")
    kept = Layout.placeLine(line(nil, nil), 100, 2)
    eq(kept[1].item.name, "b", "no tie: leftmost dropped, as before")
end

-- Resolve.annotate gives the tie (the bundled rank).
do
    data:setUserRanks({ ["饕"] = 4000 }, 3000)
    local items = items_of("饕")
    local a = Resolve.annotate(data, items, 3500)[1]
    eq(a.rank, 4000); eq(a.tie, pub_tao)
    data:setUserRanks(nil)
end

print("user ranks: ok")
