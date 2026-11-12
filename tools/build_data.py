#!/usr/bin/env python3
"""Build the reading tables (the resolver's data) from CC-CEDICT, wordfreq and
pypinyin. Normally run through tools/build_db.py, which packs these tables and
CC-CEDICT into the plugin's SQLite database.

Outputs (tab-separated UTF-8 text, in build/data/ by default; git-ignored):

  chars.tsv   char <TAB> rank <TAB> default reading
              Every character with a known reading. rank = frequency rank of the
              character in modern written Chinese (traditional characters take
              the rank of their simplified form); 0 = not in the frequency list
              (treat as very rare). Only characters ranked above 1,000 (or 0) can
              ever be annotated; the others are here for the tap popup, which
              marks the reading of any character.
  words.tsv   word <TAB> reading of each syllable, space-separated
              <TAB> frequency (occurrences per billion words, from wordfreq;
              traditional forms take the frequency of their simplified form)
              Words (2-4 characters, simplified and traditional forms) that
              contain a polyphonic character. Words come from CC-CEDICT and from
              pypinyin's phrase list.
  word_marks.tsv   word <TAB> the reading the tap popup marks, space-separated
              Only where it differs from words.tsv and words.tsv's reading is
              another of the word's CC-CEDICT readings: words.tsv gives a rare
              character's neutral tone as its own tone (大爷 dà yé, drawn), and
              the popup must still mark dà ye "uncle", not dà yé "idler".
  special.tsv, special_guard.tsv   unusual readings of common characters
              (see special_words.py)
  reading_shares.tsv   (not used by the plugin)
              char <TAB> default reading <TAB> reading:share ... (most common first)
              for every polyphonic character: how its readings split in ordinary
              text, estimated from the frequency of the words that use each
              reading. Used by tools/learn_from_cpp.py and tools/eval_readings.py.
  special_review.tsv   (not used by the plugin) every special word and why.

Everything about characters that can be annotated (rank above 1,000 or 0) is
built exactly as in koreader-interlinear-pinyin 0.5.0, so the pinyin drawn on
a page does not change. What the wider coverage adds, for common characters
only:
  * a word with several CC-CEDICT readings takes the one pypinyin's phrase
    list gives, when it gives one of them (便宜 pián yi, 明朝 míng cháo, a
    proper-name reading); where it is silent, a word of common characters
    whose readings differ only by a neutral tone takes the neutral one (东西
    dōngxi "thing", not dōngxī "east and west");
  * 一 and 不 keep their dictionary tones (yī, bù) in pypinyin phrases too:
    pypinyin writes the spoken tone changes (一定 yí, 不是 bú), CC-CEDICT and
    this plugin do not.

data/overrides.tsv holds hand-checked readings that win over both sources:
one character replaces its default reading, 2-4 characters add or replace a word
(or remove it, with the reading "-").

Usage:
  pip install wordfreq pypinyin
  python3 tools/build_data.py --cedict build/cedict_1_0_ts_utf-8_mdbg.txt.gz

CC-CEDICT: https://www.mdbg.net/chinese/dictionary?page=cc-cedict
"""

import argparse
import functools
import gzip
import os
import re
import unicodedata
from collections import Counter, defaultdict

import wordfreq
import special_words
from importlib.metadata import version
from pypinyin.phrases_dict import phrases_dict
from pypinyin.pinyin_dict import pinyin_dict

from pinyin_util import (is_erhua, is_han, is_neutral, is_toneless, numbered_to_marked,
                         only_neutral_differs, strip_tone)

# Characters ranked at or above this are never annotated by any menu setting
# (they are still in the data, for the tap popup).
MIN_ANNOTATABLE_RANK = 1000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_DATA = os.path.join(ROOT, "build", "data")

# pypinyin writes 一 and 不 with their spoken tone changes; CC-CEDICT and the
# plugin use the dictionary tones.
SANDHI_BASE = {"一": ("yī", {"yí", "yì"}), "不": ("bù", {"bú"})}


def base_tones(phrase, syls):
    """一定 [yí, dìng] -> [yī, dìng]; 不是 [bú, shì] -> [bù, shì]."""
    out = []
    for ch, syl in zip(phrase, syls):
        base = SANDHI_BASE.get(ch)
        out.append(base[0] if base and syl in base[1] else syl)
    return out
