# A collated "Classical" dictionary: research note (#49)

November 2026. A research step only: no plugin code changed and no release made. Everything
measured here can be rebuilt from `build/` (git-ignored): `tools/collate_classical.py`,
`tools/condense_classical.py` and the judging files copied into
[`classical-data/`](classical-data/).

## Summary and recommendation

**Build it.** One Classical dictionary, made of the senses open dictionaries mark as classical
and condensed by Claude Haiku into at most five English senses per character, would show
right below CC-CEDICT in a Classical mode. It fills real gaps:

- On 128 judged occurrences from classical texts, CC-CEDICT alone has the needed sense
  **84%** of the time. The Classical layer alone has it **75%** of the time (it is meant to
  sit under CC-CEDICT, not replace it), and **the two together have it 95%** of the time.
  The Classical layer supplies 15 of the 21 senses CC-CEDICT lacks.
- What CC-CEDICT lacks are core classical senses of very common characters: 是 *this*
  (CC-CEDICT only has *to be*), 也 as a final particle of assertion, 焉 *in it / there*,
  藝 *to plant*, 稍 *gradually*, 說 = 悅 *pleased*, 讎 *enemy*. For rare characters
  (rank > 3,000) CC-CEDICT has the needed sense 62% of the time, the Classical layer 88%.
- **Chinese Notes is the backbone.** Without it, the Classical layer finds 49 of its 96 hits.
  Wiktionary adds the grammatical analyses (也, 是, 之). Unihan only helps rare characters.
  MOE adds nothing on this sample beyond the English sources.
- **Haiku condensing works.** With the final prompt (v3), the condensed entries keep the needed
  sense in 95 of the 96 occurrences where the raw collated text had it. In the checks below I
  found no added senses, only one generalisation (遠 *far; distant* merged from five
  distance-related senses). The whole prototype cost **$0.15** (three prompt versions, 294
  requests each). The full bundled dictionary would cost about **$3.80** one-off, or **$1.90**
  with the Batch API.
- **Ship only the bundled layer** (CC BY-SA sources plus Unihan). Leave MOE out of the
  Classical dictionary. Its licence (BY-ND) would force a second, user-built condensed file,
  and users would need their own API key to build it. On the sample it adds nothing and
  slightly lowers retention (92/96 instead of 95/96). MOE's classical senses stay available in
  the existing MOE Always block.

## 1. Sources

Licences checked against each source's own files (not taken from the issue's table).

| Source | Licence (verified) | Ship in release? | Size | Entries | Single chars | Gloss language | Readings | Parsing |
|---|---|---|---|---|---|---|---|---|
| CC-CEDICT | CC BY-SA 4.0 (already bundled) | yes | in the release DB | 843 classical-labelled senses | 695 chars with one | English | yes | trivial |
| English Wiktionary (kaikki, dump 2026-10-01) | CC BY-SA 4.0 (and GFDL), as the plugin already uses it | yes | 149 MB gz | 328,919 entries | 35,642 | English | yes (Mandarin pinyin) | moderate (JSON, tags) |
| Chinese Notes (`cnotes_zh_en_dict.tsv`) | CC BY-SA 3.0: header of the file and the repo's `license.txt` ("applies to the content in the Chinese-English dictionary"); code Apache-2.0 | yes (BY-SA 3.0 lets adaptations use a later version, so it can be combined into a BY-SA 4.0 file) | 25.7 MB | 169,442 sense rows, 55,826 in the *Literary Chinese* domain | 19,676 chars, 18,037 with a literary sense | English (plus "In the sense of 距离" notes in modern Chinese) | yes | trivial (TSV, one sense per row) |
| Unihan `kDefinition` (latest `Unihan.zip`, downloaded 2026-11-19) | Unicode License v3: permissive, keep the notice | yes | 8.3 MB zip | definitions for 23,310 chars | — | English | yes (`kMandarin`) | trivial |
| MOE 重編國語辭典 (g0v/moedict-data) | CC BY-ND 3.0 TW | **no**, user-built only (as today) | 15 MB xz | 161,194 entries | — | modern Chinese, with 書證 quotes | yes | easy (JSON) |
| Ancient Chinese WordNet (LDC2026L03) | LDC User Agreement for Non-Members: fee, no redistribution | **excluded** | — | 38,781 forms, 55,100 senses mapped to Princeton WordNet 1.6 synsets | — | English (WordNet glosses) | ? | — |

