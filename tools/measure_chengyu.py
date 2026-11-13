#!/usr/bin/env python3
"""Phase 3 measurement: chengyu in the books, and what the popup shows for them.

    python3 tools/fetch_books.py               # first: build/corpus/ (the device's books)
    python3 tools/build_idioms.py; python3 tools/build_xinhua.py   # and the files measured
    python3 tools/measure_chengyu.py           # -> build/measure/chengyu-report.md

An idiom is any headword of 3-8 Han characters that CC-CEDICT tags
"(idiom)", or 4-8 characters in the 成語典 or the Xinhua data. Each
paragraph is scanned for them, longest first, without overlaps; a tap on any
character of an occurrence lists the idiom in the popup (its words are at
most 8 characters, the context 7 each side), so occurrences stand for taps.
For each occurrence: whether the popup has an entry for the idiom, by the
sources a reader has

  release   CC-CEDICT and the Wiktionary fallback (the plugin database)
  + MOE     the user's MOE file (tools/build_moe.py)
  + 成語典 + Xinhua   the two files of this phase

and whether it gets the Chinese short line and a 出处 view. Books:
build/corpus/NNN.txt (the device's books) and linggao-*.txt (临高启明),
reported separately.
"""
import argparse
import collections
import glob
import multiprocessing
import os
import re
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
HAN_RUN = re.compile("[㐀-䶿一-鿿豈-﫿]+")

_IDIOMS = None


def forms(con, sql):
    out = set()
    for row in con.execute(sql):
        out.update(x for x in row if x)
    return out


def load(args):
    con = sqlite3.connect(DB)
    s = {"cedict": forms(con, "SELECT simp, trad FROM entries"),
         "cedict_idiom": forms(con, "SELECT simp, trad FROM entries WHERE defs LIKE '%(idiom)%'"),
         "wikt": forms(con, "SELECT simp, trad FROM fallback WHERE source = 'wikt'")}
    con.close()
    for name, path in (("moe", args.moe), ("idioms", args.idioms), ("xinhua", args.xinhua)):
        if not os.path.exists(path):
            raise SystemExit(f"missing {path}")
        c = sqlite3.connect(path)
        s[name] = forms(c, "SELECT simp, trad FROM fallback")
        if name != "moe":
            s[name + "_all"] = forms(c, "SELECT simp, trad FROM idioms")
            s[name + "_view"] = forms(c, "SELECT simp, trad FROM idioms WHERE view != ''")
        c.close()
    s["idiom"] = ({w for w in s["cedict_idiom"] if 3 <= len(w) <= 8}
                  | {w for w in s["idioms_all"] | s["xinhua_all"] if 4 <= len(w) <= 8})
    return s


def _init(idioms):
    global _IDIOMS
    _IDIOMS = idioms


def _scan(path):
    """{idiom: occurrences} in one book."""
    found = collections.Counter()
    lens = range(8, 2, -1)
    for line in open(path, encoding="utf-8"):
        for run in HAN_RUN.findall(line):
            i, n = 0, len(run)
            while i < n - 2:
                for L in lens:
                    if i + L <= n and run[i:i + L] in _IDIOMS:
                        found[run[i:i + L]] += 1
                        i += L
                        break
                else:
                    i += 1
    return os.path.basename(path), found


def scan(files, idioms):
    total = collections.Counter()
    with multiprocessing.Pool(max(1, os.cpu_count() - 1), initializer=_init, initargs=(idioms,)) as pool:
        for _name, found in pool.imap_unordered(_scan, files):
            total.update(found)
    return total


def classify(w, s):
    cedict = w in s["cedict"]
    has = {"release": cedict or w in s["wikt"]}
    has["moe"] = has["release"] or w in s["moe"]
    has["after"] = has["moe"] or w in s["idioms"] or w in s["xinhua"]
    has["after_no_moe"] = has["release"] or w in s["idioms"] or w in s["xinhua"]
    has["short"] = w in s["idioms_all"] or w in s["xinhua_all"]
    has["view"] = w in s["idioms_view"] or w in s["xinhua_view"]
    has["view_idioms"] = w in s["idioms_view"]
    has["cedict"] = cedict
    has["new"] = has["after"] and not has["moe"]
    has["by"] = ("idioms" if w in s["idioms"] else "xinhua") if (not has["moe"] and has["after"]) else ""
    return has


