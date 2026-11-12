# Changelog

## Unreleased

- **Wikipedia titles** in the popup for words no dictionary has: about 39,000 Chinese Wikipedia
  article titles of 3–8 characters in technology, engineering, military and history, glossed with
  the English article's title (红夷大炮 *Hongyipao*, 火绳枪 *Matchlock*, 鱼鳞册 *Fish-Scale
  Registers*), with a pypinyin reading marked **· generated pinyin**. Part of the plugin; label
  **WP**. The release zip grows by about 2.7 MB.
- **Two more dictionaries you build yourself**, like MOE: **CBDB office titles** (about 2,900 Ming
  and Southern Ming office titles with English translations; `tools/build_cbdb.py`, label
  **CBDB**) and **Moegirlpedia slang** (about 350 internet-slang terms with their opening sentence
  in Chinese; `tools/build_moegirl.py`, label **Moegirl**). Their licences rule out the release.
- **Priority**: CC-CEDICT, then Wiktionary, CBDB, MOE, Wikipedia titles, Moegirlpedia; each word
  shows the first one's entry. The order is the `chinesehelper_fallback_order` setting. Each
  dictionary has its own switch under **Fallback dictionaries** and its own **Status** line. Only
  Wiktionary's words decide readings, as before.

## 1.4.0 (2026-11-11)

- **Wiktionary words can settle an uncertain reading.** When no CC-CEDICT or pypinyin word, rule
  or unusual-reading word decides a character whose reading is uncertain, a Wiktionary word
  around it picks one of its two likely readings: 累 in 累世公卿 is now *lěi*, with 累世 tagged
  *decides 累's reading*, where 1.3.1 showed *lěi/léi*. This applies to the pinyin drawn as well
  as the popup. CC-CEDICT and pypinyin words always come first, and a Wiktionary word never
  overrides a rule or a reliable default (letting it do so broke seven readings for each one it
  fixed on the CPP test split). MOE entries are still shown in the popup but do not decide
  readings: its Taiwan readings broke more than they fixed. Switching Wiktionary off under
  **Fallback dictionaries** turns this off. On the CPP test split at the default threshold the
  most-likely reading is right 96.7% of the time (96.6% before) and pairs are shown slightly less
  often; over 184 books, 86 of 1.77 million paragraphs draw different pinyin, nearly all a pair
  becoming the right single reading (刨坑 *páo*, 抡刀 *lūn*, 铮铮 *zhēng*).
- **Honest popup markers.** When nothing decided between a character's two likely readings
  (the uncertainty pair), both are marked **· one of these** instead of **· likely here**.
  *Likely here* now always means a single resolved reading; *shown above* is unchanged.
- **Marked readings in the resolver's order**: with a pair, the likelier reading comes first
  (*lěi* before *léi*), not CC-CEDICT's order.

## 1.3.1 (2026-11-11)

- **Edge pass-through width** offers 7.5 mm (89 px at 300 dpi) between 5 and 10 mm. The default
  stays 5 mm; a width saved by an earlier version is kept.

## 1.3.0 (2026-11-11)

- **Translate the sentence** from the popup: a full-width button below the word buttons sends the
  whole sentence containing the tapped character (found in the book's text, across pages, up to
  200 characters). With KOAssistant installed it reads **Translate & Analyze** and runs a
  built-in prompt (a snapshot of the author's custom action) through KOAssistant, with the
  sentence as a real selection; without it, **Translate** uses KOReader's built-in translator.
  Shown only while Wi-Fi is on and connected.

## 1.2.0 (2026-11-11)

- **Other dictionaries for words CC-CEDICT lacks**: English **Wiktionary** (about 61,000 words,
  bundled) and, optionally, the Taiwan Ministry of Education's **重編國語辭典** (a file you build
  yourself with `tools/build_moe.py`; its licence does not allow distributing it). CC-CEDICT
  always comes first; everyday combinations (很多, 这次) and numerals are left out. Entries from
  them carry their own readings and no reading markers; a small grey line above names their
  source (CEDICT, Wikt, MOE). Menu: Fallback dictionaries (source labels, each dictionary on or
  off). The database grows from 20 to 28 MB.

## 1.1.0 (2026-11-11)

- **Edge band**: a single tap within a set distance of any screen edge always goes to KOReader
  (page turn, menus, corner actions), even on a Chinese character or its pinyin. New menu item
  **Edge pass-through width**: 0 mm (off), 2.5 mm, 5 mm (default) or 10 mm, converted with the
  screen DPI KOReader reports and measured from the screen's edges in the current orientation.
  Status shows the band in mm and pixels.
- **Popup text size** now offers 40, 60, 80, 100 and 120% of the book's text size (default 60%),
  for reading with a large Chinese font. A size saved by 1.0.0 that is no longer a choice falls
  back to the default.

## 1.0.0 (2026-11-11)

First release: merges koreader-interlinear-pinyin (pinyin above rare characters) and
koreader-chinese-popup (tap a character for its CC-CEDICT entry and every word around it) into one
plugin, with one tap handler, one popup and one SQLite database. Settings are copied from the old
plugins on the first start.
