#!/usr/bin/env python3
"""Phase 1 measurement: what fallback dictionaries would add to the popup.

    python3 tools/fetch_books.py               # first: build/corpus/ from the device's books
    tools/download_sources.sh                  # and the sources, into build/sources/
    python3 tools/measure_fallback.py          # all stages; cached in build/measure/
    python3 tools/measure_fallback.py --stage report    # just rewrite the report
    python3 tools/measure_fallback.py --book linggao    # one book only (fetch_books.py --local
                                                        # linggao ...): build/measure/linggao/

Needs: jieba, opencc, lupa (pip), and the plugin database (tools/build_db.py).
Nothing here is used by the plugin; it measures, and writes its findings to
build/measure/report.md with sample lists next to it.

Stages (each cached as a pickle in build/measure/, rerun with --stage NAME):

  sources  every candidate source loaded into headword -> entry, with the
           filters the plugin would need (Han-only 1-8 character headwords,
           Mandarin readings, no redirects or disambiguation pages, ...),
           indexed under simplified and traditional forms.
  gaps     the corpus segmented with jieba's big dictionary; the word types
           CC-CEDICT lacks, with counts, and which source covers each.
  taps     simulated taps, through the plugin's own candidate code
           (ch_text.lua, run in lupa): for a sample of Han characters, the
           candidate words the popup would look up, and what each source adds
           where CC-CEDICT has nothing. A fallback match whose start and end
           fall on jieba word boundaries is counted as plausible ("aligned"),
           one that cuts through a jieba word as a likely false match
           ("crossing").
  report   build/measure/report.md and the sample files.
  built    (run on its own, after tools/build_db.py and tools/build_moe.py)
           the same taps against the fallback tables as built, by match
           length: build/measure/length-report.md.
"""
import argparse
import collections
import csv
import glob
import gzip
import json
import lzma
import multiprocessing
import os
import pickle
import random
import re
import sqlite3
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
SRC = os.path.join(BUILD, "sources")
OUT = os.path.join(BUILD, "measure")
CORPUS = os.path.join(BUILD, "corpus")
BOOK = None             # --book NAME: only build/corpus/NAME-*.txt, reports in build/measure/NAME/
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
PLUGIN = os.path.join(ROOT, "chinesehelper.koplugin")

HAN = "㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f"
HAN_WORD = re.compile(f"[{HAN}]{{1,8}}")
HAN_CHAR = re.compile(f"[{HAN}]")
MAX_WORD = 8

SOURCES = ["wikt", "wp", "moe", "naer"]
NAMES = {"wikt": "Wiktionary (kaikki)", "wp": "Wikipedia titles (zh→en)", "moe": "MOE 重編國語辭典",
         "naer": "NAER terminology"}
CLASSES = ["slang", "technical", "historical/literary"]


def han_word(w):
    return HAN_WORD.fullmatch(w) is not None


def corpus_files():
    """The corpus measured: every book, or with --book NAME only NAME-*.txt."""
    return sorted(glob.glob(os.path.join(CORPUS, f"{BOOK}-*.txt" if BOOK else "*.txt")))


def set_book(name):
    """Measure one book (or set of files) only, with its own output folder.
    The sources pickle is shared: it does not depend on the corpus."""
    global BOOK, OUT
    BOOK = name
    OUT = os.path.join(BUILD, "measure", name)


def save(name, obj):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".pickle"), "wb") as f:
        pickle.dump(obj, f)


def load(name):
    path = os.path.join(OUT, name + ".pickle")
    if name == "sources" and BOOK and not os.path.exists(path):
        path = os.path.join(BUILD, "measure", "sources.pickle")
    with open(path, "rb") as f:
        return pickle.load(f)


def converters():
    import opencc
    return opencc.OpenCC("t2s"), opencc.OpenCC("s2t"), opencc.OpenCC("tw2s")


# ---------------------------------------------------------------------------
# Sources. Each loader returns {headword: entry}, entry = {"head": canonical
# form, "py": reading or "", "gloss": short gloss, "cls": set of CLASSES,
# "n": entries merged}, plus stats {name: count} for the report.
# ---------------------------------------------------------------------------


def add(index, forms, entry):
    for form in forms:
        if form and han_word(form) and form not in index:
            index[form] = entry


def cedict_forms():
    con = sqlite3.connect(DB)
    forms = set()
    for simp, trad in con.execute("SELECT simp, trad FROM entries"):
        forms.add(simp)
        forms.add(trad)
    words = {w for (w,) in con.execute("SELECT word FROM words")}
    con.close()
    return forms, words


WIKT_SLANG_TAGS = {"slang", "Internet", "neologism", "vulgar", "euphemistic", "humorous", "derogatory"}
WIKT_HIST_TAGS = {"historical", "Classical", "literary", "archaic", "obsolete", "dated", "Classical-Chinese",
                  "Literary-Chinese", "honorific"}
WIKT_DIALECT_TAGS = {"Cantonese", "Hokkien", "Hakka", "Teochew", "Wu", "Shanghainese", "Min", "Min-Nan",
                     "Min-Dong", "Xiang", "Gan", "Jin", "Taishanese", "Puxian-Min", "Northern-Min", "Eastern-Min",
                     "Southern-Min", "Leizhou-Min", "Hainanese", "Dungan", "Zhangzhou-Hokkien",
                     "Xiamen", "Quanzhou", "Singapore-Hokkien", "Hong-Kong-Cantonese", "Guangzhou"}
