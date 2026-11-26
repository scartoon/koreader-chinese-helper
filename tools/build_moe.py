#!/usr/bin/env python3
"""Build the bundled MOE data: 教育部《重編國語辭典修訂本》 and 《成語典》,
exactly as the Ministry of Education (Taiwan) publishes them, into
chinesehelper.koplugin/data/moe/ (shipped in the release zip, #86).

    .venv/bin/pip install opencc
    .venv/bin/python tools/build_moe.py          # after tools/build_db.py (or with the release's database)

Both dictionaries are licensed CC BY-ND 3.0 TW. The licence allows copying and
distributing them, commercial use included, but not modifying them, and use must
follow MOE's 使用說明 (usage notes). So:

  * MOE's tables (`revised`, `idioms`) hold one row per MOE record, every field
    as the official .xlsx has it, in MOE's column order and with MOE's column
    names. Only the format changes: the .xlsx's OOXML escapes (_x000D_ is a
    carriage return) are decoded, a cell's value is stored as text (numbers as
    the .xlsx writes them), an empty cell is NULL. Each row's rowid is its row
    in the sheet (the header is row 1). Characters MOE could not encode stay
    as MOE codes them (private-use characters, and &98ab._104_0.gif; image
    references): the popup draws □ for them. Nothing is simplified, dropped or
    rewritten here.
  * Our own tables, never MOE's text: `revised_keys` and `idioms_keys` (the
    headword and its OpenCC tw2s simplified form pointing to a MOE row, with
    whether CC-CEDICT has the word), `revised_hidden` (records with no key, and
    why: everyday combinations, numerals, headwords that are not 1-8 Han
    characters), and `meta` (source files, dates, SHA-256, licence,
    attribution, counts).
  * Next to the database: MOE's usage notes (pdf and odt, byte for byte) and
    LICENSE.txt with the licence URI and the attribution.

The source files are downloaded from MOE's open-data pages into
build/sources/moe-official/ when missing: the newest dated dictionary zips
(the text, not the 字圖 images) and the usage notes. Their names, dates and
SHA-256 go into meta and LICENSE.txt. CC-CEDICT's headwords come from the
plugin database (taken from the latest release when missing).
"""
import argparse
import os
import re
import shutil
import sqlite3
import sys
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fallback_sources  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/"
PAGES = {"revised": BASE + "dict_reviseddict_download.html", "idioms": BASE + "dict_idiomsdict_download.html"}
ZIP_RE = {"revised": r"download/dict_revised_(\d{4})_(\d{8})\.zip", "idioms": r"download/dict_idioms_(\d{4})_(\d{8})\.zip"}
# The files this script was written against (used when a page can't be read).
KNOWN = {"revised": "download/dict_revised_2015_20260929.zip", "idioms": "download/dict_idioms_2020_20260929.zip"}
NOTES = {"revised": ["reviseddict_10312.pdf", "reviseddict_10312.odt"],
         "idioms": ["idiomsdict_10409.pdf", "idiomsdict_10409.odt"]}
SRC_DIR = os.path.join(ROOT, "build", "sources", "moe-official")
OUT_DIR = os.path.join(ROOT, "chinesehelper.koplugin", "data", "moe")
DB_NAME = "moe.sqlite"
DEFAULT_DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
LICENSE_URI = "https://creativecommons.org/licenses/by-nd/3.0/tw/"
TITLES = {"revised": "重編國語辭典修訂本", "idioms": "成語典"}
SITES = {"revised": "http://dict.revised.moe.edu.tw/", "idioms": "http://dict.idioms.moe.edu.tw/"}
# The column holding the headword, and (成語典) the main/related flag.
HEAD = {"revised": "字詞名", "idioms": "成語"}

_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_ESCAPE = re.compile(r"_x([0-9A-Fa-f]{4})_")


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

