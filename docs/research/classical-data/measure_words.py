"""#66: classical word senses and the popup's word list, on the #49 sample.

    .venv/bin/python docs/research/classical-data/measure_words.py ROOT

ROOT is the main checkout (build/ and the release database live there).
Writes build/classical/words/:
  literary_words.tsv   word senses (2+ characters) from Chinese Notes'
                       Literary Chinese domain and Wiktionary's literary,
                       Classical, archaic, obsolete or historical senses
  taps.txt             for each sampled tap: the popup's word list (every
                       CC-CEDICT word of 2-8 characters in the Han run around
                       the tap that contains it, as ch_text.lua's
                       Text.candidates), each with its CC-CEDICT senses and
                       its literary senses; plus literary words there that
                       CC-CEDICT doesn't have (the popup shows none of them)
  corpus.tsv           over all 17 texts: every distinct word in a Han run
                       that is a CC-CEDICT or literary word, with counts
"""
import collections, csv, gzip, json, os, re, sqlite3, sys

ROOT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "build", "sources")
OUT = os.path.join(ROOT, "build", "classical", "words")
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
MAX_WORD = 8
sys.path.insert(0, os.path.join(ROOT, "tools"))
import collate_classical as collate  # noqa: E402

HAN = re.compile(r"[㐀-鿿\U00020000-\U0003ffff]")


def han_all(w):
    return len(w) >= 2 and all(HAN.match(c) for c in w)


def literary_words():
    path = os.path.join(OUT, "literary_words.tsv")
    if os.path.exists(path):
        by = collections.defaultdict(list)
        for r in csv.DictReader(open(path), delimiter="\t"):
            by[r["trad"]].append(r)
        return by
    rows = []
    for line in open(os.path.join(SRC, "chinesenotes", "cnotes_zh_en_dict.tsv")):
        if line.startswith("#"):
            continue
        r = line.rstrip("\n").split("\t")
        simp, trad = r[1], (r[2] if r[2] != "\\N" else r[1])
        if not han_all(simp) or r[9] != "Literary Chinese" or r[4] in ("\\N", ""):
            continue
        rows.append(dict(trad=trad, simp=simp, source="cn", reading=r[3], sense=r[4]))
    for line in gzip.open(os.path.join(SRC, "wiktionary", "kaikki-Chinese.jsonl.gz"), "rt"):
        e = json.loads(line)
        w = e.get("word", "")
        if not han_all(w):
            continue
        for s in e.get("senses", []):
            tags = set(s.get("tags", []))
            raw = " ".join(s.get("raw_glosses") or s.get("glosses") or [])
            gl = "; ".join(s.get("glosses") or [])
            if not gl or tags & collate.DIALECT or "alt-of" in tags or collate.ALT.match(gl) or \
                    re.search(r"\b(Korean|Japanese|Vietnamese)\b", raw):
                continue
            if tags & collate.WIKT_TAGS or "Classical Chinese" in raw or "obsolete on its own" in raw:
                trad = collate.s2t.convert(w) if w == collate.t2s.convert(w) else w
                rows.append(dict(trad=trad, simp=collate.t2s.convert(w), source="wikt",
                                 reading=collate.wikt_reading(e), sense=raw.strip()))
    os.makedirs(OUT, exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, ["trad", "simp", "source", "reading", "sense"], delimiter="\t")
        w.writeheader()
        w.writerows(rows)
    return literary_words()


def cedict_words():
    out = collections.defaultdict(list)
    for simp, trad, pinyin, defs in sqlite3.connect(DB).execute(
            "SELECT simp, trad, pinyin, defs FROM entries WHERE length(simp) >= 2"):
        out[trad].append(f"{pinyin} {defs}")
        if simp != trad:
            out.setdefault(simp, out[trad])
    return out


def fallback_words():
    """Words the popup shows from the bundled fallbacks (Wiktionary, Wikipedia
    titles): CC-CEDICT lacks every one of them."""
    out = collections.defaultdict(list)
    for simp, trad, pinyin, defs, src in sqlite3.connect(DB).execute(
            "SELECT simp, trad, pinyin, defs, source FROM fallback WHERE length(simp) >= 2"):
        for w in {simp, trad}:
            out[w].append(f"[{src}] {pinyin} {defs}")
    return out