TECH_TOPICS = re.compile(
    r"^zh:(Computing|Computer science|Programming|Software|Internet|Mathematics|Physics|Chemistry|"
    r"Biochemistry|Biology|Medicine|Pathology|Diseases|Pharmacology|Anatomy|Genetics|Botany|Zoology|"
    r"Engineering|Electronics|Electricity|Telecommunications|Economics|Finance|Accounting|Law|Statistics|"
    r"Astronomy|Geology|Geography|Linguistics|Grammar|Phonetics|Philosophy|Psychology|Sociology|"
    r"Military|Weapons|Firearms|Chemical elements|Units of measure|Machinery|Technology|Video games|"
    r"Photography|Music|Business|Trade|Politics|Banking|Insurance|Taxation|Automotive|Aviation|"
    r"Nautical|Architecture|Cryptography|Artificial intelligence|Mineralogy|Optics|Meteorology|"
    r"Ecology|Neuroscience|Immunology|Microbiology|Virology|Biochemistry|Organic chemistry)\b")
ALT_GLOSS = re.compile(r"^(alternative|alternative form|variant|obsolete form|archaic form|simplified form|"
                       r"traditional form|abbreviation|misspelling|erhua form|eye dialect|clipping|"
                       r"short form|alternative name)s? (form )?of\b", re.I)


def load_wiktionary():
    path = os.path.join(SRC, "wiktionary", "kaikki-Chinese.jsonl.gz")
    stats = collections.Counter()
    entries = {}            # word -> merged entry (Mandarin senses only)
    redirects = {}          # simplified (or other) form -> target words
    alt_targets = {}        # word whose senses are all alt-of -> target words
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            if e.get("lang_code") != "zh":
                continue
            word = e.get("word", "")
            stats["records"] += 1
            if e.get("pos") == "soft-redirect":
                redirects.setdefault(word, set()).update(e.get("redirects") or [])
                stats["soft-redirect records"] += 1
                continue
            mandarin = [s for s in e.get("sounds", []) if s.get("zh_pron") and "Mandarin" in (s.get("tags") or [])
                        and "Pinyin" in (s.get("tags") or [])]
            if not mandarin:
                stats["no Mandarin reading (dropped)"] += 1
                continue
            cats = [c.get("orig") or c.get("name") or "" for c in e.get("categories", []) if isinstance(c, dict)]
            glosses, alts, cls = [], set(), set()
            for s in e.get("senses", []):
                tags = set(s.get("tags") or [])
                if tags & WIKT_DIALECT_TAGS and not tags & {"Mandarin", "Standard-Chinese", "Taiwanese-Mandarin",
                                                            "Beijing", "Northeastern-Mandarin"}:
                    stats["dialect-only senses (dropped)"] += 1
                    continue
                for c in s.get("categories", []):
                    if isinstance(c, dict):
                        cats.append(c.get("orig") or c.get("name") or "")
                gl = (s.get("glosses") or s.get("raw_glosses") or [""])[-1]
                if s.get("alt_of") or s.get("form_of") or ALT_GLOSS.match(gl or ""):
                    for t in (s.get("alt_of") or []) + (s.get("form_of") or []):
                        if t.get("word"):
                            alts.add(t["word"])
                    continue
                if not gl or "no-gloss" in tags:
                    continue
                glosses.append(gl)
                if tags & WIKT_SLANG_TAGS:
                    cls.add("slang")
                if tags & WIKT_HIST_TAGS:
                    cls.add("historical/literary")
                for t in s.get("topics") or []:
                    if TECH_TOPICS.match("zh:" + str(t).capitalize()):
                        cls.add("technical")
            for c in cats:
                if re.search(r"slang|neologism|Internet", c, re.I):
                    cls.add("slang")
                if re.search(r"chengyu|Classical Chinese|xiehouyu|historical|Literary Chinese", c, re.I):
                    cls.add("historical/literary")
                if TECH_TOPICS.match(c):
                    cls.add("technical")
            if e.get("pos") == "proverb":
                cls.add("historical/literary")
            if not glosses:
                if alts:
                    alt_targets.setdefault(word, set()).update(alts)
                    stats["alt-of only (resolved below)"] += 1
                else:
                    stats["no usable sense (dropped)"] += 1
                continue
            ent = entries.get(word)
            if ent is None:
                ent = {"head": word, "py": mandarin[0]["zh_pron"], "gloss": "; ".join(glosses[:3]),
                       "cls": cls, "n": 1, "forms": set()}
                entries[word] = ent
            else:
                ent["cls"] |= cls
                ent["n"] += 1
            for fm in e.get("forms", []):
                ftags = fm.get("tags") or []
                if "Simplified-Chinese" in ftags or "Traditional-Chinese" in ftags or \
                        "simplified" in ftags or "traditional" in ftags:
                    ent["forms"].add(fm.get("form"))
    index = {}
    for word, ent in entries.items():
        add(index, [word] + sorted(ent["forms"]), ent)
    resolved = 0
    for word, targets in list(redirects.items()) + list(alt_targets.items()):
        for t in sorted(targets):
            if t in entries:
                if word not in index and han_word(word):
                    index[word] = entries[t]
                    resolved += 1
                break
    stats["entries with a Mandarin sense"] = len(entries)
    stats["redirect/alt-of forms resolved to an entry"] = resolved
    stats["indexed headwords (Han-only, 1-8)"] = len(index)
    return index, stats


