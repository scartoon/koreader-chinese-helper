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
  and cross-references made readable (`variant of 夠|够[gou4]` → `variant of 够 gòu`,
  `鮮卑|鲜卑` → `鲜卑`).
- `fallback`: entries from English Wiktionary for words CC-CEDICT does not have
  (`tools/fallback_sources.py`). Same columns as `entries` plus `source` ("wikt"); `syllables` is
  empty (fallback entries take no part in reading markers).

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
- **Wiktionary** (English Wiktionary's Chinese entries), by Wiktionary contributors, CC BY-SA
  4.0 — https://en.wiktionary.org/ — via kaikki.org's wiktextract extraction,
  https://kaikki.org/dictionary/Chinese/ (Tatu Ylonen, "Wiktextract: Wiktionary as
  Machine-Readable Structured Data", LREC 2022), for the `fallback` table.

Changes made to the Wiktionary data: only entries with a Mandarin pinyin reading (mainland
reading first); senses marked only for a non-Mandarin variety (Cantonese, Hokkien, Wu...) dropped;
simplified-form redirect pages and "alternative form of" entries resolved to the entry they point
to; entries whose senses only name places dropped; headwords that are not 1–8 Han characters
dropped; headwords CC-CEDICT has (in either script) dropped; everyday combinations dropped (a
numeral, demonstrative, pronoun, adverb, measure word or particle before a word CC-CEDICT has, or
a locative or particle after one, e.g. 很多, 这次, 一天, 脸上; entries Wiktionary marks historical or
classical are kept) and numerals dropped; senses kept with their qualifiers ("(historical)"), one
"/" between senses, a "/" inside a sense written "／".

Not part of this data: the optional MOE dictionary (中華民國教育部《重編國語辭典修訂本》,
CC BY-ND 3.0 TW, https://github.com/g0v/moedict-data), which `tools/build_moe.py` builds into a
separate file for the user's own device. It is never committed or released.

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
| Wiktionary | English Wiktionary dump of **2026-10-01**, kaikki.org extraction of 2026-10-30 (wiktextract 19f9a30), `kaikki.org-dictionary-Chinese.jsonl.gz`, SHA-256 `9663c01322014cea417fbe4812cc073ca2d6a6998946edb244bf4f26853819c9`; 60,950 fallback rows |

`tools/build_db.py` prints the CC-CEDICT date, entry count and checksum and the Wiktionary dump
date, extraction date and checksum, and records them with the wordfreq and pypinyin versions in
the database's `meta` table; update this table whenever
the release database is rebuilt. mdbg.net and kaikki.org only serve the current
CC-CEDICT and the current extraction, so keep copies of the files if an exact rebuild matters.

For reference, the MOE file built on 2026-11-11 (not distributed) came from g0v/moedict-data commit
925fa83 (2026-07-11), `dict-revised.json.xz` SHA-256
`5cc4ec0efd7e549621edf9b46d261989230c1729d9dc2c8e2056f4b21c8a93da`: 90,501 rows.
