"""Fallback dictionaries: the sources the popup consults for candidate words
CC-CEDICT has no entry for (shared by tools/build_db.py, tools/build_moe.py and
tools/measure_fallback.py).

Every source becomes rows in the same shape as CC-CEDICT's `entries`:

    (simp, trad, pinyin, syllables, defs, source)

    simp, trad  the headword's simplified and traditional forms (the same
                string when they do not differ); the popup looks words up by
                either
    pinyin      the source's own reading, as the source writes it (MOE's are
                Taiwan standard)
    syllables   "" (fallback entries take no part in reading markers)
    defs        senses joined with "/" as in CC-CEDICT; a "/" inside a sense is
                written as a full-width "／"
    source      "wikt" or "moe"

What every source gets (the plugin can only ever match these):
  * headwords of 1-8 Han characters only: the popup's context stops at any
    other character, so 卡拉OK or 996 can never be looked up;
  * no row for a headword CC-CEDICT has, in either form: CC-CEDICT stays the
    only entry for its words;
  * no everyday combinations (see everyday()) and no numerals.

Sources:
  wikt  English Wiktionary's Chinese entries, from kaikki.org's wiktextract
        extraction (CC BY-SA 4.0): Mandarin readings only, dialect-only senses
        dropped, soft redirects (simplified pages) and alternative forms
        resolved to their entries, entries that only name places dropped.
  moe   教育部《重編國語辭典修訂本》 via g0v/moedict-data (CC BY-ND 3.0 TW):
        built only into the user's own local file, never the release.
"""
import gzip
import json
import lzma
import re
import sqlite3
import unicodedata
from collections import OrderedDict

HAN = "㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f"
HAN_WORD = re.compile(f"[{HAN}]{{1,8}}")


def han_word(w):
    return bool(w) and HAN_WORD.fullmatch(w) is not None


def cedict_forms(db_path):
    """Every CC-CEDICT headword (simplified and traditional) and the measure
    words its senses name ("CL: 个 gè, 件 jiàn"), from the plugin database."""
    con = sqlite3.connect(db_path)
    forms, measure = set(), set()
    for simp, trad, defs in con.execute("SELECT simp, trad, defs FROM entries"):
        forms.add(simp)
        forms.add(trad)
        for m in re.finditer(r"CL: ([^/]+)", defs):
            for part in m.group(1).split(","):
                word = part.strip().split(" ")[0]
                if len(word) == 1:
                    measure.add(word)
    con.close()
    return forms, measure


# ---------------------------------------------------------------------------
# Everyday combinations: closed-class words glued to a word CC-CEDICT has.
# CC-CEDICT leaves these out on purpose (很多 = 很 + 多); Wiktionary and MOE
# list some, and in the popup they add a block that says nothing new, or
# match across a word boundary (地中 in 盆地中心).
# ---------------------------------------------------------------------------

NUMERALS = set("零〇一二两兩三四五六七八九十百千万萬亿億几幾半廿卅数數")
DEMONSTRATIVES = set("这這那哪每各某此该該本其另")
PRONOUNS = set("我你他她它您咱")
DEGREE = set("很太最更挺极極超颇頗较較")
ADVERBS = set("也都就才又还還却卻只便再不没沒别別已")
LOCATIVES = set("上下里裡裏中内內外前后後边邊面头頭间間旁")
PARTICLES = set("的地得了着著过過吗嗎呢吧啊呀")
TIME_UNITS = set("年月日天时時点點分秒岁歲周週代辈輩夜晚")
# Entries their source marks as historical or classical are never treated as
# everyday combinations (六部, 九卿, 三省): they are the vocabulary the
# fallback is for. Wiktionary: the sense qualifiers; MOE: the definition.
HISTORICAL_WIKT = re.compile(r"^\((?:[^)]*\b)?(historical|Classical|literary|archaic|obsolete)\b")
HISTORICAL_MOE = re.compile(r"職官名|官署名|官名|古代|古時|舊時|朝代|典出|語本|語出|文言|古稱|爵位|官職")


