#!/usr/bin/env python3
"""Candidates for data/neutral_tone_overrides.tsv (#60, phase 2): words where a
source reads a syllable after the first as a neutral tone and CC-CEDICT gives
that syllable a full tone (喷嚏: CC-CEDICT pen1 ti4, said pēnti).

Sources:
  A  data/psc_neutral_words.tsv, the 普通话水平测试 must-read neutral-tone list
     (tools/psc_neutral_list.py);
  B  English Wiktionary via kaikki.org (build/sources/wiktionary/, the build's
     copy): Mandarin Standard Chinese pinyin, mainland or untagged; readings
     tagged Taiwan only, dialectal, regional or "phonetic" (sandhi applied) are
     ignored. Its "toneless final syllable variant" readings (喷嚏 pēnti beside
     pēntì) count.

Skipped: words CC-CEDICT does not have with the same syllables, syllables any
CC-CEDICT reading of the word already gives neutral, erhua r, and 一/不 (their
spoken tones are ch_sandhi.lua's). Words in the override file already are kept,
marked.

Writes docs/neutral-tone-candidates.tsv: word, CC-CEDICT pinyin, proposed pinyin
(numbered), sources (A, B), occurrences in the book corpus (build/corpus/, the
books kept in its index.tsv), and whether the neutral syllable's character gets
pinyin at the default level (rank above 3,500 or unranked: y/n), and for
source B whether Wiktionary's main reading is neutral ("main") or only its
toneless-final-syllable variant ("variant": 喷嚏 pēntì, variant pēnti). Only words
that occur in the corpus are written; all of them go to
build/neutral/candidates-all.tsv.

    python3 tools/neutral_candidates.py
"""
import gzip
import json
import os
import re
import sys
import unicodedata
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pinyin_util import is_erhua, is_toneless, load_neutral_overrides, numbered_to_marked, strip_tone  # noqa: E402
import fallback_sources as fs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CEDICT = os.path.join(ROOT, "build", "cedict_1_0_ts_utf-8_mdbg.txt.gz")
KAIKKI = os.path.join(ROOT, "build", "sources", "wiktionary", "kaikki-Chinese.jsonl.gz")
PSC = os.path.join(ROOT, "data", "psc_neutral_words.tsv")
CORPUS = os.path.join(ROOT, "build", "corpus")
CHARS = os.path.join(ROOT, "build", "data", "chars.tsv")
OUT = os.path.join(ROOT, "docs", "neutral-tone-candidates.tsv")
ALL_OUT = os.path.join(ROOT, "build", "neutral", "candidates-all.tsv")
DEFAULT_THRESHOLD = 3500
SANDHI = set("一不")
LINE_RE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /")
TONES = {"̄": 1, "́": 2, "̌": 3, "̀": 4}


def numbered(marked):
    """'tì' -> 'ti4', 'ti' -> 'ti5', 'lǜ' -> 'lu:4' (CC-CEDICT style)."""
    nfd = unicodedata.normalize("NFD", marked.lower())
    tone = next((TONES[c] for c in nfd if c in TONES), 5)
    plain = strip_tone(marked.lower()).replace("ü", "u:")
    return f"{plain}{tone}"


def plain(syls):
    return "".join(strip_tone(s.lower()) for s in syls).replace("u:", "ü")


def load_cedict():
    """simp -> list of readings (marked syllables), trad -> simp."""
    readings, simp_of = defaultdict(list), {}
    with gzip.open(CEDICT, "rt", encoding="utf-8") as f:
        for line in f:
            m = LINE_RE.match(line)
            if not m:
                continue
            trad, simp, py = m.groups()
            syls = py.split()
            if not 2 <= len(simp) <= 4 or len(syls) != len(simp) or any(s[:1].isupper() for s in syls):
                continue
            marked = [numbered_to_marked(s) for s in syls]
            if marked not in readings[simp]:
                readings[simp].append(marked)
            simp_of.setdefault(trad, simp)
    return readings, simp_of


def split_like(text, cedict_syls):
    """Split a source's pinyin ("pēnti") at CC-CEDICT's syllable boundaries,
    when the letters agree; else None."""
    text = unicodedata.normalize("NFC", re.sub(r"[\s'’-]", "", text))
    if strip_tone(text).lower() != plain(cedict_syls):
        return None
    out, i = [], 0
    for s in cedict_syls:
        n = len(strip_tone(s).replace("u:", "ü"))
        out.append(text[i:i + n].lower())
        i += n
    return out


def compare(word, source_syls, cedict):
    """(CC-CEDICT reading, proposed reading) when the source makes a syllable
    neutral that CC-CEDICT tones; else None."""
    for r in cedict.get(word, ()):
        src = split_like("".join(source_syls), r)
        if not src:
            continue
        positions = [k for k in range(1, len(word))
                     if is_toneless(src[k]) and not is_toneless(r[k]) and not is_erhua(src[k])
                     and word[k] not in SANDHI]
        # a syllable CC-CEDICT already gives neutral in some reading is settled
        positions = [k for k in positions
                     if not any(is_toneless(o[k]) and strip_tone(o[k]) == src[k] for o in cedict[word])]
        if positions:
            proposed = [src[k] if k in positions else r[k] for k in range(len(word))]
            return r, proposed
    return None


