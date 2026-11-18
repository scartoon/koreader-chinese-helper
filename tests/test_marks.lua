-- Reading marks (#26): the marks module with a fake file store, the
-- simplified-form lookups against the real database, the resolver with marks,
-- and the popup's button labels.
local Marks = require("ch_marks")
local Resolve = require("ch_resolve")
local H = require("sq3_shim")
local eq = H.eq

-- A fake store: `content` is what the file holds (nil: no file; false: a
-- file LuaSettings cannot read, which it gives as {}).
local function store(content)
    local st = { content = content, writes = 0, aside = 0 }
    st.read = function()
        if st.content == nil then return {}, false end
        if st.content == false then return {}, true end
        return st.content, true
    end
    st.write = function(data) st.writes = st.writes + 1; st.content = data; return true end
    st.setAside = function() st.aside = st.aside + 1 end
    return st
end

-- Missing file: no marks, nothing written by loading or reading.
local st = store(nil)
local m = Marks.new{ store = st }
eq(m:get("行", "háng"), nil)
eq(select(1, m:count()), 0)
eq(st.writes, 0, "never written at startup")
-- One write per real change, none for a no-op.
eq(m:set("行", "háng", "known"), true); eq(st.writes, 1)
eq(m:set("行", "háng", "known"), false); eq(st.writes, 1, "no change, no write")
eq(m:get("行", "háng"), "known"); eq(m:get("行", "xíng"), nil, "per reading")
eq(st.content.version, 1); eq(st.content.marks["行"]["háng"], "known")
m:set("了", "le", "remind"); m:set("了", "liǎo", "known")
eq(m:get("了", "le"), "remind"); eq(m:get("了", "liǎo"), "known")
local known, remind = m:count(); eq(known, 2); eq(remind, 1)
local list = m:list()
eq(#list, 3); eq(list[1].char .. list[1].reading .. list[1].state, "了leremind")
assert(m:mayRemind("了") and not m:mayRemind("行") and m:mayHave("行"))
eq(m:clear("了", "le"), true); eq(m:get("了", "le"), nil); assert(not m:mayRemind("了"))
eq(m:clearEntry(list[2]), true); eq(m:get("了", "liǎo"), nil)
eq(st.writes, 5)
-- A fresh load reads what was written.
local m2 = Marks.new{ store = st }
eq(m2:get("行", "háng"), "known"); eq(st.writes, 5)
eq(m2:clearAll(), true); eq(select(1, m2:count()), 0); eq(st.writes, 6)
eq(m2:clearAll(), false); eq(st.writes, 6, "nothing to clear: no write")

-- Unreadable file (LuaSettings gives {} for it): no marks, never written at
-- startup, set aside before the first write.
st = store(false)
m = Marks.new{ store = st }
eq(m:get("行", "háng"), nil); eq(st.writes, 0); eq(st.aside, 0)
m:set("行", "háng", "known")
eq(st.aside, 1, "set aside first"); eq(st.writes, 1)
m:set("行", "xíng", "known"); eq(st.aside, 1, "only once")
-- A newer format, or garbage: the same.
for _, content in ipairs({ { version = 2, marks = {} }, { "junk" }, { version = 1, marks = "x" } }) do
    st = store(content)
    m = Marks.new{ store = st }
    eq(m:get("行", "háng"), nil); eq(st.writes, 0)
    m:set("的", "de", "remind"); eq(st.aside, 1)
end
-- Bad entries in a good file are skipped.
st = store{ version = 1, marks = { ["行"] = { ["háng"] = "known", ["xíng"] = "bogus" }, [1] = "x" } }
m = Marks.new{ store = st }
eq(m:get("行", "háng"), "known"); eq(m:get("行", "xíng"), nil)
-- A store that fails to write: the mark is not kept in memory either.
st = store(nil)
st.write = function() return nil, "disk full" end
m = Marks.new{ store = st }
local ok, err = m:set("行", "háng", "known")
eq(ok, nil); eq(err, "disk full"); eq(m:get("行", "háng"), nil)

-- Simplified forms (traditional handled simply: CC-CEDICT's single-character rows).
local db = H.db()
eq(db:simplifiedOf("這", "zhè"), "这"); eq(db:simplifiedOf("这", "zhè"), "这")
eq(db:simplifiedOf("乾", "qián"), "乾"); eq(db:simplifiedOf("乾", "gān"), "干")
local forms = table.concat(db:formsOf("这"), ","); assert(forms:find("這", 1, true), forms)
m = Marks.new{ store = store(nil),
               simplify = function(ch, r) return db:simplifiedOf(ch, r) end,
               variants = function(s) return db:formsOf(s) end }
m:set("這", "zhè", "known")
eq(m:list()[1].char, "这", "stored under the simplified form")
eq(m:get("这", "zhè"), "known"); eq(m:get("這", "zhè"), "known")

-- The resolver with marks (the plugin database's readings and special words).
local data = H.readings()
local special = H.special()
local function items_of(text)
    local items, joined = {}, false
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if Resolve.single_char(ch) and not ch:match("^\227\128") and not ch:match("^\239\188") then
            items[#items + 1] = { text = ch, joined = joined }
            joined = true
        else
            joined = false
        end
    end
    return items
end
local function annotate(text, threshold, marks, uncertain)
    local items = items_of(text)
    local out = {}
    for _, a in ipairs(Resolve.annotate(data, items, threshold, uncertain, special, marks)) do
        out[#out + 1] = items[a.index].text .. "=" .. a.reading .. (a.special and "*" or "") .. (a.remind and "!" or "")
    end
    return table.concat(out, " ")
end
local function marks_with(t)
    local mk = Marks.new{ store = store(nil) }
    for _, e in ipairs(t) do mk:set(e[1], e[2], e[3]) end
    return mk
end
-- No marks: what 2.5 draws, at threshold 1 (every ranked character).
local text = "我去银行，他在银行工作，然后行走回家。"
local base = annotate(text, 1, nil)
assert(base:find("行=háng", 1, true) and base:find("行=xíng", 1, true), base)
local _, hang = base:gsub("行=háng", "")
eq(hang, 2, "both 银行 annotated")
eq(annotate(text, 1, marks_with{}), base, "empty marks change nothing")
-- 行 háng known: bare at every occurrence; 行走 still xíng.
local got = annotate(text, 1, marks_with{ { "行", "háng", "known" } })
assert(not got:find("行=háng", 1, true), got)
assert(got:find("行=xíng", 1, true), got)
eq((got:gsub(" ?行=%S+", "")), (base:gsub(" ?行=%S+", "")), "nothing else changes")
-- All (threshold 0, learner mode, #25): a known reading is bare at every
-- occurrence, the character's other readings and every other character keep
-- their pinyin.
local all = annotate(text, 0, nil)
got = annotate(text, 0, marks_with{ { "行", "háng", "known" }, { "我", "wǒ", "known" } })
assert(not got:find("行=háng", 1, true) and not got:find("我=", 1, true), got)
assert(got:find("行=xíng", 1, true), got)
local function without(str) return (str:gsub(" ?行=%S+", ""):gsub(" ?我=%S+", ""):gsub("^ ", "")) end
eq(without(got), without(all), "All: nothing else changes")
local _, n_all = all:gsub("=", "")
local _, n_got = got:gsub("=", "")
eq(n_got, n_all - 3, "two 银行 háng and one 我 bare")
-- A known reading in a special word is bare (单于 chán, normally drawn bold).
assert(annotate("匈奴单于入塞", 2500, nil):find("单=chán*", 1, true))
got = annotate("匈奴单于入塞", 2500, marks_with{ { "单", "chán", "known" } })
assert(not got:find("单=", 1, true), got)
-- Remind: a common reading drawn at every occurrence below the threshold.
got = annotate("这是书，他是人，也是笔。", 3500, marks_with{ { "是", "shì", "remind" } })
eq(got, "是=shì! 是=shì! 是=shì!", "every occurrence")
-- 那是 is nà shi: that 是 has a reading the mark is not on, so it stays bare.
eq(annotate("这是书，那是笔。", 3500, marks_with{ { "是", "shì", "remind" } }), "是=shì!")
-- The prompting case (#28): 后 hòu remind with 即位后 then 皇太后 three times.
got = annotate("即位后，尊皇太后，皇太后曰，皇太后。", 3500, marks_with{ { "后", "hòu", "remind" } })
eq(got, "后=hòu! 后=hòu! 后=hòu! 后=hòu!", "后 at all four")
-- Remind on another reading of the character: nothing drawn for this one.
eq(annotate("这是书", 3500, marks_with{ { "是", "shi", "remind" } }), "")
-- 得 alone resolves to the pair de/děi: a remind on de shows the pair.
-- (的 did too until #25 made de its hand-checked default.)
eq(annotate("写得好", 3500, marks_with{ { "得", "de", "remind" } }), "得=de/děi!")
eq(annotate("我的书", 3500, marks_with{ { "的", "de", "remind" } }), "的=de!")
-- The uncertainty pair (覃 qín/tán in 姓覃).
local pair = annotate("姓覃", 3500, nil)
eq(pair, "覃=qín/tán")
eq(annotate("姓覃", 3500, marks_with{ { "覃", "qín", "known" } }), pair, "one known: still the pair")
eq(annotate("姓覃", 3500, marks_with{ { "覃", "qín", "known" }, { "覃", "tán", "known" } }), "", "both known: bare")
eq(annotate("姓覃", 9000, nil), "", "common at this threshold: bare")
eq(annotate("姓覃", 9000, marks_with{ { "覃", "tán", "remind" } }), "覃=qín/tán!", "either remind: shown")
-- Repeated, the pair is shown at every occurrence, and hidden at every one
-- when both readings are known.
eq(annotate("姓覃，姓覃", 3500, nil), pair .. " " .. pair, "pair at both")
eq(annotate("姓覃，姓覃", 3500, marks_with{ { "覃", "qín", "known" }, { "覃", "tán", "known" } }), "", "both known: all bare")
-- A rare character marked known is bare at every occurrence.
eq(annotate("饕餮，饕餮，饕餮", 3500, nil), "饕=tāo 餮=tiè 饕=tāo 餮=tiè 饕=tāo 餮=tiè")
eq(annotate("饕餮，饕餮，饕餮", 3500, marks_with{ { "饕", "tāo", "known" } }), "餮=tiè 餮=tiè 餮=tiè", "known: all bare")
-- Mode best: the best guess's mark.
eq(annotate("姓覃", 3500, marks_with{ { "覃", "qín", "known" } }, "best"), "")
eq(annotate("姓覃", 3500, marks_with{ { "覃", "tán", "known" } }, "best"), "覃=qín")

-- The popup's button labels.
m = Marks.new{ store = store(nil) }
eq(m:button("行", "háng", true).text, "I know háng"); eq(m:button("行", "háng", true).next, "known")
eq(m:button("的", "de", false).text, "Remind me: de"); eq(m:button("的", "de", false).next, "remind")
m:set("行", "háng", "known")
eq(m:button("行", "háng", true).text, "Known háng \226\156\147"); eq(m:button("行", "háng", true).next, nil)
m:set("的", "de", "remind")
eq(m:button("的", "de", false).text, "Reminding de \226\156\147"); eq(m:button("的", "de", false).next, nil)
print("reading marks: ok")
