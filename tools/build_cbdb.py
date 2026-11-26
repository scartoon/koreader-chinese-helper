#!/usr/bin/env python3
"""Build the optional CBDB dictionary for your own device: well-known people,
office titles of every dynasty and book titles, from the China Biographical
Database (CBDB).

    .venv/bin/python tools/build_cbdb.py            # -> build/chinesehelper-cbdb.sqlite
    .venv/bin/python tools/build_cbdb.py --push     # ... and adb push it to the device

The source is CBDB's SQLite release on Hugging Face (cbdb/cbdb-sqlite, about
110 MB zipped, 590 MB unzipped), downloaded into build/sources/cbdb/ when
missing. CBDB's data licensing terms
(https://cbdb.hsites.harvard.edu/cbdb-data-licensing-terms) put the data of
the standalone release under CC BY-NC-SA 4.0 and add CBDB's own
non-commercial, no-redistribution terms beyond it. So this file is never
committed, never part of a release, and never shared: you build it yourself,
for your own device. The plugin works without it.

On the device it goes in KOReader's data folder:

    <KOReader data>/data/chinesehelper/chinesehelper-cbdb.sqlite
    Android: /sdcard/koreader/data/chinesehelper/chinesehelper-cbdb.sqlite

What is in it (#87; the categories and filters are the ones that were right
about 90% of the time or better on judged taps in real books,
tools/measure_cbdb.py):

  people   names of 3+ characters that another dictionary the plugin has also
           knows (CC-CEDICT, Wiktionary, the Wikipedia titles, the Classical
           dictionary, MOE), for the people CBDB documents with at least
           PERSON_MIN_RECORDS records. One sense per person, best documented
           first (at most PERSON_SENSES, then "+N more in CBDB"):
           "Song · 1021–1086 · 字 介甫 · 號 半山老人 · 諡 文 · 臨川 · 進士 1042".
           Alternative names (字, 號) are never headwords: in modern prose
           they are mostly ordinary words (知道, 皇帝 are somebody's 字).
  offices  OFFICE_CODES names and alternative names of 3+ characters, every
           dynasty, except modern titles (MODERN_TITLE: 副总裁, 副局长 read as
           today's titles). One sense per English translation, with its
           dynasties ("office title · Ming, Qing: Academician
           Expositor-in-waiting"); dynasties without one together
           ("office title (Tang)").
  books    TEXT_CODES titles of 2-8 characters, in their own table
           (cbdb_books): the plugin shows them only when the tapped text is
           exactly a title in 《》 (or the part before ·), as in 《隋書》.

Tables: `fallback` (people and offices, with source "cbdb" and the `covered`
column: rows for headwords CC-CEDICT has are covered = 1, for Always mode),
`cbdb_books` (simp, trad, pinyin, defs, defs_simp) and `meta`.

Readings: CBDB's pinyin has no tones. Each syllable takes the tone of the
character's CC-CEDICT reading with the same letters (单 shan -> Shàn,
解 xie -> Xiè); where none or several match, CBDB's toneless letters stay.
"""
import argparse
import collections
import json
import os
import re
import sqlite3
import sys
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fallback_sources  # noqa: E402
from simplify import Simplifier  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "build", "sources", "cbdb")
LATEST = "https://huggingface.co/datasets/cbdb/cbdb-sqlite/resolve/main/latest.json"
DEFAULT_OUT = os.path.join(ROOT, "build", "chinesehelper-cbdb.sqlite")
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
DEFAULT_MOE = os.path.join(ROOT, "chinesehelper.koplugin", "data", "moe", "moe.sqlite")
LICENSE = ("CBDB (China Biographical Database), CC BY-NC-SA 4.0 and the CBDB Data Licensing Terms. "
           "For your own use: do not distribute this file.")

PERSON_MIN_RECORDS = 10     # CBDB records (offices, entries, names, addresses ...) a person needs
PERSON_SENSES = 3           # people shown under one name, then "+N more in CBDB"
# The tables counted as a person's records (how well CBDB documents them).
RECORD_TABLES = ("POSTED_TO_OFFICE_DATA", "ENTRY_DATA", "ALTNAME_DATA", "BIOG_ADDR_DATA", "STATUS_DATA",
                 "BIOG_TEXT_DATA", "KIN_DATA", "ASSOC_DATA")