**Excluded without download.** These are under copyright: Kroll's *Student's Dictionary of
Classical and Medieval Chinese*, 汉语大字典 / 汉语大词典, and 古汉语常用字字典. CText's dictionary
is API-only and its terms rule out bulk use. These define in classical Chinese: 康熙字典,
說文解字(注), 廣韻, HDIC.

**Chinese Notes provenance caveat.** Many of its senses cite references next to the gloss:
"Guoyu" (MOE) in 46,287 rows, Kroll 2015 in some, and ABC and Mathews 1931 in others. The
English glosses are Chinese Notes' own short wording, and the project publishes the whole
file as CC BY-SA 3.0. That licence is clear and compatible, so it doesn't change the
recommendation. Still, it's worth knowing that part of its literary layer was written while
consulting a BY-ND and a copyrighted dictionary. Short dictionary glosses are usually treated
as facts, but this is a judgement for Simon.

## 2. Classical test set

17 public-domain texts from zh.wikisource (fetched with `classical-data/fetch_texts.py`), 38,054
Han characters in `build/classical/texts/`:

- 論語: 學而, 為政, 里仁, 述而
- 孟子: 梁惠王上
- 左傳: 隱公
- 史記: 廉頗藺相如列傳, 屈原賈生列傳, 刺客列傳
- 資治通鑑: 卷一
- 古文觀止 pieces: 出師表, 師說, 岳陽樓記, 醉翁亭記, 過秦論, 桃花源記, 蘭亭集序

陳情表 resolved to a disambiguation page and was dropped.

**Simon's books.** None of the 50 extracted books (`build/corpus/`) is 文言. I compared counts of
之乎者也矣焉曰兮哉耳 with counts of 的了们这吗么呢. The highest ratio among the books is 0.48 (唐德刚
晚清七十年), against 60–217 for the test texts. Several are modern histories (晚清七十年, 中国大历史,
曾国藩传, 易中天) that quote classical passages, which is where Classical mode would help.

## 3. Judged sample

150 occurrences sampled with a fixed seed (`classical-data/sample.tsv`):

- 60 over-sampled from characters whose classical sense differs (之 其 而 焉 乃 走 去 兵 夫 …)
- 35 from rank ≤ 500
- 35 from rank 500–3,000
- 20 rarer

I wrote the sense each occurrence needs in context in `classical-data/judgments.tsv`: 128
judged senses, 13 proper names (藺相如, 荊軻 …, not a dictionary question), and 9 excluded
because the sample landed in Wikisource's modern annotations. Each judgment carries a keyword
pattern. A source "has the sense" when a keyword matches one of its senses, and I then
hand-checked every match and every miss: 6 CC-CEDICT matches and 10 Classical matches were
wrong senses, and one CC-CEDICT miss was really a hit. 128 is a little under the ~150 asked
for, but the differences below are large enough not to need more.

## 4. "Identifiably classical": rules and precision

Precision is judged on a random sample of the extracted senses: is this really a sense used
in classical texts, rather than a modern one?

