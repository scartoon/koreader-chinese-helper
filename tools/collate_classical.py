#!/usr/bin/env python3
"""Research prototype for #49: collect the identifiably classical senses of
single characters from every open dictionary into one table.

    .venv/bin/python tools/collate_classical.py

Reads (all under build/, git-ignored):
  chinesehelper.koplugin/data/chinesehelper.sqlite    CC-CEDICT (entries)
  build/sources/wiktionary/kaikki-Chinese.jsonl.gz    English Wiktionary
  build/sources/chinesenotes/cnotes_zh_en_dict.tsv    Chinese Notes
  build/sources/unihan/Unihan.zip                     Unihan kDefinition
  build/sources/moe/dict-revised.json.xz              MOE 重編國語辭典

Writes build/classical/extract/<source>.tsv (one row per extracted sense)
and build/classical/collated.tsv: trad, simp, source, reading, sense, tag.
The extraction rules ("identifiably classical") are in each extract_*
function and in docs/research/classical-dictionary.md.
"""
import collections
import csv
import gzip
import io
import json
import lzma
import os
import re
import sqlite3
import zipfile

import opencc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "build", "sources")
OUT = os.path.join(ROOT, "build", "classical")
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
t2s = opencc.OpenCC("t2s")
s2t = opencc.OpenCC("s2t")
FIELDS = ["trad", "simp", "source", "reading", "sense", "tag"]


def han1(w):
    return len(w) == 1 and ("㐀" <= w <= "鿿" or "\U00020000" <= w <= "\U0003ffff")


# ---------------------------------------------------------------- CC-CEDICT
CEDICT_TAG = re.compile(r"^\((literary|classical|archaic|old|obsolete)\)\s*|\s*\((literary|classical|archaic)\)$")


def extract_cedict():
    """Senses CC-CEDICT itself labels (literary), (classical), (archaic),
    (old) or (obsolete), at the start or end of the sense."""
    out = []
    for simp, trad, pinyin, defs in sqlite3.connect(DB).execute(
            "SELECT simp, trad, pinyin, defs FROM entries WHERE length(simp) = 1"):
        if pinyin[:1].isupper():
            continue
        for sense in defs.split("/"):
            m = CEDICT_TAG.search(sense)
            if m:
                out.append(dict(trad=trad, simp=simp, source="cedict", reading=pinyin,
                                sense=sense.strip(), tag=m.group(1) or m.group(2)))
    return out


# ---------------------------------------------------------------- Wiktionary
WIKT_TAGS = {"literary", "archaic", "obsolete", "Classical", "historical"}
DIALECT = {"Cantonese", "Hokkien", "Min", "Hakka", "Wu", "Teochew", "Xiang", "Gan", "Jin", "Shanghainese",
           "Taiwanese-Hokkien", "Xiamen", "Zhangzhou-Hokkien", "Quanzhou", "Puxian-Min", "Leizhou-Min",
           "Hainanese", "Sichuanese", "Dungan", "Pinghua", "Southern", "Eastern", "Northern", "dialectal",
           "Hong-Kong", "Singapore", "Malaysia", "Philippine", "Penang-Hokkien", "Jinjiang-Hokkien", "Macau",
           "Internet", "slang", "neologism"}
ALT = re.compile(r"^(alternative|alternative form|variant|obsolete form|archaic form|simplified form|"
                 r"traditional form|abbreviation|misspelling|erhua form|eye dialect|clipping|"
                 r"short form|alternative name|ancient form|same as|original form)s? (form )?of\b", re.I)


def wikt_reading(entry):
    for s in entry.get("sounds", []):
        tags = set(s.get("tags", []))
        if "Mandarin" in tags and "Pinyin" in tags and s.get("zh_pron"):
            return s["zh_pron"].split(",")[0].strip()
    return ""


