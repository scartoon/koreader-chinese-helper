# Changelog

## 2.0.0 (2026-11-13)

The major version marks how far the plugin has come since 1.0. Nothing breaks: settings, the
database and the optional dictionary files all carry over. Since 1.0.0:

- **One plugin** for pinyin above rare characters and tap-to-define (1.0.0, merging
  koreader-interlinear-pinyin and koreader-chinese-popup), with an edge band that keeps page
  turns reliable and a choice of popup text sizes (1.1.0).
- **More dictionaries, each labelled**: Wiktionary (bundled) and MOE 重編國語辭典 for words
  CC-CEDICT lacks (1.2.0), Wikipedia titles, CBDB office titles and Moegirlpedia slang (1.5.0),
  the 成語典 and Xinhua idioms (1.9.0); a small grey line names each entry's source.
- **Better readings**: Wiktionary words settle uncertain readings (1.4.0), word readings from
  pypinyin's phrase list, neutral particles and hand-checked words (1.6.0), mainland neutral
  tones (1.6.1).
- **Character components**: what a character is made of, which part gives the meaning and which
  the sound, and the parts a simplification hid (1.7.0).
- **Simplified characters** in all explanatory text (1.8.0).
- **Chengyu explained, with their source**: a line of Chinese explanation and a 出处 view with
  the classical passage, story and examples (1.9.0).
- **Translate & Analyze** the sentence with KOAssistant or KOReader's translator (1.3.0).
- **A new README** with gated screenshots from a public-domain sample book (1.9.1, 1.9.2).
- **This release**: the text around the tapped character at the top of every popup, and an
  underline under the character on the page.

Popup
- **The text around the character, on one line at the top.** Every popup opened from a tap on
  the book now starts with as much of the character's sentence as fits on one line, at the
  popup's text size, with the character in bold and underlined
  (时有宦官曹节等弄权，窦武、陈蕃谋诛之，作事不**密**，反为所害，中涓自此愈横。). It grows outwards from
  the character, the shorter side first, and a side that is cut ends in "…". It never goes past a
  sentence end (。！？, and . ! ? before a space, with any closing quotes or brackets after it), a
  paragraph break or the edge of the page: after 。” the line starts with the next sentence, not
  the ”. Line breaks and runs of spaces in the book's source, `<br/>` included, become nothing
  between Chinese characters and one space next to Latin text.
- **Replaces the old phrase header**, which showed the run of Chinese characters around the
  tapped one, and only when the popup covered it. With the new line off there is no line at all.
