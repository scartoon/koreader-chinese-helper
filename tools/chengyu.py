"""Chengyu: the Xinhua idiom data from chinese-xinhua (tools/build_xinhua.py),
built into the user's own file, never the release (text scraped from a
published dictionary). (The 成語典 is bundled since 2.28.0, #86: MOE's own
data, tools/build_moe.py, shown by chinesehelper.koplugin/ch_moe.lua.)

Each file holds three tables:

  fallback  the same table as every fallback dictionary
            (tools/fallback_sources.py), for the idioms CC-CEDICT lacks:
            (simp, trad, pinyin, "", short, source), source "xinhua".
            The popup shows them like any fallback entry.
  idioms    (simp, trad, short, view, short_simp, view_simp) for every idiom the source has,
            CC-CEDICT's too: `short` is the one line of Chinese explanation
            the popup adds under an English entry, `view` the text of the
            出处 view (source text, the story, usage, examples), "" when the
            source has nothing beyond the short line. short and view are the
            source's own text; short_simp and view_simp are NULL (Xinhua is
            simplified already; the columns date from the user-built 成語典
            file, #48).
  meta      source, version, counts, licence.

Xinhua never decides readings: its pinyin is only shown on its own
fallback entries.

Xinhua (data/idiom.json): 30,895 idioms with explanation, derivation (the
classical source) and example, simplified, scraped from a published
dictionary; the scraping lost punctuation. Repaired here, where it can be
done reliably (clean_xinhua_* below; tests/test_chengyu.py):
  * the colon after a glossed word: 首鼠鼠性多疑 -> 首鼠：鼠性多疑, for a
    two-character part of the idiom starting a clause, and a one-character
    part after a 「；」 in the same list of glosses;
  * the colon and opening quote after the source's title: 《史记·…》武安已罢朝
    …” -> 《史记·…》：“武安已罢朝…”, when the title is followed directly by
    the text or by a numbered section (第十二回, 卷三);
  * an opening quote before a quoted idiom: 亦作各霸一方” -> 亦作“各霸一方”;
  * 曰‘ -> 曰：‘;
  * ◇ (the dictionary's sign before an extended sense) -> 。;
  * ★ before an example's source -> ——;
  * ～ (the idiom itself) in examples -> the idiom.
Not repaired: typos (右动摇 for 或动摇), titles followed by other words (诗,
词, 引《…》), which can't be told apart from the text reliably.
"""
import json
import re
import unicodedata
import xml.etree.ElementTree as ET
import zipfile

HAN = "㐀-䶿一-鿿豈-﫿"
HAN_ONLY = re.compile(f"[{HAN}]+")
# Characters the device fonts draw as a box: private-use (the 成語典's own
# glyphs) and anything outside the BMP. A line containing one is dropped.
BOXES = re.compile("[-\U00010000-\U0010ffff]")

SHORT_MAX = 90          # characters in the popup's short line, cut at a sentence end
VIEW_LIST_MAX = 6       # citations or example sentences kept in the 出处 view

# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------


def no_boxes(lines, stats=None, name=""):
    out = [x for x in lines if not BOXES.search(x)]
    if stats is not None and len(out) < len(lines):
        stats[f"{name}: lines with characters fonts draw as a box (dropped)"] += len(lines) - len(out)
    return out


def shorten(text, limit=SHORT_MAX):
    """`text` cut after the last sentence end within `limit` characters (or
    left whole when no sentence ends there)."""
    if len(text) <= limit:
        return text
    cut = max(text.rfind(p, 0, limit) for p in "。；！？")
    return text[:cut + 1] if cut > 0 else text


def view_text(sections):
    """The 出处 view: (heading, [lines]) sections, empty ones left out."""
    out = []
    for heading, lines in sections:
        lines = [x for x in lines if x]
        if lines:
            out.append((heading + "\n" if heading else "") + "\n".join(lines))
    return "\n\n".join(out)


# ---------------------------------------------------------------------------
# Xinhua
# ---------------------------------------------------------------------------

PUNCT = "，。；：、！？“”‘’《》（）「」…—"
NUM = "0-9０-９一二三四五六七八九十百千零〇○两"
# A source title at the start of a citation: optional "语出"/"语本",
# dynasty·author, one or more 《…》 (with a stray doubled 》), then optionally
# a section that can't be part of the text (第十二回, 卷三, 诗之二, 头折).
TITLE = re.compile(
    rf"((?:语出|语本|语见|出自)?[^《“”‘’，。；]{{0,16}}?《[^《》]+》》?"
    rf"(?:第[{NUM}]+[回卷章折出篇节齣幕首]|卷[{NUM}]+(?:之[{NUM}]+)?|[上中下]篇|[诗词]之[{NUM}]+|头折|楔子)?)(.)")