| Source | Rule (`tools/collate_classical.py`) | Extracted | Precision |
|---|---|---|---|
| CC-CEDICT | a sense labelled `(literary)`, `(classical)`, `(archaic)`, `(old)` or `(obsolete)` | 843 senses / 695 chars | **50/50** |
| Wiktionary | single-character senses tagged `literary`, `archaic`, `obsolete`, `Classical` or `historical`, or qualified "obsolete on its own in Standard Chinese"; not dialect senses, not "variant of", not Korean/Japanese/Vietnamese Classical Chinese | 9,122 / 4,949 | **46/50**. Misses: 戤 *to counterfeit a trademark*, 膣 *vagina*, 設 the Turkic office *shad*, 約 *to estimate* |
| Chinese Notes | single-character rows in the *Literary Chinese* domain with a gloss | 27,607 / 11,667 | **32/41** (9 of 50 drawn had no gloss; those are now dropped). Misses are modern senses filed as literary (團 *ball*, 糧 *grain*, 坊 *memorial arch*, 砌 *to pile up*) |
| Unihan | all of `kDefinition` (it has no register), only for characters outside the 3,000 most frequent | 41,254 senses; 16,391 chars kept | rare: **21/25**; common: **3/25** (苹 *apple*, 擦 *brush*: modern), hence the rank cut |
| MOE | a sense with a 書證 quote from a pre-modern, non-vernacular work: an author dated before the Yuan, or a classic quoted without a dynasty (《孟子》), never a Ming–Qing novel (水滸傳, 紅樓夢 …) | 17,450 / 7,278 | **45/50**. Misses: modern senses that happen to have an old quote (談 *to talk*, 凸, 挽 *to pull*, 瀉 *to pour*, 腐 *tofu* from 幼學瓊林) |

**Does MOE define partly in classical Chinese?** This was a stop-and-ask condition, so I
measured it. 30.6% of its extracted glosses are one or two characters, but they're
overwhelmingly modern compounds (經歷, 外城, 雜亂, 見面). Only 2.8% are a single character
(孔: 大, 臧: 善), and 0.8% lean on classical function words, mostly as modern metalanguage
(相當於「也」…, 語氣詞，用於句首). I judged that MOE defines in modern written Chinese, so the
condition didn't fire. Its 書證 quotes are classical text, so the condensing input leaves them
out.

## 5. Coverage

On the judged sample (`classical-data/verdicts.tsv`). The **Classical** column is the English
layer: CC-CEDICT's classical senses, Wiktionary, Chinese Notes and rare-character Unihan.

| Band | n | CC-CEDICT alone | Classical alone | Together |
|---|---|---|---|---|
| over-sampled (classical ≠ modern) | 55 | 85% | 82% | 96% |
| rank ≤ 500 | 29 | 93% | 52% | 97% |
| rank 500–3,000 | 28 | 82% | 79% | 96% |
| rarer | 16 | 62% | 88% | 88% |
| **all** | **128** | **84%** | **75%** | **95%** |

The Classical layer alone looks weak for common characters by design: it holds the classical
senses, not the everyday ones CC-CEDICT shows right above it.

**Marginal contributions** (Classical-layer hits, out of 96, when one source is removed):

| Removed | Hits left |
|---|---|
| Chinese Notes | 49 |
| Wiktionary | 86 |
| CC-CEDICT's own classical senses | 95 |
| Unihan | 95 |

Of the 21 senses CC-CEDICT misses, the layer supplies 15:
- Wiktionary alone: 2 (也 ×2)
- Chinese Notes alone: 5 (說, 稍, 群, 肘 …)
- Unihan alone: 1 (邾)
- several sources at once: the rest

MOE supplies none of the 6 that remain missing (夫子 *master*, 坐 *idly*, 小 *humble*, 宋/衞
as states, 昬 = 婚). CC-CEDICT's classical senses are already shown in its own block, so they
can be left out of the Classical one.

**Characters with a Classical entry** (English layer; with MOE in brackets). Ranks are the
plugin's `chars.rank`; ties put 4,508 characters at rank ≤ 3,000.

| Band | Characters with an entry |
|---|---|
| rank ≤ 3,000 | 2,936 / 4,508 (3,091) |
| 3,000–6,000 | 3,268 / 4,138 (3,270) |
| above 6,000 | 2,857 / 3,649 (2,901) |
| unranked | 12,503 (12,810) |
| **in all** | **21,564 (22,072)** |

