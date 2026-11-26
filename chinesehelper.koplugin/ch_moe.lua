--[[--
The bundled MOE dictionaries (#86): 教育部《重編國語辭典修訂本》 and 《成語典》,
data/moe/moe.sqlite, built by tools/build_moe.py.

MOE's tables (`revised`, `idioms`) are the dictionaries exactly as MOE
publishes them (CC BY-ND 3.0 TW: no modified copy may be distributed). The
plugin finds a record through its own key tables (`revised_keys`,
`idioms_keys`) and turns MOE's fields into what the popup shows here, at
display time, never in the file:

  * 重編國語辭典: the 釋義 field's lines are the entry's senses, a part-of-speech
    line ([名]) joined to the sense after it. The reading is the 漢語拼音 field.
  * 成語典: an idiom's short line (用法說明's 語義說明 for a main entry, the
    entry's own explanation for a related one, followed by its main entry's
    語義說明 when the explanation only says which idiom it equals) and its
    Origin & Usage view (釋義, 典源 with its notes, 典故說明, 書證, usage,
    examples, 辨識, 近義/反義), MOE's editorial marks (*1*, #, ※, ◎, ＆, ＋)
    left out.

What is shown is MOE's text, only selected and laid out: never reworded or
converted to simplified characters. Characters MOE could not encode
(private-use characters, and image references written as &98ab._104_0.gif;)
are drawn as □ in a 重編國語辭典 sense; a line of the 成語典 holding one is left
out (as the 成語典 file built before 3.0.0 did).

A Moe object stands in for a fallback dictionary's database in main.lua:
fallback(words), fallbackAll(words), hasCovered(), idioms(words), meta().
Moe.open(path, "revised") gives the 重編國語辭典's, Moe.open(path, "idioms") the
成語典's (each with its own connection to the one file).
]]

local DB = require("ch_db")

local Moe = setmetatable({}, { __index = DB })
Moe.__index = Moe

Moe.BOX = "□"

function Moe.open(path, kind, SQ3)
    local db, err = DB.open(path, SQ3)
    if not db then return nil, err end
    db.kind = kind
    return setmetatable(db, Moe)
end

------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------

-- Private-use characters (U+E000-U+F8FF, planes 15 and 16) and MOE's image
-- references (&98ab._104_0.gif;).
local PUA = { "\238[\128-\191][\128-\191]", "\239[\128-\163][\128-\191]",
              "\243[\176-\191][\128-\191][\128-\191]", "\244[\128-\143][\128-\191][\128-\191]" }
local IMAGE = "&[%w%._]+;"

function Moe.boxed(s)
    for _, p in ipairs(PUA) do s = s:gsub(p, Moe.BOX) end
    return (s:gsub(IMAGE, Moe.BOX))
end

-- Would the device fonts draw a box: a private-use character, any character
-- outside the BMP, or an image reference.
function Moe.hasBox(s)
    if s:find("[\240-\244]") then return true end
    for _, p in ipairs(PUA) do if s:find(p) then return true end end
    return s:find(IMAGE) ~= nil
end

local SPACE_CHARS = { " ", "\t", "\227\128\128" }          -- space, tab, U+3000
-- Python's str.strip() whitespace that MOE's text has: also \n, \r, NBSP.
local ALL_SPACE = { " ", "\t", "\n", "\r", "\v", "\f", "\227\128\128", "\194\160" }

