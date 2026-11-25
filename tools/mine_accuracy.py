#!/usr/bin/env python3
"""#35 step 7: an absolute estimate of learner mode's accuracy on the held-out books.

    mine_accuracy.py make DIR [--n 300]   judging batches build/judge/accuracy-NNN.tsv
    mine_accuracy.py gold DIR             merge the per-batch verdicts into the gold set
                                          build/judge/accuracy-verdicts.tsv
    mine_accuracy.py score DIR [--now]    learner mode against the gold set: the readings
                                          sampled before the fixes (DIR/sample.tsv), or with
                                          --now the plugin as the data stands now

DIR is the held-out sample (mine_sample.py --heldout). `make` draws --n rows at
random, weighted by count/sampled, so the draw is uniform over the polyphone
occurrences of the held-out books; it also writes DIR/accuracy_items.tsv and
DIR/polyphone_share.txt (polyphone occurrences / Han characters in those books).
The judge sees the character's readings in the database, not the plugin's or
g2pW's, so its answer is independent of both."""
import argparse, collections, csv, glob, os, random, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
ap = argparse.ArgumentParser()
ap.add_argument("cmd", choices=("make", "gold", "score"))
ap.add_argument("dir")
ap.add_argument("--n", type=int, default=300)
ap.add_argument("--per", type=int, default=25)
ap.add_argument("--now", action="store_true")
args = ap.parse_args()
d = args.dir
jd = os.path.join(ROOT, "build/judge")
csv.field_size_limit(1 << 20)


def rd(path):
    return csv.DictReader(open(path, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE)


HAN = re.compile(r"[㐀-鿿豈-﫿\U00020000-\U0003134f]")

if args.cmd == "make":
    readings = {}
    for line in open(os.path.join(ROOT, "build/data/reading_shares.tsv"), encoding="utf-8"):
        if not line.startswith("#"):
            f = line.rstrip("\n").split("\t")
            if len(f) >= 3:
                readings[f[0]] = " / ".join(x.rsplit(":", 1)[0] for x in f[2].split())
    weight = {r["char"]: int(r["count"]) / int(r["sampled"]) for r in rd(os.path.join(d, "counts.tsv"))
              if int(r["sampled"])}
    rows = [r for r in rd(os.path.join(d, "sample.tsv")) if r["drawn"]]
    rng = random.Random(35)
    # Weighted sampling without replacement (Efraimidis-Spirakis keys).
    keyed = sorted(rows, key=lambda r: -rng.random() ** (1 / weight[r["char"]]))
    pick = keyed[:args.n]
    with open(os.path.join(d, "accuracy_items.tsv"), "w", encoding="utf-8") as out:
        out.write("item\tid\tbook\tchar\tpos\tsentence\n")
        for i, r in enumerate(pick):
            out.write(f"a{i:03d}\t{r['id']}\t{r['book']}\t{r['char']}\t{r['pos']}\t{r['sentence']}\n")
    for k in range(0, len(pick), args.per):
        p = os.path.join(jd, f"accuracy-{k // args.per:03d}.tsv")
        if os.path.exists(p):
            continue
        with open(p, "w", encoding="utf-8") as out:
            out.write("item\tchar\treadings\tcontext\n")
            for j, r in enumerate(pick[k:k + args.per]):
                s, q = r["sentence"], int(r["pos"])
                ctx = s[:q] + "【" + s[q] + "】" + s[q + 1:]
                out.write(f"a{k + j:03d}\t{r['char']}\t{readings.get(r['char'], '')}\t{ctx}\n")
    # Polyphone share of the held-out books' Han characters.
    held = {l.split("\t")[0] for l in open(os.path.join(ROOT, "build/heldout_books.txt")) if l.strip()}
    han = 0
    for f in glob.glob(os.path.join(ROOT, "build/corpus/*.txt")):
        if os.path.basename(f)[:-4] in held:
            han += len(HAN.findall(open(f, encoding="utf-8").read()))
    poly = sum(int(r["count"]) for r in rd(os.path.join(d, "counts.tsv")))
    open(os.path.join(d, "polyphone_share.txt"), "w").write(f"{poly}\t{han}\t{poly / han:.4f}\n")
    print(f"items {len(pick)}, batches {(len(pick) + args.per - 1) // args.per}; "
          f"polyphones {poly} / Han {han} = {100 * poly / han:.1f}%")

elif args.cmd == "gold":
    items = {r["item"]: r for r in rd(os.path.join(d, "accuracy_items.tsv"))}
    got = {}
    for p in sorted(glob.glob(os.path.join(jd, "accuracy-*.verdicts.tsv"))):
        for r in rd(p):
            got[r["item"]] = r
    with open(os.path.join(jd, "accuracy-verdicts.tsv"), "w", encoding="utf-8") as out:
        out.write("item\tbook\tsentence\tpos\tchar\treading\tconfidence\tnote\n")
        for k, it in items.items():
            if k in got:
                v = got[k]
                out.write("\t".join([k, it["book"], it["sentence"], it["pos"], it["char"], v["reading"],
                                     v["confidence"], v.get("note") or ""]) + "\n")
    c = collections.Counter(v["confidence"] for v in got.values())
    print(f"gold {len(got)} / {len(items)} items; confidence {dict(sorted(c.items()))}")

else:
    from pinyin_util import strip_tone
    gold = list(rd(os.path.join(jd, "accuracy-verdicts.tsv")))
    if args.now:
        from plugin_runtime import Plugin
        plugin = Plugin(fallback=("wikt",))
        drawn = {}
        for g in gold:
            r = {x[0]: x for x in plugin.learner(g["sentence"])}.get(int(g["pos"]))
            drawn[g["item"]] = r[2] if r else ""
    else:
        items = {r["item"]: r["id"] for r in rd(os.path.join(d, "accuracy_items.tsv"))}
        by_id = {r["id"]: r["drawn"] for r in rd(os.path.join(d, "sample.tsv"))}
        drawn = {k: by_id[i] for k, i in items.items()}
    share = float(open(os.path.join(d, "polyphone_share.txt")).read().split("\t")[2])
    res = collections.Counter()
    wrong = []
    for g in gold:
        a, b = drawn[g["item"]], g["reading"]
        if b == "?":
            res["unclear"] += 1
        elif a == b:
            res["right"] += 1
        elif "/" in a and b in a.split("/"):
            res["pair"] += 1
        else:
            res["wrong"] += 1
            wrong.append((g["item"], g["char"], a, b, g["confidence"]))
    n = res["right"] + res["pair"] + res["wrong"]
    strict = res["right"] / n
    loose = (res["right"] + res["pair"]) / n
    print(f"{'now' if args.now else 'before'}: {dict(res)}; polyphone accuracy {100 * strict:.1f}% "
          f"(pairs wrong) / {100 * loose:.1f}% (pairs right); polyphone share {100 * share:.1f}%; "
          f"overall {100 * (1 - share * (1 - strict)):.2f}% / {100 * (1 - share * (1 - loose)):.2f}%")
    for w in wrong:
        print("  wrong:", *w)
