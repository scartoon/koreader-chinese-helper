"""Read the Moegirlpedia (萌娘百科) offline snapshot, zhmoegirl-20230507-alpha.slob,
for measuring it as a fallback dictionary (tools/measure_book.py). Nothing here
is used by the plugin.

    pip install git+https://github.com/itkach/slob.git     # needs ICU (brew install icu4c pkg-config)

The snapshot: https://github.com/aisuneko/dicts_for_aard2/releases/tag/moegirl-alpha
(listed on github.com/itkach/slob/wiki "Other projects"), 1,382,718,297 bytes,
SHA-256 75e246cf8e601e389ff72edfe0ced2ded5095347f103316b282883c707af36f8.
Licence: CC BY-NC-SA 3.0 CN (the slob's own license.name tag).

What an article looks like in it (rendered MediaWiki HTML, one blob per page):
  * <span id="a2-title">: the page's own title. A key whose title differs is a
    redirect (河蟹 -> 河蟹娘), and redirects can change the sense.
  * <div class="mw-parser-output">: the article. Before the text: hatnotes
    (div.notice), infoboxes (div.infoBox, table.moe-infobox), the TOC.
  * 黑幕 (hidden joke text): <span class="heimu">...</span>; strikethrough
    asides: <s>...</s> (also <del>). Both are dropped from the gloss.
  * No category links survive (no div.catlinks); navboxes link to category
    pages, which says nothing about the article itself.

parse() gives the opening: the first paragraph with real text once 黑幕,
strikethrough, references, tables, infoboxes, hatnotes and the TOC are
dropped, and its first sentence (the gloss).
"""
import re
from html.parser import HTMLParser

HAN = "㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f"
HAN_RE = re.compile(f"[{HAN}]")

# Elements whose whole content is left out of the text.
SKIP_TAGS = {"s", "del", "strike", "table", "style", "script", "sup", "figure", "details", "math", "ol", "ul",
             "noscript", "rt", "rp"}
SKIP_CLASSES = re.compile(r"\b(heimu|infoBox|moe-infobox|infobox|notice|dablink|toc|mw-editsection|navbox|"
                          r"mw-references-wrap|references|thumb|gallery|mobileonly|reference|hatnote|"
                          r"tabber|mw-collapsible)\b")
VOID = {"br", "img", "hr", "input", "link", "meta", "wbr", "source", "area", "col", "embed", "param", "track"}