def extract_wikt():
    """Senses of single-character entries tagged literary, archaic, obsolete,
    Classical or historical, or qualified "obsolete on its own in Standard
    Chinese" / "Classical Chinese"; not dialect senses, not "variant of"."""
    out = []
    path = os.path.join(SRC, "wiktionary", "kaikki-Chinese.jsonl.gz")
    for line in gzip.open(path, "rt"):
        e = json.loads(line)
        w = e.get("word", "")
        if not han1(w):
            continue
        reading = wikt_reading(e)
        for s in e.get("senses", []):
            tags = set(s.get("tags", []))
            raw = " ".join(s.get("raw_glosses") or s.get("glosses") or [])
            gl = "; ".join(s.get("glosses") or [])
            if not gl or tags & DIALECT or "alt-of" in tags or ALT.match(gl) or \
                    re.search(r"\b(Korean|Japanese|Vietnamese)\b", raw):
                continue
            hit = tags & WIKT_TAGS
            tag = sorted(hit)[0] if hit else None
            if not tag and "obsolete on its own" in raw:
                tag = "obsolete-alone"
            if not tag and "Classical Chinese" in raw:
                tag = "Classical"
            if not tag:
                continue
            out.append(dict(trad=s2t.convert(w) if w == t2s.convert(w) else w, simp=t2s.convert(w),
                            source="wikt", reading=reading, sense=raw.strip(), tag=tag))
    return out


# ---------------------------------------------------------------- Chinese Notes
def extract_cn():
    """Single-character senses in the "Literary Chinese" domain. A modern
    Chinese equivalent given in the notes ("In the sense of 距离") is kept
    after the gloss."""
    out = []
    path = os.path.join(SRC, "chinesenotes", "cnotes_zh_en_dict.tsv")
    for line in open(path):
        if line.startswith("#"):
            continue
        r = line.rstrip("\n").split("\t")
        simp, trad = r[1], (r[2] if r[2] != "\\N" else r[1])
        if not han1(simp) or r[9] != "Literary Chinese" or r[4] in ("\\N", ""):
            continue
        sense = r[4]
        m = re.match(r"In the sense of ([^\s(;,.]+(?: or [^\s(;,.]+)?)", r[14])
        if m:
            sense += f" (≈ {m.group(1)})"
        out.append(dict(trad=trad, simp=simp, source="cn", reading=r[3], sense=sense, tag=r[5]))
    return out


