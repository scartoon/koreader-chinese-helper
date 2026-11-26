#!/usr/bin/env python3
"""Build the optional dictionaries in one go: the files the plugin can't ship
(see the README's "Optional dictionaries"), each with its own script.

    .venv/bin/python tools/build_optional.py                 # Xinhua idioms
    .venv/bin/python tools/build_optional.py --all           # ... and CBDB office titles
    .venv/bin/python tools/build_optional.py --only xinhua,cbdb # just these
    .venv/bin/python tools/build_optional.py --only moegirl  # Moegirlpedia (needs the slob reader)
    .venv/bin/python tools/build_optional.py --push          # ... and adb push each file to the device

Names for --only: xinhua, cbdb, moegirl. (MOE's two dictionaries are part of
the plugin since 2.28.0: tools/build_moe.py builds them for the release.) Moegirlpedia is built
only when --only names it: it needs the slob reader (and ICU) and a 1.4 GB
download.

A file already in build/ is skipped (with --push it is still pushed); --force
builds it again. Downloads go into build/sources/ and are reused. The plugin
database, which every script reads for CC-CEDICT's headwords, is taken from
the latest release when chinesehelper.koplugin/data/ doesn't have it.
"""
import argparse
import glob
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
BUILD = os.path.join(ROOT, "build")
SOURCES = os.path.join(BUILD, "sources")
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
MB = 1_000_000

# name: (label, script, download MB, extra disk MB beyond the download, file MB,
#        glob of the downloaded source)
DICTS = {
    "xinhua": ("Xinhua idioms", "build_xinhua.py", 10, 0, 14.9, "xinhua/idiom.json"),
    "cbdb": ("CBDB office titles", "build_cbdb.py", 140, 590, 0.5, "cbdb/db/*"),
    "moegirl": ("Moegirlpedia slang", "build_moegirl.py", 1400, 0, 0.1,
                "moegirl/zhmoegirl-20230507-alpha.slob"),
}
DEFAULT = ["xinhua"]
ALL = DEFAULT + ["cbdb"]
# The release zip's size and the database unzipped from it.
DB_DOWNLOAD, DB_DISK = 17, 36

SLOB_HINT = """Moegirlpedia needs the slob reader, which needs the ICU library:
  macOS:  brew install icu4c pkg-config, then
          PKG_CONFIG_PATH=$(brew --prefix icu4c)/lib/pkgconfig .venv/bin/pip install git+https://github.com/itkach/slob.git
  Linux (Debian, Ubuntu):  sudo apt install libicu-dev pkg-config, then
          .venv/bin/pip install git+https://github.com/itkach/slob.git
See the README's "Moegirlpedia slang"."""


def out_path(name):
    return os.path.join(BUILD, f"chinesehelper-{name}.sqlite")


def has_source(name):
    return bool(glob.glob(os.path.join(SOURCES, DICTS[name][5])))


def size(mb):
    return f"{mb / 1000:.1f} GB" if mb >= 1000 else f"{mb:.0f} MB"


def pick(args):
    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in names if n not in DICTS]
        if unknown:
            sys.exit(f"unknown dictionary: {', '.join(unknown)} (choose from {', '.join(DICTS)})")
        return list(dict.fromkeys(names))
    return ALL if args.all else DEFAULT


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--all", action="store_true", help="the recommended three and CBDB office titles")
    group.add_argument("--only", metavar="NAMES", help=f"comma-separated, from: {', '.join(DICTS)}")
    ap.add_argument("--force", action="store_true", help="build files that are already in build/ again")
    ap.add_argument("--push", action="store_true", help=f"adb push each file to {fallback_sources.DEVICE_DIR}/")
    args = ap.parse_args()
    names = pick(args)
    sys.stdout.reconfigure(line_buffering=True)  # in order with the scripts' output when piped

    if "moegirl" in names:
        try:
            import slob  # noqa: F401
        except ImportError:
            sys.exit(SLOB_HINT)

    todo = [n for n in names if args.force or not os.path.exists(out_path(n))]
    skipped = [n for n in names if n not in todo]
    for n in skipped:
        print(f"{DICTS[n][0]}: {os.path.relpath(out_path(n))} is already built (--force to build it again)")
    if todo:
        down = sum(DICTS[n][2] for n in todo if not has_source(n))
        disk = sum(DICTS[n][4] + (0 if has_source(n) else DICTS[n][2] + DICTS[n][3]) for n in todo)
        if not os.path.exists(DB):
            down += DB_DOWNLOAD
            disk += DB_DOWNLOAD + DB_DISK
        print(f"Building {', '.join(DICTS[n][0] for n in todo)}: "
              f"about {size(down)} to download, {size(disk)} of disk space")
        if "moegirl" in todo:
            print("  (reading the Moegirlpedia snapshot takes 10-15 minutes)")
        fallback_sources.ensure_db(DB)

    failed = []
    for n in todo:
        label, script = DICTS[n][:2]
        print(f"\n== {label} ({script})")
        cmd = [sys.executable, os.path.join(TOOLS, script)]
        if args.push:
            cmd.append("--push")
        if subprocess.run(cmd, cwd=ROOT).returncode != 0:
            failed.append(n)
    if args.push:
        for n in skipped:
            fallback_sources.push_or_explain(out_path(n), True)

    print("\nFiles:")
    for n in names:
        if n in failed:
            print(f"  {DICTS[n][0]}: FAILED (see above)")
            continue
        path = out_path(n)
        state = "built" if n in todo else "already built"
        print(f"  {os.path.relpath(path)} ({os.path.getsize(path) / MB:.1f} MB, {state})")
    print(f"They go in {fallback_sources.DEVICE_DIR}/ on Android, or data/chinesehelper/ in the KOReader "
          f"folder that holds plugins; then restart KOReader.")
    if not args.push and len(failed) < len(names):
        print(f"With adb: adb shell mkdir -p {fallback_sources.DEVICE_DIR} && "
              + " && ".join(f"adb push {os.path.relpath(out_path(n))} {fallback_sources.DEVICE_DIR}/"
                            for n in names if n not in failed))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