ALT_SHOWN = ((4, "字"), (5, "號"), (6, "諡"))   # ALTNAME_CODES shown on a person's line, in order
JINSHI = 36                 # ENTRY_CODES: 科舉: 進士(籠統)
AUTHOR_ROLES = (1, 3)       # TEXT_ROLE_CODES: 撰著者, 編纂者
# Endings of modern titles: CBDB has some as historical offices (副總裁 Ming,
# 副局長 Jin), but books use them in today's sense (tools/measure_cbdb.py).
MODERN_TITLE = ("局长", "总裁", "经理", "主任", "处长", "科长", "部长", "厂长", "主席", "书记", "董事", "秘书",
                "会长", "院长", "校长", "所长", "司长", "厅长", "省长", "市长", "县长", "镇长", "乡长", "村长",
                "队长", "组长", "社长", "台长", "站长", "行长", "总监", "委员", "代表", "教授", "讲师", "干部",
                "警官", "律师", "总统", "总理", "议员", "大使", "领事", "主编")
OFFICE_CUT = 50             # OFFICE_CODES.c_office_trans is cut at this many characters (#89)
# A cut gloss that ends in one of these, or in a word no whole gloss has ("Secretariat-Ch"), gets "…".
CUT_ENDINGS = ("of", "the", "and", "for", "at", "in", "to", "a", "an", "on", "with", "by")
HAN = fallback_sources.han_word


def find_source(src_dir):
    """The CBDB SQLite file (and latest.json's metadata), downloading and
    unzipping the release named in latest.json when it is not there yet."""
    os.makedirs(src_dir, exist_ok=True)
    info_path = os.path.join(src_dir, "latest.json")
    if not os.path.exists(info_path):
        req = urllib.request.Request(LATEST, headers={"User-Agent": "koreader-chinese-helper build script"})
        with urllib.request.urlopen(req, timeout=60) as r, open(info_path, "wb") as f:
            f.write(r.read())
    with open(info_path, encoding="utf-8") as f:
        info = json.load(f)
    db = os.path.join(src_dir, "db", info["sqlite_filename"])
    if not os.path.exists(db):
        zpath = os.path.join(src_dir, os.path.basename(info["huggingface_path"]))
        if not os.path.exists(zpath):
            fallback_sources.download_file(info["huggingface_url"], zpath)
        print(f"Unzipping {os.path.relpath(zpath)}")
        with zipfile.ZipFile(zpath) as z:
            member = next(n for n in z.namelist() if n.endswith(info["sqlite_filename"]))
            os.makedirs(os.path.dirname(db), exist_ok=True)
            with z.open(member) as src, open(db + ".part", "wb") as out:
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    out.write(chunk)
            os.replace(db + ".part", db)
    return db, info


# ---------------------------------------------------------------------------
# Readings
# ---------------------------------------------------------------------------

class Readings:
    """CC-CEDICT's readings from the plugin database: `chars` {character: set
    of lowercase marked syllables} (single-character entries, both forms),
    `words` {form: [lists of lowercase marked syllables]} (longer entries) and
    `default` {character: the plugin's default reading}."""

    def __init__(self, db_path):
        con = sqlite3.connect(db_path)
        self.chars, self.words = collections.defaultdict(set), collections.defaultdict(list)
        for simp, trad, syl in con.execute("SELECT simp, trad, syllables FROM entries"):
            if not syl:
                continue
            syls = syl.lower().split(" ")
            for form in {simp, trad}:
                if len(simp) == 1 and len(syls) == 1:
                    self.chars[form].add(syls[0])
                elif len(syls) == len(form):
                    self.words[form].append(syls)
        self.default = dict(con.execute("SELECT ch, reading FROM chars"))
        con.close()

    def pick(self, chars, syls):
        """The marked syllables for `chars` read with CBDB's toneless `syls`,
        a syllable left toneless where nothing settles its tone. Left to right,
        the longest CC-CEDICT word with those letters (王安石 Wáng Ānshí,
        大將軍 dà jiàng jūn), else per character its only reading with those letters, or its default
        reading when that has them."""
        strip = fallback_sources._strip_tones
        out, i = [], 0
        while i < len(chars):
            # The longest CC-CEDICT word from here whose letters are CBDB's.
            for j in range(len(chars), i + 1, -1):
                hit = next((w for w in self.words.get("".join(chars[i:j]), ())
                            if [strip(x) for x in w] == syls[i:j]), None)
                if hit:
                    out += hit
                    i = j
                    break
            else:
                ch, syl = chars[i], syls[i]
                tones = {r for r in self.chars.get(ch, ()) if strip(r) == syl and r != syl}
                if len(tones) == 1:
                    out.append(next(iter(tones)))
                elif self.default.get(ch) in tones:
                    out.append(self.default[ch])
                else:
                    out.append(syl)
                i += 1
        return out


