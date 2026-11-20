#!/usr/bin/env python3
"""Write a small EPUB for checking popups opened from popups on a device:
an idiom with a 出处 view (首鼠两端), words only MOE has, with long dense
definitions full of quotations (三楚, 乔梓), characters with component
breakdowns (观, 茴), and 打 (CC-CEDICT's longest kind of entry).

    python3 tools/make_nested_epub.py build/chinesehelper-nested.epub
    python3 tools/make_nested_epub.py --traditional build/chinesehelper-nested-trad.epub

--traditional writes a page in traditional characters instead, for the
simplified forms on traditional taps' head lines (#50): 頭/頭髮, 發現, 乾淨
and 乾隆, 著名 and 睡著, 東西, 人民.
"""
import sys
import zipfile

sys.path.insert(0, __import__("os").path.dirname(__file__))
import make_test_epub as base  # noqa: E402

PARAS = [
    "他总是首鼠两端，拿不定主意。",
    "战国三楚之地，乔梓相依。",
    "观察茴香豆。",
    "他打了一下。",
]
TRAD_PARAS = [
    "他頭髮花白，鬢角也白了。",
    "我發現了一個問題。",
    "房間很乾淨。乾隆皇帝下江南。",
    "這位著名的作家睡著了。",
    "去市場買東西。人民的生活。",
    "他總是首鼠兩端，拿不定主意。",
]


def main():
    args = sys.argv[1:]
    trad = "--traditional" in args
    args = [a for a in args if a != "--traditional"]
    name = "chinesehelper-nested-trad" if trad else "chinesehelper-nested"
    out = args[0] if args else name + ".epub"
    body = "\n".join(f"<p>{p}</p>" for p in (TRAD_PARAS if trad else PARAS))
    xhtml = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="{'zh-TW' if trad else 'zh'}"><head><title>Nested</title></head>
<body><h2>{'彈窗查字測試' if trad else '弹窗查字测试'}</h2>
{body}
</body></html>"""
    title = "Chinese helper traditional popup test" if trad else "Chinese helper nested popup test"
    opf = base.OPF.replace("chinesehelper-test", name).replace("Chinese helper test", title)
    ncx = base.NCX.replace("chinesehelper-test", name)
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", base.CONTAINER, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/toc.ncx", ncx, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/text.xhtml", xhtml, compress_type=zipfile.ZIP_DEFLATED)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
