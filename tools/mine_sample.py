#!/usr/bin/env python3
"""#35 step 2: sample polyphone occurrences from the reader's books (build/corpus/),
leaving out the held-out books (build/heldout_books.txt) and duplicate copies,
and record learner mode's reading and what decided it.

    mine_sample.py [--heldout] [--cap-top N] [--cap N] OUT_DIR

Polyphones: characters with two or more readings in build/data/reading_shares.tsv.
Each character is capped (reservoir sample) at --cap-top occurrences for the
100 most frequent polyphones in these books, --cap for the others.

Writes OUT_DIR/counts.tsv (char, occurrences in these books, sampled) and
OUT_DIR/sample.tsv (one row per sampled occurrence: id, book, char, sentence,
pos, drawn, dict, source, word, left, right). --heldout samples the held-out
books instead (for step 7)."""
import argparse, collections, csv, glob, os, random, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--heldout", action="store_true")
ap.add_argument("--cap-top", type=int, default=1000)
ap.add_argument("--cap", type=int, default=300)
ap.add_argument("--seed", type=int, default=35)
args = ap.parse_args()
os.makedirs(args.out, exist_ok=True)

poly = set()
for line in open(os.path.join(ROOT, "build/data/reading_shares.tsv"), encoding="utf-8"):
    if line.startswith("#"):
        continue
    f = line.rstrip("\n").split("\t")
    if len(f) >= 3 and len(f[2].split()) >= 2:
        poly.add(f[0])

heldout = {l.split("\t")[0] for l in open(os.path.join(ROOT, "build/heldout_books.txt")) if l.strip()}
books = []
for f in sorted(glob.glob(os.path.join(ROOT, "build/corpus/*.txt"))):
    n = os.path.basename(f)[:-4]
    if not n.isdigit():  # linggao-1/2, zgls-1: duplicates of numbered books
        continue
    if (n in heldout) == args.heldout:
        books.append((n, f))

# Pass 1: counts and a reservoir per character (book, line number, offset).
random.seed(args.seed)
count = collections.Counter()
res = collections.defaultdict(list)
BIG = max(args.cap_top, args.cap)
for n, f in books:
    for ln, line in enumerate(open(f, encoding="utf-8")):
        for off, ch in enumerate(line):
            if ch in poly:
                count[ch] += 1
                r = res[ch]
                if len(r) < BIG:
                    r.append((n, ln, off))
                else:
                    j = random.randrange(count[ch])
                    if j < BIG:
                        r[j] = (n, ln, off)
top = {c for c, _ in count.most_common(100)}
for ch, r in res.items():
    cap = args.cap_top if ch in top else args.cap
    if len(r) > cap:
        res[ch] = random.sample(r, cap)

with open(os.path.join(args.out, "counts.tsv"), "w", encoding="utf-8") as out:
    out.write("char\tcount\tsampled\ttop100\n")
    for ch, c in count.most_common():
        out.write(f"{ch}\t{c}\t{len(res[ch])}\t{int(ch in top)}\n")

# Pass 2: the sentence around each sampled occurrence, and the plugin's reading.
want = collections.defaultdict(list)  # (book, line) -> [(off, char)]
for ch, r in res.items():
    for n, ln, off in r:
        want[(n, ln)].append((off, ch))

END = set("。！？!?；;…\n")
CLOSE = set("”’」』）)》")


def sentence(line, off, width=60):
    s = off
    while s > 0 and line[s - 1] not in END:
        s -= 1
    e = off
    while e < len(line) and line[e] not in END:
        e += 1
    while e < len(line) and (line[e] in END or line[e] in CLOSE) and line[e] != "\n":
        e += 1
    s = max(s, off - width)
    e = min(e, off + width + 1)
    return line[s:e].strip("\n"), off - s


from plugin_runtime import Plugin
plugin = Plugin(fallback=("wikt",))
cache = {}
rows = 0
with open(os.path.join(args.out, "sample.tsv"), "w", encoding="utf-8") as out:
    out.write("id\tbook\tchar\tsentence\tpos\tdrawn\tdict\tsource\tword\tleft\tright\n")
    for n, f in books:
        mine = {ln: v for (b, ln), v in want.items() if b == n}
        if not mine:
            continue
        for ln, line in enumerate(open(f, encoding="utf-8")):
            if ln not in mine:
                continue
            for off, ch in sorted(mine[ln]):
                sent, pos = sentence(line, off)
                if sent not in cache:
                    cache.clear() if len(cache) > 5000 else None
                    cache[sent] = {r[0]: r for r in plugin.learner(sent)}
                r = cache[sent].get(pos)
                if r is None:
                    drawn = dict_ = source = word = left = right = ""
                else:
                    _, _, drawn, dict_, source, word, left, right = r
                rows += 1
                vals = [rows, n, ch, sent.replace("\t", " "), pos, drawn, dict_, source or "", word or "",
                        left or "", right or ""]
                out.write("\t".join(map(str, vals)) + "\n")
print(f"books {len(books)}, polyphones seen {len(count)}, occurrences {sum(count.values())}, sampled {rows}")
