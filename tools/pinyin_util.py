"""Pinyin helpers shared by build_data.py and eval_readings.py (no dependencies)."""
import unicodedata


def is_han(ch):
    cp = ord(ch)
    return (0x3400 <= cp <= 0x4DBF or 0x4E00 <= cp <= 0x9FFF or
            0xF900 <= cp <= 0xFAFF or 0x20000 <= cp <= 0x3134F)


VOWELS = "aeiouü"
MARKS = {
    "a": "āáǎà", "e": "ēéěè", "i": "īíǐì",
    "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ",
}


def numbered_to_marked(syl):
    """'lu:4' -> 'lǜ', 'zhuang4' -> 'zhuàng', 'ma5' -> 'ma'."""
    syl = syl.lower().replace("u:", "ü").replace("v", "ü")
    tone = 5
    if syl and syl[-1].isdigit():
        tone = int(syl[-1])
        syl = syl[:-1]
    if tone in (5, 0) or not syl:
        return syl
    # Standard placement: a or e take the mark; in "ou" the o does;
    # otherwise the last vowel.
    if "a" in syl:
        idx = syl.index("a")
    elif "e" in syl:
        idx = syl.index("e")
    elif "ou" in syl:
        idx = syl.index("o")
    else:
        idx = max((i for i, c in enumerate(syl) if c in VOWELS), default=-1)
        if idx < 0:  # 'm2', 'ng2', 'r5' ...
            return syl
    return syl[:idx] + MARKS[syl[idx]][tone - 1] + syl[idx + 1:]


def is_neutral(syl):
    return not syl[-1:].isdigit() or syl[-1] in "50"


def is_erhua(syl):
    return syl.lower() in ("r", "r5")


TONE_MARKS = "\u0304\u0301\u030c\u0300"  # macron, acute, caron, grave (not ü's diaeresis)


def strip_tone(marked):
    """'lǜ' -> 'lü', 'zhuàng' -> 'zhuang'."""
    nfd = unicodedata.normalize("NFD", marked)
    return unicodedata.normalize("NFC", "".join(c for c in nfd if c not in TONE_MARKS))


def is_toneless(marked):
    return strip_tone(marked) == marked


def only_neutral_differs(cedict_syls, pypinyin_syls):
    """True when the readings differ only where CC-CEDICT has a neutral tone and
    pypinyin has the same syllable with a tone (刺猬 cì wei / cì wèi)."""
    if len(cedict_syls) != len(pypinyin_syls) or cedict_syls == pypinyin_syls:
        return False
    for c, p in zip(cedict_syls, pypinyin_syls):
        if c != p and not (is_toneless(c) and not is_toneless(p) and strip_tone(p) == c):
            return False
    return True


# ---------------------------------------------------------------------------
# data/neutral_tone_overrides.tsv: words CC-CEDICT gives full tones that
# Standard Mandarin reads with a neutral syllable (喷嚏 pen1 ti4 -> pen1 ti5).
# Both CC-CEDICT readers (build_data.py, build_db.py) patch the matching lines'
# pinyin as they read them, so the existing neutral-tone rule draws it and the
# popup's word line shows it.
# ---------------------------------------------------------------------------

def load_neutral_overrides(path):
    """simplified word -> numbered syllables (lowercase), from the file."""
    import os
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                raise SystemExit(f"{path}:{n}: expected word<TAB>numbered pinyin")
            word, syls = fields[0], fields[1].lower().split()
            if len(word) < 2 or len(syls) != len(word) or not all(is_han(ch) for ch in word):
                raise SystemExit(f"{path}:{n}: {word}: one numbered syllable per character, two or more")
            if not all(s[-1:] in "12345" for s in syls) or "5" not in [s[-1] for s in syls[1:]]:
                raise SystemExit(f"{path}:{n}: {word}: numbered syllables, a neutral (5) after the first")
            if word in out:
                raise SystemExit(f"{path}:{n}: {word} listed twice")
            out[word] = syls
    return out


def neutral_override(simp, numbered, table, used=None):
    """CC-CEDICT pinyin `numbered` ("pen1 ti4") with the table's neutral
    syllables put in, when `simp` is in the table and the line has the same
    syllables apart from the tones the table makes neutral; else unchanged.
    Capitals (names) are kept. `used` (a set) collects the words applied."""
    want = table.get(simp)
    if not want:
        return numbered
    syls = numbered.split()
    if len(syls) != len(want):
        return numbered
    out = []
    for have, new in zip(syls, want):
        base_have, base_new = have.lower().rstrip("012345"), new.rstrip("12345")
        if base_have.replace("u:", "v") != base_new.replace("u:", "v"):
            return numbered
        if new.endswith("5"):
            out.append(have.rstrip("012345") + "5")
        elif have.lower().replace("u:", "v") != new.replace("u:", "v"):
            return numbered   # another tone elsewhere: a different reading
        else:
            out.append(have)
    if used is not None:
        used.add(simp)
    return " ".join(out)
