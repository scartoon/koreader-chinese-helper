#!/usr/bin/env python3
"""Build data/psc_neutral_words.tsv: the 普通话水平测试用必读轻声词语表 (the
Putonghua Proficiency Test's must-read neutral-tone word list), word and
pinyin, from two web reproductions (#60, Source A):

  PINYIN_URL  a page that gives every word's pinyin, neutral syllables toneless
              (爱 ( ài ) 人 ( ren ) 案子 ( ànzi ) ...), but splits words
              inconsistently;
  WORDS_URL   a page that lists the same words space-separated by letter
              (A：爱人 案子 B：巴掌 ...): the word boundaries.

The pages are downloaded into build/sources/psc/ (git-ignored) once; only the
derived word list is committed. The two must give the same characters in the
same order, or the script stops.

    python3 tools/psc_neutral_list.py [--cedict build/cedict_1_0_ts_utf-8_mdbg.txt.gz]
"""
import argparse
import html
import os
import re
import sys
import unicodedata
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pinyin_util import strip_tone  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "build", "sources", "psc")
OUT = os.path.join(ROOT, "data", "psc_neutral_words.tsv")
PINYIN_URL = "https://www.scst.edu.cn/yywz/50/80/c1942a20608/page.htm"
WORDS_URL = "https://jinengtisheng.com/3642.html"
HAN = "一-鿿"
PY_CHARS = "a-zA-Zāáǎàēéěèīíǐìōóǒòūúǔùüǖǘǚǜê'"


def page_text(url, name):
    os.makedirs(SRC, exist_ok=True)
    path = os.path.join(SRC, name)
    if not os.path.exists(path):
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as r, open(path, "wb") as f:
            f.write(r.read())
    t = open(path, "rb").read().decode("utf-8")
    t = re.sub(r"<script.*?</script>|<style.*?</style>", "", t, flags=re.S)
    t = html.unescape(re.sub(r"<[^>]+>", " ", t))
    return unicodedata.normalize("NFC", re.sub(r"\s+", " ", t))


def syllable_set(cedict):
    import gzip
    out = set()
    with gzip.open(cedict, "rt", encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\S+ \S+ \[([^\]]*)\]", line)
            if m:
                for s in m.group(1).lower().replace("u:", "ü").split():
                    s = s.rstrip("012345")
                    if s.isalpha():
                        out.add(s)
    out |= {"nue", "lue"}   # often written for nüe, lüe
    out.discard("r")
    return out


def split_syllables(joined, n, valid):
    """'ànzi', 2 -> ['àn', 'zi'], using the valid toneless syllables."""
    joined = joined.replace("'", "").replace(" ", "")
    plain = strip_tone(joined).lower()

    def go(i, k):
        if i == len(plain):
            return [] if k == 0 else None
        if k == 0:
            return None
        for j in range(min(len(plain), i + 6), i, -1):
            if plain[i:j] in valid:
                rest = go(j, k - 1)
                if rest is not None:
                    return [joined[i:j]] + rest
        return None
    return go(0, n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cedict", default=os.path.join(ROOT, "build", "cedict_1_0_ts_utf-8_mdbg.txt.gz"))
    args = ap.parse_args()
    valid = syllable_set(args.cedict)

    t = page_text(WORDS_URL, "words.html")
    body = t[t.index("A：爱人"):]
    body = body[:body.index("琢磨") + 2]
    words = re.findall(f"[{HAN}]+", re.sub(f"[A-Z]：", " ", body))

    t = page_text(PINYIN_URL, "pinyin.html")
    t = t[t.index("爱 ( ài"):].replace("zi] )", "zi )")   # one typo: 子 ( zi] )
    toks = re.findall(rf"([{HAN}]+)\s*\(\s*([{PY_CHARS} ]+?)\s*\)", t)
    # per-character syllables, in page order
    stream = []
    for chars, py in toks:
        syls = split_syllables(py, len(chars), valid)
        if syls is None:
            sys.exit(f"cannot split {chars} ({py})")
        stream += list(zip(chars, syls))
    # The word page has a few typos (鞭子 for 辫子): it gives only the
    # boundaries, the characters come from the pinyin page.
    if len(stream) != sum(map(len, words)):
        sys.exit(f"the pages differ in length: {len(stream)} / {sum(map(len, words))} characters")
    diffs = [(a, b) for a, b in zip("".join(c for c, _ in stream), "".join(words)) if a != b]
    print(f"{len(diffs)} characters differ between the pages (pinyin page kept): {diffs}")
    if len(diffs) > 10:
        sys.exit("too many differences: are they the same list?")

    rows, pos, seen = [], 0, set()
    for w in words:
        w = "".join(c for c, _ in stream[pos:pos + len(w)])
        syls = [s for _, s in stream[pos:pos + len(w)]]
        pos += len(w)
        key = (w, " ".join(syls))
        if key in seen:
            continue   # the pages repeat a few words (鞭子, 肚子)
        seen.add(key)
        rows.append(key)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("# 普通话水平测试用必读轻声词语表 (Putonghua Proficiency Test must-read neutral-tone words),\n"
                f"# from {PINYIN_URL} (pinyin) and\n# {WORDS_URL} (word boundaries),\n"
                "# by tools/psc_neutral_list.py. word <TAB> pinyin, a toneless syllable is neutral.\n")
        for w, py in rows:
            f.write(f"{w}\t{py}\n")
    print(f"{len(words)} words on the page, {len(rows)} distinct (word, pinyin) -> {OUT}")


if __name__ == "__main__":
    main()
