"""Chengyu sources: 教育部《成語典》 (tools/build_idioms.py) and the Xinhua
idiom data from chinese-xinhua (tools/build_xinhua.py). Both are built into
the user's own files, never the release (CC BY-ND, and text scraped from a
published dictionary).

Each file holds three tables:

  fallback  the same table as every fallback dictionary
            (tools/fallback_sources.py), for the idioms CC-CEDICT lacks:
            (simp, trad, pinyin, "", short, source), source "idioms" or
            "xinhua". The popup shows them like any fallback entry.
  idioms    (simp, trad, short, view) for every idiom the source has,
            CC-CEDICT's too: `short` is the one line of Chinese explanation
            the popup adds under an English entry, `view` the text of the
            出处 view (source text, the story, usage, examples), "" when the
            source has nothing beyond the short line.
  meta      source, version, counts, licence.

Neither source decides readings: their pinyin is only shown on their own
fallback entries.

成語典 (dict_idioms_2020_*.xlsx, Taiwan Ministry of Education, CC BY-ND 3.0
TW): 1,664 main entries (主條) with every field, and about 3,800 related
entries (非主條) that name their main entry ("見「X」條") and carry only their
own explanation and citations. Text is traditional and goes through
simplify.py's Simplifier("tw2s"). Markup in the file: _x000D_ (a carriage
return), *N* before a word that has note N, newlines around those words,
and # before a paragraph of context around the passage.

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
# xlsx (the standard library is enough: one sheet, shared strings)
# ---------------------------------------------------------------------------

_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def _column(ref):
    n = 0
    for c in re.match(r"[A-Z]+", ref).group(0):
        n = n * 26 + ord(c) - 64
    return n - 1


def read_xlsx(path):
    """The first sheet's rows as dicts keyed by the header row."""
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).iter(_NS + "si"):
            shared.append("".join(t.text or "" for t in si.iter(_NS + "t")))
    sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = []
    for r in sheet.iter(_NS + "row"):
        out = []
        for c in r.iter(_NS + "c"):
            i = _column(c.get("r"))
            out.extend([""] * (i - len(out)))
            v, t = c.find(_NS + "v"), c.get("t")
            if t == "s":
                out.append(shared[int(v.text)])
            elif t == "inlineStr":
                out.append("".join(x.text or "" for x in c.iter(_NS + "t")))
            else:
                out.append(v.text if v is not None and v.text else "")
        rows.append(out)
    header = rows[0]
    return [dict(zip(header, r + [""] * (len(header) - len(r)))) for r in rows[1:]]


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------


# The 成語典's editorial marks (※ before 語本, ＃ and ◎ before a passage
# or as a separator line): never shown.
EDITORIAL = re.compile(r"◎\d*|[#＃※]")


def lines_of(text):
    """Non-empty stripped lines, carriage returns, editorial marks and
    full-width spaces at the ends removed."""
    text = EDITORIAL.sub("", text.replace("_x000D_", "").replace("\r", ""))
    return [x.strip(" \t　") for x in text.split("\n") if x.strip(" \t　")]


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


def first_reading(pinyin):
    """The 成語典's reading before any tone-sandhi variant: "yī máo bù bá
    （變） yì máo bù bá" -> "yī máo bù bá"."""
    pinyin = re.split(r"（[變又語讀]）|\(變\)", pinyin)[0]
    return unicodedata.normalize("NFC", re.sub(r"\s+", " ", pinyin.replace("　", " ")).strip())


# ---------------------------------------------------------------------------
# 成語典
# ---------------------------------------------------------------------------

SEE_MAIN = re.compile(r"見「([^」]+)」條。?")
CITATION_START = re.compile(r"(?<![0-9])01\.")
STORY_PREFIX = re.compile(r"^此處所列為「[^」]+」之(?:典源|典故說明)，提供參考。")
CROSS_REF = re.compile(r"\s*△.*$", re.S)        # 釋義's trailing list of related idioms
SOURCE_MARK = re.compile(r"（源）")              # a citation that is the 典源 itself
NOTE_MARK = re.compile(r"\*\d+\*")
# A related entry whose own explanation only says which idiom it equals,
# after glossing a character or two (㕙，兔。盧，黑色獵犬。「㕙盡盧烹」猶「兔死狗烹」。).
ONLY_EQUALS = re.compile(r"^(?:[^。「」]{1,6}，[^。]{1,24}。)*(?:「[^」]+」)?"
                         r"(?:義?猶|即|義同|同|義參|義仿|義似)「[^」]+」。$")
