# Data

The plugin's database, `chinesehelper.koplugin/data/chinesehelper.sqlite`, is built by
`tools/build_db.py` and shipped in the release zip, not committed (see the main README). This
folder holds the hand-made and learned inputs it is built from, which are small and are
committed so that a rebuild needs no dataset downloads beyond CC-CEDICT:

| File | Made by | |
|---|---|---|
| `overrides.tsv` | hand | Checked readings that win over every source: a character's default reading (or a default and the runner-up shown when nothing decides, `得 de/děi`), or a word's reading (or `-` to remove a word). Each line says why. |
| `special_curated.tsv` | hand | Unusual readings of common characters in names and historical terms (单于 *chán yú*), with a short note. Always included. |
| `rules.tsv` | `tools/learn_from_cpp.py` | Context rules: char, L or R, the neighbouring character, the reading, the number of training examples (each: at least 5, at least 95% agreeing). |
| `rules_exclude.tsv` | hand | Learned rules `learn_from_cpp.py` must leave out (char, L or R, the neighbour, why): it generates `rules.tsv`, so a bad rule is excluded here rather than deleted there. |
| `uncertain.tsv` | `tools/learn_from_cpp.py` | Characters whose default reading is unreliable when no word or rule decides: char, confidence in the default, the two most likely readings. Below 75% confidence, plus the hand-checked pairs from `overrides.tsv`. |

Everything else is generated into `build/` (git-ignored) by `tools/build_data.py` and packed
into the database with CC-CEDICT by `tools/build_db.py`:

- `chars`: every character with its frequency rank and default reading (the most frequent
  reading, weighted by how often the words using each reading occur).
- `words`: 2–4 character words containing a character with more than one reading, or with
  several dictionary readings themselves (东西), from CC-CEDICT and pypinyin's phrase list, with
  each word's frequency.
- `word_marks`: the reading the popup marks for a word, for the few words where it is not the
  one in `words` (大爷: *dà yé* is drawn above the rare 爷, the popup marks *dà ye* "uncle").
- `special`, `special_guard`: the unusual-readings list (from `special_curated.tsv`, plus words
  found automatically) and the overlap guards that keep it from matching by accident.
- `entries`: CC-CEDICT itself, one row per entry, with numbered pinyin converted to tone marks
  and cross-references made readable (`variant of 夠|够[gou4]` → `variant of 够 gòu`,
  `鮮卑|鲜卑` → `鲜卑`).
- `fallback`: entries from English Wiktionary and Chinese Wikipedia titles for words CC-CEDICT
  does not have (`tools/fallback_sources.py`). Same columns as `entries` plus `source` ("wikt" or
  "wp"); `syllables` is empty (fallback entries take no part in reading markers).

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
- **Chinese Wikipedia** article titles and the titles of the English Wikipedia articles they
  link to, by Wikipedia contributors, CC BY-SA 4.0 — https://zh.wikipedia.org/ — from the
  Wikimedia SQL dumps (`page`, `langlinks`, `page_props`, `categorylinks`, `linktarget`),
  https://dumps.wikimedia.org/zhwiki/, for the `fallback` table; licence
  https://creativecommons.org/licenses/by-sa/4.0/.

Changes made to the Wiktionary data: only entries with a Mandarin pinyin reading (mainland
reading first); senses marked only for a non-Mandarin variety (Cantonese, Hokkien, Wu...) dropped;
simplified-form redirect pages and "alternative form of" entries resolved to the entry they point
to; entries whose senses only name places dropped; headwords that are not 1–8 Han characters
dropped; headwords CC-CEDICT has (in either script) dropped; everyday combinations dropped (a
numeral, demonstrative, pronoun, adverb, measure word or particle before a word CC-CEDICT has, or
a locative or particle after one, e.g. 很多, 这次, 一天, 脸上; entries Wiktionary marks historical or
classical are kept) and numerals dropped; senses kept with their qualifiers ("(historical)"), one
"/" between senses, a "/" inside a sense written "／".

Changes made to the Wikipedia data: articles only (no redirects), titles of 3–8 Han characters
with an English article; disambiguation pages, lists and people dropped; kept only with a
technology, engineering, military or history category; dropped when a category marks the article
as a town, county, district, river, peak, island, station, airport, street, road, railway, school,
university, company, sports team, film, TV drama, album, song, novel, game, anime or manga
(`wikipedia_dump.WP_PLACE`), or as a living thing, mineral or chemical compound
(`wikipedia_dump.WP_NATURE`); other places, organisations and works are kept (glaciers,
observatories, museums, associations, parties, TV series, books); headwords CC-CEDICT has and everyday combinations
dropped; each title under its OpenCC `t2s` and `s2t` forms; the English title as the gloss
(underscores as spaces, Greek letters spelt out, characters KOReader's fonts may not draw taken
out); a reading generated with pypinyin, shown as such.

Not part of this data, never committed or released: three optional dictionaries that
`tools/build_moe.py`, `tools/build_cbdb.py` and `tools/build_moegirl.py` build into separate
files for the user's own device.

- **MOE**, 中華民國教育部《重編國語辭典修訂本》 — https://dict.revised.moe.edu.tw/ — © Ministry of
  Education, Republic of China (Taiwan), CC BY-ND 3.0 TW —
  https://creativecommons.org/licenses/by-nd/3.0/tw/ — read from g0v/moedict-data,
  https://github.com/g0v/moedict-data.