- **KOReader's dictionary popup gets the line too** when opened from the popup's word and
  character buttons (or when no dictionary has the character, so the tap goes straight to
  KOReader's lookup). A word button marks the whole word. The dictionary popup keeps its size and
  place: the definition gives up a line or two, which it scrolls. Other lookups are unchanged.
  This uses KOReader internals (checked on v2026.07.1); if they change, the popup opens without
  the line and the error is logged.
- Every popup is one line taller (84 px on a Boox Go 7 at 60%), so some that fit in half the
  screen are now centred.

Page
- **The tapped character is underlined on the page** while the popup is open, so you can see
  which character the tap hit. It is drawn by the plugin's own page layer (also with pinyin off),
  clears however the popup closes (tap outside, Close, Back, Translate, closing the dictionary
  popup a word button opened), and moves with the next tap. It sits clear of the pinyin on the
  line below. The e-ink refresh covers only the line; no ghost is left after it clears.

Menu
- **Show the text around the character in the popup** and **Underline the tapped character on
  the page**, both on by default, right after **Show character components**.

Speed: reading the page text for the line takes 1–4 ms per tap; page turns are unchanged.

Known limits
- In continuous (scroll) view the line can include text just below the screen.
- A dictionary lookup that never opens a popup leaves the underline until the next tap or page
  turn.

README
- New screenshots: every popup now shows the line. The main image taps 密 in
  作事不密 (the line shows text on both sides, and 密 is underlined on the page) instead of 涓.
  The screenshot script pins both new settings on, and two crops start exactly at the popup's
  frame.

Unchanged: the plugin database (byte-identical to 1.9.0, SHA-256 `20cc7ff8…`), the pinyin drawn,
every reading.

## 1.9.2 (2026-11-13)

README
- **Shorter and easier to scan** (about 8,970 → 6,650 words): short feature bullets under the
  gallery, and a table of every dictionary in the order the popup checks it, with the entries
  each adds, counted from the release database and the optional files.
- **One place for each thing**: how a reading is decided (a numbered list in Readings), the
  accuracy figures (Accuracy), the fallback dictionaries' behaviour (Fallback dictionaries) and
  how to build them (one table of commands, download and file sizes, licences).
- **Facts fixed**: database 36.4 MB (not 33); MOE adds 90,501 of its 161,194 entries; 成語典
  5,473 idioms; download sizes (MOE 15 MB, CBDB 140 MB); about 300 unusual-reading words (not
  200); the menu table lists all seven fallback dictionaries and **Show character components**;
  the file table lists every Lua module; word pinyin written joined, as the popup shows it.
- **Present tense only**: release history (since, as before, until) and comparisons with the old
  plugins are left to this changelog.
- `data/README.md` lists the 成語典 and Xinhua files built here.

Unchanged: the plugin database (byte-identical to 1.9.0), the code apart from the version number,
every reading.

## 1.9.1 (2026-11-13)

Popup
- **No Origin button.** The popup no longer offers Wiktionary's account of a character's
  origin; the components lines are what it shows about a character.
- **No buttons for a character's components.** Every button is now the tapped character, a word
  from the text containing it, 出处 or Close (plus Translate while Wi-Fi is on). The popup of a
  component on its own, which those buttons opened, is gone too. Popups with components are
  usually a button row shorter (茴: 2 rows → 1), so more of them fit in the half of the screen
  away from the tapped character.

成語典 file (rebuild it: `tools/build_idioms.py --push`)
- The ministry's separators are no longer shown: **＆** between senses (一五一十: 形容计数的仔细。
  ＆比喻… → 形容计数的仔细。比喻…) in 753 short lines, and **＆** and **＋** between source passages,
  notes and stories, now a paragraph break, in 519 出处 views. Nothing else in the file changed
  (unit tests in `tests/test_chengyu.py`).

README and sample book
- **New screenshots**, all from the new sample book: the opening of 《三国演义》 第一回 at the top
  (pinyin at the default 3,500, popup on 涓), then a gallery: pinyin off and on, a reading
  decided by its word (间或), components (茴), a part hidden by simplification (观 ← 觀), a
  chengyu with its 出处 (之乎者也), source labels (秋), and the Translate & Analyze button
  (窃书不能算偷). They replace the test-page screenshots.
- **`samples/xiaoshuo.epub`** (小说三篇): 《三国演义》 第一回 (毛宗岗 edition), 鲁迅's 《孔乙己》 and
  《阿Q正传》, built from Chinese Wikisource by `tools/make_sample_epub.py` (pinned revisions,
  simplified with `tools/simplify.py`, the 1938 text's old glyph variants normalised).
- **`tools/make_screenshots.py`** retakes every screenshot over adb. Each one is gated: the page's
  exact text is run through the plugin's own code (`tools/shot_gate.py`, every dictionary
  installed), the drawn pinyin must match a hand-checked list (21 readings over 5 pages) and each
  popup the expected lines, and KOReader's log must agree on the number of annotations and on
  each tap's context and reading.

Unchanged: the plugin database (byte-identical to 1.9.0; reading tables checksum the same), the
pinyin drawn, every reading.

## 1.9.0 (2026-11-13)

Popup
- **Chengyu explained, with their source.** Two new optional dictionaries you build yourself:
  the Taiwan Ministry of Education's **成語典** (`tools/build_idioms.py`, 5,473 idioms) and the
  **Xinhua idiom data** of chinese-xinhua (`tools/build_xinhua.py`, 30,212 idioms). With either
  installed, a chengyu gets one line of Chinese explanation under CC-CEDICT's English entry,
  labelled 成语典 or 新华 (一毛不拔: 形容人非常吝啬。贬义。), and a **出处** button opening a
  full-screen view: from the 成語典 the 典源 passage with its notes, the story (典故说明),
  citations, usage, examples, 辨识 and near and opposite idioms; from Xinhua the explanation,
  the classical source and an example. A related form (玉石俱碎) shows its main idiom's source
  and story under that idiom's name. The 成語典 comes first when both have an idiom.
