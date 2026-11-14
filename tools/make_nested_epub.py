#!/usr/bin/env python3
"""Write a small EPUB for checking popups opened from popups on a device:
an idiom with a 出处 view (首鼠两端), words only MOE has, with long dense
definitions full of quotations (三楚, 乔梓), characters with component
breakdowns (观, 茴), and 打 (CC-CEDICT's longest kind of entry).

    python3 tools/make_nested_epub.py build/chinesehelper-nested.epub
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


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "chinesehelper-nested.epub"
    body = "\n".join(f"<p>{p}</p>" for p in PARAS)
    xhtml = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head><title>Nested</title></head>
<body><h2>弹窗查字测试</h2>
{body}
</body></html>"""
    opf = base.OPF.replace("chinesehelper-test", "chinesehelper-nested").replace(
        "Chinese helper test", "Chinese helper nested popup test")
    ncx = base.NCX.replace("chinesehelper-test", "chinesehelper-nested")
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", base.CONTAINER, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/toc.ncx", ncx, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/text.xhtml", xhtml, compress_type=zipfile.ZIP_DEFLATED)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