## 6. Condensing with Haiku (the prototype)

`tools/condense_classical.py` sends each character's collated senses (one numbered line per
sense, MOE's quotes left out) to `claude-haiku-5-5` with the fixed prompt
`tools/condense_classical_prompt.txt`, thinking off. Haiku 5.5 rejects a non-default
`temperature` (HTTP 400), so none is sent. Determinism comes from the cache instead: every
response is stored under a hash of model, prompt, variant and input, so reruns never call
the API for unchanged input. Each sense cites the input lines it came from, its source labels
follow from those lines, and the raw collated input is kept beside the condensed entry for a
tap-to-expand view.

The run covered the 106 characters of the judged sample (plus 說, the form 説 needed) and 44 more
across bands, including
之 其 而 以 於 and rare ones (邯 殪 輈 矐 …), in two variants: **bundled** (no MOE) and **local**
(with MOE).

| Prompt | Needed sense kept (bundled / local, of 96) | Added senses found | Over the 5-sense cap | Cost |
|---|---|---|---|---|
| v1: tag sources, "use only the text given" | 94 / 93 | 4–5 entries: 而 *and; yet; but* (tagged CN, but no line says it), 遠 *far*, 橋 *bridge* as a noun, 還 *still; yet* | 0 | $0.05 |
| v2: numbered lines, cite them, "don't fill in missing everyday senses" | 95 / 92 | 入 *to enter* (citing *to conform with / descend / join*), 遠 *far*, 還 *return* | 3 | $0.05 |
| **v3**: the gloss must be built from the cited lines' words; at most five | **95 / 92** | none found; one generalisation (遠 *far; distant*, from *far-reaching, long-range, remote area*) | 1 (local) | $0.05 |

**How additions were checked, on every entry of the sample.** First, a screen compared each
sense's content words with the lines it cites, and flagged senses citing no line, citing a
line that doesn't exist, or sharing less than half their words with the cited lines. I
reviewed every flag. Second, I read every bundled sense of every character ranked ≤ 500 next
to its cited lines, because additions concentrate there: Haiku knows those characters' modern
senses, and the input deliberately lacks them. Senses citing only MOE lines are translations
and can't be screened by English words. I spot-checked them and they read as faithful.

**Drops.** Only 陰 *secretly* in the bundled variant: 陰 has 16 classical senses, and *secretly*
didn't make the five. In the local variant MOE's senses also crowd out 自 *oneself* (twice) and
諸 *various*. That's well under the 1-in-10 stop line.

**Tokens and cost.** The final run (v3, 294 requests) used 287,332 input and 44,700 output
tokens, $0.051. The three runs together cost $0.15. A request averages about 930 input and 140
output tokens (bundled), or about 1,030 and 165 (local). At $0.10 / $0.50 per MTok:

| Variant | Requests | Standard API | Batch API (half price) |
|---|---|---|---|
| bundled | 23,102 | about $3.80 | about $1.90 |
| local | 23,636 | about $4.40 | about $2.20 |

**Licences of the result.** A condensed entry is a derivative of its inputs. Built from CC
BY-SA sources (Wiktionary, Chinese Notes; CC-CEDICT if kept) plus Unihan (permissive), it is CC
BY-SA 4.0 with Unihan's notice, and can ship in the release. An entry that includes MOE
(BY-ND) may not be shipped and could only be built on the user's machine, which would need
their own API key. That's one more reason to leave MOE out.

## 7. Readability and design sketch

**Length.** Raw collated text per character runs at a median of 264 characters, p90 628, and
之 896. The condensed entries run at a median of 83 characters for five senses, p90 154. 之
condenses to:

> him; her; it; them (object pronoun in non-subject position) / genitive or attributive marker
> (possession or modification) / nominalizer or subordinate-clause particle in a
> subject-predicate construct / this; these; that / to go; to arrive

On the 7-inch popup the existing two-line collapse shows about three of the five senses, and
the [Tap to show more] marker opens the rest.