# A note ending by pointing to another entry: 「…腳後跟。見「摩頂放踵」。」
NOTE_POINTER = re.compile(r"見「[^」]+」(?:條)?。?$")


def source_text(text):
    """典源文獻內容 as paragraphs: note markers out, the newlines around
    annotated words joined, a # paragraph (context around the passage) kept
    as its own paragraph."""
    text = NOTE_MARK.sub("", text.replace("_x000D_", "").replace("\r", ""))
    paras, current = [], []
    pieces = text.split("\n")
    k = 0
    while k < len(pieces):
        piece = pieces[k]
        if piece.lstrip().startswith(("#", "＃", "◎")):
            if current:
                paras.append("".join(current))
                current = []
            paras.append(piece.lstrip()[1:])
        else:
            current.append(piece)
        k += 1
    if current:
        paras.append("".join(current))
    paras = [EDITORIAL.sub("", p).strip(" \t　") for p in paras]
    return [p for p in paras if p]


def source_title(text):
    """典源文獻名稱 without its markup: several titles (each after ※) joined
    with "；"."""
    text = NOTE_MARK.sub("", text.replace("_x000D_", "").replace("\r", ""))
    titles = [EDITORIAL.sub("", t).strip(" \t\u3000") for t in re.split(r"[\n※]", text)]
    return "；".join(t for t in titles if t)


def own_explanation(text):
    """A 釋義 without its related-idiom list, the pointer to its main entry
    and the citations appended to it."""
    text = CROSS_REF.sub("", text.replace("_x000D_", "").replace("\r", ""))
    m = SEE_MAIN.search(text)
    if m:
        text = text[:m.start()]
    m = CITATION_START.search(text)
    if m:
        text = text[:m.start()]
    return EDITORIAL.sub("", re.sub(r"\s+", "", text)).strip()


def numbered(lines):
    """Citation lines: "01.《燕丹子》…" kept as written, the （源） mark out."""
    return [SOURCE_MARK.sub("", x).strip() for x in lines]


