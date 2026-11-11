# Data

The plugin's database, `chinesehelper.koplugin/data/chinesehelper.sqlite`, is built by
`tools/build_db.py` and shipped in the release zip, not committed (see the main README). This
folder holds the hand-made and learned inputs it is built from, which are small and are
committed so that a rebuild needs no dataset downloads beyond CC-CEDICT:

| File | Made by | |
|---|---|---|
| `overrides.tsv` | hand | Checked readings that win over every source: a character's default reading, or a word's reading (or `-` to remove a word). Each line says why. |
| `special_curated.tsv` | hand | Unusual readings of common characters in names and historical terms (单于 *chán yú*), with a short note. Always included. |
| `rules.tsv` | `tools/learn_from_cpp.py` | Context rules: char, L or R, the neighbouring character, the reading, the number of training examples (each: at least 5, at least 95% agreeing). |
| `uncertain.tsv` | `tools/learn_from_cpp.py` | Characters whose default reading is unreliable when no word or rule decides: char, confidence in the default, the two most likely readings. Below 75% confidence. |

Everything else is generated into `build/` (git-ignored) by `tools/build_data.py` and packed
into the database with CC-CEDICT by `tools/build_db.py`:

- `chars`: every character with its frequency rank and default reading (the most frequent
  reading, weighted by how often the words using each reading occur).
- `words`: 2–4 character words containing a character with more than one reading, or with
  several dictionary readings themselves (东西), from CC-CEDICT and pypinyin's phrase list, with
  each word's frequency.
- `special`, `special_guard`: the unusual-readings list (from `special_curated.tsv`, plus words
  found automatically) and the overlap guards that keep it from matching by accident.
- `entries`: CC-CEDICT itself, one row per entry, with numbered pinyin converted to tone marks
  and cross-references made readable (`variant of 夠|够[gou4]` → `variant of 够 gòu`).

## Sources and licences

The data is derived from, and distributed under,
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/):

- **CC-CEDICT**, © MDBG and contributors, CC BY-SA 4.0 —
  https://www.mdbg.net/chinese/dictionary?page=cc-cedict
- **wordfreq** data by Robyn Speer, CC BY-SA 4.0 — https://github.com/rspeer/wordfreq
- **pypinyin** by mozillazg (character readings and its phrase list, `phrases_dict`), MIT
  License — https://github.com/mozillazg/python-pinyin
- the **CPP polyphone dataset** by Kyubyong Park and Seanie Lee (train split only, for
  `rules.tsv` and `uncertain.tsv`), https://github.com/kakaobrain/g2pM — repository Apache-2.0
  with no separate licence for the sentences, which come from Chinese Wikipedia (CC BY-SA); the
  sentences themselves are not included, only rules and statistics learned from them.

Changes made: characters ranked by summed word frequency; default readings chosen by the
frequency of the words using each reading; numbered pinyin converted to tone marks; pypinyin
phrases merged in (first reading of each syllable; where both sources have a word and disagree,
CC-CEDICT is kept unless it differs only by a neutral tone on a rare character); 一 and 不 kept at
their dictionary tones (pypinyin writes the spoken tone changes); neutral tones on rare
characters replaced by the character's toned reading with the same letters; for common words
with several CC-CEDICT readings, one chosen for the popup to mark (pypinyin's if it matches one,
else the neutral-tone one, else the first); each word's frequency added; CC-CEDICT
cross-references reformatted; everything stored in SQLite.

## Versions used

The release database was built on 2026-11-11 from:

| Source | Version |
|---|---|
| CC-CEDICT | release dated **2026-11-09T04:23:50Z**, 125,397 entries (`cedict_1_0_ts_utf-8_mdbg.txt.gz`, SHA-256 `2e8921a90b9abdca2ce78b8a6af104368f848681b7afe8020043f500fbe0238a`) |
| wordfreq | 3.1.1 |
| pypinyin | 0.55.0 |
| CPP dataset | train split, as fetched by `tools/learn_from_cpp.py` |

`tools/build_db.py` prints the CC-CEDICT date, entry count and checksum, and records them with
the wordfreq and pypinyin versions in the database's `meta` table; update this table whenever
the release database is rebuilt. mdbg.net only serves the current CC-CEDICT, so keep a copy of
the file if an exact rebuild matters.
