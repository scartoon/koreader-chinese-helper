# Changelog

## 1.6.1 (2026-11-12)

Readings
- **Neutral tones follow the standard mainland spoken form.** Where CC-CEDICT gives a word's
  syllable only as a neutral tone, that is drawn above a rare character, in any position after
  the first: 刺猬 *cì wei*, 鼓捣 *gǔ dao*, 疙瘩 *gē da*, 衣裳 *yī shang*, 扫帚 *sào zhou*, 大猩猩 *dà xīng
  xing*, 唠唠叨叨 *láo lao dāo dāo*. Before, the character's own tone was drawn (*wèi*, *dǎo*), and
  pypinyin's full tone won where the two differed only by it. Words CC-CEDICT lists both ways
  (大爷 *dà yé* / *dà ye*, 裁缝 *cái féng* / *cái feng*) are drawn as before, and the popup still
  marks the neutral one. Hand-checked readings, erhua *r*, and 一 and 不 are unchanged.
- **495 words added** (simplified and traditional forms) that exist only for such a neutral tone,
  such as 鼓捣: 捣 has the one reading *dǎo*, so no word was looked up for it before. They are
  loaded with the other rare-character words, so page turns still make no query. Words whose
  drawn reading changes, simplified forms (of them added): 574 (239) at 1,500, 306 (140) at 2,500,
  133 (65) at 3,500, 40 (22) at 5,000, 13 (5) at 7,000.
- **Popup**: tapping a character drawn with a neutral tone marks its entry with the same letters
  (猬 *wèi* · shown above), even when it is the only reading, and tags the word that decided it
  (刺猬 · decides 猬's reading). Where several tones have those letters (糊 *hù*, *hú*, *hū*, drawn
  *hu* in 含糊), only the character's default reading is marked.
- **Accuracy**: CPP labels some of these words with the full tone (枇杷 *pá*, 姥姥 *lǎo*, 收拾 *shí*,
  铃铛 *dāng*, 唠叨 *dāo*, 播弄 *nòng*): 22 test sentences now count as wrong, 0.4 to 0.7 points of
  the "most likely" figures, 0.04 to 0.08 points of the ordinary-text estimate (99.67% at 3,500).
  `tools/eval_readings.py` counts a neutral label drawn as it is as right, and takes `--data` to
  compare two builds.
- Database 33.5 MB, as before.

## 1.6.0 (2026-11-12)

Readings
- **Words with several CC-CEDICT readings** take the one pypinyin's phrase list gives (便宜
  *piányi*, not *biànyí*; 明朝 *Míngcháo*, the dynasty), and 61 more were checked by hand (教授
  *jiàoshòu*, 妻子 *qīzi*, 说法 *shuōfa*, 开通 *kāitōng*, 下水 *xiàshuǐ*, 老公 *lǎogōng*). The
  popup now marks the right sense where a rare character's drawn tone matched another entry
  (大爷 *dàye* "uncle", not *dàyé*).
- **Particles take their neutral reading**: 吧 *ba*, 啦 *la*, 呗 *bei*, 喽 *lou*, 咯 *lo*, 们 *men*;
  得 shows *de/děi* where no word decides (得到 is still *dé*). Some words now mark 得 in bold as
  an unusual reading (总得 *zǒngděi*, 得陇望蜀 *dé*).
- **Learned rules can be excluded by hand** (`data/rules_exclude.tsv`); six bad ones removed
  (累官 is now *lěi guān*, 为攒 and 粘着 no longer forced to *cuán*, *nián*). 圩 is *xū* in 圩市,
  圩日, 赶圩, 圩集.
- **Accuracy scoring** no longer counts a particle's neutral label as the toned reading (啦 *la* is
  not *lā*); figures in the README's Accuracy section. On the CPP test split no accuracy figure
  drops; the popup's markers on common characters go from 97.4% to 97.5% right.

Display
- **Continuous (scroll) view**: pinyin for everything on screen. Before, only the page at the top
  of the screen was read, from that page's start, so the lower part of the screen, and often all
  of it, had none.
- **Headings**: pinyin above rare characters in h1–h6 no longer overlaps them.
- **〇** (二〇二六年) no longer gets *líng* drawn on every page with a date, and tapping it opens
  its popup.

Other
- A tap queries Wiktionary and the Wikipedia titles in one statement; the database's prepared
  statements no longer pile up with every distinct number of words; the threshold setting is
  validated.
- GitHub Actions runs `tools/check.sh` against the latest release's database.
- README: what is drawn on a page (first occurrence only, crowded lines), only 2–4 character
  words decide readings, how the accuracy estimate is made, the KOAssistant version tested.
- Database 33.5 MB (about 4,500 more words, for the particles' neutral readings); zip 16.4 MB.

## 1.5.0 (2026-11-12)

- **Wikipedia titles** in the popup for words no dictionary has: about 39,000 Chinese Wikipedia
  article titles of 3–8 characters in technology, engineering, military and history, glossed with
  the English article's title (红夷大炮 *Hongyipao*, 火绳枪 *Matchlock*, 鱼鳞册 *Fish-Scale
  Registers*), with a pypinyin reading marked **· generated pinyin**. Bundled; label **WP**. The
  database grows from 28 to 33 MB and the release zip from 13.6 to 16.4 MB.
- **Two more dictionaries you build yourself**, like MOE: **CBDB office titles** (about 2,900 Ming
  and Southern Ming office titles with English translations; `tools/build_cbdb.py`, label
  **CBDB**) and **Moegirlpedia slang** (about 350 internet-slang terms with their opening sentence
  or two in Chinese; `tools/build_moegirl.py`, label **Moegirl**). Their licences (non-commercial)
  rule out distributing them: they are never in the repository or the release.
- **Priority**: CC-CEDICT, then Wiktionary, CBDB, MOE, Wikipedia titles, Moegirlpedia; each word
  shows the first one's entry. The order is the `chinesehelper_fallback_order` setting (not in the
  menu). **Fallback dictionaries** has a switch for each dictionary, greyed out with "(not
  installed)" for a missing file, and **Status** has a line for each (version, entries, on or
  off, or not installed). Only Wiktionary's words decide readings, as before: the reading tables
  are unchanged (same checksum), so the pinyin drawn is the same as in 1.4.0.
- **README rewritten**: a new opening on what the plugin does for Chinese readers, what the
  dictionaries cover on 临高启明, a feature list, and an **Accuracy** section with this release's
  figures (previously a link to koreader-interlinear-pinyin's).

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
