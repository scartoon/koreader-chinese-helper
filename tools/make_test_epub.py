#!/usr/bin/env python3
"""Write a small EPUB for testing on a device: mixed Chinese/English text,
traditional characters, digits, punctuation, words split by inline tags, the
resolver-and-popup cases (的确 / 的, 东西, 行, 一 and 不), rare characters
that get pinyin, and after page 1 headings with rare characters, 〇 in a date
and text to scroll through.

    python3 tools/make_test_epub.py build/chinesehelper-test.epub
"""
import sys
import zipfile

PARAS = [
    # Latin and digits between Chinese: taps on them must turn the page.
    "他昨天读了 The Economist 的一篇文章，觉得很靠谱。",
    # Traditional characters: matched through CC-CEDICT's traditional column.
    "這個歷史挺靠譜，國家圖書館裡有很多。",
    "Numbers like 2026 年 and 中华人民共和国成立的时候。",
    # Inline tags inside words: the context walk must cross them.
    "这是<b>中</b>国的<i>历</i>史，也是<span>世界</span>的历史。",
    # Paragraph boundary with Han characters on both sides.
    "第一段结尾是汉字",
    "第二段开头也是汉字",
    # The reading the popup marks: 的 in 的确 / alone, 东西, 行, 一 and 不.
    "他的确来了。我的书在桌上。",
    "去商店买东西。东西两边都是山。",
    "他在银行工作。路上的行人很多。这样也行。",
    "他一定来。这不是书。",
    # Rare characters (pinyin above them at the default threshold), and a
    # special word.
    "两军对峙，饕餮之徒侥幸逃脱。匈奴单于入塞。",
    # Fallback dictionaries: 帐 (CC-CEDICT), 甲帐 (MOE), 帐下吏 (Wiktionary); 尚书省 (Wiktionary).
    "汉武帝的甲帐下吏都是名将。唐代尚书省下设六部。",
    # A Wiktionary word picks one of an uncertain pair: 累 is lěi in 累世 (popup:
    # "likely here", 累世 decides). Nothing decides 累 in 他累: "one of these".
    "后来发展成门第望族累世公卿。他累，就睡了。",
    "A paragraph in English only, to tap on Latin text: the quick brown fox jumps over the lazy dog.",
]

# After page 1 (whose positions earlier device notes rely on): a heading with
# rare characters (line spacing in h1-h6), 〇 in a date, and enough text with
# rare characters spread through it to check continuous (scroll) view.
LATER = (
    ["<h1>饕餮与魑魅</h1>", "<p>二〇二六年十一月，他读完了这本书。</p>", "<h3>魍魉之章</h3>"]
    + [f"<p>第{n}段：两军对峙，饕餮之徒侥幸逃脱，魑魅魍魉皆遁形。这里还有一些普通的句子，"
       f"用来把页面填满，好让连续滚动时屏幕下半部分也有生僻字。</p>" for n in range(1, 41)]
)

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

OPF = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Chinese helper test</dc:title><dc:language>zh</dc:language>
    <dc:identifier id="id">chinesehelper-test</dc:identifier>
  </metadata>
  <manifest>
    <item id="text" href="text.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="text"/></spine>
</package>"""

NCX = """<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="chinesehelper-test"/></head>
  <docTitle><text>Chinese popup test</text></docTitle>
  <navMap><navPoint id="p1" playOrder="1"><navLabel><text>Test</text></navLabel>
  <content src="text.xhtml"/></navPoint></navMap>
</ncx>"""


def xhtml():
    body = "\n".join([f"<p>{p}</p>" for p in PARAS] + LATER)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head><title>Test</title></head>
<body><h2>测试页</h2>
{body}
</body></html>"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "chinesehelper-test.epub"
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", OPF, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/toc.ncx", NCX, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/text.xhtml", xhtml(), compress_type=zipfile.ZIP_DEFLATED)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