def toned(chars, cbdb_pinyin, readings, stats=None):
    """CBDB's toneless pinyin for `chars` ("Wang Anshi") with each syllable's
    tone from the character's CC-CEDICT reading with the same letters
    ("Wáng Ānshí"), CBDB's grouping and capitals kept. A syllable that
    matches no reading, or readings with different tones, stays toneless.
    Returns "" when CBDB gives no reading; CBDB's text when its syllables
    cannot be lined up with the characters."""
    py = re.sub(r"\s+", " ", (cbdb_pinyin or "").replace("ü", "v")).strip()
    if not py:
        return ""
    syls = fallback_sources.split_joined(py.lower().replace("v", "ü"), len(chars))
    if not syls:
        if stats is not None:
            stats["readings: CBDB's not lined up (kept as is)"] += 1
        return py.replace("v", "ü")
    marked = readings.pick(chars, syls)
    if stats is not None:
        stats["readings: syllables left toneless"] += sum(1 for a, b in zip(marked, syls) if a == b)
    # Back into CBDB's groups ("Wang" "Anshi"), with its capitals.
    out, k = [], 0
    for group in py.split(" "):
        need, part = len(group.replace("'", "")), []
        while k < len(marked) and need > 0:
            need -= len(marked[k])
            part.append(marked[k])
            k += 1
        text = "".join(part)
        out.append(text[:1].upper() + text[1:] if group[:1].isupper() else text)
    if k < len(marked):
        out.append("".join(marked[k:]))
    return " ".join(out)


# ---------------------------------------------------------------------------
# Other dictionaries: which people count as well known
# ---------------------------------------------------------------------------

def known_words(db_path, moe_path):
    """(CC-CEDICT's forms, every form another dictionary of the plugin has:
    CC-CEDICT, the release's fallback table, the Classical dictionary, MOE)."""
    con = sqlite3.connect(db_path)
    cedict, known = set(), set()
    for s, t in con.execute("SELECT simp, trad FROM entries"):
        cedict.update((s, t))
    known |= cedict
    for table in ("fallback", "classical"):
        if con.execute("SELECT 1 FROM sqlite_master WHERE name = ?", (table,)).fetchone():
            for s, t in con.execute(f"SELECT simp, trad FROM {table}"):
                known.update((s, t))
    con.close()
    if moe_path and os.path.exists(moe_path):
        m = sqlite3.connect(f"file:{moe_path}?mode=ro", uri=True)
        for table in ("revised_keys", "idioms_keys"):
            if m.execute("SELECT 1 FROM sqlite_master WHERE name = ?", (table,)).fetchone():
                for s, t in m.execute(f"SELECT simp, trad FROM {table}"):
                    known.update((s, t))
        m.close()
    else:
        print(f"  (no MOE data at {moe_path}: people only MOE knows are left out)")
    return cedict, known


# ---------------------------------------------------------------------------
# The three categories
# ---------------------------------------------------------------------------

def years(by, dy):
    by, dy = by or 0, dy or 0
    if not by and not dy:
        return ""
    return f"{by or '?'}–{dy or '?'}"


