# 2.0.0 handoff: context line and page underline

Session 1 of 2 built and device-tested two features. Nothing was released: the version is still
1.9.2, and the CHANGELOG, README and screenshots are unchanged. Session 2 does those and the
2.0.0 release.

## What was built

1. **Context line.** Every popup opened from a tap on book text now starts with one line of the
   text around the tapped character, with the character in bold and underlined.
2. **Page underline.** While the popup is open, the tapped character is underlined on the page.

### Settings and menu

Both are in the plugin menu, right after "Show character components" (menu items 10 and 11). Both
are on by default.

| Key (`G_reader_settings`) | Menu label | Getter |
|---|---|---|
| `chinesehelper_popup_context` | Show the text around the character in the popup | `Settings:contextEnabled()` |
| `chinesehelper_page_underline` | Underline the tapped character on the page | `Settings:underlineEnabled()` |

### Files and functions

- **`ch_snippet.lua` (new).** No KOReader requires, so it is tested offline.
  - `Snippet.select{chars, index, word, measure, width}` is the pure selection function. It returns
    `{before, mark, after, cut_left, cut_right}`.
    - Boundaries come from `Snippet.bounds`: a paragraph break, a sentence end (`Sentence.isEnd`:
      。！？ and their variants, and Latin . ! ? before a space) together with the closers after it,
      or the edge of the page text.
    - Whitespace runs, `<br/>` included, become nothing between two full-width characters
      (`Snippet.isWide`) and one space elsewhere.
    - Width grows outwards from the mark, the narrower side first. A side that is cut gets a "…".
    - The result is re-measured as whole strings, so kerning can never make it wrap.
  - `Snippet.pageBounds(document, scroll)` returns the XPointers of the visible text.
    - Page view: from `getPageXPointer(page)` to `getPageXPointer(page + visible page count)`.
    - Continuous view: from `getXPointer()` to the start of the page after next. This is
      approximate (see "Worth a second look").
  - `Snippet.pageText(document, hit, bounds)` returns the page's characters and the tapped
    character's index. It makes two `getTextFromXPointers` reads: page start to page end, and
    page start to `hit.pos1`.
  - `Snippet.markLineBreaks` and `Snippet.crossing` deal with `<br/>`. crengine returns `"\n"` for
    both a `<br/>` and a block break.
    - It walks up to `LINE_REACH` (80) characters each way from the tap.
    - A step is classed as a `<br/>` when `getHTMLFromXPointers` over it contains `<br`.
    - A step is classed as a block break when the two XPointers' paths diverge through a non-inline
      element.
    - The "\n"s are then matched to these steps in order. If the counts differ, every "\n" stays a
      paragraph break.
- **`ch_popup.lua`**
  - `Popup.contextLine(context, word, face, width)` builds the line widget: a HorizontalGroup of
    three TextWidgets (before / mark / after). The mark is bold and wrapped in a small `Underlined`
    widget that paints a rectangle under the baseline.
  - The line uses the popup's own text face (`self.face`), the same size as the entries, as the
    user asked mid-session ("same size as primary text, no down scaling").
  - Underline under the mark: thickness `max(2, round(size/10))`, offset `max(2, round(size*0.12))`
    below the baseline.
  - `Popup.addContextToDict(dql, context, word)` adds the line to KOReader's dictionary popup (see
    "Word buttons" below).
  - The old header, shown only when the popup covered the character, is gone: `Model.header` was
    removed along with its test, and so was the build-twice logic in `Popup:init`.
  - New `on_close` field, called from `Popup:onCloseWidget` however the popup closes.
- **`ch_tap.lua`**
  - `Tap:context(hit)` reads the page text (logged as `context N chars in X ms`).
  - `Tap:mark(hit)` and `Tap:unmark(id)` handle the underline. Each mark has an id, so a late close
    callback never clears a newer mark.
  - `Tap:lookupInKOReader(text, box, {context, word, on_close})` and `Tap.installDictHook()`.
  - A tap that throws now also clears the underline. Before this fix, a failed tap left it behind.
