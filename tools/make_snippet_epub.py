#!/usr/bin/env python3
"""Write a small EPUB for checking the popup's context line and the page
underline on a device: sentence ends with closing quotes, a long classical
sentence full of commas, mixed Latin and Chinese, hard line breaks and runs
of spaces inside a paragraph (in the source and as <br/>), a short sentence,
and a paragraph that runs over the page end.

    python3 tools/make_snippet_epub.py build/chinesehelper-snippet.epub
"""
import sys
import zipfile

sys.path.insert(0, __import__("os").path.dirname(__file__))
import make_test_epub as base  # noqa: E402

PARAS = [
    # Closers after sentence ends: 。」 and ？” stay with their sentence.
    "「你终于来了。」他放下书说。“真的是你吗？”她又问了一遍。",
    # A long classical sentence: commas are not boundaries.
    "臣本布衣，躬耕于南阳，苟全性命于乱世，不求闻达于诸侯。先帝不以臣卑鄙，猥自枉屈，"
    "三顾臣于草庐之中，咨臣以当世之事，由是感激，遂许先帝以驱驰。",
    # Mixed Latin and Chinese (and a Latin sentence end).
    "他昨天读了 The Economist 的一篇文章。Then he said: it is fine. 觉得 New York Times 也很靠谱。",
    # Hard line breaks and runs of spaces inside one paragraph.
    "这一段的源文件\n里有换行，\n    还有很多   空格，以及<br/>一个换行标签，English   words\nhere 也在里面。",
    # A sentence much shorter than the line.
    "好。",
    # Word buttons: 首鼠两端 and 拿不定主意 around 鼠 and 定.
    "他总是首鼠两端，拿不定主意。",
]
LATER = [
    f"<p>第{n}段：滚滚长江东逝水，浪花淘尽英雄，是非成败转头空，青山依旧在，几度夕阳红。"
    f"白发渔樵江渚上，惯看秋月春风，一壶浊酒喜相逢，古今多少事，都付笑谈中。</p>"
    for n in range(1, 30)
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "chinesehelper-snippet.epub"
    body = "\n".join([f"<p>{p}</p>" for p in PARAS] + LATER)
    xhtml = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head><title>Snippet</title></head>
<body><h2>上下文测试</h2>
{body}
</body></html>"""
    opf = base.OPF.replace("chinesehelper-test", "chinesehelper-snippet").replace(
        "Chinese helper test", "Chinese helper snippet test")
    ncx = base.NCX.replace("chinesehelper-test", "chinesehelper-snippet")
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", base.CONTAINER, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/toc.ncx", ncx, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/text.xhtml", xhtml, compress_type=zipfile.ZIP_DEFLATED)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
