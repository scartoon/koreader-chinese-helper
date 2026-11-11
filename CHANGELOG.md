# Changelog

## Unreleased

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