def _get(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "koreader-chinese-helper build script"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def newest_zip(kind):
    """The newest dated dictionary zip linked on MOE's download page."""
    try:
        page = _get(PAGES[kind]).decode("utf-8", "replace")
        links = re.findall(ZIP_RE[kind], page)
        if links:
            year, day = max(links, key=lambda x: x[1])
            return BASE + f"download/dict_{kind}_{year}_{day}.zip"
        print(f"  (no dictionary zip linked on {PAGES[kind]}; using {KNOWN[kind]})")
    except Exception as e:  # noqa: BLE001
        print(f"  (could not read {PAGES[kind]}: {e}; using {KNOWN[kind]})")
    return BASE + KNOWN[kind]


def sources(src_dir, refresh=False):
    """{kind: zip path}, and the usage-note paths, downloading what is missing
    (with refresh: whenever MOE's page links a newer zip)."""
    out = {}
    for kind in ("revised", "idioms"):
        have = sorted((f for f in os.listdir(src_dir) if re.fullmatch(ZIP_RE[kind].split("/")[1], f)),
                      key=lambda f: re.fullmatch(ZIP_RE[kind].split("/")[1], f).group(2)) \
            if os.path.isdir(src_dir) else []
        if have and not refresh:
            out[kind] = os.path.join(src_dir, have[-1])
            continue
        url = newest_zip(kind)
        path = os.path.join(src_dir, os.path.basename(url))
        if not os.path.exists(path):
            fallback_sources.download_file(url, path)
        out[kind] = path
    notes = []
    for kind in ("revised", "idioms"):
        for name in NOTES[kind]:
            path = os.path.join(src_dir, name)
            if not os.path.exists(path):
                fallback_sources.download_file(BASE + name, path)
            notes.append(path)
    return out, notes


def xlsx_bytes(zip_path):
    """The dictionary .xlsx inside MOE's zip (not the 欄位說明 sheet), as
    (name, bytes)."""
    with zipfile.ZipFile(zip_path, metadata_encoding="cp950") as z:
        names = [n for n in z.namelist() if re.fullmatch(r"dict_\w+_\d{4}_\d{8}\.xlsx", n)]
        if len(names) != 1:
            sys.exit(f"{zip_path}: expected one dictionary .xlsx, found {names}")
        return names[0], z.read(names[0])


def unescape(text):
    """OOXML's escape of characters XML can't hold (ECMA-376 ST_Xstring):
    _x000D_ is a carriage return, _x005F_ an underscore."""
    return _ESCAPE.sub(lambda m: chr(int(m.group(1), 16)), text)


def _column(ref):
    n = 0
    for c in re.match(r"[A-Z]+", ref).group(0):
        n = n * 26 + ord(c) - 64
    return n - 1


def read_sheet(data):
    """(header, rows) of the first sheet: each row a list of str or None
    (empty cell), rows numbered from 2 (the sheet's own row numbers) as
    (number, values)."""
    import io
    z = zipfile.ZipFile(io.BytesIO(data))
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).iter(_NS + "si"):
            if si.find(_NS + "rPh") is not None:
                sys.exit("sharedStrings has phonetic runs: the reader does not handle them")
            shared.append(unescape("".join(t.text or "" for t in si.iter(_NS + "t"))))
    sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = []
    for r in sheet.iter(_NS + "row"):
        out = []
        for c in r.iter(_NS + "c"):
            i = _column(c.get("r"))
            out.extend([None] * (i - len(out)))
            v, t = c.find(_NS + "v"), c.get("t")
            if t == "s":
                out.append(shared[int(v.text)])
            elif t == "inlineStr":
                out.append(unescape("".join(x.text or "" for x in c.iter(_NS + "t"))))
            elif t in ("str", None, "n"):
                out.append(unescape(v.text) if v is not None and v.text is not None else None)
            else:
                sys.exit(f"cell {c.get('r')}: unhandled type {t}")
        rows.append((int(r.get("r")), out))
    header = rows[0][1]
    if rows[0][0] != 1 or any(h is None for h in header):
        sys.exit("unexpected header row")
    body = [(n, vals + [None] * (len(header) - len(vals))) for n, vals in rows[1:]]
    if any(len(vals) > len(header) for _n, vals in body):
        sys.exit("a row is wider than the header")
    return header, body


# ---------------------------------------------------------------------------
# Our tables
# ---------------------------------------------------------------------------