class _Opening(HTMLParser):
    """Paragraph texts of mw-parser-output, minus the skipped elements;
    counts 黑幕 and strikethrough spans, headings and TOC entries."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = None
        self._in_title = False
        self.stack = []          # (tag, skipping) for open elements
        self.skip = 0            # depth inside skipped elements
        self.in_output = False
        self.paras = []          # texts of <p> (and <dd>) blocks, in order
        self._cur = None
        self.heimu = 0
        self.strike = 0
        self.toc_entries = 0
        self.headlines = 0
        self.headings = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class") or ""
        if a.get("id") == "a2-title":
            self._in_title = True
            self.title = ""
        if "mw-parser-output" in cls:
            self.in_output = True
        if "heimu" in cls.split():
            self.heimu += 1
        if tag in ("s", "del", "strike"):
            self.strike += 1
        if "toctext" in cls:
            self.toc_entries += 1
        if "mw-headline" in cls:
            self.headlines += 1
            self.headings.append(a.get("id") or "")
        if tag in VOID:
            return
        skipping = tag in SKIP_TAGS or bool(SKIP_CLASSES.search(cls))
        self.stack.append((tag, skipping))
        if skipping:
            self.skip += 1
        if tag in ("p", "dd") and self.in_output and self.skip == 0:
            self._cur = []

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        # Pop to the matching open tag (the HTML is well formed in practice).
        for k in range(len(self.stack) - 1, -1, -1):
            if self.stack[k][0] == tag:
                for t, skipping in self.stack[k:]:
                    if skipping:
                        self.skip -= 1
                del self.stack[k:]
                break
        if tag == "span" and self._in_title:
            self._in_title = False
        if tag in ("p", "dd") and self._cur is not None and self.skip == 0:
            text = re.sub(r"\s+", " ", "".join(self._cur)).strip()
            if text:
                self.paras.append(text)
            self._cur = None

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if self._cur is not None and self.skip == 0:
            self._cur.append(data)


SENTENCE_END = re.compile(r"(?<=[。！？])")


def first_sentence(text, limit=160):
    """The first sentence of `text` (to the first 。！？), at most `limit`
    characters, cut at a clause mark when longer."""
    s = SENTENCE_END.split(text, 1)[0].strip()
    if len(s) > limit:
        cut = max(s.rfind(m, 0, limit) for m in "，；：")
        s = s[:cut] + "…" if cut > limit // 3 else s[:limit] + "…"
    return s


def parse(html_text):
    """{title, opening, gloss, heimu, strike, toc, headlines, paras, length}."""
    p = _Opening()
    p.feed(html_text)
    p.close()
    opening = next((t for t in p.paras if len(HAN_RE.findall(t)) >= 6), "")
    return {"title": (p.title or "").strip(), "opening": opening, "gloss": first_sentence(opening),
            "heimu": p.heimu, "strike": p.strike, "toc": p.toc_entries, "headlines": p.headlines,
            "paras": len(p.paras), "length": len(html_text)}


# What kind of page an opening describes. Moegirlpedia is mostly characters,
# works and people; the dictionary-like pages are terms (用语, 梗, 流行语).
KIND_RULES = [
    ("term", re.compile(r"网络用语|網路用語|网络流行语|網路流行語|流行语|流行語|网络热词|网络词|热词|梗|口头禅|口頭禪|"
                        r"俚语|俚語|黑话|黑話|用语|用語|术语|術語|俗语|俗語|词语|詞語|词汇|詞彙|成语|成語|"
                        r"戏称|戲稱|蔑称|蔑稱|贬称|貶稱|昵称|暱稱|爱称|愛稱|称呼|稱呼|简称|簡稱|缩写|縮寫|"
                        r"谐音|諧音|表情|颜文字|顏文字|萌属性|萌屬性|属性|屬性|一词|一詞|词语|意为|意為|指的是|"
                        r"是指|泛指|形容|比喻|表示")),
    ("character", re.compile(r"登场|登場|角色|声优|聲優|配音|主人公|主角|女主|男主|CV")),
    ("work", re.compile(r"小说|小說|漫画|漫畫|动画|動畫|游戏|遊戲|电影|電影|歌曲|专辑|專輯|作品|电视剧|電視劇|轻小说|"
                        r"番剧|番劇|单曲|單曲|节目|節目")),
    ("person", re.compile(r"UP主|up主|主播|歌手|演员|演員|画师|畫師|作家|作者|出生|偶像|艺人|藝人|运动员|政治家|"
                          r"漫画家|声优|聲優|社团|社團|组合|組合|公司|团体|團體")),
]


# Slang proper: the opening calls the word internet / forum / danmaku usage.
SLANG = re.compile(r"网络用语|網路用語|网络流行语|網路流行語|流行语|流行語|网络热词|热词|網路|网络|梗|网文|網文|"
                   r"弹幕|彈幕|论坛|論壇|贴吧|貼吧|吐槽|恶搞|惡搞|饭圈|飯圈|二次元|口头禅|口頭禪")
DISAMBIGUATION = re.compile(r"(可以|可能|也可|或可)?是?指[：:]\s*$|可以指|可指[：:]|消歧义|消歧義")
MOE_ATTRIBUTE = re.compile(r"萌属性|萌屬性|人物属性|人物屬性|角色属性")


def is_slang(gloss):
    """A term page about internet slang: the first sentence names it as such,
    and it is neither a disambiguation page nor an ACG character attribute
    (工人, 学生 as 萌属性: ordinary words in an ACG sense)."""
    return bool(gloss) and not DISAMBIGUATION.search(gloss) and not MOE_ATTRIBUTE.search(gloss) \
        and bool(SLANG.search(gloss))


def kind(opening):
    """term / character / work / person / other, from the opening sentence:
    the first rule whose pattern appears in it (terms first: a term's opening
    often names the work it comes from)."""
    s = first_sentence(opening, 400)
    for name, rx in KIND_RULES:
        if rx.search(s):
            return name
    return "other"


def entries(path, keys=None):
    """(key, blob key, html) for every text/html entry of the slob, or for
    the given keys only (each key looked up; missing keys skipped)."""
    import slob
    with slob.open(path) as s:
        if keys is None:
            for b in s:
                if b.content_type.startswith("text/html"):
                    yield b.key, b.key, b.content.decode("utf-8", "replace")
        else:
            d = s.as_dict()
            for k in keys:
                for b in d[k]:
                    if b.content_type.startswith("text/html") and b.key == k:
                        yield k, b.key, b.content.decode("utf-8", "replace")
                        break


def tags(path):
    import slob
    with slob.open(path) as s:
        return dict(s.tags), len(s), s.blob_count