def pct(a, b):
    return f"{100 * a / b:.1f}%" if b else "-"


def report(title, found, s, w):
    types = list(found)
    occ = sum(found.values())
    w(f"## {title}\n")
    w(f"{occ:,} idiom occurrences, {len(types):,} distinct idioms.\n")
    w("| Popup | occurrences | distinct |")
    w("|---|---|---|")
    rows = [("entry, release only (CC-CEDICT, Wiktionary)", "release"),
            ("entry, release + MOE (1.8.0 with the MOE file)", "moe"),
            ("entry, release + 成語典 + Xinhua (no MOE)", "after_no_moe"),
            ("entry, release + MOE + 成語典 + Xinhua", "after"),
            ("Chinese short line (成語典 or Xinhua has it)", "short"),
            ("出处 view", "view"),
            ("出处 view from the 成語典", "view_idioms")]
    info = {t: classify(t, s) for t in types}
    for label, key in rows:
        o = sum(found[t] for t in types if info[t][key])
        d = sum(1 for t in types if info[t][key])
        w(f"| {label} | {o:,} ({pct(o, occ)}) | {d:,} ({pct(d, len(types))}) |")
    w("")
    ced = [t for t in types if info[t]["cedict"]]
    o = sum(found[t] for t in ced)
    o2 = sum(found[t] for t in ced if info[t]["view"])
    w(f"Of the {o:,} occurrences CC-CEDICT has an entry for, {o2:,} ({pct(o2, o)}) now get a 出处 view.\n")
    new = sorted((t for t in types if info[t]["new"]), key=lambda t: -found[t])
    by = collections.Counter(info[t]["by"] for t in new)
    w(f"Newly covered (no entry before, even with MOE): {len(new):,} idioms, "
      f"{sum(found[t] for t in new):,} occurrences; from the 成語典 {by['idioms']:,}, Xinhua {by['xinhua']:,}. "
      "Most frequent: " + "、".join(f"{t} {found[t]}" for t in new[:30]) + "\n")
    still = sorted((t for t in types if not info[t]["after"]), key=lambda t: -found[t])
    w(f"Still without an entry: {len(still):,} idioms, {sum(found[t] for t in still):,} occurrences. "
      "Most frequent: " + "、".join(f"{t} {found[t]}" for t in still[:30]) + "\n")
    noview = sorted((t for t in types if info[t]["after"] and not info[t]["view"]), key=lambda t: -found[t])
    w(f"An entry but no 出处 view: {len(noview):,} idioms, {sum(found[t] for t in noview):,} occurrences. "
      "Most frequent: " + "、".join(f"{t} {found[t]}" for t in noview[:30]) + "\n")
    return {"occ": occ, "types": len(types)}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--moe", default=os.path.join(BUILD, "chinesehelper-moe.sqlite"))
    ap.add_argument("--idioms", default=os.path.join(BUILD, "chinesehelper-idioms.sqlite"))
    ap.add_argument("--xinhua", default=os.path.join(BUILD, "chinesehelper-xinhua.sqlite"))
    ap.add_argument("--out", default=os.path.join(BUILD, "measure", "chengyu-report.md"))
    args = ap.parse_args()
    s = load(args)
    corpus = os.path.join(BUILD, "corpus")
    books = sorted(f for f in glob.glob(os.path.join(corpus, "*.txt")) if re.match(r"\d+\.txt$", os.path.basename(f)))
    linggao = sorted(glob.glob(os.path.join(corpus, "linggao-*.txt")))
    L = []
    w = L.append
    w("# Chengyu coverage (tools/measure_chengyu.py)\n")
    w(f"Idioms: {len(s['idiom']):,} headword forms (CC-CEDICT \"(idiom)\" 3-8 characters "
      f"{len(s['cedict_idiom']):,} forms; 成語典 {len(s['idioms_all']):,}; Xinhua {len(s['xinhua_all']):,}).\n")
    report(f"The device's books ({len(books)} files)", scan(books, s["idiom"]), s, w)
    report("临高启明 (linggao-*.txt)", scan(linggao, s["idiom"]), s, w)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main()