def person_rows(con, t2s, readings, known, stats):
    """Rows (simp, trad, pinyin, "", defs, "cbdb") for well-known people."""
    dynasty = {d: en for d, en in con.execute("SELECT c_dy, c_dynasty FROM DYNASTIES")}
    records = collections.Counter()
    for table in RECORD_TABLES:
        for pid, n in con.execute(f"SELECT c_personid, count(*) FROM {table} GROUP BY c_personid"):
            records[pid] += n
    by_name = collections.defaultdict(list)
    for pid, name, py, by, dy, d, addr in con.execute(
            "SELECT c_personid, c_name_chn, c_name, c_birthyear, c_deathyear, c_dy, c_index_addr_id FROM BIOG_MAIN"):
        if name and len(name) >= 3 and HAN(name):
            by_name[name].append((pid, py, by, dy, d, addr))
    stats["people: names of 3+ characters"] = len(by_name)
    wanted = {}
    for name, people in by_name.items():
        simp = t2s.convert(name)
        if not (name in known or simp in known):
            continue
        documented = sorted((p for p in people if records[p[0]] >= PERSON_MIN_RECORDS),
                            key=lambda p: (-records[p[0]], p[0]))
        if documented:
            wanted[name] = (simp, documented, len(people))
    stats["people: names another dictionary has, documented"] = len(wanted)
    pids = {p[0] for _s, ps, _n in wanted.values() for p in ps[:PERSON_SENSES]}
    alts = collections.defaultdict(dict)
    for pid, alt, code in con.execute("SELECT c_personid, c_alt_name_chn, c_alt_name_type_code FROM ALTNAME_DATA "
                                      "ORDER BY c_personid, c_sequence"):
        if pid in pids and alt and code in dict(ALT_SHOWN):
            alts[pid].setdefault(code, alt)
    jinshi = {}
    for pid, year in con.execute("SELECT c_personid, min(c_year) FROM ENTRY_DATA WHERE c_entry_code = ? "
                                 "GROUP BY c_personid", (JINSHI,)):
        if pid in pids:
            jinshi[pid] = year
    places = dict(con.execute("SELECT c_addr_id, c_name_chn FROM ADDR_CODES"))
    rows = []
    for name, (simp, people, total) in sorted(wanted.items()):
        senses = []
        for pid, _py, by, dy, d, addr in people[:PERSON_SENSES]:
            parts = [dynasty.get(d, "")]
            parts.append(years(by, dy))
            parts += [f"{label} {alts[pid][code]}" for code, label in ALT_SHOWN if code in alts[pid]]
            parts.append(places.get(addr) or "")
            if pid in jinshi:
                parts.append(f"進士 {jinshi[pid]}" if jinshi[pid] else "進士")
            senses.append(" · ".join(p for p in parts if p and p not in ("unknown", "未詳")))
        if total > len(senses):
            senses.append(f"+{total - len(senses)} more in CBDB")
        py = toned(list(name), people[0][1], readings, stats)
        rows.append((simp, name, py, "", "/".join(fallback_sources.clean_sense(s) for s in senses), "cbdb"))
    stats["people: rows"] = len(rows)
    return rows


