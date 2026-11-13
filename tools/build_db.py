#!/usr/bin/env python3
"""Build chinesehelper.koplugin/data/chinesehelper.sqlite: CC-CEDICT and the
reading resolver's tables in one SQLite database.

    pip install wordfreq==3.1.1 pypinyin==0.55.0      (lupa too, for --learn)
    python3 tools/build_db.py                          # download the current CC-CEDICT
    python3 tools/build_db.py --cedict build/cedict_1_0_ts_utf-8_mdbg.txt.gz
    python3 tools/build_db.py --learn                  # also re-learn data/rules.tsv and
                                                       # data/uncertain.tsv from the CPP
                                                       # dataset (downloaded, ~/.cache)

Steps:
  1. CC-CEDICT: downloaded into build/ (git-ignored), or --cedict.
  2. tools/build_data.py: the reading tables (chars, words, special words) from
     CC-CEDICT, wordfreq and pypinyin, plus data/overrides.tsv and
     data/special_curated.tsv, into build/data/.
  3. With --learn, tools/learn_from_cpp.py: context rules and uncertain
     characters from the CPP dataset's train split, into data/rules.tsv and
     data/uncertain.tsv. These are committed, so a rebuild without --learn
     does not need the CPP dataset.
  4. The fallback table: English Wiktionary (kaikki.org's extraction) and
     Chinese Wikipedia titles (the zhwiki SQL dumps, about 1.1 GB, parsed in
     a few minutes; tools/wikipedia_dump.py), both downloaded into
     build/sources/ when missing (see tools/fallback_sources.py).
  5. Character components (tools/components.py): English Wiktionary's
     `Han compound` analyses, Make Me a Hanzi's dictionary.txt (LGPL v3) and
     yi-bai/ids (MIT), both downloaded into build/sources/ at a fixed commit.
  6. Everything into one SQLite file; the lookup queries' plans are checked
     and the build fails if any of them scans a table.

Schema:
    entries(simp, trad, pinyin, syllables, defs)   one row per CC-CEDICT line
        pinyin     tone marks, joined into words: "Zhōngguó", "dōngxi"
        syllables  tone marks, one per character: "Zhōng guó", "dōng xi"
        defs       senses joined with "/", cross-references made readable
    chars(ch, rank, reading)  words(word, syllables, freq, rare)
        rare       1 when the word contains a character that can be annotated
    word_marks(word, syllables)   the reading the popup marks where it is not
                              the one drawn (see build_data.py, word_marks.tsv)
    rules(ch, side, neighbour, reading, n)  uncertain(ch, confidence, first, second)
    special(word, pinyin, marks, freq, note)  special_guard(ordinary, word, offset)
    components(ch, body)      a character's parts (format: tools/components.py Builder)
    component_notes(ch, text) Wiktionary's glyph-origin text (the popup's Origin view)
    meta(key, value)          source versions and counts
See chinesehelper.koplugin/ch_db.lua and ch_readings.lua for how they are used.

CC-CEDICT: https://www.mdbg.net/chinese/dictionary?page=cc-cedict
(c) MDBG and contributors, CC BY-SA 4.0.
"""
import argparse
import json
import gzip
import hashlib
import os
import re
import sqlite3
import subprocess
import sys
import unicodedata
import urllib.request
from collections import Counter
from importlib.metadata import version

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pinyin_util import numbered_to_marked  # noqa: E402
import fallback_sources  # noqa: E402
import components  # noqa: E402
import wikipedia_dump  # noqa: E402

URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
BUILD_DIR = os.path.join(ROOT, "build")
BUILD_DATA = os.path.join(BUILD_DIR, "data")
DATA_DIR = os.path.join(ROOT, "data")

LINE_RE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$")
RARE_RANK = 1000   # as Readings.RARE_RANK in ch_readings.lua and MIN_ANNOTATABLE_RANK in build_data.py

# ---------------------------------------------------------------------------
# CC-CEDICT pinyin and cross-references (from koreader-chinese-popup)
# ---------------------------------------------------------------------------


def marked_syllable(syl):
    """'Zhong1' -> 'Zhōng' (capital kept: names), 'xi5' -> 'xi'."""
    marked = numbered_to_marked(syl)
    return marked[:1].upper() + marked[1:] if syl[:1].isupper() else marked


