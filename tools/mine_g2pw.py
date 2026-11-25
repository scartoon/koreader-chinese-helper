#!/usr/bin/env python3
"""#35 step 3: g2pW's reading for each row of a mine_sample.py sample.

    mine_g2pw.py DIR      (reads DIR/sample.tsv, appends DIR/g2pw.tsv: id, g2pw reading)

Runs each distinct sentence once, in batches, appending as it goes: rerunning
resumes after the last finished batch. Readings are tone-marked
(tools/pinyin_util.py); empty when g2pW has no reading for the character (it
covers only CPP's polyphones). g2pW gives 一 and 不 their spoken tones."""
import collections, csv, os, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from pinyin_util import numbered_to_marked

d = sys.argv[1]
csv.field_size_limit(1 << 20)
rows = list(csv.DictReader(open(os.path.join(d, "sample.tsv"), encoding="utf-8"), delimiter="\t",
                           quoting=csv.QUOTE_NONE))
outp = os.path.join(d, "g2pw.tsv")
done = set()
if os.path.exists(outp):
    for line in open(outp, encoding="utf-8"):
        done.add(line.split("\t")[0])
by_sent = collections.defaultdict(list)
for r in rows:
    if r["id"] not in done:
        by_sent[r["sentence"]].append((r["id"], int(r["pos"])))
sents = list(by_sent)
print(f"{len(rows)} rows, {len(done)} done, {len(sents)} sentences to run", flush=True)

from g2pw import G2PWConverter
conv = G2PWConverter(model_dir=os.path.join(ROOT, "build/g2pw/G2PWModel/"), style="pinyin",
                     enable_non_tradional_chinese=True)
conv.num_workers = 0
B = 256
t0 = time.time()
with open(outp, "a", encoding="utf-8") as out:
    for k in range(0, len(sents), B):
        batch = sents[k:k + B]
        try:
            res = conv(batch)
        except Exception as e:  # one bad sentence: run the batch one by one
            res = []
            for s in batch:
                try:
                    res.append(conv([s])[0])
                except Exception:
                    res.append([None] * len(s))
        lines = []
        for s, p in zip(batch, res):
            for rid, pos in by_sent[s]:
                x = p[pos] if pos < len(p) else None
                lines.append(f"{rid}\t{numbered_to_marked(x) if x else ''}\n")
        out.write("".join(lines))
        out.flush()
        if (k // B) % 20 == 0:
            n = k + len(batch)
            print(f"{n}/{len(sents)} sentences, {n / (time.time() - t0):.1f}/s", flush=True)
print("done", flush=True)