def everyday(word, cedict, measure=frozenset(), protected=False):
    """Why `word` is an everyday combination, or None. `cedict`: CC-CEDICT's
    headwords (single characters included). `protected`: the source marks the
    entry historical or classical (only a bare numeral is still dropped)."""
    if len(word) < 2:
        return None
    if all(c in NUMERALS for c in word):
        return "numeral"
    if protected:
        return None
    rest = word.lstrip("".join(NUMERALS))
    if rest != word and rest and (rest in measure or rest in TIME_UNITS or
                                  (rest[0] in measure and rest[1:] in cedict)):
        return "number + measure word"
    first, tail = word[0], word[1:]
    if tail in cedict:
        if first in DEMONSTRATIVES:
            return "demonstrative + word"
        if first in DEGREE:
            return "degree adverb + word"
        if first in PRONOUNS:
            return "pronoun + word"
        if first in ADVERBS:
            return "adverb + word"
    head, last = word[:-1], word[-1]
    if head in cedict:
        if last in LOCATIVES:
            return "word + locative"
        if last in PARTICLES:
            return "word + particle"
    return None


# ---------------------------------------------------------------------------
# Wiktionary (kaikki.org wiktextract JSONL)
# ---------------------------------------------------------------------------

DIALECT_TAGS = {"Cantonese", "Hokkien", "Hakka", "Teochew", "Wu", "Shanghainese", "Min", "Min-Nan", "Min-Dong",
                "Xiang", "Gan", "Jin", "Taishanese", "Puxian-Min", "Northern-Min", "Eastern-Min", "Southern-Min",
                "Leizhou-Min", "Hainanese", "Dungan", "Zhangzhou-Hokkien", "Xiamen", "Quanzhou",
                "Singapore-Hokkien", "Hong-Kong-Cantonese", "Guangzhou"}
MANDARIN_TAGS = {"Mandarin", "Standard-Chinese", "Taiwanese-Mandarin", "Beijing", "Northeastern-Mandarin",
                 "Southwestern-Mandarin", "Jianghuai-Mandarin"}
ALT_GLOSS = re.compile(r"^(alternative|alternative form|variant|obsolete form|archaic form|simplified form|"
                       r"traditional form|abbreviation|misspelling|erhua form|eye dialect|clipping|"
                       r"short form|alternative name)s? (form )?of\b", re.I)
PLACE_GLOSS = re.compile(r"\b(town|township|village|subdistrict|county|district|prefecture|city|river|mountain|"
                         r"island|province|lake|commune|neighbourhood|neighborhood|borough|municipality|"
                         r"railway station|station|street|road)\b", re.I)


def clean_sense(text):
    return text.replace("/", "／").replace("\t", " ").strip()


def mandarin_pinyin(entry):
    """The entry's Mandarin pinyin (mainland before Taiwan), or None."""
    found = [s for s in entry.get("sounds", []) if s.get("zh_pron") and "Mandarin" in (s.get("tags") or [])
             and "Pinyin" in (s.get("tags") or [])]
    if not found:
        return None
    plain = [s for s in found if "Taiwan" not in (s.get("tags") or [])]
    # Some entries add the numbered form in brackets: "xiàn (xian⁴)".
    pinyin = re.sub(r"\s*\([^)]*\)", "", (plain or found)[0]["zh_pron"]).strip()
    return unicodedata.normalize("NFC", pinyin) or None


