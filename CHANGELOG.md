# Changelog

## 2.14.0 (2026-11-19)

Simplified forms for traditional taps (#50)
- A character or word tapped in traditional characters (a page of a traditional book, or MOE's
  and the 成語典's text in a popup, now in MOE's own characters since 2.13.0) shows its
  simplified form on the head line, in bold, with the form as tapped beside it, small and grey,
  just like a simplified tap: 頭 in 頭髮花白 is **头** 頭 *tóu*, the word **头发** 頭髮 *tóufa*;
  發 in 發現 **发** 發, 東西 **东西** 東西.
- A character shows **one** simplified form, the one the word around it uses (乾 in 乾淨 →
  **干** 乾; 噁 in 噁心 → **恶** 噁), else its head line's reading's (乾 on its own, read gān → **干** 乾).
  Nothing is added where the form is the same in both scripts (乾 in 乾隆, 著 in 著名, 人民).
- Applies to every block with a head line: CC-CEDICT's, the fallback dictionaries', MOE Always
  blocks, idiom blocks and nested popups. Simplified taps are unchanged (checked on 18,090
  common simplified words). A fallback row with an empty or other-length simplified form, or
  one outside the BMP that would draw as a box, adds nothing.
- Same setting, **Show traditional forms**; off, head lines are exactly as in 2.13.0.

## 2.13.0 (2026-11-19)

Dictionary text as each source writes it (#48)
- Each dictionary's text is now shown as its source writes it, by default: MOE 重編國語辭典 and
  the 成語典 (short lines and Origin & Usage) in MOE's traditional characters, Wiktionary's
  glosses with their Chinese as written (`original form of 廩／廪`), and CC-CEDICT's
  cross-references with both forms (`variant of 夠|够 gòu`, `used in 鞦韆|秋千 qiūqiān`).
- **New setting, Dictionary text** (Popup → Dictionaries): **Original** (default) or
  **Simplified**, which gives exactly the text of 2.12.0 (`variant of 够 gòu`). It applies from
  the next popup, to every block, MOE Always blocks, idiom short lines, the Origin & Usage view
  and nested popups. Head lines are unchanged (**头发** 頭髮), and so are the dictionaries that
  are simplified or English already (Xinhua, Moegirlpedia, CBDB, Wikipedia titles).
- Both versions are stored; nothing is converted on the device. **Rebuild your MOE and 成語典
  files** (`tools/build_optional.py --only moe,idioms --force`, then copy them over): files
  built before 2.13.0 hold one version, which the popup shows whatever the setting, and
  **Status** says so. `--traditional` is gone from the build scripts.
- Sizes: the release database 36.3 → 37.8 MB (the zip 17.4 → 17.6 MB); the MOE file 28.2 →
  45.2 MB, the 成語典 file 21.7 → 36.3 MB.
- MOE's popup label is now **國語辭典** (was MOE); the menu and Status still say MOE 重編國語辭典.
- A self-referring "variant of" sense is dropped in either form (`variant of 個|个 gè` on 个).

## 2.12.0 (2026-11-19)

Traditional forms on the head lines (#47)
- Each popup entry's head line shows the word's traditional form beside it, in the same
  typeface, smaller (0.8×) and grey, when it differs: **头发** 頭髮, **中国** 中國; nothing for
  人民. A word shows the one form its entry gives (发现 發現, 干净 乾淨). A single character with
  several shows them all, "/"-joined, the one the word around it uses first (发 in 头发:
  髮/發; 干 in 干净: 乾/干/幹), the character itself included when it is one of them.
- Applies to every block: CC-CEDICT's, the fallback dictionaries', MOE Always blocks and
  nested popups. A Wiktionary "traditional" form of another length (a longer wording, another
  word) is not shown. A book in traditional characters adds nothing. The entries' text and the
  components block are unchanged.
- **New setting, Show traditional forms** (on by default), after Show character frequency rank.

## 2.11.1 (2026-11-19)

Frequency ranks labels (#45, #46)
- The bundled option is now **Bundled: web, books, news, subtitles**, and its help names all of
  wordfreq's sources for Chinese: web pages, Google Books, news, film and TV subtitles,
  Wikipedia, Twitter and Jieba's wordlist (#45).
- With From my books on, the 字频 line shows just your rank (**字频 3,504**, or **5,700+** past
  your file's exact ranks), without "(my books)". A character not in your books still says
  **(bundled)**, since that rank is on a different scale (#46).

## 2.11.0 (2026-11-19)

Your own frequency ranks (#42)
- **New setting, Frequency ranks**: **Bundled (modern Chinese)** (the default, as before) or
  **From my books**. On a computer, `tools/build_user_ranks.py` ranks characters by your own
  books (from `tools/fetch_books.py`, or `--epubs DIR`): by how many works a character appears
  in, then how often, so one novel's cast of names cannot make rare characters common. Volumes
  of one work and duplicate copies count once; traditional forms count as simplified, 〇 as 零.
  `--push` copies the file to `koreader/settings/chinesehelper_ranks.tsv` over USB.
- With From my books on, the ranks decide which characters get pinyin, the popup's 字频 line
  and which pinyin is dropped first on a crowded line. Characters not in your books keep their
  bundled rank. 字频 says which it shows, **(my books)** or **(bundled)**, and shows **N+**
  past the ranks the library can tell apart (the file's exact cut-off).
- Nothing about the data changes: which words are held in memory and everything the database
  build decided keep the bundled rank. The release ships no one's ranks; From my books is
  disabled until you have a file.
- `tools/compare_user_ranks.py` compares a rank file with the bundled ranks (crossings at a
  threshold, and page-sized passages run through the plugin's own code).

## 2.10.0 (2026-11-19)

Spoken tones for 一 and 不, on in learner mode (#37)
- **New setting, Spoken tones for 一 and 不** (In learner mode, the default; Always; Never). The
  pinyin shows the tones of speech, as beginners' textbooks do: 一个 *yí gè*, 一天 *yì tiān*,
  不是 *bú shì*, 是不是 *shì bu shì*, 看不见 *kàn bu jiàn*, 吃不了 *chī bu liǎo*, 看一看
  *kàn yi kàn*. 一 stays *yī* as a number or ordinal (第一, 十一, 一九九八, 一月, 统一, 之一,
  一等奖) and before punctuation; between two units it is a quantity again (一万一千 *yíwàn
  yìqiān*). A verb and complement no dictionary word confirms keeps *bù*.
- Known and remind-me marks stay on the dictionary reading (**I know bù** hides 不 in every
  tone). The popup's entries keep *yī* and *bù*; the character's own entry gets a grey
  **spoken here: bú**.
- Measured on 49 books: about 800 sampled changes judged in context by AI reviewers over six rounds; each rule 97–100%
  right on the final code. tools/measure_sandhi.py does the scan and the judging batches.
- The README's learner-mode shots are retaken.

Leftovers of the two retired plugins removed (#34)
- No visible change. The one-time copy of koreader-interlinear-pinyin's and
  koreader-chinese-popup's settings (from 1.0.0), the warning when either was still installed,
  and the Status line naming them are gone, along with their tests. Settings already copied
  stay as they are. Code comments no longer cite the two old repos (the WordGloss credits
  stay), and tools/plugin_runtime.py no longer runs an interlinear-pinyin 0.5.0 copy.

## 2.9.2 (2026-11-19)

Popup buttons outlined in night mode (#43)
- **In KOReader's night mode, the lines between the popup's bottom buttons are visible again.**
  KOReader draws them light grey (0xAA); night mode inverted that to a dark grey (0x55) on
  black, which the Boox's e-ink hardly shows, so the word buttons, Translate & analyze and
  Close read as loose text. In night mode they are now drawn so they come out light grey
  (0xAA) on black, as day mode's are on white. Day mode is unchanged (same pixels). The
  popup's other lines and grey text were already visible in night mode.

## 2.9.1 (2026-11-18)

No punctuation lines in Translate & Analyze (#31)
- **Translate & Analyze no longer gives punctuation marks a line of their own.** The learner
  prompt (2.8.1) said to skip punctuation, but gemini-3.5-flash-lite listed every mark anyway
  (often with an empty meaning: "，(,):"), 4–7 lines per reply in three takes out of three. The
  rule is now said outright, in the system prompt too, and the example ends in a ！ that gets no
  line. Three takes with the new prompt: no punctuation lines, 15–18 entries.
- The README's Translate & Analyze screenshot is retaken with the learner reply, and its alt text
  rewritten.

## 2.9.0 (2026-11-18)

Larger line of text at the top of the popup (#32)
- **The line of text from the page at the top of the popup is now drawn at the Chinese text
  size** (130% of the popup text by default) instead of the popup text size, so it reads like
  the page and follows **Chinese text size**. The tapped character stays bold and underlined.
  On a Boox Go 7 the 孔乙己 line (31 characters) still fits whole at 130%; at 175% the popup
  shows 29 characters of it.
- The same goes for the line under the title of **KOReader's dictionary popup** opened from a
  word button: it is drawn at the Chinese text size of that popup's text.
- The menu help for **Chinese text size** and **Show the text around the character in the popup**,
  and the README, say so.

## 2.8.2 (2026-11-18)

Menu and description wording (#29)
- The pinyin toggle is now **Show pinyin** (was "Show pinyin above rare characters"): with
  **Which characters → All characters (learner mode)** it puts pinyin on every character, and
  **Which characters** already says which ones. The setting itself is unchanged.
- The **Dictionaries** help names MOE's items as they appear in the menu, **MOE for single
  characters** and **MOE for words**.
- The plugin description (KOReader's plugin manager) covers learner mode and known / remind-me
  readings.

## 2.8.1 (2026-11-18)

Translate & Analyze for learners (#30)
- **The popup's Translate & Analyze button now explains every word**, in order, for someone
  learning Chinese: a natural English translation, then one line per word with its characters,
  tone-marked pinyin and its meaning in this sentence, small words included (的, 了, 吧,
  measure words), and a short note on how the sentence fits together when its structure would
  surprise an English speaker. Grammar is described in plain words ("得 between a verb and a
  result means 'able to'"), not named ("potential complement"). Before, the prompt was written
  for advanced readers and skipped words they would know on sight.
- On a Boox Go 7 a 69-character sentence from 阿Q正传 gets its whole reply (about five pages of
  KOAssistant's viewer) within the 2000-token limit.

## 2.8.0 (2026-11-18)

Learner mode (#25)
- **Which characters → All characters (learner mode)** puts pinyin above every Chinese character
  on the page, repeats included. With **I know …** in the popup (2.6.0) a beginner switches each
  reading off as they learn it, and the page thins out. Two more levels sit between that and the
  old lowest, 1,500: **outside the 500** and **outside the 1,000 most common**.
- **The commonest function words no longer show two readings**: 的 *de*, 了 *le*, 着 *zhe*, 这
  *zhè*, 么 *me*, 呢 *ne*, 个 *gè*, 都 *dōu*, 还 *hái* and 与 *yǔ* are hand-checked defaults
  (their other readings come from words: 的确, 了解, 睡着, 首都, 还清, 参与). Before, the
  learned data put them in the uncertain list (的 *de/dì*, 了 *le/liǎo*), which never showed at
  the old levels but would have put 25–35 pairs on a page of 鲁迅 in learner mode; now about
  one character in a hundred keeps a pair there (得 *de/děi*, 过 *guò/guo*, 长). The popup marks
  them the same way. Characters with a single hand-checked reading are now never listed as
  uncertain, so the particles 哩 *li*, 咯 *lo* and 啦 *la* lose their pairs too (哩 showed *lǐ/li*
  above every 哩 in 平凡的世界). 着 in 生活无着 is now drawn *zhuó*, in bold, as an unusual
  reading. Nothing else changes at the other levels.
- No pinyin is dropped on crowded lines in learner mode on the sample book's pages (at 35% and
  40% size). On a Boox Go 7 a page takes a median 51.5 ms to prepare in learner mode, against
  30 ms at the default level.
- README: a **Learner mode** section, learner screenshots in the top grid, and the popup's
  **I know …** button.

## 2.7.0 (2026-11-17)

Every occurrence gets pinyin (#28)
- **A character that gets pinyin now gets it at every occurrence on the page**, not just the
  first, each in the reading it has there: rare characters, unusual readings in special words,
  the uncertain pair (xíng/háng) and remind-me readings alike. A reading marked known is bare
  everywhere, so each reading is now all or nothing per page; marking or clearing one from the
  popup changes every occurrence at once.
- Crowded lines drop pinyin about as rarely as before (on four sample books, roughly 1% of
  annotations at most, the most common characters first), and nothing overlaps.

## 2.6.0 (2026-11-17)

Known and remind-me readings (#26)
- **A button at the right of the popup's title bar marks the tapped character's reading**:
  **I know tāo** stops that reading from ever getting pinyin (any threshold, every book), and
  **Remind me: shū** makes a reading that wouldn't be drawn always get pinyin, once per page.
  Only that reading is affected: 刨 *bào* known leaves 刨 *páo* annotated. Marked, the button
  reads **Known tāo ✓** or **Reminding shū ✓**; a tap clears it. The page under the popup
  changes at once. An uncertain pair (xíng/háng) gets a button per reading and is hidden only
  when both are known. Nested popups have no buttons.
- **Known & remind-me readings** in the menu shows the counts, lists the marks (a tap clears
  one) and has **Clear all marks**, which asks first.
- Marks are kept by simplified form in `koreader/settings/chinesehelper_marks.lua`, which
  survives plugin updates. It is written only when a mark changes, atomically; an unreadable
  file is renamed aside, never overwritten.

## 2.5.3 (2026-11-17)

- **MOE for single characters defaults to fallback again** (#24): out of the box, a
  single-character popup shows MOE's entry only for a character CC-CEDICT lacks, in full. Set
  **MOE for single characters** to **always** (Dictionaries menu) to keep 2.5.0's MOE entry
  under CC-CEDICT's for every character, collapsed as before. A mode already chosen in the menu
  is kept; only the default changes.

## 2.5.2 (2026-11-16)

- **Words with no definition from any source are no longer listed in the popup.** A word known
  only from pypinyin's segmentation (不畅 in 受阻不畅) used to show its pinyin and "no definition
  in CC-CEDICT"; it is now left out, also when it is the word that decided the tapped
  character's reading (that character's own entry already shows the reading). Words with a
  fallback entry or a note still appear.

## 2.5.1 (2026-11-16)

- **A collapsed MOE entry ends in "[Tap to show more]"**, small and grey, right after its last
  shown line, instead of an "…" that did nothing when tapped. Tapping it, or the space after it,
  expands the entry; expanded, it ends in **[Tap to show less]**. The label line is plain "MOE"
  again, with no "show all" and no tap action. The characters before the marker still open
  nested popups.

## 2.5.0 (2026-11-16)

MOE always shown for single characters (#11, #18)
- **With the optional MOE dictionary, every single-character popup shows MOE's entry under
  CC-CEDICT's**, even when CC-CEDICT has the character: 涓 gets 细流。/ 姓。/ 细缓的、细微的。/
  清洁的。/ 选择。 under "brook; to select". Placement: CC-CEDICT's entry (with the 字频 rank),
  then MOE's, then the components, then the words.
- **MOE's entry is collapsed to two lines** as drawn, ending in "…", with all its readings as
  one block (和's six). The grey label line reads **MOE · show all**; a tap there expands the
  entry in place (**show less** cuts it again), and the popup keeps its scroll position. The
  characters left visible can be tapped for a nested popup; the hidden ones can't. A new
  **Collapse long entries** setting picks 1, 2 or 3 lines, or never.
- MOE's readings follow CC-CEDICT's order (the likely reading first). A reading CC-CEDICT doesn't
  list for the character is marked **· not in CC-CEDICT** (和 *hàn*, 亡 *wú*, 不 *fǒu*); 1,432 of
  the 9,910 characters MOE shares with CC-CEDICT have one.
- **MOE for single characters** and **MOE for words** are each off / fallback / always (defaults:
  always, fallback). Fallback is 2.4.0's behaviour. The MOE switch overrides both, and existing
  settings carry over (MOE off stays off).
- **The menu's "Fallback dictionaries" is now "Dictionaries"**, with a new **Order** item
  (KOReader's sort widget) instead of the hand-edited `fallback_order` setting, which still
  holds the order. **Status** shows MOE's modes and whether its file is ready for Always.
- **Rebuild the MOE file for Always** (`tools/build_moe.py`): it now keeps the headwords
  CC-CEDICT has, as covered rows (11,871 character rows, 50,669 word rows). It grows from 17.0 MB
  to 28.2 MB. Its 90,501 fallback rows are unchanged. With an older file, Always works as
  Fallback, popups are identical to 2.4.0's, and Status says to rebuild. The plugin database
  is unchanged.
- **Readings are unchanged.** Covered rows never reach the fallback or reading path. MOE still
  never decides a reading: `tools/eval_readings.py` gives byte-identical output to 2.4.0's, with
  and without Wiktionary fallback (72/72 regression cases).
- One query to MOE's file per tap, as before. On the Boox Go 7, building the popup takes a median
  25 ms with MOE Always against 21.5 ms with Fallback (12 common characters, 2 rounds each).

## 2.4.0 (2026-11-16)

The character's frequency rank (#17)
- **Every popup shows the tapped character's frequency rank** on its own entry, in small grey
  text: `字频 4,270` is its rank among characters in modern written Chinese (wordfreq, the same
  ranking the pinyin threshold uses). Past 7,000 it reads `字频 7,000+`, since the data is too
  thin there for an exact rank, and `字频 unranked` for a character not in the list.
- It is on the character's own entry only, also in nested popups and for a character inside a
  word or chengyu. Word entries, components and fallback words never show one. When the entry's
  source label is shown too, both share one line (`CEDICT · 字频 4,270`).
- New setting **Show character frequency rank**, on by default, next to **Show character
  components**. No database change.

## 2.3.0 (2026-11-16)

Wiktionary readings: Standard Chinese only (#15)
- **Wiktionary entries never show regional Mandarin pronunciations** (搛菜 is *jiāncài*, not
  *jiǎncāi*). Dialect words without a Standard reading take their characters' readings when those
  are unambiguous, and otherwise show no pinyin. The regional qualifier in the gloss ("(dialectal
  Mandarin, Northern Wu)", "(Xi'an Mandarin)" …) stays.
- How: a Wiktionary pinyin sound counts only when its tags are on an allow-list and include a
  Standard marker (Standard-Chinese, Standard, Mainland-China or Taiwan), so Nanjing, Xi'an,
  Sichuanese, Beijing-dialect, Harbin, Wuhan and other regional romanizations, and any tag added
  later, are left out. 1,374 entries have only regional readings: 385 rows now take their
  characters' readings (every character with exactly one CC-CEDICT reading; 子 *zǐ / zi* counts
  as two) and 887 rows show the word and definition without pinyin. Only one row that already had
  a Standard reading changed (悠千 *yōuqianr*, Wiktionary's Standard erhua form). Rows without
  pinyin never decide a reading on the page.
- The build now counts rows whose pinyin gives a character a toned reading CC-CEDICT doesn't
  have: 1,025 → 891, the rest mostly literary or variant readings (善贾 *shànjià*, 渔父 *yúfǔ*).
  Page readings on the CPP test split are unchanged.

"Likely here" only with evidence (#16)
- **The tapped character's reading is marked "likely here" only when something in the text
  picked it**: a dictionary word or special word around it, a fallback dictionary's word, or a
  context rule. When nothing did (传 in a title cut by the line, …传稿》), the usual reading
  still comes first, but unlabelled, as the uncertainty pair already was.
- `tools/eval_readings.py` reports accuracy by what decided the reading, now in the README's
  Accuracy section: context rules are right 99.9% of the time (919 test examples), words 98.0%,
  the plain default 97.2%.

## 2.2.0 (2026-11-15)

The book's font in the popup
- **Chinese text in the popup is drawn in the book's font**, behind a new setting, **Try to match
  the book's font** (on by default). It covers every Chinese character the popup shows: the line
  at the top, the character and the entries, the Chinese dictionaries' text, the Origin & Usage
  view, nested popups, source labels such as 成语典 and 新华, and the buttons. English glosses,
  pinyin and tone marks stay in KOReader's UI font (Noto Sans).
- It is the font chosen in KOReader's font menu, not a font the book embeds or sets in its CSS.
  Characters that font lacks come from KOReader's usual fallback fonts. For a PDF, or when the
  font can't be loaded, the popup uses the UI font.
- How: the popup's faces are copies with the book font first in their own fallback list;
  KOReader's global fallback fonts and its own faces are unchanged. Line height still comes from
  the UI font, so popups are the same height. Taps on characters in the popup still land on the
  right character.
- Checked on the Boox Go 7 with 华文楷体 (STKaiti) and LXGW Neo ZhiSong. With the setting off,
  all ten screenshot popups are pixel-identical to 2.1.3's.

Building the optional dictionaries
- **One command builds them**: `.venv/bin/python tools/build_optional.py` builds the MOE
  dictionary, MOE idioms and Xinhua idioms; `--all` adds CBDB office titles, `--only` picks a
  set (Moegirlpedia only when named), and files already built are skipped unless `--force`. It
  prints the download size and disk space first, and each file and where it goes on the device
  last. `--push` and `--traditional` are passed on.
- **Every build script takes the plugin database from the latest release** when the clone doesn't
  have it. Before, the MOE, CBDB and Moegirlpedia scripts stopped with "build the plugin database
  first (tools/build_db.py)". The README's step for adding the database is gone.

The database is unchanged.

## 2.1.3 (2026-11-15)

Popup labels
- **No more "· shown above".** The reading drawn on the page still comes first, now with no
  label (you can see it); a pair drawn on the page (掊 póu/pǒu) lists both readings unmarked.
  "· likely here" still marks the resolver's reading when nothing is drawn.
- **The 出处 button reads "成语 Origin & Usage"**, so it is clearly an action, not a word to
  look up; with several chengyu in one popup each is named ("九牛一毛 - Origin & Usage"). The
  full-screen view's title reads "九牛一毛 · Origin & Usage · 教育部《成语典》". The 出处 headings
  inside the dictionaries' own text are unchanged.
- **Translate is only in the popup opened from the page**, not in popups opened from a popup's
  text or the Origin & Usage view. With KOAssistant installed it reads **"Translate & analyze
  the surrounding sentence [AI]"**. The prompt sent is unchanged.
- README screenshots retaken with the new labels. The database is unchanged.

## 2.1.2 (2026-11-15)

Popup buttons
- **Close is always the bottom button, on a row of its own.** Before, Close sat in the row of
  word buttons, and while Wi-Fi was on, Translate came after it, below Close.
- **Nested popups have just Close, which closes only that popup; no Back button.** A popup opened
  from another, and the 出处 view, show only **Close**; it closes that popup and shows the one
  below (as the device's Back key does). A tap outside or Translate still closes them all; a
  top-level popup's Close still closes it and the underline on the page.
- **The Translate button reads "Translate & Analyze [AI]"** with KOAssistant installed, so it is
  clear the answer comes from a language model. The prompt sent is unchanged.
- README screenshots retaken with the new button order and label.

## 2.1.1 (2026-11-14)

Tapping the page
- **A tap inside the text always opens the popup, for the nearest Chinese character.** Before,
  only a tap on a character's glyph did; a tap between two lines (the empty half-line below the
  characters), on punctuation (，。《》) or in a paragraph's indent fell through to KOReader and
  turned the page. Now the character whose glyph is nearest to the tap is taken (a tap on ，
  takes the nearer of its neighbours), and the underline on the page marks it.
- **The text** is each line from its first to its last character, plus 1.5 mm either side, the
  full height of the line, and the gap between two lines while it is less than a line high (so
  paragraph spacing counts). A paragraph's first line also covers its indent.
- **Still KOReader's**: the edge band (checked first, unchanged), links, highlights, text
  selection; the margins, the blank space after the last paragraph on a page, the empty rest of
  a short line, the space around images; and any line with no Chinese characters (an English
  paragraph, a line of numbers).
- **Latin text in a Chinese line** takes the nearest Chinese character on that line or the line
  above or below, if one is within three characters' width; otherwise the tap does nothing (no
  popup, no page turn).
- The plugin works the geometry out at tap time, around the tap only: from the character
  crengine snaps the tap to, it reads the characters of the tapped line and the lines above and
  below it (12–100 characters), one box each. Page turns do no extra work. The **Status**
  screen shows the last tap's decision (the character, its distance from the tap, the time),
  and KOReader's debug log has a line for every tap.

Measured on the Boox Go 7 (adb taps, 48 in all, on a dense page of 张宏杰's 历史的正面与侧面, 64 px
text in 103 px lines, and on two test books). On the dense page: below 皇's glyphs (8 px) took
皇, above 计's took 计, the line boundary took 帝; the left and right halves of ， after 终
took 终 and 我; 。 after 键 and 好 took them; the indent before 其三 took 其 (68 px from its
glyph); the tail of the short line 大戏。他的运气非常好。 took 好 within the pad and turned the
page beyond it. In the test books: Latin and digits in Chinese lines took 了, 的, 年 or the
character above or below (47–63 px); the English-only paragraph, the space right of short lines
and the blank space below the last paragraph went to KOReader. None of the 30 taps that opened
a popup turned the page; all 15 pass-through taps went to KOReader. Deciding takes 1–2 ms for a
tap on a glyph and 3–13 ms otherwise.

Unchanged: the plugin database (byte-identical to 2.0.0, SHA-256 `20cc7ff8…`), every reading,
the optional dictionary files.

## 2.1.0 (2026-11-14)

Popup
- **Tap a character in the Chinese dictionaries' text to look it up.** In the text of MOE, the
  成語典, Xinhua and Moegirlpedia (definitions, quotations, an idiom's short line, the 出处 view),
  a character opens its own popup on top, looked up like a tap in the book: the character and
  every word around it in that text that contains it. The character stays underlined in the
  popup below while the new one is open. Nothing else in the popup is tappable (headlines,
  components, English glosses). A tap on a character, or within half a character's width of one
  (beside it, above or below it, on the punctuation next to it), takes the nearest, on the
  tapped line first; any other tap does what it did before. The mapping uses the positions
  KOReader's text boxes laid the characters out at, so it holds after scrolling.
- **The popup's own sentence.** A popup opened from popup text takes its context line and its
  Translate text from that text, not the book: the sentence around the character, cut at 。！？；,
  a line break or a closing quote after one of them; a whole 「…」 or 『…』 quotation when the
  tap is inside one (秃 in 首鼠两端's 典源 gives 「与长孺共一老秃翁，何为首鼠两端？」). KOAssistant gets
  the entry's text around the sentence as its context, trimmed by its own rule.
- **Back and Close.** A popup opened from another has a **Back** button (the device's Back key
  does the same): it closes that popup and shows the one below. **Close**, a tap outside and
  **Translate** close them all, with one refresh. At most 5 popups are open at once (a 出处 view
  counts); past that a tap says so and opens nothing.
- **Chinese text size** (new menu item, after **Popup text size**): the Chinese dictionaries'
  text (MOE, 成語典, Xinhua, Moegirlpedia) is drawn larger than the rest of the popup, 130% of the popup text by
  default (100, 115, 130, 150 or 175%), so it is easier to read and to tap. English glosses,
  source labels and buttons keep the popup text size. On a Boox Go 7 with 64 px book text and
  60% popup text: 38 px (3.2 mm) English, 49 px (4.2 mm) Chinese.
- **The Chinese-language dictionaries' entries come last**: MOE, 成語典, Xinhua and Moegirlpedia entries
  (when one of them is the fallback for a word) now follow every other entry, the components
  block included. An idiom's short Chinese line stays under the entry it belongs to.
- **The 出处 view is a full-height popup** instead of KOReader's text viewer: the larger Chinese
  size, every character tappable, **Back** and **Close**.

Measured on the Boox Go 7 (adb taps): 20 taps on characters, 10 in MOE's 三楚 definition and 10
in the scrolled 出处 view of 首鼠两端, each took the character under the tap point, including 7
near misses (on a character's edge, on 、 or 。 beside it); a tap above the scrolled window took
nothing; taps on headlines, components and CC-CEDICT glosses open nothing. A nested lookup takes 12–17 ms.

Unchanged: the plugin database (byte-identical to 2.0.0), every reading, the optional dictionary
files.

## 2.0.1 (2026-11-13)

Popup
- **No "· one of these" label.** When nothing decides between a character's two likely readings,
  both are now simply listed, the likelier first, with no marker. The label repeated on both
  lines and said nothing the list itself didn't.

Unchanged: the plugin database (byte-identical to 2.0.0), every reading.

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