# --- Wikipedia: MySQL dump parsing ---------------------------------------------

SQL_STR = r"'((?:[^'\\]|\\.)*)'"


def sql_unescape(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "0": "\0"}.get(m.group(1), m.group(1)), s)


def sql_rows(path, pattern):
    rx = re.compile(pattern)
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            # Rows come one per line after "INSERT INTO `t` VALUES" (newer dumps)
            # or all on the INSERT line (older ones).
            if line.startswith("(") or line.startswith("INSERT INTO"):
                yield from rx.finditer(line)


def sql_columns(path):
    cols, inside = [], False
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE"):
                inside = True
                continue
            if inside:
                m = re.match(r"\s+`(\w+)`", line)
                if m:
                    cols.append(m.group(1))
                elif line.startswith(")"):
                    return cols


PERSON_CAT = re.compile(r"(\d+年(代)?出生|\d+年(代)?逝世|在世人物|出生年份不詳|出生年份不详|逝世年份不詳|逝世年份不详|"
                        r"人物$|演員$|演员$|歌手$|作家$|運動員$|运动员$|政治人物|球員$|球员$|模特兒$|模特儿$)")
WP_SLANG = re.compile(r"網路用語|网络用语|網路流行語|网络流行语|流行語|流行语|網路迷因|网络迷因|網路文化|网络文化|俚語|俚语|黑话|黑話")
WP_TECH = re.compile(r"技術|技术|計算機|计算机|電腦|电脑|軟體|软件|程式|编程|程序设计|化學|化学|物理|數學|数学|醫學|医学|"
                     r"疾病|藥物|药物|生物|工程|電子|电子|統計|统计|天文|地質|地质|經濟學|经济学|金融|法律|材料|演算法|算法|"
                     r"網際網路|互联网|半導體|半导体|通訊|通信")
WP_HIST = re.compile(r"朝|官職|官职|官制|歷史|历史|古代|典故|成語|成语|制度|科舉|科举|年號|年号|封建|典章|爵位|宮廷|宫廷|"
                     r"文言|古籍|經典|经典|詩|诗|詞|词牌")
WP_PLACE = re.compile(r"行政區劃|行政区划|城市|鄉鎮|乡镇|村$|縣$|县$|市$|區$|区$|河流|山峰|島嶼|岛屿|車站|车站|機場|机场|"
                      r"街道|道路|公路|鐵路|铁路|學校|学校|大學|大学|公司$|企業|企业|球隊|球队|電影|电影|電視劇|电视剧|專輯|专辑|"
                      r"歌曲|小說|小说|遊戲$|游戏$|動畫|动画|漫畫|漫画")


def load_wikipedia():
    d = os.path.join(SRC, "wikipedia")
    stats = collections.Counter()
    t2s, s2t, _ = converters()
    page_cols = sql_columns(os.path.join(d, "zhwiki-latest-page.sql.gz"))
    assert page_cols[:4] == ["page_id", "page_namespace", "page_title", "page_is_redirect"], page_cols
    titles = {}
    for m in sql_rows(os.path.join(d, "zhwiki-latest-page.sql.gz"), r"\((\d+),(-?\d+)," + SQL_STR + r",(\d),"):
        if m.group(2) != "0":
            continue
        stats["articles+redirects (ns 0)"] += 1
        if m.group(4) == "1":
            stats["redirects (skipped)"] += 1
            continue
        title = sql_unescape(m.group(3))
        if not han_word(title):
            stats["titles not Han-only 1-8 (skipped)"] += 1
            continue
        titles[int(m.group(1))] = title
    ll_cols = sql_columns(os.path.join(d, "zhwiki-latest-langlinks.sql.gz"))
    assert ll_cols[:3] == ["ll_from", "ll_lang", "ll_title"], ll_cols
    english = {}
    for m in sql_rows(os.path.join(d, "zhwiki-latest-langlinks.sql.gz"), r"\((\d+),'en'," + SQL_STR + r"\)"):
        pid = int(m.group(1))
        if pid in titles:
            english[pid] = sql_unescape(m.group(2))
    stats["Han-only 1-8 titles"] = len(titles)
    stats["... with an English article"] = len(english)
    disamb = set()
    for m in sql_rows(os.path.join(d, "zhwiki-latest-page_props.sql.gz"), r"\((\d+),'disambiguation',"):
        disamb.add(int(m.group(1)))
    lt_cols = sql_columns(os.path.join(d, "zhwiki-latest-linktarget.sql.gz"))
    assert lt_cols[:3] == ["lt_id", "lt_namespace", "lt_title"], lt_cols
    catname = {}
    for m in sql_rows(os.path.join(d, "zhwiki-latest-linktarget.sql.gz"), r"\((\d+),14," + SQL_STR + r"\)"):
        catname[int(m.group(1))] = sql_unescape(m.group(2))
    cl_cols = sql_columns(os.path.join(d, "zhwiki-latest-categorylinks.sql.gz"))
    assert cl_cols[0] == "cl_from" and cl_cols[-1] == "cl_target_id", cl_cols
    cats = collections.defaultdict(list)
    for m in sql_rows(os.path.join(d, "zhwiki-latest-categorylinks.sql.gz"),
                      r"\((\d+)," + SQL_STR + r",'[^']*'," + SQL_STR + r",'(?:page|subcat|file)',\d+,(\d+)\)"):
        pid = int(m.group(1))
        if pid in english:
            name = catname.get(int(m.group(4)))
            if name:
                cats[pid].append(name)
    index, kept = {}, collections.Counter()
    rejected = collections.defaultdict(list)
    for pid, en in english.items():
        title = titles[pid]
        cs = cats.get(pid, [])
        if pid in disamb:
            stats["disambiguation (dropped)"] += 1
            rejected["disambiguation"].append((title, en))
            continue
        if "列表" in title or en.startswith("List of"):
            stats["lists (dropped)"] += 1
            rejected["list"].append((title, en))
            continue
        if any(PERSON_CAT.search(c) for c in cs):
            stats["people (dropped)"] += 1
            rejected["person"].append((title, en))
            continue
        cls = set()
        if any(WP_SLANG.search(c) for c in cs):
            cls.add("slang")
        if any(WP_TECH.search(c) for c in cs):
            cls.add("technical")
        if any(WP_HIST.search(c) for c in cs):
            cls.add("historical/literary")
        place = any(WP_PLACE.search(c) for c in cs)
        ent = {"head": title, "py": "", "gloss": en.replace("_", " "), "cls": cls, "n": 1, "place": place,
               "cats": cs[:6]}
        kept["place/organisation/work" if place else "other"] += 1
        add(index, [title, t2s.convert(title), s2t.convert(title)], ent)
    stats.update({"kept: " + k: v for k, v in kept.items()})
    stats["indexed headwords (Han-only, 1-8; t2s and s2t forms)"] = len(index)
    return index, stats, {k: v[:40] for k, v in rejected.items()}


