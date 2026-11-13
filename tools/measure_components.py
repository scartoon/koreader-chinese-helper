#!/usr/bin/env python3
"""Phase 1 measurement: how many characters, by frequency band, have a
component analysis in English Wiktionary (a `Han compound` template) and in
Make Me a Hanzi, and where both have one, how often they disagree.

    .venv/bin/python tools/measure_components.py [--disagreements N]

Reads build/sources/wiktionary/kaikki-Chinese.jsonl.gz (or its cached
char_etym.jsonl), build/sources/mmah/dictionary.txt and the chars table of
chinesehelper.koplugin/data/chinesehelper.sqlite (for ranks).
"""
import argparse
import collections
import os
import random
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))
import components as comp  # noqa: E402

BANDS = [(1, 2500), (2501, 3500), (3501, 5000), (5001, 7000), (7001, 10**9)]


def band_of(rank):
    for lo, hi in BANDS:
        if lo <= rank <= hi:
            return (lo, hi)


def band_name(b):
    lo, hi = b
    return f"{lo:,}+" if hi > 10**8 else f"{lo:,}–{hi:,}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--disagreements", type=int, default=30)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    root = os.path.join(os.path.dirname(__file__), "..")
    db = sqlite3.connect(os.path.join(root, "chinesehelper.koplugin/data/chinesehelper.sqlite"))
    ranks = dict(db.execute("SELECT ch, rank FROM chars"))
    wikt = comp.load_wiktionary(os.path.join(root, "build/sources/wiktionary"))
    mmah = comp.load_mmah(os.path.join(root, "build/sources/mmah/dictionary.txt"))
    t2s = {}
    for simp, trad in db.execute("SELECT simp, trad FROM entries WHERE length(simp) = 1 AND simp != trad"):
        t2s.setdefault(trad, simp)

    rows = collections.defaultdict(collections.Counter)
    disagree = []
    for ch, rank in ranks.items():
        b = band_of(rank)
        r = rows[b]
        r["chars"] += 1
        w = wikt.get(ch)
        wc = w and w.get("compound")
        m = mmah.get(ch)
        mc = m and comp.mmah_analysis(m)
        via = None
        if not wc and w and w.get("simp_of"):
            t = wikt.get(w["simp_of"])
            via = t and t.get("compound")
        if wc:
            r["wikt"] += 1
            if wc["disputed"]:
                r["wikt_disputed"] += 1
        elif via:
            r["wikt_via_trad"] += 1
        if m:
            r["mmah_any"] += 1
        if mc and mc["parts"]:
            r["mmah"] += 1
            if not wc and not via:
                r["mmah_only"] += 1
        if not wc and not via and not (mc and mc["parts"]):
            r["neither"] += 1
        if wc and mc and mc["parts"]:
            r["both"] += 1
            kind = comp.compare(wc, mc, t2s)
            if kind:
                r["dis_" + kind] += 1
                disagree.append((ch, rank, kind, wc, mc, m))

    print("| Rank | Chars | Wikt Han compound | (disputed) | Wikt via trad. form | MMAH has char | MMAH only | Neither | Both | Disagree: parts | Disagree: roles |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for b in BANDS:
        r = rows[b]
        n = r["chars"]
        pct = lambda k: f"{r[k]:,} ({100 * r[k] / n:.0f}%)"
        both = r["both"] or 1
        print(f"| {band_name(b)} | {n:,} | {pct('wikt')} | {r['wikt_disputed']:,} | {pct('wikt_via_trad')} | "
              f"{pct('mmah_any')} | {pct('mmah_only')} | {pct('neither')} | {r['both']:,} | "
              f"{r['dis_parts']:,} ({100 * r['dis_parts'] / both:.0f}%) | {r['dis_roles']:,} ({100 * r['dis_roles'] / both:.0f}%) |")

    random.seed(args.seed)
    sample = random.sample(disagree, min(args.disagreements, len(disagree)))
    print(f"\n{len(disagree)} disagreements; a random {len(sample)}:")
    for ch, rank, kind, wc, mc, m in sorted(sample, key=lambda x: x[1]):
        print(f"\n{ch} rank {rank} ({kind})")
        print("  wikt:", comp.describe(wc))
        print("  mmah:", comp.describe(mc), "| decomposition", m.get("decomposition"),
              "| hint:", (m.get("etymology") or {}).get("hint"))


if __name__ == "__main__":
    main()