# After a title, 诗 or 词 may name the kind of work (《曲江》诗) or start
# the quotation (诗云): left alone.
AMBIGUOUS = re.compile("[诗词]")
# Circled numbers before senses: ①指… ②比喻… (the fonts may lack them).
CIRCLED = {chr(0x2460 + k): f"{k + 1}." for k in range(10)}
SEE = re.compile(r"^(?:参)?见[^“”]+”。?$")


def lost(text):
    """Signs the scraping left where text was lost (沐猴：猕猴；冠：戴帽子★子穿衣,
    变化∶象云彩, 迅速≤快地来): any math or other symbol, shown as an ellipsis.
    The ○ of 第一○五回 is kept."""
    out = []
    for ch in text:
        if ch not in "○～" and unicodedata.category(ch) in ("Sm", "So") and ch not in CIRCLED:
            ch = "…"
        out.append(ch)
    return "".join(out)


def circled(text):
    return "".join(CIRCLED.get(ch, ch) for ch in text)


def _colon_glosses(word, text):
    """Restore the colons after glossed parts of the idiom (see the module
    docstring). Only the first sentence holds glosses, and only when
    something follows them: a further sentence or clause (有国家却不能回去
    is the whole explanation of 有国难投, not 有国 glossed)."""
    sentences = text.split("。")
    first = sentences[0]
    clauses = first.split("；")
    if len(clauses) < 2 and not "".join(sentences[1:]).strip():
        return text
    fixed, glossed = [], False
    for k, cl in enumerate(clauses):
        best = 0
        for n in range(min(len(word), len(cl) - 1), 0, -1):
            if cl[:n] in word:
                best = n
                break
        rest = cl[best:]
        if best == 2 and rest and rest[0] not in PUNCT and best < len(word):
            cl, glossed = cl[:best] + "：" + rest, True
        elif best == 1 and k > 0 and glossed and rest and rest[0] not in PUNCT:
            cl = cl[:1] + "：" + rest
        fixed.append(cl)
    sentences[0] = "；".join(fixed)
    return "。".join(sentences)


VARIANT_LEAD = "亦作|也作|又作|亦称|也称|又称|亦说|也说|又说|同|见|参见|省作|简作|略作"


def _open_quotes(text):
    """亦作各霸一方” -> 亦作“各霸一方”, and the next of a list (“凤泊鸾飘”、
    飘鸾泊凤” -> 、“飘鸾泊凤”): a closing quote after Han characters with no
    opening quote before it."""
    def fix(m):
        before = text[:m.start()]
        if before.count("“") > before.count("”"):
            return m.group(0)
        return m.group(1) + "“" + m.group(2) + "”"
    text = re.sub(rf"((?:{VARIANT_LEAD}))([{HAN}]{{2,12}})”", fix, text)
    return re.sub(rf"(”、)([{HAN}]{{2,12}})”", lambda m: m.group(1) + "“" + m.group(2) + "”", text)


def _quote_citations(text):
    """《title》text” -> 《title》：“text”, for each citation in turn (a
    derivation may quote several sources), stopping at the first that can't
    be repaired reliably."""
    out, pos = [], 0
    while pos < len(text):
        m = TITLE.match(text, pos)
        end = text.find("”", pos)
        if not m or end < 0 or m.end(1) > end:
            break
        body = text[m.end(1):end]
        if m.group(2) in PUNCT or "“" in body or AMBIGUOUS.match(body):
            break
        out.append(text[pos:m.end(1)] + "：“" + body + "”")
        pos = end + 1
        if text.startswith("。", pos):
            out.append("。")
            pos += 1
    return "".join(out) + text[pos:]


def clean_xinhua_explanation(word, text):
    text = (text or "").strip()
    if text in ("", "无"):
        return ""
    text = re.sub("◇", lambda m: "" if m.start() and text[m.start() - 1] in PUNCT else "。", text)
    text = circled(lost(text))
    text = _open_quotes(text)
    text = _colon_glosses(word, text)
    return text


def clean_xinhua_derivation(text, word=""):
    text = (text or "").strip()
    if text in ("", "无") or SEE.match(text):
        return ""
    text = text.replace("》》", "》").replace("◇", "。")
    if word:
        text = text.replace("～", word)
    text = circled(lost(text))
    text = re.sub(r"(?<=[曰云道])‘", "：‘", text)
    if "“" not in text:
        text = _quote_citations(text)
    return text


def clean_xinhua_example(word, text):
    text = (text or "").strip()
    if text in ("", "无"):
        return ""
    text = text.replace("～", word).replace("◇", "。")
    text = re.sub(r"\s*★\s*", " ——", text, count=1)
    return circled(lost(text))


