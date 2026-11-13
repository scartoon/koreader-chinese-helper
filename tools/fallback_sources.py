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
    source      "wikt", "wp", "cbdb", "moe" or "moegirl"

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
  wp    Chinese Wikipedia article titles with an English article, filtered
        to technology, engineering, military and history (CC BY-SA 4.0):
        the gloss is the English article's title.
  cbdb  CBDB's Ming and Southern Ming office titles (CC BY-NC-SA 4.0 and
        CBDB's own terms): the user's own local file, never the release.
  moegirl  萌娘百科 (Moegirlpedia) internet-slang pages, the opening sentence
        or two (CC BY-NC-SA 3.0 CN): the user's own local file, never the
        release.

Every gloss goes through font_safe(): KOReader's fonts may not draw emoji,
kaomoji and decorative symbols, so they are taken out.
"""
import gzip
import json
import lzma
import os
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
DEGREE = set("很太最更挺极極超颇頗较較多")
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
        if first in PARTICLES:
            return "particle + word"
        if first in measure and len(word) == 2:
            return "measure word + word"
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
# Glosses KOReader can draw
# ---------------------------------------------------------------------------

# Only the newer sources (wp, cbdb, moegirl) go through it: Wiktionary's and
# MOE's few hundred such glosses need what it would take out (Sanskrit ṣ,
# 10²⁸, MOE's □ for characters it cannot encode, the trigrams ☱☴ of 中孚).
# Kept: ASCII, Latin letters with diacritics (pinyin tone marks, Minié ball,
# Sanskrit and Vietnamese transliterations),
# general punctuation (– — ‘ ’ “ ” …), CJK punctuation, kana and bopomofo,
# Han characters (with radicals and compatibility forms), full-width forms.
# Everything else (emoji, kaomoji parts, ★ ♯ ① → and other symbols, Greek,
# Cyrillic, Hangul, IPA, combining marks) is taken out.
FONT_SAFE = re.compile("[^\u0020-\u007e\u00b7\u00c0-\u024f\u1e00-\u1eff\u2010-\u2027\u2e80-\u2fdf"
                       "\u3000-\u312f\u31f0-\u31ff\ufe30-\ufe4f\uff01-\uff65" + HAN + "]")
EMPTY_BRACKETS = re.compile(r"\(\s*\)|（\s*）|「\s*」|『\s*』|《\s*》|【\s*】|〔\s*〕|“\s*”|‘\s*’|\[\s*\]")


GREEK = dict(zip("αβγδεζηθικλμνξοπρστυφχψω",
                 "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho "
                 "sigma tau upsilon phi chi psi omega".split()))


def font_safe(text):
    """`text` without characters KOReader's fonts may not draw, and without
    the empty brackets and doubled spaces that leaves. Greek small letters
    are spelt out first (α-Methylfentanyl -> alpha-Methylfentanyl)."""
    if any(c in GREEK for c in text):
        text = "".join(GREEK.get(c, c) for c in text)
    clean = FONT_SAFE.sub("", text)
    if clean == text and not EMPTY_BRACKETS.search(text):
        return text
    prev = None
    while prev != clean:
        prev, clean = clean, EMPTY_BRACKETS.sub("", clean)
    return re.sub(r" {2,}", " ", clean).strip()


def font_safe_rows(rows, stats, name, examples=None):
    """The rows with font_safe() glosses, counting the glosses that had
    characters to take out and dropping rows left without a gloss.
    examples: a list to collect (source, word, characters taken out)."""
    out = []
    for simp, trad, pinyin, syl, defs, source in rows:
        clean = "/".join(x for x in (font_safe(d) for d in defs.split("/")) if x)
        if FONT_SAFE.search(defs):
            stats[f"{name}: glosses with characters fonts may not draw (cleaned)"] += 1
            if examples is not None and len(examples) < 2000:
                examples.append((name, simp, "".join(sorted(set(FONT_SAFE.findall(defs))))))
        if not clean:
            stats[f"{name}: glosses left empty (dropped)"] += 1
            continue
        out.append((simp, trad, pinyin, syl, clean, source))
    return out


def generated_pinyin(word):
    """pypinyin's reading of a word, for sources that give none (shown as a
    generated reading, never used for annotations)."""
    from pypinyin import Style, pinyin
    return " ".join(s[0] for s in pinyin(word, style=Style.TONE, heteronym=False, errors="ignore"))


# ---------------------------------------------------------------------------
# Chinese Wikipedia titles (tools/wikipedia_dump.py)
# ---------------------------------------------------------------------------


def wikipedia_rows(dump_dir, cedict, measure, stats):
    """Rows (simp, trad, pinyin, syllables, defs, "wp"): article titles of 3-8
    Han characters with an English article, in a technology, engineering,
    military or history category, and not a person, list or disambiguation
    page, nor in a category wikipedia_dump.WP_PLACE (towns, rivers, stations,
    schools, companies, films, songs ...) or WP_NATURE (living things,
    chemical compounds) matches; other places, organisations and works are
    kept on purpose: they say what a translated name refers to. The
    gloss is the English title; the reading is generated (pypinyin)."""
    import opencc
    import wikipedia_dump as W
    t2s, s2t = opencc.OpenCC("t2s"), opencc.OpenCC("s2t")
    tech = re.compile(W.WP_TECH.pattern + W.WP_EXTRA_TECH)
    rows, seen = [], set()
    for _pid, (title, english, cats, disamb) in sorted(W.titles_with_english(dump_dir, stats).items()):
        if disamb or "列表" in title or english.startswith("List of"):
            stats["wp: disambiguation pages and lists (dropped)"] += 1
            continue
        if len(title) < 3:
            stats["wp: titles shorter than 3 characters (dropped)"] += 1
            continue
        if any(W.PERSON_CAT.search(c) for c in cats):
            stats["wp: people (dropped)"] += 1
            continue
        if not any(tech.search(c) or W.WP_HIST.search(c) for c in cats):
            stats["wp: no technology/history category (dropped)"] += 1
            continue
        if any(W.WP_PLACE.search(c) for c in cats):
            stats["wp: places, organisations, works (dropped)"] += 1
            continue
        if any(W.WP_NATURE.search(c) for c in cats):
            stats["wp: living things, chemical compounds (dropped)"] += 1
            continue
        simp, trad = t2s.convert(title), s2t.convert(title)
        if not han_word(simp) or not han_word(trad):
            stats["wp: not Han-only 1-8 after conversion (dropped)"] += 1
            continue
        if simp in cedict or trad in cedict or title in cedict:
            stats["wp: CC-CEDICT has the headword (dropped)"] += 1
            continue
        if everyday(simp, cedict, measure) or everyday(trad, cedict, measure):
            stats["wp: everyday combinations (dropped)"] += 1
            continue
        if simp in seen:
            stats["wp: second article for the same headword (dropped)"] += 1
            continue
        seen.add(simp)
        gloss = clean_sense(english.replace("_", " "))
        rows.append((simp, trad, generated_pinyin(simp), "", gloss, "wp"))
    rows = font_safe_rows(rows, stats, "wp")
    stats["wp: rows"] = len(rows)
    return rows


# ---------------------------------------------------------------------------
# CBDB office titles (China Biographical Database, OFFICE_CODES)
# ---------------------------------------------------------------------------

CBDB_MING = (19, 80)    # DYNASTIES.c_dy: 明, 南明
CBDB_NO_TRANSLATION = "office title (Ming)"


def cbdb_rows(cbdb_sqlite, cedict, measure, stats):
    """Rows (simp, trad, pinyin, syllables, defs, "cbdb") for the Ming and
    Southern Ming office titles: each name and alternative name, under its
    traditional form and OpenCC's t2s. The gloss is CBDB's English
    translation followed by "(Ming office title)", or CBDB_NO_TRANSLATION;
    the reading is CBDB's own (toneless)."""
    import opencc
    t2s, s2t = opencc.OpenCC("t2s"), opencc.OpenCC("s2t")
    con = sqlite3.connect(f"file:{cbdb_sqlite}?mode=ro", uri=True)
    q = ("SELECT c_office_id, c_office_chn, c_office_chn_alt, c_office_pinyin, c_office_trans FROM OFFICE_CODES "
         f"WHERE c_dy IN ({','.join(map(str, CBDB_MING))}) ORDER BY c_office_id")
    rows, seen = [], set()
    for _oid, chn, alt, py, trans in con.execute(q):
        stats["cbdb: Ming office codes"] += 1
        trans = re.sub(r"\s+", " ", (trans or "")).strip()
        if not trans or trans.startswith("["):
            stats["cbdb: ... without an English translation"] += 1
            gloss = CBDB_NO_TRANSLATION
        else:
            gloss = clean_sense(trans) + " (Ming office title)"
        names = [chn] + re.split(r"[;；,，/、]", alt or "")
        for name in names:
            name = (name or "").strip()
            if not han_word(name):
                continue
            trad, simp = s2t.convert(t2s.convert(name)), t2s.convert(name)
            if not han_word(simp) or not han_word(trad):
                continue
            if simp in cedict or trad in cedict or name in cedict:
                stats["cbdb: names CC-CEDICT has (dropped)"] += 1
                continue
            if everyday(simp, cedict, measure, protected=True):
                stats["cbdb: numerals (dropped)"] += 1
                continue
            if simp in seen:
                stats["cbdb: names given twice (dropped)"] += 1
                continue
            seen.add(simp)
            rows.append((simp, trad, re.sub(r"\s+", " ", py or "").strip(), "", gloss, "cbdb"))
    con.close()
    rows = font_safe_rows(rows, stats, "cbdb")
    stats["cbdb: rows"] = len(rows)
    return rows


