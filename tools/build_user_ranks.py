#!/usr/bin/env python3
"""Character frequency ranks counted from your own books (#42), for the
plugin's "Frequency ranks: From my books" setting.

    python3 tools/fetch_books.py                    # first, and when your library changes
    python3 tools/build_user_ranks.py               # build/corpus/ -> build/user-ranks.tsv
    python3 tools/build_user_ranks.py --epubs DIR   # or a folder of EPUBs on this computer
    python3 tools/build_user_ranks.py --push        # copy the existing file to the device

The bundled ranks (wordfreq's for Chinese: web, Google Books, news,
subtitles, Wikipedia, Twitter, Jieba) decide which characters get pinyin, the
popup's 字频 line and which pinyin is dropped first on a crowded line. This ranks characters by what you
read instead:

  * spread first: the number of *works* a character occurs in, then its total
    occurrences, then its bundled rank. One long novel's cast of names cannot
    push rare name characters into the top few thousand.
  * a work is a book, not a file: the NAME-<k> files of one
    `fetch_books.py --local NAME` run are one work; device books whose titles
    differ only by a volume number (临高启明 第七卷 / 临高启明六卷) are one
    work; a text that is (mostly) a copy of another file's counts once, with
    the larger copy. build/user-ranks-works.tsv (file <TAB> work, `#`
    comments) overrides the grouping by hand.
  * traditional characters count as their simplified form, and 〇 as 零, as
    tools/build_data.py ranks them; the file lists the traditional forms with
    their simplified form's rank too. Only characters the plugin has a
    reading for are ranked.

Characters absent from the books are not listed: the plugin gives them their
bundled rank. Ranks past the exact cut-off in the header are too thin to tell
apart (fewer than EXACT_MIN_WORKS works); the popup shows them as "N+".

build/user-ranks.tsv:
    # chinesehelper user ranks
    # date <TAB> 2026-11-19
    # works <TAB> 45
    # han <TAB> 31234567          (Han characters counted)
    # ranked <TAB> 6789           (distinct characters ranked)
    # exact <TAB> 4300            (ranks up to here are exact)
    char <TAB> rank <TAB> works <TAB> occurrences

The tool never reads from the device; --push only copies the file already
built (KOReader's settings folder, next to the reading marks file, so plugin
updates and reinstalls keep it). The books are yours: everything stays in
build/ (git-ignored).
"""
import argparse
import datetime
import os
import re
import sqlite3
import subprocess
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

CORPUS = os.path.join(ROOT, "build", "corpus")
OUT = os.path.join(ROOT, "build", "user-ranks.tsv")
WORKS_OVERRIDE = os.path.join(ROOT, "build", "user-ranks-works.tsv")
GROUPING_OUT = os.path.join(ROOT, "build", "user-ranks-works-chosen.tsv")
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")

# On the device: KOReader's settings folder (ch_marks.lua's marks file is there).
DEVICE_PATH = "/sdcard/koreader/settings/chinesehelper_ranks.tsv"
DEVICE_NAME = "chinesehelper_ranks.tsv"

HAN_RE = re.compile(r"[㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f〇]")

# Exact ranks: characters seen in at least this many works (fewer when the
# library has fewer works).
EXACT_MIN_WORKS = 3
# Copies: a file whose 8-character shingles (after an anchor character) are at least this share
# contained in another file is the same text.
SHINGLE = 8
ANCHOR_RE = re.compile(r"[的了是](.{%d})" % SHINGLE)
COPY_CONTAINMENT = 0.5
REPORT_CONTAINMENT = 0.1

CN_DIGITS = "〇零一二三四五六七八九十百两"
VOLUME_RES = [
    re.compile(r"第\s*[" + CN_DIGITS + r"0-9]+\s*[卷册部集篇]"),
    re.compile(r"[卷册部集]\s*[" + CN_DIGITS + r"0-9]+"),
    re.compile(r"[" + CN_DIGITS + r"0-9]+\s*[卷册部集]"),
    re.compile(r"[（(]\s*[上中下" + CN_DIGITS + r"0-9]+\s*[）)]"),
    re.compile(r"\b(?:vol(?:ume)?|book|part)\.?\s*[0-9ivx]+\b", re.I),
    re.compile(r"[\s_:,，-]*[0-9]+\s*$"),
    re.compile(r"[上中下]$"),
]


# ----------------------------------------------------------------------
# Bundled ranks and the traditional -> simplified mapping (from the
# plugin's own database, so this matches what the plugin shows)
# ----------------------------------------------------------------------

