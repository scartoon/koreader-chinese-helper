-- The popup's context line (ch_snippet.lua): what is picked around the
-- tapped character, with a fake width measure (full-width characters 2
-- units, everything else 1; bold no wider).
local Text = require("ch_text")
local Snippet = require("ch_snippet")
local Fake = require("fake_credoc")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function measure(s)
    local w = 0
    for _, c in ipairs(Text.chars(s)) do w = w + (#c > 1 and 2 or 1) end
    return w
end

-- `text`: paragraphs separated by a blank line, the tapped character in
-- [brackets]. Returns the line as before [mark] after, and the selection.
local function line(text, width, word)
    local a = text:find("[", 1, true)
    local b = text:find("]", a, true)
    local plain = text:sub(1, a - 1) .. text:sub(a + 1, b - 1) .. text:sub(b + 1)
    local index = #Snippet.chars(text:sub(1, a - 1) .. text:sub(a + 1, b - 1), "\n\n")
    local chars = Snippet.chars(plain, "\n\n")
    local sel = Snippet.select{ chars = chars, index = index, word = word, measure = measure, width = width or 1000 }
    assert(sel, "no selection for " .. text)
    local total = measure(sel.before) + measure(sel.mark) + measure(sel.after)
    assert(total <= (width or 1000), "too wide: " .. total .. " > " .. tostring(width))
    return sel.before .. "[" .. sel.mark .. "]" .. sel.after, sel
end

-- Mid-sentence: the whole sentence, nothing from its neighbours.
eq(line("第一句。他放[下]书说话。第三句。"), "他放[下]书说话。", "mid-sentence")
-- Cut for width: centred, with … on both sides.
local s, sel = line("前句。他放下书以后慢慢地站[起]来走到窗前看了很久。后句。", 22)
eq(s, "…慢慢地站[起]来走到窗…", "cut both sides")
assert(sel.cut_left and sel.cut_right)
-- First and last in the sentence.
eq(line("前句。[他]放下书说话。后句。"), "[他]放下书说话。", "first in sentence")
eq(line("前句。他放下书说[话]。后句。"), "他放下书说[话]。", "last in sentence")
-- The tapped character is the first or last on the page: the page edge is a
-- boundary (no …).
eq(line("[他]放下书。"), "[他]放下书。", "first on page")
eq(line("他放下[书]"), "他放下[书]", "last on page, no sentence end")
eq(line("他放下书说话然后走[了]"), "他放下书说话然后走[了]", "last on page")
-- Paragraph start, and a paragraph with no sentence end.
eq(line("上一段结尾。\n\n[本]段开头，继续。"), "[本]段开头，继续。", "paragraph start")
eq(line("上一段没有句号\n\n本[段]开头"), "本[段]开头", "paragraph without end marks")
eq(line("这一段到此为[止]\n\n下一段"), "这一段到此为[止]", "paragraph end")
-- Closing quotes and brackets stay with the sentence they close.
eq(line("「你终于来了。」他放下[书]说。"), "他放下[书]说。", "after 。」")
eq(line("「你终于来[了]。」他放下书说。"), "「你终于来[了]。」", "before 。」")
eq(line("“真的是你[吗]？”她又问了一遍。"), "“真的是你[吗]？”", "？”")
eq(line("“真的？”[她]又问了一遍。"), "[她]又问了一遍。", "after ？”")
eq(line("他说：“好！”『[走]吧。』"), "『[走]吧。』", "！” then 『")
-- A sentence much shorter than the line.
eq(line("前面很长的一句话。[好]。后面也有很长的一句话。"), "[好]。", "short sentence")
-- A long classical sentence: commas are not boundaries; the cut is for width.
local classical = "臣本布衣，躬耕于南阳，苟全性命于乱世，不求闻达于诸侯。"
eq(line((classical:gsub("性", "[性]")), 30), "…于南阳，苟全[性]命于乱世，不…", "classical, cut for width")
eq(line((classical:gsub("性", "[性]"))), (classical:gsub("性", "[性]")), "classical, whole sentence")
-- One side at a boundary early: its leftover width goes to the other side.
eq(line("前句。[他]放下书说话然后走了很远很远。", 14), "[他]放下书说话…", "all room to the right")
eq(line("他放下书说话然后走了很远很[远]。后句。", 14), "…了很远很[远]。", "all room to the left")
-- Mixed Latin and Chinese; a Latin sentence end is a boundary.
eq(line("他昨天读了 The Economist 的一篇[文]章。"), "他昨天读了 The Economist 的一篇[文]章。", "mixed")
eq(line("Then he said: it is fine. 觉得[很]好。"), "觉得[很]好。", "after a Latin sentence end")
eq(line("他读了 The Economist 的一篇很长很长的[文]章。", 24), "…的一篇很长很长的[文]章。", "cut before Latin")
s = line("他读了 The Economist 的[一]篇。", 20)
eq(s, "…Economist 的[一]篇。", "cut inside Latin: whole words only, no space after …")
-- Whitespace and hard line breaks inside a paragraph: nothing between
-- full-width characters, one space elsewhere.
eq(line("这一段的源文件\n里有换行，\n    还有很多   [空]格，English   words\nhere 也在。"),
    "这一段的源文件里有换行，还有很多[空]格，English words here 也在。", "whitespace")
eq(line("　　[开]头有全角空格。"), "[开]头有全角空格。", "leading full-width spaces")
-- Word buttons: the word is marked when it is at the tapped position.
eq(line("他总是首[鼠]两端，拿不定主意。", nil, { text = "首鼠两端", start = -1 }),
    "他总是[首鼠两端]，拿不定主意。", "word at the tapped position")
eq(line("他总是首[鼠]两端，拿不定主意。", nil, { text = "鼠两端", start = 0 }),
    "他总是首[鼠两端]，拿不定主意。", "word starting at the tapped character")
eq(line("他总是首[鼠]两端，拿不定主意。", nil, { text = "首鼠两端", start = 0 }),
    "他总是首[鼠]两端，拿不定主意。", "word not at the tapped position: the character")
eq(line("他总是首[鼠]两端，拿不定主意。", nil, { text = "首鼠兩端", start = -1 }),
    "他总是首[鼠]两端，拿不定主意。", "word in other characters: the character")
eq(line("前句。他总是首[鼠]两端拿不定主意的样子。", 16, { text = "首鼠两端", start = -1 }),
    "…是[首鼠两端]拿…", "word, cut for width")

-- Never wider than the line, at any width, and the mark is always there.
local long = "前句。臣本布衣，躬耕于南阳，苟全 English words 性命于乱世，不求闻达于诸侯。后句。"
for width = 2, 80 do
    local s2 = line((long:gsub("南", "[南]")), width)
    assert(s2:find("[南]", 1, true), s2)
end

-- Breaks: crengine's "\n" is a paragraph break; a <br/> crossing is told
-- apart from a block crossing.
local cs = Snippet.chars("一\n二", "\n")
eq(cs[2], Snippet.BREAK, "crengine newline")
eq(#Snippet.chars("一\n\n\n二", "\n\n"), 3, "blank lines: one break")
eq(Snippet.crossing("/body/p[4]/text()[1].23", "/body/p[4]/text()[2].0", "<p>及<br/></p>"), "br")
eq(Snippet.crossing("/body/p[3]/text().74", "/body/p[4]/text()[1].0", "<body><p>。</p><p></p></body>"), "block")
eq(Snippet.crossing("/body/p[4]/b/text().0", "/body/p[4]/text()[2].0", "<p><b>中</b>国</p>"), nil, "inline")
eq(Snippet.crossing("/body/p[4]/b/text().0", "/body/p[4]/i/text().0", "<p><b>中</b><i>国</i></p>"), nil)
eq(Snippet.crossing("/body/div/p[1]/text().9", "/body/div/p[2]/text().0", ""), "block")

-- The page text from a (fake) document: the tapped character's index.
local paras = { "上一段。", "他放下书说话。后句。", "最后一段" }
local doc = Fake.fakeDoc(paras, 20)
local hit = doc:hit(2, 4)   -- 书
local chars, index = Snippet.pageText(doc, hit, { start = "1/0", stop = "3/2" })
assert(chars, "page text")
eq(chars[index], "书", "tapped index")
eq(table.concat(chars):gsub(Snippet.BREAK, "|"), "上一段。|他放下书说话。后句。|最后", "page text")
local sel2 = Snippet.select{ chars = chars, index = index, measure = measure, width = 100 }
eq(sel2.before .. "[" .. sel2.mark .. "]" .. sel2.after, "他放下[书]说话。", "from the document")
-- To the end of the document (no next page).
chars, index = Snippet.pageText(doc, doc:hit(3, 2), { start = "2/0" })
eq(chars[index], "后", "last page")
eq(chars[#chars], "段", "walked to the end")

print("snippet: ok")
