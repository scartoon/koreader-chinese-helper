#!/usr/bin/env python3
"""Build the optional 成語典 file for your own device: 教育部《成語典》 (the
Taiwan Ministry of Education's Dictionary of Chinese Idioms), from the
ministry's own download page.

    python3 -m venv .venv && .venv/bin/pip install opencc && .venv/bin/python tools/build_idioms.py --push
    .venv/bin/python tools/build_idioms.py                 # -> build/chinesehelper-idioms.sqlite only
    .venv/bin/python tools/build_idioms.py --traditional   # text as the 成語典 writes it

The plugin database (for CC-CEDICT's headwords) is taken from the latest
release when chinesehelper.koplugin/data/ has none.

The current file is found on 教育部國語辭典公眾授權網's download page and
downloaded into build/sources/idioms/ when missing; --source takes a
dict_idioms_*.zip or .xlsx you downloaded yourself. The dictionary is
licensed CC BY-ND 3.0 TW (© 中華民國教育部), which allows copying it for your
own use but not distributing adaptations, so this file is never committed,
never part of a release, and never shared. The plugin works without it.

On the device it goes in KOReader's data folder, next to the MOE file:

    <KOReader data>/data/chinesehelper/chinesehelper-idioms.sqlite
    Android: /sdcard/koreader/data/chinesehelper/chinesehelper-idioms.sqlite

What the file holds (tools/chengyu.py): for each of the 成語典's 5,489
idioms, one short line of Chinese explanation (the 用法說明's 語義說明 for a
main entry; a related entry's own explanation, completed with its main
entry's when it only says which idiom it equals) and the 出处 view (釋義,
典源 with its notes, 典故說明, 書證, usage, examples, 辨識, 近義/反義). A
related entry's view also has its main entry's source text and story, headed
with the main entry's name. Idioms CC-CEDICT lacks also get a fallback
entry. Text is simplified (tools/simplify.py, tw2s); headwords are indexed
under both forms. Readings are the 成語典's (Taiwan standard) and never
decide the pinyin drawn above characters.
"""
import argparse
import os
import re
import sys
import zipfile
from collections import Counter
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chengyu  # noqa: E402
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/"
PAGE = BASE + "dict_idiomsdict_download.html"
# The file this script was written against (used when the page can't be read).
KNOWN = "download/dict_idioms_2020_20260929.zip"
SRC_DIR = os.path.join(ROOT, "build", "sources", "idioms")
DEFAULT_OUT = os.path.join(ROOT, "build", "chinesehelper-idioms.sqlite")
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
LICENSE = ("CC BY-ND 3.0 TW, 中華民國教育部《成語典》. For your own use: do not distribute this file.")


def current_url():
    """The text database's link on the download page (not the 字圖 images)."""
    import urllib.request
    try:
        req = urllib.request.Request(PAGE, headers={"User-Agent": "koreader-chinese-helper build script"})
        with urllib.request.urlopen(req, timeout=60) as r:
            page = r.read().decode("utf-8", "replace")
        links = re.findall(r'href="(download/dict_idioms_(?!pic)[^"]+\.zip)"', page)
        if links:
            return BASE + links[0]
        print(f"  (no dict_idioms zip linked on {PAGE}; using {KNOWN})")
    except Exception as e:  # noqa: BLE001
        print(f"  (could not read {PAGE}: {e}; using {KNOWN})")
    return BASE + KNOWN


def xlsx_of(path):
    """The .xlsx inside a downloaded zip (extracted next to it), or path."""
    if path.endswith(".xlsx"):
        return path
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if n.endswith(".xlsx") and "/" not in n.strip("/")]
        if not names:
            sys.exit(f"{path}: no .xlsx inside")
        out = os.path.join(os.path.dirname(os.path.abspath(path)), os.path.basename(names[0]))
        with z.open(names[0]) as src, open(out, "wb") as dst:
            dst.write(src.read())
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", help="a dict_idioms_*.zip or .xlsx (default: the newest download in "
                                     "build/sources/idioms/, else the current one from the ministry's page)")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (for CC-CEDICT's headwords); "
                                                  "taken from the latest release when missing")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--push", action="store_true", help=f"adb push the file to {fallback_sources.DEVICE_DIR}/")
    ap.add_argument("--traditional", action="store_true", help="keep the 成語典's traditional characters")
    args = ap.parse_args()
    fallback_sources.ensure_db(args.db)
    src = args.source
    if not src:
        have = sorted(f for f in os.listdir(SRC_DIR) if re.match(r"dict_idioms_\d+_\d+\.zip$", f)) \
            if os.path.isdir(SRC_DIR) else []
        if have:
            src = os.path.join(SRC_DIR, have[-1])
        else:
            url = current_url()
            src = fallback_sources.download_file(url, os.path.join(SRC_DIR, os.path.basename(url)))
    sha = fallback_sources.sha256_of(src)
    version = re.search(r"dict_idioms_(\d+_\d+)", os.path.basename(src))
    version = version.group(1) if version else "?"
    rows = chengyu.read_xlsx(xlsx_of(src))

    from simplify import Simplifier
    simplifier = Simplifier("tw2s")
    convert = (lambda s: s) if args.traditional else simplifier.convert
    stats = Counter()
    entries = []
    for e in chengyu.idioms_entries(rows, stats):
        sections = [(convert(h), [convert(x) for x in lines]) for h, lines in e["sections"]]
        # The Simplifier, not bare OpenCC, so that a character whose simplified
        # form the fonts lack stays traditional (炊瓊爇桂, not 𦶟).
        entries.append({"simp": simplifier.convert(e["trad"]), "trad": e["trad"], "pinyin": e["pinyin"],
                        "short": convert(e["short"]), "view": chengyu.view_text(sections)})
    cedict, _measure = fallback_sources.cedict_forms(args.db)
    fallback, idioms = chengyu.tables(entries, "idioms", cedict, stats)
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")
    meta = {"fallback_sources": "idioms", "idioms_rows": str(len(set(idioms))),
            "idioms_fallback_rows": str(len(set(fallback))), "idioms_version": version,
            "idioms_file": os.path.basename(src), "idioms_sha256": sha, "idioms_url": PAGE,
            "idioms_built": date.today().isoformat(), "idioms_license": LICENSE,
            "idioms_text": "traditional" if args.traditional else "simplified"}
    fallback_sources.write_local_file(args.out, fallback, meta, "成語典",
                                      extra=lambda con: chengyu.write_idioms(con, idioms))
    print(f"成語典 {version}: {meta['idioms_rows']} idioms, {meta['idioms_fallback_rows']} not in CC-CEDICT; "
          f"source SHA-256 {sha}")
    print(f"Wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB). {LICENSE}")
    fallback_sources.push_or_explain(args.out, args.push)


if __name__ == "__main__":
    main()
