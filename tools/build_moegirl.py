#!/usr/bin/env python3
"""Build the optional Moegirlpedia slang dictionary for your own device:
internet-slang pages of 萌娘百科 (https://zh.moegirl.org.cn), the opening
sentence or two of each, in Chinese.

    pip install opencc pypinyin git+https://github.com/itkach/slob.git
        (slob needs ICU: brew install icu4c pkg-config, then
         PKG_CONFIG_PATH=$(brew --prefix icu4c)/lib/pkgconfig pip install ...)
    .venv/bin/python tools/build_moegirl.py           # -> build/chinesehelper-moegirl.sqlite
    .venv/bin/python tools/build_moegirl.py --push    # ... and adb push it to the device

The source is an offline snapshot of the wiki made by a third party,
zhmoegirl-20230507-alpha.slob (1.4 GB), listed on the slob project's
dictionary page and downloaded into build/sources/moegirl/ when missing.
Reading every page takes about 10-15 minutes. Moegirlpedia's text is
licensed CC BY-NC-SA 3.0 CN, which rules out the plugin's CC BY-SA release,
so this file is never committed, never part of a release, and never shared:
you build it yourself, for your own device. The plugin works without it.

On the device it goes in KOReader's data folder, next to the MOE file:

    <KOReader data>/data/chinesehelper/chinesehelper-moegirl.sqlite
    Android: /sdcard/koreader/data/chinesehelper/chinesehelper-moegirl.sqlite

What the file holds: one `fallback` table, the same as the release
database's (see tools/fallback_sources.py, moegirl_rows), with source
"moegirl", and a `meta` table.
  * Only pages about internet slang: the page's own title (no redirects),
    2-8 Han characters, whose opening sentence describes a term and names
    internet, forum or danmaku usage, less a hand-checked exclusion list
    (fallback_sources.MOEGIRL_EXCLUDE).
  * The gloss: the opening sentence (and the next one when the first is
    short), with 黑幕 (hidden spoiler text) and struck-through text removed,
    and characters KOReader's fonts may not draw taken out.
  * Moegirlpedia gives no readings: the pinyin is generated with pypinyin,
    and the popup marks it "generated pinyin". It is never used for the
    pinyin drawn above characters.
  * Left out: titles CC-CEDICT has (read from the plugin database, so build
    that first), everyday combinations.
"""
import argparse
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://github.com/aisuneko/dicts_for_aard2/releases/download/moegirl-alpha/zhmoegirl-20230507-alpha.slob"
# The snapshot this script was written against (SHA-256 also listed on the slob wiki).
SHA256 = "75e246cf8e601e389ff72edfe0ced2ded5095347f103316b282883c707af36f8"
DEFAULT_SRC = os.path.join(ROOT, "build", "sources", "moegirl", "zhmoegirl-20230507-alpha.slob")
DEFAULT_OUT = os.path.join(ROOT, "build", "chinesehelper-moegirl.sqlite")
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
LICENSE = ("萌娘百科 (Moegirlpedia) contributors, CC BY-NC-SA 3.0 CN, via the zhmoegirl-20230507-alpha.slob "
           "snapshot. For your own use: do not distribute this file.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SRC, help="the Moegirlpedia .slob file; downloaded when missing")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (for CC-CEDICT's headwords)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--push", action="store_true", help=f"adb push the file to {fallback_sources.DEVICE_DIR}/")
    args = ap.parse_args()
    if not os.path.exists(args.db):
        sys.exit(f"missing {args.db}: build the plugin database first (tools/build_db.py)")
    try:
        import slob  # noqa: F401
    except ImportError:
        sys.exit("needs the slob reader: pip install git+https://github.com/itkach/slob.git (see above for ICU)")
    src = args.source if os.path.exists(args.source) else fallback_sources.download_file(URL, args.source)
    import moegirl_slob
    tags, nkeys, _blobs = moegirl_slob.tags(src)
    print(f"{os.path.basename(src)}: {nkeys:,} keys, created {tags.get('created.at', '?')}, "
          f"licence {tags.get('license.name', '?')}")
    sha = fallback_sources.sha256_of(src)
    if sha != SHA256:
        print(f"  note: SHA-256 {sha} is not the snapshot's {SHA256}; the slang filter was checked on that one")

    cedict, measure = fallback_sources.cedict_forms(args.db)
    stats = Counter()
    rows = fallback_sources.moegirl_rows(src, cedict, measure, stats)
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")
    meta = {"fallback_sources": "moegirl", "moegirl_rows": str(len(set(rows))),
            "moegirl_file": os.path.basename(src), "moegirl_sha256": sha,
            "moegirl_snapshot": (tags.get("created.at") or "")[:10], "moegirl_url": URL,
            "moegirl_license": LICENSE}
    fallback_sources.write_local_file(args.out, rows, meta, "Moegirlpedia")
    print(f"Moegirlpedia slang: {meta['moegirl_rows']} rows (snapshot {meta['moegirl_snapshot'] or '?'}), "
          f"SHA-256 {sha}")
    print(f"Wrote {args.out} ({os.path.getsize(args.out) / 1e6:.2f} MB). {LICENSE}")
    fallback_sources.push_or_explain(args.out, args.push)


if __name__ == "__main__":
    main()