- **Chengyu CC-CEDICT lacks** get an entry from these files (精兵强将, 科班出身, 十二万分): 3,704
  from the 成語典 and 23,485 from Xinhua, in the fallback order Wiktionary, CBDB, MOE, 成語典,
  Xinhua, Wikipedia titles, Moegirlpedia. Each has a switch under **Fallback dictionaries** and a
  **Status** line. Their readings stay inside their own entries and never decide the pinyin drawn.

Coverage (`tools/measure_chengyu.py`; a chengyu is any headword CC-CEDICT tags *idiom* or
either file lists, occurrences scanned longest first)
- **46 books on the test device** (202,036 occurrences, 9,959 idioms): an entry for 93.2% with
  the release alone, 97.3% with the MOE file, 100% with MOE, 成語典 and Xinhua (1,282 idioms,
  5,397 occurrences had no entry even with MOE: 精兵强将, 受制于人, 由来已久). 94.7% get the
  Chinese line and 92.4% a 出处 view (30.3% from the 成語典); of the occurrences CC-CEDICT has,
  92.6% now get a 出处 view.
- **临高启明** (38,398 occurrences, 5,498 idioms): 93.7% → 97.7% with MOE → 100%; 94.6% get the
  line, 92.3% a 出处 view (28.9% from the 成語典); 353 idioms (880 occurrences) newly covered.
- Of 40 random new entries read in context, 39 fall on word boundaries; the other is
  置之死地 inside 置之死地而后生.

Data
- The 成語典 file is read with the standard library (one .xlsx sheet); its markup (note
  numbers, ＃ ※ ◎ marks, cross-reference lists, "見「X」條" pointers) is taken out, and the
  text goes through `tools/simplify.py` (tw2s). 206 lines with characters the device fonts lack
  are dropped. 21.7 MB.
- Xinhua's scraped text is repaired where that is reliable (`tools/chengyu.py`, unit tests in
  `tests/test_chengyu.py`): the colon after a glossed word (首鼠鼠性多疑 → 首鼠：鼠性多疑; 8,037
  explanations), the colon and quotes after a source's title (21,965 derivations), missing
  opening quotes, ◇ and ★ markers, and symbols standing for lost text shown as …. Typos and
  titles followed by 诗 or 词 are left as they are. 14.9 MB.
- Both scripts take the plugin database from the latest release when there is none, so one
  command works right after cloning.
- The release database is unchanged, byte for byte (SHA-256 `20cc7ff8…`), so the reading
  tables are too.

## 1.8.0 (2026-11-13)

Popup
- **All explanatory text is in simplified characters.** MOE's definitions, which were
  traditional, are converted when you build its file (`tools/build_moe.py`; `--traditional`
  keeps MOE's own text, and **Status** says which a file has: a file built before 1.8.0 has
  traditional text, so rebuild it). Wiktionary's Chinese in English glosses is converted too
  ("synonym of 鵲洲 ／鹊洲" → "synonym of 鹊洲", "variant of 伊斯蘭曆" → "variant of 伊斯兰历",
  "(～屬)" → "(～属)"), and CC-CEDICT's last cross-references that still showed both forms
  ("95後|95后", "B型超聲|B型超声", "237號房間|237号房间") show the simplified one.
- **Characters that are the point stay as written**: one character quoted in 「」 (优恤:
  「恤」文献异作「卹」; 314 MOE definitions), a single character Wiktionary names as a form
  ("variant of 鉍", "same as 穩"; 46 rows), and Wiktionary pairs whose simplified side
  OpenCC does not produce (髼鬆／髼鬙; 83 rows).
- **著 "to write"** stays 著 (著有《昌言》, 所著, 撰著, 土著, 卓著, 见微知著, and a book's author:
  书名。清王国维著。), where OpenCC writes 着: 613 MOE definitions. 徵 the musical note stays 徵
  (宫、商、角、徵、羽; 5). 甚麼 becomes 甚么, as OpenCC gives it.
- **No boxes**: where OpenCC's simplified form of a rare character is outside the BMP, which
  the device fonts draw as a box, the traditional character stays (九针: 鍉针, not 𫔂针; 顗 not 𫖮;
  321 MOE definitions).
- Japanese kanji (followed by kana) are left as written; the Chinese around a Japanese word is
  converted (为日语さようなら的音译).