def load_moe():
    path = os.path.join(SRC, "moe", "dict-revised.json.xz")
    _, _, tw2s = converters()
    stats = collections.Counter()
    index = {}
    for e in json.load(lzma.open(path, "rt", encoding="utf-8")):
        title = e.get("title", "")
        stats["entries"] += 1
        if "{[" in title or any(0xE000 <= ord(c) <= 0xF8FF for c in title):
            stats["private-use or markup in headword (dropped)"] += 1
            continue
        if not han_word(title):
            stats["not Han-only 1-8 (dropped)"] += 1
            continue
        hets = e.get("heteronyms") or []
        py = (hets[0].get("pinyin") if hets else "") or ""
        defs = [d.get("def", "") for h in hets for d in (h.get("definitions") or [])]
        gloss = (defs[0] if defs else "")[:80]
        cls = set()
        if re.search(r"職官名|官名|古代|古時|舊時|朝代|典出|語本|語出|文言|古稱|古代官", " ".join(defs)):
            cls.add("historical/literary")
        ent = {"head": title, "py": py, "gloss": gloss, "cls": cls, "n": 1}
        add(index, [title, tw2s.convert(title)], ent)
    stats["indexed headwords (original + tw2s)"] = len(index)
    return index, stats


def load_naer():
    d = os.path.join(SRC, "naer")
    _, _, tw2s = converters()
    stats = collections.Counter()
    index = {}
    files = [l.rstrip("\n").split("\t") for l in open(os.path.join(d, "files.tsv"), encoding="utf-8")]
    for path, name in files:
        full = os.path.join(SRC, path)
        if not os.path.exists(full) or os.path.getsize(full) == 0:
            stats["files missing"] += 1
            continue
        raw = open(full, "rb").read()
        for enc in ("utf-8-sig", "big5", "cp950"):
            try:
                text = raw.decode(enc)
                break
            except UnicodeDecodeError:
                continue
        else:
            stats["files undecodable"] += 1
            continue
        rows = list(csv.reader(text.splitlines()))
        if not rows:
            continue
        head = rows[0]
        en = next((i for i, h in enumerate(head) if "英文" in h), None)
        zh = next((i for i, h in enumerate(head) if h.strip() in ("中文名稱", "中文") or
                   ("中文" in h and "大陸" not in h and "大陆" not in h)), None)
        cn = next((i for i, h in enumerate(head) if "大陸" in h or "大陆" in h), None)
        if en is None or zh is None:
            stats["files without English/Chinese columns"] += 1
            continue
        stats["files"] += 1
        domain = name.replace("國家教育研究院-", "")
        for r in rows[1:]:
            if len(r) <= max(en, zh):
                continue
            stats["rows"] += 1
            ent = {"head": r[zh].strip(), "py": "", "gloss": r[en].strip(), "cls": {"technical"}, "n": 1,
                   "domain": domain}
            forms = [r[zh].strip(), tw2s.convert(r[zh].strip())]
            if cn is not None and len(r) > cn:
                for alt in re.split(r"[;；,，、/]", r[cn]):
                    forms.append(alt.strip())
            add(index, forms, ent)
    stats["indexed headwords (Taiwan term + tw2s + mainland term)"] = len(index)
    return index, stats


def stage_sources():
    forms, words = cedict_forms()
    out = {"cedict": forms, "words": words, "stats": {}, "rejected": {}}
    print("Wiktionary...", flush=True)
    out["wikt"], out["stats"]["wikt"] = load_wiktionary()
    print("Wikipedia...", flush=True)
    out["wp"], out["stats"]["wp"], out["rejected"]["wp"] = load_wikipedia()
    print("MOE...", flush=True)
    out["moe"], out["stats"]["moe"] = load_moe()
    print("NAER...", flush=True)
    out["naer"], out["stats"]["naer"] = load_naer()
    save("sources", out)
    for s in SOURCES:
        print(f"  {s}: {len(out[s]):,} headwords")


