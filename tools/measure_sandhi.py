#!/usr/bin/env python3
"""Measure the spoken tones of 一 and 不 (#37, ch_sandhi.lua) on the corpus.

    tools/measure_sandhi.py scan      every 一/不 in build/corpus/*.txt, per book
                                      (checkpointed: build/sandhi/<book>.tsv)
    tools/measure_sandhi.py counts    how often each rule fires
    tools/measure_sandhi.py sample [--seed N] [--n 100] [--per-rule 25]
                                      judging batches build/judge/sandhi-NNN.tsv
    tools/measure_sandhi.py report    precision per rule from
                                      build/judge/sandhi-verdicts.tsv

Only the sandhi changes are written with context; everything prints summaries.
The plugin resolves each run of Han characters on its own (punctuation and
anything else break words and end the next-syllable rule), so the scan does
the same.
"""
import argparse
import collections
import csv
import glob
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
CORPUS = os.path.join(ROOT, "build", "corpus")
OUT = os.path.join(ROOT, "build", "sandhi")
JUDGE = os.path.join(ROOT, "build", "judge")
VERDICTS = os.path.join(JUDGE, "sandhi-verdicts.tsv")
HAN_RUN = re.compile(r"[㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f]+")
SENTENCE_END = "。！？!?\n"
CONTEXT = 60


def sentence(text, start, end):
    """The sentence around text[start:end], at most CONTEXT characters each side."""
    a = start
    while a > 0 and start - a < CONTEXT and text[a - 1] not in SENTENCE_END:
        a -= 1
    b = end
    while b < len(text) and b - end < CONTEXT and text[b] not in SENTENCE_END:
        b += 1
    if b < len(text) and text[b] in SENTENCE_END and text[b] != "\n":
        b += 1
    return text[a:start], text[start:end], text[end:b]


def scan(args):
    from plugin_runtime import Plugin
    p = Plugin()
    os.makedirs(OUT, exist_ok=True)
    books = sorted(glob.glob(os.path.join(CORPUS, "*.txt")))
    cache = {}
    for path in books:
        book = os.path.splitext(os.path.basename(path))[0]
        dest = os.path.join(OUT, book + ".tsv")
        if os.path.exists(dest):
            continue
        text = open(path, encoding="utf-8").read()
        counts = collections.Counter()
        rows = []
        for m in HAN_RUN.finditer(text):
            run = m.group()
            if "一" not in run and "不" not in run:
                continue
            res = cache.get(run)
            if res is None:
                res = p.spoken(run)
                if len(cache) > 200000:
                    cache.clear()
                cache[run] = res
            for pos, ch, dict_reading, drawn, rule in res:
                counts[(ch, rule or "-")] += 1
                if rule:
                    at = m.start() + pos
                    left, mid, right = sentence(text, at, at + 1)
                    rows.append((book, at, ch, dict_reading, drawn, rule, left, right))
        tmp = dest + ".part"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
            for (ch, rule), n in sorted(counts.items()):
                w.writerow(["#count", ch, rule, n])
            for r in rows:
                w.writerow([x.replace("\t", " ") if isinstance(x, str) else x for x in r])
        os.replace(tmp, dest)
        print(f"{book}: {sum(counts.values())} 一/不, {len(rows)} changed", flush=True)