MAX_WORD_LEN = 4

# Single-character CC-CEDICT entries that do not describe an ordinary modern
# reading (for the reading-share estimate only).
MINOR_DEF_RE = re.compile(r"^\((dialect|archaic|old|literary|onom\.)\)|^(old |archaic |)variant of|"
                          r"^see [^/]*\]$|^used in [^/]*\]$")
LINE_RE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$")


def cedict_header(path):
    """The '#! key=value' header of a CC-CEDICT file (date, entries, ...)."""
    opener = gzip.open if path.endswith(".gz") else open
    header = {}
    with opener(path, "rt", encoding="utf-8") as f:
        for line in f:
            if not line.startswith("#"):
                break
            if line.startswith("#! ") and "=" in line:
                key, value = line[3:].strip().split("=", 1)
                header[key] = value
    return header


def load_cedict(path):
    opener = gzip.open if path.endswith(".gz") else open
    entries = []
    with opener(path, "rt", encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            m = LINE_RE.match(line.strip())
            if not m:
                continue
            trad, simp, py, defs = m.groups()
            syls = py.split()
            if len(syls) != len(simp) or len(trad) != len(simp):
                continue
            entries.append((trad, simp, syls, defs))  # original case: capitals mark names
    return entries


def load_overrides(path):
    """form -> list of marked syllables, from data/overrides.tsv."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                raise SystemExit(f"{path}:{n}: expected form<TAB>reading")
            form, reading = fields[0], unicodedata.normalize("NFC", fields[1])
            if reading == "-":
                if len(form) < 2:
                    raise SystemExit(f"{path}:{n}: only words can be removed")
                if form in out:
                    raise SystemExit(f"{path}:{n}: {form} listed twice")
                out[form] = None
                continue
            syls = reading.split()
            if len(syls) != len(form) or not all(is_han(ch) for ch in form):
                raise SystemExit(f"{path}:{n}: {form} has {len(form)} characters but {len(syls)} syllables")
            if form in out:
                raise SystemExit(f"{path}:{n}: {form} listed twice")
            out[form] = syls
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cedict", required=True)
    ap.add_argument("--out", default=BUILD_DATA)
    args = ap.parse_args()
    build(args.cedict, args.out)


def build(cedict, out, overrides_path=os.path.join(ROOT, "data", "overrides.tsv"),
          curated_path=os.path.join(ROOT, "data", "special_curated.tsv")):
    """Write the reading tables for CC-CEDICT file `cedict` into directory `out`."""
    args = argparse.Namespace(cedict=cedict, out=out, overrides=overrides_path, curated=curated_path,
                              shares_out=os.path.join(out, "reading_shares.tsv"))
    overrides = load_overrides(args.overrides)

    freq = wordfreq.get_frequency_dict("zh")  # simplified-only keys

    # 1. Character frequency rank (modern written Chinese, simplified).
    char_freq = Counter()
    for w, f in freq.items():
        for ch in w:
            if is_han(ch):
                char_freq[ch] += f
    simp_rank = {ch: i + 1 for i, (ch, _) in enumerate(char_freq.most_common())}

    entries = load_cedict(args.cedict)
    header = cedict_header(args.cedict)
    # Record this in data/README.md when the data is rebuilt.
    print(f"CC-CEDICT {header.get('date', '(no date in header)')}, {header.get('entries', '?')} entries; "
          f"wordfreq {getattr(wordfreq, '__version__', None) or version('wordfreq')}, "
          f"pypinyin {version('pypinyin')}")

    # 2. Traditional -> simplified mapping, from CEDICT's aligned pairs.
    t2s_counts = defaultdict(Counter)
    for trad, simp, _, _ in entries:
        for t, s in zip(trad, simp):
            if is_han(t) and is_han(s):
                t2s_counts[t][s] += 1

    def to_simplified(form):
        return "".join(t2s_counts[ch].most_common(1)[0][0] if ch in t2s_counts and ch not in simp_rank
                       else ch for ch in form)

    def word_freq(form, simp=None):
        """Occurrences per billion words. wordfreq keys are simplified only."""
        f = freq.get(simp or form)
        if f is None:
            f = freq.get(to_simplified(form), 0.0)
        return round(f * 1e9)

    def rank_of(ch):
        if ch in simp_rank:
            return simp_rank[ch]
        if ch in t2s_counts:
            s = t2s_counts[ch].most_common(1)[0][0]
            return simp_rank.get(s, 0)
        return 0

    # 3. Readings per character, weighted by how often the words using each
    #    reading occur. Neutral tones only count when nothing else exists.
    weights = defaultdict(Counter)
    # The same, counted in simplified forms only and in traditional forms only:
    # 乾 is qián in simplified text but mostly gān (干) in traditional.
    script_weights = {"simp": defaultdict(Counter), "trad": defaultdict(Counter)}
    neutral = defaultdict(Counter)
    single_entry_reading = {}
    for trad, simp, syls, _ in entries:
        wf = freq.get(simp, 0.0) + 1e-9
        syls = [s.lower() for s in syls]
        for script, form in (("simp", simp), ("trad", trad)):
            for ch, syl in zip(form, syls):
                if is_han(ch) and not is_neutral(syl):
                    script_weights[script][ch][syl] += wf
        for form in {trad, simp}:
            for ch, syl in zip(form, syls):
                if not is_han(ch):
                    continue
                if is_neutral(syl):
                    neutral[ch][syl] += wf
                else:
                    weights[ch][syl] += wf
            if len(form) == 1 and form not in single_entry_reading and not is_neutral(syls[0]):
                single_entry_reading[form] = syls[0]

    def default_reading(ch):
        if weights[ch]:
            return numbered_to_marked(weights[ch].most_common(1)[0][0])
        if ch in single_entry_reading:
            return numbered_to_marked(single_entry_reading[ch])
        py = pinyin_dict.get(ord(ch))
        if py:
            return unicodedata.normalize("NFC", py.split(",")[0])
        if neutral[ch]:
            return numbered_to_marked(neutral[ch].most_common(1)[0][0])
        return None

    def annotatable(ch):
        r = rank_of(ch)
        return r == 0 or r > MIN_ANNOTATABLE_RANK

    all_chars = set(weights) | set(neutral) | set(single_entry_reading)
    all_chars |= {chr(cp) for cp in pinyin_dict if is_han(chr(cp))}

    rows = []
    for ch in all_chars:
        reading = default_reading(ch)
        if reading:
            rows.append((ch, rank_of(ch), reading))
    rows.sort(key=lambda r: (r[1] == 0, r[1], r[0]))
    # Hand-checked default readings.
    char_overrides = {form: syls[0] for form, syls in overrides.items() if len(form) == 1 and syls}
    rows = [(ch, rank, char_overrides.get(ch, reading)) for ch, rank, reading in rows]

    # Annotatable characters only, as in 0.5.0: neutral-tone fixing and the
    # special words are defined on these.
    defaults = {ch: reading for ch, rank, reading in rows if annotatable(ch)}
    all_defaults = {ch: reading for ch, _, reading in rows}

    def toned_readings(ch):
        """The character's toned readings, default first, then by frequency."""
        out = [defaults[ch]] if ch in defaults else []
        for syl, _ in weights[ch].most_common():
            marked = numbered_to_marked(syl)
            if marked not in out:
                out.append(marked)
        return out

    def fix_neutral(form, marked_syls, siblings=()):
        """CC-CEDICT writes spoken neutral tones (刺猬 cì wei). Above a rare
        character we want its own tone, so a toneless syllable of an
        annotatable character takes that character's toned reading with the
        same letters (the default when it matches): wei -> wèi, and 冷颤 zhan
        -> zhàn even though 颤's default is chàn. With no such reading it is
        left as written (萝卜 bo: 卜 is otherwise only bǔ). Erhua 'r' is left
        alone. siblings: the word's other dictionary readings; a tone one of
        them gives that syllable comes first (裁缝 cái feng "tailor" -> féng,
        as in cái féng "to tailor", not 缝's default fèng)."""
        out = []
        for k, (ch, syl) in enumerate(zip(form, marked_syls)):
            if is_toneless(syl) and not is_erhua(syl) and ch in defaults:
                from_siblings = [r[k] for r in siblings if len(r) == len(form) and r[k] != syl]
                for reading in from_siblings + toned_readings(ch):
                    if strip_tone(reading) == syl and reading != syl:
                        syl = reading
                        break
            out.append(syl)
        return out

    # 4. pypinyin's phrase list (built for polyphone disambiguation): first
    #    reading of each syllable, 2-4 character phrases only.
    py_phrases = {}
    for phrase, readings in phrases_dict.items():
        if not 2 <= len(phrase) <= MAX_WORD_LEN or not all(is_han(ch) for ch in phrase):
            continue
        if len(readings) != len(phrase) or not all(readings):
            continue
        py_phrases[phrase] = [unicodedata.normalize("NFC", r[0]) for r in readings]
    # The special words are built from pypinyin's own spelling, as in 0.5.0
    # (they never mark 一 or 不); everything else uses the dictionary tones.
    py_phrases_raw = dict(py_phrases)
    py_phrases = {phrase: base_tones(phrase, syls) for phrase, syls in py_phrases.items()}

    # 5. Polyphonic annotatable characters: those with several toned readings in
    #    CC-CEDICT, plus those whose reading in some pypinyin phrase differs from
    #    their default.
    poly = {ch for ch in all_chars
            if annotatable(ch) and len({numbered_to_marked(s) for s in weights[ch]}) > 1}
    cedict_poly = len(poly)
    for phrase, syls in py_phrases.items():
        for ch, syl in zip(phrase, fix_neutral(phrase, syls)):
            if ch in defaults and syl != defaults[ch]:
                poly.add(ch)
    # The same for every character (common ones too, for the tap popup).
    poly_all = set(poly) | {ch for ch in all_chars if len({numbered_to_marked(s) for s in weights[ch]}) > 1}
    for phrase, syls in py_phrases.items():
        for ch, syl in zip(phrase, syls):
            if ch in all_defaults and not annotatable(ch) and not is_toneless(syl) and syl != all_defaults[ch]:
                poly_all.add(ch)

    def has_annotatable(form):
        return any(annotatable(ch) for ch in form)

    # 6. Words that disambiguate them. CC-CEDICT first; prefer an ordinary word
    #    over a proper-name reading of the same form, and keep the first entry
    #    otherwise (where pypinyin's phrase list does not choose; see below).
    # Common words CC-CEDICT gives several ordinary readings (东西 dōngxī "east
    # and west" / dōngxi "thing"): included even without a polyphonic
    # character, so the popup can mark one (chosen below).
    readings_by_form = defaultdict(list)    # ordinary readings only
    every_reading = defaultdict(list)       # proper-name readings too (lower case: 明朝 Míng cháo -> míng cháo)
    simp_of = defaultdict(set)              # form -> the simplified forms of its entries
    for trad, simp, syls, _ in entries:
        if not 2 <= len(simp) <= MAX_WORD_LEN:
            continue
        marked = [numbered_to_marked(s) for s in syls]
        is_name = any(s[:1].isupper() for s in syls)
        for form in {simp, trad}:
            simp_of[form].add(simp)
            if marked not in every_reading[form]:
                every_reading[form].append(marked)
            if not is_name and marked not in readings_by_form[form]:
                readings_by_form[form].append(marked)

    def phrase_reading(form):
        """pypinyin's reading of a form, or of its simplified form (traditional
        forms are rarely in its phrase list)."""
        if form in py_phrases:
            return py_phrases[form]
        simps = simp_of.get(form, ())
        return py_phrases.get(next(iter(simps))) if len(simps) == 1 else None

    def ambiguous_common(form):
        return len(readings_by_form.get(form, ())) > 1 and not has_annotatable(form)

    words = {}   # form -> [syllables (raw marked), is_name, simplified form]
    for trad, simp, syls, _ in entries:
        if not 2 <= len(simp) <= MAX_WORD_LEN:
            continue
        marked = [numbered_to_marked(s) for s in syls]
        is_name = any(s[:1].isupper() for s in syls)
        for form in (simp, trad):
            if not any(ch in poly_all for ch in form) and not ambiguous_common(form):
                continue
            if form in words and (words[form][1] is False or is_name):
                continue
            words[form] = [marked, is_name, simp]

    # Merge pypinyin. Where both have the word and they disagree, keep
    # CC-CEDICT unless the only difference is CC-CEDICT's neutral tones.
    stats = Counter()
    for phrase, syls in py_phrases.items():
        if not any(ch in poly_all for ch in phrase):
            continue
        if ambiguous_common(phrase):
            continue  # decided below
        if phrase not in words:
            words[phrase] = [syls, False, None]
            stats["pypinyin added"] += 1
        elif words[phrase][0] != syls:
            stats["disagree"] += 1
            if only_neutral_differs(words[phrase][0], syls) and has_annotatable(phrase):
                words[phrase][0] = syls
                stats["disagree: took pypinyin (neutral tone)"] += 1
            else:
                stats["disagree: kept CC-CEDICT"] += 1

    # Which reading of an ambiguous common word to mark in the popup: the one
    # pypinyin's phrase list (built for this) agrees with; else, of readings
    # that differ only by a neutral tone, the neutral one, the everyday sense
    # (东西 dōngxi, 地道 dìdao); else CC-CEDICT's first.
    for form, readings in readings_by_form.items():
        if form not in words or not ambiguous_common(form):
            continue
        py = py_phrases.get(form)
        if py in readings:
            choice = py
            stats["ambiguous common words: pypinyin"] += 1
        else:
            neutral = [r for r in readings if any(only_neutral_differs(r, o) for o in readings)]
            choice = neutral[0] if neutral else readings[0]
            stats["ambiguous common words: " + ("neutral tone" if neutral else "first")] += 1
        words[form][0] = choice

    # Any word with several CC-CEDICT readings, proper names included: where
    # pypinyin's phrase list (built for polyphone disambiguation) gives one of
    # them, that one (便宜 pián yi, not CC-CEDICT's first entry biàn yí; 明朝
    # míng cháo, the dynasty, over míng zhāo "tomorrow morning"). Where it is
    # silent, the choice above stands: an ordinary reading over a proper
    # name, the first entry otherwise; overrides.tsv settles the rest.
    for form, readings in every_reading.items():
        if form not in words or len(readings) < 2:
            continue
        py = phrase_reading(form)
        if py in readings and words[form][0] != py:
            words[form][0] = py
            stats["several CC-CEDICT readings: pypinyin's chosen"] += 1

    # Hand-checked words win over both sources.
    for form, syls in overrides.items():
        if len(form) > 1 and syls is None:
            stats["overrides: removed"] += 1 if words.pop(form, None) else 0
        elif len(form) > 1:
            stats["overrides: " + ("replaced" if form in words else "added")] += 1
            words[form] = [syls, False, None]

    neutral_fixed = set()
    word_rows = []
    # The reading the popup marks, where it is not the one drawn: the neutral
    # tone a rare character's pinyin turns into its own tone is another of the
    # word's dictionary readings (大爷 dà ye "uncle" is drawn dà yé, which is
    # also CC-CEDICT's dà yé "arrogant idler"), so the popup would mark that.
    word_marks = []
    for form in sorted(words):
        syls, _, simp = words[form]
        others = [r for r in every_reading.get(form, ()) if r != syls]
        fixed = fix_neutral(form, syls, others)
        neutral_fixed.update(ch for ch, a, b in zip(form, syls, fixed) if a != b)
        word_rows.append((form, " ".join(fixed), word_freq(form, simp)))
        if fixed != syls and fixed in others:
            word_marks.append((form, " ".join(syls)))

    # 7. How each polyphonic character's readings split in ordinary text:
    #    summed frequency of the CC-CEDICT words using each toned reading, plus
    #    readings only pypinyin's phrases have. Readings whose only support is
    #    a single-character entry marked dialect, archaic or a variant (甭 bèng,
    #    "(dialect) very") are left out unless nothing else is left. A
    #    hand-checked default (overrides.tsv) gets a 90% share.
    minor_only = defaultdict(set)    # char -> readings seen only in minor entries
    major = defaultdict(set)
    for trad, simp, syls, defs in entries:
        is_minor = len(simp) == 1 and MINOR_DEF_RE.search(defs)
        for form in {trad, simp}:
            for ch, syl in zip(form, syls):
                if is_han(ch) and not is_neutral(syl.lower()):
                    (minor_only if is_minor else major)[ch].add(numbered_to_marked(syl.lower()))
    phrases_with = defaultdict(list)   # char -> pypinyin phrases containing it, in order
    for phrase in py_phrases:
        for ch in set(phrase):
            phrases_with[ch].append(phrase)

    def default_of(ch):
        """Default reading of any character, annotatable or not."""
        return defaults.get(ch) or default_reading(ch)

    @functools.lru_cache(maxsize=None)
    def shares_of(ch, script=None):
        """reading -> share of ch's use in ordinary text (see above). Works for
        any character, not only the annotatable polyphonic ones. script
        "simp" or "trad" counts only CC-CEDICT words written in that script."""
        w = Counter()
        for syl, f in (script_weights[script] if script else weights)[ch].items():
            marked = numbered_to_marked(syl)
            if marked in minor_only[ch] and marked not in major[ch]:
                continue
            w[marked] += f
        for phrase in phrases_with[ch]:
            for c, syl in zip(phrase, fix_neutral(phrase, py_phrases[phrase])):
                if c == ch and not is_toneless(syl) and syl not in w:
                    w[syl] += word_freq(phrase) / 1e9 + 1e-9
        default = default_of(ch)
        if default and default not in w:
            w[default] = 0.0
        total = sum(w.values()) or 1.0
        shares = {r: f / total for r, f in w.items()}
        if ch in char_overrides:
            rest = sum(v for r, v in shares.items() if r != default)
            shares = {r: (0.9 if r == default else (0.1 * v / rest if rest else 0.0))
                      for r, v in shares.items()}
        return shares

    share_rows = []
    for ch in sorted(poly_all):
        ordered = sorted(shares_of(ch).items(), key=lambda kv: -kv[1])
        share_rows.append((ch, all_defaults[ch], " ".join(f"{r}:{v:.4f}" for r, v in ordered)))
    # 8. Unusual readings of common characters in names and historical terms
    #    (special.tsv, special_guard.tsv in build/data); see special_words.py.
    special = special_words.build(
        entries=entries, py_phrases=py_phrases_raw, shares_of=shares_of, default_of=default_of,
        word_freq=word_freq, wordfreq_dict=freq, curated_path=args.curated)
    os.makedirs(args.out, exist_ok=True)
    special.write(args.out, os.path.join(os.path.dirname(args.shares_out), "special_review.tsv"))

    os.makedirs(os.path.dirname(args.shares_out), exist_ok=True)
    with open(args.shares_out, "w", encoding="utf-8") as f:
        f.write("# char\tdefault\treading:share ... (generated by tools/build_data.py)\n")
        for row in share_rows:
            f.write("\t".join(row) + "\n")

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "chars.tsv"), "w", encoding="utf-8") as f:
        for ch, rank, reading in rows:
            f.write(f"{ch}\t{rank}\t{reading}\n")
    with open(os.path.join(args.out, "words.tsv"), "w", encoding="utf-8") as f:
        for form, reading, wf in word_rows:
            f.write(f"{form}\t{reading}\t{wf}\n")
    with open(os.path.join(args.out, "word_marks.tsv"), "w", encoding="utf-8") as f:
        for form, reading in word_marks:
            f.write(f"{form}\t{reading}\n")

    print(f"chars.tsv: {len(rows)} characters "
          f"({sum(1 for r in rows if r[1])} ranked, {len(poly_all)} polyphonic; annotatable: {len(poly)}, "
          f"{cedict_poly} from CC-CEDICT, {len(poly) - cedict_poly} more from pypinyin)")
    print(f"words.tsv: {len(word_rows)} words "
          f"({sum(1 for r in word_rows if r[2])} with a frequency)")
    for key in sorted(stats):
        print(f"  {key}: {stats[key]}")
    print(f"  neutral tones replaced for {len(neutral_fixed)} annotatable characters")
    print(f"word_marks.tsv: {len(word_marks)} words whose popup reading is not the one drawn")


if __name__ == "__main__":
    main()