def idioms_entries(rows, stats):
    """The 成語典's rows (read_xlsx) as dicts {trad, pinyin, short, sections,
    main} in traditional text: `sections` the 出处 view's (heading, lines),
    headings already simplified. Related entries take the source text, notes
    and story of their main entry, headed with its name."""
    by_name = {r["成語"]: r for r in rows}

    def main_sections(r, suffix=""):
        src_title = source_title(r["典源文獻名稱"])
        src = [] if STORY_PREFIX.match(r["典源文獻內容"]) else source_text(r["典源文獻內容"])
        story = STORY_PREFIX.sub("", r["典故說明"].replace("_x000D_", "")).strip()
        return [
            (("典源" + suffix + ("　" + src_title if src_title else "")), no_boxes(src, stats, "idioms")),
            ("注解" + suffix, no_boxes([NOTE_POINTER.sub("", x) for x in lines_of(r["典源注解"])], stats, "idioms")),
            ("典故说明" + suffix, no_boxes(lines_of(story), stats, "idioms")),
        ]

    out = []
    for r in rows:
        stats["idioms: entries read"] += 1
        name = r["成語"].strip()
        is_main = r["主條成語／非主條成語"].strip() == "主條成語"
        own = own_explanation(r["釋義"])
        m = SEE_MAIN.search(r["釋義"])
        main = by_name.get(m.group(1)) if m else None
        if is_main:
            stats["idioms: main entries"] += 1
            sense = r["用法說明-語義說明"].replace("_x000D_", "").strip()
            short = re.sub(r"\s+", "", sense) or own
            sections = [("释义", no_boxes([own], stats, "idioms"))] + main_sections(r) + [
                ("书证", no_boxes(numbered(lines_of(r["書證"]))[:VIEW_LIST_MAX], stats, "idioms")),
                ("用法", no_boxes(lines_of(sense) + lines_of(r["用法說明-使用類別"]), stats, "idioms")),
                ("例句", no_boxes(lines_of(r["用法說明-例句"])[:VIEW_LIST_MAX], stats, "idioms")),
                ("辨识", no_boxes(lines_of(r["辨識-形音辨誤"]) + lines_of(r["辨識-同"]) + lines_of(r["辨識-異"]),
                                stats, "idioms")),
                ("", ["近义：" + x for x in lines_of(r["近義成語"])] + ["反义：" + x for x in lines_of(r["反義成語"])]),
            ]
        else:
            stats["idioms: related entries"] += 1
            short = own
            if main is not None:
                stats["idioms: related entries with their main entry"] += 1
                main_sense = re.sub(r"\s+", "", main["用法說明-語義說明"].replace("_x000D_", ""))
                if ONLY_EQUALS.match(own) and main_sense:
                    short = own.rstrip("。") + "：" + main_sense
            sections = [("释义", no_boxes([own], stats, "idioms")),
                        ("书证", no_boxes(numbered(lines_of(r["書證"]))[:VIEW_LIST_MAX], stats, "idioms"))]
            if main is not None:
                sections += main_sections(main, "（" + main["成語"].strip() + "）")
        if BOXES.search(short):
            stats["idioms: short line with a box character (dropped)"] += 1
            short = ""
        out.append({"trad": name, "pinyin": first_reading(r["漢語拼音"]), "short": shorten(short),
                    "sections": sections, "main": is_main})
    return out


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
    CREATE TABLE idioms (simp TEXT NOT NULL, trad TEXT NOT NULL, short TEXT NOT NULL, view TEXT NOT NULL);
"""


# Keep in step with DB.idiomsSql in chinesehelper.koplugin/ch_db.lua
# (tests/test_db.lua checks that they match).
def idioms_sql(n):
    marks = ",".join("?" * n)
    return (f"SELECT simp, trad, short, view FROM idioms WHERE simp IN ({marks}) "
            f"OR trad IN ({marks}) ORDER BY rowid")


def write_idioms(con, rows):
    """rows: (simp, trad, short, view)."""
    con.executescript(IDIOMS_SCHEMA)
    con.executemany("INSERT INTO idioms VALUES (?, ?, ?, ?)", sorted(set(rows)))
    con.execute("CREATE INDEX idioms_simp ON idioms(simp)")
    con.execute("CREATE INDEX idioms_trad ON idioms(trad)")
    for n in (1, 16):
        plan = "\n".join(r[3] for r in con.execute("EXPLAIN QUERY PLAN " + idioms_sql(n), ["x"] * (2 * n)))
        if "USING INDEX idioms_simp" not in plan or "USING INDEX idioms_trad" not in plan:
            raise SystemExit(f"idioms lookup does not use its indexes:\n{plan}")


def tables(entries, source, cedict, stats):
    """entries: dicts {simp, trad, pinyin, short, view} (final text). Returns
    (fallback rows, idioms rows)."""
    fallback, idioms = [], []
    for e in entries:
        simp, trad = e["simp"], e["trad"]
        if not HAN_ONLY.fullmatch(simp) or not HAN_ONLY.fullmatch(trad):
            stats[f"{source}: headword not Han-only after conversion (dropped)"] += 1
            continue
        if not e["short"] and not e["view"]:
            continue
        idioms.append((simp, trad, e["short"], e["view"]))
        if e["view"]:
            stats[f"{source}: idioms with a 出处 view"] += 1
        if simp in cedict or trad in cedict:
            stats[f"{source}: CC-CEDICT has the idiom (short line and view only)"] += 1
        elif e["short"]:
            fallback.append((simp, trad, e["pinyin"], "", e["short"].replace("/", "／"), source))
    stats[f"{source}: idioms rows"] = len(set(idioms))
    stats[f"{source}: fallback rows"] = len(set(fallback))
    return fallback, idioms