def first_reading(pinyin):
    """The 成語典's reading before any variant: "yī máo bù bá （變） yì máo bù
    bá" -> "yī máo bù bá". (Only to say whether a row has a reading: the popup
    reads the field itself.)"""
    pinyin = re.split(r"（[變又語讀]）|\(變\)", pinyin or "")[0]
    return unicodedata.normalize("NFC", re.sub(r"\s+", " ", pinyin.replace("　", " ")).strip())


def lines(text):
    return [x.strip() for x in (text or "").replace("\r", "").split("\n") if x.strip()]


def revised_keys(header, body, tw2s, cedict, measure, stats):
    """(keys, hidden): keys (simp, trad, rowid, covered), hidden (rowid, reason)."""
    col = {h: k for k, h in enumerate(header)}
    keys, hidden = [], []
    for n, vals in body:
        stats["revised: records"] += 1
        trad = vals[col["字詞名"]] or ""
        simp = tw2s.convert(trad)
        if not fallback_sources.han_word(trad) or not fallback_sources.han_word(simp):
            hidden.append((n, "not 1-8 Han characters"))
            stats["revised: not 1-8 Han characters (no key)"] += 1
            continue
        senses = lines(vals[col["釋義"]])
        protected = any(fallback_sources.HISTORICAL_MOE.search(x) for x in senses)
        reason = (fallback_sources.everyday(simp, cedict, measure, protected)
                  or fallback_sources.everyday(trad, cedict, measure, protected))
        if reason:
            hidden.append((n, reason))
            stats["revised: everyday combinations (no key): " + reason] += 1
            continue
        covered = int(simp in cedict or trad in cedict)
        stats["revised: keyed, CC-CEDICT has the word" if covered else "revised: keyed, not in CC-CEDICT"] += 1
        keys.append((simp, trad, n, covered))
    return keys, hidden


SEE_MAIN = re.compile(r"見「([^」]+)」條")


def idioms_keys(header, body, tw2s, cedict, stats):
    """(simp, trad, rowid, covered, main): main the rowid of a related entry's
    main entry (釋義 says 見「X」條), NULL otherwise."""
    col = {h: k for k, h in enumerate(header)}
    by_name = {(vals[col["成語"]] or "").strip(): n for n, vals in body}
    keys = []
    for n, vals in body:
        stats["idioms: records"] += 1
        trad = (vals[col["成語"]] or "").strip()
        simp = tw2s.convert(trad)
        if not fallback_sources.han_word(trad) or not fallback_sources.han_word(simp):
            stats["idioms: not 1-8 Han characters (no key)"] += 1
            continue
        m = SEE_MAIN.search(vals[col["釋義"]] or "")
        main = by_name.get(m.group(1)) if m and (vals[col["主條成語／非主條成語"]] or "").strip() != "主條成語" else None
        covered = int(simp in cedict or trad in cedict)
        stats["idioms: keyed, CC-CEDICT has the idiom" if covered else "idioms: keyed, not in CC-CEDICT"] += 1
        keys.append((simp, trad, n, covered, main))
    return keys