**Inside the block:**
- the condensed senses in Haiku's order (grammatical words and senses that differ from modern
  Chinese first), one per line
- after each sense, a small grey label naming its sources (`CN · Wikt`), like the existing
  source labels
- duplicates across sources are already merged by the condensing step
- a second tap (or a "Sources" line) opens the raw collated text grouped by source, English
  sources first; the #48 principle that each source is shown as written still holds there

**Schema.** One table in the release database:

```
classical(trad TEXT, simp TEXT, senses TEXT  -- JSON [{gloss, reading, sources}]
          , raw TEXT)                         -- the collated lines, by source
```

The table is keyed by the traditional form, because a simplified character can merge several
(发: 發/髮). A simplified tap would show the entry of the form `Model.tradPick` picks from the
word around it, else all of them. Variant characters (説→說, 衞→衛) need a lookup through
Unihan's variant fields; the prototype missed 説 and 衞 because of this. Classical words (two
or more characters) are worth a later step: Chinese Notes has about 21,800 literary word
senses.

**The setting.** **Classical mode** (Popup → Dictionaries): a manual toggle, global at first,
with a per-book override as an option. Detecting it automatically is a possible follow-up.
The function-word ratio separates the test texts (60–217) from every one of the 50 books
(≤ 0.48) by two orders of magnitude.

**Place in the popup.** A block for the tapped character only, right after its CC-CEDICT
entry, before the components and the words. It's not a fallback source, so the fallback order
and the Always modes don't apply to it. It carries its own label (e.g. `文言` or `Classical`)
and is collapsed like MOE Always. With the mode off nothing changes.

**Size.**

| Layer | Size |
|---|---|
| Raw collated text, bundled | about 2.8 MB |
| Condensed entries | about 3.5 MB |
| Release database growth | about 6–8 MB (37.8 → about 45 MB; the zip grows by about 3 MB) |
| A local MOE layer, if ever wanted | about 4 MB more |

**Build cost.** A one-off Batch API run of about $2, then only the changed entries (the cache
keys on the input).

## 8. Proposed follow-up issues

1. **Build the Classical dictionary data.** Add `tools/build_classical.py`. It collates as in
   this note, with these fixes:
   - leave out CC-CEDICT's own senses
   - Unihan for rank > 3,000 only
   - no Korean/Japanese/Vietnamese-tagged Wiktionary senses
   - variant characters normalised through Unihan
   - drop Chinese Notes rows without a gloss

   Then it condenses with the v3 prompt through the Batch API and a persistent cache, validates
   each sense mechanically (it must cite existing lines; it is flagged when its words aren't in
   them; at most five per character), and writes the `classical` table into the release
   database. One-off cost about $2. Acceptance: on this note's sample, at least 95/96 needed
   senses kept and no added senses on review.
2. **Classical mode and the popup block.** Add a manual setting (global, with a per-book
   override), a block after the tapped character's CC-CEDICT entry with per-sense source
   labels, the two-line collapse, and a tap to the raw sources, plus tests and the README.
   Depends on 1.
3. **Detect classical text automatically.** Turn Classical mode on per book (or per page) from
   the ratio of classical to modern function words. The measured separation is two orders of
   magnitude; it needs a threshold and a check on the modern histories that quote classical
   passages. Depends on 2.
4. **Classical words.** Add two- and more-character literary words from Chinese Notes (about
   21,800 senses) and Wiktionary to the same table, shown in the word blocks. Measure first how
   often the words around a tapped character in the test set have such an entry and CC-CEDICT
   doesn't.

## 9. Rebuild for the top of the popup (#65)

Since #56 the 文言 entry comes first in the popup and is shown in full, so what matters is whether
the needed sense is *near the top* of that entry, not just somewhere in the popup. #65 rebuilt the
dictionary for that role. Scripts: [`classical-data/eval_top.py`](classical-data/eval_top.py)
(position of the needed sense, with the hand check in `fix_v3.json`, `fix_v4.json` and `fix_v4b.json`)
and [`classical-data/compare_proto.py`](classical-data/compare_proto.py).