# ---------------------------------------------------------------------------
# Moegirlpedia (萌娘百科) internet slang, from an offline .slob snapshot
# (tools/moegirl_slob.py)
# ---------------------------------------------------------------------------

# Pages the slang filter lets through that are not slang terms, found by
# checking all 535 titles by hand (2026-11-12): characters, people, works,
# companies, events and fictional abilities, and ordinary words and phrases
# a novel uses in their plain sense (完全一致, 民风淳朴, 拼刺刀), where a
# meme definition would mislead.
MOEGIRL_EXCLUDE = set("""
三小野 四大辅 四迹 叶良辰 赵日天 郭鹏 忧郁的台湾乌龟 罗老师别这样
不破冰菓 原外桃 宗黄红烧肉 肩口一久青 轰力雷树 鬼头鼓修理 蔚奥莱 兜冢守桔梗 华城绫女 奥间狸吉 早乙女乙女
月见草胧 栉田桔梗 桔梗凛生 桔梗芹 芳川桔梗 菅原桔梗 爱川梢 锁链康妮 五月病表情娘 五道杠娘 僵尸粉娘 喷子娘
彼尔德娘 河蟹娘 金坷垃娘 黄溜溜娘 微萌更新姬 敏感酱
七夕青蛙和不孤鸟 三国志姜维传 剑侠情缘网络版叁 恋与制作人 锁链战记 黑塔利亚 宅男腐女恋爱真难 我的名字叫夏语遥
掌派科技 勇仕网络 蛮啾网络 米哈游 猫扑 天使动漫萌战 漫萌战 挺好萌 盗版舰娘抵制事件 阴影魔女事件 京阿尼神教
格拉摩根 深圳 涪陵榨菜 猪牙花粉 共感 密度操控 化狐 阿破克烈
完全一致 民风淳朴 拼刺刀 带球撞人 倒垃圾 老兵回忆录 可喜可贺 借你吉言 时代在进步 我同学 才八点 什么都做不到
骗吃骗喝 那个人 夫妻档 早鸟 六分仪 正教 精密检查 音效卡 竹节虫 高血压 心肌梗塞 书名号 动宾短语
""".split())
SENTENCE = re.compile(r"[^。！？]*[。！？]?")


