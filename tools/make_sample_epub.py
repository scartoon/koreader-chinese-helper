#!/usr/bin/env python3
"""Build the sample books, all public-domain texts, used for the README
screenshots (tools/make_screenshots.sh) and for trying the plugin.

    python3 tools/make_sample_epub.py

samples/xiaoshuo.epub (小说三篇), from Chinese Wikisource, converted to
simplified characters with tools/simplify.py (Simplifier("t2s")):

  三国演义 第一回   罗贯中, the 毛纶/毛宗岗 edition (it opens with 杨慎's
                   临江仙 "滚滚长江东逝水"; older editions lack it)
  孔乙己 (1919)     鲁迅, from 《呐喊》
  阿Q正传 (1921)    鲁迅, from 《呐喊》

Wikisource's 鲁迅 text is the 1938 《鲁迅全集》, typeset with old glyph
variants (偸, 淸, 靑, 尙, 鎗...) that OpenCC leaves alone; VARIANTS maps
them to the standard forms, as modern editions print them, and the corner
quotation marks become “” and ‘’. Words are not
modernised (豫备, 钞书 stay). The pages are fetched once into
build/sources/wikisource/ (REVISIONS pins the revision of each page; the
鲁迅 pages transclude scanned-page text, which is not pinned).

samples/guwen.epub (古文三篇): 桃花源记 (陶渊明), 陋室铭 (刘禹锡),
爱莲说 (周敦颐), typed in.

The style sheets deliberately set no line-height, like most books, so the
screenshots show the plugin's real effect on line spacing.
"""
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
CACHE = os.path.join(ROOT, "build", "sources", "wikisource")
API = "https://zh.wikisource.org/w/api.php"

# Wikisource page -> the revision used (2026-11-13).
REVISIONS = {
    "三國演義/第001回": 2583915,
    "孔乙己": 2605389,
    "阿Q正傳": 2633268,
}

# Old glyph variants in the 1938 鲁迅全集 (and 儅 in 三国演义) -> standard form;
# 𩓐子 is 脖子 (outside the BMP, drawn as a box by the device fonts).
VARIANTS = {
    "偸": "偷", "淸": "清", "靑": "青", "嬾": "懒", "煑": "煮", "儍": "傻", "汚": "污",
    "尙": "尚", "鎗": "枪", "揑": "捏", "礮": "炮", "朶": "朵", "盌": "碗", "鬭": "斗",
    "嘷": "嗥", "簷": "檐", "燄": "焰", "尅": "克", "呪": "咒", "寃": "冤", "鑪": "炉",
    "儅": "当", "𩓐": "脖",
}


