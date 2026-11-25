#!/usr/bin/env python3
"""#35 step 3: g2pW's reading for each row of a mine_sample.py sample.

    mine_g2pw.py DIR [--threads 8]   (reads DIR/sample.tsv, appends DIR/g2pw.tsv: id, g2pw reading)

Runs g2pW's model on the sampled position only (g2pW's own converter runs it once
for every polyphone in the sentence, about ten times the work), in chunks,
appending as it goes: rerunning resumes after the last finished chunk. Readings
are tone-marked (tools/pinyin_util.py); empty when the character is not one of
g2pW's polyphones (CPP's), since its reading for any other character is a fixed
lookup, not a prediction. g2pW gives 一 and 不 their spoken tones."""
import argparse, csv, os, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from pinyin_util import numbered_to_marked

ap = argparse.ArgumentParser()
ap.add_argument("dir")
ap.add_argument("--threads", type=int, default=8)
ap.add_argument("--chunk", type=int, default=4096)
ap.add_argument("--batch", type=int, default=128)
args = ap.parse_args()
d = args.dir
csv.field_size_limit(1 << 20)
rows = list(csv.DictReader(open(os.path.join(d, "sample.tsv"), encoding="utf-8"), delimiter="\t",
                           quoting=csv.QUOTE_NONE))
outp = os.path.join(d, "g2pw.tsv")
done = set()
if os.path.exists(outp):
    for line in open(outp, encoding="utf-8"):
        done.add(line.split("\t")[0])

import onnxruntime
from g2pw import G2PWConverter
from g2pw.dataset import TextDataset

mdir = os.path.join(ROOT, "build/g2pw/G2PWModel/")
conv = G2PWConverter(model_dir=mdir, style="pinyin", enable_non_tradional_chinese=True)
so = onnxruntime.SessionOptions()
so.graph_optimization_level = onnxruntime.GraphOptimizationLevel.ORT_ENABLE_ALL
so.intra_op_num_threads = args.threads
sess = onnxruntime.InferenceSession(os.path.join(mdir, "g2pw.onnx"), sess_options=so)
poly = set(conv.chars)
cfg = conv.config

todo, empty = [], []
for r in rows:
    if r["id"] in done:
        continue
    t = conv._convert_s2t(r["sentence"])
    p = int(r["pos"])
    (todo if p < len(t) and t[p] in poly else empty).append((r["id"], t, p))
print(f"{len(rows)} rows, {len(done)} done, {len(todo)} to run, {len(empty)} not g2pW polyphones",
      flush=True)

out = open(outp, "a", encoding="utf-8")
out.write("".join(f"{rid}\t\n" for rid, _, _ in empty))
out.flush()
t0 = time.time()
for k in range(0, len(todo), args.chunk):
    chunk = todo[k:k + args.chunk]
    ds = TextDataset(conv.tokenizer, conv.labels, conv.char2phonemes, conv.chars,
                     [t for _, t, _ in chunk], [p for _, _, p in chunk],
                     use_mask=cfg.use_mask, use_char_phoneme=cfg.use_char_phoneme,
                     window_size=cfg.window_size, for_train=False)
    preds = []
    for b in range(0, len(ds), args.batch):
        data = ds.create_mini_batch([ds[i] for i in range(b, min(b + args.batch, len(ds)))])
        probs = sess.run([], {n: data[n].numpy() for n in (
            "input_ids", "token_type_ids", "attention_mask", "phoneme_mask", "char_ids", "position_ids")})[0]
        preds += [conv.labels[i] for i in probs.argmax(-1).tolist()]
    lines = []
    for (rid, _, _), pred in zip(chunk, preds):
        if cfg.use_char_phoneme:
            pred = pred.split(" ")[1]
        x = conv.style_convert_func(pred)
        lines.append(f"{rid}\t{numbered_to_marked(x) if x else ''}\n")
    out.write("".join(lines))
    out.flush()
    n = k + len(chunk)
    print(f"{n}/{len(todo)}, {n / (time.time() - t0):.1f}/s", flush=True)
print("done", flush=True)