def read_wiktionary(path, stats):
    """{word: {"pinyin": {pinyin: [senses]}, "simp": set, "alts": set}} from a
    kaikki.org Chinese JSONL(.gz), plus {redirected form: set(targets)}."""
    entries, redirects = OrderedDict(), {}
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            if e.get("lang_code") != "zh":
                continue
            word = e.get("word", "")
            if e.get("pos") == "soft-redirect":
                redirects.setdefault(word, set()).update(e.get("redirects") or [])
                continue
            stats["wikt: entries read"] += 1
            pinyin = mandarin_pinyin(e)
            if not pinyin:
                stats["wikt: no Mandarin reading (dropped)"] += 1
                continue
            senses, alts, places = [], set(), 0
            for s in e.get("senses", []):
                tags = set(s.get("tags") or [])
                if tags & DIALECT_TAGS and not tags & MANDARIN_TAGS:
                    stats["wikt: dialect-only senses (dropped)"] += 1
                    continue
                gloss = (s.get("glosses") or [""])[-1]
                if s.get("alt_of") or s.get("form_of") or ALT_GLOSS.match(gloss or ""):
                    for t in (s.get("alt_of") or []) + (s.get("form_of") or []):
                        if t.get("word"):
                            alts.add(t["word"])
                    continue
                if not gloss or "no-gloss" in tags:
                    continue
                raw = (s.get("raw_glosses") or [gloss])[-1]
                senses.append(clean_sense(raw))
                if PLACE_GLOSS.search(gloss):
                    places += 1
            if senses and e.get("pos") == "name" and places == len(senses):
                stats["wikt: place names only (dropped)"] += 1
                continue
            ent = entries.setdefault(word, {"pinyin": OrderedDict(), "simp": set(), "alts": set()})
            if senses:
                bucket = ent["pinyin"].setdefault(pinyin, [])
                bucket.extend(s for s in senses if s not in bucket)
            else:
                ent["alts"].update(alts)
            for fm in e.get("forms", []):
                if "Simplified-Chinese" in (fm.get("tags") or []) and fm.get("form"):
                    ent["simp"].add(fm["form"])
    return entries, redirects


def wiktionary_rows(path, cedict, measure, stats, dropped=None):
    """Rows (simp, trad, pinyin, syllables, defs, "wikt") for the fallback table."""
    entries, redirects = read_wiktionary(path, stats)
    simp_of = {}
    for form, targets in redirects.items():
        for t in targets:
            simp_of.setdefault(t, set()).add(form)
    rows = []

    def emit(simp, trad, pinyin, senses):
        for form in (simp, trad):
            if not han_word(form):
                stats["wikt: rows not Han-only 1-8 (dropped)"] += 1
                return
        if simp in cedict or trad in cedict:
            stats["wikt: rows CC-CEDICT has (dropped)"] += 1
            return
        protected = any(HISTORICAL_WIKT.match(x) for x in senses)
        reason = everyday(simp, cedict, measure, protected) or everyday(trad, cedict, measure, protected)
        if reason:
            stats["wikt: everyday combinations (dropped): " + reason] += 1
            if dropped is not None:
                dropped.append((simp, reason, senses[0] if senses else ""))
            return
        rows.append((simp, trad, pinyin, "", "/".join(senses), "wikt"))

    for word, ent in entries.items():
        senses_by_py = ent["pinyin"]
        if not senses_by_py and ent["alts"]:
            # Only "alternative form of X": the entry of X, under this form.
            target = next((t for t in sorted(ent["alts"]) if entries.get(t, {}).get("pinyin")), None)
            if not target:
                stats["wikt: alternative forms without a target (dropped)"] += 1
                continue
            senses_by_py = OrderedDict((py, [f"variant of {target}"] + s)
                                       for py, s in entries[target]["pinyin"].items())
            stats["wikt: alternative forms resolved"] += 1
        simps = sorted(ent["simp"] | simp_of.get(word, set())) or [word]
        for simp in simps:
            for pinyin, senses in senses_by_py.items():
                emit(simp, word, pinyin, senses)
    stats["wikt: rows"] = len(rows)
    return rows


# ---------------------------------------------------------------------------
# MOE 重編國語辭典修訂本 (g0v/moedict-data dict-revised.json.xz)
# ---------------------------------------------------------------------------