class Public:
    """public[ch]: bundled rank (0 = unranked) of every character the plugin
    has a reading for; key(ch): the character its occurrences count as."""

    def __init__(self, ranks, t2s):
        self.rank = ranks
        self.t2s = t2s

    @classmethod
    def from_db(cls, path=DB):
        if not os.path.exists(path):
            sys.exit(f"no plugin database at {path}: take it from the latest release zip (see CLAUDE.md)")
        con = sqlite3.connect(path)
        ranks = {ch: r for ch, r in con.execute("SELECT ch, rank FROM chars")}
        counts = defaultdict(Counter)
        simplified = set()
        for simp, trad in con.execute("SELECT simp, trad FROM entries"):
            if len(simp) != len(trad):
                continue
            simplified.update(simp)
            for t, s in zip(trad, simp):
                if t != s:
                    counts[t][s] += 1
        con.close()
        return cls(ranks, cls.mapping(ranks, counts, simplified))

    @staticmethod
    def mapping(ranks, counts, simplified):
        """t -> s as build_data.py's rank_of: a traditional character takes the
        rank of its most common simplified form when it is not ranked in its
        own right. Ranked: its rank equals s's (ranks are unique). Unranked:
        when it is never a simplified form itself."""
        t2s = {}
        for t, c in counts.items():
            s = c.most_common(1)[0][0]
            rt, rs = ranks.get(t), ranks.get(s)
            if rt is None or rs is None:
                continue
            if (rt > 0 and rt == rs) or (rt == 0 and rs == 0 and t not in simplified):
                t2s[t] = s
        return t2s

    def key(self, ch):
        if ch == "〇":
            ch = "零"
        return self.t2s.get(ch, ch)

    def sort_rank(self, ch):
        r = self.rank.get(ch, 0)
        return r if r > 0 else float("inf")

    def forms(self):
        """simplified -> its traditional forms (characters that count as it)."""
        out = defaultdict(list)
        for t, s in self.t2s.items():
            out[s].append(t)
        if "〇" in self.rank:
            out["零"].append("〇")
        return out


# ----------------------------------------------------------------------
# Files and works
# ----------------------------------------------------------------------

def read_index(corpus):
    """[(file key, device/display name)] of the kept books in index.tsv; any
    .txt file not in it is listed under its own name."""
    rows, seen = [], set()
    path = os.path.join(corpus, "index.tsv")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8").read().splitlines()[1:]:
            parts = line.split("\t")
            if len(parts) >= 5 and parts[3] == "1" and os.path.exists(os.path.join(corpus, parts[0] + ".txt")):
                rows.append((parts[0], parts[4]))
                seen.add(parts[0])
    for name in sorted(os.listdir(corpus)):
        if name.endswith(".txt") and name[:-4] not in seen:
            rows.append((name[:-4], name[:-4]))
    return rows


def title_stem(name):
    """The title with any volume number taken off: 临高启明 第七卷 7 -- 吹牛者
    -- ... -> 临高启明. None when no volume marker was found (the title alone
    says nothing about volumes)."""
    name = name.split(":")[-1]
    name = re.sub(r"\.epub$", "", name, flags=re.I)
    name = re.sub(r"^(?:Copy of )?【[^】]*】", "", name)
    title = re.split(r" -- | - | \(|（|【", name)[0]
    title = re.sub(r"^《(.*)》$", r"\1", re.sub(r"\s+", " ", title).strip())
    stem = title
    for rx in VOLUME_RES:
        stem = rx.sub(" ", stem)
    stem = re.sub(r"\s+", " ", stem).strip(" _-:,，")
    if not stem or stem == title:
        return None
    return stem


def han_text(path):
    with open(path, encoding="utf-8") as f:
        return "".join(HAN_RE.findall(f.read()))


def shingles(text):
    """The text's SHINGLE-character windows that follow an anchor character
    (的, 了, 是): content-defined, so two copies of a text share them
    wherever they start, and fast to collect."""
    return set(ANCHOR_RE.findall(text))


class UnionFind:
    def __init__(self, keys):
        self.parent = {k: k for k in keys}

    def find(self, k):
        while self.parent[k] != k:
            self.parent[k] = self.parent[self.parent[k]]
            k = self.parent[k]
        return k

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[max(ra, rb)] = min(ra, rb)


def read_overrides(path):
    out = {}
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        for line in lines:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 2 and parts[0].strip() and parts[1].strip():
                out[parts[0].strip()] = parts[1].strip()
    return out


