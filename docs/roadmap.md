# Roadmap: components, simplified text, chengyu, README screenshots

Written 2026-11-13 from a planning discussion, against v1.6.1 (database from the
v1.6.1 release). Four phases, one release each, run as separate Claude Code
sessions.

| Phase | What | Release | Status |
|---|---|---|---|
| 1 | Character component breakdowns in the popup | 1.7.0 | released 2026-11-13 |
| 2 | All explanatory text in simplified characters | 1.8.0 | released 2026-11-13 |
| 3 | Richer chengyu entries (two build-it-yourself dictionaries) | 1.9.0 | not started |
| 4 | New README screenshots and sample book | 1.9.1 | not started |

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
(none yet)

### Phase 4
(none yet)