def moegirl_gloss(opening, limit=160):
    """The opening's first sentence, and the second when the first is short
    (under 40 characters) and both fit in `limit`."""
    import moegirl_slob
    first = moegirl_slob.first_sentence(opening, limit)
    rest = opening[len(first):].strip() if opening.startswith(first) else ""
    second = SENTENCE.match(rest).group(0).strip() if rest else ""
    if second and len(first) < 40 and len(first) + len(second) <= limit:
        return first + second
    return first


def _moegirl_parse(item):
    import moegirl_slob
    key, html_text = item
    r = moegirl_slob.parse(html_text)
    if r["title"] != key or not r["opening"]:
        return key, None
    gloss = moegirl_slob.first_sentence(r["opening"])
    if moegirl_slob.kind(r["opening"]) != "term" or not moegirl_slob.is_slang(gloss):
        return key, None
    return key, moegirl_gloss(r["opening"])


def _moegirl_items(path):
    import moegirl_slob
    for key, _blob, html_text in moegirl_slob.entries(path):
        if 2 <= len(key) <= 8 and han_word(key):
            yield key, html_text


def moegirl_rows(slob_path, cedict, measure, stats, examples=None):
    """Rows (simp, trad, pinyin, syllables, defs, "moegirl"): Moegirlpedia's
    internet-slang pages (moegirl_slob.kind() "term" and is_slang()), 2-8 Han
    characters, the page's own title (no redirects), less MOEGIRL_EXCLUDE.
    simp: OpenCC t2s of the title; trad: s2t of that. The gloss is the
    opening sentence or two in Chinese, 黑幕 and struck-through text removed
    by the parser; the reading is generated (pypinyin)."""
    import multiprocessing
    import opencc
    t2s, s2t = opencc.OpenCC("t2s"), opencc.OpenCC("s2t")
    found = {}
    with multiprocessing.Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        for n, (key, gloss) in enumerate(pool.imap_unordered(_moegirl_parse, _moegirl_items(slob_path),
                                                              chunksize=64), 1):
            if gloss:
                found[key] = gloss
            if n % 20000 == 0:
                print(f"  moegirl: {n:,} pages read", flush=True)
    stats["moegirl: slang pages"] = len(found)
    rows, seen = [], set()
    for key in sorted(found):
        simp = t2s.convert(key)
        trad = s2t.convert(simp)
        if key in MOEGIRL_EXCLUDE or simp in MOEGIRL_EXCLUDE:
            stats["moegirl: excluded by hand (not slang, or a plain word)"] += 1
            continue
        if not han_word(simp) or not han_word(trad):
            continue
        if simp in cedict or trad in cedict or key in cedict:
            stats["moegirl: CC-CEDICT has the headword (dropped)"] += 1
            continue
        if everyday(simp, cedict, measure):
            stats["moegirl: everyday combinations (dropped)"] += 1
            continue
        if simp in seen:
            continue
        seen.add(simp)
        rows.append((simp, trad, generated_pinyin(simp), "", clean_sense(found[key]), "moegirl"))
    rows = font_safe_rows(rows, stats, "moegirl", examples)
    stats["moegirl: rows"] = len(rows)
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


