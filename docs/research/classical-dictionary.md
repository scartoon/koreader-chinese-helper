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
## 10. 文言 Mode for words: measurement and proposal (#66)

Do the popup's *words* mislead in classical text, and would classical word senses help? Scripts:
[`classical-data/measure_words.py`](classical-data/measure_words.py) (the word lists and corpus
counts) and [`classical-data/judge_words.py`](classical-data/judge_words.py) (corpus-wide
judgments by Claude Haiku, checked by hand below). Readings are out of scope.

**What the popup lists.** Every word of 2–8 characters in the Han run around the tap that
contains the tapped character (`Text.candidates`). The words come from CC-CEDICT, or from the
bundled fallbacks (Wiktionary, Wikipedia titles) for words CC-CEDICT lacks. The Wiktionary
fallback already shows its literary senses for those words: 何由 *(literary) why; for what
reason*, 為國 *(literary) to govern a state*, 自為, 金帛. So the gap is narrower than #66 assumed.
What's missing is the literary senses of words **CC-CEDICT has** (所以, 若是, 賤人), and Chinese
Notes' literary words that no bundled dictionary has. 妻子 is no gap: CC-CEDICT has *wife and
children* under 妻子 qīzǐ, and every 妻子 in the texts takes that sense.

**Sources.** Chinese Notes' *Literary Chinese* word senses (21,773 senses with a gloss) and
Wiktionary's literary, Classical, archaic, obsolete and historical word senses (16,570): 38,343
senses on 28,742 words. Of those words, 14,367 are CC-CEDICT words, 8,327 are only in the
fallbacks (already shown), and 6,048 are in no bundled dictionary. Both licences are the ones
the Classical dictionary already uses (CC BY-SA 3.0 and 4.0).

### Step 1: the 150 sampled taps

The taps are the note's sample (§3): 141 occurrences after the 9 Wikisource annotations. Only 28
taps list a word at all (21 CC-CEDICT words, 7 fallback words). Most taps fall on single-character
words in short runs.

| | Taps | Which |
|---|---|---|
| (a) a listed word has a classical sense CC-CEDICT lacks | **5** (4%) | 若是 *to be like this*, 所以 *that by which*, 莫大 *nothing greater than*, 賤人 *lowly person*, 夫子 *husband / attendant* |
| (b) a listed word is really two classical words here, and its senses mislead | **3** (2%) | 相通 in 賢相通其謀 (賢相 + 通), 坐定 in 坐定天下 (坐 + 定), 不由 in 信不由中 (不 + 由) |
| (c) (a) gives the right sense where CC-CEDICT's is wrong | **4** (3%) | 若是 (CC-CEDICT: *if*), 所以, 莫大, 賤人 (CC-CEDICT: *slut; cheap person*) |
| a literary word that no bundled dictionary has | 1 | 在其中 *therein* |

The words that do mislead are clear examples. A reader who sees 賤人 *slut* for 相如素賤人
("Xiangru was of humble birth"), or 若是 *if* for 自令若是 ("brought himself to this"), is
misled. But on this sample such a tap is about 1 in 30.

### Corpus-wide (all 17 texts, 38,054 characters)

- 2,886 distinct words appear: 2,000 CC-CEDICT words (5,446 occurrences), 686 fallback-only, and
  200 literary words in no bundled dictionary (之子 16, 不以 14, 之謂 10, 不患 7, 柰何 6, 竊聞 3 …,
  mostly phrases).
- **(a)** 998 of the CC-CEDICT words have literary senses. Haiku judged that **336** of them add
  a meaning CC-CEDICT lacks (1,171 occurrences). I checked 20 of those by hand: 16 are real
  classical senses (北面 *to face north as a subject*, 消息 *to wax and wane*, 夫人 *wife of a
  feudal lord*, 公子 *son of a feudal prince*, 前日 *formerly*, 四時 *the four periods of the
  day*). 4 add nothing a reader needs (離騷 *Sorrow at Parting*, a translation; 折枝 *a
  painting technique*; 未可; 韓文). The estimate is **about 270 distinct words**.