def group(files, texts, overrides=None):
    """Works and copies.

    files: [(key, name)]; texts: key -> Han text.
    Returns (works, copies, report): works = {work id: [file keys]}; copies =
    {file key: the key of the copy that is counted for it} (a file counted
    in its own right maps to itself); report = notes for the reader.
    """
    overrides = overrides or {}
    keys = [k for k, _ in files]
    names = dict(files)
    report = {"local": [], "volumes": [], "copies": [], "overlaps": [], "overrides": []}

    # Copies: the same text in two files (device + --local, or a book pulled
    # twice under two titles).
    sh = {k: shingles(texts[k]) for k in keys}
    copies_uf = UnionFind(keys)
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            sa, sb = sh[a], sh[b]
            small = min(len(sa), len(sb))
            if not small:
                continue
            c = len(sa & sb) / small
            if c >= REPORT_CONTAINMENT:
                report["overlaps"].append((a, b, c))
            if c >= COPY_CONTAINMENT:
                copies_uf.union(a, b)
                report["copies"].append((a, b, c))
    copy_sets = defaultdict(list)
    for k in keys:
        copy_sets[copies_uf.find(k)].append(k)
    copies = {}
    for members in copy_sets.values():
        best = max(members, key=lambda k: (len(texts[k]), k))
        for k in members:
            copies[k] = best

    # Works: --local runs, volumes, copies, then the overrides.
    works_uf = UnionFind(keys)
    by_local = defaultdict(list)
    for k in keys:
        m = re.fullmatch(r"([a-z][a-z0-9_]*)-\d+", k)
        if m:
            by_local[m.group(1)].append(k)
    for prefix, members in by_local.items():
        for k in members[1:]:
            works_uf.union(members[0], k)
        report["local"].append((prefix, members))
    by_stem = defaultdict(list)
    for k in keys:
        if not re.fullmatch(r"[a-z][a-z0-9_]*-\d+", k):
            stem = title_stem(names[k])
            if stem:
                by_stem[stem].append(k)
    for stem, members in by_stem.items():
        if len(members) > 1:
            for k in members[1:]:
                works_uf.union(members[0], k)
            report["volumes"].append((stem, members))
    for k in keys:
        works_uf.union(k, copies[k])
    work_of = {k: works_uf.find(k) for k in keys}
    for k, w in overrides.items():
        if k in work_of:
            report["overrides"].append((k, work_of[k], w))
            work_of[k] = "override:" + w
    works = defaultdict(list)
    for k in keys:
        works[work_of[k]].append(k)
    return dict(works), copies, report


# ----------------------------------------------------------------------
# Counting and ranking
# ----------------------------------------------------------------------

def count(works, copies, texts, public):
    """char -> [works, occurrences], keyed by simplified form; each copy set
    counted once (its largest file)."""
    stats = {}
    for members in works.values():
        counted = sorted({copies[k] for k in members})
        occ = Counter()
        for k in counted:
            occ.update(public.key(ch) for ch in texts[k])
        for ch, n in occ.items():
            if ch not in public.rank:
                continue
            s = stats.get(ch)
            if s is None:
                stats[ch] = [1, n]
            else:
                s[0] += 1
                s[1] += n
    return stats


def rank(stats, public):
    """[(char, rank, works, occurrences)] in rank order: works, then
    occurrences (both descending), then bundled rank, then the character."""
    order = sorted(stats, key=lambda ch: (-stats[ch][0], -stats[ch][1], public.sort_rank(ch), ch))
    return [(ch, i + 1, stats[ch][0], stats[ch][1]) for i, ch in enumerate(order)]


def exact_cutoff(ranked, n_works):
    """The last rank before the first character seen in fewer than
    min(EXACT_MIN_WORKS, n_works) works, rounded down to a hundred (at
    least 100 when anything is ranked)."""
    need = max(1, min(EXACT_MIN_WORKS, n_works))
    last = 0
    for ch, r, w, _ in ranked:
        if w < need:
            break
        last = r
    if last >= 100:
        last = last // 100 * 100
    return last


def with_forms(ranked, public):
    """The rows plus each traditional form (and 〇) under its simplified
    form's rank, in rank order."""
    forms = public.forms()
    out = []
    for ch, r, w, n in ranked:
        out.append((ch, r, w, n))
        for t in sorted(forms.get(ch, ())):
            if t not in public.rank:
                continue
            out.append((t, r, w, n))
    return out


def write(path, rows, header):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("# chinesehelper user ranks (tools/build_user_ranks.py)\n")
        for key in ("date", "works", "files", "han", "ranked", "exact"):
            f.write(f"# {key}\t{header[key]}\n")
        f.write("# char\trank\tworks\toccurrences\n")
        for ch, r, w, n in rows:
            f.write(f"{ch}\t{r}\t{w}\t{n}\n")
    os.replace(tmp, path)