def joined_pinyin(numbered):
    """'shen2 me5' -> 'shénme', 'Xi1 an1' -> "Xī'ān" (apostrophe before a, o, e)."""
    if "·" in numbered:  # names: 喬治·奧威爾|乔治·奥威尔[Qiao2 zhi4 · Ao4 wei1 er3]
        return "·".join(joined_pinyin(part) for part in numbered.split("·"))
    out = []
    for i, syl in enumerate(numbered.replace(",", " ").split()):
        capital = syl[:1].isupper()
        marked = marked_syllable(syl)
        if i > 0 and capital:  # a new name word: Dong4 wu4 Nong2 chang3 -> Dòngwù Nóngchǎng
            marked = " " + marked
        elif i > 0 and unicodedata.normalize("NFD", marked)[:1].lower() in "aoe":
            marked = "'" + marked
        out.append(marked)
    return "".join(out)


def syllable_pinyin(numbered):
    """'dong1 xi5' -> 'dōng xi': one syllable per character, for comparing
    with the resolver's readings."""
    return " ".join(marked_syllable(s) for s in numbered.split())


# Cross-references inside CC-CEDICT senses: 夠|够[gou4], 乘[cheng2], [jue2].
# A form is Chinese characters, possibly with ASCII letters and digits inside
# it (95後|95后, B型超聲|B型超声, 237號房間|237号房间).
XREF_FORM = r"[0-9A-Za-z]*(?:[^\x00-\x7f\s\[\]|,;:()/][0-9A-Za-z]*)+"
XREF_RE = re.compile(rf"(?:({XREF_FORM})(?:\|({XREF_FORM}))?)?\[([A-Za-z0-9:, ·]+)\]")
BARE_XREF_RE = re.compile(rf"({XREF_FORM})\|({XREF_FORM})")


def clean_sense(sense):
    """'variant of 夠|够[gou4]' -> 'variant of 够 gòu', 'CL:個|个[ge4],隻|只[zhi1]'
    -> 'CL: 个 gè, 只 zhī', 'Taiwan pr. [jue2]' -> 'Taiwan pr. jué',
    'branch of Xianbei 鮮卑|鲜卑' -> 'branch of Xianbei 鲜卑'.
    Cross-references show the simplified form (the reader mostly reads modern
    simplified Mandarin)."""
    def repl(m):
        first, second, py = m.groups()
        form = (second or first) if first else ""
        py = joined_pinyin(py)
        return f"{form} {py}" if form else py
    sense = XREF_RE.sub(repl, sense)
    # Without pinyin: 鮮卑|鲜卑 -> 鲜卑.
    sense = BARE_XREF_RE.sub(lambda m: m.group(2), sense)
    if sense.startswith("CL:"):
        sense = "CL: " + ", ".join(p.strip() for p in sense[3:].split(","))
    return sense.replace("\t", " ").strip()


def opener(path):
    return gzip.open(path, "rt", encoding="utf-8") if path.endswith(".gz") else open(path, encoding="utf-8")


def read_cedict(path):
    header, entries = {}, []
    with opener(path) as f:
        for line in f:
            if line.startswith("#"):
                if line.startswith("#! ") and "=" in line:
                    key, value = line[3:].strip().split("=", 1)
                    header[key] = value
                continue
            m = LINE_RE.match(line.strip())
            if not m:
                continue
            trad, simp, py, defs = m.groups()
            senses = [clean_sense(s) for s in defs.split("/") if s.strip()]
            entries.append((simp, trad, joined_pinyin(py), syllable_pinyin(py), "/".join(senses)))
    return header, entries


def download():
    os.makedirs(BUILD_DIR, exist_ok=True)
    path = os.path.join(BUILD_DIR, os.path.basename(URL))
    print(f"Downloading {URL}")
    req = urllib.request.Request(URL, headers={"User-Agent": "koreader-chinese-helper build script"})
    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
        f.write(r.read())
    return path


# ---------------------------------------------------------------------------
# Reading tables (TSV from build_data.py and data/)
# ---------------------------------------------------------------------------


def tsv(path, ncols, required=True):
    if not os.path.exists(path):
        if required:
            sys.exit(f"missing {path}")
        return []
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            rows.append((fields + [""] * ncols)[:ncols])
    return rows


def int_or_zero(s):
    return int(s) if s.strip().lstrip("-").isdigit() else 0


# ---------------------------------------------------------------------------
# The database
# ---------------------------------------------------------------------------