def office_rows(con, t2s, readings, stats):
    """Rows (simp, trad, pinyin, "", defs, "cbdb") for office titles."""
    dynasty = {}
    for d, en, start in con.execute("SELECT c_dy, c_dynasty, c_start FROM DYNASTIES"):
        dynasty[d] = (start if start is not None else 9999, en)
    titles = collections.defaultdict(lambda: {"py": "", "trad": "", "en": collections.defaultdict(set)})
    office = con.execute("SELECT c_office_chn, c_office_chn_alt, c_office_pinyin, c_office_trans, c_dy "
                         "FROM OFFICE_CODES ORDER BY c_office_id").fetchall()

    def clean(tr):
        # Stray "=" and "/" end some glosses ("... (Hucker)==").
        tr = re.sub(r"[\s=/]+$", "", re.sub(r"\s+", " ", tr or ""))
        en = re.sub(r"\s*\(Hucker\)$", "", tr).strip()
        return "" if en.startswith("[") or en.lower() == "unknown" else en

    # About 220 glosses are cut at OFFICE_CUT characters (#89: 同中書門下平章事, Tang:
    # "Jointly Manager of Affairs with the Secretariat-Ch"). Where a longer gloss starts
    # with the cut one, use it: the same title's first, else the only one in CBDB.
    cut = {clean(tr) for _, _, _, tr, _ in office if len(tr or "") == OFFICE_CUT}
    cut_lengths = {len(en) for en in cut}
    full_of_title, full = collections.defaultdict(set), collections.defaultdict(set)
    words = set()   # the words of uncut glosses
    for chn, _, _, tr, _ in office:
        en = clean(tr)
        if len(tr or "") == OFFICE_CUT:
            continue
        words.update(re.findall(r"[\w'-]+", en))
        for n in cut_lengths:
            if n < len(en) and en[:n] in cut:
                full[en[:n]].add(en)
                full_of_title[(chn, en[:n])].add(en)

    def whole(chn, tr):
        en = clean(tr)
        if len(tr or "") != OFFICE_CUT or not en:
            return en
        for found in (full_of_title.get((chn, en)), full.get(en)):
            if found and len(found) == 1:
                stats["offices: cut glosses completed"] += 1
                return next(iter(found))
        last = re.findall(r"[\w'-]+$", en)
        if not last or last[0] not in words or last[0].lower() in CUT_ENDINGS:
            stats["offices: cut glosses marked …"] += 1
            return en + "…"
        return en

    for chn, alt, py, tr, d in office:
        en = whole(chn, tr)
        for k, name in enumerate([chn] + re.split(r"[;；,，/、]", alt or "")):
            name = (name or "").strip()
            if len(name) < 3 or not HAN(name):
                continue
            simp = t2s.convert(name)
            if simp.endswith(MODERN_TITLE):
                stats["offices: modern titles (left out)"] += 1
                continue
            t = titles[simp]
            if not t["trad"]:
                t["trad"] = name
            if k == 0 and py and not t["py"]:
                t["py"] = py
            t["en"][en].add(d)
    rows = []
    for simp, t in sorted(titles.items()):
        def dyn(ds):
            return ", ".join(dynasty.get(d, (9999, "?"))[1] for d in sorted(ds, key=lambda d: dynasty.get(d, (9999,))[0]))
        first = {en: min(dynasty.get(d, (9999,))[0] for d in ds) for en, ds in t["en"].items()}
        senses = []
        for en in sorted(t["en"], key=lambda e: (first[e], e)):
            if en:
                senses.append(f"office title · {dyn(t['en'][en])}: {en}")
        untranslated = t["en"].get("")
        if untranslated:
            senses.append(f"office title ({dyn(untranslated)})")
        py = toned(list(t["trad"]), t["py"], readings, stats) if t["py"] else ""
        rows.append((simp, t["trad"], py, "", "/".join(fallback_sources.clean_sense(s) for s in senses), "cbdb"))
    stats["offices: rows"] = len(rows)
    return rows


def book_rows(con, t2s, readings, stats):
    """Rows (simp, trad, pinyin, defs) for book titles of 2-8 characters."""
    authors = collections.defaultdict(list)
    names = {}
    for tid, pid in con.execute("SELECT c_textid, c_personid FROM BIOG_TEXT_DATA WHERE c_role_id IN "
                                f"({','.join(map(str, AUTHOR_ROLES))}) ORDER BY c_textid, c_personid"):
        authors[tid].append(pid)
    for pid, name in con.execute("SELECT c_personid, c_name_chn FROM BIOG_MAIN"):
        names[pid] = name
    books = {}
    for tid, title, py, en in con.execute("SELECT c_textid, c_title_chn, c_title, c_title_trans FROM TEXT_CODES "
                                          "ORDER BY c_textid"):
        title = (title or "").strip()
        if not (2 <= len(title) <= 8) or not HAN(title):
            continue
        simp = t2s.convert(title)
        b = books.setdefault(simp, {"trad": title, "py": py, "en": set(), "authors": []})
        en = re.sub(r"\s+", " ", en or "").strip().strip("()")
        if en and en.lower() not in ("unknown", "unkonwn"):
            b["en"].add(en)
        for pid in authors.get(tid, []):
            if names.get(pid) and names[pid] not in b["authors"]:
                b["authors"].append(names[pid])
    rows = []
    for simp, b in sorted(books.items()):
        parts = ["book title"]
        if b["en"]:
            parts.append(sorted(b["en"])[0])
        if b["authors"]:
            more = f" +{len(b['authors']) - 2}" if len(b["authors"]) > 2 else ""
            parts.append("by " + ", ".join(b["authors"][:2]) + more)
        rows.append((simp, b["trad"], toned(list(b["trad"]), b["py"], readings, stats),
                     fallback_sources.clean_sense(" · ".join(parts))))
    stats["books: rows"] = len(rows)
    return rows


