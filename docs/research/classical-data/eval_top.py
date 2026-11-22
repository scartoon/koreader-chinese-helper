"""#65: where the needed sense sits in the 文言 entry.

    python eval_top.py ENTRIES [FIX.json]

ENTRIES is data/classical.tsv.gz (or a build of it). For each judged sense
(judgments.tsv, status ok) it finds the character's entry (its own, else
through classical_variant, else the simp column) and the first sense whose
gloss matches the judgment's keyword pattern. FIX.json holds the hand
check: {"id": position or 0} overriding the keyword result (0 = not in the
entry). Prints every row for checking and the totals."""
import csv, gzip, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
csv.field_size_limit(10 ** 8)


def load(path):
    entries, var = {}, {}
    with gzip.open(path, "rt", encoding="utf-8", newline="") as f:
        for row in csv.reader((l for l in f if not l.startswith("#")), delimiter="\t"):
            if row[0] == "entry":
                entries[row[1]] = (row[2], [s["gloss"] for s in json.loads(row[3])])
            else:
                var[row[1]] = row[2]
    return entries, var


def entry_for(ch, entries, var):
    if ch in entries:
        return entries[ch][1]
    if ch in var:
        return entries[var[ch]][1]
    for t, (s, g) in sorted(entries.items()):
        if s == ch:
            return g
    return []


def main():
    entries, var = load(sys.argv[1])
    fix = json.load(open(sys.argv[2])) if len(sys.argv) > 2 and os.path.exists(sys.argv[2]) else {}
    samp = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "sample.tsv")), delimiter="\t")}
    verd = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "verdicts.tsv")), delimiter="\t")}
    judg = [j for j in csv.DictReader(open(os.path.join(HERE, "judgments.tsv")), delimiter="\t") if j["status"] == "ok"]
    rows = []
    for j in judg:
        ch = samp[j["id"]]["char"]
        glosses = entry_for(ch, entries, var)
        kw = re.compile(j["keywords"], re.I)
        pos = next((i for i, g in enumerate(glosses, 1) if kw.search(g)), 0)
        auto = pos
        if j["id"] in fix:
            pos = fix[j["id"]]
        rows.append((j["id"], ch, samp[j["id"]]["band"], pos, auto, j["needed"], glosses, verd[j["id"]]["cedict"] == "1"))
    for r in rows:
        mark = "" if r[3] == r[4] else f" (keyword said {r[4]})"
        print(f"{r[0]:>4} {r[1]} {r[2]:8s} pos {r[3]}{mark} | need: {r[5][:45]} | {' / '.join(r[6])[:220]}")
    n = len(rows)
    for band in ("over", "top500", "500-3000", "rare", None):
        sub = [r for r in rows if band is None or r[2] == band]
        k = len(sub)
        inn = sum(1 for r in sub if r[3]); top2 = sum(1 for r in sub if 0 < r[3] <= 2)
        top1 = sum(1 for r in sub if r[3] == 1)
        popup = sum(1 for r in sub if r[3] or r[7])
        print(f"{band or 'all':9s} n={k:3d} in entry {inn:3d} ({inn/k:.0%})  first two {top2:3d} ({top2/k:.0%})  "
              f"first {top1:3d} ({top1/k:.0%})  popup (with CC-CEDICT) {popup:3d} ({popup/k:.0%})")
    ps = sorted(r[3] for r in rows if r[3])
    print("positions when present:", {p: ps.count(p) for p in sorted(set(ps))})


main()
