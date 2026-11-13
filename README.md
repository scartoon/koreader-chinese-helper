# koreader-chinese-helper

**A [KOReader](https://github.com/koreader/koreader) plugin for reading Chinese: tap any character
and see the words it forms in this sentence, with the reading it has here.**

Chinese has no spaces between words, so an ordinary dictionary lookup means long-pressing,
dragging a selection and guessing where the word ends. Here you tap one character. The plugin
reads the text on both sides of it, finds the dictionary words actually written there, and marks
the reading the character takes in this context: 行 is *háng* in 银行 but *xíng* in 行人. You can
also turn on pinyin, drawn only above characters that are rarer than a cutoff you choose: the hard
ones get help and the rest of the page stays clean. It works on any reflowable book (EPUB, FB2, MOBI, TXT and the like) as soon as
you open it.

![The opening of 三国演义 第一回 on a Boox Go 7: the chapter title, and below the popup the last lines of the 话说天下大势 paragraph with pinyin above the rare characters only (gù over 锢, huàn over 宦, juān over 涓). The popup is open on 涓: juān, "brook; to select", "Juān: surname Juan"; its parts, labelled MMAH: 氵 shuǐ water → meaning, 肙 yuān "a small worm; to twist" → sound (same ending); then 中涓 zhōngjuān "(archaic) eunuch", labelled Wikt; buttons 涓, 中涓, Close and Translate & Analyze](docs/main.png)

<table>
<tr>
<td width="50%"><a href="#line-spacing"><img src="docs/off-on.png" alt="The 临江仙 that opens 三国演义, pinyin off (top) and on (bottom): with it on, only 樵 qiáo and 渚 zhǔ get pinyin, the rest of the page stays clean"></a><br><b>Pinyin only above the hard characters</b>, at the level you choose (here the default: outside the 3,500 most common)</td>
<td width="50%"><a href="#the-popup"><img src="docs/context.png" alt="Popup for 间 in 孔乙己's 虽然间或没有现钱: 间 jiàn · likely here, jiān listed after it; 间或 jiànhuò · decides 间's reading, occasionally; now and then"></a><br><b>The reading it has here</b>, and the word that decides it: 间 is <i>jiàn</i> in 间或</td>
</tr>
<tr>
<td><a href="#character-components"><img src="docs/components.png" alt="Popup for 茴 in 孔乙己's 要一碟茴香豆: 茴 huí; its parts, labelled Wikt: 艹 cǎo grass; plant (草字头) → meaning, 回 huí to go back → sound (same sound); then 茴香豆 and 茴香"></a><br><b>What each character is made of</b>: 茴 is 艹 for the meaning and 回 <i>huí</i> for the sound</td>
<td><a href="#character-components"><img src="docs/traditional.png" alt="Popup for 观 in 阿Q正传's 观音娘娘: 观 guān · likely here; traditional 觀: 雚 guàn (archaic) stork; heron → sound (same sound), 見 jiàn see → meaning, simplified: 雚 → 又; 观音 Guānyīn · decides 观's reading"></a><br><b>Parts the simplification hid</b>: 观 is read through 觀, 雚 <i>guàn</i> → sound</td>
</tr>
<tr>
<td><a href="#chengyu"><img src="docs/chengyu.png" alt="Popup for 也 in 孔乙己's 满口之乎者也: 满口之乎者也 and 之乎者也 from CC-CEDICT, 之乎者也 with a Chinese line labelled 新华: 这四个字都是文言虚词，讽刺人说话喜欢咬文嚼字。也形容半文不白的话或文章。; a 出处 button"></a><br><b>Chengyu explained</b>: 之乎者也 with Xinhua's line (optional file) …</td>
<td><a href="#chengyu"><img src="docs/chengyu-2.png" alt="The 出处 view for 之乎者也 from 新华成语: 释义; 出处 宋·文莹《湘山野录》：“之乎者也，助得甚事？”; 例句 他对人说话，总是满口之乎者也，叫人半懂不懂的。"></a><br>… and its <b>出处</b>: the classical source and an example (this very line of 孔乙己)</td>
</tr>
<tr>
<td><a href="#fallback-dictionaries"><img src="docs/labels.png" alt="Popup for 秋 in the 临江仙's 惯看秋月春风: 秋 qiū from CC-CEDICT; its parts 禾 and 火 labelled MMAH; 秋月春风 labelled MOE with its Chinese definition; 秋月 labelled Wikt; a 出处 button"></a><br><b>Several dictionaries, each labelled</b>: CC-CEDICT, then MOE (optional) and Wiktionary for 秋月春风 and 秋月</td>
<td><a href="#translating-the-sentence"><img src="docs/translate.png" alt="Popup for 窃 at the top of the page, with a Translate &amp; Analyze button; below it the page of 孔乙己 with the line 窃书不能算偷……窃书！……读书人的事，能算偷么？"></a><br><b>Translate &amp; Analyze the sentence</b> with KOAssistant (while Wi-Fi is on): here 孔乙己's 窃书不能算偷</td>
</tr>
</table>

All screenshots: a Boox Go 7 (landscape), the [sample book](#the-sample-book), default settings,
with every optional dictionary installed. `tools/make_screenshots.py` takes them again.

- **One tap, no selecting.** A single tap on a Chinese character, or on the pinyin above one,
  opens the popup. Taps anywhere else turn pages and open menus as usual.
- **Only the words on the page.** The plugin checks every stretch of 1–8 characters through the
  tapped one, up to 7 characters on each side, and lists those that are dictionary words, longest
  first. Tap 宛 in 很大宛如 and you get 宛, 大宛 and 宛如, not every word in the dictionary that
  contains 宛. Nothing guesses where the words break, so when a sentence could divide two ways,
  you see both.
- **The reading it has here, marked.** For every character, common ones included, the popup
  marks the reading it takes in this sentence and names the word that decided it (的 is *dí* in
  的确). The deciding word is the 2–4 character dictionary word around the character (the more
  common one, by [wordfreq](https://github.com/rspeer/wordfreq), when two overlap); failing that,
  one of about 950 context rules learned from labelled Wikipedia sentences; failing that, the
  character's most frequent reading. Where nothing decides, both likely readings are marked. On
  held-out test sentences built around the hard cases among the 1,000 most common characters,
  the marked reading is right 97.5% of the time (see [Readings](#readings) and
  [Accuracy](#accuracy)).
- **Several dictionaries, one popup.** CC-CEDICT first, then fallback dictionaries for the words
  it lacks, each entry labelled with its source, in this order:

  | Dictionary | Label | | Mainly covers |
  |---|---|---|---|
  | Wiktionary | Wikt | bundled | historical and literary terms, chengyu, technical terms, some slang |
  | CBDB office titles | CBDB | a file you build yourself | Ming and Southern Ming office titles |
  | MOE 重編國語辭典 | MOE | a file you build yourself | historical and literary vocabulary (in Chinese) |
  | MOE 成語典 | 成语典 | a file you build yourself | chengyu, with their source texts and stories (in Chinese) |
  | Xinhua idioms | 新华 | a file you build yourself | about 30,000 chengyu and set phrases, with classical sources (in Chinese) |
  | Wikipedia titles | WP | bundled | technology, engineering, military and history terms, and many proper names: places, organisations, works (English article title) |
  | Moegirlpedia slang | Moegirl | a file you build yourself | internet slang (in Chinese) |

  The fallback set was chosen with the time-travel novel 临高启明 in mind, which mixes Ming
  officialdom, early-industrial technology and internet slang, so its readers are well served;
  nothing in the plugin is specific to it ([Coverage on one book](#accuracy)). Their
  explanatory text is in simplified characters, including MOE's (converted when you build it;
  see [Simplified text](#simplified-text)).

- **Chengyu explained, with their source.** With the optional 成語典 or Xinhua idiom files, a
  chengyu gets one line of Chinese explanation under CC-CEDICT's English entry, and a **出处**
  button opens the source text, the story behind it, usage and examples. Chengyu CC-CEDICT
  lacks get an entry from them ([Chengyu](#chengyu)).
- **Pinyin pitched to your level, optional.** Choose how rare a character must be to get pinyin:
  outside the 1,500, 2,500, 3,500 (default), 5,000 or 7,000 most common characters in modern
  written Chinese. Common characters read in an unusual way (单 in 单于) get it too. The reading
  drawn is the one the popup marks (侥 is *jiǎo* in 侥幸, *yáo* in 僬侥).
- **What each character is made of.** Below a character's entry, one line per part gives its
  reading, a short gloss and whether it carries the meaning or the sound (清: 氵 *shuǐ* water → meaning,
  青 *qīng* → sound, same sound). A
  simplified character whose simplification hid a part shows its traditional form's parts (观:
  traditional 觀, 雚 *guàn* → sound; simplified: 雚 → 又).
- **Translate the sentence**: while Wi-Fi is on and connected, a button in the popup sends the
  whole sentence to [KOAssistant](https://github.com/zeeyado/koassistant.koplugin) if you have it
  (tested with KOAssistant 0.23.0), or to KOReader's built-in translator.
- **No per-book preprocessing**, and the book file is never modified.
- **Pinyin and popup are separate switches**: either one, or both.
- **Long-press and KOReader's own dictionary are untouched**, and each word in the popup has a
  button that looks it up there.

It merges two plugins that are no longer developed:
[koreader-interlinear-pinyin](https://github.com/scartoon/koreader-interlinear-pinyin) (the pinyin)
and [koreader-chinese-popup](https://github.com/scartoon/koreader-chinese-popup) (the popup). One
plugin means one tap handler, one popup for every character, and one database.

Status: **1.9.1**, tested on a Boox Go 7 (Android, 300 dpi) with KOReader v2026.07.1.

## Install

1. Download `chinesehelper.koplugin.zip` from the
   [latest release](https://github.com/scartoon/koreader-chinese-helper/releases/latest) and unzip
   it. You get a `chinesehelper.koplugin` folder, which includes the database
   (`data/chinesehelper.sqlite`, about 33 MB).
2. Copy that folder into KOReader's `plugins` folder:
   - **Android** (Boox and others): `/sdcard/koreader/plugins/`, which appears as
     `koreader/plugins` in the device's internal storage over USB. With adb:
     `adb push chinesehelper.koplugin /sdcard/koreader/plugins/`
   - Other devices: the `plugins` folder inside KOReader's own folder.
3. Restart KOReader.

The folder must keep its name, `chinesehelper.koplugin`. The repository does not contain the
database (see [Data](#data)); to install from a clone, build it first.

### Moving from the two old plugins

1. Delete `interlinearpinyin.koplugin` and `chinesepopup.koplugin` from KOReader's `plugins`
   folder, install this one, and restart KOReader.
2. That's all: on its first start the plugin copies your settings from both (pinyin on or off,
   the frequency threshold, pinyin size, uncertain readings, unusual readings, and whether the
   popup is on). Your old settings are left in place, and neither old plugin had per-book
   settings.

While either old plugin is still installed, Chinese helper shows a message asking you to remove
it: both listening for taps on Chinese characters means a tap can open the wrong popup.
"Tap annotated character for definitions" from the pinyin plugin has no successor: "Tap
characters for popup" now covers every character, annotated or not.

## Usage

Open a book (EPUB, FB2, MOBI, HTML, TXT and other reflowable formats), then **Tools (🔧) →
Chinese helper** (the entry may be on the second page of the Tools menu). Settings apply to
all books.

| Menu item | |
|---|---|
| Show pinyin above rare characters | On / off (off when first installed) |
| Tap characters for popup | On / off (on when first installed) |
| Which characters | Pinyin for characters outside the 1,500 / 2,500 / 3,500 / 5,000 / 7,000 most common (default 3,500) |
| Pinyin size | 35–55% of the book's text size (default 40%) |
| When the reading is uncertain | Show both readings (default) / show the most likely reading / don't annotate |
| Mark unusual readings of common characters (names, historical terms) | On (default) / off. See [Unusual readings](#unusual-readings-of-common-characters) |
| Edge pass-through width | 0 mm (off) / 2.5 mm / 5 mm (default) / 7.5 mm / 10 mm. See [The edge band](#the-edge-band) |
| Popup text size | 40 / 60 (default) / 80 / 100 / 120% of the book's text size |
| Fallback dictionaries | Source labels (all entries / "other dictionaries only", meaning the fallback dictionaries only, the default / none); then each dictionary on/off, in priority order: Wiktionary, CBDB office titles, MOE 重編國語辭典, Wikipedia titles, Moegirlpedia slang (CBDB, MOE and Moegirlpedia are marked "(your own file)" when installed, and greyed out with "(not installed)" when not). See [Fallback dictionaries](#fallback-dictionaries) |
| Status | Version, data versions and load times, each fallback dictionary (version, entries, on or off, or not installed), what the current page needed, and any old plugin still installed |

The two switches are independent: pinyin without the popup, the popup without pinyin, or both.

### What a tap does

- **A single tap on a Chinese character's glyph** (CJK Unified Ideographs, all extensions, and
  the compatibility ideographs), **or on the pinyin drawn above one**, opens the popup, unless
  it is within the edge band (below).
- **Every other tap is KOReader's as usual**: margins, the space between lines, blank space after
  a paragraph, punctuation, Latin text and digits turn the page or open the menus. Taps on links
  and on your highlights keep their usual behaviour.
- **Long-press and every other gesture are untouched**, so KOReader's long-press dictionary and
  text selection work as before.
- PDF and DjVu are not supported: there, every tap is KOReader's and no pinyin is drawn.

### The edge band

A single tap within a set distance of any edge of the screen always goes to KOReader (page turn,
menus, corner actions), even when it lands on a Chinese character or on pinyin. That keeps page
turns reliable when the text runs close to the edges, for example with small page margins.

Set the width with **Edge pass-through width**:

| Choice | Band on a 300 dpi screen | |
|---|---|---|
| 0 mm (off) | none | Only taps that miss a character go to KOReader. |
| 2.5 mm | 30 px | |
| 5 mm (default) | 59 px | |
| 7.5 mm | 89 px | |
| 10 mm | 118 px | |

- The band runs along all four edges, measured from the screen's edges as it is currently held,
  so it follows rotation.
- Millimetres are converted with the screen DPI KOReader reports (shown under **Status**), so
  the band is the same physical size on any device; a screen that reports no DPI is taken as
  300 dpi.
- A change applies to the next tap; no restart is needed.
- KOReader's own menu and corner tap zones reach further than the band (the top and bottom
  menus cover an eighth of the screen height, a fifth across the middle half). Inside those zones
  but outside the band, a tap on a character opens the popup rather than KOReader's menu; tap
  in the band, or on blank space, punctuation or a margin, to open the menus.

### The popup

The plugin reads up to 7 Chinese characters before and after the tapped one (stopping at
punctuation, a paragraph break or any non-Chinese character) and looks up every 1–8 character
stretch containing the tapped character, against both simplified and traditional forms.

- **The tapped character first**, with all its readings. The reading it has here comes first,
  marked **· shown above** when its pinyin is drawn, or **· likely here** when not. When nothing
  decides between a character's two likely readings (see [Readings](#readings)), both are
  marked **· one of these**, the likelier first.
- **Then every dictionary word containing it**, longest first; words of the same length in
  reading order. A word with several readings (东西 *dōngxī* "east and west" / *dōngxi*
  "thing") has the likely one marked and first.
- **The word that decides the reading** is tagged **· decides X's reading**, also when
  CC-CEDICT does not have it (a word from pypinyin's phrase list, or an unusual-reading word
  with a short note, such as 冒顿 *mò dú*).
- **The character's components** (below), indented under its own entry.
- **Buttons**: one per entry, labelled with the character or word, which opens KOReader's
  dictionary lookup for it; **出处** for a chengyu (see [Chengyu](#chengyu)); and **Close**.
  Every button is the character, a word from the text containing it, or one of those two.
  Tapping outside the popup also closes it.
- **Translate the sentence**: a full-width button on its own row below them, shown only while
  Wi-Fi is on and connected (see below).
- Words CC-CEDICT does not have can come from the fallback dictionaries (below). If no dictionary has
  the character or any word around it, the tap goes straight to KOReader's dictionary lookup.

### Character components

Every single-character popup shows what the character is made of, one line per part, below the
character's own entry:

```
髡 kūn   scalping; to make the head bald
   髟 biāo  hair; shaggy  → meaning
   兀 wù  (literary) rising to a height  → sound (loose)
```

- **Each part** shows its form as written in the character, its modern reading, a short gloss
  and its role. Radical forms are looked up as their full character, with the common name:
  氵 *shuǐ* water (三点水), 钅 *jīn* metal (金字旁), 艹 *cǎo* (草字头). 阝 is 阜 on the left
  (左耳旁: 陈, 阿) and 邑 on the right (右耳旁: 郎, 都).
- **Sound parts** say how well they still match the character's reading: **same sound** (same
  syllable, tone aside: 茴 *huí* / 回 *huí*), **same ending** (same final, medial aside: 郎
  *láng* / 良 *liáng*), or **loose** (髡 *kūn* / 兀 *wù*: the sounds have drifted apart since
  the character was made). Among characters outside the 2,500 most common whose analysis
  names a sound part, about 56% are same sound, 20% same ending and 23% loose.
- **Ideogrammic compounds** (Wiktionary's) mark every part → meaning (武: 戈 + 止). A
  **pictogram** or **indicative** character says so (象形, 指事).
- **Simplified characters** whose simplification hid a part show the traditional form's
  analysis, then the parts replaced:

  ```
  观 guān  to look at; to watch
     traditional 觀:
     雚 guàn  (archaic) stork; heron  → sound (same sound)
     見 jiàn  see  → meaning
     simplified: 雚 → 又
  ```

  Where the simplification only writes the same parts the simplified way (铳 from 銃: 金 → 钅;
  陈 from 陳: 東 → 东), the simplified forms are shown, with the traditional form's roles. A
  character with several traditional forms (发: 發 and 髮) takes the traditional form of the
  word it was tapped in, as CC-CEDICT gives it (头发 頭髮: 髮; 发现 發現: 發). With no such word, it
  shows its own parts, if any.
- **Sources**, in this order, labelled like the dictionaries:
  - **Wikt**: English Wiktionary's analysis (its `Han compound` template; bundled, CC BY-SA
    4.0). Where Wiktionary records more than one analysis (造, 何, 秋), the first is shown. Some
    analyses describe an older form of the character than the one written today (期: semantic
    日, from the variant 㫷).
  - **MMAH**: [Make Me a Hanzi](https://github.com/skishore/makemeahanzi) (bundled, LGPL v3),
    for characters Wiktionary does not analyse. Its learner mnemonics are never shown (they
    are wrong for many simplified characters: 观 "to see 见 again 又"), and where a
    simplification hid a part, its roles are dropped and only the parts shown. Its
    "ideographic" label is often wrong, so those parts get no role, unless its note names the
    sound part (钺: 戉 *yuè*).
  - **IDS**: [yi-bai/ids](https://github.com/yi-bai/ids) (bundled, MIT): the structure alone,
    no roles, for characters neither has (龘: 龍 + 龖).
- **Readings and glosses** of the parts come from CC-CEDICT (simplified and traditional forms),
  except that Wiktionary's gloss of the sense a part contributes is used when it gives one
  (見 "see", not every sense of 見). A sound part takes the reading that best matches the
  character (雚 is *guàn* "stork", the sense behind 觀, not its default *huán*).
- **Nothing undisplayable**: an analysis containing a character outside Unicode's Basic
  Multilingual Plane is skipped (KOReader's fonts would draw an empty box), and the next
  source's is used (秋: Wiktionary's semantic 禾 + abbreviated phonetic 𤒅 is skipped; Make Me a
  Hanzi's 禾 + 火 is shown).
- Coverage of the characters in the frequency list (no analysis: 4–8% per band, mostly
  characters whose only analyses contain such characters):

  | Most common | Wikt | MMAH | IDS (structure) | None |
  |---|---|---|---|---|
  | 1–2,500 | 79% | 12% | 5% | 4% |
  | 2,501–3,500 | 66% | 23% | 6% | 5% |
  | 3,501–5,000 | 50% | 36% | 9% | 5% |
  | 5,001–7,000 | 30% | 40% | 23% | 7% |
  | beyond 7,000 | 17% | 18% | 56% | 8% |

- **Show character components** in the menu turns the block off.

### Translating the sentence

While Wi-Fi is on and connected, the popup has one more button on a row of its own. It closes
the popup and sends **the whole sentence containing the tapped character**:

- **With [KOAssistant](https://github.com/zeeyado/koassistant.koplugin) installed** (tested with
  KOAssistant 0.23.0; the button uses its internals, so a later version may fall back to the
  built-in translator), the button
  reads **Translate & Analyze** and runs the sentence through KOAssistant with a built-in prompt:
  a natural English translation, then a chunk-by-chunk analysis (characters, pinyin with tone
  marks, a literal gloss and the grammatical role), then any construction that governs the
  sentence. The sentence goes to KOAssistant as a selection, exactly as if you had selected it
  and run an action from the highlight menu, so KOAssistant also gets its surrounding context,
  your provider and model, and the book's title. The prompt is part of this plugin, a **snapshot**
  of the author's own KOAssistant custom action "Translate & Analyze" (system prompt,
  temperature 0.3, up to 2000 tokens): it works without that custom action, and editing a
  custom action of your own does not change this button. Nothing is written to KOAssistant's
  settings or files.
- **Without KOAssistant** (or with a version whose internals have changed), the button reads
  **Translate** and uses **KOReader's built-in translator**, the same as Translate in the
  highlight menu, with its usual window. KOReader translates from the book's language when
  "Translate from book language" is on: a Chinese book whose metadata says English (common with
  converted EPUBs) comes back untranslated. Fix the book's language in Book information
  (zh-CN), or turn that option off.

The label is decided when the popup opens, so it always says what the button will do. Without
Wi-Fi (off, or on but not connected) the row is left out altogether. The check reads KOReader's
network state only, with no lookup or request, so the popup opens as fast as before; a
connection lost after the popup opens is left to KOReader or KOAssistant.

**The sentence** is found in the book's text, not on the lines on screen, and crosses pages:
forward to the next 。！？ (or . ! ? in Latin text, when followed by a space or the end), with
any closing quotes or brackets right after it (。” ？」 ！』); backward to just after the
previous one, or to the start of the paragraph. A paragraph with no end mark is taken whole.
At most **200 characters** go out: a longer sentence is kept to 200 around the tapped
character (centred, or shifted when it is near one end), each cut end moved inward to a
clause mark (，；：) when there is one close by. Nothing is highlighted in the book.

### Fallback dictionaries

For words CC-CEDICT does not have, the popup also looks in the fallback dictionaries. Two are part
of the plugin:

- **Wiktionary**: about 61,000 words, many of them historical and literary terms, chengyu,
  technical terms and some slang.
- **Wikipedia titles**: about 39,000 Chinese Wikipedia article titles of 3–8 characters in
  technology, engineering, military and history (红夷大炮 *Hongyipao*, 火绳枪 *Matchlock*,
  鱼鳞册 *Fish-Scale Registers*), glossed with the English article's title. Many are proper
  names, which tell you what a transliterated or translated name refers to: places (亨特冰川
  *Hunt Glacier*), observatories and museums (翁德热约夫天文台 *Ondřejov Observatory*),
  organisations (斐济足球协会 *Fiji Football Association*) and works (恋爱的滋味 *Taste of
  Love (South Korean TV series)*).

Five more are files you build and install yourself, because their licences do not allow this
project to distribute them (see [Data](#optional-dictionaries-you-build-yourself)):

- **CBDB office titles**: about 2,900 Ming and Southern Ming office titles with English
  translations (典史 *Clerk / District Jailor*, 巡按御史 *Regional Inspector*).
- **MOE 重編國語辭典**: about 90,000 entries, monolingual, strong on historical and literary
  vocabulary, its definitions in simplified characters.
- **MOE 成語典**: the Taiwan Ministry of Education's idiom dictionary, about 5,500 chengyu with
  source texts, notes, stories, citations and usage (see [Chengyu](#chengyu)).
- **Xinhua idioms**: about 30,000 chengyu and set phrases with explanation, classical source
  and an example.
- **Moegirlpedia slang**: about 350 internet-slang terms from 萌娘百科, each with its opening
  sentence or two in Chinese (问题不大, 王八之气, 大杀器).

CC-CEDICT always comes first: a word it has never gets an entry from a fallback dictionary. After
it, each word shows the entry of the first fallback dictionary that has it, in this order: Wiktionary,
CBDB, MOE, 成語典, Xinhua, Wikipedia titles, Moegirlpedia. (CBDB's narrow office titles beat MOE's general
definitions; an English article title is a label rather than a definition, so it comes after
the real dictionaries; Moegirlpedia is only for words nothing else has.) The order is the
`chinesehelper_fallback_order` setting in KOReader's `settings.reader.lua`, which you can edit
while KOReader is closed (e.g. `"moe,wikt"`: dictionaries left out keep their default place
after those named).

- An entry from a fallback dictionary shows that dictionary's own reading (MOE's are Taiwan
  standard; CBDB's have no tone marks) and is never marked *shown above* or *likely here*: those
  markers come from the reading resolver and appear on CC-CEDICT entries only, so the popup and
  the pinyin always agree. Wikipedia and Moegirlpedia give no readings: the popup shows one
  generated with pypinyin, marked *generated pinyin*. A word that decides the reading but is
  missing from CC-CEDICT shows the fallback dictionary's definition, still tagged *decides X's
  reading*.
- A Wiktionary word can decide a reading in one case: the character's reading is uncertain
  and nothing else decides it (see [Readings](#readings)), as 累世 does for 累 in 累世公卿.
  The other fallback dictionaries' words never decide readings.
- A small grey line above an entry names its dictionary: **CEDICT**, **Wikt**, **CBDB**,
  **MOE**, **成语典**, **新华**, **WP** or **Moegirl**. By default only entries from the fallback dictionaries are
  labelled; **Source labels** can label every entry or none.
- Each fallback dictionary can be switched off under **Fallback dictionaries**; with all of them off the
  popup shows CC-CEDICT alone, as before. **Status** lists each dictionary's version and size, or
  that it is not installed.

### Chengyu

With the optional **MOE 成語典** or **Xinhua idioms** file installed (see
[Data](#optional-dictionaries-you-build-yourself)), a chengyu in the popup gets more than
CC-CEDICT's English gloss:

- **One line of Chinese explanation** under CC-CEDICT's (or Wiktionary's) entry, with its own
  small label: 一毛不拔 → *形容人非常吝啬。贬义。* (成语典). It is the 成語典's meaning when it has
  the idiom, otherwise Xinhua's explanation. Entries already in Chinese (MOE, the idiom files
  themselves) get no extra line.
- **A 出处 button** opens a full-screen view. From the 成語典: 释义, the 典源 passage with its
  notes, 典故说明 (the story retold in modern Chinese), 书证 (later citations), usage and example
  sentences, 辨识 and near and opposite idioms. A related form (玉石俱碎) shows its own
  explanation and citations, then its main idiom's source text and story, headed with that
  idiom's name (典源（玉石俱焚）). From Xinhua: the explanation, the classical source quoted, and
  an example with its source. The 成語典 comes first when both have the idiom; with several
  idioms in one popup, each button is named (首鼠两端 出处). No button appears when there is
  nothing beyond the one line.
- **Chengyu CC-CEDICT lacks** (精兵强将, 科班出身, 十二万分) get an entry from these files, in
  the fallback order above.

Both are converted to simplified characters if needed (the 成語典 with
[`tools/simplify.py`](#simplified-text)); their readings appear only on their own entries and never
decide the pinyin drawn. Measured with `tools/measure_chengyu.py` on the 46 Chinese books on the
test device (202,036 chengyu occurrences) and on 临高启明 (38,398):

| Popup | 46 books | 临高启明 |
|---|---|---|
| an entry, release only (CC-CEDICT, Wiktionary) | 93.2% | 93.7% |
| an entry, with the MOE file | 97.3% | 97.7% |
| an entry, with MOE, 成語典 and Xinhua | 100% | 100% |
| a Chinese short line | 94.7% | 94.6% |
| a 出处 view | 92.4% | 92.3% |
| a 出处 view from the 成語典 | 30.3% | 28.9% |

(Here a chengyu is any headword CC-CEDICT tags *idiom* or either file lists, so "100%" only
means the two files cover their own lists; the gain is the 1,282 idioms, 5,397 occurrences,
that had no entry even with MOE, such as 精兵强将, 受制于人, 由来已久.)

The popup is the full width of the screen (minus a small margin) and as tall as its content,
up to the full screen height, scrolling beyond that. A short popup goes in the half of the
screen away from the tapped character, so the text stays visible. A taller one starts with the
phrase around the character, the character in bold:

![A tall popup over a page of 阿Q正传: the phrase 而且又不见了观音娘娘座前的一 at the top with 观 in bold, then 观 guān · likely here, its traditional form 觀's parts, and 观音 Guānyīn · decides 观's reading](docs/traditional.png)

### Readings

Readings are dictionary readings: 一 is *yī* and 不 is *bù* everywhere, as in CC-CEDICT, without
the spoken tone changes (一定 *yídìng*, 不是 *búshì*). Neutral tones follow the standard mainland
spoken form: where CC-CEDICT gives a word's syllable only as a neutral tone, that is what is drawn
above a rare character (刺猬 *cì wei*, 鼓捣 *gǔ dao*, 疙瘩 *gē da*, 大猩猩 *dà xīng xing*), even
where pypinyin writes a full tone. Where CC-CEDICT lists the word both ways (大爷 *dà yé* "idler" /
*dà ye* "uncle", 裁缝 *cái féng* / *cái feng*), the toned reading is drawn and the popup marks the
neutral one. Tapping a character drawn with a neutral tone marks its entry with the same letters
(猬 *wèi*) and tags the word that decided it.

For each character, in order: an unusual reading in a listed name or term (单于 *chán yú*), if
that option is on; the longest dictionary word of 2–4 characters around it (侥 is *jiǎo* in 侥幸
but *yáo* in 僬侥; when two words overlap, the more common one; longer words in the popup, up to
8 characters, do not decide readings); a context rule for the character next to it
(about 950, learned from labelled sentences); its most frequent reading. Particles take their
neutral reading by default (吧 *ba*, 啦 *la*, 得 *de*), since their toned readings live in words
(酒吧 *jiǔbā*, 啦啦队, 得到 *dédào*). For the about 530
characters whose most frequent reading is unreliable, a Wiktionary word around it (one CC-CEDICT
lacks) can pick one of the two likeliest readings, while that dictionary is on; Wiktionary words
decide nothing else, since letting them override rules or reliable defaults broke more readings
than it fixed. Characters whose reading stays uncertain show both likely readings, or the most
likely, or none (the menu). An estimate puts about 99.7% of the pinyin drawn in ordinary text
right at the default setting: it is worked out from held-out labelled Wikipedia sentences,
weighted by how often each character occurs, and counts a pair as right when either reading is;
see [Accuracy](#accuracy).

What is drawn on a page:

- A character gets pinyin only the first time it appears on the page with a given reading: later
  repeats are left bare, but a repeat with a different reading (刨 *páo* in 刨根, then *bào* in
  刨子) is annotated again.
- When a line is too crowded for all its pinyin to fit, the pinyin of the line's most common
  annotated character is dropped first, and so on until the rest fit; the rarest are kept.

The popup's markers use the same resolver on the same page, for every character, common ones
included (的 is *dí* in 的确, *de* or *dì* on its own; 行 is *háng* in 银行, *xíng* in 行人). On
held-out labelled sentences built around the 1,000 most common characters' hard cases (those with
several readings), the marked reading is right 97.5% of the time (98.2% counting both of an
uncertain pair).
Some word-level choices need the meaning, which the plugin does not have: 东西 is always marked
*dōngxi* ("thing"), also where it means "east and west".

### Accuracy

`tools/eval_readings.py` runs the plugin's own resolver over the test split of the
[CPP polyphone dataset](https://github.com/kakaobrain/g2pM) (labelled sentences from Chinese
Wikipedia; the context rules are learned from its train split only). CPP holds only characters
with several readings, so it is the hard case. Figures for 1.6.1 (since 1.6.0, a
CPP label with a neutral tone that CC-CEDICT lists as an entry of its own, such as 啦 *la*, no
longer counts as the toned reading with the same letters). 1.6.1 draws a word's neutral tone
where CC-CEDICT gives it only that way, and CPP labels some of these words with the full tone
(枇杷 *pá*, 姥姥 *lǎo*, 收拾 *shí*, 铃铛 *dāng*, 唠叨 *dāo*): 22 test sentences that counted as right
now count as wrong, 0.4 to 0.7 points of the "most likely" figures and 0.04 to 0.08 points of
the ordinary-text estimate.

| Pinyin for characters outside | Characters tested | Most likely reading right | Right counting both of a pair | Shown as a pair | Estimated, ordinary text (both shown) |
|---|---|---|---|---|---|
| 1,500 most common | 5,353 | 95.9% | 97.6% | 7.2% | 99.56% |
| 2,500 | 3,189 | 96.2% | 97.8% | 8.0% | 99.61% |
| 3,500 (default) | 1,482 | 96.0% | 97.6% | 10.7% | 99.67% |
| 5,000 | 260 | 95.4% | 98.8% | 28.8% | 99.84% |
| 7,000 | 42 | 97.6% | 100.0% | 45.2% | 100.00% |

The last column weights every character the plugin would draw by how often it occurs in ordinary
text (wordfreq), counting characters with a single reading as right; CPP over-represents
minority readings, so the estimate leans pessimistic. It is an estimate from Wikipedia
sentences, not a count on books. The popup's markers on the 1,000 most common characters (3,687
test examples): 97.5% right, 98.2% counting both of a pair. Unusual
readings (单于 *chán yú*) agree with CPP's label in 25 of the 36 test sentences that contain one;
8 of the 11 others are the place name 黄陂, *Huángpí*, which CPP labels *bēi*. This measurement continues the one
published with [koreader-interlinear-pinyin](https://github.com/scartoon/koreader-interlinear-pinyin#accuracy),
this plugin's predecessor, on the same split.

**Coverage on one book.** The fallback dictionaries were tuned with one book in mind, 临高启明,
per the plugin author's latest reading interests. It is still a general-purpose plugin: nothing in
it is specific to that novel, and the sources it added (Wikipedia titles, CBDB office titles,
Moegirlpedia slang) help with history, technical writing and internet fiction generally. 临高启明
was a demanding test because it mixes Ming dynasty officialdom, early-industrial technical
vocabulary and 2010s internet and forum slang. `tools/measure_book.py` split the book into words
with jieba (its big dictionary, no HMM) plus the words it discovered in the book itself (frequent,
cohesive character sequences such as 元老院 and 归化民, which jieba alone would break up), then
simulated 8,000 taps on random characters. 81% landed in a word or character the dictionaries
have, and another 11.5% in an everyday combination of such words (很多, 连连点头). Most of the
remaining 7.5% are the novel's character names and its own coinages (髡贼, 归化民), which no
dictionary has. Ming forms of address and technical compounds are covered only in part (典史 and
红夷大炮 are in; 赵老爷 and 米尼步枪 are not).

### Line spacing

The pinyin goes in the space between lines, so while it is on the plugin sets a line height that
leaves room for it, taking KOReader's line-spacing setting into account. Turning it off restores
the book's own spacing (KOReader lays the book out again, which takes a moment).

![The 临江仙 and the start of 第一回 with pinyin off (top) and on (bottom): the same lines, a little further apart with pinyin on, and qiáo over 樵 and zhǔ over 渚](docs/off-on.png)

Books with tight spacing get more pages; books that already set generous spacing can end up with
tighter lines, because the plugin replaces the book's line height rather than adding to it.

### Unusual readings of common characters

Common characters are never annotated, but some take a rare reading in particular words, mostly
historical names, titles and places: 单于 *chán yú*, 冒顿 *mò dú*, 龟兹 *qiū cí*, 尉迟 *yù chí*,
番禺 *pān yú*. With **Mark unusual readings of common characters** on, the plugin knows about
200 such words (65 hand-checked) and draws, in bold, only the characters whose reading there
differs from their usual one. A guard keeps them from matching by accident: 订单于3日发货 is
订单 + 于, not 单于.

## Speed

Measured on a Boox Go 7 against the two old plugins, same book, same pages:

- **Page turns**: the pinyin for a page takes 13.4 ms on average to work out, against
  koreader-interlinear-pinyin 0.5.0's 13.7 ms; the pages drawn were pixel-for-pixel the same
  until 1.4.0's Wiktionary readings. The words a page can need are read into memory with the
  other reading tables when the first page is drawn (about 230 ms, once per KOReader session;
  0.5.0 took 190–270 ms to read its text files). After that, the only query a page can make is
  one Wiktionary lookup, and only when an uncertain rare character on it is left undecided
  (results are cached).
- **A tap**: from the tap to the popup built, 14.7 ms median (16.9 ms mean) with Wiktionary and
  the MOE dictionary, against 13.8 ms (16.6 ms) without them: one query to CC-CEDICT, then one to
  each fallback dictionary for the words CC-CEDICT does not have. The first tap after opening a book
  takes 20–30 ms either way; the MOE file opens on the first tap, in 1–3 ms. Memory: about
  2 MB more (KOReader's total about 133 MB against 131 MB); the dictionaries are read from the
  database, not loaded into memory.
- **A tap with all five fallback dictionaries** (1.5.0 adds Wikipedia titles, CBDB and
  Moegirlpedia): 17–20 ms median (18–29 ms mean) against 14–15 ms (about 15.5 ms mean) with
  Wiktionary and MOE alone, timed on the Go 7 over the same 31 taps, two runs of each, with the
  Translate button showing. Each extra dictionary adds at most one indexed query per tap, and
  none once every candidate word has an entry. The first run after installing had five taps of
  70–85 ms that did not come back in the second, most likely the new database being read from
  storage for the first time. CBDB and Moegirlpedia, like MOE, are opened when first needed.
- **The Translate button**: the Wi-Fi check and the choice of mode take 1–2 ms when the popup
  opens (popup built in 9–15 ms against 7–10 ms without the button, same character). The
  sentence is found when the button is pressed, in 2–3 ms.

## Data

Everything is in one SQLite database, `chinesehelper.koplugin/data/chinesehelper.sqlite` (about
36 MB):

- **CC-CEDICT** (`entries`): the popup's dictionary.
- **Fallback dictionaries** (`fallback`): entries from English **Wiktionary** for words CC-CEDICT
  does not have (about 61,000 headwords: historical and literary terms, chengyu, technical terms,
  some slang), and **Chinese Wikipedia titles** (about 39,000: articles of 3–8 characters with an
  English article, in a technology, engineering, military or history category). Left out: people,
  lists and disambiguation pages, and articles filed under some kinds of place, organisation and
  work (towns, counties, rivers, peaks, islands, stations, airports, roads, railways, schools,
  universities, companies, sports teams, films, TV dramas, albums, songs, novels, games, anime
  and manga) or under living things and chemical compounds. Only those categories are checked,
  so many places, organisations and works remain (glaciers, capes, observatories, museums,
  associations, political parties, ministries, TV series, books, ships), as do some compounds
  (麦草畏 *Dicamba*). CC-CEDICT always wins: there is no fallback row for any headword CC-CEDICT has, in
  either script. Only what the popup can match is kept (headwords of 1–8 Chinese characters with a
  Mandarin reading), and everyday combinations that CC-CEDICT leaves out on purpose are filtered
  out (很多, 这次, 一天, 脸上: a closed-class word such as a numeral, measure word, adverb, locative
  or particle next to a word CC-CEDICT has), as are numerals and Wiktionary entries that only
  name places.
- **Character components** (`components`, `component_notes`): about 13,400 characters' parts,
  roles, readings, glosses and sound labels, built once from Wiktionary, Make Me a Hanzi and
  yi-bai/ids (see [Character components](#character-components)), and Wiktionary's origin texts
  (1.1 MB of text, shown by the popup until 1.9.0; no longer used). About 2.9 MB.
- **The reading tables** (every character's frequency rank and default reading, words, context
  rules, uncertain characters, unusual readings). The fallback dictionaries never feed these: the
  build records a checksum of them, which is the same with and without the fallback table. (At
  run time, Wiktionary's words can settle an uncertain character; see [Readings](#readings).)

The popup's lookups use indexes on the simplified and traditional forms; the build checks with
`EXPLAIN QUERY PLAN` that every lookup query uses its index.

### Optional dictionaries you build yourself

Five more fallback dictionaries can be added, each as a separate file. Their licences allow
copying them for your own use but not this project's distributing them, so none is in the
repository or the release: you build the files yourself and copy them to your device. The plugin
works the same without them, and opens each only if it is there. Build the plugin database first
(or use the one from the release zip): headwords CC-CEDICT has are left out of these files too.
(The 成語典 and Xinhua scripts take the database from the latest release when you have none.)

```sh
.venv/bin/pip install opencc pypinyin
.venv/bin/python tools/build_moe.py              # -> build/chinesehelper-moe.sqlite (about 17 MB)
.venv/bin/python tools/build_cbdb.py             # -> build/chinesehelper-cbdb.sqlite (about 0.5 MB)
.venv/bin/python tools/build_idioms.py           # -> build/chinesehelper-idioms.sqlite (about 22 MB)
.venv/bin/python tools/build_xinhua.py           # -> build/chinesehelper-xinhua.sqlite (about 15 MB)
.venv/bin/python tools/build_moegirl.py          # -> build/chinesehelper-moegirl.sqlite (about 0.1 MB)
# add --push to any of them to copy the file to a USB-connected Android device (adb)
```

They go in KOReader's data folder, where plugin updates leave them alone:
`koreader/data/chinesehelper/` (on Android: `/sdcard/koreader/data/chinesehelper/`).

- **MOE 重編國語辭典**: the Taiwan Ministry of Education's
  [《重編國語辭典修訂本》](https://dict.revised.moe.edu.tw/) (about 160,000 entries, monolingual),
  from [g0v/moedict-data](https://github.com/g0v/moedict-data) (downloaded, 7 MB). Licence:
  [CC BY-ND 3.0 TW](https://creativecommons.org/licenses/by-nd/3.0/tw/). Its headwords are
  traditional, also indexed under their simplified form (OpenCC `tw2s`, characters only); its
  readings are Taiwan standard and stay inside its own entries. Its definitions are converted
  to simplified characters (since 1.8.0; see [Simplified text](#simplified-text)); to keep MOE's
  own traditional text, build it with `tools/build_moe.py --traditional`. **Status** says which
  your file has (a file built before 1.8.0 has traditional text: rebuild it to get simplified).
- **CBDB office titles**: the Ming and Southern Ming office titles of the
  [China Biographical Database (CBDB)](https://cbdb.hsites.harvard.edu/), with CBDB's English
  translations ("office title (Ming)" where CBDB has none yet) and its toneless readings, from
  CBDB's [SQLite release](https://huggingface.co/datasets/cbdb/cbdb-sqlite) (downloaded, about
  110 MB zipped, 590 MB unzipped). Licence: the
  [CBDB Data Licensing Terms](https://cbdb.hsites.harvard.edu/cbdb-data-licensing-terms)
  ([CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) for the data of the
  standalone release, CBDB's own non-commercial, no-derivatives, no-redistribution terms beyond
it). This project
  follows the stricter of the two: it ships only the build script, never CBDB data, and the file
  is meant for your own non-commercial reading on your own device. Don't share it.
- **MOE 成語典**: the Taiwan Ministry of Education's
  [《成語典》](https://dict.idioms.moe.edu.tw/) (5,489 entries: 1,664 main entries with every
  field and about 3,800 related forms), downloaded from the ministry's
  [download page](https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_idiomsdict_download.html)
  (an .xlsx in a 5 MB zip; the script finds the current file there). Licence:
  [CC BY-ND 3.0 TW](https://creativecommons.org/licenses/by-nd/3.0/tw/). Text converted to
  simplified characters (`--traditional` keeps the original). One command, from a fresh clone,
  with the Boox connected over USB (leave out `--push` to only build the file):

  ```sh
  python3 -m venv .venv && .venv/bin/pip install opencc && .venv/bin/python tools/build_idioms.py --push
  ```
- **Xinhua idioms**: `data/idiom.json` of
  [chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua) (30,895 idioms; 30,212 kept: the
  ones of 4–8 Chinese characters, since the popup's context stops at punctuation). The
  repository's MIT licence covers its code; the text was scraped from a published dictionary,
  so it is build-it-yourself too. The scraping lost punctuation; the build puts back what can be
  put back reliably (the colon after a glossed word, 首鼠鼠性多疑 → 首鼠：鼠性多疑; the colon and
  quotes after a source's title; ◇ and ★ markers) and shows symbols that stand for lost text as
  …; typos stay. One command, as above:

  ```sh
  python3 -m venv .venv && .venv/bin/pip install opencc && .venv/bin/python tools/build_xinhua.py --push
  ```
- **Moegirlpedia slang**: the internet-slang pages of [萌娘百科](https://zh.moegirl.org.cn) (the
  page's opening sentence or two, with 黑幕 and struck-through text removed; a hand-checked list
  of characters, works and plain words left out), from the offline snapshot
  [zhmoegirl-20230507-alpha.slob](https://github.com/aisuneko/dicts_for_aard2/releases/tag/moegirl-alpha)
  (1.4 GB, downloaded; listed on the [slob project's dictionary page](https://github.com/itkach/slob/wiki/Other-projects)).
  Licence: [CC BY-NC-SA 3.0 CN](https://creativecommons.org/licenses/by-nc-sa/3.0/cn/). Reading
  it needs the slob reader, which needs ICU:
  `brew install icu4c pkg-config`, then
  `PKG_CONFIG_PATH=$(brew --prefix icu4c)/lib/pkgconfig .venv/bin/pip install git+https://github.com/itkach/slob.git`.
  Reading every page takes 10–15 minutes.

The glosses of the newer sources (Wikipedia, CBDB, Moegirlpedia) are cleaned of characters
KOReader's fonts may not draw: emoji, kaomoji, decorative symbols and scripts other than Latin
and CJK (Greek letters are spelt out: α → alpha).

### Simplified text

The explanatory text of every dictionary is in simplified characters. It is converted at build
time by `tools/simplify.py`: OpenCC `tw2s` for MOE (Taiwan standard) and `t2s` for Wiktionary,
character by character (not `tw2sp`, which also swaps vocabulary, 滑鼠 → 鼠标, and would rewrite
classical quotations). On top of OpenCC:

- **著 meaning "to write" stays 著**: OpenCC writes 着 in 著有, 所著, 撰著, 原著, 土著, 卓著, 著《…》
  and a book's author (书名。清王国维著。). In MOE, 613 definitions keep 著 this way; 着 as the
  aspect particle (低着头) is converted as before. 徵 the musical note stays 徵 (宫、商、角、徵、羽).
- **One character quoted in 「」 stays as written** (优恤: 「恤」文献异作「卹」): the form is the
  point. Longer quotations are converted.
- **A character whose simplified form the device fonts lack stays traditional** (九针: 鍉针, not
  𫔂针): OpenCC's simplified forms of some rare characters are outside the BMP and would be drawn as
  boxes.
- **Wiktionary's "traditional／simplified" pairs** are shortened to the simplified side (鹊渚:
  synonym of 鹊洲), a single character named as a form stays as written (苍铅: variant of 鉍), and Japanese is left alone.
- **CC-CEDICT** cross-references show the simplified form, as before (`variant of 够 gòu`), now
  including forms with digits or Latin letters (`95后`, `B型超声`).
- CBDB's glosses are English, Wikipedia's are English article titles, and Moegirlpedia's text is
  already simplified (the few traditional-looking characters in it are Japanese), so they are
  not converted.

Headwords and readings are not converted: the reading tables have the same checksum as before,
and MOE's headwords and readings are identical with and without the conversion.

The database changes completely with each CC-CEDICT update, so it is **not committed** (every
rebuild would add another 33 MB of binary history); it is attached to each GitHub release inside
the ready-to-install zip. The small hand-made and learned inputs it is built from are in
[`data/`](data/README.md).

To rebuild it (Python 3):

```sh
python3 -m venv .venv && .venv/bin/pip install wordfreq==3.1.1 pypinyin==0.55.0 lupa opencc
.venv/bin/python tools/build_db.py                 # downloads the current CC-CEDICT
.venv/bin/python tools/build_db.py --cedict build/cedict_1_0_ts_utf-8_mdbg.txt.gz   # or a local copy
.venv/bin/python tools/build_db.py --learn         # also re-learn the context rules (downloads the CPP dataset)
.venv/bin/python tools/build_db.py --no-wiktionary # without the Wiktionary fallback rows
.venv/bin/python tools/build_db.py --no-wikipedia  # without the Wikipedia title rows
```

The Wiktionary data (kaikki.org's extraction, about 160 MB) and the five Chinese Wikipedia SQL
dumps the titles come from (about 1.1 GB; parsing them takes a few minutes) are downloaded into
`build/sources/` when missing; the build records the dump dates, and the checksums of the other
sources, in the database's `meta` table.

The release ships CC-CEDICT dated 2026-11-09 (125,397 entries), Wiktionary as of the 2026-10-01
dump (kaikki.org extraction of 2026-10-30) and Chinese Wikipedia as of the 2026-11-01 dump;
[`data/README.md`](data/README.md) lists every source's version.

To see what fallback dictionaries add on your own books: `tools/fetch_books.py` (copies the EPUBs
from a USB-connected device into `build/`), `tools/download_sources.sh`, then
`tools/measure_fallback.py` (reports in `build/measure/`). For one book on this computer:
`tools/fetch_books.py --local NAME BOOK.epub` (or a zip of EPUBs), then
`tools/measure_fallback.py --book NAME` and `tools/measure_book.py --book NAME` (what that book still
lacks after every current dictionary, and what candidate sources would add).

## Development

```sh
tools/check.sh                  # luac -p and luajit -b on every Lua file, then the tests
tools/deploy.sh "/sdcard/Books/book.epub"   # check, push to a USB-connected Android device, restart KOReader
.venv/bin/python tools/eval_readings.py     # reading accuracy on the CPP test split (--fallback none: without Wiktionary's words)
.venv/bin/python tools/scan_special.py BOOK.epub   # the unusual readings a book gets
.venv/bin/python tools/make_test_epub.py build/chinesehelper-test.epub   # a book for tap tests on a device
.venv/bin/python tools/make_sample_epub.py  # the sample books in samples/
.venv/bin/python tools/make_screenshots.py  # the README screenshots, over adb (see below)
```

### The sample book

`samples/xiaoshuo.epub` (小说三篇) holds 《三国演义》 第一回 (the 毛宗岗 edition, which opens
with 杨慎's 临江仙), and 鲁迅's 《孔乙己》 (1919) and 《阿Q正传》 (1921), all in the public
domain. `tools/make_sample_epub.py` builds it from Chinese Wikisource (pinned revisions),
converted to simplified characters with `tools/simplify.py`; the 1938 《鲁迅全集》 text's old
glyph variants (偸, 淸, 鎗) become the standard forms and its corner quotes “”. It also
rebuilds `samples/guwen.epub` (桃花源记, 陋室铭, 爱莲说).

### Screenshots

`tools/make_screenshots.py` regenerates every image in this README on a Boox Go 7 over adb:
it opens the sample book at fixed pages with fixed reader settings, taps, and saves cropped
16-grey PNGs to `docs/`. Before an image is saved, the page's exact text goes through the
plugin's own Lua code (`tools/shot_gate.py`, with every dictionary): the pinyin drawn must be
the shot's hand-checked list, each popup must show the expected lines, and KOReader's log must
agree (the number of characters annotated, and each tap's context and reading). Your
`settings.reader.lua` is backed up and restored.

The tests (`tests/run.py`, under LuaJIT through lupa) cover the reading resolver, page walking,
layout and hit testing, the popup's content and placement, the sentence finder and the
Translate button (mode, Wi-Fi), the settings migration, the menu, and the database code, which runs its real SQL against the built database. `test_integration.lua`
checks the resolver and the popup together, including that for every character the pinyin layer
draws, the popup marks the same reading. `tools/check.sh` also runs the build's Python unit tests
(`tests/test_*.py`, needs OpenCC): the simplified-text converter's fixes.

| File | |
|---|---|
| `main.lua` | lifecycle, menu, data loading, old-plugin check |
| `ch_settings.lua` | settings and the migration from the old plugins |
| `ch_annotator.lua` | the pinyin layer: line spacing, page refresh |
| `ch_page.lua` | walks the page through the rendering engine |
| `ch_resolve.lua` | the reading resolver, for the pinyin and the popup |
| `ch_readings.lua` | the resolver's tables |
| `ch_db.lua` | the database |
| `ch_overlay.lua`, `ch_layout.lua`, `ch_hit.lua` | drawing the pinyin, spacing it, and which pinyin a tap is on |
| `ch_tap.lua` | the one tap handler |
| `ch_context.lua`, `ch_text.lua` | tap → character → the characters around it; candidate words |
| `ch_pinyin.lua` | pinyin comparisons |
| `ch_popup_model.lua`, `ch_popup.lua` | what the popup shows, and the popup |
| `ch_sentence.lua` | the sentence around the tapped character |
| `ch_translate.lua` | the Translate button: KOAssistant (with the prompt snapshot) or KOReader's translator |

## Credits and licences

The annotation code comes from **[WordGloss](https://github.com/GangYe293/wordgloss.koplugin)** by
GangYe293 (GPL-3.0), which koreader-interlinear-pinyin was forked from: the paint layer, layout
and line-height injection (`ch_overlay.lua`, `ch_layout.lua`, parts of `ch_annotator.lua` and
`ch_page.lua`). WordGloss credits its inline-gloss rendering approach to
[inlinehints.koplugin](https://github.com/omer-faruq/inlinehints.koplugin) by omer-faruq.

The code is licensed under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)),
like WordGloss and both plugins it merges.

The data (the database, and the files in `data/`) is derived from, and distributed under,
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), except as noted for Make Me a
Hanzi:

- **[CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict)**, © MDBG and
  contributors, CC BY-SA 4.0: the dictionary, readings and words.
- **[wordfreq](https://github.com/rspeer/wordfreq)** by Robyn Speer, data under CC BY-SA 4.0:
  character and word frequencies.
- **[pypinyin](https://github.com/mozillazg/python-pinyin)** by mozillazg, MIT License: its phrase
  list (words CC-CEDICT lacks) and fallback readings.
- The **[CPP polyphone dataset](https://github.com/kakaobrain/g2pM)** by Kyubyong Park and Seanie
  Lee (Interspeech 2020; repository Apache-2.0, sentences from Chinese Wikipedia, CC BY-SA): its
  train split, for the context rules and uncertain characters. The dataset itself is not
  included.
- **[Wiktionary](https://en.wiktionary.org/)** (English Wiktionary's Chinese entries), by
  Wiktionary contributors, CC BY-SA 4.0, via the
  [kaikki.org](https://kaikki.org/dictionary/Chinese/) extraction made with
  [wiktextract](https://github.com/tatuylonen/wiktextract) (Tatu Ylonen, "Wiktextract: Wiktionary as
  Machine-Readable Structured Data", LREC 2022): the fallback dictionary. Changes made: Mandarin
  readings only, dialect-only senses dropped, redirects resolved, entries CC-CEDICT has and
  everyday combinations left out, senses reformatted; see `data/README.md`.
- **[Chinese Wikipedia](https://zh.wikipedia.org/)**, by Wikipedia contributors, CC BY-SA 4.0,
  from the [Wikimedia dumps](https://dumps.wikimedia.org/zhwiki/): article titles and the titles
  of their English articles (English Wikipedia, CC BY-SA 4.0), for the fallback dictionary.
  Changes made: titles filtered by category and length, converted to both scripts with OpenCC,
  readings generated with pypinyin; see `data/README.md`.
- Wiktionary's `Han compound` analyses and etymology texts, as above, for the character
  components (the etymology texts are still in the database, no longer shown).
- **[Make Me a Hanzi](https://github.com/skishore/makemeahanzi)** `dictionary.txt` by Shaunak
  Kishore (derived from Unihan and cjklib), under the
  [GNU LGPL v3](https://www.gnu.org/licenses/lgpl-3.0.html) or later: decompositions and
  etymology types for the character components. The components rows taken from it (labelled
  MMAH) are under the LGPL v3; the licence text is in the plugin folder
  (`LGPL-3.0.txt`, with the GPL v3 it refers to, `GPL-3.0.txt`), and the build script that
  derives them is `tools/components.py`. Changes made: the `hint` text dropped, roles dropped
  where a simplification hid a part, the sound part taken from the hint where it names one.
  Its `graphics.txt` (Arphic licence) is not used.
- **[yi-bai/ids](https://github.com/yi-bai/ids)** by Yi Bai, MIT License: character structures
  (`ids_lv2.txt`) for the components of characters no other source analyses.

Not distributed, never in the repository or a release; tools in `tools/` build them from the
originals for the user's own device:

- the optional MOE dictionary, [中華民國教育部《重編國語辭典修訂本》](https://dict.revised.moe.edu.tw/)
  (© Ministry of Education, Republic of China (Taiwan),
  [CC BY-ND 3.0 TW](https://creativecommons.org/licenses/by-nd/3.0/tw/)), read from
  [g0v/moedict-data](https://github.com/g0v/moedict-data) (`tools/build_moe.py`);
- the optional CBDB office titles, from the
  [China Biographical Database](https://cbdb.hsites.harvard.edu/) (Harvard University, Academia
  Sinica and Peking University;
  [CBDB Data Licensing Terms](https://cbdb.hsites.harvard.edu/cbdb-data-licensing-terms),
  CC BY-NC-SA 4.0) (`tools/build_cbdb.py`);
- the optional 成語典, [中華民國教育部《成語典》](https://dict.idioms.moe.edu.tw/) (© Ministry of
  Education, Republic of China (Taiwan),
  [CC BY-ND 3.0 TW](https://creativecommons.org/licenses/by-nd/3.0/tw/)) (`tools/build_idioms.py`);
- the optional Xinhua idioms, from [chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua)'s
  `data/idiom.json` (text scraped from a published dictionary) (`tools/build_xinhua.py`);
- the optional Moegirlpedia slang, from [萌娘百科](https://zh.moegirl.org.cn)
  ([CC BY-NC-SA 3.0 CN](https://creativecommons.org/licenses/by-nc-sa/3.0/cn/)), via a third
  party's offline snapshot (`tools/build_moegirl.py`).

[`data/README.md`](data/README.md) lists the changes made and the versions used. The texts in
the sample books are in the public domain: `samples/xiaoshuo.epub` (罗贯中, 鲁迅; from
[Chinese Wikisource](https://zh.wikisource.org/)) and `samples/guwen.epub` (陶渊明, 刘禹锡, 周敦颐).