def wiktionary_readings(simp_of):
    """simp -> list of (Standard Chinese pinyin text, is a toneless-final-
    syllable variant), mainland or untagged."""
    out = defaultdict(list)
    with gzip.open(KAIKKI, "rt", encoding="utf-8") as f:
        for line in f:
            if '"Standard-Chinese"' not in line:
                continue
            e = json.loads(line)
            word = e.get("word", "")
            if not 2 <= len(word) <= 4:
                continue
            simp = simp_of.get(word, word)
            for s in fs._pinyin_sounds(e):
                tags = set(s.get("tags") or [])
                if not fs._standard(s) or "phonetic" in tags:
                    continue
                if "Taiwan" in tags and "Mainland-China" not in tags:
                    continue
                text = fs._sound_text(s)
                item = (text, "toneless-final-syllable-variant" in tags)
                if text and item not in out[simp]:
                    out[simp].append(item)
    return out


def corpus_counts(words):
    texts = []
    index = os.path.join(CORPUS, "index.tsv")
    with open(index, encoding="utf-8") as f:
        next(f)
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 4 and parts[3] == "1":
                texts.append(os.path.join(CORPUS, parts[0] + ".txt"))
    counts = Counter()
    by_len = defaultdict(list)
    for w in words:
        by_len[len(w)].append(w)
    regexes = [re.compile("(?=(" + "|".join(map(re.escape, ws)) + "))") for ws in by_len.values()]
    for path in texts:
        text = open(path, encoding="utf-8").read()
        for rx in regexes:
            counts.update(m.group(1) for m in rx.finditer(text))
    return counts, len(texts)


def main():
    cedict, simp_of = load_cedict()
    ranks = {}
    with open(CHARS, encoding="utf-8") as f:
        for line in f:
            ch, rank, _ = line.rstrip("\n").split("\t")
            ranks[ch] = int(rank)
    existing = load_neutral_overrides(os.path.join(ROOT, "data", "neutral_tone_overrides.tsv"))

    found = {}   # word -> [cedict, proposed, set(sources)]
    b_kind = {}  # word -> "main" (Wiktionary's reading is neutral) or "variant" (only its toneless variant)
    stats = Counter()

    def add(word, syls, source):
        res = compare(word, syls, cedict)
        if not res:
            return False
        r, p = res
        if word in found and found[word][1] != p:
            stats[f"{source}: differs from the other source's proposal (kept the first)"] += 1
            return True
        found.setdefault(word, [r, p, set()])[2].add(source)
        return True

    with open(PSC, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            word, py = line.rstrip("\n").split("\t")[:2]
            if word not in cedict:
                stats["A: not in CC-CEDICT"] += 1
            elif add(word, py.split(), "A"):
                stats["A: candidates"] += 1
            else:
                stats["A: CC-CEDICT agrees (or 一/不, erhua)"] += 1

    for word, texts in wiktionary_readings(simp_of).items():
        if word not in cedict:
            continue
        texts = sorted(texts, key=lambda t: t[1])   # main readings first
        hit = next((variant for t, variant in texts if add(word, [t], "B")), None)
        if hit is not None:
            b_kind[word] = "variant" if hit else "main"
            stats["B: candidates"] += 1

    counts, nbooks = corpus_counts(found)
    rows = []
    for word, (r, p, sources) in found.items():
        neutral_chars = [word[k] for k in range(len(word)) if p[k] != r[k]]
        ruby = any(ranks.get(ch, 0) == 0 or ranks[ch] > DEFAULT_THRESHOLD for ch in neutral_chars)
        rows.append((word, " ".join(numbered(s) for s in r), " ".join(numbered(s) for s in p),
                     ",".join(sorted(sources)), counts[word], "y" if ruby else "n",
                     b_kind.get(word, ""), "y" if word in existing else ""))
    rows.sort(key=lambda r: (-r[4], r[0]))
    header = "word\tcedict\tproposed\tsources\tcount_in_books\taffects_ruby\twikt_reading\n"
    os.makedirs(os.path.dirname(ALL_OUT), exist_ok=True)
    with open(ALL_OUT, "w", encoding="utf-8") as f:
        f.write(header.rstrip("\n") + "\tin_overrides\n")
        for row in rows:
            f.write("\t".join(map(str, row)) + "\n")
    kept = [row for row in rows if row[4] > 0]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(header)
        for row in kept:
            f.write("\t".join(map(str, row[:7])) + "\n")
    for k in sorted(stats):
        print(f"{k}: {stats[k]}")
    by_src = Counter(row[3] for row in kept)
    print(f"{len(rows)} candidates, {len(kept)} in the {nbooks} corpus books -> {OUT}; by source {dict(by_src)}; "
          f"affect ruby: {sum(row[5] == 'y' for row in kept)}; Wiktionary {dict(Counter(row[6] for row in kept))}")


if __name__ == "__main__":
    main()