# ---------------------------------------------------------------------------
# The user's own files (MOE, CBDB, Moegirlpedia): a fallback table and a meta
# table, written by tools/build_moe.py, build_cbdb.py and build_moegirl.py.
# ---------------------------------------------------------------------------

DEVICE_DIR = "/sdcard/koreader/data/chinesehelper"


def write_local_file(out, rows, meta, name):
    """Write `rows` and `meta` to `out` (through a temporary file), checking
    that the plugin's lookup uses the indexes. `name` is for messages."""
    import sqlite3 as _sqlite3
    tmp = out + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    con = _sqlite3.connect(tmp)
    con.execute("PRAGMA page_size = 4096")
    write_fallback(con, rows)
    con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
    con.commit()
    for n in (1, 36):
        plan = "\n".join(r[3] for r in con.execute("EXPLAIN QUERY PLAN " + fallback_sql(n), ["x"] * (2 * n)))
        if "USING INDEX fallback_simp" not in plan or "USING INDEX fallback_trad" not in plan:
            raise SystemExit(f"{name} lookup does not use its indexes:\n{plan}")
    con.execute("VACUUM")
    con.close()
    os.replace(tmp, out)


def push_or_explain(path, push):
    """adb push `path` to the device's KOReader data folder, or print how."""
    import subprocess
    target = f"{DEVICE_DIR}/{os.path.basename(path)}"
    if push:
        subprocess.run(["adb", "shell", "mkdir", "-p", DEVICE_DIR], check=True)
        subprocess.run(["adb", "push", path, target], check=True)
        print(f"Pushed to {target}")
    else:
        print(f"To install: adb shell mkdir -p {DEVICE_DIR} && adb push {os.path.relpath(path)} {target}")


def sha256_of(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download_file(url, path):
    """Download `url` to `path` (through path + ".part")."""
    import urllib.request
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    print(f"Downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "koreader-chinese-helper build script"})
    with urllib.request.urlopen(req, timeout=600) as r, open(path + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(path + ".part", path)
    return path