def runs(text):
    return [m.group(0) for m in re.finditer(r"[㐀-鿿\U00020000-\U0003ffff]+", text)]


def candidates(run, t):
    """Substrings of run containing position t, 2..MAX_WORD long (Text.candidates)."""
    out = []
    for i in range(max(0, t - MAX_WORD + 1), t + 1):
        for j in range(t + 1, min(len(run), i + MAX_WORD)):
            w = run[i:j + 1]
            if len(w) >= 2 and w not in out:
                out.append(w)
    return out


def main():
    lit = literary_words()
    ced = cedict_words()
    fb = fallback_words()
    nlit = sum(len(v) for v in lit.values())
    print(f"literary word senses: {nlit} on {len(lit)} words "
          f"(cn {sum(1 for v in lit.values() for r in v if r['source'] == 'cn')}, "
          f"wikt {sum(1 for v in lit.values() for r in v if r['source'] == 'wikt')})")
    samp = list(csv.DictReader(open(os.path.join(HERE, "sample.tsv")), delimiter="\t"))
    judg = {j["id"]: j for j in csv.DictReader(open(os.path.join(HERE, "judgments.tsv")), delimiter="\t")}
    with open(os.path.join(OUT, "taps.txt"), "w") as f:
        for s in samp:
            if judg[s["id"]]["status"] == "excl":
                continue
            ctx = s["context"]
            left, rest = ctx.split("【", 1)
            ch, right = rest.split("】", 1)
            lrun = re.search(r"[㐀-鿿]*$", left).group(0)[-(MAX_WORD - 1):]
            rrun = re.match(r"[㐀-鿿]*", right).group(0)[:MAX_WORD - 1]
            run = lrun + ch + rrun
            cands = candidates(run, len(lrun))
            listed = [w for w in cands if w in ced or w in fb]
            litonly = [w for w in cands if w in lit and w not in ced and w not in fb]
            f.write(f"\n## {s['id']} {ch} [{judg[s['id']]['status']}] {left[-12:]}【{ch}】{right[:12]}\n")
            for w in listed:
                if w in ced:
                    f.write(f"  {w}: CEDICT {' | '.join(ced[w])[:150]}\n")
                else:
                    f.write(f"  {w}: fallback {' | '.join(dict.fromkeys(fb[w]))[:150]}\n")
                for r in (lit.get(w, []) if w in ced else []):
                    f.write(f"      {r['source']}: {r['sense'][:120]}\n")
            for w in litonly:
                f.write(f"  {w} (not shown: in no bundled dictionary)\n")
                for r in lit[w]:
                    f.write(f"      {r['source']}: {r['sense'][:120]}\n")
    # Corpus: every distinct CC-CEDICT or literary word of 2+ characters in the texts.
    cnt = collections.Counter()
    for name in sorted(os.listdir(os.path.join(ROOT, "build", "classical", "texts"))):
        text = open(os.path.join(ROOT, "build", "classical", "texts", name)).read()
        text = "\n".join(l for l in text.split("\n") if not l.startswith("#"))
        for run in runs(text):
            for i in range(len(run)):
                for j in range(i + 2, min(len(run), i + MAX_WORD) + 1):
                    w = run[i:j]
                    if w in ced or w in lit or w in fb:
                        cnt[w] += 1
    with open(os.path.join(OUT, "corpus.tsv"), "w") as f:
        f.write("word\tcount\tcedict\tfallback\tliterary\n")
        for w, n in cnt.most_common():
            f.write(f"{w}\t{n}\t{int(w in ced)}\t{int(w in fb)}\t{int(w in lit)}\n")
    print(f"corpus: {len(cnt)} distinct words; in CC-CEDICT {sum(1 for w in cnt if w in ced)}, "
          f"fallback only {sum(1 for w in cnt if w in fb and w not in ced)}, literary {sum(1 for w in cnt if w in lit)}; "
          f"CC-CEDICT words with literary senses {sum(1 for w in cnt if w in ced and w in lit)}; "
          f"literary words in no bundled dictionary {sum(1 for w in cnt if w in lit and w not in ced and w not in fb)}")


main()
