# Roadmap: components, simplified text, chengyu, README screenshots

Written 2026-11-13 from a planning discussion, against v1.6.1 (database from the
v1.6.1 release). Four phases, one release each, run as separate Claude Code
sessions. Phase 5 (a README pass) was added after phase 4.

| Phase | What | Release | Status |
|---|---|---|---|
| 1 | Character component breakdowns in the popup | 1.7.0 | released 2026-11-13 |
| 2 | All explanatory text in simplified characters | 1.8.0 | released 2026-11-13 |
| 3 | Richer chengyu entries (two build-it-yourself dictionaries) | 1.9.0 | released 2026-11-13 |
| 4 | New README screenshots and sample book | 1.9.1 | released 2026-11-13 |
| 5 | README readability pass | 1.9.2 | released 2026-11-13 |

## How to use this file

- Read **Shared rules** and your phase's section. Do only your phase.
- Numbers in this file were measured during planning. Re-measure anything you
  rely on; if a number turns out wrong, say so in Findings.
- Where a phase says **stop and report**, stop and explain instead of working
  around it.
- Before releasing, update this file: set your phase's status, and write under
  **Findings** anything a later phase needs (measurements, surprises, changed
  decisions). Commit it with the release.

## Shared rules

1. **Prose vs character forms.** Explanatory prose is shown in simplified
   characters (phase 2). Characters shown *as characters* are never converted:
   component parts (phase 1), a single character quoted in 「」, and traditional
   forms the popup deliberately shows (觀 in 观's breakdown). There, the form
   is the whole point.
2. **Licences.** Bundle only redistributable data (CC BY-SA, LGPL, MIT, Unicode
   licence). Data that can't be redistributed (CC BY-ND, scraped text) follows
   the existing MOE/CBDB/Moegirlpedia pattern: a `tools/build_*.py` script, the
   output never committed or released, a switch under **Fallback
   dictionaries**, a **Status** line, and a README entry with the source link
   and one copy-paste command that works for a user who has just cloned the
   repo. A user must be able to add each optional source trivially.
3. **Everything happens at build time.** No Python or OpenCC on the device.
   The plugin is Lua reading SQLite.
4. **Screen budget.** Boox Go 7, 7-inch e-ink. The popup must stay readable at
   the default popup text size (60%). New content goes behind a button or a
   "more" view rather than making every popup long.
5. **Honest markers.** Never show a stronger claim than the data supports (the
   1.4.0 principle). Label sources the way the popup already does (small grey
   label).
6. **Readings are untouched** unless a phase says otherwise. MOE and the new
   chengyu sources never decide readings. Show that the reading tables are
   unchanged (same checksum, as in 1.5.0).
7. **Release process.** Version in `_meta.lua` and `main.lua`, CHANGELOG entry
   with measurements in the style of earlier entries, README updated,
   `tools/check.sh` and CI passing, tested on the Boox over adb
   (`tools/deploy.sh`), GitHub release with the database zip.

## Phase 1: Character component breakdowns (1.7.0)

### What the user sees

In every single-character popup (all characters, not just those above the
pinyin threshold), below the character's own entry, one line per part:

```
髡 kūn   scalping; to make the head bald
   髟 biāo  hair; shaggy                  → meaning
   兀 wù    (literary) towering; bald      → sound (loose)
```

- Each part shows its form, modern reading, a short gloss, and its role.
- Sound parts are labelled by how well they match the character's reading:
  **same sound** (same syllable, ignoring tone), **same ending** (same final),
  or **loose**. In planning, of 4,268 rare (rank > 2,500) phono-semantic
  characters in Make Me a Hanzi, 58% were same sound and 16% same ending.
- Each part is a button that opens that part's own popup (like the word
  buttons), so the user learns the parts too.
- A **more** button shows Wiktionary's full glyph-origin text when there is one.
- Each part line, or the block, has a small source label (Wikt, or a short
  label for Make Me a Hanzi).
- **Simplified characters whose traditional form differs** show the
  traditional form's breakdown, plus a line naming the replaced part:

```
观 guān  to look at; to watch
   (traditional 觀)  見 jiàn  to see                → meaning
                     雚 guàn  (archaic) stork/heron → sound (same ending)
   simplified: 雚 → 又
```

  If the character has one traditional form, use it. If it has several
  (发 → 發/髮, 干 → 乾/幹), use the traditional form of the word the user
  tapped in when CC-CEDICT gives one; otherwise show the simplified
  character's own breakdown.

### Sources, in priority order

