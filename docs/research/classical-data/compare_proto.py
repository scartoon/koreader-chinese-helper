"""#65 step 4: compare two builds of the Classical data on the prototype
characters: entry length, sense counts, and the senses of every character
ranked <= 500 side by side for the hand review.

    python compare_proto.py OLD.tsv.gz NEW.tsv.gz CHARS_FILE DB
"""
import csv, gzip, json, sqlite3, statistics, sys
csv.field_size_limit(10 ** 8)


def load(path):
    out = {}
    with gzip.open(path, "rt", encoding="utf-8", newline="") as f:
        for row in csv.reader((l for l in f if not l.startswith("#")), delimiter="\t"):
            if row[0] == "entry":
                out[row[1]] = (row[2], json.loads(row[3]))
    return out


old, new = load(sys.argv[1]), load(sys.argv[2])
chars = list(dict.fromkeys(c for c in open(sys.argv[3]).read() if not c.isspace()))
rank = dict(sqlite3.connect(sys.argv[4]).execute("SELECT ch, rank FROM chars"))
for name, d in (("old", old), ("new", new)):
    lens = sorted((sum(len(s["gloss"]) for s in d[c][1]) + 3 * (len(d[c][1]) - 1), c) for c in chars if c in d)
    ns = [len(d[c][1]) for c in chars if c in d]
    L = [x for x, _ in lens]
    print(f"{name}: {len(L)} entries, length median {statistics.median(L):.0f}, "
          f"p90 {L[int(len(L) * 0.9)]}, longest {lens[-3:]}; senses median {statistics.median(ns)}, max {max(ns)}")
if "-v" in sys.argv:
    for c in chars:
        r = rank.get(old.get(c, new.get(c, (c,)))[0]) or rank.get(c) or 0
        if 0 < r <= 500:
            print(f"\n{c} (rank {r})")
            print("  v3: " + " / ".join(s["gloss"] for s in old.get(c, (0, []))[1]))
            for i, s in enumerate(new.get(c, (0, []))[1], 1):
                print(f"  v4 {i}. {s['gloss']}   [{','.join(s['sources'])}]")
