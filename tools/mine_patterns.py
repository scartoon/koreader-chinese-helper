#!/usr/bin/env python3
"""#35 steps 3-4: compare learner mode with g2pW over a mine_sample.py sample
and group the disagreements into patterns, weighted by corpus frequency.

    mine_patterns.py DIR     (DIR/sample.tsv, DIR/g2pw.tsv, DIR/counts.tsv)

Each occurrence falls in one category:
  uncovered   g2pW gives no reading (not one of CPP's polyphones)
  agree       same reading
  pair-has    learner mode draws the pair (de/děi) and g2pW picks one of them
  neutral     same letters, one side neutral and the other toned (CPP labels
              some neutral tones with the full tone: not a disagreement)
  disagree    anything else
Weights: each sampled occurrence stands for count/sampled occurrences of its
character in these books.

Writes DIR/compared.tsv (every row with its category and weight),
DIR/mining_patterns.tsv (disagreement patterns: char, plugin, g2pw, source,
decider, est. occurrences, sampled, example) and prints a summary."""
import collections, csv, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from pinyin_util import strip_tone, is_toneless

d = sys.argv[1]
csv.field_size_limit(1 << 20)
rd = lambda name: csv.DictReader(open(os.path.join(d, name), encoding="utf-8"), delimiter="\t",
                                 quoting=csv.QUOTE_NONE)
weight = {}
for r in rd("counts.tsv"):
    if int(r["sampled"]):
        weight[r["char"]] = int(r["count"]) / int(r["sampled"])
g2 = {}
for line in open(os.path.join(d, "g2pw.tsv"), encoding="utf-8"):
    rid, x = line.rstrip("\n").split("\t")
    g2[rid] = x

rules = collections.defaultdict(dict)  # (char, side, neighbour) -> reading
for line in open(os.path.join(ROOT, "data/rules.tsv"), encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    f = line.rstrip("\n").split("\t")
    rules[(f[0], f[1], f[2])] = f[3]


def category(drawn, g):
    if not g:
        return "uncovered"
    if drawn == g:
        return "agree"
    if "/" in drawn:
        return "pair-has" if g in drawn.split("/") else "disagree"
    if strip_tone(drawn) == strip_tone(g) and (is_toneless(drawn) or is_toneless(g)):
        return "neutral"
    return "disagree"


def decider(r):
    s = r["source"]
    if s in ("word", "special", "fallback"):
        return r["word"]
    if s == "rule":
        for side, nb in (("L", r["left"]), ("R", r["right"])):
            if nb and rules.get((r["char"], side, nb)) == r["dict"]:
                return f"{side}:{nb}"
        return "rule?"
    return ""


cats = collections.Counter()
cats_by_src = collections.defaultdict(collections.Counter)
pat = collections.defaultdict(lambda: [0.0, 0, None])
missing = 0
with open(os.path.join(d, "compared.tsv"), "w", encoding="utf-8") as out:
    out.write("id\tchar\tpos\tdrawn\tg2pw\tsource\tdecider\tcategory\tweight\tsentence\n")
    for r in rd("sample.tsv"):
        if r["id"] not in g2:
            missing += 1
            continue
        if not r["drawn"]:
            continue
        w = weight[r["char"]]
        c = category(r["drawn"], g2[r["id"]])
        dec = decider(r)
        src = r["source"] or "-"
        cats[c] += w
        cats_by_src[src][c] += w
        out.write("\t".join([r["id"], r["char"], r["pos"], r["drawn"], g2[r["id"]], src, dec, c,
                             f"{w:.3f}", r["sentence"]]) + "\n")
        if c == "disagree":
            p = pat[(r["char"], r["drawn"], g2[r["id"]], src, dec)]
            p[0] += w
            p[1] += 1
            if p[2] is None:
                pos = int(r["pos"])
                s = r["sentence"]
                p[2] = s[max(0, pos - 12):pos] + "【" + s[pos] + "】" + s[pos + 1:pos + 13]

rows = sorted(pat.items(), key=lambda kv: -kv[1][0])
with open(os.path.join(d, "mining_patterns.tsv"), "w", encoding="utf-8") as out:
    out.write("char\tplugin\tg2pw\tsource\tdecider\test\tsampled\texample\n")
    for (ch, a, b, src, dec), (w, n, ex) in rows:
        out.write(f"{ch}\t{a}\t{b}\t{src}\t{dec}\t{w:.0f}\t{n}\t{ex}\n")

tot = sum(cats.values())
covered = tot - cats["uncovered"]
print(f"missing g2pW rows: {missing}")
print("est. occurrences by category (share of covered):")
for c, w in cats.most_common():
    print(f"  {c:10s} {w:12.0f}  {100 * w / covered:6.2f}%" if c != "uncovered" else f"  {c:10s} {w:12.0f}")
print("disagreements by source (est., share of that source's covered):")
for src, cc in sorted(cats_by_src.items(), key=lambda kv: -kv[1]["disagree"]):
    cov = sum(cc.values()) - cc["uncovered"]
    if cov:
        print(f"  {src:9s} {cc['disagree']:10.0f} / {cov:10.0f}  {100 * cc['disagree'] / cov:5.2f}%")
print(f"patterns: {len(rows)}; top 20:")
for (ch, a, b, src, dec), (w, n, ex) in rows[:20]:
    print(f"  {w:8.0f} {n:4d} {ch} {a} -> {b} [{src} {dec}]")