def load():
    counts = collections.Counter()
    rows = []
    for path in sorted(glob.glob(os.path.join(OUT, "*.tsv"))):
        for r in csv.reader(open(path, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\"):
            if r[0] == "#count":
                counts[(r[1], r[2])] += int(r[3])
            else:
                rows.append(r)
    return counts, rows


def counts_cmd(args):
    counts, rows = load()
    total = collections.Counter()
    for (ch, rule), n in counts.items():
        total[ch] += n
    for ch in "一不":
        print(f"{ch}: {total[ch]} drawn in learner mode")
        for (c, rule), n in sorted(counts.items(), key=lambda kv: -kv[1]):
            if c == ch:
                print(f"  {rule:9} {n:8}  {100 * n / total[ch]:5.1f}%")


def sample(args):
    counts, rows = load()
    rng = random.Random(args.seed)
    held = set(open(os.path.join(ROOT, "build", "sandhi-heldout.txt")).read().split())
    pool = [r for r in rows if r[0] in held and (not args.rules or r[5] in args.rules.split(","))]
    done = set()
    if os.path.exists(VERDICTS):
        for r in csv.reader(open(VERDICTS, encoding="utf-8"), delimiter="\t"):
            if r and r[0] != "id":
                done.add(r[0])
    picked = rng.sample(pool, min(args.n, len(pool)))
    by_rule = collections.defaultdict(list)
    for r in pool:
        by_rule[r[5]].append(r)
    for rule, items in by_rule.items():
        have = sum(1 for r in picked if r[5] == rule)
        extra = [r for r in items if r not in picked and f"{r[0]}:{r[1]}" not in done]
        rng.shuffle(extra)
        picked += extra[:max(0, args.per_rule - have)]
    os.makedirs(JUDGE, exist_ok=True)
    existing = sorted(glob.glob(os.path.join(JUDGE, "sandhi-[0-9][0-9][0-9].tsv")))
    start = len(existing)
    batch, k = [], 0
    written = 0
    for r in picked:
        ident = f"{r[0]}:{r[1]}"
        if ident in done:
            continue
        batch.append([ident, r[2], r[3], r[4], r[6], r[2], r[7], r[5]])
        if len(batch) == 25:
            write_batch(start + k, batch)
            k += 1
            written += len(batch)
            batch = []
    if batch:
        write_batch(start + k, batch)
        k += 1
        written += len(batch)
    print(f"{written} items in {k} batches from {len(pool)} changed occurrences in {len(held)} held-out books")


def write_batch(n, batch):
    path = os.path.join(JUDGE, f"sandhi-{n:03d}.tsv")
    with open(path, "w", encoding="utf-8") as f:
        f.write("id\tchar\tdictionary\tdrawn\tleft\ttarget\tright\n")
        for b in batch:
            f.write("\t".join(b[:7]) + "\n")
    # the rule stays out of the judge's file
    with open(path + ".rules", "w", encoding="utf-8") as f:
        for b in batch:
            f.write(f"{b[0]}\t{b[7]}\n")


def merge_verdicts():
    """Each judge writes sandhi-NNN.verdicts.tsv; gather them into VERDICTS."""
    rows, seen = [], set()
    for path in sorted(glob.glob(os.path.join(JUDGE, "sandhi-[0-9][0-9][0-9].verdicts.tsv"))):
        for r in csv.reader(open(path, encoding="utf-8"), delimiter="\t"):
            if r and r[0] != "id" and r[0] not in seen:
                seen.add(r[0])
                rows.append(r)
    with open(VERDICTS, "w", encoding="utf-8") as f:
        f.write("id\tverdict\tconfidence\tshould_be\tnote\n")
        for r in rows:
            f.write("\t".join(r) + "\n")


def report(args):
    merge_verdicts()
    rules = {}
    for path in glob.glob(os.path.join(JUDGE, "sandhi-*.tsv.rules")):
        for line in open(path, encoding="utf-8"):
            ident, rule = line.rstrip("\n").split("\t")
            rules[ident] = rule
    stats = collections.defaultdict(collections.Counter)
    wrong = []
    for r in csv.reader(open(VERDICTS, encoding="utf-8"), delimiter="\t"):
        if not r or r[0] == "id" or r[0] not in rules:
            continue
        verdict = r[1].strip().lower()
        stats[rules[r[0]]][verdict] += 1
        if verdict == "wrong":
            wrong.append((rules[r[0]], r))
    for rule, c in sorted(stats.items()):
        judged = c["right"] + c["wrong"]
        prec = 100 * c["right"] / judged if judged else 0
        print(f"{rule:9} right {c['right']:3}  wrong {c['wrong']:3}  unclear {c['unclear']:3}  precision {prec:5.1f}%")
    if args.wrong:
        for rule, r in wrong:
            print(rule, "\t".join(r))


def recheck(args):
    """Every judged row, re-run through the current rules: a verdict counts
    where the drawn reading is unchanged; a changed one is right when it is
    now what the judge said it should be, wrong otherwise. Precision per
    rule the current code applies (rows it no longer changes drop out)."""
    from plugin_runtime import Plugin
    p = Plugin()
    merge_verdicts()
    batches = {}
    for path in glob.glob(os.path.join(JUDGE, "sandhi-[0-9][0-9][0-9].tsv")):
        for r in csv.reader(open(path, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE):
            if r and r[0] != "id":
                batches[r[0]] = r
    stats = collections.defaultdict(collections.Counter)
    wrong = []
    for v in csv.reader(open(VERDICTS, encoding="utf-8"), delimiter="\t"):
        if not v or v[0] == "id" or v[0] not in batches:
            continue
        ident, ch, _, drawn, left, target, right = batches[ident := v[0]][:7]
        lm = re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]*$", left).group()
        rm = re.match(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]*", right).group()
        now = [x for x in p.spoken(lm + target + rm) if x[0] == len(lm)]
        if not now or not now[0][4]:
            continue
        rule, current = now[0][4], now[0][3]
        verdict, should = v[1].strip(), (v[3].strip() if len(v) > 3 else "")
        if verdict == "unclear":
            stats[rule]["unclear"] += 1
        elif current == drawn:
            stats[rule][verdict] += 1
            if verdict == "wrong":
                wrong.append((rule, ident, current, should, lm + "【" + target + "】" + rm))
        elif verdict == "wrong" and should == current:
            stats[rule]["right"] += 1
        else:
            stats[rule]["wrong"] += 1
            wrong.append((rule, ident, current, should or drawn, lm + "【" + target + "】" + rm))
    for rule, c in sorted(stats.items()):
        judged = c["right"] + c["wrong"]
        print(f"{rule:9} right {c['right']:3}  wrong {c['wrong']:3}  unclear {c['unclear']:3}  "
              f"precision {100 * c['right'] / judged:5.1f}%")
    if args.wrong:
        for w in wrong:
            print(*w)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scan")
    sub.add_parser("counts")
    s = sub.add_parser("sample")
    s.add_argument("--seed", type=int, default=37)
    s.add_argument("--n", type=int, default=100)
    s.add_argument("--per-rule", type=int, default=25)
    s.add_argument("--rules", default="", help="only these rules, comma-separated")
    r = sub.add_parser("report")
    r.add_argument("--wrong", action="store_true")
    rc = sub.add_parser("recheck")
    rc.add_argument("--wrong", action="store_true")
    args = ap.parse_args()
    {"scan": scan, "counts": counts_cmd, "sample": sample, "report": report, "recheck": recheck}[args.cmd](args)


if __name__ == "__main__":
    main()
