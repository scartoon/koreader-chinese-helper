"""#69: compare a 文言 build with 2.21.0.

    python compare69.py OLD.tsv.gz NEW.tsv.gz [moe_matches.tsv]

Prints: the judged senses (judgments.tsv, with fix_v5.json's hand check for
2.21.0) that 2.21.0 had and the new build lost; the named test senses; the
50 commonest characters' entries side by side (+ new only, - old only);
and the sense counts restored and dropped."""
import csv, gzip, json, os, re, sqlite3, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
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
    old, ov = load(sys.argv[1])
    new, nv = load(sys.argv[2])
    moe = {}
    if len(sys.argv) > 3:
        for r in csv.DictReader(open(sys.argv[3]), delimiter="\t"):
            moe[(r["headword"], r["gloss"])] = r
    fix = json.load(open(os.path.join(HERE, "fix_v5.json")))
    samp = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "sample.tsv")), delimiter="\t")}
    judg = [j for j in csv.DictReader(open(os.path.join(HERE, "judgments.tsv")), delimiter="\t") if j["status"] == "ok"]
    print("== Judged senses (128)")
    had = lost = 0
    for j in judg:
        ch = samp[j["id"]]["char"]
        og, ng = entry_for(ch, old, ov), entry_for(ch, new, nv)
        kw = re.compile(j["keywords"], re.I)
        pos = fix.get(j["id"], next((i for i, g in enumerate(og, 1) if kw.search(g)), 0))
        if not pos:
            continue
        had += 1
        gloss = og[pos - 1]
        if gloss in ng:
            continue
        lost += 1
        print(f"  LOST {j['id']} {ch}: {gloss}  (need: {j['needed']})")
    print(f"  2.21.0 had {had}; the new build lost {lost}")
    print("\n== Named senses")
    for ch, kw in (("花甲", "sixty"), ("邦交", "diplomatic|relations"), ("外侮", "foreign|aggression|insult"),
                   ("先行", "advance|ahead|first|precede|before"), ("就", r"\bthen\b|at once|right away"),
                   ("要", r"need|must|should|want"), ("的", r"\bof\b|possessive|'s")):
        o = [g for g in entry_for(ch, old, ov) if re.search(kw, g, re.I)]
        n = [g for g in entry_for(ch, new, nv) if re.search(kw, g, re.I)]
        print(f"  {ch}: 2.21.0 {o or '-'}\n     new    {n or '-'}")
        for g in n:
            r = moe.get((ch, g))
            if r and r["decision"] == "kept":
                print(f"       evidence for '{g}': MOE {r['moe_def']}. {r['definition'][:40]} | {r['source']}")
    print("\n== 50 commonest characters")
    db = sqlite3.connect(os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite"))
    top = [c for (c,) in db.execute("SELECT ch FROM chars WHERE rank > 0 ORDER BY rank LIMIT 50")]
    for ch in top:
        og, ng = entry_for(ch, old, ov), entry_for(ch, new, nv)
        if og == ng:
            print(f"  {ch}: unchanged ({len(ng)})")
            continue
        print(f"  {ch}: {len(og)} -> {len(ng)}")
        for g in ng:
            print(f"     {'+' if g not in og else ' '} {g}")
        for g in og:
            if g not in ng:
                print(f"     - {g}")
    restored = dropped = 0
    for h in set(old) | set(new):
        og = set(old.get(h, ("", []))[1])
        ng = set(new.get(h, ("", []))[1])
        restored += len(ng - og)
        dropped += len(og - ng)
    print(f"\n== Totals: entries {len(old)} -> {len(new)}; senses {sum(len(g) for _, g in old.values())} -> "
          f"{sum(len(g) for _, g in new.values())}; {restored} senses only in the new build, {dropped} only in 2.21.0")


main()