- **(b)** Haiku judged each of the 5,446 occurrences: would a reader who takes a CC-CEDICT sense
  misunderstand the passage? It said *mislead* 685 times (411 distinct words) and *other sense*
  248 times. I checked 30 *mislead* verdicts by hand: 16 right (及其, 其所, 以為 *made them into*,
  頗為 across 廉頗 + 為, 餘年 in 百有餘年, 一會 in 無一會期 …), 11 wrong (不知, 之內, 皇帝 …),
  3 unclear. Of 25 *fits* verdicts, 1 was wrong (約法 in 約法省刑). That puts the misleading
  occurrences at roughly **600 of 5,446 (about 11%)**, on **about 250–300 distinct words**.
  A word occurrence covers about two taps, so about 3% of taps, which matches the sample's 2%.
- **Where (b) comes from.** About half the confirmed cases are function-word compounds that are
  two words in classical Chinese: 可以 (Haiku: misleading in 29 of 32), 所以 (27/41), 其所 (14/21),
  有所 (7/8), 與其 (5/8), 以及, 以為, 不可以, 及其, 故而. The other half cross a word boundary next
  to a name or a phrase: 頗為 (廉頗 + 為), 生發 (賈生 + 發), 起始 (吳起's 起 + 始), 樂之, 之至.
  Without segmenting the text those can't be predicted from the word alone.

### Step 2: design options

**A. 文言 senses on words** (recommended). In 文言 Mode, a CC-CEDICT word with classical senses
CC-CEDICT lacks gets those senses as a line labelled 文言, above its CC-CEDICT senses, and these
words come first among the words.
- *Which senses.* Chinese Notes' and Wiktionary's literary senses of CC-CEDICT words, filtered by
  the same Haiku check as above ("does this sense add a meaning CC-CEDICT lacks?"), so the line
  never repeats CC-CEDICT. Each sense is shown as its source wrote it, as for the other dictionaries
  (#48): Chinese Notes' glosses are short (median 20 characters, p90 47), Wiktionary's longer
  (median 41, p90 86, with its tags stripped). **No condensing is needed**, so nothing is
  machine-written: the model only filters.
- *Size and cost.* 14,367 words with 19,893 senses, about 0.7 MB of text before filtering, so
  well under 1 MB in the database. The filter is one Haiku request per word: about $0.30 through
  the Batch API.
- *Effect.* On the sample, 4 of 141 taps get the right sense where CC-CEDICT is wrong. In the
  texts, about 270 words gain a classical sense.

**B. Chinese Notes' literary words that no dictionary has.** In 文言 Mode, show them like a
fallback dictionary (labelled CN or 文言): 6,048 words, about 0.2 MB, no API cost. Mostly phrases
(之子, 不患, 竊聞). 1 sampled tap and 200 words in the texts. Cheap, but small. I'd fold it into A
as the same 文言 line.

**C. A "two words here?" marker.** A small grey note on a word that is often two words in
classical text: 可以 *often 可 + 以 in 文言*. How the list would be built:
- (C1) *From the sources*: there is no source listing such words.
- (C2) *By Haiku from these 17 texts*: 411 flagged words at about 60% precision. These texts are
  too few to give a general list.
- (C3) *By hand*: the function-word compounds above (about 15–20: 可以, 所以, 其所, 有所, 與其,
  以及, 以為, 足以, 是以, 何以, 於是, 而後, 及其, 之上, 之下, 之間 …). Each word has a fixed note
  naming its parts.

The boundary-crossing half (廉頗為, 賈生發) needs segmentation, which the plugin deliberately
doesn't do. A per-word marker would also show where the word is a word (所以 fits 12 of its 41
occurrences, and 可以 in 不可以假人). My recommendation: C3 only, as a short note under the word
in 文言 Mode, no API cost, size negligible. Or leave C out: it covers about 1% of taps.

**Readings** stay as they are in every option.

**Proposal.** Build A (with B folded in) and, if you want it, C3. Measured cost so far: $1.10
of API calls (the corpus judgments). Building would cost about $0.30 more and add about 1 MB to
the database.

## 11. Complete, purely classical entries for characters and words (#67)

Simon's decisions (Nov 21): in 文言 Mode the 文言 entry is the **complete** set of classical senses
of the character or word, **purely classical** (no modern-only sense), always shown in full, and the
same for words. MOE stays out. This replaces the caps of §9 and the supplement options of §10.

**Prompt v5** (`tools/condense_classical_prompt.txt`; v4 kept as
[`classical-data/prompt_v4.txt`](classical-data/prompt_v4.txt)): give every distinct sense, merging
only true duplicates; mark each `"classical": true/false`; order by frequency in classical texts. The
build drops senses marked false. The first try (v5a) counted CC-CEDICT's "(bound form)" as modern
and dropped 事 *matter*, 將 *will* and *a general*, and 民 *the people*. v5b says a bound form is
classical, that only plainly modern senses are false, and to keep a sense when unsure. It also says
the order of the input lines means nothing, and that a function word's grammatical uses come first.

**Words.** Headwords of two or more characters with a Chinese Notes *Literary Chinese* sense, a
Wiktionary literary/Classical/archaic sense or a labelled CC-CEDICT sense, plus all their CC-CEDICT
senses as candidates: 28,995 inputs. In 文言 Mode, the words' entries follow the character's, at
the top of the popup, in the popup's word order (`Model.classicalWordBlocks`).

**Purity check.** The 50 commonest characters still had modern senses after Haiku: 的 *of; 's*, 就
*then* (first!) and its 就…也 / 不…就 patterns, 來 *in order to*, 時 *fashionable*, 麼 *interrogative
particle*, 要 *need to*. That is about 11 of 50, over the issue's stop line. Those senses all came
only from CC-CEDICT's unlabelled lines (14,055 senses in the data). A dedicated check
(`tools/classical_purity.py`: one question per sense, "classical, or only vernacular/modern?"):

| Checker, on the 119 such senses of the 50 commonest characters | Catches the leaks above | Wrong the other way | Cost |
|---|---|---|---|
| Haiku 5.5, medium effort | few (keeps 就 *then*, 和 *and*, 對 *towards*) | — | $0.01 |
| Sonnet 5.5, medium | all | 一 *as soon as* (classical, 一鼓作氣) | $0.12 |
| Sonnet 5.5, low, 15 entries per request | same verdicts as medium on all 119 | same | $0.03 |

The full check covered characters ranked ≤ 3,000 and words: 5,957 entries, 9,927 senses, Batch API
**$1.43**. 3,103 senses were judged modern-only (`data/classical_modern.tsv`, applied by the build).
In 40 random *modern* verdicts, about 33 are right (要 *need to*, 賺 *to earn*, 念 *to read*, 幹 *to
work*, 毛病 *ailment*) and about 7 debatable or wrong (花甲, 邦交, 外侮, 先行 are attested
classically). In 30 random *classical* verdicts, about 1 is doubtful (對 *right; correct*). Purity
costs some real senses, roughly 1 drop in 6. The rarer characters' CC-CEDICT-only senses (4,128)
weren't rechecked: they are mostly science terms, which Haiku already drops (氦, 氟).

**Results.** Full run 51,803 requests (cached system prompt, Batch API): **$1.80**. Prototypes
$0.21, purity pilot and run $1.60, so #67's API total is about $3.60.

| On the 128 judged senses | v4b (2.20.0) | v5b, after the purity check |
|---|---|---|
| in the 文言 entry | 119 (93%) | **121 (95%)** |
| in its first two senses | 99 (77%) | 93 (73%) |
| first | 84 (66%) | 78 (61%) |
| whole popup | 122 (95%) | 122 (95%) |

No needed sense v4b had is lost; 將 *a general* is now in (23rd of 33). The purity check changed
one judged position: 還 *to return* moved from 4th to 2nd once *still; yet* went. Complete lists
cost some order: the first-two measure drops from 77% to 73%.

| | Entries | Senses (median, p90, max) | Characters (median, p90) | Longest |
|---|---|---|---|---|
| Characters | 20,620 | 2, 5, 36 | 39, 112 | 道 36, 將 33, 方 33, 著 28 |
| Words | 26,093 | 1, 3, 12 | 31, 81 | 北京 8 |

Hand review: every sense of the 50 commonest characters after the check, and 50 random words. The
words read as classical in 48 of 50; 日語 *Spanish language* is a late-Qing Wiktionary sense. No
added senses were found. The database is 52.5 MB (+6.1 MB on 2.20.0).

**Display.** Senses are numbered when there are several. With everything shown, the 文言 entry of
the commonest function characters fills the visible popup (之 18 senses, 將 33), and the rest of the
popup is below it.

## 12. Evidence instead of an AI's sense of period (#69)

Simon's decisions (Nov 22): option B. Senses a dictionary tags classical stay as they are. A
sense citing only CC-CEDICT's untagged lines (a *candidate*) stays only if MOE gives the same sense
with a quotation from a classical-register work written up to 1911. No AI decides what counts as
classical. The v5b replies are reused (no new condensing run), Haiku's `classical` mark is ignored,
and `data/classical_modern.tsv` (the Sonnet check of §11) is gone.

**Quote classifier** (`tools/moe_evidence.py`). Of MOE's 144,297 quotations, 95,008 qualify.
Left out: novels 32,086 (any work MOE ever cites by 第…回, 180 titles), other vernacular titles
8,947 (三言二拍 and other 話本 collections, titles with 演義/平話/通俗/諸宮調), drama 6,925 (any
work cited by 第…折/齣 or 楔子, 375 titles), 散曲 549, undated non-commentary quotes 167, 民國 32,
and 《清史稿》 583 (compiled 1914–27; it would have backed only 7 senses, mostly modern, such as
報章 *newspapers*). Hand check of 50 random qualifying quotes: 49 classical; the miss, 《劉知遠諸宮調》,
led to the 諸宮調 rule.

**Matching** (`tools/moe_match.py`). One Haiku request per headword with candidates and at least
one qualifying MOE definition. Haiku sees *all* the headword's MOE definitions, not only the
qualifying ones, so a near miss isn't forced onto the nearest qualifying one. The build keeps a
sense only if its matched definition has a qualifying quote. `build/classical/moe_matches.tsv`
(git-ignored, since it quotes MOE) records the decision, definition and quote for each candidate.
Prototype on the 150 characters and the #67 words: 123 requests, $0.008, and 48 of 50 kept matches
right (wrong: 戲 *trick* → 開玩笑, 卒 *pawn in Chinese chess* → 士兵). Full run: 6,033 requests,
**$0.18** at batch price.

| 18,612 candidate senses | |
|---|---|
| kept: matched a definition with a qualifying quote | 4,798 |
| headword has no qualifying MOE definition | 6,831 |
| no MOE definition with the same meaning | 3,338 |
| matched a definition without a qualifying quote | 3,645 (2,818 with no quote at all, 827 vernacular only) |

**What MOE evidence can't do.** MOE quotes classical texts for classical and specialised senses,
but for a character's plainest sense it usually gives only a modern example (如：…). So senses
classical and modern share lose their evidence: 一 *one*, 有 *to have*, 人 *person*, 不 *not*, 是
*to be*, 金 *gold*, 牛 *ox*. Counting definitions with no quote doesn't help: the same group holds 就
*then*, 的 *of*, 要 *need to*, 了 and 那 *then*. Simon chose to accept the loss (option 1). Those
senses are in the CC-CEDICT entry right below the 文言 entry. The rejected alternatives were sentence
evidence from a classical corpus, and a narrow keep-rule. Song 詞 count as classical, so 了 gains
*completed action marker* from 蘇軾's 「小喬初嫁了」.

**Results** against 2.21.0 (`classical-data/compare69.py`):
- 邦交, 外侮 and 先行 are back. 花甲 is not: MOE quotes it only from 《西遊記》.
- 就 *then*, 要 *need to* and 的 *of* stay out.
- Entries: characters 20,620 → 21,394, words 26,093 → 28,933. Senses: 95,615 → 95,820, with 6,709
  only in the new build and 6,368 only in 2.21.0.
- More entries because tagged senses Haiku had marked modern now stay.
- The database is 53.0 MB (+0.5 MB).

| On the 128 judged senses | 2.21.0 | 2.22.0 |
|---|---|---|
| in the 文言 entry | 121 (95%) | 117 (91%) |
| in its first two senses | 93 (73%) | 94 (73%) |
| first | 78 (61%) | 83 (65%) |
| whole popup | 122 (95%) | 122 (95%) |

The judged senses 2.21.0 had and 2.22.0 lacks are all shared senses with no classical quote in MOE:
信 *to believe*, 太 *greatest*, 有 *to have*, 金 *gold*, 入 *to enter*, 一 *one*, 辭 *to decline*, 牛
*ox* and 楚 *Chu*. Their entries got shorter, so other senses moved up, and *first* rose from 61% to
65%.