# Keep in step with chinesehelper.koplugin/ch_moe.lua (tests/test_moe.lua
# checks the plans).
KEYS_SCHEMA = """
CREATE TABLE revised_keys (simp TEXT NOT NULL, trad TEXT NOT NULL, id INTEGER NOT NULL, covered INTEGER NOT NULL);
CREATE TABLE revised_hidden (id INTEGER NOT NULL, reason TEXT NOT NULL);
CREATE TABLE idioms_keys (simp TEXT NOT NULL, trad TEXT NOT NULL, id INTEGER NOT NULL, covered INTEGER NOT NULL,
                          main INTEGER);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def write_moe_table(con, table, header, body):
    cols = ", ".join(quote(h) + " TEXT" for h in header)
    con.execute(f"CREATE TABLE {table} ({cols})")
    marks = ", ".join("?" * (len(header) + 1))
    con.executemany(f"INSERT INTO {table} (rowid, {', '.join(quote(h) for h in header)}) VALUES ({marks})",
                    [(n, *vals) for n, vals in body])


def attribution(kind, version):
    return (f"中華民國教育部（Ministry of Education, R.O.C.）。《{TITLES[kind]}》"
            f"（版本編號：{version}）網址：{SITES[kind]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=SRC_DIR, help="where MOE's downloads are kept (downloaded when missing)")
    ap.add_argument("--refresh", action="store_true", help="check MOE's pages for newer files")
    ap.add_argument("--db", default=DEFAULT_DB, help="the plugin database (for CC-CEDICT's headwords)")
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    import opencc
    tw2s = opencc.OpenCC("tw2s")
    fallback_sources.ensure_db(args.db)
    cedict, measure = fallback_sources.cedict_forms(args.db)
    zips, notes = sources(args.src, args.refresh)

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, DB_NAME)
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.executescript(KEYS_SCHEMA)
    stats = Counter()
    meta = {"license_uri": LICENSE_URI, "built": date.today().isoformat()}
    for kind in ("revised", "idioms"):
        zpath = zips[kind]
        day = re.search(r"_(\d{8})\.zip$", zpath).group(1)
        version = f"{day[:4]}-{day[4:6]}-{day[6:]}"
        name, data = xlsx_bytes(zpath)
        header, body = read_sheet(data)
        write_moe_table(con, kind, header, body)
        if kind == "revised":
            keys, hidden = revised_keys(header, body, tw2s, cedict, measure, stats)
            con.executemany("INSERT INTO revised_keys VALUES (?, ?, ?, ?)", keys)
            con.executemany("INSERT INTO revised_hidden VALUES (?, ?)", hidden)
        else:
            keys = idioms_keys(header, body, tw2s, cedict, stats)
            con.executemany("INSERT INTO idioms_keys VALUES (?, ?, ?, ?, ?)", keys)
        meta.update({f"{kind}_version": version, f"{kind}_file": os.path.basename(zpath),
                     f"{kind}_sha256": fallback_sources.sha256_of(zpath), f"{kind}_xlsx": name,
                     f"{kind}_url": PAGES[kind], f"{kind}_records": str(len(body)),
                     f"{kind}_keys": str(len(keys)), f"{kind}_attribution": attribution(kind, version),
                     f"{kind}_columns": "\t".join(header)})
        print(f"{TITLES[kind]} {version}: {len(body):,} records, {len(keys):,} keys")
    for table in ("revised_keys", "idioms_keys"):
        con.execute(f"CREATE INDEX {table}_simp ON {table}(simp)")
        con.execute(f"CREATE INDEX {table}_trad ON {table}(trad)")
    con.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
    con.commit()
    con.execute("VACUUM")
    con.close()
    for k in sorted(stats):
        print(f"  {k}: {stats[k]:,}")

    for note in notes:
        shutil.copyfile(note, os.path.join(args.out, os.path.basename(note)))
    with open(os.path.join(args.out, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write(license_text(meta, notes))
    print(f"Wrote {path} ({os.path.getsize(path) / 1e6:.1f} MB), the usage notes and LICENSE.txt")


def license_text(meta, notes):
    out = ["MOE dictionaries bundled with Chinese helper",
           "",
           "This folder holds two dictionaries of the Ministry of Education, Republic of China (Taiwan),",
           "unmodified, under the Creative Commons Attribution-NoDerivs 3.0 Taiwan licence (CC BY-ND 3.0 TW):",
           meta["license_uri"],
           "They are not under the plugin's GPL or the CC BY-SA licence of its other data.",
           ""]
    for kind in ("revised", "idioms"):
        out += [meta[f"{kind}_attribution"],
                f"  Source file: {meta[f'{kind}_file']} ({meta[f'{kind}_xlsx']}),"
                f" SHA-256 {meta[f'{kind}_sha256']}",
                f"  From: {meta[f'{kind}_url']}",
                f"  {int(meta[f'{kind}_records']):,} records, every field as published.",
                ""]
    out += ["moe.sqlite: the tables `revised` and `idioms` are MOE's sheets, one row per record, every field",
            "as published; only the format is converted (from .xlsx to SQLite). Characters MOE could not",
            "encode are kept as MOE codes them. The other tables (revised_keys, revised_hidden, idioms_keys,",
            "meta) are Chinese helper's own lookup data and never contain MOE's text.",
            "",
            "MOE's usage notes (使用說明), byte for byte as published:"]
    out += [f"  {os.path.basename(n)}" for n in notes]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    main()
