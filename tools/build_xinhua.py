#!/usr/bin/env python3
"""Build the optional Xinhua idiom file for your own device: the idiom list
of chinese-xinhua (https://github.com/pwxcoo/chinese-xinhua, data/idiom.json),
with each idiom's explanation, classical source and an example.

    python3 -m venv .venv && .venv/bin/pip install opencc && .venv/bin/python tools/build_xinhua.py --push
    .venv/bin/python tools/build_xinhua.py   # -> build/chinesehelper-xinhua.sqlite only

The plugin database (for CC-CEDICT's headwords) is taken from the latest
release when chinesehelper.koplugin/data/ has none.

idiom.json is downloaded into build/sources/xinhua/ when missing. The
repository's MIT licence covers its code; the text was scraped from a
published dictionary, so this file is never committed, never part of a
release, and never shared: you build it yourself, for your own device. The
plugin works without it.

On the device it goes in KOReader's data folder, next to the MOE file:

    <KOReader data>/data/chinesehelper/chinesehelper-xinhua.sqlite
    Android: /sdcard/koreader/data/chinesehelper/chinesehelper-xinhua.sqlite

What the file holds (tools/chengyu.py): for each idiom of 4-8 Han
characters, the explanation as the popup's short line, and a 出处 view
(explanation, the classical source quoted, an example with its source) when
the source or an example is given. Idioms CC-CEDICT lacks also get a
fallback entry. Punctuation lost in scraping is put back where that can be
done reliably (see tools/chengyu.py). The text is simplified; headwords are
also indexed under OpenCC's s2t form, for books in traditional characters.
Readings are the data's own and never decide the pinyin drawn above
characters.
"""
import argparse
import json
import os
import sys
import urllib.request
from collections import Counter
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chengyu  # noqa: E402
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://raw.githubusercontent.com/pwxcoo/chinese-xinhua/master/data/idiom.json"
COMMITS = "https://api.github.com/repos/pwxcoo/chinese-xinhua/commits?path=data/idiom.json&per_page=1"
DEFAULT_SRC = os.path.join(ROOT, "build", "sources", "xinhua", "idiom.json")
DEFAULT_OUT = os.path.join(ROOT, "build", "chinesehelper-xinhua.sqlite")
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
LICENSE = ("chinese-xinhua data/idiom.json (text scraped from a published dictionary). "
           "For your own use: do not distribute this file.")


def download(path):
    fallback_sources.download_file(URL, path)
    info = {"url": URL, "downloaded": date.today().isoformat()}
    try:
        req = urllib.request.Request(COMMITS, headers={"User-Agent": "koreader-chinese-helper build script"})
        with urllib.request.urlopen(req, timeout=60) as r:
            commit = json.load(r)[0]
        info["commit"] = commit["sha"]
        info["commit_date"] = commit["commit"]["committer"]["date"]
    except Exception as e:  # noqa: BLE001  (the commit is a nice-to-have)
        print(f"  (could not read the chinese-xinhua commit: {e})")
    with open(path + ".info.json", "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SRC, help="idiom.json; downloaded when missing")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (for CC-CEDICT's headwords); "
                                                  "taken from the latest release when missing")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--push", action="store_true", help=f"adb push the file to {fallback_sources.DEVICE_DIR}/")
    args = ap.parse_args()
    fallback_sources.ensure_db(args.db)
    src = args.source if os.path.exists(args.source) else download(args.source)
    info = {}
    if os.path.exists(src + ".info.json"):
        with open(src + ".info.json", encoding="utf-8") as f:
            info = json.load(f)
    sha = fallback_sources.sha256_of(src)

    import opencc
    s2t = opencc.OpenCC("s2t")
    stats = Counter()
    entries = []
    for e in chengyu.xinhua_entries(src, stats):
        entries.append({"simp": e["simp"], "trad": s2t.convert(e["simp"]), "pinyin": e["pinyin"],
                        "short": e["short"], "view": chengyu.view_text(e["sections"])})
    cedict, _measure = fallback_sources.cedict_forms(args.db)
    fallback, idioms = chengyu.tables(entries, "xinhua", cedict, stats)
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")
    meta = {"fallback_sources": "xinhua", "xinhua_rows": str(len(set(idioms))),
            "xinhua_fallback_rows": str(len(set(fallback))), "xinhua_sha256": sha,
            "xinhua_url": info.get("url", URL), "xinhua_commit": info.get("commit", ""),
            "xinhua_commit_date": info.get("commit_date", ""), "xinhua_built": date.today().isoformat(),
            "xinhua_license": LICENSE}
    fallback_sources.write_local_file(args.out, fallback, meta, "Xinhua",
                                      extra=lambda con: chengyu.write_idioms(con, idioms))
    print(f"Xinhua idioms: {meta['xinhua_rows']} idioms, {meta['xinhua_fallback_rows']} not in CC-CEDICT; "
          f"SHA-256 {sha}" + (f", chinese-xinhua {info['commit'][:7]} ({info.get('commit_date', '')[:10]})"
                              if info.get("commit") else ""))
    print(f"Wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB). {LICENSE}")
    fallback_sources.push_or_explain(args.out, args.push)


if __name__ == "__main__":
    main()
