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

-- The popup for the n-th occurrence (default 1) of `char` in `text`, as
-- ch_tap.lua builds it: the page items resolve the reading, the Han run of
-- up to 7 characters each side gives the candidate words.
local function popup(text, char, opts)
    opts = opts or {}
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
    local chosen, decided = Resolve.forPopup(data, items, i, mode, special, drawn)
    local cands, texts = Text.candidates(left, char, right)
    data:prefetch(texts)
    local matches = Model.matches{
        cands = cands, rows = db:lookup(texts), chosen = chosen, annotated = drawn ~= nil, decided = decided,
        wordReading = function(w) return Resolve.wordReading(data, w) end,
    }
    return { chosen = chosen, decided = decided, matches = matches, drawn = drawn,
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
assert(p.text:find("东西  dōngxi · likely here · decides 东's reading\nthing; stuff", 1, true), p.text)
eq(words(p), "东,买东西,东西")
assert(p.text:find("dōngxī: east and west", 1, true), p.text)
-- 西 in 东西 is neutral: its own entry xī stands for it (one reading: no marker).
p = popup("去买东西。", "西")
eq(p.chosen, "xi"); eq(p.matches[1].entries[1].pinyin, "xī"); assert(not p.matches[1].entries[1].missing)

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
assert(p.text:find("宛如  wǎnrú · decides 宛's reading", 1, true), p.text)
eq(words(p), "宛,大宛,宛如", "both words listed, the decided one tagged")
-- 大宛 alone: yuān.
p = popup("西域有大宛国。", "宛", { threshold = 2500 })
eq(p.drawn, "yuān"); eq(p.decided.word, "大宛")
-- CC-CEDICT's 宛 has no yuān (it is only in 大宛): shown first, marked, empty.
assert(p.text:find("宛  yuān · shown above\nno separate CC-CEDICT entry for this reading\nwǎn: winding", 1, true), p.text)

-- The property itself, over the regression sentences: wherever the
-- annotation layer draws pinyin, the popup's reading is the same, in every
-- mode, without being told what was drawn.
local f = assert(io.open(PLUGIN_DIR .. "/../tests/eval_cases.tsv", "r"))
local checked = 0
for line in f:lines() do
    local sentence = line:match("^([^\t#]+)\t")
    if sentence then
        local items = H.items(sentence)
        for _, mode in ipairs({ "both", "best" }) do
            for _, threshold in ipairs({ 1500, 3500 }) do
                for _, a in ipairs(Resolve.annotate(data, items, threshold, mode, special)) do
                    local chosen = Resolve.forPopup(data, items, a.index, mode, special, nil)
                    eq(chosen, a.reading, sentence .. " " .. items[a.index].text .. " (" .. mode .. ")")
                    checked = checked + 1
                end
            end
        end
    end
end
f:close()
assert(checked > 100, "only " .. checked .. " annotations checked")