def fetch(title):
    """The parsed HTML of a Wikisource page at its pinned revision (cached)."""
    rev = REVISIONS[title]
    path = os.path.join(CACHE, f"{rev}.json")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = API + "?" + urllib.parse.urlencode({
            "action": "parse", "oldid": rev, "prop": "text", "format": "json",
            "formatversion": 2, "disablelimitreport": 1})
        req = urllib.request.Request(url, headers={"User-Agent": "koreader-chinese-helper sample book builder"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        json.loads(data)["parse"]["text"]  # fail before caching an error page
        with open(path, "wb") as f:
            f.write(data)
    with open(path, encoding="utf-8") as f:
        return json.load(f)["parse"]["text"]


def text_of(fragment):
    t = html.unescape(re.sub(r"<[^>]+>", "", fragment))
    return t.replace("​", "").replace("\n", "").strip().strip("　").strip()


def blocks(page_html):
    """[(kind, text)] in reading order: kind "h" (a heading), "p" or "v"
    (a verse line), in the source's characters."""
    t = re.sub(r"<style.*?</style>", "", page_html, flags=re.S)
    start = t.find('class="prp-pages-output"')       # 鲁迅: the transcluded pages
    if start >= 0:
        t = t[start:]
    else:                                             # 三国演义: after the header tables
        t = t[t.rfind('class="ws-header"'):]
    t = re.sub(r"<table.*?</table>", "", t, flags=re.S)
    out = []
    # The innermost elements only: the verse is <dl><dd><dl><dd>line</dd>...
    for m in re.finditer(r"<(h2|p|dd)\b[^>]*>((?:(?!<(?:dd|dl|p|h2)\b).)*?)</\1>", t, re.S):
        kind, body = m.group(1), m.group(2)
        x = text_of(body)
        if not x or x.startswith(".mw-parser-output"):
            continue
        out.append(({"h2": "h", "p": "p", "dd": "v"}[kind], x))
    return out


def simplified(text, s, quotes):
    """Simplified characters, standard glyphs, and the quotation marks
    simplified-character books use: `quotes` maps the source's outer
    and inner corner brackets to “” and ‘’."""
    out = s.convert(text)
    return "".join(VARIANTS.get(c, quotes.get(c, c)) for c in out)


# 三国演义 quotes with 「」 (『』 inside); the 1938 鲁迅全集 with 『』 (「」 inside).
SANGUO_QUOTES = {"「": "“", "」": "”", "『": "‘", "』": "’"}
LUXUN_QUOTES = {"『": "“", "』": "”", "「": "‘", "」": "’"}


def xiaoshuo_texts():
    from simplify import Simplifier
    s = Simplifier("t2s")
    texts = []

    b = blocks(fetch("三國演義/第001回"))
    # The chapter ends with the closing couplet and "且听下文分解".
    texts.append(("第一回", "宴桃园豪杰三结义　斩黄巾英雄首立功", "罗贯中《三国演义》（毛宗岗本）",
                  [(k, simplified(x, s, SANGUO_QUOTES)) for k, x in b]))

    b = blocks(fetch("孔乙己"))
    end = next(i for i, (k, x) in enumerate(b) if x.startswith("（一九一九年"))
    texts.append(("孔乙己", None, "鲁迅", [(k, simplified(x, s, LUXUN_QUOTES)) for k, x in b[:end + 1]]))

    b = blocks(fetch("阿Q正傳"))
    end = next(i for i, (k, x) in enumerate(b) if x.startswith("（一九二一年"))
    texts.append(("阿Q正传", None, "鲁迅", [(k, simplified(x, s, LUXUN_QUOTES)) for k, x in b[:end + 1]]))
    for title, _, _, body in texts:
        bad = sorted({c for _, x in body for c in x if ord(c) > 0xFFFF})
        assert not bad, f"{title}: characters outside the BMP {bad}"
    return texts


GUWEN = [
    ("桃花源记", None, "陶渊明", [("p", p) for p in [
        "晋太元中，武陵人捕鱼为业。缘溪行，忘路之远近。忽逢桃花林，夹岸数百步，中无杂树，芳草鲜美，落英缤纷。渔人甚异之，复前行，欲穷其林。",
        "林尽水源，便得一山，山有小口，仿佛若有光。便舍船，从口入。初极狭，才通人。复行数十步，豁然开朗。土地平旷，屋舍俨然，有良田、美池、桑竹之属。阡陌交通，鸡犬相闻。其中往来种作，男女衣着，悉如外人。黄发垂髫，并怡然自乐。",
        "见渔人，乃大惊，问所从来。具答之。便要还家，设酒杀鸡作食。村中闻有此人，咸来问讯。自云先世避秦时乱，率妻子邑人来此绝境，不复出焉，遂与外人间隔。问今是何世，乃不知有汉，无论魏晋。此人一一为具言所闻，皆叹惋。余人各复延至其家，皆出酒食。停数日，辞去。此中人语云：“不足为外人道也。”",
        "既出，得其船，便扶向路，处处志之。及郡下，诣太守，说如此。太守即遣人随其往，寻向所志，遂迷，不复得路。",
        "南阳刘子骥，高尚士也，闻之，欣然规往。未果，寻病终。后遂无问津者。",
    ]]),
    ("陋室铭", None, "刘禹锡", [("p", p) for p in [
        "山不在高，有仙则名。水不在深，有龙则灵。斯是陋室，惟吾德馨。苔痕上阶绿，草色入帘青。谈笑有鸿儒，往来无白丁。可以调素琴，阅金经。无丝竹之乱耳，无案牍之劳形。南阳诸葛庐，西蜀子云亭。孔子云：何陋之有？",
    ]]),
    ("爱莲说", None, "周敦颐", [("p", p) for p in [
        "水陆草木之花，可爱者甚蕃。晋陶渊明独爱菊。自李唐来，世人甚爱牡丹。予独爱莲之出淤泥而不染，濯清涟而不妖，中通外直，不蔓不枝，香远益清，亭亭净植，可远观而不可亵玩焉。",
        "予谓菊，花之隐逸者也；牡丹，花之富贵者也；莲，花之君子者也。噫！菊之爱，陶后鲜有闻。莲之爱，同予者何人？牡丹之爱，宜乎众矣。",
    ]]),
]

CSS = """body { margin: 0 1em; }
h1 { font-size: 1.4em; text-align: center; margin: 1em 0 0.2em; }
p.author { text-align: center; margin: 0 0 1em; }
p { text-indent: 2em; margin: 0 0 0.5em; text-align: justify; }
"""
# For the novels: a subtitle line, chapter headings, verse lines.
CSS_XIAOSHUO = CSS + """p.subtitle { text-align: center; text-indent: 0; margin: 0 0 0.2em; }
h2 { font-size: 1.1em; text-align: center; margin: 1em 0 0.5em; }
p.verse { text-indent: 0; margin: 0 0 0.2em 4em; text-align: left; }
p.date { text-align: right; }
"""


def chapter(title, subtitle, author, body):
    lines = []
    for kind, x in body:
        x = html.escape(x, quote=False)
        if kind == "h":
            lines.append(f"<h2>{x}</h2>")
        elif kind == "v":
            lines.append(f'<p class="verse">{x}</p>')
        elif x.startswith("（一九"):
            lines.append(f'<p class="date">{x}</p>')
        else:
            lines.append(f"<p>{x}</p>")
    sub = f'<p class="subtitle">{subtitle}</p>\n' if subtitle else ""
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">
<head><meta charset="utf-8"/><title>{title}</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
<h1>{title}</h1>
{sub}<p class="author">{author}</p>
{chr(10).join(lines)}
</body>
</html>
"""


def write_epub(out, ident, book_title, creator, texts, css, extra_meta="", date=(2026, 11, 8)):
    files = {"OEBPS/style.css": css}
    manifest, spine, nav = [], [], []
    for i, (title, subtitle, author, body) in enumerate(texts, 1):
        name = f"ch{i}.xhtml"
        files["OEBPS/" + name] = chapter(title, subtitle, author, body)
        manifest.append(f'<item id="ch{i}" href="{name}" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="ch{i}"/>')
        nav.append(f'<li><a href="{name}">{title}</a></li>')

    files["OEBPS/nav.xhtml"] = f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">
<head><meta charset="utf-8"/><title>目录</title></head>
<body><nav epub:type="toc"><h1>目录</h1><ol>{"".join(nav)}</ol></nav></body>
</html>
"""
    files["OEBPS/content.opf"] = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" xml:lang="zh-CN">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">{ident}</dc:identifier>
<dc:title>{book_title}</dc:title>
<dc:language>zh-CN</dc:language>
<dc:creator>{creator}</dc:creator>
<dc:rights>Public domain</dc:rights>
{extra_meta}<meta property="dcterms:modified">{date[0]:04d}-{date[1]:02d}-{date[2]:02d}T00:00:00Z</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="css" href="style.css" media-type="text/css"/>
{chr(10).join(manifest)}
</manifest>
<spine>{"".join(spine)}</spine>
</package>
"""
    container = """<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""
    # Fixed timestamps so rebuilding gives an identical file.
    def info(name, compress):
        zi = zipfile.ZipInfo(name, date_time=date + (0, 0, 0))
        zi.compress_type = compress
        return zi

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(info("mimetype", zipfile.ZIP_STORED), "application/epub+zip")
        z.writestr(info("META-INF/container.xml", zipfile.ZIP_DEFLATED), container)
        for name in sorted(files):
            z.writestr(info(name, zipfile.ZIP_DEFLATED), files[name])
    print(out)


def main():
    write_epub(os.path.join(ROOT, "samples", "guwen.epub"), "koreader-interlinear-pinyin-sample-guwen",
               "古文三篇", "陶渊明 · 刘禹锡 · 周敦颐", GUWEN, CSS)
    sources = "".join(
        f'<dc:source>https://zh.wikisource.org/w/index.php?oldid={rev}</dc:source>\n'
        for rev in REVISIONS.values())
    write_epub(os.path.join(ROOT, "samples", "xiaoshuo.epub"), "koreader-chinese-helper-sample-xiaoshuo",
               "小说三篇", "罗贯中 · 鲁迅", xiaoshuo_texts(), CSS_XIAOSHUO, extra_meta=sources,
               date=(2026, 11, 13))


if __name__ == "__main__":
    main()