**Hand check.** For each of the 128 judged senses, the judgment's keyword pattern finds the first
matching sense. I then read every row. Where the keyword hit a different sense (之 *genitive* for
the subject–predicate particle, 將 *to command* for *a general*, 知 *to cause to know* for *to
know*) or missed the right one, I set the position by hand. I applied the same reading to every
version.

### Baseline: the 2.19.3 entries (prompt v3)

| Band | n | In the entry | In the first two | First |
|---|---|---|---|---|
| over-sampled | 55 | 44 (80%) | 29 (53%) | 25 (45%) |
| rank ≤ 500 | 29 | 14 (48%) | 11 (38%) | 7 (24%) |
| rank 500–3,000 | 28 | 22 (79%) | 20 (71%) | 12 (43%) |
| rarer | 16 | 14 (88%) | 13 (81%) | 11 (69%) |
| **all** | **128** | **94 (73%)** | **73 (57%)** | **55 (43%)** |

The whole popup (the entry or CC-CEDICT) has it 122 times (95%). Positions when present: 1st 55,
2nd 18, 3rd 12, 4th 1, 5th 8. The weak band is the commonest characters, as expected from a
supplement that left out every sense CC-CEDICT has: 而 *and*, 有 *to have*, 天 *heaven*, 事
*affair* and 知 *to know* were missing from their entries.

### Changes

- **Collation.** CC-CEDICT's senses of the character are added as `[CEDICT]` lines: its labelled
  ones keep their label in the text (`(literary) to command; to lead`), its others are candidates.
  Surnames, "Taiwan pr.", "also pr.", classifiers, "used in", "see" and colloquial, dialect and
  slang senses are left out. Only characters that already have a classical line (Wiktionary,
  Chinese Notes, rare-character Unihan, or a labelled CC-CEDICT sense) get CC-CEDICT lines, so a
  character with only modern senses still gets no entry (吗, 氟). The #55 fixes stay.
- **Prompt v4** (`tools/condense_classical_prompt.txt`; v3 is kept as
  [`classical-data/prompt_v3.txt`](classical-data/prompt_v3.txt)). It says the reader has
  switched the mode on for classical text and the entry is shown first, and asks Haiku to order
  senses by how common they are in classical texts, to include a shared sense (而 *and; but*)
  when it is among the commonest, and to leave out modern-only senses. The citation rule stays:
  every gloss is built from the words of the lines it cites, and Haiku's own knowledge decides
  only the order and the choice. The cap now comes with the input ("Senses allowed: 8").
- **Caps and input order.** The cap is 8 senses for rank ≤ 500, 6 for rank ≤ 3,000 and 5 for
  the rest. The input lists Wiktionary, Chinese Notes and Unihan first and CC-CEDICT last.

### Prototype: v3 against v4 (150-character set, 128 judged senses)

| Version | In the entry | First two | First | Whole popup | v3 senses lost |
|---|---|---|---|---|---|
| v3 (2.19.3) | 94 (73%) | 73 (57%) | 55 (43%) | 122 (95%) | — |
| v4a: CEDICT lines first, cap 8 for rank ≤ 500, else 5 | 120 (94%) | 99 (77%) | 82 (64%) | 121 (95%) | 藝 *to plant* |
| **v4b: CEDICT lines last, caps 8 / 6 / 5** | **119 (93%)** | **99 (77%)** | **84 (66%)** | **122 (95%)** | none |

v4a showed two problems. With CC-CEDICT's lines first, Haiku tended to keep their order: 乎 put
four preposition senses before *question particle*. And at five senses 藝 kept *a bound; a limit*
over *to plant*. v4b fixes both: 乎 opens with the question particle, and 藝 *to plant* is back,
6th. 