def write_books(rows, simplifier):
    def extra(con):
        con.execute("CREATE TABLE cbdb_books (simp TEXT NOT NULL, trad TEXT NOT NULL, pinyin TEXT NOT NULL, "
                    "defs TEXT NOT NULL, defs_simp TEXT)")
        out = []
        for simp, trad, py, defs in rows:
            ds = simplifier.convert(defs)
            out.append((simp, trad, py, defs, ds if ds != defs else None))
        con.executemany("INSERT INTO cbdb_books VALUES (?, ?, ?, ?, ?)", out)
        con.execute("CREATE INDEX cbdb_books_simp ON cbdb_books(simp)")
        con.execute("CREATE INDEX cbdb_books_trad ON cbdb_books(trad)")
    return extra


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", help="a CBDB SQLite file (default: the release in build/sources/cbdb/, "
                                     "downloaded when missing)")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (CC-CEDICT and the other dictionaries); "
                                                  "taken from the latest release when missing")
    ap.add_argument("--moe", default=DEFAULT_MOE, help="the plugin's MOE data (moe.sqlite)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--push", action="store_true", help=f"adb push the file to {fallback_sources.DEVICE_DIR}/")
    args = ap.parse_args()
    import opencc
    fallback_sources.ensure_db(args.db)
    if args.source:
        src, info = args.source, {}
    else:
        src, info = find_source(SRC_DIR)
    con = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    if not con.execute("SELECT 1 FROM sqlite_master WHERE name = 'OFFICE_CODES'").fetchone():
        sys.exit(f"{src} has no OFFICE_CODES table: is it CBDB?")
    t2s = opencc.OpenCC("t2s")
    simplifier = Simplifier("t2s")
    readings = Readings(args.db)
    cedict, known = known_words(args.db, args.moe)
    stats = collections.Counter()
    people = person_rows(con, t2s, readings, known, stats)
    offices = office_rows(con, t2s, readings, stats)
    books = book_rows(con, t2s, readings, stats)
    con.close()
    rows, covered = [], []
    for r in fallback_sources.font_safe_rows(people + offices, stats, "cbdb"):
        ds = simplifier.convert(r[4])
        r = (*r, ds if ds != r[4] else None)
        (covered if r[0] in cedict or r[1] in cedict else rows).append(r)
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")
    sha = info.get("sha256") or fallback_sources.sha256_of(src)
    meta = {"fallback_sources": "cbdb", "cbdb_rows": str(len(rows) + len(covered)),
            "cbdb_people": str(len(people)), "cbdb_offices": str(len(offices)), "cbdb_books": str(len(books)),
            "cbdb_file": os.path.basename(src), "cbdb_sha256": sha, "cbdb_date": info.get("generated_at_utc", ""),
            "cbdb_url": info.get("huggingface_url", ""), "cbdb_license": LICENSE}
    fallback_sources.write_local_file(args.out, rows, meta, "CBDB", extra=write_books(books, simplifier),
                                      covered=covered)
    print(f"CBDB: {len(people):,} people, {len(offices):,} office titles, {len(books):,} book titles "
          f"({len(covered):,} rows for words CC-CEDICT has) from {meta['cbdb_file']} "
          f"({meta['cbdb_date'][:10] or 'date unknown'}), SHA-256 {sha}")
    print(f"Wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB). {LICENSE}")
    fallback_sources.push_or_explain(args.out, args.push)


if __name__ == "__main__":
    main()