SCHEMA = """
    PRAGMA page_size = 4096;
    CREATE TABLE entries (simp TEXT NOT NULL, trad TEXT NOT NULL, pinyin TEXT NOT NULL,
                          syllables TEXT NOT NULL, defs TEXT NOT NULL);
    CREATE TABLE chars (ch TEXT PRIMARY KEY, rank INTEGER NOT NULL, reading TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE words (word TEXT PRIMARY KEY, syllables TEXT NOT NULL, freq INTEGER NOT NULL,
                        rare INTEGER NOT NULL) WITHOUT ROWID;
    CREATE TABLE word_marks (word TEXT PRIMARY KEY, syllables TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE rules (ch TEXT NOT NULL, side TEXT NOT NULL, neighbour TEXT NOT NULL,
                        reading TEXT NOT NULL, n INTEGER NOT NULL);
    CREATE TABLE uncertain (ch TEXT PRIMARY KEY, confidence REAL NOT NULL, first TEXT NOT NULL,
                            second TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE special (word TEXT NOT NULL, pinyin TEXT NOT NULL, marks TEXT NOT NULL,
                          freq INTEGER NOT NULL, note TEXT);
    CREATE TABLE special_guard (ordinary TEXT NOT NULL, word TEXT NOT NULL, offset INTEGER NOT NULL);
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE components (ch TEXT PRIMARY KEY, body TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE component_notes (ch TEXT NOT NULL, text TEXT NOT NULL);
"""


WIKT_URL = "https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl.gz"
WIKT_PAGE = "https://kaikki.org/dictionary/Chinese/index.html"
WIKT_DEFAULT = os.path.join(BUILD_DIR, "sources", "wiktionary", "kaikki-Chinese.jsonl.gz")
WP_DEFAULT = os.path.join(BUILD_DIR, "sources", "wikipedia")


