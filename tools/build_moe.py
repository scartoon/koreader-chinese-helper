#!/usr/bin/env python3
"""Build the optional MOE fallback dictionary for your own device:
教育部《重編國語辭典修訂本》 (the Taiwan Ministry of Education's Revised
Mandarin Chinese Dictionary), via g0v/moedict-data.

    pip install opencc
    python3 tools/build_moe.py                 # -> build/chinesehelper-moe.sqlite
    python3 tools/build_moe.py --push          # ... and adb push it to the device

The dictionary is licensed CC BY-ND 3.0 TW (© 中華民國教育部). That allows
copying it for your own use, but not distributing adaptations, so this file is
never committed, never part of a release, and never shared: you build it
yourself, for your own device. The plugin works without it.

On the device it goes in KOReader's data folder, where plugin updates leave it
alone:

    <KOReader data>/data/chinesehelper/chinesehelper-moe.sqlite
    Android: /sdcard/koreader/data/chinesehelper/chinesehelper-moe.sqlite

What the file holds: one `fallback` table, the same as the release database's
(see tools/fallback_sources.py), with source "moe", and a `meta` table.
  * Headwords are traditional; each is also indexed under its simplified form
    from OpenCC's tw2s (character conversion only).
  * Definitions as MOE writes them (defs), and again in simplified
    characters (defs_simp, for the popup's Dictionary text: Simplified;
    tools/simplify.py: OpenCC tw2s with fixes: 著 "to write" stays 著, one
    character quoted in 「」 stays as written, a character whose simplified
    form the device fonts lack stays traditional).
  * Readings are MOE's, Taiwan standard.
  * Left out: headwords with private-use characters, headwords that are not
    1-8 Han characters, everyday combinations and numerals.
  * Headwords CC-CEDICT has (read from the plugin database, taken from the
    latest release when missing) are kept as covered rows (covered = 1, meta
    moe_covered = 1): the plugin never uses them as fallback entries.
    Wiktionary's headwords are kept: the plugin applies the source priority
    when looking words up, so MOE still covers them when Wiktionary is off.
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.request
from collections import Counter
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://raw.githubusercontent.com/g0v/moedict-data/main/dict-revised.json.xz"
COMMITS = "https://api.github.com/repos/g0v/moedict-data/commits?path=dict-revised.json.xz&per_page=1"
DEFAULT_SRC = os.path.join(ROOT, "build", "sources", "moe", "dict-revised.json.xz")
DEFAULT_OUT = os.path.join(ROOT, "build", "chinesehelper-moe.sqlite")
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
DEVICE_DIR = fallback_sources.DEVICE_DIR
LICENSE = ("CC BY-ND 3.0 TW, 中華民國教育部《重編國語辭典修訂本》 (via g0v/moedict-data). "
           "For your own use: do not distribute this file.")


def download(path):
    """The dictionary, and next to it <file>.info.json with the moedict-data
    commit it came from."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    headers = {"User-Agent": "koreader-chinese-helper build script"}
    print(f"Downloading {URL}")
    with urllib.request.urlopen(urllib.request.Request(URL, headers=headers), timeout=300) as r, \
            open(path, "wb") as f:
        f.write(r.read())
    info = {"url": URL, "downloaded": date.today().isoformat()}
    try:
        with urllib.request.urlopen(urllib.request.Request(COMMITS, headers=headers), timeout=60) as r:
            commit = json.load(r)[0]
        info["commit"] = commit["sha"]
        info["commit_date"] = commit["commit"]["committer"]["date"]
    except Exception as e:  # noqa: BLE001  (the commit is a nice-to-have)
        print(f"  (could not read the moedict-data commit: {e})")
    with open(path + ".info.json", "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SRC, help="dict-revised.json.xz; downloaded when missing")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (for CC-CEDICT's headwords); "
                                                  "taken from the latest release when missing")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--push", action="store_true", help=f"adb push the file to {DEVICE_DIR}/")
    args = ap.parse_args()
    fallback_sources.ensure_db(args.db)
    src = args.source if os.path.exists(args.source) else download(args.source)
    info = {}
    if os.path.exists(src + ".info.json"):
        with open(src + ".info.json", encoding="utf-8") as f:
            info = json.load(f)
    with open(src, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()

    cedict, measure = fallback_sources.cedict_forms(args.db)
    stats = Counter()
    covered = []
    rows = fallback_sources.moe_rows(src, cedict, measure, stats, covered=covered)
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")

    meta = {"fallback_sources": "moe", "moe_rows": str(len(set(rows))), "moe_sha256": sha,
            "moe_url": info.get("url", URL), "moe_commit": info.get("commit", ""),
            "moe_commit_date": info.get("commit_date", ""), "moe_license": LICENSE,
            "moe_text": "both",
            "moe_covered": "1",
            "moe_covered_char_rows": str(sum(1 for r in set(covered) if len(r[0]) == 1)),
            "moe_covered_word_rows": str(sum(1 for r in set(covered) if len(r[0]) > 1))}
    fallback_sources.write_local_file(args.out, rows, meta, "MOE", covered=covered)
    print(f"MOE: {meta['moe_rows']} rows ({meta['moe_covered_char_rows']} covered character rows, "
          f"{meta['moe_covered_word_rows']} covered word rows), source SHA-256 {sha}"
          + (f", moedict-data {info['commit'][:7]} ({info.get('commit_date', '')[:10]})" if info.get("commit") else ""))
    print(f"Wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB). {LICENSE}")
    fallback_sources.push_or_explain(args.out, args.push)


if __name__ == "__main__":
    main()