By band (v4b): over-sampled 40/55 in the first two (73%), rank ≤ 500 22/29 (76%), 500–3,000
24/28 (86%), rarer 13/16 (81%). Positions: 1st 84, 2nd 15, 3rd 4, 4th 4, 5th 8, 6th 3, 7th 1.

Some senses moved down in v4b, though none was lost. 之's subject–predicate particle went from
3rd to 5th: 之 now leads with *him; her; them; it*, *genitive marker*, *to go*, *this*. Also
from 1st to 2nd: 若 *like*, 相 *chancellor*, 卒 *to die* (behind *soldier*) and 莫 *none*. And 說
*to be delighted* went from 1st to 4th, behind *to speak*, *to persuade* and *to explain*. These
are Haiku's frequency judgments, and on the whole they're defensible. The ones the sample needed
and v4b doesn't have are 將 *a general*, 夫子, 坐 *idly*, 小 *humble*, 宋/衞 as states and 昬 = 婚.
None of them is in the sources (as in §5) except 將, whose entry has *to command; to lead* 8th.

**Cap.** For the commonest characters the needed sense sits 5th to 7th in 9 cases (於 *by* in the
passive 6th, 大 *greatly* 6th, 之 5th, 也 5th…), so a cap of 5 would have cut them. Eight is
also where the longest entries still fit (below). For ranks 500–3,000 the cap of 6 keeps 藝
*to plant*, which five didn't.

**Added senses.** The mechanical screen (a gloss sharing under half its content words with the
cited lines) flagged 16 senses on the prototype. I read every one, and every bundled sense of
the 47 characters ranked ≤ 500 next to its cited lines. Not one sense is missing from its
sources. Some glosses carry an explanatory word that isn't in the line: 師 *master (one skilled
in an art, or a respected elder)* from "master", 前 *front; before (in space)*. 彊 spells out
`variant of 強` as *variant of 強: strong; powerful*. Those are wording, not new senses.

**Modern-only senses in the top two.** None among the characters ranked ≤ 500. Lower in the
list, CC-CEDICT brings in a few modern senses that the cap leaves room for: 前 *future*, 天
*day*, 事 *accident; item*, 得 *to catch (a disease)*, 死 *extremely*. Since 文言 Mode is only on
for classical text, they cost a line each and don't mislead at the top.

**Length** (characters of an entry, its senses joined with " / "):

| | Median | p90 | Longest |
|---|---|---|---|
| v3, prototype set | 92 | 160 | 也 282 |
| v4b, prototype set | 118 | 204 | 也 365 |
| v4b, every entry | 40 | 110 | 秦 511 (6 senses, its states and dynasties), 商 389, 也 365, 與 362 |

Each sense is a line in the popup. On the Boox Go 7 in landscape (the `docs/classical.png`
geometry: a line about 34 px, a 1,035 px popup), 也's eight one-line senses plus the head and
labels take about 380 px, about 37% of the popup. 秦's longest sense wraps to a second line. Still
to confirm on the device.

### Full run

22,956 requests through the Batch API, 25.4 M input and 2.1 M output tokens, **$1.78**; the
prototype runs cost $0.06. Two replies (就, 方) had one brace too many at the end; the build now
mends that. The result has 21,191 entries and 184 variants (21,292 before). The 221 characters
that lost their entry had only modern senses (乒 *ping*, 氟 *fluorine*, 傣 *Dai*); 120 gained
one (听, 离, 座 …). Screen flags: few-words 620, no-sense 151, over-cap 8, no-line 3. The
release database grows by 1.8 MB, to 46.4 MB.

On the judged sample the full build gives the same numbers as the v4b prototype (the cache is
shared). With 文言 Mode on, the needed sense is in the 文言 entry's first two senses 77% of the
time, up from 57%, and in the whole popup 95% of the time, as before.

**Readings.** v4 replies often give the reading on every sense. The popup only shows a reading
to tell readings apart, so the build drops them when all of an entry's senses share one. 1,432
entries keep readings, and the reading display is unchanged.