PUA = re.compile("[-]|\\{\\[[0-9a-f]+\\]\\}")


def moe_rows(path, cedict, measure, stats, dropped=None):
    """Rows (simp, trad, pinyin, syllables, defs, "moe"). The simplified form is
    OpenCC's tw2s (characters only: tw2sp would also swap vocabulary, 滑鼠 ->
    鼠标, and index a word under another word)."""
    import opencc
    tw2s = opencc.OpenCC("tw2s")
    rows = []
    for e in json.load(lzma.open(path, "rt", encoding="utf-8")):
        stats["moe: entries read"] += 1
        trad = e.get("title", "")
        if PUA.search(trad):
            stats["moe: private-use characters in headword (dropped)"] += 1
            continue
        simp = tw2s.convert(trad)
        if not han_word(trad) or not han_word(simp):
            stats["moe: not Han-only 1-8 (dropped)"] += 1
            continue
        if simp in cedict or trad in cedict:
            stats["moe: CC-CEDICT has the headword (dropped)"] += 1
            continue
        hets = []
        for het in e.get("heteronyms") or []:
            senses = []
            for d in het.get("definitions") or []:
                text = d.get("def", "")
                if PUA.search(text):
                    text = PUA.sub("□", text)
                    stats["moe: senses with private-use characters (shown as □)"] += 1
                if text:
                    senses.append(clean_sense(text))
            if senses:
                hets.append((unicodedata.normalize("NFC", het.get("pinyin") or ""), senses))
        protected = any(HISTORICAL_MOE.search(x) for _, senses in hets for x in senses)
        reason = everyday(simp, cedict, measure, protected) or everyday(trad, cedict, measure, protected)
        if reason:
            stats["moe: everyday combinations (dropped): " + reason] += 1
            if dropped is not None:
                dropped.append((simp, reason, hets[0][1][0] if hets else ""))
            continue
        for pinyin, senses in hets:
            rows.append((simp, trad, pinyin, "", "/".join(senses), "moe"))
    stats["moe: rows"] = len(rows)
    return rows


# ---------------------------------------------------------------------------
# The fallback table: the same in the release database (Wiktionary) and in the
# user's own MOE file, so the plugin queries both with the same SQL.
# ---------------------------------------------------------------------------

FALLBACK_SCHEMA = """
    CREATE TABLE fallback (simp TEXT NOT NULL, trad TEXT NOT NULL, pinyin TEXT NOT NULL,
                           syllables TEXT NOT NULL, defs TEXT NOT NULL, source TEXT NOT NULL);
"""


def write_fallback(con, rows):
    """Create and fill the fallback table, rows in a stable order (the build
    is reproducible), with indexes on both forms like `entries`."""
    con.executescript(FALLBACK_SCHEMA)
    con.executemany("INSERT INTO fallback VALUES (?, ?, ?, ?, ?, ?)", sorted(set(rows)))
    con.execute("CREATE INDEX fallback_simp ON fallback(simp)")
    con.execute("CREATE INDEX fallback_trad ON fallback(trad)")


# Keep in step with DB.fallbackSql in chinesehelper.koplugin/ch_db.lua
# (tests/test_db.lua checks that they match).
def fallback_sql(n):
    marks = ",".join("?" * n)
    return (f"SELECT simp, trad, pinyin, syllables, defs, source FROM fallback WHERE simp IN ({marks}) "
            f"OR trad IN ({marks}) ORDER BY rowid")


def forms_from_entries(entries):
    """cedict_forms() from build_db.py's entry tuples (simp, trad, pinyin,
    syllables, defs) instead of a built database."""
    forms, measure = set(), set()
    for simp, trad, _py, _syl, defs in entries:
        forms.add(simp)
        forms.add(trad)
        for m in re.finditer(r"CL: ([^/]+)", defs):
            for part in m.group(1).split(","):
                word = part.strip().split(" ")[0]
                if len(word) == 1:
                    measure.add(word)
    return forms, measure