Data
- The converter is a shared module, `tools/simplify.py` (OpenCC `tw2s` for MOE, `t2s`
  otherwise; never `tw2sp`, which swaps vocabulary: 滑鼠 → 鼠标), with unit tests for each fix
  (`tests/test_simplify.py`, run by `tools/check.sh` and CI; the build now needs OpenCC).
  Phase 3's 成語典 will use it.
- MOE: 85,192 of 90,501 rows have their definitions converted; the headword and reading
  columns are identical to 1.7.0's file, and `--traditional` reproduces 1.7.0's file exactly.
- Release database: 2,475 Wiktionary rows and 8 CC-CEDICT senses changed text (the CC-CEDICT
  fix also repairs five that were garbled, such as "阿Q阿Q正传" → "阿Q正传"). Every other table, and
  every headword and reading column, is identical to 1.7.0; the reading tables' checksum is
  unchanged (`9ee87108…`). Database 36.4 MB, as before.
- CBDB (English glosses), Wikipedia titles (English article titles) and Moegirlpedia (already
  simplified; the 8 entries OpenCC would change are Japanese quotations) are not converted.

## 1.7.0 (2026-11-13)

Popup
- **Character components.** Every single-character popup now shows what the character is made
  of, one line per part below its own entry: the part as written, its reading, a short gloss and
  its role (髡: 髟 *biāo* hair → meaning; 兀 *wù* → sound, loose). Sound parts say how well they
  still match: **same sound** (茴 / 回 *huí*), **same ending** (郎 *láng* / 良 *liáng*) or **loose**.
  Of the characters outside the 2,500 most common whose analysis names a sound part (5,169),
  56% are same sound, 20% same ending, 23% loose. Radical forms are read as their full
  character, with their name (氵 *shuǐ* 三点水, 钅 *jīn* 金字旁); 阝 is 阜 on the left (左耳旁) and
  邑 on the right (右耳旁).
- **Each part is a button** opening its own popup (no reading marked: it is not in the text), and
  **Origin** shows Wiktionary's account of the character's origin in full.
- **Simplified characters whose simplification hid a part** show the traditional form's parts and
  what replaced them (观: traditional 觀, 雚 *guàn* → sound, same sound; simplified: 雚 → 又). Where
  the simplification only writes the same parts the simplified way (铳 from 銃, 陈 from 陳), the
  simplified forms are shown with the traditional form's roles. 发, 干 and the like take the
  traditional form of the word tapped (头发: 髮, 发现: 發).
- **Sources**: English Wiktionary's `Han compound` analyses first (bundled with the Wiktionary
  data already used), then [Make Me a Hanzi](https://github.com/skishore/makemeahanzi) (LGPL v3),
  then [yi-bai/ids](https://github.com/yi-bai/ids) (MIT, structure only), labelled Wikt, MMAH and
  IDS. Before building, the two were compared (`tools/measure_components.py`): in 40 random
  disagreements Wiktionary was wrong once (曙), Make Me a Hanzi in most (it often calls a
  phono-semantic character "ideographic"). Make Me a Hanzi's mnemonics are never shown, its
  roles are dropped where a simplification hid a part, and its "ideographic" parts get no role
  unless its note names the sound part (钺: 戉 *yuè*).
- **Nothing undisplayable**: an analysis or origin text with a character outside the BMP (which
  the device fonts draw as a box) is skipped for the next source's (秋: Wiktionary's 禾 + 𤒅
  gives way to 禾 + 火). 1,604 such analyses were skipped.
- Coverage of characters with a frequency rank, by band (Wikt / MMAH / IDS / none): 1–2,500 79 /
  12 / 5 / 4%; 2,501–3,500 66 / 23 / 6 / 5%; 3,501–5,000 50 / 36 / 9 / 5%; 5,001–7,000 30 / 40 /
  23 / 7%; beyond 7,000 17 / 18 / 56 / 8%.
- A menu switch, **Show character components** (on by default), and a Status line.

Data
- New `components` and `component_notes` tables: 13,362 characters, 6,591 origin texts. Database
  36.4 MB (was 33.5), zip 17.3 MB (was 16.4). The reading tables are unchanged (checksum `9ee87108…`, as in 1.6.1).
- The plugin folder now carries `LGPL-3.0.txt` (and `GPL-3.0.txt`, which it refers to) for the
  Make Me a Hanzi rows.

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