def write_grouping(path, files, works, copies, report):
    names = dict(files)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# The grouping build_user_ranks.py chose: file <TAB> work <TAB> counted as <TAB> name.\n")
        f.write("# To change it, copy lines to build/user-ranks-works.tsv as file <TAB> work.\n")
        for wid, members in sorted(works.items(), key=lambda kv: kv[0]):
            for k in sorted(members):
                f.write(f"{k}\t{wid}\t{copies[k]}\t{names[k]}\n")


# ----------------------------------------------------------------------
# Input from EPUBs
# ----------------------------------------------------------------------

def texts_from_epubs(directory):
    """[(key, name)] and key -> Han text, for each EPUB in `directory`,
    extracted with fetch_books.py's code."""
    import fetch_books
    files, texts = [], {}
    for k, name in enumerate(sorted(n for n in os.listdir(directory) if n.lower().endswith(".epub")), 1):
        try:
            text = "".join(HAN_RE.findall("\n".join(fetch_books.paragraphs(os.path.join(directory, name)))))
        except Exception as e:  # a broken EPUB: skipped, reported
            print(f"  skipped {name}: {e}")
            continue
        if len(text) < 20000:
            continue
        key = f"{k:03d}"
        files.append((key, name))
        texts[key] = text
    return files, texts


# ----------------------------------------------------------------------
# --push
# ----------------------------------------------------------------------

def push(path=OUT, dest=DEVICE_PATH, run=subprocess.run):
    """Copy the file already built to the device (no rebuild)."""
    if not os.path.exists(path):
        sys.exit(f"no {path}: run tools/build_user_ranks.py first")
    run(["adb", "push", path, dest], check=True, capture_output=True, text=True)
    print(f"pushed {path} -> {dest}")
    print("In KOReader: Chinese helper > Frequency ranks > From my books (a new file is picked up at the next page turn).")


# ----------------------------------------------------------------------

def build(files, texts, public, overrides=None, date=None):
    works, copies, report = group(files, texts, overrides)
    stats = count(works, copies, texts, public)
    ranked = rank(stats, public)
    counted = {copies[k] for k in copies}
    han = sum(len(texts[k]) for k in counted)
    header = {
        "date": date or datetime.date.today().isoformat(),
        "works": len(works), "files": len(files), "han": han,
        "ranked": len(ranked), "exact": exact_cutoff(ranked, len(works)),
    }
    return ranked, header, works, copies, report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--corpus", default=CORPUS, help="build/corpus/ from tools/fetch_books.py (default)")
    ap.add_argument("--epubs", metavar="DIR", help="a folder of EPUBs instead of build/corpus/")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--works", default=WORKS_OVERRIDE, help="file <TAB> work overrides")
    ap.add_argument("--db", default=DB, help="the plugin database (bundled ranks, traditional forms)")
    ap.add_argument("--push", action="store_true", help="copy the existing --out file to the device; no rebuild")
    args = ap.parse_args()
    if args.push:
        return push(args.out)

    public = Public.from_db(args.db)
    if args.epubs:
        files, texts = texts_from_epubs(args.epubs)
    else:
        if not os.path.isdir(args.corpus):
            sys.exit(f"no {args.corpus}: run tools/fetch_books.py first (or give --epubs DIR)")
        files = read_index(args.corpus)
        texts = {k: han_text(os.path.join(args.corpus, k + ".txt")) for k, _ in files}
    if not files:
        sys.exit("no books with Chinese text found")
    ranked, header, works, copies, report = build(files, texts, public, read_overrides(args.works))
    rows = with_forms(ranked, public)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    write(args.out, rows, header)
    write_grouping(os.path.join(os.path.dirname(args.out), os.path.basename(GROUPING_OUT)),
                   files, works, copies, report)
    copies_dropped = sum(1 for k, c in copies.items() if k != c)
    print(f"{header['works']} works from {header['files']} files ({copies_dropped} duplicate copies not counted), "
          f"{header['han']:,} Han characters")
    print(f"{header['ranked']:,} distinct characters ranked ({len(rows):,} rows with traditional forms); "
          f"exact ranks up to {header['exact']:,}")
    for stem, members in report["volumes"]:
        print(f"  volumes of one work: {stem}: {', '.join(members)}")
    for a, b, c in report["copies"]:
        print(f"  same text: {a} ~ {b} ({c:.0%})")
    print(f"-> {args.out}")


if __name__ == "__main__":
    main()