- **`ch_annotator.lua`.** `Annotator:setMark(box, no_refresh)`, plus the refresh types
  `Annotator.MARK_DRAW = "ui"` and `Annotator.MARK_CLEAR = "partial"`.
- **`ch_overlay.lua`.** `Overlay:setMark` and `Overlay:markRect`. The mark is painted at the start
  of `paintTo`, before the pinyin and even when there is no pinyin.
- **`ch_layout.lua`.** `Layout.underlineRect(box, text_height, thick, gap)`.
  - Thickness: `max(2, round(text/16))`, which is 4 px at 64 px text.
  - Gap: `max(1, round(text/24))` below the glyph band, which is 3 px.
- **`main.lua`.** The two menu items. `onPageUpdate` and `onPosUpdate` clear the mark without a
  refresh of their own.
- **`ch_settings.lua`.** The two defaults and getters.
- **Tests.**
  - `tests/test_snippet.lua` (new) covers every case in the brief, a width sweep that checks the
    line never exceeds its width, the `<br/>` crossing classifier, and `pageText` on the fake
    document.
  - `test_layout.lua` covers the underline rectangle.
  - `test_menu.lua` covers both toggles. The fallback menu moved from index 10 to 12.
- **`tools/make_snippet_epub.py` (new).** The device test book, pushed to
  `/sdcard/Download/chinesehelper-snippet.epub`. It has closers, a classical comma sentence, mixed
  Latin, source newlines with runs of spaces and a `<br/>`, a short sentence, and 首鼠两端.

### Word buttons (KOReader's dictionary popup)

The word and character buttons open KOReader's own DictQuickLookup, not a plugin popup. To give
those popups the line:

- `Tap.installDictHook` wraps `DictQuickLookup.init` once.
- A lookup from our buttons stores `Tap.pending_dict = {boxes, context, word}`.
- The hook recognises that lookup's popup because `dql.word_boxes` is the same table we passed in.
  ReaderDictionary passes it through unchanged. Lookups made from inside a dictionary popup, or
  from anywhere else, never match, so they get no line. This was checked on the device.
- The whole word is marked when `Snippet.select` finds those exact characters at `start` from the
  tapped character. Otherwise only the tapped character is marked.
- The dictionary popup keeps its height, and so keeps the place KOReader chose for it:
  - The definition (which scrolls) gives up whole lines to make room.
  - Any spare pixels go below the definition.
  - The line is skipped if fewer than 3 definition lines would remain.
- The no-match path also gets the line. In that path a tap goes straight to KOReader's dictionary.
- **This uses DictQuickLookup internals** (KOReader v2026.07.1 on the device): `dict_frame[1]`,
  `definition_widget`, `definition_line_height`, `definition_height`, `_instantiateScrollWidget`,
  `content_face` and `content_width`. Re-check them after a KOReader update. Any failure is caught
  and logged (`context line in dictionary failed`), and the popup then opens without the line.

## Underline: drawing approach and refresh

- **Drawn in the plugin's own paint hook** (the pinyin overlay, a ReaderView view module), not with
  KOReader's highlight mechanism.
  - The overlay is always registered for reflowable books, so the hook is there even with pinyin off.
  - It already draws relative to character boxes.
  - The underline's lifetime is entirely ours.
  - KOReader's temporary highlight is tied to text selection. It draws a box or inverted colours,
    and clears on its own schedule (`DELAY_CLEAR_HIGHLIGHT_S`).
- **Refresh:** `"ui"` when the line appears and `"partial"` when it goes, each limited to the line's
  rectangle plus 2 px. Both go through `UIManager:setDirty(ReaderUI, ...)`, so a popup above is
  repainted on top. The user looked at the device after two clears (tap outside, Back) and saw
  **no ghost**, so no flashing refresh is needed.

## What the device checks showed

Checks used a Boox Go 7 in landscape (1680×1264), the snippet test book, and 这个历史挺靠谱 page
320 (64 px text, popup text at 60%).