def xinhua_entries(path, stats):
    """The idioms of data/idiom.json as dicts {simp, pinyin, short, sections},
    Han-only words of 4+ characters (the popup's context stops at
    punctuation; the 3-character entries include scraping fragments such as
    沧横流)."""
    out = []
    for x in json.load(open(path, encoding="utf-8")):
        stats["xinhua: entries read"] += 1
        word = (x.get("word") or "").strip()
        if not HAN_ONLY.fullmatch(word):
            stats["xinhua: not Han-only (dropped)"] += 1
            continue
        if len(word) < 4 or len(word) > 8:
            stats["xinhua: not 4-8 characters (dropped)"] += 1
            continue
        expl = clean_xinhua_explanation(word, x.get("explanation"))
        der = clean_xinhua_derivation(x.get("derivation"), word)
        ex = clean_xinhua_example(word, x.get("example"))
        if expl != (x.get("explanation") or "").strip():
            stats["xinhua: explanations repaired"] += 1
        if der and der != (x.get("derivation") or "").strip():
            stats["xinhua: derivations repaired"] += 1
        lines = [no_boxes([s], stats, "xinhua") for s in (expl, der, ex)]
        expl, der, ex = (y[0] if y else "" for y in lines)
        if not expl:
            stats["xinhua: no explanation (dropped)"] += 1
            continue
        view = [("释义", [expl]), ("出处", [der]), ("例句", [ex])] if (der or ex) else []
        out.append({"simp": word, "pinyin": unicodedata.normalize("NFC", (x.get("pinyin") or "").strip()),
                    "short": shorten(expl), "sections": view})
    return out


# ---------------------------------------------------------------------------
# The file
# ---------------------------------------------------------------------------

IDIOMS_SCHEMA = """
    CREATE TABLE idioms (simp TEXT NOT NULL, trad TEXT NOT NULL, short TEXT NOT NULL, view TEXT NOT NULL,
                         short_simp TEXT, view_simp TEXT);
"""


# Keep in step with DB.idiomsSql in chinesehelper.koplugin/ch_db.lua
# (tests/test_db.lua checks that they match). simp: also read short_simp and
# view_simp (files built from 2.13.0 on).
def idioms_sql(n, simp=False):
    marks = ",".join("?" * n)
    cols = "simp, trad, short, view" + (", short_simp, view_simp" if simp else "")
    return (f"SELECT {cols} FROM idioms WHERE simp IN ({marks}) "
            f"OR trad IN ({marks}) ORDER BY rowid")


def write_idioms(con, rows):
    """rows: (simp, trad, short, view[, short_simp, view_simp]); a simplified
    text the same as the original is stored as NULL."""
    full = set()
    for r in rows:
        short_simp = r[4] if len(r) > 4 else None
        view_simp = r[5] if len(r) > 5 else None
        full.add((*r[:4], short_simp if short_simp != r[2] else None, view_simp if view_simp != r[3] else None))
    con.executescript(IDIOMS_SCHEMA)
    con.executemany("INSERT INTO idioms VALUES (?, ?, ?, ?, ?, ?)",
                    sorted(full, key=lambda r: (*r[:4], r[4] or "", r[5] or "")))
    con.execute("CREATE INDEX idioms_simp ON idioms(simp)")
    con.execute("CREATE INDEX idioms_trad ON idioms(trad)")
    for n in (1, 16):
        plan = "\n".join(r[3] for r in con.execute("EXPLAIN QUERY PLAN " + idioms_sql(n, True), ["x"] * (2 * n)))
        if "USING INDEX idioms_simp" not in plan or "USING INDEX idioms_trad" not in plan:
            raise SystemExit(f"idioms lookup does not use its indexes:\n{plan}")


def tables(entries, source, cedict, stats):
    """entries: dicts {simp, trad, pinyin, short, view} (final text), with
    short_simp and view_simp when the text has a simplified version. Returns
    (fallback rows, idioms rows)."""
    fallback, idioms = [], []
    for e in entries:
        simp, trad = e["simp"], e["trad"]
        if not HAN_ONLY.fullmatch(simp) or not HAN_ONLY.fullmatch(trad):
            stats[f"{source}: headword not Han-only after conversion (dropped)"] += 1
            continue
        if not e["short"] and not e["view"]:
            continue
        short_simp, view_simp = e.get("short_simp"), e.get("view_simp")
        idioms.append((simp, trad, e["short"], e["view"], short_simp, view_simp))
        if e["view"]:
            stats[f"{source}: idioms with a 出处 view"] += 1
        if simp in cedict or trad in cedict:
            stats[f"{source}: CC-CEDICT has the idiom (short line and view only)"] += 1
        elif e["short"]:
            fallback.append((simp, trad, e["pinyin"], "", e["short"].replace("/", "／"), source,
                             short_simp.replace("/", "／") if short_simp else None))
    stats[f"{source}: idioms rows"] = len(set(idioms))
    stats[f"{source}: fallback rows"] = len(set(fallback))
    return fallback, idioms