# ---------------------------------------------------------------------------
# Gaps: jieba over the corpus
# ---------------------------------------------------------------------------

_JIEBA = None


def _jieba():
    global _JIEBA
    if _JIEBA is None:
        import jieba
        jieba.setLogLevel(60)
        jieba.set_dictionary(os.path.join(SRC, "jieba", "dict.txt.big"))
        jieba.initialize()
        _JIEBA = jieba
    return _JIEBA


def _segment_book(path):
    jieba = _jieba()
    types = collections.Counter()
    for line in open(path, encoding="utf-8"):
        for tok in jieba.cut(line.strip(), HMM=False):
            if len(tok) >= 2 and han_word(tok):
                types[tok] += 1
    return os.path.basename(path), types


def stage_gaps():
    books = corpus_files()
    total = collections.Counter()
    per_book = {}
    with multiprocessing.Pool(max(1, os.cpu_count() - 1)) as pool:
        for name, types in pool.imap_unordered(_segment_book, books):
            total.update(types)
            per_book[name] = len(types)
            print(f"  segmented {name}: {len(types):,} word types", flush=True)
    save("gaps", {"types": total, "books": per_book})


# ---------------------------------------------------------------------------
# Taps: the plugin's candidate code in lupa
# ---------------------------------------------------------------------------


def lua_text():
    try:
        from lupa.luajit21 import LuaRuntime
    except ImportError:
        from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{PLUGIN}/?.lua;" .. package.path')
    return lua, lua.require("ch_text")


def lua_list(t):
    """A Lua array as a Python list, in order."""
    return [t[k] for k in range(1, len(t) + 1)]


def tap_samples(per_book, seed):
    """The simulated taps: for a seeded sample of Han characters per book,
    (book, paragraph, index, candidates [(text, start, len)], left, right,
    jieba word boundaries of the paragraph). Same seed, same taps."""
    lua, Text = lua_text()
    jieba = _jieba()
    rnd = random.Random(seed)
    for path in corpus_files():
        paras = [l.rstrip("\n") for l in open(path, encoding="utf-8")]
        positions = [(p, i) for p, para in enumerate(paras) for i, ch in enumerate(para) if HAN_CHAR.match(ch)]
        for p, i in rnd.sample(positions, min(per_book, len(positions))):
            para = paras[p]
            ch = para[i]
            left = lua_list(Text.hanSuffix(para[:i], Text.MAX_CONTEXT))
            right = lua_list(Text.hanPrefix(para[i + 1:], Text.MAX_CONTEXT))
            cands, _ = Text.candidates(lua.table_from(left), ch, lua.table_from(right))
            cands = [(c.text, c.start, c.len) for c in lua_list(cands)]
            bounds, pos = {0}, 0
            for tok in jieba.cut(para, HMM=False):
                pos += len(tok)
                bounds.add(pos)
            yield os.path.basename(path), para, i, cands, left, right, bounds


def stage_taps(per_book, seed):
    src = load("sources")
    taps = []
    for book, para, i, cands, left, right, bounds in tap_samples(per_book, seed):
        ch = para[i]
        found = {"cedict": [c for c in cands if c[0] in src["cedict"]]}
        for s in SOURCES:
            hits = []
            for text, start, length in cands:
                if text in src["cedict"] or text not in src[s]:
                    continue
                a, b = i + start, i + start + length
                hits.append((text, start, length, a in bounds and b in bounds))
            found[s] = hits
        taps.append({"book": book, "char": ch, "context": "".join(left) + "[" + ch + "]" + "".join(right),
                     "found": found})
    save("taps", taps)
    print(f"  {len(taps):,} simulated taps")


def stage_built(per_book, seed, moe_path):
    """The same taps against the tables as built (release database: CC-CEDICT
    and the Wiktionary fallback; the MOE file), with the source priority
    CC-CEDICT > Wiktionary > MOE, one source per headword. For the open
    question of a minimum length for fallback matches."""
    con = sqlite3.connect(DB)
    cedict = set()
    for simp, trad in con.execute("SELECT simp, trad FROM entries"):
        cedict.update((simp, trad))
    forms = {"wikt": set(), "moe": set()}
    for simp, trad in con.execute("SELECT simp, trad FROM fallback WHERE source = 'wikt'"):
        forms["wikt"].update((simp, trad))
    resolver_words = {w for (w,) in con.execute("SELECT word FROM words")}
    con.close()
    if os.path.exists(moe_path):
        m = sqlite3.connect(moe_path)
        for simp, trad in m.execute("SELECT simp, trad FROM fallback"):
            forms["moe"].update((simp, trad))
        m.close()
    taps = []
    for book, para, i, cands, left, right, bounds in tap_samples(per_book, seed):
        hits = []
        for text, start, length in cands:
            if text in cedict:
                continue
            source = next((s for s in ("wikt", "moe") if text in forms[s]), None)
            if source:
                a, b = i + start, i + start + length
                hits.append({"word": text, "len": length, "source": source,
                             "aligned": a in bounds and b in bounds, "resolver": text in resolver_words})
        taps.append({"book": book, "context": "".join(left) + "[" + para[i] + "]" + "".join(right),
                     "cedict": sum(1 for c in cands if c[0] in cedict), "hits": hits})
    save("built", {"taps": taps, "sizes": {s: len(v) for s, v in forms.items()}})
    print(f"  {len(taps):,} simulated taps against the built tables")