1. **English Wiktionary**, from the kaikki file the build already downloads
   (`build/sources/wiktionary/kaikki-Chinese.jsonl.gz`; currently only the
   senses are read, in `tools/fallback_sources.py`). Character entries carry:
   - an `etymology_templates` entry named `Han compound`, with args `1`, `2`, …
     (the parts), `c1`, `c2`, … (role: `p` phonetic, `s` semantic), `t1`, `t2`, …
     (gloss of the sense the part contributes), `tr`/`tr1`/… (Old Chinese
     readings: do not display), `abb2` etc. (abbreviated part), `ls` (type,
     `psc` = phono-semantic compound);
   - a `liushu` template giving the type;
   - the prose in `etymology_text` (for the **more** view).
   Seen in planning: entries with two analyses (e.g. "Zhang (2022): …" before
   Shuowen's), two phonetic parts (`c1: p, c2: p`), and abbreviated phonetics
   (秋: 禾 + abbreviated 𤒅). Show the first analysis; if the entry records a
   competing analysis, mark the line as disputed and leave the rest to
   **more**. Unknown: whether simplified-character entries carry their own
   template or only point to the traditional form. Find out.
   Licence CC BY-SA 4.0, already bundled.
2. **Make Me a Hanzi** `dictionary.txt` (github.com/skishore/makemeahanzi,
   **LGPL v3** for dictionary.txt only; graphics.txt is Arphic and not
   needed). About 9,500 characters, with `decomposition` (IDS) and
   `etymology` (`type`: ideographic, pictographic, pictophonetic; for
   pictophonetic, `semantic` and `phonetic`). **Drop the `hint` text
   entirely**: it is a learner mnemonic and is wrong for simplified
   characters (观 "to see 见 again 又", 对 "a pair 又 of hands", 鸡 "another
   又 kind of bird"). Known role error: 钺 is labelled ideographic, but 戉
   *yuè* is clearly the phonetic.
3. **yi-bai/ids** `ids_lv2.txt` (github.com/yi-bai/ids, **MIT**): structure
   only (no roles) for characters neither source covers. Do not use
   CHISE or CJKVI-IDS (GPLv2).

Readings and glosses for the parts come from CC-CEDICT, looked up by the
simplified **and** traditional columns (many parts are traditional forms: 鳥,
魚, 馬, 貝). Prefer Wiktionary's `t` gloss when present (it is the relevant
sense: 心 "heart", not every sense of 心). Add a hand-written table of radical
forms, about 30 (氵→水, 扌→手, 亻→人, 忄→心, 讠→言, 钅/釒→金, 纟/糹→糸,
饣/飠→食, 礻→示, 衤→衣, 艹→艸, ⺮→竹, 辶→辵, 犭→犬, 灬→火, ⺼→肉, …),
showing the radical's common name where it helps (三点水). 阝 depends on
position: left = 阜, right = 邑.

### Baseline measured in planning (Make Me a Hanzi + ids, v1.6.1 ranks)

| Rank | MMAH has it | Phono-semantic (of those) | Parts resolvable to reading + gloss* |
|---|---|---|---|
| 2,501–3,500 | 93% | 78% | 97% |
| 3,501–5,000 | 88% | 82% | 96% |
| 5,001–7,000 | 67% | 82% | 95% |
| 7,001+ | 27% | 79% | 93% |

\* after the traditional-column lookup and the radical table. With yi-bai/ids,
every character in the `chars` table has a structure.

### Steps

1. **Measure first**, before building anything, and write the results under
   Findings: for each rank band above, how many characters have a Wiktionary
   `Han compound` template, how many only Make Me a Hanzi has, how many
   neither; and where both have one, how often they disagree on parts or
   roles. Read 30 disagreements. **Stop and report** if Wiktionary is wrong
   in more than a few of them, since that would change the priority order.
2. Build a components table into the release database (parts, roles, glosses,
   source, match label precomputed; the more-text separately). It should add
   at most a few MB to the 33.5 MB database. Report the size.
3. Popup: part lines, part buttons, the more view, the traditional-form rule.
4. Tests (offline harness), then on device: check a spread of characters
   including 髡, 清, 观, 鸡, 茴, 廪, 秋, a radical-form case (铳), a 阝 left and
   right, and one with no data.
5. README section with a short explanation, CHANGELOG, release.

## Phase 2: All explanatory text in simplified characters (1.8.0)

### Scope

- **MOE 重編國語辭典** definitions (`tools/build_moe.py`, source
  g0v/moedict-data). Headwords are already indexed under OpenCC `tw2s`; now
  convert the definition text too.
- **Wiktionary** bundled rows: 2,591 have traditional text, mostly character
  pairs like "original form of 廩／廪". Collapse a pair to its simplified side
  when `t2s(first) == second`; converting would give "廪／廪". Convert other
  traditional prose.
- **CC-CEDICT**: 71 definitions have pairs in its own format
  ("95後|95后"). Check how the popup currently displays these; show the
  simplified side.
- **Moegirlpedia** (`tools/build_moegirl.py`): check whether its text
  contains traditional characters, and convert if so.
- **CBDB**: glosses are English. Confirm nothing to do.
- **Wikipedia titles**: clean (5 rows with Han characters in glosses). Confirm.
- Phase 3's 成語典 will use the same converter, so build it as a shared
  module (e.g. `tools/simplify.py`).

### The converter

Use OpenCC **`tw2s`** for Taiwan-standard sources (MOE, 成語典) and `t2s`
otherwise. **Not `tw2sp`**: it swaps vocabulary (滑鼠 → 鼠标), which is wrong
inside classical quotations. Measured in planning: `tw2s` on the 77,050
CC-CEDICT headwords whose simplified form differs matched 98.8% of words and
99.6% of characters; most remaining differences are variant choices (砲 for
炮, 姪 for 侄), not wrong characters.

Fixes on top of OpenCC, each with unit tests:

1. **著 meaning "to write"** comes out as 着. Counts over the whole MOE
   dictionary: 著有 → 着有 684 times, 所著 120, 著 before 《 85; also 土著 →
   土着, 撰著 → 撰着. Add a phrase list (著有, 所著, 撰著, 編著, 合著, 原著,
   遺著, 論著, 譯著, 專著, 土著, 著書, 著 before 《, …) and check a sample of
   remaining 著 → 着 conversions by eye. Rarer: 徵羽 → 征羽 (should stay 徵).
2. **Single characters in 「」 stay as written** (shared rule 1): 305 of the
   109,499 MOE definitions the plugin shows quote one character that
   conversion would change (澤，通「襗」 → 通「𫋷」). Longer 「…」 quotations
   are citations and are converted.
3. **Keep the traditional character when the simplified one is outside the
   BMP**: 326 definitions would get an extension-block character the device
   font probably lacks (顗→𫖮, 餔→𫗦, 鑪→𬬻).
4. Leave 甚麼 → 甚么 as is.

`build_moe.py` gets an option to keep the original text (simplified is the
default). Reading tables must be unchanged.

### Steps

Build the converter with tests, apply it to each source above, rebuild, compare
a sample of before/after definitions, check on device, update README (MOE
section: text is now simplified, and the option), CHANGELOG, release.

## Phase 3: Richer chengyu entries (1.9.0)

### Current state

CC-CEDICT tags 5,684 entries "(idiom)". Its English glosses are often good
(literal + figurative) but never give the source text or gloss individual
characters (首鼠 = the rat's dithering).

### Sources (both build-it-yourself)

1. **教育部《成語典》** (Taiwan Ministry of Education). CC BY-ND 3.0 TW, same
   as the MOE dictionary, downloadable from 教育部國語辭典公眾授權網 (find the
   current download; if it can't be fetched by script, the README explains
   the manual step precisely). About 5,000 fully edited entries in 1,500+
   groups, plus 23,385 brief entries from 重編國語辭典修訂本 and appendices
   (28,000+ in all). Full entries have 釋義, 典故原文, 注解, 典故說明 (the story
   retold in modern Chinese), 書證, 用法說明 with modern examples, 辨識.
   Traditional, Taiwan readings: run through phase 2's converter (`tw2s` +
   fixes); never decides readings.
2. **Xinhua idiom data**: `data/idiom.json` from github.com/pwxcoo/chinese-xinhua
   (31,648 listed; 30,895 unique words). Fields `word`, `pinyin`,
   `explanation`, `derivation` (classical source quoted, e.g. 刻舟求剑 →
   《吕氏春秋·察今》 with the whole story), `example`. Simplified, mainland
   readings. The repo's MIT licence covers its code; the text is scraped from
   a published dictionary, so build-it-yourself only. Clean the punctuation
   lost in scraping where it can be done reliably: missing colon after a
   glossed word (首鼠鼠性多疑 = 首鼠：鼠性多疑), missing opening quotes,
   ◇ and ★ markers, occasional typos (右动摇). Don't attempt what can't be
   done reliably.

Coverage measured in planning: 4,503 Xinhua idioms overlap CC-CEDICT's tagged
ones; 23,080 four-character Xinhua idioms are not in CC-CEDICT at all, and
only 1,464 of those are in the Wiktionary fallback.

### Display

- CC-CEDICT's English entry stays first.
- The chengyu's row gets one short line of Chinese explanation (成語典 釋義,
  else Xinhua `explanation`).