def download_wiktionary(path=WIKT_DEFAULT):
    """kaikki.org's Chinese extraction of English Wiktionary, and, next to it,
    <file>.info.json with the Wiktionary dump date and extraction date from
    kaikki's page (mirrors keep only the current extraction)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    headers = {"User-Agent": "koreader-chinese-helper build script"}
    print(f"Downloading {WIKT_URL}")
    with urllib.request.urlopen(urllib.request.Request(WIKT_URL, headers=headers), timeout=600) as r, \
            open(path, "wb") as f:
        last_modified = r.headers.get("Last-Modified", "")
        f.write(r.read())
    with urllib.request.urlopen(urllib.request.Request(WIKT_PAGE, headers=headers), timeout=120) as r:
        page = r.read().decode("utf-8", "replace")
    dump = re.search(r"dump dated (\d{4}-\d{2}-\d{2})", page)
    extracted = re.search(r"extracted on (\d{4}-\d{2}-\d{2})", page)
    info = {"url": WIKT_URL, "last_modified": last_modified,
            "wiktionary_dump": dump.group(1) if dump else "",
            "extracted": extracted.group(1) if extracted else ""}
    with open(path + ".info.json", "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    return path


def wiktionary_info(path):
    info = {}
    if os.path.exists(path + ".info.json"):
        with open(path + ".info.json", encoding="utf-8") as f:
            info = json.load(f)
    with open(path, "rb") as f:
        info["sha256"] = hashlib.sha256(f.read()).hexdigest()
    return info


MMAH_COMMIT = "618dbab8a8ddefb958763c8b4afbaa741a4460de"
MMAH_URL = f"https://raw.githubusercontent.com/skishore/makemeahanzi/{MMAH_COMMIT}/dictionary.txt"
MMAH_DEFAULT = os.path.join(BUILD_DIR, "sources", "mmah", "dictionary.txt")
IDS_COMMIT = "2597437b928e8d530b7ae09cf53fe5ec7868569c"
IDS_URL = f"https://raw.githubusercontent.com/yi-bai/ids/{IDS_COMMIT}/ids_lv2.txt"
IDS_DEFAULT = os.path.join(BUILD_DIR, "sources", "ids", "ids_lv2.txt")


def fetch(url, path):
    """Download `url` to `path` unless it is there already."""
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print(f"Downloading {url}")
    headers = {"User-Agent": "koreader-chinese-helper build script"}
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=300) as r, \
            open(path + ".tmp", "wb") as f:
        f.write(r.read())
    os.replace(path + ".tmp", path)
    return path


def sha256_of(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def component_rows(cedict_entries, wikt_path, mmah_path, ids_path, stats):
    """The components and component_notes rows (tools/components.py)."""
    chars = [(ch, int(rank), reading) for ch, rank, reading in tsv(os.path.join(BUILD_DATA, "chars.tsv"), 3)]
    builder = components.Builder(cedict_entries, chars,
                                 components.load_wiktionary(os.path.dirname(wikt_path)),
                                 components.load_mmah(mmah_path), components.load_ids(ids_path))
    bodies, notes = builder.build([ch for ch, _, _ in chars], {ch for ch, rank, _ in chars if rank > 0})
    stats.update(builder.stats)
    return sorted(bodies.items()), sorted(notes.items())


def resolver_digest(*tables):
    """One checksum over the resolver's tables, recorded in meta: fallback
    data must never change it (compare builds with and without fallback)."""
    h = hashlib.sha256()
    for rows in tables:
        for row in sorted(rows, key=repr):
            h.update(repr(row).encode("utf-8"))
        h.update(b"|")
    return h.hexdigest()


def build(cedict_entries, header, sha, out, wikt=None, wp=None, comps=None):
    """wikt: (path, rows, stats) for the Wiktionary fallback rows, or None;
    wp: (dump folder, rows, stats) for the Wikipedia titles, or None;
    comps: (bodies, notes, {source: (url, sha256)}) for the components, or None."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    con = sqlite3.connect(tmp)
    con.executescript(SCHEMA)
    con.executemany("INSERT INTO entries VALUES (?, ?, ?, ?, ?)", cedict_entries)
    con.execute("CREATE INDEX entries_simp ON entries(simp)")
    con.execute("CREATE INDEX entries_trad ON entries(trad)")

    chars = [(ch, int(rank), reading) for ch, rank, reading in tsv(os.path.join(BUILD_DATA, "chars.tsv"), 3)]
    rank = {ch: r for ch, r, _ in chars}

    def rare(word):
        """Contains a character that can be annotated (rank above 1,000, or
        unranked): the plugin keeps these words in memory, so a page turn
        never queries the database."""
        return int(any(rank.get(ch, 0) == 0 or rank.get(ch, 0) > RARE_RANK for ch in word))
    words = [(w, syl, int_or_zero(freq), rare(w)) for w, syl, freq in tsv(os.path.join(BUILD_DATA, "words.tsv"), 3)]
    word_marks = [(w, syl) for w, syl in tsv(os.path.join(BUILD_DATA, "word_marks.tsv"), 2, required=False)]
    rules = [(ch, side, nb, r, int_or_zero(n)) for ch, side, nb, r, n in tsv(os.path.join(DATA_DIR, "rules.tsv"), 5)]
    uncertain = [(ch, float(c), a, b) for ch, c, a, b in tsv(os.path.join(DATA_DIR, "uncertain.tsv"), 4)]
    special = [(w, py, marks, int_or_zero(freq), note or None)
               for w, py, marks, freq, note in tsv(os.path.join(BUILD_DATA, "special.tsv"), 5)]
    guard = [(a, b, int(off)) for a, b, off in tsv(os.path.join(BUILD_DATA, "special_guard.tsv"), 3)]
    con.executemany("INSERT INTO chars VALUES (?, ?, ?)", chars)
    con.executemany("INSERT INTO words VALUES (?, ?, ?, ?)", words)
    con.executemany("INSERT INTO word_marks VALUES (?, ?)", word_marks)
    con.executemany("INSERT INTO rules VALUES (?, ?, ?, ?, ?)", rules)
    con.executemany("INSERT INTO uncertain VALUES (?, ?, ?, ?)", uncertain)
    con.executemany("INSERT INTO special VALUES (?, ?, ?, ?, ?)", special)
    con.executemany("INSERT INTO special_guard VALUES (?, ?, ?)", guard)
    # Fallback entries live in their own table: `entries` stays CC-CEDICT
    # alone, and nothing here feeds the resolver's tables above.
    fallback_sources.write_fallback(con, (wikt[1] if wikt else []) + (wp[1] if wp else []))
    # Character components: their own tables, read only by the popup.
    if comps:
        con.executemany("INSERT INTO components VALUES (?, ?)", comps[0])
        con.executemany("INSERT INTO component_notes VALUES (?, ?)", comps[1])
        con.execute("CREATE INDEX component_notes_ch ON component_notes(ch)")

    meta = {
        "cedict_date": header.get("date", ""), "cedict_entries": str(len(cedict_entries)),
        "cedict_sha256": sha, "wordfreq": version("wordfreq"), "pypinyin": version("pypinyin"),
        "chars": str(len(chars)), "words": str(len(words)), "rare_words": str(sum(w[3] for w in words)), "rules": str(len(rules)),
        "uncertain": str(len(uncertain)), "special": str(len(special)), "special_guard": str(len(guard)),
        "license": "CC BY-SA 4.0 (CC-CEDICT, wordfreq, Wiktionary, Wikipedia; see README)",
        "word_marks": str(len(word_marks)),
        "resolver_sha256": resolver_digest(chars, words, rules, uncertain, special, guard, word_marks),
        "fallback_sources": ",".join(name for name, part in (("wikt", wikt), ("wp", wp)) if part),
    }
    if wikt:
        info = wiktionary_info(wikt[0])
        meta.update({"wikt_rows": str(len(set(wikt[1]))), "wikt_sha256": info["sha256"],
                     "wikt_dump": info.get("wiktionary_dump", ""), "wikt_extracted": info.get("extracted", ""),
                     "wikt_url": info.get("url", WIKT_URL),
                     "wikt_license": "CC BY-SA 4.0 (Wiktionary contributors; wiktextract by Tatu Ylonen, kaikki.org)"})
    if wp:
        meta.update({"wp_rows": str(len(set(wp[1]))), "wp_dump": wikipedia_dump.dump_date(wp[0]),
                     "wp_url": wikipedia_dump.URL.format("*"),
                     "wp_license": "CC BY-SA 4.0 (Wikipedia contributors)"})
    if comps:
        meta.update({"components": str(len(comps[0])), "component_notes": str(len(comps[1])),
                     "mmah_url": comps[2]["mmah"][0], "mmah_sha256": comps[2]["mmah"][1],
                     "mmah_license": "LGPL v3 or later (Make Me a Hanzi dictionary.txt)",
                     "ids_url": comps[2]["ids"][0], "ids_sha256": comps[2]["ids"][1],
                     "ids_license": "MIT (yi-bai/ids)"})
    con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
    con.commit()
    con.execute("VACUUM")
    con.close()
    os.replace(tmp, out)
    return meta