- **CBDB**, the China Biographical Database (Harvard University, Academia Sinica, Peking
  University) — https://cbdb.hsites.harvard.edu/ — its SQLite release,
  https://huggingface.co/datasets/cbdb/cbdb-sqlite (via https://github.com/cbdb-project/cbdb_sqlite).
  Licence: CBDB Data Licensing Terms, https://cbdb.hsites.harvard.edu/cbdb-data-licensing-terms
  (CC BY-NC-SA 4.0, https://creativecommons.org/licenses/by-nc-sa/4.0/, for data within the
  current standalone release; CBDB's own non-commercial, no-derivatives, no-redistribution terms
  beyond it). The project applies the stricter terms: only the build script is distributed, and
  the file is built by its user for personal, non-commercial use and never shared. Used: `OFFICE_CODES` rows of the Ming (`c_dy` 19) and Southern Ming (80): every name
  and alternative name of 1–8 Han characters, under its traditional form and OpenCC `t2s`; CBDB's
  English translation with "(Ming office title)" added, or "office title (Ming)" when CBDB has
  none ("[Not Yet Translated]"); CBDB's toneless reading. Names CC-CEDICT has dropped.
- **Moegirlpedia**, 萌娘百科 — https://zh.moegirl.org.cn — by its contributors, CC BY-NC-SA 3.0 CN —
  https://creativecommons.org/licenses/by-nc-sa/3.0/cn/ — read from a third party's offline
  snapshot, zhmoegirl-20230507-alpha.slob,
  https://github.com/aisuneko/dicts_for_aard2/releases/tag/moegirl-alpha (listed on
  https://github.com/itkach/slob/wiki/Other-projects). Used: pages (not redirects) whose title
  is 2–8 Han characters and whose opening sentence describes a term and names internet, forum or
  danmaku usage (`tools/moegirl_slob.py`), less a hand-checked exclusion list of characters,
  people, works, companies and plain words (`fallback_sources.MOEGIRL_EXCLUDE`); the opening
  sentence, and the next when the first is short, with 黑幕 (hidden text), struck-through text and
  characters KOReader's fonts may not draw taken out; a reading generated with pypinyin, shown
  as such. Titles CC-CEDICT has dropped.

Changes made: characters ranked by summed word frequency; default readings chosen by the
frequency of the words using each reading (neutral readings CC-CEDICT lists as entries of their
own, such as the particles 啦 *la* and 得 *de*, are candidates too, and the default where
`overrides.tsv` says so); numbered pinyin converted to tone marks; pypinyin
phrases merged in (first reading of each syllable; where both sources have a word and disagree,
CC-CEDICT is kept unless it differs only by a neutral tone on a rare character); 一 and 不 kept at
their dictionary tones (pypinyin writes the spoken tone changes); neutral tones on rare
characters replaced by the character's toned reading with the same letters (the tone the word's
other CC-CEDICT reading gives it first, then the character's default); for words with several
CC-CEDICT readings, proper names included, the one pypinyin's phrase list gives when it gives
one of them, else an ordinary reading before a proper name and, for words of common characters
only, the neutral-tone one, else the first, with hand-checked readings in `overrides.tsv` over
all of these; where the reading drawn above a rare character is another of the word's readings,
the one the popup marks kept separately (`word_marks`); each word's frequency added; CC-CEDICT
cross-references reformatted; everything stored in SQLite.

## Versions used

The release database was built on 2026-11-12 from:

| Source | Version |
|---|---|
| CC-CEDICT | release dated **2026-11-09T04:23:50Z**, 125,397 entries (`cedict_1_0_ts_utf-8_mdbg.txt.gz`, SHA-256 `2e8921a90b9abdca2ce78b8a6af104368f848681b7afe8020043f500fbe0238a`) |
| wordfreq | 3.1.1 |
| pypinyin | 0.55.0 |
| CPP dataset | train split, as fetched by `tools/learn_from_cpp.py` |
| Wiktionary | English Wiktionary dump of **2026-10-01**, kaikki.org extraction of 2026-10-30 (wiktextract 19f9a30), `kaikki.org-dictionary-Chinese.jsonl.gz`, SHA-256 `9663c01322014cea417fbe4812cc073ca2d6a6998946edb244bf4f26853819c9`; 60,950 fallback rows |
| Chinese Wikipedia | zhwiki dump of **2026-11-01** (`zhwiki-latest-*.sql.gz`, fetched 2026-11-11); 39,122 fallback rows |

`tools/build_db.py` prints the CC-CEDICT date, entry count and checksum, the Wiktionary dump
date, extraction date and checksum and the Wikipedia dump date, and records them with the
wordfreq and pypinyin versions in the database's `meta` table; update this table whenever
the release database is rebuilt. mdbg.net, kaikki.org and dumps.wikimedia.org/zhwiki/latest/
only serve the current files, so keep copies of them if an exact rebuild matters.

For reference, the user files built here (not distributed):

| File | Built | Source | Rows |
|---|---|---|---|
| MOE | 2026-11-11 | g0v/moedict-data commit 925fa83 (2026-07-11), `dict-revised.json.xz` SHA-256 `5cc4ec0efd7e549621edf9b46d261989230c1729d9dc2c8e2056f4b21c8a93da` | 90,501 |
| CBDB | 2026-11-12 | `cbdb_20261107.sqlite3` (generated 2026-11-07), SHA-256 `df3ee4961e7def9643ed78b967c753b560249e8e3c7aa660955bf598d9834e28` | 2,920 |
| Moegirlpedia | 2026-11-12 | `zhmoegirl-20230507-alpha.slob` (snapshot 2023-05-07), SHA-256 `75e246cf8e601e389ff72edfe0ced2ded5095347f103316b282883c707af36f8` | 352 |
