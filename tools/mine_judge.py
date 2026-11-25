#!/usr/bin/env python3
"""#35 step 5: judging batches from mine_patterns.py's output, and the summary of
what is left to context (for #39).

    mine_judge.py DIR [--top 200] [--per 25]

Items (build/judge/mining-NNN.tsv, see build/judge/MINING-INSTRUCTIONS.md):
  decided  the top --top disagreement patterns decided by a word, special word,
           fallback word or rule;
  default  one per character whose undecided occurrences (default, or the first
           reading of the pair) g2pW reads as one other reading in the majority.
Writes DIR/undecided.tsv (undecided disagreement patterns by char, plugin, g2pw)
and DIR/default_shares.tsv; existing batch files are left alone."""
import argparse, collections, csv, os, random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("dir")
ap.add_argument("--top", type=int, default=200)
ap.add_argument("--per", type=int, default=25)
ap.add_argument("--contexts", type=int, default=6)
args = ap.parse_args()
d = args.dir
csv.field_size_limit(1 << 20)
random.seed(35)

DECIDED = ("word", "special", "fallback", "rule")
rows = list(csv.DictReader(open(os.path.join(d, "compared.tsv"), encoding="utf-8"), delimiter="\t",
                           quoting=csv.QUOTE_NONE))


def ctx(r):
    s, p = r["sentence"], int(r["pos"])
    return (s[:p] + "【" + s[p] + "】" + s[p + 1:]).replace("\t", " ").replace("｜", "|")


by_pat = collections.defaultdict(list)
for r in rows:
    if r["category"] == "disagree":
        by_pat[(r["char"], r["drawn"], r["g2pw"], r["source"], r["decider"])].append(r)


def est(rs):
    return sum(float(r["weight"]) for r in rs)


items = []
decided = sorted(((k, v) for k, v in by_pat.items() if k[3] in DECIDED), key=lambda kv: -est(kv[1]))
for (ch, a, b, src, dec), rs in decided[:args.top]:
    ex = random.sample(rs, min(args.contexts, len(rs)))
    items.append(["decided", ch, a, b, f"{src}:{dec}", f"{est(rs):.0f}", " ｜ ".join(map(ctx, ex))])

# Undecided occurrences: g2pW's reading against the default.
und = collections.defaultdict(list)
for r in rows:
    if r["source"] in ("default", "pair") and r["category"] != "uncovered":
        und[r["char"]].append(r)
with open(os.path.join(d, "default_shares.tsv"), "w", encoding="utf-8") as out:
    out.write("char\tdefault\tundecided_est\tcovered_sampled\tg2pw_top\tg2pw_top_share\tdisagree_share\n")
    for ch, rs in sorted(und.items(), key=lambda kv: -est(kv[1])):
        default = rs[0]["drawn"].split("/")[0]
        w = est(rs)
        other = collections.Counter()
        dis = 0.0
        for r in rs:
            g = r["g2pw"]
            if g != default and r["category"] != "neutral":
                dis += float(r["weight"])
                other[g] += float(r["weight"])
        top, tw = (other.most_common(1)[0] if other else ("", 0.0))
        out.write(f"{ch}\t{default}\t{w:.0f}\t{len(rs)}\t{top}\t{tw / w:.3f}\t{dis / w:.3f}\n")
        if w and tw / w > 0.5 and len(rs) >= 3:
            ex = [r for r in rs if r["g2pw"] == top]
            ex = random.sample(ex, min(args.contexts, len(ex)))
            items.append(["default", ch, rs[0]["drawn"], top, "", f"{w:.0f}", " ｜ ".join(map(ctx, ex))])

# Undecided disagreement patterns, for #39.
up = collections.Counter()
upn = collections.Counter()
for (ch, a, b, src, dec), rs in by_pat.items():
    if src in ("default", "pair"):
        up[(ch, a, b, src)] += est(rs)
        upn[(ch, a, b, src)] += len(rs)
with open(os.path.join(d, "undecided.tsv"), "w", encoding="utf-8") as out:
    out.write("char\tplugin\tg2pw\tsource\test\tsampled\n")
    for k, w in up.most_common():
        out.write("\t".join(k) + f"\t{w:.0f}\t{upn[k]}\n")

jd = os.path.join(ROOT, "build/judge")
n = 0
for k in range(0, len(items), args.per):
    p = os.path.join(jd, f"mining-{k // args.per:03d}.tsv")
    n += 1
    if os.path.exists(p):
        continue
    with open(p, "w", encoding="utf-8") as out:
        out.write("item\tkind\tchar\tplugin\tg2pw\tdecider\test\tcontexts\n")
        for j, it in enumerate(items[k:k + args.per]):
            out.write(f"m{k + j:04d}\t" + "\t".join(it) + "\n")
print(f"items {len(items)} (decided {min(args.top, len(decided))}, default {len(items) - min(args.top, len(decided))}), "
      f"batches {n}; undecided disagreement est {sum(up.values()):.0f} in {len(up)} patterns")