def report_built():
    """build/measure/length-report.md: the minimum-length question."""
    data = load("built")
    taps = data["taps"]
    n = len(taps)
    L = []
    w = L.append
    w("# Fallback matches by length (tables as built, priority CC-CEDICT > Wiktionary > MOE)\n")
    w(f"{n:,} simulated taps (same sample as report.md). Fallback headwords: Wiktionary "
      f"{data['sizes']['wikt']:,} forms, MOE {data['sizes']['moe']:,} forms (after the everyday-combination "
      "filter). 'Plausible' = the match starts and ends on jieba word boundaries; 'likely false' = it cuts "
      "through a jieba word. 'Resolver word' = in the resolver's word table, so it can be the word that decides "
      "a reading (the proposed exception to a length rule).\n")
    w("| Source | length | matches | plausible | likely false | of which resolver words |")
    w("|---|---|---|---|---|---|")
    for s in ("wikt", "moe"):
        for label, test in (("2", lambda h: h["len"] == 2), ("3+", lambda h: h["len"] >= 3),
                            ("1", lambda h: h["len"] == 1)):
            hs = [h for t in taps for h in t["hits"] if h["source"] == s and test(h)]
            if not hs:
                continue
            ok = sum(h["aligned"] for h in hs)
            w(f"| {s} | {label} | {len(hs):,} | {ok:,} ({pct(ok, len(hs))}) | {len(hs) - ok:,} | "
              f"{sum(h['resolver'] for h in hs):,} |")
    w("")
    def per_tap(rule):
        kept = [[h for h in t["hits"] if rule(h)] for t in taps]
        return (sum(len(k) for k in kept) / n, sum(1 for k in kept if any(h["aligned"] for h in k)),
                sum(1 for k in kept if any(not h["aligned"] for h in k)))
    rules = [("no length rule", lambda h: True),
             ("3+ characters", lambda h: h["len"] >= 3),
             ("3+ characters, or a resolver word", lambda h: h["len"] >= 3 or h["resolver"])]
    w("| Rule for fallback matches | extra blocks per tap | taps gaining a plausible match | "
      "taps gaining a likely-false match |")
    w("|---|---|---|---|")
    for label, rule in rules:
        blocks, good, bad = per_tap(rule)
        w(f"| {label} | {blocks:.3f} | {good:,} ({pct(good, n)}) | {bad:,} ({pct(bad, n)}) |")
    w("")
    rnd = random.Random(2)
    for s in ("wikt", "moe"):
        for kind, flag in (("plausible", True), ("likely false", False)):
            ex = [(h["word"], t["context"]) for t in taps for h in t["hits"]
                  if h["source"] == s and h["len"] == 2 and h["aligned"] == flag]
            rnd.shuffle(ex)
            w(f"**{s}, 2 characters, {kind}** ({len(ex):,}): " + "; ".join(f"{a} in {b}" for a, b in ex[:25]))
            w("")
    for s in ("wikt", "moe"):
        ex = [(h["word"], t["context"]) for t in taps for h in t["hits"] if h["source"] == s and h["len"] >= 3]
        rnd.shuffle(ex)
        w(f"**{s}, 3+ characters** ({len(ex):,}): " + "; ".join(f"{a} in {b}" for a, b in ex[:20]))
        w("")
    with open(os.path.join(OUT, "length-report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    with open(os.path.join(OUT, "built-tap-samples.tsv"), "w", encoding="utf-8") as f:
        f.write("source\tlength\tkind\tresolver_word\tword\tcontext\tbook\n")
        for t in taps:
            for h in t["hits"]:
                f.write(f"{h['source']}\t{h['len']}\t{'plausible' if h['aligned'] else 'likely-false'}\t"
                        f"{int(h['resolver'])}\t{h['word']}\t{t['context']}\t{t['book']}\n")
    print(f"wrote {os.path.join(OUT, 'length-report.md')}")


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


def db_size(index, path):
    """Bytes for a table like `entries` holding this source, and its zip size."""
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE fallback (simp TEXT, trad TEXT, pinyin TEXT, defs TEXT)")
    # One row per indexed form: simp = the form, trad = the source's own headword.
    rows = [(form, ent["head"], ent.get("py", ""), ent.get("gloss", "")) for form, ent in index.items()]
    con.executemany("INSERT INTO fallback VALUES (?,?,?,?)", rows)
    con.execute("CREATE INDEX fb_simp ON fallback(simp)")
    con.execute("CREATE INDEX fb_trad ON fallback(trad)")
    con.commit()
    con.execute("VACUUM")
    con.close()
    raw = os.path.getsize(path)
    zpath = path + ".zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(path, os.path.basename(path))
    return raw, os.path.getsize(zpath), len(rows)


def pct(a, b):
    return f"{100 * a / b:.1f}%" if b else "-"


def stage_report():
    src = load("sources")
    gaps = load("gaps")
    taps = load("taps")
    cedict, words = src["cedict"], src["words"]
    types = gaps["types"]
    gap = {w: n for w, n in types.items() if w not in cedict}
    gap_tokens = sum(gap.values())
    L = []
    w = L.append
    w("# Phase 1: fallback dictionary measurement\n")
    w(f"Corpus: {len(gaps['books'])} Chinese books "
      f"({', '.join(os.path.basename(p) for p in corpus_files()) if BOOK else 'from /sdcard/Books'}; "
      "see build/corpus/index.tsv).\n")
    w("## 1. Sources as loaded\n")
    for s in SOURCES:
        w(f"**{NAMES[s]}**: {len(src[s]):,} indexed headwords\n")
        for k, v in src["stats"][s].items():
            w(f"- {k}: {v:,}")
        w("")
    w("## 2. Vocabulary gaps (jieba, big dictionary, HMM off)\n")
    w(f"- word types (Han-only, 2+ characters) in the books: {len(types):,}; tokens: {sum(types.values()):,}")
    w(f"- types CC-CEDICT lacks (neither simplified nor traditional form): {len(gap):,} "
      f"({pct(len(gap), len(types))} of types), {gap_tokens:,} tokens ({pct(gap_tokens, sum(types.values()))})")
    w("- note: jieba's big dictionary lists many free combinations (这本书, 一个人), so many gap types are "
      "not words a dictionary would have; the per-source counts below are what matters.\n")
    w("| Source | gap types covered | gap tokens covered | slang | technical | historical/literary |")
    w("|---|---|---|---|---|---|")
    covered_by = {}
    for s in SOURCES:
        cov = {t: n for t, n in gap.items() if t in src[s]}
        covered_by[s] = cov
        cls_counts = collections.Counter(c for t in cov for c in src[s][t]["cls"])
        w(f"| {NAMES[s]} | {len(cov):,} ({pct(len(cov), len(gap))}) | {sum(cov.values()):,} "
          f"({pct(sum(cov.values()), gap_tokens)}) | {cls_counts['slang']:,} | {cls_counts['technical']:,} | "
          f"{cls_counts['historical/literary']:,} |")
    union = set().union(*[set(c) for c in covered_by.values()])
    w(f"| any source | {len(union):,} ({pct(len(union), len(gap))}) | {sum(gap[t] for t in union):,} "
      f"({pct(sum(gap[t] for t in union), gap_tokens)}) | | | |")
    w("\nClass labels come from each source's own metadata (Wiktionary tags and categories, Wikipedia "
      "categories, MOE definition wording); NAER is all technical; unlabelled hits are in none of the classes.\n")
    w("### Overlap between sources (gap types)\n")
    w("| | " + " | ".join(NAMES[s] for s in SOURCES) + " |")
    w("|---|" + "---|" * len(SOURCES))
    for a in SOURCES:
        w(f"| {NAMES[a]} | " + " | ".join(f"{len(set(covered_by[a]) & set(covered_by[b])):,}" for b in SOURCES) + " |")
    only = {s: set(covered_by[s]) - set().union(*[set(covered_by[o]) for o in SOURCES if o != s]) for s in SOURCES}
    w("\nCovered by this source alone: " + ", ".join(f"{NAMES[s]} {len(only[s]):,}" for s in SOURCES) + "\n")
    w("### Overlap between sources (all headwords CC-CEDICT lacks)\n")
    allsets = {s: {h for h in src[s] if h not in cedict} for s in SOURCES}
    for a in SOURCES:
        w(f"- {NAMES[a]}: {len(allsets[a]):,} headwords not in CC-CEDICT; shared with " +
          ", ".join(f"{NAMES[b]} {len(allsets[a] & allsets[b]):,}" for b in SOURCES if b != a))
    w("")

    # Samples per source and class, most frequent first.
    os.makedirs(OUT, exist_ok=True)
    for s in SOURCES:
        with open(os.path.join(OUT, f"gap-hits-{s}.tsv"), "w", encoding="utf-8") as f:
            f.write("count\tword\tclasses\treading\tgloss\n")
            for t, n in sorted(covered_by[s].items(), key=lambda kv: -kv[1]):
                e = src[s][t]
                f.write(f"{n}\t{t}\t{','.join(sorted(e['cls']))}\t{e.get('py', '')}\t{e.get('gloss', '')[:100]}\n")
    w("### Example hits (most frequent gap words each source covers; full lists in build/measure/gap-hits-*.tsv)\n")
    for s in SOURCES:
        w(f"**{NAMES[s]}**\n")
        cov = sorted(covered_by[s].items(), key=lambda kv: -kv[1])
        picked = []
        for c in CLASSES:
            picked += [kv for kv in cov if c in src[s][kv[0]]["cls"]][:8]
        picked += [kv for kv in cov if not src[s][kv[0]]["cls"]][:6]
        seen = set()
        for t, n in picked:
            if t in seen:
                continue
            seen.add(t)
            e = src[s][t]
            w(f"- {t} ×{n} [{', '.join(sorted(e['cls'])) or '-'}] {e.get('py', '')} — {e.get('gloss', '')[:90]}")
        w("")

    # Taps
    w("## 3. What the popup would gain (simulated taps)\n")
    n = len(taps)
    w(f"{n:,} taps on random Han characters ({n // max(1, len(gaps['books']))} per book), candidates from the plugin's "
      "own ch_text.lua (7 characters either side, words of 1-8). A fallback match counts only where CC-CEDICT "
      "has no entry for that string. 'Aligned' = starts and ends on jieba word boundaries (plausible); "
      "'crossing' = cuts through a jieba word (likely false).\n")
    nocedict = sum(1 for t in taps if not t["found"]["cedict"])
    w(f"- taps where CC-CEDICT has nothing at all (today: straight to KOReader's dictionary): {nocedict:,} "
      f"({pct(nocedict, n)})")
    blocks = [len(t["found"]["cedict"]) for t in taps]
    w(f"- CC-CEDICT blocks per popup today: mean {sum(blocks) / n:.2f}\n")
    w("| Source | taps gaining an aligned match | taps gaining a crossing match | extra blocks per tap (mean) | "
      "aligned / crossing matches | of taps with no CC-CEDICT match, now covered |")
    w("|---|---|---|---|---|---|")
    for s in SOURCES:
        aligned = sum(1 for t in taps if any(h[3] for h in t["found"][s]))
        crossing = sum(1 for t in taps if any(not h[3] for h in t["found"][s]))
        extra = sum(len(t["found"][s]) for t in taps)
        na = sum(1 for t in taps for h in t["found"][s] if h[3])
        nc = sum(1 for t in taps for h in t["found"][s] if not h[3])
        rescued = sum(1 for t in taps if not t["found"]["cedict"] and t["found"][s])
        w(f"| {NAMES[s]} | {aligned:,} ({pct(aligned, n)}) | {crossing:,} ({pct(crossing, n)}) | "
          f"{extra / n:.3f} | {na:,} / {nc:,} | {rescued:,} of {nocedict:,} |")
    w("")
    with open(os.path.join(OUT, "tap-samples.tsv"), "w", encoding="utf-8") as f:
        f.write("source\tkind\tword\tcontext\tbook\n")
        for t in taps:
            for s in SOURCES:
                for text, start, length, aligned in t["found"][s]:
                    f.write(f"{s}\t{'aligned' if aligned else 'crossing'}\t{text}\t{t['context']}\t{t['book']}\n")
    w("### Example tap matches (full list: build/measure/tap-samples.tsv)\n")
    rnd = random.Random(1)
    for s in SOURCES:
        for kind in (True, False):
            ex = [(h[0], t["context"]) for t in taps for h in t["found"][s] if h[3] == kind]
            rnd.shuffle(ex)
            w(f"**{NAMES[s]}, {'aligned' if kind else 'crossing'}** ({len(ex):,}): " +
              "; ".join(f"{word} in {ctx}" for word, ctx in ex[:12]))
            w("")
    # Decided-reading words with no CC-CEDICT entry
    w("## 4. Words that decide a reading but show 'no definition in CC-CEDICT'\n")
    nodef = {x for x in words if x not in cedict}
    in_books = {x for x in nodef if x in types}
    w(f"- resolver words (words table) without a CC-CEDICT entry: {len(nodef):,}; of those seen as jieba "
      f"tokens in the books: {len(in_books):,} ({sum(types[x] for x in in_books):,} occurrences)\n")
    w("| Source | of all such words | of those in the books |")
    w("|---|---|---|")
    for s in SOURCES:
        a = sum(1 for x in nodef if x in src[s])
        b = sum(1 for x in in_books if x in src[s])
        w(f"| {NAMES[s]} | {a:,} ({pct(a, len(nodef))}) | {b:,} ({pct(b, len(in_books))}) |")
    w("")
    # Sizes
    w("## 5. Size each source would add\n")
    w("One row per indexed form (simp, trad, pinyin, defs = the short gloss used here; the real build would "
      "carry full senses, so treat these as lower bounds), two indexes, VACUUMed; zip -9 for the release zip.\n")
    w("| Source | rows | SQLite | in the zip |")
    w("|---|---|---|---|")
    for s in SOURCES:
        only_new = {h: e for h, e in src[s].items() if h not in cedict}
        raw, z, rows = db_size(only_new, os.path.join(OUT, f"size-{s}.sqlite"))
        w(f"| {NAMES[s]} | {rows:,} | {raw / 1e6:.1f} MB | {z / 1e6:.1f} MB |")
    w("")
    if src["rejected"].get("wp"):
        w("## 6. Wikipedia: what the filters drop (samples)\n")
        for k, v in src["rejected"]["wp"].items():
            w(f"- {k}: " + "; ".join(f"{a} ({b})" for a, b in v[:15]))
        w("")
        kept = [(h, e) for h, e in src["wp"].items() if h == e["head"] and h not in cedict]
        rnd.shuffle(kept)
        w("Kept, random sample: " + "; ".join(f"{h} ({e['gloss']})" for h, e in kept[:40]) + "\n")
    with open(os.path.join(OUT, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {os.path.join(OUT, 'report.md')}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--stage", choices=["all", "sources", "gaps", "taps", "report", "built"], default="all")
    ap.add_argument("--moe", default=os.path.join(BUILD, "chinesehelper-moe.sqlite"),
                    help="the MOE file from tools/build_moe.py (for --stage built)")
    ap.add_argument("--taps-per-book", type=int, default=150)
    ap.add_argument("--seed", type=int, default=20261111)
    ap.add_argument("--book", help="measure build/corpus/BOOK-*.txt only (from fetch_books.py --local BOOK); "
                    "reports and caches in build/measure/BOOK/, sources shared with the full run")
    args = ap.parse_args()
    if args.book:
        set_book(args.book)
    if args.stage in ("all", "sources") and not (args.book and args.stage == "all" and
                                                 os.path.exists(os.path.join(BUILD, "measure", "sources.pickle"))):
        stage_sources()
    if args.stage in ("all", "gaps"):
        stage_gaps()
    if args.stage in ("all", "taps"):
        stage_taps(args.taps_per_book, args.seed)
    if args.stage in ("all", "report"):
        stage_report()
    if args.stage == "built":
        stage_built(args.taps_per_book, args.seed, args.moe)
        report_built()


if __name__ == "__main__":
    sys.exit(main())