- A **出处** button opens a full-screen view: source text, the story
  (典故說明), usage, example. Priority 成語典, then Xinhua. Source labels as
  elsewhere.
- Chengyu that CC-CEDICT lacks appear as fallback entries from these sources,
  in the fallback order (setting `chinesehelper_fallback_order`), with
  switches and Status lines.

### Steps

1. Build scripts for both, sharing phase 2's converter for 成語典.
2. Measure with `tools/measure_book.py` / `measure_fallback.py` on the
   184-book corpus and on 临高启明: chengyu taps covered before and after,
   and how many get a 出处. Report in the CHANGELOG and Findings.
3. Popup line, 出处 view, tests, device check.
4. README: one entry per source, each with link + one command, then
   CHANGELOG, release.

## Phase 4: README screenshots and sample book (1.9.1)

### Sample book

Extend `tools/make_sample_epub.py` (which builds `samples/guwen.epub`) or add
a script, building from **Chinese Wikisource** texts, not modern editions
(their editing may be copyrighted):

- 《三国演义》 第一回, the 毛宗岗 edition (opens with 杨慎's 临江仙
  "滚滚长江东逝水"; older editions lack it).
- 鲁迅《孔乙己》 (1919) and 《阿Q正传》 (1921), from 《呐喊》. Lu Xun died
  1936: public domain in China and, for works published before 1930, the US.

Convert to simplified with phase 2's converter if the source is traditional.
Keep the style sheet's "no line-height" choice, as now.

### Shot list

