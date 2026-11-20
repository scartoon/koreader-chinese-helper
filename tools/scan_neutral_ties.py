#!/usr/bin/env python3
"""Scan for #51: CC-CEDICT words with a neutral syllable on a character
that has two or more entries of the same letters (发 fā / fà for 头发
tóu fa). For each, which entry the popup's pass 3 marks today (the
character's default reading, when it is one of them) and which it marks
with the traditional-form tie-break (the entry whose traditional forms
include the word's traditional form of that character).

    python3 tools/scan_neutral_ties.py [out.tsv]

Prints the counts and writes every tie to out.tsv (default
build/scan51/ties.tsv): word, trad, char, trad char, neutral syllable,
the same-letter readings, today's mark, the tie-break's mark, changed.
"""
import os
import sqlite3
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")


def strip(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if not unicodedata.combining(c)).replace("ü", "u")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "scan51", "ties.tsv")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    con = sqlite3.connect(DB)
    default = dict(con.execute("SELECT ch, reading FROM chars"))
    # Each character's entries as the popup merges them (cleanRows): by
    # pinyin, with the traditional forms of the rows keyed by it as
    # simplified; ordinary readings only (capitalised ones are surnames).
    entries = {}
    for simp, trad, syl in con.execute("SELECT simp, trad, syllables FROM entries WHERE length(simp) = 1"):
        if syl[:1].isupper():
            continue
        entries.setdefault(simp, {}).setdefault(syl.lower(), set()).add(trad)
    seen, rows = set(), []
    for simp, trad, syl in con.execute("SELECT simp, trad, syllables FROM entries WHERE length(simp) > 1"):
        sylls = syl.split()
        if len(sylls) != len(simp) or len(trad) != len(simp) or syl[:1].isupper():
            continue
        for i, s in enumerate(sylls):
            s = s.lower()
            if strip(s) != s or not s.isalpha():
                continue     # not neutral
            ch = simp[i]
            same = {r: t for r, t in entries.get(ch, {}).items() if strip(r) == s}
            if len(same) < 2 or s in same:
                continue     # one entry, or the neutral reading is an entry itself (子 zi): pass 1 marks it
            key = (simp, i, s)
            if key in seen:
                continue
            seen.add(key)
            d = (default.get(ch) or "").lower()
            today = [d] if d in same else sorted(same)
            pick = [r for r, t in same.items() if trad[i] in t]
            new = sorted(pick) if pick and len(pick) < len(same) else today
            rows.append((simp, trad, ch, trad[i], s, "/".join(sorted(same)), "/".join(today), "/".join(new),
                         "changed" if new != today else ""))
    # Step 3's question: of the ties the traditional form leaves alone, how
    # many would MOE's citation tone of the word (the user-built MOE file,
    # when present) mark differently from today's default?
    moe_path = os.path.join(ROOT, "build", "chinesehelper-moe.sqlite")
    moe = {}
    if os.path.exists(moe_path):
        for simp, syl in sqlite3.connect(moe_path).execute("SELECT simp, pinyin FROM fallback"):
            moe.setdefault(simp, syl)
    moe_rows = []
    for r in rows:
        if r[8]:
            continue
        syl = moe.get(r[0])
        if not syl:
            continue
        sylls = syl.lower().split()
        i = r[0].index(r[2])
        if len(sylls) != len(r[0]):
            continue
        cite = sylls[i]
        if cite in r[5].split("/") and cite not in r[6].split("/"):
            moe_rows.append((r[0], r[2], r[4], r[6], cite))
    with open(out.replace(".tsv", "-moe.tsv"), "w") as f:
        f.write("word\tchar\tneutral\ttoday\tmoe\n")
        for r in moe_rows:
            f.write("\t".join(r) + "\n")
    with open(out, "w") as f:
        f.write("word\ttrad\tchar\ttrad_char\tneutral\treadings\ttoday\ttiebreak\tchanged\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
    changed = [r for r in rows if r[8]]
    print(f"ties: {len(rows)} (word, neutral position) on {len({r[2] for r in rows})} characters")
    print(f"changed by the tie-break: {len(changed)}")
    print(f"not separated by the traditional form: {len(rows) - len(changed)}")
    if moe:
        print(f"of those, MOE's citation tone differs from today's mark: {len(moe_rows)} "
              f"(written to {out.replace('.tsv', '-moe.tsv')})")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