# Keep in step with DB.entriesSql and DB.wordsSql in chinesehelper.koplugin/ch_db.lua
# (tests/test_db.lua checks that they match).
def entries_sql(n):
    marks = ",".join("?" * n)
    return (f"SELECT simp, trad, pinyin, syllables, defs FROM entries WHERE simp IN ({marks}) "
            f"OR trad IN ({marks}) ORDER BY rowid")


def words_sql(n):
    return f"SELECT word, syllables, freq FROM words WHERE word IN ({','.join('?' * n)})"


# Keep in step with DB.componentsSql and DB.notesSql in ch_db.lua.
COMPONENTS_SQL = "SELECT ch, body FROM components WHERE ch IN (?, ?)"
NOTES_SQL = "SELECT ch, text FROM component_notes WHERE ch IN (?, ?) ORDER BY rowid"


def check_query_plans(path):
    """Fail the build unless every lookup searches an index (no table scan).
    n: 1 and 36 candidate words for the popup (7+1+7 characters, words up to
    8), 1 and 9 for the resolver (words of 2-4 characters around one)."""
    con = sqlite3.connect(path)
    checks = [
        (entries_sql(1), 2, ("USING INDEX entries_simp", "USING INDEX entries_trad")),
        (entries_sql(36), 72, ("USING INDEX entries_simp", "USING INDEX entries_trad")),
        (words_sql(1), 1, ("USING PRIMARY KEY",)),
        (words_sql(9), 9, ("USING PRIMARY KEY",)),
        (fallback_sources.fallback_sql(1), 2, ("USING INDEX fallback_simp", "USING INDEX fallback_trad")),
        (fallback_sources.fallback_sql(36), 72, ("USING INDEX fallback_simp", "USING INDEX fallback_trad")),
        (COMPONENTS_SQL, 2, ("USING PRIMARY KEY",)),
        (NOTES_SQL, 2, ("USING INDEX component_notes_ch",)),
    ]
    try:
        for sql, nargs, wanted in checks:
            plan = "\n".join(row[3] for row in con.execute("EXPLAIN QUERY PLAN " + sql, ["x"] * nargs))
            if any(w not in plan for w in wanted) or re.search(r"\bSCAN (entries|words|fallback|components|component_notes)\b", plan):
                sys.exit(f"Query does not use its index:\n{sql}\n{plan}")
            print(f"Query plan ok: {sql[:60]}...\n    " + plan.replace("\n", "\n    "))
    finally:
        con.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cedict", help="local CC-CEDICT file (.txt or .txt.gz); downloaded when omitted")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--learn", action="store_true",
                    help="re-learn data/rules.tsv and data/uncertain.tsv from the CPP dataset first")
    ap.add_argument("--skip-readings", action="store_true",
                    help="reuse build/data/ from an earlier run instead of running build_data.py")
    ap.add_argument("--wiktionary", default=WIKT_DEFAULT,
                    help="kaikki.org Chinese JSONL(.gz); downloaded when missing")
    ap.add_argument("--no-wiktionary", action="store_true", help="build without the Wiktionary fallback rows")
    ap.add_argument("--wikipedia", default=WP_DEFAULT,
                    help="folder of zhwiki-latest-*.sql.gz dumps; missing files are downloaded")
    ap.add_argument("--no-wikipedia", action="store_true", help="build without the Wikipedia title rows")
    ap.add_argument("--mmah", default=MMAH_DEFAULT, help="Make Me a Hanzi dictionary.txt; downloaded when missing")
    ap.add_argument("--ids", default=IDS_DEFAULT, help="yi-bai/ids ids_lv2.txt; downloaded when missing")
    ap.add_argument("--no-components", action="store_true", help="build without the character components")
    args = ap.parse_args()
    path = args.cedict or download()
    with open(path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()

    if not args.skip_readings:
        import build_data  # noqa: E402  (needs wordfreq and pypinyin)
        build_data.build(path, BUILD_DATA)
    if args.learn:
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "learn_from_cpp.py")], check=True)

    header, entries = read_cedict(path)
    if len(entries) < 100000:
        sys.exit(f"Only {len(entries)} entries read from {path}; is it CC-CEDICT?")
    wikt = None
    if not args.no_wiktionary:
        wpath = args.wiktionary if os.path.exists(args.wiktionary) else download_wiktionary(args.wiktionary)
        forms, measure = fallback_sources.forms_from_entries(entries)
        stats = Counter()
        rows = fallback_sources.wiktionary_rows(wpath, forms, measure, stats)
        for k in sorted(stats):
            print(f"  {k}: {stats[k]:,}")
        wikt = (wpath, rows, stats)
    wp = None
    if not args.no_wikipedia:
        wikipedia_dump.download(args.wikipedia)
        forms, measure = fallback_sources.forms_from_entries(entries)
        stats = Counter()
        rows = fallback_sources.wikipedia_rows(args.wikipedia, forms, measure, stats)
        for k in sorted(stats):
            print(f"  {k}: {stats[k]:,}")
        wp = (args.wikipedia, rows, stats)
    comps = None
    if not args.no_components:
        wpath = args.wiktionary if os.path.exists(args.wiktionary) else download_wiktionary(args.wiktionary)
        mmah = fetch(MMAH_URL, args.mmah)
        ids = fetch(IDS_URL, args.ids)
        stats = Counter()
        bodies, notes = component_rows(entries, wpath, mmah, ids, stats)
        for k in sorted(stats):
            print(f"  components, {k}: {stats[k]:,}")
        comps = (bodies, notes, {"mmah": (MMAH_URL, sha256_of(mmah)), "ids": (IDS_URL, sha256_of(ids))})
    meta = build(entries, header, sha, args.out, wikt, wp, comps)
    check_query_plans(args.out)
    size = os.path.getsize(args.out)
    print(f"CC-CEDICT {header.get('date', '(no date)')}: {len(entries)} entries, SHA-256 {sha}")
    print("Tables: " + ", ".join(f"{k} {meta[k]}" for k in
                                 ("chars", "words", "word_marks", "rules", "uncertain", "special",
                                  "special_guard")))
    print(f"Resolver tables SHA-256 {meta['resolver_sha256']}")
    if wikt:
        print(f"Wiktionary fallback: {meta['wikt_rows']} rows (dump {meta['wikt_dump']}, "
              f"extracted {meta['wikt_extracted']}, SHA-256 {meta['wikt_sha256']})")
    if wp:
        print(f"Wikipedia titles: {meta['wp_rows']} rows (dump {meta['wp_dump']})")
    if comps:
        print(f"Components: {meta['components']} characters, {meta['component_notes']} origin notes")
    print(f"Wrote {args.out} ({size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