1. **Main image, top of the README: the opening of 三国演义 第一回**, at the
   default threshold **3,500**, popup open on 涓 (中涓 comes from Wiktionary,
   so the source labels show). Expected pinyin, checked in planning against
   v1.6.1 default readings on typed text: 樵 *qiáo*, 渚 *zhǔ* (poem), 锢 *gù*,
   宦 *huàn*, 涓 *juān* (话说天下大势 paragraph), 蟠 *pán*, 臾 *yú*, 雹 *báo*
   (建宁二年 paragraph); title none. **Do not shoot at 2,500**: 蕃 in 陈蕃
   is uncertain (*bō*/*fān*), no dictionary has 陈蕃, and the right reading
   is *Chén Fān*.
2. **Reading decided by context**: a multi-reading character decided by a
   word, found in the sample text (replaces the 单于 test-page shot).
3. **Components**: 茴 from 孔乙己's 茴香豆 scene (艹 meaning + 回 *huí*, same
   sound), plus a three-frame strip: tap 茴 → popup → tap 回 → 回's popup.
   Stills, not a GIF (e-ink refresh looks jumpy).
4. **Traditional-form breakdown**: a character on a sample page whose
   simplified form hides its phonetic (like 观/觀).
5. **Chengyu**: 之乎者也 (孔乙己) with its 出处 view, if the sources have it;
   otherwise another chengyu from the sample text. Caption that it needs the
   optional dictionaries.
6. **Dictionary labels**: a popup with entries from several sources.
7. **Translate & Analyze**: 孔乙己's 窃书不能算偷 line.
8. **Pinyin off/on**: retake on the sample book.

Fallback text for anything the Lu Xun stories can't show: 阿Q正传, or a
natural sentence written for the purpose.

**Gate for every shot**: run the exact page text through the plugin's own
code (`tools/plugin_runtime.py` or the test harness) at the shot's threshold
and check every drawn reading and every popup marker. A wrong reading in a
README screenshot is worse than no screenshot: pick another tap or page, or
fix the plugin first.

### Capture

A script (e.g. `tools/make_screenshots.sh`) driving the Boox over adb:
set font, font size, margins and status bar so taps land in the same place;
open the sample book at a page; `adb shell input tap X Y`;
`adb exec-out screencap -p`; crop to the region that matters; save as a
16-grey PNG (like the current 4-bit ones). Same width for every image.
Re-running it after a release should regenerate all screenshots.

### README

- Main image at the top, then a short **Features** gallery linking down to the
  detailed sections.
- Replace `docs/popup.png` and `docs/popup-tall.png` (taken on a test page
  with an English "quick brown fox" paragraph).
- Keep the current style of detailed alt text.
- Check the optional-dictionary sections still read as one-command steps.

## Phase 5: README readability pass (1.9.2)

README only (plus `data/README.md` where numbers must agree); no code changes. Make the README
shorter, consistent and easy to scan, describing the plugin as it is now, without losing
anything a user needs (target about 5,500 words, completeness first; alt texts unchanged):

- Top: main image, gallery and captions kept; feature bullets cut to one or two lines with
  links, bullets the captions cover dropped; a dictionary table after them (label, entries
  added, bundled or optional), CC-CEDICT first, in the popup's order, every count from the data.
- Fix wrong or inconsistent facts (sizes, counts, menu table, file table, joined pinyin, the
  popup's buttons, leftover Origin history), checking every number.
- Move misplaced material (popup placement, database building, coverage on one book, the merge
  note); say each thing once (dictionaries, the reading decision order, accuracy figures);
  remove release history, after checking the CHANGELOG has it.
- Outline: intro, Install, Usage, Readings, Accuracy, Fallback dictionaries, Data, Speed,
  Development, Credits. Every internal link resolves.

## Findings

Each phase adds what later phases need to know.

### Phase 1

**Measurement (step 1), 2026-11-13**, `tools/measure_components.py` against
the v1.6.1 database's `chars` table (the 12,295 characters with a rank), the kaikki dump of
2026-10-30 (Wiktionary 2026-10-01) and Make Me a Hanzi `dictionary.txt`
(master, 9,574 entries):

| Rank | Chars | Wikt `Han compound` | Wikt via the traditional form only | MMAH has the character | MMAH only | Neither | Both | Disagree on parts | Disagree on roles |
|---|---|---|---|---|---|---|---|---|---|
| 1–2,500 | 3,780 | 2,220 (59%) | 810 (21%) | 3,545 (94%) | 443 (12%) | 307 (8%) | 2,000 | 325 (16%) | 316 (16%) |
| 2,501–3,500 | 1,427 | 757 (53%) | 258 (18%) | 1,334 (93%) | 319 (22%) | 93 (7%) | 718 | 87 (12%) | 90 (13%) |
| 3,501–5,000 | 2,091 | 841 (40%) | 351 (17%) | 1,833 (88%) | 732 (35%) | 167 (8%) | 742 | 82 (11%) | 92 (12%) |
| 5,001–7,000 | 2,595 | 625 (24%) | 336 (13%) | 1,745 (67%) | 1,018 (39%) | 616 (24%) | 424 | 43 (10%) | 61 (14%) |
| 7,001+ | 2,402 | 382 (16%) | 256 (11%) | 660 (27%) | 433 (18%) | 1,331 (55%) | 121 | 18 (15%) | 17 (14%) |

(Parts disagreements as the final `tools/measure_components.py` prints them; a
few fewer than in the first run, after empty template arguments were
ignored.) "MMAH only" and "Neither" count a character as covered by Wiktionary when
its traditional form has a `Han compound`. The planning column "MMAH has it"
is reproduced exactly (93/88/67/27%). "Neither" is left to yi-bai/ids
(structure only).

- **Stop condition not met.** I read 40 random disagreements (more than the
  30 asked). Wiktionary was plainly wrong in one: 曙, phonetic 暑 where the
  character is written with 署. In two more it analyses an older form than
  the one written: 期 (semantic 日, from the variant 㫷) and 峭 ("originally"
  阜, later 山). 實, 去, 保 and 失 analyse the oracle-bone forms: correct, but
  the parts don't match the modern shape, so the **more** text matters
  there. Make Me a Hanzi was wrong far more often. 19 of the 40 were MMAH
  calling a phono-semantic character "ideographic" (晚, 遺, 譯, 衷, 倔, 髀...),
  and 準, 贖, 邃 and 旖 had the wrong parts. The priority order stands.
- **Simplified characters (the open question):** they carry no `Han compound`
  of their own (丛 is a rare exception). Each one has either a `Han simp`
  template (1,119 characters: `1` = the traditional form, `f`/`t`, `f2`/`t2`
  = the parts replaced, as in 观: 雚 → 又, 見 → 见) or a soft redirect to the
  traditional entry (铳 → 銃, 钺 → 鉞, 廪 → 廩). So the traditional-form
  rule is what gives most simplified characters a Wiktionary analysis.
- **MMAH role errors can be partly repaired.** 749 "ideographic" entries
  have a hint saying "X also provides the pronunciation" (钺, 郎, 晚, 倔...).
  Where Wiktionary also has the character (392), it names the same phonetic
  in 320. The build uses that phrase to set the phonetic role. The hint text
  itself is never shown.
- Wiktionary marks 169 characters with a second `Han compound` (disputed),
  often common ones (造, 何, 秋). "Abbreviated" parts (`abb`) occur in 140.
  The `alt` argument gives the written form of a part (水 written 氵, 辵
  written 辶).
- The roadmap's 观 example labels 雚 "same ending", but its sense "stork" is
  read guàn, which is the same syllable as 觀 guān. The planning numbers seem
  to have used 雚's default reading huán (from `chars`). For a sound part the
  build uses the part's reading that best matches the character, and the
  gloss of that reading.

**What was built (1.7.0)**, and what differs from the plan:

- Tables `components(ch, body)` (one text row per character: an `H` line and
  one `P` line per part, format documented in `tools/components.py`
  Builder) and `component_notes(ch, text)` (Wiktionary's origin text).
  13,362 characters, 6,591 notes, **+2.9 MB** (33.5 → 36.4 MB). The reading
  tables' checksum is unchanged. Popup code: `ch_components.lua`;
  `ch_tap.lua` now has `present()` (shared by the text popup and a part's
  popup) and `showCharPopup()`.
- **Undisplayable characters (user's decision during the session):** nothing
  containing a character outside the BMP is shown. The device fonts draw a
  box with a question mark for most of them (seen on 秋's 𤒅). The build
  skips such an analysis and uses the next source's; origin texts with one
  are dropped (Origin button absent). 1,604 analyses were skipped, and 715
  ranked characters have no row at all (37 before the rule). **Phase 2:**
  this matches its "keep the traditional character when the simplified one
  is outside the BMP" fix. Phase 4's screenshot gate should treat a box as a
  failure too.
- **No "disputed" line (user's decision):** a line like "other analyses
  exist: see Origin" was removed. The first analysis is shown with no
  marker, and the others are in the Origin text. The `d` flag is still in
  the data, unused. Avoid pointer language of that kind in later phases.
- The **more** button is labelled **Origin**. It opens a TextViewer with
  Wiktionary's text (and, for a simplified character, the traditional
  form's too).
- yi-bai/ids rows are built only for the ranked characters and for parts,
  not for the 29,000 unranked ones (that would have added about 2.5 MB).
- The match label "same ending" compares the final **without the medial**
  (良 *liáng* / 郎 *láng*, 奚 *xī* / 鸡 *jī*). Rank > 2,500 characters with a
  sound part: 56% same sound, 20% same ending, 23% loose.
- Make Me a Hanzi's "ideographic" parts get no role (it is too often wrong),
  unless its hint names the sound part. Wiktionary's ideogrammic compounds
  mark every part → meaning.
- A simplified character whose simplification only writes the same parts the
  simplified way (铳 ← 銃: 金 → 钅; 陈 ← 陳: 東 → 东) shows the simplified
  forms, with the traditional analysis's roles and no "traditional" line.
  Only a simplification that hides a part (观, 鸡, 这 ← 這: 言 → 文) shows
  the traditional form.
- **Phase 4 (茴 shot):** 茴 shows `艹 cǎo grass; plant (草字头) → meaning` /
  `回 huí to go back; to return → sound (same sound)`, label Wikt, buttons
  艹, 回, Origin. 回's own popup shows "pictogram (象形)", plus a "traditional
  迴" breakdown when it is tapped in a word CC-CEDICT writes with 迴.
  Traditional-form candidates on a sample page: 观/觀, 鸡/雞, 这/這, 让/讓,
  赵/趙.
- Device test book: `build/chinesehelper-components.epub` (pushed to
  `/sdcard/Download/`), made with `make_test_epub.py`'s builders: 髡发之刑。清水。
  观察。/ 鸡蛋。茴香豆。仓廪实。/ 秋天。火铳。陈列。新郎。/ 阿姨。首都。卍字。/ 头发很长。他发现了。
  卍 has no data. I did not redo the tap-timing A/B: a popup now makes one to
  three extra primary-key lookups.

### Phase 2

**The converter** is `tools/simplify.py`: `Simplifier("tw2s")` (MOE, and
phase 3's 成語典) or `Simplifier("t2s")`; `convert(text)` for prose,
`wiktionary(sense)` for Wiktionary glosses (pairs collapsed, single
characters named as forms kept). Unit tests: `tests/test_simplify.py`, run by
`tools/check.sh` and CI (both now install OpenCC). OpenCC 1.4.2's t2s/tw2s
never changed a string's length on MOE, so fixes work by position; the
module falls back to converting between kept characters if one ever does.

Measurements (2026-11-13; MOE file 90,501 rows = 102,264 senses, 1.7.0
database), and where they differ from the plan:

- **MOE**: OpenCC changes 94,182 senses. Fixes on top: 著 kept in 613 senses,
  「X」 kept in 314 (plan: 305), outside-BMP kept in 321 (plan: 326), 徵
  kept in 5. The plan's 著 list was not enough: 著有 after a verb is the
  aspect particle (趁著有利, 拉著有兩個輪子的), so 著有 needs a clause start,
  並/又/所/曾… before it, or a title after it; and book descriptions name
  the author with a bare 著 (書名。清王國維著。; 53 senses), handled by
  `AUTHOR_ZHE`. 見微知著 also needed adding. I read 60 random remaining
  著 → 着 by eye, plus the 70 most frequent clause-final ones: nearly all are the aspect particle or 着 senses (着色,
  着重, 附着, 沉着); the misses seen were rare (裴頠遂著崇有論). OpenCC itself
  keeps 魏徵 and 徵調.
- **Japanese** in MOE (8 senses: バール, さようなら) and Wiktionary: a
  first rule (leave any text with kana alone) left whole MOE definitions
  traditional, and the katakana middle dot ・ that MOE uses in 唐・劉禹錫
  is in the kana block. The rule now keeps only Han characters followed by
  hiragana after kana, a quote or a colon.
- **Wiktionary**: 2,597 rows (plan: 2,591) had text OpenCC changes. 1,328
  had a pair collapsed; pairs come as `A／B`, `A ／B`, chains `A ／B ／C`
  (煙袋鍋 ／菸袋鍋 ／烟袋锅) and sayings with a comma (宁为鸡口，無為牛後
  ／…). 83 rows keep a pair OpenCC disagrees with (髼鬆／髼鬙). Single
  characters after "variant of", "same as", "form of", "interchangeable with"
  are kept (46 rows: 苍铅 "variant of 鉍"). 192 rows still contain
  characters OpenCC would change, all for these reasons or the BMP rule.
- **CC-CEDICT**: the plan's 71 could not be reproduced. The build already
  collapsed `trad|simp[pinyin]` and bare `trad|simp`; only 3 senses still
  showed a pair, all forms with digits or Latin letters (95後|95后,
  B型超聲|B型超声, 237號房間|237号房间), which the regex excluded. The fixed
  regex also repairs 5 senses the old one garbled (阿Q阿Q正传,
  殲擊8歼击8型). 95后 and B超 themselves can never be tapped (the popup's
  context stops at non-Han characters). Not fixed, outside this phase:
  CC-CEDICT pinyin with capitals is mangled (九价HPV疫苗 "jiǔjià Hpüyìmiáo").
- **Moegirlpedia**: already simplified; the 8 rows OpenCC would change are
  Japanese quotations (時の涙, 裏山死刑, 特別な気分). Not converted.
- **CBDB**: English glosses, 0 rows changed. **Wikipedia titles**: 0 rows
  changed. Not converted.
- **Unchanged**: reading tables (resolver checksum `9ee87108…`), every
  headword/reading column of `entries` and `fallback`, `components` and
  `component_notes` (Wiktionary's origin texts keep their traditional forms
  on purpose: shared rule 1), the meta table. MOE: headword and reading
  columns identical, `--traditional` reproduces the 1.7.0 file byte for
  byte; `meta.moe_text` says which text a file has (Status shows it).
- **Phase 3**: run 成語典 through `Simplifier("tw2s").convert`. Its 典故原文
  and 書證 are classical quotations; spot-check 著 there (the AUTHOR_ZHE
  rule only fires in texts that look like book descriptions). Xinhua is
  already simplified. **Phase 4**: `Simplifier("t2s")` for any traditional
  Wikisource text.

### Phase 3

**Sources, as found (2026-11-13).**

- **成語典**: the ministry's download page
  (`language.moe.gov.tw/…/respub/dict_idiomsdict_download.html`) links
  `download/dict_idioms_2020_20260929.zip`: one .xlsx, fetched by script (`build_idioms.py`
  reads the link off the page, with that file as a fallback). It holds **5,489 entries, not
  28,000**: 1,664 main entries (主條) with every field and 3,825 related entries (非主條). The
  planning figure counted the 23,385 brief entries from 重編國語辭典, which are not in this file
  (the MOE file already has them). A related entry carries its own 釋義 and 書證 and names its
  main entry ("見「X」條", 3,769 of them); its 典源 and 典故說明 fields only say "此處所列為「X」之
  典源，提供參考", so the build copies the main entry's, headed with its name. Markup: `_x000D_`,
  `*N*` note numbers, newlines around annotated words, `#`/`＃` before a context paragraph, `※`,
  `◎`/`◎1` editorial marks, `△…` related-idiom lists. 17 headwords contain a comma (never
  tappable) or a non-BMP character and are dropped. 206 lines with private-use or non-BMP
  characters are dropped (popup rule: no boxes).
- **Short line, changed from the plan**: the plan said 成語典 釋義, but 釋義 is long (literal
  meaning, figurative meaning, source, cross-references). The popup uses 用法說明's 語義說明
  (形容人非常吝啬。贬义。), present for every main entry; the full 釋義 is in the 出处 view. A related
  entry uses its own 釋義, completed with its main entry's 語義說明 when it only says which
  idiom it equals (犹「玉石俱焚」：比喻…).
- **Xinhua**: 30,895 words (no duplicates; the plan's 31,648 listed). Kept: 30,212 of 4–8 Han
  characters. 550 contain commas; 126 three-character entries include scraping fragments
  (沧横流, 涸石烂) and were dropped. Repairs and their limits are in `tools/chengyu.py`'s
  docstring. Notably the colon rule is safe only for two-character glosses and for
  one-character glosses after a 「；」 in a gloss list (a one-character match at the start is
  wrong too often: 鼻子发青, 一百次中), and only when something follows the gloss (有国难投:
  有国家却不能回去 is the whole explanation). Besides ★ and ◇, the scraping left about 20 other
  symbols where text was lost (∶ ∥ ≤ ‖ ■ ⊥ § → ∝…), shown as ….
- Both files: a `fallback` table for idioms CC-CEDICT lacks and an `idioms(simp, trad, short,
  view)` table for all, so CC-CEDICT's idioms get the line and 出处 too. 21.7 MB and 14.9 MB.
  The 成語典's related entries repeat their main entry's text (about half the size); fine for a
  user file. Default order: wikt, cbdb, moe, idioms, xinhua, wp, moegirl. MOE stays ahead of
  the 成語典 (its definitions are as good for the entry line), and the 出处 button does not depend
  on which source gave the entry.

**Coverage** (`tools/measure_chengyu.py`, report in `build/measure/chengyu-report.md`).
The corpus in `build/corpus/` is **46 device books** plus 临高启明, not 184 (184 seems to have
been a different count; `index.tsv` keeps 48 files including 临高启明's two). A chengyu is any
headword CC-CEDICT tags *idiom* (3–8 characters) or either file lists (4–8), so "after" is
100% by construction; the before figures and the newly covered ones are what matter.

| | 46 books | 临高启明 |
|---|---|---|
| occurrences / distinct | 202,036 / 9,959 | 38,398 / 5,498 |
| entry, release only | 93.2% | 93.7% |
| entry, + MOE | 97.3% | 97.7% |
| entry, + MOE + 成語典 + Xinhua | 100% | 100% |
| Chinese short line | 94.7% | 94.6% |
| 出处 view | 92.4% | 92.3% |
| 出处 from the 成語典 | 30.3% | 28.9% |
| newly covered (no entry even with MOE) | 1,282 idioms, 5,397 occ. | 353, 880 |

39 of 40 random new-entry contexts were on jieba word boundaries.

**Device check** (test book `build/chinesehelper-chengyu.epub`, pushed to `/sdcard/Download/`;
rows at y = 395, 467, 540, 612, characters ≈ 47 px wide from x ≈ 100: 他一毛不拔。玉石俱碎。/
精兵强将。首鼠两端。/ 之乎者也。十二万分。/ 刻舟求剑。科班出身。): line and label under
CC-CEDICT's entry, 出处 views from both sources, MOE winning the entry for 玉石俱碎 with the
成語典's 出处, no button for 十二万分 (Xinhua has no source or example), Status lines. Tap timing
was not re-measured: a popup now makes up to two more indexed queries.

**For phase 4**: 之乎者也 (孔乙己) has CC-CEDICT's entry, Xinhua's line
(这四个字都是文言虚词…) and a Xinhua 出处 (宋·文莹《湘山野录》：“之乎者也，助得甚事？”); the
成語典 does not have it. A screenshot of it needs the Xinhua file installed. For a 成語典 出处
shot, pick a chengyu the 成語典 has (刻舟求剑, 一毛不拔, 掩耳盗铃).

### Phase 4

**Changed decisions (user, during the session).**

- **No Origin button**: "not interesting to me. whatever happens to show about the character in
  the popup is enough." `Tap:originText`/`showOrigin` are gone. The `component_notes` table
  (6,591 notes, 1.1 MB of text) is still in the database, unused, because 1.9.1 reuses 1.9.0's
  database byte for byte; drop it (`tools/build_db.py`, `COMPONENTS`/`NOTES` SQL,
  `DB:notes`, the note checks in `tests/test_components.lua`) at the next database rebuild.
- **No component buttons**: every popup button is the character, a word from the text
  containing it, 出处 or Close (plus Translate). `Tap:showCharPopup` (a part's own popup) and
  `Components.buttons` are gone. So the shot list's **three-frame strip (茴 → 回's popup) is
  dropped**: shot 3 is the single 茴 popup.
- **Shot 7 shows the button, not KOAssistant's answer.** Pressed on 窃书不能算偷, Gemini
  (gemini-3.5-flash-lite) wrote 涨红了脸 as *zhǎng hóng le liǎn* (it is *zhàng*, which the plugin
  gets right), and the text differs on every run, so the gate cannot vouch for it.

**Sample book** (`samples/xiaoshuo.epub`, `tools/make_sample_epub.py`; guwen.epub rebuilds
byte-identical). Wikisource pages via the parse API at pinned revisions (三國演義/第001回
2583915, 孔乙己 2605389, 阿Q正傳 2633268), cached in `build/sources/wikisource/`. The 鲁迅 pages
transclude scanned-page text (`prp-pages-output`), which a revision id does not pin.
- 三国演义: the 毛宗岗 edition opens with 词曰 and the 临江仙 as `<dl><dd><dl><dd>` lines (the
  innermost elements only, or the first line is lost); `{{YL|建寧二年}}` renders with a
  TemplateStyles `<style>` block inside the paragraph (stripped).
- The 1938 《鲁迅全集》 uses old glyph variants OpenCC leaves alone: 偸 淸 靑 嬾 煑 儍 汚 尙 鎗
  揑 礮 朶 盌 鬭 嘷 簷 燄 尅 呪 寃 鑪 (and 儅 in 伴儅 in 三国), mapped to the standard forms, and
  𩓐子 (outside the BMP) = 脖子. Words are left alone (豫备, 钞书, 推著). Corner quotes become
  “” ‘’ (三国 「」 outer, 鲁迅 『』 outer). Simplifier("t2s")'s extra rules never fired versus
  plain OpenCC except the BMP rule (礮, 鑪), then mapped. The book ends each story at its date
  line, so the PD licence boxes are left out.

**Capture** (`tools/make_screenshots.py`, gate `tools/shot_gate.py`).
- Reader: Noto Serif SC, `copt_font_size` 20 (about 43 px characters), line spacing 100, h
  margins 50/50, landscape 1680×1264. Page 1 of 第一回 is then exactly title + 临江仙 + the
  话说天下大势 paragraph. Pages used: 1 and 2 (三国), 13 and 14 (孔乙己), 59 (阿Q正传: 观音).
- The sidecar must contain `cre_dom_version` (20240114), or KOReader asks to upgrade the
  rendering. The device had **night mode on** (`night_mode`, with `autowarmth_control_nightmode`):
  the script turns both off for the shots, and `debug = true` so the tap log lines appear. It
  backs up `settings.reader.lua` and restores it in a `finally`.
- **Pinyin changes pagination** (74 pages on, 69 off: the plugin adds line space), so the
  off/on image uses page 1 in both modes, each crop ending after the same line.
- A TextViewer (出处) takes several seconds to appear after the tap: wait 9 s.
- Popups taller than half the screen are centred and cover the tapped character (then the
  header phrase shows it); 窃's short popup goes to the top half with the 窃书 line visible.
- The device log check catches wrong tap positions (间 first tapped one character off) and the
  gate catches wrong occurrences (the first 也 on page 13 is 主顾也, not 之乎者也's).

**Gate results.** Drawn readings, each checked by hand: page 1 樵 qiáo 渚 zhǔ 锢 gù 宦 huàn
涓 juān (as planned; 宦 drawn once per page); page 2 蟠 pán 臾 yú 雹 báo 邕 yōng 霓 ní 谞 xū
蹇 jiǎn 恽 yùn 藜 lí 讫 qì; page 13 茴 huí; page 14 砚 yàn 拭 shì 颓 tuí; page 59 诧 chà 愕 è.
Not shot: 朱隽 (later in 第一回) is drawn as the pair *jùn/juàn*; 陈蕃 at 2,500 as planned.

**Wrong or poor popup content seen while choosing taps** (common characters, nothing drawn;
none in a screenshot; not fixed):
- 我整天的靠着火: 着 marked *zháo*, "着火 decides" (it is 靠着 + 火).
- 他还比秀才长三辈呢: 长 *cháng*, "长三 decides" (it is *zhǎng*, senior).
- 也是汗流满面的唱: 的 *dī*, "面的 decides" (taxi).
- 倘使他号叫月亭: 号 *háo*, "号叫 decides" (it is *hào*, his style name).
- 加以最近观察所得: "观察所 decides 观's reading" (MOE's word, wrong split; the reading guān is right).
- 涨红了脸 shows "no definition in CC-CEDICT" (an empty CC-CEDICT entry), so shot 2 uses 间或.
- 鸡 (雞) has no "simplified:" line (its `Han simp` lacks f/t), so shot 4 uses 观 in 观音.
- In 第一回, 孔乙己 and the first 40 paragraphs of 阿Q正传, no popup had more than three labelled sources;
  CBDB and WP labels never appeared. Shot 6 is 秋 (MMAH, MOE, Wikt).

**成語典 fix (found by the gate).** The ministry's file separates senses with **＆** (in
語義說明, 使用類別, 例句) and source passages with **＆**/**＋** (典源, 注解, 典故說明). They were
shown as written ("形容计数的仔细。＆比喻…" in 753 short lines, 519 views). `tools/chengyu.py`
now drops them (`SEPARATOR`, `one_line`; tests in `tests/test_chengyu.py`). Rebuilt file: only
those short lines (each equal to the old one minus ＆) and views changed; pushed to the device.

### Phase 5

**Word count** (`wc -w`, which counts a run of Chinese characters as one word): 8,973 → 6,648.
Alt texts unchanged (369 words, checked string by string). Further cuts would have lost user
information (credits, per-source build notes, the components and chengyu tables), so the
5,500 target was not met.

**Numbers checked against the data** (release database SHA-256 `20cc7ff8…`, 36,364,288 bytes;
optional files in `build/`; `tools/eval_readings.py` rerun, every Accuracy figure reproduced):

- Wrong in the README and fixed: database "about 33 MB" (36.4 MB); MOE download "7 MB"
  (`dict-revised.json.xz` is 15 MB); CBDB "about 110 MB zipped" (`cbdb_20261107.zip` is 140 MB);
  "about 200" unusual-reading words (298 in `special`; 65 of the 71 curated ones are in it);
  MOE "about 90,000 entries" vs "about 160,000" (the source has 161,194; the file keeps 90,501);
  成語典 5,489 / 5,473 / "about 5,500" (the file's `idioms` table has 5,473, used throughout;
  5,489 is the xlsx's entry count, and 5,489 less the 17 dropped headwords is 5,472: the
  difference of one was not looked into).
- Right: 125,397 CC-CEDICT entries, 60,950 Wiktionary rows (60,415 headwords), 39,122 Wikipedia
  titles, 2,920 CBDB, 352 Moegirlpedia, 3,704 / 23,485 idiom fallback rows, 30,212 Xinhua idioms
  (24,110 with a 出处 view), 952 rules, 535 uncertain characters, 13,362 components.
- `data/README.md`: the user-files table gained the 成語典 and Xinhua rows; MOE's build date is
  2026-11-13 (the 1.8.0 rebuild), not 2026-11-11.

**Removed from the README and not in the CHANGELOG** (kept here so they are not lost):

- Speed against koreader-interlinear-pinyin 0.5.0, same book and pages: 13.7 ms per page (this
  plugin 13.4 ms); 0.5.0 read its text files in 190–270 ms (this plugin's tables about 230 ms);
  pages were pixel-for-pixel identical until 1.4.0's Wiktionary readings.
- Tap timings (1.2.0–1.4.0): 14.7 ms median (16.9 ms mean) with Wiktionary and MOE, 13.8 ms
  (16.6 ms) without; first tap after opening a book 20–30 ms either way; MOE opened in 1–3 ms;
  memory 133 MB against 131 MB. 1.5.0, all five fallback dictionaries: 17–20 ms median (18–29 ms
  mean) against 14–15 ms (about 15.5 ms mean) with Wiktionary and MOE, over the same 31 taps,
  two runs each, Translate button showing; the first run after installing had five taps of
  70–85 ms that did not recur. The README keeps only the current figures. The two idiom files
  (1.9.0) were never timed.
- Translate button (1.3.0): Wi-Fi check and mode choice 1–2 ms when the popup opens (popup built
  in 9–15 ms against 7–10 ms without the button, same character); finding the sentence 2–3 ms.
- Edge band in pixels at 300 dpi: 2.5 mm 30 px, 5 mm 59 px, 7.5 mm 89 px, 10 mm 118 px (the
  README keeps 5 mm = 59 px).
- Settings the migration copies from the old plugins: pinyin on or off, the frequency threshold,
  pinyin size, uncertain readings, unusual readings, and whether the popup is on; neither old
  plugin had per-book settings.
- The Accuracy measurement continues the one published with koreader-interlinear-pinyin, on the
  same split.
- Which glosses go through `font_safe()` (Wikipedia, CBDB, Moegirlpedia: emoji, kaomoji,
  symbols, non-Latin/CJK scripts, Greek spelt out): now only in `tools/fallback_sources.py` and,
  for Wikipedia and Moegirlpedia, `data/README.md`.

**Code changes recommended** (not made: this phase was README only):

1. Resolver-only words show spaced pinyin in the popup (`冒顿  mò dú`, `tests/test_special.lua`),
   while CC-CEDICT words are joined (单于 chányú). Join the syllables in `ch_popup_model.lua`
   (`decided.syllables`), and in the menu help text of "Mark unusual readings" (`main.lua`).
2. Menu help texts are out of date: **Fallback dictionaries** names only CBDB, MOE and
   Moegirlpedia as files you build (not the 成語典 and Xinhua), and **Source labels** lists the
   labels without 成语典 and 新华.
3. The Source labels choice "Other dictionaries only (not CC-CEDICT)" could be "Fallback
   dictionaries only", the README's name (the README now notes the mismatch once).
4. `build_moe.py`, `build_cbdb.py` and `build_moegirl.py` fail without the plugin database; the
   two idiom scripts fetch it from the latest release (`fallback_sources`). Doing the same in all
   five would make every optional dictionary one command from a fresh clone (shared rule 2).
5. The MOE file has 5 senses with private-use characters shown as □ (build log), against the
   no-boxes rule; drop those lines as the 成語典 build does.
6. Drop `component_notes` at the next database build (already decided in phase 4).