local function trimWith(s, set)
    local changed = true
    while changed and s ~= "" do
        changed = false
        for _, c in ipairs(set) do
            if s:sub(1, #c) == c then s = s:sub(#c + 1); changed = true end
            if s ~= "" and s:sub(-#c) == c then s = s:sub(1, -#c - 1); changed = true end
        end
    end
    return s
end
local function trim(s) return trimWith(s, SPACE_CHARS) end
local function strip(s) return trimWith(s, ALL_SPACE) end
local function lstrip(s)
    local changed = true
    while changed and s ~= "" do
        changed = false
        for _, c in ipairs(ALL_SPACE) do
            if s:sub(1, #c) == c then s = s:sub(#c + 1); changed = true end
        end
    end
    return s
end
local function noSpace(s)
    for _, c in ipairs(ALL_SPACE) do s = s:gsub(c, "") end
    return s
end
local function startsWith(s, p) return s:sub(1, #p) == p end
local function plainFind(s, p, init) return s:find(p, init or 1, true) end
local function replaceAll(s, from, to)
    local out, pos = {}, 1
    while true do
        local a, b = s:find(from, pos, true)
        if not a then break end
        out[#out + 1] = s:sub(pos, a - 1) .. to
        pos = b + 1
    end
    out[#out + 1] = s:sub(pos)
    return table.concat(out)
end
local function chars(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end
local function lines(s)
    local out = {}
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
    return out
end

-- A 重編國語辭典 record's senses from its 釋義 field: one per line, a
-- part-of-speech line ([名]) joined to the line after it, □ for a
-- character MOE could not encode, "/" as "／" (senses are joined with "/").
function Moe.revisedSenses(text)
    local out, pending = {}, nil
    for _, line in ipairs(lines((text or ""):gsub("\r", ""))) do
        line = strip(line)
        if line ~= "" then
            if line:match("^%[[^%]]+%]$") then
                pending = pending and (pending .. " " .. line) or line
            else
                if pending then line = pending .. " " .. line; pending = nil end
                out[#out + 1] = (Moe.boxed(line):gsub("/", "／"))
            end
        end
    end
    if pending then out[#out + 1] = pending end
    return out
end

-- The 成語典's editorial marks (※ before 語本, ＃ and ◎ before a passage or
-- as a separator line), never shown; ＆ and ＋ separate the parts of a field
-- (a part starts a new line).
local function editorial(s)
    s = s:gsub("◎%d*", "")
    for _, m in ipairs({ "#", "＃", "※" }) do s = replaceAll(s, m, "") end
    return s
end
local function separatorsTo(s, to)
    return replaceAll(replaceAll(s, "＆", to), "＋", to)
end
local function noteMarks(s) return (s:gsub("%*%d+%*", "")) end
local function noCR(s) return ((s or ""):gsub("\r", "")) end

-- Non-empty trimmed lines, marks out, a separator starting a new line.
function Moe.linesOf(text)
    local out = {}
    for _, x in ipairs(lines(separatorsTo(editorial(noCR(text)), "\n"))) do
        x = trim(x)
        if x ~= "" then out[#out + 1] = x end
    end
    return out
end

-- A field as one line: whitespace and separators out.
function Moe.oneLine(text)
    return separatorsTo(noSpace(noCR(text)), "")
end

local SHORT_MAX = 90       -- characters in the popup's short line, cut at a sentence end
local VIEW_LIST_MAX = 6    -- citations or example sentences in the Origin & Usage view
local SENTENCE_END = { ["。"] = true, ["；"] = true, ["！"] = true, ["？"] = true }

-- `text` cut after the last sentence end within SHORT_MAX characters (whole
-- when none ends there).
function Moe.shorten(text, limit)
    limit = limit or SHORT_MAX
    local cs = chars(text)
    if #cs <= limit then return text end
    local cut = 0
    for k = 1, limit do if SENTENCE_END[cs[k]] then cut = k end end
    if cut <= 1 then return text end
    return table.concat(cs, "", 1, cut)
end

-- The reading before any variant: "yī máo bù bá （變） yì máo bù bá" -> "yī máo bù bá".
function Moe.firstReading(pinyin)
    pinyin = pinyin or ""
    local cut
    for _, m in ipairs({ "（變）", "（又）", "（語）", "（讀）", "(變)" }) do
        local a = plainFind(pinyin, m)
        if a and (not cut or a < cut) then cut = a end
    end
    if cut then pinyin = pinyin:sub(1, cut - 1) end
    pinyin = replaceAll(pinyin, "　", " "):gsub("[ \t\n\r]+", " ")
    return strip(pinyin)
end

-- 典源文獻內容 as paragraphs: note markers out, the lines around annotated
-- words joined, a # paragraph (context around the passage) its own paragraph.
function Moe.sourceText(text)
    text = noteMarks(noCR(text))
    local paras, current = {}, {}
    local function flush()
        if #current > 0 then paras[#paras + 1] = table.concat(current); current = {} end
    end
    for _, piece in ipairs(lines(separatorsTo(text, "\n＋\n"))) do
        local l = lstrip(piece)
        if strip(piece) == "＋" then
            flush()
        elseif startsWith(l, "#") then
            flush(); paras[#paras + 1] = l:sub(2)
        elseif startsWith(l, "＃") or startsWith(l, "◎") then
            flush(); paras[#paras + 1] = l:sub(4)
        else
            current[#current + 1] = piece
        end
    end
    flush()
    local out = {}
    for _, p in ipairs(paras) do
        p = trim(editorial(p))
        if p ~= "" then out[#out + 1] = p end
    end
    return out
end

-- 典源文獻名稱 without its marks: several titles (each after ※) joined with "；".
function Moe.sourceTitle(text)
    text = replaceAll(noteMarks(noCR(text)), "※", "\n")
    local out = {}
    for _, t in ipairs(lines(text)) do
        t = trim(editorial(t))
        if t ~= "" then out[#out + 1] = t end
    end
    return table.concat(out, "；")
end

-- 見「X」條 in `text`: its start, or nil.
local function seeMain(text)
    local pos = 1
    while true do
        local a, b = plainFind(text, "見「", pos)
        if not a then return nil end
        local close = plainFind(text, "」", b + 1)
        if close and close > b + 1 and text:sub(close, close + #"」條" - 1) == "」條" then return a end
        pos = b + 1
    end
end

-- A 釋義 without its list of related idioms (after △), the pointer to its
-- main entry and the citations appended to it.
function Moe.ownExplanation(text)
    text = noCR(text)
    local tri = plainFind(text, "△")
    if tri then text = text:sub(1, tri - 1) end
    local see = seeMain(text)
    if see then text = text:sub(1, see - 1) end
    local pos = 1
    while true do
        local a = plainFind(text, "01.", pos)
        if not a then break end
        if a == 1 or not text:sub(a - 1, a - 1):match("%d") then text = text:sub(1, a - 1); break end
        pos = a + 1
    end
    return strip(editorial(noSpace(text)))
end

-- "此處所列為「X」之典源，提供參考。" (or 之典故說明): the length of that
-- prefix at the start of `text`, or nil.
local function storyPrefix(text)
    if not startsWith(text, "此處所列為「") then return nil end
    local close = plainFind(text, "」", #"此處所列為「" + 2)
    if not close then return nil end
    for _, tail in ipairs({ "」之典源，提供參考。", "」之典故說明，提供參考。" }) do
        if text:sub(close, close + #tail - 1) == tail then return close + #tail - 1 end
    end
    return nil
end

-- A note ending by pointing to another entry: 「…。見「摩頂放踵」。」 -> 「…。」
local function notePointer(line)
    local pos, last = 1, nil
    while true do
        local s = plainFind(line, "見「", pos)
        if not s then break end
        last = s; pos = s + 1
    end
    if not last then return line end
    local rest = line:sub(last + #"見「")
    local close = plainFind(rest, "」")
    if not close or close == 1 then return line end
    local after = rest:sub(close + #"」")
    if after == "" or after == "條" or after == "。" or after == "條。" then
        return line:sub(1, last - 1)
    end
    return line
end

local function noBoxes(list)
    local out = {}
    for _, x in ipairs(list) do if not Moe.hasBox(x) then out[#out + 1] = x end end
    return out
end
local function append(list, more)
    for _, x in ipairs(more) do list[#list + 1] = x end
    return list
end
local function firstN(list, n)
    local out = {}
    for k = 1, math.min(n, #list) do out[k] = list[k] end
    return out
end
local function numbered(list)
    local out = {}
    for _, x in ipairs(list) do out[#out + 1] = strip(replaceAll(x, "（源）", "")) end
    return out
end

-- The Origin & Usage view's text from (heading, lines) sections, empty ones left out.
function Moe.viewText(sections)
    local out = {}
    for _, s in ipairs(sections) do
        local kept = {}
        for _, x in ipairs(s[2]) do if x ~= "" then kept[#kept + 1] = x end end
        if #kept > 0 then
            out[#out + 1] = (s[1] ~= "" and (s[1] .. "\n") or "") .. table.concat(kept, "\n")
        end
    end
    return table.concat(out, "\n\n")
end

-- The source sections (典源, 注解, 典故說明) of a main entry's record r.
local function mainSections(r, suffix)
    suffix = suffix or ""
    local title = Moe.sourceTitle(r["典源文獻名稱"])
    if Moe.hasBox(title) then title = "" end
    local content = noCR(r["典源文獻內容"])
    local src = storyPrefix(content) and {} or Moe.sourceText(content)
    local story = noCR(r["典故說明"])
    local cut = storyPrefix(story)
    if cut then story = story:sub(cut + 1) end
    story = strip(story)
    local notes = {}
    for _, x in ipairs(Moe.linesOf(r["典源注解"])) do notes[#notes + 1] = notePointer(x) end
    return {
        { "典源" .. suffix .. (title ~= "" and ("　" .. title) or ""), noBoxes(src) },
        { "注解" .. suffix, noBoxes(notes) },
        { "典故说明" .. suffix, noBoxes(Moe.linesOf(story)) },
    }
end

--[[--
An idiom's popup text from its 成語典 record `r` (field name -> text) and,
for a related entry, its main entry's record `main` (nil otherwise).
equals: the related entry's explanation only says which idiom it equals
(idioms_keys.equals). Returns { short=, view=, pinyin= }.
]]
function Moe.idiomText(r, main, equals)
    local own = Moe.ownExplanation(r["釋義"])
    local short, sections
    if strip(r["主條成語／非主條成語"] or "") == "主條成語" then
        local sense = strip(noCR(r["用法說明-語義說明"]))
        short = Moe.oneLine(sense)
        if short == "" then short = own end
        sections = { { "释义", noBoxes({ own }) } }
        append(sections, mainSections(r))
        local near = {}
        for _, x in ipairs(Moe.linesOf(r["近義成語"])) do near[#near + 1] = "近义：" .. x end
        for _, x in ipairs(Moe.linesOf(r["反義成語"])) do near[#near + 1] = "反义：" .. x end
        append(sections, {
            { "书证", noBoxes(firstN(numbered(Moe.linesOf(r["書證"])), VIEW_LIST_MAX)) },
            { "用法", noBoxes(append(Moe.linesOf(sense), Moe.linesOf(r["用法說明-使用類別"]))) },
            { "例句", noBoxes(firstN(Moe.linesOf(r["用法說明-例句"]), VIEW_LIST_MAX)) },
            { "辨识", noBoxes(append(append(Moe.linesOf(r["辨識-形音辨誤"]), Moe.linesOf(r["辨識-同"])),
                                   Moe.linesOf(r["辨識-異"]))) },
            { "", near },
        })
    else
        short = own
        if main and equals then
            local main_sense = Moe.oneLine(main["用法說明-語義說明"])
            if main_sense ~= "" then short = own .. main_sense end
        end
        sections = { { "释义", noBoxes({ own }) },
                     { "书证", noBoxes(firstN(numbered(Moe.linesOf(r["書證"])), VIEW_LIST_MAX)) } }
        if main then append(sections, mainSections(main, "（" .. strip(main["成語"] or "") .. "）")) end
    end
    if Moe.hasBox(short) then short = "" end
    return { short = Moe.shorten(short), view = Moe.viewText(sections), pinyin = Moe.firstReading(r["漢語拼音"]) }
end

------------------------------------------------------------------------
-- Queries
------------------------------------------------------------------------

local function marks(n) return string.rep("?,", n - 1) .. "?" end
local function quote(name) return '"' .. name .. '"' end

-- The 成語典 fields Moe.idiomText reads: the record's, and its main entry's.
Moe.IDIOM_FIELDS = { "成語", "漢語拼音", "釋義", "典源文獻名稱", "典源文獻內容", "典源注解", "典故說明", "書證",
                     "用法說明-語義說明", "用法說明-使用類別", "用法說明-例句", "辨識-形音辨誤", "辨識-同",
                     "辨識-異", "近義成語", "反義成語", "主條成語／非主條成語" }
Moe.MAIN_FIELDS = { "成語", "典源文獻名稱", "典源文獻內容", "典源注解", "典故說明", "用法說明-語義說明" }

-- Kept identical to tools/build_moe.py's revised_sql and idioms_sql (which
-- check the query plans; tests/test_moe.lua compares them).
function Moe.revisedSql(n, uncovered)
    return "SELECT k.simp, k.trad, r." .. quote("漢語拼音") .. ", r." .. quote("釋義") .. ", k.covered"
        .. " FROM revised_keys k JOIN revised r ON r.rowid = k.id WHERE (k.simp IN (" .. marks(n)
        .. ") OR k.trad IN (" .. marks(n) .. "))" .. (uncovered and " AND k.covered = 0" or "")
        .. " ORDER BY k.rowid"
end

function Moe.idiomsSql(n, uncovered)
    local cols = { "k.simp", "k.trad", "k.covered", "k.equals" }
    for _, f in ipairs(Moe.IDIOM_FIELDS) do cols[#cols + 1] = "i." .. quote(f) end
    for _, f in ipairs(Moe.MAIN_FIELDS) do cols[#cols + 1] = "m." .. quote(f) end
    return "SELECT " .. table.concat(cols, ", ")
        .. " FROM idioms_keys k JOIN idioms i ON i.rowid = k.id LEFT JOIN idioms m ON m.rowid = k.main"
        .. " WHERE (k.simp IN (" .. marks(n) .. ") OR k.trad IN (" .. marks(n) .. "))"
        .. (uncovered and " AND k.covered = 0" or "") .. " ORDER BY k.rowid"
end

local function padded(list)
    local n, m = #list, DB.padded(#list)
    local args = {}
    for t = 0, 1 do
        for k = 1, m do args[t * m + k] = k <= n and list[k] or "" end
    end
    return args, m
end

function Moe:revisedRows(words, uncovered)
    if #words == 0 then return {} end
    local args, n = padded(words)
    local rows = {}
    local ok, err = pcall(self.each, self, Moe.revisedSql(n, uncovered), args, function(row)
        local senses = Moe.revisedSenses(row[4])
        if #senses > 0 then
            rows[#rows + 1] = { simp = row[1], trad = row[2], pinyin = strip(row[3] or ""), syllables = "",
                                defs = table.concat(senses, "/"), source = "moe", covered = tonumber(row[5]) == 1 }
        end
    end)
    if not ok then return {}, err end
    return rows
end

-- { {simp=, trad=, covered=, short=, view=, pinyin=}, ... } for `words`.
function Moe:idiomRows(words, uncovered)
    if #words == 0 then return {} end
    local args, n = padded(words)
    local rows = {}
    local nf = #Moe.IDIOM_FIELDS
    local ok, err = pcall(self.each, self, Moe.idiomsSql(n, uncovered), args, function(row)
        local r, main = {}, nil
        for k, f in ipairs(Moe.IDIOM_FIELDS) do r[f] = row[4 + k] end
        if row[4 + nf + 1] ~= nil then
            main = {}
            for k, f in ipairs(Moe.MAIN_FIELDS) do main[f] = row[4 + nf + k] end
        end
        local t = Moe.idiomText(r, main, tonumber(row[4]) == 1)
        rows[#rows + 1] = { simp = row[1], trad = row[2], covered = tonumber(row[3]) == 1,
                            short = t.short, view = t.view, pinyin = t.pinyin }
    end)
    if not ok then return {}, err end
    return rows
end

-- The fallback-dictionary interface (main.lua): rows
-- { {simp=, trad=, pinyin=, syllables=, defs=, source=}, ... }, never for a
-- word CC-CEDICT has.
function Moe:fallback(words)
    if self.kind == "idioms" then
        local out = {}
        for _, r in ipairs(self:idiomRows(words, true)) do
            if r.short ~= "" then
                out[#out + 1] = { simp = r.simp, trad = r.trad, pinyin = r.pinyin, syllables = "",
                                  defs = (r.short:gsub("/", "／")), source = "idioms" }
            end
        end
        return out
    end
    return self:revisedRows(words, true)
end

-- Every row for `words`, those for words CC-CEDICT has too (covered = true).
function Moe:fallbackAll(words)
    if self.kind == "idioms" then return {} end
    return self:revisedRows(words, false)
end

function Moe:hasCovered() return self.kind ~= "idioms" end

-- An idiom's short line and view (DB:idioms' rows), for every idiom among
-- `words` with either.
function Moe:idioms(words)
    if self.kind ~= "idioms" then return {} end
    local out = {}
    for _, r in ipairs(self:idiomRows(words, false)) do
        if r.short ~= "" or r.view ~= "" then
            out[#out + 1] = { simp = r.simp, trad = r.trad, short = r.short, view = r.view }
        end
    end
    return out
end

return Moe