# ---------------------------------------------------------------- Unihan
def extract_unihan(rank):
    """kDefinition, untagged: kept only for characters outside the 3,000
    most frequent (tag "rare"); common characters' kDefinition is mostly
    the modern sense."""
    out = []
    z = zipfile.ZipFile(os.path.join(SRC, "unihan", "Unihan.zip"))
    name = [n for n in z.namelist() if "Readings" in n][0]
    defs, mand = {}, {}
    for line in io.TextIOWrapper(z.open(name), encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        cp, field, value = line.rstrip("\n").split("\t")
        ch = chr(int(cp[2:], 16))
        if field == "kDefinition":
            defs[ch] = value
        elif field == "kMandarin":
            mand[ch] = value.split()[0]
    for ch, d in defs.items():
        r = rank.get(t2s.convert(ch)) or 99999
        tag = "rare" if r > 3000 else "common"
        for sense in d.split(";"):
            if sense.strip():
                out.append(dict(trad=ch, simp=t2s.convert(ch), source="unihan", reading=mand.get(ch, ""),
                                sense=sense.strip(), tag=tag))
    return out


# ---------------------------------------------------------------- words (#67)
def han_word(w):
    return len(w) >= 2 and all(han1(c) for c in w)


def extract_words():
    """Words of two or more characters: Chinese Notes' Literary Chinese
    senses (with a gloss) and Wiktionary's literary, Classical, archaic,
    obsolete or historical senses, by the same rules as for characters."""
    out = []
    for line in open(os.path.join(SRC, "chinesenotes", "cnotes_zh_en_dict.tsv")):
        if line.startswith("#"):
            continue
        r = line.rstrip("\n").split("\t")
        simp, trad = r[1], (r[2] if r[2] != "\\N" else r[1])
        if not han_word(simp) or r[9] != "Literary Chinese" or r[4] in ("\\N", ""):
            continue
        out.append(dict(trad=trad, simp=simp, source="cn", reading=r[3], sense=r[4], tag=r[5]))
    for line in gzip.open(os.path.join(SRC, "wiktionary", "kaikki-Chinese.jsonl.gz"), "rt"):
        e = json.loads(line)
        w = e.get("word", "")
        if not han_word(w):
            continue
        for s in e.get("senses", []):
            tags = set(s.get("tags", []))
            raw = " ".join(s.get("raw_glosses") or s.get("glosses") or [])
            gl = "; ".join(s.get("glosses") or [])
            if not gl or tags & DIALECT or "alt-of" in tags or ALT.match(gl) or \
                    re.search(r"\b(Korean|Japanese|Vietnamese)\b", raw):
                continue
            hit = tags & WIKT_TAGS
            tag = sorted(hit)[0] if hit else ("Classical" if "Classical Chinese" in raw else None)
            if tag:
                out.append(dict(trad=s2t.convert(w) if w == t2s.convert(w) else w, simp=t2s.convert(w),
                                source="wikt", reading=wikt_reading(e), sense=raw.strip(), tag=tag))
    return out


# ---------------------------------------------------------------- MOE
NOVELS = ("水滸傳", "紅樓夢", "儒林外史", "西遊記", "三國演義", "金瓶梅", "老殘遊記", "兒女英雄傳", "醒世恆言",
          "喻世明言", "警世通言", "拍案驚奇", "鏡花緣", "官場現形記", "文明小史", "孽海花", "封神演義", "俠五義",
          "儒林", "野叟曝言", "二十年目睹之怪現狀", "初刻", "二刻", "負曝閒談", "歧路燈", "醒世姻緣傳",
          "海上花", "品花寶鑑", "七俠", "說岳", "隋唐演義", "東周列國志", "平妖傳", "濟公傳", "西湖二集")
LATE = re.compile(r"^(元|明|清|民國|近代|現代)．")


def moe_classical_quote(q):
    if LATE.match(q) or any(n in q for n in NOVELS):
        return False
    return True


def extract_moe():
    """Senses with a 書證 from a pre-modern, non-vernacular work: a quote
    whose author is dated before the Yuan, or a classic quoted without a
    dynasty (《孟子》, 《韓非子》), never a Ming-Qing novel."""
    out = []
    d = json.load(lzma.open(os.path.join(SRC, "moe", "dict-revised.json.xz")))
    for e in d:
        w = e.get("title", "")
        if not han1(w):
            continue
        for h in e.get("heteronyms", []):
            for df in h.get("definitions", []):
                quotes = df.get("quote", [])
                if any(moe_classical_quote(q) for q in quotes):
                    sense = df.get("def", "").strip()
                    cite = next(q for q in quotes if moe_classical_quote(q))
                    out.append(dict(trad=w, simp=t2s.convert(w), source="moe", reading=h.get("pinyin", ""),
                                    sense=f"{sense} ‖ {cite}", tag="quote"))
    return out


def main():
    os.makedirs(os.path.join(OUT, "extract"), exist_ok=True)
    rank = dict(sqlite3.connect(DB).execute("SELECT ch, rank FROM chars"))
    sources = {"cedict": extract_cedict, "wikt": extract_wikt, "cn": extract_cn,
               "unihan": lambda: extract_unihan(rank), "moe": extract_moe}
    allrows = []
    for name, fn in sources.items():
        rows = fn()
        with open(os.path.join(OUT, "extract", name + ".tsv"), "w", newline="") as f:
            w = csv.DictWriter(f, FIELDS, delimiter="\t")
            w.writeheader()
            w.writerows(rows)
        tags = collections.Counter(r["tag"] for r in rows)
        print(f"{name}: {len(rows)} senses on {len({r['trad'] for r in rows})} characters; {dict(tags.most_common(6))}")
        allrows += rows
    with open(os.path.join(OUT, "collated.tsv"), "w", newline="") as f:
        w = csv.DictWriter(f, FIELDS, delimiter="\t")
        w.writeheader()
        w.writerows(allrows)


if __name__ == "__main__":
    main()