- **Selection on a real book: all correct.**

  | Case | Line shown |
  |---|---|
  | Mid-sentence, cut for width | `…钱，所以他总结灭佛的结果说：“自废以来，民役稍稀，租调年增，兵师日盛，东平齐国，…` |
  | After 。” | `五众释门三百万，该当兵的当兵，该交税的交税，还归编户。` (no stray ”) |
  | First on page | `你。` (stops at the page edge) |
  | Last on page | `…“自废以来，…岂非有益？”` |
  | Six-comma quote | `“融扩佛像，焚烧经教，三宝福财，簿录入官，登即赏赐，分散荡尽。”` (whole) |
  | `<br/>`, source newlines and spaces | `这一段的源文件里有换行，还有很多空格，以及一个换行标签，English words here 也在里面。` |

- **Text size and orientation.**
  - At 120% popup text, still one line, centred, cut on both sides.
  - Landscape is the device's normal orientation, and every check ran in it. Portrait could not be
    tested: Android controls rotation on this Boox, and changing `copt_rotation_mode` had no effect.
- **Speed.** The context read takes 1–4 ms per tap (4 ms with the `<br/>` walk). Tap totals are
  still 22–87 ms, as before.
- **Bold.**
  - In our popup at 60% (about 38 px), the bold mark is **faint**. Synthetic bold on the CJK
    fallback of `x_smallinfofont` is hard to tell from regular text on a close crop. The underline
    is what makes the mark clear.
  - At 120%, and in KOReader's dictionary popup (`cfont`), the bold is clearly visible.
  - The underline thickness in the line was raised from size/14 to size/10 after the first look.
- **Page underline.**
  - Visible under characters the popup leaves uncovered (谈, 笑, 你, 民), and painted over when the
    popup covers it.
  - Cleared when closed by tap outside, the Close button, Back, Translate, and closing the
    dictionary popup that a word button opened.
  - A second tap moves it (谈 → 笑, nothing left under 谈).
  - With the dictionary popup open, the underline stays on the tapped character. In both tests,
    KOReader's tall dictionary popup happened to cover the character.
- **Page turns while a popup is open** are not possible: page keys and swipes do nothing while
  either popup is up, the same as before. The clear on page turn is a safety net.
- **Pinyin collision.** With 民 tapped on the line above 戎 (róng), the underline sits just above
  the top of "róng", a few pixels clear. They touch neither each other nor the glyphs. It reads as
  belonging to 民.
- **Settings.** Each one turned off on its own works: no line but an underline, then a line but no
  underline.

## Left unfinished or worth a second look

- **With the context line off there is no line at all.** The 1.x header (the Han run around the
  character, shown only when the popup covered it) was replaced, not kept as a fallback. Confirm
  with the user that this is wanted.
- **Continuous (scroll) view was not tested on the device.** Its bounds run to the page after next,
  so the line can include text below the screen.
- **Dictionary popup.** It loses 1–2 lines of definition to the context line (they scroll). If a
  lookup never opens a popup (cancelled), the underline stays until the next tap or page turn,
  because KOReader never calls our close callback.
- **`<br/>` detection** depends on crengine's HTML output and an inline-element list
  (`Snippet.INLINE`). Unknown cases fall back to treating the break as a paragraph break.
- **Faint bold** in our popup. `Font.FORCE_SYNTHETIZED_BOLD` or a heavier face was not tried. The
  underline carries the mark either way.
- `Model.place`'s second return value (`covers`) is no longer used.

## What affects the README screenshots (session 2)

- **Every popup is taller by one line**: 84 px on this device at 60%. That is about 38 px of text,
  plus padding and the separator rule.
  - Some popups that used to fit in half the screen are now centred, and can cover the tapped
    line. On page 320, 民's popup ends just above 民 with the line off, and half-covers it with the
    line on.
  - All popup screenshots will change, and the shot gate (`tools/shot_gate.py`) only checks
    readings and markers.
- **The page underline appears in shots** whenever the tapped character is not covered. It is on
  by default, so shots will show it unless the script turns `chinesehelper_page_underline` off.
  Decide whether the main screenshot should show it as a feature.
- Popups opened from word buttons in KOReader's dictionary now also show the line.
- New features for the README: the two settings and their menu labels (above), and the behaviour
  described in the tables above.
