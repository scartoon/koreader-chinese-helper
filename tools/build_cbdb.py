#!/usr/bin/env python3
"""Build the optional CBDB fallback dictionary for your own device: Ming and
Southern Ming office titles from the China Biographical Database (CBDB),
with CBDB's English translations.

    .venv/bin/python tools/build_cbdb.py            # -> build/chinesehelper-cbdb.sqlite
    .venv/bin/python tools/build_cbdb.py --push     # ... and adb push it to the device

The source is CBDB's SQLite release on Hugging Face (cbdb/cbdb-sqlite, about
110 MB zipped, 590 MB unzipped), downloaded into build/sources/cbdb/ when
missing. CBDB's data licensing terms
(https://cbdb.hsites.harvard.edu/cbdb-data-licensing-terms) put the data of
the standalone release under CC BY-NC-SA 4.0 and add CBDB's own
non-commercial, no-redistribution terms beyond it. So this file is never
committed, never part of a release, and never shared: you build it yourself,
for your own device. The plugin works without it.

On the device it goes in KOReader's data folder, next to the MOE file:

    <KOReader data>/data/chinesehelper/chinesehelper-cbdb.sqlite
    Android: /sdcard/koreader/data/chinesehelper/chinesehelper-cbdb.sqlite

What the file holds: one `fallback` table, the same as the release
database's (see tools/fallback_sources.py, cbdb_rows), with source "cbdb",
and a `meta` table.
  * Every name and alternative name of OFFICE_CODES rows with c_dy 19 (明)
    or 80 (南明), under its traditional form and OpenCC's t2s.
  * The gloss is CBDB's English translation, "(Ming office title)" added;
    titles CBDB has not translated get "office title (Ming)".
  * The reading is CBDB's own, without tone marks ("dian shi").
  * Left out: names that are not 1-8 Han characters, names CC-CEDICT has
    (read from the plugin database, so build that first), numerals.
"""
import argparse
import json
import os
import sqlite3
import sys
import urllib.request
import zipfile
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "build", "sources", "cbdb")
LATEST = "https://huggingface.co/datasets/cbdb/cbdb-sqlite/resolve/main/latest.json"
DEFAULT_OUT = os.path.join(ROOT, "build", "chinesehelper-cbdb.sqlite")
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
LICENSE = ("CBDB (China Biographical Database), CC BY-NC-SA 4.0 and the CBDB Data Licensing Terms. "
           "For your own use: do not distribute this file.")


def find_source(src_dir):
    """The CBDB SQLite file (and latest.json's metadata), downloading and
    unzipping the release named in latest.json when it is not there yet."""
    os.makedirs(src_dir, exist_ok=True)
    info_path = os.path.join(src_dir, "latest.json")
    if not os.path.exists(info_path):
        req = urllib.request.Request(LATEST, headers={"User-Agent": "koreader-chinese-helper build script"})
        with urllib.request.urlopen(req, timeout=60) as r, open(info_path, "wb") as f:
            f.write(r.read())
    with open(info_path, encoding="utf-8") as f:
        info = json.load(f)
    db = os.path.join(src_dir, "db", info["sqlite_filename"])
    if not os.path.exists(db):
        zpath = os.path.join(src_dir, os.path.basename(info["huggingface_path"]))
        if not os.path.exists(zpath):
            fallback_sources.download_file(info["huggingface_url"], zpath)
        print(f"Unzipping {os.path.relpath(zpath)}")
        with zipfile.ZipFile(zpath) as z:
            member = next(n for n in z.namelist() if n.endswith(info["sqlite_filename"]))
            os.makedirs(os.path.dirname(db), exist_ok=True)
            with z.open(member) as src, open(db + ".part", "wb") as out:
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    out.write(chunk)
            os.replace(db + ".part", db)
    return db, info


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", help="a CBDB SQLite file (default: the release in build/sources/cbdb/, "
                                     "downloaded when missing)")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (for CC-CEDICT's headwords)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--push", action="store_true", help=f"adb push the file to {fallback_sources.DEVICE_DIR}/")
    args = ap.parse_args()
    if not os.path.exists(args.db):
        sys.exit(f"missing {args.db}: build the plugin database first (tools/build_db.py)")
    if args.source:
        src, info = args.source, {}
    else:
        src, info = find_source(SRC_DIR)
    con = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    if not con.execute("SELECT 1 FROM sqlite_master WHERE name = 'OFFICE_CODES'").fetchone():
        sys.exit(f"{src} has no OFFICE_CODES table: is it CBDB?")
    con.close()

    cedict, measure = fallback_sources.cedict_forms(args.db)
    stats = Counter()
    rows = fallback_sources.cbdb_rows(src, cedict, measure, stats)
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")
    sha = info.get("sha256") or fallback_sources.sha256_of(src)
    meta = {"fallback_sources": "cbdb", "cbdb_rows": str(len(set(rows))), "cbdb_file": os.path.basename(src),
            "cbdb_sha256": sha, "cbdb_date": info.get("generated_at_utc", ""),
            "cbdb_url": info.get("huggingface_url", ""), "cbdb_license": LICENSE}
    fallback_sources.write_local_file(args.out, rows, meta, "CBDB")
    print(f"CBDB: {meta['cbdb_rows']} rows from {meta['cbdb_file']} ({meta['cbdb_date'][:10] or 'date unknown'}), "
          f"SHA-256 {sha}")
    print(f"Wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB). {LICENSE}")
    fallback_sources.push_or_explain(args.out, args.push)


if __name__ == "__main__":
    main()
